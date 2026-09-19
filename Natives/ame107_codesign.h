// ame107_codesign.h
// Task 107：平台重标签后的 ad-hoc 重签名（纯 C，无系统依赖）。
//
// 背景（Task106 回归根因）：本设备（iPadOS 27 / dyld4）对 dlopen 的镜像
// 要求“存在代码签名 blob”，但签名哈希校验宽松（调试态侧载进程）——
// “ad-hoc 签名 + 重标签（哈希失效）”历来可加载；而 Task106 的签名中和
// （改写 LC_CODE_SIGNATURE → LC_SOURCE_VERSION + blob 清零）把库变成
// “无签名”，dyld4 直接拒载（"missing code signature in <uuid>"），
// JNA libjnidispatch 首当其冲（UUID C34856C0-A4B7-32C6-9ACE-D2166123DD04
// 与设备日志报错逐字一致），26.3 会话 MacosUtil → ca.weblite.objc 链上
// 无降级路径直接 NoClassDefFoundError 崩溃。
//
// 正解：重标签后对 [0, dataoff) 重算 SHA-256 页哈希，构建全新 ad-hoc
// CodeDirectory SuperBlob 原位替换旧签名。产出二进制在任何接受 ad-hoc
// 签名的策略下均合法（比“失效哈希的旧 ad-hoc”严格更优）；team 签名库
// 经此处理退化为 ad-hoc（spark 类，另行拦截，不依赖本路径）。
//
// SHA-256 后端经函数指针注入：设备侧 CommonCrypto CC_SHA256，本地
// harness 用 OpenSSL——同一份产线代码两端可测。
//
// CodeDirectory v0x20400 布局（Security/CodeDirectory.h）：
//   magic(4) length(4) version(4) flags(4) hashOffset(4) identOffset(4)
//   nSpecialSlots(4) nCodeSlots(4) codeLimit(4) hashSize(1) hashType(1)
//   platform(1) pageSize(1) spare2(4) scatterOffset(4) teamOffset(4)
//   spare3(4) codeLimit64(8) execSegBase(8) execSegLimit(8) execSegFlags(8)
// 固定头 88 字节；identifier 紧随；页哈希槽自 hashOffset 起（相对
// CodeDirectory 起点）。SuperBlob/CodeDirectory 多字节字段一律大端。

#ifndef AME107_CODESIGN_H
#define AME107_CODESIGN_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define AME107_CSMAGIC_CODEDIRECTORY 0xfade0c02u
#define AME107_CSMAGIC_SUPERBLOB     0xfade0cc0u
#define AME107_CS_ADHOC              0x00000002u
#define AME107_CSHASH_SHA256         2u
#define AME107_PAGE_SIZE_LOG2        12u  /* 4096 字节页 */
#define AME107_PAGE_SIZE             4096u
#define AME107_CD_FIXED              88u  /* v0x20400 固定头 */
#define AME107_SUPERBLOB_INDEX_OFF   20u  /* header 12 + 单条 index 8 */

typedef void (*ame107_sha256_fn)(const uint8_t *data, size_t len, uint8_t out[32]);

static void ame107_store_be32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v >> 24); p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >> 8);  p[3] = (uint8_t)v;
}

static void ame107_store_be64(uint8_t *p, uint64_t v) {
    for (int i = 0; i < 8; i++) p[i] = (uint8_t)(v >> (56 - 8 * i));
}

/* 精确计算 SuperBlob 总长（与 ame107_build_adhoc_superblob 同一算式，
 * 供调用方在构建前确定 LC_CODE_SIGNATURE.datasize 终值——datasize
 * 位于页 0，必须先定稿再算哈希）。 */
static size_t ame107_adhoc_blob_size(uint32_t codeLimit, size_t identLen) {
    size_t hashOffset = AME107_CD_FIXED + ((identLen + 3) & ~(size_t)3);
    size_t nCodeSlots = ((size_t)codeLimit + AME107_PAGE_SIZE - 1) / AME107_PAGE_SIZE;
    return AME107_SUPERBLOB_INDEX_OFF + hashOffset + 32 * nCodeSlots;
}

/* 对 [sliceBase, sliceBase+codeLimit) 构建 ad-hoc SuperBlob。
 * 返回 malloc 缓冲（调用方 free），*outSize 为总长；失败返回 NULL。
 * 页 0（含调用方已定稿的载入命令）参与哈希；[dataoff, ...) 的 blob
 * 本身天然排除在哈希外（codeLimit == dataoff 是调用方约定）。 */
static uint8_t *ame107_build_adhoc_superblob(const uint8_t *sliceBase, uint32_t codeLimit,
                                             const char *identifier, ame107_sha256_fn sha256,
                                             size_t *outSize) {
    if (sliceBase == NULL || identifier == NULL || sha256 == NULL || outSize == NULL) return NULL;
    size_t identLen = strlen(identifier) + 1;
    size_t hashOffset = AME107_CD_FIXED + ((identLen + 3) & ~(size_t)3);
    size_t nCodeSlots = ((size_t)codeLimit + AME107_PAGE_SIZE - 1) / AME107_PAGE_SIZE;
    size_t cdSize = hashOffset + 32 * nCodeSlots;
    size_t superLen = AME107_SUPERBLOB_INDEX_OFF + cdSize;

    uint8_t *buf = (uint8_t *)calloc(1, superLen);
    if (buf == NULL) return NULL;

    /* SuperBlob：magic/length/count + 单条 index（tag=0 CSSLOT_CODEDIRECTORY） */
    ame107_store_be32(buf + 0, AME107_CSMAGIC_SUPERBLOB);
    ame107_store_be32(buf + 4, (uint32_t)superLen);
    ame107_store_be32(buf + 8, 1);
    ame107_store_be32(buf + 12, 0);
    ame107_store_be32(buf + 16, AME107_SUPERBLOB_INDEX_OFF);

    uint8_t *cd = buf + AME107_SUPERBLOB_INDEX_OFF;
    ame107_store_be32(cd + 0, AME107_CSMAGIC_CODEDIRECTORY);
    ame107_store_be32(cd + 4, (uint32_t)cdSize);
    ame107_store_be32(cd + 8, 0x20400);                 /* version */
    ame107_store_be32(cd + 12, AME107_CS_ADHOC);        /* flags */
    ame107_store_be32(cd + 16, (uint32_t)hashOffset);
    ame107_store_be32(cd + 20, AME107_CD_FIXED);        /* identOffset */
    ame107_store_be32(cd + 24, 0);                      /* nSpecialSlots = 0 */
    ame107_store_be32(cd + 28, (uint32_t)nCodeSlots);
    ame107_store_be32(cd + 32, codeLimit);
    cd[36] = 32;                                        /* hashSize */
    cd[37] = AME107_CSHASH_SHA256;                      /* hashType */
    cd[38] = 0;                                         /* platform */
    cd[39] = AME107_PAGE_SIZE_LOG2;                     /* pageSize */
    ame107_store_be32(cd + 40, 0);                      /* spare2 */
    ame107_store_be32(cd + 44, 0);                      /* scatterOffset */
    ame107_store_be32(cd + 48, 0);                      /* teamOffset */
    ame107_store_be32(cd + 52, 0);                      /* spare3 */
    ame107_store_be64(cd + 56, (uint64_t)codeLimit);    /* codeLimit64 */
    ame107_store_be64(cd + 64, 0);                      /* execSegBase（dylib 无 execSeg 语义） */
    ame107_store_be64(cd + 72, 0);                      /* execSegLimit */
    ame107_store_be64(cd + 80, 0);                      /* execSegFlags */
    memcpy(cd + AME107_CD_FIXED, identifier, identLen);

    /* 逐页哈希；末页按剩余字节数（部分页不补零，与 codesign 语义一致） */
    for (size_t i = 0; i < nCodeSlots; i++) {
        size_t pageOff = i * AME107_PAGE_SIZE;
        size_t n = (size_t)codeLimit - pageOff;
        if (n > AME107_PAGE_SIZE) n = AME107_PAGE_SIZE;
        sha256(sliceBase + pageOff, n, cd + hashOffset + 32 * i);
    }

    *outSize = superLen;
    return buf;
}

#endif /* AME107_CODESIGN_H */
