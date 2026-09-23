# Worklog

## ⚡ READ ME FIRST —— 会话速览（只读本节 + 「滚动近况」即可开工；更早历史一律查 worklog-archive.md，勿通读）

> 最后更新：Task 144（2026-09-22）。此前：Task 143（2026-09-22）。此前记录：Task 142（2026-09-22）；2026-09-22 本文件瘦身重构（Tasks 34-140 → worklog-archive.md，未占用 Task 编号）。
> 新会话规则：新任务记录**追加到本文件最末尾**（`## Task N` 或 `---/Task ID:` 模板均可）；收尾时同步更新下面「当前状态」表；本文件超过 ~400 行时把最旧的任务段挪进 worklog-archive.md。

### 一句话
AngelAuraAmethyst（Amethyst-iOS 重制版，fork **Gsjsjzhznsz/Air-Minecraft-iOS-Launcher**）——iOS Minecraft 启动器，已发布 **v6.0.0**：MC 26.x 全链路可玩（26.3-pre-1 + Fabric + 128 mods + MobileGlues 渲染链）。当前主线：UI 打磨、渲染器存储分层（auto/mg + mobileglues.renderer_backend）、各 MC 版本崩溃根修。

### 当前状态（收尾时更新）
| 项 | 值 |
|---|---|
| 远端 HEAD | 171006ce（Task 144 七修复），CI run 35737215334 绿，IPA 产物可下载 |
| 最新 Task 号 | **144**（双会话并行开发，开新任务前先 fetch 避让编号） |
| 待用户装机验证 | Task 141 七项 UI + Task 142 渲染器分层七锚点 + **Task 143 三修复**（后端落盘 / FSR 常量 / 单 mg 列表，见 Task 143 Stage Summary） |
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
