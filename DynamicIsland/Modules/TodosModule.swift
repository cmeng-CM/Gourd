//
//  TodosModule.swift
//  Gourd 内置模块 · 待办（展开面板四视图 + 首页三环，P1 批次 / T5、T2）
//
//  形态定稿：
//  - 展开态（**P1 / T2 改版，2026-09-29**）= **左侧四视图导航**（今天 / 最近 7 天 / 清单 / 已完成，
//    竖排，每项 = 图标 + 文字 + 计数徽标）+ **右侧看板**（分组标题 + 行列表）；
//    当前视图是 **UI 局部 `@State`**（不进 Defaults），面板每次出现都回到「今天」。
//    2026-09-28 的第一版是「左侧竖排三个环（今日 / 本周 / 所有）+ 右侧该类别清单」——
//    环只能表达三个聚合量、找不到「已完成」，因此筛选器换成四视图（口径见 `TodoBucketing.TodoViewKind`
//    与 `TodoBucketing.items(in:from:now:calendar:)`）。
//    **三环与首页块一行不动**：`TodoScopeRing` 仍由首页块横排使用（`TodoHomeRingRow`），
//    `TodoRingPicker` / `TodoRingLayout` 原样留着（本批不再被展开面板使用，也不动它们）。
//  - 折叠态 = 图标 + **今日**的 `已办/总量`（自带 60s `TimelineView`，宿主不起定时器，与 progress 同口径）；
//  - **首页块**（P2 / T4）= **三环横排**（今日 / 本周 / 所有，复用展开 tab 的同一个 `TodoScopeRing`，
//    只把排布从竖排改成横排）+ 今日清单；清单按块宽**分档**（P2 / T3 改判：单阈值 220 → 三档
//    `>= 220` 完整行 / `>= 160` 紧凑行（只标题）/ `< 160` 只画三环，见 `TodosHomeBlockLayout`）；
//    块宽由宿主 `HomeStripLayoutMath` 分配（本批 180 ～ 240pt）；
//  - 分类与计数口径全在 `TodoBucketing`（纯函数，单测覆盖）——**三个 surface 共用同一份聚合**。

//
//  **取数是本模块自己的 `EKEventStore`**（取数这一条不改 `CalendarServiceProviding`，也不经 `CalendarManager`）：
//  上游 `fetchReminders(from:to:calendars:)` 只取**未完成且按 dueDate 过滤**的提醒，
//  拿不到「无到期时间的待办」，也拿不到「已完成」。本模块自己取两类：
//  - 未完成：`fetchReminders(matching: store.predicateForReminders(in: nil))`（跨所有列表，
//    **含无到期时间**）后再按 `isCompleted` 过滤（该谓词本身就含已完成的条目）；
//  - 已完成：`predicateForCompletedReminders(withCompletionDateStarting: 最近 7 天起点, ending: nil, calendars: nil)`。
//
//  **可增删**（2026-09-28 用户反馈「待办里面要可以增删待办内容」——这是**真数据**）：
//  - 新增：输入行（标题 + 今天 / 明天 / 无日期，**不引入 `DatePicker`**）→ `save(EKReminder, commit: true)`，
//    写进 `defaultCalendarForNewReminders()`（取不到时兜到第一个可用列表，见 `TodoComposer.targetList`）；
//  - 删除：每行 hover 的垃圾桶 → **确认对话框** → `store.remove(reminder, commit: true)`；
//  - 两者失败都回显**一行**提示（`module.todos.writeFailed`，细节进日志），不静默、不崩、**不请求新权限**
//    （未授权时只显示授权提示：新增与删除的入口都不渲染）。
//
//  **写回优先级走管理器侧的入口**（P1 / T2，[docs/18](../../docs/18-p1-todos-and-order.md) §接口与数据形状 4）：
//  点行上的优先级胶囊 → `TodoStore.cyclePriority` **先乐观更新 UI**，再调
//  `CalendarManager.setReminderPriority(_:priority:)`（内部是 `CalendarService` 既有的
//  提醒写回链：同一个 `EKEventStore` + `commit: true`，不新开 store）；失败 → 撤销乐观值 + 记模块日志，
//  不静默、不回显假成功。**提醒只多写 `priority` 一个字段**，其余字段保持只读。
//
//  **7 天窗口是刻意的**（[13](../../docs/13-runtime-kernel.md) D-21）：EventKit 没有「取全部已完成」的
//  高效谓词，不加窗口会让「所有」环被陈年已完成条目拖成历史总量（装完就是几百条已完成），
//  首次取数也变慢；而今日 / 本周最早也只到 6 天前，7 天窗口**完整覆盖**这两个类别的分子。
//
//  授权：**不在模块初始化 / 视图出现时请求权限**（本项目的「每次安装最多问一次 / 不打扰」策略）。
//  只有 `EKEventStore.authorizationStatus(for: .reminder) == .fullAccess` 才取数；否则视图显示提示 +
//  「请求访问提醒」（**点击才** `requestFullAccessToReminders()`）+「打开系统设置」两个按钮。
//
//  文案走 Localizable key（06 §3.3 R5）：`module.todos.name` / `.summary` / `.scope.<bucket>` /
//  `.empty` / `.overdue` / `.permission` / `.requestAccess` / `.openSettings`，增删另加
//  `.add` / `.addPlaceholder` / `.dueToday` / `.dueTomorrow` / `.dueNone` /
//  `.delete` / `.deleteConfirm` / `.cancel` / `.writeFailed`；
//  P1 / T2 另加四视图的 `.view.<todoViewKind>`（今天 / 最近 7 天 / 清单 / 已完成）、
//  优先级的 `.priority.<todoPriority>`（无 / 低 / 中 / 高）、`.priorityHint`、`.completedEmpty`。
//  **颜色**：面板是黑底、系统外观可为浅色——本模块内所有文字与图标一律显式浅色
//  （`Color.white` / `.white.opacity(...)`），不用 `.primary` / `.secondary`（同 ProgressModule 的教训）。
//

import AppKit
import EventKit
import SwiftUI

// MARK: - TodoWriteFailure

/// 写回失败的形态（面板统一显示一行 `module.todos.writeFailed`，细节进日志）。
enum TodoWriteFailure: Equatable {
    /// 标题去空白后为空（纯函数已拦，这里是写库前的双保险）。
    case emptyTitle
    /// 没有可写入的提醒列表：`defaultCalendarForNewReminders()` 为 nil 且 `calendars(for: .reminder)` 为空。
    case noRemindersList
    /// EventKit 抛错（`save` / `remove`）。
    case storage(String)

    /// 进日志的那一行描述。
    var logDescription: String {
        switch self {
        case .emptyTitle: return "标题为空"
        case .noRemindersList: return "没有可用的提醒列表（默认列表与可用列表都取不到）"
        case .storage(let description): return description
        }
    }
}

// MARK: - TodoComposer（新增的校验与构造，纯函数）

/// 新增待办的**校验与构造**：把「用户敲的标题 + 日期三选一」变成「写库所需的字段」，或给出拒绝理由。
///
/// 刻意**不依赖 EventKit / SwiftUI**（同 `TodoBucketing` 的口径）：`EKReminder` 建不出来的地方
/// 也能把「标题空白 → 不建」「今天 / 明天 → 当天 00:00 的 `[年,月,日]`」这些口径钉在单测里。
///
/// **日期口径**：只有三个选项（今天 / 明天 / 无日期），**不引入 `DatePicker`**——那一刻的交互成本
/// （弹层、日历网格、与面板的键盘焦点冲突）与收益不匹配。给到的 `DateComponents` **只带
/// 年 / 月 / 日**：与系统「提醒」App 的全天条目同形，读回时 `TodoDueLabel` 按自然日判定，
/// 落在今天就显示「今天」、其余显示 `M/D`（不再显示时刻，见该类型的注释）。
enum TodoComposer {
    /// 日期三选一。`rawValue` 同时是文案 key 的后缀（`module.todos.due<Title>`），因此**只加不改**。
    enum DueOption: String, CaseIterable, Sendable {
        case today
        case tomorrow
        case none

        /// 选项文案的本地化 key。
        var labelKey: String {
            switch self {
            case .today: return "module.todos.dueToday"
            case .tomorrow: return "module.todos.dueTomorrow"
            case .none: return "module.todos.dueNone"
            }
        }
    }

    /// 校验结果：要么可以建（标题已去空白 + 可选到期组件），要么拒绝（标题去空白后为空）。
    enum Draft: Equatable {
        case create(title: String, dueDateComponents: DateComponents?)
        case rejectEmptyTitle
    }

    /// 校验并构造草稿（纯函数）。
    ///
    /// - 标题：去掉**首尾**空白与换行后作为最终标题；去完为空则 `.rejectEmptyTitle`
    ///   （不建提醒——空标题的系统提醒在「提醒」App 里是一行看不见的条目，等于脏数据）。
    /// - 日期：`.today` / `.tomorrow` 给**当天 00:00** 的年月日组件（全天口径）；`.none` 给 nil
    ///   （无到期时间——按 `TodoBucketing` 的硬规则它只出现在「所有」里，这是刻意的）。
    static func draft(
        title: String,
        due: DueOption,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Draft {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .rejectEmptyTitle }

        switch due {
        case .none:
            return .create(title: trimmed, dueDateComponents: nil)
        case .today, .tomorrow:
            // 「明天」按 `now + 1 天` 再取当天起点（而不是「今天起点 + 1 天」）：
            // 夏令时切换日两者不是同一天，前者才是用户说的"明天"。
            let base = due == .today
                ? now
                : (calendar.date(byAdding: .day, value: 1, to: now) ?? now)
            let components = calendar.dateComponents([.year, .month, .day], from: calendar.startOfDay(for: base))
            return .create(title: trimmed, dueDateComponents: components)
        }
    }

    /// 目标列表的兜底选择：`defaultCalendarForNewReminders()` **可以为 nil**（没设默认列表 / 提醒库异常），
    /// 此时退到第一个可用列表（`calendars(for: .reminder)` 的第一个）；都没有 → nil，
    /// 调用方据此判为失败并回显一行提示，而不是把条目塞进一个猜出来的列表。
    ///
    /// 泛型是为了让单测用轻量模型（`String` / `Int`）钉住这段选择逻辑，不必造 `EKCalendar`。
    static func targetList<T>(defaultList: T?, availableLists: [T]) -> T? {
        if let defaultList { return defaultList }
        return availableLists.first
    }
}

// MARK: - TodoPriority（优先级的四档表示与双向映射，纯函数）

/// 优先级的**四档显示形态**（[docs/18](../../docs/18-p1-todos-and-order.md) §接口与数据形状 3）：
/// 无 / 低 / 中 / 高。**不做九档 UI、不做优先级排序**（列表顺序仍由 `TodoBucketing` 定）。
///
/// 与 EventKit `EKReminder.priority`（0…9）的映射见 `priority(fromEventKit:)` / `eventKitValue(of:)`：
/// 0 = 无、1…4 = 高、5 = 中、6…9 = 低——分档与上游 `Priority.init(from:)`（`EventModel.swift`）一致，
/// 只多一档 0 = 无（上游那个 `init?` 把 0 与表外值都当"无值"返回 nil，本模块要显示「无」这一档）。
///
/// `rawValue` 同时是文案 key 的后缀（`module.todos.priority.<rawValue>`），因此**只加不改**；
/// 声明顺序按 docs/18 的词汇表（无 / 高 / 中 / 低）——**点击的循环顺序另有一条**，见 `cycle`。
enum TodoPriority: String, CaseIterable, Sendable {
    case none
    case high
    case medium
    case low

    /// 文案 key（`rawValue` 派生，只加不改）。
    var labelKey: String { "module.todos.priority.\(rawValue)" }

    /// 点胶囊的**循环顺序**：无 → 低 → 中 → 高 → 无。
    ///
    /// 单列成表而**不依赖 `allCases` 的声明顺序**：声明顺序是"词汇表"（只加不改），
    /// 循环是交互口径，两者各自钉在用例里（`allCases` 变了不该悄悄改掉点击行为）。
    static let cycle: [TodoPriority] = [.none, .low, .medium, .high]

    /// EventKit 的 `priority`（0…9）→ 四档。
    ///
    /// 表外的值（负值 / > 9；EventKit 不会给）一律按「无」处理——防御式，不崩、不猜档位。
    static func priority(fromEventKit value: Int) -> TodoPriority {
        switch value {
        case 1...4: return .high
        case 5: return .medium
        case 6...9: return .low
        default: return .none
        }
    }

    /// 四档 → EventKit 的 `priority`：none → 0、high → 1、medium → 5、low → 9。
    ///
    /// 每档取**区间端点**（1 / 5 / 9）而不是区间里的随意值：这样
    /// `priority(fromEventKit: eventKitValue(of: p)) == p` 对四档一律成立（双向可逆，用例钉住）。
    static func eventKitValue(of priority: TodoPriority) -> Int {
        switch priority {
        case .none: return 0
        case .high: return 1
        case .medium: return 5
        case .low: return 9
        }
    }

    /// 循环的下一档（无 → 低 → 中 → 高 → 无）。
    static func cycled(from current: TodoPriority) -> TodoPriority {
        guard let index = cycle.firstIndex(of: current) else { return cycle[0] }
        return cycle[(index + 1) % cycle.count]
    }

    /// 写回闸门：目标与当前**同级**时**不写**（先比对当前值——幂等）。
    static func shouldWrite(current: TodoPriority, target: TodoPriority) -> Bool {
        current != target
    }
}

/// 一次写回的**计划**：目标档位 + 要写进 EventKit 的 `priority`。
struct TodoPriorityStep: Equatable {
    let priority: TodoPriority
    let eventKitValue: Int
}

/// 优先级的**乐观层**（纯状态机：无 EventKit / SwiftUI 依赖，单测可直接驱动）。
///
/// 两个字典的分工：
/// - `baseline`：**库里读回的真值**（`TodoStore.refresh()` 每次重取后整体重建）；
/// - `pending`：用户刚点出、**尚未被库确认**的乐观值。
///
/// 显示值 = `pending[id] ?? baseline[id] ?? .none`——因此「写回失败 → 回滚」就是 `clear(_:)`
/// 把乐观值撤掉（显示值立刻退回真值）；「写回成功」也走同一个 `clear(_:)`：随后的重取会把真值
/// 写进 `baseline`，清掉乐观值即等于显示真值（失败信号「写回失败后 UI 停在错误值」的判据）。
struct TodoPriorityOverlay: Equatable {
    private(set) var baseline: [String: TodoPriority] = [:]
    private(set) var pending: [String: TodoPriority] = [:]

    /// 显示值：视图与写回闸门**都**读它，「当前是什么档位」只有这一处口径。
    func value(for id: String) -> TodoPriority { pending[id] ?? baseline[id] ?? .none }

    /// 请求把某条写到指定档位；与当前**同级**时返回 nil（**不写回、也不动 UI**：重复请求天然幂等）。
    mutating func beginWrite(_ id: String, to target: TodoPriority) -> TodoPriorityStep? {
        guard TodoPriority.shouldWrite(current: value(for: id), target: target) else { return nil }
        pending[id] = target
        return TodoPriorityStep(
            priority: target,
            eventKitValue: TodoPriority.eventKitValue(of: target)
        )
    }

    /// 点一下胶囊：按 无 → 低 → 中 → 高 → 无 取下一档并**先乐观更新** UI。
    mutating func beginCycle(for id: String) -> TodoPriorityStep? {
        beginWrite(id, to: TodoPriority.cycled(from: value(for: id)))
    }

    /// 清掉乐观值（写回成功与失败都走这里，语义差别见类型注释）。
    mutating func clear(_ id: String) { pending[id] = nil }

    /// 重取后重建基线（**保留 `pending`**：写回还在飞时不能被一次重取抹掉乐观值）。
    mutating func rebuild(from values: [String: TodoPriority]) { baseline = values }
}

// MARK: - TodoStore

/// 优先级写回的执行体：`reminderID` + 目标 EventKit 值 → 成功与否。
///
/// 默认实现是**管理器侧的入口** `CalendarManager.setReminderPriority(_:priority:)`
/// （docs/18 §接口与数据形状 4：写回由 `CalendarManager` 提供，模块只做映射与乐观 UI）。
/// 抽成可注入的接缝是为了让单测用**计数型假体**覆盖「同名同档不重复写回」与「失败回滚」，
/// 而不必往用户真实的提醒库里写数据。
typealias TodoPriorityWriter = @MainActor (_ reminderID: String, _ eventKitPriority: Int) -> Bool

/// 待办的取数 / 写回 / 变更订阅。**模块自己持有** `EKEventStore`（理由见文件头）。
///
/// 只做「拿数据 + 写回」，分类交给 `TodoBucketing`、呈现交给视图；因此这里不持有任何选择态
/// （当前视图是面板的 `@State`，优先级乐观值在这里，见 `priorityOverlay`）。
@MainActor
final class TodoStore: ObservableObject {
    /// 已完成提醒的取数窗口（天）。窗口口径与理由见文件头（[13](../../docs/13-runtime-kernel.md) D-21）。
    static let completedWindowDays = 7

    /// 归一化后的条目（未完成 + 窗口内已完成）。
    @Published private(set) var items: [TodoBucketing.Item] = []
    /// 优先级的**乐观层**（读回的真值 + 用户刚点出的未确认值）。视图读 `priority(for:)`。
    @Published private(set) var priorityOverlay = TodoPriorityOverlay()
    /// 提醒的当前授权状态。**只读**：请求权限只有 `requestAccess()` 一个入口，由用户点击触发。
    @Published private(set) var authorization: EKAuthorizationStatus = TodoStore.currentAuthorization()

    /// 最近一次写回 / 取数的错误描述（只进日志与调试，不上面板）。
    private(set) var lastErrorDescription: String?

    /// 最近一次**写回失败**的形态：nil = 没有失败（或已被下一次成功写回清掉）。
    ///
    /// 与 `lastErrorDescription` 的分工：那个是给日志的原始描述，这个是给面板的**一行提示**
    /// （面板上只显示统一的 `module.todos.writeFailed`，具体是哪种失败看日志）。用户的验收口径是
    /// 「失败时给一行错误提示（不崩、不静默）」，因此失败必须**可观察**，不能只写进日志。
    @Published private(set) var writeFailure: TodoWriteFailure?

    private let store = EKEventStore()
    private let log: ModuleLogger
    private let writePriority: TodoPriorityWriter
    private var changedObserver: NSObjectProtocol?

    /// - Parameters:
    ///   - logger: 模块日志器（写回失败必须留下痕迹，不静默）。
    ///   - writePriority: 优先级写回的执行体；**nil = 走管理器侧入口**
    ///     （`CalendarManager.setReminderPriority`）。单测注入计数型假体。
    init(logger: ModuleLogger, writePriority: TodoPriorityWriter? = nil) {
        self.log = logger
        self.writePriority = writePriority ?? { reminderID, eventKitPriority in
            CalendarManager.shared.setReminderPriority(reminderID, priority: eventKitPriority)
        }
    }

    /// 是否已拿到提醒的完整访问权限（= 可以取数）。
    var hasFullAccess: Bool { authorization == .fullAccess }

    /// 某条待办的优先级显示值（乐观值优先，其次读回的真值，都没有 = 无）。
    func priority(for itemID: String) -> TodoPriority { priorityOverlay.value(for: itemID) }

    // MARK: 生命周期

    /// 订阅 `EKEventStoreChanged` 并做一次首取。**幂等**；**不请求权限**（未授权时只记状态、不取数）。
    func start() {
        authorization = Self.currentAuthorization()
        guard changedObserver == nil else { return }

        // `object: nil`：提醒库的变更对**所有** `EKEventStore` 实例广播，我们不分辨是谁改的
        //（上游 `CalendarService` 有自己的 store，用 `object: store` 会漏掉它触发的变更）。
        changedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }

        Task { await refresh() }
    }

    /// 取消订阅。`stop()` 后不再有任何回调，重新 `start()` 即可恢复。
    func stop() {
        if let changedObserver {
            NotificationCenter.default.removeObserver(changedObserver)
        }
        changedObserver = nil
    }

    // MARK: 取数

    /// 重取两类提醒（未完成 / 最近 7 天已完成）并归一化。**未授权时清空条目**（面板改显示授权提示）。
    ///
    /// 取数失败（极少数：库损坏 / 权限中途被撤销）沿用上一次的条目，只记错误——面板不该因此空白。
    /// 顺带把**优先级的真值**重建进 `priorityOverlay.baseline`（乐观值 `pending` 原样保留，
    /// 写回还在飞时不会被一次重取抹掉——见 `TodoPriorityOverlay`）。
    func refresh() async {
        authorization = Self.currentAuthorization()
        guard hasFullAccess else {
            if !items.isEmpty { items = [] }
            priorityOverlay = TodoPriorityOverlay()
            return
        }

        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let windowStart = calendar.date(
            byAdding: .day,
            value: -Self.completedWindowDays,
            to: calendar.startOfDay(for: now)
        ) ?? calendar.startOfDay(for: now)

        let allReminders = await fetchReminders(matching: store.predicateForReminders(in: nil))
        let recentCompleted = await fetchReminders(
            matching: store.predicateForCompletedReminders(
                withCompletionDateStarting: windowStart,
                ending: nil,
                calendars: nil
            )
        )

        // 两个谓词的结果可能重叠（`predicateForReminders(in:)` 也含已完成条目），按 id 去重：
        // 已完成者优先（它在第二个谓词里出现过），未完成者才会被 `!isCompleted` 收进来。
        var merged: [String: TodoBucketing.Item] = [:]
        var priorities: [String: TodoPriority] = [:]
        var openCount = 0
        for reminder in allReminders where !reminder.isCompleted {
            merged[reminder.calendarItemIdentifier] = Self.item(from: reminder, calendar: calendar)
            priorities[reminder.calendarItemIdentifier] = TodoPriority.priority(fromEventKit: reminder.priority)
            openCount += 1
        }
        var doneCount = 0
        for reminder in recentCompleted where reminder.isCompleted {
            merged[reminder.calendarItemIdentifier] = Self.item(from: reminder, calendar: calendar)
            priorities[reminder.calendarItemIdentifier] = TodoPriority.priority(fromEventKit: reminder.priority)
            doneCount += 1
        }

        items = Array(merged.values)
        priorityOverlay.rebuild(from: priorities)
        log.info("待办取数：未完成 \(openCount)、最近 \(Self.completedWindowDays) 天已完成 \(doneCount)")
    }

    /// 写回完成状态（与上游 `CalendarService.setReminderCompleted` 同一口径：只改 `isCompleted` 后 save）。
    ///
    /// **不做乐观更新**：成功与否都重取一次，面板上的环与清单必须与提醒库一致；
    /// 提醒已被删除（`calendarItem` 取不到）时也重取，让那一行自然消失。
    func setCompleted(_ item: TodoBucketing.Item, completed: Bool) async {
        guard hasFullAccess else { return }
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else {
            log.warn("写回跳过：提醒不存在或已不是提醒（\(item.id)）")
            await refresh()
            return
        }

        reminder.isCompleted = completed
        do {
            try store.save(reminder, commit: true)
            writeFailure = nil
        } catch {
            lastErrorDescription = String(describing: error)
            writeFailure = .storage(String(describing: error))
            log.error("写回完成状态失败：\(String(describing: error))")
        }
        await refresh()
    }

    // MARK: 优先级写回（P1 / T2）

    /// 点一下优先级胶囊：**先乐观更新 UI，再异步写回**；失败 → 回滚 + 记模块日志，不静默。
    ///
    /// 三条口径（docs/18 §接口与数据形状 4 与 §状态机与流程的「并发与幂等」）：
    /// 1. **幂等**：与当前档位同级时不写、也不动 UI（`TodoPriorityOverlay.beginCycle` 返回 nil）；
    /// 2. **乐观**：`pending` 先写进 `priorityOverlay`，视图下一帧就是新档位，不等 EventKit 往返；
    /// 3. **失败回滚**：写回返回 false（提醒不在库里 / save 失败）→ `clear` 撤掉乐观值（显示值退回真值）
    ///    + `writeFailure` 一行提示 + `log.error`（含提醒 id 与目标值），然后重取一次让面板与库一致。
    ///
    /// 写回的执行体是注入的 `writePriority`（默认 `CalendarManager.setReminderPriority`，见该 typealias）。
    @discardableResult
    func cyclePriority(_ item: TodoBucketing.Item) async -> Bool {
        guard hasFullAccess else {
            writeFailure = .storage("提醒未授权")
            log.warn("优先级写回跳过：提醒未授权")
            return false
        }

        // 同级 → nil：不写回、不动 UI（先比对当前值，见 TodoPriority.shouldWrite）。
        guard let step = priorityOverlay.beginCycle(for: item.id) else {
            log.info("优先级写回跳过：\(item.id) 已是 \(priorityOverlay.value(for: item.id).rawValue)")
            return false
        }

        guard writePriority(item.id, step.eventKitValue) else {
            priorityOverlay.clear(item.id)   // 回滚：显示值退回读回的旧值
            let detail = "setReminderPriority 返回 false（提醒 id \(item.id)，目标 EventKit \(step.eventKitValue)）"
            lastErrorDescription = detail
            writeFailure = .storage(detail)
            log.error("优先级写回失败：\(item.title)（\(item.id)）→ \(step.priority.rawValue) / EventKit \(step.eventKitValue)")
            await refresh()
            return false
        }

        writeFailure = nil
        log.info("优先级写回：\(item.title) → \(step.priority.rawValue)（EventKit \(step.eventKitValue)）")
        priorityOverlay.clear(item.id)       // 随后的 refresh 会把真值写进 baseline
        await refresh()
        return true
    }

    // MARK: 新增 / 删除

    /// 新增一条待办：**纯函数校验 → 建 `EKReminder` → 写库 → 重取**。
    ///
    /// 写入的库是 `store.defaultCalendarForNewReminders()`（取不到时兜到第一个可用列表，
    /// 见 `TodoComposer.targetList`）；列表里都没有则失败并回显一行提示。
    /// **不请求权限**：未授权时视图根本不渲染新增入口，这里的 `guard` 只是防御。
    ///
    /// 失败时**不清空列表、不抛错**：写回失败只是 `writeFailure` 有值（面板显示一行），
    /// 列表仍是上一次取到的内容。
    @discardableResult
    func createTodo(title: String, due: TodoComposer.DueOption) async -> Bool {
        guard hasFullAccess else {
            writeFailure = .storage("提醒未授权")
            log.warn("新增跳过：提醒未授权")
            return false
        }

        let draft = TodoComposer.draft(title: title, due: due)
        guard case let .create(finalTitle, dueDateComponents) = draft else {
            writeFailure = .emptyTitle
            log.warn("新增跳过：标题去空白后为空")
            return false
        }

        guard let list = TodoComposer.targetList(
            defaultList: store.defaultCalendarForNewReminders(),
            availableLists: store.calendars(for: .reminder)
        ) else {
            writeFailure = .noRemindersList
            log.error("新增失败：没有可用的提醒列表")
            return false
        }

        let reminder = EKReminder(eventStore: store)
        reminder.title = finalTitle
        reminder.dueDateComponents = dueDateComponents
        reminder.calendar = list

        do {
            try store.save(reminder, commit: true)
        } catch {
            writeFailure = .storage(String(describing: error))
            lastErrorDescription = String(describing: error)
            log.error("新增待办失败：\(String(describing: error))")
            return false
        }

        writeFailure = nil
        log.info("新增待办：\(finalTitle)（列表 \(list.title ?? "")，到期 \(due.rawValue)）")
        await refresh()
        return true
    }

    /// 删除一条待办（**真数据**：系统「提醒」里也会删掉，因此视图侧必须先让用户确认）。
    ///
    /// 口径与 `setCompleted` 一致：成功与否都重取一次，面板上的环与清单必须与提醒库一致。
    /// 提醒已经不在库里（在「提醒」App 里被删过 / 已被别的实例删掉）时**不算失败**：
    /// 用户要的结果（这条消失）已经达成，只记一条 warn 并重取，不弹"写入失败"的假警报。
    @discardableResult
    func removeTodo(_ item: TodoBucketing.Item) async -> Bool {
        guard hasFullAccess else {
            writeFailure = .storage("提醒未授权")
            log.warn("删除跳过：提醒未授权")
            return false
        }

        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else {
            log.warn("删除跳过：提醒不存在或已不是提醒（\(item.id)）")
            await refresh()
            return false
        }

        do {
            try store.remove(reminder, commit: true)
        } catch {
            writeFailure = .storage(String(describing: error))
            lastErrorDescription = String(describing: error)
            log.error("删除待办失败：\(String(describing: error))")
            return false
        }

        writeFailure = nil
        log.info("删除待办：\(item.title)")
        await refresh()
        return true
    }

    // MARK: 授权

    /// 用户点击「请求访问提醒」后的**唯一**权限请求入口（系统只会在 `.notDetermined` 时弹窗）。
    func requestAccess() async {
        do {
            _ = try await store.requestFullAccessToReminders()
        } catch {
            lastErrorDescription = String(describing: error)
            log.error("提醒授权请求抛错：\(String(describing: error))")
        }
        authorization = Self.currentAuthorization()
        await refresh()
    }

    // MARK: 内部

    /// 谓词取提醒（延续式包一层）。`nil` 结果（取数被取消 / 失败）按空数组处理，不抛错。
    private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder] {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private static func currentAuthorization() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    /// `EKReminder` → 归一化条目。
    ///
    /// `dueDateComponents` 可能只有年月日（全天提醒）也可能带时分；一律交给 `Calendar` 解析
    /// （组件里没带时区时按日历时区解释，与系统「提醒」App 的显示一致）。
    private static func item(from reminder: EKReminder, calendar: Calendar) -> TodoBucketing.Item {
        TodoBucketing.Item(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            dueDate: reminder.dueDateComponents.flatMap { calendar.date(from: $0) },
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            listName: reminder.calendar?.title ?? ""
        )
    }
}

// MARK: - TodosModule

/// 待办模块（09 §5.3 的 `progress` 之后，中央槽位的默认内容——见 13 号文档 D-20）。
@MainActor
final class TodosModule: GourdModule {
    /// 静态元数据（06 §2.2 的本批子集）。
    ///
    /// - `surfaces`：`expanded`（三环 + 清单）+ `compact`（折叠态中央槽位：图标 + 今日 `已办/总量`）
    ///   + `home`（**首页块** = 三环横排 + 今日清单，行数按块宽分档，见 `TodosHomeBlockLayout`）；
    /// - `defaultPlacement`：`slot == .center`、`order == 20`——与 progress（order 30）同槽位时排在它前面
    ///   （`ModuleRegistry` 的候选按 `(order, id)` 升序，只取第一个），即中央槽位的默认内容；
    /// - `defaultEnabled: true`：待办是新的中央槽位默认内容（用户定稿）；
    /// - `permissions: []`：06 §7.1 的白名单里没有「提醒」词条（提醒走系统 TCC，不是模块 capability）；
    /// - `config: nil`：**第一版不做配置**（见 [14](../../docs/14-module-manifests.md) 的 todos 行）。
    static let manifest = ModuleManifest(
        manifestVersion: 1,
        id: "com.cmeng.gourd.todos",
        name: LocalizedText(key: "module.todos.name"),
        summary: LocalizedText(key: "module.todos.summary"),
        icon: IconSpec(type: "symbol", name: "checklist"),
        version: "1.0.0",
        apiVersion: HostInfo.currentAPIVersion,
        kind: "builtin",
        surfaces: [.expanded, .compact, .home],
        defaultPlacement: Placement(slot: .center, order: 20),
        defaultEnabled: true,
        permissions: [],
        config: nil
    )

    private let context: ModuleContext
    private let store: TodoStore

    init(context: ModuleContext) {
        self.context = context
        self.store = TodoStore(logger: context.logger)
    }

    /// 只订阅变更 + 已授权时首取；**不请求权限**（见文件头的授权口径）。
    func activate() async throws {
        store.start()
        context.logger.info("todos 模块已激活（提醒授权=\(Self.authorizationDescription(store.authorization))）")
    }

    func deactivate() async {
        store.stop()
    }

    /// 三个 surface 各给一份内容；未声明的 `lockscreen` 返回 `.none`（不占位、也不算失败）。
    ///
    /// 首页块与展开 tab **同源**：同一份 `TodoBucketing` 聚合、同一个 `TodoScopeRing`，
    /// 差别只在排布（三环横排 + 今日前 N 条，窄块只画环）与「只读」。
    func content(for request: ContentRequest) -> ModuleContent {
        switch request.surface {
        case .compact:
            return .view(AnyView(TodosCompactView(store: store)))
        case .expanded:
            return .view(AnyView(TodosModuleView(store: store)))
        case .home:
            return .view(AnyView(TodosHomeBlockView(store: store)))
        case .lockscreen:
            return .none
        }
    }

    /// 授权状态的可读描述（只进日志，不上面板）。
    private static func authorizationDescription(_ status: EKAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .fullAccess: return "fullAccess"
        case .writeOnly: return "writeOnly"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - 展开面板视图（左导航四视图 + 右看板）

/// 展开面板（**P1 / T2 改版**）：**左侧四视图导航**（今天 / 最近 7 天 / 清单 / 已完成，每项带计数徽标）
/// + **右侧看板**（分组标题 + 行列表；行 = 完成圈 + 标题 + 优先级胶囊 + 日期）。
///
/// 为什么换掉三环筛选器（[docs/18](../../docs/18-p1-todos-and-order.md) §背景与目标）：环只能表达
/// 「今天 / 本周 / 所有」三个聚合量，**没有「已完成」这一档**，也没有分组标题与计数。
/// 视图口径一律走 T1 的纯函数（`TodoViewSource` 是唯一出口，视图里不另写过滤）；
/// **三环仍服务首页块**（`TodoScopeRing` / `TodoRingPicker` 本批一行不动）。
///
/// 当前视图是 **UI 局部状态**（`@State`，不进 Defaults，docs/18 §执行口径）：面板每次出现都回到「今天」。
/// 分类在每次重算时按**当下**做（展开面板是瞬时视图；常驻的折叠态另有 60s `TimelineView` 负责跨零点）。
/// `.task` 只重取数据（**不碰权限**）：面板每次出现都刷一次，避免看到上一次的陈旧计数。
private struct TodosModuleView: View {
    @ObservedObject var store: TodoStore

    /// 当前视图，默认「今天」（设计定稿）。**增删只重取数据，不动这个值**——视图保持不变。
    @State private var view: TodoBucketing.TodoViewKind = .today

    /// 四个视图的计数（左导航徽标）。与看板取数**同一个出口**（`TodoViewSource`），
    /// 因此「徽标数 = 看板条数」是同源保证，不是两处各算一遍。
    private var counts: [TodoBucketing.TodoViewKind: Int] {
        TodoViewSource.counts(from: store.items)
    }

    private var listedItems: [TodoBucketing.Item] {
        TodoViewSource.items(in: view, from: store.items)
    }

    var body: some View {
        Group {
            if store.hasFullAccess {
                HStack(alignment: .top, spacing: 12) {
                    TodoViewNav(selection: $view, counts: counts)
                        .frame(width: TodoViewNavLayout.columnWidth)
                    TodoBoard(view: view, items: listedItems, store: store)
                }
            } else {
                TodoPermissionPrompt(store: store)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await store.refresh() }
    }
}

/// 四视图的**取数出口**（唯一入口 = T1 的 `TodoBucketing.items(in:from:now:calendar:)`）。
///
/// 控制器裁决 4：视图里**不得另写过滤**——左导航徽标与右看板条数都从这里取，
/// 两者因此天然一致（失败信号「徽标数与列表条数不一致」的判据）。
/// `now` / `calendar` 可注入，单测用固定「今天」钉住四个视图的计数。
enum TodoViewSource {
    /// 某个视图的条目（顺序沿用 `TodoBucketing` 的排序，视图不再重排）。
    static func items(
        in view: TodoBucketing.TodoViewKind,
        from items: [TodoBucketing.Item],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [TodoBucketing.Item] {
        TodoBucketing.items(in: view, from: items, now: now, calendar: calendar)
    }

    /// 四个视图各自的条目数（左导航徽标）。四个视图**各过滤一次**（O(n)，n = 提醒条数）。
    static func counts(
        from items: [TodoBucketing.Item],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [TodoBucketing.TodoViewKind: Int] {
        var counts: [TodoBucketing.TodoViewKind: Int] = [:]
        for view in TodoBucketing.TodoViewKind.allCases {
            counts[view] = TodoBucketing.items(in: view, from: items, now: now, calendar: calendar).count
        }
        return counts
    }
}

/// 四视图的**外壳映射**（左导航的文案 key / 图标、看板的空态 key）。
///
/// 视图枚举本身在 `TodoBucketing`（T1）里，这里只加"外壳"的映射——**不改那个文件的边界**。
/// key 一律由 `rawValue` 派生（`module.todos.view.<rawValue>`），词汇表变化会被
/// 「词汇表 + key 可解析」两条用例拦住。
enum TodoViewChrome {
    /// 左导航项与看板分组标题共用的文案 key。
    static func labelKey(for view: TodoBucketing.TodoViewKind) -> String {
        "module.todos.view.\(view.rawValue)"
    }

    /// 看板空态的文案 key：`completed` 单列一条——「还没有待办」在有未完成条目时是错的。
    static func emptyKey(for view: TodoBucketing.TodoViewKind) -> String {
        view == .completed ? "module.todos.completedEmpty" : "module.todos.empty"
    }

    /// 左导航项的图标（四项互不相同，纯观感）。
    static func symbolName(for view: TodoBucketing.TodoViewKind) -> String {
        switch view {
        case .today: return "sun.max"
        case .next7Days: return "calendar"
        case .all: return "tray.full"
        case .completed: return "checkmark.circle"
        }
    }
}

/// 左导航（四视图竖排）的**尺寸预算**（纯值）。
///
/// 左列定宽的理由与旧的三环左列相同：右侧看板的可用宽度要随面板变宽而变宽。
/// 4 项 × 26 + 3 × 4 = 116pt：默认面板高度（约 180pt 可用）放得下，不需要像三环那样按高度收缩。
enum TodoViewNavLayout {
    /// 左列固定宽度：图标（14）+ 「最近 7 天」（最长的标签）+ 计数徽标（20）放得下。
    static let columnWidth: CGFloat = 118
    /// 项与项的垂直间距。
    static let itemSpacing: CGFloat = 4
    /// 每项的高度（即点击区高度）。
    static let itemHeight: CGFloat = 26
    /// 计数徽标的最小宽度（个位数与两位数切换时不跳）。
    static let badgeMinWidth: CGFloat = 20
}

/// 左导航：四个视图竖排，每项 = 图标 + 标签 + 计数徽标（徽标数 = 该视图的条目数）。
///
/// 只做一件事：切换 `selection`（视图是 UI 局部状态）。徽标数与看板条数同源（`TodoViewSource`）。
private struct TodoViewNav: View {
    @Binding var selection: TodoBucketing.TodoViewKind
    let counts: [TodoBucketing.TodoViewKind: Int]

    var body: some View {
        VStack(spacing: TodoViewNavLayout.itemSpacing) {
            ForEach(TodoBucketing.TodoViewKind.allCases) { view in
                TodoViewNavItem(
                    view: view,
                    count: counts[view] ?? 0,
                    isSelected: view == selection
                )
                .onTapGesture { selection = view }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// 左导航的一项：图标 + 标签 + 计数徽标；选中态用亮底 + 加粗（黑底面板上的选中 / 未选中对比）。
private struct TodoViewNavItem: View {
    let view: TodoBucketing.TodoViewKind
    let count: Int
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: TodoViewChrome.symbolName(for: view))
                .font(.system(size: 11, weight: .medium))
                .frame(width: 14)

            Text(LocalizedStringKey(TodoViewChrome.labelKey(for: view)))
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            TodoCountBadge(count: count, isSelected: isSelected)
        }
        .foregroundStyle(.white.opacity(isSelected ? 1 : (isHovered ? 0.75 : 0.55)))
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: TodoViewNavLayout.itemHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(isSelected ? 0.14 : (isHovered ? 0.06 : 0)))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

/// 计数徽标（左导航与看板标题共用）。数字**先拼 String 再给 `Text`**（走 verbatim 重载，
/// 不把 `3` 当成本地化 key 去查表——与 `已办/总量` 同口径）。
private struct TodoCountBadge: View {
    let count: Int
    var isSelected = false

    var body: some View {
        Text(TodoText.countText(count))
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.7))
            .padding(.horizontal, 5)
            .frame(minWidth: TodoViewNavLayout.badgeMinWidth, minHeight: 14)
            .background(Capsule().fill(.white.opacity(isSelected ? 0.2 : 0.1)))
    }
}

/// 左列竖排三环的**尺寸预算**（纯函数，无 SwiftUI 依赖，单测覆盖三条边界）。
///
/// 抽成命名空间是为了让「环直径随可用高度收缩」这段算术能被单测钉住（视图本身是 private）。
/// **首页块的三环横排**沿用同一个环视图与这里的设计定稿直径（不受高度约束），见 `TodosHomeBlockLayout`。
enum TodoRingLayout {
    /// 左列固定宽度：环（52）+ 标签的最宽需求 + 一点余量。
    static let columnWidth: CGFloat = 120
    /// 环与环之间的垂直间距。
    static let ringSpacing: CGFloat = 4
    /// 每个环下方「环心 → 标签」这一段的固定高度预算（环与标签的 2pt 间距 + 一行 10pt 标签）。
    static let itemTextHeight: CGFloat = 15
    /// 设计定稿的环直径（放得下就用它）。
    static let maximumDiameter: CGFloat = 52
    /// 下限：再小环心的 `已办/总量` 就挤成一团了。
    static let minimumDiameter: CGFloat = 30

    /// 竖排三环在给定可用高度下的直径：优先用设计定稿的 52，放不下就三等分剩余空间，
    /// 下限 30。
    ///
    /// 高度取不到（首帧 `GeometryReader` 给 0 / 非有限值）时按**上限**：那时布局还没算出来，
    /// 画成设计定稿的尺寸比画成一个 30pt 的小圈更稳；真正矮的面板（如 10pt）走的还是下限那一支。
    static func ringDiameter(fittingHeight height: CGFloat) -> CGFloat {
        guard height > 0, height.isFinite else { return maximumDiameter }
        let reserved = 2 * ringSpacing + 3 * itemTextHeight
        let budget = (height - reserved) / 3
        guard budget > minimumDiameter else { return minimumDiameter }
        return min(maximumDiameter, budget)
    }
}

/// 三环**竖排**在左列：**环本身即筛选器**（点击切换右侧清单的类别）。
///
/// **本批（P1 / T2）不再被展开面板使用**：面板的筛选器换成了四视图左导航（`TodoViewNav`）——
/// 环只表达三个聚合量、找不到「已完成」。这个视图与 `TodoRingLayout` 原样留着：**首页块仍用同一个
/// `TodoScopeRing`**（`TodoHomeRingRow` 横排三环），本批的约束是"三环相关的视图一行不动"，
/// 因此不删也不改（删除会连带首页的环视图，超出本批范围）。
///
/// 左列**固定宽度**（`TodoRingLayout.columnWidth`）：面板宽度可配（400 ～ 屏宽），左列定宽才能让右侧
/// 清单的可用宽度随面板变宽而变宽。环的直径按**可用高度**收缩（`TodoRingLayout.ringDiameter`）：
/// 默认 200pt 面板下三个环 + 标签也放得下，面板调高后回到设计定稿的 52（见 2026-09-28 的「高度可调」）。
private struct TodoRingPicker: View {
    let summary: TodoBucketing.Summary
    @Binding var selection: TodoBucketing.Bucket

    var body: some View {
        GeometryReader { proxy in
            let diameter = TodoRingLayout.ringDiameter(fittingHeight: proxy.size.height)
            VStack(spacing: TodoRingLayout.ringSpacing) {
                ForEach(TodoBucketing.Bucket.allCases, id: \.self) { bucket in
                    TodoScopeRing(
                        bucket: bucket,
                        result: summary.result(for: bucket),
                        isSelected: bucket == selection,
                        diameter: diameter
                    )
                    .onTapGesture { selection = bucket }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// 一个类别环：底环 + `trim` 进度环 + 环心 `已办/总量`，下方是类别标签。
///
/// 直径由 `TodoRingPicker.ringDiameter(fittingHeight:)` 给（上限 52 = 设计定稿）。
/// `trim` 的进度 = 该类别的 `已办/总量`；总量为 0 时环为空、环心显示 `0/0`。
/// 选中态用类别色 + 标签加粗；未选中一律 `.white.opacity(0.4)`（黑底面板上的选中/未选中对比）。
private struct TodoScopeRing: View {
    let bucket: TodoBucketing.Bucket
    let result: TodoBucketing.BucketResult
    let isSelected: Bool
    let diameter: CGFloat

    /// 线宽随直径等比（52 → 4，缩小后不至于糊成一圈）。
    private var lineWidth: CGFloat { max(3, diameter / 13) }
    /// 环心字号：缩小到 46 以下时退一档，避免 `已办/总量` 顶到环边。
    private var counterFontSize: CGFloat { diameter >= 46 ? 12 : 11 }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.15), lineWidth: lineWidth)

                Circle()
                    .trim(from: 0, to: result.progress)
                    .stroke(arcColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                // 环心：`已办/总量`（先拼 String 再给 Text，走 verbatim 重载，不做本地化查表）。
                Text(result.counterText)
                    .font(.system(size: counterFontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(isSelected ? 1 : 0.4))
            }
            .frame(width: diameter, height: diameter)

            Text(LocalizedStringKey(bucket.labelKey))
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(.white.opacity(isSelected ? 1 : 0.4))
        }
        .contentShape(Rectangle())
    }

    private var arcColor: Color {
        isSelected ? Self.accent(for: bucket) : .white.opacity(0.4)
    }

    /// 三个类别的强调色（纯观感，不参与计算，也不随竖排改变）。
    private static func accent(for bucket: TodoBucketing.Bucket) -> Color {
        switch bucket {
        case .today: return .blue
        case .week: return .green
        case .all: return .orange
        }
    }
}

// MARK: - 首页块（三环横排 + 今日前 N 条）

/// 首页块的**尺寸与取舍**（纯函数，无 SwiftUI 依赖，单测覆盖三条边界）。
///
/// 规格（[17](../../docs/17-nookx-adoption.md) §已知限制 16 的 2026-09-29 改判）：块内容 = 三环横排
/// （今日 / 本周 / 所有）+ 今日清单；清单按块宽**分三档**——`>= 220` 完整行（最多 5 行）、
/// `>= 160` 紧凑行（只标题单行、最多 3 行）、`< 160` 只画三环。块宽由宿主 `HomeStripLayoutMath`
/// 分配（本批模块块统一声明 180 / 240），模块自己**不声明宽度、不读 `.layoutValue`**。
///
/// 分档的由来：单阈值（220）下本机 770pt 面板实测只分给待办块 180.5pt，默认配置里永远只画三环
/// （用户很可能因此把这个组件关掉）。分档比"让用户调面板宽"或"给每块加权重"成本低得多；
/// 代价是紧凑档每行信息更少（只有标题）。
enum TodosHomeBlockLayout {
    /// 清单的档位。**纯值**：视图只按它取行数与行形态，档位切换就是布局切换（无动画）。
    enum Tier: Equatable {
        /// `>= fullListWidth`：完整行（状态圈 + 标题 + 已过期红字），最多 `maxListRows` 行。
        case full
        /// `>= compactListWidth` 且 `< fullListWidth`：紧凑行（只标题单行尾部截断），最多 `compactListRows` 行。
        case compact
        /// 更窄（或宽度取不到）：只画三环。
        case ringsOnly
    }

    /// 完整行的最小块宽（规格：220）。判据取**放置后**的宽度（`GeometryReader`），不用测量。
    static let fullListWidth: CGFloat = 220
    /// 紧凑行的最小块宽（规格：160）。本机 770pt 面板下的块宽 180.5 落在这一档。
    static let compactListWidth: CGFloat = 160
    /// 完整行最多画几行（规格：前 5 条；超出的不显示）。
    static let maxListRows = 5
    /// 紧凑行最多画几行（规格：3）。
    static let compactListRows = 3
    /// 三环**横排**的环间距（竖排的间距是 `TodoRingLayout.ringSpacing`）。
    static let ringSpacing: CGFloat = 8
    /// 三环直径：横排不受块高约束，用设计定稿的 52（与展开 tab 同源，不另取一套尺寸）。
    static let ringDiameter: CGFloat = TodoRingLayout.maximumDiameter

    /// 块宽 → 档位。边界口径：`>= 220` → `.full`；`>= 160` 且 `< 220` → `.compact`；
    /// `< 160` 或非有限数（首帧 0 / NaN）→ `.ringsOnly`。
    ///
    /// 宽度取不到时退到最保守的档（只画环）：环一定放得下（3 × 52 + 2 × 8 = 172
    /// ≤ 模块块最小宽 180），清单要按宽度取舍，因此宁可少画一段也不让标题溢出块宽。
    static func listTier(forWidth width: CGFloat) -> Tier {
        guard width.isFinite else { return .ringsOnly }
        if width >= fullListWidth { return .full }
        if width >= compactListWidth { return .compact }
        return .ringsOnly
    }

    /// 该档最多画几行清单（`.ringsOnly` 为 0：一行都不画）。
    static func listRows(for tier: Tier) -> Int {
        switch tier {
        case .full: return maxListRows
        case .compact: return compactListRows
        case .ringsOnly: return 0
        }
    }

    /// 清单要画的条目：按档取前 N 条。顺序沿用 `TodoBucketing` 的排序（不在这里另排一遍）。
    static func listedItems(_ items: [TodoBucketing.Item], tier: Tier) -> [TodoBucketing.Item] {
        Array(items.prefix(listRows(for: tier)))
    }
}

/// 首页块：**横排三环 + 今日清单**（[17](../../docs/17-nookx-adoption.md) §已知限制 16）。
///
/// 与展开 tab **同源**：聚合是同一个 `TodoBucketing.classify`（**不另写一套统计**），环是同一个
/// `TodoScopeRing`（只把排布从竖排换成横排——180 ～ 240pt 的块里竖排练三环放不下）。
///
/// **只读**（控制器裁决 2）：勾选 / 新增 / 删除都留在展开 tab，这里不挂任何手势——首页块是
/// 「一眼看进度」，不是第二个操作台。
///
/// 宽度用 `GeometryReader` 读**放置后**的尺寸（不是测量）：按 `listTier(forWidth:)` 分档——
/// `>= 220` 完整行（最多 5 行）、`>= 160` 紧凑行（只标题单行、最多 3 行）、`< 160` 只画三环。
/// 未授权时 `store.items` 为空 → 画三个 `0/0` 的空环，**不在这里引导授权**（授权入口在展开 tab，
/// 首页块没有交互面）。今日 0 条时同样只留三环（控制器裁决 3：不做空态文案）。
///
/// 重绘走本模块既有做法——观察 `store` 的 `@Published`（折叠态那 60s 的 `TimelineView` 是给**常驻**视图
/// 跨零点用的；首页块只在展开面板里存在，每次出现 `.task` 重取一次数即可，不去新建定时器）。
private struct TodosHomeBlockView: View {
    @ObservedObject var store: TodoStore

    /// 分类在每次重算时按**当下**做（与展开 tab 同口径）。
    private var summary: TodoBucketing.Summary { TodoBucketing.classify(store.items) }

    var body: some View {
        GeometryReader { proxy in
            // 档位与条目都在**同一层**算：档位决定行数上限，行数决定清单画不画（只画环时清单为空）。
            let tier = TodosHomeBlockLayout.listTier(forWidth: proxy.size.width)
            let rows = TodosHomeBlockLayout.listedItems(summary.today.items, tier: tier)

            VStack(alignment: .leading, spacing: 8) {
                TodoHomeRingRow(summary: summary)

                if !rows.isEmpty {
                    TodoHomeTodayList(items: rows, tier: tier)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task { await store.refresh() }
    }
}

/// 首页块顶部的**横排**三环：今日 / 本周 / 所有，环心 `已办/总量`。
///
/// 复用展开 tab 的 `TodoScopeRing`（只换排布方向），两个 surface 的环因此不会视觉漂移。
/// 首页块里的环**不是筛选器**（不做交互），所以三个都按「选中」画——各自用类别色 + 实心标签；
/// 未选中的灰态是给可点选的竖排环做对比用的，整排灰掉在这里只是变暗。
private struct TodoHomeRingRow: View {
    let summary: TodoBucketing.Summary

    var body: some View {
        HStack(alignment: .top, spacing: TodosHomeBlockLayout.ringSpacing) {
            ForEach(TodoBucketing.Bucket.allCases, id: \.self) { bucket in
                TodoScopeRing(
                    bucket: bucket,
                    result: summary.result(for: bucket),
                    isSelected: true,
                    diameter: TodosHomeBlockLayout.ringDiameter
                )
            }
        }
    }
}

/// 首页块的今日清单：**只读**的简化行（勾选圈只是状态字形，不是按钮）。
///
/// 画的是 `TodoBucketing` 的「今日」类别——含过期未完成 / 今天完成的，与展开 tab 的今日环
/// **同一份成员**；空清单不画空态文案（上游已保证今天数不为 0，这里不做二次判定）。
///
/// 行形态按档（`TodosHomeBlockLayout.Tier`）：完整行 = 状态圈 + 标题 + 已过期红字；
/// 紧凑行 = **只标题单行尾部截断**（窄块里先牺牲固定宽度的状态圈与红字）。
private struct TodoHomeTodayList: View {
    let items: [TodoBucketing.Item]
    /// 当前档位（`.ringsOnly` 时调用方根本不画这个清单；这里把它也当空列表处理）。
    let tier: TodosHomeBlockLayout.Tier

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items) { item in
                row(for: item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(for item: TodoBucketing.Item) -> some View {
        switch tier {
        case .full:
            TodoHomeRow(item: item)
        case .compact:
            TodoHomeCompactRow(item: item)
        case .ringsOnly:
            EmptyView()
        }
    }
}

/// 首页块的一行：状态圈 + 标题（单行尾部截断）+ 过期红字。
///
/// 是展开 tab `TodoRow` 的简化形态：去掉勾选按钮（只读）、去掉所属列表名与到期时刻
/// （今日条目都到期在今天，逐行重复同一个日期只是噪音），保留「已完成置灰 + 删除线」与「已过期」。
private struct TodoHomeRow: View {
    let item: TodoBucketing.Item

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(item.isCompleted ? 0.35 : 0.8))

            Text(item.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(item.isCompleted ? 0.4 : 0.95))
                .strikethrough(item.isCompleted, color: .white.opacity(0.4))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if TodoText.isOverdue(item) {
                Text(LocalizedStringKey("module.todos.overdue"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.red)
                    .fixedSize()
            }
        }
    }
}

/// 首页块**紧凑档**（块宽 160 ～ 220）的一行：**只标题**，单行尾部截断。
///
/// 比完整行再省两种元素——状态圈（10pt 图标 + 6pt 间距）与「已过期」红字（`fixedSize` 不缩）：
/// 它们各占一段**不会被压缩**的宽度，窄块里先牺牲它们，把宽度全留给标题。
/// 「已完成」的线索只靠标题本身的样式（置灰 + 删除线），不另加元素。
/// 条目的成员与顺序与完整档**同一份**（`TodoBucketing` 的今日类别，不在这里筛）。
private struct TodoHomeCompactRow: View {
    let item: TodoBucketing.Item

    var body: some View {
        Text(item.title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(item.isCompleted ? 0.4 : 0.95))
            .strikethrough(item.isCompleted, color: .white.opacity(0.4))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 右看板：**分组标题**（当前视图名 + 计数徽标 + `+` 新增入口）+ **行列表**。
///
/// 行 = 完成圈 + 标题 + **优先级胶囊** + 日期（+ 所属列表名 + hover 垃圾桶），见 `TodoRow`。
/// 顺序由 `TodoBucketing` 定死（未完成在前、已完成按完成时刻倒序），这里只渲染；
/// 条目多时滚动（面板高度有限），空清单按视图显示 `module.todos.empty` /
/// `module.todos.completedEmpty`（`TodoViewChrome.emptyKey(for:)`）。
///
/// **取数不在这一层**：`items` 由 `TodosModuleView` 用 `TodoViewSource` 算好传进来——
/// 视图里不另写过滤（控制器裁决 4），徽标数与这里的条数因此同源。
///
/// **可增删**（2026-09-28 用户反馈「待办里面要可以增删待办内容」）：
/// - 顶部一行 `+` 展开内联输入（标题 + 今天 / 明天 / 无日期三选一），回车或「添加」写库；
/// - 每行 hover 出现垃圾桶图标 → **确认对话框**（写的是真实系统提醒）→ 确认后删库；
/// - 两者失败都在列表上方回显**一行**提示（`module.todos.writeFailed`），不静默、不崩；
/// - 增删只重取数据，**不动当前视图**——左导航选中的视图保持不变。
private struct TodoBoard: View {
    /// 当前视图（只用于标题与空态文案；条目已由调用方按它过滤好）。
    let view: TodoBucketing.TodoViewKind
    let items: [TodoBucketing.Item]
    @ObservedObject var store: TodoStore

    /// 内联输入行是否展开。
    @State private var isComposing = false
    /// 输入行里的标题草稿。
    @State private var draftTitle = ""
    /// 输入行里选中的日期选项（默认今天，与「今天」默认视图一致）。
    @State private var draftDue: TodoComposer.DueOption = .today
    /// 等确认的那一条（非 nil 即弹确认框；删的是真数据，必须先确认）。
    @State private var pendingDeletion: TodoBucketing.Item?
    /// 展开输入行时把键盘焦点送进 `TextField`。
    @FocusState private var isDraftFocused: Bool

    /// 标题去空白后非空才允许提交（空标题既不建提醒，也不弹提示——回车当成没反应，不是失败）。
    private var canSubmit: Bool {
        !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow

            if isComposing {
                composerRow
            }

            if store.writeFailure != nil {
                writeFailureRow
            }

            if items.isEmpty {
                Text(LocalizedStringKey(TodoViewChrome.emptyKey(for: view)))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(items) { item in
                            TodoRow(item: item, store: store) {
                                pendingDeletion = item
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(
            Text(LocalizedStringKey("module.todos.delete")),
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { item in
            Button(LocalizedStringKey("module.todos.delete"), role: .destructive) {
                Task { await store.removeTodo(item) }
            }
            Button(LocalizedStringKey("module.todos.cancel"), role: .cancel) {}
        } message: { _ in
            // 说明影响范围：这里是**真数据**，系统「提醒」里同一条也会被删掉。
            Text(LocalizedStringKey("module.todos.deleteConfirm"))
        }
    }

    // MARK: 分组标题 + 新增

    /// 看板顶部一行：**分组标题**（当前视图名）+ 计数徽标 + `+`（展开 / 收起输入行）。
    ///
    /// 标题给"现在看的是哪一组"一个锚点（左导航的选中态之外的第二重指示），
    /// 徽标与左导航用的是同一个数（`TodoViewSource` 同源）；`+` 与旧版一样常显——
    /// 空态与有内容时都在，新增入口不会被清单长度藏起来。
    private var headerRow: some View {
        HStack(spacing: 6) {
            Text(LocalizedStringKey(TodoViewChrome.labelKey(for: view)))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))

            TodoCountBadge(count: items.count)

            Spacer(minLength: 4)

            Button {
                isComposing.toggle()
                if !isComposing { draftTitle = "" }
            } label: {
                Image(systemName: isComposing ? "xmark" : "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help(Text(LocalizedStringKey("module.todos.add")))
        }
        .onChange(of: isComposing) { _, expanded in
            // 展开后把焦点给输入框（否则用户得先点一下那一行才能打字）。
            isDraftFocused = expanded
        }
    }

    /// 内联输入行：标题 + 日期三选一 + 「添加」。
    private var composerRow: some View {
        HStack(spacing: 6) {
            TextField(LocalizedStringKey("module.todos.addPlaceholder"), text: $draftTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .focused($isDraftFocused)
                .onSubmit { submitDraft() }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)))

            ForEach(TodoComposer.DueOption.allCases, id: \.self) { option in
                Button {
                    draftDue = option
                } label: {
                    Text(LocalizedStringKey(option.labelKey))
                        .font(.system(size: 10, weight: draftDue == option ? .semibold : .regular))
                        .foregroundStyle(.white.opacity(draftDue == option ? 1 : 0.55))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.white.opacity(draftDue == option ? 0.24 : 0.08)))
                }
                .buttonStyle(.plain)
            }

            Button(action: submitDraft) {
                Text(LocalizedStringKey("module.todos.add"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(canSubmit ? 0.95 : 0.35))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.white.opacity(canSubmit ? 0.2 : 0.06)))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
        }
    }

    /// 提交草稿：成功则清空输入框、**保持输入行展开**（连着记几条不用反复点 `+`）；失败留给
    /// `store.writeFailure` 去回显，草稿原样留着让用户改（不丢用户敲的字）。
    private func submitDraft() {
        guard canSubmit else { return }
        let title = draftTitle
        let due = draftDue
        Task {
            let created = await store.createTodo(title: title, due: due)
            guard created else { return }
            draftTitle = ""
            draftDue = .today
            isDraftFocused = true
        }
    }

    /// 写回失败的一行提示（红字 + 三角图标，纯黑与玻璃底上都可读）。
    private var writeFailureRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text(LocalizedStringKey("module.todos.writeFailed"))
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.orange)
    }
}

/// 看板的一行：完成圈（点击写回完成）+ 标题 + **优先级胶囊** + 日期 + 所属列表名；已完成项置灰 + 删除线；
/// **hover 时行尾出现垃圾桶**（点击不直接删，交给上层弹确认框——删的是系统「提醒」里的真条目）。
///
/// 优先级胶囊（P1 / T2）挂在 `Spacer` 之后、日期之前：点一下按 无 → 低 → 中 → 高 → 无 循环并写回
/// 系统提醒（见 `TodoPriorityCapsule`）。日期口径见 `TodoDueLabel`（今天 → 「今天」，其余 `M/D`，
/// 无到期日不显示）；「已过期」红字沿用旧版（清单视图里要能一眼看到逾期条目）。
private struct TodoRow: View {
    let item: TodoBucketing.Item
    @ObservedObject var store: TodoStore
    /// 请求删除（上层弹确认框；真正删库在确认之后）。
    let onRequestDelete: () -> Void

    @State private var isHovered = false

    private var isOverdue: Bool { TodoText.isOverdue(item) }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                Task { await store.setCompleted(item, completed: !item.isCompleted) }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(item.isCompleted ? 0.4 : 0.9))
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(item.isCompleted ? 0.4 : 1))
                .strikethrough(item.isCompleted, color: .white.opacity(0.4))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            TodoPriorityCapsule(item: item, store: store)

            if let dueLabel = TodoDueLabel.label(for: item) {
                HStack(spacing: 4) {
                    if isOverdue {
                        Text(LocalizedStringKey("module.todos.overdue"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                    dueLabelView(dueLabel)
                }
                .fixedSize()
            }

            if !item.listName.isEmpty {
                Text(item.listName)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
            }

            // 垃圾桶只在 hover 时出现（常显会让每一行都多一个可点击的目标，误删风险高）。
            if isHovered {
                Button(action: onRequestDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help(Text(LocalizedStringKey("module.todos.delete")))
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(isHovered ? 0.06 : 0))
        )
        .onHover { isHovered = $0 }
    }

    /// 日期标签：`今天` 走本地化 key（复用新增行的「今天」文案），`M/D` 是**拼好的字符串**
    /// （走 `Text(_: String)` 的 verbatim 重载，不拿 `9/28` 去查表）。
    @ViewBuilder
    private func dueLabelView(_ label: TodoDueLabel) -> some View {
        switch label {
        case .today:
            Text(LocalizedStringKey("module.todos.dueToday"))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        case .day(let text):
            Text(text)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isOverdue ? .red : .white.opacity(0.6))
        }
    }
}

// MARK: - 优先级胶囊

/// 行内的**优先级胶囊**：显示当前档位（无 / 低 / 中 / 高），点一下按 无 → 低 → 中 → 高 → 无 循环。
///
/// 手势用 **`highPriorityGesture`**（docs/18 §改动点设计 2 的陷阱栏）：面板与行上还挂着别的手势
/// （面板的"点一下展开 / 收起"、行内的完成圈与垃圾桶按钮），`highPriorityGesture` 让胶囊这一下
/// 明确归胶囊自己，不去触发那些手势（与 `ContentView` 的尺寸把手同一手法）。
///
/// 写回是**异步 + 乐观**的（`TodoStore.cyclePriority`）：点完立刻变，失败才回滚——
/// 因此这里只发一次调用，不在这里判成败、不做二次状态。
private struct TodoPriorityCapsule: View {
    let item: TodoBucketing.Item
    @ObservedObject var store: TodoStore

    @State private var isHovered = false

    private var priority: TodoPriority { store.priority(for: item.id) }

    var body: some View {
        Text(LocalizedStringKey(priority.labelKey))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(TodoPriorityChrome.foregroundColor(isHovered: isHovered, priority: priority))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(accent.opacity(isHovered ? 0.28 : 0.16)))
            .overlay(Capsule().stroke(accent.opacity(0.55), lineWidth: 0.5))
            .fixedSize()
            .contentShape(Capsule())
            .highPriorityGesture(
                TapGesture().onEnded {
                    Task { await store.cyclePriority(item) }
                }
            )
            .onHover { isHovered = $0 }
            .help(Text(LocalizedStringKey("module.todos.priorityHint")))
    }

    /// 档位的强调色（同 `TodoPriorityChrome.tint`；「无」用白色系，不抢注意力）。
    private var accent: Color { TodoPriorityChrome.tint(for: priority) }
}

/// 优先级的外壳映射与观感（纯值：配色与文字不透明度；面板是黑底，一律显式浅色）。
enum TodoPriorityChrome {
    /// 档位强调色：高 = 橙、中 = 黄、低 = 蓝、无 = 白。
    ///
    /// 「高」取橙而不是红：红已经被「已过期」占用（同一行上两者可能同时出现，撞色会看不出哪个是哪个）。
    static func tint(for priority: TodoPriority) -> Color {
        switch priority {
        case .none: return .white
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .blue
        }
    }

    /// 胶囊文字色：悬停时提亮；「无」**常淡**——每一行都有胶囊，四档里只有它表示"没设过"。
    static func foregroundColor(isHovered: Bool, priority: TodoPriority) -> Color {
        switch (priority, isHovered) {
        case (.none, false): return .white.opacity(0.45)
        case (.none, true): return .white.opacity(0.75)
        case (_, false): return .white.opacity(0.95)
        case (_, true): return .white
        }
    }
}

// MARK: - 授权提示

/// 未授权时的占位：一句说明 + 两颗按钮。
///
/// **不自动请求**（本项目「每次安装最多问一次 / 不打扰」策略）：请求入口只有这一颗按钮，点击才弹窗。
private struct TodoPermissionPrompt: View {
    @ObservedObject var store: TodoStore

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            Text(LocalizedStringKey("module.todos.permission"))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TodoPromptButton(titleKey: "module.todos.requestAccess") {
                    Task { await store.requestAccess() }
                }
                TodoPromptButton(titleKey: "module.todos.openSettings") {
                    Self.openRemindersSettings()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 系统设置 → 隐私与安全性 → 提醒（`x-apple.systempreferences:` 是系统既定的跳转 scheme）。
    static func openRemindersSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

/// 提示里的胶囊按钮：黑底面板上自绘（`.bordered` 会用系统外观色，浅色外观下与面板不搭）。
private struct TodoPromptButton: View {
    let titleKey: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(titleKey))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(.white.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 折叠态中央槽位视图

/// 折叠态中央槽位：图标 + **今日**的 `已办/总量`。
///
/// 常驻关闭态，因此自带 60s 的 `TimelineView`（宿主不会为这一格起定时器）：没有它，跨零点后
/// 「今日」不会换日、环心数字也不会随时间推进（粒度与 progress 一致，见 13 号文档已知限制 14）。
private struct TodosCompactView: View {
    @ObservedObject var store: TodoStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            HStack(spacing: 5) {
                Image(systemName: "checklist")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)

                Text(TodoBucketing.classify(store.items, now: timeline.date).today.counterText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - 行内日期的显示口径（纯函数）

/// 看板行上的**日期标签**（P1 / T2 的控制器裁决 2）：有到期日显示 `M/D`，到期落在**今天**显示「今天」，
/// 没有到期日**不显示**（不为它留空位）。**不显示提醒的备注 / 地点**。
///
/// 与上一版 `TodoText.dueText` 的差别：不再附带 `时:分`、不再补前导零（`9/28` 而不是 `09/28`）——
/// 行上要回答的是"哪天到期"，具体时刻留给系统「提醒」App（时刻信息仍在 `Item.dueDate` 里，
/// `TodoComposer` 的"今天 / 明天"全天口径也不变）。
///
/// 纯值形态（而不是直接返 String）的理由：「今天」要走本地化 key，`M/D` 要走 verbatim——
/// 把"是哪一种"带回视图去渲染，`calendar` / `now` 注入后本函数可被单测逐字钉住。
enum TodoDueLabel: Equatable {
    /// 到期落在 `now` 所在的自然日（半开区间由 `Calendar.isDate(_:inSameDayAs:)` 定）。
    case today
    /// `M/D`（不补前导零；调用方走 `Text(_: String)` 的 verbatim 重载）。
    case day(String)

    /// **无到期时间 → nil**（该行不显示日期）。
    static func label(
        for item: TodoBucketing.Item,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> TodoDueLabel? {
        guard let dueDate = item.dueDate else { return nil }
        if calendar.isDate(dueDate, inSameDayAs: now) { return .today }

        let parts = calendar.dateComponents([.month, .day], from: dueDate)
        guard let month = parts.month, let day = parts.day else { return nil }
        return .day("\(month)/\(day)")
    }
}

// MARK: - 文案出口

/// 模块内动态文案的唯一出口（06 §3.3 R5：视图内不写字面量文案）。
///
/// 计数徽标的数字与 `已办/总量` 都**先拼成 String 再给 `Text`**——走 `Text(_: String)` 的 verbatim
/// 重载，不会把这些形态当成本地化 key 去查表。日历口径与 `TodoBucketing` 一致：`.autoupdatingCurrent`。
private enum TodoText {
    /// 计数徽标 / 看板标题上的数字（verbatim：`3` 不该去查本地化表）。
    static func countText(_ count: Int) -> String { "\(count)" }

    /// 是否已过期 = 有到期时间、**到期 < 今天 00:00**、且未完成。
    ///
    /// 与 `TodoBucketing` 的「今日」第 ② 条同一口径（不用「到期 < 此刻」——今天 09:00 到期的条目
    /// 在 10:00 不算过期，它只是今天该做的事）；已完成的一律不标红。
    static func isOverdue(
        _ item: TodoBucketing.Item,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> Bool {
        guard !item.isCompleted, let dueDate = item.dueDate else { return false }
        return dueDate < calendar.startOfDay(for: now)
    }
}
