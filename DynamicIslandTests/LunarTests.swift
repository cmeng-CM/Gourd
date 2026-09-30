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
//  LunarTests.swift
//  Gourd 日历 · 农历 / 节假日 / 日格第二行的取舍（P3 组件批次 / T4）
//
//  覆盖 docs/26-home-widgets-and-settings.md §做法 机制四 / D-05 与 §验收标准 1 点名的五组 + 三组：
//
//  **`LunarDayLabel`（农历，五组）**
//  - 初一显示月名（「八月初一」「正月初一」「九月初一」）；
//  - 十五、月末（「八月廿九」「九月三十」）、闰月（「闰六月初一」「闰六月初八」——同一个月里
//    非初一的日子不带月名，但月名表里第六章要能算出「闰）」；
//  - 普通日（「八月二十」）与**日名/月名表本身**（初二 … 初十、十一、二十、廿一、廿九、三十；
//    正月 … 腊月；表外的 0 / 31 / 13 一律 `nil`）。
//
//  **`HolidayLookup`（节假日，三组）**
//  - 命中：名字含「节假日」的日历里的**全天**条目当天给出标题；
//  - 无：没有这种日历（或只有定时条目）→ `nil`（降级：日格只显示农历，不报错）；
//  - 多个候选：同一天多条（「国庆节」与「休」）取**更长**的标题、两份节假日日历取
//    **(名字, id)** 最小的一份——输入顺序打乱后结论不变（确定性）。
//
//  **`MonthCellSubtitle`（放不下就不画）**：窄格子（12pt）一律不画；默认档（≈70pt / ≈78pt）放得下
//  4 字农历名；右侧事件点的横向占用（居中文字左右各让 10pt）也在判据里。
//
//  夹具是**本文件私有**的最小构造器：固定时区（北京时间）让农历结论与机器时区无关。
//

import XCTest

@testable import Gourd

@MainActor
final class LunarTests: XCTestCase {

    // MARK: - 夹具

    /// 固定时区：农历按**当地零点**换日，钉住时区后本文件的结论在任何机器上都一样。
    private static let beijing = TimeZone(identifier: "Asia/Shanghai")!

    private func gregorian() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.beijing
        return calendar
    }

    /// 农历历法（与 `LunarDayLabel.label` 的缺省同一类，只换了时区）。
    private func chinese() -> Calendar {
        var calendar = Calendar(identifier: .chinese)
        calendar.timeZone = Self.beijing
        return calendar
    }

    /// 公历某日的**当地正午**（避开零点附近的换日边界；判定只看落在哪一天，时分秒无意义）。
    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        gregorian().date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// 一条**全天**事件（节假日日历的典型形态）：`start` 取当天零点，`end` = 次日的零点
    /// （EventKit 的**排他**口径——这正是 `HolidayLookup.covers` 里那个 `−1s` 要处理的形态）。
    private func allDayEvent(
        title: String,
        calendarTitle: String,
        on start: Date,
        spanDays: Int = 1,
        calendarID: String = "calendar.holiday"
    ) -> EventModel {
        let startOfDay = gregorian().startOfDay(for: start)
        let end = gregorian().date(byAdding: .day, value: spanDays, to: startOfDay)!
        return event(
            title: title,
            calendarTitle: calendarTitle,
            calendarID: calendarID,
            start: startOfDay,
            end: end,
            isAllDay: true
        )
    }

    /// 一条**定时**事件（`isAllDay == false`）：节假日判据必须把它排除（节假日标记都是全天的）。
    private func timedEvent(title: String, calendarTitle: String, on start: Date) -> EventModel {
        let startOfHour = gregorian().date(
            from: DateComponents(year: gregorian().component(.year, from: start),
                                 month: gregorian().component(.month, from: start),
                                 day: gregorian().component(.day, from: start),
                                 hour: 9)
        )!
        return event(
            title: title,
            calendarTitle: calendarTitle,
            calendarID: "calendar.holiday",
            start: startOfHour,
            end: startOfHour.addingTimeInterval(3600),
            isAllDay: false
        )
    }

    private func event(
        title: String,
        calendarTitle: String,
        calendarID: String,
        start: Date,
        end: Date,
        isAllDay: Bool
    ) -> EventModel {
        EventModel(
            id: "\(calendarID)#\(title)#\(start.timeIntervalSince1970)",
            start: start,
            end: end,
            title: title,
            location: nil,
            notes: nil,
            url: nil,
            isAllDay: isAllDay,
            type: .event(.accepted),
            calendar: CalendarModel(
                accountName: "Test",
                id: calendarID,
                title: calendarTitle,
                color: .systemBlue,
                isSubscribed: true,
                isReminder: false
            ),
            participants: [],
            timeZone: Self.beijing,
            hasRecurrenceRules: false,
            priority: nil,
            conferenceURL: nil
        )
    }

    private func calendarModel(title: String, id: String) -> CalendarModel {
        CalendarModel(
            accountName: "Test",
            id: id,
            title: title,
            color: .systemBlue,
            isSubscribed: true,
            isReminder: false
        )
    }

    // MARK: - 农历：初一

    /// **初一显示月名**（机制四的原话「初一显示月名（如「八月初一」）」）：三个不同月序都走一遍
    /// （八月、正月、九月——月名表的前中后三段），并钉住「闰年不影响非闰月的月名」。
    func testLunarLabelOfFirstDayCarriesMonthName() {
        XCTAssertEqual(LunarDayLabel.label(for: day(2026, 9, 11), calendar: chinese()), "八月初一")
        XCTAssertEqual(LunarDayLabel.label(for: day(2026, 10, 10), calendar: chinese()), "九月初一")
        XCTAssertEqual(
            LunarDayLabel.label(for: day(2026, 2, 17), calendar: chinese()), "正月初一",
            "2026 年春节（正月初一）"
        )
    }

    /// 同一段里的对照：**初一前后一天**都只有日名（月名只在初一出现，日格那一行因此不会天天变长）。
    func testLunarLabelOfNeighboursOfFirstDayCarryNoMonthName() {
        XCTAssertEqual(LunarDayLabel.label(for: day(2026, 9, 10), calendar: chinese()), "廿九")
        XCTAssertEqual(LunarDayLabel.label(for: day(2026, 9, 12), calendar: chinese()), "初二")
    }

    // MARK: - 农历：十五

    /// 十五（中秋当天）：只显示日名，不带月名。
    func testLunarLabelOfFifteenth() {
        XCTAssertEqual(LunarDayLabel.label(for: day(2026, 9, 25), calendar: chinese()), "十五")
    }

    // MARK: - 农历：月末

    /// **月末**：廿九（小月）与三十（大月）都覆盖——月末是「日名表的上界」，也是 `label` 里
    /// `dayName(for:)` 最后一个分支（三十）与倒数第二个分支（廿九）的边界。
    ///
    /// 注意月末**不带月名**（月名只出现在初一，见机制四「初一显示月名，其余显示日名」）——
    /// 2026 年八月是小月（廿九收尾）、九月是大月（三十收尾）。
    func testLunarLabelOfMonthEnd() {
        XCTAssertEqual(LunarDayLabel.label(for: day(2026, 10, 9), calendar: chinese()), "廿九")
        XCTAssertEqual(LunarDayLabel.label(for: day(2026, 11, 8), calendar: chinese()), "三十")
    }

    // MARK: - 农历：闰月

    /// **闰月**：闰月的初一在月名前带「闰」——与正六月的初一形成对照（同为初一，
    /// 一个是「六月初一」、一个是「闰六月初一」，这正是用户要的「这个月从哪天起」）。
    ///
    /// 同一条口径的另一半也钉在这里：**闰月里非初一的日子只显示日名**（「初八」）——
    /// 9pt 一行放不下「闰六月」+ 日名两段，月名只留给初一（机制四的取舍）。
    func testLunarLabelOfLeapMonth() {
        XCTAssertEqual(LunarDayLabel.label(for: day(2025, 6, 25), calendar: chinese()), "六月初一", "正六月的初一")
        XCTAssertEqual(LunarDayLabel.label(for: day(2025, 7, 25), calendar: chinese()), "闰六月初一", "闰六月的初一")
        XCTAssertEqual(
            LunarDayLabel.label(for: day(2025, 7, 24), calendar: chinese()), "三十",
            "闰月前一天是正六月的月末（不带月名）"
        )
        XCTAssertEqual(LunarDayLabel.label(for: day(2025, 8, 1), calendar: chinese()), "初八", "闰月里的普通日")
        XCTAssertEqual(LunarDayLabel.label(for: day(2025, 8, 22), calendar: chinese()), "廿九")
    }

    // MARK: - 农历：普通日与两张表

    /// **普通日**：只给日名（「二十」——月名只出现在初一）。
    func testLunarLabelOfOrdinaryDay() {
        XCTAssertEqual(LunarDayLabel.label(for: day(2026, 9, 30), calendar: chinese()), "二十")
    }

    /// **日名表**逐档：初三 / 初十（一与十的进位）、十一 / 十九（十位段）、二十（不进「廿」）、
    /// 廿一 / 廿九（廿段）、三十（上界）；表外（0 / 31 / −1）给 `nil`。
    func testDayNameTable() {
        XCTAssertEqual(LunarDayLabel.dayName(for: 2), "初二")
        XCTAssertEqual(LunarDayLabel.dayName(for: 10), "初十")
        XCTAssertEqual(LunarDayLabel.dayName(for: 11), "十一")
        XCTAssertEqual(LunarDayLabel.dayName(for: 19), "十九")
        XCTAssertEqual(LunarDayLabel.dayName(for: 20), "二十")
        XCTAssertEqual(LunarDayLabel.dayName(for: 21), "廿一")
        XCTAssertEqual(LunarDayLabel.dayName(for: 29), "廿九")
        XCTAssertEqual(LunarDayLabel.dayName(for: 30), "三十")

        for invalid in [0, 31, -1] {
            XCTAssertNil(LunarDayLabel.dayName(for: invalid), "表外的日用 \(invalid) 试探")
        }
    }

    /// **月名表**：1 = 正月 … 12 = 腊月（十一月 / 十二月取农历通行叫法）；表外给 `nil`。
    func testMonthNameTable() {
        XCTAssertEqual(LunarDayLabel.monthName(for: 1), "正月")
        XCTAssertEqual(LunarDayLabel.monthName(for: 8), "八月")
        XCTAssertEqual(LunarDayLabel.monthName(for: 11), "冬月")
        XCTAssertEqual(LunarDayLabel.monthName(for: 12), "腊月")
        XCTAssertEqual(LunarDayLabel.monthNames.count, 12, "十二个月一个不多一个不少")

        for invalid in [0, 13, -1] {
            XCTAssertNil(LunarDayLabel.monthName(for: invalid), "表外的月用 \(invalid) 试探")
        }
    }

    // MARK: - 节假日：命中

    /// **命中**：名字含「节假日」的日历里的全天条目 → 当天给出标题；前一天（不在覆盖区间）不出名。
    /// 同时钉住 `holidayCalendar(in:)` 能从那批日历里认出它。
    func testHolidayNameHitsSubscribedHolidayCalendar() {
        let nationalDay = day(2026, 10, 1)
        let events = [
            allDayEvent(title: "国庆节", calendarTitle: "中国大陆节假日", on: nationalDay)
        ]

        XCTAssertEqual(
            HolidayLookup.name(for: nationalDay, events: events, calendar: gregorian()),
            "国庆节"
        )
        XCTAssertNil(
            HolidayLookup.name(for: day(2026, 9, 30), events: events, calendar: gregorian()),
            "前一天不在覆盖区间里"
        )

        let picked = HolidayLookup.holidayCalendar(in: [
            calendarModel(title: "工作日历", id: "calendar.work"),
            calendarModel(title: "中国大陆节假日", id: "calendar.holiday"),
        ])
        XCTAssertEqual(picked?.id, "calendar.holiday")
        XCTAssertNil(
            HolidayLookup.holidayCalendar(in: [calendarModel(title: "工作日历", id: "calendar.work")]),
            "没有候选时给 nil（降级）"
        )
    }

    /// 全天事件的覆盖区间按 **`end − 1s` 所在日**结算（EventKit 的 `end` 是次日零点的排他值）：
    /// 跨 3 天的假期在前三天都有名、第四天没有。
    func testHolidayNameCoversEveryDayOfAMultiDayAllDayEvent() {
        let events = [
            allDayEvent(title: "国庆节", calendarTitle: "中国大陆节假日", on: day(2026, 10, 1), spanDays: 3)
        ]
        for offset in 0..<3 {
            let target = gregorian().date(byAdding: .day, value: offset, to: day(2026, 10, 1))!
            XCTAssertEqual(
                HolidayLookup.name(for: target, events: events, calendar: gregorian()),
                "国庆节",
                "第 \(offset + 1) 天应在覆盖区间内"
            )
        }
        XCTAssertNil(
            HolidayLookup.name(for: day(2026, 10, 4), events: events, calendar: gregorian()),
            "区间结束的次日不在覆盖里（-1s 口径）"
        )
    }

    // MARK: - 节假日：无（降级）

    /// **无**：① 没有名字含「节假日」的日历；② 有节假日日历但只有**定时**条目（节假日标记都是全天的）；
    /// ③ 事件列表为空——三种都不崩、都给 `nil`（日格退回只显示农历）。
    func testHolidayNameIsNilWithoutHolidayCalendarOrAllDayEntries() {
        let target = day(2026, 10, 1)

        XCTAssertNil(
            HolidayLookup.name(
                for: target,
                events: [allDayEvent(title: "团建", calendarTitle: "工作日历", on: target)],
                calendar: gregorian()
            ),
            "日历名不含「节假日」"
        )
        XCTAssertNil(
            HolidayLookup.name(
                for: target,
                events: [timedEvent(title: "国庆节", calendarTitle: "中国大陆节假日", on: target)],
                calendar: gregorian()
            ),
            "定时条目不是节假日标记"
        )
        XCTAssertNil(
            HolidayLookup.name(for: target, events: [], calendar: gregorian()),
            "一条事件都没有"
        )
        XCTAssertFalse(HolidayLookup.isHolidayCalendar(titled: "工作"), "判定字符串里没有「节假日」")
        XCTAssertTrue(HolidayLookup.isHolidayCalendar(titled: "中国大陆节假日"))
    }

    /// 空标题 / 只有空白的条目不算节假日名（画一行空白比不画更糟）。
    func testHolidayNameSkipsBlankTitles() {
        let target = day(2026, 10, 1)
        XCTAssertNil(
            HolidayLookup.name(
                for: target,
                events: [allDayEvent(title: "  ", calendarTitle: "中国大陆节假日", on: target)],
                calendar: gregorian()
            )
        )
    }

    // MARK: - 节假日：多个候选

    /// **多个候选**（同一天）：订阅日历里除节假日名外还有「休」/「班」这类单字调休标记——取**更长**
    /// 的标题（「国庆节」胜过「休」），且**与输入顺序无关**。
    func testHolidayNamePrefersTheLongerTitleAmongCandidates() {
        let target = day(2026, 10, 1)
        let holiday = allDayEvent(title: "国庆节", calendarTitle: "中国大陆节假日", on: target)
        let restMarker = allDayEvent(title: "休", calendarTitle: "中国大陆节假日", on: target)

        let forward = HolidayLookup.name(for: target, events: [holiday, restMarker], calendar: gregorian())
        let reversed = HolidayLookup.name(for: target, events: [restMarker, holiday], calendar: gregorian())
        XCTAssertEqual(forward, "国庆节")
        XCTAssertEqual(reversed, forward, "结论不随事件顺序漂")
    }

    /// **多个候选**（两份节假日日历）：`holidayCalendar(in:)` 按 **(名字, id)** 定序取首个——
    /// 两种输入顺序都给同一份。
    func testHolidayCalendarPicksDeterministicallyAmongCandidates() {
        let a = calendarModel(title: "节假日A", id: "calendar.a")
        let b = calendarModel(title: "节假日B", id: "calendar.b")

        XCTAssertEqual(HolidayLookup.holidayCalendar(in: [a, b])?.id, "calendar.a")
        XCTAssertEqual(HolidayLookup.holidayCalendar(in: [b, a])?.id, "calendar.a", "顺序无关")
    }

    // MARK: - 日格第二行：放不下就不画

    /// **判据是「格子宽度 ≥ 文字实测宽 + 余量 + 右侧事件点让位」**：
    /// - 窄格子（12pt）一律不画（0 / 负值 / NaN 同样不画）；
    /// - 默认档的两处真实格子宽（首页日历行 ≈78pt、日历面板 ≈70pt）放得下 4 字农历名；
    /// - 50pt 这一档**不画**（4 字名 35.79 + 2 + 20 = 57.79 > 50——这正是「事件点在右下角，
    ///   居中的第二行要左右各让 10pt」那条余量的含义）；
    /// - 放行之后**再宽一点仍然放行**（宽度单调）。
    func testSubtitleFitUsesCellWidthAndMarkerZone() {
        XCTAssertFalse(MonthCellSubtitle.fits("八月初一", cellWidth: 12), "窄格子不画")
        XCTAssertFalse(MonthCellSubtitle.fits("八月初一", cellWidth: 50), "要让开右下角那颗事件点")
        XCTAssertTrue(MonthCellSubtitle.fits("八月初一", cellWidth: 70), "日历面板默认档")
        XCTAssertTrue(MonthCellSubtitle.fits("八月初一", cellWidth: 78), "首页日历行默认档")

        XCTAssertFalse(MonthCellSubtitle.fits("", cellWidth: 200), "空文案不画")
        XCTAssertFalse(MonthCellSubtitle.fits("八月", cellWidth: 0))
        XCTAssertFalse(MonthCellSubtitle.fits("八月", cellWidth: -10))
        XCTAssertFalse(MonthCellSubtitle.fits("八月", cellWidth: .nan))

        let narrow = MonthCellSubtitle.fits("国庆节", cellWidth: 40)
        let wide = MonthCellSubtitle.fits("国庆节", cellWidth: 60)
        XCTAssertFalse(narrow, "40pt 放不下 3 字节假日名（要让开事件点）")
        XCTAssertTrue(wide, "60pt 放得下")
    }

    /// 判据的**单调性**（纯函数的性质型断言）：同一个文案在更宽的格子里不会反而变得放不下。
    func testSubtitleFitIsMonotonicInWidth() {
        for label in ["初三", "八月二十", "八月初一", "国庆节"] {
            for width in stride(from: CGFloat(10), through: 200, by: 2) {
                if MonthCellSubtitle.fits(label, cellWidth: width) {
                    XCTAssertTrue(
                        MonthCellSubtitle.fits(label, cellWidth: width + 4),
                        "\(label) 在 \(width + 4)pt 上不该反而放不下"
                    )
                }
            }
        }
    }
}
