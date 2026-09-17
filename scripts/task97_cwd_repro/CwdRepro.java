import java.io.File;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Arrays;

/**
 * Task97 D 区复现件：用干净 JDK 复现 2f90d13 装机日志的双模组崩溃对。
 *
 * 背景机制（Java 相对路径双轨制）：
 *   - java.nio（Paths/Files）把相对路径解析到 JVM 启动时的 user.dir 属性
 *     （sun.nio.fs.UnixFileSystem 在构造时读一次 user.dir 作为 defaultDirectory，
 *      -Duser.dir=<dir> 在文件系统初始化前生效）；
 *   - java.io.File 的相对路径直接走进程 CWD（stat/opendir 的内核语义）。
 * 桌面启动器永远以 CWD == 游戏目录启动 java，两轨合一；本启动器旧版只设
 * -Duser.dir 而不 chdir，两轨分裂——正是 2f90d13（BMC2 [FABRIC] 1.20.1,
 * 474 mods, 6c3d49d 构建, zink, iPad Air M4）两 mod 崩溃的共同根因：
 *   - paintings（Paintings++ 11.0.0.1）PaintingPackReader.scanPacks：
 *       nio 门（Files.isDirectory("./resourcepacks")，走 user.dir = 游戏目录，
 *       整合包自带 resourcepacks/）→ true；io 列目录（new File(...).listFiles()，
 *       走进程 CWD）→ NULL → Arrays.stream(null) → NPE；
 *   - sparsestructures 2.1.2 onInitialize：
 *       io 守卫（toFile().exists()，走 CWD）→ false 放行；nio 创建
 *       （Files.createDirectories，走 user.dir）命中整合包自带的同名「文件」
 *       → FileAlreadyExistsException: config/sparsestructures.json5。
 *
 * 用法（verify_task97.py 驱动）：
 *   分裂场景：cwd=<空目录>  java -Duser.dir=<游戏目录> CwdRepro.java <mode>
 *   对齐场景：cwd=<游戏目录> java -Duser.dir=<游戏目录> CwdRepro.java <mode>
 *
 * 注意：全程使用相对路径字符串，不调用 toAbsolutePath()，保持 nio/io 两轨
 * 各自解析的真实形态（否则 Path 一旦绝对化，两轨就不再分裂）。
 */
public class CwdRepro {
    static final String RESOURCEPACKS = "resourcepacks";
    static final String CONFIG_FILE = "config/sparsestructures.json5";

    public static void main(String[] args) throws Exception {
        String mode = args.length > 0 ? args[0] : "probe";
        switch (mode) {
            case "probe":
                System.out.println("PROBE nio.resourcepacks.isdir=" + Files.isDirectory(Paths.get(RESOURCEPACKS)));
                File[] files = new File(RESOURCEPACKS).listFiles();
                System.out.println("PROBE io.resourcepacks.listFiles=" + (files == null ? "NULL" : String.valueOf(files.length)));
                System.out.println("PROBE io.cfg.exists=" + Paths.get(CONFIG_FILE).toFile().exists());
                System.out.println("PROBE nio.cfg.isRegularFile=" + Files.isRegularFile(Paths.get(CONFIG_FILE)));
                break;
            case "paintings":
                // subaraki.paintings.utils.PaintingPackReader.scanPacks 的形态：
                // nio 门 + io 列目录 + 流式消费。
                if (Files.isDirectory(Paths.get(RESOURCEPACKS))) {
                    File[] packs = new File(RESOURCEPACKS).listFiles();
                    long count = Arrays.stream(packs).count(); // 分裂时在此 NPE
                    System.out.println("PAINTINGS OK packs=" + count);
                } else {
                    System.out.println("PAINTINGS SKIP (nio gate says no resourcepacks dir)");
                }
                break;
            case "sparsestructures":
                // io.github.maxencedc.sparsestructures.SparseStructures.onInitialize 的形态：
                // io 守卫 + nio 创建。
                if (!Paths.get(CONFIG_FILE).toFile().exists()) {
                    Files.createDirectories(Paths.get(CONFIG_FILE)); // 分裂时在此 FileAlreadyExistsException
                    System.out.println("SPARSESTRUCTURES CREATED");
                } else {
                    System.out.println("SPARSESTRUCTURES EXISTS-SKIP");
                }
                break;
            default:
                throw new IllegalArgumentException("unknown mode: " + mode);
        }
    }
}
