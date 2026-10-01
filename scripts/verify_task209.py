#!/usr/bin/env python3
"""verify_task209.py -- Task209 verification.

A. 用户点名改名 NG-GL4ES -> Krypton Wrapper（≤26.2）五面落地
B. ANGLE "PC 红鲱鱼" 定谳与 Task208 幽灵重定向退役
C. tinygl4angle 四叉取证探针（绘制族普查 / 状态快照 / 纹理格式 / ESSL dump）
D. 文档（version.h / 公告 @2 / worklog）+ 级联

判读坐标：88fa3f6 上传 latestlog.txt（构建 59b4f25）；红鲱鱼定谳的资产/
代码双铁证（client-263.jar 零 push_constant + CFR 反编译双命名）见
spvc_shim.c 的 Task209 定谳注释与 worklog.md Task 209 条目。
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


# ============ A. 改名五面 ============
print("== A. NG-GL4ES -> Krypton Wrapper（<=26.2）五面 ==")
l10n_expect = {
    "zh-Hans": "Krypton Wrapper（≤26.2）- ZL2 同款 gl4es，老版本首选（原 NG-GL4ES）",
    "zh-CN": "Krypton Wrapper（≤26.2）- ZL2 同款 gl4es，老版本首选（原 NG-GL4ES）",
    "zh-Hant": "Krypton Wrapper（≤26.2）- ZL2 同款 gl4es，舊版本首選（原 NG-GL4ES）",
    "en": "Krypton Wrapper (≤26.2) - ZalithLauncher 2 gl4es, first choice for legacy versions (formerly NG-GL4ES)",
}
ok_a1 = True
for lg, want in l10n_expect.items():
    s = rd(f"Natives/resources/{lg}.lproj/Localizable.strings")
    line = f'"preference.title.renderer.debug.nggl4es" = "{want}";'
    if line not in s or s.count("preference.title.renderer.debug.nggl4es") != 1:
        ok_a1 = False
check("A1 l10n 四主语言新值（≤26.2 + 原名别名）", ok_a1)

vm = rd("Natives/VersionManagerViewController.m")
check("A2 VersionManager 短名 = Krypton Wrapper（渲染器键值映射不动）",
      '@ RENDERER_NAME_NGGL4ES: @"Krypton Wrapper"' in vm
      and '@ RENDERER_NAME_NGGL4ES: @"NG-GL4ES"' not in vm)

ai = rd("Natives/AI/AiSettingsTools.m")
check("A3 AI 面（友好名新名在前 + 提示词键表两处 + 子串包含序不回退）",
      'return @"Krypton Wrapper/NG-GL4ES (libnggl4es.dylib)"' in ai
      and "auto/GL4ES/Krypton Wrapper" in ai
      and "GL4ES/Krypton Wrapper/NG-GL4ES/ANGLE" in ai
      and 0 <= ai.find('containsString:@"nggl4es"') < ai.find('containsString:@"gl4es"])')
      and ai.find('containsString:@"nggl4es"') < ai.find('return @(RENDERER_NAME_GL4ES)'))

faq_files = [("Natives/resources/help-faq.json", 2), ("help-faq.json", 2),
             ("Natives/resources/zh-CN.lproj/help-faq.json", 2),
             ("Natives/resources/zh-Hant.lproj/help-faq.json", 1),
             ("Natives/resources/en.lproj/help-faq.json", 1)]
ok_counts = ok_fidelity = ok_rename = True
for rel, ind in faq_files:
    raw = open(os.path.join(REPO, rel), "rb").read()
    obj = json.loads(raw.decode("utf-8"))
    if [len(c["items"]) for c in obj["categories"]] != [12, 4, 7, 15]:
        ok_counts = False
    if (json.dumps(obj, ensure_ascii=False, indent=ind) + "\n").encode("utf-8") != raw:
        ok_fidelity = False
zh_sel = json.loads(rd("Natives/resources/help-faq.json"))["categories"][0]["items"]
en_sel = json.loads(rd("Natives/resources/en.lproj/help-faq.json"))["categories"][0]["items"]
ht_sel = json.loads(rd("Natives/resources/zh-Hant.lproj/help-faq.json"))["categories"][0]["items"]
if not ("Krypton Wrapper（≤26.2，原 NG-GL4ES）" in zh_sel[0]["description"]
        and "老版本优先 Krypton Wrapper" in zh_sel[0]["description"]
        and "Krypton Wrapper（原 NG-GL4ES）是什么" in zh_sel[2]["title"]
        and "原名 NG-GL4ES" in zh_sel[2]["description"]):
    ok_rename = False
if not ("Krypton Wrapper first" in en_sel[0]["description"]
        and "formerly NG-GL4ES" in en_sel[2]["description"]
        and "老版本優先 Krypton Wrapper" in ht_sel[0]["description"]):
    ok_rename = False
check("A4 FAQ 五份（计数不变 + 保真 roundtrip + 三语新名/别名）",
      ok_counts and ok_fidelity and ok_rename
      and open(os.path.join(REPO, "help-faq.json"), "rb").read()
      == open(os.path.join(REPO, "Natives/resources/help-faq.json"), "rb").read())

uh = rd("Natives/utils.h")
check("A5 存储键零迁移（libnggl4es.dylib 语义不动）",
      '#define RENDERER_NAME_NGGL4ES "libnggl4es.dylib"' in uh)

# ============ B. 红鲱鱼退役 ============
print("== B. PC 红鲱鱼定谳 + Task208 重定向退役 ==")
shim = rd("Natives/spvc_shim.c")
log = rd("latestlog.txt")  # 59b4f25 ANGLE 会话（88fa3f6 上传）

check("B1 装机证据（59b4f25）：重定向锚点 0 命中 + _push_constants 大量 NOT FOUND",
      "Commit: 59b4f25" in log
      and log.count("Task208: push-constant block rename redirected") == 0
      and log.count("name='_push_constants') -> 4294967295") >= 100,
      f"anchors={log.count('Task208: push-constant block rename redirected')}")

check("B2 幽灵代码三删（函数定义/重定向变量/锚点日志；注释里的退役记述合法）",
      "ame208_find_push_constant(" not in shim
      and "ame208_pcVar" not in shim
      and "ame208_redirected" not in shim
      and "[spvc-shim] Task208: push-constant block rename redirected" not in shim)

check("B3 重放回归纯形态（原样 id 逐条转发）",
      "real_set_name(es_compiler, orig->names[i].id, orig->names[i].name);" in shim
      and "Task209：纯重放（原样 id）" in shim)

check("B4 Task209 定谳注释（零 PC 块 + MC 双命名 + 0x2000021 + 反编译出处）",
      "Task209（红鲱鱼清算）" in shim
      and "零 push_constant 块" in shim
      and "_push_constants_instance" in shim
      and "0x2000021" in shim
      and "renameDescriptors case 9" in shim)

check("B5 Task206 选项保留（未来真 PC 块版本需要；与 MC 桌面选项集一致）",
      "AME206_OPTION_GLSL_PUSH_CONST_AS_UBO" in shim
      and shim.count("AME206_OPTION_GLSL_PUSH_CONST_AS_UBO") >= 3
      and '"[spvc-shim] Task206: EMIT_PUSH_CONSTANT_AS_UNIFORM_BUFFER "' in shim)

# ============ C. 四叉探针 ============
print("== C. tinygl4angle Task209 探针 ==")
tg = rd("Natives/external/gl4ses/tinygl4angle.c"
        if os.path.exists(os.path.join(REPO, "Natives/external/gl4ses/tinygl4angle.c"))
        else "Natives/external/gl4es/tinygl4angle.c")

check("C1 状态快照（blend/depth/mask/drawFb + 单元 0-3 + active 恢复）",
      "static void ame209_draw_state(const char *ame209_tag)" in tg
      and "GL_BLEND_SRC_RGB" in tg and "GL_COLOR_WRITEMASK" in tg
      and "GL_DRAW_FRAMEBUFFER_BINDING" in tg
      and "GL_TEXTURE_BINDING_2D" in tg
      and tg.count("ame209_ptr_activeTex((GLenum)ame209_act);") == 1)

check("C2 BaseVertex 族普查（统一计数 + 大规模必采 + 状态联动）",
      "static int ame209_bv_sample(int ame209_big)" in tg
      and "ame209_bv_sample(count >= 1024)" in tg
      and "ame209_bv_sample(count >= 1024 || instancecount >= 4)" in tg
      and "ame209_bv_sample(ame209_c0 >= 1024 || drawcount >= 16)" in tg
      and tg.count("ame209_draw_state(") >= 6)

check("C3 glDrawArraysInstanced 大规模通道（BIG 必采 + 状态）",
      "Task209 draw: glDrawArraysInstanced BIG" in tg
      and 'ame209_draw_state("DrawArraysInstancedBIG")' in tg
      and 'ame209_draw_state("DrawArraysInstanced")' in tg)

check("C4 纹理上传法证（TexImage/TexSubImage 格式 + 三阈值采样）",
      "Task209 tex: glTexImage2D" in tg and "Task209 tex: glTexSubImage2D" in tg
      and "ifmt=0x%04X" in tg and "ame209_px >= 1000000u" in tg
      and tg.count("% 4096) == 0") >= 2)

check("C5 地形族 ESSL dump（签名 + 大源 + begin/end 标记 + 4 次上限）",
      'strstr(ame209_src, "sphericalVertexDistance")' in tg
      and "ame209_l0 >= 3800" in tg
      and "Task209 ESSL dump #%d begin" in tg
      and "Task209 ESSL dump #%d end <<<" in tg
      and "s_ame209_dumpN < 4" in tg)

stub = rd("scripts/task179_inc/GL/gl.h")
check("C6 stub gl.h 九枚举（值对 vgpu const.h/gles.h 核验）",
      "#define GL_BLEND_SRC_RGB 0x80C9" in stub
      and "#define GL_BLEND_DST_RGB 0x80C8" in stub
      and "#define GL_DEPTH_TEST 0x0B71" in stub
      and "#define GL_DEPTH_FUNC 0x0B74" in stub
      and "#define GL_COLOR_WRITEMASK 0x0C23" in stub
      and "#define GL_DRAW_FRAMEBUFFER_BINDING 0x8CA6" in stub
      and "#define GL_ACTIVE_TEXTURE 0x84E0" in stub
      and "#define GL_TEXTURE0 0x84C0" in stub
      and "#define GL_TEXTURE_BINDING_2D 0x8069" in stub)

rsyn = run(["bash", "scripts/task193_tinygl_syntax.sh"], timeout=280)
check("C7 tinygl 语法门（task193，stub 扩枚举后）",
      rsyn.returncode == 0 and "SYNTAX OK" in rsyn.stdout,
      (rsyn.stdout or rsyn.stderr)[-160:] if rsyn.returncode != 0 else "")

# ============ D. 文档 + 级联 ============
print("== D. 文档 + 级联 ==")
vh = rd("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("D1 version.h Task209 附录（改名 + 红鲱鱼 + 探针 + 尾部 SEP）",
      "Amethyst Task 209, 2026-10-01" in vh
      and "Krypton Wrapper (<=26.2)" in vh
      and "ZERO push-constant blocks" in vh
      and "DUAL naming" in vh
      and vh.rstrip().endswith("// ============================================================================"))

ann = json.loads(rd("announcements.json"))["announcements"]
a209 = ann[2] if len(ann) > 2 else {}
check("D2 公告 task209@2（31 条 + 末位 task206 不动 + 内容双主题）",
      len(ann) == 31 and a209.get("id") == "task209-krypton-rename-2026-10-01"
      and ann[-1]["id"] == "task206-nggl4es-2026-10-01"
      and "Krypton Wrapper" in a209.get("title", "")
      and "红鲱鱼" in a209.get("content", "")
      and "Initialising Krypton Wrapper" in a209.get("content", ""))

wl = rd("worklog.md")
check("D3 worklog Task 209 条目（判读 + 定谳 + 改名 + 探针 + 级联）",
      "Task ID: 209" in wl and "红鲱鱼" in wl and "Krypton Wrapper" in wl
      and "四叉" in wl)

r206 = run([sys.executable, "scripts/verify_task206.py"], timeout=600)
check("D4 verify_task206 级联 43/43（改名重锚 E4/E6/F4 后）",
      r206.returncode == 0 and "43/43" in r206.stdout and "ALL PASS" in r206.stdout,
      r206.stdout[-160:] if r206.returncode != 0 else "")

r208 = run([sys.executable, "scripts/verify_task208.py"], timeout=600)
check("D5 verify_task208 级联 24/24（A 门退役重锚后）",
      r208.returncode == 0 and "24/24" in r208.stdout and "ALL PASS" in r208.stdout,
      r208.stdout[-160:] if r208.returncode != 0 else "")

r202 = run([sys.executable, "scripts/verify_task202.py"], timeout=600)
check("D6 verify_task202 级联 57/57（公告 31 + 索引顺延重锚后）",
      r202.returncode == 0 and "57/57" in r202.stdout,
      r202.stdout[-160:] if r202.returncode != 0 else "")

r193 = run([sys.executable, "scripts/verify_task193.py"], timeout=600)
check("D7 verify_task193 级联 86 PASS / 0 FAIL",
      r193.returncode == 0 and "86 PASS / 0 FAIL" in r193.stdout,
      r193.stdout[-160:] if r193.returncode != 0 else "")

r165 = run([sys.executable, "scripts/verify_task165.py"], timeout=280)
check("D8 存量断锚修复复证（165 34/34 + 167 31/31）",
      "34/34" in r165.stdout
      and "31/31" in run([sys.executable, "scripts/verify_task167.py"], timeout=280).stdout)

r168 = run([sys.executable, "scripts/verify_task168.py"], timeout=600)
fails168 = [l for l in r168.stdout.split("\n") if l.strip().startswith("[FAIL]")]
check("D9 verify_task168 42/43（仅 E7 存量漂移：134-E4b，纯净 HEAD 同败）",
      "42/43" in r168.stdout and len(fails168) == 1 and "E7" in fails168[0] and "E4b" in fails168[0],
      str(fails168[:2]))

# ============ summary ============
fails = [n for n, ok in results if not ok]
print()
print(f"==== Task209: {len(results) - len(fails)}/{len(results)} ====")
if fails:
    print("FAILED:")
    for n in fails:
        print("  " + n)
    sys.exit(1)
print("ALL PASS")
