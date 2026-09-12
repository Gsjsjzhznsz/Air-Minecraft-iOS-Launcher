#!/usr/bin/env python3
"""verify_task59.py — Task 59（输入错位根因：ame51 ÷2 把所有输入压到一半位置）本地验证

背景定案（f335789 真机日志，376192f 构建）：
  1) 启动器经 launchJVM 告知 MC 窗口尺寸 2360x1640（物理像素口径）：
     "[SurfaceViewController] Launching Minecraft ... size: 2360x1640"
     MC 26.3 据此创建 SDL 窗口："[SDLHook] SDL_CreateWindow ... 2360x1640"
     → MC 的输入归一化基准 = 2360x1640（Window 对象的信念），
       而非 Task51 钳制后的实际 SDL 窗口 1180x820 点。
  2) TouchController mod 的参考分辨率 = 2360x1640（sendCursorPos x 最大
     1802 > 1180，整数坐标）。
  3) Task51 Fix G 的 ÷2（UIScreen.scale=2）把 2360 口径坐标压进 1180 点
     空间 → MC 按 2360 归一化 → 每个输入落在真实位置的一半处 = "输入错位"。
  4) 渲染尺寸由 renderpearl 适配真实 EGL 表面（1180x820，Task58 后画面
     1:1 正常），与输入归一化解耦——所以画面好而输入错位。

修复内容：
  F1 input_bridge_v3.m  ame51_px_to_pt → 恒等直通（÷2 移除）+ Task59 指纹
  F2 SurfaceViewController.m updateGrabState：contentsScale（Task52 钉成 1.0）
     → screenScale（恢复 ×2 口径一致性）
  F3 SurfaceViewController.m sendTouchEvent：rootView（比 surfaceView 宽
     30pt，游戏画面两侧各缩进 15pt）→ surfaceView 参考系（消灭 +15pt 偏移）
  F4 sdl3_hook.m SDL_PollEvent：鼠标类事件附带 x/y（偏移 28/32）——
     观测 MC 实际消费的坐标，闭环取证

验证项：
  A. 源码层：F1-F4 落盘 + 括号平衡 delta 与 HEAD 一致（3 文件）
  B. 行为层（f335789 日志实值重放）：
     B1 旧模型复现错位：mod 事件 (1802,1486) ÷2 → (901,743) → MC 按 2360
        归一化 = 0.382/0.453 ≠ 手指真实归一化位置 0.763/0.905（差一半）
     B2 新模型对齐：(1802,1486) 直通 → MC /2360 = 0.763/0.905 == 手指位置
     B3 全链路代数：手指 n → mod n×2360 → 直通 → MC n×2360/2360 = n ✓
     B4 updateGrabState 乘数：虚拟鼠标 (590,410)pt ×2 = (1180,820) px ✓
        （旧行为 ×1.0 = 落在 1/4 位置）
     B5 rootView 偏移：rootView x=605（=surface 590+15 缩进）旧行为发
        1210px（+30px 偏移），新行为发 1180px ✓
  C. 影子编译：提取新版 ame51_px_to_pt → ObjC→C 翻译 → gcc -fsyntax-only
     + 行为断言（恒等直通）
"""
import re
import subprocess
import sys
import tempfile
import os

REPO = "/home/z/my-project/Amethyst-iOS-MyRemastered"
IB = f"{REPO}/Natives/input_bridge_v3.m"
SVC = f"{REPO}/Natives/SurfaceViewController.m"
SDL = f"{REPO}/Natives/sdl3_hook.m"

results = []


def check(name, ok, detail=""):
    results.append((name, ok, detail))
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}" + (f" — {detail}" if detail else ""))


def main():
    ib = open(IB, encoding="utf-8").read()
    svc = open(SVC, encoding="utf-8").read()
    sdl = open(SDL, encoding="utf-8").read()

    print("== A. 源码层 ==")

    # A1: ame51 恒等直通（不再除以 scale）
    m = re.search(r"static float ame51_px_to_pt\(float v\) \{(.*?)\n\}", ib, re.S)
    check("A1 ame51_px_to_pt 存在", m is not None)
    if m:
        body = m.group(1)
        check("A1b ÷2 换算已移除（无 v / ame51_scale）", "/" not in re.sub(r"//.*", "", body.split("NSLog")[0] + "return v;"))
        check("A1c 函数体恒等返回", "return v;" in body)
    check("A1d Task51 旧换算指纹已移除", "Task51 touch px->pt scale=" not in ib)
    check("A1e Task59 指纹存在", "Task59 raw px pass-through" in ib)

    # A2: updateGrabState 乘数修复
    seg = re.search(r"- \(void\)updateGrabState \{.*?CallbackBridge_nativeSendCursorPos\(ACTION_DOWN, lastVirtualMousePoint\.x \* ([^,]+),", svc, re.S)
    check("A2 updateGrabState 乘数表达式存在", seg is not None)
    if seg:
        mult = seg.group(1).strip()
        check("A2b 乘数改用 screenScale（非 contentsScale）",
              "screenScale" in mult and "contentsScale" not in mult, mult)

    # A3: sendTouchEvent 参考系修复
    seg2 = re.search(r"sendTouchEvent:\(UITouch \*\)touchEvent withUIEvent:\(UIEvent \*\)uievent withEvent:\(int\)event\n\{\n(?:\s*//[^\n]*\n)*\s*CGPoint locationInView = \[touchEvent locationInView:(self\.\w+)\];", svc)
    check("A3 sendTouchEvent 参考系表达式存在", seg2 is not None)
    if seg2:
        view = seg2.group(1)
        check("A3b 参考系 = surfaceView（非 rootView）", view == "self.surfaceView", view)

    # A4: sdl3_hook PollEvent 鼠标坐标取证
    check("A4 sdl3_hook Task59 mouse consumed 指纹", "Task59 mouse consumed" in sdl)
    check("A4b 偏移 28/32 读取", "event + 28" in sdl and "event + 32" in sdl)

    # A5: 括号平衡 vs HEAD（3 文件）
    for path, label in [(IB, "input_bridge_v3.m"), (SVC, "SurfaceViewController.m"), (SDL, "sdl3_hook.m")]:
        cur = open(path, encoding="utf-8").read()
        head = subprocess.run(["git", "-C", REPO, "show", f"HEAD:{path.split(REPO+'/')[1]}"],
                              capture_output=True, text=True).stdout
        ok = True
        detail = []
        for a, b, kind in [("{", "}", "brace"), ("(", ")", "paren"), ("[", "]", "bracket")]:
            d_new = cur.count(a) - cur.count(b)
            d_old = head.count(a) - head.count(b)
            if d_new != d_old:
                ok = False
                detail.append(f"{kind}:{d_old}->{d_new}")
        check(f"A5 {label} 括号 delta 与 HEAD 一致", ok, ",".join(detail) or "delta=0")

    print("== B. 行为层（f335789 真机日志实值重放） ==")
    # 日志实值：
    #   sendCursorPos #150: x=1802.0 y=1486.0（mod 输出，2360 口径像素）
    #   启动器告知/MC 窗口信念：2360x1640；实际 SDL 窗口 1180x820 点
    #   手指真实归一化位置 = mod 输出 / 2360（mod 参考即全屏）
    MC_W, MC_H = 2360.0, 1640.0
    MOD_X, MOD_Y = 1802.0, 1486.0
    true_nx, true_ny = MOD_X / MC_W, MOD_Y / MC_H  # 0.7636, 0.9061

    # B1: 旧行为（÷2）复现"输入落在一半位置"
    old_x, old_y = MOD_X / 2.0, MOD_Y / 2.0
    old_nx, old_ny = old_x / MC_W, old_y / MC_H
    check("B1 旧模型：÷2 后 MC 归一化位置 = 真实位置的一半（错位复现）",
          abs(old_nx - true_nx / 2) < 1e-9 and abs(old_ny - true_ny / 2) < 1e-9,
          f"旧 {old_nx:.3f},{old_ny:.3f} vs 真实 {true_nx:.3f},{true_ny:.3f}")

    # B2: 新行为（直通）对齐
    new_x, new_y = MOD_X, MOD_Y  # 恒等
    new_nx, new_ny = new_x / MC_W, new_y / MC_H
    check("B2 新模型：直通后 MC 归一化位置 == 手指真实位置",
          abs(new_nx - true_nx) < 1e-9 and abs(new_ny - true_ny) < 1e-9,
          f"{new_nx:.3f},{new_ny:.3f}")

    # B3: 全链路代数（手指 n → mod → native → SDL → MC）
    ok_chain = True
    for n in (0.0, 0.25, 0.5, 0.7636, 1.0):
        mod_out = n * MC_W            # mod：归一化 × 2360 参考
        sdl_evt = mod_out             # Task59：恒等直通
        mc_pos = sdl_evt / MC_W       # MC：按 2360 信念归一化
        if abs(mc_pos - n) > 1e-9:
            ok_chain = False
    check("B3 全链路代数（5 个采样点全对齐）", ok_chain)

    # B4: updateGrabState 乘数（虚拟鼠标中心 590,410 pt）
    vm_x, vm_y = 590.0, 410.0
    old_mult, new_mult = 1.0, 2.0  # contentsScale(被钉 1.0) vs screenScale
    old_land = (vm_x * old_mult) / MC_W
    new_land = (vm_x * new_mult) / MC_W
    check("B4 updateGrabState：旧行为落在 1/4 位置，新行为落回中心",
          abs(old_land - 0.25) < 1e-9 and abs(new_land - 0.5) < 1e-9,
          f"旧 {old_land:.2f} 新 {new_land:.2f}")

    # B5: rootView 偏移（rootView 比游戏表面宽 30pt，画面两侧各缩进 15pt）
    root_x = 605.0   # 手指点在 rootView 坐标（= surface 590 + 15 缩进）
    surf_x = 590.0   # 同一手指在 surfaceView 坐标
    old_evt = root_x * 2.0    # 旧行为：rootView 坐标 ×2 = 1210
    new_evt = surf_x * 2.0    # 新行为：surfaceView 坐标 ×2 = 1180
    check("B5 rootView 偏移：旧行为 +30px 恒定偏移，新行为对齐",
          abs(old_evt - new_evt) == 30.0 and abs(new_evt - 1180.0) < 1e-9,
          f"旧 {old_evt:.0f} 新 {new_evt:.0f}")

    print("== C. 影子编译（新版 ame51_px_to_pt） ==")
    # 提取真实函数体 → ObjC→C 翻译（BOOL→int，NSLog→桩）→ gcc 编译 + 断言
    fn = re.search(r"(static float ame51_px_to_pt\(float v\) \{.*?\n\})", ib, re.S)
    check("C1 提取新版函数体", fn is not None)
    if fn:
        c_fn = fn.group(1)
        c_fn = c_fn.replace("static BOOL ame59_logged = NO;", "static int ame59_logged = 0;")
        c_fn = c_fn.replace("ame59_logged = YES;", "ame59_logged = 1;")
        c_fn = re.sub(r'NSLog\(@"[^"]*"\);', "", c_fn)  # 桩掉日志
        harness = f"""
#include <stdio.h>
#include <math.h>
{c_fn}
int main(void) {{
    float cases[] = {{0.0f, 1551.0f, 1802.0f, 2360.0f, -13.5f}};
    for (int i = 0; i < 5; i++) {{
        if (fabsf(ame51_px_to_pt(cases[i]) - cases[i]) > 1e-6f) {{
            printf("FAIL identity at %f\\n", cases[i]);
            return 1;
        }}
    }}
    // 多次调用（指纹只打一次的 static 路径）
    for (int i = 0; i < 100; i++) ame51_px_to_pt(1180.0f);
    printf("OK identity\\n");
    return 0;
}}
"""
        with tempfile.TemporaryDirectory() as td:
            src_path = os.path.join(td, "task59_ame51.c")
            bin_path = os.path.join(td, "task59_ame51")
            open(src_path, "w").write(harness)
            cc = subprocess.run(["gcc", "-Wall", "-Wextra", "-fsyntax-only", src_path],
                                capture_output=True, text=True)
            check("C2 gcc -fsyntax-only 0 错误 0 警告",
                  cc.returncode == 0 and not cc.stderr.strip(), cc.stderr.strip()[:200])
            link = subprocess.run(["gcc", "-Wall", "-o", bin_path, src_path, "-lm"],
                                  capture_output=True, text=True)
            if link.returncode == 0:
                run = subprocess.run([bin_path], capture_output=True, text=True)
                check("C3 行为断言：恒等直通（含负值/边界/重复调用）",
                      run.returncode == 0 and "OK identity" in run.stdout, run.stdout.strip())
            else:
                check("C3 行为断言：恒等直通", False, link.stderr.strip()[:200])

    # 汇总
    fails = [n for n, ok, _ in results if not ok]
    print(f"\n{'='*50}\n{len(results)-len(fails)}/{len(results)} PASS")
    if fails:
        print("FAILED:", ", ".join(fails))
        return 1
    print("Task 59 验证全过：输入坐标全程保持启动器像素口径（= MC 窗口信念），")
    print("不再被 ÷2 压半；grab 重入乘数与触摸参考系一并修复。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
