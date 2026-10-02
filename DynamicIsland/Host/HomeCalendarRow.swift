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
//  HomeCalendarRow.swift
//  Gourd 宿主 · 首页全宽日历行（P2 批次 / T2）
//
//  展开面板首页从「一条 strip」改成**两排**（用户 2026-09-29 拍板）：上排仍是 strip（音乐 / 镜子 /
//  模块块，契约逐字不变），下排是本行的**全宽日历行**——左整月网格（可翻月、今天高亮、按选中日居中）、
//  右所选日期的今日清单（多行、不滚动）。
//
//  为什么单独一排：7 列月历需要宽度（原先日历塞在 200–260pt 的块里，格子只有约 26pt，只能显示
//  「日期头 + 几点内容」），单独一排既给足宽度、又把月历入口补回展开面板。
//
//  复用而非重写（D-02）：左侧直接用 `MonthGridView`（从 `StandaloneCalendarView` 左栏抽出，同一份
//  实现）；右侧直接用 `EventListView`（竖向紧凑多行，行数由 `HomeTodayListLayout.capacity` 按可用高度
//  算准，自己不滚动）。本文件只负责**排版与接缝**：两栏怎么分宽、行高多少、交互接到哪条既有链路。
//
//  规格：docs/17-nookx-adoption.md（本批改判 §做法 的结构描述：strip + 日历行）。
//

import Defaults
import SwiftUI

/// 展开面板首页的**全宽日历行**：左边整月网格、右边所选日期的今日清单。
///
/// 行的存在性由 `Defaults[.showCalendar]` 门控（在 `NotchHomeView` 的接缝处判断，关掉时本视图根本
/// 不生成——不留空壳、不占高度）。行高是**按当月周数算出的固定档**（`36N + 52`，见 `rowHeight`）：
/// 面板高度不足时优先保上排 strip（strip 拿 `max(0, 剩余高度)`），本行不参与「按内容伸缩」的协商。
struct HomeCalendarRow: View {
    /// 行高 = `36 × N + 52`（N = **当前月**的实际周数；算式本体与独立日历页同源，逐项推导与上屏校准
    /// 记录见 `MonthGridLayout.monthGridHeight(forMonth:calendar:)`）。
    ///
    /// **按当月实际**（p6-ui-polish / T8，docs/30 §做法 机制六）：3 周 160、5 周 232（2026-10）、
    /// 6 周 268。旧口径是「最坏 6 周」的固定 294（2026-09-29 复审定的那一档）→ T8 改成按当月
    /// （2026-10 先落到 258），T8 tune 按控制器上屏实测收回网格下方的三段多预留（22 + 3 + 2 = 27，
    /// 其中 1pt 作为防拉伸余量保留）→ 232。
    /// 面板高随月变化是**接受**的行为（docs/30 §做法 机制六）。
    ///
    /// **宿主 plan 的预算读同一个数**（`HomeStripView` 的三处 `calendarHeight`）：行与它的预算因此
    /// 永远同值，不会出现「行比预算高一段、末行被面板裁掉」。
    ///
    /// 浏览翻月**不改**行高（本行按当前月算；翻到更高的月份时网格在自己的视口里滚动）——宿主 plan
    /// (HomeStripView) 不在 T8 的文件范围，行高若跟着**显示**月份走，翻到 6 周月时行会比预算高 36pt、
    /// 末行被面板裁掉（T8 的失败信号之一）；「按当前月」是同一份预算下唯一自洽的那一档。
    static var rowHeight: CGFloat { rowHeight(forMonth: Date()) }

    /// 行高的**纯函数**入口（按给定月份；测试钉 2026-08 = 6 周 / 2026-10 = 5 周这类边界）。
    static func rowHeight(forMonth month: Date, calendar: Calendar = .current) -> CGFloat {
        MonthGridLayout.monthGridHeight(forMonth: month, calendar: calendar)
    }

    /// 本行与上排 strip 之间的间距（接缝里的 `VStack(spacing:)` 取同一个值，两处只有一个数）。
    static let rowSpacing: CGFloat = 8

    /// 右栏今日清单的**右侧内边距**：留给展开面板右下角的拖动把手（D-29），约 36pt（2026-09-29 补）。
    ///
    /// 为什么要留：把手命中框 `panelResizeHandleHitSize`（32pt）距面板右下角各
    /// `panelResizeHandleEdgeInset`（14pt）→ 它从面板右边往内占到 **46pt**、从下边往内也占到 46pt。
    /// 而本行内容离面板右边缘只有 12（展开态面板自身内边距）+ 14（`notchHorizontalPadding` 开态
    /// = 19 − 5）+ 8（`NotchHomeView` 的内边距）= **34pt**，今日清单**最后一行**的行尾（提醒勾选圈
    /// 与行尾那一段可点区）因此正落在把手的命中框里：点上去是被把手吃掉（拖动面板）而不是打开日程，
    /// 提醒勾选圈更是直接点不到。
    ///
    /// 取值：46 − 34 = 12 是「刚好不重叠」的下限；取 36（≈ 下限 + 24）是留出余量——把手的有效区
    /// 还受面板裁剪形状（`NotchShape` 右下角是二次曲线）影响，而 36 让行的右端停在距边 70pt 处，
    /// 与把手之间留 24pt 空白，勾选圈（14pt）也整颗在安全区内。代价是标题列窄 36pt（尾部截断更早、
    /// 勾选圈更靠内），这是「行尾可点」换来的，按判决**不缩小把手**。
    static let todayListTrailingInset: CGFloat = 36

    /// 左栏（整月网格）占行宽的比例。
    private static let monthGridWidthRatio: CGFloat = 0.55
    /// 左栏最小宽度：7 列日格低于这个宽度就挤到不可读。
    private static let monthGridMinWidth: CGFloat = 320
    /// 右栏至少留出的宽度（今日清单的「时间列 + 标题」）。
    private static let todayListMinWidth: CGFloat = 200
    /// 两栏之间的间距（分隔线两侧各一份）。
    private static let columnSpacing: CGFloat = 12

    @ObservedObject private var calendarManager = CalendarManager.shared
    @EnvironmentObject var vm: DynamicIslandViewModel
    @State private var selectedDate = Date()
    /// 月历「滚到选中日」的请求（初值在 `.onAppear` 里钉一次，让今天那格落在视口中央）。
    @State private var monthScrollTarget: Date?
    @Default(.hideCompletedReminders) private var hideCompletedReminders
    @Default(.hideAllDayEvents) private var hideAllDayEvents

    /// 与独立面板同一套过滤（已完成提醒 / 全天条目按偏好隐藏），空态判据因此也一致。
    /// **数据源是 `calendarManager.events`（选中日那一天）**——右栏今日清单的口径。
    private var filteredEvents: [EventModel] {
        EventListView.filteredEvents(
            events: calendarManager.events,
            hideCompletedReminders: hideCompletedReminders,
            hideAllDayEvents: hideAllDayEvents
        )
    }

    /// 月历网格的**按月**数据源：`calendarManager.monthEvents`（显示月份整张网格的窗口，含跨月补格）
    /// 经同一套偏好过滤。与上面 `filteredEvents`（按**日**、只覆盖选中日）是两条不同窗口的数据，
    /// **别把这一份传给右栏清单**（那会让今日清单列出整月条目）。
    private var monthEventSnapshot: MonthEventSnapshot {
        MonthEventSnapshot(
            month: calendarManager.monthEvents.month,
            events: EventListView.filteredEvents(
                events: calendarManager.monthEvents.events,
                hideCompletedReminders: hideCompletedReminders,
                hideAllDayEvents: hideAllDayEvents
            )
        )
    }

    /// 右侧清单的表头：与独立面板收起态的日期头同形，显示**选中**的日期（与月历高亮同源）。
    private var headerText: String {
        selectedDate.formatted(.dateTime.weekday(.abbreviated))
            + ", " + selectedDate.formatted(.dateTime.month(.abbreviated))
            + " " + selectedDate.formatted(.dateTime.day())
    }

    /// 今日清单的可用高度 = 行高 − 表头。`collapsedHeaderHeight` 的构成里**已经含**「表头与列表
    /// 之间的 4pt 间距」，所以不再另加（与 `CalendarView` 同一条口径）。
    private var todayListHeight: CGFloat {
        max(0, Self.rowHeight - HomeTodayListLayout.collapsedHeaderHeight)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: Self.columnSpacing) {
                MonthGridView(
                    selectedDate: $selectedDate,
                    scrollTarget: $monthScrollTarget,
                    // 翻月只改显示月份、不动选中日（首页这一排的月历是「浏览」用的；
                    // 选中日只由点某一天改，右侧清单与高亮因此只在点日期时变）。
                    monthNavigationMovesSelection: false,
                    // 有事件的日期给日格画小圆点：传**按月**快照（`calendarManager.monthEvents` 过滤后
                    // 的那一份，与右侧清单同一套偏好口径）——已完成提醒 / 被隐藏的全天条目不会有点。
                    // 传入的是整张网格窗口的条目，切片到「显示月份的那张网格」由 `MonthGridView` 自己
                    // 按它持有的 `displayedMonth` 做（翻月后标记要跟着变）。
                    monthEvents: monthEventSnapshot,
                    // 显示月份一变（翻月 / 选中日换月）就抓那个月的数据。
                    onDisplayedMonthChange: { month in
                        Task { await calendarManager.updateMonthEvents(for: month) }
                    },
                    // **首页这一排不画网格上下的滚动提示渐变**（2026-09-30 用户反馈第 1 条 / D-01）：
                    // 行高按「一屏显示整月」反推（`rowHeight` 的算式），网格不滚——两条渐变在这里
                    // 不是提示、只是纯黑面板上的两处脏线。独立日历（`StandaloneCalendarView`）的
                    // 网格可滚，默认档 `true` 保持不变。
                    showsScrollFades: false
                )
                .frame(width: monthGridWidth(in: max(0, geometry.size.width)), alignment: .topLeading)

                // 两栏之间的细分隔线（面板既有的白色细线口径）。
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)

                todayListColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    // 右侧内边距：把今日清单（含表头）的可点区右端从面板右下角的拖动把手命中框里
                    // 让出来（取值与理由见 `todayListTrailingInset`）。放在列的 `frame` 之后，
                    // 因此列的外框宽度不变、只有内容区窄了 36pt。
                    .padding(.trailing, Self.todayListTrailingInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: Self.rowHeight)
        // 日历行的**玻璃板**（p7c / docs/32 §做法 机制二 · D-13 · D-14）：毛玻璃档下本行也成一「板」
        // （黑 0.14 / 圆角 15 / 无描边 + 柔影 + 顶缘微光），与上排的单条流块同一机制。
        //
        // `interactive: false`（D-13）：本行是**纯展示块**（docs/30 机制七），口径是**「只给板」**
        // （docs/32 §做法 机制二）——不装 hover（本行自带一条 `onHover` 做面板收起遮罩
        // `vm.isHoveringCalendar`，两层会打架）、不装 scale / brightness、**也不装内容软影**
        // （该层作用在块内内容边缘，是单条流格子的装饰；本行改动前没有任何浮起层）。
        //
        // **板 = 行框**（不内缩）：D-14 优先「与单条流块外缘对齐」（板左右各内缩 8pt），但上屏实测
        // **冲突**——月历网格自带 `.padding(.horizontal, 6)`，内缩 8pt 时左侧「十月」题头的笔画落在
        // 板外（`evidence/plate-measure.txt` §八：内缩 8pt 时板外左缘 4pt 带内有白色内容像素
        // x353.5…354、y270…271；退到行框后为 0）。按 D-14 的退法取行框（板因此比流块外缘宽
        // 8pt/侧），守 D-03 的硬要求「内容必须全部落在板内」。
        // 纯黑档下本行**一层都不画**（黑档不画板——逐字不变）。
        .homeBlockFloat(interactive: false)
        // 首次出现时把日历数据对齐到**今天**（与 `CalendarView` / `StandaloneCalendarView` 的
        // `.onAppear` 同一条口径），并把月历滚到今天那格。
        .onAppear {
            monthScrollTarget = Calendar.current.startOfDay(for: selectedDate)
            Task {
                await calendarManager.updateCurrentDate(selectedDate)
            }
        }
        // 点月历某天 → 换到那一天的日程（高亮由 `MonthGridView` 自己跟着 `selectedDate` 变）。
        .onChange(of: selectedDate) {
            Task {
                await calendarManager.updateCurrentDate(selectedDate)
            }
        }
        // 悬停遮罩（沿用日历块与模块块的既有做法）：`ContentView` 用它抑制「向下滚动收起面板」与
        // 横向切歌手势，避免用户在日历上操作时面板被误收起。
        .onHover { isHovering in
            vm.isHoveringCalendar = isHovering
        }
        // 行被销毁（关日历行 / 收面板）时 `onHover` 不会再补发一次 false，必须显式归位——
        // 否则 `vm.isHoveringCalendar` 悬空为 true，面板之后再也收不起来。
        .onDisappear {
            vm.isHoveringCalendar = false
        }
    }

    /// 左栏宽度：行宽的 55%，但不小于 320pt（7 列的下限）；行太窄时给右栏留出
    /// `todayListMinWidth`，两者冲突时以 320 为下限（右栏在这种情况下自己收敛宽度）。
    private func monthGridWidth(in available: CGFloat) -> CGFloat {
        let preferred = available * Self.monthGridWidthRatio
        let roomForTodayList = max(0, available - Self.columnSpacing * 2 - 1 - Self.todayListMinWidth)
        let upperBound = max(Self.monthGridMinWidth, roomForTodayList)
        return min(max(preferred, Self.monthGridMinWidth), upperBound)
    }

    /// 右栏：表头 + 今日清单（空态走 `EmptyEventsView`），整体顶部对齐。
    private var todayListColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(headerText)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.top, 2)
                .frame(height: HomeTodayListLayout.collapsedHeaderHeight, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if filteredEvents.isEmpty {
                EmptyEventsView(selectedDate: selectedDate)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                // **不滚动**：行数由 `HomeTodayListLayout.capacity` 按可用高度算准，算不准就要么截断
                // 要么留白（与首页日历块同一条口径）。
                EventListView(
                    events: calendarManager.events,
                    selectedDate: selectedDate,
                    availableHeight: todayListHeight
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
