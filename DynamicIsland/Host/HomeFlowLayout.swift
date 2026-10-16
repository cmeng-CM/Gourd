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
//  HomeFlowLayout.swift
//  Gourd 宿主 · 首页**单条流**的摆放算术（P4 批次）
//
//  首页自本批起**不再分两条带**，改成**一条可换行的流**（docs/28-home-layout-redesign.md §4）：
//  所有块（大块与紧凑块一视同仁）按用户顺序进入同一条流，**按声明宽度贪心装行、放不下换行**；
//  一行的**行高 = 该行最高块**；块**不被拉高填满**（音乐封面不再撑到整条带那么高）。
//
//  **p13 起流是「可变流」**（docs/38-home-v5-layout.md D-01/D-07）：环境带（固定第一排）与
//  今天带（宿主直渲）**不在本文件的输入里**——接缝把它们的宽度与高度扣掉之后，剩下给流的
//  才是这里的 `availableWidth` / `availableHeight`。改前流下方那条全宽日历行**已整条退休**
//  （月历退出首页），因此 `plan` 不再有 `calendarHeight` 参数、`Plan` 不再有 `showsCalendarRow`。
//
//  **为什么废掉两条带**（docs/28 §3 的四条归因）：带是"预留高度"的容器——只剩音乐时，主块带的
//  剩余横向空间谁也借不到（P1），紧凑块只能挤在自己那条带里换行（P2）；日历行天然独占一行（P3）；
//  而带内行高是定值，内容超了就裁（P4，待办块的清单被切掉一半）。换成一条流之后：横向空间**在行内
//  共享**、纵向只按"这一行有多高"逐行扣，三条归因同时消失。
//
//  与 Nook X 的关系（[16](../../docs/16-nookx-reference.md) §5.1）：它的首页就是**一条横向密排的
//  strip，块宽按内容自适应**；它不换行（靠用户少开组件），我们换行（宁可多一行也不丢块——
//  这是 [21](../../docs/21-strip-honesty.md) 的既有裁决）。
//
//  **纯几何，无 SwiftUI**（与 `HomeStripLayoutMath` 同一条纪律）：本文件只做算术，摆放与画由
//  `HomeFlowView` 做，规则因此能被单测穷举（`DynamicIslandTests/HomeStripLayoutTests.swift`）。
//
//  行内的宽度分配**复用 `HomeStripLayoutMath.plan`**（富余不拉伸 / 不足按最小宽压缩 / 仍不足按序
//  丢尾巴 + `＋N`）——那三条规则一字未改，只多一条 **①′「弹性块吃行内余量」**
//  （docs/38 D-04；`Item.flexible`，缺省 false 时逐字是改动前的行为）。
//

import CoreGraphics

/// 首页单条流的摆放：按宽度换行 → 按高度决定画几行 → 逐行分配宽度。
public enum HomeFlowLayout {

    /// 流里的一块：宽度区间 + 高度。
    ///
    /// **高度是块自己声明的**（`homeBlockHeight` 钩子 → 宿主换算，见 `HomeFlowView.blockHeight(for:)`）：
    /// 申报固定高的块与沿用形态档高的块可以在同一行里并排。
    ///
    /// **`flexible` = 该块吸收**它所在那一行的剩余宽度（docs/38-home-v5-layout.md D-04）；
    /// 缺省 false = 余量留行尾（改动前的行为）。
    public struct Item: Equatable {
        public let min: CGFloat
        public let ideal: CGFloat
        public let height: CGFloat
        public let flexible: Bool

        public init(min: CGFloat, ideal: CGFloat, height: CGFloat, flexible: Bool = false) {
            self.min = min
            self.ideal = ideal
            self.height = height
            self.flexible = flexible
        }
    }

    /// 流的度量（都取自宿主常量，见 `HomeFlowView`）。
    ///
    /// 负值一律按 0 处理（间距为负会让"总和 + 间隙"失去意义），`plan` 内部做这一次钳制。
    public struct Metrics: Equatable {
        /// 行内格与格之间的间距。
        public let columnSpacing: CGFloat
        /// 行与行之间的间距。
        public let rowSpacing: CGFloat
        /// 有丢弃时最后一行末尾的 `＋N` 提示位宽度（0 = 不预留）。
        public let tailReserve: CGFloat

        public init(columnSpacing: CGFloat, rowSpacing: CGFloat, tailReserve: CGFloat) {
            self.columnSpacing = columnSpacing
            self.rowSpacing = rowSpacing
            self.tailReserve = tailReserve
        }
    }

    /// 流里的一行：本行有哪些块、各分到多宽、这一行多高。
    public struct Row: Equatable {
        /// 本行的块在**输入 `items` 里的下标**（顺序即显示顺序）。
        public let indices: [Int]
        /// 每格分到的宽度：下标与 `indices` 的前 `widths.count` 项一一对应；
        /// `indices` 尾部多出来的格是本行被规则 ③ 丢掉的（视图对它们用零提案）。
        public let widths: [CGFloat]
        /// 本行的高度 = 行内各块声明高度的最大值（**不是**宿主统一的定值）。
        public let height: CGFloat
        /// 本行末尾是否留出了 `＋N` 提示位（真 = 末尾 `tailReserve` 那一段归提示用）。
        public let showsHint: Bool
        /// 本行被丢掉的格数（行内规则 ③ 丢的尾巴）。
        public let droppedCount: Int

        /// 本行实际画出来的格数。
        public var visibleCount: Int { widths.count }
    }

    /// 一次摆放的完整结果：视图只需要读它，不再自己算。
    public struct Plan: Equatable {
        /// 真正画出来的行（从第一行起连续；高度不够时**尾部整行不画**）。
        public let rows: [Row]
        /// 行与行之间的间距（渲染侧把它交给 `VStack(spacing:)`——`heightUsed` 也用它算，
        /// 两边因此不可能出现两个数）。
        public let rowSpacing: CGFloat
        /// 画出来的格数。
        public let visibleCount: Int
        /// 没画出来的格数（`items.count - visibleCount`）：行不够 + 行内规则 ③ 丢的两部分。
        public let droppedCount: Int
        /// 按**宽度**铺开全部格需要的行数（与高度无关；`items` 为空时 0）。
        public let rowsNeeded: Int
        /// 最后一行末尾要不要画 `＋N` 胶囊（= 有格被丢掉且末尾留出了提示位）。
        public let showsHint: Bool

        /// 画出来的行数。
        public var rowsDrawn: Int { rows.count }

        /// 这些行一共要占的高度（含行间距）：渲染侧用它给流钉 frame——**不要再自己加一遍**，
        /// 否则「画出来的高度」与「取舍时算的高度」会漂成两个数。
        public var heightUsed: CGFloat {
            guard !rows.isEmpty else { return 0 }
            return rows.reduce(0) { $0 + $1.height } + CGFloat(rows.count - 1) * rowSpacing
        }
    }

    // MARK: - 第一步：按宽度换行

    /// 全部块按**可用宽度**铺开需要几行：**贪心逐行填**——一行里塞得下就塞（用各自的 `min` 判），
    /// 塞不下就换行。单块的 `min` 比可用宽还大时它自占一行（行内由规则 ③ 兜底，不在这里丢）。
    ///
    /// 为什么用 `min` 而不是 `ideal` 判行：`min` 是"低于它不如不显示"的下界，用它判出来的行数是
    /// **装得下全部块的最少行数**——行数越少，总共要的高度越少，越容易整条留在屏上（换行不丢块的目标）。
    /// `ideal` 只影响每行内部的自适应（由 `HomeStripLayoutMath` 的规则 ①② 决定）。
    public static func rowsNeeded(
        items: [Item],
        availableWidth: CGFloat,
        columnSpacing: CGFloat
    ) -> Int {
        wrappedRows(items: items, availableWidth: availableWidth, columnSpacing: columnSpacing).count
    }

    /// 贪心换行的行划分（每行 = 一组下标），`rowsNeeded` 与 `plan` 共用的唯一一份。
    static func wrappedRows(
        items: [Item],
        availableWidth: CGFloat,
        columnSpacing: CGFloat
    ) -> [[Int]] {
        guard !items.isEmpty else { return [] }
        let available = max(0, availableWidth)
        let spacing = max(0, columnSpacing)

        var rows: [[Int]] = []
        var current: [Int] = []
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

    // MARK: - 第二步 + 第三步：摆放

    /// 算出这条流的摆放方案。
    ///
    /// 顺序（**先宽度、再高度、最后行内分配**）：
    /// 1. 按宽度贪心换行 → 全部行（`wrappedRows`），每行的**行高 = 行内最高块**；
    /// 2. 高度取舍：在可用高度里**从第一行起累计**，装不下的**尾部整行不画**
    ///    （不切半行——P4 的病根就是定值行高切内容，这里改成"整行进出"）；
    /// 3. 行内宽度交给 `HomeStripLayoutMath.plan`（同一个分配器，语义未变；**弹性块吃余量**
    ///    那一档见 docs/38 D-04）；有丢弃时在**最后一行**末尾留出 `＋N` 提示位。
    ///
    /// **p13 起没有「日历行」这一项**（docs/38 D-07）：全宽日历行整条退休，本函数不再为它
    /// 预留高度、也不再按它做取舍（改前是"先收日历行、再收尾部行"）。
    ///
    /// **`lastRowStretchLimit`（docs/51 D-01，用户 2026-10-16）**：可用高有富余时，**最后一行**
    /// 长高吃掉这份富余（行高 = 该行申报高 + 吃到的量），它上面的行一律保持申报高；吃到的量**最多
    /// 就是这个上限**，多出来的富余照旧留在流末尾。首页底部那 20pt 空玻璃因此变成两块的板高
    /// （接缝用一条负底部内缩把这 20pt 交给本流，上限也取同一个常数
    /// `PanelAutoHeight.homeFlowBottomCredit`）。
    ///
    /// 为什么要有上限而不是"有多少吃多少"：**手动高度档**下面板可能比内容高出几百 pt，那是用户
    /// 选的框、不是「留白」，不该被块吃掉（否则两块会长成一整屏的大板）。上限还有一个作用是让
    /// **两条调用路径的差别只剩这一个数**：账本那一份传缺省的 0。
    ///
    /// 缺省 `0` = 改动前的逐字行为，**账本那一份必须用缺省**：内容自然高按「块的申报高之和」算
    /// （`PanelAutoHeight.contentHeight(from:)`），拿开着的 plan 去写账本，末行会被撑到预算上限、
    /// 面板跟着涨到上界。
    ///
    /// - Parameters:
    ///   - items: 全部块的声明（顺序即显示顺序）。
    ///   - availableWidth: 流的可用宽度（宿主给的是面板内扣掉内边距之后的整条宽）。
    ///   - availableHeight: 流的可用高度（**已扣掉环境带与今天带**，由接缝算好）。
    ///   - metrics: 度量（列间距 / 行间距 / 提示位宽）。
    ///   - lastRowStretchLimit: 末行最多长高多少（缺省 0 = 不吃；口径见上）。
    public static func plan(
        items: [Item],
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        metrics: Metrics,
        lastRowStretchLimit: CGFloat = 0
    ) -> Plan {
        let available = max(0, availableWidth)
        let height = max(0, availableHeight)
        let columnSpacing = max(0, metrics.columnSpacing)
        let rowSpacing = max(0, metrics.rowSpacing)
        let hintWidth = max(0, metrics.tailReserve)

        let rowIndices = wrappedRows(items: items, availableWidth: available, columnSpacing: columnSpacing)
        let rowHeights: [CGFloat] = rowIndices.map { indices in
            indices.map { max(0, items[$0].height) }.max() ?? 0
        }

        // 高度取舍：从第一行起累计，装不下的尾部整行不画。
        var drawnRows = 0
        var usedHeight: CGFloat = 0
        for rowHeight in rowHeights {
            let need = drawnRows == 0 ? rowHeight : usedHeight + rowSpacing + rowHeight
            guard need <= height else { break }
            usedHeight = need
            drawnRows += 1
        }

        // 末行长高：`usedHeight` 里**已含行间距**，因此把吃到的量整份加到最后一行的行高上，
        // 「各行高之和 + 行间距」于是正好等于 `usedHeight + 吃到的量`。一行都没画时富余无处可去
        // （没有末行）——留空。
        let lastRowGrowth = drawnRows > 0 && lastRowStretchLimit > 0
            ? min(max(0, height - usedHeight), lastRowStretchLimit)
            : 0

        let droppedByHeight = max(0, rowIndices.count - drawnRows)
        let reservesHint = droppedByHeight > 0 && hintWidth > 0 && available >= hintWidth

        var rows: [Row] = []
        rows.reserveCapacity(drawnRows)
        for rowIndex in 0..<drawnRows {
            let indices = rowIndices[rowIndex]
            let isLastDrawn = rowIndex == drawnRows - 1
            let showsHint = isLastDrawn && reservesHint
            let rowAvailable = showsHint ? available - hintWidth : available
            let rowPlan = HomeStripLayoutMath.plan(
                items: indices.map {
                    HomeStripLayoutMath.Item(
                        min: items[$0].min,
                        ideal: items[$0].ideal,
                        flexible: items[$0].flexible
                    )
                },
                available: rowAvailable,
                spacing: columnSpacing
            )
            rows.append(
                Row(
                    indices: Array(indices.prefix(rowPlan.visibleCount)),
                    widths: rowPlan.widths,
                    height: rowHeights[rowIndex] + (isLastDrawn ? lastRowGrowth : 0),
                    showsHint: showsHint,
                    droppedCount: rowPlan.droppedCount
                )
            )
        }

        let visibleCount = rows.reduce(0) { $0 + $1.visibleCount }
        return Plan(
            rows: rows,
            rowSpacing: rowSpacing,
            visibleCount: visibleCount,
            droppedCount: items.count - visibleCount,
            rowsNeeded: rowIndices.count,
            showsHint: rows.contains(where: \.showsHint)
        )
    }
}
