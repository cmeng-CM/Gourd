// Copyright (C) 2026 Gourd Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import SwiftUI

/// Extract whole lexical evidence from existing records before applying the resolver's input cap.
/// No fragment is split or truncated; oversized individual tokens are rejected in their entirety.
/// Each complete candidate is still validated by the unchanged T3 resolver, including domain/path rules.
enum CalendarMeetingEvidence {
    static func resolve(textFields: [String], structuredURLs: [URL] = []) -> [MeetingJoinTarget] {
        let resolver = MeetingLinkResolver()
        let patterns = [
            #"[A-Za-z][A-Za-z0-9+.-]*://[^\s<>\"“”]+"#,
            #"(?i)(?:#腾讯会议|腾讯会议|会议\s*(?:ID|号)|meeting\s*(?:ID|code))\s*[:：]\s*([0-9](?:[0-9 -]{3,18})[0-9])(?![0-9])"#
        ]
        var fragments: [String] = []
        var independentTargets: [MeetingJoinTarget] = []
        var seen = Set<String>()
        func collect(_ raw: String) {
            guard raw.count <= MeetingLinkResolver.maximumSourceCharacters else { return }
            // Resolve the COMPLETE candidate first. The scanner never authorizes a prefix.
            for target in resolver.resolve(text: raw) {
                let values = (target.sourceURL == nil ? [] : [target.sourceText]) + target.meetingCodes.map(\.sourceText)
                for value in values where seen.insert(value).inserted {
                    fragments.append(value)
                    independentTargets += resolver.resolve(text: value)
                }
            }
        }
        for field in textFields {
            let range = NSRange(field.startIndex..., in: field)
            let matches = patterns.flatMap { pattern in
                (try? NSRegularExpression(pattern: pattern))?.matches(in: field, range: range) ?? []
            }.sorted { $0.range.location < $1.range.location }
            for match in matches {
                if let range = Range(match.range, in: field) { collect(String(field[range])) }
            }
        }
        for url in structuredURLs { collect(url.absoluteString) }

        // Pair only when the COMPLETE evidence set fits the validator's input contract.
        // Splitting it into batches could wrongly make an ambiguous fallback look unique.
        let evidence = fragments.joined(separator: "\n")
        if evidence.count <= MeetingLinkResolver.maximumSourceCharacters { return resolver.resolve(text: evidence) }
        return independentTargets
    }
}

/// Copying uses display snapshots and validated complete source evidence, without opening a meeting.
struct CalendarCopyPayload: Equatable {
    let title: String
    let fullInformation: String
    let meetingInformation: String

    init(title: String, fullInformation: String, meetingSource: String = "") {
        self.init(title: title, fullInformation: fullInformation,
                  targets: CalendarMeetingEvidence.resolve(textFields: [meetingSource]))
    }

    private init(title: String, fullInformation: String, targets: [MeetingJoinTarget]) {
        self.title = title
        self.fullInformation = fullInformation
        var evidence: [String] = []
        for target in targets {
            for value in [target.sourceURL?.absoluteString, target.httpsURL?.absoluteString].compactMap({ $0 })
                + target.meetingCodes.map(\.sourceText) where !evidence.contains(value) {
                evidence.append(value)
            }
        }
        meetingInformation = evidence.joined(separator: "\n")
    }

    init(event: EventModel) {
        let calendar = CalendarPanelDates.sourceCalendar(for: event)
        var fields = [event.title, event.calendar.title]
        if CalendarPanelDates.hasDueDate(event) {
            fields.append(CalendarPanelDates.formatted(event.start, allDay: event.isAllDay, calendar: calendar))
            if !event.type.isReminder {
                let end = event.isAllDay
                    ? CalendarEventInput.includedAllDayEnd(exclusiveEnd: event.end, calendar: calendar) ?? event.start : event.end
                fields.append(CalendarPanelDates.formatted(end, allDay: event.isAllDay, calendar: calendar))
            }
        } else { fields.append(String(localized: "calendar.panel.noDueDate")) }
        if event.isAllDay { fields.append(String(localized: "All-day")) }
        if let zone = event.timeZone { fields.append(zone.identifier) }
        fields += [event.location, event.notes, event.url?.absoluteString].compactMap { $0 }.filter { !$0.isEmpty }
        if let url = event.conferenceURL?.absoluteString, !fields.contains(url) { fields.append(url) }
        self.init(title: event.title, fullInformation: fields.joined(separator: "\n"),
                  targets: CalendarMeetingEvidence.resolve(
                    textFields: [event.title, event.location, event.notes].compactMap { $0 },
                    structuredURLs: [event.url, event.conferenceURL].compactMap { $0 }))
    }

    init(item: TodoBucketing.Item) {
        var fields = [item.title, item.listName]
        if let due = item.dueDate { fields.append(due.formatted()) }
        self.init(title: item.title, fullInformation: fields.joined(separator: "\n"), meetingSource: item.title)
    }
}

/// Each text view owns one token; selection/focus alone never keeps the island open.
/// The same entry points are exercised by offline callback tests.
@MainActor
final class CalendarTextInteraction {
    let token = UUID()
    private(set) var dragging = false
    private var menus = Set<ObjectIdentifier>()
    private var active = false
    private var stopped = false
    private let setProtection: (Bool, UUID) -> Void
    private let recheckHover: () -> Void

    init(setProtection: @escaping (Bool, UUID) -> Void, recheckHover: @escaping () -> Void) {
        self.setProtection = setProtection
        self.recheckHover = recheckHover
    }

    func mouseDown() { guard !stopped else { return }; dragging = true; update() }
    func mouseUp() { dragging = false; update() }
    func trackingReturned() { mouseUp() }
    func menuWillOpen(_ menu: AnyObject) { guard !stopped else { return }; menus.insert(ObjectIdentifier(menu)); update() }
    func menuDidClose(_ menu: AnyObject) { menus.remove(ObjectIdentifier(menu)); update() }
    func depart() { dragging = false; menus.removeAll(); update() }
    func stop() { stopped = true; depart() }

    private func update() {
        let next = dragging || !menus.isEmpty
        guard next != active else { return }
        active = next
        setProtection(next, token)
        if !next { recheckHover() }
    }
}

/// Measurements own a TextKit snapshot. SwiftUI proposals must never resize live text.
@MainActor
enum CalendarTextMeasurement {
    static func size(of view: NSTextView, width proposedWidth: CGFloat, minimumHeight: CGFloat) -> CGSize {
        let width = proposedWidth.isFinite ? max(1, proposedWidth) : 200
        let storage = NSTextStorage(attributedString: view.textStorage.map {
            NSAttributedString(attributedString: $0)
        } ?? NSAttributedString(string: view.string))
        let manager = NSLayoutManager()
        let container = NSTextContainer(containerSize: CGSize(
            width: max(1, width - 2 * view.textContainerInset.width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = view.textContainer?.lineFragmentPadding ?? 0
        container.maximumNumberOfLines = view.textContainer?.maximumNumberOfLines ?? 0
        container.lineBreakMode = view.textContainer?.lineBreakMode ?? .byWordWrapping
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        let height = ceil(manager.usedRect(for: container).height) + 2 * view.textContainerInset.height
        return CGSize(width: width, height: max(minimumHeight, height.isFinite ? height : minimumHeight))
    }

    static func synchronize(_ view: NSTextView) {
        let width = max(1, view.bounds.width - 2 * view.textContainerInset.width)
        let size = CGSize(width: width, height: .greatestFiniteMagnitude)
        if view.textContainer?.containerSize != size { view.textContainer?.containerSize = size }
    }
}

/// A real read-only NSTextView: AppKit owns dragging, Cmd-C and contextual menu tracking.
struct CalendarSelectableText: NSViewRepresentable {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    let text: String
    let payload: CalendarCopyPayload
    var font: NSFont = .systemFont(ofSize: NSFont.systemFontSize)
    var color: NSColor = .white
    var maximumLines: Int = 0
    var strikethrough = false
    /// 「点了一下」（不是拖选）时的回调：列表行据此就地弹详情浮窗（docs/49 D-22）。
    /// 判定在 `CalendarReadOnlyTextView.mouseDown` 里——**必须在** `super.mouseDown` 之后，
    /// 因为 NSTextView 的选择跟踪循环会把 mouseUp 吃在它内部。
    var onPlainClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> CalendarReadOnlyTextView {
        let view = CalendarReadOnlyTextView(frame: .zero, textContainer: nil)
        view.connect(to: vm)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: CalendarReadOnlyTextView, context: Context) {
        view.connect(to: vm)
        view.payload = payload
        view.onPlainClick = onPlainClick
        view.configure(text: text, font: font, color: color, maximumLines: maximumLines,
                       strikethrough: strikethrough)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CalendarReadOnlyTextView, context: Context) -> CGSize? {
        nsView.measuredSize(width: proposal.width ?? 200)
    }

    static func dismantleNSView(_ view: CalendarReadOnlyTextView, coordinator: ()) { view.stop() }
}

@MainActor
final class CalendarReadOnlyTextView: NSTextView, NSMenuDelegate {
    var payload = CalendarCopyPayload(title: "", fullInformation: "")
    /// 「点了一下」回调（不是拖选）：列表行据此就地弹详情浮窗（docs/49 D-22）。
    var onPlainClick: (() -> Void)?
    private(set) var interaction: CalendarTextInteraction?
    private weak var viewModel: DynamicIslandViewModel?
    private var subscriptions = Set<AnyCancellable>()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var upMonitor: Any?
    private var ownedMenus: [NSMenu] = []

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        if let container {
            super.init(frame: frameRect, textContainer: container)
        } else {
            // The designated NSTextView initializer does not create TextKit for nil.
            let storage = NSTextStorage()
            let manager = NSLayoutManager()
            let container = NSTextContainer(containerSize: NSSize(width: frameRect.width, height: .greatestFiniteMagnitude))
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            super.init(frame: frameRect, textContainer: container)
        }
        isEditable = false
        isSelectable = true
        isRichText = false
        drawsBackground = false
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        isHorizontallyResizable = false
        isVerticallyResizable = false
        wantsLayer = true
        layer?.masksToBounds = true
        textContainer?.widthTracksTextView = true
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func connect(to vm: DynamicIslandViewModel) {
        guard viewModel !== vm || interaction == nil else { return }
        stop()
        viewModel = vm
        interaction = CalendarTextInteraction(
            setProtection: { [weak vm] in vm?.setAutoCloseSuppression($0, token: $1) },
            recheckHover: { [weak vm] in vm?.shouldRecheckHover.toggle() }
        )
        vm.$notchState.dropFirst().sink { [weak self] state in
            if state == .closed { self?.depart() }
        }.store(in: &subscriptions)
        attachObservers()
    }

    func configure(text: String, font: NSFont, color: NSColor, maximumLines: Int, strikethrough: Bool) {
        let value = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .strikethroughStyle: strikethrough ? NSUnderlineStyle.single.rawValue : 0
        ])
        // AppKit may replace system font runs with a CJK fallback during layout.
        // Refreshing attributes must keep selection only when its UTF-16 coordinates are unchanged.
        if textStorage?.isEqual(to: value) == false {
            let ranges = string.utf16.elementsEqual(text.utf16) ? selectedRanges : nil
            textStorage?.setAttributedString(value)
            if let ranges { selectedRanges = ranges }
        }
        textContainer?.maximumNumberOfLines = maximumLines
        textContainer?.lineBreakMode = maximumLines > 0 ? .byTruncatingTail : .byWordWrapping
    }

    func measuredSize(width: CGFloat) -> CGSize {
        CalendarTextMeasurement.size(of: self, width: width,
                                     minimumHeight: ceil(font?.boundingRectForFont.height ?? 16))
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

    /// 「点了一下」的位置容差（pt）：位移小于它且没有选中，就当作单击而不是拖选。
    static let plainClickTolerance: CGFloat = 4

    override func mouseDown(with event: NSEvent) {
        let owner = interaction
        owner?.mouseDown()
        installUpMonitor()
        // NSTextView may consume mouseUp inside its own tracking loop.
        defer { owner?.trackingReturned(); removeUpMonitor() }
        let downPoint = convert(event.locationInWindow, from: nil)
        super.mouseDown(with: event)
        // 跟踪循环已结束：此刻的鼠标位置 ≈ 抬起位置，选区也已成定局。
        guard let onPlainClick else { return }
        let upPoint = convert(window?.mouseLocationOutsideOfEventStream ?? downPoint, from: nil)
        let moved = max(abs(upPoint.x - downPoint.x), abs(upPoint.y - downPoint.y))
        guard moved < Self.plainClickTolerance, selectedRange().length == 0 else { return }
        onPlainClick()
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        interaction?.mouseUp()
        removeUpMonitor()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let copy = menu.addItem(withTitle: String(localized: "calendar.copy.selection"), action: #selector(copy(_:)), keyEquivalent: "")
        copy.target = self
        copy.isEnabled = selectedRange().length > 0
        menu.addItem(.separator())
        for (key, action, enabled) in [
            ("calendar.copy.title", #selector(copyTitle(_:)), true),
            ("calendar.copy.fullInformation", #selector(copyFullInformation(_:)), true),
            ("calendar.copy.meetingInformation", #selector(copyMeetingInformation(_:)), !payload.meetingInformation.isEmpty)
        ] {
            let item = menu.addItem(withTitle: NSLocalizedString(key, comment: ""), action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
        }
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

    @objc private func copyTitle(_ sender: Any?) { writeClipboard(payload.title) }
    @objc private func copyFullInformation(_ sender: Any?) { writeClipboard(payload.fullInformation) }
    @objc private func copyMeetingInformation(_ sender: Any?) { writeClipboard(payload.meetingInformation) }
    private func writeClipboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        depart()
        removeObservers()
        if window != nil, interaction != nil { attachObservers() }
    }

    private func attachObservers() {
        guard observers.isEmpty else { return }
        for name in [NSApplication.didResignActiveNotification, NSApplication.willTerminateNotification] {
            observe(NotificationCenter.default, name: name)
        }
        observe(NSWorkspace.shared.notificationCenter, name: NSWorkspace.didActivateApplicationNotification)
        if let window { observe(NotificationCenter.default, name: NSWindow.willCloseNotification, object: window) }
    }

    private func observe(_ center: NotificationCenter, name: Notification.Name, object: AnyObject? = nil) {
        let observer = center.addObserver(forName: name, object: object, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                if name == NSWorkspace.didActivateApplicationNotification,
                   let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
                self?.depart()
            }
        }
        observers.append((center, observer))
    }

    private func installUpMonitor() {
        guard upMonitor == nil else { return }
        upMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.interaction?.mouseUp()
            self?.removeUpMonitor()
            return event
        }
    }

    private func removeUpMonitor() {
        if let upMonitor { NSEvent.removeMonitor(upMonitor) }
        upMonitor = nil
    }

    private func removeObservers() {
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    private func depart() {
        interaction?.depart()
        removeUpMonitor()
        for menu in ownedMenus { menu.delegate = nil; menu.cancelTracking() }
        ownedMenus.removeAll()
    }

    func stop() {
        depart()
        removeObservers()
        subscriptions.removeAll()
        interaction?.stop()
        interaction = nil
        viewModel = nil
    }

    deinit {
        let owner = interaction
        MainActor.assumeIsolated { owner?.stop() }
        for (center, observer) in observers { center.removeObserver(observer) }
        if let upMonitor { NSEvent.removeMonitor(upMonitor) }
    }
}
