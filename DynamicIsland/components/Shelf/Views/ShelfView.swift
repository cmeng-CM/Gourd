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

import SwiftUI
import AppKit

private struct ShelfBackgroundClickCatcher: NSViewRepresentable {
    let onClick: () -> Void

    func makeNSView(context: Context) -> BackgroundClickView {
        let view = BackgroundClickView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: BackgroundClickView, context: Context) {
        nsView.onClick = onClick
    }

    final class BackgroundClickView: NSView {
        var onClick: (() -> Void)?

        override func mouseUp(with event: NSEvent) {
            onClick?()
        }
    }
}

private struct ShelfViewportSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// 架子的面板壳：**内容当根**（量理想高时答的就是内容高），虚线环与背景点击层都不吃尺寸。
///
/// **为什么不是「环当根 + 内容放 overlay」**（T6 前的写法）：`Shape` 在**没有高提案**时
/// 答 10pt（未指定维度的回落值），而 `.overlay` 不参与布局——整页的**理想高**就成了 10，
/// 高度探针量到的不是网格自然高，面板会被压到下限（实测：环当根 → 账本值 18；内容当根 →
/// 148 = 网格 108 + 内边距 32 + 表头 24 − 16）。抽成这个结构，是为了让用例能挂在**真组合**上
/// 量（`testShelfPanelMeasuresTheContentNotTheRing`）。
///
/// 面板仍要在有提案时填满（展开面板给的是定高）：`frame(maxWidth/maxHeight: .infinity)`
/// 只在有提案的那一档放大，量理想高（高提案为空）时逐字答内容高。
struct ShelfPanel<Content: View>: View {
    /// 拖拽悬停（虚线环高亮）。
    let isDropTargeted: Bool
    /// 面板级动画（`vm.animation`）。
    let animation: Animation?
    /// 点内容以外的空白（padding / 环那一圈）时清选择。
    let onBackgroundClick: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                // Covers the ring between the padded content and the panel edge,
                // plus the whole panel when the shelf is empty. The marquee
                // overlay only spans the ScrollView's content.
                ShelfBackgroundClickCatcher(onClick: onBackgroundClick)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isDropTargeted
                            ? Color.accentColor.opacity(0.9)
                            : Color.white.opacity(0.1),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10])
                    )
                    // 环只是画上去的：点在环上要落到下层的背景点击层（清选择），
                    // 不能挡住内容的命中（环从「根」改成「覆盖层」后必须显式让位）。
                    .allowsHitTesting(false)
            }
            .transaction { transaction in
                transaction.animation = animation
            }
            .contentShape(Rectangle())
    }
}

/// 架子网格的布局常量（p6-ui-polish / T6，docs/30 §做法 机制三）。
///
/// 格子尺寸仍是 `ShelfCellMetrics.size`（115×108，T5 钉的）——这里只声明
/// **网格怎么把它们摆开**：列宽 = 格子宽、项距 8、行距 8，自动换行（列数由
/// 自适应列按可用宽定，`columnCount(forWidth:)` 是它的算式）。
enum ShelfGridMetrics {
    /// 每个格子的宽（文件格与投放格同宽）。
    static var columnWidth: CGFloat { ShelfCellMetrics.size.width }
    /// 每个格子的高（文件格与投放格同高）。
    static var itemHeight: CGFloat { ShelfCellMetrics.size.height }
    /// 同一行里两个格子之间的距离。
    static let itemSpacing: CGFloat = 8
    /// 两行之间的距离（也是「网格 ↔ 空态一行」的距离，由 `ShelfView` 消费）。
    static let rowSpacing: CGFloat = 8

    /// **投放格在网格内容里的位置**——它永远是首格，也就是内容的左上角那一格。
    /// marquee 盖在整块内容上，靠这个矩形让位给投放格的点按（见
    /// `ShelfMarqueeSelectionView.passThroughRects`）。
    ///
    /// 不变量（改网格布局时这条要跟着改）：`VStack(alignment: .leading)` 把网格贴在
    /// 内容左上角、网格首格贴网格原点 —— 两个坐标空间（内容 / marquee 的本地空间）
    /// 是同一个 frame，因此这里不需要量、也不需要传 preference。
    static var shareTileFrame: CGRect {
        CGRect(origin: .zero, size: CGSize(width: columnWidth, height: itemHeight))
    }

    /// 可用宽下能摆几列（至少 1 列；宽还没量到 / 非有限 → 1 列）。
    ///
    /// **这是对 `.adaptive` 布局的预测，不是视图的入参**——视图用
    /// `GridItem(.adaptive(minimum:maximum:))` 让布局**自己**按可用宽分列（见 `columns`）。
    /// 2026-10-01 实测（887 宽、10 格）：SwiftUI 的分列 = 本函数的值（7 列）、
    /// 项距仍是 8（x = 0, 123, 246, …，余量 34 留在行尾）——因此这条可以用例钉住。
    static func columnCount(forWidth width: CGFloat) -> Int {
        guard width.isFinite, width > 0 else { return 1 }
        let count = Int((width + itemSpacing) / (columnWidth + itemSpacing))
        return max(1, count)
    }

    /// 网格的列：**自适应**——列宽恒等于格子宽（115）、项距恒为 8，列数由布局按可用宽算。
    ///
    /// 为什么用 `.adaptive` 而不是「拿 `@State` 里的视口宽自己算列数」：列数直接从
    /// **布局提案的宽**算，第一遍布局就与理想高的量法对上。挂在状态上的话，第一遍
    /// （视口宽还是 0）会按 1 列量一遍——探针把「一列堆起来」的大高报上去，账本收下；
    /// 等宽量到再缩，面板就会先停在那个错的高度上（「空半屏」正长这样）。
    static var columns: [GridItem] {
        [GridItem(.adaptive(minimum: columnWidth, maximum: columnWidth), spacing: itemSpacing)]
    }
}

struct ShelfView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    @State private var autoCloseToken = UUID()
    @State private var viewportSize: CGSize = .zero

    var body: some View {
        panel
        // Bind Quick Look to shelf selection. Skipped mid-marquee so a sweep
        // doesn't spawn a resolve Task per intermediate selection.
        .onChange(of: selection.selectedIDs) {
            guard !selection.isMarqueeSelecting else { return }
            updateQuickLookSelection()
        }
        .onChange(of: selection.isMarqueeSelecting) { _, active in
            if !active { updateQuickLookSelection() }
        }
        .onDisappear {
            vm.setAutoCloseSuppression(false, token: autoCloseToken)
        }
        .quickLookPresenter(using: quickLookService)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !selection.isDragging, !selection.isMarqueeSelecting else { return false }
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        return true
    }
    
    private func updateQuickLookSelection() {
        guard quickLookService.isQuickLookOpen && !selection.selectedIDs.isEmpty else { return }

        let selectedItems = selection.selectedItems(in: tvm.items)
        let capturedIDs = selection.selectedIDs

        Task {
            var urls: [URL] = []
            for item in selectedItems {
                if let fileURL = await ShelfStateViewModel.shared.resolveFileURLAsync(for: item) {
                    urls.append(fileURL)
                } else if case .link(let url) = item.kind {
                    urls.append(url)
                }
            }

            if !urls.isEmpty {
                await MainActor.run {
                    // Only update if selection hasn't changed since we started resolving
                    if selection.selectedIDs == capturedIDs {
                        quickLookService.updateSelection(urls: urls)
                    }
                }
            }
        }
    }

    var panel: some View {
        ShelfPanel(
            isDropTargeted: vm.dragDetectorTargeting,
            animation: vm.animation,
            onBackgroundClick: {
                guard !selection.isDragging, !selection.isMarqueeSelecting else { return }
                selection.clear()
            }
        ) {
            content
        }
        // The whole panel accepts drops (adds to the shelf); the file area inside
        // also does, so a drop aimed at the grid lands either way.
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            handleDrop(providers: providers)
        }
    }

    var content: some View {
        // 纵向滚动（原来是一行横滚）：首格是投放格，其余是文件格，自动换行。
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: ShelfGridMetrics.rowSpacing) {
                LazyVGrid(
                    columns: ShelfGridMetrics.columns,
                    alignment: .leading,
                    spacing: ShelfGridMetrics.rowSpacing
                ) {
                    // **投放格**（docs/30 §做法 机制三）：与文件格同尺寸的一枚虚线格，
                    // 供应商图标 + 名称、点按换供应商；`FileShareView` 的 drop 区缩进这里
                    // （`.onDrop` 仍挂它自己 + 容器/滚动区）。
                    FileShareView()
                        .environmentObject(vm)
                        .frame(
                            width: ShelfGridMetrics.columnWidth,
                            height: ShelfGridMetrics.itemHeight
                        )

                    ForEach(tvm.items) { item in
                        ShelfItemView(item: item)
                            .environmentObject(quickLookService)
                    }
                }

                // 空态：网格下居中一行（复用既有 key）。
                if tvm.isEmpty {
                    Text("Drop files here")
                        .font(.system(.callout, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            // Stretch the content to at least the viewport **width** so the marquee
            // overlay also covers the gap right of a partial row's last cell (that
            // gap is where a rubber-band selection usually starts).
            //
            // **不再撑高**（改动前这里是 `minHeight: viewportSize.height`）：高度一撑，
            // 这一页的**理想高**就变成「当前视口高」——探针量到的数 = 面板高 − 内边距，
            // 折回账本再算出的面板高 = 原面板高（不动点：面板永远不缩，「682 空半屏」再也不消失）。
            // 网格自然高才是这一页要的高度；auto 档下面板贴内容、视口没有多余空白，
            // marquee 的覆盖范围 = 内容本身（手动档/过渡帧里最后一行下方的空白带不再能起框，
            // 这是本次接受的取舍）。
            .frame(
                minWidth: viewportSize.width,
                alignment: .topLeading
            )
            .overlay {
                ShelfMarqueeSelectionView(
                    onBackgroundClick: {
                        guard !selection.isDragging else { return }
                        selection.clear()
                    },
                    onActiveChange: { active in
                        vm.setAutoCloseSuppression(active, token: autoCloseToken)
                    },
                    // 投放格在内容里永远是左上角那一格（见 `shareTileFrame` 的不变量）。
                    passThroughRects: [ShelfGridMetrics.shareTileFrame]
                )
            }
        }
        .scrollIndicators(.never)
        // Measures the ScrollView itself (the viewport), not its content,
        // so this only fires when the panel resizes. Feeds the content's
        // minimum width (marquee coverage over a partial row's tail).
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ShelfViewportSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(ShelfViewportSizeKey.self) { viewportSize = $0 }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            handleDrop(providers: providers)
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }
}
