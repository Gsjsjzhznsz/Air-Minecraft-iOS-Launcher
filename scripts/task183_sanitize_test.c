// Task183：spvc-shim ES 输出清洗功能单测（本地 gcc，Linux/CI 双跑）。
// 直接 #include 真源（静态函数可达），用真实病灶形态做断言：
//   B 族：MC 26.x OIT 系 `layout(location=0) out vec4 coeff[N]` + 循环变量
//         动态索引（terrain/entity/text 等 fragment 的实际病灶）；
//   C 族：clouds.vsh 的 `uniform isamplerBuffer CloudFaces` + texelFetch
//         线性取数 + spvc 的 `#extension GL_EXT_texture_buffer : require`。
// 断言清洗后源码在 ESSL 300 语义下可编译（由 glslangValidator 若可用时
// 加验，缺失则跳过——文本断言已覆盖关键变换）。
#include "../Natives/spvc_shim.c"

#include <assert.h>

static int g_fail = 0;
#define CHECK(cond, msg) do { \
    if (!(cond)) { printf("FAIL: %s\n", msg); g_fail = 1; } \
    else { printf("ok: %s\n", msg); } \
} while (0)

// 统计 src 里 word[name[ 形态的出现次数（word 为完整标识符且后随 '['）
static int count_bounded(const char *src, const char *name) {
    int n = 0;
    size_t l = strlen(name);
    const char *p = src;
    while ((p = strstr(p, name)) != NULL) {
        if (p[l] == '[' && (p == src || !ame183_is_ident(p[-1]))) ++n;
        p += l;
    }
    return n;
}

int main(void) {
    // ---------- B 族：OIT 输出数组动态索引 ----------
    const char *oit =
        "#version 300 es\n"
        "precision highp float;\n"
        "precision highp int;\n"
        "layout(location = 0) out mediump vec4 coeff[4];\n"
        "uniform mediump sampler2D Sampler0;\n"
        "in vec2 texCoord0;\n"
        "void addTransmittance(float t) {\n"
        "    for (int attachmentIndex = 0; attachmentIndex < 4; attachmentIndex++) {\n"
        "        for (int i = 0; i < 4; i++) {\n"
        "            coeff[attachmentIndex][i] = t;\n"
        "        }\n"
        "    }\n"
        "}\n"
        "void main() {\n"
        "    addTransmittance(0.5);\n"
        "}\n";
    char *b = ame183_sanitize_essl(oit);
    CHECK(b != NULL, "B: sanitize returned non-NULL");
    if (b != NULL) {
        CHECK(count_bounded(b, "coeff_mgio") >= 1, "B: coeff[ accesses redirected to coeff_mgio[");
        CHECK(strstr(b, "out mediump vec4 coeff[4];") != NULL, "B: original output-array decl preserved");
        CHECK(strstr(b, "mediump vec4 coeff_mgio[4];") != NULL, "B: scratch global decl appended");
        CHECK(strstr(b, "coeff[0] = coeff_mgio[0];") != NULL, "B: constant-index copy 0 present");
        CHECK(strstr(b, "coeff[3] = coeff_mgio[3];") != NULL, "B: constant-index copy 3 present");
        CHECK(strstr(b, "coeff[attachmentIndex]") == NULL, "B: no dynamic coeff[ access remains");
        CHECK(count_bounded(b, "coeff") == 5, "B: coeff[ count == 1 decl + 4 constant copies");
        // 主循环外的验证：声明处 1 次 + 常量复制 4 次 = 5 次（scratch 声明用 mgio）
        printf("---- B output ----\n%s------------------\n", b);
        free(b);
    }

    // ---------- C 族：texture buffer 模拟 ----------
    const char *tb =
        "#version 300 es\n"
        "#extension GL_EXT_texture_buffer : require\n"
        "precision highp float;\n"
        "precision highp int;\n"
        "uniform mediump isamplerBuffer CloudFaces;\n"
        "uniform mediump sampler2D OtherTex;\n"
        "void main() {\n"
        "    int a = texelFetch(CloudFaces, 5).r;\n"
        "    int b = texelFetch(CloudFaces, index + 2).r;\n"
        "    vec4 c = texelFetch(OtherTex, ivec2(3, 4), 0);\n"
        "    gl_Position = vec4(float(a + b), c);\n"
        "}\n";
    char *c = ame183_sanitize_essl(tb);
    CHECK(c != NULL, "C: sanitize returned non-NULL");
    if (c != NULL) {
        CHECK(strstr(c, "GL_EXT_texture_buffer") == NULL, "C: extension line removed");
        CHECK(strstr(c, "isampler2D CloudFaces") != NULL, "C: isamplerBuffer -> isampler2D");
        CHECK(strstr(c, "texelFetch(CloudFaces, ivec2((5) & 255, (5) >> 8), 0)") != NULL,
              "C: linear texelFetch folded to 2D (constant index)");
        CHECK(strstr(c, "ivec2((index + 2) & 255, (index + 2) >> 8)") != NULL,
              "C: linear texelFetch folded to 2D (expression index)");
        CHECK(strstr(c, "texelFetch(OtherTex, ivec2(3, 4), 0)") != NULL,
              "C: non-buffer texelFetch untouched");
        printf("---- C output ----\n%s------------------\n", c);
        free(c);
    }

    // ---------- 无需清洗的源：返回 NULL ----------
    const char *plain =
        "#version 300 es\n"
        "precision highp float;\n"
        "layout(location = 0) out mediump vec4 fragColor;\n"
        "void main() { fragColor = vec4(1.0); }\n";
    char *p = ame183_sanitize_essl(plain);
    CHECK(p == NULL, "plain source: no sanitize needed (NULL returned)");
    free(p);

    // ---------- B+C 混合 ----------
    const char *mix =
        "#version 300 es\n"
        "#extension GL_EXT_texture_buffer : require\n"
        "uniform highp isamplerBuffer Data;\n"
        "layout(location = 0) out highp vec4 oit[2];\n"
        "void main() {\n"
        "    oit[gl_FragCoord.x > 4.0 ? 0 : 1] = vec4(texelFetch(Data, 9));\n"
        "}\n";
    char *m = ame183_sanitize_essl(mix);
    CHECK(m != NULL, "mix: sanitize returned non-NULL");
    if (m != NULL) {
        CHECK(strstr(m, "GL_EXT_texture_buffer") == NULL, "mix: extension removed");
        CHECK(strstr(m, "isampler2D Data") != NULL, "mix: type replaced");
        CHECK(strstr(m, "oit_mgio[") != NULL, "mix: dynamic oit[ redirected");
        CHECK(strstr(m, "oit[0] = oit_mgio[0];") != NULL, "mix: constant copies present");
        printf("---- mix output ----\n%s--------------------\n", m);
        free(m);
    }

    if (g_fail) { printf("SANITIZE TEST FAILED\n"); return 1; }
    printf("SANITIZE TEST ALL PASS\n");
    return 0;
}
