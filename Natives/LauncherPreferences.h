#import <UIKit/UIKit.h>

void loadPreferences(BOOL reset);
void toggleIsolatedPref(BOOL forceEnable);

/// 一次性迁移：旧键 general.download_source → 新版分类镜像策略键
/// （download.fileSource / assetSearchSource / assetDownloadSource / modLoaderSource）。
/// 在 AppDelegate 启动早期调用，幂等（哨兵键 download.sourceMigrated 保证只执行一次）。
void migrateDownloadSourcePreferences(void);

/// Task 77 一次性迁移：默认触控布局出厂值 default.json -> custom.json。
/// 在 AppDelegate 启动早期调用，幂等（哨兵键 control.default_ctrl_migrated_custom
/// 保证只执行一次）。仅迁移仍停在旧出厂值 default.json 的安装；用户自选的
/// 其他布局（非 default.json）与已选 custom.json 的安装不受影响。
void migrateDefaultControlPref(void);

/// Task 130 一次性迁移：MobileGlues 性能默认值治愈（DSA / GLSL 缓存）。
/// 根因（7a680d1 装机日志实锤）：PLPreferences.setDefaultsForPref 会把缺失
/// 默认键合并进 plist 并落盘，v5.1.0 时代写入的旧默认
/// （enable_ext_direct_state_access=0、max_glsl_cache_size=32）永久压制
/// Task129d 的新默认（1/128）——默认合并只补缺失键，已存在的不覆盖。
/// 迁移仅匹配旧默认值（0/32），用户自选值（如 64）不动；哨兵键
/// mobileglues.task130_perf_defaults_migrated 保证只执行一次。
void ame130_migrateMgPerfDefaults(void);

id getPrefObject(NSString *key);
BOOL getPrefBool(NSString *key);
float getPrefFloat(NSString *key);
NSInteger getPrefInt(NSString *key);

/// Task 120：解析"有效渲染器"——profile 渲染器 + MobileGL 后端选项的单一事实源。
/// 规则（与 JavaLauncher.m 的 AMETHYST_RENDERER 解析点严格一致）：
///   1. 用户在渲染器列表里显式选择了非 auto 项 -> 永远尊重该选择
///      （修复 1d4ff3a9 会话："选了 zink 却被旧 mobilegl_vulkan 开关静默换成
///      MobileGL Vulkan"的困惑；显式选择优先于一切覆盖）；
///   2. 渲染器为 auto（默认）且设置里 MobileGL 后端选项（mobilegl_backend）
///      非"关闭" -> 覆盖为对应 MobileGL 家族渲染器（带 dylib 存在性守卫）；
///   3. 其余 -> 原样返回（auto 交由 egl_bridge 按版本解析 gl4es/ANGLE）。
/// 消费者：GameSurfaceView.layerClass（Task 124 崩溃修复）、
/// SurfaceViewController.updateSavedResolution（Task 83/119 FSR 联动）、
/// JavaLauncher（AMETHYST_RENDERER 解析点）。启动前/后调用结果一致（纯
/// profile+偏好+bundle 查询，无时序依赖）。
NSString *ame_effective_renderer(void);

void setPrefObject(NSString *key, id value);
void setPrefBool(NSString *key, BOOL value);
void setPrefFloat(NSString *key, float value);
void setPrefInt(NSString *key, NSInteger value);
void setPrefString(NSString *key, NSString *value);  // 新增

void resetWarnings();

/// 获取用户自定义主题强调色（偏好键 general.accent_color）。
/// 未设置时返回启动器默认蓝 RGB(0.26, 0.63, 0.96) = #429CF5。
/// 通过 "LauncherAppearanceChanged" 通知联动刷新，调用方应在通知回调里重新读取。
/// 参照 FCL 主题色机制：用户可在设置中选择 FCL 长春花蓝 #7797CF 等任意强调色，
/// 影响启动按钮、菜单选中态、账户添加按钮等所有"主蓝"元素。
UIColor *accentColor(void);

/// accentColor 的默认值（当前蓝 #429CF5），供需要区分"默认/自定义"的场景使用
#define ACCENT_COLOR_DEFAULT_HEX @"429CF5"

BOOL getEntitlementValue(NSString *key);

UIEdgeInsets getDefaultSafeArea();
CGRect getSafeArea(CGRect screenBounds);
void setSafeArea(CGSize screenSize, CGRect safeArea);

NSString* getSelectedJavaHome(NSString* defaultJRETag, int minVersion);

NSArray* getRendererKeys(BOOL containsDefault);
NSArray* getRendererNames(BOOL containsDefault);

// Task 132（MG 三端合并）：MobileGL 家族三后端统一浮窗（MobileGlues 分区
// renderer_backend pick 行）的数据源。keys 与渲染器值同一命名空间
// （mobilegl / mobilegl_gles / mithril 逻辑键），names 为三选项本地化文案
// （MobileGlues (Vulkan 直连) / (GLES 后端) / (OpenGL 4.0 实验性)，
// 默认 Vulkan 直连）。索引两两配对。
NSArray* getRendererFamilyKeys(void);
NSArray* getRendererFamilyNames(void);
