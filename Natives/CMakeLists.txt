cmake_minimum_required(VERSION 3.6)
project(AngelAuraAmethyst)

# 从环境变量读取 CurseForge API Key
# 不能通过 Makefile 的 -D 参数传递，因为 Make 会对环境变量值进行递归展开，
# 导致 bcrypt 哈希格式（$2a$10$...）中的 $2、$1、$Q 被 Make 解释为变量引用并替换为空，
# 最终生成损坏的 Key（如 a06bVFEP... 而非 $2a$10$Q6bVFEP...）
if(DEFINED ENV{CONFIG_CURSEFORGE_API_KEY})
    set(CONFIG_CURSEFORGE_API_KEY "$ENV{CONFIG_CURSEFORGE_API_KEY}")
endif()

configure_file(${CMAKE_CURRENT_LIST_DIR}/config.h.in ${CMAKE_CURRENT_LIST_DIR}/config.h)

set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -target arm64-apple-ios -mcpu=apple-a8 -fcommon -fobjc-arc -ObjC -F'${CMAKE_OSX_SYSROOT}/System/Cryptexes/OS/System/Library/Frameworks'")
set(CMAKE_C_FLAGS_DEBUG "-funwind-tables -g")

if("${CMAKE_HOST_SYSTEM_NAME}" MATCHES "Linux|^GNU$|Android")
  set(GLOBAL_LDFLAGS "-isysroot ${CMAKE_OSX_SYSROOT} -Wl,-syslibroot,${CMAKE_OSX_SYSROOT} -fuse-ld=lld")
  set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${GLOBAL_LDFLAGS}")
  set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} ${GLOBAL_LDFLAGS}")
endif()

include_directories(
  "."
  "external/AFNetworking/AFNetworking"
  "external/AFNetworking/UIKit+AFNetworking"
  "external/DBNumberedSlider/Classes"
  "external/NRFileManager"
  "external/UnzipKit"
  "external/fishhook"
  "external/lzma"
  "external/mesa"
  "external/AltKit"
  "external/Apple"
  "external/ballpa1n"
  "external/ballpa1n/wrapped"
  "external/zt.framework/Headers"
)

# ============================================================================
# ZeroTier Apple Framework 集成
# ============================================================================
# 如果存在真实 zt.framework（含二进制库），则链接真实库；
# 否则编译 stub 实现（zt_stub.c），使项目能编译通过但联机功能不可用。
#
# 真实 framework 路径：external/zt.framework/zt（二进制静态库）
# stub 实现路径：external/zt_stub.c
#
# 要启用真正的联机功能：
#   1. 从 https://github.com/zerotier/zerotier-sockets-apple-framework 获取 zt.framework
#   2. 替换 Natives/external/zt.framework/ 中的文件（保留 Headers 和 Modules，替换二进制）
#   3. 或运行 .github/workflows/build-zt-framework.yml 工作流自动下载
#   4. 重新构建主项目
set(ZT_FRAMEWORK_LIB "${CMAKE_CURRENT_LIST_DIR}/external/zt.framework/zt")
if(EXISTS "${ZT_FRAMEWORK_LIB}")
  message(STATUS "Found ZeroTier framework binary: ${ZT_FRAMEWORK_LIB}")
  set(ZT_SOURCES "")
  set(ZT_LIBS "${ZT_FRAMEWORK_LIB}" "-lc++")
else()
  message(STATUS "zt.framework binary not found, using stub implementation (multiplayer will be unavailable)")
  set(ZT_SOURCES "external/zt_stub.c")
  set(ZT_LIBS "")
endif()

# For cacio support library
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -rpath @loader_path -rpath @executable_path/java_runtimes/java-8-openjdk/lib -rpath /usr/lib/jvm/java-8-openjdk/lib")

# EXT: stub library, delete after compile awt_xawt
add_library(awt_headless SHARED
  awt_xawt/empty.m
)
target_link_libraries(awt_headless)

# EXT: cacio support library
add_library(awt_xawt SHARED
  awt_xawt/xawt_fake.m
)
target_link_libraries(awt_xawt
  "-L'${CMAKE_CURRENT_LIST_DIR}/build'"
  awt_headless
)

# TouchController iOS static library
# Links to libproxy_server_ios.a (device) or libproxy_server_ios_simulator.a (simulator)
# Provides JNI interface for touch control communication between Minecraft mod and launcher
set(TOUCHCONTROLLER_LIB_DIR "${CMAKE_CURRENT_LIST_DIR}/TouchController")
if(EXISTS "${TOUCHCONTROLLER_LIB_DIR}/libproxy_server_ios.a")
  message(STATUS "Found TouchController device library")
  set(TOUCHCONTROLLER_LIB "${TOUCHCONTROLLER_LIB_DIR}/libproxy_server_ios.a")
elseif(EXISTS "${TOUCHCONTROLLER_LIB_DIR}/libproxy_server_ios_simulator.a")
  message(STATUS "Found TouchController simulator library")
  set(TOUCHCONTROLLER_LIB "${TOUCHCONTROLLER_LIB_DIR}/libproxy_server_ios_simulator.a")
else()
  message(STATUS "TouchController library not found, TouchController support will be disabled")
  set(TOUCHCONTROLLER_LIB "")
endif()

set(CMAKE_FRAMEWORK_PATH "${CMAKE_CURRENT_LIST_DIR}/resources/Frameworks")

set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -rpath @executable_path/Frameworks -rpath @loader_path/Frameworks")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -rpath @executable_path/Frameworks -rpath @loader_path/Frameworks")

# ANGLE wrapper for 1.17+
add_library(tinygl4angle SHARED
  external/gl4es/string_utils.c
  external/gl4es/tinygl4angle.c
)
target_link_libraries(tinygl4angle
  "${GLOBAL_LDFLAGS}"
  "-F'${CMAKE_CURRENT_LIST_DIR}/resources/Frameworks'"
  "-framework libEGL"
  "-framework libGLESv2"
)

# AFNetworking
add_library(AFNetworking SHARED
  external/AFNetworking/AFNetworking/AFSecurityPolicy.m
  external/AFNetworking/AFNetworking/AFHTTPSessionManager.m
  external/AFNetworking/AFNetworking/AFURLRequestSerialization.m
  external/AFNetworking/AFNetworking/AFURLSessionManager.m
  external/AFNetworking/AFNetworking/AFNetworkReachabilityManager.m
  external/AFNetworking/AFNetworking/AFURLResponseSerialization.m
  external/AFNetworking/UIKit+AFNetworking/AFNetworkActivityIndicatorManager.m
  external/AFNetworking/UIKit+AFNetworking/AFAutoPurgingImageCache.m
  external/AFNetworking/UIKit+AFNetworking/AFImageDownloader.m
  external/AFNetworking/UIKit+AFNetworking/UIButton+AFNetworking.m
  external/AFNetworking/UIKit+AFNetworking/UIImageView+AFNetworking.m
)
target_link_libraries(AFNetworking
  "-framework CoreGraphics"
  "-framework CoreServices"
  "-framework Security"
  "-framework SystemConfiguration"
  "-framework UIKit"
)

# MinecraftAccount JNI
add_library(AmethystAccountJNI SHARED
  authenticator/MinecraftAccountJNI.m
)
target_link_libraries(AmethystAccountJNI)

# Angel Aura Amethyst
add_executable(AngelAuraAmethyst
  dyld_bypass_validation.m
  dyld_patch_platform.m
  main.m
  main_hook.m
  JavaLauncher.m
  external/fishhook/fishhook.c
  UIKit+hook.m
  ScreenUtils.m

  authenticator/BaseAuthenticator.m
  authenticator/LocalAuthenticator.m
  authenticator/MicrosoftAuthenticator.m
  authenticator/ThirdPartyAuthenticator.m

  ctxbridges/gl_bridge.m
  ctxbridges/osm_bridge.m
  ctxbridges/vk_bridge.m

  customcontrols/ControlButton.m
  customcontrols/ControlDrawer.m
  customcontrols/ControlJoystick.m
  customcontrols/ControlLayout.m
  customcontrols/ControlSubButton.m
  customcontrols/CustomControlsUtils.m
  customcontrols/NSPredicateUtilitiesExternal.m

  external/DBNumberedSlider/Classes/DBNumberedSlider.m
  external/NRFileManager/NSFileManager+NRFileManager.m
  external/ballpa1n/HostManager.c
  external/ballpa1n/wrapped/HostManagerBridge.m

  installer/FabricInstallViewController.m
  installer/ForgeInstallViewController.m
  installer/ForgeInstallSchemeViewController.m
  installer/ForgeDirectInstaller.m
  installer/NeoForgeDirectInstaller.m
  installer/ModpackInstallViewController.m
  installer/ModLoaderInstallViewController.m
  installer/FabricUtils.m
  installer/NeoForgeVersionFetcher.m
  installer/modpack/ModpackUtils.m
  installer/modpack/ModpackConfiguration.m
  installer/modpack/ModpackAPI.m
  installer/modpack/ModrinthAPI.m
	installer/modpack/CurseForgeAPI.m

  input/ControllerInput.m
  input/GyroInput.m
  input/KeyboardInput.m

  AccountListViewController.m
  AccountLoginViewController.m
  ThirdPartyLoginViewController.m
  GameMenuOverlayView.m
  InlineMessageView.m
  DownloadTaskItem.m
  DownloadTaskManager.m
  DownloadTasksViewController.m
  AppDelegate.m
  CustomControlsViewController.m
  CustomControlsViewController+UndoManager.m
  DownloadProgressViewController.m
  DownloadProgressCardView.m
  FileListViewController.m
  GameSurfaceView.m
  JavaGUIViewController.m
  MultiplayerManager.m
  MultiplayerViewController.m
  LanPortDetector.m
  ZeroTierBridge.m
  SOCKS5Proxy.m
  PortForwarder.m
  ReversePortForwarder.m
  LauncherMenuViewController.m
  LauncherNavigationController.m
  LauncherNewsViewController.m
  HomeCustomizeViewController.m
  LauncherRootViewController.m
  LauncherCardLayoutViewController.m
  LauncherRightPanelViewController.m
  VersionManagerViewController.m
  ProfileSettingsViewController.m
  DownloadViewController.m
  LauncherPreferences.m
  LauncherPreferencesViewController.m
  LauncherPrefContCfgViewController.m
  LauncherPrefGameDirViewController.m
  LauncherPrefManageJREViewController.m
  LauncherProfileEditorViewController.m
  LauncherProfilesViewController.m
  LauncherSplitViewController.m
  MinecraftResourceDownloadTask.m
  MinecraftResourceUtils.m
  PickTextField.m
  PLLogOutputView.m
  PLCrashView.m
  PLPickerView.m
  PLPreferences.m
  PLPrefTableViewController.m
  PLProfiles.m
  SceneDelegate.m
  SceneExternalDelegate.m
  SurfaceViewController.m
  SurfaceViewController+ExternalDisplay.m
  SurfaceViewController+LogView.m
  SurfaceViewController+Navigation.m
  TrackedTextField.m
  egl_bridge.m
  input_bridge_v3.m
  ios_uikit_bridge.m
  utils.m

  # ZeroTier Apple Framework 的 stub 实现（仅在真实 zt.framework 二进制不存在时生效）
  # 真实 framework 存在时 ZT_SOURCES 为空，链接 ZT_LIBS（zt + libc++）
  ${ZT_SOURCES}

  # Version card cell (shared between DownloadViewController and LauncherProfilesViewController)
  VersionCardCell.m

  # Mod-related sources (ensure implementations are compiled and linked)
  MarqueeLabel.m
  ModItem.m
  ModService.m
  ModTableViewCell.m
  ModTableViewController.m
  ModsManagerViewController.m
  ModVersion.m
  ModVersionViewController.m
  ModVersionTableViewCell.m

  # 通用资源详情页头部视图（Mod/Shader/Asset 版本页共用，展示项目封面图/信息/标签/描述）
  AssetDetailHeaderView.m

  # 模组加载器图标统一工具类（优先 bundle PNG，回退 SF Symbol，统一全项目加载器品牌色与图标）
  ModLoaderIconHelper.m

  # 统一的项目图标加载器（双层缓存+降采样+并发控制+CDN镜像，参照 FCL Glide + ZL2 Coil）
  IconLoader.m

  # Shader-related sources
  ShaderItem.m
  ShaderService.m
  ShaderTableViewCell.m
  ShaderVersion.m
  ShaderVersionTableViewCell.m
  ShaderVersionViewController.m
  ShadersManagerViewController.m

  # Modpack import/export sources
  ModpackImportViewController.m
  ModpackImportService.m
  ModpackExportService.m

  # CurseForge MurmurHash2 fingerprint tool
  MurmurHash2.m

  # Resource Pack / Data Pack / World management (services, items, version VC, manager VCs)
  ResourcePackItem.m
  DataPackItem.m
  WorldItem.m
  ResourcePackService.m
  DataPackService.m
  WorldService.m
  AssetVersionViewController.m
  ResourcePacksManagerViewController.m
  DataPacksManagerViewController.m
  WorldsManagerViewController.m

  # Server projects (Modrinth Server Projects + CurseForge server packs)
  ServerItem.m
  ServerService.m
  ServerListViewController.m
  ServerDetailViewController.m

  # CurseForge API Key settings page
  installer/CurseForgeAPIKeyViewController.m

  # Mod update service (dual-source SHA1/MurmurHash2 reverse lookup)
  ModUpdateService.m
  ModUpdateViewController.m

  # Custom icon management sources
  CustomIconManager.m
  ImageCropperViewController.m

  # Account custom avatar management sources
  AvatarManager.m

  # Background wallpaper sources
  BackgroundManager.m
  BackgroundSettingsViewController.m

  # FCL-style interface is implemented in LauncherMenuViewController.m

  # TouchController bridge and preferences
  TouchControllerBridge.m
  TouchControllerPreferencesViewController.m
)

# Add ModLoaderIcons PNG files into the app bundle Resources/ModLoaderIcons so they are available at runtime.
# This will copy all *.png under Natives/ModLoaderIcons into the bundle at Resources/ModLoaderIcons/<name>.png
set(MODLOADER_ICONS_DIR "${CMAKE_CURRENT_LIST_DIR}/ModLoaderIcons")
if(EXISTS "${MODLOADER_ICONS_DIR}")
  file(GLOB MODLOADER_ICON_FILES "${MODLOADER_ICONS_DIR}/*.png")
  if(MODLOADER_ICON_FILES)
    foreach(_icon ${MODLOADER_ICON_FILES})
      get_filename_component(_name ${_icon} NAME)
      message(STATUS "Including mod loader icon in bundle: ${_name}")
      # Place into Resources/ModLoaderIcons inside the .app bundle so your code can find resourcePath/ModLoaderIcons/...
      set_source_files_properties(${_icon} PROPERTIES MACOSX_PACKAGE_LOCATION "Resources/ModLoaderIcons")
    endforeach()
    # Attach the resource files to the main executable target so CMake copies them into the bundle
    target_sources(AngelAuraAmethyst PRIVATE ${MODLOADER_ICON_FILES})
  endif()
else()
  message(STATUS "ModLoaderIcons directory not found: ${MODLOADER_ICONS_DIR}")
endif()

if("${CMAKE_HOST_SYSTEM_NAME}" MATCHES "Linux|^GNU$|Android")
  target_sources(AngelAuraAmethyst PUBLIC non_darwin_utils.m)
endif()

target_link_libraries(AngelAuraAmethyst
  PUBLIC AFNetworking
  lzma
  "-F'${CMAKE_CURRENT_LIST_DIR}/build'"
  "-F'${CMAKE_CURRENT_LIST_DIR}/resources/Frameworks'"
  "-framework AltKit"
  "-framework AuthenticationServices"
  "-framework AVFoundation"
  "-framework CAltKit"
  "-framework CoreFoundation"
  "-framework CoreGraphics"
  "-framework CoreImage"
  "-framework CoreMedia"
  "-framework ImageIO"
  "-framework CoreMotion"
  "-framework GameController"
  "-framework IOKit"
  "-framework QuartzCore"
  "-framework UIKit"
  "-framework UniformTypeIdentifiers"
  "-framework UnzipKit"
  "-framework WebKit"
  "-weak_framework SafariServices"
  ${TOUCHCONTROLLER_LIB}
  ${ZT_LIBS}
)
set_target_properties(AngelAuraAmethyst PROPERTIES
  MACOSX_BUNDLE TRUE
  MACOSX_FRAMEWORK_IDENTIFIER org.cmake.ExecutableTarget
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_LIST_DIR}/Info.plist")
