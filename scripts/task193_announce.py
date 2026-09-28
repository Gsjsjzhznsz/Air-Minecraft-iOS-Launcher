#!/usr/bin/env python3
# Task 193 -- insert the announcement entry at index 2 (house convention: newest task entry sits at [2],
# the whole task-window family shifts down by one). Verified invariants:
#   [0] server-recommend pin untouched, [1] task169 untouched, [2] == task193-*, count 24 -> 25.
# Callers (re-anchored this round): verify_task173 M3 indices [3..11] -> [4..12]; verify_task190 [2] -> [3].
import json, collections

PATH = "announcements.json"

ENTRY = {
    "id": "task193-app-icon-replace-2026-09-28",
    "title": "启动器图标换新：上游 Amethyst 六边形 → 草方块立方体（Air 定制品牌第一步）",
    "date": "2026-09-28",
    "summary": "应用图标由上游遗留的浅蓝六边形替换为草方块立方体（用户上传素材）。仅替换实际生效的 Light 家族（1024×3 + 120 + 152）；Dark/Development 备用图标与 AppLogo-Vector 等上游资产按约定保持不动。",
    "content": "## 启动器图标换新\n\n- **新图标**：草方块立方体（绿顶棕底，用户上传的 IMG_9288.jpeg，690→LANCZOS 出 1024/152/120 全尺寸）\n- **替换范围（最小触碰）**：AppIcon-Light.appiconset 三张（universal/dark/tinted 外观同图三份，与上游做法一致）+ AppIcon-Light60x60@2x（iPhone 主图标）+ AppIcon-Light76x76@2x~ipad（iPad 主图标）+ README 顶部展示图自动跟随\n- **保持不动**：AppIcon-Dark / AppIcon-Development 备用三套、AppLogo-Vector、无引用的无后缀 AppIcon60x60/76x76 —— 全部为上游 2022/2025 遗留资产（blob 哈希与上游逐字节一致，本轮已查证归档）\n- **零代码改动**：图标为纯位图资源，仅文件名被引用（Contents.json/Info.plist 未动一行），同名覆盖即生效\n\nEN: The launcher icon is now the user-supplied grass-block cube (was the upstream Amethyst hexagon). Only the actually-served Light family was replaced (1024×3 + 120 + 152); Dark/Development alternates and AppLogo-Vector stay pristine upstream assets.\n\n---\n\n装机锚点：重装后桌面图标 = 草方块立方体（iPhone/iPad 一致，浅色/深色/着色外观同图）；设置页关于图标无变化（未动）。",
    "priority": "normal",
    "action_url": "",
    "action_title": "",
    "image_url": "",
}

def main():
    with open(PATH, encoding="utf-8") as f:
        data = json.load(f, object_pairs_hook=collections.OrderedDict)
    anns = data["announcements"]
    assert len(anns) == 24, f"expected 24 announcements, got {len(anns)}"
    assert anns[0]["id"].startswith("server-recommend"), "pin moved"
    assert anns[1]["id"] == "task169-four-fixes-2026-09-25", "index 1 moved"
    assert anns[2]["id"].startswith("task190-"), f"index 2 unexpected: {anns[2]['id']}"
    assert not any(a["id"] == ENTRY["id"] for a in anns), "duplicate id"

    anns.insert(2, collections.OrderedDict(ENTRY))
    with open(PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")

    # re-read and assert final order
    chk = json.load(open(PATH, encoding="utf-8"))["announcements"]
    assert len(chk) == 25
    assert chk[0]["id"].startswith("server-recommend")
    assert chk[1]["id"] == "task169-four-fixes-2026-09-25"
    assert chk[2]["id"] == ENTRY["id"]
    assert chk[3]["id"].startswith("task190-")
    assert chk[4]["id"].startswith("task184-")
    print("TASK193_ANNOUNCE_OK  (count 24 -> 25, task193@2, task190->3, task184->4)")

if __name__ == "__main__":
    main()
