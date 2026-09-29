//
//  ModuleToggleTests.swift
//  Gourd 模块内核 · 运行期开关（P2 批次 / T2）
//
//  覆盖 docs/17-nookx-adoption.md §接口与数据形状 3 与 §状态机与流程（状态迁移表 + 并发与幂等）：
//
//  - **置开**：`states[id] == nil`（已注册未 bootstrap）与 `.disabled` 两条入口都能激活 →
//    状态 `.active`、`instance(for:) != nil`、`activate()` 恰好一次；返回的是迁移后的状态；
//  - **置开幂等**：重复置开原样返回现值，不产生第二次 `activate()`、实例不被替换
//    （计数器假模块是唯一判据——UI 节流不参与）；
//  - **置关**：`.active` → `deactivate()` + 摘实例 + `.disabled`；重复置关是空操作
//    （没有第二次 `deactivate()`）；
//  - **三投影同步**：置关后 `homeEntries` / `tabEntries` / `compactEntries` 同时不含该 id，
//    内容请求降级为 `.unavailable`（docs/17 §验收标准「首页块消失、展开 tab 消失、折叠槽位让位」）；
//  - **`failed` 是终态且不可逃逸**：`activate()` 抛错 → `.failed(reason:)` 且不留实例；再置开仍 `.failed`
//    且 `activateCount` 不增（06 §3.3 硬性规则 1：不重试）；**置关也不把它降级**（D-13：没有
//    「关一下再打开」这条复活路径），置关 / 置开对 `.failed` 都不做实例动作；
//  - **未注册 id**：置开 / 置关都返回 `.disabled`、不崩、也不凭空造状态；
//  - **`activating` 期间被置关**：在飞的 `activate()` 收尾（代次比对不匹配）不把状态写回
//    `.active`、不留实例、只对自己 `deactivate()`——「关了还在跑」的判据；
//  - **代次失效的失败收尾不碰注册表**（修复 1 的判据）：gen1 悬挂 → 置关 → 置开（新实例 B 入驻
//    `.active`）→ 放行 gen1 让它**抛错**：`instances` 里必须还是 B、状态仍 `.active`、
//    B 不得被 `deactivate()`，内容请求也不得降级 `.unavailable`；
//  - **`setEnabled` 的模块拿到注入的 collapse**：`bootstrap(collapse:)` 存下的闭包直达
//    `setEnabled` 激活的模块 context（`setEnabled` 因此不需要 collapse 形参）；
//  - **`KernelBootstrap.enablementGate`**：overrides 有键压过 manifest 的 `defaultEnabled`、
//    缺键回落 manifest 值、未注册 id 回落 false；把它喂给 `register` 时登记状态随之变化；
//  - **内核不写偏好**：`setEnabled` 不碰 `Defaults[.moduleEnableOverrides]`（写盘是设置页的事）。
//
//  偏好卫生：注册表是单例、`Defaults.Keys.moduleEnableOverrides` 落开发机真实域——
//  每个用例的 `setUp` 都先 `deactivateAll()`（它连 `manifests` / `moduleTypes` 一起清，
//  因此**用例必须自己重新 `register(...)`**，否则 `setEnabled` 直接命中「未注册」分支）
//  并清掉 overrides 键；`tearDown` 再清一次。清理一律用 `removeObject`，**不写 `[:]`**：
//  `Defaults` 的 setter 不把「写回默认值」特殊化，写空字典会在 `com.cmeng.gourd` 域里
//  留下一个存在的键（验收要求跑完 `defaults read ... moduleEnableOverrides` 报键不存在）。
//

import Defaults
import XCTest

@testable import Gourd

@MainActor
final class ModuleToggleTests: XCTestCase {

    /// 夹具 id（与 `ToggleFixture.manifest(shortID:)` 同址派生）。
    private let id = "com.cmeng.gourd.probe-toggle"
    private let defaultOnID = "com.cmeng.gourd.probe-toggle-default-on"
    private let failingID = "com.cmeng.gourd.probe-toggle-failing"
    private let slowID = "com.cmeng.gourd.probe-toggle-slow"
    private let slowFailingID = "com.cmeng.gourd.probe-toggle-slow-failing"
    private let ghostID = "com.cmeng.gourd.probe-toggle-ghost"

    // MARK: - 隔离

    override func setUp() async throws {
        try await super.setUp()
        await ModuleRegistry.shared.deactivateAll()
        clearOverrides()
        ProbeLedger.reset()
        ProbeGate.reset()
    }

    override func tearDown() async throws {
        ProbeGate.reset()
        await ModuleRegistry.shared.deactivateAll()
        clearOverrides()
        ProbeLedger.reset()
        try await super.tearDown()
    }

    /// 清掉偏好键（见文件头：不能靠写 `[:]`）。
    private func clearOverrides() {
        Defaults.reset(Defaults.Keys.moduleEnableOverrides.name)
    }

    /// 注册口径与 `ModuleKernelTests` / `HomeStripLayoutTests` 一致：
    /// 启用门是 `manifests[id]?.defaultEnabled ?? false`（06 §2.2 缺省 false）。
    private func registerProbes(_ types: [any GourdModule.Type]) {
        ModuleRegistry.shared.register(types, enabled: { ModuleRegistry.shared.manifests[$0]?.defaultEnabled ?? false })
    }

    /// 账本读取：**没记过 = 0**（`ProbeLedger` 只在第一次调用时落键，直接下标会拿到 nil）。
    private func activations(_ id: String) -> Int { ProbeLedger.activations[id] ?? 0 }
    private func deactivations(_ id: String) -> Int { ProbeLedger.deactivations[id] ?? 0 }

    // MARK: - 置开

    /// `.disabled`（manifest 默认关 → 启用门落 disabled）→ 置开 → `.active` + 实例入驻。
    func testSetEnabledTrueActivatesDisabledModule() async {
        let registry = ModuleRegistry.shared
        registerProbes([ToggleProbeModule.self])
        await registry.bootstrap()
        XCTAssertEqual(registry.states[id], .disabled, "前置：默认关的模块不实例化")
        XCTAssertNil(registry.instance(for: id))

        let state = await registry.setEnabled(true, for: id)

        XCTAssertEqual(state, .active, "置开应返回迁移后的状态")
        XCTAssertEqual(registry.states[id], .active)
        XCTAssertNotNil(registry.instance(for: id), "置开后实例应入驻")
        XCTAssertEqual(activations(id), 1)
    }

    /// 已注册但尚未 `bootstrap()` 的 id（`states[id] == nil`）也走同一条激活路径。
    func testSetEnabledTrueActivatesUndecidedModule() async {
        let registry = ModuleRegistry.shared
        registry.register([ToggleProbeModule.self], enabled: { _ in true })
        XCTAssertNil(registry.states[id], "前置：过门但未 bootstrap → 无判定结果")

        let state = await registry.setEnabled(true, for: id)

        XCTAssertEqual(state, .active)
        XCTAssertNotNil(registry.instance(for: id))
        XCTAssertEqual(activations(id), 1)
    }

    /// 幂等：重复置开不产生第二次 `activate()`，实例也不被替换。
    func testRepeatedEnableDoesNotActivateTwice() async {
        let registry = ModuleRegistry.shared
        registerProbes([ToggleProbeModule.self])
        await registry.setEnabled(true, for: id)
        let first = registry.instance(for: id)

        let again = await registry.setEnabled(true, for: id)

        XCTAssertEqual(again, .active)
        XCTAssertEqual(activations(id), 1, "幂等：activate() 只准被调用一次")
        XCTAssertTrue(registry.instance(for: id) === first, "重复置开不得换实例")
        XCTAssertEqual(deactivations(id), 0)
    }

    // MARK: - 置关

    /// `.active` → 置关：`deactivate()` 一次、实例摘除、状态 `.disabled`；重复置关是空操作。
    func testSetEnabledFalseDeactivatesAndDropsInstance() async {
        let registry = ModuleRegistry.shared
        registerProbes([ToggleProbeModule.self])
        await registry.setEnabled(true, for: id)
        XCTAssertEqual(deactivations(id), 0)

        let state = await registry.setEnabled(false, for: id)

        XCTAssertEqual(state, .disabled)
        XCTAssertEqual(registry.states[id], .disabled)
        XCTAssertNil(registry.instance(for: id), "置关必须摘掉实例")
        XCTAssertEqual(deactivations(id), 1, "置关走一次 deactivate()")

        // 幂等：实例已摘，第二次置关没有可收的尾，也不崩
        let again = await registry.setEnabled(false, for: id)
        XCTAssertEqual(again, .disabled)
        XCTAssertEqual(deactivations(id), 1, "重复置关不得再 deactivate() 一次")
    }

    /// 三投影同步（docs/17 §验收标准）：置关后首页块 / 展开 tab / 折叠槽位候选同时不含该 id，
    /// 内容请求降级为 `.unavailable`——三者读的是同一份 `states`。
    func testSetEnabledFalseRemovesModuleFromAllThreeProjections() async {
        let registry = ModuleRegistry.shared
        // 夹具声明三个 surface：.home + .expanded + .compact
        registerProbes([ToggleProbeModule.self])
        await registry.setEnabled(true, for: id)

        XCTAssertEqual(registry.homeEntries.map(\.id), [id])
        XCTAssertEqual(registry.tabEntries.map(\.id), [id])
        XCTAssertEqual(registry.compactEntries.map(\.id), [id])

        await registry.setEnabled(false, for: id)

        XCTAssertEqual(registry.states[id], .disabled)
        XCTAssertNil(registry.instance(for: id))
        XCTAssertFalse(registry.homeEntries.contains { $0.id == id }, "首页块投影应同步消失")
        XCTAssertFalse(registry.tabEntries.contains { $0.id == id }, "展开 tab 投影应同步消失")
        XCTAssertFalse(registry.compactEntries.contains { $0.id == id }, "折叠槽位候选应同步消失")
        guard case .none = registry.compactSlotContent() else {
            return XCTFail("槽位候选清空后 compactSlotContent() 应回落 .none")
        }
        guard case .unavailable = registry.content(for: id, request: ModuleRegistry.home) else {
            return XCTFail("置关后首页块请求应降级为 .unavailable")
        }
    }

    // MARK: - failed 是终态（不重试、不可逃逸）

    /// `activate()` 抛错 → `.failed`、不留实例；再置开仍 `.failed` 且不再调 `activate()`。
    func testFailedIsTerminalAndEnableDoesNotRetry() async {
        let registry = ModuleRegistry.shared
        registerProbes([ToggleFailingProbeModule.self])
        await registry.bootstrap()
        XCTAssertEqual(registry.states[failingID], .disabled, "前置：默认关")

        let first = await registry.setEnabled(true, for: failingID)

        guard case .failed = first else {
            return XCTFail("期望 .failed，实到 \(first)")
        }
        XCTAssertEqual(registry.states[failingID], first)
        XCTAssertNil(registry.instance(for: failingID), "失败的模块不留实例")
        XCTAssertEqual(activations(failingID), 1)

        let second = await registry.setEnabled(true, for: failingID)

        guard case .failed = second else {
            return XCTFail("failed 是终态：再置开仍应是 .failed，实到 \(second)")
        }
        XCTAssertEqual(activations(failingID), 1, "终态不重试：activate() 不得被第二次调用")
        XCTAssertEqual(deactivations(failingID), 1, "第二次置开是空操作，不再兜底 deactivate()")
    }

    /// **终态不可逃逸**（D-13）：置关遇到 `.failed` 原样返回、不改状态、不做实例动作——
    /// 若被写成 `.disabled`，「关一下再打开」就会真的重试，与 06 §3.3 硬性规则 1 矛盾。
    func testFailedSurvivesDisableAndCannotBeRevivedByToggle() async {
        let registry = ModuleRegistry.shared
        registerProbes([ToggleFailingProbeModule.self])
        await registry.bootstrap()

        let first = await registry.setEnabled(true, for: failingID)
        guard case .failed = first else {
            return XCTFail("前置失败：期望 .failed，实到 \(first)")
        }

        let off = await registry.setEnabled(false, for: failingID)

        guard case .failed = off else {
            return XCTFail("置关不得把 failed 降级成别的状态，实到 \(off)")
        }
        guard case .failed? = registry.states[failingID] else {
            return XCTFail("置关后 states 必须仍是 .failed，实到 \(String(describing: registry.states[failingID]))")
        }
        XCTAssertEqual(deactivations(failingID), 1, "置关对 failed 不做实例动作（这 1 次来自失败路径自己的兜底）")

        // 关一下再打开：仍是 .failed、不重试（没有复活路径）
        let revived = await registry.setEnabled(true, for: failingID)
        guard case .failed = revived else {
            return XCTFail("failed 不得被开关复活，实到 \(revived)")
        }
        XCTAssertEqual(activations(failingID), 1, "终态：activate() 全程只被调用一次")
        XCTAssertNil(registry.instance(for: failingID))
    }

    // MARK: - 未注册 id

    /// 未注册的 id：置开 / 置关都返回 `.disabled`、不崩、不凭空造状态（设置页拿到过期 id 的情形）。
    func testSetEnabledIgnoresUnregisteredModule() async {
        let registry = ModuleRegistry.shared
        XCTAssertNil(registry.manifests[ghostID])

        let enable = await registry.setEnabled(true, for: ghostID)
        let disable = await registry.setEnabled(false, for: ghostID)
        XCTAssertEqual(enable, .disabled)
        XCTAssertEqual(disable, .disabled)

        XCTAssertNil(registry.states[ghostID], "未注册的 id 不得凭空造出状态")
        XCTAssertNil(registry.instance(for: ghostID))
        XCTAssertTrue(registry.homeEntries.isEmpty)
    }

    // MARK: - activating 期间被置关（代次比对）

    /// 在飞的 `activate()` 期间置关：置关立刻落 `.disabled`（不等在飞的那个），
    /// 在飞的那个收尾比对代次失败 → 不写回 `.active`、不留实例、只对自己 `deactivate()`。
    func testDisableWhileActivatingVoidsTheInFlightResult() async {
        let registry = ModuleRegistry.shared
        registerProbes([ToggleSlowProbeModule.self])
        await registry.bootstrap()
        XCTAssertEqual(registry.states[slowID], .disabled, "前置：默认关")

        let pending = Task { await registry.setEnabled(true, for: slowID) }
        var waited = 0
        while !ProbeGate.isSuspended, waited < 1_000 {
            await Task.yield()
            waited += 1
        }
        guard ProbeGate.isSuspended else {
            ProbeGate.release?()
            XCTFail("前置失败：activate() 未悬挂住（waited \(waited)）")
            return
        }
        XCTAssertEqual(registry.states[slowID], .activating, "在飞期间的状态是 .activating（瞬时态）")

        let off = await registry.setEnabled(false, for: slowID)
        XCTAssertEqual(off, .disabled, "置关不等待在飞的 activate()")
        XCTAssertEqual(registry.states[slowID], .disabled)

        ProbeGate.release?()
        ProbeGate.release = nil

        let enableResult = await pending.value
        XCTAssertEqual(enableResult, .disabled, "结果作废后置开返回的是现值（最后一次显式意图胜出）")
        XCTAssertEqual(registry.states[slowID], .disabled, "收尾不得把状态写回 .active")
        XCTAssertNil(registry.instance(for: slowID), "作废的激活不得留实例")
        XCTAssertEqual(deactivations(slowID), 1, "作废路径必须自己 deactivate() 收尾")
    }

    /// **代次失效的那一次失败收尾，对注册表的任何写入都不许发生**（修复 1 的判据）。
    ///
    /// 交错：gen1 悬挂 → 置关（作废 gen1）→ 置开（新实例 B 入驻 `.active`）→ 放行 gen1 让它**抛错**。
    /// 若失败分支在代次比对之外摘 `instances[id]`，这里会把 B 抹掉且不调 `B.deactivate()`：
    /// `states` 停在 `.active`、`instances` 为空——内容永久降级、`setEnabled(true)` 又因「已 active」
    /// 提前返回，不自愈。断言因此钉住四件事：B 还在、状态没被改写、B 没被 deactivate、内容仍转发。
    func testStaleActivationFailureDoesNotWipeTheNewInstance() async throws {
        let registry = ModuleRegistry.shared
        registerProbes([ToggleSlowFailingProbeModule.self])
        await registry.bootstrap()
        XCTAssertEqual(registry.states[slowFailingID], .disabled, "前置：默认关")

        // gen1：悬挂在 activate() 里
        let pending = Task { await registry.setEnabled(true, for: slowFailingID) }
        var waited = 0
        while !ProbeGate.isSuspended, waited < 1_000 {
            await Task.yield()
            waited += 1
        }
        guard ProbeGate.isSuspended else {
            ProbeGate.release?()
            XCTFail("前置失败：gen1 未悬挂住（waited \(waited)）")
            return
        }

        // 置关作废 gen1 → 再置开：B 的 activate() 不再悬挂，立刻入驻 `.active`
        _ = await registry.setEnabled(false, for: slowFailingID)
        let second = await registry.setEnabled(true, for: slowFailingID)
        XCTAssertEqual(second, .active, "第二个实例 B 应成功入驻")
        let instanceB = try XCTUnwrap(registry.instance(for: slowFailingID) as? ToggleSlowFailingProbeModule)
        XCTAssertEqual(activations(slowFailingID), 2, "前置：gen1 与 B 各调了一次 activate()")

        // 放行 gen1：它以抛错收尾，但代次已失效 → 只收自己的尾
        ProbeGate.release?()
        ProbeGate.release = nil
        let staleResult = await pending.value

        XCTAssertTrue(
            registry.instance(for: slowFailingID) === instanceB,
            "代次失效的失败收尾不得摘掉后来者 B"
        )
        XCTAssertEqual(registry.states[slowFailingID], .active, "状态不得被 gen1 的失败改写为 .failed / .disabled")
        XCTAssertEqual(deactivations(slowFailingID), 1, "只准 deactivate 自己那个悬挂实例，不得碰 B")
        XCTAssertEqual(staleResult, .active, "作废的那次置开返回现值（注册表此刻的真实状态）")
        guard case .none = registry.content(for: slowFailingID, request: ModuleRegistry.home) else {
            return XCTFail("B 仍在册时内容请求应转发给它（夹具答 .none），而不是降级 .unavailable")
        }
        XCTAssertEqual(registry.homeEntries.map(\.id), [slowFailingID], "投影仍含该模块（B 是 active）")
    }

    // MARK: - collapse 闭包的来源

    /// `bootstrap(collapse:)` 存下的闭包要能直达 `setEnabled` 激活的模块 context——
    /// **`setEnabled` 因此不必再要一个 `collapse` 形参**（docs/17 §改动点设计 6）。
    func testSetEnabledActivatedModuleReceivesStoredCollapseClosure() async throws {
        let registry = ModuleRegistry.shared
        let probe = CollapseProbe()
        registerProbes([ToggleProbeModule.self])
        await registry.bootstrap(collapse: { probe.count += 1 })
        XCTAssertEqual(registry.states[id], .disabled, "前置：默认关的模块没有实例、context 尚未构造")

        await registry.setEnabled(true, for: id)

        let instance = try XCTUnwrap(registry.instance(for: id) as? ToggleProbeModule)
        instance.context.ui.requestCollapse()
        XCTAssertEqual(probe.count, 1, "bootstrap 存下的闭包应直达 setEnabled 激活的模块")

        // 再 bootstrap 一次换新闭包：setEnabled 激活的模块拿到的是**最近一次**存下的那个
        let replacement = CollapseProbe()
        await registry.deactivateAll()
        registry.register([ToggleProbeModule.self], enabled: { _ in false })
        await registry.bootstrap(collapse: { replacement.count += 1 })
        XCTAssertEqual(registry.states[id], .disabled, "门不放行 → 没有实例、context 尚未构造")

        await registry.setEnabled(true, for: id)

        let second = try XCTUnwrap(registry.instance(for: id) as? ToggleProbeModule)
        second.context.ui.requestCollapse()
        XCTAssertEqual(replacement.count, 1, "setEnabled 激活的模块应拿到最近一次 bootstrap 存下的闭包")
        XCTAssertEqual(probe.count, 1, "旧闭包不得再被调用（存的是最新的那个）")
    }

    // MARK: - KernelBootstrap.enablementGate

    /// 门的取值顺序：overrides 有键取键值（两档都能压过 manifest）、缺键回落 `manifest.defaultEnabled`、
    /// 未注册 id 回落 false。
    func testEnablementGatePrefersOverrideThenFallsBackToManifest() {
        let registry = ModuleRegistry.shared
        // 只为让 `manifests` 有表（门读 manifest，与 states 无关）
        registry.register([ToggleProbeModule.self, ToggleDefaultOnProbeModule.self], enabled: { _ in true })
        let gate = KernelBootstrap.enablementGate(registry: registry)

        // 缺键 = 用户未表达 → 回落 manifest（两档都验）
        XCTAssertFalse(gate(id), "缺键应回落 manifest.defaultEnabled = false")
        XCTAssertTrue(gate(defaultOnID), "缺键应回落 manifest.defaultEnabled = true")

        // 有键 → 压过 manifest（两个方向都不得被 manifest 反压）
        Defaults[.moduleEnableOverrides] = [id: true, defaultOnID: false]
        XCTAssertTrue(gate(id), "overrides 的 true 压过 manifest 的 false")
        XCTAssertFalse(gate(defaultOnID), "overrides 的 false 压过 manifest 的 true")

        // 只写了其中一个键：另一个仍回落 manifest（缺键语义逐键独立）
        Defaults[.moduleEnableOverrides] = [id: true]
        XCTAssertTrue(gate(id))
        XCTAssertTrue(gate(defaultOnID), "另一个键缺省时仍回落 manifest.defaultEnabled")

        XCTAssertFalse(gate(ghostID), "未注册 id 回落 false（06 §2.2 缺省）")
    }

    /// 端到端：把门喂给 `register` 时，用户显式选择立刻改变登记状态——
    /// 关掉默认开的模块 → 登记即 `.disabled`；打开默认关的模块 → 过门（状态待 `bootstrap()` 判定）。
    func testEnablementGateDrivesRegisterStates() async {
        let registry = ModuleRegistry.shared
        Defaults[.moduleEnableOverrides] = [defaultOnID: false, id: true]

        registry.register(
            [ToggleProbeModule.self, ToggleDefaultOnProbeModule.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )

        XCTAssertEqual(registry.states[defaultOnID], .disabled, "overrides 关掉默认开的模块 → 登记即 .disabled")
        XCTAssertNil(registry.states[id], "overrides 打开默认关的模块 → 过门，状态待 bootstrap() 判定")

        await registry.bootstrap()

        XCTAssertEqual(registry.states[defaultOnID], .disabled)
        XCTAssertNil(registry.instance(for: defaultOnID))
        XCTAssertEqual(registry.states[id], .active, "过门的模块照常激活")
        XCTAssertNotNil(registry.instance(for: id))
    }

    // MARK: - 内核不写偏好

    /// `setEnabled` 只改内存状态：开关一趟之后 overrides 仍是空的（写盘是设置页的责任）。
    ///
    /// 断言落在**持久域**（`persistentDomain(forName:)`，即 `defaults read com.cmeng.gourd` 看到的那份）：
    /// `Defaults.Key` 的初始化会顺手把默认值注册进**注册域**（`suite.register(defaults:)`），
    /// 因此 `object(forKey:)` 对任何已声明的键都恒非 nil——它答不出「用户有没有写过」。
    func testSetEnabledDoesNotTouchPreferences() async throws {
        let registry = ModuleRegistry.shared
        registerProbes([ToggleProbeModule.self])

        await registry.setEnabled(true, for: id)
        await registry.setEnabled(false, for: id)

        XCTAssertTrue(Defaults[.moduleEnableOverrides].isEmpty, "内核不得写 moduleEnableOverrides")
        let domain = try XCTUnwrap(Bundle.main.bundleIdentifier, "测试宿主就是 Gourd.app，bundle id 必须可解析")
        XCTAssertNil(
            UserDefaults.standard.persistentDomain(forName: domain)?[Defaults.Keys.moduleEnableOverrides.name],
            "持久域里不应留下这个键（注册域的默认值不算）"
        )
    }
}

// MARK: - 假模块（文件私有）

/// 假模块的 manifest 工厂（与 `ModuleKernelTests` / `HomeStripLayoutTests` 同一口径：字面量构造）。
private enum ToggleFixture {
    static func manifest(
        shortID: String,
        surfaces: [Surface] = [.home, .expanded, .compact],
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
            defaultPlacement: order.map { Placement(slot: .center, order: $0) },
            defaultEnabled: defaultEnabled,
            permissions: [],
            config: nil
        )
    }
}

/// `activate()` / `deactivate()` 的调用账本（计数型假模块的判据；`tearDown` 后不复用）。
@MainActor
private enum ProbeLedger {
    static var activations: [String: Int] = [:]
    static var deactivations: [String: Int] = [:]

    static func reset() {
        activations.removeAll()
        deactivations.removeAll()
    }
}

/// `ToggleSlowProbeModule` 的悬挂闸：测试侧放行后才让 `activate()` 返回。
@MainActor
private enum ProbeGate {
    static var release: (() -> Void)?
    static var isSuspended = false

    static func reset() {
        release = nil
        isSuspended = false
    }
}

/// 计数 `requestCollapse` 的探针（闭包侧观测）。
private final class CollapseProbe {
    var count = 0
}

/// 假模块基线：三个 surface 都声明、`activate()` 记一次调用、`content(for:)` 答 `.none`。
@MainActor
private class ToggleProbeModule: GourdModule {
    class var manifest: ModuleManifest {
        ToggleFixture.manifest(shortID: "probe-toggle")
    }

    let context: ModuleContext

    required init(context: ModuleContext) {
        self.context = context
    }

    func activate() async throws {
        ProbeLedger.activations[Self.manifest.id, default: 0] += 1
    }

    func deactivate() async {
        ProbeLedger.deactivations[Self.manifest.id, default: 0] += 1
    }

    func content(for request: ContentRequest) -> ModuleContent { .none }
}

/// `defaultEnabled = true`（启用门缺键时应放行的那一档）
private final class ToggleDefaultOnProbeModule: ToggleProbeModule {
    override class var manifest: ModuleManifest {
        ToggleFixture.manifest(shortID: "probe-toggle-default-on", surfaces: [.expanded], defaultEnabled: true)
    }
}

/// `activate()` 必抛错 → `.failed`（终态、不重试）；抛错前记一次调用，供「不重试」断言。
private final class ToggleFailingProbeModule: ToggleProbeModule {
    struct ActivationFailure: Error {}

    override class var manifest: ModuleManifest {
        ToggleFixture.manifest(shortID: "probe-toggle-failing", surfaces: [.home])
    }

    override func activate() async throws {
        ProbeLedger.activations[Self.manifest.id, default: 0] += 1
        throw ActivationFailure()
    }
}

/// `activate()` 悬挂到 `ProbeGate.release` 被调用为止（验证「在飞期间被置关」的代次比对）。
private final class ToggleSlowProbeModule: ToggleProbeModule {
    override class var manifest: ModuleManifest {
        ToggleFixture.manifest(shortID: "probe-toggle-slow", surfaces: [.home])
    }

    override func activate() async throws {
        ProbeLedger.activations[Self.manifest.id, default: 0] += 1
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ProbeGate.release = { continuation.resume() }
            ProbeGate.isSuspended = true
        }
    }
}

/// **只让第一次** `activate()` 悬挂、且放行后**抛错**的假模块：制造「gen1 在飞 → 新实例 B 入驻 →
/// gen1 失败收尾」这条交错（修复 1 的判据）。第二次激活不再悬挂（照常返回成功），好让 B 真的入驻。
private final class ToggleSlowFailingProbeModule: ToggleProbeModule {
    override class var manifest: ModuleManifest {
        ToggleFixture.manifest(shortID: "probe-toggle-slow-failing", surfaces: [.home])
    }

    override func activate() async throws {
        let attempt = ProbeLedger.activations[Self.manifest.id, default: 0] + 1
        ProbeLedger.activations[Self.manifest.id] = attempt
        guard attempt == 1 else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ProbeGate.release = { continuation.resume() }
            ProbeGate.isSuspended = true
        }
        throw ToggleFailingProbeModule.ActivationFailure()
    }
}
