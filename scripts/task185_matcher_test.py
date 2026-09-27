#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task 185 匹配器行为单测：把 utils.m 的 ame185_loaderVersionMatchesGameVersion
语义忠实移植到 Python，用真实病灶形态验证（26.x 新纪元 / 21-25 旧纪元 /
legacy 1.20.1 坐标 / 愚人节快照 / 陈旧镜像数据负例）。"""


def loader_candidates(loader):
    if not loader:
        return []
    clean = loader.split("-", 1)[0]
    if not clean:
        return []
    cands = [clean]
    if "." in clean:
        head = clean.rsplit(".", 1)[0]
        if head:
            cands.append(head)
    return cands


def _all_numeric(parts):
    return all(p and p.isdigit() for p in parts)


def game_candidates(game):
    if not game:
        return []
    cands = [game]
    if game.startswith("1.") and len(game) > 2:
        stripped = game[2:]
        parts = stripped.split(".")
        if _all_numeric(parts):
            cands.append(stripped)
            if len(parts) == 1:
                cands.append(stripped + ".0")
    parts = game.split(".")
    if len(parts) == 2 and _all_numeric(parts):
        cands.append(game + ".0")
    return cands


def matches(loader, game):
    if not loader or not game:
        return False
    gcands = set(game_candidates(game))
    if not gcands:
        return False
    # 特殊形态一：NeoForge legacy 1.20.1 专用坐标
    if loader.startswith("47.") or "1.20.1" in loader:
        return ("1.20.1" in gcands) or ("20.1" in gcands)
    # 特殊形态二：愚人节快照（0.<snapshot>.x）
    if loader.startswith("0."):
        return any(c in gcands for c in loader_candidates(loader[2:]))
    # 通用形态 A：复合版本 "<mc>-<forge>"（失配不短路，落穿到形态 B——
    # NeoForge 预发布 "26.3.0.5-beta" 的连字符前缀不是完整 MC 版本）
    if "-" in loader:
        mc_portion = loader.split("-", 1)[0]
        if mc_portion in gcands:
            return True
    # 通用形态 B：NeoForge 新旧格式（21.1.5 / 26.3.7 / 26.1.2.71 / 26.3.0.5-beta）
    return any(c in gcands for c in loader_candidates(loader))


CASES = [
    # (loader, game, expected, 说明)
    ("26.3-66.0.5", "26.3", True, "Forge 26.x 复合（用户反馈病灶）"),
    ("26.1.2-71.0.1", "26.1.2", True, "Forge 26.1.2 复合"),
    ("1.20.1-47.2.0", "1.20.1", True, "Forge legacy 复合"),
    ("1.18-38.0.17", "1.18", True, "Forge 陈旧镜像条目（对 1.18 本身仍有效）"),
    ("1.18-38.0.17", "26.3", False, "陈旧 BMCL 数据不得匹配 26.3（竞速验证根基）"),
    ("26.3.7", "26.3", True, "NeoForge 26.x 三分量"),
    ("26.1.2.71", "26.1.2", True, "NeoForge 26.1.2 四分量"),
    ("26.3.0.5-beta", "26.3", True, "NeoForge beta 四分量（形态 B 落穿，回归用例）"),
    ("21.5.66-beta.31", "1.21.5", True, "NeoForge 预发布 beta 后缀（形态 B 落穿）"),
    ("21.6.9-beta", "1.21.6", True, "NeoForge 三分量 beta"),
    ("21.1.5", "1.21.1", True, "NeoForge 旧纪元（游戏版本带 1. 前缀）"),
    ("21.1.5", "1.21.5", False, "旧提取器误分组形态必须排除（21.1.5 属 1.21.1）"),
    ("20.2.88", "1.20.2", True, "NeoForge 更旧格式"),
    ("47.1.3", "1.20.1", True, "NeoForge legacy 47.x 坐标"),
    ("47.1.3", "26.3", False, "47.x 不得匹配新纪元"),
    ("1.20.1-47.1.3", "20.1", True, "legacy 复合跨纪元等价形态"),
    ("0.25w14craftmine.3", "25w14craftmine", True, "愚人节快照专用"),
    ("26.3", "26.3", True, "裸版本自匹配"),
    ("66.0.5", "26.3", False, "裸 Forge 版本不得当 MC 版本匹配"),
    ("21.0.143", "1.21", True, "NeoForge 21.0.x ↔ MC 1.21"),
    ("26.3.7", "1.26.3", True, "跨纪元等价（游戏侧带 1. 前缀的宽容形态）"),
    ("1.21.5", "1.21", True, "理论形态记录：裸 '1.x.y' 不在真实数据源；drop-last 语义=匹配"),
]


def run_all():
    ok = True
    for loader, game, expected, desc in CASES:
        got = matches(loader, game)
        mark = "ok " if got == expected else "FAIL"
        if got != expected:
            print(f"{mark}  matches({loader!r}, {game!r}) = {got}, 期望 {expected}  # {desc}")
            ok = False
    return ok


if __name__ == "__main__":
    sys_exit = 0 if run_all() else 1
    raise SystemExit(sys_exit)
