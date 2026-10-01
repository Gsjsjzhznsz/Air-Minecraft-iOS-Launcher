#!/usr/bin/env python3
"""task206_faq_update.py -- FAQ updates for the NG-GL4ES renderer (Task206).

(a) refresh the renderer-selection item (categories[0].items[0]) with an
    NG-GL4ES bullet + updated rule of thumb;
(b) insert a dedicated NG-GL4ES item at categories[0] index 2 (right after
    the LTW item, same cluster) -- 11/4/7/15 -> 12/4/7/15 (total 38);
(c) keep the root twin byte-identical (verify_task168 C1 contract).

Format fidelity: all five files round-trip byte-identically through
json.dumps(ensure_ascii=False, indent=N) + "\\n" (verified before writing);
root/zh-CN use indent 2, en/zh-Hant indent 1.
"""
import json
from pathlib import Path

REPO = Path(".")

# ---------------------------------------------------------------- content
SEL_BULLET = {
    "zh": "• NG-GL4ES：ZL2 启动器同款的 gl4es（Krypton Wrapper），着色器经 glslang+SPIRV-Cross 双段转译，官方口径几乎全版本 MC 可跑（老版本到 26.x）；接替 VGPU 的位置——老版本遇到材质损坏、图集错位时优先换它；",
    "ht": "• NG-GL4ES：ZL2 啟動器同款的 gl4es（Krypton Wrapper），著色器經 glslang+SPIRV-Cross 雙段轉譯，官方口徑幾乎全版本 MC 可跑（舊版本到 26.x）；接替 VGPU 的位置——舊版本遇到材質損壞、圖集錯位時優先換它；",
    "en": "• NG-GL4ES: the gl4es used by ZalithLauncher 2 (Krypton Wrapper); shaders go through a glslang+SPIRV-Cross pipeline, and upstream claims almost every MC version runs (old versions through 26.x); it replaces VGPU -- if you hit corrupted textures or broken atlases on legacy versions, switch here first;",
}
RULE_OLD = {
    "zh": "简单记法：玩新版本/整合包用 Zink；老版本/轻量场景用 MobileGlues 或 LTW；需要 Vulkan 后端时选 MoltenVK。",
    "ht": "簡單記法：玩新版本/整合包用 Zink；老版本/輕量場景用 MobileGlues 或 LTW；需要 Vulkan 後端時選 MoltenVK。",
    "en": "Rule of thumb: new versions / modpacks → Zink; older versions / lightweight play → MobileGlues or LTW; choose MoltenVK when you want the Vulkan backend.",
}
RULE_NEW = {
    "zh": "简单记法：玩新版本/整合包用 Zink；老版本优先 NG-GL4ES（轻量场景也可 MobileGlues/LTW）；需要 Vulkan 后端时选 MoltenVK。",
    "ht": "簡單記法：玩新版本/整合包用 Zink；老版本優先 NG-GL4ES（輕量場景也可 MobileGlues/LTW）；需要 Vulkan 後端時選 MoltenVK。",
    "en": "Rule of thumb: new versions / modpacks → Zink; older versions → NG-GL4ES first (MobileGlues / LTW for lightweight play); choose MoltenVK when you want the Vulkan backend.",
}
NEW_ITEM = {
    "zh": {
        "icon": "cpu",
        "title": "NG-GL4ES 是什么？和 VGPU、gl4es 什么关系？",
        "description": "NG-GL4ES（Krypton Wrapper）是 ZalithLauncher 2 所用的 gl4es 分支：桌面 OpenGL 转译到 OpenGL ES，着色器经 glslang（GLSL→SPIR-V）+ SPIRV-Cross（SPIR-V→ESSL）双段转换，与 VGPU 的内置转换管线不同路。\n\n什么时候选它：\n• 老版本（1.8.9 等 Forge 生态）在 VGPU 下出现材质损坏、图集错位、条纹（该病灶两轮修复未根除，属转译层顽疾）——换 NG-GL4ES 是首选对策；\n• 官方口径几乎全版本 MC 可跑，26.x 新版本也可尝试（不行再换 Zink）；\n• 进阶参数可放 config.json 于游戏目录 ngg/ 下（一般用不到）。\n\n选择路径：设置 → 视频设置 → 渲染器 → NG-GL4ES（游戏未运行时才能改）。",
    },
    "ht": {
        "icon": "cpu",
        "title": "NG-GL4ES 是什麼？和 VGPU、gl4es 什麼關係？",
        "description": "NG-GL4ES（Krypton Wrapper）是 ZalithLauncher 2 所用的 gl4es 分支：桌面 OpenGL 轉譯到 OpenGL ES，著色器經 glslang（GLSL→SPIR-V）+ SPIRV-Cross（SPIR-V→ESSL）雙段轉換，與 VGPU 的內建轉換管線不同路。\n\n什麼時候選它：\n• 舊版本（1.8.9 等 Forge 生態）在 VGPU 下出現材質損壞、圖集錯位、條紋（該病灶兩輪修復未根除，屬轉譯層頑疾）——換 NG-GL4ES 是首選對策；\n• 官方口徑幾乎全版本 MC 可跑，26.x 新版本也可嘗試（不行再換 Zink）；\n• 進階參數可放 config.json 於遊戲目錄 ngg/ 下（一般用不到）。\n\n選擇路徑：設定 → 影像設定 → 渲染器 → NG-GL4ES（遊戲未執行時才能改）。",
    },
    "en": {
        "icon": "cpu",
        "title": "What is NG-GL4ES? How does it relate to VGPU and gl4es?",
        "description": "NG-GL4ES (Krypton Wrapper) is the gl4es fork used by ZalithLauncher 2: it translates desktop OpenGL to OpenGL ES, with shaders converted through a glslang (GLSL to SPIR-V) + SPIRV-Cross (SPIR-V to ESSL) pipeline -- a different road from VGPU's built-in converter.\n\nWhen to pick it:\n• legacy versions (1.8.9-era Forge) showing corrupted textures, broken atlases or stripes under VGPU (two fix rounds did not root that out; it is a translation-layer defect) -- switching to NG-GL4ES is the first countermeasure;\n• upstream claims almost every MC version runs, including 26.x (fall back to Zink if not);\n• advanced tuning can go into config.json under ngg/ in the game directory (rarely needed).\n\nWhere: Settings -> Video -> Renderer -> NG-GL4ES (only changeable while the game is not running).",
    },
}

FILES = [
    ("Natives/resources/help-faq.json", 2, "zh"),
    ("help-faq.json", 2, "zh"),                                  # root twin
    ("Natives/resources/zh-CN.lproj/help-faq.json", 2, "zh"),
    ("Natives/resources/zh-Hant.lproj/help-faq.json", 1, "ht"),
    ("Natives/resources/en.lproj/help-faq.json", 1, "en"),
]

for rel, indent, lang in FILES:
    p = REPO / rel
    raw = p.read_bytes()
    faq = json.loads(raw.decode("utf-8"))
    cat0 = faq["categories"][0]

    # (a) renderer-selection item refresh
    sel = cat0["items"][0]
    assert "渲染器" in sel["title"] or "renderer" in sel["title"].lower(), rel
    if "NG-GL4ES" not in sel["description"]:
        d = sel["description"]
        # insert the bullet right after the LTW bullet (same cluster);
        # per-language anchors: zh-Hans/zh-CN "见下一条"， zh-Hant "見下一條"
        anchor_zh = "不支持 MC 26.x（见下一条）；"
        anchor_zh_hant = "不支持 MC 26.x（見下一條）；"
        anchor_en = "MC 26.x is not supported (see the next entry)."
        if lang == "ht":
            assert anchor_zh_hant in d, f"{rel}: LTW bullet anchor missing"
            d = d.replace(anchor_zh_hant, anchor_zh_hant + "\n" + SEL_BULLET[lang], 1)
        elif lang == "zh":
            assert anchor_zh in d, f"{rel}: LTW bullet anchor missing"
            d = d.replace(anchor_zh, anchor_zh + "\n" + SEL_BULLET[lang], 1)
        else:
            assert anchor_en in d, f"{rel}: LTW bullet anchor missing"
            d = d.replace(anchor_en, anchor_en + "\n" + SEL_BULLET[lang], 1)
        assert RULE_OLD[lang] in d, f"{rel}: rule-of-thumb anchor missing"
        d = d.replace(RULE_OLD[lang], RULE_NEW[lang], 1)
        sel["description"] = d

    # (b) dedicated item at index 2 (after the LTW item)
    if not any("NG-GL4ES" in i["title"] for i in cat0["items"]):
        cat0["items"].insert(2, dict(NEW_ITEM[lang]))

    out = (json.dumps(faq, ensure_ascii=False, indent=indent) + "\n").encode("utf-8")
    p.write_bytes(out)
    counts = [len(c["items"]) for c in faq["categories"]]
    print(f"{rel}: counts={counts} total={sum(counts)}")

# (c) root twin byte-identity
assert (REPO / "help-faq.json").read_bytes() == (REPO / "Natives/resources/help-faq.json").read_bytes()
print("root twin byte-identity: OK")
