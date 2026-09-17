/*
 * iOS 适配版（Task 94 重写）：与 Version.getVersion() 同源的动态版本解析。
 *
 * 原版从 MANIFEST.MF / Package.getSpecificationVersion() 读取版本，但
 * JavaApp/Makefile 合并 jar 时会剥掉 META-INF（rm -rf META-INF 后 jar -cf
 * 重建），Package API 返回 null；旧 overlay 因此硬编码 "3.4.1"，导致
 * 1.20.1 整合包被 sodium 0.5.13 的版本门拒绝（要求 startsWith("3.3.1")）。
 * 现在与 Version.getVersion() 走同一条动态解析链：
 *   org.lwjgl.version.report 属性（Tools.preProcessLibraries 从实例
 *   version.json 捕获） -> 按 -Dpojav.lwjgl.version 集合选择回退。
 */
package org.lwjgl;

public class VersionImpl {

    static String find() {
        return Version.getVersion();
    }
}
