// Modified for Gourd (2026-10-11)
// Copyright (C) 2026 Gourd Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Defaults
import EventKit
import SwiftUI

/// 界面使用包含尾日；共享草稿始终存 EventKit 的排他尾日。
enum CalendarPanelDates {
    static func includedEnd(of draft: CalendarDraft, calendar: Calendar = .current) -> Date {
        draft.isAllDay
            ? CalendarEventInput.includedAllDayEnd(exclusiveEnd: draft.end, calendar: calendar) ?? draft.start
            : draft.end
    }

    static func settingEnd(_ date: Date, in draft: CalendarDraft, calendar: Calendar = .current) -> CalendarDraft {
        var result = draft
        result.end = draft.isAllDay
            ? CalendarEventInput.exclusiveAllDayEnd(including: date, calendar: calendar) ?? draft.end
            : date
        return result
    }

    static func settingAllDay(_ allDay: Bool, in draft: CalendarDraft, calendar: Calendar = .current) -> CalendarDraft {
        guard draft.isAllDay != allDay else { return draft }
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
    @State private var hoveredID: String?

    init(session: CalendarPanelSession, manager: CalendarManager,
         onReturnSource: @escaping (CalendarPanelSource) -> Void) {
        self.session = session
        self.manager = manager
        self.onReturnSource = onReturnSource
        _lifecycle = StateObject(wrappedValue: CalendarEditorLifecycle(session: session))
    }

    private var ownerID: UUID { lifecycle.ownerID }

    private enum Field: Hashable { case title, startTime, endTime, location, notes }
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
        .font(.callout)
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CalendarEditorWindowReader(lifecycle: lifecycle).frame(width: 0, height: 0))
        .onAppear { lifecycle.connect(to: vm) }
        .onChange(of: focusedField) { _, value in
            lifecycle.setEditorFocus(value != nil)
        }
        .onChange(of: datePopover) { _, value in
            lifecycle.setDatePopoverPresented(value != nil)
        }
        .onChange(of: session.route) { _, _ in
            focusedField = nil
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
                Button { show(event) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title).fontWeight(.medium).lineLimit(showFullEventTitles ? nil : 2)
                        Text(CalendarPanelDates.hasDueDate(event) ? (event.isAllDay ? String(localized: "All-day") : event.start.formatted(date: .omitted, time: .shortened)) : String(localized: "calendar.panel.noDueDate"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("calendar-item-\(event.id)")
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(hoveredID == event.id ? 0.1 : 0.05)))
            .opacity(isCompleted(event) ? 0.55 : 1)
            .onHover { hoveredID = $0 ? event.id : nil }
        } else {
            CalendarEventCard(event: event, showFullEventTitles: showFullEventTitles)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(hoveredID == event.id ? 0.05 : 0)))
                .contentShape(Rectangle())
                .onTapGesture { show(event) }
                .onHover { hoveredID = $0 ? event.id : nil }
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("calendar-item-\(event.id)")
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
                Text(event.title).font(.headline).textSelection(.enabled)
                labeledText("calendar.panel.calendar", event.calendar.title)
                if CalendarPanelDates.hasDueDate(event) {
                    labeledText(event.type.isReminder ? "calendar.panel.dueDate" : "calendar.panel.start", displayDate(event.start, allDay: event.isAllDay))
                    if !event.type.isReminder {
                        let end = event.isAllDay ? CalendarEventInput.includedAllDayEnd(exclusiveEnd: event.end) ?? event.start : event.end
                        labeledText("calendar.panel.end", displayDate(end, allDay: event.isAllDay))
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
                if let conferenceURL = event.conferenceURL { ConferenceJoinButton(url: conferenceURL, event: event) }
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

    private func displayDate(_ date: Date, allDay: Bool) -> String {
        allDay ? date.formatted(date: .abbreviated, time: .omitted) : date.formatted(date: .abbreviated, time: .shortened)
    }

    private func labeledText(_ key: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key).font(.caption).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var editorPage: some View {
        ScrollView(.vertical) {
            if let draft = session.draft {
                VStack(alignment: .leading, spacing: 10) {
                    if draft.eventID == nil {
                        Picker("calendar.panel.kind", selection: kindBinding) {
                            Text("calendar.quickAdd.kindReminder").tag(CalendarDraft.Kind.reminder)
                            Text("calendar.quickAdd.kindEvent").tag(CalendarDraft.Kind.event)
                        }
                        .pickerStyle(.segmented).controlSize(.small)
                        .accessibilityIdentifier("calendar-kind")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("calendar.panel.title").font(.caption).foregroundStyle(.secondary)
                        TextField("calendar.quickAdd.title", text: stringBinding(\.title), axis: .vertical)
                            .textFieldStyle(.roundedBorder).focused($focusedField, equals: .title)
                            .accessibilityIdentifier("calendar-title")
                    }
                    targetPicker(draft)
                    if draft.kind == .event {
                        Toggle("All-day", isOn: allDayBinding).toggleStyle(.checkbox)
                            .accessibilityIdentifier("calendar-all-day")
                        dateRow("calendar.panel.start", field: .start, date: draft.start, allDay: draft.isAllDay)
                        dateRow("calendar.panel.end", field: .end, date: CalendarPanelDates.includedEnd(of: draft), allDay: draft.isAllDay)
                        Text("calendar.panel.additional").font(.caption).foregroundStyle(.secondary)
                        TextField("calendar.panel.location", text: stringBinding(\.location), axis: .vertical)
                            .textFieldStyle(.roundedBorder).focused($focusedField, equals: .location)
                            .accessibilityIdentifier("calendar-location")
                        Text("calendar.panel.notes").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: stringBinding(\.notes))
                            .frame(minHeight: 90).focused($focusedField, equals: .notes)
                            .accessibilityIdentifier("calendar-notes")
                    } else {
                        dateRow("calendar.panel.dueDate", field: .start, date: draft.start, allDay: true)
                    }
                    if !hasAccess { Text("Calendar access is required.").font(.caption).foregroundStyle(.secondary) }
                }
                .disabled(session.isSubmitting)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 4)
            }
        }
        .accessibilityIdentifier("calendar-editor-scroll")
        .onHover { lifecycle.setScrolling($0) }
        .task { focusedField = .title }
    }

    private func stringBinding(_ path: WritableKeyPath<CalendarDraft, String>) -> Binding<String> {
        Binding(get: { session.draft?[keyPath: path] ?? "" }, set: { session.draft?[keyPath: path] = $0 })
    }

    private var kindBinding: Binding<CalendarDraft.Kind> {
        Binding(get: { session.draft?.kind ?? .reminder }, set: { kind in
            guard var draft = session.draft else { return }
            draft.kind = kind
            draft.calendarID = kind == .event ? manager.preferredEventCalendarID : manager.preferredReminderCalendarID
            if kind == .event {
                draft.isAllDay = false
                draft.start = CalendarQuickAdd.defaultStart(on: draft.start, now: Date(), calendar: .current)
                draft.end = CalendarQuickAdd.defaultEnd(start: draft.start)
            } else {
                draft.isAllDay = true
                draft.start = Calendar.current.startOfDay(for: draft.start)
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
            if field == .start { draft.start = draft.isAllDay ? Calendar.current.startOfDay(for: date) : date }
            else { draft = CalendarPanelDates.settingEnd(date, in: draft) }
            session.draft = draft
        })
    }

    private func dayBinding(_ field: DateField) -> Binding<Date> {
        let binding = dateBinding(field)
        return Binding(get: { binding.wrappedValue }, set: { date in
            binding.wrappedValue = CalendarPanelDates.changingDay(date, preservingTimeOf: binding.wrappedValue)
        })
    }

    private func dateRow(_ key: LocalizedStringKey, field: DateField, date: Date, allDay: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button { datePopover = field } label: {
                    Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        .font(.caption)
                }
                .accessibilityIdentifier("calendar-\(field.rawValue)-date")
                .popover(isPresented: Binding(get: { datePopover == field }, set: { datePopover = $0 ? field : nil })) {
                    VStack(spacing: 8) {
                        DatePicker(key, selection: dayBinding(field), displayedComponents: .date)
                            .datePickerStyle(.graphical).labelsHidden()
                        Button("calendar.panel.done") { datePopover = nil }
                    }
                    .padding(12)
                }
                if !allDay {
                    DatePicker(key, selection: dateBinding(field), displayedComponents: .hourAndMinute)
                        .labelsHidden().controlSize(.small)
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
                            .disabled(targets.isEmpty || session.draft?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
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
                    Text(displayDate(event.start, allDay: event.isAllDay)).font(.caption).foregroundStyle(.secondary)
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
