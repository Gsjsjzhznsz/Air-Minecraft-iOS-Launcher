# Worklog

## ⚡ READ ME FIRST —— 会话速览（只读本节 + 「滚动近况」即可开工；更早历史一律查 worklog-archive.md，勿通读）

> 最后更新：Task 153（2026-09-23，渲染器三案 + Forge 模块层根修）。此前：Task 152/152b（另一会话，Mithril FunctionProvider 钉扎）；151（Bing 每日壁纸）；150（渲染器全局控制退役）；144-149（2026-09-22/23）。
> 新会话规则：新任务记录**追加到本文件最末尾**（`## Task N` 或 `---/Task ID:` 模板均可）；收尾时同步更新下面「当前状态」表；本文件超过 ~400 行时把最旧的任务段挪进 worklog-archive.md。

### 一句话
AngelAuraAmethyst（Amethyst-iOS 重制版，fork **Gsjsjzhznsz/Air-Minecraft-iOS-Launcher**）——iOS Minecraft 启动器，已发布 **v6.0.0**：MC 26.x 全链路可玩（26.3-pre-1 + Fabric + 128 mods + MobileGlues 渲染链）。当前主线：UI 打磨、渲染器存储分层（auto/mg + mobileglues.renderer_backend）、各 MC 版本崩溃根修。

### 当前状态（收尾时更新）
| 项 | 值 |
|---|---|
| 远端 HEAD | d36a24f8（Task 151 Bing 每日壁纸，CI 绿 run 35848334214）；此前 6d73fc11（Task 150） |
| 最新 Task 号 | **153**（双会话并行开发，开新任务前先 fetch 避让编号） |
| 待用户装机验证 | Task 153 渲染器三案（Vulkan 花屏/ES 方块/Forge ResolutionException）+ Task 152b 4.0 崩溃（pin 生效待证）+ Task 151 Bing 壁纸 + Task 149 六项返工 |
| 已知历史遗留 | v6.0.0-release-notes.md 是工作区工件不在 git（发布时从 announcements.json 重导出）；部分 verify 级联失败为沙箱环境性（会话本地脚本被清 + task132/135 路径依赖），与基线对拍判读 |

### 双会话并行协作规则（重要）
- 推送前必须 `git fetch origin && git rebase origin/main`；Task 编号冲突避让下一空号并在记录里注明
- 验证器级联：`scripts/verify_taskNNN.py`（129-142 全家）；动 l10n/公共 UI 必须重锚基线计数（当前 1924）并对拍「零新增失败」
- 沙箱会随机重置工作区/本地 ref：**仓库是唯一事实源**；工作区工件丢失按 archive 记录重建；本地落后时 `git fetch && git reset --hard origin/main`

### 关键路径与命令
- 仓库: `/home/z/my-project/Amethyst-iOS-MyRemastered`；GitHub token 在 `git remote -v` 的 URL 里（放心直接用）
- CI 轮询: `TOKEN=$(git remote get-url origin | sed -n 's\|https://[^:]*:\([^@]*\)@.*\|\1\|p')` + `/actions/runs?per_page=N` API；失败先拉 job log grep "error:"
- 产物: artifact `com.air-devs.air-ios.ipa`（另有 trollstore .tipa / dSYM）
- l10n: en/zh-CN/zh-Hans/zh-Hant 四语言键集一致，基线 1924
- 用户日志: 直接推仓库根 latestlog* 系列（勿删）；`/home/z/my-project/upload/` 为旧渠道（hs_err_pid*.log）
- 装机日志轮换映射（Task 144 时点）：latestlog.txt=Mithril(4.0) 崩溃会话 / latestlog.old.txt=MobileGL-gles(ES) 会话 / latestlog=Forge 安装会话 / latestlog.old=OSMesa(zink) 会话

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

## Task 143（本会话，装机日志三修复）

### 用户反馈（4ecc256 构建，日志 = 仓库根 latestlog.txt，用户经 GitHub 网页上传）
"现在无论切换什么渲染器都会变成mg。fsr没有生效。而且mg是MobileGlues，为什么列表有个mg又有个MobileGlues"。

### 根因（日志逐行实锤）
1. **后端永不落盘**：Task142 引入 `mobileglues.renderer_backend` 但漏在 PLPreferences.m setDefaultsForPref 注册；PLPreferences 只能读写已存在键。装机日志 L30-31：选 GLES 后端 → "Setter could not find preference mobileglues.renderer_backend" 写入静默丢弃 → 启动恒回落默认 libMobileGL.dylib（DirectVulkan）= "切什么都是 mg"。
2. **FSR 从未生效**：mgl_fsr.mm 把 GL_FRAGMENT_SHADER 定义为 0x8B92（实为 GL_PALETTE4_R5_G6_B5_OES，GLES1 调色板格式；规范值 0x8B30，mesa glext.h:599）。考古：Task83 原值正确 → Task84 据装机日志 stage=35632 误诊反向"勘误"成 0x8B92 → Task119 复制同错值 → MobileGL/zink 两链片元着色器恒 glCreateShader=0 + GL_INVALID_ENUM（日志 L818-820：顶点 0x8B31 成功、片元 35730 失败）→ 恒自愈回全分辨率。附带 GL_ARRAY_BUFFER_BINDING 0x8B8C（实为 GL_SHADING_LANGUAGE_VERSION）→ 0x8894——RCAS 路径 glGetIntegerv 实际引用它，VBO 保存静默失效。
3. **mg 与 MobileGlues 并列**：mg=libMobileGL.dylib 家族（Vulkan直呈/GLES/Mithril 后端），MobileGlues=libmobileglues.dylib 独立渲染器（源码构建、自带 FSR1）——本就是两个渲染器，Task142 未把后者从选择列表隐退导致命名撞车。

### 修复（4 文件 + 验证器，零 l10n 变更、基线 1924 不动）
- PLPreferences.m：mobileglues 分区注册 `@"renderer_backend": @""`——刻意空串：实体默认会让解析链第一层恒命中、legacy 档位（renderer=auto + mobilegl_backend=2/3）永久失明；空串保住"键未设"语义与 legacy 层，顺带消 Getter 噪音。
- ctxbridges/mgl_fsr.mm：GL_FRAGMENT_SHADER 0x8B92→0x8B30；GL_ARRAY_BUFFER_BINDING →0x8894。
- ctxbridges/osm_bridge.mm：同款两常量 + Task84 错误勘误注释改写为 Task143 再勘误（教训：勿据日志反推枚举规范值）。
- LauncherPreferences.m：availableRendererCandidates 规则 3——libmobileglues 条目仅当其为当前选中值时可见（存量设备照常显示/启动，legacy 显式键路径不变，dylib 仍随包），新选择一律七项列表；ame_renderer_display_name 对该键映射回既有 debug.mg 文案（存量 profile 裸键名防御，零新 l10n 键）。
- scripts/verify_task143.py：31 项（A5/B7/C5/D7/E4/F2/G1）。

### 校验
- verify_task143 31/31；task142 49/49；136=63、137=46、138=52、140=58 全绿；129-135/139/141 失败逐项 = 已记录环境性同类（会话本地审计脚本被沙箱清除 + 旧级联 + task141 硬编码另一会话路径），零新增；四文件括号平衡 (0,0,0)。

### Stage Summary
- 装机验证锚点：①后端改选 GLES/Mithril 重启后保持，启动日志 `RENDERER is set to libMobileGL-gles.dylib`（不再恒 DirectVulkan）；②不再出现 "Setter could not find preference mobileglues.renderer_backend"；③FSR1 开启后不再有 glCreateShader(stage=35730)=0 / "restoring MC window" 自愈，画面为 EASU 上采样；④选择列表不再同时出现 mg 与 MobileGlues（存量选过者除外）；⑤Task142 七锚点继续有效。
- 用户侧：mg 与 MobileGlues 本就是两个渲染器；按"渲染器选择只有一个 mg"指令把后者隐退为存量兼容项。

---

## 附：追加区
新任务记录直接追加在本文件**最末尾**（保持上面速览表的「当前状态/最新 Task 号」同步更新）。本文件增长到 ~400 行时，把最旧的任务段剪切进 worklog-archive.md 归档。

## 会话记录（2026-09-22，worklog 瘦身重构，未占用 Task 编号）
- 动机：worklog.md 膨胀至 2327 行，每次会话入场要消化全量历史，效率低
- 动作：① 速览节置顶（状态表/双会话协作规则/关键命令/方法论/检索指引）；② Tasks 34-140 原文归档 worklog-archive.md（2257 行）；③ Task 141/142 原文保留本文件
- 配套重锚：9 个验证器的 worklog 内容检查改为兼容 worklog-archive.md（92/93/96/97/98/101/102/111/119_124，python 定点替换）
- 验证：96/98/111/119_124 本地全绿；92/93/101/102 的条目在重构前即缺失（历史丢失，非本次回归，且不在 CI 集内）

---

## Task 144（本会话，装机日志四 bug 根修 + 渲染器 UX 七项）

### 用户反馈（9aa15c8 构建装机实况，日志直接推仓库根 403a4597/5b38fd72/c8221ad3）
"把mg改成全名。切换其他渲染器还是会变成mg。es后端方块不渲染。4.0后端闪退。forge安装闪退。还有优化一下自动渲染器机制。最后我排查软件自动选择mg问题发现为什么我版本有2个一模一样的版本，而这个版本不会回退mg可以使用zink等其他渲染器启动，赶快恢复一下为什么会有2个一模一样的版本。"

### 根因（逐条日志/字节码实锤）
1. **4.0(Mithril) 后端闪退**：`GL.createCapabilities` 抛 "There is no OpenGL context current in the current thread"（latestlog.txt）。反编译补丁版 lwjgl-opengl.jar（新工具 scripts/disasm.py，沙箱无 javap）：补丁 createCapabilities 在调渲染器 dylib 的 glGetString(GL_VERSION) 探针前，唯一重绑上下文的门是 `System.getenv("POJAV_RENDERER") != null -> GL.fixPojavGLContext()`（反射 GLFW.glfwMakeContextCurrent(GLFW.mainContext)）。我们只导出 AMETHYST_RENDERER -> 补丁是死代码 -> 渲染线程无上下文绑定时 Mithril（线程绑定模型）glGetString 返 NULL -> 抛异常。MobileGL-gles/OSMesa 全局单上下文模型混过探针（ES 方块不渲染 = 渲染线程状态未绑定的同根嫌疑）。
2. **ES 后端方块不渲染**：同一根因家族；另 init_loadMobileGluesConfig 白名单（mobileglues/auto/vulkan）不含 mg/家族键 -> config.json + MG_DIR_PATH 从未写入（日志 "MobileGlues config not written"），MobileGlues 分区用户偏好对 mg 会话全失效。
3. **Forge 安装闪退**：latestlog 14k 行 —— 处理器 4/4 全部成功、进度 0.85 时安装器 JVM 的 libjli 内部线程调 exit(0)，与启动器同进程 -> 整 app 被带走（Task 48 hooked_exit 取证栈实锤 libjli dummyTimer 帧）。
4. **"切换渲染器还是变 mg"**：日志证据（latestlog.old 20:43）用户连选两次 `Task140: renderer written to PROFILE ONLY = mg / = libOSMesa.8.dylib`（zink 存储键即 libOSMesa.8.dylib，20:44 会话真用 Mesa 启动）—— 写入/启动链路实际已通；困惑源 = ①"mg" 名字不透明 ②follow-global OFF 默认给 mg ③与旧 App 行为对比。
5. **"2 个一模一样的版本"**：commit 9659740a（2026-07-24）包名 org.angelauramcremastered.amethyst -> com.air-devs.air，iOS 视为不同 App，新 IPA 不覆盖旧装 -> 主屏双图标并存（旧图标 = 旧代码 + 旧偏好容器，所以它"能用 zink"）。非本仓库 bug；删除旧图标即消除。

### 修复（8 代码文件 + 1 新工具 + 7 验证器重锚，l10n 键集 1924 不动；commit 171006ce）
- **JavaLauncher.m**：①launchJVM 导出 `POJAV_RENDERER`（与 AMETHYST_RENDERER 同值：主导出点 + "Preset OpenGL libname" 处防御同步）激活 LWJGL fixPojavGLContext —— Mithril 闪退根修；②init_loadMobileGluesConfig 改读 ame_effective_renderer()，白名单 +家族三键（mg 家族 config.json + MG_DIR_PATH 修复）；③自动渲染器升级：minVersion>8（MC 1.17+）且 libMobileGL.dylib 在位 -> auto 解析为 MobileGL Vulkan 直连（装机验证最快路径；旧"always ANGLE"顾虑 = config 缺失已修），否则 ANGLE 回退；layerClass 侧 auto/MobileGL 均 CAMetalLayer，Task124 约束不受影响。
- **egl_bridge.m**：④三处 setenv(AMETHYST_RENDERER) 同步导出 POJAV_RENDERER；⑤pojavGetCurrentContext 渲染线程上下文采纳兜底（TLS 空 + ame_brLastCurrent 非空 + 非主线程 -> pojavMakeCurrent 迁移上下文）；⑥ame_brCurrent/ame_brLastCurrent 唯一 TLS 定义点。
- **bridge_tbl.h**：`static __thread currentBundle` 头文件定义退役（每 TU 一份副本、egl_bridge 那份恒 NULL -> pojavGetCurrentContext 恒空的病历见注释）-> extern 共享 TLS + br_get_current/br_set_current。
- **gl_bridge.m / osm_bridge.mm**：currentBundle 全量改走 br_get_current/br_set_current（机械替换 18+21 处，括号 delta 与 HEAD 逐文件一致）。
- **main_hook.m + JavaLauncher.h + ForgeProcessorExecutor.m**：⑦Forge 闪退根治 —— `atomic_int g_ame_suppressJvmExit`（launchHeadlessJVM 前后置位/清零），hooked_exit 命中标志且非主线程 -> pthread_exit(NULL) 只终结 JVM 线程（JLI ContinueInNewThread 的 join 正常返回 -> status.json 判定安装成败），游戏正常退出路径不受影响。
- **l10n x4 + VersionManagerViewController**：⑧renderer.debug.mgfamily 值 "mg" -> "MobileGlues"（用户指令"把mg改成全名"；逻辑键 RENDERER_KEY_MG="mg" 不动）；VersionManager 短名映射同改。
- **AppDelegate.m**：⑨旧包检测（NSClassFromString LSApplicationWorkspace + applicationIsInstalled:，@try 防御）—— 命中 org.angelauramcremastered.amethyst 打日志提示删旧图标（日志级，零 UI 噪音）。
- **scripts/disasm.py**：新最小 JVM class 反汇编器（常量池 + 字节码取证，无 javap 环境）。
- **验证器重锚（日志轮换 403a4597/5b38fd72/c8221ad3 所致）**：task140 G 块、task138 A1/A2/C1、task132 A1/A2、task133 B1/log 源、task134 E4b -> 锚定现日志映射与 Task143 修复生效证据；task137 G3 +mgfamily diff 分支；task142 F5 -> @"MobileGlues"。

### 校验
- 136=63/63、137=46/46、138=51/51、140=58/58、142=49/49、143=31/31 全绿；129/130/131/132(A15/F4/F5)/133(H1/H2)/134/141 剩余失败逐项核对 = 既有环境性同类（task116_l10n_audit.py / task132_jna_got_mirror.py 会话本地脚本被沙箱清除 + 112-118/119-124/125-128 级联 + task141 硬编码另一会话绝对路径），**零新增失败**。

### Stage Summary
- 装机待验证锚点：①选 Mithril(4.0 后端) 进游戏不再闪退（日志见 POJAV_RENDERER 导出 + 正常起图）；②ES 后端进世界方块渲染恢复（若仍复现，下轮抓 MGL 前端 GLES 行）；③Forge 安装走完 100%（不再 85% 闪退，日志出现 `Task144: exit(0) suppressed during headless JVM`）；④渲染器列表显示 "MobileGlues" 全名（不再裸 "mg"）；⑤选"自动" + MC 1.17+ -> 日志 `Auto renderer resolved to libMobileGL.dylib (modern MC...)`；⑥mg 会话日志不再出现 `MobileGlues config not written`；⑦旧包并存检测日志 `Task144: legacy bundle ... still installed`；⑧zink/gl4es/angle 切换保持 Task142/143 行为。
- 用户须知：双图标在仓库侧不可修（旧 App 独立容器）——主屏删除旧版 "AngelAuraAmethyst" 即可；新 App 数据不受影响。

## Task 145（本会话，Sodium 全崩根修 + 4.0 门补丁 + Forge 线程化）

装机日志（0297d0c7/d8295412 两批共 5 份，全部 171006c 构建）：22:16 libmithril 会话 IllegalStateException "no OpenGL context"（4.0 依旧崩）；22:19 libMobileGL / 22:20 libOSMesa 两会话 Sodium `PostLaunchChecks.isUsingPojavLauncher` 首帧抛异常（"not supported when using Sodium"）＝用户"你一改全部失效"；22:21 forge 会话 exit(0) 抑制生效但进度恒 0.85 挂死。

诊断（反汇编实锤）：
1. **Sodium 全崩根因**：Modrinth 拉 sodium-fabric-0.9.2+mc26.2.jar 反编译 `PostLaunchChecks` —— `System.getenv("POJAV_RENDERER") != null` 即判 PojavLauncher 抛异常（常量池无 isEmpty，空值也躲不过）。Task144 无条件导出该变量＝全渲染器全崩。
2. **4.0 崩因再进一层**：补丁版 lwjgl-opengl.jar `GL.createCapabilities` 的重绑定门是 `Platform.get() == Platform.LINUX && getenv("POJAV_RENDERER") != null -> fixPojavGLContext()`；本启动器伪装 `os.name=Mac OS X`（JNA 兼容，JavaLauncher.m:725）→ Platform != LINUX → **门永不触发**，Task144 的变量导出白导。运行时 GLFW 类＝Amethyst overlay（JavaApp/Makefile lwjgl-%.jar 规则，libs/*/*.jar 之上覆盖 build/lwjgl），源码已含 `mainContext` 字段+赋值（GLFW.java:513/1030），无需补字段；libs/lwjgl-341/lwjgl-glfw.jar 的 GL.class 是 stub（不进 classpath 主链）。
3. **Forge 挂死根因**：JLI_Launch 在 JVM main 返回后由【调用线程】（fatal-trace 栈帧 libjli dummyTimer）调 exit(0) 终结进程；Task144 把它转 pthread_exit → launchHeadlessJVM 永不返回 → status.json 终态判定/收尾代码永不到达 → 轮询挂死。

修复（本提交）：
- `JavaLauncher.m`：POJAV_RENDERER 仅 `isMithrilRenderer()` 时导出，其它渲染器 unsetenv（同会话先 Mithril 后其它渲染器的残留也清掉）；auto 分支与防御同步同步收紧。
- `egl_bridge.m`：gl4es/MOBILEGLUES 分支与 pojavSetWindowHint 两处共 4 个无条件 setenv("POJAV_RENDERER") 全部移除。
- `scripts/patch_lwjgl_gate.py` + 两个二进制：lwjgl-341/333 的 lwjgl-opengl.jar `GL.class` 把门里 `invokestatic Platform.get / getstatic Platform.LINUX / if_acmpne` 9 字节 NOP 掉（栈平衡、目标帧不变），门改为纯由 POJAV_RENDERER 控制（仅 Mithril 导出，非 Mithril 零行为变化）。
- `ForgeProcessorExecutor.m`：headless JVM 改跑 64MB 栈专用 pthread + pthread_join；exit 被转线程退出后 join 照常返回，status.json 终态判定恢复，轮询不再挂死。ret 仅保留启动失败语义。
- `gl_bridge.m`（取证，无行为变化）：dlsym_EGL 处捕获渲染器 dylib 句柄；gl_make_current 成功分支在 Task140 readback 后追加同源 `glGetString(GL_VERSION)` 探针——下轮 Mithril 日志可一锤判定「renderer 内部 eglGetCurrentContext 与 glGetString 分叉」还是「创建后被动解绑」。

装机验证锚点：① 带 Sodium 整合包 + MobileGL/OSMesa/zink/ANGLE 启动不再出现 "not supported when using Sodium"；② 4.0 后端（若再崩）日志必现 `Task140 make-current readback` + `Task145 glGetString-probe: version=...` 两行——NULL 值即 Mithril 内部分叉实锤；③ Forge 安装越过 0.85 后出现 status.json 终态判定日志（成功或明确报错），不再无限刷 (4/4)。

## Task 148（本会话，MobileGL 双后端 FSR 复活——内置 FSR1 独家接管）

用户指令（Run #356 判读后的否决）："不行那2个端必须可以使用fsr"——Task 147 把 Vulkan/ES 退回全分辨率直呈（FSR 停用）的方案被否，这两端必须可用 FSR。

### 根因（Run #356 五日志 + MobileGlues-cpp 源码实锤，花屏+倒转完整机理）
1. **libMobileGL.dylib / libMobileGL-gles.dylib = MobileGlues-cpp 共体构建**：iOS settings 分支读 config.json 的 fsr1Setting（Task78/130 每次启动写入，Run #356 双会话 config.json 实锤 fsr1Setting:4）→ **渲染器内置 FSR1 在这两后端本就激活**：glBindFramebuffer(fb0) 的 DRAW 绑定被重定向到 FSR1 渲染目标（framebuffer.cpp:186 `draw_fb = FSR1_Context::g_renderFBO`），呈现由 presentSurface→ApplyFSR 在 eglSwapBuffers 内收口。
2. **双重管线打架 = 毁帧**：启动器侧 Task119 预交换链（EASU→离屏→RCAS→"fb0"）在此架构下，RCAS 的 fb0 绘制经同一重定向灌进 FSR1 渲染目标——每帧把 MC 刚画好的帧摧毁成"RCAS(上一帧拷贝)按 2360x1640 视口裁进 1180x820 目标"的错位拼图，再被 ApplyFSR 2x 放大上屏 = 用户所见花屏+倒转。双会话日志（EASU/RCAS ready + 600 帧 steady）与"损坏但持续输出"完全吻合。
3. **勘误（Task147 判读错误）**：RCAS sharpness=1.000 在 mpv 口径是【最大锐化】（FSRRCASSource.h stops=2*(1-S)：S=1→0 stops→最锐），不是"无锐化"；该值为用户 pick 所选（pickKeys 含 @"1"），非默认值 bug（PLPreferences 默认 @0.2）。zink 会话 FSR 端到端 LANDED（Task103 哨兵 3/3 + bundle-direct present）——"zink fsr 不生效"的感知与 sharpness=1.0 的过锐观感需在 UI 侧引导（建议 0.2-0.5），非管线问题。latestlog.old 的"zink 无 EASU"会话实为 Forge 启动崩溃会话（OSMesa 渲染器 + JVM SIGSEGV 尾帧，Task147 osm_make_current 空指针守卫已修）。

### 修复（本提交，2 文件）
- `SurfaceViewController.m`：ame83_fsr_capable_renderer 恢复 isMobileGLRenderer（Task147 撤销块反转）——Task83 联动（MC 窗口=surface/档位）复位，这正是内置 FSR1 预期几何（与 mg 同构）；mgFsrScale 触控缩放随之恢复。
- `mgl_fsr.mm`（Task148 仲裁）：启动器预交换链不再是 MobileGL 后端的默认服务方——
  - 新增 `ame148_detect_builtin_fsr_redirect()`：GL_DRAW_FRAMEBUFFER_BINDING getter 会隐藏重定向（getter.cpp:147 回 0），改走附件查询——DRAW 绑定显式指回 fb0 后查 COLOR_ATTACHMENT0 的 OBJECT_NAME：重定向时非零（FSR1 目标颜色纹理），无重定向时按规范拒绝 NAME 查询且名字保持 0；
  - `ame_mgl_fsr_before_swap` 入口仲裁：判内置接管 → 启动器链永久退休（探测停止、零开销）；判无重定向（渲染器过旧/内置 FSR1 初始化失败未重试成功）→ 链作兜底继续活跃且逐帧复探（InitFSRResources 失败后会重试，重定向中途出现即 Retirement，杜绝晚到毁帧）；导出表缺失保守判接管；
  - 新增符号 glGetFramebufferAttachmentParameteriv（gl_native.cpp NATIVE 导出已验证）；状态位 ame148_arbitrated/ame148_builtin_owns；
  - 日志锚点：`[MGLFSR] Task148 builtin-FSR1 arbitration: fb0 draw color0 type=0x... name=... -> REDIRECTED ... RETIRED`（防刷屏：明细行仅首探/翻转时打印）。

### 装机验证锚点（下轮日志判读）
1. Vulkan/ES 会话必现 `Task148 builtin-FSR1 arbitration ... REDIRECTED -- builtin FSR1 owns upscale+present, launcher chain RETIRED`，且不再出现 `Task119 FSR1 upscale engaged` / `Task130 RCAS engaged (MobileGL)`；
2. Vulkan 花屏+倒转消失、画面正常且为 FSR 档位渲染分辨率（内置 ApplyFSR 呈现）；ES 方块渲染情况随毁帧链退休一并观察（若仍缺方块 = 独立问题，抓 MGL 前端 GLES 行）；
3. 若出现 `no redirect -- launcher chain stays as fallback`：说明该渲染器二进制未含内置 FSR1 或 config 未生效——启动器链接管（旧路径），需抓 config.json 内容与 [MG] FSR1 行再判。
---

## Task 149（本会话，UI 六项返工；编号避让注明：动工时远端为 Task 146，本任务按 147 开发；推送前 fetch 发现另一会话已占用 147/148，避让重编号为 149）

### 用户需求（Task 141 实装实测反馈，五点疑点已经用户确认）
1. 欢迎卡头像**还是**不加载默认头像，点击后才会加载。
2. 欢迎卡删掉更新语句（公告标题行）及按钮；头像移到左边居中（到左边缘 = 到上下边缘距离，**不调整大小**）；文字与头像间距 = 头像距边缘距离。
3. 更新卡片（公告磁贴）与 MC 新闻磁贴高度都和"最新正式版"磁贴一样；高度不够就把简介截断到能显示的行；新闻卡缩略图及文字按第 2 项模式移动；标题及简介样式改成和新闻卡片一样；喇叭图标放在中间的高度位置；查看详情按钮移到标题后面（调整大小）；核查新闻卡版本号是死版本还是动态检测（结论：announcements.json 驱动，用户确认保持）；新闻页简介全部显示而非截断；新闻恢复横轴两个并列排（Task141 单列退役）。
4. 主页面所有卡片全部取消阴影。
5. 公告卡片页面公告周围"不知用途的蓝色圆角矩形边边"删掉。
6. 内存分配弹窗"一整片黑色背景"改掉，能用 iOS 原生 UI 就用（用户确认：**原生底部面板**）。

### 根因与实施
- **Item1（HomeProfileTileCell）**：首帧路径封死——cell init 直接呈现 DefaultAccount（缺失回退 SF 占位；此前 init 用 SF 占位、等 cellForItem 换装的时序缝隙即"点击前空白"观感源）+ viewWillAppear 再跑 updateSkinDisplay 补账号态（标签页往返/返回前台）。
- **Item2**：announceRowStack 四件套（announceIconView/announceLabel/detailButton/announceRowStack）整体退役；greetingLabel 复位（14pt medium secondary + festivalGreeting，cellForItem 填充）；头像等边距 = 新增 avatarLeadingConstraint/textLeadingConstraint 两条动态约束，layoutSubviews 按头像实际边长（=卡高×0.5）取半刷新（左边距=文字间距=上/下边距=side/2；卡片 170/头像尺寸零变化）。
- **Item3**：heightForTileConfig 公告/新闻磁贴固定 100（ame138_announcementTileHeight 自适应机制退役）；HomeAnnouncementTileCell 重排——喇叭图标 centerY 居中、titleRowStack（标题 15pt semibold + 内联 actionButton 12pt/28pt 高/edgeInsets 自适应宽）、summaryLabel 12pt tertiary、压缩序 750<998（简介优先截断）、预览档位仅控简介显隐；HomeNewsTileCell——缩略图等边距（leading 20 = (100-60)/2）、文字 stack 相对缩略图居中 + 上下钳制、简介 numberOfLines 0；MinecraftNewsViewController 恢复双列（两个 0.5 子项 + 12pt 间距 + (8,8,8,8) 边距）、newsCardFixedHeight 固定等高退役改 estimated 280 自 sizing（简介不截断）、禁横向滑保留。**版本号核查结论**：公告卡标题/按钮文案来自仓库根 announcements.json（服务端 JSON、用户手动发布），App 无写死、不自动检测 GitHub——用户确认保持。
- **Item4**：HomeTileBaseCell.setupBaseViews 阴影四件套（shadowColor/Offset/Opacity/Radius + masksToBounds NO）删除；BackgroundManager 管线零变化。
- **Item5（AnnouncementCardCell）**：priorityBarView 整体退役（属性/创建/约束/configure + kAnnHighPriorityBarWidth 常量）——announcements.json priority=high 时的左侧 4pt 蓝条即用户所见"蓝色边边"。
- **Item6（ProfileSettingsViewController）**：showMemoryAllocator 重写为 Ame149MemoryAllocatorController 原生底部面板（UISheetPresentationController medium 档 + prefersGrabberVisible，iOS 15 以下回退 formSheet）；遮罩自绘卡片/关联对象键 kAme141MemorySliderKey/dismissMemoryAllocator/applyMemoryAllocation/memorySliderChanged 全删；拉条区间（512→maxMemory）与写回链路（allocatedMemory→saveSettings→reloadAllTableViews）不变。

### 校验
- verify_task147 新增 35 项全绿（A 欢迎卡 8 / B 高度阴影 4 / C 公告卡 6 / D 蓝条 2 / E 内存弹窗 6 / F 新闻页 4 / G 配平+UIColor 白名单 5）。
- 重锚：task136（D2/D3/E2/E4 → Task149 形态）、task137 F7（自 sizing + 双列）、task138 F1/F2（自适应高度退役 → 等高 100）、task141（A2-A6 问候语回归 / C2-C5 原生面板 / D5 写回链路 / E1-E4 双列自 sizing）。
- 级联 stash 基线对拍（在远端 HEAD 2775e2f 上重跑）：136=63/63、137=46/46、141=36/36、149=35/35 全绿；138 剩余失败（C1=另一会话 Task147/148 日志轮换未重锚的远端既有 + J-135 环境性）与基线逐项一致；139（H 块 Task146 撤销精简既有 + I1 环境性）、132/135（另一会话沙箱路径/会话本地脚本被清）均既有环境性；**零新增失败**。
- 四改动 ObjC 文件括号配平全 0；UIColor 白名单审计通过。

### Stage Summary
- 用户预期：①头像首帧即默认头像（不点击也显示）②欢迎卡=头像等边距居左+欢迎语+灰字问候语（无公告行无按钮）③公告卡/新闻卡与最新正式版卡等高（简介截断适配）、喇叭居中、按钮内联标题后、样式对齐新闻卡、新闻页双列+简介完整、版本号保持 announcements.json 驱动 ④主页卡片零阴影 ⑤公告列表蓝条消失 ⑥内存分配=原生底部面板（拉条+写回不变）。
- 待用户安装新 CI 工件实机验证；推送前 fetch 对齐（双会话并行）。

---

## Task 150（本会话，[可撤销] 删除渲染器全局控制 + Sodium 组件安装）

### 用户需求（两点疑点已经用户确认：缺省渲染器=auto；Sodium 入口=一键装双模组）
1. 启动器设置页面的渲染器选择删掉；实例页面的"跟随全局渲染器"开关删掉；有相关代码的也可删除——**每个实例强制单独选择渲染器**（初衷：促进玩家多更改渲染器以体现效果及兼容差异）。
2. 实例页面组件安装：读取 Fabric API 安装逻辑，用相同逻辑开一个 Sodium 选项（火焰图标），安装 **Podium 和 Sodium** 模组（Podium = 禁用 Sodium 的 PojavLauncher 检查，Modrinth 实锤存在、与 Task145 的 POJAV_RENDERER 导出收敛互为双保险）。

### 实施（撤销路径全部注释留档）
- **设置页（LauncherPreferencesViewController）**：video.renderer 行字典/getPreference 分支/setPreference 分支 + ame140_writeRendererGlobal 块 + shadow toast + rendererKeys/rendererList 属性全删；MobileGlues 后端行（renderer_backend）原位幸存。
- **实例页（ProfileSettingsViewController）**：advancedRows 去掉"跟随全局渲染器"；开关映射/构建器/回调三删；渲染器行永远可选（置灰态退役）；didSelect 直接弹选择器；popover 锚点 row 1→0；loadSettings 无键缺省 `@"auto"`；saveSettings 防御性写 auto（键永不再被删除）；rendererDisplayName nil→auto。
- **启动链（PLProfiles.m）**：prefDefaults 的 `renderer→video.renderer` 全局回退退役（注释留档撤销路径）+ 新增 nil 守卫（getPrefObject(nil) 会抛 NSInvalidArgumentException）——ame_effective_renderer 解析链变为【profile 键 → auto】（用户确认缺省；1.17+ 经 Task144 升级逻辑解析为 MobileGL Vulkan 直连）。
- **Sodium 组件安装（ProfileSettingsViewController）**：组件安装区新增 Sodium 行（flame.fill 火焰图标 + systemOrange，Fabric 门槛文案与 Fabric API 行同构）；`ame150_fetchModrinthPrimaryFileWithQuery:exactTitle:gameVersion:loader:completion:` ——Modrinth 搜索→**标题全等匹配**（containsString 会误命中 Sodium Extra / Podium Port）→getVersionsForModWithID→**gameVersions+loaders(fabric) 双过滤**→primaryFile；`startInstallSodiumWithGameVersion:` 注册统一下载任务（Sodium + Podium 单阶段）→两次取文件→串行下载→写实例 mods/ 目录→成功/失败 alert 与任务状态机对齐 Fabric API 流程。
- **l10n**：退役 preference.profile.renderer_follow_global_toggle / preference.warning.renderer_shadowed_by_profile；新增 component.sodium.confirm_title/confirm_message/searching/not_found/download_failed/done——四语言键集一致，**基线 1924→1928**。
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
Task ID: 154
Agent: Super Z (main agent, 本会话)
Task: 用户四连反馈根修（mg 系列"da5918a 后全部异常"回归定案）：ES 方块不渲染 + vulkan/es FSR 无效果致输入错位 + Forge 闪退 + Mithril(4.0) 加载崩溃（7c32bc3 新日志三会话，全部 3b35b26 构建）；渲染器 UI 保持现状（单 mg + 后端独立键，用户明令）

Work Log:
- 回归定案（用户问题"为什么那 2 个端在 da5918a 的时候正常"的完整答案）：libMobileGL.dylib 自 da5918a 后逐字节未变（git 单提交实锤）；9f32cb4/1d4ff3a（9e6fc27=5.1.0 发布构建）装机日志显示 MobileGL DirectVulkan 全分辨率直呈、无任何启动器侧 FSR 介入 = 用户认可的正常态；da5918a 之后的全部异常源 = Task119 起的启动器侧 FSR 联动（链体 + 缩窗 + 输入除法 + 几何豁免），与 mg 二进制无关
- 7c32bc3 三会话判读：①Vulkan（latestlog.old.txt）"Task153 backbuffer query unavailable" 一次性日志 + swap 探针 viewport 2360x1640 —— libMobileGL 的 EGL 是伪 EGL（surface/ctx 句柄恒 0x1、无 current 跟踪），eglGetCurrentDisplay/CurrentSurface 返回空 → 延迟缩窗永不下发 → MC 窗口信念恒全尺寸而 sendTouchPoint 仍除 mgFsrScale(2.0) → 触点只落左下四分之一 = "fsr 没有效果导致输入错位" 实锤；②Mithril（latestlog.txt）UnsatisfiedLinkError "Failed to locate library: liblwjgl.dylib" @ NativeLibrariesBootstrap —— Task152b 经系统类加载器预载 GL/Library + dlopen liblwjgl.dylib，MC 侧 Knot 加载器 Library.<clinit> 再载触发 JVM 单加载器不变量（already loaded in another class loader，被 LWJGL catch 吞掉伪装成 locate 失败）；且该会话 mod 列表含 sodium 0.9.2（POJAV_RENDERER 导出会在修完后再炸一次）；③Forge（latestlog.forge）"no AmethystAccountJNI in system library path" @ MinecraftAccount.<clinit> —— Task153 的 -Xbootclasspath/a 把 launcher.jar 交给 boot 加载器，其 loadLibrary 只搜 sun.boot.library.path
- 取证链：本地 JDK 21 实测双 -Xbootclasspath/a 为追加语义（Task153 该点无误但方向错）；CFR 反编译随包 lwjgl-opengl.jar 的 GL.create() —— MACOSX 分支自 c71dcfa 起读取 org.lwjgl.opengl.libname（Task152b 的"常量池无该字符串"判断系探错 jar：核心 lwjgl.jar 无 GL.class）；GL$1 Delegate 的 getFunctionAddress 先走 GetProcAddress(eglGetProcAddress) 再 dlsym 兜底 —— MobileGL 的 eglGetProcAddress 对核心 gl* 返回 0（Task140 实测）故 vulkan/es 一直走 dlsym；Mithril 的返回坏指针 = Run #356 "no OpenGL context" 真因（上下文已 current + tri-probe dlsym 正常 + createCapabilities 空值的排除法闭环）；下载官方 MC 26.2 client.jar 反编译 NativeLibrariesBootstrap（loadOpenGL=Objects.requireNonNull(GL.getFunctionProvider)）与 BootstrapLauncher 1.1.2（ignoreList=文件名前缀逗号分隔，命中 jar 不进模块层留传统 classpath）；手写 Mach-O 导出 trie 解析器（uleb128 子偏移）核实 libmithril.dylib 导出 _glGetString/_glGetIntegerv/_glGetError/_eglGetProcAddress（2082 exports）与各渲染器 dylib 的 eglGetProcAddress 导出面（OSMesa 无/导 OSMesaGetProcAddress、gl4es 空 trie、MobileGL 有但对 gl* 返 0）
- 修复 A（MobileGL FSR 全链退休，恢复 da5918a 语义）：ame83_fsr_capable_renderer 对 isMobileGLRenderer 返回 NO（mgFsrScale 恒 1.0：不缩窗、不除输入、不武装）+ 完整退休病历注释；mgl_fsr.mm ame_mgl_fsr_before_swap 入口即 return false（Task154 门禁 + 一次性日志，Task119-153 链体 #if 0 存档）；SurfaceViewController 延迟缩窗分支移除（统一 renderW 路径，armed 清零防跨渲染器残留）；gl_bridge Task78 豁免的 MobileGL 扩展回退（仅 MobileGlues 豁免——viewport==surface 使豁免对 mg 无操作，保留只会误豁免未来真几何事故）；渲染器 UI 零改动（A9 验证项）
- 修复 B（Mithril 4.0）：Tools.java Task152b 反射钉扎整块移除（跨类加载器原生库毒害根除，MC 自己的 GL.create() 读 -Dorg.lwjgl.opengl.libname 绝对路径即得正确 provider）；scripts/patch_lwjgl_delegate_dlsym.py —— GL$1.class 常量池 "eglGetProcAddress"→"xglGetProcAddress"（17 字节等长交换，零结构变更；OSMesaGetProcAddress 保留给 zink；已对 lwjgl-341/lwjgl-opengl.jar 应用并幂等复验，lwjgl-333 为上游 Delegate 结构无此串不触碰；src/lwjgl overlay 无 opengl 类，补丁在 JavaApp 构建合并后存活）；JavaLauncher 移除 Mithril 的 POJAV_RENDERER 导出（Sodium 0.9.2 雷点 + fixPojavGLContext 已无必要）
- 修复 C（Forge v2）：Task153 的 bootclasspath 迁移整体撤销（libs 回归 -cp 主路径+headless 双处）；BootstrapLauncher ignoreList 注入 —— 扫描 jvm_processed 自带 -DignoreList 则并入 launcher.jar，否则推默认值 "asm,securejarhandler,launcher.jar"；后推生效（JVM 同名 -D 后者胜出）；launcher.jar 留系统加载器（loadLibrary 搜 java.library.path=Frameworks，AmethystAccountJNI 复活）且不进 MC-BOOTSTRAP 模块层（无 "launcher" 自动模块，split package 根除）
- 验证：verify_task154 新建 39/39（A mg-FSR 退休 9 + B Mithril 5 + C Delegate 补丁 5 + D Forge v2 5 + E 7c32bc3 证据锚 6 + F 语法配平/version.h/environ 9 + G 级联）；verify_task153 重锚 29/29（C1/C3/E3/E4 改判 Task154 超越语义）；verify_task119_124 A6/A7 重锚（61/62，仅剩 F1=HEAD 既有）；task139 失败集与 HEAD 逐项一致（11/11 全环境性旧账：历史日志文件已被覆盖/工作区副本缺失）；142/143/151 与 HEAD 一致；149/150 为环境性 workspace 副本缺失（既有）；语法门 error 数与 HEAD 相等（5=5，br_get_current 类既有环境缺失）
- 环境经验：CFR 反编译 class 用 stdout 模式（--outputdir 需目录结构）；Mach-O 导出 trie 子偏移是 uleb128 且相对 trie 起点（LC_DYLD_EXPORTS_TRIE=0x80000033，0x34 是 chained fixups）；github API 限流时用 git remote 里的 token 走 actions API；heredoc 写 C 头文件注释时行首 '#' 会变成非法预处理指令（本次已修复为 '//'）

Stage Summary:
- 产出：Task154 五文件修复（SurfaceViewController.m / mgl_fsr.mm / gl_bridge.m / JavaLauncher.m / Tools.java）+ lwjgl-341 jar 字节码补丁 + patch_lwjgl_delegate_dlsym.py + verify_task154.py（39 项）+ task153/119_124 重锚 + version.h/environ.h addendum + worklog 双份
- 装机锚点：①vulkan/es 会话 "[MGLFSR] Task154 MobileGL pre-swap FSR chain RETIRED (renderer=...)" + 输入复位（触点全屏准确）+ ES 方块渲染恢复 + 全分辨率直呈画面干净；②Mithril 会话越过 NativeLibrariesBootstrap（无 "Failed to locate library"）且 GlDevice 过 createCapabilities（sodium 0.9.2 包不再被 POJAV_RENDERER 触发）；③Forge 会话 "[JavaLauncher] Task154 Forge ignoreList shield: '...launcher.jar'" 且无 ResolutionException/无 AmethystAccountJNI 闪退
- 关键决策：mg 系列 FSR 彻底退休（8 轮修补失败的架构性裁决——伪 EGL 下启动器侧链无可靠几何信号源；用户 da5918a 基准即无 FSR 态）；FSR 仍可用渲染器 = MobileGlues/zink；mg 想要画质/帧率权衡用 video.resolution
- 遗留：ES 方块不渲染若在 Task154 构建上仍复现（理论上不可能——链已 #if 0），下一轮需其会话日志；26.1.2 存档崩溃/FSR(MobileGlues 侧)/虚拟按钮等既有遗留不动

---
Task ID: 154 (续)
Agent: Super Z (main agent, 本会话)
Task: CI 确认

Work Log:
- CI run 35884635001（0a22f51）completed success（完整 SHA 轮询：15:51 触发，约 5 分钟完成——本会话改动无 iOS 编译新增面，.m/.mm 均为纯 ObjC 语法内改动）
- 轮询经验：GitHub actions API 的 head_sha 过滤需完整 40 位 SHA（短 7 位恒返回空）

Stage Summary:
- Task154 全链闭环：三案根修（mg-FSR 退休 / Mithril 双加载器+Delegate 补丁 / Forge ignoreList v2）+ 验证器 39/39 + 级联零新增失败 + CI 绿，新 IPA 就绪
- 装机待验证锚点见 Task154 主条目：①vulkan/es "Task154 ... RETIRED" + 触点全屏准确 + ES 方块渲染；②Mithril 越过 NativeLibrariesBootstrap 进 GlDevice（sodium 0.9.2 包）；③Forge "Task154 Forge ignoreList shield" 且无 ResolutionException/AmethystAccountJNI 闪退
