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
//   Task 129 (v5.1.0 field report, eight fixes): (a) 26.1.2 modpack crash =
//   OpenAL ALC_SOFT_system_events NPE -- MC 26.1.2's CallbackDeviceTracker
//   calls alcEventIsSupportedSOFT without the alcIsExtensionPresent guard
//   26.3 has, our openal-soft 1.20.1 impl lacks the extension, and LWJGL
//   3.4.1 throws NPE on a NULL ICD slot; fixed by the openal_shim re-export
//   wrapper (advertises the extension + stubs returning ALC_FALSE so MC
//   falls back to PollingDeviceTracker; auto-transparent if the impl is
//   ever upgraded to >=1.25). (b) third-party login FCL parity: multi-
//   server list (saved-server chips, auto-remember after ALI resolution,
//   long-press to remove) + multi-role management (login-time profile
//   picker instead of auto-binding the first; saved accounts carry
//   availableProfiles and offer long-press role switching via
//   switchToProfile/refresh rebind). (c) settings pickers unified back to
//   floating action sheets/popovers on iPhone AND iPad (the old iPad
//   UIContextMenuInteraction + _presentMenuAtLocation private-API compact
//   menu read as a second-level submenu and stopped presenting on
//   iPadOS 27, making FSR/download-source/backend rows unswitchable).
//   (d) MG Vulkan perf defaults: enable_ext_direct_state_access now YES
//   and max_glsl_cache_size 128 -- the old pref defaults (NO/32) silently
//   defeated the code's intended safe defaults via the getPrefObject
//   override chain (device log: "enable_ext_direct_state_access = 0").
//   (e) white-background on some devices (iPad9): a custom background
//   image that fails to decode left the window's systemBackgroundColor
//   (light mode = pure white) visible; both window and splitVC now paint
//   the neumorphic base under the background container and the image
//   loader drops a themed fallback view on decode failure. (f) iPad9
//   treated as a small-screen device: the UIKit idiom hook unconditionally
//   forced Phone; iPads are now always Pad idiom (model-derived, immune
//   to the pref-default evaluation-order trap). (g) launcher announcement
//   load failure: the default feed (air-api.vercel.app) now 404s (domain
//   repurposed); a bundled offline announcement (announcements-fallback
//   .json) serves when both network and cache are empty. (h) MC news
//   images covered by neomorphism: the collection-cell effect injector's
//   "first rounded subview" heuristic picked the thumbnail UIImageView
//   itself, whose neomorph caster sublayers paint over layer contents;
//   content-rendering views (UIImageView/UILabel/UITextView/UIControl)
//   are excluded from card-container detection.
//
// REVISION 17 addendum (Amethyst Task 130, no bump): FSR1 gains the RCAS
//   sharpening pass (mpv FSR.glsl-referenced, AMD FSR1 1.20210629 verbatim
//   32-bit non-packed body). Pipeline: EASU now draws into an offscreen
//   target and RCAS presents (5-tap cross, <0.5ms fullscreen on M-class
//   GPUs); the alpha channel passes through from the center pixel so the
//   Task103/104 per-frame sentinel survives. Sharpness is one preference
//   across all consumers: mobileglues.fsr_rcas_sharpness (mpv scale [0,1],
//   default 0.2, negative = off) -> config.json fsr1RcasSharpness for
//   MobileGlues (new config_get_double) AND the AMETHYST_FSR_RCAS_SHARPNESS
//   env var for the zink (osm_bridge) and MobileGL (mgl_fsr) pre-swap
//   paths; a 7-tier settings pick row sits next to the FSR preset. Any
//   compile/link/FBO failure degrades to EASU-only with a logged reason
//   (per backend: zink, MobileGL DirectVulkan/GLES/Mithril, MobileGlues
//   via __has_include so standalone builds stay EASU-only). Also this
//   round: the account list gains an inline "switch character" button
//   (password-free, shares Task129b's switchToProfile rebind), and the
//   launcher announcements moved to a repo-hosted announcements.json
//   (raw.githubusercontent.com primary + jsDelivr mirror cascade, the old
//   air-api.vercel.app feed is only kept as a known-default sentinel for
//   the customization check).

// REVISION 17 addendum (Amethyst Task 131, no bump): four field fixes from
//   the 1d4082f install. (a) 26.1.2 modpack SIGBUS at 0x12e550010 during
//   world join root-caused: controlify 3.0.1 (26.3 pack lacks it -- the
//   sole differential) loads SDL3 via JNA/libsdl4j; the jar's
//   darwin-aarch64 libSDL3.dylib links Cocoa/AppKit/Carbon (cannot load on
//   iOS), JNA falls back to the launcher's own bundled iOS libSDL3.dylib,
//   then SDLControllerManager registers SDL_SetEventFilter with a JNA
//   callback -- the libffi closure trampoline is a RW non-executable page
//   without the JIT entitlement, and the game-side per-frame
//   pojavPumpEvents -> SDL_PumpEvents -> SDL_PushEvent invokes it ->
//   SIGBUS (exec-of-non-exec on ARM64 Darwin). Fix: sdl3_hook intercepts
//   SDL_SetEventFilter/SDL_AddEventWatch at the dlsym layer (name-based
//   dispatch covers both LWJGL and JNA resolution) as logged no-ops;
//   controlify keeps working through its SDL_PollEvent tick path. (b) The
//   MG three backends return to the renderer floating menu (upstream
//   form): libMobileGL.dylib (Vulkan default) / libMobileGL-gles.dylib
//   (logical key mapped to the shared binary at the physical load sites;
//   MOBILEGL_BACKEND_TYPE selects DirectGLES) / libmithril.dylib
//   (auto-hidden while absent). The Task120 standalone mobilegl_backend
//   pick row is retired (user x4: "setting items still separate" / "second-
//   level entry unusable" -- it only applied under renderer=auto); legacy
//   auto+backend resolution is preserved for existing installs. (c)
//   Third-party profile switching: Blessing Skin servers reject any
//   rebinding refresh on a bound token ("the access token has already
//   been assigned a profile"), so switching now falls back to a fresh
//   /authenticate with credentials secured in the iOS Keychain at login
//   (loginIdentifier persisted on the account json; raw password only --
//   the 2FA-suffixed variant is never stored), then binds the target
//   profile on the new unbound token; without stored credentials the user
//   gets a guided one-time re-login. (d) Pick sheets present from the
//   topmost view controller (a presenting self would be silently
//   rejected) and log an evidence anchor per open.

// REVISION 17 addendum (Task 132, no bump): four field fixes from the 43ef4ae
// install logs. (a) 26.1.2 modpack crash (controlify 3.0.1 -> libsdl4j 3.2.18
// -> JNA): Task131's guards sit at the dlsym-resolution layer, but libjnidispatch
// calls dlsym through ITS OWN __la_symbol_ptr slot, which the startup fishhook
// pass cannot cover for images loaded later (the crash session shows LWJGL
// intercepted while JNA was not -- the same split). hooked_dlopen now detects
// the libjnidispatch load (the JVM's System.load path, proven live by Task106's
// profiler block) and rebinds that image's _dlsym pointer slots to hooked_dlsym
// (Mach-O indirect-symbol-table walk, fishhook's linkedit-base arithmetic,
// runtime page size, idempotent); JNA resolution then flows through
// amethyst_sdl3_hook_resolve and the Task131 no-op guards cover the JNA path
// too (real SDL_ symbols still pass through untouched). (b) The MG three
// backends leave the renderer menu and merge into ONE unified pick row in the
// MobileGlues section (in-place floating popup, exactly three options --
// Vulkan direct / GLES backend / OpenGL 4.0 experimental, Vulkan default;
// user-mandated wording), writing video.renderer directly (same storage layer
// as the renderer row; explicit selection always wins). (c) The TouchController
// child-pane entry is replaced by an in-place three-way popup (disabled / UDP /
// static lib) with its companion rows inlined (vibrate, intensity, move view,
// about); the pane file stays but is no longer referenced. (d) Third-party
// skins: bundled authlib-injector upgraded 1.2.7 -> 1.2.8 (build 56) -- MC
// 26.3+ rewrote authlib's service discovery, 1.2.7 only rewrites the legacy
// URL constants so the new chain bypassed the injection straight to Mojang
// (401, skins fell back to defaults); 1.2.8 adds httpd/DiscoveryFilter for the
// new chain and keeps Java 17/21/25 compatibility.

// REVISION 17 addendum (Task 138, no bump): eight fixes from the c68552a
// four-log install feedback (latestlog = 26.1.2 controlify SIGBUS persists /
// latestlog.old.txt = 26.2 MobileGL-gles SIGSEGV / latestlog.txt = 26.2
// Mithril UnsatisfiedLinkError / latestlog.txt.old.txt = 26.2 OSMesa 60fps
// clean run). (a) 26.1.2 crash FINAL root cause: JNA direct mapping. The new
// crash log proves every Task131/132/133/135 guard engaged as designed (three
// image detections, direct hdr+slide rebind invoked, jnilib slot idempotent
// hit -- the fishhook race hypothesis confirmed) yet the crash persists, and
// it happens BEFORE any SDL symbol resolution: controlify 3.0.1+26.1 bundles
// libsdl4j 3.2.18 whose Native.register path allocates libffi closure
// trampolines via ffi_closure_alloc + RegisterNatives; on iOS those pages are
// RW-only, so the first direct-mapped call jumps to page+0x10 and SIGBUSes
// (0x134ea0010 and 0x119a70010 share the +0x10 libffi free-list signature).
// Fix: setenv POJAV_NATIVEDIR (from POJAV_HOME) so Pojav-aware mods steer to
// the nonexistent libSDL3.so, UnsatisfiedLinkError is caught, controlify
// falls back to GLFWControllerManager and the game runs; verified against
// controlify source (only SDLNativesLoader/CUtil read the var; the 3.5.0 FFM
// loader ignores it). (b) TouchController + hide-controls were broken by
// Task134 writing config.json/order.json with NSDictionary/NSArray
// writeToFile (plist XML) while the mod parses JSON -- kotlinx threw
// JsonDecodingException reading '<', the config fell back to defaults and the
// clean-preset pointer was lost; also the read side (dictionaryWithContentsOfFile)
// could never read the mod's own JSON, so the "preserve mod settings" rewrite
// wiped them every launch. Both files now go through NSJSONSerialization
// helpers (ame138_readJSONDictionary/ame138_readJSONArray/ame138_writeJSON).
// (c) MobileGL-gles SIGSEGV: gl_bridge.m dlsym_EGL and sdl3_hook.m's renderer
// handle fallback used the logical key libMobileGL-gles.dylib verbatim for
// the @rpath dlopen (file does not exist -- the -gles variant shares
// libMobileGL.dylib); the shared mapping now lives in utils.h as
// ame_physical_renderer_dylib and both call sites use it. (d) Mithril pick
// with the dylib absent crashed with UnsatisfiedLinkError: the picker keeps
// all three family options (user mandate) but ame_effective_renderer now
// falls back to auto (ANGLE) with a once-per-process NMToast, and the pick
// handler warns immediately at selection time; new l10n key
// preference.warning.renderer_missing_dylib x4 languages. (e) Home avatar
// could turn square on tab switches: the radius was only set in
// layoutSubviews when bounds were final; a capsule constant (999) now makes
// the square view a perfect circle regardless of layout timing. (f) The
// announcement tile's fixed 90pt height clipped its action button; height is
// now measured from the preview-level text plus button (ame138_announcementTileHeight,
// floor 90) and the section reload animates via performBatchUpdates. (g)
// Download mirror strategy gains a third option "speed first" (FCL-style):
// PLMirrorCenter races official vs mirror per family (BMCLAPI / MCIM) with a
// 24h persisted cache, unknown-results default to mirror order; all four
// policy rows and the moved-in mod mirror row (from the launcher section,
// now a unified coarse control writing assetSearch+assetDownload) default to
// speed_first. (h) Animation polish: home tiles animate only on first
// appearance (no re-fade on scroll-back), item-level stagger, sidebar
// selection color cross-fades in 0.18s.

// REVISION 17 addendum (Task 139, no bump): eight fixes from the 8a6307f
// four-log install feedback (latestlog = 26.1.2 world-join crash /
// latestlog.txt = 26.2 MobileGL-gles input misalignment / latestlog.old.txt
// + latestlog.txt.old.txt = 26.2 static-lib TouchController + clean-layout
// sessions). (a) 26.1.2 world-join crash root cause: NOT a SIGBUS at all --
// voicechat 2.6.17's MicrophoneThread takes the macOS path (Platform.isMac
// spoof), opens our IOSAudioMixer TargetDataLine, and audio_capture_bridge's
// createCapture force-installed the tap with a constructed 1ch/48000 Float32
// format while the hardware input node's native format differs ->
// uncaught com.apple.coreaudio.avfaudio 'Failed to create tap due to format
// mismatch' NSException terminates the app (the three 26.2 sessions had no
// voicechat mod, which is why they survived). Fix: the tap is now installed
// with the input node's native format and the callback linearly resamples
// (absolute-position accumulation, mono mixdown, int16 quantize) to the
// requested rate; the whole creation + engine start is @try/@catch-guarded
// and destroyCapture removes the tap before freeing the capture state
// (use-after-free race). Failure now degrades to no-microphone instead of
// killing the game. (b) MobileGL-gles input misalignment: the 23:08 session
// proves the chain -- Task119's FSR-unavailable heal restored MC's window to
// the full surface (viewport 2360x1640, 'GLFW: Set size 2360x1640') but
// sendTouchPoint kept dividing by mgFsrScale(2.0), so touches landed at a
// quarter of the screen. New ame139_fsr_heal_reset_input_scale() (declared
// in utils.h, implemented in SurfaceViewController.m, called from BOTH heal
// sites -- mgl_fsr Task119 and osm_bridge Task83b) resets the divisor to 1.0
// on the main thread. (c) TouchController static-library mode dead input:
// mode==2 sends ProxyMessages into the native singleton transport, but mod
// 0.3.1-alpha14 (forced onto legacy UDP by TOUCH_CONTROLLER_PROXY from
// Task135) listens on the UDP socket -- menus kept working through the
// launcher's direct input path, in-world touch died. sendTouchControllerProxyMessage
// now dual-sends (native channel + TouchSender UDP; byte-identical wire
// format, mod consumes exactly one). (d) Hide-controls still showing
// controls: mod-side forensics (CFR on the actual Modrinth jar:
// GlobalConfigHolder.currentPreset resolves our empty preset whenever
// status==ENABLED, and the default IS ENABLED; preset files parse clean in
// all four logs) prove the mod side works -- the culprit is the launcher's
// OWN ctrlView (classic Pojav buttons) which never hid. New
// ame139_modControlsHidden gate hides it in loadCustomControls and guards
// both hardware_hide un-hide paths; order.json also moves to preset/ (the
// mod's PresetManager reads presetDir/order.json, the old location was
// never read). (e) Renderer selection resetting to auto: both settings rows
// wrote ONLY the global video.renderer while every launch-path reader
// resolves profile-first -- an instance profile with a stored renderer
// (version manager / instance settings / instance creation) permanently
// shadowed the settings pick. Both rows now dual-write (profile + global,
// ame139_writeRendererBoth), the main row displays profile-first, and
// ProfileSettingsViewController.saveSettings syncs the global key too. (f)
// mg OpenGL 4.0 backend showing 'not built': libmithril.dylib was never
// actually committed (the CI comment lied). Vendored the Mithril-Wrapper
// main-line build (3.5MB arm64 iOS, static MoltenVK, 44 egl + 380 gl
// exports verified from the symbol table) into Natives/resources/Frameworks/
// -- the option ships working now. (g) Forge install demanding manual JIT:
// launchHeadlessJVM now auto-requests (debug.jit_enabler dispatch identical
// to the launch-button flow, waiting dialog + poll) when JIT is off, and
// re-attaches the JIT26 script via stikjit:// on TXM devices when
// CS_DEBUGGED is set but no debugger is live (the RightPanel re-attach
// logic, previously missing in the headless path). (h) iPhone right panel
// streamlined: 168pt full-content column -> 96pt icon rail (username + info
// cards retired on phone, launch/version/jar buttons icon-only, avatar 44pt),
// matching the 56pt left sidebar's FCL-style language.

// REVISION 17 addendum (Task 140, no bump): four fixes from the d089745
// two-log install feedback (latestlog.txt = 26.2 MobileGL-gles session with
// FSR unavailable + blocks-not-rendering report / latestlog.old.txt = 26.2
// Mithril session crashing at GL.createCapabilities). (a) Renderer settings
// layering rebuilt (the "edited a game's renderer, it reverted to whatever
// Settings->MobileGlues had" report): the Task139 dual-write made every
// Settings renderer pick OVERWRITE the current game's per-profile renderer,
// while the game editor's picker never offered the MobileGL family backends
// (Task132 retired them from rendererCandidates and three dylibs missing
// from the bundle filtered the classic list down to 4) -- four writers
// fighting over one storage key. New FCL/HMCL-style split: Settings rows
// (video.renderer + mobileglues.renderer_backend) write the GLOBAL default
// only (ame140_writeRendererGlobal, with an NMToast when the current game's
// override shadows the pick); the game editor (ProfileSettingsViewController)
// owns per-game selection with the FULL option list (follow-global key
// removal + classic + MG family three, each marked with a checkmark) and
// writes profile-only; the RightPanel launch-time global rewrite is removed
// (launch reads profile-first via resolveKeyForCurrentProfile, the rewrite
// only polluted the global with the last launched game); the version
// manager's dead-code short-name array now maps by key value instead of
// index (the dylib filter made the old 7-name hardcode misalign with the
// 4-entry key list -- a "tap ANGLE, write Zink" landmine). (b) Mithril
// OpenGL 4.0 crash "There is no OpenGL context current in the current
// thread": gl_init_context selected context attribs by the mobileGL flag,
// so Mithril (desktopGL=YES, mobileGL=NO) got the ES attribs
// (EGL_CONTEXT_CLIENT_VERSION=3) AFTER eglBindAPI(EGL_OPENGL_API) -- the
// context MakeCurrent reported TRUE but the renderer's GL TLS never bound,
// and GlDevice.createCapabilities died. Attribs now select by desktopGL;
// a Task140 eglGetCurrentContext readback log after MakeCurrent (first 3)
// closes the forensic loop. (c) FSR "unavailable" on both MobileGL
// backends: mgl_fsr resolved its GL entry points via eglGetProcAddress
// (which returns NULL for core gl on MobileGL) with a dlsym(RTLD_DEFAULT)
// fallback -- the flat-namespace search hits the app's auto-linked ANGLE
// (libGLESv2.framework, in the global symbol table since process start,
// before libMobileGL's RTLD_GLOBAL dlopen), so all 41 "resolved" symbols
// were ANGLE's while the current context was MobileGL's; glCreateShader
// returned 0 through the only log-less failure path and the heal fired.
// ame119_resolve now dlsyms from the libMobileGL dylib handle directly
// (its export trie carries all 2851 gl/45 egl symbols -- verified), with
// source-bucket counters (handle/proc/default) in the resolve log and
// forensic logs on the two formerly-silent paths (glCreateShader==0 with
// glGetError, GLSL version query returning 0). With FSR actually engaging,
// the GLES session's mid-boot window flip-flop (Task83 linkage halves, heal
// restores full) also disappears -- a suspected contributor to the
// blocks-not-rendering report; if blocks still fail on DirectGLES after
// this build, the remaining cause is inside MobileGL's GL4.6-on-ES
// translation (upstream issue, report with the new log anchors). (d)
// TouchController virtual buttons missing ("static-lib touch works but no
// virtual buttons"): Task134 wrote an empty "Amethyst Clean" preset into
// the mod's config whenever the hide-controls switch was on, Task139 also
// hid the launcher's own ctrlView -- zero buttons on screen, while the
// user wanted the MOD's buttons (the upstream built-in preset ships a full
// set: joystick/dpad/jump/chat/pause). The mod-side write is retired
// entirely (the launcher never touches the mod's config now); the switch
// hides only the launcher's own classic controls; and
// ame140_remediateTouchControllerConfig one-time-removes the polluted
// empty-layout pointer (or restores the Task134 backup) so existing game
// dirs fall back to the mod's built-in full-button preset. l10n: 2 new
// keys (renderer_follow_global, renderer_shadowed_by_profile) + hide_controls
// + renderer_backend detail reworded x4 languages.

// REVISION 17 addendum (Task 142, no bump): renderer selection collapsed to a
// single "mg" entry + follow-global switch (the user's long-standing design,
// restated this round: "renderer selection should have only one mg, no
// backend written -- the backend follows the mg settings, Vulkan by
// default"). The renderer layer (video.renderer global + per-profile
// renderer key) now stores only logical keys (auto / mg / classic dylibs);
// the MobileGL family keys (libMobileGL / libMobileGL-gles / libmithril)
// moved to a dedicated backend key mobileglues.renderer_backend (default
// libMobileGL.dylib = Vulkan direct), picked in Settings > MobileGlues.
// ame_effective_renderer gains the mg branch: backend resolution via
// ame142_effective_backend_key (new key -> legacy global family key ->
// legacy mobilegl_backend tier -> Vulkan default) with a dylib guard that
// falls back to the default backend before auto; ame142_migrateRendererStorage
// one-time re-layers legacy direct-written family keys (global AND every
// profile) into the new scheme and retires the legacy tier key at the same
// time (explicit pick = the legacy end Task132 promised), keeping
// JavaLauncher's MOBILEGL_BACKEND_TYPE env consistent. The game editor
// (ProfileSettingsViewController) gets an EXTERNAL follow-global toggle row
// above the renderer row: ON removes the profile key and grays the renderer
// row out (value shows the global default's name); OFF enables the slim
// picker (classic list + the single mg entry, family keys checkmarked onto
// mg). The Settings backend row reads/writes its own key only (Task132-140
// wrote the renderer key -- the two layers masquerading as each other was
// the "picked a backend, the renderer row followed" confusion). Audit fix
// included: the Settings renderer row getPreference now returns the STORAGE
// key (Task140 returned the localized display name, which can never match
// pickKeys -- the picker checkmark was silently lost for auto/gl4es/zink;
// typePickField's ame132 branch maps the label). Device anchors:
// "[Amethyst] Task142: global renderer <family> migrated to 'mg'",
// "[PLPrefTable] Task142: renderer_backend written to OWN KEY", game editor
// toggle row + grayed renderer row, picker with a single "mg" option.
// l10n: -1 retired key (renderer_follow_global picker format) +3 new
// (renderer_follow_global_toggle / renderer.debug.mgfamily /
// mg_backend_missing_dylib) x4 languages.
// REVISION 17 addendum (Task 150, no bump): renderer GLOBAL control retired
// (user decree, [revertable] -- each game MUST own its renderer choice).
// The Settings-page global renderer row (video.renderer) is gone together
// with the game editor's follow-global toggle (Task142's external switch):
// PLProfiles resolveKey drops the video.renderer fallback (guarded against
// getPrefObject(nil)), so ame_effective_renderer now resolves
// [profile key -> auto] -- instances without an explicit choice run auto
// (user-confirmed default; 1.17+ resolves to MobileGL Vulkan direct via the
// Task144 upgrade). loadSettings defaults missing keys to "auto" and
// saveSettings writes explicit values (nil can no longer remove the key).
// l10n: -2 retired (renderer_follow_global_toggle /
// renderer_shadowed_by_profile) +6 new (component.sodium.*) x4 languages.
// Component install gains a Sodium entry (flame icon, Fabric-only): one
// tap downloads Sodium + Podium from Modrinth (exact-title match vs
// Sodium Extra / Podium Port forks; gameVersion+fabric loader matched
// like Fabric API) into the instance mods/ dir; Podium disables Sodium's
// PojavLauncher check, doubling the Task145 POJAV_RENDERER unwind.
// REVISION 17 addendum (Task 154, no bump): MobileGL FSR chain RETIRED to
// the da5918a semantics + Mithril double-classloader pin removed + Forge
// isolation v2. (1) The whole launcher-side MobileGL FSR linkage is retired
// (ame83_fsr_capable_renderer returns NO for both mg backends -- mgFsrScale
// pinned at 1.0: no window shrink, no touch division, no deferred arming;
// ame_mgl_fsr_before_swap hard-returns false behind a Task154 gate, full
// chain archived under #if 0): the 7c32bc3 Vulkan session proved
// libMobileGL's EGL is a fake-EGL (surface/ctx handles are 0x1, no current
// tracking) so eglGetCurrentDisplay/CurrentSurface return nothing and the
// Task153 deferred shrink never fires -- MC's window belief stays full
// while sendTouchPoint keeps dividing by mgFsrScale (touch quarter-screen
// misalignment, FSR no-op); the d36a24f sessions proved the chain's
// belief-geometry draws destroy frames when it DOES run (Vulkan corruption,
// ES "blocks not rendering"). User's own baseline: da5918a/5.1.0 (sessions
// 9f32cb4 + 1d4ff3a) shipped MobileGL with zero launcher-side FSR and was
// fully working; libMobileGL.dylib is byte-identical since da5918a, so the
// entire regression was launcher plumbing. FSR remains on MobileGlues/zink.
// (2) Task152b removed from Tools.launchMinecraft: preloading GL/Library
// through the SYSTEM classloader poisoned the JVM's
// one-native-library-per-classloader invariant for MC's Knot-loaded
// Library.<clinit> ("already loaded in another class loader", masked by
// LWJGL as "Failed to locate library: liblwjgl.dylib" -- the 3b35b26
// Mithril crash). Its premise (shipped GL.class ignoring
// org.lwjgl.opengl.libname) is disproven by jar inspection -- the MACOSX
// branch reads it since c71dcfa. The real Run #356 culprit, the
// GL$1 Delegate's eglGetProcAddress indirection (Mithril's returns broken
// pointers for core gl*), is fixed by scripts/patch_lwjgl_delegate_dlsym.py:
// a same-length constant-pool byte swap in lwjgl-341's lwjgl-opengl.jar
// ("eglGetProcAddress" -> "xglGetProcAddress") that dead-ends the
// indirection so every GL symbol resolves via dlsym on the provider
// handle -- which is how MobileGL (eglGetProcAddress returns 0 for gl
// names, Task140) and gl4es/tinygl4angle (no eglGetProcAddress export)
// already work today; OSMesaGetProcAddress stays for zink. Mithril's
// _glGetString/_glGetIntegerv/_glGetError dlsym exports are verified in
// its LC_DYLD_EXPORTS_TRIE (2082 exports). POJAV_RENDERER export retired
// for Mithril too (the 3b35b26 Mithril pack ships sodium 0.9.2, whose
// PostLaunchChecks throws on that env var -- Task145's own finding).
// (3) Forge split-package isolation v2: Task153's -Xbootclasspath/a move
// broke MinecraftAccount.<clinit>'s System.loadLibrary("AmethystAccountJNI")
// (boot loader searches only sun.boot.library.path -- "no AmethystAccountJNI
// in system library path", the 3b35b26 Forge crash). v2 uses
// BootstrapLauncher 1.1.2's own -DignoreList (source-verified filename-
// prefix matching): launcher.jar stays on -cp with the system classloader
// (loadLibrary intact) and is excluded from the MC-BOOTSTRAP module layer
// (no "launcher" automatic module -- the split package is rooted at the
// mechanism designed for exactly this). Device anchors:
// "[MGLFSR] Task154 MobileGL pre-swap FSR chain RETIRED", Vulkan/ES touch
// realignment + blocks rendering; Mithril past NativeLibrariesBootstrap
// with "[JavaLauncher] Task154 Forge ignoreList shield: '...launcher.jar'"
// on Forge sessions.

// REVISION 17 addendum (Task 156, no bump): four-render family + IME + UI.
// (1) ES (DirectGLES) blocks-invisible: pinned as an upstream MobileGL
//     26.08-dev Espryt translation-layer fault (every launcher-side suspect
//     was cleared across Tasks 140/153/154 -- d089745 already showed the
//     symptom pre-regression; Task113's "GLES variant misbehaves upstream"
//     warning was right). Binary strings expose the runtime tier switch:
//     MOBILEGL_ESPRYT_MULTIDRAW_MODE now forced to 'drawelements' (per-draw
//     glDrawElements loop) for the ES backend at both JavaLauncher and
//     egl_bridge selection sites -- chunk batches avoid the silently
//     dropping native/ext multi-draw tier. Vulkan (Magma) keeps its own
//     MOBILEGL_MAGMA_MULTIDRAW_MODE and is untouched. Device anchor:
//     "[JavaLauncher] Task156: Espryt multidraw tier forced to 'drawelements'".
// (2) Mithril (4.0) / by zero: decompiled MC 26.2 GlHeuristics -- DeviceLimits
//     reads GL33C.glGetInteger(35380) (GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT);
//     Mithril answers 0 -> DynamicUniformStorage's Mth.roundToward divides
//     by zero. New Natives/mithril_gl_shim.c builds libmithril_glshim.dylib
//     (Makefile dep_mithril_glshim, openal_shim re-export pattern): re-exports
//     every libmithril symbol, local glGetIntegerv/glGetInteger64v floor
//     zero limit enums (3379/34852/35361/35380 + 64-bit variants), and the
//     eglGetProcAddress funnel keeps dlsym-direct semantics under both GL$1
//     Delegate states. JavaLauncher points Mithril's
//     -Dorg.lwjgl.opengl.libname at the shim (existence-guarded). Anchor:
//     "[JavaLauncher] Task156: Mithril libname -> GL shim ...".
// (3) Forge android.util.ArrayMap: GLFW.class (the lwjgl overlay) declares
//     ArrayMap fields; the MC-BOOTSTRAP ModuleClassLoader parents to the boot
//     layer, so the -cp stub in launcher.jar is invisible to it (0d45e3f
//     latestlog.forge: GLFWErrorCallback$1 -> apiClassTokens ->
//     NoClassDefFoundError). The five android/util stubs are now ALSO
//     compiled into the lwjgl overlay (JavaApp/src/lwjgl/android/util/) so
//     both lwjgl-333 and lwjgl-341 merged jars carry them in the module
//     layer. Anchor: Forge reaches past DisplayWindow.initWindow.
// (4) IME (iPadOS 27): TrackedTextField gains the public UIKeyInput
//     insertText: catch-all (80 ms same-text dedup vs the private
//     insertFilteredText:/replaceRange paths) and nil-guarded/clamped
//     setAttributedMarkedText (NSNotFound backspace floods). The
//     TouchController text field is now the Ame156TCIMEAwareTextField
//     subclass: marked-text updates fire didChange and sendTextInputStatus
//     reports real markedTextRange composition bounds instead of 0/0.
// (5) UI: blur/opacity sliders get their (already localized) row titles
//     displayed + a semantics footer (background.effect.footer, l10n
//     1945->1946); the FSR row detail now states honestly that the mg
//     family (Vulkan/ES/4.0) has no launcher-side FSR and points to the
//     video Resolution scaler; the right panel's 7 info cards are tappable
//     and deep-link into settings (LauncherPreferencesViewController
//     ameDeepLinkKey scroll+flash; game version card -> VersionManager).

// REVISION 17 addendum (Task 158, no bump): mg backend remap back to
//     MobileGlues + Forge module-layer text2speech stubs + launch-time
//     library gate. User's ground truth (their own uploaded 5.1.0 logs,
//     9e6fc27 build): latestlog.4.0 (customGLVersion=40) and latestlog.es
//     (enableANGLE=3 + customGLVersion=32) both ran MC 26.2 fully playable
//     WITH fsr1Setting=4 (swapOK=1920 / 1034, exit(0)) -- those sessions
//     were libmobileglues.dylib, NOT the MobileGL/Mithril binaries the
//     Task131 rework silently substituted under the same "mg" label.
//     (1) ame_effective_renderer's mg branch now resolves the GLES and
//     OpenGL 4.0 backend keys to libmobileglues.dylib (MobileGlues; dylib
//     existence-guarded, falls back to the Task142 chain). ame83 FSR
//     capability therefore returns YES for them: the fsr1_setting preset
//     linkage (MC window = surface/scale + renderer-side FSR1 upscale +
//     matching touch math) is restored bit-for-bit to the 5.1.0 behavior.
//     init_loadMobileGluesConfig forces the 5.1.0 config per backend via
//     ame158_mg_mobileglues_mode(): GLES -> enableANGLE=3 (ForceEnable) +
//     customGLVersion=32; 4.0 -> enableANGLE=0 + customGLVersion=40; mode 0
//     (standalone MobileGlues / mg Vulkan-direct) keeps passing the user's
//     own MobileGlues section preferences through. Vulkan direct stays
//     libMobileGL.dylib (da5918a semantics; Task154's mgl_fsr retirement
//     untouched -- its EGL is fake, FSR linkage there equals input skew).
//     (2) Forge 1.20.1 Narrator CNFE (10cee5d latestlog.forge, crash at
//     GameNarrator.<init>): BootstrapLauncher 1.1.2 + securejarhandler
//     2.1.10 sources verified line-by-line (scripts/task158_bl/) -- the
//     MC-BOOTSTRAP/GAME ModuleClassLoaders parent to the boot/platform
//     layers, the system classloader is invisible to them, and
//     launcher.jar is ignoreListed (Task154), so nothing provides
//     com.mojang.text2speech inside the module layer. Fix: JavaApp/Makefile
//     now also builds mojang-stubs.jar (only the com/mojang/text2speech
//     stub classes, same bytes as launcher.jar's), shipped into app/libs
//     -> always on -cp -> always in java.class.path -> auto-modularized
//     into MC-BOOTSTRAP (filename matches no ignoreList prefix). The real
//     text2speech library stays _skipped in Java preProcessLibraries
//     (it would split-package with the stub module). Device anchor: Forge
//     gets past GameNarrator, no NoClassDefFoundError.
//     (3) Launch-time library gate (ame158_repairMissingLibraries,
//     non-blocking): before the JVM starts, every non-skipped library in
//     the merged version JSON is checked on disk; missing jars download
//     synchronously (official URL -> BMCLAPI mirror) so a silently-missing
//     library stops turning into an in-game NoClassDefFoundError crash
//     (BootstrapLauncher silently skips non-existent paths). Failures are
//     logged by name and never block (some missing libs are historically
//     tolerated). Anchors: "[JavaLauncher] Task158: library gate summary"
//     / "downloading missing library jar".
// REVISION 17 addendum (Task 159, no bump): resolution scale per-instance.
// The global Settings slider (video.resolution, 25-150%) is retired from the
// Settings page (same migration philosophy as Task 150's renderer retirement):
// each instance now owns its scale via the profile key "resolution", edited in
// the game editor right under the renderer row as an inline 25-100 number field
// with a separate "%" label (not inside the field). Resolution chain:
// [profile resolution -> legacy global video.resolution fallback -> 100], the
// PLProfiles prefDefaults mapping restored exactly like the reverted renderer
// fallback -- legacy global values keep applying to instances without an
// explicit choice until the user saves one. Launch-time single point:
// SurfaceViewController reads resolveKeyForCurrentProfile (same philosophy as
// ame_effective_renderer); the in-game resolution menu and the Java GUI
// ("Execute .jar", no instance context) keep reading/writing the global key.
// The memory-allocation card was replaced by a game-directory-style input
// dialog the same round (512..max-allocatable clamp); the auto-allocate switch
// retired with the card (stock memoryAuto profiles keep the stock auto-ratio
// semantics until one manual confirm). Manage Java gains the "26.0 and newer"
// preselect slot (tag 1_26_newer -> Java 25) with the launch/installer chains
// adapted to the three-tier defaultJRETag split. l10n: +5 new
// (manage_runtime.default.126 / footer.java25 / profile.title.resolution_scale
// / memory.adjust_title / memory.adjust_message) -1 retired (memory.current)
// x4 languages, baseline 1948->1952.
// REVISION 17 addendum (Task 160, no bump): Neumorphism UI regression + first-
// launch defaults. (1) The per-instance resolution-scale accessory is restyled
// to match the memory row (secondaryLabel gray digits at the system detail
// size, a separate % label, and a trailing chevron since the accessoryView
// suppresses the cell's disclosure arrow) and the clamp widens 25-100 ->
// 25-150 (the legacy global-slider range). (2) First-launch defaults only
// (stock users keep saved values): ui_theme dark->light, blur-mode uiOpacity
// 0.7->0.1 (panels nearly transparent against the wallpaper, readability
// carried by the 75% blur, up from 70%). (3) Modal sheets get their backdrop
// back: makeViewControllerTransparent now lays a page-level SystemThinMaterial
// glass layer under modal VCs (presenting chain check skips the sidebar /
// right panel / root content area, which keep showing wallpaper); the
// VersionManager section-header SystemMaterial block is deleted outright (the
// "Game directories / Installed versions" titles float on the wallpaper).
// (4) Neumorphism rebuilt natively per the user's CSS spec: dynamic surface
// #e0e0e0/#2c2c2c, dual outer shadows (dark bottom-right, highlight top-left)
// scaled by element size (340pt = 100% spec: radius 50 / offset 20 / blur 60,
// floors 8/4/12), primary text #333333/#f5f5f5, secondary #888888/#a0a0a0.
// The ame_apply{Card,Raised,Panel}Surface entry points now route through the
// engine; cell pipelines use a flat variant (shadows would clip/stack in
// lists). Settings-page text shadows (the "double-drawn text" ghosting) and
// the multi-line title/detail overlap are fixed back to native single-line
// label/secondaryLabel rendering. l10n baseline unchanged (1952).
// REVISION 17 addendum (Task 161, no bump): six-fix round on the 9c66184
// device logs ("3 backends all work now, but no FSR upscaling/sharpening
// anywhere, even zink"; wallpaper-settings page covered after the first-
// launch restart; Bing wallpaper still requiring a restart to silently
// load; appearance default; sidebar info-card crashes; keyboard auto-pop
// on MC <=26.2). (1) FSR root fix: renderer=auto now consumes the mg
// backend key (ame_effective_renderer's auto branch consults
// ame142_effective_backend_key -- GLES / OpenGL 4.0 remap to
// libmobileglues.dylib per Task158, Vulkan/default keeps returning "auto"
// so the legacy per-version ANGLE fallback is untouched); the modpack-
// imported profiles carry no renderer key and were permanently resolving
// to libMobileGL.dylib (Task154-retired FSR chain) while the user's
// backend pick in Settings > MobileGlues was silently ignored --
// ame158_mg_mobileglues_mode follows the same source so auto+GLES gets
// the 5.1.0 forced config (enableANGLE=3 + customGLVersion=32; without
// it the ES blocks-invisible regression returns). zink keeps its
// sentinel-verified EASU path untouched. (2) Wallpaper-settings cover:
// the Task160 modal glass backdrop must never be insertSubview'd into a
// UITableView (view==tableView form, i.e. BackgroundSettingsViewController)
// -- foreign subviews inside a table are unsupported and on iPadOS 27
// manifested as the whole page covered with dead sliders; table
// controllers now hang the glass on tableView.backgroundView, with the
// ame160 call moved to the tail of makeViewControllerTransparent (after
// the table branch nils backgroundView) and the settings pages' own
// viewWillAppear/reapply stops wiping it; the background container's
// decorative blur+dim layers get explicit userInteractionEnabled=NO.
// (3) Bing live-apply root cause: removeGlobalBackground nil-ed
// currentWindow/currentSplitVC AFTER applyBackgroundToWindow had just
// registered them, so every later setBingBackgroundImageAtPath took the
// both-nil branch (state saved, live UI never updated) = "needs a
// restart"; the host references are now left intact (both weak, mutual
// exclusivity owned by the apply methods). (4) Appearance default now
// "follow system" (ui_theme light->auto) with a one-time migration that
// only rewrites devices still sitting on the historical dark/light
// DEFAULTS and never those explicitly chosen (general.ui_theme_explicit
// marker set by the settings picker). (5) Sidebar info-card crash: the
// Task156 deep link indexed prefContents and called selectRowAtIndexPath
// while the target section was collapsed (PLPrefTable sections default to
// 1 header row) -- out-of-bounds selection on check_update / jit_enabler
// / memory_limit_help; the link now expands the section first and guards
// the row against the visible row count. (6) GLFW-path chat keyboard
// (MC <=26.2 has no text-input protocol unlike 26.3's SDL screen
// keyboard): nativeSendKey records the last pressed key; updateGrabState
// auto-shows inputTextField when an ungrab follows a T/slash within 1.5s
// (auto-shown flag auto-dismisses on re-grab; manual keyboard unaffected;
// SDL path untouched). JavaLauncher's stale "auto will be resolved to
// ANGLE" warning reworded to the Task144/161 semantics.

// REVISION 17 addendum (Task 162, no bump): eight-fix round on the bf91f41
// build (cbef9d5 logs, iPad Air M4 / iPadOS 27). (1) Profile identity
// consistency -- THE "switch a renderer and it silently reverts to auto"
// root cause: ProfileSettingsViewController saved under the profile's
// display NAME while the launch chain resolves by the dict KEY
// (selectedProfileName), and the modpack import collision suffix
// ("Name (2)" key vs "Name" field) plus the home version picker writing
// the name field into selectedProfileName made key!=name a reachable
// steady state; the editor now records profileDictKey at load and
// reads+writes the same key (rename re-keys old->new, existing-entry
// base taken from the target key so partial dicts never clobber real
// entries), and the picker selects by sorted key snapshot (allValues
// row-drift retired). Renderer/memory/resolution/java writes all land
// on the entry the launch reads. (2) Forge save-load crash: the lwjgl
// overlay's glfwSetInputMode called net.kdt.pojavlaunch.uikit.UIKit
// (launcher.jar-only class) on cursor grab -- Forge's MC-BOOTSTRAP
// module layer (launcher.jar ignoreList-ed) can't see it ->
// NoClassDefFoundError in ReceivingLevelScreen.onClose; the Java-side
// call is removed and the GLFW-path nativeSetGrabbing now runs the
// Task63 refreshGuiScaleNatively (same as the SDL path), keeping hotbar
// hit-testing fed with zero class-visibility dependencies. (3) Bing
// "loads but needs a restart": the already-today silent skip now checks
// isBackgroundLiveAttached (container in a live window + host refs
// alive) and re-plays setBingBackgroundImageAtPath when the registered
// state has no live UI, self-healing any past detached apply on every
// metadata sync / foreground / manual refresh. (4) Wallpaper defaults
// per user decree: frosted glass, opacity 60%, blur 100% (first-run /
// never-saved devices only). (5) Home avatar missing after tab switch:
// updateSkinDisplay now goes AvatarManager local -> session NSCache ->
// network (cache fill), so viewWillAppear renders instantly instead of
// flashing the placeholder through a full re-download. (6) Account list
// refreshes on viewWillAppear + AccountChanged/UpdateAccountInfo
// (adding an account no longer needs a manual refresh). (7) CurseForge
// source usable without an API key: with no key configured the API base
// URL is forced to the MCIM mirror (server-side public key, verified
// keyless GET /mods/search -> 200) and the five UI gates switch from
// isAPIKeyConfigured to isSourceAvailable -- official-direct remains
// available for keyed devices under the mirror policy. (8)
// announcements.json: server recommendation mysv.dpdns.org entry added
// (dated top-of-list) and the v6.0.0 defaults wording synced to the new
// 60%/100% + follow-system values. verify_task162 68 checks; cascades
// re-anchored: task150/157/159 announcement index [0] -> by-id (new
// entries legally take the head slot), task160 B2/B3/B5/F1/F4 re-anchored
// to the Task162 defaults decree.

// REVISION 17 addendum (Task 163, no bump): neumorphism scope correction on
// device feedback -- Task160 applied the raised surface to the wrong
// objects and left the intended ones flat. (1) Sidebar/right-panel shadow
// retirement: ame_applyPanelSurfaceWithRadius now routes to the flat
// variant (spec surface + clamped radius, no shadow host view) -- the
// full-height chrome containers sat near the 340pt metric base so their
// proportional offset/blur bled onto the central cards ("you changed what
// should not be changed"); maskedCorners (outer two corners only) and the
// creation-time masksToBounds=YES are untouched. (2) Home tiles and the
// download version cards gain the raised form:
// applyEffectToCollectionViewCell's no-wallpaper branch now mounts
// AmeNeumorphShadowView on the card target with the clip chain released
// (cell.clipsToBounds=NO, contentView masks=NO) so the dual shadow reads
// across tile gaps; wallpaper branches strip stale shadow hosts first via
// the new ame_removeNeumorphShadow (UIKit+NativeSurface). (3)
// VersionCardCell moves to the new applyNeumorphCardEffectToView:
// pipeline (wallpaper -> legacy applyEffectToView detour with shadow
// cleanup; no wallpaper -> raised surface). (4) ProfileSettings page-wide
// chevron unification: every UITableViewCellAccessoryDisclosureIndicator
// row (renderer / graphics API / Java / memory / game dir / managers)
// swaps to the same self-drawn chevron.right accessory as the Task160
// resolution row (ame162_disclosureChevron, 8x13 tertiaryLabel glyph in a
// 14x30 container) -- the mixed system/SF-symbol glyph weights read as a
// mismatch side by side. applyCardEffectToCell (table rows) and the
// Card/Raised surface methods keep their Task160 forms.

// REVISION 17 addendum (Task 164, no bump): ES / OpenGL 4.0 black-screen
// fix + wallpaper first-launch defaults repair. Device evidence
// (56c8173 logs, build 678a76f): both MG-remap sessions present the
// Task130 RCAS chain engaged (render 1180x820 -> EASU -> target
// 2360x1640 -> RCAS -> surface) with fps=58 / swap 100% OK / zero GL
// errors -- yet the screen stays black; the 5.1.0 healthy baseline
// (a0ac656 latestlog.es / latestlog.4.0) is byte-identical pipeline
// EXCEPT it is EASU-only (no RCAS pass existed) and shows a picture.
// The modpacks match (continuity/iris present in BOTH), so the delta is
// the RCAS pass itself. Four deviations from the proven zink RCAS form
// (osm_bridge, device-verified) are corrected in FSR1.cpp +
// FSRRCASSource.h: (1) FsrRcasLoadF now clamps its texelFetch taps to
// the input bounds via textureSize -- the fullscreen-quad entry
// generates out-of-range taps on every edge pixel (p+(0,-1) etc.);
// Mesa tolerates OOB texelFetch, ANGLE Metal maps it to MTLTexture
// read: which is UB and can void the whole frame (fps/swap green,
// screen black). Applies to all three TUs sharing the header (zink
// gains correct edge behavior, no visual regression). (2) Both
// directToSurface branches now disable GL_STENCIL_TEST (zink's
// five-state list; EGL configs carry stencil bits and mod shaders can
// leave a rejecting stencil test armed -- the quad gets discarded
// pixel-by-pixel while swap succeeds). (3) The RCAS draw now
// explicitly selects texture unit 0 and re-pins the sampler uniform
// every frame instead of relying on the init-time pin (zink form;
// glUniform1i(-1,..) stays a legal no-op). (4) A one-shot GPU probe
// (zink Task99 forensics form) reads a single fb0 edge pixel right
// after the first RCAS frame -- the install-verification anchor
// "[MG] Task164 RCAS GPU probe: ... nonzero = draw landed on GPU;
// all-zero = RCAS quad never landed" bisects state-eaten draws from
// presentation-layer failures on the next device round. Wallpaper
// defaults (BackgroundManager.loadUISettings): the Task162 range
// checks let never-saved keys fall through as valid values --
// integerForKey never-saved returns 0 == BackgroundUIEffectTranslucent
// (semi-transparent, NOT the decreed frosted glass) and floatForKey
// never-saved returns 0.0 which "< 0.0" cannot catch (0% blur). All
// three keys now branch on objectForKey == nil first (never saved ->
// frosted glass / 60% opacity / 100% blur; explicitly saved values,
// including a deliberate semi-transparent pick or 0% blur, are
// respected as-is). Vulkan-direct FSR remains upstream-impossible
// (libMobileGL ships zero FSR/EASU/RCAS symbols and no config
// surface; Task154 pseudo-EGL evidence stands) -- the FAQ fsr entry
// and the announcements support matrix carry the guidance: use the
// GLES / OpenGL 4.0 backend for the full MobileGlues FSR1
// (EASU upscale + RCAS sharpening).

// REVISION 17 addendum (Task 165, no bump): the REAL ES/4.0 black-screen
// root cause, found on the cc9bfe4 log pair (bc6c0b5 build) after Task164's
// four RCAS alignments changed nothing. Forensics: every black session (both
// backends, both log rounds) shows glXGetProcAddress NEVER called (the
// healthy 5.1.0 pair shows the own-image resolution + SYMBOL THEFT canary
// lines -- that function only fires from the frontend eglGetProcAddress,
// i.e. the app resolved through it), exactly 10 LWJGL "No context is
// current or a function that is not available" prints (healthy: zero), and
// the Task164 probe reading 000000ff (the Metal initial clear) with a
// pending 0x0500. Chain: Task154's patch_lwjgl_delegate_dlsym.py renamed the
// GL$1 Delegate's provider-library lookup "eglGetProcAddress" ->
// "xglGetProcAddress" (correctly killing Mithril's broken indirect layer),
// which silently forced MobileGlues sessions onto the per-name dlsym
// fallback; the flat namespace hands glDrawArrays / glTexImage2D /
// glFramebufferTexture2D (the canary trio) to the raw ANGLE image, so the
// application's draws bypassed gl/framebuffer.cpp's framebuffer-0 redirect
// and FSR1 upscaled a never-written render texture over the real frame.
// Invisible until Task161 re-armed the FSR linkage (the "3 backends fine"
// build ran libMobileGL for every backend setting). Fix: egl.cpp exports
// xglGetProcAddress -- the Delegate's dead-named lookup finds it in
// libmobileglues.dylib (pinned by -Dorg.lwjgl.opengl.libname) and gl*
// resolution owns the layer again; gated on AMETHYST_RENDERER containing
// "obileglues" (defense-in-depth -- other renderers keep Task154's dlsym
// semantics, OSMesa's OSMesaGetProcAddress untouched). FSR1.cpp gains (a) a
// one-shot render-texture probe (center pixel before the first EASU draw --
// nonzero = the app frame reached the render FBO, all-zero = the redirect
// was bypassed; splits the draw layer from the resolution layer on the next
// log) and (b) an RCAS runtime bail-out: first-frame fb0 corner AND center
// both black with healthy alpha-0xff reads latches EASU-only for the
// session and rescues the current frame with a direct EASU redraw -- the
// failure mode degrades from "black screen with healthy swap counter" to
// "unsharpened upscale" instead. Vulkan-direct FSR assessment (user ask):
// libMobileGL stays closed (zero FSR symbols, pseudo-EGL per Task154) and
// the mgl_fsr pre-swap war stays retired; the safe launcher-side option is
// a render-scale tier (window + drawableSize at render res, CA stretch)
// which trades EASU sharpness for determinism -- deferred pending the
// user's call, GLES/4.0 + full FSR1 at 60fps is the recommended path.

// Task 166 (REVISION 17 addendum, no bump): Vulkan-direct FSR ships + the
// real ES/4.0 black-screen config culprit. (1) Vulkan FSR: the Task154/165
// "upstream hard limit" verdict was re-litigated after finding the
// open-source upstream (MobileGL-Dev/MobileGL, LGPL) -- libMobileGL still
// has zero built-in FSR, but MoltenVK consumes its swapchain images through
// the id<CAMetalDrawable> ObjC protocol, so the launcher intercepts
// presentation instead: a private CAMetalLayer subclass (Layer B, render-res
// via explicit EGL_WIDTH/HEIGHT attribs) feeds MobileGL's pseudo-EGL ->
// vkCreateMetalSurfaceEXT -> MoltenVK swapchain at render resolution, while
// Layer B's overridden nextDrawable hands MoltenVK a wrapped drawable backed
// by an 8-slot MTLTexture ring; the wrapper's present runs AMD FSR1
// EASU (12-tap) + RCAS (5-tap, AMETHYST_FSR_RCAS_SHARPNESS, negative = off)
// ported verbatim to MSL (ffx_a.h 32-bit constants 0x7ef07ebb / 0x7ef19fff /
// 0x5f347d74, Task164-style OOB clamps inside the load helpers) into the
// view's real full-res layer. Zero changes to the MobileGL/MoltenVK
// binaries; the Task154 pre-swap GL war stays retired (pseudo-EGL root
// cause unchanged; double-upscale guarded); ame83_fsr_capable_renderer
// re-includes libMobileGL.dylib only (libMobileGL-gles stays excluded);
// ame48_swap_geometry_guard records Layer B so the surface-vs-layer
// comparison stays still; kill switch AME166_MGL_METAL_FSR=0; any init
// failure falls back to da5918a full-res direct semantics. Install anchors:
// "[MGLFSR] Task166 Metal FSR engaged", "first frame presented",
// "steady: 600 frames". (2) ES/4.0 black screen: after Task164 (RCAS edge
// clamps) and Task165 (xglGetProcAddress resolution routing) each failed to
// heal it, a three-session A/B on the same device/modpack/MobileGlues
// 2.0.17 isolated the sole config delta: enable_ext_direct_state_access
// (DSA). DSA=0 (9e6fc27 healthy pair) = "DSA support not detected" =
// playable with FSR; DSA=1 (cc9bfe4 pair + 3368468) = "ARB_direct_state_
// access detected, enabling DSA" = black screen with healthy swap counters.
// Task129d had forced DSA=1 citing zink perf (Mesa native DSA -- never
// applied to MobileGlues' DSAWrapper emulation under the FSR1 fb0
// redirect). Fix: default @NO in three places (PLPreferences,
// JavaLauncher config.json, ame130 migration branch retired) plus a one-shot
// reverse migration ame166_migrateMgDsaBlackScreen (persisted 1 -> 0,
// sentinel task166_dsa_blackscreen_migrated; Task130's 0->1 neutralized so
// fresh zeros are not flipped back); the settings toggle remains for manual
// override. verify_task129 D1/D3 and verify_task130 E9/E10 re-anchored.

// Task 167 (REVISION 17 addendum, no bump): the Task166 IPA's two fixes both
// failed on device (upload 1b76d19: Vulkan crashed, GLES/4.0 still black) --
// both root causes found and fixed the same session. (1) Vulkan crash:
// MoltenVK's surface extent source is NOT CAMetalLayer.drawableSize but the
// CAMetalLayer+MoltenVK category's naturalDrawableSizeMVK = bounds x
// contentsScale (MVKSurface::getNaturalExtent feeds surface capabilities'
// currentExtent). Task166's Layer B only set drawableSize, leaving bounds at
// CGRectZero -> currentExtent = {0,0} -> MobileGL's RecreateSwapchain
// zero-area guard installed NO swapchain -> m_images empty + first acquire
// deferred -> MC's first DSA glBlitNamedFramebuffer(fb0) hit
// SwapchainObject::GetImage(0) on an empty vector = nullptr load. The
// disassembly of the shipping dylib matches the device crash pc byte-for-
// byte (GetImage+0x28 is exactly the ldr x0,[x0] of m_images[index]; the
// assert is compiled out at INFO level, so the OOB/empty read is a raw
// SIGSEGV). Fix: Layer B writes bounds + contentsScale(1.0) alongside
// drawableSize at all three geometry sites (create / existing-layer sync /
// update_size hook); contentsScale=1.0 keeps natural == drawable ==
// swapchain extent so MVKSwapchain::hasOptimalSurface stays optimal. (2)
// The DSA reverse migration never executed: it was wired into
// application:configurationForConnectingSceneSession:, which UIKit only
// calls for NEW scene sessions -- devices whose session predates the code
// never run it again (60+ uploaded device logs contain zero log lines from
// anything inside that callback, including Task130-era unconditional
// lines). Meanwhile the Task129d-era @YES default was persisted into the
// plist by the defaults merge at every launch of those builds, so the
// stored 1 suppressed Task166's fresh @NO default and both 1b76d19 sessions
// still read enable_ext_direct_state_access = 1. Fix: the always-run call
// site moved to main.m right after toggleIsolatedPref (effective store
// active, before any consumer), the AppDelegate site kept as a fresh-install
// early trigger (sentinel makes the two idempotent), and
// ame166_migrateMgDsaBlackScreen gained NSNumber/NSString dual-type
// tolerance plus an unconditional run anchor log. Install anchors:
// Vulkan = "[MGLFSR] Task166 Metal FSR engaged" + "first frame presented"
// (and no GetImage crash); GLES/4.0 = "[Preferences] Task167 MG DSA
// black-screen migration ran (stored=1, flipped=1)" + "DSA support not
// detected" + a visible frame. verify_task166 C2 + verify_task130 E10
// re-anchored to the Task167 forms.

// Task 169 (REVISION 17 addendum, no bump; app version 6.0.0): device feedback
// quadruple fix + release prep (upload 485b18c, af9b807 -- the build where
// Task167 finally shipped: user confirmed Vulkan + ES/4.0 fixed, "OK了").
// (1) CurseForge source "completely unusable": the MCIM mirror's upstream key
// pool intermittently fails, returning HTTP 200 + valid JSON with NO "data"
// array ({"error":"Internal Server Error","code":500,"detail":"... 403 ..."}).
// The old parser treated that shape as "no results" and silently completed
// with @[] -- all four logged searches showed starting-request lines with
// zero completion logs, and the UI showed an empty list with no error.
// Sandbox reproduction confirmed the intermittency (3 failures in one window,
// then 6 straight successes). Fixes in CurseForgeAPI.m: gateway-error JSON
// detection (no "data"/"pagination" + error/code keys) with logging, ONE
// automatic retry after 1.5s (transient upstream failure), then a real NSError
// carrying the upstream detail (both async search and sync getEndpoint);
// CFACompiledAPIKey now rejects stringified NULL literals ("((void *)0)",
// "(nil)", "NULL", "0" -- the 11-char garbage the device logs showed being
// sent as x-api-key while suppressing the keyless forced-mirror fallback);
// gameVersion normalized (fabric build-hash suffix like "26.3-0a78cefc"
// stripped to "26.3") at both search builders.
// (2) Local modpack import required pre-copying into the app container: the
// document picker URL is a security-scoped resource; the old flow released
// the scope right after parsing, while the install phase (importModpack:)
// re-read the whole archive via info[@"filePath"] -- out-of-sandbox picks
// lost access by then (only "On My iPhone" copies happened to work).
// ModpackImportViewController now copies the picked file into app tmp WHILE
// the scope is alive (also materializing iCloud placeholders), and parse/
// preview/install all use the local copy; stale copies cleaned at next pick.
// (3) Home avatar sometimes required a tap: the fetch used dataWithContentsOfURL
// (default 60s hang, fully silent failure, no persistence). AvatarManager
// gains fetchAvatarFromURL:completion: (10s timeout, Caches disk cache keyed
// by djb2 of the URL, failure logging, main-thread single-shot completion);
// LauncherNewsViewController and the right panel use it; the news VC also
// directly updates visible ProfileTileCells (reloadSections can miss repaints
// in some layout timings).
// (4) "zink renderer launch stuck at the launcher screen": the log ends at
// the FIRST JIT-wait round (f95a219's successful sessions show the game
// launching 2 lines after the same dance) -- the stikjit:// enabler failed
// that time and all three invokeAfterJITEnabled implementations had
// unbounded while(!isJITEnabled) polls: the wait alert never dismissed.
// utils.m gains ame169_waitForJITCondition (120s bound, 10s heartbeat logs);
// all six wait loops (RightPanel/NavCtrl/DownloadVC x isJITEnabled/
// JIT26DebuggerKeepAttached) bounded, with a retry/cancel alert on timeout.
// (5) Announcements: AnnouncementItem gains a "pin" field (bool/string
// tolerant) sorted ahead of date-desc by AnnouncementService; the server
// recommendation (mysv.dpdns.org) is pinned first per user request; task169
// announcement added; v6-0-0-release rewritten to the FINAL truth (Vulkan-
// direct FSR ships via the Metal presentation layer; the old "Vulkan does
// not support FSR" matrix retired) and redated. Info.plist 5.1.0 -> 6.0.0
// (CFBundleShortVersionString + CFBundleVersion).
// Task 168 (2026-09-25): neumorphism wallpaper-mode visibility + FAQ JSON.
// (1) Root cause of "downloaded the latest commit but no neumorphism": the
// Task163 raised-card pipeline only engaged WITHOUT a custom wallpaper --
// with one set, cards fell back to the legacy frosted-glass branch and never
// showed the spec surface/shadows. Fix: applyNeumorphCardEffectToView: and
// applyEffectToCollectionViewCell: no longer early-return into the legacy
// pipeline. With a wallpaper the card FACE still follows the user's
// opacity/blur settings (dynamic neumorphism = face per wallpaper settings +
// dual-shadow overlay via the new ame_attachNeumorphShadowOnly, which keeps
// the face color untouched); the new "cardsNeumorphSolid" preference
// (BackgroundSettingsViewController switch, default OFF) forces the solid
// spec surface + dual shadows, giving up wallpaper transparency/blur.
// (2) The 34 help-FAQ entries moved out of hardcoded ObjC into a bundled
// JSON (help-faq.json, same pattern as announcements): repo root = editing
// source, Natives/resources/help-faq.json = bundled copy read at runtime,
// byte-identical, drift-guarded by verify_task168. LauncherHelpViewController
// now parses it (icon/title/description fields, empty-groups on parse
// failure). Stale FAQ conclusions updated in the same pass: FSR entry now
// states all three backends are supported (Vulkan via the Metal presentation
// layer, Task166/167), MobileGlues chunk-loading entry gains the
// Vulkan+FSR recommendation.

// Task 170 (2026-09-25): user followup on Task 168 -- the binary
// cardsNeumorphSolid toggle is retired in favor of a continuous
// "Neumorphism Opacity" slider (defaults key
// background_cards_neumorph_opacity, 0.0~1.0, default 1.0 = Task 168
// form untouched). The slider scales the WHOLE card as one unit
// (face + dual-shadow carrier + content) via the host view alpha,
// set in every terminal branch of applyNeumorphCardEffectToView /
// applyEffectToCollectionViewCell, so heavy edge halos reported on
// device can be dialed down directly. Home tile collection layout
// gaps unified to 20pt (item insets 10 + section insets 10), equal
// to the card-to-sidebar outer margin. l10n key renamed in place
// (background.cards.neumorph.opacity.title x6, count 1953). No
// engine (UIKit+NativeSurface) changes.

// Task 171 (2026-09-25): seven-symptom device-feedback round on the f26337d
// build (3 uploaded logs: latestlog.txt = ANGLE 26.3 FO pack, latestlog.old.txt
// = mg 26.3 multiplayer on mysv.dpdns.org, latestlog.old = mg 26.4-snapshot-1).
// (1) ANGLE renderer crash: libtinygl4angle.dylib was never in
// ame_glBridgeEnabled (sdl3_hook.m), so renderpearl's GlBackend pointer
// consistency check failed ("glGetError mismatch") -> Vulkan fallback ->
// Iris ExceptionInInitializerError (No GLCapabilities). The bridge now takes
// over SDL_GL for ANGLE too (AMETHYST_ANGLE_GL_BRIDGE=0 escape hatch).
// (2) Hotbar taps "a bit low": touchHotbar's hit rect ignored the FSR window
// ratio -- the visual bar spans physical 1640-88*1.7=1490..1640 but the gate
// was barY=1560 (device log: REJECT above bar y=1516/1556). Geometry is now
// ratio-aware (182x22 sprite x guiScale x physH/windowH; mcscale NOT used to
// avoid double resolutionScale division). (3) CurseForge "key not set at
// build time -> error": [headers] returning nil for keyless devices gated all
// three request paths on missingAPIKeyError BEFORE sending, while baseURL
// already forces the MCIM mirror -- keyless now sends Accept-only headers
// (mirror verified 200 keyless; official API is 403). (4) Home avatar missing
// on tab return: Task169's visible-cell direct sync only ran in the fetch
// completion; the session-cache-hit branch relied on reloadSections (dropped
// mid-transition). New ame171_syncVisibleProfileAvatar covers all branches +
// viewDidAppear. (5) Multiplayer intermittent crash: the referenced
// latestlog.old.txt session is CLEAN (60fps, exit(0)); the crashed session's
// log was lost to the one-generation rotation -- init_redirectStdio now
// preserves an exit-marker-less previous log as latestlog.crash.txt.
// (6) MC 26.4 falls back to Vulkan on zink and mg alike:
// PreferredGraphicsApi.DEFAULT.getBackendsToTry() flipped to {vulkan, gl} in
// 26.4 (26.3: {gl, vulkan}) + the OptionsForceDefaultGraphicsApiFix datafix
// resets the stored option -- Tools.java now appends --graphicsBackend opengl
// for MC >= 26.4 when the renderer is not native MoltenVK (both 26.3 and
// 26.4-snapshot-1 Main accept the argument; GL failure still falls through to
// Vulkan via the same order table). (7) Keyboard first-session race ("must
// press the IME button once after the keyboard appears"): device log shows
// becomeFirstResponder=1 on EVERY input-method press = the field loses first
// responder after each typed character (text=@" " assigned AFTER become +
// clearsOnBeginEditing fighting iPadOS 26+ UIAsyncTextInput session
// activation). Fix: sentinel text now written BEFORE becomeFirstResponder,
// clearsOnBeginEditing=NO, plus ame171_armKeyboardRecheck auto re-arm (0.4s
// health check, generation-guarded against user dismissal, max depth 2).

// REVISION 17 addendum (Amethyst Task 172, no bump): six-symptom round from
// the 9be2b53 device logs (760c07c upload: latestlog.txt = launch stuck at
// JIT wait, latestlog.old.txt = mg 26.3 multiplayer, latestlog.old = ANGLE
// 26.3 FO pack). (1) ANGLE glGetError mismatch PERSISTS with the bridge
// hooked -- CFR decompile of the bundled lwjgl-333 GL$1.class proves the
// macOS-platform provider chain NEVER consults eglGetProcAddress (LINUX:
// glXGetProcAddress/ARB, WINDOWS: wglGetProcAddress, fallback-for-all:
// OSMesaGetProcAddress; query: GPA(name) then library dlsym). The old mirror
// tried eglGetProcAddress first: harmless for MG/zink (both chains converge),
// fatal for libtinygl4angle whose dependency libEGL exports
// eglGetProcAddress while glGetError is a direct libGLESv2 export -- two
// different addresses, mismatch, Vulkan fallback, Iris No GLCapabilities.
// ame_SDL_GL_GetProcAddress now mirrors the true GL.1 macOS branch
// (OSMesaGetProcAddress only) -- pointer identity holds by construction for
// every renderer. (2) Launch stuck at JIT wait >120s then crash: the
// stikjit:// URL backgrounds the app; if StikJIT fails to switch back, iOS
// suspends the process and the 120s poll loop FREEZES (device log: zero
// heartbeats after "still waiting after 0s", zero timeout, log just ends).
// On manual return, CS_DEBUGGED can already be set while the JIT26 debugger
// died -- launching then hits brk #0x69 with no one servicing it = the
// reported crash. All three invokeAfterJITEnabled implementations now (a)
// hold a beginBackgroundTask assertion across the wait (heartbeats/timeout
// keep printing, StikJIT can attach while we are backgrounded), and (b)
// after the wait succeeds re-check debugger liveness on TXM devices and
// route through the extracted ame172_reattachJIT26ThenLaunch (foreground
// wait + stikjit:// + bounded debugger-live wait) instead of launching
// blind. (3) Keyboard "must press the IME button once": the field loses
// first responder because MC 26.3's SDL_StartTextInputWithProperties makes
// SDL's OWN UIKit textField first-responder -- its window is the hidden SDL
// UIWindow (Task32 embed), its text delivery is dead, so keystrokes vanish
// until the user re-arms the launcher field via the IME button. Start/Stop
// hooks now post AME172_SDLStartTextInput / AME172_SDLStopTextInput right
// AFTER the real calls; SurfaceViewController routes the keyboard to its own
// inputTextField (Task171 sentinel order + re-arm) and resigns it when MC
// closes the text context. (4) Home avatar still needs a tap after tab
// return: AvatarManager's fetch-failure and bad-URL paths called the
// completion OFF the main thread (contract violation) -- UICollectionView
// reloads from a session thread silently no-op until the next UI touch.
// Both paths now dispatch to main; updateSkinDisplay logs every branch
// (local / session-cache / fetch / missing-URL) and the visible-cell sync
// reports cell count + image size; viewDidAppear adds a 0.35s
// post-transition re-sync pass. (5) Per-profile TouchController (user
// request): ProfileSettingsViewController gains a TouchController row
// (advanced section; picker on/off; summary reuses existing
// preference.touchcontroller.mode.* l10n keys -- zero new keys, zero count
// cascade). UIKit_launchMinecraftSurfaceVC now calls
// ame172_applyProfileTouchController before the root-VC swap: profile key
// touchController=YES auto-configures control.mod_touch_enable=YES,
// control.mod_touch_mode=1 (UDP) and control.mod_touch_hide_controls=YES
// (Task140 semantics: launcher's own control layer hidden, the mod's virtual
// buttons stay); OFF leaves the global settings untouched. (6) CurseForge
// mirror 5xx: the device log shows a transient 502 on classId=4471 that
// succeeded on the user's manual retry 5s later -- the async search now
// retries 5xx (empty or non-JSON bodies) with a 2s backoff (max 2), and the
// sync getEndpoint wraps AFNetworking 5xx failures into the existing
// code-543 retry loop.
// REVISION 17 addendum (Amethyst Task 173, no bump): neumorphism rewritten to
// the "normal state" as the single card path. User's repro pinned the root
// cause: with a Bing wallpaper active, toggling any UI effect and then
// disabling the wallpaper made neumorphism snap back to normal -- proving the
// good form (spec surface #e0e0e0/#2c2c2c + dual shadows) always lived in the
// no-wallpaper branch, while the wallpaper-adaptive "dynamic face" (glass/
// translucent card + attachNeumorphShadowOnly + host alpha) read as heavy
// edge halos (dark 20/60px shadows over a translucent face on a wallpaper).
// Changes: (1) new cardsNeumorphEnabled preference (background_cards_neumorph_
// enabled, default YES) gates a rewritten three-stage card pipeline -- ON =
// wallpaper-agnostic normal state everywhere (applyNeumorphCardEffectToView,
// applyEffectToCollectionViewCell, applyCardEffectToCell; stray blur layers
// stripped, host chain unclipped for shadow overflow); OFF = legacy pipeline
// (glass/translucent with wallpaper per the other UI-effect options, native
// flat without). The dynamic-face wallpaper-adaptation branch is retired
// wholesale. (2) Settings: a "Neumorphic Interface" switch row now sits under
// Blur Intensity (always visible, even without a wallpaper): ON greys the
// legacy UI-effect rows (picker + opacity + blur sliders, alpha 0.35 +
// interaction off) and enables the card-opacity slider; OFF reverses.
// (3) Opacity respecified as CARD-BODY opacity (user: fonts excluded): new
// engine primitive ame_applyNeumorphCardOpacity fades the dynamic surface
// color (alpha applied inside the dynamic provider per-trait, so dark/light
// stays correct) and the shadow carrier's alpha, leaving text/icon subviews
// fully opaque -- the old whole-host view.alpha scaling is gone from all
// terminal branches. l10n: new key background.cards.neumorph.interface.title
// x6 (four-main count 1953 -> 1954, historical anchors re-locked).

// REVISION 17 addendum (Amethyst Task 173, no bump): ten-symptom round from
// the fd31b79 device logs (Task 172 build, three sessions: ANGLE FO pack on
// 26.3, Zombie Invade 100 Days on 1.20.1-forge, old Forge 1.8.9).
// (1) ANGLE renderer crash AFTER the GL backend was accepted: the session
// dies at Minecraft.loadCriticalShaders -> Failed

// REVISION 17 addendum (Amethyst Task 173, no bump): ten-symptom round from
// the fd31b79 device logs (Task 172 build, three sessions: ANGLE FO pack on
// 26.3, Zombie Invade 100 Days on 1.20.1-forge, old Forge 1.8.9).
// (1) ANGLE renderer crash AFTER the GL backend was accepted: the session
// dies at Minecraft.loadCriticalShaders -> "Failed to find or load pipeline
// minecraft:pipeline/gui" -- the LWJGL line "No context is current or a
// function that is not available..." pins NULL function pointers. CFR
// forensics of the real 26.3 client.jar renderpearl GL backend: GlDevice
// calls GL33C.glColorMaski/glEnablei/glDisablei, GlCommandEncoder uses
// glDrawElementsInstancedBaseVertex, GlQueryPool uses glQueryCounter, and
// Iris uses glTexImage1D -- none of which exist in the ES-only export set of
// the bundled libGLESv2 framework, so the GL$1 macOS chain (OSMesaGetProc
// =0 then plain dlsym, Task 172's verbatim mirror) resolves them to NULL.
// tinygl4angle.c now carries a desktop-GL completion layer: ~20 wrappers
// (per-slot blend, multi-draw family, queries, tex buffers, FBO layered
// attach, copy image, 1D textures, GLdouble adapters) resolved at first
// call via eglGetProcAddress with EXT/OES/KHR/NV/ARB suffix fallbacks and
// safe degradation (slot 0 falls through to the non-indexed variant,
// multi-draw unwinds to per-draw calls, glLogicOp no-ops). Two latent bugs
// fixed in the same file: glShaderSource early-returned WITHOUT uploading
// ES-versioned shader sources (compile-empty programs), and the GLSL
// version string "OpenGL GLSL 3.30 (ANGLE...)" broke Iris's semver regex
// (prefix now stripped in glGetString). One-shot forensics logs the
// resolved/missing table on first glGetString.
// (2) Old-Forge (1.8.9-forge-11.15.1.2318) launch crash: the generated
// version JSON lacks a "libraries" array, so Tools.getVersionInfo NPE'd at
// the customVer.libraries loop (line 752). Both sides now get empty-array
// guards + null library/name skips, and a missing parent-version JSON
// reports a locatable error instead of a raw NPE.
// (3) Zombie Invade 100 Days (244-mod 1.20.1 Forge pack) dies silently
// 53s into loading: the instance memory slider allowed 7165MB (the 0.8 x
// physical formula) which blows the iOS per-process Jetsam limit (heap +
// JVM native + renderer surfaces). ame173_safeHeapCeilingMB() derives an
// authoritative ceiling from os_proc_available_memory() minus a 1.2GB
// native reserve; ame141_currentLaunchAllocMem clamps every launch
// (profile or auto) through it with a bilingual toast, and the Profile
// memory slider is capped at ceiling+512MB so doomed values cannot be
// pre-selected.
// (4) CurseForge list ignored the sort menu: the UI passed Modrinth-style
// sort ("follows"/"downloads"/...) and loader ("fabric"/...) keys, but the
// CF search never mapped them -- sortField/sortOrder/modLoaderType are now
// appended on both the sync and async paths (2=Popularity, 6=TotalDownloads,
// 3=LastUpdated; loader enums 1/4/5/6), and ModrinthAPI gets the same
// treatment (its index was hardcoded relevance/follows -- the sort menu
// never worked on EITHER source; ame173_indexForSort maps the shared keys).
// (5) CF modpack version downloads all failed: double root cause -- the
// MCIM mirror's 302 keeps the zero-padded edge path (/files/8697/067/...)
// which mediafilez.forgecdn.net rejects with 403 (unpadded /8697/67/ works,
// verified live), and ModVersion.parseCurseForgeDictionary never ran the
// download URL through PLMirrorCenter (ModrinthAPI always did). CDN
// fallback now emits unpadded segments; CF primaryFile URLs are
// mirror-resolved like Modrinth's.
// (6) Download-page game-version picker stopped at 1.21.1/1.16.5: the
// manifest filter required the "1." prefix (26.x dropped), the 32-entry
// cap cut everything below 1.16.4, and a failed manifest load left a
// 5-entry fallback. Manifests now load through the PLMirrorCenter GameFile
// candidate chain (official + bmclapi), releases are accepted for any
// numeric id (26.x and 1.x, floor 1.8), the cap is 64, and the fallback
// list is the full common set (26.3 down to 1.8).
// (7) TouchController reworked into the Sodium-style component row (user
// decree "same style as Sodium, tap to auto-install AND auto-configure"):
// moved from the advanced section's toggle picker to the components
// section; installTouchControllerStandalone runs the exact Sodium flow
// (Fabric gate, bilingual confirm, Modrinth exact-title match, unified
// download task, jar into mods/) and arms the Task 172 auto-config key on
// success (UDP mode + launcher controls hidden at launch).
// (8) Home avatar disappearing on tab return (round 3): every
// showHomePage call allocated a FRESH LauncherNewsViewController, so the
// Task 169/171/172 timing patches could always be raced by the new
// instance's fetch. Both layout controllers now cache and reuse the home
// VC (cachedHomeVC) -- currentAvatar survives on the instance, and
// returning to the home tab is a zero-refetch path.
// (9) Wallpaper settings "default config inverted -> UI size and taps
// misaligned": the three slider rows (opacity/blur/card opacity) were
// built with top-aligned y=0 h=30 frames and fixed x offsets computed from
// the pre-layout cell width, mis-centring the thumb and overlapping the
// value label on wide form sheets and after rotation. All three rows are
// now built from one Auto Layout spec (icon -> title -> slider -> value,
// centerY-anchored, flexible width).
// (10) "After Forge's JIT install, launching the game pops a java runtime
// error until the launcher is restarted": one JVM per process -- the
// installer's headless JVM occupies it, and the old dialog told the user
// to restart manually. launchJVM's guard now offers Restart & Launch --
// internal.autolaunch_profile + exit(0), and LauncherRightPanel
// viewDidLoad consumes the key (selects the profile, waits 1.5s for
// UI/account readiness, fires launchGame through the full JIT wait chain).
// Plus: VGPU renderer added (PojavLauncherTeam/VGPU vendored under
// external/vgpu with iOS patches: @rpath framework dlopens, android/log
// removed, clang strict-implicit fixes; CMake builds it as libvgpu.dylib
// via two OBJECT libs to dodge the duplicate-basename collision); renderer
// list "Auto" label dropped its ": gl4es or ANGLE" suffix, MobileGlues is
// annotated (1.17+), and auto's legacy-MC branch switched from ANGLE to
// gl4es (per-version assignment, matching the CMake positioning of
// tinygl4angle as the 1.17+ wrapper).
// REVISION 17 addendum (Amethyst Task 174, no bump): neumorph canvas takeover
// + live opacity-percentage echo. Device feedback on the Task 173 neumorph
// build: "cannot reproduce the normal neumorphism at all -- everything has
// heavy halos" and "the neumorph opacity percentage does not display
// correctly". Root cause pinned: the neumorph Task 173 rewrote the CARDS to
// the normal state but kept the wallpaper layer underneath -- CSS-spec dual
// shadows (20pt offset / 60pt blur / opacity 1.0) cast onto a photo ALWAYS
// read as edge halos; the user's repro (Bing on -> tweak any UI effect ->
// Bing off) ends with the wallpaper REMOVED, so the terminal state's
// BACKGROUND is part of the normal state. Changes: (1) canvas takeover --
// with cardsNeumorphEnabled on, applyBackgroundToWindow /
// applyBackgroundToSplitViewController retire the wallpaper container behind
// a top gate (hosts painted native systemBackground; wallpaper state
// preserved on disk, Bing auto-refresh keeps persisting while veiled), and
// refreshUIEffect splits: ON retracts any live container + paints hosts
// native + one-shot forensic log; OFF rebuilds the wallpaper container in
// place if it was retracted (legacy blur re-apply unchanged). The toggle's
// terminal state now equals the repro's terminal state, background included.
// (2) cardsNeumorphOpacitySliderChanged now updates the % value label live
// (blur-slider pattern: slider -> contentView -> viewWithTag 501); the label
// previously froze at the last cellForRow value for the whole drag. Device
// anchor: the one-shot forensic line "[Task174] neumorph UI canvas active --
// wallpaper layer retracted" prints once per launch when the canvas governs.
