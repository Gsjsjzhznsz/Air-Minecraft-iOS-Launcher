#!/usr/bin/env python3
"""Task 109 验证器：698c6fe 双日志判读（整合包 30fps vs 原版正常）+ no-finish 取证窗口

判读结论（双会话均 38fb316 构建）：
  · 原版 26.3（2.5 分钟稳定游玩）：MC-side 中位 3.3ms + 呈现 ~10ms
    （glFinish 相位 8.5-13.7ms）→ frame 中位 18.6ms（53fps）= 用户判"正常"；
  · 整合包 26.3（110 mods，进世界仅 13 秒即退出）：MC-side 21-36ms
    + 同款呈现 ~10ms → 21-30fps = "锁 30"实为每帧预算叠加；
  · 无任何限帧器：0 次 FramerateLimiter、maxFps=260、无 vsync、
    AFK 心跳在岗；两会话 glFinish 相位一致（8-13ms，与场景负载无关）
    = 固定驱动同步常数；我们自己的权威回读（Task100 路径）仅 ~4ms/事件。

修复/实验（osm_bridge.mm Task109 no-finish trial）：
  两个固定 FSR 帧窗口（300-419 与 1020-1139，各 120 帧）内跳过驱动
  glFinish，强制权威 glReadPixels 呈现；A/B 相位计时决定下一轮去向。
  自愈安全：哨兵票窗口内跳过（bundle 必然 stale）、权威失败补迟到
  glFinish、非 FSR 帧/会话零影响。

A. 698c6fe 双日志证据（git 钉）
B. 产线代码锚点（窗口状态机 + 三处 swap 改动 + 保底）
C. FAQ / version.h
D. 窗口状态机 Python 镜像（边界 + 非 FSR + 熔断抑制）
E. 语法门复跑（task103_syntax_swap + task83_syntax_osm）
F. 级联（83/84/107 → 107 内部拉起 106 → 100/103/104/105 + 85；
   86/87/94/95/97-99 本轮已手动全绿，FAQ 计数由 C4 静态覆盖）
"""
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
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

def git_show(rev, path):
    r = subprocess.run(["git", "-C", REPO, "show", f"{rev}:{path}"],
                       capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""

osm = read("Natives/ctxbridges/osm_bridge.mm")
faq = read("Natives/LauncherHelpViewController.m")
vh = read("Natives/external/MobileGlues/MobileGlues-cpp/version.h")

print("===== A. 698c6fe 双日志证据 =====")
vanilla = git_show("698c6fe", "latestlog.txt")        # 原版会话（2.5 分钟）
modpack = git_show("698c6fe", "latestlog.old.txt")    # 整合包会话（13 秒）
check("A1 双会话均为 38fb316 构建（Task108 全修复在身）",
      vanilla.count("Commit: 38fb316") == 1 and modpack.count("Commit: 38fb316") == 1)
check("A2 会话识别：old=fabric 整合包（110 mods）、new=原版 26.3",
      "Loading 110 mods" in modpack and "fabric-loader" in modpack
      and "Launching Minecraft 26.3" in vanilla and "fabric-loader" not in vanilla)
check("A3 无限帧器（整合包会话）：0 次 FramerateLimiter + on-disk 选项干净 + AFK 心跳在岗",
      modpack.count("FramerateLimiter") == 0
      and "inactivityFpsLimit=minimized maxFps=260 enableVsync=false" in modpack
      and "Task104 AFK heartbeat armed" in modpack)

def heartbeat_stats(log):
    frames, mcside, finishes = [], [], []
    for m in re.finditer(r"t=swap [\d.]+\(max [\d.]+\) \[pre\+easu [\d.]+ glFinish ([\d.]+) readback [\d.]+\]ms frame=([\d.]+) MC-side=([\d.]+)ms", log):
        finishes.append(float(m.group(1)))
        frames.append(float(m.group(2)))
        mcside.append(float(m.group(3)))
    return frames, mcside, finishes

vf, vm, vfin = heartbeat_stats(vanilla)
mf, mm, mfin = heartbeat_stats(modpack)
check("A4 原版：66 心跳样本（2.5 分钟稳定期），frame 中位 ≤19ms（≥52fps）",
      len(vf) == 66 and sorted(vf)[len(vf) // 2] <= 19.0, f"n={len(vf)} med={sorted(vf)[len(vf)//2] if vf else '-'}")
check("A5 原版：MC-side 中位 ≤4ms（游戏自身极轻，瓶颈在呈现常数）",
      len(vm) == 66 and sorted(vm)[len(vm) // 2] <= 4.0, f"med={sorted(vm)[len(vm)//2] if vm else '-'}")
check("A6 整合包：仅 4 心跳样本（13 秒 in-world，全是加载风暴期数据）",
      len(mf) == 4)
check("A7 整合包：MC-side 全部 ≥20ms（110 mods 加载期游戏线程重载）",
      len(mm) == 4 and min(mm) >= 20.0, f"min={min(mm) if mm else '-'}")
check("A8 两会话 glFinish 相位区间重叠（固定驱动常数，非场景 GPU 负载：重载的整合包反而更低）：中位均 7-18ms 且相差 ≤5ms",
      7.0 <= sorted(vfin)[len(vfin) // 2] <= 18.0 and 7.0 <= sorted(mfin)[len(mfin) // 2] <= 18.0
      and abs(sorted(vfin)[len(vfin) // 2] - sorted(mfin)[len(mfin) // 2]) <= 5.0,
      f"v={sorted(vfin)[len(vfin)//2]:.1f} m={sorted(mfin)[len(mfin)//2]:.1f}")
check("A9 两会话 bundle-direct 均激活（呈现路径同构 = 原版正常即启动器无罪证）",
      "Task106 bundle-direct present engaged" in vanilla
      and "Task106 bundle-direct present engaged" in modpack)
check("A10 整合包会话时长：登录 15:46:13 → exit(0) 15:46:26（13 秒，退出发生在加载期）",
      "logged in with entity id 91" in modpack and "15:46:26" in modpack.split("Amethyst fatal trace")[-1][:60])
check("A11 原版会话时长：登录 15:46:52 → exit 15:49:22（约 2.5 分钟稳定游玩）",
      "logged in with entity id 85" in vanilla and "15:49:22" in vanilla.split("Amethyst fatal trace")[-1][:60])

print("===== B. 产线代码锚点（osm_bridge.mm） =====")
check("B1 窗口状态机结构体 + 边界函数（300-419 与 1020-1139，各 120 帧）",
      "} ame109 = {0};" in osm
      and "return (f >= 300 && f < 420) || (f >= 1020 && f < 1140);" in osm)
check("B2 门函数三重护栏（非 FSR 不进 / 帧计数仅 FSR / 熔断抑制跳过）",
      "static bool ame109_trial_gate(bool fsrActive) {" in osm
      and "if (!fsrActive) return false;" in osm
      and "return ame109.inWindow && !ame100_present.broken;" in osm)
check("B3 进窗强制 bd 退场（窗口内不误判、出窗后按 30 连中纪律重臂）",
      "ame106.active = false;   // 退出窗口后按既有 warmup 纪律自然重臂（30 连中）" in osm
      and "ame106.warm = 0;" in osm)
check("B4 swap 改动 1：glFinish 条件化（窗口内跳过，其余照旧）",
      "bool ame109Trial = ame109_trial_gate(fsrActiveThisFrame);" in osm
      and "if (!ame109Trial) {\n        handle.glFinish();" in osm)
check("B5 swap 改动 2：窗口内哨兵票整体跳过（bundle 必然 stale，防误触 fallback 日志）",
      osm.count("if (!ame109Trial) {") == 2
      and "if (!ame109Trial) {\n        bool bundleFresh106" in osm)
check("B6 swap 改动 3：迟到 glFinish 保底（权威失败仍能上屏正确帧）",
      "if (ame109Trial && !presentThisFrame) {\n        handle.glFinish();" in osm)
check("B7 A/B 分桶累计挂点（仅 FSR 帧计数，语义与 ame109.frame 对齐）",
      "if (fsrActiveThisFrame) {\n            if (ame109.inWindow) {" in osm
      and "++ame109.baseN;" in osm)
check("B8 进出窗日志锚点（含 trial vs baseline 均值）",
      "Task109 no-finish trial: window opens at FSR frame %ld" in osm
      and "Task109 no-finish trial: window closed -- trial avg swap %.1fms" in osm)
check("B9 相位计时语义保持（glFinish 相位窗口内趋 0 = 跳过即实测）",
      osm.count("ame106.tFinUs += t106_2 - t106_1;") == 1
      and "ame106.tReadUs += t106_3 - t106_2;" in osm)
check("B10 既有锚点零回归（bundle-direct engaged/fallback 文案逐字未动）",
      "Task106 bundle-direct present engaged: 30 consecutive fresh full-surface EASU frames" in osm
      and "Task106 bundle-direct fallback: driver buffer lost per-frame sentinels" in osm)

print("===== C. FAQ / version.h =====")
check("C1 fpsUnlock 模组对照条目（Task110 根因重归因：dynamic-fps 模组 + 原版不含 + 已根治）",
      "Task110 根因定案" in faq and "dynamic-fps 模组" in faq
      and "原版没装它所以正常" in faq and "SDL 窗口标志恒报" in faq)
check("C2 Task110 修复锚点入 FAQ（[SDLHook] Task110）",
      "[SDLHook] Task110" in faq)
check("C3 旧判读文案清除（不再断言非任何限帧器/双会话实测定论）",
      "非任何限帧器" not in faq and "Task109 双会话实测定论" not in faq
      and "进世界后先跑一两分钟再判断" not in faq)
check("C4 FAQ 计数不变 34（原位改写，零级联）",
      faq.count("= [[LauncherHelpFaqItem alloc] init]") == 34)
check("C5 version.h REVISION 17 addendum (Task 109, no bump)（判读 + 实验 + 二进制法证）",
      "REVISION 17 addendum (Task 109, no bump)" in vh
      and "no-finish trial" in vh and "Mesa 25.0.7" in vh
      and "OSMesaMakeCurrent 0x4970" in vh)
check("C6 version.h 注释无半开区间记法（括号平衡校验器纪律）",
      "[300,420)" not in vh and "[1020,1140)" not in vh)

print("===== D. 窗口状态机 Python 镜像 =====")
def window_active(f):
    return (f >= 300 and f < 420) or (f >= 1020 and f < 1139 + 1)

check("D1 边界：299 出 / 300 入 / 419 在 / 420 出",
      not window_active(299) and window_active(300)
      and window_active(419) and not window_active(420))
check("D2 第二窗口：1019 出 / 1020 入 / 1139 在 / 1140 出",
      not window_active(1019) and window_active(1020)
      and window_active(1139) and not window_active(1140))

def gate_step(fsr_active, frame, in_window, broken):
    """镜像 ame109_trial_gate：返回 (skip, frame', in_window')。"""
    if not fsr_active:
        return (False, frame, in_window)          # 非 FSR：不推进不跳过
    f = frame + 1
    in_w = window_active(f)
    return (in_w and not broken, f, in_w)          # 熔断抑制跳过但窗口照常推进

s = {"frame": 0, "in": False}
skipped_fsr = []
for i in range(1, 1700):                                # 墙钟长度覆盖 1140 FSR 帧 + 400 非 FSR 夹杂 + 余量
    fsr = (i <= 500 or i >= 900)                          # 模拟中途一段非 FSR 帧
    skip, s["frame"], s["in"] = gate_step(fsr, s["frame"], s["in"], False)
    if skip:
        skipped_fsr.append(s["frame"])                    # 收集 FSR 帧号（非墙钟位置）
check("D3 非 FSR 帧不推进计数（1700 墙钟 - 400 非 FSR = 恰 1300 FSR 帧）",
      s["frame"] == 1300)
skipped = skipped_fsr
check("D4 FSR 帧号跳过集合 = 两窗口精确并集（300-419 + 1020-1139，非 FSR 夹杂不影响窗口边界）",
      skipped == list(range(300, 420)) + list(range(1020, 1140)),
      f"got {len(skipped)} frames: {skipped[:3]}...{skipped[-3:] if skipped else ''}")
s2 = {"frame": 0, "in": False}
skip_broken = []
for i in range(1, 500):
    skip, s2["frame"], s2["in"] = gate_step(True, s2["frame"], s2["in"], broken=True)
    if skip:
        skip_broken.append(i)
check("D5 权威路径熔断：窗口照常推进但永不跳过（glFinish 兜底）",
      s2["frame"] == 499 and not skip_broken)

print("===== E. 语法门复跑 =====")
r = subprocess.run([sys.executable, os.path.join(SCRIPTS, "task103_syntax_swap.py")],
                   capture_output=True, text=True, timeout=300)
check("E1 task103_syntax_swap（含 ame109 桩）",
      r.returncode == 0 and "syntax OK" in r.stdout, r.stdout[-100:])
r = subprocess.run(["bash", os.path.join(SCRIPTS, "task83_syntax_osm.sh")],
                   capture_output=True, text=True, timeout=300)
check("E2 task83_syntax_osm（ame83/dlsym 段）",
      r.returncode == 0 and r.stdout.count("syntax OK") == 2, r.stdout[-100:])

print("===== F. 级联 =====")
for v in ("verify_task83.py", "verify_task84.py", "verify_task107.py"):
    r = subprocess.run([sys.executable, os.path.join(SCRIPTS, v)],
                       capture_output=True, text=True, timeout=900)
    ok = r.returncode == 0
    check(f"F {v}（exit={r.returncode}；107 内部级联 106→100/103/104/105+85）",
          ok, (r.stdout + r.stderr)[-100:])

print(f"\nRESULT: {'ALL PASS' if FAIL == 0 else 'FAILED'} ({PASS}/{PASS + FAIL})")
sys.exit(0 if FAIL == 0 else 1)
