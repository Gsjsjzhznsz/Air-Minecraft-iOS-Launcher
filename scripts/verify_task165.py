#!/usr/bin/env python3
"""Task165 验证器：ES/4.0 黑屏真根因（函数解析层）+ 探针/熔断 + Vulkan FSR 结论。

用户反馈（cc9bfe4 上传日志，bc6c0b5 构建 = Task164 修复后的新 IPA）：
  1. "es和4.0依旧黑屏" —— Task164 四项 RCAS 对齐未愈。真根因（本轮法证）：
     黑屏会话 glXGetProcAddress 从未被调用（健康 5.1.0 会话有 own-image
     resolution + SYMBOL THEFT 哨兵行）+ 恰好 10 条 LWJGL "No context is
     current or a function that is not available"（健康会话 0 条）+ Task164
     探针 000000ff（Metal 初始清屏色）+ 挂起 0x0500。因果链：Task154 的
     patch_lwjgl_delegate_dlsym.py 把 GL$1 Delegate 的 provider-library 查找
     名 "eglGetProcAddress" 改成死名 "xglGetProcAddress"（修 Mithril 正确），
     MobileGlues 会话因此落到逐名 dlsym 回退——平铺命名空间把
     glDrawArrays/glTexImage2D/glFramebufferTexture2D（哨兵三件套）解析给
     raw ANGLE 镜像，应用绘制绕过 gl/framebuffer.cpp 的 framebuffer-0
     重定向，FSR1 升采样读了从未被写入的 render texture 并把锐化后的
     纯黑盖在真实画面上。Task161 修好渲染器联动前该破坏不可见（所有后端
     设置实跑 libMobileGL）。
  2. "vulkan你能不能想一下怎么利用fsr" —— 结论维持上游硬限制（零 FSR 符号
     + 伪 EGL，Task154/164 二进制取证）；安全替代（渲染缩放 + CA 拉伸档）
     评估留档 version.h，待用户定夺；GLES/4.0 + 完整 FSR1 @ 60fps 为推荐路径。

修复面：
  A. egl.cpp 导出 xglGetProcAddress（Delegate 死名查找复活，恢复 5.1.0
     解析路由；渲染器门控保证其他渲染器维持 Task154 语义）
  B. FSR1.cpp renderTexture 一次性探针（分层分诊）+ RCAS 运行期熔断
     （首帧双像素全黑 → EASU-only 自愈 + 当帧抢救重绘）
  C. version.h addendum + 公告（task165 置顶 + task164 表述纠正）

用法：python3 scripts/verify_task165.py
"""
import os
import re
import subprocess
import sys
import zipfile

# Task174 可移植化收尾（169/135/164 家法）：173 已移植 14 个深验证器的
# 硬编码路径，本脚本默认值仍是会话本地旧仓路径——级联跑时被 TASK165_REPO
# env 救下、单跑即 FileNotFoundError（egl.cpp 锚）。默认值改为脚本仓两级
# dirname，env 覆盖语义不变。
ROOT = os.environ.get('TASK165_REPO',
                      os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

def rd(rel):
    return open(f"{ROOT}/{rel}", encoding="utf-8", errors="replace").read()

def git_show(rev, path):
    try:
        out = subprocess.run(["git", "-C", ROOT, "show", f"{rev}:{path}"],
                             capture_output=True, text=True, timeout=30)
        return out.stdout if out.returncode == 0 else ""
    except Exception:
        return ""

def strip_code(text):
    """字符状态机剥离 // 与 /* */ 注释与字符串字面量（配平检查用）。"""
    out = []
    i, n = 0, len(text)
    state = "code"
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if state == "code":
            if c == "/" and nxt == "/":
                state = "line"; i += 2; continue
            if c == "/" and nxt == "*":
                state = "block"; i += 2; continue
            if c == '"':
                state = "str"; i += 1; continue
            out.append(c); i += 1
        elif state == "line":
            if c == "\n":
                state = "code"; out.append(c)
            i += 1
        elif state == "block":
            if c == "*" and nxt == "/":
                state = "code"; i += 2; continue
            i += 1
        elif state == "str":
            if c == "\\":
                i += 2; continue
            if c == '"':
                state = "code"
            i += 1
    return "".join(out)

results = []
def check(label, cond):
    results.append((label, bool(cond)))
    print(f"  [{'PASS' if cond else 'FAIL'}] {label}")

print("== A. 根因法证（cc9bfe4 黑屏对 vs a0ac656 健康对）==")
# Task166 重锚：黑屏对从工作树改为 git 钉住（cc9bfe4）——3368468 新上传
# 覆盖了工作树日志且 own-image 行已回归（Task165 路由修复在装机生效），
# 工作树读取法证会随每次用户上传漂移；cc9bfe4 才是本组法证的钉住现场。
# 3368468 新对的判读（Task166 已归档）：路由行回归 + 探针全零 + DSA=1
# -> 解析层已修好，残余黑屏根因 = 强制 DSA（见 Task166）。
blk = git_show("cc9bfe4", "latestlog.txt")
blk_old = git_show("cc9bfe4", "latestlog.old.txt")
healthy = git_show("a0ac656", "latestlog.es")
healthy40 = git_show("a0ac656", "latestlog.4.0")
check("A1 黑屏双会话 Task164 探针均 000000ff（RCAS 复合未落地）",
      "rgba=000000ff" in blk and "rgba=000000ff" in blk_old)
check("A2 黑屏双会话挂起 glErr=0x0500",
      "glErr=0x0500" in blk and "glErr=0x0500" in blk_old)
check("A3 黑屏会话 glXGetProcAddress 路由从未激活（无 own-image 行）",
      "own-image resolution" not in blk and "own-image resolution" not in blk_old)
check("A4 健康会话 own-image 路由存在（该函数只被前端 eglGetProcAddress 触达）",
      "own-image resolution" in healthy and "own-image resolution" in healthy40)
check("A5 LWJGL 函数不可用异常：黑屏各 10 条 / 健康各 0 条",
      blk.count("No context is current") == 10
      and blk_old.count("No context is current") == 10
      and healthy.count("No context is current") == 0
      and healthy40.count("No context is current") == 0)
check("A6 双方同为 libmobileglues.dylib 会话（排除渲染器变量）",
      "RENDERER is set to libmobileglues.dylib" in blk
      and "RENDERER is set to libmobileglues.dylib" in healthy)
check("A7 黑屏会话 fps/swap 健康（黑屏但管线活着的签名）",
      "fps=60 swapOK=169 swapFail=0" in blk_old or ("swapOK=" in blk and "swapFail=0" in blk))

print("== B. egl.cpp xglGetProcAddress（根修）==")
egl = rd("Natives/external/MobileGlues/MobileGlues-cpp/egl/egl.cpp")
check("B1 xglGetProcAddress 定义 + 默认可见性导出",
      "EGL_API EGLAPI __eglMustCastToProperFunctionPointerType EGLAPIENTRY xglGetProcAddress" in egl)
check("B2 渲染器门控（AMETHYST_RENDERER 含 'obileglues'，不匹配 libMobileGL.dylib）",
      'strstr(ame165_renderer, "obileglues")' in egl
      and "getenv(\"AMETHYST_RENDERER\")" in egl)
check("B3 门控不通过返回 nullptr（Delegate 落回逐名 dlsym，Task154 语义保留）",
      re.search(r"xglGetProcAddress\(const char\* procname\) \{[^}]*?return nullptr;", egl, re.S) is not None)
check("B4 委托前端 eglGetProcAddress（egl* 包装 + gl* 走 glXGetProcAddress）",
      "return eglGetProcAddress(procname);" in egl)
check("B5 一次性路由日志锚点（装机验证）",
      "[MG] Task165 xglGetProcAddress: LWJGL delegate resolution routed through the frontend" in egl)
check("B6 include 补齐（cstdlib/cstring）",
      "#include <cstdlib>" in egl and "#include <cstring>" in egl)
check("B7 位于 extern \"C\" 块内（C 符号无 mangle，Delegate 按名可查）",
      egl.find("xglGetProcAddress(const char* procname)") > egl.find('extern "C"'))
check("B8 病历注释含 cc9bfe4 法证锚（跨会话可追溯）",
      "cc9bfe4" in egl and "SYMBOL THEFT" in egl)

print("== C. jar 补丁一致性（查找名 == 导出名）==")
with zipfile.ZipFile(f"{ROOT}/JavaApp/libs/lwjgl-341/lwjgl-opengl.jar") as zf:
    gl1 = zf.read("org/lwjgl/opengl/GL$1.class")
check("C1 lwjgl-341 GL$1.class 死名恰 1 处、原名 0 处",
      gl1.count(b"xglGetProcAddress") == 1 and gl1.count(b"eglGetProcAddress") == 0)
patch = rd("scripts/patch_lwjgl_delegate_dlsym.py")
check("C2 补丁脚本 NEW 串与导出名逐字一致（17 字符）",
      'NEW = b"\\x01\\x00\\x11xglGetProcAddress"' in patch)
check("C3 OSMesa 查找未被改名（zink 路径不受影响）",
      'KEEP = b"OSMesaGetProcAddress"' in patch)
for jar in ("JavaApp/libs/lwjgl-333/lwjgl-opengl.jar", "JavaApp/libs/lwjgl/lwjgl-opengl.jar"):
    with zipfile.ZipFile(f"{ROOT}/{jar}") as zf:
        d = zf.read("org/lwjgl/opengl/GL$1.class")
    check(f"C4 {jar.split('/')[-2]} 无该查找（无 eglGetProcAddress 定制，不受影响）",
          b"xglGetProcAddress" not in d and b"eglGetProcAddress" not in d)

print("== D. FSR1.cpp 探针 + RCAS 熔断 ==")
fsr = rd("Natives/external/MobileGlues/MobileGlues-cpp/gl/FSR1/FSR1.cpp")
check("D1 renderTexture 一次性探针（EASU 前读渲染 FBO 中心）",
      "Task165 render-texture probe: center pixel" in fsr
      and "glBindFramebuffer(GL_READ_FRAMEBUFFER, FSR1_Context::g_renderFBO);" in fsr)
check("D2 探针分诊语义（nonzero=重定向健康 / all-zero=解析层嫌疑）",
      "redirect healthy" in fsr and "resolution-layer suspect" in fsr)
check("D3 熔断闩锁 static + rcasOn 门控",
      "static bool s_ame165_rcasBailout = false;" in fsr
      and "!s_ame165_rcasBailout;" in fsr)
check("D4 熔断双像素判定（角+心 RGB 全零且 alpha==0xff 排除读回失败）",
      "ame164_px[3] == 0xff" in fsr and "ame165_cx[3] == 0xff" in fsr)
check("D5 熔断当帧抢救（切回 EASU 程序/纹理/单元直画 fb0）",
      re.search(r"s_ame165_rcasBailout = true;.*?glUseProgram\(FSR1_Context::g_fsrProgram\);"
                r".*?glBindTexture\(GL_TEXTURE_2D, FSR1_Context::g_renderTexture\);"
                r".*?glBindFramebuffer\(GL_DRAW_FRAMEBUFFER, 0\);.*?glDrawArrays", fsr, re.S) is not None)
check("D6 熔断日志锚点（EASU-only 退路声明）",
      "Task165 RCAS runtime bail-out" in fsr and "EASU-only (Task83 single-pass)" in fsr)
recreate_body = fsr[fsr.find("void RecreateFSRFBO()"):fsr.find("std::vector<std::pair<GLsizei, GLsizei>> g_viewportStack;")]
check("D7 闩锁会话级（RecreateFSRFBO 函数体不触碰闩锁——尺寸重建不复装已证伪链）",
      "s_ame165_rcasBailout" not in recreate_body)

print("== E. 行为镜像（Python 状态机）==")
def mirror_first_frame(corner, center, alpha_ok=True):
    """返回 (bailout_latched, rescue_draw, easu_only_next)。"""
    corner_rgb_black = all(v == 0 for v in corner[:3])
    center_rgb_black = all(v == 0 for v in center[:3])
    a_ff = alpha_ok
    latched = corner_rgb_black and a_ff and center_rgb_black and a_ff
    return latched, latched, latched  # 抢救重绘与后续帧路径同闩锁
cases = [
    ("角黑+心黑+读回健康 -> 熔断", (0, 0, 0, 255), (0, 0, 0, 255), True, (True, True, True)),
    ("角黑+心活 -> 不熔断（局部黑非整帧）", (0, 0, 0, 255), (91, 44, 11, 255), True, (False, False, False)),
    ("角活 -> 不熔断", (200, 133, 63, 255), (0, 0, 0, 255), True, (False, False, False)),
    ("读回失败（alpha=0）-> 不熔断（无证据不判死）", (0, 0, 0, 0), (0, 0, 0, 0), False, (False, False, False)),
]
ok_all = True
for name, c, m, a, expect in cases:
    got = mirror_first_frame(c, m, a)
    ok = got == expect
    ok_all &= ok
    print(f"    [{name}] {'PASS' if ok else 'FAIL'}")
results.append(("E1 熔断状态机四案例", ok_all))

def mirror_gate(renderer):
    """xglGetProcAddress 渲染器门控镜像。"""
    return renderer is not None and "obileglues" in renderer
gates = [
    ("libmobileglues.dylib", True), ("libMobileGL.dylib", False),
    ("libMobileGL-gles.dylib", False), ("libmithril.dylib", False),
    ("libOSMesa.8.dylib", False), (None, False),
]
ok_all = all(mirror_gate(r) == e for r, e in gates)
print(f"    门控六案例 {'PASS' if ok_all else 'FAIL'}")
results.append(("E2 渲染器门控六案例（MobileGlues 独占服务）", ok_all))

print("== F. 语法与文档 ==")
for path in ("Natives/external/MobileGlues/MobileGlues-cpp/egl/egl.cpp",
             "Natives/external/MobileGlues/MobileGlues-cpp/gl/FSR1/FSR1.cpp"):
    s = strip_code(rd(path))
    check(f"F 配平 {path.split('/')[-1]}",
          s.count("{") == s.count("}") and s.count("(") == s.count(")"))
vh = rd("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("F3 version.h Task165 addendum（含 Vulkan FSR 评估留档）",
      "REVISION 17 addendum (Task 165, no bump)" in vh
      and "patch_lwjgl_delegate_dlsym.py" in vh)

print("== G. 公告 ==")
import json
anns = json.load(open(f"{ROOT}/announcements.json"))["announcements"]
t165 = next((a for a in anns if a.get("id") == "task165-blackscreen-rootcause-2026-09-25"), None)
# Task166 重锚：task166 公告（Vulkan FSR + DSA 根因）置顶后，task165
# 退居第二位——置顶区口径从 anns[0] 放宽为前两位（新公告惯例： prepend）。
# Task167 重锚：task167（双失效根因修复）置顶后，task165 退居第三位——
# 置顶区口径放宽为前三位（同惯例）。
# Task169 重锚：用户点名服务器推荐置顶（pin 字段）+ task169 四连修公告与
# v6.0.0 发行文案改写插入，2026-09-25 同日组现有 6 条——置顶区口径放宽为
# 前六位（task165 现居第 6：server(pin) / task169 / v6.0.0 / task167 /
# task166 / task165）。
# Task170 诚实重锚：task170 公告 prepend 后同日组再增一位，窗口 7 -> 8
# （家法先例：task169 时代 top-3 -> top-6 -> top-7 同款顺延）。
# Task171 顺延：task171 公告再 prepend 一位，窗口 8 -> 9（同款家法）。
# Task172 顺延：task172 公告再 prepend 一位，窗口 9 -> 10（同款家法）。
# Task173 顺延（并行撞号改号）：task173 公告再 prepend 一位，窗口 10 -> 11（同款家法）。
# Task173-ten 顺延（并行会话）：十症状公告插 anns[3]，task165 再 +1，窗口 11 -> 12。
# Task174 顺延：task174 公告再 prepend 一位，窗口 12 -> 13（同款家法）。
# Task178 顺延：task178 公告再 prepend 一位，窗口 15 -> 16（同款家法）。
check("G1 task165 公告置顶区（Task178 重锚：同日组前十六位；server-pin + Task178/177/169/175/174/双173/172/171/170/168 prepend 后）且内容含根因与装机锚点",
      t165 is not None and any(anns[i]["id"] == "task165-blackscreen-rootcause-2026-09-25" for i in range(min(16, len(anns))))
      and "Task165 xglGetProcAddress" in t165.get("content", ""))
t164 = next((a for a in anns if a.get("id") == "task164-fsr-blackscreen-defaults-2026-09-25"), None)
check("G2 task164 表述纠正（第一轮未愈，指向真根因）",
      t164 is not None and "第一轮修复" in t164.get("summary", "")
      and "真根因" in t164.get("summary", "")
      and "Task165" in t164.get("summary", ""))

fails = [l for l, ok in results if not ok]
print(f"\n==== Task165: {len(results) - len(fails)}/{len(results)} ====")
if fails:
    print("FAILED:")
    for l in fails:
        print("  -", l)
sys.exit(1 if fails else 0)
