SHELL := /bin/bash
.SHELLFLAGS = -ec
# Use `make VERBOSE=1` to print commands.
$(VERBOSE).SILENT:

# Prerequisite variables
SOURCEDIR   := $(shell printf "%q\n" "$(shell pwd)")
OUTPUTDIR   := $(SOURCEDIR)/artifacts
WORKINGDIR  := $(SOURCEDIR)/Natives/build
DETECTPLAT  := $(shell uname -s)
DETECTARCH  := $(shell uname -m)
VERSION     := 1.0
BRANCH      := $(shell git branch --show-current)
COMMIT      := $(shell git log --oneline | sed '2,10000000d' | cut -b 1-7)
PLATFORM    ?= 2

# Release vs Debug
RELEASE ?= 0

# Check if running on github runner
RUNNER ?= 0

# Check if slimmed should be built
SLIMMED ?= 0

# Check if slimmed should be built, and additionally skip normal build
SLIMMED_ONLY ?= 0

# If not in a GitHub repository, default to these
# so that compiling doesn't fail
BRANCH ?= "unknown"
COMMIT ?= "unknown"

# Team IDs and provisioning profile for the codesign function
# Default to -1 for check
# Currently requires a paid Apple Developer account, will fix later
SIGNING_TEAMID ?= -1
TEAMID ?= -1
PROVISIONING ?= -1

ifeq (1,$(RELEASE))
CMAKE_BUILD_TYPE := Release
else
CMAKE_BUILD_TYPE := Debug
endif


# Distinguish iOS from macOS, and *OS from others
ifeq ($(DETECTPLAT),Darwin)
OSVER       := $(shell sw_vers -productVersion | cut -b 1-2)
ifeq ($(shell sw_vers -productName),macOS)
IOS         := 0
SDKPATH     ?= $(shell xcrun --sdk iphoneos --show-sdk-path)
BOOTJDK     ?= $(shell /usr/libexec/java_home -v 1.8)/bin
$(warning Building on macOS.)
else
IOS         := 1
SDKPATH     ?= /usr/share/SDKs/iPhoneOS.sdk
BOOTJDK     ?= /usr/lib/jvm/java-8-openjdk/bin
ifeq ($(shell test "$(OSVER)" -gt 14; echo $$?),0)
PREFIX      ?= /var/jb/
else
PREFIX      ?= /
endif
$(warning Building on iOS. Note that all targets may not compile or require external components.)
endif
else ifeq ($(DETECTPLAT),Linux)
IOS         := 0
# SDKPATH presence is checked later
BOOTJDK     ?= /usr/bin
$(warning Building on Linux. Note that all targets may not compile or require external components.)
else
$(error This platform is not currently supported for building Angel Aura Amethyst.)
endif

# Define PLATFORM_NAME from PLATFORM
ifeq ($(PLATFORM),2)
PLATFORM_NAME := ios
$(warning Set PLATFORM to 2, which is equal to iOS.)
else ifeq ($(PLATFORM),3)
PLATFORM_NAME := tvos
$(warning Set PLATFORM to 3, which is equal to tvOS.)
else ifeq ($(PLATFORM),6)
PLATFORM_NAME := maccatalyst
$(warning Set PLATFORM to 6, which is equal to Mac Catalyst.)
else ifeq ($(PLATFORM),7)
PLATFORM_NAME := iossimulator
$(warning Set PLATFORM to 7, which is equal to iOS Simulator.)
else ifeq ($(PLATFORM),8)
PLATFORM_NAME := tvossimulator
$(warning Set PLATFORM to 8, which is equal to tvOS Simulator.)
else ifeq ($(PLATFORM),11)
PLATFORM_NAME := xros
$(warning Set PLATFORM to 11, which is equal to visionOS.)
else ifeq ($(PLATFORM),12)
PLATFORM_NAME := xrsimulator
$(warning Set PLATFORM to 12, which is equal to visionOS Simulator.)
else
$(error PLATFORM is not valid.)
endif

POJAV_BUNDLE_DIR      ?= $(OUTPUTDIR)/AngelAuraAmethyst.app
POJAV_JRE8_DIR        ?= $(SOURCEDIR)/depends/java-8-openjdk
POJAV_JRE17_DIR       ?= $(SOURCEDIR)/depends/java-17-openjdk
POJAV_JRE21_DIR       ?= $(SOURCEDIR)/depends/java-21-openjdk
POJAV_JRE25_DIR       ?= $(SOURCEDIR)/depends/java-25-openjdk
MOLTENVK_LIBRARY      ?= $(SOURCEDIR)/Natives/resources/Frameworks/libMoltenVK.dylib

# Function to use later for checking dependencies
METHOD_DEPCHECK   = $(shell $(1) >/dev/null 2>&1 && echo 1)

# Function to modify Info.plist files
METHOD_INFOPLIST  =  \
	if [ '$(4)' = '0' ]; then \
		plutil -replace $(1) -string $(2) $(3); \
	else \
		plutil -value $(2) -key $(1) $(3); \
	fi

# Function to check directories
METHOD_DIRCHECK   = \
	if [ ! -d '$(1)' ]; then \
		mkdir -p $(1); \
	else \
		rm -rf $(1)/*; \
	fi
	
# Function to change the platform on Mach-O files.
# iOS = 2, tvOS = 3, iOS Simulator = 7, tvOS Simulator = 8, visionOS = 11, visionOS Simulator = 12
# https://github.com/apple-oss-distributions/xnu/blob/main/EXTERNAL_HEADERS/mach-o/loader.h
# TODO: Change Info.plist for visionOS 1.0
METHOD_CHANGE_PLAT = \
	if [ '$(1)' != '11' ] && [ '$(1)' != '12' ]; then \
		vtool -arch arm64 -set-build-version $(1) 14.0 16.0 -replace -output $(2) $(2); \
		ldid -S -M $(2); \
	else \
		vtool -arch arm64 -set-build-version $(1) 1.0 1.0 -replace -output $(2) $(2); \
	fi \
	
# Function to package the application
# 修复：使用统一的命名格式 amethystremastered
METHOD_PACKAGE = \
	if [ '$(TROLLSTORE_JIT_ENT)' == '1' ]; then \
		IPA_SUFFIX="-trollstore.tipa"; \
	else \
		IPA_SUFFIX=".ipa"; \
	fi; \
	rm -f $(OUTPUTDIR)/com.air-devs.air-$(VERSION)-$(PLATFORM_NAME)$$IPA_SUFFIX; \
	rm -f $(OUTPUTDIR)/com.air-devs.air.slimmed-$(VERSION)-$(PLATFORM_NAME)$$IPA_SUFFIX; \
	if [ '$(SLIMMED_ONLY)' = '0' ]; then \
		zip --symlinks -r $(OUTPUTDIR)/com.air-devs.air-$(VERSION)-$(PLATFORM_NAME)$$IPA_SUFFIX Payload; \
	fi; \
	if [ '$(SLIMMED)' = '1' ] || [ '$(SLIMMED_ONLY)' = '1' ]; then \
		zip --symlinks -r $(OUTPUTDIR)/com.air-devs.air.slimmed-$(VERSION)-$(PLATFORM_NAME)$$IPA_SUFFIX Payload --exclude='Payload/AngelAuraAmethyst.app/java_runtimes/*'; \
	fi

# Function to download and unpack Java runtimes.
METHOD_JAVA_UNPACK = \
	cd $(SOURCEDIR)/depends; \
	if [ ! -f "java-$(1)-openjdk/release" ] && [ ! -f "$(ls jre$(1)-*.tar.xz)" ]; then \
		if [ "$(RUNNER)" != "1" ]; then \
			wget_ok=0; \
			for attempt in 1 2 3 4 5; do \
				if wget '$(2)' --timeout=90 --tries=2 --retry-connrefused --show-progress -O jre$(1)-ios-aarch64.zip; then wget_ok=1; break; fi; \
				echo '[jre] download failed (attempt '$$attempt'/5), retrying in 15s: $(2)'; \
				sleep 15; \
			done; \
			if [ "$$wget_ok" != "1" ]; then echo '[jre] FATAL: could not download $(2) after 5 attempts'; exit 1; fi; \
			unzip jre$(1)-ios-aarch64.zip && rm jre$(1)-ios-aarch64.zip; \
		fi; \
		mkdir -p java-$(1)-openjdk; \
		tar xvf jre$(1)-*.tar.xz -C java-$(1)-openjdk; \
	fi

# Function to codesign binaries.
METHOD_CODESIGN = \
	codesign --remove-signature $(2); \
	codesign -f -s $(1) --generate-entitlement-der --entitlements entitlements.codesign.xml $(2); \
	printf 'File: '; printf $(2); printf ', Codesigned with team: '; printf $(1); printf '\n'

# Function to run code when finding Mach-O files.
METHOD_MACHO = \
	for file in $$(find $(1)); do \
		if [[ "$$(file $$file)" == *"Mach-O"* ]]; then \
			$(2); \
		fi; \
	done

# Make sure everything is already available for use. Error if they require something
ifneq ($(call METHOD_DEPCHECK,cmake --version),1)
$(error You need to install cmake)
endif

ifneq ($(call METHOD_DEPCHECK,$(BOOTJDK)/javac -version),1)
$(error You need to install JDK 8)
endif

ifeq ($(IOS),0)
ifeq ($(filter 1.8.0,$(shell $(BOOTJDK)/javac -version &> javaver.txt && cat javaver.txt | cut -b 7-11 && rm -rf javaver.txt)),)
$(error You need to install JDK 8)
endif
endif

ifneq ($(call METHOD_DEPCHECK,ldid),1)
$(error You need to install ldid)
endif

ifneq ($(call METHOD_DEPCHECK,wget --version),1)
$(error You need to install wget)
endif

ifeq ($(DETECTPLAT),Linux)
ifneq ($(call METHOD_DEPCHECK,lld),1)
$(error You need to install lld)
endif
endif

ifneq ($(filter sysctl,$(shell sysctl -n hw.logicalcpu)),)
ifneq ($(call METHOD_DEPCHECK,nproc --version),1)
ifneq ($(call METHOD_DEPCHECK,gnproc --version),1)
$(warning Unable to determine number of threads, defaulting to 2.)
JOBS   ?= 2
else
JOBS   ?= $(shell gnproc)
endif
else
JOBS   ?= $(shell nproc)
endif
else
JOBS   ?= $(shell sysctl -n hw.logicalcpu)
endif

ifndef SDKPATH
$(error You need to specify SDKPATH to the path of iPhoneOS.sdk. The SDK version should be 14.0 or newer.)
endif

all: clean native java jre assets payload package dsym

help:
	echo 'Makefile to compile Angel Aura Amethyst'
	echo ''
	echo 'Usage:'
	echo '    make                                Makes everything under all'
	echo '    make help                           Displays this message'
	echo '    make all                            Builds the entire app'
	echo '    make native                         Builds the native app'
	echo '    make java                           Builds the Java app'
	echo '    make jre                            Downloads/unpacks the iOS JREs'
	echo '    make assets                         Compiles Assets.xcassets'
	echo '    make payload                        Makes Payload/AngelAuraAmethyst.app'
	echo '    make package                        Builds ipa of Angel Aura Amethyst'
	echo '    make deploy                         Copies files to local iDevice'
	echo '    make dsym                           Generate debug symbol files'
	echo '    make clean                          Cleans build directories'
	echo '    make check                          Dump all variables for checking'

check:
	$(foreach v, \
		$(shell echo "$(filter-out METHOD_% .% MAKEFILE_LIST MAKEFLAGS CURDIR,$(.VARIABLES))" | tr ' ' '\n' | sort), \
		$(if $(filter file,$(origin $(v))), \
		$(info $(shell printf "%-20s" "$(v)") = $(value $(v)))) \
	)

native: dep_mg
	echo '[Amethyst v$(VERSION)] native - start'
	mkdir -p $(WORKINGDIR)
	cd $(WORKINGDIR) && cmake \
		-DCMAKE_BUILD_TYPE=$(CMAKE_BUILD_TYPE) \
		-DCMAKE_CROSSCOMPILING=true \
		-DCMAKE_SYSTEM_NAME=Darwin \
		-DCMAKE_SYSTEM_PROCESSOR=aarch64 \
		-DCMAKE_OSX_SYSROOT="$(SDKPATH)" \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
		-DCMAKE_C_FLAGS="-arch arm64" \
		-DCONFIG_BRANCH="$(BRANCH)" \
		-DCONFIG_COMMIT="$(COMMIT)" \
		-DCONFIG_RELEASE=$(RELEASE) \
		..

	cmake --build $(WORKINGDIR) --config $(CMAKE_BUILD_TYPE) -j$(JOBS)
	#	--target awt_headless awt_xawt libOSMesaOverride.dylib tinygl4angle AngelAuraAmethyst
	rm $(WORKINGDIR)/libawt_headless.dylib
	echo '[Amethyst v$(VERSION)] native - end'

java:
	echo '[Amethyst v$(VERSION)] java - start'
	$(MAKE) -C JavaApp -j$(JOBS) BOOTJDK=$(BOOTJDK)
	echo '[Amethyst v$(VERSION)] java - end'

jre: native
	echo '[Amethyst v$(VERSION)] jre - start'
	mkdir -p $(SOURCEDIR)/depends
	cd $(SOURCEDIR)/depends; \
	$(call METHOD_JAVA_UNPACK,8,'https://assets.angelauramc.dev/openjdk/ios-arm64/jre8-ios-aarch64.zip'); \
	$(call METHOD_JAVA_UNPACK,17,'https://assets.angelauramc.dev/openjdk/ios-arm64/jre17-ios-aarch64.zip'); \
	$(call METHOD_JAVA_UNPACK,21,'https://assets.angelauramc.dev/openjdk/ios-arm64/jre21-ios-aarch64.zip'); \
	$(call METHOD_JAVA_UNPACK,25,'https://assets.angelauramc.dev/openjdk/ios-arm64/jre25-ios-aarch64.zip'); \
	if [ -f "$(ls jre*.tar.xz)" ]; then rm $(SOURCEDIR)/depends/jre*.tar.xz; fi; \
	cd $(SOURCEDIR); \
	rm -rf $(SOURCEDIR)/depends/java-{8,17,21,25}-openjdk/{ASSEMBLY_EXCEPTION,bin,include,jre,legal,LICENSE,man,THIRD_PARTY_README,lib/{ct.sym,jspawnhelper,libjsig.dylib,src.zip,tools.jar}}; \
	$(call METHOD_DIRCHECK,$(OUTPUTDIR)/java_runtimes); \
	cp -R $(POJAV_JRE8_DIR) $(OUTPUTDIR)/java_runtimes; \
	cp -R $(POJAV_JRE17_DIR) $(OUTPUTDIR)/java_runtimes; \
	cp -R $(POJAV_JRE21_DIR) $(OUTPUTDIR)/java_runtimes; \
	cp -R $(POJAV_JRE25_DIR) $(OUTPUTDIR)/java_runtimes; \
	cp $(WORKINGDIR)/libawt_xawt.dylib $(OUTPUTDIR)/java_runtimes/java-8-openjdk/lib; \
	cp $(WORKINGDIR)/libawt_xawt.dylib $(OUTPUTDIR)/java_runtimes/java-17-openjdk/lib;
	cp $(WORKINGDIR)/libawt_xawt.dylib $(OUTPUTDIR)/java_runtimes/java-21-openjdk/lib
	cp $(WORKINGDIR)/libawt_xawt.dylib $(OUTPUTDIR)/java_runtimes/java-25-openjdk/lib
	echo '[Amethyst v$(VERSION)] jre - end'

dep_mg:
	echo '[Amethyst v$(VERSION)] dep_mg - start'

	# The shader conversion pipeline (desktop GLSL -> ESSL) is only validated
	# against the submodule commits pinned in .gitmodules. A 3rdparty/ tree
	# populated from arbitrary master snapshots produced ESSL that ANGLE-Metal
	# rejects as empty ("ERROR: 1:1: '' : syntax error" on every shader, MC
	# 26.x black screen). Force the pinned versions before configuring cmake,
	# and fail loudly if they are still missing afterwards.
	@if [ ! -f "$(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/3rdparty/glslang/CMakeLists.txt" ] || \
	    [ ! -f "$(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/3rdparty/SPIRV-Cross/CMakeLists.txt" ] || \
	    [ ! -f "$(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/3rdparty/xxhash/xxhash32.h" ]; then \
		echo '3rdparty/ incomplete: checking out pinned glslang/SPIRV-Cross/xxhash submodules'; \
		git -C $(SOURCEDIR) submodule update --init --force --recursive \
			Natives/external/MobileGlues/MobileGlues-cpp/3rdparty/glslang \
			Natives/external/MobileGlues/MobileGlues-cpp/3rdparty/SPIRV-Cross \
			Natives/external/MobileGlues/MobileGlues-cpp/3rdparty/xxhash || exit 1; \
	fi
	@test -f "$(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/3rdparty/glslang/CMakeLists.txt" || { echo "ERROR: glslang submodule still missing - cannot build MobileGlues"; exit 1; }
	@test -f "$(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/3rdparty/SPIRV-Cross/CMakeLists.txt" || { echo "ERROR: SPIRV-Cross submodule still missing - cannot build MobileGlues"; exit 1; }
	@test -f "$(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/3rdparty/xxhash/xxhash32.h" || { echo "ERROR: xxhash submodule still missing - cannot build MobileGlues"; exit 1; }
	# The pinned glslang (f5f664d) dereferences the swizzle selector aggregate in
	# TParseContext::lValueErrorCheck without a null check. On iOS/arm64 that
	# exact chain SIGSEGV'd the process while parsing Minecraft 26.x's
	# position_color vertex shader (666 bytes post moj_import), killing the game
	# during startup. Apply the defensive null-guard patch on top of the pinned
	# submodule; idempotent across cached and fresh CI workspaces.
	@if git -C $(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/3rdparty/glslang apply --check $(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/3rdparty/glslang-lvalue-nullguard.patch >/dev/null 2>&1; then \
		git -C $(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/3rdparty/glslang apply $(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/3rdparty/glslang-lvalue-nullguard.patch && echo 'glslang-lvalue-nullguard.patch applied'; \
	else \
		echo 'glslang-lvalue-nullguard.patch already applied or submodule absent - continuing'; \
	fi
	# Task 45: pool-block zero-fill + constArray size guards, applied ON TOP of
	# the nullguard patch (requires it). The prebuilt libshaderc_impl.dylib crash
	# family (45 tasks: constArray+0xd8 reads recycled source-text bytes -> SIGSEGV
	# -> all pipelines fail -> MC dies) is closed at the source level: every fresh
	# glslang pool block (malloc-recycled OR freelist-reused) is zero-filled, so
	# any un-initialized / stale field read observes 0/NULL and the nullguards
	# degrade gracefully (identity swizzle / skipped element) instead of dying.
	# Idempotent: --check first, matching the nullguard block above.
	@if git -C $(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/3rdparty/glslang apply --check $(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/3rdparty/glslang-pool-zero-and-size-guards.patch >/dev/null 2>&1; then \
		git -C $(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/3rdparty/glslang apply $(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/3rdparty/glslang-pool-zero-and-size-guards.patch && echo 'glslang-pool-zero-and-size-guards.patch applied'; \
	else \
		echo 'glslang-pool-zero-and-size-guards.patch already applied or submodule absent - continuing'; \
	fi
	mkdir -p $(WORKINGDIR)/mobileglues
	# Task 27: 显式设 CMAKE_BUILD_TYPE=RelWithDebInfo。此前未设置（--config 对
	# 单配置生成器无效），CMake 不追加 -O2/-DNDEBUG：整库 -O0 且 glslang/
	# SPIRV-Cross/MG 的 assert() 全部激活——assert 触发即 __assert_rtn->abort()，
	# 被 hooked_abort 拦截后表现为直接进启动器错误界面且无 .ips/hs_err。
	# RelWithDebInfo = -O2 -g -DNDEBUG，对齐上游 Release 语义。
	cd $(WORKINGDIR)/mobileglues && cmake \
		-DMACOS="1" \
		-DCMAKE_CROSSCOMPILING=true \
		-DCMAKE_SYSTEM_NAME=Darwin \
		-DCMAKE_SYSTEM_PROCESSOR=aarch64 \
		-DCMAKE_OSX_SYSROOT="$(SDKPATH)" \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
		-DCMAKE_C_FLAGS="-arch arm64" \
		-DCMAKE_BUILD_TYPE=RelWithDebInfo \
		$(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/

	# Task 45: also build the SPIRV emitter + default resource limits static
	# libraries - dep_shader_shims links them (with libglslang.a) into the
	# from-source libshaderc_impl.dylib. mobileglues itself only links
	# glslang::glslang, so these targets must be named explicitly.
	# Task 46: the archives land under <build>/3rdparty/glslang/ - the
	# MobileGlues superbuild add_subdirectory(3rdparty/glslang) keeps
	# source-relative binary dirs. Task 45 checked the standalone-glslang
	# layout (<build>/SPIRV/..., produced only by a manual standalone
	# configure) and aborted CI with "libSPIRV.a missing" right after an
	# all-green compile (run 34105892191). Check the superbuild layout,
	# fall back to locating the archive by name, fail with a listing.
	cmake --build $(WORKINGDIR)/mobileglues --config RelWithDebInfo -j$(JOBS) --target mobileglues SPIRV glslang-default-resource-limits
	@mg_spirv_a=$(WORKINGDIR)/mobileglues/3rdparty/glslang/SPIRV/libSPIRV.a; \
	[ -f "$$mg_spirv_a" ] || mg_spirv_a=$$(find $(WORKINGDIR)/mobileglues -type f -name libSPIRV.a -print -quit 2>/dev/null); \
	mg_glslang_a=$(WORKINGDIR)/mobileglues/3rdparty/glslang/glslang/libglslang.a; \
	[ -f "$$mg_glslang_a" ] || mg_glslang_a=$$(find $(WORKINGDIR)/mobileglues -type f -name libglslang.a -print -quit 2>/dev/null); \
	mg_rl_a=$(WORKINGDIR)/mobileglues/3rdparty/glslang/glslang/libglslang-default-resource-limits.a; \
	[ -f "$$mg_rl_a" ] || mg_rl_a=$$(find $(WORKINGDIR)/mobileglues -type f -name libglslang-default-resource-limits.a -print -quit 2>/dev/null); \
	if [ -z "$$mg_spirv_a" ] || [ ! -f "$$mg_spirv_a" ] || [ -z "$$mg_glslang_a" ] || [ ! -f "$$mg_glslang_a" ] || [ -z "$$mg_rl_a" ] || [ ! -f "$$mg_rl_a" ]; then \
		echo "ERROR: glslang static libs unresolved (spirv=$$mg_spirv_a glslang=$$mg_glslang_a rl=$$mg_rl_a) - from-source shaderc impl cannot link"; \
		find $(WORKINGDIR)/mobileglues -type f -name "lib*.a" 2>/dev/null | head -20; \
		exit 1; \
	fi; \
	echo "[shaderc-impl] glslang static libs OK (spirv=$$mg_spirv_a glslang=$$mg_glslang_a rl=$$mg_rl_a)"
	cp $(WORKINGDIR)/mobileglues/libmobileglues*.dylib $(WORKINGDIR)/
	echo '[Amethyst v$(VERSION)] dep_mg - end'
dep_mobilegl:
	# MobileGL（Vulkan/GLES 后端渲染器）集成已完全移除：
	# - 构建链中的 perl 补丁（Range1D/BufferChange/is_aggregate_v）不再需要
	# - libMobileGL.dylib / libMobileGL-gles.dylib 不再构建/打包
	# - 运行时不再提供 MobileGL 渲染器选项
	# 保留空目标避免外部 make 调用报错（payload 不再依赖此目标）
	@echo '[Amethyst v$(VERSION)] dep_mobilegl - skipped (MobileGL removed)'

assets:
	echo '[Amethyst v$(VERSION)] assets - start'
	if [ '$(IOS)' = '0' ] && [ '$(DETECTPLAT)' = 'Darwin' ]; then \
		mkdir -p $(WORKINGDIR)/AngelAuraAmethyst.app/Base.lproj; \
		xcrun actool $(SOURCEDIR)/Natives/Assets.xcassets \
			--compile $(SOURCEDIR)/Natives/resources \
			--platform iphoneos \
			--minimum-deployment-target 14.0 \
			--app-icon AppIcon-Light \
			--output-partial-info-plist /dev/null || exit 1; \
	else \
		echo 'Due to the required tools not being available, you cannot compile the extras for Angel Aura Amethyst with an iOS device.'; \
	fi
	echo '[Amethyst v$(VERSION)] assets - end'

# shaderc / spirv-cross serializing shims (hs_err_pid27329: concurrent compiles
# from multiple contexts trampled glslang AST node memory). Real libs were
# renamed *_impl.dylib (git mv). This target:
#   1) copies the impls into WORKINGDIR and fixes their LC_ID with
#      install_name_tool (re-export must point at the impl name, not back at
#      the shim, or loading recurses forever);
#   2) builds same-name shims with -reexport_library (pass through ALL impl
#      symbols); the 3 shaderc compile entries and 2 heavy spvc entries are
#      defined by the shims with a process-global recursive mutex, so every
#      resolution path (hooked dlsym / RTLD_DEFAULT / any direct dlsym) lands
#      on the locking forwarders. Deadlock avoidance details in
#      Natives/shaderc_shim.c header comment.
dep_shader_shims: dep_mg
	echo '[Amethyst v$(VERSION)] dep_shader_shims - start'
	# Task 45: build libshaderc_impl.dylib FROM SOURCE - glue over the glslang C
	# interface (Natives/shaderc_impl_glue.c) linked against the SAME pinned
	# f5f664d static libs dep_mg just built (nullguard + pool-zero/size-guard
	# patches applied). Retires the prebuilt unpatched impl blob and the Task-34
	# machine-code cave patch (scripts/patch_shaderc_lvalue_guard.py stays
	# in-repo for archaeology). The 45-task crash family (constArray+0xd8
	# reading recycled source-text bytes, deterministic per-run / ASLR-luck
	# across runs, surviving every in-process mitigation) had exactly one
	# untested variable left - the impl binary itself; now the only glslang in
	# the process is the patched, freshly-built one. dep_mg ordering: this
	# target links dep_mg's outputs (parallel-make safety).
	# Task 46: resolve the glslang static libs from the superbuild layout
	# (<build>/3rdparty/glslang/...). Task 45 pointed at the
	# standalone-glslang layout (<build>/SPIRV/...), which this build never
	# produces - CI run 34105892191 died at "libSPIRV.a missing" after an
	# all-green compile. Primary: superbuild paths; fallback: locate by
	# archive name under the mobileglues build tree so future CMake layout
	# drift cannot break the link.
	mg_bindir=$(WORKINGDIR)/mobileglues/3rdparty/glslang; \
	mg_spirv_a=$$mg_bindir/SPIRV/libSPIRV.a; \
	[ -f "$$mg_spirv_a" ] || mg_spirv_a=$$(find $(WORKINGDIR)/mobileglues -type f -name libSPIRV.a -print -quit 2>/dev/null); \
	mg_glslang_a=$$mg_bindir/glslang/libglslang.a; \
	[ -f "$$mg_glslang_a" ] || mg_glslang_a=$$(find $(WORKINGDIR)/mobileglues -type f -name libglslang.a -print -quit 2>/dev/null); \
	mg_rl_a=$$mg_bindir/glslang/libglslang-default-resource-limits.a; \
	[ -f "$$mg_rl_a" ] || mg_rl_a=$$(find $(WORKINGDIR)/mobileglues -type f -name libglslang-default-resource-limits.a -print -quit 2>/dev/null); \
	if [ -z "$$mg_spirv_a" ] || [ ! -f "$$mg_spirv_a" ] || [ -z "$$mg_glslang_a" ] || [ ! -f "$$mg_glslang_a" ] || [ -z "$$mg_rl_a" ] || [ ! -f "$$mg_rl_a" ]; then \
		echo "ERROR: glslang static libs unresolved (spirv=$$mg_spirv_a glslang=$$mg_glslang_a rl=$$mg_rl_a) - from-source shaderc impl cannot link"; \
		exit 1; \
	fi; \
	extra_glslang_libs=""; \
	for l in libOGLCompiler.a libOSDependent.a; do \
		if [ -f "$$mg_bindir/glslang/$$l" ]; then \
			extra_glslang_libs="$$extra_glslang_libs $$mg_bindir/glslang/$$l"; \
		fi; \
	done; \
	echo "[shaderc-impl] linking from-source impl (spirv=$$mg_spirv_a glslang=$$mg_glslang_a rl=$$mg_rl_a extra libs:$$extra_glslang_libs)"; \
	xcrun -sdk iphoneos clang -arch arm64 -dynamiclib \
		-install_name @rpath/libshaderc_impl.dylib \
		-I$(SOURCEDIR)/Natives/external/MobileGlues/MobileGlues-cpp/3rdparty/glslang \
		-o $(WORKINGDIR)/libshaderc_impl.dylib \
		$(SOURCEDIR)/Natives/shaderc_impl_glue.c \
		"$$mg_spirv_a" \
		"$$mg_glslang_a" \
		"$$mg_rl_a" \
		$$extra_glslang_libs \
		-lc++ || exit 1
	install_name_tool -id @rpath/libshaderc_impl.dylib $(WORKINGDIR)/libshaderc_impl.dylib || exit 1
	cp $(SOURCEDIR)/Natives/resources/Frameworks/libspirv-cross-c-shared.0.impl.dylib $(WORKINGDIR)/ || exit 1
	install_name_tool -id @rpath/libspirv-cross-c-shared.0.impl.dylib $(WORKINGDIR)/libspirv-cross-c-shared.0.impl.dylib || exit 1
	xcrun -sdk iphoneos clang -arch arm64 -dynamiclib \
		-install_name @rpath/libshaderc.dylib \
		-Wl,-reexport_library,$(WORKINGDIR)/libshaderc_impl.dylib \
		-o $(WORKINGDIR)/libshaderc.dylib \
		$(SOURCEDIR)/Natives/shaderc_shim.c \
		$(SOURCEDIR)/Natives/shaderc_include.c \
		$(SOURCEDIR)/Natives/shaderc_sandbox.m || exit 1
	xcrun -sdk iphoneos clang -arch arm64 -dynamiclib \
		-install_name @rpath/libspirv-cross-c-shared.0.dylib \
		-Wl,-reexport_library,$(WORKINGDIR)/libspirv-cross-c-shared.0.impl.dylib \
		-o $(WORKINGDIR)/libspirv-cross-c-shared.0.dylib \
		$(SOURCEDIR)/Natives/spvc_shim.c || exit 1
	echo '[Amethyst v$(VERSION)] dep_shader_shims - end'

payload: native dep_mg java jre assets dep_shader_shims
	echo '[Amethyst v$(VERSION)] payload - start'
	$(call METHOD_DIRCHECK,$(WORKINGDIR)/AngelAuraAmethyst.app/libs)
	$(call METHOD_DIRCHECK,$(WORKINGDIR)/AngelAuraAmethyst.app/libs_caciocavallo)
	$(call METHOD_DIRCHECK,$(WORKINGDIR)/AngelAuraAmethyst.app/libs_caciocavallo17)
	cp -R $(SOURCEDIR)/Natives/resources/en.lproj/LaunchScreen.storyboardc $(WORKINGDIR)/AngelAuraAmethyst.app/Base.lproj/ || exit 1
	cp -R $(SOURCEDIR)/Natives/resources/* $(WORKINGDIR)/AngelAuraAmethyst.app/ || exit 1
	cp $(WORKINGDIR)/*.dylib $(WORKINGDIR)/AngelAuraAmethyst.app/Frameworks/ || exit 1
	# spirv-cross 软链接（防御性兜底）：若 MobileGlues 构建产出 libspirv-cross-c-shared.0.dylib，
	# 创建 libspirv-cross.dylib 软链接，兼容按 macOS 默认名加载的 native 代码。
	if [ -f "$(WORKINGDIR)/AngelAuraAmethyst.app/Frameworks/libspirv-cross-c-shared.0.dylib" ] && [ ! -f "$(WORKINGDIR)/AngelAuraAmethyst.app/Frameworks/libspirv-cross.dylib" ]; then \
		ln -sf libspirv-cross-c-shared.0.dylib $(WORKINGDIR)/AngelAuraAmethyst.app/Frameworks/libspirv-cross.dylib; \
	fi
		cp -R $(SOURCEDIR)/JavaApp/libs/others/* $(WORKINGDIR)/AngelAuraAmethyst.app/libs/ || exit 1
	cp $(SOURCEDIR)/JavaApp/build/launcher.jar $(SOURCEDIR)/JavaApp/build/patchjna_agent.jar $(SOURCEDIR)/JavaApp/build/patchsvc.jar $(WORKINGDIR)/AngelAuraAmethyst.app/libs/ || exit 1
	# LWJGL 以双版本 jar 发布，由启动器按 MC 版本在运行时选择其一（26.x+ -> 341，其余 -> 333）。
	# 必须放进各自的 libs/lwjgl-<ver>/ 子目录：若平铺进 libs/，会被 classpath 中的 libs/*
	# 一并加载，使 3.3.3 与 3.4.1 的同名类同时进入 classpath 造成冲突。lwjgl.jar 是占位
	# 产物，不进 app 的 libs 目录。
	mkdir -p $(WORKINGDIR)/AngelAuraAmethyst.app/libs/lwjgl-333 $(WORKINGDIR)/AngelAuraAmethyst.app/libs/lwjgl-341; \
	cp $(SOURCEDIR)/JavaApp/build/lwjgl-333.jar $(WORKINGDIR)/AngelAuraAmethyst.app/libs/lwjgl-333/lwjgl.jar || exit 1
	cp $(SOURCEDIR)/JavaApp/build/lwjgl-341.jar $(WORKINGDIR)/AngelAuraAmethyst.app/libs/lwjgl-341/lwjgl.jar || exit 1
	cp -R $(SOURCEDIR)/JavaApp/libs/caciocavallo/* $(WORKINGDIR)/AngelAuraAmethyst.app/libs_caciocavallo || exit 1
	cp -R $(SOURCEDIR)/JavaApp/libs/caciocavallo17/* $(WORKINGDIR)/AngelAuraAmethyst.app/libs_caciocavallo17 || exit 1
	# Copy TouchController static library if available
	if [ -f "$(SOURCEDIR)/TouchController/libproxy_server_ios.a" ]; then \
		mkdir -p $(WORKINGDIR)/AngelAuraAmethyst.app/Frameworks; \
		cp $(SOURCEDIR)/TouchController/libproxy_server_ios.a $(WORKINGDIR)/AngelAuraAmethyst.app/Frameworks/ || exit 1; \
		echo '[Amethyst v$(VERSION)] Copied TouchController device library'; \
	elif [ -f "$(SOURCEDIR)/TouchController/libproxy_server_ios_simulator.a" ]; then \
		mkdir -p $(WORKINGDIR)/AngelAuraAmethyst.app/Frameworks; \
		cp $(SOURCEDIR)/TouchController/libproxy_server_ios_simulator.a $(WORKINGDIR)/AngelAuraAmethyst.app/Frameworks/ || exit 1; \
		echo '[Amethyst v$(VERSION)] Copied TouchController simulator library'; \
	else \
		echo '[Amethyst v$(VERSION)] TouchController library not found, skipping'; \
	fi
	$(call METHOD_DIRCHECK,$(OUTPUTDIR)/Payload)
	cp -R $(WORKINGDIR)/AngelAuraAmethyst.app $(OUTPUTDIR)/Payload
	if [ '$(SLIMMED_ONLY)' != '1' ]; then \
		cp -R $(OUTPUTDIR)/java_runtimes $(OUTPUTDIR)/Payload/AngelAuraAmethyst.app; \
	fi
	ldid -S $(OUTPUTDIR)/Payload/AngelAuraAmethyst.app; \
	if [ '$(TROLLSTORE_JIT_ENT)' == '1' ]; then \
		ldid -S$(SOURCEDIR)/entitlements.trollstore.xml $(OUTPUTDIR)/Payload/AngelAuraAmethyst.app/AngelAuraAmethyst; \
	elif [ '$(PLATFORM)' == '6' ]; then \
		ldid -S$(SOURCEDIR)/entitlements.codesign.xml $(OUTPUTDIR)/Payload/AngelAuraAmethyst.app/AngelAuraAmethyst; \
	else \
		ldid -S$(SOURCEDIR)/entitlements.sideload.xml $(OUTPUTDIR)/Payload/AngelAuraAmethyst.app/AngelAuraAmethyst; \
	fi
	chmod -R 755 $(OUTPUTDIR)/Payload
	# 总是运行平台重打标（对齐 Ynnyny 仓库）—— 对已 iOS 标记的 Mach-O 是幂等的，
	# 但能捕获从 Maven 直接拉取的新 dylib（如 3.3.5 lwjgl-stb），它们 ship 时
	# platform=macos，iOS dyld 会静默拒绝加载，导致 LWJGL 抛 UnsatisfiedLinkError。
	# 原本用 [ PLATFORM != 2 ] 守卫的假设是所有 commit 的 dylib 都已 iOS 标记，
	# 这个假设在同步 Ynnyny 顶层 dylib 时被打破。
	$(call METHOD_MACHO,$(OUTPUTDIR)/Payload/AngelAuraAmethyst.app,$(call METHOD_CHANGE_PLAT,$(PLATFORM),$$file)); \
	$(call METHOD_MACHO,$(OUTPUTDIR)/java_runtimes,$(call METHOD_CHANGE_PLAT,$(PLATFORM),$$file));
	echo '[Amethyst v$(VERSION)] payload - end'

deploy:
	echo '[Amethyst v$(VERSION)] deploy - start'
	cd $(OUTPUTDIR); \
	if [ '$(IOS)' = '1' ]; then \
		ldid -S $(WORKINGDIR)/AngelAuraAmethyst.app || exit 1; \
		ldid -S$(SOURCEDIR)/entitlements.trollstore.xml $(WORKINGDIR)/AngelAuraAmethyst.app/AngelAuraAmethyst || exit 1; \
		sudo mv $(WORKINGDIR)/*.dylib $(PREFIX)Applications/AngelAuraAmethyst.app/Frameworks/ || exit 1; \
		sudo mv $(WORKINGDIR)/AngelAuraAmethyst.app/AngelAuraAmethyst $(PREFIX)Applications/AngelAuraAmethyst.app/AngelAuraAmethyst || exit 1; \
		sudo mkdir -p $(PREFIX)Applications/AngelAuraAmethyst.app/libs/lwjgl-333 $(PREFIX)Applications/AngelAuraAmethyst.app/libs/lwjgl-341 || exit 1; \
		sudo mv $(SOURCEDIR)/JavaApp/build/launcher.jar $(SOURCEDIR)/JavaApp/build/patchjna_agent.jar $(SOURCEDIR)/JavaApp/build/patchsvc.jar $(PREFIX)Applications/AngelAuraAmethyst.app/libs/ || exit 1; \
		sudo mv $(SOURCEDIR)/JavaApp/build/lwjgl-333.jar $(PREFIX)Applications/AngelAuraAmethyst.app/libs/lwjgl-333/lwjgl.jar || exit 1; \
		sudo mv $(SOURCEDIR)/JavaApp/build/lwjgl-341.jar $(PREFIX)Applications/AngelAuraAmethyst.app/libs/lwjgl-341/lwjgl.jar || exit 1; \
		cd $(PREFIX)Applications/AngelAuraAmethyst.app/Frameworks || exit 1; \
		sudo chown -R 501:501 $(PREFIX)Applications/AngelAuraAmethyst.app/* || exit 1; \
	elif [ '$(IOS)' = '0' ] && [ '$(DETECTPLAT)' = 'Darwin' ]; then \
		if [ '$(PLATFORM)' != '2' ] || [ '$(TEAMID)' = '-1' ] || [ '$(SIGNING_TEAMID)' = '-1' ] || [ '$(PROVISIONING)' = '-1' ]; then \
			echo 'Configuration not supported for deploy recipe.'; \
		else \
			$(call METHOD_PACKAGE); \
			if [ '$(SLIMMED_ONLY)' = '0' ]; then \
				open $(OUTPUTDIR)/com.air-devs.air-$(VERSION)-$(PLATFORM_NAME).ipa; \
			else \
				open $(OUTPUTDIR)/com.air-devs.air.slimmed-$(VERSION)-$(PLATFORM_NAME).ipa; \
			fi; \
		fi; \
	else \
		echo 'Device not supported for deploy recipe.'; \
	fi
	echo '[Amethyst v$(VERSION)] deploy - end'

package: payload
	echo '[Amethyst v$(VERSION)] package - start'
	if [ '$(TEAMID)' != '-1' ] && [ '$(SIGNING_TEAMID)' != '-1' ] && [ -f '$(PROVISIONING)' ] && [ '$(DETECTPLAT)' = 'Darwin' ]; then \
		printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n	<key>application-identifier</key>\n	<string>$(TEAMID).com.air-devs.air</string>\n	<key>com.apple.developer.team-identifier</key>\n	<string>$(TEAMID)</string>\n	<key>get-task-allow</key>\n	<true/>\n	<key>keychain-access-groups</key>\n	<array>\n	<string>$(TEAMID).*</string>\n	<string>com.apple.token</string>\n	</array>\n	<key>com.apple.developer.kernel.extended-virtual-addressing</key>\n	<true/>\n	<key>com.apple.developer.kernel.increased-memory-limit</key>\n	<true/>\n</dict>\n</plist>' > entitlements.codesign.xml; \
		$(MAKE) codesign; \
		rm -rf entitlements.codesign.xml; \
	else \
		echo 'Skipped codesigning. If not intentional, check your variables.'; \
	fi
	cd $(OUTPUTDIR); \
	$(call METHOD_PACKAGE); \
	zip --symlinks -r $(OUTPUTDIR)/java_runtimes.zip java_runtimes; \
	echo '[Amethyst v$(VERSION)] package - end'

dsym: payload
	echo '[Amethyst v$(VERSION)] dsym - start'
	dsymutil --arch arm64 $(OUTPUTDIR)/Payload/AngelAuraAmethyst.app/AngelAuraAmethyst; \
	rm -rf $(OUTPUTDIR)/AngelAuraAmethyst.dSYM; \
	mv $(OUTPUTDIR)/Payload/AngelAuraAmethyst.app/AngelAuraAmethyst.dSYM $(OUTPUTDIR)/AngelAuraAmethyst.dSYM
	echo '[Amethyst v$(VERSION)] dsym - end'
	
codesign:
	echo '[Amethyst v$(VERSION)] codesign - start'
	cp '$(PROVISIONING)' $(OUTPUTDIR)/Payload/AngelAuraAmethyst.app/embedded.mobileprovision
	$(call METHOD_MACHO,$(OUTPUTDIR)/Payload/AngelAuraAmethyst.app,$(call METHOD_CODESIGN,$(SIGNING_TEAMID),$$file))
	$(call METHOD_MACHO,$(OUTPUTDIR)/java_runtimes,$(call METHOD_CODESIGN,$(SIGNING_TEAMID),$$file))
	echo '[Amethyst v$(VERSION)] codesign - end'

clean:
	echo '[Amethyst v$(VERSION)] clean - start'
	rm -rf $(WORKINGDIR)
	rm -rf JavaApp/build
	rm -rf $(OUTPUTDIR)
	echo '[Amethyst v$(VERSION)] clean - end'

.PHONY: all clean check native java jre package dsym deploy help
