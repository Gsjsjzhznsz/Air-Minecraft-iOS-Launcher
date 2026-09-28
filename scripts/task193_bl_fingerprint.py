#!/usr/bin/env python3
"""Task 193: 用 727a291 IPA 二进制做 bl 指纹符号化（task192_true_slide_final 同款）。

崩溃帧 0x10ac454d8 是【返回地址】= bl 调用点 + 4。找到 __objc_stubs 里
insertObject:atIndex: 的专属桩 → 全 __TEXT 扫描 bl 到该桩的调用点 →
slide = 0x10ac454d8 - (callsite + 4)，要求页对齐（0x4000 倍数）。
"""
import lief, bisect, struct
from capstone import *

md = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)
md.detail = True
BIN = "/tmp/appx727/payload/Payload/AngelAuraAmethyst.app/AngelAuraAmethyst"
bin = lief.MachO.parse(BIN)[0]
text = next(s for s in bin.segments if s.name == "__TEXT")
data = bytes(text.content)
tbase = text.virtual_address
md = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)

FRAMES = [0x10ac454d8, 0x10ac45848, 0x10ac47d0c, 0x10ac42e34, 0x10ac431f8,
          0x10ad149d0, 0x10ad17050, 0x10ad27644, 0x10abe4d00]

# 符号表（来自同一二进制）
syms = []
for s in bin.symbols:
    try:
        if s.value and s.name:
            syms.append((s.value, s.name))
    except Exception:
        pass
syms.sort()
addrs = [a for a, _ in syms]


def lookup(off):
    i = bisect.bisect_right(addrs, off) - 1
    if i < 0:
        return "<none>"
    a, n = syms[i]
    return f"{n} +0x{off-a:x}"


# 1) 找 "insertObject:atIndex:" 选择子字符串地址
strtab = None
for seg in bin.segments:
    for sec in seg.sections:
        if sec.name == "__objc_methname":
            strtab = (sec.virtual_address, bytes(sec.content))
            break
    if strtab:
        break
assert strtab, "__objc_methname not found"
sbase, sdata = strtab
target = b"insertObject:atIndex:\x00"
idx = sdata.find(target)
assert idx >= 0, "selector string not found"
SEL_STR = sbase + idx
print(f"sel string @ 0x{SEL_STR:x}")

# 2) __objc_selrefs 找槽（chained fixup 解码；target 可能是绝对 vmaddr，
#    也可能是相对镜像基址 0x100000000 的偏移）
selref_slot = None
for seg in bin.segments:
    for sec in seg.sections:
        if sec.name == "__objc_selrefs":
            srdata = bytes(sec.content)
            srbase = sec.virtual_address
            for off in range(0, len(srdata), 8):
                v = struct.unpack("<Q", srdata[off:off + 8])[0]
                if v == SEL_STR:
                    selref_slot = srbase + off
                    break
                if v & 0x8000000000000000 == 0:
                    # 实测格式（727a291 二进制）：target = 低 48 位，高位是
                    # chained-fixup 链（next/opcode）。selref[0]=0x00100001004d6d82
                    # → target 0x1004d6d82（__objc_methname 区）。
                    t = v & 0xFFFFFFFFFFFF
                    if t == SEL_STR:
                        selref_slot = srbase + off
                        break
            break
    if selref_slot:
        break
print("selref slot:", hex(selref_slot) if selref_slot else "not found")

# 3) __objc_stubs 找专属桩：桩形 adrp x1,...; ldr x1,[x1,#..]; <ldr x16; br>
stubs_sec = next(sec for sec in text.sections if sec.name == "__objc_stubs")
stdata = bytes(stubs_sec.content)
stbase = stubs_sec.virtual_address
stub_addr = None
for off in range(0, len(stdata) - 16, 16):
    ins = list(md.disasm(stdata[off:off + 16], stbase + off, count=2))
    if len(ins) >= 2 and ins[0].mnemonic == "adrp" and ins[1].mnemonic == "ldr":
        # capstone 已把 adrp 解析为绝对页目标（op_str "#0x10059d000"）
        try:
            target_addr = ins[0].operands[1].imm
        except Exception:
            continue
        try:
            imm2 = ins[1].operands[1].mem.disp
        except Exception:
            continue
        slot = target_addr + imm2
        if slot == selref_slot:
            stub_addr = stbase + off
            break
print("insertObject stub:", hex(stub_addr) if stub_addr else "not found")
assert stub_addr

# 4) 全 __TEXT 扫描 bl stub_addr
callsites = []
for ins in md.disasm(data, tbase):
    if ins.mnemonic == "bl" and ins.op_str == f"#0x{stub_addr:x}":
        callsites.append(ins.address)
print(f"bl callsites: {len(callsites)}")

# 5) 页对齐 slide 判定
anchor = FRAMES[0]
found = []
for cs in callsites:
    slide = anchor - (cs + 4)
    if slide <= 0 or (slide & 0x3FFF):
        continue
    found.append((cs, slide))
print(f"page-aligned: {[(hex(c), hex(s)) for c, s in found]}")

for cs, slide in found:
    print(f"\n===== callsite 0x{cs:x} ({lookup(cs)}) -> slide=0x{slide:x} =====")
    for fr in FRAMES:
        print(f"  0x{fr:x} -> {lookup(fr - slide)}")
