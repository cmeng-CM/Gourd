//
//  TodosModule.swift
//  Gourd 内置模块 · 待办（今日 / 本周 / 所有三环，P1 批次 / T5）
//
//  形态定稿（2026-09-28 用户反馈）：
//  - 展开态 = 顶部**三个环**（今日 / 本周 / 所有，52×52，环心为 `已办/总量`）+ 下方**该类别清单**；
//    三个环同时是**筛选器**（点击切换清单类别，默认今日）；选中态用环的类别色 + 标签加粗表达，
//    未选中一律 `.white.opacity(0.4)`；
//  - 折叠态 = 图标 + **今日**的 `已办/总量`（自带 60s `TimelineView`，宿主不起定时器，与 progress 同口径）；
//  - 分类与计数口径全在 `TodoBucketing`（纯函数，单测覆盖）。
//
//  **取数是本模块自己的 `EKEventStore`**（不改上游 `CalendarServiceProviding`，也不进 `CalendarManager`）：
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
//  `.delete` / `.deleteConfirm` / `.cancel` / `.writeFailed`。
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
/// 年 / 月 / 日**：与系统「提醒」App 的全天条目同形，读回时 `TodoText.dueText` 按
/// 「到期 == 当天起点」判为全天，只显示日期。
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

// MARK: - TodoStore

/// 待办的取数 / 写回 / 变更订阅。**模块自己持有** `EKEventStore`（理由见文件头）。
///
/// 只做「拿数据 + 写回」，分类交给 `TodoBucketing`、呈现交给视图；因此这里不持有任何选择态。
@MainActor
final class TodoStore: ObservableObject {
    /// 已完成提醒的取数窗口（天）。窗口口径与理由见文件头（[13](../../docs/13-runtime-kernel.md) D-21）。
    static let completedWindowDays = 7

    /// 归一化后的条目（未完成 + 窗口内已完成）。
    @Published private(set) var items: [TodoBucketing.Item] = []
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
    private var changedObserver: NSObjectProtocol?

    init(logger: ModuleLogger) {
        self.log = logger
    }

    /// 是否已拿到提醒的完整访问权限（= 可以取数）。
    var hasFullAccess: Bool { authorization == .fullAccess }

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
    func refresh() async {
        authorization = Self.currentAuthorization()
        guard hasFullAccess else {
            if !items.isEmpty { items = [] }
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
        var openCount = 0
        for reminder in allReminders where !reminder.isCompleted {
            merged[reminder.calendarItemIdentifier] = Self.item(from: reminder, calendar: calendar)
            openCount += 1
        }
        var doneCount = 0
        for reminder in recentCompleted where reminder.isCompleted {
            merged[reminder.calendarItemIdentifier] = Self.item(from: reminder, calendar: calendar)
            doneCount += 1
        }

        items = Array(merged.values)
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
    /// - `surfaces`：`expanded`（三环 + 清单）+ `compact`（折叠态中央槽位：图标 + 今日 `已办/总量`）；
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
        surfaces: [.expanded, .compact],
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

    /// 两个 surface 各给一份内容；未声明的 `lockscreen` 返回 `.none`（不占位、也不算失败）。
    func content(for request: ContentRequest) -> ModuleContent {
        switch request.surface {
        case .compact:
            return .view(AnyView(TodosCompactView(store: store)))
        case .expanded:
            return .view(AnyView(TodosModuleView(store: store)))
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

// MARK: - 展开面板视图（顶部三环 + 清单）

/// 展开面板：**顶部三环**（今日 / 本周 / 所有，环心 `已办/总量`，同时是筛选器）+ 下方选中类别的清单。
///
/// 分类在每次重算时按**当下**做（展开面板是瞬时视图；常驻的折叠态另有 60s `TimelineView` 负责跨零点）。
/// `.task` 只重取数据（**不碰权限**）：面板每次出现都刷一次，避免看到上一次的陈旧计数。
private struct TodosModuleView: View {
    @ObservedObject var store: TodoStore

    /// 当前筛选的类别，默认「今日」（设计定稿）。
    @State private var scope: TodoBucketing.Bucket = .today

    private var summary: TodoBucketing.Summary { TodoBucketing.classify(store.items) }

    var body: some View {
        Group {
            if store.hasFullAccess {
                VStack(spacing: 10) {
                    TodoRingPicker(summary: summary, selection: $scope)
                    TodoListView(result: summary.result(for: scope), store: store)
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

/// 三环横排：**环本身即筛选器**（点击切换下方清单的类别）。
private struct TodoRingPicker: View {
    let summary: TodoBucketing.Summary
    @Binding var selection: TodoBucketing.Bucket

    var body: some View {
        HStack(spacing: 20) {
            ForEach(TodoBucketing.Bucket.allCases, id: \.self) { bucket in
                TodoScopeRing(
                    bucket: bucket,
                    result: summary.result(for: bucket),
                    isSelected: bucket == selection
                )
                .onTapGesture { selection = bucket }
            }
        }
    }
}

/// 一个类别环：底环 + `trim` 进度环 + 环心 `已办/总量`，下方是类别标签。
///
/// 52×52（设计定稿）。`trim` 的进度 = 该类别的 `已办/总量`；总量为 0 时环为空、环心显示 `0/0`。
/// 选中态用类别色 + 标签加粗；未选中一律 `.white.opacity(0.4)`（黑底面板上的选中/未选中对比）。
private struct TodoScopeRing: View {
    let bucket: TodoBucketing.Bucket
    let result: TodoBucketing.BucketResult
    let isSelected: Bool

    /// 环的直径与线宽（设计定稿 52）。
    private static let diameter: CGFloat = 52
    private static let lineWidth: CGFloat = 4

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.15), lineWidth: Self.lineWidth)

                Circle()
                    .trim(from: 0, to: result.progress)
                    .stroke(arcColor, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                // 环心：`已办/总量`（先拼 String 再给 Text，走 verbatim 重载，不做本地化查表）。
                Text(result.counterText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(isSelected ? 1 : 0.4))
            }
            .frame(width: Self.diameter, height: Self.diameter)

            Text(LocalizedStringKey(bucket.labelKey))
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(.white.opacity(isSelected ? 1 : 0.4))
        }
        .contentShape(Rectangle())
    }

    private var arcColor: Color {
        isSelected ? Self.accent(for: bucket) : .white.opacity(0.4)
    }

    /// 三个类别的强调色（纯观感，不参与计算）。
    private static func accent(for bucket: TodoBucketing.Bucket) -> Color {
        switch bucket {
        case .today: return .blue
        case .week: return .green
        case .all: return .orange
        }
    }
}

/// 选中类别的清单：勾选框 + 标题 + 到期时间（**有到期时间才显示**，过期红）+ 所属列表名。
///
/// 顺序由 `TodoBucketing` 定死（未完成在前、已完成排最后），这里只渲染；
/// 条目多时滚动（面板高度有限），空清单显示 `module.todos.empty`。
///
/// **可增删**（2026-09-28 用户反馈「待办里面要可以增删待办内容」）：
/// - 顶部一行 `+` 展开内联输入（标题 + 今天 / 明天 / 无日期三选一），回车或「添加」写库；
/// - 每行 hover 出现垃圾桶图标 → **确认对话框**（写的是真实系统提醒）→ 确认后删库；
/// - 两者失败都在列表上方回显**一行**提示（`module.todos.writeFailed`），不静默、不崩；
/// - 增删只重取数据，**不动 `scope`**——当前选中的尺度筛选保持不变。
private struct TodoListView: View {
    let result: TodoBucketing.BucketResult
    @ObservedObject var store: TodoStore

    /// 内联输入行是否展开。
    @State private var isComposing = false
    /// 输入行里的标题草稿。
    @State private var draftTitle = ""
    /// 输入行里选中的日期选项（默认今天，与「今日」默认筛选一致）。
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
            addToggleRow

            if isComposing {
                composerRow
            }

            if store.writeFailure != nil {
                writeFailureRow
            }

            if result.items.isEmpty {
                Text(LocalizedStringKey("module.todos.empty"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(result.items) { item in
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

    // MARK: 新增

    /// 顶部一行：`+`（展开 / 收起输入行）。空态与有内容时都在，新增入口不会被清单长度藏起来。
    private var addToggleRow: some View {
        HStack(spacing: 6) {
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

            Spacer(minLength: 0)
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

/// 清单的一行：勾选框（点击写回完成）+ 标题 + 到期时间 + 所属列表名；已完成项置灰 + 删除线；
/// **hover 时行尾出现垃圾桶**（点击不直接删，交给上层弹确认框——删的是系统「提醒」里的真条目）。
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

            if let dueText = TodoText.dueText(for: item) {
                HStack(spacing: 4) {
                    if isOverdue {
                        Text(LocalizedStringKey("module.todos.overdue"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                    Text(dueText)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isOverdue ? .red : .white.opacity(0.6))
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

// MARK: - 文案出口

/// 模块内动态文案的唯一出口（06 §3.3 R5：视图内不写字面量文案）。
///
/// 到期时间与 `已办/总量` 都**先拼成 String 再给 `Text`**——走 `Text(_: String)` 的 verbatim 重载，
/// 不会把这些形态当成本地化 key 去查表。日历口径与 `TodoBucketing` 一致：`.autoupdatingCurrent`。
private enum TodoText {
    /// 到期时间的显示文本；**无到期时间 → nil（该行不显示到期时间）**。
    ///
    /// 当天 00:00 的到期时间按**全天提醒**处理，只显示日期（上游 `EventModel` 用
    /// `dueDateComponents.hour == nil` 判全天；这里等价地用「到期 == 当天起点」判，不额外给
    /// `Item` 加字段）；带时分的显示「月-日 时:分」。格式走 `Date.FormatStyle` 的本地化格式，
    /// 因此**不新增文案 key**（同 `ProgressText.interval` 的口径）。
    static func dueText(for item: TodoBucketing.Item, calendar: Calendar = .autoupdatingCurrent) -> String? {
        guard let dueDate = item.dueDate else { return nil }
        if dueDate == calendar.startOfDay(for: dueDate) {
            return dueDate.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
        }
        return dueDate.formatted(
            Date.FormatStyle()
                .month(.twoDigits)
                .day(.twoDigits)
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
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
