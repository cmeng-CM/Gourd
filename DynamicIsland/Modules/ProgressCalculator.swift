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
//  2026-09-27 形态定稿后新增两个纯函数（09 §5.3 呈现行）：
//  - `resolveScopes(from:)`：manifest 的 `visibleScopes` 默认值 → 展示尺度（默认 **日 + 年**）；
//  - `remaining(for:now:calendar:)`：剩余量清单的主信息，只给结构化数值（value + unit），文案归视图。
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

    /// 剩余量的计量单位。`rawValue` 同时是文案 key 的后缀（`module.progress.unit.<rawValue>`），
    /// 因此**只加不改**；具体文案由视图拼（09 §5.3 呈现行：剩余量只给结构化数值）。
    enum RemainingUnit: String, Sendable {
        case day
        case hour
        case minute
    }

    /// 未配置 `visibleScopes` 时的默认展示尺度：**日 + 年**（09 §5.3 呈现行定稿）。
    static let defaultVisibleScopes: [Scope] = [.day, .year]

    /// `manifest.config.properties["visibleScopes"].default` → 实际展示的尺度（纯函数）。
    ///
    /// 规则（09 §5.3 定稿）：
    /// - 默认（`nil` / 不是 list / 空列表 / 全是未知取值）→ `defaultVisibleScopes`（日 + 年）；
    /// - 未知取值**逐项忽略**（配置被改坏不该让面板空白，07 §2 规则 4 的「回落默认、不崩」口径）；
    /// - 顺序按输入（用户给的先后即展示先后）；重复项去重（`ForEach(id:)` 的 id 必须唯一）。
    static func resolveScopes(from value: ConfigValue?) -> [Scope] {
        guard case .strings(let raw)? = value else { return defaultVisibleScopes }
        var seen: Set<Scope> = []
        let declared = raw.compactMap(Scope.init(rawValue:)).filter { seen.insert($0).inserted }
        return declared.isEmpty ? defaultVisibleScopes : declared
    }

    /// 距离 `scope` 区间结束还剩多久——**只返回结构化数值**，文案由视图拼（09 §5.3）。
    ///
    /// 分档规则：
    /// | 剩余量 | 返回 | 视图里的形态 |
    /// |---|---|---|
    /// | ≥ 1 天 | 天数（**向上取整**：整日之外还有余量就算一天） | 「剩 98 天」 |
    /// | 1 小时 ≤ r < 1 天 | 整点小时数（分钟余量由视图从同一区间取） | 「剩 5 小时 30 分钟」 |
    /// | < 1 小时 | 分钟（**截断**，至少 1） | 「剩 59 分钟」 |
    ///
    /// 天数/小时数/分钟数一律用 `Calendar` 做**日期分量差**（不按 86400 秒手算）：
    /// 夏令时的一天不等于 24 小时，按秒算会在切换日差一天（09 §5.3 的「不手算」口径）。
    /// 「向上取整」也落在日期分量上：先取整日数，再加一天仍早于区间结束就是有余量。
    static func remaining(
        for scope: Scope,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> (value: Int, unit: RemainingUnit) {
        guard let end = interval(for: scope, now: now, calendar: calendar)?.end else {
            // 区间取不到（正常取值不可达，见 `progress(for:)`）：给「至少 1 分钟」的兜底，
            // 面板不显示 0（与下面 < 1 小时档的「至少 1」一致）。
            return (1, .minute)
        }

        let wholeDays = calendar.dateComponents([.day], from: now, to: end).day ?? 0
        if wholeDays >= 1 {
            let boundary = calendar.date(byAdding: .day, value: wholeDays, to: now)
            let hasRemainder = boundary.map { $0 < end } ?? false
            return (wholeDays + (hasRemainder ? 1 : 0), .day)
        }

        let wholeHours = calendar.dateComponents([.hour], from: now, to: end).hour ?? 0
        if wholeHours >= 1 {
            return (wholeHours, .hour)
        }

        let wholeMinutes = calendar.dateComponents([.minute], from: now, to: end).minute ?? 0
        return (max(1, wholeMinutes), .minute)
    }

    /// 小时档的（整点小时, 余分钟）**成对**取值。
    ///
    /// 两者必须来自同一次取整：早先的实现是 `remaining()` 取整点小时、另一个私有函数取总分钟，
    /// 于是出现「剩 13 小时 826 分钟」这种把**总分钟当余数**的显示（826 = 13×60 + 46）。
    /// 现在统一在这里算：`hours = 总分钟 / 60`、`minutes = 总分钟 % 60`（0…59）。
    static func remainingHoursAndMinutes(
        for scope: Scope,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> (hours: Int, minutes: Int) {
        guard let end = interval(for: scope, now: now, calendar: calendar)?.end else {
            return (0, 1)
        }
        let totalMinutes = calendar.dateComponents([.minute], from: now, to: end).minute ?? 0
        let clamped = max(0, totalMinutes)
        return (clamped / 60, clamped % 60)
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
