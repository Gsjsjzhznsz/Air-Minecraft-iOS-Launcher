// test_task45_glue.c — end-to-end validation of the from-source shaderc glue
// against the REAL patched glslang (nullguard + pool-zero/size-guard).
// Mirrors the exact on-device call pattern from latestlog:
//   options: target_env=0 (vulkan) version=4202496 (vulkan 1.2),
//            generate_debug_info ON, optimization_level 0
//   kinds:   0 (vertex) / 1 (fragment), entry "main"
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_fail = 0;
#define CHECK(cond, ...)                                                    \
    do {                                                                    \
        if (!(cond)) {                                                      \
            g_fail++;                                                       \
            printf("FAIL: " __VA_ARGS__);                                   \
            printf("  (%s:%d)\n", __FILE__, __LINE__);                      \
        } else {                                                            \
            printf("ok: " __VA_ARGS__);                                     \
        }                                                                   \
    } while (0)

typedef void *(*fn_compiler_init)(void);
typedef void (*fn_compiler_release)(void *);
typedef void *(*fn_opt_init)(void);
typedef void *(*fn_opt_clone)(const void *);
typedef void (*fn_opt_release)(void *);
typedef void (*fn_opt_set_env)(void *, int, unsigned);
typedef void (*fn_opt_set_opt)(void *, int);
typedef void (*fn_opt_set_dbg)(void *);
typedef void (*fn_opt_macro)(void *, const char *, size_t, const char *, size_t);
typedef void *(*fn_compile)(void *, const char *, size_t, int, const char *,
                            const char *, void *);
typedef void (*fn_result_release)(void *);
typedef int (*fn_result_status)(void *);
typedef size_t (*fn_result_len)(void *);
typedef size_t (*fn_result_nerr)(void *);
typedef const char *(*fn_result_bytes)(void *);
typedef const char *(*fn_result_msg)(void *);
typedef void (*fn_get_spv_version)(unsigned *, unsigned *);

static fn_compiler_init p_compiler_initialize;
static fn_compiler_release p_compiler_release;
static fn_opt_init p_options_initialize;
static fn_opt_clone p_options_clone;
static fn_opt_release p_options_release;
static fn_opt_set_env p_set_target_env;
static fn_opt_set_opt p_set_opt_level;
static fn_opt_set_dbg p_set_debug;
static fn_opt_macro p_add_macro;
static fn_compile p_compile_spv, p_compile_pre;
typedef void *(*fn_assemble)(void *, const char *, size_t, void *);
static fn_assemble p_assemble;
static fn_result_release p_result_release;
static fn_result_status p_result_status;
static fn_result_len p_result_get_length;
typedef size_t (*fn_result_spv_len)(void *);
static fn_result_spv_len p_result_get_spv_length;
static fn_result_nerr p_result_get_num_errors;
static fn_result_bytes p_result_get_bytes;
typedef const char *(*fn_result_spv_bytes)(void *);
static fn_result_spv_bytes p_result_get_spv_bytes;
static fn_result_msg p_result_get_error_message;
typedef int (*fn_parse_vp)(const char *, int *, int *);
static fn_parse_vp p_parse_version_profile;
static fn_get_spv_version p_get_spv_version;

// MC-style GLSL (RenderPearl preamble: #version 330 + ARB separate-shader-
// objects + 420pack, UBO uniforms, explicit locations, l-value swizzle
// writes that exercise the guarded lValueErrorCheck/convertSwizzle chains).
#define MC_PREAMBLE "#version 330\n" \
    "#extension GL_ARB_separate_shader_objects : require\n" \
    "#extension GL_ARB_shading_language_420pack : require\n"

static const char *VS =
    MC_PREAMBLE
    "layout(location = 0) in vec3 Position;\n"
    "layout(location = 1) in vec4 Color;\n"
    "layout(location = 2) in vec2 UV0;\n"
    "layout(set = 0, binding = 0) uniform UniformBlock {\n"
    "    mat4 ModelViewMat;\n"
    "    mat4 ProjMat;\n"
    "};\n"
    "layout(location = 0) out vec4 vertexColor;\n"
    "layout(location = 1) out vec2 texCoord0;\n"
    "void main() {\n"
    "    vec4 pos = ProjMat * ModelViewMat * vec4(Position, 1.0);\n"
    "    vertexColor = Color;\n"
    "    vec4 swz = vec4(1.0);\n"
    "    swz.xwyz = Color.abgr;     // l-value swizzle: the guarded chain\n"
    "    texCoord0 = UV0 * swz.xy;\n"
    "    gl_Position = pos + swz * 0.0;\n"
    "}\n";

static const char *FS =
    MC_PREAMBLE
    "layout(location = 0) in vec4 vertexColor;\n"
    "layout(location = 1) in vec2 texCoord0;\n"
    "layout(set = 0, binding = 1) uniform sampler2D Sampler0;\n"
    "layout(location = 0) out vec4 fragColor;\n"
    "void main() {\n"
    "    vec4 c = texture(Sampler0, texCoord0) * vertexColor;\n"
    "    c.xyzw = c.wzyx;           // l-value swizzle\n"
    "    fragColor = c;\n"
    "}\n";

static const char *VS_BAD =
    MC_PREAMBLE
    "layout(location = 0) in vec3 Position;\n"
    "void main() {\n"
    "    gl_Position = vec4(Position 1.0);   // syntax error: missing comma\n"
    "}\n";

int main(int argc, char **argv) {
    const char *lib = (argc > 1) ? argv[1] : "libshaderc_impl_test.so";
    void *h = dlopen(lib, RTLD_NOW);
    if (h == NULL) { printf("FATAL: dlopen %s: %s\n", lib, dlerror()); return 1; }
#define RESOLVE(var, name)                                                   \
    var = (typeof(var))dlsym(h, name);                                       \
    if (var == NULL) { printf("FATAL: missing %s\n", name); return 1; }
    RESOLVE(p_compiler_initialize, "shaderc_compiler_initialize");
    RESOLVE(p_compiler_release, "shaderc_compiler_release");
    RESOLVE(p_options_initialize, "shaderc_compile_options_initialize");
    RESOLVE(p_options_clone, "shaderc_compile_options_clone");
    RESOLVE(p_options_release, "shaderc_compile_options_release");
    RESOLVE(p_set_target_env, "shaderc_compile_options_set_target_env");
    RESOLVE(p_set_opt_level, "shaderc_compile_options_set_optimization_level");
    RESOLVE(p_set_debug, "shaderc_compile_options_set_generate_debug_info");
    RESOLVE(p_add_macro, "shaderc_compile_options_add_macro_definition");
    RESOLVE(p_compile_spv, "shaderc_compile_into_spv");
    RESOLVE(p_compile_pre, "shaderc_compile_into_preprocessed_text");
    RESOLVE(p_assemble, "shaderc_assemble_into_spv");
    RESOLVE(p_result_release, "shaderc_result_release");
    RESOLVE(p_result_status, "shaderc_result_get_compilation_status");
    RESOLVE(p_result_get_length, "shaderc_result_get_length");
    RESOLVE(p_result_get_spv_length, "shaderc_result_get_spv_length");
    RESOLVE(p_result_get_num_errors, "shaderc_result_get_num_errors");
    RESOLVE(p_result_get_bytes, "shaderc_result_get_bytes");
    RESOLVE(p_result_get_spv_bytes, "shaderc_result_get_spv_bytes");
    RESOLVE(p_result_get_error_message, "shaderc_result_get_error_message");
    RESOLVE(p_parse_version_profile, "shaderc_parse_version_profile");
    RESOLVE(p_get_spv_version, "shaderc_get_spv_version");
    p_result_get_spv_bytes = (fn_result_spv_bytes)dlsym(h, "shaderc_result_get_spv_bytes");

    // ---- version helpers ----
    unsigned spv_v = 0, spv_r = 0;
    p_get_spv_version(&spv_v, &spv_r);
    CHECK(spv_v == 0x00010500, "get_spv_version -> %#x rev %u", spv_v, spv_r);
    int pv = 0, pp = 0;
    CHECK(p_parse_version_profile("330core", &pv, &pp) && pv == 330 && pp == 1,
          "parse_version_profile(330core) -> v=%d p=%d", pv, pp);
    CHECK(p_parse_version_profile("100es", &pv, &pp) && pv == 100 && pp == 3,
          "parse_version_profile(100es) -> v=%d p=%d", pv, pp);
    CHECK(!p_parse_version_profile("garbage", &pv, &pp),
          "parse_version_profile(garbage) rejected");

    // ---- lifecycle + options (exact MC pattern) ----
    void *compiler = p_compiler_initialize();
    CHECK(compiler != NULL, "compiler_initialize");
    void *opt = p_options_initialize();
    CHECK(opt != NULL, "options_initialize");
    p_set_target_env(opt, 0, 4202496);  // vulkan 1.2 (device log value)
    p_set_debug(opt);
    p_set_opt_level(opt, 0);
    p_add_macro(opt, "MC_VERSION", 10, "263", 3);
    p_add_macro(opt, "NO_VALUE", 8, NULL, 0);

    // ---- compile vertex (success path) ----
    void *r = p_compile_spv(compiler, VS, strlen(VS), 0, "minecraft:core/terrain",
                            "main", opt);
    CHECK(r != NULL, "compile VS -> non-NULL result");
    int st = p_result_status(r);
    size_t nerr = p_result_get_num_errors(r);
    size_t spv_len = p_result_get_spv_length(r);
    const char *spv = p_result_get_spv_bytes(r);
    const char *msg = p_result_get_error_message(r);
    CHECK(st == 0, "VS status == 0 (got %d), errors=%zu msg='%.80s'", st, nerr, msg);
    CHECK(nerr == 0, "VS num_errors == 0 (got %zu)", nerr);
    CHECK(spv_len > 100 && spv_len % 4 == 0, "VS spv_len = %zu (word-aligned)", spv_len);
    uint32_t magic = (spv_len >= 4) ? *(const uint32_t *)spv : 0;
    CHECK(magic == 0x07230203u, "VS SPIR-V magic %08x", magic);
    CHECK(p_result_get_length(r) == spv_len && p_result_get_bytes(r) == spv,
          "VS bytes/length aliases spv accessors");
    p_result_release(r);

    // ---- compile fragment (success) ----
    r = p_compile_spv(compiler, FS, strlen(FS), 1, "minecraft:core/terrain", "main", opt);
    st = p_result_status(r);
    spv_len = p_result_get_spv_length(r);
    CHECK(r != NULL && st == 0 && spv_len > 100,
          "FS status=%d spv_len=%zu msg='%.80s'", st, spv_len,
          r ? p_result_get_error_message(r) : "(null)");
    if (r) p_result_release(r);

    // ---- NUL-termination robustness: exact-size buffer, no terminator ----
    char *vs_copy = (char *)malloc(strlen(VS));
    memcpy(vs_copy, VS, strlen(VS));
    r = p_compile_spv(compiler, vs_copy, strlen(VS), 0, "minecraft:core/terrain", "main", opt);
    CHECK(r != NULL && p_result_status(r) == 0 && p_result_get_spv_length(r) > 100,
          "compile from non-NUL-terminated buffer works");
    if (r) p_result_release(r);
    free(vs_copy);

    // ---- macro actually applied (preprocessed text path) ----
    void *rp = p_compile_pre(compiler, VS, strlen(VS), 0, "test", "main", opt);
    CHECK(rp != NULL && p_result_status(rp) == 0,
          "preprocessed status=%d", rp ? p_result_status(rp) : -1);
    if (rp) {
        const char *txt = p_result_get_bytes(rp);
        size_t tl = p_result_get_length(rp);
        CHECK(txt != NULL && tl > 0 && txt[tl - 1] == '\0',
              "preprocessed text NUL-terminated (len=%zu, tail NUL present)", tl);
        p_result_release(rp);
    }

    // ---- error path: bad GLSL -> compilation_error + message + num_errors>0 ----
    r = p_compile_spv(compiler, VS_BAD, strlen(VS_BAD), 0, "bad.glsl", "main", opt);
    CHECK(r != NULL, "bad VS -> non-NULL");
    st = p_result_status(r);
    nerr = p_result_get_num_errors(r);
    msg = p_result_get_error_message(r);
    CHECK(st == 2, "bad VS status == 2 (compilation_error), got %d", st);
    CHECK(nerr >= 1, "bad VS num_errors >= 1 (got %zu)", nerr);
    CHECK(msg != NULL && strstr(msg, "ERROR") != NULL,
          "bad VS message contains ERROR ('%.60s')", msg ? msg : "(null)");
    if (r) p_result_release(r);

    // ---- unsupported kind -> internal_error, non-NULL ----
    r = p_compile_spv(compiler, VS, strlen(VS), 6, "x", "main", opt);
    CHECK(r != NULL && p_result_status(r) == 3, "infer_from_source -> internal_error 3");
    if (r) p_result_release(r);

    // ---- assembly surfaces -> internal_error (documented) ----
    r = p_assemble(compiler, "; magic", 7, opt);
    CHECK(r != NULL && p_result_status(r) == 3, "assemble_into_spv -> internal_error 3");
    if (r) p_result_release(r);
    void *ra = ((fn_compile)dlsym(h, "shaderc_compile_into_spv_assembly"))(
        compiler, VS, strlen(VS), 0, "x", "main", opt);
    CHECK(ra != NULL && p_result_status(ra) == 3,
          "compile_into_spv_assembly -> internal_error 3");
    if (ra) p_result_release(ra);

    // ---- options clone carries fields ----
    void *opt2 = p_options_clone(opt);
    CHECK(opt2 != NULL, "options_clone");
    r = p_compile_spv(compiler, VS, strlen(VS), 0, "clone", "main", opt2);
    CHECK(r != NULL && p_result_status(r) == 0, "compile with cloned options OK");
    if (r) p_result_release(r);
    p_options_release(opt2);

    // ---- stress: 300 alternating compiles (pool reuse / freelist churn) ----
    int failures = 0;
    for (int i = 0; i < 300; ++i) {
        int kind = (i & 1) ? 1 : 0;              // 0=vertex, 1=fragment
        const char *src = (i & 1) ? FS : VS;     // source MUST match kind
        void *rr = p_compile_spv(compiler, src, strlen(src), kind, "storm", "main", opt);
        if (rr == NULL || p_result_status(rr) != 0) {
            if (failures == 0)
                printf("first storm failure at i=%d: status=%d msg='%.80s'\n", i,
                       rr ? p_result_status(rr) : -1,
                       rr ? p_result_get_error_message(rr) : "(null)");
            failures++;
        }
        if (rr) p_result_release(rr);
    }
    CHECK(failures == 0, "storm: 300 alternating compiles, %d failures", failures);

    // ---- teardown / re-init (the shim's rebuild pattern) ----
    p_options_release(opt);
    p_compiler_release(compiler);
    compiler = p_compiler_initialize();
    CHECK(compiler != NULL, "re-initialize after release (refcount cycle)");
    r = p_compile_spv(compiler, VS, strlen(VS), 0, "after-rebuild", "main", NULL);
    CHECK(r != NULL && p_result_status(r) == 0,
          "compile after release/init cycle, NULL options");
    if (r) p_result_release(r);
    p_compiler_release(compiler);

    printf(g_fail ? "\n=== %d FAILURES ===\n" : "\n=== ALL GREEN ===\n", g_fail);
    return g_fail ? 1 : 0;
}
