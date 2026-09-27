//
//  GourdModule.swift
//  Gourd 模块内核 · 运行时协议与内容请求（P1 批次 / T1）
//
//  协议逐字沿用 docs/06-module-protocol.md §3 的**本批子集**：
//  `onEvent` 未纳入（事件总线属 P1-3，见 docs/13「明确不做」）。
//

import CoreGraphics
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
