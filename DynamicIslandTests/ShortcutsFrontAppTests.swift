//
//  ShortcutsFrontAppTests.swift
//  Gourd 模块 · 快捷指令与前台应用联动（p2-shortcuts-frontapp / T1）
//
//  docs/22-shortcuts-and-frontapp.md §接口与数据形状 1 的用例落点（T1 段）：
//
//  - `ShortcutListParser.parse` 五组：正常行 / 名称含空格 / **名称含括号** / 形状不符丢弃 / 空表；
//  - `ShortcutFiltering.visible` 四组：固定在前且保持固定表顺序 / 搜索命中 name / 命中 identifier / 无命中；
//  - 文件内 `RecordingConfigHandle`：**会落盘**的 `ConfigHandle` 假体——T2 用它断言
//    「刷新时缓存确实先落盘再发布」。
//
//  三条刻意写死的口径（改动前先读）：
//
//  1. **样本行全是合成的**：本机 `/usr/bin/shortcuts list --show-identifiers` 恰两行
//     （形如 `外观-浅色 (24D4F870-…)`），identifier 是**这台机器独有的**——把它写进用例
//     等于给别的机器埋一条必红的断言。这里只借**形状**（名称里的空格与括号），值全是自造串；
//  2. **不跑真命令**：`parse` / `visible` 是纯函数；T1 的用例不碰 `Process`
//     （注入点是给 T2 的 store 用的），因此不受本机装了什么快捷指令影响；
//  3. **假体不写任何真实域**：`RecordingConfigHandle` 只落在内存字典里，**不碰**
//     `com.cmeng.gourd.module.shortcuts`（那是开发机的真实域，真 `ManifestConfigHandle` 会写它）。
//

import Foundation
import XCTest

@testable import Gourd

@MainActor
final class ShortcutsFrontAppTests: XCTestCase {

    // MARK: - parse（五组）

    /// ① 正常行：`<名称> (<identifier>)` → 名称与 identifier 都正确，顺序不变。
    func testParseNormalLines() {
        let parsed = ShortcutListParser.parse(lines: [
            "晨间惯例 (11111111-1111-1111-1111-111111111111)",
            "去公司 (22222222-2222-2222-2222-222222222222)",
        ])

        XCTAssertEqual(parsed, [
            Shortcut(identifier: "11111111-1111-1111-1111-111111111111", name: "晨间惯例"),
            Shortcut(identifier: "22222222-2222-2222-2222-222222222222", name: "去公司"),
        ])
    }

    /// ② 名称含空格：空格是名称的一部分，不是分界（分界是 ` (`，不是任意空格）。
    func testParseNameWithSpaces() {
        let parsed = ShortcutListParser.parse(lines: [
            "整理 收件箱 模板 (33333333-3333-3333-3333-333333333333)",
        ])

        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed.first?.name, "整理 收件箱 模板")
        XCTAssertEqual(parsed.first?.identifier, "33333333-3333-3333-3333-333333333333")
    }

    /// ③ 名称含括号（**判据是「从行尾往回找第一个 ` (`」**）：按第一个 ` (` 从左往右切的话，
    /// 名称会变成 `整理桌面`、identifier 会变成 `旧) (4444…`——后者「看起来也像一个 identifier」，
    /// 所以断言必须精确到值，不能只数条数。
    ///
    /// 全角括号（`外观（浅色）`）不是 ` (`，因此它们连干扰项都算不上——一并钉住，说明
    /// 「名称里有括号」这件事与括号的种类无关，规则只看 ASCII 的 ` (`。
    func testParseNameWithParentheses() {
        let parsed = ShortcutListParser.parse(lines: [
            "整理桌面 (旧) (44444444-4444-4444-4444-444444444444)",
            "外观（浅色） (55555555-5555-5555-5555-555555555555)",
        ])

        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed.first?.name, "整理桌面 (旧)", "名称含括号 → 仍切在最后一个 ` (` 上")
        XCTAssertEqual(parsed.first?.identifier, "44444444-4444-4444-4444-444444444444")
        XCTAssertEqual(parsed.last?.name, "外观（浅色）")
        XCTAssertEqual(parsed.last?.identifier, "55555555-5555-5555-5555-555555555555")
    }

    /// ④ 形状不符丢弃：**不猜、不补默认名**（名字可变，任何兜底都会静默错人）。
    ///
    /// 五条坏行各坏在不同的地方，且**都不能**变成条目：
    /// 没有 ` (` / 不以 `)` 结尾 / 名称为空 / identifier 为空 / 名称只有空白（去空白后为空）。
    func testParseDropsMalformedLines() {
        let parsed = ShortcutListParser.parse(lines: [
            "没有分隔符",                                     // 没有 ` (` → 丢
            "有括号但没结尾 (66666666-6666-6666-6666-666666666666",  // 不以 `)` 结尾 → 丢
            " (77777777-7777-7777-7777-777777777777)",       // 名称为空 → 丢
            "只有名字 ()",                                    // identifier 为空 → 丢
            "   (88888888-8888-8888-8888-888888888888)",     // 名称只有空白 → 丢
            "留下这一条 (99999999-9999-9999-9999-999999999999)",
        ])

        XCTAssertEqual(parsed, [
            Shortcut(identifier: "99999999-9999-9999-9999-999999999999", name: "留下这一条"),
        ], "五条坏行都不能变成条目")
    }

    /// ⑤ 空表：空输入 → 空输出（不崩、不造占位行）。
    func testParseEmptyList() {
        XCTAssertEqual(ShortcutListParser.parse(lines: []), [])
    }

    // MARK: - visible（四组）

    /// ① 固定项在前且**保持固定表顺序**，其余保持命令给出的顺序。
    ///
    /// 三条：固定表自己排的顺序说了算（c 在 a 前）、固定项从原位消失（不重复出现）、
    /// 固定表里已不在清单里的 id 跳过（在系统里删掉的指令不该凭空出现）。
    func testVisiblePutsPinnedFirstKeepingPinnedOrder() {
        let list = [
            Shortcut(identifier: "id-a", name: "Alpha"),
            Shortcut(identifier: "id-b", name: "Beta"),
            Shortcut(identifier: "id-c", name: "Gamma"),
        ]

        XCTAssertEqual(
            ShortcutFiltering.visible(list, pinned: ["id-c", "id-a"], query: "").map(\.identifier),
            ["id-c", "id-a", "id-b"],
            "固定项在前（固定表顺序 c → a），其余保持清单顺序（b）"
        )
        XCTAssertEqual(
            ShortcutFiltering.visible(list, pinned: ["id-b"], query: "").map(\.identifier),
            ["id-b", "id-a", "id-c"],
            "只固定 b：它提前，a / c 的相对顺序不变"
        )
        XCTAssertEqual(
            ShortcutFiltering.visible(list, pinned: ["id-ghost", "id-c"], query: "").map(\.identifier),
            ["id-c", "id-a", "id-b"],
            "固定表里已不存在的 id 直接跳过"
        )
        XCTAssertEqual(
            ShortcutFiltering.visible(list, pinned: ["id-c"], query: "   ").map(\.identifier),
            ["id-c", "id-a", "id-b"],
            "查询词只有空白 = 不过滤（搜索框里多打一个空格不该变成「无命中」）"
        )
    }

    /// ② 搜索命中 name（大小写不敏感）。
    func testVisibleMatchesNameCaseInsensitively() {
        let list = [
            Shortcut(identifier: "id-a", name: "Alpha 收件箱"),
            Shortcut(identifier: "id-b", name: "Beta"),
        ]

        XCTAssertEqual(
            ShortcutFiltering.visible(list, pinned: [], query: "alpha").map(\.identifier),
            ["id-a"],
            "命中 name：`alpha` 匹配 `Alpha 收件箱`"
        )
        XCTAssertEqual(
            ShortcutFiltering.visible(list, pinned: [], query: "收件箱").map(\.identifier),
            ["id-a"],
            "中文同样按包含匹配"
        )
    }

    /// ③ 搜索命中 identifier（大小写不敏感）——名称里没有的串也能搜到，这是 identifier 那一半。
    func testVisibleMatchesIdentifierCaseInsensitively() {
        let list = [
            Shortcut(identifier: "9F9F9F9F-1111-1111-1111-111111111111", name: "晨间惯例"),
            Shortcut(identifier: "id-b", name: "Beta"),
        ]

        XCTAssertEqual(
            ShortcutFiltering.visible(list, pinned: [], query: "9f9f9f9f").map(\.identifier),
            ["9F9F9F9F-1111-1111-1111-111111111111"],
            "命中 identifier（小写查询匹配大写 identifier）"
        )
        XCTAssertEqual(
            ShortcutFiltering.visible(list, pinned: [], query: "1111-1111").map(\.identifier),
            ["9F9F9F9F-1111-1111-1111-111111111111"],
            "identifier 中段也能命中"
        )
    }

    /// ④ 无命中 → 空表；**固定项也要过搜索**（固定不等于「永远显示」，否则搜别的名字会看到一堆
    /// 无关的固定项）。这一条是「搜索先于排序」的判据。
    func testVisibleReturnsNothingWhenQueryMatchesNothing() {
        let list = [
            Shortcut(identifier: "id-a", name: "Alpha"),
            Shortcut(identifier: "id-c", name: "Gamma"),
        ]

        XCTAssertEqual(ShortcutFiltering.visible(list, pinned: [], query: "zzz"), [], "无命中 → 空表")
        XCTAssertEqual(
            ShortcutFiltering.visible(list, pinned: ["id-c"], query: "zzz"),
            [],
            "固定项也要过搜索"
        )
    }

    // MARK: - 假体本身的落盘语义

    /// `RecordingConfigHandle` 是 T2 的断言工具（「缓存先落盘再刷新」），因此它自己的落盘语义
    /// 也要有断言：写进去读得回来、写入顺序按发生次序记、schema 之外两边都不认。
    func testRecordingConfigHandlePersistsWritesInOrder() {
        let config = RecordingConfigHandle()

        XCTAssertTrue(config.set("cachedShortcuts", to: ["A (1)", "B (2)"]))
        XCTAssertEqual(
            config.stringList("cachedShortcuts"),
            ["A (1)", "B (2)"],
            "写进去的值读得回来（这就是「落盘」，与 `StubConfigHandle` 的恒 nil 不同）"
        )

        XCTAssertTrue(config.set("pinnedShortcuts", to: ["1"]))
        XCTAssertEqual(config.writeLog, ["cachedShortcuts", "pinnedShortcuts"], "写入顺序按发生次序记下")

        XCTAssertNil(config.get("cachedShortcuts", as: [Int].self), "类型不符 → nil（同真句柄的回落口径）")
        XCTAssertFalse(config.set("cachedShortcuts2", to: ["x"]), "schema 之外的键不落盘")
        XCTAssertNil(config.stringList("cachedShortcuts2"), "schema 之外的键读不出来")
    }
}

// MARK: - 会落盘的 ConfigHandle 假体（T2 用）

/// **会落盘**的 `ConfigHandle` 假体：`ModuleKernelTests` 的 `StubConfigHandle` 只返 nil、
/// 真 `ManifestConfigHandle`（`ModuleContextFactory.swift`）是 `private` 且会写开发机真实域
/// `com.cmeng.gourd.module.shortcuts`——两者都不能拿来断言「缓存确实写下去了」。
///
/// 形态与真句柄一致：`set` 走 JSON 编码落进内存字典、`get` 走 JSON 解码读回；
/// schema 之外的键 `get` 返 nil、`set` 返 false。另记一条**写入顺序**（`writeLog`），
/// T2 据此断言刷新时「先落盘再发布」。
///
/// **不落任何真实域**（不动 `UserDefaults`），用例因此不会污染开发机的模块配置。
final class RecordingConfigHandle: ConfigHandle {
    /// 落盘的值（键 → JSON 字节，与真句柄的存储形态一致）。
    private(set) var storage: [String: Data] = [:]
    /// 写过的键，按写入顺序（同一键写两次就有两条）。
    private(set) var writeLog: [String] = []

    private let schema: Set<String>

    /// - Parameter schema: 本模块 manifest 登记的键（默认 = 快捷指令的四键）。
    init(schema: Set<String> = ["pinnedShortcuts", "showOutput", "timeoutSeconds", "cachedShortcuts"]) {
        self.schema = schema
    }

    func get<T: Codable & Sendable>(_ key: String, as type: T.Type) -> T? {
        guard schema.contains(key), let data = storage[key] else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func set<T: Codable & Sendable>(_ key: String, to value: T) -> Bool {
        guard schema.contains(key), let data = try? JSONEncoder().encode(value) else { return false }
        storage[key] = data
        writeLog.append(key)
        return true
    }

    /// 用例侧的便捷读法（等价于 `get(key, as: [String].self)`）。
    func stringList(_ key: String) -> [String]? { get(key, as: [String].self) }
}
