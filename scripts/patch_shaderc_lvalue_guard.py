#!/usr/bin/env python3
"""patch_shaderc_lvalue_guard.py — binary patch for libshaderc_impl.dylib
(arm64 iOS). Amethyst Task 34.

WHAT
----
Closes the glslang::TParseContext::lValueErrorCheck swizzle-selector crash:
device hs_err shows SIGSEGV at lValueErrorCheck+0x204 during RenderPearl
shader compilation (builds b199c07 / 777302c, crash at compile#7
'minecraft:core/terrain'; Task 30 saw the identical PC with si_addr = ASCII
string bytes — freed-then-reused glslang pool memory, a corruption family
that predates Amethyst per MobileGlues 2.0.1..2.0.3 crash reports).

The MobileGlues source tree guards this exact chain in
3rdparty/glslang-lvalue-nullguard.patch, but the prebuilt
libshaderc_impl.dylib ships an UNPATCHED glslang. This script applies the
equivalent guard as machine code:

  1. Relocates the vulnerable loop body (FUNC+0x1e4 .. +0x243) into the
     executable __TEXT tail-padding cave (0x512400, zero-filled, verified).
  2. The relocated body adds:
       - null guard after node load            (*p == nullptr)
       - null guard after getAsTyped()
       - null guard after getAsConstantUnion()
       - null guard for the constArray data pointer (empty vector)
       - null guard for the TConstUnion element
       - value bounds 0..3 before the offset[] table write
         (the Task-30 OOB stack write amplifier)
     Any guard trip skips the duplicate-component check for that element
     and continues the loop — parse always completes (same semantics as the
     MobileGlues source patch).
  3. Leaves a single 4-byte trampoline `b <stub>` at FUNC+0x1e4; the 23
     following original instructions become dead code (never executed; the
     only loop entry is +0x1e4 itself).

The stub and trampoline bytes were assembled with keystone and verified by
capstone round-trip disassembly (see the development script
assemble_stub3.py in the session worklog); they are embedded below so this
script runs with the Python standard library only (CI-safe).

CODE SIGNATURE: patching invalidates the embedded signature. The existing
build flow already runs install_name_tool on this dylib (same invalidation)
and re-signs the whole .app with ldid at package time, so no extra step is
needed. install_name_tool on modern Xcode also re-signs ad-hoc.

USAGE
-----
  python3 patch_shaderc_lvalue_guard.py <libshaderc_impl.dylib> [--verify]

  --verify : check patch state only, never write.
  Idempotent: re-running on a patched binary verifies and exits 0.
  Exits 1 with a clear message when the binary does not match the expected
  pristine pattern (future impl updates must re-derive the patch).
"""
import struct
import sys

FUNC_VM = 0x98A38          # glslang::TParseContext::lValueErrorCheck
BLOCK_VM = 0x98C1C         # FUNC+0x1e4 — vulnerable loop head
STUB_VM = 0x512400         # cave: __TEXT tail padding (zero-filled)
# NOTE: the string-table name carries the Mach-O platform prefix underscore
# on top of the Itanium mangled name, hence the double leading underscore.
SYM = b"__ZN7glslang13TParseContext16lValueErrorCheckERKNS_10TSourceLocEPKcPNS_12TIntermTypedE"

ORIG_BLOCK_HEX = (
    "e00240f9"  # +0x1e4 ldr  x0, [x23]
    "080040f9"  # +0x1e8 ldr  x8, [x0]
    "081140f9"  # +0x1ec ldr  x8, [x8, #0x20]
    "00013fd6"  # +0x1f0 blr  x8            (node->getAsTyped())
    "080040f9"  # +0x1f4 ldr  x8, [x0]
    "081940f9"  # +0x1f8 ldr  x8, [x8, #0x30]
    "00013fd6"  # +0x1fc blr  x8            (typed->getAsConstantUnion())
    "086c40f9"  # +0x200 ldr  x8, [x0, #0xd8]  (getConstArray data ptr)
    "080140f9"  # +0x204 ldr  x8, [x8]      <-- CRASH PC (hs_err 0x98c3c)
    "080180b9"  # +0x208 ldrsw w8, [x8]     (constArray[0].getIConst())
    "08f57ed3"  # +0x20c lsl  x8, x8, #2
    "096b68b8"  # +0x210 ldr  w9, [x24, x8] (offset[value])
    "2a050011"  # +0x214 add  w10, w9, #1
    "0a6b28b8"  # +0x218 str  w10, [x24, x8]
    "3f050071"  # +0x21c cmp  w9, #1
    "8a110054"  # +0x220 b.ge 0x98e88       (duplicate -> error path)
    "f7220091"  # +0x224 add  x23, x23, #8  (++p)
    "c80240f9"  # +0x228 ldr  x8, [x22]
    "08d540f9"  # +0x22c ldr  x8, [x8, #0x1a8]
    "e00316aa"  # +0x230 mov  x0, x22
    "00013fd6"  # +0x234 blr  x8            (aggr->getSequence())
    "080440f9"  # +0x238 ldr  x8, [x0, #8]  (end)
    "ff0208eb"  # +0x23c cmp  x23, x8
    "21fdff54"  # +0x240 b.ne 0x98c1c       (loop back)
)

STUB_HEX = (
    "e00240f9"  # 0x512400 ldr  x0, [x23]           node = *p
    "e00200b4"  # 0x512404 cbz  x0, advance         null node guard
    "080040f9"  # 0x512408 ldr  x8, [x0]
    "081140f9"  # 0x51240c ldr  x8, [x8, #0x20]
    "00013fd6"  # 0x512410 blr  x8                  getAsTyped()
    "600200b4"  # 0x512414 cbz  x0, advance         null guard
    "080040f9"  # 0x512418 ldr  x8, [x0]
    "081940f9"  # 0x51241c ldr  x8, [x8, #0x30]
    "00013fd6"  # 0x512420 blr  x8                  getAsConstantUnion()
    "e00100b4"  # 0x512424 cbz  x0, advance         null guard
    "086c40f9"  # 0x512428 ldr  x8, [x0, #0xd8]     constArray data ptr
    "a80100b4"  # 0x51242c cbz  x8, advance         empty array guard
    "080140f9"  # 0x512430 ldr  x8, [x8]
    "680100b4"  # 0x512434 cbz  x8, advance         null element guard
    "090180b9"  # 0x512438 ldrsw x9, [x8]           getIConst()
    "2901f837"  # 0x51243c tbnz w9, #31, advance    negative value guard
    "3f110071"  # 0x512440 cmp  w9, #4
    "ea000054"  # 0x512444 b.ge advance             value >= 4 (OOB write guard)
    "29f57ed3"  # 0x512448 lsl  x9, x9, #2
    "0a6b69b8"  # 0x51244c ldr  w10, [x24, x9]
    "4a050011"  # 0x512450 add  w10, w10, #1
    "0a6b29b8"  # 0x512454 str  w10, [x24, x9]
    "5f090071"  # 0x512458 cmp  w10, #2
    "6a010054"  # 0x51245c b.ge 0x512488            duplicate -> error
    "f7220091"  # 0x512460 advance: add x23, x23, #8
    "c80240f9"  # 0x512464 ldr  x8, [x22]
    "08d540f9"  # 0x512468 ldr  x8, [x8, #0x1a8]
    "e00316aa"  # 0x51246c mov  x0, x22
    "00013fd6"  # 0x512470 blr  x8                  getSequence()
    "080440f9"  # 0x512474 ldr  x8, [x0, #8]
    "ff0208eb"  # 0x512478 cmp  x23, x8
    "21fcff54"  # 0x51247c b.ne 0x512400            loop
    "01000014"  # 0x512480 b    0x512484
    "721aee17"  # 0x512484 b    0x98e4c            loop done -> return false
    "801aee17"  # 0x512488 b    0x98e88            duplicate -> error path
)

TRAMP_HEX = "f9e51114"     # 0x98c1c: b 0x512400

TEXT_LIMIT = 0x514000      # __TEXT vmsize end (stub must stay below this)


def fail(msg):
    print(f"patch_shaderc_lvalue_guard: FAIL: {msg}", file=sys.stderr)
    sys.exit(1)


def main():
    args = [a for a in sys.argv[1:] if a != "--verify"]
    verify_only = "--verify" in sys.argv
    if len(args) != 1:
        print(__doc__)
        sys.exit(2)
    path = args[0]
    try:
        data = bytearray(open(path, "rb").read())
    except OSError as e:
        fail(f"cannot read {path}: {e}")

    # --- parse Mach-O: segments (vm->file) + symtab ---
    if struct.unpack_from("<I", data, 0)[0] != 0xFEEDFACF:
        fail("not a 64-bit little-endian Mach-O")
    ncmds = struct.unpack_from("<I", data, 16)[0]
    off = 32
    segs = []
    symtab = None
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd == 0x19:  # LC_SEGMENT_64
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", data, off + 24)
            segs.append((vmaddr, vmsize, fileoff, filesize))
        elif cmd == 0x2:  # LC_SYMTAB
            symtab = struct.unpack_from("<IIII", data, off + 8)
        off += cmdsize
    if symtab is None:
        fail("no symtab")

    def vm2file(a):
        for va, vs, fo, fs in segs:
            if va <= a < va + vs:
                return fo + (a - va)
        return None

    # --- resolve the symbol (sanity: must land on the expected FUNC_VM) ---
    symoff, nsyms, stroff, strsize = symtab
    func_vm = None
    for i in range(nsyms):
        so = symoff + i * 16
        n_strx, n_type = struct.unpack_from("<IB", data, so)
        if n_strx < strsize and (n_type & 0x0E) == 0x0E:
            end = data.index(b"\0", stroff + n_strx)
            if bytes(data[stroff + n_strx:end]) == SYM:
                func_vm = struct.unpack_from("<Q", data, so + 8)[0]
                break
    if func_vm is None:
        fail("lValueErrorCheck symbol not found — binary layout changed, re-derive patch")
    if func_vm != FUNC_VM:
        fail(f"lValueErrorCheck moved: found 0x{func_vm:x}, expected 0x{FUNC_VM:x} — re-derive patch")

    block_fo = vm2file(BLOCK_VM)
    stub_fo = vm2file(STUB_VM)
    if block_fo is None or stub_fo is None:
        fail("cannot map patch addresses into file offsets")
    if STUB_VM + len(STUB_HEX) // 2 > TEXT_LIMIT:
        fail("stub would exceed __TEXT")

    orig = bytes.fromhex(ORIG_BLOCK_HEX)
    stub = bytes.fromhex(STUB_HEX)
    tramp = bytes.fromhex(TRAMP_HEX)

    cur_block = bytes(data[block_fo:block_fo + len(orig)])
    cur_tramp = bytes(data[block_fo:block_fo + 4])
    cur_stub = bytes(data[stub_fo:stub_fo + len(stub)])

    already = cur_tramp == tramp and cur_stub == stub
    pristine = cur_block == orig

    if verify_only:
        if already:
            print("patch_shaderc_lvalue_guard: PATCH PRESENT ✓ (trampoline + stub verified)")
            return
        if pristine:
            print("patch_shaderc_lvalue_guard: NOT PATCHED (pristine pattern matches)")
            return
        fail("binary matches neither pristine nor patched state")
    if already:
        print("patch_shaderc_lvalue_guard: already patched, nothing to do ✓")
        return
    if not pristine:
        fail("vulnerable block bytes do not match the expected pristine pattern — "
             "impl binary changed, re-derive the patch")
    if cur_stub != bytes(len(stub)):
        fail("cave is not zero-filled — refusing to overwrite live code")

    data[stub_fo:stub_fo + len(stub)] = stub
    data[block_fo:block_fo + 4] = tramp

    with open(path, "wb") as f:
        f.write(bytes(data))
    print(f"patch_shaderc_lvalue_guard: PATCHED ✓ "
          f"(trampoline @0x{BLOCK_VM:x}, stub @0x{STUB_VM:x}+{len(stub)}, "
          f"6 null/bounds guards, crash PC 0x98c3c now unreachable)")


if __name__ == "__main__":
    main()
