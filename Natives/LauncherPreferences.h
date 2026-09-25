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
/// Task 166 修订：DSA 0→1 分支已停用（DSA=1 实锤为 MG GLES/4.0 黑屏
/// 唯一配置差异，见 ame166_migrateMgDsaBlackScreen），仅保留缓存 32→128。
void ame130_migrateMgPerfDefaults(void);

/// Task 166 一次性迁移：MobileGlues DSA 黑屏反向治愈——把 Task129d/130
/// 时代持久化的 enable_ext_direct_state_access=1 归 0。三会话 A/B 实锤
/// （同机同模组包同 MobileGlues 2.0.17）：DSA=0 全程可玩（9e6fc27 两档），
/// DSA=1 黑屏（Task158 后三会话：swap 100% 健康 + render-texture 探针
/// 全零 + 首秒 10 次一次性 No-context）。机理：MobileGlues 2.0.17 的
/// DSAWrapper 模拟层在 FSR1 fb0 重定向下自洽性不足，MC 26.x 检测到
/// ARB_direct_state_access 即切 DSA 路径。哨兵键
/// mobileglues.task166_dsa_blackscreen_migrated 保证只执行一次；用户此后
/// 仍可在偏好分区手动开回（mobileglues.enable_ext_direct_state_access）。
void ame166_migrateMgDsaBlackScreen(void);

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

/// Task 142：一次性迁移渲染器存储分层——旧版（Task132-140）把 MobileGL
/// 家族键（libMobileGL.dylib / libMobileGL-gles.dylib / libmithril.dylib）
/// 直接写进全局 video.renderer 与各 profile 的 renderer 键；新版里渲染器
/// 层只存逻辑键 "mg"（不写后端），后端独立存 mobileglues.renderer_backend。
/// 迁移：全局家族键 → 后端键（若未设）+ video.renderer = "mg"；
/// 各 profile 的家族键 → "mg"（后端自此统一由 mg 设置决定，用户本轮明令
/// "渲染器选择只有一个 mg，不写什么后端"）。幂等（进程内 static 哨兵 +
/// 值域判断），在 AppDelegate 启动早期调用，也可被任何读前路径安全重入。
void ame142_migrateRendererStorage(void);

/// Task 142：解析 mg 的当前后端（家族物理键）。
/// 优先级：mobileglues.renderer_backend（合法家族键）→ legacy 全局
/// video.renderer 里残留的家族键 → legacy renderer=auto +
/// mobileglues.mobilegl_backend 档位（1/2/3）→ 默认 Vulkan 直连
/// （libMobileGL.dylib，用户指定"默认vulkan"）。返回值永远是家族键；
/// 调用方（ame_effective_renderer）负责 dylib 存在性守卫。
NSString* ame142_effective_backend_key(void);

/// Task 158：mg 家族 GLES / OpenGL 4.0 后端重映射（ame_effective_renderer
/// 把这两个后端解析为 libmobileglues.dylib，即 5.1.0 用户实际可玩的路径）
/// 后，本会话的 MobileGlues 配置强制模式。0 = 不强制（独立 MobileGlues
/// 直选或 mg+Vulkan 直连，用户分区偏好透传）；1 = GLES 后端（ANGLE
/// ForceEnable + GL 3.2）；2 = OpenGL 4.0 后端（GL 4.0 + ANGLE off）。
/// 消费者：JavaLauncher.init_loadMobileGluesConfig。
int ame158_mg_mobileglues_mode(void);

NSArray* getRendererKeys(BOOL containsDefault);
NSArray* getRendererNames(BOOL containsDefault);

// Task 140：统一渲染器显示名（设置页两行 + 实例设置页共用）。
// Task 142 语义更新："mg" 逻辑键与 legacy 家族键统一显示为 "mg"
// （渲染器层不呈现后端——后端由 MobileGlues 分区的 renderer_backend 行
// 呈现）；经典键（auto/gl4es/zink/...）→ candidates 表显示名，
// 未知值原样返回。设置页显示全局默认值、实例页显示该游戏自身值
// （含"跟随全局"态）——分层语义见 LauncherPreferences.m 的 Task140 注释。
NSString* ame_renderer_display_name(NSString *renderer);

// Task 132（MG 三端合并）：MobileGL 家族三后端统一浮窗（MobileGlues 分区
// renderer_backend pick 行）的数据源。keys 为物理键（libMobileGL.dylib /
// libMobileGL-gles.dylib / libmithril.dylib），Task 142 起作为
// mobileglues.renderer_backend 后端键的取值域（渲染器层只存 "mg"，
// 后端在启动时按此键解析，默认 libMobileGL.dylib = Vulkan 直连），
// names 为三选项本地化文案（MobileGlues (Vulkan 直连) / (GLES 后端) /
// (OpenGL 4.0 实验性)，默认 Vulkan 直连）。索引两两配对。
NSArray* getRendererFamilyKeys(void);
NSArray* getRendererFamilyNames(void);

// Task 142：逻辑渲染器键 "mg"（MobileGL 家族的唯一渲染器层入口，
// 不写后端——后端由 mg 设置 mobileglues.renderer_backend 决定）。
#define RENDERER_KEY_MG "mg"
