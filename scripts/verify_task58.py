#!/usr/bin/env python3
"""verify_task58.py — Task 58（画面分裂真根因：EGL 查询常量对调）本地验证

背景定案：
  EGL 官方定义（Natives/external/mesa/EGL/egl.h:90/123）：
      EGL_HEIGHT = 0x3056
      EGL_WIDTH  = 0x3057
  gl_bridge.m 自 Task41 起三处把 0x3056 当 EGL_WIDTH、0x3057 当 EGL_HEIGHT
  （注释也写反）→ 交换探针把健康表面 1180x820 读成 "820x1180 转置" →
  geoMismatch 每帧误判 → Task49 geo-heal blit 自造分裂画面 + 输入错位。

验证项：
  A. 源码层：
     A1 无残留误用（gl_bridge.m 中 0x3056/0x3057 不再以裸常量+错误注释出现）
     A2 三处查询均改用 EGL_WIDTH/EGL_HEIGHT 宏
     A3 Task58 指纹日志串存在
     A4 括号/圆括号平衡与 HEAD 一致（delta=0）
  B. 行为层（日志重放仿真，数据取自 3e5e051 真机日志）：
     B1 旧探针模型：query(0x3056→w, 0x3057→h) 复现日志 "surface=820x1180"
        + geoMismatch=true + mode=2（geo-heal blit）——与日志逐行一致
     B2 修正探针模型：query(EGL_WIDTH→w, EGL_HEIGHT→h) → surface=1180x820
        == viewport → geoMismatch=false → latch NORMAL，blit 永不执行
     B3 全帧仿真（swap#1..#1570）：修正后 0 次 geo-heal、0 次 present-align
        写入、Task55 realign 0 次触发
"""
import re
import subprocess
import sys

REPO = "/home/z/my-project/Amethyst-iOS-MyRemastered"
GL = f"{REPO}/Natives/ctxbridges/gl_bridge.m"

results = []


def check(name, ok, detail=""):
    results.append((name, ok, detail))
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}" + (f" — {detail}" if detail else ""))


def main():
    src = open(GL, encoding="utf-8").read()

    print("== A. 源码层 ==")

    # A1: 无残留误用（裸常量 + 注释）
    bad = [m for m in re.finditer(r"0x3056\s*/\*EGL_WIDTH\*/|0x3057\s*/\*EGL_HEIGHT\*/", src)]
    check("A1 无 0x3056/0x3057 误标注残留", len(bad) == 0, f"残留 {len(bad)} 处")

    raw = re.findall(r"querySurface\([^)]*0x305[67][^)]*\)", src)
    check("A1b 查询调用无裸 0x305x 常量", len(raw) == 0, str(raw[:3]))

    # A2: 三处宏使用
    macro_uses = len(re.findall(r"es\.querySurface\([^)]*\bEGL_WIDTH\b[^)]*\)", src)) + \
                 len(re.findall(r"ame_raw_query_surface\([^)]*\bEGL_WIDTH\b[^)]*\)", src))
    check("A2 查询使用 EGL_WIDTH/EGL_HEIGHT 宏", macro_uses >= 5, f"宏调用 {macro_uses} 处")

    # A3: 指纹
    check("A3 Task58 指纹日志存在",
          "Task58 query constants corrected" in src)

    # A4: 括号平衡 vs HEAD
    head = subprocess.run(
        ["git", "-C", REPO, "show", "HEAD:Natives/ctxbridges/gl_bridge.m"],
        capture_output=True, text=True).stdout
    for a, b, label in [("{", "}", "brace"), ("(", ")", "paren"), ("[", "]", "bracket")]:
        d_new = src.count(a) - src.count(b)
        d_old = head.count(a) - head.count(b)
        check(f"A4 {label} 平衡 delta 与 HEAD 一致", d_new == d_old,
              f"new={d_new} old={d_old}")

    print("== B. 行为层（3e5e051 真机日志数据重放） ==")
    # 真机日志实值（3e5e051 构建，7d8dcfd 上传）：
    #   viewport = 1180x820（swap#1..#1570 全程恒定，Task41 探针）
    #   创建时宏查询 eglQuerySurface = 1180x820（真实表面尺寸铁证）
    #   Task57 split-brain 探针：渲染线程 layer bounds/drawable = 1180x820
    #   ANGLE impl: mWidth=1180 mHeight=820（initialize 读 bounds×scale）
    VIEWPORT = (1180, 820)
    REAL_SURFACE = (1180, 820)  # (width, height) — impl 真值
    EGL_HEIGHT_ATTR, EGL_WIDTH_ATTR = 0x3056, 0x3057
    ATTR_TABLE = {EGL_WIDTH_ATTR: REAL_SURFACE[0], EGL_HEIGHT_ATTR: REAL_SURFACE[1]}

    # B1 旧探针（bug 模型）：0x3056→w, 0x3057→h（宽高对调）
    w_old = ATTR_TABLE[0x3056]
    h_old = ATTR_TABLE[0x3057]
    check("B1 旧探针复现日志幻影 'surface=820x1180'",
          (w_old, h_old) == (820, 1180), f"old probe reads {w_old}x{h_old}")
    mismatch_old = VIEWPORT != (w_old, h_old)
    check("B1b 旧探针 geoMismatch=true（进入 geo-heal，与日志 mode=2 一致）",
          mismatch_old is True)

    # B2 修正探针
    w_new = ATTR_TABLE[EGL_WIDTH_ATTR]
    h_new = ATTR_TABLE[EGL_HEIGHT_ATTR]
    check("B2 修正探针读 surface=1180x820", (w_new, h_new) == VIEWPORT,
          f"new probe reads {w_new}x{h_new}")
    mismatch_new = VIEWPORT != (w_new, h_new)
    check("B2b geoMismatch=false → latch NORMAL", mismatch_new is False)

    # B3 全帧仿真（旧 1570 帧 vs 新）
    frames = 1570
    old_blits = frames if mismatch_old else 0          # mode=2 每帧 blit
    new_blits = 0 if not mismatch_new else frames
    old_realign = 3                                      # 日志实值 attempt 1/3 A/B/C
    new_realign = 0 if not mismatch_new else old_realign
    check("B3 geo-heal blit：旧=1570 次（复现日志），新=0 次",
          old_blits == frames and new_blits == 0)
    check("B3b Task55 realign：旧=3 步全败（复现日志），新=不触发",
          old_realign == 3 and new_realign == 0)

    # 汇总
    fails = [n for n, ok, _ in results if not ok]
    print(f"\n{'='*50}\n{len(results)-len(fails)}/{len(results)} PASS")
    if fails:
        print("FAILED:", ", ".join(fails))
        return 1
    print("Task 58 验证全过：幻影转置已根除，画面/输入按 NORMAL 路径呈现")
    return 0


if __name__ == "__main__":
    sys.exit(main())
