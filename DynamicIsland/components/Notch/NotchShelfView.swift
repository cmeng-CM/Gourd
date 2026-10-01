/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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

import SwiftUI

struct NotchShelfView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var coordinator = DynamicIslandViewCoordinator.shared

    var body: some View {
        // **自然高上报**（p6-ui-polish / T6，docs/30 §做法 机制三）：架子页与模块页一样
        // 挂同一支探针——`panelContentHeightReport` 在生产路径上只挂在 `.module` 分支
        // （`ContentView` 的展开 switch），架子走 `.shelf` 分支，因此在这里补挂。
        // 键 = `ContentView.selectedPanelTabKey` 对 `.shelf` 传的那个值（`"shelf"`，
        // 与 `PanelContentHeight.shelfTab` 同字面量）；探针量的是这一页的**理想高**
        // （纵向 `ScrollView` 的理想高 = 网格的自然高，与面板当前多高无关）。
        ShelfView()
            .environmentObject(vm)
            .panelContentHeightReport(
                tab: PanelContentHeight.shelfTab,
                headerHeight: PanelAutoHeight.panelHeaderHeight(
                    effectiveClosedNotchHeight: vm.effectiveClosedNotchHeight
                ),
                isCurrent: { coordinator.currentView == .shelf }
            )
    }
}

