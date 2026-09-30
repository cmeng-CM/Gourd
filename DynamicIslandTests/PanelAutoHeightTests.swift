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
//  PanelAutoHeightTests.swift
//  Gourd 展开面板 · 「贴内容」的高度算术（p5-home-blocks / T6）
//
//  覆盖 docs/29-home-blocks-and-panel.md §做法 机制六 / §接口与数据形状 与 D-11 / D-12 / D-16：
//
//  **模式与键**
//  - `Defaults.Keys.panelHeightMode`：裸字符串、默认 `"auto"`（与 `timerDisplayMode` 同形的存法）；
//  - `isAuto(_:)`：只有 `"manual"` 是手动档，**未知值一律按 auto**（裸字符串键的存量 / 手改值）。
//
//  **`panelHeight(...)` 的四个边界**（D-11）
//  - manual：**原样返回手动值**（连越界值都不夹——夹取由尺寸层既有的 `clampedOpenNotchHeight` 做，
//    那条链因此逐字还是今天那条）；
//  - auto：`内容高 + 上下内边距`，夹在 `[120, min(850, 屏可见高 × 0.9)]`；
//  - 内容高非有限（首帧还没算过）：回落手动值；
//  - 上下界夹取：内容极小 → 下界 120；内容极大 / 屏矮 → 上界（与滑块同一个上界函数）。
//
//  **per-tab 覆盖值**（D-16 / 机制六边界 ④）
//  - `mergedTabHeight(...)`：manual = 逐字替换（计时器 250 / 终端比例高），
//    auto = `max(覆盖值, 内容高)`——覆盖值是**下限**不是上限。
//
//  **收敛**（D-12）
//  - 种子高于内容 → 收缩、低于内容 → **长高**（不是单向棘轮：种子只有收缩一条路时，
//    内容高的面板永远长不上去）；
//  - 夹取后不回改内容（上界封顶时收敛值 = 上界）；
//  - manual 档不读内容（一步即返回手动值）。
//
//  **内容高的口径**
//  - `contentHeight(from:)` = 流内容高 + （画了日历行时的「缝 + 行高」）+ 面板表头；非有限项按 0；
//  - `naturalFlowBudget(...)` = 面板高上界 − 宿主垂直开销（有限数，不是无界）；
//  - `panelHeaderHeight(...)` = `max(24, effectiveClosedNotchHeight)`（与
//    `DynamicIslandCalendar` / `NotchTimerView` / `ContentView` 表头三处同源的那个数）；
//  - `homeVerticalPadding` = **面板内三处内边距的逐项求和**（16 + 12 + 4，每一项带出处；
//    加在返回尺寸**之上**的阴影带 18 与顶出血 4 刻意不计——见该常数的注释与 T6 评审 P2）。
//
//  **种子与持有者的往返**（T6 评审 P1）
//  - 持有者口径 = `面板高 − homeVerticalPadding`，尺寸层再 `+ homeVerticalPadding` → 对区间内的
//    任何面板高都必须**幂等**；不幂等就是漂移源（光标在面板里时 `heldForPointer` 会把种子原样
//    写回，每个 resize 事件推高一段）。
//
//  **尺寸出口**
//  - `openNotchSize`（`matters.swift`）在 auto 下读过渡持有者、manual 下逐字读滑块值；
//  - 右下角把手（D-16）：`showsPanelResizeHandle(isOpen:isMinimalistic:heightMode:)` 只在
//    **展开 + 非极简 + 手动档**三个条件全真时为真（auto 下拖动写的键当场没有效果）。
//

import AppKit
import Defaults
import XCTest

@testable import Gourd

@MainActor
final class PanelAutoHeightTests: XCTestCase {

    // MARK: - 键与模式

    func testPanelHeightModeIsABareStringKeyDefaultingToAuto() {
        XCTAssertEqual(PanelAutoHeight.modeAuto, "auto", "档名就是键的取值（裸字符串，无枚举）")
        XCTAssertEqual(PanelAutoHeight.modeManual, "manual")
        XCTAssertEqual(
            Defaults.Keys.panelHeightMode.defaultValue, "auto",
            "默认档 = 自适应（用户第 7 条反馈：面板高度按内容自适应）"
        )
        XCTAssertEqual(Defaults.Keys.panelHeightMode.name, "panelHeightMode", "键名与文档一致")
    }

    func testUnknownModeFallsBackToAuto() {
        XCTAssertTrue(PanelAutoHeight.isAuto("auto"))
        XCTAssertFalse(PanelAutoHeight.isAuto("manual"))
        XCTAssertTrue(PanelAutoHeight.isAuto("nonsense"), "未知值按默认档（auto）处理")
        XCTAssertTrue(PanelAutoHeight.isAuto(""), "空串同样按默认档")
    }

    // MARK: - panelHeight：自动 / 手动 / 非有限 / 上下界夹取

    func testPanelHeightAutoManualBoundsAndOverrides() {
        // ① manual：原样返回手动值——**不夹取**（夹取仍在 `clampedOpenNotchHeight`，那条链逐字未变）。
        XCTAssertEqual(
            PanelAutoHeight.panelHeight(
                contentHeight: 300, mode: PanelAutoHeight.modeManual,
                manualHeight: 837, screenVisibleHeight: 800
            ),
            837,
            "manual = 用户拨的值原样；837 在 800 屏上会被 `clampedOpenNotchHeight` 收成 720，但那一步不在这里"
        )
        XCTAssertEqual(
            PanelAutoHeight.panelHeight(
                contentHeight: 300, mode: PanelAutoHeight.modeManual,
                manualHeight: 20, screenVisibleHeight: nil
            ),
            20,
            "manual 连下界都不在这里夹（同一条理由）"
        )

        // ② auto：内容高 + 上下内边距，未触界时逐字就是这个和。
        // 面板内的三处内边距逐项求和（T6 评审 P2）：`NotchHomeView` 的 8+8、`ContentView`
        // 展开态的底边 12、刘海屏的顶出血 4（唯一的具名来源是 `notchTopScreenBleedAmount`）。
        // **不含** `notchShadowPaddingStandard`（18）与 `adjustedSizeForScreen` 的顶出血——
        // 那两项是加在 `panelHeight(...)` 返回值**之上**的窗口尺寸，折进来就是双重计数。
        XCTAssertEqual(notchTopScreenBleedAmount, 4, "顶出血那一项的具名来源（matters.swift）")
        XCTAssertEqual(PanelAutoHeight.homeVerticalPadding, 16 + 12 + 4, "= 8+8（NotchHomeView）+ 12（ContentView 底边）+ 4（顶出血）")
        XCTAssertEqual(
            PanelAutoHeight.panelHeight(
                contentHeight: 300, mode: PanelAutoHeight.modeAuto,
                manualHeight: 200, screenVisibleHeight: nil
            ),
            300 + 32,
            "300 + 32（宿主内边距 32）；nil 屏 → 上界回落 850，不触界"
        )

        // ③ 下界夹取：内容极小（甚至 0）也不低于可配下界 120。
        XCTAssertEqual(
            PanelAutoHeight.panelHeight(
                contentHeight: 0, mode: PanelAutoHeight.modeAuto,
                manualHeight: 200, screenVisibleHeight: nil
            ),
            openNotchHeightRange.lowerBound,
            "0 + 16 < 120 → 取下界"
        )

        // ④ 上界夹取：与滑块同一个上界函数（屏可见高 × 0.9，且不超过 850）。
        XCTAssertEqual(
            PanelAutoHeight.panelHeight(
                contentHeight: 5000, mode: PanelAutoHeight.modeAuto,
                manualHeight: 200, screenVisibleHeight: nil
            ),
            openNotchHeightRange.upperBound,
            "无屏信息 → 850"
        )
        XCTAssertEqual(
            PanelAutoHeight.panelHeight(
                contentHeight: 5000, mode: PanelAutoHeight.modeAuto,
                manualHeight: 200, screenVisibleHeight: 900
            ),
            810,
            "900 × 0.9 = 810 < 850 → 上界是 810（同一个 `effectiveOpenNotchHeightUpperBound`）"
        )
        XCTAssertEqual(
            PanelAutoHeight.panelHeight(
                contentHeight: 5000, mode: PanelAutoHeight.modeAuto,
                manualHeight: 200, screenVisibleHeight: 2000
            ),
            850,
            "屏再高也不越过可配上界 850"
        )

        // ⑤ 内容高非有限（首帧还没算过 / 异常读数）：回落手动值，不让 NaN 打掉面板尺寸。
        for invalid in [CGFloat.nan, .infinity, -.infinity] {
            XCTAssertEqual(
                PanelAutoHeight.panelHeight(
                    contentHeight: invalid, mode: PanelAutoHeight.modeAuto,
                    manualHeight: 333, screenVisibleHeight: 900
                ),
                333,
                "内容高 \(invalid) → 回落手动值（不做任何算术）"
            )
        }

        // ⑥ per-tab 覆盖值：manual 逐字替换（今天那条），auto 取 max（覆盖值是下限，D-16）。
        XCTAssertEqual(
            PanelAutoHeight.mergedTabHeight(
                override: 250, current: 420, mode: PanelAutoHeight.modeManual
            ),
            250,
            "manual：计时器档就是 250（逐字替换，今天的行为）"
        )
        XCTAssertEqual(
            PanelAutoHeight.mergedTabHeight(
                override: 250, current: 420, mode: PanelAutoHeight.modeAuto
            ),
            420,
            "auto：内容高（420）比覆盖值高 → 取内容高"
        )
        XCTAssertEqual(
            PanelAutoHeight.mergedTabHeight(
                override: 250, current: 130, mode: PanelAutoHeight.modeAuto
            ),
            250,
            "auto：内容高比覆盖值矮 → 覆盖值当下限"
        )
        XCTAssertEqual(
            PanelAutoHeight.mergedTabHeight(
                override: 250, current: 420, mode: "unknown"
            ),
            420,
            "未知档按 auto 处理（同 `isAuto`）"
        )
    }

    // MARK: - 内容高与自然高预算

    func testContentHeightAddsCalendarSeamAndHeader() {
        let metrics = HomeFlowLayout.Metrics(columnSpacing: 8, rowSpacing: 8, tailReserve: 34)
        let items = [HomeFlowLayout.Item(min: 140, ideal: 140, height: 140)]

        // 关掉日历行（`calendarHeight` 传 0）：内容高 = 流的内容高 + 表头。
        let noCalendar = HomeFlowLayout.plan(
            items: items, availableWidth: 700, availableHeight: 600,
            calendarHeight: 0, metrics: metrics
        )
        XCTAssertEqual(
            PanelAutoHeight.contentHeight(
                from: noCalendar, calendarHeight: 294, calendarSpacing: 8, headerHeight: 32
            ),
            140 + 32,
            "没有日历行时只加表头（缝不加）"
        )

        // 开了日历行且放得下：内容高 = 流 + 缝 + 行高 + 表头。
        let withCalendar = HomeFlowLayout.plan(
            items: items, availableWidth: 700, availableHeight: 600,
            calendarHeight: 294, metrics: metrics
        )
        XCTAssertTrue(withCalendar.showsCalendarRow, "600 高放得下 140 + 8 + 294")
        XCTAssertEqual(
            PanelAutoHeight.contentHeight(
                from: withCalendar, calendarHeight: 294, calendarSpacing: 8, headerHeight: 32
            ),
            140 + 8 + 294 + 32,
            "流内容高 + 缝 + 日历行高 + 表头"
        )

        // 高度不够时流方案自己先把日历行收掉（既有取舍）：内容高里因此不含它。
        let tooTight = HomeFlowLayout.plan(
            items: items, availableWidth: 700, availableHeight: 200,
            calendarHeight: 294, metrics: metrics
        )
        XCTAssertFalse(tooTight.showsCalendarRow, "200 高放不下日历行（既有口径：日历行先让位）")
        XCTAssertEqual(
            PanelAutoHeight.contentHeight(
                from: tooTight, calendarHeight: 294, calendarSpacing: 8, headerHeight: 32
            ),
            140 + 32,
            "方案没收日历行时不加它"
        )

        // 非有限项按 0（不让一个坏数把面板尺寸打掉）。
        XCTAssertEqual(
            PanelAutoHeight.contentHeight(
                from: noCalendar, calendarHeight: .nan, calendarSpacing: .nan, headerHeight: .nan
            ),
            140,
            "表头 / 缝 / 行高非有限 → 各自按 0"
        )
    }

    func testNaturalFlowBudgetStaysFiniteAndFollowsUpperBound() {
        XCTAssertEqual(
            PanelAutoHeight.naturalFlowBudget(hostChrome: 48, screenVisibleHeight: nil),
            850 - 48,
            "无屏信息 → 面板上界 850 扣掉宿主开销（**不是无界的预算**）"
        )
        XCTAssertEqual(
            PanelAutoHeight.naturalFlowBudget(hostChrome: 48, screenVisibleHeight: 900),
            810 - 48,
            "屏 900 → 上界 810"
        )
        XCTAssertEqual(
            PanelAutoHeight.naturalFlowBudget(hostChrome: 900, screenVisibleHeight: nil),
            0,
            "开销比上界还大（拿不到屏的极端配置）→ 预算按 0，不出现负值"
        )
        XCTAssertEqual(
            PanelAutoHeight.naturalFlowBudget(hostChrome: .nan, screenVisibleHeight: nil),
            850,
            "开销非有限按 0"
        )
    }

    func testPanelHeaderHeightSharesTheExistingChromeFormula() {
        XCTAssertEqual(PanelAutoHeight.panelHeaderHeight(effectiveClosedNotchHeight: 32), 32)
        XCTAssertEqual(PanelAutoHeight.panelHeaderHeight(effectiveClosedNotchHeight: 0), 24, "下限 24（同 ContentView 的 .frame(height:)）")
        XCTAssertEqual(PanelAutoHeight.panelHeaderHeight(effectiveClosedNotchHeight: 12), 24, "比下限矮 → 24")
        XCTAssertEqual(PanelAutoHeight.panelHeaderHeight(effectiveClosedNotchHeight: .nan), 24)
    }

    // MARK: - 收敛（D-12）

    func testConvergedPanelHeightGrowsAndShrinksBidirectionally() {
        let content: CGFloat = 400

        // 种子高于内容 → 收缩到「内容 + 内边距」。
        XCTAssertEqual(
            PanelAutoHeight.convergedPanelHeight(
                seedPanelHeight: 900, mode: PanelAutoHeight.modeAuto,
                manualHeight: 200, screenVisibleHeight: nil, contentHeight: { _ in content }
            ),
            432,
            "900 → 432（432 = 400 + 32）"
        )

        // 种子低于内容 → **长高**（不是单向棘轮：只许收缩时这一档永远长不上去）。
        XCTAssertEqual(
            PanelAutoHeight.convergedPanelHeight(
                seedPanelHeight: 150, mode: PanelAutoHeight.modeAuto,
                manualHeight: 200, screenVisibleHeight: nil, contentHeight: { _ in content }
            ),
            432,
            "150 → 432（这一条就是「不是棘轮」的判据）"
        )

        // 已经是不动点：一步返回同一个值。
        XCTAssertEqual(
            PanelAutoHeight.convergedPanelHeight(
                seedPanelHeight: 432, mode: PanelAutoHeight.modeAuto,
                manualHeight: 200, screenVisibleHeight: nil, contentHeight: { _ in content }
            ),
            432,
            "432 是不动点"
        )

        // 夹取后不回改内容：内容高到顶时收敛值就是上界（无屏信息 → 850）。
        XCTAssertEqual(
            PanelAutoHeight.convergedPanelHeight(
                seedPanelHeight: 300, mode: PanelAutoHeight.modeAuto,
                manualHeight: 200, screenVisibleHeight: nil, contentHeight: { _ in 5000 }
            ),
            850,
            "内容高 5000 → 夹到上界 850，不再回头拿 850 反推内容"
        )

        // 与预算有关的内容探针也收敛（探针是阶跃函数：面板越大，能画的行越多）。
        // 这里给的是「面板 < 500 时只有一行（200），否则两行（400）」的样式。
        XCTAssertEqual(
            PanelAutoHeight.convergedPanelHeight(
                seedPanelHeight: 900, mode: PanelAutoHeight.modeAuto,
                manualHeight: 200, screenVisibleHeight: nil,
                contentHeight: { height in height >= 500 ? 400 : 200 }
            ),
            232,
            "900 → 432 → 232 → 232：阶跃探针在 232（= 200 + 32）上稳定"
        )

        // manual：不读内容（一步返回手动值），种子怎么给都一样。
        XCTAssertEqual(
            PanelAutoHeight.convergedPanelHeight(
                seedPanelHeight: 900, mode: PanelAutoHeight.modeManual,
                manualHeight: 333, screenVisibleHeight: nil, contentHeight: { _ in 5000 }
            ),
            333,
            "manual 档由滑块说了算"
        )

        // 非有限种子：按手动值起算（不把 NaN 传进算术）。
        XCTAssertEqual(
            PanelAutoHeight.convergedPanelHeight(
                seedPanelHeight: .nan, mode: PanelAutoHeight.modeAuto,
                manualHeight: 120, screenVisibleHeight: nil, contentHeight: { _ in content }
            ),
            432,
            "种子 NaN → 从手动值 120 起算，仍然收敛到内容高"
        )
    }

    func testPointerInsidePanelOnlyBlocksShrinking() {
        // 光标在面板里 + 要收缩 → 保持当前（边界 ①：不把面板从光标底下抽走）。
        XCTAssertEqual(
            PanelAutoHeight.heldForPointer(converged: 300, currentPanelHeight: 600, pointerInsidePanel: true),
            600
        )
        // 光标在面板里 + 要长高 → 长高（「只允许长高」不是「不许变」）。
        XCTAssertEqual(
            PanelAutoHeight.heldForPointer(converged: 700, currentPanelHeight: 600, pointerInsidePanel: true),
            700
        )
        // 光标在面板外 → 照常贴合（§已知限制 1：移开鼠标后下一次重算才缩回去）。
        XCTAssertEqual(
            PanelAutoHeight.heldForPointer(converged: 300, currentPanelHeight: 600, pointerInsidePanel: false),
            300
        )
        // 非有限值不参与比较（原样透传，不把 NaN 变成某个数）。
        XCTAssertTrue(
            PanelAutoHeight.heldForPointer(converged: .nan, currentPanelHeight: 600, pointerInsidePanel: true).isNaN,
            "收敛值非有限 → 原样返回（不引入新的算术）"
        )
    }

    // MARK: - 尺寸出口：auto 读持有者、manual 逐字读滑块

    /// **持有者往返必须幂等**（T6 评审 P1 的护栏）：持有者写的是 `面板高 − homeVerticalPadding`，
    /// 尺寸层读回来再 `+ homeVerticalPadding` —— 对区间内的任何面板高这两个方向必须回到同一个数。
    ///
    /// 为什么这条是漂移的护栏：接缝的种子取的是**权威的当前面板高**（`openNotchSize.height`），
    /// 光标在面板里时 `heldForPointer` 会把种子原样写回持有者；若持有者口径与 `panelHeight(...)`
    /// 的加数不一致（例如种子由「几何高 + 假设的开销」重建、而假设比真实少一段），写回的就不是
    /// 当前值而是「当前值 ± 那一段」，下一次重算再拿它当种子——**每个 resize 事件都推走一段**。
    /// 这里把一致性钉在纯函数层：种子取权威值时，往返必然回到原值。
    func testHolderPaddingRoundTripKeepsTheAuthoritativeSeedFromDrifting() {
        let panelHeights: [CGFloat] = [
            openNotchHeightRange.lowerBound,   // 下界（120）：夹取后仍在区间内
            200,                               // 滑块的出厂档
            432,                               // 内容高 400 + 内边距 32
            630,                               // 曾经的默认面板档
            openNotchHeightRange.upperBound    // 无屏信息时的上界（850）
        ]
        for panelHeight in panelHeights {
            let holderValue = panelHeight - PanelAutoHeight.homeVerticalPadding
            XCTAssertEqual(
                PanelAutoHeight.panelHeight(
                    contentHeight: holderValue,
                    mode: PanelAutoHeight.modeAuto,
                    manualHeight: 200,
                    screenVisibleHeight: nil
                ),
                panelHeight,
                "面板高 \(panelHeight) 经持有者往返必须回到同一个数（口径不一致就是漂移源）"
            )
        }
        // 敏感性：持有者多写了 20pt（正是「种子由几何高 + 少算一段的假设开销重建」时的形态）→
        // 面板高就跟着涨 20pt。这条把 P1 那个漂移的成因钉在纯函数层：多写的那一段 = 涨的那一段，
        // 1:1 —— 所以两侧的加数必须同一份，种子必须取权威值。
        let driftedHolderValue = (432 - PanelAutoHeight.homeVerticalPadding) + 20
        XCTAssertEqual(
            PanelAutoHeight.panelHeight(
                contentHeight: driftedHolderValue,
                mode: PanelAutoHeight.modeAuto,
                manualHeight: 200,
                screenVisibleHeight: nil
            ),
            432 + 20,
            "持有者多写 20pt → 面板高多 20pt（漂移 1:1）"
        )
    }

    func testOpenNotchSizeReadsHolderInAutoAndVerbatimManualInManual() {
        let savedMode = Defaults[.panelHeightMode]
        let savedHeight = Defaults[.openNotchHeight]
        let savedContent = PanelAutoHeight.homeContentHeight
        defer {
            Defaults[.panelHeightMode] = savedMode
            Defaults[.openNotchHeight] = savedHeight
            PanelAutoHeight.homeContentHeight = savedContent
        }

        // manual：与改动前逐字一致——滑块值（经 `clampedOpenNotchHeight` 夹取）就是面板高，
        // 持有者写什么与它无关（auto → manual 切档时不会残留内容高）。
        Defaults[.panelHeightMode] = PanelAutoHeight.modeManual
        Defaults[.openNotchHeight] = 333
        PanelAutoHeight.homeContentHeight = 999
        XCTAssertEqual(
            openNotchSize.height, 333,
            "manual 档不读内容高（改动前那条：`clampedOpenNotchHeight(Defaults[.openNotchHeight])`）"
        )

        // auto：读持有者 → `内容 + 宿主内边距` → 夹取。
        Defaults[.panelHeightMode] = PanelAutoHeight.modeAuto
        PanelAutoHeight.homeContentHeight = 400
        XCTAssertEqual(openNotchSize.height, 432, "auto 档 = 内容高 400 + 宿主内边距 32")

        // auto + 还没有人算过（首帧）：回落手动值（§已知限制 2 的「首帧一拍」）。
        PanelAutoHeight.homeContentHeight = nil
        XCTAssertEqual(openNotchSize.height, 333, "持有者为 nil → 回落手动值")

        // auto + 内容高离谱（超过可配上界）：夹到上界（上界本身与屏相关，期望值按同一个函数取）。
        let upper = effectiveOpenNotchHeightUpperBound(
            screenVisibleHeight: NSScreen.main?.visibleFrame.height
        )
        PanelAutoHeight.homeContentHeight = 5000
        XCTAssertEqual(openNotchSize.height, upper, "内容高再大也不越过有效上界")
    }

    // MARK: - 右下角把手（D-16）

    func testResizeHandleHiddenInAutoMode() {
        // 出现：只有「展开 + 非极简 + 手动档」三个条件全真。
        XCTAssertTrue(
            showsPanelResizeHandle(isOpen: true, isMinimalistic: false, heightMode: PanelAutoHeight.modeManual),
            "展开 + 标准 + 手动档 = 出现（拖动写 `openNotchHeight`，当场有效）"
        )

        // 三条否掉的档：全都是「拖了没用」的同一条理由。
        XCTAssertFalse(
            showsPanelResizeHandle(isOpen: true, isMinimalistic: false, heightMode: PanelAutoHeight.modeAuto),
            "auto 档：高度由内容决定，拖动写的键当场没有效果 → 隐藏"
        )
        XCTAssertFalse(
            showsPanelResizeHandle(isOpen: true, isMinimalistic: false, heightMode: "nonsense"),
            "未知档按 auto 处理 → 同样隐藏"
        )
        XCTAssertFalse(
            showsPanelResizeHandle(isOpen: true, isMinimalistic: true, heightMode: PanelAutoHeight.modeManual),
            "极简档：尺寸来源是 `minimalisticOpenNotchSize`，手动档的值不参与 → 隐藏（既有行为）"
        )
        XCTAssertFalse(
            showsPanelResizeHandle(isOpen: false, isMinimalistic: false, heightMode: PanelAutoHeight.modeManual),
            "折叠态没有把手（既有行为）"
        )
    }
}
