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
//  PanelAutoHeight.swift
//  Gourd 宿主 · 展开面板的「贴内容」高度算术（p5-home-blocks / T6）
//
//  展开面板的高度自本批起有两种模式（`Defaults[.panelHeightMode]`，**裸字符串** `"auto"`（默认）/
//  `"manual"`，与 `timerDisplayMode` 同形的存法）：
//
//  - **manual**：今天的行为——高度 = 用户滑块 / 右下角拖出来的 `Defaults[.openNotchHeight]`，
//    逐字不变。本文件的 `panelHeight(...)` 在这一档**原样返回手动值**，夹取仍由既有的
//    `clampedOpenNotchHeight` 做（尺寸层那条调用链一字未改，改动前它就是这一条）。
//  - **auto**：高度 = **内容自然高 + 宿主上下内边距**，夹在
//    `[openNotchHeightRange.lowerBound, effectiveOpenNotchHeightUpperBound(屏高)]`
//    ——与滑块同一个上界函数，不另立一套（D-11 / docs/29 §做法 机制六）。
//
//  内容自然高只有**首页**是算出来的（`HomeBandedHomeView` 把流方案的 `heightUsed` + 日历行 +
//  缝算出结果写进下面的过渡持有者）；其它 tab 由 T7 的测量账本（`PanelContentHeight`）上报
//  ——见 docs/29 §备选与取舍 ⑥：流方案在渲染前就有自然高，用测量反而引入首帧跳动。
//
//  **本文件是纯算术**（与 `HomeFlowLayout` / `HomeVerticalFit` / `matters.swift` 同一条纪律：
//  只做算术、不读偏好、不碰视图），唯一的例外是那个**过渡持有者** `homeContentHeight`
//  （`@MainActor` 静态可写，T7 升级成 `PanelContentHeight`）。
//

import CoreGraphics
import Foundation

/// 展开面板的高度模式与「内容高 → 面板高」的换算（纯函数）。
enum PanelAutoHeight {

    // MARK: - 模式（裸字符串）

    /// 自适应（默认）：面板贴住内容。
    static let modeAuto = "auto"
    /// 手动：滑块 / 拖动把手说了算（今天的行为）。
    static let modeManual = "manual"

    /// 这一档是不是自适应。**未知值按 auto 处理**：`panelHeightMode` 是裸字符串键，存量值被手改 /
    /// 写进未知串时 `Defaults` 不会拦（与 `notchPanelBackgroundStyle` 的裸串同一条口径），
    /// 而这一档的默认值就是 auto——未知值落回默认比落进「手动」更保守。
    static func isAuto(_ mode: String) -> Bool { mode != modeManual }

    // MARK: - 宿主垂直内边距（auto 加在内容高之上的那一份）

    /// 首页内容之外、**面板高度之内**的上下内边距 = `NotchHomeView` 给首页内容包的 `.padding(8)`
    /// 上下各一（`NotchHomeView.mainContent` 的那句，非极简档）。
    ///
    /// 它是 `panelHeight(...)` 在 auto 下加的唯一一份：面板表头（`DynamicIslandHeader`）由接缝
    /// 折进**内容高**里（见下面 `contentHeight(from:)` 与持有者的注释）——表头高随屏 / 配置变
    /// （`panelHeaderHeight(...)`），写不成这里的常量；而它对「面板高 = 内容 + 内边距」这条式子
    /// 必须**不低估**（少算表头 → 可用高比内容矮一截 → 最后一行被流方案整行丢掉），
    /// 所以只能由知道 `vm` 的那一层给。
    static let homeVerticalPadding: CGFloat = 16

    /// 展开态内容**上方面板表头**的高度（`NotchLayout` 给 `DynamicIslandHeader` 的高度：
    /// `max(24, vm.effectiveClosedNotchHeight)`）。
    ///
    /// 与 `DynamicIslandCalendar.availableTodayListHeight` / `NotchTimerView.maxTabContentHeight`
    /// 里那条既有口径**同一个数**（两处都是「面板高度 − 这个数 − 自己的内边距」）；`max(24, …)`
    /// 的下限也在那两处，且 `ContentView` 的表头 `.frame(height:)` 就是它——三处同源。
    static func panelHeaderHeight(effectiveClosedNotchHeight: CGFloat) -> CGFloat {
        let closed = effectiveClosedNotchHeight.isFinite ? effectiveClosedNotchHeight : 0
        return max(24, closed)
    }

    /// 流的**自然高预算**（纯函数）：面板高度上界扣掉宿主垂直开销——流在这个预算下画满
    /// 全部行与日历行（上界函数给的是有限数，最坏 850，**不是无界**）。
    ///
    /// 这是「内容自然高」的算入口径：比这个预算还装不下的尾巴行，即使面板顶到上界也永远显示不了，
    /// 丢掉是对的（流方案自己会丢）。
    static func naturalFlowBudget(hostChrome: CGFloat, screenVisibleHeight: CGFloat?) -> CGFloat {
        let upper = effectiveOpenNotchHeightUpperBound(screenVisibleHeight: screenVisibleHeight)
        return max(0, upper - max(0, hostChrome.isFinite ? hostChrome : 0))
    }

    // MARK: - 换算（纯函数）

    /// 内容高 → 面板高（纯函数）。
    ///
    /// - manual：**原样返回手动值**（夹取由尺寸层既有的 `clampedOpenNotchHeight` 做——manual 那条
    ///   链路因此逐字还是今天那条）。
    /// - auto：`min(max(contentHeight + homeVerticalPadding, 下界), 上界)`；`contentHeight` 非有限
    ///   （首帧还没有人算过 / 异常读数）时**回落手动值**，不让一个 NaN 把面板尺寸整块打掉。
    static func panelHeight(
        contentHeight: CGFloat,
        mode: String,
        manualHeight: CGFloat,
        screenVisibleHeight: CGFloat?
    ) -> CGFloat {
        guard isAuto(mode) else { return manualHeight }
        guard contentHeight.isFinite else { return manualHeight }
        let upper = effectiveOpenNotchHeightUpperBound(screenVisibleHeight: screenVisibleHeight)
        return min(max(contentHeight + homeVerticalPadding, openNotchHeightRange.lowerBound), upper)
    }

    /// 首页内容高（接缝口径）= 流方案的内容高 + 画了日历行时那一段「缝 + 行高」+ **面板表头**。
    ///
    /// 表头折在这里是刻意的（见 `homeVerticalPadding` 的注释）：`panelHeight(...)` 只加那 16pt 的
    /// 上下内边距，表头这一块随屏变化，只能由知道 `vm.effectiveClosedNotchHeight` 的那一层
    /// （接缝）折进内容高。`plan.showsCalendarRow` 是流方案按预算自己的取舍结果（关掉日历行时
    /// 调用方传的 `calendarHeight` 为 0，方案自然不画那一行）。
    static func contentHeight(
        from plan: HomeFlowLayout.Plan,
        calendarHeight: CGFloat,
        calendarSpacing: CGFloat,
        headerHeight: CGFloat
    ) -> CGFloat {
        var height = max(0, plan.heightUsed.isFinite ? plan.heightUsed : 0)
        if plan.showsCalendarRow {
            height += max(0, calendarSpacing.isFinite ? calendarSpacing : 0)
            height += max(0, calendarHeight.isFinite ? calendarHeight : 0)
        }
        height += max(0, headerHeight.isFinite ? headerHeight : 0)
        return height
    }

    /// per-tab 高度覆盖（计时器 250 / 终端比例高）与内容高的合并口径（D-16 / docs/29 §做法 机制六
    /// 边界 ④）：**manual = 逐字替换**（今天那条：`baseSize.height = 覆盖值`），
    /// **auto = `max(覆盖值, 内容高)`**——它们是某些 tab 的**下限**，不是上限。
    ///
    /// 便签 / 剪贴板那两条本来就是 `max(base, preferred)` 的形状，auto 下逐字就是
    /// `max(覆盖值, 内容高)`，因此不走本函数（`calculateRequiredNotchSize` 的注释里写明）。
    static func mergedTabHeight(override: CGFloat, current: CGFloat, mode: String) -> CGFloat {
        isAuto(mode) ? max(override, current) : override
    }

    // MARK: - 收敛（首页那一份的种子口径）

    /// 迭代上限：内容高的台阶只有「多一行 / 少一行」那么粗，典型 2~3 步就停；到顶还没停下说明
    /// 出现了不该有的振荡，直接返回当前值（宁可停在近似值，也不无限算）。
    static let convergenceMaxIterations = 6

    /// 收敛判据（pt）：差在这个以内就算到了不动点（窗口高度本身还会取整，追到小数没有意义）。
    static let convergenceEpsilon: CGFloat = 0.5

    /// **双向收敛**（纯函数）：`h₀ = seedPanelHeight`（**当前面板高度**），
    /// `hₙ₊₁ = panelHeight(contentHeight(hₙ), …)`。
    ///
    /// `contentHeight` 由接缝给：它是「内容自然高」的探针（首页那一份按 `naturalFlowBudget` 的口径
    /// 算出来，与面板当前多高**无关**——理由见 `contentHeight(from:)` 与接缝里的注释：按预算丢行的
    /// 口径会让收敛变成单向棘轮）。manual 档下 `panelHeight(...)` 不读它，循环一步即返回手动值。
    ///
    /// **双向**：高于内容就收缩、低于就长高——从屏幕上的现状（种子）出发走到「内容高 + 内边距」，
    /// 种子在内容之上 / 之下都不需要不同的分支（**不是**单向棘轮：只许收缩时，种子低于内容高
    /// 就永远长不上去，日历行与后半行会永久不画，docs/29 §做法 机制六 的收敛口径）。
    /// 夹取（上界 / 下界）之后**不回改内容**：本函数返回的就是结论，调用方拿它直接当面板高。
    static func convergedPanelHeight(
        seedPanelHeight: CGFloat,
        mode: String,
        manualHeight: CGFloat,
        screenVisibleHeight: CGFloat?,
        contentHeight: (CGFloat) -> CGFloat
    ) -> CGFloat {
        var height = seedPanelHeight.isFinite ? seedPanelHeight : manualHeight
        for _ in 0..<convergenceMaxIterations {
            let next = panelHeight(
                contentHeight: contentHeight(height),
                mode: mode,
                manualHeight: manualHeight,
                screenVisibleHeight: screenVisibleHeight
            )
            if abs(next - height) <= convergenceEpsilon { return next }
            height = next
        }
        return height
    }

    /// 唯一单向的规则：**光标在面板里时不缩**（只允许长高）——否则鼠标停在下方时会把面板从光标
    /// 底下抽走（docs/29 §做法 机制六 边界 ①）。
    ///
    /// 副作用是「从高内容切到矮内容、光标又停在面板里」时看起来偏大，移开鼠标后下一次重算才贴合
    /// （§已知限制 1，本批如实接受）。作用范围只有首页这一路；其它 tab 的账本在 T7。
    static func heldForPointer(
        converged: CGFloat,
        currentPanelHeight: CGFloat,
        pointerInsidePanel: Bool
    ) -> CGFloat {
        guard pointerInsidePanel else { return converged }
        guard converged.isFinite, currentPanelHeight.isFinite else { return converged }
        return max(converged, currentPanelHeight)
    }

    // MARK: - 过渡持有者（首页内容高）

    /// 首页**内容自然高**（含面板表头，口径见 `contentHeight(...)`）：接缝 `HomeBandedHomeView`
    /// 在 body 里写，尺寸层（`openNotchSize` → `calculateRequiredNotchSize` / `calculateDynamicNotchSize`）
    /// 经 `panelHeight(...)` 读。
    ///
    /// **过渡形态**（T7 升级为 `PanelContentHeight` 账本）：`nil` = 还没有人算过（首帧 / 从没渲染
    /// 过首页）→ 尺寸层回落手动值，于是「打开面板的第一拍」按旧高度画，第二帧才贴内容
    /// （docs/29 §已知限制 2 如实记下）。
    ///
    /// 写方是视图 body、读方是尺寸层，两者都在主线程上：`@MainActor` 只是把这件事写明。
    @MainActor
    static var homeContentHeight: CGFloat?
}
