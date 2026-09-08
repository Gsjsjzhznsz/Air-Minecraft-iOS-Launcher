// test_task47_e2e_driver.c — Task 47 端到端驱动：展开一个 vsh 并写盘
// 用法：driver <input.vsh> <output.expanded.vsh> <shader_name>
// 模拟 Mojang GlslCompiler + LWJGL 的 include 回调（minecraft:xxx →
// task47_fixtures/include/xxx），布局按 LWJGL 3.4.1 ShadercIncludeResult。
// ⚠ 重要：每次 resolver 调用独立 malloc（Mojang 的 CachedIncludeSource 每个条
// 目独立分配 native 内存，嵌套递归期间各层内容互不覆写——static 复用缓冲
// 会让内层读文件覆写外层正在迭代的内容，产生伪缺陷）。
#include "../Natives/shaderc_include.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct mock_node {
    void *payload; // malloc：内容 + result 结构（首尾拼接，一次分配）
    struct mock_node *next;
} mock_node_t;
static mock_node_t *g_allocs = NULL;

static void *mock_alloc_permanent(size_t total) {
    mock_node_t *n = (mock_node_t *)malloc(sizeof *n);
    n->payload = malloc(total);
    n->next = g_allocs;
    g_allocs = n;
    return n->payload;
}
static void *resolver(void *user_data, const char *requested, int type,
                      const char *requesting, size_t depth) {
    (void)user_data; (void)type; (void)requesting; (void)depth;
    if (strncmp(requested, "minecraft:", 10) != 0) return NULL;
    char path[512];
    snprintf(path, sizeof path, "task47_fixtures/include/%s", requested + 10);
    FILE *f = fopen(path, "rb");
    if (f == NULL) {
        fprintf(stderr, "[e2e-driver] missing include: %s\n", requested);
        return NULL;
    }
    fseek(f, 0, SEEK_END);
    long fsz = ftell(f);
    fseek(f, 0, SEEK_SET);
    // 一次分配：内容 (fsz+1) + result 结构 (40)，独立于其它调用
    size_t total = (size_t)fsz + 1 + 40;
    char *block = (char *)mock_alloc_permanent(total);
    if (block == NULL) { fclose(f); return NULL; }
    char *storage = block;
    char *result = block + fsz + 1;
    if (fread(storage, 1, (size_t)fsz, f) != (size_t)fsz) { fclose(f); return NULL; }
    fclose(f);
    storage[fsz] = '\0';
    memset(result, 0, 40);
    *(char **)(result + 0) = storage; // source_name（简化）
    *(size_t *)(result + 8) = strlen(requested);
    *(char **)(result + 16) = storage; // content
    *(size_t *)(result + 24) = (size_t)fsz; // content_length
    return result;
}

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: %s <in.vsh> <out.expanded.vsh> <name>\n", argv[0]);
        return 2;
    }
    FILE *f = fopen(argv[1], "rb");
    if (f == NULL) { perror(argv[1]); return 2; }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *src = malloc((size_t)n + 1);
    if (fread(src, 1, (size_t)n, f) != (size_t)n) { fclose(f); return 2; }
    fclose(f);
    src[n] = '\0';

    size_t out_len = 0;
    char *out = ame_include_expand(src, (size_t)n, argv[3], resolver, NULL,
                                   NULL, NULL, &out_len);
    if (out == NULL) {
        fprintf(stderr, "[e2e-driver] expand returned NULL for %s\n", argv[1]);
        return 1;
    }
    FILE *o = fopen(argv[2], "wb");
    if (o == NULL) { perror(argv[2]); free(out); return 2; }
    fwrite(out, 1, out_len, o);
    fclose(o);
    free(out);
    while (g_allocs != NULL) {
        mock_node_t *nx = g_allocs->next;
        free(g_allocs->payload);
        free(g_allocs);
        g_allocs = nx;
    }
    return 0;
}
