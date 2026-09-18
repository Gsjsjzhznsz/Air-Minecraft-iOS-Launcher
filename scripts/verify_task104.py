#!/usr/bin/env python3
"""Task104 verifier: 30fps AFK cap fix (heartbeat + options) + far-corner sentinel."""
import subprocess, sys, os
os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # repo root

ok = fail = 0
def check(name, cond):
    global ok, fail
    print(('  PASS  ' if cond else '  FAIL  ') + name)
    ok, fail = ok + (1 if cond else 0), fail + (0 if cond else 1)

ib = open('Natives/input_bridge_v3.m', encoding='utf-8').read()
ob = open('Natives/ctxbridges/osm_bridge.mm', encoding='utf-8').read()
mo = open('JavaApp/src/launcher/net/kdt/pojavlaunch/utils/MCOptionUtils.java', encoding='utf-8').read()
pj = open('JavaApp/src/launcher/net/kdt/pojavlaunch/PojavLauncher.java', encoding='utf-8').read()
faq = open('Natives/LauncherHelpViewController.m', encoding='utf-8').read()

print('===== A. 30fps SHORT_AFK 根治（input_bridge_v3.m） =====')
check('A1 AFK 心跳实现（45s dispatch timer + wheel(0,0)）',
      'ame104_armAfkHeartbeat' in ib and '45 * NSEC_PER_SEC' in ib and 'pushSDLMouseWheel(0.0f, 0.0f)' in ib)
check('A2 窗口注册即布防（Amethyst_SetSDLWindow 调用）',
      ib.index('ame104_armAfkHeartbeat();') > ib.index('void Amethyst_SetSDLWindow'))
check('A3 心跳锚点日志（armed + #N 行）',
      'Task104 AFK heartbeat armed' in ib and 'Task104 AFK heartbeat #%lu' in ib)
check('A4 前向声明存在（定义在使用之后）', 'static void ame104_armAfkHeartbeat(void);' in ib)

print('===== B. options 写入加固（Java） =====')
check('B1 MCOptionUtils.set 去重（ListIterator 替换+删除重复行）',
      'it.remove(); // 重复行' in mo and 'ListIterator<String> it' in mo)
check('B2 getFromFile 落盘校验助手', 'public static String getFromFile(String key)' in mo)
check('B3 PojavLauncher 落盘校验日志锚点',
      'Task104 on-disk verification' in pj and 'getFromFile("inactivityFpsLimit")' in pj)

print('===== C. 远角哨兵 + 兜底升级（osm_bridge.mm） =====')
check('C1 远角哨兵注入（top-right 4x4 块）',
      'uTargetSize.x - 4.0' in ob and 'far-corner sentinel' in ob)
check('C2 双哨兵 AND 票（got && gotFar）',
      'bool mkHit = (got == (unsigned char)ame83_fsr.markerCode)' in ob
      and '&& (gotFar == (unsigned char)ame83_fsr.markerCode);' in ob)
check('C3 mkFarHits 统计字段', 'int mkFarHits;' in ob and '++ame99_fsrdiag.mkFarHits;' in ob)
check('C4 远角读取边界保护（>=8 尺寸 + farIdx 越界钳制）',
      'bundle.width >= 8 && bundle.height >= 8 && farIdx < total104' in ob)
check('C5 verdict 行追加 far-corner 统计', 'Task104 far-corner hits %d/%d' in ob)
check('C6 心跳追加 far=%d/%d（不破坏既有 task100 子串锚）',
      'far=%d/%d' in ob and 'verdict=%d present=%d drvProbe=%d/%d' in ob)
check('C7 GPU probe 单次远角直读 + 判读文案',
      'Task104 far-corner (%d,%d) alpha=%02x' in ob and 'MISS (coverage limited to game region' in ob)
check('C8 视口验证（glGetIntegerv(GL_VIEWPORT) 一次性日志）',
      'Task104 EASU viewport check' in ob and 'CLAMPED/MISMATCH' in ob)
check('C9 兜底滤镜 Linear / 落地还原 Nearest（共享文件级旗标）',
      'ame104_filters_linear' in ob and 'kCAFilterLinear' in ob and 'kCAFilterNearest' in ob
      and 'restored to Nearest' in ob)
check('C10 (0,0) 哨兵与既有锚点保留（scratch[3] 字面量）', 'ame100_present.scratch[3]' in ob)

print('===== D. FAQ 原位刷新（计数不变，零级联） =====')
check('D1 fpsUnlock 补 26.3 不活动限帧机制 + Task104 修复指引',
      '26.x 整合包加载中/不操作时被压在 30fps' in faq and 'Task104 AFK heartbeat' in faq)
check('D2 fsrCorner 补 Task104 双哨兵语义', 'Task104 远角哨兵' in faq and 'far=N/M' in faq)

print('===== E. 语法门 =====')
r = subprocess.run(['python3', 'scripts/task103_syntax_swap.py'], capture_output=True, text=True)
check('E1 osm_swap_buffers 段 g++ 语法门', r.returncode == 0)

print(f'\n===== 结果：{ok} PASS / {fail} FAIL =====')
sys.exit(1 if fail else 0)
