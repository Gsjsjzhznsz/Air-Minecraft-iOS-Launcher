#!/usr/bin/env python3
"""Task 77 验证：MG 卡顿深度研究落地两件套。

A. 帧相位归因仪器（present vs build 分相计时）——66e57f0 双日志定案的
   下轮设备日志判读硬指标：
   - gl_bridge.m 计数器块 + ame_egl_swap_phase_stats 读取即重置
   - gl_swap_buffers：build 在入口记录（先于 Task48 卫兵）、present 只包
     eglSwapBuffers 本体、成败两路都计
   - utils.h 声明
   - SurfaceViewController 心跳 pres=%u/%ums build=%u/%ums 上报
   - Task76 锚点不回退（framegap 调用与格式子串仍在）
B. 默认控件 = custom.json：
   - PLPreferences 出厂值 + 迁移哨兵默认值
   - migrateDefaultControlPref（.h 声明 + .m 实现 + AppDelegate 调用）
   - Task64 恢复默认控件复位到 custom.json（文件存在时）
   - ControlLayout 解析失败回落 default.json 保留（可玩性兜底不变）
   - 手柄默认布局不受影响
C. 行为回放：相位统计 avg/max/重置语义 + 迁移决策表
D. 括号平衡：全部触碰文件 vs HEAD 差量 = 0
"""
import re
import subprocess
import sys

ROOT = "/home/z/my-project/Amethyst-iOS-MyRemastered"
results = []


def check(name, ok, detail=""):
    results.append((name, bool(ok)))
    mark = "PASS" if ok else "FAIL"
    print(f"[{mark}] {name}" + (f" -- {detail}" if detail and not ok else ""))


def read(p):
    return open(f"{ROOT}/{p}", encoding="utf-8", errors="replace").read()


# ============================================================================
print("== A. 帧相位归因仪器 ==")
gb = read("Natives/ctxbridges/gl_bridge.m")
uh = read("Natives/utils.h")
sv = read("Natives/SurfaceViewController.m")

check("A1 gl_bridge Task77 计数器块（present/build sum/max/count 6 变量）",
      all(tok in gb for tok in [
          "ame77_present_sum_us", "ame77_present_max_us", "ame77_present_count",
          "ame77_build_sum_us", "ame77_build_max_us", "ame77_build_count",
          "ame77_last_swap_end_us"]))

check("A2 ame_egl_swap_phase_stats 定义（4 出参）",
      "void ame_egl_swap_phase_stats(uint32_t *presentAvgMs, uint32_t *presentMaxMs," in gb
      and "uint32_t *buildAvgMs, uint32_t *buildMaxMs) {" in gb)

check("A3 utils.h 声明 + 判读法注释",
      "void ame_egl_swap_phase_stats(unsigned int *presentAvgMs, unsigned int *presentMaxMs," in uh
      and "buildAvgMs" in uh)

check("A4 心跳调用 + 格式串 pres/build",
      "ame_egl_swap_phase_stats(&presAvg, &presMax, &buildAvg, &buildMax);" in sv
      and "pres=%u/%ums build=%u/%ums" in sv)

# build 记录点必须在 Task48 卫兵之前；present 计时必须夹住 eglSwapBuffers 本体
m_swap = gb.index("void gl_swap_buffers()")
swap_body = gb[m_swap:m_swap + 4000]
i_build = swap_body.find("ame77_record_build(")
i_guard = swap_body.find("ame48_swap_geometry_guard(")
i_p0 = swap_body.find("ame77_t_present0 = ame77_now_us();")
i_swap_call = swap_body.find("handle.eglSwapBuffers(g_EglDisplay")
i_p1 = swap_body.find("ame77_t_present1 = ame77_now_us();")
i_fail = swap_body.find("if (!swapResult)")
check("A5a build 入口记录先于 Task48 卫兵",
      0 < i_build < i_guard, f"i_build={i_build} i_guard={i_guard}")
check("A5b present 计时夹住 eglSwapBuffers（p0<call<p1）",
      0 < i_p0 < i_swap_call < i_p1, f"{i_p0},{i_swap_call},{i_p1}")
check("A5c present 记录在失败早退之前（成败都计）",
      0 < i_p1 < i_fail, f"i_p1={i_p1} i_fail={i_fail}")

check("A6 Task76 锚点不回退",
      "ame76_record_swap(ame53_now_ms());" in swap_body
      and "maxGap=%ums avgGap=%ums" in sv
      and "ame_egl_swap_framegap(&maxGap, &avgGap);" in sv)

# ============================================================================
print("== B. 默认控件 = custom.json ==")
plp = read("Natives/PLPreferences.m")
lp = read("Natives/LauncherPreferences.m")
lph = read("Natives/LauncherPreferences.h")
ad = read("Natives/AppDelegate.m")
ccu = read("Natives/customcontrols/CustomControlsUtils.m")
cl = read("Natives/customcontrols/ControlLayout.m")

check("B1 PLPreferences 出厂值 custom.json",
      '@"default_ctrl": @"custom.json",' in plp)

check("B2 迁移哨兵默认值注册",
      '@"default_ctrl_migrated_custom": @NO,' in plp)

check("B3 migrateDefaultControlPref 实现（哨兵早退 + 仅迁移 default.json）",
      "void migrateDefaultControlPref(void)" in lp
      and 'getPrefObject(@"control.default_ctrl_migrated_custom")' in lp
      and 'isEqualToString:@"default.json"]' in lp
      and 'setPrefObject(@"control.default_ctrl", @"custom.json");' in lp)

check("B4 头文件声明 + AppDelegate 调用",
      "void migrateDefaultControlPref(void);" in lph
      and "migrateDefaultControlPref();" in ad)

check("B5 Task64 恢复默认复位到 custom.json（存在时）",
      'NSString *ame77RestoreCtrl = [fm fileExistsAtPath:customPath] ? @"custom.json" : @"default.json";' in ccu
      and "ame77RestoreCtrl" in ccu)

check("B6 解析失败回落 default.json 保留",
      'if (![name isEqualToString:@"default.json"])' in cl
      and "Task64 parse-fail fallback" in cl)

check("B7 手柄默认布局不受影响",
      '@"default_gamepad_ctrl": @"default.json",' in plp)

# ============================================================================
print("== C. 行为回放 ==")


def phase_stats_replay():
    """移植 ame_egl_swap_phase_stats 的 avg/max/重置语义。"""
    state = dict(last_end_us=0, p_sum=0, p_max=0, p_cnt=0, b_sum=0, b_max=0, b_cnt=0)

    def record_build(now_us):
        if state["last_end_us"] != 0 and now_us > state["last_end_us"]:
            dur = now_us - state["last_end_us"]
            state["b_max"] = max(state["b_max"], dur)
            state["b_sum"] += dur
            state["b_cnt"] += 1

    def record_present(dur_us, now_us):
        state["p_max"] = max(state["p_max"], dur_us)
        state["p_sum"] += dur_us
        state["p_cnt"] += 1
        state["last_end_us"] = now_us

    def read_reset():
        p_avg = state["p_sum"] // state["p_cnt"] // 1000 if state["p_cnt"] else 0
        p_max = state["p_max"] // 1000 if state["p_cnt"] else 0
        b_avg = state["b_sum"] // state["b_cnt"] // 1000 if state["b_cnt"] else 0
        b_max = state["b_max"] // 1000 if state["b_cnt"] else 0
        for k in ("p_sum", "p_max", "p_cnt", "b_sum", "b_max", "b_cnt"):
            state[k] = 0
        return p_avg, p_max, b_avg, b_max

    return record_build, record_present, read_reset


rb, rp, rr = phase_stats_replay()
# 场景：60fps 好相位 3 帧（build 8ms/present 3ms），坏相位 2 帧（build 12ms/present 240ms）
rb(0)                    # 首帧入口（无 last_end → 不计 build）
rp(3000, 3000)           # present 3ms
rb(11000)                # build 8ms
rp(240000, 251000)       # 坏帧 present 240ms
rb(263000)               # build 12ms
rp(2000, 265000)
p_avg, p_max, b_avg, b_max = rr()
check("C1 相位统计：present avg=81ms max=240ms build avg=10ms max=12ms",
      (p_avg, p_max, b_avg, b_max) == (81, 240, 10, 12),
      f"got {(p_avg, p_max, b_avg, b_max)}")
p_avg2, p_max2, b_avg2, b_max2 = rr()
check("C2 读取即重置（第二次读全零）",
      (p_avg2, p_max2, b_avg2, b_max2) == (0, 0, 0, 0),
      f"got {(p_avg2, p_max2, b_avg2, b_max2)}")


def migrate_replay(stored, sentinel):
    """移植 migrateDefaultControlPref 决策表。"""
    if sentinel:
        return stored, False  # 未写回（早退）
    effective = stored if stored is not None else "custom.json"  # defaults 回填
    wrote = False
    if effective == "default.json":
        effective = "custom.json"
        wrote = True
    return effective, wrote


cases = [
    # (存储值, 哨兵) -> (期望有效值, 期望写回)
    (("default.json", False), ("custom.json", True)),    # 老安装物化值 → 迁移
    (("custom.json", False), ("custom.json", False)),    # 已是新值 → 无事
    (("mylayout.json", False), ("mylayout.json", False)),  # 用户自选 → 尊重
    ((None, False), ("custom.json", False)),              # 全新安装 → defaults 即新值
    (("default.json", True), ("default.json", False)),   # 哨兵已置 → 早退不改
]
ok = True
for (stored, sentinel), (exp_v, exp_w) in cases:
    v, w = migrate_replay(stored, sentinel)
    if (v, w) != (exp_v, exp_w):
        ok = False
        print(f"    mismatch: stored={stored} sentinel={sentinel} -> {(v, w)} != {(exp_v, exp_w)}")
check("C3 迁移决策表 5 组合", ok)

# ============================================================================
print("== D. 括号平衡（触碰文件 vs HEAD 差量） ==")
files = [
    "Natives/ctxbridges/gl_bridge.m", "Natives/SurfaceViewController.m",
    "Natives/PLPreferences.m", "Natives/LauncherPreferences.m",
    "Natives/LauncherPreferences.h", "Natives/AppDelegate.m",
    "Natives/customcontrols/CustomControlsUtils.m", "Natives/utils.h",
]


def balance(src):
    s = re.sub(r"//[^\n]*", "", src)
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    s = re.sub(r'"(\\.|[^"\\])*"', '""', s)
    return s.count("{") - s.count("}"), s.count("(") - s.count(")")


for f in files:
    cur = balance(read(f))
    try:
        head = subprocess.run(["git", "-C", ROOT, "show", f"HEAD:{f}"],
                              capture_output=True, text=True).stdout
        old = balance(head)
    except Exception:
        old = cur
    check(f"D {f} 平衡差量 0", cur == old, f"cur={cur} head={old}")

# ============================================================================
print("== E. 级联回归 verify_task76 ==")
r = subprocess.run([sys.executable, f"{ROOT}/scripts/verify_task76.py"],
                   capture_output=True, text=True)
tail = (r.stdout or "").strip().splitlines()
summary = next((l for l in reversed(tail) if "RESULT" in l or "/" in l and "PASS" in l), "")
check("E verify_task76 全绿", r.returncode == 0, summary)

# ============================================================================
total = len(results)
passed = sum(1 for _, ok in results if ok)
print(f"\nRESULT: {passed}/{total} " + ("PASS" if passed == total else "FAIL"))
sys.exit(0 if passed == total else 1)
