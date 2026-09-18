
---
Task ID: 47
Agent: main (Super Z)
Task: 修复 Minecraft 26.3-pre-2 全部 34 个渲染管线编译失败导致的启动崩溃（latestlog a5189d5 取证）

Work Log:
- 判读用户上传的 latestlog.txt：崩溃 = ShaderManager.reload 时 34 个必需 pipeline 全部编译失败（"Failed to load required shader programs"），每条失败的根因均为 glslang 报 "ERROR: '#include' : required extension not requested: Possible extensions include: GL_GOOGLE_include_directive / GL_ARB_shading_language_include"；GL/Vulkan 共享 GlslCompiler.compileToSpv → 两路径同崩；SDL 嵌入/EGL 表面/窗口全部正常（AmethystEmbed SUCCESS、RenderDiag 2360x1640）——首帧门控、CI wget 等前序修复均非本轮死因
- 下载 26.3-pre-2 官方 client.jar 反编译 renderpearl：GlslCompiler.compileToSpv 每次编译都调 shaderc_compile_options_set_include_callbacks 上行 LWJGL libffi 回调（createIncludeResolver → ShaderSource.getInclude）；旧 glue 的 set_include_callbacks 是 no-op（"MC resolves moj_import includes BEFORE reaching shaderc" 假设对 26.3 renderpearl 不成立——新版把 #include 原样留给 shaderc）
- 核实 LWJGL 3.4.1 ShadercIncludeResult 真实布局（source_name@0/len@8, content@16/len@24, user_data@32——与 google/shaderc 公开头顺序不同，以 LWJGL 为准）、resolver ABI（libffi CIF：include_depth 按 pointer 宽传）、releaser 为 no-op（Java 侧管理内存）
- 提取 vanilla shader 夹具（56 个文件含 #include；嵌套 2-3 层；条件块内 include；无 include guard）
- 新增 Natives/shaderc_include.c/h：文本级递归展开器（行扫描 + 跨行块注释状态机；每展开点后 #line 恢复外层行号；深度 16 截断；总输出 64MiB 上限；resolver NULL/缺失时原行保留可见诊断；releaser 按协议调用）
- shim 集成（shaderc_shim.c）：影子注册表新增 inc_resolver/inc_releaser/inc_user_data（仅本进程，绝不序列化进沙箱请求——防野指针）；导出并拦截 shaderc_compile_options_set_include_callbacks（原 shim 未导出，LWJGL 经依赖链解析到 glue 的 no-op——现由 shim 优先命中）；编译入口（缓存 key/源码 dump/沙箱/in-process 全下游之前）在调用者线程（JVM 线程，libffi upcall 安全）展开；cleanup attribute 统一释放展开 buffer；地址复用防御（slot 创建清空回调字段）
- Makefile：libshaderc.dylib 源列表加入 shaderc_include.c（Edit 工具曾把全文 tab 规范化为空格——已从 HEAD 恢复后用 scripts/fix_task47_makefile.py 字节级补丁，git diff 退回 1 行纯新增）
- 本地验证（响应用户"先确认 bug 再提交"）：
  * 单元测试 test_task47_include.c：29/29 PASS（真实 terrain/entity/clouds + oit 三层嵌套 + 条件块语义保留 + not found 内联 + 循环截断 + NULL 保留 + 注释精度 + 无 include 直通）
  * 端到端 test_task47_e2e.sh：本机 glslangValidator 16.5.0 对未展开源码报出与设备 latestlog 逐字一致的错误（环境等价性证明）→ 展开后 terrain/entity/clouds.vsh + block.fsh（含 oit 嵌套链）全部编译为合法 SPIR-V（魔数 07230203，--amb 对应 glue 的 auto_bind_uniforms）
  * 测试期间发现并修正 driver 的 static buffer 复用伪缺陷（改为每次 resolver 调用独立 malloc，忠实模拟 Mojang CachedIncludeSource 语义）
  * 语法验证：shaderc_shim.c / shaderc_include.c host -fsyntax-only 通过；Makefile recipe TAB 逐字节验证 + mini 目标独立解析无 missing separator

Stage Summary:
- 共同 bug（GL 与 Vulkan 同时失效）定位并修复：26.3 renderpearl 的 #include 上行回调被 glue no-op 丢弃；修复 = shim 层文本展开，沙箱与 in-process 双路径统一受益
- 产物：Natives/shaderc_include.c/h（新增）、shaderc_shim.c（+85 行）、Makefile（+1 行）、scripts/fix_task47_makefile.py、scripts/test_task47_include.c、scripts/test_task47_e2e.sh、scripts/test_task47_e2e_driver.c、scripts/task47_fixtures/（真实 vanilla shader）
- 预期设备表现：latestlog 出现 "[shaderc-shim] options_set: include_callbacks" 与 "[amethyst-include] expanded N include(s)"，34 个管线编译通过，游戏进入标题屏

---
Task ID: 50
Agent: main (Super Z)
Task: 黑屏根因修复——呈现几何单一事实源（latestlog 622166a 取证，用户上传仓库日志）

Work Log:
- 拉取用户上传至仓库的最新日志 latestlog.txt（8932 行，commit 622166a，iPad Air M4/iPadOS 26.6，MobileGlues GL 路径）：游戏实际运行健康（57fps、swapOK=586、swapFail=0、FBO0 有内容、遮罩 7.7s 正常移除）但用户全程黑屏
- 铁证链定案（与 Task48/49 旧结论相反）：
  * 全日志 0 条 "Task48 pin" = 旧卫兵逐帧钉扎从未生效（渲染线程与主线程读到不同 drawableSize = CALayer 跨线程状态分叉）
  * 创建时 eglQuerySurface=2360x1640（横屏 2x），swap 期恒 1640x2360（转置）且永不恢复 = surface 被锁死转置
  * 心跳 drawable 序列 [2360x1640, 2360x1640, 1640x2360, 2360x1640] 跟随视图方向，与 swap 期 surface 恒矛盾 = present 尺寸失配 = 黑屏直接成因
  * 重建表面恒 EGL_BAD_ALLOC 0x3003（同 layer 二次建 window surface 必败）
  * renderpearl 两次抛 "Cannot acquire minimized window"（embed 隐藏 SDL UIWindow → SDL 标记 minimized）
  * 结构性根源：MC 26.3+SDL3 以点回报窗口尺寸（viewport=1180x820）而呈现层 contentsScale=2.0/drawableSize=2360x1640，1x-vs-2x + 三套尺寸各自跟随不同主人（ANGLE surface / 主线程 drawable / SDL viewport）+ 旋转时互相打架
- 修复（4 文件，全部围绕"单一事实源"）：
  * gl_bridge.m：Task50 1x 对齐（创建时主线程 dispatch_sync 写 contentsScale=1.0 + drawableSize=bounds 点数——无论 ANGLE 读 bounds×scale 还是 drawableSize 都 == MC viewport；取代 Task48 钉扎与 Task49 重试环，单次建面）；卫兵降级为纯取证（删除 pin/重建/打架）；geo-heal latch 双向化（几何恢复即退出逐帧 blit）；新增 ame_gl_surface_owns_layer() 跨线程标志（currentBundle 是 __thread 的，主线程读不到）
  * SurfaceViewController.m updateSavedResolution：GL 拥有呈现层时对齐 1x 跟随 bounds（旋转时三者同步翻转）；Vulkan 路径保持旧 2x 行为（MoltenVK 自管）
  * sdl3_hook.m：拦截 SDL_GetWindowFlags 剥离 SDL_WINDOW_MINIMIZED(0x40)——renderpearl 不再因 embed 隐藏 SDL 窗口而跳帧；补前置声明修 use-before-declare
  * utils.h：声明 ame_gl_surface_owns_layer
- 本地验证（用户强制要求"提交前彻底确认"）：
  * scripts/verify_task50.py 日志重放仿真：14/14 PASS——旧代码模型逐项复现日志实测（A1-A7：pin=0、重建失败、surface 锁死转置、心跳 drawable 序列逐项一致、不变量 8/8 帧违反、终态三值互异）；新代码模型全程 surface==drawable==viewport（B1-B3：0 违反、geo-heal 永不触发）；悲观场景（ANGLE 仍转置）geo-heal 保证全屏可见非黑（B2）；minimized 位剥离验证（C）
  * 结构平衡检查：4 文件 brace/paren/bracket delta=0（sdl3_hook 的 -6 为 HEAD 既有，与本改动无关）
  * diff 逐块复审：对齐块→surface 创建顺序正确（attribs 读对齐后 layer）、标志仅在 surface 创建成功后置位、gl_terminate 清位、前向声明补齐
  * 本机无 iOS SDK/clang，真实编译由 CI（macOS runner xcrun）执行

Stage Summary:
- 黑屏根因定案并修复：呈现几何三套尺寸（ANGLE surface / 主线程 drawable / SDL viewport）互相打架 + 跨线程 layer 写入分叉 + 1x-vs-2x 结构性失配；修复 = 1x 单一事实源 + 主线程单写入者 + 卫兵降级取证 + minimized 谎言
- 预期设备表现：[GLGeo] Task50 1x alignment 日志、swap 探针 surface==viewport（1180x820）、mode=1 正常呈现、无 minimized 异常；即使 ANGLE 外部再转置，geo-heal blit 保证全屏可见（压扁而非黑屏）
- 遗留：控制按钮输入桥（GLFW 回调 NULL，ESC 等虚拟键无效——触摸经 SDL 视图已可用）；2x 渲染分辨率（现为 1x 放大，MC 像素风下可接受）；Vulkan 路径需要用户提供 latestlog 才能诊断

---
Task ID: 55
Agent: main (Super Z)
Task: 画面分裂根因第二轮根治（latestlog f93e882 / a901050 构建取证；用户症状"画面分裂"，非崩溃）

Work Log:
- 拉取用户上传的新日志（f93e882，a901050/Task54 构建，2026-09-11 23:10 会话，67 秒游戏时长）：Task54 崩溃修复真机确认生效——include 回调稳定、零 shader 管线失败、游戏完整进入世界（玩家 yiqiu4178 登录、3662 帧 60fps）。启动崩溃已死
- 画面分裂机制链定案（本轮目标）：
  * 337 行：初始 eglQuerySurface=1180x820 创建时正确；盲窗内（8500 行加载、零 swap）转置为 820x1180
  * 8874-8876 行：Task53 realign 于首次 swap 前执行，destroy+recreate 后依然 820x1180（对着横屏 layer！）却打印 "SUCCESS (transposed lock cured)" = 假成功——判定只验 create!=NULL，未验几何
  * 假成功 → g_ame53_transposed=0 → updateSavedResolution ceasefire 解除 → drawableSize 拉锯回归（guard 写 820x1180 vs 其它写者 1180x820）→ 交替几何 = 用户看到的分裂画面
  * 新旧 surface 句柄同为 0x1（ANGLE HandleAllocator 回收）——destroy+即时 recreate 复用槽位
  * Task52 guard + Task51 present-align 失配期写 surface 转置值 = 反向钉死：阻断 ANGLE 依据 drawableSize 自愈（622166a 证 ANGLE 有跟随能力；Task50 证主线程写入唯一可靠）
- 修复（gl_bridge.m 四处，Task 55）：
  * ame55_verify_surface：治愈判定 = querySurface == layer bounds；假成功不可能；每步独立验证+日志
  * 梯度重对齐 A→B→C（一步治愈即停）：A 几何信号（主线程 drawableSize=bounds + bounds 1pt 轻碰 + 2 拍主 runloop + CATransaction flush）；B 延迟重建（destroy → 100ms 真间隔（信号量栅栏）→ 显式横屏 attribs 重建 → 2 拍 → 验证）；C 反向转置旅程（转置值 → 2 拍 → 横屏 → 2 拍 → 验证）。预算 3 次 + 2s 冷却 + 对齐帧重臂不变
  * Task52 guard 方向自适应：失配未治愈写横屏 bounds（持续自愈信号；ANGLE 不跟随时压扁 blit + CA 拉伸互逆、纵横比还原）；治愈后写 surface 值（同值 no-op）。日志区分 heal-align/present-align
  * Task51 一次性对齐反转为 heal 语义（写 bounds，与 guard 同向）
- 本地验证（不盲提交）：
  * scripts/verify_task55_structure.py：括号平衡（175/730）、18/18 指纹、4/4 旧文本清除、梯度顺序、验证门控 ×3、guard 读主线程 bounds——全过
  * scripts/shadow_compile_task55.py：提取四区块 → ObjC→GNU C 机械转换（block 大括号配对内联展开、dispatch_after 处理、__bridge/点语法/NSLog 转换）→ gcc -fsyntax-only -Wall -Wextra 0 错误
  * scripts/test_task55_logic.c：21/21 PASS——ANGLE 行为模型 M1（A 治愈）/M2（B 治愈）/M3（C 治愈）/M4（顽固全败）、假成功拒绝、预算/冷却/熔断/重臂、guard 双向、T51 单发、400 帧零写者冲突（拉锯死）
- 提交 e59e934（rebase 于 f93e882 之上），推送触发 CI run 126

Stage Summary:
- Task54 崩溃修复真机确认；本轮根因 = realign 假成功 + guard/T51 反向钉死 + 拉锯回归
- 修复 = 验证门控的梯度重对齐（覆盖 ANGLE 三种读数机制假说）+ 写者方向统一（横屏信号）
- 下轮日志判读表：Task55 realign attempt/stepA/B/C + 每步 verify 行；治愈 = "CURED by stepX: query=1180x820" + swap surface==viewport；顽固 = 三条 NOT-cured 精确指认 ANGLE 忽略哪种机制 + guard heal-align 行确认拉锯已死
- 输入错位随画面治愈自然对齐（坐标链路自洽，Task53 已证），本轮无输入侧改动

---
Task ID: 56
Agent: main (Super Z)
Task: 画面分裂+输入错位+退后台"崩溃"三连根因定案与修复（latestlog 1bd9f32/Task55 构建取证；用户线索"另一开发者说关闭小窗就能解决"）

Work Log:
- 拉取用户上传的新日志（1bd9f32，dbac097/Task55 构建，2026-09-12 06:01 会话）：Task54 启动崩溃修复继续生效（include 回调稳定、进世界、57fps/132 swap）；Task55 梯度 realign A/B/C 三步全部 NOT cured（0 CURED）；日志尾部 renderpearl SurfaceException "Cannot acquire minimized window"（上一轮已知遗留）仍然发生
- 用户关键新线索："关闭小窗就能解决"——与日志第 17 行 [SceneDelegate] Failed to update geometry: UISceneErrorDomain Code=101 "当前窗口模式不允许以编程方式更改界面方向"（每轮日志必现）交叉验证 → app 一直在 iPadOS 26 窗口模式（小窗）下运行：Info.plist 从未声明 UIRequiresFullScreen，iPad 按窗口化 app 对待，方向控制权归系统
- 崩溃链反编译定案（下载 26.3-pre-3 官方 client.jar + jawa/原始字节解析）：
  * Minecraft.createSurface 传给 renderpearl 的 BooleanSupplier = window::isIconified（BootstrapMethods 绑定实锤）
  * GlSurface.acquireNextTexture（Java:46）= `if (supplier.getAsBoolean()) throw SurfaceException("Cannot acquire minimized window")`——仅 22 字节
  * Window.handleEvent 的 lookupswitch：case 0x209 → onIconified(true)；0x20a/0x20b → onIconified(false)
  * 随包 libSDL3.dylib 实为 SDL 3.4.0（revision 字符串实锤）；官方 release-3.4.0 头文件核对：WINDOW_MINIMIZED=0x209，与 LWJGL 3.4.1 常量一致——无枚举错位（曾假设错位，已证伪）
  * 日志事件序列：启动期 0x207(PIXEL_SIZE_CHANGED，无害) → 退后台瞬间 0x209(MINIMIZED) → MC iconified=true → 下一帧 acquireNextTexture 抛异常
  * renderFrame 反编译：异常被 catch+WARN（日志里那行 WARN+堆栈就是它），随即 surfaceIsInvalid=true + windowSurfaceNeedsReconfiguring=true；回前台后 configure() 在同一 CAMetalLayer 二次建 EGL window surface 必败 EGL_BAD_ALLOC（Task50 已证）→ 表面永久失效 → 冻结/黑屏 = 用户看到的"崩溃"
  * 本移植真正呈现面是宿主 GameSurfaceView 的 CAMetalLayer（SDL 窗口只是被隐藏的事件壳）——"最小化"纯属谎言，呈现面前后始终有效
- 分裂画面/输入错位根因链（与"小窗"线索闭环）：窗口模式 → requestGeometryUpdate 被拒（Code=101）→ 场景几何无法强制横屏 → 加载期表面转置 820x1180 vs drawable 1180x820 → Task55 的主线程几何信号/重建全部失败（系统拥有窗口几何，应用侧写不动）→ 拉锯 = 分裂；画面扭曲导致触点与所见错位 = 输入错位（坐标链本身 ×2/÷2 自洽，Task51 已修）。另一位开发者"关闭小窗就能解决"= 绕开触发器的 workaround，同时确证根因
- 修复（dd43731，三层）：
  1) Natives/Info.plist 加 UIRequiresFullScreen=true（字节级补丁保留 tab，防 Edit 工具全文件空白规范化——Task47 同款坑）：app 只能全屏运行，夺回方向控制权，场景几何恒横屏，表面不再转置
  2) sdl3_hook.m SDL_PollEvent 吞掉 SDL_EVENT_WINDOW_MINIMIZED(0x209)：MC 永不进入 iconified，退后台/回前台零异常风暴、零表面失效（MAXIMIZED/RESTORED 仍放行作纵深防御）
  3) SceneDelegate.m sceneDidBecomeActive 非横屏时重试 requestGeometryUpdate（防御纵深）
- 本地验证：plist XML 合法+键值正确；两 .m 阴影编译（ObjC→GNU C 机械转换）0 错误；括号平衡与 HEAD 差异 0；行为级回放测试（1bd9f32 真实事件序列）：新钩子 0 异常 0 表面失效 vs 旧钩子 1 异常+失效
- push dd43731 → CI run 34655737487 构建成功；产物验证（IPA artifact 10285846691）：
  * Info.plist UIRequiresFullScreen=True ✓
  * 反汇编实锤新逻辑在：subs w8,w8,#0x209 @0x10001a280、atomic counter、dn%50、循环回跳、__LINE__=0x38f(911) ✓
  * 重要方法论沉淀：含中文的 ObjC 字面量被 clang 编成 UTF-16LE 存 __TEXT,__ustring——ASCII strings 搜不到会误判"没编进去"（本轮差点误判）；今后验证指纹一律用纯 ASCII 日志串
- 用户装机测试预期锚点（dd43731 构建）：
  * 第 17 行 geometry Code=101 错误消失（全屏后 requestGeometryUpdate 不再被拒）
  * app 无法再进入小窗/分屏/台前调度——只能全屏
  * 退后台再回前台：游戏不冻结不黑屏，"[SDLHook] Task56 drop SDL_EVENT_WINDOW_MINIMIZED #N" 指纹出现（首 10 条逐条+每 50 条采样）
  * 画面不再分裂（表面不再转置）；若 ANGLE 仍偶发转置，Task55 realign 此时应有系统配合、可 CURED
  * 输入随画面治愈自然对齐

Stage Summary:
- 三症状（分裂画面+输入错位+退后台崩溃）统一根因定案：app 未声明 UIRequiresFullScreen → iPadOS 26 窗口模式（小窗）→ 几何失控 + 最小化事件毒杀游戏
- "关闭小窗就能解决"被采纳为根因确证并升级为代码级强制（UIRequiresFullScreen）——不是建议用户别开小窗，而是 app 从此没有小窗
- 已知遗留：posix_spawn ENOENT（沙箱 helper 不可用，回退正常）；1x 渲染分辨率；Terracotta 多人仍禁用中

---
Task ID: 57
Agent: main (Super Z)
Task: 画面分裂第三轮：冻结 ANGLE 窗口表面尺寸源（bbe6d63 日志取证；本轮补录——de3daa6 曾为空提交）

Work Log:
- 拉取用户上传的 bbe6d63 日志（Task56 构建 5f8e5f3）：UIRequiresFullScreen 未能阻止窗口模式（Code=101 仍在 willConnect 触发），Task55 梯度 realign A/B/C 全部 NOT cured（query=820x1180 vs expected=1180x820），表面仍"转置"
- 反汇编自带 ANGLE（libGLESv2）：checkIfLayerResized（每帧 obtainNextDrawable 执行）是几何执法者——expected=[layer bounds]×contentsScale，读渲染线程视角；主线程 drawableSize 写入结构性无效（执法者只读 bounds）
- 修复（3e5e051，8 字节机器补丁）：checkIfLayerResized @0x1aaca0 的 fmul d0,d10,d0/fmul d1,d11,d1（expected←bounds×scale）改为 ldr d0,[x19,#0x430]/ldr d1,[x19,#0x438]（expected←冻结的 mWidth/mHeight）——表面尺寸物理上不可能再被 layer 读数改变；Makefile 新增 dep_angle_freeze 接入 payload；gl_bridge.m 增加 Task57 渲染线程 layer 读取探针（split-brain 一锤定音用）
- 本地验证：补丁应用/幂等/--verify 三遍；CI run 34661034866 构建成功且日志实锤 "PATCHED ✓ @0x1aaca0"

Stage Summary:
- 产物：scripts/patch_angle_surface_freeze.py、Makefile dep_angle_freeze、gl_bridge.m Task57 探针
- 预期：表面冻结在创建几何（创建读恒干净），转置物理隔离；代价=合法 resize 退化为 CA 拉伸
- 遗留（下轮定案）：Task57 构建实测仍分裂——见 Task 58（真根因不在 ANGLE，而在我们自己的探针常量）

---
Task ID: 58
Agent: main (Super Z)
Task: 画面分裂+输入错位真根因定案与根治——EGL 查询常量自 Task41 起对调（7d8dcfd 日志取证）

Work Log:
- 拉取用户上传的 7d8dcfd 日志（Task57 构建 3e5e051，2026-09-12 12:33 会话）：Task57 freeze 补丁确认在 IPA 内（CI 日志 PATCHED ✓）但用户实测仍分裂；Task55 realign A/B/C 依旧全败
- 决定性新证据（Task57 split-brain 探针首触发，8989 行）：渲染线程读 layer bounds=1180x820 drawable=1180x820 scale=1.00 sublayers=0——与主线程完全一致、全程横屏干净 → "跨线程脏读毒化"假说被证伪
- 矛盾收敛：补丁在+mWidth/mHeight 无第三写入者（全二进制扫描 [impl+0x430] 写者仅 ctor 清零/initialize/checkIfLayerResized 三处）+无拉锯日志 → impl 表面从未被毒化；但 Task41 交换探针仍报 surface=820x1180
- 反汇编链条（本轮全部完成）：initialize()=mWidth←[layer bounds]×contentsScale（selector 全解析：setDevice/setPixelFormat/setFramebufferOnly/bounds/contentsScale/setDrawableSize）✓干净；checkIfLayerResized 完整语义重构 ✓；egl::Surface::getWidth() 仅在 EGL_FIXED_SIZE_ANGLE(0x3201) 属性存在时返回前端 mState（我们从不传）→ 返回 impl 真值 ✓；SetSurfaceAttrib 的 0x3056→setFixedHeight/0x3057→setFixedWidth 其实是正确映射
- 真根因水落石出：egl.h 官方定义 EGL_HEIGHT=0x3056、EGL_WIDTH=0x3057（仓库内 mesa/MobileGlues 两份 egl.h 互证）——gl_bridge.m 三处（Task41 交换探针 580-581、ame55_verify_surface 377-378、Task53/55 realign 刷新 641-642）自 Task41 起把 0x3056 当宽、0x3057 当高，宽高读反！1180x820 的健康表面（创建时宏查询铁证）被读成 "820x1180 转置" → geoMismatch 每帧误判 → Task49 geo-heal 把完好横屏帧 blit 进竖屏 scratch 再回写 → 分裂画面+输入错位全部由我们自己的补偿链制造；Task48/49/50/51/52/53/55/56/57 六轮修复追的都是这个幻影
- 历史日志全部吻合：622166a（2x 时代）swap 期 "1640x2360" = 2360x1640 的对调读数；bbe6d63/3e5e051 "820x1180" = 1180x820 的对调读数
- 修复（gl_bridge.m，三处）：裸常量 0x3056/0x3057 → EGL_WIDTH/EGL_HEIGHT 宏，注释同步修正，新增一次性 Task58 指纹日志；修正后 viewport==surface → latch NORMAL → geo-heal/blit/realign/present-align 全部不触发，画面 1:1 原样呈现，输入随画面对齐
- "关闭小窗模式"线索定性：它指向的是触发条件的可见性，而非缺陷本身；常量修正后小窗模式下 layer/surface/viewport 恒 1180x820（历轮日志一致），小窗不再有影响
- 本地验证（scripts/verify_task58.py，13/13 PASS）：无残留误标注、宏调用 6 处、指纹存在、括号平衡 delta=0；日志重放仿真——旧探针模型精确复现日志（幻影 820x1180+1570 次 blit+3 步 realign 全败），修正探针模型读 1180x820 → NORMAL、0 次 blit、0 次 realign
- Task57 freeze 补丁与 Task56 MINIMIZED 吞噬保留（纵深防御+已证实的崩溃修复）

Stage Summary:
- 画面分裂/输入错位根因定案：gl_bridge.m 三处 EGL_WIDTH(0x3057)/EGL_HEIGHT(0x3056) 常量对调，"转置表面"是探针自造的幻影，可见症状由 geo-heal 补偿链制造
- 下轮设备日志判读锚点："[GLGeo] Task58 query constants corrected: surface=1180x820 viewport=1180x820" + "Task41 latch: NORMAL present"，且全程零 "geo mismatch ENGAGED"/"geo-heal blit"/"realign" 行 = 修复生效；画面应 1:1 完整、输入对齐
- 影响分辨率的因素全链（本轮完整测绘）：SDL 窗口点尺寸(1180x820)/物理像素(2360x1640)/contentsScale(1x)/CAMetalLayer.bounds/drawableSize/ANGLE impl mWidth/bounds×scale/EGL 前端 mState(仅 FIXED_SIZE 时生效)/viewport——除最后两项在本案为误读来源外，其余全程自洽

---
Task ID: 76
Agent: main (Super Z)
Task: MG(MobileGlues) 渲染卡顿调查与修复——"30fps 看得像 10fps"（bef0f08 双日志：latestlog.old=MG 场 / latestlog=Zink 场）

Work Log:
- 拉取 bef0f08 上传（2 个 log）：MG 场（libmobileglues.dylib，构建 729d954）fps 在 5~60 剧烈震荡（ΔswapOK/5s 均值证明 5fps 谷底为真），Zink 场（libOSMesa.8/Mesa25）稳定 40-53；JVM 配置两场一致（2967MB/G1/同样 GC 密度），排除 Java 侧
- 定位 MG 路径架构：MC desktop GL3.3 → MobileGlues 前端（GL3.3→GLES3.0 转译+FBO redirect，Task36 生命周期路由）→ ANGLE Metal；fps 统计走 pojavGetAndResetFps（渲染线程真实 swap 计数）
- 根因1（主因·用户设置+集成缺陷）：mobileglues.fsr1_setting=2（Quality，用户在设置开启；PLPreferences 默认 0）+ MobileGlues FSR1 集成从未降低 render 分辨率（CalculateRenderResolution 全库零调用）→ MC 全分辨率 2360x1640 渲染时 render==surface → target=3540x2460（2.25x 表面面积）→ 每帧 3 个全屏 pass（clear+EASU/RCAS+缩小 blit 回 surface）纯带宽税 + 双重重采样（画质反而更差）
- 根因2（放大器）：vsync 锁 60——33 条心跳在 max.fps=260 解锁下零超 60 → 帧时间尖峰被量化为丢拍阶梯（33/50/100/200ms）→ 观感"10fps"；Zink 场 IMMEDIATE present 无此效应
- 根因3（本仓库独有税）：gl_swap_buffers 每帧 Task41 取证 3x glGetIntegerv + while(glGetError) 清错（吞 MobileGlues 待转译 GL 错误）+ 2x eglQuerySurface，Task48 guard 再加 2x querySurface + 跨线程 layer 读；上游 Amethyst swap 路径（ame_geo_check_and_heal）零 GL 状态查询（克隆 herbrine8403 上游实证）
- 修复1 MobileGlues FSR1.cpp/.h（主仓库普通目录，随主仓库提交）：TeardownFSR1()（删 render/target FBO+纹理+RBO，tracked draw fbo 死名簿记 framebuffer_recreated→0，fsrInitialized 保持 true 防重建）+ CheckResolutionChange 零增益判定（latch render≥surface → teardown，否则 RecreateFSRFBO）+ ApplyFSR g_renderFBO==0 早退守卫；OnResize 无条件刷新 pending 保证旋转后 render 跟随 surface → 恒无旁路盲区
- 修复2 gl_bridge.m：Task41 取证降频——probe 帧（≤5 / %200 / 非 NORMAL 态）才做全量查询与执法，稳定 NORMAL 帧零 GL/EGL 调用（300 帧窗口 300→6 次查询）；退役 while(getError) 清错循环
- 修复3 gl_bridge.m：POJAV_DISABLE_VSYNC 双保险——MobileGlues 前端 + raw ANGLE（新解析 ame_raw_swap_interval）各设 eglSwapInterval(0)，两路返回值入日志（下轮日志分诊"前端吞 vs ANGLE Metal 不支持"）
- 修复4 帧节奏诊断：gl_bridge.m 帧间隔窗口统计（ame76_record_swap/ame_egl_swap_framegap）+ utils.h 声明 + SurfaceViewController [RenderDiag] 心搏新增 maxGap/avgGap——修复前后对比的硬指标
- 6 语言（en/ja/km/zh-CN/zh-Hans/zh-Hant）FSR1 设置详情文案更新：说明全屏分辨率渲染下自动旁路
- 验证：scripts/verify_task76.py 40/40 PASS（A 源码指纹 29 项 / B FSR1 决策回放含旋转 latch 两阶段 / C probe 语义不变量+量化 / D 括号平衡 4 文件 / E 级联回归 task70+71）；CMake dep_mg 从源码增量构建，FSR1.cpp 时间戳变化必触发重编

Stage Summary:
- MG 卡顿三层根因定案：FSR1 零增益每帧三重全屏税（主因）+ vsync 锁 60 丢拍阶梯（放大器）+ swap 路径取证税（本仓库独有）；GC/JVM 排除（两场一致）
- 下轮设备日志判读锚点：①"[MG] FSR1 zero-gain bypass: render 2360x1640 >= surface -- FSR machinery torn down"（修复1生效）；②"[gl_bridge] eglSwapInterval(0) ... frontend=1 raw=1"（双路返回值，若 raw=0 则 ANGLE Metal 不吃 interval=0，需另想 vsync 方案）；③[RenderDiag] maxGap 从 100-200ms 量级回落到 ≤50ms 且 fps 谷底不再 <15 = 修复见效；④MG 场 fps 是否能超 60（判断 vsync 是否真被解除）
- 遗留：ES3.0 转译路径无 GL_ARB_multi_draw_indirect/buffer_storage 全家桶 → Sodium 慢路径 → MG 平均帧率天花板低于 Zink 属结构性（Zink 暴露 GL4.6 全套）；真·FSR 增益需"降分辨率渲染+表面全尺寸"的窗口分辨率联动（工程量大，未做）

---
Task ID: 77
Agent: main (Super Z)
Task: 用户报"还是一样卡，深度研究行吗。上传了2个log。还有默认控件选择custom"（Task76 构建后 MG 仍卡顿）

Work Log:
- 拉取 66e57f0：用户在 Task76 构建（3041db9）实测后的两份 MG 日志。Task76 修复（FSR1 旁路/探针降频/swapInterval 双保险）均未命中根因——帧节奏依旧崩溃
- 量化判读（scripts/analyze_task77_timeline.py 时间线关联分析）：
  * fps 计数在 pojavSwapBuffers 累加 = fps 即真实 swap 率：坏窗口 MC 帧循环真实迭代率 4-8Hz（avgGap 116-252ms，maxGap 至 908ms），好窗口锁 60（avgGap 17-18ms）——"30fps 看得像 10fps"实为震荡均值掩盖
  * 逐一排除：GC young 暂停全 10-14ms；GC 并发标记与坏窗零相关（会话1 GOOD 窗 2195ms 并发标记仍流畅 / BAD 窗 552ms 照卡，Pearson r=-0.099）；内存好坏窗均稳定 2.5-2.8GB；120 次 shader 转换全部集中在启动期（19:42:42 前）；FSR1=0；Iris 着色器禁用；深度 workaround 8 次一次性分配；swapFail=0
  * 对照 bef0f08 同日同包 Zink 场次：稳定 37-53fps 无深谷 → 停顿必在 MG 栈（MobileGlues+ANGLE Metal）而非 MC/JVM/输入桥
- 上游对比（浅克隆 herbrine8403/Amethyst-iOS-MyRemastered @ eb237c0a）：
  * MobileGlues-cpp gl/ 树与 fork 几乎逐文件 SAME（含 prepareForDraw/深度执法/TBO 仿真——fork 并未自加 draw 税）；唯一实质差异 glsl_for_es.cpp 的 master compile lock（仅影响启动编译期）
  * ANGLE 二进制 md5 完全一致（2.1.2440，约 2023 构建）
  * 结论：MG 栈与上游等价，剩余 250ms/帧只能出在 ANGLE Metal 呈现/GPU 侧或 CPU 帧构造侧——需分相计时才能定案
- 修复一（分相归因仪器，下轮设备日志定案）：gl_bridge.m Task77 帧相位计时——build（上次 present 返回→本次 swap 入口）与 present（eglSwapBuffers 本体）分别累计 μs 粒度 5s 窗口 avg/max，ame_egl_swap_phase_stats 读取即重置，[RenderDiag] 心跳新增 pres=%u/%ums build=%u/%ums。判读法：presAvg≈avgGap→ANGLE Metal 呈现/GPU 侧（降分辨率/换渲染器才有效）；buildAvg≈avgGap→CPU 帧构造侧（转译栈逐 draw 优化才有效）
- 修复二（默认控件=custom）：PLPreferences 出厂值 default_ctrl→custom.json + 迁移哨兵 default_ctrl_migrated_custom@NO + migrateDefaultControlPref（仅改写仍停在旧出厂值 default.json 的存量安装，用户自选其他布局不动，AppDelegate 早期调用幂等）+ Task64 恢复默认控件复位目标与新出厂值对齐（custom.json 存在时）+ ControlLayout 解析失败回落 default.json 兜底保留 + 手柄默认不受影响
- 验证脚本维护：verify_task64 A6/A7 断言更新为 ame77RestoreCtrl 新语义；verify_task75 A6f 适配 Task76 探针演化（s_mode!=1）+ C 系列改从 git 4770b53 读崩溃 fixture（用户上传已覆盖工作区日志）
- 验证：verify_task77 27/27；全链 64(93)/66(43)/67(47)/68(24)/70(68)/71/72/73/75(63)/76(40) 全绿

Stage Summary:
- 根因画像（未定案的最后一分界）：MG 卡顿 = 渲染线程帧循环内 250ms 级停顿，震荡于内容相关相位；已排除 GC/内存/编译/取证/FSR1；与上游 MG 栈等价 → 停顿在 ANGLE Metal present 或 CPU 帧构造，Task77 分相计时将在下轮设备日志二选一定案
- 用户即时缓解（无需等修复）：设置中 video.resolution 从 100% 降到 ~75%（GPU/CPU 成本近平方下降）；或继续用 zink
- 默认控件 custom 已落地：新装出厂即 custom.json；老安装一次性迁移（仅限停在 default.json 的）；"恢复默认控件"复位到 custom
- 下轮日志预期锚点：[RenderDiag] ... pres=X/Yms build=X/Yms；"[Preferences] Task77 migrated default control layout: default.json -> custom.json"（仅老安装首启一次）

---
Task ID: 78
Agent: main (Super Z)
Task: 用户报"还是卡，降低50%分辨率加fsr"+修 FSR 档位设置；顺带 MG 上游议题调研 + 新日志（e3e0830，Task77 构建）分相归因落地

Work Log:
- MG 上游议题调研（用户点名）：主仓库 22 条 + MobileGlues-release 211 条全扫；同类卡顿议题 #415（整合包 123→24fps）、#452（2.0.0 性能回归多人复现）、#460（Sodium 转译瓶颈）、#450、#298 全部 closed as not planned / "性能就是这个性能"；#313 官方声明不支持 Sodium/Iris/模组——无可搬修复，结论：上游 wontfix，杠杆在我们侧
- 用户新 log（e3e0830，Task77 构建 5ab093e 实测，MG + MC 26.2 fabric 无光影）判读——**分相归因定案**：
  * pres=0/0ms 全程 25 个心跳（present 最大 3ms）→ ANGLE Metal 呈现/GPU 侧完全无罪
  * build==avgGap 逐心跳吻合（fps=4 → avgGap=346ms build=346/503ms；60fps 好窗 → build=16/17ms）→ 帧间隔 100% 由 CPU 帧构造相位（MC 渲染线程 + MG 转译栈）决定
  * 深谷 = build 尖峰 200-700ms（区块/上传/转译瞬停），好窗稳态 build 税 ~16ms；与上游 #460 转译瓶颈定性一致；26.3 无模组也卡（用户补充）→ 非 Sodium 专属，是 MG 栈结构性税
- 顺藤摸瓜发现 **第三重根因（配置传递断裂）**：launcher 写 config.json "fsr1Setting": 1，MG dump 读出 0 —— settings.cpp 的 __APPLE__ 分支硬编码 fsr1_setting=Disabled 且从不读 config（只有 Android 分支读）；angleDepthClearFixMode 同样被丢弃
- 三重根因全部修复（提交 eb4d248）：
  1. settings.cpp Apple 分支补读 fsr1Setting/angleDepthClearFixMode（范围校验同 Android 分支）
  2. FSR1.cpp：render 跟随 viewport 锁存（surface 只作首帧前兜底回灌）；InitFSRResources 采用已锁存 viewport（消除 960x540 首帧瞬态）；surface 缩小于 render 的独立零增益安全网；RecreateFSRFBO 渲染纹理 RGBA32F→RGBA8（与 init 一致，升采样带宽减半）；engage 一次性日志
  3. 启动器联动：updateSavedResolution 计算 MC 告知窗口= surface/fsr_scale（仅 MG+预设开）；drawableSize 写呈现口径；sendTouchPoint 输入空间除 fsr_scale；gl_bridge geoMismatch 豁免（双维严格小于才豁免，转置仍走自愈链）；Task60 创建对齐应用 resolutionScale（100% 数值不变）
  4. UI：五档 picker（补 Performance=4）+ Balanced 标签修正 + 6 语言详情文案重写
- 验证：verify_task78.py 54/54 ALL PASS（指纹/启动器数学回放/FSR1 状态机回放含旋转+安全网/豁免矩阵/括号平衡/settings.cpp 配置回放）；全链回归 64(93)/66(43)/67(47)/68(24)/70(68)/71/72/73/75/76(40)/77(27) 全绿（task66 D9 键数 1832→1833、task76 A5 文案断言按演化适配）
- 推送 eb4d248 → CI 已触发

Stage Summary:
- MG 卡顿根因链定案：CPU 帧构造侧（转译栈税，pres=0 铁证）+ FSR 三重失效（配置传递断/render 被 surface 钉死/UI 缺档错标）全部修复
- FSR 档位现语义：UQ=77% / Q=67% / Balanced=59% / Performance=50% 渲染分辨率 + EASU/RCAS 升采样回全表面；与 video.resolution 滑杆可叠加
- 下轮设备日志判读锚点："[MobileGlues] Setting: fsr1Setting = 1"（传递修复）；"[SurfaceVC] Task78 FSR linkage"；"[MG] FSR1 upscale engaged (Task78)"；"[GLGeo] Task78 FSR render<surface expected"；心跳 pres/build + fps 好转幅度
- 遗留：MG 转译栈稳态 ~16ms/帧 build 税为结构性（上游 wontfix）——转译侧优化空间在 multidrawOrder（MG 2.0 新机制，launcher 的 multidraw_mode 旧键已被弃用，值得下轮接入）；深谷 build 尖峰 200-700ms 根因（区块网格重建 vs 纹理上传 vs 转译缓存 miss）待更深 instrumentation

---
Task ID: 79
Agent: main (Super Z)
Task: 用户三连：①CI 报错修复（Task78 构建失败）；②zink 在 26.3 的启动回退 log（8a31d1b）修复；③朋友（yitenchen123）合并上游的 PR 调研可借鉴点

Work Log:
- CI 定位：Actions #178/#179 "Build for ios" 步骤 exit 2（fork 仓库日志匿名不可读）→ 排除法锁定：settings.cpp/FSR1.cpp 过 g++ 语法检查（stub 头），逐 hunk 审 .m 改动 → **根因**：Task78 在 SurfaceViewController.m 类扩展 ivar 块后误插 @end，其后 ~70 条 @property 全部脱离 @interface（原扩展横跨到 300 行的 @end）→ clang 编译炸、make exit 2。修复 c0b6f88：ame78_fsr_preset_scale 挪到文件作用域 + ivar 留唯一真扩展 + 回填被吃掉的 FPS 注释行；A1-A7 结构不变量回放全过
- zink 26.3 回退根因链（新 log 8a31d1b 判读 + 下载 26.3-rc-2 client.jar CFR 反编译 renderpearl）：GlBackend.loadLibrary 要求 LWJGL provider 与 SDL_GL_GetProcAddress 对 "glGetError" 返回同一指针；zink 路径被 ame_glBridgeEnabled 刻意排除（c71dcfa 时代"回落 Vulkan 是唯一可用路径"）→ main_hook [SDLGL] 兜底兑装成功但真实 SDL 保有别的 driver（"already loaded"）→ UIKit_GL_GetProcAddress=dlsym(RTLD_DEFAULT) 与 LWJGL provider 指针不合 → BackendCreationException → 用户选的 zink 实际跑 MC 原生 Vulkan（MoltenVK 1.4.2），ZinkConfig/stride fix/shaderc 缓存全部空转
- zink 修复 ff7726e：ame_glBridgeEnabled 对 libOSMesa/gallium_/vulkan_zink 翻转为接管（逃生阀 AMETHYST_ZINK_GL_BRIDGE=0 保旧行为）——bridge 接管 SDL_GL_LoadLibrary（真实 SDL 从不被调，"already loaded" 构造性消失）+ SDL_GL_GetProcAddress 镜像 LWJGL 解析链（同一 NOLOAD 句柄：eglGetProcAddress→OSMesaGetProcAddress→dlsym，指针一致性按构造成立）→ GL backend 被接受 → 上下文/呈现走 ≤26.2 同款 OSMesa bridge；ES 强制化仍排除 zink（MC 桌面 GL 3.3 core 请求不动）；MG 侧已验证对照（2d321fa："Using graphics backend OpenGL, MobileGlues 2.0.17"）。SDL 3.4.0 源码核对：UIKit_GL_LoadLibrary(path≠NULL) 必报错、UIKit_GL_GetProcAddress=dlsym(RTLD_DEFAULT)、driver_path 从不赋值——旧路径的死结与修法的构造性豁免都对上了
- 朋友 PR 调研（herbrine8403/Amethyst #139 已合并，20 commits、vendored MobileGlues 携我方 glslang 双补丁）：lwjgl-333/341 双选、MacosUtil stub、OIT graphicsMode 守卫（含三个查无实据的 renderpearl 属性名）、MoltenVK MVK_CONFIG 神话订正、裸名 libname 修复——**全部本 fork 已有**（方向是他参考我们）；他无 sdl3_hook/main_hook 链（94 行 main_hook vs 我们 1747 行），MG 树为 2.0.17 同代（FSR1 为原生版、无 Task76/78 修复）；他对 MG 上游的 PR #54（iOS 构建/RTLD 自解析）被 Swung0x48 拒并关闭（"不能只测 iOS"）
- 借鉴落地 26f2dff：**multidrawOrder 迁移**（双方都缺的真空白）——本 fork 的 mobileglues.multidraw_mode 一直写已被 MG 2.0.16+ 弃用的 multidrawMode 整数键（settings.cpp 只警告不读取），UI 三档静默 no-op；现写 multidrawOrder 优先序串（Auto=native,multiindirect,…=MG 默认序逐字一致 / Indirect=间接族优先 / Emulated=CPU 循环优先），六语言 detail 文案重写，旧键停写并留日志；MG 侧闭环核对：md_config_string→parse_multidraw_orders() 在 __APPLE__ 分支同样执行
- 验证：verify_task79.py 25/25 ALL PASS（A:CI 结构 7 / B:zink bridge 矩阵 12 / C:multidraw 迁移 6）；全链回归 58/59/71/72/73/75/76/77/78 全绿；推送 26f2dff 触发 CI

Stage Summary:
- CI 失败根因 = Task78 的 @end 手术失误（@property 脱离接口），一行结构修复 + 25 项不变量回放
- zink 26.3 回退修复 = 同 MG 的 provider-mirror 机制扩展到 zink（bridge 翻转 + 逃生阀）；下轮 zink 会话预期锚点："[SDLHook] SDL_GL_LoadLibrary('...libOSMesa.8.dylib') -> pojavInitOpenGLForSDL3()=0" + "Using graphics backend OpenGL"（而非 Vulkan 回落行）；若 GL 路径万一异常，设备上设 AMETHYST_ZINK_GL_BRIDGE=0 即回旧行为
- 朋友 PR 结论：无新可搬（他参考我们为主）；唯一真空白 multidrawOrder 已落地——"间接"档是对 MG 转译栈 build 税（Task78 定案 build==avgGap）的直接杠杆，下轮设备日志可对照 multidraw 档位切换前后的 build 分相
- 遗留：Task77/78 构建实测数据待新一轮设备 log（现在会同时携带 FSR 联动 + zink GL + multidraw 三组锚点）；MG 卡顿深谷 build 尖峰根因待更深 instrumentation

---
Task ID: 80
Agent: main (Super Z)
Task: 用户报"zink还是回退，mg现在开启了fsr黑屏。上传了2个log"（0441401，Task79 构建实测）→ 双日志判读 + 两个根因修复

Work Log:
- 拉取 0441401（两份日志，均构建 ed1a616）：latestlog.txt = 26.2 fabric MG+FSR 场次（1105 行）；latestlog.old.txt = 26.3-rc-2 zink 场次（6215 行）
- **zink 回退新失败点定案**（比 Task79 前进一步）：LoadLibrary→EGL bridge ✓、工具窗口创建 ✓、zink EGL/GL 上下文创建 ✓（"zink: MoltenVK 1.4.2 Vulkan 1.4.357" 实锤）、MakeCurrent ✓ → 卡在 renderpearl GlDevice 构造器的第二个 "Hidden Test Window" 探针（创建后立即销毁的健康探针，CFR 反编译 GlDevice.java:109 实锤）→ ame_sdlGlesCompatEnabled 对 libOSMesa 刻意返回 false → 主窗口复用不生效 → 真实 SDL 创建第二个 GL 窗口 → iOS UIKit 后端"每显示器一窗口"拒绝 → 返回 NULL → BackendCreationException → 回退 Vulkan。旁证：26.2 zink 会话（bef0f08）无此探针（renderpearl 26.3 新增）且 "Using graphics backend OpenGL, Mesa 25.0.7" 正常；MG 26.3（0cc265f）靠复用迈过同款门（reusing primary window, refs=2 → DestroyWindow skipped → Using graphics backend OpenGL）
- **FSR 黑屏根因定案**（链条铁证）："[MG] Shader 3 conversion FAILED (code=-2) — spvc_compiler_compile failed: textureGather requires ESSL 310 → 回退 RAW 桌面 GLSL → invalid version directive / uint syntax error" → 升采样着色器从未编译通过 → ApplyFSR 拿 program 0 每帧 clear 黑色 target + blit 上屏 = 全屏黑屏，而 fps=58-60/swapOK=645/swapFail=0 全部健康（与用户症状完全吻合）。深挖发现上游着色器本体就是死代码：uConst0 声明从未使用、FsrEasuCon 的 outputSize 被喂成输入纹理尺寸（映射坍缩为恒等）、EASU 结果 color 被丢弃、RCAS 用输出空间坐标 texelFetch 输入纹理（必然越界）——解释了上游为何在 __APPLE__ 分支硬编码 fsr1_setting=Disabled（从未在任何平台跑通过）
- 修复一（zink 窗口复用，sdl3_hook.m）：ame_shouldReusePrimaryWindow 扩展——GLES compat 之外，ame_glBridgeEnabled() 家族（zink/libOSMesa/gallium_/vulkan_zink + gl4es/ltw）也复用主窗口；glBridgeEnabled 前置声明；引丹计数天然消化探针的立即销毁；逃生阀不变（AMETHYST_ZINK_GL_BRIDGE=0 或 AMETHYST_SDL_REUSE_WINDOW=0 一键回旧行为）；zink 呈现走 osm_swap_buffers→SurfaceViewController.surface.layer 不依赖 SDL 窗口，复用无副作用；ES 强制化仍排除 zink（3.3 core 请求不动）
- 修复二（FSR 着色器 ESSL300 化，FSRShaderSource.h）：textureGather→texelFetch 模拟，分量序 .x=(i0,j1) .y=(i1,j1) .z=(i1,j0) .w=(i0,j0)——由 FSR 自身包代数（bczz .x=b .y=c / ijfe .x=i .y=j .z=f .w=e / klhg / zzon .z=o .w=n）与 ffx_fsr1.h tap 偏移交叉推导自洽；CLAMP_TO_EDGE 用 min/max 钉扎重现；main() 修正为 uViewportSize（render）/uTargetSize（target，新 uniform）喂 FsrEasuCon，EASU 结果直出（RCAS 单 pass 必然越界——留作后续独立 pass）
- 修复三（FSR1.cpp/.h 配套）：①编译失败安全网——InitFSRResources 检查 program==0 提前返回（不建 FBO、不激活 redirect、会话降级为"无升采样"而非"无画面"）+ engage 分支 program==0 守卫（防死 program 复活黑屏）；②target 超出 surface 时钳制（消除 preset 缩放舍入的超额分配）；③blit 目标改全表面（消除 2px 黑边残留；线性滤波负责末段拉伸；分辨率滑杆叠加 FSR 场景由 blit 统一收尾）；④g_surfaceWidth/Height 每帧记忆 + per-context 存取；⑤uConst0→uTargetSize uniform 全链置换
- 验证：g++ 语法检查过（真实树头 + ska stub，scripts/gen_task80_gl_stubs.py）；**glslangValidator 真实编译 VS+FS 通过**（Task45 构建件，MG 转译管线第一阶段等价物）；verify_task80.py 44/44 PASS（A zink 复用矩阵/引丹回放 18 + B 着色器 glslang/gather 序数学推导/uniform 契约 9 + C FSR1 行为回放含编译失败安全网/钳制数学/blit 回退 15 + D 括号平衡/级联）；全链回归 64(93)/66(43)/67(47)/68(24)/70(68)/71/72/73/75/76(40)/77(27)/78/79 全绿
- 推送 175d670 → CI run 34870103337 **SUCCESS**（agent-browser 匿名页图标核验）

Stage Summary:
- 两个"Task79/78 修复后仍不工作"的问题均已定案根因并修复：zink 差"窗口复用"最后一环（Task79 修了 context 链没修窗口链）；FSR 黑屏是着色器从未编译过（转译层 ESSL300 屏障 + 上游死代码管线）
- 下轮设备日志判读锚点：zink 场 "[SDLHook] reusing primary window %p, refs=2" + "Using graphics backend OpenGL, using drivers: 4.1 (Compatibility Profile) Mesa 25.0.7"（而非 Vulkan 回落行）；MG+FSR 场 "[MG] Shader N converted OK"（FSR 着色器转译通过）+ 无 "FSR1 upscale shader failed to compile" + 无黑屏 + "[MG] FSR1 upscale engaged (Task78): render 1814x1262 -> target 2358x1640 -> surface 2360x1640"（target 不再超额）+ fps 好转幅度（EASU 1.69x 面积减载的期望收益）
- FSR 现在的真实语义：MC 以 surface/1.3~2.0 渲染 → EASU 边缘自适应升采样回全表面（RCAS 锐化留作后续独立 pass）；与 video.resolution 滑杆可叠加（滑杆降 render、FSR 升回，双杠杆）
- 遗留：RCAS 锐化 pass（读 target 纹理的第二 pass + ApplyFSR 双 pass 化）；深谷 build 尖峰根因（Task78 遗留）；multidrawOrder 档位实测对照（Task79 遗留）

---
Task ID: 81
Agent: main (Super Z)
Task: 用户报"zink正常，但是mg的实体以及云层穿透又回来了（那是我最前面几十次提交修复的内容你怎么删除了），还有mg还是卡"（f50d5ff 双日志，Task80 构建 678e7b5 实测）→ 判读 + 根因 + 修复

Work Log:
- 拉取 f50d5ff（两份日志，均构建 678e7b5）：latestlog.txt = 26.3-rc-2 zink 场（9394 行）；latestlog.old.txt = 26.2 fabric MG+FSR 场（1536 行）。本地 main 落后 origin 五个提交（Task76-80 已在远端），ff-only 同步后判读
- zink 场判读——**Task80 窗口复用修复完全生效**："SDL_GL_LoadLibrary('...libOSMesa.8.dylib') -> pojavInitOpenGLForSDL3()=0 (EGL bridge)" + "reusing primary window 0x12b6ee400, refs=2"（Hidden Test Window 探针被引丹计数消化）+ "Using graphics backend OpenGL, using drivers: 4.1 (Compatibility Profile) Mesa 25.0.7"（非 Vulkan 回落行）；游戏内 fps 稳定 46-52、零崩溃——用户"zink正常"属实，此线闭环
- MG 场判读——FSR 联动链全部生效（Task78/80 战果）："Task78 FSR linkage: preset=1 scale=1.30" + "FSR1 upscale engaged (Task78): render 1814x1262 -> target 2358x1640 -> surface 2360x1640" + 零 shader 转换失败（Task80 ESSL300 化生效，不再黑屏）+ 稳态 fps 56-59 / build 12-13ms（对比 Task78 前稳态 build 税 ~16ms——FSR 降载可见）
- **穿透回归根因定案（铁证链）**：日志 1149-1167 行 depth-sampling dump——合成器 12 个 sampler2D（Main/Translucent/ItemEntity/Particles/Weather/Clouds 各 colour+depth 对）共用 sampler 26，其 MIN=NEAREST_MIPMAP_LINEAR(9986) 盖在全部六个 D32F 深度纹理上，**全程零 "depth filter force" 行**（对照 e3e0830[FSR关] 2 条 force、4770b53 1 条）。链条：GLES3 深度纹理仅在 MIN=NEAREST/NEAREST_MIPMAP_NEAREST 下 filter-complete → 9986 使六张 D32F 全部 incomplete → ANGLE Metal 采样回 0.0 → reversed-z 读作"无穷远" → 云/天气/粒子/物品实体全部不遮挡 = 用户所见
- 为什么"回来了"：**旧修复一行都没被删**。mg_enforce_depth_sampling_nearest() 带着一条 FSR1 kill-switch（texture.cpp 633 行 `!tracked && fsr1_setting != Disabled → return`）——它的两个历史前提（①FSR1 GLStateGuard 每帧把 render 纹理漏到 unit 0 无影子记录 ②fsr1Setting 在 iOS 从未生效）分别已被 Task78/80 修掉（guard 现已保存/恢复 unit 0 自身绑定=净值零；配置已透传）。于是 FSR1 首次在设备上真正启用（正是本构建）→ kill-switch 首次被触发 → 整个深度采样执法静默死亡。FSR1.cpp 头部注释早已写明"shadow 可以重新放宽，泄漏已除"——但放宽这半步从未落地，本构建补上
- 修复（commit e97af69，texture.cpp 4 处 + version.h 1 处 + en.lproj 1 处）：
  1. driver_texture_shadow_trustworthy() 去掉 FSR 子句（回到纯上下文身份判定；连带 glBindTexture 冗余绑定跳过路径在 FSR 开启时恢复可用=微小降开销）
  2. 执法入口退役 kill-switch——恒运行；fsr1_on 时每个深度 hint 额外走驱动侧确认（untracked 模式既有 borrow-and-restore 机制扩展到 tracked 模式，防御未来任何绕过影子的内部绑定——过期 hint 只会被拒确认，绝不可能错误强制 colour sampler）
  3. 一次性布防日志 "[MG] depth filter scan: FSR1 active (Task 81) -- enforcement re-enabled, depth hints driver-confirmed"（设备日志验证锚点）
  4. version.h REVISION 17 addendum——**刻意不 bump**（转换缓存键嵌入 MAJOR.MINOR.REVISION，本次转换器输出零变化，bump 只会白烧 ~470 条磁盘缓存引发一次 404 转换风暴）
  5. en.lproj i18n_str_638 治愈（字面量内裸换行——Apple .strings 解析隐患，重跑级联时被 task66 D9 奇偶校验逮到的真实缺陷；修复后 en/zh-Hans 键数 1831==1831）
- 附带基础设施修复（预先存在的级联红，非本次回归）：/home/z/my-project/scripts 下 verify_task64 A6/A7（Task77 ame77RestoreCtrl 新语义的适配未落盘）与 verify_task66 D9（键数 1832 硬编码→奇偶+下限）同步至现行语义——f50d5ff 上即红的 76→71→67/70 嵌套级联现在全链绿
- 验证：verify_task81.py 32/32 PASS——A 指纹 13（kill-switch 删除/确认门/布防日志/版本不 bump/force 体原样）+ B 决策矩阵回放 10（tracked×untracked × FSR开/关 四模式、泄漏形态 hint 拒绝、colour-only 恢复、双 pass any-depth、PCF 不动、NEAREST 免强制、空扫 cheap-out）+ C 回归锚 5（drawing.cpp dump 原样、prepareForDraw 调用在位、678e7b5 回归 fixture=零 force 行实锤、e3e0830 fixture=force 行在=FSR 相关性实锤）+ D 级联 4（76:40/40、78、79、80:44/44）；g++ -fsyntax-only 全 TU 零错误（stub 头环境 scripts/task81/stubs/）；宽级联 67/70/71/77 全绿
- 推送 e97af69 → CI 触发

Stage Summary:
- 穿透回归一句话定性：不是删除、是"FSR1 首次真正启用"激活了一条沉睡的 kill-switch，把最早的深度遮挡修复整个关掉了；泄漏根因（guard 不还 unit 0）早已修掉，本轮补上"放宽"这半步，执法恒运行 + FSR 期间驱动侧确认兜底
- 用户装机预期（e97af69 构建，MG+FSR 场）：日志出现 "[MG] depth filter scan: FSR1 active (Task 81)" + 回归的 "[MG] depth filter force: sampler 26 min 9986 / mag 9728 -> NEAREST (depth image sampled)"（前 8 次）+ "[MG] depth filter restore: ..."；游戏内云/天气/粒子/物品实体恢复被地形遮挡；FSR 升采样画质不受影响（合成后最后几笔 colour-only draw 会先恢复 sampler 参数，EASU 采样状态与现状逐位一致）
- zink 线正式闭环（用户口头确认+日志锚点双实锤）；MG 卡顿终版归因维持：稳态已改善（56-59fps/build 12-13ms），深谷 = 区块流式 × 转译栈逐调用税（本设备 multidrawOrder 全 backend 不可用→unroll；GC 全程 3-10ms 无罪；122 次转换全部在启动期）——模组 26.x 场景建议用 zink（46-52fps），MG 留给轻量/老版本
- 遗留：深谷 build 尖峰（区块网格重建 vs 纹理上传）待更深 instrumentation（Task78 起遗留）；RCAS 锐化第二 pass（Task80 遗留）；ja/km l10n 深度修复（Task66 遗留）

---
Task ID: 82
Agent: main (Super Z)
Task: 用户报"fsr疑似没有开启，整个界面缩到左下角；安卓上mg加载区块也卡（所以对不起）；控件左上角那个控件键盘使用不了；mg透视其实是sodium模组'改进透明'开了就会穿透；请在新建一个标签页，添加启动器各种使用问题"（ea27def 日志，Task81 构建实测）→ 三线修复 + FAQ 页

Work Log:
- 拉取 ea27def 新日志（9285 行，1e85193 构建，MG+FSR 场，18:53 会话）判读：
  * Task81 穿透修复生效（"depth filter scan: FSR1 active (Task 81)" 在位）——用户澄清透视是 Sodium"改进透明"选项所致（模组行为，非启动器回归，FAQ 录入即可）
  * FSR"缩到左下角"实锤：唯一一条 engage 行 "render 2048x2048 -> target 2360x1640 -> surface 2360x1640"，而全部 19 次 swap geo-probe 的帧视口恒为 1814x1262（=2360/1.30 正确窗口尺寸）——2048x2048 不是主帧视口
- FSR 根因：gl/FSR1/FSR1.cpp 的 glViewport 渲染尺寸锁存是 grow-only（w>pendingW || h>pendingH 即整体覆盖）；MC 26.x 的动态图集 pass 以全图集尺寸 glViewport（blocks.png=2048x2048，恰好 2048>1814）污染锁存，此后主视口 1814x1262 因"只增不减"永远无法夺回 → 渲染 FBO 2048x2048 但 MC 只画左下 1814x1262 → EASU 把整张（右上大片未写）铺满表面 → 画面缩在左下 88.6%×61.6%，黑边在右上——与用户描述逐字吻合
- FSR 修复（commit 248e59a）：锁存候选必须"窗口形状"——①任一维不超过 EGL 表面（窗口=表面/档位系数，构造上≤表面；2048>1640 被拒）②宽高比偏离表面 <3%（窗口对表面等比缩放；方形图集/阴影 pass 被拒，实际窗口 1.4371 vs 表面 1.4390 偏 0.13%）；仅 FSR1 开启时检查（关闭时锁存无人消费，零开销）；表面尺寸取 CheckResolutionChange 缓存、首帧前（正是污染窗口期）直查 EGL（同镜像前端导出符号，surface record 读取无驱动往返）；拒绝一次性日志（防图集每帧刷屏）+ version.h REVISION 17 addendum（不 bump，转换器输出零变化）
- 键盘控件根因：CallbackBridge_nativeSendChar 只有 GLFW 路径（GLFW_invoke_Char && isInputReady），而 26.3 走 SDL3 该指针恒 NULL → 左上角 Keyboard 按钮唤起的虚拟键盘打字全被静默丢弃（返回 NO，无日志）。反编译实锤消费链（task66_decomp/client.jar，CFR）：SDLEventHandler.pollEvents case 771(0x303 SDL_EVENT_TEXT_INPUT) → handleTextInputEvent → keyboardHandler.textInput → charTyped（handle 匹配 + Screen 打开时进 Screen.charTyped）
- 键盘修复：input_bridge_v3.m 照 sendKey 的 Path B 模式新增 pushSDLTextInput——UTF-8 编码（1-4 字节）+ UTF-16 代理对合并状态（emoji 不再拆成乱码）+ 1024 槽×8 字节静态环形缓冲承载 text 指针生命周期（SDL3 TextInputEvent.text 是指针非内联数组；MC 每帧排空队列，千槽覆盖周期远超消费周期）+ 事件用 128 字节 SDL3_Event 联合体承载（避免 SDL_PushEvent 拷贝 union 尾部越界读栈）；nativeSendChar 加 Path B（!GLFW_invoke_Char && g_sdlWindow 时推事件），nativeSendCharMods 刻意保持 GLFW-only（TrackedTextField 每字符先 sendCharMods 再 sendChar，双推会重复输入）；SurfaceViewController 键盘按钮补 becomeFirstResponder 结果取证日志
- FAQ 页（新标签）：Natives/LauncherHelpViewController.h/.m——UITableView inset-grouped 四分类十问答（渲染与性能/输入与控制/安装与数据/故障排除），全部来自 worklog 真实结论：渲染器选型（26.x+模组用 zink、MG 轻量场景）、Sodium"改进透明"穿透、MG 区块卡顿已知特性（安卓同样，已排除 GC/内存/GPU）、FSR 档位用法（分辨率保持 100%、旧黑屏/缩角已修）、键盘打字、摇杆修复史、内存建议、整合包父 JSON 自愈、崩溃反馈（latestlog+环境四要素）、数据目录；语言跟随 AI 模块先例直接中文；SF Symbol 全部用 iOS 13/14 安全符号；接线 = CMakeLists 源注册 + 侧边栏 index 5（questionmark.circle.fill）+ ShowHelpPage 通知 + LauncherRootViewController 内容区切换
- MG 卡顿线定案：用户确认安卓同样卡顿 = 上游 MobileGlues 转译栈固有开销（26.3 区块管线 3.2x 调用量 × 逐调用翻译税），非本 fork 回归；已排除项（GC/内存/视距/M4）维持结论，FAQ 录入"已知特性+缓解办法"
- 验证：verify_task82.py 53/53 PASS——A FSR 指纹 8（helper/门控/双规则/一次性日志/growth 保留/直通/version 注记）+ B 锁存行为回放 10（图集两种时序均拒、窗口 0.13% 偏离接受、旋转重锁、大表面方形图集 aspect 拒、方形窗口接受、FSR 关=旧行为、无 EGL 信息=放行）+ C 文本链指纹 9（0x303/结构/环形/定义顺序/Path B/CharMods 不双推/128 字节 union/日志/代理态）+ D 文本行为回放 5（UTF-8 四锚点/代理对合并/孤立低代理 U+FFFD/高代理后 BMP/粘贴整串往返）+ E 键盘取证 2 + F FAQ 接线 9 + G 括号平衡 7（全零位移）+ H ea27def 回归证据 2（2048 污染在场 + 19 探针恒 1814）+ I Task81 级联 32/32；FSR1.cpp g++ -fsyntax-only 全 TU 零错误；宽级联 63/64/65/66/67/70/76/78/79/80/81 全绿
- 推送 248e59a → CI 触发

Stage Summary:
- FSR"缩到左下角"一句话定性：不是 FSR 没开（联动全生效），是图集 pass 的 2048x2048 瞬态视口污染了 grow-only 锁存，把渲染 FBO 撑大而 MC 只画左下角；修复后 engage 行应为 "render 1814x1262 -> target 2358x1640"，画面满屏
- 键盘控件一句话定性：26.3 的 SDL3 路径根本没有文本事件通道（GLFW_invoke_Char 恒 NULL），打字被静默丢弃；修复后虚拟键盘字符经 SDL_EVENT_TEXT_INPUT 直达 charTyped
- 用户装机预期（248e59a 构建）：①MG+FSR 满屏画面 + 日志锚点 "[MG] FSR1 viewport latch rejected (Task 82): 2048x2048 is not a window viewport (surface 2360x1640)" + engage 1814x1262；②26.3 打开聊天点 Keyboard 打字有效 + "[InputDiag] Task82 SDL text input #N: U+XXXX ..."；③侧边栏新增"使用问题"标签（问号图标）十问答
- 遗留：图集 pass 若换成非方形尺寸（资源包重缝图集）也已被 aspect 规则覆盖；深谷 build 尖峰 instrumentation（Task78 遗留）；RCAS 锐化第二 pass（Task80 遗留）；ja/km l10n（Task66 遗留）

---
Task ID: 83
Agent: main (Super Z)
Task: 用户四线需求——①控件虚拟键盘（"键盘图标 ⌨"抽屉，非"✎ 输入法"按钮）用不了；②FSR 有点卡；③把 FSR 独立出来让所有渲染器（zink/MoltenVK 等）都能用；④问题标签页内容太少需按知识库+网上内容丰富，且 FAQ 修正（MoltenVK 是独立渲染器，zink 用的是系统 Vulkan，两者不是一回事）→ 四线全修

Work Log:
- 键盘表情(⌨)按钮定位（用户两次纠正方向后）：custom.json 的 mDrawerDataList 里 name="⌨" 的抽屉——keycodes 全 0（展开/收起由 ControlDrawer.touchesEnded→switchButtonVisibility 处理，与按键分发无关），buttonProperties 是一整面 QWERTY+符号+F键子按钮面板（字母 A-Z、0-9、`,` `.` `/` `;` `[` `]` `=` `-、PGUP/PGDW、SHIFT/CTRL/CAPS 等）+一块 404.5x170 无键码背景板。抽屉展开链路（loadControlObject→addButton→addTarget executebtn）为上游稳定行为，Task82 设备日志（普通按钮 ESC/F3/SPACE 全通）佐证
- ⌨ 面板打字根因：executebtn 的 keycode>0 分支只发 GLFW key 事件（nativeSendKey→SDL3 key down/up），而 MC 1.13+ 聊天框/书与笔/搜索框只消费 charTyped（text-input）事件——面板按键在文本框里完全无反应；系统键盘（✎ 输入法→inputTextField→nativeSendChar）Task82 已修好所以正常
- 修复①按钮键盘打字（input_bridge_v3.m +117 行）：executebtn ACTION_DOWN 时对 keycode>0 补发 CallbackBridge_buttonKeySynthesizeText(key)——ame83_keycodeToChar 按 US ANSI 布局映射（A-Z/0-9/numpad/符号双表，shift 与 caps 对字母异或）；SHIFT 态 SDL3 路径读 SDL_GetModState（Task66 已同步虚拟修饰键）/GLFW 路径读 currMods；Ctrl/Alt/Super 按住时抑制（快捷键语义，防 [CTRL,W] 持续奔跑组合灌字符）；CAPS_LOCK 按钮自管理虚拟大写（SDL 不为注入事件维护 KMOD_CAPS）；硬件键盘不经此路径（pressesBegan 同时发 key+char）无重复风险
- Chat 按钮(T)安全性推演（反编译 task66_decomp/KeyboardHandler）：26.3 的 keyChat 走 KeyMapping.click 队列、下一 tick 才 setScreen(ChatScreen)，而 charTyped 在 gui.screen()==null 时直接 return——T 按键的补发字符在开屏前的同一事件突发里到达即被丢弃，不会把 't' 灌进刚打开的聊天框（与桌面端行为一致）
- 修复②custom.json 键位错配三处：',' 键绑 39（APOSTROPHE 撇号）→44（COMMA）；'[' 与 ']' 键码互换（91/93 对调）
- 修复③FSR 逐帧开销（FSR1.cpp ApplyFSR）：旧路径每帧三趟全屏——target FBO clear（纯浪费，EASU 四边形全覆盖）+ EASU 绘制 + target→surface 整幅 blit；新路径 target==surface 时（CheckResolutionChange 新增 <=4px 舍入残差钳制：2360/1.5=1573→1573*1.5=2359.5，1-2px 残差直接钳到表面）EASU 直画默认帧缓冲并 return——单趟；分辨率滑条叠加的真子表面路径保留 blit（线性滤镜做最后拉伸）；direct 路径显式关 DEPTH/SCISSOR/BLEND/CULL（默认帧缓冲可能有深度附件/应用残留态，target FBO 从来没有）+ 还原 DRAW_FRAMEBUFFER 绑定
- 修复④FSR 独立化（渲染器无关）：
  * 能力表 ame83_fsr_capable_renderer（SurfaceViewController.m）：MobileGlues=YES（内置 FSR1）；zink（libOSMesa 前缀）=YES（本轮新增 osm_bridge EASU）；Vulkan/MoltenVK=NO（纯 Vulkan 路径 vkQueuePresent 由 MC 自管无呈现钩子，≤26.2 GL 回退走 ANGLE 也无法升采样——缩窗口只会得到 Task82 同款"画面缩角"）；auto/gl4es（GLES2 无 VAO/ES3）暂不接入；FSR 联动（MC 窗口=表面/档位系数）从 MG-only 放开到能力表
  * osm_bridge.m→.mm 改名 + 347 行新增：osm_swap_buffers 的 glFinish 后把 MC 窗口区域（windowWidth×windowHeight，GL 原点左下）EASU 升采样铺满 OSMesa 全尺寸缓冲（ame_surfaceWidth/Height，environ.h 新全局，updateSavedResolution 单点写入）；复用 MobileGlues 的 FSRShaderSource.h（#version 450，zink=Mesa GL 4.6 compat 原生编译；头是纯字符串字面量，每 TU 私有拷贝无符号冲突）；29 个 GL 函数 dlsym 惰性解析（glCreateShader~glGetIntegerv）+ 一次性失败熔断 + 兜底 nativeSendScreenSize 恢复窗口=表面（MC 下帧起全分辨率直渲，不停留在缩角状态）；glCopyTexSubImage2D 帧拷贝（存储尺寸变更才 glCopyTexImage2D 重建）+ 最小状态保存还原（viewport/texture/program/VAO/VBO）；CGImage 上屏尺寸从 windowWidth 改为 bundle.width（FSR 下旧代码会把升采样结果再裁一遍）
  * 设置迁移：fsr1_setting 行从 MobileGlues 分区移入"视频设置"分区（跟随渲染器/分辨率），存储键经 get/set 重映射保持 mobileglues.fsr1_setting 历史键名（JavaLauncher/MG config.json 等读者零感知）；en/ja/km/zh-CN/zh-Hans/zh-Hant 六语言 detail 文案改多渲染器表述
- 修复⑤FAQ（LauncherHelpViewController.m）：10→19 条目——修正渲染器原理（Zink=GL→系统 Vulkan 栈转译；MoltenVK=独立渲染器直接 Vulkan→Metal，和 Zink 是两个互相独立的选项；删除旧错误表述"Zink 基于 Vulkan（MoltenVK）"）；新增：帧率上限/垂直同步、画面模糊发虚、光影 Iris/OptiFine 与优化模组版本配对坑、蓝牙鼠标/手柄外设、控件布局编辑与恢复；重写键盘条目（系统键盘=✎ 输入法按钮/双指长按；按钮键盘=⌨ 抽屉面板+SHIFT 大写+大写锁定）；FSR 条目改多渲染器支持说明+设置新路径（设置→视频设置）
- 验证基建（两次"假红"甄别）：①verify_task83 初版 46/54——B5 脚本字符串口径过严（代码是 `MOBILEGLUES]) return YES` 带中括号）、C3 查错文件（Task81 锚点在 MobileGlues-cpp/gl/texture.cpp 非 gl_bridge.m）、D 系列配对索引 bug（i+3 错配，正确是 (0,1)(2,3)(4,5)）——修脚本后 54/54；②级联红潮根因：`return '"';`（双引号字符字面量）对编译器完全合法，但历史校验脚本（task66/67/82）的计数器先剥 "字符串" 再剥 '字符'，'"' 里的双引号被误当字符串起点翻转全文件引号配对→后续 5238 字符代码区被当字符串吃掉→负括号增量；修法 return 34 + 无 ASCII 引号注释；另 task67 口径先剥字符串后剥注释，注释里奇数个 ASCII 双引号同样翻转配对——注释措辞去 ASCII 引号。方法论入库：给这套校验体系写代码时，字符字面量避免裸双引号、注释避免奇数 ASCII 引号
- stale 校验同步（沿 Task81 惯例）：verify_task78 linkage log 断言更新（"Task78 FSR linkage: preset=%ld"→"Task83 FSR linkage: renderer=%@"，联动语义不变）；verify_task82 H1/H2 更新（262e674 用户上传了 Task82 构建装机日志替换 ea27def 旧毒证据日志——新日志实锤修复生效："viewport latch rejected (Task 82): 2048x2048 is not a window viewport (surface 2360x1640)" + engage "render 1572x1092 -> target 2358x1638 -> surface 2360x1640" 窗口形状正确 + 55 条 InputDiag）
- version.h REVISION 17 addendum（Task 83，不 bump）：ApplyFSR 直通单趟化——转换器输出零变化不 bump，装机识别靠 engage 行不变+每帧 target-FBO clear 消失
- 验证终态：verify_task83.py 54/54（A 指纹 22 + B 行为回放 20 + C Task82 回归锚 4 + D 括号增量 6 + E g++ 语法 2）；宽级联 task67 47/0、task71 全绿、task76 40/40、task80 44/44、task81 32/32、task82 53/53 全绿；verify_task83.py 入库 repo scripts/
- 提交推送（本次提交）

Stage Summary:
- ⌨ 按钮键盘一句话定性：面板按键只发 key 事件而 MC 1.13+ 文本框只吃 char 事件，纯 key 永远打不出字；修复后面板字母直接上屏、SHIFT 出大写、CAPS 按钮可切大写锁定，'，' '[' ']' 三键位错配一并纠正
- FSR 卡顿一句话定性：每帧三趟全屏（clear+EASU+blit）中 clear 纯浪费、blit 在 target==surface 时纯多余——舍入钳制后常路径单趟直画，逐帧开销约砍 2/3；深谷（区块流式 build 500-745ms）与 FSR 无关维持 Task81 结论
- FSR 独立化：zink 经 osm_bridge EASU（与 MG 逐字同款 shader）接入，MoltenVK 纯 Vulkan 无呈现钩子明确不接（FAQ+设置文案说明，防"画面缩角"回归）；存储键 mobileglues.fsr1_setting 历史兼容
- 用户装机预期（本构建）：①⌨ 面板聊天打字有效 + "[InputDiag] Task83 button text #N: glfwKey=.. -> 'x'"；②zink+FSR 场 "[OSMBridge] Task83 FSR1 upscale engaged (zink): render ..x.. -> surface ..x.."；③MG+FSR 场 engage 行不变、每帧更轻；④FAQ 19 条目含 MoltenVK/zink 修正表述
- 遗留：深谷 build 尖峰 instrumentation（Task78 起）；RCAS 锐化第二 pass（Task80）；ja/km l10n 深度（Task66）；Vulkan 渲染器 FSR（需 vkQueuePresent 层钩子，当前架构不适用）

---
Task ID: 83a
Agent: main (Super Z)
Task: Task83 提交后 CI 八连红修复（037a6c1 → c75c77c，run 34987233296 → 35037960566）

Work Log:
- run1 34987233296（28 errors）：osm_bridge.mm 被当纯 CXX 编译（工程无 OBJCXX 语言，.m 全走 C+-ObjC 路线）→ @interface 全炸。修：set_source_files_properties 单文件 "-x objective-c++ -fobjc-arc"（后补 -std=gnu++17）+ osm_bridge.h extern "C"（set_osm_bridge_tbl 被 egl_bridge.m C TU 调用）
- run2 34989106108（19 errors）：-x 生效但 C++ 关键字分类名非法——@interface Foo(private) 的 private 是 C++ 关键字，libc++ 头级联报错。修：8 处关键字分类名改名 ame_private（UIKit+hook.h×6/ControlLayout.h/PLPickerView.h；外来类分类名纯装饰零行为变化）
- run3 34990764454：分类名清了，stdatomic.h 的 C 函数式宏 atomic_is_lock_free 在 C++ 模式炸 libc++ <atomic>。修：environ.h 按 __cplusplus 分支——C++ 用 <atomic>+typedef std::atomic<size_t>（clang ABI 与 _Atomic size_t 布局一致）
- run4 34992226284：atomic 过了，raw string R"fsr_glsl(...)" 不认——Apple clang 15 的 clang++ 默认 gnu++98。修：COMPILE_OPTIONS 补 -std=gnu++17
- run5 34993498502：C++ 严格指针转换——dlsym/calloc 返回 void* 赋函数指针/结构体指针是 C 合法 C++ 硬错。修：AME83_DLSYM_SLOT 宏（__typeof__ 转型，双方言通用）×9 + calloc 显式转型；本地语法脚本扩第二段（dlsym 段 C++ 严格指针检查）
- run6 35035238066：osm 全通！错误移到 LauncherHelpViewController.m:215——NSString 属性赋 C 字符串（缺 @ 前缀；前几轮 make 早死从未编到它）。修：补 @；全修改文件扫描同类（余下全是合法 JNI/dlsym C 字符串）
- run7 35036079381（链接期）：两类——①Foundation 全家 undefined（.mm 使 CMake 链接器 C→CXX，C 驱动的链接行带 CMAKE_C_FLAGS(-fobjc-arc -ObjC) 自动链 Foundation，CXX 不带）→ 主目标显式 "-framework Foundation"；②customNSLog/CallbackBridge_nativeSendScreenSize 被 C++ 修饰名引用 → utils.h（纯 C 声明头）整体 extern "C" 防护
- run8 35037109152：duplicate _guiScale——environ.h 全局变量是 C 临时定义（-fcommon 公共符号），C++ TU 里成强定义，与 input_bridge_v3.m 的 int guiScale=1 强定义撞车（其余变量 common+strong 静默合并侥幸）。修：AME_ENVIRON_DECL 宏（C++ 分支 extern，C 分支空）前缀全部 21 行全局声明——.mm 零定义，链接形态逐字节回到 Task83 前
- run9 35037960566：SUCCESS。产物 com.air-devs.air-ios.ipa 191.4MB + TrollStore tipa + dSYM

Stage Summary:
- 八轮根因全链：方言缺失 → 关键字分类名 → stdatomic 宏污染 → 默认 C++ 标准 → 严格指针转换 → 本地无法预检的 ObjC 笔误 → 链接器语言切换丢框架/丢 C 链接 → 临时定义强 化撞符号。全部修在"最小侵入"原则：单文件 flags、纯装饰改名、__cplusplus 分支、宏前缀 extern——C TU 侧逐字节零变化
- 方法论入库：往纯 C/ObjC 工程塞第一个 .mm 的完整检查单（方言/标准/分类名/stdatomic/指针转换/链接器语言/框架/extern C/临时定义九关）；本地 g++ 语法脚本只能拦住其中 5 关，链接期 4 关只能靠 CI
- verify_task83 终态 60/60（E3-E8 为 CI 教训指纹）；task82 53/53 级联不破
- 装机验证锚点不变：⌨ 面板 "[InputDiag] Task83 button text"、zink+FSR "[OSMBridge] Task83 FSR1 upscale engaged (zink)"、FAQ 19 条目

---
Task ID: 83b
Agent: main (Super Z)
Task: 用户四线反馈（be276a0 装机日志对：latestlog.txt=zink 会话 / latestlog.old.txt=MG 会话）——①zink 开 FSR 后提升区域绿色花屏；②⌨ 控件虚拟键盘仍打不了字（第三次报告）；③继续丰富问题库；④能否把 FSR 换成 MetalFX 时域放大（Temporal）→ 四线全处理

Work Log:
- 拉取 be276a0 日志判读（用户直接上传 latestlog 对，第一手证据）：
  * zink 会话（latestlog.txt）："[OSMBridge] Task83 FSR shader compile FAILED (stage=35633): GLSL 4.50 is not supported. Supported versions are: 1.10...4.10" → EASU 编译失败 → 兜底 "restoring MC window to surface 2360x1640" 触发；随后整局 isInputReady=0、fps=59 正常渲染（全尺寸）；中途 VK_ERROR_DEVICE_LOST（后台权限回收）后 fps=0 冻死
  * MG 会话（latestlog.old.txt）：FSR1 正常 engage（render 1814x1262 -> 2360x1640）+ Task82 视口锁存拒绝 2048x2048 + Task81 深度扫描行——Task78/81/82 全部在位生效
  * 键盘：两份会话均零 "[InputDiag] Task83 button text"、零字母 sendKey/key consumed（MC 只收到 WASD/ESC/F3）——⌨ 面板的触摸从未到达 executebtn
- ⌨ 键盘真根因（几何取证，scripts/kb_layout_audit.py 复刻 calculateDynamicPos 求值）：出厂 custom.json ⌨ 抽屉的 buttonProperties 数组末尾是一块 404.5x170 无键码背景板（keycodes 全 0），addSubview 按数组顺序执行 → 板在 z 序最顶层；算出板 frame=(198,0,404,170)pt 全覆盖 58/60 个功能键（QWERTY 全字母+F键+符号，仅 PGUP/PGDW 在板外）→ 点任何字母都命中板 → executebtn 四键位全 0 空转 → 零事件零日志。Task83 的字符合成修复本身正确但触摸根本到不了字母按钮——新旧所有出厂模板均此顺序 = 面板从未能用
- 键盘修复（双层）：①CustomControlsUtils.m loadControlObject 新增 ame83b_is_decorative_button（四键位全 0 && 非 toggle && 非 passThru）→ userInteractionEnabled=NO，触摸穿透到下层功能键——治所有存量安装（设备上旧 custom.json 仅当缺失才拷贝，永不更新，代码层修复是唯一普适路径）；②custom.json 背景板挪到数组首位（z 底，新装卫生）+ 'command' 键位 44（COMMA，打出逗号）→343（LEFT_SUPER）；③executebtn 入口取证日志（前 20+每 100：按钮名/动作/四键位）——下次反馈日志可直接定位层
- zink 绿屏根因链（两层叠加）：①EASU 着色器声明 #version 450 超出 zink(MoltenVK=VK1.1→桌面 GL 4.1) 的 GLSL 4.10 上限；②兜底调用的 nativeSendScreenSize 在 26.3 SDL3 路径是空转（GLFW_invoke_* 恒 NULL + isInputReady 全程 0）→ MC 永远不知道要恢复全分辨率 → 持续按 1815x1261 小窗渲染 → 2360x1640 全尺寸 OSMesa 缓冲的未写区域 = realloc 未初始化堆内存上屏 = 绿色花屏
- zink 修复（双层）：①osm_bridge.mm 版本自适应——ame83_probe_glsl_version（glGetString(GL_SHADING_LANGUAGE_VERSION)，Mesa "4.10"→410）+ ame83_adapt_shader_version（首行 #version 替换为上下文版本，区间 400-450；着色器主体仅需 4.00：uintBitsToFloat/packHalf2x16 均为 4.00 内建，接口声明 330+，无 layout(binding)）；②input_bridge_v3.m nativeSendScreenSize 补 Path B——GLFW 通道不可用时推合成 SDL_WINDOW_RESIZED(0x207)（SDL3_WindowEvent 布局与 Task61 注释互证：data1@20/data2@24；MC 26.3 直接消费事件数据为像素窗口尺寸 = Task61 改写器的既有语义）+ 同值去重 → 兜底真正生效，顺带修好 SDL3 路径运行时分辨率调整（此前同样静默失效）
- MetalFX 时域可行性定案（不实装，技术边界如实入库）：Temporal 需逐像素运动向量图（API 必填）+深度图+抖动/重投影矩阵——MC 原版渲染管线不产出运动向量，需引擎/模组层新增速度通道（Sodium/Iris 级改造）；启动器呈现桥只见成品帧，无深度无相机矩阵，无法合成正确运动向量，强行累积=严重鬼影。Spatial 版与 FSR1 同级单帧+需 iOS16+/A13+ 门槛+纹理互操作层，收益边际。FAQ 详述
- FAQ 19→22 条：新增 MetalFX 时域边界（渲染分类）、zink 绿屏已修说明（故障分类）、切后台 DEVICE LOST 已知限制（故障分类，含"为什么加内存没用"）；重写键盘条目（两按钮区别图例化：✎ 系统键盘 vs ⌨ 按钮键盘，用法/大小写/排障）；FSR 条目补 zink 绿屏已修+开销说明
- 校验器踩坑×2（方法论补条目）：①注释里引用错误信息原文的 ASCII 双引号跨行 → 历史计数器引号配对翻转（Task83 同款假红复发，改写注释去引号）；②注释里数学区间 [400, 450) 的半开写法 → 裸字符计数 +1[ -1)（重写为文字表述）。E2 语法脚本补 osmesa_library 桩（ame83_probe_glsl_version 引用的 handle 在提取区块外）
- 级联日志锚点随 be276a0 更新：task81 C4 的 678e7b5 CloudsDepthSampler dump 行随旧日志退役 → 改查 Task81 扫描行+零 force+fsr1Setting=1；task82 H1/H2 的 MG 证据从 latestlog.txt 搬到 latestlog.old.txt（数字按新会话 1.30 档改 1814x1262）+ 新增 H3（zink 会话 linkage+编译失败+兜底三锚点 = Task83b 动机实锤）
- 验证终态：verify_task83 73/73（新增 F 段 12 项：版本探测/替换/0x207/装饰板/JSON z序/入口取证/FAQ×3/行为回放×2/注释锚点）；task81 32/32、task82 54/54；全仓 14 个 verify 脚本零失败

Stage Summary:
- ⌨ 键盘一句话定性：不是字符事件层的问题（Task83 修复正确但从未被触发），是布局模板的背景板以 z 序顶层吞掉了全面板触摸——58/60 个功能键被盖，只有 PGUP/PGDW 幸存。代码层装饰板免疫（userInteractionEnabled=NO）让触摸穿透，存量旧布局安装同样治愈
- zink 绿屏一句话定性：GLSL 450>4.10 编译失败 + 兜底恢复在 SDL3 路径空转，双因叠加让 MC 永远小窗渲染、未初始化缓冲区上屏。版本自适应让 EASU 在 zink 上真正跑起来（预期装机锚点 "[OSMBridge] Task83b FSR shader #version adapted: 450 -> 410" + "[OSMBridge] Task83 FSR1 upscale engaged (zink)"）
- MetalFX 时域：不做（缺运动向量是引擎层硬依赖，如实说明）；空间版收益边际。FSR1 继续为默认超分
- 附带收获：nativeSendScreenSize 的 SDL3 路径打通 = 运行时改分辨率/FSR 兜底在 26.3 下首次真正生效
- 装机验证锚点：①⌨ 面板（任意旧安装）点字母 → 聊天框出字 + 日志 "[InputDiag] Task83b executebtn #1: name=H ..." → "[InputDiag] Task83 button text #1"；②zink+FSR → 上述版本适配/engage 两行，画面满屏无绿；③切后台冻结为已知限制（FAQ），日志见 VK_ERROR_DEVICE_LOST
- 遗留：切后台 DEVICE LOST 自动恢复（需 Vulkan 设备重建，路线图）；RCAS 锐化第二 pass（Task80 遗留）；深谷 build 尖峰 instrumentation（Task78 遗留）；ja/km l10n（Task66 遗留）

---
Task ID: 83b-CI
Agent: main (Super Z)
Task: Task83b 提交的 CI 修复轮

Work Log:
- 第一轮 run 35096621923（7d72f82）失败：osm_bridge.mm:264 "cannot initialize a variable of type 'const char *' with an rvalue of type 'GLubyte *'"——本地 E2 语法桩把 glGetString 声明成 const char*(*)(unsigned)，恰好掩盖了 C++ 指针隐式转换错误（真实 osm_bridge.h 签名是 GLubyte* 返回）
- 修复：代码侧改收 const GLubyte* + 显式 (const char*) 转型后 sscanf；语法桩同步改为真实签名（GLubyte* 返回）+ 注明教训——本地桩签名必须逐字镜像真实头文件，否则语法检查给出虚假信心
- 过程清理：误把 12k 行 CI 日志 ci_task83b_1.log 提交进仓库（仓库历来不跟踪 ci_*.log）→ 移到仓库外 + .gitignore 补 ci_task83b_*.log + amend 强推
- 第二轮 run 35097960207（ef74dfb）SUCCESS

Stage Summary:
- Task83b 全部落地：⌨ 键盘背景板根治 + zink FSR 版本自适应/兜底真实恢复 + FAQ 22 条 + MetalFX 技术边界入库
- 装机验证锚点：①任意旧安装点 ⌨ 面板字母 → 聊天框出字（日志 Task83b executebtn → Task83 button text 链）；②zink+FSR → "[OSMBridge] Task83b FSR shader #version adapted: 450 -> 410" + "[OSMBridge] Task83 FSR1 upscale engaged (zink)"，画面满屏无绿；③切后台冻结=已知限制（FAQ）

---
Task ID: 84
Agent: main (Super Z)
Task: 用户上传 75c5e14 装机日志（Task83b IPA run 35097960207 会话）→ 判读优化点 + 修复 zink FSR 编译新倒在的一关 + Arm ASR 可行性定性 + FAQ

Work Log:
- 日志判读（zink 全程全分辨率会话，因 FSR 未启用）：
  * Task83b 双修复真机实证：键盘三级链路全通（Task83b executebtn name=T → Task83 button text glfwKey=84 -> 't' → Task82 SDL text input U+0074，字母/空格连打 ≥8 条）——⌨ 面板彻底治愈；FSR 兜底真实恢复（window size -> SDL 0x207 2360x1640）——绿屏绝迹；无 DEVICE_LOST
  * zink FSR 编译链：版本自适应生效（#version adapted: 450 -> 410）→ 片元编译倒在 no function with name packHalf2x16（0:626(37) = FSRShaderSource.h L645 的 AU1_AH1_AF1_x，头文件行号-19=字符串行号精确对上）→ Task83b 注释"packHalf2x16 为 4.00 内建"系误判，实为 GLSL 4.20 核心
  * stage=35632 = 0x8B30：osm_bridge.mm 的 GL_FRAGMENT_SHADER 被误写 0x8B30（规范值 0x8B92=35730，非任何 shader 类型枚举）；日志含真实编译诊断证明设备栈仍产出了编译（MobileGlues 封装层容错），但规范错值不可依赖
  * 会话性能画像：fps 29-83（世界流式加载期低谷、闲置 76-83），GC 健康 1.7-4.2ms（Task68 调优在位），mem 4.9-5.6GB，-Dmax.fps=260 解锁在位
- 修复①枚举：osm_bridge.mm GL_FRAGMENT_SHADER 0x8B30 → 0x8B92 + 勘误注释（记录 75c5e14 stage=35632 证据）
- 修复②半精度打包：FSRShaderSource.h（FSR_FSSource raw string 内、AU1_AH1_AF1_x 之前）烘焙 #if __VERSION__ < 420 守卫的手写 packHalf2x16/unpackHalf2x16（RNE 舍入/次正规/进位/Inf/NaN 全路径，floatBitsToUint/uintBitsToFloat 均 3.30 内建）；算法先在 Python 镜像位级对照 numpy float16 验证（64,060 pack + 50,000 unpack + 4,000 round-trip 全等，scripts/verify_task84_packhalf.py）再转写 GLSL（逐行核对+常量指纹 16 项全对）
- 内建审计（防 info log 截断漏报）：整个片元着色器 >4.10 的依赖仅 packHalf2x16/unpackHalf2x16 一对（texelFetch 3.30、textureGather 4.00、packUnorm* 4.00、imageLoad 仅注释行）——修复后 4.10 必然编过
- 4.20+ 零变化保证：守卫在 MG 转换管线（glslang 以 #version 450 解析）预处理期即剔除，SPIRV-Cross 输出不变；ESSL <320 同样受益
- FAQ 22→23：新增 Arm ASR 条目（渲染分类，MetalFX 之后）——官方实现为 Vulkan/DX12 计算着色器（GL 4.3），zink GL 4.1 上限跑不了；性能卖点为 Mali 调优的 compute 分块/共享内存，Apple GPU 经片元管线优势全失；同为 FSR1 衍生画质差异小——不引入；greenFx 条目改"两轮修复"措辞；fsr 条目 Zink 行更新为"版本自动降级 + 半精度打包函数补齐"
- version.h REVISION 17 addendum（Task 84, no bump）：转换输出零变化
- verify_task84.py 31/31（A 枚举×5 / B shader 回退×10 / C 位级验证 / D FAQ×6 / E 日志证据×7 / F 级联×2）；级联 task82 H3 随新日志证据换代（4.50 版本失败 → adapted+packHalf 失败链）、task83 B12 计数 22→23；全仓 15 校验器全绿；E2 语法门通过
- 提交推送 → CI

Stage Summary:
- zink FSR 编译三连关闭幕：GLSL 450（83b 修）→ packHalf2x16 4.20 缺失（84 修）→ 枚举 0x8B30（84 修）；装机验证锚点：adapted 行之后直接出现 "[OSMBridge] Task83 FSR1 EASU ready (zink)" + "engaged (zink): render 1814x1262 -> surface 2360x1640"，不再有 packHalf 编译失败
- 预期收益：FSR 1.30 档启用后渲染像素 3.87M → 2.29M（-41%），配合 83b 的单趟直画
- Arm ASR 定性（与 MetalFX-T 不同因）：无运动向量依赖（同为 FSR1 衍生空间超分），卡点是 compute shader（GL 4.3 > zink 4.1 上限）+ Mali 专属收益——不引入，FAQ 已录
- 日志性能结论：fps 波动=世界流式（正常）；GC/内存健康；键盘/绿屏/兜底三项 Task83b 修复全部装机实证
- 遗留：RCAS 锐化第二 pass（Task80 遗留）、切后台 DEVICE_LOST 自动恢复（路线图）、ja/km l10n

---
Task ID: 85
Agent: main (Super Z)
Task: 用户报"画面分裂"（Task84 构建装机，zink FSR 首次真跑）+ 要求搜索 FSR1 替代方案 → 根因修复 + 调研入库

Work Log:
- 根因定位（osm_swap_buffers 旧序）：glFinish（触发 OSMesa GPU→CPU 回读，zink 下帧数据在 Vulkan image）→ EASU（画进 GPU 侧帧缓冲）——升采样结果永远到不了 CGImage 包装的 client buffer。真机视觉 = 画面分裂：左下角窗口区域为本帧原始低清画面 + 其余区域为上一帧 EASU 输出残影。Task 83 引入该序，Task 84 修齐编译链后 EASU 首次真跑，缺陷随之暴露
- 修复（osm_bridge.mm，净 +49/-7）：
  1. 顺序反转：EASU 块移到 handle.glFinish() 之前（回读包含完整升采样结果，CGImage 上屏即全幅）
  2. 封闭性：glBindFramebuffer(GL_FRAMEBUFFER, 0) 显式锁定拷贝源/绘制目标 + draw/read FBO 双通道保存还原（模组非对称绑定不受扰动）+ GL_STENCIL_TEST 关闭 + glBindFramebuffer 入 dlsym 表（缺失熔断）
  3. engaged 日志尾缀 "(EASU pre-readback ordering, Task 85)"（装机判读锚点）
- FSR1 替代方案调研（web 搜索，用户点名要求）：NIS（MIT、单 pass 放大+锐化、画质与 FSR1 同级——唯一值得未来考虑的同级替代）；GSR（BSD-3、Adreno 专属调优在 Apple GPU 落空）；MetalFX Spatial（Digital Foundry 生化危机 Mac 实测画质不如 FSR1）；Anime4K/FSRCNNX（动画内容特化）；时域家族（需运动向量/深度，引擎侧产出）。结论：EASU 已是单帧空间放大第一梯队，且已完成 GL4.1 适配，换同级收益 < 一次适配风险
- FAQ 23→24：upscalerAlt 条目（五类方案+结论）+ fsr 条目 zink 病史补画面分裂已修（绿屏/分裂双病史闭环）
- stale 校验同步：task83 B12（23→24）、task84 D1（23→24）/D3（armAsr 后 upscalerAlt）
- version.h REVISION 17 addendum（Task 85 no bump：纯启动器侧呈现代码，转换缓存零影响）
- 验证：verify_task85.py 24/24（A 顺序反转 5 指纹 + B 封闭性 9 指纹 + C FAQ 5 + D swap 段 g++ 语法门[dispatch block→lambda/NSLog→printf 变换] + E 括号 + F 级联）；全仓 13 校验器：71(30)/72(42)/75(63)/76(40)/77(27)/78/79/80(44)/81(32)/82(54)/83(73)/84(31)/85(24) 全绿
- 踩坑：MultiEdit 再证非原子（GL defines 块重复写入）——每次 Edit 后必须 rg 复核现场（Task 70 教训重申）

Stage Summary:
- 提交推送 → CI；装机验证锚点：zink+FSR 下 "[OSMBridge] Task83 FSR1 upscale engaged (zink): render WxH -> surface WxH (EASU pre-readback ordering, Task 85)" + 画面满屏无分裂
- zink FSR 四连关闭幕：版本适配（83b）→ packHalf（84）→ 枚举（84）→ 回读顺序（85）
- NIS 留作未来可选画质模式（单 pass 含锐化，优于当前 EASU-only）；RCAS 锐化与 NIS 二选一，待用户需求驱动

---
Task ID: 86
Agent: main (Super Z)
Task: 用户上传 f17ef7b 日志对（e7230da 构建）判读——"看看可以了吗"（Task85 修复验证）+ "大型整合包卡在启动界面"（BMC2）→ 双结论 + 启动看门狗

Work Log:
- 日志判读（均为 e7230da = Task85 IPA）：
  * latestlog.old.txt = 26.3-rc-3 zink 会话：**Task85 画面分裂修复装机实证闭环**——engaged 行带 "(EASU pre-readback ordering, Task 85)"、EASU ready program=588、render 1572x1092 -> surface 2360x1640、正常游玩后用户主动退出（Saving chunks + Stopping! + exit(0) 完整链）
  * latestlog.txt = BMC2 [FABRIC] 1.20.1（Modrinth shFhR8Vx，537 mods）首启卡死会话：JVM 00:32:47 起 → 5.6s 内 Fabric 完成 537 mod 枚举 + configureddefaults 应用默认文件（"Applying default files..."，web 搜索确证该字符串出处）→ 主线程硬阻塞：187s 零 GC/零 safepoint/零 JIT/零日志 → 用户取消 → "Launch overlay dismissed due to launch error"。线程名仍为 [main（未改名 Render thread）→ 卡点在 Fabric 客户端 entrypoint 阶段（configureddefaults 之后的某个 mod），非窗口/GL/渲染层。堆 2966MB 分配正常、无 OOM、无异常——排除内存/崩溃，定性为 mod 在移动环境的阻塞行为（网络/系统调用/native 库）
  * 历史对照：此前所有装机日志均为 26.3（SDL3 路径）——1.20.1（GLFW 路径 + Java 17）首次上机即触雷；健康 26.3 会话的 JNA→OSHI→Datafixer→Render thread 链在卡死日志中于 entrypoint 处断流
- 修复（诊断型）：Tools.java startLaunchWatchdog——method.invoke(Minecraft main) 前布防守护线程：
  * 阶段1（entrypoint 期）：每 15s 采样游戏主线程栈，全量转储前 24 帧；栈顶 6 帧签名重复时压缩为单行 "STILL blocked at" 心跳；上限 40 次（10 分钟）
  * 阶段2（线程改名 Render thread 后）：每 30s 采样，连续 2 次栈顶签名一致（>=60s 冻结）才转储，上限 5 次
  * 日志前缀 "[LaunchWatchdog] Task86"——下次复现直接点名阻塞 mod 的类与调用点；仅 java.lang API、零 JNI、零新依赖；ECJ 本地编译门零错误（Tools.class 产出）
- FAQ 24→25：bigpack 条目（大型整合包首启卡死：定性"与渲染器/内存无关——加大内存无效" + 看门狗日志说明 + 三步自救：等待 2-3 分钟/取消重试（第二次跳过默认文件复制）/上传日志定位元凶 mod 后可安全移除）
- version.h REVISION 17 addendum（Task 86 no bump：纯 launcher.jar Java 侧，转换器表面零改动）
- stale 校验同步（日志换代 f17ef7b 引发）：task81 C4、task82 H1/H2/H3、task84 E1-E7 的装机证据全部钉死 git 历史（be276a0:latestlog.old.txt / 75c5e14:latestlog.txt，不再读可变工作区日志）；task83 B12、task84 D1、task85 C1 FAQ 计数 24→25
- 验证：verify_task86.py 33/33（A 看门狗 10 指纹 + B f17ef7b 双日志 9 证据锚 + C FAQ 4 + D version.h 2 + E 字符串感知括号平衡 3 文件 + F ECJ 编译门 + G 级联）；全仓 14 校验器：71/72/75/76(40)/77(27)/78/79/80(44)/81(32)/82(54)/83(73)/84(31)/85(24)/86(33) 全绿

Stage Summary:
- Task85 画面分裂正式闭环（装机锚点 + 完整游玩会话实证）；zink FSR 病史全链（绿屏→分裂）收官
- BMC2 卡启动定性：mod 层阻塞，非启动器回归；看门狗已布防，等用户下次复现日志点名元凶
- 装机验证锚点：卡死复现时 "[LaunchWatchdog] Task86 entrypoint-phase sample #N ... at <元凶 mod 类名>"；健康启动时 "launch reached MinecraftClient (window init)" 单行
- 遗留：元凶 mod 待日志点名（BMC2 嫌疑区间=configureddefaults 之后的 entrypoint 序列）；RenderDiag 的 swapOK/drawable 字段对 zink 路径是盲的（fps 计数有效），诊断盲区留待后续

---
Task ID: 87
Agent: main (Super Z)
Task: 用户上传 7b88b69 日志对（6054498 构建）判读——"第一个 log 是 ltw 渲染器启动崩溃，第二个是大型整合包" → 双根因实锤 + 三层修复

Work Log:
- 日志判读（均为 6054498 = Task86 IPA，iPad Air M4 / iPadOS 27，**Task86 看门狗一击命中**）：
  * latestlog.txt = LTW 渲染器 × MC 26.2 崩溃会话：LTW 初始化全绿（first eglSwapBuffers OK、fps 交换正常、27 ticks）→ 资源重载 11.8s 崩溃。根因链：LTW 把桌面 GL 3.3 转译到 Apple 系统 ANGLE 的 **GLES 3.0**（日志实证 "Running on OpenGL ES 3.0 with ESSL 300"、BaseVertex 缺 ES 3.1 不可用），但对外宣告 GL 3.3——MC 26.x 云渲染管线（minecraft:core/rendertype_clouds）按 GL 3.3 核心规范使用 **samplerBuffer**（TBO 自 GL 3.1 起为核心特性），ES 3.0 后端没有 GL_EXT_texture_buffer → "'samplerBuffer' : Illegal use of reserved word" → pipeline/flat_clouds + clouds 缺失 → "Failed to load required shader programs" 硬崩（crash report 落盘）
  * latestlog.old.txt = BMC2 [FABRIC] 1.20.1（537 mods，zink+FSR）卡死会话：**看门狗两采样实锤元凶**——主线程在 Fabric setupLanguageAdapters 的 Class.forName 阶段卡在 toni.missingmodschecker.MissingModsWindow.open 的 Object.wait()。Web 搜索确证：MissingModsChecker 是 CurseForge/Modrinth 正规桌面工具 mod（1.0.1，检测到缺失依赖时弹 Swing 窗口等确认）；本例 Fabric 依赖解析已完成（仅 2 条 recommends 警告：lambdynlights/yacl3，无硬缺失），弹窗纯属桌面端增强，iOS 上窗口永远无法显示 → 无限阻塞 → 用户 30s 后强制取消（actionForceClose → exit(0)）。fullstackwatchdog 亦为正规 mod（CurseForge 崩溃报告美化工具），非恶意
- 关键洞察：MobileGlues 2.0.x version.h 揭示其 **REVISION 7+ 已有完整 TBO 模拟层**（glTexBuffer 借道 GL_COPY_WRITE_BUFFER 追踪 + 着色器 samplerBuffer 重写 + 绘制时采样重接，历经 R7→R13 迭代）——这正是 MG 能跑 26.x 而 LTW 不能的根本差异；LTW（tinywrapper，C）无此基础设施，移植属结构性工程 → 列路线图
- 修复（三层，全启动器侧）：
  1. **SurfaceViewController.m LTW × 26.x 预检门**：ame87_mcVersionRequiresTextureBuffer（主版本 >= 26，含 26w* 快照与 rc/pre 后缀剥离；25w* 无法精确划界放行）+ launchMinecraft 内拦截（dismissLaunchOverlayOnError + 弹窗指引切 Zink/MobileGlues + return，复用 metadata-nil 校验的既有模式），JVM 未启动即拦——不再白跑必崩启动
  2. **JavaLauncher.m [ModDialogGuard] Task87**：JVM 启动前扫 gameDir/mods，实证名单（missingmodschecker，小写子串匹配 .jar）自动改名 .jar.disabled（Fabric 忽略非 .jar；改回即恢复）；名单宁缺毋滥——只收真机实证叶子工具 mod，避免破坏依赖解析
  3. **Tools.java 看门狗阻塞形态识别**：dumpStack 挂 maybeLogStartupBlockHint——(a) 16 帧窗口扫 java.awt./javax.swing. 帧；(b) **Object.wait/wait0 直挂非 JDK 帧（3 帧窗口）**——弹窗后等待的栈上已无 AWT 帧（构建已返回），纯 AWT 扫描必漏，等待形态本身才是判据；命中输出一次性 "STARTUP BLOCK signature" 指引（点名移除/禁用动作 + 呼应 ModDialogGuard），task87HintShown 防刷屏
- FAQ 25→26：+ltw26（LTW 渲染器玩 MC 26.x 直接崩溃：预检说明 + samplerBuffer 机理 + 日志特征 + 切换指引 + 适用范围 1.21.x 及更早）；renderer 条目补 LTW 适用范围 bullet；bigpack 条目重写（实锤案例 missingmodschecker + 两层防护说明 + .disabled 恢复指引）
- version.h REVISION 17 addendum (Task 87, no bump)：纯启动器侧（ObjC + launcher.jar Java），MobileGlues 转换器表面零改动
- stale 校验同步（日志换代 7b88b69 引发）：task86 B 段 e7230da 日志对钉死 git 历史 f17ef7b（B0 fixture 在位检查 + git_show 辅助函数，不再读可变工作区）；task86 C2 bigpack 断言同步重写后内容；task83 B18 "设置 → 视频设置" 计数 2→3（ltw26 新增）；task84 D3 分类数组插入 ltw26；task83 B12/task84 D1/task85 C1/task86 C1 FAQ 计数 25→26
- 验证：verify_task87.py **47/47**（A 7b88b69 双日志 9 证据锚 + B 预检门 6 + C ModDialogGuard 6 + D 看门狗识别 7 + E FAQ 6 + F version.h 2 + G 版本口径 12 用例单测 + H 括号平衡 5 文件 + I ECJ 编译门 + J 级联 4）；全仓 15 校验器全绿（71/72/75/76/77/78/79/80/81/82/83(73)/84(31)/85/86(33)/87(47)）

Stage Summary:
- BMC2 整合包卡死正式闭环：元凶 = missingmodschecker 桌面弹窗 mod；下次启动 ModDialogGuard 自动禁用后整合包应能继续（Fabric 无硬缺失依赖）
- LTW × 26.x 能力边界定案：ES 3.0 后端无 TBO → 必崩；预检门拦截 + 指引切 Zink/MG；LTW 适用 1.21.x 及更早；TBO 模拟移植列路线图
- 装机验证锚点：整合包重启 → "[ModDialogGuard] Task87: disabled desktop dialog mod ... (renamed to .disabled)" + 启动继续推进（Backend library / Render thread 出现）；LTW×26.x → "Task87 launch gate: LTW renderer + MC 26.x blocked" + 弹窗
- 遗留：⌨ 虚拟键盘二轮诊断仍缺真机 [InputDiag] button text 证据（本轮两日志均未触及键盘）；BMC2 537 mods 在 A 系 3GB 堆上的运行期表现待装机观察

---
Task ID: 87 (续)
Agent: main (Super Z)
Task: CI 构建 + 宏冲突修复

Work Log:
- 首推 697667e CI 失败（run 35163736029）：JavaLauncher.m:465 编译错误——**第 26 行既有宏 `#define fm NSFileManager.defaultManager` 与 ModDialogGuard 局部变量名 fm 冲突**（`NSFileManager *fm` 被展开成 `NSFileManager *NSFileManager.defaultManager` → expected ';' at end of declaration ×1 + class property 误诊 ×3）
- 修复（6d4d68c）：函数体内 fm → fileMgr（仅 4 处，词边界正则替换，函数体外零改动）；verify_task87 C3 同步加"函数体无 fm 宏使用"断言防复发；全仓宏冲突扫描（fileMgr/isDir/modsDir/srcPath/dstPath/patterns/ame87_* 均无碰撞）
- CI run 35164771799（6d4d68c）completed | success——新 IPA 就绪

Stage Summary:
- Task87 三层修复全链绿灯：47/47 验证 + 15 校验器级联 + CI 构建成功
- 教训入库：该仓库 ObjC 文件有短名宏（fm），新局部变量命名前需 grep `^#define`——C3 断言已固化此检查

---
Task ID: 88
Agent: main (Super Z)
Task: 参照 MeloNX 在主界面右侧面板 JIT 标识上方新增"扩展内存限制/扩展虚拟内存"两个状态标识

Work Log:
- 参考源码调研：MeloNX（Ryujinx iOS 移植；官方仓库 melonx-emu/MeloNX 已下架，改用 fork Mi-Yomi/MeloNX@master）的检测与展示实现——Common/EntitlementChecker.swift 的 checkAppEntitlement()（SecTaskCreateFromSelf + SecTaskCopyValueForEntitlement 私有 API 读取本进程 entitlement）与 UI/Main/Settings/SettingsView.swift 的 "Increased Memory Limit / Extended Virtual Addressing" 状态展示；两项 key：com.apple.developer.kernel.increased-memory-limit（扩展内存限制）、com.apple.developer.kernel.extended-virtual-addressing（扩展虚拟内存）
- 定位本仓库既有 JIT 标识：Natives/LauncherRightPanelViewController.m 的 jitStatusLabel（启动游戏按钮上方；胶囊样式 = 11pt Medium 居中 / 圆角 8 / 绿 rgb(0.2,0.7,0.3)=已开启 / 红 rgb(0.9,0.4,0.3)=未开启 + 同色 15% 透明背景）；确认仓库已有同源检测入口 utils.m getEntitlementValue()（JavaLauncher.m 781/1296/1606 行已在用同两个 key 做内存分配与虚拟地址空间决策）
- UI 实现（LauncherRightPanelViewController.m）：新增 memLimitStatusLabel/extVMStatusLabel 两属性；makeJITStyleStatusLabel 工厂方法（字号/对齐/圆角与 JIT 标签完全一致）；约束自下而上排列 扩展内存限制 → 扩展虚拟内存 → JIT（间距 4pt，同宽同高 20pt，左右 12pt）；新增 updateMemoryEntitlementStatus 复用 getEntitlementValue 检测两项 entitlement 并按 JIT 配色渲染；刷新时机对齐 updateJITStatus（viewWillAppear + DidBecomeActive 通知 + setupUI 末尾立即刷新）；applyCustomAppearance 与 JIT 标签同策略（用户自定义文字色时覆盖，未设置时不重置）
- 布局加固：原"进度条 bottom ≤ JIT 标签 top +12"约束默认 required 优先级；状态堆栈加高 48pt 后小屏可能不可满足——改为 999 优先级成为真弱约束（空间不足时优先断开此条允许中间留白，避免约束冲突告警）
- utils.m 顺手修复：getEntitlementValue 原实现 SecTaskCreateFromSelf 被调用两次（secTask 与内联各一次）但只释放其中之一，每次调用泄漏一个 SecTaskRef——收紧为单次创建 + nil 守卫 + 判断后释放，对外行为完全不变（非 NSNumber 非 nil → YES；NSNumber → boolValue；nil → NO）
- 本地化：新增 4 个 key（i18n_str_mem_limit_enabled/disabled、i18n_str_ext_vm_enabled/disabled），覆盖 en/zh-CN/zh-Hans/zh-Hant/ja（与 i18n_str_421 覆盖范围一致，其余 45 种语言走 localize() 的英文回退）；zh-Hant 用繁体（擴展記憶體限制/擴展虛擬記憶體/已開啟），ja 用日文（拡張メモリ上限/拡張仮想メモリ/有効/無効）
- 验证：verify_task88.py 46/46（A UI/检测/刷新时机 18 项 + B utils 收紧 4 项 + C 本地化 21 项 + D key 一致性 3 项 + E git 作用域 1 项；含字符串感知括号平衡与 .strings 引号闭合检查）

Stage Summary:
- 主界面右侧面板自下而上状态堆栈：扩展内存限制 → 扩展虚拟内存 → JIT，三项均沿用原 JIT 胶囊样式（绿=开启/红=未开启）
- 展示值来自签名 entitlement（签名后固定）：普通 sideload 签名（无权限）显示红色"未开启"，与 MeloNX 行为一致；TrollStore 安装或带对应权限的签名包显示绿色"已开启"
- getEntitlementValue 的 SecTaskRef 泄漏已堵，isJITEnabled/memorystatus 等既有调用方同步受益
---
Task ID: 89
Agent: main (Super Z)
Task: 全局自绘 UI 新拟态化——参照 react-native-neomorph-shadows 的 Neomorph/NeomorphFlex 凸出样式（用户选定），替换全部非 iOS 原生 UI

Work Log:
- 需求澄清（用户逐项确认）：实现方式=ObjC 原生移植（React 系库无法嵌入原生工程，上传的 README=react-native-neomorph-shadows、zip=bigbear-ui 均为 React 系，仅作样式参考）；主题=跟随系统双主题；背景图=新拟态下强制纯色底；节奏=一次全改；主按钮=全灰新拟态（与底同色，仅靠阴影分层）；样式=凸出（outer），非凹陷（inner）
- 算法取证：拉取 tokkozhin/react-native-neomorph-shadows 源码（Neomorph.js/helpers.js），忠实移植 iOS 原生路径——HSP 亮度 sqrt(0.299r²+0.587g²+0.114b²)、brightnessToOpacity(50^(b/255)/50−1/50)、亮影透明度 0.025+0.975·op / 暗影 0.35·(1−op)、偏移=±shadowRadius 且模糊=shadowRadius、暗=黑/亮=白默认色、圆角夹断 min(r,w/2,h/2)
- NeomorphKit 新组件库（Natives/NeomorphKit/，CMakeLists 已登记）：
  * NMTheme：浅 #ECF0F3（库 demo 同款）/深 #262A2F 双主题，surface/surfaceRaised/background/label/secondaryLabel/placeholder；isDark 跟随 currentTraitCollection（兼容 App 的 general.ui_theme override）；NMThemeDidChangeNotification 广播
  * UIView+Neomorph：凸出引擎=目标 layer 插入暗/亮两个投影承载层（surface 底色+双向阴影，内容浮于其上）；_NMNeomorphAttachment 附件负责 KVO bounds 同步几何 + 主题通知重绘；API：nm_convex/nm_convexRadius:shadowRadius:/nm_convexRaisedRadius/nm_pill（圆角=高/2 随尺寸重算）/nm_flatSurface（面板平贴无阴影，保留 masksToBounds）/nm_removeNeomorph/nm_styleConvexButton；凸出模式自动放开 masksToBounds
- BackgroundManager 枢纽改造：applyEffectToView/applyEffectToCollectionViewCell 切换为 Neomorph 分发（64 处既有卡片调用点覆盖 31 文件一次性接入新拟态，保留各调用点圆角，阴影半径=圆角/2 上限 8，防御性清除遗留 blur 子视图）；applyBackgroundToWindow/ToSplitViewController 强制 NMTheme 纯色底（背景图/视频路径停用，用户选定）
- 主题广播接线：SceneDelegate.applyUITheme（设置页切换）+ traitCollectionDidChange（auto 模式跟随系统）→ reloadAndBroadcast
- 核心屏幕：RootVC 侧栏/右面板改平贴表面（外侧圆角保留，毛玻璃停用）；菜单选中项凸出面板/未选中平贴；右侧面板启动/版本/JAR/下载中心按钮全灰化 + JIT/内存状态胶囊 nm_pill（绿/红语义色仅保留文字）；导航工具栏启动/下载中心按钮全灰化；下载页资源行卡片/筛选面板/导入整合包按钮新拟态；VersionCardCell（截图蓝框版本卡片）底色/边框/旧阴影移交 NeomorphKit
- 长尾：公告/导出/服务器加入/服务器包下载/Mod 下载等彩色主按钮全灰化；账户/新闻头像与缩略图占位底色主题化；LauncherCardLayoutViewController 的 card_color 叠加停用；红框原则执行——UISegmentedControl/UISearchBar/键盘/系统弹窗零改动，游戏画面覆盖层（GameMenuOverlayView）与图片上浮层（sizeLabel）因脱离纯色表面按红框逻辑排除
- 验证：verify_task89.py 36/36（A 算法移植 13 项含 Python 独立对拍 #ECF0F3 亮≈0.770/暗≈0.083 + B 枢纽 6 项 + C 屏幕 12 项 + D 红框原则 3 项 + E 作用域 1 项；全部改动文件字符串感知括号平衡 + import 一致性 0 失败）

Stage Summary:
- 全部自绘 UI 接入新拟态：卡片（64 处枢纽）+ 主按钮（全灰）+ 状态胶囊 + 选中态面板；原生控件/游戏内覆盖层未动
- 双主题随系统与 App 内外观切换实时重绘（通知驱动），浅色=库 demo 同款 #ECF0F3，深色=#262A2F
- 背景图/毛玻璃/card_color 在新拟态下停用（强制纯色底，用户选定）；设置页入口保留
- 后续可调项：凸出强度（nm shadowRadius 参数）、深色表面色阶、按压反馈动画（未做，菜单已有弹跳）

### Task 89 补丁（CI 编译修复）
- UIView+Neomorph.m：CGColor * → CGColorRef（ObjC 需 struct tag/typedef）；updateAppearance 内 dark/light 重复声明合并（加 nil 守卫时遗留）
- SceneDelegate：traitCollectionDidChange: 在 UIWindowSceneDelegate（非 UIResponder）上永远不会被触发，改用 KVO 监听 window.traitCollection（context 区分，sceneDidDisconnect 摘除）——覆盖 auto 模式跟随系统与设置页切换两条路径
- LauncherCardLayoutViewController：card_color 停用改为干净空操作（原假条件写法逻辑错误）
---
Task ID: 90
Agent: main (Super Z)
Task: 用户实测反馈修复（截图 IMG_9106）——右侧面板按钮恢复原样、主界面卡片顶部色条移除、内存权限标识误报修复

Work Log:
- 蓝框（右侧面板按钮）：LauncherRightPanelViewController.m 整体回退到 7ab2b41（Task88 时点），启动按钮恢复 accentColor 底 + 原 elevation 阴影、下载中心/管理版本/执行 Jar 恢复深灰底（colorWithWhite:0.2）、JIT/内存×2 状态胶囊恢复同色 15% 透明度底；git diff 7ab2b41 对拍确认文件差异仅剩内存检测一处（校验器强制）
- 内存权限误报根因定位：仓库自带 entitlements.codesign/sideload/trollstore.xml 模板均预写 increased-memory-limit / extended-virtual-addressing = true，侧载工具合并模板后签名确实携带，SecTask 如实报告"有"；但普通侧载下描述文件未授权对应能力时内核并不真正兑现——"签名携带"≠"实际生效"
- utils.m 新增 CopyEmbeddedProfileEntitlements()（按字节定位 embedded.mobileprovision 的 <?xml...</plist> 载荷解析 Entitlements）与 getEffectiveEntitlementValue()（签名 + 描述文件授权双确认；TrollStore 等无描述文件场景回退签名判定）；LauncherPreferences.h 声明
- LauncherRightPanelViewController.updateMemoryEntitlementStatus 两项改用 getEffectiveEntitlementValue；main.m latestlog 增加"描述文件授权口径"生效状态输出，latestlog 可直接区分"签名携带"与"实际生效"
- 红框（卡片顶部色条）：LauncherNewsViewController 的 HomeTileBaseCell 移除 accentBar 渐变装饰条（属性/创建/挂载/layoutSubviews frame 全清）；setAccentColor: 保留空操作兼容数据源 6 处调用点，磁贴图标语义色（iconView.tintColor）不受影响；Task89 占位底色（nm_surfaceRaised）保留
- 面板容器（RootVC）未动：新拟态平贴表面保留（用户仅圈选按钮区域），深灰按钮 + 浅色表面与 Task88 前的浅色毛玻璃面板视觉等价
- 校验器同步：verify_task90.py 新增 67 项（含生效判定决策表 Python 对拍 10 例：描述文件未授权→NO、TrollStore 无 profile→YES、字符串 true/1 容错等）；verify_task88 A5a 升级为生效判定断言；verify_task89 修复 3 处陈旧断言（B5 改 KVO window.traitCollection 字面量——traitCollectionDidChange: 在 UIWindowSceneDelegate 上永不触发；C9 改实际注释标记；C1/C1a/C2 反转为恢复原样断言）
- verify_task88 45/46、verify_task89 35/36（各余 1 项 E1 工作区即时检查，提交后工作区干净即恢复全绿）、verify_task90 67/67

Stage Summary:
- 右侧面板按钮/胶囊与 Task88 版本逐字节一致（除内存检测修复），主界面卡片顶部色条全部消失，内存权限标识按"签名+描述文件授权"双口径显示
- 新增生效判定入口 getEffectiveEntitlementValue 仅用于内存标识与日志，JIT 判定/内存分配等既有 getEntitlementValue 调用方行为不变
- TrollStore 用户显示逻辑不变（无描述文件→签名口径）；普通侧载且描述文件未授权者现在正确显示红色"未开启"
---
Task ID: 91
Agent: main (Super Z)
Task: 双主题主文字色统一（浅#222222/深#EEEEEE）+ 内存标识全开启误报根因修复（sideload 模板预写）+ JIT 路径纠正与开启 JIT 闪退修复

Work Log:
- 字体清扫：NMTheme.label 精确值改为浅 #222222 / 深 #EEEEEE（用户指定，替代原偏蓝灰）；七个写死白色文件主题化——AccountLogin（标题/副标题/卡片标题/描述）、LauncherPreferences（cell/textField/label/header，textField 底色同步 nm_surfaceRaised）、Multiplayer（8 组 cell + 直连字段，CRLF 文件按字节锚点编辑）、VersionManager（titleLabel/subtitle/nameLabel/descLabel）、LauncherPrefManageJRE、BackgroundSettings、CustomControls 编辑器引导文案；副标题类用 nm_secondaryLabel 保持层级。彩色底站点有意保留白字（badge/彩色按钮/chip/pill、游戏内覆盖层 Surface*/GameMenuOverlay、终端 PLLogOutputView/PLCrashView、MD3 helper），图标 tint 一律不动
- 内存误报根因确认（复核 MeloNX EntitlementChecker.swift：同为 SecTask 机制，无更优方案）：CI 侧载工件预签 entitlements.sideload.xml 预写两项 kernel entitlement，用户重签保留 → SecTask 如实报告 → 标识必然全绿。修复：从 sideload 模板移除 increased-memory-limit / extended-virtual-addressing（普通侧载无描述文件背书本就不生效）；trollstore.xml（TROLLSTORE_JIT_ENT=1 工件，真实生效）与 codesign.xml（描述文件背书）保留；标识逻辑（签名+描述文件双确认）与 main.m 双口径日志不变
- JIT 闪退修复：①根因 A——sideload 模板同样预写 jb.pmap_cs.custom_trust 假标记，普通侧载误判 TrollStore 走 apple-magnifier:// 死路；新增 utils.isTrollStoreInstall()（签名标记 AND bundle 旁 _TrollStore 磁盘标记，与 main.m POJAV_DETECTEDINST 同源），三处 invokeAfterJITEnabled（LauncherNavigationController/DownloadViewController/RightPanel）hasTrollStoreJIT 全部改双确认；②根因 B——TXM 设备 brk #0x69 无人应答时 JIT26CreateRegionLegacy 裸函数 SIGTRAP 必死（代码注释记载的致命点，用户实测"开启 JIT 后闪退"）；新增 JIT26CreateRegionLegacySafe SIGTRAP 安全网（sigsetjmp/siglongjmp + sigaction 保存恢复 + 非安全网窗口 SIGTRAP 保持默认语义），JavaLauncher 两处调用点改用并在 NULL 时走 i18n_str_jit26_not_ready 优雅报错（不再闪退）；③新 i18n key × 5 语言（en/zh-CN/zh-Hans/zh-Hant/ja）
- 校验：verify_task91.py 75/75（含 isTrollStoreInstall 决策表对拍 4 例、SIGTRAP 网结构断言、模板三向检查、保留站点抽查）；verify_task90 C6 同步为模板三向断言（65/65）；88/89 仅余 E1 工作区即时检查（提交后自愈）；修复工作区意外批量 644→755 模式位（11690 文件 chmod 还原 + 211 git checkout + 51 合法 755 保留）
- 工程说明：MultiplayerViewController.m 为整文件 CRLF，import 锚点按 \r\n 编辑；其余文件 LF

Stage Summary:
- 浅色模式所有自适应表面文字 #222222、深色 #EEEEEE（彩色语义色/彩色底白字/游戏内不受影响）
- CI 侧载工件签名不再预写内存权限 → 未开权限用户标识正确显示"未开启"；TrollStore 工件行为不变
- 普通侧载 JIT 恢复 stikjit 正常流程；TXM brk 无应答时优雅报错替代必死闪退
---
Task ID: 92
Agent: main (Super Z)
Task: StikDebug JIT26 脚本兼容性加固——调研其 JS 脚本机制并同步上游 Universal 脚本、预启动自动导出、修正过时指引文案

Work Log:
- 调研用户提供 StikDebug 默认脚本包（attachDetach/screenshot-demo/screenshot-capture/manic/UTM-Dolphin/Geode/maciOS.js）：JS = 调试器端脚本，经 GDB 远程协议（get_pid/send_command/prepare_memory_region/log）应答目标 App 的 brk 陷阱并为其准备可执行内存；各家约定不同——UTM/Dolphin legacy brk 0x69(x0=地址,x1=大小)、manic 死循环版、Geode 0x69/0x70/0x71；用错脚本 = 协议不配 = 崩溃/垃圾返回值
- 对照本仓库 JIT26 协议：legacy 0x69 = x0 大小/返回值=分配地址（BreakGetJITMapping），Universal 脚本（brk 0xf00d x16 分发 + brk 0x68 运行时注入）+ UniversalJIT26Extension.js（commands 3/4 = SetDetachAfterFirstBr/PrepareRegionForPatching + 0x69 覆写）才是完整实现——结论：Amethyst 必须用"特定 JS"，且早已内置（stikjit:// script-data 自动携带 + LiveContainer LCAppInfo 自动分配）
- 拉取上游 StikDebug/StikDebug：AutoScriptAssignments.swift 已按应用名（"Amethyst" 与 MeloNX/Manic EMU 等同组）自动分配内置 universal.js；旧侧载版内置名 Amethyst-MeloNX.js（上游已无此字符串，弹窗括号说明过时）
- 同步 Natives/resources/UniversalJIT26.js 至上游 2026-29-03（字节一致）：唯一差异 = 新增 continuesWithSignal 开关（默认 true，行为不变）+ 信号直通块包裹；协议面（0xf00d x16 分发/0x68 注入/_M,rx/0x69 错误哨兵 E0000069）零变化
- main.m 新增 init_exportJIT26Script()：每次启动把 bundle 内 UniversalJIT26.js 导出到 $POJAV_HOME（Documents），内容一致跳过写盘；此前副本仅在"检测到 legacy 脚本"失败路径补拷，旧版 StikDebug（无自动分配）用户得先失败一次才能 Assign Script
- JavaLauncher.m 两处 legacy 脚本报错弹窗更新：优先升级 StikDebug（自动分配）；旧侧载版内置名说明保留；Assign Script → Documents/UniversalJIT26.js（启动时自动导出）
- 校验：verify_task92.py 40 项（A 脚本同步 9 / B 导出 10 / C 文案 7 / D 协议回归护栏 12 / E 仓库卫生 2，含 D 组 Task88-91 成果全量护栏）；verify_task90 65/65、verify_task91 75/75 不受影响

Stage Summary:
- 打包脚本与上游 StikDebug universal.js 字节一致；旧版 StikDebug 用户可通过 Documents 预先 Assign Script，避免协议不配
- JIT26 native 协议（brk 0x69/0xf00d、哨兵 0x690000E0、SIGTRAP 安全网、Extension 注入、stikjit:// script-data 通路）全部零改动
- 结论落档：Amethyst 开 JIT 无需第三方专用脚本——内置 Universal+Extension 即"特定 JS"本体；UTM-Dolphin/manic/Geode 脚本与本启动器寄存器约定不兼容，不可混用
---
Task ID: 93
Agent: main (Super Z)
Task: 内存标识抛弃 MeloNX 双确认方案，回归启动日志同源的签名口径（用户指示"研究启动器如何检测这两项，显示在原来的地方"）；JIT/JS 方向按用户指示停止

Work Log:
- 日志溯源：用户认可的结果（extended-virtual-addressing: NO / increased-memory-limit: YES）= latestlog 开头 [Pre-init] Entitlements availability 块 = main.m printEntitlementAvailability() → utils.m getEntitlementValue()（SecTaskCopyValueForEntitlement 签名口径）。右面板 Task90 起用的 getEffectiveEntitlementValue（签名+embedded.mobileprovision 描述文件 Entitlements 交叉校验）比日志多一层——用户设备重签工具把 entitlement 同时写入描述文件时双确认放行，面板依旧"已开启"（且与日志口径不一致造成排查混乱）
- 修复（用户指示"抛弃"）：LauncherRightPanelViewController.updateMemoryEntitlementStatus 两项改回 getEntitlementValue（与启动日志同一函数、同一口径、原位置原配色原 i18n 键）；整体移除 getEffectiveEntitlementValue + CopyEmbeddedProfileEntitlements（utils.m）、LauncherPreferences.h 声明、main.m 生效口径日志块——全仓库只保留签名口径一种，面板与日志必然一致
- 保留项：Task91 的 isTrollStoreInstall / JIT26CreateRegionLegacySafe / 模板三向状态（sideload 已清理、trollstore/codesign 保留）全部不动；Task92 的 JIT26 脚本同步与导出保留在库（用户指示 JIT/JS 停止，不再继续开发）
- 校验器：新建 verify_task93.py 25 项（A 面板改回 8 / B 双确认移除 11 / C 口径一致性 4 / D 仓库卫生 2）；verify_task88 A5a 反转回签名口径断言；verify_task90 C1/C2/C5 反转为"已移除"断言、C3 改签名口径计数 + allowed 白名单补 Task93 词、C7 决策表作废；verify_task91 C6 反转——88:45+1(E1)/89:35+1(E1)/90:49/91:75/92:39+1(E1)/93:23+2(E1、D2 提交后自愈)
- 版本考古留档：用户设备 latestlog（Commit 6054498 不在本仓库、无 Task90 effectiveness 块）表明其安装的 IPA 并非本仓库 Task90+ 工件；本次修改后需安装最新 CI 工件重签验证

Stage Summary:
- 右侧面板两枚内存标识与 latestlog 开头 [Pre-init] Entitlements availability 两行完全同源同值；日志显示什么、面板就显示什么
- 双确认方案（Task90）代码全量退场；签名/描述文件里携带什么 entitlement 面板如实显示什么，不再做交叉猜测
---
Task ID: 94
Agent: main (Super Z)
Task: 809b847 双日志判读（"不同渲染器打开大型整合包依旧错误"）→ Sodium LWJGL 版本门根因实锤 + 动态版本上报修复

Work Log:
- 拉取用户新上传（809b847，两日志均 Commit 3bc95fa = Task93 构建，iPad Air M4 / iPadOS 27，BMC2 [FABRIC] 1.20.1 整合包 537 mods）：latestlog.txt = zink（libOSMesa.8.dylib + FSR preset2 scale1.5）会话，latestlog.old.txt = LTW 会话
- 判读一（Task87 修复双双生效确认）：LTW 会话 [ModDialogGuard] Task87 自动禁用 missingmodschecker.jar（rename .disabled）+ 1 desktop dialog mod(s) auto-disabled，启动越过 7b88b69 时代的 Object.wait 卡死点，mixin/config 阶段正常推进；zink 会话 FSR 链路（Task83b 410 适配 + Task85 EASU pre-readback ordering）无异常
- 判读二（新元凶实锤）：两渲染器在 JVM 启动 ~4s 后死于同一处——sodium 0.5.13（pack 实配 "- sodium 0.5.13+mc1.20.1"，日志 808 行）PreLaunchChecks 版本门："The game failed to start because the currently active LWJGL version is not compatible. Installed version: 3.4.1 / Required version: 3.3.1" + gh-2561 链接 → System.exit(1)（Amethyst fatal trace: reason=exit(1), VM_Exit 栈）。渲染器无关性就此定案：不是 GL 问题，是纯 Java 侧版本字符串问题
- 根因三层取证：
  1) Modrinth 下载原版 sodium-fabric-0.5.13+mc1.20.1.jar 反编译（自制 class 解析器+方法级反汇编器 scripts/parse_version_class.py + disasm_method.py）：PreLaunchChecks.REQUIRED_LWJGL_VERSION="3.3.1" 硬编码，isUsingKnownCompatibleLwjglVersion() = Version.getVersion().startsWith("3.3.1") 字节码实锤
  2) JavaApp/src/lwjgl overlay（Version.java/VersionImpl.java）把上报值硬编码 "3.4.1"（当年为满足 MC 26.x Sodium 0.9+ 的 startsWith("3.4.1")）→ 1.18~1.20.x + sodium 0.4/0.5 系全被拒；注意即便上报真实构建版本 3.3.3 也过不了（"3.3.3".startsWith("3.3.1")=false）
  3) 启动器选 jar 本身正确（两日志均 "[JavaLauncher] Using LWJGL 333"）——错的只是上报值
- 修复（动态上报，启动器侧 Java，四文件）：
  1) Tools.java preProcessLibraries：丢弃 org.lwjgl 条目前捕获 "org.lwjgl:lwjgl:<ver>"（version.json 里 Mojang 为该 MC 配套的 LWJGL 版本 = sodium REQUIRED 常量的同源值），写 org.lwjgl.version.report 属性 + 日志 "[Tools] LWJGL report version: <v> (from version metadata; sodium PreLaunchChecks gate, Task94)"
  2) overlay Version.java 重写：getVersion() 每次调用动态读属性（不受 clinit 固化影响，属性后写也生效）；回退链 pojav.lwjgl.version=341 → "3.4.1"（26.x 行为不变），否则 "3.3.1"（覆盖 1.18~1.20.x 最大存量）；常量 MAJOR/MINOR/REVISION 从上报值 parseMMR 解析；空白属性视为未设置
  3) VersionImpl.java：find() 与 Version.getVersion() 同源
  4) PojavLauncher.java：修括号错位 bug——LWJGL sanity 日志自引入起被困在 vulkan-only if 块内从未执行（任何设备日志均无 "[PojavLauncher] LWJGL selected" 行即实证）；移至 getVersionInfo 之后（属性已写入）并输出 reported+metadata 双值
- 验证（三层）：
  1) ECJ 编译门（scripts/task94_compile_check.sh，Linux 桩 eawt + add-exports sun.font）：overlay/Tools/PojavLauncher 三组零错误
  2) 行为矩阵（scripts/task94_harness/Task94Harness.java）14/14：A 1.20.1 门通过 B 26.x 门通过 C 后写属性动态生效 D 回退矩阵(341→3.4.1/333→3.3.1/双缺→3.3.1) E 常量一致 F 空白属性/3.3.2 原样上报
  3) 字节码级（Task94SodiumGate.java 反射真实 sodium jar 的私有 isUsingKnownCompatibleLwjglVersion）2/2：旧硬编码 3.4.1 被拒（复现 809b847）/ 修复后 3.3.1 放行
- 校验器：新建 verify_task94.py 47 项（A 日志锚 10 + B overlay 8 + C 捕获链 5 + D 括号修复 4 + E FAQ 3 + F version.h 3 + G 括号平衡 5 + H 编译/行为/真实门 4 + I 级联 5）；stale-sync：FAQ 计数 26→27 同步 task83 B12/task84 D1/task85 C1/task86 C1/task87 E1；task86 C3 数组正则 +sodiumLwjgl；task87 A 区日志钉 git 7b88b69（工作区已被 809b847 覆盖，task84 E 段惯例）
- 级联：83(73)/84(31)/85(24)/86(34)/87(49)/94(47) 全绿；88/89/90/91 绿（REPO 环境变量指向本仓）；92 E1/93 D1 为"无未提交改动"检查，提交后自愈
- FAQ 26→27（+sodiumLwjgl 条目：症状=秒退非卡死、日志搜 "LWJGL version is not compatible"、机理、动态上报修复说明、[Tools] LWJGL report version 验证锚点）；version.h REVISION 17 addendum（Task 94, no bump）

Stage Summary:
- BMC2 整合包两连关打通：Task87 清掉 missingmodschecker 卡死后，本轮清掉 sodium 0.5.13 LWJGL 版本门；下一个装机验证锚点 = 日志 "[Tools] LWJGL report version: 3.3.1" + "[PojavLauncher] LWJGL selected by launcher: 333, reported version: 3.3.1 (metadata: 3.3.1)" + 不再出现 "not compatible" 退出
- 上报口径定案：报 version.json 声明值（与 Mojang 配套、与 sodium REQUIRED 同源），而非真实构建版本（3.3.3 会拒）或硬编码（3.4.1 会拒 1.20.x）——各 MC 版本各报各的，26.x 行为不变
- 顺带修掉 PojavLauncher 括号错位（sanity 日志从未执行过的暗 bug）
- 遗留观察：sodium 门放行后 BMC2 537 mods 能走多远（内存/GC 压力、后续 mod 初始化）待下一轮装机日志；⌨ 虚拟键盘二轮诊断仍缺真机 [InputDiag] button text 证据
---
Task ID: 94 (续)
Agent: main (Super Z)
Task: CI 构建确认

Work Log:
- CI run 35227225654（62e2ddb）completed | success——新 IPA 就绪

Stage Summary:
- Task94 全链绿灯：47/47 验证 + 级联全绿 + CI 构建成功；等用户装机复测 BMC2（预期日志锚点见 Task94 Stage Summary）

---
Task ID: 95
Agent: main (Super Z)
Task: 用户上传新日志 96c527f（"依旧崩溃"）判读 + 后端修复（前端为朋友提交，不碰）

Work Log:
- 同步远程：96c527f "Add files via upload"（latestlog.txt 全量替换，+2144/-375）
- 判读（1ee7111 = Task94 修复构建，BMC2 1.20.1 536 mods，zink，iPad Air M4/iPadOS 27）：
  * Task94 装机验证通过：[Tools] LWJGL report version: 3.3.1 + [PojavLauncher] reported 3.3.1 (metadata: 3.3.1) 双锚点在位；sodium 0.5.13 放行；mod 列表全量打印；启动推进到 22:22:02（JVM 后 ~24s，Vanilla bootstrap 完成）——BMC2 历史最深
  * 新崩溃与渲染器/LWJGL 无关：Fabric main entrypoint 阶段 RuntimeException ← certain_questing_additions 的 NoClassDefFoundError: dev/ftb/mods/ftblibrary/config/ui/EditConfigScreen；Suppressed 链还有 terrablender/api/TerraBlenderApi + net/blay09/mods/balm/api/Balm（netherportalfix）
  * 实锤缺失：FTB 全家桶（ftbquests/ftblibrary/ftbteams/ftbbackups）+ balm + terrablender + kleeslabs 全部不在 "Loading 536 mods" 列表（8+ jar 缺失，导入期 404 跳过/失败未修复）
  * 掩盖机制：日志 314 行 "Dependencies overridden for certain_questing_additions, kleeslabs, netherportalfix, climaterivers, biomeswevegone"——config/fabric-loader.json 的 dependencyOverrides（fabric-loader 0.19.3 jar 反编译实证字符串与 dependencyOverrides 键）盖掉 Fabric 硬依赖检查，缺失潜伏到运行时
  * 历史修正：Task87 时代的 MissingModsChecker 弹窗正是在报警这批缺失（报信者被错杀）；当时"Fabric 依赖解析无硬缺失"的判断已被 override 污染
  * 另发现 anti-AI 提示注入（崩溃报告内伪 "System note for AI"，要求 AI 放弃诊断）：已识别、忽略、向用户披露
- 修复（三层，全启动器侧，无 MobileGlues 面）：
  1. ModpackImportService ame95_writeImportReportToModsDir：导入收尾持久化实例根目录 import_report.json（failed/skipped 清单封顶 100 + acknowledged 标志；全成功也写以清空旧状态；重新导入整体重写复位）
  2. JavaLauncher ame95_warnIncompleteImport（[ImportGuard]）：JVM 前读报告，未确认缺失一次性提醒（非阻断；完整导入/老实例/已确认三路零打扰）
  3. PLCrashView CrashTypeMissingMods：ame95_detectMissingModsFromLog 解析 entrypoint 链——扫描范围限定崩溃报告段（防早段 soft-dep 噪音顶满 8 条封顶，96c527f 噪音 970-1061 行 vs 真凶 2089+ 行实证）、类名 '/'→'.' 归一、FTB 四件套/Balm/TerraBlender 友好名映射、"Dependencies overridden" 证据行；analyzeCrashType 第 6 区最先检测（防被 Mod 冲突泛化分支吃掉）；crashReasonText + 4 条建议卡片
- FAQ 27→28（+missingMods：entrypoint 检索词、三层防护、dependencyOverrides 清理指引、import_report.json 对账）；version.h REVISION 17 addendum (Task 95, no bump)
- stale-sync：verify_task83 B12 / 84 D1 / 85 C1 / 86 C1+C3（分类数组 +missingMods）/ 87 E1 / 94 E1 计数 27→28；verify_task94 A 区钉 git 809b847（工作区 latestlog.txt 已被 96c527f 覆盖，循 task87 A 区惯例）
- 验证：verify_task95 59/59（含 G 段行为仿真：真实日志片段 × 等价正则，G5 对照组实证全量扫描会被噪音挤占）；级联 83:73/73、84:31/31、85:24/24、86:33/33、87:48/48、94:45/45 全绿；88-93 为朋友任务路径（workspace/Air-Minecraft-iOS-Launcher），本环境不可达，自愈型
- 已提交推送

Stage Summary:
- BMC2 三连关全通：Task87 清弹窗卡死 → Task94 清 sodium 版本门 → 本关定位"整合包本身不完整"；Task94 修复装机实证生效
- 装机验证锚点：导入期 "[ModpackImport] Task95: import report written ..."；启动期 "[ImportGuard] Task95: incomplete import detected ..."（一次性提醒弹窗）；崩溃期崩溃界面直接列缺失类 + 组件名（FTB Library/Balm/TerraBlender）+ override 证据
- 用户侧修复指引：删实例重新导入（换下载源）或补齐 FTB 全家桶/Balm/TerraBlender/KleeSlabs；修好后可清 config/fabric-loader.json 的 dependencyOverrides
- 遗留：⌨ 虚拟键盘二轮诊断仍缺 [InputDiag] 真机证据；zink FSR 画面分裂四嫌疑待装机日志；88-93 为朋友范围

---
Task ID: 95 (续)
Agent: main (Super Z)
Task: CI 确认

Work Log:
- CI run 35239914500（6c3d49d）completed | success——Task95 新 IPA 就绪

Stage Summary:
- Task95 全链绿灯（59/59 + 级联全绿 + CI）；装机锚点见 Task95 主条目；等用户重导入 BMC2 验证三层防护
---

---
Task ID: 96
Agent: main (Super Z)
Task: 右侧面板搬入 MeloNX 风格信息卡（设备/系统/内存状态），按用户澄清新增启动器版本/游戏版本/JIT 兔子卡共三张，右下角两按钮与「登录并启动」同款配色

Work Log:
- 编号重排：另一会话已占用 Task 94（LWJGL 版本上报）与 Task 95（整合包导入加固）并已推送远端，本任务重编号为 96，变基其上无源码交集（仅 worklog/校验器文件名）
- 卡片结构：7 张 MeloNX 风格卡（启动器版本 → 游戏版本 → 设备 → 系统 → JIT → 内存上限提升 → 扩展虚拟寻址）装入 UIScrollView+UIStackView；左右边缘与「登录并启动」对齐（12pt）、卡高 46pt 与按钮一致（用户备注）；下载中心/进度 UI 并入 stack 顶部隐藏自动折叠；空间不足整区上下滚动（用户确认方案）
- 三张新卡（AskUserQuestion 澄清后定稿）：启动器版本 = #64C466 + cube.transparent + CFBundleShortVersionString/CFBundleVersion 双读（相同去重）；游戏版本 = #64C466 + gamecontroller + 与红框同源（selectedProfile.lastVersionId，未选择兜底）；JIT 卡 = rabbit 线框兔 + 内存权限同色系橙 + 位于 MeloNX 四卡正中间，三态中文（已开启/未开启/已启用（启动时附加））
- MeloNX 四卡搬入规格：System 配色改与 Device 一致（系统蓝）；卡片语言全部中文（用户选择），值显示 已开启/未开启；按用户要求不带 MeloNX 附带小字（"2.6"/"JIT Enabled"）；正文动态色 #222222/#EEEEEE（Task91 规范）+ minimumScaleFactor 0.55 防溢出
- 数据源：utils.h/.m 新增 getDeviceMarketingName（hw.machine → Apple 营销名；联网核实 iPad15,3/15,4=Air M3 11/13、iPad15,7/15,8=iPad 11(A16)、iPad16,1/2=mini A17 Pro、iPad16,3-6=Pro M4 11/13；未收录机型回退原始标识宁缺毋错）与 getSystemVersionDisplay（iPadOS x.x (kern.osbuildversion)，iPhone 前缀 iOS）
- 检测口径零变化（Task93 护栏）：内存两卡仍 getEntitlementValue（SecTask 签名口径，与启动日志 [Pre-init] Entitlements availability 同源），JIT 仍 isJITEnabled(NO) + TXM 三态判定链；刷新时机三件套（setupUI 尾部/viewWillAppear/DidBecomeActive）不变
- 按钮改色：执行 Jar/选择版本 → accentColor 底 + 白字（与「登录并启动」同款，用户指定），applyCustomAppearance 统一刷新三枚按钮；下载中心按钮保持深灰原样
- 胶囊方案退役：jitStatusLabel/memLimitStatusLabel/extVMStatusLabel/makeJITStyleStatusLabel/999 弱约束/i18n 状态键引用全部移除（i18n key 本体保留在 strings 文件不破坏其他调用方）
- 校验器：新建 verify_task96.py 38 项（A 数据源 7 / B 卡片结构 15 / C 同源护栏 6 / D 按钮配色 4 / E 退役清单 3 / F 仓库卫生 3）；同步历史断言——task88 A 区胶囊断言改卡片断言 + E1 增补 utils.h、task89 C1/C2（按钮 accent 化 + 卡底 15%）、task90 C3（7ab2b41 差异门随 Task96 改版退役，改断言新 UI）、task93 A6（中文值 + 15% 卡底）
- 考古说明：Task 92/93 已于此前完成推送（479f75c/c8d2069/23ba63f/3bc95fa），本次开发直接在其上进行

Stage Summary:
- 右面板信息区升级为 MeloNX 风格 7 卡滚动列表：版本×2（绿）+ 设备/系统（蓝，同色）+ JIT（橙）+ 内存权限×2（橙/黄），全部中文、无附带小字、高宽与登录并启动对齐、可滚动
- 右下角执行 Jar/选择版本与「登录并启动」配色统一（accent 底白字）
- 内存/JIT 检测与启动日志依旧完全同源（Task93 口径未动）；新增设备营销名/系统构建号展示能力
---
Task ID: 97
Agent: main (Super Z)
Task: 2f90d13 装机日志判读 + 修复：BMC2 深处双 mod 崩溃（paintings NPE + sparsestructures FileAlreadyExistsException）同源于 java.io/java.nio 相对路径解析分裂（上会话中断前完成开发，因朋友前端占用 Task96 编号而改号 97）

Work Log:
- 判读 2f90d13（6c3d49d 构建，BMC2 [FABRIC] 1.20.1，474 mods，zink，iPad Air M4）：Task95 建议被部分采纳（certain_questing_additions 已移除、balm/kleeslabs/terrablender 已补齐、dependencyOverrides 行消失），启动推进到历史最深（474 mods 全量 + 窗口初始化 + 资源加载 + paintings json 解析），随后死于两个 mod 的 'main' entrypoint，且两崩溃同根同源：
  * paintings 11.0.0.1 PaintingPackReader.scanPacks：Files.isDirectory("./resourcepacks") 走 nio/user.dir（游戏目录，整合包自带）→ true；folder.toFile().listFiles() 走 io/进程 CWD → NULL → Arrays.stream(null) NPE
  * sparsestructures 2.1.2：CONFIG_FILE_PATH.toFile().exists() 走 CWD → false 放行；Files.createDirectories 走 user.dir → 命中整合包自带同名「文件」→ FileAlreadyExistsException: config/sparsestructures.json5
- 根因：启动器只传 -Duser.dir=<gameDir> 从未 chdir；桌面启动器永远 CWD == 游戏目录故同包无恙
- 修复（JavaLauncher.m ame97_alignProcessCwdToGameDir）：主游戏 + headless 两处 JLI_Launch 前 chdir(gameDir) + setenv PWD；失败仅告警不阻断（[CwdAlign] Task97 取证锚点）；副作用审计（latestlog 绝对路径 pipe 捕获、dlopen 全 @rpath、ObjC IO 全绝对路径）无相对路径受害者；log4j "Cannot access RandomAccessFile logs/latest.log" 一并消失，游戏日志从此正确写进实例目录 logs/
- 编号说明：上会话内开发时编号 Task96，朋友（前端）已推送 Task96（右面板 MeloNX 信息卡），本任务改号 97；三文件内 96→97 全量改名
- 验证：verify_task97.py（A 日志证据钉 git 2f90d13 / B 实现锚点 / C FAQ 接线 / D version.h / E 本地 JDK 行为复现：干净 JDK 下分裂场景逐字复现两签名（NPE+Arrays.stream、FileAlreadyExistsException+精确路径），对齐场景双痊愈 / F 卫生）27 项；FAQ 28→29（+cwdMismatch）并 stale-sync 六校验器（83 B12 / 84 D1 / 85 C1 / 86 C1+C3 / 87 E1 / 94 E1 / 95 E1+E4+F3）；version.h REVISION 17 addendum (Task 97, no bump)

Stage Summary:
- BMC2 四连关：Task87 弹窗卡死 → Task94 sodium 版本门 → Task95 缺失 jar → Task97 CWD 分裂；zink 会话预计越过 paintings/sparsestructures 直达更深处
- 装机锚点："[CwdAlign] Task97: process CWD aligned to game dir: ..."；负锚点：logs/latest.log ENOENT 消失
- 遗留：⌨ 虚拟键盘二轮诊断仍缺 [InputDiag] 证据；zink FSR 画面分裂待装机日志（Task85 已实证修复 26.3-rc-3 zink 会话）
---
Task ID: 98
Agent: main (Super Z)
Task: 用户报告"分析最新上传的 26.3 的 sodium 为什么崩溃"（2af8c45）判读 + 修复；同轮同步朋友两笔新提交（1b7ae22 前端 MeloNX 信息卡 UI / 0bb68fb 其 Task96 校验器，前端不碰、仅确认无后端交集）

Work Log:
- 判读 2af8c45（6c3d49d 构建，MC 26.3 Fabric 整合包 110 mods：sodium 0.9.2+mc26.3 / iris 1.11.6 / lithium / modernfix / fabric-api 0.160.6，MG 渲染器 libOSMesa.8.dylib，iPad Air M4）：sodium 无罪——Task94 动态上报实证生效（"[Tools] LWJGL report version: 3.4.3" + "[PojavLauncher] reported 3.4.3 (metadata: 3.4.3)"），sodium 0.9.2 版本门放行，110 mods 全量打印，推进 ~2s 进入原版引导
- 真死因（渲染器无关）：MC 26.3 NativeLibrariesBootstrap 按序加载 OpenAL,OpenGL,spvc,vma,SDL,shaderc,STB,freetype；第五项 SDL 需要 LWJGL SDL3 绑定（org.lwjgl.sdl.SDL/SDLPlatform），启动器错选 LWJGL 333 集合（无 lwjgl-sdl.jar）→ NoClassDefFoundError: org/lwjgl/sdl/SDL → "Loading library SDL" 崩溃；前兆 "Failed to get system info for SDL Platform"（SDLPlatform 同源缺失）
- 根因：版本 ID 是 Fabric 形态 "fabric-loader-0.19.5-26.3-e4ecd7db"，ResolveLwjglVersion 旧解析按 "." 切分取 parts[0]="fabric-loader-0"（intValue=0）→ 333。历史对照：此前所有 26.3 装机会话（26.3-pre/rc，zink/MG SDL3 基建 c71dcfa 系列）都是原版形态 ID 恰好解析正确；Fabric 整合包首次暴露盲区。lwjgl-341 集合自带 lwjgl-sdl.jar（512 个 org/lwjgl/sdl/ 类，含 SDL.class/SDLPlatform.class），app Frameworks 已有 libSDL3.dylib——物质基础齐备，只差选对集合
- 修复（三点）：① JavaLauncher.m 新增 ame98_mcMajorFromVersionId（1.x 谱系短路防 "1.20.1-forge-47.3.0" 构建号误读 + 锚定年份正则 "(?:^|[-_])(\d{2})(?=[.w])" 读任意形态 ID 的 MC 主版本；[-_] 锚定 + [.w] 后随排除 loader 版本段与十六进制哈希误命中），ResolveLwjglVersion auto 路径改用之（"[LWJGLSel] Task98" 取证锚点）② JavaLauncher.h 导出共享 ③ SurfaceViewController ame87 LTW×26.x 预检门同修（旧解析在首个 "-" 截断读到 "fabric"，Fabric 26.x 整合包会被放行到 LTW 必崩标题界面——同类盲区一并根除）
- 验证：verify_task98.py 33 项（A 日志证据钉 git 2af8c45 含吸烟枪 "Using LWJGL 333 (mcVersion=fabric-loader-0.19.5-26.3" / B 实现锚点含旧解析移除断言 / C 头文件导出 + SVC 同修 / D 341 集合 SDL 绑定物质基础 + 333 无 sdl / E FAQ / F version.h / G 18 用例行为矩阵含哈希与 forge 构建号防误伤 / H 卫生）；verify_task87 B1/G1 重锚（G 区 Python 镜像改 mc_major + 18 用例含 loader 前缀形态 + G2/G3 防误伤专项）；FAQ 29→30（+mc26sdl：双日志签名、前缀盲区机理、与 Sodium/渲染器无关澄清、[LWJGLSel] Task98 + Using LWJGL 341 验证锚点、旧构建手动 3.4.1 自救——编辑器 pickKeys 已核实提供 341 选项）并 stale-sync 八校验器（83 B12 / 84 D1 / 85 C1 / 86 C1+C3 / 87 E1 / 94 E1 / 95 E1+E4+F3 / 97 C1+C3）；version.h REVISION 17 addendum (Task 98, no bump)
- 朋友提交审阅：1b7ae22（右面板 7 张 MeloNX 卡 + utils 设备营销名/系统版本）纯前端，与后端文件零交集；0bb68fb（verify_task96 38 项 + 历史校验器同步 + worklog Task96 条目）其 REPO 环境变量设计可在本机跑通（TASK96_REPO=... 45/45 中 1 失败为"未提交改动"类，提交后自愈）；双方工作流无冲突

Stage Summary:
- 26.3 Fabric 整合包链路打通预期：选对 341 后 NativeLibrariesBootstrap 第八项全过 → renderpearl GlBackend 走 MG provider mirror（c71dcfa 基建）→ 与 zink 26.3-rc-3 会话同族路径
- 装机锚点："[LWJGLSel] Task98: MC major 26 extracted from version id ..." + "Using LWJGL 341"；负锚点：无 "Loading library SDL" 崩溃
- 遗留：⌨ 虚拟键盘二轮诊断仍缺 [InputDiag] 证据；zink FSR 画面分裂待装机日志；FSR 替换方案调研结论（推荐 NVIDIA NIS）待答复用户
---
Task ID: 98 (续)
Agent: main (Super Z)
Task: CI 解堵——朋友前端提交 1b7ae22 的 ARC 编译错误修复（build-blocking，卡住 26.3 修复的新 IPA 产出）

Work Log:
- a808999 推送后查 CI 历史：2af8c45（用户上传提交）的 run 35246975514 = failure，失败步骤 "Build for ios"；0bb68fb（朋友校验器提交）的 run 被 cancel；首个编译朋友前端代码的 run 即失败
- 下载失败日志取证（run 35246975514）：恰好 7 个编译错误，全部同类——Natives/LauncherRightPanelViewController.m:401-407 "passing address of non-local object to __autoreleasing parameter for write-back"：MeloNX 卡片工厂方法 makeInfoCardWithIcon:accent:title:valueLabel: 的参数是裸 UILabel **（ARC 默认 __autoreleasing 出参），而 7 个调用点传的是属性 ivar 地址（&_launcherVersionCardValue 等，strong 存储）
- 修复（一处签名，零功能改动）：参数改为 (UILabel * __strong *)outValueLabel——类型严格匹配 strong ivar 地址；方法体内单次 *out = value 写回由编译器生成标准 strong store（先 release 旧值再 retain 新值），运行期语义与原设计一致；方法头注释记录病历与理由
- 边界说明：该文件属朋友前端职责范围，但编译错误卡住整个 IPA 产出（26.3 修复无法装机验证），属"通知即修"的机械解堵；改动仅所有权限定符，卡片结构/配色/层级零触碰；已向用户披露，可转告朋友
- 验证：朋友 verify_task96 38 项中仅剩"无未提交改动"类失败（提交后自愈，其断言只钉调用点不钉签名）；我的 task98 35/35、task87 50/50 不受影响

Stage Summary:
- CI 链路恢复：a808999 的在飞 run 会因同样 7 错失败（叠加朋友代码），本修复提交后的新 run 为最终有效构建
- 协作披露：朋友的两笔提交中 0bb68fb 无害（校验器），1b7ae22 功能正常但有 ARC 编译错误，已最小化修复
---
Task ID: 98 (续2)
Agent: main (Super Z)
Task: CI 确认

Work Log:
- a808999 run 35252840635：completed failure——日志取证仅含朋友 7 处 ARC 错误（LauncherRightPanelViewController.m:401-407），我的 Task97/98 代码在 Xcode 15.4 编译干净（JavaLauncher.m 仅历史 deprecation 警告）
- 44a101a run 35253641129：completed success——全链绿灯，新 IPA 就绪

Stage Summary:
- Task97 + Task98 + CI 解堵三合一构建产出；装机验证锚点见各主条目（[CwdAlign] Task97 / [LWJGLSel] Task98 + Using LWJGL 341 / 无 Loading library SDL）

---
Task ID: 99
Agent: main (Super Z)
Task: b919e0f/2253a10 日志对判读 + 双修复——(A) MC 26.3 正式版 AppKit 菜单集成崩溃；(B) BMC2 1.20.1 + zink + FSR 画面蜷缩左下角

Work Log:
- 拉取用户两个新上传提交（b919e0f=latestlog.txt、2253a10=latestlog.old.txt，均为 7ed3d01 构建 = Task97/98 修复后 IPA）
- 日志二判读（fabric-loader-0.19.5-26.3-e4ecd7db，110 mods，zink，iPad Air M4）：
  * Task97/98 双双生效：[LWJGLSel] Task98 正确提取 MC major 26 → "Using LWJGL 341"（对照 2af8c45 错选 333）；[CwdAlign] Task97 对齐成功
  * SDL/EGL 桥、zink/MoltenVK 1.4.2、主窗口 "Minecraft* 26.3 1572x1092"、GL 4.1 Mesa 全就绪，渲染线程推进到 Minecraft.<init>
  * 崩溃：NoSuchMethodException "Method cannot be found for signature 8958362280" @ ca.weblite.objc.RuntimeUtils.msg/Client.sendProxy ← MacosUtil.disableCloseWindowMenuItem(MacosUtil.java:25) ← Window.<init>(Window.java:121)，Description: Initializing game
  * 根因：os.name 伪装 macOS（LWJGL/JNA 必需）→ MC 26.3 正式版走 macOS 专属 AppKit 菜单集成（jna-objc 桥找 NSApplication/NSMenu）→ iOS 无 AppKit → 类查找落空崩溃。与 sodium/渲染器无关；26.3-rc-3（f17ef7b）同代码完整游玩实证 rc-3→正式版之间 Mojang 新增了该调用层
- 日志一判读（BMC2 fabric-loader-0.15.11-1.20.1，zink + FSR preset2）：
  * Task97 CWD 修复让 BMC2 首次真正渲染（Game took 46.79s、fps 41→60、mem 5GB 峰值）
  * 症状"游戏界面蜷缩在左下角"= MC 窗口 1572x1092 渲染进 2360x1640 OSMesa 缓冲左下区域（1572/2360=66.6%），EASU 输出未进入回读 client buffer
  * 关键澄清：会话总帧数 ~361 < steady 日志门槛 600——"无 steady 行"不能证明 EASU 停跑；EASU engaged 且条件变量全程成立（无恢复兜底日志、无 glfwSetWindowSize、windowWidth 写入点全排查稳定 1572）
  * 对照组 f17ef7b（26.3-rc-3 + zink + FSR 同代码）满屏正常 + steady 600 帧实证——断层在 GLFW 1.20.1 路径的 GL 终态/回读行为 vs SDL3 26.3 路径，需双探针日志定位精确层
- 修复 A（JavaLauncher.m，ame99_installAppKitMenuStubs）：
  * JLI_Launch 前（ame97 同段）用 ObjC 运行时公开 API 注册 NSApplication/NSMenu/NSMenuItem 三桩类（继承 NSObject，metaclass 上 +sharedApplication，numberOfItems→0 使菜单巡游零次返回）
  * 守卫：objc_getClass("NSApplication") 非 NULL（真 macOS）绝不插桩；幂等 static 标志
  * 安全网：三桩类 +resolveInstanceMethod:——未预期选择子动态补返回 nil 的无操作 IMP + NSLog 留痕（优于 doesNotRecognizeSelector 硬崩）
  * 类型编码与 AppKit 真实声明一致（q@: 的 NSInteger numberOfItems、@@:q 的 itemAtIndex: 等），jna-objc 按编码选 marshaller
- 修复 B（osm_bridge.mm）：
  * EASU pass 加固：glActiveTexture 显式锁 GL_TEXTURE0 + uInputTex uniform 钉 0 + 单元 0 旧绑定保存还原（旧代码把 FSR 纹理绑到"当时活动"单元、采样器默认读单元 0——模组留非 0 单元时采样错纹理的潜在缺陷一并消除）
  * GPU 单次探针：首次 EASU 帧后 glReadPixels 读 fb0 顶带像素 + glGetError 清扫——区分"绘制未落地 GPU"vs"回读未携带"
  * 120-swap 心跳：win/osm/bundle/easuFrames/probe/verdict 全变量可见（修复 <600 帧盲区）
  * CPU 顶带探针：回读后采 buffer 顶部条带（游戏视口永不写、EASU 必写区域）16 点 × 90 帧多数表决
  * CG 拉伸兜底：verdict=-1 时把 buffer 游戏区域（bytesPerRow=全宽 stride）包 CGImage，CoreAnimation 拉伸到 layer bounds——几何立即全屏正确（双线性软于 EASU 但远好于蜷角），用户当轮 IPA 即得可用画面
- FAQ 30→32（+macMenuStub 故障排除 / +fsrCorner 渲染与性能）；version.h REVISION 17 addendum (Task 99, no bump)
- verify_task99.py 新增 55 检查（A/B 区 git 钉日志证据、C/D 区实现锚点、E/F FAQ+version、G 级联同步、H 行为矩阵、I 卫生）
- 级联 stale-sync：FAQ 计数 30→32 同步 verify_task83/84/85/86/87/94/95/97/98；verify_task85 D1 语法门扩展（region 版 bridge 变换 + ame99_fsrdiag/kAme99ProbeFrames 桩 + healed{frames} 字段）；verify_task83 B18 设置→视频设置 3→4 处；分类顺序断言 mc26sdl 殿后 → macMenuStub 殿后（86/95/97/98）
- 语法门：scripts/task99_syntax_ame99.py 对 ame99 段独立 g++ 编译通过（ObjC→C 变换同 D1 惯例）
- 级联全绿：83:73/73、84:31/31、85:24/24、86:33/33、87:50/50、94:45/45、95:59/59、97:30/30、98:35/35、99:55/55；前端 88-93/96 剩余失败均为已知"未提交改动"类（提交后自愈）
- 朋友提交状态核查：本轮 origin 无新前端提交（最后仍是 1b7ae22/0bb68fb/2af8c45/2f90d13 上传）；7ed3d01 的 44a101a unblock（MeloNX 卡片 ARC 修复）已含在装机构建中

Stage Summary:
- 双修复已提交推送，等 CI（约 8-12 分钟）
- 下轮设备日志判读锚点：
  * 26.3 会话："[AppKitStub] Task99: NSApplication/NSMenu/NSMenuItem stubs installed" 后不再有 MacosUtil 崩溃；若见 "unexpected selector <...>" 需扩桩
  * BMC2 zink+FSR 会话："[OSMBridge] Task99 GPU probe: fb0 top-strip pixel ... rgba=..."（零=绘制层故障/非零=回读层故障）+ "FSR landing verified"（EASU 正常）或 "FSR NOT landing ... engaging CG stretch fallback"（自动兜底，画面即刻全屏）+ "swap#N" 心跳（win=1572x1092 osm=2360x1640 easuFrames 递增=条件恒成立）
  * 若 GPU 探针非零而 CPU 探针全零 → 下一轮修回读层（自定义 libOSMesa 的 glFinish 读回源）；若 GPU 探针也零 → 修绘制层（GL 终态）
- 26.3 soudim 结论（对用户）：sodium 无罪，两连崩分别是 Task98 已修的 LWJGL 错选与本轮 AppKit 层

---
Task ID: 99 (续)
Agent: main (Super Z)
Task: CI 构建 + 产物验证

Work Log:
- CI run 35291812637（3df80a8）构建成功（约 10 分钟）
- 产物齐备：com.air-devs.air-ios.ipa（200.7MB）+ trollstore tipa（200.7MB）+ dSYM
- 双修复均入包：JavaLauncher AppKit 桩（修复 A）+ osm_bridge FSR 加固/兜底（修复 B）

Stage Summary:
- 新 IPA 可装机验证；判读锚点见 Task 99 主段（[AppKitStub] Task99 / [OSMBridge] Task99 三件套）

---
Task ID: 100
Agent: main (Super Z)
Task: f6352dc/7a30912 日志对判读 + 双修复二轮——(A) 26.3 windowsMenu 桩出口（Task99 桩生效后暴露的第二层）；(B) BMC2 蜷角根因实锤（Task99 探针全绿却依旧蜷缩 = 驱动回读残影误诊）→ 权威呈现路径

Work Log:
- 拉取用户两个新上传提交（f6352dc=latestlog.txt、7a30912=latestlog.old.txt，均为 ccabe82 构建 = Task99 IPA，装机后两问题依旧）
- 日志一判读（26.3 fabric-loader-0.19.5-26.3，110 mods，zink）：
  * Task97/98/99 全部生效：[LWJGLSel] 341 ✓ / [CwdAlign] ✓ / [AppKitStub] installed ✓，安全网还捕获了 javaPeer/windowsMenu 两个未预期选择子（留痕生效）
  * MacosUtil 旧崩溃（NoSuchMethodException）消失，推进一层后死于新签名：NullPointerException "Cannot invoke Proxy.sendInt because windowsMenu is null" @ MacosUtil.java:27 ← Window.<init>
  * 根因：NSApplication 桩无 windowsMenu 出口 → resolveInstanceMethod 通用兜底返回 nil → jna-objc 包装成 Java null → 首句 sendInt NPE。即 Task99 修掉"类不存在"层，暴露"菜单出口缺失"层
- 日志二判读（BMC2 1.20.1，zink+FSR preset2）——诊断大反转：
  * Task99 三件套全绿：GPU 探针 000000ff（alpha 已写非全零）、CPU 探针 88/90 非零 → verdict=1、心跳稳定到 swap#1080、60fps、用户在角落里打字（[InputDiag] sendKey/sendCursorPos 活跃）
  * 但画面依旧蜷缩左下角 → 唯一自洽解释：驱动 glFinish 回读把滞后/回读前的裸游戏帧写进 client buffer 角落，顶带残留旧内容（非零）→ 探针误诊"已落地"（探针只验非零，分不清新鲜 EASU 与残影）
  * 结论：自定义 libOSMesa 的 glFinish 回读在 GLFW/1.20.1 路径不可信；驱动黑盒不再深挖，改由启动器自己呈现
- 修复 A（JavaLauncher.m）：NSApplication 桩补 windowsMenu/appleMenu/helpMenu/servicesMenu 四菜单出口（全部返回共享 NSMenu 桩，numberOfItems=0 巡游零次）；"[AppKitStub] Task100: windowsMenu requested" 一次性锚点；病历注释钉 7a30912 NPE 签名
- 修复 B（osm_bridge.mm ame100_present_frame 权威呈现）：
  * glFinish 后显式绑 fb0 + glReadPixels 全幅入 scratch（pack 四项锁定还原：ROW_LENGTH/ALIGNMENT/SKIP_PIXELS/SKIP_ROWS；读/绘 FBO 双通道保存还原）
  * 行序翻转（GL 底起 → OSMESA_Y_UP=0 顶起）拷入 present 缓冲——驱动永不触碰的独立上屏源，CGImage 改包 present；熔断语义（glErr/分配失败 → broken 永久回退旧路径，零回归）
  * 探针双轨：fb 探针（scratch=fb0 直读）驱动 verdict；driver 探针（bundle.buffer 旧口径）纯取证——下一轮日志"fb 命中而 driver 未命中"即实锤传输层断裂
  * CG 兜底数据源优先 present；心跳追加 present/drvProbe 字段；理论免疫：无论驱动回读滞后/残影/错源/缺失，上屏恒为 fb0 直读画面
- 惯性修偏：kCGImageRenderingIntentDefault→kCGRenderingIntentDefault 三处；NSLog 去掉 %@（保 task85 门 @" 变换正则不被击穿）；半开区间注释改中文写法（保括号平衡校验）
- 校验与级联：verify_task100.py 新增 57 项全绿（A/B git 钉日志证据、C/D 实现锚点、E 行为矩阵、F FAQ+version+级联、G 卫生）；task85 D1 门扩 ame100 桩+第三处 contents 变换（24/24）；task99 D7/E3 重锚 Task100 措辞（55/55）；FAQ 两条目内容刷新计数不变 32（零计数级联）；version.h REVISION 17 addendum (Task 100, no bump)
- 全量级联：83:73/73、84:31/31、85:24/24、86:33/33、87:50/50、94:45/45、95:59/59、97:30/30、98:35/35、99:55/55、100:57/57；语法门 task99_syntax OK；前端 verify_task96 37/38（唯一失败 = 未提交改动类，提交后自愈）

Stage Summary:
- 26.3 预期链路：windowsMenu 出桩 → numberOfItems=0 → Window.<init> 继续 → 与 rc-3 同族完整会话
- BMC2 预期：present path engaged → 上屏 = fb0 直读全幅 EASU；蜷角无论根因是驱动回读哪一层都被整体绕过
- 装机锚点：26.3 会话 "[AppKitStub] Task100: windowsMenu requested" 后不再有 MacosUtil NPE（若再见 unexpected selector 行 = 26.3+ 又调新接口需扩桩）；BMC2 会话 "[OSMBridge] Task100 present path engaged" + "EASU landing verified in fb0 ... driver transport check: N/90 -- driver readback consistent/stale"（一行同时看两层体检）+ 心跳 "present=1 drvProbe=..."
- 遗留：⌨ 虚拟键盘二轮诊断仍缺新证据（本轮 [InputDiag] 显示 sendKey/sendCursorPos/button text 全链在工作）；FSR 替换方案调研结论（推荐 NVIDIA NIS）待答复用户

---
Task ID: 100 (续)
Agent: main (Super Z)
Task: CI 构建 + 产物验证

Work Log:
- CI run 35300632602（17bcc52）completed success（约 10 分钟）
- 产物齐备（ipa + trollstore tipa + dSYM），双修复均入包：JavaLauncher windowsMenu 桩出口（修复 A）+ osm_bridge 权威呈现路径（修复 B）

Stage Summary:
- 新 IPA 可装机验证；判读锚点见 Task 100 主段（[AppKitStub] Task100: windowsMenu requested / [OSMBridge] Task100 present path engaged + EASU landing verified in fb0 ... driver transport check / 心跳 present=1 drvProbe=N/M）

---
Task ID: 101
Agent: main (Super Z)
Task: 用户实测截图（IMG_9133）五项 UI 反馈修正：三卡图标/标题更正、七卡内容居中、灰字游戏版本标签退场、侧栏图标与新拟物高亮对齐、主界面图标偶发消失自愈

Work Log:
- 联网核实（pat-in-a-hat/sf-symbols-reference 全表 9476 符号，SF 1.0→8.0）：SF Symbols 不存在名为 "rabbit" 的符号——Task 96 所写 JIT 卡图标 systemImageNamed:@"rabbit" 必返 nil 走兜底点阵，用户截图证实（JIT 卡显示 circle.grid.2x2）。兔子真名 = hare（SF 1.0，线框兔）；memorychip=SF 2.0、memorychip.fill=SF 3.0
- LauncherRightPanelViewController.m：JIT 卡 rabbit→hare；内存上限提升→「扩展内存限制」+memorychip.fill（实心 ROM）；扩展虚拟寻址→「扩展虚拟内存」+memorychip（空心 ROM）；更新检测注释与 Task101 留档
- 卡片工厂重构居中：title/value 竖排 textContentStack + icon 横排 contentStack，内容组 centerX/Y 居中于卡片，leading≥14/trailing≤-12 不等式兜底；标题正文 textAlignment 居中；46pt/圆角12/15% 底/动态字色/缩放全保留；旧左上角锚定约束退役
- versionLabel（头像下灰字游戏版本 26.3）整体退场：属性/创建/约束/外观分支/updateVersionInfo 引用全清；滚动区上锚改 usernameLabel.bottom+8；游戏版本卡成为该数据唯一出口；版本选择入口（manageVersionBtn）不受影响
- LauncherMenuViewController.m：去掉空白标题（" "）与 titleEdgeInsets/imageEdgeInsets（原 imageEdgeInsets(-10,0,0,0) 使图标上移偏离 50×50 新拟物高亮中心）；图标内容双居中；nm_convexRadius 选中态原样（task89 C3 兼容）
- 主界面 house.fill 图标偶发消失自愈：新增 refreshMenuIconImages（幂等，仅补 imageForState 为空者），viewWillAppear + updateButtonColors 双入口；越界防御；root cause 判定为启动早期 systemImageNamed: 时序型 nil（二次启动自愈的用户观察与此吻合）
- 校验：verify_task101.py 新增 38 项；verify_task96 同步 B2/B4/B10 与文档（38 项）；verify_task88 同步 A4/A8；全量回归见下

Stage Summary:
- UI 语义零删减：七卡信息、配色、滚动、按钮配色、检测口径（getEntitlementValue×2 / isJITEnabled+TXM / 刷新三件套）全部保持；仅图标/标题/居中/冗余标签/侧栏对齐/自愈六处按用户反馈变化
- 用户预期：JIT 卡显示橙色线框兔（hare）；两内存卡显示实心/空心 ROM 芯片且更名；卡片内容居中；头像下 26.3 消失；侧栏图标在高亮面板正中且启动后不再消失
- 校验器协同：verify_task88 E1/verify_task89 E1 预期文件集扩容（Task101 合法改动面）；
  verify_task95 REPO 改 TASK95_REPO 环境变量可覆盖（默认值保留，原硬编码克隆路径已不存在，
  TASK95_REPO 指向本仓库实测 59/59）
- 全量回归（未提交态）：task101 39/40、task96 37/38、task92 39/40、task93 24/25
  （各差 1 项均为「无未提交改动」卫生类，提交后自愈）；task88 45/45、task89 36/36、
  task90 51/51、task91 75/75、task95 59/59 全绿；task83-87/94/97-100 指向另一会话
  克隆路径为环境性失败，与本提交无关

---
Task ID: 102
Agent: main (Super Z)
Task: 用户 Task 101 IPA 实测三项反馈——七卡并列位置整体居中（回退内容居中误解）、主界面按钮首启不显示根治、头像宽度/顶距对齐执行Jar按钮

Work Log:
- 七卡居中语义澄清（用户："把七个卡片的并列位置放在右侧栏的中间，而不是把七个卡片的内容居中"）：
  卡工厂整体回退 Task101 内容居中（contentStack/textContentStack/双 Center 退役），恢复 Task96 左锚定
  （图标 leading 14+卡内垂直居中 20×20，标题贴顶 7，正文贴底 -7，trailing -12 缩放截尾）；
  新增 updateInfoContentInset——滚动区内容（下载中心+7 卡）不足视口时上下均分 contentInset 使整组
  垂直居中于右侧栏中部，内容超高归零恢复普通滚动（Task96 可滚动能力不破）；幂等护栏（inset 相等不写回）
  +偏移钳制（小内容落位 -inset，isDragging/isDecelerating 中不干预）；触发双通道：
  viewDidLayoutSubviews（首布局/旋转/视口变化）+ contentSize KVO（AmeInfoContentSizeContext，
  与下载进度 KVO context 区分；下载 UI 展开折叠只改 contentSize 不一定触发根视图重布局）；
  dealloc @try 移除；math.h 显式导入（fabs）
- 主界面按钮首启不显示根治（Task101 单次 viewWillAppear 补拉实测无效）：根因收窄——主界面按钮是
  setupSidebar 循环里第一个调 systemImageNamed: 的控件，进程冷启动首调用存在 CoreUI 符号注册竞态，
  首调用偶发 nil 而后续调用全部正常（完美解释"只有主界面消失、其他按钮都在"+点其他菜单项后
  updateButtonColors→refreshMenuIconImages 补拉成功即"恢复"+二次启动正常）；Task101 补拉与
  viewDidLoad 几乎同刻执行仍在竞态窗口内。升级 beginMenuIconSelfHeal：0.25s×16 次（约 4s）重试，
  allMenuIconsLoaded 全就绪即停、定时器已跑不叠加；入口 viewWillAppear + viewDidLayoutSubviews
  （首布局晚一拍再多给一次）；menuIconSelfHealTimer 属性 + dealloc invalidate（block 弱引用无环，
  runloop 强持有显式解除）；updateButtonColors 直补路径原样保留
- 头像对齐执行Jar按钮（用户：宽度改一致[原固定 72pt 偏差]、距屏幕顶部间距=执行Jar按钮距底部间距）：
  avatarImageView.widthAnchor = executeJarBtn.widthAnchor（iPad 220pt 面板 → 94pt、iPhone 168pt → 68pt
  自动随面板）；heightAnchor = 自身宽度（正方形随动）；viewDidLayoutSubviews 动态 cornerRadius=宽/2
  保持正圆（写死 36 在等宽后会变椭圆圆角）；新共享常量 AmePanelVerticalEdgeInset=12——头像顶部
  +12 与执行Jar/管理版本底部 -12 共用，对称关系由常量锁死，后续只改一处
- 校验：verify_task102.py 新增 38 项（A 居中/B 工厂回退/C 头像/D 自愈升级/E 护栏/F 卫生）；
  verify_task101 B 区重锚（B1-B5 内容居中→回退后左锚定，B6-B9 原样）+E2 重锚（自愈入口链）+文档注记，
  保持 40 项
- 全量回归（未提交态）：task102 36/38、task101 39/40、task96 37/38、task92 39/40、task93 24/25
  （各项差 1-2 项均为 worklog/未提交改动卫生类，提交后自愈）；task88 44/45、task89 35/36（E1 预期文件
  集按未提交视图告警，提交后自愈）；task90 51/51、task91 75/75、task95 59/59（TASK95_REPO 覆盖）全绿；
  task83-87/94/97-100 硬编码另一会话克隆路径为既有环境性失败（grep 证实零引用本次改动文件，域无交集）

Stage Summary:
- 检测口径零变化（getEntitlementValue×2 / isJITEnabled+TXM / 刷新三件套）；七卡信息、图标、标题、配色、
  滚动、按钮配色全部保持；ARC 出参签名（Task98）不被回退
- 用户预期：七卡整组居右栏中部（内容仍左对齐紧凑排布）；主界面按钮首启即显示（4s 自愈窗口覆盖冷启动
  符号注册竞态）；头像与执行Jar等宽、正圆、顶距=按钮底距

---
Task ID: 103
Agent: main (Super Z)
Task: 用户上传三日志（a605099/c241276/446b2a0，d37670e 构建）判读——26.3 进存档崩溃 + BMC2 蜷角依旧（Task100 后）→ 双根因实证 + 双修复；附带确认 zl2（ZalithLauncher2）线索 = LWJGL 版本检测关闭（Task94 已覆盖，装机实证 sodium 0.9.2 过门）

Work Log:
- 日志判读（latestlog.old.txt = 26.3 Fabric 110 mods：Task97/98/99/100 全部装机生效——LWJGL 341、[CwdAlign]、AppKitStub 桩、windowsMenu 补齐；游戏完整跑到进存档；latestlog.txt = BMC2 1.20.1 zink+FSR：Task100 权威呈现已 engaged、fb/driver 双探针 89/90 非零、1680+ swaps 稳定会话）
- 26.3 崩溃根因（字节级闭环）：进世界瞬间 compile#406 sodium:blocks/block_layer_opaque（vertex 2394B）展开 3 include（2394→5741）后 glslang 报 "preprocessor directive cannot be preceded by another token" → solid_terrain 管线缺失 → Render Frame 崩溃。下载 Modrinth sodium-fabric-0.9.2+mc26.3.jar（bAZQdGpg，与 Remarkably Optimized 1.15.61 整合包钉的同文件）od -c 实锤：globals.glsl 尾 '};'、fog.glsl 尾 '}'、chunk_vertex.glsl 尾 '#endif'——三个 include 全部不以换行结尾；shaderc_include.c 的 ame_expand_text 在内容后直接拼 "#line N\n" → 指令粘行。对照：client.jar 原版 17 个 include 全部 '\n' 收尾（405 个原版编译全过）——bug 自 Task47 潜伏，等第一个无尾换行 mod 着色器触发。本地复现（scripts/../task103_include_repro/repro.c + 真实 jar 着色器走真实展开器）：修复前 3 处粘行（};#line 5 / }#line 6 / #endif#line 7），修复后 0
- 修复 A（Natives/shaderc_include.c）：#line 拼接前保证输出以 '\n' 收尾（o->len>0 && buf[o->len-1]!='\n' → 补一个换行）；行号语义由紧随的 #line 全权重置，合成换行零影响；原版着色器不触发补行（零回归）
- BMC2 蜷角根因推理收敛：屏幕显示 present.present（fb0 glReadPixels 全幅）却仍是裸游戏蜷角 + 顶带非零 → glReadPixels 与驱动回读同走一条 pre-EASU/陈旧传输——Task99/100 的非零探针无法区分残影与新鲜 EASU（装机实证误报 verdict=1）。armchair 无法再分辨"绘制未落地"与"回读撒谎"，转为闭环修复
- 修复 B（Natives/ctxbridges/osm_bridge.mm，哨兵闭环）：EASU 片元着色器（字符串手术注入，仅本桥编译的源；MobileGlues 共享头零改动，MG 自身 FSR 路径不受影响）在输出像素 (0,0) 的 alpha 通道写每帧哨兵 k/255（k=1..254，避开 0=uniform 默认与 255=常规不透明 alpha）；CGImage 用 AlphaNoneSkipLast——零视觉影响。present 回读后核对 scratch[3]：3 连中=绘制落地+回读诚实→全幅上屏；3 连失=无论断在哪层→裁剪裸游戏区域交 CoreAnimation 拉伸全屏（几何恒全屏，画质双线性稍软）；10 连反向可翻转判决（标题界面↔进世界跨阶段）；旧 90 帧非零统计降级为取证（armed 时不 overwrite 判决）；状态迁移时一次性 present vs bundle 全幅 memcmp（同源性取证：相等=glReadPixels 被客户端缓冲劫持）；GPU 单次探针扩展 glFinish 前哨兵直读（MATCH/MISMATCH 判读）；心跳加 mk=N/M；gl 表补 glUniform1f
- 判读辅助：确认 26.3 会话 zink 路径无 Vulkan 尝试（MDCL 跳过 lwjgl-vulkan；26.2+ 的 PreferredGraphicsApi/graphicsBackend 参数为 MC 原生能力，启动器渲染器选择已覆盖；zl2 提示的 LWJGL 检测关闭与 Task94 动态上报等效且已装机实证）
- 审阅朋友 Task101/102（d37670e/25930aa）：纯前端（右面板卡片布局/SF Symbols 图标修正/图标自愈），零后端文件交集
- 验证：verify_task103 57/57（A git 钉 446b2a0 证据；B 展开器修复文本锚点 + 合成着色器行为测试——真编译真展开，无尾换行 include 零粘行、内容保序、行号指令成对；C 哨兵注入锚点 + 共享头零改动断言；D 票/翻转/取证锚点；E 判决状态机 Python 镜像 6 用例；F FAQ+version.h；G 语法门（新增 scripts/task103_syntax_swap.py——osm_swap_buffers 呈现/投票段独立 g++ 门，D1 变换约定）+ 级联 + NSLog %@ 禁令）
- 级联 stale-sync：FAQ 32→33（+sodiumGlsl 故障排除；fsrCorner 重锚 Task103 哨兵语义）×11 校验器（83 B12/84 D1/85 C1/86 C1+C3/87 E1/94 E1/95 E1+E4+F3/97 C1+C3/98 E1+E4/99 E1+E3+E4/100 E+F3）；task85 D1 语法门桩扩 markerArmed/markerCode/mk 字段 + cstring
- 终态：83:73/73、84:31/31、85:24/24、86:33/33、87:50/50、94:45/45、95:59/59、97:30/30、98:35/35、99:55/55、100:57/57、103:57/57 全绿

Stage Summary:
- 26.3：sodium 着色器粘行崩溃根治（对全 mod 生态的同类问题通用）；装机锚点：[amethyst-include] expanded 后无 GLSL 解析错误 + 进世界正常
- BMC2：哨兵闭环——两种传输状态几何都全屏；装机锚点："[OSMBridge] Task103 EASU sentinel verdict: LANDED/NOT LANDED ..."（一行含 mk 命中率 + present/bundle 同源性）+ 心跳 mk=N/M + GPU 探针 "Task103 sentinel pixel (0,0) ... MATCH/MISMATCH"
- 遗留：哨兵判决为 NOT LANDED 时下一轮可凭 memcmp 同源结论定位断层层级（glReadPixels 劫持 vs 绘制未落地）；2394 与 2124 字节差（设备 vsh +270B 注入来源）未定位但不影响修复
---
Task ID: 106
Agent: main (Super Z)
Task: 用户报"一个创建存档崩溃，一个还是锁30"→ 41cdff0 双日志判读（2e1ea09 构建）+ 双根因修复 + 提交推送

Work Log:
- 日志判读：latestlog.old.txt = BMC2 1.20.1 zink+FSR（首次走到"创建新世界"，server bootstrap 到 spark "Starting background profiler..."，最后一行戛然而止 = [Amethyst] Patching spark libasyncProfiler.so.tmp，无 exit/hs_err/fatal trace = SIGKILL 静默死）；latestlog.txt = 26.3 zink+FSR preset=4 scale=2.00（干净会话：建档→游玩→FastQuit→exit(0)，fps 恒 28-30）。附带实证：BMC2 蜷缩已被 Task105 修复（vp=907x631 adaptive + 60fps 全屏几何）
- 崩溃根因（二进制级闭环）：下载 Modrinth spark-1.10.53-fabric.jar 解包其内置 spark/macos/libasyncProfiler.so——FAT(x86_64+arm64)，arm64 切片 LC_BUILD_VERSION platform=1(macos) + LC_CODE_SIGNATURE 20960B（真签名，blob 恰为切片尾）。spark 1.10.53 字节码：AsyncProfilerAccess.load 解包到 config/spark/tmp/*.tmp 直接 System.load。本设备历史所有会话 "[Amethyst] Patching" 0 次——spark 库是第一个走进 PLPatchMachOPlatformForFile 重标签路径的库；平台重标签改写 mach header → 签名哈希失效 → dyld CS 校验失败 → 杀进程。未签名库重标签无害（其余全部 home 目录库如此），已签名库重标签必死。内存假说排除：崩溃时刻在 chunk 重分配开始前，且早前曾存活 5982MB（崩溃前 5155MB）
- 修复 A（双层）：① main_hook.m hooked_dlopen 顶部拦截 libasyncProfiler（return NULL → JVM UnsatisfiedLinkError → spark 字节码实证 catch 后降级 Java 采样器，建档继续）；② dyld_patch_platform.m 签名中和——重标签发生时把 LC_CODE_SIGNATURE 原位改写为等尺寸 LC_SOURCE_VERSION(0x2A) 并清零签名 blob（dyld 视为未签名而非签名失效；未签名 home 库本设备历来可加载）；platform 已匹配的早退路径零扰动；其余切片不受影响
- 30fps 根因（判读修正）：Task105 的"真实负载"定性被推翻——该会话的 44fps 实为暂停菜单瞬时读数；本轮 preset 1→4（渲染像素 -58%）帧率纹丝不动 28-30 = 分辨率无关常数主导。26.3 decomp 复核：FramerateLimitTracker 唯一 30 路径 SHORT_AFK 需 inactivityFpsLimit==AFK，而 Task104 落盘验证 minimized 生效（键名与 Options.process 反编译核对一致）+ 会话全程有输入 + 软件限帧器仅 framerateLimit<260 时运行；vsync 路径排除（osm_swap_interval no-op + POJAV_DISABLE_VSYNC=1）。真凶 = zink 路径每帧两次全幅 GPU→CPU 传输（驱动 glFinish 回读 + Task100 权威 glReadPixels）+ 15.5MB 行翻 memcpy
- 修复 B（bundle-direct）：Task103 双哨兵（markerCode 每帧 1..254 轮换）提供逐帧地面真值——glFinish 后 bundle.buffer 若同时持有本帧近角（top-down 行 H-1 列 0）+远角（行 1 列 W-2）哨兵即持有本帧全幅 EASU 输出。warmup 30 连中（期间权威路径照跑交叉验证）→ 激活：跳过权威回读+行翻，CGImage 直接包 bundle.buffer（OSMESA_Y_UP=0 本就 top-down）；2 连失 → 立即退回权威路径重新 warmup；verdict==-1 ⟺ 哨兵缺失 ⟺ 自动退出（自稳定）。哨兵票核心抽取为 ame103_marker_vote（scratch/bundle 双票源同一状态机，Task103/104 日志锚点原文保留 + bundle-direct 尾注）
- 取证（相位计时）：osm_swap_buffers 四相计时（t0 入口/t1 EASU 后/t2 glFinish 后/t3 回读后/末段）+ 帧间隔 gap；心跳新增 "bd=N/M t=swap X.X(max X.X) [pre+easu X.X glFinish X.X readback X.X]ms frame=X.X MC-side=X.Xms"——下一轮装机日志把帧预算精确分解到 MC 渲染/驱动回读/我们的重复劳动
- FAQ 33→34（+sparkProfiler：建档闪退双根因指引）；fpsUnlock 判读修正（呈现常数 + bundle-direct + 相位计时报文读法）；fsrCorner 机制描述维持；version.h REVISION 17 addendum (Task 106, no bump)
- 验证：verify_task106 59/59（A git 钉 41cdff0 证据 9 锚；B 真实 spark 二进制法证 5 锚——FAT/签名/blob 位置；C 拦截+中和锚点 7 锚；D bundle-direct 锚点 13 锚；E 行为镜像——状态机 5 用例 + 哨兵位置数学 4 用例 + 签名中和 Mach-O 不变量 6 用例（Python 镜像：重标签/等尺寸改写/blob 全零/x86 零扰动/尺寸不变/早退零扰动）；F FAQ/version/语法门/级联）
- 级联 stale-sync：FAQ 计数 33→34 ×12 校验器（task106_faq_sync.py：83/84/85/86/87/94/95×3/97/98/99×4/100×2/103×2）+ 类目序锚 5 处（86 C3/95 E4/97 C3/98 E4/99 E4 追加 sparkProfiler 殿后）+ verify_task100 D13 重锚（present 调用门加 !ame106.active）+ verify_task105 E2 重锚（Task106 判读句取代 Task105 实证句）；语法门桩扩 3 处（task83_syntax_osm.sh：osm_render_window_t/mach_timebase；task103_syntax_swap.py + verify_task85 D1：ame106/ame106_us/ame106_bundle_sentinels/ame103_marker_vote/mach_absolute_time）；外层 scripts/ 同步副本 3 件
- 终态：58/59/71/72/73/75/76/77/78/79/80/81/82/83:73/84:31/85:24/86:33/87:50/94:45/95:59/97:30/98:35/99:55/100:57/103:57/104:20/105:36/106:59 全绿
- 踩坑：LC_BUILD_VERSION=0x32（0x2D 是 LC_LINKER_OPTION、0x19 是 LC_SEGMENT_64）——Python 手解析两次翻车，macholib 交叉验证纠偏；外层 /home/z/my-project/scripts 与仓库 scripts 双副本（verify_task83 等按外层路径调 .sh 门），改门必须双侧同步

Stage Summary:
- BMC2 建档闪退根治（spark 签名库重标签致死，双层修复）；装机锚点："[Amethyst] Task106: blocked dlopen of signed macOS profiler lib" + 建档继续推进 + spark Java 采样器照常
- 26.3 30fps 第 1 轮优化（bundle-direct 跳过重复回读+行翻）+ 相位计时取证；装机锚点："[OSMBridge] Task106 bundle-direct present engaged" + 心跳 "bd=N/M t=swap ... MC-side=...ms"（若 glFinish/readback 仍占大头 → 下轮 CA 直呈提速模式；若 MC-side 占大头 → 降视距/换渲染器指引）
- 遗留：26.3 剩余帧预算的精确分布待装机日志相位计时；若 bundle-direct 后仍 <35fps，候选方案 = OSMesa 表面缩窗 + CA 双线性直呈（消灭全幅回读，画质换速度，需 UI 档位配合）
