#!/usr/bin/env python3
"""Task 167: prepend the task167 announcement + append an honest addendum to
the task166 entry (both fixes failed on device; superseded by Task 167)."""
import json

PATH = "/home/z/my-project/Amethyst-iOS-MyRemastered/announcements.json"
d = json.load(open(PATH, encoding="utf-8"))
anns = d["announcements"]

# 1) Remove any pre-existing task167 entry (idempotent re-run)
anns[:] = [a for a in anns if a.get("id") != "task167-crashfix-migration-2026-09-25"]

task167 = {
    "id": "task167-crashfix-migration-2026-09-25",
    "title": "上一版两处修复的失效根因修复（Vulkan 崩溃 + ES/4.0 黑屏迁移未执行）",
    "date": "2026-09-25",
    "summary": "上一版实测：Vulkan 崩溃、ES/4.0 仍黑屏。两个失效根因均已定位并修复：Vulkan 崩溃 = 交换层只设了 drawableSize 没设 bounds，而 MoltenVK 的表面尺寸真源是 bounds × contentsScale，零尺寸导致交换链被跳过、首个画面拷贝踩空指针；ES/4.0 = DSA 迁移挂在了一个系统几乎不会再调用的回调里（从未执行），且旧默认值早已被持久化。本轮修复后 Vulkan FSR 与 ES/4.0 黑屏修复应真正生效。",
    "content": (
        "## 本轮修复（上一版装机实测反馈处理）\n\n"
        "**Vulkan 崩溃（上一版新引入，本轮根治）**\n\n"
        "- 现象：Vulkan 后端启动即崩溃（首个画面帧之前），崩溃点在渲染器交换链图像管理内部\n"
        "- 根因：FSR 私有交换层创建时只设置了 drawableSize，没有设置 bounds；而 MoltenVK 读取表面尺寸走的是"
        " bounds × contentsScale（drawableSize 不参与能力查询）——零尺寸被渲染器的保护逻辑判定为"
        " \"零面积窗口\"，交换链整个被跳过；随后游戏的第一个全屏拷贝指令在空交换链上取图像，踩中空指针\n"
        "- 取证：对随包渲染器二进制反汇编，崩溃指令与装机崩溃地址逐字节吻合；渲染器开源上游源码逐行核对确认保护链\n"
        "- 修复：交换层三处几何写入点（创建/同步/尺寸更新钩子）全部补齐 bounds + contentsScale，"
        " 交换链恢复正常创建，FSR 升采样链路随即完整可用\n\n"
        "**ES / OpenGL 4.0 黑屏（上一版修复未生效的根因，本轮补上）**\n\n"
        "- 现象：上一版已把 DSA 默认改关并写了存量迁移，但装机日志显示 DSA 仍然开启、迁移日志从未出现\n"
        "- 根因一：迁移挂在\"场景会话配置\"回调里——该回调只在系统新建场景会话时触发，"
        " 老设备上永远不会执行（历史装机日志中该回调内的任何日志从未出现过）\n"
        "- 根因二：更早版本\"DSA 默认开\"时代的默认值早已随启动写进配置文件持久化，"
        " 新默认值被存量值压制\n"
        "- 修复：迁移挪到进程启动必经路径（读取生效配置之后、任何使用之前），"
        " 判定兼容数字/字符串两种存储形态，并新增执行锚点日志\n"
        "- 装机验证：启动器启动时应出现 `[Preferences] Task167 MG DSA black-screen migration ran (stored=1, flipped=1)`，"
        " 随后 GLES / 4.0 进世界应显示画面（游戏日志出现 DSA support not detected）\n\n"
        "**装机验证清单**\n\n"
        "- Vulkan 后端 + FSR 档位：不再崩溃；日志出现 `[MGLFSR] Task166 Metal FSR engaged` 与"
        " `first frame presented`；画质放大生效（区块加载保持流畅）\n"
        "- ES / OpenGL 4.0 后端：启动器启动日志出现 Task167 迁移行；进世界有画面\n"
        "- 如需临时关闭 Vulkan 的 Metal 层 FSR 做对照：环境变量 `AME166_MGL_METAL_FSR=0`\n\n"
        "---\n\n"
        "Fixes: both Task 166 fixes had failed on device (upload 1b76d19: Vulkan crashed at startup, "
        "GLES/4.0 still black). Vulkan crash: MoltenVK's surface extent comes from the CAMetalLayer "
        "category property naturalDrawableSizeMVK = bounds x contentsScale (not drawableSize); Layer B "
        "had zero bounds, so MobileGL's zero-area guard installed no swapchain and the first DSA "
        "glBlitNamedFramebuffer(fb0) dereferenced an empty image vector (disassembly of the shipping "
        "dylib matches the crash pc at GetImage+0x28 byte-for-byte). Layer B now writes bounds + "
        "contentsScale(1.0) at all three geometry sites. Black screen: the DSA reverse migration was "
        "wired into application:configurationForConnectingSceneSession: which UIKit never calls again "
        "for existing scene sessions (zero evidence across 60+ uploaded logs), while the Task129d-era "
        "@YES default had been persisted into the plist by the defaults merge -- the stored 1 kept "
        "suppressing the fresh @NO default. The always-run call site now lives in main.m after "
        "toggleIsolatedPref, with dual-type tolerance and an unconditional run-anchor log."
    ),
    "priority": 100,
    "action_url": "",
    "action_title": "",
    "image_url": "",
}
anns.insert(0, task167)

# 2) Honest addendum on the task166 entry
for a in anns:
    if a.get("id") == "task166-vulkan-fsr-dsa-2026-09-25":
        addendum = (
            "\n\n---\n\n**勘误（装机实测后补记）**：本条发布后装机实测发现两处缺陷——"
            "Vulkan 后端启动即崩溃（交换层 bounds 未设置，交换链被零面积保护跳过），"
            "ES / 4.0 的 DSA 迁移因挂载点在既有场景会话设备上永不执行而未生效。"
            "两处根因与修复见下一条公告（Task 167）。本条中的功能描述与支持矩阵以修复后的实际表现为准。"
        )
        if "勘误（装机实测后补记）" not in a["content"]:
            a["content"] += addendum
        break

json.dump(d, open(PATH, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("announcements:", len(anns))
print("top:", anns[0]["id"])
