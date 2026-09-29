//
//  TakeoverEnablementTests.swift
//  Gourd 模块内核 · 接管三件套与重同步桥（P2 接管批次 / T1）
//
//  覆盖 docs/20-component-page.md §接口与数据形状 1/2/3 与 §做法 机制一/机制二：
//
//  - **启用真源 read-through**：接管键（`GourdModule.takeoverEnableKey`）压过
//    `moduleEnableOverrides` 与 `manifest.defaultEnabled`——两个方向都压（键 false + overrides true
//    → `.disabled`；键 true + overrides false → `.active`），缺 overrides 时也压 manifest 默认；
//  - **重同步桥**：模块 `.active` 后上游键被改 false → 让出主 actor 若干回合后 `states` 跟着变
//    （订阅回调走 `Task { @MainActor }`，不是同帧）；
//  - **`failed` 不被桥救活**：`activate()` 抛错的模块在键被置 true 后仍是 `.failed`、
//    `activate()` 不被第二次调用（D-13 / 06 §3.3 硬性规则 1）；
//  - **`isTabVisible()` 契约**：缺省 true 进 `tabEntries`；重写成 false 的假模块**不进**，
//    而它的 `states` 仍是 `.active`（可见性与启用是两件事）；
//  - **写路径**（`ModuleEnablementWrite`）：接管键非 nil → 只写上游键、连 overrides 键都不写出来；
//    nil → 只写 overrides、上游键一个字节不动；
//  - **桥幂等**：连调两次 `startTakeoverBridge` → 订阅条数等于接管模块数（不是两倍），
//    非接管模块不建订阅；
//  - **块宽钩子**：声明 140/160 的模块取值一致、未声明为 nil、未注册 id 为 nil；
//  - **回弹策略**（`ModuleEnablementRollback`，D-13）：接管模块 nil（什么都不写）、非接管模块 false。
//
//  三条刻意写死的口径（改动前先读）：
//
//  1. **注册一律走真门 `KernelBootstrap.enablementGate(registry:)`**：用旧门
//     （`manifests[$0]?.defaultEnabled`）的话接管键根本不被读，read-through 用例永不可能过；
//  2. **不调 `KernelBootstrap.bootstrap()`**：那个入口会落首启默认值（写开发机真实的
//     `enableScreenAssistant`，见派发片段与 `KernelBootstrap.applyFirstLaunchDefaults`）。
//     用例只调注册表自己的 `bootstrap()`，桥直接调 `KernelBootstrap.startTakeoverBridge`；
//  3. **偏好卫生**：每个写真实键的用例进入时记下该键的**持久域原值**、`defer` 逐字还原
//     （原本有键写回原值、原本没键删键）——跑完 `defaults read com.cmeng.gourd <键>` 与跑之前相同。
//     不写 `Defaults.withoutPropagation`：桥要看的正是「键变了」，屏蔽掉就把被测行为一起屏蔽了。
//

import Defaults
import XCTest

@testable import Gourd

@MainActor
final class TakeoverEnablementTests: XCTestCase {

    /// 夹具 id（与 `TakeoverFixture.manifest(shortID:)` 同址派生）。
    private let id = "com.cmeng.gourd.probe-takeover"
    private let hiddenTabID = "com.cmeng.gourd.probe-takeover-hidden-tab"
    private let wideBlockID = "com.cmeng.gourd.probe-takeover-wide"
    private let failingID = "com.cmeng.gourd.probe-takeover-failing"
    private let baseID = "com.cmeng.gourd.probe-takeover-base"
    private let ghostID = "com.cmeng.gourd.probe-takeover-ghost"

    // MARK: - 隔离

    override func setUp() async throws {
        try await super.setUp()
        await ModuleRegistry.shared.deactivateAll()
        // `deactivateAll()` 连 `manifests` / `moduleTypes` 一起清（接管查询因此也一并清空），
        // 用例必须自己重新 `register(...)`（同 `ModuleToggleTests` 的坑）。订阅表在这里清干净：
        // 注册表空时起桥 = 只 `removeAll()`，上一个用例的桥不会把状态写进下一个用例。
        KernelBootstrap.startTakeoverBridge(registry: ModuleRegistry.shared)
        TakeoverLedger.reset()
    }

    override func tearDown() async throws {
        await ModuleRegistry.shared.deactivateAll()
        KernelBootstrap.startTakeoverBridge(registry: ModuleRegistry.shared)
        TakeoverLedger.reset()
        try await super.tearDown()
    }

    // MARK: - 启用真源（read-through）

    /// 接管键压过 overrides 与 manifest 默认——两个方向都压（「真源唯一」的判据）。
    func testTakeoverKeyBeatsOverridesAndManifestDefault() async {
        let preferences = snapshotPreferences()
        defer { restore(preferences) }

        let registry = ModuleRegistry.shared
        // 夹具的 manifest 默认**故意**是 `true`（与上游键的语义相反），overrides 也显式写着 true：
        // 门若还是旧口径（overrides → manifest），这里就会放行。
        Defaults[.enableTimerFeature] = false
        Defaults[.moduleEnableOverrides] = [id: true]

        registry.register(
            [TakeoverProbeModule.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )
        await registry.bootstrap()

        XCTAssertEqual(registry.states[id], .disabled, "接管键 false 压过 overrides true 与 manifest 默认 true")
        XCTAssertNil(registry.instance(for: id), "未启用的模块不实例化")
        XCTAssertTrue(registry.tabEntries.isEmpty, "未启用 → 不进 tab 投影")

        // 去掉 overrides（缺键 = 用户未表达）再走一遍：接管键 false 同样压过 manifest 默认 true。
        await registry.deactivateAll()
        Defaults.reset(Defaults.Keys.moduleEnableOverrides.name)
        registry.register(
            [TakeoverProbeModule.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )
        await registry.bootstrap()

        XCTAssertEqual(registry.states[id], .disabled, "缺 overrides 时接管键 false 仍压过 manifest 默认 true")
        XCTAssertNil(registry.instance(for: id))
    }

    /// 接管键是**唯一**真源：键 true 时，overrides 里的 false 与 manifest 默认都压不过它。
    func testTakeoverKeyIsTheOnlyTruthForEnablement() async {
        let preferences = snapshotPreferences()
        defer { restore(preferences) }

        let registry = ModuleRegistry.shared
        Defaults[.enableTimerFeature] = true
        Defaults[.moduleEnableOverrides] = [id: false]

        registry.register(
            [TakeoverProbeModule.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )
        await registry.bootstrap()

        XCTAssertEqual(registry.states[id], .active, "接管键 true 压过 overrides false")
        XCTAssertNotNil(registry.instance(for: id), "过门的模块照常激活")
        XCTAssertEqual(registry.tabEntries.map(\.id), [id], "激活后进 tab 投影")
    }

    // MARK: - 重同步桥

    /// 上游键被别处（上游设置页）改动 → 注册表状态跟上（docs/20 §做法 机制二）。
    func testBridgeResyncsStateWhenUpstreamKeyChanges() async {
        let preferences = snapshotPreferences()
        defer { restore(preferences) }

        let registry = ModuleRegistry.shared
        Defaults[.enableTimerFeature] = true
        registry.register(
            [TakeoverProbeModule.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )
        await registry.bootstrap()
        XCTAssertEqual(registry.states[id], .active, "前置：接管键 true → 活跃")

        KernelBootstrap.startTakeoverBridge(registry: registry)
        XCTAssertEqual(KernelBootstrap.takeoverSubscriptionCount, 1, "前置：桥为该模块建了一条订阅")

        Defaults[.enableTimerFeature] = false   // 上游设置页的那一次写

        let resynced = await waitUntil { registry.states[id] == .disabled }
        XCTAssertTrue(resynced, "上游键改 false 后注册表状态应跟上（桥的回调不是同帧）")
        XCTAssertNil(registry.instance(for: id), "重同步置关必须摘掉实例")
        XCTAssertTrue(registry.tabEntries.isEmpty, "tab 投影随之消失")
    }

    /// `failed` 是终态：桥把键置 true 也不把它救活（D-13 / 06 §3.3 硬性规则 1）。
    func testBridgeDoesNotReviveFailedModule() async {
        let preferences = snapshotPreferences()
        defer { restore(preferences) }

        let registry = ModuleRegistry.shared
        Defaults[.enableTimerFeature] = false
        registry.register(
            [TakeoverFailingProbeModule.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )
        await registry.bootstrap()
        XCTAssertEqual(registry.states[failingID], .disabled, "前置：键 false → 不激活")

        // 直接把开关打开：`setEnabled` 不读门（门只在注册那一刻判过），因此这里能造出 `.failed`。
        let failed = await registry.setEnabled(true, for: failingID)
        guard case .failed = failed else {
            return XCTFail("前置失败：期望 .failed，实到 \(failed)")
        }
        XCTAssertEqual(activations(failingID), 1, "前置：activate() 抛错一次")

        KernelBootstrap.startTakeoverBridge(registry: registry)
        Defaults[.enableTimerFeature] = true   // 桥上的一次置开

        // 「本不该发生」的断言：把在飞的回合跑完再看结果。
        await yieldTurns()

        guard case .failed? = registry.states[failingID] else {
            return XCTFail("failed 不得被桥救活，实到 \(String(describing: registry.states[failingID]))")
        }
        XCTAssertEqual(activations(failingID), 1, "终态不重试：activate() 全程只被调用一次")
        XCTAssertNil(registry.instance(for: failingID))
    }

    // MARK: - isTabVisible 契约

    /// 缺省 true 进 tab 列表；重写成 false 的模块**不进**，而它仍是 `.active`（可见性 ≠ 启用）。
    func testTabVisibilityHookFiltersTabEntries() async {
        let preferences = snapshotPreferences()
        defer { restore(preferences) }

        let registry = ModuleRegistry.shared
        Defaults[.enableTimerFeature] = true
        registry.register(
            [TakeoverProbeModule.self, TakeoverHiddenTabProbeModule.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )
        await registry.bootstrap()

        XCTAssertEqual(registry.states[id], .active)
        XCTAssertEqual(registry.states[hiddenTabID], .active, "可见性与启用是两件事：模块照常激活")
        XCTAssertEqual(registry.tabEntries.map(\.id), [id], "缺省 true 进投影，重写 false 的不进")
        XCTAssertNotNil(registry.instance(for: hiddenTabID), "不进 tab 不影响实例入驻")
        XCTAssertTrue(registry.homeEntries.isEmpty, "两者都只声明 expanded，home 投影不受影响")
    }

    // MARK: - 写路径与回弹

    /// 写路径：接管模块写上游键、非接管写 overrides——各写各的，互不越界（docs/20 §接口与数据形状 3）。
    func testWriteGoesToTakeoverKeyOrOverrides() {
        let preferences = snapshotPreferences()
        defer { restore(preferences) }

        Defaults[.enableTimerFeature] = false
        Defaults.reset(Defaults.Keys.moduleEnableOverrides.name)   // 干净起点：连 overrides 键都不存在

        ModuleEnablementWrite.write(true, for: id, takeoverKey: .enableTimerFeature)

        XCTAssertTrue(Defaults[.enableTimerFeature], "接管模块：开关就是上游那个键")
        XCTAssertNil(Defaults[.moduleEnableOverrides][id], "接管模块不得同时写 overrides")
        XCTAssertNil(
            persistedValue(of: Defaults.Keys.moduleEnableOverrides.name),
            "接管模块的写路径连 overrides 键都不该写出来"
        )

        // 非接管：只写 overrides，上游键一个字节都不动
        Defaults[.enableTimerFeature] = false
        ModuleEnablementWrite.write(true, for: id, takeoverKey: nil)

        XCTAssertFalse(Defaults[.enableTimerFeature], "非接管模块的写路径不得碰上游键")
        XCTAssertEqual(Defaults[.moduleEnableOverrides][id], true, "非接管模块写的是 overrides")
    }

    /// 回弹策略（D-13）：接管模块什么都不写、非接管写回 false。
    func testRollbackWritesNothingForTakeoverModules() {
        XCTAssertNil(
            ModuleEnablementRollback.preferenceToWrite(takeoverKey: .enableTimerFeature),
            "接管模块的偏好就是上游总开关：回弹等于因为激活失败把用户的功能关了"
        )
        XCTAssertEqual(
            ModuleEnablementRollback.preferenceToWrite(takeoverKey: nil),
            false,
            "非接管模块：把用户的开关拨回去"
        )
    }

    // MARK: - 桥幂等

    /// 连调两次 `startTakeoverBridge` 不翻倍；且只订阅接管模块（非接管模块不建订阅）。
    ///
    /// 本用例**不写**任何真实偏好：门只读（`Defaults[takeoverKey]`），判定结果与断言无关。
    func testBridgeIsIdempotentAndSubscribesOnlyTakeoverModules() {
        let registry = ModuleRegistry.shared
        registry.register(
            [TakeoverProbeModule.self, TakeoverHiddenTabProbeModule.self, TakeoverProbeBase.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )
        XCTAssertEqual(registry.manifests.count, 3, "前置：三个夹具都已注册")
        XCTAssertNil(registry.takeoverEnableKey(for: baseID), "前置：基类是**非接管**模块（缺省 nil）")

        KernelBootstrap.startTakeoverBridge(registry: registry)
        XCTAssertEqual(KernelBootstrap.takeoverSubscriptionCount, 2, "只订阅两个接管模块")

        KernelBootstrap.startTakeoverBridge(registry: registry)
        XCTAssertEqual(KernelBootstrap.takeoverSubscriptionCount, 2, "重复起桥不得翻倍（进入先 removeAll）")
    }

    // MARK: - 块宽钩子

    /// 块宽钩子：声明的模块取值一致、未声明为 nil、未注册 id 为 nil（docs/20 §做法 机制一）。
    ///
    /// 本用例**不写**任何真实偏好（门只读）。
    func testHomeBlockWidthHookReadsDeclaredValueOrNil() {
        let registry = ModuleRegistry.shared
        registry.register(
            [TakeoverWideBlockProbeModule.self, TakeoverProbeModule.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )

        XCTAssertEqual(
            registry.homeBlockWidth(for: wideBlockID),
            ModuleHomeBlockWidth(min: 140, ideal: 160),
            "声明的宽度原样取给宿主（镜子那一档）"
        )
        XCTAssertNil(registry.homeBlockWidth(for: id), "未声明 → nil（宿主用统一值 180/240）")
        XCTAssertNil(registry.homeBlockWidth(for: ghostID), "未注册的 id → nil")
        XCTAssertNil(registry.takeoverEnableKey(for: ghostID), "未注册的 id 同样没有接管键")
        XCTAssertEqual(
            registry.takeoverEnableKey(for: id)?.name,
            Defaults.Keys.enableTimerFeature.name,
            "接管键按模块取，取到的是形参给的那一个键"
        )
    }

    // MARK: - 工具

    /// 让出主 actor 若干回合，直到条件成立（桥的回调是 `Task { @MainActor }`，不是同帧）。
    /// 上限 1000 回合：等不到就返回 false，由断言报出「等不到」而不是死在死循环里。
    @discardableResult
    private func waitUntil(_ condition: () -> Bool, limit: Int = 1_000) async -> Bool {
        for _ in 0..<limit {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }

    /// 让出主 actor 若干回合（用于「本不该发生」的断言：把在飞的回合跑完再看结果）。
    private func yieldTurns(_ times: Int = 100) async {
        for _ in 0..<times { await Task.yield() }
    }

    /// 账本读取：**没记过 = 0**（`TakeoverLedger` 只在第一次调用时落键，直接下标会拿到 nil）。
    private func activations(_ id: String) -> Int { TakeoverLedger.activations[id] ?? 0 }

    /// 记下两个真实键在**持久域**里的原值（nil = 原本没有这个键）。
    private func snapshotPreferences() -> PreferenceSnapshot {
        PreferenceSnapshot(
            enableTimerFeature: persistedValue(of: Defaults.Keys.enableTimerFeature.name),
            moduleEnableOverrides: persistedValue(of: Defaults.Keys.moduleEnableOverrides.name)
        )
    }

    /// 逐字还原（见文件头「偏好卫生」）：原本有键写回原值、原本没键删键。
    private func restore(_ snapshot: PreferenceSnapshot) {
        restore(snapshot.enableTimerFeature, to: Defaults.Keys.enableTimerFeature.name)
        restore(snapshot.moduleEnableOverrides, to: Defaults.Keys.moduleEnableOverrides.name)
    }

    /// 持久域里那个键的原值（`nil` = 用户从未写过 / 已被 `reset`）。
    ///
    /// 为什么不用 `Defaults[...]`：`Defaults.Key` 的初始化会顺手把默认值注册进**注册域**，
    /// 于是 `object(forKey:)` 对任何已声明的键都恒非 nil——它答不出「盘上有没有」。
    private func persistedValue(of key: String) -> Any? {
        guard let domain = Bundle.main.bundleIdentifier else { return nil }
        return UserDefaults.standard.persistentDomain(forName: domain)?[key]
    }

    /// 还原一个持久域原值：原本有键写回原值、原本没键删键（写 `[:]` 会在域里留下一个存在的键）。
    private func restore(_ value: Any?, to key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

// MARK: - 偏好快照（文件私有）

/// 用例读写过的两个真实键的原值（`TakeoverProbeModule` 的接管键 = `enableTimerFeature`；
/// 写路径的另一半是 `moduleEnableOverrides`）——本文件只用这两个，因此快照就两个字段。
private struct PreferenceSnapshot {
    let enableTimerFeature: Any?
    let moduleEnableOverrides: Any?
}

// MARK: - 假模块与账本（文件私有）

/// 假模块的 manifest 工厂（与 `ModuleKernelTests` / `ModuleToggleTests` 同一口径：字面量构造）。
private enum TakeoverFixture {
    static func manifest(
        shortID: String,
        surfaces: [Surface] = [.expanded],
        order: Int? = 10,
        defaultEnabled: Bool = false
    ) -> ModuleManifest {
        ModuleManifest(
            manifestVersion: 1,
            id: "com.cmeng.gourd.\(shortID)",
            name: LocalizedText(key: "module.\(shortID).name"),
            summary: nil,
            icon: IconSpec(type: "symbol", name: "square"),
            version: "1.0.0",
            apiVersion: HostInfo.currentAPIVersion,
            kind: "builtin",
            surfaces: surfaces,
            defaultPlacement: order.map { Placement(slot: nil, order: $0) },
            defaultEnabled: defaultEnabled,
            permissions: [],
            config: nil
        )
    }
}

/// `activate()` / `deactivate()` 的调用账本（计数型假模块的判据；`tearDown` 后不复用）。
@MainActor
private enum TakeoverLedger {
    static var activations: [String: Int] = [:]
    static var deactivations: [String: Int] = [:]

    static func reset() {
        activations.removeAll()
        deactivations.removeAll()
    }
}

/// 假模块基线：**非接管**（三条钩子都显式写成缺省语义，好让子类能 `override` 到别的实现——
/// 基类不声明、子类就只能走协议扩展的静态派发，接管模块的声明会被静默忽略）。
///
/// 注意 `takeoverEnableKey` 是**协议要求**（缺省实现在 `GourdModule` 的扩展里）：本类显式重写它，
/// 是为了让 `TakeoverProbeModule` 那一层能 `override`——经 `any GourdModule.Type` 取用时走的是
/// 具体模块的实现，不是扩展缺省。
@MainActor
private class TakeoverProbeBase: GourdModule {
    class var manifest: ModuleManifest {
        TakeoverFixture.manifest(shortID: "probe-takeover-base", surfaces: [.expanded])
    }

    class var takeoverEnableKey: Defaults.Key<Bool>? { nil }
    class func isTabVisible() -> Bool { true }
    class var homeBlockWidth: ModuleHomeBlockWidth? { nil }

    let context: ModuleContext

    required init(context: ModuleContext) {
        self.context = context
    }

    func activate() async throws {
        TakeoverLedger.activations[Self.manifest.id, default: 0] += 1
    }

    func deactivate() async {
        TakeoverLedger.deactivations[Self.manifest.id, default: 0] += 1
    }

    func content(for request: ContentRequest) -> ModuleContent { .none }
}

/// 接管模块：`takeoverEnableKey` 指向真的上游键 `.enableTimerFeature`（本批唯一被读写的真实键）。
private class TakeoverProbeModule: TakeoverProbeBase {
    /// `defaultEnabled = true`：**故意**与上游键的语义相反，好让「接管键压过 manifest 默认」可判
    /// （见 `testTakeoverKeyBeatsOverridesAndManifestDefault` 的第一个断言）。
    override class var manifest: ModuleManifest {
        TakeoverFixture.manifest(
            shortID: "probe-takeover",
            surfaces: [.expanded],
            order: 10,
            defaultEnabled: true
        )
    }

    override class var takeoverEnableKey: Defaults.Key<Bool>? { .enableTimerFeature }
}

/// 接管模块 + `isTabVisible() == false`（定时器那种「启用之外还有可见性条件」的形态）。
private final class TakeoverHiddenTabProbeModule: TakeoverProbeModule {
    override class var manifest: ModuleManifest {
        TakeoverFixture.manifest(shortID: "probe-takeover-hidden-tab", surfaces: [.expanded], order: 20)
    }

    override class func isTabVisible() -> Bool { false }
}

/// 接管模块 + 声明块宽 140/160（镜子那一档，docs/20 §接口与数据形状 5）。
private final class TakeoverWideBlockProbeModule: TakeoverProbeModule {
    override class var manifest: ModuleManifest {
        TakeoverFixture.manifest(shortID: "probe-takeover-wide", surfaces: [.home], order: 2)
    }

    override class var homeBlockWidth: ModuleHomeBlockWidth? {
        ModuleHomeBlockWidth(min: 140, ideal: 160)
    }
}

/// 接管模块 + `activate()` 必抛错（`failed` 终态的判据）；抛错前记一次调用，供「不重试」断言。
private final class TakeoverFailingProbeModule: TakeoverProbeModule {
    struct ActivationFailure: Error {}

    override class var manifest: ModuleManifest {
        TakeoverFixture.manifest(shortID: "probe-takeover-failing", surfaces: [.expanded], order: 30)
    }

    override func activate() async throws {
        TakeoverLedger.activations[Self.manifest.id, default: 0] += 1
        throw ActivationFailure()
    }
}
