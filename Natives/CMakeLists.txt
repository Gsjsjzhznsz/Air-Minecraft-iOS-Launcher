cmake_minimum_required(VERSION 3.6)
project(AngelAuraAmethyst)

# ===== 新增：从环境变量读取 CurseForge API Key（用于 GitHub Actions）=====
if(DEFINED ENV{CURSEFORGE_API_KEY} AND NOT "$ENV{CURSEFORGE_API_KEY}" STREQUAL "")
  set(CONFIG_CURSEFORGE_API_KEY "$ENV{CURSEFORGE_API_KEY}")
endif()
# =====================================================================

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
)

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

  authenticator/BaseAuthenticator.m
  authenticator/LocalAuthenticator.m
  authenticator/MicrosoftAuthenticator.m
  authenticator/ThirdPartyAuthenticator.m

  ctxbridges/gl_bridge.m
  ctxbridges/osm_bridge.m

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
  installer/FabricUtils.m
  installer/NeoForgeVersionFetcher.m
  installer/modpack/ModpackUtils.m
  installer/modpack/ModpackAPI.m
  installer/modpack/ModrinthAPI.m
  installer/modpack/CurseForgeAPI.m

  input/ControllerInput.m
  input/GyroInput.m
  input/KeyboardInput.m

  AccountListViewController.m
  AppDelegate.m
  CustomControlsViewController.m
  CustomControlsViewController+UndoManager.m
  DownloadProgressViewController.m
  FileListViewController.m
  GameSurfaceView.m
  JavaGUIViewController.m
  LauncherMenuViewController.m
  LauncherNavigationController.m
  LauncherNewsViewController.m
  HomeCustomizeViewController.m
  LauncherRootViewController.m
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

  # Shader-related sources
  ShaderItem.m
  ShaderService.m
  ShaderTableViewCell.m
  ShaderVersion.m
  ShaderVersionTableViewCell.m
  ShaderVersionViewController.m
  ShadersManagerViewController.m

  # Modpack import sources
  ModpackImportViewController.m
  ModpackImportService.m

  # Custom icon management sources
  CustomIconManager.m
  ImageCropperViewController.m

  # Background wallpaper sources
  BackgroundManager.m
  BackgroundSettingsViewController.m

  # FCL-style interface is implemented in LauncherMenuViewController.m

  # TouchController bridge and preferences
  TouchControllerBridge.m
  TouchControllerPreferencesViewController.m

  # AI Crash Fix sources
  AIConfigService.m
  AIFixService.m
  AIFixViewController.m
  AIToolKit.m
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
)
set_target_properties(AngelAuraAmethyst PROPERTIES
  MACOSX_BUNDLE TRUE
  MACOSX_FRAMEWORK_IDENTIFIER org.cmake.ExecutableTarget
  MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_LIST_DIR}/Info.plist")