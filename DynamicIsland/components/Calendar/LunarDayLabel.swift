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
//  LunarDayLabel.swift
//  Gourd 日历 · 农历日名 / 节假日名 / 日格第二行的取舍（P3 组件批次 / T4）
//
//  用户 2026-09-30 第 5 条：「首页的日历和日历面板的日历取系统的日历数据，包含：公历，农历，节假日等数据」。
//  公历是现状（`MonthGridLayout.days(forMonth:)`）；本文件补的是**另外两样**，以及它们在日格里的**取舍**：
//
//  - `LunarDayLabel`：**Foundation 自带的中国农历**（`Calendar(identifier: .chinese)`，零依赖、零权限）
//    ——初一显示月名（「八月初一」），其余显示日名（「初二」…「廿九」「三十」）；
//  - `HolidayLookup`：从**已加载的事件**里挑名字含「节假日」的日历（用户订阅了「中国大陆节假日」
//    就自动有）的**全天**事件标题；取不到就是 `nil`（**降级**：日格只显示农历，不报错、不弹窗、
//    不新增 TCC 权限——数据来自 `CalendarManager` 已经抓到手里的那批事件）；
//  - `MonthCellSubtitle`：9pt 那一行**放不放得下**的判据（放不下就整行不画，绝不挤压公历数字）。
//
//  **为什么全是纯函数**：三件事都只有几条边界（初一 / 十五 / 月末 / 闰月 / 普通日；命中 / 无 /
//  多个候选；放得下 / 放不下），值得穷举；写在视图里就只能上屏肉眼看。三条都不读 `Defaults`、
//  不碰单例、不碰「今天」——日期与日历**一律由调用方传入**（`calendar` 参数有缺省，测试可换固定时区），
//  因此用例在任意机器上结论一致（`DynamicIslandTests/LunarTests.swift`）。
//
//  口径：docs/26-home-widgets-and-settings.md §做法 机制四 / D-05（公历 + 农历 + 节假日，取不到就降级）。
//

import AppKit
import Foundation

// MARK: - 农历日名

/// 中国农历的**日名 / 月名**（纯函数，可单测）。
///
/// 命名口径（`label(for:calendar:)` 的返回值）：
/// - **初一显示月名**：`"八月" + "初一"` = **「八月初一」**（闰月带「闰」前缀：**「闰六月初一」**）
///   ——只用日名的话，初一与「月名」这两条信息在格子里都占不下，用户要的正是「这个月从哪天起」；
/// - 其余显示日名：**初二 … 初十、十一 … 十九、二十、廿一 … 廿九、三十**（十进制的「二十」
///   不写成「廿」，与「廿一」区分开——这是农历日名的既有写法，不是本文件发明的）。
///
/// 月名表（农历月序 → 汉字）：**正月 / 二月 / … / 十月 / 冬月 / 腊月**——十一月、十二月取
/// 「冬月」「腊月」这两个农历里的通行叫法（`Calendar` 不提供月名，只能自己排）。
///
/// 返回值是 `String?`：`date` 落在 `calendar` 算不出的区间（极少数，`dateComponents` 返回 nil）时给 `nil`，
/// 调用方按「这一行不画」处理（与放不下同一条出口）。
enum LunarDayLabel {
    /// 农历日名：`date` 在这一天的农历日名；初一额外带月名（闰月带「闰」）。
    ///
    /// - Parameters:
    ///   - date: 任意时刻（判定只看它落在哪一天，与时分秒无关）。
    ///   - calendar: 农历历法。缺省 `Calendar(identifier: .chinese)`（时区取当前时区，
    ///     与视图里那些 `startOfDay` 同一个时区口径）；用例传固定时区的一份。
    static func label(for date: Date, calendar: Calendar = Calendar(identifier: .chinese)) -> String? {
        let components = calendar.dateComponents([.month, .day, .isLeapMonth], from: date)
        guard let day = components.day, let dayName = dayName(for: day) else { return nil }

        // 寻常日子：只有日名（格子里 9pt 一行也放得下）。
        guard day == 1 else { return dayName }

        // 初一：月名 + 初一（月名取不出来时退回「初一」，总比空着好——这一段不可达，防御而已）。
        guard let month = components.month, let monthName = monthName(for: month) else { return dayName }
        let leapPrefix = (components.isLeapMonth ?? false) ? "闰" : ""
        return leapPrefix + monthName + dayName
    }

    /// 农历月序（1 = 正月 … 12 = 腊月）→ 月名。表外（`Calendar` 理论上只给 1…12）返回 `nil`。
    static func monthName(for month: Int) -> String? {
        guard monthNames.indices.contains(month - 1) else { return nil }
        return monthNames[month - 1]
    }

    /// 农历日（1…30）→ 日名。表外（理论上只给 1…30）返回 `nil`。
    static func dayName(for day: Int) -> String? {
        switch day {
        case 1...9: return "初" + digit(day)
        case 10: return "初十"
        case 11...19: return "十" + digit(day - 10)
        case 20: return "二十"
        case 21...29: return "廿" + digit(day - 20)
        case 30: return "三十"
        default: return nil
        }
    }

    /// 「正月 … 腊月」（下标 = 月序 − 1，`monthName(for:)` 的唯一来源）。
    static let monthNames = [
        "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月",
    ]

    /// 汉字数码（1…9）：日名的三个分支共用一份，不写三张表。
    private static func digit(_ value: Int) -> String {
        let digits = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
        guard digits.indices.contains(value - 1) else { return "" }
        return digits[value - 1]
    }
}

// MARK: - 节假日名

/// 「节假日」这个名字从**系统日历**里捡出来（纯函数，可单测）。
///
/// 数据源口径（D-05 / 机制四）：**不自算中国节假日**（调休规则每年变、要维护数据），而是取用户在
/// 系统日历里**订阅**的那一份——「中国大陆节假日」这类订阅日历在 EventKit 里就是一个普通日历，
/// 判定只有一条：**日历名里含「节假日」**。名字取的是 `EventModel.calendar.title`（`CalendarManager`
/// 已经随事件带进来了），因此**不新增任何 TCC 权限**：看得见的是已经授权范围内的那批事件。
///
/// 降级（明确不做的一侧）：取不到（没订阅 / 该日没有条目 / 名字不含「节假日」）一律返回 `nil`，
/// 日格只显示农历——不报错、不提示、不引导订阅（引导写在用户手册里，见 §已知限制 1）。
enum HolidayLookup {
    /// 「节假日」日历的判定：日历名里含这三个字（**唯一一处**口径，两个公开函数共用）。
    static func isHolidayCalendar(titled title: String) -> Bool {
        title.contains("节假日")
    }

    /// 从日历清单里挑「节假日」那一份。多个候选时按 **(名字, id)** 定序取首个——确定性：
    /// 同一天的显示结果不随 `allCalendars` 的顺序漂（`CalendarManager` 的顺序是 EventKit 给的，
    /// 不该成为界面的一部分）。没有候选返回 `nil`。
    static func holidayCalendar(in calendars: [CalendarModel]) -> CalendarModel? {
        calendars
            .filter { isHolidayCalendar(titled: $0.title) }
            .min { lhs, rhs in (lhs.title, lhs.id) < (rhs.title, rhs.id) }
    }

    /// `date` 这一天的节假日名：取**该日覆盖到的、名字含「节假日」的日历的、全天**条目的标题。
    ///
    /// 三条判据与理由：
    /// 1. **全天**（`event.isAllDay`）：订阅日历里节假日就是全天事件；定时事件不是节假日标记；
    /// 2. **覆盖整天**：与 `MonthGridLayout.daysWithEvents` 同一条区间口径——全天事件在 EventKit 里
    ///    `end` 是**次日零点的排他值**（9/29 全天 = 9/29 00:00 → 9/30 00:00），因此判据取
    ///    `[起日, (结束时刻 − 1s) 所在日]`，否则会把次日也标成节假日；
    /// 3. **多个候选取第一个**：同一份订阅里除节假日名外还有「休」/「班」这类单字调休标记，
    ///    按 **(标题长, 标题, 开始时刻)** 定序——长名优先（「国庆节」胜过「休」），
    ///    同长再按名字与开始时刻兜底，结论因此与事件顺序无关。
    ///
    /// 空标题（订阅数据里偶尔有空白条目）直接跳过——画一行空白比不画更糟。
    static func name(for date: Date, events: [EventModel], calendar: Calendar = .current) -> String? {
        let day = calendar.startOfDay(for: date)
        let candidates = events.compactMap { event -> (title: String, start: Date)? in
            guard event.isAllDay,
                  !event.type.isReminder,
                  isHolidayCalendar(titled: event.calendar.title),
                  covers(day: day, event: event, calendar: calendar)
            else { return nil }

            let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return (title, event.start)
        }

        return candidates.min { lhs, rhs in
            if lhs.title.count != rhs.title.count { return lhs.title.count > rhs.title.count }
            if lhs.title != rhs.title { return lhs.title < rhs.title }
            return lhs.start < rhs.start
        }?.title
    }

    /// 事件是否覆盖 `day`（`day` 已是零点）：口径与 `MonthGridLayout.daysWithEvents` 一致（见上）。
    private static func covers(day: Date, event: EventModel, calendar: Calendar) -> Bool {
        let first = calendar.startOfDay(for: event.start)
        // 结束时刻不晚于起始时刻（零长 / 数据异常）时退化为「只覆盖起始日」，不产生空区间。
        let last = max(first, calendar.startOfDay(for: event.end.addingTimeInterval(-1)))
        return day >= first && day <= last
    }
}

// MARK: - 日格第二行的取舍

/// 日格第二行（农历 / 节假日）**放不放得下**的判据（纯函数，可单测）。
///
/// 用户要的是「格子里有农历」，但格子是 7 列网格按宽度摊出来的：面板调窄后一格可能只有 18pt。
/// 那时唯一正确的做法是**整行不画**——挤压公历数字（换行 / 缩小 / 裁切）比少一行更糟
/// （批次失败信号之一：「农历行挤压公历数字导致换行/裁切」）。
///
/// **判据是三条余量相加**（都写在这里，视图不另算）：
/// 1. `textWidth`：那一行文案用 **9pt 系统字体实测的宽度**（`NSString.size(withAttributes:)`，
///    与格子里那行 `Text` 同一个字号与字体解析路径）；不写死「几个字」——「八月初一」（4 字）
///    与「国庆节」（3 字）宽度不同，而节假日名是**用户订阅的数据**，长度不由我们定；
/// 2. `slack`：抗锯齿 / 字体 fallback 的误差余量（不该让最后半个字被切掉）；
/// 3. `trailingMarkerZone`：**右下角那颗事件点**的横向占用（`MonthGridView.eventMarker`：
///    右内缩 6 + 点宽 4 = 10pt）。第二行是**居中**的，它的右端因此落在
///    `(cellWidth + textWidth) / 2`，要让开 `[cellWidth − 10, cellWidth − 6]` 这一段就是
///    `(cellWidth + textWidth) / 2 ≤ cellWidth − 10`，即 **`cellWidth ≥ textWidth + 20`**
///    （居中让开一侧，等价于两侧各让 10——所以这里减的是两个 `trailingMarkerZone`）。
enum MonthCellSubtitle {
    /// 这一行在 `cellWidth` 宽的日格里放得下吗。
    ///
    /// - Parameters:
    ///   - label: 要显示的那一行文案（节假日名或农历日名）。
    ///   - cellWidth: 日格可用宽度（`MonthGridView` 按 7 列网格摊出来的那份）。
    ///   - fontSize: 与视图里 `Text` 的字号同一个数（缺省 9，见 §做法 机制四）。
    /// - Returns: 放得下为 `true`；`cellWidth` 取不到（0 / 负数 / 非有限数）或文案为空为 `false`。
    static func fits(_ label: String, cellWidth: CGFloat, fontSize: CGFloat = 9) -> Bool {
        guard !label.isEmpty, cellWidth.isFinite, cellWidth > 0 else { return false }
        let textWidth = (label as NSString)
            .size(withAttributes: [.font: NSFont.systemFont(ofSize: fontSize)])
            .width
        return cellWidth >= textWidth + slack + trailingMarkerZone * 2
    }

    /// 右下角事件点的横向占用（右内缩 6 + 点宽 4）：居中的第二行要左右各让开它（见类型注释 3）。
    static let trailingMarkerZone: CGFloat = 10

    /// 判定余量（pt）：抗锯齿与字体 fallback 的误差不该让最后半个字被切掉。
    /// 4 字农历名实测 35.79pt，于是判据在 57.79pt 以上才放行——默认档（首页日历行 ≈78pt、
    /// 日历面板 ≈70pt）都在放行侧，窄面板的格子（≈18–50pt）如实退化为「只显示公历数字」。
    static let slack: CGFloat = 2
}
