// MobileGlues - config/config.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header
#ifndef _MOBILEGLUES_CONFIG_H_
#define _MOBILEGLUES_CONFIG_H_

#ifdef __cplusplus
extern "C"
{
#endif

    extern char* mg_directory_path;
    extern char* config_file_path;
    extern char* log_file_path;
    extern char* glsl_cache_file_path;

    extern int initialized;

    char* concatenate(char* str1, char* str2);

    int check_path();

    int config_refresh();
    int config_get_int(char* name);
    char* config_get_string(char* name);
    void config_cleanup();

#ifdef __cplusplus
}
#endif

extern bool is_custom_mg_dir;

#endif // _MOBILEGLUES_CONFIG_H_
