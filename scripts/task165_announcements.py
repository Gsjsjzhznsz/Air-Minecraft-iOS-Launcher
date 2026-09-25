#!/usr/bin/env python3
"""Task 165: prepend the real black-screen root-cause announcement.

The Task164 announcement pinned the RCAS edge-clamp theory; the cc9bfe4 log
pair disproved it (probe still 000000ff). This script adds a new pinned
announcement describing the actual root cause (Task154's LWJGL delegate
dlsym patch silently bypassing the MobileGlues frontend resolution) and the
fix, and rewords the Task164 entry's claim from "已修复" to the honest
"第一轮修复未愈" so the on-device narrative reads correctly.

Idempotent: exits 0 without writing when the task165 id is already present.
"""
import json
import sys

PATH = "announcements.json"
TASK165_ID = "task165-blackscreen-rootcause-2026-09-25"

task165 = {
    "id": TASK165_ID,
    "title": "ES / OpenGL 4.0 黑屏真根因修复（函数解析层）+ Vulkan FSR 结论",
    "date": "2026-09-25",
    "summary": "ES / OpenGL 4.0 后端黑屏的真正根因已找到并修复：此前的 LWJGL 兼容补丁让游戏的 GL 函数解析绕过了 MobileGlues 前端，画面被渲染进了错误的缓冲区，FSR 升采样把空帧盖在了真实画面上；现已恢复 5.1.0 的解析路由。Vulkan 直连后端的 FSR 经两轮二进制取证确认属上游硬限制，需要 FSR 请使用 GLES / OpenGL 4.0 后端（同样 60fps）。",
    "content": "## 本轮修复\n\n"
    "**ES / OpenGL 4.0 后端黑屏（真根因，重点修复）**\n\n"
    "- 症状：GLES / OpenGL 4.0 后端 + FSR 档位 = 整屏黑（渲染与交换计数全部健康，仅画面不显示）；上一轮的锐化边界修复未愈\n"
    "- 真根因：一个为兼容其他渲染器而打的 LWJGL 补丁，顺带改变了 MobileGlues 后端的函数解析路径——游戏的绘制调用绕过了渲染器前端的帧缓冲重定向，真实画面落在了错误的位置，FSR 升采样随即把空帧铺满全屏（黑屏但帧率正常即此形态）\n"
    "- 修复：前端补回补丁所需的解析入口，恢复 5.1.0 时代的解析路由；并加入两级保险——渲染纹理探针（下轮装机日志可直接分诊）与 RCAS 运行期熔断（锐化链异常时自动退回纯放大模式，宁可画质降档也不再黑屏）\n"
    "- 装机验证：GLES / 4.0 后端 + FSR 档位应恢复画面且更锐利；日志出现 `[MG] Task165 xglGetProcAddress: ... routed through the frontend`\n\n"
    "**FSR 支持矩阵（维持）**\n\n"
    "- ✅ **GLES 后端 / OpenGL 4.0 后端**：完整 FSR 1.0（EASU 放大 + RCAS 锐化），实测 60fps\n"
    "- ✅ **Zink 渲染器**：同一套 EASU + RCAS\n"
    "- ❌ **Vulkan 直连后端**：暂不支持（上游二进制零 FSR 接口、伪 EGL，两轮取证确认）。Vulkan 直连目前为全分辨率直呈（流畅）；需要 FSR 的画质/帧率取舍时请切 GLES / OpenGL 4.0 后端——两者同为 60fps 量级\n\n"
    "---\n\n"
    "Fixes: the real ES/OpenGL 4.0 black-screen root cause (the Task154 LWJGL delegate "
    "dlsym patch silently bypassing the MobileGlues frontend resolution route -- app draws "
    "missed the framebuffer-0 redirect and FSR1 painted sharpened zeros over the real "
    "frame); frontend now exports the dead-named lookup so the delegate routes gl* names "
    "through the layer again (other renderers keep Task154 semantics). Added a one-shot "
    "render-texture probe (layer-split diagnostics) and an RCAS runtime bail-out (first-frame "
    "black latches EASU-only for the session -- degrades to unsharpened upscale instead of "
    "a black screen). Vulkan-direct FSR confirmed upstream-blocked after binary forensics; "
    "use the GLES / OpenGL 4.0 backend for full FSR1 at 60fps.",
    "priority": "normal",
    "action_url": "",
    "action_title": "",
    "image_url": "",
}


def main():
    with open(PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
    anns = data["announcements"]
    if any(a.get("id") == TASK165_ID for a in anns):
        print(f"[task165] {TASK165_ID} already present -- no-op")
        return 0
    # Honest rewording of the Task164 claim: its fix did NOT heal the screen.
    for a in anns:
        if a.get("id") == "task164-fsr-blackscreen-defaults-2026-09-25":
            if "第一轮修复（锐化边界）" not in a.get("summary", ""):
                a["summary"] = (
                    "第一轮修复（锐化边界钳制）经装机验证未愈黑屏——真根因见后续公告"
                    "（函数解析层，Task165）；FSR 支持矩阵：GLES/4.0 后端 = 完整 FSR"
                    "（EASU 放大 + RCAS 锐化），Vulkan 直连暂不支持（上游限制）；"
                    "壁纸初次使用默认值确认为毛玻璃、透明度 60%、模糊 100%。"
                )
    data["announcements"].insert(0, task165)
    with open(PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write("\n")
    # sanity: reload must parse
    with open(PATH, "r", encoding="utf-8") as f:
        json.load(f)
    print(f"[task165] prepended {TASK165_ID}; task164 summary reworded; JSON valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
