/*
 * iOS 适配版（Task 94 重写）：动态 LWJGL 版本上报。
 *
 * 背景：Sodium 在 PreLaunchChecks 里硬性校验 org.lwjgl.Version.getVersion()
 * 必须以其所支持版本开头（startsWith）：
 *   - sodium 0.5.13（MC 1.20.x 整合包，如 BMC2 537 mods）要求 "3.3.1"
 *   - sodium 0.9+（MC 26.x）要求 "3.4.1"
 * 旧 overlay（Task 9x 之前）把两个 LWJGL 集合都硬编码上报 "3.4.1" 以满足 26.x，
 * 结果 1.20.1 整合包被 sodium 0.5.13 拒绝：
 *   "The game failed to start because the currently active LWJGL version
 *    is not compatible. Installed version: 3.4.1 / Required version: 3.3.1"
 * 然后 System.exit(1)（809b847 双日志，zink 与 LTW 同一处死亡，与渲染器无关）。
 *
 * 现在由 Tools.preProcessLibraries 在启动时从实例 version.json 的
 * libraries 里捕获 "org.lwjgl:lwjgl:<ver>"（与 Mojang 为该版本配套的 LWJGL
 * 一致，sodium 的要求值即来源于此），写入系统属性 org.lwjgl.version.report。
 * 本类 getVersion() 每次调用动态读取该属性；未设置时按 native 启动器传入的
 * -Dpojav.lwjgl.version（333/341 集合选择）回退：341 -> "3.4.1"（26.x，
 * 与旧行为一致），333 -> "3.3.1"（1.18~1.20.x 的 sodium 要求值；真实构建是
 * 3.3.3，但 "3.3.3".startsWith("3.3.1") 为 false 会被拒，故回退值取 3.3.1）。
 */
package org.lwjgl;

public final class Version {

    public static final int VERSION_MAJOR;
    public static final int VERSION_MINOR;
    public static final int VERSION_REVISION;
    public static final BuildType BUILD_TYPE = BuildType.STABLE;

    static {
        int[] mmr = parseMMR(getVersion());
        VERSION_MAJOR = mmr[0];
        VERSION_MINOR = mmr[1];
        VERSION_REVISION = mmr[2];
    }

    private Version() {}

    public static String getVersion() {
        // Task94: 优先用实例 version.json 声明的版本（由 Tools.preProcessLibraries
        // 启动时写入）。动态读取（而非 clinit 固化），保证属性写入晚于类加载也生效。
        String reported = System.getProperty("org.lwjgl.version.report");
        if (reported != null) {
            reported = reported.trim();
            if (!reported.isEmpty()) {
                return reported;
            }
        }
        // 回退：按 native 启动器选择的 LWJGL 集合（-Dpojav.lwjgl.version=333/341）
        if ("341".equals(System.getProperty("pojav.lwjgl.version"))) {
            return "3.4.1";
        }
        return "3.3.1";
    }

    public static String createImplementation(String specVersion, String implVersion) {
        String ver = VersionImpl.find();
        if (ver != null) {
            return ver;
        }
        return specVersion;
    }

    /** "3.3.1" / "3.4.1" -> {3, 3, 1}；解析失败按 {3, 3, 1} 兜底。 */
    private static int[] parseMMR(String v) {
        int[] out = {3, 3, 1};
        if (v == null) {
            return out;
        }
        String[] parts = v.split("[^0-9]+");
        int idx = 0;
        for (String p : parts) {
            if (p.isEmpty()) {
                continue;
            }
            try {
                out[idx] = Integer.parseInt(p.length() > 3 ? p.substring(0, 3) : p);
            } catch (NumberFormatException ignored) {
            }
            if (++idx == 3) {
                break;
            }
        }
        return out;
    }

    public enum BuildType {
        SNAPSHOT,
        STABLE
    }
}
