// shaderc_include.h — Task 47：RenderPearl 26.3 `#include <minecraft:...>` 展开器
//
// 根因（latestlog a5189d5，2026-09-08）：Minecraft 26.3-pre-2 的 renderpearl
// 新渲染前端把 GLSL 统一编译为 SPIR-V，全部管线 shader 使用
// `#include <minecraft:fog.glsl>` 系指令，并通过 LWJGL 的
// shaderc_compile_options_set_include_callbacks 上行回调解析
// （GlslCompiler.createIncludeResolver → ShaderSource.getInclude）。
// 旧假设“MC 在 Java 层预解析 include”对 26.3 renderpearl 不成立：
// 回调被 glue no-op 丢弃 + 源码原样进入 glslang →
// "ERROR: '#include' : required extension not requested" → 34 个必需
// 管线全部编译失败 → ShaderManager 崩溃 → 黑屏闪退。GL 与 Vulkan 两
// 路径共享 GlslCompiler，因此同时失效。
//
// 修复策略：在 shim 的编译入口（调用者线程 = JVM 线程，LWJGL libffi
// upcall 安全）做**文本级递归展开**，展开后的干净源码统一进入磁盘缓存
// key / 源码 dump / 进程外沙箱 / 进程内 impl 全部下游路径——沙箱子进程
// 无需任何回调即可编译含 include 的管线（函数指针不可跨进程，这是沙箱
// 路径唯一可行的 include 支持方式）。
//
// include 语义（与桌面 shaderc/glslang 预处理器一致）：
//   - 逐行扫描，跳过 /*...*/ 块注释与 // 行注释内的伪指令
//   - `#include <name>` / `#include "name"`：调 resolver(user_data, name,
//     type(0=quoted,1=angled), requesting_file, depth) 取内容，递归展开
//   - 每个展开点后插 `#line <下一行号>` 恢复外层文件行号（诊断可用）
//   - 条件编译块（#ifndef/#if）内的 include 同样原位展开：条件结构保留，
//     glslang 预处理器按宏裁剪，语义与桌面完全一致（条件为假分支中即使
//     引用了缺失文件，其内联错误文本也会被条件整体跳过）
//   - 无去重（C 预处理器语义，Mojang 片段无 include guard，靠精心设计的
//     include 组合保证单编译单元无重复）
//   - resolver 返回的 result 按 LWJGL 3.4.1 ShadercIncludeResult 布局读取
//     （与 google/shaderc 公开头字段顺序不同，见下方偏移——以 LWJGL 为准，
//     因为结构由 Mojang 经 LWJGL 构造）：
//       +0   const char* source_name        +8  size_t source_name_length
//       +16 const char* content             +24 size_t content_length
//     content 不保证 NUL 终止，必须按 content_length 读取。
//   - releaser(user_data, result) 按协议在使用后调用（Mojang 实现为 no-op，
//     native 内存由 Java 侧 CachedIncludeSource.close 管理）
//
// 防御（真实 shader 最深 2 层，但按敌意输入设计）：
//   - include 深度上限 16（循环 A→B→A 截断）
//   - 展开总输出上限 64 MiB
//   - resolver NULL / 返回 NULL / content NULL：保留原行（下游报错可见）
//   - resolver 崩溃不在此层防护：调用点在 shim 编译入口（crash-net 覆盖
//     编译调用链之前，且 JNI upcall 在 JVM 线程上稳定）
#ifndef AME_SHADERC_INCLUDE_H
#define AME_SHADERC_INCLUDE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// ---- LWJGL 3.4.1 shaderc_include_result 布局（aarch64/64-bit）----
#define AME_IR_SOURCE_NAME_OFF 0
#define AME_IR_SOURCE_NAME_LENGTH_OFF 8
#define AME_IR_CONTENT_OFF 16
#define AME_IR_CONTENT_LENGTH_OFF 24

// shaderc_include_resolve_fn 的 ABI（LWJGL libffi CIF 核实）：
//   返回 result 指针；include_depth 以 pointer 宽度（size_t）传递
typedef void *(*ame_include_resolver_fn)(void *user_data, const char *requested_source,
                                         int type, const char *requesting_source,
                                         size_t include_depth);
typedef void (*ame_include_releaser_fn)(void *user_data, void *include_result);

// shaderc_include_type：quoted("...")=0 relative，angled(<...>)=1 standard
#define AME_INCLUDE_TYPE_RELATIVE 0
#define AME_INCLUDE_TYPE_STANDARD 1

#define AME_INCLUDE_MAX_DEPTH 16
#define AME_INCLUDE_MAX_OUTPUT (64u * 1024u * 1024u) // 64 MiB

// 快速探测源码是否包含 #include 指令（不区分注释；仅决定是否走展开，
// 误报的代价只是一次逐行扫描）。0 = 无。
int ame_source_has_include(const char *src, size_t len);

// 递归展开。返回 malloc 的 NUL 终止 buffer（长度写入 *out_len，不含 NUL），
// 调用方负责 free；失败/无需要展开时返回 NULL（*out_len 置 0）。
// requesting_file 透传给 resolver（Mojang 实现忽略；诊断用）。
char *ame_include_expand(const char *src, size_t len, const char *requesting_file,
                         ame_include_resolver_fn resolver, void *resolver_user_data,
                         ame_include_releaser_fn releaser, void *releaser_user_data,
                         size_t *out_len);

#ifdef __cplusplus
}
#endif

#endif // AME_SHADERC_INCLUDE_H
