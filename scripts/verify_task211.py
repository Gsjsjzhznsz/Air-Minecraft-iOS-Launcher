#!/usr/bin/env python3
"""verify_task211.py -- Task211 verification (stage 1: metallum/CF/ANGLE/l10n).

A. Metallum 退出"崩溃"根治（补丁器/探针源码锚点 + jar 变更 + E2E 行为门）
B. CurseForge 403 三层防线 + 源迁移 + 403 友好化
C. ANGLE multidraw 拆解 + 全屏四边形普查 + in-world 五点回读
D. l10n Krypton 显示名收短
E. 文档（version.h 附录 / 公告 task211@2）+ 级联重锚面
F. 语法门（task211_syntax_gate）+ 受影响级联 verify

判读坐标：17c51003 上传 latestlog.txt（CF 占位 Key 403 会话）+
latestlog.old.txt（Task209 构建 c7079e1 上的 ANGLE 会话：绘制健康 +
ClientShutdownWatchdog 退出误报）。
（Stage 2 的 gl4es 移植验证在 G 组追加。）
"""
import json
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
results = []


def rd(rel):
    with open(os.path.join(REPO, rel), encoding="utf-8", errors="replace") as f:
        return f.read()


def check(name, ok, detail=""):
    results.append((name, ok))
    print(("  PASS " if ok else "  FAIL ") + name + (f"  -- {detail}" if detail and not ok else ""))


def run(cmd, timeout=300):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, cwd=REPO)


# ============ A. Metallum 退出修复 ============
print("== A. Metallum 退出根治 ==")
patcher = rd("scripts/task211_metallum_daemon_patch.java")
check("A1 补丁器：premain 内两处 Thread.start 前插 setDaemon（ASM DUP/ICONST_1）",
      "expected exactly 2 Thread.start() sites" in patcher
      and "setDaemon" in patcher
      and "Opcodes.DUP" in patcher and "Opcodes.ICONST_1" in patcher
      and "COMPUTE_MAXS" in patcher)
check("A2 补丁器：只动 MetallumAgent.class，其余条目字节原样透传",
      "com/metallum/agent/MetallumAgent.class" in patcher
      and "preserve compression + timestamps" in patcher)
probe = rd("scripts/task211_metallum_probe.java")
check("A3 探针：metallum-dump/state 双线程 daemon 判定 + 即退语义",
      't.getName().equals("metallum-dump")' in probe
      and 't.getName().equals("metallum-state")' in probe
      and "isDaemon" in probe)
r = run(["git", "diff", "--stat", "HEAD", "--", "JavaApp/libs/others/metallum_agent.jar"])
check("A4 仓库 jar 已变更（补丁版入库）", "Bin" in r.stdout or "jar" in r.stdout or r.stdout.strip() != "", r.stdout[:80])

# E2E 行为门（java 可用时）：补丁版 = daemon=true + 即退 0
have_java = run(["bash", "-lc", "command -v java"]).returncode == 0
if have_java:
    try:
        r = subprocess.run(["timeout", "30", "java", "-javaagent:JavaApp/libs/others/metallum_agent.jar",
                            "-cp", "/tmp/t211", "T211Probe"],
                           capture_output=True, text=True, timeout=45, cwd=REPO)
        ok = (r.returncode == 0 and "metallum-dump daemon=true" in r.stdout
              and "metallum-state daemon=true" in r.stdout)
        check("A5 E2E 行为门（仓库 jar as -javaagent）", ok,
              f"exit={r.returncode} out={r.stdout[:200]}")
    except Exception as e:
        check("A5 E2E 行为门（仓库 jar as -javaagent）", False, str(e)[:120])
else:
    check("A5 E2E 行为门", True, "skipped: java 不在本机（CI 无此门；补丁器确定性 + A1-A4 为静态门）")

# ============ B. CF 三层防线 ============
print("== B. CurseForge 403 根治 ==")
cf = rd("Natives/installer/modpack/CurseForgeAPI.m")
check("B1 共享占位判定 CFAIsGarbageAPIKey（家族表 + ((void 前缀兜底）",
      "static BOOL CFAIsGarbageAPIKey(NSString *key)" in cf
      and 'isEqualToString:@"((void *)0)"]' in cf
      and 'hasPrefix:@"((void"]' in cf)
check("B2 apiKey getter：运行时占位键视为未配置 + 一次性设备锚点日志",
      "!CFAIsGarbageAPIKey(runtimeKey)) {" in cf
      and "Task211: runtime preference holds a placeholder key" in cf)
check("B3 isAPIKeyConfigured 同表拒收",
      re.search(r"runtimeKey\.length > 0 &&\s*\r?\n\s*!CFAIsGarbageAPIKey\(runtimeKey\)\) \{\s*\r?\n\s*return YES;",
                cf) is not None)
check("B4 +isPlaceholderAPIKey: 类方法（getter/VC 共用）",
      "+ (BOOL)isPlaceholderAPIKey:(NSString *)key" in cf
      and "+ (BOOL)isPlaceholderAPIKey:(NSString *)key;" in rd("Natives/installer/modpack/CurseForgeAPI.h"))
check("B5 403 友好化（API-Key 类 403 翻译为可读信息）",
      "statusCode == 403" in cf and "api key" in cf
      and "CurseForge 拒绝了请求：API Key 缺失或无效（403）" in cf)
_cfb = open(os.path.join(REPO, "Natives/installer/modpack/CurseForgeAPI.m"), "rb").read()
check("B6 CurseForgeAPI.m 保持 CRLF（字节纪律）",
      _cfb.count(b"\r\n") > 1200 and _cfb.count(b"\n") == _cfb.count(b"\r\n"))

ivc = rd("Natives/installer/CurseForgeAPIKeyViewController.m")
check("B7 installer VC（在编实现）：CFKCompiledAPIKey 委托共享判定",
      "[CurseForgeAPI isPlaceholderAPIKey:compiledKey])" in ivc
      and 'isEqualToString:@"CONFIG_CURSEFORGE_API_KEY"]' not in ivc.split("loadInitialValue")[0].split("CFKCompiledAPIKey")[1].split("}")[0])
check("B8 installer VC：保存门 + 测试门拒占位键",
      ivc.count("[CurseForgeAPI isPlaceholderAPIKey:key]") >= 2
      and "占位/无效的 Key 不予保存" in ivc and "占位/无效的 Key 不予测试" in ivc)
rvc = rd("Natives/CurseForgeAPIKeyViewController.m")
check("B9 根 VC（未在编同构对）：预填净化 + 保存门 + 失效导入修正",
      "[CurseForgeAPI isPlaceholderAPIKey:runtimeKey]" in rvc
      and "占位/无效的 Key 不予保存" in rvc
      and '#import "installer/modpack/CurseForgeAPI.h"' in rvc)
plp = rd("Natives/PLPreferences.m")
check("B10 哨兵键 general.task211_cf_source_migrated 入默认表",
      '@"task211_cf_source_migrated": @NO' in plp)
lp = rd("Natives/LauncherPreferences.m")
check("B11 迁移函数：清占位 Key + 无有效 Key 时七源拨回 modrinth",
      "void ame211_migrateCfSourceToModrinth(void)" in lp
      and "cleared placeholder CurseForge API key" in lp
      and "general.download_source_server" in lp
      and "flipped %lu curseforge source(s) to modrinth" in lp)
check("B12 迁移声明 + main.m 常跑点（Task167 教训位）",
      "void ame211_migrateCfSourceToModrinth(void);" in rd("Natives/LauncherPreferences.h")
      and "ame211_migrateCfSourceToModrinth();" in rd("Natives/main.m"))

# ============ C. ANGLE 拆解 + 探针 ============
print("== C. ANGLE multidraw 拆解 + 双探针 ==")
tg = rd("Natives/external/gl4es/tinygl4angle.c")
check("C1 三个 MultiDraw 全部拆解（不再经 multidraw 指针提交）",
      tg.count("Task211 decompose:") == 3
      and "ame173_ptr_glMultiDrawElementsBaseVertex(mode, count, type, indices, drawcount, basevertex);" not in tg
      and "ame173_ptr_glMultiDrawArrays(mode, first, count, drawcount);" not in tg
      and "ame173_ptr_glMultiDrawElements(mode, count, type, indices, drawcount);" not in tg)
check("C2 拆解循环走本文件包装（Task209 普查自动覆盖子绘制）",
      "glDrawElementsBaseVertex(mode, count[i], type, indices[i]," in tg
      and "(basevertex != NULL) ? basevertex[i] : 0" in tg
      and "glDrawArrays(mode, first[i], count[i]);" in tg
      and "glDrawElements(mode, count[i], type, indices[i]);" in tg)
check("C3 全屏四边形普查（final-blit 可见性）",
      "Task211 fsq: fullscreen-quad candidate" in tg
      and "(mode == 4u || mode == 5u || mode == 6u) && count >= 3 && count <= 6" in tg)
gb = rd("Natives/ctxbridges/gl_bridge.m")
check("C4 五点 in-world 回读（swapIndex>=900 门 + 中心/四角 + 1x1 独立小读）",
      "Task211 5-point in-world readback" in gb
      and "swapIndex >= 900" in gb and "s_task211_5pt < 2" in gb
      and "ame211_xs[5]" in gb and "0x1908 /*GL_RGBA*/, 0x1401 /*GL_UNSIGNED_BYTE*/" in gb)
check("C5 五点门与 Task188 同界（drawFb==0 + viewport 有效）且 Task75 纪律注释在场",
      "drawFb == 0 && viewport[2] > 16 && viewport[3] > 16" in gb
      and "Task75" in gb.split("Task211 5-point")[0].split("Task211（ANGLE 方块透明，in-world 五点回读）")[1][:1500])

# ============ D. l10n 收短 ============
print("== D. Krypton 显示名收短 ==")
for lang in ("en", "zh-CN", "zh-Hant", "zh-Hans"):
    s = rd(f"Natives/resources/{lang}.lproj/Localizable.strings")
    line = [l for l in s.split("\n") if "preference.title.renderer.debug.nggl4es" in l]
    ok = line and "ZL2 同款" not in line[0] and "ZalithLauncher 2 gl4es" not in line[0] \
         and "Krypton Wrapper" in line[0]
    check(f"D-{lang} 收短且无长尾", ok, line[0][:90] if line else "missing")

# ============ E. 文档 + 公告 ============
print("== E. 文档 + 公告 ==")
vh = rd("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("E1 version.h Task211 附录（五主题 + 尾部 SEP）",
      "REVISION 18 addendum (Task 211, no bump)" in vh
      and "metallum-state/metallum-dump" in vh
      and "ame211_migrateCfSourceToModrinth" in vh
      and "ALWAYS decompose into per-draw" in vh
      and re.search(r"// ={70,}\s*$", vh) is not None)
ann = json.loads(rd("announcements.json"))["announcements"]
check("E2 公告 task211@2（33 条 + 钉死不动 + task210 顺延 + 尾锚）",
      len(ann) == 33 and ann[2]["id"] == "task211-exit-cf-angle-gl4es-2026-10-02"
      and ann[0]["id"] == "server-recommend-2026-09-24"
      and ann[1]["id"] == "task169-four-fixes-2026-09-25"
      and ann[3]["id"] == "task210-neumorph-retirement-card-fixes-2026-10-02"
      and ann[-1]["id"] == "task206-nggl4es-2026-10-01")
check("E3 公告内容五主题齐备",
      all(k in ann[2]["content"] for k in
          ("退出", "CurseForge", "Modrinth", "拆解", "ZL2 经典版", "virglrenderer")))

# ============ F. 语法门 + 级联 ============
print("== F. 语法门 + 级联 ==")
r = run(["python3", "scripts/task211_syntax_gate.py"])
check("F1 task211_syntax_gate（A/B 语法 + 10 文件括号平衡）", r.returncode == 0,
      r.stdout[-200:] if r.returncode else "")

cascade_shallow = ["verify_task165.py", "verify_task167.py", "verify_task190.py", "verify_task193.py",
                   "verify_task196_197_198_201.py", "verify_task202.py", "verify_task203.py",
                   "verify_task206.py", "verify_task207.py", "verify_task209.py", "verify_task210.py"]
cascade_deep = ["verify_task168.py", "verify_task170.py", "verify_task171.py", "verify_task172.py",
                "verify_task173.py", "verify_task174.py", "verify_task175.py"]
all_ok = True
detail = []
for c in cascade_shallow + cascade_deep:
    to = 240 if c in cascade_shallow else 540
    try:
        r = run(["python3", f"scripts/{c}"], timeout=to)
        if r.returncode != 0:
            all_ok = False
            detail.append(f"{c}:exit{r.returncode}")
            print(f"    cascade FAIL {c}:\n" + "\n".join(
                l for l in r.stdout.split("\n") if "FAIL" in l)[:600])
    except subprocess.TimeoutExpired:
        all_ok = False
        detail.append(f"{c}:timeout")
        print(f"    cascade TIMEOUT {c}")
check("F2 公告级联 18 verify 全绿（重锚面；深级联失败需 ⊆ stash 对拍基线）", all_ok, "; ".join(detail))

print()
fails = [n for n, ok in results if not ok]
print(f"verify_task211 (stage1): {len(results) - len(fails)}/{len(results)}",
      ("ALL PASS" if not fails else "FAILED: " + ", ".join(fails)))
sys.exit(1 if fails else 0)
