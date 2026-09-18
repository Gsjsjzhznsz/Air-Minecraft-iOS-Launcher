#!/usr/bin/env python3
"""Task103 双修复校验器
A. 装机日志证据（git 钉 446b2a0 的 latestlog.txt / latestlog.old.txt）
B. shaderc_include.c 粘行修复（文本锚点 + 合成着色器行为测试：真编译真展开）
C. EASU 哨兵注入（字符串手术锚点 + MobileGlues 共享头零改动断言）
D. 哨兵票/翻转判决/取证（osm_bridge.mm 锚点）
E. 判决状态机行为矩阵（Python 镜像仿真）
F. FAQ 34 条目 + version.h 附录
G. 卫生（语法门 + 级联 + NSLog %@ 禁令）
"""
import os, re, subprocess, sys, tempfile

os.chdir(os.path.dirname(os.path.abspath(__file__)) + '/..')
PASS = FAIL = 0
def check(name, ok, detail=''):
    global PASS, FAIL
    if ok:
        PASS += 1
        print(f'  PASS  {name}')
    else:
        FAIL += 1
        print(f'  FAIL  {name}  {detail}')

def read(p):
    return open(p, encoding='utf-8', errors='replace').read()

print('===== A. 装机日志证据（git 446b2a0）=====')
log_old = subprocess.run(['git', 'show', '446b2a0:latestlog.old.txt'],
                         capture_output=True, text=True).stdout
check('A1 日志可读（26.3 会话，9735 行量级）', len(log_old) > 100000, f'{len(log_old)} bytes')
check('A2 崩溃签名：preprocessor directive cannot be preceded by another token',
      'preprocessor directive cannot be preceded by another token' in log_old)
check('A3 sodium 管线缺失：Failed to find or load pipeline sodium:pipeline/solid_terrain',
      'Failed to find or load pipeline sodium:pipeline/solid_terrain' in log_old)
check('A4 粘行发生点：compile#406 sodium:blocks/block_layer_opaque 展开 2394 -> 5741',
      'in=\'sodium:blocks/block_layer_opaque\'' in log_old and '2394 -> 5741' in log_old)
vanilla_ok = len(re.findall(r'expanded \d+ include\(s\), 0 kept verbatim', log_old))
check('A5 同会话原版 include 展开大量成功（尾换行规范 → 不触发粘行）',
      vanilla_ok > 30, f'{vanilla_ok} expansions')

log_new = subprocess.run(['git', 'show', '446b2a0:latestlog.txt'],
                         capture_output=True, text=True).stdout
check('A6 BMC2 会话：Task100 present path engaged 但屏幕仍蜷角（探针全绿的矛盾）',
      'Task100 present path engaged' in log_new and
      'EASU landing verified in fb0: top-strip nonzero 89/90' in log_new and
      'drvProbe=89/90' in log_new)

print('===== B. shaderc_include.c 粘行修复 =====')
inc = read('Natives/shaderc_include.c')
check('B1 换行守卫存在且位于 #line 拼接之前',
      "o->len > 0 && o->buf[o->len - 1] != '\\n'" in inc and
      inc.index("o->buf[o->len - 1] != '\\n'") < inc.index('snprintf(linefix'))
check('B2 守卫注释钉 Task103 与装机报错形态',
      'Task 103' in inc and 'cannot be preceded' in inc)
check('B3 原语：守卫仅追加单个换行（行号语义由 #line 全权重置）',
      'ame_out_append_str(o, "\\n")' in inc)

# 行为测试：合成着色器（含/不含尾换行的 include）走真实展开器
HARNESS = r'''
#include "shaderc_include.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef struct { const char *source_name; size_t source_name_length;
                 const char *content; size_t content_length; } fr_t;
static const char *g_nonl; static const char *g_withnl;
static void *resolver(void *ud, const char *name, int type, const char *req, size_t d) {
    (void)ud;(void)type;(void)req;(void)d;
    const char *c = strstr(name, "nonl") ? g_nonl : g_withnl;
    fr_t *r = (fr_t *)malloc(sizeof *r);
    r->source_name = name; r->source_name_length = strlen(name);
    r->content = c; r->content_length = strlen(c);
    return r;
}
static void releaser(void *ud, void *res) { (void)ud; free(res); }
int main(void) {
    g_nonl = "int a_nonl;\nint b_nonl;";          /* 无尾换行：粘行高危 */
    g_withnl = "int a_withnl;\nint b_withnl;\n";  /* 规范收尾 */
    const char *src = "#version 330\n"
                      "#include <test:nonl.glsl>\n"
                      "int mid;\n"
                      "#include <test:withnl.glsl>\n"
                      "int tail;\n";
    size_t out_len = 0;
    char *out = ame_include_expand(src, strlen(src), "t", resolver, NULL, releaser, NULL, &out_len);
    if (!out) { printf("EXPAND_NULL\n"); return 1; }
    printf("%s", out);
    return 0;
}
'''
with tempfile.TemporaryDirectory() as td:
    hp = os.path.join(td, 'h.c')
    open(hp, 'w').write(HARNESS)
    exe = os.path.join(td, 'h')
    r = subprocess.run(['cc', '-I', 'Natives', hp, 'Natives/shaderc_include.c', '-o', exe],
                       capture_output=True, text=True)
    check('B4 合成测试编译（真实展开器）', r.returncode == 0, r.stderr[:300])
    if r.returncode == 0:
        out = subprocess.run([exe], capture_output=True, text=True).stdout
        lines = out.split('\n')
        glued = [l for l in lines if '#line' in l and not l.startswith('#line')]
        check('B5 无尾换行 include 不再粘行（#line 全部行首）', not glued, f'glued={glued}')
        check('B6 内容保序（a_nonl/b_nonl/mid/a_withnl/b_withnl/tail 顺序完整）',
              all(k in out for k in ['a_nonl', 'b_nonl', 'int mid', 'a_withnl', 'b_withnl', 'int tail']))
        check('B7 行号指令成对（两个 include → 两条 #line）',
              sum(1 for l in lines if l.startswith('#line')) == 2)
        check('B8 无尾换行 include 的合成换行只补一处（b_nonl 行后紧跟 #line 3 再接 int mid）',
              'int b_nonl;' in out and out.index('int b_nonl;') < out.index('#line 3') <
              out.index('int mid'))

print('===== C. EASU 哨兵注入（osm_bridge 字符串手术）=====')
ob = read('Natives/ctxbridges/osm_bridge.mm')
check('C1 手术锚点：声明注入（uniform float uMarker）',
      '"out vec4 oFragColor;"' in ob and 'uniform float uMarker;' in ob)
check('C2 手术锚点：写入注入（ip==(0,0) 时 alpha=哨兵）',
      '"oFragColor = vec4(color, 1.0);"' in ob and
      'if (ip.x == 0u && ip.y == 0u) oFragColor.a = uMarker;' in ob)
check('C3 手术失败防御（markerArmed=false 回退旧逻辑）',
      'ame83_fsr.markerArmed = false;' in ob and
      ob.index('ame83_fsr.markerArmed = false;') < ob.index('kDeclAnchor'))
check('C4 uniform 定位 + 优化掉防御', 'glGetUniformLocation(prog, "uMarker")' in ob)
check('C5 哨兵值域 1..254（避开 0=默认 255=常规不透明 alpha）',
      '1u + (unsigned)(ame83_fsr.frames % 254u)' in ob)
check('C6 绘制前设置（在 glDrawArrays 之前）',
      ob.index('glUniform1f(ame83_fsr.uMarker') < ob.index('glDrawArrays(GL_TRIANGLES, 0, 6)'))
mg = read('Natives/external/MobileGlues/MobileGlues-cpp/gl/FSR1/FSRShaderSource.h')
check('C7 MobileGlues 共享头零改动（无 uMarker 泄漏）', 'uMarker' not in mg)

print('===== D. 哨兵票/翻转判决/取证 =====')
check('D1 票源：present 全幅回读的 scratch[3]（零额外 GL 调用）',
      'ame100_present.scratch[3]' in ob)
check('D2 初始 3 连定性', 'mkConsecM >= 3' in ob and 'mkConsecMiss >= 3' in ob)
check('D3 跨阶段翻转（10 连反向）',
      'mkConsecMiss >= 10' in ob and 'mkConsecM >= 10' in ob)
check('D4 状态迁移即同步 verdict', 'ame99_fsrdiag.verdict = newState;' in ob)
check('D5 迁移时一次性 memcmp 取证（present vs bundle 同源性）',
      'memcmp(ame100_present.present, bundle.buffer' in ob)
check('D6 旧 90 帧统计：armed 时不 overwrite 判决（final90Logged 门）',
      'final90Logged' in ob and '!ame83_fsr.markerArmed' in ob)
check('D7 投票段持续运行（外门含 markerArmed 分支）',
      '(ame99_fsrdiag.verdict == 0 || ame83_fsr.markerArmed)' in ob)
check('D8 GPU 探针扩展（glFinish 前哨兵直读 + MATCH/MISMATCH 判读）',
      'Task103 sentinel pixel (0,0)' in ob and 'MATCH (draw + direct readback healthy pre-glFinish)' in ob)
check('D9 心跳新增 mk=N/M', 'mk=%d/%d' in ob)
check('D10 哨兵判决日志锚点（LANDED/NOT LANDED + 兜底语义）',
      'Task103 EASU sentinel verdict' in ob and 'CG stretch fallback engaged' in ob)
check('D11 gl 表新增 glUniform1f（typedef + dlsym 条目）',
      'void (*glUniform1f)(int, float);' in ob and '{"glUniform1f",               (void**)&ame83_fsr.gl.glUniform1f},' in ob)
check('D12 EASU ready 日志带 marker 状态', 'uTargetSize=%d marker=%d' in ob)
check('D13 CG 拉伸数据源优先级保持（present 优先，bundle 回退）',
      'presentThisFrame ? ame100_present.present' in ob)

print('===== E. 判决状态机行为矩阵（Python 镜像）=====')
def simulate(votes):
    st, cm, cmiss, states = 0, 0, 0, []
    for v in votes:
        if v: cm += 1; cmiss = 0
        else: cmiss += 1; cm = 0
        ns = st
        if ns == 0:
            if cm >= 3: ns = 1
            elif cmiss >= 3: ns = -1
        elif ns == 1 and cmiss >= 10: ns = -1
        elif ns == -1 and cm >= 10: ns = 1
        st = ns
        states.append(st)
    return states
check('E1 全命中：第 3 帧起 verdict=1', simulate([1]*5) == [0, 0, 1, 1, 1])
check('E2 全失手：第 3 帧起 verdict=-1（CG 拉伸兜底）', simulate([0]*5) == [0, 0, -1, -1, -1])
check('E3 噪声容限（2 失手不足以翻转）', simulate([1]*3 + [0, 0] + [1]*2) == [0, 0, 1, 1, 1, 1, 1])
check('E4 跨阶段翻转（3 中后 10 失 → 兜底）',
      simulate([1]*3 + [0]*9)[-1] == 1 and simulate([1]*3 + [0]*10)[-1] == -1)
check('E5 反向恢复（兜底后 10 连中 → EASU）', simulate([0]*3 + [1]*10)[-1] == 1)
check('E6 状态机镜像与 C 常量一致（3/10）', '>= 3' in ob and '>= 10' in ob)

print('===== F. FAQ + version.h =====')
faq = read('Natives/LauncherHelpViewController.m')
items = re.findall(r'LauncherHelpFaqItem \*(\w+) = \[\[LauncherHelpFaqItem alloc\] init\];', faq)
check('F1 FAQ 34 条目（Task103 33 + Task106 sparkProfiler）', len(items) == 34, f'got {len(items)}')
check('F2 sodiumGlsl 条目（签名 + 机制 + 验证锚点 + 旧构建自救）',
      any(i == 'sodiumGlsl' for i in items) and
      'preprocessor directive cannot be preceded by another token' in faq and
      'solid_terrain' in faq and '[amethyst-include] expanded' in faq)
check('F3 fsrCorner 重锚（Task103 哨兵语义 + far=N/M + LANDED/NOT LANDED）',
      'Task103 地面真值闭环' in faq and 'far=N/M' in faq and
      'Task103 EASU sentinel verdict' in faq)
vh = read('Natives/external/MobileGlues/MobileGlues-cpp/version.h')
check('F4 version.h REVISION 17 addendum (Task 103, no bump)',
      'REVISION 17 addendum (Task 103, no bump)' in vh and 'REVISION stays 17' in vh)

print('===== G. 卫生 =====')
r = subprocess.run(['bash', 'scripts/task83_syntax_osm.sh'], capture_output=True, text=True)
check('G1 task83 语法门（ame83 段）', r.returncode == 0 and 'syntax OK' in r.stdout)
r = subprocess.run(['python3', 'scripts/task103_syntax_swap.py'], capture_output=True, text=True)
check('G2 task103 语法门（swap 段投票/呈现）', r.returncode == 0 and 'syntax OK' in r.stdout, r.stdout[-200:])
new_logs = re.findall(r'NSLog\(@?"[^"]*%@[^"]*"', ob)
check('G3 新 NSLog 无 %@（ObjC→C 变换保护）', not new_logs, f'{new_logs[:2]}')
check('G4 展开器修复脚本入库（scripts/task103_faq_sync.py）',
      os.path.exists('scripts/task103_faq_sync.py'))
for v in ['85', '86', '87', '94', '95', '97', '98', '99', '100']:
    r = subprocess.run(['python3', f'scripts/verify_task{v}.py'], capture_output=True, text=True, timeout=300)
    last = [l for l in r.stdout.strip().split('\n') if l.strip()][-1] if r.stdout.strip() else ''
    real_fail = re.search(r'([1-9]\d*)\s*FAIL', last) is not None or r.returncode != 0
    check(f'G5 级联 verify_task{v}', not real_fail, last[:80])

print(f'\n===== 结果：{PASS} PASS / {FAIL} FAIL =====')
sys.exit(1 if FAIL else 0)
