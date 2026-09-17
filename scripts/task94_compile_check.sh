#!/bin/bash
# Task94: ECJ 编译验证（Tools.java / PojavLauncher.java / overlay Version.java + VersionImpl.java）
# 用法：bash scripts/task94_compile_check.sh [--keep]   （--keep 保留产物目录便于 harness 复用）
set -e
REPO=/home/z/my-project/Amethyst-iOS-MyRemastered
ECJ=/tmp/ecj.jar
TD=/tmp/task94_build
rm -rf "$TD"; mkdir -p "$TD/ov" "$TD/t" "$TD/p" "$TD/stub/com/apple/eawt"

# CI 的 macOS JDK 自带 com.apple.eawt，Linux 本地编译验证需要桩
cat > "$TD/stub/com/apple/eawt/Application.java" <<'EOF'
package com.apple.eawt;
public class Application {
    private static final Application sApplication = new Application();
    public static Application getApplication() { return sApplication; }
}
EOF

CP="$TD/stub:$REPO/JavaApp/src/launcher:$REPO/JavaApp/src/lwjgl"
for j in "$REPO"/JavaApp/libs/*/*.jar; do
  [ -e "$j" ] && CP="$CP:$j"
done

echo "=== 1. overlay Version + VersionImpl（自包含，Java 8 目标与 LWJGL 构建一致） ==="
java -jar $ECJ -nowarn -source 8 -target 8 -d "$TD/ov" \
  "$REPO/JavaApp/src/lwjgl/org/lwjgl/Version.java" \
  "$REPO/JavaApp/src/lwjgl/org/lwjgl/VersionImpl.java"
ls "$TD/ov/org/lwjgl/Version.class" "$TD/ov/org/lwjgl/VersionImpl.class" >/dev/null && echo "overlay OK"

echo "=== 2. Tools.java（完整 classpath） ==="
java -jar $ECJ -nowarn -source 17 -target 17 -cp "$CP" -d "$TD/t" \
  "$REPO/JavaApp/src/launcher/net/kdt/pojavlaunch/Tools.java" 2>&1 | grep -E "^[0-9]+\. ERROR" && exit 1
[ -f "$TD/t/net/kdt/pojavlaunch/Tools.class" ] && echo "Tools.class OK"

echo "=== 3. PojavLauncher.java（eawt 桩 + add-exports sun.font；CI 由 macOS JDK 直接满足） ==="
java -jar $ECJ -nowarn -source 8 -target 8 \
  --add-exports java.desktop/sun.font=ALL-UNNAMED \
  -cp "$CP" -d "$TD/p" \
  "$REPO/JavaApp/src/launcher/net/kdt/pojavlaunch/PojavLauncher.java" 2>&1 | grep -E "^[0-9]+\. ERROR" && exit 1
[ -f "$TD/p/net/kdt/pojavlaunch/PojavLauncher.class" ] && echo "PojavLauncher.class OK"

echo "ALL COMPILE CHECKS PASSED (artifacts in $TD)"
