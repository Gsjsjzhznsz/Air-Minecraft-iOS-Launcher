// MobileGlues - glx/lookup.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#ifndef MOBILEGLUES_LOOKUP_H
#define MOBILEGLUES_LOOKUP_H

#ifdef __cplusplus
extern "C"
{
#endif

#include <GL/gl.h>

    GLAPI GLAPIENTRY void* glXGetProcAddress(const char* name);
    GLAPI GLAPIENTRY void* glXGetProcAddressARB(const char* name);

#ifdef __cplusplus
}
#endif

#endif // MOBILEGLUES_LOOKUP_H
