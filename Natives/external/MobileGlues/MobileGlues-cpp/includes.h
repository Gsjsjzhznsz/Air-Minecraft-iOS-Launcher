// MobileGlues - includes.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#ifndef MOBILEGLUES_INCLUDES_H
#define MOBILEGLUES_INCLUDES_H

#define RENDERERNAME "MobileGlues"
#ifdef __ANDROID__
#include <android/log.h>
#endif
#include <dlfcn.h>

#include <EGL/egl.h>
#include <GLES3/gl32.h>
#include <MG/extensions.h>

#include "egl/egl.h"
#include "egl/loader.h"

#if PROFILING
#include <perfetto.h>
PERFETTO_DEFINE_CATEGORIES(perfetto::Category("glcalls").SetDescription("Calls from OpenGL"),
                           perfetto::Category("internal").SetDescription("Internal calls"));
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    static int g_initialized = 0;

    void proc_init();

#ifdef __cplusplus
}
#endif

#include <ska/flat_hash_map.hpp>

// One hash map for the whole tree. It used to be four -- a hand-written open
// addressing map, ankerl::unordered_dense, std::unordered_map and khash -- which
// meant four sets of iterator-invalidation rules to keep straight while reading
// code that mixes them, and no way to tell whether a container had been chosen
// or merely inherited from whatever the neighbouring file used.
//
// ska::flat_hash_map is open addressing with robin-hood probing, so a rehash
// moves the elements: iterators, references and pointers into it are invalidated
// by any insertion. Where a mapped value's address has to outlive later inserts
// -- the per-context tables handed out as a thread_local pointer, the EGL
// extension strings whose c_str() the application keeps -- the map holds a
// unique_ptr and the pointee stays put. Those sites say so where they are
// declared.
//
// Its value_type is pair<Key, T> with the key exposed mutably, so `it->first =`
// compiles and silently corrupts the table. Nothing here does that, but it is
// the one sharp edge this map has that a node-based one does not.
template <typename Key, typename T, class Hash = std::hash<Key>, class KeyEqual = std::equal_to<Key>,
          class Allocator = std::allocator<std::pair<Key, T>>>
using UnorderedMap = ska::flat_hash_map<Key, T, Hash, KeyEqual, Allocator>;

#endif // MOBILEGLUES_INCLUDES_H
