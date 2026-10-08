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
            // **宿主门槛键**（p5-home-blocks / T5 修复 P2）：被门槛键排除的视图**不许被选中**——
            // 选中的那一刻就落回首页。挡在这里而不只挡在「键变化」那一路，是因为把面板开到某个
            // 宿主视图的入口不止设置页那一个（`openShelfByDefault` 会在打开面板时直接设 `.shelf`、
            // 剪贴板快捷键直接设 `.notes` / `.clipboard`）——键关着时它们同样会把面板开到一个
            // 已经关掉的元素上。判据是纯函数 `isHostSurfaceGatedOff(_:offKeyNames:)`。
            if Self.isHostSurfaceGatedOff(currentView, offKeyNames: Self.hostSurfaceOffKeyNames) {
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

        // 宿主门槛键（p5-home-blocks / T5 修复 P2）：四个宿主元素（暂存器 / 终端 / 剪贴板 / 取色器）
        // 的键关掉时，当前若正停在被它门控的视图上就收回首页——同扩展 tab 那条
        // `resetExtensionViewIfNeeded()` 的先例（`ContentView` 的 switch 只认视图 id、不认门槛键）。
        // 逐键订阅而不是合并成一条：将来哪一条要单独处理时不必先拆管道。
        for gate in Self.hostSurfaceGateViews {
            Defaults.publisher(gate.key)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.resetHostSurfaceViewIfNeeded()
                }
                .store(in: &cancellables)
        }

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

    // MARK: - 宿主元素的视图归一化（p5-home-blocks / T5 修复 P2）

    /// 一条**宿主元素的视图映射**：门槛键 + 它关掉时**不能继续停留 / 不能再被选中**的视图。
    ///
    /// 视图 id 取自「谁在读这个键」（`docs/29` §机制三那张枚举表的宿主行）：
    /// - 暂存器 `dynamicShelf` → `.shelf`（`TabSelectionView` 的 Shelf tab + 拖拽落点 `dragDetector`）；
    /// - 终端 `enableTerminalFeature` → `.terminal`；
    /// - 剪贴板 `enableClipboardManager` → `.notes` 与 `.clipboard`（面板 tab 走 `.notes`、
    ///   刘海图标 `notchTab` 那一路走 `.clipboard`——两条支路都是剪贴板今天的形态）；
    /// - 取色器 `enableColorPickerFeature` → `.colorPicker`。
    ///
    /// **计时器不在表里**：它是模块行不是宿主行，它的收回走既有那条
    /// `handleTimerFeatureToggle()`（判据 `isTimerSurfaceSelected()`），两处不重复。
    struct HostSurfaceGate {
        /// 门槛键——与设置页 `ModuleSettingsSection.hostPanelRows` 那四条同一批键。
        let key: Defaults.Key<Bool>
        /// 该键关掉时不允许停留的视图（`ContentView` 的 `switch coordinator.currentView` 分支）。
        let views: [NotchViews]

        /// 稳定 id = 上游键名（与 `HostSurfaceRow.id` 同口径：用例两侧按它对键）。
        var id: String { key.name }
    }

    /// **不是 `private`**：用例拿它与设置页那四条宿主行对键（同一个集合的两个端点）。
    /// `.notes` **不在任何一条的 `views` 里**：它与 `.clipboard` 共用同一个视图（`NotchNotesView`
    /// 自己按 `enableNotes` 决定画哪一半），门槛是「两个键都关着」这个**复合**条件，
    /// 由 `isHostSurfaceGatedOff` 单独判（2026-10-08 恢复笔记时从剪贴板那条里摘出来的）。
    static let hostSurfaceGateViews: [HostSurfaceGate] = [
        HostSurfaceGate(key: .dynamicShelf, views: [.shelf]),
        HostSurfaceGate(key: .enableTerminalFeature, views: [.terminal]),
        HostSurfaceGate(key: .enableClipboardManager, views: [.clipboard]),
        HostSurfaceGate(key: .enableColorPickerFeature, views: [.colorPicker]),
    ]

    /// 该视图是否被某个**已关掉**的宿主门槛键排除（纯函数：吃「哪些键关着」的名字集合，不读偏好
    /// ——用例拿几个字面量就能把四条映射各钉一条，与 `ModuleSurfaceGroup.hasOtherSurface` 同款）。
    static func isHostSurfaceGatedOff(_ view: NotchViews, offKeyNames: Set<String>) -> Bool {
        // `.notes` 是笔记与剪贴板共用的视图：只有两个键**都**关着才收回。只看剪贴板那一个键的话，
        // 「笔记开 + 剪贴板关」的用户一进 notes tab 就会被弹回首页。
        if view == .notes {
            return offKeyNames.contains(Defaults.Keys.enableNotes.name)
                && offKeyNames.contains(Defaults.Keys.enableClipboardManager.name)
        }
        return hostSurfaceGateViews.contains { gate in
            offKeyNames.contains(gate.key.name) && gate.views.contains(view)
        }
    }

    /// 此刻**关着**的宿主门槛键名（读偏好的那一半，只出现在这一处）。
    ///
    /// `enableNotes` 不在门禁表的四条里（它只参与 `.notes` 那个复合门槛），但必须**一并报进来**——
    /// 否则 `isHostSurfaceGatedOff(.notes, ...)` 里那个 `contains(enableNotes)` 恒为假，笔记关掉也收不回。
    private static var hostSurfaceOffKeyNames: Set<String> {
        var names = Set(hostSurfaceGateViews.filter { !Defaults[$0.key] }.map(\.key.name))
        if !Defaults[.enableNotes] { names.insert(Defaults.Keys.enableNotes.name) }
        return names
    }

    /// 当前视图被它自己的门槛键排除时收回首页——**「已经停在这个视图上，再把键关掉」那一路**
    /// （订阅四个键的变更触发）；「被排除的视图不许被选中」那一路在 `currentView` 的 `didSet` 里。
    /// 先例是扩展 tab 的 `resetExtensionViewIfNeeded()`（同为「关了就得从面板上消失」）。
    private func resetHostSurfaceViewIfNeeded() {
        guard Self.isHostSurfaceGatedOff(currentView, offKeyNames: Self.hostSurfaceOffKeyNames) else { return }
        withAnimation(.smooth) {
            currentView = .home
        }
    }
    
    // MARK: - Clipboard Management
    @Published var shouldToggleClipboardPopover: Bool = false
    
    func toggleClipboardPopover() {
        // Toggle the published property to trigger UI updates
        shouldToggleClipboardPopover.toggle()
    }
}
