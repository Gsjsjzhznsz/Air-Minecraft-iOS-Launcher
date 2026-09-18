#!/usr/bin/env python3
"""Task105 verifier: viewport-adaptive EASU input region (BMC2 corner-shrink round 4).

判读依据（c947464 装机日志，bacbf1e 构建）：
  - BMC2（1.20.1/GLFW/zink+FSR）双哨兵 LANDED + present==bundle + fps=60，
    但 GPU 探针顶带 (2352,1636) RGB=000000 → EASU 输入区域内 MC 内容没填满；
  - 对照 26.3（SDL 路径）同探针 c85e84ff 活色全屏正常；
  - vanilla 1.20.1 反编译核对（task105_decomp）：framebuffer/blit 均取
    glfwGetFramebufferSize（= shim 1814×1262）→ 分叉在 mod 尺寸链上游。

修复面：osm_swap_buffers 在交换时刻读 glGetIntegerv(GL_VIEWPORT)（MC 最终
呈现 blit 恰在 flipFrame 前设置它），EASU 输入/探针/兜底裁剪全部跟随
effW×effH；三重闸门防 aux 视口误采；证据日志 + 心跳 vp=。
"""
import subprocess, sys, os

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # repo root

ok = fail = 0
def check(name, cond, detail=''):
    global ok, fail
    print(('  PASS  ' if cond else '  FAIL  ') + name)
    if not cond and detail:
        print('        ' + detail[:300])
    ok, fail = ok + (1 if cond else 0), fail + (0 if cond else 1)

ob = open('Natives/ctxbridges/osm_bridge.mm', encoding='utf-8').read()
faq = open('Natives/LauncherHelpViewController.m', encoding='utf-8').read()
vh = open('Natives/external/MobileGlues/MobileGlues-cpp/version.h', encoding='utf-8').read()

swap = ob[ob.index('void osm_swap_buffers() {'):]
swap = swap[:swap.index('void osm_swap_interval')]

print('===== A. 视口自适应核心（osm_bridge.mm swap 段） =====')
check('A1 swap 时刻读取 MC 真实视口（glGetIntegerv(GL_VIEWPORT)）',
      'ame83_fsr.gl.glGetIntegerv(GL_VIEWPORT, vp105);' in swap)
check('A2 有效输入区域变量（effW/effH 默认=窗口信仰）',
      'int effW = windowWidth, effH = windowHeight;' in swap)
check('A3 闸门 1：原点 (0,0)（anchored105）',
      'bool anchored105 = (vp105[0] == 0 && vp105[1] == 0);' in swap)
check('A4 闸门 2：正尺寸且不超表面（fits105）',
      'bool fits105 = (vp105[2] > 0 && vp105[3] > 0 &&' in swap and
      '(uint32_t)vp105[2] <= currentBundle->osm.width' in swap)
check('A5 闸门 3：面积 ≥ 信仰 1/4（area105，整型乘法无除零）',
      '(long long)vp105[2] * (long long)vp105[3] * 4ll' in swap and
      '>= (long long)windowWidth * (long long)windowHeight);' in swap)
check('A6 采纳条件（三闸门全过且 ≠ 信仰才自适应）',
      'if (anchored105 && fits105 && area105 &&' in swap and
      '(vp105[2] != windowWidth || vp105[3] != windowHeight)) {' in swap)
check('A7 EASU 调用改用 effW/effH（旧 windowWidth 调用点已替换）',
      'ame83_fsr_upscale(effW, effH,' in swap and
      'ame83_fsr_upscale(windowWidth' not in swap)
check('A8 EASU 门控条件同步（effW 正值 + 小于表面）',
      '(effW > 0 && effH > 0) &&' in swap and
      '((uint32_t)effW < currentBundle->osm.width || (uint32_t)effH < currentBundle->osm.height)) {' in swap)
check('A9 探针/兜底裁剪区域跟随（gameW/gameH = effW/effH）',
      'int gameW = effW, gameH = effH;' in swap and
      'int gameW = windowWidth' not in swap)
check('A10 resolve 幂等入口（真实实现 resolved 旗标防重试）',
      'if (ame83_resolve_gl() && ame83_fsr.gl.glGetIntegerv &&' in swap)
check('A11 null/尺寸前置（currentBundle 非空 + 表面正值）',
      'currentBundle != NULL &&' in swap and
      'currentBundle->osm.width > 0 && currentBundle->osm.height > 0) {' in swap)

print('===== B. 证据/心跳 =====')
check('B1 证据行（每个新视口尺寸一次）',
      'Task105 viewport evidence: MC present viewport 0,0 %dx%d vs launcher window belief %dx%d -- %s' in swap and
      'static int s_vp105W = -1, s_vp105H = -1;' in swap)
check('B2 证据三分支（match / DIVERGED 自适应 / gated 保守）',
      'match (vanilla path, no adaptation)' in swap and
      'DIVERGED: EASU input follows MC (adaptive) -- geometry restored' in swap and
      'diverged but gated (origin/area); EASU keeps launcher belief' in swap)
check('B3 心跳追加 vp=WxH（自适应期标注）',
      'vp=%dx%d%s' in swap and 'vp105Adapted ? " (adaptive)" : ""' in swap)
check('B4 心跳保留 win=（信仰值不删，跨版本日志可比）',
      'win=%dx%d osm=%ux%u' in swap)

print('===== C. 行为矩阵（Python 镜像推演，无设备依赖） =====')
def adapt(vp, belief_w, belief_h, surf_w, surf_h):
    """镜像 osm_swap_buffers 的 Task105 采纳逻辑，返回 (effW, effH, adapted)。"""
    eff_w, eff_h = belief_w, belief_h
    adapted = False
    if not (belief_w > 0 and belief_h > 0):
        return eff_w, eff_h, adapted
    x, y, w, h = vp
    anchored = (x == 0 and y == 0)
    fits = (w > 0 and h > 0 and w <= surf_w and h <= surf_h)
    area = (w * h * 4) >= (belief_w * belief_h)
    if anchored and fits and area and (w != belief_w or h != belief_h):
        eff_w, eff_h = w, h
        adapted = True
    return eff_w, eff_h, adapted

# C1 正常路径（26.3/SDL）：视口 == 信仰 → 零自适应（字节级行为不变）
w, h, a = adapt((0, 0, 1814, 1262), 1814, 1262, 2360, 1640)
check('C1 视口==信仰 → 零自适应（26.3 路径零回归）',
      (w, h, a) == (1814, 1262, False))
# C2 BMC2 型折半：907×631 → 自适应接管（面积 1/4 恰好过闸）
w, h, a = adapt((0, 0, 907, 631), 1814, 1262, 2360, 1640)
check('C2 折半视口 907×631 → EASU 输入跟随 MC（几何恢复）',
      (w, h, a) == (907, 631, True))
# C3 点尺寸型：1180×820（65% 面积）→ 同样接管
w, h, a = adapt((0, 0, 1180, 820), 1814, 1262, 2360, 1640)
check('C3 点尺寸视口 1180×820 → 自适应接管', (w, h, a) == (1180, 820, True))
# C4 aux 小视口：512×512（面积 11%）→ 拒绝，保持信仰（= 旧行为）
w, h, a = adapt((0, 0, 512, 512), 1814, 1262, 2360, 1640)
check('C4 aux 视口 512×512（<1/4 面积）→ 保守拒绝',
      (w, h, a) == (1814, 1262, False))
# C5 非零原点：拒绝
w, h, a = adapt((10, 20, 907, 631), 1814, 1262, 2360, 1640)
check('C5 非零原点视口 → 拒绝（blit 恒 (0,0) 锚定）',
      (w, h, a) == (1814, 1262, False))
# C6 超表面视口：拒绝
w, h, a = adapt((0, 0, 3000, 2000), 1814, 1262, 2360, 1640)
check('C6 超表面视口 → 拒绝（不可能区域）',
      (w, h, a) == (1814, 1262, False))
# C7 恢复全分辨率（heal 后）：视口 == 表面 → 采纳为 eff==表面（EASU 门控
#    effW<surface 不成立 → 正确跳过升采样直呈全幅；若拒绝采纳则 eff=信仰
#    <surface → 会错误放大全幅帧的左下裁剪）
w, h, a = adapt((0, 0, 2360, 1640), 1814, 1262, 2360, 1640)
check('C7 视口==表面（heal 全分辨率）→ eff==表面（EASU 门控正确跳过）',
      (w, h, a) == (2360, 1640, True))
# C8 尺寸略偏（未偶数化）：1815×1261 → 接管（保真度更高）
w, h, a = adapt((0, 0, 1815, 1261), 1814, 1262, 2360, 1640)
check('C8 未偶数化视口 1815×1261 → 自适应跟随', (w, h, a) == (1815, 1261, True))
# C9 零视口（极早期）：拒绝
w, h, a = adapt((0, 0, 0, 0), 1814, 1262, 2360, 1640)
check('C9 零视口 → 拒绝', (w, h, a) == (1814, 1262, False))

print('===== D. 语法门 + 既有锚点不回退 =====')
r = subprocess.run(['python3', 'scripts/task103_syntax_swap.py'], capture_output=True, text=True)
check('D1 osm_swap_buffers 段 g++ 语法门（含 Task105 新段）',
      r.returncode == 0, r.stdout[-200:] + r.stderr[-200:])
check('D2 Task104 远角哨兵锚点保留（far-corner 双哨兵 AND 票不回退）',
      'bool mkHit = (got == (unsigned char)ame83_fsr.markerCode)' in ob and
      '&& (gotFar == (unsigned char)ame83_fsr.markerCode);' in ob and
      'Task104 far-corner hits %d/%d' in ob)
check('D3 Task100 权威呈现路径锚点保留（present 帧缓冲直读）',
      'ame100_present_frame((int)bundle.width, (int)bundle.height);' in ob and
      'Task100 present path engaged' in ob)
check('D4 Task83 heal 路径保留（shader 失败恢复全分辨率）',
      'Task83 FSR upscale unavailable -- restoring MC window to surface' in ob)
check('D5 CG 拉伸兜底跟随有效区域（topRow/crop 用 gameW/gameH）',
      'int topRow = (int)bundle.height - gameH;' in ob and
      'CGImageCreate(gameW, gameH, 8, 32, stride, bundle.color_space,' in ob)

print('===== E. FAQ + version.h =====')
check('E1 fsrCorner 补 Task105 视口自适应机制',
      'Task105 视口自适应' in faq and 'Task105 viewport evidence' in faq and
      'DIVERGED = 已自适应接管' in faq)
check('E2 fpsUnlock 负载判读（Task106 修正：呈现常数 + bundle-direct + 相位计时）',
      'Task106 判读修正' in faq and '重整合包建议视距 ≤16' in faq and 'bundle-direct present engaged' in faq)
check('E3 version.h REVISION 17 addendum (Task 105, no bump)',
      'REVISION 17 addendum (Task 105, no bump)' in vh)

print('===== F. 级联回归 =====')
for v in ('verify_task85.py', 'verify_task100.py', 'verify_task103.py', 'verify_task104.py'):
    r = subprocess.run([sys.executable, os.path.join('scripts', v)],
                       capture_output=True, text=True, timeout=600)
    last = [ln for ln in r.stdout.splitlines() if ln.strip()][-1] if r.stdout.strip() else ''
    check(f'F {v}', r.returncode == 0, (r.stdout + r.stderr)[-300:])

print(f'\n===== 结果：{ok} PASS / {fail} FAIL =====')
sys.exit(1 if fail else 0)
