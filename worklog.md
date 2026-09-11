
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
