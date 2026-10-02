/*
 * Copyright 2026 Google LLC
 * SPDX-License-Identifier: MIT
 */

#include "vkr_descriptor_heap.h"

#include "vn_protocol_renderer_descriptor_heap.h"

#include "vkr_context.h"
#include "vkr_device.h"

static void
vkr_dispatch_vkWriteSamplerDescriptorMESA(
   UNUSED struct vn_dispatch_context *dispatch,
   struct vn_command_vkWriteSamplerDescriptorMESA *args)
{
   struct vkr_device *dev = vkr_device_from_handle(args->device);
   struct vn_device_proc_table *vk = &dev->proc_table;

   vn_replace_vkWriteSamplerDescriptorMESA_args_handle(args);

   VkHostAddressRangeEXT descriptor = {
      .address = args->pData,
      .size = args->dataSize,
   };
   args->ret =
      vk->WriteSamplerDescriptorsEXT(args->device, 1, args->pSampler, &descriptor);
}

static void
vkr_dispatch_vkWriteResourceDescriptorMESA(
   UNUSED struct vn_dispatch_context *dispatch,
   struct vn_command_vkWriteResourceDescriptorMESA *args)
{
   struct vkr_device *dev = vkr_device_from_handle(args->device);
   struct vn_device_proc_table *vk = &dev->proc_table;

   vn_replace_vkWriteResourceDescriptorMESA_args_handle(args);

   VkHostAddressRangeEXT descriptor = {
      .address = args->pData,
      .size = args->dataSize,
   };
   args->ret =
      vk->WriteResourceDescriptorsEXT(args->device, 1, args->pResource, &descriptor);
}

static void
vkr_dispatch_vkGetImageOpaqueCaptureDataEXT(
   UNUSED struct vn_dispatch_context *dispatch,
   struct vn_command_vkGetImageOpaqueCaptureDataEXT *args)
{
   struct vkr_device *dev = vkr_device_from_handle(args->device);
   struct vn_device_proc_table *vk = &dev->proc_table;

   vn_replace_vkGetImageOpaqueCaptureDataEXT_args_handle(args);
   args->ret = vk->GetImageOpaqueCaptureDataEXT(args->device, args->imageCount,
                                                args->pImages, args->pDatas);
}

static void
vkr_dispatch_vkRegisterCustomBorderColorEXT(
   UNUSED struct vn_dispatch_context *dispatch,
   struct vn_command_vkRegisterCustomBorderColorEXT *args)
{
   struct vkr_device *dev = vkr_device_from_handle(args->device);
   struct vn_device_proc_table *vk = &dev->proc_table;

   vn_replace_vkRegisterCustomBorderColorEXT_args_handle(args);
   args->ret = vk->RegisterCustomBorderColorEXT(args->device, args->pBorderColor,
                                                args->requestIndex, args->pIndex);
}

static void
vkr_dispatch_vkUnregisterCustomBorderColorEXT(
   UNUSED struct vn_dispatch_context *dispatch,
   struct vn_command_vkUnregisterCustomBorderColorEXT *args)
{
   struct vkr_device *dev = vkr_device_from_handle(args->device);
   struct vn_device_proc_table *vk = &dev->proc_table;

   vn_replace_vkUnregisterCustomBorderColorEXT_args_handle(args);
   vk->UnregisterCustomBorderColorEXT(args->device, args->index);
}

void
vkr_context_init_descriptor_heap_dispatch(struct vkr_context *ctx)
{
   struct vn_dispatch_context *dispatch = &ctx->dispatch;

   dispatch->dispatch_vkWriteSamplerDescriptorMESA =
      vkr_dispatch_vkWriteSamplerDescriptorMESA;
   dispatch->dispatch_vkWriteResourceDescriptorMESA =
      vkr_dispatch_vkWriteResourceDescriptorMESA;
   dispatch->dispatch_vkGetImageOpaqueCaptureDataEXT =
      vkr_dispatch_vkGetImageOpaqueCaptureDataEXT;
   dispatch->dispatch_vkRegisterCustomBorderColorEXT =
      vkr_dispatch_vkRegisterCustomBorderColorEXT;
   dispatch->dispatch_vkUnregisterCustomBorderColorEXT =
      vkr_dispatch_vkUnregisterCustomBorderColorEXT;

   dispatch->dispatch_vkWriteSamplerDescriptorsEXT = NULL;
   dispatch->dispatch_vkWriteResourceDescriptorsEXT = NULL;
}
