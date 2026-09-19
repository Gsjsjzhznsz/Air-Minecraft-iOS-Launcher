#!/usr/bin/env python3
"""Task107 独立复验：对 harness 产出的重签名 Mach-O 用纯 Python 重算
SuperBlob/CodeDirectory 布局与逐页 SHA-256 哈希（不依赖产线 C 代码）。
"""
import struct, hashlib, sys

def validate(path, orig_datasize):
    d = open(path, 'rb').read()
    magic, cputype, cpusub, ftype, ncmds, sizeofcmds, flags, res = struct.unpack_from('<IIIIIIII', d, 0)
    assert magic == 0xfeedfacf, hex(magic)
    off = 32; sig = None; bv = None
    for i in range(ncmds):
        cmd, cs = struct.unpack_from('<II', d, off)
        if cmd == 0x32: bv = off
        if cmd == 0x1d: sig = struct.unpack_from('<IIII', d, off)
        off += cs
    plat = struct.unpack_from('<I', d, bv + 8)[0]
    assert plat == 2, f'platform not retagged to IOS: {plat}'
    dataoff, datasize = sig[2], sig[3]
    sb = d[dataoff:dataoff + datasize]
    m, ln, cnt = struct.unpack_from('>III', sb, 0)
    assert m == 0xfade0cc0 and cnt == 1, hex(m)
    assert ln == datasize, f'superblob len {ln} != datasize {datasize}'
    tag, blo = struct.unpack_from('>II', sb, 12)
    assert tag == 0
    bm, bl = struct.unpack_from('>II', sb, blo)
    assert bm == 0xfade0c02, hex(bm)
    assert bl == ln - blo
    (ver, flg, hOff, iOff, nSpec, nCode, codeLim,
     hs, ht, plat_, ps) = struct.unpack_from('>IIIIIIIBBBB', sb, blo + 8)
    assert ver == 0x20400 and flg == 0x2, hex(flg)          # v0x20400 + CS_ADHOC
    assert ht == 2 and hs == 32 and ps == 12 and plat_ == 0  # SHA-256 / 4K 页
    assert codeLim == dataoff, (codeLim, dataoff)
    assert nSpec == 0
    ident_end = sb.index(b'\x00', blo + iOff)
    ident = sb[blo + iOff:ident_end].decode()
    assert ident == 'amethyst-retag', ident
    n_expect = (dataoff + 4095) // 4096
    assert nCode == n_expect, (nCode, n_expect)
    for i in range(nCode):
        p = i * 4096
        n = min(4096, dataoff - p)
        h = hashlib.sha256(d[p:p + n]).digest()
        got = sb[blo + hOff + 32 * i: blo + hOff + 32 * (i + 1)]
        assert h == got, f'page {i} hash mismatch'
    if datasize < orig_datasize:  # 原位路径：死区清零
        tail = d[dataoff + datasize: dataoff + orig_datasize]
        assert tail == b'\x00' * len(tail), 'dead zone not zeroed'
    print(f'VALID {path}: platform=2 datasize={datasize} (was {orig_datasize}) '
          f'nCodeSlots={nCode} hash=OK ident={ident}')
    return True

validate(sys.argv[1], int(sys.argv[2]))
