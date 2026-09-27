//
//  ModuleKernelTests.swift
//  Gourd 模块内核 · 类型层单测（P1 批次 / T1）
//
//  覆盖 docs/13-runtime-kernel.md §接口与数据形状：
//  T1 类型层——manifest 校验（每个 ModuleManifestError 分支至少一例）、取值词汇表、
//  权限白名单常量表、config 子集解析、协议可一致性；构造一律走 `ModuleManifest.decode(from:)`
//  （JSON 路径），与宿主读 descriptor 同一条路。
//  T2 注册表与组合根——注册幂等、activate 抛错隔离、启用门、tab 投影、content 降级、
//  `ModuleContextFactory` 的默认值读取、首启默认值幂等。
//  T3 接缝——S2 的 tab 计数（刘海最小宽度的输入）把注册表条目计入总数；S4 的
//  `selectModule(_:)` 同时设 `selectedModuleID` 与 `currentView`。
//

import Defaults
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
