// Modified for Gourd (2026-10-11)
// Copyright (C) 2026 Gourd Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Combine
import SwiftUI

/// 每个页面只释放自己的 ownership 和 VM 令牌；真正离开应用才暂存共享会话。
@MainActor
final class CalendarEditorLifecycle: ObservableObject {
    let ownerID = UUID()
    let session: CalendarPanelSession
    var editorHasFocus: Bool { session.editorHasFocus }
    var ownedMenuCount: Int { session.ownedMenuCount }
    var datePopoverPresented: Bool { session.datePopoverPresented }
    var shouldProtectAutoClose: Bool { session.shouldProtectAutoClose }

    private let protectionToken = UUID()
    private let scrollToken = UUID()
    private weak var window: NSWindow?
    private weak var viewModel: DynamicIslandViewModel?
    private var focused = false
    private var menuCount = 0
    private var popoverPresented = false
    private var protected = false
    private var subscriptions = Set<AnyCancellable>()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var localClickMonitor: Any?
    private var outsideClickMonitor: Any?
    private var keyLossCheck: DispatchWorkItem?
    private var setProtection: (Bool, UUID) -> Void
    private var setScroll: (Bool, UUID) -> Void
    private var recheckHover: () -> Void

    init(session: CalendarPanelSession, setProtection: @escaping (Bool, UUID) -> Void = { _, _ in },
         setScroll: @escaping (Bool, UUID) -> Void = { _, _ in }, recheckHover: @escaping () -> Void = {}) {
        self.session = session
        self.setProtection = setProtection
        self.setScroll = setScroll
        self.recheckHover = recheckHover
    }

    func connect(to viewModel: DynamicIslandViewModel) {
        self.viewModel = viewModel
        setProtection = { [weak viewModel] in viewModel?.setAutoCloseSuppression($0, token: $1) }
        setScroll = { [weak viewModel] in viewModel?.setScrollGestureSuppression($0, token: $1) }
        recheckHover = { [weak viewModel] in viewModel?.shouldRecheckHover.toggle() }
        subscriptions.removeAll()
        session.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] in
            self?.updateProtection()
        }.store(in: &subscriptions)
        viewModel.$notchState.dropFirst().sink { [weak self] state in
            if state == .closed { self?.clearLocalInput(); self?.setScrolling(false) }
        }.store(in: &subscriptions)
        updateProtection()
    }

    func setEditorFocus(_ focused: Bool) {
        self.focused = focused
        if focused { window?.makeKey() }
        session.setEditorFocus(focused, ownerID: ownerID)
        updateProtection()
    }

    func setOwnedMenuCount(_ count: Int) {
        menuCount = max(0, count)
        session.setOwnedMenuCount(menuCount, ownerID: ownerID)
        updateProtection()
        if menuCount == 0 { scheduleKeyLossCheck() }
    }

    func setDatePopoverPresented(_ presented: Bool) {
        popoverPresented = presented
        session.setDatePopoverPresented(presented, ownerID: ownerID)
        updateProtection()
        if !presented { scheduleKeyLossCheck() }
    }

    func setScrolling(_ scrolling: Bool) { setScroll(scrolling, scrollToken) }

    func clearLocalInput() {
        focused = false
        menuCount = 0
        popoverPresented = false
        session.clearOwnership(ownerID)
        setScrolling(false)
        updateProtection()
    }

    private func updateProtection() {
        let next = shouldProtectAutoClose
        setProtection(next, protectionToken)
        if next { AppDelegate.shared?.cancelPendingNotchAutoClose() }
        if protected && !next { recheckHover() }
        protected = next
    }

    func attach(to window: NSWindow?) {
        guard self.window !== window else { return }
        removeWindowMonitoring()
        self.window = window
        guard let window else { return }
        let center = NotificationCenter.default
        let lostKey = center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleKeyLossCheck() }
        }
        let closed = center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let activated = workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated { self?.suspendForExternalDeparture() }
        }
        observers = [(center, lostKey), (center, closed), (workspace, activated)]
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspendForExternalDeparture() }
        }
        // Esc remains with CalendarPanelPages so popovers and confirmations dismiss first.
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, !self.owns(event.window) else { return event }
            if self.menuCount == 0 && !self.popoverPresented { self.suspendForExternalDeparture() }
            else { self.scheduleKeyLossCheck() }
            return event
        }
        if focused { window.makeKey() }
    }

    private func owns(_ candidate: NSWindow?) -> Bool {
        guard let window else { return false }
        var candidate = candidate
        while let current = candidate {
            if current === window { return true }
            candidate = current.parent
        }
        return false
    }

    private func scheduleKeyLossCheck() {
        keyLossCheck?.cancel()
        guard focused || menuCount > 0 || popoverPresented else { return }
        let check = DispatchWorkItem { [weak self] in
            guard let self, let window = self.window, !window.isKeyWindow,
                  !self.owns(NSApp.keyWindow), self.menuCount == 0, !self.popoverPresented else { return }
            self.suspendForExternalDeparture()
        }
        keyLossCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: check)
    }

    func suspendForExternalDeparture() {
        keyLossCheck?.cancel()
        session.suspend()
        clearLocalInput()
        setScrolling(false)
        recheckHover()
    }

    func stop() {
        removeWindowMonitoring()
        subscriptions.removeAll()
        clearLocalInput()
        setProtection(false, protectionToken)
        protected = false
        setScrolling(false)
        viewModel = nil
    }

    private func removeWindowMonitoring() {
        keyLossCheck?.cancel()
        keyLossCheck = nil
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        localClickMonitor = nil
        outsideClickMonitor = nil
        window = nil
    }

    static func closeForLock(session: CalendarPanelSession, closePanels: [() -> Void]) {
        session.suspend()
        closePanels.forEach { $0() }
    }
}

/// 读实际页面所属窗口，不另建宿主或以全局 keyWindow 猜测归属。
struct CalendarEditorWindowReader: NSViewRepresentable {
    var lifecycle: CalendarEditorLifecycle
    func makeNSView(context: Context) -> Reader { Reader(lifecycle: lifecycle) }
    func updateNSView(_ view: Reader, context: Context) { view.lifecycle = lifecycle; lifecycle.attach(to: view.window) }
    static func dismantleNSView(_ view: Reader, coordinator: ()) { view.lifecycle?.stop() }

    final class Reader: NSView {
        weak var lifecycle: CalendarEditorLifecycle?
        init(lifecycle: CalendarEditorLifecycle) { self.lifecycle = lifecycle; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); lifecycle?.attach(to: window) }
    }
}

/// NSApplication's repeated quit/restart requests share one prompt and one write decision.
@MainActor
final class CalendarTerminationController {
    private var request: Task<Bool, Never>?
    private(set) var restartPending = false
    func requestRestart() { restartPending = true }

    func resolve(session: CalendarPanelSession, choose: @escaping () -> CalendarTerminationChoice,
                 restart: @escaping () -> Void = {}) async -> Bool {
        if let request { return await request.value }
        let task = Task { @MainActor in
            if session.isSubmitting, !(await session.waitForSubmission()) { return false }
            let choice: CalendarTerminationChoice = session.hasDirtyDraft ? choose() : .save
            return await session.resolveTermination(choice)
        }
        request = task
        let allowed = await task.value
        request = nil
        let shouldRestart = allowed && restartPending
        restartPending = false
        if shouldRestart { restart() }
        return allowed
    }
}

#if DEBUG
@MainActor
final class CalendarFixtureReadiness: ObservableObject {
    static let shared = CalendarFixtureReadiness()
    @Published private(set) var ready = false
    private var bootstrapCompleted = false
    private var windowsCreated = false
    private var opening = false
    func didBootstrap() { bootstrapCompleted = true }
    func didCreateWindows() { windowsCreated = true }
    func beginOpening() -> Bool {
        guard bootstrapCompleted, windowsCreated, !opening else { return false }
        opening = true
        return true
    }
    func didOpen() { ready = true }
}
#endif
