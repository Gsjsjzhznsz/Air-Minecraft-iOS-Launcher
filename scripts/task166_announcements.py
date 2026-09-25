#!/usr/bin/env python3
"""Task 166: prepend the Vulkan FSR + DSA black-screen announcement.

Two things happened this round:

1. Vulkan FSR shipped. The Task154/165 "upstream hard limit" verdict was
   re-litigated against the (newly found) open-source upstream
   MobileGL-Dev/MobileGL and overturned *for the presentation side*: while
   libMobileGL still has no built-in FSR, MoltenVK consumes the CAMetalLayer
   through a ObjC protocol (id<CAMetalDrawable>) -- so the launcher now
   intercepts presentation with a private swap layer (render-res) and runs
   AMD FSR1 EASU+RCAS in Metal on the way to the real display layer. The
   Task154 pre-swap GL war stays retired (pseudo-EGL root cause unchanged;
   double-upscale guard).

2. The ES/OpenGL 4.0 black screen (survived Task164 and Task165 fixes) is
   actually the forced DSA default: three-session A/B on the same device,
   same modpack, same MobileGlues 2.0.17 -- DSA=0 playable (9e6fc27 pair),
   DSA=1 black. Task129d enabled it citing zink (Mesa native DSA), which
   never applied to MobileGlues' DSAWrapper emulation. Default now OFF with
   a one-shot reverse migration (1 -> 0); the preference toggle remains.

This script also honestly rewords the Task165 announcement's FSR matrix
(Vulkan row flips from "not supported" to "supported via Task166 Metal
layer") and its "use GLES/4.0 for FSR at 60fps" advice -- the user has
clarified both backends are unplayably laggy during chunk loading, so
Vulkan is the only smooth backend and now also has FSR.

Idempotent: exits 0 without writing when the task166 id is already present.
"""
import json
import sys

PATH = "announcements.json"
TASK166_ID = "task166-vulkan-fsr-dsa-2026-09-25"

task166 = {
    "id": TASK166_ID,
    "title": "Vulkan 后端 FSR 上线（Metal 层方案）+ ES/4.0 黑屏 DSA 根因修复",
    "date": "2026-09-25",
    "summary": "Vulkan 直连后端现已支持 FSR 超分辨率（AMD FSR 1.0：EASU 放大 + RCAS 锐化）——以 Metal 呈现层拦截方案实现，渲染器与 MoltenVK 二进制零改动；这是唯一在加载区块时保持流畅的后端，现在画质与流畅可以兼得。同时修复 ES / OpenGL 4.0 后端残留黑屏的真根因：一项默认开启的 GL 扩展（DSA）在该路径下触发黑屏，已改回关闭并自动迁移存量设置。",
    "content": "## 本轮修复\n\n"
    "**Vulkan 直连后端 FSR（重点新功能）**\n\n"
    "- 背景：GLES / OpenGL 4.0 后端在加载区块时严重卡顿（无解），Vulkan 直连是唯一流畅的后端；此前公告中\"需要 FSR 请切换 GLES / 4.0 后端\"的建议因此作废\n"
    "- 实现：呈现层拦截——私有交换层以渲染分辨率接入 MoltenVK 交换链，每帧呈现时在 Metal 层执行 AMD FSR 1.0（EASU 放大 + RCAS 锐化，AMD 参考实现逐位移植）后写入全分辨率显示层；渲染器与 MoltenVK 二进制零改动\n"
    "- 联动：FSR 档位设置（画面设置内的渲染缩放）对 Vulkan 后端生效；RCAS 锐化强度设置沿用同一滑条\n"
    "- 降级保护：任何一步初始化失败自动回退全分辨率直呈（此前语义）；装机日志锚点 `[MGLFSR] Task166 Metal FSR engaged`\n"
    "- 覆盖范围：仅 Vulkan 直连后端；libMobileGL-gles 变体维持全分辨率直呈\n\n"
    "**ES / OpenGL 4.0 黑屏（真根因第二轮，装机实证）**\n\n"
    "- 三组同机同模组包会话对照锁定唯一配置差异：GL 直连状态访问扩展（DSA）关闭 = 全程可玩，开启 = 黑屏（交换链健康、帧率正常、画面不显示）\n"
    "- 机理：渲染器的 DSA 兼容层与 FSR 帧缓冲重定向路径自洽性不足，游戏检测到该扩展即切换渲染路径，画面落在错误位置\n"
    "- 当年开启它的性能依据来自另一渲染器（zink 原生支持），与该后端无关\n"
    "- 修复：默认改回关闭 + 存量设置一次性迁移（开启 -> 关闭）；偏好分区的高级开关保留，可手动开回\n\n"
    "**FSR 支持矩阵（更新）**\n\n"
    "- ✅ **Vulkan 直连后端**：完整 FSR 1.0（EASU + RCAS，Metal 层方案），加载区块保持流畅 —— 推荐首选\n"
    "- ✅ **GLES 后端 / OpenGL 4.0 后端**：完整 FSR 1.0（渲染器内置）；注意两后端在加载区块时存在卡顿\n"
    "- ✅ **Zink 渲染器**：同一套 EASU + RCAS\n"
    "- ➖ **libMobileGL-gles**：全分辨率直呈（不在本期范围）\n"
    "- 装机验证锚点：`[MGLFSR] Task166 Metal FSR engaged`（Vulkan + FSR 档位）与 `[MGLFSR] Task166 first frame presented`；GLES / 4.0 后端应恢复画面（DSA 已关）\n\n"
    "---\n\n"
    "Fixes: Vulkan-direct backend gains full FSR1 (EASU upscale + RCAS sharpen) via a "
    "Metal presentation-layer intercept -- a private CAMetalLayer feeds MoltenVK a "
    "render-res swapchain while a wrapped id<CAMetalDrawable> runs the AMD reference "
    "EASU/RCAS port into the full-res display layer (zero changes to the MobileGL/"
    "MoltenVK binaries; the Task154 pre-swap GL war stays retired, pseudo-EGL root "
    "cause unchanged and double-upscale guarded). The surviving ES/OpenGL 4.0 black "
    "screen root cause is the forced enable_ext_direct_state_access default: "
    "three-session A/B on identical device/modpack/MobileGlues 2.0.17 shows DSA=0 "
    "playable (9e6fc27 pair) vs DSA=1 black with healthy swap counters; Task129d's "
    "perf rationale came from zink's native Mesa DSA, not MobileGlues' DSAWrapper "
    "emulation. Default flipped to OFF with a one-shot 1->0 reverse migration "
    "(ame166_migrateMgDsaBlackScreen); the preference toggle remains for manual "
    "override. Task129/130 verifiers re-anchored (D1/D3, E9/E10).",
    "priority": "normal",
    "action_url": "",
    "action_title": "",
    "image_url": "",
}


def main():
    with open(PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
    anns = data["announcements"]
    if any(a.get("id") == TASK166_ID for a in anns):
        print(f"[task166] {TASK166_ID} already present -- no-op")
        return 0

    # Honest rewording of the Task165 FSR matrix: the Vulkan row and the
    # "switch to GLES/4.0 for FSR" advice are both obsolete after Task166
    # (and the user clarified both backends lag badly during chunk loading).
    for a in anns:
        if a.get("id") == "task165-blackscreen-rootcause-2026-09-25":
            a["content"] = a["content"].replace(
                "- ❌ **Vulkan 直连后端**：暂不支持（上游二进制零 FSR 接口、伪 EGL，两轮取证确认）。"
                "Vulkan 直连目前为全分辨率直呈（流畅）；需要 FSR 的画质/帧率取舍时请切 GLES / OpenGL 4.0 后端——两者同为 60fps 量级",
                "- ✅ **Vulkan 直连后端**：已支持（Task166 Metal 层方案：EASU + RCAS，二进制零改动）——"
                "见后续公告；GLES / 4.0 后端在加载区块时存在卡顿，Vulkan 是流畅首选",
            )
            a["content"] = a["content"].replace(
                "需要 FSR 的画质/帧率取舍时请切 GLES / OpenGL 4.0 后端——两者同为 60fps 量级",
                "（Task166 更新：Vulkan 直连已支持 FSR，推荐使用）",
            )
            a["content"] += (
                "\n\n**Task166 追记**：本公告发布时的 FSR 结论已被 Task166 推翻——"
                "上游开源事实（MobileGL-Dev/MobileGL）+ Metal 呈现层拦截方案令 "
                "Vulkan 直连后端获得完整 FSR 1.0；ES/4.0 黑屏的真根因亦在 Task166 "
                "定位为强制开启的 DSA 默认值（与本公告的解析层修复叠加存在）。"
            )
            print("[task166] task165 matrix reworded (Vulkan row + advice)")

    anns.insert(0, task166)
    with open(PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    print(f"[task166] prepended {TASK166_ID} (total {len(anns)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
