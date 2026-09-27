//
//  ModuleContent.swift
//  Gourd 模块内核 · 渲染内容（P1 批次 / T1）
//
//  06 §3.2 的**本批子集**（docs/13-runtime-kernel.md D-06）：
//  `descriptor` 只解析/占位，不带 payload、不渲染——descriptor 渲染对应上游扩展管线，属 P4。
//

import SwiftUI

/// 模块对某次内容请求的回答。
///
/// - `.view`：仅内置模块（`kind == builtin`）可用；`kind != builtin` 的模块返回它会
///   被宿主断言失败并降级为 `.unavailable`（06 §3.2 的硬边界，宿主侧判定属 T3）；
/// - `.descriptor`：本批无关联值、不渲染（D-06，P4 加回 payload 时需同步所有已写模块
///   与 `ModuleHostView` 的 switch，见 docs/13「已知限制」9）；
/// - `.unavailable(reason:)`：优雅降级——显示占位与原因，**不算失败**；
/// - `.none`：该 surface 此刻无内容（不占位）。
public enum ModuleContent {
    case view(AnyView)
    case descriptor
    case unavailable(reason: String)
    case none
}
