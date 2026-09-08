// shaderc_include.c — Task 47：RenderPearl 26.3 `#include <minecraft:...>` 展开器
// 语义、ABI 与防御设计见 shaderc_include.h 头注释。
//
// 实现要点：
//   - 输出 buffer 用几何增长拼接（sprintf 风格的追加），初始 4x 源长
//   - 行迭代器 + 跨行块注释状态机（真 shader 无此形态，防御性处理）
//   - resolver 调用结果按 LWJGL 偏移读取 content/content_length，递归展开
//     后原位替换该行，并追加 `#line <外层下一行号>` 恢复行号
//   - 任何失败（深度/大小/空 result）都保留原始 #include 行——下游
//     glslang 会给出 "required extension not requested"（与今日一致的
//     可见诊断），绝不静默吞错
#include "shaderc_include.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// ---- 输出缓冲 ----
typedef struct {
    char *buf;
    size_t len;
    size_t cap;
    size_t limit;
    int overflow;
} ame_out_t;

static int ame_out_reserve(ame_out_t *o, size_t extra) {
    if (o->overflow) return 0;
    if (o->len + extra + 1 > o->cap) {
        size_t ncap = o->cap ? o->cap : 4096;
        while (ncap < o->len + extra + 1) {
            if (ncap > (size_t)1 << 40) { // 几何增长保护
                o->overflow = 1;
                return 0;
            }
            ncap *= 2;
        }
        char *nbuf = (char *)realloc(o->buf, ncap);
        if (nbuf == NULL) {
            o->overflow = 1;
            return 0;
        }
        o->buf = nbuf;
        o->cap = ncap;
    }
    if (o->len + extra > o->limit) {
        o->overflow = 1;
        return 0;
    }
    return 1;
}

static void ame_out_append(ame_out_t *o, const char *data, size_t n) {
    if (n == 0) return;
    if (!ame_out_reserve(o, n)) return;
    memcpy(o->buf + o->len, data, n);
    o->len += n;
    o->buf[o->len] = '\0';
}

static void ame_out_append_str(ame_out_t *o, const char *s) {
    ame_out_append(o, s, strlen(s));
}

// ---- include 指令解析（单行）----
typedef struct {
    int found;         // 本行是否为有效 include 指令
    int type;          // AME_INCLUDE_TYPE_*
    char name[256];    // 请求名（去掉括号）
    size_t name_len;
    size_t line_len;   // 该行全长（含换行符，若存在）
} ame_include_line_t;

// line 指向行首，avail 为该行到缓冲末尾的字节数（含换行符）。
// 解析规则：允许 [ \t]* # [ \t]* include [ \t]* (<...> | "...")，
// 之后到行尾仅允许空白与 //注释（宽松：RenderPearl 真实形态）。
static void ame_parse_include_line(const char *line, size_t avail, ame_include_line_t *out) {
    memset(out, 0, sizeof *out);
    const char *p = line;
    const char *end = line + avail;
    // 行边界
    const char *nl = (const char *)memchr(line, '\n', avail);
    const char *line_end = (nl != NULL) ? nl : end;
    out->line_len = (size_t)(line_end - line) + (nl != NULL ? 1 : 0);
    const char *scan_end = line_end;

    while (p < scan_end && (*p == ' ' || *p == '\t')) p++;
    if (p >= scan_end || *p != '#') return;
    p++;
    while (p < scan_end && (*p == ' ' || *p == '\t')) p++;
    size_t kw = 7; // "include"
    if ((size_t)(scan_end - p) < kw) return;
    if (memcmp(p, "include", kw) != 0) return;
    p += kw;
    while (p < scan_end && (*p == ' ' || *p == '\t')) p++;
    if (p >= scan_end) return;

    char open = *p, close = '\0';
    int type = -1;
    if (open == '<') {
        close = '>';
        type = AME_INCLUDE_TYPE_STANDARD;
    } else if (open == '"') {
        close = '"';
        type = AME_INCLUDE_TYPE_RELATIVE;
    } else {
        return;
    }
    p++;
    const char *name_start = p;
    while (p < scan_end && *p != close) {
        // 名字里不允许换行/引号/尖括号（防御）
        if (*p == '"' || *p == '<' || *p == '>' || *p == '\r') return;
        p++;
    }
    if (p >= scan_end) return; // 无闭合括号
    size_t name_len = (size_t)(p - name_start);
    if (name_len == 0 || name_len >= sizeof out->name) return;
    p++; // 跳过闭合括号

    // 尾部：仅允许空白 / '\r' / 行注释
    while (p < scan_end) {
        if (*p == ' ' || *p == '\t' || *p == '\r') {
            p++;
        } else if (*p == '/' && p + 1 < scan_end && p[1] == '/') {
            break;
        } else {
            return; // 括号后还有内容 —— 不是纯 include 行，保守拒绝
        }
    }

    memcpy(out->name, name_start, name_len);
    out->name[name_len] = '\0';
    out->name_len = name_len;
    out->found = 1;
    out->type = type;
}

// ---- 快速探测 ----
int ame_source_has_include(const char *src, size_t len) {
    if (src == NULL || len < 9) return 0; // "#include"=8 + 至少1字符
    // 子串级快查（注释误报无代价——只触发一次逐行精扫）
    const char *p = src, *end = src + len;
    while (p < end) {
        const char *hit = (const char *)memchr(p, '#', (size_t)(end - p));
        if (hit == NULL) return 0;
        if ((size_t)(end - hit) >= 8 && memcmp(hit, "#include", 8) == 0) return 1;
        p = hit + 1;
    }
    return 0;
}

// ---- 递归展开 ----
// 返回 0 = 成功（o 内已拼接）；非 0 = 失败（调用方保留原始行）。
// stats 仅供诊断日志。
static int ame_expand_text(ame_out_t *o, const char *src, size_t len,
                           const char *requesting_file, size_t depth,
                           ame_include_resolver_fn resolver, void *resolver_ud,
                           ame_include_releaser_fn releaser, void *releaser_ud,
                           int *out_expanded_count, int *out_skipped_count) {
    size_t pos = 0;
    int in_block_comment = 0;
    int line_no = 1;
    while (pos < len) {
        // 找行边界
        const char *line = src + pos;
        size_t avail = len - pos;
        const char *nl = (const char *)memchr(line, '\n', avail);
        size_t line_len = (nl != NULL) ? (size_t)(nl - line) + 1 : avail;

        // 块注释状态机（跨行）
        if (in_block_comment) {
            const char *close = NULL;
            for (const char *q = line; q < line + line_len; ++q) {
                if (q + 1 < line + line_len && *q == '*' && q[1] == '/') {
                    close = q + 2;
                    break;
                }
            }
            if (close == NULL) {
                ame_out_append(o, line, line_len);
                pos += line_len;
                line_no++;
                continue; // 整行仍在注释里
            }
            // 注释在本行闭合：输出到闭合点，从其后继续解析本行
            ame_out_append(o, line, (size_t)(close - line));
            pos += (size_t)(close - line);
            in_block_comment = 0;
            // 重新从当前 pos 解析剩余行（无换行重扫，行号未变）
            avail = len - pos;
            nl = (const char *)memchr(src + pos, '\n', avail);
            line = src + pos;
            line_len = (nl != NULL) ? (size_t)(nl - line) + 1 : avail;
        }

        // 检测行内新开的块注释（在 #include 判定之前 —— 注释优先）
        // 仅当行首指令命中 #include 后才做完整解析，否则整行输出。
        ame_include_line_t inc;
        ame_parse_include_line(line, line_len, &inc);
        if (!inc.found) {
            ame_out_append(o, line, line_len);
            pos += line_len;
            line_no++;
            // 行内是否有未闭合的 /* 开头（下一行进入注释态）
            // 简化：扫描本行（不含已输出部分）的 /* 与 */ 配对
            {
                int cmt = 0;
                for (const char *q = line; q < line + line_len; ++q) {
                    if (q[0] == '/' && q + 1 < line + line_len && q[1] == '*') {
                        cmt = 1;
                        q++;
                    } else if (q[0] == '*' && q + 1 < line + line_len && q[1] == '/') {
                        if (cmt) cmt = 0;
                        q++;
                    }
                }
                if (cmt) in_block_comment = 1;
            }
            continue;
        }

        // 命中 include 指令 —— 调 resolver
        if (depth >= AME_INCLUDE_MAX_DEPTH) {
            fprintf(stderr,
                    "[amethyst-include] depth limit (%d) hit at '%.64s' line %d "
                    "-- keeping directive verbatim\n",
                    AME_INCLUDE_MAX_DEPTH, inc.name, line_no);
            ame_out_append(o, line, line_len);
            pos += line_len;
            line_no++;
            if (out_skipped_count) (*out_skipped_count)++;
            continue;
        }

        void *result = resolver(resolver_ud, inc.name, inc.type, requesting_file, depth);
        if (result == NULL) {
            fprintf(stderr,
                    "[amethyst-include] resolver returned NULL for '%.64s' -- keeping "
                    "directive verbatim\n",
                    inc.name);
            ame_out_append(o, line, line_len);
            pos += line_len;
            line_no++;
            if (out_skipped_count) (*out_skipped_count)++;
            continue;
        }
        const char *content =
            *(const char **)((char *)result + AME_IR_CONTENT_OFF);
        size_t content_len = *(size_t *)((char *)result + AME_IR_CONTENT_LENGTH_OFF);
        if (content == NULL) content_len = 0;

        if (content_len > 0) {
            // 递归展开内层（requesting_file 换成 include 名，诊断用）
            char inner_requesting[300];
            snprintf(inner_requesting, sizeof inner_requesting, "%.256s", inc.name);
            int rc = ame_expand_text(o, content, content_len, inner_requesting,
                                     depth + 1, resolver, resolver_ud, releaser,
                                     releaser_ud, out_expanded_count,
                                     out_skipped_count);
            if (rc != 0) {
                if (releaser != NULL) releaser(releaser_ud, result);
                return rc; // 输出溢出等硬失败，整链放弃
            }
        }
        // 行号恢复：本 include 行消耗后，外层下一行 = line_no + 1
        {
            char linefix[48];
            snprintf(linefix, sizeof linefix, "#line %d\n", line_no + 1);
            ame_out_append_str(o, linefix);
        }
        if (releaser != NULL) releaser(releaser_ud, result);
        pos += line_len;
        line_no++;
        if (out_expanded_count) (*out_expanded_count)++;
    }
    return 0;
}

char *ame_include_expand(const char *src, size_t len, const char *requesting_file,
                         ame_include_resolver_fn resolver, void *resolver_user_data,
                         ame_include_releaser_fn releaser, void *releaser_user_data,
                         size_t *out_len) {
    if (out_len != NULL) *out_len = 0;
    if (src == NULL || len == 0 || resolver == NULL) return NULL;
    if (!ame_source_has_include(src, len)) return NULL; // 无指令，无需展开

    ame_out_t o;
    memset(&o, 0, sizeof o);
    o.limit = AME_INCLUDE_MAX_OUTPUT;
    o.cap = len * 4 + 4096;
    o.buf = (char *)malloc(o.cap);
    if (o.buf == NULL) return NULL;
    o.buf[0] = '\0';

    int expanded = 0, skipped = 0;
    int rc = ame_expand_text(&o, src, len, requesting_file, 0, resolver,
                             resolver_user_data, releaser, releaser_user_data,
                             &expanded, &skipped);
    if (rc != 0 || o.overflow || o.buf == NULL) {
        fprintf(stderr,
                "[amethyst-include] expand FAILED (rc=%d overflow=%d) -- caller "
                "falls back to raw source\n",
                rc, o.overflow);
        free(o.buf);
        return NULL;
    }
    fprintf(stderr,
            "[amethyst-include] expanded %d include(s), %d kept verbatim, "
            "%zu -> %zu bytes\n",
            expanded, skipped, len, o.len);
    if (out_len != NULL) *out_len = o.len;
    return o.buf; // 调用方 free
}
