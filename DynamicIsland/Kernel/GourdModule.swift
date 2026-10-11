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
//  GourdModule.swift
//  Gourd 模块内核 · 运行时协议与内容请求（P1 批次 / T1）
//
//  协议逐字沿用 docs/06-module-protocol.md §3 的**本批子集**：
//  `onEvent` 未纳入（事件总线属 P1-3，见 docs/13「明确不做」）。
//
//  P2 接管批次 / T1 增量：**接管三件套**三条钩子（`takeoverEnableKey` / `isTabVisible()` /
//  `homeBlockWidth`，docs/20-component-page.md §接口与数据形状 1）——它们是协议要求、
//  在文件末尾的扩展里给缺省实现，既有的四个内置模块因此一行不改。
//
//  P3 组件批次 / T7 增量：第四条同形钩子 `homeFormFactor`（docs/26-home-widgets-and-settings.md
//  §做法 机制六 / D-09）——首页块的形态（`.large` 主块带 / `.compact` 小组件带，缺省 `.compact`）。
//  同样「协议要求 + 扩展缺省」：音乐与镜子显式答 `.large`，其余模块一行不改。
//

import CoreGraphics
import Defaults
import Foundation

/// 06 §3 的模块协议（本批子集）。
///
/// 生命周期与硬性规则（06 §3.3）：
/// - `init(context:)` 完成依赖注入——模块不存在「未注入」的中间态（R2：不得持有全局单例）；
/// - `activate()` 幂等，重复调用直接返回；副作用（起 Task、订阅）放在这里；
/// - `deactivate()` 幂等，且必须在 1s 内返回；
/// - `content(for:)` **同步**返回，渲染路径上禁止 async（R3）。
///
/// `activate()` 抛错 → 宿主把该模块置为禁用（不是崩溃、不是重试），其余模块照常
/// （架构 §4 硬性规则 1；本批的落地见 `ModuleRegistry.bootstrap()`，T2 交付）。
@MainActor
public protocol GourdModule: AnyObject {
    /// 静态元数据。内置模块在类型上直接给值。
    static var manifest: ModuleManifest { get }

    /// 依赖注入在构造期完成。
    init(context: ModuleContext)

    /// 幂等：重复调用须直接返回。
    func activate() async throws

    /// 幂等，且必须在 1s 内返回。
    func deactivate() async

    /// **同步**返回该 surface/相位此刻的内容。
    func content(for request: ContentRequest) -> ModuleContent

    // MARK: - 接管三件套（docs/20-component-page.md §接口与数据形状 1）

    /// 本模块的**启用真源**键；缺省 nil = 非接管模块（走 `moduleEnableOverrides` +
    /// `manifest.defaultEnabled` 的既有口径）。
    ///
    /// 接管模块在这里声明**上游那个开关键本身**（`enableTimerFeature` / `showMirror` /
    /// `showStandardMediaControls`）：组合根的启用门见到它就**直接读它**，
    /// `moduleEnableOverrides` 与 `manifest.defaultEnabled` 都不再看——「模块开不开」
    /// 与「功能开不开」因此是同一个布尔量，不存在第二份状态。
    ///
    /// **三条钩子都声明为协议要求**（缺省实现见文件末尾的扩展）：经组合根持有的
    /// `any GourdModule.Type` 取用时才会走到具体模块的实现上；只写在扩展里的话，
    /// 元类型取用一律静默拿到缺省值（`nil` / `true`），接管模块的声明会被无声忽略。
    static var takeoverEnableKey: Defaults.Key<Bool>? { get }

    /// 本模块此刻是否出现在**展开面板的 tab 列表**里（缺省 `true`）。
    ///
    /// 只在「启用之外还有别的可见性条件」时才需要重写（本批唯一一例：计时器的
    /// `timerDisplayMode == .tab`）。**每次读都问一次**：`ModuleRegistry.tabEntries`
    /// 不做缓存，模块因此按**当下**状态回答，而不是注册那一刻的快照。
    static func isTabVisible() -> Bool

    /// 首页块的宽度声明（缺省 `nil` = 用宿主统一值 180/240，docs/17 D-11）。
    ///
    /// **只有接管模块需要重写**：它接住的是被接管块原本的宽度（镜子 140/160、音乐 300/420），
    /// 不是为了形状统一把老块改小。类型是内核侧的 `ModuleHomeBlockWidth`——Host 的
    /// `HomeBlockWidth` 由 `HomeStripView` 自己映射，内核不引用渲染层类型。
    static var homeBlockWidth: ModuleHomeBlockWidth? { get }

    /// 首页块的**形态**（缺省 `.compact`）：它属于主块带（`.large`）还是小组件带（`.compact`）。
    ///
    /// **只声明「我是什么」，不声明「我在哪」**：两带的摆法（主块带沿用 strip 的丢块语义、
    /// 小组件带网格换行）与高度取舍都属于宿主（docs/26 §做法 机制六 / D-09）。
    /// 形态**不由宽度反推**——宽度是布局的结果，不是块形态的原因。
    ///
    /// 与另外两条钩子同一个理由声明为**协议要求**（缺省实现见文件末尾的扩展）：经组合根持有的
    /// `any GourdModule.Type` 取用时才会走到具体模块的实现上；只写在扩展里的话，元类型取用
    /// 一律静默拿到缺省值（`.compact`），大块的声明会被无声忽略。
    static var homeFormFactor: HomeFormFactor { get }

    /// 首页块的**高度声明**（缺省 `.formFactor` = 沿用形态档高，docs/37-home-layout-v2.md D-01）。
    ///
    /// 需要按内容要高度的模块（前台应用 / 通知 / 统计 / 待办）重写它，答一个按**理想宽**
    /// 量出的固定高。宿主把它交给流（`HomeFlowLayout.Item.height`），行高 = 该行最高块——
    /// 于是「块显示多少内容」只由块自己的声明决定，不再受同一行里别的块（例如镜子）影响
    /// （2026-10-10 用户反馈：前台应用「开镜子显示得多、关了显示得少」）。
    static var homeBlockHeight: ModuleHomeBlockHeight { get }

    /// 首页块的**区**（缺省 `.flow`，docs/38-home-v5-layout.md D-01~D-03）：它进环境带
    /// （固定第一排）还是可变流。**只声明「在哪一排」**，带内顺序仍是用户的 `homeBlockOrder`。
    static var homeZone: ModuleHomeZone { get }

    /// 首页块在**它所在的那一行**里是否**吸收剩余宽度**（缺省 false，docs/38 D-04）。
    ///
    /// 一行的宽度分配（`HomeStripLayoutMath`）在「富余」档下先把各块给到 `ideal`，多余的部分
    /// 按**弹性块的 `ideal`** 等比分配——**没有弹性块时余量留在行尾**（改动前的行为）。
    ///
    /// 谁答真：前台应用（环境带的富余都归它——「cpu 那三个宽度降低，第一排大部分留给前台应用」）、
    /// 今日清单与通知（并排时按比例分富余）。**固定的块（音乐 260 / 系统读数 145）答 false**：
    /// 它们被拉宽只会变形，不会更好用。
    static var homeBlockAbsorbsSurplus: Bool { get }
}

/// 接管三件套的**缺省语义**（docs/20-component-page.md §接口与数据形状 1 逐字）：
/// 非接管模块一律「没有真源键 / 始终可见 / 用宿主统一宽度」，既有模块因此一行不改。
public extension GourdModule {
    /// 接管模块的**启用真源**：非 nil 时，本模块的启用状态由这个上游 `Defaults` 键承载——
    /// 组合根的启用门直接读它，`moduleEnableOverrides` 与 `manifest.defaultEnabled` 都不再看。
    /// 缺省 nil = 非接管模块（走既有口径）。
    static var takeoverEnableKey: Defaults.Key<Bool>? { nil }

    /// 本模块此刻是否出现在**展开面板的 tab 列表**里（缺省 true）。
    /// 只在「启用之外还有别的可见性条件」时才需要重写（本批唯一一例：计时器的
    /// `timerDisplayMode == .tab`）。**每次读都问一次**（投影不缓存）。
    static func isTabVisible() -> Bool { true }

    /// 首页块的宽度声明（缺省 nil = 用宿主统一值 180/240，`docs/17` D-11）。
    /// **只有接管模块需要重写**：它接住的是被接管块原本的宽度（镜子 140/160、音乐 300/420），
    /// 不是为了形状统一把老块改小。类型是内核侧的 `ModuleHomeBlockWidth`（Host 的
    /// `HomeBlockWidth` 由 `HomeStripView` 自己映射，内核不引用渲染层类型）。
    static var homeBlockWidth: ModuleHomeBlockWidth? { nil }

    /// 首页块的形态（缺省 `.compact` = 小组件带；`docs/26` §做法 机制六 / D-09）。
    /// **只有需要面积的大块才重写**（音乐、镜子答 `.large`）：缺省值是「一眼看得完的小组件」，
    /// 这是新增模块的常态（进度 / 统计 / 待办 / 通知 / 前台应用都不写这一条）。
    /// 与宽度钩子同一条理由进协议要求而不是只放扩展里：元类型取用走的是具体模块的实现。
    static var homeFormFactor: HomeFormFactor { .compact }

    /// 首页块的高度声明（缺省 `.formFactor` = 沿用形态档高：`.large` 140 / `.compact` 96）。
    /// **不申报的模块行为逐字不变**；按内容要高度的四块（前台应用 / 通知 / 统计 / 待办）
    /// 答 `.points(...)`，取值口径见各自模块与 docs/37 §接口与数据形状。
    static var homeBlockHeight: ModuleHomeBlockHeight { .formFactor }

    /// 首页块的区（缺省 `.flow` = 可变流，docs/38 §接口）。**只有环境带那三块重写它**
    /// （音乐 / 前台应用 / 统计答 `.environment`）；新增模块什么都不用声明。
    /// 与另外几条钩子同一条理由进协议要求而不是只放扩展里：元类型取用走的是具体模块的实现。
    static var homeZone: ModuleHomeZone { .flow }

    /// 首页块是否吸收所在行的剩余宽度（缺省 false = 余量留在行尾，docs/38 D-04）。
    /// **只有「宽一点更好用」的块重写它**（前台应用 / 今日清单 / 通知）。
    static var homeBlockAbsorbsSurplus: Bool { false }
}

/// 06 §3.1 的内容请求（本批去掉事件相关字段——事件总线属 P1-3）。
public struct ContentRequest: Sendable {
    public let surface: Surface
    public let phase: NotchPhase
    /// 仅 `surface == .compact` 时非 nil（06 §3.1）。
    public let slot: Slot?
    /// 宿主可提供的目标尺寸（模块可忽略）。
    public let sizeHint: CGSize
    public let reason: ContentRequestReason
    /// 低功耗模式（架构 §7 要求动画可关）。本批宿主的 `UIHandle.isLowPower` 恒 false。
    public let isLowPower: Bool

    public init(
        surface: Surface,
        phase: NotchPhase,
        slot: Slot? = nil,
        sizeHint: CGSize = .zero,
        reason: ContentRequestReason,
        isLowPower: Bool = false
    ) {
        self.surface = surface
        self.phase = phase
        self.slot = slot
        self.sizeHint = sizeHint
        self.reason = reason
        self.isLowPower = isLowPower
    }
}
