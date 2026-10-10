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

import Foundation
import EventKit

protocol CalendarServiceProviding {
    func requestAccess() async -> Bool
    func requestAccess(to type: EKEntityType) async -> Bool
    func calendars() async -> [CalendarModel]
    func events(from start: Date, to end: Date, calendars: [String]) async -> [EventModel]
    func setReminderCompleted(reminderID: String, completed: Bool) async
}

class CalendarService: CalendarServiceProviding {
    private let store = EKEventStore()
    
    @MainActor
    func requestAccess() async -> Bool {
        let eventsAccess = await requestAccess(to: .event)
        let remindersAccess = await requestAccess(to: .reminder)
        return eventsAccess || remindersAccess
    }

    @MainActor
    func requestAccess(to type: EKEntityType) async -> Bool {
        do {
            return try await performAccessRequest(for: type)
        } catch {
            print("Calendar access error: \(error)")
            return false
        }
    }

    private func performAccessRequest(for type: EKEntityType) async throws -> Bool {
        switch type {
        case .event:
            return try await store.requestFullAccessToEvents()
        case .reminder:
            return try await store.requestFullAccessToReminders()
        @unknown default:
            return false
        }
    }
    
    private func hasAccess(to entityType: EKEntityType) -> Bool {
        let status = EKEventStore.authorizationStatus(for: entityType)
        return status == .fullAccess
    }
    
    func calendars() async -> [CalendarModel] {
        var calendars: [EKCalendar] = []
        
        for type in [EKEntityType.event, .reminder] where hasAccess(to: type) {
            calendars.append(contentsOf: store.calendars(for: type))
        }
        
        return calendars.map { CalendarModel(from: $0) }
    }
    
    func events(from start: Date, to end: Date, calendars ids: [String]) async -> [EventModel] {
        let allCalendars = await self.calendars()
        let filteredCalendars = allCalendars.filter { ids.isEmpty || ids.contains($0.id) }
        let ekCalendars = filteredCalendars.compactMap { calendarModel in
            store.calendars(for: .event).first { $0.calendarIdentifier == calendarModel.id } ??
            store.calendars(for: .reminder).first { $0.calendarIdentifier == calendarModel.id }
        }
        
        var events: [EventModel] = []
        
        // Fetch regular events
        if hasAccess(to: .event) {
            let eventCalendars = ekCalendars.filter { store.calendars(for: .event).contains($0) }
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: eventCalendars)
            let ekEvents = store.events(matching: predicate)
            events.append(contentsOf: ekEvents.compactMap { EventModel(from: $0) })
        }
        
        // Fetch reminders
        if hasAccess(to: .reminder) {
            let reminderCalendars = ekCalendars.filter { store.calendars(for: .reminder).contains($0) }
            events.append(contentsOf: await fetchReminders(from: start, to: end, calendars: reminderCalendars))
        }
        
        return events.sorted { $0.start < $1.start }
    }
    
    private func fetchReminders(from start: Date, to end: Date, calendars: [EKCalendar]) async -> [EventModel] {
        guard !calendars.isEmpty else { return [] }

        return await withCheckedContinuation { continuation in
            let predicate = store.predicateForReminders(in: calendars)
            store.fetchReminders(matching: predicate) { reminders in
                guard let reminders else {
                    continuation.resume(returning: [])
                    return
                }

                let filtered = reminders.compactMap { reminder -> EventModel? in
                    guard let dueDate = reminder.dueDateComponents?.date,
                          dueDate >= start,
                          dueDate <= end else {
                        return nil
                    }
                    return EventModel(from: reminder)
                }

                continuation.resume(returning: filtered)
            }
        }
    }

    @MainActor
    func setReminderCompleted(reminderID: String, completed: Bool) async {
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else { return }
        reminder.isCompleted = completed
        do {
            try store.save(reminder, commit: true)
        } catch {
            print("Failed to update reminder completion: \(error)")
        }
    }

    /// 设置提醒的优先级（`EKReminder.priority`，0…9）。**返回成功与否**——
    /// 找不到提醒（已在「提醒」App 里被删）或 `save` 抛错都返回 false，调用方据此回滚 UI 上的乐观值。
    ///
    /// **不在主线程上做磁盘 I/O**（P1 / T2 复审修）：取值与 `commit: true` 的 `save` 放进
    /// `Task.detached(priority: .userInitiated)`，结果 hop 回调用方——因此这个方法是
    /// `nonisolated async`：主 actor 在 `await` 期间是空的，UI 可以先画乐观值，点胶囊不会卡在落盘上。
    /// `EKEventStore` 的存取从后台线程调用是既有的常见做法（本文件既有的 `fetchReminders(matching:)`
    /// 也是「EventKit 回调 + 延续式包一层」的形态，那个回调本来就不在主线程）。
    ///
    /// 与 `setReminderCompleted` **同一条写回链**：同一个 `EKEventStore`、`commit: true`，
    /// 不新开 store、不新增权限（[docs/18](../../docs/18-p1-todos-and-order.md) §接口与数据形状 4）。
    /// 不写进 `CalendarServiceProviding` 协议：本批**不改对外契约**（设计分级），
    /// 调用方 `CalendarManager` 持有的是具体类型 `CalendarService`。
    nonisolated func setReminderPriority(reminderID: String, priority: Int) async -> Bool {
        let store = self.store
        return await Task.detached(priority: .userInitiated) {
            guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else {
                return false
            }
            reminder.priority = priority
            do {
                try store.save(reminder, commit: true)
                return true
            } catch {
                print("Failed to update reminder priority: \(error)")
                return false
            }
        }.value
    }

    // MARK: - 新增（P11 / T5：两处日历的「+」快速新增待办与日程）

    /// 新建一条待办（`EKReminder`，docs/36 §做法 机制三）。
    ///
    /// **目标列表**：`defaultCalendarForNewReminders()` 兜第一个 `.reminder` 日历；一个都没有 → `false`
    /// （调用方给失败提示，不重试）。`dueDateComponents` **允许 nil**——无日期的待办也是合法输入
    /// （本批表单总是传选中日的年月日，nil 只留给直接调用这个服务的路径）。
    ///
    /// 写档口径与 `setReminderPriority` 完全一致：`nonisolated` + `Task.detached(priority: .userInitiated)`，
    /// `commit: true` 的磁盘 I/O 不在主线程；成功 `true`、失败 `false` 并把细节 `print` 到控制台。
    /// 不进 `CalendarServiceProviding` 协议（本批不改对外契约），调用方 `CalendarManager` 持有具体类型。
    nonisolated func createReminder(title: String, dueDateComponents: DateComponents?) async -> Bool {
        let store = self.store
        return await Task.detached(priority: .userInitiated) {
            guard let targetList = store.defaultCalendarForNewReminders() ?? store.calendars(for: .reminder).first else {
                print("Failed to create reminder: no reminder list available")
                return false
            }

            let reminder = EKReminder(eventStore: store)
            reminder.title = title
            reminder.dueDateComponents = dueDateComponents
            reminder.calendar = targetList

            do {
                try store.save(reminder, commit: true)
                return true
            } catch {
                print("Failed to create reminder: \(error)")
                return false
            }
        }.value
    }

    /// 新建一条日程（`EKEvent`，docs/36 §做法 机制三）。
    ///
    /// **目标日历**（逐级兜底，全无 → `false`）：
    /// ① 给定 `calendarID` 且该日历 `allowsContentModifications` → 用它；
    /// ② `store.defaultCalendarForNewEvents`；
    /// ③ 第一个 `allowsContentModifications` 的 `.event` 日历。
    ///
    /// 写档口径同上：`nonisolated` + `Task.detached(priority: .userInitiated)`，`commit: true`；
    /// `span: .thisEvent`（本批不建重复规则 / 不做编辑，跨度参数只是 `save` 的必填项）。
    nonisolated func createEvent(title: String, start: Date, end: Date, isAllDay: Bool, calendarID: String?) async -> Bool {
        let store = self.store
        return await Task.detached(priority: .userInitiated) {
            let writableCalendars = store.calendars(for: .event).filter(\.allowsContentModifications)

            let targetCalendar: EKCalendar? = {
                if let calendarID,
                   let requested = writableCalendars.first(where: { $0.calendarIdentifier == calendarID }) {
                    return requested
                }
                if let defaultCalendar = store.defaultCalendarForNewEvents {
                    return defaultCalendar
                }
                return writableCalendars.first
            }()

            guard let targetCalendar else {
                print("Failed to create event: no writable event calendar available")
                return false
            }

            let event = EKEvent(eventStore: store)
            event.title = title
            event.startDate = start
            event.endDate = end
            event.isAllDay = isAllDay
            event.calendar = targetCalendar

            do {
                try store.save(event, span: .thisEvent, commit: true)
                return true
            } catch {
                print("Failed to create event: \(error)")
                return false
            }
        }.value
    }

    /// **可写**的日程日历（`allowsContentModifications` 过滤，`CalendarModel(from:)` 复用）——新增表单的
    /// 「目标日历」下拉只列它，避免用户选中一个订阅 / 只读日历经到保存失败。
    ///
    /// 同步读（主线程调用；与既有 `reloadCalendarAndReminderLists` 内部的同步读同口径）：
    /// 一次 `calendars(for:)` 的内存过滤，不做 I/O。
    func writableEventCalendars() -> [CalendarModel] {
        store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map { CalendarModel(from: $0) }
    }

    /// 新日程的默认目标日历 id（`defaultCalendarForNewEvents`）——新增表单的初始选中项。
    /// 同步读，理由同上；为 nil（没有默认日历的仓库）时调用方再由 `writableEventCalendars()` 兜底。
    func defaultEventCalendarID() -> String? {
        store.defaultCalendarForNewEvents?.calendarIdentifier
    }
}

// MARK: - Model Extensions

extension CalendarModel {
    init(from calendar: EKCalendar) {
        self.init(
            accountName: calendar.accountTitle,
            id: calendar.calendarIdentifier,
            title: calendar.title,
            color: calendar.color,
            isSubscribed: calendar.isSubscribed || calendar.isDelegate,
            isReminder: calendar.allowedEntityTypes.contains(.reminder)
        )
    }
}

extension EventModel {
    init?(from event: EKEvent) {
        guard let calendar = event.calendar else { return nil }
        
        self.init(
            id: event.calendarItemIdentifier,
            start: event.startDate,
            end: event.endDate,
            title: event.title ?? "",
            location: event.location,
            notes: event.notes,
            url: event.url,
            isAllDay: event.shouldBeAllDay,
            type: .init(from: event),
            calendar: .init(from: calendar),
            participants: .init(from: event),
            timeZone: calendar.isSubscribed || calendar.isDelegate ? nil : event.timeZone,
            hasRecurrenceRules: event.hasRecurrenceRules || event.isDetached,
            priority: nil,
            conferenceURL: event.extractConferenceURL()
        )
    }
    
    init?(from reminder: EKReminder) {
        guard let calendar = reminder.calendar,
              let dueDateComponents = reminder.dueDateComponents,
              let date = Calendar.current.date(from: dueDateComponents)
        else { return nil }
        
        self.init(
            id: reminder.calendarItemIdentifier,
            start: date,
            end: Calendar.current.endOfDay(for: date),
            title: reminder.title ?? "",
            location: reminder.location,
            notes: reminder.notes,
            url: reminder.url,
            isAllDay: dueDateComponents.hour == nil,
            type: .reminder(completed: reminder.isCompleted),
            calendar: .init(from: calendar),
            participants: [],
            timeZone: calendar.isSubscribed || calendar.isDelegate ? nil : reminder.timeZone,
            hasRecurrenceRules: reminder.hasRecurrenceRules,
            priority: .init(from: reminder.priority),
            conferenceURL: nil
        )
    }
}

extension EventType {
    init(from event: EKEvent) {
        self = event.birthdayContactIdentifier != nil ? .birthday : .event(.init(from: event.currentUser?.participantStatus))
    }
}

extension AttendanceStatus {
    init(from status: EKParticipantStatus?) {
        switch status {
        case .accepted:
            self = .accepted
        case .tentative:
            self = .maybe
        case .declined:
            self = .declined
        case .pending:
            self = .pending
        default:
            self = .unknown
        }
    }
}

extension Array where Element == Participant {
    init(from event: EKEvent) {
        var participants = event.attendees ?? []
        if let organizer = event.organizer, !participants.contains(where: { $0.url == organizer.url }) {
            participants.append(organizer)
        }
        self.init(
            participants.map { .init(from: $0, isOrganizer: $0.url == event.organizer?.url) }
        )
    }
}

extension Participant {
    init(from participant: EKParticipant, isOrganizer: Bool) {
        self.init(
            name: participant.name ?? participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: ""),
            status: .init(from: participant.participantStatus),
            isOrganizer: isOrganizer,
            isCurrentUser: participant.isCurrentUser
        )
    }
}

extension Priority {
    init?(from p: Int) {
        switch p {
        case 1...4:
            self = .high
        case 5:
            self = .medium
        case 6...9:
            self = .low
        default:
            return nil
        }
    }
}

// MARK: - Helper Extensions

extension EKCalendar {
    var accountTitle: String {
        switch source.sourceType {
        case .local, .subscribed, .birthdays:
            return String(localized: "Other")
        default:
            return source.title
        }
    }
    
    var isDelegate: Bool {
        return source.isDelegate
    }
}

private extension EKEvent {
    var currentUser: EKParticipant? {
        attendees?.first(where: \.isCurrentUser)
    }
    
    var shouldBeAllDay: Bool {
        guard !isAllDay else { return true }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: startDate)
        let endOfDay = calendar.dateInterval(of: .day, for: endDate)?.end
        return startDate == startOfDay && endDate == endOfDay
    }
    
    /// Extract conference call URL from various sources
    func extractConferenceURL() -> URL? {
        // First try the URL field if it's a conference URL
        if let eventURL = url, isConferenceURL(eventURL) {
            return eventURL
        }
        
        // Then try to extract from location field
        if let location = location, let conferenceURL = extractURLFromText(location) {
            return conferenceURL
        }
        
        // Finally try to extract from notes
        if let notes = notes, let conferenceURL = extractURLFromText(notes) {
            return conferenceURL
        }
        
        return nil
    }
    
    /// Check if a URL is likely a conference URL
    private func isConferenceURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let conferenceHosts = [
            "zoom.us",
            "teams.microsoft.com",
            "meet.google.com",
            "webex.com",
            "gotomeeting.com",
            "bluejeans.com",
            "whereby.com",
            "meet.jit.si",
            "discord.gg",
            "discord.com",
            "facetime.apple.com"
        ]
        
        return conferenceHosts.contains { host.contains($0) }
    }
    
    /// Extract first valid conference URL from text
    private func extractURLFromText(_ text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        
        for match in matches ?? [] {
            if let url = match.url, isConferenceURL(url) {
                return url
            }
        }
        
        return nil
    }
}

private extension Calendar {
    func endOfDay(for date: Date) -> Date {
        dateInterval(of: .day, for: date)?.end ?? date
    }
}
