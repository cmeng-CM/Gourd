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
//  让两处宿主只决定「列表容器」，卡片本体只有一份实现。本批 T1 只做**抽取**：面板页接入后
//  渲染与改动前逐像素同形、零行为变化（T2 起首页行右栏才换成同款卡片列）。
//
//  **两处宿主**：
//  - 面板「日历」页右栏 —— `StandaloneEventCardList`（`DynamicIslandCalendar.swift`，本批 T1 接入）；
//  - 首页整宽日历行的右栏 —— `CalendarEventCardList`（`HomeCalendarRow.swift`，本批 T2 接入）。
//
//  **形态口径（逐字不变，T1 审查的 10 个视觉参数）**：字体 `.callout` / 权重 `.medium`（待办）与
//  `.semibold`（日程）；`padding(.horizontal, 11)` / `padding(.vertical, 8)`；`minHeight 50`；
//  圆角 14（`.continuous`）+ `Color.white.opacity(0.05)` 底；弱化档 0.55（勾选完成的待办）/ 0.6
//  （今天已结束的日程）；标题 `lineLimit(showFullEventTitles ? nil : 2)`；地点 `lineLimit(1)`；
//  日程收尾时间右列（起 `.caption` 白 / 止 `.caption2` 0.65 灰；全天显示 `All-day`）；色条 4×36。
//  勾选圈左置（待办）、`ConferenceJoinButton` 在正文列内（日程）——位置都不许动。
//
//  口径：docs/36-calendar-cards-and-add.md §接口与数据形状（`CalendarEventCard(event:showFullEventTitles:)`、
//  `ReminderCard(event:showFullEventTitles:onToggle:)`）。
//
//  说明：本文件只含**纯展示**卡片——点击 / 悬停 / 打开系统 App 等宿主交互仍由宿主包装层负责
//  （面板侧见 `StandaloneEventCardList.eventCard(_:)`）。`ReminderToggle` / `ConferenceJoinButton`
//  留在 `DynamicIslandCalendar.swift`（同模块可见），不随本次抽取搬迁。
//

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
}
