// Modified for Gourd (2026-10-11)
// Copyright (C) 2026 Gourd Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import SwiftUI

enum CalendarPanelSource: Equatable {
    case home(anchor: String?)
    case calendar(date: Date, anchor: String?)
}

enum CalendarPanelRoute: Equatable { case list, editor }
enum CalendarDraftConflictChoice { case resume, discardAndStart, cancel }
enum CalendarTerminationChoice { case save, discard, cancel }

enum CalendarGenerationMode: Equatable { case manual, required, ready }

enum CalendarGenerationState: Equatable {
    case idle, debouncing, parsing, ready, failed, cancelled
}

struct CalendarDraft: Equatable {
    enum Kind: Equatable { case event, reminder }

    var kind: Kind
    var eventID: String?
    var originalDate: Date
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String = ""
    var notes: String = ""
    var calendarID: String?
    var url: URL? = nil
    var timeZoneIdentifier: String? = nil

    var sourceText: String = ""
    var generationMode: CalendarGenerationMode = .manual
    var confirmations: Set<ScheduleConfirmation> = []

    func validateGeneration() throws {
        guard generationMode != .required, confirmations.isEmpty else { throw ScheduleParsingError.confirmationRequired }
    }

    func eventInput(calendar: Calendar = .current) throws -> CalendarEventInput {
        guard kind == .event else { throw CalendarMutationError.wrongRecordType }
        try validateGeneration()
        try validateTarget()
        return try CalendarEventInput(
            title: title, start: start, end: end, isAllDay: isAllDay,
            location: location.isEmpty ? nil : location, notes: notes.isEmpty ? nil : notes,
            calendarID: calendarID, url: url, timeZoneIdentifier: timeZoneIdentifier
        ).validated(calendar: calendar)
    }

    func reminderInput() throws -> CalendarReminderInput {
        guard kind == .reminder else { throw CalendarMutationError.wrongRecordType }
        try validateGeneration()
        try validateTarget()
        return CalendarReminderInput(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines), due: start, isAllDay: isAllDay,
            notes: notes.isEmpty ? nil : notes, url: url, listID: calendarID, timeZoneIdentifier: timeZoneIdentifier
        )
    }

    func validateTarget() throws {
        guard let calendarID, !calendarID.isEmpty else { throw CalendarMutationError.noWritableCalendar }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CalendarMutationError.invalidTitle }
    }
}

/// 每个窗口只贡献自己的输入 ownership；草稿及导航在整个进程内共享。
@MainActor
final class CalendarPanelSession: ObservableObject {
    static let shared = CalendarPanelSession(manager: .shared)

    enum Confirmation: Equatable { case discardDraft, draftConflict }

    /// 只有两种档位（T6 / D-11：详情档退休，详情内容改由列表行的浮层承担）。
    @Published private(set) var route: CalendarPanelRoute = .list {
        didSet { if oldValue != route { autoCloseProtectionRevision += 1 } }
    }
    /// **变更之后**才发的信号（`@Published` 是 willSet 发的，拿它重算会读到旧值）：
    /// 保护窗口（`shouldProtectAutoClose`）依赖 route / isSubmitting，宿主据此在**改完之后**重算，
    /// 否则「离开编辑档」那一下会读到旧的 `.editor`，保护永远撤不掉。
    @Published private(set) var autoCloseProtectionRevision: Int = 0
    @Published var selectedDate: Date {
        didSet { if oldValue != selectedDate { navigationGeneration += 1 } }
    }
    @Published private(set) var returnSource: CalendarPanelSource
    @Published var calendarScrollAnchor: String?
    @Published var homeScrollAnchor: String?
    @Published var draft: CalendarDraft? {
        didSet {
            if !applyingCandidate, oldValue != nil, draft != nil, oldValue?.notes != draft?.notes { notesWereEdited = true }
            if oldValue?.sourceText != draft?.sourceText, draft != nil,
               oldValue != nil || draft?.sourceText.isEmpty == false { sourceDidChange() }
        }
    }
    @Published private(set) var generationState: CalendarGenerationState = .idle
    @Published private(set) var generationError: String?
    @Published private(set) var baseline: CalendarDraft?
    @Published private(set) var isSubmitting = false {
        didSet { if oldValue != isSubmitting { autoCloseProtectionRevision += 1 } }
    }
    @Published private(set) var error: String?
    /// 首页只展示本次完成动作的错误，不能读到先前保存草稿的错误。
    @Published private(set) var completionError: String?
    @Published private(set) var pendingConfirmation: Confirmation?
    @Published private(set) var editorHasFocus = false
    @Published private(set) var ownedMenuCount = 0
    @Published private(set) var datePopoverPresented = false

    var hasDirtyDraft: Bool { draft != nil && draft != baseline }
    /// 当前稿的身份（`draftID` 的只读映射）。
    ///
    /// 编辑页把它用在不换稿时会失效的路径上做**二次保险**：真正的权威机制是「编辑页子树被卸载」
    /// ——`pendingConfirmation != nil` 时 body 走别的分支、`suspend()` 把 route 切走，两者都会
    /// 丢掉输入框的本地 `@State`。今天不存在「不卸载编辑页的同 route 换稿」路径（见
    /// `testDraftSwapsNeverChangeIdentityWhileTheEditorSubtreeStaysMounted`），所以 `.id` 尚未被独立验证。
    var draftIdentity: UUID? { draftID }
    /// 面板**不该自动收起**的判据（宿主 `ContentView` 的收面板决策 + `CalendarEditorLifecycle`
    /// 经 `vm.setAutoCloseSuppression` 接进 `vm.isAutoCloseSuppressed`）。
    ///
    /// 2026-10-16（用户）：**编辑 / 新增档整个期间都抑制自动收起**——鼠标移出面板不再把正在写的稿收走；
    /// 离开编辑档只有用户动作：点「保存」/「取消」（或 Esc、点面板外、切页）。
    /// 改前只在「输入框有焦点 / 有菜单元 / 日期弹层开着」时抑制，鼠标一移开就可能被收走。
    /// 注：列表档的**详情浮窗**不在此列（D-23：浮窗随面板一起关，不扣住面板）。
    var shouldProtectAutoClose: Bool {
        isSubmitting || route == .editor
    }

    private struct DraftContext {
        /// 只记「来源」——详情档退休后，编辑档的唯一归宿就是列表（T6）。
        var source: CalendarPanelSource
    }
    private struct PendingDraft {
        var draft: CalendarDraft
        var context: DraftContext
    }
    private struct Ownership {
        var focused = false
        var menuCount = 0
        var popover = false
    }

    private let calendar: Calendar
    private let now: () -> Date
    private let saveEventRecord: (CalendarEventInput, String?) async throws -> EventModel
    private let createReminderRecord: (CalendarReminderInput) async throws -> EventModel
    private let deleteEventRecord: (String) async throws -> Void
    /// 待办删除（C2 / D-10：列表行对**可写待办**也给 🗑）。服务层的能力是分开的
    /// （`deleteEvent` 只吃 EKEvent），所以这里也分开注入；nil = 该宿主不支持删待办。
    private let deleteReminderRecord: ((String) async throws -> Void)?
    private let completeReminderRecord: (String, Bool) async throws -> EventModel
    private let readEvent: (String) -> EventModel?
    private let openSystemEvent: (EventModel) -> Void
    private var draftContext: DraftContext?
    private var pendingDraft: PendingDraft?
    private var draftID: UUID?
    private var draftError: String?
    private var navigationGeneration = 0
    private var ownership: [UUID: Ownership] = [:]
    private var submission: Task<Bool, Never>?
    private var submissionID: UUID?
    private var termination: Task<Bool, Never>?
    private var applyingCandidate = false
    private var notesWereEdited = false
    private var ai: (any AIHandle)?
    private var sourceRevision = 0
    private struct SourceReferenceContext {
        let date: Date
        let timeZone: TimeZone
    }
    // Relative dates use this revision's reference zone, never a merged candidate's
    // source zone. Keep the instant and zone together through retries and cancellation.
    private var sourceReferenceContext: SourceReferenceContext?
    private var parsingTask: Task<ScheduleCandidate, Error>?
    private var parsingID: UUID?

    /// Composition root supplies the same handle to every shared-session consumer.
    func configureAI(_ ai: any AIHandle) { self.ai = ai }

    /// Read-only access to the module-injected handle; meeting UI must use this same object.
    var configuredAI: (any AIHandle)? { ai }

    func updateSourceText(_ text: String) { draft?.sourceText = text }

    /// 显式「生成」的同步前半段：写回视图本地原文并**立刻**进入 `.parsing`。
    /// 写回原文本身会经草稿 didSet 触发 `sourceDidChange()` 把状态打到 `.debouncing`——那是
    /// 「输入已失效、等待重新生成」的中间档；这里随即覆盖成 `.parsing`，本次生成不留这一帧，
    /// 生成按钮因此只从「生成」切到取消态一次。
    /// 解析本身仍由随后的 `generateDraft()`（内部走 `parseSource`）完成。
    func commitSourceForGeneration(_ text: String) {
        guard draft != nil else { return }
        updateSourceText(text)
        generationState = .parsing
    }

    /// 显式「生成」：视图已把本地输入写回草稿，这里只触发这一次解析。
    /// 过期防护仍由 `parseSource` 的 `sourceRevision` / `parsingID` 与草稿合并口径负责，本方法不做任何调度。
    func generateDraft() async { await parseSource() }

    private func sourceDidChange() {
        sourceRevision += 1
        sourceReferenceContext = nil
        parsingTask?.cancel()
        parsingTask = nil
        parsingID = nil
        draft?.generationMode = .required
        draft?.confirmations = Set(ScheduleConfirmation.allCases)
        generationState = .debouncing
        generationError = nil
    }

    /// T7 owns debounce scheduling; invalidation has already happened synchronously on input.
    func parseSource() async {
        guard let ai else {
            generationState = .failed
            generationError = AIError.missingDefault(.text).localizedDescription
            return
        }
        await parseSource(using: ScheduleParsing(ai: ai))
    }

    func parseSource(using parser: any ScheduleParser) async {
        guard !isSubmitting, let snapshot = draft, let id = draftID else { return }
        parsingTask?.cancel()
        let requestID = UUID()
        let revision = sourceRevision
        let reference = sourceReferenceContext ?? SourceReferenceContext(
            date: now(),
            timeZone: TimeZone(identifier: snapshot.timeZoneIdentifier ?? calendar.timeZone.identifier) ?? calendar.timeZone
        )
        sourceReferenceContext = reference
        parsingID = requestID
        draft?.generationMode = .required
        draft?.confirmations = Set(ScheduleConfirmation.allCases)
        generationState = .parsing
        generationError = nil
        let task = Task { try await parser.parse(text: snapshot.sourceText, referenceDate: reference.date, timeZone: reference.timeZone) }
        parsingTask = task
        do {
            let candidate = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard draftID == id, sourceRevision == revision, parsingID == requestID, var current = draft else { return }
            if Task.isCancelled || task.isCancelled {
                generationState = .cancelled
                parsingTask = nil
                parsingID = nil
                return
            }
            if current.title == snapshot.title { current.title = candidate.title }
            if current.start == snapshot.start {
                if let start = candidate.start { current.start = start }
                else if let day = candidate.date {
                    let sourceCalendar = try CalendarRecordDates.calendar(timeZoneIdentifier: candidate.timeZoneIdentifier, fallback: calendar)
                    let clock = sourceCalendar.dateComponents([.hour, .minute, .second], from: current.start)
                    current.start = sourceCalendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: clock.second ?? 0, of: day) ?? current.start
                }
            }
            if current.end == snapshot.end {
                if let end = candidate.end { current.end = end }
                else if candidate.date != nil, candidate.start == nil {
                    // Preserve the manual duration while moving only the date hint; time still needs confirmation.
                    current.end = current.start.addingTimeInterval(snapshot.end.timeIntervalSince(snapshot.start))
                }
            }
            if current.isAllDay == snapshot.isAllDay { current.isAllDay = candidate.isAllDay }
            if current.location == snapshot.location { current.location = candidate.location }
            if !notesWereEdited, current.notes == snapshot.notes {
                current.notes = [candidate.notes, snapshot.sourceText].filter { !$0.isEmpty }.joined(separator: "\n\n")
            }
            if current.url == snapshot.url { current.url = candidate.url }
            if current.timeZoneIdentifier == snapshot.timeZoneIdentifier { current.timeZoneIdentifier = candidate.timeZoneIdentifier }
            current.confirmations = candidate.confirmations
            if current.start != snapshot.start && candidate.start != current.start {
                current.confirmations.formUnion([.date, .time])
            }
            if current.end != snapshot.end && candidate.end != current.end { current.confirmations.insert(.time) }
            if current.isAllDay != snapshot.isAllDay && candidate.isAllDay != current.isAllDay { current.confirmations.insert(.time) }
            if current.timeZoneIdentifier != snapshot.timeZoneIdentifier && current.timeZoneIdentifier != candidate.timeZoneIdentifier {
                current.confirmations.formUnion([.date, .time])
            }
            current.generationMode = .ready
            applyingCandidate = true
            draft = current
            applyingCandidate = false
            generationState = .ready
            generationError = nil
        } catch {
            guard draftID == id, sourceRevision == revision, parsingID == requestID else { return }
            generationState = task.isCancelled || Task.isCancelled ? .cancelled : .failed
            // Do not surface arbitrary parser/provider text containing source data.
            generationError = (error as? AIError)?.localizedDescription ?? (error as? ScheduleParsingError)?.localizedDescription ?? ScheduleParsingError.failed.localizedDescription
        }
        if parsingID == requestID { parsingTask = nil; parsingID = nil }
    }

    func cancelSourceParsing() {
        parsingTask?.cancel()
        parsingTask = nil
        parsingID = nil
        if draft?.generationMode != .manual {
            draft?.generationMode = .required
            draft?.confirmations = Set(ScheduleConfirmation.allCases)
        }
        generationState = .cancelled
        generationError = nil
    }

    /// Explicit manual fallback still requires acknowledgment of current date and time.
    func useManualEntry() {
        cancelSourceParsing()
        draft?.generationMode = .manual
        draft?.confirmations = Set(ScheduleConfirmation.allCases)
        generationState = .idle
    }

    func confirmSource(_ item: ScheduleConfirmation) {
        guard draft?.generationMode != .required else { return }
        draft?.confirmations.remove(item)
    }

    init(
        selectedDate: Date = Date(), calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init,
        saveEvent: @escaping (CalendarEventInput, String?) async throws -> EventModel,
        createReminder: @escaping (CalendarReminderInput) async throws -> EventModel,
        deleteEvent: @escaping (String) async throws -> Void,
        completeReminder: @escaping (String, Bool) async throws -> EventModel,
        event: @escaping (String) -> EventModel?,
        deleteReminder: ((String) async throws -> Void)? = nil,
        openSystemEvent: @escaping (EventModel) -> Void = { _ in }
    ) {
        self.selectedDate = calendar.startOfDay(for: selectedDate)
        returnSource = .calendar(date: calendar.startOfDay(for: selectedDate), anchor: nil)
        self.calendar = calendar
        self.now = now
        saveEventRecord = saveEvent
        createReminderRecord = createReminder
        deleteEventRecord = deleteEvent
        deleteReminderRecord = deleteReminder
        completeReminderRecord = completeReminder
        readEvent = event
        self.openSystemEvent = openSystemEvent
    }

    /// Compatibility for existing manual callers; rich drafts must use the input closure.
    convenience init(
        selectedDate: Date = Date(), calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init,
        saveEvent: @escaping (CalendarEventInput, String?) async throws -> EventModel,
        createReminder: @escaping (String, Date, String?) async throws -> EventModel,
        deleteEvent: @escaping (String) async throws -> Void,
        completeReminder: @escaping (String, Bool) async throws -> EventModel,
        event: @escaping (String) -> EventModel?,
        deleteReminder: ((String) async throws -> Void)? = nil,
        openSystemEvent: @escaping (EventModel) -> Void = { _ in }
    ) {
        self.init(
            selectedDate: selectedDate, calendar: calendar, now: now, saveEvent: saveEvent,
            createReminder: { input in
                let arguments = try input.legacyArguments()
                return try await createReminder(arguments.title, arguments.due, arguments.listID)
            },
            deleteEvent: deleteEvent, completeReminder: completeReminder, event: event,
            deleteReminder: deleteReminder, openSystemEvent: openSystemEvent
        )
    }

    convenience init(manager: CalendarManager) {
        self.init(
            selectedDate: manager.currentWeekStartDate,
            saveEvent: { try await manager.saveEvent(input: $0, eventID: $1) },
            createReminder: { try await manager.createReminderRecord(input: $0) },
            deleteEvent: { try await manager.deleteEvent(id: $0) },
            completeReminder: { try await manager.completeReminder(id: $0, completed: $1) },
            event: { manager.event(withID: $0) },
            deleteReminder: { try await manager.deleteReminder(id: $0) },
            openSystemEvent: { CalendarInteractionFixtures.openSystemEvent($0) }
        )
    }

    func setEditorFocus(_ focused: Bool, ownerID: UUID) {
        ownership[ownerID, default: Ownership()].focused = focused
        publishOwnership()
    }

    func setOwnedMenuCount(_ count: Int, ownerID: UUID) {
        ownership[ownerID, default: Ownership()].menuCount = max(0, count)
        publishOwnership()
    }

    func setDatePopoverPresented(_ presented: Bool, ownerID: UUID) {
        ownership[ownerID, default: Ownership()].popover = presented
        publishOwnership()
    }

    func clearOwnership(_ ownerID: UUID) {
        ownership.removeValue(forKey: ownerID)
        publishOwnership()
    }

    private func publishOwnership() {
        let focused = ownership.values.contains(where: \.focused)
        let menuCount = ownership.values.reduce(0) { $0 + $1.menuCount }
        let popoverPresented = ownership.values.contains(where: \.popover)
        if editorHasFocus != focused { editorHasFocus = focused }
        if ownedMenuCount != menuCount { ownedMenuCount = menuCount }
        if datePopoverPresented != popoverPresented { datePopoverPresented = popoverPresented }
    }

    private func changeNavigation() {
        navigationGeneration += 1
        ownership.removeAll()
        publishOwnership()
        error = nil
        pendingConfirmation = nil
        pendingDraft = nil
    }

    private func applySource(_ source: CalendarPanelSource) {
        returnSource = source
        switch source {
        case .home(let anchor): homeScrollAnchor = anchor
        case .calendar(let date, let anchor):
            selectedDate = calendar.startOfDay(for: date)
            calendarScrollAnchor = anchor
        }
    }

    /// 回列表档（左栏「回到月历」与月历网格选日都走它）。
    ///
    /// 进入前先 `dropCleanDraft()`（docs/49 D-39）：没改过的稿不留在会话里——否则列表档顶部会
    /// 冒出一行「有未保存的日程 · 继续编辑」的假提示（那行只看 `draft != nil`）。
    func showList(on date: Date, anchor: String? = nil) {
        dropCleanDraft()
        changeNavigation()
        applySource(.calendar(date: date, anchor: anchor))
        route = .list
    }

    /// - Parameter source: **入口来源**（2026-10-27 用户要求「从首页进的添加 / 编辑，返回也回首页」）。
    ///   缺省 `nil` = 按面板现状推（列表档 = `.calendar`，行为与加参数前逐字一致——日历面板自己的
    ///   入口与既有用例都不用改）；首页的入口传 `.home(anchor:)`，返回链（`back()` 把来源交回
    ///   `onReturnSource`）就会把面板切回首页、并把锚点还给待办块的滚动位。
    func beginCreate(kind: CalendarDraft.Kind, on date: Date, calendarID: String?,
                     source: CalendarPanelSource? = nil) {
        let day = calendar.startOfDay(for: date)
        let start = kind == .event ? CalendarQuickAdd.defaultStart(on: day, now: now(), calendar: calendar) : day
        let end = kind == .event ? CalendarQuickAdd.defaultEnd(start: start) : calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let newDraft = CalendarDraft(
            kind: kind, eventID: nil, originalDate: day, title: "", start: start, end: end,
            isAllDay: kind == .reminder, calendarID: calendarID
        )
        requestDraft(newDraft, context: currentContext(override: source))
    }

    /// - Parameter source: 入口来源，语义同 `beginCreate(kind:on:calendarID:source:)` 的那条。
    func beginEdit(_ event: EventModel, source: CalendarPanelSource? = nil) {
        guard event.canModifyInIsland else {
            error = event.modificationRestriction?.localizedDescription
            return
        }
        if draft?.eventID == event.id { resumeDraft(); return }
        let newDraft = CalendarDraft(
            kind: .event, eventID: event.id, originalDate: event.start, title: event.title,
            start: event.start, end: event.end, isAllDay: event.isAllDay,
            location: event.location ?? "", notes: event.notes ?? "", calendarID: event.calendar.id,
            url: event.url, timeZoneIdentifier: event.timeZone?.identifier
        )
        requestDraft(newDraft, context: currentContext(override: source))
    }

    private func currentContext(override: CalendarPanelSource? = nil) -> DraftContext {
        let source: CalendarPanelSource = override ?? (route == .list
            ? .calendar(date: selectedDate, anchor: calendarScrollAnchor) : returnSource)
        return DraftContext(source: source)
    }

    private func requestDraft(_ newDraft: CalendarDraft, context: DraftContext) {
        // **只有「有未保存改动」的稿才拦人**（2026-10-16 上屏反馈：点左栏另一条时，明明一个字没改
        // 也弹「已有未保存草稿。继续旧稿，或放弃旧稿后开始此事项？」——那是把「存在稿」当成了「有改动」）。
        // 稿与基线一致时直接换：丢掉它不损失任何用户输入（「改过」的口径见 `hasDirtyDraft`）。
        guard let existing = draft, existing != baseline else {
            installDraft(newDraft, context: context)
            return
        }
        pendingDraft = PendingDraft(draft: newDraft, context: context)
        pendingConfirmation = .draftConflict
    }

    private func installDraft(_ newDraft: CalendarDraft, context: DraftContext) {
        changeNavigation()
        notesWereEdited = false
        draftID = UUID()
        draft = newDraft
        baseline = newDraft
        generationState = .idle
        generationError = nil
        sourceReferenceContext = nil
        draftContext = context
        draftError = nil
        returnSource = context.source
        route = .editor
    }

    func resolveDraftConflict(_ choice: CalendarDraftConflictChoice) {
        guard pendingConfirmation == .draftConflict, let pending = pendingDraft else { return }
        pendingDraft = nil
        pendingConfirmation = nil
        switch choice {
        case .resume: resumeDraft()
        case .discardAndStart:
            clearDraft()
            installDraft(pending.draft, context: pending.context)
        case .cancel: break
        }
    }

    /// 编辑档当前稿的返回目标是不是**首页**（视图据此换左栏按钮的文案与出口；
    /// 来源语义见 `beginCreate(kind:on:calendarID:source:)`）。没有稿（列表档）恒为 `false`。
    var editorReturnsHome: Bool {
        if case .home = draftContext?.source { return true }
        return false
    }

    /// **保存出口**要不要「回家」（2026-10-27 用户反馈「添加完保存还是回到日历面板」）：
    /// 视图在 `await save()` 返回后读一次——保存成功且档已退到列表、来源是首页 → `true`
    ///（保存成功那一刻 `returnSource` 已写回来源，`draftContext` 已清空，所以这里读的是它）；
    /// 保存失败 / 提交期间又敲了字（档还留在编辑档）/ 日历面板自己的入口 → `false`。
    var shouldReturnHomeAfterSave: Bool {
        guard route == .list else { return false }
        if case .home = returnSource { return true }
        return false
    }

    /// 退出编辑档：回列表（详情档退休后这是唯一归宿），并把来源交回调用方。
    @discardableResult
    func back() -> CalendarPanelSource? {
        guard route == .editor, let context = draftContext else { return nil }
        dropCleanDraft()
        changeNavigation()
        route = .list
        applySource(context.source)
        return context.source
    }

    func suspend() {
        dropCleanDraft()
        changeNavigation()
        route = .list
    }

    /// **离开编辑档时，没改过的稿直接丢掉**（docs/49 D-39，2026-10-16 用户第二轮反馈：
    /// 「打开一个日程编辑，不改动任何内容，点击回到月历，会显示存在一条草稿」）。
    ///
    /// 判据与「拦人」那一处**同源**（`hasDirtyDraft` = `draft != baseline`，D-36）：稿与基线一致
    /// 时丢掉它不损失任何用户输入——留在会话里只会让列表档顶部冒出一行**假提示**
    ///（「有未保存的日程 · 继续编辑」，那行只看 `draft != nil`）。
    /// **改过的稿照旧留着**：那是用户真敲进去的东西，回来还能接着写（`resumeDraft()` 那条路）。
    ///
    /// 三个出口（顶部返回 `back()` / 左栏「回到月历」`showList(on:)` / 面板收起 `suspend()`）都调它；
    /// **刻意不放进 `changeNavigation()`**——`resumeDraft()` 也走那个函数（它先把 route 切回编辑档），
    /// 在那里丢掉「干净的稿」会让编辑档开成一张空表单。
    private func dropCleanDraft() {
        guard draft != nil, !hasDirtyDraft else { return }
        clearDraft()
    }

    func resumeDraft() {
        guard draft != nil, let context = draftContext else { return }
        changeNavigation()
        route = .editor
        returnSource = context.source
        error = draftError
    }

    func requestCancel() {
        guard !isSubmitting else { return }
        if hasDirtyDraft { pendingConfirmation = .discardDraft }
        else { discardDraft() }
    }

    func dismissConfirmation() {
        pendingConfirmation = nil
        pendingDraft = nil
    }

    func discardDraft() {
        if route == .editor { _ = back() }
        else { changeNavigation() }
        clearDraft()
    }

    private func clearDraft() {
        parsingTask?.cancel()
        parsingTask = nil
        parsingID = nil
        sourceRevision += 1
        sourceReferenceContext = nil
        generationState = .idle
        generationError = nil
        notesWereEdited = false
        draft = nil
        baseline = nil
        draftID = nil
        draftContext = nil
        draftError = nil
    }

    func openInSystemApp(_ event: EventModel) {
        openSystemEvent(event)
    }

    func save() async -> Bool {
        guard !isSubmitting, let submitted = draft, let id = draftID else { return false }
        if submitted.kind == .reminder, submitted.eventID != nil {
            error = String(localized: "Edit saved reminders in the system app.")
            draftError = error
            return false
        }
        do {
            try submitted.validateGeneration()
            try submitted.validateTarget()
            if submitted.kind == .event { _ = try submitted.eventInput(calendar: calendar) }
            else { _ = try submitted.reminderInput().dueDateComponents(calendar: calendar) }
        } catch {
            self.error = error.localizedDescription
            draftError = self.error
            return false
        }
        let generation = navigationGeneration
        let context = draftContext
        return await submit {
            do {
                let saved: EventModel
                if submitted.kind == .event {
                    saved = try await self.saveEventRecord(try submitted.eventInput(calendar: self.calendar), submitted.eventID)
                } else {
                    saved = try await self.createReminderRecord(try submitted.reminderInput())
                }
                let unchangedDraft = self.draftID == id && self.draft == submitted
                if unchangedDraft { self.clearDraft() }
                else if self.draftID == id {
                    var savedBaseline = submitted
                    // 新建已成功时，后续输入必须继续指向真实记录，不能再次新建同一项。
                    savedBaseline.eventID = saved.id
                    self.draft?.eventID = saved.id
                    self.baseline = savedBaseline
                    self.draftError = nil
                }
                // 用户已恢复同一份稿时允许展示其保存结果；其他新页面仍由代数隔离。
                if unchangedDraft && (self.navigationGeneration == generation || self.route == .editor) {
                    // 保存成功后回**列表**（T6：详情档不存在了）。
                    self.route = .list
                    if let context { self.returnSource = context.source }
                    self.error = nil
                    self.ownership.removeAll()
                    self.publishOwnership()
                }
                return true
            } catch {
                if self.draftID == id { self.draftError = error.localizedDescription }
                if self.navigationGeneration == generation || (self.draftID == id && self.route == .editor) {
                    self.error = error.localizedDescription
                }
                return false
            }
        }
    }

    /// 岛内**可删**判据：可写日程走 `canModifyInIsland`；可写待办走 `canCompleteReminderInIsland`
    /// （`canModifyInIsland` 对提醒恒 false——它的语义是「岛内可编辑」）。两处行内按钮与会话层共用它。
    ///
    /// **重复记录一律不给删**（与日程那条「重复日程交给系统应用维护」同一条边界，docs/39 D-03）：
    /// 提醒在 EventKit 里删的是**整串**（没有 `span` 可选），岛内不提供这种不可细分的破坏性动作。
    static func canDeleteInIsland(_ event: EventModel) -> Bool {
        guard !event.hasRecurrenceRules else { return false }
        return event.canModifyInIsland || event.canCompleteReminderInIsland
    }

    /// 删除记录（**列表档行内 🗑 与详情档共用这一条**）：唯一判据是 `CanDeleteInIsland`。
    ///
    /// 改前首行 guard 是 `route == .detail`——列表档的删除因此在会话层直接返回 false（用户报的
    /// 「行内删除点了没反应」类问题的根）；判据也已从 `canModifyInIsland` 换成 `canDeleteInIsland`
    /// （后者含可写待办）。删除后面板**停在列表**（C2）。
    func delete(_ event: EventModel) async -> Bool {
        guard !isSubmitting, Self.canDeleteInIsland(event) else { return false }
        let generation = navigationGeneration
        let writer: (String) async throws -> Void
        if event.type.isReminder {
            guard let deleteReminderRecord else { return false }
            writer = deleteReminderRecord
        } else {
            writer = deleteEventRecord
        }
        return await submit {
            do {
                try await writer(event.id)
                _ = generation
                return true
            } catch {
                if self.navigationGeneration == generation { self.error = error.localizedDescription }
                return false
            }
        }
    }

    func complete(_ event: EventModel, completed: Bool) async -> Bool {
        guard !isSubmitting else { return false }
        completionError = nil
        guard event.canCompleteReminderInIsland else {
            completionError = (event.calendar.allowsContentModifications ? CalendarMutationError.wrongRecordType : .readOnlyCalendar).localizedDescription
            return false
        }
        let generation = navigationGeneration
        return await submit {
            do {
                _ = try await self.completeReminderRecord(event.id, completed)
                _ = generation
                return true
            } catch {
                self.completionError = error.localizedDescription
                if self.navigationGeneration == generation { self.error = error.localizedDescription }
                return false
            }
        }
    }

    private func submit(_ operation: @escaping () async -> Bool) async -> Bool {
        guard submission == nil else { return false }
        error = nil
        isSubmitting = true
        let id = UUID()
        let task = Task { await operation() }
        submissionID = id
        submission = task
        let result = await task.value
        finishSubmission(id: id)
        return result
    }

    private func finishSubmission(id: UUID) {
        guard submissionID == id else { return }
        submission = nil
        submissionID = nil
        isSubmitting = false
    }

    func waitForSubmission() async -> Bool {
        guard let submission, let id = submissionID else { return true }
        let result = await submission.value
        finishSubmission(id: id)
        return result
    }

    func resolveTermination(_ choice: CalendarTerminationChoice) async -> Bool {
        if case .cancel = choice { return false }
        // 同时到达的退出请求复用首个裁决，避免等待后分别再次保存同一稿。
        if let termination { return await termination.value }
        let task = Task { await self.finishTermination(choice) }
        termination = task
        let result = await task.value
        termination = nil
        return result
    }

    private func finishTermination(_ choice: CalendarTerminationChoice) async -> Bool {
        while isSubmitting {
            guard await waitForSubmission() else { return false }
        }
        switch choice {
        case .save:
            // 既有任务可能只是完成提醒，或只保存了较早输入；成功不代表剩余稿已保存。
            while hasDirtyDraft {
                guard await save() else { return false }
            }
            return true
        case .discard: discardDraft(); return true
        case .cancel: return false
        }
    }
}

/// Only source revisions schedule parsing. Injectable delay keeps tests off the host UI and network.
@MainActor
final class CalendarSourceDebouncer: ObservableObject {
    private let delay: () async throws -> Void
    private var task: Task<Void, Never>?
    private var revision = 0

    init(delay: @escaping () async throws -> Void = { try await Task.sleep(for: .milliseconds(800)) }) {
        self.delay = delay
    }

    func schedule(session: CalendarPanelSession, parse: (() async -> Void)? = nil) {
        cancel()
        guard session.generationState == .debouncing,
              let source = session.draft?.sourceText, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let current = revision
        task = Task { [weak self, weak session] in
            guard let self, let session else { return }
            do { try await self.delay() } catch { return }
            guard !Task.isCancelled, self.revision == current, session.draft?.sourceText == source,
                  session.generationState == .debouncing else { return }
            if let parse { await parse() } else { await session.parseSource() }
        }
    }

    func cancel() {
        revision += 1
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}
