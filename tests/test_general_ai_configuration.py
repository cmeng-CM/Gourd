# Copyright (C) 2026 Gourd Contributors
# SPDX-License-Identifier: GPL-3.0-or-later
"""Offline source guards; no workflow directory, historical objects or app required."""
import hashlib
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "cd825466"
LEGACY_HASHES = {
    "DynamicIsland/managers/ScreenAssistantManager.swift": "dee7398b38c91c5586fa0e2af8544bace061e2dedd5cdda2415237788242ec76",
    "DynamicIsland/components/ScreenAssistant/ModelSelectionPanel.swift": "99ba81899ddf434ec0e969502d30bf413a1bafa96cdc199a9b9c32a7b60fec4e",
    # 2026-10-16（面板通知浮层的屏口径）：`Constants.swift` 新增一个 Defaults 键
    # `notificationHUDOnExternalDisplays`（默认 false），指纹随之更新——核对方式：
    # `git diff cd825466 -- DynamicIsland/models/Constants.swift` 只有那一处新增。
    "DynamicIsland/models/Constants.swift": "da65f78a209b993ae19fce730c115dd780b87d7699fafd86d436571125f44b2c",
}
LEGACY_SETTINGS_HASH = "9ab4b78e456086b3813897b71349da3a8a99c8aed87cabb8e9f286153210502f"
# All added/changed main-app catalog entries in cd825466..9bed9efc, not prefix filtering.
LOCALE_KEYS = (
    'The time zone is invalid.',
    'This due time cannot be preserved in its time zone. Choose another time or use all-day.',
    'This reminder writer cannot save time or metadata.',
    'ai.error.cancelled',
    'ai.error.capabilityMismatch',
    'ai.error.configurationReadFailed',
    'ai.error.configurationWriteFailed',
    'ai.error.httpStatus',
    'ai.error.invalidConfiguration',
    'ai.error.invalidEndpoint',
    'ai.error.invalidRequest',
    'ai.error.invalidResponse',
    'ai.error.missingCredential',
    'ai.error.missingDefault',
    'ai.error.profileNotFound',
    'ai.error.redirectRejected',
    'ai.error.responseTooLarge',
    'ai.error.rollbackFailed',
    'ai.error.secretDeleteFailed',
    'ai.error.secretReadFailed',
    'ai.error.secretWriteFailed',
    'ai.error.timedOut',
    'ai.error.transportFailed',
    'ai.settings.add',
    'ai.settings.apiKey',
    'ai.settings.baseURL',
    'ai.settings.cancelTest',
    'ai.settings.clearKey',
    'ai.settings.defaultText',
    'ai.settings.defaultVision',
    'ai.settings.defaults',
    'ai.settings.defaultsImmediate',
    'ai.settings.defaultsSaved',
    'ai.settings.delete',
    'ai.settings.deleted',
    'ai.settings.editor',
    'ai.settings.keepKey',
    'ai.settings.keyOptional',
    'ai.settings.modelID',
    'ai.settings.name',
    'ai.settings.none',
    'ai.settings.profiles',
    'ai.settings.protocol',
    'ai.settings.protocol.anthropic',
    'ai.settings.protocol.gemini',
    'ai.settings.protocol.ollama',
    'ai.settings.protocol.openAICompatible',
    'ai.settings.save',
    'ai.settings.saved',
    'ai.settings.screenSeparate',
    'ai.settings.test',
    'ai.settings.testExplanation',
    'ai.settings.testSucceeded',
    'ai.settings.textCapability',
    'ai.settings.title',
    'ai.settings.visionCapability',
    'ai.settings.visionDeclaration',
    'calendar.copy.fullInformation',
    'calendar.copy.meetingInformation',
    'calendar.copy.selection',
    'calendar.copy.title',
    'calendar.generation.blocked',
    'calendar.generation.confirm.date',
    'calendar.generation.confirm.time',
    'calendar.generation.error.confirmationRequired',
    'calendar.generation.error.emptySource',
    'calendar.generation.error.failed',
    'calendar.generation.error.invalidEvidence',
    'calendar.generation.error.invalidResponse',
    'calendar.generation.error.sourceTooLarge',
    'calendar.generation.generate',
    'calendar.generation.manual',
    'calendar.generation.retry',
    'calendar.generation.settings',
    'calendar.generation.source',
    'calendar.generation.state.failed',
    'calendar.generation.unconfigured',
    'calendar.meeting.actions',
    'calendar.meeting.copyCodeFormat',
    'calendar.meeting.copySource',
    'calendar.meeting.noEvidence',
    'calendar.meeting.openIn.huawei',
    'calendar.meeting.openIn.tencent',
    'calendar.meeting.provider.huawei',
    'calendar.meeting.provider.tencent',
    'calendar.meeting.row.choose',
    'calendar.meeting.row.copy',
    'calendar.meeting.row.open',
    'calendar.meeting.tooltip.copyValue',
    'calendar.meeting.tooltip.more',
    'calendar.meeting.tooltip.multiple',
    'calendar.meeting.tooltip.open',
    'calendar.panel.backToMonth',
    'calendar.panel.deleteEventConsequence',
    'calendar.panel.deleteReminderConsequence',
    'calendar.panel.sourceTimeZoneFormat',
    'calendar.panel.url',
    # docs/50（2026-10-16）：首页音乐块的封面成了「打开正在放歌的那个音乐软件」的入口，
    # 这条是该入口的 tooltip 与可访问性文案（en + zh-Hans）。
    'module.music.openPlayer',
    # 2026-10-27（docs/53 D-08）：首页通知块表头的「外接显示器」快捷开关，两态悬停说明
    # （设置页同一开关的快捷入口，键翻转同一个 notificationHUDOnExternalDisplays）。
    'module.notifications.externalDisplays.off',
    'module.notifications.externalDisplays.on',
    # 2026-10-16（通知浮层的屏口径，docs/53）：设置页「通知浮层」那一段的控件文案与段脚注。
    # 这五条（含段标题）此前**根本没有进 catalog**——整段是英文直显；本批顺手补齐 zh-Hans。
    # 段脚注原文写了「appears on every display at once」，与新口径（默认只上主屏）冲突，
    # 因此连文案一起改并双语化（旧英文串从未进过 catalog，没有留下无消费者的遗留键）。
    'Notification HUD',
    'Show notification HUD',
    'Show notification HUD on external displays',
    'Display duration',
    'Show notification body in the notch HUD',
    'Notification HUD size',
    'Notification HUD = the brief overlay shown when a new notification arrives. It reads the notification database (needs Full Disk Access) and appears in its own floating window on the main display — turn on the external-display switch to show it there too. Turn the switch off to receive notifications on the island without the overlay; body text and size are controlled below.',
)

# docs/45 → docs/47 的会议入口返工（T1–T6）删掉了「用 AI 识别会议」、行内状态文字、时间闸门
# 与「逐候选」二级菜单。那批已无消费者的会议键（recognize / choose / copyLink / menuHelp /
# tooEarly / sendingScope / opening / accepted / fallback / refused / cancelled / configure /
# recognizing / recognitionFailed / sourceTooLarge）在本轮已随 catalog 一并移出，不再出现在
# LOCALE_KEYS 里；因此下面的「必须有消费者」断言对余下的键仍然成立。
# T4（docs/48）再移出 5 条已无视图读者的生成状态键（idle / debouncing / parsing / ready /
# cancelled）及其唯一凭据 `CalendarGenerationState.labelKey`；`state.failed` 仍由失败行渲染，保留。


def legacy_settings(text):
    return text.split("struct ScreenAssistantSettings: View {", 1)[1].split(
        "\nstruct ColorPickerSettings: View {", 1)[0]


class GeneralAIConfigurationTests(unittest.TestCase):
    def test_old_screen_assistant_and_defaults_match_verified_baseline(self):
        for name, expected in LEGACY_HASHES.items():
            with self.subTest(path=name):
                self.assertEqual(hashlib.sha256((ROOT / name).read_bytes()).hexdigest(), expected)
        section = legacy_settings((ROOT / "DynamicIsland/components/Settings/SettingsView.swift").read_text())
        self.assertEqual(hashlib.sha256(section.encode()).hexdigest(), LEGACY_SETTINGS_HASH)

    def test_all_changed_app_catalog_keys_are_bilingual_and_consumed(self):
        catalog = json.loads((ROOT / "DynamicIsland/Localizable.xcstrings").read_text())["strings"]
        sources = "\n".join(p.read_text() for p in (ROOT / "DynamicIsland").rglob("*.swift"))
        for key in LOCALE_KEYS:
            with self.subTest(key=key):
                for language in ("en", "zh-Hans"):
                    unit = catalog[key]["localizations"][language]["stringUnit"]
                    self.assertEqual(unit["state"], "translated")
                    self.assertTrue(unit["value"].strip())
                # Exact literal key only: a substring match would let e.g. `calendar.meeting.open`
                # ride on `calendar.meeting.openIn.huawei` and slip through (审查 I-1).
                consumed = ('"%s"' % key) in sources
                if key.startswith("ai.settings.protocol."):
                    consumed |= '"ai.settings.protocol.\\(protocolKind.rawValue)"' in sources
                if key.startswith("calendar.generation.confirm."):
                    consumed |= '"calendar.generation.confirm.\\(rawValue)"' in sources
                self.assertTrue(consumed, "changed localization has no source consumer")

    def test_manifest_covers_actual_diff_when_history_is_available(self):
        result = subprocess.run(["git", "show", BASELINE + ":DynamicIsland/Localizable.xcstrings"],
                                cwd=ROOT, capture_output=True, text=True)
        if result.returncode:
            # Fresh/shallow clones use the checked-in manifest and verified fingerprints.
            return
        before = json.loads(result.stdout)["strings"]
        after = json.loads((ROOT / "DynamicIsland/Localizable.xcstrings").read_text())["strings"]
        changed = {key for key, value in after.items() if before.get(key) != value}
        self.assertEqual(changed, set(LOCALE_KEYS))

    def test_general_ai_configuration_keeps_secrets_out_of_encoded_profiles(self):
        text = (ROOT / "DynamicIsland/services/AI/AIConfigurationStore.swift").read_text()
        text = text.split("struct AIModelProfile:", 1)[1].split("struct AIConfiguration:", 1)[0]
        self.assertIn("secretReference", text)
        self.assertNotRegex(text, r"(?:let|var)\s+(?:apiKey|secret|password)\s*:\s*String")
        context = (ROOT / "DynamicIsland/Kernel/ModuleContext.swift").read_text()
        self.assertIn("public let ai: any AIHandle", context)


if __name__ == "__main__":
    unittest.main()
