#!/bin/bash
# Builds the Amethyst LWJGL Java jars (3.3.3 and 3.4.1) from the lwjgl-lib sources.
#
# The sources live in $SOURCEDIR/lwjgl-lib/3.3.3-lwgjl and
# $SOURCEDIR/lwjgl-lib/3.4.1-lwgjl. Fix LWJGL bugs in those sources and
# re-run this script (or `make java`) to rebuild; the launcher itself does
# not need any changes for library fixes.
#
# Output: JavaApp/libs/lwjgl-333/*.jar and JavaApp/libs/lwjgl-341/*.jar
# (the per-module jars produced by the LWJGL ant build).
#
# IMPORTANT: this script does NOTHING unless BUILD_LWJGL=1 is set.
#
# The prebuilt LWJGL jars (JavaApp/libs/lwjgl-333 and -341) are committed to
# git and are what a normal build packages. Building from source is opt-in:
#
#     BUILD_LWJGL=1 make java          # or: BUILD_LWJGL=1 scripts/build_lwjgl.sh
#
# It previously ran unconditionally, which broke CI: GitHub's macOS runners
# ship Apache Ant and Temurin 8, so the script really did try to compile LWJGL
# from source, needed extra tooling plus network access, and failed in about
# two minutes with make exit code 2. Building from source is now attempted
# only when explicitly requested; when it is, a missing toolchain is a hard
# error (so the request cannot silently go unfulfilled).
#
# Requirements when BUILD_LWJGL=1: JDK 8 (used to compile LWJGL), ant, and
# network access on the first build (ant init downloads the LWJGL build
# dependencies).
#
# Note: if the sources under lwjgl-lib/ are older than the jars already in
# JavaApp/libs/lwjgl-*, this script skips the build entirely, so `make java`
# does not pay the ant cost on a normal build. When Ant or JDK 8 is missing
# it also skips (instead of failing), because the prebuilt jars are kept in
# git and are enough to produce a working app.
set -euo pipefail

# --- Opt-in gate (must stay before any toolchain probe) ------------------
# Building from source is opt-in so that a normal build (and CI) never needs
# Ant, JDK 8 or network access: the prebuilt jars are committed to git.
if [ "${BUILD_LWJGL:-0}" != "1" ]; then
    echo "[build_lwjgl] BUILD_LWJGL!=1 - skipping, using the prebuilt LWJGL jars."
    echo "[build_lwjgl] (Set BUILD_LWJGL=1 to rebuild them from lwjgl-lib/ sources.)"
    exit 0
fi
echo "[build_lwjgl] BUILD_LWJGL=1 - building LWJGL from source."
# ------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCEDIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LWJGL_LIB="$SOURCEDIR/lwjgl-lib"

# JDK 8 is required by the LWJGL ant build. Accept BOOTJDK (bin dir) from
# the Makefile, JAVA8_HOME, or fall back to java_home.
# Resolve JAVA8_HOME defensively: under `set -e` a bare `cd` into a missing
# BOOTJDK would abort the script before the friendly error below is printed.
if [ -n "${BOOTJDK:-}" ]; then
    JAVA8_HOME="$(cd "$BOOTJDK/.." 2>/dev/null && pwd || true)"
elif [ -z "${JAVA8_HOME:-}" ]; then
    JAVA8_HOME="$(/usr/libexec/java_home -v 1.8 2>/dev/null || true)"
fi
if [ -z "${JAVA8_HOME:-}" ] || [ ! -x "$JAVA8_HOME/bin/java" ]; then
    echo "Error: BUILD_LWJGL=1 but JDK 8 was not found." >&2
    echo "       Set JAVA8_HOME or BOOTJDK to a JDK 8, or unset BUILD_LWJGL" >&2
    echo "       to use the prebuilt LWJGL jars." >&2
    exit 1
fi
JAVA8_VERSION="$("$JAVA8_HOME/bin/java" -version 2>&1 | head -1)"
echo "[build_lwjgl] Using JDK 8 at $JAVA8_HOME ($JAVA8_VERSION)"

if ! command -v ant >/dev/null 2>&1; then
    echo "Error: BUILD_LWJGL=1 but Apache Ant was not found." >&2
    echo "       Install it (brew install ant), or unset BUILD_LWJGL to use the" >&2
    echo "       prebuilt LWJGL jars." >&2
    exit 1
fi
echo "[build_lwjgl] Using $(ant -version)"

# Bindings not needed by Amethyst. Everything else (core, lwjglx, glfw,
# openal, opengl, stb, nanovg, vulkan, vma, shaderc, spvc, freetype,
# tinyfd, and on 3.4.1 also sdl/spng) is enabled by the default config.
LWJGL_BINDINGS_OFF="assimp bgfx cuda egl fmod harfbuzz hwloc jawt jemalloc ktx libdivide llvm lmdb lz4 meow meshoptimizer msdfgen nfd nuklear odbc opengles opencl openvr openxr opus ovr par remotery renderdoc rpmalloc sse tinyexr tootle xxhash yoga zstd"

build_version() {
    local src_dir="$1" build_type="$2" out_dir="$3" extra_flags="$4"
    local module_jar
    local newest_src newest_jar

    echo "[build_lwjgl] === Building LWJGL $build_type from $src_dir ==="

    if [ ! -d "$LWJGL_LIB/$src_dir" ]; then
        echo "Error: LWJGL source directory not found: $LWJGL_LIB/$src_dir" >&2
        exit 1
    fi

    # Skip the build if it is already up to date (sources unchanged).
    if compgen -G "$out_dir/lwjgl*.jar" >/dev/null; then
        newest_jar="$(ls -t "$out_dir"/lwjgl*.jar | head -1)"
        newest_src="$(find "$LWJGL_LIB/$src_dir" -path '*/bin' -prune -o -path '*/.git' -prune -o -path '*/build' -prune -o -type f -newer "$newest_jar" -print -quit 2>/dev/null || true)"
        if [ -z "$newest_src" ]; then
            echo "[build_lwjgl] $out_dir is up to date, skipping"
            return 0
        fi
        echo "[build_lwjgl] Source change detected ($newest_src), rebuilding"
    fi

    pushd "$LWJGL_LIB/$src_dir" >/dev/null

    # HACK: Skip compiling and running the generator to save time and keep
    # the checked-in generated sources (and the Amethyst/LWJGLX changes).
    mkdir -p bin/classes/generator bin/classes/templates/META-INF
    touch bin/classes/generator/touch.txt bin/classes/templates/touch.txt
    touch bin/classes/generator/generated-touch.txt

    export JAVA_HOME="$JAVA8_HOME"
    export JAVA8_HOME
    export ANDROID=1

    # If a previous build died during `compile`, the "jar: update JSpecify"
    # step may have left a stub jspecify.jar (contains only NullMarked.class).
    # ant's usetimestamp then skips re-downloading the real jar, and the core
    # module fails to compile (cannot find symbol: class Nullable).
    if [ -f "$LWJGL_LIB/$src_dir/bin/libs/java/jspecify.jar" ] &&
       [ "$(stat -f%z "$LWJGL_LIB/$src_dir/bin/libs/java/jspecify.jar")" -lt 2000 ]; then
        rm "$LWJGL_LIB/$src_dir/bin/libs/java/jspecify.jar"
    fi

    # ant init downloads the build dependencies on first run. It must run
    # BEFORE LWJGL_BUILD_OFFLINE is set, otherwise the dependency check is
    # skipped and the kotlin/template toolchain is never downloaded.
    # (Feed 'y' via process substitution so `set -o pipefail` never sees
    # the SIGPIPE death of `yes` as a failure.)
    ant init < <(yes)

    # Force the Maven dependency download pass. On 3.4.x this fetches
    # jspecify.jar, which ant init's uptodate check can silently skip when
    # bin/ was removed but touch.txt survived, or when the local file is
    # newer than the server copy (see the stub guard above).
    ant -f update-dependencies.xml update-dependencies < <(yes)
    export LWJGL_BUILD_OFFLINE=true

    local binding_flags=()
    local binding
    for binding in $LWJGL_BINDINGS_OFF; do
        binding_flags+=("-Dbinding.$binding=false")
    done

    ant \
        "${binding_flags[@]}" \
        -Dbinding.shaderc=true \
        -Dbinding.vulkan=true \
        -Dbinding.vma=true \
        -Dbinding.spvc=true \
        -Dbuild.type="$build_type" \
        -Djavadoc.skip=true \
        -Dnashorn.args="--no-deprecation-warning" \
        $extra_flags \
        compile release < <(yes)

    popd >/dev/null

    echo "[build_lwjgl] Packaging jars into $out_dir"
    rm -rf "$out_dir"
    mkdir -p "$out_dir"
    find "$LWJGL_LIB/$src_dir/bin/RELEASE" \( -name '*.jar' ! -name '*-natives-*' ! -name '*-sources.jar' ! -name '*-javadoc.jar' \) -exec cp {} "$out_dir/" \;
    echo "[build_lwjgl] $(ls -1 "$out_dir" | wc -l | tr -d ' ') jars built:"
    ls -1 "$out_dir"
}

# 3.3.3 - Minecraft 1.21.11 and below (and anything below 26.x in auto mode)
build_version "3.3.3-lwgjl" "release/3.3.3" "$SOURCEDIR/JavaApp/libs/lwjgl-333" ""

# 3.4.1 - Minecraft 26.1.x and above. No -Djdk25=true: we compile on JDK 8
# and ship a plain Java 8 jar (multi-release 25 classes are optional extras
# and are not used by the current Amethyst Java runtimes).
build_version "3.4.1-lwgjl" "release/3.4.1" "$SOURCEDIR/JavaApp/libs/lwjgl-341" ""

echo "[build_lwjgl] Done."
