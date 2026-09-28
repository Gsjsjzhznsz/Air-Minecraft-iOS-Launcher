#!/usr/bin/env python3
# Task 193 -- replace the launcher's visible app icon (Light family) with the
# user-uploaded IMG_9288.jpeg (grass-block cube, repo root).
#
# Scope decision (user's caution: upstream assets >1y old stay untouched):
#   REPLACED (the icon iOS actually shows + README header):
#     - Natives/Assets.xcassets/AppIcon-Light.appiconset/1024x1024.png            (1024x1024)
#     - Natives/Assets.xcassets/AppIcon-Light.appiconset/1024x1024-Transparent.png (dark appearance; upstream ships the SAME image in all three slots -> we mirror that)
#     - Natives/Assets.xcassets/AppIcon-Light.appiconset/1024x1024-Monochrome-White.png (tinted appearance; same image)
#     - Natives/resources/AppIcon-Light60x60@2x.png        (120x120, iPhone primary icon per Info.plist)
#     - Natives/resources/AppIcon-Light76x76@2x~ipad.png   (152x152, iPad primary icon per Info.plist)
#   UNTOUCHED (upstream heritage, unreferenced or dormant):
#     - AppIcon-Dark.appiconset + resources/AppIcon-Dark{60x60,76x76} (alternate icons, not reachable from the settings picker)
#     - AppIcon-Development.appiconset + resources/AppIcon-Development{60x60,76x76}
#     - AppLogo-Vector.imageset (no code reference)
#     - resources/AppIcon60x60@2x.png / AppIcon76x76@2x~ipad.png (referenced by NOTHING in Info.plist)
import subprocess, sys, io
from PIL import Image

SRC = "IMG_9288.jpeg"
TARGETS = [
    ("Natives/Assets.xcassets/AppIcon-Light.appiconset/1024x1024.png", 1024),
    ("Natives/Assets.xcassets/AppIcon-Light.appiconset/1024x1024-Transparent.png", 1024),
    ("Natives/Assets.xcassets/AppIcon-Light.appiconset/1024x1024-Monochrome-White.png", 1024),
    ("Natives/resources/AppIcon-Light60x60@2x.png", 120),
    ("Natives/resources/AppIcon-Light76x76@2x~ipad.png", 152),
]

def blob(path):
    return subprocess.run(["git", "hash-object", path], capture_output=True, text=True).stdout.strip()

def main():
    src = Image.open(SRC)
    src.load()
    assert src.size == (690, 690), f"unexpected source size {src.size}"
    if src.mode != "RGB":
        src = src.convert("RGB")

    print("== before ==")
    before = {}
    for path, size in TARGETS:
        before[path] = blob(path)
        print(f"  {before[path][:12]}  {path}")

    print("== writing ==")
    for path, size in TARGETS:
        im = src.resize((size, size), Image.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, format="PNG", optimize=True)
        data = buf.getvalue()
        with open(path, "wb") as f:
            f.write(data)
        # sanity: re-open and check dimensions + PNG magic
        chk = Image.open(path)
        assert data[:8] == b"\x89PNG\r\n\x1a\n", f"{path}: not a PNG"
        assert chk.size == (size, size), f"{path}: wrong size {chk.size}"
        print(f"  {size}x{size} -> {path} ({len(data)} bytes)")

    print("== after ==")
    for path, size in TARGETS:
        after = blob(path)
        tag = "CHANGED" if after != before[path] else "!!! UNCHANGED !!!"
        print(f"  [{tag}] {after[:12]}  {path}")
        assert after != before[path], f"{path} did not change"
    print("TASK193_ICON_OK")

if __name__ == "__main__":
    sys.exit(main())
