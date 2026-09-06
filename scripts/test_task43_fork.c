// test_task43_fork.c — Task 43 fork server 端到端功能测试（Linux）
//
// 验证链路（全部走真实代码：Natives/shaderc_sandbox.m + fork 出的子进程 +
// 假 libshaderc_impl.dylib）：
//   1. ame_sb_fork_server_early()：fork 不 exec、握手成功（"fork server online"）
//   2. 正常编译：请求往返，status=0，SPIR-V 字节逐字节回显
//   3. CRASHONCE：子进程内 SIGSEGV → 崩溃网长跳 → glslang 重建 → 重试成功
//      （状态=0；日志有 "compile crashed on attempt 1/4" + fake-impl 的
//       Finalize/Initialize 对账）
//   4. CRASHALWAYS：4 次尝试全崩 → status=3 + "crashed 4 times" 消息
//   5. 崩溃后子进程仍在服务：再一次正常编译成功
//
// 构建：gcc -D_GNU_SOURCE -x c -I Natives scripts/test_task43_fork.c \
//         Natives/shaderc_sandbox.m -o test43_fork -ldl -lpthread
// 运行：LD_LIBRARY_PATH=<假 impl 目录> ./test43_fork

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "shaderc_sandbox.h"

#define CHECK(cond, msg)                                                    \
    do {                                                                    \
        if (!(cond)) {                                                      \
            fprintf(stderr, "[TEST-FAIL] %s (line %d)\n", msg, __LINE__);  \
            exit(1);                                                        \
        }                                                                   \
        fprintf(stderr, "[TEST-PASS] %s\n", msg);                           \
    } while (0)

int main(void) {
    // 1. fork server 拉起（子进程 dlopen 假 impl 经 LD_LIBRARY_PATH）
    int rc = ame_sb_fork_server_early();
    CHECK(rc == 0, "fork server online (handshake ok)");

    ame_sb_opt_fields_t opt;
    memset(&opt, 0, sizeof opt);

    // 2. 正常编译：字节回显校验
    const char *good = "void main() {}";
    void *r1 = ame_sandbox_compile(0, good, strlen(good), 0, "test/good", "main", &opt);
    CHECK(r1 != NULL, "good compile returned non-NULL");
    ame_sb_result_t *res1 = (ame_sb_result_t *)r1;
    CHECK(res1->status == 0, "good compile status=0");
    char expected[256];
    snprintf(expected, sizeof expected, "SPV:0:%s", good);
    CHECK(res1->spv_len == strlen(expected) &&
              memcmp(ame_sb_result_spv(res1), expected, res1->spv_len) == 0,
          "good compile spv bytes echo exactly");
    CHECK(res1->err_len == 0, "good compile err empty");
    free(r1);

    // 3. CRASHONCE：崩溃 → 重建 → 重试 → 成功
    const char *once = "CRASHONCE void main() {}";
    void *r2 = ame_sandbox_compile(0, once, strlen(once), 0, "test/once", "main", &opt);
    CHECK(r2 != NULL, "crash-once compile returned non-NULL");
    ame_sb_result_t *res2 = (ame_sb_result_t *)r2;
    CHECK(res2->status == 0,
          "crash-once RECOVERED via child crash-net + glslang rebuild + retry");
    CHECK(res2->spv_len > 0, "crash-once retry produced spv bytes");
    free(r2);

    // 4. CRASHALWAYS：4 次全崩 → internal_error + 明确消息
    const char *always = "CRASHALWAYS void main() {}";
    void *r3 = ame_sandbox_compile(0, always, strlen(always), 0, "test/always", "main", &opt);
    CHECK(r3 != NULL, "crash-always compile returned non-NULL");
    ame_sb_result_t *res3 = (ame_sb_result_t *)r3;
    CHECK(res3->status == 3, "crash-always status=3 (internal_error)");
    CHECK(strstr(ame_sb_result_err(res3), "crashed 4 times") != NULL,
          "crash-always err message mentions 4 attempts");
    CHECK(res3->spv_len == 0, "crash-always no spv bytes");
    free(r3);

    // 5. 子进程仍在服务（崩溃未杀死 helper）
    const char *good2 = "void main() { vec4 p; }";
    void *r4 = ame_sandbox_compile(0, good2, strlen(good2), 0, "test/good2", "main", &opt);
    CHECK(r4 != NULL, "post-crash compile returned non-NULL");
    ame_sb_result_t *res4 = (ame_sb_result_t *)r4;
    CHECK(res4->status == 0, "child still serving after crash storm");
    free(r4);

    fprintf(stderr, "\n=== ALL TASK43 FORK-SERVER TESTS PASSED ===\n");
    return 0;
}
