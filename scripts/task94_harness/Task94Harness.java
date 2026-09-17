/**
 * Task94 行为验证 harness：模拟 Sodium PreLaunchChecks 的版本门，
 * 验证 overlay Version.getVersion() 的动态上报矩阵。
 *
 * 场景矩阵（对应真机链路）：
 *  A. 1.20.1 整合包：Tools 捕获 version.json 的 org.lwjgl:lwjgl:3.3.1 写属性
 *     → getVersion() 必须 startsWith("3.3.1")（sodium 0.5.13 的要求）
 *  B. 26.x：属性=3.4.1 → startsWith("3.4.1")（sodium 0.9+ 的要求）
 *  C. 属性运行期才写入（模拟 Tools 在 getVersionInfo 阶段、sodium 调用之前写入；
 *     类可能已被 PojavLauncher sanity 日志提前加载）→ 动态读取必须生效
 *  D. 无属性回退：pojav.lwjgl.version=333 → "3.3.1"；=341 → "3.4.1"；都没有 → "3.3.1"
 *  E. 常量一致性：VERSION_MAJOR/MINOR/REVISION 与上报值一致
 *  F. 边界：属性为空白串时视为未设置走回退；1.20.5 的 3.3.2 原样上报
 */
public class Task94Harness {
    static int pass = 0, fail = 0;

    static void check(String name, boolean cond, String detail) {
        if (cond) { pass++; System.out.println("  PASS  " + name); }
        else { fail++; System.out.println("  FAIL  " + name + "  " + detail); }
    }

    public static void main(String[] args) throws Exception {
        System.out.println("===== A. 1.20.1 元数据路径（BMC2 场景） =====");
        System.setProperty("org.lwjgl.version.report", "3.3.1");
        System.clearProperty("pojav.lwjgl.version");
        String v = org.lwjgl.Version.getVersion();
        check("A1 上报 3.3.1", "3.3.1".equals(v), "got " + v);
        check("A2 sodium 0.5.13 门 startsWith(\"3.3.1\") 通过", v.startsWith("3.3.1"), "got " + v);

        System.out.println("===== B. 26.x 元数据路径 =====");
        System.setProperty("org.lwjgl.version.report", "3.4.1");
        System.setProperty("pojav.lwjgl.version", "341");
        v = org.lwjgl.Version.getVersion();
        check("B1 上报 3.4.1", "3.4.1".equals(v), "got " + v);
        check("B2 sodium 0.9+ 门 startsWith(\"3.4.1\") 通过", v.startsWith("3.4.1"), "got " + v);

        System.out.println("===== C. 运行期后写属性（类已加载后再写） =====");
        System.clearProperty("org.lwjgl.version.report");
        String stale = org.lwjgl.Version.getVersion(); // 此时无属性 -> 回退
        System.setProperty("org.lwjgl.version.report", "3.3.1");
        v = org.lwjgl.Version.getVersion();
        check("C1 后写属性动态生效（不受首次调用固化）", "3.3.1".equals(v),
              "stale=" + stale + " now=" + v);

        System.out.println("===== D. 无属性回退矩阵 =====");
        System.clearProperty("org.lwjgl.version.report");
        System.setProperty("pojav.lwjgl.version", "341");
        check("D1 341 集合回退 3.4.1", "3.4.1".equals(org.lwjgl.Version.getVersion()),
              org.lwjgl.Version.getVersion());
        System.setProperty("pojav.lwjgl.version", "333");
        check("D2 333 集合回退 3.3.1", "3.3.1".equals(org.lwjgl.Version.getVersion()),
              org.lwjgl.Version.getVersion());
        System.clearProperty("pojav.lwjgl.version");
        check("D3 双缺省回退 3.3.1", "3.3.1".equals(org.lwjgl.Version.getVersion()),
              org.lwjgl.Version.getVersion());

        System.out.println("===== E. 常量一致性（当前上报 3.3.1） =====");
        check("E1 VERSION_MAJOR==3", org.lwjgl.Version.VERSION_MAJOR == 3,
              String.valueOf(org.lwjgl.Version.VERSION_MAJOR));
        check("E2 VERSION_MINOR==3", org.lwjgl.Version.VERSION_MINOR == 3,
              String.valueOf(org.lwjgl.Version.VERSION_MINOR));
        check("E3 VERSION_REVISION==1", org.lwjgl.Version.VERSION_REVISION == 1,
              String.valueOf(org.lwjgl.Version.VERSION_REVISION));

        System.out.println("===== F. 边界 =====");
        System.setProperty("org.lwjgl.version.report", "   ");
        System.setProperty("pojav.lwjgl.version", "333");
        check("F1 空白属性视为未设置走回退", "3.3.1".equals(org.lwjgl.Version.getVersion()),
              org.lwjgl.Version.getVersion());
        System.setProperty("org.lwjgl.version.report", "3.3.2");
        check("F2 1.20.5 的 3.3.2 原样上报（元数据即真相）",
              "3.3.2".equals(org.lwjgl.Version.getVersion()),
              org.lwjgl.Version.getVersion());
        System.setProperty("org.lwjgl.version.report", "3.3.1");
        check("F3 1.20.1 + 333 组合门再次通过",
              org.lwjgl.Version.getVersion().startsWith("3.3.1"),
              org.lwjgl.Version.getVersion());

        System.out.println("===== Task94Harness RESULT: " + pass + " PASS, " + fail + " FAIL =====");
        if (fail > 0) System.exit(1);
    }
}
