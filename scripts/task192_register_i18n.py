#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Task192 i18n 注册（AI 界面批次）：76 键 × 4 语言（en/zh-Hans/zh-CN/zh-Hant）。
覆盖 AIViewController / AiSafetyManager / AIProviderConfigViewController /
AISessionListViewController 的用户可见硬编码中文。工具描述类字符串
（AiFileTools 等，LLM 提示词）留待下轮。
幂等：已存在的键跳过。"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(REPO, "Natives", "resources")

K = {
    # --- AIViewController ---
    "ame192.ai.title": ("AI 助手", "AI Assistant"),
    "ame192.ai.configure_button": ("去配置", "Set Up"),
    "ame192.ai.default_model": ("默认模型", "Default model"),
    "ame192.ai.no_provider": ("未配置 AI 提供商", "No AI provider configured"),
    "ame192.ai.no_provider_title": ("尚未配置 AI 提供商", "No AI Provider Configured"),
    "ame192.ai.no_provider_msg": ("请在设置 → AI 助手 中配置 API 服务。", "Configure an API provider in Settings → AI Assistant."),
    "ame192.ai.no_provider_hint": ("请到 设置 → AI 助手 配置 API 服务", "Go to Settings → AI Assistant to configure an API provider"),
    "ame192.ai.ok": ("好", "OK"),
    "ame192.ai.placeholder_greeting": ("和 AI 助手打个招呼吧", "Say hi to your AI assistant"),
    "ame192.ai.placeholder_sub": ("向 Prisma 询问启动器问题或 Minecraft 知识", "Ask about the launcher or anything Minecraft"),
    "ame192.ai.request_failed": ("请求失败", "Request Failed"),
    "ame192.ai.unknown_error": ("未知错误", "Unknown error"),
    # --- AiSafetyManager ---
    "ame192.ai.confirm_title": ("AI 操作确认", "Confirm AI Action"),
    "ame192.ai.run_anyway": ("仍要执行", "Run Anyway"),
    "ame192.ai.allow": ("允许", "Allow"),
    "ame192.ai.safety_changed": ("安全模式已更改", "Safety mode changed"),
    "ame192.ai.got_it": ("知道了", "Got It"),
    "ame192.ai.op_readonly": ("只读操作", "Read-only operation"),
    "ame192.ai.op_controlled_write": ("受控写入", "Controlled write"),
    "ame192.ai.op_dangerous_write": ("危险写入", "Dangerous write"),
    "ame192.ai.op_network": ("网络访问", "Network access"),
    "ame192.ai.op_unknown": ("未知操作", "Unknown operation"),
    "ame192.ai.mode_safe_desc": ("安全（Safe）\\n\\n仅允许执行只读操作，会修改或删除文件等操作将被拒绝。\\n适合日常使用，最大限度地保护你的数据。",
        "Safe\\n\\nOnly read-only operations are allowed; anything that modifies or deletes files is rejected.\\nBest for daily use, with maximum protection for your data."),
    "ame192.ai.mode_ask_desc": ("询问（Ask）\\n\\n写操作与网络请求在执行前会弹出确认框，由你逐个决定是否放行。\\n兼顾安全与便利的推荐模式。",
        "Ask\\n\\nWrites and network requests show a confirmation prompt before running, so you decide case by case.\\nThe recommended balance of safety and convenience."),
    "ame192.ai.mode_yolo_desc": ("完全（YOLO）\\n\\n写操作与网络请求不再询问，直接执行。\\n适合完全信任 AI 的场景，谨慎使用！",
        "YOLO\\n\\nWrites and network requests run immediately without asking.\\nFor when you fully trust the AI — use with caution!"),
    "ame192.ai.mode_unknown": ("未知模式", "Unknown mode"),
    # --- AIProviderConfigViewController ---
    "ame192.ai.pc.title": ("提供商配置", "Provider Settings"),
    "ame192.ai.pc.intro": ("支持 OpenAI / DeepSeek / Kimi / GLM / Ollama 等任意 OpenAI 兼容服务。",
        "Works with any OpenAI-compatible service: OpenAI, DeepSeek, Kimi, GLM, Ollama and more."),
    "ame192.ai.pc.add": ("＋ 新增提供商", "+ Add Provider"),
    "ame192.ai.pc.unnamed": ("未命名提供商", "Untitled provider"),
    "ame192.ai.pc.no_model": ("未设置模型", "No model set"),
    "ame192.ai.pc.no_url": ("未设置 Base URL", "No base URL set"),
    "ame192.ai.pc.delete": ("删除", "Delete"),
    "ame192.ai.pc.edit_title": ("编辑提供商", "Edit Provider"),
    "ame192.ai.pc.new_title": ("新增提供商", "New Provider"),
    "ame192.ai.pc.save": ("保存", "Save"),
    "ame192.ai.pc.name_ph": ("例如 DeepSeek / OpenAI / Ollama", "e.g. DeepSeek / OpenAI / Ollama"),
    "ame192.ai.pc.model_ph": ("例如 deepseek-chat", "e.g. deepseek-chat"),
    "ame192.ai.pc.temp_ph": ("留空使用默认 4096", "Leave empty for the default 4096"),
    "ame192.ai.pc.ctx_ph": ("留空使用默认 8192", "Leave empty for the default 8192"),
    "ame192.ai.pc.key_saved": ("已保存（重新输入以修改）", "Saved — type again to change"),
    "ame192.ai.pc.section_conn": ("连接信息", "Connection"),
    "ame192.ai.pc.section_params": ("参数", "Parameters"),
    "ame192.ai.pc.name": ("名称", "Name"),
    "ame192.ai.pc.model": ("模型", "Model"),
    "ame192.ai.pc.temperature": ("温度", "Temperature"),
    "ame192.ai.pc.max_tokens": ("最大 Token 上限", "Max Tokens"),
    "ame192.ai.pc.context_window": ("上下文窗口", "Context Window"),
    "ame192.ai.pc.test": ("测试连接", "Test Connection"),
    "ame192.ai.pc.test_desc": ("测试连接会向此提供商发送一条极短的 \\\"ping\\\" 请求以验证可用性。",
        "Test Connection sends a very short \\\"ping\\\" request to this provider to verify it works."),
    "ame192.ai.pc.notice": ("提示", "Notice"),
    "ame192.ai.pc.need_name": ("请填写提供商名称", "Please enter a provider name"),
    "ame192.ai.pc.need_url": ("请填写 Base URL", "Please enter the base URL"),
    "ame192.ai.pc.need_model": ("请填写模型名称", "Please enter a model name"),
    # --- AISessionListViewController ---
    "ame192.ai.sl.title": ("会话列表", "Chats"),
    "ame192.ai.sl.empty_new": ("还没有会话，点左上角 + 新建", "No chats yet — tap + in the top-left to start one"),
    "ame192.ai.sl.empty_search": ("没有匹配的会话", "No matching chats"),
    "ame192.ai.sl.empty": ("还没有会话", "No chats yet"),
    "ame192.ai.sl.just_now": ("刚刚", "Just now"),
    "ame192.ai.sl.min_ago": ("%ld 分钟前", "%ld min ago"),
    "ame192.ai.sl.hour_ago": ("%ld 小时前", "%ld h ago"),
    "ame192.ai.sl.day_ago": ("%ld 天前", "%ld d ago"),
    "ame192.ai.sl.new_chat": ("新会话", "New Chat"),
    "ame192.ai.sl.msg_count": ("%lu 条消息 · %@", "%lu messages · %@"),
    "ame192.ai.sl.delete": ("删除", "Delete"),
}

try:
    from opencc import OpenCC
    _cc = OpenCC("s2t")
    def s2t(s):
        return _cc.convert(s)
except Exception:
    def s2t(s):
        return s  # opencc 不可用时 zh-Hant 退化为简体（localize 链兜底 en）


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
        content += "\n/* Task192 i18n registration (AI surfaces, %d keys) */\n" % added + "\n".join(lines) + "\n"
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
    print("%s: +%d (skipped %d existing)" % (os.path.relpath(path, REPO), added, skipped))


def main():
    zh_hans = {k: v[0] for k, v in K.items()}
    en = {k: v[1] for k, v in K.items()}
    zh_hant = {k: s2t(v[0]) for k, v in K.items()}
    assert len(K) == len(zh_hans) == len(en) == len(zh_hant), "键数不一致"
    register(os.path.join(RES, "en.lproj", "Localizable.strings"), en)
    register(os.path.join(RES, "zh-Hans.lproj", "Localizable.strings"), zh_hans)
    register(os.path.join(RES, "zh-CN.lproj", "Localizable.strings"), zh_hans)
    register(os.path.join(RES, "zh-Hant.lproj", "Localizable.strings"), zh_hant)
    print("total keys: %d" % len(K))
    return 0


if __name__ == "__main__":
    sys.exit(main())
