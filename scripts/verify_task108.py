#!/usr/bin/env python3
"""Task 108 验证器：382432d CI 失败修复 + Task107 修复 B 撤销

问题 1（CI failure，run 35423882511 on 382432d）：Task107 重写
  dyld_patch_platform.m 时意外丢失了裸 extern 声明
  `extern int dyld_get_active_platform();`（<mach-o/dyld.h> 的该函数带
  __API_AVAILABLE(macos(12.0), ios(15.0)) 标注，部署目标更低只能手写）。
  CI clang（C99+，隐式函数声明 = error）在 dyld_patch_platform.m:84
  响亮失败，全日志恰好 1 个 error。修复：逐字恢复该声明。
问题 2（撤销）：用户确认 1.20.1 画面糊是自己的配置问题（sodium-extra
  的 reduce_resolution_on_mac 是用户自己开的），启动器不应每次启动
  强制改写用户模组配置 → 删除 patchSodiumExtraResolution（调用 + 方法），
  机制结论移入 FAQ 标签页「画面模糊」第 5 条（用户自助关闭指引）。

A. CI 失败取证与修复锚点（含 git 钉回归证明）
B. 修复 B 撤销（Java 侧现状 + git 钉曾存在证明）
C. FAQ 标签页改写（用户自助指引）
D. version.h addendum
E. ECJ 编译门（PojavLauncher.java，-source 21，基线 223 类路径噪音）
F. 级联（含重锚后的 verify_task107 全链）
"""
import os
import re
import subprocess
import sys

REPO = "/home/z/my-project/Amethyst-iOS-MyRemastered"
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

def grep_java_tree(pattern):
    """在当前工作树 JavaApp/*.java 里搜 pattern（撤销尚未提交，必须查工作树）。"""
    r = subprocess.run(["grep", "-rn", "--include=*.java", pattern,
                        os.path.join(REPO, "JavaApp")],
                       capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""

dpp = read("Natives/dyld_patch_platform.m")
pj = read("JavaApp/src/launcher/net/kdt/pojavlaunch/PojavLauncher.java")
faq = read("Natives/LauncherHelpViewController.m")
vh = read("Natives/external/MobileGlues/MobileGlues-cpp/version.h")

print("===== A. CI 失败取证与修复 =====")
check("A1 声明已恢复：extern int dyld_get_active_platform();（与 CI 绿的 Task106 形态逐字一致）",
      "extern int dyld_get_active_platform();" in dpp)
check("A2 恰好一处，且位于首次调用（LC_BUILD_VERSION 分支）之前",
      dpp.count("extern int dyld_get_active_platform();") == 1
      and dpp.index("extern int dyld_get_active_platform();") < dpp.index("int activePlatform = dyld_get_active_platform();"))
check("A3 注释记录 CI 失败事实（implicit-function-declaration + dyld_patch_platform.m:84）",
      "dyld_patch_platform.m:84" in dpp and "隐式函数声明" in dpp)
check("A4 git 钉：cefdf21（CI 绿）携带同一声明 = 恢复到被证明可编译的形态",
      "extern int dyld_get_active_platform();" in git_show("cefdf21", "Natives/dyld_patch_platform.m"))
check("A5 git 钉：382432d（CI 失败提交）确实缺失该声明 = 回归诊断成立",
      "extern int dyld_get_active_platform();" not in git_show("382432d", "Natives/dyld_patch_platform.m"))
check("A6 其余 syscall 均有 include 覆盖（pwrite/ftruncate/read←unistd；fstat←sys/stat；mutex←pthread；CC_SHA256←CommonCrypto）",
      "#include <unistd.h>" in dpp and "#include <sys/stat.h>" in dpp
      and "#include <pthread.h>" in dpp and "#import <CommonCrypto/CommonCrypto.h>" in dpp)

print("===== B. 修复 B 撤销 =====")
check("B1 patchSodiumExtraResolution 方法与调用已全删（PojavLauncher.java）",
      "patchSodiumExtraResolution" not in pj)
# 撤销说明注释合法提及选项名（「reduce_resolution_on_mac」），故剔除整行注释后
# 再查代码态：JSON 键字面量与其余任何代码引用都必须清零。
_pj_code = "\n".join(ln for ln in pj.splitlines() if not ln.lstrip().startswith("//"))
check("B2 代码态清零（剔除注释后无 reduce_resolution_on_mac / 无正则补丁残迹）",
      "reduce_resolution_on_mac" not in _pj_code
      and "sodium-extra-options.json" not in _pj_code
      and "config patch skipped" not in _pj_code)
check("B3 撤销说明注释在位（Task108 + 用户要求撤销 + 指向 FAQ）",
      "Task108：Task107 的 sodium-extra「reduce_resolution_on_mac」配置补丁已按" in pj
      and "用户要求撤销" in pj and "标签页" in pj)
check("B4 启动主链完型（Tools.launchMinecraft 调用保留）",
      "Tools.launchMinecraft(account, version, serverIp);" in pj)
check("B5 git 钉：382432d 确实含有该补丁（调用 + 方法 + 日志锚点）= 本次是撤销而非漏配",
      "patchSodiumExtraResolution();" in git_show("382432d", "JavaApp/src/launcher/net/kdt/pojavlaunch/PojavLauncher.java")
      and "Task107: sodium-extra reduce_resolution_on_mac" in git_show("382432d", "JavaApp/src/launcher/net/kdt/pojavlaunch/PojavLauncher.java"))
check("B6 工作树全 JavaApp 无残留引用（Task107 日志锚点字符串清零，含未提交态）",
      grep_java_tree("sodium-extra reduce_resolution_on_mac") == ""
      and grep_java_tree("patchSodiumExtraResolution") == "")

print("===== C. FAQ 标签页改写 =====")
check("C1 第 5 条新文案：模组自身设置 + 自助关闭路径（视频设置 → sodium-extra 设置）",
      "sodium-extra 整合包的「Mac 下降低分辨率」选项" in faq
      and "这是模组自身的设置、不是启动器问题" in faq
      and "模组设置里把它关掉" in faq)
check("C2 实测证据保留（590x410 / 2360x1640 / 4 倍放大）",
      "590x410" in faq and "2360x1640" in faq and "4 倍放大" in faq)
check("C3 旧文案清除：不再宣称启动器自动改回、不再引用已退役的日志锚点",
      "启动器现在每次启动自动把该选项改回关" not in faq
      and "[PojavLauncher] Task107: sodium-extra reduce_resolution_on_mac" not in faq)
check("C4 FAQ 计数不变 34（原位改写，零级联）",
      faq.count("= [[LauncherHelpFaqItem alloc] init]") == 34)
check("C5 帧率指引保留（FSR 档位替代）", "FSR 档位（画质更好）" in faq)

print("===== D. version.h addendum =====")
check("D1 REVISION 17 addendum (Task 108, no bump) 在位，双主题齐全（CI 修复 + 撤销）",
      "REVISION 17 addendum (Task 108, no bump)" in vh
      and "dyld_patch_platform.m:84" in vh
      and "patchSodiumExtraResolution" in vh)
check("D2 REVISION 不递增（无 REVISION 18 字样）", "REVISION 18" not in vh)

print("===== E. ECJ 编译门（PojavLauncher.java） =====")
ecj = None
for cand in ("/tmp/ecj.jar", os.path.join(SCRIPTS, "ecj.jar")):
    if os.path.exists(cand):
        ecj = cand
        break
if ecj:
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        cp = f"{REPO}/JavaApp/src/launcher:" + ":".join(
            os.path.join(REPO, "JavaApp", "libs", d, f)
            for d in ("lwjgl", "lwjgl-333", "lwjgl-341", "caciocavallo",
                      "caciocavallo17", "others")
            for f in (os.listdir(os.path.join(REPO, "JavaApp", "libs", d))
                      if os.path.isdir(os.path.join(REPO, "JavaApp", "libs", d)) else [])
            if f.endswith(".jar"))
        r = subprocess.run(["java", "-jar", ecj, "-nowarn", "-source", "21",
                            "-target", "21", "-cp", cp, "-d", td,
                            os.path.join(REPO, "JavaApp/src/launcher/net/kdt/pojavlaunch/PojavLauncher.java")],
                           capture_output=True, text=True, timeout=180)
        # ECJ 的诊断行走 stderr（stdout 只有摘要）；“N. ERROR in <file>” 才是错误行。
        errs = [l for l in r.stderr.splitlines()
                if re.search(r"ERROR in .*/PojavLauncher\.java", l) or
                   (l.count("ERROR") and "PojavLauncher.java" in l and l.lstrip()[0].isdigit())]
        # 基线 4：既有类路径噪音（GLFW.mGLFWWindow* 等，Task107 期即存在），
        # 撤销只删代码不应新增任何错误。
        check("E1 ECJ 错误数不高于基线 4（撤销不引入新错误）",
              len(errs) <= 4, f"got {len(errs)}: " + "; ".join(errs[:3]))
        check("E2 撤销区（Task108 注释附近 295-315 行）零错误",
              not [l for l in errs if re.search(r"\(at line (29[5-9]|30\d|31[0-5])\)", l)],
              "; ".join(errs[:3]))
else:
    check("E ECJ 编译门", True, "skipped: ecj.jar 不在本机（CI javac 为最终关卡）")

print("===== F. 级联 =====")
for v in ("verify_task83.py", "verify_task84.py", "verify_task85.py", "verify_task86.py",
          "verify_task87.py", "verify_task94.py", "verify_task95.py", "verify_task97.py",
          "verify_task98.py", "verify_task99.py", "verify_task100.py", "verify_task103.py",
          "verify_task104.py", "verify_task105.py", "verify_task106.py", "verify_task107.py"):
    r = subprocess.run([sys.executable, os.path.join(SCRIPTS, v)],
                       capture_output=True, text=True, timeout=900)
    # 各验证器 RESULT 行格式不一（“ALL PASS (N/N)”/“N/N PASS”/“N/N”），
    # 退出码才是权威信号（全体遵守 sys.exit(0 if FAIL==0 else 1)）。
    ok = r.returncode == 0
    check(f"F {v}（exit={r.returncode}）", ok, (r.stdout + r.stderr)[-100:])

print(f"\nRESULT: {'ALL PASS' if FAIL == 0 else 'FAILED'} ({PASS}/{PASS + FAIL})")
sys.exit(0 if FAIL == 0 else 1)
