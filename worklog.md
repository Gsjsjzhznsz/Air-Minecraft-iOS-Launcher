
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
