<div align="center">
  <img src="Natives/Assets.xcassets/AppIcon-Light.appiconset/1024x1024.png" alt="Air Icon" width="120" style="border-radius: 24px;">
</div>

<h1 align="center">Air</h1>
<p align="center"><b>A polished Minecraft: Java Edition launcher for iOS, optimized for Chinese users.</b></p>
<p align="center"><sub>Forked from <a href="https://github.com/herbrine8403/Amethyst-iOS-MyRemastered">Amethyst-iOS-MyRemastered</a></sub></p>

<div align="center">
  <img alt="Build Status" src="https://github.com/Gsjsjzhznsz/Air-Minecraft-iOS-Launcher/actions/workflows/development.yml/badge.svg?branch=main">
  <img alt="Downloads" src="https://img.shields.io/github/downloads/Gsjsjzhznsz/Air-Minecraft-iOS-Launcher/total?label=Downloads&style=flat">
  <img alt="Release" src="https://img.shields.io/github/v/release/Gsjsjzhznsz/Air-Minecraft-iOS-Launcher?style=flat">
  <img alt="License" src="https://img.shields.io/github/license/Gsjsjzhznsz/Air-Minecraft-iOS-Launcher?style=flat">
  <img alt="Last Commit" src="https://img.shields.io/github/last-commit/Gsjsjzhznsz/Air-Minecraft-iOS-Launcher?color=c78aff&label=last%20commit&style=flat">
</div>

<p align="center">
  <a href="./README.md">English</a> | <a href="./README_CN.md">Chinese</a>
</p>

---

## What is Air?

**Air** is a customized fork of [Amethyst-iOS-MyRemastered](https://github.com/herbrine8403/Amethyst-iOS-MyRemastered), a premium Minecraft: Java Edition launcher for iOS and iPadOS. This fork focuses on the **Chinese user experience** -- delivering robust Chinese localization, in-app language switching, streamlined JIT handling for iOS 26+, and bug fixes sourced from upstream issue audits.

> **Not sure which fork to use?** See the [Fork Network](#fork-network) section below for a comparison of active forks and their unique features.

---

## What's Different from Upstream

| Change | Description |
|--------|-------------|
| **LWJGL 3.4.1 Compatibility** | Updated LWJGL to a 3.4.1-compatible layer, enabling mods like Sodium 0.9+ that require LWJGL >= 3.4.1. Uses developer herbrine8403's approach: 3.3.x base modules + lwjgl-callback-descriptor.jar (3.4.1) + source overlay for dual-API compatibility. |
| **JIT Pre-enabled Direct Launch** | When JIT is already enabled (e.g. from a previous session), the game launches directly without re-requesting via stikjit:// URL, avoiding unnecessary background transitions and potential crashes on iOS 26+ devices. The JIT26 script is handled by JavaLauncher during game startup. |
| **In-App Language Switching** | Added a language picker in Settings > General that allows switching between Follow System, Simplified Chinese, and English without restarting the app. The `localize()` function respects the user's choice while maintaining the full fallback chain. |
| **Enhanced Chinese Localization** | Complete Chinese UI translation (1955+ lines), more comprehensive than upstream. |
| **Bug Fixes from Upstream Issue Audit** | 8+ bug fixes identified through systematic review of upstream and upstream's upstream GitHub issues, including nil crash in JIT script loading, UIKit thread safety, KVO observer cleanup, and more. |
| **Makefile Robustness** | Fixed TAB-to-space indentation issues that caused CI build failures. |

---

## Fork Network

This project exists within a fork chain. Understanding each fork's purpose helps you choose the right one for your needs.

```
PojavLauncherTeam/PojavLauncher_iOS          (Original upstream - official PojavLauncher iOS port)
        |
        v
herbrine8403/Amethyst-iOS-MyRemastered       (Major remastered fork - UI overhaul, mod management,
        |                                     BMCLAPI support, multi-account, auto renderer/JVM)
        |
        +----> yitenchen123/Amethyst-iOS-MyRemastered   (TouchController integration, CI optimizations,
        |                                              UI polish, UDP/XCFramework comm)
        |
        +----> Gsjsjzhznsz/Air-Minecraft-iOS-Launcher   (THIS REPO - Chinese UX, JIT direct launch,
                                                       in-app language switch, bug fixes, LWJGL 3.4.1)
```

### Active Forks Comparison

| Feature | herbrine8403 (Upstream) | yitenchen123 | Air (This Repo) |
|---------|:---:|:---:|:---:|
| **Focus** | Full-featured remaster | TouchController + CI speed | Chinese UX + Stability |
| **TouchController Mod** | No | Yes (UDP + XCFramework) | No |
| **JIT Direct Launch** | No | No | Yes |
| **In-App Language Switch** | No | No | Yes (System/ZH/EN) |
| **Chinese Localization** | Partial (via Crowdin) | Enhanced | Full (1955+ lines) |
| **BMCLAPI Mirror** | Yes | Yes | Yes |
| **LWJGL 3.4.1** | Partial | No | Yes |
| **CI Build Speed** | Standard | Optimized (prebuilt MobileGlues) | Standard |
| **Upstream Bug Fixes** | -- | No | Yes (8+ fixes) |
| **Sync Status** | Source | Behind by 950+ | Active sync |

---

## Table of Contents

- [What is Air?](#what-is-air)
- [What's Different from Upstream](#whats-different-from-upstream)
- [Fork Network](#fork-network)
- [Core Features](#core-features)
- [Quick Start](#quick-start)
  - [Device Requirements](#device-requirements)
  - [Sideload Preparation](#sideload-preparation)
  - [Installation](#installation)
  - [Enabling JIT](#enabling-jit)
- [Contributors](#contributors)
- [Fork Acknowledgments](#fork-acknowledgments)
- [Third-Party Components](#third-party-components)
- [Sponsor](#sponsor)

## Core Features

- **Modern UI Redesign** -- The interface has been deeply refined for a contemporary, polished visual style.
- **Resource Management & Downloads** -- Browse, enable, disable, and delete mods, shader packs, resource packs, and other assets, with integrated Modrinth and CurseForge download support.
- **Modpack Import** -- Import ZIP-format modpacks directly from the launcher interface.
- **Smart Download Sources** -- Switch between Mojang Official, BMCLAPI mirror, and other sources on the fly for optimal download speeds.
- **Complete Chinese Localization** -- Fully translated interface with native-quality Chinese language support. In-app language switching between Chinese and English available in Settings.
- **Unrestricted Accounts** -- Local accounts, demo mode, and third-party authentication all supported; no Microsoft account required to download and play.
- **Multi-Account** -- Seamlessly switch between Microsoft, local, and third-party authentication accounts.
- **Auto Renderer Selection** -- Automatically chooses the optimal rendering backend (including MobileGlues, MoltenVK, and more) when set to Auto.
- **Auto JVM Selection** -- Automatically selects the correct JVM version (Java 8, 17, 21, or 25) based on the game version.
- **Minecraft 26.X Support** -- Experimental support for Minecraft 26.x.
- **Custom Mouse Pointer** -- Customize the virtual mouse pointer skin in settings.
- **Custom News URL** -- Configure a custom news feed URL for the launcher home screen.
- **TouchController Support** -- Communicates with the TouchController mod via both UDP local proxy and XCFramework, delivering full touchscreen control on iOS.
- **AI Integration** -- (In development) The goal is to enable AI to fully manage the launcher, including resource downloads and instance management.
- **Custom App Icons** -- (In development)

... and much more to explore!

> [!NOTE]
> There are no plans to port this remastered version to Android. The Android ecosystem already has excellent launchers such as [Zalith Launcher](https://github.com/ZalithLauncher/ZalithLauncher), [Fold Craft Launcher](https://github.com/FCL-Team/FoldCraftLauncher), and ShardLauncher. For the official Android version, visit [Amethyst-Android](https://github.com/AngelAuraMC/Amethyst-Android).

## Quick Start

For complete documentation, refer to the [Amethyst Official Wiki](https://wiki.angelauramc.dev/wiki/getting_started/INSTALL.html#ios) or the [Bilibili tutorial](https://b23.tv/KyxZr12). Below is a condensed guide.

### Device Requirements

| Tier | iOS Version | Supported Devices |
|------|-------------|-------------------|
| **Minimum** | iOS 14.0+ | iPhone 6s+, iPad 5th gen+, iPad Air 2+, iPad mini 4+, all iPad Pro, iPod touch 7th gen |
| **Recommended** | iOS 14.5+ | iPhone XS+ (excl. XR/SE 2nd gen), iPad 10th gen+, iPad Air 4th gen+, iPad mini 6th gen+, iPad Pro (excl. 9.7-inch) |

> [!CAUTION]
> iOS 14.0--14.4.2 has known critical compatibility issues. **Upgrading to iOS 14.5 or later is strongly recommended.** iOS 17.x and 18.x are supported but require a companion computer for initial JIT configuration (see the [Official JIT Guide](https://wiki.angelauramc.dev/wiki/faq/ios/JIT.html#what-are-the-methods-to-enable-jit)).

### Sideload Preparation

Prioritize tools that support permanent signing and automatic JIT enablement:

1. **TrollStore** *(Recommended)* -- Permanent signing, automatic JIT, increased memory limits. Compatible with select iOS versions. [Download from official repo](https://github.com/opa334/TrollStore)
2. **AltStore / SideStore** *(Alternative)* -- Requires periodic re-signing; initial setup needs a computer and Wi-Fi. Only compatible with **development certificates** (must include `com.apple.security.get-task-allow` entitlement for JIT). Distribution certificate signing services are not supported.

> [!WARNING]
> Only download sideloading tools and IPA files from official or trusted sources. The author is not responsible for device issues caused by unofficial software. Jailbroken devices support permanent signing, but daily-driver jailbreaking is not recommended.

### Installation

<details>
<summary><b>Official Release (TrollStore)</b></summary>

1. Download the `.tipa` package from [Releases](https://github.com/Gsjsjzhznsz/Air-Minecraft-iOS-Launcher/releases).
2. Open the file with TrollStore via the system share menu to complete installation.
</details>

<details>
<summary><b>Official Release (AltStore / SideStore)</b></summary>

1. Download the `.ipa` package from [Releases](https://github.com/Gsjsjzhznsz/Air-Minecraft-iOS-Launcher/releases).
2. Import the IPA into your sideloading tool following its standard installation procedure.
</details>

<details>
<summary><b>Nightly Builds (Development Testing)</b></summary>

> [!CAUTION]
> Nightly builds may contain critical bugs including crashes and startup failures. Use only for development and testing purposes.

1. Navigate to the [GitHub Actions](https://github.com/Gsjsjzhznsz/Air-Minecraft-iOS-Launcher/actions) page and download the latest IPA artifact.
2. Import the IPA into your sideloading tool (AltStore, SideStore, etc.) to install.
</details>

### Enabling JIT

JIT (Just-In-Time compilation) is essential for smooth gameplay. Choose the approach that matches your environment:

| Tool | External Device | Wi-Fi Required | Auto-Enable | Notes |
|------|:---:|:---:|:---:|-------|
| TrollStore | No | No | Yes | Preferred; no additional action needed |
| AltStore | Yes | Yes | Yes | Requires AltServer running on local network |
| SideStore | First time only | First time only | No | Device/network-free after initial setup |
| StikDebug | First time only | First time only | Yes | Device/network-free after initial setup |
| Jitterbug | Yes (without VPN) | Yes | No | Manual trigger required |
| Jailbroken | No | No | Yes | System-level automatic support |

## Contributors

- [@herbrine8403](https://github.com/herbrine8403) -- Original Amethyst-iOS-MyRemastered author
- [@yitenchen123](https://github.com/yitenchen123) -- TouchController integration, CI optimizations, UI polish
- [@EternityQwQ](https://github.com/EternityQwQ) -- Metal Universal Mod support
- [@LanRhyme](https://github.com/LanRhyme) -- iOS 26 compatibility and logging improvements
- [@WeiErLiTeo](https://github.com/WeiErLiTeo) -- Mod download integration, TouchController optimizations
- [@Li2548](https://github.com/Li2548) -- Upstream synchronization

## Fork Acknowledgments

This project would not exist without the following fork chain:

- **[PojavLauncherTeam/PojavLauncher_iOS](https://github.com/PojavLauncherTeam/PojavLauncher_iOS)** -- The original iOS Minecraft launcher that started it all.
- **[herbrine8403/Amethyst-iOS-MyRemastered](https://github.com/herbrine8403/Amethyst-iOS-MyRemastered)** -- The major remastered fork that added the modern UI, mod management, BMCLAPI support, multi-account, and auto renderer/JVM selection. This is the direct upstream of Air.
- **[yitenchen123/Amethyst-iOS-MyRemastered](https://github.com/yitenchen123/Amethyst-iOS-MyRemastered)** -- A sibling fork focusing on TouchController touchscreen control integration (UDP + XCFramework communication), CI build optimizations (prebuilt MobileGlues), announcement bar UI, and Chinese localization refinements. Although Air does not directly include TouchController code, this fork's approach to Chinese user experience improvements informed several design decisions.

## About Translations

If you would like to contribute translations for this project, please go to [Crowdin](https://crowdin.com/project/amethyst-ios-remastered).

## Third-Party Components

| Component | Purpose | License | Source |
|-----------|---------|---------|--------|
| Caciocavallo | AWT runtime framework | GPL-2.0 | [GitHub](https://github.com/PojavLauncherTeam/caciocavallo) |
| jsr305 | Code annotation support | BSD-3 | [Google Code](https://code.google.com/p/jsr-305) |
| Boardwalk | Core functionality adaptation | Apache-2.0 | [GitHub](https://github.com/zhuowei/Boardwalk) |
| GL4ES | OpenGL-to-GLES translation | MIT | [GitHub](https://github.com/ptitSeb/gl4es) |
| Mesa 3D | 3D graphics library | MIT | [GitLab](https://gitlab.freedesktop.org/mesa/mesa) |
| MetalANGLE | Metal-to-OpenGL ES translation | BSD-2 | [GitHub](https://github.com/khanhduytran0/MetalANGLE) |
| MoltenVK | Vulkan-to-Metal translation | Apache-2.0 | [GitHub](https://github.com/KhronosGroup/MoltenVK) |
| openal-soft | Cross-platform 3D audio | LGPL-2.0 | [GitHub](https://github.com/kcat/openal-soft) |
| Azul Zulu JDK | Java runtime (8/17/21/25) | GPL-2.0 | [Website](https://www.azul.com/downloads/?package=jdk) |
| LWJGL3 | Java game development library | BSD-3 | [GitHub](https://github.com/PojavLauncherTeam/lwjgl3) |
| LWJGLX | LWJGL2 compatibility layer | -- | [GitHub](https://github.com/PojavLauncherTeam/lwjglx) |
| DBNumberedSlider | UI slider control | Apache-2.0 | [GitHub](https://github.com/khanhduytran0/DBNumberedSlider) |
| fishhook | Dynamic library rebinding | BSD-3 | [GitHub](https://github.com/khanhduytran0/fishhook) |
| shaderc | Vulkan shader compilation | Apache-2.0 | [GitHub](https://github.com/khanhduytran0/shaderc) |
| NRFileManager | File management utilities | MPL-2.0 | [GitHub](https://github.com/mozilla-mobile/firefox-ios) |
| AltKit | AltStore integration | -- | [GitHub](https://github.com/rileytestut/AltKit) |
| UnzipKit | ZIP archive handling | BSD-2 | [GitHub](https://github.com/abbeycode/UnzipKit) |
| DyldDeNeuralyzer | Library verification bypass | -- | [GitHub](https://github.com/xpn/DyldDeNeuralyzer) |
| MobileGlues | Third-party renderer | LGPL-2.1 | [GitHub](https://github.com/MobileGL-Dev/MobileGlues) |
| LTW | OpenGL Core-to-ES wrapper | LGPL-3.0 | [GitHub](https://github.com/MojoLauncher/LTW) |
| authlib-injector | Third-party authentication | AGPL-3.0 | [GitHub](https://github.com/yushijinhun/authlib-injector) |

Additional thanks to [MCHeads](https://mc-heads.net) for Minecraft avatar services, [Modrinth](https://modrinth.com) for mod distribution, and [BMCLAPI](https://bmclapidoc.bangbang93.com) for Minecraft download mirroring.

## Sponsor

If you find this project valuable, consider supporting the original author through [Ko-Fi](https://ko-fi.com/herbrine8403), [Afdian](https://afdian.com/a/herbrine8403), or [WeChat Reward Code](donate.png).

## Star History

<a href="https://www.star-history.com/?type=date&repos=Gsjsjzhznsz%2FAir-Minecraft-iOS-Launcher">
 <picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=Gsjsjzhznsz%2FAir-Minecraft-iOS-Launcher&type=date&theme=dark" />
  <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=Gsjsjzhznsz%2FAir-Minecraft-iOS-Launcher&type=date&legend=top-left" />
  <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=Gsjsjzhznsz%2FAir-Minecraft-iOS-Launcher&type=date&legend=top-left" />
 </picture>
</a>
