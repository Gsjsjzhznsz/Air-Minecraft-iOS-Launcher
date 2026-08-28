/*
 * iOS 适配版：VersionImpl 直接返回 3.4.1 版本字符串。
 *
 * 原版从 MANIFEST.MF / Package.getSpecificationVersion() 读取版本，
 * 但 iOS 预打包 jar 的 MANIFEST.MF 记录的是 3.3.3-snapshot。
 * 覆盖此类直接返回 3.4.1。
 */
package org.lwjgl;

public class VersionImpl {

    static String find() {
        return "3.4.1";
    }
}
