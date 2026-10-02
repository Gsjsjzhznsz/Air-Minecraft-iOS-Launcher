#!/usr/bin/env python3
"""Task212: remove the two holy-gl4es binary patch invocations from the Makefile
payload section (the dylib itself is deleted this round; its successor
libgl4eszl2.dylib is built from source and needs no binary surgery)."""
import sys

path = 'Makefile'
data = open(path, 'rb').read()
tab_before = data.count(b'\t')

lines = data.split(b'\n')
out = []
i = 0
removed = []
while i < len(lines):
    line = lines[i]
    if b'patch_gl4es_rtld_default.py' in line or b'patch_gl4es_ggstr_nullguard.py' in line:
        removed.append(i + 1)
        # also drop immediately preceding comment lines (walk backwards over already-emitted)
        while out and out[-1].startswith(b'\t#') and b'Task' in out[-1]:
            out.pop()
        i += 1
        continue
    out.append(line)
    i += 1

assert len(removed) == 2, f"expected 2 patch lines, found {removed}"

# insert the retirement note where the first patch line was (before the next
# non-comment payload line following position removed[0])
new_data = b'\n'.join(out)
note = ('\t# Task212：holy gl4es（libgl4es_114.dylib）退役删除——Task192 的 RTLD_DEFAULT\n'
        '\t# 补丁与 Task202 的 ggstr NULL 守卫两个二进制手术随 dylib 一并移除：接棒者\n'
        '\t# ZL2 经典版 gl4es（libgl4eszl2.dylib，dep_gl4eszl2 目标）从源码构建，\n'
        '\t# 构建期即带 Task208 三件套，无需任何 post-build 二进制补丁。\n').encode('utf-8')

# place note right before the "cp $(WORKINGDIR)/*.dylib" line in payload
anchor = b'\tcp $(WORKINGDIR)/*.dylib $(WORKINGDIR)/AngelAuraAmethyst.app/Frameworks/ || exit 1'
assert new_data.count(anchor) == 1, new_data.count(anchor)
new_data = new_data.replace(anchor, note + anchor)

tab_after = new_data.count(b'\t')
print(f'TABs: {tab_before} -> {tab_after} (removed {tab_before - tab_after})')
open(path, 'wb').write(new_data)
print('removed lines:', removed)
print('OK')
