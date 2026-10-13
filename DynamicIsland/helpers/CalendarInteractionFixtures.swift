// Modified for Gourd (2026-10-11)
// Copyright (C) 2026 Gourd Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import EventKit
import Foundation

/// 系统入口在夹具模式只记 ID；调用 calendarAppURL 前短路，避免启动第三方日历。
@MainActor
enum CalendarInteractionFixtures {
    static var isEnabled: Bool {
        #if DEBUG
        return AppRuntimeEnvironment.isUITesting || AppRuntimeEnvironment.isRunningTests
        #else
        return false
        #endif
    }

    static func openSystemEvent(_ event: EventModel) {
        #if DEBUG
        if isEnabled { backend.recordSystemOpen(event.id); return }
        #endif
        if let url = event.calendarAppURL() { NSWorkspace.shared.open(url) }
    }

    #if DEBUG
    static let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
    static let backend: CalendarInteractionMemoryService = {
        let count = CommandLine.arguments.first(where: { $0.hasPrefix("--calendar-fixture-count=") })
            .flatMap { Int($0.split(separator: "=").last ?? "") } ?? 30
        let service = makeBackend(count: count, on: now)
        if CommandLine.arguments.contains("--calendar-write-failure") { service.writeFailure = .readOnlyCalendar }
        if CommandLine.arguments.contains("--calendar-write-failure-once") { service.nextWriteFailure = .readOnlyCalendar }
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--calendar-write-delay-ms=") }),
           let milliseconds = UInt64(arg.split(separator: "=").last ?? "") {
            service.writeDelayNanoseconds = min(milliseconds, 60_000) * 1_000_000
        }
        return service
    }()

    static func makeBackend(count: Int = 30, on date: Date, calendar: Calendar = .current) -> CalendarInteractionMemoryService {
        let sources = [
            CalendarModel(accountName: "Fixture", id: "fixture-events", title: "Fixture Calendar", color: .systemBlue, isSubscribed: false, isReminder: false),
            CalendarModel(accountName: "Fixture", id: "fixture-readonly", title: "Fixture Read Only", color: .systemGray, isSubscribed: true, isReminder: false, allowsContentModifications: false),
            CalendarModel(accountName: "Fixture", id: "fixture-reminders", title: "Fixture Reminders", color: .systemOrange, isSubscribed: false, isReminder: true)
        ]
        let day = calendar.startOfDay(for: date)
        let records = (1...max(1, count)).map { index -> EventModel in
            let isEvent = index % 3 == 1
            let id = String(format: "fixture-%@-%02d", isEvent ? "event" : "reminder", index)
            let start = calendar.date(bySettingHour: 8 + (index / 3) % 12, minute: 0, second: 0, of: day) ?? day
            let allDay = isEvent && index == 7
            let end = calendar.date(byAdding: allDay ? .day : .hour, value: 1, to: allDay ? day : start) ?? start
            let notes = isEvent ? (1...45).map { "\($0). Long fixture notes for \(id). 日程备注完整滚动验收。" }.joined(separator: "\n") + "\nEND OF NOTES \(id)" : "Fixture reminder \(index)"
            let type: EventType = isEvent ? (index == 16 ? .birthday : .event(.unknown)) : .reminder(completed: index == 6)
            return EventModel(
                id: id, start: allDay ? day : start, end: end,
                title: "\(String(format: "%02d", index)) · \(isEvent ? "日程 Event" : "待办 Reminder") · Fixture item \(index)",
                location: isEvent ? "Fixture meeting room with a long location description" : nil,
                notes: notes, url: nil, isAllDay: allDay, type: type,
                calendar: isEvent ? (index == 4 ? sources[1] : sources[0]) : sources[2],
                participants: index == 13 ? [Participant(name: "Fixture attendee", status: .accepted, isOrganizer: false, isCurrentUser: false)] : [],
                timeZone: calendar.timeZone, hasRecurrenceRules: index == 7 || index == 3,
                priority: nil, conferenceURL: nil, isDetached: index == 10
            )
        }
        return CalendarInteractionMemoryService(records: records, calendars: sources, calendar: calendar)
    }
    #endif
}

#if DEBUG
/// 完整内存后端；锁保护同一记录字典，无 EKEventStore / TCC 初始化。
final class CalendarInteractionMemoryService: CalendarServiceProviding {
    private let lock = NSLock()
    private var records: [String: EventModel]
    private let sources: [CalendarModel]
    private let calendar: Calendar
    private var completionDates: [String: Date]
    private var serial = 0
    private var failure: CalendarMutationError?
    private var oneTimeFailure: CalendarMutationError?
    private var delay: UInt64 = 0
    private var openedIDs: [String] = []
    private var attempts = 0
    private var eventAuthorization: EKAuthorizationStatus
    private var reminderAuthorization: EKAuthorizationStatus

    init(
        records: [EventModel], calendars: [CalendarModel], calendar: Calendar = .current,
        eventAuthorization: EKAuthorizationStatus = .fullAccess,
        reminderAuthorization: EKAuthorizationStatus = .fullAccess
    ) {
        self.records = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        completionDates = Dictionary(records.compactMap { event in
            guard case .reminder(completed: true) = event.type else { return nil }
            return (event.id, event.start == .distantFuture ? Date() : event.start)
        }, uniquingKeysWith: { _, last in last })
        sources = calendars
        self.calendar = calendar
        self.eventAuthorization = eventAuthorization
        self.reminderAuthorization = reminderAuthorization
    }

    private func locked<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }

    var writeFailure: CalendarMutationError? {
        get { locked { failure } }
        set { locked { failure = newValue } }
    }
    var writeDelayNanoseconds: UInt64 {
        get { locked { delay } }
        set { locked { delay = newValue } }
    }
    var nextWriteFailure: CalendarMutationError? {
        get { locked { oneTimeFailure } }
        set { locked { oneTimeFailure = newValue } }
    }
    var writeAttempts: Int { locked { attempts } }
    var systemOpenedIDs: [String] { locked { openedIDs } }
    func recordSystemOpen(_ id: String) { locked { openedIDs.append(id) } }
    func allRecords() -> [EventModel] { locked { records.values.sorted { $0.id < $1.id } } }
    func completionDate(forReminderID id: String) -> Date? { locked { completionDates[id] } }
    func setAuthorization(_ status: EKAuthorizationStatus, for type: EKEntityType) {
        locked { if type == .event { eventAuthorization = status } else { reminderAuthorization = status } }
    }

    func authorizationStatus(for type: EKEntityType) -> EKAuthorizationStatus {
        locked { type == .event ? eventAuthorization : reminderAuthorization }
    }
    func requestAccess() async -> Bool { authorizationStatus(for: .event) == .fullAccess || authorizationStatus(for: .reminder) == .fullAccess }
    func requestAccess(to type: EKEntityType) async -> Bool { authorizationStatus(for: type) == .fullAccess }
    func calendars() async -> [CalendarModel] {
        locked { sources.filter { CalendarAccessPolicy.canRead(status: $0.isReminder ? reminderAuthorization : eventAuthorization) } }
    }
    func events(from start: Date, to end: Date, calendars ids: [String]) async -> [EventModel] {
        locked {
            records.values.filter { event in
                CalendarAccessPolicy.canRead(status: event.type.isReminder ? reminderAuthorization : eventAuthorization)
                    && (ids.isEmpty || ids.contains(event.calendar.id))
                    && (event.type.isReminder ? event.start >= start && event.start < end : event.start < end && event.end > start)
            }.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        }
    }
    func event(withID id: String) -> EventModel? {
        locked {
            guard let event = records[id], CalendarAccessPolicy.canRead(status: event.type.isReminder ? reminderAuthorization : eventAuthorization) else { return nil }
            return event
        }
    }
    func writableEventCalendars() -> [CalendarModel] {
        locked { sources.filter { !$0.isReminder && $0.allowsContentModifications && CalendarAccessPolicy.canCreate(status: eventAuthorization, for: .event) } }
    }
    func writableReminderCalendars() -> [CalendarModel] {
        locked { sources.filter { $0.isReminder && $0.allowsContentModifications && CalendarAccessPolicy.canRead(status: reminderAuthorization) } }
    }
    func defaultEventCalendarID() -> String? { writableEventCalendars().first?.id }
    var preferredReminderCalendarID: String? { writableReminderCalendars().first?.id }

    private func performWrite<T>(type: EKEntityType, creating: Bool = false, operation: () throws -> T) throws -> T {
        try locked {
            attempts += 1
            return try CalendarAccessPolicy.performWrite(
                status: type == .event ? eventAuthorization : reminderAuthorization, type: type, creating: creating
            ) {
                if let failure { throw failure }
                if let oneTimeFailure {
                    self.oneTimeFailure = nil
                    throw oneTimeFailure
                }
                return try operation()
            }
        }
    }
    private func waitForWrite() async throws {
        let delay = writeDelayNanoseconds
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
    }
    private func target(_ id: String?, originalID: String? = nil, reminder: Bool) throws -> CalendarModel {
        let id = try CalendarMutationPolicy.targetCalendarID(
            requestedID: id, originalID: originalID,
            defaultID: reminder ? "fixture-reminders" : "fixture-events", calendars: sources, isReminder: reminder
        )
        guard let source = sources.first(where: { $0.id == id }) else { throw CalendarMutationError.invalidCalendar }
        return source
    }
    private func nextID() -> String { serial += 1; return "fixture-created-\(serial)" }

    func saveEvent(input: CalendarEventInput, eventID: String?) async throws -> EventModel {
        try await waitForWrite()
        return try performWrite(type: .event, creating: eventID == nil) {
            let input = try input.validated(calendar: calendar)
            let existing: EventModel?
            if let eventID {
                guard let event = records[eventID] else { throw CalendarMutationError.recordNotFound }
                try CalendarMutationPolicy.performEventWrite(event: event, write: {})
                existing = event
            } else { existing = nil }
            let calendar = try target(input.calendarID, originalID: existing?.calendar.id, reminder: false)
            let metadata = try input.resolvedMetadata(
                existingURL: existing?.url, existingTimeZone: eventID == nil ? self.calendar.timeZone : existing?.timeZone
            )
            let saved = EventModel(
                id: existing?.id ?? nextID(), start: input.start, end: input.end, title: input.title,
                location: input.location, notes: input.notes, url: metadata.url, isAllDay: input.isAllDay,
                type: .event(.unknown), calendar: calendar, participants: [], timeZone: metadata.timeZone,
                hasRecurrenceRules: false, priority: nil, conferenceURL: nil
            )
            return try CalendarMutationPolicy.performEventWrite(event: saved) { records[saved.id] = saved; return saved }
        }
    }
    func createReminderRecord(title: String, due: Date, listID: String?) async throws -> EventModel {
        try await createReminderRecord(input: CalendarReminderInput(title: title, due: due, isAllDay: true, listID: listID))
    }

    func createTodoReminder(title: String, due: Date?, listID: String? = nil) async throws -> EventModel {
        try await createReminderRecord(input: CalendarReminderInput(title: title, due: due, isAllDay: true, listID: listID))
    }

    func createReminderRecord(input: CalendarReminderInput) async throws -> EventModel {
        try await waitForWrite()
        return try performWrite(type: .reminder, creating: true) {
            let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { throw CalendarMutationError.invalidTitle }
            let source = try target(input.listID, reminder: true)
            let components = try input.dueDateComponents(calendar: calendar)
            let dateCalendar = components.map { CalendarRecordDates.calendar(for: $0, fallback: calendar) } ?? calendar
            let start = components.flatMap { CalendarRecordDates.absoluteDate(from: $0, fallback: calendar) } ?? .distantFuture
            let saved = EventModel(
                id: nextID(), start: start, end: components == nil ? .distantFuture : CalendarRecordDates.endOfDay(for: start, calendar: dateCalendar),
                title: title, location: nil, notes: input.notes, url: input.url,
                isAllDay: components?.hour == nil, type: .reminder(completed: false),
                calendar: source, participants: [], timeZone: components?.timeZone ?? components?.calendar?.timeZone,
                hasRecurrenceRules: false, priority: nil, conferenceURL: nil
            )
            return try CalendarMutationPolicy.performReminderWrite(event: saved) { records[saved.id] = saved; return saved }
        }
    }
    func deleteEvent(id: String) async throws {
        try await waitForWrite()
        try performWrite(type: .event) {
            guard let event = records[id] else { throw CalendarMutationError.recordNotFound }
            try CalendarMutationPolicy.performEventWrite(event: event) { records.removeValue(forKey: id); return () }
        }
    }
    func deleteReminder(id: String) async throws {
        try await waitForWrite()
        try performWrite(type: .reminder) {
            guard let event = records[id] else { throw CalendarMutationError.recordNotFound }
            try CalendarMutationPolicy.performReminderWrite(event: event) {
                records.removeValue(forKey: id)
                completionDates.removeValue(forKey: id)
            }
        }
    }

    func completeReminder(id: String, completed: Bool) async throws -> EventModel {
        try await waitForWrite()
        return try performWrite(type: .reminder) {
            guard let event = records[id] else { throw CalendarMutationError.recordNotFound }
            return try CalendarMutationPolicy.performReminderWrite(event: event) {
                let saved = copyReminder(event, completed: completed, priority: event.priority)
                records[id] = saved
                completionDates[id] = completed ? (completionDates[id] ?? Date()) : nil
                return saved
            }
        }
    }
    func setReminderCompleted(reminderID: String, completed: Bool) async {
        _ = try? await completeReminder(id: reminderID, completed: completed)
    }
    func setReminderPriority(reminderID: String, priority: Int) async -> Bool {
        do {
            try await waitForWrite()
            try performWrite(type: .reminder) {
                guard let event = records[reminderID] else { throw CalendarMutationError.recordNotFound }
                try CalendarMutationPolicy.performReminderWrite(event: event) {
                    let completed: Bool
                    if case .reminder(let value) = event.type { completed = value } else { completed = false }
                    records[reminderID] = copyReminder(event, completed: completed, priority: Priority(from: priority))
                }
            }
            return true
        } catch { return false }
    }
    private func copyReminder(_ event: EventModel, completed: Bool, priority: Priority?) -> EventModel {
        EventModel(
            id: event.id, start: event.start, end: event.end, title: event.title, location: event.location,
            notes: event.notes, url: event.url, isAllDay: event.isAllDay, type: .reminder(completed: completed),
            calendar: event.calendar, participants: event.participants, timeZone: event.timeZone,
            hasRecurrenceRules: event.hasRecurrenceRules, priority: priority, conferenceURL: event.conferenceURL, isDetached: event.isDetached
        )
    }
}
#endif
