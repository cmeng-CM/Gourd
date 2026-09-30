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
//  T2 段（`ShortcutsModule` / `ShortcutsStore`，§接口与数据形状 2 + §做法 机制一/二）：
//
//  - manifest 逐字段契约（只声明 `expanded`、默认关、`shortcuts:run`、config 四键、文案可解析）；
//  - 内容分发（`expanded` → `.view`，其余 surface → `.none`）；
//  - store：缓存非空时进 tab **不取数** / 缓存为空时自动拉一次且只有那一次；
//    `refresh()` **先写回原始行再发布** / `togglePin` 先落盘再刷新 / `run` 的并发闸门。
//
//  T3 段（`FrontAppHistory`，§接口与数据形状 3 的纯函数侧；store 的订阅与图标取值不进单测）：
//
//  - `updated` 三组：去重移前（含"应用重启后 pid 变了仍是同一条历史"）/ 截到上限 / 空表 +
//    `limit: 1` 时**纯函数严格按 1 截断**（夹取只在 store 那一次，见 `clampedLimit`）；
//  - `excludingSelf` 两组：自身被滤掉 / 自身不在表里（或本应用没有 bundleID）→ 原样；
//  - 身份 `id` 的 pid 兜底（无 bundleID 的进程）；
//  - 夹取区间本身：`clampedLimit(1) == 3` / `(99) == 8` / `(5) == 5`。
//
//  T4 段（`FrontAppModule`，§接口与数据形状 4 + §做法 机制三/机制四）：
//
//  - manifest 逐字段契约（只声明 `home`、默认关、零权限、`order 30`、config 一键、文案可解析）；
//  - 内容分发（`home` → `.view`，其余 surface → `.none`）与 `deactivate()` 的幂等；
//  - 块宽回落：模块不声明 `homeBlockWidth`，注册表对「已注册但不声明」回 nil（宿主统一值）；
//  - `maxRecentApps` 的读 → 夹：模块显式传进 store 的值被夹一次后写进 `recentLimit`。
//
//  视图（`FrontAppHomeBlockView`）不进单测：它只做呈现（排布、悬停、点击转发），
//  历史口径与上限都在 T3 的纯函数与 store 里——这里只钉"模块把哪一份内容交出去"。
//
//  四条刻意写死的口径（改动前先读）：
//
//  1. **样本行全是合成的**：本机 `/usr/bin/shortcuts list --show-identifiers` 恰两行
//     （形如 `外观-浅色 (24D4F870-…)`），identifier 是**这台机器独有的**——把它写进用例
//     等于给别的机器埋一条必红的断言。这里只借**形状**（名称里的空格与括号），值全是自造串；
//  2. **不跑真命令**：`parse` / `visible` 是纯函数；T2 的 store 用例一律给**注入点假体**
//     （`RecordingRunner` + 构造的行），因此不依赖本机装了什么快捷指令、也不起子进程；
//  3. **假体不写任何真实域**：`RecordingConfigHandle` 只落在内存字典里，**不碰**
//     `com.cmeng.gourd.module.shortcuts`（那是开发机的真实域，真 `ManifestConfigHandle` 会写它）；
//  4. **前台应用的样本全是手造快照**（T3）：不订阅真 `NSWorkspace` 通知、不读当下真实的前台应用
//     ——跑测试时前台是 Xcode / 终端，把任何真名字写进断言都必红，且会让用例互相污染。
//

import Foundation
import SwiftUI
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

    // MARK: - T2：manifest 契约

    /// manifest 逐字段对齐 docs/22 §接口与数据形状 2：**只声明 `expanded`**、默认关、
    /// `permissions = ["shortcuts:run"]`、无 placement、config 四键；文案 key 都能从宿主 bundle 解析。
    func testShortcutsManifestContract() throws {
        let manifest = ShortcutsModule.manifest
        XCTAssertNoThrow(try manifest.validate(), "真模块的 manifest 必须过校验（含 symbol 可解析性）")

        XCTAssertEqual(manifest.manifestVersion, 1)
        XCTAssertEqual(manifest.id, "com.cmeng.gourd.shortcuts")
        XCTAssertEqual(ShortcutsModule.moduleID, "com.cmeng.gourd.shortcuts", "moduleID 是 id 的唯一字面量来源")
        XCTAssertEqual(manifest.shortID, "shortcuts")
        XCTAssertEqual(manifest.name.key, "module.shortcuts.name")
        XCTAssertEqual(manifest.summary?.key, "module.shortcuts.summary")
        XCTAssertEqual(manifest.icon.type, "symbol")
        XCTAssertEqual(manifest.icon.name, "bolt.square")
        XCTAssertEqual(manifest.version, "1.0.0")
        XCTAssertEqual(manifest.apiVersion, HostInfo.currentAPIVersion)
        XCTAssertEqual(manifest.kind, "builtin")

        XCTAssertEqual(manifest.surfaces, [.expanded], "只声明 expanded（docs/22 §接口与数据形状 2 / D-06）")
        XCTAssertFalse(manifest.surfaces.contains(.compact), "折叠槽位不占（已随左右槽位降级）")
        XCTAssertFalse(manifest.surfaces.contains(.home), "首页块不占（本批只做展开 tab）")
        XCTAssertFalse(manifest.surfaces.contains(.lockscreen))

        XCTAssertEqual(manifest.defaultEnabled, false, "新增模块一律默认关（docs/22 D-06 / docs/14 T-12）")
        XCTAssertEqual(manifest.permissions, ["shortcuts:run"], "06 §7.1 已登记的能力条目")
        XCTAssertNil(manifest.defaultPlacement, "placement 只在含 compact 时有意义，本批不给")

        let properties = try XCTUnwrap(manifest.config?.properties)
        XCTAssertEqual(
            Set(properties.keys),
            ["pinnedShortcuts", "showOutput", "timeoutSeconds", "cachedShortcuts"],
            "config 只有这四个键"
        )
        XCTAssertEqual(properties["pinnedShortcuts"]?.type, "list")
        XCTAssertEqual(properties["pinnedShortcuts"]?.itemType, "string")
        XCTAssertEqual(properties["pinnedShortcuts"]?.default, .strings([]))
        XCTAssertEqual(properties["showOutput"]?.type, "boolean")
        XCTAssertEqual(properties["showOutput"]?.default, .bool(false))
        XCTAssertEqual(properties["timeoutSeconds"]?.type, "integer")
        XCTAssertEqual(properties["timeoutSeconds"]?.default, .int(30))
        XCTAssertEqual(properties["cachedShortcuts"]?.type, "list")
        XCTAssertEqual(properties["cachedShortcuts"]?.itemType, "string")
        XCTAssertEqual(properties["cachedShortcuts"]?.default, .strings([]))
        // 默认值只有一个来源：`ShortcutsConfigDefaults`（这里同时把数值钉在文档口径上）
        XCTAssertEqual(ShortcutsConfigDefaults.pinnedShortcuts, [])
        XCTAssertEqual(ShortcutsConfigDefaults.showOutput, false)
        XCTAssertEqual(ShortcutsConfigDefaults.timeoutSeconds, 30)
        XCTAssertEqual(ShortcutsConfigDefaults.cachedShortcuts, [])

        // 文案 key 可解析（06 §3.3 R5：视图内不写字面量文案；catalog 没编进宿主 bundle 时这里会红）
        for key in [
            "module.shortcuts.name",
            "module.shortcuts.summary",
            "module.shortcuts.searchPlaceholder",
            "module.shortcuts.refresh",
            "module.shortcuts.run",
            "module.shortcuts.running",
            "module.shortcuts.pin",
            "module.shortcuts.unpin",
            "module.shortcuts.empty",
            "module.shortcuts.noMatch",
            "module.shortcuts.success",
            "module.shortcuts.failure",
            "module.shortcuts.timedOut",
            "module.shortcuts.outputTruncated",
            "module.shortcuts.runFailed",
        ] {
            let localized = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
            XCTAssertNotEqual(localized, key, "\(key) 没解析出文案（catalog 未编进宿主 bundle？）")
            XCTAssertFalse(localized.isEmpty, "\(key) 解析为空串")
        }
    }

    /// 内容分发：`expanded` 给 `.view`；**`.compact` / `.lockscreen` / `.home` 一律 `.none`**
    /// （不占位、不算失败——本批的契约，也是"折叠态与首页没有多出东西"的判据）。
    func testShortcutsModuleServesOnlyExpandedSurface() async throws {
        let module = ShortcutsModule(context: shortcutsContext())
        try await module.activate()

        guard case .view = module.content(for: request(.expanded)) else {
            return XCTFail("expanded 请求应拿到列表的 .view")
        }
        for surface in [Surface.compact, .lockscreen, .home] {
            guard case .none = module.content(for: request(surface)) else {
                return XCTFail("\(surface.rawValue) 未声明 → 必须答 .none（不占位）")
            }
        }

        await module.deactivate()
    }

    // MARK: - T2：取数、缓存与并发闸门

    /// `load()`：**读盘不算取数**——缓存非空时一次都不起子进程；
    /// 缓存为空时自动拉一次，且只有那一次（`load` 幂等）。
    ///
    /// 两条合起来正是失败信号「进 tab 就起子进程（每次进都刷新）」的反面。
    func testShortcutsStoreLoadsCacheWithoutListingAndAutoRefreshesOnce() async {
        // ① 缓存非空：读盘 → 发布（取数器一次都不该被调到）
        let cachedConfig = RecordingConfigHandle()
        XCTAssertTrue(cachedConfig.set("cachedShortcuts", to: ["晨间惯例 (id-morning)"]))
        XCTAssertTrue(cachedConfig.set("pinnedShortcuts", to: ["id-morning"]))
        var cachedListCalls = 0
        let cachedStore = ShortcutsStore(
            config: cachedConfig,
            logger: logger(),
            list: { cachedListCalls += 1; return [] },
            runShortcut: RecordingRunner().run
        )

        await cachedStore.load()

        XCTAssertEqual(cachedStore.shortcuts.map(\.identifier), ["id-morning"], "缓存里的**原始行**被解析出来")
        XCTAssertEqual(cachedStore.pinned, ["id-morning"], "固定表同样来自盘上")
        XCTAssertEqual(cachedListCalls, 0, "缓存非空 → 进 tab 不起子进程")

        // ② 缓存为空：首次进入自动拉一次并落盘；再进不重复取数
        let emptyConfig = RecordingConfigHandle()
        var emptyListCalls = 0
        let emptyStore = ShortcutsStore(
            config: emptyConfig,
            logger: logger(),
            list: { emptyListCalls += 1; return ["去公司 (id-office)"] },
            runShortcut: RecordingRunner().run
        )

        await emptyStore.load()
        XCTAssertEqual(emptyListCalls, 1, "缓存为空 → 首次进入自动拉一次")
        XCTAssertEqual(emptyStore.shortcuts.map(\.identifier), ["id-office"])
        XCTAssertEqual(
            emptyConfig.stringList("cachedShortcuts"),
            ["去公司 (id-office)"],
            "自动拉回来的原始行已落盘"
        )

        await emptyStore.load()
        XCTAssertEqual(emptyListCalls, 1, "再次进 tab 不再取数（`load` 幂等 + 缓存已非空）")
    }

    /// `refresh()`：**先写回 config 的 `cachedShortcuts`（原始行）再发布**（§做法 机制一 / D-01）。
    ///
    /// 四条一起钉住：盘上存的是**原始行**（不是解析后的名称或对象）、发布的是解析后的清单
    /// （屏幕与盘同源）、写盘发生在**发布之前**（`onSet` 在写盘那一刻读到的还是旧清单）、
    /// 这次刷新只写了一次盘。
    func testShortcutsStoreRefreshWritesRawLinesThenPublishes() async {
        let config = RecordingConfigHandle()
        XCTAssertTrue(config.set("cachedShortcuts", to: ["旧条目 (id-old)"]))
        let lines = ["新甲 (id-new-a)", "新乙 (id-new-b)"]
        let store = ShortcutsStore(
            config: config,
            logger: logger(),
            list: { lines },
            runShortcut: RecordingRunner().run
        )

        await store.load()
        XCTAssertEqual(store.shortcuts.map(\.identifier), ["id-old"], "先读盘上的旧缓存（不取数）")

        // 写盘那一刻的内存清单：用来判「先落盘、后发布」——若改成"只发布不落盘"，回调不会被调到
        var publishedWhenWritten: [Shortcut]?
        config.onSet = { key in
            if key == "cachedShortcuts" { publishedWhenWritten = store.shortcuts }
        }

        await store.refresh()

        XCTAssertEqual(config.stringList("cachedShortcuts"), lines, "缓存里存的是**原始行**")
        XCTAssertEqual(store.shortcuts.map(\.identifier), ["id-new-a", "id-new-b"], "发布的是解析后的清单")
        XCTAssertEqual(
            store.shortcuts,
            ShortcutListParser.parse(lines: config.stringList("cachedShortcuts") ?? []),
            "屏幕与盘同一份来源（解析只有一份）"
        )
        XCTAssertEqual(
            publishedWhenWritten?.map(\.identifier),
            ["id-old"],
            "落盘那一刻还没发布（先落盘、后刷新）"
        )
        XCTAssertEqual(config.writeLog, ["cachedShortcuts", "cachedShortcuts"], "初始化一次 + 这次刷新一次")
    }

    /// `togglePin`：**先落盘再刷新**（幂等，表尾追加 = 固定区的用户顺序）。
    func testShortcutsStoreTogglePinPersistsBeforePublishing() async {
        let config = RecordingConfigHandle()
        let store = ShortcutsStore(
            config: config,
            logger: logger(),
            list: { [] },
            runShortcut: RecordingRunner().run
        )
        let alpha = Shortcut(identifier: "id-a", name: "甲")
        let beta = Shortcut(identifier: "id-b", name: "乙")

        store.togglePin(alpha)
        XCTAssertEqual(config.stringList("pinnedShortcuts"), ["id-a"], "固定项已落盘（重启不丢）")
        XCTAssertEqual(store.pinned, ["id-a"], "落盘之后才换内存值")

        store.togglePin(beta)
        XCTAssertEqual(config.stringList("pinnedShortcuts"), ["id-a", "id-b"], "新固定追加在表尾（固定区顺序）")
        XCTAssertEqual(store.pinned, ["id-a", "id-b"])

        store.togglePin(alpha)
        XCTAssertEqual(config.stringList("pinnedShortcuts"), ["id-b"], "再点一次 = 取消固定")
        XCTAssertEqual(store.pinned, ["id-b"], "屏幕与盘一致")
    }

    /// **模块级并发闸门**（§做法 机制二）：运行期间再点一条，`run` 直接返回——假 runner 不再被调到。
    ///
    /// 驱动方式是「重入」：假 runner 的第一次调用里再 `run` 另一条（同一主 actor，没有竞态），
    /// 于是"闸门有没有生效"被判在**调用次数**上（去掉 `isRunning` 闸门 → 这里会数到 2 → 红）。
    func testShortcutsStoreRunIsGatedWhileRunning() async {
        let runner = RecordingRunner()
        let store = ShortcutsStore(
            config: RecordingConfigHandle(),
            logger: logger(),
            list: { [] },
            runShortcut: runner.run
        )
        runner.onFirstCall = { [weak store] in
            guard let store else { return XCTFail("store 已被释放") }
            await store.run(Shortcut(identifier: "id-second", name: "第二条"))   // 运行期间再点一条
        }

        await store.run(Shortcut(identifier: "id-first", name: "第一条"))

        XCTAssertEqual(
            runner.calls.map(\.identifier),
            ["id-first"],
            "运行期间第二次运行被闸门挡住：假 runner 没有被再调到"
        )
        XCTAssertFalse(store.isRunning, "跑完闸门放开")
        XCTAssertNil(store.runningIdentifier, "跑完行内 spinner 的判据清空")
        XCTAssertEqual(store.lastResult?.identifier, "id-first", "结果行记的是跑的那一条")
        XCTAssertEqual(store.lastResult?.name, "第一条")
    }

    /// 运行参数在**运行那一刻**从 config 读：`timeoutSeconds` / `showOutput` 原样传进注入的运行器；
    /// 缺键时兜到 `ShortcutsConfigDefaults`（30s / 不回显）。
    func testShortcutsStoreRunReadsSettingsFromConfig() async {
        let config = RecordingConfigHandle()
        XCTAssertTrue(config.set("timeoutSeconds", to: 7))
        XCTAssertTrue(config.set("showOutput", to: true))
        let runner = RecordingRunner()
        let store = ShortcutsStore(config: config, logger: logger(), list: { [] }, runShortcut: runner.run)

        await store.run(Shortcut(identifier: "id-a", name: "甲"))

        XCTAssertEqual(runner.calls.count, 1)
        XCTAssertEqual(runner.calls.first?.timeout, 7, "限时来自 config（不是写死的 30）")
        XCTAssertEqual(runner.calls.first?.captureOutput, true, "是否回显输出来自 config")

        // 缺键 → 默认值（`get` 给 nil 时兜到 `ShortcutsConfigDefaults`）
        let defaultRunner = RecordingRunner()
        let defaultStore = ShortcutsStore(
            config: RecordingConfigHandle(),
            logger: logger(),
            list: { [] },
            runShortcut: defaultRunner.run
        )
        await defaultStore.run(Shortcut(identifier: "id-b", name: "乙"))

        XCTAssertEqual(defaultRunner.calls.first?.timeout, 30, "缺键 → 默认 30s")
        XCTAssertEqual(defaultRunner.calls.first?.captureOutput, false, "缺键 → 默认不回显输出")
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

    // MARK: - T3：前台应用历史（纯函数）

    /// `updated` ① **去重移前**：同一个应用再切换回来只有一行、且排在最前。
    ///
    /// 去重是**按 `id`**（不是按对象相等）：同一个 bundleID、pid 变了的两次快照是同一条历史
    /// （应用重启后 pid 会变，那不该变成两行）。
    func testFrontAppHistoryUpdatedDedupesAndMovesToFront() {
        let safari = FrontAppSnapshot(bundleID: "com.apple.Safari", name: "Safari", pid: 101)
        let xcode = FrontAppSnapshot(bundleID: "com.apple.dt.Xcode", name: "Xcode", pid: 202)
        let notes = FrontAppSnapshot(bundleID: "com.apple.Notes", name: "备忘录", pid: 303)

        XCTAssertEqual(
            FrontAppHistory.updated([], activating: safari, limit: 5).map(\.id),
            ["com.apple.Safari"],
            "空表 + 一条 → 就是它"
        )
        XCTAssertEqual(
            FrontAppHistory.updated([safari], activating: xcode, limit: 5).map(\.id),
            ["com.apple.dt.Xcode", "com.apple.Safari"],
            "新来的排最前"
        )
        XCTAssertEqual(
            FrontAppHistory.updated([xcode, safari], activating: safari, limit: 5).map(\.id),
            ["com.apple.Safari", "com.apple.dt.Xcode"],
            "切回 Safari：只有一行（不是两行）+ 移到最前"
        )

        let relaunched = FrontAppSnapshot(bundleID: "com.apple.Safari", name: "Safari", pid: 999)
        let afterRelaunch = FrontAppHistory.updated([safari, xcode, notes], activating: relaunched, limit: 5)
        XCTAssertEqual(afterRelaunch.map(\.id), ["com.apple.Safari", "com.apple.dt.Xcode", "com.apple.Notes"])
        XCTAssertEqual(afterRelaunch.first?.pid, 999, "同 id 留下的是这一份新快照（pid 跟着更新）")
        XCTAssertEqual(afterRelaunch.count, 3, "不是并列两条")

        // 去重是全局的：表里被手改成两份的同一个 id 也并成一条
        XCTAssertEqual(
            FrontAppHistory.updated([xcode, xcode, safari], activating: notes, limit: 5).map(\.id),
            ["com.apple.Notes", "com.apple.dt.Xcode", "com.apple.Safari"],
            "同 id 的重复项并成一条（保留最先出现的那份）"
        )
    }

    /// `updated` ② **截到上限**：只留最新的 `limit` 条，最旧的从尾部挤掉；不足上限时不补东西。
    func testFrontAppHistoryUpdatedTruncatesToLimit() {
        let six = (0..<6).map {
            FrontAppSnapshot(bundleID: "com.example.app\($0)", name: "应用 \($0)", pid: pid_t(100 + $0))
        }
        let recent = six.reduce(into: [FrontAppSnapshot]()) { list, item in
            list = FrontAppHistory.updated(list, activating: item, limit: 3)
        }

        XCTAssertEqual(recent.count, 3, "截到 limit 条")
        XCTAssertEqual(
            recent.map(\.id),
            ["com.example.app5", "com.example.app4", "com.example.app3"],
            "留下的是最新的三条（新在前）"
        )
        XCTAssertFalse(recent.contains { $0.id == "com.example.app0" }, "最旧的被挤出")

        XCTAssertEqual(
            FrontAppHistory.updated([six[0], six[1]], activating: six[2], limit: 8).count,
            3,
            "不足上限时不补占位、也不报错"
        )
    }

    /// `updated` ③ **空表**与 `limit` 的严格截断：纯函数**不夹取**。
    ///
    /// 「夹到 3…8」是 **store 读 config 之后那一次**的事（`clampedLimit`），`updated` 只认传进来的
    /// `limit`——两处各夹一遍，"到底哪个值说了算"就没有唯一答案（口径 3）。
    func testFrontAppHistoryUpdatedOnEmptyTableAndStrictLimit() {
        let lone = FrontAppSnapshot(bundleID: "com.example.lone", name: "独苗", pid: 7)
        let alpha = FrontAppSnapshot(bundleID: "com.example.a", name: "甲", pid: 1)
        let beta = FrontAppSnapshot(bundleID: "com.example.b", name: "乙", pid: 2)

        XCTAssertEqual(
            FrontAppHistory.updated([], activating: lone, limit: 5),
            [lone],
            "空表 → 只有这一条（不造占位行）"
        )
        XCTAssertEqual(
            FrontAppHistory.updated([lone], activating: alpha, limit: 1).map(\.id),
            ["com.example.a"],
            "`limit: 1` → 严格只留 1 条（纯函数不抬到 3）"
        )
        XCTAssertEqual(
            FrontAppHistory.updated([alpha, beta], activating: lone, limit: 0),
            [],
            "`limit` 非正 → 空表（不崩、不越界）"
        )

        XCTAssertEqual(FrontAppHistory.defaultLimit, 5, "默认 5")
        XCTAssertEqual(FrontAppHistory.limitRange, 3...8, "可配区间 3…8")
        XCTAssertEqual(FrontAppHistory.clampedLimit(1), 3, "夹取：小于下界取下界")
        XCTAssertEqual(FrontAppHistory.clampedLimit(99), 8, "夹取：大于上界取上界")
        XCTAssertEqual(FrontAppHistory.clampedLimit(5), 5, "区间内原样")
    }

    /// 身份 `id`：有 bundleID 用它（跨重启稳定）；没有（命令行工具、裸可执行文件）退到 `pid:pid`。
    func testFrontAppSnapshotIdentityFallsBackToPID() {
        XCTAssertEqual(
            FrontAppSnapshot(bundleID: "com.apple.Safari", name: "Safari", pid: 101).id,
            "com.apple.Safari"
        )
        XCTAssertEqual(
            FrontAppSnapshot(bundleID: nil, name: "swift-frontend", pid: 4242).id,
            "pid:4242",
            "无 bundleID 的进程用 pid 兜底"
        )

        let bare = FrontAppSnapshot(bundleID: nil, name: "swift-frontend", pid: 4242)
        XCTAssertEqual(
            FrontAppHistory.updated([bare], activating: bare, limit: 5).count,
            1,
            "pid 兜底的身份同样参与去重"
        )
    }

    /// `excludingSelf` ① **自身被滤掉**，其余保持顺序（含只剩自己 → 空表）。
    ///
    /// 失败信号的正面对应：没排除自身时，每次点开刘海都会把壶中天自己记成"最近应用"。
    func testFrontAppHistoryExcludingSelfDropsSelf() {
        let selfApp = FrontAppSnapshot(bundleID: "com.cmeng.gourd", name: "壶中天", pid: 1)
        let safari = FrontAppSnapshot(bundleID: "com.apple.Safari", name: "Safari", pid: 101)
        let xcode = FrontAppSnapshot(bundleID: "com.apple.dt.Xcode", name: "Xcode", pid: 202)

        XCTAssertEqual(
            FrontAppHistory.excludingSelf([selfApp, safari, xcode], selfBundleID: "com.cmeng.gourd").map(\.id),
            ["com.apple.Safari", "com.apple.dt.Xcode"],
            "自己被滤掉，其余顺序不变"
        )
        XCTAssertEqual(
            FrontAppHistory.excludingSelf([selfApp], selfBundleID: "com.cmeng.gourd"),
            [],
            "只剩自己 → 空表"
        )
    }

    /// `excludingSelf` ② **自身不在表里**（或本应用没有 bundleID）→ 原样返回。
    ///
    /// 后两条是"没有判据就不猜"的边界：`selfBundleID` 为 nil 时不能拿 nil 去比（否则会把所有
    /// 无 bundleID 的进程一起误伤）；无 bundleID 的条目也不能被某个具体 bundleID 误伤。
    func testFrontAppHistoryExcludingSelfKeepsListWhenSelfAbsent() {
        let safari = FrontAppSnapshot(bundleID: "com.apple.Safari", name: "Safari", pid: 101)
        let xcode = FrontAppSnapshot(bundleID: "com.apple.dt.Xcode", name: "Xcode", pid: 202)
        let bare = FrontAppSnapshot(bundleID: nil, name: "swift-frontend", pid: 4242)

        XCTAssertEqual(
            FrontAppHistory.excludingSelf([safari, xcode], selfBundleID: "com.cmeng.gourd").map(\.id),
            ["com.apple.Safari", "com.apple.dt.Xcode"],
            "自身不在表里 → 一条都不动"
        )
        XCTAssertEqual(
            FrontAppHistory.excludingSelf([safari, bare], selfBundleID: nil).map(\.id),
            ["com.apple.Safari", "pid:4242"],
            "本应用没有 bundleID → 没有可排除的对象，原样返回（含无 bundleID 的条目）"
        )
        XCTAssertEqual(
            FrontAppHistory.excludingSelf([bare], selfBundleID: "com.cmeng.gourd").map(\.id),
            ["pid:4242"],
            "无 bundleID 的条目不被某个具体 bundleID 误伤"
        )
    }

    // MARK: - T4：前台应用模块（manifest / 内容分发 / 块宽回落）

    /// manifest 逐字段对齐 docs/22 §接口与数据形状 4：**只声明 `home`**、默认关、零权限、
    /// config 一键 `maxRecentApps`（默认 5）、文案 key 都能从宿主 bundle 解析。
    func testFrontAppManifestContract() throws {
        let manifest = FrontAppModule.manifest
        XCTAssertNoThrow(try manifest.validate(), "真模块的 manifest 必须过校验（含 symbol 可解析性）")

        XCTAssertEqual(manifest.manifestVersion, 1)
        XCTAssertEqual(manifest.id, "com.cmeng.gourd.frontapp")
        XCTAssertEqual(FrontAppModule.moduleID, "com.cmeng.gourd.frontapp", "moduleID 是 id 的唯一字面量来源")
        XCTAssertEqual(manifest.shortID, "frontapp")
        XCTAssertEqual(manifest.name.key, "module.frontapp.name")
        XCTAssertEqual(manifest.summary?.key, "module.frontapp.summary")
        XCTAssertEqual(manifest.icon.type, "symbol")
        XCTAssertEqual(manifest.icon.name, "app.badge")
        XCTAssertEqual(manifest.version, "1.0.0")
        XCTAssertEqual(manifest.apiVersion, HostInfo.currentAPIVersion)
        XCTAssertEqual(manifest.kind, "builtin")

        XCTAssertEqual(manifest.surfaces, [.home], "只声明 home（docs/22 §接口与数据形状 4 / D-06）")
        XCTAssertFalse(manifest.surfaces.contains(.expanded), "展开 tab 不占（本批只做首页块）")
        XCTAssertFalse(manifest.surfaces.contains(.compact), "折叠槽位不占（左右槽位已降级，§备选与取舍 ④）")
        XCTAssertFalse(manifest.surfaces.contains(.lockscreen))

        XCTAssertEqual(manifest.defaultEnabled, false, "新增模块一律默认关（docs/22 D-06 / docs/14 T-12）")
        XCTAssertTrue(
            manifest.permissions.isEmpty,
            "零权限：NSWorkspace 通知与 NSRunningApplication 都是公开 API（§接口与数据形状 4）"
        )
        XCTAssertEqual(
            manifest.defaultPlacement,
            Placement(slot: nil, order: 30),
            "首页块顺序 30（待办 20 与通知 40 之间，§接口与数据形状 4）"
        )
        XCTAssertNil(manifest.defaultPlacement?.slot, "slot 只在含 compact 时有意义，本模块不占槽位")

        let properties = try XCTUnwrap(manifest.config?.properties)
        XCTAssertEqual(Set(properties.keys), ["maxRecentApps"], "config 只有这一个键")
        XCTAssertEqual(properties["maxRecentApps"]?.type, "integer")
        XCTAssertEqual(
            properties["maxRecentApps"]?.default,
            .int(FrontAppHistory.defaultLimit),
            "默认值只有一个来源：`FrontAppHistory.defaultLimit`"
        )
        XCTAssertEqual(FrontAppHistory.defaultLimit, 5, "文档口径：默认 5（运行时夹取 3…8）")

        // 文案 key 可解析（06 §3.3 R5：视图内不写字面量文案；catalog 没编进宿主 bundle 时这里会红）
        for key in [
            "module.frontapp.name",
            "module.frontapp.summary",
            "module.frontapp.current",
            "module.frontapp.recent",
            "module.frontapp.emptyRecent",
        ] {
            let localized = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
            XCTAssertNotEqual(localized, key, "\(key) 没解析出文案（catalog 未编进宿主 bundle？）")
            XCTAssertFalse(localized.isEmpty, "\(key) 解析为空串")
        }
    }

    /// 内容分发：`home` → `.view`（当前应用 + 最近切换）；**`.compact` / `.expanded` / `.lockscreen`
    /// 一律 `.none`**（不占位、不算失败——本批的契约，也是"折叠态与展开 tab 没有多出东西"的判据）。
    ///
    /// 块宽走**宿主默认**：模块不声明 `homeBlockWidth`，注册表对"已注册但不声明"同样回 nil
    /// （`HomeStripView` 因此用统一值 180/240，docs/17 D-11）。
    func testFrontAppModuleServesOnlyHomeSurfaceAndFallsBackToHostWidth() async throws {
        let module = FrontAppModule(context: frontAppContext())
        try await module.activate()

        guard case .view = module.content(for: request(.home)) else {
            return XCTFail("home 请求应拿到首页块的 .view（当前应用 + 最近切换）")
        }
        for surface in [Surface.compact, .expanded, .lockscreen] {
            guard case .none = module.content(for: request(surface)) else {
                return XCTFail("\(surface.rawValue) 未声明 → 必须答 .none（不占位）")
            }
        }

        await module.deactivate()
        // `deactivate()` 幂等（06 §3.3 / T3 的 store）：重复调用不崩、也不再摘第二次
        await module.deactivate()

        XCTAssertNil(FrontAppModule.homeBlockWidth, "只有接管模块声明块宽，新增模块不参与宽度决策（docs/17 D-11）")

        // 注册表侧同一条回落（`HomeStripView` 的真实取法）：未注册 → nil；已注册但不声明 → 仍然 nil。
        // 注册表是**单例**，用完 `deactivateAll()` 清干净（别的用例的 setUp 也清，这里不留尾）。
        let registry = ModuleRegistry.shared
        XCTAssertNil(registry.homeBlockWidth(for: FrontAppModule.moduleID), "未注册的 id → nil")
        registry.register([FrontAppModule.self], enabled: { _ in true })
        XCTAssertNil(
            registry.homeBlockWidth(for: FrontAppModule.moduleID),
            "已注册但不声明 → nil（宿主统一值 180/240）"
        )
        await registry.deactivateAll()
    }

    /// `maxRecentApps` 这条线的**读 → 夹**：store 收下模块显式传进来的原样值，夹一次（3…8）
    /// 写进 `recentLimit`——视图拿到的就是这个值（T3 口径 3 的接线由 T4 的模块负责传值）。
    ///
    /// 用**会落盘**的假 config（不碰 `com.cmeng.gourd.module.frontapp` 真实域）：只验读到的值与类型。
    func testFrontAppStoreClampsTheValueTheModulePassesIn() {
        let config = RecordingConfigHandle(schema: ["maxRecentApps"])
        XCTAssertTrue(config.set("maxRecentApps", to: 99))

        let store = FrontAppStore(config: config, logger: frontAppLogger())
        store.start(selfBundleID: "com.cmeng.gourd.test", maxRecentApps: config.get("maxRecentApps", as: Int.self))
        XCTAssertEqual(store.recentLimit, 8, "99 → 夹到上界 8（模块原样传，夹取在 store 那一处）")
        store.deactivate()

        let tight = FrontAppStore(config: RecordingConfigHandle(schema: ["maxRecentApps"]), logger: frontAppLogger())
        tight.start(selfBundleID: nil, maxRecentApps: 1)
        XCTAssertEqual(tight.recentLimit, 3, "1 → 夹到下界 3")
        tight.deactivate()
    }

    // MARK: - 夹具（T2）

    private func logger() -> ModuleLogger {
        ModuleLogger(moduleID: ShortcutsModule.moduleID, shortID: "shortcuts")
    }

    private func request(_ surface: Surface = .expanded) -> ContentRequest {
        ContentRequest(surface: surface, phase: .expanded, reason: .initial)
    }

    /// 模块的 `ModuleContext` 假体（config 是**会落盘**的 `RecordingConfigHandle`，不碰真实域）。
    private func shortcutsContext(config: ConfigHandle? = nil) -> ModuleContext {
        ModuleContext(
            moduleID: ShortcutsModule.moduleID,
            host: HostInfo(appVersion: "0", apiVersion: HostInfo.currentAPIVersion, macOSVersion: "15.0"),
            config: config ?? RecordingConfigHandle(),
            logger: logger(),
            ui: SilentUIHandle()
        )
    }

    /// 前台应用模块的 logger（T4）：`shortID` 只用于拼 subsystem。
    private func frontAppLogger() -> ModuleLogger {
        ModuleLogger(moduleID: FrontAppModule.moduleID, shortID: "frontapp")
    }

    /// 前台应用模块的 `ModuleContext` 假体（T4）：config 给**只认 `maxRecentApps` 的**会落盘假体
    /// （缺键时模块兜 `FrontAppHistory.defaultLimit`），因此**不碰** `com.cmeng.gourd.module.frontapp`。
    private func frontAppContext(config: ConfigHandle? = nil) -> ModuleContext {
        ModuleContext(
            moduleID: FrontAppModule.moduleID,
            host: HostInfo(appVersion: "0", apiVersion: HostInfo.currentAPIVersion, macOSVersion: "15.0"),
            config: config ?? RecordingConfigHandle(schema: ["maxRecentApps"]),
            logger: frontAppLogger(),
            ui: SilentUIHandle()
        )
    }
}

// MARK: - 运行假体（T2 用）

/// **记录型**运行假体：记下每次被调到的 `(identifier, timeout, captureOutput)`，返回构造的结果。
///
/// `onFirstCall` 是并发闸门用例的驱动：第一次被调用时执行一个额外动作（在那里再 `run` 一条），
/// 于是"闸门有没有生效"变成"假体被调了几次"——**不起任何子进程**。
@MainActor
private final class RecordingRunner {
    private(set) var calls: [(identifier: String, timeout: TimeInterval, captureOutput: Bool)] = []
    /// 每次返回的结果（用例按需改：失败 / 超时 / 带输出）。
    var result = ShortcutRunResult(outcome: .success, output: "", failureMessage: "", duration: 0.2)
    /// 第一次被调用时做的额外动作（缺省 nil = 只记一次调用）。
    var onFirstCall: (() async -> Void)?

    func run(identifier: String, timeout: TimeInterval, captureOutput: Bool) async -> ShortcutRunResult {
        calls.append((identifier, timeout, captureOutput))
        if calls.count == 1, let onFirstCall { await onFirstCall() }
        return result
    }
}

/// 最小 `UIHandle` 假体（`ModuleKernelTests` 的 `StubUIHandle` 是 `private`）：
/// 本文件的用例只走 `content(for:)`，没有浮层与收起请求。
@MainActor
private final class SilentUIHandle: UIHandle {
    func requestRedraw() {}
    var isLowPower: Bool { false }
    func presentTransient(view: AnyView, ttl: TimeInterval) {}
    func dismissTransient() {}
    func requestCollapse() {}
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
    /// 每次落盘时的回调（T2 的「先落盘、后发布」判据）：**在写进字典之前**调，
    /// 于是回调里读到的是"写盘那一刻"的状态。若实现改成"只发布不落盘"，它不会被调到。
    var onSet: ((String) -> Void)?

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
        onSet?(key)
        storage[key] = data
        writeLog.append(key)
        return true
    }

    /// 用例侧的便捷读法（等价于 `get(key, as: [String].self)`）。
    func stringList(_ key: String) -> [String]? { get(key, as: [String].self) }
}
