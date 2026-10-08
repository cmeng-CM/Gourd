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
//  缝算出来写进账本）；其它 tab 由高度账本（`PanelContentHeight`，Kernel 层）上报——见
//  docs/29 §备选与取舍 ⑥：流方案在渲染前就有自然高，用测量反而引入首帧跳动。
//
//  **本文件是纯算术**（与 `HomeFlowLayout` / `HomeVerticalFit` / `matters.swift` 同一条纪律：
//  只做算术、不读偏好、不碰视图）：T6 那个过渡持有者（`homeContentHeight`）在 **T7 升级成
//  `PanelContentHeight`**（`DynamicIsland/Kernel/PanelContentHeight.swift`），本文件不再持有任何
//  可变状态；「测量值 → 内容高」的那一步换算仍是纯函数（`measuredContentHeight(naturalHeight:headerHeight:)`）。
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

    /// 展开面板**内容区上下**的宿主内边距 = 面板里那四处内边距的**逐项求和**（每一项都带出处）：
    ///
    /// | 项 | 出处 |
    /// |---|---|
    /// | **+16** | `NotchHomeView.swift:954` 的 `.padding(Defaults[.enableMinimalisticUI] ? 0 : 8)`（上下各一，非极简档） |
    /// | **+12** | `ContentView.swift:814` 的 `.padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)`（展开态的底边） |
    /// | **+4** | `ContentView.swift:815` 的 `.padding(.top, isIslandMode ? 0 : notchTopScreenBleedAmount)`（刘海屏的顶出血，`notchTopScreenBleedAmount = 4`） |
    /// | **+8** | `ContentView.swift` 的 `NotchLayout()` 里 `VStack(alignment: .leading, spacing: notchLayoutSpacing)`——**表头与内容之间那道缝**（原先不写 `spacing:` 走平台默认值 8；控制器 2026-10-01 实机测量发现它落在可见黑框以内、吃掉首页可用高，日历行因此整行被丢） |
    ///
    /// **刻意不计入的两项**——它们在 `panelHeight(...)` 的返回值**之上**又加了一次窗口尺寸，
    /// 折进本常数就是把同一段距离算两遍：
    /// - `+18`（`matters.swift` 的 `notchShadowPaddingStandard`）：`addShadowPadding(to:isMinimalistic:)`
    ///   在 `DynamicIslandApp.calculateRequiredNotchSize` 里加在**返回尺寸上**（窗口比这里返回的值
    ///   高 18）；控制器实测确认它**在可见黑框之外**（窗口 588 → 黑框 570），不计是对的。
    /// - `+4`（`DynamicIslandApp.adjustedSizeForScreen` 的 `notchTopScreenBleed`）：同一份顶出血在
    ///   窗口一侧再加一次——上面那 **+4** 是它在**面板内**的那一侧，这一项在面板外，不重复计。
    ///
    /// 逐项求和 = **40**（= 16 + 12 + 4 + 8）。口径：**面板的可见黑框 ≈ `panelHeight(...)` 返回的
    /// 那个值 + 4**（顶出血在黑框内、在屏幕外）——于是「返回的面板高 − 内容自然高（含表头）」必须
    /// 覆盖面板内的这四处内边距，首页拿到的 frame 才等得住它自己那份 plan 的需求：
    /// `frame = 需求 + (本常数 − 40)`，40 就是等式解（零富余，`need <= budget` 的闭区间判据因此
    /// 仍把日历行画上）；面板底部的可见留白只剩 `NotchHomeView` 的 8 与 `ContentView` 的 12
    /// = **20pt**（设计内的呼吸感，也是本次实机验收的判据）。
    ///
    /// **与既有先例的关系**：`DynamicIslandCalendar.availableTodayListHeight` 用的是
    /// 「面板高 − 表头 − 16」（只算 `NotchHomeView` 那一项，另两处与那道缝都漏了）；
    /// 本常数是同一条算式补全到四处（T6 复核 P2 + 控制器实机测量两轮）。
    /// 作用范围：**刘海屏的展开态**（浮动药丸模式顶部不占 4，见上表第三项的 `isIslandMode`）。
    static let homeVerticalPadding: CGFloat = 16 + 12 + 4 + notchLayoutSpacing

    /// `NotchLayout()` 里**表头与内容之间那道缝**（`VStack(alignment: .leading, spacing:)`）。
    ///
    /// 取值与平台默认值一致（8），提到这里只是为了让它**具名**：它是面板可见黑框以内、消耗首页
    /// 可用高的一段距离，`homeVerticalPadding` 的表里必须能点到它（控制器 2026-10-01 实机测量：
    /// 漏掉它会让日历行整行被流方案丢掉）。改这个数 = 同时改面板的观感与首页的预算，两处一起走。
    static let notchLayoutSpacing: CGFloat = 8

    /// **所有 tab 共享**的那一份宿主垂直开销 = `ContentView` 展开态的底边 12 + 刘海屏顶出血 4 +
    /// 表头↔内容的缝 8 = **24**（三项的出处与 `homeVerticalPadding` 的表同源，逐项写死在这里）。
    ///
    /// 与 `homeVerticalPadding`（40）的**差**恰好是 `NotchHomeView` 那一份上下各 8（只有首页有，
    /// 见 `homeOnlyVerticalPadding`）——非首页 tab 的「内容区高 → 面板高」的换算必须用本常数，
    /// 拿 40 会每算一次多留 16pt（T7：其它 tab 的高度是**量**出来的，量的那一步先减掉首页独有的
    /// 那一段，见 `measuredContentHeight(naturalHeight:headerHeight:)`）。
    static let panelVerticalPadding: CGFloat = 12 + 4 + notchLayoutSpacing

    /// 首页**独有**的一份宿主内边距 = `NotchHomeView` 的 `.padding(8)`（上下各一，非极简档）
    /// = `homeVerticalPadding − panelVerticalPadding` = **16**。
    ///
    /// 其它 tab 的内容不经过 `NotchHomeView`，因此它们的「自然高 + 表头」折算成内容高时要**减掉**
    /// 这一份，尺寸层再 `+ homeVerticalPadding` 时才刚好等于「自然高 + 表头 + 24」——面板贴住内容、
    /// 且整页**填满**内容区时（量出来的自然高 = 内容区高）面板高**一步回到原值**（不动点）。
    static let homeOnlyVerticalPadding: CGFloat = homeVerticalPadding - panelVerticalPadding

    /// 测量出来的**自然高** → 账本口径的内容高（含表头，`PanelContentHeight.current`）的换算
    /// （纯函数，p5-home-blocks / T7）。
    ///
    /// 口径一条链写死：面板高 = 内容高 + `homeVerticalPadding`（40），而其它 tab 的内容区 =
    /// 面板高 − 表头 − `panelVerticalPadding`（24）。于是「自然高 N、表头 H」的一页要的面板高是
    /// `N + H + 24`，反解出内容高 = `N + H + 24 − 40` = **`N + H − 16`**（`homeOnlyVerticalPadding`）。
    ///
    /// 非有限项按 0（与 `contentHeight(from:)` 同一条口径：不让一个坏读数把面板尺寸打掉；不过
    /// 账本的 `report(...)` 本来就不收非有限值——这里是第二道）。
    static func measuredContentHeight(naturalHeight: CGFloat, headerHeight: CGFloat) -> CGFloat {
        let natural = naturalHeight.isFinite ? naturalHeight : 0
        let header = headerHeight.isFinite ? headerHeight : 0
        return natural + header - homeOnlyVerticalPadding
    }

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
    ///
    /// **2026-10-08（p8-height-smooth）**：起点（种子）从那以后**不再影响结论**——原先唯一会读它的
    /// 规则（「光标在面板内不缩」，`heldForPointer`）已删除（理由见 `PanelContentHeight` 文件头与
    /// docs/00 ADR-0015）：本函数今天在首页那份常量探针下**一步就收敛**，留下它是为了保住
    /// 「夹取 + 双向」这条既有语义与它的用例（换一个真的依赖面板高的探针时仍然是这套算术）。
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
}
