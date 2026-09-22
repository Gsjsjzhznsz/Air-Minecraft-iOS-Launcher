#pragma once

#include <Foundation/Foundation.h>
#include "jni.h"

typedef jint JLI_Launch_func(int argc, const char ** argv, /* main argc, argc */
        int jargc, const char** jargv,          /* java args */
        int appclassc, const char** appclassv,  /* app classpath */
        const char* fullversion,                /* full version defined */
        const char* dotversion,                 /* dot version defined */
        const char* pname,                      /* program name */
        const char* lname,                      /* launcher name */
        jboolean javaargs,                      /* JAVA_ARGS */
        jboolean cpwildcard,                    /* classpath wildcard*/
        jboolean javaw,                         /* windows-only javaw */
        jint ergo                               /* ergonomics class policy */
);
JLI_Launch_func *pJLI_Launch;

int launchJVM(NSString *accountId, id launchTarget, int width, int height, int minVersion);

// Task98：从任意形态的版本 ID（原版 "26.3" / 快照 "26w14a" / Fabric
// "fabric-loader-0.19.5-26.3-e4ecd7db" / Forge "1.20.1-forge-47.3.0"）提取
// MC 主版本号（年份制口径）。1.x 谱系返回 1；无法解析返回 0。
// 供 ResolveLwjglVersion（LWJGL 333/341 选择）与 SurfaceViewController 的
// LTW × 26.x 预检门（ame87_mcVersionRequiresTextureBuffer）共用，
// 保证两处口径一致（详见 JavaLauncher.m 内实现头注释）。
NSInteger ame98_mcMajorFromVersionId(NSString *versionId);

// Headless JVM：在当前进程内以最小参数（无 caciocavallo/LWJGL/渲染）启动 JVM，
// 运行指定 main 类。用于 Forge/NeoForge 直装执行 install_profile 的 processors。
// 返回 JLI_Launch 的返回值（0 = 成功）；负数为启动器侧错误：
//   -1 JIT 未启用 / legacy JIT 脚本需要重启
//   -2 JLI_Launch 符号缺失
//   -3 无可用 JRE 运行时
//   -4 dlopen libjli 失败
//   -5 进程内 JVM 已创建过（需重启 app）
int launchHeadlessJVM(NSString *mainClass, NSArray<NSString *> *args, int minJavaVersion);

// 当前进程是否已创建过 JVM（游戏或 headless 任一次）。
// 进程内 JVM 只能创建一次，再次 JLI_Launch 会崩溃；调用方据此提示用户重启 app。
BOOL JVMUsedInProcess(void);

// Task 144：headless JVM 执行期 exit 抑制标志（定义在 main_hook.m）。
// Forge/NeoForge 直装的 processors 与启动器同进程，安装器 JVM 跑完时
// libjli 内部线程会 exit(0) 把整个 app 带走（用户视角"forge安装闪退"）。
// launchHeadlessJVM 的调用方（ForgeProcessorExecutor）置位/清零本标志；
// hooked_exit 命中标志时改为 pthread_exit 仅终结 JVM 线程，进程存活。
#include <stdatomic.h>
extern atomic_int g_ame_suppressJvmExit;
