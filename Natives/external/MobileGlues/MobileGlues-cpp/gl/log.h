// MobileGlues - gl/log.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#ifndef MOBILEGLUES_LOG_H

#include "../includes.h"

#define FORCE_SYNC_WITH_LOG_FILE 0

#define GLOBAL_DEBUG 0

#define LOG_CALLED_FUNCS 0

#ifdef __cplusplus
extern "C"
{
#endif

    const char* glEnumToString(GLenum e);

#ifdef __cplusplus
}
#endif

#ifndef __ANDROID__
// Define a stub for __android_log_print if not on Android
#define ANDROID_LOG_UNKNOWN 0
#define ANDROID_LOG_DEFAULT 1
#define ANDROID_LOG_VERBOSE 2
#define ANDROID_LOG_DEBUG 3
#define ANDROID_LOG_INFO 4
#define ANDROID_LOG_WARN 5
#define ANDROID_LOG_ERROR 6
#define ANDROID_LOG_FATAL 7
#define ANDROID_LOG_SILENT 8

typedef int android_LogPriority;

int __android_log_print(int prio, const char* tag, const char* fmt, ...);
#endif

#if GLOBAL_DEBUG_FORCE_OFF
#define LOG()                                                                                                          \
    {}
#define LOG_D(...)                                                                                                     \
    {}
#define LOG_D_N(...)                                                                                                   \
    {}
#define LOG_W(...)                                                                                                     \
    {}
#define LOG_E(...)                                                                                                     \
    {}
#define LOG_F(...)                                                                                                     \
    {}
#else
#if PROFILING
#define LOG()                                                                                                          \
    perfetto::StaticString _FUNC_NAME_ = __func__;                                                                     \
    TRACE_EVENT("glcalls", _FUNC_NAME_);
#elif LOG_CALLED_FUNCS
#define LOG()                                                                                                          \
    if (DEBUG || GLOBAL_DEBUG) {                                                                                       \
        __android_log_print(ANDROID_LOG_DEBUG, RENDERERNAME, "Use function: %s", __FUNCTION__);                        \
        printf("Use function: %s\n", __FUNCTION__);                                                                    \
        write_log("Use function: %s\n", __FUNCTION__);                                                                 \
    }                                                                                                                  \
    log_unique_function(__FUNCTION__);
void log_unique_function(const char* func_name);
#else
#define LOG()                                                                                                          \
    if (DEBUG || GLOBAL_DEBUG) {                                                                                       \
        __android_log_print(ANDROID_LOG_DEBUG, RENDERERNAME, "\nUse function: %s", __FUNCTION__);                      \
        printf("\nUse function: %s\n", __FUNCTION__);                                                                  \
        write_log("\nUse function: %s\n", __FUNCTION__);                                                               \
    }
#endif

#define LOG_D(...)                                                                                                     \
    if (DEBUG || GLOBAL_DEBUG) {                                                                                       \
        __android_log_print(ANDROID_LOG_DEBUG, RENDERERNAME, __VA_ARGS__);                                             \
        printf(__VA_ARGS__);                                                                                           \
        printf("\n");                                                                                                  \
        write_log(__VA_ARGS__);                                                                                        \
    }
#define LOG_D_N(...)                                                                                                   \
    if (DEBUG || GLOBAL_DEBUG) {                                                                                       \
        __android_log_print(ANDROID_LOG_DEBUG, RENDERERNAME, __VA_ARGS__);                                             \
        printf(__VA_ARGS__);                                                                                           \
        write_log_n(__VA_ARGS__);                                                                                      \
    }
#define LOG_W(...)                                                                                                     \
    if (DEBUG || GLOBAL_DEBUG) {                                                                                       \
        __android_log_print(ANDROID_LOG_WARN, RENDERERNAME, __VA_ARGS__);                                              \
        printf(__VA_ARGS__);                                                                                           \
        printf("\n");                                                                                                  \
        write_log(__VA_ARGS__);                                                                                        \
    }
#define LOG_E(...)                                                                                                     \
    if (DEBUG || GLOBAL_DEBUG) {                                                                                       \
        __android_log_print(ANDROID_LOG_ERROR, RENDERERNAME, __VA_ARGS__);                                             \
        printf(__VA_ARGS__);                                                                                           \
        printf("\n");                                                                                                  \
        write_log(__VA_ARGS__);                                                                                        \
    }
#define LOG_F(...)                                                                                                     \
    if (DEBUG || GLOBAL_DEBUG) {                                                                                       \
        __android_log_print(ANDROID_LOG_FATAL, RENDERERNAME, __VA_ARGS__);                                             \
        printf(__VA_ARGS__);                                                                                           \
        printf("\n");                                                                                                  \
        write_log(__VA_ARGS__);                                                                                        \
    }
#endif

#define LOG_V(...)                                                                                                     \
    {                                                                                                                  \
        __android_log_print(ANDROID_LOG_VERBOSE, RENDERERNAME, __VA_ARGS__);                                           \
        printf(__VA_ARGS__);                                                                                           \
        printf("\n");                                                                                                  \
        write_log(__VA_ARGS__);                                                                                        \
    }
#define LOG_I(...)                                                                                                     \
    {                                                                                                                  \
        __android_log_print(ANDROID_LOG_INFO, RENDERERNAME, __VA_ARGS__);                                              \
        printf(__VA_ARGS__);                                                                                           \
        printf("\n");                                                                                                  \
        write_log(__VA_ARGS__);                                                                                        \
    }
#define LOG_W_FORCE(...)                                                                                               \
    {                                                                                                                  \
        __android_log_print(ANDROID_LOG_WARN, RENDERERNAME, __VA_ARGS__);                                              \
        printf(__VA_ARGS__);                                                                                           \
        printf("\n");                                                                                                  \
        write_log(__VA_ARGS__);                                                                                        \
    }

#define MOBILEGLUES_LOG_H

#endif // MOBILEGLUES_LOG_H