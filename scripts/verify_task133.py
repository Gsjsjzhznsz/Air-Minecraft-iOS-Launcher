#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""verify_task133.py — Task 133 五项修复验证（用户验收返工轮）。
A 悬浮弹窗回归根治（ame120 包装器指针失配）；
B 26.1.2 controlify/JNA SIGBUS 崩溃链根治（Task133 镜像扫描重绑定）；
C 第三方皮肤头像（无连字符 profileId + 本地渲染 + file:// URL + 存量自愈）；
D 三个二级页面行浮窗化（键位调整/手柄配置/运行时管理 + pickExtraAction）；
E ANGLE ES 驱动开关退役（与 GLES 后端重复，死配置）；
F/G 语法与 l10n 门（键基线 1907）；
H 级联全链。
"""
import re
import subprocess
import sys
import os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

PASS = 0
TOTAL = 0


def rd(p):
    with open(os.path.join(REPO, p), encoding="utf-8", errors="replace") as fh:
        return fh.read()


def check(name, cond, extra=""):
    global PASS, TOTAL
    TOTAL += 1
    ok = bool(cond)
    PASS += ok
    print(("  PASS  " if ok else "  FAIL  ") + name + (f"   {extra}" if extra and not ok else ""))


lpvc = rd("Natives/LauncherPreferencesViewController.m")
plpt = rd("Natives/PLPrefTableViewController.m")
sdl = rd("Natives/sdl3_hook.m")
mh = rd("Natives/main_hook.m")
tpa = rd("Natives/authenticator/ThirdPartyAuthenticator.m")
jl = rd("Natives/JavaLauncher.m")
plp = rd("Natives/PLPreferences.m")
utils_h = rd("Natives/utils.h")

print("== A. 悬浮弹窗回归根治（用户截图铁证：pick 行只剩 > 且点击无反应）==")
check("A1 ame120 包装器已删除（items 构建后不得替换 type* 块——指针失配根因）",
      "ame120_basePick" not in lpvc and lpvc.count("self.typePickField = ^") == 0)
check("A2 根因病历注释在位（Task133 事故复盘锚点）",
      "包装块【替换】self.typePickField" in lpvc and "指针比较" in lpvc)
check("A3 基类 ame132 标签映射保留（包装器的功能等价物，未命中回落）",
      "ame132_pickKeys" in plpt and "ame132_idx != NSNotFound" in plpt)
check("A4 崩溃日志三轮反馈同根因记录（Task129/131/132 误诊史）",
      "Task129" in lpvc and "Task131" in lpvc)

print("== B. 26.1.2 controlify/JNA SIGBUS 根治（Task133 镜像扫描重绑定）==")
log = rd("latestlog.txt")
check("B1 崩溃证据链在位（3bcf8c4 日志：controlify -> SDLNativesLoader -> Structure -> SIGBUS，零守卫日志）",
      "Initializing Controlify" in log and
      "[SDLNativesLoader] Attempting to load SDL3 from SDL3" in log and
      "Platform.isMac called from com.sun.jna.Structure" in log and
      re.search(r"SIGBUS \(0xa\) at pc=0x[0-9a-f]+", log) is not None and
      "[SDLHook] Task131: SDL_SetEventFilter" not in log)
check("B2 ensure 主函数定义 + 增量游标设计（dlclose 回落全量重扫）",
      "void amethyst_task133_ensure_jvm_chain(void)" in sdl and
      "t133_cursor" in sdl and "count >= t133_cursor" in sdl)
check("B3 install name 识别（jna*.tmp 解包形态——Task132 路径 strstr 永不命中的断点二）",
      "amethyst_task133_install_name" in sdl and "LC_ID_DYLIB" in sdl and
      "isJna" in sdl)
check("B4 双法改写（经典间接表 + __DATA* 值扫描）与 __auth_got 跳过",
      "S_LAZY_SYMBOL_POINTERS" in sdl and "S_NON_LAZY_SYMBOL_POINTERS" in sdl and
      "strncmp(seg->segname, \"__DATA\", 6)" in sdl and "__auth_got" in sdl)
check("B5 hooked_dlopen 触发面（libjli/libjvm/jna/.tmp/java 五路 + 非尾返路径）",
      mh.count("amethyst_task133_ensure_jvm_chain") >= 2 and
      'strstr(path, "libjli")' in mh and 'strstr(path, ".tmp")' in mh and
      "needsT133Scan" in mh)
check("B6 hooked_dlsym 入口兜底扫描（dlopen 链失守时的第二触发面）",
      "amethyst_task133_ensure_jvm_chain();" in mh.split("void* hooked_dlsym")[1][:900])
check("B7 main_hook 前向声明（CI 35512461717 教训类）",
      "void amethyst_task133_ensure_jvm_chain(void);" in mh)
check("B8 Task131 守卫本体保留（SetEventFilter/AddEventWatch no-op）",
      "ame_SDL_SetEventFilter" in sdl and "ame_SDL_AddEventWatch" in sdl)

print("== C. 第三方皮肤头像根治（LittleSkin 实测：带连字符 404 / 无连字符 200）==")
check("C1 三处 profile URL 均用无连字符 profileId",
      tpa.count('ame133_undashedProfileId(self.authData[@"profileId"])') == 3)
check("C2 本地渲染（脸 8x8 @(8,8) + 帽层 @(40,8)，最近邻 128x128，64x64/64x32/HD 兼容）",
      "ame133_renderAvatarFromSkin" in tpa and "CGImageCreateWithImageInRect" in tpa and
      "kCGInterpolationNone" in tpa and "h * 2 != w" in tpa)
check("C3 一次性签名 URL 立即下载（helm 换算仅作兜底）",
      "ame133_downloadAndCacheAvatar" in tpa and "NSURLSession sharedSession" in tpa and
      tpa.count('"/helm.png"') + tpa.count('stringByReplacingOccurrencesOfString:@".png" withString:@"/helm.png"') >= 3)
check("C4 file:// URL 落盘（skin-<accountId>.png，与 AvatarManager 自定义键空间不冲突）",
      "ame133_skinAvatarPath" in tpa and 'skin-%@.png' in tpa and
      "fileURLWithPath" in tpa)
check("C5 存量账户自愈（initWithData 覆写：非 file:// 形态后台重取 + 防抖集合）",
      "Task133: stale avatar URL" in tpa and "ame133_inflight" in tpa)
check("C6 accountId 传递链未动（上轮已证 47e84d5d 即 yiqiu4178 有效 UUID，非根因）",
      "authData[@\"accountId\"] = self.authData[@\"profileId\"]" in tpa)

print("== D. 三个二级页面行浮窗化（键位调整/手柄配置/运行时管理）==")
check("D1 设置页 typeChildPane 行清零（零主观豁免）",
      lpvc.count('@"type": self.typeChildPane') == 0)
check("D2 键位调整 -> pickField（controlmap 列表 + 编辑器经 pickExtraAction 模态）",
      '@"key": @"custom_controls"' in lpvc and "ame133_ctrlKeys" in lpvc and
      "CustomControlsViewController" in lpvc.split('@"key": @"custom_controls"')[1][:1600] and
      "setDefaultCtrl" in lpvc.split('@"key": @"custom_controls"')[1][:1600])
check("D3 手柄配置 -> pickField（gamepads 列表 + ContCfg 模态）",
      '@"key": @"default_gamepad_ctrl"' in lpvc and "ame133_padKeys" in lpvc and
      "LauncherPrefContCfgViewController" in lpvc.split('@"key": @"default_gamepad_ctrl"')[1][:1200])
check("D4 运行时管理 -> pickField（版本列表 + 1_17_newer 路由读写 + JRE 管理器模态）",
      '@"key": @"manage_runtime"' in lpvc and "ame133_rtKeys" in lpvc and
      'ame133_route[@"1_17_newer"]' in lpvc and
      "LauncherPrefManageJREViewController" in lpvc.split('@"key": @"manage_runtime"')[1][:1400])
check("D5 复合 get/set 映射（custom_controls<->default_ctrl；manage_runtime<->java_homes[0]）",
      'getPrefObject(@"control.default_ctrl")' in lpvc and
      'setPrefObject(@"control.default_ctrl", value)' in lpvc and
      'ame133_homesM[@"0"] = ame133_route' in lpvc)
check("D6 基类 pickExtraAction 支持（label/handler 键 + 收起后再呈现防竞争）",
      'ame133_extra[@"label"]' in plpt and "ame133_alert dismissViewControllerAnimated" in plpt)

print("== E. ANGLE ES 驱动开关退役（与 GLES 后端重复，iOS 死配置）==")
check("E1 设置行已删（LPVC 无 enable_angle 行）",
      '@"key": @"enable_angle"' not in lpvc)
check("E2 JavaLauncher 读取已删（enableANGLE/config 写入随行退役）",
      "enable_angle" not in jl and "enableANGLE" not in jl)
check("E3 PLPreferences 默认已删",
      '@"enable_angle"' not in plp)

print("== F. l10n（四语言维护面）==")
LANGS = ["en", "zh-Hans", "zh-CN", "zh-Hant"]


def lkeys(lang):
    ks = set()
    for line in rd(f"Natives/resources/{lang}.lproj/Localizable.strings").splitlines():
        m = re.match(r'^"([^"]+)"\s*=', line)
        if m:
            ks.add(m.group(1))
    return ks


ks = [lkeys(l) for l in LANGS]
check("F1 四语言键集一致（Task133 基线 1907 = 1906 + pickextra 3 - enable_angle 2）",
      ks[0] == ks[1] == ks[2] == ks[3] and len(ks[0]) == 1907, f"counts={[len(k) for k in ks]}")
check("F2 pickextra 三键在位（edit_layout/edit_gamepad/manage_runtime）",
      all("preference.pickextra.edit_layout" in k and
          "preference.pickextra.edit_gamepad" in k and
          "preference.pickextra.manage_runtime" in k for k in ks))
check("F3 enable_angle 死键已删",
      all("preference.title.enable_angle" not in k and
          "preference.detail.enable_angle" not in k for k in ks))
check("F4 renderer_backend detail 含 ANGLE 关系说明（GLES 后端经 ANGLE 翻译）",
      all("ANGLE" in rd(f"Natives/resources/{l}.lproj/Localizable.strings").split(
          '"preference.detail.renderer_backend"')[1][:600] for l in LANGS))

print("== G. 语法门 ==")


def raw_delta(path):
    cur = rd(path)
    head = subprocess.run(["git", "-C", REPO, "show", f"HEAD:{path}"],
                          capture_output=True, text=True).stdout
    pairs = [("{", "}"), ("(", ")"), ("[", "]")]
    return all(cur.count(a) - cur.count(b) == head.count(a) - head.count(b) for a, b in pairs)


for f in ["Natives/LauncherPreferencesViewController.m", "Natives/PLPrefTableViewController.m",
          "Natives/main_hook.m", "Natives/sdl3_hook.m",
          "Natives/authenticator/ThirdPartyAuthenticator.m", "Natives/JavaLauncher.m",
          "Natives/PLPreferences.m"]:
    check(f"G 裸括号 delta 与 HEAD 一致（{f.split('/')[-1]}）", raw_delta(f))

bad_grammar = 0
for lang in LANGS:
    in_block = False
    for ln in rd(f"Natives/resources/{lang}.lproj/Localizable.strings").splitlines():
        s = ln.strip()
        if in_block:
            if "*/" in s:
                in_block = False
            continue
        if not s or s.startswith("//") or s.startswith("/*"):
            if s.startswith("/*") and "*/" not in s[2:]:
                in_block = True
            continue
        if not re.match(r'^"((?:[^"\\]|\\.)+)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;$', s):
            bad_grammar += 1
check("G .strings 行文法（键=值; 形态 × 四语言）", bad_grammar == 0, f"bad={bad_grammar}")

print("== H. 审计与级联 ==")
audit = subprocess.run([sys.executable, "/home/z/my-project/scripts/task116_l10n_audit.py"],
                       capture_output=True, text=True)
check("H1 全量 key 审计归零", "缺失 (0)" in audit.stdout, audit.stdout[-100:])
audit2 = subprocess.run([sys.executable, "/home/z/my-project/scripts/task116c_precise_audit.py"],
                        capture_output=True, text=True)
check("H2 hasDetail 精确审计归零", "共 0 项" in audit2.stdout, audit2.stdout[-100:])

cascade = []
for v in ["verify_task112_118", "verify_task119_124", "verify_task125_128",
          "verify_task129", "verify_task130", "verify_task131", "verify_task132"]:
    r = subprocess.run([sys.executable, os.path.join(REPO, "scripts", f"{v}.py")],
                       capture_output=True, text=True)
    ok = "ALL PASS" in r.stdout
    cascade.append((v, ok, r.stdout.strip().split("\n")[-1] if r.stdout.strip() else "?"))
    if not ok:
        print(f"    {v}: FAIL")
check("H3 级联七验证器全绿（112_118/119_124/125_128/129/130/131/132）",
      all(ok for _, ok, _ in cascade))

print()
print(f"==== RESULT: {'ALL PASS' if PASS == TOTAL else 'FAILED'} ({PASS}/{TOTAL}) ====")
sys.exit(0 if PASS == TOTAL else 1)
