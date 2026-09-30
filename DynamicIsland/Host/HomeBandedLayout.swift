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
//  HomeBandedLayout.swift
//  Gourd 宿主 · 首页两条带的摆放算术（P3 组件批次 / T7）
//
//  首页自 T7 起分**两条带**（docs/26-home-widgets-and-settings.md §做法 机制六 / D-09）：
//
//  - **主块带**（上）：大块（音乐的封面 + 控制、镜子的画面）——**逐字沿用**旧 strip 的语义
//    （`HomeStripLayoutMath.plan` 的三条规则：富余不拉伸 / 不足按最小宽压缩 / 仍不足按序丢尾巴 + `＋N`）；
//  - **小组件带**（下）：紧凑块（进度、统计、待办、通知、前台应用）——按可用宽**铺网格、放不下换行**，
//    行数由分给这条带的高度决定；**只有连一行都放不下时才丢块**并计入 `＋N`。
//
//  它解决的是**默认宽度下就丢块**的问题（用户原话：「不要把所有小组件都放在第一排……都隐藏掉了」）：
//  一条 strip 要装 6–8 块时，规则 ③ 从尾部丢到只剩前几块；换成两带后，紧凑块换行而不是消失
//  （T1+T2 的实拍：默认 1154pt 面板下 6 块最小宽之和 + 间隙 = 1280 > 可用宽 ≈1086，尾部块被丢）。
//
//  **纯几何，无 SwiftUI**（与 `HomeStripLayoutMath` / `HomeVerticalFit` 同一条纪律）：本文件只做算术，
//  摆放与画由 `HomeStripView` / `HomeWidgetBandView` 做，规则因此能被单测穷举
//  （`DynamicIslandTests/HomeStripLayoutTests.swift`）。
//
//  分工（三个纯函数的调用顺序，唯一一处）：
//  1. `HomeBandedLayout.rowsNeeded(items:availableWidth:columnSpacing:)`
//     —— 只按**宽度**铺：全部紧凑块要几行（贪心换行，用各自的最小宽判）；
//  2. `HomeVerticalFit.plan(… widgetRowsNeeded:)`
//     —— 分给小组件带多少高度（以及画不画日历行、画不画主块带，见那边的四档）；
//  3. `HomeBandedLayout.plan(… widgetBandHeight:)`
//     —— 按分到的高度定「真正画几行」（高不够就少画几行、尾巴的格计入 `＋N`）。
//
//  **宽度与高度的判据必须互相咬合**：`HomeVerticalFit` 判「这条高度放得下 n 行」用的算式是
//  `n × rowHeight + (n-1) × rowSpacing`，而本文件判「这条高度放得下几行」用的是同一个式子的反解
//  （`floor((bandHeight + rowSpacing) / (rowHeight + rowSpacing))`）——两条判据在阈值上等价，
//  由 `testWidgetRowAffordabilityInvertsTheTierThreshold` 钉住（改一个算式就会红）。
//

import CoreGraphics

/// 首页两条带的摆放：主块带交给 `HomeStripLayoutMath.plan`，小组件带按网格换行。
public enum HomeBandedLayout {

    /// 两条带的度量（都取自宿主常量，见 `HomeStripView`）。
    ///
    /// 负值一律按 0 处理（间距为负会让「总和 + 间隙」的算式失去意义），`plan` 内部做这一次钳制；
    /// 调用方传的就是宿主写死的常量，生产路径上不会出现负数。
    public struct Metrics: Equatable {
        /// 主块带的块间距。
        public let mainSpacing: CGFloat
        /// 主块带的尾部预留位宽度（`＋N` 提示位；0 = 不预留）。
        public let mainTailReserve: CGFloat
        /// 小组件带的**列**间距（同一行内格与格之间）。
        public let widgetColumnSpacing: CGFloat
        /// 小组件带的**行**间距。
        public let widgetRowSpacing: CGFloat
        /// 小组件带**每行的高度**（定值：行是等高网格，不随可用高度伸缩）。
        public let widgetRowHeight: CGFloat
        /// 小组件带最后一行末尾的 `＋N` 提示位宽度（0 = 不预留）。
        public let widgetTailReserve: CGFloat

        public init(
            mainSpacing: CGFloat,
            mainTailReserve: CGFloat,
            widgetColumnSpacing: CGFloat,
            widgetRowSpacing: CGFloat,
            widgetRowHeight: CGFloat,
            widgetTailReserve: CGFloat
        ) {
            self.mainSpacing = mainSpacing
            self.mainTailReserve = mainTailReserve
            self.widgetColumnSpacing = widgetColumnSpacing
            self.widgetRowSpacing = widgetRowSpacing
            self.widgetRowHeight = widgetRowHeight
            self.widgetTailReserve = widgetTailReserve
        }
    }

    /// 小组件带的一行：**摆放方案**（每格拿多少宽 + 这一行的位置信息）。
    public struct WidgetRow: Equatable {
        /// 本行的格在**输入 `widgetItems` 里的下标**（顺序即显示顺序）。
        public let indices: [Int]
        /// 每格分到的宽度：下标与 `indices` 的前 `widths.count` 项一一对应；
        /// `indices` 尾部多出来的格是本行被规则 ③ 丢掉的（视图对它们用零提案，同主块带）。
        public let widths: [CGFloat]
        /// 本行的高度（恒为 `Metrics.widgetRowHeight`；带上是为了渲染侧不必再问一次）。
        public let height: CGFloat
        /// 本行末尾是否留出了 `＋N` 提示位（真 = 末尾 `widgetTailReserve` 那一段归提示用）。
        public let showsHint: Bool
        /// 本行被丢掉的格数（规则 ③ 在行内丢的尾巴）。
        public let droppedCount: Int

        /// 本行实际画出来的格数。
        public var visibleCount: Int { widths.count }
    }

    /// 小组件带的一次摆放。
    public struct WidgetBandPlan: Equatable {
        /// 真正画出来的行（从第一行起连续；高不够时尾部整行不画）。
        public let rows: [WidgetRow]
        /// 画出来的格数。
        public let visibleCount: Int
        /// 没画出来的格数（`widgetItems.count - visibleCount`）：行不够 + 行内规则 ③ 丢的两部分。
        public let droppedCount: Int
        /// 按**宽度**铺开全部格需要的行数（与高度无关；`widgetItems` 为空时 0）。
        public let rowsNeeded: Int
        /// 这条带末尾要不要画 `＋N` 胶囊（= 有格被丢掉且末尾留出了提示位）。
        public let showsHint: Bool

        /// 画出来的行数。
        public var rowsDrawn: Int { rows.count }
    }

    /// 一次摆放的完整结果：两带各自的方案（视图只需要读它，不再自己算）。
    public struct Plan: Equatable {
        /// 主块带的宽度分配（`HomeStripLayoutMath.plan` 的原样结果，语义逐字未变）。
        public let main: HomeStripLayoutMath.Plan
        /// 小组件带的网格方案。
        public let widgets: WidgetBandPlan
        /// 两带一共丢了几个块（条尾 `＋N` 的 N 是**每条带各一个**，见 `WidgetBandPlan.showsHint`）。
        public var droppedCount: Int { main.droppedCount + widgets.droppedCount }
    }

    // MARK: - 宽度：铺成几行（第一步）

    /// 全部格按**可用宽度**铺开需要几行：**贪心逐行填**——一行里塞得下就塞（用各自的 `min` 判），
    /// 塞不下就换行。单格的 `min` 比可用宽还大时它自占一行（行内由规则 ③ 兜底，不在这里丢）。
    ///
    /// 为什么用 `min` 而不是 `ideal` 判行：`min` 是「低于它不如不显示」的下界，用它判出来的行数
    /// 是**装得下全部格的最少行数**——行数越少，这条带要的高度越少，越容易整条留在屏上（换行不丢块的
    /// 目标）。`ideal` 只影响每行内部的自适应（`plan` 里由 `HomeStripLayoutMath` 的规则 ①② 决定）。
    public static func rowsNeeded(
        items: [HomeStripLayoutMath.Item],
        availableWidth: CGFloat,
        columnSpacing: CGFloat
    ) -> Int {
        wrappedRows(items: items, availableWidth: availableWidth, columnSpacing: columnSpacing).count
    }

    /// 贪心换行的行划分（每行 = 一组下标），`rowsNeeded` 与 `plan` 共用的唯一一份。
    static func wrappedRows(
        items: [HomeStripLayoutMath.Item],
        availableWidth: CGFloat,
        columnSpacing: CGFloat
    ) -> [[Int]] {
        guard !items.isEmpty else { return [] }
        let available = max(0, availableWidth)
        let spacing = max(0, columnSpacing)

        var rows: [[Int]] = []
        var current: [Int] = []
        // 本行当前的占用（sum(min) + 格间间隙）：与 `HomeStripLayoutMath` 的「总和 + 间隙」同口径。
        var used: CGFloat = 0

        for (index, item) in items.enumerated() {
            let itemMin = max(0, item.min)
            let withNewCell = current.isEmpty ? itemMin : used + spacing + itemMin
            if current.isEmpty || withNewCell <= available {
                current.append(index)
                used = withNewCell
            } else {
                rows.append(current)
                current = [index]
                used = itemMin
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    /// 分给小组件带的高度**放得下几行**（等高行：`n` 行要 `n × rowHeight + (n-1) × rowSpacing`）。
    ///
    /// 与 `HomeVerticalFit` 判「这条带要多少高度」是同一个式子的两个方向（文件头注释的咬合说明）。
    public static func affordableRows(
        bandHeight: CGFloat,
        rowHeight: CGFloat,
        rowSpacing: CGFloat
    ) -> Int {
        guard rowHeight > 0, bandHeight > 0, bandHeight.isFinite else { return 0 }
        let spacing = max(0, rowSpacing)
        let stride = rowHeight + spacing
        guard stride > 0, stride.isFinite else { return 0 }
        let raw = (bandHeight + spacing) / stride
        guard raw >= 1 else { return 0 }
        // 上限只为挡住非有限 / 天文数字的输入（生产档是 562 / 104 ≈ 5 行），不做产品约束。
        return Int(min(raw, 10_000).rounded(.down))
    }

    // MARK: - 摆放：两带的方案（第三步）

    /// 算出两条带的摆放方案。
    ///
    /// - **主块带**：`HomeStripLayoutMath.plan` 的原样调用（三条规则与尾部预留位的语义一字未改）；
    /// - **小组件带**：先按宽度贪心换行（`wrappedRows`），再看 `widgetBandHeight` 放得下几行，
    ///   放不下的整行不画、被丢的格计入 `＋N`；行内宽度交给 `HomeStripLayoutMath.plan`（同一个
    ///   分配器——富余不拉伸 / 不足压缩 / 单行也放不下时按 `max(0, available)` 兜底）。
    ///
    /// **提示位**（`Metrics.widgetTailReserve`）：只有「有格被丢掉」时才在**最后一行**末尾留出那段
    /// 宽度（那也正是 `＋N` 胶囊的落点，视图按 `showsHint` 画）。留出提示位可能让该行自己再丢一格
    /// （宽度不够时的规则 ③）——那一个格也如实计入 `droppedCount`，与主块带同一条口径
    /// （docs/21-strip-honesty.md §已知限制 6）。
    ///
    /// - Parameters:
    ///   - mainItems: 主块带的块宽声明（顺序即显示顺序）。
    ///   - widgetItems: 小组件带的块宽声明（顺序即显示顺序）。
    ///   - availableWidth: 两条带的**可用宽度**（同宽；宿主给的是面板内的整条宽）。
    ///   - widgetBandHeight: 分给小组件带的可用高度（由 `HomeVerticalFit` 定）。
    ///   - metrics: 两带的度量（间距、行高、尾部预留位）。
    public static func plan(
        mainItems: [HomeStripLayoutMath.Item],
        widgetItems: [HomeStripLayoutMath.Item],
        availableWidth: CGFloat,
        widgetBandHeight: CGFloat,
        metrics: Metrics
    ) -> Plan {
        let available = max(0, availableWidth)
        let rowHeight = max(0, metrics.widgetRowHeight)

        let main = HomeStripLayoutMath.plan(
            items: mainItems,
            available: available,
            spacing: max(0, metrics.mainSpacing),
            tailReserve: max(0, metrics.mainTailReserve)
        )

        let rows = wrappedRows(
            items: widgetItems,
            availableWidth: available,
            columnSpacing: metrics.widgetColumnSpacing
        )
        let rowsNeeded = rows.count
        let rowsDrawn = min(rowsNeeded, affordableRows(
            bandHeight: widgetBandHeight,
            rowHeight: rowHeight,
            rowSpacing: metrics.widgetRowSpacing
        ))
        let dropsBlocks = rowsDrawn < rowsNeeded
        let hintWidth = max(0, metrics.widgetTailReserve)
        // 提示位只在「真的有格被丢」且「留得下那段宽度」时存在（留不下就画在行尾之上会压住内容）。
        let reservesHint = dropsBlocks && hintWidth > 0 && available >= hintWidth

        var widgetRows: [WidgetRow] = []
        widgetRows.reserveCapacity(rowsDrawn)
        for rowIndex in 0..<max(0, rowsDrawn) {
            let indices = rows[rowIndex]
            let isLastDrawn = rowIndex == rowsDrawn - 1
            let showsHint = isLastDrawn && reservesHint
            let rowAvailable = showsHint ? available - hintWidth : available
            let rowPlan = HomeStripLayoutMath.plan(
                items: indices.map { widgetItems[$0] },
                available: rowAvailable,
                spacing: max(0, metrics.widgetColumnSpacing)
            )
            widgetRows.append(
                WidgetRow(
                    indices: Array(indices.prefix(rowPlan.visibleCount)),
                    widths: rowPlan.widths,
                    height: rowHeight,
                    showsHint: showsHint,
                    droppedCount: rowPlan.droppedCount
                )
            )
        }

        let visibleCount = widgetRows.reduce(0) { $0 + $1.visibleCount }
        return Plan(
            main: main,
            widgets: WidgetBandPlan(
                rows: widgetRows,
                visibleCount: visibleCount,
                droppedCount: widgetItems.count - visibleCount,
                rowsNeeded: rowsNeeded,
                showsHint: widgetRows.contains(where: \.showsHint)
            )
        )
    }
}
