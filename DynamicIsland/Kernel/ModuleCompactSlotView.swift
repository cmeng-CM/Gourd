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
//  ModuleCompactSlotView.swift
//  Gourd 模块内核 · 折叠态中央槽位视图（P2 形态重做）
//
//  接缝：`ContentView.swift` 关闭态优先级链里插入的**低优先**分支（判据是
//  `ModuleRegistry.compactEntries` 非空，即「有 active 且声明 compact 的模块，且没有别的
//  live activity 占用关闭态」时）才走到这里。
//
//  职责边界与 `ModuleHostView` 一致：只做「取内容 + 分发分支」——不持有模块状态、不做尺寸协商
//  （模块自报高度属 P2）。
//

import SwiftUI

/// 把 `ModuleRegistry.compactSlotContent()` 的答案渲染进关闭态的**中央槽位**。
///
/// 观察注册表是**必需**的（同 `ModuleHostView`）：`UIHandle.requestRedraw` 被路由到
/// `ModuleRegistry.shared.objectWillChange`，不观察就不会重绘。
///
/// 颜色：关闭态面板是黑底、系统外观可为浅色，所以这里的降级文案也显式浅色
/// （`.white`）——`ModuleHostView` 的 `.secondary` 在黑底 + 浅色外观下会看不见。
struct ModuleCompactSlotView: View {
    @ObservedObject private var registry = ModuleRegistry.shared

    var body: some View {
        content
    }

    /// 四个分支逐条对应 06 §3.2（与 `ModuleHostView.content(for:)` 同构）：
    /// `.view` 渲染模块给的视图；`.descriptor` 不渲染（D-06，占位成 unavailable 文案）；
    /// `.unavailable` 显示占位与原因（**不算失败**）；`.none` 不占位。
    @ViewBuilder
    private var content: some View {
        switch registry.compactSlotContent() {
        case .view(let view):
            view
        case .descriptor:
            unavailable("折叠态槽位不支持插件描述符（descriptor）渲染")
        case .unavailable(let reason):
            unavailable(reason)
        case .none:
            EmptyView()
        }
    }

    /// 降级占位：只解释原因，不带任何交互（不崩、不阻塞关闭态的其它内容）。
    private func unavailable(_ reason: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .medium))
            Text(reason)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 8)
    }
}
