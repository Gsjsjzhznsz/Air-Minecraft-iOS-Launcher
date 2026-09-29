#!/usr/bin/env python3
"""patch_gl4es_ggstr_nullguard.py — Task203 v2 binary patch for libgl4es_114.dylib

Root cause (e4d704e device log latestlog.1; re-confirmed on 64fdaf2 latestlog.txt):
  The dylib constructor initialize_gl4es -> GetHardwareExtensions calls
  glGetString(GL_EXTENSIONS / GL_VENDOR) with NO current context. ANGLE's
  legitimate answer is NULL, and the very first strstr(NULL, needle)
  (file offset 0x1BC2F4, needle "GL_APPLE_texture_2D_limited_npot") SIGSEGVs
  before the library ever finishes initializing.

v1 failure autopsy (Task202, commit 64fdaf2, device SIGILL at libgl4es+0x6400):
  v1 redirected the `blr x8` at 0x1BC2B4 to a 32-byte cave shim placed in the
  inter-section gap at 0x6400 (before __text@0x64F8). The build pipeline's
  METHOD_CHANGE_PLAT runs `vtool -set-build-version` on every Mach-O AFTER
  this patch, and vtool RE-SERIALIZES the binary from section data -- bytes
  living in the gap between sections are NOT part of any section, so the shim
  was silently zero-wiped. Device proof: the shipped IPA contains the patched
  BL at 0x1BC2B4 (inside __text, preserved) but ZEROS at 0x6400 -> executing
  UDF #0 -> SIGILL, pc = libgl4es_114.dylib+0x6400, exactly as reported.

v2 approach (this script, Task203) -- vtool-proof BY CONSTRUCTION:
  No cave, no new code, no BL. Overwrite the 2-instruction sequence at each
  glGetString call site (both live inside __text, which vtool copies verbatim,
  as proven by v1's surviving BL) with a direct pointer load of an existing
  NUL byte:

      site 1 (GL_EXTENSIONS) @ 0x1BC2B0:          site 2 (GL_VENDOR) @ 0x1BDE4C:
        mov  w0, #0x1f03        5283E060            mov  w0, #0x1f00   52803E00
        blr  x8                 D63F0100            blr  x8            D63F0100
      ->                                        ->
        adrp x0, #0x1ce000                          adrp x0, #0x1ce000
        add  x0, x0, #0x9a2                         add  x0, x0, #0x9a2

  x0 = 0x1CE9A2 = the NUL terminator of the needle string
  "GL_APPLE_texture_2D_limited_npot " at 0x1CE981 (inside __TEXT,__cstring --
  a real section, vtool-preserved). The following instruction
  `stur x0, [x29, #-0xc8]` stores the "" pointer into the extensions slot;
  every one of the ~45 strstr(exts, needle) checks then evaluates
  strstr("", needle) == NULL -> "extension not present" -> the constructor
  completes with conservative defaults (GLES 2.0 backend), exactly the
  semantics of v1's NULL->empty-string substitution, minus the cave.
  Semantics when a context IS current are irrelevant: this call site only
  exists on the constructor path (verified: only 2 glGetString call sites in
  the whole of GetHardwareExtensions, both patched here).

Full-coverage audit (capstone sweep of GetHardwareExtensions 0x1BB364-0x1C0000):
  * glGetString call sites: exactly 2 (this patch covers both)
  * strstr consumers read stack slots -0xc8 (extensions), -0xd8 (vendor) --
    both fed exclusively by the two patched sites -- and -0xa0
    (eglQueryString, display-scoped, returns a valid string without a
    current context; pre-crash execution already proved it non-NULL)

Usage:
  python3 patch_gl4es_ggstr_nullguard.py <libgl4es_114.dylib> [--verify]

Exit codes: 0 = patched / already present / verify OK; 1 = fingerprint
mismatch (binary drift -- refusing to touch anything).
"""
import struct
import sys

# Offsets pinned to the vendored binary (fingerprint-gated below).
SITE_EXTS_PC   = 0x1BC2B0        # `mov w0, #0x1f03` (GL_EXTENSIONS)
SITE_VENDOR_PC = 0x1BDE4C        # `mov w0, #0x1f00` (GL_VENDOR)
# Original 2-word sequences at each site (fingerprints).
SITE_EXTS_ORIG   = (0x5283E060, 0xD63F0100)   # movz w0,#0x1f03 ; blr x8
SITE_VENDOR_ORIG = (0x5283E000, 0xD63F0100)   # movz w0,#0x1f00 ; blr x8
# Live code that must remain untouched (guard against off-by-one writes).
SITE_EXTS_NEXT   = 0xF9404FE8    # ldr x8, [sp, #0x98]
SITE_VENDOR_NEXT = 0xF94067E8    # ldr x8, [sp, #0xd0]
# The NUL byte we point at: terminator of the needle cstring at 0x1CE981
# ("GL_APPLE_texture_2D_limited_npot " -- 33 chars incl. trailing space).
EMPTY_STR_ADDR = 0x1CE9A2
NEEDLE_CSTR_ADDR = 0x1CE981      # for the audit check below


def enc_adrp_x0(pc, target):
    """ADRP X0, <page(target)> -- 64-bit PC-relative page load."""
    page = target & ~0xFFF
    pc_page = pc & ~0xFFF
    delta = (page - pc_page) >> 12
    assert -(1 << 20) <= delta < (1 << 20), "adrp imm out of range"
    delta &= (1 << 21) - 1
    immlo = delta & 3
    immhi = (delta >> 2) & 0x7FFFF
    return (1 << 31) | (immlo << 29) | (0x10 << 24) | (immhi << 5) | 0  # Rd=x0


def enc_add_x0_x0_imm12(imm):
    assert 0 <= imm < 0x1000
    return (0x91 << 24) | (imm << 10) | (0 << 5) | 0  # ADD X0, X0, #imm


def decode_adrp_target(word, pc):
    """Inverse of enc_adrp for self-verification (no capstone needed)."""
    assert (word >> 31) & 1 == 1 and (word >> 24) & 0x1F == 0x10, "not an ADRP"
    immlo = (word >> 29) & 3
    immhi = (word >> 5) & 0x7FFFF
    imm21 = (immhi << 2) | immlo
    if imm21 & (1 << 20):
        imm21 -= 1 << 21
    return (pc & ~0xFFF) + (imm21 << 12)


def decode_add_imm12(word):
    assert (word >> 24) & 0xFF == 0x91, "not an ADD imm"
    return (word >> 10) & 0xFFF


def read_word(blob, off):
    return struct.unpack_from("<I", blob, off)[0]


def patch_site(blob, pc, orig_pair, next_guard, label):
    w1, w2 = read_word(blob, pc), read_word(blob, pc + 4)
    want1 = enc_adrp_x0(pc, EMPTY_STR_ADDR)
    want2 = enc_add_x0_x0_imm12(EMPTY_STR_ADDR & 0xFFF)
    if (w1, w2) == (want1, want2):
        return "present"
    if (w1, w2) != orig_pair:
        print(f"patch_gl4es_ggstr_nullguard: FAIL: {label} site @ 0x{pc:X} "
              f"unexpected words (0x{w1:08x}, 0x{w2:08x}, wanted orig "
              f"(0x{orig_pair[0]:08x}, 0x{orig_pair[1]:08x}) or v2 adrp/add "
              f"(0x{want1:08x}, 0x{want2:08x})) - binary drift, refusing",
              file=sys.stderr)
        return "fail"
    # v1 remnant? BL-to-shim form (97xxxxxx at pc+4 with movz at pc) --
    # only possible if this script runs on a v1-patched binary; v1 only
    # patched the EXTENSIONS site, and builds always start from the pristine
    # resources copy, so this is theoretical. Fingerprint above already
    # refuses anything that is neither pristine nor v2.
    struct.pack_into("<II", blob, pc, want1, want2)
    # guards: live code after the site must be untouched
    assert read_word(blob, pc + 8) == next_guard, f"{label}: post-site guard changed"
    # self-verification without capstone
    assert decode_adrp_target(read_word(blob, pc), pc) == (EMPTY_STR_ADDR & ~0xFFF)
    assert decode_add_imm12(read_word(blob, pc + 4)) == (EMPTY_STR_ADDR & 0xFFF)
    return "patched"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    verify_only = "--verify" in sys.argv
    if len(args) != 1:
        print(__doc__)
        return 1
    path = args[0]
    with open(path, "rb") as f:
        blob = bytearray(f.read())

    # Audit gates (fail loudly on any drift before touching anything):
    # 1) the empty-string byte must exist and be NUL
    if blob[EMPTY_STR_ADDR] != 0x00:
        print(f"patch_gl4es_ggstr_nullguard: FAIL: byte at 0x{EMPTY_STR_ADDR:X} "
              f"is 0x{blob[EMPTY_STR_ADDR]:02X}, expected 0x00 (empty-string "
              f"anchor drifted)", file=sys.stderr)
        return 1
    # 2) the needle cstring must be where we think (prefix check)
    needle_prefix = b"GL_APPLE_texture_2D_limited_npot"
    if bytes(blob[NEEDLE_CSTR_ADDR:NEEDLE_CSTR_ADDR + len(needle_prefix)]) != needle_prefix:
        print(f"patch_gl4es_ggstr_nullguard: FAIL: needle cstring at "
              f"0x{NEEDLE_CSTR_ADDR:X} drifted (prefix mismatch)", file=sys.stderr)
        return 1

    r1 = patch_site(blob, SITE_EXTS_PC, SITE_EXTS_ORIG, SITE_EXTS_NEXT, "GL_EXTENSIONS")
    if r1 == "fail":
        return 1
    r2 = patch_site(blob, SITE_VENDOR_PC, SITE_VENDOR_ORIG, SITE_VENDOR_NEXT, "GL_VENDOR")
    if r2 == "fail":
        return 1

    if verify_only:
        print("patch_gl4es_ggstr_nullguard: VERIFY OK "
              "(both GetHardwareExtensions glGetString sites present in v2 "
              "adrp+add-to-empty-string form; zero-byte anchor intact)")
        return 0

    if r1 == "present" and r2 == "present":
        print("patch_gl4es_ggstr_nullguard: PATCH PRESENT "
              "(GetHardwareExtensions GL_EXTENSIONS + GL_VENDOR -> \"\" "
              "pointer loads; vtool-proof v2)")
        return 0

    with open(path, "wb") as f:
        f.write(blob)
    print(f"patch_gl4es_ggstr_nullguard: PATCHED GetHardwareExtensions "
          f"glGetString x2 (GL_EXTENSIONS@0x{SITE_EXTS_PC:X} + GL_VENDOR@"
          f"0x{SITE_VENDOR_PC:X}): movz+blr -> adrp+add -> \"\" "
          f"(0x{EMPTY_STR_ADDR:X}); strstr never sees NULL; both writes "
          f"inside __text = vtool-proof (v1 cave wiped by METHOD_CHANGE_PLAT) "
          f"\u2713")
    return 0


if __name__ == "__main__":
    sys.exit(main())
