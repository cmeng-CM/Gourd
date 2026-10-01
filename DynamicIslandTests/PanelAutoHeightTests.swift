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
//  **首页两支的账本键**（终审 T-final / F1 / D-57）：**侧歌词档**（`NotchHomeView` 的第二支）
//  用 `PanelContentHeight.sideLyricsHomeTab`——没人上报的键 → `current` = nil → 回落手动值；
//  判据 `showsSideLyricsHomeLayout(...)` 与键映射 `homePanelTabKey(showsSideLyricsLayout:)`
//  两处都由用例直接钉住；标准路径（首页键 + 接缝写的那份值）逐字不变。
//
//  **hover 退出 × 面板自己动**（p6-ui-polish 回归修复：「切日历页不再塌回关闭态」）：
//  auto 高度切页会在指针底下把面板缩短，SwiftUI 的 `.onHover(false)` 与隐藏态轮询都会把它
//  读成「指针离开面板」——判据 `shouldHonorHoverExit` 拿**面板与指针最后一次接触**时的窗口
//  rect 判「指针还在不在面板里」（`ContentView.swift`，判据层用例在本文件末）。
//

import AppKit
import Combine
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
        ledger.selectTab(PanelContentHeight.homeTab)
        ledger.setHomeContentHeight(999)
        XCTAssertEqual(
            openNotchSize.height, 333,
            "manual 档不读内容高（改动前那条：`clampedOpenNotchHeight(Defaults[.openNotchHeight])`）"
        )

        // auto：读账本（首页那一份）→ `内容 + 宿主内边距` → 夹取。
        Defaults[.panelHeightMode] = PanelAutoHeight.modeAuto
        ledger.selectTab(PanelContentHeight.homeTab)
        ledger.setHomeContentHeight(400)
        XCTAssertEqual(openNotchSize.height, 440, "auto 档 = 内容高 400 + 宿主内边距 40")

        // auto + 还没有人算过（首帧）：回落手动值（§已知限制 2 的「首帧一拍」）。
        ledger.setHomeContentHeight(nil)
        XCTAssertEqual(openNotchSize.height, 333, "账本里没有值 → 回落手动值")

        // auto + 内容高离谱（超过可配上界）：夹到上界（上界本身与屏相关，期望值按同一个函数取）。
        let upper = effectiveOpenNotchHeightUpperBound(
            screenVisibleHeight: NSScreen.main?.visibleFrame.height
        )
        ledger.selectTab(PanelContentHeight.homeTab)
        ledger.setHomeContentHeight(5000)
        XCTAssertEqual(openNotchSize.height, upper, "内容高再大也不越过有效上界")

        // auto + 面板停在别的 tab 上（T7）：尺寸出口读的是**量出来的那一份**（同一个出口、同一口径）。
        ledger.selectTab("com.cmeng.gourd.todos")
        ledger.report(300, for: "com.cmeng.gourd.todos")
        XCTAssertEqual(openNotchSize.height, 340, "量出来的 300 与算出来的走同一个出口（300 + 40）")

        // auto + 切到**名单外**的页（计时器 / 终端）：回落手动值（今天的行为）。
        ledger.selectTab("terminal")
        XCTAssertEqual(
            openNotchSize.height, 333,
            "名单外的页没有值 → 手动值（不是继承上一页量出来的 300）"
        )
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

    /// 首页那一份**权威**（派发片段裁决 4 + T7 复核 P2）：量出来的值碰不到它，`home` 键不接上报，
    /// 而且**首页的写入不碰「当前页」**——切 tab 过渡里旧首页再跑一次 body，也不能把刚量完的模块页
    /// 顶掉（`activeTab` 只由 `selectTab(_:)` 定）。
    func testHomeHeightStaysAuthoritativeAndMeasuredValuesCannotOverwriteIt() {
        let ledger = PanelContentHeight.shared
        ledger.reset()
        defer { ledger.reset() }

        // 首页那份是接缝**算**出来的（T6 那条路），写进自己的槽；当班与否由 `selectTab` 声明。
        ledger.selectTab(PanelContentHeight.homeTab)
        ledger.setHomeContentHeight(400)
        XCTAssertEqual(ledger.current, 400)
        XCTAssertEqual(ledger.activeTab, PanelContentHeight.homeTab)

        // 别的页上报：当前页换人，但首页那一份原样保留（量出来的值碰不到它）。
        ledger.selectTab("com.cmeng.gourd.todos")
        ledger.report(250, for: "com.cmeng.gourd.todos")
        XCTAssertEqual(ledger.current, 250, "别人当班 → 读别人量出来的那一份")
        XCTAssertEqual(ledger.homeContentHeight, 400, "首页那一份原样保留（权威）")

        // **旧首页再写一次也不能把当前页抢回去**（切 tab 的 0.3s 里旧页还活着）：
        // 槽被更新（那是首页自己的数），但 `current` 仍是模块页量出来的值。
        ledger.setHomeContentHeight(380)
        XCTAssertEqual(ledger.current, 250, "首页的写入不碰当前页（不给模块页的结论翻盘）")
        XCTAssertEqual(ledger.activeTab, "com.cmeng.gourd.todos", "当前页只由 `selectTab` 改")
        XCTAssertEqual(ledger.homeContentHeight, 380, "首页的槽照常更新（它自己的数）")

        // 回到首页：`selectTab` 声明 + 接缝在 body 里再写一次 → 当前值回到首页那一份。
        ledger.selectTab(PanelContentHeight.homeTab)
        XCTAssertEqual(ledger.current, 380, "首页当班 → 读算出来的那一份")

        // `home` 键的上报被忽略（首页有自己的槽，不许两条路写同一个值）。
        ledger.report(999, for: PanelContentHeight.homeTab)
        XCTAssertEqual(ledger.current, 380, "`home` 键的上报不进门")
        XCTAssertEqual(ledger.measuredHeight, 250, "`home` 键的上报没写脏量出来的那一槽")

        // 空串（还没选中模块 / 没选中扩展）= 不是一页，同样不进门。
        ledger.report(123, for: "")
        XCTAssertEqual(ledger.current, 380)
    }

    /// **切页**（T7 复核 P1 + p6-ui-polish / T7 机制五）：名单外的页必须**没有值**（回落手动值），
    /// 名单内**没量过**的页保留到新页量完，**量过**的页直接读每页缓存（一步到位），首页读算出来的
    /// 那一份。为什么前两条是硬要求：不清值就会继承上一页的高度——首页 → 待办 ~200 → 终端，
    /// 终端按 200 的画布铺一屏（高是面板高的函数），挤得不能用。
    func testSelectTabClearsValueForUnlistedPagesAndKeepsItForMeasuredOnes() {
        let ledger = PanelContentHeight.shared
        ledger.reset()
        defer { ledger.reset() }

        let todos = "com.cmeng.gourd.todos"
        let notifications = "com.cmeng.gourd.notifications"

        // 首页 → 待办：量出来 200。
        ledger.selectTab(PanelContentHeight.homeTab)
        ledger.setHomeContentHeight(400)
        ledger.selectTab(todos)
        ledger.report(200, for: todos)
        XCTAssertEqual(ledger.current, 200)

        // 名单内**没量过**的另一页：仍是旧路径——**保留**上一页的量值（新页量完那一拍无条件覆盖它，
        // §已知限制 2 的形态；切页就清会变成「先跳手动值再跳量值」两次跳动）。缓存（T7 机制五）
        // 只对**量过的**页做一步到位，没量过的页没有条目，这里因此逐字不变。
        //
        // **没量过的新页第一份上报无条件**（滞回与光标规则都不参与）：用户刚点完 tab，手还停在面板里，
        // 新页比旧值矮也要接受——否则「切到内容短的页」在光标压着的时候永远不生效。这一档**不因
        // 缓存而变**（T7 裁决 T7-fix 只改缓存命中那一档，见另一条用例）。
        ledger.selectTab(notifications)
        XCTAssertEqual(ledger.current, 200, "名单内没量过的页：先拿上一页的数，等新页量完覆盖")
        ledger.pointerInsidePanel = { true }
        ledger.report(150, for: notifications)
        XCTAssertEqual(ledger.current, 150, "没缓存的页：第一份上报无条件接受（变矮 + 光标在面板里都接受）")
        ledger.pointerInsidePanel = { false }

        // **量过的页切回来一步到位**（p6-ui-polish / T7 机制五）：缓存里就有待办上一次被接受的 200，
        // 不再先落在那份 150 上再跳一次（0 次跳动，T6 的「一次跳动」再收一档）。
        ledger.selectTab(todos)
        XCTAssertEqual(ledger.current, 200, "量过的页：直接读 `heightCache`（不是留着的 150）")

        // 缓存命中的页**第一份上报回普通条款**（T7 裁决 T7-fix）：差 < 8pt 不推窗口（消微跳）；
        // 变矮时光标在面板内按条款 ④ 拦下（移开鼠标才贴合——§已知限制 1 的既有形态）。
        ledger.pointerInsidePanel = { true }
        ledger.report(205, for: todos)
        XCTAssertEqual(ledger.current, 200, "缓存命中 + 首报差 5pt → 滞回拦下（不再多推一次窗口）")
        ledger.report(90, for: todos)
        XCTAssertEqual(ledger.current, 200, "缓存命中 + 变矮 + 光标在面板内 → 条款 ④ 拦下")
        ledger.pointerInsidePanel = { false }
        ledger.report(90, for: todos)
        XCTAssertEqual(ledger.current, 90, "光标离开 → 差 ≥ 8pt 的收缩照常接受")

        // 第二份起回正常条款（同页微动 / 变大）。
        ledger.report(60, for: todos)
        XCTAssertEqual(ledger.current, 60, "光标已移开 → 收缩 30pt 照常接受")
        ledger.report(95, for: todos)
        XCTAssertEqual(ledger.current, 95, "同页 +35pt → 接受")

        // 名单外的页（终端）：**清掉**当班值 → `current` = nil → 尺寸层回落手动值。
        ledger.selectTab("terminal")
        XCTAssertNil(ledger.current, "名单外的页没有值（不是继承上一页的 95）")
        XCTAssertNil(ledger.measuredHeight, "量出来的那一槽被清掉")
        XCTAssertEqual(ledger.activeTab, "terminal")

        // 再切回名单内的页：**缓存按页留着**（名单外那一趟只清当班值，不动别人的缓存）——
        // 量过的待办一步到位回到**最后一次被接受的** 95；若从没量过才是 nil（回落手动值），量完就位。
        ledger.selectTab(todos)
        XCTAssertEqual(ledger.current, 95, "缓存按页保留（切到名单外不清别人页的缓存）")
        ledger.report(180, for: todos)
        XCTAssertEqual(ledger.current, 180, "缓存命中 + ≥ 8pt 的变化照常接受")

        // 首页：读 `homeContentHeight`（不是量出来的那一份）。
        ledger.selectTab(PanelContentHeight.homeTab)
        XCTAssertEqual(ledger.current, 400, "首页当班 → 算出来的那一份")

        // 声明是幂等的（每帧都调）；空键（还没选中模块）不声明、也不清任何东西。
        ledger.selectTab(PanelContentHeight.homeTab)
        XCTAssertEqual(ledger.current, 400)
        ledger.selectTab("")
        XCTAssertEqual(ledger.activeTab, PanelContentHeight.homeTab, "空键不进门（不改当前页）")
        XCTAssertEqual(ledger.current, 400)
    }

    /// `selectTab` 只在 `current` **真的变了**时才响 `objectWillChange`（尺寸层据此走那条既有的
    /// 0.15s 防抖链）：同键再声明一次、以及「切到同值的页」都不该触发多余的重算。
    func testSelectTabNotifiesOnlyWhenTheEffectiveValueChanges() {
        let ledger = PanelContentHeight.shared
        ledger.reset()
        defer { ledger.reset() }

        let todos = "com.cmeng.gourd.todos"
        var notifications = 0
        let cancellable = ledger.objectWillChange.sink { _ in notifications += 1 }

        ledger.selectTab(todos)
        XCTAssertEqual(notifications, 0, "第一次声明（`current` 还是 nil）→ 不响")
        ledger.report(200, for: todos)
        XCTAssertEqual(notifications, 1, "值从 nil 变成 200 → 响一次")

        ledger.selectTab(todos)
        XCTAssertEqual(notifications, 1, "同键重复声明（每帧都调）→ 不响")
        ledger.selectTab("com.cmeng.gourd.notifications")
        XCTAssertEqual(notifications, 1, "名单内的页且量值没变化（还是 200）→ 不响")
        ledger.report(200, for: "com.cmeng.gourd.notifications")
        XCTAssertEqual(notifications, 1, "同一个数（换页的第一拍）→ 滞回之外也不响")

        ledger.selectTab("terminal")
        XCTAssertEqual(notifications, 2, "名单外的页把值清掉 → current 变 nil → 响一次")

        withExtendedLifetime(cancellable) {}
    }

    /// **切页读每页缓存**（p6-ui-polish / T7 机制五，docs/30 D-10 / D-11）：量过的页切回来**一步到位**
    /// ——直接落回它上一次被接受的那一份，既不先落在上一页的量值上、也不落手动值；名单外的页照旧
    /// 清值回落手动值，但**缓存按页留着**（切回来还在）。没量过的页没有条目，逐字走旧路径
    /// （留上一页的量值 + 首份上报无条件接受）。
    ///
    /// **缓存命中的页第一份上报回普通条款**（T7 裁决 T7-fix）：起点已是这一页自己的量值，差 < 8pt
    /// 的微跳不该再推第二次窗口——「单步」目标；无缓存那一档的无条件豁免逐字不变（另一条用例钉着）。
    ///
    /// 顺带钉住免防抖标记（`lastChangeWasTabSwitch`）——它就是「这一拍窗口要立刻跟」的账本侧信号：
    /// 切页换掉当班值、以及**没量过**的新页第一份上报为真；普通的内容变化（滞回之外的同页上报）
    /// 为假（那条仍走 0.15s 防抖的既有链）。
    func testTabSwitchUsesThePerTabHeightCache() {
        let ledger = PanelContentHeight.shared
        ledger.reset()
        defer { ledger.reset() }

        let todos = "com.cmeng.gourd.todos"
        let notifications = "com.cmeng.gourd.notifications"
        let terminal = "terminal"

        // 待办量出 200：**接受即写缓存**（四条款通过之后的每一个被接受的值都算）。
        ledger.selectTab(todos)
        ledger.report(200, for: todos)
        XCTAssertEqual(ledger.current, 200)
        XCTAssertEqual(ledger.heightCache[todos], 200, "被接受的上报立即进缓存")

        // 通知没量过：没有条目 → 逐字走旧路径（先留着上一页的 200），首份上报无条件 + 写缓存。
        XCTAssertNil(ledger.heightCache[notifications], "没量过的页没有条目（旧路径的判据）")
        ledger.selectTab(notifications)
        XCTAssertEqual(ledger.current, 200, "没缓存的页：先拿上一页的数，等首份上报覆盖")
        ledger.report(150, for: notifications)
        XCTAssertEqual(ledger.heightCache[notifications], 150)

        // **一步到位**：切回量过的待办，直接读缓存里的 200——不再先落在那份 150 上（0 次跳动）。
        ledger.selectTab(todos)
        XCTAssertEqual(ledger.current, 200, "量过的页切回来一步到位（缓存值，不是上一页的 150）")
        XCTAssertEqual(ledger.activeTab, todos)
        XCTAssertTrue(ledger.lastChangeWasTabSwitch, "切页换掉当班值 → 这一拍免防抖（订阅走立即链）")

        // **缓存命中的页第一份上报回普通条款**（T7 裁决 T7-fix）：起点已经是这一页**自己的**量值，
        // 与它比出来的差就是「同一页的微动」——差 < 8pt **不推窗口**（消掉切页后那一次微跳）。
        // 无缓存时的无条件豁免没变（在 `testSelectTabClearsValueForUnlistedPagesAndKeepsItForMeasuredOnes`
        // 里钉着：变矮 + 光标在面板内也接受）。
        ledger.report(205, for: todos)
        XCTAssertEqual(ledger.current, 200, "缓存命中 + 首报差 5pt（< 8pt 滞回）→ 不推窗口（单步）")
        XCTAssertFalse(ledger.lastChangeWasTabSwitch, "滞回拦下 → 没有通知，也就没有「立即推」那一拍")

        // 差 ≥ 8pt 仍按普通条款接受（滞回不是把页面钉死）——但它是**普通过报**，走 0.15s 防抖那条链。
        ledger.report(210, for: todos)
        XCTAssertEqual(ledger.current, 210, "缓存命中 + 首报差 10pt（≥ 8pt）→ 接受")
        XCTAssertFalse(ledger.lastChangeWasTabSwitch, "普通过报不置免防抖标记（不抢立即链）")
        XCTAssertEqual(ledger.heightCache[todos], 210, "被接受的值照常刷新缓存")

        // 名单外的终端：清当班值 → `current` = nil（回落手动值），但**不动别人页的缓存**。
        ledger.selectTab(terminal)
        XCTAssertNil(ledger.current, "名单外的页没有值（回落手动值）")
        XCTAssertEqual(ledger.heightCache[todos], 210, "名单外那一趟不清别人页的缓存")
        ledger.selectTab(todos)
        XCTAssertEqual(ledger.current, 210, "切回来还是缓存里那一份（名单外只是「当班没有值」）")

        // 切页首报**与缓存同值**：一次都不响（值没变就没有要推的窗口那一拍），标记随之是假。
        ledger.report(210, for: todos)
        XCTAssertEqual(ledger.current, 210, "首报与缓存同值 → 值不动")
        XCTAssertFalse(ledger.lastChangeWasTabSwitch, "没有通知就没有「切页那一拍」这回事")

        // 普通内容变化（同页、滞回之外）**不是**切页那一拍：仍走 0.15s 防抖那条既有链。
        ledger.report(300, for: todos)
        XCTAssertEqual(ledger.current, 300, "同页 +90pt → 接受")
        XCTAssertFalse(ledger.lastChangeWasTabSwitch, "普通过报不置免防抖标记（走防抖链，不抢立即链）")
        ledger.report(303, for: todos)
        XCTAssertEqual(ledger.current, 300, "同页 3pt 微动仍被滞回吃掉（缓存不改四条款）")

        // 切页读缓存时**值相同就不响**（`selectTab` 只在 `current` 真的变时发通知，口径不变）。
        var notificationCount = 0
        let cancellable = ledger.objectWillChange.sink { _ in notificationCount += 1 }
        ledger.selectTab(notifications)
        XCTAssertEqual(notificationCount, 1, "通知页的缓存 150 ≠ 300 → 响一次")
        XCTAssertEqual(ledger.current, 150, "另一个量过的页同样一步到位")
        ledger.selectTab(todos)
        XCTAssertEqual(notificationCount, 2, "回待办：缓存 300 → 响一次")
        ledger.selectTab(todos)
        XCTAssertEqual(notificationCount, 2, "同键重复声明（每帧都调）→ 不响")
        withExtendedLifetime(cancellable) {}
    }

    /// **谁上报**的名单（派发片段裁决 6 + p6-ui-polish / T6、T8）：内容随条数 / 格子数 / 月周数变
    /// 的那几页——四个模块页 + **架子**（宿主页，T6 进名单）+ **日历**（模块页，T8 进名单）；
    /// 另外两页刻意不在里面，逐条理由在 `PanelContentHeight.measuredTabs`（量它们 = 把面板高喂回自己）。
    func testMeasuredTabListIsTheCountDrivenPages() {
        XCTAssertEqual(
            PanelContentHeight.measuredTabs,
            [
                "com.cmeng.gourd.todos",
                "com.cmeng.gourd.notifications",
                "com.cmeng.gourd.launcher",
                "com.cmeng.gourd.shortcuts",
                // p6-ui-polish / T6：投放格 + 文件格网格 —— 高是格子数的函数。
                PanelContentHeight.shelfTab,
                // p6-ui-polish / T8：左栏固定格高月网格（36N + 52）+ 右栏在其高内滚动 —— 高是当月周数
                // 的函数（旧版面「自己的高是面板高的函数」已不成立，见名单里的注释）。
                CalendarModule.moduleID,
            ],
            "名单 = 内容随条数 / 格子数 / 月周数变的那几页（多一个 / 少一个都要连理由一起改）"
        )
        XCTAssertEqual(PanelContentHeight.hysteresis, 8, "滞回阈值 = 8pt（docs/29 §做法 机制六）")

        XCTAssertFalse(PanelContentHeight.isMeasuredTab(nil), "还没选中模块 → 不上报")
        XCTAssertFalse(PanelContentHeight.isMeasuredTab(""), "空键 → 不上报")
        XCTAssertFalse(
            PanelContentHeight.isMeasuredTab(PanelContentHeight.homeTab),
            "首页有算出来的那一份，不走测量"
        )
        // 未覆盖的两页：计时器（`.frame` 吃面板高 + 250 的 per-tab 下限）、终端（整块填满，没有自然高）。
        XCTAssertFalse(PanelContentHeight.isMeasuredTab("com.cmeng.gourd.timer"))
        XCTAssertFalse(PanelContentHeight.isMeasuredTab("terminal"))
    }

    /// **日历进测量名单**（p6-ui-polish / T8，docs/30 §做法 §机制六 / §接口与数据形状）。
    ///
    /// 旧版面（`GeometryReader + paneHeight` 两栏填满面板高）的自然高是**面板高**的函数——量它等于
    /// 把面板高喂回自己；T8 改成自然布局后它变成**当月周数**的函数（左栏 `36N + 52`、右栏在其高内
    /// 滚动），因此与模块页同一口径上报。判据分三层：① 键 = 模块 id 常量（宿主 `selectedPanelTabKey`
    /// 对 `.module` 传的就是它，不写第二份字面量）；② 名单含它（探针据此进门）；③ 账本行为——切到
    /// 日历页不再回落手动值（682 那种空半屏），量到的就是它。
    func testCalendarIsAMeasuredTab() {
        // ① 键：模块 id 的唯一字面量（manifest 与用例共用）。
        XCTAssertEqual(
            CalendarModule.moduleID, "com.cmeng.gourd.calendar",
            "日历页的 tab 键 = 模块 id（`ContentView.selectedPanelTabKey` 的 `.module` 分支传它）"
        )

        // ② 名单：探针的进门判据（名单外的页静默不上报）。
        XCTAssertTrue(
            PanelContentHeight.measuredTabs.contains(CalendarModule.moduleID),
            "日历页在测量名单里（T8 前不在：旧版面「自己的高是面板高的函数」）"
        )
        XCTAssertTrue(
            PanelContentHeight.isMeasuredTab(CalendarModule.moduleID),
            "`isMeasuredTab` 对日历键为真——探针据此上报"
        )

        // ③ 账本行为：切到日历页 + 上报 → `current` 就是量出来的那一份（不是手动回落值）。
        let ledger = PanelContentHeight.shared
        ledger.reset()
        defer { ledger.reset() }

        ledger.selectTab(CalendarModule.moduleID)
        XCTAssertEqual(ledger.activeTab, CalendarModule.moduleID)
        XCTAssertNil(ledger.current, "还没量到 → 回落手动值（首帧那一拍）")

        // 2026-10 的自然高 = 232（`MonthGridLayout.monthGridHeight`）→ 账本口径 = 232 + 表头 28 − 16。
        let natural = MonthGridLayout.monthGridHeight(
            forMonth: makeFixedMonth(2026, 10), calendar: fixedGridCalendar(firstWeekday: 1)
        )
        XCTAssertEqual(natural, 232, "前提：2026-10 = 5 周 → 36 × 5 + 52")

        ledger.report(natural + 28 - 16, for: CalendarModule.moduleID)
        XCTAssertEqual(ledger.current, 244, "日历页的量值进门（名单外的页写不进这个槽）")
        XCTAssertEqual(
            PanelAutoHeight.panelHeight(
                contentHeight: 244, mode: PanelAutoHeight.modeAuto,
                manualHeight: 682, screenVisibleHeight: nil
            ),
            284,
            "auto 档：面板高 = 量值 + 宿主内边距（不是盘上残留的 682 手动值——「不再 682 空半屏」）"
        )
    }

    /// 固定日历（格里高利 + GMT + `en_US_POSIX` + `firstWeekday`，与 `MonthGridLayoutTests` 同式）。
    private func fixedGridCalendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    /// 固定月份的首日零点。
    private func makeFixedMonth(_ year: Int, _ month: Int) -> Date {
        fixedGridCalendar(firstWeekday: 1).date(from: DateComponents(year: year, month: month, day: 1))!
    }

    /// **架子进测量名单**（p6-ui-polish / T6，docs/30 §做法 机制三 / D-08）。
    ///
    /// 新版面（投放格 + 多行网格、纵向滚动）下这一页的高是**格子数**的函数：
    /// 纵向 `ScrollView` 的理想高 = 网格自然高，与面板当前多高无关——因此与模块页同一口径上报。
    /// 判据分三层：① 键与宿主声明同字面量；② 名单含它（探针据此进门）；③ 账本行为——切到架子页
    /// 不再回落手动值（682 那种空半屏），量到的就是它。
    func testShelfIsAMeasuredTab() {
        // ① 键：`ContentView.selectedPanelTabKey` 对 `.shelf` 传的就是 `PanelContentHeight.shelfTab`
        //    （探针在 `NotchShelfView` 里用同一个常量挂上，两边不各写一份字符串）。
        XCTAssertEqual(
            PanelContentHeight.shelfTab, "shelf",
            "架子页的键 = 宿主 `selectedPanelTabKey` 对 `.shelf` 传的那个字面量"
        )

        // ② 名单：探针的进门判据（名单外的页静默不上报）。
        XCTAssertTrue(
            PanelContentHeight.measuredTabs.contains(PanelContentHeight.shelfTab),
            "架子页在测量名单里（T6 前不在：旧版面「拖放区整块填满」没有自然高）"
        )
        XCTAssertTrue(
            PanelContentHeight.isMeasuredTab(PanelContentHeight.shelfTab),
            "`isMeasuredTab` 对架子键为真——探针据此上报"
        )

        // ③ 账本行为：切到架子页 + 上报 → `current` 就是量出来的那一份。
        let ledger = PanelContentHeight.shared
        ledger.reset()
        defer { ledger.reset() }

        ledger.selectTab(PanelContentHeight.shelfTab)
        XCTAssertEqual(ledger.activeTab, PanelContentHeight.shelfTab)
        XCTAssertNil(ledger.current, "还没量到 → 回落手动值（首帧那一拍）")

        ledger.report(200, for: PanelContentHeight.shelfTab)
        XCTAssertEqual(ledger.current, 200, "架子页的量值进门（名单外的页写不进这个槽）")
        XCTAssertEqual(
            PanelAutoHeight.panelHeight(
                contentHeight: 200, mode: PanelAutoHeight.modeAuto,
                manualHeight: 682, screenVisibleHeight: nil
            ),
            240,
            "auto 档：面板高 = 量值 + 宿主内边距（不是盘上残留的 682 手动值）"
        )
    }

    /// **网格布局常量**（p6-ui-polish / T6，docs/30 §做法 机制三「列宽 115、项距 8、行距 8」）。
    ///
    /// 格子尺寸不在这一层重钉（`ShelfCellMetrics.size` 由 `ShelfInteractionTests` 钉住），
    /// 这里只钉「网格怎么把它们摆开」：列宽 = 格子宽、项距 / 行距、按宽度分列（自动换行），
    /// 以及投放格 = 首格那条不变量（marquee 的 pass-through 矩形直接吃它）。
    func testShelfGridMetricsMatchTheDesignConstants() {
        XCTAssertEqual(
            ShelfGridMetrics.columnWidth, ShelfCellMetrics.size.width,
            "列宽 = 文件格宽（115，T5 钉的尺寸——不是字面量，跟它同源）"
        )
        XCTAssertEqual(
            ShelfGridMetrics.itemHeight, ShelfCellMetrics.size.height,
            "行高 = 文件格高（108）"
        )
        XCTAssertEqual(ShelfGridMetrics.itemSpacing, 8, "项距 8")
        XCTAssertEqual(ShelfGridMetrics.rowSpacing, 8, "行距 8")

        // 投放格 = 网格首格 = 内容的左上角那一格（marquee 让位用的矩形）。
        XCTAssertEqual(
            ShelfGridMetrics.shareTileFrame,
            CGRect(x: 0, y: 0, width: ShelfCellMetrics.size.width, height: ShelfCellMetrics.size.height),
            "投放格的位置 = 内容原点 + 一格大小（布局不变量：网格贴内容左上角、首格贴网格原点）"
        )

        // 自动换行：列数按可用宽算（至少 1 列；量不到宽 / 非有限 → 1 列）。
        // 这是**对 `.adaptive` 布局的预测**（视图用自适应列，不拿这个值分列）——
        // 与下面 `testShelfGridWrapsWithTheDeclaredColumnWidthAndSpacing` 的实测同值。
        XCTAssertEqual(ShelfGridMetrics.columnCount(forWidth: 0), 1, "还没量到宽 → 1 列")
        XCTAssertEqual(ShelfGridMetrics.columnCount(forWidth: .nan), 1, "非有限 → 1 列")
        XCTAssertEqual(ShelfGridMetrics.columnCount(forWidth: 114), 1, "塞不下一格")
        XCTAssertEqual(ShelfGridMetrics.columnCount(forWidth: 115), 1, "正好一格")
        XCTAssertEqual(ShelfGridMetrics.columnCount(forWidth: 237), 1, "还差 1pt 才放得下两列")
        XCTAssertEqual(ShelfGridMetrics.columnCount(forWidth: 238), 2, "2×115 + 8 = 238 起两列")
        XCTAssertEqual(ShelfGridMetrics.columnCount(forWidth: 887), 7, "887 宽面板：7 列（7×115 + 6×8 = 853 ≤ 887）")
        XCTAssertEqual(ShelfGridMetrics.columns.count, 1, "一条自适应列定义（列数由布局按可用宽定）")
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

    /// 把任一页挂进 `NSHostingView` 跑一趟真布局（探针只在布局里发生）。
    @discardableResult
    private func mountPanelPage<Content: View>(
        _ content: Content, width: CGFloat, height: CGFloat
    ) -> NSHostingView<some View> {
        let host = NSHostingView(rootView: content.frame(width: width, height: height))
        host.frame = CGRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        return host
    }

    /// 宽度自适应的页（启动台那一类的形状）：`GridItem(.adaptive(minimum: 100))` —— 列数随宽度变，
    /// **行数**（因此自然高）也就随宽度变。
    private struct AdaptiveGridPageFixture: View {
        let itemCount: Int

        var body: some View {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                    ForEach(0..<itemCount, id: \.self) { _ in
                        Color.clear.frame(height: 40)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// **探针按面板的实际宽量**（T7 复核 P2）：宽度自适应的页在**没有宽提案**时会按最窄那一档算
    /// （单列）——启动台那样几百个 App 的页因此量出「几百行」的自然高，把面板顶到 850 上界；
    /// 而它本来只该要「6 列 × 若干行」那么高。
    ///
    /// 判据用**同一页在两个宽度上的差**（不钉具体行高）：700 宽 → 6 列 → 2 行；300 宽 → 2 列 →
    /// 4 行；两个值必须**不同**。若探针传的是「宽度也 unspecified」，两次量到的会是同一个数
    /// （同为单列的 8 行）→ 差为 0 → 这条用例红。
    func testProbeMeasuresAtThePanelsContentWidthNotAnUnspecifiedWidth() {
        let ledger = PanelContentHeight.shared
        ledger.reset()
        defer { ledger.reset() }

        let tab = "com.cmeng.gourd.launcher"
        let header: CGFloat = 24

        let wide = mountPanelPage(
            AdaptiveGridPageFixture(itemCount: 8)
                .panelContentHeightReport(tab: tab, headerHeight: header, isCurrent: { true }),
            width: 700, height: 600
        )
        let wideValue = ledger.current

        let narrow = mountPanelPage(
            AdaptiveGridPageFixture(itemCount: 8)
                .panelContentHeightReport(tab: tab, headerHeight: header, isCurrent: { true }),
            width: 300, height: 600
        )
        let narrowValue = ledger.current

        guard let wideValue, let narrowValue else {
            return XCTFail("探针没有上报（`current` 为 nil）")
        }

        // 700 宽：6 列 → 2 行（40 + 8 + 40 = 88）；300 宽：2 列 → 4 行（4×40 + 3×8 = 184）。
        // 两个值都要再加这一页自己的内边距 10 + 10 与账本口径的「+ 表头 24 − 16」。
        XCTAssertEqual(wideValue, 88 + 20 + 8, accuracy: 2, "6 列 2 行 + 页面内边距 + 表头 − 16")
        XCTAssertEqual(narrowValue, 184 + 20 + 8, accuracy: 2, "2 列 4 行 + 页面内边距 + 表头 − 16")
        XCTAssertGreaterThan(
            narrowValue - wideValue, 50,
            "同一页在窄布面上自然高更高（列数变少、行数变多）——宽度没有被当成 unspecified"
        )
        // 反证：若按单列量（8 行 = 8×40 + 7×8 = 376 → 账本值 376 + 20 + 8 = 404），两个宽度会给出
        // 同一个数。实测 116 / 212（差 96 = 少 2 行 + 少 2 个行距）：量的是**真实布面**上的高。
        XCTAssertLessThan(wideValue, 200, "不是单列那 404（按真实布面 6 列量）")
        withExtendedLifetime(wide) {}
        withExtendedLifetime(narrow) {}
    }

    /// **启动台就绪门**（p6-ui-polish / T7 机制五，docs/30 D-11）：`apps` 首轮扫描完成前探针**一次都不报**
    /// ——那几帧页面上是 loading / 空态占位，量它进账本就是首开「先塌陷再长高」的三拍。
    ///
    /// 判据分两半，这里都钉住：① **模块侧** `LauncherStore.hasLoadedApps`（`load()` 前后一假一真；
    /// 与「只扫一次」的 `hasLoaded` 不是一回事——那个在扫描**开始前**就置位）；② **探针侧**
    /// `PanelContentHeight.isTabReportReady`（宿主按 tab 接的就是 ①：为假时同一页挂了探针也不上报，
    /// 为真才进账本，且**不是永久封锁**）。
    func testLauncherDoesNotReportBeforeAppsLoad() async {
        let ledger = PanelContentHeight.shared
        ledger.reset()
        defer { ledger.reset() }

        let launcherTab = LauncherModule.manifest.id
        XCTAssertEqual(launcherTab, "com.cmeng.gourd.launcher", "探针的键 = 模块 id（测量名单里那一条）")
        XCTAssertTrue(PanelContentHeight.isMeasuredTab(launcherTab), "前提：启动台在测量名单里")

        // ① 模块侧的就绪判据。`roots` 给空目录（扫描立即返回空表），`showRecents = false` +
        //    `fetchUsage` 注入空样本 → 整条 `load()` 不碰 Spotlight、也不扫开发机真实的 /Applications。
        let store = LauncherStore(
            logger: ModuleLogger(moduleID: launcherTab, shortID: "launcher"),
            roots: [],
            pins: LauncherPins(read: { [] }, write: { _ in }),
            settings: { LauncherSettings(iconSize: 44, density: 1, showRecents: false) },
            fetchUsage: { _ in [:] }
        )
        XCTAssertFalse(store.hasLoadedApps, "还没 load：就绪门是关的")

        // ② 宿主那条接缝的判据（`DynamicIslandApp` 里按同一个 tab 转发同一个属性）。
        ledger.isTabReportReady = { tab in
            guard tab == launcherTab else { return true }
            return store.hasLoadedApps
        }

        // 加载前：同一页挂上探针**一次都不报**（`current` 保持 nil → 尺寸层回落手动值，
        // 而不是先把空态占位高写进账本、等 App 扫完再改一次）。
        let beforeLoad = mountPanelPage(
            Color.clear.frame(height: 60)
                .panelContentHeightReport(tab: launcherTab, headerHeight: 24, isCurrent: { true }),
            width: 700, height: 600
        )
        XCTAssertNil(ledger.current, "首轮扫描完成前不上报（loading / 空态占位高不进账本）")
        XCTAssertNil(ledger.activeTab, "一次都没进门，`activeTab` 也不该被写")

        // 首轮扫描完成：`roots` 空 → 空表，但**算已就绪**（空目录的高就是这一页的高，不开特例）。
        await store.load()
        XCTAssertTrue(store.hasLoadedApps, "`load()` 之后就绪（本标记只在 `apps` 落地后置位）")
        XCTAssertEqual(store.apps, [], "空根目录 → 空表（本用例只关心就绪门，不造真 `.app`）")

        // 加载后：同一页再量一趟就进门了——就绪门是**闸门**，不是把这一页永久挡住。
        let afterLoad = mountPanelPage(
            Color.clear.frame(height: 60)
                .panelContentHeightReport(tab: launcherTab, headerHeight: 24, isCurrent: { true }),
            width: 700, height: 600
        )
        guard let measured = ledger.current else {
            return XCTFail("就绪后仍未上报——就绪门把这一页永久挡住了（量值再也进不来）")
        }
        XCTAssertEqual(
            measured,
            PanelAutoHeight.measuredContentHeight(naturalHeight: 60, headerHeight: 24),
            accuracy: 1,
            "就绪后的量值照常进门（夹具 60 高 = 模拟网格 / 真实空态）"
        )
        XCTAssertEqual(ledger.activeTab, launcherTab)

        withExtendedLifetime(beforeLoad) {}
        withExtendedLifetime(afterLoad) {}
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

    /// 架子新版面的形状（p6-ui-polish / T6）：纵向 `ScrollView` + `LazyVGrid`（首格投放格 +
    /// `fileCount` 个文件格）。格子尺寸与列定义都吃 `ShelfGridMetrics`（与生产同源），
    /// 但**不挂** `ShelfView` 本身——那一支带 `QuickShareService` / `LocalSendService`
    /// 的副作用（发现与组播），不适合进单测。
    ///
    /// `recorder` 收每个格子在网格坐标空间里的位置（排序前的原始表）——用来钉
    /// 「列宽 115、项距 8、行距 8、自动换行」在实际布局里的样子（断言侧排序后再比）。
    private struct ShelfGridPageFixture: View {
        let fileCount: Int
        let width: CGFloat
        var recorder: LaidOutRectsBox?

        var body: some View {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: ShelfGridMetrics.rowSpacing) {
                    LazyVGrid(
                        columns: ShelfGridMetrics.columns,
                        alignment: .leading,
                        spacing: ShelfGridMetrics.rowSpacing
                    ) {
                        // 首格 = 投放格。
                        cell
                        ForEach(0..<fileCount, id: \.self) { _ in
                            cell
                        }
                    }
                    .coordinateSpace(name: Self.gridSpace)
                }
                .frame(minWidth: width, alignment: .topLeading)
            }
            .scrollIndicators(.never)
        }

        private static let gridSpace = "shelfGridFixture"

        private var cell: some View {
            Color.clear
                .frame(width: ShelfGridMetrics.columnWidth, height: ShelfGridMetrics.itemHeight)
                .background(
                    GeometryReader { proxy in
                        let _ = recorder?.record(proxy.frame(in: .named(Self.gridSpace)))
                        Color.clear
                    }
                )
        }
    }

    /// 收一组矩形的小盒子（引用类型：布局期的回调闭包只能捕获它）。
    private final class LaidOutRectsBox {
        private(set) var rects: [CGRect] = []
        func record(_ rect: CGRect) { rects.append(rect) }
    }

    /// **网格的常量在真布局里的样子**（p6-ui-polish / T6，docs/30 §做法 机制三）：
    /// 887 宽（实机面板宽）下 7 列、列宽 115、项距 8、左对齐，第 8 格换行到 y = 116（108 + 行距 8）。
    /// 与 `columnCount(forWidth:)` 的预测同值——`.adaptive` 的实测行为就是那条算式。
    func testShelfGridWrapsWithTheDeclaredColumnWidthAndSpacing() {
        let box = LaidOutRectsBox()
        let host = NSHostingView(
            rootView: ShelfGridPageFixture(fileCount: 7, width: 887, recorder: box)
        )
        host.frame = CGRect(x: 0, y: 0, width: 887, height: 600)
        host.layoutSubtreeIfNeeded()

        let rects = box.rects.sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) }
        guard rects.count == 8 else { return XCTFail("只记到 \(rects.count) 格（期望 8）") }

        XCTAssertEqual(ShelfGridMetrics.columnCount(forWidth: 887), 7, "预测：7 列")
        XCTAssertEqual(
            rects.map(\.minX), [0, 123, 246, 369, 492, 615, 738, 0],
            "列宽 115 + 项距 8 = 步长 123，左对齐；第 8 格回到行首"
        )
        XCTAssertEqual(
            rects.map(\.minY), [0, 0, 0, 0, 0, 0, 0, 116],
            "首行 7 格；换行 = 一格高 108 + 行距 8 = 116"
        )
        XCTAssertEqual(rects[0].size, CGSize(width: 115, height: 108), "格子尺寸不变（T5 的 cell 尺寸）")
        withExtendedLifetime(host) {}
    }

    /// **架子页的理想高能被量到、且是格子数的函数**（p6-ui-polish / T6，docs/30 §做法 机制三）。
    ///
    /// 同一页在同一个 600 高的容器里，文件数一多（行数变多）上报值就必须跟着长——量「摆放后的高」
    /// 的话两次都是容器给的那个数。这是在单测里对「架子进测量名单」的行为覆盖：探针走的是与
    /// `NotchShelfView` 同一支 `panelContentHeightReport`、同一个键（`PanelContentHeight.shelfTab`）。
    /// 单文件时量到的是「一格网格」的高（不占半屏），不是面板高、也不是手动回落值。
    func testShelfPageIdealHeightFollowsTheItemCountNotThePanelHeight() {
        let ledger = PanelContentHeight.shared
        ledger.reset()
        defer { ledger.reset() }

        let header: CGFloat = 24
        // 700 宽容器 → 5 列（(700 + 8) / 123 = 5.75）；格子 115×108 → 行高 108、行距 8。
        XCTAssertEqual(ShelfGridMetrics.columnCount(forWidth: 700), 5, "夹具的列数前提")

        // 1 个文件 + 投放格 = 2 格 = 1 行。
        let oneFile = mountPanelPage(
            ShelfGridPageFixture(fileCount: 1, width: 700)
                .panelContentHeightReport(
                    tab: PanelContentHeight.shelfTab, headerHeight: header, isCurrent: { true }
                ),
            width: 700, height: 600
        )
        let emptyish = ledger.current

        // 5 个文件 + 投放格 = 6 格 = 2 行。
        let fiveFiles = mountPanelPage(
            ShelfGridPageFixture(fileCount: 5, width: 700)
                .panelContentHeightReport(
                    tab: PanelContentHeight.shelfTab, headerHeight: header, isCurrent: { true }
                ),
            width: 700, height: 600
        )
        let twoRows = ledger.current

        guard let emptyish, let twoRows else {
            return XCTFail("架子页的探针没有上报（`current` 为 nil）——键或名单没对上")
        }

        // 1 行：自然高 108 → 账本值 = 108 + 表头 24 − 16（`measuredContentHeight` 的换算）。
        XCTAssertEqual(emptyish, 108 + header - 16, accuracy: 1, "单文件：一格网格的高（不占半屏）")
        // 2 行：自然高 108×2 + 8 = 224。
        XCTAssertEqual(twoRows, 224 + header - 16, accuracy: 1, "两行网格的高")
        XCTAssertEqual(twoRows - emptyish, 116, accuracy: 1, "多一行就多一格高 + 一道行距（1:1）")

        // 量的是理想高，不是容器给的 600（放「摆放后的高」= 量容器 = 反馈环）。
        XCTAssertLessThan(twoRows, 300, "量的是网格自然高，不是容器的 600")
        withExtendedLifetime(oneFile) {}
        withExtendedLifetime(fiveFiles) {}
    }

    /// **面板壳量的是内容，不是虚线环**（p6-ui-polish / T6 实现期实测踩到的那条）。
    ///
    /// 架子页的壳（`ShelfPanel`）T6 前是「环当根 + 内容放 overlay」——`Shape` 在没有高提案时
    /// 答 10pt，而 `.overlay` 不参与布局，于是**整页的理想高**成了 10：探针把 18 报进账本，
    /// 面板被压到下界（内容反而被裁）。现在内容当根，量到的就是「网格 + 内边距」。
    /// 这条挂在**真组合**上（`ShelfPanel` + 真夹具），挂了环、背景点击层与填满提案的那一层
    /// ——任何一层把理想高吃掉都会在这里报红。
    func testShelfPanelMeasuresTheContentNotTheRing() {
        let ledger = PanelContentHeight.shared
        ledger.reset()
        defer { ledger.reset() }

        let host = mountPanelPage(
            ShelfPanel(isDropTargeted: false, animation: nil, onBackgroundClick: {}) {
                ShelfGridPageFixture(fileCount: 1, width: 700)
            }
            .panelContentHeightReport(
                tab: PanelContentHeight.shelfTab, headerHeight: 24, isCurrent: { true }
            ),
            width: 700, height: 600
        )

        // 1 行网格 108 + 面板内边距 32 = 自然高 140 → 账本值 = 140 + 表头 24 − 16 = 148。
        guard let measured = ledger.current else {
            return XCTFail("架子页的探针没有上报（`current` 为 nil）")
        }
        XCTAssertEqual(
            measured, 148, accuracy: 1,
            "量的是「网格 + 内边距」（环的 10pt 回落 / 容器的 600 都不许混进来）"
        )
        withExtendedLifetime(host) {}
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

    /// **不在名单里的页**一个值都不写（覆盖范围的负向护栏）：拿终端的键挂同一个夹具，账本必须
    /// 保持空——名单外的页要回落「今天的行为」（手动值），悄悄写一个值就是另一套高度来源。
    func testUnlistedPageWritesNothingEvenWhenProbed() {
        let ledger = PanelContentHeight.shared
        ledger.reset()
        defer { ledger.reset() }

        let host = mountFillStylePage(
            rowCount: 3, tab: "terminal", headerHeight: 24, isCurrent: { true }
        )
        XCTAssertNil(ledger.current, "名单外的页（终端）不上报")
        XCTAssertNil(ledger.activeTab)
        withExtendedLifetime(host) {}
    }

    // MARK: - 首页两支的账本键（侧歌词档不吃首页的槽；终审 T-final / D-57）

    /// **侧歌词档的账本键不是首页键**（p5-home-blocks 终审 F1）：`NotchHomeView` 的第二支
    /// （歌词 + 音乐 + 镜子）**没有自己的内容高**——写首页那一份的接缝（`HomeBandedHomeView`）
    /// 不在屏幕上。它若落在首页键上，`current` 就会拿到「上一次标准首页算出来的值」，auto 档下
    /// 面板高度 = 那个值 + 40（与侧歌词无关，且把手隐藏、滑块禁用，用户没得改）；给它一个
    /// **没人上报**的键 → `current` = nil → 尺寸层回落**手动值**（D-45 对名单外页同一条口径）。
    /// 标准路径逐字不变（仍读首页那一份）。
    func testSideLyricsHomeLayoutDoesNotResolveToTheHomeLedgerKey() {
        // ① 判据（`matters.swift` 的纯函数，与 `NotchHomeView` / `ContentView` 两处共用）：
        //    只有「歌词开 + 日历关 + 非极简 + 音乐该显示」这组全真时才是侧歌词档。
        XCTAssertTrue(
            showsSideLyricsHomeLayout(
                enableLyrics: true,
                showCalendar: false,
                enableMinimalisticUI: false,
                showStandardMediaControls: true,
                autoHideInactiveNotchMediaPlayer: true,
                musicHasActiveSession: true
            ),
            "歌词开 + 日历关 + 非极简 + 有音乐会话 = 侧歌词档（`NotchHomeView` 的第二支）"
        )
        XCTAssertFalse(
            showsSideLyricsHomeLayout(
                enableLyrics: false,
                showCalendar: false,
                enableMinimalisticUI: false,
                showStandardMediaControls: true,
                autoHideInactiveNotchMediaPlayer: true,
                musicHasActiveSession: true
            ),
            "歌词关 → 标准路径（逐字不变的那一支）"
        )
        XCTAssertFalse(
            showsSideLyricsHomeLayout(
                enableLyrics: true,
                showCalendar: true,
                enableMinimalisticUI: false,
                showStandardMediaControls: true,
                autoHideInactiveNotchMediaPlayer: true,
                musicHasActiveSession: true
            ),
            "日历行开着 → 标准路径（`shouldShowSideLyrics` 的 `!showCalendar` 一条）"
        )
        XCTAssertFalse(
            showsSideLyricsHomeLayout(
                enableLyrics: true,
                showCalendar: false,
                enableMinimalisticUI: true,
                showStandardMediaControls: true,
                autoHideInactiveNotchMediaPlayer: true,
                musicHasActiveSession: true
            ),
            "极简档是另一支（尺寸走 `minimalisticOpenNotchSize`、不读账本）——它的键保持首页键"
        )
        XCTAssertFalse(
            showsSideLyricsHomeLayout(
                enableLyrics: true,
                showCalendar: false,
                enableMinimalisticUI: false,
                showStandardMediaControls: true,
                autoHideInactiveNotchMediaPlayer: true,
                musicHasActiveSession: false
            ),
            "「自动隐藏无会话的音乐」且没有会话 → 不画音乐条，也不是侧歌词档"
        )

        // ② 键的映射（`ContentView.swift` 的文件级函数）：侧歌词档 → 专用键——不是首页键、
        //    也不在测量名单里（没人上报它）；标准路径仍是首页键。
        let sideLyricsKey = homePanelTabKey(showsSideLyricsLayout: true)
        XCTAssertNotEqual(sideLyricsKey, PanelContentHeight.homeTab, "侧歌词档不许落到首页键上")
        XCTAssertFalse(PanelContentHeight.isMeasuredTab(sideLyricsKey), "专用键不在测量名单里（没人上报它）")
        XCTAssertEqual(
            homePanelTabKey(showsSideLyricsLayout: false),
            PanelContentHeight.homeTab,
            "标准路径逐字不变（接缝写的就是这个槽）"
        )

        // ③ 账本行为：哪怕首页槽里还留着上一次标准首页算出来的值，侧歌词档当班时 `current` 也是
        //    nil（尺寸层据此回落手动值），不是那个存量的 400。
        let ledger = PanelContentHeight.shared
        ledger.reset()
        defer { ledger.reset() }

        ledger.setHomeContentHeight(400)
        ledger.selectTab(sideLyricsKey)
        XCTAssertEqual(ledger.activeTab, sideLyricsKey)
        XCTAssertNil(ledger.current, "侧歌词档没有值 → 回落手动值（不是继承首页槽里的 400）")
        XCTAssertEqual(ledger.homeContentHeight, 400, "首页那一份原样保留（切回标准路径还要用）")

        // 切回标准路径：首页槽照常当班（逐字不变的那一条）。
        ledger.selectTab(homePanelTabKey(showsSideLyricsLayout: false))
        XCTAssertEqual(ledger.current, 400, "标准路径仍读首页那一份")
    }

    // MARK: - hover 退出 × 面板自己动（p6-ui-polish 回归修复：「切日历页不再塌回关闭态」）

    /// **判据层用例**：`shouldHonorHoverExit`（`ContentView.swift` 文件级纯函数，与
    /// `shouldSuppressHoverOpen` / `shouldHideClosedContentUntilHover` 同一族）。
    ///
    /// 回归的实机形态（控制器 3/3 复现）：auto 高度下切页会**在指针底下**把面板缩短
    ///（日历页 ≈310、通知页 ≈850、首页 ≈604）——SwiftUI 的 `.onHover(false)`（布局一变就补发）
    /// 与隐藏态轮询的「指针还在窗口里吗」都会把「面板缩走了」读成「指针离开了面板」，
    /// 照常收起就是「切到日历页 → 面板塌回关闭态」（窗口停在内容高、画面只剩折叠条）。
    /// 修复：展开态的「面板位置」取**面板与指针最后一次接触**时观测到的那块窗口 rect
    ///（`lastPanelContactRect`），指针还在那块位置里时这次退出是**面板自己动的**，不收。
    ///
    /// **为什么只钉到判据层**：整条链是「真实指针位置 + SwiftUI `.onHover` 的补发 + 隐藏态轮询
    ///（100ms 采样 `NSEvent.mouseLocation`）」的活窗口交互，单测里没有可驱动的指针与 AppKit 窗口。
    /// 上屏判据（控制器复验）：指针停在面板下半部 → 切「日历」→ 面板留在打开态（窗口 ≈310、
    /// AX 元素数不掉）；再把指针移开 → 面板照常收起。本机已用注入鼠标 + AX 驱动在 Debug 构建上
    /// 逐条跑过这两条判据（修复前：切页即收起；修复后：留在打开态，移开后收起）。
    func testHoverExitIsNotHonoredWhenThePanelItselfMovesAwayFromThePointer() {
        // NSEvent 屏幕坐标（左下原点）：接触位置 = 指针还停在通知页（高面板）里时那块窗口 rect。
        let tallPanelContactRect = CGRect(x: 313, y: 100, width: 887, height: 872)
        let pointerInsideTallPanel = NSPoint(x: 756, y: 200)

        // ① 面板自己动的（切页取高）那一档：指针读数没动、面板从 872 缩到 310，
        //    指针仍在**接触位置**之内 → 不算退出（修复的核心断言）。
        XCTAssertFalse(
            shouldHonorHoverExit(
                isOpen: true,
                lastContactRect: tallPanelContactRect,
                pointer: pointerInsideTallPanel
            ),
            "指针还在最后接触到的面板位置里 → 这次退出是面板缩走了（切页取高），不按 hover 退出收面板"
        )

        // ② 真退出：指针出了那块接触位置（下方 160pt）→ 照收（既有契约不变）。
        XCTAssertTrue(
            shouldHonorHoverExit(
                isOpen: true,
                lastContactRect: tallPanelContactRect,
                pointer: NSPoint(x: 756, y: 40)
            ),
            "指针已经出了接触位置 → 真退出，照收"
        )

        // ③ 真退出（横向移开同样算）：指针从侧面离开面板。
        XCTAssertTrue(
            shouldHonorHoverExit(
                isOpen: true,
                lastContactRect: tallPanelContactRect,
                pointer: NSPoint(x: 100, y: 200)
            ),
            "指针横向出了接触位置 → 真退出，照收"
        )

        // ④ 接触位置刷新到**缩小后**的面板（用户重新进过面板）：指针在这块新位置之外 → 真退出。
        //    （观测量就是轮询 / `handleHover(true)` 记录的「面板窗口」rect——不是别的 app 窗口。）
        let shrunkPanelContactRect = CGRect(x: 313, y: 650, width: 887, height: 310)
        XCTAssertTrue(
            shouldHonorHoverExit(
                isOpen: true,
                lastContactRect: shrunkPanelContactRect,
                pointer: pointerInsideTallPanel
            ),
            "接触位置已刷新为缩短后的面板 → 指针在它之外 = 真退出"
        )

        // ⑤ 没有接触记录（还没观测到过；例如面板由快捷键打开、指针从没进过面板）→ 老口径（照收，保守）。
        XCTAssertTrue(
            shouldHonorHoverExit(isOpen: true, lastContactRect: nil, pointer: pointerInsideTallPanel),
            "没有接触记录 → 按老口径收（没观测过就不猜）"
        )

        // ⑥ 折叠态：退出只收起 hover 视觉（`finishHoverExit` 在折叠态本来就不关面板）→ 一律按退出处理，
        //    本判据不得改变折叠态的既有行为。
        XCTAssertTrue(
            shouldHonorHoverExit(
                isOpen: false,
                lastContactRect: tallPanelContactRect,
                pointer: pointerInsideTallPanel
            ),
            "折叠态一律按退出处理（那一档不关面板，判据不参与）"
        )
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
