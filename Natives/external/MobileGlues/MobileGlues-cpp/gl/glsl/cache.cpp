// MobileGlues - gl/glsl/cache.cpp
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#include "cache.h"
#include <cstdio>
#include <cstring>
#include <ctime>
#include <fstream>
#include <string>

using namespace std;

// SHA256
static const uint32_t k[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

namespace {
    inline uint32_t rotr(uint32_t x, uint32_t n) {
        return (x >> n) | (x << (32 - n));
    }
    inline uint32_t sigma0(uint32_t x) {
        return rotr(x, 7) ^ rotr(x, 18) ^ (x >> 3);
    }
    inline uint32_t sigma1(uint32_t x) {
        return rotr(x, 17) ^ rotr(x, 19) ^ (x >> 10);
    }
    inline uint32_t Sigma0(uint32_t x) {
        return rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22);
    }
    inline uint32_t Sigma1(uint32_t x) {
        return rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25);
    }
    inline uint32_t ch(uint32_t x, uint32_t y, uint32_t z) {
        return (x & y) ^ (~x & z);
    }
    inline uint32_t maj(uint32_t x, uint32_t y, uint32_t z) {
        return (x & y) ^ (x & z) ^ (y & z);
    }

    void sha256_compress(uint32_t h[8], const uint8_t* block) {
        uint32_t w[64];
        for (int t = 0; t < 16; ++t) {
            // Widen before shifting: a uint8_t promotes to int, and 0xff << 24
            // overflows a signed int.
            w[t] = (static_cast<uint32_t>(block[t * 4]) << 24) | (static_cast<uint32_t>(block[t * 4 + 1]) << 16) |
                   (static_cast<uint32_t>(block[t * 4 + 2]) << 8) | static_cast<uint32_t>(block[t * 4 + 3]);
        }

        for (int t = 16; t < 64; ++t) {
            w[t] = sigma1(w[t - 2]) + w[t - 7] + sigma0(w[t - 15]) + w[t - 16];
        }

        uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];

        for (int t = 0; t < 64; ++t) {
            uint32_t T1 = hh + Sigma1(e) + ch(e, f, g) + k[t] + w[t];
            uint32_t T2 = Sigma0(a) + maj(a, b, c);
            hh = g;
            g = f;
            f = e;
            e = d + T1;
            d = c;
            c = b;
            b = a;
            a = T1 + T2;
        }

        h[0] += a;
        h[1] += b;
        h[2] += c;
        h[3] += d;
        h[4] += e;
        h[5] += f;
        h[6] += g;
        h[7] += hh;
    }
} // namespace

// Streamed over the caller's buffer. This used to copy the whole shader source
// into a vector first, only to append nine to seventy-two bytes of padding to
// it -- a full allocation and copy of the source on top of the hash itself.
// Only the final partial block is materialised now. Digests are unchanged bit
// for bit, so caches written by
// earlier builds still hit; that was checked against the previous
// implementation over every length up to 300 plus random multi-block inputs,
// and against the FIPS 180-4 vectors.
array<uint8_t, 32> Cache::computeSHA256(const uint8_t* data, size_t length) {
    uint32_t h[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};

    size_t offset = 0;
    for (; length - offset >= 64; offset += 64) {
        sha256_compress(h, data + offset);
    }

    // The tail is the remainder, a 0x80 byte, zero padding, and the message
    // length in bits as a big-endian uint64. It needs a second block exactly
    // when the remainder plus the 0x80 leaves no room for those eight bytes.
    const size_t remainder = length - offset;
    uint8_t tail[128] = {0};
    if (remainder > 0) memcpy(tail, data + offset, remainder);
    tail[remainder] = 0x80;
    const size_t tail_size = (remainder < 56) ? 64 : 128;

    // Widened before the multiply: on 32-bit ABIs a size_t multiply would wrap
    // at 512 MB of source and the two ABIs would then disagree on the digest.
    const uint64_t bit_length = static_cast<uint64_t>(length) * 8;
    for (int i = 0; i < 8; ++i) {
        tail[tail_size - 8 + i] = static_cast<uint8_t>(bit_length >> (56 - i * 8));
    }
    for (size_t i = 0; i < tail_size; i += 64) {
        sha256_compress(h, tail + i);
    }

    array<uint8_t, 32> hash{};
    for (int i = 0; i < 8; ++i) {
        hash[i * 4] = static_cast<uint8_t>(h[i] >> 24);
        hash[i * 4 + 1] = static_cast<uint8_t>(h[i] >> 16);
        hash[i * 4 + 2] = static_cast<uint8_t>(h[i] >> 8);
        hash[i * 4 + 3] = static_cast<uint8_t>(h[i]);
    }
    return hash;
}

size_t Cache::SHA256Hash::operator()(const array<uint8_t, 32>& key) const {
    size_t hash = 0;
    for (int i = 0; i < 4; ++i) {
        hash = (hash << 8) | key[i];
    }
    for (int i = 28; i < 32; ++i) {
        hash = (hash << 8) | key[i];
    }
    return hash;
}

// Persistence policy.
//
// put() used to call save() on every insert, and save() rewrites the whole file,
// so a shader pack loading hundreds of programs paid O(n^2) bytes of I/O for a
// file that is only ever read once, at startup. That is the stutter felt while a
// world loads. The on-disk format is one "count, then entries" blob with nowhere
// to append a single record, and it has to stay exactly that so caches written by
// older builds keep loading -- what a save costs therefore cannot change, only
// how often one happens.
//
// A save is deferred until 16 entries are pending or 5 seconds have passed since
// the last one, whichever comes first, and the check runs on every cache
// operation rather than only on inserts so that a run of hits still flushes a
// tail left by earlier misses. The exposure that buys is bounded and small: a
// crash or an Android kill loses at most the 15 most recently translated
// shaders, and only ones translated since the last flush -- they are recompiled
// and re-cached on the next run. Nothing older can be lost, because save() no
// longer overwrites the live file in place.
//
// The alternative shape, write-behind on a thread, was rejected: it needs a
// lock around cacheList that nothing in this class has today, and a background
// writer racing an Android kill has the same failure window anyway.
namespace {
    constexpr int kPendingEntriesBeforeSave = 16;
    constexpr int64_t kSaveIntervalNs = 5LL * 1000 * 1000 * 1000;

    int64_t monotonic_now_ns() {
        // CLOCK_MONOTONIC, so a wall-clock jump -- which Android does hand out
        // after an NTP sync -- can neither stall the flush nor force one.
        timespec ts{};
        if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
        return static_cast<int64_t>(ts.tv_sec) * 1000000000LL + static_cast<int64_t>(ts.tv_nsec);
    }

    // get() and put() are called back to back with the same source on every miss
    // -- once to discover the miss, once to file what the translator produced --
    // and shader pack sources run to tens of kilobytes, so hashing twice per
    // compile is half the hashing done for nothing. A missing get() parks its
    // digest here together with the bytes it was computed from, and put() reuses
    // it when the source matches byte for byte.
    //
    // The match has to be on content. Keying on the pointer would be wrong: the
    // caller hashes a local std::string, so a later compile can hand back the
    // same address holding different text, and a false match would file one
    // shader's ESSL under another shader's hash -- a silently wrong program for
    // as long as the cache lives. The memcmp that rules that out is still one to
    // two orders of magnitude cheaper than the SHA-256 it replaces.
    //
    // thread_local, not members, because the pair is always issued from one
    // thread while this class takes no lock anywhere: two threads translating at
    // once could otherwise interleave the two stores and leave one thread's
    // bytes standing next to the other thread's digest.
    thread_local string g_hash_memo_source;
    thread_local array<uint8_t, 32> g_hash_memo_digest{};
    thread_local bool g_hash_memo_valid = false;
} // namespace

Cache::Cache() {
    load();
    lastSaveNs = monotonic_now_ns();
}

Cache::~Cache() {
    // Best effort on top of the bound stated above, never the thing that bound
    // rests on: the instance is a function-local static, so this runs on an
    // orderly unload or exit and not at all when Android kills the process.
    // Both globals it reaches through save() outlive it -- global_settings_t is
    // trivially destructible, glsl_cache_file_path is a never-freed raw pointer,
    // and this object is constructed lazily on the first translation, hence
    // destroyed before either of them.
    if (pendingEntries > 0) save();
}

void Cache::flushIfDue() {
    if (pendingEntries == 0) return;
    if (pendingEntries < kPendingEntriesBeforeSave && (monotonic_now_ns() - lastSaveNs) < kSaveIntervalNs) return;
    save();
}

const char* Cache::get(const char* glsl) {
    if (global_settings.max_glsl_cache_size <= 0) return nullptr;
    flushIfDue();

    const size_t length = strlen(glsl);
    auto hash = computeSHA256(reinterpret_cast<const uint8_t*>(glsl), length);
    auto it = cacheMap.find(hash);
    if (it == cacheMap.end()) {
        // A miss is what put() follows; a hit ends the translation here, so only
        // the miss is worth remembering.
        g_hash_memo_valid = false;
        g_hash_memo_source.assign(glsl, length);
        g_hash_memo_digest = hash;
        g_hash_memo_valid = true;
        return nullptr;
    }

    cacheList.splice(cacheList.end(), cacheList, it->second);
    return it->second->essl.c_str();
}

void Cache::put(const char* glsl, const char* essl) {
    if (global_settings.max_glsl_cache_size <= 0) return;

    const size_t length = strlen(glsl);
    array<uint8_t, 32> hash;
    if (g_hash_memo_valid && g_hash_memo_source.size() == length &&
        memcmp(g_hash_memo_source.data(), glsl, length) == 0) {
        hash = g_hash_memo_digest;
    } else {
        hash = computeSHA256(reinterpret_cast<const uint8_t*>(glsl), length);
    }
    size_t esslStrSize = strlen(essl) + 1;

    size_t entryMemory = sizeof(CacheEntry::sha256) + sizeof(size_t) + esslStrSize;

    if (auto it = cacheMap.find(hash); it != cacheMap.end()) {
        cacheSize -= (sizeof(CacheEntry::sha256) + sizeof(size_t) + it->second->size);
        cacheList.erase(it->second);
        cacheMap.erase(it);
    }

    cacheList.emplace_back(CacheEntry{hash, essl, esslStrSize});
    cacheMap[hash] = prev(cacheList.end());
    cacheSize += entryMemory;

    maintainCacheSize();
    ++pendingEntries;
    flushIfDue();
}

void Cache::maintainCacheSize() {
    if (global_settings.max_glsl_cache_size <= 0) return;
    while (cacheSize > global_settings.max_glsl_cache_size && !cacheList.empty()) {
        const auto& oldEntry = cacheList.front();
        size_t removedMemory = sizeof(CacheEntry::sha256) + sizeof(size_t) + oldEntry.size;
        cacheSize -= removedMemory;
        cacheMap.erase(oldEntry.sha256);
        cacheList.pop_front();
    }
}

bool Cache::load() {
    try {
        // check_path() runs long before the first translation, but the path is a
        // global that starts null and ifstream would take it straight to fopen.
        if (!glsl_cache_file_path) return false;
        ifstream file(glsl_cache_file_path, ios::binary);
        if (!file) return false;

        size_t count;
        file.read(reinterpret_cast<char*>(&count), sizeof(count));

        while (count--) {
            array<uint8_t, 32> hash{};
            size_t esslSize;

            file.read(reinterpret_cast<char*>(hash.data()), hash.size());
            file.read(reinterpret_cast<char*>(&esslSize), sizeof(esslSize));

            string essl(esslSize, '\0');
            file.read(essl.data(), (long)esslSize);

            if (cacheMap.count(hash)) continue;

            size_t entryMemory = sizeof(CacheEntry::sha256) + sizeof(size_t) + esslSize;
            cacheSize += entryMemory;

            cacheList.emplace_back(CacheEntry{hash, move(essl), esslSize});
            cacheMap[hash] = prev(cacheList.end());
        }

        maintainCacheSize();
        return true;
    }
    catch (...) {
        LOG_W_FORCE("Error while loading glsl cache file. Clearing it...")
        cacheMap.clear();
        cacheSize = 0;
        cacheList.clear();
        save();
        return false;
    }
}

void Cache::save() {
    if (global_settings.max_glsl_cache_size <= 0) return;
    if (!glsl_cache_file_path) return;

    // Cleared before the attempt, not after it. save() serialises the whole list
    // every time, so the counter is a trigger and not a record of what is
    // missing: if this write fails, the next one still writes those entries, and
    // clearing here is what stops a device with a full or unwritable /sdcard
    // from retrying a whole-file write on every single compile.
    pendingEntries = 0;
    lastSaveNs = monotonic_now_ns();

    // Written to a sibling and renamed over the cache instead of truncating the
    // live file: the write costs the same, but a crash in the middle of one can
    // no longer leave a half-written file that load() can only react to by
    // discarding every entry in it. rename(2) is atomic against this process
    // dying, which is the failure this cache has; it promises nothing about
    // power loss, which regenerable data does not need protecting from.
    const string temp_path = string(glsl_cache_file_path) + ".new";
    {
        ofstream file(temp_path, ios::binary);
        if (!file) return;

        size_t count = cacheList.size();
        file.write(reinterpret_cast<const char*>(&count), sizeof(count));

        for (const auto& entry : cacheList) {
            file.write(reinterpret_cast<const char*>(entry.sha256.data()), (long)entry.sha256.size());
            size_t esslSize = entry.size;
            file.write(reinterpret_cast<const char*>(&esslSize), sizeof(esslSize));
            file.write(entry.essl.data(), (long)esslSize);
        }

        file.flush();
        if (!file) {
            // A short write must not become the cache: keep whatever is already
            // in place and drop the partial file.
            file.close();
            std::remove(temp_path.c_str());
            return;
        }
    }

    if (std::rename(temp_path.c_str(), glsl_cache_file_path) != 0) {
        std::remove(temp_path.c_str());
    }
}

Cache& Cache::get_instance() {
    static Cache s_cache;
    return s_cache;
}
