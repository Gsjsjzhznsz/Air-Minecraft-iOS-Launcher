// MobileGlues - gl/transfer.cpp
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#include "transfer.h"
#include "buffer.h"
#include "log.h"
#include "mg.h"
#include "pixel.h"
#include "../egl/context.h"
#include "../gles/loader.h"
#include <cstring>
#include <vector>

#define DEBUG 0

// GL 3.0 enums that live in glext.h, which not every include path pulls in.
#ifndef GL_BGR_INTEGER
#define GL_BGR_INTEGER 0x8D9A
#endif
#ifndef GL_BGRA_INTEGER
#define GL_BGRA_INTEGER 0x8D9B
#endif

#define TR_WARN_ONCE(...)                                                                                              \
    do {                                                                                                               \
        static bool mg_tr_warned = false;                                                                              \
        if (!mg_tr_warned) {                                                                                           \
            mg_tr_warned = true;                                                                                       \
            LOG_W_FORCE(__VA_ARGS__)                                                                                   \
        }                                                                                                              \
    } while (0)

namespace {

// One scratch per thread: uploads can happen on any thread that holds a
// context, and nothing here takes a lock.
std::vector<uint8_t>& scratch() {
    static thread_local std::vector<uint8_t> buf;
    return buf;
}

// The scratch only ever grew: resize() to a smaller size keeps the capacity, so
// one 16384x8192 atlas pinned half a gigabyte on that thread for the life of the
// process even though every later upload was a few kilobytes. Handed back once
// the transfer is done and the peak was large.
constexpr size_t k_scratch_keep = 16u << 20; // 16 MiB
void scratch_release_if_large(size_t used) {
    if (scratch().capacity() <= k_scratch_keep) return;
    // Only when this transfer did not need the room. Releasing on every large
    // transfer would make a stream of them -- a resource-pack reload uploading
    // atlas after atlas -- pay a fresh allocate and free each time, which is the
    // one thing a scratch buffer exists to avoid. Handing it back matters for the
    // opposite shape: one huge upload followed by thousands of small ones.
    if (used * 4 > scratch().capacity()) return;
    std::vector<uint8_t>().swap(scratch());
}

// width * height * depth * channels without wrapping.
bool mg_checked_area(GLsizei width, GLsizei height, GLsizei depth, int channels, size_t* out) {
    if (width <= 0 || height <= 0 || depth <= 0 || channels <= 0) return false;
    // 1 TiB is far past any real texture, but it is not even representable when
    // size_t is 32 bits -- and `size_t(1) << 40` is not merely wrong there, it is
    // a hard error, because a shift wider than the type is undefined and a
    // constant expression may not be undefined. That broke the armeabi-v7a and x86
    // builds outright; only arm64 was being compiled locally. Where the cap does
    // not fit, SIZE_MAX is the real ceiling anyway.
    constexpr size_t kMax = sizeof(size_t) >= 8 ? static_cast<size_t>(1ULL << 40) : static_cast<size_t>(-1);
    size_t n = static_cast<size_t>(width);
    for (size_t f : {static_cast<size_t>(height), static_cast<size_t>(depth), static_cast<size_t>(channels)}) {
        if (f != 0 && n > kMax / f) return false;
        n *= f;
    }
    *out = n;
    return true;
}

// ---------------------------------------------------------------------------
// Decoders. Each reads one source pixel and writes RGBA (or RGB) bytes in
// memory order. The packed GL_UNSIGNED_INT_* types are defined as components
// of a host-endian integer -- non-REV packs the format's first component into
// the most significant bits, REV into the least -- so decoding through an
// integer load is endian-correct by construction. Only GL_UNSIGNED_BYTE
// addresses memory directly, and its component order *is* memory order.
// ---------------------------------------------------------------------------

void dec_bgra_u8(const uint8_t* s, uint8_t* d) {
    d[0] = s[2];
    d[1] = s[1];
    d[2] = s[0];
    d[3] = s[3];
}

void dec_bgr_u8(const uint8_t* s, uint8_t* d) {
    d[0] = s[2];
    d[1] = s[1];
    d[2] = s[0];
}

void dec_bgra_8888(const uint8_t* s, uint8_t* d) { // B=31..24 G=23..16 R=15..8 A=7..0
    uint32_t v;
    memcpy(&v, s, 4);
    d[0] = (v >> 8) & 0xff;
    d[1] = (v >> 16) & 0xff;
    d[2] = (v >> 24) & 0xff;
    d[3] = v & 0xff;
}

void dec_bgra_8888_rev(const uint8_t* s, uint8_t* d) { // B=7..0 G=15..8 R=23..16 A=31..24
    uint32_t v;
    memcpy(&v, s, 4);
    d[0] = (v >> 16) & 0xff;
    d[1] = (v >> 8) & 0xff;
    d[2] = v & 0xff;
    d[3] = (v >> 24) & 0xff;
}

void dec_rgba_8888(const uint8_t* s, uint8_t* d) { // R=31..24 G=23..16 B=15..8 A=7..0
    uint32_t v;
    memcpy(&v, s, 4);
    d[0] = (v >> 24) & 0xff;
    d[1] = (v >> 16) & 0xff;
    d[2] = (v >> 8) & 0xff;
    d[3] = v & 0xff;
}

void dec_rgba_8888_rev(const uint8_t* s, uint8_t* d) { // R=7..0 ... A=31..24
    uint32_t v;
    memcpy(&v, s, 4);
    d[0] = v & 0xff;
    d[1] = (v >> 8) & 0xff;
    d[2] = (v >> 16) & 0xff;
    d[3] = (v >> 24) & 0xff;
}

void dec_bgra_1555_rev(const uint8_t* s, uint8_t* d) { // B=4..0 G=9..5 R=14..10 A=15
    uint16_t v;
    memcpy(&v, s, 2);
    const uint8_t b = v & 0x1f, g = (v >> 5) & 0x1f, r = (v >> 10) & 0x1f;
    d[0] = (r << 3) | (r >> 2);
    d[1] = (g << 3) | (g >> 2);
    d[2] = (b << 3) | (b >> 2);
    d[3] = (v & 0x8000) ? 255 : 0;
}

void dec_bgra_4444_rev(const uint8_t* s, uint8_t* d) { // B=3..0 G=7..4 R=11..8 A=15..12
    uint16_t v;
    memcpy(&v, s, 2);
    d[0] = ((v >> 8) & 0x0f) * 17;
    d[1] = ((v >> 4) & 0x0f) * 17;
    d[2] = (v & 0x0f) * 17;
    d[3] = ((v >> 12) & 0x0f) * 17;
}

// Straight copies. GLES accepts these pairs already, so they are only ever
// selected when the destination format needs a different number of channels than
// the source carries -- see the note on want_format below.
void dec_rgb_u8(const uint8_t* s, uint8_t* d) {
    d[0] = s[0];
    d[1] = s[1];
    d[2] = s[2];
}

void dec_rgba_u8(const uint8_t* s, uint8_t* d) {
    memcpy(d, s, 4);
}

struct upload_rule_t {
    GLenum format, type;
    void (*dec)(const uint8_t*, uint8_t*);
    int src_size;
    GLenum out_format;
    int channels; // how many 8-bit components dec writes
    bool adapt_only; // selected only to change the channel count, never on its own
};

const upload_rule_t k_upload_rules[] = {
    {GL_BGRA, GL_UNSIGNED_BYTE, dec_bgra_u8, 4, GL_RGBA, 4, false},
    {GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, dec_bgra_8888_rev, 4, GL_RGBA, 4, false},
    {GL_BGRA, GL_UNSIGNED_INT_8_8_8_8, dec_bgra_8888, 4, GL_RGBA, 4, false},
    {GL_BGRA, GL_UNSIGNED_SHORT_1_5_5_5_REV, dec_bgra_1555_rev, 2, GL_RGBA, 4, false},
    {GL_BGRA, GL_UNSIGNED_SHORT_4_4_4_4_REV, dec_bgra_4444_rev, 2, GL_RGBA, 4, false},
    {GL_BGR, GL_UNSIGNED_BYTE, dec_bgr_u8, 3, GL_RGB, 3, false},
    // Not reversed, but the packed 8888 types themselves do not exist in GLES.
    {GL_RGBA, GL_UNSIGNED_INT_8_8_8_8_REV, dec_rgba_8888_rev, 4, GL_RGBA, 4, false},
    {GL_RGBA, GL_UNSIGNED_INT_8_8_8_8, dec_rgba_8888, 4, GL_RGBA, 4, false},
    {GL_RGB, GL_UNSIGNED_BYTE, dec_rgb_u8, 3, GL_RGB, 3, true},
    {GL_RGBA, GL_UNSIGNED_BYTE, dec_rgba_u8, 4, GL_RGBA, 4, true},
};

int channels_of(GLenum format) {
    switch (format) {
    case GL_RGBA:
    case GL_BGRA:
        return 4;
    case GL_RGB:
    case GL_BGR:
        return 3;
    default:
        return 0; // not a format this file adapts between
    }
}

const upload_rule_t* find_upload_rule(GLenum format, GLenum type, GLenum want_format) {
    const upload_rule_t* adapt = nullptr;
    for (const auto& r : k_upload_rules) {
        if (r.format != format || r.type != type) continue;
        if (!r.adapt_only) return &r;
        adapt = &r;
    }
    // An adapt-only rule earns its keep only when the caller has told us the
    // destination wants a different channel count than the source carries.
    if (adapt && want_format != 0) {
        const int want = channels_of(want_format);
        if (want != 0 && want != adapt->channels) return adapt;
    }
    return nullptr;
}

bool is_reversed_family(GLenum format, GLenum type) {
    return format == GL_BGRA || format == GL_BGR || format == GL_BGRA_INTEGER || format == GL_BGR_INTEGER ||
           type == GL_UNSIGNED_INT_8_8_8_8 || type == GL_UNSIGNED_INT_8_8_8_8_REV;
}

// The context the mirror in gl/pixel.cpp was last confirmed against, or ~0 for
// none -- which context 0, the fallback for a context this layer never saw
// created, is a legitimate value for.
//
// The mirror keys itself on gl_state, a pointer into the MGContext record, and a
// destroyed context's record can be handed back to the next one at the same
// address. The id never is (egl/context.h), so requiring both closes the one hole
// the pointer alone leaves.
thread_local unsigned long long g_unpack_ctx = ~0ull;

// The six unpack parameters an upload has to know, without asking the driver for
// them every time. See mg_unpack_state() in gl/pixel.h for why the mirror can be
// trusted and when it cannot.
mg_unpack_state_t current_unpack_state() {
    const unsigned long long ctx = g_current_ctx ? g_current_ctx->id : 0;
    mg_unpack_state_t st;
    if (ctx == g_unpack_ctx && mg_unpack_state(&st)) return st;

    GLES.glGetIntegerv(GL_UNPACK_ALIGNMENT, &st.alignment);
    GLES.glGetIntegerv(GL_UNPACK_ROW_LENGTH, &st.row_length);
    GLES.glGetIntegerv(GL_UNPACK_SKIP_ROWS, &st.skip_rows);
    GLES.glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &st.skip_pixels);
    GLES.glGetIntegerv(GL_UNPACK_IMAGE_HEIGHT, &st.image_height);
    GLES.glGetIntegerv(GL_UNPACK_SKIP_IMAGES, &st.skip_images);
    mg_unpack_state_adopt(st);
    g_unpack_ctx = ctx;
    return st;
}

} // namespace

bool mg_upload_has_data(const void* pixels) {
    if (pixels != nullptr) return true;
    // A null pointer still carries bytes when an unpack buffer is bound: there it
    // is an offset into that buffer, not "no data".
    //
    // Answered from the tracked binding rather than the driver, which was a query
    // per upload on a predicate every glTexImage* asks. Where the two can disagree
    // is written out on the constructor's copy of this below.
    return mg_driver_bound_buffer(GL_PIXEL_UNPACK_BUFFER) != 0;
}

mg_upload_fix_t::mg_upload_fix_t(GLsizei width, GLsizei height, GLsizei depth, GLenum format_in, GLenum type_in,
                                 const void* pixels_in, GLenum want_format, bool three_d)
    : format(format_in), type(type_in), pixels(pixels_in) {
    has_data_ = mg_upload_has_data(pixels_in);

    const upload_rule_t* rule = find_upload_rule(format_in, type_in, want_format);
    if (!rule) {
        if (is_reversed_family(format_in, type_in)) {
            TR_WARN_ONCE("pixel transfer: unhandled combination %s + %s, the driver will reject this upload",
                         glEnumToString(format_in), glEnumToString(type_in));
        }
        return;
    }

    // The emitted stream carries as many channels as the destination asked for,
    // when it asked for something this file can adapt to. Anything else keeps the
    // source's own channel count -- the enum must describe the bytes, so it is
    // never allowed to run ahead of them.
    int out_channels = rule->channels;
    if (want_format != 0) {
        const int want = channels_of(want_format);
        if (want != 0) out_channels = want;
    }
    format = out_channels == 4 ? GL_RGBA : GL_RGB;
    type = GL_UNSIGNED_BYTE;

    // With an unpack PBO bound, pixels is an offset -- and offset 0 is real
    // data, so nullptr only means "no data" when no PBO is bound.
    //
    // The tracked binding, already mapped to the driver's own name so the
    // destructor can hand it straight back. Nothing borrows this target without
    // putting it back, and it is not vertex array state, so the depth-clear
    // triangle that desynchronises the array bindings cannot reach it. Two places
    // do leave it behind: glDeleteBuffers does not clear the binding slots, so
    // deleting a still-bound unpack buffer resets the driver to 0 while this keeps
    // reporting the dead name, and the glTexBuffer emulation in gl/buffer.cpp
    // leaves the driver on 0 when it gives up on a buffer too small for one texel.
    //
    // Both err the same way, and it is the survivable one: the map and the copy
    // fallback below fail against a target with nothing bound, so the upload is
    // dropped with a warning. Believing there is no PBO when there is one would
    // instead read client memory from an offset.
    prev_pbo_ = static_cast<GLint>(mg_driver_bound_buffer(GL_PIXEL_UNPACK_BUFFER));
    has_data_ = !(pixels_in == nullptr && prev_pbo_ == 0);
    if (!has_data_) return; // allocation only: the enums were all that needed fixing
    if (width <= 0 || height <= 0 || depth <= 0) return;

    // Mirrored in gl/pixel.cpp rather than asked of the driver, which was six
    // queries on every converted upload -- and Minecraft converts every texture it
    // has. The values are still the driver's, so the destructor restoring them is
    // still a restore and not an overwrite.
    const mg_unpack_state_t unpack = current_unpack_state();
    prev_align_ = unpack.alignment;
    prev_row_len_ = unpack.row_length;
    prev_skip_rows_ = unpack.skip_rows;
    prev_skip_px_ = unpack.skip_pixels;
    prev_img_h_ = unpack.image_height;
    prev_skip_img_ = unpack.skip_images;

    // IMAGE_HEIGHT and SKIP_IMAGES only describe a three-dimensional transfer, so a
    // 2D upload must read past them however the application left them set -- it
    // cannot be told apart from a one-slice 3D upload by its depth alone. The saved
    // copies stay as they are: they are what the destructor gives back.
    const GLint eff_img_h = three_d ? prev_img_h_ : 0;
    const GLint eff_skip_img = three_d ? prev_skip_img_ : 0;

    const size_t ss = static_cast<size_t>(rule->src_size);
    const size_t row_px = prev_row_len_ > 0 ? static_cast<size_t>(prev_row_len_) : static_cast<size_t>(width);
    const size_t row_stride = widthalign(row_px * ss, static_cast<size_t>(prev_align_));
    const size_t img_rows = eff_img_h > 0 ? static_cast<size_t>(eff_img_h) : static_cast<size_t>(height);
    const size_t img_stride = row_stride * img_rows;
    const size_t start = static_cast<size_t>(eff_skip_img) * img_stride +
                         static_cast<size_t>(prev_skip_rows_) * row_stride + static_cast<size_t>(prev_skip_px_) * ss;
    const size_t span = start + static_cast<size_t>(depth - 1) * img_stride +
                        static_cast<size_t>(height - 1) * row_stride + static_cast<size_t>(width) * ss;

    const uint8_t* src = nullptr;
    void* mapped = nullptr;
    if (prev_pbo_ != 0) {
        const GLintptr pbo_off = static_cast<GLintptr>(reinterpret_cast<uintptr_t>(pixels_in));
        mapped = GLES.glMapBufferRange(GL_PIXEL_UNPACK_BUFFER, pbo_off, static_cast<GLsizeiptr>(span), GL_MAP_READ_BIT);

        if (!mapped) {
            // Read it through a copy instead of giving up.
            //
            // A mobile driver routinely refuses a READ mapping of a buffer whose
            // usage hint is one of the _DRAW ones -- and _DRAW is the natural hint
            // for a buffer whose whole purpose is uploading. What those drivers do
            // serve is a copy into a buffer asked for with _READ, which is a buffer
            // we can make ourselves. Dropping the upload here instead is what left
            // Xaero's map tiles, which arrive exactly this way, as black texture.
            while (GLES.glGetError() != GL_NO_ERROR) {
            } // the failed map left an error behind
            if (GLES.glCopyBufferSubData != nullptr && GLES.glGenBuffers != nullptr &&
                GLES.glDeleteBuffers != nullptr && GLES.glBufferData != nullptr) {
                GLES.glGetIntegerv(GL_COPY_WRITE_BUFFER_BINDING, &prev_copy_write_);
                GLES.glGenBuffers(1, &copy_scratch_);
                GLES.glBindBuffer(GL_COPY_WRITE_BUFFER, copy_scratch_);
                GLES.glBufferData(GL_COPY_WRITE_BUFFER, static_cast<GLsizeiptr>(span), nullptr, GL_STREAM_READ);
                GLES.glCopyBufferSubData(GL_PIXEL_UNPACK_BUFFER, GL_COPY_WRITE_BUFFER, pbo_off, 0,
                                         static_cast<GLsizeiptr>(span));
                mapped = GLES.glMapBufferRange(GL_COPY_WRITE_BUFFER, 0, static_cast<GLsizeiptr>(span), GL_MAP_READ_BIT);
                if (!mapped) {
                    GLES.glBindBuffer(GL_COPY_WRITE_BUFFER, static_cast<GLuint>(prev_copy_write_));
                    GLES.glDeleteBuffers(1, &copy_scratch_);
                    copy_scratch_ = 0;
                }
            }
        }

        if (!mapped) {
            // Wrong colours are worse than a missing upload: dropping keeps the
            // failure visible instead of shipping swapped channels.
            TR_WARN_ONCE("pixel transfer: unpack buffer %d is readable neither by mapping nor by copy, "
                         "upload dropped",
                         prev_pbo_);
            GLES.glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
            pbo_unbound_ = true;
            pixels = nullptr;
            dropped_ = true;
            return;
        }
        src = static_cast<const uint8_t*>(mapped);
    } else {
        src = static_cast<const uint8_t*>(pixels_in);
    }

    // Checked, not just multiplied. Desktop GL answers GL_INVALID_VALUE for
    // dimensions past GL_MAX_TEXTURE_SIZE without touching client memory; this
    // conversion runs before the driver ever sees the call, so an out-of-range
    // request used to reach resize() first -- either throwing bad_alloc or
    // length_error out of a constructor nobody catches, or, once the product
    // wrapped, succeeding small and letting the decode loop run off the end.
    size_t need = 0;
    if (!mg_checked_area(width, height, depth, out_channels, &need)) {
        TR_WARN_ONCE("pixel transfer: %dx%dx%d x %d channels does not fit in memory, dropped", width, height, depth,
                     out_channels);
        mg_set_gl_error(GL_INVALID_VALUE);
        // Same unwind as the unmappable-PBO drop above. Returning straight out
        // left the unpack buffer mapped and bound, because the unmap below is
        // never reached and the destructor only knows about pbo_unbound_.
        release_source(mapped);
        pixels = nullptr;
        dropped_ = true;
        return;
    }
    scratch().resize(need);
    converted_bytes_ = need;
    uint8_t* out = scratch().data();

    // GL_UNPACK_SWAP_BYTES reverses the bytes of every component -- of the whole
    // unit, for a packed type, which is what gl_sizeof answers for one. It has no
    // meaning for a single byte, and mg_unpack_swaps_bytes says so. Honoured here
    // because here is the only place this layer looks at the bytes at all; a pair
    // that needs no repack still goes to the driver untouched and unswapped, and
    // the shadow in gl_state_s records that.
    const size_t comp = static_cast<size_t>(gl_sizeof(type_in));
    const bool swap_in = mg_unpack_swaps_bytes(type_in) && comp > 1 && ss % comp == 0 && ss <= 16;
    if (mg_unpack_swaps_bytes(type_in) && !swap_in) {
        TR_WARN_ONCE("pixel transfer: GL_UNPACK_SWAP_BYTES cannot be applied to %s + %s, uploading unswapped",
                     glEnumToString(format_in), glEnumToString(type_in));
    }
    uint8_t swapped[16];

    for (GLsizei z = 0; z < depth; ++z) {
        for (GLsizei row = 0; row < height; ++row) {
            const uint8_t* s = src + start + static_cast<size_t>(z) * img_stride + static_cast<size_t>(row) * row_stride;
            for (GLsizei col = 0; col < width; ++col) {
                uint8_t px[4] = {0, 0, 0, 255};
                if (swap_in) {
                    for (size_t b = 0; b < ss; b += comp) {
                        for (size_t k = 0; k < comp; ++k) swapped[b + k] = s[b + comp - 1 - k];
                    }
                    rule->dec(swapped, px);
                } else {
                    rule->dec(s, px);
                }
                // GL 4.6 sec. 8.4.4.4: a source without an alpha channel reads as
                // 1.0, and a destination without one discards the source's.
                for (int c = 0; c < out_channels; ++c) out[c] = px[c];
                s += ss;
                out += out_channels;
            }
        }
    }

    release_source(mapped);

    // The converted stream is tight and the skips are already applied.
    GLES.glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    GLES.glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
    GLES.glPixelStorei(GL_UNPACK_SKIP_ROWS, 0);
    GLES.glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0);
    GLES.glPixelStorei(GL_UNPACK_IMAGE_HEIGHT, 0);
    GLES.glPixelStorei(GL_UNPACK_SKIP_IMAGES, 0);
    converted_ = true;
    pixels = scratch().data();
}

// Let go of whatever the source was read through -- the unpack buffer itself, or
// the scratch it had to be copied into first.
void mg_upload_fix_t::release_source(void* mapped) {
    if (!mapped) return;
    if (copy_scratch_ != 0) {
        GLES.glUnmapBuffer(GL_COPY_WRITE_BUFFER);
        GLES.glBindBuffer(GL_COPY_WRITE_BUFFER, static_cast<GLuint>(prev_copy_write_));
        GLES.glDeleteBuffers(1, &copy_scratch_);
        copy_scratch_ = 0;
    } else {
        GLES.glUnmapBuffer(GL_PIXEL_UNPACK_BUFFER);
    }
    GLES.glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
    pbo_unbound_ = true;
}

mg_upload_fix_t::~mg_upload_fix_t() {
    if (converted_) {
        GLES.glPixelStorei(GL_UNPACK_ALIGNMENT, prev_align_);
        GLES.glPixelStorei(GL_UNPACK_ROW_LENGTH, prev_row_len_);
        GLES.glPixelStorei(GL_UNPACK_SKIP_ROWS, prev_skip_rows_);
        GLES.glPixelStorei(GL_UNPACK_SKIP_PIXELS, prev_skip_px_);
        GLES.glPixelStorei(GL_UNPACK_IMAGE_HEIGHT, prev_img_h_);
        GLES.glPixelStorei(GL_UNPACK_SKIP_IMAGES, prev_skip_img_);
    }
    if (pbo_unbound_) {
        GLES.glBindBuffer(GL_PIXEL_UNPACK_BUFFER, static_cast<GLuint>(prev_pbo_));
    }
    // The driver has consumed pixels by now, so the scratch that fed it can go
    // back if this transfer was the one that made it enormous.
    if (converted_) scratch_release_if_large(converted_bytes_);
}

// ---------------------------------------------------------------------------
// Readback
// ---------------------------------------------------------------------------

namespace {

// Encoders: RGBA memory-order bytes in, one destination pixel out.
void enc_bgra_u8(const uint8_t* s, uint8_t* d) {
    d[0] = s[2];
    d[1] = s[1];
    d[2] = s[0];
    d[3] = s[3];
}

// Channel subsets of the RGBA the driver hands back. GLES only guarantees a
// GL_RGBA/GL_UNSIGNED_BYTE readback, so an application asking for plain GL_RGB or
// GL_RED -- the ordinary way to dump an atlas or a single-channel map -- used to
// be handed straight to the driver, which refuses it and leaves the destination
// exactly as it was.
void enc_rgb_u8(const uint8_t* s, uint8_t* d) {
    d[0] = s[0];
    d[1] = s[1];
    d[2] = s[2];
}

void enc_rg_u8(const uint8_t* s, uint8_t* d) {
    d[0] = s[0];
    d[1] = s[1];
}

void enc_r_u8(const uint8_t* s, uint8_t* d) {
    d[0] = s[0];
}

void enc_bgr_u8(const uint8_t* s, uint8_t* d) {
    d[0] = s[2];
    d[1] = s[1];
    d[2] = s[0];
}

void enc_bgra_8888(const uint8_t* s, uint8_t* d) {
    const uint32_t v = (static_cast<uint32_t>(s[2]) << 24) | (static_cast<uint32_t>(s[1]) << 16) |
                       (static_cast<uint32_t>(s[0]) << 8) | s[3];
    memcpy(d, &v, 4);
}

void enc_bgra_8888_rev(const uint8_t* s, uint8_t* d) {
    const uint32_t v = s[2] | (static_cast<uint32_t>(s[1]) << 8) | (static_cast<uint32_t>(s[0]) << 16) |
                       (static_cast<uint32_t>(s[3]) << 24);
    memcpy(d, &v, 4);
}

void enc_rgba_8888(const uint8_t* s, uint8_t* d) {
    const uint32_t v = (static_cast<uint32_t>(s[0]) << 24) | (static_cast<uint32_t>(s[1]) << 16) |
                       (static_cast<uint32_t>(s[2]) << 8) | s[3];
    memcpy(d, &v, 4);
}

void enc_rgba_8888_rev(const uint8_t* s, uint8_t* d) {
    const uint32_t v = s[0] | (static_cast<uint32_t>(s[1]) << 8) | (static_cast<uint32_t>(s[2]) << 16) |
                       (static_cast<uint32_t>(s[3]) << 24);
    memcpy(d, &v, 4);
}

// The inverses of dec_bgra_1555_rev / dec_bgra_4444_rev, bit for bit. Narrowing
// truncates, which is exactly what the decoders' replication expands back: 5-bit
// 31 decodes to 255 and encodes to 31 again, 4-bit 15 to 255 and back. An 8-bit
// value the decoder could not have produced lands on the level below it -- at five
// bits 130 encodes to 16 and reads back as 132, at four bits 200 encodes to 12 and
// reads back as 204 -- which is the precision of the format the application asked
// for, not a loss this file introduces. Alpha is one bit in 1555: it rounds at 128,
// so the decoder's own 0 and 255 come back unchanged.
void enc_bgra_1555_rev(const uint8_t* s, uint8_t* d) { // B=4..0 G=9..5 R=14..10 A=15
    const uint16_t v = static_cast<uint16_t>((s[2] >> 3) | ((s[1] >> 3) << 5) | ((s[0] >> 3) << 10) |
                                             (s[3] >= 128 ? 0x8000 : 0));
    memcpy(d, &v, 2);
}

void enc_bgra_4444_rev(const uint8_t* s, uint8_t* d) { // B=3..0 G=7..4 R=11..8 A=15..12
    const uint16_t v = static_cast<uint16_t>((s[2] >> 4) | ((s[1] >> 4) << 4) | ((s[0] >> 4) << 8) |
                                             ((s[3] >> 4) << 12));
    memcpy(d, &v, 2);
}

struct readback_rule_t {
    GLenum format, type;
    void (*enc)(const uint8_t*, uint8_t*);
    int dst_size;
};

// Whether the driver took a call, asked of the driver directly: this layer's own
// glGetError always answers GL_NO_ERROR, so it cannot report anything. gl/multidraw.cpp
// probes the same way for the same reason.
GLenum mg_tr_check() {
    return GLES.glGetError();
}

// Empty the queue first, or an error the application left pending would be read as
// our own failure. Nothing observable is lost -- those entries could never reach the
// application anyway.
void mg_tr_drain() {
    for (int i = 0; i < 16 && GLES.glGetError() != GL_NO_ERROR; ++i) {
    }
}

const readback_rule_t k_readback_rules[] = {
    {GL_BGRA, GL_UNSIGNED_BYTE, enc_bgra_u8, 4},
    {GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, enc_bgra_8888_rev, 4},
    {GL_BGRA, GL_UNSIGNED_INT_8_8_8_8, enc_bgra_8888, 4},
    {GL_BGRA, GL_UNSIGNED_SHORT_1_5_5_5_REV, enc_bgra_1555_rev, 2},
    {GL_BGRA, GL_UNSIGNED_SHORT_4_4_4_4_REV, enc_bgra_4444_rev, 2},
    {GL_BGR, GL_UNSIGNED_BYTE, enc_bgr_u8, 3},
    {GL_RGB, GL_UNSIGNED_BYTE, enc_rgb_u8, 3},
    {GL_RG, GL_UNSIGNED_BYTE, enc_rg_u8, 2},
    {GL_RED, GL_UNSIGNED_BYTE, enc_r_u8, 1},
    {GL_RGBA, GL_UNSIGNED_INT_8_8_8_8_REV, enc_rgba_8888_rev, 4},
    {GL_RGBA, GL_UNSIGNED_INT_8_8_8_8, enc_rgba_8888, 4},
};

} // namespace

bool mg_readback_pair_supported(GLenum format, GLenum type) {
    // Anything this file re-encodes from an RGBA read is deliverable whatever the
    // backend thinks of the pair itself.
    for (const auto& r : k_readback_rules) {
        if (r.format == format && r.type == type) return true;
    }
    // GLES guarantees exactly two pairs for a colour read (ES 3.2 sec. 16.1.2):
    // this one...
    if (format == GL_RGBA && type == GL_UNSIGNED_BYTE) return true;
    // ...and one the implementation names. Asked every time rather than cached:
    // it is a property of the bound read framebuffer's attachment, so a read from
    // a float FBO answers differently than one from the window.
    GLint impl_format = 0, impl_type = 0;
    GLES.glGetIntegerv(GL_IMPLEMENTATION_COLOR_READ_FORMAT, &impl_format);
    GLES.glGetIntegerv(GL_IMPLEMENTATION_COLOR_READ_TYPE, &impl_type);
    return static_cast<GLenum>(impl_format) == format && static_cast<GLenum>(impl_type) == type;
}

bool mg_transfer_readback(GLint x, GLint y, GLsizei width, GLsizei height, GLenum format, GLenum type, void* pixels) {
    const readback_rule_t* rule = nullptr;
    for (const auto& r : k_readback_rules) {
        if (r.format == format && r.type == type) {
            rule = &r;
            break;
        }
    }
    if (!rule) return false;
    if (width <= 0 || height <= 0) return true; // ours, and nothing to do

    GLint pbo = 0, align = 4, row_len = 0, skip_rows = 0, skip_px = 0;
    GLES.glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &pbo);
    GLES.glGetIntegerv(GL_PACK_ALIGNMENT, &align);
    GLES.glGetIntegerv(GL_PACK_ROW_LENGTH, &row_len);
    GLES.glGetIntegerv(GL_PACK_SKIP_ROWS, &skip_rows);
    GLES.glGetIntegerv(GL_PACK_SKIP_PIXELS, &skip_px);

    // Read tight RGBA into scratch, with the pack state and PBO out of the way.
    scratch().resize(static_cast<size_t>(width) * static_cast<size_t>(height) * 4);
    if (pbo != 0) GLES.glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
    GLES.glPixelStorei(GL_PACK_ALIGNMENT, 1);
    GLES.glPixelStorei(GL_PACK_ROW_LENGTH, 0);
    GLES.glPixelStorei(GL_PACK_SKIP_ROWS, 0);
    GLES.glPixelStorei(GL_PACK_SKIP_PIXELS, 0);
    mg_tr_drain();
    GLES.glReadPixels(x, y, width, height, GL_RGBA, GL_UNSIGNED_BYTE, scratch().data());
    const GLenum read_err = mg_tr_check();
    GLES.glPixelStorei(GL_PACK_ALIGNMENT, align);
    GLES.glPixelStorei(GL_PACK_ROW_LENGTH, row_len);
    GLES.glPixelStorei(GL_PACK_SKIP_ROWS, skip_rows);
    GLES.glPixelStorei(GL_PACK_SKIP_PIXELS, skip_px);
    if (read_err != GL_NO_ERROR) {
        // Not every read buffer hands itself back as RGBA8. The scratch still holds
        // the previous transfer's bytes, and encoding those would give the
        // application a whole frame of plausible stale pixels reported as a
        // successful read. Hand the call back to the driver instead: the pair may be
        // that buffer's own implementation-defined read format, and if it is not, the
        // driver rejects it and leaves the destination as the application left it.
        TR_WARN_ONCE("pixel transfer: RGBA readback failed with 0x%04x, leaving %s + %s to the driver", read_err,
                     glEnumToString(format), glEnumToString(type));
        if (pbo != 0) GLES.glBindBuffer(GL_PIXEL_PACK_BUFFER, static_cast<GLuint>(pbo));
        return false;
    }

    // Encode into the destination the application described with its pack state.
    const size_t ds = static_cast<size_t>(rule->dst_size);
    const size_t row_px = row_len > 0 ? static_cast<size_t>(row_len) : static_cast<size_t>(width);
    const size_t dst_stride = widthalign(row_px * ds, static_cast<size_t>(align));
    const size_t start = static_cast<size_t>(skip_rows) * dst_stride + static_cast<size_t>(skip_px) * ds;
    const size_t span = start + static_cast<size_t>(height - 1) * dst_stride + static_cast<size_t>(width) * ds;

    const GLintptr pbo_offset = static_cast<GLintptr>(reinterpret_cast<uintptr_t>(pixels));
    const size_t row_bytes = static_cast<size_t>(width) * ds;
    uint8_t* dst = nullptr;
    void* mapped = nullptr;
    bool via_subdata = false;
    std::vector<uint8_t> row_buf;
    if (pbo != 0) {
        GLES.glBindBuffer(GL_PIXEL_PACK_BUFFER, static_cast<GLuint>(pbo));
        mapped = GLES.glMapBufferRange(GL_PIXEL_PACK_BUFFER, pbo_offset, static_cast<GLsizeiptr>(span),
                                       GL_MAP_WRITE_BIT);
        if (!mapped) {
            // A buffer glBufferStorage made without GL_MAP_WRITE_BIT can never be
            // mapped that way, and dropping the readback there left the application
            // reading whatever its buffer already held. glBufferSubData still reaches
            // it, a row at a time so the padding between rows keeps its contents.
            TR_WARN_ONCE("pixel transfer: pack buffer %d is not mappable for writing, using glBufferSubData", pbo);
            row_buf.resize(row_bytes);
            via_subdata = true;
        } else {
            dst = static_cast<uint8_t*>(mapped);
        }
    } else {
        if (pixels == nullptr) return true;
        dst = static_cast<uint8_t*>(pixels);
    }

    const uint8_t* src = scratch().data();
    if (via_subdata) mg_tr_drain();
    // GL_PACK_SWAP_BYTES, the mirror of the unpack side: reverse the bytes of each
    // component of the pixel this encoder just wrote. Of the pairs handled here
    // only the packed ones are wider than a byte, so most reads skip it entirely.
    const size_t dcomp = static_cast<size_t>(gl_sizeof(type));
    const bool swap_out = mg_pack_swaps_bytes(type) && dcomp > 1 && ds % dcomp == 0;
    for (GLsizei row = 0; row < height; ++row) {
        const size_t row_off = start + static_cast<size_t>(row) * dst_stride;
        uint8_t* d = via_subdata ? row_buf.data() : dst + row_off;
        for (GLsizei col = 0; col < width; ++col) {
            rule->enc(src, d);
            if (swap_out) {
                for (size_t b = 0; b < ds; b += dcomp) {
                    for (size_t k = 0; k < dcomp / 2; ++k) {
                        const uint8_t t = d[b + k];
                        d[b + k] = d[b + dcomp - 1 - k];
                        d[b + dcomp - 1 - k] = t;
                    }
                }
            }
            src += 4;
            d += ds;
        }
        if (via_subdata) {
            GLES.glBufferSubData(GL_PIXEL_PACK_BUFFER, pbo_offset + static_cast<GLintptr>(row_off),
                                 static_cast<GLsizeiptr>(row_bytes), row_buf.data());
            if (row == 0) {
                // Immutable, unmappable and not dynamic either: there is no way into
                // this buffer at all. Say so once and stop, rather than have the
                // driver reject one call per row.
                const GLenum sub_err = mg_tr_check();
                if (sub_err != GL_NO_ERROR) {
                    TR_WARN_ONCE("pixel transfer: pack buffer %d takes neither a write map nor glBufferSubData "
                                 "(0x%04x), readback dropped",
                                 pbo, sub_err);
                    return true;
                }
            }
        }
    }

    if (mapped) GLES.glUnmapBuffer(GL_PIXEL_PACK_BUFFER);
    return true;
}
