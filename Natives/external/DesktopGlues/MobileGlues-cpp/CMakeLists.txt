cmake_minimum_required(VERSION 3.22.1)
project("desktopglues")
enable_language(CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# glslang & SPIRV-Cross
set(ENABLE_RTTI                ON  CACHE BOOL "Enables RTTI (will be took by glslang)" FORCE)
set(ENABLE_HLSL                OFF CACHE BOOL "Disable HLSL input for glslang" FORCE)
set(BUILD_EXTERNAL             OFF CACHE BOOL "Disable build external dependencies for glslang" FORCE)
set(ENABLE_GLSLANG_BINARIES    OFF CACHE BOOL "Disable glslangValidator/spirv-remap" FORCE)
set(ENABLE_OPT                 OFF CACHE BOOL "Disable SPIRV-Tools opt usage in glslang" FORCE)
set(BUILD_EXTERNAL             OFF CACHE BOOL "Don't build external deps in External/" FORCE)

set(SPIRV_CROSS_ENABLE_C_API   ON  CACHE BOOL "Enable C API" FORCE)
set(SPIRV_CROSS_ENABLE_GLSL    ON  CACHE BOOL "Enable GLSL backend" FORCE)
set(SPIRV_CROSS_ENABLE_REFLECT OFF CACHE BOOL "Disable reflect" FORCE)
set(SPIRV_CROSS_ENABLE_HLSL    OFF CACHE BOOL "Disable HLSL backend" FORCE)
set(SPIRV_CROSS_ENABLE_MSL     OFF CACHE BOOL "Disable MSL backend" FORCE)
set(SPIRV_CROSS_ENABLE_CPP     OFF CACHE BOOL "Disable C++ API target" FORCE)
set(SPIRV_CROSS_CLI            OFF CACHE BOOL "Disable CLI binary" FORCE)
set(SPIRV_CROSS_STATIC         ON  CACHE BOOL "Prefer static libs" FORCE)
set(SPIRV_CROSS_ENABLE_UTIL    OFF CACHE BOOL "Disable util" FORCE)

add_subdirectory(3rdparty/glslang)
add_subdirectory(3rdparty/SPIRV-Cross)

if (DEFINED ENV{USE_EXTRA_OPTIMIZATIONS})
    set(USE_EXTRA_OPTIMIZATIONS "$ENV{USE_EXTRA_OPTIMIZATIONS}" CACHE STRING "Enable extra performance optimizations" FORCE)
endif()
if (NOT USE_EXTRA_OPTIMIZATIONS)
    set(USE_EXTRA_OPTIMIZATIONS "OFF")
endif()

if (USE_EXTRA_OPTIMIZATIONS STREQUAL "ON" OR USE_EXTRA_OPTIMIZATIONS STREQUAL "TRUE" OR USE_EXTRA_OPTIMIZATIONS STREQUAL "1")
    set(USE_EXTRA_OPTIMIZATIONS_ENABLED TRUE)
else()
    set(USE_EXTRA_OPTIMIZATIONS_ENABLED FALSE)
endif()

if (DEFINED LTO_FLAG)
    set(LTO_FLAG "${LTO_FLAG}" CACHE STRING "LTO flag (e.g., -flto or -flto=thin)" FORCE)
endif()

if(MACOS)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -w -fvisibility=default -funwind-tables -g -D_THREAD_SAFE -fPIC -stdlib=libc++")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -w -g -std=gnu99 -funwind-tables -fvisibility=hidden")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -static-libstdc++")
else()
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -w -fvisibility=hidden -funwind-tables -g -D_THREAD_SAFE -fPIC")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -w -g -std=gnu99 -funwind-tables -fvisibility=hidden")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -static-libstdc++")
    set(CMAKE_ANDROID_STL_TYPE c++_static)
endif()

if (CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang" AND NOT CMAKE_CXX_COMPILER_ID MATCHES "AppleClang")
    add_compile_options(-O3 -ffunction-sections -fdata-sections)
    add_link_options(-Wl,--gc-sections)
    
    if (USE_EXTRA_OPTIMIZATIONS_ENABLED AND NOT CMAKE_BUILD_TYPE STREQUAL "Debug")
        message(STATUS "")
        message(STATUS "============================================================")
        message(STATUS "  EXTRA OPTIMIZATIONS ENABLED")
        message(STATUS "============================================================")
        message(STATUS "  Compile flags:")
        message(STATUS "    -fomit-frame-pointer     : omit frame pointer")
        message(STATUS "    -fno-semantic-interposition : allow more aggressive optimizations")
        message(STATUS "    -fmerge-all-constants    : merge identical constants")
        message(STATUS "    -fno-math-errno          : don't set errno for math functions")
        message(STATUS "    -fno-signed-zeros        : ignore sign of zero")
        message(STATUS "    -fno-trapping-math       : don't trap floating point exceptions")
        message(STATUS "    -fno-unwind-tables       : don't generate unwind tables")
        message(STATUS "    -fno-asynchronous-unwind-tables : no async unwind tables")
        message(STATUS "    -fstrict-aliasing        : enable strict aliasing optimizations")
        message(STATUS "    -fno-rtti                : disable RTTI")
        message(STATUS "    -march=armv8.2-a+fp16+rcpc+dotprod+crypto : target ARMv8.2 with extensions")
        message(STATUS "    -mtune=cortex-a76        : optimize for Cortex-A76")
        message(STATUS "    -D_NDK_MATH_NO_SOFT=1   : force hardware floating point")
        message(STATUS "    -ffast-math              : aggressive floating point optimizations (may affect precision)")
        message(STATUS "")
        message(STATUS "  Link flags:")
        message(STATUS "    -Wl,--as-needed          : only link used libraries")
        message(STATUS "    -Wl,--icf=all            : merge identical code sections")
        message(STATUS "    -Wl,--hash-style=gnu     : use GNU hash style")
        message(STATUS "    -Wl,-Bsymbolic           : prefer local symbols")
        message(STATUS "    -Wl,--exclude-libs,ALL   : hide all static library symbols")
        if (LTO_FLAG)
            message(STATUS "    ${LTO_FLAG}             : LTO")
        else()
            message(STATUS "    LTO                     : Disabled")
        endif()
        message(STATUS "============================================================")
        message(STATUS "")

        add_compile_options(
            -fomit-frame-pointer
            -fno-semantic-interposition
            -fmerge-all-constants
            -fno-math-errno
            -fno-signed-zeros
            -fno-trapping-math
            -fno-unwind-tables
            -fno-asynchronous-unwind-tables
            -fstrict-aliasing
            -fno-rtti
            -march=armv8.2-a+fp16+rcpc+dotprod+crypto
            -mtune=cortex-a76
            -D_NDK_MATH_NO_SOFT=1
            -ffast-math
        )
        add_link_options(
            -Wl,--as-needed
            -Wl,--icf=all
            -Wl,--hash-style=gnu
            -Wl,-Bsymbolic
            -Wl,--exclude-libs,ALL
        )

        # LTO flag added if provided
        if (LTO_FLAG)
            message(STATUS "LTO: ${LTO_FLAG}")
            add_compile_options(${LTO_FLAG})
            add_link_options(${LTO_FLAG})
        else()
            message(STATUS "LTO: Disabled")
        endif()

    else()
        message(STATUS "")
        message(STATUS "============================================================")
        message(STATUS "  EXTRA OPTIMIZATIONS DISABLED")
        message(STATUS "============================================================")
        message(STATUS "  USE_EXTRA_OPTIMIZATIONS = ${USE_EXTRA_OPTIMIZATIONS}")
        message(STATUS "  CMAKE_BUILD_TYPE = ${CMAKE_BUILD_TYPE}")
        message(STATUS "============================================================")
        message(STATUS "")
    endif()
elseif (CMAKE_CXX_COMPILER_ID MATCHES "MSVC")
    add_compile_options(/O2)
endif()

if (CMAKE_CXX_COMPILER_ID MATCHES "MSVC")
    add_compile_options(/Zc:preprocessor)
    add_compile_options(/Zc:__cplusplus)
endif()

set(PROFILING OFF)

add_library(${CMAKE_PROJECT_NAME} SHARED
    init.cpp
    main.cpp
    gl/gl_stub.cpp
    gl/gl_native.cpp
    gl/gl.cpp
    gl/envvars.cpp
    gl/log.cpp
    gl/program.cpp
    gl/shader.cpp
    gl/framebuffer.cpp
    gl/texture.cpp
    gl/drawing.cpp
    gl/multidraw.cpp
    bench/multidraw_bench.cpp
    gl/mg.cpp
    gl/buffer.cpp
    gl/getter.cpp
    gl/enable.cpp
    gl/restart.cpp
    egl/context.cpp
    gl/pixel.cpp
    gl/transfer.cpp
    gl/random_string_gen.cpp
    gl/ExtWrappers/DSAWrapper.cpp
    gl/ExtWrappers/MultiBindWrapper.cpp
    gl/glsl/glsl_for_es.cpp
    gl/glsl/cache.cpp
    gl/FSR1/FSR1.cpp
    gl/vertexattrib.cpp
    glx/lookup.cpp
    egl/egl.cpp
    egl/loader.cpp
    gles/loader.cpp
    config/cJSON.c
    config/config.cpp
    config/gpu_utils.cpp
    config/settings.cpp
    config/stats.cpp
)

target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE
    ./includes
    ./3rdparty/xxhash)
target_include_directories(${CMAKE_PROJECT_NAME} PUBLIC ${CMAKE_SOURCE_DIR}/include)

target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE
    glslang::glslang
    spirv-cross-c
)

if (NOT MSVC AND NOT APPLE)
    # Calls between this library's own translation units must land in this
    # library. Without this, an internal call to an exported gl* symbol goes
    # through a preemptible PLT slot, and in an Android app process the system
    # libGLESv2 -- always in the global symbol scope -- can win the lookup: the
    # DSA wrappers and the benchmark would then be calling the real driver where
    # they meant the frontend, silently bypassing all state tracking. The
    # symbols stay exported for dlsym and eglGetProcAddress; only who internal
    # calls bind to changes. On the target, not in the AppleClang-guarded block
    # above -- that block's condition has never been true (dangling NOT MATCHES),
    # which is also why --gc-sections never made it into the link. Darwin's ld64
    # has no -Bsymbolic-functions; Apple ld does not support it.
    target_link_options(${CMAKE_PROJECT_NAME} PRIVATE -Wl,-Bsymbolic-functions)
endif()

if(MACOS)
    # iOS
    target_link_libraries(${CMAKE_PROJECT_NAME} PUBLIC
        "-F${CMAKE_SOURCE_DIR}/external"
        "-framework libEGL"
        "-framework libGLESv2"
        "-framework Metal"
        "-framework Foundation"
        "-framework QuartzCore"
    )
elseif(ANDROID)
    # Android
    target_link_libraries(${CMAKE_PROJECT_NAME} PUBLIC
        android
        log
    )
    else()
    # Linux — EGL/GLES are loaded dynamically via dlopen
    target_link_libraries(${CMAKE_PROJECT_NAME} PUBLIC
        ${CMAKE_DL_LIBS}
    )
endif()

if (PROFILING)
    find_package(Threads)
    include_directories(${CMAKE_SOURCE_DIR}/3rdparty/perfetto/sdk)
    add_library(perfetto STATIC ${CMAKE_SOURCE_DIR}/3rdparty/perfetto/sdk/perfetto.cc)
    target_link_libraries(${CMAKE_PROJECT_NAME} perfetto ${CMAKE_THREAD_LIBS_INIT})
    target_compile_definitions(${CMAKE_PROJECT_NAME} PUBLIC PROFILING=1)
endif()