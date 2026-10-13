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
    func saveEvent(input: CalendarEventInput, eventID: String?) async throws -> EventModel
    func createReminderRecord(input: CalendarReminderInput) async throws -> EventModel
    func createReminderRecord(title: String, due: Date, listID: String?) async throws -> EventModel
    func deleteEvent(id: String) async throws
    func completeReminder(id: String, completed: Bool) async throws -> EventModel
    func event(withID id: String) -> EventModel?
    func writableEventCalendars() -> [CalendarModel]
    func writableReminderCalendars() -> [CalendarModel]
    func defaultEventCalendarID() -> String?
    var preferredReminderCalendarID: String? { get }
    func authorizationStatus(for type: EKEntityType) -> EKAuthorizationStatus
    func setReminderPriority(reminderID: String, priority: Int) async -> Bool
}

extension CalendarServiceProviding {
    func createReminderRecord(title: String, due: Date, listID: String?) async throws -> EventModel {
        try await createReminderRecord(input: CalendarReminderInput(title: title, due: due, isAllDay: true, listID: listID))
    }
}

/// 仅写授权支持新建日程及目标日历查询；既有记录的详情、改删仍需完整读取权限。
enum CalendarAccessPolicy {
    static func canRead(status: EKAuthorizationStatus) -> Bool { status == .fullAccess }

    static func canCreate(status: EKAuthorizationStatus, for type: EKEntityType) -> Bool {
        canRead(status: status) || (type == .event && status == .writeOnly)
    }

    static func performWrite<T>(
        status: EKAuthorizationStatus, type: EKEntityType, creating: Bool, write: () throws -> T
    ) throws -> T {
        guard creating ? canCreate(status: status, for: type) : canRead(status: status) else {
            throw CalendarMutationError.accessDenied
        }
        return try write()
    }
}

class CalendarService: CalendarServiceProviding {
    private let store = EKEventStore()
    /// 一个 store 的全部写入（含兼容入口）顺序执行；队列内重读和复核后才 commit。
    private let writeQueue = DispatchQueue(label: "com.cmeng.gourd.calendar.writes", qos: .userInitiated)

    func authorizationStatus(for type: EKEntityType) -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: type)
    }

    private func performWrite<T>(
        to type: EKEntityType, creating: Bool = false, _ operation: @escaping () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            writeQueue.async {
                do {
                    let result = try CalendarAccessPolicy.performWrite(
                        status: self.authorizationStatus(for: type), type: type, creating: creating, write: operation
                    )
                    continuation.resume(returning: result)
                }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func targetCalendar(requestedID: String?, originalID: String? = nil, type: EKEntityType) throws -> EKCalendar {
        let calendars = store.calendars(for: type)
        // 也检查另一种类型，使错误类型与失效 ID 能明确区分，绝不改投其它源。
        let all = calendars + store.calendars(for: type == .event ? .reminder : .event)
        let defaultID = type == .event
            ? store.defaultCalendarForNewEvents?.calendarIdentifier
            : store.defaultCalendarForNewReminders()?.calendarIdentifier
        let id = try CalendarMutationPolicy.targetCalendarID(
            requestedID: requestedID, originalID: originalID, defaultID: defaultID,
            calendars: all.map { CalendarModel(from: $0) }, isReminder: type == .reminder
        )
        guard let calendar = calendars.first(where: { $0.calendarIdentifier == id }),
              calendar.allowedEntityTypes.contains(type == .event ? .event : .reminder) else {
            throw CalendarMutationError.wrongRecordType
        }
        return calendar
    }

    private func savedModel(from item: EKCalendarItem) throws -> EventModel {
        guard !item.calendarItemIdentifier.isEmpty else { throw CalendarMutationError.missingRecordIdentifier }
        let model: EventModel?
        if let event = item as? EKEvent { model = EventModel(from: event) }
        else if let reminder = item as? EKReminder { model = EventModel(from: reminder) }
        else { model = nil }
        guard let model else { throw CalendarMutationError.missingRecordIdentifier }
        return model
    }

    
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
        CalendarAccessPolicy.canRead(status: authorizationStatus(for: entityType))
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
            if !eventCalendars.isEmpty {
                let predicate = store.predicateForEvents(withStart: start, end: end, calendars: eventCalendars)
                let ekEvents = store.events(matching: predicate)
                events.append(contentsOf: ekEvents.compactMap { EventModel(from: $0) })
            }
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
                    guard let components = reminder.dueDateComponents,
                          let dueDate = CalendarRecordDates.absoluteDate(from: components),
                          dueDate >= start,
                          dueDate < end else {
                        return nil
                    }
                    return EventModel(from: reminder)
                }

                continuation.resume(returning: filtered)
            }
        }
    }

    func event(withID id: String) -> EventModel? {
        guard hasAccess(to: .event) || hasAccess(to: .reminder) else { return nil }
        guard let item = store.calendarItem(withIdentifier: id) else { return nil }
        if let event = item as? EKEvent, hasAccess(to: .event) { return EventModel(from: event) }
        if let reminder = item as? EKReminder, hasAccess(to: .reminder) { return EventModel(from: reminder) }
        return nil
    }

    func saveEvent(input: CalendarEventInput, eventID: String? = nil) async throws -> EventModel {
        try await performWrite(to: .event, creating: eventID == nil) {
            let input = try input.validated()
            let event: EKEvent
            if let eventID {
                guard let item = self.store.calendarItem(withIdentifier: eventID) else {
                    throw CalendarMutationError.recordNotFound
                }
                guard let existing = item as? EKEvent else { throw CalendarMutationError.wrongRecordType }
                event = existing
                let original = try self.savedModel(from: event)
                // 复核原记录发生在更换目标日历前，不能用新日历绕过只读/复杂记录限制。
                try CalendarMutationPolicy.performEventWrite(event: original, write: {})
            } else {
                event = EKEvent(eventStore: self.store)
            }
            let calendar = try self.targetCalendar(
                requestedID: input.calendarID, originalID: eventID == nil ? nil : event.calendar?.calendarIdentifier,
                type: .event
            )
            return try CalendarMutationPolicy.performWithRollback(write: {
                event.calendar = calendar
                event.title = input.title
                event.startDate = input.start
                event.endDate = input.end
                event.isAllDay = input.isAllDay
                event.location = input.location
                event.notes = input.notes
                let metadata = try input.resolvedMetadata(existingURL: event.url, existingTimeZone: event.timeZone)
                event.url = metadata.url
                event.timeZone = metadata.timeZone
                return try CalendarMutationPolicy.performEventWrite(event: try self.savedModelForWrite(from: event)) {
                    try self.store.save(event, span: .thisEvent, commit: true)
                    return try self.savedModel(from: event)
                }
            }, rollback: { event.rollback() })
        }
    }

    /// 新记录在首次 save 前可以没有 ID，限制仍从实际 EKEvent/EKReminder 转出的模型复核。
    private func savedModelForWrite(from event: EKEvent) throws -> EventModel {
        guard let model = EventModel(from: event) else { throw CalendarMutationError.wrongRecordType }
        return model
    }

    func deleteEvent(id: String) async throws {
        try await performWrite(to: .event) {
            guard let item = self.store.calendarItem(withIdentifier: id) else {
                throw CalendarMutationError.recordNotFound
            }
            guard let event = item as? EKEvent else { throw CalendarMutationError.wrongRecordType }
            try CalendarMutationPolicy.performEventWrite(event: try self.savedModel(from: event)) {
                try self.store.remove(event, span: .thisEvent, commit: true)
            }
        }
    }

    func completeReminder(id: String, completed: Bool) async throws -> EventModel {
        try await performWrite(to: .reminder) {
            guard let item = self.store.calendarItem(withIdentifier: id) else {
                throw CalendarMutationError.recordNotFound
            }
            guard let reminder = item as? EKReminder else { throw CalendarMutationError.wrongRecordType }
            return try CalendarMutationPolicy.performReminderWrite(event: try self.savedModel(from: reminder)) {
                return try CalendarMutationPolicy.performWithRollback(write: {
                    reminder.isCompleted = completed
                    try self.store.save(reminder, commit: true)
                    return try self.savedModel(from: reminder)
                }, rollback: { reminder.rollback() })
            }
        }
    }

    func createReminderRecord(title: String, due: Date, listID: String? = nil) async throws -> EventModel {
        try await createReminderRecord(input: CalendarReminderInput(title: title, due: due, isAllDay: true, listID: listID))
    }

    func createReminderRecord(input: CalendarReminderInput) async throws -> EventModel {
        try await createReminderRecord(
            title: input.title, dueDateComponents: { try input.dueDateComponents() }, listID: input.listID,
            notes: input.notes, url: input.url
        )
    }

    private func createReminderRecord(
        title: String, dueDateComponents: @escaping () throws -> DateComponents?, listID: String?, notes: String? = nil, url: URL? = nil
    ) async throws -> EventModel {
        try await performWrite(to: .reminder, creating: true) {
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { throw CalendarMutationError.invalidTitle }
            let calendar = try self.targetCalendar(requestedID: listID, type: .reminder)
            let reminder = EKReminder(eventStore: self.store)
            reminder.title = title
            reminder.dueDateComponents = try dueDateComponents()
            reminder.notes = notes
            reminder.url = url
            reminder.calendar = calendar
            guard let model = EventModel(from: reminder) else { throw CalendarMutationError.wrongRecordType }
            return try CalendarMutationPolicy.performReminderWrite(event: model) {
                try self.store.save(reminder, commit: true)
                return try self.savedModel(from: reminder)
            }
        }
    }

    // MARK: - 兼容写入口（相同守卫与串行队列）

    func setReminderCompleted(reminderID: String, completed: Bool) async {
        do { _ = try await completeReminder(id: reminderID, completed: completed) }
        catch { print("Failed to update reminder completion: \(error)") }
    }

    func setReminderPriority(reminderID: String, priority: Int) async -> Bool {
        do {
            try await performWrite(to: .reminder) {
                guard let item = self.store.calendarItem(withIdentifier: reminderID) else {
                    throw CalendarMutationError.recordNotFound
                }
                guard let reminder = item as? EKReminder else { throw CalendarMutationError.wrongRecordType }
                try CalendarMutationPolicy.performReminderWrite(event: try self.savedModel(from: reminder)) {
                    try CalendarMutationPolicy.performWithRollback(write: {
                        reminder.priority = priority
                        try self.store.save(reminder, commit: true)
                    }, rollback: { reminder.rollback() })
                }
            }
            return true
        } catch {
            print("Failed to update reminder priority: \(error)")
            return false
        }
    }

    func createReminder(title: String, dueDateComponents: DateComponents?) async -> Bool {
        do {
            _ = try await createReminderRecord(title: title, dueDateComponents: { dueDateComponents }, listID: nil)
            return true
        } catch {
            print("Failed to create reminder: \(error)")
            return false
        }
    }

    func createEvent(title: String, start: Date, end: Date, isAllDay: Bool, calendarID: String?) async -> Bool {
        do {
            _ = try await saveEvent(input: CalendarEventInput(
                title: title, start: start, end: end, isAllDay: isAllDay, calendarID: calendarID
            ))
            return true
        } catch {
            print("Failed to create event: \(error)")
            return false
        }
    }

    func writableEventCalendars() -> [CalendarModel] {
        guard CalendarAccessPolicy.canCreate(status: authorizationStatus(for: .event), for: .event) else { return [] }
        return store.calendars(for: .event).filter(\.allowsContentModifications).map { CalendarModel(from: $0) }
    }

    func writableReminderCalendars() -> [CalendarModel] {
        guard hasAccess(to: .reminder) else { return [] }
        return store.calendars(for: .reminder).filter(\.allowsContentModifications).map { CalendarModel(from: $0) }
    }

    func defaultEventCalendarID() -> String? {
        guard CalendarAccessPolicy.canCreate(status: authorizationStatus(for: .event), for: .event) else { return nil }
        return store.defaultCalendarForNewEvents?.calendarIdentifier
    }

    var preferredReminderCalendarID: String? {
        let writable = writableReminderCalendars()
        if let id = store.defaultCalendarForNewReminders()?.calendarIdentifier,
           writable.contains(where: { $0.id == id }) { return id }
        return writable.first?.id
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
            isReminder: calendar.allowedEntityTypes.contains(.reminder),
            allowsContentModifications: calendar.allowsContentModifications
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
            conferenceURL: event.extractConferenceURL(),
            isDetached: event.isDetached
        )
    }
    
    init?(from reminder: EKReminder) {
        guard let calendar = reminder.calendar else { return nil }
        let dueDateComponents = reminder.dueDateComponents
        // 兼容无日期提醒的完成/详情入口；查询仍只收有到期日的提醒。
        let date = dueDateComponents.flatMap { CalendarRecordDates.absoluteDate(from: $0) } ?? .distantFuture
        let dateCalendar = dueDateComponents.map { CalendarRecordDates.calendar(for: $0) } ?? .current
        
        self.init(
            id: reminder.calendarItemIdentifier,
            start: date,
            end: CalendarRecordDates.endOfDay(for: date, calendar: dateCalendar),
            title: reminder.title ?? "",
            location: reminder.location,
            notes: reminder.notes,
            url: reminder.url,
            isAllDay: dueDateComponents?.hour == nil,
            type: .reminder(completed: reminder.isCompleted),
            calendar: .init(from: calendar),
            participants: [],
            timeZone: calendar.isSubscribed || calendar.isDelegate ? nil : (dueDateComponents?.timeZone ?? dueDateComponents?.calendar?.timeZone ?? reminder.timeZone),
            hasRecurrenceRules: reminder.hasRecurrenceRules,
            priority: .init(from: reminder.priority),
            conferenceURL: nil
        )
    }
}

extension EventType {
    init(from event: EKEvent) {
        self = event.birthdayContactIdentifier != nil || event.calendar?.type == .birthday ? .birthday : .event(.init(from: event.currentUser?.participantStatus))
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
    
}

extension EKEvent {
    /// Multiple invitations remain unresolved for the selection UI; never choose the first link.
    func extractConferenceURL() -> URL? {
        let source = [url?.absoluteString, location, notes].compactMap { $0 }.joined(separator: "\n")
        return MeetingLinkResolver().uniqueOpenTarget(text: source)?.sourceURL
    }
}
