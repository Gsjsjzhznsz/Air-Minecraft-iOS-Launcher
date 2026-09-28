#!/usr/bin/env python3
"""patch_gl4es_rtld_default.py — Task192 binary patch for libgl4es_114.dylib

Root cause (956ea9b device session, latestlog.old, Forge 1.8.9 + gl4es):
  initialize_gl4es (dylib constructor) -> GetHardwareExtensions ->
  proc_address(name):
      if (resolver_global) return resolver_global(name);   // never set by anyone
      return dlsym(RTLD_NEXT, name);                        // <- the bug
  RTLD_NEXT from libgl4es searches images loaded AFTER gl4es in the global
  image list. libEGL.framework / libGLESv2.framework are gl4es's OWN
  dependencies — they load BEFORE gl4es (dyld loads deps first), so
  RTLD_NEXT finds nothing -> all egl_* pointers NULL -> the constructor
  calls one of them -> SIGSEGV at pc=0.

Fix (4 bytes): in proc_address, `mov x0, #-1` (RTLD_NEXT) -> `mov x0, #-2`
(RTLD_DEFAULT). RTLD_DEFAULT searches the global symbol scope, which
contains libEGL/libGLESv2 (gl4es is dlopen'd RTLD_GLOBAL by our
egl_bridge, and its dependency frameworks are therefore globally visible).

Encoding: MOVN Xd, #imm  ->  0x92800000 | (imm << 5) | Rd
  mov x0, #-1 = 0x92800000 ; mov x0, #-2 = 0x92800020

Usage:
  python3 patch_gl4es_rtld_default.py <libgl4es_114.dylib> [--verify]
"""
import struct
import sys

# __TEXT segment: vmaddr 0, file off 0（已核对该二进制）。
PROC_ADDR = 0x136DA4
PATCH_SITE = 0x136DEC          # mov x0, #-1 inside proc_address's fallback
ORIG_CTX = bytes.fromhex("e10740f900008092b61f0294a0831ff8")  # 0x136de8..0x136df8
WORD_ORIG = 0x92800000          # mov x0, #-1
WORD_NEW = 0x92800020           # mov x0, #-2


def patch(path, verify_only=False):
    with open(path, "rb") as f:
        blob = bytearray(f.read())

    # proc_address 函数头指纹（防版本漂移错位）：
    # sub sp, sp, #0x30 ; stp x29, x30, [sp, #0x20]
    head = bytes(blob[PROC_ADDR:PROC_ADDR + 8])
    if head != bytes.fromhex("ffc300d1fd7b02a9"):
        print(f"patch_gl4es_rtld_default: FAIL: proc_address header mismatch "
              f"(got {head.hex()}) - binary drift, refusing to patch", file=sys.stderr)
        return 1

    ctx = bytes(blob[PATCH_SITE - 4:PATCH_SITE + 8])
    word = struct.unpack("<I", blob[PATCH_SITE:PATCH_SITE + 4])[0]

    if word == WORD_NEW:
        print("patch_gl4es_rtld_default: PATCH PRESENT (mov x0, #-2 / RTLD_DEFAULT) ✓")
        return 0
    if word != WORD_ORIG or ctx[:4] != ORIG_CTX[:4] or ctx[8:12] != ORIG_CTX[8:12]:
        print(f"patch_gl4es_rtld_default: FAIL: patch site context mismatch "
              f"(word=0x{word:08x} ctx={ctx.hex()}) - refusing", file=sys.stderr)
        return 1

    if verify_only:
        print("patch_gl4es_rtld_default: NOT PATCHED (pristine pattern matches)")
        return 0

    blob[PATCH_SITE:PATCH_SITE + 4] = struct.pack("<I", WORD_NEW)
    with open(path, "wb") as f:
        f.write(blob)
    print("patch_gl4es_rtld_default: PATCHED proc_address fallback "
          "dlsym(RTLD_NEXT) -> dlsym(RTLD_DEFAULT) (4 bytes @ 0x%x) ✓" % PATCH_SITE)
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(patch(sys.argv[1], verify_only="--verify" in sys.argv))
