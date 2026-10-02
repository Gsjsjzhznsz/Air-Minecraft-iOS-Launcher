import com.metallum.shaded.asm.ClassReader;
import com.metallum.shaded.asm.ClassVisitor;
import com.metallum.shaded.asm.ClassWriter;
import com.metallum.shaded.asm.MethodVisitor;
import com.metallum.shaded.asm.Opcodes;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;
import java.util.jar.JarOutputStream;
import java.util.jar.Manifest;

/**
 * Task211: make MetallumAgent's premain monitor threads DAEMON.
 *
 * (Chronicle: authored under the previous session's internal "Task210"
 * numbering; that sandbox died before push and the number had already been
 * yielded to the parallel UI round b7220d0 -- renumbered to Task 211 and
 * re-derived from the current repo jar, byte-verified end-to-end.)
 *
 * Device forensics (17c5100 latestlog.old.txt, ANGLE 26.3 session): MC 26.3's
 * new ClientShutdownWatchdog fires "Client shutdown from post-main" whenever
 * the JVM lingers after main() returns. The only non-daemon threads keeping
 * DestroyJavaVM waiting were "metallum-state" (our bundled metallum_agent.jar,
 * Task201) and "metallum-dump" -- premain starts them WITHOUT setDaemon(true)
 * (state: 24 x 5s probes; dump: 35s one-shot). Exit within ~120s of JVM start
 * => watchdog => the user sees a crash report on every "退出游戏".
 *
 * Patch: in premain, before EVERY `invokevirtual java/lang/Thread.start ()V`,
 * insert `dup; iconst_1; invokevirtual java/lang/Thread.setDaemon (Z)V`.
 * Stack shape at the start() boundary is unchanged ([Thread]), the insertion
 * does not alter stack depth at any label boundary, so the original
 * StackMapTable frames stay valid (COMPUTE_MAXS only, no COMPUTE_FRAMES).
 *
 * Reproduce (repo script names are lowercase; javac needs exact class-named
 * files, so compile through temp copies):
 *   cp scripts/task211_metallum_daemon_patch.java /tmp/Task211MetallumDaemonPatch.java
 *   cp scripts/task211_metallum_probe.java /tmp/T211Probe.java
 *   java -jar /tmp/ecj.jar -21 -nowarn -cp JavaApp/libs/others/metallum_agent.jar \
 *       /tmp/Task211MetallumDaemonPatch.java /tmp/T211Probe.java -d /tmp/t211
 *   java -cp /tmp/t211:JavaApp/libs/others/metallum_agent.jar \
 *       Task211MetallumDaemonPatch JavaApp/libs/others/metallum_agent.jar /tmp/patched.jar
 * E2E gate: T211Probe (scripts/task211_metallum_probe.java) with
 *   -javaagent:patched.jar  => metallum-dump/state daemon=true + exit 0 in <2s
 *   -javaagent:original.jar => daemon=false + JVM hangs (timeout kill) [control]
 */
public class Task211MetallumDaemonPatch {
    public static void main(String[] args) throws Exception {
        if (args.length != 2) {
            System.err.println("usage: Task211MetallumDaemonPatch <in-jar> <out-jar>");
            System.exit(2);
        }
        Path in = Path.of(args[0]);
        Path out = Path.of(args[1]);

        byte[] original;
        try (JarFile jar = new JarFile(in.toFile())) {
            InputStream is = jar.getInputStream(new JarEntry("com/metallum/agent/MetallumAgent.class"));
            if (is == null) throw new IllegalStateException("MetallumAgent.class not found in " + in);
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            is.transferTo(bos);
            original = bos.toByteArray();
        }

        ClassReader cr = new ClassReader(original);
        ClassWriter cw = new ClassWriter(cr, ClassWriter.COMPUTE_MAXS);
        final int[] patched = {0};
        cr.accept(new ClassVisitor(Opcodes.ASM9, cw) {
            @Override
            public MethodVisitor visitMethod(int access, String name, String descriptor,
                                             String signature, String[] exceptions) {
                MethodVisitor mv = super.visitMethod(access, name, descriptor, signature, exceptions);
                if (!name.equals("premain")) return mv;
                return new MethodVisitor(Opcodes.ASM9, mv) {
                    @Override
                    public void visitMethodInsn(int opcode, String owner, String mName, String mDesc, boolean isInterface) {
                        if (opcode == Opcodes.INVOKEVIRTUAL
                                && owner.equals("java/lang/Thread")
                                && mName.equals("start")
                                && mDesc.equals("()V")) {
                            // [Thread] -> [Thread, Thread] -> [Thread, Thread, 1] -> [Thread]
                            super.visitInsn(Opcodes.DUP);
                            super.visitInsn(Opcodes.ICONST_1);
                            super.visitMethodInsn(Opcodes.INVOKEVIRTUAL, "java/lang/Thread",
                                    "setDaemon", "(Z)V", false);
                            patched[0]++;
                        }
                        super.visitMethodInsn(opcode, owner, mName, mDesc, isInterface);
                    }
                };
            }
        }, 0);
        byte[] patchedClass = cw.toByteArray();

        if (patched[0] != 2) {
            throw new IllegalStateException("expected exactly 2 Thread.start() sites in premain, patched " + patched[0]);
        }

        // Rewrite the jar: every entry byte-copied, MetallumAgent.class replaced.
        try (JarFile jar = new JarFile(in.toFile());
             JarOutputStream jos = new JarOutputStream(Files.newOutputStream(out))) {
            Manifest mf = jar.getManifest();
            if (mf != null) {
                JarEntry me = new JarEntry(JarFile.MANIFEST_NAME);
                jos.putNextEntry(me);
                mf.write(jos);
                jos.closeEntry();
            }
            java.util.Enumeration<JarEntry> entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry e = entries.nextElement();
                if (JarFile.MANIFEST_NAME.equals(e.getName())) continue;
                if (e.getName().equals("com/metallum/agent/MetallumAgent.class")) {
                    JarEntry ne = new JarEntry(e.getName());
                    jos.putNextEntry(ne);
                    jos.write(patchedClass);
                    jos.closeEntry();
                } else {
                    // preserve compression + timestamps
                    jos.putNextEntry(e);
                    try (InputStream is = jar.getInputStream(e)) {
                        is.transferTo(jos);
                    }
                    jos.closeEntry();
                }
            }
        }
        System.out.println("Task211MetallumDaemonPatch: OK - " + patched[0]
                + " Thread.start() sites daemonized in premain; wrote " + out);
    }
}
