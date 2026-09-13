package com.mojang.text2speech;

/**
 * Task 73：真实 text2speech 1.19.12 的 macOS 叙述器类名为 NarratorMac
 * （旧版桩误命名为 NarratorOSX，与真实 jar 不符）。
 *
 * 当前 client 26.2/26.3 与 FO v14.1.0 的 51 个 mod 均未直接引用该类，
 * 此处仅为 API 形状对齐的防御性补齐：若未来 mod（或 ModernFix 新版本）
 * 按 OperatingSystem.get()==MAC_OS 分支构造 NarratorMac，不再缺符号。
 * 行为与 NarratorDummy 一致——iOS 无 AppKit 语音合成，叙述器始终为空实现。
 */
public class NarratorMac extends NarratorDummy {
}
