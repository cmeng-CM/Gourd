// Modified for Gourd (2026-10-01)
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
//  WorkdayCalendar.swift
//  Gourd 内置模块 · 工作日判定与统计（p7 批次 / T2，docs/31 §接口与数据形状 3）
//
//  **纯函数**：没有 SwiftUI / Defaults / EventKit 依赖——「现在」、星期集合、上下班小时与
//  `Calendar` 全部由调用方注入（单测传固定 `now` + `Asia/Shanghai` 固定日历），因此每个结论
//  都能按手算值断言。模块侧（T3）只做「读配置 → 调这里 → 摆文案」，判定与算术都在本文件。
//
//  判定口径（docs/31 §做法 机制二 / D-07）——**先查表、后看星期**，顺序不可换：
//
//  1. 调休上班日（`makeupWorkdays` 命中）→ **恒为工作日**（哪怕它落在周六周日）；
//  2. 放假日（`holidays` 命中）→ **恒为休息日**（哪怕它落在周一至周五）；
//  3. 都查不到 → 该日的 ISO 星期编号 ∈ 星期集合（默认一~五）。
//
//  **数据来源**：2026 年表逐日期照抄国务院办公厅《关于 2026 年部分节假日安排的通知》
//  （国办发明电〔2025〕7号，见 docs/31 §接口与数据形状 3）；本文件的日期一律与那份清单
//  逐字一致，**不凭记忆增删**。表只含 2026 年，**表外年份退化为纯星期判定**（docs/31
//  §已知限制 1：2027 及以后调休周六会被算作休息日、法定假日会被算作工作日，年度更新随发版）
//  ——退化不崩、不猜测，只回答「按星期算」这一个确定答案。
//
//  **星期编号只在一处换算**：`Calendar.component(.weekday)` 是 1=周日 … 7=周六，而本模块对外
//  （`defaultWorkdays`、manifest `workdays` 配置、设置控件）一律用 **ISO：1=周一 … 7=周日**。
//  两套编号的映射集中在 `isoWeekday(of:calendar:)` 这一个私有函数里（docs/31 的失败信号：
//  混用会错一天）；本文件之外不得再出现第二处换算。
//
//  工作时间为**整点**（0–23 的整数，`workHourRange` 是区间唯一来源，照
//  `LauncherGridMetrics.iconSizeRange` 先例）；非法值回落默认（9–18），见 `resolveWorkHours`。
//

import Foundation

/// 工作日判定与统计（工作日集合 × 2026 国务院节假日与调休表 × 整点上下班时间）。
enum WorkdayCalendar {
    // MARK: - 常量

    /// 默认工作日集合，**ISO 编号：1 = 周一 … 7 = 周日**（docs/31 §接口 3）。
    static let defaultWorkdays: Set<Int> = [1, 2, 3, 4, 5]

    /// 默认上班 / 下班小时（整点）。
    static let defaultWorkStartHour = 9
    static let defaultWorkEndHour = 18

    /// 小时取值的**单一来源**：设置控件的整数滑块与读侧夹取共用这一个区间，
    /// 禁止在他处再写一份 `0...23` 字面量（照 `LauncherGridMetrics.iconSizeRange` 先例）。
    static let workHourRange: ClosedRange<Int> = 0...23

    /// ISO 星期编号的合法取值（私有：对外只通过 `resolveWorkdays` 出入）。
    private static let weekdayRange: ClosedRange<Int> = 1...7

    // MARK: - 节假日与调休表

    /// 某一年的放假日与调休上班日，键为 `"M/d"`（无前导零，与 docs/31 §接口 3 的写法一致）。
    struct HolidayTable {
        /// 放假日（恒为休息日）。
        let holidays: Set<String>
        /// 调休上班日（恒为工作日）。
        let makeupWorkdays: Set<String>
    }

    /// 年份 → 该年表；**查询不到的年份走纯星期判定**（`isWorkday` 的第 3 步）。
    ///
    /// 2026 表来自国办发明电〔2025〕7号（逐日期照抄 docs/31 §接口与数据形状 3）：
    /// 元旦 1/1–1/3；春节 2/15–2/23（2/14、2/28 调休上班）；清明 4/4–4/6；劳动节 5/1–5/5
    /// （5/9 调休上班）；端午 6/19–6/21；中秋 9/25–9/27（9/20 调休上班）；国庆 10/1–10/7
    /// （10/10 调休上班）。
    static let holidayTables: [Int: HolidayTable] = [
        2026: HolidayTable(
            holidays: [
                "1/1", "1/2", "1/3",
                "2/15", "2/16", "2/17", "2/18", "2/19", "2/20", "2/21", "2/22", "2/23",
                "4/4", "4/5", "4/6",
                "5/1", "5/2", "5/3", "5/4", "5/5",
                "6/19", "6/20", "6/21",
                "9/25", "9/26", "9/27",
                "10/1", "10/2", "10/3", "10/4", "10/5", "10/6", "10/7",
            ],
            makeupWorkdays: ["1/4", "2/14", "2/28", "5/9", "9/20", "10/10"]
        )
    ]

    // MARK: - 判定

    /// 某个时刻所在自然日是否工作日。
    ///
    /// 顺序**先查表、后看星期**（docs/31 §接口 3）：调休上班日恒为工作日、放假日恒为休息日，
    /// 查不到才按 ISO 星期判定。`calendar` 决定「哪一天」与「星期几」（时区语义在这里生效）。
    static func isWorkday(
        _ date: Date,
        workdays: Set<Int>,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        let year = calendar.component(.year, from: date)
        if let table = holidayTables[year] {
            let key = dayKey(of: date, calendar: calendar)
            if table.makeupWorkdays.contains(key) { return true }
            if table.holidays.contains(key) { return false }
        }
        return workdays.contains(isoWeekday(of: date, calendar: calendar))
    }

    /// manifest `workdays`（`[String]`，ISO 编号）→ 工作日集合。
    ///
    /// 坏值**逐项忽略**（非整数、`"0"` / `"8"` 这类越界值）；空表或全坏值 → `defaultWorkdays`
    /// （同 `ProgressCalculator.resolveScopes` 的「配置被改坏不该让界面空白」口径）。
    static func resolveWorkdays(from raw: [String]) -> Set<Int> {
        let parsed = Set(raw.compactMap(Int.init).filter { weekdayRange.contains($0) })
        return parsed.isEmpty ? defaultWorkdays : parsed
    }

    /// `workStart` / `workEnd` 配置 → 可用的（上班, 下班）。
    ///
    /// 口径（docs/31 §接口 3；越界处置经 2026-10-01 T2 审查裁定）：`nil`（未配置）先取 manifest
    /// 默认（9 / 18）；随后**任一值不在 `workHourRange`（0…23）内即整体回落默认 `(9, 18)`——
    /// 不夹取**（把手改坏值 `99` 夹成 23 会得到「有效但荒谬」的 9–23 班，回落默认更可预期，
    /// 与「非法一律回落」的既定容错口径一致）；两值都在区间内但 `end ≤ start`（相等或倒挂）
    /// 同样回落默认。返回值恒满足 `0 ≤ start < end ≤ 23`，因此后续的时间边界构造不可能倒挂。
    static func resolveWorkHours(start: Int?, end: Int?) -> (start: Int, end: Int) {
        let resolvedStart = start ?? defaultWorkStartHour
        let resolvedEnd = end ?? defaultWorkEndHour
        guard workHourRange.contains(resolvedStart),
              workHourRange.contains(resolvedEnd),
              resolvedEnd > resolvedStart
        else {
            return (defaultWorkStartHour, defaultWorkEndHour)
        }
        return (resolvedStart, resolvedEnd)
    }

    /// `Calendar.component(.weekday)`（1 = 周日 … 7 = 周六）→ **ISO**（1 = 周一 … 7 = 周日）。
    ///
    /// **全文件唯一的编号换算点**：`(周日 + 5) % 7 + 1` 把两套编号对齐——
    /// 周日 1 → 7、周一 2 → 1、周六 7 → 6。别处一律只拿 ISO 编号。
    private static func isoWeekday(of date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7 + 1
    }

    /// 表键 `"M/d"`（无前导零；按注入日历的年月日分量取，时区语义与判定一致）。
    private static func dayKey(of date: Date, calendar: Calendar) -> String {
        "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))"
    }

    // MARK: - 今天

    /// 「今天」行的四态（docs/31 §做法 机制二：文案由视图从这里派生）。
    enum TodayState: Equatable {
        /// 非工作日（周末 / 放假日；调休上班日不落这一态）。
        case restDay
        /// 工作日、现在 < 上班：距上班还有 `minutes` 分钟。
        case beforeStart(minutes: Int)
        /// 工作日、上班 ≤ 现在 < 下班：距下班还有 `minutesToEnd` 分钟。
        case working(minutesToEnd: Int)
        /// 工作日、现在 ≥ 下班。
        case afterEnd
    }

    /// 「今天」行的状态。分钟数按**整分钟截断**（`Calendar` 分量差，不按秒手算）。
    /// 上下班小时先经 `resolveWorkHours` 归一（坏配置在此也回落默认，不产生倒挂边界）。
    static func todayState(
        now: Date,
        workdays: Set<Int>,
        workStartHour: Int,
        workEndHour: Int,
        calendar: Calendar
    ) -> TodayState {
        guard isWorkday(now, workdays: workdays, calendar: calendar) else { return .restDay }
        let hours = resolveWorkHours(start: workStartHour, end: workEndHour)
        guard let start = hourBoundary(hours.start, on: now, calendar: calendar),
              let end = hourBoundary(hours.end, on: now, calendar: calendar)
        else {
            // 正常参数不可达的兜底（`Calendar` 推不出当天的整点边界）：宁可显示「已下班」，
            // 也不显示一个错误的倒计时。
            return .afterEnd
        }

        if now < start {
            let minutes = calendar.dateComponents([.minute], from: now, to: start).minute ?? 0
            return .beforeStart(minutes: max(0, minutes))
        }
        if now < end {
            let minutes = calendar.dateComponents([.minute], from: now, to: end).minute ?? 0
            return .working(minutesToEnd: max(0, minutes))
        }
        return .afterEnd
    }

    /// 「今天」的工作时长完成比例，落在 `0...1`：休息日 / 上班前 = 0，下班及以后 = 1，
    /// 班内 = 已过整分钟 / 当班总整分钟（9–18 班的正午 = 180/540 = 1/3）。
    ///
    /// 这是 **spanStats 分子的「今天」那一份**（docs/31 §已知限制 3：进度条分子含今天的
    /// 部分完成，而「剩 N 天」只数整天——两套口径并存是刻意的）。
    static func todayFraction(
        now: Date,
        workdays: Set<Int>,
        workStartHour: Int,
        workEndHour: Int,
        calendar: Calendar
    ) -> Double {
        guard isWorkday(now, workdays: workdays, calendar: calendar) else { return 0 }
        let hours = resolveWorkHours(start: workStartHour, end: workEndHour)
        guard let start = hourBoundary(hours.start, on: now, calendar: calendar),
              let end = hourBoundary(hours.end, on: now, calendar: calendar)
        else { return 0 }

        if now <= start { return 0 }
        if now >= end { return 1 }

        let total = calendar.dateComponents([.minute], from: start, to: end).minute ?? 0
        guard total > 0 else { return 0 }
        let elapsed = calendar.dateComponents([.minute], from: start, to: now).minute ?? 0
        return min(max(Double(elapsed) / Double(total), 0), 1)
    }

    // MARK: - 区间统计

    /// 某个时间尺度的**工作日**统计（docs/31 §接口 3；调用方传 `.week` / `.month` / `.quarter`
    /// / `.year`——`.day` 由 `todayState` / `todayFraction` 承担）。
    ///
    /// - 区间取 `ProgressCalculator.interval(for:now:calendar:)`（半开 `[start, end)`；周起止随
    ///   日历 `firstWeekday`，季度与跨年边界由它保证——这里**不手写日期**）；
    /// - `progress` = （今天**之前**的工作日数 + 今天是工作日时的 `todayFraction`）/ 区间工作日
    ///   总数；总数为 0（如 2026 春节假期整周）→ `0`（不除零、不返回 NaN）；
    /// - `remainingWorkdays` = 今天**之后**（不含今天）仍在区间内的工作日个数。
    static func spanStats(
        scope: ProgressCalculator.Scope,
        now: Date,
        workdays: Set<Int>,
        workStartHour: Int,
        workEndHour: Int,
        calendar: Calendar
    ) -> (progress: Double, remainingWorkdays: Int) {
        guard let interval = ProgressCalculator.interval(for: scope, now: now, calendar: calendar) else {
            return (0, 0)
        }

        let today = calendar.startOfDay(for: now)
        var total = 0
        var completedBeforeToday = 0
        var remainingAfterToday = 0

        var cursor = calendar.startOfDay(for: interval.start)
        while cursor < interval.end {
            if isWorkday(cursor, workdays: workdays, calendar: calendar) {
                total += 1
                if cursor < today { completedBeforeToday += 1 }
                if cursor > today { remainingAfterToday += 1 }
            }
            // 逐日推进（整年最多 366 次）；推进失败即停——不冒死循环的风险。
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }

        let todayIsWorkday = isWorkday(today, workdays: workdays, calendar: calendar)
        let numerator = Double(completedBeforeToday)
            + (todayIsWorkday
                ? todayFraction(
                    now: now, workdays: workdays,
                    workStartHour: workStartHour, workEndHour: workEndHour, calendar: calendar
                )
                : 0)
        let progress = total > 0 ? numerator / Double(total) : 0
        return (progress, remainingAfterToday)
    }

    // MARK: - 私有工具

    /// 某天的整点小时边界（先 `startOfDay` 再加小时——跨 DST 的一天由 `Calendar` 语义保证）。
    private static func hourBoundary(_ hour: Int, on date: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .hour, value: hour, to: calendar.startOfDay(for: date))
    }
}
