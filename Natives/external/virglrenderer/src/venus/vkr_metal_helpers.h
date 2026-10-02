/*
 * Copyright 2026 Lucas Amaral
 * SPDX-License-Identifier: MIT
 */

#ifndef VKR_METAL_HELPERS_H
#define VKR_METAL_HELPERS_H

#include <stddef.h>

/*
 * Metal shared memory (opaque, allocated/freed in vkr_metal_helpers.m)
 */
struct vkr_mtl_shm {
   int shm_fd;
   void *shm_ptr;
   size_t shm_size;
   void *mtl_buffer;
};

#ifdef __APPLE__

#include <stdint.h>

/*
 * Metal helper functions (implemented in vkr_metal_helpers.m)
 */

/* Return the MTLDevice backing a VkDevice.
 * Uses vkExportMetalObjectsEXT to query the device, or NULL on failure.
 */
void *
vkr_metal_get_device(VkDevice vk_device, PFN_vkGetDeviceProcAddr GetDeviceProcAddr);

/* Allocate Metal shared memory: create anonymous SHM file, mmap it,
 * wrap as MTLBuffer.  Returns a populated vkr_mtl_shm, or NULL on failure.
 * Caller must free with vkr_mtl_shm_free().
 */
struct vkr_mtl_shm *
vkr_mtl_shm_alloc(void *mtl_device, uint64_t size);

/* Release all resources held by a vkr_mtl_shm and free the struct. */
void
vkr_mtl_shm_free(struct vkr_mtl_shm *shm);

#else /* !__APPLE__ */

static inline void *
vkr_metal_get_device(VkDevice vk_device, PFN_vkGetDeviceProcAddr GetDeviceProcAddr)
{
   (void)vk_device;
   (void)GetDeviceProcAddr;
   return NULL;
}

static inline struct vkr_mtl_shm *
vkr_mtl_shm_alloc(void *mtl_device, uint64_t size)
{
   (void)mtl_device;
   (void)size;
   return NULL;
}

static inline void
vkr_mtl_shm_free(struct vkr_mtl_shm *shm)
{
   (void)shm;
}

#endif /* __APPLE__ */

#endif /* VKR_METAL_HELPERS_H */
