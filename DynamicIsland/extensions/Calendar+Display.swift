// Modified for Gourd (2026-10-09)
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
//  Calendar+Display.swift
//  Gourd 宿主 · 显示日历（面板日历的周起点唯一落点）（p9 批次 / T1）
//
//  两个日历面板（首页整宽日历行 + 展开面板日历页）的**周起点固定周一**：唯一落点是下面这枚
//  `Calendar.gourdDisplay`（`Calendar.current` + `firstWeekday = 2`）。视图持有的日历与
//  「按月取数窗口」都从它取数——消费点改的是各自的 **default 值**，不是调用点
//  （「跟随」这件事只写一遍；`MonthGridLayout` 的签名一字不动）。
//
//  规格：docs/34-calendar-week-and-panel-icons.md §做法 机制一。
//

import Foundation

extension Calendar {
    /// 面板日历唯一的**显示日历**：在 `Calendar.current` 上把周起点钉成**周一**。
    ///
    /// `firstWeekday` 是 Foundation 的 1-based 口径：`1 = 周日`、`2 = 周一`……（本机 zh_CN 的
    /// `Calendar.current.firstWeekday` 是 1，照抄系统等于照抄出用户 2026-10-09 要求改掉的那个结果，
    /// 见 docs/34 §备选与取舍 · 周起点·1）——产品口径因此不跟随区域设置，固定周一（D-01 / D-02）。
    ///
    /// **唯一落点**（docs/34 §做法 机制一）：`MonthGridLayout` 一族纯函数与
    /// `HomeCalendarRow.rowHeight(forMonth:calendar:)` 的 `calendar:` 默认值、
    /// `MonthGridView` / `StandaloneCalendarView` 持有的日历、`CalendarManager.updateMonthEvents`
    /// 的按月取数窗口（走 `monthWindow` 的默认值）全部指向它。要换周起点，只改这里一处。
    static var gourdDisplay: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        return calendar
    }
}
