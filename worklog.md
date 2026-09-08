
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
