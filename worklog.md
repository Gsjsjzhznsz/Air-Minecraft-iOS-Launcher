# Worklog

## ⚡ READ ME FIRST —— 会话速览（只读本节 + 「滚动近况」即可开工；更早历史一律查 worklog-archive.md，勿通读）

> 最后更新：Task 142（2026-09-22）。此前记录：2026-09-22 本文件瘦身重构（Tasks 34-140 → worklog-archive.md，未占用 Task 编号）。
> 新会话规则：新任务记录**追加到本文件最末尾**（`## Task N` 或 `---/Task ID:` 模板均可）；收尾时同步更新下面「当前状态」表；本文件超过 ~400 行时把最旧的任务段挪进 worklog-archive.md。

### 一句话
AngelAuraAmethyst（Amethyst-iOS 重制版，fork **Gsjsjzhznsz/Air-Minecraft-iOS-Launcher**）——iOS Minecraft 启动器，已发布 **v6.0.0**：MC 26.x 全链路可玩（26.3-pre-1 + Fabric + 128 mods + MobileGlues 渲染链）。当前主线：UI 打磨、渲染器存储分层（auto/mg + mobileglues.renderer_backend）、各 MC 版本崩溃根修。

### 当前状态（收尾时更新）
| 项 | 值 |
|---|---|
| 远端 HEAD | 3400211d（worklog 瘦身 + verify 重锚），CI #340 前绿（~10-12 分钟/次） |
| 最新 Task 号 | **142**（双会话并行开发，开新任务前先 fetch 避让编号） |
| 待用户装机验证 | Task 141 七项 UI（欢迎卡/版本行/内存弹窗/JVM行/新闻页）+ Task 142 渲染器分层七锚点（见下文两条 Stage Summary） |
| 已知历史遗留 | v6.0.0-release-notes.md 是工作区工件不在 git（发布时从 announcements.json 重导出）；部分 verify 级联失败为沙箱环境性（会话本地脚本被清），与基线对拍判读 |

### 双会话并行协作规则（重要）
- 推送前必须 `git fetch origin && git rebase origin/main`；Task 编号冲突避让下一空号并在记录里注明
- 验证器级联：`scripts/verify_taskNNN.py`（129-142 全家）；动 l10n/公共 UI 必须重锚基线计数（当前 1924）并对拍「零新增失败」
- 沙箱会随机重置工作区/本地 ref：**仓库是唯一事实源**；工作区工件丢失按 archive 记录重建；本地落后时 `git fetch && git reset --hard origin/main`

### 关键路径与命令
- 仓库: `/home/z/my-project/Amethyst-iOS-MyRemastered`；GitHub token 在 `git remote -v` 的 URL 里（放心直接用）
- CI 轮询: `TOKEN=$(git remote get-url origin | sed -n 's\|https://[^:]*:\([^@]*\)@.*\|\1\|p')` + `/actions/runs?per_page=N` API；失败先拉 job log grep "error:"
- 产物: artifact `com.air-devs.air-ios.ipa`（另有 trollstore .tipa / dSYM）
- l10n: en/zh-CN/zh-Hans/zh-Hant 四语言键集一致，基线 1924
- 用户日志: `/home/z/my-project/upload/`（hs_err_pid*.log / latestlog.txt）

### 高频方法论（细节查 archive）
- hs_err 判读：信号类型 / si_addr（ASCII 字节=UAF 或字符串当指针；地址截断=ABI 错位）/ pc 崩溃帧 / free stack 排除栈溢出；latestlog 管道会丢尾，截断点 ≠ 崩溃点
- CI 产物必须 `strings` 验证包含新日志串再交付；TEST-ONLY 补丁用 python 定点替换（禁 git checkout 回滚）；Makefile 防 tab→空格污染
- shaderc 渲染链（Task 30-47 沉淀）：main_hook.m 32MB 栈 hop → shaderc_shim.c（串行化 + SIGSEGV 恢复网 + 源快照 + #include 文本级展开）→ libshaderc_impl（源码构建 + lValueErrorCheck 二进制补丁）

### 历史检索
- Tasks 34-140 明细 → `grep -n "Task ID:" worklog-archive.md`；Task 141 起在本文件
- 找 commit：`git log --oneline --grep "Task N"`

---

## Task 141（本会话）

### 用户七项需求
1. 未选择账号时主页欢迎卡显示空白 → 应显示右边栏同款默认头像。
2. 欢迎卡灰字问候语改为公告标题（喇叭图标 + 标题）+ 公告卡同款"查看详情"按钮；字号与欢迎语一致。
3. 下载页版本行主标题字号比时间灰字小 → 改成一致。
4. 实例管理"内存分配"枚举列表改弹出小窗口：顶部灰字（当前内存：xMB）+ 拉条 512MB→启动器检测最大可分配。
5. 排查"…"截断改缩字（至少：实例管理 JVM启动参数行、下载页版本列表时间 2026-…）。
6. 排查启动内存由实例内存分配还是全局"Java 内存分配(MB)"决定；改为实例决定；后者（及其自动调整选项）删除。
7. MC 新闻页贴边单列、禁左右滑（检测屏幕大小贴于窗口）。
注：另一会话并行提交 CI，编号避让至 141（远端已推进 138/139/140），推送前 fetch 对齐。

### 根因与实施
- **Item1/2（LauncherNewsViewController.HomeProfileTileCell）**：无头像分支改用 `DefaultAccount` 资产（账户列表同源；缺失回退 SF 占位）；greetingLabel 退役，第二行改为 announceRowStack（megaphone.fill 图标 + 公告标题 21pt bold 与欢迎语一致、缩字不截断 minScale 0.6 + detailButton 公告卡同款 #3B82F6 白字圆角 8，条件与公告卡一致 actionURL+actionTitle，复用 openAnnouncementActionURL）；无公告回退 festivalGreeting 14pt 灰字、图标按钮隐藏；welcomeStack 仍相对头像 centerY 居中。
- **Item3/5（VersionCardCell）**：版本号 minimumScaleFactor 0.7→0.75（16×0.75=12pt=日期字号，标题永不再小于灰字）；日期右锚从 topRowStack 尾部（被短版本号拖窄 → "2026-…"截断根因）改锚 chevron 左侧 8pt，12pt 日期完整显示。
- **Item4/5（ProfileSettingsViewController）**：showMemoryAllocator 由 actionSheet 枚举列表重写为原生弹出小窗口（遮罩点击取消 + ame 卡片表面 16pt + 顶部灰字 memory.current 实时刷新 + UISlider 512MB→self.maxMemory（物理×0.8 随设备自适应，用户参考值 6116MB 即此口径）+ 取消/确定，确定写回 allocatedMemory→saveSettings）；cell 创建时 textLabel/detailTextLabel 加 adjustsFontSizeToFitWidth + minScale 0.6（JVM 启动参数行被 200pt accessoryView 挤压的"JVM启动…"根治）。
- **Item6（内存决策链）**：旧链 = 全局 java.auto_ram/java.allocated_memory 决定 -Xmx，实例 allocatedMemory 写 general.ram_allocation 但全仓无读取方（死项）。按用户指令反转为实例决定：utils.h/.m 新增共享助手 `ame141_currentLaunchAllocMem`（读当前实例 profile[@"allocatedMemory"]，未设置回退原自动比例 0.5/0.25），JavaLauncher -Xmx 与 SurfaceViewController updateJetsamControl 两处同源（Task68 的"必须逐字一致"从结构上保证）；LauncherPreferencesViewController 全局两行（auto_ram 开关 + allocated_memory 滑条）删除；validateVirtualMemorySpace 校验与启动日志锚点保留。
- **Item7（MinecraftNewsViewController）**：旧布局组宽 1.0 但子项 0.5 且仅一项 → 卡片贴左半宽右侧留白（"不是连贯的上下滑动"根因）；改子项 fractional 1.0 贴于窗口随屏幕自适应 + contentInset 左右 0 + alwaysBounceHorizontal NO；Task136 等高机制不变。
- **l10n**：+2 键（memory.current/memory.apply）× en/zh-CN/zh-Hans/zh-Hant（基线 1920→1922，四语言键集一致）。

### 校验
- verify_task141 新增 35 项（A 欢迎卡 7/B 版本行 3/C 实例设置 7/D 内存决策链 7/E 新闻页 4/F l10n 3/G 语法 4，含 UIColor 白名单审计）。
- 重锚：task136 E4（welcomeStack 第二行）；l10n 基线门 1920→1922 ×7（task129 I3/130 H3/131 G3/132 F1/133 F1/134 G1/135 D3/138 I-l10n）；task137 G3 增加 Task141 diff 形态分支（修复 diff 行 `+` 前缀未剥离的谓词漏洞）。
- 全量级联 stash 基线对拍（129-141 + 103/105）：**零新增失败**；基线独有 20 条为 103/105 的 g++ 环境闪失（本轮反而全过）；task132 A15/F4/F5 为被沙箱清除的会话本地审计脚本所致（与基线一致，环境性）。
- 口径护栏零变化：getEntitlementValue ×2 / isJITEnabled(NO)+TXM / 七卡工厂 / 侧栏自愈 / 新闻等高 / AmeBadgeLabel / 原生表面 API 全部原位。

### Stage Summary
- 用户预期：①无账号显示 DefaultAccount 默认头像 ②欢迎卡第二行=公告标题行（同字号+同款按钮，可点查看详情）③版本标题最坏情况与时间同字号 ④内存分配弹窗拉条（灰字实时显示当前内存，512→设备最大）⑤JVM 启动参数行与版本时间不再截断 ⑥启动内存由实例拉条决定，全局两行删除 ⑦新闻页贴边单列不可左右滑。
- 待用户安装新 CI 工件实机验证；另一会话并行开发期间推送前需 fetch 对齐。

---

## Task 142（本会话，渲染器）

### 用户需求（原话要点）
1. 实例页渲染器选项太多（跟随全局 + 8 经典 + MG 家族三后端共 11 项）。
2. "跟随全局渲染器设置放到外面，只要为真，渲染器选择就变灰"。
3. "我之前的想法一直都是在渲染器选择只有一个 mg，而且不写什么后端，后端是根据 mg 设置选择的后端启动默认 vulkan"。
4. "最后再审核一下"（渲染器持久化链路全面复审）。
5. 注意：另一会话并行操作项目（其对 Task 141 已占用 141 编号与 verify_task141.py——本轮重命名避让为 Task 142，rebase 对齐后推送）。

### 设计（存储分层）
- **渲染器层**（全局 `video.renderer` + 各 profile `renderer` 键）：只存逻辑键 `auto` / `mg`（新增 RENDERER_KEY_MG，rendererCandidates 永列项）/ 经典 dylib 键。
- **后端层**：MobileGL 家族键（libMobileGL / libMobileGL-gles / libmithril）迁入独立键 `mobileglues.renderer_backend`（默认 libMobileGL.dylib = Vulkan 直连），由设置页 MobileGlues 分区独占读写——用户明令"不写什么后端"。
- **解析**（单一事实源 ame_effective_renderer，"mg" 逻辑键不外泄）：mg 分支 → ame142_effective_backend_key（新键 → legacy 全局家族键 → legacy 档位 → 默认 Vulkan）→ dylib 守卫（缺失回落默认后端→auto，一次性 NMToast 显示后端真名）；legacy 直写家族键仍原样生效（Task132-140 兼容 + Task138 守卫）；JavaLauncher/egl_bridge/layerClass/FSR 消费的仍是解析后的家族物理键——零下游行为变化。
- **迁移 ame142_migrateRendererStorage**（幂等 static 哨兵；ame_effective_renderer/设置页/实例页读前触达）：全局家族键 → 后端键 + video.renderer="mg"；各 profile 家族键 → "mg"（活字典原地改写 + 单次 save）；同时退役 legacy 档位键（显式改选 = Task132 承诺的 legacy 终点，也防 JavaLauncher 档位分支与新键矛盾）。

### UI
- **实例页（ProfileSettingsViewController）**："跟随全局渲染器" 外置 UISwitch 行（渲染器行上方）；开 = 删 profile 键 + 渲染器整行置灰（tertiary 三色 + 无箭头 + 点击不弹窗，值位显示全局默认显示名）；关 = 启用精简选择器（经典列表 + 唯一 mg 项），关闭时默认给 "mg"；点行可拨开关（accessoryView 在 cell.subviews 而非 contentView）；legacy 家族键 ✓ 归一到 mg；popover 锚点移至 row 1。cell 复用复位补 detailTextLabel.textColor（防灰值外泄）。
- **设置页**：MobileGlues renderer_backend 行只读写自己的键（Task132-140 直写渲染器键——两层互相伪装正是"选了后端、渲染器行跟着变"的困惑源）；显式改选同时清零 legacy 档位；dylib 缺失即时提示保留。
- **审核修复**（"最后再审核一下"命中）：设置页渲染器行 getPreference 改回返回【存储键】——Task140 返回本地化显示名，openPicker 的 ✓ 按 pickKeys 精确比较存储值，auto/gl4es 等经典值 ✓ 永远丢失（隐性回归）；typePickField ame132 分支本就支持存储键→标签映射，两头皆对（含 "mg"）。

### l10n（+3/-1 ×4 语言，基线 1922→1924）
- 新增：renderer_follow_global_toggle（跟随全局渲染器/跟隨全域渲染器/Follow Global Renderer）、renderer.debug.mgfamily="mg"、mg_backend_missing_dylib（后端 dylib 缺失回落提示）。
- 退役：preference.profile.renderer_follow_global（旧选择器格式键"跟随全局设置（当前: %@）"）。
- 重写：preference.detail.renderer_backend（mg 后端语义：渲染器选 mg 时按此启动，默认 Vulkan 直连）。

### 发布资产
- announcements.json v6.0.0：summary 加"mg 单入口"；渲染器弹点重写（开关+置灰+精简列表+唯一 mg+后端归 MobileGlues 设置）；删除 Task139 时代"设置页的选择现在与实例配置同步写入"陈旧弹点（与新分层矛盾）；英文尾段重写。
- README/README_CN 渲染器行、version.h REVISION 17 addendum（Task 142, no bump）。
- 注意：v6.0.0-release-notes.md 是工作区工件（不在 git），发布时需从 announcements.json 重新导出（verify_task140 F7 已改为缺失跳过）。

### 校验
- **verify_task142 新增 49 项全绿**（A 核心模型 13 / B 设置页 6 / C 实例页 12 / D l10n 5 / E 发布资产 7 / F 下游单一事实源 6）。
- 重锚：verify_task140（C6/C7/C8/C12/C13/C14/E → 58/58）、task132（B6/B7/B11/F1）、task139（E2/E3/I2）、task129/130/131/133/134/135/138 计数基线 1922→1924（rebase 合并双方）。
- **级联全绿对照**（本沙箱）：141(their)=35/35、140=58/58、138=52/52、137=46/46、142=49/49；129-135/139 剩余失败全部为环境性（另一会话沙箱的会话本地脚本 task116_l10n_audit.py / task132_jna_got_mirror.py / task139_syntax_gate.py 及其级联，与基线一致，零新增）。
- 括号平衡：五个改动 ObjC 文件 + 合并波及的 JavaLauncher/SurfaceViewController 全部平衡。
- rebase 冲突（7 个验证器计数销）以 1924 统一解决；双方 ObjC 改动（其 Task141 字号缩放/内存弹窗 vs 本轮开关/置灰）自动合并无重叠，逐一目检。

### Stage Summary
- 提交 1c23bab（rebase 于另一会话 649609f 之上），CI 已触发。
- 装机待验证锚点：①实例页"跟随全局渲染器"开关行，开启时渲染器行置灰、值显示全局默认；②渲染器选择器仅"mg / 自动 / 经典项"（无三后端、无跟随全局）；③设置页 MobileGlues 渲染后端行独立变化，渲染器行不再跟着变；④✓ 标记在设置页渲染器行正确显示（含 auto/gl4es/zink——Task140 起丢失，本轮修复）；⑤旧设备首启日志 '[Amethyst] Task142: global renderer <family> migrated to 'mg''；⑥后端行改选日志 '[PLPrefTable] Task142: renderer_backend written to OWN KEY'；⑦渲染器选 mg + 后端选 GLES/OpenGL4.0 启动，日志 RENDERER is set to 对应家族 dylib。

---

## 附：追加区
新任务记录直接追加在本文件**最末尾**（保持上面速览表的「当前状态/最新 Task 号」同步更新）。本文件增长到 ~400 行时，把最旧的任务段剪切进 worklog-archive.md 归档。

## 会话记录（2026-09-22，worklog 瘦身重构，未占用 Task 编号）
- 动机：worklog.md 膨胀至 2327 行，每次会话入场要消化全量历史，效率低
- 动作：① 速览节置顶（状态表/双会话协作规则/关键命令/方法论/检索指引）；② Tasks 34-140 原文归档 worklog-archive.md（2257 行）；③ Task 141/142 原文保留本文件
- 配套重锚：9 个验证器的 worklog 内容检查改为兼容 worklog-archive.md（92/93/96/97/98/101/102/111/119_124，python 定点替换）
- 验证：96/98/111/119_124 本地全绿；92/93/101/102 的条目在重构前即缺失（历史丢失，非本次回归，且不在 CI 集内）
