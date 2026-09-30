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
//  HomeStripLayoutTests.swift
//  Gourd 首页 strip · 布局纯函数与 `home` 投影（P2 批次 / T1）
//
//  覆盖 docs/17-nookx-adoption.md §接口与数据形状 1 / 2 / 5：
//
//  **布局 `HomeStripLayoutMath.plan`**（纯几何，无 SwiftUI）
//  - 富余不放大：块保持理想宽度、余量留尾部（D-02「不能强硬拉伸」）；
//  - 恰好放满：走规则 ① 且 `leftover == 0`；
//  - 不足但够最小宽度和：按可压缩量等比压缩、**向下取整到 0.5pt**、每块 ≥ `min`、
//    总和 + spacing ≤ available（首页真实预算 4 块 / 1010pt 的锚点用例）；
//  - 连最小宽度和都不够：从**尾部**逐块丢弃（D-03 丢块比压扁更可读），断言丢的是最后一块；
//  - 单块兜底：`widths == [max(0, available)]`、不出现负宽；
//  - 空数组：`leftover == available`；`spacing == 0` 与「间隙只出现在块与块之间」；
//  - 三条不变量（`widths.count == visibleCount` / 无负宽 / 总和约束）的批量复检；
//  - `leftover` 一律是**未被使用的尾部空间总量**（规则 ② 的取整零头、规则 ③ 丢块空出来的
//    空间都计入），`> 0` 不等于「没铺满」，所以断言一律走公式而不是 `== 0`。
//
//  **尾部预留位**（`plan(…:tailReserve:)`，docs/21-strip-honesty.md §做法 机制一 / §接口与数据形状 1）
//  - 不丢块 → 预留位不生效：宽度分配、`leftover` 与不传预留位时逐字相同，`tailReserveUsed == false`；
//  - 生产档（可用宽 702、四个块）：基线 3 块、预留 34pt 后**仍 3 块**、`droppedCount == 1`；
//  - 边界档（可用宽 660）：预留把尾部再挤掉一块（3 → 2，docs/21 §已知限制 6）；
//  - `tailReserve` 缺省 0 / 显式 0 / 负值等价（既有用例的默认行为因此逐字不变）。
//
//  **协议与投影**
//  - `Surface.home`：词汇表取值与保序解码（四个取值，既有三个不变）；
//  - `ModuleRegistry.homeEntries`：只收 `active` 且声明 `.home` 的模块（failed / disabled /
//    只声明 `.expanded` 的都不得入选），排序与 `tabEntries` **同一比较器** `(order, id)`，
//    `label` / `symbolName` 复用既有解析；
//  - `ModuleRegistry.home` 请求形状：`surface` / `phase` / `slot` / `sizeHint` / `reason` /
//    `isLowPower`——**宽度不由请求传递**（`sizeHint == .zero`）。
//
//  **首页两排的高度取舍 `HomeVerticalFit.plan`**（T2 / docs/23-home-fit.md §做法 机制二）
//  - 三档穷举：`.both`（582 → strip 280）/ `.stripOnly`（453 → strip 拿**全部** 453，日历行让位）/
//    `.calendarOnly`（151.9 → 两排都不画；合成入参下日历行放得下就画）；
//  - 阈值边界（闭区间）：454 恰好两排都在、453 日历行先消失、152 恰好 strip 仍在、151.9 strip 也让位；
//  - 顺序反转的正面判据：850 → 140 逐 pt 扫，日历行在 453 先消失、strip 撑到 151；
//  - 日历行关掉时（行高与间距按 0 传）strip 拿全部可用高度（与改动前同一口径）；
//  - 退化输入：`available == 0` 与负值都判成什么都不画（负值按 0 处理）。
//
//  夹具是**本文件私有**的最小假模块：`ModuleKernelTests` 的 `RegistryFixture` / `ProbeModule`
//  是 fileprivate（不跨文件可见），这里不复用、也不改它们的可见性。
//

import Defaults
import XCTest

import AppKit
import SwiftUI

@testable import Gourd

@MainActor
final class HomeStripLayoutTests: XCTestCase {

    // MARK: - 布局夹具

    /// 首页四块的真实宽度声明（docs/17 §接口与数据形状 6 的取值，不得另取一套）。
    private static let music = HomeStripLayoutMath.Item(min: 300, ideal: 420)
    private static let calendar = HomeStripLayoutMath.Item(min: 200, ideal: 260)
    private static let mirror = HomeStripLayoutMath.Item(min: 140, ideal: 160)
    private static let moduleBlock = HomeStripLayoutMath.Item(min: 180, ideal: 240)

    /// 770pt 面板下 strip 的可用宽：`770 − 两侧各 34pt`（内边距常量链推导，docs/17 §接口与数据形状 6；
    /// 像素反推 ≈703，两个口径都在同一档——这里取常量链的口径）。
    private static let panelWidth770StripWidth: CGFloat = 702

    /// **生产档四块**（T4 复现的输入）：音乐那一档 300/420 + 三个模块档 180/240
    /// （`HomeStripView.moduleBlockWidth` 的统一值）。770/900/1088 三档面板都拿这一组算。
    private static let productionFourBlockItems: [HomeStripLayoutMath.Item] = [
        HomeStripLayoutMath.Item(min: 300, ideal: 420),
        HomeStripLayoutMath.Item(min: 180, ideal: 240),
        HomeStripLayoutMath.Item(min: 180, ideal: 240),
        HomeStripLayoutMath.Item(min: 180, ideal: 240),
    ]

    /// 块间距：本文件**改动前**口径的宿主恒定值（`HomeStripView` 曾为 12）。既有用例的数字都按
    /// 这个值算过，因此保留不动；宿主**现值**走 `HomeStripLayout.spacing`（2026-09-29 改为 8），
    /// 由 `testThreeRealBlocksFitAtDefaultPanelBudget` 读它并钉住。
    private static let spacing: CGFloat = 12

    private func gaps(_ visibleCount: Int, spacing: CGFloat) -> CGFloat {
        spacing * CGFloat(max(0, visibleCount - 1))
    }

    /// 三条不变量（docs/17 §接口与数据形状 5）＋ 尾量非负。
    /// 每个用例末尾都过一遍，省得各写一套断言。
    private func assertInvariants(
        _ plan: HomeStripLayoutMath.Plan,
        available: CGFloat,
        spacing: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(plan.widths.count, plan.visibleCount, "widths.count 必须等于 visibleCount", file: file, line: line)
        XCTAssertTrue(plan.widths.allSatisfy { $0 >= 0 }, "不得出现负宽，实到 \(plan.widths)", file: file, line: line)
        XCTAssertTrue(plan.widths.allSatisfy { $0.isFinite }, "宽度必须是有限值，实到 \(plan.widths)", file: file, line: line)
        let total = plan.widths.reduce(CGFloat.zero, +) + gaps(plan.visibleCount, spacing: spacing)
        XCTAssertLessThanOrEqual(total, available + 1e-9, "总和不得越过可用宽度，实到 \(total) > \(available)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(plan.leftover, 0, "尾部余量不得为负", file: file, line: line)
    }

    /// 分配宽度都落在 0.5pt 网格上（向下取整的落点）。
    private func assertOnHalfPointGrid(_ widths: [CGFloat], file: StaticString = #filePath, line: UInt = #line) {
        for width in widths {
            XCTAssertEqual(width * 2, (width * 2).rounded(.down), "宽度应落在 0.5pt 网格上，实到 \(width)", file: file, line: line)
        }
    }

    /// `leftover` 只有一个口径：**未被使用的尾部空间总量**
    ///（`max(0, available − sum(widths) − spacing × max(0, count−1))`）。
    /// 规则 ② 的取整零头、规则 ③ 丢块空出来的空间都算在里面，所以不能拿 `== 0` 当「用满」判据。
    private func expectedLeftover(
        _ plan: HomeStripLayoutMath.Plan,
        available: CGFloat,
        spacing: CGFloat
    ) -> CGFloat {
        let used = plan.widths.reduce(CGFloat.zero, +) + gaps(plan.visibleCount, spacing: spacing)
        return max(0, available - used)
    }

    // MARK: - 规则 ①：富余不放大（D-02）

    /// 富余时块保持**理想宽度**（不得被拉伸）、`leftover` 是余量、块数不变。
    func testSurplusKeepsIdealWidthsAndLeavesLeftover() {
        let items = [Self.music, Self.calendar, Self.mirror, Self.moduleBlock]
        let available: CGFloat = 1200
        let plan = HomeStripLayoutMath.plan(items: items, available: available, spacing: Self.spacing)

        XCTAssertEqual(plan.widths, [420, 260, 160, 240], "富余时块应保持理想宽度（D-02：不拉伸）")
        XCTAssertEqual(plan.visibleCount, 4, "富余时四块都在")
        // 1200 − (420+260+160+240) − 12×3 = 84
        XCTAssertEqual(plan.leftover, 84, accuracy: 1e-9, "余量留在尾部")
        for (width, item) in zip(plan.widths, items) {
            XCTAssertLessThanOrEqual(width, item.ideal, "任何块的分配宽都不得超过其 ideal")
        }
        assertInvariants(plan, available: available, spacing: Self.spacing)
    }

    /// 恰好放满（`available == sum(ideal) + spacing × (n-1)`）也是规则 ①，但 `leftover == 0`。
    func testExactFitUsesIdealWidthsWithZeroLeftover() {
        let items = [Self.music, Self.calendar, Self.mirror, Self.moduleBlock]
        let available: CGFloat = 420 + 260 + 160 + 240 + Self.spacing * 3  // 1116
        let plan = HomeStripLayoutMath.plan(items: items, available: available, spacing: Self.spacing)

        XCTAssertEqual(plan.widths, [420, 260, 160, 240])
        XCTAssertEqual(plan.visibleCount, 4)
        XCTAssertEqual(plan.leftover, 0, accuracy: 1e-9, "恰好放满时没有余量")
        assertInvariants(plan, available: available, spacing: Self.spacing)
    }

    // MARK: - 规则 ②：按最小宽度收敛（等比压缩 + 向下取整到 0.5）

    /// 首页真实预算：四块（音乐 / 日历 / 镜子 / 模块块）理想合计 1080 + 间隙 36 = 1116，
    /// 可用 1010 → 走规则 ②。逐字钉住分配结果，并复检「每块 ≥ min」「都不是等分」。
    func testCompressionShrinksProportionallyAboveMinimums() {
        let items = [Self.music, Self.calendar, Self.mirror, Self.moduleBlock]
        let available: CGFloat = 1010
        let plan = HomeStripLayoutMath.plan(items: items, available: available, spacing: Self.spacing)

        // deficit = 1080 − (1010 − 36) = 106；compressible = 120+60+20+60 = 260；scale = 1 − 106/260
        // raw：371.077 / 235.538 / 151.846 / 215.538 → 向下取整到 0.5
        XCTAssertEqual(plan.widths, [371, 235.5, 151.5, 215.5])
        XCTAssertEqual(plan.visibleCount, 4, "够最小宽度和时一块都不丢")
        // 向下取整留下 0.5pt 零头（1010 − 973.5 − 36）：它是 leftover，但块并没有少
        XCTAssertGreaterThan(plan.leftover, 0, "取整零头也是尾部余量")
        XCTAssertLessThanOrEqual(plan.leftover, 0.5 * CGFloat(plan.visibleCount) + 1e-9, "零头不超过 0.5 × 块数")
        XCTAssertEqual(plan.leftover, expectedLeftover(plan, available: available, spacing: Self.spacing), accuracy: 1e-9)
        assertOnHalfPointGrid(plan.widths)
        assertInvariants(plan, available: available, spacing: Self.spacing)

        for (width, item) in zip(plan.widths, items) {
            XCTAssertGreaterThanOrEqual(width, item.min, "压缩后每块不得低于其 min")
            XCTAssertLessThanOrEqual(width, item.ideal, "压缩后每块不得高于其 ideal")
        }

        // 等比（不是等分）：各块「让出的比例」应一致（差额含 < 0.5pt 的取整误差）
        let ratios = zip(plan.widths, items).map { width, item in
            (item.ideal - width) / (item.ideal - item.min)
        }
        for ratio in ratios.dropFirst() {
            XCTAssertEqual(ratio, ratios[0], accuracy: 0.03, "各块按同一比例压缩，实到 \(ratios)")
        }
        XCTAssertEqual(Set(plan.widths).count, 4, "压缩不是等分网格：四块宽度互不相同")
    }

    /// 恰好等于最小宽度和 + 间隙：仍走规则 ②（此时每块恰为 `min`）。
    func testCompressionBoundaryAtMinimumSumKeepsEveryBlock() {
        let items = [Self.music, Self.calendar, Self.mirror]
        let available: CGFloat = 300 + 200 + 140 + Self.spacing * 2  // 664
        let plan = HomeStripLayoutMath.plan(items: items, available: available, spacing: Self.spacing)

        XCTAssertEqual(plan.widths, [300, 200, 140], "恰好够最小宽度和时每块就是 min")
        XCTAssertEqual(plan.visibleCount, 3)
        XCTAssertEqual(plan.leftover, 0, accuracy: 1e-9)
        assertInvariants(plan, available: available, spacing: Self.spacing)
    }

    /// 取整**只准向下**：raw 100.75 → 100.5、raw 100.25 → 100.0，都不得向上进位
    ///（向上取整会让总和越过可用宽度，违反不变量）。
    func testRoundingGoesDownToHalfPointAndNeverUp() {
        let items = [HomeStripLayoutMath.Item(min: 100, ideal: 101), HomeStripLayoutMath.Item(min: 100, ideal: 101)]

        // 可用 201.5：compressible = 2、deficit = 0.5、scale = 0.75 → raw 100.75 → **100.5**
        let loose = HomeStripLayoutMath.plan(items: items, available: 201.5, spacing: 0)
        XCTAssertEqual(loose.widths, [100.5, 100.5], "100.75 向下取整到 100.5（不得进位到 101）")
        // 取整零头 0.5pt（201.5 − 201）留在尾部：它不属于任何块，但仍是未被使用的空间
        XCTAssertEqual(loose.leftover, 0.5, accuracy: 1e-9, "取整零头计入尾部余量")
        XCTAssertEqual(loose.leftover, expectedLeftover(loose, available: 201.5, spacing: 0), accuracy: 1e-9)
        assertOnHalfPointGrid(loose.widths)
        assertInvariants(loose, available: 201.5, spacing: 0)

        // 可用 200.5：deficit = 1.5、scale = 0.25 → raw 100.25 → **100.0**
        let tight = HomeStripLayoutMath.plan(items: items, available: 200.5, spacing: 0)
        XCTAssertEqual(tight.widths, [100, 100], "100.25 向下取整到 100.0")
        XCTAssertEqual(tight.leftover, expectedLeftover(tight, available: 200.5, spacing: 0), accuracy: 1e-9)
        assertInvariants(tight, available: 200.5, spacing: 0)
    }

    // MARK: - 规则 ③：按尾部丢块（D-03）

    /// 连最小宽度和都不够：丢掉**最后一块**（`order` 大的一端），保留前两块的原最小宽度。
    func testDropsTrailingBlockWhenBelowMinimumSum() {
        let items = [Self.music, Self.calendar, Self.mirror]  // min 300 / 200 / 140
        let available: CGFloat = 520  // 三块最小和 + 间隙 = 664 > 520；两块 = 512 ≤ 520
        let plan = HomeStripLayoutMath.plan(items: items, available: available, spacing: Self.spacing)

        XCTAssertEqual(plan.widths, [300, 200], "丢的是尾部那一块（镜子 140），留下的取各自 min")
        XCTAssertEqual(plan.visibleCount, 2)
        // 丢块空出来的空间（520 − 300 − 200 − 12 = 8）也是尾部余量：**不为 0 不代表没铺满**
        XCTAssertEqual(plan.leftover, 8, accuracy: 1e-9, "丢块空出来的空间计入尾部余量")
        XCTAssertGreaterThan(plan.leftover, 0, "丢块路径的 leftover > 0")
        XCTAssertEqual(plan.leftover, expectedLeftover(plan, available: available, spacing: Self.spacing), accuracy: 1e-9)
        XCTAssertFalse(plan.widths.contains(140), "被丢的应是数组最后一项")
        assertInvariants(plan, available: available, spacing: Self.spacing)
    }

    /// 边界：`available` 恰好等于两块最小和 + 一个间隙（512）→ 第二块保住（判定用严格大于）。
    func testDroppingBoundaryKeepsBlockWhoseMinimumExactlyFits() {
        let items = [Self.music, Self.calendar, Self.mirror]
        let plan = HomeStripLayoutMath.plan(items: items, available: 512, spacing: Self.spacing)

        XCTAssertEqual(plan.widths, [300, 200])
        XCTAssertEqual(plan.visibleCount, 2)
        assertInvariants(plan, available: 512, spacing: Self.spacing)
    }

    /// **770pt 面板的三块预算**（2026-09-29 修复轮，实测发现）：块间距 12 → 8 之后，
    /// 音乐 / 日历 / 模块块的最小宽度和 + 两个间隙 = `680 + 16 = 696 ≤ 702`（样本面板 770pt 减去
    /// `ContentView` 两侧各 34pt 的内边距）——三块全部保住；模块块 ≥ 160，待办首页块因此能进
    /// `.compact` 档显示今日标题。改动前 `680 + 24 = 704 > 702`：第三块被规则 ③ 丢掉
    ///（且当时外框不裁剪，屏上留下溢出残影）。
    ///
    /// **注意口径**：`702 > 696` 落在规则 ②，那 6pt 余量**按可压缩量等比分摊**，因此每块略高于
    /// 自己的 `min`（min 是下界、不是取值）；「每块恰好取 `min`」只在可用 = 696 时成立（本用例两段都钉）。
    func testThreeRealBlocksFitAtDefaultPanelBudget() {
        // 宿主现值（`HomeStripView` 的常量；12 → 8 是本次修复的一部分）
        let hostSpacing = HomeStripLayout.spacing
        XCTAssertEqual(hostSpacing, 8, "宿主块间距现值为 8（770pt 三块预算的唯一余量来源）")

        let items = [Self.music, Self.calendar, Self.moduleBlock]  // min 300 / 200 / 180
        let available: CGFloat = 702  // 770pt 面板 − 两侧各 34

        // ① 默认面板：三块都保住（规则 ② 等比分摊余量，逐字钉住分配结果）
        let plan = HomeStripLayoutMath.plan(items: items, available: available, spacing: hostSpacing)
        XCTAssertEqual(plan.visibleCount, 3, "三块都要在默认面板里（改动前是 2）")
        XCTAssertEqual(plan.widths, [303, 201.5, 181.5], "6pt 余量按可压缩量等比分摊；各自 ≥ min、不放大到 ideal")
        XCTAssertEqual(plan.leftover, 0, accuracy: 1e-9, "702 − (303 + 201.5 + 181.5 + 16) = 0")
        XCTAssertGreaterThanOrEqual(plan.widths[2], 160, "第三块 181.5 ≥ 160 → 待办首页块走 .compact 档")
        XCTAssertGreaterThanOrEqual(plan.widths[2], Self.moduleBlock.min, "不得低于声明的最小宽度")
        assertInvariants(plan, available: available, spacing: hostSpacing)

        // ② 恰好等于「最小宽度和 + 间隙」的预算（696）：这里每块**恰好**取自己的 min
        let exact: CGFloat = 696
        let tight = HomeStripLayoutMath.plan(items: items, available: exact, spacing: hostSpacing)
        XCTAssertEqual(tight.visibleCount, 3)
        XCTAssertEqual(tight.widths, [300, 200, 180], "恰好在最小和上：各块取各自 min")
        XCTAssertEqual(tight.leftover, 0, accuracy: 1e-9)
        assertInvariants(tight, available: exact, spacing: hostSpacing)

        // ③ 同一预算下的**四块**（再开一个模块）：容不下 → 尾部那块被规则 ③ 丢弃（设计行为，不是故障）
        let fourBlocks = [Self.music, Self.calendar, Self.moduleBlock, Self.moduleBlock]
        let cramped = HomeStripLayoutMath.plan(items: fourBlocks, available: available, spacing: hostSpacing)
        XCTAssertEqual(cramped.visibleCount, 3, "770pt 只容得下三块（内置两块 + 一个模块块）")
        XCTAssertEqual(cramped.widths, [300, 200, 180], "规则 ③ 路径下留下的三块取各自 min")
        assertInvariants(cramped, available: available, spacing: hostSpacing)
    }

    /// 继续不足时逐块丢到只剩第一块；单块的 `min` 仍放得下就取该 `min`（不走兜底）。
    func testDropsDownToFirstBlockWhenOnlyOneFits() {
        let items = [Self.music, Self.calendar, Self.mirror]
        let plan = HomeStripLayoutMath.plan(items: items, available: 460, spacing: Self.spacing)

        XCTAssertEqual(plan.widths, [300], "只剩第一块时不留间隙（单块不乘 spacing）")
        XCTAssertEqual(plan.visibleCount, 1)
        // 460 里只用掉 300，余下 160 是尾部余量（丢块路径同理）
        XCTAssertEqual(plan.leftover, 160, accuracy: 1e-9, "只剩一块时没用到的宽度也是尾部余量")
        XCTAssertEqual(plan.leftover, expectedLeftover(plan, available: 460, spacing: Self.spacing), accuracy: 1e-9)
        assertInvariants(plan, available: 460, spacing: Self.spacing)
    }

    /// 单块兜底：连第一块的 `min` 都放不下 → 宽度取可用宽度（**不为负**）。
    func testSingleBlockFallbackUsesAvailableWidth() {
        let twoBlocks = [Self.music, Self.calendar]
        let cramped = HomeStripLayoutMath.plan(items: twoBlocks, available: 260, spacing: Self.spacing)
        XCTAssertEqual(cramped.widths, [260], "单块兜底取可用宽度（不是它的 min）")
        XCTAssertEqual(cramped.visibleCount, 1)
        XCTAssertEqual(cramped.leftover, 0, accuracy: 1e-9)
        assertInvariants(cramped, available: 260, spacing: Self.spacing)

        let zero = HomeStripLayoutMath.plan(items: [Self.music], available: 0, spacing: Self.spacing)
        XCTAssertEqual(zero.widths, [0], "可用宽度为 0 时给 0（不得为负）")
        XCTAssertEqual(zero.visibleCount, 1)
        assertInvariants(zero, available: 0, spacing: Self.spacing)
    }

    // MARK: - 尾部预留位（`＋N` 丢块提示，docs/21 §做法 机制一）

    /// ① **不丢块 → 预留位不存在**：基线没丢块时 `tailReserve` 传了也不生效
    ///（`tailReserveUsed == false`、`droppedCount == 0`），宽度分配与不传时**逐字相同**。
    /// 这一条挡的是「不丢块也预留」——那会白占尾部 34pt、把压缩档的宽度分配整个改掉。
    func testTailReserveDoesNothingWhenBaselineKeepsEveryBlock() {
        // 富余档（规则 ①）：宽度就是各自的 ideal、余量留尾部
        let surplusItems = [Self.music, Self.calendar, Self.mirror, Self.moduleBlock]
        let surplusAvailable: CGFloat = 1200
        let surplus = HomeStripLayoutMath.plan(
            items: surplusItems,
            available: surplusAvailable,
            spacing: Self.spacing,
            tailReserve: 34
        )
        XCTAssertEqual(surplus.widths, [420, 260, 160, 240], "不丢块时宽度分配不得因预留位改变")
        XCTAssertEqual(surplus.visibleCount, 4)
        XCTAssertEqual(surplus.droppedCount, 0, "一块都没丢")
        XCTAssertFalse(surplus.tailReserveUsed, "不丢块时预留位不生效")
        // 1200 − 1080 − 36 = 84：未生效的预留位不得从尾部余量里扣走任何东西
        XCTAssertEqual(surplus.leftover, 84, accuracy: 1e-9, "未生效的预留位不得改变 leftover 口径")
        assertInvariants(surplus, available: surplusAvailable, spacing: Self.spacing)
        XCTAssertEqual(
            surplus,
            HomeStripLayoutMath.plan(items: surplusItems, available: surplusAvailable, spacing: Self.spacing),
            "传 / 不传预留位在「不丢块」档必须得到同一份 plan"
        )

        // 压缩档（规则 ②，同样一块都不丢）：预留位不得生效——误扣掉它会让宽度从「等比压缩」
        // 掉到「每块取 min」甚至丢块（fail signal：不丢块时提示把块挤掉）
        let hostSpacing = HomeStripLayout.spacing
        let compressedItems = [Self.music, Self.calendar, Self.moduleBlock]
        let compressedAvailable: CGFloat = 702
        let compressed = HomeStripLayoutMath.plan(
            items: compressedItems,
            available: compressedAvailable,
            spacing: hostSpacing,
            tailReserve: 34
        )
        XCTAssertEqual(compressed.widths, [303, 201.5, 181.5], "压缩档的分配不得因预留位变化")
        XCTAssertEqual(compressed.visibleCount, 3, "压缩档一块都不丢")
        XCTAssertEqual(compressed.droppedCount, 0)
        XCTAssertFalse(compressed.tailReserveUsed)
        assertInvariants(compressed, available: compressedAvailable, spacing: hostSpacing)
    }

    /// ② **生产档（770pt 面板，可用宽 ≈702）**：四个块时基线就丢第 4 块（D-03），
    /// 预留 34pt 后**可见块数不变**（提示只占本来空着的位置）、`tailReserveUsed == true`、
    /// `droppedCount == 1`（条尾显示 `＋1`）。
    ///
    /// 数字与 docs/21 §验收标准 2 逐字对应：`300 + 140 + 180 + 2×8 = 636 ≤ 702`、预留后 `636 ≤ 668`。
    func testTailReserveKeepsVisibleCountAtDefaultPanelBudget() {
        let hostSpacing = HomeStripLayout.spacing
        XCTAssertEqual(hostSpacing, 8, "本用例的数字按宿主块间距 8 算（改它会同时改这些数字）")
        XCTAssertEqual(HomeStripView.droppedHintWidth, 34, "预留位宽度的唯一取值（docs/21 §备选与取舍 ②）")
        XCTAssertEqual(hostSpacing * 2 + 300 + 140 + 180, 636, "三块最小宽度和 + 两个间隙（docs/21 §验收标准 2）")

        // 生产四块：音乐 300/420、镜子 140/160、待办与通知各 180/240（宿主统一宽度）
        let items = [Self.music, Self.mirror, Self.moduleBlock, Self.moduleBlock]
        let available: CGFloat = 702

        // 基线（缺省 = 改动前的行为）：第 4 块被规则 ③ 从尾部丢掉
        let baseline = HomeStripLayoutMath.plan(items: items, available: available, spacing: hostSpacing)
        XCTAssertEqual(baseline.visibleCount, 3, "702 下基线只放得下三块（第 4 块从尾部丢）")
        XCTAssertEqual(baseline.widths, [300, 140, 180], "丢块路径下留下的取各自 min")
        XCTAssertEqual(baseline.droppedCount, 1)
        XCTAssertFalse(baseline.tailReserveUsed)

        // 预留版：可见块数与基线**相同**（提示不得把本可显示的块挤掉）
        let reserved = HomeStripLayoutMath.plan(
            items: items,
            available: available,
            spacing: hostSpacing,
            tailReserve: HomeStripView.droppedHintWidth
        )
        XCTAssertEqual(reserved.visibleCount, 3, "预留位不得把可见块从 3 挤到 2（fail signal）")
        XCTAssertEqual(reserved.widths, baseline.widths, "可见块的宽度逐字不变（同一个 636 预算）")
        XCTAssertEqual(reserved.droppedCount, 1, "条尾显示 ＋1：提示数字 = 真的少显示的块数")
        XCTAssertTrue(reserved.tailReserveUsed, "702 下预留位真的用上了")
        // leftover 按**缩减后**的宽度算：668 − 636 = 32（预留的 34pt 不属于任何块）
        XCTAssertEqual(reserved.leftover, 32, accuracy: 1e-9, "预留版的 leftover 与基线同一个口径")
        assertInvariants(reserved, available: available - HomeStripView.droppedHintWidth, spacing: hostSpacing)
        // 不越界：可见块 + 间隙 + 预留位 ≤ 可用宽度 → 提示位不会压到最后一块上
        XCTAssertLessThanOrEqual(
            reserved.widths.reduce(CGFloat.zero, +) + gaps(3, spacing: hostSpacing) + HomeStripView.droppedHintWidth,
            available,
            "提示位必须落在本来空着的位置里"
        )
    }

    /// ③ **边界档（可用宽 660）**：基线三块，预留 34pt 后**掉到两块**——D-02 的确定行为：
    /// 宁可少显示一块，也要把「还有 N 块」说出来（docs/21 §已知限制 6，不是故障）。
    func testTailReserveMayDropOneMoreBlockAtBoundaryWidth() {
        let hostSpacing = HomeStripLayout.spacing
        let items = [Self.music, Self.mirror, Self.moduleBlock, Self.moduleBlock]
        let available: CGFloat = 660

        let baseline = HomeStripLayoutMath.plan(items: items, available: available, spacing: hostSpacing)
        XCTAssertEqual(baseline.visibleCount, 3, "660 下基线放得下三块（636 ≤ 660）")
        XCTAssertEqual(baseline.widths, [300, 140, 180])
        XCTAssertEqual(baseline.droppedCount, 1)
        XCTAssertFalse(baseline.tailReserveUsed)
        XCTAssertEqual(baseline.leftover, 24, accuracy: 1e-9)  // 660 − 636

        let reserved = HomeStripLayoutMath.plan(
            items: items,
            available: available,
            spacing: hostSpacing,
            tailReserve: HomeStripView.droppedHintWidth
        )
        XCTAssertEqual(reserved.visibleCount, 2, "预留 34pt 后尾部再让出一块（docs/21 §已知限制 6）")
        XCTAssertEqual(reserved.widths, [300, 140], "少显示的那一块从尾部掉（留下的仍取各自 min）")
        XCTAssertEqual(reserved.droppedCount, 2, "被丢块数与提示数字同一个来源")
        XCTAssertTrue(reserved.tailReserveUsed)
        // 626 − 448 = 178
        XCTAssertEqual(reserved.leftover, 178, accuracy: 1e-9)
        assertInvariants(reserved, available: available - HomeStripView.droppedHintWidth, spacing: hostSpacing)
        XCTAssertLessThan(
            reserved.visibleCount,
            baseline.visibleCount,
            "这一档就是「预留位可能多丢一块」的现场（已知限制 6，提示优先于多显示一块）"
        )
    }

    /// ④ **`tailReserve` 缺省 0 = 改动前的行为**：缺省、显式 `0`、负值三条路径得到**同一份 plan**
    ///（`tailReserveUsed == false`；`droppedCount` 就是真实的丢块数）。
    func testTailReserveDefaultsToNoReserve() {
        let cases: [(items: [HomeStripLayoutMath.Item], available: CGFloat, spacing: CGFloat)] = [
            ([Self.music, Self.calendar, Self.mirror, Self.moduleBlock], 1200, Self.spacing),  // 规则 ①
            ([Self.music, Self.calendar, Self.mirror, Self.moduleBlock], 1010, Self.spacing),  // 规则 ②
            ([Self.music, Self.calendar, Self.mirror], 520, Self.spacing),                     // 规则 ③（丢块）
            ([Self.music, Self.mirror, Self.moduleBlock, Self.moduleBlock], 702, HomeStripLayout.spacing),
            ([], 1010, Self.spacing),                                                          // 空数组
        ]

        for itemCase in cases {
            let defaulted = HomeStripLayoutMath.plan(
                items: itemCase.items,
                available: itemCase.available,
                spacing: itemCase.spacing
            )
            let explicitZero = HomeStripLayoutMath.plan(
                items: itemCase.items,
                available: itemCase.available,
                spacing: itemCase.spacing,
                tailReserve: 0
            )
            let negative = HomeStripLayoutMath.plan(
                items: itemCase.items,
                available: itemCase.available,
                spacing: itemCase.spacing,
                tailReserve: -HomeStripView.droppedHintWidth
            )

            XCTAssertEqual(defaulted, explicitZero, "缺省 0 与显式 0 必须是同一份 plan")
            XCTAssertEqual(negative, defaulted, "`<= 0` 视为不预留（负值不得开启预留位）")
            XCTAssertFalse(defaulted.tailReserveUsed, "不预留时永不占用尾位")
            XCTAssertEqual(
                defaulted.droppedCount,
                itemCase.items.count - defaulted.visibleCount,
                "droppedCount 的口径恒为 items.count − visibleCount"
            )
            assertInvariants(defaulted, available: itemCase.available, spacing: itemCase.spacing)
        }
    }

    // MARK: - 空数组与 spacing 口径

    /// 空数组：没有块、也没有块宽，可用宽度**原样**留给尾部；`spacing` 不参与。
    func testEmptyItemsLeaveAllAvailableAsLeftover() {
        let empty = HomeStripLayoutMath.plan(items: [], available: 1010, spacing: Self.spacing)
        XCTAssertTrue(empty.widths.isEmpty)
        XCTAssertEqual(empty.visibleCount, 0)
        XCTAssertEqual(empty.leftover, 1010, accuracy: 1e-9)
        assertInvariants(empty, available: 1010, spacing: Self.spacing)

        let zero = HomeStripLayoutMath.plan(items: [], available: 0, spacing: 0)
        XCTAssertEqual(zero.visibleCount, 0)
        XCTAssertEqual(zero.leftover, 0, accuracy: 1e-9)
    }

    /// `spacing == 0`：块紧贴，判定与取整只跟宽度有关；与同一输入下 `spacing == 12` 的结果不同。
    func testZeroSpacingRemovesGapFromEveryDecision() {
        let items = [HomeStripLayoutMath.Item(min: 100, ideal: 200), HomeStripLayoutMath.Item(min: 100, ideal: 200)]

        // 恰好放满（无间隙时 400 就是理想和）
        let exact = HomeStripLayoutMath.plan(items: items, available: 400, spacing: 0)
        XCTAssertEqual(exact.widths, [200, 200])
        XCTAssertEqual(exact.leftover, 0, accuracy: 1e-9)
        assertInvariants(exact, available: 400, spacing: 0)

        // 压缩：deficit = 400 − 350 = 50、compressible = 200、scale = 0.75 → 175 / 175
        let compressed = HomeStripLayoutMath.plan(items: items, available: 350, spacing: 0)
        XCTAssertEqual(compressed.widths, [175, 175])
        XCTAssertEqual(compressed.leftover, 0, accuracy: 1e-9)
        assertInvariants(compressed, available: 350, spacing: 0)

        // 同一可用宽度下加了间隙 → 要压得更狠（deficit = 400 − (350 − 12) = 62 → scale 0.69）
        let withGap = HomeStripLayoutMath.plan(items: items, available: 350, spacing: Self.spacing)
        XCTAssertEqual(withGap.widths, [169, 169], "间隙只存在于块与块之间，压缩时要把它让出来")
        assertInvariants(withGap, available: 350, spacing: Self.spacing)

        // 丢块判定也按无间隙口径：150 < 200（两块最小和）→ 只剩第一块
        let dropped = HomeStripLayoutMath.plan(items: items, available: 150, spacing: 0)
        XCTAssertEqual(dropped.widths, [100])
        XCTAssertEqual(dropped.visibleCount, 1)
        assertInvariants(dropped, available: 150, spacing: 0)
    }

    /// **单块不乘 `spacing`**：一块时没有间隙可让，`available` 就是它能用的全部宽度。
    func testSingleBlockPaysNoSpacing() {
        let items = [HomeStripLayoutMath.Item(min: 100, ideal: 200)]
        let plan = HomeStripLayoutMath.plan(items: items, available: 150, spacing: Self.spacing)

        XCTAssertEqual(plan.widths, [150], "单块的宽度就是可用宽度（若误乘 spacing 会给出 138）")
        XCTAssertEqual(plan.visibleCount, 1)
        XCTAssertEqual(plan.leftover, 0, accuracy: 1e-9)
        assertInvariants(plan, available: 150, spacing: Self.spacing)
    }

    // MARK: - 不变量批量复检

    /// 在代表性预算上扫一遍：三条不变量恒成立；「富余 ⟺ 走规则 ①」的判据也要对得上
    ///（富余时宽度就是 ideal）；`leftover` 一律等于「未被使用的尾部空间总量」。
    func testInvariantsHoldAcrossRepresentativeBudgets() {
        let itemSets: [[HomeStripLayoutMath.Item]] = [
            [Self.music, Self.calendar, Self.mirror, Self.moduleBlock],
            [Self.music, Self.calendar],
            [Self.music],
            [HomeStripLayoutMath.Item(min: 100, ideal: 200), HomeStripLayoutMath.Item(min: 100, ideal: 200)],
        ]
        let budgets: [CGFloat] = [0, 50, 100, 140, 200, 260, 500, 512, 664, 856, 1010, 1116, 1200, 1500]
        let spacings: [CGFloat] = [0, Self.spacing, 40]

        for items in itemSets {
            let sumIdeal = items.reduce(CGFloat.zero) { $0 + $1.ideal }
            let sumMin = items.reduce(CGFloat.zero) { $0 + $1.min }
            for spacing in spacings {
                for available in budgets {
                    let plan = HomeStripLayoutMath.plan(items: items, available: available, spacing: spacing)
                    assertInvariants(plan, available: available, spacing: spacing)
                    let gapTotal = gaps(items.count, spacing: spacing)

                    if available >= sumIdeal + gapTotal {
                        XCTAssertEqual(plan.widths, items.map(\.ideal), "富余时宽度应逐字等于 ideal")
                        XCTAssertEqual(plan.visibleCount, items.count)
                    }
                    // `leftover` 三条规则同一个口径（非富余路径完全可以 > 0，例如丢块之后）
                    XCTAssertEqual(
                        plan.leftover,
                        expectedLeftover(plan, available: available, spacing: spacing),
                        accuracy: 1e-9,
                        "leftover 应是未使用的尾部空间（available \(available)，spacing \(spacing)）"
                    )

                    if available >= sumMin + gapTotal {
                        XCTAssertEqual(plan.visibleCount, items.count, "够最小宽度和时一块都不丢")
                        for (width, item) in zip(plan.widths, items) {
                            XCTAssertGreaterThanOrEqual(width, item.min)
                            XCTAssertLessThanOrEqual(width, item.ideal)
                        }
                    } else if plan.visibleCount >= 2 {
                        XCTAssertEqual(plan.widths, items.prefix(plan.visibleCount).map(\.min), "丢块后留下的取各自 min")
                    } else {
                        XCTAssertEqual(plan.widths.count, 1)
                        XCTAssertLessThanOrEqual(plan.widths[0], max(0, available) + 1e-9)
                    }
                }
            }
        }
    }

    // MARK: - `Surface.home`

    /// 词汇表：`home` 排在既有三个取值之后，保序解码（新增取值不改既有语义）。
    func testSurfaceVocabularyAndDecodingCarryHome() throws {
        XCTAssertEqual(Surface.allCases.map(\.rawValue), ["compact", "expanded", "lockscreen", "home"])
        XCTAssertEqual(Surface.home.rawValue, "home")

        let decoded = try JSONDecoder().decode(
            [Surface].self,
            from: Data(#"["compact","expanded","lockscreen","home"]"#.utf8)
        )
        XCTAssertEqual(decoded, [.compact, .expanded, .lockscreen, .home], "解码保序且四个取值都在")
    }

    /// 首页块请求的形状（docs/17 §接口与数据形状 2）：**宽度不由请求传递**。
    func testHomeRequestShapeCarriesNoWidth() {
        let request = ModuleRegistry.home

        XCTAssertEqual(request.surface, .home)
        XCTAssertEqual(request.phase, .expanded)
        XCTAssertNil(request.slot, "首页没有槽位语义（Slot 只在 compact 时有意义）")
        XCTAssertEqual(request.sizeHint, .zero, "块宽由 SwiftUI 提案 / 布局纯函数决定，请求不带宽度")
        XCTAssertEqual(request.reason, .initial, "与宿主既有口径一致：尚未记录「第几次评估」")
        XCTAssertFalse(request.isLowPower)
    }

    // MARK: - `homeEntries` 投影

    /// 注册一批假模块（含 `.home` / 只 `.expanded` / 抛错 / 被禁用），覆盖投影的三条过滤与排序：
    /// 只收 `active` 且声明 `.home`；顺序与 `tabEntries` **同一比较器**（`(order, id)` 升序，
    /// `order` 缺省 `Int.max` 排最后）；`label` / `symbolName` 复用既有解析。
    func testHomeEntriesFilterAndOrderMatchTabEntriesComparator() async {
        let registry = ModuleRegistry.shared
        registerProbes([
            HomeAlphaProbeModule.self,     // .home + .expanded，order 10
            HomeGammaProbeModule.self,     // .home + .expanded，order 10（同序 → 比 id）
            HomeBetaProbeModule.self,      // .home + .expanded，order 5
            HomeNoPlacementProbeModule.self,  // .home + .expanded，无 placement → Int.max
            HomeOnlyProbeModule.self,      // 只声明 .home，order 1
            ExpandedOnlyProbeModule.self,  // 只声明 .expanded，order 1
            HomeFailedProbeModule.self,    // .home，但 activate() 抛错 → failed
            HomeOptInProbeModule.self,     // .home，defaultEnabled = false → disabled
        ])

        // 注册了但尚未 bootstrap：没有 active 的候选
        XCTAssertTrue(registry.homeEntries.isEmpty, "未 bootstrap 时不应有首页块")

        await registry.bootstrap()

        let prefix = "com.cmeng.gourd."
        XCTAssertEqual(registry.homeEntries.map(\.id), [
            "\(prefix)probe-home-only",   // order 1
            "\(prefix)probe-home-beta",   // order 5
            "\(prefix)probe-home-alpha",  // order 10，与 gamma 同序 → id 字典序在前
            "\(prefix)probe-home-gamma",  // order 10
            "\(prefix)probe-home-nop",    // 无 placement → Int.max，排最后
        ])
        XCTAssertEqual(registry.homeEntries.map(\.order), [1, 5, 10, 10, Int.max])

        // 不得入选的三类：failed / disabled / 只声明 .expanded
        for id in ["\(prefix)probe-home-failed", "\(prefix)probe-home-optin", "\(prefix)probe-expanded-only"] {
            XCTAssertFalse(registry.homeEntries.contains { $0.id == id }, "\(id) 不应进首页块投影")
        }

        // 排序口径与 tabEntries 一致：同时进两条投影的模块，相对顺序完全相同
        let homeIDs = registry.homeEntries.map(\.id)
        let tabIDs = registry.tabEntries.map(\.id)
        let sharedIDs = Set(homeIDs).intersection(tabIDs)
        XCTAssertEqual(
            homeIDs.filter { sharedIDs.contains($0) },
            tabIDs.filter { sharedIDs.contains($0) },
            "两条投影共用 (order, id) 比较器，公共子集的相对顺序必须一致"
        )

        // label / symbolName 复用既有解析：key 形态取不到译文回落 shortID，locale 表形态取表值
        let gamma = registry.homeEntries.first { $0.id == "\(prefix)probe-home-gamma" }
        XCTAssertEqual(gamma?.label, "Gamma Home", "localized table 形态应取表值")
        XCTAssertEqual(registry.homeEntries.first?.label, "probe-home-only", "key 形态取不到译文时回落 shortID")
        XCTAssertEqual(registry.homeEntries.first?.symbolName, "square")

        // 投影是现算的（不缓存）：清空注册表后立刻为空
        await registry.deactivateAll()
        XCTAssertTrue(registry.homeEntries.isEmpty, "deactivateAll() 之后投影应为空（现算、不缓存）")
    }

    // MARK: - 首页两排的高度取舍（T2 / docs/23-home-fit.md §做法 机制二）

    /// 生产档的四个入参（与 `NotchHomeView.standardHomeContent` 传的逐字同源）：日历行固定档 294、
    /// 两排间距 8、strip 最小可用高度 152。
    private static let calendarRowHeight: CGFloat = HomeCalendarRow.rowHeight
    private static let rowSpacing: CGFloat = HomeCalendarRow.rowSpacing
    private static let stripMinimumHeight: CGFloat = HomeStripView.minimumUsableHeight

    /// 两排一起放得下的**最低高度**（= 152 + 8 + 294 = 454）——下面的边界断言都由它派生，
    /// 免得三处各写一个数。
    private static let bothMinimumHeight: CGFloat = stripMinimumHeight + rowSpacing + calendarRowHeight

    /// 阈值链的锚点：四个常量任一被改动，本用例先红——边界数值要跟着一起重新审，而不是静默漂。
    func testVerticalFitThresholdsArePinned() {
        XCTAssertEqual(Self.calendarRowHeight, 294, "日历行固定档（HomeCalendarRow.rowHeight 的算式见那边注释）")
        XCTAssertEqual(Self.rowSpacing, 8)
        XCTAssertEqual(Self.stripMinimumHeight, 152)
        XCTAssertEqual(Self.bothMinimumHeight, 454, "152 + 8 + 294：两排一起放得下的最低高度")
    }

    /// `.both` 档（默认面板高度）：日历行在，strip 拿剩下的（= 改动前的算式，逐字未变）。
    func testBothLayoutKeepsCalendarRowAndShrinksStrip() {
        let plan = HomeVerticalFit.plan(
            available: 582,
            calendarRowHeight: Self.calendarRowHeight,
            rowSpacing: Self.rowSpacing,
            stripMinimumHeight: Self.stripMinimumHeight
        )

        XCTAssertEqual(plan.layout, .both)
        XCTAssertTrue(plan.showsStrip)
        XCTAssertTrue(plan.showsCalendarRow)
        XCTAssertEqual(plan.stripHeight, 582 - 294 - 8, "strip 拿扣掉日历行与间距的剩余（280）")
    }

    /// `.both` 的**下边界**：`available` 恰好等于 454 时两排仍都在，strip 恰好拿到它的最小可用高度
    ///（闭区间：恰好放得下算放得下）。
    func testBothLayoutBoundaryAtExactCombinedMinimum() {
        let plan = HomeVerticalFit.plan(
            available: Self.bothMinimumHeight,
            calendarRowHeight: Self.calendarRowHeight,
            rowSpacing: Self.rowSpacing,
            stripMinimumHeight: Self.stripMinimumHeight
        )

        XCTAssertEqual(plan.layout, .both, "恰好等于阈值算放得下（不留一条只有 0.0001pt 宽的缝）")
        XCTAssertEqual(plan.stripHeight, Self.stripMinimumHeight, "恰好放满：strip 拿到 152")
        XCTAssertTrue(plan.showsCalendarRow)
    }

    /// `.both` 下一点（454 − 1 = 453）：**让位的是日历行**，strip 拿全部可用高度
    /// ——这是本次改动的核心判据（D-02），也是改动前会画反的那一档。
    func testCalendarRowGivesWayJustBelowCombinedMinimum() {
        let plan = HomeVerticalFit.plan(
            available: Self.bothMinimumHeight - 1,
            calendarRowHeight: Self.calendarRowHeight,
            rowSpacing: Self.rowSpacing,
            stripMinimumHeight: Self.stripMinimumHeight
        )

        XCTAssertEqual(plan.layout, .stripOnly)
        XCTAssertFalse(plan.showsCalendarRow, "两排一起放不下 → 收起日历行（D-02）")
        XCTAssertTrue(plan.showsStrip, "strip 仍在（改动前这一档整条不画）")
        XCTAssertEqual(plan.stripHeight, 453, "stripOnly 档 strip 拿**全部**可用高度，不是扣掉日历行的剩余")
    }

    /// `.stripOnly` 的**整个高度带**（152…453）：日历行全程不在、strip 全程都在且拿全部高度。
    /// 逐个高度过一遍，是为了钉住「这一档里的任何一个高度都不会把 strip 也收掉」。
    func testStripOnlyBandKeepsStripAndDropsCalendarRow() {
        for available in [CGFloat(453), 400, 300, 200, 152] {
            let plan = HomeVerticalFit.plan(
                available: available,
                calendarRowHeight: Self.calendarRowHeight,
                rowSpacing: Self.rowSpacing,
                stripMinimumHeight: Self.stripMinimumHeight
            )

            XCTAssertEqual(plan.layout, .stripOnly, "可用高度 \(available) 应落在 stripOnly 档")
            XCTAssertTrue(plan.showsStrip, "strip 在 \(available) 应仍在")
            XCTAssertFalse(plan.showsCalendarRow, "日历行在 \(available) 应已让位")
            XCTAssertEqual(plan.stripHeight, available, "strip 在 \(available) 应拿全部可用高度")
            XCTAssertGreaterThanOrEqual(plan.stripHeight, Self.stripMinimumHeight, "strip 的高度不低于它的最小可用高度")
        }
    }

    /// `.stripOnly` 的**下边界**：`available` 恰好等于 strip 最小可用高度（152）时 strip 仍画
    ///（闭区间），它在这一档拿到的高度就等于阈值本身。
    func testStripOnlyBoundaryAtExactStripMinimum() {
        let plan = HomeVerticalFit.plan(
            available: Self.stripMinimumHeight,
            calendarRowHeight: Self.calendarRowHeight,
            rowSpacing: Self.rowSpacing,
            stripMinimumHeight: Self.stripMinimumHeight
        )

        XCTAssertEqual(plan.layout, .stripOnly, "恰好等于 strip 最小可用高度算放得下")
        XCTAssertTrue(plan.showsStrip)
        XCTAssertEqual(plan.stripHeight, Self.stripMinimumHeight)
        XCTAssertFalse(plan.showsCalendarRow)
    }

    /// `.calendarOnly` 档（152 以下）：strip 整条不画；生产档下日历行（294）也放不下 → 两排都不画。
    func testCalendarOnlyBelowStripMinimumDrawsNothingAtProductionHeights() {
        let plan = HomeVerticalFit.plan(
            available: Self.stripMinimumHeight - 0.1,
            calendarRowHeight: Self.calendarRowHeight,
            rowSpacing: Self.rowSpacing,
            stripMinimumHeight: Self.stripMinimumHeight
        )

        XCTAssertEqual(plan.layout, .calendarOnly)
        XCTAssertFalse(plan.showsStrip, "strip 连最小可用高度都放不下 → 整条不画（「画不满就不画」的既有裁决）")
        XCTAssertEqual(plan.stripHeight, 0, "不画时不占高度（不是负值、不是残高）")
        XCTAssertFalse(plan.showsCalendarRow, "生产档日历行要 294，151.9 放不下 → 这一档什么都不画")
    }

    /// `.calendarOnly` 档**画日历行**的那半边判据：日历年行比 strip 阈值矮时（用合成入参——生产档
    /// 294 > 152，这一支在真机上到不了），strip 仍不画、日历行画。
    func testCalendarOnlyDrawsCalendarRowWhenItsHeightFits() {
        let plan = HomeVerticalFit.plan(
            available: 120,
            calendarRowHeight: 100,
            rowSpacing: 8,
            stripMinimumHeight: Self.stripMinimumHeight
        )

        XCTAssertEqual(plan.layout, .calendarOnly)
        XCTAssertFalse(plan.showsStrip)
        XCTAssertTrue(plan.showsCalendarRow, "行高 100 在 120 里放得下 → 这一档画日历行")
    }

    /// 退化输入：`available == 0` 与负值都判成「什么都不画」，且两者结果一致（负值按 0 处理，
    /// 不产生负高度）。
    func testZeroAndNegativeAvailableDrawNothing() {
        let zero = HomeVerticalFit.plan(
            available: 0,
            calendarRowHeight: Self.calendarRowHeight,
            rowSpacing: Self.rowSpacing,
            stripMinimumHeight: Self.stripMinimumHeight
        )
        XCTAssertEqual(zero.layout, .calendarOnly)
        XCTAssertFalse(zero.showsStrip)
        XCTAssertFalse(zero.showsCalendarRow)

        let negative = HomeVerticalFit.plan(
            available: -40,
            calendarRowHeight: Self.calendarRowHeight,
            rowSpacing: Self.rowSpacing,
            stripMinimumHeight: Self.stripMinimumHeight
        )
        XCTAssertEqual(negative, zero, "负的可用高度与 0 等价（布局退化时不出现负高度）")
    }

    /// 日历行关掉时（接缝把行高与间距都按 0 传）不存在取舍：只要 strip 放得下，它就拿**全部**可用
    /// 高度（与改动前 `showCalendar == false` 那一支逐字同口径）。
    func testCalendarRowDisabledHandsAllHeightToStrip() {
        for available in [CGFloat(152), 300, 453, 454, 850] {
            let plan = HomeVerticalFit.plan(
                available: available,
                calendarRowHeight: 0,
                rowSpacing: 0,
                stripMinimumHeight: Self.stripMinimumHeight
            )

            XCTAssertTrue(plan.showsStrip, "关掉日历行后 \(available) 应仍画 strip")
            XCTAssertEqual(plan.stripHeight, available, accuracy: 1e-9, "strip 应拿全部可用高度")
        }

        let belowMinimum = HomeVerticalFit.plan(
            available: Self.stripMinimumHeight - 1,
            calendarRowHeight: 0,
            rowSpacing: 0,
            stripMinimumHeight: Self.stripMinimumHeight
        )
        XCTAssertFalse(belowMinimum.showsStrip, "低于阈值仍整条不画（阈值与日历行开不开无关）")
    }

    /// **顺序反转的正面判据**（D-02）：可用高度从 850 一路降到 140，**先消失的是日历行**（454 下一点
    /// 的 453），strip 一路撑到 152 以下才让位。改动前是反的（strip 先死、日历行到最后都画着）。
    func testReversalOrderCalendarRowDisappearsBeforeStrip() {
        var calendarRowDroppedAt: CGFloat?
        var stripDroppedAt: CGFloat?

        for available in stride(from: CGFloat(850), through: 140, by: -1) {
            let plan = HomeVerticalFit.plan(
                available: available,
                calendarRowHeight: Self.calendarRowHeight,
                rowSpacing: Self.rowSpacing,
                stripMinimumHeight: Self.stripMinimumHeight
            )
            if !plan.showsCalendarRow, calendarRowDroppedAt == nil { calendarRowDroppedAt = available }
            if !plan.showsStrip, stripDroppedAt == nil { stripDroppedAt = available }
        }

        XCTAssertEqual(calendarRowDroppedAt, 453, "日历行应在 454 的下一点（453）先消失")
        XCTAssertEqual(stripDroppedAt, 151, "strip 应一直撑到 strip 最小可用高度之下（151）才让位")
        XCTAssertGreaterThan(
            calendarRowDroppedAt ?? -1,
            stripDroppedAt ?? -1,
            "日历行必须先于 strip 消失（顺序反了就是 D-02 没落地）"
        )
    }

    // MARK: - 面板宽度下的摆放（T4：被判为可见的块必须真的画出来）

    /// **770pt 面板的复现固化**（T4，docs/23-home-fit.md §做法 机制四 / §验收标准 4）。
    ///
    /// 探针实测的机制（`.workflow/p2-home-fit/evidence/probe-770/`）：`HomeStripLayout` 上报的宽度是
    /// 「可见块宽 + 间隙」——丢块路径下它比可用宽窄（770pt 面板：可用 702 → 上报 488）。SwiftUI 的
    /// **下一趟布局会拿这个上报宽度再问它一次**（尺寸反馈）；没有 `HomeStripView` 里那句「提案宽钉在
    /// 可用宽上」时，第二趟按 488 重算 plan，预留 34pt 的 ＋N 位后 `visibleCount` 从 2 掉到 1——
    /// 屏上只剩第一块，而视图那份（按 702 算）仍显示 ＋2。用户看到的就是「只显示播放器、右侧空着」。
    ///
    /// 判据是**渲染真值**：每块拿到的尺寸（`GeometryReader` 上报）必须与 plan 一一对上——
    /// 可见块拿到 plan 的分配宽 + strip 满高，被丢的块是零尺寸，空白块数等于 `droppedCount`。
    /// 修复前这一条会红（变异：把 `HomeStripView` 的 `.frame(width: available, …)` 去掉即可复现）。
    func testMinimumPanelWidthGivesEveryPlanVisibleBlockItsWidth() async {
        homeBlockSizeLog.reset()
        registerProbes([
            HomeWideProbeModule.self,
            HomeNarrowAProbeModule.self,
            HomeNarrowBProbeModule.self,
            HomeNarrowCProbeModule.self,
        ])
        await ModuleRegistry.shared.bootstrap()

        let items = Self.productionFourBlockItems
        let available = Self.panelWidth770StripWidth
        let height: CGFloat = 212
        let plan = HomeStripLayoutMath.plan(
            items: items,
            available: available,
            spacing: HomeStripLayout.spacing,
            tailReserve: HomeStripView.droppedHintWidth
        )

        // 锚：先把「这道题该是什么答案」钉住（数值变了要有人复核，而不是被断言静默吸收）
        XCTAssertEqual(available, 702, "770pt 面板的 strip 可用宽 = 770 − 两侧各 34（docs/17 §接口与数据形状 6）")
        XCTAssertEqual(plan.visibleCount, 2, "四块（音乐档 300/420 + 三个模块档 180/240）在 702 下只放得下两块")
        XCTAssertEqual(plan.droppedCount, 2, "剩下两块靠条尾 ＋2 提示（docs/21）")
        XCTAssertTrue(plan.tailReserveUsed)

        renderRealHomeStrip(available: available, height: height)

        assertRenderedSizesMatchPlan(plan, height: height)
    }

    /// 三个面板宽度各过一遍（770 / 900 / 1088 → strip 可用宽 702 / 832 / 1020）：**任何宽度下
    /// 「拿到尺寸的块 == plan 的 visibleCount」**，且宽度与 plan 的分配宽一致。
    ///
    /// 900（可用 832）是「＋1 + 两块可见」那一档（丢块路径 + 预留位），也是修复前唯一还会
    /// **＋N 与实际不符**的中间档；1088（可用 1020）走规则 ②（全可见、无提示），是防过度修复的对照。
    func testEveryPlanVisibleBlockGetsItsWidthAcrossPanelWidths() async {
        registerProbes([
            HomeWideProbeModule.self,
            HomeNarrowAProbeModule.self,
            HomeNarrowBProbeModule.self,
            HomeNarrowCProbeModule.self,
        ])
        await ModuleRegistry.shared.bootstrap()

        let items = Self.productionFourBlockItems
        let height: CGFloat = 212
        for (panelWidth, expectedVisible) in [(CGFloat(770), 2), (900, 3), (1088, 4)] {
            homeBlockSizeLog.reset()
            let available = panelWidth - 68
            let plan = HomeStripLayoutMath.plan(
                items: items,
                available: available,
                spacing: HomeStripLayout.spacing,
                tailReserve: HomeStripView.droppedHintWidth
            )

            XCTAssertEqual(plan.visibleCount, expectedVisible, "面板 \(panelWidth)pt（可用 \(available)）的可见块数")
            XCTAssertEqual(plan.droppedCount, items.count - expectedVisible)
            XCTAssertEqual(plan.tailReserveUsed, plan.droppedCount > 0, "丢块才用预留位")

            renderRealHomeStrip(available: available, height: height)
            assertRenderedSizesMatchPlan(plan, height: height)
        }
    }

    /// 渲染真值与 plan 的逐块对照：可见块 = 分配宽 + 满高；被丢的块 = 零尺寸；空白块数 == `droppedCount`。
    private func assertRenderedSizesMatchPlan(
        _ plan: HomeStripLayoutMath.Plan,
        height: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let ids = HomeSizedProbeModule.ids
        XCTAssertEqual(ids.count, plan.widths.count + plan.droppedCount, "夹具块数应与 plan 的输入块数一致", file: file, line: line)

        for (index, id) in ids.enumerated() {
            let size = homeBlockSizeLog.size(of: id)
            if index < plan.visibleCount {
                XCTAssertEqual(
                    size.width, plan.widths[index], accuracy: 0.5,
                    "第 \(index) 块（\(id)）应拿到 plan 的分配宽 \(plan.widths[index])，实到 \(size.width)（「被判可见却没画出来」= T4 的复现）",
                    file: file, line: line
                )
                XCTAssertEqual(size.height, height, accuracy: 0.5, "可见块应拿满 strip 高", file: file, line: line)
            } else {
                XCTAssertEqual(
                    size, .zero,
                    "第 \(index) 块（\(id)）被 plan 丢掉 → 必须是零尺寸（显式 `.zero` 提案），实到 \(size)",
                    file: file, line: line
                )
            }
        }

        let blanks = ids.filter { homeBlockSizeLog.size(of: $0) == .zero }
        XCTAssertEqual(
            blanks.count, plan.droppedCount,
            "条尾 ＋\(plan.droppedCount) 与实际空白块数必须一致（实到空白 \(blanks.count) 块：\(blanks)）",
            file: file, line: line
        )
    }

    /// 把**真的 `HomeStripView`** 放进 `NSHostingView` 跑一趟布局：尺寸反馈只在真布局里发生
    /// （纯函数测不到，探针脚本已验证），因此这里必须挂真视图而不是复刻一份结构——复刻的话，
    /// 被测的就成了复刻件，`HomeStripView` 里那句修复反而是「测外之物」。
    private func renderRealHomeStrip(available: CGFloat, height: CGFloat) {
        let host = NSHostingView(rootView: HomeStripHost().frame(width: available, height: height))
        host.frame = CGRect(x: 0, y: 0, width: available, height: height)
        host.layoutSubtreeIfNeeded()
    }

    /// 挂载壳：`HomeStripView` 要一条 matchedGeometry 命名空间（宿主本来是 `ContentView` 给的）。
    private struct HomeStripHost: View {
        @Namespace private var albumArtNamespace

        var body: some View {
            HomeStripView(albumArtNamespace: albumArtNamespace)
        }
    }

    // MARK: - 夹具

    /// 与 `ModuleKernelTests` 的注册口径一致：启用门是 `manifests[id]?.defaultEnabled ?? false`
    ///（06 §2.2 缺省 false）。
    private func registerProbes(_ types: [any GourdModule.Type]) {
        ModuleRegistry.shared.register(types, enabled: { ModuleRegistry.shared.manifests[$0]?.defaultEnabled ?? false })
    }

    /// 用例间的注册表隔离（注册表是单例，`manifests` / `states` 不清会互相污染）。
    override func setUp() async throws {
        try await super.setUp()
        await ModuleRegistry.shared.deactivateAll()
    }

    override func tearDown() async throws {
        await ModuleRegistry.shared.deactivateAll()
        try await super.tearDown()
    }
}

// MARK: - 假模块（文件私有）

/// 假模块的 manifest 工厂：字面量构造（与 `ModuleKernelTests` 同一口径，不走 JSON 解码）。
private enum HomeStripFixture {
    static func manifest(
        shortID: String,
        surfaces: [Surface],
        order: Int? = nil,
        name: LocalizedText? = nil,
        defaultEnabled: Bool = true
    ) -> ModuleManifest {
        ModuleManifest(
            manifestVersion: 1,
            id: "com.cmeng.gourd.\(shortID)",
            name: name ?? LocalizedText(key: "module.\(shortID).name"),
            summary: nil,
            icon: IconSpec(type: "symbol", name: "square"),
            version: "1.0.0",
            apiVersion: HostInfo.currentAPIVersion,
            kind: "builtin",
            surfaces: surfaces,
            defaultPlacement: order.map { Placement(slot: .center, order: $0) },
            defaultEnabled: defaultEnabled,
            permissions: [],
            config: nil
        )
    }
}

/// 假模块基线：`activate()` 不抛错、`content(for:)` 答 `.none`。
@MainActor
private class HomeProbeModule: GourdModule {
    class var manifest: ModuleManifest { HomeStripFixture.manifest(shortID: "probe-home", surfaces: [.home]) }

    required init(context: ModuleContext) {}

    func activate() async throws {}

    func deactivate() async {}

    func content(for request: ContentRequest) -> ModuleContent { .none }
}

/// order 10、`.home` + `.expanded`
private final class HomeAlphaProbeModule: HomeProbeModule {
    override class var manifest: ModuleManifest {
        HomeStripFixture.manifest(shortID: "probe-home-alpha", surfaces: [.home, .expanded], order: 10)
    }
}

/// order 10（与 alpha 同序 → 比 id 字典序）+ name 用 locale 表形态
private final class HomeGammaProbeModule: HomeProbeModule {
    override class var manifest: ModuleManifest {
        HomeStripFixture.manifest(
            shortID: "probe-home-gamma",
            surfaces: [.home, .expanded],
            order: 10,
            name: LocalizedText(table: ["en": "Gamma Home"])
        )
    }
}

/// order 5
private final class HomeBetaProbeModule: HomeProbeModule {
    override class var manifest: ModuleManifest {
        HomeStripFixture.manifest(shortID: "probe-home-beta", surfaces: [.home, .expanded], order: 5)
    }
}

/// 无 `defaultPlacement`（order = `Int.max`）
private final class HomeNoPlacementProbeModule: HomeProbeModule {
    override class var manifest: ModuleManifest {
        HomeStripFixture.manifest(shortID: "probe-home-nop", surfaces: [.home, .expanded])
    }
}

/// 只声明 `.home`（不进 tab 投影，但进首页块投影）
private final class HomeOnlyProbeModule: HomeProbeModule {
    override class var manifest: ModuleManifest {
        HomeStripFixture.manifest(shortID: "probe-home-only", surfaces: [.home], order: 1)
    }
}

/// 只声明 `.expanded`（不得进首页块投影）
private final class ExpandedOnlyProbeModule: HomeProbeModule {
    override class var manifest: ModuleManifest {
        HomeStripFixture.manifest(shortID: "probe-expanded-only", surfaces: [.expanded], order: 1)
    }
}

/// `activate()` 必抛错 → failed（不得进首页块投影）
private final class HomeFailedProbeModule: HomeProbeModule {
    struct ActivationFailure: Error {}

    override class var manifest: ModuleManifest {
        HomeStripFixture.manifest(shortID: "probe-home-failed", surfaces: [.home], order: 2)
    }

    override func activate() async throws { throw ActivationFailure() }
}

/// `defaultEnabled = false` → disabled（不得进首页块投影）
private final class HomeOptInProbeModule: HomeProbeModule {
    override class var manifest: ModuleManifest {
        HomeStripFixture.manifest(shortID: "probe-home-optin", surfaces: [.home], order: 3, defaultEnabled: false)
    }
}

// MARK: - 假模块 / 摆放取证夹具（T4）

/// 首页块的**尺寸探针块**：假模块的内容就是它——`GeometryReader` 每趟布局都上报一次拿到的尺寸，
/// 留下的最后一份即**渲染真值**（被 `HomeStripLayout` 丢掉的块拿 `.zero` 提案 → 尺寸为零）。
private struct HomeBlockSizeProbe: View {
    let id: String

    var body: some View {
        GeometryReader { proxy in
            let _ = homeBlockSizeLog.record(id, proxy.size)
            Color.clear
        }
    }
}

/// 探针块的落点。**文件级**：假模块由注册表 `init(context:)` 实例化，拿不到用例里的局部对象。
private let homeBlockSizeLog = HomeBlockSizeLog()

/// 尺寸落点（键 = 模块 id）。只在主线程读写（SwiftUI 布局与用例都在主线程）。
private final class HomeBlockSizeLog {
    private(set) var byID: [String: CGSize] = [:]

    func reset() { byID.removeAll() }

    func record(_ id: String, _ size: CGSize) { byID[id] = size }

    /// 没被记过 = 没拿到尺寸（与 `.zero` 同解）。
    func size(of id: String) -> CGSize { byID[id] ?? .zero }
}

/// 假首页块：只声明 `.home`，块宽按参数声明（对齐生产档：接管块 300/420、新增模块 180/240）。
///
/// **根 conformer**（与 `TakeoverEnablementTests` 的 `TakeoverProbeBase` 同形）：`homeBlockWidth`
/// 写在**类体**里而不是留给协议扩展的默认实现——只有类体里的成员才会进 vtable，注册表的元类型
/// 查询（`registry.homeBlockWidth(for:)`）才会走到子类的 `override`。
private class HomeSizedProbeModule: GourdModule {
    class var manifest: ModuleManifest {
        HomeStripFixture.manifest(shortID: "probe-sized", surfaces: [.home])
    }

    /// 本模块声明的块宽（nil = 走宿主统一值 180/240，与新增模块同口径）。
    class var homeBlockWidth: ModuleHomeBlockWidth? { nil }

    /// 夹具四块的 id（**按 `order` 升序**，与 `HomeStripView.resolvedHomeBlocks()` 的排序同序）。
    static let ids = [
        "com.cmeng.gourd.probe-wide",
        "com.cmeng.gourd.probe-narrow-a",
        "com.cmeng.gourd.probe-narrow-b",
        "com.cmeng.gourd.probe-narrow-c",
    ]

    let context: ModuleContext

    required init(context: ModuleContext) {
        self.context = context
    }

    func activate() async throws {}

    func deactivate() async {}

    func content(for request: ContentRequest) -> ModuleContent {
        guard request.surface == .home else { return .none }
        return .view(AnyView(HomeBlockSizeProbe(id: Self.manifest.id)))
    }
}

/// 接管块那一档（音乐 300/420，order 0）：丢块路径下第一块永远保得住，用它检验**第二块**也真的画出来。
private final class HomeWideProbeModule: HomeSizedProbeModule {
    override class var manifest: ModuleManifest {
        HomeStripFixture.manifest(shortID: "probe-wide", surfaces: [.home], order: 0)
    }

    override class var homeBlockWidth: ModuleHomeBlockWidth? {
        ModuleHomeBlockWidth(min: 300, ideal: 420)
    }
}

/// 模块块档（宿主统一 180/240）第二块：702 下它与 wide 一起是「可见的两块」。
private final class HomeNarrowAProbeModule: HomeSizedProbeModule {
    override class var manifest: ModuleManifest {
        HomeStripFixture.manifest(shortID: "probe-narrow-a", surfaces: [.home], order: 20)
    }
}

/// 模块块档第三块：702 下被丢、832 下可见（900pt 面板那一档）。
private final class HomeNarrowBProbeModule: HomeSizedProbeModule {
    override class var manifest: ModuleManifest {
        HomeStripFixture.manifest(shortID: "probe-narrow-b", surfaces: [.home], order: 30)
    }
}

/// 模块块档第四块：只有 1020 宽（1088pt 面板）才放得下——防「修过头」的对照。
private final class HomeNarrowCProbeModule: HomeSizedProbeModule {
    override class var manifest: ModuleManifest {
        HomeStripFixture.manifest(shortID: "probe-narrow-c", surfaces: [.home], order: 40)
    }
}
