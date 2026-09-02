package com.mojang.blaze3d.platform;

/**
 * iOS stub shadowing Minecraft's MacosUtil.
 *
 * The launcher reports os.name=Mac OS X, so Minecraft's Window constructor
 * unconditionally invokes MacosUtil.disableCloseWindowMenuItem() on 26.x
 * snapshots. That method drives AppKit through ca.weblite java-objc-bridge
 * (NSApplication/windowsMenu), which does not exist on iOS and crashes the
 * game during initialization.
 *
 * This no-op version is packaged inside launcher.jar, which the Pojav
 * classloader searches before the Minecraft client jar, so it shadows the
 * real class. Older versions never reach this code path (their call is gated
 * behind GLFW's cocoa backend check), so shadowing them is harmless.
 *
 * Method set mirrors MC 26.3-pre-1's MacosUtil (verified by scanning the
 * official client jar's constant pool, scripts/scan_stub_refs.py):
 * disableCloseWindowMenuItem() existed in the 26.3 snapshots;
 * setFullscreenMenuVisibility(Z) and setCtrlClickEmulatesRightClick(Z) are
 * new call sites in 26.3-pre-1 (Options.<init> calls the latter, which
 * previously crashed with NoSuchMethodError). All three drive AppKit and
 * are meaningless on iOS, so they are no-ops here.
 */
public final class MacosUtil {
    private MacosUtil() {
    }

    public static final boolean IS_MACOS = false;

    public static void disableCloseWindowMenuItem() {
        // No-op: there is no menu bar to tweak outside of macOS.
    }

    public static void setFullscreenMenuVisibility(boolean visible) {
        // No-op: there is no AppKit menu bar on iOS.
    }

    public static void setCtrlClickEmulatesRightClick(boolean emulate) {
        // No-op: no NSEvent ctrl-click path; right-click emulation is
        // handled by the launcher's touch controller instead.
    }
}
