//
//  ModuleTypes.swift
//  Gourd 模块内核 · 类型层（P1 批次 / T1）
//
//  取值词汇表逐字沿用 docs/06-module-protocol.md（§3.1 / §6.1 / §6.2）；
//  本文件不含任何行为，只有共享的枚举。
//

import Foundation

/// 06 §6.1 的三个 surface：模块内容可以出现在哪里。
///
/// | 取值 | 语义 | 承载 |
/// |---|---|---|
/// | `compact` | 折叠态 | 槽位（`Slot`） |
/// | `expanded` | 展开面板 | 展开区的 tab |
/// | `lockscreen` | 锁屏小组件 | 锁屏 widget |
///
/// 不新增 `hud` 之类的 surface——瞬时浮层是 `expanded` 的一种呈现方式（06 §6.1），
/// 本批不声明 `lockscreen`（D-12，ADR-0011 第 4 条「锁屏维持现状」）。
public enum Surface: String, Codable, Sendable, CaseIterable {
    case compact
    case expanded
    case lockscreen
}

/// 06 §6.2 的槽位模型：仅在 `surface == .compact` 时有意义。
public enum Slot: String, Codable, Sendable, CaseIterable {
    case left
    case right
    case center
}

/// 06 §3.1 的四态。
///
/// **本批（D-04「包装 / 观测」路线）只有 `collapsed` / `expanded` 可达**：
/// - `hoverPreview` 需要把上游 `ContentView.isHovering`（`@State private`，类外不可观测）
///   提升为可观测量；
/// - `dragging` 需要内核订阅拖拽布尔量（`dragDetectorTargeting` / `anyDropZoneTargeting`）；
///
/// 两者都属 P1-2 的 `NotchStateMachine`（见 docs/13-runtime-kernel.md「已知限制」5）。
/// 本批先把四态定死，避免 P1-2 改协议。
public enum NotchPhase: String, Codable, Sendable, CaseIterable {
    case collapsed
    case hoverPreview
    case expanded
    case dragging
}

/// 06 §3.1：这一次 `content(for:)` 是被什么触发的。
/// 本批只有 `initial` / `redraw` 会被真实产生（`event` / `tick` / `configChanged`
/// 依赖 P1-3 的事件总线与配置存储）。
public enum ContentRequestReason: String, Codable, Sendable {
    case initial
    case event
    case configChanged
    case tick
    case redraw
}
