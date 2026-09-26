#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task175: insert the task175 announcement at index 2 (server/task169 pinned
at anns[0]/[1]; task174 and the rest shift down by one). House pattern from
task170_announcements.py / task168 sync scripts."""
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATH = os.path.join(REPO, "announcements.json")

doc = json.load(open(PATH, encoding="utf-8"))
anns = doc["announcements"]
ids = [a["id"] for a in anns]

NEW_ID = "task175-six-fixes-2026-09-26"
if NEW_ID in ids:
    print("already inserted, nothing to do")
    sys.exit(0)

entry = {
    "id": NEW_ID,
    "title": "六连修：ANGLE 着色器根修 / CF 下载量+整合包排序 / 主页头像 / 物品栏-分辨率 / 旧版 Forge 装包 / 新拟态壁纸共存",
    "date": "2026-09-26",
    "priority": "normal",
    "summary": (
        "针对最新装机反馈的六项根修。① ANGLE 渲染器闪退根因定稿：MC 26.3 的着色器管线"
        "经 spirv-cross 交叉编译回【桌面 GLSL 330】，而底下的 ANGLE 是 GLES3 上下文——"
        "桌面源在 ES 编译器上 1:1 语法报错，pipeline/gui 崩溃。本轮在 spirv-cross 垫片内"
        "闭环重写：桌面 GLSL 自动转 GLSL ES 300 再交给 ANGLE（仅 ANGLE 渲染器生效，"
        "mg/zink/vgpu 不受影响）。② CurseForge 下载量恒显 0 + 整合包列表不排序：字段名"
        "断层（downloadCount→downloads）与整合包路径漏传排序/加载器参数，双补。③ 主页头像"
        "切标签页回来才显示：初始主页实例从未注册进缓存，首次切回必新建实例重走全部时序"
        "病灶——注册修复。④ 物品栏/触控在更改分辨率后偏移：抓取态输入换算漏乘分辨率系数"
        "（历史会话恒 100% 从未暴露）+ 命中比例改单点写入防篡改。⑤ 旧版 Forge（≤1.12.2）"
        "整合包装载器安装 404 → 启动裸崩：maven 后缀形路径补候选（1.8.9 实锤 200）+ 启动"
        "前占位版本拦截弹窗。⑥ 新拟态开启时壁纸被整层盖住：画布接管退役，壁纸回归可见，"
        "双阴影自动切柔和档（偏移/模糊缩约 1/3 + 不透明度降档），照片上读作轻悬浮而非晕影。"
    ),
    "content": (
        "## 本轮六连修（装机反馈逐项根因）\n\n"
        "**① ANGLE 闪退 = 桌面 GLSL 送进了 GLES 编译器**\n\n"
        "- Task171/172 桥接与 Task173 桌面 GL 补全层生效后，游戏已能走到着色器编译阶段；"
        "本轮崩溃点后移到 minecraft:pipeline/gui：MC 26.3 把 GLSL 经 shaderc 编到 SPIR-V"
        "再由 spirv-cross 交叉编译回桌面 GLSL 330（它以为自己在桌面 GL 3.3 上），而"
        " tinygl4angle 底下是 ANGLE GLES3 上下文——ES 编译器对桌面版本号直接 1:1 语法"
        "报错。\n- 修复：spirv-cross 垫片内拦截编译出口，桌面源自动用同一份 SPIR-V 重开"
        "ES 编译器产出 GLSL ES 300（tinygl4angle 的 ES 直通分支原样上传）。仅"
        " AMETHYST_RENDERER 含 tinygl4angle 的会话生效；逃生阀 AME175_ANGLE_ES_REWRITE=0。\n"
        "- 装机锚点：\"[spvc-shim] Task175 ANGLE ES rewrite: desktop GLSL -> GLSL ES 300\""
        " + 不再出现 \"Couldn't compile vertex shader for pipeline\"。\n\n"
        "**② CF 下载量 + 整合包排序**\n\n"
        "- 下载量：CF 响应字段叫 downloadCount，UI 读的是 downloads——旧转换把字段整个"
        "丢了，所有 CF 条目恒显 0 次。已透传（镜像实测数据一直在响应里）。\n"
        "- 排序：侧栏的排序/加载器筛选从未传给整合包搜索（模组页一直有）——CF 与"
        " Modrinth 双源已补，选\"下载量/关注/更新\"即重排。\n\n"
        "**③ 主页头像（第五轮，这次有日志铁证）**\n\n"
        "- 装机日志实锤：初始主页实例从未注册进缓存，首次切标签页回来必然新建实例——"
        "此前三轮修的时序病灶全部在新实例上复发。已注册；另在转场落定后先重载个人卡"
        "再直写兜底。\n\n"
        "**④ 物品栏/触控偏移（分辨率 ≠100% 时）**\n\n"
        "- 抓取态（游戏内）的触点换算漏乘分辨率系数：50% 分辨率下游戏内触控/视角映射"
        "整体偏大一倍。已修（历史会话恒 100% 所以从未暴露）。\n- 物品栏命中矩形的比例"
        "改为启动器单点写入的全局值（旋转/分辨率/FSR 档位一体），并加了 guiScale 节流"
        "保鲜——改完界面尺寸立即生效，不用等开关一次菜单。\n- 装机锚点：\"[HotbarDiag]"
        " Task175 geometry snapshot\"（全量输入快照，下次再偏移凭这一行直接定位）。\n\n"
        "**⑤ 旧版 Forge 整合包（1.8.9 等 ≤1.12.2）**\n\n"
        "- 装包时 Forge installer 404（maven 对旧版晋升构建用\"版本号-MC版本\"后缀形"
        "路径）→ 写占位 JSON → 启动时裸 ClassNotFoundException。现在：补后缀形候选"
        "（1.8.9-11.15.1.2318 实锤可下）+ 启动前识别占位版本弹窗提示手动装 Forge，"
        "不再裸崩。\n- 另：装包/启动时若 JIT 已通过调试器启用（日志\"TXM debug JIT"
        " mapping active\"），则不会弹 JIT 申请——这是设计行为（已启用无需再申请），"
        "不是故障。\n\n"
        "**⑥ 新拟态 + 壁纸共存（画布接管退役）**\n\n"
        "- Task174 的\"开启即收起壁纸\"矫枉过正。现在：新拟态界面开启时壁纸照常显示，"
        "卡片保持实底规格表面，双阴影自动切【柔和档】（偏移/模糊缩约 1/3、不透明度"
        " 0.45/0.5）——照片上读作轻微悬浮感而非晕影；无壁纸时维持原规格档。\n"
        "- 装机锚点：\"[Task175] neumorph UI wallpaper coexist\"。\n\n"
        "EN: Six-fix round -- ANGLE shader chain root fix (desktop GLSL auto-rewritten to"
        " GLSL ES 300 for the GLES context), CurseForge download counts + modpack"
        " sort/loader filters, home avatar instance-cache registration, hotbar/touch"
        " resolution-scale fix, legacy-Forge (<=1.12.2) installer URL candidates +"
        " placeholder launch guard, and neumorphism-wallpaper coexistence with softened"
        " shadows. [Task175]"
    ),
}

anns.insert(2, entry)
json.dump(doc, open(PATH, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("inserted", NEW_ID, "at index 2; total", len(anns))
for i, a in enumerate(anns[:10]):
    print(i, a["id"])
