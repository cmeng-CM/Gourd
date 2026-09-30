// Modified for Gourd (2026-10-01)
// Copyright (C) 2026 Gourd Contributors
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
//

//
//  PanelLayoutDefaultsTests.swift
//  Gourd 外观页 · 「恢复默认」的键清单与重置动作（p5-home-blocks / T8）
//
//  覆盖 docs/29-home-blocks-and-panel.md §做法 机制七 / §接口与数据形状 与 D-13：
//
//  **清单本身**
//  - `PanelLayoutDefaults.resetKeys` **逐字**等于文档那一行（17 个键、无重复）；顺序不判（清单是集合）；
//  - 文档**明确不在清单里**的键（功能入口类三条 + 内容 / 授权类）一个都不许在里面——名字级护栏；
//  - 行为级护栏：把清单外的键写成非默认值，重置之后**仍是那个非默认值**（名字级护栏挡不住
//    「先删一点、再抄一份」这类改法）。
//
//  **重置动作**（D-13 的核心口径）
//  - **删掉，不是写默认值**：重置后每个键在**持久域**里都不存在（`persistedDomain`，不是
//    `object(forKey:)`——后者被注册域污染，答不出「盘上有没有」）；`Defaults[...]` 读回来是出厂默认；
//  - 不碰持久域以外的东西：模块配置在 `com.cmeng.gourd.module.<shortID>` 自己的 suite 里
//    （`ManifestConfigHandle`），本清单够不着——快捷指令清单与缓存因此天然安全；
//  - 重置会被**既有的**订阅链看到（`Defaults.publisher`，KVO）：面板尺寸 / tab 名单的重算不用
//    另开第二条通知链（`removeObject` 逐键发变化）。
//
//  **外观页那条联动**（T8 的界面口径，能判的那部分）
//  - `expandHeightSliderEnabled(heightMode:)`：展开高度滑块（Notch Height 组）只在手动档可用，
//    自适应 / 未知档禁用——它写的 `openNotchHeight` 在自适应档被内容高取代（「拖了没用」，
//    与右下角把手 `showsPanelResizeHandle` 同一条先例）；
//  - 新增的五条文案 key 在 **en 与 zh-Hans** 两份里都解析得出（语言锁定的查法见
//    `TakeoverEnablementTests.XCTAssertResolves` 的说明：跟着机器语言查会红）。
//
//  **脚本取证**（`testResetWritesTheThreeScriptExports`，证据目录不在时自动跳过）
//  - 三份 `defaults export`：改乱前（= 刚重置过的干净起点）/ 改乱后 / 重置后；逐键比对在
//    `.workflow/p5-home-blocks/evidence/t8-reset-evidence.sh`（人可读的表）——本用例只负责
//    按顺序产出三份文件并断言过程本身（改乱确实落进导出、重置确实删净、清单外确实没动）。
//
//  **偏好卫生**：用例会动 17 个键 + 几个清单外对照键，一律按 `TakeoverEnablementTests` 的
//  同一套快照 / 逐字还原（原本有键写回原值、原本没键删键）在 `defer` 里还原。
//

import Defaults
import XCTest

@testable import Gourd

@MainActor
final class PanelLayoutDefaultsTests: XCTestCase {

    // MARK: - 文档清单（期望值，逐字抄自 §接口与数据形状）

    /// 「恢复默认」重置的键（唯一清单）——**这是契约**：`PanelLayoutDefaults.resetKeys` 与它不等就是红。
    private static let documentedResetKeys: [String] = [
        "openNotchWidth",
        "openNotchHeight",
        "panelHeightMode",
        "homeBlockOrder",
        "panelOrder",
        "hiddenHomeModules",
        "hiddenPanelModules",
        "moduleEnableOverrides",
        "showCalendar",
        "enableStatsFeature",
        "dynamicShelf",
        "enableTerminalFeature",
        "enableClipboardManager",
        "enableColorPickerFeature",
        "showMirror",
        "showStandardMediaControls",
        "enableTimerFeature",
    ]

    /// 文档**明确不在清单里**的键（§接口与数据形状 那一行 + 机制七的判据「这个键丢了会不会让用户
    /// 丢东西 / 要重新授权」）。分类与理由写在 `PanelLayoutDefaults` 的文件头。
    private static let documentedOutOfScopeKeys: [String] = [
        // 功能入口类（文档点名的三条）
        "enableScreenAssistant",
        "quickShareProvider",
        "enableLLMUsageFeature",
        // 提醒 / 日历来源（选中哪些日历 = 要用户重选一遍）
        "calendarSelectionState",
        // 剪贴板历史与固定项（裸键：`ClipboardManager` 直接写 `UserDefaults.standard`）
        "ClipboardHistory",
        "ClipboardPinnedItems",
        // 取色历史（同一类「内容」；文档只写了剪贴板历史，这一条按同一判据补上）
        "ColorPickerHistory",
        // 屏幕助手留下的文件清单（同一类）
        "ScreenAssistantFiles",
        // 快捷指令清单与缓存（模块 suite 的键：连域都不是本域，列在这里是为了把「够不着」也钉住）
        "pinnedShortcuts",
        "cachedShortcuts",
    ]

    /// 改乱清单内 17 键用的值（类型与各自真源一致）。
    private static let mangledInScopeValues: [(key: String, value: Any)] = [
        (Defaults.Keys.openNotchWidth.name, CGFloat(777)),
        (Defaults.Keys.openNotchHeight.name, CGFloat(555)),
        (Defaults.Keys.panelHeightMode.name, PanelAutoHeight.modeManual),
        (Defaults.Keys.homeBlockOrder.name, ["com.example.block": 3]),
        (Defaults.Keys.panelOrder.name, ["com.example.tab": 1]),
        (Defaults.Keys.hiddenHomeModules.name, ["com.example.hidden"]),
        (Defaults.Keys.hiddenPanelModules.name, ["com.example.hiddenTab"]),
        (Defaults.Keys.moduleEnableOverrides.name, ["com.example.module": true]),
        (Defaults.Keys.showCalendar.name, false),
        (Defaults.Keys.enableStatsFeature.name, true),
        (Defaults.Keys.dynamicShelf.name, false),
        (Defaults.Keys.enableTerminalFeature.name, true),
        (Defaults.Keys.enableClipboardManager.name, false),
        (Defaults.Keys.enableColorPickerFeature.name, false),
        (Defaults.Keys.showMirror.name, true),
        (Defaults.Keys.showStandardMediaControls.name, false),
        (Defaults.Keys.enableTimerFeature.name, false),
    ]

    /// 改乱**清单外**对照键用的值：类型可简单读回的那几个（三个强类型键 + 四个裸内容键）。
    /// 重置之后它们必须**仍是**这些值——这是「清单外的键一个不动」的行为级判据。
    private static let mangledOutOfScopeValues: [(key: String, value: Any)] = [
        (Defaults.Keys.enableScreenAssistant.name, false),
        (Defaults.Keys.quickShareProvider.name, "LocalSend"),
        (Defaults.Keys.enableLLMUsageFeature.name, true),
        ("ClipboardHistory", Data([0x01, 0x02, 0x03])),
        ("ClipboardPinnedItems", Data([0x04])),
        ("ColorPickerHistory", Data([0x05])),
        ("ScreenAssistantFiles", Data([0x06])),
    ]

    /// 外观页新增的五条文案 key（§接口与数据形状 的文案表）。
    private static let appearanceLayoutLocalisationKeys: [String] = [
        "settings.appearance.panelLayout",
        "settings.appearance.resetLayout",
        "settings.appearance.resetLayout.footer",
        "settings.appearance.heightMode.auto",
        "settings.appearance.heightMode.manual",
    ]

    // MARK: - 清单本身（契约）

    /// 清单**逐字**等于文档那一行：不多（把授权 / 内容类顺手扫进来）、不少（漏键会留下改乱后的值）。
    func testResetKeysAreExactlyTheDocumentedList() {
        XCTAssertEqual(PanelLayoutDefaults.resetKeys.count, Self.documentedResetKeys.count, "个数与文档一致")
        XCTAssertEqual(
            Set(PanelLayoutDefaults.resetKeys).count,
            PanelLayoutDefaults.resetKeys.count,
            "清单里没有重复项"
        )
        XCTAssertEqual(
            Set(PanelLayoutDefaults.resetKeys),
            Set(Self.documentedResetKeys),
            "与文档那一行逐字一致（多一个 / 少一个都是清单漂移）"
        )
    }

    /// 名字级护栏：文档点名的排除项 + 各内容类键，一个都不在清单里。
    func testOutOfScopeKeysAreNotInTheResetList() {
        for key in Self.documentedOutOfScopeKeys {
            XCTAssertFalse(
                PanelLayoutDefaults.resetKeys.contains(key),
                "\(key) 不该被「恢复默认」扫掉（判据：丢了会不会让用户丢东西 / 要重新授权）"
            )
        }
    }

    // MARK: - 重置动作

    /// 核心口径：**删掉，不是写默认值**。
    ///
    /// 判据只能在**持久域**上做（`persistedDomain(forName:)`）：`object(forKey:)` 会被注册域污染
    /// ——`Defaults.Key` 的初始化就 `register(defaults:)` 了默认值，任何已声明的键恒非 nil
    /// （`TakeoverEnablementTests.persistedValue(of:)` 里写明同一条）。写一个「恰好等于默认值的值」
    /// 与用户的显式选择同形，盘上就是不可判的——所以必须真的删。
    func testResetDeletesEveryKeyInsteadOfWritingTheDefaultValue() {
        let scope = Self.mangledInScopeValues.map(\.key)
        let snapshot = snapshotValues(of: scope)
        defer { restoreValues(snapshot, for: scope) }

        for (key, value) in Self.mangledInScopeValues {
            UserDefaults.standard.set(value, forKey: key)
        }
        // 机制自检：改乱得**看得见**（否则下面那句「没了」可能是假的）。
        for (key, _) in Self.mangledInScopeValues {
            XCTAssertNotNil(persistedValue(of: key), "\(key) 改乱之后应该在持久域里")
        }

        PanelLayoutDefaults.reset()

        for key in PanelLayoutDefaults.resetKeys {
            XCTAssertNil(
                persistedValue(of: key),
                "\(key) 重置后必须**不在盘上**（删掉，不是把默认值写回去）"
            )
        }
        // 出厂默认从注册域读得回来（真源仍是 `Defaults.Keys` 的 `default`，不是写进去的一份）。
        XCTAssertEqual(Defaults[.openNotchWidth], 640)
        XCTAssertEqual(Defaults[.openNotchHeight], 200)
        XCTAssertEqual(Defaults[.panelHeightMode], PanelAutoHeight.modeAuto)
        XCTAssertEqual(Defaults[.homeBlockOrder], [:])
        XCTAssertEqual(Defaults[.panelOrder], [:])
        XCTAssertEqual(Defaults[.hiddenHomeModules], [])
        XCTAssertEqual(Defaults[.hiddenPanelModules], [])
        XCTAssertEqual(Defaults[.moduleEnableOverrides], [:])
        XCTAssertEqual(Defaults[.showCalendar], true)
        XCTAssertEqual(Defaults[.enableStatsFeature], false)
        XCTAssertEqual(Defaults[.dynamicShelf], true)
        XCTAssertEqual(Defaults[.enableTerminalFeature], false)
        XCTAssertEqual(Defaults[.enableClipboardManager], true)
        XCTAssertEqual(Defaults[.enableColorPickerFeature], true)
        XCTAssertEqual(Defaults[.showMirror], false)
        XCTAssertEqual(Defaults[.showStandardMediaControls], true)
        XCTAssertEqual(Defaults[.enableTimerFeature], true)
    }

    /// 清单外的键**一个不动**（行为级）：改乱之后重置，它们仍是改乱值。
    ///
    /// 名字级护栏（`testOutOfScopeKeysAreNotInTheResetList`）只挡得住「被列进清单」；这条挡的是
    /// 「重置实现改成删一圈 / 删一片」——D-13 的失败信号里那条「把授权 / 内容类一起清掉」。
    func testResetLeavesOutOfScopeKeysUntouched() {
        let scope = Self.mangledOutOfScopeValues.map(\.key)
        let snapshot = snapshotValues(of: scope)
        defer { restoreValues(snapshot, for: scope) }

        for (key, value) in Self.mangledOutOfScopeValues {
            UserDefaults.standard.set(value, forKey: key)
        }

        PanelLayoutDefaults.reset()

        for (key, value) in Self.mangledOutOfScopeValues {
            XCTAssertTrue(
                persistedValue(of: key).map { ($0 as AnyObject).isEqual(value as AnyObject) } ?? false,
                "\(key) 不在清单里 → 重置必须一个不动（原值 \(value)）"
            )
        }
        // 强类型读法也跟着没动（写进去的仍是那个非默认值）。
        XCTAssertFalse(Defaults[.enableScreenAssistant])
        XCTAssertEqual(Defaults[.quickShareProvider], "LocalSend")
        XCTAssertTrue(Defaults[.enableLLMUsageFeature])
    }

    /// 重置**会被既有的订阅链看到**（不然界面 / 面板尺寸不会跟着更新 = 「按了没反应」）。
    ///
    /// 钉的是 `Defaults.reset(_: [String])` 逐键走 `UserDefaults.removeObject`（KVO）这一层：
    /// `DynamicIslandApp` 的五条与 `DynamicIslandViewCoordinator` 的四条订阅都挂在这上面，
    /// 若哪天有人把重置改成绕过 `Defaults` 直接改一份私有存储，这条会红。
    func testResetNotifiesTheExistingDefaultsSubscribers() {
        let key = Defaults.Keys.panelHeightMode.name
        let snapshot = snapshotValues(of: [key])
        defer { restoreValues(snapshot, for: [key]) }

        UserDefaults.standard.set(PanelAutoHeight.modeManual, forKey: key)

        let expectation = expectation(description: "panelHeightMode 的订阅者在重置后收到变化")
        expectation.assertForOverFulfill = false
        let cancellable = Defaults.publisher(.panelHeightMode, options: []).sink { _ in
            expectation.fulfill()
        }
        defer { cancellable.cancel() }

        PanelLayoutDefaults.reset()

        wait(for: [expectation], timeout: 1)
    }

    /// 展开高度滑块（Notch Height 组）只在手动档可用：自适应档它写的 `openNotchHeight` 被内容高取代
    /// ——留着能拖就是「拖了没用」（与右下角把手 `showsPanelResizeHandle` 同一条先例，D-16）。
    func testExpandHeightSliderIsEnabledOnlyInManualMode() {
        XCTAssertFalse(
            PanelLayoutDefaults.expandHeightSliderEnabled(heightMode: PanelAutoHeight.modeAuto),
            "自适应档：滑块禁用"
        )
        XCTAssertTrue(
            PanelLayoutDefaults.expandHeightSliderEnabled(heightMode: PanelAutoHeight.modeManual),
            "手动档：滑块可用（今天的行为逐字不变）"
        )
        XCTAssertFalse(
            PanelLayoutDefaults.expandHeightSliderEnabled(heightMode: "nonsense"),
            "未知档按默认档（auto）算 → 禁用"
        )
    }

    /// 新增的五条文案 key 在 **en 与 zh-Hans 两份**里都解析得出（都 `translated`）。
    ///
    /// 语言锁定地查子 bundle（不跟着跑测机器的语言走）——理由与用法见
    /// `TakeoverEnablementTests.XCTAssertResolves` 的注释。
    func testAppearanceLayoutLocalisationKeysResolveInBothLanguages() {
        for language in ["en", "zh-Hans"] {
            guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
                  let bundle = Bundle(path: path) else {
                XCTFail("宿主 bundle 里找不到 \(language).lproj")
                continue
            }
            for key in Self.appearanceLayoutLocalisationKeys {
                let localized = bundle.localizedString(forKey: key, value: nil, table: nil)
                XCTAssertNotEqual(localized, key, "\(key) 在 \(language) 里没解析出文案（catalog 未编进宿主 bundle？）")
                XCTAssertFalse(localized.isEmpty, "\(key) 在 \(language) 里解析为空串")
            }
        }
    }

    // MARK: - 脚本取证（三份 defaults export）

    /// 产三份 `defaults export`（改乱前 / 改乱后 / 重置后）到证据目录，逐键比对交给同目录下的
    /// `t8-reset-evidence.sh`（人可读的表）。
    ///
    /// 顺序（**全在同一进程里同步做**：`Process.run` 期间主线程被占住，跑测的 App 那一侧没有机会
    /// 在写与导出之间插进自己的写）：
    /// ① `reset()` → 干净起点（=「改乱前」；出厂态，不是这台机器的历史状态）→ `t8-reset-before.plist`；
    /// ② 17 键 + 对照键改乱 → `t8-reset-messed.plist`（并断言导出里**真的**看得到改乱值：
    ///    「导出的确读得到进程内的写」这条机制不成立的话，整份证据都不算数）；
    /// ③ `reset()` → `t8-reset-after.plist`（并断言 17 键从持久域消失、对照键仍是改乱值）；
    /// ④ `defer` 里逐字还原（偏好卫生）。
    ///
    /// 域 = `Bundle.main.bundleIdentifier`（跑测宿主就是 Gourd.app：Debug 档是 `com.cmeng.gourd.dev`，
    /// Release 档是 `com.cmeng.gourd`）——不写死，换档跑也能用。
    func testResetWritesTheThreeScriptExports() throws {
        let evidenceDirectory = Self.repositoryRoot
            .appendingPathComponent(".workflow/p5-home-blocks/evidence")
        guard FileManager.default.fileExists(atPath: evidenceDirectory.path) else {
            throw XCTSkip("没有 .workflow/p5-home-blocks/evidence（这条只带工作流一起跑）")
        }
        let domain = try XCTUnwrap(Bundle.main.bundleIdentifier, "宿主 bundle id 必须可解析（= 我们的偏好域）")

        let scope = Self.mangledInScopeValues.map(\.key) + Self.mangledOutOfScopeValues.map(\.key)
        let snapshot = snapshotValues(of: scope)
        defer { restoreValues(snapshot, for: scope) }

        let before = evidenceDirectory.appendingPathComponent("t8-reset-before.plist")
        let messed = evidenceDirectory.appendingPathComponent("t8-reset-messed.plist")
        let after = evidenceDirectory.appendingPathComponent("t8-reset-after.plist")

        // ① 干净起点（改乱前）
        PanelLayoutDefaults.reset()
        try exportDefaults(domain: domain, to: before)

        // ② 改乱（清单内 17 键 + 清单外对照键）
        for (key, value) in Self.mangledInScopeValues + Self.mangledOutOfScopeValues {
            UserDefaults.standard.set(value, forKey: key)
        }
        try exportDefaults(domain: domain, to: messed)

        // 机制自检：导出的那份里看得到改乱值（看不到 = `defaults export` 读的是别处 / 有缓存）。
        let messedPlist = try XCTUnwrap(NSDictionary(contentsOf: messed) as? [String: Any], "改乱后的导出必须能读回来")
        for (key, _) in Self.mangledInScopeValues + Self.mangledOutOfScopeValues {
            XCTAssertNotNil(messedPlist[key], "\(key) 的改乱值应该在导出的 plist 里（否则这条取证链断了）")
        }
        XCTAssertEqual(messedPlist[Defaults.Keys.panelHeightMode.name] as? String, PanelAutoHeight.modeManual)

        // ③ 重置（真代码路径）→ 重置后
        PanelLayoutDefaults.reset()
        try exportDefaults(domain: domain, to: after)

        for key in PanelLayoutDefaults.resetKeys {
            XCTAssertNil(persistedValue(of: key), "\(key) 重置后不该在持久域里")
        }
        for (key, value) in Self.mangledOutOfScopeValues {
            XCTAssertTrue(
                persistedValue(of: key).map { ($0 as AnyObject).isEqual(value as AnyObject) } ?? false,
                "\(key) 不在清单里 → 重置后仍是改乱值"
            )
        }
    }

    // MARK: - 夹具

    /// 仓库根（`#filePath` 是编译期的绝对路径：`.../DynamicIslandTests/PanelLayoutDefaultsTests.swift`）。
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// `defaults export <域> <路径>`（证据产物就是这条命令的原样输出）。
    private func exportDefaults(domain: String, to url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["export", domain, url.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "defaults export \(domain) \(url.lastPathComponent) 失败")
    }

    /// 持久域里那个键的原值（`nil` = 盘上没有这个键）。
    ///
    /// 为什么不用 `object(forKey:)`：`Defaults.Key` 的初始化会 `register(defaults:)`，
    /// 于是 `object(forKey:)` 对任何已声明的键恒非 nil，答不出「盘上有没有」——同
    /// `TakeoverEnablementTests.persistedValue(of:)` 的口径。
    private func persistedValue(of key: String) -> Any? {
        guard let domain = Bundle.main.bundleIdentifier else { return nil }
        return UserDefaults.standard.persistentDomain(forName: domain)?[key]
    }

    /// 一次记下若干键的持久域原值（**只装「盘上真有」的键**：缺的键不在表里 → 还原成删键）。
    private func snapshotValues(of keys: [String]) -> [String: Any] {
        var table: [String: Any] = [:]
        for key in keys {
            if let value = persistedValue(of: key) { table[key] = value }
        }
        return table
    }

    /// 按同一份键表逐字还原（表里没有的键 = 原本没有 → 删键）。
    private func restoreValues(_ snapshot: [String: Any], for keys: [String]) {
        for key in keys { restore(snapshot[key], to: key) }
    }

    /// 还原一个持久域原值：原本有键写回原值、原本没键删键（写一个默认值会在域里留下存在的键）。
    private func restore(_ value: Any?, to key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
