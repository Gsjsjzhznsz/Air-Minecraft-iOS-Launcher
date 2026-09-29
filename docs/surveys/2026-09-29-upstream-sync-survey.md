# 上游同步调查报告（第二轮）——herbrine8403/Amethyst-iOS-MyRemastered

**调查日期**：2026-09-29（Task201 归档）
**调查范围**：fork 点 `3c13d5e5`（2026-08-31）以来的上游全部提交
**用途**：Task201（Metallum Metal 渲染器移植）的同步决策依据

## 1. 提交总量与谱系

- fork 点 `3c13d5e5`（08-31）以来上游共 **346 commits**（截至调查时点）
- 其中约 **90 commits 为我方回移**（此前轮次推送后被上游合并/采纳），标记扫描命中 76+ 处 `Task` 字样锚点
- 净新增（上游原创）提交集中在三个主题：Metallum Metal 渲染器、输入子系统修复、上游自有 bug 修复

## 2. Metallum Metal 渲染器定位

- **形态**：javaagent 注入的原生 Metal 后端（非 GL 转译路径）
  - `Premain-Class: com.metallum.agent.MetallumAgent`
  - agent jar 自带 `natives/ios` 与 `ios12111` 双套 metallum/spvc 原生库（868 entries）
- **上游实测环境**：iPhone 17 Pro / iOS 27.2，运行 26.2 / 26.3 原版 + Forge + Fabric
  - 证据提交：`cc122400`（#147）、`7ac756ca`（#148）、`184321a7`（#149）
- **移植要点**（详见 worklog Task201 主条目）：
  - 五件二进制 + `utils.h` 定义 + 渲染器表末位条目（索引稳定）
  - `JavaLauncher.m` 四块：`AMETHYST_METAL` 环境链 / `--add-opens java.base/java.lang` / `-javaagent` 注入带 `mcMajor>=26` 门控（Java 8 会话无法加载 class-65 agent 字节码）/ `-Dmetallum.mc.version` 传递
  - `shaderc_impl_glue.c` 补 `glslang_program_map_io`（Metallum 的 MetalCrossShaderCompiler 对 binding/location 敏感）
- **刻意不同步**：上游三个 spirv 裸副本（`libspvc.dylib` / `libspirv-cross.dylib` / `libspirv-cross-c-shared.0.dylib`，同一真库）——会绕过我方 Task175 串行化垫片链（并发编译互踩崩溃家族）；上游 Makefile 的 shaderc 预编译 blob——我方 Task45 从源码构建形态保持

## 3. 上游无 Metal 游玩崩溃修复

- 调查时点（09-29）扫描上游最新提交：**无** 针对 Metal 游玩中崩溃（AGX 驱动层）的修复提交
- 我方装机日志（e4d704e，latestlog.old.txt）的 Metal 会话：标题画面→游戏内→视频设置→资源重载→`createTexture` 后 JVM 崩溃于 AGX 驱动层——该症状上游议题库亦无对应修复，FAQ 已建档指引（换渲染器旁路）

## 4. 结论

- Task201 移植面完整（渲染器可选、agent 注入门控、spirv 垫片链保持）
- Metal 游玩崩溃为上游共同未解问题，等待上游修复后回移
