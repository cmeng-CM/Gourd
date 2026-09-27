//
//  ProgressCalculator.swift
//  Gourd 内置模块 · 日/周/月/季/年进度算法（P1 批次 / T4）
//
//  09 §5.3 的算法口径：`Calendar.dateInterval(of:for:)` 取区间（`.day` / `.weekOfYear` /
//  `.month` / `.year`），`elapsed / total` 得比例；季度按 1–3 / 4–6 / 7–9 / 10–12 月自定义。
//  **不手算天数**——闰年、跨年、时区与 DST 一律交给 `Calendar`。
//
//  纯函数、无 UI 依赖：日历与「现在」都可注入（单测传固定 `now` + 固定时区日历），
//  默认值 `Calendar.autoupdatingCurrent`（09 §5.3 的边界要求：用户改系统时间 / 时区要跟着变）。
//

import Foundation

/// 某个时间尺度在 `now` 所在自然区间里的完成比例。
enum ProgressCalculator {
    /// 五种时间尺度。`rawValue` 同时是 manifest `visibleScopes` 的取值（09 §5.3）；
    /// 声明顺序即界面上的展示顺序。
    enum Scope: String, CaseIterable, Sendable {
        case day
        case week
        case month
        case quarter
        case year
    }

    /// `now` 所在区间的完成比例，落在 `0...1`。
    ///
    /// 区间由 `now` 自己派生，正常取值必在区间内；钳制只为系统时钟跳变兜底（不崩、不返回负数）。
    static func progress(
        for scope: Scope,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Double {
        guard let interval = interval(for: scope, now: now, calendar: calendar),
              interval.duration > 0
        else { return 0 }
        return min(max(now.timeIntervalSince(interval.start) / interval.duration, 0), 1)
    }

    /// `now` 所在尺度的自然区间（半开 `[start, end)`）。
    ///
    /// | scope | 区间来源 |
    /// |---|---|
    /// | `day` | `.day` |
    /// | `week` | `.weekOfYear`——起止随日历的 `firstWeekday`（周一 / 周日起首各随其便，不假定周一） |
    /// | `month` | `.month` |
    /// | `quarter` | 自定义：1–3 / 4–6 / 7–9 / 10–12 月 |
    /// | `year` | `.year` |
    ///
    /// 季度也**不手写日期**：先取该季度首月的 `.month` 区间，再加 3 个月得结束边界，
    /// 因此跨年（Q4 → 次年 1 月 1 日）与时区语义仍由 `Calendar` 保证。
    static func interval(
        for scope: Scope,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> DateInterval? {
        switch scope {
        case .day:
            return calendar.dateInterval(of: .day, for: now)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now)
        case .month:
            return calendar.dateInterval(of: .month, for: now)
        case .year:
            return calendar.dateInterval(of: .year, for: now)
        case .quarter:
            return quarterInterval(containing: now, calendar: calendar)
        }
    }

    /// Q1 = 1–3 月、Q2 = 4–6 月、Q3 = 7–9 月、Q4 = 10–12 月（09 §5.3）。
    private static func quarterInterval(containing now: Date, calendar: Calendar) -> DateInterval? {
        var components = calendar.dateComponents([.year, .month], from: now)
        components.month = ((components.month ?? 1) - 1) / 3 * 3 + 1
        guard let firstMonth = calendar.date(from: components),
              let monthInterval = calendar.dateInterval(of: .month, for: firstMonth),
              let end = calendar.date(byAdding: .month, value: 3, to: monthInterval.start)
        else { return nil }
        return DateInterval(start: monthInterval.start, end: end)
    }
}
