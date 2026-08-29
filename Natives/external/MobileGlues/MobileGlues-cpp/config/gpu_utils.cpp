// MobileGlues - config/gpu_utils.cpp
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#include "gpu_utils.h"
#include "../gles/loader.h"
#if !defined(__APPLE__)
#include "vulkan/vulkan.h"
#endif

#include <EGL/egl.h>
#include <cstring>
#include <optional>
typedef const char* cstr;
// open_lib() below hands these to dlopen() verbatim, unlike the loader in gles/loader.cpp which appends a
// platform extension itself. Without the ".so" every dlopen here fails, getGPUInfo() returns an empty string
// and hasVulkan12() returns 0 on every device.
static const cstr gles3_lib[] = {"libGLESv3_CM.so", "libGLESv3.so", nullptr};
static const cstr egl_libs[] = {"libEGL.so", nullptr};
static const cstr vk_lib[] = {"libvulkan.so", nullptr};

namespace egl_func {
    PFNEGLGETDISPLAYPROC eglGetDisplay = nullptr;
    PFNEGLINITIALIZEPROC eglInitialize = nullptr;
    PFNEGLCHOOSECONFIGPROC eglChooseConfig = nullptr;
    PFNEGLCREATECONTEXTPROC eglCreateContext = nullptr;
    PFNEGLMAKECURRENTPROC eglMakeCurrent = nullptr;
    PFNEGLDESTROYCONTEXTPROC eglDestroyContext = nullptr;
    PFNEGLTERMINATEPROC eglTerminate = nullptr;
} // namespace egl_func

template <typename T>
static void* open_lib(const T names[], const char* override) {
    void* handle = nullptr;
    int flags = RTLD_LOCAL | RTLD_NOW;
    if (override) {
        handle = dlopen(override, flags);
        if (handle) return handle;
    }
    for (int i = 0; names[i]; ++i) {
        handle = dlopen(names[i], flags);
        if (handle) break;
    }
    return handle;
}

static bool loadEGLFunctions(void* lib) {
    if (!lib) return false;
    egl_func::eglGetDisplay = (PFNEGLGETDISPLAYPROC)dlsym(lib, "eglGetDisplay");
    egl_func::eglInitialize = (PFNEGLINITIALIZEPROC)dlsym(lib, "eglInitialize");
    egl_func::eglChooseConfig = (PFNEGLCHOOSECONFIGPROC)dlsym(lib, "eglChooseConfig");
    egl_func::eglCreateContext = (PFNEGLCREATECONTEXTPROC)dlsym(lib, "eglCreateContext");
    egl_func::eglMakeCurrent = (PFNEGLMAKECURRENTPROC)dlsym(lib, "eglMakeCurrent");
    egl_func::eglDestroyContext = (PFNEGLDESTROYCONTEXTPROC)dlsym(lib, "eglDestroyContext");
    egl_func::eglTerminate = (PFNEGLTERMINATEPROC)dlsym(lib, "eglTerminate");

    return egl_func::eglGetDisplay && egl_func::eglInitialize && egl_func::eglChooseConfig &&
           egl_func::eglCreateContext && egl_func::eglMakeCurrent && egl_func::eglDestroyContext &&
           egl_func::eglTerminate;
}

std::string getGPUInfo() {
    void* egllib = open_lib(egl_libs, nullptr);
    if (!loadEGLFunctions(egllib)) {
        if (egllib) dlclose(egllib);
        return std::string();
    }

    EGLDisplay display = egl_func::eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (display == EGL_NO_DISPLAY) {
        egl_func::eglTerminate(display);
        dlclose(egllib);
        return std::string();
    }
    if (egl_func::eglInitialize(display, nullptr, nullptr) != EGL_TRUE) {
        egl_func::eglTerminate(display);
        dlclose(egllib);
        return std::string();
    }

    const EGLint attribs[] = {EGL_BLUE_SIZE,
                              8,
                              EGL_GREEN_SIZE,
                              8,
                              EGL_RED_SIZE,
                              8,
                              EGL_ALPHA_SIZE,
                              8,
                              EGL_DEPTH_SIZE,
                              24,
                              EGL_SURFACE_TYPE,
                              EGL_PBUFFER_BIT,
                              EGL_RENDERABLE_TYPE,
                              EGL_OPENGL_ES2_BIT,
                              EGL_NONE};
    EGLint numConfigs = 0;
    if (egl_func::eglChooseConfig(display, attribs, nullptr, 0, &numConfigs) != EGL_TRUE || numConfigs == 0) {
        egl_func::eglTerminate(display);
        dlclose(egllib);
        return std::string();
    }
    EGLConfig config;
    egl_func::eglChooseConfig(display, attribs, &config, 1, &numConfigs);

    const EGLint ctxAttribs[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
    EGLContext ctx = egl_func::eglCreateContext(display, config, EGL_NO_CONTEXT, ctxAttribs);
    if (ctx == EGL_NO_CONTEXT) {
        egl_func::eglTerminate(display);
        dlclose(egllib);
        return std::string();
    }

    if (egl_func::eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx) != EGL_TRUE) {
        egl_func::eglDestroyContext(display, ctx);
        egl_func::eglTerminate(display);
        dlclose(egllib);
        return std::string();
    }

    void* glesLib = open_lib(gles3_lib, nullptr);
    std::string renderer;
    if (glesLib) {
        auto glGetString = (const GLubyte* (*)(GLenum))dlsym(glesLib, "glGetString");
        if (glGetString) {
            // Now that the GLES library actually opens, this call runs for the first time; a driver that answers
            // GL_RENDERER with null would otherwise construct the string from a null pointer.
            const GLubyte* name = glGetString(GL_RENDERER);
            if (name) renderer = reinterpret_cast<const char*>(name);
        }
        dlclose(glesLib);
    }

    egl_func::eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    egl_func::eglDestroyContext(display, ctx);
    egl_func::eglTerminate(display);
    dlclose(egllib);

    return renderer;
}

int isAdreno(const char* gpu) {
    //    const char* gpu = getGPUInfo();
    if (!gpu) return 0;
    return strstr(gpu, "Adreno") != nullptr;
}

int isAdreno740(const char* gpu) {
    //    const char* gpu = getGPUInfo();
    if (!gpu) return 0;
    return isAdreno(gpu) && (strstr(gpu, "740") != nullptr);
}

int isAdreno730(const char* gpu) {
    //    const char* gpu = getGPUInfo();
    if (!gpu) return 0;
    return isAdreno(gpu) && (strstr(gpu, "730") != nullptr);
}

bool checkIfANGLESupported(const char* gpu) {
    return !isAdreno730(gpu) && !isAdreno740(gpu) && hasVulkan12();
}

int isAdreno830(const char* gpu) {
    //    const char* gpu = getGPUInfo();
    if (!gpu) return 0;
    return isAdreno(gpu) && (strstr(gpu, "830") != nullptr);
}

static std::optional<int> hasVk12;
int hasVulkan12() {
    if (hasVk12.has_value()) return hasVk12.value();
    void* vulkan_lib = open_lib(vk_lib, nullptr);
    if (!vulkan_lib) return 0;

#ifndef __APPLE__

    typedef VkResult (*PFN_vkEnumerateInstanceExtensionProperties)(const char*, uint32_t*, VkExtensionProperties*);
    typedef VkResult (*PFN_vkCreateInstance)(const VkInstanceCreateInfo*, const VkAllocationCallbacks*, VkInstance*);
    typedef void (*PFN_vkDestroyInstance)(VkInstance, const VkAllocationCallbacks*);
    typedef VkResult (*PFN_vkEnumeratePhysicalDevices)(VkInstance, uint32_t*, VkPhysicalDevice*);
    typedef void (*PFN_vkGetPhysicalDeviceProperties)(VkPhysicalDevice, VkPhysicalDeviceProperties*);

    auto vkEnumerateInstanceExtensionProperties =
        (PFN_vkEnumerateInstanceExtensionProperties)dlsym(vulkan_lib, "vkEnumerateInstanceExtensionProperties");
    auto vkCreateInstance = (PFN_vkCreateInstance)dlsym(vulkan_lib, "vkCreateInstance");
    auto vkDestroyInstance = (PFN_vkDestroyInstance)dlsym(vulkan_lib, "vkDestroyInstance");
    auto vkEnumeratePhysicalDevices = (PFN_vkEnumeratePhysicalDevices)dlsym(vulkan_lib, "vkEnumeratePhysicalDevices");
    auto vkGetPhysicalDeviceProperties =
        (PFN_vkGetPhysicalDeviceProperties)dlsym(vulkan_lib, "vkGetPhysicalDeviceProperties");

    // Everything below runs to a single exit: the early returns this used to take left the library open and,
    // on the success path, leaked the physical-device array as well.
    int found = 0;
    bool instanceCreated = false;
    VkInstance instance = VK_NULL_HANDLE;
    VkPhysicalDevice* physicalDevices = nullptr;
    uint32_t instanceExtensionCount = 0;
    uint32_t gpuCount = 0;

    bool haveEntryPoints = vkEnumerateInstanceExtensionProperties && vkCreateInstance && vkDestroyInstance &&
                           vkEnumeratePhysicalDevices && vkGetPhysicalDeviceProperties;

    VkApplicationInfo appInfo = {};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pNext = nullptr;
    appInfo.pApplicationName = "Vulkan Check";
    appInfo.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.pEngineName = "MobileGlues";
    appInfo.engineVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.apiVersion = VK_API_VERSION_1_3;

    VkInstanceCreateInfo createInfo = {};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pNext = nullptr;
    createInfo.flags = 0;
    createInfo.pApplicationInfo = &appInfo;
    createInfo.enabledLayerCount = 0;
    createInfo.ppEnabledLayerNames = nullptr;
    createInfo.enabledExtensionCount = 0;
    createInfo.ppEnabledExtensionNames = nullptr;

    if (haveEntryPoints &&
        vkEnumerateInstanceExtensionProperties(nullptr, &instanceExtensionCount, nullptr) == VK_SUCCESS &&
        vkCreateInstance(&createInfo, nullptr, &instance) == VK_SUCCESS) {
        instanceCreated = true;
        if (vkEnumeratePhysicalDevices(instance, &gpuCount, nullptr) == VK_SUCCESS && gpuCount > 0) {
            physicalDevices = (VkPhysicalDevice*)malloc(sizeof(VkPhysicalDevice) * gpuCount);
            // A null malloc used to be handed straight to the driver, which writes gpuCount handles through it.
            if (physicalDevices && vkEnumeratePhysicalDevices(instance, &gpuCount, physicalDevices) == VK_SUCCESS) {
                for (uint32_t i = 0; i < gpuCount; i++) {
                    VkPhysicalDeviceProperties deviceProperties;
                    vkGetPhysicalDeviceProperties(physicalDevices[i], &deviceProperties);

                    if (deviceProperties.apiVersion >= VK_API_VERSION_1_2) {
                        found = 1;
                        break;
                    }
                }
            }
        }
    }

    free(physicalDevices);
    if (instanceCreated) vkDestroyInstance(instance, nullptr);
    dlclose(vulkan_lib);

    hasVk12 = found;
    return found;

#else

    dlclose(vulkan_lib);
    hasVk12 = 0;
    return 0;

#endif
}