// ============================================================================
// Task 166（Amethyst）：MobileGL DirectVulkan 后端的 Metal 层 FSR1
// （EASU 放大 + RCAS 锐化，双 CAMetalLayer 交换层拦截方案）。
//
// 用户指令定案（2026-09-25）：GLES / OpenGL 4.0 后端在加载区块时卡顿无解，
// 唯一流畅的 Vulkan 后端【必须】支持 FSR——"vulkan必须支持fsr"。
//
// ── 为什么是 Metal 层拦截 ──────────────────────────────────────────────────
// 上游事实链（本 Task 全新取证，推翻 Task154/164 的"上游硬限制"结论的一部分）：
//   * MobileGL（github.com/MobileGL-Dev/MobileGL，LGPL-2.1，开源）是
//     libMobileGL.dylib 的源头；其源码/文档/二进制三方一致：【没有】内置
//     FSR（配置面仅 MOBILEGL_* 环境变量：backend/quirk/framesInFlight 类）。
//     "零 FSR 符号"取证成立，但"不可能"不成立——闭源结论被开源事实替代。
//   * Task148 曾误判"libMobileGL 是 MobileGlues-cpp 共体构建、fsr1Setting
//     令内置 FSR1 生效"——上游 MobileGL 源码里根本没有 ApplyFSR/
//     FSR1_Context/egl.cpp 前端；当时的 fb0 附件探测非零是 MobileGL 把默认
//     帧缓冲实现为内部 FBO 的正常形态，不是 FSR1 重定向。
//   * 历史 mgl_fsr.mm（Task119-154）的"预交换几何战争"根因是伪 EGL 无
//     current 跟踪导致启动器信念几何与渲染器后缓冲失配 + 输入除法失配
//     （7c32bc3 病历），不是"FSR 在 Vulkan 上不可能"。
//
// 本方案完全绕开那场战争的战场（不在 GL/EGL 层画任何东西）：
//   Layer A（视图真层，GameSurfaceView 的 CAMetalLayer）
//     · drawableSize 保持全表面（updateSavedResolution 单一写者，不变）；
//     · 只服务【我们】的 EASU/RCAS 输出——上屏目标。
//   Layer B（本模块私有的 CAMetalLayer 子类，不在视图树里）
//     · 以 renderW x renderH 的 EGL_WIDTH/HEIGHT attribs + 本层作为
//       native window 交给 MobileGL 伪 EGL -> vkCreateMetalSurfaceEXT ->
//       MoltenVK swapchain（MoltenVK 1.2.9 源码实证：surface 尺寸来自
//       swapchain imageExtent，而 MobileGL 的 eglCreateWindowSurface 不从
//       CALayer 推断尺寸、只认显式 attribs——gl_bridge.m L1625 既有事实）；
//     · 重写 nextDrawable：返回【包装 drawable】（自有 MTLTexture 环），
//       MoltenVK 的 MVKPresentableSwapchainImage 以 id<CAMetalDrawable>
//       协议类型持有并 retain（MVKImage.mm:502/1522），present 走
//       [drawable present]/presentAtTime:（MVKImage.mm:1564-1566）——全部
//       经 ObjC 动态派发进入包装器，MobileGL/MoltenVK 二进制零改动。
//   包装 drawable 的 present：
//     src(环纹理, render-res, MoltenVK 已渲好 MC 帧)
//       -> EASU(Metal, AMD FSR1 32-bit 逐字移植)
//       -> [RCAS 可选, AMETHYST_FSR_RCAS_SHARPNESS, 负值=关]
//       -> Layer A 真 drawable -> present -> CoreAnimation 上屏。
//
// ── 与既有机制的联动（零新事实源）─────────────────────────────────────────
//   * MC 窗口信念：ame83_fsr_capable_renderer 重新纳入 libMobileGL.dylib
//     （SurfaceViewController.m，Task166 修订）-> mgFsrScale = 预设档位 ->
//     windowWidth = surface/fsr_scale（渲染分辨率）-> nativeSendScreenSize
//     + SDL/GLFW 桩三路同值上报 -> MC viewport = render-res，与 EGL 表面
//     （attribs=render-res）天然相等：Task78 豁免比较 viewport vs surface，
//     两者恒等 -> 零失配，geo-heal 链路天然静止。
//   * ame48_swap_geometry_guard 比较的是 EGL surface vs【记录的创建层】：
//     gl_bridge 改为记录 Layer B（drawableSize=render-res）-> 恒等，静止。
//   * 输入：sendTouchPoint 的 screenScale /= mgFsrScale（既有，系数驱动），
//     与缩窗同步恢复，无 Task154 病历里的"除法失配"形态。
//   * Task154 退休门（mgl_fsr.mm 的预交换链）维持 return false——那条链
//     不复活；本模块是【呈现端】拦截，与其零交集。
//
// ── 安全边界 ──────────────────────────────────────────────────────────────
//   * 门控：仅 libMobileGL.dylib（mg 的 Vulkan 后端，DirectVulkan）。
//     libMobileGL-gles / MobileGlues / zink / Mithril 不受任何影响
//     （MobileGlues 的内置 FSR1 与 zink 的 osm_bridge EASU 原样保留）。
//   * 任何初始化失败（Metal 库编译/层创建/设备缺失）-> acquire_layer 返回
//     nil -> gl_bridge 回退旧路径（视图层直连 + 全分辨率 attribs，
//     da5918a 逐位语义）。present 期失败 -> 丢帧 + 限频日志，绝不崩溃。
//   * 环境开关：AME166_MGL_METAL_FSR=0 强制关闭（装机诊断用）。
//   * 帧同步：依赖 Metal 默认的设备级资源 hazard tracking（MoltenVK 自身
//     对其跨队列镜像同样依赖此机制）；包装 present 在 MoltenVK 的队列提交
//     线程上同步执行，先提交 EASU 命令缓冲再 present 真 drawable，呈现序
//     由 Metal 按 texture 依赖自动排列。
//   * MoltenVK 侧图像可用性信令：包装实现 addPresentedHandler:（缓冲后
//     转发给真 drawable），presented-time 反馈链完整；若真 drawable 不支持
//     则立即回调（MoltenVK 有 respondsToSelector 兜底分支）。
// ============================================================================

#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#import <os/lock.h>
#import <dlfcn.h>
#import <stdlib.h>
#import <string.h>
#import <math.h>

#include "mgl_metal_fsr.h"
#include "../environ.h"
#include "../utils.h"

// ============================================================================
// Metal Shading Language 源（AMD FidelityFX-FSR 1.20210629 32-bit 逐字移植）
//
// 移植口径（与 osm_bridge / MobileGlues FSR1.cpp 的 GLSL 版本同源同款）：
//   * ffx_a.h 32-bit 辅助函数的精确位技巧常量：
//     APrxLoRcpF1  = 0x7ef07ebb 取负指数位；
//     APrxMedRcpF1 = 0x7ef19fff + 一轮牛顿；
//     APrxLoRsqF1  = 0x5f347d74 - (bits >> 1)（快速平方根倒数）。
//   * EASU：12-tap 各向异性核 + 方向/长度估计（4 组十字）+ min/max 夹持。
//     GLSL 原版用 gather4 打包 4 texel；Metal 版改为显式 .read() 12 命名
//     tap（b,c,e,f,g,h,i,j,k,l,n,o——与 AMD 注释图逐位对应），数值等价、
//     无 gather 顺序约定差异风险。
//   * 越界读防御（Task164 教训口径）：MTLTexture.read() 越界是未定义行为
//     （ANGLE Metal 同款），所有 tap 在 shader 内 clamp 到 [0, size-1]。
//   * RCAS：5-tap（b,d,e,f,h）+ stops 语义锐化；GLSL 版的 packHalf2x16
//     con[1] 依赖在 Metal 上不需要（uniform 直接传 float）。alpha 从中心
//     像素原样透传（osm_bridge 哨兵链语义在本路径无消费者，保持同构）。
//   * gl_FragCoord.xy 是像素中心（x+0.5）；AMD 的 ip 参数是整数像素位。
//     MSL 侧 uint2(in.pos.xy) 截断 0.5 后与 GLSL 的 AU2(gl_FragCoord.xy)
//     语义一致（FSR1.cpp 同款入口）。
// ============================================================================
static NSString *const kAme166EasuMSL = @R"ame166_msl(
#include <metal_stdlib>
using namespace metal;

struct Ame166V2F { float4 pos [[position]]; };

vertex Ame166V2F ame166_vs(uint vid [[vertex_id]]) {
    float2 uv = float2(float((vid << 1u) & 2u), float(vid & 2u));
    Ame166V2F o;
    o.pos = float4(uv * 2.0 - 1.0, 0.0, 1.0);
    return o;
}

static inline float ame166_loRcp(float a) {
    return as_type<float>(0x7ef07ebbu - as_type<uint>(a));
}
static inline float ame166_medRcp(float a) {
    float b = as_type<float>(0x7ef19fffu - as_type<uint>(a));
    return b * (-b * a + 2.0);
}
static inline float ame166_loRsq(float a) {
    return as_type<float>(0x5f347d74u - (as_type<uint>(a) >> 1u));
}
static inline float3 ame166_load(texture2d<float> tex, int2 p, int2 sz) {
    p = clamp(p, int2(0), sz - 1);
    return tex.read(uint2(p)).rgb;
}
static inline float ame166_luma(float3 c) { return c.b * 0.5 + (c.r * 0.5 + c.g); }

static inline void ame166_setF(thread float2 &dir, thread float &len, float2 pp,
                               bool s, bool t, bool u, bool v,
                               float lA, float lB2, float lC, float lD, float lE) {
    float w = 0.0;
    if (s) w = (1.0 - pp.x) * (1.0 - pp.y);
    if (t) w =        pp.x * (1.0 - pp.y);
    if (u) w = (1.0 - pp.x) *        pp.y ;
    if (v) w =        pp.x *        pp.y ;
    float dc = lD - lC;
    float cb = lC - lB2;
    float lenX = max(abs(dc), abs(cb));
    lenX = ame166_loRcp(lenX);
    float dirX = lD - lB2;
    dir.x += dirX * w;
    lenX = saturate(abs(dirX) * lenX);
    lenX *= lenX;
    len += lenX * w;
    float ec = lE - lC;
    float ca = lC - lA;
    float lenY = max(abs(ec), abs(ca));
    lenY = ame166_loRcp(lenY);
    float dirY = lE - lA;
    dir.y += dirY * w;
    lenY = saturate(abs(dirY) * lenY);
    lenY *= lenY;
    len += lenY * w;
}

static inline void ame166_tap(thread float3 &aC, thread float &aW, float2 off,
                              float2 dir, float2 len2, float lob, float clp, float3 c) {
    float2 v;
    v.x = (off.x * dir.x) + (off.y * dir.y);
    v.y = (off.x * (-dir.y)) + (off.y * dir.x);
    v *= len2;
    float d2 = v.x * v.x + v.y * v.y;
    d2 = min(d2, clp);
    float wB = 2.0 / 5.0 * d2 - 1.0;
    float wA = lob * d2 - 1.0;
    wB *= wB;
    wA *= wA;
    wB = 25.0 / 16.0 * wB - (25.0 / 16.0 - 1.0);
    float w = wB * wA;
    aC += c * w;
    aW += w;
}

fragment float4 ame166_easu_fs(Ame166V2F in [[stage_in]],
                               texture2d<float> srcTex [[texture(0)]],
                               constant float4 &con0 [[buffer(0)]],
                               constant int2 &srcSize [[buffer(1)]]) {
    uint2 ip = uint2(in.pos.xy);
    float2 pp = float2(ip) * con0.xy + con0.zw;
    float2 fp = floor(pp);
    pp -= fp;
    int2 b = int2(fp);
    int2 S = srcSize;

    float3 t_b = ame166_load(srcTex, b + int2( 0, -1), S);
    float3 t_c = ame166_load(srcTex, b + int2( 1, -1), S);
    float3 t_e = ame166_load(srcTex, b + int2(-1,  0), S);
    float3 t_f = ame166_load(srcTex, b + int2( 0,  0), S);
    float3 t_g = ame166_load(srcTex, b + int2( 1,  0), S);
    float3 t_h = ame166_load(srcTex, b + int2( 2,  0), S);
    float3 t_i = ame166_load(srcTex, b + int2(-1,  1), S);
    float3 t_j = ame166_load(srcTex, b + int2( 0,  1), S);
    float3 t_k = ame166_load(srcTex, b + int2( 1,  1), S);
    float3 t_l = ame166_load(srcTex, b + int2( 2,  1), S);
    float3 t_n = ame166_load(srcTex, b + int2( 0,  2), S);
    float3 t_o = ame166_load(srcTex, b + int2( 1,  2), S);

    float lB = ame166_luma(t_b); float lC = ame166_luma(t_c);
    float lE = ame166_luma(t_e); float lF = ame166_luma(t_f);
    float lG = ame166_luma(t_g); float lH = ame166_luma(t_h);
    float lI = ame166_luma(t_i); float lJ = ame166_luma(t_j);
    float lK = ame166_luma(t_k); float lL = ame166_luma(t_l);
    float lN = ame166_luma(t_n); float lO = ame166_luma(t_o);

    float2 dir = float2(0.0);
    float len = 0.0;
    ame166_setF(dir, len, pp, true , false, false, false, lB, lE, lF, lG, lJ);
    ame166_setF(dir, len, pp, false, true , false, false, lC, lF, lG, lH, lK);
    ame166_setF(dir, len, pp, false, false, true , false, lF, lI, lJ, lK, lN);
    ame166_setF(dir, len, pp, false, false, false, true , lG, lJ, lK, lL, lO);

    float2 dir2 = dir * dir;
    float dirR = dir2.x + dir2.y;
    bool zro = dirR < (1.0 / 32768.0);
    dirR = ame166_loRsq(dirR);
    dirR = zro ? 1.0 : dirR;
    dir.x = zro ? 1.0 : dir.x;
    dir *= dirR;
    len *= 0.5;
    len *= len;
    float stretch = (dir.x * dir.x + dir.y * dir.y) * ame166_loRcp(max(abs(dir.x), abs(dir.y)));
    float2 len2 = float2(1.0 + (stretch - 1.0) * len, 1.0 + (-0.5) * len);
    float lob = 0.5 + (0.25 - 0.04 - 0.5) * len;
    float clp = ame166_loRcp(lob);

    float3 min4 = min(min(min(t_f, t_g), t_j), t_k);
    float3 max4 = max(max(max(t_f, t_g), t_j), t_k);

    float3 aC = float3(0.0);
    float aW = 0.0;
    ame166_tap(aC, aW, float2( 0.0, -1.0) - pp, dir, len2, lob, clp, t_b);
    ame166_tap(aC, aW, float2( 1.0, -1.0) - pp, dir, len2, lob, clp, t_c);
    ame166_tap(aC, aW, float2(-1.0,  1.0) - pp, dir, len2, lob, clp, t_i);
    ame166_tap(aC, aW, float2( 0.0,  1.0) - pp, dir, len2, lob, clp, t_j);
    ame166_tap(aC, aW, float2( 0.0,  0.0) - pp, dir, len2, lob, clp, t_f);
    ame166_tap(aC, aW, float2(-1.0,  0.0) - pp, dir, len2, lob, clp, t_e);
    ame166_tap(aC, aW, float2( 1.0,  0.0) - pp, dir, len2, lob, clp, t_g);
    ame166_tap(aC, aW, float2( 2.0,  0.0) - pp, dir, len2, lob, clp, t_h);
    ame166_tap(aC, aW, float2( 1.0,  1.0) - pp, dir, len2, lob, clp, t_k);
    ame166_tap(aC, aW, float2( 2.0,  1.0) - pp, dir, len2, lob, clp, t_l);
    ame166_tap(aC, aW, float2( 0.0,  2.0) - pp, dir, len2, lob, clp, t_n);
    ame166_tap(aC, aW, float2( 1.0,  2.0) - pp, dir, len2, lob, clp, t_o);

    float3 pix = aC * ame166_medRcp(aW);
    pix = clamp(pix, min4, max4);
    return float4(pix, 1.0);
}
)ame166_msl";

static NSString *const kAme166RcasMSL = @R"ame166_msl(
#include <metal_stdlib>
using namespace metal;

struct Ame166V2F { float4 pos [[position]]; };

vertex Ame166V2F ame166_vs(uint vid [[vertex_id]]) {
    float2 uv = float2(float((vid << 1u) & 2u), float(vid & 2u));
    Ame166V2F o;
    o.pos = float4(uv * 2.0 - 1.0, 0.0, 1.0);
    return o;
}

static inline float ame166_medRcp(float a) {
    float b = as_type<float>(0x7ef19fffu - as_type<uint>(a));
    return b * (-b * a + 2.0);
}
static inline float4 ame166_load4(texture2d<float> tex, int2 p, int2 sz) {
    p = clamp(p, int2(0), sz - 1);
    return tex.read(uint2(p));
}

fragment float4 ame166_rcas_fs(Ame166V2F in [[stage_in]],
                               texture2d<float> srcTex [[texture(0)]],
                               constant float &sharp [[buffer(0)]],
                               constant int2 &srcSize [[buffer(1)]]) {
    constexpr float kAme166RcasLimit = 0.25 - (1.0 / 16.0);
    int2 sp = int2(uint2(in.pos.xy));
    int2 S = srcSize;

    float3 b = ame166_load4(srcTex, sp + int2( 0, -1), S).rgb;
    float3 d = ame166_load4(srcTex, sp + int2(-1,  0), S).rgb;
    float4 e4 = ame166_load4(srcTex, sp, S);
    float3 e = e4.rgb;
    float3 f = ame166_load4(srcTex, sp + int2( 1,  0), S).rgb;
    float3 h = ame166_load4(srcTex, sp + int2( 0,  1), S).rgb;

    float3 mn4 = min(min(min(b, d), f), h);
    float3 mx4 = max(max(max(b, d), f), h);

    // AMD FsrRcasF 32-bit（FSR_RCAS_DENOISE 未定义，nz 计算被死代码消除）。
    float3 hitMin = min(mn4, e) * (1.0 / (4.0 * mx4));
    float3 hitMax = (1.0 - max(mx4, e)) * (1.0 / (4.0 * mn4 - 4.0));
    float3 lobe3 = max(-hitMin, hitMax);
    float lobeMax = max(max(lobe3.r, lobe3.g), lobe3.b);
    lobeMax = min(lobeMax, 0.0);
    lobeMax = max(-kAme166RcasLimit, lobeMax);
    float lobe = lobeMax * sharp;
    float rcpL = ame166_medRcp(4.0 * lobe + 1.0);
    float3 pix = (lobe * (b + d + h + f) + e) * rcpL;
    // alpha 透传（与 FSRRCASSource.h 同构）：RGB 走锐化，alpha 中心原样。
    return float4(pix, e4.a);
}
)ame166_msl";

// ============================================================================
// 模块状态
// ============================================================================
static os_unfair_lock s_ame166_lock = OS_UNFAIR_LOCK_INIT;

static CAMetalLayer *s_ame166_layerA = nil;          // 视图真层（上屏目标）
static __kindof CAMetalLayer *s_ame166_layerB = nil; // 私有交换层（FSR 层）
static id<MTLDevice> s_ame166_device = nil;
static id<MTLCommandQueue> s_ame166_queue = nil;
static id<MTLRenderPipelineState> s_ame166_easuPSO = nil;
static id<MTLRenderPipelineState> s_ame166_rcasPSO = nil;
static id<MTLLibrary> s_ame166_libEasu = nil;
static id<MTLLibrary> s_ame166_libRcas = nil;
static id<MTLTexture> s_ame166_intermediate = nil;   // RCAS 中转（目标分辨率）
static MTLPixelFormat s_ame166_targetFmt = MTLPixelFormatInvalid;

static int s_ame166_renderW = 0, s_ame166_renderH = 0; // 交换链（渲染）分辨率
static bool s_ame166_active = false;
static bool s_ame166_rcasOn = true;
static float s_ame166_rcasConX = 0.0f;   // exp2(-stops)（AMD FsrRcasCon 产物）
static long s_ame166_frames = 0;
static long s_ame166_dropped = 0;
static long s_ame166_ringWaitTimeouts = 0;

// 环形纹理池：8 槽 >> MoltenVK imageCount（maximumDrawableCount=3 + MobileGL
// framesInFlight 默认 3），槽位复用距离远大于单帧 EASU 时长（<1ms）。
static const int kAme166RingSlots = 8;
static id<MTLTexture> s_ame166_ring[kAme166RingSlots];
static dispatch_semaphore_t s_ame166_ringSem[kAme166RingSlots];
static int s_ame166_ringNext = 0;

// ============================================================================
// Ame166Drawable：CAMetalDrawable 协议包装器。
//
// MoltenVK 1.2.9 的全部消费面（MVKImage.h:494/502, MVKImage.mm:1512-1627）：
//   .texture（渲染目标，pixelFormat 必须非零）、.layer、[present]、
//   [presentAtTime:]、[addPresentedHandler:]（respondsToSelector 守卫）、
//   其余 MTLDrawable 方法为可选路径（presentAfterMinimumDuration /
//   presentedTime / waitUntilPresented / addScheduledHandler）。
// present 家族在此截获：EASU(+RCAS) -> Layer A 真 drawable -> 上屏。
// ============================================================================
@interface Ame166Drawable : NSObject <CAMetalDrawable> {
 @package
    CAMetalLayer *_fsrLayer; // Layer B（ARC 强持有：teardown 与在速 drawable 生命周期安全）
    id<MTLTexture> _texture;                      // 本槽位纹理（强持有，环内共享）
    int _slot;
    NSMutableArray *_presentedHandlers; // present 前注册的回调，present 时转发
    NSMutableArray *_scheduledHandlers;
    id<CAMetalDrawable> _realDrawable; // present 后有效（转发 presentedTime）
}
@end

@implementation Ame166Drawable

- (id)initWithLayer:(CAMetalLayer *)layer texture:(id<MTLTexture>)texture slot:(int)slot {
    self = [super init];
    if (self) {
        _fsrLayer = layer;
        _texture = texture;
        _slot = slot;
        _presentedHandlers = [NSMutableArray array];
        _scheduledHandlers = [NSMutableArray array];
    }
    return self;
}

- (id<MTLTexture>)texture { return _texture; }
- (CAMetalLayer *)layer { return _fsrLayer; }
- (NSTimeInterval)presentedTime { return _realDrawable != nil ? _realDrawable.presentedTime : 0.0; }

- (void)addPresentedHandler:(void (^)(id<MTLDrawable>))block {
    if (_realDrawable != nil && [_realDrawable respondsToSelector:@selector(addPresentedHandler:)]) {
        [(id)_realDrawable addPresentedHandler:block];
    } else {
        [_presentedHandlers addObject:[block copy]];
    }
}

- (void)addScheduledHandler:(void (^)(id<MTLDrawable>))block {
    [_scheduledHandlers addObject:[block copy]];
}

- (void)waitUntilPresented { /* MoltenVK 1.2.9 不走此路径；真等待由 presented 回调链承担 */ }

// ============================================================================
// present 核心：Task166 Metal FSR 上采样 + 真 drawable 呈现。
// 在 MoltenVK 的队列提交线程上同步执行（vkQueuePresentKHR -> presentCAMetalDrawable）。
// ============================================================================
- (void)ame166_presentWithTime:(double)atTime duration:(double)minDuration {
    @autoreleasepool {
        id<MTLCommandQueue> queue = nil;
        id<MTLRenderPipelineState> easuPSO = nil, rcasPSO = nil;
        id<MTLTexture> intermediate = nil;
        id<CAMetalDrawable> real = nil;
        CAMetalLayer *layerA = nil;
        float rcasConX = 0.0f;
        bool rcasOn = false;

        os_unfair_lock_lock(&s_ame166_lock);
        queue = s_ame166_queue;
        easuPSO = s_ame166_easuPSO;
        rcasPSO = s_ame166_rcasPSO;
        intermediate = s_ame166_intermediate;
        layerA = s_ame166_layerA;
        rcasConX = s_ame166_rcasConX;
        rcasOn = s_ame166_rcasOn;
        os_unfair_lock_unlock(&s_ame166_lock);

        if (queue == nil || easuPSO == nil || layerA == nil) {
            s_ame166_dropped++;
            if (s_ame166_dropped == 1 || s_ame166_dropped % 600 == 0) {
                NSLog(@"[MGLFSR] Task166 present dropped (pipeline unavailable): dropped=%ld", s_ame166_dropped);
            }
            [self ame166_fireHandlersOnReal:nil];
            return;
        }

        real = [layerA nextDrawable];
        if (real == nil || real.texture == nil) {
            s_ame166_dropped++;
            if (s_ame166_dropped == 1 || s_ame166_dropped % 600 == 0) {
                NSLog(@"[MGLFSR] Task166 present dropped (Layer A nextDrawable nil): dropped=%ld", s_ame166_dropped);
            }
            [self ame166_fireHandlersOnReal:nil];
            return;
        }
        _realDrawable = real;

        // 自描述几何：源 = 环纹理（render-res），目标 = 真 drawable（surface）。
        const int inW = (int)_texture.width;
        const int inH = (int)_texture.height;
        const int outW = (int)real.texture.width;
        const int outH = (int)real.texture.height;
        if (inW <= 0 || inH <= 0 || outW < inW || outH < inH) {
            s_ame166_dropped++;
            if (s_ame166_dropped == 1 || s_ame166_dropped % 600 == 0) {
                NSLog(@"[MGLFSR] Task166 present dropped (geometry: %dx%d -> %dx%d): dropped=%ld",
                      inW, inH, outW, outH, s_ame166_dropped);
            }
            [self ame166_fireHandlersOnReal:nil];
            return;
        }

        // 中转纹理随真 drawable 尺寸/格式自适应（旋转/分辨率变更后的首帧重建）。
        if (rcasOn) {
            bool needRebuild = (intermediate == nil ||
                                (int)intermediate.width != outW ||
                                (int)intermediate.height != outH ||
                                intermediate.pixelFormat != real.texture.pixelFormat);
            if (needRebuild) {
                MTLTextureDescriptor *desc = [[MTLTextureDescriptor alloc] init];
                desc.textureType = MTLTextureType2D;
                desc.pixelFormat = real.texture.pixelFormat;
                desc.width = (NSUInteger)outW;
                desc.height = (NSUInteger)outH;
                desc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
                desc.storageMode = MTLStorageModePrivate;
                intermediate = [s_ame166_device newTextureWithDescriptor:desc];
                os_unfair_lock_lock(&s_ame166_lock);
                s_ame166_intermediate = intermediate;
                os_unfair_lock_unlock(&s_ame166_lock);
                if (intermediate == nil) {
                    // 中转建不出来：退化为 EASU 单趟直画真 drawable（Task83 语义）。
                    rcasOn = false;
                    NSLog(@"[MGLFSR] Task166 intermediate alloc failed -- falling back to EASU-only this frame");
                }
            }
        }

        // FsrEasuCon（32-bit，CPU 侧）：inputViewport==inputResource==render，
        // output=surface。con0 = (inW/outW, inH/outH, 0.5*inW/outW-0.5, 0.5*inH/outH-0.5)。
        const float con0[4] = {
            (float)inW / (float)outW,
            (float)inH / (float)outH,
            0.5f * (float)inW / (float)outW - 0.5f,
            0.5f * (float)inH / (float)outH - 0.5f
        };
        const int srcSize[2] = { inW, inH };
        const float sharpVal = rcasConX;

        id<MTLCommandBuffer> cmd = [queue commandBuffer];
        if (cmd == nil) {
            s_ame166_dropped++;
            [self ame166_fireHandlersOnReal:nil];
            return;
        }

        id<MTLTexture> dst1 = (rcasOn && intermediate != nil) ? intermediate : real.texture;
        MTLRenderPassDescriptor *rp1 = [MTLRenderPassDescriptor renderPassDescriptor];
        rp1.colorAttachments[0].texture = dst1;
        rp1.colorAttachments[0].loadAction = MTLLoadActionDontCare;
        rp1.colorAttachments[0].storeAction = MTLStoreActionStore;
        id<MTLRenderCommandEncoder> enc1 = [cmd renderCommandEncoderWithDescriptor:rp1];
        [enc1 setRenderPipelineState:easuPSO];
        [enc1 setViewport:(MTLViewport){ 0.0, 0.0, (double)dst1.width, (double)dst1.height, 0.0, 1.0 }];
        [enc1 setFragmentTexture:_texture atIndex:0];
        [enc1 setFragmentBytes:con0 length:sizeof(con0) atIndex:0];
        [enc1 setFragmentBytes:srcSize length:sizeof(srcSize) atIndex:1];
        [enc1 drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
        [enc1 endEncoding];

        if (rcasOn && intermediate != nil && rcasPSO != nil) {
            MTLRenderPassDescriptor *rp2 = [MTLRenderPassDescriptor renderPassDescriptor];
            rp2.colorAttachments[0].texture = real.texture;
            rp2.colorAttachments[0].loadAction = MTLLoadActionDontCare;
            rp2.colorAttachments[0].storeAction = MTLStoreActionStore;
            id<MTLRenderCommandEncoder> enc2 = [cmd renderCommandEncoderWithDescriptor:rp2];
            [enc2 setRenderPipelineState:rcasPSO];
            [enc2 setViewport:(MTLViewport){ 0.0, 0.0, (double)outW, (double)outH, 0.0, 1.0 }];
            [enc2 setFragmentTexture:intermediate atIndex:0];
            [enc2 setFragmentBytes:&sharpVal length:sizeof(sharpVal) atIndex:0];
            const int rcasSrc[2] = { outW, outH };
            [enc2 setFragmentBytes:rcasSrc length:sizeof(rcasSrc) atIndex:1];
            [enc2 drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
            [enc2 endEncoding];
        }

        // 本槽位读侧完成即可复用（Metal 设备级 hazard tracking 保证 MoltenVK
        // 写入与本读取的先后序）。
        dispatch_semaphore_t slotSem = s_ame166_ringSem[_slot];
        [cmd addCompletedHandler:^(__unused id<MTLCommandBuffer> cb) {
            dispatch_semaphore_signal(slotSem);
        }];

        for (void (^blk)(id<MTLDrawable>) in _scheduledHandlers) {
            blk(self);
        }
        [_scheduledHandlers removeAllObjects];

        [cmd commit];

        if (minDuration > 0.0 && [real respondsToSelector:@selector(presentAfterMinimumDuration:)]) {
            [real presentAfterMinimumDuration:minDuration];
        } else if (atTime > 0.0) {
            [real presentAtTime:atTime];
        } else {
            [real present];
        }
        [self ame166_fireHandlersOnReal:real];

        s_ame166_frames++;
        if (s_ame166_frames == 1) {
            NSLog(@"[MGLFSR] Task166 first frame presented: EASU %dx%d -> %dx%d -> %@ -> display layer (Metal direct)",
                  inW, inH, outW, outH,
                  (rcasOn && intermediate != nil && rcasPSO != nil) ? @"RCAS" : @"direct");
        } else if (s_ame166_frames == 600) {
            NSLog(@"[MGLFSR] Task166 steady: 600 frames upscaled (dropped=%ld ringWaitTimeouts=%ld)",
                  s_ame166_dropped, s_ame166_ringWaitTimeouts);
        }
    }
}

- (void)ame166_fireHandlersOnReal:(id<CAMetalDrawable>)real {
    if (real != nil && [real respondsToSelector:@selector(addPresentedHandler:)]) {
        for (void (^blk)(id<MTLDrawable>) in _presentedHandlers) {
            [(id)real addPresentedHandler:blk];
        }
    } else {
        // 无真 drawable（丢帧路径）：立即回调，MoltenVK 的图像可用性信令不被卡死。
        for (void (^blk)(id<MTLDrawable>) in _presentedHandlers) {
            blk(self);
        }
    }
    [_presentedHandlers removeAllObjects];
}

- (void)present { [self ame166_presentWithTime:0.0 duration:0.0]; }
- (void)presentAtTime:(double)presentationTime { [self ame166_presentWithTime:presentationTime duration:0.0]; }
- (void)presentAfterMinimumDuration:(double)duration { [self ame166_presentWithTime:0.0 duration:duration]; }

@end

// ============================================================================
// Ame166SwapchainLayer：私有交换层（Layer B）。
// nextDrawable 永不调用 super（Layer B 自身的 drawable 池零消耗）；返回
// 环形槽位包装器。MoltenVK 在 swapchain 创建时会写 pixelFormat/drawableSize
// —— 两者均被读取为本层的纹理分配参数，天然一致。
//
// Task 167（崩溃根因补丁）：MoltenVK 的表面尺寸真源不足 drawableSize，
// 而是 CAMetalLayer+MoltenVK 分类的 naturalDrawableSizeMVK = bounds ×
// contentsScale（MVKSurface::getNaturalExtent -> MVKDevice 表面能力
// currentExtent）。Task166 只写了 drawableSize，bounds 保持 CGRectZero
// -> currentExtent={0,0} -> MobileGL RecreateSwapchain 的 zero-area 守卫
// 直接返回（不建 swapchain）-> m_images 空 + 首次 acquire 被推迟
// -> MC 启用 DSA 后第一个 glBlitNamedFramebuffer(fb0) 走
// ResolveColorBlitBinding -> SwapchainObject::GetImage(0) -> 空向量
// data()=nullptr 解引用 = SIGSEGV（装机 1b76d19 实测：崩溃 pc 恰为
// GetImage+0x28 的 ldr x0,[x0]，反汇编逐字节比对吻合）。修复：
// bounds 与 drawableSize 同源同写（contentsScale 钉 1.0，乘法无精度损失），
// 三个几何写入点（新建/已存在同步/update_size 钩子）全部成对更新。
// ============================================================================
@interface Ame166SwapchainLayer : CAMetalLayer
@end

@implementation Ame166SwapchainLayer

- (nullable id<CAMetalDrawable>)nextDrawable {
    if (!s_ame166_active) {
        return nil;
    }
    os_unfair_lock_lock(&s_ame166_lock);
    int slot = s_ame166_ringNext % kAme166RingSlots;
    s_ame166_ringNext++;

    NSUInteger w = (NSUInteger)MAX(1.0, round(self.drawableSize.width));
    NSUInteger h = (NSUInteger)MAX(1.0, round(self.drawableSize.height));
    MTLPixelFormat fmt = self.pixelFormat;
    if (fmt == MTLPixelFormatInvalid) {
        fmt = MTLPixelFormatBGRA8Unorm; // MoltenVK 尚未写入时的兜底（正常时序不会走到）
    }
    id<MTLTexture> tex = s_ame166_ring[slot];
    if (tex == nil || tex.width != w || tex.height != h || tex.pixelFormat != fmt) {
        MTLTextureDescriptor *desc = [[MTLTextureDescriptor alloc] init];
        desc.textureType = MTLTextureType2D;
        desc.pixelFormat = fmt;
        desc.width = w;
        desc.height = h;
        desc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        desc.storageMode = MTLStorageModePrivate;
        tex = [s_ame166_device newTextureWithDescriptor:desc];
        s_ame166_ring[slot] = tex;
        s_ame166_ringSem[slot] = dispatch_semaphore_create(1); // 许可语义：新建即可用；nextDrawable 消耗，EASU 完成归还（初值 0 会让首取空等超时）
    }
    dispatch_semaphore_t slotSem = s_ame166_ringSem[slot];
    os_unfair_lock_unlock(&s_ame166_lock);

    if (tex == nil) {
        NSLog(@"[MGLFSR] Task166 ring texture alloc failed (slot=%d %lux%lu)", slot, (unsigned long)w, (unsigned long)h);
        return nil;
    }

    // 防御：槽位仍被上一帧的 EASU 读着（环深 8 >> imageCount 3，正常永不触发）。
    if (slotSem != NULL && dispatch_semaphore_wait(slotSem, dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC)) != 0) {
        s_ame166_ringWaitTimeouts++;
        if (s_ame166_ringWaitTimeouts == 1 || s_ame166_ringWaitTimeouts % 600 == 0) {
            NSLog(@"[MGLFSR] Task166 ring slot %d still in flight after 250ms (proceeding; count=%ld)",
                  slot, s_ame166_ringWaitTimeouts);
        }
    }

    return [[Ame166Drawable alloc] initWithLayer:self texture:tex slot:slot];
}

@end

// ============================================================================
// 对外 API
// ============================================================================

bool ame166_metal_fsr_should_engage(const char *renderer) {
    // 门控四重：mg 的 Vulkan 后端（DirectVulkan，严格匹配 libMobileGL.dylib，
    // 排除 -gles 变体）+ FSR 联动几何在场（windowWidth < ame_surfaceWidth，
    // 即 ame83 能力表已按预设档位缩窗）+ 表面初始化完成 + 环境开关未关。
    if (renderer == NULL || strcmp(renderer, RENDERER_NAME_MOBILEGL) != 0) return false;
    const char *killSwitch = getenv("AME166_MGL_METAL_FSR");
    if (killSwitch != NULL && strcmp(killSwitch, "0") == 0) return false;
    if (windowWidth <= 0 || windowHeight <= 0) return false;
    if (ame_surfaceWidth <= 0 || ame_surfaceHeight <= 0) return false;
    return (windowWidth < ame_surfaceWidth) && (windowHeight < ame_surfaceHeight);
}

CAMetalLayer *ame166_metal_fsr_acquire_layer(CAMetalLayer *viewLayer, int renderW, int renderH) {
    if (viewLayer == nil || renderW <= 0 || renderH <= 0) return nil;

    @autoreleasepool {
        os_unfair_lock_lock(&s_ame166_lock);
        if (s_ame166_layerB != nil) {
            // 已存在（同会话二次建 surface / 旋转重建）：仅同步几何。
            // Task 167：bounds 必须与 drawableSize 成对写（naturalDrawableSizeMVK
            // 是 MoltenVK 的 currentExtent 真源，见类注释）。
            s_ame166_layerB.drawableSize = CGSizeMake(renderW, renderH);
            s_ame166_layerB.bounds = CGRectMake(0.0, 0.0, renderW, renderH);
            s_ame166_renderW = renderW;
            s_ame166_renderH = renderH;
            os_unfair_lock_unlock(&s_ame166_lock);
            return s_ame166_layerB;
        }
        os_unfair_lock_unlock(&s_ame166_lock);

        // ── 初始化链：设备 -> 层 -> 管线。任何一步失败 = 回退旧路径 ──
        id<MTLDevice> device = viewLayer.device;
        if (device == nil) {
            device = MTLCreateSystemDefaultDevice();
            if (device != nil) viewLayer.device = device; // 同设备钉扎（跨层纹理共享前提）
        }
        if (device == nil) {
            NSLog(@"[MGLFSR] Task166 fallback: no MTLDevice (Metal unavailable) -- full-res direct present");
            return nil;
        }

        NSError *err = nil;
        id<MTLLibrary> libEasu = [device newLibraryWithSource:kAme166EasuMSL options:nil error:&err];
        if (libEasu == nil) {
            NSLog(@"[MGLFSR] Task166 fallback: EASU library compile failed: %@",
                  err.localizedDescription ?: @"(no error)");
            return nil;
        }
        id<MTLLibrary> libRcas = [device newLibraryWithSource:kAme166RcasMSL options:nil error:&err];
        if (libRcas == nil) {
            NSLog(@"[MGLFSR] Task166 fallback: RCAS library compile failed: %@ (EASU-only would work, conservative bail)",
                  err.localizedDescription ?: @"(no error)");
            return nil;
        }

        // 渲染目标格式 = Layer A 的 drawable 格式（EASU/RCAS 的最终落点）。
        MTLPixelFormat targetFmt = viewLayer.pixelFormat;
        if (targetFmt == MTLPixelFormatInvalid) targetFmt = MTLPixelFormatBGRA8Unorm;

        MTLRenderPipelineDescriptor *easuDesc = [[MTLRenderPipelineDescriptor alloc] init];
        easuDesc.vertexFunction = [libEasu newFunctionWithName:@"ame166_vs"];
        easuDesc.fragmentFunction = [libEasu newFunctionWithName:@"ame166_easu_fs"];
        easuDesc.colorAttachments[0].pixelFormat = targetFmt;
        id<MTLRenderPipelineState> easuPSO = [device newRenderPipelineStateWithDescriptor:easuDesc error:&err];
        if (easuPSO == nil) {
            NSLog(@"[MGLFSR] Task166 fallback: EASU pipeline failed: %@",
                  err.localizedDescription ?: @"(no error)");
            return nil;
        }

        MTLRenderPipelineDescriptor *rcasDesc = [[MTLRenderPipelineDescriptor alloc] init];
        rcasDesc.vertexFunction = [libRcas newFunctionWithName:@"ame166_vs"];
        rcasDesc.fragmentFunction = [libRcas newFunctionWithName:@"ame166_rcas_fs"];
        rcasDesc.colorAttachments[0].pixelFormat = targetFmt;
        id<MTLRenderPipelineState> rcasPSO = [device newRenderPipelineStateWithDescriptor:rcasDesc error:&err];
        if (rcasPSO == nil) {
            NSLog(@"[MGLFSR] Task166 fallback: RCAS pipeline failed: %@ (conservative bail)",
                  err.localizedDescription ?: @"(no error)");
            return nil;
        }

        // RCAS 锐化（Task130 口径）：AMETHYST_FSR_RCAS_SHARPNESS ∈ [0,1]，
        // 负值 = 关（EASU-only）。映射：stops = 2*(1-s)，con.x = exp2(-stops)。
        float sharpness = 0.2f;
        const char *sharpEnv = getenv("AMETHYST_FSR_RCAS_SHARPNESS");
        if (sharpEnv != NULL) {
            sharpness = (float)strtod(sharpEnv, NULL);
        }
        bool rcasOn = (sharpness >= 0.0f);
        if (sharpness < 0.0f) sharpness = 0.0f;
        if (sharpness > 1.0f) sharpness = 1.0f;
        const float stops = 2.0f * (1.0f - sharpness);
        const float rcasConX = exp2f(-stops);

        Ame166SwapchainLayer *layerB = [[Ame166SwapchainLayer alloc] init];
        layerB.device = device;
        layerB.drawableSize = CGSizeMake(renderW, renderH);
        // Task 167：MoltenVK currentExtent 真源 = bounds × contentsScale
        // （naturalDrawableSizeMVK），与 drawableSize 同源同写，缺一即
        // zero-area 守卫拒建 swapchain（见类注释的崩溃链）。
        layerB.bounds = CGRectMake(0.0, 0.0, renderW, renderH);
        layerB.contentsScale = 1.0;
        layerB.framebufferOnly = NO;       // 我们只借用其 drawable 分发，防御性
        layerB.maximumDrawableCount = 3;   // 与 MoltenVK imageCount 期望对齐
        layerB.presentsWithTransaction = NO;
        layerB.drawsAsynchronously = YES;
        layerB.opaque = YES;

        id<MTLCommandQueue> queue = [device newCommandQueue];
        if (queue == nil) {
            NSLog(@"[MGLFSR] Task166 fallback: command queue alloc failed");
            return nil;
        }

        os_unfair_lock_lock(&s_ame166_lock);
        s_ame166_layerA = viewLayer;
        s_ame166_layerB = layerB;
        s_ame166_device = device;
        s_ame166_queue = queue;
        s_ame166_easuPSO = easuPSO;
        s_ame166_rcasPSO = rcasPSO;
        s_ame166_libEasu = libEasu;
        s_ame166_libRcas = libRcas;
        s_ame166_targetFmt = targetFmt;
        s_ame166_renderW = renderW;
        s_ame166_renderH = renderH;
        s_ame166_rcasOn = rcasOn;
        s_ame166_rcasConX = rcasConX;
        s_ame166_frames = 0;
        s_ame166_dropped = 0;
        s_ame166_ringWaitTimeouts = 0;
        s_ame166_ringNext = 0;
        for (int i = 0; i < kAme166RingSlots; i++) {
            s_ame166_ring[i] = nil;
            s_ame166_ringSem[i] = NULL;
        }
        s_ame166_active = true;
        int targetW = ame_surfaceWidth, targetH = ame_surfaceHeight;
        os_unfair_lock_unlock(&s_ame166_lock);

        NSLog(@"[MGLFSR] Task166 Metal FSR engaged: EGL surface (private layer) %dx%d -> MoltenVK swapchain -> EASU -> %dx%d -> %@ -> display layer (Metal direct, MobileGL/MoltenVK binaries untouched; ring=%d slots)",
              renderW, renderH, targetW > 0 ? targetW : renderW * 2, targetH > 0 ? targetH : renderH * 2,
              rcasOn ? [NSString stringWithFormat:@"RCAS(sharpness=%.3f)", (double)sharpness] : @"no-RCAS(env off)",
              kAme166RingSlots);
        return layerB;
    }
}

void ame166_metal_fsr_update_size(int renderW, int renderH) {
    if (!s_ame166_active) return;
    if (renderW <= 0 || renderH <= 0) return;
    os_unfair_lock_lock(&s_ame166_lock);
    if (s_ame166_layerB != nil) {
        s_ame166_layerB.drawableSize = CGSizeMake(renderW, renderH);
        // Task 167：bounds 成对同步（currentExtent 真源，见类注释）。
        s_ame166_layerB.bounds = CGRectMake(0.0, 0.0, renderW, renderH);
        s_ame166_renderW = renderW;
        s_ame166_renderH = renderH;
    }
    os_unfair_lock_unlock(&s_ame166_lock);
}

void ame166_metal_fsr_context_reset(void) {
    // 新 EGL 上下文：会话级计数复位（层/管线/环保持——同一进程同一设备，
    // shader 编译结果可复用；纹理按 nextDrawable 的尺寸自查惰性重建）。
    os_unfair_lock_lock(&s_ame166_lock);
    s_ame166_frames = 0;
    s_ame166_dropped = 0;
    s_ame166_ringWaitTimeouts = 0;
    os_unfair_lock_unlock(&s_ame166_lock);
}

void ame166_metal_fsr_teardown(void) {
    os_unfair_lock_lock(&s_ame166_lock);
    s_ame166_active = false;
    s_ame166_layerA = nil;
    s_ame166_layerB = nil;
    s_ame166_device = nil;
    s_ame166_queue = nil;
    s_ame166_easuPSO = nil;
    s_ame166_rcasPSO = nil;
    s_ame166_libEasu = nil;
    s_ame166_libRcas = nil;
    s_ame166_intermediate = nil;
    for (int i = 0; i < kAme166RingSlots; i++) {
        s_ame166_ring[i] = nil;
        s_ame166_ringSem[i] = NULL;
    }
    s_ame166_renderW = s_ame166_renderH = 0;
    s_ame166_ringNext = 0;
    s_ame166_frames = s_ame166_dropped = 0;
    os_unfair_lock_unlock(&s_ame166_lock);
    NSLog(@"[MGLFSR] Task166 teardown complete (Metal FSR layer released)");
}
