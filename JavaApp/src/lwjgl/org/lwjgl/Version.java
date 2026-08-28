/*
 * iOS 适配版：覆盖 LWJGL 版本号以满足 Sodium 0.9+ 的版本检查。
 *
 * Sodium 要求 LWJGL >= 3.4.1，但 iOS 预打包的 lwjgl-system.jar 仍为 3.3.x。
 * 此源码覆盖层在编译时替换 jar 中的 Version.class，报告版本 3.4.1。
 */
package org.lwjgl;

public final class Version {

    public static final int VERSION_MAJOR = 3;
    public static final int VERSION_MINOR = 4;
    public static final int VERSION_REVISION = 1;
    public static final BuildType BUILD_TYPE = BuildType.STABLE;

    private static final String version;

    static {
        String v = createImplementation(
            "3.4.1",
            "3.4.1"
        );
        version = v != null ? v : "3.4.1";
    }

    private Version() {}

    public static String getVersion() {
        return version;
    }

    public static String createImplementation(String specVersion, String implVersion) {
        String ver = VersionImpl.find();
        if (ver != null) {
            return ver;
        }
        // Fallback: use specVersion as version string
        return specVersion;
    }
}
