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
//  HomeVerticalFit.swift
//  Gourd 宿主 · 首页各带的高度取舍（P2 批次 / T2；P3 组件批次 / T7 扩四档）
//
//  展开面板首页的**标准路径**由三样东西组成（自上而下）：**主块带**（大块：音乐、镜子）、
//  **小组件带**（紧凑块：进度、统计、待办、通知、前台应用）、**全宽日历行**。三样都要高度，
//  面板高度不够时就得按顺序放弃。**放弃顺序是产品默认值**（不是用户旋钮），本文件是那条判据的
//  唯一落点。
//
//  口径（docs/26-home-widgets-and-settings.md §做法 机制六 / D-09）：
//  1. `both`（三样都在）→ 2. `noCalendar`（**先收日历行**，两带都在）→
//  3. `widgetsOnly`（**再收主块带**，小组件带拿全部可用高度）→ 4. `none`（空）。
//  「先收日历行」是 P2 的既有裁决（docs/23-home-fit.md §做法 机制二 / D-02）：主块带是「扫一眼」
//  的主内容，日历行是「展开看」的次内容；T7 起把同一条口径往下一档延伸——**主块带先于小组件带让位**
//  （小组件更便宜、信息密度更高，矮面板下先保住它们，这正是用户「不要都隐藏掉」那条反馈的落点）。
//
//  **T7 改动前后**：旧三档是 `both` / `stripOnly` / `calendarOnly`；新四档里 `both` 与
//  `noCalendar` 的算式与旧 `both` / `stripOnly` 逐字一致（没有紧凑块时新四档**退化成旧三档**：
//  `both` ≡ 旧 both、`noCalendar` ≡ 旧 stripOnly、`none` ≡ 旧 calendarOnly——旧 `calendarOnly`
//  那一档在生产档下从来不画日历行，见 `HomeCalendarRow.rowHeight`（294）> `HomeStripView.minimumUsableHeight`
//  （152），判据的 `available >= calendarRowHeight` 因而不可能成立）。
//
//  为什么是**纯函数**（无 SwiftUI、无偏好、无单例）：取舍只有几条边界，值得穷举；放在视图里就只能
//  靠改高度、截图、肉眼比，判错一位也没人知道。视图侧只剩「按 plan 画哪几条」的机械动作。
//
//  本文件**不读** `Defaults[.showCalendar]`：日历行开不开是用户偏好，由接缝
//  （`HomeBandedHomeView`）先判，再把「日历行要占的高度」作为入参传进来（关掉时传 0——
//  日历行不存在时它不参与取舍）。同理，「有没有大块 / 有几个紧凑块」也由调用方按名单算好传进来。
//

import CoreGraphics

/// 首页三样（主块带 + 小组件带 + 全宽日历行）在给定可用高度下的取舍结果。
///
/// 判据是**按顺序的四段问句**，顺序即优先级（先问「三样一起放得下吗」，再逐样往下让）：
/// 1. `both`：日历行 + 主块带（≥ 最小可用高度）+ 小组件带（全部行）一起放得下 → 三样都画；
/// 2. `noCalendar`：日历行让位，两带按需高画（主块带拿剩下的高度）；
/// 3. `widgetsOnly`：主块带让位，小组件带拿**全部**可用高度（行数够时全部行都在）；
/// 4. `none`：连一行小组件都放不下 → 什么都不画。
///
/// **空带不进取舍**：没有大块时传 `mainBandMinimumHeight = 0`、没有紧凑块时传
/// `widgetRowHeight = 0` / `widgetRowsNeeded = 0`——那一条带既不占高度、也不占带间间距，
/// 取舍因此退化成「剩下那几样」的旧算式。
enum HomeVerticalFit {

    /// 取舍落在哪一档。档名描述的是**画出来的东西**（不是「谁被放弃」）：
    /// - `.both`：日历行 + 两带都在（改动前叫 `both` 的那一档，日历行的位置与算式未变）；
    /// - `.noCalendar`：两带都在（日历行让位，D-02 的那一档）；
    /// - `.widgetsOnly`：只有小组件带（主块带也让位，D-09 新增的那一档）；
    /// - `.none`：什么都不画（连一行小组件都放不下）。
    enum Layout: Equatable {
        case both
        case noCalendar
        case widgetsOnly
        case none
    }

    /// 一次取舍的完整结果：视图只需要读它，不再自己算高度。
    struct Plan: Equatable {
        /// 落在哪一档（判据见 `HomeVerticalFit` 的文档）。
        let layout: Layout
        /// 主块带的高度：`.both` / `.noCalendar` 档 = 扣掉日历行与小组件带之后的剩余；
        /// 其余档 = `0`（不画）。**没有大块时恒为 0**（调用方传的 `mainBandMinimumHeight = 0`）。
        let mainBandHeight: CGFloat
        /// 小组件带的高度：`.both` / `.noCalendar` 档 = 全部行要的高度；
        /// `.widgetsOnly` 档 = **全部可用高度**（行数多时也不会溢出：行数由这条高度反算）；其余档 = `0`。
        let widgetBandHeight: CGFloat
        /// 日历行画不画。**调用方仍需自己与「用户有没有开日历行」相与**
        /// （本类型不认偏好，见文件头注释）。
        let showsCalendarRow: Bool

        /// 主块带画不画。**高度是唯一判据**：分到高度才有它——没有大块的调用方传
        /// `mainBandMinimumHeight = 0`，于是任何一档都算不出正高度（不必再看 `layout`）。
        var showsMainBand: Bool { mainBandHeight > 0 }

        /// 小组件带画不画（同上：没有紧凑块时任何一档都算不出正高度）。
        var showsWidgetBand: Bool { widgetBandHeight > 0 }
    }

    /// 按可用高度决定三样的取舍（纯函数：同样入参永远同样结果）。
    ///
    /// - Parameters:
    ///   - available: 分给这些内容的**全部**可用高度（已扣掉宿主内边距等），负值按 0 处理。
    ///   - calendarRowHeight: 日历行要占的高度（关掉日历行时传 `0`）。
    ///   - rowSpacing: 相邻两样之间的统一间距（`HomeCalendarRow.rowSpacing`；只有一样时它不生效）。
    ///   - mainBandMinimumHeight: 主块带的**最小可用高度**（`HomeStripView.minimumUsableHeight`，
    ///     「画不满就不画」的阈值）；**没有大块时传 0**（这条带不参与取舍）。
    ///   - widgetRowHeight: 小组件带**一行**的高度；**没有紧凑块时传 0**。
    ///   - widgetRowSpacing: 小组件带的行间距（算「全部行要多少高度」用）。
    ///   - widgetRowsNeeded: 全部紧凑块按宽度铺开需要几行（`HomeBandedLayout.rowsNeeded(...)`）。
    /// - Returns: 四档之一的 `Plan`。**阈值是闭区间**：`available` 恰好等于某个阈值时算「放得下」，
    ///   不留一档只有 0.0001pt 宽的缝。
    static func plan(
        available: CGFloat,
        calendarRowHeight: CGFloat,
        rowSpacing: CGFloat,
        mainBandMinimumHeight: CGFloat,
        widgetRowHeight: CGFloat,
        widgetRowSpacing: CGFloat,
        widgetRowsNeeded: Int
    ) -> Plan {
        let available = max(0, available)
        let gap = max(0, rowSpacing)
        let calendarNeed = max(0, calendarRowHeight)
        let mainMin = max(0, mainBandMinimumHeight)
        let rowHeight = max(0, widgetRowHeight)
        let rows = max(0, widgetRowsNeeded)

        let hasCalendar = calendarNeed > 0
        let hasMain = mainMin > 0
        let hasWidgets = rowHeight > 0 && rows > 0
        // 小组件带要的总高度：n 行 = n × 行高 + (n−1) × 行间距（行间距只存在于行与行之间）。
        let widgetsNeed = hasWidgets
            ? CGFloat(rows) * rowHeight + CGFloat(rows - 1) * max(0, widgetRowSpacing)
            : 0
        // 间距只存在于**两个都画**的相邻两样之间（空带不占间距）。
        let calendarGap = hasCalendar && (hasMain || hasWidgets) ? gap : 0
        let bandGap = hasMain && hasWidgets ? gap : 0

        // ① 三样一起放得下：小组件带拿它的需高，主块带拿剩下的（日历行拿固定档，算式未变）
        if available >= calendarNeed + calendarGap + mainMin + bandGap + widgetsNeed {
            let widgetBandHeight = widgetsNeed
            return Plan(
                layout: .both,
                mainBandHeight: hasMain ? available - calendarNeed - calendarGap - bandGap - widgetBandHeight : 0,
                widgetBandHeight: widgetBandHeight,
                showsCalendarRow: hasCalendar
            )
        }

        // ② 日历行让位（两带都在，主块带拿剩下的高度）
        if available >= mainMin + bandGap + widgetsNeed {
            let widgetBandHeight = widgetsNeed
            return Plan(
                layout: .noCalendar,
                mainBandHeight: hasMain ? available - bandGap - widgetBandHeight : 0,
                widgetBandHeight: widgetBandHeight,
                showsCalendarRow: false
            )
        }

        // ③ 主块带让位：小组件带拿全部可用高度（**行数不再受限**，除了「一行都放不下」这一条——
        //    真实行数由 `HomeBandedLayout.affordableRows(bandHeight:…)` 按这条高度反算）
        if hasWidgets, available >= rowHeight {
            return Plan(layout: .widgetsOnly, mainBandHeight: 0, widgetBandHeight: available, showsCalendarRow: false)
        }

        // ④ 连一行小组件都放不下：什么都不画（日历行不单独存活——它是第一个让位的）
        return Plan(layout: .none, mainBandHeight: 0, widgetBandHeight: 0, showsCalendarRow: false)
    }
}
