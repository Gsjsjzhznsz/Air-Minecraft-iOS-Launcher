/*
 * Copyright 2026 Lucas Amaral
 * SPDX-License-Identifier: MIT
 */

#ifdef __APPLE__

#include "vkr_common.h"

#import <Metal/Metal.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

#include "util/anon_file.h"
#include "vulkan/vulkan_metal.h"

#include "vkr_metal_helpers.h"

void *
vkr_metal_get_device(VkDevice vk_device, PFN_vkGetDeviceProcAddr GetDeviceProcAddr)
{
   PFN_vkExportMetalObjectsEXT pfn = (PFN_vkExportMetalObjectsEXT)GetDeviceProcAddr(
      vk_device, "vkExportMetalObjectsEXT");
   if (!pfn)
      return NULL;

   VkExportMetalDeviceInfoEXT device_info = {
      .sType = VK_STRUCTURE_TYPE_EXPORT_METAL_DEVICE_INFO_EXT,
   };
   VkExportMetalObjectsInfoEXT export_info = {
      .sType = VK_STRUCTURE_TYPE_EXPORT_METAL_OBJECTS_INFO_EXT,
      .pNext = &device_info,
   };
   pfn(vk_device, &export_info);
   return (void *)device_info.mtlDevice;
}

struct vkr_mtl_shm *
vkr_mtl_shm_alloc(void *mtl_device, uint64_t size)
{
   if (!mtl_device)
      return NULL;

   const size_t page_size = getpagesize();
   const size_t aligned_size = (size + page_size - 1) & ~(page_size - 1);

   int shm_fd = os_create_anonymous_file(aligned_size, "vkr-metal-mem");
   if (shm_fd < 0)
      return NULL;

   void *shm_ptr =
      mmap(NULL, aligned_size, PROT_READ | PROT_WRITE, MAP_SHARED, shm_fd, 0);
   if (shm_ptr == MAP_FAILED) {
      close(shm_fd);
      return NULL;
   }

   id<MTLDevice> device = (id<MTLDevice>)mtl_device;
   id<MTLBuffer> buffer = [device newBufferWithBytesNoCopy:shm_ptr
                                                    length:aligned_size
                                                   options:MTLResourceStorageModeShared
                                               deallocator:nil];
   if (!buffer) {
      munmap(shm_ptr, aligned_size);
      close(shm_fd);
      return NULL;
   }

   struct vkr_mtl_shm *shm = calloc(1, sizeof(*shm));
   if (!shm) {
      CFRelease(buffer);
      munmap(shm_ptr, aligned_size);
      close(shm_fd);
      return NULL;
   }

   shm->shm_fd = shm_fd;
   shm->shm_ptr = shm_ptr;
   shm->shm_size = aligned_size;
   shm->mtl_buffer = (void *)buffer;
   return shm;
}

void
vkr_mtl_shm_free(struct vkr_mtl_shm *shm)
{
   if (!shm)
      return;
   if (shm->mtl_buffer)
      CFRelease(shm->mtl_buffer);
   if (shm->shm_ptr)
      munmap(shm->shm_ptr, shm->shm_size);
   if (shm->shm_fd >= 0)
      close(shm->shm_fd);
   free(shm);
}

#endif /* __APPLE__ */
