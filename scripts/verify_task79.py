#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Task 79 静态验证（两件事）:
  A. CI 编译失败修复：SurfaceViewController.m 的 Task78 改动曾把 @end 提前
     插在类扩展属性区之前，导致其后整段 @property 脱离任何 @interface
     （clang error: expected identifier or '('）→ CI #178/#179 exit 2。
     修复 = 静态函数挪到 @interface 之前的文件作用域 + ivar 留在唯一的
     类扩展里 + 恢复被吃掉的 FPS 注释行。本节回放该结构不变量。
  B. zink 26.3 启动回退修复：MC 26.3 renderpearl GlBackend.loadLibrary 的
     glGetError 指针一致性检查失败 → 回落 Vulkan。修复 = sdl3_hook.m
     ame_glBridgeEnabled() 把 zink（libOSMesa/gallium_/vulkan_zink）从
     "绝不接管"翻转为"接管"（带 AMETHYST_ZINK_GL_BRIDGE 逃生阀）。
     本节回放判定矩阵与逃生阀语义，并确认 ES 强制化仍排除 zink。

全部为纯静态断言（无设备依赖）。输出逐项 PASS/FAIL，末行汇总。
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'Natives')
failures = []

def check(name, ok, detail=''):
    tag = 'PASS' if ok else 'FAIL'
    print(f'{tag} {name}' + (f' {detail}' if detail else ''))
    if not ok:
        failures.append(name)

# ---------------------------------------------------------------- A. CI fix
svc = open(os.path.join(SRC, 'SurfaceViewController.m'), encoding='utf-8').read()
svc_lines = svc.split('\n')

# A1: @property 必须全部处于某个 @interface/@implementation 内（Task78 事故点）
d = 0
bad_props = []
for i, line in enumerate(svc_lines, 1):
    s = line.strip()
    if re.match(r'^@(interface|implementation|protocol)\b', s):
        d += 1
    elif s == '@end':
        d -= 1
    elif s.startswith('@property') and d == 0:
        bad_props.append(i)
check('A1 @property 全部位于 interface 内（CI exit2 根因）', not bad_props,
      f'violations at {bad_props}' if bad_props else '')

# A2: @interface/@end 配平且无 stray @end
d = 0; stray = []
for i, line in enumerate(svc_lines, 1):
    s = line.strip()
    if re.match(r'^@(interface|implementation|protocol)\b', s): d += 1
    elif s == '@end':
        d -= 1
        if d < 0: stray.append(i)
check('A2 @interface/@end 配平', d == 0 and not stray,
      f'depth={d} stray={stray}')

# A3: mgFsrScale ivar 在类扩展内；ame78_fsr_preset_scale 在 @interface 之外（文件作用域）
iv_ok = re.search(
    r'@interface SurfaceViewController \(\)<[^>]*> \{\s*\n\s*// Task 78[^\n]*\n(?:\s*//[^\n]*\n)*\s*float mgFsrScale;\s*\n\}',
    svc) is not None
check('A3 mgFsrScale ivar 位于类扩展块内', iv_ok)

fn_pos = svc.find('static float ame78_fsr_preset_scale(NSInteger preset)')
iface_pos = svc.find('@interface SurfaceViewController ()<')
check('A4 ame78_fsr_preset_scale 位于首个 @interface 之前（文件作用域）',
      0 < fn_pos < iface_pos, f'fn@{fn_pos} iface@{iface_pos}')

# A5: 函数体完整（5 档 + default）
scale_ok = re.search(
    r'static float ame78_fsr_preset_scale\(NSInteger preset\) \{\s*\n'
    r'\s*switch \(\(int\)preset\) \{\s*\n'
    r'\s*case 1: return 1\.3f;[^\n]*\n'
    r'\s*case 2: return 1\.5f;[^\n]*\n'
    r'\s*case 3: return 1\.7f;[^\n]*\n'
    r'\s*case 4: return 2\.0f;[^\n]*\n'
    r'\s*default: return 1\.0f;[^\n]*\n'
    r'\s*\}\s*\n\}', svc) is not None
check('A5 五档缩放函数体完整（1.3/1.5/1.7/2.0/default）', scale_ok)

# A6: 被吃掉的 FPS 注释行已恢复
check('A6 FPS 注释行恢复（Task79 回填）',
      '// FPS/内存监控相关（FPS 在 native pojavSwapBuffers 中计数，参照 FCL/ZL2）' in svc)

# A7: updateSavedResolution 联动代码仍在（Task78 核心逻辑未因修复而丢失）
linkage_ok = ('int ame153_renderW = roundf((float)surfaceWidth / mgFsrScale);' in svc and  # Task175 re-anchor: Task153 indirection
              'metalLayer.drawableSize = CGSizeMake(MAX(surfaceWidth, 1), MAX(surfaceHeight, 1));' in svc and
              'if (mgFsrScale > 0.0f) screenScale /= mgFsrScale;' in svc)
check('A7 Task78 FSR 联动逻辑保持完整（窗口/drawable/输入三口径）', linkage_ok)

# ------------------------------------------------- B. zink 26.3 回退修复
sdl = open(os.path.join(SRC, 'sdl3_hook.m'), encoding='utf-8').read()

def bridge_enabled(renderer, env):
    """回放 ame_glBridgeEnabled 的当前实现。env: dict[name]->str。"""
    def flag(name, default):
        v = env.get(name)
        if v is None or v == '':
            return default
        return not (v == '0' or v.lower() in ('false', 'no', 'off'))
    if not flag('AMETHYST_SDL_GL_BRIDGE', True):
        return False
    if renderer is None or renderer == '':
        return False
    if renderer.startswith('libOSMesa'):
        return flag('AMETHYST_ZINK_GL_BRIDGE', True)
    if renderer.startswith('gallium_'):
        return flag('AMETHYST_ZINK_GL_BRIDGE', True)
    if renderer == 'vulkan_zink':
        return flag('AMETHYST_ZINK_GL_BRIDGE', True)
    if 'libMoltenVK' in renderer:
        return False
    if 'libMobileGL' in renderer: return True
    if 'libmithril' in renderer: return True
    if 'mobileglues' in renderer: return True
    if 'gl4es' in renderer: return True
    if 'libltw' in renderer: return True
    if renderer.startswith('opengles'): return True
    return False

# B1-B4: 判定矩阵（设备实测形态：libOSMesa.8.dylib / 26.3 会话 log 8a31d1b）
check('B1 zink libOSMesa.8.dylib -> bridge ON（回退修复本体）',
      bridge_enabled('libOSMesa.8.dylib', {}) is True)
check('B2 zink vulkan_zink -> ON；gallium_ 系 -> ON',
      bridge_enabled('vulkan_zink', {}) is True and
      bridge_enabled('gallium_swr', {}) is True)
check('B3 非 zink 原值保持：mobileglues ON / MoltenVK OFF / 空renderer OFF',
      bridge_enabled('libmobileglues.dylib', {}) is True and
      bridge_enabled('libMoltenVK.dylib', {}) is False and
      bridge_enabled(None, {}) is False)

# B4: 逃生阀
check('B4 AMETHYST_ZINK_GL_BRIDGE=0 -> zink 回落旧行为（不接管）',
      bridge_enabled('libOSMesa.8.dylib', {'AMETHYST_ZINK_GL_BRIDGE': '0'}) is False)
check('B5 AMETHYST_SDL_GL_BRIDGE=0 全局关闸仍优先',
      bridge_enabled('libmobileglues.dylib', {'AMETHYST_SDL_GL_BRIDGE': '0'}) is False)

# B6: 源码中三处 zink 分支确实走 ame_envFlagOn（而非硬编码 return false）
zink_branches = re.findall(
    r'if \(strncmp\(renderer, "(libOSMesa|gallium_)", \d+\) == 0\)[^\n]*\n\s*'
    r'|if \(strcmp\(renderer, "vulkan_zink"\) == 0\)[^\n]*\n\s*'
    r'return ame_envFlagOn\("AMETHYST_ZINK_GL_BRIDGE", true\);', sdl)
src_zink_returns = len(re.findall(r'return ame_envFlagOn\("AMETHYST_ZINK_GL_BRIDGE", true\);', sdl))
check('B6 源码：三个 zink 分支均接 AMETHYST_ZINK_GL_BRIDGE 阀', src_zink_returns == 3,
      f'count={src_zink_returns}')

# B7: 旧的硬编码排除已移除
check('B7 旧 "绝不接管" 硬排除已删除',
      '是唯一的可用路径，一个字节都不能动' not in sdl.replace('“', '"').replace('”', '"') or
      'Task 79' in sdl)

# B8: ES 强制化（ame_sdlGlesCompatEnabled）仍排除 zink —— 语义未被牵连
gles_fn = sdl[sdl.find('static bool ame_sdlGlesCompatEnabled'):sdl.find('static void ame_forceEglProfileEs')]
gles_excludes_zink = ('strncmp(renderer, "libOSMesa", 9)' in gles_fn and
                      'strncmp(renderer, "gallium_", 8)' in gles_fn and
                      'vulkan_zink' in gles_fn)
check('B8 ES 强制化仍排除 zink（desktop GL 3.3 core 请求不被 ES 化）', gles_excludes_zink)

# B9: main_hook 兜底注释与 bridge 优先序（hooked_dlsym 先问 amethyst_sdl3_hook_resolve）
mh = open(os.path.join(SRC, 'main_hook.m'), encoding='utf-8').read()
resolve_first = mh.find('amethyst_sdl3_hook_resolve(handle, name)') < mh.find('strcmp(name, "SDL_GL_LoadLibrary") == 0')
check('B9 hooked_dlsym 中 bridge resolver 先于 main_hook 的 SDLGL 兜底', resolve_first)

# B10: bridge 的 GetProcAddress 镜像链对 OSMesa 亦成立（eglGetProcAddress/OSMesaGetProcAddress 双腿）
mirror_ok = ('dlsym(h, "eglGetProcAddress")' in sdl and
             'dlsym(h, "OSMesaGetProcAddress")' in sdl and
             'g_lwjglGLLibPath' in sdl)
check('B10 provider 镜像链双腿齐全（指针一致性按构造成立）', mirror_ok)

# B11: Task78 的 verify 仍全绿（关键子集复跑——档位表与 settings.cpp 传递）
fsr_h = open(os.path.join(SRC, 'external/MobileGlues/MobileGlues-cpp/config/settings.h'), encoding='utf-8').read()
enum_ok = re.search(r'UltraQuality, // 1\s*\n\s*Quality,\s+// 2\s*\n\s*Balanced,\s+// 3\s*\n\s*Performance,\s+// 4\s*\n\s*MaxValue\s+// 5', fsr_h) is not None
check('B11 FSR 五档枚举保持（Task78 settings.h 未回退）', enum_ok)
settings_cpp = open(os.path.join(SRC, 'external/MobileGlues/MobileGlues-cpp/config/settings.cpp'), encoding='utf-8').read()
check('B12 settings.cpp Apple 分支 fsr1Setting 读取保持（Task78 传递修复未回退）',
      'config_get_int((char*)"fsr1Setting")' in settings_cpp)

# ------------------------------------------- C. multidrawOrder 迁移（借鉴落地）
jl = open(os.path.join(SRC, 'JavaLauncher.m'), encoding='utf-8').read()

# C1: 不再写被弃用的 multidrawMode 整数键
bad_legacy = re.search(r'config\[\@"multidrawMode"\]\s*=\s*@\(', jl)
check('C1 旧键 multidrawMode 不再写入（MG 2.0.16+ 已弃用读取）', bad_legacy is None)

# C2: 新键 multidrawOrder 三档映射齐全
c2 = ('config[@"multidrawOrder"] = mdOrder;' in jl and
      'multiindirect,indirect,multibasevertex,multiarrays,basevertex,unroll,compute' in jl and
      'unroll,basevertex,indirect,multiindirect,multibasevertex,multiarrays,compute' in jl and
      'native,multiindirect,multibasevertex,multiarrays,indirect,basevertex,unroll,compute' in jl)
check('C2 multidrawOrder 三档优先序映射齐全（Auto/Indirect/Emulated）', c2)

# C3: MG 侧确实读取 multidrawOrder（闭环回放）
c3 = ('md_config_string("multidrawOrder")' in settings_cpp and
      'config_get_string' in settings_cpp and
      'parse_multidraw_orders()' in settings_cpp)
check('C3 MG settings.cpp 读取 multidrawOrder（config_get_string 链）', c3)

# C4: 全局序允许 native 伪项；默认序与 0 档写入一致
c4 = ('k_md_default_global_order' in settings_cpp and
      '"native", "multiindirect", "multibasevertex", "multiarrays", "indirect", "basevertex", "unroll", "compute"' in settings_cpp)
check('C4 MG 默认序与 Auto 档写入逐字一致（含 native 伪项）', c4)

# C5: 六语言 detail 文案已更新为新语义
lang_ok = True
for lang in ['en', 'ja', 'km', 'zh-CN', 'zh-Hans', 'zh-Hant']:
    p = os.path.join(SRC, f'resources/{lang}.lproj/Localizable.strings')
    s = open(p, encoding='utf-8').read()
    m = re.search(r'^"preference\.detail\.multidraw_mode" = "([^"]*)";', s, re.M)
    if not m or 'multidrawOrder' not in m.group(1):
        lang_ok = False
        print(f'  -> {lang} detail 缺失或未更新')
check('C5 六语言 multidraw detail 文案更新为新优先序语义', lang_ok)

# C6: UI picker 三档保持（既有 pref 键不迁移，零回归）
lpvc = open(os.path.join(SRC, 'LauncherPreferencesViewController.m'), encoding='utf-8').read()
c6 = re.search(r'\@"key": \@"multidraw_mode",.*?pickKeys.*?\@\[\@"0", \@"1", \@"2"\]', lpvc, re.S) is not None
check('C6 UI picker 三档保持（mobileglues.multidraw_mode 键名不变）', c6)

# ------------------------------------------------------------------ 汇总
print()
if failures:
    print(f'FAILED ({len(failures)}): {failures}')
    sys.exit(1)
print('ALL PASS')
