// Modified for Gourd (2026-09-30)
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
//  ModuleRegistry.swift
//  Gourd 模块内核 · 注册表与生命周期（P1 批次 / T2）
//
//  形态仿写上游既有的同构先例 `managers/Extensions/ExtensionNotchExperienceManager.swift`
//  （`@Published` 投影 + 按 id 查找内容 + 启用门 + 优先级排序）：D-03 定为**仿写形态、不继承**——
//  那套是扩展通道的线协议身份（B 表冻结项），混用会把两条生命周期绑在一起。
//
//  06 §3.3 的硬性规则落点：单个模块 `activate()` 抛错**只把自己置为失败**（不崩、不重试），
//  其余模块照常激活——P1 验收 A6 / docs/13 失败信号「抛错模块不得让 bootstrap() 提前返回」。
//
//  P2 接管批次 / T1 增量（docs/20-component-page.md §做法 机制一 / §接口与数据形状 2）：
//  两个**接管查询**（`takeoverEnableKey(for:)` / `homeBlockWidth(for:)`，都读 `moduleTypes`）
//  与 `tabEntries` 过滤条件里的 `isTabVisible()`。三者一律**每次读现问一次、不缓存**。
//
//  P3 组件批次 / T7 增量：第三条同形查询 `homeFormFactor(for:)`（docs/26 §做法 机制六 / D-09）
//  ——首页块属于主块带还是小组件带，宿主按它切两条带。同样不缓存。
//

import Combine
import Defaults
import Foundation
import SwiftUI
import os

// MARK: - 运行时状态与 tab 投影

/// 模块的运行时状态（06 §4 状态机的**本批子集**）。
///
/// 与 06 §4 相比缺 `degraded` 与运行期超时计数（docs/13「已知限制」11）：本批的失败隔离
/// 只覆盖 `activate()` 抛错。
public enum ModuleRuntimeState: Equatable {
    /// 已注册但未启用（`defaultEnabled == false`）：不实例化、不激活、不进 tab。
    case disabled
    /// `activate()` 执行中。在 `@Published` 投影里只于切换的一瞬间可见。
    case activating
    /// 已激活：`content(for:)` 转发给它；`surfaces` 含 `.expanded` 时进 tab 列表。
    case active
    /// `activate()` 抛错——**终态**，模块被禁用、不重试（06 §3.3 硬性规则 1）。
    case failed(reason: String)
}

/// 展开面板的一个 tab 条目（模块清单在 UI 上的投影；06 §3.2）。
public struct ModuleTabEntry: Identifiable, Equatable {
    /// 模块 id（`com.cmeng.gourd.<shortID>`）。
    public let id: String
    /// 已本地化标题（解析顺序见 `ModuleRegistry.label(for:)`）。
    public let label: String
    /// SF Symbol 名（生产路径不调 `validate()`，本批未校验符号可解析性，见 docs/13「已知限制」17）。
    public let symbolName: String
    /// `defaultPlacement.order`，无 placement 时 `Int.max`（排在最后）。
    public let order: Int
}

/// 首页 strip 的一个块条目（模块清单在「展开面板首页」上的投影；docs/17 §接口与数据形状 2）。
///
/// 与 `ModuleTabEntry` 同形不同语义：tab 条目属于展开面板的 tab 列表，本条目属于首页那一条
/// 横向 strip。两者都复用 `defaultPlacement.order` 作为排序键（D-04），但**各自独立投影**——
/// 声明 `home` 不意味着有 tab，反之亦然。
public struct ModuleHomeEntry: Identifiable, Equatable {
    /// 模块 id（`com.cmeng.gourd.<shortID>`）。
    public let id: String
    /// 已本地化标题（解析顺序见 `ModuleRegistry.label(for:)`，与 tab 条目同一份）。
    public let label: String
    /// SF Symbol 名（生产路径不调 `validate()`，本批未校验符号可解析性，见 docs/13「已知限制」17）。
    public let symbolName: String
    /// `defaultPlacement.order`，无 placement 时 `Int.max`（排在最后）。
    public let order: Int
}

/// 一条**瞬时浮层**（09 §5.5 呈现 ①：新事件到达时在折叠态刘海上短暂展示）。
///
/// 与 `ModuleCompactSlotView` / `ModuleHostView` 的关系：那两处渲染的是**常驻内容**
/// （模块答什么就显示什么，由模块自己的状态驱动）；浮层是**宿主托管的短命条目**——
/// 谁先请求谁显示、到期自动消失，模块不持有它的生命周期。
///
/// `id` 与模块 id 无关：它是「这一次弹出」的身份，`presentHUD` 的到期任务据此判断
/// 「我这条还在不在台前」（见 `presentHUD` 的只清自己那一条）。
public struct ModuleHUD: Identifiable {
    public let id: UUID
    public let moduleID: String
    public let view: AnyView
    /// 到期时刻（由 `presentHUD` 按夹取后的 ttl 算好，日志与测试读它）。
    public let expiresAt: Date
}

// MARK: - ModuleRegistry

/// 模块注册表：注册 → 启用门 → 激活 → 内容转发 → UI 投影。
///
/// 单例（`shared`）：06 §3.3 R2 要求模块不持全局单例，全局状态收在宿主这一层。
/// 生命周期由组合根 `KernelBootstrap` 驱动（注册 + `bootstrap()`）。
@MainActor
public final class ModuleRegistry: ObservableObject {
    public static let shared = ModuleRegistry()

    /// 每个模块的运行状态。**注册了但尚未 `bootstrap()` 的启用模块不在这里**——
    /// 状态只记「已判定」的结果（active / failed / disabled），判定由 `bootstrap()` 落。
    @Published public private(set) var states: [String: ModuleRuntimeState] = [:]
    /// 注册表：id → manifest。同 id 只留先注册者（06 §10.1 第 14 步的全局 id 唯一）。
    public private(set) var manifests: [String: ModuleManifest] = [:]

    /// 当前正在展示的瞬时浮层；nil = 无（关闭态自然回落到 live activity 链的其它分支）。
    @Published public private(set) var activeHUD: ModuleHUD?

    /// 浮层 ttl 的夹取区间（秒）。**下界 1s**：低于它的浮层肉眼看不见（等于没弹）；
    /// **上界 15s**：09 §5.5 的浮层是「瞬时」的，不能变成常驻占位（那会让关闭态
    /// 永久让位给一条通知）。模块传什么都会落在这个区间内。
    public static let hudTTLRange: ClosedRange<TimeInterval> = 1...15

    /// 已激活的实例。只在 `activate()` 成功后入驻，失败即摘除。
    private var instances: [String: any GourdModule] = [:]
    /// id → 类型。`manifests` 只够判启用与排序，实例化还需要元类型。
    private var moduleTypes: [String: any GourdModule.Type] = [:]
    /// 应用侧注入的「收起刘海」闭包（`bootstrap(collapse:)` 第一步落进来）。
    /// 初值 `{}`：`setEnabled` 与「从未 `bootstrap()` 过」的路径拿到的都是空操作闭包。
    private var collapseHandler: () -> Void = {}
    /// 代次取号器：**全局单调**自增（跨 id、跨 `deactivateAll()` 都不回退），只增不减。
    private var activationGenerationCounter = 0
    /// id → 该 id 当前有效的激活代次令牌。进入 `activateIfNeeded` 领新号；`setEnabled(false)` 也领新号
    /// （作废在飞的结果）。用途只有一个：`activate()` 悬挂期间被置关时，**结果不写回任何注册表状态**
    ///（docs/17 §状态机与流程）。**只当相等性令牌用，不要当计数器读**——每次激活与每次置关都会领号。
    private var activationGeneration: [String: Int] = [:]
    private let log = os.Logger(subsystem: "com.cmeng.gourd.kernel", category: "registry")

    private init() {}

    /// 领一个新代次令牌（全局单调取号）。
    ///
    /// 为什么不是「每 id 从 0 复起的计数器」：`deactivateAll()` 清空 `activationGeneration` 后，
    /// 同一个 id 重新注册会拿到与**在飞任务**相同的号（ABA），作废机制随之静默失效。
    /// 全局单调取号让任何一次作废都不可逆——没有号会被第二次发出。
    private func nextGeneration() -> Int {
        activationGenerationCounter += 1
        return activationGenerationCounter
    }

    // MARK: - 注册

    /// 注册模块类型。**幂等**：同 id 重复注册记 warning 并忽略（不覆盖先注册者）。
    ///
    /// `enabled` 是组合根注入的启用门（`KernelBootstrap` 传
    /// `manifests[$0]?.defaultEnabled ?? false`——06 §2.2 的 `defaultEnabled` 缺省 `false`）。
    /// 因此判启用时**该模块的 manifest 必须已在表内**：本方法先落全部 manifest，再逐个过门；
    /// 未过门的落 `.disabled`，过门的**不写状态**（首个终态由 `bootstrap()` 落）。
    public func register(_ types: [any GourdModule.Type], enabled: @escaping (String) -> Bool) {
        var accepted: [ModuleManifest] = []
        for type in types {
            let manifest = type.manifest
            guard manifests[manifest.id] == nil else {
                log.warning("忽略重复注册的模块 \(manifest.id, privacy: .public)")
                continue
            }
            manifests[manifest.id] = manifest
            moduleTypes[manifest.id] = type
            accepted.append(manifest)
        }
        for manifest in accepted where !enabled(manifest.id) {
            states[manifest.id] = .disabled
        }
    }

    // MARK: - 生命周期

    /// 逐个实例化并 `activate()`。
    ///
    /// **跳过规则**：`states` 里已有判定结果的 id 一律跳过——`active` 跳过（不重复激活）、
    /// `disabled` 跳过（不实例化）、`failed` 跳过（**不重试**）。因此本方法幂等，
    /// 可在启动流程里安全重复调用。
    ///
    /// 单个模块抛错只把自己置 `.failed(reason:)` 并继续下一个（06 §3.3 硬性规则 1）。
    /// 迭代顺序按 id 升序（稳定，便于复现「失败模块之后的兄弟模块仍被激活」）。
    ///
    /// `collapse` 是应用侧注入的「收起刘海」闭包（`UIHandle.requestCollapse()` 的唯一出口），
    /// 注册表只把它转交给每个模块的 context——**透传、不改写、不做裁决**（docs/13 D-28）。
    /// 默认 `{}` 让既有调用点（单测、未接线的启动路径）保持原语义：请求了也什么都不发生。
    /// 收到后存在 `collapseHandler`：`setEnabled` 因此不必再要一个 `collapse` 形参
    ///（docs/17 §改动点设计 6）。
    public func bootstrap(collapse: @escaping () -> Void = {}) async {
        collapseHandler = collapse
        for manifest in manifests.values.sorted(by: { $0.id < $1.id }) {
            // 跳过规则（见上）：已有判定结果的 id 不进激活路径。
            guard states[manifest.id] == nil else { continue }
            _ = await activateIfNeeded(manifest.id)
        }
    }

    /// 实例化 + `activate()` 的**唯一路径**（`bootstrap()` 与 `setEnabled(_:for:)` 共用）。
    ///
    /// **跳过规则由调用方负责**：`bootstrap()` 只把「尚无判定结果」的 id 送进来，
    /// `setEnabled(true)` 只把 `.disabled`（或尚无结果）的 id 送进来——两条路径的前置判定不同，
    /// 放在这里会让 `setEnabled(true)` 被 `states[id] == nil` 的守卫挡回。本方法自身只要求
    /// 「id 已注册」（有 manifest 与元类型），因此对 id 的作用是**无条件激活一次**。
    ///
    /// 单模块失败只把自己置 `.failed(reason:)` 并继续（06 §3.3 硬性规则 1）；日志文案与
    /// `bootstrap()` 抽取前逐字一致。
    ///
    /// **代次（generation）**：进入时领一个新代次并记下，**每次写回注册表状态前比对**——
    /// `activate()` 悬挂期间被 `setEnabled(false)` 干预过（代次不匹配）时结果一律作废：
    /// **收尾时对注册表（`instances` / `states`）的任何写入都不许发生**，只对自己那个悬挂实例
    /// `deactivate()`（它可能已经不属于注册表：期间置关 + 置开会让后来者入驻），
    /// 返回值是当时已落定的状态（docs/17 §状态机与流程「并发与幂等」）。
    private func activateIfNeeded(_ id: String) async -> ModuleRuntimeState {
        guard let type = moduleTypes[id], let manifest = manifests[id] else {
            return states[id] ?? .disabled
        }
        let generation = nextGeneration()
        activationGeneration[id] = generation

        states[id] = .activating
        let instance = type.init(context: ModuleContextFactory.make(
            manifest: manifest,
            // requestRedraw 的路由：注册表是模块与 UI 之间唯一的可观测点，
            // T3 的 ModuleHostView 观察注册表即可被模块的重绘请求驱动。
            redraw: { [weak self] in
                guard let self else { return }
                self.objectWillChange.send()
            },
            // requestCollapse 的路由：注册表没有窗口能力，也不该有——原样交给应用侧。
            collapse: collapseHandler
        ))

        do {
            try await instance.activate()
            guard activationGeneration[id] == generation else {
                // 期间被 setEnabled(false) 干预过：状态已由它落定，本次结果作废、只收自己的尾。
                await instance.deactivate()
                log.info("模块 \(id, privacy: .public) 的 activate() 已完成但已被 setEnabled(false) 作废，不写回状态")
                return states[id] ?? .disabled
            }
            instances[id] = instance
            states[id] = .active
        } catch {
            // 半激活的实例不留：先摘出注册表，再兜底 deactivate 清理它已起的副作用。
            // **摘除与置失败都必须在代次有效时**：代次失效意味着 `instances[id]` 此刻可能已经是
            // 后来者的实例（置关 → 置开），抹掉它会让 `states == .active` 而 `instances` 为空——
            // 内容永久降级、`setEnabled(true)` 又因「已 active」提前返回，不自愈。
            if activationGeneration[id] == generation {
                instances[id] = nil
                states[id] = .failed(reason: String(describing: error))
            } else {
                log.info("模块 \(id, privacy: .public) 的 activate() 失败结果已被 setEnabled(false) 作废，不写回状态")
            }
            await instance.deactivate()
            log.error("模块 \(id, privacy: .public) activate() 抛错：\(String(describing: error), privacy: .public)")
        }
        return states[id] ?? .disabled
    }

    /// 运行期开关：置开按 `bootstrap()` 的同一条路径激活，置关 `deactivate()` 后摘除实例。
    ///
    /// - **未注册的 id**（`manifests[id] == nil`）：记 warning 并返回 `.disabled`——不崩、
    ///   也不凭空造状态（设置页拿到了过期的 id 时是这样）。
    /// - **置开**：`.active` / `.activating` / `.failed` **原样返回**（幂等：不重复实例化；
    ///   `failed` 是终态**不重试**，06 §3.3 硬性规则 1）；`states[id] == nil` 或 `.disabled`
    ///   才真的走 `activateIfNeeded`。返回时通常是 `.active` / `.failed`；并发下可能拿到
    ///   `.activating`（在飞），调用方按「进行中」处理即可，不需要自旋等待。
    /// - **置关**：`.active` → `deactivate()` + 摘实例 + 落 `.disabled`；`nil` / 已 `.disabled`
    ///   → 落 `.disabled`（幂等）。**`.failed` 原样返回、不改状态、不做实例动作**——它是终态
    ///   （06 §3.3 硬性规则 1 / D-13），置关**不会**把它降级成 `.disabled`，因此也没有
    ///   「关一下再打开」这条复活路径（等价于「要恢复只能重启应用」）。`.activating` 的收尾
    ///   由代次比对拦下（它不写回任何状态）。
    /// - **只改内存状态，不写偏好**：`Defaults[.moduleEnableOverrides]` 由设置页负责落盘，
    ///   内核不知道「用户偏好」这一层（D-05 / docs/17 §改动点设计 5+6）。
    /// - 每次调用记一条 `os.Logger`（`setEnabled(id:on:from:to:)`），便于排查「关了还在跑」。
    @discardableResult
    public func setEnabled(_ enabled: Bool, for id: String) async -> ModuleRuntimeState {
        guard manifests[id] != nil else {
            log.warning("setEnabled 忽略未注册的模块 \(id, privacy: .public)（on: \(enabled, privacy: .public)）")
            return .disabled
        }

        let from = states[id]
        let to: ModuleRuntimeState
        if enabled {
            if let current = from, current != .disabled {
                // 幂等 / 终态：不重复实例化、不重试，原样返回现值。
                to = current
            } else {
                to = await activateIfNeeded(id)
            }
        } else if let current = from, case .failed = current {
            // **终态不可逃逸**（D-13）：置关不改写 `.failed`、不碰实例。写成 `disabled` 会让
            // 下一次置开真的重试，与 06 §3.3 硬性规则 1「`failed` 不重试」矛盾。
            to = current
        } else {
            if from == .active {
                await instances[id]?.deactivate()
                instances[id] = nil
            }
            // 代次换新号：任何在飞的 `activate()` 结果就此作废（它比对的是换号前的那个值）。
            activationGeneration[id] = nextGeneration()
            states[id] = .disabled
            to = .disabled
        }

        log.info("setEnabled(id: \(id, privacy: .public), on: \(enabled, privacy: .public), from: \(String(describing: from), privacy: .public), to: \(String(describing: to), privacy: .public))")
        return to
    }

    /// 停用全部模块并**清空注册表**（instances / states / manifests / moduleTypes）。
    ///
    /// 语义是「组合根的对称收尾」：应用退出或内核重置时调用。单测也用它做用例间隔离——
    /// 注册表是单例，`manifests` / `states` 不清会互相污染。
    public func deactivateAll() async {
        for id in instances.keys.sorted() {
            await instances[id]?.deactivate()
        }
        instances.removeAll()
        states.removeAll()
        manifests.removeAll()
        moduleTypes.removeAll()
        // 代次一并清：清空后任何在飞的 `activate()` 结果都作废（比对到 nil 即不匹配）。
        // 取号器**不回退**（全局单调），因此同一 id 重新注册也拿不到旧号（无 ABA）。
        activationGeneration.removeAll()
        // 浮层属于「某个模块的一次弹出」：注册表清空后它没有归属，必须一并撤掉
        //（否则单测之间会串味，退出路径上也会留下一帧孤儿视图）。
        clearHUD()
    }

    /// 已激活的模块实例；未注册 / 未启用 / 已失败 / 尚未 `bootstrap()` → nil。
    public func instance(for id: String) -> (any GourdModule)? {
        instances[id]
    }

    // MARK: - 接管查询（docs/20 §接口与数据形状 2）

    /// 该模块的**启用真源**键（docs/20 §做法 机制一）：非 nil = 接管模块，组合根的启用门
    /// 直接读它；nil = 未注册 / 非接管模块。
    ///
    /// 读 `moduleTypes`（不是 `manifests`）：钩子挂在**类型**上（`GourdModule` 的静态要求），
    /// manifest 里没有这一列。**每次读现问一次**（不缓存，同三条投影的口径）。
    public func takeoverEnableKey(for id: String) -> Defaults.Key<Bool>? {
        moduleTypes[id]?.takeoverEnableKey
    }

    /// 该模块声明的**首页块宽度**（docs/20 §做法 机制一「块宽继承」）：nil = 用宿主统一值
    /// 180/240（`HomeStripLayoutMath` 的 `moduleBlockWidth`）。同样是每次读现问一次。
    public func homeBlockWidth(for id: String) -> ModuleHomeBlockWidth? {
        moduleTypes[id]?.homeBlockWidth
    }

    /// 该模块声明的**首页块形态**（docs/26 §做法 机制六 / D-09）：`.large` = 主块带、
    /// `.compact` = 小组件带。**未注册的 id 一律答缺省 `.compact`**（钩子的缺省值，与
    /// `homeBlockWidth(for:)` 答 nil 的形态对齐：宿主拿到的都是「这个 id 的形态」这一个答案）。
    /// 同样是每次读现问一次（不缓存，与三条投影同一口径）。
    public func homeFormFactor(for id: String) -> HomeFormFactor {
        moduleTypes[id]?.homeFormFactor ?? .compact
    }

    // MARK: - UI 投影

    /// 展开面板的 tab 列表：仅 `active` 且 `surfaces` 含 `.expanded`，
    /// 按 `order` 升序、同 `order` 按 id 字典序（`order` 缺省 = `Int.max`，排最后）。
    ///
    /// **可见性钩子**（docs/20 §做法 机制一）：过滤条件里还有 `isTabVisible()`（缺省 true）——
    /// 「启用」不总是等价于「tab 出不出来」（计时器还要求 `timerDisplayMode == .tab`）。
    /// 与另外两条投影一样**每次读都现问一次**（不缓存），模块因此按当下状态回答。
    /// 比较器与排序**不动**（order → id 字典序）。
    public var tabEntries: [ModuleTabEntry] {
        manifests.values
            .filter {
                states[$0.id] == .active
                    && $0.surfaces.contains(.expanded)
                    && (moduleTypes[$0.id]?.isTabVisible() ?? true)
            }
            .map { manifest in
                ModuleTabEntry(
                    id: manifest.id,
                    label: Self.label(for: manifest),
                    symbolName: manifest.icon.name ?? "",
                    order: manifest.defaultPlacement?.order ?? Int.max
                )
            }
            .sorted { ($0.order, $0.id) < ($1.order, $1.id) }
    }

    /// 折叠态中央槽位的候选：`active` 且 `surfaces` 含 `.compact`，
    /// 按 `order` 升序、同 `order` 按 id 字典序（与 `tabEntries` 同一比较器）。
    ///
    /// 本批**只有中央槽位**：06 §6.2 的三槽布局（`slot` 的 left/right 与每侧上限）
    /// 仍需重构关闭态的 HStack，仍推 P2（docs/13「明确不做」）。
    public var compactEntries: [ModuleTabEntry] {
        manifests.values
            .filter { states[$0.id] == .active && $0.surfaces.contains(.compact) }
            .map { manifest in
                ModuleTabEntry(
                    id: manifest.id,
                    label: Self.label(for: manifest),
                    symbolName: manifest.icon.name ?? "",
                    order: manifest.defaultPlacement?.order ?? Int.max
                )
            }
            .sorted { ($0.order, $0.id) < ($1.order, $1.id) }
    }

    /// 首页 strip 的块列表：`active` 且 `surfaces` 含 `.home`，
    /// 按 `order` 升序、同 `order` 按 id 字典序（与 `tabEntries` / `compactEntries` 同一比较器）。
    ///
    /// 与另两条投影一样**不做缓存**：每次读都现算（`manifests` / `states` 都是 `@Published`
    /// 的派生量，缓存会让「注册后 / 激活后 / 停用后」三个时刻的视图不一致）。
    ///
    /// 宿主侧（T3）对返回的条目还要再过滤一次「本次 `content(for:request:.home)` 答 `.none`」的
    /// 条目——投影层不做这件事：投影是**声明**（manifest 说愿意在首页占一块），
    /// 内容是**表态**（这一刻有没有东西可画），两者分开才不会让一次 `.none` 影响后续刷新。
    public var homeEntries: [ModuleHomeEntry] {
        manifests.values
            .filter { states[$0.id] == .active && $0.surfaces.contains(.home) }
            .map { manifest in
                ModuleHomeEntry(
                    id: manifest.id,
                    label: Self.label(for: manifest),
                    symbolName: manifest.icon.name ?? "",
                    order: manifest.defaultPlacement?.order ?? Int.max
                )
            }
            .sorted { ($0.order, $0.id) < ($1.order, $1.id) }
    }

    /// 折叠态中央槽位的内容：取 `compactEntries` 的**第一个**转发；无候选、或模块答 `.none` → `.none`
    ///（不占位，关闭态自然回落到人脸动画 / 空矩形等既有分支）。
    ///
    /// 请求按 06 §3.1 填成「compact + 折叠 + 中央槽位」：`sizeHint` 用 `.zero`（槽位不做尺寸协商，
    /// 模块自报高度属 P2）、`reason` 用 `.initial`（宿主尚未记录「第几次评估」，与 `ModuleHostView` 同一口径）。
    public func compactSlotContent() -> ModuleContent {
        guard let entry = compactEntries.first else { return .none }
        return content(for: entry.id, request: Self.compactSlotRequest)
    }

    /// 折叠态中央槽位的定值请求（`compactSlotContent()` 的唯一生产点）。
    private static let compactSlotRequest = ContentRequest(
        surface: .compact,
        phase: .collapsed,
        slot: .center,
        sizeHint: .zero,
        reason: .initial,
        isLowPower: false
    )

    /// 首页 strip 的块请求（宿主渲染首页块时用，docs/17 §接口与数据形状 2）。
    ///
    /// **宽度不由请求传递**：`sizeHint` 是 `.zero`，块拿到的是 SwiftUI 的提案宽度——
    /// 分配由 `HomeStripLayoutMath.plan` 在布局层算完（富余不拉伸、不足按最小宽度收敛）。
    /// `slot` 为 nil：首页没有槽位语义（`Slot` 只在 `surface == .compact` 时有意义）。
    /// 与 `compactSlotRequest` 同档——定值、静态、无实例状态；`ContentRequest` 的字段一个不加。
    public static let home: ContentRequest = ContentRequest(
        surface: .home,
        phase: .expanded,
        slot: nil,
        sizeHint: .zero,
        reason: .initial,
        isLowPower: false
    )

    /// tab 标题的解析顺序：Localizable key 形态 → locale 表（`en`）→ `shortID`。
    ///
    /// key 拿不到译文时 `Bundle.localizedString(forKey:value:table:)` **原样返回 key**，
    /// 借此判「解析不到」——T4 把 `module.<shortID>.name` 写进 `Localizable.xcstrings` 后
    /// 这里自然切到本地化文案，无需改代码。
    static func label(for manifest: ModuleManifest) -> String {
        if let key = manifest.name.key, !key.isEmpty {
            let localized = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
            if !localized.isEmpty, localized != key { return localized }
        }
        if let english = manifest.name.table?["en"], !english.isEmpty { return english }
        return manifest.shortID
    }

    // MARK: - 内容转发

    /// 把内容请求转给已激活的模块。**未知 id / 未激活（disabled / failed / 尚未 bootstrap）
    /// 一律返回 `.unavailable`**——不崩、也不返回空内容，渲染侧据此显示占位与原因（06 §3.2）。
    ///
    /// `.view` 仅限内置模块的硬边界判定（06 §3.2）**属 P4**：本批只有 `kind == builtin`
    /// 的内置模块（`register()` 不校验 manifest，见 docs/13「已知限制」17），插件越权边界
    /// 随 `PluginModuleAdapter` 一起实现；本批注册表只做「是否激活」的裁剪。
    public func content(for id: String, request: ContentRequest) -> ModuleContent {
        guard let instance = instances[id], states[id] == .active else {
            let reason = manifests[id] == nil ? "模块未注册：\(id)" : "模块未激活：\(id)"
            log.warning("content 请求降级：\(reason, privacy: .public)")
            return .unavailable(reason: reason)
        }
        return instance.content(for: request)
    }

    // MARK: - 瞬时浮层（HUD）

    /// 弹出瞬时浮层（模块侧入口是 `UIHandle.presentTransient`）。
    ///
    /// **覆盖语义**：已有浮层直接被新的一条替换——不排队、不叠加。理由：刘海关闭态只有
    /// 一格位置（见 `ContentView` 关闭态优先级链的插入注释），两条浮层同时到达时「后到者
    /// 就是最新事件」，排队只会让先到的那条在过期后突然冒出来。
    ///
    /// `ttl` 一律夹取到 `hudTTLRange`（1…15s）：模块给 0.2s 等于没弹，给 600s 等于常驻。
    ///
    /// 到期清除**只清自己那一条**：任务醒来时先比对 `activeHUD?.id`，被后来者替换过就直接返回——
    /// 否则「先弹 A（短 ttl）、再弹 B（长 ttl）」会让 A 的旧任务把 B 提前清掉。
    public func presentHUD(moduleID: String, view: AnyView, ttl: TimeInterval) {
        let clamped = min(max(ttl, Self.hudTTLRange.lowerBound), Self.hudTTLRange.upperBound)
        let hud = ModuleHUD(id: UUID(), moduleID: moduleID, view: view, expiresAt: Date().addingTimeInterval(clamped))
        activeHUD = hud
        log.info("presentHUD：模块 \(moduleID, privacy: .public)，ttl \(clamped, privacy: .public)s")

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(clamped))
            guard let self, self.activeHUD?.id == hud.id else { return }
            self.clearHUD()
        }
    }

    /// 撤掉当前浮层（用户侧无入口；到期任务、模块显式收尾与 `deactivateAll()` 走这里）。
    ///
    /// 语义是**幂等**的：没有浮层时是空操作（到期任务的 `guard` 之后可能重复到达）。
    public func clearHUD() {
        guard activeHUD != nil else { return }
        activeHUD = nil
    }

    /// 撤掉**指定的那一条**浮层（模块侧入口是 `UIHandle.dismissTransient()`；模块点掉浮层的 × 后
    /// 走它让位给下层内容，而不是等 ttl 到点——否则关闭后关闭态那一格仍被浮层分支占着）。
    ///
    /// 与 `clearHUD()` 的分工：`clearHUD()` 是宿主侧的**无条件**收尾（到期任务 / `deactivateAll()`），
    /// 本方法带 `id` 判据——模块点 × 的那一刻台前可能已经**被后来者替换**（通知连发 /
    /// 另一个模块抢先），那种情况必须让后来者继续显示，撤掉它不是本模块该做的事。
    ///
    /// **幂等**：`id` 不等于当前浮层（已被替换 / 已到期 / 本来就没有）时是空操作。
    public func dismissHUD(id: UUID) {
        guard let current = activeHUD, current.id == id else { return }
        activeHUD = nil
        log.info("dismissHUD：模块 \(current.moduleID, privacy: .public) 主动撤掉浮层，让位给下层内容")
    }
}
