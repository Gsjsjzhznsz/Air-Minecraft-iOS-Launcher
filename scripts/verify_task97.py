#!/usr/bin/env python3
"""
Task 97 验证器：进程 CWD 与 -Duser.dir 对齐（桌面启动器等价行为）

背景（2f90d13 装机日志，BMC2 [FABRIC] 1.20.1, 474 mods, 6c3d49d 构建, zink,
iPad Air M4 / iPadOS 27）：
  Task95 修复实证生效后（用户部分采纳建议：移除 certain_questing_additions、
  补齐 balm/kleeslabs/terrablender），启动推进到历史最深（474 mods 全量加载、
  窗口初始化、资源加载、paintings json 解析），随后死于两个 mod 的 'main'
  entrypoint，且两类崩溃同根同源——java.io（进程 CWD）与 java.nio（user.dir）
  两套相对路径解析各看各的目录：
    - paintings 11.0.0.1 PaintingPackReader.scanPacks：nio 门 true（游戏目录有
      resourcepacks/）→ io listFiles() NULL（CWD 没有）→ Arrays.stream(null) NPE；
    - sparsestructures 2.1.2：io 守卫 false 放行 → nio createDirectories 命中
      整合包自带同名文件 → FileAlreadyExistsException: config/sparsestructures.json5。
  桌面启动器永远 CWD == 游戏目录，同样的整合包在桌面无恙。

修复（JavaLauncher.m ame97_alignProcessCwdToGameDir）：两处 JLI_Launch 前
chdir(<gameDir>) + setenv PWD；失败仅告警不阻断。FAQ 28→29（+cwdMismatch）；
version.h REVISION 17 addendum（Task 97, no bump）。

编号说明：本任务在上一会话内完成开发时编号 96，因朋友（前端）推送的
Task96（右面板 MeloNX 信息卡）已占用该号，改号为 97。
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = "/home/z/my-project/Amethyst-iOS-MyRemastered"
PASS, FAIL = 0, 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {detail}")


def read(path):
    with open(os.path.join(REPO, path), encoding="utf-8", errors="replace") as f:
        return f.read()


def git_show(ref_path):
    r = subprocess.run(["git", "-C", REPO, "show", ref_path],
                       capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


print("===== A. 2f90d13 日志证据（钉 git——工作区 latestlog.txt 已被 26.3 上传替换） =====")
log = git_show("2f90d13:latestlog.txt")
check("A0 git fixture 2f90d13 latestlog.txt 在位", len(log) > 1000)
check("A1 会话身份：6c3d49d 构建（Task95 修复版）+ BMC2 fabric-loader-0.15.11-1.20.1",
      "Commit: 6c3d49d (main)" in log
      and "Launching Minecraft fabric-loader-0.15.11-1.20.1-88955f01" in log)
check("A2 历史最深推进：474 mods 全量加载",
      "Loading 474 mods:" in log)
check("A3 paintings 崩溃签名在位（PaintingPackReader + NullPointerException）",
      "subaraki.paintings.utils.PaintingPackReader.scanPacks" in log
      and re.search(r"java\.lang\.NullPointerException", log) is not None)
check("A4 sparsestructures 崩溃签名在位（FileAlreadyExistsException + 精确路径）",
      "java.nio.file.FileAlreadyExistsException: config/sparsestructures.json5" in log
      and "io.github.maxencedc.sparsestructures.SparseStructures.onInitialize" in log)
check("A5 附带证据：log4j 相对路径 ENOENT（CWD 分裂的另一受害者，修复后消失）",
      "Cannot access RandomAccessFile java.io.FileNotFoundException: logs/latest.log" in log)
check("A6 渲染器无关性：zink 会话（LTW/BMC2 前科同一死法家族）",
      "profileRenderer=libOSMesa.8.dylib" in log)

print("===== B. JavaLauncher.m：CWD 对齐实现 =====")
jl = read("Natives/JavaLauncher.m")
check("B1 ame97_alignProcessCwdToGameDir 定义在位（gameDir 空值守卫 + chdir + errno 取证）",
      "static void ame97_alignProcessCwdToGameDir(NSString *gameDir)" in jl
      and "chdir(dir) != 0" in jl
      and "int savedErrno = errno;" in jl)
check("B2 失败非阻断：chdir 失败仅告警继续（维持旧行为）",
      "continuing with unaligned CWD" in jl)
check("B3 PWD 环境变量同步 + 权威回读取证（getcwd）",
      'setenv("PWD", dir, 1);' in jl
      and "[[NSFileManager defaultManager] currentDirectoryPath]" in jl
      and '"[CwdAlign] Task97: process CWD aligned to game dir: %@", nowCwd' in jl)
check("B4 主游戏路径：JLI_Launch 前调用（[Init] Calling JLI_Launch 之前）",
      jl.index("ame97_alignProcessCwdToGameDir(gameDir);")
      < jl.index('NSLog(@"[Init] Calling JLI_Launch");'))
check("B5 headless 路径：headless JLI_Launch 前同样调用",
      jl.count("ame97_alignProcessCwdToGameDir(gameDir);") == 2)
check("B6 注释链完整（根因 + 桌面等价 + 副作用审计 + 失败策略）",
      "Task97: 进程 CWD 与 -Duser.dir 对齐" in jl
      and "桌面启动器等价行为" in jl
      and "副作用审计" in jl)

print("===== C. FAQ 接线（LauncherHelpViewController.m） =====")
helpvc = read("Natives/LauncherHelpViewController.m")
faq_items = re.findall(r"LauncherHelpFaqItem \*(\w+) = \[", helpvc)
check("C1 FAQ 32 条目（Task99 30 +2 macMenuStub/fsrCorner；Task97 29 + Task98 +1 mc26sdl）",
      len(faq_items) == 34, f"got {len(faq_items)}")
check("C2 cwdMismatch 条目在位（两大签名 + [CwdAlign] 验证锚点 + 桌面对照）",
      re.search(r"cwdMismatch\.question.*paintings.*sparsestructures", helpvc, re.S) is not None
      and "listFiles 空指针" in helpvc
      and "[CwdAlign] Task97" in helpvc
      and "桌面端从不双标" in helpvc)
check("C3 注册在故障排除分类（missingMods 之后，Task106 后 sparkProfiler 殿后）",
      re.search(r"@\[ xray, greenFx, background, crash, stuck, bigpack, sodiumLwjgl, missingMods, cwdMismatch, mc26sdl, macMenuStub, sodiumGlsl, sparkProfiler \]", helpvc) is not None)

print("===== D. version.h addendum =====")
vh = read("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("D1 REVISION 17 addendum (Task 97, no bump) 在位且不升版",
      "REVISION 17 addendum (Task 97, no bump)" in vh
      and "#define REVISION 17" in vh)
check("D2 addendum 记录双崩溃签名与修复手段",
      "PaintingPackReader.scanPacks" in vh
      and "FileAlreadyExistsException" in vh
      and "ame97_alignProcessCwdToGameDir" in vh
      and "FAQ 28->29 (+cwdMismatch)" in vh)

print("===== E. 本地 JDK 行为复现（干净 JDK 复现双签名 + 对齐后双痊愈） =====")
repro = os.path.join(REPO, "scripts", "task97_cwd_repro", "CwdRepro.java")
check("E0 复现件在位 + java 可用", os.path.exists(repro)
      and shutil.which("java") is not None)

tmp = None
if os.path.exists(repro) and shutil.which("java"):
    tmp = tempfile.mkdtemp(prefix="task97_", dir="/home/z/my-project")
    game_dir = os.path.join(tmp, "gamedir")       # 模拟游戏目录（user.dir）
    cwd_dir = os.path.join(tmp, "cwddir")         # 模拟未对齐的进程 CWD
    os.makedirs(os.path.join(game_dir, "resourcepacks"))
    os.makedirs(os.path.join(game_dir, "config"))
    with open(os.path.join(game_dir, "resourcepacks", "pack_a.zip"), "w") as f:
        f.write("a")
    with open(os.path.join(game_dir, "resourcepacks", "pack_b.zip"), "w") as f:
        f.write("b")
    # 整合包自带的同名「文件」（sparsestructures 的目标路径）
    with open(os.path.join(game_dir, "config", "sparsestructures.json5"), "w") as f:
        f.write("{}")
    os.makedirs(cwd_dir)

    def run_java(mode, cwd, userdir):
        return subprocess.run(
            ["java", f"-Duser.dir={userdir}", repro, mode],
            cwd=cwd, capture_output=True, text=True, timeout=60)

    # --- 分裂场景：CWD != user.dir（旧启动器形态） ---
    r = run_java("probe", cwd_dir, game_dir)
    lines = r.stdout.strip().splitlines()
    probe = dict(l.replace("PROBE ", "").split("=", 1) for l in lines if l.startswith("PROBE "))
    check("E1 分裂探针：nio 看得见 resourcepacks（user.dir 轨）",
          probe.get("nio.resourcepacks.isdir") == "true", str(probe))
    check("E2 分裂探针：io listFiles 返回 NULL（进程 CWD 轨）——paintings 死因",
          probe.get("io.resourcepacks.listFiles") == "NULL", str(probe))
    check("E3 分裂探针：io 守卫看不见 config 文件 + nio 看得见——sparsestructures 死因",
          probe.get("io.cfg.exists") == "false" and probe.get("nio.cfg.isRegularFile") == "true",
          str(probe))
    r = run_java("paintings", cwd_dir, game_dir)
    check("E4 分裂 paintings：NPE 且栈含 Arrays.stream（与真机同族签名）",
          r.returncode != 0 and "java.lang.NullPointerException" in r.stderr
          and "Arrays.stream" in r.stderr, r.stderr[-300:])
    r = run_java("sparsestructures", cwd_dir, game_dir)
    check("E5 分裂 sparsestructures：FileAlreadyExistsException + 精确路径（逐字同真机）",
          r.returncode != 0 and "java.nio.file.FileAlreadyExistsException" in r.stderr
          and "config/sparsestructures.json5" in r.stderr, r.stderr[-300:])

    # --- 对齐场景：CWD == user.dir（Task97 修复后形态） ---
    r = run_java("probe", game_dir, game_dir)
    lines = r.stdout.strip().splitlines()
    probe2 = dict(l.replace("PROBE ", "").split("=", 1) for l in lines if l.startswith("PROBE "))
    check("E6 对齐探针：两轨合一（listFiles=2 非 NULL，io 守卫看得见）",
          probe2.get("io.resourcepacks.listFiles") == "2"
          and probe2.get("io.cfg.exists") == "true", str(probe2))
    r = run_java("paintings", game_dir, game_dir)
    check("E7 对齐 paintings：正常列目录不崩",
          r.returncode == 0 and "PAINTINGS OK packs=2" in r.stdout, r.stdout + r.stderr[-200:])
    r = run_java("sparsestructures", game_dir, game_dir)
    check("E8 对齐 sparsestructures：守卫正确短路（EXISTS-SKIP，无异常）",
          r.returncode == 0 and "SPARSESTRUCTURES EXISTS-SKIP" in r.stdout, r.stdout + r.stderr[-200:])

if tmp and os.path.exists(tmp):
    shutil.rmtree(tmp, ignore_errors=True)

print("===== F. 仓库卫生 =====")
check("F1 三文件无 Task96/ame96 残留（改号干净）",
      not re.search(r"Task96|ame96_|task96", jl + helpvc + vh))
check("F2 工作日志含 Task 97 条目",
      "Task ID: 97" in read("worklog.md") + read("worklog-archive.md"))
check("F3 本验证器自身在 scripts/ 下",
      os.path.exists(os.path.join(REPO, "scripts", "verify_task97.py")))

print()
if FAIL == 0:
    print(f"RESULT: {PASS}/{PASS + FAIL} PASS")
    sys.exit(0)
else:
    print(f"RESULT: FAILED ({PASS}/{PASS + FAIL})")
    sys.exit(1)
