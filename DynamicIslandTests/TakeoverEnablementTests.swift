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
//  P2 接管批次 / T4 追加（镜子接管模块 + 首页块顺序表的历史键映射）：
//  - **`MirrorModule` 的 manifest 契约**：`surfaces == [.home]`（不含 `.expanded` / `.compact`）、
//    `defaultPlacement == Placement(slot: nil, order: 2)`、真源键 `showMirror`、块宽 140/160、
//    `config` 只登记上游三键；
//  - **`MirrorModule.isVisible(showMirror:cameraAvailable:)`** 四组：两段是「且」；
//  - **`HomeBlockOrdering.migratingLegacyIDs`** 四组：旧键 → 新 id、新键优先、非映射键逐字保留、
//    空表恒等；另有一条**经 `sorted(...)` 走一遍**的用例（映射是 `sorted` 的第一步——只测纯函数的话
//    「映射没接上」不会红）。
//
//  P2 接管批次 / T5 追加（音乐接管模块 + 命名空间环境键的默认值半边）：
//  - **`MusicModule` 的 manifest 契约**：`surfaces == [.home]`（不含 `.expanded` / `.compact`）、
//    `defaultPlacement == Placement(slot: nil, order: 0)`（= 被接管的内置音乐块的默认序号）、
//    真源键 `showStandardMediaControls`、块宽 300/420、`config` 只登记上游两键；
//  - **`MusicModule.isVisible(showStandardMediaControls:autoHideInactive:hasActiveSession:)`** 四组：
//    两段是「且」（表达式逐字沿用上游那个 `shouldShowMusicPlayer`）；
//  - **`EnvironmentValues().homeAlbumArtNamespace == nil`**（D-08 的默认值一半：没人注入时是 nil，
//    模块侧据此退回自带 `@Namespace`）。**注入那一半没有自动化断言**——注入点是 SwiftUI 视图修饰符
//    （`HomeStripView` 的 `.environment(\.homeAlbumArtNamespace, …)`），起作用与否只能人工验收
//    （封面配对动画：折叠态播放器 ↔ 展开态音乐块）；为它造一条「读回自己刚写的环境值」的断言
//    只是把修饰符抄进用例，不证明宿主真的注入了，故不写（见 T5 报告 §4）。
//
//  P2 接管批次 / T6 追加（组件页的文案解析——功能卡段 + 接管卡的效果行）：
//  - **七张功能卡的键解析**：数据源是生产表本身（`ModuleSettingsSection.featureCards`，为了这条
//    用例它没写成 `private`）——`id` / `effectKey` / `nameKey` 写错或文案没进 catalog 都会红；
//  - **三个接管模块的名称 / 效果行 key 解析**：名称 key 取自真模块的 manifest（与 `label(for:)`
//    同源）；
//  - **回弹两档**用三个真模块的真源键再钉一遍（钉的是策略函数，不是视图接线——同见报告）。
//
//  P2 接管批次 / T6 **修复**（补齐上一轮两条覆盖缺口的第二条 + 测试本地化形态）：
//  - **效果行映射有断言了**：映射从 `ModuleSettingsCard` 的私有 switch 提成生产表
//    `ModuleSettingsSection.effectKeysByModuleID`（internal），`testModuleEffectKeysMatchTableAndCatalog`
//    迭代它——值写错（含写成另一条已存在的 key）与模块 id 写错都会红。上一轮「把
//    `settings.modules.effect.music` 改成错字」是全绿的（T6 报告 §3 变异 ②b）；
//  - **`XCTAssertResolves` 锁定语言**：改查宿主 bundle 的 **zh-Hans** 那一份。七条上游名称 key
//    没有 `en` 值，原先的 `Bundle.main.localizedString + != key` 跟着机器语言走（英语环境下红）。
//    Swift 在 Darwin 上没导入带 `localization:` 的四参重载，故用等价的 `.lproj` 子 bundle 形态。
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
import SwiftUI
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

    // MARK: - 镜子接管模块（T4）

    /// docs/20 §接口与数据形状 5 的 mirror 行：**这个真模块**的 manifest 声明值逐条对齐。
    ///
    /// 与 `testTimerModuleManifestMatchesTakeoverContract` 同款：三条钩子的**行为**（真源压过
    /// overrides / 可见性过滤 / 重同步）由本文件上半段的假模块覆盖，这里钉的是真模块的声明——
    /// `surfaces == [.home]`（不声明 tab、不占折叠槽位）、`order 2`（= 被接管的内置块的默认序号，
    /// 接管前后首页顺序一致）、真源键 `showMirror`、块宽 140/160（D-10）。
    ///
    /// 本用例**不写**任何真实偏好（只读钩子与常量）。
    func testMirrorModuleManifestMatchesTakeoverContract() throws {
        let manifest = MirrorModule.manifest
        XCTAssertNoThrow(try manifest.validate())

        XCTAssertEqual(manifest.id, MirrorModule.moduleID, "moduleID 与 manifest.id 必须是同一份字面量")
        XCTAssertEqual(manifest.id, "com.cmeng.gourd.mirror")
        XCTAssertEqual(manifest.shortID, "mirror")
        XCTAssertEqual(manifest.name.key, "module.mirror.name")
        XCTAssertEqual(manifest.summary?.key, "module.mirror.summary")
        XCTAssertEqual(manifest.icon, IconSpec(type: "symbol", name: "camera"))
        XCTAssertEqual(manifest.kind, "builtin")
        XCTAssertEqual(manifest.surfaces, [.home], "只声明首页块（D-09：本批不声明任何 compact）")
        XCTAssertFalse(manifest.surfaces.contains(.expanded), "不声明 expanded → 不进 tab 投影")
        XCTAssertFalse(manifest.surfaces.contains(.compact), "接管模块不占折叠槽位")
        XCTAssertEqual(
            manifest.defaultPlacement,
            Placement(slot: nil, order: 2),
            "slot 只在含 compact 时有意义；order 2 = 被它取代的内置镜子块的默认序号"
        )
        XCTAssertEqual(
            manifest.defaultPlacement?.order,
            HomeBlockOrdering.BuiltinBlock.mirror.defaultOrder,
            "接管前后的默认序号必须相同（否则未调过顺序的用户会看到块跳位）"
        )
        XCTAssertEqual(manifest.defaultEnabled, false, "= 上游 `showMirror` 的默认值（接管键读不到时才不生效）")
        XCTAssertTrue(manifest.permissions.isEmpty, "本批只搬渲染归属与开关真源：零新增能力请求（含摄像头 TCC）")

        let properties = try XCTUnwrap(manifest.config?.properties)
        XCTAssertEqual(properties.count, 3, "config 只登记上游三键，不新发明键（D-03）")
        XCTAssertEqual(properties["showMirror"]?.type, "boolean")
        XCTAssertEqual(properties["showMirror"]?.default, ConfigValue.bool(false))
        XCTAssertEqual(properties["mirrorShape"]?.type, "enum")
        XCTAssertEqual(properties["mirrorShape"]?.values, ["Rectangular", "Circular"])
        XCTAssertEqual(properties["mirrorShape"]?.default, ConfigValue.string("Rectangular"))
        XCTAssertEqual(properties["selectedCameraID"]?.type, "string")
        XCTAssertEqual(properties["selectedCameraID"]?.default, ConfigValue.string(""), "空串 = 跟随第一台（上游键的默认值）")
        XCTAssertNil(properties["selectedCameraID"]?.values, "设备 id 是运行期发现的值，不列可选值")

        // 两条取值型钩子：真源 = 上游总开关；块宽 = 被接管块原本的那一档
        XCTAssertEqual(MirrorModule.takeoverEnableKey?.name, Defaults.Keys.showMirror.name)
        XCTAssertEqual(MirrorModule.homeBlockWidth, ModuleHomeBlockWidth(min: 140, ideal: 160))

        // 字面量 manifest 也能走 JSON（与宿主读 descriptor 同一条路）
        XCTAssertEqual(try ModuleManifest.decode(from: try JSONEncoder().encode(manifest)), manifest)
    }

    /// 镜子块的**存在性判据**（docs/20 §做法 机制一末段）：`showMirror && cameraAvailable`——
    /// 两段是「且」，且**不含展开态**（`.home` 块只在展开面板首页渲染，旧内置块重复判一次
    /// `notchState == .open` 的写法本批一并删除）。
    ///
    /// 本用例**不写**任何真实偏好（判据是纯函数，两个入参都是形参）。
    func testMirrorVisibilityPredicate() {
        XCTAssertTrue(
            MirrorModule.isVisible(showMirror: true, cameraAvailable: true),
            "功能开 + 有摄像头 → 块在"
        )
        XCTAssertFalse(
            MirrorModule.isVisible(showMirror: true, cameraAvailable: false),
            "有开关但没摄像头 → 块消失（答 .none 不占位，不是画一个空壳）"
        )
        XCTAssertFalse(
            MirrorModule.isVisible(showMirror: false, cameraAvailable: true),
            "摄像头在但功能关着 → 块消失（与接管前的 `showMirror && …` 同序）"
        )
        XCTAssertFalse(
            MirrorModule.isVisible(showMirror: false, cameraAvailable: false),
            "两段都不成立 → 块消失"
        )
    }

    /// 注册表侧的接管查询对**真模块**同样成立（docs/20 §接口与数据形状 2）：`homeBlockWidth(for:)`
    /// 取回 140/160（`HomeStripView` 就靠它让镜子块保持改动前的档位，D-10）、`takeoverEnableKey(for:)`
    /// 取回 `showMirror`（启用真源）。
    ///
    /// 注册走**真门**（`KernelBootstrap.enablementGate`），但**不 bootstrap**：门只读，
    /// 本用例不写任何真实偏好（镜子当前的启用状态与断言无关）。
    func testMirrorModuleHooksReadThroughTheRegistry() {
        let registry = ModuleRegistry.shared
        registry.register(
            [MirrorModule.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )

        XCTAssertEqual(
            registry.homeBlockWidth(for: MirrorModule.moduleID),
            ModuleHomeBlockWidth(min: 140, ideal: 160),
            "镜子块宽度声明经注册表原样取给宿主（140/160，与接管前同一档）"
        )
        XCTAssertEqual(
            registry.takeoverEnableKey(for: MirrorModule.moduleID)?.name,
            Defaults.Keys.showMirror.name,
            "镜子的启用真源 = 上游 `showMirror` 键"
        )
    }

    // MARK: - 首页块顺序表的历史键映射（T4）

    /// `migratingLegacyIDs` 的四组口径（docs/20 §做法 机制四 / §接口与数据形状 4）：
    /// ① 旧键 → 新 id（新 id 缺席时生效）；② 新键优先（用户在新版里表达过）；③ 两个旧键都映射、
    /// 表里其它键（含不迁移的 `builtin.calendar`）逐字保留；④ 空表 / 无旧键 → 恒等。
    ///
    /// 新 id 一律用 `MirrorModule.moduleID` / 字面量查表：`HomeBlockOrdering` 是纯逻辑文件、
    /// 不认识模块类型（那边写的是字面量），两处一致由本用例钉住——id 任一处漂了这里就红。
    ///
    /// 本用例**不写**任何真实偏好（纯函数，入参是字典）。
    func testMigratingLegacyIDsMapsOnlyWhenNewIDIsAbsent() {
        let mirrorID = MirrorModule.moduleID

        // ① 旧键 → 新 id：老用户排过的位置跟着搬到改名后的块上
        let mapped = HomeBlockOrdering.migratingLegacyIDs(["builtin.mirror": -1])
        XCTAssertEqual(mapped[mirrorID], -1, "builtin.mirror 的值要落到镜子模块 id 上")
        XCTAssertEqual(mapped["builtin.mirror"], -1, "旧键**保留**在返回的表里（别名语义：设置页顺序节只列模块 id，旧键今天没有消费者，盘上那一条只在第一次重排前还在）")

        // ② 新键优先：新 id 已有自己的值 → 旧值不覆盖它
        let newWins = HomeBlockOrdering.migratingLegacyIDs(["builtin.mirror": -1, mirrorID: 3])
        XCTAssertEqual(newWins[mirrorID], 3, "只在新 id 缺席时才搬旧值")
        XCTAssertEqual(newWins["builtin.mirror"], -1, "旧键自身不动（它只是没人再查）")

        // ③ 两个旧键同时映射；非映射键（日历 / 模块 id / 任意键）逐字保留
        let mixed = HomeBlockOrdering.migratingLegacyIDs([
            "builtin.music": 1,
            "builtin.calendar": 0,
            "com.cmeng.gourd.todos": 5,
        ])
        XCTAssertEqual(mixed["com.cmeng.gourd.music"], 1, "builtin.music 同样映射（T5 接管音乐前先就位）")
        XCTAssertEqual(mixed["builtin.calendar"], 0, "日历不迁移（今天已不在任何名单里，迁移它没有接收者）")
        XCTAssertEqual(mixed["com.cmeng.gourd.todos"], 5, "表里的模块 id 逐字保留")
        XCTAssertEqual(mixed.count, 4, "只多出一条（新 id），不清理、不改写旧键")

        // ④ 空表与「没有旧键的表」恒等
        XCTAssertEqual(HomeBlockOrdering.migratingLegacyIDs([:]), [:], "空表 → 空表")
        let untouched = ["com.cmeng.gourd.progress": 2, "com.cmeng.gourd.todos": 0]
        XCTAssertEqual(HomeBlockOrdering.migratingLegacyIDs(untouched), untouched, "没有旧键 → 原样返回")
    }

    /// 映射是 **`sorted(...)` 的第一步**（docs/20 §接口与数据形状 4 末句）：只钉纯函数的话，
    /// 「映射没接上排序」不会红——这条用例整条经 `sorted` 走一遍。
    ///
    /// 输入表用的是**老表**（只有 `builtin.mirror`），名单用的是**接管后的名单**（镜子是模块 id）：
    /// 判据就是「老用户排过镜子 → 重启后镜子仍在最前」。
    ///
    /// 本用例**不写**任何真实偏好（`sorted` 是纯函数，覆盖表是形参）。
    func testSortedAppliesLegacyMigrationBeforeRanking() {
        let mirrorID = MirrorModule.moduleID
        let blocks: [(id: String, order: Int)] = [
            (id: "builtin.music", order: 0),
            (id: mirrorID, order: 2),
            (id: "com.cmeng.gourd.todos", order: 20),
        ]

        let sorted = HomeBlockOrdering.sorted(
            blocks,
            defaultOrder: { $0.order },
            id: { $0.id },
            overrides: ["builtin.mirror": -1]
        ).map(\.id)

        XCTAssertEqual(
            sorted,
            [mirrorID, "builtin.music", "com.cmeng.gourd.todos"],
            "老表里的 builtin.mirror = -1 要把镜子模块块提到最前（映射没接上时它按默认 2 排，会红）"
        )
    }

    // MARK: - 音乐接管模块（T5）

    /// docs/20 §接口与数据形状 5 的 music 行：**这个真模块**的 manifest 声明值逐条对齐。
    ///
    /// 与 `testTimerModuleManifestMatchesTakeoverContract` / `testMirrorModuleManifestMatchesTakeoverContract`
    /// 同款：三条钩子的**行为**（真源压过 overrides / 可用性过滤 / 重同步）由本文件上半段的假模块覆盖，
    /// 这里钉的是真模块的声明——`surfaces == [.home]`（不声明 tab、不占折叠槽位）、`order 0`
    /// （= 被接管的内置音乐块的默认序号，接管前后首页顺序一致）、真源键 `showStandardMediaControls`、
    /// 块宽 300/420（D-10）。
    ///
    /// `config` 两个键的默认值**取上游键的默认值**（D-03 / docs/20 §已知限制 1：登记值必须等于真源值，
    /// 否则这份登记就是假的）：`playerColorTinting` 与 `useMusicVisualizer` 在上游
    /// （`Constants.swift` 的 `Defaults.Keys`）**都是 `true`**——后者的名字带「可视化」，容易按直觉
    /// 记成默认关，本用例把它钉在真值上。
    ///
    /// 本用例**不写**任何真实偏好（只读钩子与常量），因此没有夹具与还原。
    func testMusicModuleManifestMatchesTakeoverContract() throws {
        let manifest = MusicModule.manifest
        XCTAssertNoThrow(try manifest.validate())

        XCTAssertEqual(manifest.id, MusicModule.moduleID, "moduleID 与 manifest.id 必须是同一份字面量")
        XCTAssertEqual(manifest.id, "com.cmeng.gourd.music")
        XCTAssertEqual(manifest.shortID, "music")
        XCTAssertEqual(manifest.name.key, "module.music.name")
        XCTAssertEqual(manifest.summary?.key, "module.music.summary")
        XCTAssertEqual(manifest.icon, IconSpec(type: "symbol", name: "music.note"))
        XCTAssertEqual(manifest.kind, "builtin")
        XCTAssertEqual(manifest.surfaces, [.home], "只声明首页块（D-09：本批不声明任何 compact）")
        XCTAssertFalse(manifest.surfaces.contains(.expanded), "不声明 expanded → 不进 tab 投影")
        XCTAssertFalse(manifest.surfaces.contains(.compact), "接管模块不占折叠槽位")
        XCTAssertEqual(
            manifest.defaultPlacement,
            Placement(slot: nil, order: 0),
            "slot 只在含 compact 时有意义；order 0 = 被它取代的内置音乐块的默认序号"
        )
        XCTAssertEqual(
            manifest.defaultPlacement?.order,
            HomeBlockOrdering.BuiltinBlock.music.defaultOrder,
            "接管前后的默认序号必须相同（否则未调过顺序的用户会看到块跳位）"
        )
        XCTAssertEqual(
            manifest.defaultEnabled,
            Defaults.Keys.showStandardMediaControls.defaultValue,
            "= 上游 `showStandardMediaControls` 的默认值（接管键读不到时才不生效）"
        )
        XCTAssertEqual(
            manifest.defaultEnabled,
            true,
            "上游这个开关默认是开的（方向也要钉住，避免它被悄悄改成保守值）"
        )
        XCTAssertTrue(manifest.permissions.isEmpty, "本批只搬渲染归属与开关真源：零新增能力请求")

        let properties = try XCTUnwrap(manifest.config?.properties)
        XCTAssertEqual(properties.count, 2, "config 只登记上游两键，不新发明键（D-03）")
        XCTAssertEqual(properties["playerColorTinting"]?.type, "boolean")
        XCTAssertEqual(properties["playerColorTinting"]?.default, ConfigValue.bool(true))
        XCTAssertEqual(properties["useMusicVisualizer"]?.type, "boolean")
        XCTAssertEqual(
            properties["useMusicVisualizer"]?.default,
            ConfigValue.bool(Defaults.Keys.useMusicVisualizer.defaultValue),
            "登记值必须等于上游键的默认值（上游为 true——不按「可视化默认关」的直觉填 false）"
        )

        // 两条取值型钩子：真源 = 上游总开关；块宽 = 被接管块原本的那一档（300/420，不是宿主统一值）
        XCTAssertEqual(MusicModule.takeoverEnableKey?.name, Defaults.Keys.showStandardMediaControls.name)
        XCTAssertEqual(MusicModule.homeBlockWidth, ModuleHomeBlockWidth(min: 300, ideal: 420))

        // 字面量 manifest 也能走 JSON（与宿主读 descriptor 同一条路）
        XCTAssertEqual(try ModuleManifest.decode(from: try JSONEncoder().encode(manifest)), manifest)
    }

    /// 音乐块的**存在性判据**（docs/20 §做法 机制一末段 / §接口与数据形状 5 的 music 行）：
    /// `showStandardMediaControls && (!autoHideInactiveNotchMediaPlayer || hasActiveSession)`
    /// ——表达式**逐字沿用**改动前的 `HomeStripView.shouldShowMusicPlayer`，且**不含展开态**。
    ///
    /// 四组：两段各自都能单独把结论翻成 false（总开关、运行期条件），第三组单独证明**第二段是「或」**
    /// （关掉「无会话即隐藏」后没有会话也该显示——这正是「显示占位元数据」那一档的语义）。
    ///
    /// 本用例**不写**任何真实偏好（判据是纯函数，三个入参都是形参）。
    func testMusicVisibilityPredicate() {
        XCTAssertTrue(
            MusicModule.isVisible(showStandardMediaControls: true, autoHideInactive: true, hasActiveSession: true),
            "总开关开 + 无会话即隐藏 + 真有会话 → 块在"
        )
        XCTAssertFalse(
            MusicModule.isVisible(showStandardMediaControls: true, autoHideInactive: true, hasActiveSession: false),
            "总开关开但没有会话（且选了「无会话即隐藏」）→ 块消失（答 .none 不占位）"
        )
        XCTAssertTrue(
            MusicModule.isVisible(showStandardMediaControls: true, autoHideInactive: false, hasActiveSession: false),
            "关掉「无会话即隐藏」后没有会话也显示（第二段是「或」：显示占位元数据那一档）"
        )
        XCTAssertFalse(
            MusicModule.isVisible(showStandardMediaControls: false, autoHideInactive: false, hasActiveSession: true),
            "总开关关着 → 会话在放也不显示（第一段是「且」的前置，与接管前的判据同序）"
        )
    }

    /// 注册表侧的接管查询对**音乐模块**同样成立（docs/20 §接口与数据形状 2）：`homeBlockWidth(for:)`
    /// 取回 300/420（`HomeStripView` 就靠它让音乐块保持改动前的档位，D-10）、`takeoverEnableKey(for:)`
    /// 取回 `showStandardMediaControls`（启用真源）。
    ///
    /// 注册走**真门**（`KernelBootstrap.enablementGate`），但**不 bootstrap**：门只读，
    /// 本用例不写任何真实偏好（音乐当前的启用状态与断言无关）。
    func testMusicModuleHooksReadThroughTheRegistry() {
        let registry = ModuleRegistry.shared
        registry.register(
            [MusicModule.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )

        XCTAssertEqual(
            registry.homeBlockWidth(for: MusicModule.moduleID),
            ModuleHomeBlockWidth(min: 300, ideal: 420),
            "音乐块宽度声明经注册表原样取给宿主（300/420，与接管前同一档）"
        )
        XCTAssertEqual(
            registry.takeoverEnableKey(for: MusicModule.moduleID)?.name,
            Defaults.Keys.showStandardMediaControls.name,
            "音乐的启用真源 = 上游 `showStandardMediaControls` 键"
        )
        XCTAssertNotEqual(
            registry.takeoverEnableKey(for: MusicModule.moduleID)?.name,
            Defaults.Keys.autoHideInactiveNotchMediaPlayer.name,
            "「无会话即隐藏」是**运行期条件**（判据的第二段），不是本模块的启用真源"
        )
    }

    /// 命名空间环境键的**默认值半边**（D-08 / docs/20 §接口与数据形状 6）：没有注入者时读到 `nil`，
    /// 模块侧据此退回自带 `@Namespace`（配对静默失效，不崩不空白）。
    ///
    /// **注入那一半没有自动化断言**：注入点是一条 SwiftUI 视图修饰符
    /// （`HomeStripView` 的 `.environment(\.homeAlbumArtNamespace, albumArtNamespace)`），
    /// 起作用与否只能靠人工验收（折叠态播放器 ↔ 展开态封面那对 matchedGeometry 动画）；
    /// 「读回自己刚写的环境值」那种断言只是把修饰符抄进用例，不证明宿主真的注入了，故不写。
    func testHomeAlbumArtNamespaceDefaultsToNil() {
        XCTAssertNil(
            EnvironmentValues().homeAlbumArtNamespace,
            "没人注入时缺省 nil（模块此时用自带 @Namespace 兜底）"
        )
    }

    // MARK: - 组件页文案解析（T6：功能卡段 + 接管卡的效果行）

    /// 七张功能卡的键在宿主 bundle 里全部能解析（docs/20 §接口与数据形状 7）：
    /// 七条效果行 key + 七条名称 key（上游设置页那一个字面量）+ 段头 / 段脚注。
    ///
    /// **数据源是生产表本身**（`ModuleSettingsSection.featureCards`——为了这条用例它没有写成
    /// `private`）：表里把 `id` / `effectKey` / `nameKey` 写错、或文案没写进 catalog，这条都会红。
    /// 测试另抄一份键表的话，「表写错、文案对」这条谁都发现不了（见 T6 报告 §候选决策）。
    ///
    /// **语言无关**（T6 修复）：七条名称 key 是上游那几个字面量，只有 zh-Hans 等译文、**没有 `en` 值**
    /// ——`XCTAssertResolves` 因此查的是宿主 bundle 的 **zh-Hans 那一份**，本机语言环境不再参与
    /// （原先的 `Bundle.main.localizedString(...) != key` 在英语环境下会红）。
    func testFeatureCardKeysResolve() {
        let cards = ModuleSettingsSection.featureCards

        XCTAssertEqual(
            cards.map(\.id),
            [
                "enableClipboardManager", "showCalendar", "enableLockScreenWeatherWidget",
                "enableStatsFeature", "dynamicShelf", "enableTerminalFeature", "enableNotes",
            ],
            "七行 = docs/20 §接口与数据形状 7 的七个上游键名，顺序与取值都不改"
        )

        for card in cards {
            XCTAssertEqual(
                card.effectKey,
                "settings.features.effect.\(card.id)",
                "\(card.id) 的效果行 key 必须是 `settings.features.effect.<键名>` 这一形态"
            )
            XCTAssertResolves(card.effectKey)
            XCTAssertResolves(card.nameKey)
        }

        XCTAssertResolves("settings.features.title")
        XCTAssertResolves("settings.features.footer")
    }

    /// 三个接管模块的卡片文案也能解析：名称 key 取**真模块的 manifest**（卡片上那行名称走
    /// `ModuleRegistry.label(for:)`，读的就是它），效果行是 T6 新增的那三条。
    ///
    /// 效果行这三条**不再是用例里的字面量**（T6 修复）：它们改由
    /// `testModuleEffectKeysMatchTableAndCatalog` 从生产映射表里取，映射侧写错会红——
    /// 原先映射是宿于 `private struct ModuleSettingsCard` 的私有 switch，用例够不到，
    /// 「把 `settings.modules.effect.music` 改成错字」是全绿的（T6 报告 §3 变异 ②b）。
    /// 本用例保留「三条 key 在 catalog 里解析得出」这一半，值那一半交给映射表用例。
    func testTakeoverModuleCardKeysResolve() throws {
        for manifest in [TimerModule.manifest, MirrorModule.manifest, MusicModule.manifest] {
            let nameKey = try XCTUnwrap(manifest.name.key, "\(manifest.id) 的名称 key 必须写成 Localizable key")
            XCTAssertEqual(nameKey, "module.\(manifest.shortID).name", "名称 key 形态与 label(for:) 同源")
            XCTAssertResolves(nameKey)
        }

        for key in [
            "settings.modules.effect.timer",
            "settings.modules.effect.mirror",
            "settings.modules.effect.music",
        ] {
            XCTAssertResolves(key)
        }
    }

    /// 组件卡的「效果 / 出现位置」映射（`ModuleSettingsSection.effectKeysByModuleID`，T6 修复）：
    /// **表是唯一取值处**，用例直接迭代生产表——
    ///
    /// ① 表里每个值都能在宿主 bundle 里解析出 zh-Hans 文案（键写错 / 文案没进 catalog → 红），
    ///    并钉住 `settings.modules.effect.<模块短名>` 的 key 形态（值被写串成另一条**已存在**的
    ///    key——比如 todos 指到 progress 那条——解析断言抓不到，这一条抓得到）；
    /// ② 接管三块的值逐条钉住（`TimerModule.manifest.id` → `settings.modules.effect.timer`，镜子 /
    ///    音乐同形）——这一条就是上一轮缺的那条断言；
    /// ③ 表里每个**模块 id** 都是已注册模块的 id（模块改名 / 表里 id 写错 → 红）。
    ///
    /// **③ 先 `register` 再取集合**：`setUp` 的 `deactivateAll()` 把 `manifests` 一起清空了
    /// （注册表因此每次都是空的），不注册就取集合会恒为空表、断言恒红。注册用
    /// `enabled: { _ in true }` 过门（不读任何偏好键、不落状态），且**不调 `bootstrap()`**：
    /// 本用例只看 manifest 的 id 集合，不激活、不碰上游键。
    ///
    /// **不钉表的条数**：`LauncherModule` 这类没有「效果 / 出现位置」一行的模块**合法地**不在表里
    /// （未命中 = 整行不显示），拿 `builtinModules.count` 去比会把它变成假红。漏一条模块的效果行
    /// 由「组件页肉眼一条」兜底，见文件头 T6 段。
    func testModuleEffectKeysMatchTableAndCatalog() {
        let table = ModuleSettingsSection.effectKeysByModuleID

        // ③ 表里的模块 id 必须都是已注册模块（注册表是单例，先补注册再取 id 集合）。
        let registry = ModuleRegistry.shared
        registry.register(KernelBootstrap.builtinModules, enabled: { _ in true })
        let registeredIDs = Set(registry.manifests.keys)
        XCTAssertFalse(registeredIDs.isEmpty, "前置：注册后不能还是空表（setUp 刚清过注册表）")
        for moduleID in table.keys.sorted() {
            XCTAssertTrue(
                registeredIDs.contains(moduleID),
                "\(moduleID) 不是已注册模块的 id（模块改名漏改表 / 表里 id 写错？）"
            )
        }

        // ① 每个值都能解析出 zh-Hans 文案（语言锁在 `XCTAssertResolves` 里）。
        for (moduleID, effectKey) in table.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(
                effectKey,
                "settings.modules.effect." + String(moduleID.split(separator: ".").last ?? ""),
                "\(moduleID) 的效果行 key 形态：`settings.modules.effect.<模块短名>`"
            )
            XCTAssertResolves(effectKey)
        }

        // ② 接管三块逐条钉死（表里把这三条写错、或 key 形态被改，都会红）。
        XCTAssertEqual(
            table[TimerModule.manifest.id], "settings.modules.effect.timer",
            "计时器的效果行 key——上一轮这条在用例里是字面量，映射侧写错抓不到"
        )
        XCTAssertEqual(
            table[MirrorModule.manifest.id], "settings.modules.effect.mirror",
            "镜子的效果行 key（同形）"
        )
        XCTAssertEqual(
            table[MusicModule.manifest.id], "settings.modules.effect.music",
            "音乐的效果行 key（同形）"
        )
    }

    /// 回弹两档仍成立（D-13 / docs/20 §做法 机制七），这里用**三个真模块的真源键**再钉一遍：
    /// 组件卡把它们的真源键交给 `preferenceToWrite` 时必须拿到 `nil`（**什么都不写**）。
    ///
    /// 注意这条钉的是**策略函数**，不是视图接线：卡里「回弹时去问策略、而不是无条件写 false」
    /// 那一句没有自动化断言（视图的 `Binding` 闭包不可直接驱动——见 T6 报告的变异记录 ①）。
    func testRollbackStaysNilForRealTakeoverKeys() {
        for key in [
            TimerModule.takeoverEnableKey,
            MirrorModule.takeoverEnableKey,
            MusicModule.takeoverEnableKey,
        ] {
            XCTAssertNotNil(key, "三个接管模块必须声明真源键（声明缺失时它就不是接管模块了）")
            XCTAssertNil(
                ModuleEnablementRollback.preferenceToWrite(takeoverKey: key),
                "接管模块的回弹是空操作——写回偏好等于因为激活失败把用户的功能关了"
            )
        }

        XCTAssertEqual(
            ModuleEnablementRollback.preferenceToWrite(takeoverKey: nil),
            false,
            "非接管模块照旧回弹（把用户的开关拨回去）"
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

    /// 本地化 key 在**宿主 bundle 的 zh-Hans 那一份**里解析得出文案（查不到时 `Bundle` 原样返回 key，
    /// 据此判定）。
    ///
    /// **为什么锁定语言**（T6 修复）：catalog 里七条上游名称 key（`Enable Clipboard Manager` 等）
    /// **没有 `en` 值**（它们在 `en` 下以 key 自身为值），因此 `Bundle.main.localizedString(forKey:value:table:)`
    /// 的结果**跟着跑测机器的语言走**：本机是 zh-Hans 时返回译文（`!= key`，断言过），英语环境下原样
    /// 返回 key（断言红）。用例要判的是「文案已进 catalog」，与机器语言无关，所以查**具体的 zh-Hans 一份**。
    ///
    /// **形态说明**：Swift 在 Darwin 上只暴露三参的 `localizedString(forKey:value:table:)`
    /// （ObjC 那条带 `localization:` 的四参方法没有导入：`extra argument 'localization' in call`），
    /// 因此「指定语言」用等价写法落到 `zh-Hans.lproj` 子 bundle 上——解析结果就是 zh-Hans 那一份译文，
    /// 本机语言环境不再参与。
    ///
    /// 与 `ModuleKernelTests` 的同类断言**不再逐字相同**：那边仍是 `Bundle.main.localizedString` +
    /// `!= key`（同样的语言依赖），本文件只修自己这一段，不去改别的测试文件。
    private func XCTAssertResolves(
        _ key: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let localizationPath = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"),
              let bundle = Bundle(path: localizationPath) else {
            XCTFail("宿主 bundle 里找不到 zh-Hans.lproj（拿不到锁语言的解析口径）", file: file, line: line)
            return
        }
        let localized = bundle.localizedString(forKey: key, value: nil, table: nil)
        XCTAssertNotEqual(localized, key, "\(key) 没解析出 zh-Hans 文案（catalog 未编进宿主 bundle？）", file: file, line: line)
        XCTAssertFalse(localized.isEmpty, "\(key) 解析为空串", file: file, line: line)
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
