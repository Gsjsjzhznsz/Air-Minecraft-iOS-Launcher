# Worklog

## ⚡ READ ME FIRST —— 会话速览（只读本节> Task 141 全文已挪入 worklog-archive.md（Task 157 收尾时行数控制，`grep -n "Task 141" worklog-archive.md` 检索）。

 + 「滚动近况」即可开工；更早历史一律查 worklog-archive.md，勿通读）

> 最后更新：Task 163（2026-09-24，新拟态范围修正：侧栏/右面板阴影退役 + 主页磁贴/下载版本卡凸起 + 实例设置页箭头统一）。此前：Task 162（另一会话，八案根修：profile 身份一致性=渲染器回退根修 / Forge 存档闪退 / Bing 自愈 / 壁纸默认 60%/100% / 头像缓存 / 账号刷新 / CurseForge 免 key / 公告服务器推荐）；Task 161（六案根修）；160（新拟态回归/弹窗背景/重影修复）。
> 新会话规则：新任务记录**追加到本文件最末尾**（`## Task N` 或 `---/Task ID:` 模板均可）；收尾时同步更新下面「当前状态」表；本文件超过 ~400 行时把最旧的任务段挪进 worklog-archive.md。

### 一句话
AngelAuraAmethyst（Amethyst-iOS 重制版，fork **Gsjsjzhznsz/Air-Minecraft-iOS-Launcher**）——iOS Minecraft 启动器，已发布 **v6.0.0**：MC 26.x 全链路可玩（26.3-pre-1 + Fabric + 128 mods + MobileGlues 渲染链）。当前主线：UI 打磨、渲染器存储分层（auto/mg + mobileglues.renderer_backend）、各 MC 版本崩溃根修。

### 当前状态（收尾时更新）
| 项 | 值 |
|---|---|
| 远端 HEAD | 本会话 Task 163 提交（新拟态范围修正：Panel 阴影退役 + 主页磁贴/下载版本卡凸起 + 实例设置页箭头统一，CI 盯绿中）；此前 df96d13（Task162 八案根修）+ bf91f41（Task161 CI 绿） |
| 最新 Task 号 | **163**（多会话并行开发，开新任务前先 fetch 避让编号） |
| 待用户装机验证 | Task 163（本批三案）+ Task 162（八案）+ Task 161（六案）+ Task 160（新拟态/默认配置/弹窗背景/重影修复）+ Task 159（Java 26.0+ 预选/内存输入框/分辨率缩放实例化）+ Task 158 + 157 + 156 |
| 已知历史遗留 | v6.0.0-release-notes.md 是工作区工件不在 git（发布时从 announcements.json 重导出）；部分 verify 级联失败为沙箱环境性（会话本地脚本被清 + task132/135/149/158 路径依赖 + task140 G2/G3 日志轮换），与基线对拍判读 |

### 双会话并行协作规则（重要）
- 推送前必须 `git fetch origin && git rebase origin/main`；Task 编号冲突避让下一空号并在记录里注明
- 验证器级联：`scripts/verify_taskNNN.py`（129-142 全家）；动 l10n/公共 UI 必须重锚基线计数（当前 1924）并对拍「零新增失败」
- 沙箱会随机重置工作区/本地 ref：**仓库是唯一事实源**；工作区工件丢失按 archive 记录重建；本地落后时 `git fetch && git reset --hard origin/main`

### 关键路径与命令
- 仓库: `/home/z/my-project/Amethyst-iOS-MyRemastered`；GitHub token 在 `git remote -v` 的 URL 里（放心直接用）
- CI 轮询: `TOKEN=$(git remote get-url origin | sed -n 's\|https://[^:]*:\([^@]*\)@.*\|\1\|p')` + `/actions/runs?per_page=N` API；失败先拉 job log grep "error:"
- 产物: artifact `com.air-devs.air-ios.ipa`（另有 trollstore .tipa / dSYM）
- l10n: en/zh-CN/zh-Hans/zh-Hant 四语言键集一致，基线 1952
- 用户日志: 直接推仓库根 latestlog* 系列（勿删）；`/home/z/my-project/upload/` 为旧渠道（hs_err_pid*.log）
- 装机日志轮换映射（Task 144 时点）：latestlog.txt=Mithril(4.0) 崩溃会话 / latestlog.old.txt=MobileGL-gles(ES) 会话 / latestlog=Forge 安装会话 / latestlog.old=OSMesa(zink) 会话

### 高频方法论（细节查 archive）
- hs_err 判读：信号类型 / si_addr（ASCII 字节=UAF 或字符串当指针；地址截断=ABI 错位）/ pc 崩溃帧 / free stack 排除栈溢出；latestlog 管道会丢尾，截断点 ≠ 崩溃点
- CI 产物必须 `strings` 验证包含新日志串再交付；TEST-ONLY 补丁用 python 定点替换（禁 git checkout 回滚）；Makefile 防 tab→空格污染
- shaderc 渲染链（Task 30-47 沉淀）：main_hook.m 32MB 栈 hop → shaderc_shim.c（串行化 + SIGSEGV 恢复网 + 源快照 + #include 文本级展开）→ libshaderc_impl（源码构建 + lValueErrorCheck 二进制补丁）

### 历史检索
- Tasks 34-140 明细 → `grep -n "Task ID:" worklog-archive.md`；Task 141 起在本文件（141/154 两段已挪 archive 留指针）
- 找 commit：`git log --oneline --grep "Task N"`

---

---

## Task 142（渲染器）——已挪 worklog-archive.md
> 全文检索：`grep -n "Task ID: 142" worklog-archive.md` 或 `grep -n "Task 142" worklog-archive.md`（存储分层设计/三端 UI/l10n +3/-1/发布资产/校验矩阵）。

## Task 143（装机日志三修复）——已挪 worklog-archive.md
> 全文检索：`grep -n "Task ID: 143" worklog-archive.md` 或 `grep -n "Task 143" worklog-archive.md`（后端键注册/FSR 常量勘误/mg 与 MobileGlues 并列归因）。

---

## 附：追加区
新任务记录直接追加在本文件**最末尾**（保持上面速览表的「当前状态/最新 Task 号」同步更新）。本文件增长到 ~400 行时，把最旧的任务段剪切进 worklog-archive.md 归档。

## 会话记录（2026-09-22，worklog 瘦身重构，未占用 Task 编号）
- 动机：worklog.md 膨胀至 2327 行，每次会话入场要消化全量历史，效率低
- 动作：① 速览节置顶（状态表/双会话协作规则/关键命令/方法论/检索指引）；② Tasks 34-140 原文归档 worklog-archive.md（2257 行）；③ Task 141/142 原文保留本文件
- 配套重锚：9 个验证器的 worklog 内容检查改为兼容 worklog-archive.md（92/93/96/97/98/101/102/111/119_124，python 定点替换）
- 验证：96/98/111/119_124 本地全绿；92/93/101/102 的条目在重构前即缺失（历史丢失，非本次回归，且不在 CI 集内）

## Task 144（装机日志四 bug 根修 + 渲染器 UX 七项）/ Task 145（Sodium 全崩根修 + 4.0 门补丁 + Forge 线程化）/ Task 148（MobileGL 双后端 FSR 复活）——均已挪 worklog-archive.md
> 全文检索：`grep -n "Task ID: 144\|Task ID: 145\|Task ID: 148" worklog-archive.md`。
## Task 149（UI 六项返工）——已挪 worklog-archive.md
> 全文检索：`grep -n "Task ID: 149" worklog-archive.md`（UI 六项/重锚链）。

## Task 150（本会话，[可撤销] 删除渲染器全局控制 + Sodium 组件安装）

### 用户需求（两点疑点已经用户确认：缺省渲染器=auto；Sodium 入口=一键装双模组）
1. 启动器设置页面的渲染器选择删掉；实例页面的"跟随全局渲染器"开关删掉；有相关代码的也可删除——**每个实例强制单独选择渲染器**（初衷：促进玩家多更改渲染器以体现效果及兼容差异）。
2. 实例页面组件安装：读取 Fabric API 安装逻辑，用相同逻辑开一个 Sodium 选项（火焰图标），安装 **Podium 和 Sodium** 模组（Podium = 禁用 Sodium 的 PojavLauncher 检查，Modrinth 实锤存在、与 Task145 的 POJAV_RENDERER 导出收敛互为双保险）。

### 实施（撤销路径全部注释留档）
- **设置页（LauncherPreferencesViewController）**：video.renderer 行字典/getPreference 分支/setPreference 分支 + ame140_writeRendererGlobal 块 + shadow toast + rendererKeys/rendererList 属性全删；MobileGlues 后端行（renderer_backend）原位幸存。
- **实例页（ProfileSettingsViewController）**：advancedRows 去掉"跟随全局渲染器"；开关映射/构建器/回调三删；渲染器行永远可选（置灰态退役）；didSelect 直接弹选择器；popover 锚点 row 1→0；loadSettings 无键缺省 `@"auto"`；saveSettings 防御性写 auto（键永不再被删除）；rendererDisplayName nil→auto。
- **启动链（PLProfiles.m）**：prefDefaults 的 `renderer→video.renderer` 全局回退退役（注释留档撤销路径）+ 新增 nil 守卫（getPrefObject(nil) 会抛 NSInvalidArgumentException）——ame_effective_renderer 解析链变为【profile 键 → auto】（用户确认缺省；1.17+ 经 Task144 升级逻辑解析为 MobileGL Vulkan 直连）。
- **Sodium 组件安装（ProfileSettingsViewController）**：组件安装区新增 Sodium 行（flame.fill 火焰图标 + systemOrange，Fabric 门槛文案与 Fabric API 行同构）；`ame150_fetchModrinthPrimaryFileWithQuery:exactTitle:gameVersion:loader:completion:` ——Modrinth 搜索→**标题全等匹配**（containsString 会误命中 Sodium Extra / Podium Port）→getVersionsForModWithID→**gameVersions+loaders(fabric) 双过滤**→primaryFile；`startInstallSodiumWithGameVersion:` 注册统一下载任务（Sodium + Podium 单阶段）→两次取文件→串行下载→写实例 mods/ 目录→成功/失败 alert 与任务状态机对齐 Fabric API 流程。
- **l10n**：退役 preference.profile.renderer_follow_global_toggle / preference.warning.renderer_shadowed_by_profile；新增 component.sodium.confirm_title/confirm_message/searching/not_found/download_failed/done——四语言键集一致，**基线 1952→1928**。
- **发布资产**：announcements.json v6.0.0 渲染器 bullet/summary/英文尾段重写为"每游戏强制单选（无全局默认，缺省自动）+ Sodium+Podium 一键安装"；主页卡片 bullet 同步 Task149 语义；README/README_CN 渲染器行重写；version.h 追加 REVISION 17 addendum (Task 150, no bump)。

### 校验
- verify_task150 新增 43 项全绿（A 设置页 6 / B 实例页 9 / C 启动链 4 / D Sodium 8 / E l10n 5 / F 发布资产 6 / G 配平+UIColor 白名单 5）。
- 重锚：task142（B4/B5/B6、C1-C4/C8-C11、D1/D5、E2/E4/E5/E6 —— Task142 的开关/置灰/删键/全局行锚点全面转 Task150 形态）、task140（C2/C4/C7/C9/C10/C12、E1/E2、F1/F4/F6 + G1 日志轮换重锚）、task139（E1-E4、I2）、task137（G3 增加 Task150 l10n diff 形态分支）、l10n 计数门 ×9（129-135/138/143 → 1928）。
- 级联 stash 基线对拍（远端 HEAD 2775e2f）：**零新增失败**；顺带修复另一会话 Task147/148 日志轮换造成的 task140 G1 断链（142 F6/143 G1 级联随之自愈：140=58/58、142=49/49、143=31/31）；task139 26/36 与基线一致；129-135/138 环境性失败逐项一致；task132/135 沙箱路径环境性。
- 四改动 ObjC 文件括号配平全 0；UIColor 白名单审计通过；ObjC 改动集中 4 文件，与另一会话 Task147/148 触及面（JavaLauncher/mgl_fsr/SurfaceViewController/egl_bridge/osm_bridge）零重叠。

### Stage Summary
- 用户预期：①设置页无渲染器选择、实例页无跟随全局开关、实例渲染器行永远可选、未设置实例走 auto（装机日志锚：无键实例启动日志 RENDERER is set to libMobileGL.dylib=auto 解析路径）②实例页组件安装出现火焰图标 Sodium 行，Fabric 实例一键下载 Sodium+Podium 进 mods/（非 Fabric 实例点击提示"仅 Fabric 有效"）。
- [可撤销] 说明：git revert 单提交即可整体还原；代码内注释标注了各退役点的恢复方式（PLProfiles prefDefaults 映射行 / 实例页 pragma 区 / 设置页行字典）。
- 待用户安装新 CI 工件实机验证；推送前 fetch 对齐（双会话并行）。

---
Task ID: 151
Agent: Super Z (main agent, 另一会话)
Task: 壁纸设置新增 Bing 每日壁纸（用户指定：搜索第三方接入方案 → 默认开启 → 基础功能完全）

Work Log:
- 搜索确认接入方案：业界第三方通用 = Bing 官方无鉴权接口 HPImageArchive.aspx?format=js&idx=0&n=8&mkt=zh-CN（返回 images[]：url/urlbase/copyright/title/startdate），图片 URL 补 host 即可下载；1920x1080→UHD 替换取 4K（404 静默回退）；th 服务附加 &w= 做缩略图（不支持则原样返回大图，零失败模式）
- 新增 BingWallpaperManager.h/.m：cn.bing.com 主源 + www.bing.com 备源兜底；元数据 plist 持久化于 Application Support/BingWallpaper（避开 Caches 清理）；UHD→原图两级下载回退（>4KB 防 截断占位）；4h 节流 + 跨天检测；NSCache 缩略图 + 磁盘 _thumb.jpg；回前台自动补拉；BingWallpaperDidUpdate 通知
- 默认开启语义：bing_wallpaper_enabled 键 nil→YES（显式默认，不依赖 registerDefaults 时序）；BackgroundManager 新增 background_source 标记（user/bing，历史数据→user 保证老用户自定义壁纸不被覆盖）；用户自定义永远优先；清除背景后立即回补 Bing；彻底关掉 = 关开关
- BackgroundManager：isBingSource + setBingBackgroundImageAtPath（不重编码不复制，来源=bing，画廊勾选靠文件名前缀 startdate 匹配）；clearBackgroundInternal 删除守卫（仅 backgrounds/ 目录内文件，Bing 缓存保留离线回退）
- 设置页 section 2 = Bing（开关行 Value1+UISwitch+今日状态副标题 / 浏览壁纸库 / 立即刷新），原图片/视频与恢复/清除顺延 3/4；footer 说明；BingWallpaperDidUpdate 监听刷新状态行
- 新增 BingWallpaperGalleryViewController：近 8 天自适应 2/3/4 列网格（16:9 缩略图+日期+标题），异步缩略图（可见 indexPath 回填防复用错位），当前应用项蓝框，点按→操作面板（设为壁纸/保存到相册，message=版权+标题），下载 HUD，导航栏刷新，首进无缓存自动补同步，空态提示
- 启动链：SceneDelegate applyBackgroundToWindow 之后 fire autoRefreshAndApplyIfEnabled（全异步不阻塞）
- 基建：CMakeLists +2 源文件；Info.plist 加 NSPhotoLibraryAddUsageDescription（此前无相册权限键，保存相册功能必须）；l10n 17 个 bing.* 键 x6 语言（en/zh-CN/zh-Hans/zh-Hant 门禁基线 1928→1945）
- 门禁重锚：12 个 verify 脚本 `== 1928`→`== 1945`（含 verify_task135.py vals=={1945} 代码级硬编码）+ 消息文本同步；新 verify_task151.py 46 项 ALL GREEN
- 级联对拍：129-143/150 当前 vs HEAD~1 基线 FAIL 集合逐项 diff = **零新增失败**（现存失败均为既有环境性：112_118 括号 delta/139 H 块 Task146 撤销精简/132 135 沙箱路径）

Stage Summary:
- 产出：commit 86239549（本地 main，推送后由 CI 出包）；verify_task151 46/46 绿
- 用户验证锚点（装机后）：① 首启/未设自定义壁纸 → 启动器背景自动变为 Bing 今日图（需联网）② 壁纸设置新增「Bing 壁纸」区块，开关默认开 ③「浏览壁纸库」网格 = 近 8 天，点按可设为壁纸/保存相册，当前项蓝框 ④ 设自定义壁纸后 Bing 让位（开关行副标题仍显示今日标题）⑤ 清除背景 → Bing 立即回来 ⑥ 关开关 → Bing 背景清除且不再自动应用 ⑦ 断网启动 → 上次缓存图兜底
- 技术要点：HPImageArchive url 为相对路径需补 host；th?id 链接可直接附加 &w= 缩放；UHD 变体 = 替换 _1920x1080→_UHD；Application Support 而非 Caches 存图（防系统清理致离线首启无图）
- 未动：FSR/渲染链（另一会话 Task148 已按用户硬性要求修复双后端 FSR）；用户上传的 3 份 latestlog（09-16 时间戳）尚未逐行判读，Task148 记录称 zink FSR 已 sentinel-verified landed、花屏倒转根因已修，待装机复核
- CI 记录（3 跑 2 败 1 绿，均为本任务新增代码问题，基线无涉）：
  * run 35846197362 FAIL = ①+galleryController 未在 .h 声明（设置页只见头文件）②ame_loadMetadataFromDisk 的 raw 缺 __block；顺带根治两处 -Warc-retain-cycles（自递归 block → 实例方法递归 ame_fetchWithHosts/ame_attemptDownloadURLs）
  * run 35847353064 FAIL = 链接期 Undefined symbols PHAssetChangeRequest/PHPhotoLibrary —— PhotoLibrary 保存功能首次真正调用 Photos 框架；此前 BackgroundManager/settings 只 import 头文件不触发链接。修复 = target_link_libraries 加 "-framework Photos"
  * run 35848334214 GREEN，产物 ipa/tipa/dSYM 全可用

## Task 153（本会话，渲染器三案 + Forge 模块层根修）

### 用户反馈（7d51c28/0aac3aa/68f5706 三批装机日志，4894876/d36a24f 构建）
"vulkan花屏，es驱动后端方块不渲染，opengl4.0后端崩溃。可是4.0和es后端在5.1.0正式版发布的时候是完全正常的。而刚适配vulkan解决崩溃问题后也没有出现花屏，我怀疑是flash模型改了什么导致mg系列全部无法正常使用。还有不要恢复回把3个端放到渲染器列表的模式，保持现状就行了。还有forge的启动崩溃异常指向启动器问题。最后我说的问题在log都有。"

### 判读与根因（逐条日志实锤）
1. **Vulkan 花屏 + ES 方块不渲染（同一根因）**：最新双会话（latestlog.old.txt=Vulkan / latestlog.txt=ES，均 d36a24f）"Task148 仲裁探测 -> no redirect（err=0x500）→ 启动器预交换链 ACTIVE"且 "EASU 1180x820 -> offscreen 2360x1640 -> RCAS engaged 600+ 帧"——但 geo-probe 全程 `surface=1180x820`（viewport 同为 1180x820）。**MobileGL 渲染器把 EGL window surface 尺寸钉在 MC 窗口信念上**（Task83 FSR 联动已把窗口缩到 surface/2=1180x820 → 后缓冲只剩 1180x820），启动器链却按信念 ame_surfaceWidth（2360x1640）画 RCAS——全屏四边形按 2360x1640 视口栅格化进 1180x820 后缓冲，只有左下四分之一落图，其余区域每帧残留旧帧 = 花屏（Vulkan）/毁帧错位（ES 方块不渲染）。Task148 的"内置 FSR1 重定向"理论对当前二进制【证伪】：`strings libMobileGL.dylib` 零 fsr1Setting/FSR1 符号（配置只有 MOBILEGL_* 环境变量；MobileGlues-cpp 有 FSR1 的是另一个渲染器 libmobileglues.dylib——Task148 张冠李戴）。用户"flash 改坏了"的直觉方向正确：花屏正是 Task143 修好 shader 常量（链从 inert 变 live）+ Task148 恢复联动后，链第一次在"后缓冲=窗口信念"的真实几何下全速运转所致。
2. **4.0 (Mithril) 崩溃**：Run #356（2c66887:latestlog.txt，7b4d7df 构建）`GlDevice.<init> -> GL.createCapabilities "There is no OpenGL context current"`——LWJGL GL$1 按裸名解析 libGLESv2 命中全局 ANGLE，其 glGetString 在 Mithril 上下文返 NULL。**Task152b（4894876，FunctionProvider 钉到 libmithril.dylib 绝对路径）已修，待装机验证**（本轮无 4894876 的 Mithril 会话日志）。
3. **Forge 1.20.1 启动崩溃（4894876 最新构建仍崩）**：`java.lang.module.ResolutionException: Module minecraft contains package com.mojang.blaze3d.platform, module launcher exports package ...`。机理链：launcher.jar 含 com/mojang/** 影子类（MacosUtil/text2speech 桩，26.x 必需）+ PojavClassLoader.addURL 把游戏 jar 回写 java.class.path + BootstrapLauncher/FML 把 classpath 每个 jar 变成 GAME 层自动模块 → "launcher" 与 "minecraft" 在 com.mojang.* 上 split package。考古：上游 Android Pojav 无任何 com/mojang 影子类（Forge 因此不炸）；本 fork 09-01 引入影子后 Forge launch 从未走通过（Task146 期同点原为 native 崩溃掩蔽）。

### 修复（4 文件 + 2 验证器，零 l10n 变更）
- **mgl_fsr.mm（几何仲裁）**：目标尺寸改读渲染器自己的 `eglQuerySurface`（eglGetCurrentDisplay/CurrentSurface/QuerySurface 三入口 dlsym 自 mgHandle，绝不外溢 ANGLE——Task140 纪律）——**实测后缓冲 or 不画**（查询失败零开销跳过，绝不按信念盲画）；视口闸门同步按实测；自愈恢复窗口改用实测后缓冲（防二次溢出）。
- **mgl_fsr.mm + SurfaceViewController.m（延迟缩窗，真 FSR 几何复位）**：FSR 联动 + MobileGL 时不再启动即缩窗，先按全尺寸窗口启动（渲染器建出全尺寸后缓冲——403a459 会话实证 surface 不随窗口缩小），链在确认后缓冲全尺寸后下发缩窗（nativeSendScreenSize(渲染尺寸)）；无余量兜底 = 全尺寸直呈 + CA 缩放（零花屏）+ 输入除数归一（Task139 同款）。environ.h 新增 4 全局（armed/pending render/believed surface）。
- **JavaLauncher.m（Forge 隔离）**：版本 JSON mainClass 含 cpw.mods.bootstraplauncher 判定 Forge；启动器侧 jar（launcher/patchjna/patchsvc/gson/jsr305/arc_dns）整体转 `-Xbootclasspath/a`（boot 未命名模块不参与 split 检查；委托链仍先命中 = 影子语义保真；JVM 多值 -Xbootclasspath/a 追加语义已本地 JDK 实测），`-cp` 只留 lwjgl（游戏自身 lwjgl 已被 MCDL 跳过无冲突）。非 Forge（vanilla/Fabric）-cp 组装逐位不变；launchHeadlessJVM（安装器，需 launcher.jar 内 ForgeProcessorRunner）不动。

### 校验
- verify_task153 新增 29 项全绿（A 几何仲裁 7 / B 状态机 4 / C 武装侧 3 / D 全局 1 / E Forge 隔离 6 / F 配平 4 / G 既有锚点 4）。
- 级联基线对拍（git stash 前后）：119_124（A9 重锚 Task153 形态后 61/62 与基线一致）、130=59/60、142=48+1、143=30+1、149=35/35（TASK149_REPO）、150=43/43（TASK150_REPO）、151=ALL GREEN——**零新增失败**（112_118 E5/E6、139 B 块、140 G1/G3 为既有环境性同类，与基线逐项一致）。

### Stage Summary
- 装机验证锚点：①Vulkan/ES 会话日志必现 `[MGLFSR] Task153 deferred shrink applied: backbuffer 2360x1640 ... -> pushing MC render window 1180x820`，随后 `EASU 1180x820 -> offscreen 2360x1640`（真 FSR）；或 `Task153 geometry arbitration: backbuffer ... == window ...（no upscale headroom）-- full-res direct present`（兜底，同样零花屏）；②花屏/方块不渲染消失（两形态都不再溢出裁切）；③Forge 会话日志必现 `[JavaLauncher] Task153 Forge bootclasspath isolation ON`，且不再出现 ResolutionException、游戏进入 mod 加载完成；④4.0 后端按 Task152b 锚点验证（`Task152b` 无新日志 = pin 生效未崩）。
- 用户明确指令遵守：**未动渲染器选择 UI**（保持单 mg + 后端独立键现状，未恢复三后端列表模式）。
- 后续观察项：Vulkan 直连后端的 CopyTexSubImage2D 翻转/迟滞风险（Run #356 曾报"倒转"）——若下轮日志显示 EASU engaged 但画面上下颠倒，在链内加行序翻转（shader 常量级修复）。

---
Task ID: 156
Agent: Super Z (main agent, 本会话)
Task: 用户五连反馈根修（0d45e3f/a1488ab 四份装机日志，0a22f51=Task154 构建）：①ES 仍透明（方块不渲染）②Mithril(4.0) 游戏内 /0 崩溃 ③Forge GLFWErrorCallback android.util.ArrayMap 崩溃 ④输入法无法正常输入（iPadOS 27.0）⑤毛玻璃下两个百分比滑块无名 + FSR 设置诚实化 + 右侧边栏信息卡点击直达。渲染器 UI 保持现状（单 mg + 后端独立键，用户明令）。FSR-on-mg 定案为架构性不支持（Task154 已退休），本轮做设置项诚实化而非重试。

Work Log:
- 四日志判读（latestlog=ES / latestlog.old.txt=Vulkan / latestlog.txt=Mithril / latestlog.forge=Forge-zink）：ES/Vulkan 会话 Task154 退休标记在位、全分辨率直呈、swap 链健康（ES 671 swaps fps59 exit(0)；Vulkan 684 swaps fps60）；Mithril 会话越过 GlDevice 后崩在 DynamicUniformStorage /0；Forge ignoreList 生效后崩在 android.util.ArrayMap
- ES 考古定案：d089745（09-22 07:32，Task140 构建）ES 会话与当前会话启动器侧行为逐行一致（raw ANGLE/mg_init_gles not found/DSA 探针失败/同一 LWJGL 错误行），且 Task140 判读早已记录"方块不渲染"存在于该会话 + "若仍复现属 MobileGL 上游翻译层问题"——ES 透明自 Task131 上架起一直存在，非 da5918a 后启动器回归；Task113 vendoring 注释"the GLES variant ... misbehave upstream"为原始警告。两会话 mod 列表 diff 为零（排除 mod 变量）。二进制 strings 实锤 libMobileGL.dylib 只认 MOBILEGL_* 环境变量（config.json/MG_DIR_PATH 全部 inert，Task144 写配置对 mg 无效），且暴露 MOBILEGL_ESPRYT_MULTIDRAW_MODE 档位开关（ext|multiindirect|indirect|basevertex|drawelements|compute|auto）
- ES 修复：DirectGLES 后端强制 multidraw 保守档 drawelements（逐子绘制 glDrawElements 循环，避开静默丢绘制的 native/ext 批绘制路径——方块消失而天空/实体/UI 正常的地形批绘制特征），JavaLauncher 主导出处 + egl_bridge 兑底双站点，已有值不覆盖，非 MobileGL 渲染器 unsetenv 清残留；Vulkan(Magma) 独立开关不触碰
- Mithril /0 根因（反编译 /tmp/mc262_client.jar，CFR）：GlHeuristics.java:75 new DeviceLimits(..., GL33C.glGetInteger(35380))——35380=GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT，Mithril 包装层返 0 → DynamicUniformStorage.<init> 的 Mth.roundToward(uboSize, 0) → positiveCeilDiv 除零。修复：新增 Natives/mithril_gl_shim.c → libmithril_glshim.dylib（Makefile dep_mithril_glshim，dep_openal_shim 同款 -reexport_library 模式）：re-export libmithril 全部符号 + 本地 glGetIntegerv/glGetInteger64v（本地定义优先于 re-export）对 0 值 limit 枚举补下限（3379→1024/34852→8/35361→16384/35380→256 + 64 位路径）+ eglGetProcAddress 漏斗保证两种 GL$1 Delegate 状态（Task154 补丁在/不在）下解析语义一致；JavaLauncher Mithril libname 优先指向 shim（存在性守卫 + Task146 绝对路径 + 裸名三层回退）。不触碰 libmithril.dylib 二进制，不回退 Task154 jar 补丁
- Forge ArrayMap 根因：GLFWErrorCallback$1.<init> → APIUtil.apiClassTokens → getDeclaredFields(GLFW.class) 解析字段类型 android/util/ArrayMap（lwjgl overlay 的 Pojav Android 血统 GLFW.java:511 ArrayMap<Long, GLFWWindowProperties>）→ MC-BOOTSTRAP ModuleClassLoader 父链为 boot layer（非 AppClassLoader），-cp 上 launcher.jar 里的既有 android.util 桩对模块层不可见（只有 Tools.java 经 app loader 用到它）。修复：5 个 android/util 桩源复制进 JavaApp/src/lwjgl/android/util/（overlay 编译进 lwjgl-333/341 双 jar，自动模块全包导出 → 模块层可见；launcher.jar 侧保留原件，双层各自解析互不冲突）
- IME（iPadOS 27.0, 24A437）双路径加固：①TrackedTextField（启动器虚拟键盘）：字符送达链全建筑在 UIKit 私有 API（insertFilteredText:/replaceRangeWithTextWithoutClosingTyping:/setAttributedMarkedText:），iOS 26+ UIAsyncTextInput 管线下部分提交不再走私有入口 → 新增公有 UIKeyInput insertText: 兜底（80ms 同文本去重防双发，三处私有路径送达后登记）；setAttributedMarkedText 补 markedTextRange nil 守卫 + 长度钳制（NSNotFound → 百万级退格风暴）。②TouchController 文本框：子类化 Ame156TCIMEAwareTextField（组字更新补发 EditingChanged）+ sendTextInputStatus 上报真实 markedTextRange 组字边界（原硬编码 0/0，mod 把拼音字母当已提交文本）
- UI 三案：①毛玻璃滑块命名——sections[0] 里本就有 i18n_str_1296"透明度"/1297"模糊程度"但原代码 textLabel.text=nil 从未显示；两行加 95pt 标题标签（tag 202/302，滑块右移），图标分化 circle.lefthalf.filled/drop.halffull，section 0 新页脚 background.effect.footer 语义说明（l10n 基线 1945→1946，13 个 verify 脚本门禁同步 bump）②FSR 设置诚实化——preference.detail.fsr1_setting 六语言重写：明示仅 MobileGlues/Zink 生效，mg 家族（Vulkan/ES/4.0）/MoltenVK/gl4es 不支持启动器侧 FSR，指向视频设置"分辨率"③右侧边栏 7 张信息卡可点击直达——关联对象路由 + 父链宿主定位（LauncherRoot/LauncherCardLayout 双布局适配），LauncherPreferencesViewController 新增 ameDeepLinkKey 深链（viewDidAppear 滚动到 prefContents 匹配行 + 0.45s 高亮闪烁），映射：启动器版本→设置·检查更新 / 游戏版本→版本管理 / JIT→设置·JIT 开启工具 / 内存两卡→设置·内存分配 / 设备/系统→设置首页
- 过程事故与修复：Edit 工具对 tab 缩进的 Makefile 做了全文件空格化（recipe 行必须 tab，会弄坏构建）——git checkout 恢复后改用 scripts/task156_patch_makefile.py（tab 保真 + 幂等）重新打补丁；ObjC 文件均为空格缩进不受影响（git diff 确认只有目标 hunk）
- 验证：verify_task156 新建 52/52（A Espryt 6 / B Mithril 8 / C Forge 4 / D IME 6 / E UI 9 / F l10n+配平+档案 17 / G 级联 2+2）；级联对拍 verify_task153=29/29 ALL GREEN、task151=46/46 ALL GREEN、task150=43/43（TASK150_REPO）、task154=36P/3F 与 git stash 基线逐项一致（E1/E3/E5 为用户日志轮换后的既有环境项）、task142=48/49 与基线一致；7 个改动 ObjC 文件括号配平全 0；Java 桩双源排布经模式规则（逐文件 javac + sourcepath 首命中）推演无 duplicate-class 风险
- 协同纪律：另一会话 Task155（BackgroundManager/BingWallpaperManager 壁纸切换刷新修复）在工区未提交——本轮 git add 显式排除这两个文件，零接触零冲突

Stage Summary:
- 产出：Task156 九文件修复（JavaLauncher.m / egl_bridge.m / mithril_gl_shim.c(新) / Makefile / TrackedTextField.m / SurfaceViewController.m / BackgroundSettingsViewController.m / LauncherPreferencesViewController.h+.m / LauncherRightPanelViewController.m）+ android 桩复制进 lwjgl overlay + l10n 六语言（FSR 重写 + footer 新键）+ 13 个门禁 bump + disasm_gl1.py（GL$1 Delegate 常量池反汇编器）+ task156 两脚本 + verify_task156（52 项）+ version.h addendum
- 装机验证锚点：①ES 会话 "[JavaLauncher] Task156: Espryt multidraw tier forced to 'drawelements'" + 方块渲染恢复（若仍透明，下一轮试 basevertex/ext 档位二分定位）；②Mithril 会话越过 DynamicUniformStorage（无 / by zero）"[JavaLauncher] Task156: Mithril libname -> GL shim ..."；③Forge 会话越过 DisplayWindow.initWindow（无 android.util.ArrayMap）进 mod 加载；④输入法：游戏内拼音组字/候选上屏正常送达（TrackedTextField 路径）+ TouchController 模式下组字边界正确；⑤毛玻璃下两行显示"透明度/模糊程度"标题 + 页脚说明；⑥右侧边栏 7 卡点击直达设置/版本管理
- 关键决策：ES 透明按上游翻译层缺陷处置（保守档绕行而非修 dylib）；Mithril 走 re-export 垫片（不回退 Task154 jar 补丁、不改 libmithril.dylib）；FSR-on-mg 不再重试（8 轮失败后的架构性定案，设置项诚实化收口）；Bing 切换刷新归另一会话 Task155（未提交，不抢跑）

---
Task ID: 156 (续)
Agent: Super Z (main agent, 本会话)
Task: CI 确认

Work Log:
- CI run 35897091776（8b6ec05）completed success（约 8 分钟）——dep_mithril_glshim 新 dylib 编译通过（re-export libmithril + 本地 glGetIntegerv 覆盖）、JavaApp 双源排布（src/launcher + src/lwjgl 的 android/util 桩）无 duplicate-class、全部 ObjC 改动编译通过
- 新 IPA 工件就绪，装机验证锚点见 Task156 主条目

Stage Summary:
- Task156 全链闭环：四案根修（ES multidraw 保守档 / Mithril GL shim / Forge android 模块层桩 / iPadOS 27 IME 双路径）+ 三案 UI（滑块命名 / FSR 诚实化 / 侧边栏深链）+ 验证器 52/52 + 级联零新增失败 + CI 绿
- 下一轮装机反馈关注：①ES 方块是否恢复（若仍透明 → 二分试 basevertex/ext 档）②Mithril 是否越过 /0（若新崩点 → 附日志）③Forge 是否进 mod 加载④拼音组字/候选上屏⑤毛玻璃两行标题⑥侧边栏卡片点击

## Task 157（本会话，内存分配卡片弹窗 + Sodium + Iris Shaders；原编号 154 被并行会话占用，按协作规则重编号）

### 用户需求（Task 149/150 实装后的两项返工）
1. 实例设置 > 内存分配：行右侧去除"最大可分配内存"、加与 Java 版本同款右箭头；弹窗高度/顶部抓手条不对 → 改居中卡片（类放大 alert，右上角✕ = 实例页同款关闭语义），原生观感出入场动画；"当前内存：xMB"简介升为标题字号、"内存分配"弹窗标题删除；拉条下保持间距加"自动分配内存"开关，开启后拉条变灰、右侧显示"自动分配内存"；用原启动器自动分配逻辑。
2. 组件安装 Sodium → Sodium + Iris Shaders：功能同步改；"仅 Fabric 有效"弹窗改为 Fabric API 同文案结构（换模组名）；组件安装区灰字加一行"Sodium + Iris Shaders：优化模组 + 光影加载器 (附带安装Podium)"。

### 用户问答定稿（AskUserQuestion）
弹窗形态=居中卡片；保存时机=即改即存（✕/点外部仅关闭）；自动挡拉条=显示自动比例实值（置灰）；新实例默认态=默认手动（仅显式拨过开关才为自动）；安装内容=三个 jar（Sodium+Iris+Podium）；统一下载任务显示名=Sodium + Iris Shaders + Podium。

### 实施（ProfileSettingsViewController.m 单文件主战场 + l10n x4 + announcements.json）
- **内存行（A）**：detailTextLabel 改 `memoryAutoEnabled ? memory.auto_row : "%ld MB"`（去 "/ 最大值"）；accessoryType 改 DisclosureIndicator（Java 版本同款）。
- **Ame157MemoryAllocatorCard（B）**：Task149 的 Ame149MemoryAllocatorController sheet 整体退役（mediumDetent/grabber/formSheet 回退清零）。居中卡片 340pt（≤ 屏宽-48）圆角 18 + 窗口式投影（masksToBounds NO，手绘不走 ame_applyCardSurfaceWithRadius——该助手裁剪会吃掉阴影）；右上角 xmark.circle.fill ✕ + 点外部 UIControl 关闭；"当前内存：xMB"（memory.current）升为 17pt semibold 标题、i18n_str_2037 弹窗标题退役（仅保留表格行名映射）；拉条 512→MAX(1024,maxMemory) 不变；下方 16pt 间距新增 memory.auto_row 标签 + UISwitch。自动挡：`enabled=NO` 置灰 + 显示 `MAX(512, ameAutoMemory)` 实值 + 标题切"自动分配内存"；关自动还原最近手动值。Ame157CardTransitionAnimator 自绘转场：入场 spring 缩放 1.14→1 + 遮罩淡入 0.38s，出场 1.08 缩放淡出 0.26s（UIModalPresentationCustom + 自持 transitioningDelegate）。
- **即改即存（C）**：ame157SliderReleased（TouchUpInside|UpOutside）与 ame157AutoSwitchChanged 当下回调 ameOnChange → 父层 `memoryAutoEnabled = autoEnabled; allocatedMemory = autoEnabled ? 0 : memoryMB;` → saveSettings → reloadAllTableViews；拖动中 ValueChanged 仅刷标题不落盘。
- **持久化**：profile 新键 `memoryAuto`（仅显式拨过为 YES——"默认手动"）；saveSettings 分支：自动 = `allocatedMemory=0 + memoryAuto@YES`，手动 = 数值 + 清键。`allocatedMemory=0` 恰为启动链 ame141_currentLaunchAllocMem 既有自动语义（0.5/0.25 比例）→ **JavaLauncher/SurfaceViewController/utils 零改动**，Jetsam 链自动一致。自动实值计算与 utils.m 同口径（getEntitlementValue memorystatus ? 0.5 : 0.25 × 物理 MB）。
- **Sodium + Iris Shaders（D）**：行名/映射/isEqual 判断 ×2 升级；火焰图标保留；门槛弹窗改 i18n_str_899 + 新键 component.sodium.fabric_only（Fabric API i18n_str_900 同构换名）；一键装三 jar：ame150 助手沿用，链 = sodium → iris shaders → iris 回退（防官方改名）→ podium，ame157_downloadAll 三下载串行（dlError1/2/3）+ 三文件落盘（ok1/2/3 级联守卫），done 提示三文件并列，失败码扩至 11/12；任务 displayName=Sodium + Iris Shaders + Podium、resourceName=sodium-iris-podium-<版本>。
- **l10n（E）**：+2 键（memory.auto_row / component.sodium.fabric_only）×4 门语言（ja/km 沿 Task150 口径不涉）；i18n_str_882 footer 加用户原文行；sodium 六键文案改写含 Iris（confirm_title/confirm_message/searching/not_found/download_failed/done）。基线 1946→1948。
- **发布资产（F）**：announcements.json 四处同步（summary/content bullet/EN 尾段/内存分配口径改"居中卡片弹窗（右上角✕关闭，新增自动分配内存开关）"）。

### 校验
- verify_task157 新增 44 项全绿（A 内存行 3 / B 卡片弹窗 10 / C 持久化与启动链 6 / D Sodium+Iris 9 / E l10n 7 / F 发布资产 4 / G 配平+白名单 2 / H 回归锚点 3）。
- 门禁重锚：l10n 计数门 1946→1948 共 14 处（129-135/138/139/142/143/150/151 + 并行新增的 verify_task156 F1，描述算式同步改真）；verify_task149 E 块重锚 Task157 卡片形态（35/35）；verify_task150 D1/D7/D8/F4 重锚三 jar + 行名（43/43）；verify_task141 C2/C3/C5/D5/D5b 重锚即改即存+自绘转场（36/36）。
- 级联对拍：129=44/47（基线 44/47；A9 为并行 Task156 改 Makefile payload 行的显见重锚，本任务顺手修复并注明）、130=59/60、131=34/37、132=IndexError、133=41/44、134=64/68、138=49/51、139=26/36、142=1、143=1——**与基线逐项一致**；151/135/153/154(并行)/156-G 块的失败均为 MyRemastered 沙箱环境性（156 的 G 块子进程 36P/3F 基线口径不变，其 l10n 计数门已随本任务提升 1948）。**零新增失败**。

### Stage Summary
- 产出：本地 main 提交（推送后 CI 出包）；verify_task157 44/44 绿。
- 用户验证锚点（装机后）：①内存行右侧只有 "xxxx MB" 且带右箭头；②点开 = 居中卡片（右上角✕、大字当前内存、拉条、"自动分配内存"开关），缩放+淡入出入场，无抓手条；③拨开开关 → 拉条变灰显示自动实值、行右侧变"自动分配内存"、✕ 关闭即生效（启动日志 `[Task141] launch memory from auto ratio: xxxx MB`）；④关开关 → 还原手动值；⑤组件区行名"Sodium + Iris Shaders"，非 Fabric 实例点按弹 Fabric API 同构长文案；⑥Fabric 实例一键装 3 jar（下载任务名 Sodium + Iris Shaders + Podium），装完 mods/ 含 sodium/iris/podium 三个文件；⑦组件区灰字含"Sodium + Iris Shaders：优化模组 + 光影加载器 (附带安装Podium)"。
- 技术要点：allocatedMemory=0 与 memoryAuto=YES 双写保证启动链无需感知新键；旧实例（无标记）显示与启动行为错位为用户定稿接受项（显示手动缺省值、实际按自动比例启动——与 Task141 以来行为一致）；本任务开工时远端被并行会话推进至 156（含另一 verify_task154.py），全部 ame154/Task154 前缀与验证器名重编号为 157 后 rebase（零冲突自动合并），l10n 键数 1946+2=1948。

---

## Task 158（本会话，渲染器 + Forge）

### 用户需求（原话要点）
1. "把fsr取消掉干嘛"——Task154 把 MobileGL FSR 链退休后，mg 家族三后端全部无 FSR，用户不满。
2. "我上传了旧版本的log，有4.0有es，是完全正常使用且有fsr"——a0ac656 上传 latestlog.4.0 / latestlog.es 作为 5.1.0 可玩性基准。
3. "现在的es方块穿透，4.0崩溃，vulkan没有fsr"。

### 判读（用户日志实证，全链闭环）
- **5.1.0 基准（9e6fc27）**：latestlog.4.0 与 latestlog.es 两会话的渲染器都是 **libmobileglues.dylib（MobileGlues）**——前者 customGLVersion=40（GL 4.0），后者 enableANGLE=3 + customGLVersion=32（ANGLE ES）；均 fsr1Setting=4、MC 26.2 + fabric + 110 mods 全程可玩（swapOK=1920/1034，exit(0) 正常退出）。**5.1.0 用户的"4.0/ES 后端"从来不是 Mithril/MobileGL-Espryt 二进制**——Task131 重构把这两个档位静默换到了上游二进制上。
- **4.0 崩溃（10cee5d，libmithril）**：Mithril 把 MC 26.2 pipeline 着色器转 MSL 时 `Sampler0Smplr` 未声明（未用采样器被剥离但引用残留）→ MoltenVK pipeline 编译失败 → vkCreateGraphicsPipelines 重试路径 commit_frame SIGSEGV。上游二进制缺陷，启动器不可修。
- **ES 方块不渲染（libMobileGL DirectGLES/Espryt）**：Task140/153/154 清完启动器侧全部嫌疑 + Task156 强制 drawelements 档实测仍不渲染——上游翻译层缺陷，启动器不可修。
- **Forge 闪退（10cee5d）**：NoClassDefFoundError: com/mojang/text2speech/Narrator @ GameNarrator.<init>。源码级机制闭环（BootstrapLauncher 1.1.2 + securejarhandler 2.1.10 全文判读，scripts/task158_bl/ 存档）：ModuleClassLoader 父链=boot/platform 层，系统类加载器对模块层不可见；Task154 起 launcher.jar 进 ignoreList（split-package 根治）的代价=模块层失去 com.mojang 桩；Java 侧 preProcessLibraries 又恒 _skip text2speech → 模块层无人提供该类。

### 修复
1. **mg 后端重映射（LauncherPreferences.m ame_effective_renderer mg 分支）**：GLES / OpenGL 4.0 两档解析为 libmobileglues.dylib（dylib 存在守卫，缺失落回 Task142 守卫链）。Vulkan 直连（默认）保持 libMobileGL.dylib（da5918a 语义 + Task154 退休链零回退）。
2. **5.1.0 配置强制（JavaLauncher.init_loadMobileGluesConfig + ame158_mg_mobileglues_mode）**：mg+GLES → enableANGLE=3(ForceEnable)+customGLVersion=32；mg+4.0 → enableANGLE=0+customGLVersion=40；mode 0（独立 MobileGlues/mg+Vulkan）透传用户分区偏好。AME83 FSR 能力表对 libmobileglues 恒 YES → **fsr1_setting 档位联动原样复活**（窗口=surface/档位 + MobileGlues FSR1 渲染器侧升采样 + 触控同口径 = 5.1.0 逐位同款）。
3. **Forge 模块层桩（JavaApp/Makefile 新规则）**：构建 mojang-stubs.jar（仅 com/mojang/text2speech 桩类，与 launcher.jar 同源同字节，getNarrator() 恒 NarratorDummy）随包进 app/libs → 恒在 -cp → 恒在 java.class.path → BootstrapLauncher 自动模块化进 MC-BOOTSTRAP 层 → GameNarrator 可加载（真实 text2speech 库保持 _skip，防与桩 split-package）。
4. **启动前缺库闸门（JavaLauncher ame158_repairMissingLibraries，非阻断）**：遍历合并版 JSON libraries 核对磁盘存在性，缺者同步下载（官方→BMCLAPI 双源），失败仅日志点名——BootstrapLauncher 对不存在路径静默 continue 的"缺库=模块层黑洞"从此可自愈可诊断。
5. l10n 四语言值级更新（FSR 详情/renderer_backend 详情/mithril 标签去"实验性"，零键增删）+ FAQ 标签页同步 + version.h addendum。

### 验证
- verify_task158 **35/35 ALL GREEN**（A 日志取证 5 + B 重映射锚点 7 + C Forge 桩/闸门 6 + C7 桩本地 ECJ 编译+jar 组装+类清单 3 + D l10n 键集不变+新文案 9 + E version.h + F 语法配平/Makefile tab + G 级联）。
- 级联基线对拍（task158_baseline_compare.sh，HEAD worktree 对拍）：129-143/150-154/156-158 全部 BASELINE-IDENTICAL 或预期改善；task156 E5/G 重锚（FSR 详情新语义 + task154 基线 36P/3F→35P/4F 随用户日志轮换漂移）；task133 E2 重锚（enableANGLE 偏好读取仍删，Task158 后端模式写入合法）；task137 G3/G4 重锚（l10n 值级行 + JavaApp//Makefile 文件集）；task138 C1 为日志轮换环境项（基线同败）。
- ECJ 编译门（task94）三段全过；Makefile tab 卫生检查（Edit 工具 tab→空格事故被 python 定点替换规避，worklog 教训复发拦截）。

### Stage Summary
- 装机验证锚点：mg+GLES/4.0 后端 → 日志 `RENDERER is set to libmobileglues.dylib` + `[JavaLauncher] Task158: mg GLES backend -> MobileGlues (enableANGLE=3 ...)` / `mg OpenGL 4.0 backend -> ...` + FSR 联动行 `[SurfaceVC] Task83 FSR linkage: renderer=libmobileglues.dylib preset=N scale=...`；画面=方块正常渲染 + FSR 档位生效。
- Forge 1.20.1 → 过 GameNarrator（无 Narrator CNFE）+ `[JavaLauncher] Task158: library gate ...` 行；mojang-stubs.jar 在 IPA 的 libs/ 内。
- Vulkan 直连=MobileGL 仍无 FSR（伪 EGL 无升采样钩子，结构性限制）——FSR 行详情/FAQ 已诚实指向 GLES/4.0 后端或「分辨率」缩放。
- 遗留：Mithril/MobileGL-Espryt 两个上游二进制的原生缺陷仍在（已被重映射绕开，不再是用户路径）；设备侧 text2speech-1.17.9.jar 若曾缺失由闸门自动补下。

---

## Task 158（续：CI 闭环）

- 首推 cd13424 CI run 35940449744 failure：JavaApp/Makefile:138 mojang-stubs.jar 规则——BSD cp -R 把源目录末级组件拷进目标，`cp -R build/launcher/com/mojang/text2speech build/mojang-stubs/` 产出 `mojang-stubs/text2speech`（缺 com/ 层级）→ `jar -cf ../mojang-stubs.jar com` 报 "com: no such file or directory"。
- 热修 afea13b：先 `mkdir -p mojang-stubs/com/mojang` 再 cp 进该父目录（本地 replica 测试通过）；CI run 35941955757 **completed success**。
- IPA 产物三重验证（rule: strings 验证后才交付）：①libs/mojang-stubs.jar 在包内且 jar 根为 com/（Narrator+嵌套类+全平台桩+OperatingSystem 全清单）；②Frameworks/libmobileglues.dylib 在包（5.7MB，重映射目标）；③主二进制含全部 8 条 Task158 日志串（mg GLES/4.0 backend 行 ×2 + 缺库闸门行 ×6）。
- Stage Summary：Task158 全链闭环（verify 35/35 + 级联基线对拍 + CI 绿 + 产物验证）；新 IPA 就绪，装机锚点见 Task158 主条目。

---

## Task 159（本会话，管理 Java 26.0+ 预选 + 内存输入框弹窗 + 分辨率缩放实例化）

### 用户三需求
1. 管理 Java：1.17+ 预选下加"26.0 及更高版本：Java 25"行 + 适配检测代码。
2. 实例内存弹窗改与游戏目录同款输入框（标题"调整内存分配"、简介"设备最大内存/可分配最大内存/内存调配指南见启动器使用教程"、删"恢复默认"、数值 clamp 512~可分配最大内存）。
3. 分辨率缩放从设置页迁到每实例"渲染器"行下（删 % 后缀 → 右侧独立 % 标签，像名称行点击编辑 25~100），做单独选项而非全局。

### Work Log
- 前置：fetch 对齐 ce0783d（Task158 已被并行会话完成），下一个空号 159；l10n 基线 1948
- **A. Manage JRE 26.0+ 预选**：javaRuntimes[@DEFAULT_JRE] 与 selectedRTTags 在 1_17_newer 与 execute_jar 之间插入 `1_26_newer`（新键 preference.manage_runtime.default.126）；PLPreferences java_homes 默认 "0" 加 `1_26_newer: 25`（25=internal 捆绑已存在）；footer 加 `case 25 → footer.java25`（"这是 Minecraft 26.0 及更高版本的默认版本"）；预选行 detail 加 nil 守卫（getObject 无深合并，存量设备新 tag 无键 → 显示"自动"，getSelectedJavaHome 的 minVersion 搜索语义兜底，首次点选落值）
- **B. 26.x 检测代码**：JavaLauncher launchJVM defaultJRETag 三档分界（minVersion>=25 → 1_26_newer；26.x 官方 javaVersion.majorVersion=25，原二档会让 26.x 落 1_17_newer 槽选 Java 17 启动即崩）+ execute_jar 路径（2616 区）三档；ModpackUtils.javaMajorVersionForMC 补 first>=26→25（"26.2" parts[1]=2 漏到 Java 8——对齐 ModpackImportService 的 Task70 口径）；ForgeProcessorExecutor.inferJavaMajorForMinecraft 补 parts[0]>=26→25（原 fallback 17 漏网）；NeoForgeDirectInstaller loader 反推 major>=26→25（原"未来版本→21"过时）；ModpackImportService/ForgeDirectInstaller 已有 Task70 分支（B7 锚点验证幸存）
- **C. 内存输入框弹窗**：Ame157MemoryAllocatorCard + Ame157CardTransitionAnimator 整类删除（脚本删行 95-334 + 锚点断言 + 残留清零）；showMemoryAllocator 重写为 editGameDir 同款 UIAlertControllerStyleAlert + addTextField（NumberPad、预填 allocatedMemory>0?:512、clearButtonMode）；标题 memory.adjust_title、简介 memory.adjust_message（设备最大内存=物理MB、可分配最大内存=self.maxMemory=物理×0.8 下限 1024 与原拉条上限同口径）；不搬"恢复默认"（i18n_str_898 仅存 editGameDir）；确定 → clamp [512, maxMemory]（空输入落 512）→ allocatedMemory 落值 + memoryAutoEnabled=NO → saveSettings → reload；**存量兼容**：memoryAuto=YES 老实例行仍显示"自动分配内存"（memory.auto_row 键保留），弹窗预填 512，确认一次即回手动；启动链 ame141_currentLaunchAllocMem 的 0=自动比例语义零改动（用户不碰内存行为不变）
- **D. 分辨率缩放实例化**：设置页全局滑条行删除（留 [可撤销] 注释，撤销=恢复行字典 typeSlider 25-150）；PLProfiles prefDefaults 恢复 `@"resolution": @"video.resolution"`（renderer 退役前同款回退机制，[可撤销]）——解析链【profile 键 → 全局存量 → 100】，存量全局值继续生效直到实例显式设置；SurfaceViewController 启动解析单点改 resolveKeyForCurrentProfile:@"resolution"（ame_effective_renderer 同哲学）；实例页 advancedRows 渲染器后插"分辨率缩放"（viewfinder 图标）+ buildResolutionScaleAccessory（52pt NumberPad 输入框 + 右侧 18pt 独立 "%" 标签同一容器、Done 条收键盘、tag 1004、container 复用）+ 点击行聚焦 + resolutionScaleDidEnd clamp [25,100] 落盘 + loadSettings 读（NSString/NSNumber/全局回退、<=0 兜底 100）+ saveSettings 写 existing[@"resolution"] NSString（PLProfiles resolveKey 的 NSString 约定）；JavaGUIViewController 4 处保留全局键（执行 .jar 无实例上下文，注释留档）；游戏内菜单 actionAdjustResolution 维持写全局（运行时调整，重启后实例显式值接管）
- **E. l10n**：+5（default.126 / footer.java25 / profile.title.resolution_scale / memory.adjust_title / memory.adjust_message）-1（memory.current 随卡片退役）×4 门语言 → 基线 1948→1952（set 口径逐语言断言；首版脚本行计数 1986 与门禁不符即 Task154 同款坑，改 set 口径核实 +5/-1 正确）；zh-Hant 风格跟邻近键（manage_runtime 区现状简体照抄、memory 区繁体）
- **F. 发布资产**：announcements.json 四处（summary 尾补三项 / content 新块"Java 与内存（体验调整）"三 bullet / 主页卡片内存措辞改输入框口径 / EN 尾段追加）；indent=1 保持原格式最小 diff（首版 indent=2 全文件重排 92 行 diff，checkout 重跑）；MobileGlues-cpp/version.h 追加 REVISION 17 addendum (Task 159)
- **校验**：verify_task159 新建 48 项全绿（A 预选 4 / B 26.x 7 / C 输入框 10 / D 分辨率 12 / E l10n 5 / F 资产 4 / G 配平+白名单 2 / H 回归 4）；重锚三件：verify_task157 B1-B9/C3/C4/C6 → 输入框形态（44/44）、verify_task149 E1-E6 → 输入框形态（35/35）、verify_task141 C2-C5/D5/D5b/F2/F3 → 输入框+新键口径（36/36，G4 允许前缀 +announcements.json）；l10n 门 1948→1952 ×15 文件（129-135/138/139/142/143/150/151/156/157，脚本 task159_gates.py）；级联 stash 基线对拍零新增失败（129=44/47、130=59/60、131=34/37、133=41/44、134=64/68、138=49/51、139=26/36、142=48+1、143=30+1、140=56+2、137=44+2、156=49+3 全基线一致；132/135/151/153/154/158/125_128 = MyRemastered 沙箱环境性）；重锚脚本坑：sub_check 块替换吞了块间变量定义行（157 的 utils_m / 149 的 mcnews=读 MinecraftNewsViewController.m 而非 LauncherNews…）→ 逐个补回
- 提交推送（fetch 防撞号后）+ CI 轮询

### Stage Summary
- 用户预期装机锚点：①管理 Java 默认预选四行（1.16.5- / 1.17+ / **26.0 及更高版本 [Java 25]** / 执行 .jar），26.x 实例启动走 1_26_newer 槽；②实例内存行点开=输入框弹窗（标题"调整内存分配" + 三行简介 + 数字框 + 取消/确定，无恢复默认），输 0/超上限定 512/上限，确认即生效；③实例"渲染器"行下"分辨率缩放"行（点击行内数字框编辑 25~100，右侧独立 %，Done 落盘），启动生效；全局设置页视频区无分辨率行
- 已知边界：游戏内分辨率菜单与 Java GUI 仍读写全局键（运行时语义）；自动分配开关无入口再开启（存量自动实例保持原比例直到手动确认）；footer.java17 文案保持原文（"1.17 及更高版本"），26.0+ 的默认说明由新 footer.java25 承载
- 留档纪律：CI 绿后不推 worklog-only 提交（Task 96 教训）

---

## Task 160（本会话，新拟态 UI 回归 + 初次默认配置 + 弹窗背景回归 + 分辨率行样式统一 + 文字重影修复）

### 用户五需求（AskUserQuestion 八问定稿后实施）
1. 实例页分辨率缩放行右侧参数样式与内存分配同款（灰字+向右箭头）；输入 clamp 25~150。**定稿：保留行内输入**（不弹窗），右侧值显示带 %。
2. 初次使用默认配置：浅色模式、背景 UI 效果毛玻璃、透明度 10%、模糊 75%。**定稿：仅影响新装/重置**；透明度按"反转理解"= 面板 alpha≈0.1（毛玻璃模式 uiOpacity 直接作 cell 底色 alpha，滑条显示 10% 与实际效果一致）。
3. 大量小窗口背景加回来（例如自定义背景/自定义主页）；"游戏目录/已安装的版本"等字样背后的背景去掉。**定稿：弹窗底色跟随壁纸状态**（无壁纸=系统底、有壁纸=毛玻璃）；范围=模态弹窗类（侧栏/右面板/主页继续透壁纸）。
4. 所有自创 UI 改新拟态（原生代码非 webview），按 CSS 规格：浅 #e0e0e0 + 双阴影 #bebebe/#ffffff、深 #2c2c2c + #1e1e1e/#3a3a3a，主文字 #333333/#f5f5f5、次文字 #888888/#a0a0a0。**定稿：按元素尺寸等比**（340pt=100% 规格 50/20/60，下限 8/4/12）。
5. 设置页选项文字"重叠两次"修复。**定稿：两个都修**（黑影重影 + 换行压字），颜色回归原生。

### Work Log
- 前置：fetch 对齐 e979a58（Task159 并行会话已闭环），空号 160；勘察实锤：ui_theme 默认 dark（PLPreferences:241）、uiOpacity/blurIntensity 默认 0.7/0.7（BackgroundManager:150-160）、makeViewControllerTransparent 毛玻璃分支整页透明、VMSectionHeaderView 铺满 SystemMaterial 毛玻璃块、Task137 曾整退新拟态（三大历史问题：阴影被裁/圆角 50 小元素过圆/深浅色对比）
- **A. 分辨率行样式统一**：buildResolutionScaleAccessory 重构——输入框 17pt secondaryLabelColor（内存行 detailTextLabel 同款灰字）、% 标签同步 17pt、容器尾端补 chevron.right（tertiaryLabel 灰，accessoryView 占位后系统箭头不绘制）+ 容器 76→96pt；clamp [25,100]→[25,150]（旧全局滑条同口径）；行内输入/NumberPad/Done 条/tap-to-focus 保留；属性注释与 loadSettings 注释同步
- **B. 初次默认配置**：PLPreferences general.ui_theme dark→light（SceneDelegate 消费链零改动）；BackgroundManager loadUISettings 默认 uiOpacity 0.7→0.1（毛玻璃分支 cell 底色 alpha=0.1 几乎全透，模糊 75% 保可读）+ blurIntensity 0.7→0.75；效果默认 BackgroundUIEffectBlur 保持；仅 prefDefaults 层生效，存量用户已保存值不变
- **C. 弹窗背景回归**：makeViewControllerTransparent 毛玻璃分支追加 ame160_applyGlassBackdropIfModal——判定 presentingViewController / navigationController.presentingViewController（弹窗 nav 内 push 子页覆盖；侧栏/右面板/root 中央 setContentViewController 两链为空自然跳过），view 底插 SystemThinMaterial UIVisualEffectView（tag 99994 防重复、autoresizing、userInteractionEnabled=NO）；半透明模式走既有底色逻辑不动；VMSectionHeaderView 的 blurView 属性/创建/四边约束全删（标题直接浮壁纸，Task160 注释留档）
- **D. 新拟态引擎**：UIKit+NativeSurface 重建——五个动态色函数（colorWithDynamicProvider 浅/深规格值）+ AmeNeumorphMetricsForSide（340 基准等比，radius clamp[8,50]/offset[4,20]/blur=offset*3）+ AmeNeumorphShadowView（双 CALayer 只投影不画块、shadowPath 圆角矩形、layoutSubviews 随宿主短边重算并写宿主圆角、traitCollectionDidChange 重刷 CGColor；insertSubview atIndex:0 + autoresizing W/H + 关联对象复用）；ame_apply{Card,Raised,Panel}Surface 三方法内部统一路由 ame_applyNeumorphSurface（Task137 语义色退役）；新增 ame_applyNeumorphSurfaceFlatWithRadius（cell/列表场景：只上规格表面色+圆角 clamp[8,50]+masksToBounds=YES，防相邻 cell/tableView 裁剪互叠）——BackgroundManager 三处 cell 管线（applyEffectToView 尾/applyEffectToCollectionViewCell 尾/applyCardEffectToCell）改用 flat；host masksToBounds=NO 放行外阴影（Task137 教训注释）；文字色规格化 11 文件（VMSectionHeader title/subtitle、VersionCard version/date、Home 磁贴 welcome/greeting/公告卡/新闻卡 title/summary、VM 空态、Hero 卡 ×2、NMToast、RightPanel username/progress else 分支——customColor 用户自定义优先分支保留）；Hero 卡手绘黑影/白边框/白 14% 半透明底移除（表面由 applyEffectToView flat/毛玻璃接管）
- **E. 文字重影修复**：LauncherPreferences cell 分支（hasBackground）textLabel/detailTextLabel shadowColor=nil+offset=0（detail 写死 0.8 灰→secondaryLabelColor）+ pickerLabel 同步 + 自定义 label 循环去阴影；header/footer willDisplay 去阴影；PLPrefTableViewController textLabel/detailTextLabel numberOfLines 0→1（Subtitle 多行标题换行压小字的布局半因；adjustsFontSizeToFitWidth 缩字兜长标题）；ManageJRE header 同口径
- **F. 发布资产**：announcements.json 四处（summary 尾 / content 新块"新拟态 UI 与默认体验"四 bullet + 分辨率 bullet 口径更新 / 主页卡片追加 / EN 尾段）；JSON 合法性断言；version.h REVISION 17 addendum (Task 160)；**l10n 零新键零退役，基线 1952 四语言 set 口径复验不变**
- **校验**：verify_task160 新建 47 项全绿（A 分辨率行 7 / B 默认 5 / C 弹窗背景 6 / D 新拟态 10 / E 重影 6 / F 资产 5 / G 配平+白名单 2 / H 回归 6）；重锚 5 处：verify_task159 D9（clamp 150）+F2（announcements 口径）48/48、verify_task149 A4/C2（文字色规格化）35/35、verify_task141 A3 36/36、verify_task137 D1/D2/D9（三表面→新拟态形态；masks 计数 3→2）46/46；verify_task157 44/44、150 43/43 幸存；级联对拍零新增失败（129=44/47、130=59/60、133=41/44、143=30+1、156=49+3 与基线逐项一致；132/135/151/153/154/158=沙箱环境性）；校验器配平函数坑：正则版 strip 在"字符串内含 //"（URL）时错位误报 PLPreferences/PreferredVC/RightPanel 三文件——改字符状态机单遍扫描修复
- 提交推送（fetch 防撞号后）+ CI 轮询

### Stage Summary
- 用户预期装机锚点：①实例页"分辨率缩放"右侧=灰字数字+独立%+向右箭头（内存分配同款），输入 25~150；②新装/重置后=浅色模式+毛玻璃+透明度 10%+模糊 75%，存量用户不受影响；③壁纸模式下自定义背景/自定义主页/各设置弹窗有页面级毛玻璃底（不再整页透明），"游戏目录/已安装的版本"标题背景块消失；④全部自创 UI 新拟态（规格表面色+双阴影+规格文字色，深浅自适应）；⑤设置页文字无重影、换行不压字（黑标题+灰小字）
- 已知边界：Task137 的"列表 cell 无阴影"以 flat 版本延续（列表阴影互叠是历史证明的坑）；Hero 卡/设置列表走 flat 无外阴影（壁纸模式毛玻璃视觉主导）；等比圆角下限 8 对徽章类仍略圆
- 留档纪律：CI 绿后不推 worklog-only 提交（Task 96 教训）

## Task 161（本会话，装机反馈六案根修：FSR 复活 + 壁纸设置页被盖 + Bing 静默应用 + 外观默认 + 侧边栏闪退 + 26.2 键盘）

### 用户反馈（9c66184 构建，1e6f796 日志两份均 libMobileGL 会话）
"可以呀3端都可以了。怎么都没有fsr放大和锐化呀连zink都没有了。还有第一次启动重启之后壁纸设置中，好像盖了什么东西，所有文字和按钮都看不到，但是只有滑块滑动不了，而且2个滑块默认值是透明度60%模糊程度为100%。还有bing壁纸还是要重启才能静默加载。还有外观模式默认跟随系统。还有右边信息栏点击启动器版本，jit和2个内存扩展闪退。还有26.3遇到光标能正常弹出键盘，而26.2及以下都不行。"

### 根因（逐条实锤）
1. **FSR 全无（连 zink）**：用户整合包 profile（ModpackImportService.createProfileForModpack 建）无 renderer 键 → ame_effective_renderer 落 "auto" → auto 只认 legacy 整数档位（mobileglues.mobilegl_backend），**不消费新后端键 mobileglues.renderer_backend** → 用户设置页选的 4.0 后端（日志 L23 实锤写入 libmithril.dylib）完全被无视，恒解析 libMobileGL.dylib（Vulkan 直连，Task154 FSR 退休链）。zink 本身链路完好（10cee5d/e8e55b2 会话 sentinel LANDED 实证），用户感知"连 zink 都没有"= 其 auto 实例永远到不了任何 FSR 路径。
2. **壁纸设置页被盖**：Task160 的 ame160_applyGlassBackdropIfModal 对 UITableViewController（view==tableView，即 BackgroundSettingsViewController）insertSubview 进 **UITableView 本体**——外来视图插表不受支持，iPadOS 27 装机表现为整页像盖了东西/文字按钮不可见/滑块拖不动。另：背景容器 addBlurEffectToContainer 的 blurView/dimView 从未关 userInteractionEnabled（层级异常时拦截触摸的保险带）。
3. **Bing 需重启才能静默加载**：`applyBackgroundToWindow:` 顺序为【L200 设 currentWindow → L204 调 removeGlobalBackground → 后者 L311-312 把 currentWindow/currentSplitVC 置 nil】——启动后宿主引用恒空，Bing 下载完成后的 setBingBackgroundImageAtPath 应用分支（双 nil）静默空转：状态已落盘、活 UI 从不更新，重启时启动路径才真正应用。Task152 的 refreshTransparencyForWindowUI 同因 root=nil 跳过。
4. **外观默认**：Task160 默认 light（此前 dark）；用户指令改"跟随系统"。存量设备已固化历史默认，需迁移（dark/light → auto，仅未显式选择者）。
5. **侧边栏 4 卡闪退**：Task156 深链按 prefContents 全量索引 selectRowAtIndexPath，而主设置页分区默认折叠（prefSectionsVisible 默认 NO，折叠分区 numberOfRows=1）→ check_update/jit_enabler/memory_limit_help 的 r>0 索引越界 → NSInternalInconsistencyException。游戏版本卡（versionManager 分支）/设备系统卡（无深链键）不滚动故不炸——与用户报告的四卡完全吻合。
6. **26.2 及以下键盘不自动弹**：26.3 走 SDL（SDL_StartTextInput + Task114 screen-keyboard hint → 系统键盘 ✓）；≤26.2 走 GLFW——GLFW 协议无"开始文本输入"概念，vanilla EditBox 聚焦不发出任何可观察信号。

### 修复（10 代码文件 + 3 验证器）
- **LauncherPreferences.m**：①ame_effective_renderer auto 分支消费 ame142_effective_backend_key（GLES/Mithril → libmobileglues.dylib 存在守卫；Vulkan/默认维持返回 "auto"，旧 MC ANGLE 回退语义不变）；②ame158_mg_mobileglues_mode 对 auto/无键 profile 同源跟随（否则 auto+GLES 拿 mode 0 → customGLVersion=40 → ES 方块不渲染回归）。
- **BackgroundManager.m**：③ame160 对 view==tableView 的 table 控制器改挂 tableView.backgroundView（UIKit 管理位，cells 之下、不参与命中测试）+ 非 table 路径保持 insertSubview:atIndex:0；ame160 调用移到 makeViewControllerTransparent 末尾（table 分支 backgroundView=nil 之后）；④addBlurEffectToContainer 的 blurView/dimView 显式 userInteractionEnabled=NO；⑤removeGlobalBackground 不再清空 currentWindow/currentSplitVC（均 weak；注册语义归 apply 方法所有）。
- **BackgroundSettingsViewController.m / LauncherPreferencesViewController.m**：⑥viewWillAppear/reapplyBackgroundEffect 改走 makeViewControllerTransparent 单点，不再手写 backgroundView=nil（会把 glass 清掉）。
- **PLPreferences.m / SceneDelegate.m / LauncherPreferencesViewController.m**：⑦ui_theme 默认 light→auto + 注册 ui_theme_explicit 标记键；SceneDelegate 一次性迁移（未显式选择 + 值为历史默认 dark/light → auto）；设置页 pick action 置显式标记。
- **LauncherPreferencesViewController.m**：⑧深链命中后先展开折叠分区（prefSectionsVisibility[s]=YES + reloadSections）再滚动/高亮 + 行数防御（r >= numberOfRowsInSection 只展开不选中）。
- **input_bridge_v3.m / utils.h / SurfaceViewController.m**：⑨nativeSendKey 记录最近按下键（ame161_lastSentKey/Time）；ame161_lastSentKeyWasChatOpener(within) 查询（T=84/SLASH=53）；updateGrabState 在 GLFW 路径（g_sdlWindow==NULL）grab 转 false 且 1.5s 内发过聊天开键 → inputTextField 自动弹出（ame161_autoShown 标记，回游戏自动收起，手动 ⌨ 不受影响，26.3 SDL 零影响）。
- **JavaLauncher.m**：⑩过时的 "auto will be resolved to ANGLE" 警告改写为 Task144/161 语义。

### 校验
- verify_task161 新建 56/56 ALL GREEN（A auto 跟随 5 + A2b 决策矩阵镜像 14 + B 壁纸页 7 + C Bing 4 + D 外观 5 + E 深链 3 + F 键盘 7 + G 文案 1 + H 括号平衡 10）。
- 级联：156=52/52、160=47/47（B1/B5 重锚 Task161 语义 + ROOT 环境注入）、151=46/46、158=32/33（A4 重锚 git 钉住 d380bcc 防日志轮换；C6 取证存档被沙箱清除=既有环境性）、140 G2/G3 与 stash 基线逐项一致（日志轮换）、142/143 链式同因、149 路径硬编码另一会话沙箱=环境性——**零新增失败**。
- 10 个改动 ObjC 文件 + version.h 括号平衡全 0（字符状态机剥离）。

### Stage Summary
- 装机验证锚点：①整合包实例（renderer 未设）+ 设置页后端选 GLES/4.0 → 日志 `RENDERER is set to libmobileglues.dylib` + `[SurfaceVC] Task83 FSR linkage: renderer=libmobileglues.dylib preset=4 scale=2.00` + MobileGlues FSR1 生效（画面=渲染分辨率升采样）；后端选 Vulkan/默认 → 行为与 9c66184 一致（libMobileGL）；②重启后壁纸设置页文字/按钮/滑块全部正常可交互（glass 走 backgroundView）；③首启联网数秒后 Bing 壁纸不重启即上屏（日志出现 `Task151 auto-apply OK` + `Task152: transparency refreshed`）；④未手动选过外观的设备自动跟随系统（日志 `Task161: ui_theme 'dark' was a historical default ... migrated to 'auto'`）；⑤侧边栏启动器版本/JIT/内存两卡点击直达设置对应行并高亮（日志 `deep-linked to row`），不再闪退；⑥26.2 及以下游戏内按 T/斜杠打开聊天 → 键盘自动弹出（日志 `Task161: chat key + ungrab -> keyboard auto-shown`），回游戏自动收起；26.3 行为不变。
- 已知边界：GLFW 路径的键盘自动弹只覆盖聊天/命令行（T/斜杠前驱）；告示牌/书与笔等右键场景仍需 ⌨ 手动（歧义大，故意不自动化）。

---
Task ID: 162
Agent: main (Super Z)
Task: 用户八案装机反馈根修（bf91f41 构建 = Task161 修复后的新 IPA，cbef9d5 两份日志）：①"切换渲染器为其他都会自动切回自动" + "mg的fsr依旧失效" ②"forge加载存档闪退" ③"bing壁纸加载完成还是要重启才能有图片" ④"壁纸设置默认值为毛玻璃，60%的透明度，100%的模糊" ⑤"切换其他标签页再切换回主页，上方的头像缺失，必须点击一下" ⑥"账号添加完成需要手动刷新账号标签页" ⑦"curse forge加载源完全无法使用" ⑧"在公告添加服务器推荐：mysv.dpdns.org"

Work Log:
- 判读：旧会话日志实锤 "renderer written to PROFILE ONLY 'Fabulously Optimized' = mg/libOSMesa.8.dylib" 两次写入后，启动链 "Task120: profile renderer was (null) -> auto"——写入与读取用了两个不同身份
- ①根因（Profile 身份不一致，三处叠加）：ProfileSettingsViewController 以 name 字段为字典键写；ModpackImportService 重名导入产生键 "Name (2)" + name 字段 "Name"；主页版本选择器把 name 字段写进 selectedProfileName + allValues 无序行漂移。修复：编辑器加载时记录 profileDictKey（读源同写目标、空基底回退 working copy、重命名按旧键删新键建并同步 selected/profileDictKey）；选择器改排序键快照（didSelectRow 落字典键、漂移自愈重建、越界防御）。渲染器/内存/分辨率/Java 全部字段随之修复（= mg 的 FSR 丢失根因：mg 选择从未落到真实条目 → 恒 auto；mg+GLES/4.0 后端才有 MobileGlues FSR1，mg+Vulkan 直连无 FSR 属 Task154 设计语义，zink 有）
- ②根因：进存档 ReceivingLevelScreen.onClose → MouseHandler 抓鼠标 → GLFW.glfwSetInputMode → UIKit.updateMCGuiScale()（launcher.jar 独有类）→ Forge MC-BOOTSTRAP 模块层 NoClassDefFoundError。修复：lwjgl overlay 移除 UIKit 调用；nativeSetGrabbing（GLFW JNI 路径）补 refreshGuiScaleNatively()（Task63 native 直读，与 SDL 路径对齐）
- ③根因："已是今日图"静默跳过不检查活 UI。修复：BackgroundManager.isBackgroundLiveAttached（容器→window→宿主三段判定）；静默跳过前检查，未挂载则重放 setBingBackgroundImageAtPath（每次元数据同步/回前台/手动刷新都是自愈口）
- ④壁纸默认值：uiOpacity 0.1→0.6、blurIntensity 0.75→1.0（仅新装/从未保存过键的设备）
- ⑤主页头像：AvatarManager 本地 → 会话 NSCache → 网络三层链（viewWillAppear 同步命中，不再裸重下载）
- ⑥账号列表：reloadAccountList 提取 + viewWillAppear 重扫 + AccountChanged/UpdateAccountInfo 双通知
- ⑦CurseForge：实测 MCIM 镜像免 key（curl 无 x-api-key → 200）→ baseURL 无 key 强制落镜像 + isSourceAvailable 替换 6 处门控（DownloadViewController×3 / ModVersion / ShaderVersion / ServerList）；有 key 设备镜像策略语义不变
- ⑧公告：新增"推荐服务器：mysv.dpdns.org"（2026-09-24 置顶）；v6.0.0 文案默认值同步 60%/100% + 跟随系统（CN+EN）
- version.h REVISION 17 addendum (Task 162)
- 验证：verify_task162 新建 68/68 ALL GREEN；级联 161=56/56、160=47/47（重锚）、158=32/33（C6 环境性=基线）、156=52/52、150=43/43 + 157=44/44 + 159=48/48（公告锚点 [0]→按 id 重锚）、149=35/35、151=46/46；其余与 stash 基线逐项一致（差异仅"预期文件集"类检查，提交自愈）
- 教训：终端显示层吞 "[m" 序列（[msg dismiss] 显示成 sg dismiss]）→ bash 管道观察 ObjC 方括号代码不可信，须字节级复核

Stage Summary:
- 装机验证锚点：①实例页选渲染器后不再回退 auto（键≠名设备日志 "Task162: save keyed by dict key ... no phantom write"）；mg+GLES/4.0 → "Task83 FSR linkage ... scale=2.00" ②Forge 1.20.1 进存档不崩 ③Bing 加载完成即上屏（脱界自愈日志 "Task162 self-heal re-apply OK"）④新装默认 60%/100% ⑤切页返回头像即显 ⑥添加账号即见 ⑦无 key 可用 CurseForge（世界 tab 同）⑧公告见服务器推荐
- 遗留待装机观察：26.2 键盘弹出（Task161⑥）、静态库虚拟按钮、26.1.2 libjvm 崩溃

---


Task ID: 163
Agent: herbrine8403 (Claude 会话)
Task: 装机反馈修正——新拟态范围纠偏（侧栏/右面板阴影退役 + 主页磁贴/下载版本卡凸起）+ 实例设置页箭头统一

用户反馈（逐字）：
1. "我根本就没看到你改了UI，主页的卡片一点没改，下载页面版本选项一点没改，倒是把左侧栏和右侧栏改了，这两个栏的阴影直接影响了旁边的卡片，不该改的你改了，该改的你就是不改。"
2. "实例设置页面的渲染器右侧的灰色箭头与其他选项样式不匹配，十分突兀"

根因：
- 侧栏/右面板：LauncherRootViewController updateChromeSurfaces 无壁纸分支走 ame_applyPanelSurfaceWithRadius（Task160 把三方法统一路由到 ame_applyNeumorphSurface 带双阴影）——全屏高大容器短边接近 340pt 基准，等比 offset≈20/blur≈60 的阴影直接溢出压到中央卡片上。
- 主页磁贴/下载版本卡：走 BackgroundManager 管线的 Flat 尾分支（Task160 防 cell 阴影互叠的取舍）——完全无阴影，与 Task160 之前观感几乎一致 = 用户"一点没改"。
- 箭头：实例设置页 13 处系统 DisclosureIndicator 与分辨率行（Task160 自绘 chevron.right）相邻对比，glyph 粗细/形态肉眼可见不同。

修复（8 文件 + 3 验证器重锚 + 1 新验证器 + 公告，零 l10n 变更基线 1952 不动）：
- UIKit+NativeSurface.h/.m：ame_applyPanelSurfaceWithRadius 转 Flat 路由（规格表面色+圆角 clamp[8,50]，不挂阴影承载层；maskedCorners 不触碰、masks=YES 与侧栏创建态一致）；新增 ame_removeNeumorphShadow（移除阴影承载视图+清关联对象，背景模式切换防旧投影穿帮）。
- BackgroundManager.h/.m：新增 applyNeumorphCardEffectToView:（有壁纸转调 applyEffectToView 并前置清阴影；无壁纸挂 ame_applyNeumorphSurface 凸起）；applyEffectToCollectionViewCell 无壁纸分支 Flat→NeumorphSurface + 宿主链放行（cell.clipsToBounds=NO + contentView masks=NO，阴影越界投磁贴间隙）；applyEffectToView/CollectionViewCell 壁纸分支入口防御清阴影。
- VersionCardCell.m：换调 applyNeumorphCardEffectToView（cardContainer 链 masks=NO 阴影链通）。
- ProfileSettingsViewController.m：新增 ame163_disclosureChevron（chevron.right tertiaryLabel 8x13 in 14x30 容器，与分辨率行尾端同 glyph/同色/同尺寸/同距右缘 6pt）；13 处 DisclosureIndicator→自绘 accessory（渲染器/游戏目录/资源管理 5 行/组件安装 3 行/图形API/Java/内存），游戏版本行无效 accessoryType 赋值删除——整页系统 disclosure 清零。
- LauncherRootViewController.m：updateChromeSurfaces 注释同步（调用点不动，语义就地生效）。
- version.h：REVISION 17 addendum (Task 163, no bump)。
- announcements.json：新拟态 bullet 补"主页磁贴与下载版本卡片凸起双阴影（侧栏/右面板平贴不投影）+ 实例设置页箭头统一"；"主页所有卡片取消阴影"（Task149 旧语义）改"主页磁贴卡片随视觉大改更新为新拟态凸起阴影"。JSON 合法断言过。

验证：
- verify_task163.py 新建 36 项全绿（A 侧栏平贴 5 / B 卡片凸起 11 / C 箭头统一 6 / D 回归 7 / E 配平 7）。
- 重锚：task160 D6（NeumorphSurface 直调 3→2，Panel 转 Flat）+ H1（内存行箭头锚→chevron 形态）；task157 A1 / task159 H4（"行箭头与 Java 版本同款"语义保留，实现锚→ame163_disclosureChevron）。重锚后 160=47/47、157=PASSED、159=PASSED。
- 幸存全绿：137=46/46、149=35/35、141=36/36、150=43/43；基线对拍 129=44/47、130=59/60、133=41/44、143=30+1、156=49+3 与记录一致（沙箱环境性，零新增）。
- 配平：7 个触碰 ObjC 文件 {} () 平衡全 0（字符状态机，与 task160 口径一致——引号奇偶属基线噪声不判定）。
- 教训：MultiEdit 多编辑非严格原子（H1 old_str 失败但 D6 已应用）——重锚后必须 grep 复核每一处。

Stage Summary
- 装机验证锚点（无壁纸模式）：①主页磁贴（Profile/Info/公告/新闻/快捷）呈现新拟态凸起双阴影（右下暗影+左上高光，随卡片尺寸等比）；②下载页版本卡片同款凸起；③侧栏/右面板平贴表面+外侧两角圆角，无阴影溢出，旁边卡片不再被压；④实例设置页渲染器/内存/Java 等所有跳转行箭头与分辨率行完全同款（细灰 chevron）；⑤壁纸模式行为不变（磁贴/版本卡毛玻璃，侧栏透壁纸）；⑥深浅色切换阴影/表面自动重刷。
- 已知边界：collectionView 边缘磁贴外侧阴影由 collectionView 自身裁剪收口（原生 app 常见形态）；相邻磁贴间隙淡阴影叠加属新拟态正常形态，若装机观感需调浓度可改比例系数。
- CI 记录：push 后 fetch 发现并行会话 df96d13 抢占 162 号 + 其 CI 失败（AccountList duplicate method）→ 本批重编 163（rebase 融合：源码自动合并无冲突；version.h/announcements/worklog 手工融合；verify_task162.py 保留并行 68 项版、我的 36 项版改名 verify_task163.py；ame162 独占标识→ame163 精确改号）；我的首 run 36026472118 被并行 hotfix 678a76f 的 concurrency 取消；**组合 run 36026565195（678a76f，基于 447a677）completed success**——含 Task163 全部改动的最终产物 ipa/tipa/dSYM 可下载，待用户装机验证。
- 融合期重锚链：task160 D6/H1 注记改号 163、task157 A1 / task159 H4 锚改 ame163、task150 F6（Task163 推翻 Task149 '取消阴影'→'新拟态凸起阴影'）、task161/162 ROOT 环境变量化；终态 163=36/36、162=68/68、161=56/56、160=47/47、157/159/150/137/149/141 全绿。

---
Task ID: 162 (续)
Agent: main (Super Z)
Task: CI 闭环

Work Log:
- df96d13 首推 CI 失败（run 36024818658）：AccountListViewController.m 重复声明 reloadAccountList（:89 我方新增 vs :883 文件末既有的 FCL 风格实现——grep "reloadData" 时漏查了既有方法的调用面）；lwjgl overlay（GLFW.java）编译通过
- 热修 33a0281：删除我方重复定义，既有 reloadAccountList 成为唯一实现，viewWillAppear/双通知三个触发口全部复用；verify_task162 F1-F4 重锚（新增唯一实现检查）
- 推送遇并行会话 Task 163（447a677，新拟态作用域修正，已自觉从 162 改号为 163 并在我的 60%/100% 文案同步之上叠加）——rebase 干净落地（仅 AccountListViewController.m + verify_task162.py 两文件差异）
- 复验：162=68/68、163=36/36（TASK163_REPO 注入）、161=56/56、160=47/47
- CI run 36026565195（678a76f）completed success；artifacts：com.air-devs.air-ios.ipa 205.8MB + trollstore .tipa + dSYM

Stage Summary:
- Task162 八案全链闭环：根修 + 验证器 + 级联 + CI 绿 + 新 IPA 就绪（含 Task163 新拟态修正）
- 装机待验证锚点见上一节 Stage Summary；mg 的 FSR 注意：mg+GLES/OpenGL 4.0 后端 → MobileGlues FSR1（装机日志看 "Task83 FSR linkage ... scale=2.00"）；mg+Vulkan 直连后端无 FSR（Task154 设计语义）；zink 自带 FSR（本轮日志已实证）

---
Task ID: 164
Agent: main (Super Z)
Task: 用户报"vulkan没有fsr。es和4.0黑屏。壁纸默认半透明60%/0%（应为毛玻璃60%/100%）" + 判读朋友 00:40 上传的新日志（56c8173）+ 解释"Add files via upload #399"

Work Log:
- 判读 56c8173 上传对（构建 678a76f）：latestlog.txt = mg GLES 会话（FSR+EASU+RCAS 全 engage、fps=58、swap 330/330、用户拖鼠标后切后台 = 黑屏现场）；latestlog.old.txt = Vulkan 直连会话（fps=59、exit(0)、Task154 退休链日志 = "vulkan 没有 fsr"实锤）
- "Add files via upload #399"释义：朋友（Gsjsjzhznsz）网页拖拽上传新设备日志，#399 是该上传触发的 CI 构建编号，非代码改动
- ES/4.0 黑屏根因定位：5.1.0 健康基线（a0ac656 latestlog.es/4.0）同管线但 EASU-only（无 RCAS pass）有画面；新构建唯一 delta = Task130 RCAS pass；mod 组合两场一致（continuity/iris 都在）排除模组变量；四项与 zink 已验证 RCAS（osm_bridge，实机正常）的实现差异全部修正：
  ① FSRRCASSource.h FsrRcasLoadF 边界 clamp（textureSize 自查）——fullscreen-quad 边缘像素的 5-tap 越界 texelFetch 在 Mesa 良性、ANGLE Metal（MTLTexture read:）未定义可整帧作废 = 最可能真根因；三 TU 共享（zink 获得正确边缘行为，零视觉回归）
  ② FSR1.cpp 两个 directToSurface 分支 disable 列表补 GL_STENCIL_TEST（zink 五件套；EGL config 带 stencil bits + 模组可能留拒绝型 stencil test → quad 逐像素被丢而 swap 照常）
  ③ RCAS draw 前显式 glActiveTexture(GL_TEXTURE0) + sampler 每帧 re-pin（zink 形态）
  ④ RCAS 首帧后一次性 GPU 探针（fb0 边缘单像素 + glGetError 清扫）——装机分诊锚点 "[MG] Task164 RCAS GPU probe"
- 壁纸默认值根因：Task162 范围检查把"从未保存"误当"保存了 0"——integerForKey 未保存返回 0 = 枚举半透明（范围检查放行）；floatForKey 未保存返回 0.0 过 "< 0.0" 检查（0% 模糊）；三键统一 objectForKey == nil 判定（nil → 毛玻璃/0.6/1.0；显式保存值含故意选半透明/0% 照常尊重）
- Vulkan FSR 评估：libMobileGL.dylib 二进制 strings 零 FSR/EASU/RCAS 符号、零相关环境变量、不读 config.json（Task153 实证）+ 伪 EGL（Task154 三重实证：句柄恒 0x1、无 current 跟踪、强推 = 花屏+输入错位）→ 上游硬限制不可行；公告/FAQ 明示矩阵（GLES/4.0 = 完整 FSR1 EASU+RCAS；Vulkan 直连 = 暂不支持，切后端指引）
- 公告更新（scripts/task164_announcements.py）：v6.0.0 失实的"MobileGL 全后端 FSR 修复"改为准确矩阵表述 + 新增 Task164 置顶公告；保持 indent=1
- version.h REVISION 17 addendum（Task 164，不 bump）
- 验证：verify_task164 新 30/30；级联 162=68/68（D1-D4 重锚 nil 判定形态）、160=47/47（B5 重锚）、161=56/56、163=36/36（env 注入）、150=43/43、157=44/44、159=48/48、158=32/33（C6 与上轮 environmental baseline 一致）

Stage Summary:
- ES/4.0 黑屏：RCAS 管线四项对齐 zink 已验证形态（边界 clamp/五件套状态防护/显式 unit+re-pin/GPU 探针），装机验证锚点 "[MG] Task164 RCAS GPU probe: ... nonzero = draw landed"
- 壁纸首启默认：毛玻璃/60%/100% 真正生效（nil 判定）
- Vulkan 直连 FSR：上游不可行（零符号+伪 EGL 实证），公告/FAQ 明示切换 GLES/4.0 获得完整 FSR
- 遗留：装机验证（黑屏是否痊愈 + 探针读数）；26.1.2 libjvm 崩溃、静态库虚拟按钮等继承待办
