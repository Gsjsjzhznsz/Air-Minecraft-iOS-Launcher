// MobileGlues - gl/transfer.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#ifndef MOBILEGLUES_TRANSFER_H
#define MOBILEGLUES_TRANSFER_H

#include "../includes.h"
#include <GL/gl.h>

// ---------------------------------------------------------------------------
// Pixel-transfer formats GLES does not have
//
// Desktop GL accepts GL_BGRA / GL_BGR as *client* formats: the driver reorders
// the data during the transfer and the texture stores ordinary RGBA. GLES has
// no reversed client formats and none of the packed GL_UNSIGNED_INT_8_8_8_8*
// types -- the pair Minecraft uploads every texture with.
//
// GL_EXT_texture_format_BGRA8888 is not a substitute. It makes BGRA an
// *internalformat*, which forbids exactly the combination desktop applications
// use (BGRA client data into a GL_RGBA8 texture), still has no packed types,
// and what it may render to or mipmap differs per driver.
//
// So the reordering desktop GL does in the driver happens here on the CPU: the
// client data is converted at the transfer boundary, honouring the full
// unpack state including a bound unpack PBO, and GLES only ever sees formats
// it has. This replaces the previous approach -- renaming the enum and
// patching the damage with a texture swizzle -- which mends sampling only, and
// only until the application mixes upload formats on one texture, renders
// into it, or sets a swizzle of its own.
// ---------------------------------------------------------------------------

#ifdef __cplusplus

// Rewrites one upload's (format, type, pixels) into a form GLES accepts.
//
//   mg_upload_fix_t fix(width, height, depth, format, type, pixels);
//   GLES.glTexSubImage2D(target, level, x, y, width, height,
//                        fix.format, fix.type, fix.pixels);
//
// For combinations GLES understands it does nothing at all. When it converts,
// the emitted stream is tightly packed, so the unpack parameters already
// applied on the way in are zeroed for the driver call; the destructor
// restores every piece of state it touched, including the unpack PBO binding.
struct mg_upload_fix_t {
    GLenum format;
    GLenum type;
    const void* pixels;

    // True when the conversion could not be performed and the caller must not
    // issue the transfer at all. Only glTexImage* may treat a null `pixels` as
    // "allocate without data"; for glTexSubImage* a null with no unpack buffer
    // bound is a client-memory read from address zero, so those callers have to
    // ask rather than infer.
    bool dropped() const { return dropped_; }

    // True when the call actually carries pixels -- a client pointer, or any
    // offset with an unpack buffer bound. An allocation-only glTexImage has no
    // bytes for the enums to describe, and is the only case where they may be
    // rewritten freely.
    bool has_data() const { return has_data_; }

    // want_format, when non-zero, is the client format the destination is going
    // to be labelled with. The conversion emits that many channels, so the enum
    // handed to the driver always describes the bytes behind it. Pass 0 (the
    // default) to keep the source's own channel count.
    //
    // three_d says whether this is a TexImage3D-style transfer. GL_UNPACK_IMAGE_HEIGHT
    // and GL_UNPACK_SKIP_IMAGES are three-dimensional unpack state (GL 4.6 sec. 8.4.4.1)
    // and must not be applied to a 2D upload: a 2D call passes depth=1, which is
    // indistinguishable from a one-slice 3D upload, so a SKIP_IMAGES left set by an
    // earlier 3D upload would displace the 2D source pointer. The default is true only
    // because that is what the callers got before the parameter existed; every 2D call
    // site should pass false.
    mg_upload_fix_t(GLsizei width, GLsizei height, GLsizei depth, GLenum format_in, GLenum type_in,
                    const void* pixels_in, GLenum want_format = 0, bool three_d = true);
    ~mg_upload_fix_t();

    mg_upload_fix_t(const mg_upload_fix_t&) = delete;
    mg_upload_fix_t& operator=(const mg_upload_fix_t&) = delete;

  private:
    bool dropped_ = false;
    size_t converted_bytes_ = 0; // what this transfer actually needed, for the scratch policy
    bool has_data_ = false;
    bool converted_ = false;
    bool pbo_unbound_ = false;
    GLint prev_pbo_ = 0;
    // A buffer of our own that the unpack PBO is copied into when the driver will
    // not let us map the PBO itself for reading. Zero when the direct map worked.
    GLuint copy_scratch_ = 0;
    GLint prev_copy_write_ = 0;

    void release_source(void* mapped);
    GLint prev_align_ = 4, prev_row_len_ = 0, prev_skip_rows_ = 0, prev_skip_px_ = 0;
    GLint prev_img_h_ = 0, prev_skip_img_ = 0;
};

// The same predicate mg_upload_fix_t::has_data() answers, asked before the
// conversion exists. internal_convert() in gl/texture.cpp has to know whether a
// call carries bytes -- an allocation's `type` describes nothing, so nothing may
// be derived from it -- but it runs first, because the conversion needs the
// destination format it produces. Both go through here so the two can never
// disagree about the same call.
bool mg_upload_has_data(const void* pixels);

#endif // __cplusplus

#ifdef __cplusplus
extern "C"
{
#endif

    // Performs a glReadPixels whose (format, type) pair GLES lacks, encoding the
    // driver's RGBA readback into the layout the application asked for --
    // honouring the pack state, including a bound pack PBO.
    //
    // Returns false for a pair GLES accepts, so the caller does its normal read --
    // and also for a pair that is ours but whose underlying RGBA read the driver
    // refused, where falling through to the driver is likewise the right move. The
    // caller's action is the same either way; the distinction is only that false no
    // longer means "not ours".
    // Whether a glReadPixels of this pair can deliver anything at all: either
    // mg_transfer_readback re-encodes it, or the backend takes it directly. GLES
    // rejects everything else with GL_INVALID_OPERATION and leaves the
    // destination untouched, so an emulation that forwards blindly hands the
    // caller back its own uninitialised buffer.
    bool mg_readback_pair_supported(GLenum format, GLenum type);

    bool mg_transfer_readback(GLint x, GLint y, GLsizei width, GLsizei height, GLenum format, GLenum type,
                              void* pixels);

#ifdef __cplusplus
}
#endif

#endif // MOBILEGLUES_TRANSFER_H
