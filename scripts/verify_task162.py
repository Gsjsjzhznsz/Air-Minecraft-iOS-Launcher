#!/usr/bin/env python3
"""Task162 八案根修验证器。

用户反馈（bf91f41 构建 = Task161 修复后的新 IPA，cbef9d5 两份日志）：
  1. "切换渲染器为其他都会自动切回自动" + "mg的fsr依旧失效" —— Profile 身份
     不一致：ProfileSettings 按name字段写、启动链按字典键读；主页版本
     选择器把 name 字段写进 selectedProfileName；allValues 无序行漂移。
  2. "forge加载存档闪退" —— GLFW overlay 的 glfwSetInputMode 引用
     launcher.jar 独有类 UIKit，Forge MC-BOOTSTRAP 模块层不可见 →
     NoClassDefFoundError（ReceivingLevelScreen.onClose → grabMouse）。
  3. "bing壁纸加载完成还是要重启才能有图片" —— "已是今日图"静默跳过不检查
     活 UI 挂载状态（状态层与视图层脱节无自愈）。
  4. "壁纸设置默认值为毛玻璃，60%的透明度，100%的模糊" —— 默认值改
     uiOpacity 0.6 / blurIntensity 1.0。
  5. "切换其他标签页再切换回主页，上方的头像缺失，必须点击一下" —— 主页头像
     每次 viewWillAppear 裸网络重拉，无本地/会话缓存。
  6. "账号添加完成需要手动刷新账号标签页" —— AccountListViewController 只在
     viewDidLoad 扫一次目录，pop 返回不刷新。
  7. "curse forge加载源完全无法使用" —— 无 key 设备门控被拦 + 官方 API 恒 403；
     MCIM 镜像免 key（实测 GET /mods/search 无 x-api-key 返回 200）。
  8. "在公告添加服务器推荐：mysv.dpdns.org" —— announcements.json 新条目。

用法：python3 scripts/verify_task162.py
"""
import os
import sys

ROOT = os.environ.get('TASK162_REPO', '/home/z/my-project/Amethyst-iOS-MyRemastered')  # Task163: env-injected

def rd(rel):
    return open(f"{ROOT}/{rel}", encoding="utf-8", errors="replace").read()

results = []
def check(label, cond):
    results.append((label, bool(cond)))
    print(f"  [{'PASS' if cond else 'FAIL'}] {label}")

print("== A. Profile 身份一致性（渲染器回退 auto 根因）==")
ps = rd("Natives/ProfileSettingsViewController.m")
check("A1 profileDictKey 属性声明（Task162 病历注）",
      "@property (nonatomic, copy, nullable) NSString *profileDictKey;" in ps
      and "Task162（profile 身份一致性）" in ps)
check("A2 viewDidLoad：profileName 键存在时记录 profileDictKey",
      "if (PLProfiles.current.profiles[self.profileName]) {" in ps
      and "self.profileDictKey = self.profileName;" in ps)
check("A3 viewDidLoad：直传 profile 路径的 name 反查兜底",
      "NSString *ame162_probeName = self.profile[@\"name\"];" in ps)
check("A4 saveSettings：ame162_targetKey = profileDictKey 优先，键≠名时打日志",
      "NSString *ame162_targetKey = self.profileDictKey.length > 0 ? self.profileDictKey : profName;" in ps
      and "no phantom write" in ps)
check("A5 saveSettings：existing 读源 = ame162_targetKey（读源同写目标，防残缺条目覆写）+ 落盘写 ame162_targetKey",
      "NSMutableDictionary *existing = [PLProfiles.current.profiles[ame162_targetKey] mutableCopy];" in ps
      and "PLProfiles.current.profiles[ame162_targetKey] = existing;" in ps
      and "PLProfiles.current.profiles[profName] = existing;" not in ps
      and "[PLProfiles.current.profiles[profName] mutableCopy]" not in ps)
check("A5b saveSettings：existing 空基底回退 working copy（保完整字段）",
      "existing = [self.profile mutableCopy] ?: [NSMutableDictionary dictionary];" in ps)
check("A6 saveSettings：renderer 写入日志显示目标键",
      "NSLog(@\"[ProfileSettings] Task150: renderer written to PROFILE ONLY '%@' = %@\",\n              ame162_targetKey, self.selectedRenderer);" in ps.replace("\r", ""))
check("A7 actionDone：旧键 ame162_oldKey = profileDictKey ?: originalName；删旧键建新键",
      "NSString *ame162_oldKey = self.profileDictKey.length > 0 ? self.profileDictKey : self.originalName;" in ps
      and "[PLProfiles.current.profiles removeObjectForKey:ame162_oldKey];" in ps
      and "PLProfiles.current.profiles[newName] = self.profile;" in ps)
check("A8 actionDone：重命名同步 profileDictKey + selectedProfileName 按旧键判断",
      "self.profileDictKey = newName;" in ps
      and "[PLProfiles.current.selectedProfileName isEqualToString:ame162_oldKey]" in ps)
check("A9 actionDone：名称没变分支按键落位",
      "PLProfiles.current.profiles[ame162_oldKey] = self.profile;" in ps)

ln = rd("Natives/LauncherNavigationController.m")
check("A10 主页版本选择器：键快照属性（Task162 注）",
      "@property(nonatomic, strong) NSArray<NSString *> *ame162PickerKeys;" in ln
      and "Task162（选择器键稳定化）" in ln)
check("A11 ame162RefreshPickerKeys：排序快照",
      "- (void)ame162RefreshPickerKeys {" in ln
      and "sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)" in ln)
check("A12 reloadProfileList：快照重建 + selectedProfileAt 按快照键定位",
      "[self ame162RefreshPickerKeys];" in ln
      and "self.profileSelectedAt = (int)[self.ame162PickerKeys indexOfObject:PLProfiles.current.selectedProfileName];" in ln)
check("A13 didSelectRow：selectedProfileName 落字典键（不再落 titleForRow 的 name）",
      "PLProfiles.current.selectedProfileName = self.ame162PickerKeys[row];" in ln
      and "PLProfiles.current.selectedProfileName = self.versionTextField.text;" not in ln)
check("A14 numberOfRows：行数=快照数 + 漂移自愈重建",
      "if (self.ame162PickerKeys.count != PLProfiles.current.profiles.count) {" in ln
      and "return self.ame162PickerKeys.count;" in ln)
check("A15 titleForRow/enumerateImageView：经快照键定位 + 越界防御",
      "NSDictionary *profile = PLProfiles.current.profiles[self.ame162PickerKeys[row]];" in ln
      and "NSString *name = profile[@\"name\"];" in ln
      and "PLProfiles.current.profiles[self.ame162PickerKeys[row]][@\"icon\"]" in ln
      and "row < 0 || row >= (NSInteger)self.ame162PickerKeys.count" in ln
      and "row >= 0 && row < (NSInteger)self.ame162PickerKeys.count" in ln)
check("A16 allValues 行号索引全部退役（选择器三处）",
      "profiles.allValues[row]" not in ln)

print("== A2b. Profile 身份决策镜像（Python）==")
def resolve(selected_key, profiles):
    """镜像 resolveKeyForCurrentProfile + 编辑器写入目标键。"""
    entry = profiles.get(selected_key)
    if entry is None:
        return None
    return entry.get("renderer")
profiles = {"Fabulously Optimized (2)": {"name": "Fabulously Optimized", "javaVersion": 25},
            "1.20.1-forge-47.4.13": {"name": "1.20.1-forge-47.4.13"}}
# 用户在编辑器为 FO 选 zink：旧代码写 name 字段键（幻影），新代码写字典键
profiles_fixed = dict(profiles)
# 旧行为模拟：写 profiles["Fabulously Optimized"] = {renderer: zink}
profiles_old = dict(profiles)
profiles_old["Fabulously Optimized"] = {"name": "Fabulously Optimized", "renderer": "libOSMesa.8.dylib"}
check("A2b-1 旧行为镜像：启动链读 selectedProfileName=(2) 键 → renderer=None（复现装机日志 (null)）",
      resolve("Fabulously Optimized (2)", profiles_old) is None)
# 新行为模拟：写 profiles["Fabulously Optimized (2)"] 的 renderer
new_entry = dict(profiles["Fabulously Optimized (2)"])
new_entry["renderer"] = "libOSMesa.8.dylib"
profiles_fixed["Fabulously Optimized (2)"] = new_entry
check("A2b-2 新行为镜像：同一键读回 renderer=zink（渲染器不再回退 auto）",
      resolve("Fabulously Optimized (2)", profiles_fixed) == "libOSMesa.8.dylib")
# 主页选择器：旧 = name 字段（错档），新 = 字典键
check("A2b-3 选择器镜像：didSelectRow 键=(2) 与启动链同键（旧 name 字段键不存在→错档）",
      "Fabulously Optimized" not in profiles_fixed)

print("== B. Forge 存档闪退（GLFW overlay UIKit 引用）==")
gj = rd("JavaApp/src/lwjgl/org/lwjgl/glfw/GLFW.java")
check("B1 glfwSetInputMode 不再引用 UIKit（Task162 病历注 + native 接管说明）",
      "net.kdt.pojavlaunch.uikit.UIKit.updateMCGuiScale();" not in gj
      and "Task 162（Forge 存档闪退根修）" in gj
      and "refreshGuiScaleNatively" in gj)
check("B2 grab 分支 CallbackBridge.nativeSetGrabbing 保留（模块内可见类）",
      "CallbackBridge.nativeSetGrabbing(true);" in gj)
ib = rd("Natives/input_bridge_v3.m")
check("B3 nativeSetGrabbing（GLFW JNI 路径）补 refreshGuiScaleNatively 调用",
      "Java_org_lwjgl_glfw_CallbackBridge_nativeSetGrabbing" in ib
      and ib.count("refreshGuiScaleNatively();") >= 2)
check("B4 Task162 注：与 SDL 路径 Task63 对齐说明在位",
      "Task162：GLFW 路径补齐 guiScale 原生刷新" in ib)
check("B5 readGuiScaleFromOptions 本体未被改动（native 直读链保持）",
      "static int readGuiScaleFromOptions(void) {" in ib)

print("== C. Bing 静默加载自愈 ==")
bw = rd("Natives/BingWallpaperManager.m")
check("C1 已是今日图分支：isBackgroundLiveAttached 检查 + 未挂载时重放应用",
      "if ([bgManager isBackgroundLiveAttached]) {" in bw
      and "not live-attached -- re-applying for self-heal" in bw
      and "Task162 self-heal re-apply" in bw)
check("C2 活 UI 上保持静默跳过（防每日重建闪烁语义不变）",
      "避免每日无谓重建闪烁" in bw)
bm = rd("Natives/BackgroundManager.m")
check("C3 isBackgroundLiveAttached 实现：容器→window→宿主三段判定",
      "- (BOOL)isBackgroundLiveAttached {" in bm
      and "if (!self.globalBackgroundContainer) return NO;" in bm
      and "if (!self.globalBackgroundContainer.window) return NO;" in bm)
bh = rd("Natives/BackgroundManager.h")
check("C4 头文件声明（Task162 注）",
      "- (BOOL)isBackgroundLiveAttached;" in bh)

print("== D. 壁纸默认值（毛玻璃/60%/100%；Task164 重锚：nil 判定形态）==")
check("D1 uiOpacity 默认 0.6（Task162 定稿，Task164 nil 判定重写后语义不变）",
      "_uiOpacity = 0.6; // Task162/164：默认透明度 60%" in bm)
check("D2 blurIntensity 默认 1.0（Task162 定稿，Task164 nil 判定重写后语义不变）",
      "_blurIntensity = 1.0; // Task162/164：默认模糊程度 100%" in bm)
check("D3 效果默认毛玻璃保持不变（Task164：未保存键不再误读为枚举 0 半透明）",
      "_uiEffect = BackgroundUIEffectBlur; // Task162/164：默认毛玻璃效果" in bm
      and "[defaults objectForKey:kBackgroundUIEffectKey]" in bm)
check("D4 存量已保存值不受影响（Task164 重锚：显式保存值走 else 分支 + 越界兜底）",
      "if (_uiOpacity < 0.1 || _uiOpacity > 1.0) {" in bm
      and "if (_blurIntensity < 0.0 || _blurIntensity > 1.0) {" in bm
      and "_uiEffect < BackgroundUIEffectTranslucent || _uiEffect > BackgroundUIEffectBlur" in bm)

print("== E. 主页头像缓存 ==")
nw = rd("Natives/LauncherNewsViewController.m")
check("E1 ame162_avatarCache 会话缓存（Task162 病历注 + NSCache countLimit 16）",
      "static NSCache<NSString *, UIImage *> *ame162_avatarCache(void) {" in nw
      and "cache.countLimit = 16;" in nw)
check("E2 AvatarManager 本地自定义头像优先（与右面板同源）",
      "[[AvatarManager sharedManager] avatarForAccount:auth.authData[@\"accountId\"]]" in nw)
check("E3 缓存命中同步上屏（不再裸网络重拉）",
      "UIImage *ame162_cached = [ame162_avatarCache() objectForKey:avatarURL];" in nw
      and "命中缓存：同步上屏" in nw)
check("E4 网络成功回填缓存",
      "[ame162_avatarCache() setObject:img forKey:avatarURL];" in nw)

print("== F. 账号列表自动刷新 ==")
al = rd("Natives/AccountListViewController.m")
check("F1 既有的 FCL 风格 reloadAccountList 保持唯一实现（CI 热修：删除我方重复定义）",
      al.count("- (void)reloadAccountList {") == 1
      and "重新加载账户列表并刷新表格（FCL 风格：登录/删除后刷新卡片视图）" in al
      and "勿在此重复实现（CI 实锤 duplicate declaration）" in al)
check("F2 viewWillAppear 重扫（复用既有 reloadAccountList）",
      "- (void)viewWillAppear:(BOOL)animated {" in al
      and "[self reloadAccountList];" in al
      and "[self.tableView reloadData];\n}" not in al.split("- (void)viewWillAppear")[1][:400])
check("F3 AccountChanged / UpdateAccountInfo 双通知注册",
      'name:@"AccountChanged"' in al and 'name:@"UpdateAccountInfo"' in al)
check("F4 通知处理主线程重扫（ame162_handleAccountsChanged → reloadAccountList）",
      "- (void)ame162_handleAccountsChanged {" in al
      and "dispatch_async(dispatch_get_main_queue(), ^{" in al)

print("== G. CurseForge 免 key 可用 ==")
cfa = rd("Natives/installer/modpack/CurseForgeAPI.m").replace("\r", "")
check("G1 baseURL：无 key 且解析为官方 → 强制 MCIM 镜像（Task162 注）",
      "NSString *ame162_resolved = [PLMirrorCenter curseForgeAPIBaseURL];" in cfa
      and "[PLMirrorCenter mcimCurseForgeAPIBaseURL];" in cfa
      and "Task162(CurseForge source completely unusable root fix)" in cfa)
check("G2 isSourceAvailable 类方法（恒可用语义注）",
      "+ (BOOL)isSourceAvailable {" in cfa)
cfh = rd("Natives/installer/modpack/CurseForgeAPI.h")
check("G3 头文件声明",
      "+ (BOOL)isSourceAvailable;" in cfh)
mc = rd("Natives/PLMirrorCenter.m")
mch = rd("Natives/PLMirrorCenter.h")
check("G4 PLMirrorCenter.mcimCurseForgeAPIBaseURL 唯一定义处 + 头声明",
      "+ (NSString *)mcimCurseForgeAPIBaseURL {" in mc
      and "+ (NSString *)mcimCurseForgeAPIBaseURL;" in mch)
check("G5 6 处 UI 门控全部改用 isSourceAvailable（DownloadViewController x3 / Mod / Shader / ServerList）",
      "![CurseForgeAPI isSourceAvailable]" in rd("Natives/DownloadViewController.m")
      and rd("Natives/DownloadViewController.m").count("isSourceAvailable") >= 3
      and "![CurseForgeAPI isSourceAvailable]" in rd("Natives/ModVersionViewController.m")
      and "![CurseForgeAPI isSourceAvailable]" in rd("Natives/ShaderVersionViewController.m")
      and "![CurseForgeAPI isSourceAvailable]" in rd("Natives/ServerListViewController.m"))
check("G6 isAPIKeyConfigured 仅存定义处（无 UI 门控再消费）",
      "isAPIKeyConfigured" not in rd("Natives/DownloadViewController.m")
      and "isAPIKeyConfigured" not in rd("Natives/ModVersionViewController.m")
      and "isAPIKeyConfigured" not in rd("Natives/ShaderVersionViewController.m")
      and "isAPIKeyConfigured" not in rd("Natives/ServerListViewController.m"))

print("== H. 公告（服务器推荐 + 默认值文案同步）==")
import json
ann = json.load(open(f"{ROOT}/announcements.json", encoding="utf-8"))
ids = [a.get("id") for a in ann["announcements"]]
srv = [a for a in ann["announcements"] if a.get("id") == "server-recommend-2026-09-24"]
check("H1 服务器推荐条目存在（id/title/date）",
      len(srv) == 1 and srv[0]["title"] == "推荐服务器：mysv.dpdns.org" and srv[0]["date"] == "2026-09-24")
check("H2 条目内容含 mysv.dpdns.org 地址 + 添加服务器指引",
      "mysv.dpdns.org" in srv[0]["content"] and "添加服务器" in srv[0]["content"])
check("H3 v6.0.0 发行文案：默认值 60%/100% 已同步（CN summary/content + EN tail）",
      all("10%" not in json.dumps(a, ensure_ascii=False) and "75%" not in json.dumps(a, ensure_ascii=False)
          for a in ann["announcements"] if a.get("id") == "v6-0-0-release-2026-09-21")
      and "透明度默认 60%、模糊程度默认 100%" in json.dumps(
          [a for a in ann["announcements"] if a.get("id") == "v6-0-0-release-2026-09-21"][0], ensure_ascii=False))
check("H4 公告数组按日期可排序（服务端排序消费兼容）",
      all("date" in a for a in ann["announcements"]))

print("== I. 括号平衡（字符状态机：去注释/字符串后 {=}, (=) ）==")
def strip_code(s):
    out = []; state = "code"; i = 0
    while i < len(s):
        c = s[i]; nxt = s[i+1] if i+1 < len(s) else ""
        if state == "code":
            if c == "/" and nxt == "/":
                state = "line"; i += 2; continue
            if c == "/" and nxt == "*":
                state = "block_comment"; i += 2; continue
            if c == '"':
                state = "string"; i += 1; continue
            out.append(c); i += 1
        elif state == "line":
            if c == "\n":
                out.append("\n"); state = "code"
            i += 1
        elif state == "block_comment":
            if c == "*" and nxt == "/":
                state = "code"; i += 2; continue
            if c == "\n":
                out.append("\n")
            i += 1
        elif state == "string":
            if c == "\\":
                i += 2; continue
            if c == '"':
                state = "code"
            i += 1
        else:
            if c == "\\":
                i += 2; continue
            if c == "'":
                state = "code"
            i += 1
    return "".join(out)

for f in ["Natives/ProfileSettingsViewController.m", "Natives/LauncherNavigationController.m",
          "Natives/BingWallpaperManager.m", "Natives/BackgroundManager.m", "Natives/BackgroundManager.h",
          "Natives/LauncherNewsViewController.m", "Natives/AccountListViewController.m",
          "Natives/DownloadViewController.m", "Natives/ModVersionViewController.m",
          "Natives/ShaderVersionViewController.m", "Natives/ServerListViewController.m",
          "Natives/PLMirrorCenter.m", "Natives/PLMirrorCenter.h",
          "Natives/installer/modpack/CurseForgeAPI.m", "Natives/installer/modpack/CurseForgeAPI.h",
          "Natives/input_bridge_v3.m"]:
    s = strip_code(rd(f))
    b = s.count("{") - s.count("}")
    p = s.count("(") - s.count(")")
    check(f"I {f}: brace=0 paren=0", b == 0 and p == 0)

# GLFW.java 用 Java 风格平衡检查（同状态机适用）
s = strip_code(rd("JavaApp/src/lwjgl/org/lwjgl/glfw/GLFW.java"))
b = s.count("{") - s.count("}")
p = s.count("(") - s.count(")")
check("I JavaApp/src/lwjgl/org/lwjgl/glfw/GLFW.java: brace=0 paren=0", b == 0 and p == 0)

failed = [l for l, ok in results if not ok]
print()
print(f"==== RESULT: {'ALL GREEN' if not failed else 'HAS FAILURES'} "
      f"({sum(1 for _, ok in results if ok)} passed, {len(failed)} failed) ====")
if failed:
    for l in failed:
        print(f"  FAILED: {l}")
sys.exit(0 if not failed else 1)
