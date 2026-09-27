#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task 188 验证器：15fddc2 六日志裁决 + 六项修复轮。
vgpu 包装块 textureGather 仿真 / Forge split-package 镜像撤除 / 安装器杂散文件
自愈 + 后置产物验证 / UIRequiresFullScreen 横屏 / ANGLE 取证升级三件套 /
FCL 式控件仓库。
"""
import json, os, re, subprocess, sys

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Amethyst-iOS-MyRemastered'))
PASS, FAIL = 0, 0
def check(name, cond):
    global PASS, FAIL
    print(("OK   " if cond else "FAIL ") + name)
    if cond: PASS += 1
    else: FAIL += 1

def read(p): return open(p, encoding='utf-8').read()

# ---------- A. vgpu textureGather 仿真 ----------
sc = read('Natives/external/vgpu/src/gl/pack/shaderconv.c')
check("A1 textureGather_ 仿真定义（texelFetch 四点采样）",
      'texelFetch(tex, c0, 0).r' in sc and 'textureGather_(sampler2D tex, vec2 P)' in sc)
check("A2 基点公式 floor(P*size-0.5) 在场",
      'floor(P * vec2(sz) - 0.5)' in sc)
check("A3 越界钳制 clamp 在场", 'clamp(tc, ivec2(0), sz-ivec2(1))' in sc)
check("A4 comp 重载启用（动态下标）", 'texelFetch(tex, c0, 0)[k]' in sc)
check("A5 Offset_ 变体带 ivec2(offset)", '+ ivec2(offset)' in sc)
# 活跃（非注释）原生 textureGather 调用必须为 0
in_block = False; active_bad = 0
for l in sc.split('\n'):
    stripped, j = '', 0
    while j < len(l):
        if in_block:
            if l.startswith('*/', j): in_block = False; j += 2; continue
            j += 1; continue
        if l.startswith('/*', j): in_block = True; j += 2; continue
        if l.startswith('//', j): break
        stripped += l[j]; j += 1
    if 'textureGather(' in stripped and 'textureGather_' not in stripped.split('textureGather(')[0][-20:]:
        active_bad += 1
check("A6 零活跃原生 textureGather 调用", active_bad == 0)
r = subprocess.run(['gcc', '-fsyntax-only',
                    '-I', 'Natives/external/vgpu/include',
                    '-I', 'Natives/external/vgpu/src',
                    '-I', 'Natives/external/vgpu/src/gl',
                    'Natives/external/vgpu/src/gl/pack/shaderconv.c'],
                   capture_output=True, text=True)
check("A7 shaderconv.c gcc 语法门", r.returncode == 0)

# ---------- B. Forge split package ----------
mk = read('JavaApp/Makefile')
check("B1 lwjgl_lib 音频类镜像已撤除", 'lwjgl_lib_$*/com/apple/ios/audio' not in mk)
check("B2 lwjgl_lib services 镜像已撤除", 'lwjgl_lib_$*/META-INF/services' not in mk)
check("B3 Task188 病历注释在场（ResolutionException）", 'ResolutionException' in mk)
check("B4 launcher 侧音频包仍在（唯一提供者）",
      os.path.exists('JavaApp/src/launcher/com/apple/ios/audio/NativeAudioCapture.java') and
      'com.apple.ios.audio.IOSAudioMixerProvider' in read('JavaApp/src/launcher/META-INF/services/javax.sound.sampled.spi.MixerProvider'))
check("B5 lwjgl overlay 对音频包零引用（回归确认）",
      subprocess.run(['grep', '-rl', 'com.apple.ios.audio', 'JavaApp/src/lwjgl/'],
                     capture_output=True).stdout.strip() == b'')

# ---------- C. 安装器加固 ----------
uh, um = read('Natives/utils.h'), read('Natives/utils.m')
check("C1 ame188_ensureDirectoryHealed 声明", 'BOOL ame188_ensureDirectoryHealed(NSString *path);' in uh)
check("C2 实现：祖先链扫描 + 杂散文件移除",
      'ame188_ensureDirectoryHealed' in um and 'stray file blocking ancestor removed' in um)
check("C3 实现：最终路径同名文件移除", 'stray file at target removed' in um)
nf = read('Natives/installer/NeoForgeDirectInstaller.m')
fd = read('Natives/installer/ForgeDirectInstaller.m')
check("C4 NeoForge 安装器接入自愈（主下载路径）",
      'Task188：杂散文件自愈建目录' in nf and nf.count('ame188_ensureDirectoryHealed') >= 5)
check("C5 NeoForge extractAllMavenEntries 自愈接入（病历现场）",
      'extractAllMavenEntries' in nf and 'Task188：杂散文件自愈（病历：universal jar' in nf)
check("C6 NeoForge Step E 后置产物验证",
      'Step E (Task188)：后置产物验证' in nf and 'post-processor verification FAILED' in nf)
check("C7 NeoForge PK 魔数校验", "ame188_p[0] == 0x50 && ame188_p[1] == 0x4B" in nf)
check("C8 Forge 安装器 Step E 同款", 'Step E (Task188)：后置产物验证' in fd and 'post-processor verification FAILED' in fd)
check("C9 Forge ensureDirectoryExists 升级为全链自愈委托",
      'ame188_ensureDirectoryHealed(path)' in fd)

# ---------- D. 强制横屏 ----------
pl = read('Natives/Info.plist')
check("D1 UIRequiresFullScreen=true", re.search(r'UIRequiresFullScreen</key>\s*<true/>', pl) is not None)
check("D2 Task188 病历注释（窗口模式根因）", 'Task188（强制横屏·第二轮）' in pl)
sd = read('Natives/SceneDelegate.m')
check("D3 Code=101 降噪为单次提示", 's_task188_logged' in sd and 'expected in window mode' in sd)
check("D4 方向列表保持横屏 only", pl.count('UIInterfaceOrientationLandscapeLeft') >= 2
      and 'UIInterfaceOrientationPortrait</string>' not in pl)

# ---------- E. ANGLE 取证升级 ----------
gb = read('Natives/ctxbridges/gl_bridge.m')
check("E1 readPixels typedef + 结构体成员", 'ame_es_readpx_t' in gb and 'ame_es_readpx_t    readPixels' in gb)
check("E2 Task146 派发接入 glReadPixels", 'dlsym(ame145_rendererHandle, "glReadPixels")' in gb)
check("E3 1x1 中心回读（≤3 次/会话）", 's_task188_reads < 3' in gb and 'Task188 readback' in gb)
check("E4 回读预清错误队列", 'while (es.getError()) {}' in gb)
check("E5 GL_ALPHA_BITS/GL_DEPTH_BITS 探测", '0x0D55' in gb and '0x0D56' in gb)
check("E6 相位标记（Invalid pname 定位）", 'Task188 phase-tag' in gb)
check("E7 CAMetalLayer pixelFormat/opaque 取证",
      'Task188 layer: pixelFormat=' in gb and 'framebufferOnly' in gb)

# ---------- F. 控件仓库 ----------
check("F1 ControlRepoViewController.h/.m 存在",
      os.path.exists('Natives/ControlRepoViewController.h') and os.path.exists('Natives/ControlRepoViewController.m'))
crv = read('Natives/ControlRepoViewController.m')
check("F2 双源（raw.githubusercontent 主 + jsDelivr 回退）",
      'raw.githubusercontent.com' in crv and 'cdn.jsdelivr.net' in crv)
check("F3 布局校验（mControlDataList 数组门）", 'mControlDataList' in crv and 'download.invalid' in crv)
check("F4 落盘 controlmap/ + 自愈建目录", 'controlmap' in crv and 'ame188_ensureDirectoryHealed' in crv)
check("F5 防连点下载锁", 'downloading containsObject' in crv.replace('[self.downloading ', 'downloading '))
cc = read('Natives/CustomControlsViewController.m')
check("F6 编辑器长按菜单入口（actionMenuRepo）", 'actionMenuRepo' in cc and 'custom_controls.control_menu.repo' in cc)
cml = read('Natives/CMakeLists.txt')
check("F7 CMake 源列表收录", 'ControlRepoViewController.m' in cml)
for lang in ('zh-Hans', 'zh-Hant', 'zh-CN', 'en'):
    s = read(f'Natives/resources/{lang}.lproj/Localizable.strings')
    n = s.count('custom_controls.repo.')
    check(f"F8 {lang} 仓库 i18n 键 ≥10", n >= 10)
idx = json.load(open('controls/index.json'))
check("F9 仓库索引 3 布局", len(idx.get('layouts', [])) == 3)
allv = all(json.load(open('controls/' + l['file'])).get('mControlDataList') is not None
           for l in idx['layouts'])
check("F10 种子布局全部为合法 layoutDictionary", allv)
check("F11 种子生成脚本入库", os.path.exists('/home/z/my-project/scripts/task188_seed_controls.py'))

# ---------- G. 括号门（栈式：计数平衡但类型错位也能抓——Task188 CI 三连败教训） ----------
def balanced(path):
    s = open(path, encoding='utf-8').read()
    s = re.sub(r'@"(?:[^"\\]|\\.)*"', '""', s)
    s = re.sub(r'//[^\n]*', '', s)
    s = re.sub(r'/\*.*?\*/', '', s, flags=re.S)
    stack = []
    for ch in s:
        if ch in '([{':
            stack.append(ch)
        elif ch in ')]}':
            if not stack or stack[-1] != {')':'(', ']':'[', '}':'{'}[ch]:
                return False
            stack.pop()
    return not stack
for f in ['Natives/ctxbridges/gl_bridge.m', 'Natives/utils.m', 'Natives/SceneDelegate.m',
          'Natives/installer/NeoForgeDirectInstaller.m', 'Natives/installer/ForgeDirectInstaller.m',
          'Natives/ControlRepoViewController.m', 'Natives/CustomControlsViewController.m']:
    check(f"G 括号门 {os.path.basename(f)}", balanced(f))

print(f"\nRESULT: {PASS} pass, {FAIL} fail")
sys.exit(1 if FAIL else 0)
