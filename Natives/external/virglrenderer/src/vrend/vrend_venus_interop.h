/*
 * Copyright 2026 Collabora Limited
 * SPDX-License-Identifier: MIT
 */

#ifndef VREND_VENUS_INTEROP_H
#define VREND_VENUS_INTEROP_H

#include <stdbool.h>

#include "util/macros.h"

struct virgl_gbm_format_modifier;

#if defined(ENABLE_GBM_ALLOCATION) && !defined(MINIGBM) && defined(ENABLE_VENUS)
#include <gbm.h>

void vrend_init_venus_interop(struct gbm_device *gbm_dev);
void vrend_deinit_venus_interop(void);
bool vrend_has_venus_interop(void);
struct gbm_bo *
vrend_vk_gbm_bo_create(struct gbm_device *gbm_dev, uint32_t width, uint32_t height,
                       uint32_t gbm_format);
void vrend_vk_get_supported_formats(struct virgl_gbm_format_modifier *fmt_mod);
#else
struct gbm_device;
struct gbm_bo;

static inline void vrend_init_venus_interop(UNUSED struct gbm_device *gbm_dev) {}
static inline void vrend_deinit_venus_interop(void) {}
static inline bool vrend_has_venus_interop(void) { return false; }
static inline struct gbm_bo *
vrend_vk_gbm_bo_create(UNUSED struct gbm_device *gbm_dev,
                       UNUSED uint32_t width, UNUSED uint32_t height,
                       UNUSED uint32_t gbm_format)
{
   return NULL;
}
static inline void vrend_vk_get_supported_formats(UNUSED struct virgl_gbm_format_modifier *fmt_mod) {}
#endif

#endif
