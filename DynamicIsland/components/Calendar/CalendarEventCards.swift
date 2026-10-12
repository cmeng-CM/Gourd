// Modified for Gourd (2026-10-10)
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
//  CalendarEventCards.swift
//  Gourd 日历 · 两处日历共用的条目卡片（P11 批次 / T1）
//
//  **为什么抽**：首页整宽日历行的右栏与展开面板「日历」页右栏渲染的是同一份 `EventModel` 数据，
//  却各有一套条目视图。本文件把面板页的两张卡（日程 / 待办）**逐字**从
//  `DynamicIslandCalendar.swift` 的 `StandaloneEventCardList` 私有 builder 搬出来成为独立组件，
//  让两处宿主只决定「列表容器」，卡片本体只有一份实现。T1 只做**抽取**：面板页接入后渲染与
//  改动前逐像素同形、零行为变化；T2 起首页行右栏换成同款卡片列（列容器 `CalendarEventCardList`
//  也在本文件，仅首页列所用）。
//
//  **两处宿主**：
//  - 面板「日历」页右栏 —— `StandaloneEventCardList`（`DynamicIslandCalendar.swift`，T1 接入）：
//    全天芯片条 + 可滚动 `List`（本文件只提供卡片本体）；
//  - 首页整宽日历行的右栏 —— `CalendarEventCardList`（`HomeCalendarRow.swift`，T2 接入）：
//    竖向滚动卡片列（容器与卡片都在本文件，全天条目合并进同一列）。
//
//  **形态口径（逐字不变，T1 审查的 10 个视觉参数；2026-10-12 只有「行高」两档随日历页放大，
//  见下一条）**：字体 `.callout` / 权重 `.medium`（待办）与
//  `.semibold`（日程）；`padding(.horizontal, 11)` / `padding(.vertical, 8)`；`minHeight 50`；
//  圆角 14（`.continuous`）+ `Color.white.opacity(0.05)` 底；弱化档 0.55（勾选完成的待办）/ 0.6
//  （今天已结束的日程）；标题 `lineLimit(showFullEventTitles ? nil : 2)`；地点 `lineLimit(1)`；
//  日程收尾时间右列（起 `.caption` 白 / 止 `.caption2` 白色 0.8 不透明；全天显示 `All-day`）；色条 4×36。
//  **2026-10-12 p18**：卡片的次要文字（地点 / 止时间 / 全天行）从固定中灰（0.65 / 0.75）改为
//  白系不透明度常量（`MonthGridLayout.cardSecondaryOpacity` / `cardSecondaryStrongOpacity`）——
//  固定中灰在浅色 / 中间调玻璃（`.liquidGlass` / `.frostedGlass` + 浅色系统外观）上对比度归零，
//  与日历页星期行同一根因（见 `MonthGridLayout` 的「次要文字的不透明度」一节）。
//  勾选圈左置（待办）、`ConferenceJoinButton` 在正文列内（日程）——位置都不许动。
//
//  **2026-10-12：右栏行高随面板「日历」页等比放大**（docs/41-home-and-calendar-scale.md D-03 / D-04）：
//  本文件里由 `MonthGridLayout.scale` 派生的只有两处**行高**——列容器的 `headerHeight`（26 → 31.2，
//  **取整 31**）与两张卡片的 `minHeight`（50 → 60，让出的高度正好补上左栏 `monthGridHeight` 长高的
//  那一截，两栏拿同一个高度）。两档都**取整到整点**（`(原值 × scale).rounded()`，2026-10-12 T2fix2）：
//  整条链（左栏日格 / 行距 / chrome / 行高 + 右栏表头 / 卡片）都是整点，AppKit 逐层落地不再逐档
//  向下取整累加误差（左栏网格底贴行底的结构护栏依赖这一点）。卡片的文字用的是**语义字号**（`.callout` / `.caption` / `.caption2`）而不是
//  数值字号，随动态字体走，因此**不随 `scale` 变**（要变只能写死数值字号，那会丢掉动态字体）；
//  `padding` / 圆角 / 色条 4×36 同样不在本次放大范围（卡片结构一个字没动）。
//
//  口径：docs/36-calendar-cards-and-add.md §接口与数据形状（`CalendarEventCard(event:showFullEventTitles:)`、
//  `ReminderCard(event:showFullEventTitles:onToggle:)`、
//  `CalendarEventCardList(events:showFullEventTitles:details:)` 与它的 `ordered(_:)` 纯函数）。
//  **P11 / T7 增补**：本文件同时承载**两处共用的过滤口径** `CalendarEventFilters.filtered(events:hideCompletedReminders:hideAllDayEvents:)`
//  （旧紧凑行的过滤函数迁址，函数体逐字未动）——「列组件 + 过滤口径」是配套的一对。
//  **签名（P11 / T3；T8b 归位）**：`CalendarEventCardList` 的 `details: CalendarEventDetailsModel`（详情浮层
//  接线用）——本列是**唯一**给浮层上报锚点与悬停 / 点击的组件，浮层本体与模型在 `CalendarEventDetail.swift`；
//  `selectedDate` 参数（组件不消费）T8b 已删，实现与 docs/36 §接口与数据形状 对齐。
//
//  说明：本文件只含**纯展示**卡片——点击 / 悬停 / 打开系统 App 等宿主交互仍由宿主包装层负责
//  （面板侧见 `StandaloneEventCardList.eventCard(_:)`；首页侧 T3 起由本文件的 `CalendarEventCardList`
//  接详情浮层：卡片包 `CalendarEventHoverTarget` + `anchorPreference` 上报锚点，点击 `togglePin`）。
//  `ReminderToggle` / `ConferenceJoinButton` 留在 `DynamicIslandCalendar.swift`（同模块可见），
//  不随本次抽取搬迁。
//

import Defaults
import SwiftUI

/// 日程卡片（原 `StandaloneEventCardList.calendarEventCard(_:)` 逐字搬家）。
///
/// 结构：左色条（4×36）→ 正文列（标题 / 地点 / Join 按钮）→ `Spacer` → 收尾时间右列。
/// 弱化档：今天且已结束（`eventStatus == .ended && isDateInToday(start)`）降为 0.6。
struct CalendarEventCard: View {
    let event: EventModel
    /// 标题是否不限行（开「显示完整事件标题」时为 `true`，否则 2 行截断）。
    let showFullEventTitles: Bool

    var body: some View {
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
                        // p18：改前固定中灰 `Color(white: 0.65)`——浅色 / 中间调玻璃上卡片会整片看不清。
                        .foregroundColor(.white.opacity(MonthGridLayout.cardSecondaryOpacity))
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
                        .foregroundColor(.white.opacity(MonthGridLayout.cardSecondaryOpacity))
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        // 卡片最小行高（原 50 → 60）：右栏行高随 `MonthGridLayout.scale` 放大（docs/41 D-03），
        // 取整到整点（T2fix2），卡片跟着长高，一屏的行数与左栏日格的对位才不会走样。
        .frame(maxWidth: .infinity, minHeight: (50 * MonthGridLayout.scale).rounded(), alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .opacity(event.eventStatus == .ended && Calendar.current.isDateInToday(event.start) ? 0.6 : 1)
    }
}

/// 待办卡片（原 `StandaloneEventCardList.reminderCard(_:)` 逐字搬家；勾选圈左置）。
///
/// 结构：左勾选圈（`ReminderToggle`）→ 正文列（标题 / 全天行）→ `Spacer` → 开始时间。
/// 弱化档：已完成降为 0.55。勾选写回由宿主经 `onToggle` 提供
/// （面板侧走 `CalendarManager.setReminderCompleted`）。
struct ReminderCard: View {
    let event: EventModel
    /// 标题是否不限行（开「显示完整事件标题」时为 `true`，否则 2 行截断）。
    let showFullEventTitles: Bool
    /// 勾选圈写回：`true` = 标记完成、`false` = 标记未完成。
    let onToggle: (Bool) -> Void

    /// 完成态判定（原 builder 内的 `isCompleted` 局部量原样搬入）。
    private var isCompleted: Bool {
        if case .reminder(let completed) = event.type {
            return completed
        }
        return false
    }

    var body: some View {
        HStack(spacing: 10) {
            ReminderToggle(
                isOn: Binding(
                    get: { isCompleted },
                    set: { newValue in onToggle(newValue) }
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
                        .foregroundColor(.white.opacity(MonthGridLayout.cardSecondaryOpacity))
                }
            }

            Spacer(minLength: 8)

            if !event.isAllDay {
                Text(event.start, style: .time)
                    .font(.caption)
                    .foregroundColor(.white.opacity(MonthGridLayout.cardSecondaryStrongOpacity))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        // 卡片最小行高（原 50 → 60）：与 `CalendarEventCard` 同一条口径，随 `MonthGridLayout.scale` 放大并取整。
        .frame(maxWidth: .infinity, minHeight: (50 * MonthGridLayout.scale).rounded(), alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .opacity(isCompleted ? 0.55 : 1)
    }
}

/// 两处日历共用的**过滤口径**（P11 / T7）：原旧紧凑行的 `filteredEvents` 静态函数**逐字搬家**为本枚举。
///
/// 剔除「已完成的提醒」（`hideCompletedReminders`）与被偏好隐藏的「全天条目」（`hideAllDayEvents`）；
/// 两个偏好由调用方从 `Defaults` 读出后传入（本枚举**不读 `Defaults`**，仍是纯函数，可直接单测）。
///
/// **为什么独立成枚举**：旧紧凑行退休后这条口径仍是两处共用——首页卡片列在组件内过滤
/// （`CalendarEventCardList.orderedEvents`）、独立日历面板右栏与月历标记快照在宿主侧过滤
/// （`StandaloneCalendarView` / `HomeCalendarRow` 的 `filteredEvents` / `monthEventSnapshot`）。
enum CalendarEventFilters {
    static func filtered(
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
}

/// 首页整宽日历行右栏的**可滚动卡片列**（P11 / T2；docs/36 §接口与数据形状 / D-13）。
///
/// **为什么是滚动列**：卡片高度随标题行数（「显示完整事件标题」开着时更多行）与地点有无而变
/// （约 50–66pt），定高容量算式（旧紧凑列表的行容量档，本批已退休）算不准——要么裁掉
/// 内容、要么白留一档，因此条目多于栏高时**栏内滚动**：不做 `+N`、不做容量算式、不分「全天
/// 芯片条」（全天条目合并进本列，收尾时间列显 `All-day`）。
///
/// **过滤口径**：`events` 收的是**未过滤**的原始条目（首页宿主传 `calendarManager.events`），
/// 组件自己读 `hideCompletedReminders` / `hideAllDayEvents` 两个偏好走 `CalendarEventFilters.filtered`
/// （口径逐字沿用旧紧凑行的 `filteredEvents` 计算属性，T7 起迁为本文件顶部的独立枚举），
/// 再交给 `ordered`。宿主不预先过滤（组件与宿主空态判据因此同源）。
///
/// **排序口径**：`ordered` 纯函数——`partitionEvents` 后全天在前、各自按 `start` 升序
/// （口径逐字沿用旧紧凑行的 `orderedEvents`；与面板「芯片条 + 时间线」同序）。
///
/// **高度口径**：本组件**自身不设高度**（不读行高、不读可用高度）——视口高度由宿主钉
/// （`HomeCalendarRow` 给 `rowHeight − headerHeight`）；条目多则栏内滚动、少则自然高。
/// 表头（收起态日期头）的占用高度由本组件的 `headerHeight` 常量提供（原旧紧凑列表的
/// `collapsedHeaderHeight` 原值迁入，见下方）。
///
/// **交互口径（P11 / T3 起）**：提醒卡片的勾选写回走 `CalendarManager.shared.setReminderCompleted`
/// （与旧紧凑行的勾选圈同链路）；每张卡片包一层 `CalendarEventHoverTarget`
/// （悬停约 0.3s 报给 `details`）+ `anchorPreference` 上报锚点（宿主据此画详情浮层）+
/// 点击 `details.togglePin(event.id)`（**点击从「打开系统 App」改为「钉住详情」**，D-09——打开按钮
/// 移进浮层的 `CalendarEventDetailCard`）。提醒卡的勾选圈是 `Button`、自身吞点击，因此点勾选圈
/// 不会落到本层的 `onTapGesture`（不误触钉住）。
///
/// 说明：本列**不新增滚动 / 收起手势抑制逻辑**——首页宿主 `HomeCalendarRow` 既有
/// `.onHover { vm.isHoveringCalendar }` 已覆盖本行，`ContentView` 的面板收起滚动判据是
/// `!vm.isHoveringCalendar`，本列滚动因此安全（docs/36 执行期裁决）。
struct CalendarEventCardList: View {
    /// 宿主表头（收起态日期头那一行）占用的高度（P11 / T7 从已退休的旧紧凑列表行容量档原值 26
    /// 迁入）：一行 `subheadline` + 顶部 2pt padding + 与列表之间的 4pt 间距。
    ///
    /// **2026-10-12 起随面板「日历」页整体等比放大**（docs/41-home-and-calendar-scale.md D-03 / D-04）：
    /// 右栏与本页左栏（`MonthGridLayout.monthGridHeight`）拿的是同一个高度，行高不跟着走就会
    /// 「卡片列溢出到行外」或「行内留白」——所以它引左栏那一个 `scale` 常量，不再自己写数
    /// （唯一取值处仍是这里）。两处宿主共用这一个数——`CalendarView`（**仅供 `#Preview`**）的
    /// 视口换算也引它。**取整到整点**（26 × 1.2 = 31.2 → **31**，T2fix2）：与左栏同一批量化口径，
    /// 右栏视口 = `monthGridHeight − headerHeight` 也是整点（278 − 31 = 247）。
    static let headerHeight: CGFloat = (26 * MonthGridLayout.scale).rounded()

    @ObservedObject private var calendarManager = CalendarManager.shared
    /// **未过滤**的原始条目（首页宿主传 `calendarManager.events`）；偏好过滤在组件内做。
    let events: [EventModel]
    /// 标题是否不限行（宿主读 `Defaults[.showFullEventTitles]` 后传入，与面板同源）。
    let showFullEventTitles: Bool
    /// 详情浮层状态（P11 / T3；宿主一份）：卡片把 `event.id` 的悬停 / 点击写给它，
    /// 浮层本体由宿主的 `.calendarEventDetails(model:)` 画（本组件只上报锚点、不画浮层）。
    @ObservedObject var details: CalendarEventDetailsModel
    @Default(.hideCompletedReminders) private var hideCompletedReminders
    @Default(.hideAllDayEvents) private var hideAllDayEvents

    /// 展示顺序（纯函数）：全天在前、再定时，各自按开始时间升序——口径逐字沿用旧紧凑行的
    /// `orderedEvents`（`partitionEvents` 分组后两次 `sorted`）。
    static func ordered(_ events: [EventModel]) -> [EventModel] {
        let partitioned = partitionEvents(events)
        return partitioned.allDay.sorted { $0.start < $1.start }
            + partitioned.timed.sorted { $0.start < $1.start }
    }

    /// 过滤（组件内，读偏好）→ 排序（纯函数）。**渲染全部条目**，不再有 `prefix(capacity)`。
    private var orderedEvents: [EventModel] {
        Self.ordered(
            CalendarEventFilters.filtered(
                events: events,
                hideCompletedReminders: hideCompletedReminders,
                hideAllDayEvents: hideAllDayEvents
            )
        )
    }

    var body: some View {
        ScrollView(.vertical) {
            // 卡片间距 8pt（与面板 `List` 行的 `padding(.bottom, 8)` 同一条口径）。
            VStack(alignment: .leading, spacing: 8) {
                ForEach(orderedEvents) { event in
                    card(for: event)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 无滚动条（与面板 `StandaloneEventCardList` 的 `.scrollIndicators(.never)` 同口径）。
        .scrollIndicators(.never)
    }

    /// 日程 → `CalendarEventCard`；提醒 → `ReminderCard`（勾选走既有写回链路）。
    ///
    /// 外面统一包一层宿主交互（P11 / T3）：`CalendarEventHoverTarget`（悬停 0.3s → `details.hover`）
    /// + `anchorPreference`（把本卡的 bounds 按 id 上报给宿主的详情浮层）
    /// + `contentShape(Rectangle())`（整块卡片（含色条与空隙）都可悬停 / 可点）
    /// + `onTapGesture`（点击 → `details.togglePin`，同卡再点取消、点其它卡转移）。
    private func card(for event: EventModel) -> some View {
        CalendarEventHoverTarget(id: event.id, model: details) {
            cardBody(for: event)
        }
        .anchorPreference(key: CalendarEventAnchorKey.self, value: .bounds) { [event.id: $0] }
        .contentShape(Rectangle())
        .onTapGesture {
            details.togglePin(event.id)
        }
        // 辅助功能语义（T8b）：整块可点（点击 = 钉住详情），补 Button 语义——不加视觉、不加文案键
        // （屏幕朗读仍读卡片内容，读者由此知道「这是可点开的条目」）。
        .accessibilityAddTraits(.isButton)
    }

    /// 卡片本体分派（纯展示，不含宿主交互；交互见上面的 `card(for:)`）。
    @ViewBuilder
    private func cardBody(for event: EventModel) -> some View {
        if event.type.isReminder {
            ReminderCard(
                event: event,
                showFullEventTitles: showFullEventTitles,
                onToggle: { completed in
                    Task {
                        await calendarManager.setReminderCompleted(
                            reminderID: event.id, completed: completed
                        )
                    }
                }
            )
        } else {
            CalendarEventCard(event: event, showFullEventTitles: showFullEventTitles)
        }
    }
}
