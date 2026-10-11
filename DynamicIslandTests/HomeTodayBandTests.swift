// Modified for Gourd (2026-10-11)
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
//  HomeTodayBandTests.swift
//  Gourd 单测 · 首页**今天带**的纯函数（p13-home-v5 / docs/38-home-v5-layout.md §做法 三）
//
//  今天带是宿主直渲的一条「排版」带（不是模块），它的四段文案各有一个纯函数出口：
//  `TodayHeadline`（公历 + 农历 + 节假日名）、`TodayNextEvent`（下一个 / 进行中 + 倒计时）、
//  `WorkdayRemainderLine`（本月 / 本季 / 今年剩余工作日）、`LunarDateLabel`（农历中文专名）。
//  本文件把它们的口径逐条钉住——视图只组装，判据都在这里。
//
//  **夹具用固定日历 / 固定时区**（不读本机时区与语言）：`TodayHeadline` 的公历与星期走
//  `Date.FormatStyle`（随语言），因此那部分只断「含什么」，比字面量更稳的是农历 / 节假日 /
//  倒计时这三段的字面量断言（它们不分语言，见 docs/38 口径 ①）。
//

import EventKit
import XCTest

@testable import Gourd

@MainActor
final class HomeTodayBandTests: XCTestCase {

    /// 固定日历：格里高利 + GMT + `en_US_POSIX`（构造夹具时刻的时区与语言都钉死，同文件其余日历用例同口径）。
    private func fixtureCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }

    /// 夹具时刻（2026 年某月某日某时某分，日历固定）。
    private func time(
        _ calendar: Calendar,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0,
        second: Int = 0
    ) -> Date {
        calendar.date(
            from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second)
        )!
    }

    /// 一条定时日程（`title` 当 id，取数不参与判定）。
    private func event(
        _ title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        id: String? = nil,
        type: EventType = .event(.accepted)
    ) -> EventModel {
        EventModel(
            id: id ?? title,
            start: start,
            end: end,
            title: title,
            location: nil,
            notes: nil,
            url: nil,
            isAllDay: isAllDay,
            type: type,
            calendar: CalendarModel(
                accountName: "Fixture",
                id: "fixture.calendar",
                title: "Fixture",
                color: .systemBlue,
                isSubscribed: false,
                isReminder: false
            ),
            participants: [],
            timeZone: TimeZone(secondsFromGMT: 0),
            hasRecurrenceRules: false,
            priority: nil,
            conferenceURL: nil
        )
    }

    // MARK: - 农历

    /// 三十天的日名**逐项**（十的整数天不走「十位字 + 个位字」的拼法，否则会拼出 `十十` / `廿十`）。
    func testLunarDayNamesCoverThirtyDays() {
        let names = LunarDateLabel.dayNames
        XCTAssertEqual(names.count, 30)
        XCTAssertEqual(Array(names.prefix(11)), [
            "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十", "十一",
        ])
        XCTAssertEqual(names[19], "二十")
        XCTAssertEqual(names[20], "廿一")
        XCTAssertEqual(names[28], "廿九")
        XCTAssertEqual(names[29], "三十")
        XCTAssertEqual(LunarDateLabel.monthNames.count, 12)
        XCTAssertEqual(LunarDateLabel.monthNames.first, "正月")
        XCTAssertEqual(LunarDateLabel.monthNames.last, "腊月")
    }

    /// 农历标签的**真值**：`Calendar(identifier: .chinese)` 给出的月 / 日 → 中文名（含闰月前缀）。
    ///
    /// 断言取「与 `Calendar` 的分量自洽」而不是写死某一天的农历（写死会把用例绑在某个年份的
    /// 置闰上；下面同时钉一条**已知的**真值，两条一起才既有自洽又有回归意义）。
    func testLunarDateLabelMatchesChineseCalendarComponents() {
        let chinese = Calendar(identifier: .chinese)
        let gregorian = fixtureCalendar()
        var checked = 0
        for month in 1...12 {
            guard let date = gregorian.date(from: DateComponents(year: 2026, month: month, day: 15)) else { continue }
            let components = chinese.dateComponents([.month, .day], from: date)
            guard let lunarMonth = components.month, let lunarDay = components.day,
                  let label = LunarDateLabel.text(for: date)
            else {
                XCTFail("2026-\(month)-15 应能算出农历标签")
                continue
            }
            let expected = (components.isLeapMonth == true ? "闰" : "")
                + LunarDateLabel.monthNames[lunarMonth - 1]
                + LunarDateLabel.dayNames[lunarDay - 1]
            XCTAssertEqual(label, expected, "2026-\(month)-15 的农历标签应与日历分量自洽")
            checked += 1
        }
        XCTAssertEqual(checked, 12, "12 个月各取一天都应能算出农历")

        // 已知真值：2026-02-17 是农历正月初一（2026 年春节——与 `WorkdayCalendar.holidayRuns` 的
        // 「春节 2/15–2/23」同一年同一段）。
        XCTAssertEqual(
            LunarDateLabel.text(for: gregorian.date(from: DateComponents(year: 2026, month: 2, day: 17))!),
            "正月初一",
            "2026-02-17 = 丙午年正月初一（春节）"
        )
    }

    // MARK: - 节假日名（与工作日表同源的第二张表）

    /// **两张表不许各说一套**：`holidayRuns` 里每一个放假日都必须真的在 `holidayTables.holidays` 里
    /// （反之亦然）——名字表是给人看的，工作日表是判定用的，两者错开就会出现「显示国庆节却是工作日」。
    func testHolidayNamesCoverEveryHolidayDay() {
        for (year, table) in WorkdayCalendar.holidayTables {
            let runs = WorkdayCalendar.holidayRuns[year]
            XCTAssertNotNil(runs, "\(year) 有工作日表就应有节日名表")
            var namedDays: Set<String> = []
            for run in runs ?? [] {
                for day in run.days {
                    namedDays.insert("\(run.month)/\(day)")
                }
            }
            XCTAssertEqual(
                namedDays.symmetricDifference(table.holidays), [],
                "\(year) 的放假日与节日名覆盖的日期必须完全一致"
            )
        }
    }

    /// 调休日也**逐条有名字**（10/10 归国庆、2/14 与 2/28 归春节…），且键集与 `makeupWorkdays` 一致。
    func testHolidayNamesCoverEveryMakeupDay() {
        for (year, table) in WorkdayCalendar.holidayTables {
            let names = WorkdayCalendar.makeupDayNames[year] ?? [:]
            XCTAssertEqual(
                Set(names.keys), table.makeupWorkdays,
                "\(year) 的调休日必须逐个登记归属节日（否则那天显示不出「节日名（班）」）"
            )
        }
    }

    /// 查询口径：放假日 → 名字；调休日 → 名字 + `（班）`；平常日子 → nil（表外年份同样 nil）。
    func testHolidayLabelQuery() {
        let calendar = fixtureCalendar()
        // 2026-10-01 国庆节第一天（放假日）
        XCTAssertEqual(
            TodayHeadline.holidayLabel(for: time(calendar, month: 10, day: 1), calendar: calendar),
            "国庆节"
        )
        // 2026-10-10 国庆调休上班（周六上班）——名字 + （班）
        XCTAssertEqual(
            TodayHeadline.holidayLabel(for: time(calendar, month: 10, day: 10), calendar: calendar),
            "国庆节" + TodayHeadline.localized("home.today.makeupSuffix")
        )
        XCTAssertTrue(WorkdayCalendar.isMakeupWorkday(time(calendar, month: 10, day: 10), calendar: calendar))
        XCTAssertTrue(WorkdayCalendar.isWorkday(
            time(calendar, month: 10, day: 10),
            workdays: WorkdayCalendar.defaultWorkdays,
            calendar: calendar
        ), "调休日恒为工作日")
        // 平常的周三：没有名字
        XCTAssertNil(TodayHeadline.holidayLabel(for: time(calendar, month: 10, day: 14), calendar: calendar))
        // 表外年份：不猜、不画
        let year2030 = calendar.date(from: DateComponents(year: 2030, month: 1, day: 1))!
        XCTAssertNil(TodayHeadline.holidayLabel(for: year2030, calendar: calendar))
        XCTAssertFalse(WorkdayCalendar.isMakeupWorkday(year2030, calendar: calendar))
    }

    /// 日期行**含公历、星期、农历三段的形状**（公历 / 星期随语言，因此只断分隔与包含关系）。
    func testTodayHeadlineShape() {
        let calendar = fixtureCalendar()
        let text = TodayHeadline.text(for: time(calendar, month: 10, day: 1), calendar: calendar)
        XCTAssertTrue(text.contains("10"), "含公历的日：\(text)")
        XCTAssertTrue(text.contains("·"), "三段之间用 ` · ` 连接：\(text)")
        XCTAssertTrue(text.contains("八月"), "2026-10-01 的农历在八月：\(text)")
        XCTAssertTrue(text.contains("国庆节"), "国庆节第一天应带节日名：\(text)")
    }

    // MARK: - 下一个日程

    /// 取舍三态：**正在进行优先** → 最近的将来 → 没有更多。
    func testNextEventPickPrefersOngoingThenEarliestUpcoming() {
        let calendar = fixtureCalendar()
        let now = time(calendar, month: 10, day: 14, hour: 10, minute: 40)
        let ongoing = event("正在进行", start: time(calendar, month: 10, day: 14, hour: 10), end: time(calendar, month: 10, day: 14, hour: 11))
        let soon = event("马上开始", start: time(calendar, month: 10, day: 14, hour: 12), end: time(calendar, month: 10, day: 14, hour: 13))
        let later = event("下午", start: time(calendar, month: 10, day: 14, hour: 15), end: time(calendar, month: 10, day: 14, hour: 16))
        let past = event("已经结束", start: time(calendar, month: 10, day: 14, hour: 8), end: time(calendar, month: 10, day: 14, hour: 9))
        let allDay = event("全天", start: time(calendar, month: 10, day: 14), end: time(calendar, month: 10, day: 15), isAllDay: true)
        let tomorrow = event("明天", start: time(calendar, month: 10, day: 15, hour: 9), end: time(calendar, month: 10, day: 15, hour: 10))

        let pick = TodayNextEvent.pick(events: [later, soon, ongoing, past, allDay, tomorrow], now: now, calendar: calendar)
        XCTAssertEqual(
            pick,
            .ongoing(ongoing, minutesUntilEnd: 20),
            "有正在进行的就取它（全天条目与已结束的不算）"
        )

        let upcomingOnly = TodayNextEvent.pick(events: [later, soon, past, allDay, tomorrow], now: now, calendar: calendar)
        XCTAssertEqual(
            upcomingOnly,
            .upcoming(soon, minutesUntilStart: 80),
            "没有进行中的 → 取最近的将来（明天的日程不在「今天」窗口里）"
        )

        let none = TodayNextEvent.pick(events: [past, allDay], now: now, calendar: calendar)
        XCTAssertEqual(none, .none, "只剩全天条目与已结束的 → 没有更多日程")
    }

    /// 大字那一行：`下一个 · 标题 · 时间区间`；进行中说「进行中」；没有时是那句空态文案。
    func testNextEventHeadline() {
        let calendar = fixtureCalendar()
        let now = time(calendar, month: 10, day: 14, hour: 13, minute: 40)
        let next = event("评审会", start: time(calendar, month: 10, day: 14, hour: 14), end: time(calendar, month: 10, day: 14, hour: 15))
        let pick = TodayNextEvent.pick(events: [next], now: now, calendar: calendar)
        let headline = TodayNextEvent.headline(for: pick, calendar: calendar)
        XCTAssertTrue(headline.hasPrefix(TodayNextEvent.localized("home.today.next")), "以「下一个」开头：\(headline)")
        XCTAssertTrue(headline.contains("评审会"), headline)
        XCTAssertTrue(headline.contains("–"), "定时日程给时间区间：\(headline)")
        XCTAssertEqual(
            TodayNextEvent.headline(for: .none, calendar: calendar),
            TodayNextEvent.localized("home.today.noMore"),
            "没有更多日程时是那句空态文案"
        )
    }

    /// 倒计时四档 + 空态：小时分钟 / 整小时 / 分钟 / 即将开始 / 距结束 / 马上结束 / nil。
    func testCountdownText() {
        let calendar = fixtureCalendar()
        let start = time(calendar, month: 10, day: 14, hour: 14)
        let target = event("会议", start: start, end: time(calendar, month: 10, day: 14, hour: 15))

        func pick(nowHour: Int, nowMinute: Int, nowSecond: Int = 0) -> TodayNextEvent.Pick {
            let now = time(calendar, month: 10, day: 14, hour: nowHour, minute: nowMinute, second: nowSecond)
            return TodayNextEvent.pick(events: [target], now: now, calendar: calendar)
        }

        XCTAssertEqual(
            TodayNextEvent.countdown(for: pick(nowHour: 12, nowMinute: 40)),
            String(format: TodayNextEvent.localized("home.today.countdown.hoursMinutes"), 1, 20),
            "还有 1 小时 20 分"
        )
        XCTAssertEqual(
            TodayNextEvent.countdown(for: pick(nowHour: 12, nowMinute: 0)),
            String(format: TodayNextEvent.localized("home.today.countdown.hours"), 2),
            "整小时不带「0 分」"
        )
        XCTAssertEqual(
            TodayNextEvent.countdown(for: pick(nowHour: 13, nowMinute: 30)),
            String(format: TodayNextEvent.localized("home.today.countdown.minutes"), 30),
            "不足一小时按分钟"
        )
        XCTAssertEqual(
            TodayNextEvent.countdown(for: pick(nowHour: 13, nowMinute: 59, nowSecond: 30)),
            TodayNextEvent.localized("home.today.countdown.starting"),
            "不到一分钟 → 即将开始"
        )
        XCTAssertEqual(
            TodayNextEvent.countdown(for: pick(nowHour: 13, nowMinute: 59)),
            String(format: TodayNextEvent.localized("home.today.countdown.minutes"), 1),
            "刚好 60 秒仍算「1 分钟」（整分钟向下截断）"
        )
        XCTAssertEqual(
            TodayNextEvent.countdown(for: pick(nowHour: 14, nowMinute: 40)),
            String(format: TodayNextEvent.localized("home.today.countdown.ongoingMinutes"), 20),
            "进行中 → 距结束 20 分钟"
        )
        XCTAssertEqual(
            TodayNextEvent.countdown(for: pick(nowHour: 14, nowMinute: 59, nowSecond: 30)),
            TodayNextEvent.localized("home.today.countdown.ending"),
            "进行中且不足一分钟 → 马上结束"
        )
        XCTAssertNil(TodayNextEvent.countdown(for: .none), "没有日程时没有倒计时")
    }

    // MARK: - 工作日剩余

    /// 三段（本月 / 本季 / 今年）**恒为三条**、数字与 `WorkdayCalendar.spanStats` 同源。
    func testWorkdayRemainderLineMatchesSpanStats() {
        let calendar = fixtureCalendar()
        let now = time(calendar, month: 10, day: 14, hour: 10)
        let parts = WorkdayRemainderLine.parts(now: now, calendar: calendar)
        XCTAssertEqual(parts.count, 3, "本月 / 本季 / 今年三段")

        for (index, scope) in [ProgressCalculator.Scope.month, .quarter, .year].enumerated() {
            let remaining = WorkdayCalendar.spanStats(
                scope: scope,
                now: now,
                workdays: WorkdayCalendar.defaultWorkdays,
                workStartHour: WorkdayCalendar.defaultWorkStartHour,
                workEndHour: WorkdayCalendar.defaultWorkEndHour,
                calendar: calendar
            ).remainingWorkdays
            XCTAssertTrue(
                parts[index].contains("\(remaining)"),
                "第 \(index) 段应含剩余工作日数 \(remaining)，实到 \(parts[index])"
            )
        }

        // 2026-10-14（周三）：10 月剩 12 个工作日（10/15、16 + 19–23 + 26–30，扣掉周末）；
        // 本季 = 10–12 月；今年 = 全年。三个数一起钉住这条口径（跨年 / 跨季边界的算术在 `WorkdayCalendar` 里）。
        let monthRemaining = WorkdayCalendar.spanStats(
            scope: .month, now: now, workdays: WorkdayCalendar.defaultWorkdays,
            workStartHour: 9, workEndHour: 18, calendar: calendar
        ).remainingWorkdays
        XCTAssertEqual(monthRemaining, 12, "2026-10-15 起至月底的工作日（2 + 5 + 5）")
        XCTAssertEqual(
            WorkdayRemainderLine.text(now: now, calendar: calendar),
            parts.joined(separator: " · "),
            "整行 = 三段用 ` · ` 连接"
        )
    }

    // MARK: - 首页全量清单与独立今天快照

    func testHomeTodayEventsUseHalfOpenOverlapAndRecordIDs() {
        let calendar = fixtureCalendar()
        let day = time(calendar, month: 10, day: 14)
        let tomorrow = time(calendar, month: 10, day: 15)
        let now = time(calendar, month: 10, day: 14, hour: 10)
        let ongoing = event("同名", start: time(calendar, month: 10, day: 13, hour: 23), end: time(calendar, month: 10, day: 14, hour: 11), id: "overnight")
        let sameTitle = event("同名", start: now, end: time(calendar, month: 10, day: 14, hour: 12), id: "other")
        let midnightEnded = event("零点结束", start: time(calendar, month: 10, day: 13, hour: 20), end: day)
        let future = event("明日", start: tomorrow, end: time(calendar, month: 10, day: 15, hour: 1))
        let allDay = event("全天", start: day, end: tomorrow, isAllDay: true)
        let reminder = event("提醒", start: now, end: tomorrow, type: .reminder(completed: false))
        let input = [ongoing, sameTitle, ongoing, midnightEnded, future, allDay, reminder]
        XCTAssertEqual(HomeTodayEvents.filtered(input, now: now, calendar: calendar).map(\.id), ["overnight", "other", "全天"])
        XCTAssertEqual(HomeTodayEvents.filtered(input, now: now, hideAllDayEvents: true, calendar: calendar).map(\.id), ["overnight", "other"])
        XCTAssertEqual(TodayNextEvent.pick(events: input, now: now, calendar: calendar), .ongoing(ongoing, minutesUntilEnd: 60))
        XCTAssertEqual(TodayNextEvent.pick(events: [midnightEnded, future, allDay, reminder], now: now, calendar: calendar), .none)
    }

    func testHomeNextEventKeepsIndependentTodaySnapshotWhileBrowsingDate() async {
        let calendar = fixtureCalendar()
        let now = time(calendar, month: 10, day: 14, hour: 10)
        let today = event("今天", start: now, end: time(calendar, month: 10, day: 14, hour: 11))
        let tomorrow = event("明日", start: time(calendar, month: 10, day: 15, hour: 10), end: time(calendar, month: 10, day: 15, hour: 11))
        let service = CalendarInteractionMemoryService(records: [today, tomorrow], calendars: [today.calendar], calendar: calendar)
        let manager = CalendarManager(service: service, now: { now }, calendar: calendar, startMonitoring: false)
        await manager.updateTodayEvents(force: true)
        let before = TodayNextEvent.pick(events: manager.todayEvents, now: now, calendar: calendar)
        await manager.updateCurrentDate(tomorrow.start)
        XCTAssertEqual(manager.events.map(\.id), [tomorrow.id])
        XCTAssertEqual(manager.todayEvents, [today])
        XCTAssertEqual(TodayNextEvent.pick(events: manager.todayEvents, now: now, calendar: calendar), before)
        XCTAssertEqual(HomeTodayEvents.filtered(manager.todayEvents, now: now, calendar: calendar), [today])
    }

    func testHomeEntriesContainAllNineOrThirtyRecordsAndDeduplicateByID() async {
        for count in [9, 30] {
            let backend = CalendarInteractionFixtures.makeBackend(count: count, on: Date())
            let store = fixtureTodoStore(backend)
            await store.refresh()
            let records = backend.allRecords()
            let events = records.filter { !$0.type.isReminder }
            let todos = store.items
            let all = TodosHomeBlockLayout.listedEntries(events: events + records, todos: todos + todos, hasFullAccess: true)
            XCTAssertEqual(all.count, count)
            XCTAssertEqual(Set(all.map(\.recordID)).count, count)
            XCTAssertTrue(all.contains { $0.recordID == String(format: "fixture-reminder-%02d", count) })
            let hidden = TodosHomeBlockLayout.listedEntries(events: events, todos: todos, hasFullAccess: true, hideCompletedReminders: true)
            XCTAssertEqual(hidden.count, count - 1)
            XCTAssertEqual(TodosHomeBlockLayout.listedEntries(events: events, todos: todos, hasFullAccess: false).count, count / 3)
        }
        let sameTitle = [TodoBucketing.Item(id: "one", title: "同名"), TodoBucketing.Item(id: "two", title: "同名")]
        XCTAssertEqual(TodosHomeBlockLayout.uniqueTodos(sameTitle + sameTitle).map(\.id), ["one", "two"])
    }

    func testHomeAnchorKeepsViewportAndFindsAdjacentSurvivor() {
        let ids = ["event", "one", "two", "three"]
        XCTAssertEqual(TodosHomeBlockLayout.anchor(afterRemoving: "two", from: ids, anchor: "one"), "one")
        XCTAssertEqual(TodosHomeBlockLayout.anchor(afterRemoving: "two", from: ids, anchor: "two"), "three")
        XCTAssertEqual(TodosHomeBlockLayout.anchor(afterRemoving: "three", from: ids, anchor: "three"), "two")
        XCTAssertNil(TodosHomeBlockLayout.anchor(afterRemoving: "one", from: ["one"], anchor: "one"))
        XCTAssertNil(TodosHomeBlockLayout.anchor(afterRemoving: "one", from: ids, anchor: nil))
    }

    private func fixtureTodoStore(_ backend: CalendarInteractionMemoryService) -> TodoStore {
        TodoStore(logger: ModuleLogger(moduleID: "com.cmeng.gourd.todos", shortID: "todos"), fixtureBackend: backend)
    }

    func testTodoFixtureInitializationAuthorizationAndRefreshAvoidEventKit() async {
        let backend = CalendarInteractionFixtures.makeBackend(count: 9, on: Date())
        let store = fixtureTodoStore(backend)
        XCTAssertEqual(store.authorization, .fullAccess)
        XCTAssertFalse(store.hasInitializedEventStore)
        store.start()
        await store.refresh()
        XCTAssertEqual(store.items.count, 6)
        XCTAssertFalse(store.isObservingEventStore)
        backend.setAuthorization(.denied, for: .reminder)
        await store.requestAccess()
        XCTAssertEqual(store.authorization, .denied)
        XCTAssertTrue(store.items.isEmpty)
        backend.setAuthorization(.fullAccess, for: .reminder)
        await store.requestAccess()
        XCTAssertEqual(store.items.count, 6)
        store.stop()
        XCTAssertFalse(store.hasInitializedEventStore)
        XCTAssertFalse(store.isObservingEventStore)
        let defaultStore = TodoStore(logger: ModuleLogger(moduleID: "com.cmeng.gourd.todos", shortID: "todos"))
        await defaultStore.refresh()
        XCTAssertFalse(defaultStore.hasInitializedEventStore)
        XCTAssertFalse(defaultStore.items.isEmpty)
    }

    func testTodoFixtureAllWritesShareBackendIncludingNoDateAndFailureRollback() async throws {
        let backend = CalendarInteractionFixtures.makeBackend(count: 9, on: Date())
        let store = fixtureTodoStore(backend)
        await store.refresh()
        let item = try XCTUnwrap(store.items.first { !$0.isCompleted })
        await store.setCompleted(item, completed: true)
        XCTAssertTrue(try XCTUnwrap(store.items.first { $0.id == item.id }).isCompleted)
        XCTAssertEqual(backend.event(withID: item.id)?.type, .reminder(completed: true))
        XCTAssertNotNil(backend.completionDate(forReminderID: item.id))
        let priorityOK = await store.setPriority(item, to: .high)
        XCTAssertTrue(priorityOK)
        await store.refresh()
        XCTAssertEqual(store.priority(for: item.id), .high)
        XCTAssertEqual(backend.event(withID: item.id)?.priority, .high)
        for due in [TodoComposer.DueOption.today, .tomorrow, .none] {
            let ok = await store.createTodo(title: "  created-\(due.rawValue)  ", due: due)
            XCTAssertTrue(ok)
            let created = try XCTUnwrap(store.items.first { $0.title == "created-\(due.rawValue)" })
            XCTAssertEqual(created.dueDate == nil, due == .none)
            XCTAssertEqual(backend.event(withID: created.id)?.start == .distantFuture, due == .none)
            if due == .tomorrow {
                XCTAssertTrue(Calendar.current.isDateInTomorrow(try XCTUnwrap(created.dueDate)))
            }
            let removed = await store.removeTodo(created)
            XCTAssertTrue(removed)
            XCTAssertNil(backend.event(withID: created.id))
            XCTAssertFalse(store.items.contains { $0.id == created.id })
        }
        backend.writeFailure = .readOnlyCalendar
        let originalRecords = backend.allRecords()
        let originalItems = store.items
        await store.setCompleted(item, completed: false)
        XCTAssertNotNil(store.writeFailure)
        let failedPriority = await store.setPriority(item, to: .low)
        let failedCreate = await store.createTodo(title: "failed", due: .none)
        let failedDelete = await store.removeTodo(item)
        XCTAssertFalse(failedPriority)
        XCTAssertFalse(failedCreate)
        XCTAssertFalse(failedDelete)
        XCTAssertEqual(store.priority(for: item.id), .high)
        XCTAssertEqual(backend.allRecords(), originalRecords)
        XCTAssertEqual(store.items, originalItems)
        XCTAssertFalse(store.hasInitializedEventStore)
        XCTAssertFalse(store.isObservingEventStore)
    }

    func testHomeCompletionSharesSubmissionStateAndUpdatesCountsWithoutNavigation() async throws {
        let backend = CalendarInteractionFixtures.makeBackend(count: 9, on: Date())
        let store = fixtureTodoStore(backend)
        await store.refresh()
        let item = try XCTUnwrap(store.items.first { !$0.isCompleted })
        let record = try XCTUnwrap(backend.event(withID: item.id))
        let manager = CalendarManager(service: backend, startMonitoring: false)
        let session = CalendarPanelSession(manager: manager)
        session.homeScrollAnchor = item.id
        let before = TodoBucketing.classify(store.items).today
        backend.writeDelayNanoseconds = 5_000_000
        let first = Task { await session.complete(record, completed: true) }
        while !session.isSubmitting { await Task.yield() }
        XCTAssertTrue(session.shouldProtectAutoClose)
        let duplicate = await session.complete(record, completed: true)
        XCTAssertFalse(duplicate)
        let completed = await first.value
        XCTAssertTrue(completed)
        await store.refresh()
        let after = TodoBucketing.classify(store.items).today
        XCTAssertEqual(after.total, before.total)
        XCTAssertEqual(after.completed, before.completed + 1)
        XCTAssertEqual(session.route, .list)
        XCTAssertNil(session.detailEvent)
        XCTAssertEqual(session.homeScrollAnchor, item.id)
        XCTAssertEqual(backend.writeAttempts, 1)
        XCTAssertFalse(session.isSubmitting)
        session.showDetail(record, source: .home(anchor: item.id))
        XCTAssertEqual(session.back(), .home(anchor: item.id))
        XCTAssertEqual(session.homeScrollAnchor, item.id)
        backend.writeFailure = .readOnlyCalendar
        let original = store.items
        let failed = await session.complete(record, completed: false)
        XCTAssertFalse(failed)
        XCTAssertEqual(session.completionError, CalendarMutationError.readOnlyCalendar.localizedDescription)
        await store.refresh()
        XCTAssertEqual(store.items, original)
    }

    func testHomeCompletionErrorDoesNotReusePreviousSaveError() async throws {
        let backend = CalendarInteractionFixtures.makeBackend(count: 9, on: Date())
        let session = CalendarPanelSession(manager: CalendarManager(service: backend, startMonitoring: false))
        session.beginCreate(kind: .event, on: Date(), calendarID: "fixture-events")
        let saved = await session.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(session.error, CalendarMutationError.invalidTitle.localizedDescription)
        let event = try XCTUnwrap(backend.allRecords().first { !$0.type.isReminder })
        let completed = await session.complete(event, completed: true)
        XCTAssertFalse(completed)
        XCTAssertEqual(session.completionError, CalendarMutationError.wrongRecordType.localizedDescription)
        XCTAssertNotEqual(session.completionError, session.error)
        XCTAssertEqual(backend.writeAttempts, 0)
    }

    func testTodoRefreshDiscardsOlderAsynchronousReadAfterNewCompletionSnapshot() async {
        var callbacks: [CheckedContinuation<[TodoBucketing.Item], Never>] = []
        let store = TodoStore(
            logger: ModuleLogger(moduleID: "com.cmeng.gourd.todos", shortID: "todos"),
            authorizationStatus: { .fullAccess },
            readItems: { await withCheckedContinuation { callbacks.append($0) } }
        )
        let oldRead = Task { await store.refresh() }
        while callbacks.count < 1 { await Task.yield() }
        let newRead = Task { await store.refresh() }
        while callbacks.count < 2 { await Task.yield() }
        let latest = TodoBucketing.Item(id: "same", title: "latest", dueDate: Date(), isCompleted: true, completionDate: Date())
        callbacks[1].resume(returning: [latest])
        await newRead.value
        callbacks[0].resume(returning: [TodoBucketing.Item(id: "same", title: "old", dueDate: Date())])
        await oldRead.value
        XCTAssertEqual(store.items, [latest])
        XCTAssertEqual(TodoBucketing.classify(store.items).today.completed, 1)
        XCTAssertFalse(store.hasInitializedEventStore)
    }

}
