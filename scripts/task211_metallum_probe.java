import java.util.Map;

/**
 * Task211 E2E gate for the metallum daemon patch (see
 * scripts/task211_metallum_daemon_patch.java for the full chronicle).
 *
 * Run WITH the jar under test as -javaagent:
 *   timeout 30 java -javaagent:<jar> -cp <dir-of-this-class> T211Probe
 * PASS criteria: both monitor threads visible AND daemon=true; main() returns
 * and the JVM exits promptly (exit 0, well under the timeout).
 * CONTROL (unpatched jar): daemon=false and the JVM hangs past main() return
 * (timeout kills it, exit 124) -- the on-device "crash on exit" mechanism.
 */
public class T211Probe {
    public static void main(String[] args) throws Exception {
        // let the agent's monitor threads spin up
        Thread.sleep(1500);
        boolean sawDump = false, sawState = false;
        for (Map.Entry<Thread, StackTraceElement[]> e : Thread.getAllStackTraces().entrySet()) {
            Thread t = e.getKey();
            if (t.getName().equals("metallum-dump")) {
                sawDump = true;
                System.out.println("PROBE metallum-dump daemon=" + t.isDaemon());
            }
            if (t.getName().equals("metallum-state")) {
                sawState = true;
                System.out.println("PROBE metallum-state daemon=" + t.isDaemon());
            }
        }
        System.out.println("PROBE sawDump=" + sawDump + " sawState=" + sawState);
        if (!sawDump || !sawState) {
            System.out.println("PROBE FAIL: monitor threads not found");
            System.exit(1);
        }
        System.out.println("PROBE OK -- main() returning now; JVM should exit immediately (daemon threads no longer block DestroyJavaVM)");
    }
}
