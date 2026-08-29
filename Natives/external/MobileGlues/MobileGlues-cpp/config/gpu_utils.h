// MobileGlues - config/gpu_utils.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#ifndef MOBILEGLUES_PLUGIN_GPU_UTILS_H
#define MOBILEGLUES_PLUGIN_GPU_UTILS_H

#include <string.h>
#include <string>

std::string getGPUInfo();

#ifdef __cplusplus
extern "C"
{
#endif

    int isAdreno(const char* gpu);

    int isAdreno730(const char* gpu);

    int isAdreno740(const char* gpu);

    int isAdreno830(const char* gpu);

    int hasVulkan12();

    bool checkIfANGLESupported(const char* gpu);

#ifdef __cplusplus
}
#endif

#endif // MOBILEGLUES_PLUGIN_GPU_UTILS_H
