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

    static Narrator getNarrator() {
        return new NarratorDummy();
    }

    static void setJNAPath(String sep) {
        System.setProperty("jna.library.path", System.getProperty("jna.library.path") + sep + "./src/natives/resources/");
        System.setProperty("jna.library.path", System.getProperty("jna.library.path") + sep + System.getProperty("java.library.path"));
    }
}
