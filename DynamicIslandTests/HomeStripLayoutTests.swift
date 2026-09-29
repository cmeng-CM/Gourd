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
//  **协议与投影**
//  - `Surface.home`：词汇表取值与保序解码（四个取值，既有三个不变）；
//  - `ModuleRegistry.homeEntries`：只收 `active` 且声明 `.home` 的模块（failed / disabled /
//    只声明 `.expanded` 的都不得入选），排序与 `tabEntries` **同一比较器** `(order, id)`，
//    `label` / `symbolName` 复用既有解析；
//  - `ModuleRegistry.home` 请求形状：`surface` / `phase` / `slot` / `sizeHint` / `reason` /
//    `isLowPower`——**宽度不由请求传递**（`sizeHint == .zero`）。
//
//  夹具是**本文件私有**的最小假模块：`ModuleKernelTests` 的 `RegistryFixture` / `ProbeModule`
//  是 fileprivate（不跨文件可见），这里不复用、也不改它们的可见性。
//

import Defaults
import XCTest

@testable import Gourd

@MainActor
final class HomeStripLayoutTests: XCTestCase {

    // MARK: - 布局夹具

    /// 首页四块的真实宽度声明（docs/17 §接口与数据形状 6 的取值，不得另取一套）。
    private static let music = HomeStripLayoutMath.Item(min: 300, ideal: 420)
    private static let calendar = HomeStripLayoutMath.Item(min: 200, ideal: 260)
    private static let mirror = HomeStripLayoutMath.Item(min: 140, ideal: 160)
    private static let moduleBlock = HomeStripLayoutMath.Item(min: 180, ideal: 240)

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
