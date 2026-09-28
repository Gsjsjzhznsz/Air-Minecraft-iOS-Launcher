#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task189 i18n 注册：
1. 157 个 MultiplayerViewController MPLocalized 键（zh 值取自源码，变体键取
   通用表述）注册进 en / zh-Hans / zh-CN / zh-Hant 四份 Localizable.strings；
2. 28 个 ame189.* 新键（本轮迁移的散点硬编码）同批注册；
3. zh-Hant 由简转繁映射生成（覆盖本轮全部 366 个用字）。
运行后四份 .strings 追加条目（幂等：已存在的键跳过）。
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(REPO, "Natives", "resources")

# ---------------------------------------------------------------------------
# 1) mp.* 键表（zh = 源码 fallback；en = Task189 翻译；变体键取通用表述）
# ---------------------------------------------------------------------------
MP = {
    "common.cancel": ("取消", "Cancel"),
    "common.ok": ("好", "OK"),
    "common.save": ("保存", "Save"),
    "mp.close": ("关闭", "Close"),
    "mp.connect.failed": ("连接失败", "Connection Failed"),
    "mp.connect.failed_msg": ("无法连接到 ZeroTier 网络，请检查 Network ID 是否正确以及网络是否畅通。",
                              "Could not connect to the ZeroTier network. Check that the Network ID is correct and the network is reachable."),
    "mp.connect.port_forward_failed_msg": ("端口转发器启动失败，无法连接到房主。请尝试断开重连。",
                                            "The port forwarder failed to start, so the host cannot be reached. Try disconnecting and reconnecting."),
    "mp.core.unavailable_msg": ("ZeroTier 联机核心未加载，无法启用联机。请使用包含真实 zt.framework 的构建版本。",
                                 "The ZeroTier multiplayer core is not loaded. Please use a build that includes the real zt.framework."),
    "mp.core.unavailable_title": ("联机核心不可用", "Multiplayer Core Unavailable"),
    "mp.direct.error.ip_empty": ("请输入服务器 IP 地址", "Enter a server IP address"),
    "mp.direct.error.ip_invalid": ("IP 地址格式不正确，请检查输入", "Invalid IP address format. Check your input."),
    "mp.direct.error.no_profile": ("未找到当前 profile，请先选择一个游戏配置", "No profile found. Select a game profile first."),
    "mp.direct.error_title": ("提示", "Notice"),
    "mp.direct.ip_placeholder": ("服务器 IP", "Server IP"),
    "mp.direct.join_button": ("加入游戏", "Join Game"),
    "mp.direct.success_msg_prefix": ("已添加服务器", "Server added"),
    "mp.direct.success_title": ("已添加服务器", "Server Added"),
    "mp.guest.code_placeholder": ("在此粘贴分享代码", "Paste the share code here"),
    "mp.guest.connected_msg": ("已连接到房主的联机网络", "Connected to the host's multiplayer network"),
    "mp.guest.connected_title": ("已加入联机", "Joined Multiplayer"),
    "mp.guest.connecting_msg": ("正在连接到房主的 ZeroTier 网络，请稍候...", "Connecting to the host's ZeroTier network, please wait..."),
    "mp.guest.connecting_title": ("正在加入联机", "Joining Multiplayer"),
    "mp.guest.error.empty": ("请输入房主提供的分享代码", "Enter the share code provided by the host"),
    "mp.guest.error.invalid_code": ("无法解析分享代码，请确认代码完整无误", "Could not parse the share code. Make sure it is complete."),
    "mp.guest.error.invalid_network_id": ("分享代码中的 Network ID 无效", "The Network ID in the share code is invalid"),
    "mp.guest.error_title": ("代码无效", "Invalid Input"),
    "mp.guest.input_msg": ("请输入房主提供的分享代码", "Enter the share code provided by the host"),
    "mp.guest.input_title": ("输入分享代码", "Enter Share Code"),
    "mp.guest.join_button": ("加入", "Join"),
    "mp.guest.server_address": ("服务器地址", "Server Address"),
    "mp.guest.tip.add_server": ("请在 MC 多人游戏界面点击「添加服务器」，粘贴以下地址即可加入",
                                 "In the Minecraft Multiplayer screen, tap \"Add Server\" and paste this address to join"),
    "mp.guest.tip.address_copied": ("服务器地址已自动复制到剪贴板，直接粘贴即可",
                                     "The server address has been copied to the clipboard — just paste it"),
    "mp.guest.tip.auto_saved": ("地址已自动保存到当前配置，下次启动游戏会自动连接",
                                 "The address was saved to the current profile; the game will connect automatically next launch"),
    "mp.guide.fast_step1_desc": ("在本页面点击「预设 Network ID」行", "On this page, tap the \"Preset Network ID\" row"),
    "mp.guide.fast_step1_title": ("点击「预设 Network ID」", "Tap \"Preset Network ID\""),
    "mp.guide.fast_step2_desc": ("点击「使用快速模式（无需注册）」按钮，系统自动生成 Network ID",
                                  "Tap \"Use Quick Mode (no sign-up)\" and a Network ID will be generated automatically"),
    "mp.guide.fast_step2_title": ("选择快速模式", "Choose Quick Mode"),
    "mp.guide.fast_step3_desc": ("启动游戏后在悬浮球中打开联机界面，选择「当房主」即可开房",
                                  "Launch the game, open the multiplayer panel from the floating ball, and pick \"Host\" to open a room"),
    "mp.guide.fast_step3_title": ("开始联机", "Start Playing"),
    "mp.guide.intro": ("ZeroTier 提供两种联机模式，根据需求选择：", "ZeroTier offers two multiplayer modes. Pick the one you need:"),
    "mp.guide.mode_fast": ("快速模式", "Quick Mode"),
    "mp.guide.mode_fast_desc": ("使用 Ad-hoc 网络自动生成 Network ID，无需注册账号。但只有 IPv6 地址、公开网络安全性弱、IP 可能变化。",
                                 "Generates a Network ID automatically via an ad-hoc network — no account needed. IPv6-only, on a public network with weaker security; the IP may change."),
    "mp.guide.mode_standard": ("标准模式", "Standard Mode"),
    "mp.guide.mode_standard_desc": ("在 central.zerotier.com 注册账号并创建组织，获得固定的 Network ID。IP 稳定、支持授权管理、每人独立网络。",
                                     "Register an account at central.zerotier.com and create an organization to get a fixed Network ID. Stable IP, access control, and a private network per person."),
    "mp.guide.note": ("注意：房主和房客使用相同的 Network ID 才能联机。标准模式需在后台授权成员（Private）或设为 Public。快速模式所有人共享同一公开网络。",
                       "Note: host and guests must use the same Network ID. In Standard mode, authorize members in the dashboard (Private) or set the network to Public. Quick mode shares one public network for everyone."),
    "mp.guide.open_website": ("打开 central.zerotier.com（标准模式）", "Open central.zerotier.com (Standard mode)"),
    "mp.guide.stable": ("稳定", "Stable"),
    "mp.guide.step1_desc": ("访问 central.zerotier.com（新版 Central），注册并登录账号（免费，支持 Google/GitHub/Microsoft 登录）",
                             "Go to central.zerotier.com (the new Central), register and sign in (free; Google/GitHub/Microsoft sign-in supported)"),
    "mp.guide.step1_title": ("注册 ZeroTier 账号", "Register a ZeroTier Account"),
    "mp.guide.step2_desc": ("登录后输入组织名称，点击「Create Organization」。免费套餐自带一个 Network Group 和一个 Network",
                             "After signing in, enter an organization name and tap \"Create Organization\". The free plan includes one Network Group and one Network"),
    "mp.guide.step2_title": ("创建组织", "Create an Organization"),
    "mp.guide.step3_desc": ("在左侧边栏展开「Networks」，点击默认网络（如 my-first-network），复制顶部的 16 位 Network ID",
                             "Expand \"Networks\" in the left sidebar, click the default network (e.g. my-first-network), and copy the 16-character Network ID at the top"),
    "mp.guide.step3_title": ("获取 Network ID", "Get the Network ID"),
    "mp.guide.step4_desc": ("Private（推荐）：需手动授权成员更安全；Public：任何人可直接加入",
                             "Private (recommended): safer, members must be authorized manually; Public: anyone can join directly"),
    "mp.guide.step4_title": ("设置网络访问控制", "Set Network Access Control"),
    "mp.guide.step5_desc": ("回到本页面，点击「预设 Network ID」行，粘贴并保存",
                             "Come back to this page, tap the \"Preset Network ID\" row, then paste and save"),
    "mp.guide.step5_title": ("填入启动器", "Fill It into the Launcher"),
    "mp.guide.step6_desc": ("房客加入后在「Member Devices」标签点击三点菜单→「Authorize」授权（Private 模式需要，Public 模式跳过）",
                             "After a guest joins, open the \"Member Devices\" tab, tap the three-dot menu and choose \"Authorize\" (needed for Private mode; skip for Public)"),
    "mp.guide.step6_title": ("授权房客设备", "Authorize Guest Devices"),
    "mp.guide.step7_desc": ("启动游戏后在悬浮球中打开联机界面，选择「当房主」即可开房",
                             "Launch the game, open the multiplayer panel from the floating ball, and pick \"Host\" to open a room"),
    "mp.guide.step7_title": ("开始联机", "Start Playing"),
    "mp.guide.title": ("ZeroTier 联机教程", "ZeroTier Multiplayer Guide"),
    "mp.guide.unstable": ("不稳定", "Unstable"),
    "mp.guide.use_fast_mode": ("使用快速模式", "Use Quick Mode"),
    "mp.host.connected_msg": ("已连接到联机网络，请在 MC 中开放局域网后输入端口号",
                               "Connected to the multiplayer network. Open the world to LAN in Minecraft, then enter the port"),
    "mp.host.connected_title": ("联机已开启", "Multiplayer Started"),
    "mp.host.connecting_msg": ("正在连接到 ZeroTier 网络，请稍候...", "Connecting to the ZeroTier network, please wait..."),
    "mp.host.connecting_title": ("正在开启联机", "Starting Multiplayer"),
    "mp.host.copy_code": ("复制代码", "Copy Code"),
    "mp.host.default_room_name": ("我的联机房间", "My Multiplayer Room"),
    "mp.host.generate_code": ("生成分享代码", "Generate Share Code"),
    "mp.host.ip_changed_msg": ("你的 ZeroTier IP 已变化，之前分享的旧代码已失效。请将新的分享代码重新发给房客。",
                                "Your ZeroTier IP has changed and the previously shared code is no longer valid. Send the new share code to your guests."),
    "mp.host.ip_changed_title": ("房主 IP 已变化", "Host IP Changed"),
    "mp.host.local_ip": ("本机 IP", "Local IP"),
    "mp.host.no_local_ip": ("无法获取本机 ZeroTier IP，请检查网络连接后重试",
                             "Could not get the local ZeroTier IP. Check the network connection and retry"),
    "mp.host.no_network_id_msg": ("房主需要先设置预设 ZeroTier Network ID。请在启动器联机界面中设置后再来。",
                                   "The host must set a preset ZeroTier Network ID first. Set it in the launcher's multiplayer screen and come back."),
    "mp.host.no_network_id_title": ("未设置 Network ID", "Network ID Not Set"),
    "mp.host.port_empty_msg": ("请输入 LAN 端口号", "Enter the LAN port number"),
    "mp.host.port_empty_title": ("端口为空", "Port Empty"),
    "mp.host.port_invalid_msg": ("端口号必须在 1-65535 之间", "The port must be between 1 and 65535"),
    "mp.host.port_invalid_title": ("端口无效", "Invalid Port"),
    "mp.host.port_placeholder": ("端口号（如 54321）", "Port (e.g. 54321)"),
    "mp.host.server_address": ("服务器地址", "Server Address"),
    "mp.host.share_button": ("分享...", "Share..."),
    "mp.host.share_code_failed": ("生成分享代码失败", "Failed to Generate Share Code"),
    "mp.host.share_code_ready": ("分享代码已生成！将以下代码发给房客：", "Share code ready! Send the following code to your guests:"),
    "mp.host.share_code_title": ("分享代码已生成", "Share Code Generated"),
    "mp.host.tip.copy_or_share": ("可点击下方按钮复制或分享代码", "Use the buttons below to copy or share the code"),
    "mp.host.tip.create_world": ("请在 MC 中创建世界并点击「对局域网开放」",
                                  "Create a world in Minecraft and use \"Open to LAN\""),
    "mp.host.tip.manual_port": ("开放局域网后，MC 会在聊天框显示端口号，请将其输入下方",
                                 "After opening to LAN, Minecraft shows the port in chat — enter it below"),
    "mp.host.tip.wait_guest": ("房客输入此代码即可加入你的联机网络", "Guests enter this code to join your multiplayer network"),
    "mp.ingame.guest_desc": ("输入分享代码，加入房主的联机网络", "Enter a share code to join the host's multiplayer network"),
    "mp.ingame.guest_title": ("当房客", "Be a Guest"),
    "mp.ingame.host_desc": ("创建联机房间，开放局域网后生成分享代码", "Create a multiplayer room and generate a share code after opening to LAN"),
    "mp.ingame.host_title": ("当房主", "Be the Host"),
    "mp.ingame.section.role": ("选择角色", "Choose a Role"),
    "mp.ingame.section.role_footer": ("房主需在 MC 中开放局域网，房客输入分享代码即可加入",
                                       "The host opens the world to LAN in Minecraft; guests join with the share code"),
    "mp.ingame.section.status": ("联机状态", "Multiplayer Status"),
    "mp.ingame.section.status_footer": ("显示当前联机网络的状态信息", "Shows the current multiplayer network status"),
    "mp.ingame.status.connected": ("已连接", "Connected"),
    "mp.ingame.status.disconnected": ("未连接", "Disconnected"),
    "mp.ingame.status.guest_mode": ("房客模式", "Guest Mode"),
    "mp.ingame.status.host_mode": ("房主模式", "Host Mode"),
    "mp.ingame.status.idle": ("未开始", "Not Started"),
    "mp.ingame.status.local_ip": ("本地 IP", "Local IP"),
    "mp.ingame.status.network_id": ("Network ID", "Network ID"),
    "mp.ingame.status.server_address": ("服务器地址", "Server Address"),
    "mp.ingame.status.share_code": ("分享代码", "Share Code"),
    "mp.network_id.adhoc_failed_msg": ("无法生成快速模式 Network ID，请改用标准模式",
                                         "Could not generate a Quick Mode Network ID. Use Standard mode instead"),
    "mp.network_id.adhoc_failed_title": ("生成失败", "Generation Failed"),
    "mp.network_id.adhoc_success_msg": ("已自动生成 Network ID，无需注册账号即可联机。注意：快速模式稳定性不如标准模式，IP 可能变化。",
                                          "A Network ID was generated automatically — no account needed. Note: Quick Mode is less stable than Standard Mode and the IP may change."),
    "mp.network_id.adhoc_success_title": ("已启用快速模式", "Quick Mode Enabled"),
    "mp.network_id.invalid_msg": ("Network ID 应为 16 位十六进制字符串", "The Network ID must be a 16-character hexadecimal string"),
    "mp.network_id.invalid_title": ("Network ID 格式不正确", "Invalid Network ID"),
    "mp.network_id.message": ("在 central.zerotier.com 创建网络后填入 16 位 Network ID，开房时自动使用",
                               "Create a network at central.zerotier.com, then enter the 16-character Network ID here. It is used automatically when hosting"),
    "mp.network_id.placeholder": ("16 位十六进制 Network ID", "16-character hex Network ID"),
    "mp.network_id.title": ("设置 Network ID", "Set Network ID"),
    "mp.network_id.use_adhoc": ("使用快速模式（无需注册）", "Use Quick Mode (no sign-up)"),
    "mp.node.start_failed_msg": ("ZeroTier 节点启动失败，请重试。", "The ZeroTier node failed to start. Please retry."),
    "mp.node.start_failed_title": ("启动失败", "Start Failed"),
    "mp.room.action.connect": ("连接房间", "Connect Room"),
    "mp.room.action.delete": ("删除房间", "Delete Room"),
    "mp.room.action.disconnect": ("断开连接", "Disconnect"),
    "mp.room.action.share": ("分享房间", "Share Room"),
    "mp.room.button.connect": ("连接", "Connect"),
    "mp.room.button.connecting": ("连接中", "Connecting"),
    "mp.room.button.disconnect": ("断开", "Disconnect"),
    "mp.room.delete.button": ("删除", "Delete"),
    "mp.room.delete.confirm_prefix": ("确定要删除房间", "Are you sure you want to delete the room"),
    "mp.room.delete.confirm_title": ("确认删除", "Confirm Deletion"),
    "mp.room.delete.confirm_warning": ("此操作无法撤销。", "This action cannot be undone."),
    "mp.room.network_id": ("Network ID", "Network ID"),
    "mp.room.server_address": ("服务器地址", "Server Address"),
    "mp.room.status.connected": ("已连接", "Connected"),
    "mp.room.status.connecting": ("连接中", "Connecting"),
    "mp.room.status.disconnected": ("未连接", "Disconnected"),
    "mp.room.status.error": ("错误", "Error"),
    "mp.room.unnamed": ("未命名房间", "Unnamed Room"),
    "mp.rooms.empty": ("暂无房间（房间仅在本次会话中保留）", "No rooms yet (rooms are kept for this session only)"),
    "mp.rooms.empty_msg": ("请先在 Section 0 设置 Network ID，然后在游戏内模式中选择当房主或房客",
                            "Set the Network ID first, then choose Host or Guest in the in-game multiplayer panel"),
    "mp.rooms.empty_title": ("暂无房间", "No Rooms"),
    "mp.section.direct": ("直连", "Direct Connect"),
    "mp.section.direct_footer": ("输入服务器 IP 和端口，写入当前 profile，启动游戏后自动加入",
                                  "Enter the server IP and port; it is saved to the current profile and joined automatically on launch"),
    "mp.section.rooms": ("我的房间", "My Rooms"),
    "mp.section.settings": ("联机设置", "Multiplayer Settings"),
    "mp.section.settings_footer": ("启用联机后可设置 Network ID，房主开房时自动使用",
                                    "After enabling multiplayer you can set the Network ID used automatically when hosting"),
    "mp.settings.enable_multiplayer": ("启用联机", "Enable Multiplayer"),
    "mp.settings.node_offline": ("节点未启动", "Node Not Running"),
    "mp.settings.node_online": ("节点已上线", "Node Online"),
    "mp.settings.node_starting": ("节点启动中...", "Node starting..."),
    "mp.settings.not_set": ("未设置", "Not Set"),
    "mp.settings.preset_network_id": ("预设 Network ID", "Preset Network ID"),
    "mp.settings.zt_guide": ("ZeroTier 网络创建教程", "ZeroTier Network Setup Guide"),
    "mp.settings.zt_guide_desc": ("不知道怎么创建网络？点这里", "Don't know how to create a network? Tap here"),
    "mp.sharecode.invalid": ("分享代码无效", "Invalid share code"),
    "mp.sharecode.missing_host": ("分享代码缺少房主 IP，请确认代码完整无误", "The share code is missing the host IP. Make sure it is complete."),
    "mp.unknown": ("未知", "Unknown"),
}

# ---------------------------------------------------------------------------
# 2) ame189.* 新键（本轮散点迁移）
# ---------------------------------------------------------------------------
AME = {
    "download.tab.controls": ("控件", "Controls"),
    "ame189.common.unknown": ("未知", "Unknown"),
    "ame189.common.unknown_device": ("未知设备", "Unknown device"),
    "ame189.common.on": ("已开启", "On"),
    "ame189.common.off": ("未开启", "Off"),
    "ame189.rp.launcher_version": ("启动器版本", "Launcher Version"),
    "ame189.rp.game_version": ("游戏版本", "Game Version"),
    "ame189.rp.device": ("设备", "Device"),
    "ame189.rp.system": ("系统", "System"),
    "ame189.rp.mem_limit": ("扩展内存限制", "Increased Memory Limit"),
    "ame189.rp.ext_vm": ("扩展虚拟内存", "Extended Virtual Memory"),
    "ame189.rp.jit_attached": ("已启用（启动时附加）", "Enabled (attached at launch)"),
    "ame189.rp.not_selected": ("未选择", "Not Selected"),
    "ame189.jit.timeout_msg": ("JIT 开启等待超时（120 秒）。请确认 JIT 工具（StikDebug 等）已安装并可正常拉起后选择重试；也可在设置中选择其它 JIT 开启方式。",
                                "Timed out waiting for JIT (120s). Make sure your JIT enabler app (StikDebug etc.) is installed and can be launched, then retry — or choose a different JIT enabler in Settings."),
    "ame189.jit.retry": ("重试", "Retry"),
    "ame189.ai.safety_mode_title": ("默认安全模式", "Default Safety Mode"),
    "ame189.ai.safety_safe": ("只读自动执行（Safe）", "Read-only auto-run (Safe)"),
    "ame189.ai.safety_ask": ("写操作逐次确认（Ask）", "Confirm each write (Ask)"),
    "ame189.ai.safety_yolo": ("自动批准（YOLO）", "Auto-approve (YOLO)"),
    "ame189.uikit.account_repair_msg": ("账号凭据已丢失（更换安装方式/恢复备份后常见）。\n\n点击「删除账号并重新登录」将移除「%@」并直接打开登录页面，登录后即可恢复正版皮肤与联机功能。",
                                          "Account tokens are missing from the keychain (common after changing install methods or restoring a backup).\n\nTap \"Remove account and sign in again\" to remove \"%@\" and open the sign-in page. Signing in restores skins and multiplayer."),
    "ame189.uikit.restart_title": ("需要重启启动器", "Launcher Restart Required"),
    "ame189.uikit.restart_msg": ("Forge 安装器占用了本次会话的 Java 运行时（进程内只能创建一次 JVM）。\n\n点击「重启并启动」后启动器将退出，重新打开后将自动启动「%@」并完成 JIT 授权。",
                                   "The mod installer used this session's Java runtime (only one JVM per process).\n\nTap \"Restart & Launch\" to quit. When you reopen the launcher, \"%@\" will auto-launch with JIT authorization."),
    "ame189.uikit.restart_button": ("重启并启动", "Restart & Launch"),
    "ame189.utils.mem_clamped": ("内存 %dMB 超过设备安全上限，已降至 %dMB",
                                  "Memory %dMB exceeds the device limit; clamped to %dMB"),
    "ame189.jl.missing_header": ("该整合包导入时缺失 %lu 个文件（下载失败 %lu / 被跳过 %lu），游戏可能因此崩溃或功能异常。\n\n",
                                  "This modpack import is missing %lu files (%lu failed / %lu skipped). The game may crash or misbehave.\n\n"),
    "ame189.jl.missing_more": ("  ……等共 %lu 个\n", "  ...%lu in total\n"),
    "ame189.jl.missing_footer": ("建议：删除该实例并重新导入（可换个下载源），或在 Mod 管理器中补齐缺失文件。\n本次将照常启动，此提醒只显示一次。",
                                  "Tip: delete this instance and re-import it (optionally with a different download source), or complete the missing files in the mod manager.\nThe game will launch anyway; this reminder shows only once."),
    "ame189.svc.ltw_unsupported": ("LTW 渲染器不支持 MC %@：\n\n26.x 的云渲染管线需要纹理缓冲（samplerBuffer），而 LTW 在 iOS 上的 ES 3.0 后端无法提供，启动后必崩在标题界面。\n\n请到 设置 → 视频设置 → 渲染器 切换到 Zink 或 MobileGlues 后重试。LTW 仍可用于 1.21.x 及更早版本。",
                                    "The LTW renderer does not support MC %@:\n\n26.x's cloud rendering pipeline needs texture buffers (samplerBuffer), which LTW's ES 3.0 backend on iOS cannot provide — it always crashes at the title screen.\n\nSwitch to Zink or MobileGlues in Settings → Video → Renderer and retry. LTW still works for 1.21.x and earlier."),
}

# ---------------------------------------------------------------------------
# 3) 简→繁映射（覆盖本轮全部用字；未列出的字符原样保留）
# ---------------------------------------------------------------------------
S2T = str.maketrans(
    "丢两个为么云仅会关内册写冲准凭击侧创删务动单占发变台号后启员命对导将尝带并应开异式当录态悬戏执扩拟择据换构标栏检模点状独畅留码确种称稳符签组织给络统缓网联肤节荐获虚补装见视认议设访试话该误请读败账贴费转载输边过运这进连选销错闭问间须预频题页顶齐机权来里粘"
    "无旧时显",
    "丟兩個為麼雲僅會關內冊寫衝準憑擊側創刪務動單佔發變臺號後啟員命對導將嘗帶並應開異式當錄態懸戲執擴擬擇據換構標欄檢模點狀獨暢留碼確種稱穩符簽組織給絡統緩網聯膚節薦獲虛補裝見視認議設訪試話該誤請讀敗賬貼費轉載輸邊過運這進連選銷錯閉問間須預頻題頁頂齊機權來裡黏"
    "無舊時顯")


def esc(v):
    return v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def register(path, table):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    existing = set(re.findall(r'^"([^"]+)"\s*=', content, re.M))
    added = skipped = 0
    lines = []
    for key in sorted(table):
        if key in existing:
            skipped += 1
            continue
        lines.append('"%s" = "%s";' % (key, esc(table[key])))
        added += 1
    if lines:
        if not content.endswith("\n"):
            content += "\n"
        content += "\n/* Task189 i18n registration (%d keys) */\n" % added + "\n".join(lines) + "\n"
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
    print("%s: +%d (skipped %d existing)" % (os.path.relpath(path, REPO), added, skipped))


def main():
    full = {}
    full.update(MP)
    full.update(AME)
    zh_hans = {k: v[0] for k, v in full.items()}
    en = {k: v[1] for k, v in full.items()}
    zh_hant = {k: v[0].translate(S2T) for k, v in full.items()}

    # 一致性：值不得含未转义引号（esc 处理）；键不重复
    assert len(full) == len(zh_hans) == len(en)
    register(os.path.join(RES, "en.lproj", "Localizable.strings"), en)
    register(os.path.join(RES, "zh-Hans.lproj", "Localizable.strings"), zh_hans)
    register(os.path.join(RES, "zh-CN.lproj", "Localizable.strings"), zh_hans)
    register(os.path.join(RES, "zh-Hant.lproj", "Localizable.strings"), zh_hant)
    print("total keys: %d (mp=%d ame=%d)" % (len(full), len(MP), len(AME)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
