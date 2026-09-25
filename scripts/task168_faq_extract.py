#!/usr/bin/env python3
# Task168：把 LauncherHelpViewController.m 的硬编码 FAQ 条目抽取为 help-faq.json
# （双文件对齐公告：仓库根 = 维护源，Natives/resources/ = 随包运行时读取）。
# 同时更新已被 Task166/167 推翻的过时结论（用户定稿"顺带更新过时项"）。
import json
import os
import re
import shutil
import sys

SRC = "Natives/LauncherHelpViewController.m"
ROOT_OUT = "help-faq.json"
BUNDLE_OUT = "Natives/resources/help-faq.json"

src = open(SRC, encoding="utf-8").read()

start = src.index("- (void)buildFaqData {")
end = src.index("\n}\n", start)
body = src[start:end]

# --- 抽取字段（相邻 @"..." 字面量串接；支持 \n \" \\ 转义） ---
LIT = re.compile(r'@"((?:[^"\\]|\\.)*)"')
FIELD = re.compile(r"\.(iconName|question|answer)\s*=\s*((?:\s*@\"(?:[^\"\\]|\\.)*\")+)\s*;")
ITEM_DECL = re.compile(r"LauncherHelpFaqItem \*(\w+) = \[\[LauncherHelpFaqItem alloc\] init\];")


def unescape(lit):
    out = []
    i = 0
    while i < len(lit):
        c = lit[i]
        if c == "\\" and i + 1 < len(lit):
            n = lit[i + 1]
            if n == "n":
                out.append("\n")
            elif n == '"':
                out.append('"')
            elif n == "\\":
                out.append("\\")
            elif n == "t":
                out.append("\t")
            else:
                out.append(n)
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


decls = list(ITEM_DECL.finditer(body))
items = {}
order = []
for i, m in enumerate(decls):
    name = m.group(1)
    seg_end = decls[i + 1].start() if i + 1 < len(decls) else body.index("self.categories", m.start())
    seg = body[m.end():seg_end]
    fields = dict(iconName=None, question=None, answer=None)
    for fm in FIELD.finditer(seg):
        fname, lits = fm.group(1), fm.group(2)
        parts = [unescape(x) for x in LIT.findall(lits)]
        fields[fname] = "".join(parts)
    assert fields["iconName"] and fields["question"] and fields["answer"], name
    items[name] = fields
    order.append(name)

# --- 分类装配 ---
tail = body[body.index("self.categories"):]
cats_m = re.search(r"self\.categories\s*=\s*@\[(.*?)\];", tail, re.S)
cat_names = [unescape(x) for x in LIT.findall(cats_m.group(1))]
groups_m = re.search(r"self\.itemsByCategory\s*=\s*@\[(.*?)\];", tail, re.S)
assert groups_m, "itemsByCategory not found"
group_src = groups_m.group(1)
groups = []
depth = 0
cur = ""
for ch in group_src:
    if ch == "@" and depth == 0:
        continue
    if ch == "[":
        depth += 1
        if depth == 1:
            cur = ""
            continue
    if ch == "]":
        depth -= 1
        if depth == 0:
            groups.append([v.strip() for v in cur.split(",") if v.strip()])
            continue
    if depth >= 1:
        cur += ch
assert len(groups) == len(cat_names), (len(groups), len(cat_names))

# --- 过时结论更新（用户定稿：顺带更新） ---
UPDATES = [
    (
        "fsr",
        "• mg 的 Vulkan 直连后端（MobileGL）/ 其它渲染器（MoltenVK/自动/gl4es 等）：暂不支持。Vulkan 直连无升采样呈现钩子，需要 FSR 请切到 GLES / OpenGL 4.0 后端、MobileGlues 或 Zink。",
        "• mg 的 Vulkan 直连后端（MobileGL）：已支持（Task166/167 起经 Metal 呈现层拦截放大，完整 FSR1 = EASU+RCAS，装机验证通过）；\n• 其它渲染器（MoltenVK/自动/gl4es 等）：暂不支持。",
    ),
    (
        "mgLag",
        "缓解办法（按性价比排序）：\n1. 换 Zink 渲染器（区块流式吞吐明显更高）；\n2. 开启 FSR 超分辨率降低渲染分辨率（见下条）；\n3. 视距保持 10 左右即可，调大只会放大加载风暴时长。",
        "缓解办法（按性价比排序）：\n1. 换 Vulkan 直连后端（MobileGL）并开 FSR 档位（Task166 起的推荐路径，加载区块期最流畅）；\n2. 换 Zink 渲染器（区块流式吞吐明显更高）；\n3. 开启 FSR 超分辨率降低渲染分辨率（见下条）；\n4. 视距保持 10 左右即可，调大只会放大加载风暴时长。",
    ),
]
for var, old, new in UPDATES:
    assert old in items[var]["answer"], (var, "old text not found")
    items[var]["answer"] = items[var]["answer"].replace(old, new)
    print(f"[updated] {var}")

# --- 生成 JSON ---
cats_out = []
for cname, gvars in zip(cat_names, groups):
    cat_items = []
    for v in gvars:
        assert v in items, v
        f = items[v]
        cat_items.append({"icon": f["iconName"], "title": f["question"], "description": f["answer"]})
    cats_out.append({"name": cname, "items": cat_items})

doc = {"categories": cats_out}
total = sum(len(c["items"]) for c in cats_out)
out = json.dumps(doc, ensure_ascii=False, indent=2) + "\n"
open(ROOT_OUT, "w", encoding="utf-8").write(out)
shutil.copyfile(ROOT_OUT, BUNDLE_OUT)
assert open(ROOT_OUT, "rb").read() == open(BUNDLE_OUT, "rb").read()

print(f"categories: {[ (c['name'], len(c['items'])) for c in cats_out ]}")
print(f"total items: {total}")
sizes = os.path.getsize(ROOT_OUT), os.path.getsize(BUNDLE_OUT)
print(f"bytes: root={sizes[0]} bundle={sizes[1]} (identical: {sizes[0]==sizes[1]})")
