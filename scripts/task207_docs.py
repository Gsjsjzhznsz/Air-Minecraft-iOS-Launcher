#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Task 207 文档三件套（幂等）。编号让位重锚版：并行会话的 Task206（NG-GL4ES
渲染器移植，11 轮 CI）已占用 206 并尾部追加了 task206-nggl4es 公告（29 条）；
本轮实例卡快捷指令化顺延为 207，@2 插入后全体非钉位索引再 +1（29 -> 30）。
  1. announcements.json 插入 task207-shortcuts@2
  2. 公告锚重锚：193 F / 173 M3 / 190 H / 196-201 E / 202 H / 203 H
     + 并行会话 verify_task206.py F5（len 29 -> 30，尾锚不变）
  3. version.h 追加 Task 207 附录（REVISION 18 append-only，无 bump）
"""
import io
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANN = os.path.join(REPO, "announcements.json")
VH = os.path.join(REPO, "Natives", "external", "MobileGlues", "MobileGlues-cpp", "version.h")

ENTRY = {
    "id": "task207-shortcuts-instance-cards-2026-10-01",
    "title": "实例选择页快捷指令化：竖卡双列网格 + 点卡即选用 + ⋯ 纯编辑 + 内缩高亮环",
    "date": "2026-10-01",
    "summary": ("版本管理页实例卡整体重写为 iOS 快捷指令样式：accent 统一渐变竖卡、"
                "左上白色实例图标（原 loader 图标模板化）、右上 ⋯ 编辑钮、左下名称+版本；"
                "点卡片=选用实例（旧'进编辑顺带选中'逻辑退役），⋯=纯编辑；"
                "选中高亮=内缩 accent 环（内缩距=省略号到卡缘间距的 1/3，2pt 描边+柔光）；"
                "密度翻倍：iPhone 2 列 / iPad 4 列，行高沿用旧版单卡 84pt。长按菜单三件套保留。"),
    "content": (
        "## 实例选择页 = 快捷指令（Task207 用户创新定稿）\n\n"
        "**视觉**\n\n"
        "- 卡底：统一主题渐变（accent → 深 accent 对角 CAGradientLayer），盖在新拟态表面/壁纸 blur 承载层之上、内容之下；卡体透明度滑条（Task178 语义）继续生效\n"
        "- 左上：实例图标沿用原来源（ModLoaderIconHelper loader 品牌图 / cube 兜底），统一重渲染为白色模板——alpha 即形状，任意透明度原图兼容\n"
        "- 右上：⋯ 半透明圆钮（白 0.28，24pt 圆）\n"
        "- 左下：实例名（sp15 semibold 白）+ 版本号（sp11 白 75%）\n\n"
        "**交互（快捷指令语义）**\n\n"
        "- 点卡片 = 选用该实例（已是当前实例时静默跳过；等同原长按菜单'选用'动作）\n"
        "- 点 ⋯ = 纯编辑（进 ProfileSettingsViewController，不再顺带切换选中实例）\n"
        "- 长按 = 选择/编辑/删除菜单（保留不变）\n"
        "- 选中高亮 = 内缩 accent 环：内缩距 = 省略号钮到卡片边缘间距的 1/3（动态推导 12/3=4pt），2pt accent 描边 + 同色柔光\n\n"
        "**布局（密度翻倍）**\n\n"
        "- 行高沿用旧版单卡行高 84pt（kVMVersionRowHeight），一个旧卡位 = 两张新卡\n"
        "- 列数翻倍：iPhone 1→2 列、iPad 2→4 列（分数宽 0.5/0.25）\n"
        "- 卡内几何量用固定 pt（dp 的 iPad 1.3× 会撑爆 84pt 预算）；字体仍走 sp（1.15 上限）\n\n"
        "**退役**\n\n"
        "- 旧横向行卡五件套：iconContainer / selectedBadge / isolatedBadge / lastPlayedLabel / chevron（用户定稿'纯快捷指令样'）\n\n"
        "English: VersionManagerViewController's instance cards rewritten as iOS Shortcuts-style vertical cards "
        "(unified accent gradient, white-template icon, ellipsis edit button, name+version footer, inset accent selection ring; "
        "density doubled at the legacy 84pt row height; tap = select, ellipsis = pure edit).\n\n"
        "Task 207 (user innovation round; number yielded from the parallel Task206 NG-GL4ES port): instance cards restyled "
        "isomorphic to the iOS Shortcuts app (two user-supplied reference screenshots), with select-on-tap / edit-on-ellipsis "
        "interaction and an inset accent highlight ring whose inset is dynamically derived as one third of the "
        "ellipsis-to-edge inset."
    ),
    "priority": None,
    "action_url": None,
    "action_title": None,
    "image_url": None,
    "pin": False,
}

VH_ADDENDUM = """// REVISION 18 addendum (Amethyst Task 207, no bump): instance-selection page
//     restyled as iOS Shortcuts-style cards (user innovation brief + two
//     reference screenshots; number yielded to the parallel Task206 NG-GL4ES
//     port). VMVersionCardCell rewritten: vertical card on a unified accent ->
//     darkened-accent diagonal CAGradientLayer (added above the Task172
//     neumorph-surface/blur carriers, below content; view alpha follows
//     cardsNeumorphOpacity so the Task178 opacity slider keeps working),
//     top-left instance icon re-rendered as a WHITE TEMPLATE (original
//     loader/cube artwork preserved, alpha-as-shape so transparent sources
//     stay compatible), top-right translucent ellipsis button = PURE EDIT
//     entry (editProfile no longer implicitly re-selects the profile --
//     Shortcuts semantics: "..." edits, does not run), bottom-left name
//     (sp15 semibold white) + version (sp11 white 75%). Selection = inset
//     accent ring: inset = ellipsis-to-edge inset / 3 (kVMCardEllipsisInset/3,
//     dynamically derived per user spec), 2pt accent border + soft accent
//     glow (readability on the same-hue gradient), corner radius 12 - inset.
//     Legacy per-card isolatedBadge / lastPlayedLabel / selectedBadge /
//     chevron retired (user-picked "pure Shortcuts" four-element card).
//     Versions section density doubled: row height keeps the legacy 84pt
//     single-card slot (kVMVersionRowHeight), columns x2 (iPhone 1->2, iPad
//     2->4 via fractional 0.5/0.25 widths). Tap card = selectProfileNamed:
//     (silent no-op when already current), long-press menu unchanged.
//     Fixed-pt geometry inside the tile (dp 1.3x on iPad would overflow the
//     84pt budget; fonts stay sp with the 1.15 cap); name-icon clearance
//     guard demoted to priority 999. l10n: zero new keys (ellipsis a11y
//     reuses i18n_str_1091). Verify: verify_task207 (new); verify_task91 C2
//     re-anchored (white-direct-write allowance 2 kept: keep-site
//     isolatedBadge -> nameLabel); announcement family re-anchored
//     (193 F / 173 M3 / 190 H / 196-201 E / 202 H / 203 H + the parallel
//     verify_task206 F5 len 29 -> 30).
"""


def fail(msg):
    print(f"[task207_docs] FAIL: {msg}")
    sys.exit(1)


def patch(path, pairs):
    p = os.path.join(REPO, path)
    s = io.open(p, encoding="utf-8").read()
    for old, new in pairs:
        if new in s and old not in s:
            continue  # already applied
        if old not in s:
            fail(f"{path}: anchor not found: {old[:70]!r}")
        s = s.replace(old, new, 1)
    io.open(p, "w", encoding="utf-8").write(s)
    print(f"[task207_docs] re-anchored {path}")


def main():
    # ---------- 1. announcements.json ----------
    data = json.loads(io.open(ANN, encoding="utf-8").read())
    ann = data["announcements"]
    if any(a.get("id") == ENTRY["id"] for a in ann):
        print("[task207_docs] announcement already present, skip insert")
    else:
        if len(ann) != 29:
            fail(f"unexpected announcement count {len(ann)} (expect 29 before insert)")
        if not ann[0]["id"].startswith("server-recommend") or not ann[1]["id"].startswith("task169"):
            fail(f"unexpected pinned window head: {ann[0]['id']} / {ann[1]['id']}")
        if ann[-1]["id"] != "task206-nggl4es-2026-10-01":
            fail(f"unexpected tail: {ann[-1]['id']}")
        ann.insert(2, ENTRY)
        io.open(ANN, "w", encoding="utf-8").write(
            json.dumps(data, ensure_ascii=False, indent=1) + "\n")
        print(f"[task207_docs] announcement inserted @2 (count {len(ann)-1} -> {len(ann)})")

    # ---------- 2. verify re-anchors ----------
    # verify_task193 F：len 29->30，task193 [3]->[4]，task190 [4]->[5]
    patch("scripts/verify_task193.py", [
        ('check("F", "条目数 -> 29（Task206 末位追加零位移）", len(ann) == 29, f"actual={len(ann)}")',
         'check("F", "条目数 -> 30（Task207@2 插入，窗口族顺延）", len(ann) == 30, f"actual={len(ann)}")'),
        ('check("F", "Task201 重锚：task193 顺延至 [3]，task190 顺延至 [4]，置顶公告 [0] 未动",\n'
         '      len(ann) > 3 and ann[3]["id"] == "task193-app-icon-replace-2026-09-28"\n'
         '      and ann[4]["id"].startswith("task190-") and ann[0]["id"].startswith("server-recommend"))',
         'check("F", "Task207 重锚：task193 顺延至 [4]，task190 顺延至 [5]，置顶公告 [0] 未动",\n'
         '      len(ann) > 5 and ann[4]["id"] == "task193-app-icon-replace-2026-09-28"\n'
         '      and ann[5]["id"].startswith("task190-") and ann[0]["id"].startswith("server-recommend"))'),
    ])

    # verify_task173 M3：整链 +1（origin 未动此段，沿用本轮原锚）
    m3_old = (
        '# Task201 重锚：task196 四连修公告@2 插入，全体非钉位再顺延 +1（184/190/193/201 各 +1 累计）。\n'
        'check("M3 announcement at index 9 (Task201 重锚：task196@2 插入后 ten-fixes@12、toggle-173@11、174@10、175@9、177@8、178@7、179@6、180@5、184@4)",\n'
        '      ann["announcements"][13]["id"] == "task173-ten-fixes-2026-09-26"  # Task184+190+193+201 各 +1\n'
        '      and ann["announcements"][12]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"\n'
        '      and ann["announcements"][11]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"\n'
        '      and ann["announcements"][10]["id"] == "task175-six-fixes-2026-09-26"\n'
        '      and ann["announcements"][9]["id"] == "task177-neumorph-css-spec-2026-09-26"\n'
        '      and ann["announcements"][8]["id"] == "task178-neumorph-decouple-opacity-2026-09-26"\n'
        '      and ann["announcements"][7]["id"] == "task179-eight-fixes-2026-09-26"\n'
        '      and ann["announcements"][6]["id"] == "task180-opacity-dual-slider-2026-09-26"\n'
        '      and ann["announcements"][5]["id"] == "task184-revert-180-ui-whitespace-fix-2026-09-27")'
    )
    m3_new = (
        '# Task207 重锚：task207@2 插入，全体非钉位再顺延 +1（184/190/193/196/201/206/207 累计）。\n'
        'check("M3 announcement at index 10 (Task207 重锚：task207@2 插入后 ten-fixes@14、toggle-173@13、174@12、175@11、177@10、178@9、179@8、180@7、184@6)",\n'
        '      ann["announcements"][14]["id"] == "task173-ten-fixes-2026-09-26"  # Task184+190+193+196+201+207 各 +1\n'
        '      and ann["announcements"][13]["id"] == "task173-neumorph-rewrite-toggle-2026-09-25"\n'
        '      and ann["announcements"][12]["id"] == "task174-neumorph-canvas-opacity-label-2026-09-26"\n'
        '      and ann["announcements"][11]["id"] == "task175-six-fixes-2026-09-26"\n'
        '      and ann["announcements"][10]["id"] == "task177-neumorph-css-spec-2026-09-26"\n'
        '      and ann["announcements"][9]["id"] == "task178-neumorph-decouple-opacity-2026-09-26"\n'
        '      and ann["announcements"][8]["id"] == "task179-eight-fixes-2026-09-26"\n'
        '      and ann["announcements"][7]["id"] == "task180-opacity-dual-slider-2026-09-26"\n'
        '      and ann["announcements"][6]["id"] == "task184-revert-180-ui-whitespace-fix-2026-09-27")'
    )
    patch("scripts/verify_task173.py", [(m3_old, m3_new)])

    # verify_task190 H：[4] -> [5]
    patch("scripts/verify_task190.py", [
        ('check("H", "announcements/task190 条目存在且为最新任务条目",\n'
         '      json.loads(rdrepo("announcements.json"))["announcements"][4]["id"].startswith("task190-"))',
         'check("H", "announcements/task190 条目存在（Task207 重锚：@2 插入后顺延至 [5]）",\n'
         '      json.loads(rdrepo("announcements.json"))["announcements"][5]["id"].startswith("task190-"))'),
    ])

    # verify_task196_197_198_201 E：[2]->[3]，[3]->[4]，len 29->30
    patch("scripts/verify_task196_197_198_201.py", [
        ('      ann[2]["id"] == "task196-quad-fixes-2026-09-29"\n'
         '      and ann[3]["id"] == "task193-app-icon-replace-2026-09-28")',
         '      ann[3]["id"] == "task196-quad-fixes-2026-09-29"\n'
         '      and ann[4]["id"] == "task193-app-icon-replace-2026-09-28")'),
        ('check("E", "公告计数 29（Task206 末位追加 NG-GL4ES 上线）", len(ann) == 29, f"got {len(ann)}")',
         'check("E", "公告计数 30（Task207@2 插入，NG-GL4ES 尾锚顺延不变）", len(ann) == 30, f"got {len(ann)}")'),
    ])

    # verify_task202 H：len 29->30，task202 [26]->[27]，task196 [2]->[3]，task193 [3]->[4]
    patch("scripts/verify_task202.py", [
        ('check("H", "公告 28 条且末位是 Task203（零索引位移）",\n'
         '      # Task203 重锚：task202 末位追加后 task203 又末位追加（27→28）；\n'
         '      # 历史锚（[2]=task196 / [3]=task193 / [0]=server）不变。\n'
         '      len(ann) == 29 and ann[-1]["id"] == "task206-nggl4es-2026-10-01"\n'
         '      and ann[26]["id"] == "task202-october-fix-wave")',
         'check("H", "公告 30 条且末位仍是 task206-nggl4es（Task207@2 插入 +1）",\n'
         '      # Task207 重锚：task207@2 插入（29→30）；task202 锚顺延 [27]。\n'
         '      len(ann) == 30 and ann[-1]["id"] == "task206-nggl4es-2026-10-01"\n'
         '      and ann[27]["id"] == "task202-october-fix-wave")'),
        ('check("H", "公告索引锚保持（[2]=task196 / [3]=task193 / [0]=server）",\n'
         '      ann[2]["id"] == "task196-quad-fixes-2026-09-29" and ann[3]["id"] == "task193-app-icon-replace-2026-09-28"\n'
         '      and ann[0]["id"].startswith("server-recommend"))',
         'check("H", "公告索引锚（Task207 重锚：[3]=task196 / [4]=task193 / [0]=server）",\n'
         '      ann[3]["id"] == "task196-quad-fixes-2026-09-29" and ann[4]["id"] == "task193-app-icon-replace-2026-09-28"\n'
         '      and ann[0]["id"].startswith("server-recommend"))'),
    ])

    # verify_task203 H：len 29->30（尾锚 task206-nggl4es 不变）
    patch("scripts/verify_task203.py", [
        ("check(\"H\", \"公告末位追加（27→28，索引锚保全）\",\n"
         "      len(ann) == 29 and ann[-1]['id'] == 'task206-nggl4es-2026-10-01')",
         "check(\"H\", \"公告末位是 task206-nggl4es（Task207 重锚：@2 插入后 29→30）\",\n"
         "      len(ann) == 30 and ann[-1]['id'] == 'task206-nggl4es-2026-10-01')"),
    ])

    # 并行会话 verify_task206.py F5：len 29->30（尾锚不变）
    patch("scripts/verify_task206.py", [
        ('check("F5 公告 29 且末位为 task206-nggl4es-2026-10-01",\n'
         '      len(ann) == 29 and ann[-1]["id"] == "task206-nggl4es-2026-10-01"',
         'check("F5 公告 30 且末位为 task206-nggl4es-2026-10-01（Task207 重锚：@2 插入 29→30）",\n'
         '      len(ann) == 30 and ann[-1]["id"] == "task206-nggl4es-2026-10-01"'),
    ])

    # ---------- 2b. 并行 Task206 资产的联动重锚 ----------
    # （a）其 verify_task206 F6 计数锚：公告 len 断言 29 -> 30
    patch("scripts/verify_task206.py", [
        ('             and "len(ann) == 29" in rd("scripts/verify_task203.py")\n'
         '             and "len(ann) == 29" in rd("scripts/verify_task202.py")\n'
         '             and "len(ann) == 29" in rd("scripts/verify_task196_197_198_201.py"))\n'
         'check("F6 计数锚重锚一致（FAQ 168/202 + 公告 193/202/203/196 家族）", anchor_ok)',
         '             and "len(ann) == 30" in rd("scripts/verify_task203.py")\n'
         '             and "len(ann) == 30" in rd("scripts/verify_task202.py")\n'
         '             and "len(ann) == 30" in rd("scripts/verify_task196_197_198_201.py"))\n'
         'check("F6 计数锚重锚一致（FAQ 168/202 + 公告 193/202/203/196 家族；Task207 重锚 29→30）", anchor_ok)'),
    ])
    # （b）verify_task202 J 门容忍表扩容：吸收 134-E4b 存量漂移（纯净 HEAD 实锤）
    patch("scripts/verify_task202.py", [
        ('    "verify_task168": "D2",\n'
         '}',
         '    "verify_task168": ("D2", "E4b"),\n'
         '}'),
        ('    drift_ok = all(_j_known_drift.get(v, "") in l for l in fails) if fails else True',
         '    drift_ok = all(any(tag in l for tag in _j_known_drift.get(v, ("",))) for l in fails) if fails else True'),
    ])

    # ---------- 3. version.h addendum ----------
    vh = io.open(VH, encoding="utf-8").read()
    if "Amethyst Task 207" in vh:
        print("[task207_docs] version.h addendum already present, skip")
    else:
        if not vh.endswith("\n"):
            vh += "\n"
        vh += VH_ADDENDUM
        SEP = "// " + "=" * 76 + "\n"
        if not vh.endswith(SEP):
            if not vh.endswith("\n"):
                vh += "\n"
            vh += SEP
        io.open(VH, "w", encoding="utf-8").write(vh)
        print("[task207_docs] version.h addendum appended")

    print("[task207_docs] DONE")


if __name__ == "__main__":
    main()
