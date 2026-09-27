//
//  ModuleKernelTests.swift
//  Gourd 模块内核 · 类型层单测（P1 批次 / T1）
//
//  覆盖 docs/13-runtime-kernel.md §接口与数据形状 的本批类型层：
//  manifest 校验（每个 ModuleManifestError 分支至少一例）、取值词汇表、
//  权限白名单常量表、config 子集解析、协议可一致性。
//  构造一律走 `ModuleManifest.decode(from:)`（JSON 路径），与宿主读 descriptor 同一条路。
//

import XCTest

@testable import Gourd

@MainActor
final class ModuleKernelTests: XCTestCase {

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
}

// MARK: - 假体

/// 最小假体：不读也不写，只满足 `ConfigHandle` 的签名（真实现属 T2 的 `ModuleContextFactory`）。
private final class StubConfigHandle: ConfigHandle {
    func get<T: Codable & Sendable>(_ key: String, as: T.Type) -> T? { nil }
    func set<T: Codable & Sendable>(_ key: String, to value: T) -> Bool { false }
}

private final class StubUIHandle: UIHandle {
    var redrawCount = 0
    func requestRedraw() { redrawCount += 1 }
    var isLowPower: Bool { false }
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
