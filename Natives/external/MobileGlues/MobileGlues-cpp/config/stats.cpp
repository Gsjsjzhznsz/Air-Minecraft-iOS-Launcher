// MobileGlues - config/stats.cpp
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header
#include "stats.h"

#include "../gl/envvars.h"
#include "../gl/log.h"
#include "../gl/mg.h"
#include "cJSON.h"
#include "config.h"
#include <climits>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DEBUG 0

char* stats_file_path = nullptr;

// The whole file is one small JSON object so that a later counter can be added
// without invalidating the ones already on disk. Unknown keys are carried over
// on write for the same reason: an older library must not silently drop what a
// newer one recorded.
static const char* LAUNCH_COUNT_KEY = "launchCount";

// Opt in, not out: this library gets loaded by benchmarks, by tools and by the
// plugin app itself, and none of those is a game launch. Only a launcher that
// says so counts.
static const char* COUNT_ENV_VAR = "MG_COUNT_LAUNCH";

static cJSON* read_stats() {
    FILE* file = fopen(stats_file_path, "r");
    if (!file) return nullptr;

    fseek(file, 0, SEEK_END);
    long size = ftell(file);
    fseek(file, 0, SEEK_SET);
    if (size <= 0) {
        fclose(file);
        return nullptr;
    }

    char* content = (char*)malloc(size + 1);
    if (!content) {
        fclose(file);
        return nullptr;
    }

    size_t read = fread(content, 1, size, file);
    fclose(file);
    content[read] = '\0';

    cJSON* json = cJSON_Parse(content);
    free(content);

    // A damaged stats file is not worth a word to the user: the counters restart
    // and nothing about rendering changes.
    if (json && !cJSON_IsObject(json)) {
        cJSON_Delete(json);
        return nullptr;
    }
    return json;
}

static void write_stats(cJSON* json) {
    char* text = cJSON_PrintUnformatted(json);
    if (!text) return;

    FILE* file = fopen(stats_file_path, "w");
    if (file) {
        fwrite(text, 1, strlen(text), file);
        fclose(file);
    } else {
        LOG_D("Unable to write stats file %s", stats_file_path);
    }
    cJSON_free(text);
}

void bump_launch_count() {
    if (!IsEnvVarTrue(COUNT_ENV_VAR)) {
        LOG_D("%s is not set, not counting this load as a launch", COUNT_ENV_VAR);
        return;
    }

    if (!stats_file_path) {
        LOG_D("Stats path is unknown, not counting this launch");
        return;
    }

    cJSON* json = read_stats();
    if (!json) json = cJSON_CreateObject();
    if (!json) return;

    int count = 0;
    cJSON* item = cJSON_GetObjectItem(json, LAUNCH_COUNT_KEY);
    if (item && cJSON_IsNumber(item)) count = item->valueint;

    // A count that went backwards or overflowed is meaningless; start over rather
    // than persist a negative number the app would have to defend against.
    if (count < 0 || count == INT_MAX) count = 0;

    cJSON_DeleteItemFromObject(json, LAUNCH_COUNT_KEY);
    cJSON_AddNumberToObject(json, LAUNCH_COUNT_KEY, count + 1);

    write_stats(json);
    cJSON_Delete(json);

    LOG_D("Launch count is now %d", count + 1);
}
