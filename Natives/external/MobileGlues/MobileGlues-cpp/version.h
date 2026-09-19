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
// REVISION 12: 2.0.11 device log results + the root cause of the transparency
// occlusion break (clouds visible through terrain, underground clouds, water/
// particles/weather sorting against nothing). The log closed the case with the
// depth-sampler dump: the composite program's twelve sampler2D uniforms all
// have one SamplerCache sampler object bound over them whose MIN filter is
// GL_LINEAR_MIPMAP_NEAREST (9986) -- with the dump's 9728/9729 labels fixed,
// its MAG is GL_NEAREST, and the "LINEAR" the 2.0.11 log printed for MIN was
// the value 9986, not a NEAREST/linear mistake on MC's part. 9986 is what
// Mojang's GlSampler deliberately emits for minFilter=NEAREST (LINEAR goes to
// 9987), kept pointed at level 0 by TEXTURE_MAX_LEVEL=0 on the texture and the
// sampler's own MAX_LOD=0. The within-level part of 9986 is a LINEAR sample,
// and GLES 3.0 does not filter depth images (desktop GL does, which is why the
// same state renders fine on PC): on ANGLE Metal the composite's depth samples
// are undefined and read 0.0, which in reversed-z is "infinitely far", so
// every layer-vs-layer sort degenerates and the last-blended clouds layer
// wins over everything. The dump's own filter table had GL_NEAREST/GL_LINEAR
// swapped, which is why 2.0.11's log reads as MAG=LINEAR at first glance --
// fixed here so the next log is readable. The fix, desktop semantics on ES:
// (1) every depth-family allocation (TexImage2D/3D, TexStorage2D/3D) joins a
// depth registry and gets MIN/MAG = NEAREST on the texture object itself;
// (2) glTexParameteri/glTexParameterf aimed at a registered depth texture
// cannot set anything but NEAREST for MIN/MAG; (3) the sampler objects are
// now tracked (glGenSamplers/glDeleteSamplers/glBindSampler/glSamplerParameteri/
// glSamplerParameterf moved from the native table into gl/texture.cpp, ARB
// aliases kept), and prepareForDraw forces a bound sampler's driver-side
// MIN/MAG to NEAREST exactly while any unit it is bound on holds a depth
// image, restoring the application's parameters on the first draw where the
// pairing no longer holds (two-pass per draw so one cache sampler shared by a
// colour and a depth unit in the same composite draw converges on forced);
// comparison-mode samplers are left alone so hardware PCF is untouched; the
// enforcement is skipped while FSR1 makes the per-unit binding shadow
// untrustworthy. Retired diagnostics that had answered their questions: the
// 24-program draw census, the depth-family attach census, and the depth blit
// content probe (ANGLE Metal refuses every depth glReadPixels with
// GL_INVALID_OPERATION, so a probe can only report its own refusal). The
// depth-sampler program dump stays, with the corrected filter names, and the
// force/restore transitions log their first eight occurrences.
// REVISION 13: 2.0.12 device log results + why the depth-filter enforcement
// never armed where it was needed. The log shows deployment healthy, the
// composite dump firing (program 197, twelve sampler2D inputs, one SamplerCache
// sampler 26 bound across all of them, MIN 9986, six D32F depth textures whose
// texture-object filters read NEAREST/NEAREST from fix (1)) -- and not one
// "depth filter force" line. The enforcement's precondition,
// driver_texture_shadow_trustworthy(), is false on the iOS/ANGLE host for a
// reason nothing had exercised before: the app talks to ANGLE's libEGL
// directly, so mg_texture_bind_context never fires and the texture layer sits
// on the shared fallback record forever -- the same precondition the TBO
// rewiring survives by falling back to a direct driver query, which the
// enforcement lacked. (The dump's "tex 0/9" rows are this gate refusing to
// answer, not an empty binding map.) Fix: two modes in
// mg_enforce_depth_sampling_nearest. Tracked mode is 2.0.12 unchanged. The
// untracked mode treats the fallback record as a HINT -- every hooked bind
// still maintains it, and the decompiled GlCommandEncoder shows MC 26.2 binds
// textures exclusively through _activeTexture/_bindTexture/glBindSampler, all
// hooked -- and confirms every depth hint against the driver
// (glActiveTexture + GL_TEXTURE_BINDING_2D, borrowed and restored via the
// GLES entry points directly) before a filter may be forced. A stale hint
// costs a rejected confirmation; acting on the record alone is what the
// layer's invariant forbids. FSR1 keeps enforcement off entirely, as before:
// its binding leak is silent, so neither a record nor a confirm can see it.
// One line logs once when the untracked scan arms, so the next device log
// can distinguish "armed and confirming" from "never ran".
// REVISION 14: 2.0.13 verified on device (armed line + force/restore pairs +
// occlusion restored in play), and a self-correction the verification pass
// uncovered. The filter labels this layer printed since 2.0.12 -- and the
// gl.h definitions behind them -- were themselves wrong: the Khronos
// registry (and Mesa's and ANGLE's headers, all cross-checked) define
// 0x2701 = GL_LINEAR_MIPMAP_NEAREST and 0x2702 = GL_NEAREST_MIPMAP_LINEAR,
// so 2.0.12's "corrected" gl.h had in fact inverted a correct header, and
// Mojang's GlSampler maps minFilter=NEAREST to 9986 = GL_NEAREST_MIPMAP_
// LINEAR (nearest within a level, blended across levels, clipped to one
// level by MAX_LOD=0) -- not GL_LINEAR_MIPMAP_NEAREST. The mechanism
// narrative is relabelled accordingly and gets tighter: GLES 3.0 keeps a
// depth-family texture filter-complete only while MIN_FILTER is NEAREST or
// NEAREST_MIPMAP_NEAREST, so the MIPMAP_LINEAR family alone is enough to
// make every D32F image under that sampler read incomplete (0.0 on ANGLE
// Metal, "infinitely far" in reversed-z). No behavioural change to the
// enforcement itself: the force still writes plain NEAREST, and the
// decision paths only ever compared against GL_NEAREST. Fixed here: the
// gl.h pair, the dump's filter_name table (9985/9986 labels), the sampler
// record's GLES-default MIN (9986, not 9985 -- the restore write-back for a
// never-parameterised sampler used to hand back LINEAR_MIPMAP_NEAREST
// instead of the default), and the rationale comments in gl/texture.{h,cpp}.
// REVISION 15: the MC 26.3 SDL3 host turned the 2.0.10 theft canary from a
// hypothetical into the actual failure. 26.3's renderpearl GlBackend.loadLibrary
// cross-checks its two GL entry points: the LWJGL function provider (built on
// this layer's exported glXGetProcAddress) must return the SAME address for
// "glGetError" as SDL_GL_GetProcAddress (hooked by the host to dlsym this
// layer's handle). glXGetProcAddress resolved names through the process-wide
// flat namespace (RTLD_DEFAULT), where this layer and the host's ANGLE
// libGLESv2 both export every gl* name and dyld image order decides the
// winner. In the 26.3 path ANGLE loads first, the LWJGL side bound ANGLE's
// GLES exports, the SDL side bound this layer's exports, the pointer check
// failed ("glGetError mismatch"), the OpenGL backend was rejected and the
// game fell back to MoltenVK (which then died in shaderc's unpatched glslang).
// Fixed by resolving from this layer's own image first (RTLD_SELF: the
// calling image, then its dependents), so this layer's exports win regardless
// of image order; RTLD_DEFAULT remains the fallback for names this layer does
// not export. The flat-namespace canary stays as environment diagnostics --
// resolution no longer depends on what it reports.
// REVISION 16: 2.0.15's RTLD_SELF did not survive contact with the device --
// the 3c13d5e5 build still reported "glGetError mismatch" and fell back to
// MoltenVK. Root cause of the trap: dyld derives the "caller image" of the
// special handles (RTLD_SELF/RTLD_NEXT) from __builtin_return_address(0), and
// the host launcher rebinding dlsym process-wide (fishhook) redirects every
// dlsym issued from this layer through host code, so the "caller" dyld saw was
// the host binary, not this layer -- RTLD_SELF searched the host's dependency
// subtree and the outcome depended on where the dlopen'd renderers sit in it.
// Fixed by dropping special handles entirely: glXGetProcAddress now resolves
// through a handle to THIS image (dladdr on an own function + dlopen
// RTLD_NOLOAD, which can never map a duplicate) and falls back to
// RTLD_DEFAULT only for names this layer does not export. Handle-based dlsym
// has no caller-image ambiguity, so this layer's exports win for every name
// it implements, independent of image order and of who is calling. One-time
// W_FORCE line reports the resolved own-image path for device-log verification.
// REVISION 17: Amethyst Task 32 -- two ESSL-output bugs that surfaced once the
// Task 30/31 lifecycle locks stopped the SIGSEGV (build a09e020 ran all 390
// shaderc compiles with zero native crashes, revealing what the crash used to
// hide). (1) process_uniform_declarations() matched the "uniform" keyword as
// a raw substring, so RenderPearl's _uniform_instance_00_XX block-instance
// identifiers triggered a bogus has_initializer rewrite that destroyed the
// enclosing statement -- every core pipeline fragment failed in ANGLE with
// "'_uniform' : undeclared identifier" + "'_instance_00_XX' : syntax error".
// Now token-guarded on both sides. (2) Minecraft 26.x OIT shaders index
// fragment-output arrays (coeff[attachmentIndex][i]) with loop variables,
// which ESSL 300 rejects outright; the converter now routes those accesses
// through a scratch array and copies out with constant indices at the end of
// main(). This bump also force-invalidates the on-disk conversion cache:
// entries written by <= 2.0.16 embed the corrupted ESSL and would keep being
// re-served for identical sources. "MobileGlues 2.0.17" in the runtime
// Graphics Drivers line identifies the fixed build on device.
//
// REVISION 17 addendum (Amethyst Task 81, no bump): gl/texture.cpp's depth-
// sampling filter enforcement no longer switches itself off while FSR1 is
// engaged. The kill-switch dated from the era when FSR1's GLStateGuard leaked
// the render texture onto unit 0 once per presented frame (no shadow recorded
// it, so a stale hint could have flipped a colour sampler) AND fsr1Setting
// never engaged on iOS at all (its config was never read), so the switch cost
// nothing. Two changes invalidated each half: the guard now saves and restores
// unit 0's own binding (nets to zero), and the launcher passes fsr1Setting
// through -- so the first device session with FSR1 on (build 678e7b5) ran with
// the enforcement silently dead: the composite's sampler 26 kept MIN 9986 over
// six D32F units, every depth sample read 0.0 ("infinitely far" in reversed-z),
// and clouds/weather/particles/item entities rendered through terrain -- the
// exact symptom the enforcement was built to cure, back as an FSR1 side effect.
// Enforcement now always runs, and every depth hint is driver-confirmed while
// FSR1 is on (the untracked mode's borrow-and-restore, extended to tracked
// contexts for the duration). REVISION deliberately NOT bumped: the conversion
// cache key embeds MAJOR.MINOR.REVISION and no converter output changed, so a
// bump would only burn the on-disk cache (~400 entries) for nothing. The
// one-shot "[MG] depth filter scan: FSR1 active (Task 81)" log line identifies
// the fixed build on device, alongside the returning force/restore pairs.
// REVISION 17 addendum (Task 82): the glViewport render-size latch now refuses
// viewports that are not window-shaped -- larger than the EGL surface in either
// axis, or off the surface's aspect ratio by more than 3%. MC 26.x's animated
// atlas pass drives glViewport at the full blocks-atlas size (2048x2048 on a
// 2360x1640 surface), which the grow-only latch adopted as the render size and
// then could never drop: the upscale stretched the mostly-unwritten 2048x2048
// render texture over the whole surface and the game appeared shrunk into the
// bottom-left corner (ea27def). No converter output changed, so REVISION stays
// 17 -- the one-shot "[MG] FSR1 viewport latch rejected (Task 82)" line (plus
// the engage log now naming 1814x1262 instead of 2048x2048) identifies the
// fixed build on device.
// REVISION 17 addendum (Task 83, no bump): ApplyFSR now draws EASU straight
// into the surface when the target equals it (the common launcher case after
// the new <=4px rounding clamp), replacing the old clear + draw + blit triple
// with a single fullscreen pass; the resolution-slider-stacked sub-surface
// path keeps the blit. No converter output changed, so REVISION stays 17 --
// the steady-state per-frame cost drop is identified on device by the absence
// of the previously-per-frame target-FBO clear, with the engage log line
// unchanged from Task 82.
// REVISION 17 addendum (Task 84, no bump): FSRShaderSource.h now carries a
// manual packHalf2x16 / unpackHalf2x16 fallback under __VERSION__ < 420 --
// the builtins are GLSL 4.20 core and the zink/MoltenVK path caps at GLSL
// 4.10, where the EASU fragment compile previously died at the first packing
// helper (75c5e14 device log). The fallback is bit-exact against numpy
// float16 (RNE, subnormals, Inf/NaN) and preprocessed out entirely on 4.20+
// contexts, so no converter output changed and REVISION stays 17. The fixed
// build identifies itself on device by the zink engage line now appearing
// after "Task83b FSR shader #version adapted: 450 -> 410" instead of the
// "no function with name packHalf2x16" compile failure.
// REVISION 17 addendum (Task 85, no bump): the zink-side EASU pass in
// osm_bridge.mm now runs BEFORE the glFinish that triggers OSMesa's
// GPU-to-CPU readback, instead of after it. The Task 83 ordering drew the
// upscaled frame into the GPU-side image only after the client buffer had
// already been read back, so the displayed CGImage never contained the
// upscale result: the bottom-left window region showed the raw low-res
// frame while the rest showed the previous frame's EASU output -- the
// on-device "split picture". The pass additionally pins the default
// framebuffer (saving/restoring draw and read FBO bindings) and disables
// stencil test, making it hermetic against any FBO state a mod leaves
// bound at swap. Purely launcher-side presentation code, no converter
// output changed, so REVISION stays 17. The fixed build identifies itself
// on device by the zink engage line now ending in "(EASU pre-readback
// ordering, Task 85)".
// REVISION 17 addendum (Task 86, no bump): Tools.java (launcher.jar) now arms a
// launch watchdog daemon thread right before invoking Minecraft main. On-device
// evidence (BMC2 [FABRIC] 1.20.1, 537 mods, zink): the game main thread hard-
// blocked inside a Fabric client entrypoint ~5.6s after JVM start -- zero GC,
// zero JIT installs, zero log lines for 187s until the user cancelled, launch
// overlay stuck ("stuck on the loading screen"). The watchdog samples the game
// thread's stack every 15s during the entrypoint phase (compacting repeats to
// one heartbeat line) and, after the thread renames to "Render thread", runs a
// 30s freeze detector on the top stack frames. Log lines are prefixed with
// "[LaunchWatchdog] Task86" and name the blocking mod's class directly, turning
// the next reproduction into a one-read diagnosis. Launcher-side Java only;
// no MobileGlues converter surface touched, so REVISION stays 17.
// REVISION 17 addendum (Task 87, no bump): the watchdog paid off -- the 7b88b69
// log pair named the modpack stall AND exposed an LTW capability gap. (1) The
// 537-mod BMC2 stall is toni.missingmodschecker.MissingModsWindow.open's
// Object.wait(): a desktop utility mod popping a Swing dialog over missing
// (recommends-level) dependencies; the window can never be shown on iOS, so
// the game thread waited forever. JavaLauncher.m now auto-disables evidenced
// desktop-dialog mods before the JVM starts ([ModDialogGuard] Task87, rename
// to .jar.disabled -- Fabric ignores non-.jar files), and the watchdog logs a
// one-shot STARTUP BLOCK hint when it sees AWT/Swing frames or Object.wait
// held directly under mod code (the post-construction wait carries no AWT
// frames, so the detector matches the wait pattern itself). (2) The same log
// pair's LTW session crashed at 11.8s in the title-screen resource reload:
// MC 26.x's clouds pipeline (minecraft:core/rendertype_clouds) uses
// samplerBuffer under the desktop GL 3.3 profile LTW advertises, but LTW's
// iOS backend is Apple's system ANGLE GLES 3.0 (no GL_EXT_texture_buffer) and
// LTW has no TBO emulation layer -- "samplerBuffer: Illegal use of reserved
// word" kills pipeline/flat_clouds and the reload aborts. SurfaceViewController
// now gates LTW x MC >= 26 before launch with a dialog pointing at Zink or
// MobileGlues (this layer's own TBO emulation, REVISION 7+, is why MG runs
// 26.x unharmed). Launcher-side only; no MobileGlues converter surface
// touched, so REVISION stays 17.
// REVISION 17 addendum (Task 94, no bump): the 809b847 log pair (commit 3bc95fa
// build, both zink and LTW sessions of the 537-mod BMC2 pack on 1.20.1)
// proved the Task87 fixes engaged -- [ModDialogGuard] disabled
// missingmodschecker.jar and startup sailed past the old stall -- and then
// died at the SAME spot in BOTH renderers ~4s after JVM start: Sodium
// 0.5.13's PreLaunchChecks gate, which requires
// org.lwjgl.Version.getVersion().startsWith("3.3.1") for MC 1.20.1 and calls
// System.exit(1) otherwise ("Installed version: 3.4.1 / Required version:
// 3.3.1"). The launcher's JavaApp overlay Version.java/VersionImpl.java had
// hardcoded the reported version to "3.4.1" (added for Sodium 0.9+ on 26.x,
// which requires the 3.4.1 prefix), so every 1.18-1.20.x modpack with sodium
// 0.4+/0.5+ was rejected. The overlay now reports dynamically: Tools.java's
// preProcessLibraries captures "org.lwjgl:lwjgl:<ver>" from the instance's
// version.json (the same value Mojang paired with that MC version, which is
// exactly what sodium's REQUIRED constant derives from) into the
// org.lwjgl.version.report system property, and Version.getVersion() reads it
// live (fallback: -Dpojav.lwjgl.version=341 -> "3.4.1", otherwise "3.3.1").
// Bytecode-level proof: reflecting into the pack's actual sodium-fabric-
// 0.5.13+mc1.20.1.jar, isUsingKnownCompatibleLwjglVersion() returns false
// under the old hardcoded 3.4.1 and true under the fixed 3.3.1 report.
// PojavLauncher.java's LWJGL sanity log additionally escaped a brace bug that
// had trapped it inside the vulkan-only branch since introduction (the line
// never appeared in any device log). Purely launcher-side Java; no MobileGlues
// converter surface touched, so REVISION stays 17. The fixed build identifies
// itself on device by the pair "[Tools] LWJGL report version: 3.3.1 (from
// version metadata...)" + "[PojavLauncher] LWJGL selected by launcher: 333,
// reported version: 3.3.1 (metadata: 3.3.1)" -- and by the absence of the
// sodium "not compatible" exit.
// REVISION 17 addendum (Task 95, no bump): the 96c527f upload (commit 1ee7111
// build, BMC2 [FABRIC] 1.20.1, 536 mods, iPad Air M4 / iPadOS 27) verified the
// Task94 fix on device -- "[Tools] LWJGL report version: 3.3.1" and "[PojavLauncher]
// LWJGL selected by launcher: 333, reported version: 3.3.1 (metadata: 3.3.1)"
// both present, Sodium 0.5.13 passed its gate, and startup sailed into full mod
// init (deepest BMC2 run yet). The new crash is a different layer: the instance's
// mods folder is missing 8+ jars (the whole FTB suite ftbquests/ftblibrary/
// ftbteams/ftbbackups, balm, terrablender, kleeslabs -- zero of them in the
// "Loading 536 mods" list), while config/fabric-loader.json dependencyOverrides
// ("Dependencies overridden for certain_questing_additions, kleeslabs,
// netherportalfix, climaterivers, biomeswevegone") masked Fabric's clean missing-
// dependency rejection, so the pack died at the 'main' entrypoint with
// NoClassDefFoundError: dev/ftb/mods/ftblibrary/config/ui/EditConfigScreen
// (certain_questing_additions) + suppressed Balm/TerraBlender chains. Launcher-
// side hardening, no MobileGlues surface touched, REVISION stays 17:
// (1) ModpackImportService writes import_report.json into the instance root at
//     every import finale (failed/skipped lists + acknowledged flag; a clean
//     re-import rewrites it empty);
// (2) JavaLauncher's ImportGuard reads it pre-JVM and shows a one-shot reminder
//     when unacknowledged missing files exist (non-blocking, "[ImportGuard]
//     Task95" anchor);
// (3) PLCrashView gains CrashTypeMissingMods: parses "Could not execute
//     entrypoint stage" + ClassNotFoundException/NoClassDefFoundError chains,
//     maps dev.ftb.mods.*/net.blay09.mods.balm/terrablender.* to friendly names,
//     and surfaces the "Dependencies overridden" evidence in the crash UI.
// FAQ 27->28 (+missingMods entry). On-device anchors: "[ModpackImport] Task95:
// import report written ...", "[ImportGuard] Task95: incomplete import detected
// ...", and the crash view's missing-mod class list.
// REVISION 17 addendum (Task 97, no bump): the 2f90d13 upload (commit 6c3d49d
// build, BMC2 [FABRIC] 1.20.1, 474 mods, zink, iPad Air M4 / iPadOS 27) -- the
// user partially applied the Task95 advice (removed certain_questing_additions,
// balm/kleeslabs/terrablender now present, dependencyOverrides line gone), and
// startup reached the deepest point ever: all mods loaded, window init, resource
// reload, paintings json parsing -- then died at the 'main' entrypoint on TWO
// mods whose crashes share one root cause: the launcher passed -Duser.dir=
// <gameDir> but never chdir()'d, so java.io.File (raw process CWD) and
// java.nio.Files/Paths (user.dir) resolved relative paths against two DIFFERENT
// directories. paintings (Paintings++ 11.0.0.1) PaintingPackReader.scanPacks:
// Files.exists/isDirectory("./resourcepacks") true via user.dir, then
// folder.toFile().listFiles() NULL via process CWD -> Arrays.stream(null) NPE;
// sparsestructures 2.1.2: CONFIG_FILE_PATH.toFile().exists() false via CWD
// (guard passes), Files.createDirectories("config/sparsestructures.json5") hits
// the pack-shipped file via user.dir -> FileAlreadyExistsException. Desktop
// launchers always run java with CWD == game dir, which is why the same pack
// never trips there; both signatures reproduced bit-for-bit on a local JDK
// (verify_task97 D-section). Fix: JavaLauncher ame97_alignProcessCwdToGameDir
// chdir()s to the game dir (+ $PWD sync) immediately before both JLI_Launch
// sites (game + headless); failure is non-fatal with a "[CwdAlign] Task97"
// forensic anchor. Side-effect audit: latestlog capture is absolute-path pipe
// based, all dlopens resolve via @rpath/@loader_path, ObjC file IO is
// NSHomeDirectory/NSBundle-absolute -- no relative-path victims. Bonus: log4j's
// "Cannot access RandomAccessFile logs/latest.log" ENOENT (relative path into
// the old CWD) disappears, and the game writes real logs/ into the instance dir
// like desktop. FAQ 28->29 (+cwdMismatch). Launcher-side only, REVISION stays 17.
// REVISION 17 addendum (Task 98, no bump): the 2af8c45 upload (commit 6c3d49d
// build, MC 26.3 Fabric modpack, 110 mods incl. sodium 0.9.2 + iris 1.11.6, MG
// renderer, iPad Air M4) crashed renderer-independently at MC's
// NativeLibrariesBootstrap fifth load item: "Description: Loading library SDL" /
// NoClassDefFoundError org/lwjgl/sdl/SDL. Sodium's own LWJGL gate PASSED (Task94
// reporting 3.4.3 worked; the mod list printed and startup ran ~2s deep) -- the
// failure is the launcher's LWJGL set selection: the version ID was the Fabric
// form "fabric-loader-0.19.5-26.3-e4ecd7db", and ResolveLwjglVersion's old
// parser (split by ".", read parts[0]) saw "fabric-loader-0" -> intValue 0 ->
// LWJGL 333 picked, whose bundled jar set has no lwjgl-sdl classes (only the
// 341 set ships lwjgl-sdl.jar; MC 26.3 moved windowing/input from GLFW to SDL3
// and requires the SDL bindings). All previous 26.3 device sessions used
// vanilla-form IDs ("26.3-rc2" etc.) that the old parser happened to read
// correctly, so the blind spot only surfaced with the first Fabric modpack.
// Fix: new shared helper ame98_mcMajorFromVersionId (exported via
// JavaLauncher.h) -- 1.x-line early-out (protects "1.20.1-forge-47.3.0"'s forge
// build number 47 from being year-misread), then an anchored year regex
// "(?:^|[-_])(\d{2})(?=[.w])" that reads the MC major from any ID form
// ("26.3" / "26w14a" / "fabric-loader-0.19.5-26.3-e4ecd7db" -> 26;
// "fabric-loader-0.19.3-1.20.1-9c2ee306" -> 1; "25w45a" -> 25). Used by BOTH
// ResolveLwjglVersion (auto path -> 341 for >=26, "[LWJGLSel] Task98" anchor)
// and SurfaceViewController's ame87 LTW x 26.x gate (which had the same
// first-hyphen blind spot and would have let Fabric 26.x packs through to the
// guaranteed LTW title-screen crash). FAQ 29->30 (+mc26sdl: the log signatures,
// the prefix-blind selection explanation, the manual 3.4.1 profile override as
// old-build self-help). Launcher-side only, REVISION stays 17.
// REVISION 17 addendum (Task 99, no bump): two launcher-side fixes, both from
// the b919e0f/2253a10 device-log pair (7ed3d01 build). (A) MC 26.3 release's
// Window.<init> -> MacosUtil.disableCloseWindowMenuItem walks AppKit via
// jna-objc (NSApplication/NSMenu) which iOS does not have -> NoSuchMethodException
// "Initializing game" crash; JavaLauncher now registers minimal ObjC stub classes
// before JLI_Launch ("[AppKitStub] Task99" anchor, resolveInstanceMethod safety
// net). (B) 1.20.x modpack (BMC2) + zink + FSR: game image shrunk to the
// bottom-left corner -- the EASU upscale output does not reach the readback
// client buffer on this path (26.3-rc-3 same code renders full-screen);
// osm_bridge EASU pass now pins texture unit 0 + uInputTex, carries a one-shot
// GPU probe (glReadPixels top-strip pixel), a 120-swap condition heartbeat, a
// 90-frame CPU top-strip landing probe, and an automatic CG-stretch fallback
// presenting the game region full-screen via CoreAnimation when EASU is
// verified not landing ("[OSMBridge] Task99" anchors). FAQ 30->32
// (+macMenuStub, +fsrCorner). Launcher-side only, REVISION stays 17.
// REVISION 17 addendum (Task 100, no bump): two follow-ups from the
// f6352dc/7a30912 device-log pair (ccabe82 build = Task99 IPA, both problems
// still present on device). (A) 26.3: the Task99 stubs worked
// (sharedApplication returned the stub app) but MC 26.3's MacosUtil then
// fetched "windowsMenu" which hit the generic nil no-op -> jna-objc returned
// Java null -> NPE "because windowsMenu is null" at MacosUtil.java:27;
// NSApplication stub now answers windowsMenu/appleMenu/helpMenu/servicesMenu
// with the shared NSMenu stub ("[AppKitStub] Task100: windowsMenu requested"
// anchor). (B) BMC2 1.20.1 + zink + FSR: Task99's probes were all green (GPU
// probe alpha-stamped, CPU probe 88/90 nonzero -> verdict=1, heartbeat stable
// to swap#1080) yet the screen still showed the live game shrunk bottom-left
// -- proof the driver's glFinish readback fills the client buffer with a
// stale/pre-EASU image (nonzero top-strip = residue, misread as landing);
// osm_bridge now performs an authoritative present: after glFinish it binds
// fb0, glReadPixels the full surface into a scratch buffer, row-flips it into
// a driver-untouched present buffer, and the CGImage wraps THAT (the driver
// readback is bypassed for display entirely; bundle.buffer kept only for a
// forensic dual-track probe -- fb probe drives the verdict, driver probe
// reports transport health) ("[OSMBridge] Task100" anchors). FAQ content
// refreshed in place (macMenuStub/fsrCorner, count stays 32). Launcher-side
// only, REVISION stays 17.
#define REVISION 17
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
// REVISION 17 addendum (Task 103, no bump): two fixes from the a605099/
// c241276/446b2a0 device-log triple (d37670e build = Task100 IPA). (A) 26.3
// modpack world-entry crash: sodium 0.9.2+mc26.3's block_layer_opaque.vsh
// died in GLSL preprocessing ("preprocessor directive cannot be preceded by
// another token") -> solid_terrain pipeline missing -> Render Frame crash.
// Root cause byte-level proven: sodium's three include files (globals.glsl
// ends '};', fog.glsl ends '}', chunk_vertex.glsl ends '#endif') all lack a
// trailing newline, and Natives/shaderc_include.c appended the '#line'
// fixup directly after the content -> the directive glued onto the last
// token line. All 17 vanilla includes end with '\n', which is why only the
// first sodium shader of the session died (compile#406, 405 vanilla
// compiles passed). Fixed by guaranteeing a newline before the '#line'
// append (repo-local repro with the real Modrinth jar shaders: 3 glued
// sites -> 0). (B) BMC2 corner-shrink: the Task100 present path still
// showed the raw game in the corner while BOTH probes read 89/90 nonzero --
// glReadPixels itself serves pre-EASU/stale content on this path, so the
// "authoritative readback" inherited the same untrustworthy transport. The
// EASU fragment shader (osm_bridge string surgery only, shared header
// untouched) now stamps a per-frame sentinel byte (1..254) into the alpha
// channel of output pixel (0,0) -- display ignores alpha
// (kCGImageAlphaNoneSkipLast), the swap path reads it back: 3 consecutive
// matches = EASU landed -> full-surface present; 3 consecutive misses =
// pre-EASU/stale transport or draw not landing -> CG stretch of the raw
// game region (full-screen geometry either way); 10 consecutive opposite
// votes flip the verdict across game-phase changes. GPU probe extended
// with a pre-glFinish sentinel read; verdict logs add a one-shot
// present-vs-bundle memcmp (same-source transport forensics); heartbeat
// gains mk=N/M. FAQ 32->33 (+sodiumGlsl, fsrCorner refreshed). Launcher
// side + shaderc_include.c only, REVISION stays 17.

// REVISION 17 addendum (Task 104, no bump): two fixes from the 341c110
// log pair (d00d695 build). (A) 26.3 FSR stuck at 30fps: MC 26.3's
// FramerateLimitTracker runs SHORT_AFK (min(maxFps,30)) when
// inactivityFpsLimit==AFK (26.3 default) and no MC-visible input for 60s
// -- modpack loading takes minutes -> the whole load + idle phases were
// capped at 30 (watchdog caught the render thread parked in
// FramerateLimiter.limitDisplayFPS). Fix layers: MCOptionUtils dedup
// (last-line-wins at MC load made our minimized write fragile) + on-disk
// post-save verification log; input_bridge_v3 AFK heartbeat pushes a
// (0,0) SDL_MOUSEWHEEL every 45s -> MouseHandler.onScroll calls
// onInputReceived unconditionally after the handle check, so the 60s
// clock can never expire while the game runs. Zero side effects:
// overlay!=null skips the body, in-game (0,0) wheel early-returns.
// (B) BMC2 corner-shrink round 3: the (0,0) sentinel proved only that
// SOME EASU fragment ran in the corner -- coverage remained unproven.
// The EASU fragment shader now stamps the same per-frame marker at the
// FAR corner too (top-right 4x4 block); the vote requires BOTH markers
// -> corner-only coverage flips the verdict to NOT LANDED and the CG
// stretch fallback takes over (geometry full-screen either way; fallback
// upgrades layer filters to Linear, LANDED restores Nearest). One-shot
// Task104 viewport check logs what the driver actually holds after
// glViewport. Desktop anchor lines: '[InputDiag] Task104 AFK heartbeat',
// '[PojavLauncher] Task104 on-disk verification', '[OSMBridge] Task104
// EASU viewport check', 'far=N/M' in the swap heartbeat.

// REVISION 17 addendum (Task 105, no bump): the c947464 log pair (bacbf1e
// build) closed both open questions. (A) 26.3 FSR "stuck at 30fps" is
// fixed-and-load: the AFK cap never engaged (no FramerateLimiter watchdog
// hits, inactivityFpsLimit=minimized verified on disk, heartbeat #1 seen);
// fps fluctuated 19-44 with memory peaking 5.4GB at view distance 32 and
// recovered 30->44+ still climbing after the user dropped to 16 -- pure
// GPU/CPU load, FAQ fpsUnlock now carries the guidance. (B) BMC2 1.20.1
// corner-shrink root layer finally isolated: dual sentinels LANDED (EASU
// pass covers the full surface, present==bundle byte-identical, 60fps)
// yet the GPU probe top-strip RGB read 000000 -- the EASU input region
// itself held a shrunk MC frame with black padding. i.e. MC-1.20.1/GLFW
// + BMC2's mod set presents into fb0 at a smaller region than the
// launcher-told window belief (vanilla 1.20.1 decompiled clean: blit uses
// glfwGetFramebufferSize == shim 1814x1262). Fix (renderer-side, immune
// to the upstream mod cause): osm_swap_buffers now reads the live GL
// viewport at swap time -- MC 1.20.1's final present blit sets
// _viewport(0,0,w,h) immediately before RenderSystem.flipFrame, so the
// query returns exactly what MC painted into fb0 this frame. The EASU
// input region, the landing probes, and the CG-stretch crop all follow
// this effective size. Gates: origin must be (0,0), positive dims that
// fit the surface, and area >= 1/4 of the window belief (aux/shadow
// viewports rejected -> fall back to the belief = old behavior). Viewport
// == belief (26.3/SDL path) -> byte-identical behavior; viewport ==
// surface (healed full-res path) -> EASU correctly skipped. Forensics:
// one-shot '[OSMBridge] Task105 viewport evidence: MC present viewport
// 0,0 WxH vs launcher window belief WxH -- match/DIVERGED/gated' per new
// size (pins the upstream mod number next round), and the Task99 swap
// heartbeat gains 'vp=WxH (adaptive)'. Desktop anchor lines:
// '[OSMBridge] Task105 viewport evidence ... DIVERGED: EASU input follows
// MC (adaptive) -- geometry restored' + 'vp=' in the swap heartbeat.
// Verifier maintenance: verify_task100 D14 anchor follows the code
// (upscale call now passes effW/effH); verify_task103 F3 re-anchored to
// the Task104 FAQ wording (far=N/M); task103_syntax_swap + verify_task85
// D1 stubs gain ame83_resolve_gl + gl.glGetIntegerv + GL_VIEWPORT.

// REVISION 17 addendum (Task 106, no bump): the 41cdff0 log pair (2e1ea09
// build) resolved both open issues. (A) BMC2 1.20.1 "crash on creating a
// world": the session reached world creation for the first time (previous
// sessions never got past the title screen), the server bootstrap hit
// spark's "Starting background profiler...", spark extracted its bundled
// spark/macos/libasyncProfiler.so (FAT x86_64+arm64, arm64 slice carries a
// real LC_CODE_SIGNATURE, platform=macOS) into config/spark/tmp/*.tmp and
// System.load()ed it -- the FIRST library ever to hit the
// PLPatchMachOPlatformForFile retag path on this device (0 occurrences in
// all prior logs). The macOS->iOS platform retag mutates the mach header,
// invalidating the code signature; dyld's signature validation then kills
// the process (silent SIGKILL -- no hs_err, no fatal trace; the log's last
// line is literally the "[Amethyst] Patching ...libasyncProfiler.so.tmp").
// Unsigned home-dir libs retag harmlessly (that is why every other lib
// works); signed ones die. Fix (two layers): hooked_dlopen blocks
// libasyncProfiler loads outright -- spark's own bytecode (1.10.53
// AsyncProfilerAccess.load) catches UnsatisfiedLinkError and degrades to
// its Java sampler, so world creation proceeds; and the retag path now
// neutralizes LC_CODE_SIGNATURE (in-place rewrite to the same-size benign
// LC_SOURCE_VERSION + zeroed blob) so any OTHER signed macOS dylib a mod
// extracts loads as unsigned instead of badly-signed. Desktop anchor:
// '[Amethyst] Task106: blocked dlopen of signed macOS profiler lib'.
// (B) 26.3 zink+FSR "still locked at 30fps": verdict REVISED -- Task105's
// "pure load" closure was wrong (its 44fps reading was the pause-menu
// moment, and in this session the user doubled the FSR scale (preset 1 ->
// 4, render pixels -58%) with fps unchanged at 28-30 -- a
// resolution-independent constant dominates the frame budget). The zink
// path was doing TWO full-surface GPU->CPU readbacks per frame (the
// driver's glFinish readback + Task100's authoritative glReadPixels) plus
// a 15.5MB row-flip memcpy. Fix: bundle-direct present -- the Task103
// dual sentinels (markerCode cycles 1..254 per frame) give per-frame
// ground truth that bundle.buffer holds THIS frame's full-surface EASU
// output; after 30 consecutive fresh frames the launcher skips the
// duplicate readback + row-flip and presents the driver buffer directly
// (OSMESA_Y_UP=0 is already top-down). Two consecutive sentinel misses
// revert to the authoritative path; the marker vote state machine is
// shared (ame103_marker_vote) between the scratch and bundle feeds.
// Plus per-phase timing instrumentation in the swap heartbeat (t=swap /
// [pre+easu glFinish readback] / frame / MC-side) so the next log
// decomposes the remaining frame budget exactly. Desktop anchors:
// '[OSMBridge] Task106 bundle-direct present engaged' + heartbeat
// 'bd=N/M t=swap ... MC-side=...ms'. Good news pinned by the same log:
// the BMC2 corner-shrink is FIXED on device by Task105 (vp=907x631
// adaptive, 60fps, full-screen geometry). FAQ 33->34 (+sparkProfiler);
// fpsUnlock carries the corrected verdict + timing-field guide; stale
// sync: FAQ count 33->34 across 12 verifiers (task106_faq_sync.py),
// verify_task100 D13 re-anchored to the bundle-direct present gate,
// verify_task105 E2 re-anchored to the Task106 wording; syntax gates
// (task83_syntax_osm.sh / task103_syntax_swap.py / verify_task85 D1)
// gain ame106/mach/vote-helper stubs.

// REVISION 17 addendum (Task 107, no bump): dyld_patch_platform.m now RE-SIGNS
// (ad-hoc) every library it platform-retags, replacing Task106's signature
// neutralization. The ce43a34 log pair (6a81ba5 build) proved the neutralized
// form fatal: iPadOS 27's dyld4 hard-rejects ANY dlopen'ed image without a
// code-signature blob ("missing code signature in <uuid>") while tolerating
// stale ad-hoc hashes in a debug-signed process -- so rewriting
// LC_CODE_SIGNATURE to LC_SOURCE_VERSION + zeroing the blob turned every
// previously-loadable retagged ad-hoc lib into a guaranteed dlopen failure.
// JNA's libjnidispatch was the first casualty (its LC_UUID matches the
// reported uuid verbatim): both sessions lost JNA, and 26.3 crashed outright
// at MacosUtil.disableCloseWindowMenuItem -> ca.weblite.objc.Runtime ->
// JNA (no degradation path), while 1.20.1 merely degraded (oshi caught,
// junixsocket suppressed) and ran on -- blurry. The re-signer (pure C in
// Natives/ame107_codesign.h, SHA-256 backend injected as a function pointer:
// CommonCrypto on device, OpenSSL in scripts/task107_harness.c) rebuilds a
// v0x20400 CS_ADHOC CodeDirectory over [0, dataoff) with SHA-256 4K-page
// hashes and swaps it in place (thin files may grow via realloc + ftruncate
// with __LINKEDIT filesize/vmsize kept in cover; FAT slices stay in place or
// keep the stale signature with a capped warning -- spark's team-signed FAT
// remains blocklisted by hooked_dlopen). Page-0 load commands are finalized
// BEFORE hashing (datasize tightened first), and any build failure rolls the
// header back to the original stale state. Device anchors: '[Amethyst]
// Task107: re-signed ad-hoc after platform retag (in place/grown)' and the
// warn variants. Same log pair's second finding: BMC2 1.20.1 blurriness =
// sodium-extra 0.5.4 reduce_resolution_on_mac halving the framebuffer under
// the launcher's Mac spoof (vp=590x410 vs belief 1180x820, exactly half;
// EASU then 4x-upscales to the 2360x1640 panel); PojavLauncher now flips
// config/sodium-extra-options.json's reduce_resolution_on_mac to false at
// launch (anchor '[PojavLauncher] Task107: sodium-extra
// reduce_resolution_on_mac true->false ...'); FAQ sparkProfiler amended +
// blurry gains cause #5 (both in place, count stays 34, zero cascade).

// REVISION 17 addendum (Task 108, no bump): two follow-ups on 382432d. (1) CI
// fix: the Task107 rewrite of dyld_patch_platform.m accidentally dropped the
// bare 'extern int dyld_get_active_platform();' declaration that every prior
// revision carried (<mach-o/dyld.h> declares it behind __API_AVAILABLE
// (macos(12.0), ios(15.0)) -- too new for this deployment target, hence the
// manual extern). CI's clang (C99+ mode, implicit-function-declaration is an
// error) failed the 382432d build at dyld_patch_platform.m:84 with exactly
// one error; the declaration is restored verbatim (the old include set
// already covered every other syscall in the file -- open/pwrite/ftruncate/
// read/fstat/pthread/CC_SHA256 -- proven by the CI-green Task106 build).
// (2) sodium-extra revert, user decision: the user confirmed the BMC2 1.20.1
// blurriness was their own configuration (reduce_resolution_on_mac was on by
// their own choice -- an fps measure), and the launcher must not rewrite the
// user's mod config on every launch. PojavLauncher's patchSodiumExtraResolution()
// is removed (call + method); the mechanism knowledge moves to the FAQ page
// ('画面模糊' cause #5 now tells the user to toggle the mod's own setting:
// 视频设置 → sodium-extra 设置 → 性能 → Mac 下降低分辨率; fps-seekers use the
// FSR preset instead). The '[PojavLauncher] Task107: sodium-extra
// reduce_resolution_on_mac true->false' anchor is retired with it. The 26.3
// re-signing fix (fix A) is untouched.

// REVISION 17 addendum (Task 109, no bump): the 698c6fe log pair (both sessions
// on 38fb316) closes the "26.3 modpack locked at 30fps but vanilla fine"
// question with per-phase data and ships a self-stabilizing experiment.
// VERDICT (superseded by Task 110 same log pair): the 30fps pin on the
// modpack is dynamic_fps 3.11.10 seeing an UNFOCUSED window (SDL focus bit
// never set -- see Task 110); the modpack session also measured MC-side
// 21-36ms/frame + our present ~10ms during its 13-second load-storm stay,
// vs vanilla's MC-side median 3.3ms + the SAME present ~10ms = 53fps median
// ("normal"). Zero VANILLA limiter hits (FramerateLimiter, maxFps=260, no
// vsync) -- the mod's throttle was invisible to our watchdog because it
// lives outside the vanilla classes we monitor. The launcher present path is identical across both
// sessions (glFinish phase ~8-15ms regardless of scene -- the heavier modpack
// session actually reads LOWER) = fixed driver
// sync/readback constant; our own authoritative readback (glReadPixels full
// surface + row-flip) measures only ~4ms/event, so the cost is NOT the data
// movement but the driver glFinish's internal synchronization. EXPERIMENT
// (osm_bridge.mm Task109 no-finish trial): in two fixed FSR-frame windows
// (FSR frames 300-419 and 1020-1139, 120 frames each) the driver glFinish is SKIPPED and the
// authoritative glReadPixels path (with its internal sync) takes over
// presenting; phase timing then shows [glFinish ~0 | readback +sync] vs
// neighbor windows -- the A/B decides next round (adopt permanently if
// cheaper; if not, the wait is inherent GPU completion and only the CA
// direct-present / IOSurface zero-copy architecture remains). Safety: the
// authoritative path is the same one that runs for the first ~30 frames of
// every session (incl. its circuit breaker); sentinel voting is skipped
// inside the window (bundle is stale by design, no false fallback logs); if
// the authoritative path fails mid-window a LATE glFinish runs so the legacy
// bundle wrap still shows the correct frame -- the screen can never break;
// non-FSR frames/sessions are untouched (legacy present needs the driver
// readback). Window enter/exit log lines carry trial-vs-baseline averages:
// '[OSMBridge] Task109 no-finish trial: window opens/closed ...'. FAQ
// fpsUnlock's modpack-vs-vanilla bullet was later re-attributed to the
// dynamic_fps root cause by Task 110 (same file). Binary forensics started:
// libOSMesa.8.dylib is Mesa 25.0.7 (git-742a20f48c) built from
// /Volumes/D/mesa-source gallium osmesa target; export trie parsed
// (OSMesaCreateContextAttribs 0x4078 / OSMesaMakeCurrent 0x4970 / glFinish
// 0x9204); MakeCurrent's format dispatch confirmed RGBA+UBYTE -> internal
// 0x33 vs BGRA+UBYTE -> 0x36 (formats DO diverge internally -- a BGRA client
// switch remains a candidate micro-opt if the no-finish trial fails).

// REVISION 17 addendum (Task 110, no bump): ROOT CAUSE of "26.3 modpack
// pinned at 30fps while vanilla runs free" -- dynamic_fps 3.11.10 sees an
// UNFOCUSED window. Chain: the user reported the pack stuck at 30 (698c6fe
// modpack session, 38fb316 build) while pure vanilla 26.3 was "completely
// normal"; the pack's mod list contains dynamic_fps 3.11.10, vanilla does
// not. Decompiled the ACTUAL Modrinth jar (dynamic-fps-3.11.10+minecraft-
// 26.3.0, nested common jar): WindowObserver's constructor queries
// SDLVideo.SDL_GetWindowFlags & SDL_WINDOW_INPUT_FOCUS (0x200) directly --
// it does NOT use vanilla's Window.focused (which starts true and is only
// flipped by SDL events 526/527 that we never deliver -- hence vanilla
// behaves fine). The power state machine
// focused ? (idle?ABANDONED : ... FOCUSED) : (hovered?HOVERED :
// (iconified?INVISIBLE : UNFOCUSED)) had ALL THREE inputs broken by our
// embed mode: the hidden SDL UIWindow (Task 32/49 anti-black-cover) holds
// no input focus (0x200=0), no mouse focus (0x400=0), and is flagged
// HIDDEN (0x4) -- so the mod sat in a throttle state (its defaults:
// unfocused=1fps, invisible=0fps; the device pinned at the observed 30
// per its config/render floor). Task 50's flag hook only stripped
// MINIMIZED (0x40, for renderpearl's acquireNextTexture); the focus bit
// was the escapee. FIX (sdl3_hook.m ame_SDL_GetWindowFlags): return
// (flags | SDL_WINDOW_INPUT_FOCUS) & ~MINIMIZED & ~HIDDEN -- completing
// the same harmless lie: in embed mode the game view IS the foreground
// focus and the visible picture; iOS freezes the app in the background
// anyway, so focus=1 is always true when it matters. With focus set the
// mod's machine short-circuits into FOCUSED (Config.ACTIVE,
// frame_rate_target=-1 = unlimited); the idle branch (ABANDONED, 10fps,
// default timeout 300s) is neutralized by the Task104 45s wheel heartbeat
// feeding IdleHandler.onActivity (mouse events 1536-1539 family, verified
// in the decompile). Vanilla's ONLY flags consumer is Window.isFullscreen
// (& 1 FULLSCREEN) -- untouched; renderpearl's MINIMIZED strip retained.
// Reachability proven: LWJGL SDLVideo resolves through the same hooked
// dlsym path Task 50's MINIMIZED strip already validated on device
// (622166a). FAQ fpsUnlock bullet re-attributed to this root cause with
// the [SDLHook] Task110 anchor. Task 109's no-finish experiment stands
// unchanged (the 8-15ms present constant is a separate, real cost).
//
// REVISION 17 addendum (Tasks 112-118, launcher 5.1.0 release train; no MG
// bump -- all changes are launcher-side):
//   Task 112 (OpenAL NPE on 26.3): SoundEngine -> Library.createDeviceTracker
//   -> CallbackDeviceTracker.isSupported() passed alcIsExtensionPresent(
//   "ALC_SOFT_system_events") but LWJGL's SOFTSystemEvents ICD pointer was
//   NULL -> Checks.check NPE -> crash. Our bundled libopenal.dylib (1.21-1.23
//   era, no such extension) always fell back cleanly -- so the crashing openal
//   had to come from a classpath-hijacked natives jar (LWJGL loadNative
//   bundledWithLWJGL=true prefers classpath resources over java.library.path).
//   FIX: -Dorg.lwjgl.openal.libname pinned to the absolute Frameworks path
//   (absolute paths bypass classpath extraction entirely).
//   Task 113 (MobileGL Vulkan): prebuilt libMobileGL.dylib vendored from the
//   upstream-verified caf6822 build (DirectVulkan: GL -> Vulkan -> MoltenVK ->
//   CAMetalLayer direct present, readback-free; upstream device log shows it
//   smooth where the OSMesa readback path carries an 8-15ms present constant).
//   Entry point is the mobilegl_vulkan switch next to the ANGLE ES driver
//   setting (user request: keep the renderer LIST uncluttered); the GLES
//   variant is intentionally NOT shipped (other backends misbehave upstream).
//   Task 114 (keyboard would not auto-open when a text field had a blinking
//   cursor): ported the upstream caf6822 SDL hooks verbatim -- Start/Stop
//   TextInput + StartTextInputWithProperties + SetTextInputArea marshalled to
//   the main thread (SDL's iOS backend touches UIKit from the render thread
//   otherwise), and SDL_InitSubSystem sets SDL_ENABLE_SCREEN_KEYBOARD=1 to
//   override MC's desktop-convention 0 (plus RETURN_KEY_HIDES_IME and the
//   srgb-framebuffer hint for bridge renderers).
//   Task 115: UpdateChecker now targets Gsjsjzhznsz/Air-Minecraft-iOS-Launcher
//   (was pointing at the upstream repo).
//   Task 116: 12 preference.detail.* keys + 4 crash.* keys added to zh-Hans
//   and en (the settings page showed raw keys in detail mode after the UI
//   refresh tasks).
//   Task 118 (background focus release, complements Task 110): the Task 110
//   focus lie is now state-dependent -- foreground keeps (f|0x200)&~0x40&~0x4
//   (30fps pin fix intact); on UIApplicationDidEnterBackground the 0x200 bit
//   is released (still stripping 0x40/0x4) so dynamic_fps-class mods read
//   UNFOCUSED and legitimately throttle during the background transition
//   window (default 1fps); WillEnterForeground restores the Task 110
//   expression. Deliberately NOT INVISIBLE (0x4 passthrough would hit 0fps
//   and risks aggressive side effects in other mods).
//   Task 119 (MobileGL FSR): mgl_fsr.mm pre-swap EASU pass -- the 5.1.0 field
//   report "mg vulkan path FSR shrinks instead of upscaling" was the Task83
//   window-shrink linkage meeting a MobileGL path with NO upscaling hook;
//   MC rendered into the bottom-left corner of the full-size swapchain image
//   and eglSwapBuffers presented it curled. The new pass captures the render
//   region and EASU-upscales it into the default framebuffer (= the MobileGL
//   swapchain image) right before eglSwapBuffers, GPU-side, zero readback.
//   Task 120: mobilegl_vulkan (unconditional override) retired in favor of
//   the single mobilegl_backend pick (Vulkan default / GLES / Mithril /
//   off) with ame_effective_renderer() as the single source of truth --
//   explicit renderer selections now always win (the 1d4ff3a9 session had
//   zink silently swapped to MobileGL Vulkan).
//   Task 121: l10n parity -- en/zh-Hans were missing 23 keys, zh-CN/zh-Hant
//   22 behind; all four key sets now identical, pick rows show localized
//   labels instead of raw stored values.
//   Task 124: the 774fa7871-build crash verdict (zink -> vk override +
//   NSInvalidArgumentException naturalDrawableSizeMVK on a plain CALayer)
//   closed by the Task120 single-source renderer + explicit-selection
//   priority + CAMetalLayer for all MobileGL paths.
//   Task 125: auto update check on launch (general.auto_update_check,
//   default on) -- silent unless a newer release exists, then an in-app
//   neumorphic toast (NMToast) with a View action; never a modal dialog.
//   Task 126: showDialog's level-1000 UIWindow leaked after OK (the
//   "system popup you must manually dismiss" complaint) -- the OK handler
//   now hides the alert window and restores the previous key window;
//   Microsoft-login success/status notices moved to auto-dismissing toasts.
//   Task 127: all sub-level panels get the neumorphic base style via
//   UIViewController+NMPanel, enforced at one point (LauncherNavigation
//   Controller push + root), idempotent, transparent-by-design panels skip.
//   Task 128 (third-party login completely broken, zl2-referenced): three
//   stacked fixes -- (a) authlib-injector jar now bundled in the app
//   payload (Natives/resources/authlib-injector-1.2.7.jar; POJAV_HOME
//   copy installed locally from the bundle, network download demoted to
//   last-resort fallback), so login/launch never hard-depends on a download
//   again; (b) account selection no longer hard-fails when the Yggdrasil
//   refresh rejects an expired token -- the account is still selected with
//   a re-login toast (skins/server-auth may be limited), session-validated
//   accounts skip the refresh entirely (zl2 isSessionValidated semantics);
//   (c) explicit accountType marker ("thirdparty"/"microsoft"/"local") saved
//   at login and honored by every classifier (three divergent key-sniffing
//   discriminators unified; legacy files fall back to the old sniffing).
//   Launch-time agent wiring additionally falls back to the bundled jar when
//   the POJAV_HOME copy is missing (the silent 401 chain's missing link).
