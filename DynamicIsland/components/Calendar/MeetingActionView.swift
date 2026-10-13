// Copyright (C) 2026 Gourd Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
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
        // Invitation intent only; an ordinary task mentioning a meeting room is not an invitation.
        let hints = #"(?i)(会议邀请|会议主题\s*[:：]|会议链接\s*[:：]|邀请[^\n]{0,40}(?:参加|加入)[^\n]{0,15}会议|(?:请|欢迎)[^\n]{0,20}(?:参加|加入)[^\n]{0,20}会议|(?:meeting|conference)\s+invit(?:ation|e)|(?:join|invited)[^\n]{0,40}(?:meeting|conference))"#
        return textFields.contains { $0.range(of: hints, options: .regularExpression) != nil }
    }
}

/// An injected, offline-testable action controller. Recognition never opens a candidate.
@MainActor
final class MeetingActionModel: ObservableObject {
    @Published private(set) var targets: [MeetingJoinTarget]
    @Published private(set) var isRecognizing = false
    @Published private(set) var isOpening = false
    @Published private(set) var statusKey: String?
    private let source: String
    private let start: Date?
    private let session: CalendarPanelSession
    private let opening: MeetingOpening
    private let now: () -> Date
    private let copyText: (String) -> Void
    private var task: Task<Void, Never>?
    private var revision = 0

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

    var isJoinable: Bool { start.map { $0.addingTimeInterval(-15 * 60) <= now() } ?? true }
    var hasAI: Bool { session.configuredAI != nil }
    var hasSource: Bool { !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isBusy: Bool { isRecognizing || isOpening }

    func recognize() {
        guard !isBusy else { return }
        guard let ai = session.configuredAI else { statusKey = "calendar.meeting.configure"; return }
        revision += 1
        let current = revision
        isRecognizing = true
        statusKey = "calendar.meeting.recognizing"
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let recognized = try await MeetingLinkResolver().recognize(text: self.source, using: ai)
                guard !Task.isCancelled, self.revision == current else { return }
                // Preserve every deterministic opening choice even if AI only returns a code.
                for target in recognized where !self.targets.contains(target) { self.targets.append(target) }
                self.statusKey = self.targets.isEmpty ? "calendar.meeting.noEvidence" : "calendar.meeting.choose"
            } catch {
                guard !Task.isCancelled, self.revision == current else { return }
                self.statusKey = (error as? MeetingRecognitionError) == .sourceTooLarge
                    ? "calendar.meeting.sourceTooLarge" : "calendar.meeting.recognitionFailed"
            }
            if self.revision == current { self.isRecognizing = false; self.task = nil }
        }
    }

    func open(_ target: MeetingJoinTarget) {
        guard !isBusy, isJoinable, target.canOpen, targets.contains(target) else { return }
        revision += 1
        let current = revision
        isOpening = true
        statusKey = "calendar.meeting.opening"
        task = Task { [weak self] in
            guard let self else { return }
            let result = await self.opening.open(target)
            guard self.revision == current, !Task.isCancelled else { return }
            switch result {
            case .accepted: self.statusKey = "calendar.meeting.accepted"
            case .fallback: self.statusKey = "calendar.meeting.fallback"
            case .refused, .unavailable: self.statusKey = "calendar.meeting.refused"
            case .cancelled: self.statusKey = "calendar.meeting.cancelled"
            }
            self.isOpening = false
            self.task = nil
        }
    }

    func copySource() { copy(source) }

    func copy(_ value: String) { guard !value.isEmpty else { return }; copyText(value) }
    func cancel() {
        revision += 1
        task?.cancel()
        task = nil
        if isBusy { statusKey = "calendar.meeting.cancelled" }
        isRecognizing = false
        isOpening = false
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
            if let key = model.statusKey {
                Text(LocalizedStringKey(key)).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("calendar-meeting-status")
            }
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
            if let status = model.statusKey { add(status, to: menu, enabled: false) {} }
            if !model.isJoinable { add("calendar.meeting.tooEarly", to: menu, enabled: false) {} }
            if model.targets.isEmpty { add("calendar.meeting.noEvidence", to: menu, enabled: false) {} }
            if model.targets.filter(\.canOpen).count > 1 { add("calendar.meeting.choose", to: menu, enabled: false) {} }
            for target in model.targets {
                let candidate = NSMenuItem(title: target.sourceURL?.absoluteString ?? target.sourceText, action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                if target.canOpen {
                    add("calendar.meeting.open", to: submenu, enabled: model.isJoinable && !model.isBusy) { model.open(target) }
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
            add("calendar.meeting.recognize", to: menu, enabled: model.hasSource && !model.isBusy) { model.recognize() }
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
        let width = max(1, proposal.width ?? 200)
        nsView.textContainer?.containerSize = CGSize(width: max(1, width - 8), height: .greatestFiniteMagnitude)
        guard let container = nsView.textContainer, let manager = nsView.layoutManager else { return CGSize(width: width, height: 60) }
        manager.ensureLayout(for: container)
        return CGSize(width: width, height: max(60, ceil(manager.usedRect(for: container).height) + 8))
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
        super.init(frame: frame, textContainer: textContainer)
        isRichText = false
        isEditable = true
        isSelectable = true
        isHorizontallyResizable = false
        isVerticallyResizable = true
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
