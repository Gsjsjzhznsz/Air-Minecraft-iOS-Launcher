#!/usr/bin/env python3
"""Task 167: disassemble SwapchainObject::GetImage at file offset 0x673a08 (+0x28 crash pc)
in libMobileGL.dylib to identify the faulting instruction."""
import struct
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN

DYLIB = "/home/z/my-project/Amethyst-iOS-MyRemastered/Natives/resources/Frameworks/libMobileGL.dylib"
FUNC_OFF = 0x673a08          # from fatal trace: libMobileGL.dylib+0x673a08
CRASH_OFF = 0x673a30         # +0x28

with open(DYLIB, "rb") as f:
    f.seek(FUNC_OFF - 0x20)
    blob = f.read(0xC0)

md = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)
start = FUNC_OFF - 0x20
for insn in md.disasm(blob, start):
    marker = "  <-- FAULT PC" if insn.address == CRASH_OFF else ""
    print(f"0x{insn.address:x}:  {insn.bytes.hex():<12} {insn.mnemonic} {insn.op_str}{marker}")
