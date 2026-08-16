// MobileGlues - egl/context.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#ifndef MOBILEGLUES_EGL_CONTEXT_H
#define MOBILEGLUES_EGL_CONTEXT_H

#include "../includes.h"
#include "../gl/enable.h"
#include "../gl/mg.h"
#include <memory>

// ---------------------------------------------------------------------------
// Virtual context records
//
// Everything MobileGlues emulates has to live somewhere, and until now there was
// nowhere to put it: eglMakeCurrent was a five-line passthrough, so the layer had
// no idea a context switch had happened. State that GL scopes to a context ended
// up as process-global singletons, and gl/multidraw.cpp had to poll
// eglGetCurrentContext() on every draw to approximate the switch it could not
// observe.
//
// An MGContext is created by eglCreateContext, kept alive by a reference count
// rather than destroyed the moment eglDestroyContext returns -- GL allows
// destroying a context that is still current, and the object must outlive that
// call -- and pointed at by a thread-local current pointer that only
// eglMakeCurrent writes.
//
// The identity is a monotonic id, never the EGLContext pointer. EGLContext is a
// driver heap allocation, so destroying one and creating another frequently
// yields the same address; comparing addresses reports "same context" for a
// context that never owned the cached objects.
// ---------------------------------------------------------------------------

struct MGShareGroup {
    unsigned long long id;
    // Objects GL shares across a share group -- buffers, textures, renderbuffers,
    // samplers, shaders, programs, syncs -- belong here. They are still
    // process-global today; moving them is the last step of this work.
};

struct MGContext {
    unsigned long long id;
    EGLDisplay display;
    EGLContext handle;
    EGLenum client_type;   // EGL_OPENGL_API or EGL_OPENGL_ES_API, fixed at creation
    EGLint granted_major;  // what the application was told it got
    EGLint granted_minor;
    EGLint profile_mask;
    EGLint context_flags;  // reported back through glGetIntegerv(GL_CONTEXT_FLAGS)
    std::shared_ptr<MGShareGroup> share_group;

    mg_enable_state_t enable; // per-context by definition: enable state is not shared
    gl_state_s gl;            // current program / texture unit / draw fbo, all per-context

    EGLSurface draw;
    EGLSurface read;
    int current_count;     // how many threads have this current
    bool destroy_pending;  // eglDestroyContext was called while still current
};

// The context current on THIS thread, or nullptr. EGL scopes the current context
// per thread, so this must be thread_local even though the record it points at is
// shared.
//
// Reading it is safe for as long as the thread keeps the context current, because
// the thread holds a reference of its own (a shared_ptr private to context.cpp)
// alongside this pointer. The map is not the only owner: a handle the driver
// hands out twice would otherwise replace the map entry and free a record another
// thread is still pointing at.
extern thread_local MGContext* g_current_ctx;

// Called from the EGL wrappers.
MGContext* mg_context_create(EGLDisplay dpy, EGLContext handle, EGLContext share_handle, EGLenum client_type,
                             EGLint major, EGLint minor, EGLint profile_mask, EGLint context_flags);
void mg_context_make_current(EGLDisplay dpy, EGLSurface draw, EGLSurface read, EGLContext handle);
void mg_context_destroy(EGLContext handle);
void mg_context_forget_display(EGLDisplay dpy);
MGContext* mg_context_find(EGLContext handle);

// Per-context / per-share-group state owned by other translation units.
//
// The containers stay private to the file that uses them -- moving them into
// MGContext would drag gl/texture.h and friends into this header and back. Each
// subsystem keeps its own table keyed by id and swaps a thread_local pointer
// when the current context changes. Every one of those tables holds its records
// through a unique_ptr, because the map underneath is open addressing and moves
// its elements when it grows: the record is what has to stay put, so a pointer
// handed out here stays valid until the entry is erased.
void mg_buffer_bind_context(unsigned long long ctx_id, unsigned long long group_id);
void mg_texture_bind_context(unsigned long long ctx_id, unsigned long long group_id);
void mg_framebuffer_bind_context(unsigned long long ctx_id);
void mg_fsr1_bind_context(unsigned long long ctx_id);

// ...and the matching teardown. Every table above inserts with operator[] and
// none of them had an erase, so a context's bookkeeping outlived the context for
// the life of the process. Called from release_locked once the record is going
// away, i.e. after the last thread has stopped using it, so the entry being
// erased is guaranteed not to be the one any thread_local pointer refers to.
//
// The share group is deliberately not torn down here: sibling contexts may still
// be using it, and the group record is small. Only per-context state is dropped.
void mg_buffer_forget_context(unsigned long long ctx_id);
void mg_texture_forget_context(unsigned long long ctx_id);
void mg_framebuffer_forget_context(unsigned long long ctx_id);
void mg_fsr1_forget_context(unsigned long long ctx_id);
void mg_depth_clear_forget_context(unsigned long long ctx_id);

// Per-display eglInitialize accounting.
//
// EGL does not reference-count initialisation per caller: whoever calls
// eglTerminate marks EVERY resource on the display for destruction, including
// ones another part of the process created. The bootstrap probe used to do
// exactly that to EGL_DEFAULT_DISPLAY. These let it terminate only a display it
// actually brought up itself.
//
// Two holders, not a count, because eglInitialize is idempotent: an application
// may call it any number of times and is still only obliged to call eglTerminate
// once. Counting calls meant two inits and one terminate left the display up for
// good. `probe` distinguishes the bootstrap in egl/loader.cpp from everything
// arriving through the eglInitialize wrapper; each side holds at most one share.
void mg_display_initialised(EGLDisplay dpy, bool probe);
bool mg_display_release(EGLDisplay dpy, bool probe); // true when this was the last holder

#endif // MOBILEGLUES_EGL_CONTEXT_H
