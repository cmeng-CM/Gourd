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

enum SneakContentType: Equatable {
    case brightness
    case volume
    case backlight
    case music
    case mic
    case battery
    case download
    case timer
    case reminder
    case recording
    case doNotDisturb
    case bluetoothAudio
    case privacy
    case lockScreen
    case capsLock
    case extensionLiveActivity(bundleID: String, activityID: String)
}

extension SneakContentType {
    static func == (lhs: SneakContentType, rhs: SneakContentType) -> Bool {
        switch (lhs, rhs) {
        case (.brightness, .brightness),
             (.volume, .volume),
             (.backlight, .backlight),
             (.music, .music),
             (.mic, .mic),
             (.battery, .battery),
             (.download, .download),
             (.timer, .timer),
             (.reminder, .reminder),
             (.recording, .recording),
             (.doNotDisturb, .doNotDisturb),
             (.bluetoothAudio, .bluetoothAudio),
             (.privacy, .privacy),
             (.lockScreen, .lockScreen),
             (.capsLock, .capsLock):
            return true
        case let (.extensionLiveActivity(lb, la), .extensionLiveActivity(rb, ra)):
            return lb == rb && la == ra
        default:
            return false
        }
    }
}

extension SneakContentType {
    var isExtensionPayload: Bool {
        if case .extensionLiveActivity = self {
            return true
        }
        return false
    }
}

struct sneakPeek {
    var show: Bool = false
    var type: SneakContentType = .music
    var value: CGFloat = 0
    var icon: String = ""
    var title: String = ""
    var subtitle: String = ""
    var accentColor: Color?
    var styleOverride: SneakPeekStyle? = nil
    var targetScreenName: String? = nil
}

enum BrowserType {
    case chromium
    case safari
}

struct ExpandedItem {
    var show: Bool = false
    var type: SneakContentType = .battery
    var value: CGFloat = 0
    var browser: BrowserType = .chromium
    var autoHideDuration: TimeInterval? = nil
}

class DynamicIslandViewCoordinator: ObservableObject {
    static let shared = DynamicIslandViewCoordinator()
    private var cancellables = Set<AnyCancellable>()
    private var hoverOpenSuppressedUntil: Date = .distantPast
    
    /// 展开面板的 tab 次序（只用来算切换方向：`tabSwitchForward`）。
    /// 其中的 `.timer` **保留但已无生产路径**：计时器接管成模块后走模块 tab（`docs/20` §做法 机制六），
    /// 而这一项还是动画方向的尺度来源（删掉会让 `.timer` 与 `.stats` 之间的方向判定换档），
    /// 因此按机制六保留、不参与运行时选中。
    private static let tabOrder: [NotchViews] = [.home, .shelf, .timer, .stats, .llmUsage, .colorPicker, .notes, .clipboard, .terminal, .extensionExperience, .module]
    
    /// Direction of the most recent tab switch (true = forward/right, false = backward/left)
    @Published var tabSwitchForward: Bool = true
    
    @Published var currentView: NotchViews = .home {
        didSet {
            if Defaults[.enableMinimalisticUI] && currentView != .home {
                currentView = .home
                return
            }
            // Track direction before SwiftUI re-renders
            let oldIdx = Self.tabOrder.firstIndex(of: oldValue) ?? 0
            let newIdx = Self.tabOrder.firstIndex(of: currentView) ?? 0
            tabSwitchForward = newIdx >= oldIdx
            handleStatsTabTransition(from: oldValue, to: currentView)
        }
    }
    
    @Published var statsSecondRowExpansion: CGFloat = 1
    @Published var notesLayoutState: NotesLayoutState = .list
    @Published var selectedExtensionExperienceID: String?
    /// 当前选中的模块 id（P1 接缝 S4）。与 `currentView == .module` 配合使用：
    /// `NotchViews` 不能带关联值（D-02），「哪个模块」只能存在这一层。
    @Published var selectedModuleID: String?
    
    
    @AppStorage("firstLaunch") var firstLaunch: Bool = true
    @AppStorage("showWhatsNew") var showWhatsNew: Bool = true
    @AppStorage("musicLiveActivityEnabled") var musicLiveActivityEnabled: Bool = true
    @AppStorage("timerLiveActivityEnabled") var timerLiveActivityEnabled: Bool = true

    @Default(.enableTimerFeature) private var enableTimerFeature
    @Default(.timerDisplayMode) private var timerDisplayMode
    
    @AppStorage("alwaysShowTabs") var alwaysShowTabs: Bool = true {
        didSet {
            if !alwaysShowTabs {
                openLastTabByDefault = false
                if TrayDrop.shared.isEmpty || !Defaults[.openShelfByDefault] {
                    currentView = .home
                }
            }
        }
    }
    
    @AppStorage("openLastTabByDefault") var openLastTabByDefault: Bool = false {
        didSet {
            if openLastTabByDefault {
                alwaysShowTabs = true
            }
        }
    }
    
    @AppStorage("hudReplacement") var hudReplacement: Bool = true
    
    @AppStorage("preferred_screen_name") var preferredScreen = NSScreen.main?.localizedName ?? "Unknown" {
        didSet {
            selectedScreen = preferredScreen
            NotificationCenter.default.post(name: Notification.Name.selectedScreenChanged, object: nil)
        }
    }
    
    @Published var selectedScreen: String = NSScreen.main?.localizedName ?? "Unknown"

    @Published var optionKeyPressed: Bool = true
    private let extensionNotchExperienceManager = ExtensionNotchExperienceManager.shared
    
    private init() {
        selectedScreen = preferredScreen
        Defaults.publisher(.timerDisplayMode)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.handleTimerDisplayModeChange(change.newValue)
            }
            .store(in: &cancellables)

        Defaults.publisher(.enableTimerFeature)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.handleTimerFeatureToggle(change.newValue)
            }
            .store(in: &cancellables)

        Defaults.publisher(.enableMinimalisticUI)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.handleMinimalisticModeChange(change.newValue)
            }
            .store(in: &cancellables)

        extensionNotchExperienceManager.$activeExperiences
            .receive(on: DispatchQueue.main)
            .sink { [weak self] experiences in
                self?.handleExtensionExperienceSnapshot(experiences)
            }
            .store(in: &cancellables)

        Defaults.publisher(.enableThirdPartyExtensions)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleExtensionFeatureToggle()
            }
            .store(in: &cancellables)

        Defaults.publisher(.enableExtensionNotchExperiences)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleExtensionFeatureToggle()
            }
            .store(in: &cancellables)

        Defaults.publisher(.enableExtensionNotchTabs)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleExtensionFeatureToggle()
            }
            .store(in: &cancellables)

        handleExtensionExperienceSnapshot(extensionNotchExperienceManager.activeExperiences)

        // Observe all tab-affecting settings to enforce minimum notch width
        Publishers.MergeMany(
            Defaults.publisher(.showStandardMediaControls).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.showCalendar).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.showMirror).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.dynamicShelf).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableTimerFeature).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.timerDisplayMode).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableStatsFeature).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableNotes).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableClipboardManager).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.clipboardDisplayMode).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableTerminalFeature).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.enableMinimalisticUI).map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
        .sink { _ in
            enforceMinimumNotchWidth()
        }
        .store(in: &cancellables)

        // Enforce minimum width on launch for existing configurations
        enforceMinimumNotchWidth()
    }

    var isHoverOpenSuppressed: Bool {
        Date() < hoverOpenSuppressedUntil
    }

    func suppressHoverOpen(for duration: TimeInterval = 0.35) {
        hoverOpenSuppressedUntil = Date().addingTimeInterval(max(0, duration))
    }

    private func handleStatsTabTransition(from oldValue: NotchViews, to newValue: NotchViews) {
        guard oldValue != newValue else { return }
        if newValue == .stats && Defaults[.enableStatsFeature] {
            statsSecondRowExpansion = 1
        }
    }

    private func handleTimerDisplayModeChange(_ mode: TimerDisplayMode) {
        // 判据走 `isTimerSurfaceSelected()`：接管后计时器页是**模块 tab**（docs/20 §做法 机制六），
        // 只比 `currentView == .timer` 的话「显示方式切成 popover 时把视图收回 Home」在模块路径下失效
        // （切走显示方式后视图停在计时器——本任务的失败信号之一）。
        guard mode == .popover, isTimerSurfaceSelected() else { return }
        withAnimation(.smooth) {
            currentView = .home
        }
    }

    private func handleTimerFeatureToggle(_ isEnabled: Bool) {
        // 同上：上游总开关关掉时，计时器页（模块 tab）也要收回 Home。
        guard !isEnabled, isTimerSurfaceSelected() else { return }
        withAnimation(.smooth) {
            currentView = .home
        }
    }

    private func handleMinimalisticModeChange(_ isEnabled: Bool) {
        guard isEnabled else { return }
        if currentView != .home {
            withAnimation(.smooth) {
                currentView = .home
            }
        }
    }

    private func handleExtensionExperienceSnapshot(_ experiences: [ExtensionNotchExperiencePayload]) {
        guard extensionTabsAllowed else {
            selectedExtensionExperienceID = nil
            resetExtensionViewIfNeeded()
            return
        }

        let tabCapablePayloads = experiences.filter { $0.descriptor.tab != nil }
        guard !tabCapablePayloads.isEmpty else {
            selectedExtensionExperienceID = nil
            resetExtensionViewIfNeeded()
            return
        }

        if let currentID = selectedExtensionExperienceID,
           tabCapablePayloads.contains(where: { $0.descriptor.id == currentID }) {
            return
        }

        selectedExtensionExperienceID = tabCapablePayloads.first?.descriptor.id
    }

    private func handleExtensionFeatureToggle() {
        handleExtensionExperienceSnapshot(extensionNotchExperienceManager.activeExperiences)
    }

    private func resetExtensionViewIfNeeded() {
        guard currentView == .extensionExperience else { return }
        withAnimation(.smooth) {
            currentView = .home
        }
    }

    private var extensionTabsAllowed: Bool {
        Defaults[.enableThirdPartyExtensions]
        && Defaults[.enableExtensionNotchExperiences]
        && Defaults[.enableExtensionNotchTabs]
    }
    
    func toggleSneakPeek(
        status: Bool,
        type: SneakContentType,
        duration: TimeInterval = 1.5,
        value: CGFloat = 0,
        icon: String = "",
        title: String = "",
        subtitle: String = "",
        accentColor: Color? = nil,
        styleOverride: SneakPeekStyle? = nil,
        onScreen targetScreen: NSScreen? = nil
    ) {
        let resolvedDuration: TimeInterval
        switch type {
        case .timer:
            resolvedDuration = 10
        case .reminder:
            resolvedDuration = Defaults[.reminderSneakPeekDuration]
        case .extensionLiveActivity:
            resolvedDuration = duration
        default:
            resolvedDuration = duration
        }
        sneakPeekDuration = resolvedDuration
        let bypassedTypes: [SneakContentType] = [.music, .timer, .reminder, .bluetoothAudio]
        
        // Check if it's an extension type
        let isExtensionType: Bool
        if case .extensionLiveActivity = type {
            isExtensionType = true
        } else {
            isExtensionType = false
        }
        
        if !isExtensionType && !bypassedTypes.contains(type) && !Defaults[.enableSystemHUD] {
            return
        }
        DispatchQueue.main.async {
            // Single write so `sneakPeek.didSet` (which schedules the auto-hide)
            // fires once, not once per field — the per-field writes raced the hide
            // Task and could wedge `show == true` with no pending hide.
            var updated = self.sneakPeek
            updated.show = status
            updated.type = type
            updated.value = value
            updated.icon = icon
            updated.title = title
            updated.subtitle = subtitle
            updated.accentColor = accentColor
            updated.styleOverride = styleOverride
            updated.targetScreenName = targetScreen?.localizedName
            withAnimation(.smooth(duration: 0.3)) {
                self.sneakPeek = updated
            }
        }
    }
    
    private var sneakPeekDuration: TimeInterval = 1.5
    private var sneakPeekTask: Task<Void, Never>?

    // Helper function to manage sneakPeek timer using Swift Concurrency
    private func scheduleSneakPeekHide(after duration: TimeInterval) {
        sneakPeekTask?.cancel()
        
        // Don't schedule auto-hide if duration is infinite (for persistent indicators like Caps Lock)
        guard duration.isFinite else { return }

        sneakPeekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self = self, !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    // Hide the sneak peek with the correct type that was showing
                    self.toggleSneakPeek(status: false, type: self.sneakPeek.type)
                    self.sneakPeekDuration = 1.5
                }
            }
        }
    }
    
    @Published var sneakPeek: sneakPeek = .init() {
        didSet {
            if sneakPeek.show {
                scheduleSneakPeekHide(after: sneakPeekDuration)
            } else {
                sneakPeekTask?.cancel()
            }
        }
    }
    
    func toggleExpandingView(
        status: Bool,
        type: SneakContentType,
        value: CGFloat = 0,
        browser: BrowserType = .chromium,
        autoHideDuration: TimeInterval? = nil
    ) {
        Task { @MainActor in
            withAnimation(.smooth) {
                self.expandingView.show = status
                self.expandingView.type = type
                self.expandingView.value = value
                self.expandingView.browser = browser
                self.expandingView.autoHideDuration = autoHideDuration
            }
        }
    }

    private var expandingViewTask: Task<Void, Never>?
    
    @Published var expandingView: ExpandedItem = .init() {
        didSet {
            if expandingView.show {
                expandingViewTask?.cancel()
                // Only auto-hide for battery, not for downloads (DownloadManager handles that)
                if expandingView.type != .download {
                    let duration = expandingView.autoHideDuration ?? 3
                    expandingViewTask = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(duration))
                        guard let self = self, !Task.isCancelled else { return }
                        self.toggleExpandingView(status: false, type: .battery)
                    }
                }
            } else {
                expandingViewTask?.cancel()
            }
        }
    }

    
    func showEmpty() {
        currentView = .home
    }

    /// 选中某个模块并切到模块视图（P1 接缝 S4）。
    ///
    /// 必须**同时**设 `selectedModuleID` 与 `currentView`：只设后者会让 `ModuleHostView`
    /// 拿不到模块 id 而渲染 EmptyView（docs/13 S1 ④ 的失败模式）。
    func selectModule(_ id: String) {
        selectedModuleID = id
        currentView = .module
    }

    /// 「计时器这个页面此刻是不是被选中」——计时器的第二入口（悬浮聚焦 / 点预设）与它自己的
    /// 250pt 高度档都问这一条（`docs/20-component-page.md` §做法 机制六，D-11）。
    ///
    /// 接管（T2）后计时器页由**模块 tab** 渲染（`TimerModule`），因此判据有两段：
    /// - `.timer`：批前的旧路径——枚举成员与 `case .timer: NotchTimerView()` 分支按机制六**保留**
    ///   （删除会牵动 `NotchViews` 的哈希与 `tabOrder` 的动画方向语义），但三条上游生产路径
    ///   （悬浮聚焦 / 点预设 / `startCustomTimer`）已全部改走 `selectModule(TimerModule.moduleID)`，
    ///   故这一档今天只为「老路径 / 测试」而留；
    /// - `.module` + `selectedModuleID == TimerModule.moduleID`：今天唯一的生产形态。
    ///
    /// 只判 `currentView == .module` 是不够的：同一个 `.module` 下可以有别的模块 tab
    /// （与 `TabSelectionView.isSelected` 同一口径）。
    func isTimerSurfaceSelected() -> Bool {
        currentView == .timer || (currentView == .module && selectedModuleID == TimerModule.moduleID)
    }
    
    // MARK: - Clipboard Management
    @Published var shouldToggleClipboardPopover: Bool = false
    
    func toggleClipboardPopover() {
        // Toggle the published property to trigger UI updates
        shouldToggleClipboardPopover.toggle()
    }
}
