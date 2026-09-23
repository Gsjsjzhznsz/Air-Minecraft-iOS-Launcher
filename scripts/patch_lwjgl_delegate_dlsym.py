#!/usr/bin/env python3
"""Task 154: patch GL$1 (the GL.create(SharedLibrary) Delegate) in
lwjgl-341/lwjgl-opengl.jar so that its GetProcAddress indirection can never
resolve to a renderer's eglGetProcAddress.

Why (7c32bc3 + e52a91c device-log forensics):
  The Delegate resolves every GL function as
      addr = GetProcAddress(name)  if GetProcAddress != 0
      addr = dlsym(library, name) otherwise
  On MACOSX the Delegate's constructor looks up "eglGetProcAddress" in the
  provider library (an Amethyst customization on top of upstream 3.4.1; the
  lwjgl-333 build does not have it). For Mithril that indirect pointer hands
  out broken results for core gl* names, while Mithril's own dlsym exports
  (_glGetString/_glGetIntegerv/_glGetError, verified in its LC_DYLD_EXPORTS_
  TRIE) are exactly what the working tri-probe used. MobileGL's
  eglGetProcAddress returns 0 for core gl names (Task140), so it already
  resolves through the dlsym fallback; OSMesa exports OSMesaGetProcAddress
  (that lookup is left untouched); gl4es/tinygl4angle do not export
  eglGetProcAddress at all. Renaming the constant-pool string to a dead name
  therefore changes behaviour only for Mithril -- from broken-indirection to
  dlsym-direct, matching how every working renderer already resolves.

Surgery (same-length constant-pool byte swap, zero structural change):
  b"\\x01\\x00\\x11eglGetProcAddress"  ->  b"\\x01\\x00\\x11xglGetProcAddress"
  (CONSTANT_Utf8 tag 0x01, length 0x11 = 17 bytes, first byte e->x)

Idempotent: a second run finds the dead name already in place and exits 0.
Verifies: exactly one occurrence before patching, "OSMesaGetProcAddress"
untouched, jar rewritten preserving all other entries.
"""
import sys, zipfile, shutil, os

TARGET_ENTRY = "org/lwjgl/opengl/GL$1.class"
OLD = b"\x01\x00\x11eglGetProcAddress"
NEW = b"\x01\x00\x11xglGetProcAddress"
DEAD_RAW = b"xglGetProcAddress"
KEEP = b"OSMesaGetProcAddress"

def main(jar_path):
    with zipfile.ZipFile(jar_path, "r") as zf:
        names = zf.namelist()
        if TARGET_ENTRY not in names:
            print(f"FAIL: {TARGET_ENTRY} not found in {jar_path}")
            return 1
        data = zf.read(TARGET_ENTRY)
        others = {n: zf.read(n) for n in names if n != TARGET_ENTRY}
        infos = {i.filename: i for i in zf.infolist()}

    if data.count(OLD) == 1:
        patched = data.replace(OLD, NEW)
    elif data.count(OLD) == 0 and DEAD_RAW in data:
        # already patched (idempotent re-run)
        patched = data
        print(f"[task154] {jar_path}: already patched (dead name present) -- no-op")
    else:
        print(f"FAIL: unexpected eglGetProcAddress occurrence count "
              f"(cp={data.count(OLD)}, raw={data.count(DEAD_RAW)}) in {jar_path}")
        return 1

    if KEEP not in patched:
        print(f"FAIL: {KEEP.decode()} missing after patch -- aborting")
        return 1
    if b"eglGetProcAddress" in patched:
        print(f"FAIL: eglGetProcAddress still present after patch -- aborting")
        return 1

    if patched == data:
        return 0

    # rewrite the jar preserving entry order and compression
    tmp = jar_path + ".task154.tmp"
    with zipfile.ZipFile(jar_path, "r") as zin, \
         zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
        for info in zin.infolist():
            if info.filename == TARGET_ENTRY:
                zout.writestr(info, patched)
            else:
                zout.writestr(info, zin.read(info.filename))
    shutil.move(tmp, jar_path)
    print(f"[task154] {jar_path}: GL$1 Delegate 'eglGetProcAddress' -> 'xglGetProcAddress' "
          f"(GetProcAddress indirection dead-ends, dlsym direct resolution engaged)")
    return 0

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: patch_lwjgl_delegate_dlsym.py <lwjgl-opengl.jar>")
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
