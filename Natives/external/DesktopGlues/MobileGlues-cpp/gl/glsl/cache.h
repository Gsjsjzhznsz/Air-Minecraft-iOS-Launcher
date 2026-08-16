// MobileGlues - gl/glsl/cache.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#ifndef MOBILEGLUES_PLUGIN_CACHE_H
#define MOBILEGLUES_PLUGIN_CACHE_H

#include "../mg.h"
#include "../../config/config.h"
#include "../../config/settings.h"

#include <list>
#include <array>
#include <string>
#include <cstdint>

class Cache {
public:
    Cache();
    ~Cache();

    // cacheMap holds iterators into cacheList, so a copy would leave the copy's
    // map pointing into the original's list. There is exactly one instance and
    // it is the singleton below; say so structurally rather than by convention.
    Cache(const Cache&) = delete;
    Cache& operator=(const Cache&) = delete;

    const char* get(const char* glsl);
    void put(const char* glsl, const char* essl);
    bool load();
    // Serialises the whole cache immediately. put() no longer calls this on
    // every insert -- see the persistence policy comment in cache.cpp -- so it
    // doubles as the "flush what is pending" entry point for any teardown hook
    // that later wants one.
    void save();

    static Cache& get_instance();

private:
    struct CacheEntry {
        std::array<uint8_t, 32> sha256;
        std::string essl;
        size_t size;
    };

    struct SHA256Hash {
        size_t operator()(const std::array<uint8_t, 32>& key) const;
    };

    std::list<CacheEntry> cacheList;
    using ListIterator = std::list<CacheEntry>::iterator;
    UnorderedMap<std::array<uint8_t, 32>, ListIterator, SHA256Hash> cacheMap;
    size_t cacheSize = 0;

    // Entries inserted since the last save(), and when that save happened on
    // CLOCK_MONOTONIC. The count is only a trigger, never a record of what is
    // unwritten: save() always serialises the entire list, so whichever save
    // runs next writes every pending entry regardless of how the counter got
    // where it is.
    int pendingEntries = 0;
    int64_t lastSaveNs = 0;

    static std::array<uint8_t, 32> computeSHA256(const uint8_t* data, size_t length);
    void maintainCacheSize();
    void flushIfDue();
};

#endif
