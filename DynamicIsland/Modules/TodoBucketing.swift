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
//  TodoBucketing.swift
//  Gourd 内置模块 · 待办分类与计数（P1 批次 / T5）
//
//  纯逻辑：没有 EventKit / SwiftUI 依赖——输入是**已解析**的提醒条目（标识 / 标题 / 到期日可空 /
//  是否已完成 / 完成日期可空 / 所属列表名），加上注入的 `Calendar` 与 `now`；
//  输出三个类别各自的成员与 `(已办, 总量)`。取数与写回在 `TodosModule`（`TodoStore`），
//  本文件只回答「归哪一类、算几个」——因此日历 / 时刻都能注入，单测可复现。
//
//  分类口径（2026-09-28 用户定稿）：
//
//  | 类别 | 成员判据 |
//  |---|---|
//  | 今日 | ① 到期时间落在今天（`now` 所在自然日）；② **已过期**（到期 < 今天 00:00）且**未完成**；③ **今天完成的** |
//  | 本周 | 到期时间落在 `dateInterval(of: .weekOfYear, for: now)` 内，**再加今日的全部成员**（见下 2） |
//  | 所有 | **全集**：含无到期时间的、含未来很久的、含已完成的 |
//
//  **无到期时间 → 只出现在「所有」**，不进今日 / 本周。
//
//  三处刻意写下、避免日后被当 bug「修掉」的口径：
//
//  1. **今日与本周重叠计数是刻意的**：本周是更大的窗口，今日的成员一律**再次**出现在本周
//     （同一条目在两个环里各算一次，三个类别不做互斥分割）。
//  2. **本周 ⊇ 今日**：除「到期落在一周区间内」外，今日的成员也并入本周——包括「已过期未完成」
//     这类到期时间落在**本周之前**的条目。否则嵌套关系（今日 ⊆ 本周 ⊆ 所有）会在逾期条目上被破坏，
//     而设计原文明确要求「今日重复出现在本周」。
//  3. 「今天完成的也归今日」**只对有到期时间的条目生效**：与硬规则「无到期时间只进所有」相抵时，
//     以后者为准（后者是设计里单列的一条，且无歧义）。
//
//  `已办` 一律 = 该类别的成员里 `isCompleted == true` 的条数，`总量` = 成员条数——
//  分子分母同源，不另立一套「应办」口径。
//
//  **P1 / T1 增量**（2026-09-29，docs/18-p1-todos-and-order.md）：在本文件内加**四视图过滤**
//  （`TodoViewKind` + `items(in:from:now:calendar:)`）供展开面板取数。它与上面的三环口径
//  **并存且互不改动**（三环仍服务首页块）：三环 = 聚合计数（今日与本周刻意重叠），
//  四视图 = 清单过滤（互斥、含「已完成」档）。两条口径的详细判据各见对应小节。
//

import Foundation

enum TodoBucketing {
    /// 三个类别。`rawValue` 同时是标签文案 key 的后缀（`module.todos.scope.<rawValue>`），
    /// 因此**只加不改**；声明顺序即环的展示顺序（今日 → 本周 → 所有）。
    enum Bucket: String, CaseIterable, Sendable {
        case today
        case week
        case all

        /// 标签文案的本地化 key。
        var labelKey: String { "module.todos.scope.\(rawValue)" }
    }

    /// 一条待办（已归一化，与 EventKit 解耦）。
    ///
    /// `dueDate == nil` 即「无到期时间」——它定义了「只进所有」这一档；
    /// `completionDate` 只在 `isCompleted == true` 时有意义（未完成条目上的残留完成时刻不参与判定）。
    struct Item: Equatable, Identifiable, Sendable {
        /// 提醒的稳定标识（生产路径给 `EKReminder.calendarItemIdentifier`）。
        let id: String
        let title: String
        /// 到期时刻；无到期时间时为 nil。
        let dueDate: Date?
        let isCompleted: Bool
        let completionDate: Date?
        /// 所属列表名（提醒的日历标题），空串表示取不到。
        let listName: String

        init(
            id: String,
            title: String,
            dueDate: Date? = nil,
            isCompleted: Bool = false,
            completionDate: Date? = nil,
            listName: String = ""
        ) {
            self.id = id
            self.title = title
            self.dueDate = dueDate
            self.isCompleted = isCompleted
            self.completionDate = completionDate
            self.listName = listName
        }
    }

    /// 一个类别的结果：成员（已排序）+ 派生计数。
    struct BucketResult: Equatable {
        let bucket: Bucket
        /// 成员，顺序见 `TodoBucketing.sorted(_:)`（未完成在前、已完成置最后）。
        let items: [Item]

        /// 已办条数（分子）。
        var completed: Int { items.reduce(0) { $0 + ($1.isCompleted ? 1 : 0) } }
        /// 总量（分母）。
        var total: Int { items.count }
        /// 环的 `trim` 进度；总量为 0 时为 0（环为空）。
        var progress: Double { total == 0 ? 0 : Double(completed) / Double(total) }
        /// 环心文案（`已办/总量`）。**先拼 String 再给 `Text`**——走 `Text(_: String)` 的
        /// verbatim 重载，不会把 `3/5` 当成本地化 key 去查表（同 `ProgressText` 的口径）。
        var counterText: String { "\(completed)/\(total)" }
    }

    /// 三个类别的完整结果。
    struct Summary: Equatable {
        let today: BucketResult
        let week: BucketResult
        let all: BucketResult

        /// 展示顺序：今日 → 本周 → 所有（三环横排）。
        var ordered: [BucketResult] { [today, week, all] }

        func result(for bucket: Bucket) -> BucketResult {
            switch bucket {
            case .today: return today
            case .week: return week
            case .all: return all
            }
        }
    }

    /// 分类 + 排序 + 计数（唯一入口，纯函数）。
    ///
    /// - Parameters:
    ///   - items: 归一化后的条目（未完成 + 已完成混在一起，不要求有序）。
    ///   - now: 「今天」「本周」的基准时刻；默认当下。
    ///   - calendar: 定义自然日 / 周区间的日历（周起止随其 `firstWeekday`，不假定周一）；
    ///     默认 `.autoupdatingCurrent`（用户改系统时区 / 周起始日要跟着变）。
    static func classify(
        _ items: [Item],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Summary {
        let day = dayInterval(containing: now, calendar: calendar)
        let week = weekInterval(containing: now, calendar: calendar)

        var todayItems: [Item] = []
        var weekItems: [Item] = []
        for item in items {
            let isToday = belongsToToday(item, day: day)
            if isToday { todayItems.append(item) }
            // 本周 = 到期落在一周区间内 ∪ 今日的成员（后者含「已过期未完成」这类到期在本周之前的）。
            if isToday || belongsToWeek(item, week: week) { weekItems.append(item) }
        }

        return Summary(
            today: BucketResult(bucket: .today, items: sorted(todayItems)),
            week: BucketResult(bucket: .week, items: sorted(weekItems)),
            all: BucketResult(bucket: .all, items: sorted(items))
        )
    }

    // MARK: - 四视图过滤（P1 / T1）

    /// 展开面板左导航的四个视图（docs/18-p1-todos-and-order.md §接口与数据形状 3）。
    ///
    /// **嵌套在 `TodoBucketing` 里**（与 `Bucket` / `Item` / `BucketResult` 同一个命名空间，
    /// 调用点写 `TodoBucketing.TodoViewKind`）——不往全局命名空间再放一个 `TodoViewKind`。
    ///
    /// 与 `Bucket` 的关系：**两套口径互不替代、也不互改**——`Bucket`（今日 / 本周 / 所有）只服务
    /// 首页三环的聚合计数（今日与本周刻意重叠），本枚举服务展开面板的**清单过滤**：视图之间
    /// **互斥**（一条只出现在一个视图里），且多出「已完成」这一档（环没有它）。
    /// `rawValue` 即视图的稳定标识（`id`），声明顺序即左导航的展示顺序。
    enum TodoViewKind: String, CaseIterable, Identifiable, Sendable {
        case today
        case next7Days
        case all
        case completed

        var id: String { rawValue }
    }

    /// 按视图过滤（纯函数：`now` 与 `calendar` 必须注入，便于固定测试）。
    ///
    /// 口径逐条定死（docs/18 §接口与数据形状 3）：
    ///
    /// | 视图 | 成员判据 |
    /// |---|---|
    /// | `today` | 到期日落在 `[今天 00:00, 明天 00:00)` 且**未完成** |
    /// | `next7Days` | 到期日落在 `[今天 00:00, 今天 + 7 天 00:00)` 且**未完成** |
    /// | `all` | 全部**未完成**（**没有到期日的也算**） |
    /// | `completed` | 全部**已完成**（不论到期日 / 完成日） |
    ///
    /// 三处刻意写下、日后不要当 bug 改掉的口径：
    ///
    /// 1. **两个时间窗视图都只收未完成**——已完成的条目一律只在 `completed` 里；视图之间
    ///    **互斥**（与 `classify` 的三环刻意重叠相反，两者各自成立，不是同一套口径）。
    /// 2. **`next7Days` 不含「已过期未完成」**（到期 < 今天 00:00 的落不进区间）——它们只在
    ///    `all`（清单）里可见（docs/18 §已知限制 3）。
    /// 3. **区间是半开的**：到期恰好是**明天 00:00** 不算 `today`，恰好是**第 7 天 00:00**
    ///    不算 `next7Days`；边界判定复用本文件既有的 `contains`（`DateInterval.contains(_:)`
    ///    含 end 端点，只差一刻钟的边界会错一天）。
    ///
    /// 返回顺序沿用 `sorted(_:)`（与三环同一比较器）：未完成在前、按到期升序、无到期日最后；
    /// `completed` 里按完成时刻倒序——顺序稳定可复现，视图直接照画、不再重排。
    static func items(
        in view: TodoViewKind,
        from items: [Item],
        now: Date,
        calendar: Calendar
    ) -> [Item] {
        switch view {
        case .today:
            let day = dayInterval(containing: now, calendar: calendar)
            return sorted(items.filter { isOpen($0) && $0.dueDate.map { contains(day, $0) } == true })

        case .next7Days:
            let day = dayInterval(containing: now, calendar: calendar)
            // 七天窗从**今天 00:00** 起算（不是 now 起算）：今天已经过去的时段同样算在内。
            let end = calendar.date(byAdding: .day, value: 7, to: day.start) ?? day.end
            let window = DateInterval(start: day.start, end: end)
            return sorted(items.filter { isOpen($0) && $0.dueDate.map { contains(window, $0) } == true })

        case .all:
            // 无到期日期的也在这里（到期日不参与判定）。
            return sorted(items.filter(isOpen))

        case .completed:
            return sorted(items.filter { !isOpen($0) })
        }
    }

    /// 未完成（两个时间窗视图与 `all` 共用）。
    private static func isOpen(_ item: Item) -> Bool { !item.isCompleted }

    // MARK: - 成员判定

    /// 今日：到期在今天（含已完成）／已过期且未完成／今天完成的。
    ///
    /// 第 3 条是设计原文「今天完成的也归今日」的落点——它把「已过期但今天完成」这类
    /// 被第 2 条的「未完成」限定挡掉的条目接回来；无到期时间的条目在第一步就被排除。
    private static func belongsToToday(_ item: Item, day: DateInterval) -> Bool {
        guard let dueDate = item.dueDate else { return false }  // 无到期时间 → 只进「所有」
        if contains(day, dueDate) { return true }
        if !item.isCompleted, dueDate < day.start { return true }
        if item.isCompleted, let completionDate = item.completionDate, contains(day, completionDate) {
            return true
        }
        return false
    }

    /// 本周：仅按到期时间取（「今日的成员重复出现在本周」由 `classify` 侧的并集保证）。
    private static func belongsToWeek(_ item: Item, week: DateInterval) -> Bool {
        guard let dueDate = item.dueDate else { return false }
        return contains(week, dueDate)
    }

    /// 半开区间判定 `start ≤ date < end`。
    ///
    /// **不用 `DateInterval.contains(_:)`**：Foundation 的实现**含 end 端点**，而「到期时间恰好是
    /// 明天 00:00」会被它算进今天（边界错一天，且是提醒里最常见的边界）。
    private static func contains(_ interval: DateInterval, _ date: Date) -> Bool {
        date >= interval.start && date < interval.end
    }

    /// 自然日区间；`dateInterval` 取不到时用当天起点 + 1 天兜底（正常取值不可达，只为不崩）。
    private static func dayInterval(containing now: Date, calendar: Calendar) -> DateInterval {
        if let interval = calendar.dateInterval(of: .day, for: now) { return interval }
        let start = calendar.startOfDay(for: now)
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start) ?? start)
    }

    /// 周区间；起止随日历的 `firstWeekday`（周一 / 周日起首各随其便）。
    private static func weekInterval(containing now: Date, calendar: Calendar) -> DateInterval {
        if let interval = calendar.dateInterval(of: .weekOfYear, for: now) { return interval }
        let start = calendar.startOfDay(for: now)
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 7, to: start) ?? start)
    }

    // MARK: - 排序

    /// 清单顺序（视图直接用，因此定死在纯函数里、由单测钉住）：
    /// 1. **未完成在前、已完成置最后**（设计原文：已完成项排最后、置灰 + 删除线）；
    /// 2. 未完成内部按到期时间**升序**，无到期时间的排最后（它们只在「所有」里可见）；
    /// 3. 已完成内部按**完成时刻倒序**（刚完成的在前），无完成时刻的排最后；
    /// 4. 其余并列按（标题, id）字典序，保证顺序稳定、可复现。
    private static func sorted(_ items: [Item]) -> [Item] {
        items.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }

            if lhs.isCompleted {
                switch (lhs.completionDate, rhs.completionDate) {
                case let (left?, right?) where left != right: return left > right
                case (nil, .some): return false
                case (.some, nil): return true
                default: break
                }
            }

            switch (lhs.dueDate, rhs.dueDate) {
            case let (left?, right?) where left != right: return left < right
            case (nil, .some): return false
            case (.some, nil): return true
            default: break
            }

            return (lhs.title, lhs.id) < (rhs.title, rhs.id)
        }
    }
}
