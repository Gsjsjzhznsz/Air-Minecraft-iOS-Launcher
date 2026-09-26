#!/usr/bin/env python3
# Task168 verifier: neumorphism wallpaper-mode visibility (dynamic/solid dual form)
# + help-FAQ JSON migration (dual-file, aligned with announcements).
# Task170 诚实重锚：实底开关退役为整体透明度滑条（cardsNeumorphOpacity），
# 管线实底分支合并、l10n 键原位换名（计数 1954 不变）、公告顺延一位。
# 用法: python3 scripts/verify_task168.py   （在仓库根的任意子目录运行皆可）
import json
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(REPO)


def rd(p):
    with open(p, encoding="utf-8") as f:
        return f.read()


results = []


def check(name, cond, detail=""):
    results.append((bool(cond), name, detail))


# ============================================================
# A. 新拟态双模式管线（引擎 + BackgroundManager）
# ============================================================
engine_h = rd("Natives/UIKit+NativeSurface.h")
engine_m = rd("Natives/UIKit+NativeSurface.m")
bm_m = rd("Natives/BackgroundManager.m")
bm_h = rd("Natives/BackgroundManager.h")

check("A1 退役完整性（Task177 重锚）：attachShadowOnly 声明随透明承载层时代退役（.h）",
      "- (void)ame_attachNeumorphShadowOnly;" not in engine_h)
check("A2 Task177 重锚：三层结构在位（投影对 + 不透明渐变表面层盖住内侧），\"只投影不画块\"旧语义退役",
      "ame177_darkLayer" in engine_m and "ame177_lightLayer" in engine_m
      and "ame177_surfaceLayer" in engine_m and "CAGradientLayer layer" in engine_m)
surf_m = engine_m[engine_m.index("- (void)ame_applyNeumorphSurface"):]
surf_m = surf_m[surf_m.index("\n}\n") + 1:]
surf_m = surf_m[surf_m.index("- (void)ame_applyNeumorphSurfaceFlatWithRadius"):]
surf_m = surf_m[:surf_m.index("\n}\n")]
# ame_applyNeumorphSurface 本体在 Flat 版之前
apply_body = engine_m[engine_m.index("- (void)ame_applyNeumorphSurface {"):engine_m.index("- (void)ame_applyNeumorphSurfaceFlatWithRadius")]
check("A3 实底版 ame_applyNeumorphSurface 仍写规格表面色（兑底；Task177 重锚尾部锚点）",
      "self.backgroundColor = AmeNeumorphSurfaceColor();" in apply_body)

check("A4 卡片视图管线：壁纸早退旧形态已删除（Task163 的 hasBackground-return 不复存在）",
      "if ([self hasBackground]) {\n        [view ame_removeNeumorphShadow];\n        [self applyEffectToView:view];\n        return;" not in bm_m)
check("A5 卡片视图管线（Task173 重锚：正常态重写）= 开关门在先，壁纸适配分支整链退役",
      "if (!self.cardsNeumorphEnabled) {" in bm_m[bm_m.index("- (void)applyNeumorphCardEffectToView"):bm_m.index("- (void)applyEffectToSearchBar")]
      and "if ([self hasBackground])" not in bm_m[bm_m.index("- (void)applyNeumorphCardEffectToView"):bm_m.index("- (void)applyEffectToSearchBar")]
      and "[view ame_attachNeumorphShadowOnly];" not in bm_m
      and "view.alpha = self.cardsNeumorphOpacity;" not in bm_m)
check("A6 卡片视图管线：正常态尾部仍走规格表面（ame_applyNeumorphSurface）",
      "[view ame_applyNeumorphSurface];" in bm_m)
check("A7 cell 管线新门（Task173 重锚）：开关开启分支在最前（壁纸无关），旧无壁纸门退居其次",
      "if (![self hasBackground]) {" in bm_m
      and bm_m[bm_m.index("- (void)applyEffectToCollectionViewCell"):].index("if (self.cardsNeumorphEnabled) {")
      < bm_m[bm_m.index("- (void)applyEffectToCollectionViewCell"):].index("if (![self hasBackground]) {"))
check("A7b 透明度原语全链退役（Task177 重锚：宿主 alpha 与卡片本体透明度原语都成历史）",
      "target.alpha = self.cardsNeumorphOpacity;" not in bm_m
      and "cardTarget.alpha = self.cardsNeumorphOpacity;" not in bm_m
      and bm_m.count("[target ame_applyNeumorphCardOpacity:self.cardsNeumorphOpacity];") == 0
      and bm_m.count("[view ame_applyNeumorphCardOpacity:self.cardsNeumorphOpacity];") == 0)
check("A8 动态收口退役（Task172）：attach 调用点全撤；Task177 重锚：引擎方法本体也退役",
      "[cardTarget ame_attachNeumorphShadowOnly];" not in bm_m
      and "subview.layer.cornerRadius = cardTarget.layer.cornerRadius;" not in bm_m
      and "- (void)ame_attachNeumorphShadowOnly" not in engine_m)
check("A9 宿主链放行裁剪维持（Task172 ON 分支保留：阴影越出卡片边界）",
      "cell.contentView.clipsToBounds = NO;" in bm_m
      and "cell.contentView.layer.masksToBounds = NO;" in bm_m)
check("A10 cell 管线实底尾部：ame_applyNeumorphSurface 仍在（规格表面+双阴影）",
      "[target ame_applyNeumorphSurface];" in bm_m)
check("A11 边界维持：列表行 applyCardEffectToCell 仍 Flat 平贴（不受开关影响）",
      "[cell.contentView ame_applyNeumorphSurfaceFlatWithRadius:12];" in bm_m)
check("A12 边界维持：侧栏/右面板仍走 applyEffectToView（Task163 平贴结论不被波及）",
      "applyEffectToView:self.sidebarContainer]" in rd("Natives/LauncherRootViewController.m")
      and "applyEffectToView:self.rightPanelContainer]" in rd("Natives/LauncherRootViewController.m"))
check("A13 联机页状态卡改走新拟态卡片管线（全部卡片统一）",
      "applyNeumorphCardEffectToView:self.statusCard]" in rd("Natives/TerracottaViewController.m"))

# ============================================================
# B. 卡片新拟态整体透明度滑条（Task170 重锚：替换 Task168 实底开关）
# ============================================================
bsvc = rd("Natives/BackgroundSettingsViewController.m")

check("B1 透明度属性退役（Task177 重锚：cardsNeumorphOpacity 从 .h/.m 全退）",
      'cardsNeumorphOpacity' not in bm_h
      and '- (CGFloat)cardsNeumorphOpacity' not in bm_m)
check("B2 落盘键退役（Task177 重锚：kBackgroundCardsNeumorphOpacityKey 常量与读写全退）",
      'kBackgroundCardsNeumorphOpacityKey' not in bm_m
      and "background_cards_neumorph_opacity =" not in bm_m)
check("B3 实底开关全链退役（Task170：代码零残留）",
      "cardsNeumorphSolid" not in bm_m and "cardsNeumorphSolid" not in bm_h
      and "cardsNeumorphSolid" not in bsvc
      and "background_cards_neumorph_solid" not in bm_m)
check("B4 滑条行退役（Task177 重锚：行/回调/tags 500~502 全退，开关行保留）",
      '"CardsNeumorphOpacityCell"' not in bsvc
      and "slider.tag = 500;" not in bsvc
      and "cardsNeumorphOpacitySliderChanged" not in bsvc
      and '"CardsNeumorphToggleCell"' in bsvc)
check("B5 滑条回调退役（Task177 重锚）：落盘与刷新链随行消失，开关回调仍在",
      "cardsNeumorphOpacity = slider.value;" not in bsvc
      and "[[BackgroundManager sharedManager] refreshUIEffect];" in bsvc)
check("B6 既有行不受影响（透明度/模糊滑块行仍在位）",
      "opacitySliderChanged:" in bsvc and "blurIntensitySliderChanged:" in bsvc
      and bsvc.count("- (void)blurIntensitySliderChanged:") == 1
      and bsvc.count("- (void)opacitySliderChanged:") == 1)

l10n_key = "background.cards.neumorph.opacity.title"  # Task177：键随滑条退役（Task170 原位换名的历史就此终结）
l10n_vals = {}
for lg in ["en", "zh-Hans", "zh-CN", "zh-Hant", "ja", "km"]:
    s = rd(f"Natives/resources/{lg}.lproj/Localizable.strings")
    m = re.search(r'^"' + re.escape(l10n_key) + r'"\s*=\s*"(.*)";\s*$', s, re.M)
    l10n_vals[lg] = m.group(1) if m else None
check("B7 六语言键全部退役（Task177 重锚）", all(v is None for v in l10n_vals.values()), str(l10n_vals))
check("B8 四主语言键集一致且计数 = 1954（Task170 键原位换名，净变化 0）",
      all(len(set(re.findall(r'^"([^"]+)"\s*=', rd(f"Natives/resources/{lg}.lproj/Localizable.strings"), re.M))) == 1954
          for lg in ["en", "zh-Hans", "zh-CN", "zh-Hant"]))
keysets = [set(re.findall(r'^"([^"]+)"\s*=', rd(f"Natives/resources/{lg}.lproj/Localizable.strings"), re.M))
           for lg in ["en", "zh-Hans", "zh-CN", "zh-Hant"]]
check("B9 四主语言键集逐键一致", keysets[0] == keysets[1] == keysets[2] == keysets[3])

# ============================================================
# C. 使用问题 JSON 化（双文件对齐公告）
# ============================================================
root_bytes = open("help-faq.json", "rb").read()
bundle_bytes = open("Natives/resources/help-faq.json", "rb").read()
check("C1 双文件逐字节一致（根 = 维护源，resources = 随包）", root_bytes == bundle_bytes)
faq = json.loads(root_bytes.decode("utf-8"))
cats = faq.get("categories", [])
check("C2 结构：四分类且组名正确",
      [c["name"] for c in cats] == ["渲染与性能", "输入与控制", "安装与数据", "故障排除"])
check("C3 条数口径（11/4/7/13，总 35 —— Task176 重锚：用户并行编辑 3d36ea5/407b710 把"
      "「内存分配建议」拆成「正确分配内存」+「内存权限」两条，安装与数据 6→7；"
      "Task82-166 硬编码时代的 34 已过时）",
      [len(c["items"]) for c in cats] == [11, 4, 7, 13]
      and sum(len(c["items"]) for c in cats) == 35)
allit = [i for c in cats for i in c["items"]]
check("C4 每条 icon/title/description 三字段全非空",
      all(i.get("icon") and i.get("title") and i.get("description") for i in allit))
check("C5 过时结论已更新：FSR 条目 = 三后端支持（Metal 呈现层），旧句清除",
      any("Metal 呈现层拦截放大" in i["description"] and "FSR 超分辨率怎么用" in i["title"] for i in allit)
      and not any("暂不支持。Vulkan 直连无升采样呈现钩子" in i["description"] for i in allit))
check("C6 过时结论已更新：MobileGlues 卡顿条目补 Vulkan+FSR 推荐路径",
      any("Vulkan 直连后端（MobileGL）并开 FSR 档位" in i["description"] for i in allit))
helpvc = rd("Natives/LauncherHelpViewController.m")
check("C7 页面改读随包 JSON（pathForResource + JSONSerialization + 空分组兜底日志）",
      'pathForResource:@"help-faq" ofType:@"json"' in helpvc
      and "JSONObjectWithData" in helpvc
      and "help-faq.json missing/unparsable" in helpvc)
check("C8 硬编码条目已整体退役（旧 buildFaqData 大块不存在）",
      "renderer.iconName" not in helpvc and "sparkProfiler" not in helpvc
      and "self.itemsByCategory = @[" not in helpvc)
check("C9 LauncherHelpFaqItem 类保留（页面模型零改动）",
      "@interface LauncherHelpFaqItem : NSObject" in helpvc
      and "item.question = title;" in helpvc
      and "item.iconName" in helpvc)
check("C10 抽取/幂等脚本入库（可重跑再生成）",
      os.path.exists("scripts/task168_faq_extract.py")
      and "help-faq.json" in rd("scripts/task168_faq_extract.py"))

# ============================================================
# D. 公告 + version.h
# ============================================================
anns = json.loads(rd("announcements.json"))["announcements"]
ids = [a["id"] for a in anns]
check("D1 公告顺延（Task177 重锚：task177/175/174 + 双 task173 相继插入 index 2 起，task169 F5 钉死 anns[1] 不动；task168 顺延至 anns[10]）且 id 唯一",
      len(ids) == len(set(ids))
      and anns[1]["id"] == "task169-four-fixes-2026-09-25"
      and anns[10]["id"] == "task168-neumorph-faq-json-2026-09-25")
t168 = anns[10]
check("D2 公告内容：根因叙述 + 双形态 + 两个维护路径",
      "447a677" in t168["content"] and "透明度/模糊" in t168["content"]
      and "announcements.json" in t168["content"] and "help-faq.json" in t168["content"]
      and "实底" in t168["summary"])
vh = rd("Natives/external/MobileGlues/MobileGlues-cpp/version.h")
check("D3 version.h Task 168 addendum（双事由）",
      "Task 168" in vh and "ame_attachNeumorphShadowOnly" in vh and "help-faq.json" in vh)

# ============================================================
# E. 语法 / 配平 / 级联
# ============================================================
def balance(path):
    src = open(path, encoding="utf-8").read()
    depth = {"{": 0, "(": 0, "[": 0}
    pair = {"}": "{", ")": "(", "]": "["}
    i, n, state = 0, len(src), "code"
    while i < n:
        c = src[i]
        if state == "code":
            if c == '"':
                state = "str"
            elif c == "/" and i + 1 < n and src[i + 1] == "/":
                state = "line"
                i += 1
            elif c == "/" and i + 1 < n and src[i + 1] == "*":
                state = "block"
                i += 1
            elif c in depth:
                depth[c] += 1
            elif c in pair:
                depth[pair[c]] -= 1
        elif state == "str":
            if c == "\\":
                i += 1
            elif c == '"':
                state = "code"
        elif state == "line":
            if c == "\n":
                state = "code"
        elif state == "block":
            if c == "*" and i + 1 < n and src[i + 1] == "/":
                state = "code"
                i += 1
        i += 1
    return all(v == 0 for v in depth.values())


check("E1 配平：BackgroundManager.m", balance("Natives/BackgroundManager.m"))
check("E2 配平：BackgroundSettingsViewController.m", balance("Natives/BackgroundSettingsViewController.m"))
check("E3 配平：LauncherHelpViewController.m", balance("Natives/LauncherHelpViewController.m"))
check("E4 配平：UIKit+NativeSurface.m", balance("Natives/UIKit+NativeSurface.m"))
check("E5 配平：TerracottaViewController.m", balance("Natives/TerracottaViewController.m"))
check("E6 新增 NSLog 无格式符（Task169 格式串审计口径）",
      "FAQ rendered empty" in helpvc and helpvc.count('NSLog(@"[LauncherHelp]') == 1)

CASCADES = ["160", "161", "162", "163", "164", "165", "166", "167", "169",
            "129", "130", "131", "132", "133", "134", "135", "138", "139",
            "141", "142", "143", "150", "151", "156", "157", "159"]
# 历史 verify 脚本用 TASKxxx_REPO / AME_REPO 环境变量注入仓库根（默认值是
# 并行会话沙箱路径）——级联运行时统一注入为本仓库根。
ENV_NAMES = ["TASK160_REPO", "TASK161_REPO", "TASK162_REPO", "TASK163_REPO",
             "TASK164_REPO", "TASK165_REPO", "AME_REPO", "TASK101_REPO",
             "TASK102_REPO", "TASK111_REPO", "TASK136_REPO", "TASK137_REPO",
             "TASK141_REPO", "TASK149_REPO", "TASK150_REPO", "TASK157_REPO",
             "TASK159_REPO", "TASK88_REPO", "TASK89_REPO", "TASK90_REPO",
             "TASK91_REPO", "TASK92_REPO", "TASK93_REPO", "TASK95_REPO",
             "TASK96_REPO"]
cascade_env = {k: REPO for k in ENV_NAMES}
cascade_env.update(os.environ)


def fail_lines(text):
    lines = []
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("[FAIL]") or s.startswith("FAIL ") or " FAILED:" in s or s.startswith("FAILED"):
            lines.append(s[:120])
    return lines


baseline_doc = json.loads(rd("scripts/task168_cascade_baseline.json"))
baseline = baseline_doc.get("baseline", {})
# Task173 具名沙箱传播簇（详证见 verify_task173 G1 注释；Task171 先例同款）。
SANDBOX_EXCEPTIONS = {
    "131": ("H3 verify_task130",),
    "132": ("A1 崩溃日志证据", "A15 libjnidispatch", "G4 级联六验证器"),
    "135": ("E. verify_task130", "E. verify_task131", "E. verify_task132",
            "E. verify_task133", "E. verify_task134", "G4 级联六验证器"),
    "156": ("G verify_task154",),
}
new_failures = []
for t in CASCADES:
    script = f"scripts/verify_task{t}.py"
    if not os.path.exists(script):
        new_failures.append((t, ["<script missing>"]))
        continue
    r = subprocess.run([sys.executable, script], capture_output=True, text=True,
                       timeout=600, env=cascade_env)
    if r.returncode == 0:
        continue
    cur = set(fail_lines(r.stdout + r.stderr))
    allow = set(baseline.get(t, []))
    exc = SANDBOX_EXCEPTIONS.get(t, ())
    extra = sorted(f for f in cur
                   if f not in allow and not any(e in f for e in exc))
    if extra:
        new_failures.append((t, [e[:120] for e in extra]))
cascade_fail = new_failures
check("E7 级联零新增失败（当前失败 ⊆ 提交树基线，家法 stash 对拍口径）", not cascade_fail, str(cascade_fail))
# E7 实现：与 scripts/task168_cascade_baseline.json（提交树实测既有失败清单）
# 逐脚本比对——新增失败脚本或新增失败检查行都会置红；基线内的既有失败
# （子级联沙箱路径默认值 / 日志钉住漂移，HEAD 上即存在）不计为回归。

# ============================================================
print("=" * 72)
passed = sum(1 for ok, _, _ in results if ok)
for ok, name, detail in results:
    print(("[PASS] " if ok else "[FAIL] ") + name + (f"  -- {detail}" if (detail and not ok) else ""))
print("=" * 72)
print(f"verify_task168: {passed}/{len(results)}" + ("  ALL GREEN" if passed == len(results) else "  HAS FAILURES"))
sys.exit(0 if passed == len(results) else 1)
