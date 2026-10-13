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
import Defaults
import AppKit

struct EventModel: Equatable, Identifiable {
    let id: String
    let start: Date
    let end: Date
    let title: String
    let location: String?
    let notes: String?
    let url: URL?
    let isAllDay: Bool
    let type: EventType
    let calendar: CalendarModel
    let participants: [Participant]
    let timeZone: TimeZone?
    let hasRecurrenceRules: Bool
    let priority: Priority?
    let conferenceURL: URL?
    var isDetached: Bool = false
}

/// 保存输入使用 EventKit 的全天排他结束日期；跨日定时只要求结束晚于开始。
struct CalendarEventInput: Equatable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String? = nil
    var notes: String? = nil
    var calendarID: String? = nil
    var url: URL? = nil
    var timeZoneIdentifier: String? = nil

    func validated(calendar: Calendar = .current) throws -> Self {
        let calendar = try CalendarRecordDates.calendar(timeZoneIdentifier: timeZoneIdentifier, fallback: calendar)
        var input = self
        input.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.title.isEmpty else { throw CalendarMutationError.invalidTitle }
        guard end > start else { throw CalendarMutationError.invalidDateRange }
        if isAllDay {
            guard calendar.startOfDay(for: start) == start,
                  calendar.startOfDay(for: end) == end else {
                throw CalendarMutationError.invalidAllDayRange
            }
        }
        return input
    }

    func resolvedMetadata(existingURL: URL?, existingTimeZone: TimeZone?) throws -> (url: URL?, timeZone: TimeZone?) {
        let zone = try timeZoneIdentifier.map {
            try CalendarRecordDates.calendar(timeZoneIdentifier: $0, fallback: .current).timeZone
        }
        return (url ?? existingURL, zone ?? existingTimeZone)
    }

    static func exclusiveAllDayEnd(including lastDay: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: lastDay))
    }

    static func includedAllDayEnd(exclusiveEnd: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: exclusiveEnd))
    }
}

/// Date-only and timed reminders share one write input; due is optional for existing undated callers.
struct CalendarReminderInput: Equatable {
    var title: String
    var due: Date?
    var isAllDay: Bool
    var notes: String? = nil
    var url: URL? = nil
    var listID: String? = nil
    var timeZoneIdentifier: String? = nil

    func dueDateComponents(calendar: Calendar = .current) throws -> DateComponents? {
        let calendar = try CalendarRecordDates.calendar(timeZoneIdentifier: timeZoneIdentifier, fallback: calendar)
        guard let due else { return nil }
        let fields: Set<Calendar.Component> = isAllDay ? [.year, .month, .day] : [.year, .month, .day, .hour, .minute, .second]
        var components = calendar.dateComponents(fields, from: due)
        // Legacy date-only reminders remain floating. Timed reminders carry the source zone.
        if !isAllDay || timeZoneIdentifier != nil {
            components.calendar = calendar
            components.timeZone = calendar.timeZone
        }
        if !isAllDay {
            // Calendar.date(from:) selects a DST occurrence; reject shifts but allow subsecond loss.
            guard let readback = CalendarRecordDates.absoluteDate(from: components, fallback: calendar),
                  readback.timeIntervalSince1970.rounded(.down) == due.timeIntervalSince1970.rounded(.down) else {
                throw CalendarMutationError.unrepresentableReminderTime
            }
        }
        return components
    }

    /// A legacy three-argument writer cannot represent richer input; fail before calling it.
    func legacyArguments() throws -> (title: String, due: Date, listID: String?) {
        guard isAllDay, notes == nil, url == nil, timeZoneIdentifier == nil, let due else {
            throw CalendarMutationError.unsupportedReminderInput
        }
        return (title, due, listID)
    }
}

/// Shared by EventKit and the in-memory backend, including reads of components carrying a zone.
enum CalendarRecordDates {
    static func calendar(timeZoneIdentifier: String?, fallback: Calendar) throws -> Calendar {
        guard let timeZoneIdentifier else { return fallback }
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else {
            throw CalendarMutationError.invalidTimeZone
        }
        var calendar = fallback
        calendar.timeZone = zone
        return calendar
    }

    static func calendar(for components: DateComponents, fallback: Calendar = .current) -> Calendar {
        var calendar = components.calendar ?? fallback
        if let zone = components.timeZone { calendar.timeZone = zone }
        return calendar
    }

    static func endOfDay(for date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .day, for: date)?.end ?? date
    }

    static func absoluteDate(from components: DateComponents, fallback: Calendar = .current) -> Date? {
        calendar(for: components, fallback: fallback).date(from: components)
    }
}

enum CalendarMutationError: Error, Equatable, LocalizedError {
    case accessDenied, invalidTitle, invalidDateRange, invalidAllDayRange
    case recordNotFound, wrongRecordType, invalidCalendar, noWritableCalendar
    case readOnlyCalendar, recurringEvent, detachedEvent, meetingEvent, birthdayEvent
    case missingRecordIdentifier, invalidTimeZone, unsupportedReminderInput, unrepresentableReminderTime

    var errorDescription: String? {
        switch self {
        case .accessDenied: return String(localized: "Calendar access is required.")
        case .invalidTitle: return String(localized: "Enter a title.")
        case .invalidDateRange: return String(localized: "End must be after start.")
        case .invalidAllDayRange: return String(localized: "All-day dates must start at midnight.")
        case .recordNotFound: return String(localized: "This item is no longer available.")
        case .wrongRecordType: return String(localized: "This item has an unsupported type.")
        case .invalidCalendar: return String(localized: "The selected calendar is no longer available.")
        case .noWritableCalendar: return String(localized: "No writable calendar is available.")
        case .readOnlyCalendar: return String(localized: "This calendar is read-only.")
        case .recurringEvent: return String(localized: "Open recurring items in the system app.")
        case .detachedEvent: return String(localized: "Open detached events in the system app.")
        case .meetingEvent: return String(localized: "Open meeting invitations in the system app.")
        case .birthdayEvent: return String(localized: "Open birthdays in the system app.")
        case .missingRecordIdentifier: return String(localized: "The saved item could not be read.")
        case .invalidTimeZone: return String(localized: "The time zone is invalid.")
        case .unsupportedReminderInput: return String(localized: "This reminder writer cannot save time or metadata.")
        case .unrepresentableReminderTime: return String(localized: "This due time cannot be preserved in its time zone. Choose another time or use all-day.")
        }
    }
}

/// UI 只展示许可；服务从同一 store 重读记录后，也必须经过这些守卫才调用写入闭包。
enum CalendarMutationPolicy {
    static func performWithRollback<T>(write: () throws -> T, rollback: () -> Void) throws -> T {
        do { return try write() }
        catch {
            rollback()
            throw error
        }
    }

    static func performEventWrite<T>(event: EventModel, write: () throws -> T) throws -> T {
        if let restriction = event.modificationRestriction { throw restriction }
        return try write()
    }

    static func performReminderWrite<T>(event: EventModel, write: () throws -> T) throws -> T {
        guard event.type.isReminder, event.calendar.isReminder else {
            throw CalendarMutationError.wrongRecordType
        }
        guard event.calendar.allowsContentModifications else { throw CalendarMutationError.readOnlyCalendar }
        return try write()
    }

    /// 显式选择不兜底；编辑未指定目标时保留原源；仅新建且未指定目标才选默认可写源。
    static func targetCalendarID(
        requestedID: String?, originalID: String? = nil, defaultID: String?,
        calendars: [CalendarModel], isReminder: Bool
    ) throws -> String {
        if let id = requestedID ?? originalID {
            guard let target = calendars.first(where: { $0.id == id }) else {
                throw CalendarMutationError.invalidCalendar
            }
            guard target.isReminder == isReminder else { throw CalendarMutationError.wrongRecordType }
            guard target.allowsContentModifications else { throw CalendarMutationError.readOnlyCalendar }
            return id
        }
        let writable = calendars.filter { $0.isReminder == isReminder && $0.allowsContentModifications }
        if let defaultID, writable.contains(where: { $0.id == defaultID }) { return defaultID }
        guard let id = writable.first?.id else { throw CalendarMutationError.noWritableCalendar }
        return id
    }
}

enum AttendanceStatus: Comparable {
    case accepted
    case maybe
    case pending
    case declined
    case unknown

    private var comparisonValue: Int {
        switch self {
        case .accepted: return 1
        case .maybe: return 2
        case .declined: return 3
        case .pending: return 4
        case .unknown: return 5
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.comparisonValue < rhs.comparisonValue
    }
}

enum EventType: Equatable {
    case event(AttendanceStatus)
    case birthday
    case reminder(completed: Bool)
}

enum EventStatus: Equatable {
    case upcoming
    case inProgress
    case ended
}

extension EventType {
    var isEvent: Bool { if case .event = self { return true } else { return false } }
    var isBirthday: Bool { self ~= .birthday }
    var isReminder: Bool { if case .reminder = self { return true } else { return false } }
}

extension EventModel {
    
    var eventStatus: EventStatus {
        if start > Date() {
            return .upcoming
        } else if end > Date() {
            return .inProgress
        } else {
            return .ended
        }
    }
        
    var attendance: AttendanceStatus { if case .event(let attendance) = type { return attendance } else { return .unknown } }

    var isMeeting: Bool { !participants.isEmpty }

    var modificationRestriction: CalendarMutationError? {
        if type.isBirthday { return .birthdayEvent }
        if !type.isEvent || calendar.isReminder { return .wrongRecordType }
        if !calendar.allowsContentModifications { return .readOnlyCalendar }
        if isDetached { return .detachedEvent }
        if hasRecurrenceRules { return .recurringEvent }
        if isMeeting { return .meetingEvent }
        return nil
    }

    var canModifyInIsland: Bool { modificationRestriction == nil }

    var canCompleteReminderInIsland: Bool {
        type.isReminder && calendar.isReminder && calendar.allowsContentModifications
    }

    func calendarAppURL() -> URL? {
        // Check if a third-party calendar app is enabled
        if Defaults[.enableThirdPartyCalendarApp] {
            switch Defaults[.selectedCalendarApp] {
            case .fantastical:
                return fantasticalURL()
            case .notionCalendar:
                return notionCalendarURL()
            }
        }
        return appleCalendarURL()
    }
    
    /// Returns URL to open event in Apple Calendar
    private func appleCalendarURL() -> URL? {
        guard let id = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }

        guard !type.isReminder else {
            return URL(string: "x-apple-reminderkit://remcdreminder/\(id)")
        }

        let date: String
        if hasRecurrenceRules {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            if !isAllDay {
                formatter.timeZone = .init(secondsFromGMT: 0)
            }
            if let formattedDate = formatter.string(for: start) {
                date = "/\(formattedDate)"
            } else {
                return nil
            }
        } else {
            date =  ""
        }
        return URL(string: "ical://ekevent\(date)/\(id)?method=show&options=more")
    }
    
    /// Returns URL to open date in Fantastical
    private func fantasticalURL() -> URL? {
        // Reminders still use Apple's Reminders app
        guard !type.isReminder else {
            return URL(string: "x-apple-reminderkit://remcdreminder/\(id)")
        }
        
        let viewStyle = Defaults[.fantasticalDefaultView]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: start)
        
        // x-fantastical3://show/mini/yyyy-MM-dd or x-fantastical3://show/calendar/yyyy-MM-dd
        return URL(string: "x-fantastical3://show/\(viewStyle.rawValue)/\(dateString)")
    }
    
    /// Returns URL to open Fantastical at current date (for general calendar access)
    static func fantasticalShowURL(for date: Date? = nil) -> URL? {
        let viewStyle = Defaults[.fantasticalDefaultView]
        if let date = date {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: date)
            return URL(string: "x-fantastical3://show/\(viewStyle.rawValue)/\(dateString)")
        }
        return URL(string: "x-fantastical3://show/\(viewStyle.rawValue)")
    }
    
    /// Returns URL to open event in Notion Calendar (formerly Cron)
    private func notionCalendarURL() -> URL? {
        // Reminders still use Apple's Reminders app
        guard !type.isReminder else {
            return URL(string: "x-apple-reminderkit://remcdreminder/\(id)")
        }
        
        let formatter = ISO8601DateFormatter()
        
        var components = URLComponents()
        components.scheme = "cron"
        components.host = "showEvent"
        components.queryItems = [
            URLQueryItem(name: "accountEmail", value: calendar.accountName),
            URLQueryItem(name: "iCalUID", value: id),
            URLQueryItem(name: "startDate", value: formatter.string(from: start)),
            URLQueryItem(name: "endDate", value: formatter.string(from: end)),
            URLQueryItem(name: "title", value: title)
        ]
        
        if let url = components.url {
            return url
        }
        
        // Fallback: just launch Notion Calendar app
        Self.launchNotionCalendar()
        return nil
    }
    
    /// Launches Notion Calendar app directly (fallback or general access)
    static func launchNotionCalendar() {
        // Launch via bundle identifier (Notion Calendar's bundle ID is "com.cron.electron")
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.cron.electron") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error = error {
                    print("Error launching Notion Calendar: \(error.localizedDescription)")
                }
            }
        }
    }
}

struct Participant: Hashable {
    let name: String
    let status: AttendanceStatus
    let isOrganizer: Bool
    let isCurrentUser: Bool
}

enum Priority {
    case high
    case medium
    case low
}
