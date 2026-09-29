/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Defaults
import EventKit
import SwiftUI

// MARK: - CalendarManager

@MainActor
class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    @Published var currentWeekStartDate: Date
    /// **按日**窗口（`[选中日, +1 天)`）的条目：今日清单（`HomeCalendarRow` 右栏 /
    /// `EventListView`）与独立日历面板右栏（`StandaloneEventCardList`）的数据源。
    /// `updateEvents` 是它唯一的赋值点。**月历标记不用它**（见 `monthEvents`）。
    @Published var events: [EventModel] = []
    /// **按月**窗口的条目快照（与 `events` 完全独立的一条数据路径，2026-09-29 补）。
    ///
    /// 为什么必须单开一条：`events` 的窗口只有一天（选中日），拿它算「月历上哪些天有事件」等于
    /// **除选中日外整月的格子永远不会有标记**——这正是上一版标记「基本无用」的原因。
    ///
    /// 窗口 = 显示月份**首日所在周的起点 → 末日所在周的终点**（`MonthGridLayout.monthWindow`，
    /// 与月历网格 `days(forMonth:)` 逐日同源、含跨月补格），查询与权限**沿用**既有
    /// `CalendarService.events(from:to:calendars:)`（不新增权限、不新增查询口径）。
    ///
    /// 触发点（不轮询）：① `MonthGridView` 在**显示月份变化**时通知宿主调一次
    /// `updateMonthEvents(for:)`（含首次出现）；② 既有 `EKEventStoreChanged` 监听里、且**只在
    /// 已经有人要过按月数据时**重抓一次（`refreshRequestedMonthEvents()`）——不打开日历行的用户
    /// 不为这条数据付任何查询代价。
    ///
    /// 条目**未过滤**：已完成提醒 / 全天条目的隐藏偏好由显示侧（宿主）走
    /// `EventListView.filteredEvents` 施加，与右侧今日清单同一条链路。
    @Published private(set) var monthEvents: MonthEventSnapshot = .empty
    @Published var allCalendars: [CalendarModel] = []
    @Published var eventCalendars: [CalendarModel] = []
    @Published var reminderLists: [CalendarModel] = []
    @Published var selectedCalendarIDs: Set<String> = []
    @Published var calendarAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var reminderAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var lockScreenEvents: [EventModel] = []

    private var lockScreenPreviewEvents: [EventModel]?
    /// 最近一次发出按月请求的月份：`monthEvents` 的**最后一次请求为准**判据（快速连翻月份时
    /// 丢弃迟到的旧响应，见 `updateMonthEvents(for:force:)`）。
    private var requestedMonth: Date?

    private var selectedCalendars: [CalendarModel] = []
    private let calendarService = CalendarService()
    private var lastEventsFetchDate: Date?
    private let reloadRefreshInterval: TimeInterval = 15
    private var eventStoreChangedObserver: NSObjectProtocol?
    private var pendingEventStoreRefreshTask: Task<Void, Never>?
    private var nextAllowedEventStoreRefresh: Date = .distantPast
    private var ignoreEventStoreChangesUntil: Date = .distantPast
    private let eventStoreChangeThrottle: TimeInterval = 20
    private let selfInducedChangeSuppression: TimeInterval = 6
    private let eventFetchLimiter = EventFetchLimiter()
    private var lastLockScreenEventsFetchDate: Date?
    private let lockScreenRefreshInterval: TimeInterval = 15
    private var lockScreenRefreshTask: Task<Void, Never>?

    var hasCalendarAccess: Bool { isAuthorized(calendarAuthorizationStatus) }
    var hasReminderAccess: Bool { isAuthorized(reminderAuthorizationStatus) }

    private init() {
        currentWeekStartDate = CalendarManager.startOfDay(Date())
        setupEventStoreChangedObserver()
        startLockScreenRefreshLoop()
        Task {
            await reloadCalendarAndReminderLists()
        }
    }

    deinit {
        if let observer = eventStoreChangedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        pendingEventStoreRefreshTask?.cancel()
        lockScreenRefreshTask?.cancel()
    }

    private func setupEventStoreChangedObserver() {
        eventStoreChangedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleEventStoreChanged()
        }
    }

    private func handleEventStoreChanged() {
        Logger.log("CalendarManager: Event store changed notification received", category: .lifecycle)
        let now = Date()
        guard now >= ignoreEventStoreChangesUntil else { return }

        if now < nextAllowedEventStoreRefresh {
            let delay = max(nextAllowedEventStoreRefresh.timeIntervalSince(now), 0.05)
            scheduleEventStoreRefresh(after: delay)
            return
        }

        nextAllowedEventStoreRefresh = now.addingTimeInterval(eventStoreChangeThrottle)
        scheduleEventStoreRefresh(after: 0)
    }

    private func scheduleEventStoreRefresh(after delay: TimeInterval) {
        pendingEventStoreRefreshTask?.cancel()
        pendingEventStoreRefreshTask = Task { [weak self] in
            guard let self else { return }
            if delay > 0 {
                let nanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            await self.performEventStoreRefresh()
        }
    }

    @MainActor
    private func performEventStoreRefresh() async {
        pendingEventStoreRefreshTask = nil
        await reloadCalendarAndReminderLists()
        await maybeRefreshEventsAfterReload()
        await updateLockScreenEvents(force: true)
        // 复用同一个既有监听刷新按月数据（只在已经有人要过按月数据时；节流与抑制口径同上）。
        await refreshRequestedMonthEvents()
        nextAllowedEventStoreRefresh = Date().addingTimeInterval(eventStoreChangeThrottle)
        ignoreEventStoreChangesUntil = Date().addingTimeInterval(selfInducedChangeSuppression)
    }

    @MainActor
    func reloadCalendarAndReminderLists() async {
        let allCalendars = await calendarService.calendars()
        eventCalendars = allCalendars.filter { !$0.isReminder }
        reminderLists = allCalendars.filter { $0.isReminder }
        self.allCalendars = allCalendars
        updateSelectedCalendars()
    }

    @MainActor
    private func maybeRefreshEventsAfterReload() async {
        guard hasCalendarAccess else { return }
        let now = Date()
        if let lastFetch = lastEventsFetchDate, now.timeIntervalSince(lastFetch) < reloadRefreshInterval {
            return
        }
        await updateEvents()
    }

    private func isAuthorized(_ status: EKAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .fullAccess:
            return true
        default:
            return false
        }
    }

    func checkCalendarAuthorization() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        calendarAuthorizationStatus = status

        switch status {
        case .notDetermined:
            let granted = await calendarService.requestAccess(to: .event)
            calendarAuthorizationStatus = granted ? .fullAccess : .denied
            if granted {
                await reloadCalendarAndReminderLists()
                await updateEvents(force: true)
                await updateLockScreenEvents(force: true)
            }
        case .restricted, .denied:
            NSLog("Calendar access denied or restricted")
        case .authorized, .fullAccess:
            await reloadCalendarAndReminderLists()
            await updateEvents(force: true)
            await updateLockScreenEvents(force: true)
        case .writeOnly:
            NSLog("Calendar write only")
        @unknown default:
            NSLog("Unknown calendar authorization status")
        }
    }

    func checkReminderAuthorization() async {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        reminderAuthorizationStatus = status

        switch status {
        case .notDetermined:
            let granted = await calendarService.requestAccess(to: .reminder)
            reminderAuthorizationStatus = granted ? .fullAccess : .denied
            if granted {
                await reloadCalendarAndReminderLists()
            }
        case .restricted, .denied:
            NSLog("Reminder access denied or restricted")
        case .authorized, .fullAccess:
            await reloadCalendarAndReminderLists()
        case .writeOnly:
            NSLog("Reminder write only")
        @unknown default:
            NSLog("Unknown reminder authorization status")
        }
    }

    func updateSelectedCalendars() {
        switch Defaults[.calendarSelectionState] {
        case .all:
            selectedCalendarIDs = Set(allCalendars.map { $0.id })
        case .selected(let identifiers):
            selectedCalendarIDs = identifiers
        }

        selectedCalendars = allCalendars.filter { selectedCalendarIDs.contains($0.id) }
    }

    func getCalendarSelected(_ calendar: CalendarModel) -> Bool {
        selectedCalendarIDs.contains(calendar.id)
    }

    func setCalendarSelected(_ calendar: CalendarModel, isSelected: Bool) async {
        var selectionState = Defaults[.calendarSelectionState]

        switch selectionState {
        case .all:
            if !isSelected {
                let identifiers = Set(allCalendars.map { $0.id }).subtracting([calendar.id])
                selectionState = .selected(identifiers)
            }
        case .selected(var identifiers):
            if isSelected {
                identifiers.insert(calendar.id)
            } else {
                identifiers.remove(calendar.id)
            }

            if identifiers.isEmpty || identifiers.count == allCalendars.count {
                selectionState = .all
            } else {
                selectionState = .selected(identifiers)
            }
        }

        Defaults[.calendarSelectionState] = selectionState
        updateSelectedCalendars()
        await updateEvents(force: true)
        await updateLockScreenEvents(force: true)
        // 月历标记走的是按 `selectedCalendars` 抓的**另一份**数据：换日历勾选后它也必须跟着换，
        // 否则取消勾选的日历的事件会继续在月历上留点。
        await refreshRequestedMonthEvents()
    }

    static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    func updateCurrentDate(_ date: Date) async {
        currentWeekStartDate = Calendar.current.startOfDay(for: date)
        await updateEvents(force: true)
        await updateLockScreenEvents(force: true)
    }

    func updateLockScreenEvents(force: Bool = false) async {
        if let previewEvents = lockScreenPreviewEvents {
            if lockScreenEvents != previewEvents {
                withAnimation(.smooth(duration: 0.25)) {
                    lockScreenEvents = previewEvents
                }
            }
            lastLockScreenEventsFetchDate = Date()
            return
        }

        let now = Date()

        if !force,
           let lastFetch = lastLockScreenEventsFetchDate,
           now.timeIntervalSince(lastFetch) < lockScreenRefreshInterval {
            return
        }

        let lookaheadRaw = Defaults[.lockScreenCalendarEventLookaheadWindow]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let isAllTimeLookahead =
            lookaheadRaw == "all_time" ||
            lookaheadRaw == "all time" ||
            lookaheadRaw == "alltime"

        let isRestOfDay =
            lookaheadRaw == "rest_of_day" ||
            lookaheadRaw == "rest of the day" ||
            lookaheadRaw == "restofday"

        func lookaheadMinutes(from raw: String) -> Int? {
            switch raw {
            case "15m", "15 min", "15 mins", "15min", "15mins": return 15
            case "30m", "30 min", "30 mins", "30min", "30mins": return 30
            case "1h", "1 hr", "1 hour", "1hour": return 60
            case "3h", "3 hr", "3 hours", "3hours": return 180
            case "6h", "6 hr", "6 hours", "6hours": return 360
            case "12h", "12 hr", "12 hours", "12hours": return 720
            default: return nil
            }
        }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let startDate = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday

        let endDate: Date
        if isAllTimeLookahead {
            endDate = calendar.date(byAdding: .day, value: 365, to: now) ?? now.addingTimeInterval(365 * 24 * 3600)
        } else if isRestOfDay {
            endDate = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday.addingTimeInterval(24 * 3600)
        } else if let minutes = lookaheadMinutes(from: lookaheadRaw) {
            endDate = calendar.date(byAdding: .minute, value: minutes, to: now) ?? now.addingTimeInterval(TimeInterval(minutes * 60))
        } else {
            endDate = calendar.date(byAdding: .minute, value: 180, to: now) ?? now.addingTimeInterval(180 * 60)
        }

        let calendarIDs = allCalendars.map { $0.id }
        let service = calendarService

        let fetched = await eventFetchLimiter.run {
            await service.events(from: startDate, to: endDate, calendars: calendarIDs)
        }

        if lockScreenEvents == fetched {
            lastLockScreenEventsFetchDate = Date()
            return
        }

        withAnimation(.smooth(duration: 0.25)) {
            lockScreenEvents = fetched
        }
        lastLockScreenEventsFetchDate = Date()
    }

    func setLockScreenPreviewEvents(_ events: [EventModel]?) {
        lockScreenPreviewEvents = events
        guard let events else {
            Task { await updateLockScreenEvents(force: true) }
            return
        }
        withAnimation(.smooth(duration: 0.25)) {
            lockScreenEvents = events
        }
        lastLockScreenEventsFetchDate = Date()
    }

    private func startLockScreenRefreshLoop() {
        lockScreenRefreshTask?.cancel()
        lockScreenRefreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                if Task.isCancelled { break }
                guard self.hasCalendarAccess else { continue }
                await self.updateLockScreenEvents(force: false)
            }
        }
    }

    private func updateEvents(force: Bool = false) async {
        let now = Date()
        if !force, let lastFetch = lastEventsFetchDate, now.timeIntervalSince(lastFetch) < reloadRefreshInterval {
            return
        }
        
        Logger.log("CalendarManager: Updating events (force: \(force))", category: .lifecycle)

        let calendarIDs = selectedCalendars.map { $0.id }
        let startDate = currentWeekStartDate
        guard let endDate = Calendar.current.date(byAdding: .day, value: 1, to: currentWeekStartDate) else { return }
        let service = calendarService

        let events = await eventFetchLimiter.run {
            await service.events(
                from: startDate,
                to: endDate,
                calendars: calendarIDs
            )
        }

        self.events = events
        lastEventsFetchDate = Date()
    }

    /// 抓取（或复用）**某个显示月份**的按月数据，写进 `monthEvents`（窗口与理由见该属性的注释）。
    ///
    /// 三条口径：
    /// 1. **按月去重**：已经有了同一个月的快照就不再查（`force` 可越过）。翻月才查一次，
    ///    同一月份内点日期 / 重开面板都不产生新查询；
    /// 2. **最后一次请求为准**：连翻两个月份会有两个请求在飞，晚到的旧响应被丢弃
    ///    （否则「翻到 10 月又马上翻回 9 月」会把 10 月的条目画在 9 月的网格上）；
    /// 3. 没有日历权限时不动 `monthEvents`（键保持 `nil`，下次请求会重试）。
    ///
    /// - Parameter month: 显示月份里的任意日期（内部归一化到该月 1 日零点）。
    func updateMonthEvents(for month: Date, force: Bool = false) async {
        let normalizedMonth = MonthGridLayout.firstDay(ofMonth: month)
        if !force, monthEvents.month == normalizedMonth { return }
        // 权限读数**直取 EventKit**，而不是用 `hasCalendarAccess`（它读的 @Published
        // `calendarAuthorizationStatus` 只在 `checkCalendarAuthorization()` 被调过之后才有真值，
        // 而那条链路只挂在设置页与锁屏天气小部件上、不在应用启动链上）——按它守门的话，没打开过
        // 设置页的机器上按月数据**一次都抓不到**，月历会一个点都没有。这里只读不写：授权状态本身
        // 仍由既有链路维护。（`CalendarService.events` 内部也各自按 EventKit 状态决定查哪一类。）
        guard isAuthorized(EKEventStore.authorizationStatus(for: .event)),
              let window = MonthGridLayout.monthWindow(forMonth: normalizedMonth)
        else { return }

        Logger.log("CalendarManager: Updating month events (force: \(force))", category: .lifecycle)

        requestedMonth = normalizedMonth

        let calendarIDs = selectedCalendars.map { $0.id }
        let service = calendarService

        let fetched = await eventFetchLimiter.run {
            await service.events(from: window.start, to: window.end, calendars: calendarIDs)
        }

        guard requestedMonth == normalizedMonth else { return }
        monthEvents = MonthEventSnapshot(month: normalizedMonth, events: fetched)
    }

    /// 把**已经要过**的那个月重抓一次（选择日历 / 事件库发生变化后调用，让月历标记跟着变）。
    /// 没人要过按月数据（`monthEvents.month == nil`）时什么也不做——不给不打开日历行的用户白查。
    private func refreshRequestedMonthEvents() async {
        guard let month = monthEvents.month else { return }
        await updateMonthEvents(for: month, force: true)
    }

    func setCalendarsSelected(_ calendars: [CalendarModel], isSelected: Bool) async {
        var selectionState = Defaults[.calendarSelectionState]
        let ids = Set(calendars.map { $0.id })

        switch selectionState {
        case .all:
            if !isSelected {
                let identifiers = Set(allCalendars.map { $0.id }).subtracting(ids)
                selectionState = .selected(identifiers)
            }
        case .selected(var identifiers):
            if isSelected {
                identifiers.formUnion(ids)
            } else {
                identifiers.subtract(ids)
            }

            if identifiers.isEmpty || identifiers.count == allCalendars.count {
                selectionState = .all
            } else {
                selectionState = .selected(identifiers)
            }
        }

        Defaults[.calendarSelectionState] = selectionState
        updateSelectedCalendars()
        await updateEvents(force: true)
        await updateLockScreenEvents(force: true)
        await refreshRequestedMonthEvents()
    }

    func setReminderCompleted(reminderID: String, completed: Bool) async {
        await calendarService.setReminderCompleted(reminderID: reminderID, completed: completed)
        await updateEvents(force: true)
        // 勾选/取消勾选会改变它是否被 `hideCompletedReminders` 过滤掉 → 月历上的点也要跟着变。
        await refreshRequestedMonthEvents()
    }

    /// 设置提醒的优先级（`EKReminder.priority`，0…9）——待办面板的行内优先级胶囊走这个入口
    /// （[docs/18](../../docs/18-p1-todos-and-order.md) §接口与数据形状 4）。
    ///
    /// **async 的理由（P1 / T2 复审修）**：`CalendarService.setReminderPriority` 内部把 **`save` 的
    /// 磁盘 I/O 放到后台执行器**上跑，这里 `await` 等它回来。于是调用方（`TodoStore.cyclePriority`）
    /// 在「乐观更新」与「写回完成」之间有一次**真正的挂起点**：主 actor 在这段区间是空的，
    /// SwiftUI 因此有机会先把新档位画出来（`docs/18` §并发与幂等「写回在后台任务里做」），
    /// 也不会因为 `commit: true` 的落盘把主线程顶住。
    ///
    /// **返回成功与否**（找不到提醒 / `save` 失败 → false）：调用方据此决定是否回滚 UI 上的乐观值。
    /// 这里**不抛错、不打日志**——失败细节由调用方落模块日志（`module.todos`），与「谁发起、谁记账」的分工一致。
    ///
    /// 写回沿用本文件既有的提醒写回口径：与 `setReminderCompleted` **同一条链**
    /// （`calendarService` 的同一个 `EKEventStore` + `commit: true`），不新开 store、不新增权限。
    /// 写完**不在这里刷日历数据**：优先级不参与日历行 / 月历标记的取数（`EventModel.priority`
    /// 只作为事件属性透传），库变更由既有的 `EKEventStoreChanged` 监听统一收口。
    @discardableResult
    func setReminderPriority(_ reminderID: String, priority: Int) async -> Bool {
        await calendarService.setReminderPriority(reminderID: reminderID, priority: priority)
    }
}

// MARK: - Event Fetch Limiter

private actor EventFetchLimiter {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isRunning = false

    func run<T>(_ operation: @escaping @Sendable () async -> T) async -> T {
        await waitTurn()
        defer { resumeNext() }
        return await operation()
    }

    private func waitTurn() async {
        if !isRunning {
            isRunning = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func resumeNext() {
        if waiters.isEmpty {
            isRunning = false
            return
        }

        let continuation = waiters.removeFirst()
        continuation.resume()
    }
}
