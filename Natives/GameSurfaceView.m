#import "GameSurfaceView.h"
#import "LauncherPreferences.h"
#import "PLProfiles.h"
#import "utils.h"

@interface GameSurfaceView()
@end

@implementation GameSurfaceView

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    self.layer.drawsAsynchronously = YES;
    self.layer.opaque = YES;

    return self;
}

+ (Class)layerClass {
    // Task 124（MobileGL 崩溃根治）：必须用"有效渲染器"（ame_effective_renderer，
    // 含 MobileGL 后端选项覆盖）判定，而不是裸读 profile 渲染器。
    // 事故链（1d4ff3a9 装机日志）：用户 profile=zink -> 这里返回了普通 CALayer；
    // 旧 Task113 的 mobilegl_vulkan 开关却把实际渲染器覆盖成 libMobileGL.dylib
    // (DirectVulkan) -> MobileGL 内部 MoltenVK 在 swapchain 创建时向该层发送
    // naturalDrawableSizeMVK（MoltenVK 挂在 CAMetalLayer 上的 category 方法）
    // -> 普通CALayer 无此方法 -> NSInvalidArgumentException，进程终止。
    // 修复：layerClass 与 JavaLauncher 的 AMETHYST_RENDERER 解析同源（单一
    // 事实源 ame_effective_renderer），MobileGL / Mithril 一律 CAMetalLayer。
    NSString *renderer = ame_effective_renderer();
    if ([renderer hasPrefix:@"libOSMesa"]) {
        // zink/OSMesa：呈现走 CGImage contents（CPU 侧回读），无需 Metal 层。
        return CALayer.class;
    }
    // 其余全部 CAMetalLayer：MobileGL(DirectVulkan 内部 MoltenVK 直呈 Metal 层，
    // DirectGLES 同样支持 CAMetalLayer native window)、Mithril、MoltenVK、
    // ANGLE/MobileGlues/LTW（EGL -> Metal）。
    return CAMetalLayer.class;
}

@end
