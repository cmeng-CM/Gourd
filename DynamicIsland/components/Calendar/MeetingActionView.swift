// Copyright (C) 2026 Gourd Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Defaults
import SwiftUI

private struct CalendarMeetingSessionKey: EnvironmentKey {
    static let defaultValue: CalendarPanelSession? = nil
}

extension EnvironmentValues {
    var calendarMeetingSession: CalendarPanelSession? {
        get { self[CalendarMeetingSessionKey.self] }
        set { self[CalendarMeetingSessionKey.self] = newValue }
    }
}

/// Original record evidence and optional start; visibility is independent of calendar navigation.
struct CalendarMeetingSource: Equatable {
    let recordID: String
    let textFields: [String]
    let structuredURLs: [URL]
    let start: Date?

    init(event: EventModel, url: URL? = nil) {
        recordID = event.id
        textFields = [event.title, event.location, event.notes].compactMap { $0 }
        structuredURLs = [url, event.url, event.conferenceURL].compactMap { $0 }
        start = event.start == .distantFuture ? nil : event.start
    }

    init(item: TodoBucketing.Item) {
        recordID = item.id
        textFields = [item.title]
        structuredURLs = []
        start = item.dueDate
    }

    var text: String { (textFields + structuredURLs.map(\.absoluteString)).joined(separator: "\n") }
    var targets: [MeetingJoinTarget] {
        CalendarMeetingEvidence.resolve(textFields: textFields, structuredURLs: structuredURLs)
    }
    var identity: [String] {
        [recordID, start.map { String($0.timeIntervalSince1970) } ?? ""] + textFields + structuredURLs.map(\.absoluteString)
    }
    var hasMeetingInformation: Bool {
        if !targets.isEmpty { return true }
        // Exclude known place/material nouns, while allowing invitation follow-up actions.
        let hints = #"(?i)(会议邀请(?=$|[\s\p{P}])|会议(?:主题|链接)\s*[:：]|邀请[^\n]{0,40}(?:参加|加入)[^\n]{0,15}会议(?!室|记录|材料|纪要|资料|文档)|(?:请|欢迎)[^\n]{0,20}(?:参加|加入)[^\n]{0,20}会议(?!室|记录|材料|纪要|资料|文档)|\b(?:meeting|conference)\s+invit(?:ation|e)\b|\b(?:join|invited)\b[^\n]{0,40}\b(?:meeting|conference)\b(?![\s-]+(?:rooms?|notes|minutes|materials|documents)\b))"#
        return textFields.contains { $0.range(of: hints, options: .regularExpression) != nil }
    }
}

/// 一次点击的结果状态（docs/47 §接口与数据形状）。
///
/// 只由图标自身表达（D-10）——面板与首页那一行高度固定，塞不下状态文字，原因留给 tooltip。
enum MeetingActionFeedback: Equatable { case idle, opening, opened, copied, failed }

/// 点击一下要执行的动作（D-01）：打开一个候选、复制会议号，或没有可信动作。
///
/// `open` 的 `MeetingJoinTarget` 既可能是带链接的候选，也可能是「只有会议号」的兜底候选
/// （`provider == nil`、`canOpen == false`）——后者的打开由 `MeetingJoinURLBuilder` 按号码拼深链。
enum MeetingPrimaryAction: Equatable {
    case open(MeetingJoinTarget, MeetingProvider)
    case copyCode(String)
    case none
}

/// 状态到 SF Symbol 的纯映射（D-10）。
enum MeetingActionGlyph {
    static func symbol(for feedback: MeetingActionFeedback) -> String {
        switch feedback {
        case .idle: return "video.fill"
        case .opening: return "arrow.triangle.2.circlepath"
        case .opened: return "checkmark"
        case .copied: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

/// An injected, offline-testable action controller. Recognition never opens a candidate.
@MainActor
final class MeetingActionModel: ObservableObject {
    @Published private(set) var targets: [MeetingJoinTarget]
    @Published private(set) var isOpening = false
    @Published private(set) var feedback: MeetingActionFeedback = .idle
    private let source: String
    /// 记录的开始时间与时钟：时间闸门已按 docs/47 D-02 删除，二者仅作为模型输入保留（对外签名不变）。
    private let start: Date?
    private let session: CalendarPanelSession
    private let opening: MeetingOpening
    private let now: () -> Date
    private let copyText: (String) -> Void
    private var task: Task<Void, Never>?
    private var revision = 0

    /// 成功状态自动回 idle 的停留时长（docs/47 §做法 3「瞬时状态」）。
    static let feedbackDwell: Duration = .seconds(1.5)

    convenience init(event: EventModel, url: URL? = nil, session: CalendarPanelSession,
                     opener: (any MeetingURLOpening)? = nil, now: @escaping () -> Date = Date.init,
                     copyText: @escaping (String) -> Void = {
                         NSPasteboard.general.clearContents()
                         NSPasteboard.general.setString($0, forType: .string)
                     }) {
        self.init(source: CalendarMeetingSource(event: event, url: url), session: session,
                  opener: opener, now: now, copyText: copyText)
    }

    init(source: CalendarMeetingSource, session: CalendarPanelSession,
         opener: (any MeetingURLOpening)? = nil, now: @escaping () -> Date = Date.init,
         copyText: @escaping (String) -> Void = {
             NSPasteboard.general.clearContents()
             NSPasteboard.general.setString($0, forType: .string)
         }) {
        self.session = session
        self.start = source.start
        self.now = now
        self.copyText = copyText
        opening = MeetingOpening(opener: opener)
        self.source = source.text
        targets = source.targets
    }

    var hasSource: Bool { !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isBusy: Bool { isOpening }

    /// 用户为「只有会议号」的邀请选过的客户端（D-09），存 `Defaults[.meetingCodeOpener]`。
    var rememberedProvider: MeetingProvider? {
        Defaults[.meetingCodeOpener].flatMap(MeetingProvider.init(rawValue:))
    }

    /// 点击一下要执行的动作（D-01）。
    ///
    /// 有可打开候选就打开；只有会议号时，记住过客户端就按号码打开、否则复制号码；都没有则不臆造动作。
    /// 未判定平台时不得凭猜选客户端（`MeetingJoinURLBuilder.url(provider:...)` 不复核号码归属），
    /// 这类候选退到纯号码分支。
    var primary: MeetingPrimaryAction {
        if let target = targets.first(where: \.canOpen),
           let provider = target.provider ?? rememberedProvider {
            return .open(target, provider)
        }
        guard let target = targets.first(where: { !$0.meetingCodes.isEmpty }),
              let number = Self.number(in: target) else { return .none }
        if let provider = rememberedProvider { return .open(target, provider) }
        return .copyCode(number)
    }

    /// 按号码打开时使用的入会显示名（D-08）：macOS 用户名，空或全空白（含 U+00A0）回落 `Gourd`。
    static func resolvedDisplayName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? MeetingJoinURLBuilder.fallbackDisplayName : trimmed
    }

    /// 打开的入口一：带链接的候选（保留）。
    func open(_ target: MeetingJoinTarget) {
        guard !isBusy, target.canOpen, targets.contains(target) else { return }
        performOpen(target: target, provider: target.provider ?? rememberedProvider)
    }

    /// 打开的入口二：只有会议号时按平台拼深链，并**记住**这个客户端（D-09）供下次主动作直接用。
    func openByNumber(provider: MeetingProvider) {
        guard !isBusy, let target = targets.first(where: { !$0.meetingCodes.isEmpty }) else { return }
        Defaults[.meetingCodeOpener] = provider.rawValue
        performOpen(target: target, provider: provider)
    }

    /// 一级动作（D-01）：点一下就是结果。
    func performPrimary() {
        guard !isBusy else { return }
        switch primary {
        case let .open(target, provider):
            performOpen(target: target, provider: provider)
        case let .copyCode(number):
            revision += 1
            copy(number)
            settle(with: .copied)
        case .none:
            feedback = .failed
        }
    }

    /// 两个入口共用的执行器：带链接的候选走 `MeetingOpening.open`，只有会议号时按号码拼深链。
    private func performOpen(target: MeetingJoinTarget, provider: MeetingProvider?) {
        revision += 1
        let current = revision
        isOpening = true
        feedback = .opening
        task = Task { [weak self] in
            guard let self else { return }
            let result: MeetingOpenResult
            if target.canOpen {
                result = await self.opening.open(target)
            } else if let provider, let number = Self.number(in: target) {
                // 入会密码只喂华为深链（D-07）：腾讯分支没有可查依据可写。
                result = await self.opening.openByNumber(
                    provider: provider, number: number,
                    displayName: Self.resolvedDisplayName(NSFullUserName()),
                    passcode: provider == .huawei ? MeetingLinkResolver().passcode(in: self.source) : nil)
            } else {
                result = .unavailable
            }
            guard self.revision == current, !Task.isCancelled else { return }
            self.task = nil
            self.apply(result, to: target)
            self.isOpening = false
        }
    }

    /// 打开结果落到瞬时状态（D-10）。打不开就退回复制号码（docs/47 §做法 3），不谎称已加入。
    private func apply(_ result: MeetingOpenResult, to target: MeetingJoinTarget) {
        switch result {
        case .accepted, .fallback:
            settle(with: .opened)
        case .refused, .unavailable:
            guard let number = Self.number(in: target) else {
                feedback = .failed
                return
            }
            copy(number)
            settle(with: .copied)
        case .cancelled:
            feedback = .idle
        }
    }

    /// 置状态并在 1.5 秒后回到 `idle`（成功态是瞬时反馈，不是「已加入」的确认）。
    private func settle(with value: MeetingActionFeedback) {
        feedback = value
        guard value == .opened || value == .copied else { return }
        let current = revision
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.feedbackDwell)
            guard let self, !Task.isCancelled, self.revision == current else { return }
            self.feedback = .idle
        }
    }

    /// 号码取证据里第一个会议号的纯数字值（`MeetingCode.value` 已剥掉空格与连字符）。
    private static func number(in target: MeetingJoinTarget) -> String? {
        target.meetingCodes.first.map(\.value)
    }

    func copySource() { copy(source) }

    func copy(_ value: String) { guard !value.isEmpty else { return }; copyText(value) }
    func cancel() {
        revision += 1
        task?.cancel()
        task = nil
        isOpening = false
        feedback = .idle
    }

    deinit { task?.cancel() }
}

/// The entry is available before start−15m; only actual URL dispatch keeps the old time gate.
struct MeetingActionView: View {
    let source: CalendarMeetingSource
    let session: CalendarPanelSession

    init(event: EventModel, url: URL? = nil, session: CalendarPanelSession) {
        source = CalendarMeetingSource(event: event, url: url)
        self.session = session
    }
    init(source: CalendarMeetingSource, session: CalendarPanelSession) {
        self.source = source
        self.session = session
    }
    var body: some View {
        if source.hasMeetingInformation {
            MeetingActionContent(source: source, session: session)
                .id(source.identity)
        }
    }
}

private struct MeetingActionContent: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @StateObject private var model: MeetingActionModel

    init(source: CalendarMeetingSource, session: CalendarPanelSession) {
        _model = StateObject(wrappedValue: MeetingActionModel(source: source, session: session))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            MeetingActionMenu(model: model, vm: vm)
                .frame(height: 24)
                .accessibilityIdentifier("calendar-meeting-actions")
        }
        .onDisappear { model.cancel() }
    }
}

/// Real NSMenu lifecycle, no popover pin. Explicit candidates remain distinct menu choices.
private struct MeetingActionMenu: NSViewRepresentable {
    @ObservedObject var model: MeetingActionModel
    var vm: DynamicIslandViewModel

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.show(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        context.coordinator.connect()
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        button.title = String(localized: "calendar.meeting.actions")
        button.toolTip = String(localized: "calendar.meeting.menuHelp")
        button.setAccessibilityLabel(button.title)
    }
    static func dismantleNSView(_ button: NSButton, coordinator: Coordinator) { coordinator.stop() }

    @MainActor final class Coordinator: NSObject, NSMenuDelegate {
        var parent: MeetingActionMenu
        private var interaction: CalendarTextInteraction?
        private var menu: NSMenu?
        private var actions: [() -> Void] = []
        private var observers: [NSObjectProtocol] = []
        init(_ parent: MeetingActionMenu) { self.parent = parent }
        func connect() {
            let vm = parent.vm
            interaction = CalendarTextInteraction(
                setProtection: { [weak vm] in vm?.setAutoCloseSuppression($0, token: $1) },
                recheckHover: { [weak vm] in vm?.shouldRecheckHover.toggle() })
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                                     object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.depart() }
            })
        }
        @objc func show(_ button: NSButton) {
            depart()
            let menu = NSMenu()
            menu.autoenablesItems = false
            self.menu = menu
            menu.delegate = self
            actions.removeAll()
            let model = parent.model
            if model.targets.isEmpty { add("calendar.meeting.noEvidence", to: menu, enabled: false) {} }
            if model.targets.filter(\.canOpen).count > 1 { add("calendar.meeting.choose", to: menu, enabled: false) {} }
            for target in model.targets {
                let candidate = NSMenuItem(title: target.sourceURL?.absoluteString ?? target.sourceText, action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                if target.canOpen {
                    add("calendar.meeting.open", to: submenu, enabled: !model.isBusy) { model.open(target) }
                }
                for link in [target.sourceURL, target.httpsURL].compactMap({ $0 }).reduce(into: [URL](), { if !$0.contains($1) { $0.append($1) } }) {
                    add("calendar.meeting.copyLink", to: submenu) { model.copy(link.absoluteString) }
                }
                for code in target.meetingCodes {
                    add(String(format: String(localized: "calendar.meeting.copyCodeFormat"), code.sourceText), to: submenu, localized: false) { model.copy(code.sourceText) }
                }
                candidate.submenu = submenu
                submenu.delegate = self
                menu.addItem(candidate)
            }
            menu.addItem(.separator())
            add("calendar.meeting.sendingScope", to: menu, enabled: false) {}
            add("calendar.generation.model", to: menu, enabled: false) {}
            add("calendar.generation.settings", to: menu) { CalendarAISettingsNavigation.open() }
            add("calendar.meeting.copySource", to: menu, enabled: model.hasSource) { model.copySource() }
            if model.isBusy { add("Cancel", to: menu) { model.cancel() } }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button)
        }
        private func add(_ title: String, to menu: NSMenu, enabled: Bool = true, localized: Bool = true, action: @escaping () -> Void) {
            let item = NSMenuItem(title: localized ? NSLocalizedString(title, comment: "") : title,
                                  action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
            item.tag = actions.count
            actions.append(action)
            menu.addItem(item)
        }
        @objc private func choose(_ item: NSMenuItem) { if actions.indices.contains(item.tag) { actions[item.tag]() } }
        func menuWillOpen(_ menu: NSMenu) { interaction?.menuWillOpen(menu) }
        func menuDidClose(_ menu: NSMenu) { interaction?.menuDidClose(menu) }
        private func depart() {
            interaction?.depart()
            clearDelegate(menu)
            menu?.cancelTracking()
            menu = nil
        }
        private func clearDelegate(_ menu: NSMenu?) {
            menu?.delegate = nil
            for item in menu?.items ?? [] { clearDelegate(item.submenu) }
        }
        func stop() {
            depart()
            interaction?.stop()
            interaction = nil
            actions.removeAll()
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
        }
    }
}

/// Editable text grows inside the page's single ScrollView rather than owning a nested scroll view.
struct CalendarGrowingTextEditor: NSViewRepresentable {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @Binding var text: String
    var label: String
    var onFocus: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> CalendarEditableTextView {
        let view = CalendarEditableTextView(frame: .zero, textContainer: nil)
        view.delegate = context.coordinator
        view.onFocus = onFocus
        view.interaction = CalendarTextInteraction(
            setProtection: { [weak vm] in vm?.setAutoCloseSuppression($0, token: $1) },
            recheckHover: { [weak vm] in vm?.shouldRecheckHover.toggle() })
        view.setAccessibilityLabel(NSLocalizedString(label, comment: ""))
        return view
    }
    func updateNSView(_ view: CalendarEditableTextView, context: Context) {
        context.coordinator.parent = self
        view.onFocus = onFocus
        if view.string != text { view.string = text }
        view.setAccessibilityLabel(NSLocalizedString(label, comment: ""))
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CalendarEditableTextView, context: Context) -> CGSize? {
        nsView.measuredSize(width: proposal.width ?? 200)
    }
    static func dismantleNSView(_ view: CalendarEditableTextView, coordinator: Coordinator) { view.stop() }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CalendarGrowingTextEditor
        init(_ parent: CalendarGrowingTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}

@MainActor
final class CalendarEditableTextView: NSTextView, NSMenuDelegate {
    var onFocus: (Bool) -> Void = { _ in }
    var interaction: CalendarTextInteraction?
    private var ownedMenus: [NSMenu] = []
    private var resignObserver: NSObjectProtocol?

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        if let textContainer {
            super.init(frame: frame, textContainer: textContainer)
        } else {
            // Match the read-only bridge: nil needs an owned, complete TextKit chain.
            let storage = NSTextStorage()
            let manager = NSLayoutManager()
            let container = NSTextContainer(containerSize: NSSize(width: frame.width, height: .greatestFiniteMagnitude))
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            super.init(frame: frame, textContainer: container)
        }
        isRichText = false
        isEditable = true
        isSelectable = true
        isHorizontallyResizable = false
        isVerticallyResizable = false
        wantsLayer = true
        layer?.masksToBounds = true
        drawsBackground = true
        backgroundColor = NSColor.white.withAlphaComponent(0.06)
        textColor = .white
        insertionPointColor = .white
        allowsUndo = true
        font = .systemFont(ofSize: NSFont.systemFontSize)
        textContainerInset = NSSize(width: 4, height: 4)
        self.textContainer?.lineFragmentPadding = 0
        self.textContainer?.widthTracksTextView = true
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.depart() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func measuredSize(width: CGFloat) -> CGSize {
        CalendarTextMeasurement.size(of: self, width: width, minimumHeight: 60)
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CalendarTextMeasurement.synchronize(self)
    }
    override func layout() {
        super.layout()
        CalendarTextMeasurement.synchronize(self)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        bounds.clip()
        super.draw(dirtyRect.intersection(bounds))
        NSGraphicsContext.restoreGraphicsState()
    }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus(true) }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocus(false) }
        return accepted
    }
    override func mouseDown(with event: NSEvent) {
        let owner = interaction
        owner?.mouseDown()
        defer { owner?.trackingReturned() }
        super.mouseDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }
        menu.delegate = self
        ownedMenus.append(menu)
        return menu
    }
    func menuWillOpen(_ menu: NSMenu) { interaction?.menuWillOpen(menu) }
    func menuDidClose(_ menu: NSMenu) {
        interaction?.menuDidClose(menu)
        menu.delegate = nil
        ownedMenus.removeAll { $0 === menu }
    }
    private func depart() {
        onFocus(false)
        interaction?.depart()
        for menu in ownedMenus { menu.delegate = nil; menu.cancelTracking() }
        ownedMenus.removeAll()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { depart() }
    }
    func stop() {
        depart()
        interaction?.stop()
        interaction = nil
        delegate = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }
    deinit {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        let owner = interaction
        MainActor.assumeIsolated { owner?.stop() }
    }
}
