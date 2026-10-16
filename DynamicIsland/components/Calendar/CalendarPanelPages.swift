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
/// 编辑页与列表卡片的字号档（docs/49 D-06 / D-17：整体 +3 号）。
/// 视图只引用名字，数值只在这里改一次；AppKit 侧（原生文本控件）走 `PointSize` 那几个数。
enum CalendarPanelTypography {
    static let fieldLabelPointSize: CGFloat = 13      // 字段标签（原 .caption ≈ 10）
    static let fieldInputPointSize: CGFloat = 15      // 输入框正文（原 12）
    static let actionPointSize: CGFloat = 13          // 按钮与状态文字（原 .caption / .caption2）
    static let cardTitlePointSize: CGFloat = 15       // 列表卡片标题（原 systemFontSize 13）
    static let cardSecondaryPointSize: CGFloat = 13   // 列表卡片次要（原 smallSystemFontSize 11 / .caption 10）
    static let bigEditorPointSize: CGFloat = 16       // 大文本编辑器（原 systemFontSize 13）

    static var fieldLabel: Font { .system(size: fieldLabelPointSize) }
    static var fieldInput: Font { .system(size: fieldInputPointSize) }
    static var action: Font { .system(size: actionPointSize) }
    static var cardTitle: Font { .system(size: cardTitlePointSize) }
    static var cardSecondary: Font { .system(size: cardSecondaryPointSize) }

    static func appKitTitle(_ weight: NSFont.Weight) -> NSFont {
        .systemFont(ofSize: cardTitlePointSize, weight: weight)
    }
    static func appKitSecondary() -> NSFont { .systemFont(ofSize: cardSecondaryPointSize) }
}

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
    /// 详情浮层状态（D-07：列表行整行点开它；页/列级一份，**不**在滚动视口里）。
    @StateObject private var details = CalendarEventDetailsModel()
    /// 就地删除确认的目标 id（C2：行下方确认条；同一时刻只认一条）。
    @State private var deleteTargetID: String?
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
            } else {
                switch session.route {
                case .list: listPage
                case .editor: editorPage
                }
            }
            footer
        }
        // 删除确认弹框（2026-10-16 第 6 条：由「行下方确认条」改为弹框）：挂在浮层之上。
        .overlay {
            if let target = deleteTargetID.flatMap({ id in events.first { $0.id == id } }) {
                CalendarDeleteConfirmation(
                    event: target,
                    onConfirm: { Task { await confirmDelete(target) } },
                    onCancel: { deleteTargetID = nil }
                )
            }
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
            // 切页（列表 ↔ 编辑）也要把浮窗与确认条收掉：C2「条目离窗 / 切页 / 收起面板 → 自动复位」，
            // 否则从编辑档返回列表时那条浮窗会带着旧态自己冒出来。
            details.clear()
            deleteTargetID = nil
            focusedField = nil
            nativeEditorFocused = false
            datePopover = nil
            lifecycle.clearLocalInput()
        }
        .task(id: session.draft?.kind) { await loadTargets() }
        // 收面板 / 视图卸载：浮窗与确认条一律复位（D-23：不抑制自动收起，浮窗随面板一起关）。
        .onChange(of: vm.notchState) { _, state in
            if state != .open { details.clear(); deleteTargetID = nil }
        }
        .onDisappear {
            details.clear()
            deleteTargetID = nil
            lifecycle.stop()
        }
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
        case .editor:
            session.draft?.eventID == nil ? String(localized: "calendar.panel.newItem") : String(localized: "calendar.panel.editItem")
        }
    }

    private var listPage: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 「继续编辑」这一行**只看「有未保存改动」，不看「存在稿」**（docs/49 D-39，判据与 D-36
            // 同源）：开一条日程一个字没改就回月历，不该在这里冒出一行假提示。会话侧那三个出口
            // （`back()` / `showList(on:)` / `suspend()`）也会把干净的稿丢掉——这里是第二道，
            // 将来多一条出口也不会漏。
            if session.hasDirtyDraft, let draft = session.draft {
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
        // 详情浮层挂在**列级**（滚动视口之外，C2 硬规则）：锚点由行上报，浮层就近定位。
        .calendarEventDetails(model: details, actions: detailActions)
    }

    private func restoreListAnchor() {
        guard session.calendarScrollAnchor == nil, autoScrollToNextEvent else { return }
        let timed = partitionEvents(events).timed.sorted { $0.start < $1.start }
        session.calendarScrollAnchor = scrollTargetForTimedEvents(timed: timed, referenceTime: scrollReferenceTime(for: session.selectedDate))?.id
    }


    /// 面板列表行的会议入口（一枚 22×22 按钮，与首页同款；docs/49 D-19）。既有用例
    /// （`CalendarGenerationAndMeetingActionTests`）靠它取面板侧的会议接线。
    func meetingAction(_ event: EventModel) -> MeetingActionView {
        MeetingActionView(event: event, session: session)
    }

    /// 列表行（C1 设计图 / docs/49 D-07·D-19·D-20）：整行可点 → 钉住详情浮层；右端动作**整组贴右**
    /// （会议 22 + ✎ 28 + 🗑 28，间距 8，最后一枚的右缘 = 行内边距内缘 11）；只读记录整组不画
    /// （标题用满宽度）。行下方可挂就地删除确认条。
    @ViewBuilder
    private func itemCard(_ event: EventModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if event.type.isReminder {
                    completionButton(event)
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color(event.calendar.color)).frame(width: 4, height: 36)
                }
                VStack(alignment: .leading, spacing: 3) {
                    CalendarSelectableText(text: event.title, payload: CalendarCopyPayload(event: event),
                                           font: CalendarPanelTypography.appKitTitle(.medium),
                                           maximumLines: showFullEventTitles ? 0 : 2,
                                           onPlainClick: { details.togglePin(event.id) })
                    HStack(spacing: 8) {
                        Text(dueOrTimeText(event))
                            .font(CalendarPanelTypography.cardSecondary).foregroundStyle(.secondary)
                        MeetingActionInfoText(event: event, session: session)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                rowActionGroup(event)
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(hoveredID == event.id ? 0.06 : 0.03)))
        .opacity(isCompleted(event) ? 0.55 : 1)
        .contentShape(Rectangle())
        // 既有 UI 套件的定位符（`calendar-item-<id>`）：改前挂在右端箭头按钮上，现在整行可点，挂回容器。
        .accessibilityIdentifier("calendar-item-\(event.id)")
        .onHover { hoveredID = $0 ? event.id : nil }
        // 整行点开详情浮层（D-07）：再点同一行取消。文字上的单击由文本视图自己吃（可拖选），
        // 属实现时实测 + 人工项（计划 ②）。
        .onTapGesture { details.togglePin(event.id) }
        .anchorPreference(key: CalendarEventAnchorKey.self, value: .bounds) { [event.id: $0] }
    }

    /// 行的第二行文字（C1 设计图）：日程给「起–止」时段、全天只写 All-day；待办给「截止 日期」
    /// （无截止给既有「无截止」键）。刻意不写日期——列表本身就是按日分组的。
    private func dueOrTimeText(_ event: EventModel) -> String {
        let calendar = CalendarPanelDates.sourceCalendar(for: event)
        if event.type.isReminder {
            guard CalendarPanelDates.hasDueDate(event) else { return String(localized: "calendar.panel.noDueDate") }
            return event.isAllDay
                ? String(localized: "All-day")
                : String(localized: "calendar.panel.dueDate") + " "
                    + CalendarPanelDates.formatted(event.start, allDay: true, calendar: calendar)
        }
        if event.isAllDay { return String(localized: "All-day") }
        return CalendarPanelDates.formattedTime(event.start, calendar: calendar)
            + " – " + CalendarPanelDates.formattedTime(event.end, calendar: calendar)
    }

    /// 右端动作组（C1：只对可写记录给 ✎ / 🗑；会议入口与首页同款一枚按钮，`hasMeetingInformation` 判据）。
    @ViewBuilder
    private func rowActionGroup(_ event: EventModel) -> some View {
        let source = CalendarMeetingSource(event: event)
        let canDelete = CalendarPanelSession.canDeleteInIsland(event)
        if source.hasMeetingInformation || event.canModifyInIsland || canDelete {
            HStack(spacing: 8) {
                if source.hasMeetingInformation {
                    meetingAction(event)
                }
                if event.canModifyInIsland, !event.type.isReminder {
                    rowIconButton("calendar.panel.editItem", systemImage: "pencil") { session.beginEdit(event) }
                        .accessibilityIdentifier("calendar-row-edit-\(event.id)")
                }
                if canDelete {
                    rowIconButton("calendar.panel.delete", systemImage: "trash") { requestDelete(event) }
                        .accessibilityIdentifier("calendar-row-delete-\(event.id)")
                }
            }
            .disabled(session.isSubmitting)
        }
    }

    /// 行内一枚动作图标：28pt 命中区 + 16pt 图标（C1 的圆形按钮）。
    private func rowIconButton(_ labelKey: LocalizedStringKey, systemImage: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(0.10)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(Text(labelKey))
        .accessibilityLabel(Text(labelKey))
    }

    /// 行内 🗑 / 浮层里的删除（C2 硬规则③）：**先收浮窗**，再在行下方出确认条——同屏只留一个浮层。
    private func requestDelete(_ event: EventModel) {
        details.clear()
        deleteTargetID = event.id
    }

    private func confirmDelete(_ event: EventModel) async {
        guard await session.delete(event) else { return }
        deleteTargetID = nil
        // 删掉的那条如果正是滚动锚点，把它挪到邻近条目（旧 `deletionConfirmation` 里的同一语义：
        // 锚点不能继续指向已消失的记录）。
        if session.calendarScrollAnchor == event.id,
           let index = events.firstIndex(where: { $0.id == event.id }) {
            session.calendarScrollAnchor = events.dropFirst(index + 1).first?.id ?? events.prefix(index).last?.id
        }
    }

    /// 浮层卡片的动作集（H2 设计图 / D-20）：按记录类型给；只读记录只给「打开系统日历」。
    private func detailActions(_ event: EventModel) -> CalendarEventDetailActions {
        let source = CalendarMeetingSource(event: event)
        let isReminder = event.type.isReminder
        let completed = isCompleted(event)
        return CalendarEventDetailActions(
            openSystem: { session.openInSystemApp(event) },
            complete: isReminder ? { Task { _ = await session.complete(event, completed: !completed) } } : nil,
            edit: event.canModifyInIsland && !isReminder ? { session.beginEdit(event) } : nil,
            delete: CalendarPanelSession.canDeleteInIsland(event) ? { requestDelete(event) } : nil,
            meeting: source.hasMeetingInformation ? { MeetingActionView(source: source, session: session) } : nil
        )
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



    private func displayDate(_ date: Date, allDay: Bool, calendar: Calendar) -> String {
        CalendarPanelDates.formatted(date, allDay: allDay, calendar: calendar)
    }


    private var editorPage: some View {
        ScrollView(.vertical) {
            if let draft = session.draft {
                // 行距 7（D-17 的杠杆再收 1pt，2026-10-16）：+3 号字号 + 大文本框 2 行之后，
                // 待办表单刚好落进编辑档可视区（336），面板不再冒滚动条。
                VStack(alignment: .leading, spacing: 7) {
                    // 新建可点、编辑锁定（而不是不渲染）：四种入口的版式不再跳。
                    Picker("calendar.panel.kind", selection: kindBinding) {
                        Text("calendar.quickAdd.kindReminder").tag(CalendarDraft.Kind.reminder)
                        Text("calendar.quickAdd.kindEvent").tag(CalendarDraft.Kind.event)
                    }
                    .pickerStyle(.segmented).controlSize(.regular)
                    .disabled(draft.eventID != nil)
                    .accessibilityIdentifier("calendar-kind")
                    if draft.eventID == nil { generationControls(draft) }
                    fieldRow("calendar.panel.title") {
                        TextField("calendar.quickAdd.title", text: stringBinding(\.title), axis: .vertical)
                            .textFieldStyle(.roundedBorder).font(CalendarPanelTypography.fieldInput)
                            .focused($focusedField, equals: .title)
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
                            .font(CalendarPanelTypography.action).foregroundStyle(.secondary)
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
                                    .textFieldStyle(.roundedBorder).font(CalendarPanelTypography.fieldInput)
                                    .focused($focusedField, equals: .location)
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
                    if !hasAccess { Text("Calendar access is required.").font(CalendarPanelTypography.action).foregroundStyle(.secondary) }
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
            Text(label).font(CalendarPanelTypography.fieldLabel).foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 「链接」一格：日程的「地点｜链接」行与待办的「截止｜链接」行共用，避免两处漂移。
    private var urlField: some View {
        fieldRow("calendar.panel.url") {
            TextField("calendar.panel.url", text: urlBinding)
                .textFieldStyle(.roundedBorder).font(CalendarPanelTypography.fieldInput)
                .focused($focusedField, equals: .url)
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
            Text("calendar.generation.blocked").font(CalendarPanelTypography.action).foregroundStyle(.secondary)
                .accessibilityIdentifier("calendar-generation-blocked")
            if draft.generationMode != .required {
                ForEach(ScheduleConfirmation.allCases, id: \.rawValue) { item in
                    if draft.confirmations.contains(item) {
                        Button(LocalizedStringKey(item.labelKey)) { session.confirmSource(item) }
                            .font(CalendarPanelTypography.action).accessibilityIdentifier("calendar-generation-confirm-" + item.rawValue)
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
            Text(key).font(CalendarPanelTypography.fieldLabel).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button { datePopover = field } label: {
                    Label(CalendarPanelDates.formatted(date, allDay: true, calendar: calendar), systemImage: "calendar")
                        .font(CalendarPanelTypography.action)
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
                        .labelsHidden().controlSize(.regular)
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
                .font(CalendarPanelTypography.fieldLabel).foregroundStyle(.secondary)
            if targets.isEmpty {
                Text("No writable calendar is available.").font(CalendarPanelTypography.action).foregroundStyle(.secondary)
            } else {
                CalendarPanelTargetPicker(targets: targets, selection: Binding(
                    get: { session.draft?.calendarID }, set: { session.draft?.calendarID = $0 }
                ), session: session, ownerID: ownerID, lifecycle: lifecycle)
                .frame(height: 26).accessibilityIdentifier("calendar-target")
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
        if session.pendingConfirmation == nil {
            switch session.route {
            case .list: EmptyView()
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
                }.disabled(session.isSubmitting).font(CalendarPanelTypography.action).frame(height: 28)
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


    private func goBack() {
        if let source = session.back() { onReturnSource(source) }
    }

    private func escape() {
        // Esc 顺序（C2）：先收浮窗 / 确认条 → 再处理日期弹层与菜单 → 最后才返回上一页 / 收面板。
        if details.activeID != nil { details.clear() }
        else if deleteTargetID != nil { deleteTargetID = nil }
        else if datePopover != nil { datePopover = nil }
        else if session.pendingConfirmation != nil { session.dismissConfirmation() }
        else if session.route != .list { goBack() }
        else { vm.close() }
    }
}

/// 生成区主按钮的三种状态（设计图 C4 的「就绪 / 生成中 / 失败」；纯函数，便于钉住映射）。
/// 三态**共用同一枚按钮**、同一位置与尺寸，只换文案——不存在「按钮不见了」这一态。
enum CalendarGenerationPrimary: Equatable {
    case ready, busy, failed

    init(_ state: CalendarGenerationState) {
        switch state {
        case .parsing, .debouncing: self = .busy
        case .failed: self = .failed
        case .idle, .ready, .cancelled: self = .ready
        }
    }

    var labelKey: LocalizedStringKey {
        switch self {
        case .ready: "calendar.generation.generate"
        case .busy: "Cancel"
        case .failed: "calendar.generation.retry"
        }
    }

    var identifier: String {
        switch self {
        case .ready: "calendar-generation-generate"
        case .busy: "calendar-generation-cancel"
        case .failed: "calendar-generation-retry"
        }
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
            Text("calendar.generation.source").font(CalendarPanelTypography.fieldLabel).foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 8) {
                CalendarGrowingTextEditor(text: $sourceDraft, label: "calendar.generation.source", onFocus: onFocus)
                    .accessibilityIdentifier("calendar-generation-source")
                // 生成中的 mini 指示器（C4 ②）：槽位**恒定**占宽，按钮三态才不会左右挪。
                ProgressView().controlSize(.mini)
                    .opacity(CalendarGenerationPrimary(session.generationState) == .busy ? 1 : 0)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                generationPrimaryButton
                // AI 模型设置：从按钮降级为生成行右端的齿轮，文案复用既有键。
                Button { CalendarAISettingsNavigation.open() } label: { Image(systemName: "gearshape") }
                    .help(Text("calendar.generation.settings"))
                    .accessibilityLabel(Text("calendar.generation.settings"))
                    .accessibilityIdentifier("calendar-generation-settings")
            }
            if session.configuredAI == nil {
                Text("calendar.generation.unconfigured").font(CalendarPanelTypography.action).foregroundStyle(.secondary)
            }
            // 状态词不再单独占行：只有失败时留一行「生成失败：<原因>」+ 改为手工填写。
            // 重试就是上面那枚常驻按钮——不再有第二个重试入口（设计图 C4）。
            if session.generationState == .failed {
                HStack(spacing: 8) {
                    (Text("calendar.generation.state.failed") + Text(session.generationError.map { "：" + $0 } ?? ""))
                        .font(CalendarPanelTypography.action).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("calendar-generation-failed")
                    manualEntryButton
                }
            } else if session.draft?.generationMode == .required || session.generationState == .cancelled {
                manualEntryButton
            }
        }
    }

    /// 三态共用同一格、同一尺寸（76 × 26 的白 14% 圆角胶囊），只换文案——不存在「按钮不见了」这一态。
    private var generationPrimaryButton: some View {
        let primary = CalendarGenerationPrimary(session.generationState)
        // 只有生成中的「取消」可以无条件点：其余两态都要有原文（清空原文后的重试没有意义）。
        let enabled = primary == .busy || hasSource
        // 生成中比就绪态暗一档（设计图 C4 ②）：同一格里的「取消」不该看起来像主行动。
        let fillAlpha: Double = (primary == .busy || !enabled) ? 0.07 : 0.14
        let textAlpha: Double = primary == .busy ? 0.75 : (enabled ? 0.95 : 0.45)
        return Button { primaryAction(primary) } label: {
            Text(primary.labelKey)
                .font(CalendarPanelTypography.action).fontWeight(.semibold)
                .foregroundStyle(.white.opacity(textAlpha))
                .frame(width: 76, height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(fillAlpha)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityIdentifier(primary.identifier)
    }

    private func primaryAction(_ primary: CalendarGenerationPrimary) {
        switch primary {
        case .busy: session.cancelSourceParsing()
        case .ready, .failed: generate()
        }
    }

    /// 「改为手工填写」：浅底文字按钮（原来是一枚看不出能点的纯文字）。
    private var manualEntryButton: some View {
        Button { session.useManualEntry() } label: {
            Text("calendar.generation.manual")
                .font(CalendarPanelTypography.action)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("calendar-generation-manual")
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
        button.controlSize = .regular
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
