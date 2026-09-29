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
