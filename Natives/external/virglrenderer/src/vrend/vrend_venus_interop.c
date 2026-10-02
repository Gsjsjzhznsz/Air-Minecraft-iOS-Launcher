/*
 * Copyright 2026 Collabora Limited
 * SPDX-License-Identifier: MIT
 */

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <errno.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>
#include <dlfcn.h>

#include <drm_fourcc.h>

#include "vulkan/vulkan.h"

#include "vrend_venus_interop.h"

#include "virgl_util.h"
#include "virgl_hw.h"
#include "virgl_protocol.h"

static PFN_vkCreateInstance pfn_vkCreateInstance;
static PFN_vkDestroyInstance pfn_vkDestroyInstance;
static PFN_vkEnumeratePhysicalDevices pfn_vkEnumeratePhysicalDevices;
static PFN_vkGetPhysicalDeviceProperties2 pfn_vkGetPhysicalDeviceProperties2;
static PFN_vkGetPhysicalDeviceFormatProperties2 pfn_vkGetPhysicalDeviceFormatProperties2;
static PFN_vkGetPhysicalDeviceImageFormatProperties2 pfn_vkGetPhysicalDeviceImageFormatProperties2;
static PFN_vkGetPhysicalDeviceMemoryProperties pfn_vkGetPhysicalDeviceMemoryProperties;
static PFN_vkGetPhysicalDeviceQueueFamilyProperties pfn_vkGetPhysicalDeviceQueueFamilyProperties;
static PFN_vkCreateDevice pfn_vkCreateDevice;
static PFN_vkDestroyDevice pfn_vkDestroyDevice;
static PFN_vkGetDeviceProcAddr pfn_vkGetDeviceProcAddr;
static PFN_vkGetInstanceProcAddr pfn_vkGetInstanceProcAddr;

static void *g_vulkan_lib;

static bool g_vk_inited;
static VkInstance g_instance;
static VkPhysicalDevice g_phys;
static VkDevice g_dev;

static const struct {
    uint32_t gbm_format;
    VkFormat vk_format;
    uint32_t virgl_format;
} gbm_to_vk_conversions[] = {
    { GBM_FORMAT_RGB565, VK_FORMAT_B5G6R5_UNORM_PACK16, VIRGL_FORMAT_B5G6R5_UNORM },
    { GBM_FORMAT_ARGB8888, VK_FORMAT_B8G8R8A8_UNORM, VIRGL_FORMAT_B8G8R8A8_UNORM },
    { GBM_FORMAT_XRGB8888, VK_FORMAT_B8G8R8A8_UNORM, VIRGL_FORMAT_B8G8R8X8_UNORM },
    { GBM_FORMAT_ABGR2101010, VK_FORMAT_A2B10G10R10_UNORM_PACK32, VIRGL_FORMAT_R10G10B10A2_UNORM },
    { GBM_FORMAT_XBGR2101010, VK_FORMAT_A2B10G10R10_UNORM_PACK32, VIRGL_FORMAT_R10G10B10X2_UNORM },
    { GBM_FORMAT_ARGB2101010, VK_FORMAT_A2R10G10B10_UNORM_PACK32, VIRGL_FORMAT_B10G10R10A2_UNORM },
    { GBM_FORMAT_XRGB2101010, VK_FORMAT_A2R10G10B10_UNORM_PACK32, VIRGL_FORMAT_B10G10R10X2_UNORM },
    { GBM_FORMAT_ABGR16161616F, VK_FORMAT_R16G16B16A16_SFLOAT, VIRGL_FORMAT_R16G16B16A16_FLOAT },
    { GBM_FORMAT_XBGR16161616F, VK_FORMAT_R16G16B16A16_SFLOAT, VIRGL_FORMAT_R16G16B16X16_FLOAT },
#ifdef GBM_FORMAT_XBGR16161616
    { GBM_FORMAT_XBGR16161616, VK_FORMAT_R16G16B16A16_UNORM, VIRGL_FORMAT_R16G16B16X16_UNORM },
    { GBM_FORMAT_ABGR16161616, VK_FORMAT_R16G16B16A16_UNORM, VIRGL_FORMAT_R16G16B16A16_UNORM },
#endif
    { GBM_FORMAT_ABGR8888, VK_FORMAT_R8G8B8A8_UNORM, VIRGL_FORMAT_R8G8B8A8_UNORM },
    { GBM_FORMAT_XBGR8888, VK_FORMAT_R8G8B8A8_UNORM, VIRGL_FORMAT_R8G8B8X8_UNORM },
};

struct vrend_virgl_format_modifier {
    uint32_t virgl_format;
    uint32_t gbm_format;
    uint64_t modifier;
};

static struct vrend_virgl_format_modifier g_supported_formats[ARRAY_SIZE(gbm_to_vk_conversions)];
static uint32_t g_num_supported_formats;

struct mod_info {
   uint64_t modifier;
   uint32_t plane_count;
};

static struct mod_info *
query_modifier_infos(VkPhysicalDevice phys, VkFormat fmt, uint32_t *out_count)
{
   *out_count = 0;

   VkDrmFormatModifierPropertiesListEXT mod_list = {
      .sType = VK_STRUCTURE_TYPE_DRM_FORMAT_MODIFIER_PROPERTIES_LIST_EXT,
   };
   VkFormatProperties2 props2 = {
      .sType = VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2,
      .pNext = &mod_list,
   };

   pfn_vkGetPhysicalDeviceFormatProperties2(phys, fmt, &props2);
   if (mod_list.drmFormatModifierCount == 0)
      return NULL;

   VkDrmFormatModifierPropertiesEXT *mods =
      calloc(mod_list.drmFormatModifierCount, sizeof(*mods));
   if (!mods)
      return NULL;

   mod_list.pDrmFormatModifierProperties = mods;
   pfn_vkGetPhysicalDeviceFormatProperties2(phys, fmt, &props2);

   if (mod_list.drmFormatModifierCount == 0) {
      free(mods);
      return NULL;
   }

   struct mod_info *infos = calloc(mod_list.drmFormatModifierCount, sizeof(*infos));
   if (!infos) {
      free(mods);
      return NULL;
   }

   for (uint32_t i = 0; i < mod_list.drmFormatModifierCount; i++) {
      infos[i].modifier = mods[i].drmFormatModifier;
      infos[i].plane_count = mods[i].drmFormatModifierPlaneCount;
   }

   *out_count = mod_list.drmFormatModifierCount;
   free(mods);
   return infos;
}

static bool
check_modifier_image_format_support(VkPhysicalDevice phys, VkFormat fmt, uint64_t modifier)
{
   VkPhysicalDeviceImageDrmFormatModifierInfoEXT mod_info = {
      .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_DRM_FORMAT_MODIFIER_INFO_EXT,
      .drmFormatModifier = modifier,
      .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
   };

   VkPhysicalDeviceExternalImageFormatInfo ext_img_info = {
      .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTERNAL_IMAGE_FORMAT_INFO,
      .pNext = &mod_info,
      .handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT,
   };

   VkPhysicalDeviceImageFormatInfo2 fmt_info = {
      .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_FORMAT_INFO_2,
      .pNext = &ext_img_info,
      .format = fmt,
      .type = VK_IMAGE_TYPE_2D,
      .tiling = VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT,
      .usage = VK_IMAGE_USAGE_SAMPLED_BIT |
               VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
               VK_IMAGE_USAGE_TRANSFER_DST_BIT |
               VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
      .flags = 0,
   };

   VkExternalImageFormatProperties ext_props = {
      .sType = VK_STRUCTURE_TYPE_EXTERNAL_IMAGE_FORMAT_PROPERTIES,
   };

   VkImageFormatProperties2 props2 = {
      .sType = VK_STRUCTURE_TYPE_IMAGE_FORMAT_PROPERTIES_2,
      .pNext = &ext_props,
   };

   VkResult vr = pfn_vkGetPhysicalDeviceImageFormatProperties2(phys, &fmt_info, &props2);
   if (vr != VK_SUCCESS)
      return false;

   const VkExternalMemoryFeatureFlags required =
      VK_EXTERNAL_MEMORY_FEATURE_EXPORTABLE_BIT;

   return (ext_props.externalMemoryProperties.externalMemoryFeatures & required) == required;
}

static void init_supported_formats(void)
{
    memset(g_supported_formats, 0, sizeof(g_supported_formats));
    g_num_supported_formats = 0;

    for (size_t i = 0; i < ARRAY_SIZE(gbm_to_vk_conversions); i++) {
        uint32_t gbm_format = gbm_to_vk_conversions[i].gbm_format;
        VkFormat vk_fmt = gbm_to_vk_conversions[i].vk_format;

        uint32_t mod_count = 0;
        struct mod_info *mods = query_modifier_infos(g_phys, vk_fmt, &mod_count);
        if (!mods)
            continue;

        for (uint32_t mi = 0; mi < mod_count; mi++) {
            uint64_t mod = mods[mi].modifier;

            if (mod == DRM_FORMAT_MOD_LINEAR)
                continue;

            /*
             * Mesa EGL requires format planes == memory planes
             * https://elixir.bootlin.com/mesa/mesa-26.0.5/source/src/egl/drivers/dri2/egl_dri2.c#L2273
             *
             * AMD VK driver has modifier that uses disjoint CCS planes for RGBA,
             * which conflicts with Mesa's requirement.
             */
            if (mods[mi].plane_count != 1)
                continue;

            if (!check_modifier_image_format_support(g_phys, vk_fmt, mod))
                continue;

            virgl_debug("%s: gbm_format=0x%08x picked modifier 0x%016" PRIx64"\n",
                        __func__, gbm_format, mod);

            g_supported_formats[g_num_supported_formats].virgl_format =
                gbm_to_vk_conversions[i].virgl_format;
            g_supported_formats[g_num_supported_formats].gbm_format = gbm_format;
            g_supported_formats[g_num_supported_formats].modifier = mod;
            g_num_supported_formats++;
            break; /* one (best) modifier per format is enough */
        }

        free(mods);
    }
}

static uint64_t
pick_gbm_format_modifier(uint32_t gbm_format, uint64_t *out_modifier)
{
    for (size_t i = 0; i < ARRAY_SIZE(g_supported_formats); i++) {
        if (g_supported_formats[i].gbm_format == gbm_format) {
            *out_modifier = g_supported_formats[i].modifier;
            return true;
        }
    }
    return false;
}

static bool
load_vulkan_library(void)
{
    if (g_vulkan_lib)
        return true;

    g_vulkan_lib = dlopen("libvulkan.so.1", RTLD_NOW | RTLD_LOCAL);
    if (!g_vulkan_lib)
        g_vulkan_lib = dlopen("libvulkan.so", RTLD_NOW | RTLD_LOCAL);

    if (!g_vulkan_lib) {
        virgl_error("%s: Failed to load libvulkan.so: %s\n", __func__, dlerror());
        return false;
    }

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wpedantic"
    pfn_vkCreateInstance = (PFN_vkCreateInstance)dlsym(g_vulkan_lib, "vkCreateInstance");
    pfn_vkDestroyInstance = (PFN_vkDestroyInstance)dlsym(g_vulkan_lib, "vkDestroyInstance");
    pfn_vkEnumeratePhysicalDevices = (PFN_vkEnumeratePhysicalDevices)dlsym(g_vulkan_lib, "vkEnumeratePhysicalDevices");
    pfn_vkGetPhysicalDeviceProperties2 = (PFN_vkGetPhysicalDeviceProperties2)dlsym(g_vulkan_lib, "vkGetPhysicalDeviceProperties2");
    pfn_vkGetPhysicalDeviceFormatProperties2 = (PFN_vkGetPhysicalDeviceFormatProperties2)dlsym(g_vulkan_lib, "vkGetPhysicalDeviceFormatProperties2");
    pfn_vkGetPhysicalDeviceMemoryProperties = (PFN_vkGetPhysicalDeviceMemoryProperties)dlsym(g_vulkan_lib, "vkGetPhysicalDeviceMemoryProperties");
    pfn_vkGetPhysicalDeviceQueueFamilyProperties = (PFN_vkGetPhysicalDeviceQueueFamilyProperties)dlsym(g_vulkan_lib, "vkGetPhysicalDeviceQueueFamilyProperties");
    pfn_vkCreateDevice = (PFN_vkCreateDevice)dlsym(g_vulkan_lib, "vkCreateDevice");
    pfn_vkDestroyDevice = (PFN_vkDestroyDevice)dlsym(g_vulkan_lib, "vkDestroyDevice");
    pfn_vkGetDeviceProcAddr = (PFN_vkGetDeviceProcAddr)dlsym(g_vulkan_lib, "vkGetDeviceProcAddr");
    pfn_vkGetInstanceProcAddr = (PFN_vkGetInstanceProcAddr)dlsym(g_vulkan_lib, "vkGetInstanceProcAddr");
#pragma GCC diagnostic pop

    if (!pfn_vkCreateInstance || !pfn_vkDestroyInstance ||
        !pfn_vkEnumeratePhysicalDevices || !pfn_vkGetPhysicalDeviceProperties2 ||
        !pfn_vkGetPhysicalDeviceFormatProperties2 || !pfn_vkGetPhysicalDeviceMemoryProperties ||
        !pfn_vkGetPhysicalDeviceQueueFamilyProperties || !pfn_vkCreateDevice ||
        !pfn_vkDestroyDevice || !pfn_vkGetDeviceProcAddr || !pfn_vkGetInstanceProcAddr) {
        virgl_error("%s: Failed to load required Vulkan symbols\n", __func__);
        dlclose(g_vulkan_lib);
        g_vulkan_lib = NULL;
        return false;
    }

    return true;
}

static bool
get_gbm_fd_major_minor(struct gbm_device *gbm_dev, unsigned *out_major, unsigned *out_minor)
{
   int fd = gbm_device_get_fd(gbm_dev);
   if (fd < 0)
      return false;

   struct stat st;
   if (fstat(fd, &st) != 0) {
      virgl_error("%s: failed fstat(gbm_fd)\n", __func__);
      return false;
   }

   *out_major = major(st.st_rdev);
   *out_minor = minor(st.st_rdev);
   return true;
}

static VkPhysicalDevice
pick_physdev_matching_gbm(struct gbm_device *gbm_dev, VkInstance instance)
{
   unsigned gbm_major = 0, gbm_minor = 0;
   if (!get_gbm_fd_major_minor(gbm_dev, &gbm_major, &gbm_minor)) {
      virgl_error("%s: failed to get gbm fd major/minor\n", __func__);
      return VK_NULL_HANDLE;
   }

   uint32_t count = 0;
   pfn_vkEnumeratePhysicalDevices(instance, &count, NULL);
   if (!count)
      return VK_NULL_HANDLE;

   VkPhysicalDevice *devs = calloc(count, sizeof(*devs));
   if (!devs)
      return VK_NULL_HANDLE;

   pfn_vkEnumeratePhysicalDevices(instance, &count, devs);

   VkPhysicalDevice chosen = VK_NULL_HANDLE;
   for (uint32_t i = 0; i < count; i++) {
      VkPhysicalDeviceDrmPropertiesEXT drm = {
         .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRM_PROPERTIES_EXT,
      };
      VkPhysicalDeviceProperties2 props2 = {
         .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2,
         .pNext = &drm,
      };

      pfn_vkGetPhysicalDeviceProperties2(devs[i], &props2);

      bool match =
         (drm.hasRender && drm.renderMajor == gbm_major && drm.renderMinor == gbm_minor) ||
         (drm.hasPrimary && drm.primaryMajor == gbm_major && drm.primaryMinor == gbm_minor);

      if (match) {
         chosen = devs[i];
         break;
      }
   }

   free(devs);
   return chosen;
}

void vrend_init_venus_interop(struct gbm_device *gbm_dev)
{
   if (!gbm_dev) {
      virgl_debug("%s: gbm_dev is NULL\n", __func__);
      return;
   }

   unsigned gbm_major = 0, gbm_minor = 0;
   if (!get_gbm_fd_major_minor(gbm_dev, &gbm_major, &gbm_minor)) {
      virgl_error("%s: failed to get gbm fd major/minor\n", __func__);
      return;
   }

   if (g_vk_inited)
      return;

   if (!load_vulkan_library()) {
      virgl_error("%s: Failed to load Vulkan library\n", __func__);
      return;
   }

   const char *inst_exts[] = {
      VK_KHR_GET_PHYSICAL_DEVICE_PROPERTIES_2_EXTENSION_NAME,
   };

   VkApplicationInfo app = {
      .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
      .pApplicationName = "vrend-venus-integration",
      .apiVersion = VK_API_VERSION_1_1,
   };

   VkInstanceCreateInfo ici = {
      .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
      .pApplicationInfo = &app,
      .enabledExtensionCount = ARRAY_SIZE(inst_exts),
      .ppEnabledExtensionNames = inst_exts,
   };

   VkResult vr = pfn_vkCreateInstance(&ici, NULL, &g_instance);
   if (vr != VK_SUCCESS) {
      virgl_error("%s: vkCreateInstance failed (VkResult=%d)\n", __func__, vr);
      return;
   }

   pfn_vkGetPhysicalDeviceProperties2 =
      (PFN_vkGetPhysicalDeviceProperties2)pfn_vkGetInstanceProcAddr(g_instance, "vkGetPhysicalDeviceProperties2");
   pfn_vkGetPhysicalDeviceFormatProperties2 =
      (PFN_vkGetPhysicalDeviceFormatProperties2)pfn_vkGetInstanceProcAddr(g_instance, "vkGetPhysicalDeviceFormatProperties2");
   pfn_vkGetPhysicalDeviceImageFormatProperties2 =
      (PFN_vkGetPhysicalDeviceImageFormatProperties2)pfn_vkGetInstanceProcAddr(g_instance, "vkGetPhysicalDeviceImageFormatProperties2");

   if (!pfn_vkGetPhysicalDeviceProperties2 || !pfn_vkGetPhysicalDeviceFormatProperties2 ||
       !pfn_vkGetPhysicalDeviceImageFormatProperties2) {
      virgl_error("%s: required instance procs missing\n", __func__);
      goto fail_instance;
   }

   g_phys = pick_physdev_matching_gbm(gbm_dev, g_instance);
   if (g_phys == VK_NULL_HANDLE) {
      virgl_error("%s: no VkPhysicalDevice matches gbm fd\n", __func__);
      goto fail_instance;
   }

   uint32_t qf_count = 0;
   pfn_vkGetPhysicalDeviceQueueFamilyProperties(g_phys, &qf_count, NULL);
   if (!qf_count) {
      virgl_error("%s: no queue families found\n", __func__);
      goto fail_instance;
   }

   VkQueueFamilyProperties *qfp = calloc(qf_count, sizeof(*qfp));
   if (!qfp)
      goto fail_instance;

   pfn_vkGetPhysicalDeviceQueueFamilyProperties(g_phys, &qf_count, qfp);

   uint32_t qfam = UINT32_MAX;
   for (uint32_t i = 0; i < qf_count; i++) {
      if (qfp[i].queueCount > 0) {
         qfam = i;
         break;
      }
   }
   free(qfp);

   if (qfam == UINT32_MAX) {
      virgl_error("%s: no queue family found\n", __func__);
      goto fail_instance;
   }

   float prio = 1.0f;
   VkDeviceQueueCreateInfo dqci = {
      .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
      .queueFamilyIndex = qfam,
      .queueCount = 1,
      .pQueuePriorities = &prio,
   };

   const char *dev_exts[] = {
      VK_KHR_EXTERNAL_MEMORY_EXTENSION_NAME,
      VK_KHR_EXTERNAL_MEMORY_FD_EXTENSION_NAME,
      VK_EXT_EXTERNAL_MEMORY_DMA_BUF_EXTENSION_NAME,
      VK_EXT_IMAGE_DRM_FORMAT_MODIFIER_EXTENSION_NAME,
   };

   VkDeviceCreateInfo dci = {
      .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
      .queueCreateInfoCount = 1,
      .pQueueCreateInfos = &dqci,
      .enabledExtensionCount = (uint32_t)(sizeof(dev_exts) / sizeof(dev_exts[0])),
      .ppEnabledExtensionNames = dev_exts,
   };

   vr = pfn_vkCreateDevice(g_phys, &dci, NULL, &g_dev);
   if (vr != VK_SUCCESS) {
      virgl_error("%s: vkCreateDevice failed (VkResult=%d)\n", __func__, vr);
      goto fail_instance;
   }

   init_supported_formats();

   g_vk_inited = true;

   return;

fail_instance:
   pfn_vkDestroyInstance(g_instance, NULL);
   g_instance = VK_NULL_HANDLE;
   g_phys = VK_NULL_HANDLE;
   pfn_vkGetPhysicalDeviceFormatProperties2 = NULL;
   pfn_vkGetPhysicalDeviceImageFormatProperties2 = NULL;
   pfn_vkGetPhysicalDeviceProperties2 = NULL;
}

void vrend_deinit_venus_interop(void)
{
   if (!g_vk_inited)
      return;

   if (g_dev != VK_NULL_HANDLE)
      pfn_vkDestroyDevice(g_dev, NULL);
   if (g_instance != VK_NULL_HANDLE)
      pfn_vkDestroyInstance(g_instance, NULL);

   if (g_vulkan_lib) {
      dlclose(g_vulkan_lib);
      g_vulkan_lib = NULL;
   }

   g_vk_inited = false;
   g_instance = VK_NULL_HANDLE;
   g_phys = VK_NULL_HANDLE;
   g_dev = VK_NULL_HANDLE;
   g_num_supported_formats = 0;

   pfn_vkCreateInstance = NULL;
   pfn_vkDestroyInstance = NULL;
   pfn_vkEnumeratePhysicalDevices = NULL;
   pfn_vkGetPhysicalDeviceProperties2 = NULL;
   pfn_vkGetPhysicalDeviceFormatProperties2 = NULL;
   pfn_vkGetPhysicalDeviceImageFormatProperties2 = NULL;
   pfn_vkGetPhysicalDeviceMemoryProperties = NULL;
   pfn_vkGetPhysicalDeviceQueueFamilyProperties = NULL;
   pfn_vkCreateDevice = NULL;
   pfn_vkDestroyDevice = NULL;
   pfn_vkGetDeviceProcAddr = NULL;
   pfn_vkGetInstanceProcAddr = NULL;
}

bool vrend_has_venus_interop(void)
{
    return g_vk_inited;
}

struct gbm_bo *
vrend_vk_gbm_bo_create(struct gbm_device *gbm_dev, uint32_t width, uint32_t height,
                       uint32_t gbm_format)
{
    if (!g_vk_inited)
        return NULL;

    uint64_t mod = 0;
    if (pick_gbm_format_modifier(gbm_format, &mod)) {
        struct gbm_bo *bo = gbm_bo_create_with_modifiers(gbm_dev, width, height,
                                                         gbm_format, &mod, 1);
        if (bo) {
            virgl_debug("%s: gbm_bo_create_with_modifiers success mod=0x%016" PRIx64
                        " gbm_format=0x%08x %ux%u\n",
                        __func__, mod, gbm_format, width, height);
            return bo;
        }

        virgl_error("%s: gbm_bo_create_with_modifiers failed for mod=0x%016" PRIx64
                        " gbm_format=0x%08x %ux%u\n",
                    __func__, mod, gbm_format, width, height);
    } else {
        virgl_debug("%s: unsupported gbm_format=0x%08x\n", __func__, gbm_format);
    }

    return NULL;
}

void vrend_vk_get_supported_formats(struct virgl_gbm_format_modifier *fmt_mod)
{
    for (size_t i = 0; i < g_num_supported_formats; i++) {
        fmt_mod->formats[i].virgl_format = g_supported_formats[i].virgl_format;
        fmt_mod->formats[i].modifier = g_supported_formats[i].modifier;
    }

    fmt_mod->num = g_num_supported_formats;
}
