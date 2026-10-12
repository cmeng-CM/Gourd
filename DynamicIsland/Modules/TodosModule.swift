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
//  TodosModule.swift
//  Gourd 内置模块 · 待办（展开面板四视图 + 首页今日块，P1 批次 / T5、T2；P5 / T1 去三环）
//
//  形态定稿：
//  - 展开态（**P1 / T2 改版，2026-09-29**）= **左侧四视图导航**（今天 / 最近 7 天 / 清单 / 已完成，
//    竖排，每项 = 图标 + 文字 + 计数徽标）+ **右侧看板**（分组标题 + 行列表）；
//    当前视图是 **UI 局部 `@State`**（不进 Defaults），面板每次出现都回到「今天」。
//    2026-09-28 的第一版是「左侧竖排三个环（今日 / 本周 / 所有）+ 右侧该类别清单」——
//    环只能表达三个聚合量、找不到「已完成」，因此筛选器换成四视图（口径见 `TodoBucketing.TodoViewKind`
//    与 `TodoBucketing.items(in:from:now:calendar:)`）。
//    **三环代码保留但不挂 surface**（可逆）：`TodoScopeRing` / `TodoRingPicker` / `TodoRingLayout`
//    一律留着，不再被任何 surface 渲染（P5 / T1 起首页块也不再画环，见下一条）。
//  - 折叠态 = 图标 + **今日**的 `已办/总量`（自带 60s `TimelineView`，宿主不起定时器，与 progress 同口径）；
//  - 首页块（docs/39）：固定统计头 + 一个滚动区，日程/待办分组完整展示；
//    完成圈独立提交，标题进日历详情；窄行也保留圈。旧容量 helper 仅作历史 API 兼容。
//  - 分类与计数口径全在 `TodoBucketing`（纯函数，单测覆盖）——**各 surface 共用同一份聚合**。

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
import Defaults
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

    /// 写回**失败**：撤销乐观值——显示值立刻退回 `baseline` 里的真值（不停在错误值）。
    mutating func rollback(_ id: String) { pending[id] = nil }

    /// 写回**成功**：把乐观值**转正**成基线——此后即使一次重读还没拿到新值
    /// （写回走的是另一个 `EKEventStore` 实例、通知尚未处理时的既有现象），
    /// 显示值也停在用户点出的档位，不会闪回旧值；真正的库变更由 `EKEventStoreChanged` 收口。
    mutating func confirm(_ id: String) {
        if let value = pending[id] { baseline[id] = value }
        pending[id] = nil
    }

    /// 重取后重建基线（**保留 `pending`**：写回还在飞时不能被一次重取抹掉乐观值）。
    mutating func rebuild(from values: [String: TodoPriority]) { baseline = values }
}

// MARK: - TodoStore

/// 优先级写回的执行体：`reminderID` + 目标 EventKit 值 → 成功与否。
///
/// **异步**（P1 / T2 复审修）：默认实现 `CalendarManager.setReminderPriority` 内部把
/// `EKEventStore.save(commit: true)` 放到**后台执行器**上跑，调用方 `await` 它。
/// 对 `TodoStore` 来说关键是「乐观更新」与「写回完成」之间因此有**一次真正的挂起点**：
/// 主 actor 在这段区间是空的、落盘 I/O 也不在主线程上，所以 UI 先画新档位、不等 EventKit
/// （`docs/18` §状态机与流程「并发与幂等」：写回在后台任务里做）。
///
/// 抽成可注入的接缝是为了让单测用**计数型假体**覆盖「同级不重复写回」与「失败回滚」，
/// 而不必往用户真实的提醒库里写数据（见 `ModuleKernelTests` 的两条 store 级用例）。
typealias TodoPriorityWriter = @MainActor (_ reminderID: String, _ eventKitPriority: Int) async -> Bool

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
    @Published private(set) var authorization: EKAuthorizationStatus

    /// 最近一次写回 / 取数的错误描述（只进日志与调试，不上面板）。
    private(set) var lastErrorDescription: String?

    /// 最近一次**写回失败**的形态：nil = 没有失败（或已被下一次成功写回清掉）。
    ///
    /// 与 `lastErrorDescription` 的分工：那个是给日志的原始描述，这个是给面板的**一行提示**
    /// （面板上只显示统一的 `module.todos.writeFailed`，具体是哪种失败看日志）。用户的验收口径是
    /// 「失败时给一行错误提示（不崩、不静默）」，因此失败必须**可观察**，不能只写进日志。
    @Published private(set) var writeFailure: TodoWriteFailure?

    // 测试分支在访问这个属性之前早退；初始化模块不会构造 EventKit store。
    private var eventStore: EKEventStore?
    private var store: EKEventStore {
        if let eventStore { return eventStore }
        let created = EKEventStore()
        eventStore = created
        return created
    }
    var hasInitializedEventStore: Bool { eventStore != nil }
    var isObservingEventStore: Bool { changedObserver != nil }
    #if DEBUG
    private let fixtureBackend: CalendarInteractionMemoryService?
    #endif
    private let readItems: (() async -> [TodoBucketing.Item])?
    private var refreshGeneration = 0
    private let log: ModuleLogger
    private let writePriority: TodoPriorityWriter
    /// 授权读数接缝（**不引入协议**）：默认读 EventKit 的实时状态；单测注入固定值，
    /// 让写回链的用例不依赖本机 TCC（也不会因为机器上没授权就整条用例空转）。
    private let authorizationStatus: () -> EKAuthorizationStatus
    private var changedObserver: NSObjectProtocol?
    private var isStarted = false

    /// - Parameters:
    ///   - logger: 模块日志器（写回失败必须留下痕迹，不静默）。
    ///   - writePriority: 优先级写回的执行体；**nil = 走管理器侧入口**
    ///     （`CalendarManager.setReminderPriority`）。单测注入计数型假体。
    ///   - authorizationStatus: 授权读数；生产默认读 EventKit，夹具默认读内存。显式注入优先。
    ///   - readItems: 异步归一化读取接缝，供旧刷新回调的竞争回归；nil 保持正常读取。
    init(
        logger: ModuleLogger,
        writePriority: TodoPriorityWriter? = nil,
        authorizationStatus: (() -> EKAuthorizationStatus)? = nil,
        readItems: (() async -> [TodoBucketing.Item])? = nil
    ) {
        self.log = logger
        self.readItems = readItems
        #if DEBUG
        let backend = CalendarInteractionFixtures.isEnabled ? CalendarInteractionFixtures.backend : nil
        fixtureBackend = backend
        if let backend {
            self.writePriority = writePriority ?? { await backend.setReminderPriority(reminderID: $0, priority: $1) }
            let reader = authorizationStatus ?? { backend.authorizationStatus(for: .reminder) }
            self.authorizationStatus = reader
            authorization = reader()
            return
        }
        #endif
        self.writePriority = writePriority ?? { reminderID, eventKitPriority in
            await CalendarManager.shared.setReminderPriority(reminderID, priority: eventKitPriority)
        }
        let reader = authorizationStatus ?? { Self.currentAuthorization() }
        self.authorizationStatus = reader
        authorization = reader()
    }

    #if DEBUG
    /// 每个测试可注入独立字典；显式写入器和授权读数仍优先于默认夹具实现。
    init(
        logger: ModuleLogger, fixtureBackend: CalendarInteractionMemoryService,
        writePriority: TodoPriorityWriter? = nil,
        authorizationStatus: (() -> EKAuthorizationStatus)? = nil
    ) {
        log = logger
        self.fixtureBackend = fixtureBackend
        readItems = nil
        self.writePriority = writePriority ?? { await fixtureBackend.setReminderPriority(reminderID: $0, priority: $1) }
        let reader = authorizationStatus ?? { fixtureBackend.authorizationStatus(for: .reminder) }
        self.authorizationStatus = reader
        authorization = reader()
    }
    #endif

    /// 是否已拿到提醒的完整访问权限（= 可以取数 / 可以写回）。
    ///
    /// 判定走 `authorizationStatus` 接缝（**实时读**，不缓存）：生产里接缝就是
    /// `EKEventStore.authorizationStatus(for: .reminder)`，与 `authorization` 同源
    /// （后者是最近一次读数，供 UI 展示）；单测注入固定值后，这条 gate 也照样生效——
    /// 否则用例会在「未授权」上静默空转（P1 / T2 复审修 2 的 store 级用例就靠它）。
    var hasFullAccess: Bool { authorizationStatus() == .fullAccess }

    /// 某条待办的优先级显示值（乐观值优先，其次读回的真值，都没有 = 无）。
    func priority(for itemID: String) -> TodoPriority { priorityOverlay.value(for: itemID) }

    // MARK: 生命周期

    /// 订阅 `EKEventStoreChanged` 并做一次首取。**幂等**；**不请求权限**（未授权时只记状态、不取数）。
    func start() {
        authorization = authorizationStatus()
        guard !isStarted else { return }
        isStarted = true
        #if DEBUG
        if fixtureBackend != nil {
            Task { if isStarted { await refresh() } }
            return
        }
        #endif

        // `object: nil`：提醒库的变更对**所有** `EKEventStore` 实例广播，我们不分辨是谁改的
        //（上游 `CalendarService` 有自己的 store，用 `object: store` 会漏掉它触发的变更）。
        changedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                await self.refresh()
            }
        }

        Task { if isStarted { await refresh() } }
    }

    /// 取消订阅。`stop()` 后不再有任何回调，重新 `start()` 即可恢复。
    func stop() {
        isStarted = false
        refreshGeneration += 1
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
        refreshGeneration += 1
        let generation = refreshGeneration
        authorization = authorizationStatus()
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

        if let readItems {
            let fetched = await readItems()
            guard refreshGeneration == generation else { return }
            items = TodosHomeBlockLayout.uniqueTodos(fetched)
            return
        }
        #if DEBUG
        if let fixtureBackend {
            let reminders = fixtureBackend.allRecords().filter { $0.type.isReminder }
            items = reminders.compactMap { event in
                guard case .reminder(let completed) = event.type else { return nil }
                let completion = fixtureBackend.completionDate(forReminderID: event.id)
                guard !completed || (completion.map { $0 >= windowStart } ?? false) else { return nil }
                return TodoBucketing.Item(
                    id: event.id, title: event.title,
                    dueDate: event.start == .distantFuture ? nil : event.start,
                    isCompleted: completed, completionDate: completion, listName: event.calendar.title
                )
            }
            priorityOverlay.rebuild(from: Dictionary(uniqueKeysWithValues: reminders.map {
                ($0.id, Self.fixturePriority($0.priority))
            }))
            return
        }
        #endif
        let allReminders = await fetchReminders(matching: store.predicateForReminders(in: nil))
        guard refreshGeneration == generation else { return }
        let recentCompleted = await fetchReminders(
            matching: store.predicateForCompletedReminders(
                withCompletionDateStarting: windowStart,
                ending: nil,
                calendars: nil
            )
        )

        guard refreshGeneration == generation else { return }

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
        #if DEBUG
        if let fixtureBackend {
            do {
                _ = try await fixtureBackend.completeReminder(id: item.id, completed: completed)
                writeFailure = nil
            } catch { recordFixtureFailure(error) }
            await refresh()
            return
        }
        #endif
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

    /// 点一下优先级胶囊：按 无 → 低 → 中 → 高 → 无 取下一档，交给 `setPriority(_:to:)` 写回。
    @discardableResult
    func cyclePriority(_ item: TodoBucketing.Item) async -> Bool {
        await setPriority(item, to: TodoPriority.cycled(from: priority(for: item.id)))
    }

    /// 把某条待办写到指定档位：**先乐观更新 UI，再异步写回**；失败 → 回滚 + 记模块日志，不静默。
    ///
    /// 三条口径（docs/18 §接口与数据形状 4 与 §状态机与流程的「并发与幂等」）：
    ///
    /// 1. **幂等**：与当前档位同级 → `beginWrite` 返回 nil，**不写、也不动 UI**（先比对当前值）；
    /// 2. **乐观且先渲染**：`beginWrite` **同步**把新档位写进 `@Published priorityOverlay`
    ///    （`objectWillChange` 当场发出，SwiftUI 立刻把这次视图标脏），紧接着 `await Task.yield()`
    ///    **把主 actor 让出一轮**，让排队等主 actor 的工作（含这次 UI 更新）先跑。于是
    ///    **乐观值一定先于写回结果上屏**：写回这一侧是 async 的、且内部把 `save` 放到后台执行器
    ///    （见该 typealias），主线程在它整个执行期间都是空的——既不会被落盘 I/O 顶住，
    ///    也不会出现"等 EventKit 回来才变色"（"视图下一帧就是新档位"的准确含义）；
    /// 3. **失败回滚 / 成功转正**：写回返回 false → `rollback` 撤掉乐观值（显示值退回读回的真值）+
    ///    `writeFailure` 一行提示 + `log.error`（含提醒 id 与目标值），随后重取一次（提醒可能已被删，
    ///    让那一行自然消失）；成功 → `confirm` 把乐观值转正成基线，**不再立刻重取**：优先级不改变
    ///    条目归属与顺序，而写回走的是另一个 `EKEventStore` 实例，紧跟着重读可能拿到尚未失效的旧值、
    ///    把 UI 拉回旧档位——库变更由既有的 `EKEventStoreChanged` 监听收口。
    ///
    /// 「同级不产生第二次写回」这条口径由本方法第 1 条保证（用例经 `writePriority` 接缝直接驱动它）。
    @discardableResult
    func setPriority(_ item: TodoBucketing.Item, to target: TodoPriority) async -> Bool {
        guard hasFullAccess else {
            writeFailure = .storage("提醒未授权")
            log.warn("优先级写回跳过：提醒未授权")
            return false
        }

        // 同级 → nil：不写回、不动 UI（先比对当前值，见 TodoPriority.shouldWrite）。
        guard let step = priorityOverlay.beginWrite(item.id, to: target) else {
            log.info("优先级写回跳过：\(item.title)（\(item.id)）已是 \(target.rawValue)")
            return false
        }

        // 口径 2：乐观值先渲染——`beginWrite` 已同步发出 objectWillChange，这里让主 actor 一轮，
        // 让这次 UI 更新先跑；写回随后开始，且它的落盘在后台执行器上（不占主线程）。
        await Task.yield()

        guard await writePriority(item.id, step.eventKitValue) else {
            priorityOverlay.rollback(item.id)   // 回滚：显示值退回读回的真值
            let detail = "setReminderPriority 返回 false（提醒 id \(item.id)，目标 EventKit \(step.eventKitValue)）"
            lastErrorDescription = detail
            writeFailure = .storage(detail)
            log.error("优先级写回失败：\(item.title)（\(item.id)）→ \(step.priority.rawValue) / EventKit \(step.eventKitValue)")
            await refresh()
            return false
        }

        priorityOverlay.confirm(item.id)   // 乐观值转正（口径 3：不立刻重取，避免读到未失效的旧值）
        writeFailure = nil
        log.info("优先级写回：\(item.title) → \(step.priority.rawValue)（EventKit \(step.eventKitValue)）")
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

        #if DEBUG
        if let fixtureBackend {
            do {
                let date = dueDateComponents.flatMap { Calendar.autoupdatingCurrent.date(from: $0) }
                _ = try await fixtureBackend.createTodoReminder(title: finalTitle, due: date)
                writeFailure = nil
                await refresh()
                return true
            } catch { recordFixtureFailure(error); return false }
        }
        #endif
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

        #if DEBUG
        if let fixtureBackend {
            do {
                try await fixtureBackend.deleteReminder(id: item.id)
                writeFailure = nil
                await refresh()
                return true
            } catch { recordFixtureFailure(error); return false }
        }
        #endif
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
        #if DEBUG
        if let fixtureBackend {
            _ = await fixtureBackend.requestAccess(to: .reminder)
            authorization = authorizationStatus()
            await refresh()
            return
        }
        #endif
        do {
            _ = try await store.requestFullAccessToReminders()
        } catch {
            lastErrorDescription = String(describing: error)
            log.error("提醒授权请求抛错：\(String(describing: error))")
        }
        authorization = authorizationStatus()
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

    #if DEBUG
    private static func fixturePriority(_ priority: Priority?) -> TodoPriority {
        switch priority {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        case nil: return .none
        }
    }

    private func recordFixtureFailure(_ error: Error) {
        let detail = error.localizedDescription
        lastErrorDescription = detail
        writeFailure = .storage(detail)
        log.error("待办夹具写回失败：\(detail)")
    }
    #endif

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
    /// - `surfaces`：`expanded`（四视图左导航 + 右看板）+ `compact`（折叠态中央槽位：图标 + 今日 `已办/总量`）
    ///   + `home`（**首页块** = 表头一行 + 今日清单，**行数按块高算、行形态按块宽选**，
    ///   见 `TodosHomeBlockLayout`）；
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

    /// 首页块**高度申报**（docs/37 D-05；p13 按 docs/38 §做法 五 调到与通知块对齐）：
    /// 固定 = 顶部内缩 + 表头 + 6 行（按日程行高 34）= **228**。
    ///
    /// 改前不申报（紧凑档 96）——96 里只放得下表头 + 4 行待办，日程根本没有位置
    /// （用户 2026-10-10 反馈「应该显示今日日程，而不是光待办」「显示的区域过小」）。
    static var homeBlockHeight: ModuleHomeBlockHeight {
        .points(TodosHomeBlockLayout.blockHeight)
    }

    /// 首页块**宽度申报**（p13 / docs/38-home-v5-layout.md D-04 / D-12；docs/41 D-01/D-02）：`420 / 420` + **弹性**。
    ///
    /// **与通知取同一个 ideal（420）**：规则 ①′ 按弹性块的 ideal 等比分富余，ideal 相等 → 该行富余等分
    /// →「今日清单 + 通知」横向等宽（docs/41 D-01/D-02；行宽 855 → 各 423.5）。
    /// 通知关掉时它独占整行（弹性块吃满富余），这正是「用户少开一块时不留大片空白」的做法。
    static var homeBlockWidth: ModuleHomeBlockWidth? {
        ModuleHomeBlockWidth(
            min: TodosHomeBlockLayout.minimumBlockWidth,
            ideal: TodosHomeBlockLayout.idealBlockWidth
        )
    }

    /// **吃余量**（docs/38 D-04）：第三排两块都弹性，富余按各自 ideal 等比分配。
    static var homeBlockAbsorbsSurplus: Bool { true }

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
    /// 首页与展开 tab 共用 TodoBucketing 聚合；首页固定统计头、完整滚动并提供独立完成动作。
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
/// **三环不再服务任何 surface**（首页块也已换形态）：`TodoScopeRing` / `TodoRingPicker` /
/// `TodoRingLayout` 原样保留、不挂 surface，可逆。
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
    /// 左列固定宽度：图标（14）+ **最长的标签** + 计数徽标（20）放得下。
    ///
    /// 最长的标签是「已完成（近 7 天）」（P1 / T2 复审修 3：把 `completedWindowDays = 7`
    /// 这个可见窗口写进文案，标签因此从 3 个字变长约一倍）——列宽从 118 提到 150 容纳它，
    /// 标签另有 `minimumScaleFactor(0.8)` 兜底（再窄也只是缩一点，不会截成「已完成（近 …」）。
    static let columnWidth: CGFloat = 150
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
                .minimumScaleFactor(0.8)   // 「已完成（近 7 天）」放不进 150pt 时缩字，不截断
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
/// **不再被任何 surface 渲染**（P5 / T1 撤销首页块的三环横排，展开面板早已换成四视图）——
/// 与 `TodoScopeRing` / `TodoRingPicker` 一起原样保留，可逆。
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
/// **不再被任何 surface 渲染**（P1 / T2 起展开面板换成四视图左导航；P5 / T1 起首页块的三环横排
/// 也撤了）。这个视图与 `TodoRingLayout` / `TodoScopeRing` 一起**原样保留**——删除是最后手段，
/// 将来要回到面板或首页，把 `TodoRingPicker` 挂到某个 surface 上即可（可逆口径）。
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

// MARK: - 首页块（表头一行 + 今日清单）

/// 首页块尺寸与全量取舍。旧带 rowCount 的 helper 保留供历史调用，真实首页不消费容量裁剪。
/// 块高决定滚动视口，块宽决定宽窄行；统计头固定在滚动区上方。
enum TodosHomeBlockLayout {
    /// 清单的**行形态**（只有两档）。**纯值**：视图只按它选行视图，切换就是布局切换（无动画）。
    ///
    /// 任何宽度都保留完成圈；窄行省略过期标签。
    enum Tier: Equatable {
        /// 块宽 `>= compactListWidth`：完整行（状态圈 + 标题 + 已过期红字）。
        case full
        /// 更窄（或宽度取不到）：完成圈与标题，省去过期标签。
        case compact
    }

    /// 行形态分界线沿用 160pt；更窄时保留完成圈与标题，只省去过期标签。
    static let compactListWidth: CGFloat = 160

    /// 首页块的**宽度申报**（p13 / docs/38 D-04；docs/41 D-01/D-02）：最小 420（再窄就装不下「色条 + 标题 +
    /// 时间列」的完整日程行与右侧时间列），理想 **420**——**与通知取同一个 ideal**：规则 ①′ 按弹性块的
    /// ideal 等比分富余，ideal 相等 → 该行富余等分 →「今日清单 + 通知」横向等宽（docs/41 D-01/D-02；
    /// 行宽 855 → 各 423.5。改前 470，470 是 v5 设计稿里与通知并排那一档，见 docs/38）。
    static let minimumBlockWidth: CGFloat = 420
    static let idealBlockWidth: CGFloat = 420
    /// 表头一行的高度（`今天` + `已办/总量` + 细进度条）。
    static let headerHeight: CGFloat = 16
    /// 清单一行的高度：完整行与紧凑行**都钉在这个高度上**（行数是按它算的，行高必须是真的）。
    static let rowHeight: CGFloat = 16
    /// 表头与清单之间的间距。清单**行与行之间不留间距**（行高 16 已含行距）——`rowCount` 的算术
    /// 因此是「表头 + 一段间距 + N 行」。
    static let listSpacing: CGFloat = 4
    /// 历史容量 helper 的上限，真实首页不使用。
    static let maximumRows = 8

    // MARK: - 首页块尺寸（2026-10-10 / docs/37 D-05：今日日程与待办同一清单）

    /// **今日日程行**的高度（图标/色条 + 标题 + 时间，两行式）。p13 由 30 抬到 **34**：
    /// 与通知块（6 × 30）并排时两块申报高对齐（228 vs 225），行高不再差出一行。
    static let eventRowHeight: CGFloat = 34
    /// **今日待办行**的高度（在混合清单里与日程行**等高**：行高不齐会让清单读起来散。
    /// 状态圈 + 标题在 34 里居中——比旧 `rowHeight`(16) 松，因此不再复用 `rowCount` 的算术）。
    static let todoRowHeightInSchedule: CGFloat = 34
    /// 视口高度沿用六行预算；数据量没有六行上限，全部条目在单一滚动区内。
    static let maximumScheduleRows = 6

    /// 首页块申报的**固定高**（`TodosModule.homeBlockHeight` 引用它）。
    ///
    /// = **顶部内缩 4 + 表头 16 + 间距 4 + 6 × 34 = 228**（p13：行高 30 → **34**，
    /// docs/38-home-v5-layout.md §做法 五）。
    ///
    /// **为什么要与通知块对齐**：第三排是「今日清单 + 通知」**并排**（v5 设计稿），
    /// 行高 = 行内最高块——两块申报 228 / 225 时行高 228，短的（通知）余 3pt 落板底；
    /// 若沿用改前的 207，两块会差 20 余 pt 的空白，一眼就看得出没对齐。
    /// 视图侧的 `scheduleRowCount(fittingHeight:)` 吃的是**扣掉内缩之后**的高（与
    /// `ProgressHomeBlockLayout` 同一条口径：按真正拿到的高算行数），两条算式因此对齐——
    /// 申报高下必然画满 6 行。
    static var blockHeight: CGFloat {
        HomeBlockChrome.contentInsetTopListHeader
            + headerHeight + listSpacing
            + CGFloat(maximumScheduleRows) * eventRowHeight
    }

    /// **混合清单**的行数（块高 → 行数）：`floor((高 − 表头 − 间距) / 行高)`，钳 `0…maximumScheduleRows`。
    ///
    /// 与 `blockHeight` 是同一个算式的两个方向：`scheduleRowCount(fittingHeight: blockHeight) == 6`。
    /// 高度取不到（首帧 0 / NaN / ±∞）→ 0（先只画表头，下一帧就有真值）。
    static func scheduleRowCount(fittingHeight height: CGFloat) -> Int {
        guard height.isFinite else { return 0 }
        let usable = height - headerHeight - listSpacing
        guard usable > 0 else { return 0 }
        let fit = Int((usable / eventRowHeight).rounded(.down))
        return min(max(fit, 0), maximumScheduleRows)
    }

    /// 块高 → 清单行数：`floor((height − headerHeight − listSpacing) / rowHeight)`，钳 `0...maximumRows`。
    ///
    /// 高度取不到（首帧 `GeometryReader` 给 0 / NaN / ±∞）→ 0：那时布局还没算出来，先只画表头；
    /// 也不能让 `floor` 的结果直接进 `Int(_:)`（`Int(Double.nan)` / `Int(1e300)` 都是运行时陷阱）。
    static func rowCount(fittingHeight height: CGFloat) -> Int {
        guard height.isFinite else { return 0 }
        let rows = (height - headerHeight - listSpacing) / rowHeight
        guard rows.isFinite, rows > 0 else { return 0 }
        guard rows < CGFloat(maximumRows) else { return maximumRows }
        return Int(rows.rounded(.down))
    }

    /// 块宽 → 行形态。边界口径：`>= compactListWidth` → `.full`；更窄或非有限数（首帧 0 / NaN）→ `.compact`。
    ///
    /// 宽度取不到时使用紧凑行，保留独立完成圈。
    static func listTier(forWidth width: CGFloat) -> Tier {
        guard width.isFinite else { return .compact }
        return width >= compactListWidth ? .full : .compact
    }

    /// 清单要画的条目：按 `count`（= `rowCount(fittingHeight:)`）取前 N 条。
    /// 顺序沿用 `TodoBucketing` 的排序（不在这里另排一遍）。
    static func listedItems(_ items: [TodoBucketing.Item], count: Int) -> [TodoBucketing.Item] {
        guard count > 0 else { return [] }
        return Array(items.prefix(count))
    }

    /// **表头之下那段**该画什么（纯值）。
    enum TodayContent: Equatable {
        /// 今日条目（已按行数截好）。
        case rows([TodoBucketing.Item])
        /// 今日确实 0 条（且那一行放得下）→ 空态文案。
        case empty
        /// 什么都不画，只留表头。
        case nothing
    }

    /// 表头之下的内容（纯函数，三条判据逐条定死；审查 2 / 3 的修复轮，2026-09-30）。
    ///
    /// | 判据 | 结果 | 为什么 |
    /// |---|---|---|
    /// | 没有完整授权 | `.nothing` | `store.items` 空是**「读不到」，不是「今天没事」**——画「今日无待办」是正面假断言（旧的三个空环只是静默，不做断言）。授权入口在展开 tab，首页块没有交互面 |
    /// | `rowCount == 0`（块高连一行都放不下） | `.nothing` | 空态行与清单行**同高**（`rowHeight`），块矮于「表头 + 间距 + 一行」时画它就溢出块高 |
    /// | 放得下且今日 0 条 | `.empty` | 有授权、有位置、确实没事——这时才该出现空态文案 |
    ///
    /// 第三条与第二条**不是同一个判断**：`rowCount == 0` 是「画不下」（宁可少画），今日 0 条是
    /// 「没有」（该说就说）。
    static func todayContent(
        todayItems: [TodoBucketing.Item],
        hasFullAccess: Bool,
        rowCount: Int
    ) -> TodayContent {
        guard hasFullAccess else { return .nothing }
        guard rowCount > 0 else { return .nothing }
        let rows = listedItems(todayItems, count: rowCount)
        return rows.isEmpty ? .empty : .rows(rows)
    }

    // MARK: - 混合清单（今日日程 + 今日待办，docs/37 D-05）

    /// 混合清单里的一条：**日程在前、待办在后**（同一条清单，两种行形态）。
    enum ScheduleEntry: Equatable, Identifiable {
        case event(EventModel)
        case todo(TodoBucketing.Item)

        var id: String {
            switch self {
            case .event(let event): return "event:" + event.id
            case .todo(let item): return "todo:" + item.id
            }
        }
        var recordID: String {
            switch self {
            case .event(let event): return event.id
            case .todo(let item): return item.id
            }
        }
    }

    /// 全量首页入口：按记录 ID 去重，容量只决定滚动区高度，不裁剪数据。
    static func uniqueTodos(_ items: [TodoBucketing.Item]) -> [TodoBucketing.Item] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    static func listedEntries(
        events: [EventModel], todos: [TodoBucketing.Item], hasFullAccess: Bool,
        hideCompletedReminders: Bool = false
    ) -> [ScheduleEntry] {
        var seen = Set<String>()
        let eventEntries = events.filter { !$0.type.isReminder && seen.insert($0.id).inserted }
            .sorted {
                if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
                if $0.start != $1.start { return $0.start < $1.start }
                return $0.id < $1.id
            }.map(ScheduleEntry.event)
        let todoEntries = hasFullAccess ? uniqueTodos(todos)
            .filter { !hideCompletedReminders || !$0.isCompleted }.map(ScheduleEntry.todo) : []
        return eventEntries + todoEntries
    }

    /// 当前锚点被隐藏时选下一条，其次上一条；操作非锚点条目不改变视口。
    static func anchor(afterRemoving id: String, from ids: [String], anchor: String?) -> String? {
        guard anchor == id, let index = ids.firstIndex(of: id) else { return anchor }
        return ids.dropFirst(index + 1).first ?? ids.prefix(index).last
    }

    /// 混合清单要画的条目（纯函数）：**日程按时间排在前面**（全天在最前，与日历卡片的 `ordered`
    /// 同一条口径——`partitionEvents` 的等价简化：全天在前、各自按 `start` 升序），待办按
    /// `TodoBucketing` 的既有次序接在后面；总数截到 `rowCount`。
    ///
    /// **未授权（`hasFullAccess == false`）时待办侧不给条目**——那读的是「读不到」而不是「今天没事」，
    /// 与 `todayContent` 的第一条判据同源；**日程侧不看这个开关**（日历事件走 EventKit 自己那条授权，
    /// 与提醒事项是两回事）。
    static func listedEntries(
        events: [EventModel],
        todos: [TodoBucketing.Item],
        hasFullAccess: Bool,
        rowCount: Int
    ) -> [ScheduleEntry] {
        guard rowCount > 0 else { return [] }
        let eventEntries = events
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.start < rhs.start
            }
            .map(ScheduleEntry.event)
        let todoEntries = hasFullAccess ? todos.map(ScheduleEntry.todo) : []
        return Array((eventEntries + todoEntries).prefix(rowCount))
    }

    /// 空态（「今天没有安排」）该不该画：**有完整授权 + 有一行的位置 + 日程与待办都确实为空**。
    ///
    /// 与旧 `todayContent` 的 `.empty` 判据同源，只多了一条「日程也为空」——日程有内容时清单非空、
    /// 这条本来就不会被问到。
    static func emptyStateShows(
        hasFullAccess: Bool,
        rowCount: Int,
        eventCount: Int,
        todoCount: Int
    ) -> Bool {
        hasFullAccess && rowCount > 0 && eventCount == 0 && todoCount == 0
    }
}

/// 固定统计头，下方单一滚动区展示日程与待办；轻量完成和详情导航彼此独立。
private struct TodosHomeBlockView: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject var store: TodoStore
    @ObservedObject private var calendarManager = CalendarManager.shared
    @ObservedObject private var session = CalendarPanelSession.shared
    @ObservedObject private var registry = ModuleRegistry.shared
    @Default(.hideCompletedReminders) private var hideCompletedReminders
    @Default(.hideAllDayEvents) private var hideAllDayEvents
    @State private var actionError: String?
    @State private var completingItemID: String?
    @State private var scrollToken = UUID()

    private var summary: TodoBucketing.Summary {
        TodoBucketing.classify(TodosHomeBlockLayout.uniqueTodos(store.items))
    }
    private var todayEvents: [EventModel] {
        HomeTodayEvents.filtered(calendarManager.todayEvents, now: Date(), hideAllDayEvents: hideAllDayEvents)
    }
    private var canOpenDetail: Bool { registry.tabEntries.contains { $0.id == CalendarModule.moduleID } }
    private var entries: [TodosHomeBlockLayout.ScheduleEntry] {
        TodosHomeBlockLayout.listedEntries(
            events: todayEvents, todos: summary.today.items, hasFullAccess: store.hasFullAccess,
            hideCompletedReminders: hideCompletedReminders
        )
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: TodosHomeBlockLayout.listSpacing) {
                TodoHomeHeader(result: summary.today, eventCount: todayEvents.count)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("home-counts")
                if let actionError {
                    Text(actionError).font(.caption).foregroundStyle(.red)
                        .accessibilityIdentifier("home-error")
                }
                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical) {
                        TodoHomeTodayList(
                            entries: entries, tier: TodosHomeBlockLayout.listTier(forWidth: proxy.size.width),
                            canOpenDetail: canOpenDetail && !session.isSubmitting && completingItemID == nil,
                            isSubmitting: session.isSubmitting || completingItemID != nil,
                            openEvent: openDetail, openTodo: openTodo, completeTodo: completeTodo
                        )
                        if entries.isEmpty, store.hasFullAccess { TodoHomeEmptyRow() }
                    }
                    .scrollPosition(id: $session.homeScrollAnchor, anchor: .top)
                    .accessibilityIdentifier("home-today-scroll")
                    .onAppear {
                        if let anchor = session.homeScrollAnchor {
                            scrollProxy.scrollTo(anchor, anchor: .top)
                        }
                    }
                    .onHover { vm.setScrollGestureSuppression($0, token: scrollToken) }
                }
            }
            .padding(.top, HomeBlockChrome.contentInsetTopListHeader)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task { await store.refresh() }
        .onDisappear { vm.setScrollGestureSuppression(false, token: scrollToken) }
    }

    private func openDetail(_ event: EventModel) {
        guard canOpenDetail, !session.isSubmitting else { return }
        session.showDetail(event, source: .home(anchor: session.homeScrollAnchor ?? event.id))
        vm.coordinator.selectModule(CalendarModule.moduleID)
    }

    private func openTodo(_ item: TodoBucketing.Item) {
        guard let event = calendarManager.event(withID: item.id) else {
            actionError = CalendarMutationError.recordNotFound.localizedDescription
            return
        }
        openDetail(event)
    }

    private func completeTodo(_ item: TodoBucketing.Item) {
        guard !session.isSubmitting, completingItemID == nil else { return }
        actionError = nil
        guard let event = calendarManager.event(withID: item.id) else {
            actionError = CalendarMutationError.recordNotFound.localizedDescription
            return
        }
        let ids = entries.map(\.recordID)
        completingItemID = item.id
        Task {
            defer { completingItemID = nil }
            let succeeded = await session.complete(event, completed: !item.isCompleted)
            if succeeded {
                if hideCompletedReminders && !item.isCompleted && vm.coordinator.currentView == .home {
                    session.homeScrollAnchor = TodosHomeBlockLayout.anchor(
                        afterRemoving: item.id, from: ids, anchor: session.homeScrollAnchor
                    )
                }
                await store.refresh()
            } else {
                actionError = session.completionError ?? TodoText.localized("module.todos.writeFailed")
            }
        }
    }
}

/// 首页块的表头一行：类别名（`今天`）+ `已办/总量` + （有日程时）`N 项日程` + 细进度条。
///
/// 计数与细条都取 `BucketResult` 的派生值（`counterText` / `progress`），与展开 tab 的今日数、
/// 旧三环的环心**同一份聚合**——「表头计数与展开面板今日数不一致」因此不是两个数各算一遍的问题，
/// 而是同一个数。字号比清单行略小（10）、加粗，让它在视觉上是一行**表头**而不是清单的一条。
///
/// **2026-10-10 / docs/37 D-05**：清单里加了「今日日程」之后，表头也要交代日程有几条
///（`N 项日程`，只有日程非空时才出现——没有日程时不画一个恒为 0 的计数）。
private struct TodoHomeHeader: View {
    let result: TodoBucketing.BucketResult
    /// 今日日程条数（0 = 不画那一段）。
    let eventCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(LocalizedStringKey(TodoBucketing.Bucket.today.labelKey))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .fixedSize()

            // 先拼 String 再给 `Text`（verbatim 重载），`1/4` 不去查本地化表（同环心口径）。
            Text(result.counterText)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .fixedSize()

            if eventCount > 0 {
                Text(String(format: TodoText.localized("module.todos.homeEventCount"), eventCount))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .fixedSize()
            }

            ProgressView(value: result.progress)
                .progressViewStyle(.linear)
                .frame(maxWidth: .infinity)
        }
        .frame(height: TodosHomeBlockLayout.headerHeight)
    }
}

/// 今日 0 条时的一行浅色空态（`module.todos.home.empty`）。
///
/// 取代旧的「三个 0/0 的环」：环是聚合计数，读不出「哪件事该做」，而空态要回答的正是
/// 「今天有没有事」。高度同样钉在 `rowHeight` 上，块的竖向账目因此与清单态一致。
///
/// **不是「今日 0 条」就画**：只在**有完整授权 + 块高放得下这一行 + 今日确实 0 条**时才出现
/// （判据在 `TodosHomeBlockLayout.todayContent`）——未授权时的空表是「读不到」，不是「没有」。
private struct TodoHomeEmptyRow: View {
    var body: some View {
        Text(LocalizedStringKey("module.todos.home.empty"))
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.5))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: TodosHomeBlockLayout.rowHeight)
    }
}

/// 两个组共用一个滚动区；行 ID 同时供来源锚点与 UI 验收使用。
private struct TodoHomeTodayList: View {
    let entries: [TodosHomeBlockLayout.ScheduleEntry]
    let tier: TodosHomeBlockLayout.Tier
    let canOpenDetail: Bool
    let isSubmitting: Bool
    let openEvent: (EventModel) -> Void
    let openTodo: (TodoBucketing.Item) -> Void
    let completeTodo: (TodoBucketing.Item) -> Void

    private var eventEntries: [TodosHomeBlockLayout.ScheduleEntry] {
        entries.filter { if case .event = $0 { return true }; return false }
    }
    private var todoEntries: [TodosHomeBlockLayout.ScheduleEntry] {
        entries.filter { if case .todo = $0 { return true }; return false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !eventEntries.isEmpty {
                groupHeader("calendar.quickAdd.kindEvent")
                ForEach(eventEntries, id: \.recordID) { entry in
                    if case .event(let event) = entry {
                        TodoHomeEventRow(event: event, open: { openEvent(event) })
                            .disabled(!canOpenDetail)
                            .id(event.id)
                    }
                }
            }
            if !todoEntries.isEmpty {
                groupHeader("calendar.quickAdd.kindReminder")
                ForEach(todoEntries, id: \.recordID) { entry in
                    if case .todo(let item) = entry {
                        TodoHomeRow(
                            item: item, tier: tier, canOpenDetail: canOpenDetail, isSubmitting: isSubmitting,
                            open: { openTodo(item) }, complete: { completeTodo(item) }
                        ).id(item.id)
                    }
                }
            }
        }
        // Measure all today's rows so restoration uses their actual positions rather than lazy estimates.
        .scrollTargetLayout()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func groupHeader(_ key: String) -> some View {
        Text(LocalizedStringKey(key)).font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55)).padding(.vertical, 4)
    }
}

private struct TodoHomeEventRow: View {
    let event: EventModel
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(event.calendar.color)).frame(width: 4, height: 24)
                Text(event.title).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 6)
                Text(TodoText.eventTimeLabel(for: event))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit().foregroundStyle(.white.opacity(0.6)).lineLimit(1).fixedSize()
            }.frame(height: TodosHomeBlockLayout.eventRowHeight)
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("home-item-" + event.id)
    }
}

/// 宽窄两档都有独立完成圈；窄行只省去过期标签。
private struct TodoHomeRow: View {
    let item: TodoBucketing.Item
    let tier: TodosHomeBlockLayout.Tier
    let canOpenDetail: Bool
    let isSubmitting: Bool
    let open: () -> Void
    let complete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: complete) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(item.isCompleted ? 0.35 : 0.8))
                    .frame(width: 20, height: 24).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(isSubmitting)
                .accessibilityLabel(Text(LocalizedStringKey(item.isCompleted ? "calendar.panel.markIncomplete" : "calendar.panel.markComplete")))
                .accessibilityIdentifier("home-complete-" + item.id)
            Button(action: open) {
                HStack(spacing: 4) {
                    Text(item.title).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(item.isCompleted ? 0.4 : 0.95))
                        .strikethrough(item.isCompleted, color: .white.opacity(0.4))
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                    if tier == .full, TodoText.isOverdue(item) {
                        Text(LocalizedStringKey("module.todos.overdue"))
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(.red).fixedSize()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(!canOpenDetail)
                .accessibilityIdentifier("home-item-" + item.id)
        }.frame(height: TodosHomeBlockLayout.todoRowHeightInSchedule)
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
        // 整行底色走首页那条唯一的 hover 规则（T8 / docs/26 §做法 机制七）——本行原先自己写的是
        // `cornerRadius: 6` + `opacity 0.06`（浓度本来就对，形状与取值现统一由 `HomeBandChrome` 给）。
        .homeBlockHoverBackground(isHovered: isHovered)
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
/// 模块内文字口径（计数、过期判定、日程时间列）——**不是 private**：这几条是纯函数，
/// 单测直接钉住（`ModuleKernelTests` 的 `testTodoTextEventTimeLabel` 一族）。
enum TodoText {
    /// 计数徽标 / 看板标题上的数字（verbatim：`3` 不该去查本地化表）。
    static func countText(_ count: Int) -> String { "\(count)" }

    /// 模块内动态文案的本地化出口（查不到时 `Bundle` 原样返回 key，与 `NotificationText.localized` 同款）。
    static func localized(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }

    /// **日程行右侧的时间列文案**（docs/37 D-05 的纯函数，单测直接钉）：
    /// 全天 → `全天`（`module.todos.homeAllDay`，与日历卡片的时间列同一口径）；
    /// 定时 → `9:30`（起点）或 `9:30 – 10:30`（同一天内、止点大于起点时给区间）。
    ///
    /// 跨天日程的时间列只给起点（首页块是「今天」的清单，跨天那一段的语义在卡片里有完整呈现）。
    static func eventTimeLabel(
        for event: EventModel,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        if event.isAllDay { return localized("module.todos.homeAllDay") }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        guard calendar.isDate(event.end, inSameDayAs: event.start), event.end > event.start else {
            return start
        }
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return start + " – " + end
    }

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
