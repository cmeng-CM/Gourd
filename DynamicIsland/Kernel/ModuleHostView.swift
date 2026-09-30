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
//  ModuleHostView.swift
//  Gourd 模块内核 · 展开面板宿主视图（P1 批次 / T3）
//
//  接缝 S5 的落点：`ContentView` 展开内容的 switch 里 `case .module` 指向本视图。
//  职责边界：本批只做「取内容 + 分发分支」——不持有模块状态、不做尺寸协商
//  （模块自报高度属 P2，见 docs/13-runtime-kernel.md「明确不做」）。
//

import SwiftUI

/// 把一个模块的展开内容渲染进刘海的展开面板。
///
/// 观察注册表是**必需**的：T2 把 `UIHandle.requestRedraw` 路由到
/// `ModuleRegistry.shared.objectWillChange`（T2 报告候选决策 2），
/// 本视图不观察它的话，模块的 `requestRedraw()` 不会真的重绘。
struct ModuleHostView: View {
    /// 模块 id（`coordinator.selectedModuleID`）；nil = 尚无选中模块 → EmptyView。
    let moduleID: String?

    @ObservedObject private var registry = ModuleRegistry.shared

    /// 上游视图就是这么拿 vm 的（ContentView 根部 `.environmentObject(vm)`）。
    @EnvironmentObject var vm: DynamicIslandViewModel

    /// 滚动抑制令牌（补于 2026-09-28）。
    ///
    /// 原因：面板装了全局 `scrollWheel` 监听（`extensions/PanGesture.swift` 的本地/全局
    /// monitor → `ContentView.handleCloseScrollGesture`），向下滚动被判定为「收起面板」
    /// 手势。模块内容（通知 / 待办等列表）原本没有占用抑制令牌，于是用户在模块列表里
    /// 滚动时，面板一边按收起动画模糊一边继续滚动——表现为「列表一滑面板就收起」
    /// 与「滑动过程中看不清列表」两个症状。
    ///
    /// 上游每个自带滚动区的视图都用同一套令牌规避（`NotchNotesView`、`NotchClipboardView`、
    /// `NotchTerminalView`、`NotchHomeView`、`RulerTimerPicker` 都是悬停时
    /// `vm.setScrollGestureSuppression(true, token:)`）：令牌非空 →
    /// `vm.isScrollGestureActive == true` → `handleCloseScrollGesture` 的守卫直接 return。
    /// 本视图是**模块内容的统一宿主**，在这里占令牌即可一次覆盖所有模块列表，
    /// 无需逐个模块改造。
    ///
    /// 注意：`ModuleCompactSlotView`（折叠态槽位）不加——折叠态的展开手势不检查该令牌。
    @State private var suppressionToken = UUID()
    @State private var isSuppressing = false

    var body: some View {
        if let moduleID {
            content(for: moduleID)
                .onHover { updateSuppression(for: $0) }
                // 切走 tab 或面板收起时本视图被销毁，`onHover` 不会再补发一次 false，
                // 必须显式释放令牌，否则抑制状态悬空、面板之后再也收不起来。
                .onDisappear { updateSuppression(for: false) }
        }
    }

    private func updateSuppression(for hovering: Bool) {
        guard hovering != isSuppressing else { return }
        isSuppressing = hovering
        vm.setScrollGestureSuppression(hovering, token: suppressionToken)
    }

    /// 本批的内容请求是「展开面板 + 已展开」的定值：
    /// - `reason` 恒 `.initial`——宿主还没记录「这是第几次评估」，`redraw` 与 `initial`
    ///   在当前实现里走同一条同步取内容路径（P1-2 的状态机接管后才有区分价值）；
    /// - `isLowPower` 用宿主信号的本批恒定值 false（P1-3 补信号）；
    /// - `sizeHint` 不参与协商（模块自报高度属 P2），留初始值 `.zero`。
    private var request: ContentRequest {
        ContentRequest(surface: .expanded, phase: .expanded, reason: .initial)
    }

    /// 四个分支逐条对应 06 §3.2：
    /// `.view` 渲染模块给的视图；`.descriptor` 本批不渲染（D-06，占位成 unavailable 文案）；
    /// `.unavailable` 显示占位与原因（**不算失败**）；`.none` 不占位。
    @ViewBuilder
    private func content(for moduleID: String) -> some View {
        switch registry.content(for: moduleID, request: request) {
        case .view(let view):
            view
        case .descriptor:
            unavailable("模块 \(moduleID) 使用插件描述符（descriptor），本批尚未支持渲染")
        case .unavailable(let reason):
            unavailable(reason)
        case .none:
            EmptyView()
        }
    }

    /// 降级占位：只解释原因，不带任何交互（不崩、不阻塞展开面板的其他部分）。
    private func unavailable(_ reason: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 18))
            Text(reason)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
