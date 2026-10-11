/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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

import Combine
import Defaults
import SwiftUI

@MainActor
class DynamicIslandViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var detector = FullscreenMediaDetector.shared

    let animationLibrary: DynamicIslandAnimations = .init()
    let animation: Animation?

    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchState = .closed

    @Published var dragDetectorTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var dropEvent: Bool = false
    @Published var anyDropZoneTargeting: Bool = false
    var cancellables: Set<AnyCancellable> = []

    /// Teardown hook ContentView registers in `onAppear`; the window-cleanup path
    /// invokes it before closing the panel since `.onDisappear` is unreliable for
    /// borderless panels, preventing leaked hover-polling Tasks from accumulating.
    var onViewTeardown: (() -> Void)?
    
    @Published var hideOnClosed: Bool = true
    @Published var isHoveringCalendar: Bool = false
    @Published var isBatteryPopoverActive: Bool = false
    @Published var isClipboardPopoverActive: Bool = false
    @Published var isColorPickerPopoverActive: Bool = false
    @Published var isStatsPopoverActive: Bool = false
    @Published var isReminderPopoverActive: Bool = false
    @Published var isMediaOutputPopoverActive: Bool = false
    @Published var isTimerPopoverActive: Bool = false
    /// 钉住详情浮层期间抑制面板自动收起（日历条目详情浮层，P11 / T3；并入 `ContentView.hasAnyActivePopovers()`）。
    @Published var isCalendarDetailsPinned: Bool = false
    @Published var shouldRecheckHover: Bool = false
    @Published var isScrollGestureActive: Bool = false
    private var scrollGestureSuppressionTokens: Set<UUID> = []
    @Published private(set) var isAutoCloseSuppressed: Bool = false
    private var autoCloseSuppressionTokens: Set<UUID> = []
    private let clipboardFocusWindow: TimeInterval = 10

    func setScrollGestureSuppression(_ active: Bool, token: UUID) {
        if active {
            let inserted = scrollGestureSuppressionTokens.insert(token).inserted
            if inserted {
                isScrollGestureActive = true
            }
        } else {
            if scrollGestureSuppressionTokens.remove(token) != nil {
                isScrollGestureActive = !scrollGestureSuppressionTokens.isEmpty
            }
        }
    }

    private func resetScrollGestureSuppression() {
        scrollGestureSuppressionTokens.removeAll()
        isScrollGestureActive = false
    }

    func setAutoCloseSuppression(_ active: Bool, token: UUID) {
        if active {
            let inserted = autoCloseSuppressionTokens.insert(token).inserted
            if inserted {
                isAutoCloseSuppressed = true
            }
        } else if autoCloseSuppressionTokens.remove(token) != nil {
            isAutoCloseSuppressed = !autoCloseSuppressionTokens.isEmpty
        }
    }

    private func resetAutoCloseSuppression() {
        autoCloseSuppressionTokens.removeAll()
        isAutoCloseSuppressed = false
    }

    private func focusClipboardTabIfNeeded() {
        guard !Defaults[.enableMinimalisticUI] else { return }
        guard Defaults[.enableClipboardManager] else { return }
        guard Defaults[.clipboardDisplayMode] == .separateTab else { return }
        guard let lastCopyDate = ClipboardManager.shared.lastCopiedItemDate else { return }
        guard Date().timeIntervalSince(lastCopyDate) <= clipboardFocusWindow else { return }
        guard coordinator.currentView != .notes else { return }
        withAnimation(.smooth) {
            coordinator.currentView = .notes
        }
    }
    
    let webcamManager = WebcamManager.shared
    @Published var isCameraExpanded: Bool = false
    @Published var isRequestingAuthorization: Bool = false

    @Published var screen: String?

    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()
    
    @MainActor
    deinit {
        destroy()
    }

    func destroy() {
        onViewTeardown?()
        onViewTeardown = nil
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    init(screen: String? = nil) {
        animation = animationLibrary.animation

        super.init()
        
        self.screen = screen
        notchSize = getClosedNotchSize(screen: screen)
        closedNotchSize = notchSize

        Publishers.CombineLatest($dropZoneTargeting, $dragDetectorTargeting)
            .map { value1, value2 in
                value1 || value2
            }
            .assign(to: \.anyDropZoneTargeting, on: self)
            .store(in: &cancellables)
        
        setupDetectorObserver()

        ReminderLiveActivityManager.shared.$activeWindowReminders
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let updatedTarget = self.calculateDynamicNotchSize()
                guard self.notchState == .open else { return }
                guard self.notchSize != updatedTarget else { return }
                withAnimation(.smooth) {
                    self.notchSize = updatedTarget
                }
                if let delegate = AppDelegate.shared {
                    delegate.ensureWindowSize(
                        addShadowPadding(to: updatedTarget, isMinimalistic: Defaults[.enableMinimalisticUI]),
                        animated: true,
                        force: false
                    )
                }
            }
            .store(in: &cancellables)

        TimerManager.shared.$activeSource
            .combineLatest(TimerManager.shared.$isTimerActive)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.handleMinimalisticTimerHeightChange()
            }
            .store(in: &cancellables)

        coordinator.$statsSecondRowExpansion
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.notchState == .open else { return }
                let updatedTarget = self.calculateDynamicNotchSize()
                guard self.notchSize != updatedTarget else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.notchSize = updatedTarget
                }
                if let delegate = AppDelegate.shared {
                    delegate.ensureWindowSize(
                        addShadowPadding(to: updatedTarget, isMinimalistic: Defaults[.enableMinimalisticUI]),
                        animated: false,
                        force: false
                    )
                }
            }
            .store(in: &cancellables)

        coordinator.$notesLayoutState
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.notchState == .open else { return }
                let updatedTarget = self.calculateDynamicNotchSize()
                guard self.notchSize != updatedTarget else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.notchSize = updatedTarget
                }
                if let delegate = AppDelegate.shared {
                    delegate.ensureWindowSize(
                        addShadowPadding(to: updatedTarget, isMinimalistic: Defaults[.enableMinimalisticUI]),
                        animated: true,
                        force: false
                    )
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.openNotchWidth, options: [])
            .map { $0.newValue }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.notchState == .open else { return }
                guard !Defaults[.enableMinimalisticUI] else { return }
                let updatedTarget = self.calculateDynamicNotchSize()
                guard self.notchSize != updatedTarget else { return }
                withAnimation(.smooth) {
                    self.notchSize = updatedTarget
                }
                if let delegate = AppDelegate.shared {
                    delegate.ensureWindowSize(
                        addShadowPadding(to: updatedTarget, isMinimalistic: false),
                        animated: true,
                        force: false
                    )
                }
            }
            .store(in: &cancellables)

        // 面板尺寸的重算触发（函数名里的「侧歌词」是旧档遗留；侧歌词一族已随 T5/T6 退休）。
        // 本链保留：下面每个成员仍会改变 `calculateDynamicNotchSize()` 的输出，逐条给出处——
        // - `showStandardMediaControls` / `showMirror`：首页**块**的存在性判据（音乐块 / 镜子块，
        //   见下一条）→ 块名单 → 自然高 → `openNotchSize.height`。**首页 tab 自己的那一条已不读
        //   任何键**（p13 / docs/38 D-14：Home 恒有一枚，`enabledStandardTabCount()` 直接 +1）；
        // - `showMirror` / `autoHideInactiveNotchMediaPlayer` / `WebcamManager.$cameraAvailable` /
        //   `isPlaying` / `songTitle` / `artistName`：首页块的存在性判据（`MirrorModule.isVisible` /
        //   `MusicModule.isVisible`；音乐那条经 `MusicManager.hasActiveSession`，MusicManager.swift:489）
        //   → 块名单 → 接缝算出的自然高 → 高度账本（`PanelContentHeight.current`，matters.swift:86 读）
        //   → `openNotchSize.height`。
        // 已删成员：`enableLyrics`（T5/T6 后没有一条尺寸路径读它）与侧歌词档的两枚旧键
        // （键定义同批删除）、`showCalendar`（p13 / docs/38 D-13：月历退出首页，键定义同批删除）。
        Publishers.MergeMany(
            Defaults.publisher(.showStandardMediaControls, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.autoHideInactiveNotchMediaPlayer, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.showMirror, options: []).map { _ in () }.eraseToAnyPublisher(),
            MusicManager.shared.$isPlaying.map { _ in () }.eraseToAnyPublisher(),
            MusicManager.shared.$songTitle.map { _ in () }.eraseToAnyPublisher(),
            MusicManager.shared.$artistName.map { _ in () }.eraseToAnyPublisher(),
            WebcamManager.shared.$cameraAvailable.map { _ in () }.eraseToAnyPublisher()
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateSideLyricsNotchSizeIfNeeded()
            }
            .store(in: &cancellables)
    }

    /// 由上方 `MergeMany` 链驱动（成员名单与保留理由见那里的注释）；名字里的「侧歌词」是旧档遗留。
    private func updateSideLyricsNotchSizeIfNeeded() {
        guard notchState == .open, !Defaults[.enableMinimalisticUI] else { return }

        let updatedTarget = calculateDynamicNotchSize()
        guard notchSize != updatedTarget else { return }
        withAnimation(.smooth) {
            notchSize = updatedTarget
        }
        AppDelegate.shared?.ensureWindowSize(
            addShadowPadding(to: updatedTarget, isMinimalistic: false),
            animated: true,
            force: false
        )
    }

    private func handleMinimalisticTimerHeightChange() {
        guard Defaults[.enableMinimalisticUI] else { return }
        guard notchState == .open else { return }
        let updatedTarget = calculateDynamicNotchSize()
        guard notchSize != updatedTarget else { return }
        withAnimation(.smooth) {
            notchSize = updatedTarget
        }
        if let delegate = AppDelegate.shared {
            delegate.ensureWindowSize(
                addShadowPadding(to: updatedTarget, isMinimalistic: Defaults[.enableMinimalisticUI]),
                animated: true,
                force: false
            )
        }
    }
    
    private func setupDetectorObserver() {
        // 1) Publisher for the user’s fullscreen detection setting
        let enabledPublisher = Defaults
            .publisher(.enableFullscreenMediaDetection)
            .map(\.newValue)

        // 2) For each non‑nil screen name, map to a Bool publisher for that screen's status
        let statusPublisher = $screen
            .compactMap { $0 }
            .removeDuplicates()
            .map { screenName in
                self.detector.$fullscreenStatus
                    .map { $0[screenName] ?? false }
                    .removeDuplicates()
            }
            .switchToLatest()

        // 3) Combine enabled & status, animate only on changes
        Publishers.CombineLatest(statusPublisher, enabledPublisher)
            .map { status, enabled in enabled && status }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldHide in
                withAnimation(.smooth) {
                    self?.hideOnClosed = shouldHide
                }
            }
            .store(in: &cancellables)
    }
    
    // Computed property for effective notch height
    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = NSScreen.screens.first { $0.localizedName == screen }
        let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
        return noNotchAndFullscreen ? 0 : closedNotchSize.height
    }

    func isMouseHovering(position: NSPoint = NSEvent.mouseLocation) -> Bool {
        let screenFrame = getScreenFrame(screen)
        if let frame = screenFrame {
            
            let baseY = frame.maxY - notchSize.height
            let baseX = frame.midX - notchSize.width / 2
            
            return position.y >= baseY && position.x >= baseX && position.x <= baseX + notchSize.width
        }
        
        return false
    }

    func open() {
        let targetSize = calculateDynamicNotchSize()

        let applyWindowResize: () -> Void = {
            guard let delegate = AppDelegate.shared else { return }
            delegate.ensureWindowSize(
                addShadowPadding(to: targetSize, isMinimalistic: Defaults[.enableMinimalisticUI]),
                animated: false,
                force: true
            )
        }

        if Thread.isMainThread {
            applyWindowResize()
        } else {
            DispatchQueue.main.async(execute: applyWindowResize)
        }

        notchSize = targetSize
        notchState = .open

        // Force music information update when notch is opened
        MusicManager.shared.forceUpdate()
        focusClipboardTabIfNeeded()
    }
    
    private func calculateDynamicNotchSize() -> CGSize {
        let baseSize = Defaults[.enableMinimalisticUI] ? minimalisticOpenNotchSize(isDynamicIslandMode: shouldUseDynamicIslandMode(for: screen)) : openNotchSize
        var adjustedSize = baseSize

        if coordinator.currentView == .notes || coordinator.currentView == .clipboard {
            let preferred = coordinator.notesLayoutState.preferredHeight
            adjustedSize.height = max(adjustedSize.height, preferred)
            return adjustedSize
        }

        return statsAdjustedNotchSize(
            from: adjustedSize,
            isStatsTabActive: coordinator.currentView == .stats,
            secondRowProgress: coordinator.statsSecondRowExpansion
        )
    }

    func close() {
        let targetSize = getClosedNotchSize(screen: screen)
        notchSize = targetSize
        closedNotchSize = targetSize
        notchState = .closed
        resetScrollGestureSuppression()
        resetAutoCloseSuppression()

        // Set the current view to shelf if it contains files and the user enables openShelfByDefault
        // Otherwise, if the user has not enabled openLastShelfByDefault, set the view to home
        if !ShelfStateViewModel.shared.isEmpty && Defaults[.openShelfByDefault] && !Defaults[.enableMinimalisticUI] {
            coordinator.currentView = .shelf
        } else if !coordinator.openLastTabByDefault {
            coordinator.currentView = .home
        }
    }

    func closeForLockScreen() {
        let targetSize = getClosedNotchSize(screen: screen)
        withAnimation(.none) {
            notchSize = targetSize
            closedNotchSize = targetSize
            notchState = .closed
            resetScrollGestureSuppression()
            resetAutoCloseSuppression()
        }
    }

    private var helloCloseScheduled = false

    func closeHello() {
        guard !helloCloseScheduled else { return }
        helloCloseScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            guard let self else { return }
            self.coordinator.firstLaunch = false
            withAnimation(self.animationLibrary.animation) {
                self.close()
            }
        }
    }
    
    /// 顶栏镜子按钮的动作（p13 / docs/38-home-v5-layout.md D-08 是本批的新口径）。
    ///
    /// **两条 p13 改动**（改前只起 / 停采集会话，首页块负责显示——首页块已退场）：
    /// 1. `isCameraExpanded` 是**浮动镜子**的显隐开关（`ContentView` 按它画
    ///    `MirrorFloatingPreview`）：**只要按钮被按下它就要有可见的反应**——不然用户看到的是
    ///    「点了没反应」（p13 上屏实测：摄像头没就绪时旧实现一个像素都不变）；
    /// 2. 因此「已授权 + 摄像头可用」才起会话，**其余情况照样翻标记**，
    ///    浮层里那块占位（`CameraPreviewView` 自带：未起会话显示 `Mirror` / 被拒显示 `Access Denied`，
    ///    点它一次就是授权 / 起会话）负责把原因说清楚。
    func toggleCameraPreview() {
        if isRequestingAuthorization {
            return
        }

        switch webcamManager.authorizationStatus {
        case .authorized:
            if isCameraExpanded {
                // 第二下：收起浮层并停会话（不看了就别占着摄像头）。
                isCameraExpanded = false
                webcamManager.stopSession()
                return
            }
            isCameraExpanded = true
            if webcamManager.isSessionRunning {
                // 会话已在跑（别处起的）：只把浮层放出来。
                return
            }
            if webcamManager.cameraAvailable {
                webcamManager.startSession()
            }

        case .denied, .restricted:
            // 浮层照样放出来（占位会写 `Access Denied`），随后的系统提示说明怎么开权限。
            isCameraExpanded = true
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)

                let alert = NSAlert()
                alert.messageText = "Camera Access Required"
                alert.informativeText = "Please allow camera access in System Settings."
                alert.addButton(withTitle: "OK")
                alert.runModal()

                NSApp.setActivationPolicy(.accessory)
                NSApp.deactivate()
            }

        case .notDetermined:
            isRequestingAuthorization = true
            isCameraExpanded = true
            // 与 `.denied` 那一档同一条先例：**先把应用唤到前台**再请求——非激活面板里发出的
            // 授权请求不保证压得住别的窗口（p13 上屏实测：提示没出现，用户看到的是「点了没反应」）。
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                self.webcamManager.checkAndRequestVideoAuthorization()
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.isRequestingAuthorization = false
                    NSApp.setActivationPolicy(.accessory)
                    NSApp.deactivate()
                }
            }

        default:
            break
        }
    }
}
