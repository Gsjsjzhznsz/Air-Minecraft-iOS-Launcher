package com.mojang.text2speech;

public interface Narrator {
    void say(final String msg, final boolean interrupt);

    /**
     * Three-arg variant introduced in the MC 26.3 series (26.3-pre-1 call
     * sites pass a float volume argument). Kept alongside the legacy 2-arg
     * overload because the same launcher.jar must satisfy older MC versions
     * whose Narrator interface only declares the 2-arg form.
     */
    void say(final String msg, final boolean interrupt, final float volume);

    void clear();

    boolean active();

    void destroy();

    /**
     * Task 73（崩溃根因修复）：真实 text2speech 1.19.12 API 的空叙述者实例。
     *
     * MC 26.2 + Fabulously Optimized v14.1.0 崩溃链：
     *   Minecraft.<init>:733 → new GameNarrator → 类验证期解析 ModernFix
     *   (suppress_narrator_stacktrace) GameNarratorMixin 注入的 catch 块类型
     *   Narrator$InitializeException → 桩缺失该符号 →
     *   NoClassDefFoundError: com/mojang/text2speech/Narrator$InitializeException。
     *
     * ModernFix 的 mixin 同时引用 Narrator.EMPTY（叙述器初始化失败时的回退值）
     * 与 OperatingSystem 枚举——三者必须一并补齐，缺一会在运行期命中下一个
     * NoClassDefFoundError/NoSuchFieldError。EMPTY 语义与真实库一致：
     * 全 no-op、active()=false。
     */
    Narrator EMPTY = new NarratorDummy();

    /**
     * Task 73：按真实 1.19.12 API 复刻的叙述器初始化异常。
     * 真实类为 public class InitializeException extends Exception，
     * 构造器 (String) 与 (String, Throwable)；接口成员类隐式 public static，
     * 与真实字节码的访问标志一致（public super）。
     */
    class InitializeException extends Exception {
        public InitializeException(final String message) {
            super(message);
        }

        public InitializeException(final String message, final Throwable cause) {
            super(message, cause);
        }
    }

    /**
     * Task 73：真实 1.19.12 API 的致命叙述器异常（RuntimeException，
     * 构造器仅 (String)）。当前无已知调用方（client 26.2/26.3 与 ModernFix
     * 均未引用），纯 API 完整性防御——真实 getNarrator() 在平台叙述器初始化
     * 失败时抛出，未来 mod 或 MC 版本引用时不缺符号。
     */
    class FatalException extends RuntimeException {
        public FatalException(final String message) {
            super(message);
        }
    }

    static Narrator getNarrator() {
        return new NarratorDummy();
    }

    static void setJNAPath(String sep) {
        System.setProperty("jna.library.path", System.getProperty("jna.library.path") + sep + "./src/natives/resources/");
        System.setProperty("jna.library.path", System.getProperty("jna.library.path") + sep + System.getProperty("java.library.path"));
    }
}
