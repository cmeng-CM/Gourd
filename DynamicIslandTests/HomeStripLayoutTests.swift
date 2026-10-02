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
//  **首页各带的高度取舍 `HomeVerticalFit.plan`**（T2 / docs/23-home-fit.md §做法 机制二；
//    T7 起扩四档 / docs/26-home-widgets-and-settings.md §做法 机制六）
//  - 四档穷举（含紧凑块的合成入参）：`.both`（日历行 + 两带）/ `.noCalendar`（两带，日历行让位）/
//    `.widgetsOnly`（只留小组件带，主块带让位）/ `.none`（空）；
//  - 阈值边界（闭区间）：三样一起的最低高度恰好放得下、差 1pt 时**先没的是日历行**；两带的最低高度
//    恰好放得下、差 1pt 时**再没的是主块带**（不是小组件带的某一行）；连一行小组件都放不下 → 空；
//  - 顺序的正面判据：可用高度从高到低逐 pt 扫，**让位顺序恒为 日历行 → 主块带 → 小组件带**；
//  - **空带不进取舍**（T7）：没有紧凑块时四档**退化成旧三档**（`.both` ≡ 旧 both、`.noCalendar` ≡
//    旧 stripOnly、`.none` ≡ 旧 calendarOnly——旧 calendarOnly 那一档本就不画日历行，见
//    `HomeCalendarRow.rowHeight`（T8 起按当月周数，2026-10 = 232）> `HomeStripView.minimumUsableHeight`（140））；
//  - 日历行关掉时（行高按 0 传）不存在取舍：剩下的几样拿全部可用高度；
//  - 退化输入：`available == 0` 与负值都判成什么都不画（负值按 0 处理）。
//
//  **首页分带 `HomeBandedLayout`**（T7 / docs/26 §做法 机制六 / D-09）
//  - 小组件带**换行不丢块**：4 个紧凑块在 760pt 可用宽下排成两行、`＋N` 为 0；同一个名单在更宽的
//    可用宽下只排一行（行数由宽度定）；
//  - 主块带**仍按旧规则丢块**并计入 `＋N`（窄宽度下从尾部丢，`droppedCount` 与可见块数互补）；
//  - 行数由**高度**定：放不下 n 行时只画前几行、被丢的格计入 `＋N`；提示位（34pt）只在真有丢弃时
//    才在**最后一行**末尾预留，预留后这行的总宽仍不越过可用宽、且被挤掉的格也计入 `＋N`；
//  - 「放得下几行」与「n 行要多少高度」是同一个式子的两个方向（阈值上等价，有一条用例钉住）。
//
//  **首页块浮起**（p6-ui-polish / docs/30 §做法 机制一 / §验收标准 A1；p7 / docs/31 §接口 1 调参；
//    p7b 底色档自适应）
//  - 钉**纯函数 `HomeBlockFloatMetrics.effects(hovered:surface:)` 的两档 × 两底色档输出**（不是常量
//    本身）：`.dark`（纯黑底）常驻档中性（scale 1 / brightness 增量 0）+ 柔光池与辉光常驻可见，
//    hover 档池不透明度、辉光半径与不透明度都更大，放大 1.005…1.05、提亮增量 0.02…0.12；p7 起
//    常驻池 ∈ 0.08…0.25、hover 与常驻池差 ≥ 0.03、effects 与声明常量逐项同源（调参后的最终值回写
//    docs/31 §接口 1；hover 本身驱动不出，见 docs/30 §已知限制 1）；**p7b 起** `.glass`（玻璃两档）
//    的池与影都是黑色（亮底减亮）、hover 更深、三档映射与池半径不变量一并钉住
//    （`testGlassSurfaceUsesDarkVeilEffects`）。
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

    /// **分配算术的样本宽度**（四块：音乐 / 日历 / 镜子 / 模块块）——规则 ①②③ 的用例拿它们做题面。
    ///
    /// **样本约束：每块都要留可压缩量 `min < ideal`**（规则 ② 的「等比压缩」按
    /// `ideal − min` 分摊余量、并要判「各块让出的比例一致」）。**当前生产档的镜子不满足它**：
    /// p5-home-blocks / T3 起镜子是方形 `140/140`（压无可压，见 `MirrorModule.homeBlockWidth`），
    /// 拿它入样本会让「比例」变成 0/0——所以这一族样本沿用 T4 接管批次那一刻的声明
    /// （docs/17 §接口与数据形状 6：音乐 300/420、镜子 140/160）。
    ///
    /// **它不是生产声明的真源**：当前生产声明钉在各自模块的用例里
    /// （`TakeoverEnablementTests` 的音乐 / 镜子 manifest 段），以及本文件的
    /// `testLargeTierHeightAndMirrorSquareSideShareOneSource`（档高 ↔ 镜子边长的同源关系）。
    private static let music = HomeStripLayoutMath.Item(min: 300, ideal: 420)
    private static let calendar = HomeStripLayoutMath.Item(min: 200, ideal: 260)
    private static let mirror = HomeStripLayoutMath.Item(min: 140, ideal: 160)
    private static let moduleBlock = HomeStripLayoutMath.Item(min: 180, ideal: 240)

    /// 770pt 面板下 strip 的可用宽：`770 − 两侧各 34pt`（内边距常量链推导，docs/17 §接口与数据形状 6；
    /// 像素反推 ≈703，两个口径都在同一档——这里取常量链的口径）。
    private static let panelWidth770StripWidth: CGFloat = 702

    /// 一条带在**带级容器内边距扣完之后**的可用宽（T8 / docs/26 §做法 机制七）。
    ///
    /// T8 起两带各包一层带级容器：容器底画在带的 frame 上，内容左右各缩
    /// `HomeBandChrome.containerInset`（8）——因此**渲染真值用例挂在托管视图上的宽度**（= 面板可用宽）
    /// 与**接缝真正喂给两条带的那个宽度**差 16pt。plan 必须按后者算，否则比的是两份不同输入的答案。
    private static func bandContentWidth(forHostingWidth width: CGFloat) -> CGFloat {
        max(0, width - HomeBandChrome.containerInset * 2)
    }

    /// **尺寸反馈那一族的样本输入**（合成四块，**不是生产声明**）：一块 300/420 + 三块 180/240
    /// （`HomeStripView.moduleBlockWidth` 的统一值）。**必须与下面探针模块的宽度声明逐字一致**
    /// ——渲染真值对照的是「plan 说的宽」与「探针实际拿到的宽」，两边各取一套数就会对不上。
    /// 取样沿用 T4 那一刻的四块（含当时音乐那一档 300/420）：770/900/1088 三档面板的
    /// **可见块数阶梯（2/3/4）**是按这一组算出来的，它不是「当前生产声明」的转述。
    private static let syntheticFourBlockItems: [HomeStripLayoutMath.Item] = [
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
    /// ~~`.compact` 档显示今日标题~~ **`.full` 档画完整行形态（2026-10-01 口径改判：分数线
    /// `compactListWidth`(160) 的 ≥ 一侧是 `.full`，`.compact` 只标题留给更窄的块——旧三档的
    /// 语义方向作废，见 `TodosHomeBlockLayout.listTier(forWidth:)`）**。改动前 `680 + 24 = 704 > 702`：
    /// 第三块被规则 ③ 丢掉（且当时外框不裁剪，屏上留下溢出残影）。
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
        // 2026-10-01 口径（终审 F4）：`TodosHomeBlockLayout.compactListWidth`（160）这条线是
        // **≥ → `.full`**（完整行形态：完成圈 + 标题 + 过期红字），`.compact`（只标题）留给**更窄**
        // 的块——与旧三档的语义方向相反，旧消息写反了（断言本身一字未动）。
        XCTAssertGreaterThanOrEqual(plan.widths[2], 160, "第三块 181.5 ≥ 160 → 待办首页块走 .full 档（完整行形态）")
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

        // 样本四块（数值沿用 T4 那一档：音乐 300/420、镜子 140/160、待办与通知各 180/240，
        // 见 `music` / `mirror` 的说明——当前生产声明不是这一组）
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

    // MARK: - 首页各带的高度取舍（T2 / docs/23-home-fit.md §做法 机制二；T7 四档 / docs/26 §做法 机制六）

    /// 生产档的入参（与 `HomeBandedHomeView` 传的逐字同源）：日历行**按当月周数**算高
    /// （`HomeCalendarRow.rowHeight`，2026-10 = 5 周 → 232；T8 前是「最坏 6 周」的固定 294；T8 tune
    /// 按控制器上屏实测把网格上方两段多预留 + 网格底部 2pt 收回，见 `MonthGridLayout.monthGridHeight`）、
    /// 接缝间距 8、主块带最小可用高度 140（= 大块档 `HomeFlowView.largeBlockHeight`，T3 起）、
    /// 小组件带行高 96 / 行距 8。
    ///
    /// **钉在一个固定月份上**（2026-10，周日-first）：`HomeCalendarRow.rowHeight` 随当月走，
    /// 断言里的阈值链因此必须拿一个与运行日无关的月份来算，否则换个 6 周月这份文件整片红。
    private static let calendarRowHeight: CGFloat = HomeCalendarRow.rowHeight(
        forMonth: calendarRowMonth(calendarRowCalendar(firstWeekday: 1), year: 2026, month: 10),
        calendar: calendarRowCalendar(firstWeekday: 1)
    )
    private static let rowSpacing: CGFloat = HomeCalendarRow.rowSpacing
    private static let stripMinimumHeight: CGFloat = HomeStripView.minimumUsableHeight
    private static let widgetRowHeight: CGFloat = HomeStripView.widgetRowHeight
    private static let widgetRowSpacing: CGFloat = HomeStripView.widgetRowSpacing

    /// **三样一起**（日历行 + 两带各一行）放得下的最低高度 = `232 + 8 + 140 + 8 + 96 = 484`
    /// （T8 前按 6 周行高 294 算是 546）。
    private static let allThreeMinimumHeight: CGFloat =
        calendarRowHeight + rowSpacing + stripMinimumHeight + rowSpacing + widgetRowHeight

    /// **两带一起**（无日历行，各一行）放得下的最低高度 = `140 + 8 + 96 = 244`。
    private static let bothBandsMinimumHeight: CGFloat = stripMinimumHeight + rowSpacing + widgetRowHeight

    /// 一行小组件的高度（单独成档的下边界 = 96）。
    private static let oneWidgetRowHeight: CGFloat = widgetRowHeight

    /// 生产档四参数：`widgetRowsNeeded` 个紧凑块行、其余照上。
    private static func bandedPlan(
        available: CGFloat,
        widgetRowsNeeded: Int,
        calendarRowHeight: CGFloat = calendarRowHeight
    ) -> HomeVerticalFit.Plan {
        HomeVerticalFit.plan(
            available: available,
            calendarRowHeight: calendarRowHeight,
            rowSpacing: rowSpacing,
            mainBandMinimumHeight: stripMinimumHeight,
            widgetRowHeight: widgetRowHeight,
            widgetRowSpacing: widgetRowSpacing,
            widgetRowsNeeded: widgetRowsNeeded
        )
    }

    /// **旧三档那一档**（没有紧凑块：`widgetRowHeight = 0` / `widgetRowsNeeded = 0`）——
    /// 空带不进取舍，四档因此退化成「主块带 + 日历行」的旧题面。
    private static func legacystylePlan(available: CGFloat, calendarRowHeight: CGFloat = calendarRowHeight) -> HomeVerticalFit.Plan {
        HomeVerticalFit.plan(
            available: available,
            calendarRowHeight: calendarRowHeight,
            rowSpacing: rowSpacing,
            mainBandMinimumHeight: stripMinimumHeight,
            widgetRowHeight: 0,
            widgetRowSpacing: widgetRowSpacing,
            widgetRowsNeeded: 0
        )
    }

    /// 阈值链的锚点：五个常量任一被改动，本用例先红——边界数值要跟着一起重新审，而不是静默漂。
    func testVerticalFitThresholdsArePinned() {
        XCTAssertEqual(
            Self.calendarRowHeight, 232,
            "日历行按当月周数（2026-10 = 5 周 → 36 × 5 + 52；T8 前是「最坏 6 周」的固定 294）"
        )
        XCTAssertEqual(Self.rowSpacing, 8)
        XCTAssertEqual(Self.stripMinimumHeight, 140, "主块带最小可用高 = 大块档（T3 起 140，见 HomeStripView 的属性注释）")
        XCTAssertEqual(Self.widgetRowHeight, 96, "小组件带行高（T7 的高度预算见 HomeStripView 的属性注释）")
        XCTAssertEqual(Self.widgetRowSpacing, 8)
        XCTAssertEqual(Self.allThreeMinimumHeight, 484, "232 + 8 + 140 + 8 + 96：三样一起放得下的最低高度")
        XCTAssertEqual(Self.bothBandsMinimumHeight, 244, "140 + 8 + 96：两带一起放得下的最低高度")
    }

    // MARK: - 首页日历行：行高按当月周数（p6-ui-polish / T8，docs/30 §做法 机制六）

    /// 固定日历：格里高利 + GMT（不受本机时区影响）+ `en_US_POSIX` + 指定 `firstWeekday`
    /// （与 `MonthGridLayoutTests.gridCalendar` 同式；那个是别的类的 private，不跨类可见）。
    static func calendarRowCalendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    /// 固定月份的首日零点（`gridMonth` 同式）。
    static func calendarRowMonth(_ calendar: Calendar, year: Int, month: Int, day: Int = 1) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// **行高 = `36 × N + 52`**（N = 当月实际周数；p6-ui-polish / T8，docs/30 §做法 机制六）。
    ///
    /// 三条判据：
    /// 1. **与网格渲染同源**：N 就是 `MonthGridLayout.days(forMonth:)`（屏幕上的那张网格）的格数 / 7
    ///    ——两处算法不可能漂；
    /// 2. **边界**：2026-08 = 6 周（7/26–9/5，跨到 9 月的 6 周月 → 268）、2026-10 = 5 周（232；T8 tune
    ///    后控制器上屏实测口径下的那一档）、跨年 1 月（首格落在上一年 12 月）、首日恰是周起点的
    ///    11 月（leading days = 0）；
    /// 3. **周起点跟随 `firstWeekday`**：同一月份在周日-first 与周一-first 下的周数按各自网格算
    ///    （2026-05 就是一个 6 / 5 不同的月份）——行高不按任何写死的「最多 6 周」拍脑袋。
    func testHomeCalendarRowHeightFollowsTheMonthWeeks() throws {
        let sunday = Self.calendarRowCalendar(firstWeekday: 1)
        let monday = Self.calendarRowCalendar(firstWeekday: 2)

        /// 同源判据：周数 = 网格格数 / 7；行高 = `36N + 52`。
        func assertMonth(
            _ calendar: Calendar, _ year: Int, _ month: Int, weeks: Int,
            file: StaticString = #filePath, line: UInt = #line
        ) {
            let monthDate = Self.calendarRowMonth(calendar, year: year, month: month)
            let days = MonthGridLayout.days(forMonth: monthDate, calendar: calendar)
            XCTAssertEqual(days.count % 7, 0, "整月网格恒为整周数", file: file, line: line)
            XCTAssertEqual(
                MonthGridLayout.weekCount(for: monthDate, calendar: calendar), weeks,
                "\(year)-\(month) 应占 \(weeks) 周", file: file, line: line
            )
            XCTAssertEqual(
                days.count / 7, weeks,
                "同源判据：周数 = 网格格数 / 7（`weekCount` 就是网格那份数据摊出来的行数）",
                file: file, line: line
            )
            XCTAssertEqual(
                HomeCalendarRow.rowHeight(forMonth: monthDate, calendar: calendar),
                36 * CGFloat(weeks) + 52,
                "行高 = 36N + 52（\(weeks) 周）", file: file, line: line
            )
        }

        // 2026-08 = 6 周（7/26–9/5）→ 268；2026-10 = 5 周 → 232。
        assertMonth(sunday, 2026, 8, weeks: 6)
        assertMonth(sunday, 2026, 10, weeks: 5)
        XCTAssertEqual(
            HomeCalendarRow.rowHeight(
                forMonth: Self.calendarRowMonth(sunday, year: 2026, month: 10), calendar: sunday
            ),
            232, "10 月 5 周 → 232（T8 tune 后的设计值；T8 前固定 294、T8 首版 258）"
        )
        XCTAssertEqual(
            HomeCalendarRow.rowHeight(
                forMonth: Self.calendarRowMonth(sunday, year: 2026, month: 8), calendar: sunday
            ),
            268, "8 月 6 周 → 268（T8 tune 后；旧固定值 294 恰好是这一档）"
        )

        // 跨年 1 月：首格跨到上一年 12 月（2027-01 的首格 = 2026-12-27，Sunday-first）。
        let january2027 = Self.calendarRowMonth(sunday, year: 2027, month: 1)
        let januaryDays = MonthGridLayout.days(forMonth: january2027, calendar: sunday)
        XCTAssertLessThan(
            try XCTUnwrap(januaryDays.first), january2027,
            "跨年月的首格落在上一年（2026-12-27）"
        )
        XCTAssertEqual(
            sunday.component(.year, from: try XCTUnwrap(januaryDays.first)), 2026,
            "跨年首格属于上一年"
        )
        assertMonth(sunday, 2027, 1, weeks: 6)

        // 首日恰是周起点：2026-11-01 是周日 → leading days = 0，首格就是月初那天。
        let november = Self.calendarRowMonth(sunday, year: 2026, month: 11)
        XCTAssertEqual(
            try XCTUnwrap(MonthGridLayout.days(forMonth: november, calendar: sunday).first), november,
            "月初即周起点 → 首格 = 月初（leading days = 0 的边界）"
        )
        assertMonth(sunday, 2026, 11, weeks: 5)

        // 首周日 = 周日的口径：同一月份在两种周起点下周数按各自的网格算（2026-05：周日-first 6 周、
        // 周一-first 5 周）——`weekCount` 跟着 `firstWeekday` 走，不写死任何一档。
        assertMonth(sunday, 2026, 5, weeks: 6)
        assertMonth(monday, 2026, 5, weeks: 5)
        // 2026-10 在两种周起点下都是 5 周（周日-first：9/27–10/31；周一-first：9/28–11/1）。
        assertMonth(monday, 2026, 10, weeks: 5)

        // 生产入口（无月参的那一个）与纯函数逐字同值：宿主 plan 的预算与行的 frame 读的是同一份。
        XCTAssertEqual(HomeCalendarRow.rowHeight, HomeCalendarRow.rowHeight(forMonth: Date()), "静态入口 = 当前月的纯函数值")

        // 两处宿主同源（首页行 / 独立日历页左栏）：`MonthGridLayout.monthGridHeight` 就是行高算式
        // 的那一份——两处不可能各写一套（`StandaloneCalendarView.monthGridHeight` 直接调它）。
        for month in [8, 10] {
            let monthDate = Self.calendarRowMonth(sunday, year: 2026, month: month)
            XCTAssertEqual(
                HomeCalendarRow.rowHeight(forMonth: monthDate, calendar: sunday),
                MonthGridLayout.monthGridHeight(forMonth: monthDate, calendar: sunday),
                "首页日历行高与独立日历页左栏高同源（\(month) 月）"
            )
        }
    }

    /// **行高下网格恰好装下整月**（p6-ui-polish / T8 tune 的结构护栏）：在 `HomeCalendarRow.rowHeight`
    /// 给定的行高里挂**真的** `MonthGridView`，量日格那个 `NSScrollView` 的视口——它必须恰好等于
    /// 「整月网格内容」= `36N − 6`（`LazyVGrid` 的 N 行 + (N−1) 道行距；T8 tune 去掉了额外的
    /// `.padding(.bottom, 2)`），且网格底**贴住行底**（上方两段 chrome 的余量都落在网格上方）。
    ///
    /// 视口小于内容 = 末行被裁（T8 的失败信号）；网格底离行底还有空档 = 底部可见留白又长回来。
    /// 两侧都钉住：5 周（2026-10 / 11）与 6 周（2026-08）各量一条。量法 = 宿主视图树里的
    /// `NSScrollView`（SwiftUI 在 macOS 上的滚动实现）；找不到就 skip——换实现不算失败，
    /// 上屏像素判据仍在控制器那边。
    func testHomeCalendarGridViewportFitsTheMonthAtItsRowHeight() throws {
        let calendar = Self.calendarRowCalendar(firstWeekday: 1)
        for (year, month, weeks) in [(2026, 10, 5), (2026, 11, 5), (2026, 8, 6)] {
            let monthDate = Self.calendarRowMonth(calendar, year: year, month: month)
            let rowHeight = HomeCalendarRow.rowHeight(forMonth: monthDate, calendar: calendar)
            XCTAssertEqual(rowHeight, 36 * CGFloat(weeks) + 52, "前提：\(year)-\(month) = \(weeks) 周")

            var selected = monthDate
            var target: Date?
            let grid = MonthGridView(
                selectedDate: Binding(get: { selected }, set: { selected = $0 }),
                scrollTarget: Binding(get: { target }, set: { target = $0 }),
                monthNavigationMovesSelection: false,
                monthEvents: .empty,
                onDisplayedMonthChange: { _ in },
                showsScrollFades: false
            )
            .frame(width: 460, height: rowHeight)

            let host = NSHostingView(rootView: grid)
            host.frame = CGRect(x: 0, y: 0, width: 460, height: rowHeight)
            host.layoutSubtreeIfNeeded()

            var scrollViews: [NSScrollView] = []
            func walk(_ v: NSView) {
                if let sv = v as? NSScrollView { scrollViews.append(sv) }
                for sub in v.subviews { walk(sub) }
            }
            walk(host)
            try XCTSkipIf(scrollViews.isEmpty, "宿主里找不到 NSScrollView —— 留给上屏像素判据")

            let dayGrid = scrollViews[0]
            XCTAssertEqual(
                dayGrid.contentSize.height, 36 * CGFloat(weeks) - 6, accuracy: 0.5,
                "\(year)-\(month)：视口必须恰好是整月内容高（小于 = 末行被裁，大于 = 底部又留空档）"
            )
            let gridFrameInRow = host.convert(dayGrid.bounds, from: dayGrid)
            XCTAssertEqual(
                gridFrameInRow.maxY, rowHeight, accuracy: 1,
                "\(year)-\(month)：网格底贴住行底（行高 = 4 + 标题 chrome + 周标题 chrome + 内容，逐项见 monthGridHeight）"
            )
            withExtendedLifetime(host) {}
        }
    }

    /// **紧凑档音乐条的高度预算**（p5-home-blocks / T3 fix / D-17；T2 收窄）：`MusicControlsView`
    /// 紧凑档的六项之和必须 ≤ **紧凑档高**（`HomeFlowView.compactBlockHeight` = 96）——这是「不裁不溢」的
    /// 算术判据（T3 阶段 Checkpoint 上屏实测过：标准档内容 ≈127pt，96 里控制三键整行被裁）。
    ///
    /// 六个数都是**固有高**、不是拍出来的比例（T3 fix 离线实测，`NSHostingView.fittingSize`）：
    /// - 曲名行 17 ≥ 单行 `.headline` 的两条路径（滚动 `MarqueeText` 的 `1.3 × 13 = 16.9`、
    ///   纯文本截断 16）；
    /// - 进度行 34 = `MusicSliderView`（stacked，**同一份滑条实现**）的实测固有高
    ///   （轨道 `max(8, 14)` + 间距 6 + 时间行 14）；
    /// - 控制行 26 = `.small` 档 `HoverButton` 的实测边长（T2 起；标准档 `.large` 是 40、`.medium` 30）。
    ///
    /// 上屏的最终判据仍以截图为准（字体度量随系统漂，这里钉的是预算与六项取值）；
    /// **装宽度**（封面档 ≤ min）那条在 T2 的
    /// `testMusicBlockWidthAndCompactControlsFitTheMinimum` 里。
    func testCompactMusicBarFitsTheCompactTier() {
        typealias Metrics = MusicControlsView.CompactMetrics
        XCTAssertEqual(Metrics.topPadding, 4, "标准档 10 → 紧凑档 4")
        XCTAssertEqual(Metrics.titleRowHeight, 17, "单行曲名（展开面板那一档还叠艺人行 + 可能有歌词行）")
        XCTAssertEqual(Metrics.titleSliderSpacing, 4, "组内间距与标准档同值（不动它）")
        XCTAssertEqual(Metrics.sliderRowHeight, 34, "stacked MusicSliderView 的固有高")
        XCTAssertEqual(Metrics.controlsSpacing, 6, "标准档的 VStack 缺省是 8")
        XCTAssertEqual(Metrics.controlsRowHeight, 26, "T2 起紧凑档五键同走 .small 档（26；标准档播放键 .large = 40）")
        XCTAssertEqual(
            Metrics.controlsRowHeight, Metrics.controlKeyDiameter,
            "控制行高 = 键径（一行全是同档方形键）"
        )

        XCTAssertEqual(Metrics.contentHeight, 91, "六项之和（4 + 17 + 4 + 34 + 6 + 26）")
        XCTAssertLessThanOrEqual(
            Metrics.contentHeight, HomeFlowView.compactBlockHeight,
            "整条内容必须装进紧凑档 \(HomeFlowView.compactBlockHeight)pt——超了就是 Checkpoint 那次「控制三键被裁」"
        )
        XCTAssertLessThanOrEqual(
            max(Metrics.contentHeight, Metrics.albumArtSide), HomeFlowView.compactBlockHeight,
            "封面打开那一档：HStack 的高 = max(\(Metrics.albumArtSide)pt 小封面, 控制条内容) 也必须装进紧凑档"
        )
    }

    /// **T3 的三个数是一个数**（docs/29 §做法 机制四 / D-10 / §已知限制 7）：大块档高、主块带
    /// 最小可用高与镜子的方形边长必须**同源**——只改一处就会「圆被行高卡成椭圆」或「块里留横向空档」。
    ///
    /// 断言的是**关系**（读生产常量与模块声明），不是三个各自独立的魔数：字面量只有一处
    /// （`HomeFlowView.largeBlockHeight` 的 140），另外两个引用它。
    func testLargeTierHeightAndMirrorSquareSideShareOneSource() {
        XCTAssertEqual(HomeFlowView.largeBlockHeight, 140, "大块档高的字面量（唯一取值处是 HomeFlowView）")
        XCTAssertEqual(
            HomeFlowView.blockHeight(for: .large), HomeFlowView.largeBlockHeight,
            "档高表的入口就是那个常量（`homeFormFactor == .large` → 140）"
        )
        XCTAssertEqual(
            HomeStripView.minimumUsableHeight, HomeFlowView.largeBlockHeight,
            "主块带最小可用高 = 档高（同一常量：带至少装得下带里最高的块）"
        )

        let mirror = MirrorModule.homeBlockWidth
        XCTAssertEqual(mirror?.min, HomeFlowView.largeBlockHeight, "镜子的方形边长 = 档高（声明直接引用宿主常量）")
        XCTAssertEqual(mirror?.ideal, mirror?.min, "镜子块是方形：ideal == min（否则块里留横向空档）")
        XCTAssertEqual(
            HomeFlowView.blockHeight(for: .compact), 96,
            "紧凑档仍 96（音乐 T3 起是这一档——它的高度不在本条同源关系里）"
        )
    }

    /// `.both` 档：三样都在——日历行在、小组件带拿它要的一行、主块带拿剩下的。
    func testBothLayoutKeepsCalendarRowAndShrinksMainBand() {
        let plan = Self.bandedPlan(available: 582, widgetRowsNeeded: 1)

        XCTAssertEqual(plan.layout, .both)
        XCTAssertTrue(plan.showsMainBand)
        XCTAssertTrue(plan.showsWidgetBand)
        XCTAssertTrue(plan.showsCalendarRow)
        XCTAssertEqual(plan.widgetBandHeight, Self.oneWidgetRowHeight, "小组件带拿它要的高度（一行）")
        XCTAssertEqual(
            plan.mainBandHeight, 582 - Self.calendarRowHeight - 8 - 8 - Self.oneWidgetRowHeight,
            "主块带拿扣掉日历行、小组件带与两个间距的剩余（238）"
        )
    }

    /// `.both` 的**下边界**：`available` 恰好等于 484 时三样仍都在，主块带恰好拿到它的最小可用高度。
    func testBothLayoutBoundaryAtExactCombinedMinimum() {
        let plan = Self.bandedPlan(available: Self.allThreeMinimumHeight, widgetRowsNeeded: 1)

        XCTAssertEqual(plan.layout, .both, "恰好等于阈值算放得下（不留一条只有 0.0001pt 宽的缝）")
        XCTAssertEqual(
            plan.mainBandHeight, Self.stripMinimumHeight,
            "恰好放满：主块带拿到它的最小可用高度（T3 起 140）"
        )
        XCTAssertEqual(plan.widgetBandHeight, Self.oneWidgetRowHeight)
        XCTAssertTrue(plan.showsCalendarRow)
    }

    /// `.both` 下一点（483）：**让位的是日历行**（D-02，第一条让位规则），两带都还在。
    func testCalendarRowGivesWayJustBelowCombinedMinimum() {
        let available = Self.allThreeMinimumHeight - 1
        let plan = Self.bandedPlan(available: available, widgetRowsNeeded: 1)

        XCTAssertEqual(plan.layout, .noCalendar, "三样一起放不下 → 收起日历行（D-02）")
        XCTAssertFalse(plan.showsCalendarRow)
        XCTAssertTrue(plan.showsMainBand, "主块带仍在")
        XCTAssertTrue(plan.showsWidgetBand, "小组件带仍在")
        XCTAssertEqual(plan.widgetBandHeight, Self.oneWidgetRowHeight)
        XCTAssertEqual(
            plan.mainBandHeight, available - Self.rowSpacing - Self.oneWidgetRowHeight,
            "主块带拿剩下的（379）"
        )
    }

    /// `.noCalendar` 的整个高度带（244…483）：日历行全程不在、两带全程都在、小组件带恒拿它要的一行。
    func testNoCalendarBandKeepsBothBandsAndDropsCalendarRow() {
        // 取样点必须落在带内（≤ 483）：T8 tune 把三样阈值从 510 收到 484，500 已落进 `.both` 档。
        for available in [Self.allThreeMinimumHeight - 1, 460, 400, 300, Self.bothBandsMinimumHeight] {
            let plan = Self.bandedPlan(available: available, widgetRowsNeeded: 1)

            XCTAssertEqual(plan.layout, .noCalendar, "可用高度 \(available) 应落在 noCalendar 档")
            XCTAssertTrue(plan.showsMainBand, "主块带在 \(available) 应仍在")
            XCTAssertTrue(plan.showsWidgetBand, "小组件带在 \(available) 应仍在")
            XCTAssertFalse(plan.showsCalendarRow, "日历行在 \(available) 应已让位")
            XCTAssertEqual(plan.widgetBandHeight, Self.oneWidgetRowHeight, "小组件带在 \(available) 恒拿一行")
            XCTAssertEqual(plan.mainBandHeight, available - 8 - Self.oneWidgetRowHeight, "主块带拿剩下的")
            XCTAssertGreaterThanOrEqual(plan.mainBandHeight, Self.stripMinimumHeight, "主块带不低于它的最小可用高度")
        }
    }

    /// `.noCalendar` 的**下边界**（244）与下一点（243）：恰好放得下时两带都在（主块带恰好 140）；
    /// 差 1pt 时**让位的是主块带**（不是小组件带的某一行）——D-09 的顺序。
    func testMainBandGivesWayJustBelowBothBandsMinimum() {
        let exact = Self.bandedPlan(available: Self.bothBandsMinimumHeight, widgetRowsNeeded: 1)
        XCTAssertEqual(exact.layout, .noCalendar, "恰好等于两带阈值算放得下")
        XCTAssertEqual(exact.mainBandHeight, Self.stripMinimumHeight, "恰好放满：主块带拿到 140")

        let below = Self.bandedPlan(available: Self.bothBandsMinimumHeight - 1, widgetRowsNeeded: 1)
        XCTAssertEqual(below.layout, .widgetsOnly, "两带一起放不下 → 主块带让位（D-09）")
        XCTAssertFalse(below.showsMainBand)
        XCTAssertTrue(below.showsWidgetBand, "小组件带是最后让位的")
        XCTAssertEqual(below.widgetBandHeight, Self.bothBandsMinimumHeight - 1, "它拿**全部**可用高度")
        XCTAssertFalse(below.showsCalendarRow)
    }

    /// `.widgetsOnly` 档的整个高度带（96…243）：主块带全程不在、小组件带拿全部可用高度。
    func testWidgetsOnlyBandKeepsWidgetBandAndDropsMainBand() {
        for available in [Self.bothBandsMinimumHeight - 1, 200, 150, 96] {
            let plan = Self.bandedPlan(available: available, widgetRowsNeeded: 1)

            XCTAssertEqual(plan.layout, .widgetsOnly, "可用高度 \(available) 应落在 widgetsOnly 档")
            XCTAssertFalse(plan.showsMainBand)
            XCTAssertTrue(plan.showsWidgetBand)
            XCTAssertEqual(plan.widgetBandHeight, available, "小组件带拿全部可用高度")
            XCTAssertGreaterThanOrEqual(plan.widgetBandHeight, Self.oneWidgetRowHeight)
        }
    }

    /// `.widgetsOnly` 的**下边界**（96）与 `.none`（95.9）：连一行小组件都放不下 → 什么都不画
    /// （日历行不单独存活——它是第一个让位的）。
    func testNothingBelowOneWidgetRow() {
        let exact = Self.bandedPlan(available: Self.oneWidgetRowHeight, widgetRowsNeeded: 1)
        XCTAssertEqual(exact.layout, .widgetsOnly, "恰好等于一行的高度算放得下")
        XCTAssertEqual(exact.widgetBandHeight, Self.oneWidgetRowHeight)

        let below = Self.bandedPlan(available: Self.oneWidgetRowHeight - 0.1, widgetRowsNeeded: 1)
        XCTAssertEqual(below.layout, .none, "一行都放不下 → 空")
        XCTAssertFalse(below.showsMainBand)
        XCTAssertFalse(below.showsWidgetBand)
        XCTAssertFalse(below.showsCalendarRow)
        XCTAssertEqual(below.mainBandHeight, 0, "不画时不占高度（不是负值、不是残高）")
        XCTAssertEqual(below.widgetBandHeight, 0)
    }

    /// **让位顺序的正面判据**（D-02 + D-09）：可用高度从 850 一路降到 60，**先消失的是日历行**
    /// （三样阈值 484 下一点的 483）、**再是主块带**（244 下一点的 243）、小组件带一路撑到 96 以下才整条消失。
    func testGiveWayOrderIsCalendarThenMainBandThenWidgets() {
        var calendarRowDroppedAt: CGFloat?
        var mainBandDroppedAt: CGFloat?
        var widgetsDroppedAt: CGFloat?

        for available in stride(from: CGFloat(850), through: 60, by: -1) {
            let plan = Self.bandedPlan(available: available, widgetRowsNeeded: 1)
            if !plan.showsCalendarRow, calendarRowDroppedAt == nil { calendarRowDroppedAt = available }
            if !plan.showsMainBand, mainBandDroppedAt == nil { mainBandDroppedAt = available }
            if !plan.showsWidgetBand, widgetsDroppedAt == nil { widgetsDroppedAt = available }
        }

        XCTAssertEqual(
            calendarRowDroppedAt, Self.allThreeMinimumHeight - 1,
            "日历行应在三样阈值（\(Self.allThreeMinimumHeight)）的下一点先消失"
        )
        XCTAssertEqual(mainBandDroppedAt, 243, "主块带应在两带阈值（244）的下一点（243）消失")
        XCTAssertEqual(widgetsDroppedAt, 95, "小组件带应一直撑到 96 之下（95）才整条消失")
        XCTAssertGreaterThan(
            calendarRowDroppedAt ?? -1,
            mainBandDroppedAt ?? -1,
            "日历行必须先于主块带消失（顺序反了就是 D-02 没落地）"
        )
        XCTAssertGreaterThan(
            mainBandDroppedAt ?? -1,
            widgetsDroppedAt ?? -1,
            "主块带必须先于小组件带消失（顺序反了就是 D-09 没落地）"
        )
    }

    /// **空带不进取舍**（T7）：没有紧凑块时四档退化成旧三档——`.both` ≡ 旧 both、
    /// `.noCalendar` ≡ 旧 stripOnly、`.none` ≡ 旧 calendarOnly（旧 calendarOnly 那一档本就不画
    /// 日历行：日历行按当月周数算出的 232（2026-10 那一档）> 主块带阈值 140，判据
    /// `available >= calendarRowHeight` 不可能成立）。
    func testEmptyWidgetBandDegeneratesToLegacyThreeTiers() {
        // 旧 both：380 = 140 + 8 + 232（日历行）—— 恰好放得下时主块带拿 140、日历行在
        let both = Self.legacystylePlan(available: Self.stripMinimumHeight + Self.rowSpacing + Self.calendarRowHeight)
        XCTAssertEqual(both.layout, .both)
        XCTAssertEqual(both.mainBandHeight, 140)
        XCTAssertFalse(both.showsWidgetBand, "没有紧凑块 → 小组件带不占高度")
        XCTAssertTrue(both.showsCalendarRow)

        // 旧 stripOnly：379 —— 日历行先让位，主块带拿全部可用高度
        let noCalendar = Self.legacystylePlan(
            available: Self.stripMinimumHeight + Self.rowSpacing + Self.calendarRowHeight - 1
        )
        XCTAssertEqual(noCalendar.layout, .noCalendar)
        XCTAssertEqual(
            noCalendar.mainBandHeight, Self.stripMinimumHeight + Self.rowSpacing + Self.calendarRowHeight - 1,
            "主块带拿全部可用高度，不是扣掉日历行的剩余"
        )
        XCTAssertFalse(noCalendar.showsCalendarRow)
        XCTAssertFalse(noCalendar.showsWidgetBand)

        // 旧 calendarOnly：139.9 —— 生产档下两样都不画（日历行 232 放不下）
        let nothing = Self.legacystylePlan(available: 139.9)
        XCTAssertEqual(nothing.layout, .none)
        XCTAssertFalse(nothing.showsMainBand, "主块带连最小可用高度都放不下 → 整条不画")
        XCTAssertFalse(nothing.showsCalendarRow, "生产档日历行要 232（2026-10），139.9 放不下 → 这一档什么都不画")
        XCTAssertEqual(nothing.mainBandHeight, 0, "不画时不占高度（不是负值、不是残高）")
    }

    /// 退化输入：`available == 0` 与负值都判成「什么都不画」，且两者结果一致（负值按 0 处理，
    /// 不产生负高度）。
    func testZeroAndNegativeAvailableDrawNothing() {
        let zero = Self.bandedPlan(available: 0, widgetRowsNeeded: 1)
        XCTAssertEqual(zero.layout, .none)
        XCTAssertFalse(zero.showsMainBand)
        XCTAssertFalse(zero.showsWidgetBand)
        XCTAssertFalse(zero.showsCalendarRow)

        let negative = Self.bandedPlan(available: -40, widgetRowsNeeded: 1)
        XCTAssertEqual(negative, zero, "负的可用高度与 0 等价（布局退化时不出现负高度）")

        // 没有紧凑块时也一样（退化路径不因为空带而多画一条）
        XCTAssertEqual(Self.legacystylePlan(available: -1), Self.legacystylePlan(available: 0))
        XCTAssertEqual(Self.legacystylePlan(available: 0).layout, .none)
    }

    /// 日历行关掉时（接缝把行高按 0 传）不存在取舍：剩下的几样拿**全部**可用高度
    /// （与改动前 `showCalendar == false` 那一支同口径）。
    func testCalendarRowDisabledHandsAllHeightToBands() {
        for available in [Self.bothBandsMinimumHeight, 300, 442, 850] {
            let plan = Self.bandedPlan(available: available, widgetRowsNeeded: 1, calendarRowHeight: 0)

            XCTAssertTrue(plan.showsMainBand, "关掉日历行后 \(available) 应仍画主块带")
            XCTAssertTrue(plan.showsWidgetBand, "小组件带也应在")
            XCTAssertFalse(plan.showsCalendarRow)
            XCTAssertEqual(plan.widgetBandHeight, Self.oneWidgetRowHeight, "小组件带仍只要一行的高度")
            XCTAssertEqual(
                plan.mainBandHeight, available - 8 - Self.oneWidgetRowHeight, accuracy: 1e-9,
                "主块带拿全部可用高度减去小组件带与那一个间距"
            )
        }

        // 只剩主块带那一档（没有紧凑块）时，它拿全部可用高度——旧题面逐字不变
        for available in [Self.stripMinimumHeight, 300, 442, 850] {
            let plan = Self.legacystylePlan(available: available, calendarRowHeight: 0)
            XCTAssertTrue(plan.showsMainBand, "关掉日历行后 \(available) 应仍画主块带")
            XCTAssertEqual(plan.mainBandHeight, available, accuracy: 1e-9, "主块带应拿全部可用高度")
        }
        XCTAssertFalse(
            Self.legacystylePlan(available: Self.stripMinimumHeight - 1, calendarRowHeight: 0).showsMainBand,
            "低于阈值仍整条不画（阈值与日历行开不开无关）"
        )
    }

    /// **两档判据的咬合**（防两个算式各自漂）：`HomeVerticalFit` 判「n 行要多少高度」与
    /// `HomeBandedLayout` 判「这条高度放得下几行」必须互为反函数——在阈值上等价。
    func testWidgetRowAffordabilityInvertsTheTierThreshold() {
        for rows in 1...4 {
            let need = CGFloat(rows) * Self.widgetRowHeight + CGFloat(rows - 1) * Self.widgetRowSpacing
            XCTAssertEqual(
                HomeBandedLayout.affordableRows(
                    bandHeight: need,
                    rowHeight: Self.widgetRowHeight,
                    rowSpacing: Self.widgetRowSpacing
                ),
                rows,
                "恰好等于 \(rows) 行的高度时应判「放得下 \(rows) 行」（闭区间）"
            )
            XCTAssertEqual(
                HomeBandedLayout.affordableRows(
                    bandHeight: need - 0.1,
                    rowHeight: Self.widgetRowHeight,
                    rowSpacing: Self.widgetRowSpacing
                ),
                rows - 1,
                "差 0.1pt 时应判「放不下 \(rows) 行」"
            )
        }
    }

    // MARK: - 首页分带（T7 / docs/26 §做法 机制六 / D-09）

    /// 生产档四个紧凑块的宽度声明（**真实取值**）：进度 / 待办 / 通知走宿主统一值 180/240，
    /// 统计是接管块那一档 220/300。
    private static let compactFourItems: [HomeStripLayoutMath.Item] = [
        HomeStripLayoutMath.Item(min: 180, ideal: 240),
        HomeStripLayoutMath.Item(min: 180, ideal: 240),
        HomeStripLayoutMath.Item(min: 180, ideal: 240),
        HomeStripLayoutMath.Item(min: 220, ideal: 300),
    ]

    /// 一条带（主块带 + 小组件带）的度量：生产常量，两带的尾部预留位都是 34（`＋N` 位）。
    private static let bandMetrics = HomeBandedLayout.Metrics(
        mainSpacing: HomeStripLayout.spacing,
        mainTailReserve: HomeStripView.droppedHintWidth,
        widgetColumnSpacing: HomeStripView.widgetColumnSpacing,
        widgetRowSpacing: HomeStripView.widgetRowSpacing,
        widgetRowHeight: HomeStripView.widgetRowHeight,
        widgetTailReserve: HomeStripView.droppedHintWidth
    )

    /// ① **小组件带换行而不是丢块**（用户原话那条）：4 个紧凑块在 760pt 可用宽下排成**两行**、
    /// `＋N` 为 0（`rowsNeeded == 2`）。
    ///
    /// 760 的算法：四块最小宽之和 + 3 个列间距 = `180×3 + 220 + 24 = 784 > 760`（装不下一行），
    /// 而前三块 `180×3 + 16 = 556 ≤ 760`（第一行），统计一块（`220 ≤ 760`）落第二行。
    /// **同一个名单在改动前是「一条 strip」**：规则 ③ 从尾部丢到只剩两块（＋2）。
    func testWidgetBandWrapsInsteadOfDropping() {
        let available: CGFloat = 760
        let plan = HomeBandedLayout.plan(
            mainItems: [],
            widgetItems: Self.compactFourItems,
            availableWidth: available,
            widgetBandHeight: 2 * Self.widgetRowHeight + Self.widgetRowSpacing,
            metrics: Self.bandMetrics
        )

        XCTAssertEqual(plan.widgets.rowsNeeded, 2, "4 块在 760 可用宽下要两行（放不下才换行）")
        XCTAssertEqual(plan.widgets.rowsDrawn, 2, "两行的高度给够了 → 两行都画")
        XCTAssertEqual(plan.widgets.droppedCount, 0, "换行不丢块")
        XCTAssertEqual(plan.widgets.visibleCount, 4)
        XCTAssertFalse(plan.widgets.showsHint, "没有丢弃 → 不画 ＋N（也不预留提示位）")

        // 行的构成：第一行前三块、第二行统计
        XCTAssertEqual(plan.widgets.rows[0].indices, [0, 1, 2])
        XCTAssertEqual(plan.widgets.rows[1].indices, [3])
        for row in plan.widgets.rows {
            XCTAssertEqual(row.height, Self.widgetRowHeight, "行高恒等于声明的行高")
            XCTAssertEqual(row.droppedCount, 0)
            XCTAssertFalse(row.showsHint)
            let used = row.widths.reduce(CGFloat.zero, +)
                + Self.widgetRowSpacing * CGFloat(max(0, row.widths.count - 1))
            XCTAssertLessThanOrEqual(used, available + 1e-9, "行内总宽不得越过可用宽")
            XCTAssertTrue(row.widths.allSatisfy { $0 >= 180 }, "每格不低于它的最小宽（规则 ②）")
        }
        // 第一行三块都拿 min 与 ideal 之间的压缩宽（不等、也不必等）；第二行单块走规则 ① 拿 ideal
        XCTAssertEqual(plan.widgets.rows[1].widths, [300], "单块一行：富余不拉伸，用它的 ideal（300）")
    }

    /// 行数由**宽度**定：同一份名单，可用宽够大时只排一行（1020 = 1088pt 面板）。
    func testWidgetRowsNeededFollowAvailableWidth() {
        for (available, expected) in [(CGFloat(1020), 1), (784, 1), (783, 2), (556, 2), (368, 3)] {
            let rows = HomeBandedLayout.rowsNeeded(
                items: Self.compactFourItems,
                availableWidth: available,
                columnSpacing: Self.bandMetrics.widgetColumnSpacing
            )
            XCTAssertEqual(rows, expected, "可用宽 \(available) 下应排 \(expected) 行")
        }
    }

    /// ② **主块带仍按旧规则丢块**并计入 `＋N`：四块（音乐档 + 三个模块档）在 702 可用宽下
    /// 只放得下两块，尾部两块被丢——与改动前那条 strip 的答案逐字一致（T7 只把它限定在「大块」上，
    /// 分配语义一字未动）。
    func testMainBandStillDropsTrailingBlocks() {
        let available = Self.panelWidth770StripWidth
        let plan = HomeBandedLayout.plan(
            mainItems: Self.syntheticFourBlockItems,
            widgetItems: [],
            availableWidth: available,
            widgetBandHeight: 0,
            metrics: Self.bandMetrics
        )

        XCTAssertEqual(plan.main.visibleCount, 2, "702 下四块只放得下两块（规则 ③）")
        XCTAssertEqual(plan.main.droppedCount, 2, "剩下两块靠条尾 ＋2 提示")
        XCTAssertTrue(plan.main.tailReserveUsed, "丢块时预留提示位")
        XCTAssertEqual(plan.droppedCount, 2, "整条首页的丢块数 = 主块带的丢块数（小组件带没有块）")
        XCTAssertTrue(plan.widgets.rows.isEmpty)
        XCTAssertEqual(plan.widgets.droppedCount, 0)
    }

    /// ③ 行数由**高度**定：两行的高度只够一行 → 只画第一行、第二行的格计入 `＋N`
    /// （**不是**把第一行压扁、也不是整条不画）。
    func testWidgetRowsFollowBandHeight() {
        let available: CGFloat = 760
        // 恰好放得下两行
        let both = HomeBandedLayout.plan(
            mainItems: [],
            widgetItems: Self.compactFourItems,
            availableWidth: available,
            widgetBandHeight: 2 * Self.widgetRowHeight + Self.widgetRowSpacing,
            metrics: Self.bandMetrics
        )
        XCTAssertEqual(both.widgets.rowsDrawn, 2)
        XCTAssertEqual(both.widgets.droppedCount, 0)

        // 差 0.1pt：只放得下一行
        let one = HomeBandedLayout.plan(
            mainItems: [],
            widgetItems: Self.compactFourItems,
            availableWidth: available,
            widgetBandHeight: 2 * Self.widgetRowHeight + Self.widgetRowSpacing - 0.1,
            metrics: Self.bandMetrics
        )
        XCTAssertEqual(one.widgets.rowsDrawn, 1, "第二行的高度不够 → 整行不画")
        XCTAssertEqual(one.widgets.visibleCount, 3, "第一行的三格仍在")
        XCTAssertEqual(one.widgets.droppedCount, 1, "第二行那一格计入 ＋N")
        XCTAssertTrue(one.widgets.showsHint, "有丢弃 → 画 ＋N")
        XCTAssertTrue(one.widgets.rows[0].showsHint, "提示位在**最后一行**（也就是唯一画出来的那行）")

        // 一行都放不下：高度按 0 给（接缝不会这么传——它在 `.widgetsOnly` 档才给高度，那一档保证
        // 至少一行放得下；这里钉住纯函数的退化行为）
        let none = HomeBandedLayout.plan(
            mainItems: [],
            widgetItems: Self.compactFourItems,
            availableWidth: available,
            widgetBandHeight: Self.widgetRowHeight - 0.1,
            metrics: Self.bandMetrics
        )
        XCTAssertEqual(none.widgets.rowsDrawn, 0)
        XCTAssertEqual(none.widgets.visibleCount, 0)
        XCTAssertEqual(none.widgets.droppedCount, 4, "一行都放不下 → 全部计入 ＋N")
    }

    /// 提示位（34pt）：只在真有丢弃时预留；**预留后这行的总宽仍不越过可用宽**；
    /// 预留把该行自己挤掉的格也如实计入 `＋N`（docs/21 §已知限制 6 的同一条口径）。
    func testWidgetHintReserveOnlyWhenBlocksAreDropped() {
        // 三块在 368 可用宽下排成两行（第一行两块 = 180 + 8 + 180 = 368 恰好用满）。
        let items = Array(Self.compactFourItems.prefix(3))
        let rowsNeeded = HomeBandedLayout.rowsNeeded(
            items: items,
            availableWidth: 368,
            columnSpacing: Self.bandMetrics.widgetColumnSpacing
        )
        XCTAssertEqual(rowsNeeded, 2, "368 下三块排两行（前两块恰好用满一行）")

        // 高度只够一行 → 第二行的第三块被丢；预留 34pt 提示位后又把第一行的第二块挤掉
        let plan = HomeBandedLayout.plan(
            mainItems: [],
            widgetItems: items,
            availableWidth: 368,
            widgetBandHeight: Self.widgetRowHeight,
            metrics: Self.bandMetrics
        )
        let row = plan.widgets.rows[0]
        XCTAssertTrue(row.showsHint, "有丢弃 → 在最后一行末尾留提示位")
        XCTAssertEqual(row.widths, [180], "预留 34pt 后第二块也放不下（该行只剩第一块）")
        XCTAssertEqual(plan.widgets.visibleCount, 1)
        XCTAssertEqual(plan.widgets.droppedCount, 2, "被挤掉的那块同样计入 ＋N（如实）")
        let used = row.widths.reduce(CGFloat.zero, +) + HomeStripView.droppedHintWidth
        XCTAssertLessThanOrEqual(used, 368 + 1e-9, "格 + 提示位的总宽不得越过可用宽")

        // 对照：同样一份名单给够两行的高度 → 不丢块、不预留提示位（第一行两块都用满它的 368）
        let enough = HomeBandedLayout.plan(
            mainItems: [],
            widgetItems: items,
            availableWidth: 368,
            widgetBandHeight: 2 * Self.widgetRowHeight + Self.widgetRowSpacing,
            metrics: Self.bandMetrics
        )
        XCTAssertEqual(enough.widgets.rowsDrawn, 2)
        XCTAssertEqual(enough.widgets.droppedCount, 0)
        XCTAssertFalse(enough.widgets.showsHint)
        XCTAssertEqual(enough.widgets.rows[0].widths, [180, 180], "没有丢弃 → 不预留提示位")
    }

    /// 空名单：两带都为空时什么都不摆（也不预留提示位）。
    func testEmptyBandsProduceEmptyPlan() {
        let plan = HomeBandedLayout.plan(
            mainItems: [],
            widgetItems: [],
            availableWidth: 702,
            widgetBandHeight: 200,
            metrics: Self.bandMetrics
        )
        XCTAssertEqual(plan.droppedCount, 0)
        XCTAssertTrue(plan.main.widths.isEmpty)
        XCTAssertTrue(plan.widgets.rows.isEmpty)
        XCTAssertEqual(plan.widgets.rowsNeeded, 0)
        XCTAssertEqual(plan.widgets.visibleCount, 0)
        XCTAssertFalse(plan.widgets.showsHint)
    }

    // MARK: - 形态钩子（T7 / D-09）

    /// ④ **`homeFormFactor` 的缺省与声明**：
    /// 缺省 `.compact`（什么都不声明的模块走协议扩展的缺省实现）、未注册的 id 也答缺省、
    /// 生产档**只剩镜子一个大块**（音乐自 p5-home-blocks / T3 起降为紧凑档），其余模块不写这一条。
    func testHomeFormFactorDefaultsToCompactAndLargeBlocksDeclareIt() async {
        registerProbes([HomeBareProbeModule.self])
        await ModuleRegistry.shared.bootstrap()
        let bareID = HomeBareProbeModule.manifest.id

        XCTAssertEqual(
            ModuleRegistry.shared.homeFormFactor(for: bareID), .compact,
            "缺省形态 = 紧凑块（小组件带）——新增模块不写这一条时的答案"
        )
        XCTAssertEqual(
            ModuleRegistry.shared.homeFormFactor(for: "com.cmeng.gourd.never-registered"), .compact,
            "未注册的 id 答缺省（与 homeBlockWidth(for:) 答 nil 的形态对齐：宿主拿到的总是「这个 id 的形态」）"
        )

        // 生产档：T3 起**只有镜子**是大块（元类型直取，走的是它自己的实现）；音乐同批降为紧凑档
        XCTAssertEqual(MusicModule.homeFormFactor, .compact, "音乐块 T3 起是紧凑块：降档后只剩一条（96 高）")
        XCTAssertEqual(MirrorModule.homeFormFactor, .large, "镜子块是大块：摄像头画面需要面积")
        XCTAssertEqual(ProgressModule.homeFormFactor, .compact, "进度是紧凑块（默认）")
        XCTAssertEqual(StatsModule.homeFormFactor, .compact, "统计是紧凑块（默认）")
        XCTAssertEqual(TodosModule.homeFormFactor, .compact, "待办是紧凑块（默认）")
        XCTAssertEqual(NotificationsModule.homeFormFactor, .compact, "通知是紧凑块（默认）")
        XCTAssertEqual(FrontAppModule.homeFormFactor, .compact, "前台应用是紧凑块（默认）")
    }

    /// **接缝按形态切带**：`.large` 进主块带、`.compact` 进小组件带，两带各自保持同一条全局顺序
    ///（覆盖值 + 默认序号 + id 字典序），宽度按各自的声明解析（样本大块 300/420、紧凑块走宿主统一值）。
    func testCatalogSplitsBandsByFormFactor() async {
        registerProbes([
            HomeWideProbeModule.self,
            HomeCompactAProbeModule.self,
            HomeCompactDProbeModule.self,
        ])
        await ModuleRegistry.shared.bootstrap()

        let catalog = HomeBandCatalog.resolve(registry: ModuleRegistry.shared, overrides: [:])

        XCTAssertEqual(catalog.main.map(\.id), [HomeWideProbeModule.manifest.id], "只有 .large 进主块带")
        XCTAssertEqual(
            catalog.widgets.map(\.id),
            [HomeCompactAProbeModule.manifest.id, HomeCompactDProbeModule.manifest.id],
            "紧凑块进小组件带，且按 (order, id) 排序（a 的 10 在 d 的 40 之前）"
        )
        XCTAssertEqual(catalog.main.first?.width, HomeBlockWidth(min: 300, ideal: 420), "大块样本按被接管块那一档声明（300/420）")
        XCTAssertEqual(catalog.widgets.first?.width, HomeBlockWidth(min: 180, ideal: 240), "紧凑块走宿主统一值")
        XCTAssertEqual(catalog.widgets.last?.width, HomeBlockWidth(min: 220, ideal: 300), "统计那一档的声明原样带回")
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

        let items = Self.syntheticFourBlockItems
        let available = Self.panelWidth770StripWidth
        // 接缝真正喂给主块带的宽度 = 托管宽 − 两侧容器内边距（T8）；渲染挂的是托管宽那份。
        let bandWidth = Self.bandContentWidth(forHostingWidth: available)
        let height: CGFloat = 212
        // **P4 起改走单条流**：这一档的预期不再是"一条 strip 里挤得下几块"，而是"流铺几行、
        // 高度放得下几行"——下面锚的数字是实测值，变了要有人复核。
        let plan = HomeFlowLayout.plan(
            items: Self.flowItems(items),
            availableWidth: bandWidth,
            availableHeight: height,
            calendarHeight: 0,
            metrics: HomeFlowLayout.Metrics(
                columnSpacing: HomeStripLayout.spacing,
                rowSpacing: HomeStripView.widgetRowSpacing,
                tailReserve: HomeStripView.droppedHintWidth
            )
        )

        // 锚：先把「这道题该是什么答案」钉住（数值变了要有人复核，而不是被断言静默吸收）
        XCTAssertEqual(available, 702, "770pt 面板的 strip 可用宽 = 770 − 两侧各 34（docs/17 §接口与数据形状 6）")
        XCTAssertEqual(
            bandWidth, 702 - HomeBandChrome.containerInset * 2,
            "T8：带级容器两侧各吃 8pt——带内可用宽 = 可用宽 − 16"
        )
        XCTAssertEqual(plan.rowsNeeded, 2, "四块（音乐档 300/420 + 三个 180/240）在 686 下铺两行")
        XCTAssertEqual(
            plan.visibleCount, 2,
            "高度 212 只放得下第一行那两块（行高 \(HomeFlowView.largeBlockHeight) + 缝 8 + 同样一行 > 212）"
        )
        XCTAssertEqual(plan.droppedCount, 2, "剩下两块靠条尾 ＋2 提示（docs/21）")
        XCTAssertTrue(plan.showsHint)

        renderRealHomeStrip(available: available, height: height)

        assertRenderedSizesMatchFlowPlan(plan)
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

        let items = Self.syntheticFourBlockItems
        let height: CGFloat = 212
        // **P4 起改走单条流**：三档宽度下的可见块数不再是"一条 strip 挤得下几块"，而是"流铺几行 ×
        // 高度放得下几行"。锚值（实到）：770 → 2、900 → 3、1088 → 4。
        for (panelWidth, expectedVisible) in [(CGFloat(770), 2), (900, 3), (1088, 4)] {
            homeBlockSizeLog.reset()
            let available = panelWidth - 68
            // T8：plan 按「带内可用宽」（= 托管宽 − 两侧容器内边距）算；渲染仍挂托管宽。
            let bandWidth = Self.bandContentWidth(forHostingWidth: available)
            let plan = HomeFlowLayout.plan(
                items: Self.flowItems(items),
                availableWidth: bandWidth,
                availableHeight: height,
                calendarHeight: 0,
                metrics: HomeFlowLayout.Metrics(
                    columnSpacing: HomeStripLayout.spacing,
                    rowSpacing: HomeStripView.widgetRowSpacing,
                    tailReserve: HomeStripView.droppedHintWidth
                )
            )

            XCTAssertEqual(plan.visibleCount, expectedVisible, "面板 \(panelWidth)pt（带内可用 \(bandWidth)）的可见块数")
            XCTAssertEqual(plan.droppedCount, items.count - expectedVisible)
            XCTAssertEqual(plan.showsHint, plan.droppedCount > 0, "丢块才画 ＋N")

            renderRealHomeStrip(available: available, height: height)
            assertRenderedSizesMatchFlowPlan(plan)
        }
    }

    /// **小组件带真的换行、一块都不丢**（渲染真值，T7 / 用户原话那条）。
    ///
    /// 4 个紧凑块在 770pt 面板（可用 702，**带内可用 686**）下**排成两行**：第一行三块各拿规则 ② 的
    /// 压缩宽 223（`686` 下 `180×3 + 2×8 = 556 ≤ 686 < 240×3 + 16 = 736`，可压缩量 180、缺口 50 →
    /// `180 + 60 × (1 − 50/180) = 223.33` → 落 0.5pt 网格 = 223），第二行的统计单块走规则 ① 拿它的
    /// ideal 300；四块都拿到尺寸（没有一块是零尺寸），行高恒为 96。**改动前它们是「一条 strip 装
    /// 四块」**：规则 ③ 从尾部丢到只剩两块（`t2-default-width-all-blocks.png` 那一档的实测就是
    /// 「6 块里第 6 块被丢」）——换行让第四块看得见，这正是本批的验收点。
    ///
    /// **T8 的数字变了**（228.5 → 223）：带级容器两侧各吃 8pt，行内可用宽 702 → 686，压缩解随之变。
    /// 断言仍是「渲染 == 规则」，不是「等于某个历史数」——变的只有代入的那一份宽度。
    func testWidgetBandRendersTwoRowsAtNarrowPanelWidth() async {
        homeBlockSizeLog.reset()
        registerProbes([
            HomeCompactAProbeModule.self,
            HomeCompactBProbeModule.self,
            HomeCompactCProbeModule.self,
            HomeCompactDProbeModule.self,
        ])
        await ModuleRegistry.shared.bootstrap()

        let available = Self.panelWidth770StripWidth
        // 两行要 2 × 96 + 8 = 200，给 400（接缝在这组入参下把 200 分给小组件带，见
        // `HomeVerticalFit` 的 `.both` / `.noCalendar` 两档——有没有日历行都是这个数）
        renderBandedWidgets(available: available, height: 400)

        let ids = HomeCompactProbeModule.ids
        let compressedRowWidth: CGFloat = 223
        let expected: [CGFloat] = [compressedRowWidth, compressedRowWidth, compressedRowWidth, 300]
        for (index, id) in ids.enumerated() {
            let size = homeBlockSizeLog.size(of: id)
            XCTAssertEqual(
                size.width, expected[index], accuracy: 0.5,
                "第 \(index) 块（\(id)）应拿到行内分配宽 \(expected[index])（换行后不丢块），实到 \(size.width)"
            )
            XCTAssertEqual(
                size.height, HomeStripView.widgetRowHeight, accuracy: 0.5,
                "小组件带的行高恒为 \(HomeStripView.widgetRowHeight)，实到 \(size.height)"
            )
        }
    }

    /// 渲染真值与 plan 的逐块对照：可见块 = 分配宽 + 满高；被丢的块 = 零尺寸；空白块数 == `droppedCount`。
    private func assertRenderedSizesMatchFlowPlan(
        _ plan: HomeFlowLayout.Plan,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let ids = HomeSizedProbeModule.ids
        // 每块的期望 = 它所在行给它的宽 + **那一行的高**（行高随行内最高块变，不再是全带一个数）。
        var expected: [Int: (width: CGFloat, height: CGFloat)] = [:]
        for row in plan.rows {
            for (position, blockIndex) in row.indices.enumerated() where position < row.widths.count {
                expected[blockIndex] = (row.widths[position], row.height)
            }
        }
        XCTAssertEqual(ids.count, plan.visibleCount + plan.droppedCount, "夹具块数应与 plan 的输入块数一致", file: file, line: line)

        for (index, id) in ids.enumerated() {
            let size = homeBlockSizeLog.size(of: id)
            if let want = expected[index] {
                XCTAssertEqual(
                    size.width, want.width, accuracy: 0.5,
                    "第 \(index) 块（\(id)）应拿到它那一行分配的宽 \(want.width)，实到 \(size.width)",
                    file: file, line: line
                )
                XCTAssertEqual(
                    size.height, want.height, accuracy: 0.5,
                    "第 \(index) 块（\(id)）应拿它那一行的高 \(want.height)（行高 = 行内最高块）",
                    file: file, line: line
                )
            } else {
                XCTAssertEqual(
                    size, .zero,
                    "第 \(index) 块（\(id)）没进任何一行（被丢）→ 必须是零尺寸，实到 \(size)",
                    file: file, line: line
                )
            }
        }

        let blanks = ids.filter { homeBlockSizeLog.size(of: $0) == .zero }
        XCTAssertEqual(
            blanks.count, plan.droppedCount,
            "＋\(plan.droppedCount) 与实际空白块数必须一致（实到空白 \(blanks.count) 块：\(blanks)）",
            file: file, line: line
        )
    }

    /// 探针夹具的流输入：`syntheticFourBlockItems` 加**大块档高**（那一族探针都答 `.large`，
    /// 见 `HomeSizedProbeModule` 的注释）。
    private static func flowItems(_ items: [HomeStripLayoutMath.Item]) -> [HomeFlowLayout.Item] {
        items.map { HomeFlowLayout.Item(min: $0.min, ideal: $0.ideal, height: HomeFlowView.largeBlockHeight) }
    }

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

    // MARK: - 自动高度：首页真拿得到它自己那份 plan 的需求（p5-home-blocks / T6）

    /// **自动高度下，首页拿到的 frame ≥ 它自己那份 plan 的需求**（T6 控制器 2026-10-01 实机测量）。
    ///
    /// 这条是**行为护栏**，不是常数断言：面板高由生产函数 `PanelAutoHeight.panelHeight(...)` 算，
    /// 首页真拿到的 frame 由面板内**每一项**折出来（下面逐项注明出处），再用生产 plan 在同一个
    /// frame 上判「日历行还在不在」，最后真渲染一遍。常数只要少一段，frame 就低于需求、日历行被
    /// 整行丢掉——实机那次（`homeVerticalPadding` 漏掉 `NotchLayout` 里表头与内容之间那道 8pt 缝）
    /// 就是这么丢的：AX 树里 0 个日格、面板下方空出约 300pt。
    func testAutoPanelHeightLeavesTheHomeTheHeightItsOwnPlanNeeds() async {
        homeBlockSizeLog.reset()
        registerProbes([HomeCompactAProbeModule.self])
        await ModuleRegistry.shared.bootstrap()

        let savedShowCalendar = Defaults[.showCalendar]
        Defaults[.showCalendar] = true
        defer { Defaults[.showCalendar] = savedShowCalendar }

        // 夹具：一块紧凑块（宿主统一档 180/240、档高 96）+ 日历行（按当月周数算高，见
        // `HomeCalendarRow.rowHeight`——T8 起 2026-10 = 232）。
        let available = Self.panelWidth770StripWidth
        let bandWidth = Self.bandContentWidth(forHostingWidth: available)
        let items = [flowItem(180, 240, HomeFlowView.compactBlockHeight)]
        // 表头高取实机的 `max(24, closedNotchHeight)` 那一档；它在**内容侧**（`contentHeight(...)`
        // 把它折进内容高），所以下面对 frame 的两处减法里都不该再出现它第二遍。
        let headerHeight: CGFloat = 28

        // ① 自然内容高（与接缝同一套生产调用：`naturalFlowBudget` 预算下的 plan → `contentHeight`）
        let naturalPlan = HomeFlowLayout.plan(
            items: items,
            availableWidth: bandWidth,
            availableHeight: PanelAutoHeight.naturalFlowBudget(
                hostChrome: headerHeight + PanelAutoHeight.homeVerticalPadding,
                screenVisibleHeight: nil
            ),
            calendarHeight: HomeCalendarRow.rowHeight,
            metrics: flowMetrics
        )
        let content = PanelAutoHeight.contentHeight(
            from: naturalPlan,
            calendarHeight: HomeCalendarRow.rowHeight,
            calendarSpacing: HomeCalendarRow.rowSpacing,
            headerHeight: headerHeight
        )
        let requirement = content - headerHeight
        XCTAssertEqual(
            requirement,
            HomeFlowView.compactBlockHeight + HomeCalendarRow.rowSpacing + HomeCalendarRow.rowHeight,
            "自然内容 = 流（96）+ 缝（8）+ 日历行（`HomeCalendarRow.rowHeight`，T8 起按当月周数）+ 表头（28）——先把这个等式钉住，下面的 frame 才有意义"
        )

        // ② 面板高走**生产函数**（auto 档；上界取不到屏 → 850，不触界）
        let panelHeight = PanelAutoHeight.panelHeight(
            contentHeight: content,
            mode: PanelAutoHeight.modeAuto,
            manualHeight: 200,
            screenVisibleHeight: nil
        )

        // ③ 首页真拿到的 frame = 面板高 − 面板内除首页内容之外的每一项（**逐项写死**，每项带出处）：
        //    表头 = `NotchLayout` 的 `max(24, closedNotchHeight)`（实机档 28）；
        //    16 = `NotchHomeView` 的 `.padding(8)` 上下各一；
        //    12 = `ContentView` 的 `.padding([.horizontal, .bottom], open ? 12 : 0)` 底边；
        //     4 = 同一处的 `.padding(.top, isIsland ? 0 : notchTopScreenBleedAmount)`；
        //     8 = `NotchLayout` 里表头与内容之间那道缝（`notchLayoutSpacing`）。
        //
        //    **刻意不引用 `homeVerticalPadding`**：引用它会让「常数」与「链路」用同一个符号，
        //    常数缩水时两边一起缩、用例照样绿（这正是上一版用例被评审判为无效的原因）。
        //    这几项是**链路的事实**（实机测过），常数必须 ≥ 它们的和——这就是本用例的判据。
        let chainBelowHeader = 16 + 12 + 4 + PanelAutoHeight.notchLayoutSpacing
        let frame = panelHeight - headerHeight - chainBelowHeader
        XCTAssertGreaterThanOrEqual(
            frame, requirement,
            "自动高度下面板必须给得住首页它自己那份 plan 的需求（少一段 → 日历行整行被丢）"
        )

        // ④ 同一个 frame 上跑一遍**生产 plan**：它想要的行必须一行不少（那块紧凑块 + 日历行）
        let drawnPlan = HomeFlowLayout.plan(
            items: items,
            availableWidth: bandWidth,
            availableHeight: frame,
            calendarHeight: HomeCalendarRow.rowHeight,
            metrics: flowMetrics
        )
        XCTAssertTrue(
            drawnPlan.showsCalendarRow,
            "frame ≥ 需求时日历行必须留下（plan 的阈值是闭区间；实机那次它是被丢掉的那一行）"
        )
        XCTAssertEqual(drawnPlan.rowsDrawn, 1, "紧凑块那一行也在，且不被丢")
        XCTAssertEqual(drawnPlan.droppedCount, 0, "两块（一块 + 日历行）都不丢")

        // ⑤ 真渲染一遍（同一个 frame、同一份夹具）：接缝把块摆出来（不是零提案的空布局）。
        //    用带 `vm` 的那只挂载壳——这一档的 frame 放得下日历行，它会被真的构造出来。
        renderCalendarBearingHome(available: available, height: frame)
        XCTAssertEqual(
            homeBlockSizeLog.size(of: HomeCompactProbeModule.ids[0]).height,
            HomeFlowView.compactBlockHeight,
            "接缝在自动高度的 frame 里把紧凑块摆出来了（拿到档高 96，不是被丢成 0）"
        )
    }

    /// 把**真的接缝**（`HomeBandedHomeView`）放进 `NSHostingView` 跑一趟布局：尺寸反馈只在真布局里
    /// 发生（纯函数测不到，探针脚本已验证），因此这里必须挂真视图而不是复刻一份结构——复刻的话，
    /// 被测的就成了复刻件，接缝里那句「提案宽钉在可用宽上」反而是「测外之物」。
    ///
    /// **T7 起挂的是接缝而不是单条带**：块名单、切带、高度取舍都在接缝里，只挂 `HomeStripView`
    /// 就测不到「紧凑块到底进了哪条带」（那正是本批的验收点）。夹具全部声明 `.large`（见
    /// `HomeSizedProbeModule`），因此这一条路径等价于改动前的「一条 strip」；小组件带走
    /// `renderBandedWidgets`（夹具是 `.compact`）。
    private func renderRealHomeStrip(available: CGFloat, height: CGFloat) {
        let host = NSHostingView(rootView: HomeBandedHost().frame(width: available, height: height))
        host.frame = CGRect(x: 0, y: 0, width: available, height: height)
        host.layoutSubtreeIfNeeded()
    }

    /// 把**真的接缝**放进 `NSHostingView`，夹具是**紧凑块**（走小组件带）——换行那条渲染真值用它。
    private func renderBandedWidgets(available: CGFloat, height: CGFloat) {
        renderRealHomeStrip(available: available, height: height)
    }

    /// **带日历行的挂载壳**（T6 的自动高度用例专用）：比上面那个多给一样环境对象——`vm`。
    /// `HomeCalendarRow` 用 `@EnvironmentObject var vm`，而其余渲染用例的 frame 都放不下日历行
    /// （它从不被构造），只有「日历行真的画出来」的那一条会撞上它：不给就崩在 `EnvironmentObject` 上，
    /// 用例的断言根本走不到（T6 实测：`Fatal error: No ObservableObject of type DynamicIslandViewModel found`）。
    private struct CalendarBearingHomeHost: View {
        private let viewModel = DynamicIslandViewModel()
        @Namespace private var albumArtNamespace

        var body: some View {
            HomeBandedHomeView(
                albumArtNamespace: albumArtNamespace,
                panelHeaderHeight: 28,
                pointerInsidePanel: false
            )
            .environmentObject(viewModel)
        }
    }

    /// 把带日历行的那个挂载壳放进 `NSHostingView` 跑一趟布局（与 `renderRealHomeStrip` 同形）。
    private func renderCalendarBearingHome(available: CGFloat, height: CGFloat) {
        let host = NSHostingView(rootView: CalendarBearingHomeHost().frame(width: available, height: height))
        host.frame = CGRect(x: 0, y: 0, width: available, height: height)
        host.layoutSubtreeIfNeeded()
    }

    /// 挂载壳：接缝要一条 matchedGeometry 命名空间（宿主本来是 `ContentView` 给的），
    /// p5-home-blocks / T6 起还要两样宿主事实（面板表头高 / 光标在不在面板里）——这里给**中性值**：
    /// 表头 0（不占垂直开销）、光标在面板外（「不缩」那条边界不生效）。本文件测的是摆放与宽度，
    /// 高度账本自己的用例在 `PanelAutoHeightTests`。
    private struct HomeBandedHost: View {
        @Namespace private var albumArtNamespace

        var body: some View {
            HomeBandedHomeView(
                albumArtNamespace: albumArtNamespace,
                panelHeaderHeight: 0,
                pointerInsidePanel: false
            )
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

    // MARK: - 单条流（P4 / docs/28 §4）

    /// 流的一行：行内块按下标给出，行高 = 行内最高块。
    private func flowRows(_ plan: HomeFlowLayout.Plan) -> [[Int]] {
        plan.rows.map(\.indices)
    }

    private func flowItem(_ min: CGFloat, _ ideal: CGFloat, _ height: CGFloat) -> HomeFlowLayout.Item {
        HomeFlowLayout.Item(min: min, ideal: ideal, height: height)
    }

    private var flowMetrics: HomeFlowLayout.Metrics {
        HomeFlowLayout.Metrics(columnSpacing: 8, rowSpacing: 8, tailReserve: 34)
    }

    /// **行高取行内最高块**：大块（档高 140）与紧凑块（96）并排时，这一行是 140；全是紧凑块的行是 96。
    func testFlowRowHeightIsMaxOfItsItems() {
        let items = [
            flowItem(300, 420, HomeFlowView.largeBlockHeight),   // 大块样本（档高 = 140）
            flowItem(180, 240, 96),    // 待办（紧凑）
            flowItem(180, 240, 96),    // 前台应用
            flowItem(220, 300, 96),    // 统计
        ]
        // 可用 964：大块 300 + 8 + 180 + 8 + 180 = 676 ≤ 964，再塞统计 220 → 904 ≤ 964 ✓（一行四块）
        let plan = HomeFlowLayout.plan(
            items: items, availableWidth: 964, availableHeight: 1000,
            calendarHeight: 0, metrics: flowMetrics
        )
        XCTAssertEqual(flowRows(plan), [[0, 1, 2, 3]], "四块按最小宽 904 ≤ 964，全在头一行")
        XCTAssertEqual(
            plan.rows[0].height, HomeFlowView.largeBlockHeight,
            "这一行有大块 → 行高取档高（T3 起 140，不再是从音乐封面量出来的 152）"
        )
    }

    /// **按最小宽贪心换行**：装不下就换行，**不丢块**（行数够时）。
    func testFlowWrapsInsteadOfDropping() {
        let items = (0..<5).map { _ in flowItem(180, 240, 96) }
        // 可用 560：180 + 8 + 180 = 368 ✓，再塞第三块 368 + 8 + 180 = 556 ≤ 560 ✓ → 一行三块
        let plan = HomeFlowLayout.plan(
            items: items, availableWidth: 560, availableHeight: 1000,
            calendarHeight: 0, metrics: flowMetrics
        )
        XCTAssertEqual(flowRows(plan), [[0, 1, 2], [3, 4]], "3 + 2 两行；换行不丢块")
        XCTAssertEqual(plan.droppedCount, 0, "高度够时一块都不丢")
        XCTAssertFalse(plan.showsHint, "没有丢弃就不画 ＋N")
    }

    /// **高度不够时按"整行"丢**（尾部行不画），丢掉的块计入 `＋N`。
    func testFlowDropsTrailingRowsAndHints() {
        let items = (0..<5).map { _ in flowItem(180, 240, 96) }
        // 两行要 96 + 8 + 96 = 200；给 100 只放得下第一行。
        // 可用宽取 600（一行三块 = 180×3 + 8×2 = 556 ≤ 600，且留出 ＋N 的 34 位后 556 ≤ 566 仍放得下）
        // ——**特意避开"提示位把本行挤掉一块"那条口径**（那条单独由下一个用例钉）。
        let plan = HomeFlowLayout.plan(
            items: items, availableWidth: 600, availableHeight: 100,
            calendarHeight: 0, metrics: flowMetrics
        )
        XCTAssertEqual(flowRows(plan), [[0, 1, 2]], "第二行整行不画（**不切半行**——P4 的病根）")
        XCTAssertEqual(plan.droppedCount, 2, "第二行那两块计入丢弃")
        XCTAssertTrue(plan.showsHint, "有丢弃 → 末行留出 ＋N 位")
        XCTAssertTrue(plan.rows[0].showsHint)
    }

    /// **提示位的代价**（既有口径，与旧小组件带一致）：末行留出 `＋N` 的 34pt 后，那一行自己可能
    /// 少放一块——少的那块如实计入 `droppedCount`。这条把代价写下来，免得后来人以为是算错了。
    func testFlowHintReserveMayCostOneCellInLastRow() {
        let items = (0..<5).map { _ in flowItem(180, 240, 96) }
        // 可用 560：三块 = 556 ≤ 560 本来放得下；但留 34 位后只剩 526 < 556 → 末行只放得下两块
        let plan = HomeFlowLayout.plan(
            items: items, availableWidth: 560, availableHeight: 100,
            calendarHeight: 0, metrics: flowMetrics
        )
        XCTAssertEqual(flowRows(plan), [[0, 1]], "为 ＋N 让出 34pt → 这一行只放得下两块")
        XCTAssertEqual(plan.droppedCount, 3, "两块在被丢掉的那一行 + 一块被提示位挤掉")
    }

    /// **日历行优先让位**（沿用 D-02）：放不下时先收日历行，再收流的尾部行。
    func testFlowCalendarRowYieldsFirst() {
        // 一行两块：大块样本 300/420 + 模块块 180/240 → 行高 = 档高
        let items = [
            flowItem(300, 420, HomeFlowView.largeBlockHeight),
            flowItem(180, 240, 96),
        ]
        // 日历行 232（2026-10 那一档）+ 缝 8 + 档高 140 = 380
        let fits = HomeFlowLayout.plan(
            items: items, availableWidth: 964, availableHeight: 460,
            calendarHeight: Self.calendarRowHeight, metrics: flowMetrics
        )
        XCTAssertTrue(fits.showsCalendarRow, "460 ≥ 380 → 日历行在")
        XCTAssertEqual(flowRows(fits), [[0, 1]])

        let tight = HomeFlowLayout.plan(
            items: items, availableWidth: 964, availableHeight: 300,
            calendarHeight: Self.calendarRowHeight, metrics: flowMetrics
        )
        XCTAssertFalse(tight.showsCalendarRow, "300 < 380 → **先收日历行**")
        XCTAssertEqual(flowRows(tight), [[0, 1]], "流那一行留着（日历行比它先让位）")
        XCTAssertEqual(tight.droppedCount, 0, "只收日历行不算丢块")

        let both = HomeFlowLayout.plan(
            items: items, availableWidth: 964, availableHeight: 100,
            calendarHeight: Self.calendarRowHeight, metrics: flowMetrics
        )
        XCTAssertFalse(both.showsCalendarRow)
        XCTAssertEqual(flowRows(both), [], "连第一行（档高 140）都放不下 → 流也不画")
        XCTAssertEqual(both.droppedCount, 2)
    }

    /// **用户实况那一档的分布**（面板 1041×853，全部组件开着；docs/28 §4.2 的预期表）。
    ///
    /// 名单是**当前生产声明**（p5-home-blocks / T3 之后：音乐紧凑、镜子 140/140 方形大块、
    /// 其余模块块走宿主统一 180/240、统计 220/300；T2 起音乐缩为 200/250）。
    /// 可用宽 = 1041 − 2 × 8（容器内边距）= 1025；可用高取 560
    ///（该档实测的内容高只有 ≈536：日历行 232（当月周数那一档）+ 缝 8 + 两行流（140 + 8 + 96）= 484
    /// ≤ 536 就装得下，取 560 是留一点余量——**恰好放得下**是这条用例要的题面）。
    func testFlowDistributionAtUserPanelSize() {
        let items = [
            flowItem(200, 250, 96),    // 音乐（T2 起再缩一档：200/250、96）
            flowItem(140, 140, HomeFlowView.largeBlockHeight),   // 镜子（方形大块：边长 = 档高）
            flowItem(180, 240, 96),    // 待办
            flowItem(180, 240, 96),    // 前台应用
            flowItem(180, 240, 96),    // 进度
            flowItem(180, 240, 96),    // 通知
            flowItem(220, 300, 96),    // 统计
        ]
        let plan = HomeFlowLayout.plan(
            items: items, availableWidth: 1025, availableHeight: 560,
            calendarHeight: Self.calendarRowHeight, metrics: flowMetrics
        )
        // 行1：音乐 200 + 8 + 镜子 140 + 8 + 待办 180 + 8 + 前台 180 + 8 + 进度 180 = 912 ≤ 1025 ✓
        // 行2：通知 180 + 8 + 统计 220 = 408 ✓
        XCTAssertEqual(
            flowRows(plan), [[0, 1, 2, 3, 4], [5, 6]],
            "全开时仍是「一行五块 + 一行两块」——音乐缩宽后第一行的成员没变"
        )
        XCTAssertEqual(
            plan.rows[0].height, HomeFlowView.largeBlockHeight,
            "第一行含大块（镜子 140）→ 行高 = 档高"
        )
        XCTAssertEqual(plan.rows[1].height, 96, "第二行全是紧凑块 → 96")
        XCTAssertEqual(plan.droppedCount, 0, "一块都不丢")
    }

    /// 空名单：没有块时不产生任何行（日历行仍按自己的高度单独存活）。
    func testFlowEmptyItems() {
        let plan = HomeFlowLayout.plan(
            items: [], availableWidth: 964, availableHeight: 300,
            calendarHeight: Self.calendarRowHeight, metrics: flowMetrics
        )
        XCTAssertTrue(plan.rows.isEmpty)
        XCTAssertEqual(plan.rowsNeeded, 0)
        XCTAssertEqual(plan.droppedCount, 0)
        XCTAssertTrue(plan.showsCalendarRow, "没有块时日历行单独存活")

        let noCalendar = HomeFlowLayout.plan(
            items: [], availableWidth: 964, availableHeight: 300,
            calendarHeight: 0, metrics: flowMetrics
        )
        XCTAssertFalse(noCalendar.showsCalendarRow)
    }

    /// `rowsNeeded` 与 `plan` 的行划分**同一份**（改一个就会红）。
    func testFlowRowsNeededMatchesPlan() {
        let items = (0..<7).map { _ in flowItem(180, 240, 96) }
        let needed = HomeFlowLayout.rowsNeeded(items: items, availableWidth: 560, columnSpacing: 8)
        let plan = HomeFlowLayout.plan(
            items: items, availableWidth: 560, availableHeight: 10_000,
            calendarHeight: 0, metrics: flowMetrics
        )
        XCTAssertEqual(needed, plan.rowsNeeded)
        XCTAssertEqual(needed, 3, "7 块 / 一行 3 块 = 3 行")
    }

    // MARK: - 首页块浮起（p6-ui-polish / docs/30 §做法 机制一 / D-02）

    /// **修饰符真正消费的效果值待在可读区间**（p6 / docs/30 §验收标准 A1；**本用例只钉 `.dark` 档**
    /// ——p7b 起签名按底色档分岔，玻璃档由 `testGlassSurfaceUsesDarkVeilEffects` 另钉）。
    ///
    /// 钉的是**纯函数 `HomeBlockFloatMetrics.effects(hovered:surface:)` 的两档输出**，不是常量本身
    /// （T1 首轮审查意见 2）：常量到应用的算式（含 brightness 的 `- 1`、两档映射的方向）改错
    /// 就会变红——例如去掉 brightness 的 `- 1`，hover 档的增量会变成 1.06 > 0.12 上界。
    ///
    /// 区间而不是定值（上屏调参由执行者在任务内做，调完回写 docs/31 §接口第 1 小节）：
    /// hover 的放大要让块「看得出浮起」但不至于像抖动（> 1.05 小字上开始像抖）；提亮要能分辨但
    /// 不得把字冲白（增量 > 0.12 浅色元素会糊）；两层光（柔光池 + 内容辉光）必须**常驻可见**
    /// （> 0，否则块与背景无区分）且 **hover 都更深**（否则 hover 与常驻没差别，机制一的 hover
    /// 半条腿没落地）；池半径系数 ≤ 0.5（最近边在 `0.5 × min(w, h)` 处——系数过大时边缘残留亮度，
    /// 形成直角台阶 = 变相底板）。
    ///
    /// **p7 档位扩展**（docs/31 §接口第 1 小节；静态区分加强后钉得更具体）：常驻池的不透明度
    /// ∈ **0.08…0.25**（p6 的 0.06 实机近不可见，下限抬到 0.08；上限 0.25 防池变「亮底」）、
    /// `hoverPoolOpacity − poolOpacity ≥ 0.03`（两档可辨差的下限）、`hoverGlowRadius > idleGlowRadius > 0`
    /// 与 `hoverGlowOpacity > idleGlowOpacity > 0`（辉光两档次序 + 常驻可见一并钉住），并补
    /// 「`effects(hovered:surface:)` 与声明常量同源」——修饰符只消费 effects，effects 与常量漂开就等于
    /// 测试钉的是另一个数（p6 两档断言只钉了次序，没钉同一性）。
    ///
    /// **本用例不是 hover 行为证据**：hover 驱动不出（合成事件进不了 tracking area，docs/30
    /// §已知限制 1 / D-20），这里钉的是效果算式；上屏的 hover 观感列入「需真人鼠标复核」清单
    /// （报告 T1 §待人工验收）。
    func testHomeBlockFloatMetricsStayInTheLegibleRange() {
        // p7b：签名按底色档分岔后**等价改写调用**（断言逐条不放宽）；本用例的档位是 `.dark`，
        // 即 p7 定稿的那一套白光常量——玻璃档的新增断言在下一个用例里。
        let idle = HomeBlockFloatMetrics.effects(hovered: false, surface: .dark)
        let hover = HomeBlockFloatMetrics.effects(hovered: true, surface: .dark)

        // 常驻档必须是中性：静止的块不被缩放、不被提亮，只有柔光池与辉光两层光可见。
        XCTAssertEqual(idle.scale, 1, "常驻不放大")
        XCTAssertEqual(idle.brightness, 0, "常驻不提亮（`.brightness` 的增量档是 0）")
        XCTAssertGreaterThan(idle.glowRadius, 0, "常驻辉光必须可见（半径 > 0）")
        XCTAssertGreaterThan(idle.glowOpacity, 0, "常驻辉光的不透明度为正")
        XCTAssertLessThanOrEqual(idle.glowOpacity, 0.5, "辉光是低透明度的一层，不该成「底」（不透明度 0…0.5）")
        // p7：常驻池的档位（下限 = 0.06 实测不可见后的可辨起点；上限防池变「亮底」）。
        XCTAssertGreaterThanOrEqual(idle.poolOpacity, 0.08, "常驻柔光池必须可辨（p7 下限 0.08）")
        XCTAssertLessThanOrEqual(idle.poolOpacity, 0.25, "常驻柔光池不该成「亮底」（p7 上限 0.25）")
        XCTAssertGreaterThan(HomeBlockFloatMetrics.poolEndRadiusFactor, 0, "池半径系数为正")
        XCTAssertLessThanOrEqual(
            HomeBlockFloatMetrics.poolEndRadiusFactor, 0.5,
            "池必须在**最近边之前**归零：最近边在 0.5 × min(w, h) 处，系数 > 0.5 时边缘仍残留亮度、"
                + "形成直角台阶 = 变相底板（0.7 曾实测残留 28.6%）"
        )

        // hover 档：光的两层（柔光池 + 内容辉光）都加深，放大与提亮待在可读区间。
        XCTAssertGreaterThan(hover.poolOpacity, idle.poolOpacity, "hover 柔光池要比常驻更亮")
        XCTAssertGreaterThanOrEqual(
            hover.poolOpacity - idle.poolOpacity, 0.03,
            "p7：两档池的可辨差有下限（≥ 0.03）——hover 与常驻必须分得出（p6 只钉了次序）"
        )
        XCTAssertGreaterThan(hover.glowRadius, idle.glowRadius, "hover 辉光半径要比常驻更大")
        XCTAssertGreaterThan(hover.glowOpacity, idle.glowOpacity, "hover 辉光不透明度要比常驻更大")
        XCTAssertGreaterThanOrEqual(hover.scale, 1.005, "hover 放大要看得出来")
        XCTAssertLessThanOrEqual(hover.scale, 1.05, "再大就不像浮起、像抖动")
        XCTAssertGreaterThanOrEqual(hover.brightness, 0.02, "hover 提亮要看得出来（增量 ≥ 0.02）")
        XCTAssertLessThanOrEqual(hover.brightness, 0.12, "再亮字就冲白了（增量 ≤ 0.12）")

        // p7：`effects(hovered:surface:)` 与声明常量**同源**——修饰符只消费 effects，两者漂开时上面的
        // 档位断言的就不是真正上屏的那个数（同一性，逐项钉）。
        XCTAssertEqual(idle.glowRadius, HomeBlockFloatMetrics.idleGlowRadius, "常驻辉光半径 = 声明常量")
        XCTAssertEqual(idle.glowOpacity, HomeBlockFloatMetrics.idleGlowOpacity, "常驻辉光不透明度 = 声明常量")
        XCTAssertEqual(idle.poolOpacity, HomeBlockFloatMetrics.poolOpacity, "常驻池 = 声明常量")
        XCTAssertEqual(hover.glowRadius, HomeBlockFloatMetrics.hoverGlowRadius, "hover 辉光半径 = 声明常量")
        XCTAssertEqual(hover.glowOpacity, HomeBlockFloatMetrics.hoverGlowOpacity, "hover 辉光不透明度 = 声明常量")
        XCTAssertEqual(hover.poolOpacity, HomeBlockFloatMetrics.hoverPoolOpacity, "hover 池 = 声明常量")
        XCTAssertEqual(hover.scale, HomeBlockFloatMetrics.hoverScale, "hover 放大 = 声明常量")
        XCTAssertEqual(
            hover.brightness, HomeBlockFloatMetrics.hoverBrightness - 1,
            "hover 提亮 = 常量 − 1（组装口径）"
        )

        // 动画时长：太快看不见、再慢就滞后于指针。
        XCTAssertGreaterThan(HomeBlockFloatMetrics.duration, 0.1, "太快看不见动画")
        XCTAssertLessThan(HomeBlockFloatMetrics.duration, 0.3, "再慢就滞后于指针")
    }

    /// **柔光池半径恒在最近边之前归零**（终审修复）：钉的不是系数本身，而是**有效半径**这条
    /// 不变量——`poolEndRadius(w, h) ≤ 0.5 × min(w, h)`。改回带下界的写法（曾为
    /// `max(48, min(w, h) × 0.45)`）时，块高 40 档立刻变红：`0.5 × 40 = 20 < 48`，下界把半径顶过
    /// 最近边，渐变在边缘残留亮度、形成直角台阶 = **变相底板**（正是本用例防的回归）。
    ///
    /// 三档块高取生产里的高度档（`HomeStripView.blockHeight(for:)` 的 140 / 96 与矮块 40 档），
    /// 每档配「宽 ≥ 高」与「宽 < 高」两侧的代表宽度：两条边都当过一次短边，`min` 的取法
    /// （别写死 height）一并钉住。零尺寸一档钉非负 guard（给 0，不给负半径）。
    func testHomeBlockPoolRadiusNeverCrossesTheNearestEdge() {
        let heights: [CGFloat] = [40, 96, 140]
        let widths: [CGFloat] = [60, 140, 180, 250, 400]
        for height in heights {
            for width in widths {
                let radius = HomeBlockFloatMetrics.poolEndRadius(width: width, height: height)
                let nearestEdge = 0.5 * min(width, height)
                XCTAssertLessThanOrEqual(
                    radius, nearestEdge,
                    "块 \(width)×\(height)：有效半径 \(radius) 必须 ≤ 最近边 \(nearestEdge)"
                        + "（渐变在最近边之前归零，否则边缘残留直角台阶 = 变相底板）"
                )
            }
        }
        XCTAssertEqual(
            HomeBlockFloatMetrics.poolEndRadius(width: 0, height: 140), 0,
            "0 宽给 0（非负 guard），不给负半径"
        )
        XCTAssertEqual(
            HomeBlockFloatMetrics.poolEndRadius(width: 140, height: 0), 0,
            "0 高给 0（非负 guard），不给负半径"
        )
    }

    /// **玻璃档用暗影池 + 暗影，黑档仍是白光两层**（p7b / docs/31 §验收标准 A1b · §决策摘要 D-22）。
    ///
    /// **本用例是回归护栏，不是复现证据**：`HomeBlockFloatModifier` 是视图修饰符，单测驱动不了
    /// 上屏渲染；复现由像素证据承担（修复前上屏实测白光池在毛玻璃底上只贡献 ≈ +10…+11/255、
    /// 被材质自身 ±4–5 的起伏淹没——`.workflow/p7b-glass-float/evidence/p7b-before-glass.png`
    /// 与 `p7b-measure.txt`；旧代码上本用例因 API 不存在根本无法编译）。它防两类回归：
    /// 玻璃档退回白光（亮底加亮 = 原缺陷）、黑档被顺手改成黑影（改动点只该是新增的玻璃档）。
    ///
    /// 钉四组：
    /// ① 玻璃档的池与影**都是暗色**（含 hover 两档）——亮底减亮；黑档两层仍是白、影 y 偏移恒 0；
    /// ② 玻璃档 hover 的池 / 影不透明度、影半径、影 y 偏移**四值都严格更深**（含「常驻必须可见」
    ///    与「不得成黑底」两条区间）；
    /// ③ 玻璃档 effects 与声明常量**逐项同源**（修饰符只消费 effects——漂开时上屏的不是这一组数）；
    /// ④ `NotchPanelBackgroundStyle` 三档映射（`.solidBlack → .dark`、两个玻璃档 → `.glass`）
    ///    与池半径不变量（两档共用同一条几何算式：块高三档都 ≤ `0.5 × min(w, h)`）。
    ///
    /// 黑档的既有口径一个字不放宽：白光两层与 y = 0 仍由上一个用例逐条钉住（这里只补「不暗」）。
    func testGlassSurfaceUsesDarkVeilEffects() {
        let glassIdle = HomeBlockFloatMetrics.effects(hovered: false, surface: .glass)
        let glassHover = HomeBlockFloatMetrics.effects(hovered: true, surface: .glass)
        let darkIdle = HomeBlockFloatMetrics.effects(hovered: false, surface: .dark)
        let darkHover = HomeBlockFloatMetrics.effects(hovered: true, surface: .dark)

        // ① 玻璃档：池与影都是暗色（亮底减亮）——静息与 hover 两档都不得退回白光。
        XCTAssertTrue(glassIdle.poolIsDark, "玻璃档常驻池必须是暗色（黑）")
        XCTAssertTrue(glassIdle.shadowIsDark, "玻璃档常驻影必须是暗色（黑）")
        XCTAssertTrue(glassHover.poolIsDark, "玻璃档 hover 池仍是暗色")
        XCTAssertTrue(glassHover.shadowIsDark, "玻璃档 hover 影仍是暗色")
        // 黑档：两层仍是白（修饰符选 `Color.white`），影无 y 偏移——与 p7 定稿逐字一致。
        XCTAssertFalse(darkIdle.poolIsDark, "黑档池仍是白色（p7 定稿不变）")
        XCTAssertFalse(darkIdle.shadowIsDark, "黑档影 / 辉光仍是白色（p7 定稿不变）")
        XCTAssertEqual(darkIdle.shadowYOffset, 0, "黑档影不带 y 偏移（逐字不变）")
        XCTAssertEqual(darkHover.shadowYOffset, 0, "黑档 hover 影也不带 y 偏移")

        // ② hover 严格更深：池 / 影不透明度、影半径、影 y 偏移四值都更大（两档可辨差）。
        XCTAssertGreaterThan(glassHover.poolOpacity, glassIdle.poolOpacity, "玻璃档 hover 池更深")
        XCTAssertGreaterThan(glassHover.glowOpacity, glassIdle.glowOpacity, "玻璃档 hover 影更深")
        XCTAssertGreaterThan(glassHover.glowRadius, glassIdle.glowRadius, "玻璃档 hover 影半径更大")
        XCTAssertGreaterThan(glassHover.shadowYOffset, glassIdle.shadowYOffset, "玻璃档 hover 影更沉")
        // 常驻必须可见（0 或负值 = 暗影不存在，缺陷原样）；又都只是低透明度的一层，不该成「黑底」。
        XCTAssertGreaterThan(glassIdle.poolOpacity, 0, "玻璃档常驻池必须可见")
        XCTAssertGreaterThan(glassIdle.glowOpacity, 0, "玻璃档常驻影必须可见")
        XCTAssertGreaterThan(glassIdle.glowRadius, 0, "玻璃档常驻影半径为正")
        XCTAssertLessThanOrEqual(glassIdle.poolOpacity, 0.25, "玻璃档常驻池不该成「黑底」")
        XCTAssertLessThanOrEqual(glassHover.poolOpacity, 0.35, "玻璃档 hover 池也不该成「黑底」")
        XCTAssertLessThanOrEqual(glassHover.glowOpacity, 0.5, "玻璃档 hover 影是低透明度的一层，不该成「黑底」")

        // ③ effects 与声明常量同源（修饰符只消费 effects，两者漂开时上屏的不是这一组数）。
        XCTAssertEqual(glassIdle.poolOpacity, HomeBlockFloatMetrics.glassPoolOpacity, "常驻池 = 声明常量")
        XCTAssertEqual(glassHover.poolOpacity, HomeBlockFloatMetrics.glassHoverPoolOpacity, "hover 池 = 声明常量")
        XCTAssertEqual(glassIdle.glowOpacity, HomeBlockFloatMetrics.glassShadowOpacity, "常驻影 = 声明常量")
        XCTAssertEqual(glassIdle.glowRadius, HomeBlockFloatMetrics.glassShadowRadius, "常驻影半径 = 声明常量")
        XCTAssertEqual(glassIdle.shadowYOffset, HomeBlockFloatMetrics.glassShadowYOffset, "常驻影 y = 声明常量")
        XCTAssertEqual(glassHover.glowOpacity, HomeBlockFloatMetrics.glassHoverShadowOpacity, "hover 影 = 声明常量")
        XCTAssertEqual(glassHover.glowRadius, HomeBlockFloatMetrics.glassHoverShadowRadius, "hover 影半径 = 声明常量")
        XCTAssertEqual(glassHover.shadowYOffset, HomeBlockFloatMetrics.glassHoverShadowYOffset, "hover 影 y = 声明常量")

        // ④ 三档映射：纯黑 → .dark；两个玻璃档 → .glass（两个玻璃档机制同源、各档取值一致）。
        XCTAssertEqual(HomeBlockFloatMetrics.surface(for: .solidBlack), .dark, "纯黑档走白光两层")
        XCTAssertEqual(HomeBlockFloatMetrics.surface(for: .frostedGlass), .glass, "毛玻璃档走暗影两层")
        XCTAssertEqual(HomeBlockFloatMetrics.surface(for: .liquidGlass), .glass, "液态玻璃档同走暗影两层")

        // ④ 池半径不变量（两档共用同一条几何算式）：块高三档 40 / 96 / 140 都 ≤ 0.5 × min(w, h)
        // ——暗影池仍是无边界径向渐变，渐变在最近边之前归零，不留直角台阶（不是卡片底）。
        for height in [CGFloat(40), 96, 140] {
            for width in [CGFloat(60), 140, 180, 250, 400] {
                let radius = HomeBlockFloatMetrics.poolEndRadius(width: width, height: height)
                XCTAssertLessThanOrEqual(
                    radius, 0.5 * min(width, height),
                    "块 \(width)×\(height)：池半径 \(radius) 必须 ≤ 最近边（暗影池同样不得留硬边）"
                )
            }
        }
    }

    // MARK: - 音乐块再缩宽（p6-ui-polish / docs/30 §做法 机制二 / D-03 · D-04）

    /// **T2 的三条钉**（docs/30 §接口与数据形状·机制二）：① min/ideal 取值；② **封面档装宽度**
    /// 关系式 `5×26 + 4×6 + 36 + 6 = 196 ≤ min`；③ 紧凑高度和 ≤ 96。
    ///
    /// 关系式而不是三个各自独立的魔数：封面打开那一档，「封面 + 封面距 + 五键 + 四道键距」必须
    /// 装进块声明的 `min`——破了这条，封面打开时控制键会被裁（T3 那次「控制三键整行被裁」的宽度版，
    /// 也是 docs/30 §验收标准 A2 的算术判据）。三个来源都读**生产常量**（不是用例里另抄一份）：
    /// - 块宽 = `MusicModule` 的命名常量（`homeBlockMinWidth` / `homeBlockIdealWidth`，声明从它们装）；
    /// - 四档键与封面值 = `MusicControlsView.CompactMetrics`（唯一取值处）；
    /// - 键径的**真源**是 `HoverButton.buttonSize(for:)` 的 `.small` 档（紧凑行的每个槽位都走它），
    ///   所以本用例同时钉它一档、并顺带把 `.medium` / `.large` 钉回 30 / 40——
    ///   展开面板等处的键尺寸必须与 T2 改动前逐字一致（docs/30 机制二的口径）。
    ///
    /// **本用例不是上屏证据**：真实布局里这条关系式成不成立（有没有别的内边距吃掉余量）由
    /// 控制器在 Checkpoint 上屏核对（截图 `.workflow/p6-ui-polish/evidence/t2-music-narrow.png`）。
    func testMusicBlockWidthAndCompactControlsFitTheMinimum() throws {
        typealias Metrics = MusicControlsView.CompactMetrics

        // ① min/ideal 取值（上屏调参由控制器回写；本用例钉当前档 200/250）
        let declared = try XCTUnwrap(MusicModule.homeBlockWidth, "音乐模块必须声明块宽（接管模块的那一档）")
        XCTAssertEqual(declared.min, 200, "T2 起 min 200（T3 是 240：封面档只剩 10pt 余量）")
        XCTAssertEqual(declared.ideal, 250, "T2 起 ideal 250（T3 是 300：那一档是配大封面选的）")
        XCTAssertEqual(MusicModule.homeBlockMinWidth, declared.min, "声明从命名常量装（两个 200 不许漂开）")
        XCTAssertEqual(MusicModule.homeBlockIdealWidth, declared.ideal, "声明从命名常量装（两个 250 不许漂开）")
        XCTAssertEqual(MusicModule.homeFormFactor, .compact, "宽度与形态同批（T2 只缩宽，不换档）")

        // ② 封面档的装宽度：四档取值先逐个钉，再钉求和式与 ≤ min 的关系
        XCTAssertEqual(Metrics.controlKeyDiameter, 26, "T2：控制键 30 → 26")
        XCTAssertEqual(Metrics.controlsKeySpacing, 6, "T2：键距 8 → 6")
        XCTAssertEqual(Metrics.albumArtSide, 36, "T2：封面 40 → 36")
        XCTAssertEqual(Metrics.albumArtSpacing, 6, "T2：封面距 8 → 6")
        XCTAssertEqual(
            HoverButton.buttonSize(for: .small), Metrics.controlKeyDiameter,
            "紧凑控制行的键径就是 HoverButton 的 .small 档——两处不一致时装宽度算式是假的"
        )
        XCTAssertEqual(HoverButton.buttonSize(for: .medium), 30, "展开面板的其余键仍是 30（T2 不动中档）")
        XCTAssertEqual(HoverButton.buttonSize(for: .large), 40, "展开面板的播放键仍是 40（T2 不动大档）")

        XCTAssertEqual(
            Metrics.albumArtRowInstallWidth, 196,
            "五键 + 四道键距 + 封面 + 封面距 = 5×26 + 4×6 + 36 + 6"
        )
        XCTAssertLessThanOrEqual(
            Metrics.albumArtRowInstallWidth, declared.min,
            "封面档的装宽度必须 ≤ 块声明的 min——超了就是「封面打开时控制键被裁」"
        )
        XCTAssertEqual(
            Metrics.albumArtRowInstallWidth + 4, declared.min,
            "余量 4（余量变成 0 或负就是踩线：字体 / 图标度量一漂就裁）"
        )

        // ③ 紧凑高度和 ≤ 96（装宽度之外的另一半：竖着也要装得下）
        XCTAssertLessThanOrEqual(
            Metrics.contentHeight, HomeFlowView.compactBlockHeight,
            "整条内容高（\(Metrics.contentHeight)）必须 ≤ 紧凑档高 \(HomeFlowView.compactBlockHeight)"
        )
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

/// 假首页块：只声明 `.home`，块宽按参数声明（样本沿用 T4 那一档：接管块档 300/420、新增模块 180/240）。
///
/// **根 conformer**（与 `TakeoverEnablementTests` 的 `TakeoverProbeBase` 同形）：`homeBlockWidth`
/// 与 `homeFormFactor` 写在**类体**里而不是留给协议扩展的默认实现——只有类体里的成员才会进
/// vtable，注册表的元类型查询（`registry.homeBlockWidth(for:)` / `homeFormFactor(for:)`）才会走到
/// 子类的 `override`。
///
/// **形态答 `.large`**（T7 起）：这一族夹具要测的是**主块带**的摆放语义（旧 strip 的丢块规则与
/// 「被判可见就必须真画出来」），因此四块都声明成大块——真实产品里只有镜子才是 `.large`
///（音乐自 p5-home-blocks / T3 起是 `.compact`），这里保住
/// 的是「一条带在同一组宽度声明下的行为」这条被测性质。
private class HomeSizedProbeModule: GourdModule {
    class var manifest: ModuleManifest {
        HomeStripFixture.manifest(shortID: "probe-sized", surfaces: [.home])
    }

    /// 本模块声明的块宽（nil = 走宿主统一值 180/240，与新增模块同口径）。
    class var homeBlockWidth: ModuleHomeBlockWidth? { nil }

    /// 本模块声明的**形态**（`.large` = 主块带；小组件带的夹具见 `HomeCompactProbeModule`）。
    class var homeFormFactor: HomeFormFactor { .large }

    /// 夹具四块的 id（**按 `order` 升序**，与 `HomeBandCatalog.resolve` 的排序同序）。
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

/// 接管块那一档样本（300/420，order 0）：丢块路径下第一块永远保得住，用它检验**第二块**也真的画出来。
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

// MARK: - 假模块 / 小组件带（T7 分带）

/// 紧凑块的尺寸探针根 conformer（T7 / docs/26 §做法 机制六）：四块都声明 `.compact`，
/// 因此走**小组件带**（网格换行）。宽度对齐生产档：前三块走宿主统一值 180/240
///（进度 / 待办 / 通知），第四块 220/300（统计那一档）。
///
/// 与 `HomeSizedProbeModule` 同形（形态同样写在**类体**里，见那边的注释）。
private class HomeCompactProbeModule: GourdModule {
    class var manifest: ModuleManifest {
        HomeStripFixture.manifest(shortID: "probe-compact", surfaces: [.home])
    }

    /// nil = 走宿主统一值 180/240。
    class var homeBlockWidth: ModuleHomeBlockWidth? { nil }

    /// **`.compact`**（小组件带）。
    class var homeFormFactor: HomeFormFactor { .compact }

    /// 夹具四块的 id（**按 `order` 升序**，与 `HomeBandCatalog.resolve` 的排序同序）。
    static let ids = [
        "com.cmeng.gourd.probe-compact-a",
        "com.cmeng.gourd.probe-compact-b",
        "com.cmeng.gourd.probe-compact-c",
        "com.cmeng.gourd.probe-compact-d",
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

/// 紧凑块一（order 10，宿主统一档 180/240）。
private final class HomeCompactAProbeModule: HomeCompactProbeModule {
    override class var manifest: ModuleManifest {
        HomeStripFixture.manifest(shortID: "probe-compact-a", surfaces: [.home], order: 10)
    }
}

/// 紧凑块二（order 20，宿主统一档 180/240）。
private final class HomeCompactBProbeModule: HomeCompactProbeModule {
    override class var manifest: ModuleManifest {
        HomeStripFixture.manifest(shortID: "probe-compact-b", surfaces: [.home], order: 20)
    }
}

/// 紧凑块三（order 30，宿主统一档 180/240）。
private final class HomeCompactCProbeModule: HomeCompactProbeModule {
    override class var manifest: ModuleManifest {
        HomeStripFixture.manifest(shortID: "probe-compact-c", surfaces: [.home], order: 30)
    }
}

/// 紧凑块四（order 40，**接管块那一档 220/300**——统计）：702 可用宽下它落第二行。
private final class HomeCompactDProbeModule: HomeCompactProbeModule {
    override class var manifest: ModuleManifest {
        HomeStripFixture.manifest(shortID: "probe-compact-d", surfaces: [.home], order: 40)
    }

    override class var homeBlockWidth: ModuleHomeBlockWidth? {
        ModuleHomeBlockWidth(min: 220, ideal: 300)
    }
}

/// **形态什么都不声明**的探针：`homeFormFactor` 由协议扩展的缺省实现回答（`.compact`）——
/// 钉住「缺省 = 紧凑块」这条，避免将来把缺省改成 `.large` 时没人发现（那会让所有新增模块
/// 都挤进主块带）。宽度声明照旧（只测形态那一维）。
private final class HomeBareProbeModule: GourdModule {
    class var manifest: ModuleManifest {
        HomeStripFixture.manifest(shortID: "probe-bare", surfaces: [.home], order: 10)
    }

    class var homeBlockWidth: ModuleHomeBlockWidth? { nil }

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
