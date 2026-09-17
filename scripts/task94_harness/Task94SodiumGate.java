/**
 * Task94 终极验证：反射调用【BMC2 整合包里真实的 sodium 0.5.13】
 * PreLaunchChecks.isUsingKnownCompatibleLwjglVersion()（private static），
 * 验证修复后的 overlay Version 能让真实字节码的版本门放行。
 *
 * classpath 需要：overlay 编译产物 + sodium-fabric-0.5.13+mc1.20.1.jar
 * （由 scripts/verify_task94.py 自动准备，或手动：
 *   curl Modrinth 下载 sodium-fabric-0.5.13+mc1.20.1.jar 到 /tmp/task94_build/）
 */
public class Task94SodiumGate {
    static int pass = 0, fail = 0;

    static void check(String name, boolean cond, String detail) {
        if (cond) { pass++; System.out.println("  PASS  " + name); }
        else { fail++; System.out.println("  FAIL  " + name + "  " + detail); }
    }

    public static void main(String[] args) throws Exception {
        Class<?> c = Class.forName(
            "net.caffeinemc.mods.sodium.client.compatibility.checks.PreLaunchChecks");
        java.lang.reflect.Method m = c.getDeclaredMethod("isUsingKnownCompatibleLwjglVersion");
        m.setAccessible(true);
        java.lang.reflect.Field req = c.getDeclaredField("REQUIRED_LWJGL_VERSION");
        req.setAccessible(true);

        System.out.println("===== G. 真实 sodium 0.5.13 版本门（字节码级） =====");
        System.out.println("  [sodium] REQUIRED_LWJGL_VERSION = " + req.get(null));

        // G1: 反证旧行为——模拟旧 overlay 硬编码 3.4.1（809b847 日志实测被拒）
        System.setProperty("org.lwjgl.version.report", "3.4.1");
        boolean oldBehavior = (Boolean) m.invoke(null);
        check("G1 旧硬编码 3.4.1 被真实 sodium 拒绝（复现 809b847）",
              !oldBehavior, "sodium accepted 3.4.1 ?!");

        // G2: 修复后 1.20.1 场景——属性=3.3.1（version.json 捕获值）
        System.setProperty("org.lwjgl.version.report", "3.3.1");
        System.clearProperty("pojav.lwjgl.version");
        boolean fixed1201 = (Boolean) m.invoke(null);
        check("G2 修复后 3.3.1 通过真实 sodium 0.5.13 版本门", fixed1201,
              "sodium rejected 3.3.1 ?!");

        System.out.println("===== Task94SodiumGate RESULT: " + pass + " PASS, " + fail + " FAIL =====");
        if (fail > 0) System.exit(1);
    }
}
