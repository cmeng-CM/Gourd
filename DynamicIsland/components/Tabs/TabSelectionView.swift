/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AtollExtensionKit
import SwiftUI
import Defaults
import AppKit

struct TabModel: Identifiable {
    let id: String
    let label: String
    let icon: String
    let view: NotchViews
    let experienceID: String?
    let accentColor: Color?

    init(label: String, icon: String, view: NotchViews, experienceID: String? = nil, accentColor: Color? = nil) {
        self.id = experienceID.map { "extension-\($0)" } ?? "system-\(view)-\(label)"
        self.label = label
        self.icon = icon
        self.view = view
        self.experienceID = experienceID
        self.accentColor = accentColor
    }
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var extensionNotchExperienceManager = ExtensionNotchExperienceManager.shared
    /// 模块注册表（接缝 S1）：**必须观察**——否则注册表变化后 tab 列表不重绘
    /// （与同文件 `extensionNotchExperienceManager` 同理；注册表空时本视图与改动前一致）。
    @ObservedObject private var moduleRegistry = ModuleRegistry.shared
    @StateObject private var quickShareService = QuickShareService.shared
    @Default(.quickShareProvider) private var quickShareProvider
    @State private var showQuickSharePopover = false
    @Default(.enableColorPickerFeature) var enableColorPickerFeature
    @Default(.enableThirdPartyExtensions) private var enableThirdPartyExtensions
    @Default(.enableExtensionNotchExperiences) private var enableExtensionNotchExperiences
    @Default(.enableExtensionNotchTabs) private var enableExtensionNotchTabs
    @Default(.showCalendar) private var showCalendar
    @Default(.showMirror) private var showMirror
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.enableMinimalisticUI) private var enableMinimalisticUI
    @Namespace var animation
    
    private var tabs: [TabModel] {
        var tabsArray: [TabModel] = []

        if homeTabVisible {
            tabsArray.append(TabModel(label: "Home", icon: "house.fill", view: .home))
        }

        if Defaults[.dynamicShelf] {
            tabsArray.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        }
        
        // Timer tab：**已由模块投影产出**（`TimerModule`，docs/20 §做法 机制一）——
        // 上游那条「功能开着 + 显示方式选 tab」的分支已删除，不允许与模块并存
        // （并存就是两个计时器 tab）。下方模块段的条目即计时器页。

        // Stats tab：**已删除**（p3-widgets / T2，docs/26 §做法 机制一/机制二）——统计改成
        // **首页块**（`StatsModule`，启用真源不变：上游 `enableStatsFeature`），不再占展开 tab
        // 里的一个位置；`enabledStandardTabCount()` 里对应的 `+1` 同批删除。
        // 允许与模块段并存是不行的：并存就是两个统计入口。

        // Usage tab only shown when LLM usage feature is enabled
        if Defaults[.enableLLMUsageFeature] {
            tabsArray.append(TabModel(label: "Usage", icon: "chart.bar.doc.horizontal", view: .llmUsage))
        }

        // Notes / Clipboard tab：**只看剪贴板**（p3-widgets 收尾修复）——笔记设置页已从侧栏摘掉
        //（T5，`SettingsTab.notes` 与 `NotesSettingsView` 全保留），若这里仍认笔记那个总开关
        //（`enable` + `Notes` 拼出来的上游键），置 1 的用户会看到一个既不知道是什么、也
        //**无处可关**的 tab（本机该键恰好就是 1）。故条件里删掉笔记那一半、label / icon 固定为
        // Clipboard；笔记开关从此**惰性**（笔记代码与键一个字没删，只是不再产生任何入口）。
        // 与统计开关（p3-widgets / T2）同款先例：键保留、tab 分支删除。
        // 注意：`clipboardDisplayMode == .separateTab` 的用户仍必须能拿到这一支——不是整支删掉。
        if Defaults[.enableClipboardManager] && Defaults[.clipboardDisplayMode] == .separateTab {
            tabsArray.append(TabModel(label: "Clipboard", icon: "doc.on.clipboard", view: .notes))
        }
        if Defaults[.enableTerminalFeature] {
            tabsArray.append(TabModel(label: "Terminal", icon: "apple.terminal", view: .terminal))
        }
        if extensionTabsEnabled {
            for payload in extensionTabPayloads {
                guard let tab = payload.descriptor.tab else { continue }
                let accent = payload.descriptor.accentColor.swiftUIColor
                let iconName = tab.iconSymbolName ?? "puzzlepiece.extension"
                tabsArray.append(
                    TabModel(
                        label: tab.title,
                        icon: iconName,
                        view: .extensionExperience,
                        experienceID: payload.descriptor.id,
                        accentColor: accent
                    )
                )
            }
        }

        // 模块内核 tab（接缝 S1）：注册表投影，`experienceID` 复用为模块 id（`TabModel` 的 id
        // 由 experienceID 派生，`ForEach` 零改）。只含 active 且声明 `.expanded` 的模块。
        for entry in ModuleRegistry.shared.tabEntries {
            tabsArray.append(
                TabModel(label: entry.label, icon: entry.symbolName, view: .module, experienceID: entry.id)
            )
        }
        return tabsArray
    }
    var body: some View {
        HStack(spacing: 24) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { idx, tab in
                let isSelected = isSelected(tab)
                let activeAccent = tab.accentColor ?? .white

                // Render the tab button
                TabButton(label: tab.label, icon: tab.icon, selected: isSelected) {
                    if tab.view == .extensionExperience {
                        coordinator.selectedExtensionExperienceID = tab.experienceID
                    }
                    if tab.view == .module {
                        // 模块 tab：必须走 selectModule（同时设 selectedModuleID + currentView），
                        // 只设 currentView = .module 会让内容区渲染 EmptyView（接缝 S1 ④）。
                        coordinator.selectModule(tab.experienceID ?? "")
                    }
                    coordinator.currentView = tab.view
                }
                .frame(height: 26)
                .foregroundStyle(isSelected ? activeAccent : .gray)
                .background {
                    if isSelected {
                        Capsule()
                            .fill((tab.accentColor ?? Color(nsColor: .secondarySystemFill)).opacity(0.25))
                            .shadow(color: (tab.accentColor ?? .clear).opacity(0.4), radius: 8)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                            .hidden()
                    }
                }

                
            }
        }
        .clipShape(Capsule())
        .onAppear {
            ensureValidSelection(with: tabs)
        }
    }

    private var extensionTabsEnabled: Bool {
        enableThirdPartyExtensions && enableExtensionNotchExperiences && enableExtensionNotchTabs
    }

    private var extensionTabPayloads: [ExtensionNotchExperiencePayload] {
        extensionNotchExperienceManager.activeExperiences.filter { $0.descriptor.tab != nil }
    }

    private var homeTabVisible: Bool {
        if enableMinimalisticUI {
            return true
        }
        return showStandardMediaControls || showCalendar || showMirror
    }

    private func isSelected(_ tab: TabModel) -> Bool {
        if tab.view == .extensionExperience {
            return coordinator.currentView == .extensionExperience
                && coordinator.selectedExtensionExperienceID == tab.experienceID
        }
        // 模块 tab 与扩展 tab 同理：`currentView` 只表达「在模块视图」，还要比对模块 id
        // 才能区分同一个 `.module` 下的多个 tab（接缝 S1 ③）。
        if tab.view == .module {
            return coordinator.currentView == .module
                && coordinator.selectedModuleID == tab.experienceID
        }
        return coordinator.currentView == tab.view
    }

    private func ensureValidSelection(with tabs: [TabModel]) {
        guard !tabs.isEmpty else { return }
        if tabs.contains(where: { isSelected($0) }) {
            return
        }
        guard let first = tabs.first else { return }
        if first.view == .extensionExperience {
            coordinator.selectedExtensionExperienceID = first.experienceID
        } else {
            coordinator.selectedExtensionExperienceID = nil
        }
        // 模块 tab 落到首位时（其余 tab 全关）与扩展 tab 同构：不带上模块 id 就会渲染 EmptyView
        if first.view == .module {
            coordinator.selectedModuleID = first.experienceID
        }
        coordinator.currentView = first.view
    }
}

#Preview {
    DynamicIslandHeader().environmentObject(DynamicIslandViewModel())
}
