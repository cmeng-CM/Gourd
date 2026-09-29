//
//  ModuleKernelTests.swift
//  Gourd 模块内核 · 类型层单测（P1 批次 / T1）
//
//  覆盖 docs/13-runtime-kernel.md §接口与数据形状：
//  T1 类型层——manifest 校验（每个 ModuleManifestError 分支至少一例）、取值词汇表、
//  权限白名单常量表、config 子集解析、协议可一致性；构造一律走 `ModuleManifest.decode(from:)`
//  （JSON 路径），与宿主读 descriptor 同一条路。
//  T2 注册表与组合根——注册幂等、activate 抛错隔离、启用门、tab 投影、content 降级、
//  `ModuleContextFactory` 的默认值读取、首启默认值幂等、**折叠态中央槽位投影**
//  （`compactEntries` 过滤与排序、`compactSlotContent()` 的转发与无候选回退）。
//  T3 接缝——S2 的 tab 计数（刘海最小宽度的输入）把注册表条目计入总数；S4 的
//  `selectModule(_:)` 同时设 `selectedModuleID` 与 `currentView`。
//  T4 试点模块 progress——进度计算（闰年 2 月 / 季度边界 / 年初年末 / 周起止随日历）、
//  剩余量分档（`remaining`：跨天向上取整 / 跨小时 / 最后一分钟 / 刚过整点）、
//  `visibleScopes` 解析（缺省=日+年 / 非法值忽略 / 顺序按输入）、
//  manifest 与 config 契约、真组合根注册后的 tab 投影与展开内容。
//  T5 待办模块 todos——分类与计数（今日 / 本周 / 所有三档的成员与 `(已办, 总量)`、
//  「无到期时间只进所有」、今日与本周的刻意重叠、本周随 `firstWeekday`）、清单排序、
//  manifest 契约、中央槽位的候选顺序（todos 的 order 20 排在 progress 的 30 之前）。
//  T6 笔记同步过滤——`AppleNotesTrashFilter.isTrashed` 的语言表命中、表外与空串不命中、
//  大小写与首尾空白无关（「最近删除」条目按语言名判定，表外语言保持旧行为）。
//  P2c 通知上岛——相对时间分档边界（<1 分钟 / 59 分钟 / 1 小时 / 23 小时 / 1 天 与时钟回拨）、
//  二进制 plist 的防御式解码（键齐解出 / 缺键给空并记缺失键名 / 垃圾字节与空 data 只记错不崩）、
//  manifest 契约与本地化 key 可解析、组合根的模块投影（三模块 tab 与槽位候选顺序）。
//  **单测不读系统通知库**（构造的二进制 plist 夹具），真实可读性由运行期探针报告判定。
//  P2d 瞬时浮层——`presentHUD` 的覆盖语义与身份更替、`ttl` 夹取到 1…15s、
//  到期**只清自己那一条**（被后来者替换后旧任务让路）与无人接替时自动清除、
//  `UIHandle.presentTransient` 转发到注册表（唯一实现落点）、
//  **主动撤浮层**（`dismissHUD(id:)` 的 id 判据与 `UIHandle.dismissTransient()` 的归属判定）、
//  **浮层窗口宿主的放置几何与尺寸消毒**（D-23：刘海 / 菜单栏内边、居中贴顶、0×0 与非有限值兜底）、
//  **可见性状态机的幂等性**（2026-09-28：首次上台 / 淡出中被接手 / 淡出结束无接手 / 同尺寸重弹 /
//  有接手时不 orderOut——「内置屏偶发只显示第一条」的根因判据）。
//  **浮层的多屏显示**（D-25：`targetScreenNames` 的三种输入口径——全屏模式取全集 /
//  单屏模式「指定屏 → 主屏 → 第一块」三档兜底 / 空屏集合给空集合）。
//  P2d 通知浮层——基线过滤（只有 `rec_id > 基线` 才弹、多条只弹最新一条）、
//  `showBodyInHUD` 的呈现口径（默认 true 显示正文，关掉只剩「新通知」）与键的声明默认值、
//  **卡片尺寸口径**（`notificationHUDScale` 的边界与钳位）、
//  **显示时长口径**（`notificationHUDDurationSeconds` 默认 8s + 设置值 → ttl 的映射与夹取边界）、
//  **配置区口径**（`enableNotificationHUD` 总开关关掉 → 不弹浮层的纯判据、`notificationHUDBackgroundStyle`
//  的默认档与写盘往返）。
//  **主面板背景可配**（D-26：`notchPanelBackgroundStyle` 的默认纯黑 / 三档词汇表 / 写盘往返、
//  `panelBackgroundUsesStyle` 的「玻璃只在展开态与浮动药丸上生效、刘海屏折叠态保持纯黑」四条组合、
//  以及玻璃底顶部的**不透明黑带高度** `panelTopOpaqueBandHeight`：取「刘海高度 / 菜单栏高度」里
//  更高的那个再 +1、异常输入夹到 0——2026-09-28「菜单栏图标被玻璃糊变形」与
//  2026-09-29「顶部比系统黑区窄」的判据）。
//

import AppKit
import ApplicationServices
import Defaults
import SwiftUI
import XCTest

@testable import Gourd

@MainActor
final class ModuleKernelTests: XCTestCase {

    /// 注册表是 `shared` 单例：用例之间必须清空，否则前一个用例注册的模块会污染后一个的
    /// `manifests` / `states`（`deactivateAll()` 停用实例并清空 instances / states / manifests / moduleTypes）。
    override func setUp() async throws {
        try await super.setUp()
        await ModuleRegistry.shared.deactivateAll()
    }

    override func tearDown() async throws {
        await ModuleRegistry.shared.deactivateAll()
        try await super.tearDown()
    }

    // MARK: - 夹具

    /// 合法内置 manifest 的基线：字段与取值对齐 docs/13 §接口与数据形状 + 06 §2.2。
    private enum Fixture {
        static let baseline: [String: Any] = [
            "manifestVersion": 1,
            "id": "com.cmeng.gourd.progress",
            "name": ["key": "module.progress.name"] as [String: Any],
            "summary": ["key": "module.progress.summary"] as [String: Any],
            "icon": ["type": "symbol", "name": "chart.pie"] as [String: Any],
            "version": "1.0.0",
            "apiVersion": "1.0",
            "kind": "builtin",
            "surfaces": ["expanded"],
            "defaultPlacement": ["slot": "center", "order": 30] as [String: Any],
            "defaultEnabled": true,
            "permissions": ["notifications", "network:api.example.com"],
            "config": [
                "type": "object",
                "properties": [
                    "visibleScopes": ["type": "list", "itemType": "string", "default": ["day", "week"]] as [String: Any],
                    "style": ["type": "enum", "default": "ring", "values": ["ring", "bar", "text"]] as [String: Any],
                    "showSeconds": ["type": "boolean", "default": false] as [String: Any],
                    "refreshMinutes": ["type": "integer", "default": 1] as [String: Any],
                    "scale": ["type": "number", "default": 1.5] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
        ]

        static func data(_ overrides: [String: Any] = [:], removing: [String] = []) throws -> Data {
            var object = baseline
            for key in removing { object.removeValue(forKey: key) }
            for (key, value) in overrides { object[key] = value }
            return try JSONSerialization.data(withJSONObject: object)
        }

        static func decode(_ overrides: [String: Any] = [:], removing: [String] = []) throws -> ModuleManifest {
            try ModuleManifest.decode(from: data(overrides, removing: removing))
        }
    }

    /// 断言 manifest 解码失败且错误是某个具体分支（`ModuleManifestError` 九个分支各有其证）。
    private func assertRejects(
        _ overrides: [String: Any] = [:],
        removing: [String] = [],
        equals expected: ModuleManifestError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try Fixture.decode(overrides, removing: removing), file: file, line: line) { error in
            XCTAssertEqual(error as? ModuleManifestError, expected, file: file, line: line)
        }
    }

    private func decodeConfigNode(_ json: String) throws -> ConfigNode {
        try JSONDecoder().decode(ConfigNode.self, from: Data(json.utf8))
    }

    /// `badLocalizedText` 的载荷是给人看的中文描述，断言分支而不是逐个字符串。
    private func assertBadLocalizedText(
        _ overrides: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try Fixture.decode(overrides), file: file, line: line) { error in
            guard let manifestError = error as? ModuleManifestError,
                  case .badLocalizedText = manifestError
            else {
                return XCTFail("期望 badLocalizedText，实到 \(error)", file: file, line: line)
            }
        }
    }

    // MARK: - 合法路径

    func testValidManifestDecodes() throws {
        let manifest = try Fixture.decode()

        XCTAssertEqual(manifest.manifestVersion, 1)
        XCTAssertEqual(manifest.id, "com.cmeng.gourd.progress")
        XCTAssertEqual(manifest.name.key, "module.progress.name")
        XCTAssertNil(manifest.name.table)
        XCTAssertEqual(manifest.summary?.key, "module.progress.summary")
        XCTAssertEqual(manifest.icon, IconSpec(type: "symbol", name: "chart.pie"))
        XCTAssertEqual(manifest.version, "1.0.0")
        XCTAssertEqual(manifest.apiVersion, "1.0")
        XCTAssertEqual(manifest.kind, "builtin")
        XCTAssertEqual(manifest.surfaces, [.expanded])
        XCTAssertEqual(manifest.defaultPlacement?.slot, .center)
        XCTAssertEqual(manifest.defaultPlacement?.order, 30)
        XCTAssertEqual(manifest.defaultEnabled, true)
        XCTAssertEqual(manifest.permissions, ["notifications", "network:api.example.com"])
        XCTAssertEqual(manifest.config?.type, "object")
        XCTAssertEqual(manifest.config?.properties.count, 5)
        XCTAssertNoThrow(try manifest.validate())
    }

    /// `surfaces` 可以只声明 `expanded`（D-12：本批不声明 `lockscreen`）；
    /// 内置模块必须用 `symbol` 图标；`permissions` 可省略（06 §2.2 缺省 `[]`）。
    func testManifestAcceptsMinimalBuiltinShape() throws {
        let manifest = try Fixture.decode(removing: ["summary", "defaultPlacement", "defaultEnabled", "permissions", "config"])
        XCTAssertNil(manifest.summary)
        XCTAssertNil(manifest.defaultPlacement)
        XCTAssertNil(manifest.defaultEnabled)
        XCTAssertTrue(manifest.permissions.isEmpty)
        // `config` 缺省即无 schema——06 §2.2 的默认 `{object, properties:{}}` 对读取侧等价于空表。
        XCTAssertNil(manifest.config)
        XCTAssertEqual(manifest.surfaces, [.expanded])
    }

    /// 插件形态的 locale 表（含 `en`）合法；本批只解析、不渲染。
    func testManifestAcceptsPluginStyleLocalizedText() throws {
        let manifest = try Fixture.decode([
            "name": ["en": "Progress", "zh-Hans": "进度"] as [String: Any],
            "summary": ["en": "Day/week/month/quarter/year progress"] as [String: Any],
        ])
        XCTAssertNil(manifest.name.key)
        XCTAssertEqual(manifest.name.table, ["en": "Progress", "zh-Hans": "进度"])
        XCTAssertEqual(manifest.summary?.table, ["en": "Day/week/month/quarter/year progress"])
    }

    /// D-11：`shortID` 由保留前缀派生；前缀是内置专属，插件不得占用（06 §2.2）。
    func testManifestShortIDAndIDPrefix() throws {
        XCTAssertEqual(try Fixture.decode().shortID, "progress")
        XCTAssertEqual(try Fixture.decode(["id": "com.cmeng.gourd.nowplaying"]).shortID, "nowplaying")

        // 内置缺保留前缀 → badID
        assertRejects(["id": "com.example.pomodoro"], equals: .badID("com.example.pomodoro"))

        // 非内置不得使用保留前缀 → badID（先于 unsupportedKind 报出，见 validate() 顺序）
        assertRejects(["id": "com.cmeng.gourd.fake", "kind": "js"], equals: .badID("com.cmeng.gourd.fake"))

        // 非内置 id 无 shortID 概念：原样返回（绕过 validate 直接解码，隔离该断言）
        let raw = try JSONDecoder().decode(ModuleManifest.self, from: Fixture.data(["id": "com.example.pomodoro"]))
        XCTAssertEqual(raw.shortID, "com.example.pomodoro")
    }

    // MARK: - manifest 校验（每个错误分支至少一例）

    func testManifestRejectsBadManifestVersion() throws {
        assertRejects(["manifestVersion": 2], equals: .badVersion(2))
        assertRejects(["manifestVersion": 0], equals: .badVersion(0))
    }

    func testManifestRejectsBadID() throws {
        // 大写不在 `^[a-z0-9]+(\.[a-z0-9-]+)+$` 内（06 §2.2）
        assertRejects(["id": "com.cmeng.Gourd"], equals: .badID("com.cmeng.Gourd"))
        // 单段（无点）
        assertRejects(["id": "progress"], equals: .badID("progress"))
        // 长度 > 128
        let tooLong = "com.cmeng.gourd." + String(repeating: "a", count: 129)
        assertRejects(["id": tooLong], equals: .badID(tooLong))
    }

    func testManifestRejectsBadAPIVersion() throws {
        // 必须 `^\d+\.\d+$`（不含 patch，06 §8.1）
        assertRejects(["apiVersion": "1"], equals: .badAPIVersion("1"))
        assertRejects(["apiVersion": "1.0.0"], equals: .badAPIVersion("1.0.0"))
        assertRejects(["apiVersion": "v1.0"], equals: .badAPIVersion("v1.0"))
        // major 不符
        assertRejects(["apiVersion": "2.0"], equals: .badAPIVersion("2.0"))
        // minor 超出宿主实现的最高 minor（本批 = 0）
        assertRejects(["apiVersion": "1.1"], equals: .badAPIVersion("1.1"))
    }

    func testManifestRejectsEmptySurfaces() throws {
        assertRejects(["surfaces": [String]()], equals: .emptySurfaces)
    }

    /// surface 取值是封闭词汇表：未知值在解码层就失败，不可能进入 validate（06 §6.1 不新增 `hud`）。
    func testManifestRejectsUnknownSurface() throws {
        let data = try Fixture.data(["surfaces": ["expanded", "hud"]])
        XCTAssertThrowsError(try ModuleManifest.decode(from: data)) { error in
            XCTAssertTrue(error is DecodingError, "期望解码失败，实到 \(error)")
        }
    }

    func testManifestRejectsBadIcon() throws {
        // 内置必须 `symbol`（06 §2.2）
        assertRejects(["icon": ["type": "image"] as [String: Any]], equals: .badIcon("image"))
        assertRejects(["icon": ["type": "appIcon"] as [String: Any]], equals: .badIcon("appIcon"))
        // `symbol` 必须给 name
        assertRejects(["icon": ["type": "symbol"] as [String: Any]], equals: .badIcon("symbol 缺少 name"))
        // `name` 必须能被系统符号表解析（06 §2.4 实测一次）
        let bogus = "gourd.definitely.not.a.symbol"
        assertRejects(["icon": ["type": "symbol", "name": bogus] as [String: Any]], equals: .badIcon(bogus))
    }

    func testManifestRejectsMixedLocalizedText() throws {
        // key 与 locale 表混用（06 §2.3）
        let mixed: [String: Any] = ["key": "module.progress.name", "en": "Progress"]
        assertBadLocalizedText(["name": mixed])

        // locale 表缺 `en`
        let noEnglish: [String: Any] = ["zh-Hans": "进度"]
        assertBadLocalizedText(["name": noEnglish])

        // 空文本（既无 key 也无 locale 表）
        assertBadLocalizedText(["name": [String: Any]()])

        // 长度上限（06 §2.2：name ≤ 40）
        let tooLong: [String: Any] = ["en": String(repeating: "x", count: 41)]
        assertBadLocalizedText(["name": tooLong])

        // 上限内的文本照常通过（约束不是「一律拒绝」）
        XCTAssertNoThrow(try Fixture.decode(["summary": ["en": String(repeating: "y", count: 120)] as [String: Any]]))
    }

    func testManifestRejectsUnknownPermission() throws {
        // 不在 06 §7.1 白名单内
        assertRejects(["permissions": ["clipboard"]], equals: .unknownPermission("clipboard"))
        // 裸 `network` 不合法（06 §7 硬性规则 1：必须 `network:<host>`）
        assertRejects(["permissions": ["network"]], equals: .unknownPermission("network"))
        // 参数为空
        assertRejects(["permissions": ["network:"]], equals: .unknownPermission("network:"))
        assertRejects(["permissions": ["events:subscribe:"]], equals: .unknownPermission("events:subscribe:"))
    }

    /// `kind == builtin` 不得声明 `entry`（06 §2.2 → `E_UNEXPECTED_FIELD`）
    func testManifestRejectsUnexpectedEntry() throws {
        let entry: [String: Any] = ["runtime": "js", "main": "main.js"]
        assertRejects(["entry": entry], equals: .unexpectedEntry)
    }

    /// 本批只允许 `builtin`（插件运行时属 P4）；非内置 id 用合法反域名以免与前缀规则混淆。
    func testManifestRejectsUnsupportedKind() throws {
        assertRejects(["id": "com.example.pomodoro", "kind": "js"], equals: .unsupportedKind("js"))
        assertRejects(["id": "com.example.pomodoro", "kind": "xpc"], equals: .unsupportedKind("xpc"))
    }

    // MARK: - config 子集

    func testManifestParsesConfigSubset() throws {
        let properties = try XCTUnwrap(try Fixture.decode().config?.properties)

        XCTAssertEqual(properties["visibleScopes"]?.type, "list")
        XCTAssertEqual(properties["visibleScopes"]?.itemType, "string")
        XCTAssertEqual(properties["visibleScopes"]?.default, ConfigValue.strings(["day", "week"]))

        XCTAssertEqual(properties["style"]?.type, "enum")
        XCTAssertEqual(properties["style"]?.values, ["ring", "bar", "text"])
        XCTAssertEqual(properties["style"]?.default, ConfigValue.string("ring"))

        XCTAssertEqual(properties["showSeconds"]?.default, ConfigValue.bool(false))
        XCTAssertEqual(properties["refreshMinutes"]?.default, ConfigValue.int(1))
        XCTAssertEqual(properties["scale"]?.default, ConfigValue.double(1.5))
        XCTAssertEqual(properties["scale"]?.type, "number")
    }

    /// 06 §5.3：`default` 在 manifest JSON 里是**裸值**——不是一个带类型标签的对象。
    /// 这条是 `ConfigValue` 必须自定义 `Codable` 的理由，也是它最容易写错的地方。
    func testConfigValueDefaultIsBareJSON() throws {
        XCTAssertEqual(try decodeConfigNode(#"{"type":"string","default":"ring"}"#).default, ConfigValue.string("ring"))
        XCTAssertEqual(try decodeConfigNode(#"{"type":"boolean","default":true}"#).default, ConfigValue.bool(true))
        XCTAssertEqual(try decodeConfigNode(#"{"type":"integer","default":1}"#).default, ConfigValue.int(1))
        XCTAssertEqual(try decodeConfigNode(#"{"type":"number","default":1.5}"#).default, ConfigValue.double(1.5))
        XCTAssertEqual(try decodeConfigNode(#"{"type":"list","default":["a","b"]}"#).default, ConfigValue.strings(["a", "b"]))

        // 整数不得被写成浮点（裸值 `1` 解成 `.int(1)`），否则 `get(_:as:Int.self)` 会静默失败
        XCTAssertNotEqual(try decodeConfigNode(#"{"type":"integer","default":1}"#).default, ConfigValue.double(1))

        // 编码回写同样是裸值（合成编码会产出 {"string":"ring"}）
        let encoded = try JSONEncoder().encode(ConfigValue.string("ring"))
        XCTAssertEqual(String(data: encoded, encoding: .utf8), #""ring""#)

        // 来回一趟不丢形态（同时验证 `default` 的 CodingKey 双向可用）
        let node = try decodeConfigNode(#"{"type":"enum","default":"ring","values":["ring","bar"]}"#)
        XCTAssertEqual(try JSONDecoder().decode(ConfigNode.self, from: JSONEncoder().encode(node)), node)
    }

    // MARK: - 取值词汇表与权限白名单

    /// 06 §3.1 / §6.1 / §6.2 的取值词汇表是本批对外契约（D-02 / D-11：逐字沿用、不得漂移）。
    func testProtocolVocabularyMatchesProtocolDoc() {
        XCTAssertEqual(Surface.allCases.map(\.rawValue), ["compact", "expanded", "lockscreen"])
        XCTAssertEqual(Slot.allCases.map(\.rawValue), ["left", "right", "center"])
        // 四态定死；本批只有 collapsed / expanded 可达（D-04 包装路线，hoverPreview / dragging 属 P1-2）
        XCTAssertEqual(NotchPhase.allCases.map(\.rawValue), ["collapsed", "hoverPreview", "expanded", "dragging"])
        XCTAssertEqual(
            [ContentRequestReason.initial, .event, .configChanged, .tick, .redraw].map(\.rawValue),
            ["initial", "event", "configChanged", "tick", "redraw"]
        )
    }

    /// 06 §7.1 全表 15 行抄成常量：无参数 13 项 + 带参数 2 项。
    func testPermissionCatalogMatchesProtocolDoc() {
        let table = [
            "notifications", "timers", "storage",
            "clipboard:read", "clipboard:write",
            "files:picker", "files:shelf",
            "media:control", "media:read",
            "system:metrics", "power:control",
            "shortcuts:run", "ai:complete",
            "network:<host>", "events:subscribe:<eventName>",
        ]
        XCTAssertEqual(table.count, 15)
        XCTAssertEqual(ModulePermissionCatalog.allCapabilities.count, 15)
        for capability in table {
            XCTAssertTrue(ModulePermissionCatalog.allCapabilities.contains(capability), capability)
        }

        XCTAssertTrue(ModulePermissionCatalog.isKnown("network:api.example.com"))
        XCTAssertTrue(ModulePermissionCatalog.isKnown("events:subscribe:notch.phaseChanged"))
        XCTAssertFalse(ModulePermissionCatalog.isKnown("network"))
        XCTAssertFalse(ModulePermissionCatalog.isKnown("network:"))
        XCTAssertFalse(ModulePermissionCatalog.isKnown("events:subscribe:"))
        XCTAssertFalse(ModulePermissionCatalog.isKnown(""))
    }

    // MARK: - 协议可一致性（GourdModule / ModuleContent / ModuleContext）

    func testModuleProtocolIsUsableWithInjectedContext() throws {
        let stub = StubModule.manifest
        XCTAssertNoThrow(try stub.validate())
        XCTAssertEqual(stub.shortID, "stub")
        XCTAssertEqual(stub.surfaces, [.expanded])

        let ui = StubUIHandle()
        let context = ModuleContext(
            moduleID: stub.id,
            host: HostInfo(appVersion: "0.1.0", apiVersion: HostInfo.currentAPIVersion, macOSVersion: "15.0"),
            config: StubConfigHandle(),
            logger: ModuleLogger(moduleID: stub.id, shortID: stub.shortID),
            ui: ui
        )

        let module = StubModule(context: context)
        XCTAssertEqual(module.context.moduleID, "com.cmeng.gourd.stub")
        XCTAssertEqual(context.host.apiVersion, "1.0")

        let request = ContentRequest(surface: .expanded, phase: .expanded, reason: .initial)
        guard case .unavailable(let reason) = module.content(for: request) else {
            return XCTFail("期望 .unavailable")
        }
        XCTAssertEqual(reason, "stub 未实现内容")

        XCTAssertFalse(context.ui.isLowPower)
        context.ui.requestRedraw()
        XCTAssertEqual(ui.redrawCount, 1)
    }

    // MARK: - 注册表与组合根（T2）

    /// 组合根的启用门**逐字复刻**：`manifests[id]?.defaultEnabled ?? false`（06 §2.2 缺省 false）。
    private func registerProbes(_ types: [any GourdModule.Type]) {
        ModuleRegistry.shared.register(types, enabled: { ModuleRegistry.shared.manifests[$0]?.defaultEnabled ?? false })
    }

    private func request(_ surface: Surface = .expanded) -> ContentRequest {
        ContentRequest(surface: surface, phase: .expanded, reason: .initial)
    }

    private func assertUnavailable(
        _ content: ModuleContent,
        contains id: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .unavailable(let reason) = content else {
            return XCTFail("期望 .unavailable，实到 \(content)", file: file, line: line)
        }
        XCTAssertTrue(reason.contains(id), "降级原因应带上模块 id，实到 \(reason)", file: file, line: line)
    }

    /// 同 id 重复注册被忽略：manifest 只留一份，bootstrap 后实例是**先注册**的那个类型（不被覆盖）。
    func testRegisterIgnoresDuplicateID() async {
        let registry = ModuleRegistry.shared
        registerProbes([AlphaProbeModule.self, AlphaImpostorModule.self])

        XCTAssertEqual(registry.manifests.count, 1, "同 id 重复注册应被忽略")
        XCTAssertNotNil(registry.manifests["com.cmeng.gourd.probe-alpha"])

        await registry.bootstrap()
        XCTAssertEqual(registry.states.count, 1)
        XCTAssertTrue(
            registry.instance(for: "com.cmeng.gourd.probe-alpha") is AlphaProbeModule,
            "后注册的同 id 模块不得覆盖先注册者"
        )
    }

    /// 一个模块 `activate()` 抛错只禁用它自己：其余模块照常激活——含 id 排在它**之后**的模块，
    /// 证明 `bootstrap()` 没有提前返回；`.failed` 是终态，不重试。
    func testRegistryIsolatesFailingModule() async {
        let registry = ModuleRegistry.shared
        registerProbes([AlphaProbeModule.self, BetaProbeModule.self, GammaProbeModule.self])

        await registry.bootstrap()

        XCTAssertEqual(registry.states["com.cmeng.gourd.probe-alpha"], .active)
        // beta 的 id 在 gamma 之前：它抛错后 gamma 仍 active = 循环走完了
        XCTAssertEqual(registry.states["com.cmeng.gourd.probe-gamma"], .active)
        XCTAssertNil(registry.instance(for: "com.cmeng.gourd.probe-beta"), "失败的模块不留实例")

        guard case .failed(let reason)? = registry.states["com.cmeng.gourd.probe-beta"] else {
            return XCTFail("期望 .failed，实到 \(String(describing: registry.states["com.cmeng.gourd.probe-beta"]))")
        }
        XCTAssertFalse(reason.isEmpty)

        // 再 bootstrap 一次：失败的模块不重试、已激活的模块不重复激活
        await registry.bootstrap()
        guard case .failed? = registry.states["com.cmeng.gourd.probe-beta"] else {
            return XCTFail("失败的模块不得被重试")
        }
        XCTAssertEqual(registry.states["com.cmeng.gourd.probe-gamma"], .active)
    }

    /// `defaultEnabled = false` 的模块：不实例化、状态为 `.disabled`、不进 `tabEntries`。
    func testDisabledModuleIsNotActivated() async {
        let registry = ModuleRegistry.shared
        registerProbes([AlphaProbeModule.self, OptInProbeModule.self])

        await registry.bootstrap()

        XCTAssertEqual(registry.states["com.cmeng.gourd.probe-alpha"], .active)
        XCTAssertEqual(registry.states["com.cmeng.gourd.probe-optin"], .disabled)
        XCTAssertNil(registry.instance(for: "com.cmeng.gourd.probe-optin"), "未启用的模块不实例化")
        XCTAssertEqual(registry.tabEntries.map(\.id), ["com.cmeng.gourd.probe-alpha"])
    }

    /// tab 投影 = 只含 `active` 且声明 `.expanded` 的模块，按 `order` 升序、同 `order` 按 id 字典序；
    /// `label` 走 key → `en` 表 → `shortID` 的解析顺序。
    func testTabEntriesReflectRegistryProjection() async {
        let registry = ModuleRegistry.shared
        // 注册顺序与 tab 顺序**故意不一致**：排序不能是注册顺序
        registerProbes([
            DeltaProbeModule.self,
            GammaProbeModule.self,
            OptInProbeModule.self,
            CompactProbeModule.self,
            BetaProbeModule.self,
            AlphaProbeModule.self,
        ])

        await registry.bootstrap()

        XCTAssertEqual(registry.tabEntries.map(\.id), [
            "com.cmeng.gourd.probe-alpha",   // order 10，与 gamma 同序 → id 字典序在前
            "com.cmeng.gourd.probe-gamma",   // order 10
            "com.cmeng.gourd.probe-delta",   // 无 defaultPlacement → Int.max
        ])
        XCTAssertEqual(registry.tabEntries.map(\.order), [10, 10, Int.max])
        XCTAssertEqual(registry.tabEntries.map(\.symbolName), Array(repeating: "square", count: 3))
        // key 形态在 Localizable 里查不到 → 回退 shortID；locale 表形态 → 取 en 文案
        XCTAssertEqual(registry.tabEntries.map(\.label), ["probe-alpha", "Gamma Probe", "probe-delta"])

        // 被过滤的三类：failed（beta）/ disabled（optin）/ 只声明 .compact（compact）
        for id in ["com.cmeng.gourd.probe-beta", "com.cmeng.gourd.probe-optin", "com.cmeng.gourd.probe-compact"] {
            XCTAssertFalse(registry.tabEntries.contains { $0.id == id }, "\(id) 不应进 tab 列表")
        }
        XCTAssertEqual(registry.states.count, 6, "六个模块都被判定过（active / failed / disabled）")
    }

    /// `content(for:request:)` 转发已激活模块；未知 id 与未激活模块（disabled / failed / 未 bootstrap）
    /// 一律 `.unavailable`（不崩、不返回空内容）。
    func testContentUnavailableForInactiveModule() async {
        let registry = ModuleRegistry.shared
        registerProbes([AlphaProbeModule.self, BetaProbeModule.self, OptInProbeModule.self])

        // 已注册但尚未 bootstrap（无状态、无实例）→ unavailable
        assertUnavailable(registry.content(for: "com.cmeng.gourd.probe-alpha", request: request()), contains: "com.cmeng.gourd.probe-alpha")

        await registry.bootstrap()

        // 已激活：转发到实例（夹具返回 `.none`，与注册表的降级 `.unavailable` 可区分）
        guard case .none = registry.content(for: "com.cmeng.gourd.probe-alpha", request: request()) else {
            return XCTFail("期望转发给实例并返回 .none")
        }
        XCTAssertEqual(registry.states["com.cmeng.gourd.probe-alpha"], .active)

        assertUnavailable(registry.content(for: "com.cmeng.gourd.probe-optin", request: request()), contains: "com.cmeng.gourd.probe-optin")
        assertUnavailable(registry.content(for: "com.cmeng.gourd.probe-beta", request: request()), contains: "com.cmeng.gourd.probe-beta")
        // 未知 id：返回 unavailable 而不是崩溃
        assertUnavailable(registry.content(for: "com.cmeng.gourd.probe-ghost", request: request()), contains: "com.cmeng.gourd.probe-ghost")
    }

    /// `ModuleContextFactory`：host 从宿主取、config 读 manifest 默认值（含 `number` 节点整数默认值的
    /// int→Double 互认）、覆盖值落模块专属 suite、`requestRedraw` 转发注入闭包。
    func testModuleContextConfigReadsManifestDefault() throws {
        let suiteName = "com.cmeng.gourd.module.probe-config"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)      // 前置：清掉上次运行留下的覆盖值
        defer { suite.removePersistentDomain(forName: suiteName) }

        let manifest = try ModuleManifest.decode(from: Data(#"""
        {
          "manifestVersion": 1,
          "id": "com.cmeng.gourd.probe-config",
          "name": {"key": "module.probe-config.name"},
          "icon": {"type": "symbol", "name": "square"},
          "version": "1.0.0",
          "apiVersion": "1.0",
          "kind": "builtin",
          "surfaces": ["expanded"],
          "config": {
            "type": "object",
            "properties": {
              "scale": {"type": "number", "default": 2},
              "ratio": {"type": "number", "default": 1.5},
              "refreshMinutes": {"type": "integer", "default": 1},
              "style": {"type": "enum", "default": "ring", "values": ["ring", "bar"]},
              "showSeconds": {"type": "boolean", "default": false},
              "visibleScopes": {"type": "list", "itemType": "string", "default": ["day", "week"]}
            }
          }
        }
        """#.utf8))

        let probe = RedrawProbe()
        let context = ModuleContextFactory.make(manifest: manifest, redraw: { probe.count += 1 })

        XCTAssertEqual(context.moduleID, "com.cmeng.gourd.probe-config")
        XCTAssertEqual(context.host.apiVersion, "1.0")
        XCTAssertEqual(context.host.appVersion, Bundle.main.releaseVersionNumber ?? "0")
        XCTAssertEqual(context.host.macOSVersion, ModuleContextFactory.macOSVersion)

        // manifest 默认值（本批唯一默认值来源）
        XCTAssertEqual(context.config.get("refreshMinutes", as: Int.self), 1)
        XCTAssertEqual(context.config.get("style", as: String.self), "ring")
        XCTAssertEqual(context.config.get("showSeconds", as: Bool.self), false)
        XCTAssertEqual(context.config.get("visibleScopes", as: [String].self), ["day", "week"])
        XCTAssertEqual(context.config.get("ratio", as: Double.self), 1.5)
        // `{"type":"number","default":2}` 的裸值落成 `.int(2)`：`get(_:as: Double.self)` 必须互认，
        // 否则 `number` 型的整数默认值会静默返回 nil
        XCTAssertEqual(context.config.get("scale", as: Double.self), 2.0)
        // schema 之外的键读不到（不崩）
        XCTAssertNil(context.config.get("undeclared", as: String.self))

        // 覆盖值：落模块专属 suite、优先于默认值；未声明的键不落盘
        XCTAssertTrue(context.config.set("refreshMinutes", to: 30))
        XCTAssertEqual(context.config.get("refreshMinutes", as: Int.self), 30)
        let readBack = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertNotNil(readBack.data(forKey: "refreshMinutes"), "覆盖值应落在 com.cmeng.gourd.module.<shortID>")
        XCTAssertFalse(context.config.set("undeclared", to: 1))
        XCTAssertNil(readBack.object(forKey: "undeclared"))

        // 覆盖值清掉后回到 manifest 默认值
        readBack.removeObject(forKey: "refreshMinutes")
        XCTAssertEqual(context.config.get("refreshMinutes", as: Int.self), 1)

        // UIHandle：转发注入闭包、isLowPower 恒 false
        XCTAssertFalse(context.ui.isLowPower)
        context.ui.requestRedraw()
        context.ui.requestRedraw()
        XCTAssertEqual(probe.count, 2)
    }

    /// 首启默认值**一次性、幂等**：闸门键为真后不再覆盖用户手动改回的值。
    func testFirstLaunchDefaultsIdempotent() {
        let defaults = UserDefaults.standard
        // 闸门键（接缝 S7）定义在 `Constants.swift` 的 `Defaults.Keys` 里：用例取 Key 名做
        // `UserDefaults` 原值快照/还原，不再有第二处字面量。
        let flagKey = Defaults.Keys.gourdFirstLaunchDefaultsApplied.name
        // TEST_HOST = Gourd.app：这里改的是开发者机器上真实的 app defaults，用例改过的键全部还原
        let originalFlag = defaults.object(forKey: flagKey)
        let originalScreenAssistant = defaults.object(forKey: "enableScreenAssistant")
        defer {
            if let originalFlag {
                defaults.set(originalFlag, forKey: flagKey)
            } else {
                defaults.removeObject(forKey: flagKey)
            }
            if let originalScreenAssistant {
                defaults.set(originalScreenAssistant, forKey: "enableScreenAssistant")
            } else {
                defaults.removeObject(forKey: "enableScreenAssistant")
            }
        }

        // 前置：模拟「从未首启」+ 上游默认值 true
        defaults.removeObject(forKey: flagKey)
        defaults.set(true, forKey: "enableScreenAssistant")

        KernelBootstrap.applyFirstLaunchDefaults()
        XCTAssertFalse(defaults.bool(forKey: "enableScreenAssistant"), "首启应关掉 enableScreenAssistant")
        XCTAssertTrue(defaults.bool(forKey: flagKey), "首启应落闸门键")

        // 用户随后手动打开 → 第二次调用不得再覆盖（幂等）
        defaults.set(true, forKey: "enableScreenAssistant")
        KernelBootstrap.applyFirstLaunchDefaults()
        XCTAssertTrue(defaults.bool(forKey: "enableScreenAssistant"), "已应用过 → 第二次调用必须原样返回")
    }

    // MARK: - 接缝（T3）

    /// 接缝 S2：`enabledStandardTabCount()`（刘海最小宽度的输入）必须把注册表 tab 计入总数。
    ///
    /// 断言用**增量**而非绝对值：上游那 6 个标准 tab 由开发机上的真实 Defaults 决定，
    /// 只有增量能把「注册表条目被计入」与「Default 开关恰好这样」分开。注册表为空时该数
    /// 必须回到基线——否则 S2 读的就不是 `tabEntries`（清空后应当归零）。
    func testEnabledStandardTabCountIncludesActiveModuleEntries() async {
        let baseline = enabledStandardTabCount()

        registerProbes([
            AlphaProbeModule.self,     // active + 声明 .expanded → 计入
            GammaProbeModule.self,     // active + 声明 .expanded → 计入
            DeltaProbeModule.self,     // active + 声明 .expanded → 计入
            BetaProbeModule.self,      // activate 抛错 → failed，不计入
            CompactProbeModule.self,   // 只声明 .compact，不计入
            OptInProbeModule.self,     // defaultEnabled=false → disabled，不计入
        ])
        await ModuleRegistry.shared.bootstrap()

        let entries = ModuleRegistry.shared.tabEntries
        XCTAssertEqual(entries.count, 3, "投影只含 active 且声明 .expanded 的模块")
        XCTAssertEqual(
            enabledStandardTabCount(),
            baseline + entries.count,
            "S2 必须把注册表条目计入总数（恰好多 N，而不是只多了一个词）"
        )

        // 反向：注册表清空 → 回到基线（S2 的增量只来自 tabEntries）
        await ModuleRegistry.shared.deactivateAll()
        XCTAssertEqual(enabledStandardTabCount(), baseline, "注册表清空后必须回到基线")
    }

    /// 接缝 S4：`selectModule(_:)` 必须**同时**设 `selectedModuleID` 与 `currentView = .module`。
    ///
    /// 两个都要：只设 `currentView` 会让内容区拿不到模块 id 而渲染 EmptyView（S1 ④ 的失败模式）；
    /// 只设 id 则 tab 选中态（`isSelected` 比 id）与内容区不同步。
    func testSelectModuleSetsSelectedIDAndView() {
        let coordinator = DynamicIslandViewCoordinator.shared
        let originalID = coordinator.selectedModuleID
        let originalView = coordinator.currentView
        // 上游 `currentView.didSet` 在极简模式下会把非 `.home` 的选中强制回 `.home`；
        // 用例把该开关压到 false 再断言，结束还原原值（只影响本用例窗口期）。
        let originalMinimalistic = Defaults[.enableMinimalisticUI]
        defer {
            Defaults[.enableMinimalisticUI] = originalMinimalistic
            coordinator.selectedModuleID = originalID
            coordinator.currentView = originalView
        }
        Defaults[.enableMinimalisticUI] = false

        coordinator.selectModule("com.cmeng.gourd.probe-alpha")

        XCTAssertEqual(coordinator.selectedModuleID, "com.cmeng.gourd.probe-alpha")
        XCTAssertEqual(coordinator.currentView, .module, "selectModule 必须把 currentView 切到 .module")
    }

    // MARK: - 试点模块 progress（T4）

    /// 固定日历：不读开发机的时区 / 语言 / 周起始日，断言才可复现。
    private func fixedGregorian(timeZone: String = "Asia/Shanghai", firstWeekday: Int = 2) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: timeZone))
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    /// 构造注入用的固定「现在」（按给定日历的时区解释）。
    private func instant(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0,
        calendar: Calendar
    ) throws -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = calendar.timeZone
        return try XCTUnwrap(calendar.date(from: components), "构造日期失败：\(year)-\(month)-\(day)")
    }

    /// D-07 的进度计算：断言覆盖闰年 2 月、季度边界（3/31、4/1、12/31）、年初年末、
    /// 周进度在周一 / 周日两侧——一律「注入固定 now + 固定时区日历」，结论只依赖 `Calendar` 语义。
    func testProgressCalculation() throws {
        let calendar = try fixedGregorian()

        // 日：正午恰好一半；00:00 归零
        XCTAssertEqual(
            ProgressCalculator.progress(for: .day, now: try instant(2026, 3, 31, 12, calendar: calendar), calendar: calendar),
            0.5, accuracy: 1e-9
        )
        XCTAssertEqual(
            ProgressCalculator.progress(for: .day, now: try instant(2026, 3, 31, calendar: calendar), calendar: calendar),
            0, accuracy: 1e-9
        )

        // 闰年 2 月：区间总长由 `Calendar` 定（2024 = 29 天、2023 = 28 天），不手算天数
        let leapDayNoon = try instant(2024, 2, 29, 12, calendar: calendar)
        XCTAssertEqual(
            try XCTUnwrap(ProgressCalculator.interval(for: .month, now: leapDayNoon, calendar: calendar)).duration,
            29.0 * 86_400, accuracy: 1
        )
        XCTAssertEqual(ProgressCalculator.progress(for: .month, now: leapDayNoon, calendar: calendar), 28.5 / 29, accuracy: 1e-9)
        XCTAssertEqual(
            try XCTUnwrap(ProgressCalculator.interval(for: .month, now: try instant(2023, 2, 28, 12, calendar: calendar), calendar: calendar)).duration,
            28.0 * 86_400, accuracy: 1
        )
        // 跨月边界：闰日多出来的那天在 3/1 00:00 之后才计入
        XCTAssertEqual(
            ProgressCalculator.progress(for: .month, now: try instant(2024, 3, 1, calendar: calendar), calendar: calendar),
            0, accuracy: 1e-9
        )
        // 年尺度也跟着 `Calendar` 走：闰年 366 天
        XCTAssertEqual(
            try XCTUnwrap(ProgressCalculator.interval(for: .year, now: try instant(2024, 6, 1, calendar: calendar), calendar: calendar)).duration,
            366.0 * 86_400, accuracy: 1
        )

        // 季度边界 3/31：Q1 = [1/1, 4/1)，1–3 月 = 90 天；3/31 00:00 = 89/90，最后一分钟仍 < 1
        let q1 = try XCTUnwrap(ProgressCalculator.interval(for: .quarter, now: try instant(2026, 3, 31, calendar: calendar), calendar: calendar))
        XCTAssertEqual(q1.start, try instant(2026, 1, 1, calendar: calendar))
        XCTAssertEqual(q1.end, try instant(2026, 4, 1, calendar: calendar))
        XCTAssertEqual(
            ProgressCalculator.progress(for: .quarter, now: try instant(2026, 3, 31, calendar: calendar), calendar: calendar),
            89.0 / 90.0, accuracy: 1e-9
        )
        let q1LastMinute = ProgressCalculator.progress(for: .quarter, now: try instant(2026, 3, 31, 23, 59, calendar: calendar), calendar: calendar)
        XCTAssertGreaterThan(q1LastMinute, 89.0 / 90.0)
        XCTAssertLessThan(q1LastMinute, 1)

        // 季度边界 4/1：落到 Q2 的起点（0）
        let q2Start = try instant(2026, 4, 1, calendar: calendar)
        let q2 = try XCTUnwrap(ProgressCalculator.interval(for: .quarter, now: q2Start, calendar: calendar))
        XCTAssertEqual(q2.start, q2Start)
        XCTAssertEqual(q2.end, try instant(2026, 7, 1, calendar: calendar))
        XCTAssertEqual(ProgressCalculator.progress(for: .quarter, now: q2Start, calendar: calendar), 0, accuracy: 1e-9)

        // 季度边界 12/31：Q4 = [10/1, **次年** 1/1)，跨年边界仍由 `Calendar` 给；10–12 月 = 92 天
        let q4Mid = try instant(2026, 12, 31, 12, calendar: calendar)
        let q4 = try XCTUnwrap(ProgressCalculator.interval(for: .quarter, now: q4Mid, calendar: calendar))
        XCTAssertEqual(q4.start, try instant(2026, 10, 1, calendar: calendar))
        XCTAssertEqual(q4.end, try instant(2027, 1, 1, calendar: calendar))
        XCTAssertEqual(ProgressCalculator.progress(for: .quarter, now: q4Mid, calendar: calendar), 91.5 / 92, accuracy: 1e-9)

        // 年初 / 年末：1/1 00:00 归零、12/31 23:59:59 尚未到 1、次日 00:00 已是新年
        XCTAssertEqual(
            ProgressCalculator.progress(for: .year, now: try instant(2026, 1, 1, calendar: calendar), calendar: calendar),
            0, accuracy: 1e-9
        )
        let yearEnd = try instant(2026, 12, 31, 23, 59, 59, calendar: calendar)
        let yearProgress = ProgressCalculator.progress(for: .year, now: yearEnd, calendar: calendar)
        XCTAssertGreaterThan(yearProgress, 0.9999)
        XCTAssertLessThan(yearProgress, 1)
        XCTAssertEqual(
            try XCTUnwrap(ProgressCalculator.interval(for: .year, now: yearEnd, calendar: calendar)).duration,
            365.0 * 86_400, accuracy: 1
        )
        XCTAssertEqual(
            ProgressCalculator.progress(for: .year, now: try instant(2027, 1, 1, calendar: calendar), calendar: calendar),
            0, accuracy: 1e-9
        )

        // 周（周一为首日）：2026-03-29 是周日，落在 [3/23, 3/30) 的第 6.5 天
        let mondayFirst = try fixedGregorian(firstWeekday: 2)
        let sundayNoon = try instant(2026, 3, 29, 12, calendar: mondayFirst)
        let mondayFirstWeek = try XCTUnwrap(ProgressCalculator.interval(for: .week, now: sundayNoon, calendar: mondayFirst))
        XCTAssertEqual(mondayFirstWeek.start, try instant(2026, 3, 23, calendar: mondayFirst))
        XCTAssertEqual(mondayFirstWeek.end, try instant(2026, 3, 30, calendar: mondayFirst))
        XCTAssertEqual(ProgressCalculator.progress(for: .week, now: sundayNoon, calendar: mondayFirst), 6.5 / 7, accuracy: 1e-9)
        // 周一 00:00 是新的周起点 → 归零，一小时后重新推进
        XCTAssertEqual(
            ProgressCalculator.progress(for: .week, now: try instant(2026, 3, 30, calendar: mondayFirst), calendar: mondayFirst),
            0, accuracy: 1e-9
        )
        XCTAssertEqual(
            ProgressCalculator.progress(for: .week, now: try instant(2026, 3, 30, 1, calendar: mondayFirst), calendar: mondayFirst),
            1.0 / (7 * 24), accuracy: 1e-9
        )

        // 周（**周日**为首日）：起止随日历走，不假定周一——同一个周日（3/29）成了新周的第 0.5 天，
        // 而在周一为首日时它已是那一周的第 6.5 天（同刻不同位，两个日历各自成立）
        let sundayFirst = try fixedGregorian(firstWeekday: 1)
        let sundayFirstWeek = try XCTUnwrap(
            ProgressCalculator.interval(for: .week, now: try instant(2026, 3, 29, 12, calendar: sundayFirst), calendar: sundayFirst)
        )
        XCTAssertEqual(sundayFirstWeek.start, try instant(2026, 3, 29, calendar: sundayFirst))
        XCTAssertEqual(sundayFirstWeek.end, try instant(2026, 4, 5, calendar: sundayFirst))
        XCTAssertEqual(
            ProgressCalculator.progress(for: .week, now: try instant(2026, 3, 29, 12, calendar: sundayFirst), calendar: sundayFirst),
            0.5 / 7, accuracy: 1e-9
        )
        // 同一时刻（2026-03-30 周一 12:00）在两种日历下落在不同的周内位置：
        // 周日起首 = 第 1.5 天，周一为首日 = 第 0.5 天
        XCTAssertEqual(
            ProgressCalculator.progress(for: .week, now: try instant(2026, 3, 30, 12, calendar: sundayFirst), calendar: sundayFirst),
            1.5 / 7, accuracy: 1e-9
        )
        XCTAssertEqual(
            ProgressCalculator.progress(for: .week, now: try instant(2026, 3, 30, 12, calendar: mondayFirst), calendar: mondayFirst),
            0.5 / 7, accuracy: 1e-9
        )
    }

    /// `remaining` 的分档边界（09 §5.3 剩余量）：跨天（≥ 1 天，**向上取整**）、
    /// 跨小时（1 小时 ≤ r < 1 天，整点截断）、最后一分钟（截断且至少 1）、刚过整点（区间起点重新计数）。
    /// 回归测试（2026-09-28）：小时档必须**成对**取值。
    ///
    /// 修复前的显示是「剩 13 小时 826 分钟」——`remaining()` 给整点小时、另一个函数给**总分钟**，
    /// 两者口径不一致（826 = 13×60 + 46）。这条用例把"余分钟必须落在 0…59 且与整点小时同源"钉住。
    func testProgressRemainingHoursAndMinutesArePaired() throws {
        let calendar = try fixedGregorian()

        // 10:14 → 当天 24:00 剩 13 小时 46 分（修复前分钟位会显示 826）
        let pair = ProgressCalculator.remainingHoursAndMinutes(
            for: .day, now: try instant(2026, 9, 28, 10, 14, calendar: calendar), calendar: calendar
        )
        XCTAssertEqual(pair.hours, 13)
        XCTAssertEqual(pair.minutes, 46)

        // 余分钟永不越界：全天逐刻扫一遍，分钟位必须恒在 0…59
        for minute in stride(from: 0, to: 24 * 60, by: 7) {
            let now = try instant(2026, 9, 28, minute / 60, minute % 60, calendar: calendar)
            let p = ProgressCalculator.remainingHoursAndMinutes(for: .day, now: now, calendar: calendar)
            XCTAssertTrue((0...59).contains(p.minutes), "分钟位越界：\(p)")
            XCTAssertEqual(p.hours * 60 + p.minutes, 24 * 60 - minute, "小时/分钟不同源：\(p)")
        }
    }

    func testProgressRemainingBoundaries() throws {
        let calendar = try fixedGregorian()

        // 跨天：年尺度剩 95 整日；同一天的正午「余量算一天」仍是 95（向上取整）
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .year, now: try instant(2026, 9, 28, calendar: calendar), calendar: calendar).value,
            95
        )
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .year, now: try instant(2026, 9, 28, 12, calendar: calendar), calendar: calendar).value,
            95
        )
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .year, now: try instant(2026, 9, 28, calendar: calendar), calendar: calendar).unit,
            .day
        )
        // 刚过整点：区间起点（元旦 00:00）剩满一年 365 天；日尺度 00:00 剩满 24 小时 = 1 天
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .year, now: try instant(2026, 1, 1, calendar: calendar), calendar: calendar).value,
            365
        )
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .day, now: try instant(2026, 9, 27, calendar: calendar), calendar: calendar).value,
            1
        )
        // 刚过整点 + 30 秒：不足 1 整日 → 落到小时档（23 小时 59 分）
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .day, now: try instant(2026, 9, 27, 0, 0, 30, calendar: calendar), calendar: calendar).value,
            23
        )
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .day, now: try instant(2026, 9, 27, 0, 0, 30, calendar: calendar), calendar: calendar).unit,
            .hour
        )

        // 跨小时：2 小时 / 1 小时 30 分都落小时档（整点截断，分钟余量由视图从同一区间拼）
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .day, now: try instant(2026, 9, 27, 22, calendar: calendar), calendar: calendar).value,
            2
        )
        let hourAndHalf = ProgressCalculator.remaining(for: .day, now: try instant(2026, 9, 27, 22, 30, calendar: calendar), calendar: calendar)
        XCTAssertEqual(hourAndHalf.value, 1)
        XCTAssertEqual(hourAndHalf.unit, .hour)
        // 恰好 1 小时：整点边界仍算小时档
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .day, now: try instant(2026, 9, 27, 23, calendar: calendar), calendar: calendar).unit,
            .hour
        )
        // 月末最后半天 / 周日的最后半天：同一条规则（12 小时、18 小时）
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .month, now: try instant(2026, 9, 30, 12, calendar: calendar), calendar: calendar).value,
            12
        )
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .week, now: try instant(2026, 3, 29, 12, calendar: calendar), calendar: calendar).value,
            12
        )

        // 最后一分钟：不足 1 分钟时截断为 0，**至少给 1**；59 分 30 秒仍是 59（不越到小时档）
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .day, now: try instant(2026, 9, 27, 23, 59, 30, calendar: calendar), calendar: calendar).value,
            1
        )
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .day, now: try instant(2026, 9, 27, 23, 59, 30, calendar: calendar), calendar: calendar).unit,
            .minute
        )
        let almostAnHour = ProgressCalculator.remaining(for: .day, now: try instant(2026, 9, 27, 23, 0, 30, calendar: calendar), calendar: calendar)
        XCTAssertEqual(almostAnHour.value, 59)
        XCTAssertEqual(almostAnHour.unit, .minute)

        // 年末最后一天：00:00 剩 1 整天（天档），正午只剩 12 小时（小时档）——分档按剩余量而非日期
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .year, now: try instant(2026, 12, 31, calendar: calendar), calendar: calendar).unit,
            .day
        )
        XCTAssertEqual(
            ProgressCalculator.remaining(for: .year, now: try instant(2026, 12, 31, 12, calendar: calendar), calendar: calendar).unit,
            .hour
        )
    }

    /// `visibleScopes` 解析（纯函数）：缺省 / 非 list / 空 / 全非法 → **日 + 年**；
    /// 非法值逐项忽略；顺序按输入；重复项去重。manifest 的默认值本身也是「日 + 年」。
    func testProgressVisibleScopesResolution() {
        XCTAssertEqual(ProgressCalculator.defaultVisibleScopes, [.day, .year])
        XCTAssertEqual(ProgressCalculator.resolveScopes(from: nil), [.day, .year], "缺省 → 日 + 年")
        XCTAssertEqual(ProgressCalculator.resolveScopes(from: .string("day")), [.day, .year], "不是 list → 回落默认")
        XCTAssertEqual(ProgressCalculator.resolveScopes(from: .strings([])), [.day, .year], "空列表 → 回落默认")
        XCTAssertEqual(
            ProgressCalculator.resolveScopes(from: .strings(["bogus", "Week"])),
            [.day, .year],
            "全非法（含大小写不符的取值）→ 回落默认"
        )

        XCTAssertEqual(ProgressCalculator.resolveScopes(from: .strings(["year", "month"])), [.year, .month], "顺序按输入")
        XCTAssertEqual(
            ProgressCalculator.resolveScopes(from: .strings(["day", "bogus", "year"])),
            [.day, .year],
            "非法值逐项忽略，剩下的按输入顺序"
        )
        XCTAssertEqual(
            ProgressCalculator.resolveScopes(from: .strings(["week", "week", "day"])),
            [.week, .day],
            "重复项去重且保留首次出现的位置"
        )

        XCTAssertEqual(
            ProgressCalculator.resolveScopes(from: ProgressModule.manifest.config?.properties["visibleScopes"]?.default),
            [.day, .year],
            "manifest 的 visibleScopes 默认值即出厂展示尺度"
        )
    }

    /// 行首图标的符号名必须能被系统符号表解析（否则面板上那一行只剩空白）。
    func testProgressScopeSymbolsResolve() {
        for scope in ProgressCalculator.Scope.allCases {
            XCTAssertNotNil(
                NSImage(systemSymbolName: scope.symbolName, accessibilityDescription: nil),
                "\(scope.rawValue) 的图标 \(scope.symbolName) 不是可解析的 SF Symbol"
            )
        }
    }

    /// `ProgressModule.manifest` 的契约：id / surfaces / icon / defaultEnabled / 三项 config
    /// 的类型、取值与默认值；并回走一次 JSON 路径（与宿主读 descriptor 同一条路）。
    func testProgressModuleManifestMatchesContract() throws {
        let manifest = ProgressModule.manifest
        XCTAssertNoThrow(try manifest.validate())

        XCTAssertEqual(manifest.id, "com.cmeng.gourd.progress")
        XCTAssertEqual(manifest.shortID, "progress")
        XCTAssertEqual(manifest.name.key, "module.progress.name")
        XCTAssertEqual(manifest.summary?.key, "module.progress.summary")
        XCTAssertEqual(manifest.icon, IconSpec(type: "symbol", name: "chart.pie"))
        XCTAssertEqual(manifest.kind, "builtin")
        XCTAssertEqual(manifest.surfaces, [.compact, .expanded], "折叠态中央槽位 + 展开面板清单")
        // 2026-09-28 用户判定「时间进度」无行动价值 → 默认关（代码保留），中央槽位默认内容改由 todos 承担
        XCTAssertEqual(manifest.defaultEnabled, false, "progress 默认关（13 号文档 D-20）")
        XCTAssertEqual(manifest.defaultPlacement?.order, 30)
        XCTAssertEqual(manifest.defaultPlacement?.slot, .center, "声明 compact 后 slot 记 center（06 §6.2）")
        XCTAssertTrue(manifest.permissions.isEmpty, "09 §5.3：progress 无权限")

        let properties = try XCTUnwrap(manifest.config?.properties)
        XCTAssertEqual(properties["visibleScopes"]?.type, "list")
        XCTAssertEqual(properties["visibleScopes"]?.itemType, "string")
        XCTAssertEqual(
            properties["visibleScopes"]?.default,
            ConfigValue.strings(["day", "year"]),
            "09 §5.3 呈现行定稿：出厂只显示 日 + 年"
        )
        XCTAssertEqual(properties["style"]?.type, "enum")
        XCTAssertEqual(properties["style"]?.values, ["ring", "bar", "text"])
        XCTAssertEqual(properties["style"]?.default, ConfigValue.string("ring"))
        XCTAssertEqual(properties["baseCalendar"]?.type, "enum")
        XCTAssertEqual(properties["baseCalendar"]?.values, ["gregorian", "chinese"])
        XCTAssertEqual(properties["baseCalendar"]?.default, ConfigValue.string("gregorian"))

        // 字面量 manifest 也能走 JSON：编码 → `decode(from:)`（含 validate）→ 相等
        XCTAssertEqual(try ModuleManifest.decode(from: try JSONEncoder().encode(manifest)), manifest)
    }

    /// T4/T5 的端到端：`KernelBootstrap.builtinModules` 里的**真模块**经真组合根注册 → 过启用门 →
    /// 激活 → 进 tab 投影 → 内容请求拿到 `.view`。
    ///
    /// 两段：① 走**真启用门**（`defaultEnabled`）——todos 默认开、progress 默认关（D-20）；
    /// ② 手动全放行重注册一次，保住 progress 的内容路径覆盖（它是「两条 surface + lockscreen 降级」
    /// 的样本）。`module.progress.name` / `module.todos.name` 必须能从宿主 bundle 解析出文案
    /// （06 §3.3 R5 的 key 形态）。
    /// （激活失败隔离等机制由假模块覆盖，见 T2 的用例；`register` 本身不校验 manifest，
    /// 所以这里显式对真模块的 manifest 跑一次 `validate()`。）
    ///
    /// **这条用例的 `count == 2` 与逐项 `ObjectIdentifier` 断言是批内契约**（13 号文档已知限制 22）：
    /// 加第三个内置模块时会红，按该条的口径一并放宽。
    func testKernelBootstrapRegistersBuiltinModulesAndServesExpandedContent() async throws {
        // `bootstrap()` 会落首启默认值：把闸门先置真让它提前返回（用例结束还原原值），
        // 避免改开发机上真实的 `enableScreenAssistant`。
        let defaults = UserDefaults.standard
        let flagKey = Defaults.Keys.gourdFirstLaunchDefaultsApplied.name
        let originalFlag = defaults.object(forKey: flagKey)
        defer {
            if let originalFlag {
                defaults.set(originalFlag, forKey: flagKey)
            } else {
                defaults.removeObject(forKey: flagKey)
            }
        }
        defaults.set(true, forKey: flagKey)

        XCTAssertEqual(KernelBootstrap.builtinModules.count, 3, "A3：内置模块清单 = 三行（progress + todos + notifications）")
        XCTAssertEqual(
            KernelBootstrap.builtinModules.map { ObjectIdentifier($0) },
            [
                ObjectIdentifier(ProgressModule.self),
                ObjectIdentifier(TodosModule.self),
                ObjectIdentifier(NotificationsModule.self),
            ],
            "builtinModules 里应是 ProgressModule、TodosModule 与 NotificationsModule"
        )
        for type in KernelBootstrap.builtinModules {
            XCTAssertNoThrow(try type.manifest.validate(), "真模块的 manifest 必须过校验")
        }

        await KernelBootstrap.bootstrap()

        let registry = ModuleRegistry.shared
        let id = "com.cmeng.gourd.progress"
        let todosID = "com.cmeng.gourd.todos"
        let notificationsID = "com.cmeng.gourd.notifications"

        // ① 真启用门逐字取 `defaultEnabled`：todos 与 notifications 默认开、progress 默认关（D-20）
        XCTAssertEqual(registry.states[todosID], .active)
        XCTAssertEqual(registry.states[notificationsID], .active)
        XCTAssertEqual(registry.states[id], .disabled, "progress 默认关（D-20），启用门不放行")
        XCTAssertNil(registry.instance(for: id), "disabled 的模块不实例化")
        XCTAssertNotNil(registry.instance(for: todosID) as? TodosModule)
        XCTAssertNotNil(registry.instance(for: notificationsID) as? NotificationsModule)

        // 投影里只剩已激活的两个（未激活的 progress 不进 tab、不进槽位候选），
        // 槽位内容 = todos 的视图；对 progress 的内容请求按 06 §3.2 降级为 `.unavailable`
        XCTAssertEqual(registry.tabEntries.map(\.id), [todosID, notificationsID])
        XCTAssertEqual(registry.compactEntries.map(\.id), [todosID, notificationsID])
        guard case .view = registry.compactSlotContent() else {
            return XCTFail("折叠态中央槽位应拿到 todos 的 .view 内容")
        }
        guard case .view = registry.content(for: todosID, request: request(.expanded)) else {
            return XCTFail("todos 的展开请求应拿到 .view")
        }
        guard case .view = registry.content(for: todosID, request: request(.compact)) else {
            return XCTFail("todos 声明了 compact，应返回 .view")
        }
        guard case .none = registry.content(for: todosID, request: request(.lockscreen)) else {
            return XCTFail("todos 未声明 lockscreen，应返回 .none")
        }
        // 通知上岛：expanded（列表）/ compact（未读数）各一份内容，lockscreen 不占位
        guard case .view = registry.content(for: notificationsID, request: request(.expanded)) else {
            return XCTFail("notifications 的展开请求应拿到 .view")
        }
        guard case .view = registry.content(for: notificationsID, request: request(.compact)) else {
            return XCTFail("notifications 声明了 compact，应返回 .view")
        }
        guard case .none = registry.content(for: notificationsID, request: request(.lockscreen)) else {
            return XCTFail("notifications 未声明 lockscreen，应返回 .none")
        }
        guard case .unavailable = registry.content(for: id, request: request(.expanded)) else {
            return XCTFail("未激活的 progress 应降级为 .unavailable")
        }

        // ② 手动全放行（模拟用户显式开启 progress）后重注册：三个模块都 active
        await registry.deactivateAll()
        registry.register(KernelBootstrap.builtinModules, enabled: { _ in true })
        await registry.bootstrap()

        XCTAssertEqual(registry.states[id], .active)
        XCTAssertNotNil(registry.instance(for: id) as? ProgressModule)

        // tab / 槽位候选都按 `order` 升序：todos（20）→ progress（30）→ notifications（40）
        XCTAssertEqual(registry.tabEntries.map(\.id), [todosID, id, notificationsID])
        let entry = try XCTUnwrap(registry.tabEntries.first { $0.id == id }, "progress 应进展开面板的 tab 投影")
        XCTAssertEqual(entry.symbolName, "chart.pie")
        // 文案来自 Localizable 的 `module.progress.name`：宿主语言下解析为 en 或 zh-Hans；
        // catalog 没编进宿主 bundle 时会回退 shortID（"progress"），断言因此能抓住漏编译
        XCTAssertTrue(["Progress", "进度"].contains(entry.label), "tab 文案应已本地化，实到 \(entry.label)")

        // 两个 surface 各给一份内容：expanded = 剩余量清单、compact = 中央槽位的图标 + 百分比；
        // 未声明的 lockscreen 一律 `.none`（不占位、不算失败）
        guard case .view = registry.content(for: id, request: request(.expanded)) else {
            return XCTFail("展开请求应拿到 .view")
        }
        guard case .view = registry.content(for: id, request: request(.compact)) else {
            return XCTFail("compact 已声明，应返回 .view")
        }
        guard case .none = registry.content(for: id, request: request(.lockscreen)) else {
            return XCTFail("lockscreen 未声明，应返回 .none")
        }

        // 折叠态中央槽位投影：三个模块都声明 compact，**第一个候选是 order 20 的 todos**
        //（`compactSlotContent()` 只转发第一个），因此槽位内容仍是待办的视图——
        // notifications（order 40）在默认配置下拿不到槽位，它的 compact 视图只是候选之一。
        XCTAssertEqual(registry.compactEntries.map(\.id), [todosID, id, notificationsID])
        XCTAssertEqual(registry.compactEntries.map(\.order), [20, 30, 40])
        guard case .view = registry.compactSlotContent() else {
            return XCTFail("折叠态中央槽位应拿到 todos 的 .view 内容")
        }
    }

    /// 折叠态中央槽位的投影：只含 `active` 且声明 `.compact` 的模块（**只有 `expanded` 的不得入选**，
    /// failed / disabled 同样不入选），按 `order` 升序、同 `order` 按 id 字典序；
    /// `compactSlotContent()` 转发候选里的第一个，无候选（未 bootstrap / 未激活）时返回 `.none`。
    func testCompactEntriesProjectionAndSlotContent() async {
        let registry = ModuleRegistry.shared
        // 三个声明 compact 的：order 1 的 compact（只有 compact）、order 1 的 dual（compact + expanded，
        // 同 order 按 id 字典序）、order 40 的 compact-late；加上只有 expanded 的 alpha（不得入选）、
        // 抛错的 beta 与被禁用的 optin（不得入选）
        registerProbes([
            CompactProbeModule.self,
            DualSurfaceProbeModule.self,
            CompactLateProbeModule.self,
            AlphaProbeModule.self,
            BetaProbeModule.self,
            OptInProbeModule.self,
        ])

        // 注册了但尚未 bootstrap：没有 active 的候选 → 槽位内容 `.none`（不占位）
        XCTAssertTrue(registry.compactEntries.isEmpty, "未 bootstrap 时不应有候选")
        guard case .none = registry.compactSlotContent() else {
            return XCTFail("无候选时槽位内容应为 .none")
        }

        await registry.bootstrap()

        XCTAssertEqual(registry.compactEntries.map(\.id), [
            "com.cmeng.gourd.probe-compact",       // order 1，与 dual 同序 → id 字典序在前
            "com.cmeng.gourd.probe-dual",          // order 1
            "com.cmeng.gourd.probe-compact-late",  // order 40
        ])
        XCTAssertEqual(registry.compactEntries.map(\.order), [1, 1, 40])
        // 只有 expanded 的模块（alpha）不得入选；failed（beta）/ disabled（optin）也不得入选
        for id in ["com.cmeng.gourd.probe-alpha", "com.cmeng.gourd.probe-beta", "com.cmeng.gourd.probe-optin"] {
            XCTAssertFalse(registry.compactEntries.contains { $0.id == id }, "\(id) 不应进折叠态槽位候选")
        }

        // 转发**第一个**候选：`compact` / `compact-late` 的内容都是 `.none`（与「无候选」同形），
        // 所以换一组夹具——只注册 dual（compact 请求答一个可辨认的 `.unavailable`）
        await registry.deactivateAll()
        registerProbes([DualSurfaceProbeModule.self, AlphaProbeModule.self])
        await registry.bootstrap()
        XCTAssertEqual(registry.compactEntries.map(\.id), ["com.cmeng.gourd.probe-dual"])
        guard case .unavailable(let reason) = registry.compactSlotContent() else {
            return XCTFail("槽位内容应转发给第一个候选模块")
        }
        XCTAssertTrue(reason.contains("probe-dual"), "转发到的应是 compactEntries 的第一个，实到 \(reason)")
    }

    // MARK: - 瞬时浮层 HUD（D-22）

    /// 覆盖语义：第二条浮层**替换**第一条（不排队、不叠加），`id` 换成新的（到期任务的判据）；
    /// `clearHUD()` 幂等；`deactivateAll()` 也把浮层撤掉（注册表清空后它没有归属）。
    func testPresentHUDOverridesPreviousHUD() async {
        let registry = ModuleRegistry.shared

        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-alpha", view: AnyView(Text("A")), ttl: 4)
        let firstID = registry.activeHUD?.id
        XCTAssertNotNil(firstID)
        XCTAssertEqual(registry.activeHUD?.moduleID, "com.cmeng.gourd.probe-alpha")

        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-beta", view: AnyView(Text("B")), ttl: 4)
        XCTAssertNotEqual(registry.activeHUD?.id, firstID, "第二条浮层必须是新身份（旧到期任务据此让路）")
        XCTAssertEqual(registry.activeHUD?.moduleID, "com.cmeng.gourd.probe-beta", "后到者覆盖先到者")

        registry.clearHUD()
        XCTAssertNil(registry.activeHUD)
        registry.clearHUD()
        XCTAssertNil(registry.activeHUD, "clearHUD 必须幂等")

        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-alpha", view: AnyView(Text("A")), ttl: 4)
        await registry.deactivateAll()
        XCTAssertNil(registry.activeHUD, "注册表清空时浮层必须一并撤掉")
    }

    /// `ttl` 夹取到 1…15s：给 0.05s（等于没弹）与 600s（等于常驻）都落回区间端点，
    /// `expiresAt` 按夹取后的值算（模块给什么值都不会让浮层常驻）。
    func testPresentHUDClampsTTLToRange() {
        let registry = ModuleRegistry.shared
        XCTAssertEqual(ModuleRegistry.hudTTLRange.lowerBound, 1)
        XCTAssertEqual(ModuleRegistry.hudTTLRange.upperBound, 15)

        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-alpha", view: AnyView(Text("A")), ttl: 0.05)
        XCTAssertEqual(
            registry.activeHUD?.expiresAt.timeIntervalSinceNow ?? -1,
            ModuleRegistry.hudTTLRange.lowerBound,
            accuracy: 0.5,
            "过短的 ttl 应被抬到下界 1s"
        )

        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-alpha", view: AnyView(Text("A")), ttl: -10)
        XCTAssertEqual(
            registry.activeHUD?.expiresAt.timeIntervalSinceNow ?? -1,
            ModuleRegistry.hudTTLRange.lowerBound,
            accuracy: 0.5,
            "负数 ttl 同样夹到下界"
        )

        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-alpha", view: AnyView(Text("A")), ttl: 600)
        XCTAssertEqual(
            registry.activeHUD?.expiresAt.timeIntervalSinceNow ?? -1,
            ModuleRegistry.hudTTLRange.upperBound,
            accuracy: 0.5,
            "过长的 ttl 应被压到上界 15s"
        )

        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-alpha", view: AnyView(Text("A")), ttl: 4)
        XCTAssertEqual(registry.activeHUD?.expiresAt.timeIntervalSinceNow ?? -1, 4, accuracy: 0.5, "区间内的 ttl 原样使用")

        registry.clearHUD()
    }

    /// 到期清除**只清自己那一条**：先弹一条短 ttl、立即被长 ttl 的后来者替换，
    /// 旧任务的到期时刻醒来后不得把新浮层清掉（否则「两条通知先后到达」会闪断）。
    func testHUDExpiryDoesNotClearNewerEntry() async throws {
        let registry = ModuleRegistry.shared

        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-alpha", view: AnyView(Text("short")), ttl: 1)
        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-beta", view: AnyView(Text("long")), ttl: 15)
        let newerID = registry.activeHUD?.id

        try await Task.sleep(for: .seconds(1.3))  // 跨过第一条的到期点

        XCTAssertEqual(registry.activeHUD?.id, newerID, "旧浮层的到期任务不得清掉后来者")
        XCTAssertEqual(registry.activeHUD?.moduleID, "com.cmeng.gourd.probe-beta")
        registry.clearHUD()
    }

    /// 没有人接替时，到期**自动清除**（浮层是瞬时的：不需要模块自己收尾）。
    func testHUDExpiresAndClearsItself() async throws {
        let registry = ModuleRegistry.shared

        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-alpha", view: AnyView(Text("A")), ttl: 1)
        XCTAssertNotNil(registry.activeHUD)

        try await Task.sleep(for: .seconds(1.3))

        XCTAssertNil(registry.activeHUD, "ttl 到点后应自动清除")
    }

    /// `UIHandle.presentTransient` 的实现落点是注册表（同一份浮层状态，不是第二处副本）：
    /// 模块 id 由工厂补上，视图原样送达。
    func testPresentTransientRoutesToRegistry() throws {
        let manifest = RegistryFixture.manifest(shortID: "hud-probe")
        let context = ModuleContextFactory.make(manifest: manifest, redraw: {})

        context.ui.presentTransient(view: AnyView(Text("hi")), ttl: 4)

        XCTAssertEqual(ModuleRegistry.shared.activeHUD?.moduleID, "com.cmeng.gourd.hud-probe")
        XCTAssertNotNil(ModuleRegistry.shared.activeHUD?.view)
        ModuleRegistry.shared.clearHUD()
    }

    /// `dismissHUD(id:)` **只撤匹配 id 的那条**：`id` 是「这一次弹出」的身份，不是模块 id——
    /// 模块点掉自己那条 × 时台前可能已被后来者替换（通知连发 / 别的模块抢先），
    /// 那种情况必须让后来者继续显示。不匹配 = 空操作（幂等）。
    func testDismissHUDOnlyClearsMatchingID() throws {
        let registry = ModuleRegistry.shared

        // 第一条（极短 ttl → 夹到 1s 下界，代表「已经被顶掉的旧身份」）
        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-alpha", view: AnyView(Text("A")), ttl: 0.05)
        let staleID = try XCTUnwrap(registry.activeHUD?.id)

        // 第二条把它顶掉（覆盖语义）——台前那次弹出的身份已经换人
        registry.presentHUD(moduleID: "com.cmeng.gourd.probe-beta", view: AnyView(Text("B")), ttl: 15)
        let liveID = try XCTUnwrap(registry.activeHUD?.id)
        XCTAssertNotEqual(staleID, liveID, "覆盖后是新身份")

        // 拿旧身份 / 无关身份去撤：一条都不许动
        registry.dismissHUD(id: staleID)
        XCTAssertEqual(registry.activeHUD?.id, liveID, "旧身份的撤请求不得清掉台前的后来者")
        registry.dismissHUD(id: UUID())
        XCTAssertEqual(registry.activeHUD?.id, liveID, "无关 id 同样是空操作")

        // 拿当前身份去撤：这一条消失；重复撤仍幂等
        registry.dismissHUD(id: liveID)
        XCTAssertNil(registry.activeHUD)
        registry.dismissHUD(id: liveID)
        XCTAssertNil(registry.activeHUD, "dismissHUD 必须幂等")
        registry.dismissHUD(id: UUID())
        XCTAssertNil(registry.activeHUD, "本来就没有浮层时也不崩")
    }

    /// `UIHandle.dismissTransient()`（工厂实现）→ 注册表 `dismissHUD(id:)`，且**先判归属**：
    /// 只撤本模块弹的那一条；台前是别的模块的浮层时什么都不做。
    func testDismissTransientDismissesOwnHUDOnly() throws {
        let registry = ModuleRegistry.shared
        let manifest = RegistryFixture.manifest(shortID: "hud-probe")
        let context = ModuleContextFactory.make(manifest: manifest, redraw: {})

        // 本模块弹的那条：撤得掉
        context.ui.presentTransient(view: AnyView(Text("mine")), ttl: 4)
        XCTAssertEqual(registry.activeHUD?.moduleID, "com.cmeng.gourd.hud-probe")
        context.ui.dismissTransient()
        XCTAssertNil(registry.activeHUD, "本模块的浮层应被主动撤掉")

        // 别的模块弹的那条：撤不动（归属判定，不是「无条件清台前」）
        registry.presentHUD(moduleID: "com.cmeng.gourd.someone-else", view: AnyView(Text("other")), ttl: 4)
        context.ui.dismissTransient()
        XCTAssertEqual(
            registry.activeHUD?.moduleID,
            "com.cmeng.gourd.someone-else",
            "别的模块的浮层不在本模块的处置范围内"
        )
        registry.clearHUD()
    }

    // MARK: - 浮层期间的悬浮展开抑制

    /// **有浮层 → 抑制**：浮层在台前时，两条抢跑路径（`startHoverClickMonitor` 的 `mouseDown`
    /// 回调、`handleHover` 的延时展开任务）都必须在 `openNotch()` 前被这条判据挡住——
    /// 否则点浮层上 × / 打开 App 的那一下会被 mouseDown 先吃走，面板被打开、浮层被盖掉。
    func testHoverOpenSuppressedWhileHUDIsPresent() {
        let registry = ModuleRegistry.shared
        XCTAssertNil(registry.activeHUD, "前置：setUp 的 deactivateAll 应已清掉浮层")

        registry.presentHUD(moduleID: "com.cmeng.gourd.hud-probe", view: AnyView(Text("HUD")), ttl: 4)
        XCTAssertNotNil(registry.activeHUD)
        XCTAssertTrue(
            shouldSuppressHoverOpen(activeHUD: registry.activeHUD),
            "浮层存活的 ttl 内必须抑制悬浮展开"
        )

        registry.clearHUD()
    }

    /// **无浮层 → 放行**：判据是「当前有没有浮层」而不是「曾经弹过浮层」——
    /// ttl 到期（内核清）或 × 主动撤（`dismissHUD`）后 `activeHUD` 回到 nil，悬浮展开照旧。
    func testHoverOpenAllowedWithoutHUD() {
        XCTAssertNil(ModuleRegistry.shared.activeHUD)
        XCTAssertFalse(
            shouldSuppressHoverOpen(activeHUD: ModuleRegistry.shared.activeHUD),
            "无浮层时必须放行悬浮展开"
        )
        XCTAssertFalse(shouldSuppressHoverOpen(activeHUD: nil), "显式 nil 同样放行（判据形状）")
    }

    // MARK: - 非刘海屏 hide-until-hover

    /// **基础为真**：非刘海屏 + 关闭态 + 设置开启 + 没有上游瞬时提示 → 隐藏（挪出屏幕）。
    /// 这条是 hide-until-hover 的原有语义，改判据不得把它改掉。
    func testHideClosedContentUntilHoverBaseline() {
        XCTAssertTrue(
            shouldHideClosedContentUntilHover(
                hideSetting: true,
                isNonNotch: true,
                isClosed: true,
                hasSneakPeek: false
            ),
            "非刘海屏关闭态且无瞬时提示时必须隐藏"
        )
    }

    /// **上游 sneak 在场 → 不隐藏**：sneakPeek（音量 / 亮度 / 音乐…）是上游既有的豁免项，
    /// 与改造前同口径（音量键按下时非刘海屏必须露出来）。
    func testHideClosedContentUntilHoverRevealedBySneakPeek() {
        XCTAssertFalse(
            shouldHideClosedContentUntilHover(
                hideSetting: true,
                isNonNotch: true,
                isClosed: true,
                hasSneakPeek: true
            ),
            "上游瞬时提示在场时必须强制显示"
        )
    }

    /// **模块浮层不再是豁免项**（2026-09-28，D-23）：浮层改由内核的独立窗口渲染
    ///（`Kernel/ModuleHUDWindow.swift`），不再占用关闭态那一格——判据回到「只认上游 sneakPeek」，
    /// 并且**即使注册表里有浮层也照常隐藏关闭态内容**（两条路径互不干扰：浮层窗口自己会出现在
    /// 鼠标所在屏，关不关关闭态内容都不影响它）。
    /// 判据同时**读真值**（注册表 `activeHUD`）验证接缝：注册表状态不再影响本判据的取值。
    func testHideClosedContentUntilHoverIgnoresModuleHUD() {
        let registry = ModuleRegistry.shared
        XCTAssertNil(registry.activeHUD, "前置：setUp 的 deactivateAll 应已清掉浮层")

        registry.presentHUD(moduleID: "com.cmeng.gourd.hud-probe", view: AnyView(Text("HUD")), ttl: 4)
        defer { registry.clearHUD() }
        XCTAssertNotNil(registry.activeHUD, "前置：浮层确实在台前")

        XCTAssertTrue(
            shouldHideClosedContentUntilHover(
                hideSetting: true,
                isNonNotch: true,
                isClosed: true,
                hasSneakPeek: false
            ),
            "浮层在台前时关闭态内容照常隐藏（浮层走独立窗口，不再需要豁免）"
        )
    }

    // MARK: - 浮层窗口宿主的放置几何（D-23）

    /// **内置屏（有刘海）**：顶部内边取刘海高度（实测 32pt），窗口顶端贴在其下方 `topGap`，
    /// 水平居中于该屏。这条钉住「浮层不再压在刘海底下、下半截被裁」。
    func testHUDWindowPlacementOnNotchedScreen() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let inset = ModuleHUDWindowHost.topInset(
            safeAreaTop: 32,          // 刘海高度优先于菜单栏高度
            frameMaxY: screenFrame.maxY,
            visibleFrameMaxY: screenFrame.maxY - 24
        )
        XCTAssertEqual(inset, 32, "有刘海时必须避让刘海高度")

        let origin = ModuleHUDWindowHost.origin(
            windowSize: CGSize(width: 400, height: 66),
            screenFrame: screenFrame,
            topInset: inset,
            topGap: ModuleHUDWindowHost.topGap
        )
        XCTAssertEqual(origin.y, screenFrame.maxY - 32 - ModuleHUDWindowHost.topGap - 66, "顶端贴齐可用顶边下方")
        XCTAssertEqual(origin.x, screenFrame.midX - 200, "水平居中于该屏")
    }

    /// **外接屏（无刘海）**：顶部内边取菜单栏高度（屏顶与 `visibleFrame` 顶之差，实测 24pt）——
    /// 不避开会被菜单栏盖住上半行。
    func testHUDWindowPlacementOnNonNotchScreen() {
        let screenFrame = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
        let inset = ModuleHUDWindowHost.topInset(
            safeAreaTop: 0,
            frameMaxY: screenFrame.maxY,
            visibleFrameMaxY: screenFrame.maxY - 25
        )
        XCTAssertEqual(inset, 25, "无刘海时必须避让菜单栏高度")

        let origin = ModuleHUDWindowHost.origin(
            windowSize: CGSize(width: 400, height: 66),
            screenFrame: screenFrame,
            topInset: inset,
            topGap: ModuleHUDWindowHost.topGap
        )
        XCTAssertEqual(origin.y, screenFrame.maxY - 25 - ModuleHUDWindowHost.topGap - 66)
        XCTAssertEqual(origin.x, screenFrame.midX - 200, "居中按该屏而不是主屏")
    }

    /// **菜单栏高度缺失时不产生负内边**（`visibleFrame` 与屏顶一样高的极端值）：内边兜底 0，
    /// 窗口仍然贴顶。（`sanitizedContentSize` / 0×0 兜底那条链在改固定尺寸时已删除——
    /// 固定尺寸永远是有限的正数，不需要消毒；尺寸口径见
    /// `testHUDWindowFixedContentSizeScalesAndClamps`。）
    func testHUDWindowPlacementAndSizeGuards() {
        XCTAssertEqual(
            ModuleHUDWindowHost.topInset(safeAreaTop: 0, frameMaxY: 1000, visibleFrameMaxY: 1000),
            0,
            "量不出菜单栏高度时兜底 0（不能是负数）"
        )
    }

    // MARK: - 浮层的多屏显示（D-25：所有屏同时显示）

    /// **全屏模式**（用户当前设置 `showOnAllDisplays = 1`）：所有屏都该显示浮层——
    /// 这条钉住 2026-09-28 的用户反馈「应该是所有屏幕都显示才对」（旧口径是跟随鼠标屏，
    /// 于是只有一块屏看得见）。
    func testHUDScreensAllDisplaysModeShowsEveryScreen() {
        let names = ["Built-in Retina Display", "VA2478-H-2", "DELL U2720Q"]
        XCTAssertEqual(
            ModuleHUDWindowHost.targetScreenNames(
                showOnAllDisplays: true,
                screenNames: names,
                mainScreenName: names[0],
                preferredScreenName: names[2]
            ),
            Set(names),
            "全屏模式下三层输入都无关：所有屏都在集合里（鼠标 / 主屏 / 指定屏都不该收窄它）"
        )
        XCTAssertEqual(
            ModuleHUDWindowHost.targetScreenNames(
                showOnAllDisplays: true,
                screenNames: ["Only One"],
                mainScreenName: "Only One",
                preferredScreenName: nil
            ),
            ["Only One"],
            "单屏机器同样成立"
        )
    }

    /// **单屏模式**（`showOnAllDisplays = false`）：只在该设置指定的那块屏；
    /// 指定屏不在场时退到主屏；主屏也取不到时退到列表第一块（三档兜底，见纯函数文档）。
    func testHUDScreensSingleDisplayModePrefersSettingThenMainThenFirst() {
        let names = ["Built-in Retina Display", "VA2478-H-2"]

        // ① 指定屏在场 → 只它
        XCTAssertEqual(
            ModuleHUDWindowHost.targetScreenNames(
                showOnAllDisplays: false,
                screenNames: names,
                mainScreenName: names[0],
                preferredScreenName: names[1]
            ),
            [names[1]],
            "单屏模式：只显示在设置指定的那块屏上（与岛同源：preferred_screen_name）"
        )

        // ② 指定屏不在场（拔掉 / 改名 / 尚未写入键）→ 主屏
        XCTAssertEqual(
            ModuleHUDWindowHost.targetScreenNames(
                showOnAllDisplays: false,
                screenNames: names,
                mainScreenName: names[0],
                preferredScreenName: "已拔掉的外接屏"
            ),
            [names[0]],
            "指定屏不在场时退到主屏（不能让浮层彻底消失）"
        )
        XCTAssertEqual(
            ModuleHUDWindowHost.targetScreenNames(
                showOnAllDisplays: false,
                screenNames: names,
                mainScreenName: names[0],
                preferredScreenName: nil
            ),
            [names[0]],
            "键没写过（nil）同口径 → 主屏"
        )

        // ③ 连主屏都取不到 → 列表第一块（仍然要有一块屏显示）
        XCTAssertEqual(
            ModuleHUDWindowHost.targetScreenNames(
                showOnAllDisplays: false,
                screenNames: names,
                mainScreenName: nil,
                preferredScreenName: nil
            ),
            [names[0]],
            "主屏也取不到时退到列表第一块"
        )
    }

    /// **空屏集合兜底**：没有屏可显示 → 空集合（调用方（`present`）据此什么都不做，
    /// 不会去创建 0 个窗口或崩在取下标上）。两种模式都要成立。
    func testHUDScreensEmptyFallbackYieldsNoScreen() {
        XCTAssertEqual(
            ModuleHUDWindowHost.targetScreenNames(
                showOnAllDisplays: true,
                screenNames: [],
                mainScreenName: "Main",
                preferredScreenName: "Main"
            ),
            [],
            "全屏模式 + 空屏集合 → 空集合"
        )
        XCTAssertEqual(
            ModuleHUDWindowHost.targetScreenNames(
                showOnAllDisplays: false,
                screenNames: [],
                mainScreenName: nil,
                preferredScreenName: nil
            ),
            [],
            "单屏模式 + 空屏集合 → 空集合（不越界取 screenNames[0]）"
        )
    }

    // MARK: - 浮层窗口的可见性状态机（2026-09-28：「内置屏偶发只显示第一条」）

    /// ① **首次 present**：窗口还不在台上（刚创建时 `alphaValue` 是 1，所以这里是 `alpha = 1` +
    /// `isVisible = false`）→ 必须「先归零 + 摆位 + 上台 + 淡入」，四步一个都不能少。
    func testHUDVisibilityFirstPresentOrdersFrontAndFadesIn() {
        let actions = HUDVisibilityStateMachine.presentActions(isVisible: false, alpha: 1)
        XCTAssertEqual(actions, [.setAlpha(0), .reposition, .orderFront, .fadeIn])
        XCTAssertTrue(actions.contains(.orderFront), "首次 present 必须让窗口上台")
        XCTAssertEqual(actions.last, .fadeIn, "淡入在三步之后（先归零，淡入才看得见）")
    }

    /// ② **淡出中被接手**（坏状态 ①）：窗口还在台上但 alpha 停在 0 / 半透明 →
    /// 必须**直接给 alpha 终态 1**（不赌动画），且不许出现 `orderOut`。
    ///
    /// 这条正是「内置屏偶发看不到」的修复判据：旧实现只剩 `fadeIn` 的 `guard alphaValue < 1`
    /// 一条恢复路径，且 present 因 `isVisible == true` 跳过 `orderFrontRegardless`。
    func testHUDVisibilityPresentRecoversWindowStuckTransparent() {
        let actions = HUDVisibilityStateMachine.presentActions(isVisible: true, alpha: 0)
        XCTAssertEqual(actions, [.setAlpha(1), .reposition])
        XCTAssertFalse(actions.contains(.orderOut), "在台的窗口不许被收起")
        XCTAssertFalse(actions.contains(.fadeIn), "停在 0 的窗口要给终态，不靠动画恢复")

        // 半透明（淡出进行到一半）同样直接补到 1
        XCTAssertEqual(
            HUDVisibilityStateMachine.presentActions(isVisible: true, alpha: 0.4),
            [.setAlpha(1), .reposition]
        )
        // 已经 1：只剩「重新贴顶居中」一条（幂等；不做无意义的 alpha 写入）
        XCTAssertEqual(HUDVisibilityStateMachine.presentActions(isVisible: true, alpha: 1), [.reposition])
    }

    /// ③ **淡出结束、无人接手**：这才是真正该下台的时刻（`orderOut` + 归零，下次上台重新淡入）。
    func testHUDVisibilityDismissCompletionOrdersOutWhenNobodyTookOver() {
        XCTAssertEqual(
            HUDVisibilityStateMachine.dismissCompletionActions(generationMatches: true, hasActiveHUD: false),
            [.orderOut, .setAlpha(0)]
        )
    }

    /// ④ **同尺寸重弹**：尺寸回调的早退只该省掉 `setContentSize`，不该省掉显隐纠正——
    /// 窗口已被收起（`isVisible == false`）时，即使内容尺寸与缓存一模一样，也必须重新露出。
    ///
    /// 状态机因此**不看尺寸**（尺寸是另一条正交的输入）：动作只由「窗口在不在台上 / 透明不透明」
    /// 决定，所以「同尺寸重弹」得到的动作与首次 present 完全一致。
    func testHUDVisibilitySameSizeRePresentStillBringsWindowBack() {
        let first = HUDVisibilityStateMachine.presentActions(isVisible: false, alpha: 1)
        let sameSizeAgain = HUDVisibilityStateMachine.presentActions(isVisible: false, alpha: 0)
        XCTAssertEqual(first, sameSizeAgain, "同尺寸重弹的动作必须与首次一致（不因尺寸相同而空转）")
        XCTAssertTrue(sameSizeAgain.contains(.orderFront), "窗口已被收起时重新露出它")
        XCTAssertTrue(
            HUDVisibilityStateMachine.presentActions(isVisible: true, alpha: 1).contains(.reposition),
            "尺寸没变也要重新贴顶居中（鼠标可能换到了另一块屏）"
        )
    }

    /// ⑤ **有接手时不 orderOut**：新浮层已经在台前 / 已有更新的淡出在途时，
    /// 旧淡出的完成回调不得把窗口收起来、也不得把 alpha 留在 0（否则新浮层跟着一起消失）。
    func testHUDVisibilityDismissCompletionNeverHidesAHandedOverWindow() {
        let takenOver = HUDVisibilityStateMachine.dismissCompletionActions(
            generationMatches: true,
            hasActiveHUD: true
        )
        XCTAssertFalse(takenOver.contains(.orderOut), "新浮层在台前：不许收起窗口")
        XCTAssertFalse(takenOver.contains(.setAlpha(0)), "更不许把 alpha 留在 0（那就是「看不到」）")
        XCTAssertEqual(takenOver, [.setAlpha(1), .reposition], "撤销这次淡出并重新贴顶居中")

        XCTAssertEqual(
            HUDVisibilityStateMachine.dismissCompletionActions(generationMatches: false, hasActiveHUD: false),
            [],
            "代数不匹配 = 早有更新的浮层/淡出接手，旧回调什么都不做"
        )
        XCTAssertEqual(
            HUDVisibilityStateMachine.dismissCompletionActions(generationMatches: false, hasActiveHUD: true),
            [],
            "代数不匹配优先：接手方自己保证可见，旧回调不得插手"
        )
    }

    // MARK: - 待办模块 todos（T5）

    /// 构造一条待办（id 兼作标题，便于按 id 断言顺序）。
    private func todo(
        _ id: String,
        due: Date? = nil,
        completed: Bool = false,
        completedAt: Date? = nil,
        list: String = "提醒"
    ) -> TodoBucketing.Item {
        TodoBucketing.Item(
            id: id,
            title: id,
            dueDate: due,
            isCompleted: completed,
            completionDate: completedAt,
            listName: list
        )
    }

    private func todoIDs(_ result: TodoBucketing.BucketResult) -> [String] { result.items.map(\.id) }

    /// 分类与计数（2026-09-28 用户定稿的口径）：
    /// 今日 = ① 到期在今天 ∪ ② 已过期且未完成 ∪ ③ 今天完成；本周 = 到期落在一周区间内 **∪ 今日**（刻意重叠）；
    /// 所有 = 全集。**无到期时间只进「所有」**（含「无到期时间 + 今天完成」这种两条规则相抵的条目）。
    func testTodoBucketingMembershipAndCounts() throws {
        let calendar = try fixedGregorian()  // Asia/Shanghai，周一为首日
        let now = try instant(2026, 9, 28, 10, calendar: calendar)  // 2026-09-28 是周一

        let summary = TodoBucketing.classify([
            todo("due-today", due: try instant(2026, 9, 28, 9, calendar: calendar)),
            todo(
                "done-today",
                due: try instant(2026, 9, 28, 8, calendar: calendar),
                completed: true,
                completedAt: try instant(2026, 9, 28, 9, 30, calendar: calendar)
            ),
            todo("overdue-open", due: try instant(2026, 9, 25, 9, calendar: calendar)),
            todo(
                "overdue-done-last-week",
                due: try instant(2026, 9, 25, 9, calendar: calendar),
                completed: true,
                completedAt: try instant(2026, 9, 26, 9, calendar: calendar)
            ),
            todo("later-this-week", due: try instant(2026, 10, 1, 9, calendar: calendar)),
            todo("next-month", due: try instant(2026, 10, 20, 9, calendar: calendar)),
            todo("no-due", list: "收集箱"),
            todo(
                "no-due-done-today",
                completed: true,
                completedAt: try instant(2026, 9, 28, 9, calendar: calendar),
                list: "收集箱"
            ),
        ], now: now, calendar: calendar)

        // 今日：未完成在前（到期升序）、已完成排最后 → 逾期 > 今天到期 > 今天完成
        XCTAssertEqual(todoIDs(summary.today), ["overdue-open", "due-today", "done-today"])
        // 本周：今日的三条**重复出现**（刻意重叠），再加本周内到期的 later-this-week
        XCTAssertEqual(todoIDs(summary.week), ["overdue-open", "due-today", "later-this-week", "done-today"])
        XCTAssertEqual(summary.week.total, summary.today.total + 1, "本周 ⊇ 今日：本周是更大窗口，重叠计数是刻意的")
        // 本周之后 / 上周完成的 / 无到期时间的：都不进今日、本周（later-this-week 则只在本周、不在今日）
        for id in ["next-month", "overdue-done-last-week", "no-due", "no-due-done-today"] {
            XCTAssertFalse(todoIDs(summary.week).contains(id), "\(id) 不应在本周")
            XCTAssertFalse(todoIDs(summary.today).contains(id), "\(id) 不应在今日")
        }
        XCTAssertFalse(todoIDs(summary.today).contains("later-this-week"), "本周内但非今天到期的，不进今日")

        // 所有：全集（含无到期时间与下月的）；未完成按到期升序、无到期时间排最后，已完成按完成时刻倒序
        XCTAssertEqual(summary.all.total, 8)
        XCTAssertEqual(todoIDs(summary.all), [
            "overdue-open", "due-today", "later-this-week", "next-month", "no-due",
            "done-today", "no-due-done-today", "overdue-done-last-week",
        ])

        // (已办, 总量) 与环心文案
        XCTAssertEqual(summary.today.completed, 1)
        XCTAssertEqual(summary.today.total, 3)
        XCTAssertEqual(summary.today.counterText, "1/3")
        XCTAssertEqual(summary.week.completed, 1)
        XCTAssertEqual(summary.week.total, 4)
        XCTAssertEqual(summary.week.counterText, "1/4")
        XCTAssertEqual(summary.all.completed, 3)
        XCTAssertEqual(summary.all.total, 8)
        XCTAssertEqual(summary.all.counterText, "3/8")
        XCTAssertEqual(summary.all.progress, 3.0 / 8.0, accuracy: 1e-9)
    }

    /// 今日的第 ③ 条「今天完成的也归今日」：把被第 ② 条（已过期**且未完成**）挡掉的
    /// 「已过期但今天完成」接回来；未来到期但今天完成的同样归今日。
    /// 而「无到期时间 + 今天完成」按单列的硬规则**只进「所有」**（两条规则相抵时以前者为准）。
    func testTodoBucketingCompletedTodayEntersToday() throws {
        let calendar = try fixedGregorian()
        let now = try instant(2026, 9, 28, 10, calendar: calendar)
        let completedAt = try instant(2026, 9, 28, 9, calendar: calendar)

        let summary = TodoBucketing.classify([
            todo(
                "overdue-done-today",
                due: try instant(2026, 9, 25, 9, calendar: calendar),
                completed: true,
                completedAt: completedAt
            ),
            todo(
                "future-done-today",
                due: try instant(2026, 10, 20, 9, calendar: calendar),
                completed: true,
                completedAt: completedAt
            ),
            todo("no-due-done-today", completed: true, completedAt: completedAt),
        ], now: now, calendar: calendar)

        XCTAssertEqual(todoIDs(summary.today), ["overdue-done-today", "future-done-today"], "今天完成的都归今日（有到期时间的）")
        XCTAssertEqual(todoIDs(summary.all), ["overdue-done-today", "future-done-today", "no-due-done-today"])
        XCTAssertFalse(todoIDs(summary.today).contains("no-due-done-today"), "无到期时间只进「所有」")
        XCTAssertFalse(todoIDs(summary.week).contains("no-due-done-today"), "无到期时间不进「本周」")
    }

    /// 总量为 0 的边界：三个类别都是 `0/0`、进度 0（环为空）；并钉住环的展示顺序。
    func testTodoBucketingEmptyBoundary() throws {
        let calendar = try fixedGregorian()
        let summary = TodoBucketing.classify(
            [],
            now: try instant(2026, 9, 28, 10, calendar: calendar),
            calendar: calendar
        )

        XCTAssertEqual(summary.ordered.map(\.bucket), [.today, .week, .all], "环的展示顺序：今日 → 本周 → 所有")
        for result in summary.ordered {
            XCTAssertEqual(result.completed, 0)
            XCTAssertEqual(result.total, 0)
            XCTAssertEqual(result.counterText, "0/0")
            XCTAssertEqual(result.progress, 0)
        }
    }

    /// 周区间的起止随日历的 `firstWeekday`（不假定周一）：2026-10-04（周日）在「周一为首日」的
    /// 周 `[09-28, 10-05)` 内，在「周日为首日」的周 `[09-27, 10-04)` 之外（它是下一周的第一天）——
    /// 两种日历下都不进今日、都进所有。
    ///
    /// 用未来到期（而非昨天）的条目，是为了不撞上「已过期 → 进今日」那条规则：
    /// 2026-09-27（周日）虽然也随 `firstWeekday` 在两周之间挪动，但它已过期，两种日历下都进今日。
    func testTodoBucketingWeekFollowsFirstWeekday() throws {
        let mondayFirst = try fixedGregorian(firstWeekday: 2)
        let sundayFirst = try fixedGregorian(firstWeekday: 1)
        let now = try instant(2026, 9, 28, 10, calendar: mondayFirst)
        let item = todo("sunday-due", due: try instant(2026, 10, 4, 9, calendar: mondayFirst))

        let mondaySummary = TodoBucketing.classify([item], now: now, calendar: mondayFirst)
        let sundaySummary = TodoBucketing.classify([item], now: now, calendar: sundayFirst)

        XCTAssertEqual(todoIDs(mondaySummary.week), ["sunday-due"], "周一为首日：本周 = [09-28, 10-05)")
        XCTAssertTrue(todoIDs(sundaySummary.week).isEmpty, "周日为首日：本周 = [09-27, 10-04)，10-04 已是下一周")
        XCTAssertEqual(mondaySummary.today.total, 0, "日后到期且未完成 → 不进今日")
        XCTAssertEqual(sundaySummary.today.total, 0)
        XCTAssertEqual(mondaySummary.all.total, 1)
        XCTAssertEqual(sundaySummary.all.total, 1)
    }

    /// 到期时间恰好是**明天 00:00** 时不算今天（自然日的半开区间边界）。
    /// `DateInterval.contains(_:)` 的实现含 end 端点，用它会把这条算进今天——本模块因此自写半开判定。
    func testTodoBucketingMidnightBoundary() throws {
        let calendar = try fixedGregorian()
        let summary = TodoBucketing.classify([
            todo("tomorrow-midnight", due: try instant(2026, 9, 29, calendar: calendar)),
            todo("today-last-minute", due: try instant(2026, 9, 28, 23, 59, calendar: calendar)),
        ], now: try instant(2026, 9, 28, 23, 59, calendar: calendar), calendar: calendar)

        XCTAssertEqual(todoIDs(summary.today), ["today-last-minute"])
    }

    /// `TodosModule.manifest` 的契约：id / surfaces / icon / defaultEnabled / placement / 空权限 / 无配置；
    /// 并回走一次 JSON 路径（与宿主读 descriptor 同一条路）。
    func testTodosModuleManifestMatchesContract() throws {
        let manifest = TodosModule.manifest
        XCTAssertNoThrow(try manifest.validate())

        XCTAssertEqual(manifest.id, "com.cmeng.gourd.todos")
        XCTAssertEqual(manifest.shortID, "todos")
        XCTAssertEqual(manifest.name.key, "module.todos.name")
        XCTAssertEqual(manifest.summary?.key, "module.todos.summary")
        XCTAssertEqual(manifest.icon, IconSpec(type: "symbol", name: "checklist"))
        XCTAssertEqual(manifest.kind, "builtin")
        XCTAssertEqual(manifest.surfaces, [.expanded, .compact], "展开面板 + 折叠态中央槽位")
        XCTAssertEqual(manifest.defaultEnabled, true)
        XCTAssertEqual(manifest.defaultPlacement, Placement(slot: .center, order: 20))
        XCTAssertTrue(manifest.permissions.isEmpty, "06 §7.1 无「提醒」词条：提醒走系统 TCC，不声明 capability")
        XCTAssertNil(manifest.config, "第一版不做配置")

        XCTAssertEqual(try ModuleManifest.decode(from: try JSONEncoder().encode(manifest)), manifest)
    }

    // MARK: - 待办的新增 / 删除（2026-09-28 用户反馈「待办里面要可以增删待办内容」）

    /// 新增的校验与构造是纯函数：**标题去首尾空白**后写库，日期三选一给「当天 00:00 的年月日」。
    ///
    /// 「今天」给的是**年月日组件、不带时分**——与系统「提醒」App 的全天条目同形，读回时
    /// `TodoText.dueText` 按「到期 == 当天起点」判为全天、只显示日期（口径闭环）。
    func testTodoComposerTrimsTitleAndBuildsTodayDue() throws {
        let calendar = try fixedGregorian()
        let now = try instant(2026, 9, 28, 14, 30, calendar: calendar)

        let draft = TodoComposer.draft(title: "  买牛奶\n ", due: .today, now: now, calendar: calendar)
        guard case let .create(title, components) = draft else {
            return XCTFail("非空标题必须能建：\(draft)")
        }
        XCTAssertEqual(title, "买牛奶", "首尾空白与换行都去掉，内部文字不动")
        XCTAssertEqual(components?.year, 2026)
        XCTAssertEqual(components?.month, 9)
        XCTAssertEqual(components?.day, 28)
        XCTAssertNil(components?.hour, "只给年月日：不带时分才是全天口径（14:30 的现在也不写 14:30）")
        XCTAssertNil(components?.minute)
        XCTAssertNil(components?.second)
        XCTAssertEqual(
            calendar.date(from: try XCTUnwrap(components)),
            calendar.startOfDay(for: now),
            "今天 = 今天 00:00"
        )
    }

    /// 标题去空白后为空：**拒绝**（不建提醒）——空标题在「提醒」App 里是一行看不见的条目。
    func testTodoComposerRejectsBlankTitle() {
        for blank in ["", "   ", "\n\t ", " \n \t\n"] {
            XCTAssertEqual(
                TodoComposer.draft(title: blank, due: .today),
                .rejectEmptyTitle,
                "\(blank.debugDescription) 是空标题"
            )
        }
    }

    /// 「明天」= `now + 1 天`的当天起点：跨月（9/30 → 10/1）与跨年（12/31 → 次年 1/1）都按自然日推进，
    /// 且**先加一天再取起点**（夏令时切换日「今天起点 + 1 天」与「现在 + 1 天」不是同一天）。
    func testTodoComposerTomorrowUsesNextDayStart() throws {
        let calendar = try fixedGregorian()
        func tomorrow(_ now: Date) -> DateComponents? {
            guard case let .create(_, components) = TodoComposer.draft(
                title: "x", due: .tomorrow, now: now, calendar: calendar
            ) else { return nil }
            return components
        }

        let acrossMonth = try XCTUnwrap(tomorrow(try instant(2026, 9, 30, 23, 50, calendar: calendar)))
        XCTAssertEqual([acrossMonth.year, acrossMonth.month, acrossMonth.day], [2026, 10, 1], "月末跨月")

        let acrossYear = try XCTUnwrap(tomorrow(try instant(2026, 12, 31, 0, 5, calendar: calendar)))
        XCTAssertEqual([acrossYear.year, acrossYear.month, acrossYear.day], [2027, 1, 1], "跨年")
    }

    /// 「无日期」给 nil：条目**没有** `dueDateComponents`——按 `TodoBucketing` 的硬规则它只出现在
    /// 「所有」里，这是刻意的（不是漏填）。
    func testTodoComposerNoDateYieldsNilDueComponents() {
        XCTAssertEqual(
            TodoComposer.draft(title: "收集", due: .none),
            .create(title: "收集", dueDateComponents: nil)
        )
    }

    /// 目标列表的兜底：默认列表（`defaultCalendarForNewReminders()` 可为 nil）优先，
    /// 取不到时退到第一个可用列表；两者都没有 → nil（调用方据此显示一行失败提示，而不是猜一个列表）。
    func testTodoComposerTargetListFallsBackToFirstAvailable() {
        XCTAssertEqual(
            TodoComposer.targetList(defaultList: "默认", availableLists: ["A", "B"]),
            "默认",
            "有默认列表就用默认列表（不碰第一个可用列表）"
        )
        XCTAssertEqual(
            TodoComposer.targetList(defaultList: String?.none, availableLists: ["A", "B"]),
            "A",
            "默认列表为 nil 时兜到第一个可用列表"
        )
        XCTAssertNil(
            TodoComposer.targetList(defaultList: String?.none, availableLists: []),
            "一个列表都没有 → nil（失败并回显提示，不静默）"
        )
    }

    /// 左列竖排三环的直径是**可用高度的纯函数**（2026-09-28 用户改版：「三个圈…放在左侧」）：
    /// 高度够就回到设计定稿的 52，不够就三等分剩余空间，缩到下限 30 为止；
    /// 高度取不到（GeometryReader 给 0）时不能出现 0 直径的环。
    func testTodoRingPickerDiameterFitsAvailableHeight() {
        XCTAssertEqual(
            TodoRingLayout.ringDiameter(fittingHeight: 400),
            TodoRingLayout.maximumDiameter,
            "面板调高后回到设计定稿的 52（不再因竖排缩小）"
        )
        XCTAssertEqual(
            TodoRingLayout.ringDiameter(fittingHeight: 0),
            TodoRingLayout.maximumDiameter,
            "高度取不到（0）时按上限，不出现 0 直径"
        )
        XCTAssertEqual(
            TodoRingLayout.ringDiameter(fittingHeight: TodoRingLayout.maximumDiameter * 3 + 200),
            TodoRingLayout.maximumDiameter,
            "远超所需的高度同样封顶在 52"
        )

        // 默认 200pt 面板扣掉上下 padding ≈ 180：三个环收缩后必须真的放得下（含标签与间距）
        let defaultHeight: CGFloat = 180
        let fitted = TodoRingLayout.ringDiameter(fittingHeight: defaultHeight)
        XCTAssertLessThan(fitted, TodoRingLayout.maximumDiameter, "默认高度下要收缩（52 三个环放不进 180）")
        XCTAssertGreaterThanOrEqual(fitted, TodoRingLayout.minimumDiameter)
        let used = fitted * 3
            + TodoRingLayout.ringSpacing * 2
            + TodoRingLayout.itemTextHeight * 3
        XCTAssertLessThanOrEqual(used, defaultHeight, "收缩后的三环 + 标签必须落在可用高度内")

        XCTAssertEqual(
            TodoRingLayout.ringDiameter(fittingHeight: 10),
            TodoRingLayout.minimumDiameter,
            "极矮的面板（用户把高度拖到最小）也保底 30，不缩成看不见的点"
        )
    }

    /// `TODO` 日期选项的文案 key 与 `DueOption` 同源（加选项必须同时给 key，否则面板上出现裸 key）。
    func testTodoComposerDueOptionLabelKeys() {
        XCTAssertEqual(
            TodoComposer.DueOption.allCases.map(\.labelKey),
            ["module.todos.dueToday", "module.todos.dueTomorrow", "module.todos.dueNone"]
        )
    }

    /// `module.todos.*` 的 key 必须能从宿主 bundle 解析出文案（06 §3.3 R5 的 key 形态）：
    /// 解析不到时 `Bundle` 原样返回 key，断言因此能抓住漏编译 / 拼错的 key。
    func testTodosLocalizationKeysResolve() {
        let keys = [
            "module.todos.name",
            "module.todos.summary",
            "module.todos.scope.today",
            "module.todos.scope.week",
            "module.todos.scope.all",
            "module.todos.empty",
            "module.todos.overdue",
            "module.todos.permission",
            "module.todos.requestAccess",
            "module.todos.openSettings",
            // 增删（2026-09-28）：新增输入行、日期三选一、删除确认、写回失败的一行提示
            "module.todos.add",
            "module.todos.addPlaceholder",
            "module.todos.dueToday",
            "module.todos.dueTomorrow",
            "module.todos.dueNone",
            "module.todos.delete",
            "module.todos.deleteConfirm",
            "module.todos.cancel",
            "module.todos.writeFailed",
        ]
        for key in keys {
            let localized = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
            XCTAssertNotEqual(localized, key, "\(key) 没解析出文案（catalog 未编进宿主 bundle？）")
            XCTAssertFalse(localized.isEmpty, "\(key) 解析为空串")
        }
        // 三个类别的标签 key 与 `TodoBucketing.Bucket.rawValue` 同源
        XCTAssertEqual(TodoBucketing.Bucket.allCases.map(\.labelKey), [
            "module.todos.scope.today", "module.todos.scope.week", "module.todos.scope.all",
        ])
    }

    // MARK: - 通知上岛 notifications（P2c：探针 + 表）

    /// `NotificationText.relativeParts` 的分档边界（09 §5.5 的列表形态「3 分钟前」）：
    /// `< 1 分钟` / `59 分钟` / `1 小时` / `23 小时` / `1 天`，外加时钟回拨（未来时间）不得出负数。
    func testNotificationsRelativeTimeBoundaries() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func parts(_ interval: TimeInterval) -> (key: String, value: Int) {
            NotificationText.relativeParts(since: now.addingTimeInterval(-interval), now: now)
        }

        XCTAssertEqual(parts(0).key, "module.notifications.justNow", "0 秒 = 刚刚")
        XCTAssertEqual(parts(0).value, 0)
        XCTAssertEqual(parts(59).key, "module.notifications.justNow", "59 秒未满 1 分钟，仍是「刚刚」")
        XCTAssertEqual(parts(60).key, "module.notifications.minutesAgo", "满 1 分钟进分钟档")
        XCTAssertEqual(parts(60).value, 1)
        XCTAssertEqual(parts(59 * 60).key, "module.notifications.minutesAgo", "59 分钟仍在分钟档")
        XCTAssertEqual(parts(59 * 60).value, 59)
        XCTAssertEqual(parts(3600).key, "module.notifications.hoursAgo", "满 1 小时进小时档")
        XCTAssertEqual(parts(3600).value, 1)
        XCTAssertEqual(parts(23 * 3600).key, "module.notifications.hoursAgo", "23 小时仍在小时档")
        XCTAssertEqual(parts(23 * 3600).value, 23)
        XCTAssertEqual(parts(24 * 3600).key, "module.notifications.daysAgo", "满 24 小时进天档")
        XCTAssertEqual(parts(24 * 3600).value, 1)
        XCTAssertEqual(parts(47 * 3600).value, 1, "47 小时向下取整仍是 1 天")
        XCTAssertEqual(parts(3 * 24 * 3600).value, 3)
        XCTAssertEqual(parts(-120).key, "module.notifications.justNow", "未来时间（时钟回拨）按「刚刚」，不出负数")
    }

    /// 相对时间的**成文**形态走本地化查表（`String(format:)` + `%d`）：查不到时 `Bundle` 原样返回 key，
    /// 且 `%d` 必须被替换掉——断言因此能抓住「key 漏编译」与「格式串写错」两类问题。
    func testNotificationsRelativeTimeTextIsLocalized() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let text = NotificationText.relative(now.addingTimeInterval(-3 * 60), now: now)
        XCTAssertFalse(text.contains("%d"), "格式串没被替换：\(text)")
        XCTAssertTrue(text.contains("3"), "应带上分钟数：\(text)")
        XCTAssertNotEqual(text, "module.notifications.minutesAgo", "key 没解析出文案")
    }

    /// `NotificationItem` 的字段拼装是**纯函数**：喂一个构造的二进制 plist（`req.titl` 等键）
    /// 应解出 title / subtitle / body / bundleIdentifier，缺省字段由调用方补。
    func testNotificationItemCompositionFromBinaryPlist() throws {
        let data = try Self.binaryPlist([
            "req": [
                "titl": "构建完成",
                "subt": "CI",
                "body": "全部任务通过",
                "cate": "",
                "app": "com.apple.Mail",
                "date": 800_000_000,
            ] as [String: Any],
        ])

        let payload = NotificationCenterReader.payload(fromRecord: data)
        XCTAssertEqual(payload.title, "构建完成")
        XCTAssertEqual(payload.subtitle, "CI")
        XCTAssertEqual(payload.body, "全部任务通过")
        XCTAssertEqual(payload.bundleIdentifier, "com.apple.Mail")
        XCTAssertTrue(payload.missingKeys.isEmpty, "键齐时不该报缺失：\(payload.missingKeys)")
        XCTAssertNil(payload.decodeError)

        let item = NotificationItem.make(recordID: 42, data: data, appName: "邮件")
        XCTAssertEqual(item.id, 42)
        XCTAssertEqual(item.bundleIdentifier, "com.apple.Mail")
        XCTAssertEqual(item.appName, "邮件")
        XCTAssertEqual(item.displayName, "邮件")
        XCTAssertEqual(item.title, "构建完成")
        XCTAssertEqual(item.subtitle, "CI")
        XCTAssertEqual(item.body, "全部任务通过")
        // plist 的时间是 Apple 纪元（2001）秒数：< 1e9 走 `timeIntervalSinceReferenceDate`
        XCTAssertEqual(item.deliveredDate, Date(timeIntervalSinceReferenceDate: 800_000_000))

        // 拿不到 `app` 表映射时退回 bundle id 的最后一段；两者都拿不到时留空串
        XCTAssertEqual(
            NotificationCenterReader.appDisplayName(bundleIdentifier: "com.apple.Mail", appMap: ["com.apple.Mail": "邮件"]),
            "邮件"
        )
        XCTAssertEqual(
            NotificationCenterReader.appDisplayName(bundleIdentifier: "com.apple.Mail", appMap: [:]),
            "Mail",
            "app 表取不到显示名时退回 bundle id 最后一段"
        )
        XCTAssertEqual(NotificationCenterReader.appDisplayName(bundleIdentifier: "", appMap: [:]), "")
        // 条目自身的兜底：appName 空 → 用 bundle id；两者都空 → `?`
        XCTAssertEqual(NotificationItem.make(recordID: 43, data: data).displayName, "com.apple.Mail")
        XCTAssertEqual(NotificationItem.make(recordID: 44, data: Data()).displayName, "?")
    }

    /// **防御式解码**（09 §5.5：schema 私有，Apple 改版即失效）：缺键给空并记录缺失键名、
    /// 垃圾字节 / 空 data 只记 `decodeError`，两种情形都**不许崩、不许抛错**。
    func testNotificationPayloadToleratesMissingKeysAndGarbage() throws {
        // 只有 titl：其余键全缺 → 空串 / nil + 可读的缺键清单（探针报告据此校准新键名）
        let partial = NotificationCenterReader.payload(fromRecord: try Self.binaryPlist([
            "req": ["titl": "只有标题"] as [String: Any],
        ]))
        XCTAssertEqual(partial.title, "只有标题")
        XCTAssertEqual(partial.body, "")
        XCTAssertNil(partial.subtitle)
        XCTAssertNil(partial.bundleIdentifier)
        XCTAssertNil(partial.decodeError)
        XCTAssertEqual(partial.missingKeys, ["subt", "body", "cate", "app", "date"])

        // 顶层直接给键（老格式没有 req 包一层）同样能解出
        let flat = NotificationCenterReader.payload(fromRecord: try Self.binaryPlist([
            "titl": "扁平标题",
            "body": "扁平正文",
        ]))
        XCTAssertEqual(flat.title, "扁平标题")
        XCTAssertEqual(flat.body, "扁平正文")

        // 非 plist 的垃圾字节：给空字段 + decodeError，不抛错
        let garbage = NotificationCenterReader.payload(fromRecord: Data([0x00, 0x01, 0x02]))
        XCTAssertEqual(garbage.title, "")
        XCTAssertEqual(garbage.body, "")
        XCTAssertNotNil(garbage.decodeError)
        XCTAssertEqual(garbage.missingKeys, ["titl", "subt", "body", "cate", "app", "date"])

        // 空 data（列是 NULL 或零长）
        let empty = NotificationCenterReader.payload(fromRecord: Data())
        XCTAssertEqual(empty.decodeError, "data 列为空")
        XCTAssertEqual(NotificationItem.make(recordID: 1, data: Data()).title, "")
    }

    /// `NotificationsModule.manifest` 的契约：id / surfaces / icon / placement / 默认启用 / 空权限 / 无配置；
    /// 并回走一次 JSON 路径（与宿主读 descriptor 同一条路）。
    func testNotificationsModuleManifestMatchesContract() throws {
        let manifest = NotificationsModule.manifest
        XCTAssertNoThrow(try manifest.validate())

        XCTAssertEqual(manifest.id, "com.cmeng.gourd.notifications")
        XCTAssertEqual(manifest.shortID, "notifications")
        XCTAssertEqual(manifest.name.key, "module.notifications.name")
        XCTAssertEqual(manifest.summary?.key, "module.notifications.summary")
        XCTAssertEqual(manifest.icon, IconSpec(type: "symbol", name: "bell.badge"))
        XCTAssertEqual(manifest.kind, "builtin")
        XCTAssertEqual(manifest.surfaces, [.expanded, .compact], "展开面板通知列表 + 折叠态未读数")
        XCTAssertEqual(manifest.defaultEnabled, true)
        XCTAssertEqual(manifest.defaultPlacement, Placement(slot: .center, order: 40))
        XCTAssertTrue(
            manifest.permissions.isEmpty,
            "06 §7.1 白名单里还没有 `notifications:read`（docs/14 标注「待落」）；完全磁盘访问是系统 TCC，不是模块 capability"
        )
        XCTAssertNil(manifest.config, "第一版不读配置")

        XCTAssertEqual(try ModuleManifest.decode(from: try JSONEncoder().encode(manifest)), manifest)
    }

    /// `module.notifications.*` 的 key 必须能从宿主 bundle 解析出文案（06 §3.3 R5 的 key 形态）。
    func testNotificationsLocalizationKeysResolve() {
        let keys = [
            "module.notifications.name",
            "module.notifications.summary",
            "module.notifications.empty",
            "module.notifications.needsFullDiskAccess",
            "module.notifications.openSettings",
            "module.notifications.recent",
            "module.notifications.justNow",
            "module.notifications.minutesAgo",
            "module.notifications.hoursAgo",
            "module.notifications.daysAgo",
            "module.notifications.readOnlyNote",
            "module.notifications.newNotification",
            "module.notifications.clearAll",
            "module.notifications.dismiss",
            "module.notifications.closeSystemNotification",
            // 一次取数多条新通知时，浮层第二行末尾的计数后缀（浮层仍只展示最新一条）
            "module.notifications.moreCount",
        ]
        for key in keys {
            let localized = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
            XCTAssertNotEqual(localized, key, "\(key) 没解析出文案（catalog 未编进宿主 bundle？）")
            XCTAssertFalse(localized.isEmpty, "\(key) 解析为空串")
        }
    }

    // MARK: - 通知浮层（P2d：基线 + 正文口径）

    /// 浮层候选是**纯函数**：只有 `rec_id > 基线` 的条目才可能触发，且多条时只取**最新一条**。
    ///
    /// 这条钉住「首次 activate 建基线」的语义——激活前就在库里的通知（≤ 基线）永远不弹浮层，
    /// 一次轮询进来一串新通知也不刷屏（其余只进未读计数）。
    func testNotificationHUDCandidateFiltersByBaseline() {
        // 激活前已存在（≤ 基线）→ 不弹
        XCTAssertNil(NotificationStore.hudCandidate(in: [], above: 10), "空集合没有候选")
        XCTAssertNil(
            NotificationStore.hudCandidate(in: [notificationItem(3), notificationItem(9), notificationItem(10)], above: 10),
            "等于基线的也不算新增（SQL 侧是 `rec_id > 基线`，此处必须同口径）"
        )

        // 严格大于基线才入选
        XCTAssertEqual(NotificationStore.hudCandidate(in: [notificationItem(10), notificationItem(11)], above: 10)?.id, 11)

        // 多条新通知只弹最新那一条（与到达顺序无关，按 id 取最大）
        XCTAssertEqual(
            NotificationStore.hudCandidate(
                in: [notificationItem(12), notificationItem(11), notificationItem(15), notificationItem(13)],
                above: 10
            )?.id,
            15,
            "一次轮询有多条新增时只弹最新一条"
        )

        // 基线与新记录混在一起：老的一条不得顶掉新的
        XCTAssertEqual(
            NotificationStore.hudCandidate(in: [notificationItem(2), notificationItem(7), notificationItem(8)], above: 6)?.id,
            8
        )
    }

    /// `showBodyInHUD` 的呈现口径（纯函数）：**默认为 true = 浮层显示正文**；
    /// 关掉后浮层第二行只剩「新通知」，正文一个字都不进浮层。
    func testNotificationHUDDetailHonorsShowBodyFlag() {
        let newNotification = NotificationText.localized("module.notifications.newNotification")
        XCTAssertNotEqual(newNotification, "module.notifications.newNotification", "新通知文案没解析出来")

        // 默认（true）：标题 + 正文
        XCTAssertEqual(
            NotificationText.hudDetail(title: "构建完成", body: "全部任务通过", showsBody: true),
            "构建完成 · 全部任务通过"
        )
        // 关掉：正文不进浮层
        let hidden = NotificationText.hudDetail(title: "构建完成", body: "全部任务通过", showsBody: false)
        XCTAssertEqual(hidden, newNotification)
        XCTAssertFalse(hidden.contains("全部任务通过"), "关掉后正文不得出现在浮层文案里")

        // 单边为空：只显示有的那一边；首尾空白不算内容
        XCTAssertEqual(NotificationText.hudDetail(title: "只有标题", body: "", showsBody: true), "只有标题")
        XCTAssertEqual(NotificationText.hudDetail(title: "   ", body: "只有正文", showsBody: true), "只有正文")
        XCTAssertEqual(
            NotificationText.hudDetail(title: "  ", body: "\n", showsBody: true),
            newNotification,
            "两边都空时不留一行空白"
        )
    }

    /// **超长内容策略**（2026-09-28 用户：「消息内容过多考虑下怎么显示」）：
    /// ① 正文里的换行**先压成空格**（浮层第二行只有 2 行预算，换行会白白吃掉一行）；
    /// ② 一次取数多条新通知只在末尾追加「等 N 条」计数后缀（浮层仍只展示最新一条）。
    func testNotificationHUDDetailFlattensNewlinesAndCountsExtraNotifications() {
        // ① 换行 / 制表符 / `\r\n` → 空格，连续空白折成一个，首尾去净
        XCTAssertEqual(
            NotificationText.hudDetail(title: "构建", body: "第一行\n第二行", showsBody: true),
            "构建 · 第一行 第二行"
        )
        XCTAssertEqual(
            NotificationText.hudDetail(title: "构建", body: "第一行\r\n\r\n第二行\t末尾  ", showsBody: true),
            "构建 · 第一行 第二行 末尾",
            "`\\r\\n` 与连续空白都归一成单个空格"
        )
        XCTAssertEqual(NotificationText.singleLine("\n  \n"), "", "全是空白 → 空串（不占第二行的预算）")
        XCTAssertEqual(NotificationText.singleLine("原样"), "原样")

        // ② 计数后缀：> 0 才追加，用的是本地化文案（`and %d more` / `等 %d 条`）
        let more = NotificationText.localized("module.notifications.moreCount")
        XCTAssertNotEqual(more, "module.notifications.moreCount", "计数文案没解析出来")
        XCTAssertEqual(
            NotificationText.hudDetail(title: "构建", body: "全部通过", showsBody: true, moreCount: 0),
            "构建 · 全部通过",
            "0 条不追加后缀"
        )
        let withMore = NotificationText.hudDetail(title: "构建", body: "全部通过", showsBody: true, moreCount: 3)
        XCTAssertTrue(withMore.hasPrefix("构建 · 全部通过"), "后缀追加在末尾，内容不动：\(withMore)")
        XCTAssertNotEqual(withMore, "构建 · 全部通过")
        XCTAssertTrue(withMore.contains("3"), "后缀要带上「还有几条」：\(withMore)")
        XCTAssertEqual(withMore, "构建 · 全部通过 " + String(format: more, 3))
        // 关掉正文时后缀照旧（「还有几条」与正文显示与否无关）
        let hidden = NotificationText.hudDetail(title: "构建", body: "全部通过", showsBody: false, moreCount: 2)
        XCTAssertEqual(hidden, NotificationText.localized("module.notifications.newNotification") + " "
            + String(format: more, 2))
    }

    /// 键本身的口径：`showBodyInHUD` 的**声明默认值是 true**（用户 2026-09-28 要求默认显示正文，
    /// 覆盖设计稿原口径的 false）——断言读 `defaultValue` 而不是当前生效值，
    /// 不受开发机上真实 UserDefaults 影响。
    func testShowBodyInHUDKeyDefaultsToTrue() {
        XCTAssertEqual(Defaults.Keys.showBodyInHUD.name, "showBodyInHUD", "键名与设计稿/设置页一致")
        XCTAssertTrue(
            Defaults.Keys.showBodyInHUD.defaultValue,
            "默认必须是 true（用户口径）；设计稿原口径的 false 已被覆盖"
        )
    }

    // MARK: - 浮层显示时长（D-25：可配 + 默认 8s）

    /// **显示时长可配**（2026-09-28 用户反馈「显示时长太短」）：设置值 → ttl 的映射与夹取。
    /// 边界取 1 / 8 / 15 / 20 —— 内核 `hudTTLRange`（1…15）的两端、设置默认值（8）与其外侧。
    func testNotificationHUDDurationMapsToTTLWithClamp() {
        XCTAssertEqual(NotificationHUDPolicy.ttl(forSettingSeconds: 8), 8, "默认档 8s 原样交给内核")
        XCTAssertEqual(NotificationHUDPolicy.ttl(forSettingSeconds: 2), 2, "滑块下界 2s")
        XCTAssertEqual(NotificationHUDPolicy.ttl(forSettingSeconds: 1), 1, "内核下界 1s 仍可达（不是 0）")
        XCTAssertEqual(
            NotificationHUDPolicy.ttl(forSettingSeconds: 0.2),
            1,
            "低于内核下界 → 夹到 1s（直接改 UserDefaults 写了个 0.2 也要有确定行为）"
        )
        XCTAssertEqual(NotificationHUDPolicy.ttl(forSettingSeconds: 15), 15, "内核上界 15s")
        XCTAssertEqual(
            NotificationHUDPolicy.ttl(forSettingSeconds: 20),
            15,
            "高于上界 → 夹到 15s（浮层不得变成常驻占位）"
        )
        XCTAssertEqual(
            NotificationHUDPolicy.durationRange,
            2...15,
            "设置滑块区间（2…15）与内核夹取区间（1…15）同源：滑块不会给出被夹掉的档位"
        )
    }

    /// 键本身的口径：**默认 8s**（原实现是模块里的代码常量 `hudTTL = 4`——用户 2026-09-28
    /// 反馈「显示时长太短」后改为可配）。断言 `defaultValue` 而不是当前生效值，
    /// 不受开发机上真实 UserDefaults 影响。
    func testNotificationHUDDurationKeyDefaultsToEightSeconds() {
        XCTAssertEqual(
            Defaults.Keys.notificationHUDDurationSeconds.name,
            "notificationHUDDurationSeconds",
            "键名与设置页 / 文档一致"
        )
        XCTAssertEqual(Defaults.Keys.notificationHUDDurationSeconds.defaultValue, 8, "默认 8s（原 4s）")
        XCTAssertTrue(
            ModuleRegistry.hudTTLRange.contains(Defaults.Keys.notificationHUDDurationSeconds.defaultValue),
            "默认值必须落在内核夹取区间（1…15）内，否则一装上就被夹、日志与实际不符"
        )
    }

    // MARK: - 通知浮层的配置区（D-25：总开关 / 背景样式）

    /// **总开关**（2026-09-28 用户要求「做一个配置项，要包含总开关…」）：关掉 → 判定函数直接给 `nil`，
    /// 模块因此**连 `presentTransient` 都不调**（两条通道共用这一个判据）。
    ///
    /// 用纯判定函数测（不起真窗口、不读开发机上的 UserDefaults）：`resolve` 就是「弹 / 不弹」
    /// 这条判据的唯一落点。
    func testNotificationHUDPresentationMasterSwitchGatesPresentation() {
        XCTAssertNil(
            NotificationHUDPresentation.resolve(enabled: false, showsBody: true, backgroundStyle: .liquidGlass),
            "总开关关掉 → 不弹浮层（这就是「不调用 presentTransient」的判据）"
        )
        XCTAssertNil(
            NotificationHUDPresentation.resolve(enabled: false, showsBody: false, backgroundStyle: .solid),
            "总开关优先于其余三项：它们怎么设都不弹"
        )

        XCTAssertEqual(
            NotificationHUDPresentation.resolve(enabled: true, showsBody: false, backgroundStyle: .solid),
            NotificationHUDPresentation(showsBody: false, backgroundStyle: .solid),
            "开起来时两项口径原样进快照"
        )
        XCTAssertEqual(
            NotificationHUDPresentation.resolve(enabled: true, showsBody: true, backgroundStyle: .liquidGlass),
            NotificationHUDPresentation(showsBody: true, backgroundStyle: .liquidGlass)
        )
    }

    /// 两个新键的**声明默认值** + 背景样式的**序列化往返**（写盘 → 读回）。
    ///
    /// 往返走一个**临时 suite**（不碰开发机 `com.cmeng.gourd` 域）：枚举存的是 `rawValue`
    /// 字符串（`RawRepresentable` 桥，同 `LockScreenGlassStyle` / `OSDMaterial`），
    /// 因此断言盘上真的出现 `"Solid"` 而不只是一个内存值。
    func testNotificationHUDConfigKeysDefaultsAndBackgroundRoundTrip() {
        XCTAssertEqual(Defaults.Keys.enableNotificationHUD.name, "enableNotificationHUD")
        XCTAssertTrue(Defaults.Keys.enableNotificationHUD.defaultValue, "总开关默认开（不给用户添意外）")
        XCTAssertEqual(
            Defaults.Keys.notificationHUDBackgroundStyle.defaultValue,
            .liquidGlass,
            "背景默认液态玻璃（用户 2026-09-28 口径：要能选「是否为液态玻璃模式」）"
        )

        // 取值词汇表：rawValue 是设置页 Picker 直接显示的字面量（同 OSD 的 Material 选择器）
        XCTAssertEqual(NotificationHUDBackgroundStyle.allCases.map(\.rawValue), ["Liquid glass", "Solid"])
        XCTAssertEqual(NotificationHUDBackgroundStyle(rawValue: "Liquid glass"), .liquidGlass)

        let suiteName = "com.cmeng.gourd.tests.notificationHUDBackgroundStyle"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            return XCTFail("建不出临时 suite（\(suiteName)）")
        }
        defer { suite.removePersistentDomain(forName: suiteName) }
        let key = Defaults.Key<NotificationHUDBackgroundStyle>(
            "notificationHUDBackgroundStyle",
            default: .liquidGlass,
            suite: suite
        )

        XCTAssertEqual(Defaults[key], .liquidGlass, "没写过时读回声明默认值")
        Defaults[key] = .solid
        XCTAssertEqual(Defaults[key], .solid, "写盘 → 读回同一档")
        XCTAssertEqual(suite.string(forKey: key.name), "Solid", "盘上存的就是 rawValue 字符串")
        Defaults[key] = .liquidGlass
        XCTAssertEqual(Defaults[key], .liquidGlass, "再切回默认档同样往返")
    }

    // MARK: - 通知浮层卡片的尺寸口径（D-23）

    /// **固定尺寸**（2026-09-28 用户：「尺寸不固定，要固定个初始大小」）：卡片 = **320 × 64 × 倍率**，
    /// 且**与窗口用同一个来源**（`ModuleHUDWindowHost.contentSize(scale:)`）——两处各写一份常量
    /// 就会出现「窗口 416pt、卡片 300pt」的错位。
    func testHUDWindowFixedContentSizeScalesAndClamps() {
        // 基准档（倍率 1.0）= 320 × 64
        XCTAssertEqual(ModuleHUDWindowHost.contentSize(scale: 1.0), CGSize(width: 320, height: 64))
        // 默认档（1.3）：320 × 1.3 = 416，64 × 1.3 = 83.2（保留两位小数，避开浮点尾巴）
        XCTAssertEqual(ModuleHUDWindowHost.contentSize(scale: 1.3), CGSize(width: 416, height: 83.2))
        XCTAssertEqual(ModuleHUDWindowHost.contentSize(scale: 2.0), CGSize(width: 640, height: 128))

        // 越界值夹取到区间端点（用户直接改 UserDefaults 写了个离谱值时也要有确定尺寸）
        XCTAssertEqual(ModuleHUDWindowHost.contentSize(scale: 5.0), ModuleHUDWindowHost.contentSize(scale: 2.0))
        XCTAssertEqual(ModuleHUDWindowHost.contentSize(scale: 0.1), ModuleHUDWindowHost.contentSize(scale: 0.8))
        XCTAssertEqual(ModuleHUDWindowHost.hudScaleRange, 0.8...2.0, "与设置滑块 0.8…2.0 同源")

        // 卡片与窗口同一来源（模块侧 metrics 的 cardSize 必须就是这一组常量）
        XCTAssertEqual(NotificationHUDCardLayout.metrics(scale: 1.3).cardSize, ModuleHUDWindowHost.contentSize(scale: 1.3))
        XCTAssertEqual(NotificationHUDCardLayout.scaleRange, ModuleHUDWindowHost.hudScaleRange)
    }

    /// **倍率越大、每一项都越大**：字号 / 图标 / 内边距 / 卡片尺寸随倍率单调增，
    /// 且默认值 1.3 明显大于改造前的口径（这就是用户要的「调大一些」）。
    func testNotificationHUDCardMetricsScaleWithSetting() {
        let small = NotificationHUDCardLayout.metrics(scale: 1.0)
        let scaled = NotificationHUDCardLayout.metrics(scale: 1.3)
        let large = NotificationHUDCardLayout.metrics(scale: 2.0)

        XCTAssertLessThan(small.titleSize, scaled.titleSize)
        XCTAssertLessThan(scaled.titleSize, large.titleSize)
        XCTAssertLessThan(small.bodySize, scaled.bodySize)
        XCTAssertLessThan(small.iconSize, scaled.iconSize)
        XCTAssertLessThan(small.padding, scaled.padding)
        XCTAssertLessThan(small.cardSize.width, scaled.cardSize.width)
        XCTAssertLessThan(small.cardSize.height, scaled.cardSize.height)

        // 1.3 倍 = 基准 × 1.3（保留两位小数，避开浮点尾巴）
        XCTAssertEqual(scaled.titleSize, 15.6, accuracy: 0.001)
        XCTAssertEqual(scaled.bodySize, 14.3, accuracy: 0.001)
        XCTAssertEqual(scaled.iconSize, 18.2, accuracy: 0.001)
        XCTAssertEqual(scaled.padding, 13, accuracy: 0.001)
        // 卡片尺寸 = 320 × 64 × 1.3（固定常量，不再按内容 / 屏幕分档）
        XCTAssertEqual(scaled.cardSize, CGSize(width: 416, height: 83.2))
    }

    /// **边界一：下限 0.8**——每一项按 0.8 缩放，字体仍可读（标题 ≥ 9pt），文字列不会被压到 0。
    func testNotificationHUDCardMetricsAtLowerBound() {
        let metrics = NotificationHUDCardLayout.metrics(scale: 0.8)
        XCTAssertEqual(metrics.titleSize, 9.6, accuracy: 0.001)
        XCTAssertEqual(metrics.bodySize, 8.8, accuracy: 0.001)
        XCTAssertEqual(metrics.iconSize, 11.2, accuracy: 0.001)
        XCTAssertGreaterThan(metrics.titleSize, 8, "0.8 倍下标题仍要能读")
        XCTAssertGreaterThan(metrics.textMaxWidth, 0, "文字列宽度不得归零")
        XCTAssertEqual(metrics.cardSize, CGSize(width: 256, height: 51.2))
    }

    /// **边界二：上限 2.0**——字号翻倍、卡片也翻倍（640 × 128）；
    /// 卡片尺寸不再有「绝对上限」：固定尺寸下它就是常量 × 倍率，倍率本身已被夹到 2.0。
    func testNotificationHUDCardMetricsAtUpperBound() {
        let metrics = NotificationHUDCardLayout.metrics(scale: 2.0)
        XCTAssertEqual(metrics.titleSize, 24, accuracy: 0.001)
        XCTAssertEqual(metrics.bodySize, 22, accuracy: 0.001)
        XCTAssertEqual(metrics.iconSize, 28, accuracy: 0.001)
        XCTAssertEqual(metrics.cardSize, CGSize(width: 640, height: 128))
        // 文字列 = 卡片宽度 −（两侧内边距 + 图标 + 两个间距 + × 及其余量）
        XCTAssertLessThan(metrics.textMaxWidth, metrics.cardSize.width)
        XCTAssertGreaterThan(metrics.textMaxWidth, 500, "上限档下文字列仍要足够宽")
        // 间距 / × / 点击余量都按同一倍率缩放：改任一项都不会让内容比卡片宽（固定尺寸下就是右侧被裁）
        XCTAssertEqual(metrics.lineSpacing, 4, accuracy: 0.001)
        XCTAssertEqual(metrics.closeSize, 22, accuracy: 0.001)
    }

    /// **越界值夹取到区间端点**：用户直接改 UserDefaults 写了个离谱值（0.2 / 5.0）时，
    /// 呈现必须是确定的（同 `ttl` 的夹取口径），而不是崩或缩成一条。
    func testNotificationHUDCardMetricsClampsOutOfRangeScale() {
        XCTAssertEqual(
            NotificationHUDCardLayout.metrics(scale: 0.2),
            NotificationHUDCardLayout.metrics(scale: 0.8),
            "低于下限按 0.8 算"
        )
        XCTAssertEqual(
            NotificationHUDCardLayout.metrics(scale: 5.0),
            NotificationHUDCardLayout.metrics(scale: 2.0),
            "高于上限按 2.0 算"
        )
    }

    // MARK: - 主面板背景（D-26）

    /// **主面板背景的生效范围是纯函数**（2026-09-28 用户要求给展开态主面板加「液态玻璃」配置）：
    /// 玻璃两档**只在「展开态」或「非刘海屏的浮动药丸」上生效**，刘海屏的折叠态保持纯黑
    /// （折叠态要与物理刘海对齐融合，玻璃会露出壁纸、在刘海下方形成一块突兀的方块）。
    ///
    /// 四条组合逐条钉住——这是「用户选了玻璃但折叠态没变」不算 bug 的唯一依据，
    /// 也是唯一一条把「状态」与「样式」绑在一起的判据（样式本身三档都能选）。
    func testPanelBackgroundUsesStyleOnlyForExpandedOrFloatingPill() {
        XCTAssertTrue(
            panelBackgroundUsesStyle(isOpen: true, isDynamicIslandMode: false),
            "展开态（用户截图里音乐 / 日历那一屏）：标准刘海屏也要走配置的样式"
        )
        XCTAssertTrue(
            panelBackgroundUsesStyle(isOpen: true, isDynamicIslandMode: true),
            "展开态 + 浮动药丸：两条件任一成立即生效"
        )
        XCTAssertTrue(
            panelBackgroundUsesStyle(isOpen: false, isDynamicIslandMode: true),
            "非刘海屏的折叠态就是那块浮动药丸：本身就是独立悬浮面板，没有要与物理刘海融合的前提"
        )
        XCTAssertFalse(
            panelBackgroundUsesStyle(isOpen: false, isDynamicIslandMode: false),
            "刘海屏的折叠态：**保持纯黑**（唯一的 false 组合，玻璃在这里会露出壁纸）"
        )
    }

    /// **滚动边缘的黑色渐隐遮罩只在纯黑档显示**（2026-09-28 用户反馈，截图是笔记 tab 且面板已切液态玻璃：
    /// 「这个上面和下面的黑色框是什么，得去掉」）。
    ///
    /// 遮罩（`Color.black.opacity(0.65) → .clear` 的 16pt 渐变）是给纯黑面板做的滚动边缘淡出，
    /// 换到玻璃底上就成了两条突兀的黑带。判据收在 `shouldShowScrollFadeMask`，消费点只有两处：
    /// 笔记 tab 的滚动网格（`NoteListView`）与计时器预设列表（`NotchTimerView.presetColumn`）。
    func testScrollFadeMaskOnlyShownForSolidBlackPanel() {
        XCTAssertTrue(
            shouldShowScrollFadeMask(panelBackgroundStyle: .solidBlack),
            "纯黑档：遮罩是它本来要干的事（黑底上的滚动边缘淡出），保持原样"
        )
        XCTAssertFalse(
            shouldShowScrollFadeMask(panelBackgroundStyle: .liquidGlass),
            "液态玻璃档：用户截图的那一档——黑色渐变必须消失"
        )
        XCTAssertFalse(
            shouldShowScrollFadeMask(panelBackgroundStyle: .frostedGlass),
            "毛玻璃档同理：黑带在任何玻璃底上都是异物"
        )
    }

    /// **面板顶部的不透明黑带高度**（2026-09-28 用户反馈「不能强硬拉伸，菜单栏里面的图标都变形了」；
    /// 2026-09-29 用户反馈「顶部的高度不够，比系统的黑色区域要窄」→ 改为 `max(刘海, 菜单栏) + 1`）：
    /// 玻璃两档都是 behindWindow 材质（`NSGlassEffectView` / `NSVisualEffectView.hudWindow`），
    /// 采样的就是窗口背后的画面；面板顶边与系统 UI 带同高，于是菜单栏图标被采进玻璃里糊成一片。
    /// 因此这条带必须不透明，高度取**系统 UI 带（刘海与菜单栏里更高的那个）+ 1pt**——
    /// 刘海屏上 `safeAreaInsets.top`（本机内置屏实测 32）比「屏顶 − visibleFrame 顶」（33）小 1pt，
    /// 只取刘海高度会从面板顶部露出 1pt 玻璃（用户看到的「比系统黑区窄」）。
    func testPanelTopOpaqueBandHeightPrefersNotchHeight() {
        XCTAssertEqual(
            panelTopOpaqueBandHeight(safeAreaTop: 38, menuBarHeight: 24),
            39,
            "刘海屏：刘海高度（38）是两者里更高的那个 → 38 + 1"
        )
        XCTAssertEqual(
            panelTopOpaqueBandHeight(safeAreaTop: 32, menuBarHeight: 33),
            34,
            "本机内置屏的实测口径：刘海 32 < 菜单栏 33 → 取菜单栏 33 + 1（盖住系统黑区）"
        )
        XCTAssertEqual(
            panelTopOpaqueBandHeight(safeAreaTop: 32, menuBarHeight: 0),
            33,
            "菜单栏取不到（0）时只用刘海高度，仍 +1"
        )
    }

    /// **菜单栏比刘海高时取菜单栏高度**（2026-09-29 新增要求）：外接屏 / 缩放分辨率下
    /// 「屏顶 − visibleFrame 顶」可能比 `safeAreaInsets.top` 更大，这时黑带必须跟着菜单栏走，
    /// 否则玻璃会把菜单栏图标采进来（同 2026-09-28 那条反馈的根因）。
    func testPanelTopOpaqueBandHeightTakesMenuBarWhenTallerThanNotch() {
        XCTAssertEqual(
            panelTopOpaqueBandHeight(safeAreaTop: 24, menuBarHeight: 38),
            39,
            "菜单栏 38 > 刘海 24 → 取 38 + 1（不再是「只认刘海高度」）"
        )
        XCTAssertEqual(
            panelTopOpaqueBandHeight(safeAreaTop: 30, menuBarHeight: 999),
            1000,
            "悬殊口径下同样取大者：判据是 max 而不是「谁优先」"
        )
    }

    /// 非刘海屏取**菜单栏高度**（屏顶与 `visibleFrame` 顶之差，口径同
    /// `ModuleHUDWindowHost.topInset(safeAreaTop:frameMaxY:visibleFrameMaxY:)`）：
    /// 浮动药丸的顶边落在菜单栏带里，不盖住就会把菜单栏图标采进玻璃。
    /// 异常输入一律夹到 0（= 不加黑带，退回改造前观感），**不产生负高度**（负的 `frame(height:)` 会崩）。
    func testPanelTopOpaqueBandHeightFallsBackToMenuBarHeight() {
        XCTAssertEqual(
            panelTopOpaqueBandHeight(safeAreaTop: 0, menuBarHeight: 24),
            25,
            "非刘海屏：黑带 = 菜单栏高度 + 1"
        )
        XCTAssertEqual(
            panelTopOpaqueBandHeight(safeAreaTop: 0, menuBarHeight: -5),
            0,
            "可见框高于屏顶（异常）→ 夹到 0：不加黑带，不产生负高度"
        )
        XCTAssertEqual(
            panelTopOpaqueBandHeight(safeAreaTop: 0, menuBarHeight: .nan),
            0,
            "非有限值同样夹到 0，不把 NaN 传进 frame(height:)"
        )
        XCTAssertEqual(
            panelTopOpaqueBandHeight(safeAreaTop: .nan, menuBarHeight: 0),
            0,
            "两个入参都取不到 → 0：不该凭空多出 1pt 黑边"
        )
        XCTAssertEqual(
            panelTopOpaqueBandHeight(safeAreaTop: 0, menuBarHeight: 0),
            0,
            "没有系统 UI 带（都为 0）→ 0，而不是 1"
        )
        XCTAssertEqual(
            panelTopOpaqueBandHeight(for: nil),
            0,
            "取不到屏 → 0（不加黑带，退回改造前的玻璃底观感）"
        )
    }

    // MARK: - 展开态高度（120…850，按屏高 90% 收敛；2026-09-28「高度可以调」+ 2026-09-29 上限收 850）

    /// 下界恒定 120：低于它的值一律抬到 120（面板再矮就装不下 tab 栏与内容）。
    /// 上界与屏无关的两个极端（不管传多大的屏）也一并钉住。
    func testClampedOpenNotchHeightKeepsLowerBound() {
        XCTAssertEqual(
            clampedOpenNotchHeight(0, screenVisibleHeight: 1000),
            openNotchHeightRange.lowerBound,
            "0（用户直接改 UserDefaults）抬到 120"
        )
        XCTAssertEqual(
            clampedOpenNotchHeight(60, screenVisibleHeight: nil),
            openNotchHeightRange.lowerBound,
            "取不到屏时同样有下界"
        )
        XCTAssertEqual(
            clampedOpenNotchHeight(120, screenVisibleHeight: 1000),
            120,
            "正好是下界：原样保留"
        )
        XCTAssertEqual(
            clampedOpenNotchHeight(.nan, screenVisibleHeight: 1000),
            120,
            "非有限值不参与比较，退回下界（不崩、不产生 NaN 尺寸）"
        )
    }

    /// **可配上限就是 850**（2026-09-29 用户明确「展开的高度最高是 850」）：
    /// 高屏上有效上界 = 850（不再按 1000 放行）。
    func testOpenNotchHeightConfiguredUpperBoundIs850() {
        XCTAssertEqual(openNotchHeightRange, 120...850, "可配范围（也是滑块的两端）")
        XCTAssertEqual(
            effectiveOpenNotchHeightUpperBound(screenVisibleHeight: 1200),
            850,
            "1200 * 0.9 = 1080 > 850 → 取可配上限 850"
        )
        XCTAssertEqual(
            clampedOpenNotchHeight(850, screenVisibleHeight: 1200),
            850,
            "正好是可配上限：原样生效（滑块拖到底就是这个值）"
        )
        XCTAssertEqual(
            clampedOpenNotchHeight(851, screenVisibleHeight: 1200),
            850,
            "超过可配上限 1pt 也夹回 850"
        )
        XCTAssertEqual(
            clampedOpenNotchHeight(1500, screenVisibleHeight: nil),
            850,
            "取不到屏 → 回落可配上限 850"
        )
        // 850 与「屏高 90%」取小：949（本机内置屏的 visibleFrame 高）→ 854.1 > 850 → 850
        XCTAssertEqual(
            effectiveOpenNotchHeightUpperBound(screenVisibleHeight: 949),
            850,
            "本机内置屏：854.1 > 850 → 850"
        )
        // 矮屏上仍然按屏收敛（比 850 更小）
        XCTAssertEqual(
            effectiveOpenNotchHeightUpperBound(screenVisibleHeight: 900),
            810,
            "900 * 0.9 = 810 < 850 → 810"
        )
    }

    /// 区间内的值**原样通过**（用户拖到 800 时不能再被悄悄改掉）：这里用「可见高度 1200 → 上界 850」
    /// 的屏幕，800 落在区间内。改造前 400 的上限会把它夹成 400 —— 那正是用户反馈的问题。
    func testClampedOpenNotchHeightPassesValuesInsideRange() {
        let visible: CGFloat = 1200
        XCTAssertEqual(
            effectiveOpenNotchHeightUpperBound(screenVisibleHeight: visible),
            850,
            "1200 的 90% = 1080 > 850，因此上界是可配上限 850"
        )
        for value: CGFloat in [400, 401, 800, 850] {
            XCTAssertEqual(
                clampedOpenNotchHeight(value, screenVisibleHeight: visible),
                value,
                "\(value) 在 120…850 内且低于屏高 90%，必须原样生效"
            )
        }
    }

    /// 超过上界被**夹到屏高 90%**（矮屏）：900 可见高度的屏上，1500 与 850 都落在 810；
    /// 取不到屏时才回落到可配上限 850。
    func testClampedOpenNotchHeightClampsToScreenLimit() {
        let visible: CGFloat = 900
        XCTAssertEqual(
            effectiveOpenNotchHeightUpperBound(screenVisibleHeight: visible),
            810,
            "900 * 0.9 = 810（比可配上限 850 更小）"
        )
        XCTAssertEqual(clampedOpenNotchHeight(1500, screenVisibleHeight: visible), 810, "离谱值夹到屏高 90%")
        XCTAssertEqual(clampedOpenNotchHeight(850, screenVisibleHeight: visible), 810, "可配上限也要按屏收敛")
        XCTAssertEqual(clampedOpenNotchHeight(810, screenVisibleHeight: visible), 810, "正好在上界：原样保留")
        XCTAssertEqual(clampedOpenNotchHeight(1500, screenVisibleHeight: nil), 850, "取不到屏 → 回落 850")

        // 极矮的屏：90% 低于可配下界时区间会反向，必须保底到 120（而不是给一个 < 120 的上界）
        XCTAssertEqual(
            effectiveOpenNotchHeightUpperBound(screenVisibleHeight: 100),
            120,
            "100 * 0.9 = 90 < 120 → 上界保底 120"
        )
        XCTAssertEqual(clampedOpenNotchHeight(1000, screenVisibleHeight: 100), 120)
    }

    /// **滑块与夹取同源**：设置页滑块的上界就是 `effectiveOpenNotchHeightUpperBound`，
    /// 因此「滑块能拖到的每个值」都不会再被 `clampedOpenNotchHeight` 改掉——否则用户看到的是
    /// 「拖了没用」（本次改造要修的正是这种自相矛盾）。
    /// 屏高列表里特意放了本机内置屏（949 → 854.1，被 850 收住）与高屏（1200/2400 → 850）。
    func testOpenNotchHeightSliderUpperBoundMatchesClamp() {
        for visible: CGFloat in [600, 900, 949, 1112, 1200, 2400] {
            let upper = effectiveOpenNotchHeightUpperBound(screenVisibleHeight: visible)
            XCTAssertGreaterThanOrEqual(upper, openNotchHeightRange.lowerBound)
            XCTAssertLessThanOrEqual(upper, openNotchHeightRange.upperBound)
            for value in stride(from: openNotchHeightRange.lowerBound, through: upper, by: 10) {
                XCTAssertEqual(
                    clampedOpenNotchHeight(value, screenVisibleHeight: visible),
                    value,
                    "滑块能拖到的 \(value)（屏可见高度 \(visible)）必须原样生效"
                )
            }
        }
    }

    /// 判据与**档位数量**同源：给 `NotchPanelBackgroundStyle` 加第四档时，这条会失败并提醒
    /// 「新档要不要显示遮罩」必须显式表态（而不是默默沿用某个默认）。
    func testScrollFadeMaskDecisionCoversEveryPanelBackgroundStyle() {
        let shownStyles = NotchPanelBackgroundStyle.allCases.filter {
            shouldShowScrollFadeMask(panelBackgroundStyle: $0)
        }
        XCTAssertEqual(
            shownStyles,
            [.solidBlack],
            "三档里**只有纯黑档**显示遮罩；新增档位必须在此显式登记"
        )
    }

    /// 主面板背景键的**声明默认值** + 三档取值词汇表 + **序列化往返**（写盘 → 读回）。
    ///
    /// 默认必须是 `.solidBlack`：改造前主面板底是 `ContentView` 里写死的 `.background(.black)`，
    /// 新键的默认值不该改变任何老用户的观感（升级即变色是回归）。
    /// 往返走临时 suite（不碰开发机 `com.cmeng.gourd` 域）：枚举存的是 `rawValue` 字符串
    /// （`RawRepresentable` 桥，同 `notificationHUDBackgroundStyle`），因此断言盘上真的出现
    /// `"Liquid glass"` 而不只是一个内存值。
    func testNotchPanelBackgroundStyleKeyDefaultsAndRoundTrip() {
        XCTAssertEqual(Defaults.Keys.notchPanelBackgroundStyle.name, "notchPanelBackgroundStyle")
        XCTAssertEqual(
            Defaults.Keys.notchPanelBackgroundStyle.defaultValue,
            .solidBlack,
            "默认纯黑（与改造前写死的 .background(.black) 完全一致）"
        )

        // 取值词汇表：rawValue 是设置页 Picker 直接显示的字面量（同 OSD 的 Material 选择器）
        XCTAssertEqual(
            NotchPanelBackgroundStyle.allCases.map(\.rawValue),
            ["Solid black", "Liquid glass", "Frosted glass"]
        )
        XCTAssertEqual(NotchPanelBackgroundStyle(rawValue: "Liquid glass"), .liquidGlass)
        XCTAssertEqual(NotchPanelBackgroundStyle(rawValue: "Frosted glass"), .frostedGlass)
        XCTAssertEqual(Set(NotchPanelBackgroundStyle.allCases.map(\.id)).count, 3, "三档 id 互不相同")

        let suiteName = "com.cmeng.gourd.tests.notchPanelBackgroundStyle"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            return XCTFail("建不出临时 suite（\(suiteName)）")
        }
        defer { suite.removePersistentDomain(forName: suiteName) }
        let key = Defaults.Key<NotchPanelBackgroundStyle>(
            "notchPanelBackgroundStyle",
            default: .solidBlack,
            suite: suite
        )

        XCTAssertEqual(Defaults[key], .solidBlack, "没写过时读回声明默认值")
        Defaults[key] = .liquidGlass
        XCTAssertEqual(Defaults[key], .liquidGlass, "写盘 → 读回同一档")
        XCTAssertEqual(suite.string(forKey: key.name), "Liquid glass", "盘上存的就是 rawValue 字符串")
        Defaults[key] = .frostedGlass
        XCTAssertEqual(Defaults[key], .frostedGlass, "第三档同样往返")
        XCTAssertEqual(suite.string(forKey: key.name), "Frosted glass")
        Defaults[key] = .solidBlack
        XCTAssertEqual(Defaults[key], .solidBlack, "再切回默认档同样往返")
    }

    /// **固定尺寸与内容无关**（用户：「外接屏可以显示，但尺寸不固定」）：`metrics` 只吃倍率——
    /// 卡片没有「按内容」「按刘海 / 非刘海屏」的第二条输入，内容再长也不改尺寸
    /// （超长内容按 `lineLimit` 在卡片内截断，见 `hudDetail` 的用例）。
    func testNotificationHUDCardMetricsDependOnScaleOnly() {
        let scaleOne = NotificationHUDCardLayout.metrics(scale: 1.0)
        XCTAssertEqual(scaleOne.cardSize, CGSize(width: 320, height: 64), "同一倍率只有一个尺寸")
        // 文字列宽度是「卡片宽度 − 其它元素」的确定值：不同倍率下按同一条算式缩放
        let ratio = scaleOne.textMaxWidth / scaleOne.cardSize.width
        let largeRatio = NotificationHUDCardLayout.metrics(scale: 2.0).textMaxWidth
            / NotificationHUDCardLayout.metrics(scale: 2.0).cardSize.width
        XCTAssertEqual(ratio, largeRatio, accuracy: 0.01, "文字列占比不随倍率变（同一套算式）")
    }

    /// **高度预算够「标题 + 正文 2 行」**（实测踩到的坑，钉住它）：固定高度 64 × 倍率，
    /// 上下内边距若与左右同档（10 × 倍率 = 13pt），正文会被挤成 **1 行 + `…`**——
    /// 长正文通知因此丢掉了「最多 2 行」的呈现。所以垂直内边距单列一档（5 × 倍率）。
    ///
    /// 估算口径：系统字体的行高按 **1.3 × 字号**算（保守偏大）；要求
    /// `标题 + 行间距 + 2 × 正文 ≤ 卡片高度 − 上下内边距`。
    func testNotificationHUDCardHeightFitsTitleAndTwoBodyLines() {
        for scale in [0.8, 1.0, 1.3, 2.0] {
            let metrics = NotificationHUDCardLayout.metrics(scale: scale)
            let contentHeight = metrics.cardSize.height - metrics.verticalPadding * 2
            let needed = metrics.titleSize * 1.3 + metrics.lineSpacing + metrics.bodySize * 1.3 * 2
            XCTAssertLessThanOrEqual(needed, contentHeight, "倍率 \(scale)：高度预算不够 2 行正文（会被挤成 1 行 + …）")
            XCTAssertLessThan(metrics.verticalPadding, metrics.padding, "垂直内边距必须比水平小一档")
        }

        // 反证：上下内边距与左右同档时预算不够（这就是修复前的形态）
        let defaultMetrics = NotificationHUDCardLayout.metrics(scale: 1.3)
        let uniformPaddingBudget = defaultMetrics.cardSize.height - defaultMetrics.padding * 2
        let needed = defaultMetrics.titleSize * 1.3 + defaultMetrics.lineSpacing + defaultMetrics.bodySize * 1.3 * 2
        XCTAssertGreaterThan(
            needed,
            uniformPaddingBudget,
            "同档内边距下确实装不下（记录的实测根因：\(needed) > \(uniformPaddingBudget)）"
        )
    }

    /// 键本身的口径：`notificationHUDScale` 的**声明默认值是 1.3**（2026-09-28 用户要求
    /// 「外接屏太小，需要调大一些」）——断言读 `defaultValue`，不受开发机上真实 UserDefaults 影响。
    func testNotificationHUDScaleKeyDefaultsToLargerThanBefore() {
        XCTAssertEqual(Defaults.Keys.notificationHUDScale.name, "notificationHUDScale", "键名与设置滑块一致")
        XCTAssertEqual(Defaults.Keys.notificationHUDScale.defaultValue, 1.3, accuracy: 0.0001)
        XCTAssertGreaterThan(
            Defaults.Keys.notificationHUDScale.defaultValue,
            1.0,
            "默认必须比改造前大（改造前的字号口径 = 1.0）"
        )
        // 默认值必须落在滑块区间内，否则设置页一打开滑块就跳到端点
        XCTAssertTrue(
            NotificationHUDCardLayout.scaleRange.contains(Defaults.Keys.notificationHUDScale.defaultValue),
            "默认值必须落在 \(NotificationHUDCardLayout.scaleRange) 内"
        )
    }

    /// **新记录筛选**是纯函数（实时化的核心判据）：`id > 基线`、**按 id 升序**、**按 id 去重**。
    ///
    /// 它与 SQL 侧的 `WHERE rec_id > ? ORDER BY rec_id ASC` 是同一口径——单测钉住它，
    /// 就不必为了验证「哪些算新增」去读真实的系统通知库（那既慢又要完全磁盘访问）。
    func testNotificationNewRecordsFilterSortAndDeduplicate() {
        // 空集：没有输入就没有输出（事件驱动下"文件变了但没有新记录"是常态，不能崩）
        XCTAssertTrue(NotificationStore.newRecords(in: [], above: 10).isEmpty)
        XCTAssertTrue(NotificationStore.newRecords(in: [], above: 0).isEmpty)

        // 全部 ≤ 基线：旧记录一条都不算新增（含**恰好等于基线**的那条——判据是 `>` 不是 `>=`）
        XCTAssertTrue(
            NotificationStore.newRecords(
                in: [notificationItem(3), notificationItem(9), notificationItem(10)],
                above: 10
            ).isEmpty
        )

        // 乱序输入 → 输出按 id 升序（调用方按到达顺序累加，`hudCandidate` 取 `.last` = 最新）
        XCTAssertEqual(
            NotificationStore.newRecords(
                in: [notificationItem(15), notificationItem(11), notificationItem(18), notificationItem(13)],
                above: 10
            ).map(\.id),
            [11, 13, 15, 18]
        )

        // 重复 id（同一批里重复投递 / 事件重放）只算一条：不过滤会让未读数虚高
        XCTAssertEqual(
            NotificationStore.newRecords(
                in: [notificationItem(11), notificationItem(12), notificationItem(11), notificationItem(12)],
                above: 10
            ).map(\.id),
            [11, 12]
        )

        // 重复 + 乱序 + 基线的混合：一条不多、一条不少、顺序稳定
        XCTAssertEqual(
            NotificationStore.newRecords(
                in: [
                    notificationItem(10), notificationItem(12), notificationItem(11),
                    notificationItem(2), notificationItem(12), notificationItem(11),
                ],
                above: 10
            ).map(\.id),
            [11, 12]
        )

        // 基线 0（空库 / 首次取数）：全部都是新增，整段升序
        XCTAssertEqual(
            NotificationStore.newRecords(in: [notificationItem(2), notificationItem(1)], above: 0).map(\.id),
            [1, 2]
        )
        // 负基线（理论上的回退）不改变判据
        XCTAssertEqual(NotificationStore.newRecords(in: [notificationItem(1)], above: -5).map(\.id), [1])
    }

    /// 浮层候选与新记录筛选是同一口径（`hudCandidate` = 升序结果的 `.last`）：
    /// 去重不会让「最新那一条」变成别人，`>` 基线也不会漏掉紧邻基线的第一条。
    func testNotificationHUDCandidateMatchesNewRecordsOrdering() {
        let newItems = [notificationItem(12), notificationItem(11), notificationItem(12)]
        XCTAssertEqual(NotificationStore.newRecords(in: newItems, above: 10).last?.id, 12)
        XCTAssertEqual(NotificationStore.hudCandidate(in: newItems, above: 10)?.id, 12)
        // 只有一条晚于基线时，浮层就是那一条（实时性验收里最常见的形态）
        XCTAssertEqual(NotificationStore.hudCandidate(in: [notificationItem(4), notificationItem(11)], above: 10)?.id, 11)
        XCTAssertNil(NotificationStore.hudCandidate(in: [notificationItem(4), notificationItem(10)], above: 10))
    }

    /// 事件驱动 / 兜底轮询的两个常量口径：兜底是 **60s**（原来 30s 轮询的替代），
    /// 不能再回到「亚秒轮询」——实时性由文件事件负责（09 §5.5）。
    func testNotificationFallbackPollIntervalIsCoarse() {
        XCTAssertEqual(NotificationStore.fallbackPollInterval, 60, "兜底轮询是 60s；实时性靠文件事件")
    }

    /// 「关闭 / 清除」的过滤是**纯函数**：`fetchRecent` / `fetchNew` 返回前按 id 滤掉已关闭的条目。
    ///
    /// 这是只读原则在代码上的落点：**过滤只发生在我们这一侧**，函数既不排序也不去重，
    /// 更不触碰任何库状态——关闭只是「岛上不再显示这一条」。
    func testNotificationDismissedFilterIsPure() {
        let items = [notificationItem(11), notificationItem(12), notificationItem(13)]

        // 没有已关闭条目（热路径）：原样返回，且**同一个数组实例**
        let untouched = NotificationCenterReader.visible(in: items, excluding: [])
        XCTAssertEqual(untouched.map(\.id), [11, 12, 13])

        // 空输入：空输出（不给下游留 nil/崩溃路径）
        XCTAssertTrue(NotificationCenterReader.visible(in: [], excluding: [11, 12]).isEmpty)

        // 滤掉命中项，保持输入顺序（不排序、不去重）
        XCTAssertEqual(
            NotificationCenterReader.visible(in: items, excluding: [12]).map(\.id),
            [11, 13]
        )
        // 关闭集合里有「不在这一批里」的 id：不影响结果（跨批次的关闭状态）
        XCTAssertEqual(
            NotificationCenterReader.visible(in: items, excluding: [1, 99, 1000]).map(\.id),
            [11, 12, 13]
        )
        // 全部关闭 → 空列表（面板显示「暂无通知」，不是错误）
        XCTAssertTrue(NotificationCenterReader.visible(in: items, excluding: [11, 12, 13]).isEmpty)
    }

    /// 已关闭集合的**落盘裁剪**是纯函数：只保留最近 `limit` 个（尾部 = 最近关闭的）并去重。
    /// 上限存在的意义是「用一年后 UserDefaults 里不该堆几万个 id」。
    func testNotificationDismissedTrimmingKeepsMostRecent() {
        XCTAssertEqual(NotificationStore.dismissedLimit, 500, "上限口径：保留最近 500 个")

        // 未超上限：原样（保序）
        XCTAssertEqual(NotificationStore.trimmed([3, 1, 2], limit: 5), [3, 1, 2])
        // 恰好等于上限：不裁剪
        XCTAssertEqual(NotificationStore.trimmed([1, 2, 3], limit: 3), [1, 2, 3])
        // 超上限：只留**最近** limit 个（尾部），最旧的被丢掉
        XCTAssertEqual(NotificationStore.trimmed([1, 2, 3, 4, 5], limit: 3), [3, 4, 5])
        // 重复 id 去重（重复只算一次关闭）
        XCTAssertEqual(NotificationStore.trimmed([7, 7, 8, 8, 9], limit: 10), [7, 8, 9])
        // 去重后再裁剪：`[5,5,6,6,7,7]` 去重成 3 个，limit 2 → 留最近两个
        XCTAssertEqual(NotificationStore.trimmed([5, 5, 6, 6, 7, 7], limit: 2), [6, 7])
        // 边界：空输入、limit 0（丢弃一切）、limit 1
        XCTAssertTrue(NotificationStore.trimmed([], limit: 10).isEmpty)
        XCTAssertTrue(NotificationStore.trimmed([1, 2, 3], limit: 0).isEmpty)
        XCTAssertEqual(NotificationStore.trimmed([1, 2, 3], limit: 1), [3])
    }

    /// `dismissedNotificationIDs` 键本身的口径：键名与类型（`[Int]`）固定，默认空。
    /// 断言读 `defaultValue` 而不是当前生效值——不受开发机上真实 UserDefaults 影响。
    func testDismissedNotificationIDsKeyShape() {
        XCTAssertEqual(Defaults.Keys.dismissedNotificationIDs.name, "dismissedNotificationIDs")
        XCTAssertEqual(Defaults.Keys.dismissedNotificationIDs.defaultValue, [], "默认没有已关闭条目")
    }

    // MARK: - AX 横幅通道（P2e：实时 + 真关闭）

    /// **本机实测（macOS 27）**的横幅树形状 → 解析结果。
    ///
    /// 夹具逐字对齐 `~/Library/Logs/Gourd/ax-banner-probe.log` 里的真配置探针原文：
    /// 静态文本是 标题 → 副标题 → 正文（App 名**不在**里面）；关闭是**横幅容器上的自定义动作**，
    /// 名字含「关闭」；容器描述形如 `"<App 名> <标题>, <副标题>, <正文>"`。
    func testNotificationBannerParseMatchesMacOS27Shape() {
        let snapshot = Self.bannerSnapshot(
            description: "脚本编辑器 无副标题测试, 正文只有一行",
            texts: ["无副标题测试", "正文只有一行"],
            actions: ["AXPress", "Name:关闭\nTarget:0x0\nSelector:(null)"]
        )

        let content = NotificationBannerParser.parse(snapshot)
        XCTAssertTrue(content.foundBannerRoot, "subrole=AXNotificationCenterBanner 必须被认成横幅")
        XCTAssertEqual(content.appName, "脚本编辑器", "App 名从容器描述首段剥掉标题得到")
        XCTAssertEqual(content.title, "无副标题测试", "第一个静态文本 = 标题")
        XCTAssertEqual(content.subtitle, "", "两个静态文本时没有副标题")
        XCTAssertEqual(content.body, "正文只有一行", "最后一个静态文本 = 正文")
        XCTAssertEqual(content.closeActionName, "Name:关闭\nTarget:0x0\nSelector:(null)", "自定义动作名要原样保留（截断就执行不了）")
        XCTAssertEqual(content.closeLabel, "自定义动作: Name:关闭\nTarget:0x0\nSelector:(null)")

        // 带副标题（三个静态文本）：标题 / 副标题 / 正文 依次取
        let withSubtitle = NotificationBannerParser.parse(
            Self.bannerSnapshot(
                description: "脚本编辑器 AX 探针, 副标题, AX 实时测试",
                texts: ["AX 探针", "副标题", "AX 实时测试"],
                actions: ["AXPress", "Name:关闭\nTarget:0x0\nSelector:(null)"]
            )
        )
        XCTAssertEqual(withSubtitle.appName, "脚本编辑器")
        XCTAssertEqual(withSubtitle.title, "AX 探针")
        XCTAssertEqual(withSubtitle.subtitle, "副标题")
        XCTAssertEqual(withSubtitle.body, "AX 实时测试")
    }

    /// 关闭控件的**两条路**与「没有关闭控件」：按钮（`AXPress`）优先于自定义动作；
    /// 都没有时 `closeActionName == nil`（调用方据此退化为「仅从岛上隐藏」）。
    func testNotificationBannerCloseControlVariants() {
        // ① 真按钮（带副标题的横幅本机偶尔暴露）：命中后动作用 AXPress
        let button = NotificationBannerParser.parse(
            Self.bannerSnapshot(
                description: "脚本编辑器 标题, 正文",
                texts: ["标题", "正文"],
                buttons: ["显示", "关闭"],
                actions: ["AXPress"]
            )
        )
        XCTAssertEqual(button.closeActionName, kAXPressAction as String)
        XCTAssertEqual(button.closeLabel, "AXButton: 关闭")

        // ② 英文按钮 + 其它关键词（大小写不敏感）
        XCTAssertEqual(
            NotificationBannerParser.parse(Self.bannerSnapshot(buttons: ["CLOSE"])).closeActionName,
            kAXPressAction as String
        )
        XCTAssertEqual(
            NotificationBannerParser.parse(Self.bannerSnapshot(buttons: ["Dismiss"])).closeActionName,
            kAXPressAction as String
        )
        XCTAssertEqual(
            NotificationBannerParser.parse(Self.bannerSnapshot(buttons: ["清除"])).closeActionName,
            kAXPressAction as String
        )
        // ③ 非关闭按钮（「显示」）不算
        XCTAssertNil(NotificationBannerParser.parse(Self.bannerSnapshot(buttons: ["显示"])).closeActionName)
        // ④ 都没有 → nil
        let none = NotificationBannerParser.parse(Self.bannerSnapshot(texts: ["标题"]))
        XCTAssertNil(none.closeActionName)
        XCTAssertNil(none.closeLabel)

        // ⑤ 关键词判据本身
        XCTAssertTrue(NotificationBannerParser.matchesCloseKeyword("Close"))
        XCTAssertTrue(NotificationBannerParser.matchesCloseKeyword("关闭"))
        XCTAssertTrue(NotificationBannerParser.matchesCloseKeyword("dismiss notification"))
        XCTAssertFalse(NotificationBannerParser.matchesCloseKeyword("显示"))
        XCTAssertFalse(NotificationBannerParser.matchesCloseKeyword(""))
    }

    /// **防御式解析**（AX 树随系统版本变）：
    /// 空树 / 没有横幅子角色 / App 名剥不出来 / 超深超宽 —— 一律给空值，**不崩不抛**。
    func testNotificationBannerParseIsDefensive() {
        let empty = NotificationBannerParser.parse(AXNodeSnapshot())
        XCTAssertFalse(empty.foundBannerRoot)
        XCTAssertFalse(empty.hasContent)
        XCTAssertNil(empty.closeActionName)

        // 没有横幅子角色（例如通知中心面板开着）：仍尽力解析，但 foundBannerRoot = false
        let panel = NotificationBannerParser.parse(
            AXNodeSnapshot(
                role: "AXWindow",
                title: "Notification Center",
                children: [AXNodeSnapshot(role: "AXStaticText", value: "某条通知")]
            )
        )
        XCTAssertFalse(panel.foundBannerRoot, "不是横幅窗口不得被认成横幅")
        XCTAssertEqual(panel.title, "某条通知", "兜底解析仍给出尽力而为的结果（探针要它）")
        XCTAssertEqual(panel.appName, "", "描述为空 → 不猜 App 名")

        // App 名剥不出来（描述首段就是标题本身）→ 给空串，**不把标题当 App 名**
        XCTAssertEqual(
            NotificationBannerParser.appName(fromDescription: "标题甲", title: "标题甲", body: "正文"),
            ""
        )
        XCTAssertEqual(NotificationBannerParser.appName(fromDescription: "", title: "标题", body: ""), "")
        // 描述首段以正文结尾（标题为空）也能剥
        XCTAssertEqual(
            NotificationBannerParser.appName(fromDescription: "脚本编辑器 正文乙", title: "", body: "正文乙"),
            "脚本编辑器"
        )

        // 超深树：不爆栈、不卡死（深度上限 8）
        var deep = AXNodeSnapshot(role: "AXStaticText", value: "最深处")
        for _ in 0..<40 { deep = AXNodeSnapshot(role: "AXGroup", children: [deep]) }
        _ = NotificationBannerParser.parse(deep)
        XCTAssertLessThanOrEqual(NotificationBannerParser.render(deep).count, NotificationBannerParser.maxNodes + 1)

        // 超宽树：节点数上限 200，渲染截断并留一行说明
        let wide = AXNodeSnapshot(
            role: "AXGroup",
            children: (0..<500).map { AXNodeSnapshot(role: "AXStaticText", value: "第 \($0) 条") }
        )
        XCTAssertLessThanOrEqual(NotificationBannerParser.render(wide).count, NotificationBannerParser.maxNodes + 1)
        XCTAssertGreaterThanOrEqual(NotificationBannerParser.staticTexts(in: wide).count, 1)
    }

    /// 探针渲染：一行一个元素、关键字段齐全、换行转义（BOM 是单文件追加，靠这些行 grep）。
    func testNotificationBannerProbeRendering() {
        let snapshot = Self.bannerSnapshot(
            description: "脚本编辑器 标题, 正文",
            texts: ["标题", "正文"],
            actions: ["Name:关闭\nTarget:0x0\nSelector:(null)"]
        )
        let lines = NotificationBannerParser.render(snapshot)
        XCTAssertGreaterThan(lines.count, 3)
        let bannerLine = lines.first { $0.contains(NotificationBannerParser.bannerSubrole) }
        XCTAssertNotNil(bannerLine, "探针必须写出横幅容器那一行（校准靠它）")
        XCTAssertTrue(bannerLine?.contains("description=") == true)
        XCTAssertTrue(bannerLine?.contains("actions=") == true)
        XCTAssertFalse(lines.joined().contains("\n\n"), "动作名里的换行必须转义，否则一行一个元素的约定就废了")

        XCTAssertEqual(NotificationBannerParser.escaped("a\"b\nc", limit: 80), "a\\\"b\\nc")
        XCTAssertEqual(NotificationBannerParser.escaped(String(repeating: "x", count: 100), limit: 10).count, 11, "超长截断 + 省略号")
    }

    /// 指纹归一化：去首尾空白、折叠内部空白、小写——AX 的 App 名与 DB 的 App 名来源不同，
    /// 不归一化就会「同一条通知弹两次」。
    func testNotificationFingerprintNormalization() {
        let axSide = NotificationFingerprint(appName: "脚本编辑器", title: "构建 完成", body: "全部通过")
        let dbSide = NotificationFingerprint(appName: " 脚本编辑器 ", title: "构建\t完成", body: "全部通过\n")
        XCTAssertEqual(axSide, dbSide, "空白/大小写差异不得影响去重")
        XCTAssertNotEqual(axSide, NotificationFingerprint(appName: "脚本编辑器", title: "构建 完成", body: "别的正文"))
        XCTAssertNotEqual(axSide, NotificationFingerprint(appName: "别的 App", title: "构建 完成", body: "全部通过"))
        XCTAssertEqual(NotificationFingerprint.normalized("  A  b\nC "), "a b c")
        XCTAssertEqual(NotificationFingerprint.normalized(""), "")
    }

    /// 去重台账（**AX 优先** + 10s 窗口 + 句柄台账）：
    /// - 同指纹 10s 内只弹一次：AX 先到 → DB 那条（约 5s 后）不再弹浮层；
    /// - AX 没到（未授权 / 树变了）时 DB 照常弹——两条通道都不会被对方饿死；
    /// - 窗口过期后同指纹可再弹；
    /// - 窗口期内保留 AX 的真关闭句柄，过期即丢；DB 来源不留句柄。
    func testNotificationBannerLedgerDedupWindowAndAXPriority() {
        XCTAssertEqual(NotificationBannerLedger.window, 10, "去重窗口是 10s（覆盖 DB 约 5s 的落盘延迟）")

        let key = NotificationFingerprint(appName: "邮件", title: "新邮件", body: "来自张三")
        let other = NotificationFingerprint(appName: "邮件", title: "新邮件", body: "来自李四")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var ledger = NotificationBannerLedger()

        // AX 先到：弹
        XCTAssertTrue(ledger.shouldPresent(key, source: .ax, now: start))
        // 同指纹再来（AX 重放 / DB 那条晚到 5s）：窗口内不弹（**AX 优先**）
        XCTAssertFalse(ledger.shouldPresent(key, source: .ax, now: start.addingTimeInterval(0.4)))
        XCTAssertFalse(ledger.shouldPresent(key, source: .database, now: start.addingTimeInterval(5.1)))
        // 不同指纹不受影响（未读数与列表照旧，只是浮层不重复）
        XCTAssertTrue(ledger.shouldPresent(other, source: .database, now: start.addingTimeInterval(5.2)))
        // 窗口外（≥ 10s）同指纹可再弹
        XCTAssertFalse(ledger.shouldPresent(key, source: .database, now: start.addingTimeInterval(9.9)))
        XCTAssertTrue(ledger.shouldPresent(key, source: .database, now: start.addingTimeInterval(10.1)))
        // 台账不随运行时长增长：过期登记会被清掉（20.2s 时前两条登记都已过期，只剩刚登记的这条）
        XCTAssertEqual(ledger.count, 2, "10.1s：key 刚登记，other（5.2s 登记）仍在 10s 窗口内")
        XCTAssertTrue(ledger.shouldPresent(key, source: .ax, now: start.addingTimeInterval(20.2)))
        XCTAssertEqual(ledger.count, 1, "两条旧登记都已过期并被清掉，台账只保存最近 10s 内的")

        // 反向：DB 先到（AX 没拿到）→ AX 后到来时窗口内不弹，但通道本身没死
        var databaseFirst = NotificationBannerLedger()
        XCTAssertTrue(databaseFirst.shouldPresent(key, source: .database, now: start))
        XCTAssertFalse(databaseFirst.shouldPresent(key, source: .ax, now: start.addingTimeInterval(1)))
        XCTAssertTrue(databaseFirst.shouldPresent(key, source: .ax, now: start.addingTimeInterval(11)))
    }

    /// 真关闭句柄的台账口径：**只有 AX 来源**在窗口期内能取到句柄，过期即 nil，DB 来源恒 nil。
    func testNotificationBannerLedgerCloseHandleWindow() {
        let key = NotificationFingerprint(appName: "邮件", title: "新邮件", body: "来自张三")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var ledger = NotificationBannerLedger()

        // DB 来源：窗口期内也取不到句柄（它没有 AX 横幅）
        XCTAssertTrue(ledger.shouldPresent(key, source: .database, now: start))
        XCTAssertNil(ledger.closeHandle(for: key, now: start.addingTimeInterval(1)))

        // 同指纹的 AX 横幅在窗口外到来 → 登记成功；窗口内可取句柄
        let later = start.addingTimeInterval(11)
        let handle = Self.closeHandleFixture()
        XCTAssertTrue(ledger.shouldPresent(key, source: .ax, closeHandle: handle, now: later))
        XCTAssertEqual(ledger.closeHandle(for: key, now: later.addingTimeInterval(9.9))?.label, handle.label)
        XCTAssertNil(ledger.closeHandle(for: key, now: later.addingTimeInterval(10.1)), "过期即丢")
        XCTAssertNil(ledger.closeHandle(for: NotificationFingerprint(appName: "别的", title: "", body: ""), now: later))
    }

    /// 模块接缝：DB 侧指纹取自 `NotificationItem`（`displayName + title + body`），
    /// 与 AX 侧的 `BannerEvent.fingerprint` 同一口径 —— 这条钉住「两条通道能对上」。
    func testNotificationFingerprintFromItemMatchesBannerEvent() {
        let item = NotificationItem(
            id: 77,
            bundleIdentifier: "com.apple.Mail",
            appName: "邮件",
            title: "新邮件",
            subtitle: nil,
            body: "来自张三",
            deliveredDate: nil
        )
        let event = BannerEvent(
            appName: "邮件",
            title: "新邮件",
            subtitle: "",
            body: "来自张三",
            closeHandle: Self.closeHandleFixture(),
            receivedAt: Date()
        )
        XCTAssertEqual(NotificationStore.fingerprint(for: item), event.fingerprint, "两条通道的指纹必须一致，否则去重失效")

        // 没有显示名时退回 bundle id（`displayName` 的兜底链）
        let unnamed = NotificationItem(
            id: 78,
            bundleIdentifier: "com.apple.Mail",
            appName: "",
            title: "新邮件",
            subtitle: nil,
            body: "来自张三",
            deliveredDate: nil
        )
        XCTAssertEqual(NotificationStore.fingerprint(for: unnamed).appName, "com.apple.mail")
    }

    /// AX 通道新增文案：× 的「真关闭」提示必须能解析出译文（06 §3.3 R5 的 key 形态）。
    func testNotificationCloseSystemKeyResolves() {
        let localized = Bundle.main.localizedString(
            forKey: "module.notifications.closeSystemNotification",
            value: nil,
            table: nil
        )
        XCTAssertNotEqual(localized, "module.notifications.closeSystemNotification", "key 没解析出文案")
        XCTAssertFalse(localized.isEmpty)
    }

    /// 关闭句柄夹具：**只构造、不执行**（单测不该起 AX IPC、也不该动任何真实界面）。
    /// `AXUIElementCreateApplication(getpid())` 只建一个指向本进程的 CF 对象——不申请权限、
    /// 不读写任何元素；台账只搬运这个句柄，从不碰它的内容。
    private static func closeHandleFixture(label: String = "自定义动作: 关闭") -> NotificationBannerCloseHandle {
        NotificationBannerCloseHandle(
            element: AXUIElementCreateApplication(getpid()),
            actionName: "关闭",
            label: label
        )
    }

    /// 构造一棵**横幅树**夹具（形状逐字对齐真探针原文；`buttons` 可选，macOS 27 通常没有）。
    private static func bannerSnapshot(
        description: String = "",
        texts: [String] = [],
        buttons: [String] = [],
        actions: [String] = []
    ) -> AXNodeSnapshot {
        var bannerChildren = texts.map { AXNodeSnapshot(role: "AXStaticText", value: $0) }
        bannerChildren += buttons.map { AXNodeSnapshot(role: "AXButton", description: $0) }
        let banner = AXNodeSnapshot(
            role: "AXGroup",
            subrole: NotificationBannerParser.bannerSubrole,
            description: description,
            actionNames: actions,
            children: bannerChildren
        )
        return AXNodeSnapshot(
            role: "AXWindow",
            subrole: "AXSystemDialog",
            title: "Notification Center",
            children: [
                AXNodeSnapshot(
                    role: "AXGroup",
                    subrole: "AXHostingView",
                    children: [
                        AXNodeSnapshot(
                            role: "AXGroup",
                            children: [
                                AXNodeSnapshot(role: "AXScrollArea", children: [banner])
                            ]
                        )
                    ]
                )
            ]
        )
    }

    /// 构造一条通知夹具（只关心 id 的用例用它）。
    private func notificationItem(_ id: Int64, title: String = "", body: String = "") -> NotificationItem {
        NotificationItem(
            id: id,
            bundleIdentifier: "com.apple.Mail",
            appName: "邮件",
            title: title,
            subtitle: nil,
            body: body,
            deliveredDate: nil
        )
    }

    /// `modificationDate` 必须把 **WAL 旁文件**算进来（2026-09-28 实测：库是 WAL 模式，
    /// 新通知只改 `db-wal`，主库 mtime 纹丝不动）。只认主库会让 30s 轮询永远早退——
    /// 增量与浮层都不再触发。夹具用临时文件，**不碰系统通知库**。
    func testNotificationReaderModificationDateTracksWALSibling() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gourd-wal-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let database = directory.appendingPathComponent("db")
        try Data([0x00]).write(to: database)
        let mainDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: mainDate], ofItemAtPath: database.path)

        let reader = NotificationCenterReader(databasePath: database.path)
        XCTAssertEqual(reader.modificationDate, mainDate, "没有 -wal 时退化成只看主库")

        // WAL 比主库新 → 闸门看到的是 WAL 的时间（新通知写在这里）
        let wal = directory.appendingPathComponent("db-wal")
        let walDate = mainDate.addingTimeInterval(600)
        try Data([0x00]).write(to: wal)
        try FileManager.default.setAttributes([.modificationDate: walDate], ofItemAtPath: wal.path)
        XCTAssertEqual(reader.modificationDate, walDate, "WAL 较新时必须取 WAL 的时间")

        // WAL 较旧（例如 checkpoint 后主库被改写）→ 取主库
        try FileManager.default.setAttributes(
            [.modificationDate: mainDate.addingTimeInterval(1200)],
            ofItemAtPath: database.path
        )
        XCTAssertEqual(reader.modificationDate, mainDate.addingTimeInterval(1200), "主库较新时取主库")

        // 库文件不存在 → nil（`pollOnce` 据此报「库文件不可访问」而不是静默早退）
        let missing = NotificationCenterReader(
            databasePath: directory.appendingPathComponent("nope").path
        )
        XCTAssertNil(missing.modificationDate)
    }

    /// 构造二进制 plist 夹具（通知库的 `record.data` 就是二进制 plist）——**不读系统通知库**。
    private static func binaryPlist(_ object: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
    }
}

// MARK: - 假体

/// 最小假体：不读也不写，只满足 `ConfigHandle` 的签名（真实现属 T2 的 `ModuleContextFactory`）。
private final class StubConfigHandle: ConfigHandle {
    func get<T: Codable & Sendable>(_ key: String, as: T.Type) -> T? { nil }
    func set<T: Codable & Sendable>(_ key: String, to value: T) -> Bool { false }
}

@MainActor
private final class StubUIHandle: UIHandle {
    var redrawCount = 0
    /// 收到的瞬时浮层请求（`ttl` 逐条记下，断言夹取/覆盖语义时不必等真实到期）。
    var presentedTTLs: [TimeInterval] = []
    /// 收到的主动撤浮层请求次数（只记次数：假体不持有注册表，转发语义由别处钉）。
    var dismissCount = 0
    func requestRedraw() { redrawCount += 1 }
    var isLowPower: Bool { false }
    func presentTransient(view: AnyView, ttl: TimeInterval) { presentedTTLs.append(ttl) }
    func dismissTransient() { dismissCount += 1 }
}

@MainActor
private final class StubModule: GourdModule {
    static var manifest: ModuleManifest {
        ModuleManifest(
            manifestVersion: 1,
            id: "com.cmeng.gourd.stub",
            name: LocalizedText(key: "module.stub.name"),
            summary: nil,
            icon: IconSpec(type: "symbol", name: "square"),
            version: "1.0.0",
            apiVersion: HostInfo.currentAPIVersion,
            kind: "builtin",
            surfaces: [.expanded],
            defaultPlacement: nil,
            defaultEnabled: true,
            permissions: [],
            config: nil
        )
    }

    let context: ModuleContext

    init(context: ModuleContext) {
        self.context = context
    }

    func activate() async throws {}
    func deactivate() async {}

    func content(for request: ContentRequest) -> ModuleContent {
        .unavailable(reason: "stub 未实现内容")
    }
}

// MARK: - T2 假模块（注册表夹具）

/// 假模块的 manifest 工厂：**字面量构造**，不走 `ModuleManifest.decode(from:)`
/// （T1 的口径：`kind == builtin` 时顶层出现 `entry` 会被判 `unexpectedEntry`，夹具因此不碰该键）。
private enum RegistryFixture {
    static func manifest(
        shortID: String,
        surfaces: [Surface] = [.expanded],
        order: Int? = nil,
        name: LocalizedText? = nil,
        defaultEnabled: Bool = true
    ) -> ModuleManifest {
        ModuleManifest(
            manifestVersion: 1,
            id: "com.cmeng.gourd.\(shortID)",
            name: name ?? LocalizedText(key: "module.\(shortID).name"),
            summary: nil,
            icon: IconSpec(type: "symbol", name: "square"),
            version: "1.0.0",
            apiVersion: HostInfo.currentAPIVersion,
            kind: "builtin",
            surfaces: surfaces,
            defaultPlacement: order.map { Placement(slot: .center, order: $0) },
            defaultEnabled: defaultEnabled,
            permissions: [],
            config: nil
        )
    }
}

/// 记录 `requestRedraw` 的转发次数（T2 的 `UIHandle` 实现体是文件私有的，只能从注入闭包侧观测）。
private final class RedrawProbe {
    var count = 0
}

/// 假模块基线：`activate()` 不抛错、`content(for:)` 返回 `.none`。
/// manifest 由子类覆写 `class var` 提供（`GourdModule` 的 `static var manifest` 可由 `class var` 满足），
/// 六个夹具因此共享同一份 `init(context:)` / `deactivate()`。
@MainActor
private class ProbeModule: GourdModule {
    class var manifest: ModuleManifest { RegistryFixture.manifest(shortID: "probe") }

    required init(context: ModuleContext) {}

    func activate() async throws {}

    func deactivate() async {}

    /// 与注册表对未激活模块返回的 `.unavailable` 区分开：激活的模块转发到这里。
    func content(for request: ContentRequest) -> ModuleContent { .none }
}

/// order 10 + 声明 `.expanded`
private final class AlphaProbeModule: ProbeModule {
    override class var manifest: ModuleManifest { RegistryFixture.manifest(shortID: "probe-alpha", order: 10) }
}

/// 与 `AlphaProbeModule` **同 id**：验证重复注册被忽略（而不是覆盖）
private final class AlphaImpostorModule: ProbeModule {
    override class var manifest: ModuleManifest { RegistryFixture.manifest(shortID: "probe-alpha", order: 10) }
}

/// `activate()` 必抛错
private final class BetaProbeModule: ProbeModule {
    struct ActivationFailure: Error {}

    override class var manifest: ModuleManifest { RegistryFixture.manifest(shortID: "probe-beta", order: 5) }

    override func activate() async throws { throw ActivationFailure() }
}

/// order 10（与 alpha 同序 → 比 id 字典序）+ name 用 locale 表形态
private final class GammaProbeModule: ProbeModule {
    override class var manifest: ModuleManifest {
        RegistryFixture.manifest(shortID: "probe-gamma", order: 10, name: LocalizedText(table: ["en": "Gamma Probe"]))
    }
}

/// 无 `defaultPlacement`（order = `Int.max`）
private final class DeltaProbeModule: ProbeModule {
    override class var manifest: ModuleManifest { RegistryFixture.manifest(shortID: "probe-delta") }
}

/// 只声明 `.compact`：即使激活也不进展开面板
private final class CompactProbeModule: ProbeModule {
    override class var manifest: ModuleManifest {
        RegistryFixture.manifest(shortID: "probe-compact", surfaces: [.compact], order: 1)
    }
}

/// `defaultEnabled = false`
private final class OptInProbeModule: ProbeModule {
    override class var manifest: ModuleManifest {
        RegistryFixture.manifest(shortID: "probe-optin", order: 2, defaultEnabled: false)
    }
}

/// `compact` + `expanded`、order 1（与 `CompactProbeModule` 同序 → 比 id 字典序）；
/// `compact` 请求答一个**可辨认**的 `.unavailable`（默认假体答 `.none`，与注册表「无候选」同形，
/// 无法证明 `compactSlotContent()` 转发到了谁），其余 surface 仍答 `.none`。
private final class DualSurfaceProbeModule: ProbeModule {
    override class var manifest: ModuleManifest {
        RegistryFixture.manifest(shortID: "probe-dual", surfaces: [.compact, .expanded], order: 1)
    }

    override func content(for request: ContentRequest) -> ModuleContent {
        request.surface == .compact ? .unavailable(reason: "probe-dual 的 compact 内容") : .none
    }
}

/// 只声明 `compact`、order 40：验证折叠态候选按 `order` 升序（排在两个 order 1 的后面）
private final class CompactLateProbeModule: ProbeModule {
    override class var manifest: ModuleManifest {
        RegistryFixture.manifest(shortID: "probe-compact-late", surfaces: [.compact], order: 40)
    }
}

// MARK: - 笔记同步：「最近删除」过滤

/// `AppleNotesTrashFilter` 是纯函数，直接对表测。
/// 背景：`notes of default account` 会把「最近删除」里的笔记一起枚举出来，被删条目因此
/// 永远留在 merge 的 `linkedRemoteIds` 里，本地对应项清不掉（岛上残留 / 同名重复）。
/// 这里只覆盖判定的三条性质：表内命中、表外不命中（含空串）、大小写与首尾空白无关。
final class AppleNotesTrashFilterTests: XCTestCase {

    /// 表中各语言的「最近删除」名称逐字命中。三例都要留着：本机实测（系统语言 zh-Hans-CN）
    /// AppleScript 侧返回的其实是英文 `Recently Deleted`，只按 UI 语言准备一条会在真机漏判。
    func testKnownTrashedFolderNamesAreDetected() {
        XCTAssertTrue(AppleNotesTrashFilter.isTrashed(containerName: "最近删除"), "zh-Hans")
        XCTAssertTrue(AppleNotesTrashFilter.isTrashed(containerName: "最近刪除"), "zh-Hant")
        XCTAssertTrue(AppleNotesTrashFilter.isTrashed(containerName: "Recently Deleted"), "en")
    }

    /// 普通文件夹名与空串不算垃圾：**空串（旧格式记录 / 取不到容器名）必须保持旧行为**，
    /// 否则升级后会把所有笔记误判为已删除。
    func testOrdinaryFolderNamesAreNotTrashed() {
        XCTAssertFalse(AppleNotesTrashFilter.isTrashed(containerName: "备忘录"), "用户自己的文件夹")
        XCTAssertFalse(AppleNotesTrashFilter.isTrashed(containerName: "Notes"), "en 普通文件夹")
        XCTAssertFalse(AppleNotesTrashFilter.isTrashed(containerName: ""), "空容器名 = 不过滤")
    }

    /// 大小写与首尾空白（含换行）不影响判定。
    func testMatchIsCaseAndWhitespaceInsensitive() {
        XCTAssertTrue(AppleNotesTrashFilter.isTrashed(containerName: "  recently DELETED  "))
        XCTAssertTrue(AppleNotesTrashFilter.isTrashed(containerName: "\n最近删除\t"))
        XCTAssertFalse(AppleNotesTrashFilter.isTrashed(containerName: "   "))
        XCTAssertFalse(AppleNotesTrashFilter.isTrashed(containerName: " recently deleted extra"))
    }
}
