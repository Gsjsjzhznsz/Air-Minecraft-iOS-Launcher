#!/usr/bin/env python3
# Task 193 -- app icon replacement (upstream Amethyst hexagon -> user grass-block cube).
# Scope: ONLY the Light family that iOS actually serves (1024x3 + 120 + 152). Everything
# else upstream stays pristine. Blob hashes below are content-addressed (stable forever).
import os, sys, io, json, struct, subprocess

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(REPO)

PASS, FAIL = [], []
def check(group, name, cond, detail=""):
    (PASS if cond else FAIL).append((group, name, detail))
    print(("  PASS " if cond else "  FAIL ") + f"[{group}] {name}" + ("" if cond else f"  -- {detail}"))

def blob(path):
    return subprocess.run(["git", "hash-object", path], capture_output=True, text=True).stdout.strip()

def png_size(path):
    with open(path, "rb") as f:
        head = f.read(33)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", head[16:24])

# ============ A. replaced files: valid PNG, exact dimensions ============
print("== A. 替换集尺寸与 PNG 完整性 ==")
A = [
    ("Natives/Assets.xcassets/AppIcon-Light.appiconset/1024x1024.png", 1024),
    ("Natives/Assets.xcassets/AppIcon-Light.appiconset/1024x1024-Transparent.png", 1024),
    ("Natives/Assets.xcassets/AppIcon-Light.appiconset/1024x1024-Monochrome-White.png", 1024),
    ("Natives/resources/AppIcon-Light60x60@2x.png", 120),
    ("Natives/resources/AppIcon-Light76x76@2x~ipad.png", 152),
]
for path, size in A:
    ok = os.path.exists(path) and png_size(path) == (size, size)
    check("A", f"{size}x{size}: {os.path.basename(path)}", ok, f"actual={png_size(path) if os.path.exists(path) else 'missing'}")

# ============ B. replaced-vs-upstream: blobs moved, trio same-image ============
print("== B. 替换断言（blob 已离开上游内容） ==")
UP_OLD = {
    "Natives/Assets.xcassets/AppIcon-Light.appiconset/1024x1024.png": "03f063d5b3d3e518503231e8ef616609dc31aa1b",
    "Natives/Assets.xcassets/AppIcon-Light.appiconset/1024x1024-Transparent.png": "03f063d5b3d3e518503231e8ef616609dc31aa1b",
    "Natives/Assets.xcassets/AppIcon-Light.appiconset/1024x1024-Monochrome-White.png": "03f063d5b3d3e518503231e8ef616609dc31aa1b",
    "Natives/resources/AppIcon-Light60x60@2x.png": "86bf1a2f7059bb24196a06ff9abd5e77937634d4",
    "Natives/resources/AppIcon-Light76x76@2x~ipad.png": "fd634b457a540b43ecf7ea26f1a2d5ac2f4f6118",
}
new_blobs = {}
for path, old in UP_OLD.items():
    b = blob(path)
    new_blobs[path] = b
    check("B", f"replaced: {os.path.basename(path)}", b != old, f"now={b[:12]} old={old[:12]}")
trio = {new_blobs[A[0][0]], new_blobs[A[1][0]], new_blobs[A[2][0]]}
check("B", "1024 三外观同图一份（与上游同约定）", len(trio) == 1, f"distinct={len(trio)}")

# ============ C. untouched: upstream heritage stays byte-identical ============
print("== C. 上游资产不动断言 ==")
UP_KEEP = {
    "Natives/Assets.xcassets/AppIcon-Dark.appiconset/AppIcon-Dark_1024x1024.png": "a0432d5fe04cc5c714b81960e8edfbada084c403",
    "Natives/Assets.xcassets/AppIcon-Development.appiconset/AppIcon-Development_1024x1024.png": "9075d45eb2cf7dd9b4c923fe86dce07d99bb0121",
    "Natives/resources/AppIcon-Dark60x60@2x.png": "201ad8f125b2647dcef91d6639706d62f6165049",
    "Natives/resources/AppIcon-Dark76x76@2x~ipad.png": "43ff9a88815ab269ed0848371ce625b548ad01c7",
    "Natives/resources/AppIcon-Development60x60@2x.png": "196e31c5ab0a5a8307482ada0a38539e964dd7a9",
    "Natives/resources/AppIcon-Development76x76@2x~ipad.png": "8df3c3566db65545e46148d64f725fafc8a92f62",
    "Natives/resources/AppIcon60x60@2x.png": "0260a341aede9e2efd395852abdfb55d4e1e635d",
    "Natives/resources/AppIcon76x76@2x~ipad.png": "d38f16e9f319f9f78b691de82c35a7c009f88c42",
    "Natives/Assets.xcassets/AppLogo-Vector.imageset/1024x1024-Transparent.png": "54d3a349d8c1ff3ab21c2e57794bf284c705db14",
    "Natives/Assets.xcassets/AppIcon-Light.appiconset/Contents.json": "4819ac371c028eefd057dbdb474f45bdd2935de9",
}
for path, up in UP_KEEP.items():
    b = blob(path)
    check("C", f"pristine: {os.path.basename(os.path.dirname(path))}/{os.path.basename(path)}", b == up, f"now={b[:12]} upstream={up[:12]}")

# ============ D. config purity: filename-referencing configs untouched in meaning ============
print("== D. 配置纯净度（引用未动） ==")
plist = io.open("Natives/Info.plist", encoding="utf-8", errors="replace").read()
check("D", "Info.plist iPhone 主图标仍为 AppIcon-Light60x60", "AppIcon-Light60x60" in plist)
check("D", "Info.plist iPad 主图标仍含 AppIcon-Light76x76", "AppIcon-Light76x76" in plist)
check("D", "Info.plist CFBundleIconName 仍为 AppIcon-Light", "<string>AppIcon-Light</string>" in plist)
check("D", "无后缀 AppIcon60x60 依旧零引用（不动它的依据）", "AppIcon60x60" not in plist)
vh = io.open("Natives/external/MobileGlues/MobileGlues-cpp/version.h", encoding="utf-8", errors="replace").read()
check("D", "version.h 含 Task 193 附录", "Amethyst Task 193" in vh)

# ============ E. provenance: source artwork + scripts present ============
print("== E. 素材与脚本溯源 ==")
check("E", "根目录 IMG_9288.jpeg 在场（用户上传源）", os.path.exists("IMG_9288.jpeg"))
if os.path.exists("IMG_9288.jpeg"):
    from PIL import Image
    try:
        im = Image.open("IMG_9288.jpeg"); im.load()
        check("E", "源图 690x690 可解码", im.size == (690, 690), f"actual={im.size}")
    except Exception as e:
        check("E", "源图 690x690 可解码", False, str(e))
for s in ("scripts/task193_icon.py", "scripts/task193_announce.py", "scripts/task193_docs.py", "scripts/verify_task193.py"):
    check("E", f"script: {os.path.basename(s)}", os.path.exists(s))

# ============ F. announcement: task193@2, family shifted, pin intact ============
print("== F. 公告窗口族 ==")
ann = json.loads(io.open("announcements.json", encoding="utf-8").read())["announcements"]
check("F", "条目数 24 -> 25", len(ann) == 25, f"actual={len(ann)}")
check("F", "task193 位于 [2]，task190 顺延至 [3]，置顶公告 [0] 未动",
      len(ann) > 3 and ann[2]["id"] == "task193-app-icon-replace-2026-09-28"
      and ann[3]["id"].startswith("task190-") and ann[0]["id"].startswith("server-recommend"))

# ============ G. re-anchored verifiers import-clean ============
print("== G. 重锚校验器语法完好 ==")
for v in ("scripts/verify_task173.py", "scripts/verify_task190.py"):
    src = io.open(v, encoding="utf-8").read()
    try:
        compile(src, v, "exec")
        check("G", f"{os.path.basename(v)} compile-ok", True)
    except SyntaxError as e:
        check("G", f"{os.path.basename(v)} compile-ok", False, str(e))

print(f"\n===== verify_task193: {len(PASS)} PASS / {len(FAIL)} FAIL =====")
sys.exit(1 if FAIL else 0)
