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
//  - `homeVerticalPadding` = **面板内四处内边距的逐项求和**（16 + 12 + 4 + 8，每一项带出处；
//    加在返回尺寸**之上**的阴影带 18 与顶出血 4 刻意不计——见该常数的注释、T6 评审 P2
//    与控制器 2026-10-01 的实机测量）。
//
//  **种子与账本的往返**（T6 评审 P1）
//  - 账本口径 = `面板高 − homeVerticalPadding`，尺寸层再 `+ homeVerticalPadding` → 对区间内的
//    任何面板高都必须**幂等**；不幂等就是漂移源（光标在面板里时 `heldForPointer` 会把种子原样
//    写回，每个 resize 事件推高一段）。
//
//  **尺寸出口**
//  - `openNotchSize`（`matters.swift`）在 auto 下读高度账本（`PanelContentHeight.current`）、
//    manual 下逐字读滑块值；
//  - 右下角把手（D-16）：`showsPanelResizeHandle(isOpen:isMinimalistic:heightMode:)` 只在
//    **展开 + 非极简 + 手动档**三个条件全真时为真（auto 下拖动写的键当场没有效果）。
//
//  **高度账本与其它 tab 的测量**（T7 / D-12，本文件下半部分）
//  - `report(_:for:)` 的四条款：非有限值忽略 / 同一 tab 差 < 8pt 忽略（滞回）/ 换 tab 无条件接受
//    （判在光标规则之前）/ 同一 tab 且光标在面板内时只接受变大；
//  - 首页那一份**权威**：量出来的值碰不到 `homeContentHeight`，`home` 键的上报被忽略；
//  - `measuredContentHeight(naturalHeight:headerHeight:)` 的换算（自然高 + 表头 − 16）与
//    「整页填满内容区 → 面板高是**不动点**」这条不漂移的算式；
//  - 探针量的是**理想高**（不是摆放后的高）：`NSHostingView` 里挂真视图，换行数看上报值跟着内容走
//    （量摆放后的高 = 量容器，反馈环；这条用例是那个判断的行为护栏）；`isCurrent = false` 的旧页
//    一次都不报（切 tab 那 0.3s 的防抖闸门）。
//

import AppKit
import Defaults
import SwiftUI
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
        // 面板内的**四处**内边距逐项求和（T6 评审 P2 + 控制器 2026-10-01 实机测量）：
        // `NotchHomeView` 的 8+8、`ContentView` 展开态的底边 12、刘海屏的顶出血 4、
        // `NotchLayout` 里表头与内容之间那道缝 8（`notchLayoutSpacing`，原先走平台默认值、
        // 不具名也不算进预算，实测因此让日历行整行被丢）。
        // **不含** `notchShadowPaddingStandard`（18）与 `adjustedSizeForScreen` 的顶出血——
        // 那两项是加在 `panelHeight(...)` 返回值**之上**的窗口尺寸，折进来就是双重计数。
        XCTAssertEqual(notchTopScreenBleedAmount, 4, "顶出血那一项的具名来源（matters.swift）")
        XCTAssertEqual(PanelAutoHeight.notchLayoutSpacing, 8, "表头↔内容那道缝（ContentView 的 NotchLayout）")
        XCTAssertEqual(
            PanelAutoHeight.homeVerticalPadding,
            16 + 12 + 4 + PanelAutoHeight.notchLayoutSpacing,
            "= 8+8（NotchHomeView）+ 12（ContentView 底边）+ 4（顶出血）+ 8（表头↔内容的缝）"
        )
        XCTAssertEqual(
            PanelAutoHeight.panelHeight(
                contentHeight: 300, mode: PanelAutoHeight.modeAuto,
                manualHeight: 200, screenVisibleHeight: nil
            ),
            300 + PanelAutoHeight.homeVerticalPadding,
            "300 + 宿主内边距（40）；nil 屏 → 上界回落 850，不触界"
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
            440,
            "900 → 440（440 = 400 + 宿主内边距 40）"
        )

        // 种子低于内容 → **长高**（不是单向棘轮：只许收缩时这一档永远长不上去）。
        XCTAssertEqual(
            PanelAutoHeight.convergedPanelHeight(
                seedPanelHeight: 150, mode: PanelAutoHeight.modeAuto,
                manualHeight: 200, screenVisibleHeight: nil, contentHeight: { _ in content }
            ),
            440,
            "150 → 440（这一条就是「不是棘轮」的判据）"
        )

        // 已经是不动点：一步返回同一个值。
        XCTAssertEqual(
            PanelAutoHeight.convergedPanelHeight(
                seedPanelHeight: 440, mode: PanelAutoHeight.modeAuto,
                manualHeight: 200, screenVisibleHeight: nil, contentHeight: { _ in content }
            ),
            440,
            "440 是不动点"
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
            240,
            "900 → 440 → 240 → 240：阶跃探针在 240（= 200 + 40）上稳定"
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
            440,
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
            440,                               // 内容高 400 + 内边距 40
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
        let driftedHolderValue = (440 - PanelAutoHeight.homeVerticalPadding) + 20
        XCTAssertEqual(
            PanelAutoHeight.panelHeight(
                contentHeight: driftedHolderValue,
                mode: PanelAutoHeight.modeAuto,
                manualHeight: 200,
                screenVisibleHeight: nil
            ),
            440 + 20,
            "持有者多写 20pt → 面板高多 20pt（漂移 1:1）"
        )
    }

    func testOpenNotchSizeReadsHolderInAutoAndVerbatimManualInManual() {
        let savedMode = Defaults[.panelHeightMode]
        let savedHeight = Defaults[.openNotchHeight]
        let ledger = PanelContentHeight.shared
        ledger.reset()
        defer {
            Defaults[.panelHeightMode] = savedMode
            Defaults[.openNotchHeight] = savedHeight
            // 账本是**单例**：跑完必须还原，否则下一条用例读到本条留下的值。
            ledger.reset()
        }

        // manual：与改动前逐字一致——滑块值（经 `clampedOpenNotchHeight` 夹取）就是面板高，
        // 账本写什么与它无关（auto → manual 切档时不会残留内容高）。
        Defaults[.panelHeightMode] = PanelAutoHeight.modeManual
        Defaults[.openNotchHeight] = 333
        ledger.setHomeContentHeight(999)
        XCTAssertEqual(
            openNotchSize.height, 333,
            "manual 档不读内容高（改动前那条：`clampedOpenNotchHeight(Defaults[.openNotchHeight])`）"
        )

        // auto：读账本（首页那一份）→ `内容 + 宿主内边距` → 夹取。
        Defaults[.panelHeightMode] = PanelAutoHeight.modeAuto
        ledger.setHomeContentHeight(400)
        XCTAssertEqual(openNotchSize.height, 440, "auto 档 = 内容高 400 + 宿主内边距 40")

        // auto + 还没有人算过（首帧）：回落手动值（§已知限制 2 的「首帧一拍」）。
        ledger.setHomeContentHeight(nil)
        XCTAssertEqual(openNotchSize.height, 333, "账本里没有值 → 回落手动值")

        // auto + 内容高离谱（超过可配上界）：夹到上界（上界本身与屏相关，期望值按同一个函数取）。
        let upper = effectiveOpenNotchHeightUpperBound(
            screenVisibleHeight: NSScreen.main?.visibleFrame.height
        )
        ledger.setHomeContentHeight(5000)
        XCTAssertEqual(openNotchSize.height, upper, "内容高再大也不越过有效上界")

        // auto + 面板停在别的 tab 上（T7）：尺寸出口读的是**量出来的那一份**（同一个出口、同一口径）。
        ledger.report(300, for: "com.cmeng.gourd.todos")
        XCTAssertEqual(openNotchSize.height, 340, "量出来的 300 与算出来的走同一个出口（300 + 40）")
    }


    // MARK: - 高度账本：四条款（T7 / D-12）

    /// `report(_:for:)` 的**四条口径**（派发片段裁决 3 逐条对应）。
    ///
    /// 为什么这四条是账本的全部语义：高度是从**布局**里量出来的，而布局又跟着面板高走——
    /// 没有这四条，测量就是一个反馈环（面板一变→ 内容重排 → 再报一次 → 再变）。四条各挡一类：
    /// ① 坏读数不进门；② 同一页的微动（秒数 / 进度）不碰窗口；③ 换页必须能当场换（含光标停在
    /// 面板里那一档，否则点 tab 的手永远等不到面板变矮）；④ 同一页变小只在光标不在面板里时接受
    /// （不把面板从光标底下抽走，§已知限制 1）。
    func testContentHeightReportHysteresisAndGrowthOnly() {
        let ledger = PanelContentHeight.shared
        ledger.reset()
        defer { ledger.reset() }

        let todos = "com.cmeng.gourd.todos"
        let notifications = "com.cmeng.gourd.notifications"

        // 谁都没报过：`nil` → 尺寸层回落手动值（§已知限制 2 的「首帧一拍」）。
        XCTAssertNil(ledger.current, "账本空 → 尺寸层回落手动值")

        // ① 非有限值忽略（不把 NaN / ±∞ 写成面板高）。
        for invalid in [CGFloat.nan, .infinity, -.infinity] {
            ledger.report(invalid, for: todos)
            XCTAssertNil(ledger.current, "非有限值 \(invalid) 不进门")
        }

        // 同一 tab 的第一次上报（还没有值）：接受。
        ledger.report(300, for: todos)
        XCTAssertEqual(ledger.current, 300)
        XCTAssertEqual(ledger.activeTab, todos, "当前页 = 最后一个被接受的页")

        // ② 滞回：差 < 8pt 忽略（两个方向都忽略）。
        ledger.report(305, for: todos)
        XCTAssertEqual(ledger.current, 300, "5pt 的微动（秒数跳动那一类）不改窗口")
        ledger.report(293, for: todos)
        XCTAssertEqual(ledger.current, 300, "收缩方向同样滞回")

        // 差 ≥ 8pt 才接受（阈值取闭区间下界：正好 8 要接受，不然「差 8 永远不改」是个死角）。
        ledger.report(308, for: todos)
        XCTAssertEqual(ledger.current, 308, "正好 8pt → 接受")
        ledger.report(300, for: todos)
        XCTAssertEqual(ledger.current, 300, "回落 8pt → 同样接受")

        // ④ 光标在面板内：只接受变大。
        ledger.pointerInsidePanel = { true }
        ledger.report(200, for: todos)
        XCTAssertEqual(ledger.current, 300, "光标在面板内 → 缩小被拦（面板不从光标底下抽走）")
        ledger.report(420, for: todos)
        XCTAssertEqual(ledger.current, 420, "光标在面板内 → 变大照常接受")

        // 光标移开：下一次上报就贴合（§已知限制 1 的「移开鼠标才贴合」）。
        ledger.pointerInsidePanel = { false }
        ledger.report(210, for: todos)
        XCTAssertEqual(ledger.current, 210, "光标离开 → 缩小照常")

        // ③ 换 tab 无条件接受——**判在光标规则之前**：光标还停在面板里、新页更矮，也必须换。
        ledger.pointerInsidePanel = { true }
        ledger.report(150, for: notifications)
        XCTAssertEqual(ledger.current, 150, "换 tab 无条件接受（含光标在面板里那一档）")
        XCTAssertEqual(ledger.activeTab, notifications)

        // 换回来也一样（没有「记住旧页」的第二份状态：每次换页都要按新页的量值重新定）。
        ledger.report(320, for: todos)
        XCTAssertEqual(ledger.current, 320, "换回旧页同样无条件接受")
    }

    /// 首页那一份**权威**（派发片段裁决 4）：量出来的值碰不到它，`home` 键也不接上报。
    func testHomeHeightStaysAuthoritativeAndMeasuredValuesCannotOverwriteIt() {
        let ledger = PanelContentHeight.shared
        ledger.reset()
        defer { ledger.reset() }

        // 首页那份是接缝**算**出来的（T6 那条路），写进自己的槽。
        ledger.setHomeContentHeight(400)
        XCTAssertEqual(ledger.current, 400)
        XCTAssertEqual(ledger.activeTab, PanelContentHeight.homeTab)

        // 别的页上报：当前页换人，但首页那一份原样保留（量出来的值碰不到它）。
        ledger.report(250, for: "com.cmeng.gourd.todos")
        XCTAssertEqual(ledger.current, 250, "别人当班 → 读别人量出来的那一份")
        XCTAssertEqual(ledger.homeContentHeight, 400, "首页那一份原样保留（权威）")

        // 回到首页：接缝在 body 里再写一次（每帧都写）→ 当前值立刻回到首页那一份。
        ledger.setHomeContentHeight(400)
        XCTAssertEqual(ledger.current, 400, "首页当班 → 读算出来的那一份")

        // `home` 键的上报被忽略（首页有自己的槽，不许两条路写同一个值）。
        ledger.report(999, for: PanelContentHeight.homeTab)
        XCTAssertEqual(ledger.current, 400, "`home` 键的上报不进门")
        XCTAssertEqual(ledger.measuredHeight, 250, "`home` 键的上报没写脏量出来的那一槽")

        // 空串（还没选中模块 / 没选中扩展）= 不是一页，同样不进门。
        ledger.report(123, for: "")
        XCTAssertEqual(ledger.current, 400)
    }

    /// **谁上报**的名单（派发片段裁决 6）：内容随条数变的那四页；另外四页刻意不在里面，
    /// 逐条理由在 `PanelContentHeight.measuredTabs`（量它们 = 把面板高喂回自己）。
    func testMeasuredTabListIsTheFourCountDrivenPages() {
        XCTAssertEqual(
            PanelContentHeight.measuredTabs,
            [
                "com.cmeng.gourd.todos",
                "com.cmeng.gourd.notifications",
                "com.cmeng.gourd.launcher",
                "com.cmeng.gourd.shortcuts",
            ],
            "名单 = 内容随条数变的那四页（多一个 / 少一个都要连理由一起改）"
        )
        XCTAssertEqual(PanelContentHeight.hysteresis, 8, "滞回阈值 = 8pt（docs/29 §做法 机制六）")

        XCTAssertFalse(PanelContentHeight.isMeasuredTab(nil), "还没选中模块 → 不上报")
        XCTAssertFalse(PanelContentHeight.isMeasuredTab(""), "空键 → 不上报")
        XCTAssertFalse(
            PanelContentHeight.isMeasuredTab(PanelContentHeight.homeTab),
            "首页有算出来的那一份，不走测量"
        )
        // 未覆盖的四页：日历 / 计时器（自然高是面板高的函数）、暂存器 / 终端（整块填满，没有自然高）。
        XCTAssertFalse(
            PanelContentHeight.isMeasuredTab("com.cmeng.gourd.calendar"),
            "日历的 `.frame(height: maxTabContentHeight)` 是面板高的函数——量它每接受一次就缩 12pt"
        )
        XCTAssertFalse(PanelContentHeight.isMeasuredTab("com.cmeng.gourd.timer"))
        XCTAssertFalse(PanelContentHeight.isMeasuredTab("shelf"))
        XCTAssertFalse(PanelContentHeight.isMeasuredTab("terminal"))
    }

    // MARK: - 测量值 → 内容高（T7 的换算与不动点）

    /// 换算与**不动点**：非首页 tab 的宿主开销是共享那份 24（`12 + 4 + 8`），与首页那份 40 的差
    /// 是 `NotchHomeView` 的 16（只有首页有）。于是「自然高 N、表头 H」的一页要的内容高是
    /// `N + H − 16`；整页**填满**内容区时（`N = 面板高 − H − 24`）代进去正好回到**同一个面板高**
    /// ——这是「量摆放后的高不会成棘轮」的算式，也是量理想高时同一页反复量不会漂的判据。
    func testMeasuredContentHeightStepsAndFullBleedFixedPoint() {
        XCTAssertEqual(PanelAutoHeight.homeVerticalPadding, 40, "首页那一份（T6）")
        XCTAssertEqual(
            PanelAutoHeight.panelVerticalPadding,
            12 + 4 + PanelAutoHeight.notchLayoutSpacing,
            "共享那一份 = ContentView 的底 12 + 顶出血 4 + 表头↔内容的缝 8"
        )
        XCTAssertEqual(
            PanelAutoHeight.homeOnlyVerticalPadding,
            PanelAutoHeight.homeVerticalPadding - PanelAutoHeight.panelVerticalPadding,
            "首页独有的那一份 = 两者之差"
        )
        XCTAssertEqual(PanelAutoHeight.homeOnlyVerticalPadding, 16, "= NotchHomeView 的 8 + 8")

        // 换算：+ 表头、− 首页独有的 16；非有限项各自按 0。
        XCTAssertEqual(
            PanelAutoHeight.measuredContentHeight(naturalHeight: 300, headerHeight: 28), 312
        )
        XCTAssertEqual(
            PanelAutoHeight.measuredContentHeight(naturalHeight: .nan, headerHeight: 28), 12,
            "自然高非有限按 0（账本本来就不收非有限值，这是第二道）"
        )
        XCTAssertEqual(
            PanelAutoHeight.measuredContentHeight(naturalHeight: 114, headerHeight: .nan), 98
        )

        // 不动点：填满的一页量完之后面板高不漂移（区间内的任意档都成立）。
        let header: CGFloat = 28
        for panelHeight: CGFloat in [openNotchHeightRange.lowerBound, 200, 440, 630, 850] {
            let natural = panelHeight - header - PanelAutoHeight.panelVerticalPadding
            let content = PanelAutoHeight.measuredContentHeight(
                naturalHeight: natural, headerHeight: header
            )
            XCTAssertEqual(
                PanelAutoHeight.panelHeight(
                    contentHeight: content, mode: PanelAutoHeight.modeAuto,
                    manualHeight: 400, screenVisibleHeight: nil
                ),
                panelHeight,
                "面板高 \(panelHeight)：量出来 → 折成内容高 → 再算回面板高 = 同一个数（不漂）"
            )
        }

        // 内容短的一页：面板高 = 自然高 + 表头 + 24（**贴合**——手算一遍与上一条互证）。
        let shortContent = PanelAutoHeight.measuredContentHeight(naturalHeight: 120, headerHeight: 28)
        XCTAssertEqual(
            PanelAutoHeight.panelHeight(
                contentHeight: shortContent, mode: PanelAutoHeight.modeAuto,
                manualHeight: 400, screenVisibleHeight: nil
            ),
            120 + 28 + PanelAutoHeight.panelVerticalPadding,
            "等于「自然高 + 表头 + 共享内边距」，不多不少"
        )
    }

    // MARK: - 探针（真布局里量：理想高，不是摆放后的高）

    /// 夹具：一页**填满**面板的典型形态（表头 + 可滚动清单 + 脚注 + 内边距）——四页的根部都是
    /// 这个形状（`.frame(maxHeight: .infinity)` 到底），因此它量出来的值最有代表性。
    ///
    /// `recorder` 收的是这一页**摆放后**的自报高（与探针报的理想高是两回事）。**不用 preference**：
    /// `Layout` 容器是**偏好屏障**（子视图的 `PreferenceKey` 不越过它）——所以这里在 `GeometryReader`
    /// 的 body 里直接写引用盒子（布局期求值，只用例可见）。
    private struct FillStylePageFixture: View {
        let rowCount: Int
        var recorder: LaidOutSizeBox?

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Color.clear.frame(height: 20) // 表头
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(0..<rowCount, id: \.self) { _ in
                            Color.clear.frame(height: 16)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                Color.clear.frame(height: 10) // 脚注
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                GeometryReader { proxy in
                    let _ = recorder?.record(proxy.size)
                    Color.clear
                }
            )
        }
    }

    /// 收尺寸的小盒子（引用类型：布局期的回调闭包只能捕获它）。
    private final class LaidOutSizeBox {
        private(set) var size: CGSize = .zero
        func record(_ size: CGSize) { self.size = size }
    }

    /// 把夹具挂进 `NSHostingView`（容器 700×600）跑一趟真布局——探针只在布局里发生。
    /// 返回挂载壳本身（用例里要留着它，别让视图还没布局就被回收）；`laidOutSize` 收夹具**摆放后**
    /// 的自报高（探针的透明性判据：整页还要是 600 高，不是 114）。
    @discardableResult
    private func mountFillStylePage(
        rowCount: Int,
        tab: String,
        headerHeight: CGFloat,
        isCurrent: @escaping @MainActor () -> Bool,
        laidOutSize: LaidOutSizeBox? = nil
    ) -> NSHostingView<some View> {
        let view = FillStylePageFixture(rowCount: rowCount, recorder: laidOutSize)
            .panelContentHeightReport(tab: tab, headerHeight: headerHeight, isCurrent: isCurrent)
            .frame(width: 700, height: 600)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 700, height: 600)
        host.layoutSubtreeIfNeeded()
        return host
    }

    /// **探针对渲染透明**（`sizeThatFits` 逐字转发提案）：整页在这一层里面仍然把这个 700×600 的
    /// 格子填满——探针要是把它压成「理想高」，页面就不再填满面板（滚动区会缩成内容那么高、
    /// 长列表再也滚不动），那是比高度不对更重的回归。
    func testProbeKeepsThePageFillingItsContainer() {
        let ledger = PanelContentHeight.shared
        ledger.reset()
        defer { ledger.reset() }

        let laidOut = LaidOutSizeBox()
        let host = mountFillStylePage(
            rowCount: 3, tab: "com.cmeng.gourd.todos", headerHeight: 24,
            isCurrent: { true }, laidOutSize: laidOut
        )
        XCTAssertEqual(
            laidOut.size, CGSize(width: 700, height: 600),
            "填满的一页在探针里还是填满（提案逐字转发，摆放尺寸 = 子视图自己接受的尺寸）"
        )
        withExtendedLifetime(host) {}
    }

    /// **探针量的是理想高**（本批覆盖范围的全部依据）：同一页在同一个 600 高的容器里，行数一多
    /// 上报值就必须跟着长——量「摆放后的高」的话两次都是容器给的那个数（恒等），面板再也不会变。
    ///
    /// 这一条用**行为**钉住机制（不钉 SwiftUI 的某个具体返回值）：换行数看差，且两者都远小于容器高。
    func testProbeReportsThePagesIdealHeightNotTheContainerHeight() {
        let ledger = PanelContentHeight.shared
        ledger.reset()
        defer { ledger.reset() }

        let tab = "com.cmeng.gourd.todos"
        let header: CGFloat = 24

        let threeRows = mountFillStylePage(rowCount: 3, tab: tab, headerHeight: header, isCurrent: { true })
        XCTAssertEqual(ledger.activeTab, tab, "布局时探针上报了（挂上就报，不需要等交互）")
        let three = ledger.current

        let eightRows = mountFillStylePage(rowCount: 8, tab: tab, headerHeight: header, isCurrent: { true })
        let eight = ledger.current

        guard let three, let eight else {
            return XCTFail("探针没有上报（`current` 为 nil）")
        }

        // ① **量的是这一页的自然高**（实测 122 / 222，算术逐项对得上）：
        //    3 行 = 表头 20 + （3×16 + 2×4 = 56）清单 + 脚注 10 + 行距 12 + 内边距 16 = **114**
        //    → 账本值 = 114 + 表头 24 − 首页独有的 16 = **122**（`measuredContentHeight` 的换算）
        //    8 行 = 114 + 5×20 = 214 → **222**
        XCTAssertEqual(three, 122, accuracy: 0.5, "自然高 114 + 表头 24 − 16")
        XCTAssertEqual(eight, 222, accuracy: 0.5, "自然高 214 + 表头 24 − 16")

        // ② 上报值**跟着内容走**（3 行 → 8 行：多 5 行 ×（16 行高 + 4 行距）= 100pt）。
        XCTAssertEqual(
            eight - three, 5 * (16 + 4), accuracy: 1,
            "行数变化 1:1 落到上报值上（±1 是布局取整）"
        )

        // ③ 上报值**不是容器高**：600 高的容器里量出来的是 122，不是 600（也不是 600 减表头内边距）。
        XCTAssertLessThan(three, 300, "量的是理想高，不是容器给的 600")
        XCTAssertGreaterThan(three, 24, "至少把面板表头含进去（口径是「内容高含表头」）")

        // ④ 与「面板高」的关系：折出来的面板高就是这一页的内容高 + 宿主内边距（贴合、可复算）。
        XCTAssertEqual(
            PanelAutoHeight.panelHeight(
                contentHeight: three, mode: PanelAutoHeight.modeAuto,
                manualHeight: 400, screenVisibleHeight: nil
            ),
            three + PanelAutoHeight.homeVerticalPadding,
            "账本里的值就是尺寸层要的那个数（同一条换算）"
        )
        withExtendedLifetime(threeRows) {}
        withExtendedLifetime(eightRows) {}
    }

    /// **不是当班的那一页不报**（`isCurrent` 闸门）：切 tab 的 0.3s 里旧页还活着、还会被重新布局，
    /// 而条款 ③ 是「换 tab 无条件接受」——旧页一量到新尺寸就会把账本抢回去（面板来回跳）。
    func testStalePageReportIsDropped() {
        let ledger = PanelContentHeight.shared
        ledger.reset()
        defer { ledger.reset() }

        let host = mountFillStylePage(
            rowCount: 3, tab: "com.cmeng.gourd.todos", headerHeight: 24, isCurrent: { false }
        )
        XCTAssertNil(ledger.current, "不当班的页一次都不报（旧页在过渡里的那一拍）")
        XCTAssertNil(ledger.activeTab)
        withExtendedLifetime(host) {}
    }

    /// **不在名单里的页**一个值都不写（覆盖范围的负向护栏）：拿日历的键挂同一个夹具，账本必须
    /// 保持空——名单外的页要回落「今天的行为」（手动值），悄悄写一个值就是另一套高度来源。
    func testUnlistedPageWritesNothingEvenWhenProbed() {
        let ledger = PanelContentHeight.shared
        ledger.reset()
        defer { ledger.reset() }

        let host = mountFillStylePage(
            rowCount: 3, tab: "com.cmeng.gourd.calendar", headerHeight: 24, isCurrent: { true }
        )
        XCTAssertNil(ledger.current, "名单外的页（日历）不上报")
        XCTAssertNil(ledger.activeTab)
        withExtendedLifetime(host) {}
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
