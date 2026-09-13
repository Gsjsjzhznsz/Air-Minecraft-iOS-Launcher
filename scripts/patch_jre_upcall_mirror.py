#!/usr/bin/env python3
"""Task 74: patch JRE 21/25 libjvm.dylib -- fix SIGBUS in UpcallStub::create under MirrorMappedCodeCache.

ROOT CAUSE (confirmed by device log 1ef50ec + binary analysis of the shipped
jre25-ios-arm64-20260710-release):

  Fabulously Optimized's Controlify registers FFM (java.lang.foreign) upcall
  callbacks -> UL_MakeUpcallStub -> UpcallStub::create ->
  CodeCache::allocate(size, NonMethod, ...) -> CodeBlob::CodeBlob(this=<blob>)
  -> first store "stp xzr, x1, [x0]" faults with SIGBUS.

  On iOS 26+ TXM devices the launcher enables -XX:+MirrorMappedCodeCache:
  the code cache is the debugger-provided RX region (write-protected!) with an
  RW alias at RX+0x4000000. CodeCache::allocate() returns RX-space pointers;
  EVERY writer must translate them through os::Bsd::mirrored_find_rw()
  (RX -> RW alias) before writing the blob header.

  The Amethyst mirror patch fixed all 13 blob ::create factories
  (RuntimeStub/BufferBlob/Adapter/Vtable/nmethod/... -- verified
  instruction-by-instruction: each does "bl allocate; bl mirrored_find_rw"),
  but MISSED UpcallStub::create in the JDK 21 and 25 builds:
      0x299f3c(JRE25): bl  CodeCache::allocate
      0x299f40       : mov x24, x0          <-- raw RX pointer, no find_rw!
      ...            : bl  CodeBlob::CodeBlob(this=x24)  --> SIGBUS
  JRE17 is NOT affected: its incubator-FFM path (OptimizedEntryBlob::create)
  already has the canonical "bl allocate; bl mirrored_find_rw" sequence.

FIX (mirrors the verified RuntimeStub::new_runtime_stub pattern):

  Replace the single "mov xN, x0" with "bl <cave>" where <cave> is the dead
  UpcallStub::operator new(size_t, jint) body (0 callers -- the allocation is
  inlined into create; verified by exhaustive BL/B scan of __text):

      cave:  str  x30, [sp, #-0x10]!      ; save lr
             bl   mirrored_find_rw        ; x0 = find_rw(x0)  (null-safe,
                                          ;  identity when mirror mode off)
             mov  xN, x0                  ; blob register = RW address
             ldr  x30, [sp], #0x10        ; restore lr
             ret                         ; back to "cbz x0, fail" (unchanged)

  Everything downstream (CodeBlob ctor writes, UpcallStub field stores,
  CodeCache::commit -- normalizes via mirrored_swap_wx, and the final
  mirrored_find_rx that returns the executable RX view) then behaves exactly
  like the sibling factories that already work on this device.

  When MirrorMappedCodeCache is OFF, mirrored_find_rw is an identity function,
  so the patch is a no-op for non-mirror devices (JIT-entitled builds etc.).

Safety: full-file SHA256 pins for both published runtimes; exact original-byte
verification at both patch sites; idempotent (patched state detected);
loud failure on any mismatch (runtime version drift guard).
"""
import hashlib
import struct
import sys

MIRRIR_FIND_RW_NOTE = "os::Bsd::mirrored_find_rw (RX->RW alias translation)"


def _u32(data, off):
    return struct.unpack_from('<I', data, off)[0]


def bl_enc(src, dst):
    diff = dst - src
    assert diff % 4 == 0, 'unaligned bl target'
    imm26 = (diff >> 2) & 0x3FFFFFF
    return 0x94000000 | imm26


def cave_words(cave_va, find_rw_va, blob_reg):
    """str x30,[sp,#-0x10]! / bl find_rw / mov xN,x0 / ldr x30,[sp],#0x10 / ret"""
    mov = 0xAA0003E0 | blob_reg          # mov xN, x0 (ORR Xd, XZR, X0)
    return [
        0xF81F0FFE,                        # str  x30, [sp, #-0x10]!
        bl_enc(cave_va + 4, find_rw_va),   # bl   mirrored_find_rw
        mov,                                # mov  xN, x0
        0xF84107FE,                        # ldr  x30, [sp], #0x10
        0xD65F03C0,                        # ret
    ]


# ---------------------------------------------------------------------------
# Per-runtime patch specifications. Offsets are FILE offsets (== __TEXT vaddrs:
# __TEXT has vmaddr 0 / fileoff 0 in both runtimes).
# ---------------------------------------------------------------------------
RUNTIMES = {
    'java-21-openjdk': {
        'pristine_sha256':
            '88d7fb0eae4cece29197f0963bf420a1977603ca3c01dfcec082f1955ae4d956',
        'site_off': 0x276B68,             # mov x25, x0  (in UpcallStub::create)
        'blob_reg': 25,
        'cave_off': 0x2769CC,             # dead UpcallStub::operator new body
        'find_rw_va': 0x81B2A0,           # os::Bsd::mirrored_find_rw
        # original site: mov x25, x0
        'site_orig': [0xAA0003F9],
        # original cave (8 instrs of dead UpcallStub::operator new):
        #   stp x29,x30,[sp,#-0x10]! / mov x29,sp / mov x0,x1 / mov w1,#2 /
        #   mov w2,#1 / mov w3,#3 / ldp x29,x30,[sp],#0x10 / b CodeCache::allocate
        'cave_orig': [0xA9BF7BFD, 0x910003FD, 0xAA0103E0, 0x52800041,
                      0x52800022, 0x52800063, 0xA8C17BFD, 0x14001989],
    },
    'java-25-openjdk': {
        'pristine_sha256':
            '9234ae05e6f2856f8cab6dc7e4fe39f5d4416322c2bec5152b2195dad475ea6b',
        'site_off': 0x299F40,             # mov x24, x0  (in UpcallStub::create)
        'blob_reg': 24,
        'cave_off': 0x299DE8,             # dead UpcallStub::operator new body
        'find_rw_va': 0x897F3C,           # os::Bsd::mirrored_find_rw
        'site_orig': [0xAA0003F8],
        'cave_orig': [0xA9BF7BFD, 0x910003FD, 0xAA0103E0, 0x52800041,
                      0x52800022, 0x52800063, 0xA8C17BFD, 0x14001CB9],
    },
}


def words_at(data, off, n):
    return [struct.unpack_from('<I', data, off + 4 * i)[0] for i in range(n)]


def patch_file(path):
    with open(path, 'rb') as f:
        data = f.read()
    sha = hashlib.sha256(data).hexdigest()

    spec = None
    for name, s in RUNTIMES.items():
        if sha == s['pristine_sha256']:
            spec = s
            runtime = name
            break
    if spec is None:
        # unknown hash: either already patched, or a drifted runtime
        for name, s in RUNTIMES.items():
            site = words_at(data, s['site_off'], 1)
            cave = words_at(data, s['cave_off'], 5)
            want_site = [bl_enc(s['site_off'], s['cave_off'])]
            want_cave = cave_words(s['cave_off'], s['find_rw_va'], s['blob_reg'])
            if site == want_site and cave == want_cave:
                print(f'[jre-upcall-mirror] {path}: already patched '
                      f'({name} site+cave verified) -- OK')
                return True
        sys.stderr.write(
            f'[jre-upcall-mirror] FATAL: {path} (sha256 {sha}) matches no '
            f'known runtime and no patched state. The bundled JRE changed -- '
            f're-derive UpcallStub::create offsets before patching.\n')
        return False

    site_off = spec['site_off']
    cave_off = spec['cave_off']
    n_cave_orig = len(spec['cave_orig'])

    # ---- verify original bytes (drift guard) ----
    if words_at(data, site_off, 1) != spec['site_orig'] or \
       words_at(data, cave_off, n_cave_orig) != spec['cave_orig']:
        sys.stderr.write(
            f'[jre-upcall-mirror] FATAL: {path} ({runtime}) hash matched but '
            f'patch-site bytes differ -- refusing to patch.\n')
        return False

    # ---- build patched words ----
    new_site = bl_enc(site_off, cave_off)               # bl <cave>
    new_cave = cave_words(cave_off, spec['find_rw_va'], spec['blob_reg'])

    # ---- write cave FIRST (crash-safe ordering), then the site ----
    buf = bytearray(data)
    for i, w in enumerate(new_cave):
        struct.pack_into('<I', buf, cave_off + 4 * i, w)
    struct.pack_into('<I', buf, site_off, new_site)

    with open(path, 'wb') as f:
        f.write(bytes(buf))

    patched_sha = hashlib.sha256(bytes(buf)).hexdigest()
    print(f'[jre-upcall-mirror] {runtime}: PATCHED')
    print(f'    site {site_off:#x}: {spec["site_orig"][0]:08x} (mov x{spec["blob_reg"]}, x0)'
          f' -> {new_site:08x} (bl {cave_off:#x})')
    print(f'    cave {cave_off:#x}: dead UpcallStub::operator new -> '
          f'save-lr / bl mirrored_find_rw({spec["find_rw_va"]:#x}) / '
          f'mov x{spec["blob_reg"]}, x0 / restore-lr / ret')
    print(f'    patched sha256: {patched_sha}')
    return True


def main(argv):
    if len(argv) < 2:
        sys.stderr.write(
            'usage: patch_jre_upcall_mirror.py <libjvm.dylib> '
            '[<libjvm.dylib> ...]  (pass the java-21/java-25 lib/server copies)\n')
        return 2
    ok = True
    for p in argv[1:]:
        if not patch_file(p):
            ok = False
    if not ok:
        sys.stderr.write('[jre-upcall-mirror] FAILED -- see errors above\n')
        return 1
    print('[jre-upcall-mirror] all runtimes OK')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
