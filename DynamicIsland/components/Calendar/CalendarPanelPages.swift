// Modified for Gourd (2026-10-11)
// Copyright (C) 2026 Gourd Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Defaults
import EventKit
import SwiftUI

/// 界面使用包含尾日；共享草稿始终存 EventKit 的排他尾日。
enum CalendarPanelDates {
    /// Invalid identifiers remain unchanged in the draft and are rejected by the save layer.
    static func sourceCalendar(for draft: CalendarDraft, fallback: Calendar = .current) -> Calendar {
        (try? CalendarRecordDates.calendar(timeZoneIdentifier: draft.timeZoneIdentifier, fallback: fallback)) ?? fallback
    }

    static func sourceCalendar(for event: EventModel, fallback: Calendar = .current) -> Calendar {
        var calendar = fallback
        if let zone = event.timeZone { calendar.timeZone = zone }
        return calendar
    }

    static func formatted(_ date: Date, allDay: Bool, calendar: Calendar) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: allDay ? .omitted : .shortened,
                                       calendar: calendar, timeZone: calendar.timeZone))
    }

    static func formattedTime(_ date: Date, calendar: Calendar) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened,
                                       calendar: calendar, timeZone: calendar.timeZone))
    }

    static func settingStart(_ date: Date, in draft: CalendarDraft, calendar: Calendar = .current) -> CalendarDraft {
        let calendar = sourceCalendar(for: draft, fallback: calendar)
        var result = draft
        result.start = draft.isAllDay ? calendar.startOfDay(for: date) : date
        return result
    }

    static func includedEnd(of draft: CalendarDraft, calendar: Calendar = .current) -> Date {
        let calendar = sourceCalendar(for: draft, fallback: calendar)
        return draft.isAllDay
            ? CalendarEventInput.includedAllDayEnd(exclusiveEnd: draft.end, calendar: calendar) ?? draft.start
            : draft.end
    }

    static func settingEnd(_ date: Date, in draft: CalendarDraft, calendar: Calendar = .current) -> CalendarDraft {
        let calendar = sourceCalendar(for: draft, fallback: calendar)
        var result = draft
        result.end = draft.isAllDay
            ? CalendarEventInput.exclusiveAllDayEnd(including: date, calendar: calendar) ?? draft.end
            : date
        return result
    }

    static func settingAllDay(_ allDay: Bool, in draft: CalendarDraft, calendar: Calendar = .current) -> CalendarDraft {
        guard draft.isAllDay != allDay else { return draft }
        let calendar = sourceCalendar(for: draft, fallback: calendar)
        var result = draft
        if allDay {
            let first = calendar.startOfDay(for: draft.start)
            var last = calendar.startOfDay(for: draft.end)
            // 定时结束恰在次日零点时，那一天并不属于事件跨度。
            if draft.end == last, draft.end > draft.start {
                last = calendar.date(byAdding: .day, value: -1, to: last) ?? last
            }
            result.start = first
            result.end = CalendarEventInput.exclusiveAllDayEnd(including: max(first, last), calendar: calendar) ?? draft.end
        } else {
            let last = includedEnd(of: draft, calendar: calendar)
            result.start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: draft.start) ?? draft.start
            result.end = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: last) ?? draft.end
        }
        result.isAllDay = allDay
        return result
    }

    static func hasDueDate(_ event: EventModel) -> Bool {
        !event.type.isReminder || event.start != .distantFuture
    }

    static func changingDay(_ date: Date, preservingTimeOf original: Date, calendar: Calendar = .current) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: original)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                             second: time.second ?? 0, of: date) ?? date
    }
}

/// 页面保存入口与服务使用同一权限口径；仅新建日程可使用 EventKit 仅写授权。
enum CalendarPanelAccess {
    static func canSave(draft: CalendarDraft?, authorization: EKAuthorizationStatus) -> Bool {
        guard let draft else { return false }
        if draft.eventID == nil {
            return CalendarAccessPolicy.canCreate(status: authorization, for: draft.kind == .event ? .event : .reminder)
        }
        return CalendarAccessPolicy.canRead(status: authorization)
    }
}

/// 真实日历右栏。局部状态只描述控件呈现，所有记录与草稿均归共享会话。
struct CalendarPanelPages: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject var session: CalendarPanelSession
    @ObservedObject var manager: CalendarManager
    var onReturnSource: (CalendarPanelSource) -> Void
    @Default(.hideAllDayEvents) private var hideAllDayEvents
    @Default(.hideCompletedReminders) private var hideCompletedReminders
    @Default(.showFullEventTitles) private var showFullEventTitles
    @Default(.autoScrollToNextEvent) private var autoScrollToNextEvent
    @StateObject private var lifecycle: CalendarEditorLifecycle
    @FocusState private var focusedField: Field?
    @State private var datePopover: DateField?
    @State private var deleteConfirmation = false
    @State private var targets: [CalendarModel] = []
    @State private var authorizationRevision = 0
    @State private var nativeEditorFocused = false
    @State private var hoveredID: String?

    init(session: CalendarPanelSession, manager: CalendarManager,
         onReturnSource: @escaping (CalendarPanelSource) -> Void) {
        self.session = session
        self.manager = manager
        self.onReturnSource = onReturnSource
        _lifecycle = StateObject(wrappedValue: CalendarEditorLifecycle(session: session))
    }

    private var ownerID: UUID { lifecycle.ownerID }

    private enum Field: Hashable { case title, startTime, endTime, location, notes, source, url }
    private enum DateField: String, Identifiable { case start, end; var id: String { rawValue } }

    private var events: [EventModel] {
        CalendarEventCardList.ordered(CalendarEventFilters.filtered(
            events: manager.events, hideCompletedReminders: hideCompletedReminders,
            hideAllDayEvents: hideAllDayEvents
        ))
    }

    private var authorization: EKAuthorizationStatus {
        _ = authorizationRevision
        return session.draft?.kind == .reminder ? manager.liveReminderAuthorization : manager.liveCalendarAuthorization
    }

    private var hasAccess: Bool {
        CalendarPanelAccess.canSave(draft: session.draft, authorization: authorization)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let error = session.error {
                Text(error).font(.caption).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("calendar-error")
            }
            if session.pendingConfirmation != nil {
                draftConfirmation
            } else if deleteConfirmation, let event = session.detailEvent {
                deletionConfirmation(event)
            } else {
                switch session.route {
                case .list: listPage
                case .detail:
                    if let event = session.detailEvent { detailPage(event) }
                case .editor: editorPage
                }
            }
            footer
        }
        .environment(\.calendarMeetingSession, session)
        .font(.callout)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CalendarEditorWindowReader(lifecycle: lifecycle).frame(width: 0, height: 0))
        .onAppear { lifecycle.connect(to: vm) }
        .onChange(of: focusedField) { _, value in
            lifecycle.setEditorFocus(value != nil || nativeEditorFocused)
        }
        .onChange(of: datePopover) { _, value in
            lifecycle.setDatePopoverPresented(value != nil)
        }
        .onChange(of: session.route) { _, _ in
            focusedField = nil
            nativeEditorFocused = false
            datePopover = nil
            deleteConfirmation = false
            lifecycle.clearLocalInput()
        }
        .onChange(of: session.detailEvent?.id) { _, _ in deleteConfirmation = false }
        .task(id: session.draft?.kind) { await loadTargets() }
        .onDisappear { lifecycle.stop() }
        .onExitCommand { escape() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if session.route != .list {
                Button(action: goBack) { Image(systemName: "chevron.left") }
                    .accessibilityLabel(Text("calendar.panel.back"))
                    .accessibilityIdentifier("calendar-back")
            }
            Text(headerTitle).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if session.route == .list {
                CalendarQuickAddButton {
                    session.beginCreate(kind: .reminder, on: session.selectedDate, calendarID: manager.preferredReminderCalendarID)
                }
                .accessibilityIdentifier("calendar-add")
            }
            if session.isSubmitting { ProgressView().controlSize(.mini) }
        }
        .frame(height: 24)
    }

    private var headerTitle: String {
        switch session.route {
        case .list: session.selectedDate.formatted(.dateTime.month(.abbreviated).day())
        case .detail: String(localized: "calendar.panel.details")
        case .editor:
            session.draft?.eventID == nil ? String(localized: "calendar.panel.newItem") : String(localized: "calendar.panel.editItem")
        }
    }

    private var listPage: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let draft = session.draft {
                Button { session.resumeDraft() } label: {
                    Label(draft.kind == .event ? String(localized: "calendar.panel.resumeEvent") : String(localized: "calendar.panel.resumeReminder"), systemImage: "pencil.circle")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("calendar-resume-draft")
            }
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if events.isEmpty { EmptyEventsView(selectedDate: session.selectedDate) }
                    ForEach(events) { event in
                        itemCard(event).id(event.id)
                    }
                }
                .scrollTargetLayout()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollPosition(id: $session.calendarScrollAnchor, anchor: .top)
            .scrollIndicators(.never)
            .accessibilityIdentifier("calendar-list-scroll")
            .onHover { lifecycle.setScrolling($0) }
            .onAppear { restoreListAnchor() }
            .onChange(of: events.isEmpty) { _, empty in if !empty { restoreListAnchor() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func restoreListAnchor() {
        guard session.calendarScrollAnchor == nil, autoScrollToNextEvent else { return }
        let timed = partitionEvents(events).timed.sorted { $0.start < $1.start }
        session.calendarScrollAnchor = scrollTargetForTimedEvents(timed: timed, referenceTime: scrollReferenceTime(for: session.selectedDate))?.id
    }

    private func show(_ event: EventModel) {
        session.showDetail(event, source: .calendar(date: session.selectedDate, anchor: session.calendarScrollAnchor ?? event.id))
    }

    @ViewBuilder
    private func itemCard(_ event: EventModel) -> some View {
        if event.type.isReminder {
            HStack(spacing: 10) {
                completionButton(event)
                VStack(alignment: .leading, spacing: 4) {
                    CalendarSelectableText(text: event.title, payload: CalendarCopyPayload(event: event),
                                           font: .systemFont(ofSize: NSFont.systemFontSize, weight: .medium),
                                           maximumLines: showFullEventTitles ? 0 : 2)
                    Text(CalendarPanelDates.hasDueDate(event) ? (event.isAllDay ? String(localized: "All-day") : CalendarPanelDates.formattedTime(event.start, calendar: CalendarPanelDates.sourceCalendar(for: event))) : String(localized: "calendar.panel.noDueDate"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                meetingAction(event)
                Button { show(event) } label: { Image(systemName: "chevron.right") }
                    .disabled(session.isSubmitting)
                    .accessibilityLabel(Text("calendar.panel.details"))
                    .accessibilityIdentifier("calendar-item-\(event.id)")
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(hoveredID == event.id ? 0.1 : 0.05)))
            .opacity(isCompleted(event) ? 0.55 : 1)
            .onHover { hoveredID = $0 ? event.id : nil }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                CalendarEventCard(event: event, showFullEventTitles: showFullEventTitles,
                                  onDetail: { show(event) }, detailEnabled: !session.isSubmitting)
                if event.conferenceURL == nil {
                    meetingAction(event)
                }
            }
                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(hoveredID == event.id ? 0.05 : 0)))
                .contentShape(Rectangle())
                .onHover { hoveredID = $0 ? event.id : nil }
        }
    }

    private func isCompleted(_ event: EventModel) -> Bool {
        if case .reminder(let completed) = event.type { return completed }
        return false
    }

    private func completionButton(_ event: EventModel) -> some View {
        Button { Task { _ = await session.complete(event, completed: !isCompleted(event)) } } label: {
            Image(systemName: isCompleted(event) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(Color(event.calendar.color)).font(.system(size: 18))
        }
        .disabled(session.isSubmitting || !event.canCompleteReminderInIsland)
        .accessibilityLabel(Text(isCompleted(event) ? "calendar.panel.markIncomplete" : "calendar.panel.markComplete"))
        .accessibilityIdentifier("calendar-complete-\(event.id)")
    }

    private func detailPage(_ event: EventModel) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                CalendarSelectableText(text: event.title, payload: CalendarCopyPayload(event: event),
                                       font: .systemFont(ofSize: NSFont.systemFontSize, weight: .bold))
                labeledText("calendar.panel.calendar", event.calendar.title)
                if CalendarPanelDates.hasDueDate(event) {
                    labeledText(event.type.isReminder ? "calendar.panel.dueDate" : "calendar.panel.start", displayDate(event.start, allDay: event.isAllDay, calendar: CalendarPanelDates.sourceCalendar(for: event)))
                    if !event.type.isReminder {
                        let end = event.isAllDay ? CalendarEventInput.includedAllDayEnd(exclusiveEnd: event.end, calendar: CalendarPanelDates.sourceCalendar(for: event)) ?? event.start : event.end
                        labeledText("calendar.panel.end", displayDate(end, allDay: event.isAllDay, calendar: CalendarPanelDates.sourceCalendar(for: event)))
                    }
                } else { Text("calendar.panel.noDueDate").foregroundStyle(.secondary) }
                if event.isAllDay { Text("All-day").font(.caption).foregroundStyle(.secondary) }
                if let location = event.location, !location.isEmpty { labeledText("calendar.panel.location", location) }
                if let notes = event.notes, !notes.isEmpty {
                    labeledText("calendar.panel.notes", notes)
                    // 尾标记给 UI 验证明确的可滚达节点，不截断或限制备注高度。
                    Text("calendar.panel.notesEnd").font(.caption2).foregroundStyle(.secondary)
                        .accessibilityIdentifier("calendar-notes-end")
                }
                meetingAction(event)
                if event.type.isReminder {
                    Text(LocalizedStringKey(event.calendar.allowsContentModifications ? "Edit saved reminders in the system app." : "This calendar is read-only."))
                        .font(.caption).foregroundStyle(.secondary)
                } else if let reason = event.modificationRestriction {
                    Text(reason.localizedDescription).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 4)
        }
        .accessibilityIdentifier("calendar-detail-scroll")
        .onHover { lifecycle.setScrolling($0) }
    }

    func meetingAction(_ event: EventModel) -> MeetingActionView {
        MeetingActionView(event: event, session: session, style: .row)
    }

    private func displayDate(_ date: Date, allDay: Bool, calendar: Calendar) -> String {
        CalendarPanelDates.formatted(date, allDay: allDay, calendar: calendar)
    }

    private func labeledText(_ key: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key).font(.caption).foregroundStyle(.secondary)
            if let event = session.detailEvent {
                CalendarSelectableText(text: value, payload: CalendarCopyPayload(event: event))
            }
        }
    }

    private var editorPage: some View {
        ScrollView(.vertical) {
            if let draft = session.draft {
                // 行距 8（D-17）：+3 号字号下把整页收进 400 的编辑档高——不动字号、控件尺寸与内外边距。
                VStack(alignment: .leading, spacing: 8) {
                    // 新建可点、编辑锁定（而不是不渲染）：四种入口的版式不再跳。
                    Picker("calendar.panel.kind", selection: kindBinding) {
                        Text("calendar.quickAdd.kindReminder").tag(CalendarDraft.Kind.reminder)
                        Text("calendar.quickAdd.kindEvent").tag(CalendarDraft.Kind.event)
                    }
                    .pickerStyle(.segmented).controlSize(.small)
                    .disabled(draft.eventID != nil)
                    .accessibilityIdentifier("calendar-kind")
                    if draft.eventID == nil { generationControls(draft) }
                    fieldRow("calendar.panel.title") {
                        TextField("calendar.quickAdd.title", text: stringBinding(\.title), axis: .vertical)
                            .textFieldStyle(.roundedBorder).focused($focusedField, equals: .title)
                            .accessibilityIdentifier("calendar-title")
                    }
                    // 目标｜全天
                    HStack(spacing: 8) {
                        targetPicker(draft).frame(maxWidth: .infinity, alignment: .leading)
                        fieldRow("All-day") {
                            Toggle("All-day", isOn: allDayBinding).toggleStyle(.checkbox).labelsHidden()
                                .accessibilityIdentifier("calendar-all-day")
                        }
                    }
                    if let identifier = draft.timeZoneIdentifier, identifier != TimeZone.current.identifier {
                        Text(String(format: String(localized: "calendar.panel.sourceTimeZoneFormat"), identifier))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    // 日程：开始｜结束 一行、地点｜链接 一行；待办：截止｜链接 一行（不留任何空半格）
                    if draft.kind == .event {
                        HStack(spacing: 8) {
                            dateRow("calendar.panel.start", field: .start, date: draft.start, allDay: draft.isAllDay)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            dateRow("calendar.panel.end", field: .end, date: CalendarPanelDates.includedEnd(of: draft), allDay: draft.isAllDay)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack(spacing: 8) {
                            fieldRow("calendar.panel.location") {
                                TextField("calendar.panel.location", text: stringBinding(\.location), axis: .vertical)
                                    .textFieldStyle(.roundedBorder).focused($focusedField, equals: .location)
                                    .accessibilityIdentifier("calendar-location")
                            }
                            urlField
                        }
                    } else {
                        HStack(spacing: 8) {
                            dateRow("calendar.panel.dueDate", field: .start, date: draft.start, allDay: draft.isAllDay)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            urlField
                        }
                    }
                    // 备注的落点由框本身承担（浅边框 + 框内占位文字，D-04）：不再另起一行标签。
                    CalendarGrowingTextEditor(text: stringBinding(\.notes), label: "calendar.panel.notes",
                                              placeholder: "calendar.panel.notes",
                                              onFocus: setNativeEditorFocus)
                        .accessibilityIdentifier("calendar-notes")
                    confirmationControls(draft)
                    if !hasAccess { Text("Calendar access is required.").font(.caption).foregroundStyle(.secondary) }
                }
                .disabled(session.isSubmitting)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 4)
            }
        }
        .accessibilityIdentifier("calendar-editor-scroll")
        .onHover { lifecycle.setScrolling($0) }
        .onAppear { focusedField = session.draft?.sourceText.isEmpty == true ? .title : nil }
    }

    /// 表单里的一格：沿用「标签在上、控件在下」的既有风格，并占满所在列宽（两列网格的一半）。
    private func fieldRow(_ label: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 「链接」一格：日程的「地点｜链接」行与待办的「截止｜链接」行共用，避免两处漂移。
    private var urlField: some View {
        fieldRow("calendar.panel.url") {
            TextField("calendar.panel.url", text: urlBinding)
                .textFieldStyle(.roundedBorder).focused($focusedField, equals: .url)
                .accessibilityIdentifier("calendar-url")
        }
    }

    private func setNativeEditorFocus(_ focused: Bool) {
        nativeEditorFocused = focused
        lifecycle.setEditorFocus(focused || focusedField != nil)
    }

    private var urlBinding: Binding<String> {
        Binding(get: { session.draft?.url?.absoluteString ?? "" }, set: {
            session.draft?.url = $0.isEmpty ? nil : URL(string: $0)
        })
    }

    private func generationControls(_ draft: CalendarDraft) -> some View {
        CalendarSourceGeneration(session: session, initialText: draft.sourceText, onFocus: setNativeEditorFocus)
            .id(session.draftIdentity)
    }

    @ViewBuilder
    private func confirmationControls(_ draft: CalendarDraft) -> some View {
        if draft.generationMode == .required || !draft.confirmations.isEmpty {
            Text("calendar.generation.blocked").font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("calendar-generation-blocked")
            if draft.generationMode != .required {
                ForEach(ScheduleConfirmation.allCases, id: \.rawValue) { item in
                    if draft.confirmations.contains(item) {
                        Button(LocalizedStringKey(item.labelKey)) { session.confirmSource(item) }
                            .font(.caption).accessibilityIdentifier("calendar-generation-confirm-" + item.rawValue)
                    }
                }
            }
        }
    }

    private func stringBinding(_ path: WritableKeyPath<CalendarDraft, String>) -> Binding<String> {
        Binding(get: { session.draft?[keyPath: path] ?? "" }, set: { session.draft?[keyPath: path] = $0 })
    }

    private var kindBinding: Binding<CalendarDraft.Kind> {
        Binding(get: { session.draft?.kind ?? .reminder }, set: { kind in
            guard var draft = session.draft else { return }
            let calendar = CalendarPanelDates.sourceCalendar(for: draft)
            draft.kind = kind
            draft.calendarID = kind == .event ? manager.preferredEventCalendarID : manager.preferredReminderCalendarID
            if kind == .event, draft.sourceText.isEmpty {
                draft.isAllDay = false
                draft.start = CalendarQuickAdd.defaultStart(on: draft.start, now: Date(), calendar: calendar)
                draft.end = CalendarQuickAdd.defaultEnd(start: draft.start)
            }
            session.draft = draft
        })
    }

    private var allDayBinding: Binding<Bool> {
        Binding(get: { session.draft?.isAllDay ?? false }, set: { value in
            if let draft = session.draft { session.draft = CalendarPanelDates.settingAllDay(value, in: draft) }
        })
    }

    private func dateBinding(_ field: DateField) -> Binding<Date> {
        Binding(get: {
            guard let draft = session.draft else { return Date() }
            return field == .start ? draft.start : CalendarPanelDates.includedEnd(of: draft)
        }, set: { date in
            guard var draft = session.draft else { return }
            if field == .start { draft = CalendarPanelDates.settingStart(date, in: draft) }
            else { draft = CalendarPanelDates.settingEnd(date, in: draft) }
            session.draft = draft
        })
    }

    private func dayBinding(_ field: DateField) -> Binding<Date> {
        let binding = dateBinding(field)
        return Binding(get: { binding.wrappedValue }, set: { date in
            guard let draft = session.draft else { return }
            binding.wrappedValue = CalendarPanelDates.changingDay(
                date, preservingTimeOf: binding.wrappedValue, calendar: CalendarPanelDates.sourceCalendar(for: draft)
            )
        })
    }

    private func dateRow(_ key: LocalizedStringKey, field: DateField, date: Date, allDay: Bool) -> some View {
        let calendar = session.draft.map { CalendarPanelDates.sourceCalendar(for: $0) } ?? .current
        return VStack(alignment: .leading, spacing: 4) {
            Text(key).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button { datePopover = field } label: {
                    Label(CalendarPanelDates.formatted(date, allDay: true, calendar: calendar), systemImage: "calendar")
                        .font(.caption)
                }
                .accessibilityIdentifier("calendar-\(field.rawValue)-date")
                .popover(isPresented: Binding(get: { datePopover == field }, set: { datePopover = $0 ? field : nil })) {
                    VStack(spacing: 8) {
                        DatePicker(key, selection: dayBinding(field), displayedComponents: .date)
                            .datePickerStyle(.graphical).labelsHidden()
                            .environment(\.calendar, calendar)
                            .environment(\.timeZone, calendar.timeZone)
                        Button("calendar.panel.done") { datePopover = nil }
                    }
                    .padding(12)
                }
                if !allDay {
                    DatePicker(key, selection: dateBinding(field), displayedComponents: .hourAndMinute)
                        .labelsHidden().controlSize(.small)
                        .environment(\.calendar, calendar)
                        .environment(\.timeZone, calendar.timeZone)
                        .focused($focusedField, equals: field == .start ? .startTime : .endTime)
                        .accessibilityIdentifier("calendar-\(field.rawValue)-time")
                }
            }
        }
    }

    private func targetPicker(_ draft: CalendarDraft) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(draft.kind == .event ? "calendar.panel.calendar" : "calendar.panel.list")
                .font(.caption).foregroundStyle(.secondary)
            if targets.isEmpty {
                Text("No writable calendar is available.").font(.caption).foregroundStyle(.secondary)
            } else {
                CalendarPanelTargetPicker(targets: targets, selection: Binding(
                    get: { session.draft?.calendarID }, set: { session.draft?.calendarID = $0 }
                ), session: session, ownerID: ownerID, lifecycle: lifecycle)
                .frame(height: 24).accessibilityIdentifier("calendar-target")
            }
        }
    }

    private func loadTargets() async {
        targets = session.draft?.kind == .reminder ? manager.writableReminderCalendars() : await manager.creatableEventCalendars()
        // 仅缺失目标的稿可在授权后获得初始目标；不替换用户已选或外部失效的 ID。
        if session.draft?.calendarID == nil {
            session.draft?.calendarID = session.draft?.kind == .reminder ? manager.preferredReminderCalendarID : manager.preferredEventCalendarID
        }
    }

    @ViewBuilder
    private var footer: some View {
        if session.pendingConfirmation == nil && !deleteConfirmation {
            switch session.route {
            case .list: EmptyView()
            case .detail:
                if let event = session.detailEvent {
                    HStack(spacing: 12) {
                        Button(event.type.isReminder ? "calendar.panel.openReminders" : "calendar.panel.openCalendar") { session.openInSystemApp(event) }
                            .font(.caption).accessibilityIdentifier("calendar-open-system")
                        Spacer(minLength: 0)
                        if event.type.isReminder { completionButton(event) }
                        else if event.canModifyInIsland {
                            Button { session.beginEdit(event) } label: { Image(systemName: "pencil") }
                                .accessibilityLabel(Text("calendar.panel.editItem")).accessibilityIdentifier("calendar-edit")
                            Button { deleteConfirmation = true } label: { Image(systemName: "trash") }
                                .accessibilityLabel(Text("calendar.panel.delete")).accessibilityIdentifier("calendar-delete")
                        }
                    }.disabled(session.isSubmitting).frame(height: 28)
                }
            case .editor:
                HStack(spacing: 12) {
                    Button("Cancel") { session.requestCancel() }.accessibilityIdentifier("calendar-cancel")
                    Spacer(minLength: 0)
                    if hasAccess {
                        Button("calendar.panel.save") { Task { _ = await session.save() } }
                            .disabled(targets.isEmpty || session.draft?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
                                      || session.draft?.generationMode == .required || session.draft?.confirmations.isEmpty != true)
                            .accessibilityIdentifier("calendar-save")
                    } else { authorizationButton }
                }.disabled(session.isSubmitting).font(.caption).frame(height: 28)
            }
        }
    }

    @ViewBuilder
    private var authorizationButton: some View {
        if authorization == .notDetermined {
            Button("Request Access") {
                Task {
                    if session.draft?.kind == .reminder { await manager.checkReminderAuthorization() }
                    else { await manager.checkCalendarAuthorization() }
                    authorizationRevision += 1
                    await loadTargets()
                }
            }.accessibilityIdentifier("calendar-request-access")
        } else {
            Button("Open System Settings") {
                let pane = session.draft?.kind == .reminder ? "Privacy_Reminders" : "Privacy_Calendars"
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
            }.accessibilityIdentifier("calendar-open-settings")
        }
    }

    private var draftConfirmation: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.pendingConfirmation == .draftConflict ? "calendar.panel.draftConflict" : "calendar.panel.discardQuestion")
                    if let draft = session.draft { Text(draft.title).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if session.pendingConfirmation == .draftConflict {
                Button("calendar.panel.continueDraft") { session.resolveDraftConflict(.resume) }
                    .accessibilityIdentifier("calendar-conflict-resume")
                Button("calendar.panel.discardAndStart") { session.resolveDraftConflict(.discardAndStart) }
                    .accessibilityIdentifier("calendar-conflict-discard")
                Button("Cancel") { session.resolveDraftConflict(.cancel) }
                    .accessibilityIdentifier("calendar-conflict-cancel")
            } else {
                HStack {
                    Button("calendar.panel.keepEditing") { session.dismissConfirmation() }
                        .accessibilityIdentifier("calendar-discard-cancel")
                    Spacer()
                    Button("calendar.panel.discard") { session.discardDraft() }
                        .accessibilityIdentifier("calendar-discard-confirm")
                }
            }
        }
        .disabled(session.isSubmitting)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier(session.pendingConfirmation == .draftConflict ? "calendar-draft-conflict" : "calendar-draft-discard")
    }

    private func deletionConfirmation(_ event: EventModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("calendar.panel.deleteQuestion").font(.headline)
                    Text(event.title)
                    Text(displayDate(event.start, allDay: event.isAllDay, calendar: CalendarPanelDates.sourceCalendar(for: event))).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Cancel") { deleteConfirmation = false }.accessibilityIdentifier("calendar-delete-cancel")
                Spacer()
                Button("calendar.panel.delete") {
                    // 删除后保留来源附近的锚点，不能继续指向已消失记录。
                    if case .calendar(let date, let anchor) = session.returnSource,
                       anchor == event.id, let index = events.firstIndex(where: { $0.id == event.id }) {
                        let neighbor = events.dropFirst(index + 1).first?.id ?? events.prefix(index).last?.id
                        // 提交前绑定来源；异步完成后不改共享锚点，避免旧结果污染新导航。
                        session.showDetail(event, source: .calendar(date: date, anchor: neighbor))
                    }
                    let source = session.returnSource
                    Task {
                        if await session.delete() {
                            deleteConfirmation = false
                            if session.route == .list, session.returnSource == source, case .home = source {
                                onReturnSource(source)
                            }
                        }
                    }
                }.accessibilityIdentifier("calendar-delete-confirm")
            }.disabled(session.isSubmitting)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func goBack() {
        if let source = session.back() { onReturnSource(source) }
    }

    private func escape() {
        if datePopover != nil { datePopover = nil }
        else if session.pendingConfirmation != nil { session.dismissConfirmation() }
        else if deleteConfirmation { deleteConfirmation = false }
        else if session.route != .list { goBack() }
        else { vm.close() }
    }
}

/// 显式生成：原文先落在本视图的本地 state，点「生成」（或 ⌘↩）才写回草稿并触发一次解析。
///
/// 输入框的复位：权威机制是**本视图被卸载**（`pendingConfirmation != nil` 时 body 走别的分支、
/// `suspend()` 把 route 切走），卸载即丢掉 `@State`，重新出现时用 `initialText`（当前草稿原文）起头。
/// 调用方另按 `session.draftIdentity` 定了 `.id`，那是**二次保险**：今天不存在「不卸载本视图的同
/// route 换稿」路径，所以它未被独立验证（见 `DynamicIslandTests` 的换稿用例与报告 I3）。
private struct CalendarSourceGeneration: View {
    @ObservedObject var session: CalendarPanelSession
    let onFocus: (Bool) -> Void
    @State private var sourceDraft: String

    init(session: CalendarPanelSession, initialText: String, onFocus: @escaping (Bool) -> Void) {
        self.session = session
        self.onFocus = onFocus
        _sourceDraft = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("calendar.generation.source").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 8) {
                CalendarGrowingTextEditor(text: $sourceDraft, label: "calendar.generation.source", onFocus: onFocus)
                    .accessibilityIdentifier("calendar-generation-source")
                if session.generationState == .parsing || session.generationState == .debouncing {
                    ProgressView().controlSize(.mini)
                    Button("Cancel") { session.cancelSourceParsing() }
                        .accessibilityIdentifier("calendar-generation-cancel")
                } else if session.generationState != .failed, hasSource {
                    Button("calendar.generation.generate") { generate() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityIdentifier("calendar-generation-generate")
                }
                // AI 模型设置：从按钮降级为生成行右端的齿轮，文案复用既有键。
                Button { CalendarAISettingsNavigation.open() } label: { Image(systemName: "gearshape") }
                    .help(Text("calendar.generation.settings"))
                    .accessibilityLabel(Text("calendar.generation.settings"))
                    .accessibilityIdentifier("calendar-generation-settings")
            }
            if session.configuredAI == nil {
                Text("calendar.generation.unconfigured").font(.caption2).foregroundStyle(.secondary)
            }
            // 状态词不再单独占行：只有失败时留一行「生成失败：<原因>」+ 重试。
            if session.generationState == .failed {
                HStack(spacing: 8) {
                    (Text("calendar.generation.state.failed") + Text(session.generationError.map { "：" + $0 } ?? ""))
                        .font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("calendar-generation-failed")
                    Button("calendar.generation.retry") { generate() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .font(.caption).accessibilityIdentifier("calendar-generation-retry")
                    Button("calendar.generation.manual") { session.useManualEntry() }
                        .font(.caption).accessibilityIdentifier("calendar-generation-manual")
                }
            } else if session.draft?.generationMode == .required || session.generationState == .cancelled {
                Button("calendar.generation.manual") { session.useManualEntry() }
                    .font(.caption).accessibilityIdentifier("calendar-generation-manual")
            }
        }
    }

    private var hasSource: Bool {
        !sourceDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 点「生成」/⌘↩：先同步写回原文并进入 `.parsing`（不闪 `.debouncing`），再请求这一次解析。
    /// 两步之间没有自动调度，也无第二次解析。
    private func generate() {
        session.commitSourceForGeneration(sourceDraft)
        Task { await session.generateDraft() }
    }
}

/// NSPopUpButton 的 NSMenuDelegate 提供真实菜单开关，避免 onHover 猜测菜单状态。
private struct CalendarPanelTargetPicker: NSViewRepresentable {
    var targets: [CalendarModel]
    @Binding var selection: String?
    var session: CalendarPanelSession
    var ownerID: UUID
    var lifecycle: CalendarEditorLifecycle

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .small
        button.target = context.coordinator
        button.action = #selector(Coordinator.choose(_:))
        button.menu?.delegate = context.coordinator
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        let expectedIDs = (!targets.contains(where: { $0.id == selection }) ? [""] : []) + targets.map(\.id)
        if button.itemArray.map({ $0.representedObject as? String ?? "" }) == expectedIDs {
            button.select(button.itemArray.first(where: { $0.representedObject as? String == selection }))
            button.isEnabled = !session.isSubmitting
            return
        }
        button.removeAllItems()
        if !targets.contains(where: { $0.id == selection }) {
            button.addItem(withTitle: String(localized: "calendar.panel.chooseTarget"))
            button.lastItem?.representedObject = ""
        }
        for target in targets {
            button.addItem(withTitle: target.title)
            button.lastItem?.representedObject = target.id
        }
        button.select(button.itemArray.first(where: { $0.representedObject as? String == selection }))
        button.isEnabled = !session.isSubmitting
        button.menu?.delegate = context.coordinator
    }

    static func dismantleNSView(_ nsView: NSPopUpButton, coordinator: Coordinator) {
        coordinator.parent.lifecycle.setOwnedMenuCount(0)
        nsView.menu?.delegate = nil
    }

    @MainActor final class Coordinator: NSObject, NSMenuDelegate {
        var parent: CalendarPanelTargetPicker
        init(_ parent: CalendarPanelTargetPicker) { self.parent = parent }
        @objc func choose(_ sender: NSPopUpButton) {
            guard let id = sender.selectedItem?.representedObject as? String, !id.isEmpty else { return }
            parent.selection = id
        }
        func menuWillOpen(_ menu: NSMenu) { parent.lifecycle.setOwnedMenuCount(1) }
        func menuDidClose(_ menu: NSMenu) { parent.lifecycle.setOwnedMenuCount(0) }
    }
}
