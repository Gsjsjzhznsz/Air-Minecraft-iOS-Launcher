// task107_harness.c —— 本地验证产线 ad-hoc 重签名器（Natives/ame107_codesign.h）
//
// 在 Linux 上用 OpenSSL SHA-256 后端编译同一份产线头文件，对真实
// jna-5.13.0 darwin-aarch64/libjnidispatch.jnilib 执行与
// dyld_patch_platform.m 等价的操作序列：
//   1) LC_BUILD_VERSION platform: MACOS(1) -> IOS(2)（手工重标签）
//   2) LC_CODE_SIGNATURE.datasize 收紧为 ame107_adhoc_blob_size 终值
//   3) ame107_build_adhoc_superblob 构建 blob 并原位写入
// 产出 <out>，由 verify_task107.py 用独立 Python 实现复验布局与哈希。
//
// 用例：
//   argv[1] = 输入 Mach-O（arm64 thin）
//   argv[2] = 输出文件
//   argv[3] = 模式：inplace（默认，JNA 实测形态）
//             grow（把 datasize 砍小 32 字节强制走增长路径语义）
//             nosign（无 LC_CODE_SIGNATURE 输入，应原样输出且 blob 长度为 0 判定）
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <openssl/sha.h>

#include "ame107_codesign.h"

static void harness_sha256(const uint8_t *data, size_t len, uint8_t out[32]) {
    SHA256(data, len, out);
}

// 最小 Mach-O 解析（与产线 .m 相同的遍历逻辑，无 Apple 头依赖）
struct lc_cursor { uint32_t cmd, cmdsize; };

int main(int argc, char **argv) {
    if (argc < 3) { fprintf(stderr, "usage: %s <in> <out> [inplace|grow|nosign]\n", argv[0]); return 2; }
    const char *mode = (argc >= 4) ? argv[3] : "inplace";

    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror("open in"); return 2; }
    fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
    uint8_t *buf = malloc(sz);
    if (fread(buf, 1, sz, f) != (size_t)sz) { perror("read"); return 2; }
    fclose(f);

    uint32_t magic; memcpy(&magic, buf, 4);
    if (magic != 0xfeedfacf) { fprintf(stderr, "not MH_MAGIC_64: 0x%x\n", magic); return 2; }

    uint32_t ncmds; memcpy(&ncmds, buf + 16, 4);
    uint8_t *off = buf + 32;
    struct linkedit_data_command_sig { uint32_t cmd, cmdsize, dataoff, datasize; } *sig = NULL;
    uint8_t *buildver = NULL;
    for (uint32_t i = 0; i < ncmds; i++) {
        uint32_t cmd, cmdsize; memcpy(&cmd, off, 4); memcpy(&cmdsize, off + 4, 4);
        if (cmdsize == 0) break;
        if (cmd == 0x32) buildver = off;             // LC_BUILD_VERSION
        if (cmd == 0x1d) sig = (void *)off;          // LC_CODE_SIGNATURE
        off += cmdsize;
    }

    // 1) 重标签 MACOS -> IOS
    if (buildver) {
        uint32_t plat; memcpy(&plat, buildver + 8, 4);
        fprintf(stderr, "[harness] LC_BUILD_VERSION platform %u -> 2 (IOS)\n", plat);
        uint32_t ios = 2; memcpy(buildver + 8, &ios, 4);
    } else {
        fprintf(stderr, "[harness] no LC_BUILD_VERSION (旧 VERSION_MIN 形态，产线走 retagged=NO)\n");
    }

    if (!sig) {
        // nosign 用例：产线行为 = 仅重标签 + 取证日志，原样落盘
        fprintf(stderr, "[harness] no LC_CODE_SIGNATURE -> retag only, output unchanged besides platform\n");
        FILE *o = fopen(argv[2], "wb"); fwrite(buf, 1, sz, o); fclose(o);
        printf("NOSIGN %ld\n", sz);
        return 0;
    }

    uint32_t dataoff = sig->dataoff, oldSize = sig->datasize;
    if (strcmp(mode, "grow") == 0) {
        oldSize -= 32; // 人为收窄，强制 blobLen > oldSize
        sig->datasize = oldSize;
        fprintf(stderr, "[harness] grow mode: datasize forced to %u\n", oldSize);
    }

    size_t blobLen = ame107_adhoc_blob_size(dataoff, strlen("amethyst-retag") + 1);
    fprintf(stderr, "[harness] dataoff=%u oldDatasize=%u blobLen=%zu\n", dataoff, oldSize, blobLen);

    size_t finalSize = sz;
    if (blobLen > oldSize) {
        // 增长路径（thin）：datasize 定稿 + 扩缓冲
        sig->datasize = (uint32_t)blobLen;
        finalSize = dataoff + blobLen;
        buf = realloc(buf, finalSize);
        memset(buf + sz, 0, finalSize - sz);
        fprintf(stderr, "[harness] grow: file %ld -> %zu\n", sz, finalSize);
    } else {
        // 原位路径：datasize 收紧（页 0 定稿）
        sig->datasize = (uint32_t)blobLen;
    }

    size_t builtLen = 0;
    uint8_t *blob = ame107_build_adhoc_superblob(buf, dataoff, "amethyst-retag", harness_sha256, &builtLen);
    if (!blob) { fprintf(stderr, "[harness] blob build FAILED\n"); return 1; }
    if (builtLen != blobLen) { fprintf(stderr, "[harness] size mismatch %zu != %zu\n", builtLen, blobLen); return 1; }

    memcpy(buf + dataoff, blob, builtLen);
    if (blobLen < oldSize) memset(buf + dataoff + builtLen, 0, oldSize - blobLen);
    free(blob);

    FILE *o = fopen(argv[2], "wb");
    fwrite(buf, 1, finalSize, o);
    fclose(o);
    printf("OK %zu dataoff=%u oldDatasize=%u blobLen=%zu\n", finalSize, dataoff, oldSize, blobLen);
    return 0;
}
