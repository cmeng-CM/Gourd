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
//  - **桥幂等（进入时先清空）**：`startTakeoverBridge` 进入时先 `removeAll()`，再按当前注册表里的
//    接管模块逐个建订阅——重复起桥是**替换**不是翻倍，注册表清空后再起桥不会留下上一段的订阅，
//    非接管模块不建订阅；
//  - **块宽钩子**：声明 140/160 的模块取值一致、未声明为 nil、未注册 id 为 nil；
//  - **回弹策略**（`ModuleEnablementRollback`，D-13）：接管模块 nil（什么都不写）、非接管模块 false。
//
//  P2 接管批次 / T2 追加（同一个真模块的声明与计数）：
//  - **`TimerModule` 的 manifest 契约**：`surfaces == [.expanded]`（不含 `.compact`）、
//    `moduleID == manifest.id`、`config` 只登记上游三键、两条取值型钩子（真源键 / 无块宽）；
//  - **计数回归**（docs/20 §做法 机制五）：上游那条 `+1` 删掉后，计时器对
//    `enabledStandardTabCount()` 的贡献仍是 1 / 0 / 0（启用 × 显示方式三种组合）。
//
//  P2 接管批次 / T3 追加（计时器页判据——第二入口与 250pt 高度档）：
//  - **`isTimerSurfaceSelected()`**（docs/20 §做法 机制六 / D-11）三档：
//    `.timer`（老路径，枚举成员按机制六保留）与 `.module` + `TimerModule.moduleID`
//    （今天唯一的生产形态：悬浮聚焦 / 点预设 / `startCustomTimer` 三条路径都走它）都答 true；
//    `.module` + 别的模块 id、以及 `.home`（哪怕 `selectedModuleID` 残留着计时器 id）答 false。
//
//  三条刻意写死的口径（改动前先读）：
//
//  1. **注册一律走真门 `KernelBootstrap.enablementGate(registry:)`**：用旧门
//     （`manifests[$0]?.defaultEnabled`）的话接管键根本不被读，read-through 用例永不可能过；
//  2. **不调 `KernelBootstrap.bootstrap()`**：那个入口会落首启默认值（写开发机真实的
//     `enableScreenAssistant`，见派发片段与 `KernelBootstrap.applyFirstLaunchDefaults`）。
//     用例只调注册表自己的 `bootstrap()`，桥直接调 `KernelBootstrap.startTakeoverBridge`；
//  3. **偏好卫生**：每个写真实键的用例进入时记下该键的**持久域原值**、`defer` 逐字还原
//     （原本有键写回原值、原本没键删键）——跑完 `defaults read com.cmeng.gourd.dev <键>`
//     （测试域是 Debug 域，不是 Release 域 `com.cmeng.gourd`）与跑之前相同。
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
        XCTAssertEqual(deactivations(id), 1, "置关真的走到了模块的 deactivate()（不是只改状态 / 只摘实例）")
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

    // MARK: - 桥幂等（进入时先清空）

    /// 它钉的是 `startTakeoverBridge` **进入时先清空**（`takeoverSubscriptions.removeAll()`）这一条：
    /// 清掉的是**本用例上一段自己起的桥**，与其它用例在订阅表里留下的残留无关——跑单条也成立。
    ///
    /// 两段刻意用**不同 id**：订阅表是 `[String: AnyCancellable]`，同一个 id 重复建桥是「替换」——
    /// 第二段若还注册第一段的 id，缺 `removeAll()` 也只有 2 条，区分不出「替换」与「先清空」。
    ///
    /// 本用例**不写**任何真实偏好：门只读（`Defaults[takeoverKey]`），判定结果与断言无关。
    func testStartTakeoverBridgeClearsOnEntryAndSubscribesOnlyTakeoverModules() async {
        let registry = ModuleRegistry.shared
        // ① 两个接管模块 + 一个非接管基类：只有接管模块建订阅。
        registry.register(
            [TakeoverProbeModule.self, TakeoverHiddenTabProbeModule.self, TakeoverProbeBase.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )
        XCTAssertEqual(registry.manifests.count, 3, "前置：三个夹具都已注册")
        XCTAssertNil(registry.takeoverEnableKey(for: baseID), "前置：基类是**非接管**模块（缺省 nil）")

        KernelBootstrap.startTakeoverBridge(registry: registry)
        XCTAssertEqual(KernelBootstrap.takeoverSubscriptionCount, 2, "只订阅两个接管模块")

        // ② 注册表清空 → 只注册一个**新 id** 的接管模块再起桥：进入时先清空的话订阅表里只剩这 1 条；
        //    缺 `removeAll()` 时上一段那 2 条仍挂在同一个字典上（新 id 不覆盖旧键），条数必然 > 1
        //    （本机单跑实测 4 = 本用例那 2 条 + 宿主进程启动时既有的计时器 1 条）。
        await registry.deactivateAll()
        XCTAssertEqual(registry.manifests.count, 0, "前置：注册表已清空（订阅表不随注册表收敛）")
        registry.register(
            [TakeoverWideBlockProbeModule.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )
        XCTAssertEqual(
            registry.takeoverEnableKey(for: wideBlockID)?.name,
            Defaults.Keys.enableTimerFeature.name,
            "前置：第二段这个新 id 也是接管模块"
        )

        KernelBootstrap.startTakeoverBridge(registry: registry)
        XCTAssertEqual(
            KernelBootstrap.takeoverSubscriptionCount,
            1,
            "重复起桥不得翻倍（进入先 removeAll）：上一段那 2 条订阅必须消失，实到 1"
        )
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

    // MARK: - 计时器接管模块（T2）

    /// docs/20 §接口与数据形状 5 的 timer 行：**这个真模块**的 manifest 声明值逐条对齐。
    ///
    /// 三条钩子与启用门的**行为**（真源压过 overrides / 可见性过滤 / 重同步）已由本文件上半段的
    /// 假模块覆盖，这里钉的是真模块的声明：`surfaces` 不含 `.compact`（D-09）、tab 落模块段
    /// （`defaultPlacement == nil`）、`config` 只登记上游三键（D-03）。
    func testTimerModuleManifestMatchesTakeoverContract() throws {
        let manifest = TimerModule.manifest
        XCTAssertNoThrow(try manifest.validate())

        XCTAssertEqual(manifest.id, TimerModule.moduleID, "moduleID 与 manifest.id 必须是同一份字面量")
        XCTAssertEqual(manifest.id, "com.cmeng.gourd.timer")
        XCTAssertEqual(manifest.shortID, "timer")
        XCTAssertEqual(manifest.name.key, "module.timer.name")
        XCTAssertEqual(manifest.summary?.key, "module.timer.summary")
        XCTAssertEqual(manifest.icon, IconSpec(type: "symbol", name: "timer"))
        XCTAssertEqual(manifest.kind, "builtin")
        XCTAssertEqual(manifest.surfaces, [.expanded], "只声明 expanded（D-09：本批不声明任何 compact）")
        XCTAssertFalse(manifest.surfaces.contains(.compact), "接管模块不占折叠槽位")
        XCTAssertNil(manifest.defaultPlacement, "tab 落模块段（无 placement → Int.max，docs/20 §已知限制 2）")
        XCTAssertEqual(manifest.defaultEnabled, true, "= 上游 `enableTimerFeature` 的默认值（接管键读不到时才不生效）")
        XCTAssertTrue(manifest.permissions.isEmpty, "本批只搬渲染归属与开关真源：零新增能力请求")

        let properties = try XCTUnwrap(manifest.config?.properties)
        XCTAssertEqual(properties.count, 3, "config 只登记上游三键，不新发明键（D-03）")
        XCTAssertEqual(properties["enableTimerFeature"]?.type, "boolean")
        XCTAssertEqual(properties["enableTimerFeature"]?.default, ConfigValue.bool(true))
        XCTAssertEqual(properties["timerDisplayMode"]?.type, "enum")
        XCTAssertEqual(properties["timerDisplayMode"]?.values, ["tab", "popover"])
        XCTAssertEqual(properties["timerDisplayMode"]?.default, ConfigValue.string("tab"))
        XCTAssertEqual(properties["timerPresets"]?.type, "list")
        XCTAssertEqual(properties["timerPresets"]?.itemType, "string")
        XCTAssertNil(properties["timerPresets"]?.default, "预设清单不给 default（结构比 06 §5.3 标量复杂，只登记键名）")

        // 两条取值型钩子：真源 = 上游总开关；本模块不接首页块 → 不声明块宽
        XCTAssertEqual(TimerModule.takeoverEnableKey?.name, Defaults.Keys.enableTimerFeature.name)
        XCTAssertNil(TimerModule.homeBlockWidth, "只接展开 tab（宿主统一宽度）")

        // 字面量 manifest 也能走 JSON（与宿主读 descriptor 同一条路）
        XCTAssertEqual(try ModuleManifest.decode(from: try JSONEncoder().encode(manifest)), manifest)
    }

    /// 计数回归（docs/20 §做法 机制五 / §验收标准 1）：上游那条「功能开着 + 显示方式选 tab」的 `+1`
    /// 从 `enabledStandardTabCount()` 删掉后，计时器对它的贡献必须仍是 **1 / 0 / 0**——
    /// 这一数是刘海最小宽度的唯一输入，错一位就是宽度回归。
    ///
    /// 三点刻意写死（改动前先读）：
    /// 1. **自己置全夹具**：`enabledStandardTabCount()` 读到的每条上游键都压到 false——
    ///    那一段读的是**测试域**（Debug 域 `com.cmeng.gourd.dev`，不是 Release 域 `com.cmeng.gourd`）
    ///    盘上的值，不能当常数用：这一域写这段注释时的读数是 `enableTimerFeature = 0`、
    ///    `timerDisplayMode` **缺键**（`defaults read com.cmeng.gourd.dev <键>`；缺键走 Defaults 默认
    ///    `.tab`）——不置夹具的话启用真源那条是 0：模块不激活、不进 tab 投影，① 期望 1 实到 0，直接红；
    /// 2. **注册走真门**（`KernelBootstrap.enablementGate`）：接管键是启用的唯一真源——
    ///    旧门（`manifests[$0]?.defaultEnabled` 或用户 overrides）根本读不到上游键；
    /// 3. 三种组合各自**重新注册**（`deactivateAll` → `register` → `bootstrap`）：门只在注册那一刻
    ///    判过（`setEnabled` 不重读门），重注册走的正是应用启动时 `bootstrap()` 的那条路；
    ///    运行期改键的路径（重同步桥）由 T1 的用例覆盖。
    func testTimerModuleKeepsEnabledStandardTabCountParity() async {
        // 夹具键：`enabledStandardTabCount()` 的上游输入穷举（Home / Shelf / Stats / Notes-Clipboard /
        // Terminal 五条，加计时器的启用与显示方式两条）。
        let upstreamKeys = [
            Defaults.Keys.showStandardMediaControls.name,
            Defaults.Keys.showCalendar.name,
            Defaults.Keys.showMirror.name,
            Defaults.Keys.dynamicShelf.name,
            Defaults.Keys.enableStatsFeature.name,
            Defaults.Keys.enableNotes.name,
            Defaults.Keys.enableClipboardManager.name,
            Defaults.Keys.enableTerminalFeature.name,
        ]
        let keys = upstreamKeys + [
            Defaults.Keys.enableTimerFeature.name,
            Defaults.Keys.timerDisplayMode.name,
        ]
        let originals = snapshotValues(of: keys)
        defer { restoreValues(originals, for: keys) }

        Defaults[.showStandardMediaControls] = false
        Defaults[.showCalendar] = false
        Defaults[.showMirror] = false
        Defaults[.dynamicShelf] = false
        Defaults[.enableStatsFeature] = false
        Defaults[.enableNotes] = false
        Defaults[.enableClipboardManager] = false
        Defaults[.enableTerminalFeature] = false

        let registry = ModuleRegistry.shared
        let timerID = TimerModule.moduleID

        // ① 功能开 + 显示方式选 tab → 贡献 1（与上游分支删掉之前同一结果）
        Defaults[.enableTimerFeature] = true
        Defaults[.timerDisplayMode] = .tab
        registry.register([TimerModule.self], enabled: KernelBootstrap.enablementGate(registry: registry))
        await registry.bootstrap()

        XCTAssertEqual(registry.states[timerID], .active, "接管键 true → 启用门放行")
        XCTAssertTrue(TimerModule.isTabVisible(), "显示方式选 tab → 此刻该在 tab 列表里")
        XCTAssertEqual(registry.tabEntries.map(\.id), [timerID], "接管的 tab 由模块投影产出（上游分支已删）")
        XCTAssertEqual(enabledStandardTabCount(), 1, "① 计时器的贡献 = 1")

        // ② 功能开 + 显示方式改选 popover → 贡献 0（模块仍 active：可见性 ≠ 启用）
        Defaults[.timerDisplayMode] = .popover
        XCTAssertEqual(registry.states[timerID], .active, "可见性只在投影层过滤，不改模块状态")
        XCTAssertFalse(TimerModule.isTabVisible(), "显示方式不是 tab → 不该在 tab 列表里")
        XCTAssertTrue(registry.tabEntries.isEmpty, "投影随之消失")
        XCTAssertEqual(enabledStandardTabCount(), 0, "② 计时器的贡献 = 0")

        // ③ 功能关 → 贡献 0（门直接读上游键 → 模块不激活）
        Defaults[.timerDisplayMode] = .tab
        Defaults[.enableTimerFeature] = false
        await registry.deactivateAll()
        registry.register([TimerModule.self], enabled: KernelBootstrap.enablementGate(registry: registry))
        await registry.bootstrap()

        XCTAssertEqual(registry.states[timerID], .disabled, "接管键 false → 启用门不放行（不看 overrides / manifest 默认）")
        XCTAssertEqual(enabledStandardTabCount(), 0, "③ 计时器的贡献 = 0")
    }

    // MARK: - 计时器页判据：第二入口与 250pt 高度档（T3）

    /// `isTimerSurfaceSelected()` 三档：① `.timer` → true（老路径，枚举成员按机制六保留）；
    /// ② `.module` + `TimerModule.moduleID` → true（今天唯一的生产形态）；③ `.module` + 别的 id
    /// **与** `.home` → false（判据两段是「且」，且第二段要比对 id）。
    ///
    /// 四项刻意写死（改动前先读）：
    /// 1. **判据是纯读**：三档只调 `isTimerSurfaceSelected()`，不写 `Defaults` 的计时器键、
    ///    不注册模块——`.timer` 与 `.module` 都是枚举成员，判定与注册表 / 上游开关无关；
    /// 2. **读写的是共享协调器**（`DynamicIslandViewCoordinator.shared`，`private init` 只能取单例）：
    ///    它同时被宿主 UI 观察，用例留下的 `.module` + 计时器 id 会变成别的用例的初始状态，
    ///    因此进入时记下 `currentView` / `selectedModuleID`、`defer` 逐字还原（T3 派发片段的要求）；
    /// 3. **`enableMinimalisticUI` 必须置假**：`currentView` 的 `didSet` 在极简 UI 开着时把非 `.home`
    ///    的选中**强制打回 `.home`**（`DynamicIslandViewCoordinator.currentView`），于是 `selectModule`
    ///    只剩 `selectedModuleID` 生效、第 ①② 档必红——这是「共享协调器 + 盘上偏好」这一对的固有坑
    ///    （同款处理见 `ModuleKernelTests.testSelectModuleSetsSelectedIDAndView`）。夹具与文件内其它键
    ///    同款：持久域原值 → 置定值 → `defer` 逐字还原（原本有键写回原值、原本没键删键）；
    /// 4. **三档各一条用例**：判据的每一段都要有能单独变红的断言（变异验证见 T3 报告 §3）。
    ///
    /// 本文件的三档用例**不写**任何计时器键（第 1 条），因此只做「协调器字段 + 极简 UI 开关」的卫生。
    func testTimerSurfaceSelectedOnLegacyTimerView() {
        let coordinator = DynamicIslandViewCoordinator.shared
        let snapshot = snapshotTimerSurface()
        defer { restoreTimerSurface(snapshot) }
        Defaults[.enableMinimalisticUI] = false

        coordinator.selectedModuleID = nil
        coordinator.currentView = .timer

        XCTAssertTrue(coordinator.isTimerSurfaceSelected(), "① 老路径 `.timer` 仍是计时器页")

        // 判据第一段短路：`.timer` 档下 `selectedModuleID` 是谁都不影响结论
        coordinator.selectedModuleID = id
        XCTAssertTrue(coordinator.isTimerSurfaceSelected(), "① `.timer` 档不依赖 `selectedModuleID`")
    }

    /// ② **模块 tab + 计时器 id → true**：这是接管后唯一的生产形态——悬浮聚焦、点预设与
    /// `startCustomTimer` 三条路径都改走 `selectModule(TimerModule.moduleID)`（docs/20 §做法 机制六），
    /// 判据不认它就会出现「内容在、tab 条上没有任何 tab 高亮」且高度回落到默认档（D-11）。
    func testTimerSurfaceSelectedOnTimerModuleTab() {
        let coordinator = DynamicIslandViewCoordinator.shared
        let snapshot = snapshotTimerSurface()
        defer { restoreTimerSurface(snapshot) }
        Defaults[.enableMinimalisticUI] = false

        coordinator.selectModule(TimerModule.moduleID)

        XCTAssertEqual(coordinator.selectedModuleID, TimerModule.moduleID, "前置：selectModule 同时记下模块 id")
        XCTAssertEqual(coordinator.currentView, .module, "前置：selectModule 切到模块视图")
        XCTAssertTrue(coordinator.isTimerSurfaceSelected(), "② 模块 tab + 计时器 id = 计时器页")
    }

    /// ③ **别的模块 tab 与首页都不是计时器页**：第二段要比对模块 id（同一个 `.module` 下可以有多个
    /// 模块 tab，与 `TabSelectionView.isSelected` 同一口径）；`.home` 即使 `selectedModuleID`
    /// 还留着计时器 id 也不是（两段是「且」不是「或」）。
    func testTimerSurfaceSelectedIsFalseForOtherModuleTabAndHome() {
        let coordinator = DynamicIslandViewCoordinator.shared
        let snapshot = snapshotTimerSurface()
        defer { restoreTimerSurface(snapshot) }
        Defaults[.enableMinimalisticUI] = false

        coordinator.selectModule(id)
        XCTAssertFalse(coordinator.isTimerSurfaceSelected(), "③ `.module` + 别的模块 id 不是计时器页")

        // 残留「上次选中的是计时器」也不能算：`.home` 档下判据第一段就不成立
        coordinator.selectedModuleID = TimerModule.moduleID
        coordinator.currentView = .home
        XCTAssertEqual(coordinator.selectedModuleID, TimerModule.moduleID, "前置：首页上仍挂着计时器 id（残留选择）")
        XCTAssertFalse(coordinator.isTimerSurfaceSelected(), "③ `.home` 不是计时器页")
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

    /// 账本读取：置关次数（同上）。钉「置关走到了模块的 `deactivate()`」这条。
    private func deactivations(_ id: String) -> Int { TakeoverLedger.deactivations[id] ?? 0 }

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

    // MARK: - 协调器页面字段（T3）

    /// 共享协调器的页面字段 + `enableMinimalisticUI` 的持久域原值。
    ///
    /// 前者是 T3 三档用例读写的状态；后者是它们的前置条件（`currentView` 的 `didSet` 在极简 UI
    /// 开着时把非 `.home` 的选中打回 `.home`），因此也要纳入卫生——夹具取值见各用例的注释。
    private struct TimerSurfaceSnapshot {
        let currentView: NotchViews
        let selectedModuleID: String?
        let enableMinimalisticUI: Any?
    }

    /// 进入时记下协调器两个字段 + 极简 UI 键的**持久域**原值（不读 `Defaults[...]`，理由同 `persistedValue(of:)`）。
    private func snapshotTimerSurface() -> TimerSurfaceSnapshot {
        let coordinator = DynamicIslandViewCoordinator.shared
        return TimerSurfaceSnapshot(
            currentView: coordinator.currentView,
            selectedModuleID: coordinator.selectedModuleID,
            enableMinimalisticUI: persistedValue(of: Defaults.Keys.enableMinimalisticUI.name)
        )
    }

    /// 逐字还原（顺序有意）：先还原极简 UI 键（它决定 `didSet` 要不要打回 `.home`），再写回两个字段，
    /// 这样即使原 `currentView` 不是 `.home`，落盘的最后一个值也与进入前一致。
    private func restoreTimerSurface(_ snapshot: TimerSurfaceSnapshot) {
        restore(snapshot.enableMinimalisticUI, to: Defaults.Keys.enableMinimalisticUI.name)
        let coordinator = DynamicIslandViewCoordinator.shared
        coordinator.selectedModuleID = snapshot.selectedModuleID
        coordinator.currentView = snapshot.currentView
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
