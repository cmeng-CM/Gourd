/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import Defaults
import EventKit

// MARK: - Shared auto-scroll helpers

/// Partition events into all-day and timed groups.
func partitionEvents(_ events: [EventModel]) -> (allDay: [EventModel], timed: [EventModel]) {
    (events.filter { $0.isAllDay }, events.filter { !$0.isAllDay })
}

/// Determine which timed event to scroll to, based on a reference time.
/// For today, pass Date() to find in-progress/upcoming events.
/// For other dates, pass startOfDay to scroll to the first event of that day.
func scrollTargetForTimedEvents(timed: [EventModel], referenceTime: Date) -> EventModel? {
    // Prefer an event that carries a conference (Join Meeting) link and is
    // currently active, so its Join button is scrolled into view (#566 feedback:
    // all-day events used to push these out of the visible area).
    let activeConference = timed.first(where: { event in
        guard event.conferenceURL != nil else { return false }
        if event.type.isReminder {
            return event.start <= referenceTime && referenceTime < event.start.addingTimeInterval(3600)
        }
        return event.start <= referenceTime && event.end > referenceTime
    })
    let inProgress = timed.first(where: { event in
        if event.type.isReminder {
            // Reminders are point-in-time; treat as "in progress" only within 1h of start
            return event.start <= referenceTime && referenceTime < event.start.addingTimeInterval(3600)
        }
        return event.start <= referenceTime && event.end > referenceTime
    })
    let nextUpcoming = timed.first(where: { $0.start > referenceTime })
    let lastTimed = timed.last
    return activeConference ?? inProgress ?? nextUpcoming ?? lastTimed
}

/// Reference time for auto-scroll: current time for today, startOfDay for past/future days.
func scrollReferenceTime(for date: Date) -> Date {
    Calendar.current.isDateInToday(date) ? Date() : Calendar.current.startOfDay(for: date)
}

// MARK: - Compact all-day events strip

/// Shared layout metrics for the all-day events strip.
///
/// The strip height and the space reserved for it in the timed-events list must
/// stay in sync across `AllDayEventsStrip`, `StandaloneEventCardList`, and
/// `EventListView`. Centralising the values here avoids the hardcoded
/// `28` / `3` / `41` / `30` duplicated in multiple views (#566 review).
private enum AllDayStripMetrics {
    /// Height of the horizontal chip row inside `AllDayEventsStrip`.
    static let chipRowHeight: CGFloat = 28
    /// Vertical padding applied around the chips and the strip content.
    static let verticalPadding: CGFloat = 3
    /// Top inset pushed onto the timed `List` so `scrollTo(.top)` lands the
    /// target event fully below the floating all-day overlay
    /// (chip row + 1pt divider + 1pt margin ≈ 30pt). Shared by `EventListView`
    /// and `StandaloneEventCardList` so both reserve exactly the same space.
    /// (#566 review: de-duplicate the hardcoded 28/3/41/30)
    static let listTopInset: CGFloat = 30
}

/// Horizontal, single-row strip of all-day events.
///
/// The Dynamic Island calendar panel is height-constrained (`CalendarView` is
/// capped at a fixed height). The previous design stacked one full row per
/// all-day event in a pinned top section, so two all-day events could consume
/// the entire panel and leave no room for the timed-events scroll area below
/// (#566 follow-up). This strip keeps the all-day section at a constant
/// single-row height regardless of how many all-day events exist — extra
/// events scroll horizontally within the strip instead of growing vertically.
private struct AllDayEventsStrip: View {
    @Environment(\.openURL) private var openURL
    let events: [EventModel]
    var onToggleReminder: ((String, Bool) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(events) { event in
                        allDayChip(event)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, AllDayStripMetrics.verticalPadding)
            }
            .frame(height: AllDayStripMetrics.chipRowHeight)
            .clipped()

            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 1)
                .padding(.horizontal, 4)
        }
    }

    private func allDayChip(_ event: EventModel) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(event.calendar.color))
                .frame(width: 8, height: 8)

            Text(event.title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(1)

            if event.isAllDay {
                Text("All-day")
                    .font(.caption2)
                    .foregroundColor(Color(white: 0.6))
                    .lineLimit(1)
            }

            if event.type.isReminder, let onToggleReminder {
                reminderToggle(for: event, using: onToggleReminder)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, AllDayStripMetrics.verticalPadding)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .contentShape(Capsule())
        .onTapGesture {
            if let url = event.calendarAppURL() {
                openURL(url)
            }
        }
    }

    private func reminderToggle(for event: EventModel, using onToggleReminder: @escaping (String, Bool) -> Void) -> some View {
        let isCompleted: Bool
        if case .reminder(let completed) = event.type {
            isCompleted = completed
        } else {
            isCompleted = false
        }
        return ReminderToggle(
            isOn: Binding(
                get: { isCompleted },
                set: { newValue in onToggleReminder(event.id, newValue) }
            ),
            color: Color(event.calendar.color)
        )
    }
}

struct Config: Equatable {
    var past: Int = 7
    var future: Int = 14
    var steps: Int = 1
    var spacing: CGFloat = 0
    var showsText: Bool = true
    var offset: Int = 2
}

/// Reports the measured width of a single date cell, used to translate a
/// mouse drag (in points) into a scroll-position step.
private struct CellWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct WheelPicker: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @Binding var selectedDate: Date
    @State private var scrollPosition: Int?
    @State private var haptics: Bool = false
    @State private var byClick: Bool = false
    /// Tracks a mouse press-drag so an external mouse can scrub dates like a
    /// trackpad two-finger scroll (macOS ScrollView doesn't pan on mouse drag).
    @State private var dragAnchorPos: Int? = nil
    @State private var measuredCellWidth: CGFloat = 40
    let config: Config

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: config.spacing) {
                let spacerNum = config.offset
                let dateCount = totalDateItems()
                let totalItems = dateCount + 2 * spacerNum
                ForEach(0..<totalItems, id: \.self) { index in
                    if index < spacerNum || index >= spacerNum + dateCount {
                        Spacer()
                            .frame(width: 24, height: 24)
                            .id(index)
                    } else {
                        let date = dateForItemIndex(index: index, spacerNum: spacerNum)
                        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                        dateButton(date: date, isSelected: isSelected, id: index) {
                            selectedDate = date
                            byClick = true
                            withAnimation {
                                scrollPosition = index
                            }
                            if Defaults[.enableHaptics] {
                                haptics.toggle()
                            }
                        }
                    }
                }
            }
            .frame(height: 50)
            .scrollTargetLayout()
        }
        .scrollIndicators(.never)
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .scrollTargetBehavior(.viewAligned)
        .safeAreaPadding(.horizontal)
        .sensoryFeedback(.alignment, trigger: haptics)
        .onChange(of: scrollPosition) { _, newValue in
            if !byClick {
                handleScrollChange(newValue: newValue, config: config)
            } else {
                byClick = false
            }
        }
        .onAppear {
            scrollToToday(config: config)
        }
        .onChange(of: selectedDate) { _, newValue in
            let targetIndex = indexForDate(newValue)
            if scrollPosition != targetIndex {
                byClick = true
                withAnimation {
                    scrollPosition = targetIndex
                }
            }
        }
        .onPreferenceChange(CellWidthKey.self) { measuredCellWidth = $0 }
        // Mouse press-drag scrubs dates (trackpad two-finger scroll still works
        // natively — that arrives as a scroll event, not a drag gesture, so the
        // two never conflict). Steps = drag points / measured cell width.
        // `.simultaneousGesture` (not `.gesture`) so the drag runs alongside the
        // strip's own gestures instead of swallowing the date-cell taps.
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if dragAnchorPos == nil { dragAnchorPos = scrollPosition }
                    guard let start = dragAnchorPos, measuredCellWidth > 1 else { return }
                    let steps = Int((-value.translation.width / measuredCellWidth).rounded())
                    let spacerNum = config.offset
                    let totalItems = totalDateItems() + 2 * spacerNum
                    let newPos = min(max(spacerNum, start + steps), totalItems - 1)
                    if newPos != scrollPosition {
                        withTransaction(Transaction(animation: nil)) {
                            scrollPosition = newPos
                        }
                    }
                }
                .onEnded { _ in
                    dragAnchorPos = nil
                }
        )
    }

    private func dateButton(date: Date, isSelected: Bool, id: Int, onClick: @escaping () -> Void) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        return Button(action: onClick) {
            VStack(spacing: 8) {
                dayText(date: dateToString(for: date), isToday: isToday, isSelected: isSelected)
                dateCircle(date: date, isToday: isToday, isSelected: isSelected)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.effectiveAccentBackground : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .id(id)
        .background(GeometryReader { geo in
            Color.clear.preference(key: CellWidthKey.self, value: geo.size.width)
        })
    }

    private func dayText(date: String, isToday: Bool, isSelected: Bool) -> some View {
        Text(date)
            .font(.caption)
            .foregroundColor(isSelected ? .white : Color(white: 0.65))
    }

    private func dateCircle(date: Date, isToday: Bool, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isToday ? Color.effectiveAccent : .clear)
                .frame(width: 20, height: 20)
            Text(date.date)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : Color(white: isToday ? 0.9 : 0.65))
        }
    }

    func handleScrollChange(newValue: Int?, config: Config) {
        guard let newIndex = newValue else { return }
        let spacerNum = config.offset
        let dateCount = totalDateItems()
        guard (spacerNum..<(spacerNum + dateCount)).contains(newIndex) else { return }
        let date = dateForItemIndex(index: newIndex, spacerNum: spacerNum)
        if !Calendar.current.isDate(date, inSameDayAs: selectedDate) {
            selectedDate = date
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }

    private func scrollToToday(config: Config) {
        let today = Date()
        byClick = true
        scrollPosition = indexForDate(today)
        selectedDate = today
    }

    /// 下面三个换算都转发到 `WheelPickerIndexMath`（纯函数，**没有** SwiftUI 依赖）：
    /// 「选中日 ↔ 轮上项下标」的算术是本视图唯一能被单测穷举的部分（`ModuleKernelTests`），
    /// 视图里只留 `Date()` / `Calendar.current` 这两个环境取值。
    private func indexForDate(_ date: Date) -> Int {
        WheelPickerIndexMath.index(for: date, config: config, now: Date(), calendar: .current)
    }

    private func dateForItemIndex(index: Int, spacerNum: Int) -> Date {
        WheelPickerIndexMath.date(atItemIndex: index, spacerNum: spacerNum, config: config, now: Date(), calendar: .current)
    }

    private func totalDateItems() -> Int {
        WheelPickerIndexMath.totalItems(config: config)
    }

    private func dateToString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
}

/// 日期轮的**下标算术**（纯函数：不引 SwiftUI、不读环境，`now` 与 `calendar` 由调用方给）。
///
/// 抽出它的理由（2026-09-29，T1）：轮子的「初始定位」= 「选中日 → 项下标」这一条换算，
/// 而视图层（`WheelPicker` 的 `onAppear` / `onChange`）本身测不了——把算术抽出来，
/// 「初始定位落在选中日上」才有可回归的判据（`DynamicIslandTests/ModuleKernelTests.swift`）。
/// 逐字照搬 `WheelPicker` 原来的三个私有方法，**行为不变**：同一条公式、同一个 `Calendar`
/// 口径（`startOfDay` 归一后按天差算）、同样的左闭右夹取（`0...totalItems-1`）。
enum WheelPickerIndexMath {
    /// 轮上的项总数：`ceil((past + future) / steps) + 1`（照 `WheelPicker.totalDateItems()`；
    /// `steps` 用 `max(_, 1)` 兜底，`steps = 3` 时按 3 天一跳计）。
    static func totalItems(config: Config) -> Int {
        let range = config.past + config.future
        let step = max(config.steps, 1)
        return Int(ceil(Double(range) / Double(step))) + 1
    }

    /// `date` 落在轮上的项下标：`offset + clamp(天数差 / steps, 0, totalItems - 1)`。
    ///
    /// `now` 决定「今天」——它同时是窗口的起点（`now - past` 天）与天数差的参照；传固定日期
    /// 就能得到确定的判据（本机今天不算输入）。
    static func index(for date: Date, config: Config, now: Date, calendar: Calendar) -> Int {
        let spacerNum = config.offset
        let today = calendar.startOfDay(for: now)
        let startDate = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: -config.past, to: today) ?? today
        )
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startDate, to: target).day ?? 0
        let stepIndex = max(0, min(days / max(config.steps, 1), totalItems(config: config) - 1))
        return spacerNum + stepIndex
    }

    /// 项下标对应的日期（`WheelPicker.dateForItemIndex` 原式）：`startDate + (index - 起点偏移) × steps`。
    ///
    /// 下标落在前导 `offset` 个「占位格」上时返回 `now - past` 天那天（原式不区分占位格与日期格，
    /// 前导格在视图里是 `Spacer`，不会被当作日期显示）。
    static func date(atItemIndex index: Int, spacerNum: Int, config: Config, now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        let startDate = calendar.date(byAdding: .day, value: -config.past, to: today) ?? today
        let stepIndex = index - spacerNum
        return calendar.date(byAdding: .day, value: stepIndex * max(config.steps, 1), to: startDate) ?? today
    }
}

struct CalendarView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var selectedDate = Date()
    @State private var dateExpanded = false
    @Default(.hideAllDayEvents) private var hideAllDayEvents
    @Default(.hideCompletedReminders) private var hideCompletedReminders

    /// 今日列表的可用高度（2026-09-29）：面板高度 − 刘海底座 − 首页内边距 − 收起态日期头。
    ///
    /// 口径与独立面板旧档的 `StandaloneCalendarView.maxTabContentHeight` 同源（都从 `vm.notchSize`
    /// 往下减）——独立面板 p6-ui-polish / T8 起改**自然高**布局（docs/30 §做法 机制六），那个
    /// 「按面板高反推」的口径现在只剩本视图（**仅供 `#Preview`**，运行期不可达；首页日历见
    /// `HomeCalendarRow` 自己按行高算的那一份）。今日列表的行数**只**由这里决定
    /// （`HomeTodayListLayout.capacity`），不再靠滚动容纳条目。
    private var availableTodayListHeight: CGFloat {
        let panelHeight = vm.notchSize.height > 0 ? vm.notchSize.height : openNotchSize.height
        let closedNotch = max(24, vm.effectiveClosedNotchHeight)
        // 16 = 首页 `NotchHomeView` 的上下各 8pt 内边距（与独立面板的 −36 不同源，各自留自己的）。
        let reserved = closedNotch + 16 + HomeTodayListLayout.collapsedHeaderHeight
        return max(0, panelHeight - reserved)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact-by-default date header: when collapsed it shows a single
            // small "weekday, month day" line (~20pt) so the event list below
            // keeps almost the whole height. Hovering the header expands
            // the horizontal date-scroll strip (with edge-fade shadows) — the
            // shadows therefore appear exactly when it is scrollable, matching
            // the maintainer's review #1 intent (not permanently drawn).
            // (2026-09-29：块本身已不再写死 120pt，日期头省下的高度直接留给「今日」行数。)
            HStack(alignment: .center, spacing: 8) {
                // Left label: one compact line when collapsed; month + year when expanded.
                VStack(alignment: .leading, spacing: 1) {
                    if dateExpanded {
                        Text(selectedDate.formatted(.dateTime.month(.abbreviated)))
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Text(selectedDate.formatted(.dateTime.year()))
                            .font(.caption)
                            .fontWeight(.regular)
                            .foregroundColor(Color(white: 0.65))
                    } else {
                        Text(selectedDate.formatted(.dateTime.weekday(.abbreviated))
                             + ", " + selectedDate.formatted(.dateTime.month(.abbreviated))
                             + " " + selectedDate.formatted(.dateTime.day()))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 72, alignment: .leading)

                ZStack {
                    WheelPicker(selectedDate: $selectedDate, config: Config())
                        .frame(maxWidth: .infinity)
                    // Edge fades indicating the date strip is horizontally
                    // scrollable. Subtle (0.45) so they hint without hiding text.
                    LinearGradient(colors: [Color.black.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 16)
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LinearGradient(colors: [.clear, Color.black.opacity(0.45)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 16)
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                // Use the WheelPicker's natural height (50pt) when expanded so its
                // date cells are never clipped top/bottom. Collapsed = 0 height.
                .frame(height: dateExpanded ? 50 : 0)
                .opacity(dateExpanded ? 1 : 0)
                .allowsHitTesting(dateExpanded)
                // 这里**不能**加 `.clipped()`（2026-09-29 实测定位，T1 修复）：`WheelPicker`
                // 内部是 AppKit 背书的 `ScrollView`（`NSScrollView`），而外层 `.clipped()` 在容器
                // 还是零高时就被求值/缓存成「全裁掉」，之后容器长到 50pt 也不会刷新——日期轮于是
                // 永远不可见（只剩两侧渐隐；同容器里的 SwiftUI 自绘内容照常显示）。对照实验：
                // 同一容器写法下 A（带 clipped）= 空条、B（去掉 clipped）= 日期正常、C（展开才挂载
                // 但带 clipped）= 日期正常，见 `.workflow/p2-calendar-row/reports/`。
                // 收起态的不可见由上面两行保证（0 高 + 透明），不需要裁剪。
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            .contentShape(Rectangle())
            .onHover { inside in
                withAnimation(.easeInOut(duration: 0.18)) {
                    dateExpanded = inside
                }
            }

            let filteredEvents = EventListView.filteredEvents(
                events: calendarManager.events,
                hideCompletedReminders: hideCompletedReminders,
                hideAllDayEvents: hideAllDayEvents
            )
            if filteredEvents.isEmpty {
                // 空态：保持既有文案（`EmptyEventsView`），但**不占满高度**——脚本原先跟在
                // 后面的 `Spacer(minLength: 0)` 已删（2026-09-29 用户反馈：首页日历不允许出现
                // 「一行内容 + 大片留白」）。
                EmptyEventsView(selectedDate: selectedDate)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                EventListView(
                    events: calendarManager.events,
                    selectedDate: selectedDate,
                    availableHeight: availableTodayListHeight
                )
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 整块按**内容高度**收缩（2026-09-29 用户反馈「还有很大留白」）：原先这里写死
        // `.frame(height: 120)`——当时为了不撑大折叠态窗口，但首页面板早已是 120…850 可配的
        // 展开态，120pt 的固定块在今日条目少时就是一块空白（且把列表压进 120 里去滚）。
        // 现在块高 = 日期头 + 今日列表（最多 5 行 + 溢出提示），多余的空白自然留在面板最下方，
        // 不再夹在日期头与列表之间；顶部对齐由 `NotchHomeView` 的 `HStack(alignment: .top)` 保证。
        .fixedSize(horizontal: false, vertical: true)
        .listRowBackground(Color.clear)
        .onChange(of: selectedDate) {
            Task {
                await calendarManager.updateCurrentDate(selectedDate)
            }
        }
        .onChange(of: vm.notchState) { _, _ in
            Task {
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
            }
        }
        .onAppear {
            Task {
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
            }
        }
    }
}

// MARK: - 整月网格（抽取复用：独立面板左栏 + 首页日历行左栏）

/// 一份**按月**的事件快照：`month` = 这份数据覆盖的显示月份（该月 1 日零点），`events` = 该月
/// 网格覆盖区间（`MonthGridLayout.monthWindow`）内的**已过滤**条目（口径 = `EventListView.filteredEvents`）。
///
/// 由 `CalendarManager.monthEvents`（按月的唯一抓取路径）产出、经宿主过滤后交给 `MonthGridView`。
///
/// **为什么把「月份」和「条目」绑成一份传**：网格的显示月份由 `MonthGridView` 自持，而按月数据是
/// 异步到的——只传条目数组的话，翻月那一瞬间会拿**上个月**的条目去算新月份的标记（错点落在新网格上）；
/// 绑上月份后 `MonthGridLayout.eventDays` 只在「快照月份 == 显示月份」时出点，数据在路上时宁可空着。
struct MonthEventSnapshot {
    /// 快照覆盖的月份（该月 1 日零点）；`nil` = 还没有任何按月数据。
    var month: Date?
    var events: [EventModel]

    static let empty = MonthEventSnapshot(month: nil, events: [])
}

/// 整月网格的**纯几何 + 纯标记**：`MonthGridView` 日格与事件标记的唯一来源，由 `StandaloneCalendarView`
/// 的 `monthDays` 逐字抽出（口径不变）——
///
/// 首格 = **当月首日所在那一周的起点**、末格 = **当月末日所在那一周的终点**，逐日 +1 展开，
/// 因此两端都含跨月补格（补格来自相邻月份），总天数恒为 7 的整数倍。周起点跟着
/// `calendar.firstWeekday` 走（与 `MonthGridView` 的星期表头同一来源）。
///
/// 不读 `Defaults`、不碰「今天」，因此可以用固定 `Calendar` + 固定月份/事件直接单测
/// （`ModuleKernelTests` 的 `MonthGridLayoutTests`）。
enum MonthGridLayout {
    static func days(forMonth month: Date, calendar: Calendar = .current) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let firstWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
              let lastWeekInterval = calendar.dateInterval(of: .weekOfMonth, for: lastDay)
        else { return [] }

        var days: [Date] = []
        var current = firstWeekInterval.start
        while current < lastWeekInterval.end {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return days
    }

    /// 显示月份在固定格高网格里占的**周数**（纯函数）：`MonthGridView` 两侧的高度算式共用的唯一来源。
    ///
    /// 就是 `days(forMonth:calendar:)`（网格渲染的那份数据）按 7 列摊开后的行数——**逐字同源**，
    /// 不另写一份「按日历算周数」的算式：首格 = 当月首日所在周的起点、末格 = 当月末日所在周的终点，
    /// 两端含跨月补格、总格数恒为 7 的倍数（`days(forMonth:)` 的口径），因此 `count / 7` 就是
    /// `LazyVGrid`（7 列）画出来的行数。另起一份算式会在「首周起点跟 `firstWeekday` 走」
    /// 「一个月最多跨 6 周」这些边界上与网格漂（2026 年 8 月 = 7/26–9/5 = 6 周即那类边界）。
    ///
    /// 取不到当月（异常日期 → 空数组）→ 0 周（调用方各自兜底，不产生负高）。
    static func weekCount(for month: Date, calendar: Calendar = .current) -> Int {
        days(forMonth: month, calendar: calendar).count / 7
    }

    /// 整月网格在**固定格高**下要的高度（纯函数）：`36 × N + 78`，N = `weekCount(for:calendar:)`。
    ///
    /// 算式（`MonthGridView` 的既有内部刻度，两处宿主共用的唯一一份）：
    /// - 网格视口 = `(高度 − 4 − 56) − 22` = `高度 − 82`（4 = 网格自身 `.padding(.top, 4)`；
    ///   56 = `pickerViewportHeight` 里让给「月份标题行 + 周标题行」的固定扣减；22 = 周标题行与
    ///   其下日格之间那段的扣减）；
    /// - 一周占 `30`（日格 `minHeight`）+ `6`（`LazyVGrid` 行距）= **36pt**；`N` 周需要
    ///   `36N − 6`（末行不带行距）+ `2`（网格 `.padding(.bottom, 2)`）= `36N − 4`；
    /// - 视口 ≥ 内容 → `高度 ≥ 36N + 78`：3 周 186、5 周 258（2026-10）、6 周 294。
    ///
    /// 两个调用方：首页日历行（`HomeCalendarRow.rowHeight`，宿主 plan 的预算与行的 frame 同值）与
    /// 独立日历页（`StandaloneCalendarView` 左栏，面板高按它上报）。
    static func monthGridHeight(forMonth month: Date, calendar: Calendar = .current) -> CGFloat {
        36 * CGFloat(weekCount(for: month, calendar: calendar)) + 78
    }

    /// 某个日期所在月份的**首日零点**——按月数据的键（`MonthEventSnapshot.month` 与
    /// `MonthGridView.displayedMonth` 用它比较，`CalendarManager.updateMonthEvents` 用它去重）。
    static func firstDay(ofMonth month: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: month))
            ?? calendar.startOfDay(for: month)
    }

    /// 某个显示月份要**抓取的事件区间**：网格首格零点 → 末格次日零点（末尾排他，正好是 EventKit
    /// 谓词的 `end` 口径）。
    ///
    /// 与 `days(forMonth:)` **同源**（就是它的首末格）：网格画得出的每一格都在这个区间内，
    /// 因此「哪些天有点」不会因为抓取窗口比网格小而缺格——这是按月数据路径的窗口判据
    /// （用例 `testMonthWindowCoversEveryMonthGridOfAYear` 钉住）。
    ///
    /// 注意末端的**半开**口径：`end` 那一瞬间（末格的次日零点）不属于窗口。`DateInterval.contains`
    /// 是**闭**区间（末点也算在内），判边界时别拿它当判据（测试里显式按半开比较）。
    static func monthWindow(forMonth month: Date, calendar: Calendar = .current) -> DateInterval? {
        let gridDays = days(forMonth: month, calendar: calendar)
        guard let first = gridDays.first,
              let last = gridDays.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last)
        else { return nil }
        return DateInterval(start: first, end: end)
    }

    /// 给定月份里**有事件的日期**（每个元素都是那天的零点）——`MonthGridView` 日格标记的唯一判据。
    ///
    /// 三条口径（都有用例钉住）：
    /// 1. **传入的 `events` 必须已过滤**：调用方走 `EventListView.filteredEvents(events:hideCompletedReminders:hideAllDayEvents:)`
    ///    （「已完成提醒 / 被偏好隐藏的全天条目」不进标记），本函数自己**不读 `Defaults`、不碰 `CalendarManager`**
    ///    ——这样"哪些天有点"与右侧清单同源，不会出现「清单里没有这条、格子上却有点」；
    /// 2. **覆盖区间按天算**：一条事件覆盖 `[起始日, (结束时刻 − 1s) 所在日]` 里的每一天（跨天事件每天都算）。
    ///    那个 −1s 是必须的：全天事件在 EventKit 里 `end` 是**次日零点的排他值**（9/29 全天 = 9/29 00:00 → 9/30 00:00），
    ///    不减就会把次日也标上；定时事件跨零点（9/29 23:00 → 9/30 01:00）两天都覆盖，也是这条规则的自然结果；
    /// 3. **按月切片**：只返回**当月网格（含跨月补格）里**的日期。补格（相邻月份的日期）照样带标记——与系统
    ///    日历一致，格子既然画出来了就该显示它有没有事件；网格之外的日期不进集合，跨月事件因此不会把标记
    ///    画到别的月份的格子上。
    static func daysWithEvents(
        inMonth month: Date,
        events: [EventModel],
        calendar: Calendar = .current
    ) -> Set<Date> {
        guard !events.isEmpty else { return [] }

        let coverage: [(first: Date, last: Date)] = events.map { event in
            let first = calendar.startOfDay(for: event.start)
            // 结束时刻不晚于起始时刻（零长 / 数据异常）时退化为「只覆盖起始日」，不产生空区间。
            let last = calendar.startOfDay(for: event.end.addingTimeInterval(-1))
            return (first, max(first, last))
        }

        var daysWithEvents: Set<Date> = []
        for day in days(forMonth: month, calendar: calendar) {
            let normalized = calendar.startOfDay(for: day)
            if coverage.contains(where: { normalized >= $0.first && normalized <= $0.last }) {
                daysWithEvents.insert(normalized)
            }
        }
        return daysWithEvents
    }

    /// 显示月份对应的「有事件日期」集合 = **按月快照的切片**，`MonthGridView` 日格标记的唯一入口。
    ///
    /// 比 `daysWithEvents(inMonth:events:calendar:)` 多一层**月份对齐**判据：快照的 `month`
    /// 必须与显示月份同月，否则返回空集。数据是按月异步抓的（`CalendarManager.updateMonthEvents`），
    /// 翻月后新数据到达之前手上还是上个月的条目——不对齐就会把上个月的点画到新网格上
    /// （批次的失败信号之一）；对齐判据下这段时间是「没有点」，不会出错点。
    ///
    /// 快照的条目仍然**必须已过滤**（口径同 `daysWithEvents`，由宿主走 `EventListView.filteredEvents`）。
    static func eventDays(
        forDisplayedMonth displayedMonth: Date,
        snapshot: MonthEventSnapshot,
        calendar: Calendar = .current
    ) -> Set<Date> {
        guard let month = snapshot.month,
              calendar.isDate(month, equalTo: displayedMonth, toGranularity: .month)
        else { return [] }
        return daysWithEvents(inMonth: displayedMonth, events: snapshot.events, calendar: calendar)
    }
}

/// 可复用的整月网格：**月份标题 + ‹ › 翻月 + 星期表头 + 7 列日格（公历数字 + 第二行的农历 / 节假日
/// + 今天 / 选中高亮 / 有事件的小圆点）+ 按选中日居中**。
///
/// 从 `StandaloneCalendarView` 左栏**逐字抽出**（只抽不重写）：独立日历面板与首页的整行日历共用这
/// 一份实现——月历逻辑只有一处，不再复制第二份（复制必然漂移）。
///
/// 视图只负责「显示哪个月 + 选中哪天」：选中日的写回方（调用方）自己决定要不要拉那一天的日程
/// （独立面板与首页日历行都走 `CalendarManager.updateCurrentDate`）。
///
/// **事件标记的数据源由调用方传入**（`monthEvents`，一份**按月**的快照、条目已过滤）：本视图不读
/// `CalendarManager.shared`，因为同一个网格有两个宿主（首页日历行 / 独立面板），谁读全局单例都会让
/// 这份实现绑死在宿主的数据口径上，也没法用固定事件直接测「标记画在哪几天」。
///
/// **T4 起同一份快照还供给日格的第二行**（农历 + 节假日，见 `subtitleText(for:cellWidth:)`）：
/// 两个宿主因此自动都拿到系统数据（机制四「只改一处」），不需要各接一条新链路。
///
/// 数据是**按月**抓的（窗口 = 本视图显示月份的整张网格，见 `MonthGridLayout.monthWindow`），
/// 因此本视图多了一个出口 `onDisplayedMonthChange`：显示月份一变就通知宿主去抓那个月
/// ——月历标记不能靠宿主自己的选中日窗口（那是**一天**，除选中日外整月都不会有点）。
struct MonthGridView: View {
    /// 选中日：日格读它做高亮、点日格写它。
    @Binding var selectedDate: Date
    /// 「把日格滚到某日」的请求通道（原 `StandaloneCalendarView.datePickerScrollTarget` 的那套）：
    /// 置值即滚一次、滚完清回 `nil`。
    @Binding var scrollTarget: Date?
    /// 翻月时是否把选中日一并挪到**新月份首日**：独立面板的既有行为是 `true`；
    /// 首页日历行传 `false`（翻月只改显示月份，选中日不动）。
    var monthNavigationMovesSelection: Bool
    /// 事件标记的数据源：**按月**快照，`events` 必须**已过滤**（口径 = `EventListView.filteredEvents`，
    /// 由调用方在「`CalendarManager.monthEvents` → 过滤」之后传进来）。
    /// 切片到「显示月份的那张网格（含跨月补格）」由 `MonthGridLayout.eventDays` 在这里做；
    /// 快照月份与显示月份不同月时不出点（数据在路上时的口径）。
    var monthEvents: MonthEventSnapshot
    /// 显示月份变化通知（含首次出现）：宿主据此抓该月数据（`CalendarManager.updateMonthEvents(for:)`）。
    /// 只在这一件事上回调，不做高频轮询。
    var onDisplayedMonthChange: ((Date) -> Void)?

    /// 日格网格上下那两条**滚动提示渐变**（`datePicker` 里的两处 `LinearGradient`）画不画。
    ///
    /// 这两条渐变只服务于「网格高于视口、可以滚」的场景，是滚动提示而不是装饰（2026-09-30 D-01）。
    /// 用户对同一处脏线**提了第二次**（2026-09-30 第 5 条「日历面板还存在两条线的遮罩」）后，
    /// **两个宿主都传 `false`**（D-04）：
    /// - 首页日历行（`HomeCalendarRow`）：行高按「一屏显示整月」反推（`HomeCalendarRow.rowHeight`
    ///   的算式），网格根本不滚——渐变在这里从来不是提示；
    /// - 独立日历面板（`StandaloneCalendarView`）：用户实测那两条线在纯黑面板上只是两处脏线，
    ///   遮挡了月历格里的第二行（农历 / 节假日）。
    ///
    /// **默认值仍是 `true`**（本视图参数保留）：谁都不再依赖它，留着是给 `#Preview` / 将来第三个宿主
    /// 用的（改默认值会让「不看这一行调用方就多两条线」变成隐式行为）。
    ///
    /// **只切「画不画」，不切样式与位置**：渐变的颜色 / 16pt 高度 / 上下贴边都不随它变
    ///（改样式是另一件事，会把余下这条支路的提示也一起改掉）。
    var showsScrollFades: Bool = true

    /// 显示月份：本视图自持（翻月只动它），随选中日同步——选中日一变就跳到它所在的月份。
    @State private var displayedMonth: Date

    private let calendar = Calendar.current

    init(
        selectedDate: Binding<Date>,
        scrollTarget: Binding<Date?>,
        monthNavigationMovesSelection: Bool = false,
        monthEvents: MonthEventSnapshot,
        onDisplayedMonthChange: ((Date) -> Void)? = nil,
        showsScrollFades: Bool = true
    ) {
        _selectedDate = selectedDate
        _scrollTarget = scrollTarget
        self.monthNavigationMovesSelection = monthNavigationMovesSelection
        self.monthEvents = monthEvents
        self.onDisplayedMonthChange = onDisplayedMonthChange
        self.showsScrollFades = showsScrollFades
        // 初值取选中日所在月（而不是 `Date()`）：`onChange` 不会为首帧补发，初值必须自己对齐。
        _displayedMonth = State(initialValue: selectedDate.wrappedValue.startOfMonth)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard !symbols.isEmpty else { return symbols }

        let firstWeekdayIndex = max(0, min(symbols.count - 1, calendar.firstWeekday - 1))
        var ordered = Array(symbols[firstWeekdayIndex...])
        ordered.append(contentsOf: symbols[..<firstWeekdayIndex])
        return ordered
    }

    private var monthTitle: String {
        displayedMonth.formatted(.dateTime.month(.wide))
    }

    private var yearTitle: String {
        displayedMonth.formatted(.dateTime.year())
    }

    /// 当前显示月份里「有事件」的日期（日格标记的唯一判据）。
    ///
    /// 切片放在视图内（而不是调用方）是必需的：**显示月份由本视图自持**，翻月改的是 `displayedMonth`，
    /// 调用方事先算好一个月的集合翻月后就过期了。所以调用方传的是**按月快照**（月份 + 已过滤条目），
    /// 「哪几天有点」由纯函数 `MonthGridLayout.eventDays(forDisplayedMonth:snapshot:calendar:)` 在这里算
    /// ——快照月份与本视图显示月份不同月的这段时间（翻月后新数据还在路上）**不出点**，不会出错点。
    private var eventDays: Set<Date> {
        MonthGridLayout.eventDays(forDisplayedMonth: displayedMonth, snapshot: monthEvents, calendar: calendar)
    }

    var body: some View {
        GeometryReader { geometry in
            let pickerViewportHeight = max(96, geometry.size.height - 56)
            // 7 列日格的**单格宽**（与 `datePicker` 里的网格同一算式：两侧各 6pt 内边距 + 6 列 × 6pt
            // 列距，其余 7 等分）——第二行（农历 / 节假日）放不放得下按它判（`MonthCellSubtitle`）。
            let cellWidth = max(0, (geometry.size.width - 36) / 7)

            VStack(alignment: .leading, spacing: 10) {
                header
                datePicker(viewportHeight: pickerViewportHeight, cellWidth: cellWidth)
                    .frame(height: pickerViewportHeight)
                    .clipped()
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
        .clipped()
        // 显示月份一变（翻月 / 选中日换到别的月）就通知宿主去抓那个月的标记数据。
        // `.onChange` 不为首帧补发，所以出现时另发一次（首月同样要抓）。
        .onAppear {
            onDisplayedMonthChange?(displayedMonth)
        }
        .onChange(of: displayedMonth) { _, newMonth in
            onDisplayedMonthChange?(newMonth)
        }
        // 选中日一变（点日格 / 调用方换选中日）→ 显示月份跟到那一天所在月。
        .onChange(of: selectedDate) { _, newDate in
            withAnimation(.smooth(duration: 0.22)) {
                displayedMonth = newDate.startOfMonth
            }
        }
    }

    /// 月份标题 + ‹ › 翻月（原 `leftPickerPane` 的第一段，逐字抽出）。
    private var header: some View {
        HStack(alignment: .center) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(monthTitle)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Text(yearTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color(white: 0.65))
            }
            Spacer()
            HStack(spacing: 6) {
                Button(action: showPreviousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)

                Button(action: showNextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
        }
    }

    /// 星期表头 + 日格网格（原 `leftPickerPane` 的中下两段，逐字抽出）。
    ///
    /// `cellWidth` 只服务于日格第二行（农历 / 节假日）的**放不下就不画**判据：它由 `body` 按
    /// 「网格宽 → 7 等分」算好后传进来，视图内不另算一份（两处各算一次必然漂）。
    private func datePicker(viewportHeight: CGFloat, cellWidth: CGFloat) -> some View {
        ScrollViewReader { proxy in
            VStack(spacing: 6) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 14), spacing: 6), count: 7), spacing: 6) {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol.prefix(1))
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color(white: 0.55))
                            .frame(maxWidth: .infinity)
                    }
                }

                ZStack {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 14), spacing: 6), count: 7), spacing: 6) {
                            ForEach(MonthGridLayout.days(forMonth: displayedMonth, calendar: calendar), id: \.self) { day in
                                dayCell(for: day, cellWidth: cellWidth)
                                    .id(calendar.startOfDay(for: day))
                            }
                        }
                        .padding(.bottom, 2)
                    }
                    .onChange(of: scrollTarget) { _, target in
                        guard let target else { return }
                        centerDatePicker(on: target, proxy: proxy)
                    }

                    // 上下两条滚动提示渐变（`showsScrollFades`，见该属性的注释）：两个宿主现在都不传
                    // → 这里一条都不生成（不占位、不参与布局，网格几何因此与画时逐字相同）。
                    if showsScrollFades {
                        LinearGradient(colors: [Color.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 16)
                            .allowsHitTesting(false)
                            .frame(maxHeight: .infinity, alignment: .top)

                        LinearGradient(colors: [.clear, Color.black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 16)
                            .allowsHitTesting(false)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .frame(height: max(0, viewportHeight - 22))
                .clipped()
            }
            .frame(height: viewportHeight)
        }
        .frame(height: viewportHeight)
        .clipped()
    }

    /// 日格的**三个高度刻度**（T4 新增第二行后仍是这一份，别改成会撑高的写法）：
    /// 日格恒 30pt（`MonthGridLayout.monthGridHeight` 的行高算式 `36 × 周数 + 78` 依赖这个 30）、第一行（数字 +
    /// 选中圆）与第二行（农历 / 节假日）各自的高度——三者互相咬合：`19 + 11 == 30`。
    ///
    /// **为什么有两档选中圆**：30pt 的日格里塞下「圆 + 一行 9pt 文字」时，圆的最大直径是
    /// `30 − 11 = 19`——28pt 的圆（单行档的现状）与第二行在几何上必然重叠（圆的下弧会切进文字）。
    /// 单行档（格子放不下第二行时）继续用 28pt，两个档位各自的圆都**完整落在日格内**
    ///（不溢出、不被 ScrollView 裁掉顶边——这也是不采用「28pt 圆 + 溢出顶边」那条路的原因：
    /// 网格滚到顶时第一行的圆会被裁平）。
    private static let dayCellHeight: CGFloat = 30
    private static let singleLineSelectionDiameter: CGFloat = 28
    private static let twoLineSelectionDiameter: CGFloat = 19
    /// 第二行的行框高度：9pt 字（CJK 的 ink 约 8.8pt）放得下，且与选中圆加起来恰好 30。
    /// **显式定高**：PingFang（CJK fallback）的行高比 SF Pro 宽，交给它自然排版会撑破 30pt。
    private static let subtitleLineHeight: CGFloat = 11

    /// 这一天的**第二行**：有节假日名就显示它，否则农历日名（机制四）；放不下（或取不到）给 `nil`
    /// ——`nil` 时整行不画，公历数字的位置与高度因此与改前逐字一致（那段是 30pt 日格的全部）。
    ///
    /// 数据源 = 本视图的**按月快照**（`monthEvents`，与事件小圆点同一份，已按偏好过滤）：
    /// 节假日名走 `HolidayLookup`（名字含「节假日」的日历的全天条目），农历走 `LunarDayLabel`
    /// （Foundation 的中国农历）。两条都是纯函数，视图这一层只做「取哪个 + 放不放得下」。
    ///
    /// **已知的降级**：`hideAllDayEvents` 打开时全天条目不进快照，节假日名因此一并消失（那时网格
    /// 上连事件点都没有，口径一致——见批次报告 / docs/26 §已知限制）。
    private func subtitleText(for day: Date, cellWidth: CGFloat) -> String? {
        guard let label = HolidayLookup.name(for: day, events: monthEvents.events, calendar: calendar)
            ?? LunarDayLabel.label(for: day)
        else { return nil }
        return MonthCellSubtitle.fits(label, cellWidth: cellWidth) ? label : nil
    }

    /// 日格第二行的颜色：跟随公历数字的层级（跨月补格更暗），比数字低一档（次要色）。
    private func subtitleColor(isCurrentMonth: Bool) -> Color {
        isCurrentMonth ? Color(white: 0.65) : Color(white: 0.35)
    }

    private func dayCell(for day: Date, cellWidth: CGFloat) -> some View {
        let isCurrentMonth = calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)
        let hasEvents = eventDays.contains(calendar.startOfDay(for: day))
        let subtitle = subtitleText(for: day, cellWidth: cellWidth)
        let selectionDiameter = subtitle == nil
            ? Self.singleLineSelectionDiameter
            : Self.twoLineSelectionDiameter

        return Button {
            withAnimation(.smooth(duration: 0.18)) {
                selectedDate = day
            }
        } label: {
            VStack(spacing: 0) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.effectiveAccent)
                            .frame(width: selectionDiameter, height: selectionDiameter)
                    }

                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(dayTextColor(isCurrentMonth: isCurrentMonth, isSelected: isSelected, isToday: isToday))
                }

                // 第二行：公历数字**下方**（不挤数字、不换行）；放不下时 `subtitle` 为 nil、这里不生成。
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(subtitleColor(isCurrentMonth: isCurrentMonth))
                        .lineLimit(1)
                        .frame(height: Self.subtitleLineHeight)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Self.dayCellHeight)
            // 事件标记：右侧小圆点（位置与颜色见 `eventMarker` 的注释）。放在日格**右下角**而不是
            // 日号正下方，是为了和选中圆永不重叠；`overlay` 不进布局，日格仍恰好 30pt 高
            // （`MonthGridLayout.monthGridHeight` 的算式 `36 × 周数 + 78` 依赖这个 30，别改成会撑高的写法）。
            // T4 的第二行让日格下半部分多了文字：那颗点在**右下角内缩**（右 6pt / 下 2pt），
            // 与居中的第二行之间仍有 `MonthCellSubtitle` 判据里预留的那段横向余量（见该类型注释）。
            .overlay(alignment: .bottomTrailing) {
                if hasEvents {
                    eventMarker(isCurrentMonth: isCurrentMonth)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 「有事件」的小圆点：**4pt 实心圆，日格右下角内缩（右 6pt / 下 2pt）**。
    ///
    /// 两条都是刻意的选择（候选决策，见批次报告 `final-fix.md`）：
    /// - **位置取右下角**：日格只有 30pt 高，而选中高亮是**居中**的 28pt 实心圆（纵向占满 1…29pt），
    ///   日号正下方正是那个圆的底边——把点画在那里会和选中高亮糊成一团。右下角离圆心约 20pt，
    ///   今天高亮（日号变强调色，无圆圈）与选中高亮因此都能与它共存；它也不改日格高度，不影响
    ///   整月网格的行距算式。
    /// - **颜色取面板强调色**（`Color.effectiveAccent`，与今天的日号、选中的圆同一支），跨月补格降到
    ///   45% 不透明：补格的日号本来就是灰的（`Color(white: 0.35)`），标记跟着一起弱化，免得把视线
    ///   引到不属于当前显示月份的日子上。
    private func eventMarker(isCurrentMonth: Bool) -> some View {
        Circle()
            .fill(Color.effectiveAccent.opacity(isCurrentMonth ? 1 : 0.45))
            .frame(width: 4, height: 4)
            .padding(.trailing, 6)
            .padding(.bottom, 2)
    }

    private func dayTextColor(isCurrentMonth: Bool, isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .white }
        if !isCurrentMonth { return Color(white: 0.35) }
        if isToday { return Color.effectiveAccent }
        return .white
    }

    private func showPreviousMonth() {
        guard let newMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) else { return }
        withAnimation(.smooth(duration: 0.22)) {
            displayedMonth = newMonth.startOfMonth
            if monthNavigationMovesSelection {
                selectedDate = newMonth.startOfMonth
            }
        }
    }

    private func showNextMonth() {
        guard let newMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) else { return }
        withAnimation(.smooth(duration: 0.22)) {
            displayedMonth = newMonth.startOfMonth
            if monthNavigationMovesSelection {
                selectedDate = newMonth.startOfMonth
            }
        }
    }

    private func centerDatePicker(on target: Date, proxy: ScrollViewProxy) {
        let normalizedTarget = calendar.startOfDay(for: target)
        DispatchQueue.main.async {
            withAnimation(.smooth(duration: 0.24)) {
                proxy.scrollTo(normalizedTarget, anchor: .center)
            }
            if scrollTarget == normalizedTarget {
                scrollTarget = nil
            }
        }
    }
}

struct StandaloneCalendarView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var selectedDate = Date()
    @State private var datePickerScrollTarget: Date?
    @Default(.hideAllDayEvents) private var hideAllDayEvents
    @Default(.hideCompletedReminders) private var hideCompletedReminders

    /// 左栏**显示月份**（`MonthGridView` 自持，经 `onDisplayedMonthChange` 回声到这里）：只用于左栏高度
    /// ——网格高度算式与首页日历行**同源**（`MonthGridLayout.monthGridHeight`，`36N + 78`）。
    /// 初值与 `MonthGridView` 的初值同式（选中日所在月，见那边的 init）；出现时回调会再对齐一次。
    @State private var displayedMonth: Date = Date().startOfMonth

    /// 两栏之间的间距（旧 `body` 里的局部常量逐字搬上来：几何读数去掉后它得有个具名住处）。
    private static let paneSpacing: CGFloat = 12

    private let calendar = Calendar.current

    private var filteredEvents: [EventModel] {
        EventListView.filteredEvents(
            events: calendarManager.events,
            hideCompletedReminders: hideCompletedReminders,
            hideAllDayEvents: hideAllDayEvents
        )
    }

    /// 月历网格的**按月**数据源：`calendarManager.monthEvents`（该显示月份整张网格的窗口）经同一套
    /// 偏好过滤——与右栏清单的**按日** `filteredEvents` 是两条不同窗口的数据，别混用。
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

    /// 左栏（整月网格）的高度 = `36 × 显示月份周数 + 78`（与首页日历行同源，算式见
    /// `MonthGridLayout.monthGridHeight`）：这个高度下网格视口恰好一屏放下整月，网格内不滚动。
    /// 翻月改的是**显示月份**（`monthNavigationMovesSelection: true` 会连带挪选中日，两条都会经
    /// `onDisplayedMonthChange` 回声）→ 这一页的自然高随之变 → 探针重报，面板高跟着走
    /// （「面板高随月变化」是 docs/30 §做法 机制六 接受的行为）。
    private var monthGridHeight: CGFloat {
        MonthGridLayout.monthGridHeight(forMonth: displayedMonth, calendar: calendar)
    }

    var body: some View {
        // **自然高布局**（p6-ui-polish / T8，docs/30 §做法 机制六）：旧结构是
        // `GeometryReader` + `paneHeight = geometry.size.height` 的两栏定高 frame——探针按
        // 「宽给定、高 unspecified」量这一页时，`GeometryReader` 的理想高只有 10pt 级，整页自然高
        // 因此被答成 10、面板落到下限。现在两栏的高度都来自**内容**：左栏 = 月网格按固定格高自然堆叠的
        // 高（`36N + 78`，与首页日历行同源），右栏 = 同一个高度（事件列在它里面滚动 / 裁剪），
        // 这一页**不再读任何几何高度**（宽度也不读：两栏 `.frame(maxWidth: .infinity)` 等分，
        // 结果与旧的 `paneWidth = (width − 间距) / 2` 逐字相同）。
        HStack(alignment: .top, spacing: Self.paneSpacing) {
            // 左栏 = 抽取后的整月网格（`monthNavigationMovesSelection: true` 保留本视图的既有行为：
            // 翻月把选中日一并挪到新月份首日）。
            // 有事件的日期给日格画小圆点：传**按月**快照（`calendarManager.monthEvents` 过滤后的
            // 那一份，与右栏清单同一套偏好口径）——共用同一个 `MonthGridView` 时，两个宿主的标记
            // 口径也必须一致（首页日历行同样传）；显示月份变化时回调去抓那个月。
            MonthGridView(
                selectedDate: $selectedDate,
                scrollTarget: $datePickerScrollTarget,
                monthNavigationMovesSelection: true,
                monthEvents: monthEventSnapshot,
                onDisplayedMonthChange: { month in
                    // 左栏高度按**这个月份**算（见 `monthGridHeight`）；顺手抓该月的标记数据。
                    displayedMonth = month
                    Task { await calendarManager.updateMonthEvents(for: month) }
                },
                // **日历面板也不画网格上下的那两条滚动提示渐变**（2026-09-30 用户第 5 条
                // 「日历面板还存在两条线的遮罩」/ D-04）：首页日历行早就传了 `false`（上一批
                // D-01），这是第二处、也是最后一处。理由是两条在纯黑面板上只是脏线，而它们盖住的
                // 正是 T4 新加的那一行（农历 / 节假日）——网格可滚这件事由右侧清单的滚动与
                // 选中日居中自己表达。`MonthGridView` 的参数保留（默认 `true`，其余宿主 / 预览用）。
                showsScrollFades: false
            )
                // 左栏宽度 = 两栏等分（`.frame(maxWidth: .infinity)` 的结果与旧 `paneWidth` 同值）
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: monthGridHeight, alignment: .topLeading)
                .layoutPriority(1)

            rightEventsPane
                .frame(maxWidth: .infinity, alignment: .topLeading)
                // 右栏拿**同一个高度**：事件列表在它里面滚动 / 裁剪（它不参与「这一页要多高」，
                // 因此把它的大内容量进自然高是不可能的——旧结构正是靠 `paneHeight` 把它钉住的）。
                .frame(height: monthGridHeight, alignment: .topLeading)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .onAppear {
            // 显示月份由 `MonthGridView` 自持（随选中日同步），这里只在 `onDisplayedMonthChange` 的回声里
            // 读一份用于左栏高度；出现时钉选中日与滚动落点。
            selectedDate = Date.now
            requestDatePickerCenterOnCurrentDate()
            Task {
                await calendarManager.updateCurrentDate(selectedDate)
            }
        }
        .onChange(of: selectedDate) { _, newDate in
            Task {
                await calendarManager.updateCurrentDate(newDate)
            }
        }
        .onChange(of: vm.notchState) { _, newState in
            guard newState == .open else { return }
            selectedDate = Date.now
            requestDatePickerCenterOnCurrentDate()
            Task {
                await calendarManager.updateCurrentDate(selectedDate)
            }
        }
    }

    private var rightEventsPane: some View {
        Group {
            if filteredEvents.isEmpty {
                EmptyEventsView(selectedDate: selectedDate)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                StandaloneEventCardList(
                    events: filteredEvents,
                    selectedDate: selectedDate,
                    showFullEventTitles: Defaults[.showFullEventTitles],
                    onToggleReminder: { reminderID, completed in
                        Task {
                            await calendarManager.setReminderCompleted(reminderID: reminderID, completed: completed)
                        }
                    }
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func requestDatePickerCenterOnCurrentDate() {
        datePickerScrollTarget = calendar.startOfDay(for: selectedDate)
    }
}

struct EmptyEventsView: View {
    let selectedDate: Date

    var body: some View {
        VStack {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title)
                .foregroundColor(Color(white: 0.65))
            Text(Calendar.current.isDateInToday(selectedDate) ? "No events today" : "No events")
                .font(.subheadline)
                .foregroundColor(.white)
            Text("Enjoy your free time!")
                .font(.caption)
                .foregroundColor(Color(white: 0.65))
        }
    }
}

private extension Date {
    var startOfMonth: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self)) ?? self
    }
}

private struct StandaloneEventCardList: View {
    @Environment(\.openURL) private var openURL
    @Default(.autoScrollToNextEvent) private var autoScrollToNextEvent
    let events: [EventModel]
    let selectedDate: Date
    let showFullEventTitles: Bool
    let onToggleReminder: (String, Bool) -> Void
    @State private var initialAutoScrollDone = false

    private var allDayEvents: [EventModel] {
        partitionEvents(events).allDay.sorted { $0.start < $1.start }
    }

    private var timedEvents: [EventModel] {
        // Sorted by start time so `scrollTargetForTimedEvents` (which uses
        // `first(where:)` to pick in-progress / next-upcoming) returns the true
        // nearest-to-now event, and the list renders chronologically. (#566)
        partitionEvents(events).timed.sorted { $0.start < $1.start }
    }

    private func scrollToRelevantEvent(proxy: ScrollViewProxy) {
        guard autoScrollToNextEvent else { return }
        let refTime = scrollReferenceTime(for: selectedDate)
        guard let target = scrollTargetForTimedEvents(timed: timedEvents, referenceTime: refTime) else { return }

        // Use .center anchor for more reliable positioning with List's internal padding.
        // DispatchQueue.main.async ensures the scroll fires after List completes its initial layout,
        // avoiding the race condition where proxy.scrollTo fires before items are measured.
        let anchor: UnitPoint = .center
        DispatchQueue.main.async {
            withTransaction(Transaction(animation: nil)) {
                proxy.scrollTo(target.id, anchor: anchor)
            }
        }
    }

    var body: some View {
        // Timed-events list fills the whole panel; the all-day strip floats as
        // an overlay on top (zero vertical cost) so the scroll area below keeps
        // its full height inside the constrained calendar panel. The List
        // carries a top padding equal to the strip height so scrollTo(.top)
        // lands the target event fully below the overlay. Using `List` (instead
        // of the previous `LazyVStack`-in-`ScrollView`) keeps the scroll
        // behaviour and look consistent with `EventListView` and gives built-in
        // separators. (#566 review: unify the two event lists)
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ZStack {
                    List {
                        ForEach(timedEvents) { event in
                            eventCard(event)
                                .id(event.id)
                                .padding(.bottom, 8)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets())
                        }
                    }
                    .listStyle(.plain)
                    .scrollIndicators(.never)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    // Push list content down so scrollTo(.top) positions the
                    // target event fully below the floating all-day overlay.
                    .padding(.top, allDayEvents.isEmpty ? 0 : AllDayStripMetrics.listTopInset)
                }
                .onAppear {
                    scrollToRelevantEvent(proxy: proxy)
                    if !timedEvents.isEmpty {
                        initialAutoScrollDone = true
                    }
                }
                .onChange(of: selectedDate) { _, _ in
                    scrollToRelevantEvent(proxy: proxy)
                }
                .onChange(of: timedEvents.isEmpty) { wasEmpty, isEmpty in
                    // Retrigger the initial auto-scroll once, when timed events become
                    // available after the view appeared (e.g. async calendar load).
                    // Guarded so later data refreshes don't re-scroll. (#566 follow-up)
                    guard wasEmpty, !isEmpty, !initialAutoScrollDone else { return }
                    scrollToRelevantEvent(proxy: proxy)
                    initialAutoScrollDone = true
                }
                .onChange(of: events) { _, _ in
                    // Fallback: re-trigger auto-scroll when events are refreshed (e.g., calendar
                    // permission granted, calendars re-selected, or external calendar change).
                    // The initialAutoScrollDone guard prevents unwanted re-scrolling on minor updates.
                    if !initialAutoScrollDone {
                        scrollToRelevantEvent(proxy: proxy)
                    }
                }
            }

            // Floating all-day strip overlay (28pt chip row + 1pt divider ≈ 29pt).
            // It sits above the list and events scroll underneath it, like macOS
            // Calendar's Day view. Matches `EventListView`'s overlay exactly so
            // the reserved `listTopInset` (30) lines up with the real strip
            // height. No shadow gradient is drawn on top of the events anymore.
            if !allDayEvents.isEmpty {
                AllDayEventsStrip(
                    events: allDayEvents,
                    onToggleReminder: onToggleReminder
                )
                .background(Color.black.opacity(0.95))
            }
        }
        .clipped()
    }

    @ViewBuilder
    private func eventCard(_ event: EventModel) -> some View {
        if event.type.isReminder {
            Button {
                if let url = event.calendarAppURL() {
                    openURL(url)
                }
            } label: {
                reminderCard(event)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 2)
        } else {
            calendarEventCard(event)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let url = event.calendarAppURL() {
                        openURL(url)
                    }
                }
                .padding(.horizontal, 2)
        }
    }

    private func reminderCard(_ event: EventModel) -> some View {
        let isCompleted: Bool
        if case .reminder(let completed) = event.type {
            isCompleted = completed
        } else {
            isCompleted = false
        }

        return HStack(spacing: 10) {
            ReminderToggle(
                isOn: Binding(
                    get: { isCompleted },
                    set: { newValue in onToggleReminder(event.id, newValue) }
                ),
                color: Color(event.calendar.color)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(showFullEventTitles ? nil : 2)

                if event.isAllDay {
                    Text("All-day")
                        .font(.caption)
                        .foregroundColor(Color(white: 0.65))
                }
            }

            Spacer(minLength: 8)

            if !event.isAllDay {
                Text(event.start, style: .time)
                    .font(.caption)
                    .foregroundColor(Color(white: 0.75))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .opacity(isCompleted ? 0.55 : 1)
    }

    private func calendarEventCard(_ event: EventModel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(event.calendar.color))
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineLimit(showFullEventTitles ? nil : 2)

                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.65))
                        .lineLimit(1)
                }

                if let conferenceURL = event.conferenceURL {
                    ConferenceJoinButton(url: conferenceURL, event: event)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                if event.isAllDay {
                    Text("All-day")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                } else {
                    Text(event.start, style: .time)
                        .font(.caption)
                        .foregroundColor(.white)
                    Text(event.end, style: .time)
                        .font(.caption2)
                        .foregroundColor(Color(white: 0.65))
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .opacity(event.eventStatus == .ended && Calendar.current.isDateInToday(event.start) ? 0.6 : 1)
    }
}

// MARK: - 首页「今日」紧凑列表（2026-09-29 用户反馈改造）

/// 首页日历「今日」列表的**行容量**：给定可用高度与条目数 → 显示几行 + 溢出多少条。
///
/// **为什么要有它**（2026-09-29 用户反馈：「日历的今日内容不能只是一行，这种情况下还需要滑动，
/// 然后还有很大留白」）：原先今日内容里，全天条目走一条**横向滚动**的芯片行（只露一行、要左右滑），
/// 定时条目另走一个竖向 `List`，而整块被写死 120pt——条目一多只能横滑，条目少则是一块空白。
/// 改成「竖向紧凑多行 + 溢出提示」后，**行数必须由可用高度算准**：算不准就要么截断要么又留白，
/// 所以把这条算式抽成不读 `Defaults`、不碰 `Calendar` 的纯函数，直接单测（`ModuleKernelTests`）。
enum HomeTodayListLayout {
    /// 单行高度（`caption` 正文 + 行内余量）。行高与行距是容量的唯一刻度，视图里逐字使用这两个值。
    static let rowHeight: CGFloat = 19
    /// 行间距（与列表 `VStack(spacing:)` 取同一值，否则算出的高度与渲染高度会差一档）。
    static let rowSpacing: CGFloat = 4
    /// 条目行数上限：再多也不让日历块抢占面板高度（对齐参考里 Nook X 首页「日历压成小信息条」的做法）。
    static let maxItemRows: Int = 5
    /// 时间列宽度：`HH:mm` / `全天` 都要放得下，且各行的标题左边缘对齐。
    static let timeColumnWidth: CGFloat = 36
    /// 收起态日期头占用的高度（一行 `subheadline` + 顶部 2pt padding + 与列表之间的 4pt 间距）。
    static let collapsedHeaderHeight: CGFloat = 26

    /// 行容量：`visibleItemCount` 行内容，外加（若溢出）一行 `+N` 提示。
    struct Capacity: Equatable {
        /// 实际渲染的条目行数（**不含**溢出提示行）。
        let visibleItemCount: Int
        /// 未显示的条目数；0 表示全部放得下。
        let overflowCount: Int

        var showsOverflow: Bool { overflowCount > 0 }

        /// 列表内容高度（条目行 + 溢出提示行 + 行距）。块本身按内容收缩，所以这就是块内列表部分的高度。
        var contentHeight: CGFloat {
            let lines = visibleItemCount + (showsOverflow ? 1 : 0)
            guard lines > 0 else { return 0 }
            return CGFloat(lines) * HomeTodayListLayout.rowHeight
                + CGFloat(lines - 1) * HomeTodayListLayout.rowSpacing
        }
    }

    /// 给定可用高度与条目数，返回「显示几行 + 溢出多少条」。
    ///
    /// 口径（三条，都有用例钉住）：
    /// 1. `itemCount == 0` → 0 行 0 溢出（空态由 `EmptyEventsView` 负责，不占高度）；
    /// 2. 放得下（且不超过 `maxItemRows`）→ 全部显示、不溢出；
    /// 3. 放不下 / 超上限 → 让出一行额度给 `+N` 提示行，剩余条目计入溢出。
    ///
    /// - Parameters:
    ///   - availableHeight: 列表可用高度。两个调用方各自换算：`CalendarView`（**仅供 `#Preview`**，
    ///     运行期不可达；首页日历见 `HomeCalendarRow`）按
    ///     **面板高度**（`vm.notchSize` 减去刘海底座与内边距、再减去收起态日期头），
    ///     `HomeCalendarRow`（展开面板首页的全宽日历行）按**行高**（`rowHeight` 减去收起态日期头）。
    ///   - itemCount: 今日条目数（全天 + 定时合计，已过 `filteredEvents` 与排序）。
    static func capacity(availableHeight: CGFloat, itemCount: Int) -> Capacity {
        guard itemCount > 0 else { return Capacity(visibleItemCount: 0, overflowCount: 0) }
        guard availableHeight.isFinite else { return Capacity(visibleItemCount: 0, overflowCount: itemCount) }

        // 可用高度里最多能摆几行：最后一行不需要行距，故先补一个行距再取整。
        let pitch = rowHeight + rowSpacing
        let fittingLines = max(0, Int(floor((availableHeight + rowSpacing) / pitch)))
        guard fittingLines > 0 else { return Capacity(visibleItemCount: 0, overflowCount: itemCount) }

        if itemCount <= min(fittingLines, maxItemRows) {
            return Capacity(visibleItemCount: itemCount, overflowCount: 0)
        }
        // 需要「+N」提示行 → 条目行让出一行额度，且不超过行数上限。
        let visible = min(fittingLines - 1, maxItemRows)
        guard visible > 0 else { return Capacity(visibleItemCount: 0, overflowCount: itemCount) }
        return Capacity(visibleItemCount: visible, overflowCount: itemCount - visible)
    }
}

/// 首页日历的「今日」列表：**竖向紧凑多行，不横向滚动**（2026-09-29 用户反馈改造）。
///
/// 改造前：全天条目走 `AllDayEventsStrip` 那条**横向滚动**的芯片行（只露一行、要左右滑），
/// 定时条目另走一个竖向 `List`；当天条目全是全天时 `List` 是空的，于是「今日内容只有一行 +
/// 要在一条细条上左右滑 + 大片留白」三件事同时出现。
/// 改造后：全天与定时条目**合并成一条竖向列表**（全天在前、各自按开始时间排序），每行
/// 「时间 + 标题（单行尾部截断）」，行数由 `HomeTodayListLayout.capacity` 按可用高度算准
/// （条目行最多 5 行 + 必要时一行 `+N`）；高度算得准，因此列表**自身既不同横滚也不同竖滚**。
///
/// 说明：`AllDayEventsStrip` 仍服务于独立日历面板（`StandaloneEventCardList`），本视图已不再使用它。
struct EventListView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject private var calendarManager = CalendarManager.shared
    let events: [EventModel]
    let selectedDate: Date
    /// 列表可用高度——决定显示几行 + 是否溢出。由调用方各自换算：`CalendarView`（**仅供 `#Preview`**，
    /// 运行期不可达；首页日历见 `HomeCalendarRow`）
    /// 按**面板高度**（`vm.notchSize` 减去刘海底座与内边距、再减去收起态日期头），
    /// `HomeCalendarRow`（展开面板首页的全宽日历行）按**行高**（`rowHeight` 减去收起态日期头）。
    let availableHeight: CGFloat
    @Default(.hideCompletedReminders) private var hideCompletedReminders
    @Default(.hideAllDayEvents) private var hideAllDayEvents

    static func filteredEvents(
        events: [EventModel],
        hideCompletedReminders: Bool,
        hideAllDayEvents: Bool
    ) -> [EventModel] {
        events.filter { event in
            if event.type.isReminder {
                if case .reminder(let completed) = event.type {
                    return !completed || !hideCompletedReminders
                }
            }
            if event.isAllDay && hideAllDayEvents {
                return false
            }
            return true
        }
    }

    private var filteredEvents: [EventModel] {
        Self.filteredEvents(
            events: events,
            hideCompletedReminders: hideCompletedReminders,
            hideAllDayEvents: hideAllDayEvents
        )
    }

    /// 展示顺序：全天在前、再定时，各自按开始时间升序——与独立面板「顶部芯片条 + 下方时间线」
    /// 同序，只是这里合成一条竖向列表（时间列里全天显示「全天」，定时显示 `HH:mm`）。
    private var orderedEvents: [EventModel] {
        let partitioned = partitionEvents(filteredEvents)
        return partitioned.allDay.sorted { $0.start < $1.start }
            + partitioned.timed.sorted { $0.start < $1.start }
    }

    private var capacity: HomeTodayListLayout.Capacity {
        HomeTodayListLayout.capacity(
            availableHeight: availableHeight,
            itemCount: orderedEvents.count
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HomeTodayListLayout.rowSpacing) {
            ForEach(Array(orderedEvents.prefix(capacity.visibleItemCount))) { event in
                row(for: event)
            }

            if capacity.showsOverflow {
                overflowRow(hiddenCount: capacity.overflowCount)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 一行 = 时间 + 标题。**文字一律显式浅色**（`.white` / `.white.opacity(...)`）：
    /// 本项目在浅色系统外观下踩过 `.primary` / `.secondary` 变黑的坑，这里不使用环境色。
    private func row(for event: EventModel) -> some View {
        let isDimmed = self.isDimmed(event)
        return HStack(spacing: 8) {
            timeLabel(for: event, isDimmed: isDimmed)
                .frame(width: HomeTodayListLayout.timeColumnWidth, alignment: .leading)

            Text(event.title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(isDimmed ? 0.5 : 1))
                .lineLimit(1)
                .truncationMode(.tail)

            // 行内**横向** `Spacer`：只把行尾的提醒勾选圈推到右边，不参与纵向分摊
            // （2026-09-29：面板里不允许再用会把内容摊开的纵向 `Spacer`）。
            Spacer(minLength: 0)

            if event.type.isReminder {
                reminderToggle(for: event)
            }
        }
        .padding(.horizontal, 2)
        .frame(height: HomeTodayListLayout.rowHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            openInCalendar(event)
        }
    }

    /// 时间列：有具体时间的显示 `HH:mm`，全天项显示「全天」（`All-day` 已有 19 个语言的译文）。
    @ViewBuilder
    private func timeLabel(for event: EventModel, isDimmed: Bool) -> some View {
        let color = Color.white.opacity(isDimmed ? 0.5 : 0.7)
        if event.isAllDay {
            Text("All-day")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(color)
                .lineLimit(1)
        } else {
            Text(verbatim: Self.clockLabel(for: event.start))
                .font(.caption2)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundColor(color)
                .lineLimit(1)
        }
    }

    /// 溢出提示行 `+N`（N = 没显示的条目数）。
    ///
    /// 用 `Text(verbatim:)` 而不是 `Text("+\(n)")`：后者会被当成带 `%lld` 的本地化 key，
    /// 在 19 个语言的 string catalog 里凭空多出一条待翻译条目（2026-09-29：本改动不新增文案 key）。
    private func overflowRow(hiddenCount: Int) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: "+\(hiddenCount)")
                .font(.caption2)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.55))
                .frame(width: HomeTodayListLayout.timeColumnWidth, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .frame(height: HomeTodayListLayout.rowHeight)
    }

    /// 已完成提醒 / 已结束（过期）的日程整行降到 `.white.opacity(0.5)`。
    private func isDimmed(_ event: EventModel) -> Bool {
        if case .reminder(let completed) = event.type, completed {
            return true
        }
        return event.eventStatus == .ended
    }

    /// `HH:mm`（固定 24 小时制）：`Text(_, style: .time)` 与 `DateFormatter` 的默认样式都跟随
    /// 系统 locale，会变成 `12:10 PM` 这类 12 小时制 + AM/PM，紧凑行放不下。
    /// 走 `Calendar` 取时分再补零：纯函数、无 locale 依赖，也便于单测。
    static func clockLabel(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private func openInCalendar(_ event: EventModel) {
        if let url = event.calendarAppURL() {
            openURL(url)
        }
    }

    /// 提醒的勾选圈（保留首页可勾选完成的能力；勾选写回系统提醒，与独立面板同一条链路）。
    private func reminderToggle(for event: EventModel) -> some View {
        let isCompleted: Bool
        if case .reminder(let completed) = event.type {
            isCompleted = completed
        } else {
            isCompleted = false
        }

        return ReminderToggle(
            isOn: Binding(
                get: { isCompleted },
                set: { newValue in
                    Task {
                        await calendarManager.setReminderCompleted(
                            reminderID: event.id, completed: newValue
                        )
                    }
                }
            ),
            color: Color(event.calendar.color)
        )
    }
}

struct ReminderToggle: View {
    @Binding var isOn: Bool
    var color: Color

    var body: some View {
        Button(action: {
            isOn.toggle()
        }) {
            ZStack {
                Circle()
                    .strokeBorder(color, lineWidth: 2)
                    .frame(width: 14, height: 14)
                if isOn {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Circle()
                    .fill(Color.black.opacity(0.001))
                    .frame(width: 14, height: 14)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .padding(0)
        .accessibilityLabel(isOn ? "Mark as incomplete" : "Mark as complete")
    }
}

// MARK: - Conference Provider

enum ConferenceProvider: CaseIterable {
    case zoom, teams, meet, webex, facetime, gotomeeting, bluejeans, whereby, jitsi, discord, generic
    
    var name: String {
        switch self {
        case .zoom: return "Zoom"
        case .teams: return "Teams"
        case .meet: return "Meet"
        case .webex: return "Webex"
        case .facetime: return "FaceTime"
        case .gotomeeting: return "GoToMeeting"
        case .bluejeans: return "BlueJeans"
        case .whereby: return "Whereby"
        case .jitsi: return "Jitsi"
        case .discord: return "Discord"
        case .generic: return ""
        }
    }
    
    var color: Color {
        switch self {
        case .zoom: return Color(red: 0.16, green: 0.52, blue: 0.95)
        case .teams: return Color(red: 0.36, green: 0.42, blue: 0.89)
        case .meet: return Color(red: 0.0, green: 0.65, blue: 0.42)
        case .webex: return Color(red: 0.0, green: 0.71, blue: 0.84)
        case .facetime: return Color(red: 0.2, green: 0.78, blue: 0.35)
        case .gotomeeting: return Color(red: 0.95, green: 0.5, blue: 0.13)
        case .bluejeans: return Color(red: 0.0, green: 0.48, blue: 0.87)
        case .whereby: return Color(red: 0.27, green: 0.51, blue: 0.96)
        case .jitsi: return Color(red: 0.16, green: 0.68, blue: 0.95)
        case .discord: return Color(red: 0.35, green: 0.39, blue: 0.98)
        case .generic: return Color.accentColor
        }
    }
    
    private var hostIdentifiers: [String] {
        switch self {
        case .zoom: return ["zoom.us"]
        case .teams: return ["teams.microsoft.com"]
        case .meet: return ["meet.google.com"]
        case .webex: return ["webex.com"]
        case .facetime: return ["facetime.apple.com"]
        case .gotomeeting: return ["gotomeeting.com"]
        case .bluejeans: return ["bluejeans.com"]
        case .whereby: return ["whereby.com"]
        case .jitsi: return ["meet.jit.si", "jitsi"]
        case .discord: return ["discord.gg", "discord.com"]
        case .generic: return []
        }
    }
    
    var nativeURLScheme: String? {
        switch self {
        case .zoom: return "zoommtg"
        case .teams: return "msteams"
        case .facetime: return "facetime"
        case .discord: return "discord"
        default: return nil
        }
    }

    static func detect(from url: URL) -> ConferenceProvider {
        let host = url.host?.lowercased() ?? ""
        return allCases.first { provider in
            provider.hostIdentifiers.contains { host.contains($0) }
        } ?? .generic
    }
}

// MARK: - Conference Join Button

struct ConferenceJoinButton: View {
    let url: URL
    let event: EventModel
    @Environment(\.openURL) private var openURL
    
    private var provider: ConferenceProvider { .detect(from: url) }
    private var isJoinable: Bool {
        event.start.addingTimeInterval(-15 * 60) <= Date()
    }
    
    private var buttonText: String {
        event.eventStatus == .inProgress ? "Rejoin" : "Join"
    }
    
    var body: some View {
        Button(action: {
            if let scheme = provider.nativeURLScheme,
               var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                components.scheme = scheme
                if let nativeURL = components.url {
                    openURL(nativeURL)
                    return
                }
            }
            openURL(url)
        }) {
            HStack(spacing: 4) {
                Image(systemName: "video.fill")
                    .font(.system(size: 9))
                Text(provider.name.isEmpty ? buttonText : "\(buttonText) \(provider.name)")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundColor(isJoinable ? .white : Color(white: 0.5))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isJoinable ? provider.color.opacity(0.85) : Color.gray.opacity(0.3))
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isJoinable)
        .help(isJoinable ? "Join the meeting" : "Meeting starts at \(event.start.formatted(date: .omitted, time: .shortened))")
    }
}

#Preview {
    CalendarView()
        .frame(width: 250)
        .padding(.horizontal)
        .background(.black)
        .environmentObject(DynamicIslandViewModel.init())
}
