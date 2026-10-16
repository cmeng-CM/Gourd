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
//  HomeTodayBand.swift
//  Gourd 宿主 · 首页的**今天带**（p13-home-v5 / docs/38-home-v5-layout.md §做法 三）
//
//  首页自 p13 起分三带（docs/38 D-01）：环境带（固定第一排）→ **今天带** → 可变流。
//  本文件是中间那一条：**宿主直渲、不吃板、不可排**——它不是模块（数据跨「日历 + 农历 +
//  节假日 + 工作日」四个域，做成模块只会把它拆成四份），也不进 `homeBlockOrder`。
//
//  **一行四段**（2026-10-16 用户：「这个内容放在日期后面，不单独放一排」——原来「下一个」自己占
//  第二行，整带 56pt；现在并进日期行，整带 32pt，省下的 24pt 归可变流）：
//
//      10月10日 周六 · 九月初十 · 国庆节（班） · 下一个 · 评审会 · 14:00–15:00   本月剩 15 天 · 还有 1 小时 20 分
//
//  - 「今天是什么日子」：公历（随语言）+ 农历（中文专名）+ 节假日名（2026 表内）；
//  - 「当务之急」：今天**还没结束**的下一条定时日程（+ 距它还有多久 / 进行中）；**字号都不动**，
//    仍是 20pt 半粗，只是从「独占一行」改成「接在日期后面」；
//  - 「工作日剩余」（本月 / 本季 / 今年）来自 `WorkdayCalendar.spanStats`——原「工作日统计」模块
//    退场后的替身（docs/38 D-06：那块占 347×220 而价值低）；
//  - **倒计时**（蓝色）留在最右：眼睛最后落在「还有多久」上。
//
//  **截断口径**：只有「下一个」那一段会截断（标题长时先吃中间的空档）；日期 / 工作日 / 倒计时三段
//  都是 `fixedSize`，宽度不够时先缩「下一个」。
//
//  **四条口径**（docs/38 §做法 三）：
//  ① 农历与节假日名**按中文输出、不分语言**——它们是中文日历的专名，翻成英文没有意义；
//     周围那几段文案（`下一个` / `还有…` / `本月剩`）走 Localizable 的 en + zh-Hans 两栏；
//  ② 节假日名只覆盖 2026（`WorkdayCalendar.holidayRuns`）：表外年份**不画那一段**，不猜也不画「未知」；
//  ③ 「下一个」**只在定时日程里找**：全天条目不是一个「几点开始」的对象；
//  ④ 倒计时按分钟刷新（`TimelineView(.everyMinute)` 只包住本带，不包整页）。
//
//  纯函数（文案与取舍）与视图分开：`TodayHeadline` / `TodayNextEvent` / `TodayCountdown` /
//  `WorkdayRemainderLine` / `LunarDateLabel` 都可单测，视图只组装。
//

import Defaults
import SwiftUI

// MARK: - 尺寸（宿主常量）

/// 今天带的**尺寸**（唯一取值处；接缝的高度账本也读它）。
enum HomeTodayBandLayout {
    /// 整条带的**高度 = 单行 32**（2026-10-16：原来两行 16 + 8 + 32 = 56，用户要求并成一行）。
    /// 省下的 24pt 归可变流——接缝的高度账本读的就是这个数。
    static var height: CGFloat { nextLineHeight }

    /// 与两侧（环境带 / 可变流）之间的缝——**与块间距同值**（`HomeStripLayout.spacing`）。
    /// 改前这个位置是 `HomeCalendarRow.rowSpacing`（日历行与流之间的那道缝），值不变、换了个家。
    static let rowSpacing: CGFloat = 8

    /// 日期行的高度（12pt 文字）——并成一行后不再单独占高，保留给断言与将来复用。
    static let headlineHeight: CGFloat = 16
    /// 两行之间的间距——并成一行后不再使用（保留理由同上）。
    static let lineSpacing: CGFloat = 8
    /// 这一行的高度（20pt「下一个」+ 16pt 倒计时）。
    static let nextLineHeight: CGFloat = 32

    /// 两行共用的左右内缩（与块的内容内缩同档：内容不贴板缘——本条没有板，但两侧与块的
    /// 内容左缘对齐，整页才是一条竖线）。
    static let horizontalInset: CGFloat = HomeBlockChrome.contentInsetHorizontal

    // MARK: 三段式（2026-10-16 变体 A：胶囊分组）
    //
    // 段间与段内的样式档集中在这里；视图只引用名字（与 `MonthGridLayout` 的写法一致）。

    /// 三段之间的间距。
    static let segmentSpacing: CGFloat = 12
    /// 胶囊圆角。
    static let pillRadius: CGFloat = 10
    /// 日期段胶囊的高度（12pt 文字 + 上下各 4）。
    static let datePillHeight: CGFloat = 24
    /// 下一个段胶囊的高度（19pt 标题 + 上下各 5；比日期段高一档）。
    static let nextPillHeight: CGFloat = 30
    /// 倒计时胶囊的高度（14pt 文字 + 上下各 7）与左右内边距。
    static let countdownPillHeight: CGFloat = 28
    static let countdownPillPadding: CGFloat = 10
    /// 段② 左缘那条日历色竖条的宽度。
    static let nextBarWidth: CGFloat = 3
    /// 日期段胶囊的底（白 6%）与下一个段胶囊的底（白 10%）——两档不同的「有底」。
    static let datePillFill: Double = 0.06
    static let nextPillFill: Double = 0.10
    /// 农历比公历亮一档（同一段内的层次）。
    static let datePrimaryOpacity: Double = 0.62
    static let lunarOpacity: Double = 0.9
    /// 工作日段（最弱的一档）。
    static let workdayOpacity: Double = 0.42
}

// MARK: - 农历（中文专名）

/// 农历日期的中文标签（纯函数；`Calendar(identifier: .chinese)` 提供月 / 日 / 闰月）。
///
/// **为什么自己拼字符串**：`DateFormatter` 走中文 locale 时对农历的输出与 `zh-Hans` 的
/// 「九月初十」并不逐字一致（不同系统版本上出现过 `九月10` 一类混合写法），而首页这一行要的
/// 就是固定的中文写法。月 / 日的字表短且封闭（12 + 30），自己拼换来的是**可断言**（用例直接钉）。
///
/// 取不到农历分量（极端时区 / 日历异常）时返回 nil，**不画那一段**（调用方据此跳过，
/// 不画占位的破折号）。
enum LunarDateLabel {
    /// 十二个月的月名（农历正月起）。
    static let monthNames = [
        "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月",
    ]

    /// 三十天的日名（初一…初十 / 十一…十九 / 二十 / 廿一…廿九 / 三十）。
    ///
    /// 十的整数天（10 / 20 / 30）各自成词、不走「十位字 + 个位字」的拼法——否则会拼出
    /// `十十` / `廿十` 这类不存在的写法（`testLunarDayNamesCoverThirtyDays` 逐项钉这四条）。
    static let dayNames: [String] = {
        let units = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        return (1...30).map { day in
            switch day {
            case 10: return "初十"
            case 20: return "二十"
            case 30: return "三十"
            default:
                let tens = day < 10 ? "初" : (day < 20 ? "十" : "廿")
                return tens + units[day % 10]
            }
        }
    }()

    /// 农历标签：`九月初十`（闰月前缀 `闰`）。
    static func text(for date: Date, calendar: Calendar = Calendar(identifier: .chinese)) -> String? {
        let components = calendar.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day,
              (1...monthNames.count).contains(month),
              (1...dayNames.count).contains(day)
        else { return nil }
        let prefix = components.isLeapMonth == true ? "闰" : ""
        return prefix + monthNames[month - 1] + dayNames[day - 1]
    }
}

// MARK: - 日期行

/// 今天带的**第一行左侧**：`10月10日 周六 · 九月初十 · 国庆节（班）`（纯函数）。
enum TodayHeadline {
    /// 组装整行。公历与星期走 `Date.FormatStyle`（随语言：en 得 `Oct 10 Sat`、zh 得 `10月10日 周六`）；
    /// 农历与节假日名是中文专名（口径 ①），取不到就整段略去。
    static func text(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let parts = parts(for: date, calendar: calendar)
        return ([parts.weekday] + [parts.lunar, parts.holiday].compactMap { $0 }).joined(separator: " · ")
    }

    /// 拆成三段（2026-10-16 变体 A：同一段里分两档亮度）——公历+星期 / 农历 / 节假日。
    /// 农历与节假日取不到时给 nil，调用方**整段略去**（口径 ①/②：不画占位的破折号）。
    static func parts(
        for date: Date, calendar: Calendar = .autoupdatingCurrent
    ) -> (weekday: String, lunar: String?, holiday: String?) {
        let weekday = [
            date.formatted(.dateTime.month(.abbreviated).day()),
            date.formatted(.dateTime.weekday(.abbreviated)),
        ].joined(separator: " · ")
        return (weekday, LunarDateLabel.text(for: date), holidayLabel(for: date, calendar: calendar))
    }

    /// 节假日那一段：**名 + 是否调休上班**（`国庆节（班）` / `春节`）。表外年份返回 nil（口径 ②）。
    ///
    /// 名字与「是不是调休」都由 `WorkdayCalendar` 的两张表答（放假日与调休日**都有名字**，
    /// 见那边的 `holidayRuns` / `makeupDayNames`），这里只负责拼那个后缀。
    static func holidayLabel(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String? {
        guard let name = WorkdayCalendar.holidayName(of: date, calendar: calendar) else { return nil }
        guard WorkdayCalendar.isMakeupWorkday(date, calendar: calendar) else { return name }
        return name + localized("home.today.makeupSuffix")
    }

    static func localized(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }
}

/// 首页只读独立今天快照，按半开窗口重叠筛选；跨日未结束事件也属于今天。
enum HomeTodayEvents {
    static func filtered(
        _ events: [EventModel], now: Date,
        hideAllDayEvents: Bool = false, calendar: Calendar = .autoupdatingCurrent
    ) -> [EventModel] {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        var seen = Set<String>()
        return events.filter {
            !$0.type.isReminder && (!hideAllDayEvents || !$0.isAllDay)
                && $0.start < end && $0.end > start && seen.insert($0.id).inserted
        }
    }
}

// MARK: - 下一个日程

/// 「今天还没结束的下一条定时日程」的取舍与文案（纯函数）。
enum TodayNextEvent {
    /// 取舍结果（三态）。
    enum Pick: Equatable {
        /// 今天没有更多定时日程（含「今天就没有定时日程」与「都结束了」）。
        case none
        /// 还没开始：`minutesUntilStart` 按整分钟截断（≥ 0）。
        case upcoming(EventModel, minutesUntilStart: Int)
        /// 正在进行：`minutesUntilEnd` 按整分钟截断（≥ 0）。
        case ongoing(EventModel, minutesUntilEnd: Int)

        var event: EventModel? {
            switch self {
            case .none: return nil
            case .upcoming(let event, _), .ongoing(let event, _): return event
            }
        }
    }

    /// 从**当天窗口**里挑一条（口径 ③：只看定时条目，全天条目不算「下一个」）。
    ///
    /// 两条判据的顺序是刻意的：**先看有没有正在进行的**（它才是最当务之急的），再找最近的将来。
    /// 同刻有多条时取起点最早的那条（`start` 相同时按标题字典序，保证结果与输入顺序无关）。
    static func pick(
        events: [EventModel],
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Pick {
        let timed = HomeTodayEvents.filtered(events, now: now, hideAllDayEvents: true, calendar: calendar)
            .sorted { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                if lhs.title != rhs.title { return lhs.title < rhs.title }
                return lhs.id < rhs.id
            }

        if let ongoing = timed.first(where: { $0.start <= now && $0.end > now }) {
            return .ongoing(ongoing, minutesUntilEnd: minutes(from: now, to: ongoing.end, calendar: calendar))
        }
        guard let upcoming = timed.first(where: { $0.start > now }) else { return .none }
        return .upcoming(upcoming, minutesUntilStart: minutes(from: now, to: upcoming.start, calendar: calendar))
    }

    /// 段②的三段文字（2026-10-16 变体 A：前缀 / 标题 / 时间各一档样式；倒计时由 `countdown(for:)` 给）。
    /// `.none` 时只给一句「今天没有更多日程」（前缀与时间都为 nil）。
    static func parts(
        for pick: Pick, calendar: Calendar = .autoupdatingCurrent
    ) -> (prefix: String?, title: String, time: String?) {
        guard let event = pick.event else { return (nil, localized("home.today.noMore"), nil) }
        let prefix: String
        switch pick {
        case .ongoing: prefix = localized("home.today.now")
        default: prefix = localized("home.today.next")
        }
        return (prefix, event.title, timeRange(of: event, calendar: calendar))
    }

    /// 拼成一行（纯文案口径，用例直接钉）：`下一个 · 评审会 · 14:00–15:00`（没有时 `今天没有更多日程`）。
    static func headline(for pick: Pick, calendar: Calendar = .autoupdatingCurrent) -> String {
        let parts = parts(for: pick, calendar: calendar)
        return ([parts.prefix, parts.title, parts.time].compactMap { $0 }
            .filter { !$0.isEmpty }).joined(separator: " · ")
    }

    /// 时间列（与待办块的日程行同一条口径：全天 → `全天`；定时 → `9:30` 或 `9:30 – 10:30`）。
    /// 本带只挑定时条目，因此全天那一档实际走不到，保留是为了与 `TodoText.eventTimeLabel` 同形。
    static func timeRange(of event: EventModel, calendar: Calendar = .autoupdatingCurrent) -> String {
        if event.isAllDay { return localized("module.todos.homeAllDay") }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        guard calendar.isDate(event.end, inSameDayAs: event.start), event.end > event.start else {
            return start
        }
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return start + " – " + end
    }

    /// 右侧倒计时：`还有 1 小时 20 分` / `还有 40 分钟` / `即将开始` / `距结束 12 分钟` /
    /// `马上结束`；`.none` 时没有倒计时（nil）。
    static func countdown(for pick: Pick) -> String? {
        switch pick {
        case .none:
            return nil
        case .upcoming(_, let minutes):
            if minutes <= 0 { return localized("home.today.countdown.starting") }
            if minutes >= 60 {
                let hours = minutes / 60
                let rest = minutes % 60
                guard rest > 0 else {
                    return String(format: localized("home.today.countdown.hours"), hours)
                }
                return String(format: localized("home.today.countdown.hoursMinutes"), hours, rest)
            }
            return String(format: localized("home.today.countdown.minutes"), minutes)
        case .ongoing(_, let minutes):
            guard minutes > 0 else { return localized("home.today.countdown.ending") }
            return String(format: localized("home.today.countdown.ongoingMinutes"), minutes)
        }
    }

    /// 两个时刻之间的**整分钟数**（向下截断、不为负）——与 `WorkdayCalendar.todayState` 同一条口径。
    static func minutes(from start: Date, to end: Date, calendar: Calendar = .autoupdatingCurrent) -> Int {
        let seconds = end.timeIntervalSince(start)
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(seconds / 60)
    }

    static func localized(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }
}

// MARK: - 工作日剩余（右侧小字）

/// 今天带第一行右侧：`本月剩 15 天 · 本季剩 59 天 · 今年剩 59 天`（纯函数）。
///
/// 口径是 `WorkdayCalendar.spanStats` 的 `remainingWorkdays`（**今天之后、不含今天**的工作日个数），
/// 按默认工作日（ISO 一~五）+ 表内节假日算——原「工作日统计」模块退场后，那三个键
/// （`workStart` / `workEnd` / `workdays`）不再可配，这是本次的一处能力收缩（docs/38 §已知限制 1）。
enum WorkdayRemainderLine {
    /// 三段（本月 / 本季 / 今年），可直接 join；某一段算不出来（区间取不到）时跳过该段。
    static func parts(
        now: Date,
        workdays: Set<Int> = WorkdayCalendar.defaultWorkdays,
        workStartHour: Int = WorkdayCalendar.defaultWorkStartHour,
        workEndHour: Int = WorkdayCalendar.defaultWorkEndHour,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [String] {
        [
            ("home.today.remain.month", ProgressCalculator.Scope.month),
            ("home.today.remain.quarter", ProgressCalculator.Scope.quarter),
            ("home.today.remain.year", ProgressCalculator.Scope.year),
        ].map { key, scope in
            let remaining = WorkdayCalendar.spanStats(
                scope: scope,
                now: now,
                workdays: workdays,
                workStartHour: workStartHour,
                workEndHour: workEndHour,
                calendar: calendar
            ).remainingWorkdays
            return String(format: TodayHeadline.localized(key), remaining)
        }
    }

    /// 整行文案（` · ` 连接）。
    static func text(
        now: Date,
        workdays: Set<Int> = WorkdayCalendar.defaultWorkdays,
        workStartHour: Int = WorkdayCalendar.defaultWorkStartHour,
        workEndHour: Int = WorkdayCalendar.defaultWorkEndHour,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        parts(
            now: now,
            workdays: workdays,
            workStartHour: workStartHour,
            workEndHour: workEndHour,
            calendar: calendar
        ).joined(separator: " · ")
    }
}

// MARK: - 视图

/// 首页的**今天带**（docs/38 §做法 三）：两行四段，宿主直渲、**不吃板**。
///
/// **为什么不吃板**：它没有交互、没有 hover、没有可点的东西——画一块玻璃板只是把「今天是几号」
/// 糊进一个盒子里。三带里只有环境和可变流是「组件」，中间这条是**排版**。
///
/// **分钟粒度刷新**：`TimelineView(.everyMinute)` 只包住本带（不包整页）——倒计时文案
/// （「还有 1 小时 20 分」）不刷新就是错的，而环境带与流没有任何按分钟变的东西。
///
/// 日程来自 `CalendarManager.todayEvents` 独立快照；浏览日历日期不改变这条带。
struct HomeTodayBand: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.hideAllDayEvents) private var hideAllDayEvents

    var body: some View {
        // 分钟粒度：`context.date` 每次 tick 都是「这一分钟」的时刻，倒计时据此重算。
        TimelineView(.everyMinute) { context in
            rows(now: context.date)
        }
        .frame(height: HomeTodayBandLayout.height, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// 段①：公历 + 星期（白 62%）· 农历（白 90%，同一段内亮一档）· 节假日（同段末尾）。
    private func dateSegment(now: Date) -> some View {
        let parts = TodayHeadline.parts(for: now)
        return HStack(spacing: 6) {
            Text(parts.weekday)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(HomeTodayBandLayout.datePrimaryOpacity))
                .lineLimit(1)
                .fixedSize()
            if let lunar = parts.lunar {
                Text(lunar)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(HomeTodayBandLayout.lunarOpacity))
                    .lineLimit(1)
                    .fixedSize()
            }
            if let holiday = parts.holiday {
                Text(holiday)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(HomeTodayBandLayout.datePrimaryOpacity))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: HomeTodayBandLayout.datePillHeight)
        .background(RoundedRectangle(cornerRadius: HomeTodayBandLayout.pillRadius, style: .continuous)
            .fill(.white.opacity(HomeTodayBandLayout.datePillFill)))
    }

    /// 段②：「下一个」前缀 · 标题（会截断的唯一一段）· 起止时间 · 倒计时蓝胶囊；左缘一条事件日历色。
    private func nextSegment(pick: TodayNextEvent.Pick) -> some View {
        let parts = TodayNextEvent.parts(for: pick)
        return HStack(spacing: 8) {
            if let prefix = parts.prefix {
                Text(prefix)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(HomeTodayBandLayout.workdayOpacity + 0.1))
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(parts.title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if let time = parts.time {
                Text(time)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.72))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            if let countdown = TodayNextEvent.countdown(for: pick) {
                Text(countdown)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, HomeTodayBandLayout.countdownPillPadding)
                    .frame(height: HomeTodayBandLayout.countdownPillHeight)
                    // 强调色（默认蓝，跟随「外观 → 强调色」设置）：整条带里唯一的强调色（设计图 F5 的口径）。
                    .background(Capsule().fill(Color.effectiveAccent))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: HomeTodayBandLayout.nextPillHeight)
        .background(RoundedRectangle(cornerRadius: HomeTodayBandLayout.pillRadius, style: .continuous)
            .fill(.white.opacity(HomeTodayBandLayout.nextPillFill)))
        .overlay(alignment: .leading) {
            // 左缘那条日历色（只有真的有一条日程时才画：没有事件就没有颜色）。
            if let event = pick.event {
                Rectangle()
                    .fill(Color(event.calendar.color))
                    .frame(width: HomeTodayBandLayout.nextBarWidth)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: HomeTodayBandLayout.pillRadius, style: .continuous))
    }

    private func rows(now: Date) -> some View {
        let events = HomeTodayEvents.filtered(calendarManager.todayEvents, now: now, hideAllDayEvents: hideAllDayEvents)
        let pick = TodayNextEvent.pick(events: events, now: now)
        // **三段式**（2026-10-16 变体 A，设计图 F5）：① 日期（白 6% 胶囊）② 下一个 + 倒计时
        // （白 10% 胶囊 + 事件日历色左条，倒计时做蓝胶囊贴在段内右端）③ 工作日（无底，最弱一档）。
        return HStack(spacing: HomeTodayBandLayout.segmentSpacing) {
            dateSegment(now: now)
            nextSegment(pick: pick)
            Spacer(minLength: HomeTodayBandLayout.segmentSpacing)
            Text(WorkdayRemainderLine.text(now: now))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(HomeTodayBandLayout.workdayOpacity))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .frame(height: HomeTodayBandLayout.nextLineHeight)
        // 内容左缘与块的**内容左缘**对齐（块的内容内缩 5 + 板 = 块框，见 `HomeBlockChrome`）。
        .padding(.horizontal, HomeTodayBandLayout.horizontalInset)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

}
