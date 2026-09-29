#!/usr/bin/env python3
"""patch_gl4es_ggstr_nullguard.py — Task202 binary patch for libgl4es_114.dylib

Root cause (e4d704e device session, latestlog.1, 1.8.9-forge + gl4es; forensics
re-verified against this exact binary):
  initialize_gl4es (dylib constructor) -> GetHardwareExtensions:
      0x1bc2a8  adrp x8, 0x1e0000
      0x1bc2ac  ldr  x8, [x8, #0x938]     ; glGetString pointer (globals slot)
      0x1bc2b0  mov  w0, #0x1f03          ; GL_EXTENSIONS
      0x1bc2b4  blr  x8                   ; glGetString(GL_EXTENSIONS)
      0x1bc2bc  stur x0, [x29, #-0xc8]    ; store result -- NULL when no ctx
      ...
      0x1bc2e4  ldur x0, [x29, #-0xc8]    ; haystack = NULL
      0x1bc2ec  add  x1, "GL_APPLE_texture_2D_limited_npot"
      0x1bc2f0  bl   _platform_strstr     ; SIGSEGV (return PC 0x1bc2f4)
  The constructor runs context-less in the device session (the Task193
  context-bootstrap anchors never fired -- see egl_bridge Task202 entry-anchor
  follow-up), ANGLE's glGetString legitimately returns NULL with no current
  context, and the first strstr(NULL, ...) kills the process. Task196/197-era
  diagnosis (useVbo / DSA advertisement) was mis-attributed; the crash is this
  constructor path.

Fix (crash immunity, 4 bytes at the call site + 32-byte cave shim):
  Redirect the `blr x8` at 0x1bc2b4 to a cave shim that calls the SAME
  glGetString pointer, then substitutes an empty string for NULL:
      strstr("", needle) == NULL  ->  every extension check simply reports
      "not present"; the constructor completes; gl4es falls back to its
  default caps (GLES 2.0 backend, as before) instead of dying. Zero behavioral
  change whenever a context IS current (non-NULL passes through untouched).

  Shim @ 0x6400 (__TEXT zero cave before __text@0x64f8, verified all-zero):
      str  x30, [sp, #-16]!     ; save LR (blr inside clobbers it)
      blr  x8                   ; call real glGetString(GL_EXTENSIONS)
      cbnz x0, ret_path         ; non-NULL -> pass through
      adr  x0, empty_str        ; NULL -> point at ""
  ret_path:
      ldr  x30, [sp]            ; restore LR (saved at [sp], offset 0)
      add  sp, sp, #16
      ret
  empty_str: .word 0

  Encoding notes (recorded for audit):
      str x30,[sp,#-16]! = F81F0FFE   blr x8        = D63F0100
      cbnz x0, +16       = B5000080   adr x0, +16   = 10000080
      ldr x30,[sp]       = F94003FE   add sp,sp,#16 = 910043FF
      ret                = D65F03C0   bl <cave>     = 94000000|(disp26)

Usage:
  python3 patch_gl4es_ggstr_nullguard.py <libgl4es_114.dylib> [--verify]
"""
import struct
import sys

# Offsets pinned to the vendored binary (fingerprint-gated below).
GHE_CALL_SITE = 0x1BC2B4          # `blr x8` -- glGetString(GL_EXTENSIONS)
# on-disk little-endian byte fingerprints around the call site
CALL_CTX_BEFORE = bytes.fromhex("60e08352")             # mov w0, #0x1f03 (0x5283e060)
CALL_CTX_AFTER = bytes.fromhex("e84f40f9a08313f8")      # ldr x8,[sp,#0x98] ; stur x0,[x29,#-0xc8]
WORD_ORIG = 0xD63F0100            # blr x8

SHIM_ADDR = 0x6400                # __TEXT cave (all-zero, verified)
SHIM_END = 0x6420                 # 32 bytes: 7 insns + 4-byte empty string

SHIM = [
    0xF81F0FFE,   # str  x30, [sp, #-16]!
    0xD63F0100,   # blr  x8              (real glGetString)
    0xB5000080,   # cbnz x0, +16         (non-NULL -> 0x6418 ret)
    0x10000080,   # adr  x0, +16         (NULL -> x0 = "" @ 0x641C)
    0xF94003FE,   # ldr  x30, [sp]            (LR was stored at [sp])
    0x910043FF,   # add  sp, sp, #16
    0xD65F03C0,   # ret
    0x00000000,   # empty_str: ""
]


def bl_word(pc, target):
    disp = target - pc
    assert disp % 4 == 0
    disp26 = (disp // 4) & 0x3FFFFFF
    return 0x94000000 | disp26


def patch(path, verify_only=False):
    with open(path, "rb") as f:
        blob = bytearray(f.read())

    # --- fingerprint gates (binary drift -> loud refusal, CI fails) ---
    ctx_before = bytes(blob[GHE_CALL_SITE - 4:GHE_CALL_SITE])
    ctx_after = bytes(blob[GHE_CALL_SITE + 4:GHE_CALL_SITE + 12])
    word = struct.unpack("<I", blob[GHE_CALL_SITE:GHE_CALL_SITE + 4])[0]
    if ctx_before != CALL_CTX_BEFORE or ctx_after != CALL_CTX_AFTER:
        print(f"patch_gl4es_ggstr_nullguard: FAIL: call-site context mismatch "
              f"(before={ctx_before.hex()} after={ctx_after.hex()}) - binary drift, "
              f"refusing to patch", file=sys.stderr)
        return 1
    expected_bl = bl_word(GHE_CALL_SITE, SHIM_ADDR)
    if word == expected_bl:
        # already patched -- verify the shim is intact too
        for i, w in enumerate(SHIM):
            got = struct.unpack("<I", blob[SHIM_ADDR + 4 * i:SHIM_ADDR + 4 * i + 4])[0]
            if got != w:
                print(f"patch_gl4es_ggstr_nullguard: FAIL: shim word {i} mismatch "
                      f"(got {got:08x} want {w:08x})", file=sys.stderr)
                return 1
        print("patch_gl4es_ggstr_nullguard: PATCH PRESENT "
              "(glGetString NULL->empty-string shim) \u2713")
        return 0
    if word != WORD_ORIG:
        print(f"patch_gl4es_ggstr_nullguard: FAIL: unexpected word at call site "
              f"(0x{word:08x}, expected blr x8) - refusing", file=sys.stderr)
        return 1

    # cave must be zero (do not clobber anything)
    if any(blob[SHIM_ADDR:SHIM_END]):
        print(f"patch_gl4es_ggstr_nullguard: FAIL: cave "
              f"0x{SHIM_ADDR:x}..0x{SHIM_END:x} is not empty - refusing",
              file=sys.stderr)
        return 1

    if verify_only:
        print("patch_gl4es_ggstr_nullguard: NOT PATCHED (pristine pattern matches)")
        return 0

    # --- write shim into the cave ---
    for i, w in enumerate(SHIM):
        struct.pack_into("<I", blob, SHIM_ADDR + 4 * i, w)
    # --- redirect the call site ---
    struct.pack_into("<I", blob, GHE_CALL_SITE, expected_bl)

    with open(path, "wb") as f:
        f.write(blob)
    print(f"patch_gl4es_ggstr_nullguard: PATCHED glGetString(GL_EXTENSIONS) "
          f"call in GetHardwareExtensions: blr x8 -> bl shim@0x{SHIM_ADDR:x} "
          f"(NULL -> empty string; strstr never sees NULL) \u2713")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(patch(sys.argv[1], verify_only="--verify" in sys.argv))
