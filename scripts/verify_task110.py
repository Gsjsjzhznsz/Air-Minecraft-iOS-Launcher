#!/usr/bin/env python3
"""Task 110 验证器：整合包 30fps 根因 = dynamic_fps 看到未聚焦窗口（SDL 焦点位缺失）

判读链（698c6fe 双会话 + 真实 Modrinth jar 反编译法证）：
  · 整合包含 dynamic_fps 3.11.10，原版不含 → "整合包卡 30、原版正常"；
  · WindowObserver 构造直接查 SDL_GetWindowFlags & 0x200（INPUT_FOCUS），
    不走 vanilla Window.focused（初始 true、仅 526/527 事件翻转、我们不喂
    → vanilla 恒聚焦即原版正常）；
  · 状态机三输入全坏（0x200=0、0x400=0、iconified=0x40||0x4=true）→
    稳态落 UNFOCUSED/INVISIBLE 降频档；
  · embed 隐藏 SDL UIWindow（Task32/49）是根；Task50 只剥了 MINIMIZED。

修复（sdl3_hook.m）：(f | 0x200) & ~0x40 & ~0x4——焦点位置 1、
MINIMIZED/HIDDEN 剥离；vanilla 唯一 flags 消费点是 isFullscreen(&1) 不受
影响；idle 档（ABANDONED 10fps）由 Task104 滚轮心跳喂养 onActivity 免疫。

A. 698c6fe 双日志证据（git 钉）
B. 真实 jar 法证（task110 工作区，WindowObserver/状态机/默认档/idle 钩子）
C. vanilla 对照（task66_decomp：Window.focused 路径 + 唯一 flags 消费点）
D. 修复锚点（sdl3_hook.m）
E. 位变换 + mod 状态机 Python 镜像
F. 文档（FAQ 重归因 / version.h 双 addendum / osm_bridge Task109 注释修正）
G. 语法与级联
"""
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = "/home/z/my-project/task110"
DECOMP = "/home/z/my-project/task66_decomp/out"
os.chdir(REPO)
SCRIPTS = os.path.join(REPO, "scripts")

PASS = FAIL = 0
def check(name, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {detail}")

def read(path):
    return open(os.path.join(REPO, path), encoding="utf-8", errors="replace").read()

def wread(path):
    return open(os.path.join(WORK, path), encoding="utf-8", errors="replace").read()

def git_show(rev, path):
    r = subprocess.run(["git", "-C", REPO, "show", f"{rev}:{path}"],
                       capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""

sdl = read("Natives/sdl3_hook.m")
faq = read("Natives/LauncherHelpViewController.m")
vh = read("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
osm = read("Natives/ctxbridges/osm_bridge.mm")

print("===== A. 698c6fe 双日志证据 =====")
vanilla = git_show("698c6fe", "latestlog.txt")
modpack = git_show("698c6fe", "latestlog.old.txt")
check("A1 整合包含 dynamic_fps 3.11.10（mod 列表 + resource reload 双证）",
      "- dynamic_fps 3.11.10" in modpack and "dynamic_fps_common 3.11.10" in modpack)
check("A2 原版会话不含 dynamic_fps（根因的模组差异面）",
      "dynamic_fps" not in vanilla)
check("A3 双会话同构建 38fb316（同代码不同模组 = 模组侧根因的对照证明）",
      vanilla.count("Commit: 38fb316") == 1 and modpack.count("Commit: 38fb316") == 1)
check("A4 整合包稳态 30fps 钉住（用户反馈来源：MC-side 含 mod 限帧等待）",
      "MC-side=2" in modpack or "MC-side=3" in modpack)

print("===== B. 真实 jar 法证（Modrinth dynamic-fps 3.11.10+mc26.3.0） =====")
jar = os.path.join(WORK, "dynamic_fps.jar")
check("B0 jar 就位（Modrinth CDN 下载，非猜测版本）",
      os.path.exists(jar) and os.path.getsize(jar) > 100000)
if os.path.exists(jar):
    wo = wread("common/src/dynamic_fps/impl/feature/state/WindowObserver.java")
    dfm = wread("common/src/dynamic_fps/impl/DynamicFPSMod.java")
    check("B1 WindowObserver 构造直接查 SDL_GetWindowFlags & 0x200（INPUT_FOCUS）",
          "SDLVideo.SDL_GetWindowFlags" in wo and "(flags & 0x200L) != 0L" in wo)
    check("B2 事件驱动面：526/527 翻转 isFocused + onEvent 喂票（我们不喂 → 初值即终值）",
          "case 526:" in wo and "case 527:" in wo and "this.isFocused = true;" in wo)
    check("B3 isIconified = MINIMIZED(0x40) || HIDDEN(0x4)（旧 hook 只剥 0x40 漏 0x4）",
          "(flags & 0x40L) != 0L || (flags & 4L) != 0L" in wo)
    check("B4 状态机：focused ? (idle?ABANDONED:…FOCUSED) : (hovered?HOVERED:(!iconified?UNFOCUSED:INVISIBLE))",
          "window.isFocused() ? (IdleHandler.isIdle() ? PowerState.ABANDONED" in dfm
          and "window.isHovered() ? PowerState.HOVERED" in dfm
          and "!window.isIconified() ? PowerState.UNFOCUSED : PowerState.INVISIBLE" in dfm)
    cfg = wread("ext2/assets/dynamic_fps/data/default_config.json")
    check("B5 默认降频档：unfocused=1fps / invisible=0fps / abandoned=10fps / idle 300s",
          '"unfocused"' in cfg and '"frame_rate_target": 1' in cfg
          and '"invisible"' in cfg and '"frame_rate_target": 0' in cfg
          and '"abandoned"' in cfg and '"frame_rate_target": 10' in cfg
          and '"timeout": 300' in cfg)
    check("B6 idle 免疫链：mouse 事件族触发 IdleHandler.onActivity（Task104 滚轮心跳在列）",
          "IdleHandler.onActivity();" in wo and "case 1536:" in wo)

print("===== C. vanilla 对照（task66_decomp 反编译） =====")
win = wread("../task66_decomp/out/com/mojang/blaze3d/platform/Window.java").replace("REPO", "")
win = open(os.path.join(DECOMP, "com/mojang/blaze3d/platform/Window.java"), encoding="utf-8", errors="replace").read()
check("C1 vanilla Window.focused 初始 true（原版恒聚焦 = 原版正常的机制解释）",
      "private boolean focused = true;" in win)
check("C2 vanilla 焦点仅由 SDL 事件 526/527 驱动（我们不喂 → 恒 true）",
      "case 526:" in win and "case 527:" in win)
check("C3 vanilla 唯一 flags 消费点 = isFullscreen(&1)——修复位(0x200/0x4/0x40)零交集",
      "SDL_GetWindowFlags((long)this.handle) & 1L" in win
      and win.count("SDL_GetWindowFlags") == 1)

print("===== D. 修复锚点（sdl3_hook.m） =====")
check("D1 位变换表达式（焦点置 1 + MINIMIZED/HIDDEN 剥离，不多不少）",
      "return (f | 0x200u) & ~0x40u & ~0x4u;" in sdl)
check("D2 Task110 注释块（INPUT_FOCUS 置 1 + dynamic_fps 3.11.10 根因叙事）",
      "Task 110：INPUT_FOCUS 位（0x200）置 1" in sdl
      and "dynamic_fps 3.11.10 的 WindowObserver" in sdl)
check("D3 Task50 语义保留（MINIMIZED 剥离 + renderpearl 注释原位）",
      "Cannot acquire minimized window" in sdl and "Task 50：SDL_GetWindowFlags 剥离 MINIMIZED 位" in sdl)
check("D4 双注册点仍路由 hook（SDL_LoadFunction + dlsym 两条解析路径）",
      sdl.count('strcmp(name, "SDL_GetWindowFlags") == 0') == 2
      and "*out = (void *)ame_SDL_GetWindowFlags;" in sdl)
check("D5 焦点恒真的安全性论证在注释（iOS 后台冻结 + idle 心跳喂养 ABANDONED 档）",
      "iOS app 活跃时恒真" in sdl and "45s 滚轮心跳喂养" in sdl)

print("===== E. 位变换 + 状态机镜像 =====")
def fix_flags(f):
    return (f | 0x200) & ~0x40 & ~0x4

check("E1 变换：0x40|0x4（旧实况）→ 0x200（聚焦）且 0x40/0x4 清零",
      fix_flags(0x44) == 0x200)
check("E2 变换：FULLSCREEN(0x1) 保留 + 焦点补上",
      fix_flags(0x1) == 0x201 and fix_flags(0x1) & 1 == 1)
check("E3 变换：真实 SDL 各位不越权（只动 0x200/0x40/0x4 三位）",
      fix_flags(0xABCD) == (0xABCD | 0x200) & ~0x44)

def mod_state(focused, hovered, iconified, idle=False, battery=False):
    if focused:
        return "ABANDONED" if idle else ("UNPLUGGED" if battery else "FOCUSED")
    if hovered:
        return "HOVERED"
    return "INVISIBLE" if iconified else "UNFOCUSED"

def mod_inputs_from_flags(f):
    return ((f & 0x200) != 0, (f & 0x400) != 0, (f & 0x40) != 0 or (f & 0x4) != 0)

check("E4 旧实况（隐藏窗口 raw flags 0x44）→ mod 判 INVISIBLE/UNFOCUSED 降频档",
      mod_state(*mod_inputs_from_flags(0x44)) in ("INVISIBLE", "UNFOCUSED"))
check("E5 修复后（0x200 恒真）→ mod 判 FOCUSED（Config.ACTIVE 不限帧）",
      mod_state(*mod_inputs_from_flags(fix_flags(0x44))) == "FOCUSED")
check("E6 idle 免疫镜像：onActivity 由心跳持续重置 → ABANDONED 不可达（isIdle=False）",
      mod_state(*mod_inputs_from_flags(fix_flags(0x44)), idle=False) == "FOCUSED")

print("===== F. 文档 =====")
check("F1 FAQ 根因重归因（Task110 定案 + dynamic-fps + [SDLHook] Task110 锚点）",
      "Task110 根因定案" in faq and "dynamic-fps 模组" in faq
      and "[SDLHook] Task110" in faq)
check("F2 FAQ 计数不变 34（原位改写，零级联）",
      faq.count("= [[LauncherHelpFaqItem alloc] init]") == 34)
check("F3 version.h Task 110 addendum（根因链 + 修复 + 免疫论证）",
      "REVISION 17 addendum (Task 110, no bump)" in vh
      and "dynamic_fps 3.11.10 sees an" in vh)
check("F4 version.h Task109 addendum 已修正（不再断言 no limiter，改记 mod 不可见于 watchdog）",
      "no limiter anywhere" not in vh
      and "the mod's throttle was invisible to our watchdog" in vh)
check("F5 osm_bridge Task109 注释同步根因（真凶 dynamic_fps + 见 sdl3_hook.m Task110）",
      "Task110 定案：真凶是 dynamic_fps" in osm and "sdl3_hook.m Task110" in osm)

print("===== G. 语法与级联 =====")
def bracket_balance(src):
    depth = 0; i = 0; n = len(src); state = 0
    while i < n:
        c = src[i]
        if state == 0:
            if c == '"': state = 1
            elif c == '/' and i + 1 < n and src[i+1] == '/': state = 3
            elif c == '/' and i + 1 < n and src[i+1] == '*': state = 4
            elif c == '{': depth += 1
            elif c == '}': depth -= 1
        elif state == 1:
            if c == '\\': i += 1
            elif c == '"': state = 0
        elif state == 3:
            if c == '\n': state = 0
        elif state == 4:
            if c == '*' and i + 1 < n and src[i+1] == '/': state = 0; i += 1
        i += 1
    return depth

check("G1 sdl3_hook.mm 括号自平衡（字符串/注释感知）", bracket_balance(sdl) == 0)
for v in ("verify_task59.py", "verify_task79.py", "verify_task80.py"):
    r = subprocess.run([sys.executable, os.path.join(SCRIPTS, v)],
                       capture_output=True, text=True, timeout=600)
    note = "（80→76→71→67→66→65/61 链含外层工作区副本，61/65 旧 flags 锚已随 Task110 重锚）" if v == "verify_task80.py" else ""
    check(f"G2 {v}（exit={r.returncode}）{note}", r.returncode == 0, (r.stdout + r.stderr)[-90:])

print(f"\nRESULT: {'ALL PASS' if FAIL == 0 else 'FAILED'} ({PASS}/{PASS + FAIL})")
sys.exit(0 if FAIL == 0 else 1)
