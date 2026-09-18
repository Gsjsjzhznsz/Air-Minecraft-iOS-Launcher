#!/usr/bin/env python3
"""
Task 95 验证器：96c527f 日志判读（整合包缺失 mod → entrypoint 崩溃）+ 三层防护

背景（96c527f 用户上传，commit 1ee7111 = Task94 修复构建，iPad Air M4 /
iPadOS 27，BMC2 [FABRIC] 1.20.1，536 mods，zink 会话）：
  * Task94 修复装机验证通过："[Tools] LWJGL report version: 3.3.1" +
    "[PojavLauncher] LWJGL selected by launcher: 333, reported version: 3.3.1
    (metadata: 3.3.1)" 双锚点在位，sodium 0.5.13 放行，mod 列表全量打印，
    启动推进到 22:22:02（JVM 后约 24s）——BMC2 历史最深度；
  * 新崩溃与渲染器无关、与 LWJGL 无关：Fabric 'main' entrypoint 阶段
    RuntimeException: Could not execute entrypoint stage 'main' due to errors,
    provided by 'certain_questing_additions'
      Caused by: NoClassDefFoundError: dev/ftb/mods/ftblibrary/config/ui/EditConfigScreen
    + Suppressed: terrablender/api/TerraBlenderApi、net/blay09/mods/balm/api/Balm
      （netherportalfix）等链；
  * 实例 mods 目录缺失 8+ 个 jar：FTB 全家桶（ftbquests/ftblibrary/ftbteams/
    ftbbackups）+ balm + terrablender + kleeslabs——"Loading 536 mods" 列表中
    全部为 0；
  * "Dependencies overridden for certain_questing_additions, kleeslabs,
    netherportalfix, climaterivers, biomeswevegone"（config/fabric-loader.json
    的 dependencyOverrides，fabric-loader 0.19.3 实测字符串）掩盖了 Fabric 的
    硬依赖检查 → 缺失潜伏到运行时才爆；
  * 日志中另发现 anti-AI 提示注入（伪 "System note for AI"），已识别、忽略
    并向用户披露。

修复（三层，全启动器侧，无 MobileGlues 面）：
  1. ModpackImportService：导入收尾持久化实例根目录 import_report.json
     （failed/skipped 清单 + acknowledged 标志；干净重导入会重写清空）；
  2. JavaLauncher [ImportGuard]：JVM 启动前读报告，未确认缺失一次性提醒
     （非阻断，重新导入复位）；
  3. PLCrashView CrashTypeMissingMods：entrypoint 链解析 → 缺失类清单 +
     组件名推断（FTB/Balm/TerraBlender）+ override 证据 → 崩溃界面精确指引。
FAQ 27→28（+missingMods）；version.h REVISION 17 addendum (Task 95, no bump)。
"""
import os
import re
import subprocess
import sys

# Task101：路径改为环境变量可覆盖（与 verify_task96 的 TASK96_REPO 同款约定），
# 默认值保留原克隆路径——该克隆已不存在，本仓库环境下用 TASK95_REPO 指向共享主仓库即可
REPO = os.environ.get("TASK95_REPO", "/home/z/my-project/Amethyst-iOS-MyRemastered")
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


print("===== A. 96c527f 日志证据（钉 git——工作区 latestlog.txt 会随未来上传漂移） =====")
log = git_show("96c527f:latestlog.txt")
check("A0 git fixture 96c527f latestlog.txt 在位", len(log) > 1000)
check("A1 1ee7111 构建（Task94 修复版，非旧 3bc95fa）",
      "Commit: 1ee7111 (main)" in log and "Commit: 3bc95fa" not in log)
check("A2 Task94 双锚点在位（动态上报生效）",
      "[Tools] LWJGL report version: 3.3.1 (from version metadata; sodium PreLaunchChecks gate, Task94)" in log
      and "[PojavLauncher] LWJGL selected by launcher: 333, reported version: 3.3.1 (metadata: 3.3.1)" in log)
check("A3 sodium 门放行：无 not compatible 退出，mod 列表全量打印",
      "not compatible" not in log and "Loading 536 mods:" in log
      and "sodium 0.5.13+mc1.20.1" in log)
check("A4 死于 Fabric main entrypoint（certain_questing_additions）",
      "Could not execute entrypoint stage 'main' due to errors, provided by 'certain_questing_additions'" in log)
check("A5 缺失类链：ftblibrary EditConfigScreen + Balm + TerraBlender",
      "NoClassDefFoundError: dev/ftb/mods/ftblibrary/config/ui/EditConfigScreen" in log
      and "java.lang.ClassNotFoundException: net.blay09.mods.balm.api.Balm" in log
      and "java.lang.NoClassDefFoundError: terrablender/api/TerraBlenderApi" in log)
# A6：已加载 mod 列表（tab 缩进的 "- modid version" 行）中缺失家族计数
mod_lines = re.findall(r"^\t- ([a-z0-9_-]+) ", log, re.M)
loaded = set(mod_lines)
missing_family = [m for m in ("ftbquests", "ftblibrary", "ftbteams", "ftbbackups",
                              "balm", "terrablender", "kleeslabs")
                  if m not in loaded]
check("A6 FTB 全家桶 + balm + terrablender + kleeslabs 全部不在已加载列表",
      len(missing_family) == 7, f"still loaded missing from expected-absent: {missing_family}")
check("A7 dependencyOverrides 掩盖证据在位",
      "Dependencies overridden for certain_questing_additions, kleeslabs, netherportalfix, climaterivers, biomeswevegone" in log)
check("A8 干净 exit(-1)（VM_Exit，非段错误非卡死）",
      "reason: exit(-1) called" in log and "#@!@# Game crashed!" in log)
check("A9 崩溃时间 22:22:02（JVM 后约 24s，历史最深推进：Vanilla bootstrap 完成）",
      "Vanilla bootstrap took 2542 milliseconds" in log and "crash-2026-09-17_22.22.02-client.txt" in log)
check("A10 anti-AI 提示注入在案（已识别并忽略，如实披露）",
      "System note for AI" in log)

print("===== B. ModpackImportService：import_report.json 持久化 =====")
svc = read("Natives/ModpackImportService.m")
check("B1 ame95_writeImportReportToModsDir 方法在位（含 packName/total/success/skipped/failed 六参）",
      re.search(r"- \(void\)ame95_writeImportReportToModsDir:\(NSString \*\)modsDir\s+packName:\(NSString \*\)packName\s+total:\(NSUInteger\)total\s+success:\(NSUInteger\)successCount\s+skipped:\(NSUInteger\)skippedCount\s+failed:\(NSUInteger\)failedCount", svc) is not None)
check("B2 报告落盘实例根目录（modsDir 删尾段）",
      "stringByDeletingLastPathComponent" in svc
      and 'stringByAppendingPathComponent:@"import_report.json"' in svc)
check("B3 报告字段齐备（version/task/acknowledged/failed/skipped）",
      all(k in svc for k in ('@"version": @1', '@"task": @"95"', '@"acknowledged": @NO',
                             '@"failed": failedEntries', '@"skipped": skippedEntries')))
check("B4 调用点在 downloadModFiles 汇总段（NSLog completed 之后、取消检查之前）",
      svc.index("[ModpackImport] Mod download completed") < svc.index("ame95_writeImportReportToModsDir:modsDir")
      and svc.index("ame95_writeImportReportToModsDir:modsDir") < svc.index("if ([self checkCancelledWithError:error]) {", svc.index("ame95_writeImportReportToModsDir:modsDir")))
check("B5 全成功也写报告（清空旧缺失状态，注释语义在位）",
      "即使全部成功也写" in svc)
check("B6 条目封顶 100（防兆级报告）", "kAme95EntryCap = 100" in svc)
check("B7 写失败有 NSLog 取证（FAILED to write import report）",
      svc.count("FAILED to write import report") >= 2)

print("===== C. JavaLauncher：ImportGuard 启动前提醒门 =====")
jl = read("Natives/JavaLauncher.m")
check("C1 ame95_warnIncompleteImport 静态函数在位",
      re.search(r"static void ame95_warnIncompleteImport\(NSString \*gameDir\)", jl) is not None)
check("C2 读实例根目录 import_report.json",
      'stringByAppendingPathComponent:@"import_report.json"' in jl)
check("C3 完整导入不打扰（failed+skipped==0 提前 return）",
      re.search(r"if \(failedCount == 0 && skippedCount == 0\) \{\s*return;", jl) is not None)
check("C4 已确认不再弹（acknowledged 提前 return + 提醒后回写置位）",
      re.search(r'if \(\[report\[@"acknowledged"\] boolValue\]\) \{\s*return;', jl) is not None
      and 'ack[@"acknowledged"] = @YES;' in jl)
check("C5 调用点紧跟 Task87 ModDialogGuard（launchJVM 内、gameDir 就绪处）",
      jl.index("int launchJVM(") < jl.index("ame87_disableDesktopDialogMods(gameDir)")
      < jl.index("ame95_warnIncompleteImport(gameDir)"))
check("C6 非阻断设计（函数无返回值语义 + 明示 launch continues）",
      "launch continues" in jl and "本次将照常启动" in jl)
check("C7 提醒含修复指引（重新导入 + Mod 管理器补齐）",
      "删除该实例并重新导入" in jl and "Mod 管理器中补齐缺失文件" in jl)
check("C8 老实例零打扰（无报告 = 非 Task95 路径，return）",
      "无报告 = 非 Task95 路径导入" in jl)

print("===== D. PLCrashView：CrashTypeMissingMods 分析器 =====")
cv = read("Natives/PLCrashView.m")
check("D1 枚举新增 CrashTypeMissingMods（紧随 CrashTypeMissingLibrary）",
      cv.index("CrashTypeMissingLibrary,") < cv.index("CrashTypeMissingMods,") < cv.index("CrashTypeJavaVersionMismatch"))
check("D2 ame95_detectMissingModsFromLog:lowerLog: 方法在位",
      "- (BOOL)ame95_detectMissingModsFromLog:(NSString *)logContent lowerLog:(NSString *)lowerLog" in cv)
check("D3 只认 Fabric 实证形态（could not execute entrypoint stage，小写匹配）",
      '"could not execute entrypoint stage"' in cv)
check("D4 正则同时抓 ClassNotFoundException / NoClassDefFoundError 类名",
      "(?:ClassNotFoundException|NoClassDefFoundError): ([A-Za-z0-9_.$/]+)" in cv)
check("D5 '/'→'.' 类名归一（JVM 内部态）",
      'stringByReplacingOccurrencesOfString:@"/" withString:@"."' in cv)
check("D6 缺失类封顶 8 条（防错误卡片爆版）",
      "missingClasses.count >= 8" in cv)
check("D7 组件名映射表（FTB 四件套 + FTB 组件 + Balm + TerraBlender）",
      all(s in cv for s in ('@"FTB Quests"', '@"FTB Library"', '@"FTB Teams"',
                            '@"FTB Backups"', '@"FTB 组件"', '@"Balm"', '@"TerraBlender"')))
check("D8 override 证据提取（Dependencies overridden for）",
      '"Dependencies overridden for"' in cv)
check("D9 analyzeCrashType 第 6 区最先做缺失 mod 检测（先于 Mod 冲突泛化分支）",
      cv.index("ame95_detectMissingModsFromLog:logContent lowerLog:lowerLog") < cv.index('// Mod 冲突\n', cv.index("// 6. 基于日志关键词分析")))
check("D10 crashReasonText 有 MissingMods 文案（导入不完整）",
      'case CrashTypeMissingMods:' in cv and "整合包缺失 mod 文件（入口点阶段类加载失败，常见于导入不完整）" in cv)
check("D11 建议卡片：重新导入（点名缺失组件）+ 手动补齐",
      "删除该实例并重新导入整合包" in cv and "missingmods_manual" in cv)
check("D12 建议卡片：override 条目指引（fabric-loader.json）",
      "missingmods_override" in cv and "dependencyOverrides 条目" in cv)
check("D13 建议卡片：分享 latestlog 指引（missingmods_share）",
      "missingmods_share" in cv)
check("D14 无图标键名笔误（doc.text 裸键形态不存在，防复发）",
      re.search(r'@\{@"doc\.text"\s*:', cv) is None)
check("D15 扫描范围限定崩溃报告段（防早段 soft-dep 噪音顶满 8 条封顶）",
      'rangeOfString:@"---- Minecraft Crash Report ----"' in cv
      and 'rangeOfString:@"A detailed walkthrough"' in cv)

print("===== E. FAQ 27→28（+missingMods） =====")
helpvc = read("Natives/LauncherHelpViewController.m")
faq_items = re.findall(r"LauncherHelpFaqItem \*(\w+) = \[", helpvc)
check("E1 32 条目（Task99 +2 macMenuStub/fsrCorner；Task95 +missingMods，Task97 +cwdMismatch，Task98 +mc26sdl）", len(faq_items) == 32, f"got {len(faq_items)}")
check("E2 missingMods 条目在位（问题句含 entrypoint 检索词）",
      "missingMods.question = @\"整合包启动到一半闪退，日志说 Could not execute entrypoint stage？\"" in helpvc)
check("E3 条目三层防护 + 自救步骤齐备（import_report.json / ImportGuard / dependencyOverrides）",
      all(k in helpvc for k in ("import_report.json", "[ImportGuard] Task95", "dependencyOverrides 条目", "FTB Library、Balm、TerraBlender")))
check("E4 注册在故障排除分类（sodiumLwjgl 之后，cwdMismatch/mc26sdl 之前；Task99 后 macMenuStub 殿后）",
      re.search(r"bigpack, sodiumLwjgl, missingMods, cwdMismatch, mc26sdl, macMenuStub \]", helpvc) is not None)

print("===== F. version.h + 级联 stale-sync =====")
vh = read("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("F1 REVISION 17 addendum (Task 95, no bump)",
      "REVISION 17 addendum (Task 95, no bump)" in vh and "#define REVISION 17" in vh)
check("F2 addendum 记录三层修复与装机锚点（ImportGuard / import report / CrashTypeMissingMods）",
      all(k in vh for k in ("ImportGuard", "import_report.json", "CrashTypeMissingMods")))
cascade = {
    "scripts/verify_task83.py": "32 条目",
    "scripts/verify_task84.py": "len(faq_items) == 32",
    "scripts/verify_task85.py": "len(faq_items) == 32",
    "scripts/verify_task86.py": "len(faq_items) == 32",
    "scripts/verify_task87.py": "len(faq_items) == 32",
    "scripts/verify_task94.py": "len(faq_items) == 32",
}
for path, marker in cascade.items():
    content = read(path)
    check(f"F3 {os.path.basename(path)} FAQ 计数已 sync 32", marker in content)
v94 = read("scripts/verify_task94.py")
check("F4 verify_task94 A 区已钉 git 809b847（工作区日志被 96c527f 覆盖）",
      'git_show("809b847:latestlog.txt")' in v94 and 'git_show("809b847:latestlog.old.txt")' in v94)

print("===== G. 检测逻辑行为仿真（真实日志片段 × 等价正则） =====")
# 从 96c527f 日志抽取崩溃报告段，跑与 ObjC 等价的 python 正则，
# 验证提取出的缺失类/组件名正是本案例实锤的三个家族。
seg = log[log.index("---- Minecraft Crash Report ----"):log.index("A detailed walkthrough")]
classes = []
for m in re.finditer(r"(?:ClassNotFoundException|NoClassDefFoundError): ([A-Za-z0-9_.$/]+)", seg):
    cls = m.group(1).replace("/", ".")
    if cls not in classes and len(classes) < 8:
        classes.append(cls)
expected_any = ["dev.ftb.mods.ftblibrary.config.ui.EditConfigScreen",
                "net.blay09.mods.balm.api.Balm",
                "terrablender.api.TerraBlenderApi"]
check("G1 缺失类清单含三个实锤家族",
      all(any(c in cls for cls in classes) for c in expected_any), f"got {classes}")
names = []
for cls in classes:
    name = None
    if cls.startswith("dev.ftb.mods.ftbquests"): name = "FTB Quests"
    elif cls.startswith("dev.ftb.mods.ftblibrary"): name = "FTB Library"
    elif cls.startswith("dev.ftb.mods.ftbteams"): name = "FTB Teams"
    elif cls.startswith("dev.ftb.mods.ftbbackups"): name = "FTB Backups"
    elif cls.startswith("dev.ftb.mods."): name = "FTB 组件"
    elif cls.startswith("net.blay09.mods.balm"): name = "Balm"
    elif cls.startswith("terrablender."): name = "TerraBlender"
    if name and name not in names:
        names.append(name)
check("G2 组件名推断命中 FTB Library + Balm + TerraBlender",
      {"FTB Library", "Balm", "TerraBlender"} <= set(names), f"got {names}")
check("G3 负样本：健康启动日志（无 entrypoint 串）不触发检测",
      "could not execute entrypoint stage" not in log[:log.index("---- Minecraft Crash Report ----")])
# G4：全量扫描 vs 崩溃报告段扫描对照——早段 soft-dep 噪音（frex/emi/lootjs）必须被排除
all_classes = []
for m in re.finditer(r"(?:ClassNotFoundException|NoClassDefFoundError): ([A-Za-z0-9_.$/]+)", log):
    cls = m.group(1).replace("/", ".")
    if cls not in all_classes and len(all_classes) < 8:
        all_classes.append(cls)
check("G4 崩溃报告段限定排除早段噪音（全量扫描会先顶满 frex/emi/lootjs）",
      not any(c.startswith(("io.vram.frex", "dev.emi.emi", "com.almostreliable.lootjs")) for c in classes),
      f"segmented scan got {classes}")
check("G5 对照组：全量扫描（旧行为）确实会被噪音挤占（证明 D15 修复必要性）",
      any(c.startswith(("io.vram.frex", "dev.emi.emi", "com.almostreliable.lootjs")) for c in all_classes),
      f"full scan got {all_classes}")

print()
print(f"===== 结果：{PASS} PASS / {FAIL} FAIL =====")
sys.exit(1 if FAIL else 0)
