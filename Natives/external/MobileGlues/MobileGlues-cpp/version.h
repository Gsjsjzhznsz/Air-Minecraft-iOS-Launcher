// MobileGlues - version.h
// Copyright (c) 2025-2026 MobileGL-Dev
// Licensed under the GNU Lesser General Public License v2.1:
//   https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
// SPDX-License-Identifier: LGPL-2.1-only
// End of Source File Header

#ifndef MOBILEGLUES_VERSION_H

#define VERSION_DEVELOPMENT 0
#define VERSION_ALPHA 1
#define VERSION_BETA 2
#define VERSION_RC 3
#define VERSION_RELEASE 10

#define MAJOR 2
#define MINOR 0
// 0 -> 1: force-invalidate the on-disk GLSL conversion cache. The 2.0.0 builds
// that shipped with a mis-populated 3rdparty/ tree cached ESSL that ANGLE-Metal
// rejects with "ERROR: 1:1: '' : syntax error"; the cache key embeds
// MAJOR.MINOR.REVISION, so this bump makes every device discard those entries
// on first run instead of re-serving them.
// 1 -> 2: iOS host-driver binding rework (explicit ANGLE dlopen instead of the
// RTLD_DEFAULT free-for-all) + per-shader submit/readback records. The bump
// invalidates cached conversion results once more and, more importantly, makes
// "MobileGlues 2.0.2" visible in the runtime log so a stale dylib in the IPA
// is instantly obvious.
// 2 -> 3: mg_init_gles() now pins the GL ES table to the REAL ANGLE libGLESv2
// instead of libtinygl4angle, whose glShaderSource does not forward into
// ANGLE's object namespace (every pipeline died with "ERROR: 1:1: ''" and a
// zero-byte driver readback). Shader conversions now ALWAYS run on the
// dedicated 32 MB-stack thread (the >= 8 MB inline fast path depended on the
// caller's stack-size report and could still overflow inside glslang).
// 3 -> 4: process_sampler_buffer() rewrote texelFetch argument lists with a
// [^)]+? regex that truncated at the first ')', shredding any coordinate with
// nested calls. Sodium 0.9.x's
//     texelFetch(u_SectionTimeInfo, int((u_RegionID * 256u) + uint(chunkId)))
// became 'temp uint % uniform int' garbage -> glslang parse failure -> every
// Sodium terrain pipeline invalid -> no blocks rendered. Rewritten with a
// paren-depth scanner; coordinates now also pass through int(...) so
// driver-lenient uint indices cannot re-mix sign with u_BufferTexWidth.
// REVISION 6: stage-tagged SIGSEGV crash-site report + optimizer-disabled
// retry on the conversion thread.
// REVISION 7: buffer-texture emulation runtime repair. (1) Draw-time sampler
// rewiring now repoints ONLY the samplers converted from samplerBuffer at the
// emulation unit; it used to repoint every sampler2D in the program, which on
// Sodium 0.9's chunk program hijacked the block atlas (u_BlockTex) and light
// map (u_LightTex) onto the section-info texture -- every chunk fragment then
// discarded itself below ALPHA_CUTOUT and the whole terrain vanished
// (MobileGlues-release issue #432). (2) The snapshot is refreshed whenever the
// backing buffer is mutated (glBufferData/glBufferSubData/glUnmapBuffer/
// glBufferStorage); it used to be taken exactly once at glTexBuffer. (3) The
// GL_TEXTURE_BUFFER binding point no longer reaches an ES 3.0/3.1 driver (it
// answered GL_INVALID_ENUM there, silently swallowing every mutation MC issued
// through that target); it is tracked here and the mutations borrow
// GL_COPY_WRITE_BUFFER instead.
// REVISION 8: glslang emission-side swizzle null guards. Device log 2.0.7:
// 264 conversions SIGSEGV'd at ONE site -- (anon)::TGlslangToSpvTraverser::
// convertSwizzle+0x1c via visitBinary+0x1318 (symbolicated from the crash-site
// report, pc-libmobileglues+0x24a838) -- the selector aggregate read as
// missing/malformed on iOS/arm64 for inputs that convert cleanly under
// x86_64/qemu-arm64/ASan and converted fine in the 2.0.6 process. Same defect
// family as the 2.0.1-2.0.3 lValueErrorCheck kill, one stage later. The
// nullguard patch now covers SPIRV/GlslangToSpv.cpp: convertSwizzle returns
// bool and rejects unusable selectors (null/non-constant element, out-of-range
// index) instead of dereferencing them, and both call sites (visitBinary
// EOpVectorSwizzle, createInvertedSwizzle) fall back to the identity swizzle
// of the result's component count. Byte-identical output vs pristine glslang
// on all swizzle-heavy positive tests and every edge-case candidate.
// REVISION 9: MC 26.x transparency-pipeline depth-path hardening + device
// diagnostics. The game's clouds/weather/particles are composited by
// post/transparency.fsh, which per-pixel-sorts six layers (main + five
// dedicated FBOs, each with its own D32F depth texture) and blends far to
// near. If any depth texture reads garbage the sort degenerates to insertion
// order and the last layer -- clouds -- draws over everything, including from
// underground. A locally built libmobileglues (Linux) replaying the exact
// blaze3d call sequence against a conformant ES 3.0 driver (Mesa llvmpipe)
// passes every hop end to end: D32F allocation, D32F sampling, reversed-Z
// draw, copyDepthFrom's depth-only glBlitFramebuffer (byte-exact), composite
// sort. So the on-device breakage is a per-driver divergence this layer must
// flatten. Two changes: (1) glFramebufferTexture2D redirects depth-ONLY
// textures attached at GL_DEPTH_STENCIL_ATTACHMENT to GL_DEPTH_ATTACHMENT and
// detaches the stencil point. blaze3d's fallback DirectStateAccess attaches
// every depth texture at the combined point; strict drivers (Mesa, measured)
// answer FRAMEBUFFER_INCOMPLETE_ATTACHMENT for a depth-only image there, and
// the lenient drivers that accept it are left with a stencil attachment
// pointing at a stencil-less image. (2) One-shot W_FORCE diagnostics on the
// first depth-texture allocation (driver-reported internalformat/depth/
// stencil bits), the first combined-point depth+stencil attach (driver
// completeness verdict), the first DEPTH blit (both FBOs' completeness +
// error verdict), and the first draw of the composite program (all twelve
// sampler uniforms with unit, texture name and internalformat). Together
// these grade every hop the composite depends on directly from a device log.
// REVISION 10: 2.0.9 device log results -- the depth blit (copyDepthFrom) is
// healthy on device (both FBOs complete, GL_NO_ERROR), but the combined-point
// redirect never fired AND the composite sampler dump never fired. Two
// corrections and one new probe. (1) Constant correction: 36096 is
// GL_DEPTH_ATTACHMENT, not GL_DEPTH_STENCIL_ATTACHMENT -- MC attaches depth
// directly at GL_DEPTH_ATTACHMENT and the 2.0.9 combined-point redirect is
// dead code for this application (kept for spec hygiene). The attach
// diagnostic now grades the FIRST EIGHT depth-family attaches at whichever
// point they actually use, with the registry's view of each texture. (2) The
// depth-allocation probe read GL_TEXTURE_INTERNAL_FORMAT, which is not an
// ES 3.0 pname (ANGLE rejects it; Mesa tolerates it), so its zeros were
// ambiguous. Rewritten to separate the three confounded things per
// allocation: the shadow's texture, the DRIVER's texture on the active unit,
// the upload's own error, and GL_TEXTURE_DEPTH_SIZE of what the driver
// actually has. (3) The composite dump never fired because nothing verified
// the composite draws reach this layer's glDrawArrays at all; a 24-draw
// census plus a depth-sampler dump keyed on any program with a "Depth"-named
// sampler2D now grades reachability and the composite's inputs together.
// (4) One-shot symbol-theft check in glXGetProcAddress: the app-facing proc
// addresses come from dlsym(RTLD_DEFAULT), whose flat namespace also holds
// the host ANGLE libGLESv2; if dyld's image order ever lets ANGLE win a name
// this layer exports, the application bypasses this layer for that function
// entirely.
// REVISION 11: 2.0.10 device log results + the real reason the composite was
// never observed. The log graded three things: depth allocations healthy
// (shadow == driver binding, upload clean), depth blit healthy (both FBOs
// complete, GL_NO_ERROR), no symbol theft -- and the draw census answered a
// question nobody had asked: every one of the first 24 programs was first
// seen on "other draw", meaning MC 26.2 never issues plain glDrawArrays or
// glDrawElements at all. Disassembling the shipped client.jar's
// GlCommandEncoder.drawFromBuffers confirms it: the non-indexed branch is
// glDrawArraysInstanced / glDrawArraysInstancedBaseInstance, the indexed one
// glDrawElementsInstancedBaseVertex(_BaseInstance) -- there is NO plain
// glDrawArrays branch, so the transparency composite (a 3-vertex, 1-instance
// non-indexed draw) sailed through the glDrawArraysInstanced native
// passthrough without ever reaching prepareForDraw: no TBO sampler rewiring
// for any instanced draw, and no diagnostic could ever see the composite's
// inputs. (1) glDrawArraysInstanced moved from the native table into
// gl/drawing.cpp behind prepareForDraw(3); glDrawArraysInstancedBaseInstance
// now tags prepareForDraw(4); the ARB alias the NATIVE_FUNCTION_HEAD macro
// used to emit is kept. (2) The depth-family attach census turned out to
// query glCheckFramebufferStatus BEFORE the forward -- its odd 0x8cd7 rows
// measured the pre-attach emptiness of fresh temp fbos, not driver verdicts;
// it now runs after the forward and records the attach error plus the
// color0/depth attachment object names. (3) The depth blit gets a content
// probe: for the first two DEPTH blits, five depth texels are read back from
// both sides and logged -- NO_ERROR says the driver accepted the copy, only
// the values say the data moved. (4) The depth-sampler program dump (now
// reachable through the instanced hooks) grades per sampler: unit, shadow and
// driver texture, registry internal format, the texture's own MIN/MAG filter,
// and any bound sampler object's MIN/MAG filter -- sampling depth with a
// LINEAR filter is the classic silent killer on strict ES drivers (an
// unfilterable depth texture reads black, which in reversed-z is "infinitely
// far" and un-occludes everything), and the draw fbo's color0/depth
// attachments are logged with it.
#define REVISION 11
#define PATCH 0

#define VERSION_TYPE VERSION_RELEASE

#if VERSION_TYPE == VERSION_RC
#define VERSION_RC_NUMBER 2
#endif

// Development builds are numbered for the reason release candidates are: several
// of them carry the same MAJOR.MINOR.REVISION, and a bug report has to be able to
// name which one it came from. Bump this whenever a build leaves this machine.
#if VERSION_TYPE == VERSION_DEVELOPMENT
#define VERSION_DEV_NUMBER 4
#endif

#define VERSION_SUFFIX ""

#define MOBILEGLUES_VERSION_H

#endif // MOBILEGLUES_VERSION_H
