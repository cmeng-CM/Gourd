// Modified for Gourd (2026-10-10)
// Copyright (C) 2026 Gourd Contributors
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
//

//
//  LyricsOverlayWindowManager.swift
//  Gourd 音乐 · 桌面歌词悬浮层的**窗口与显隐**（p10 悬浮层批次 / T3）
//
//  歌词自 docs/35-desktop-lyrics-overlay.md 起不再画在灵动岛面板里，而是由 Gourd 自绘一层
//  桌面悬浮窗（只在**岛不展开**时出现）。本文件管那一层的**窗口生命周期、锚点与显隐**：
//  一个无边框、非激活、置顶、随所有空间显示的 `NSPanel`，装着 `LyricsOverlayView`。
//
//  **窗口配方**：常量组逐条照抄 `FlyoutWindowPresenter.ensureWindow`（同一种窗口语义只留一份
//  配方），但**不复用它的本体**——它的定位与动画是「贴着岛」的专用逻辑（备选 3），歌词层要
//  自由位置 + 拖拽 + 位置记忆。多出来的窗口属性只有一处：`ignoresMouseEvents` 跟着
//  `lyricsOverlayLocked`（锁定档 = 完全鼠标穿透）。
//
//  **显隐判据**：只有一条——`LyricsOverlayRules.shouldShow(...)`（总开关 && 有活跃音乐会话 &&
//  有真实歌词行 && 岛不展开 && 屏幕未锁）。`hasRealLyrics` 读 `!syncedLyrics.isEmpty`：既有
//  链路的两种占位态（「Loading lyrics...」/「No lyrics found」）都伴随空数组，所以不去比占位串。
//  `sync()` 幂等：同状态重复调用不重复 orderFront / setFrame（同一帧里还有 300ms 的歌词推进，
//  这个热路径不能每次动窗口）。
//
//  **观察链**：`MusicManager` 的 `syncedLyrics` / `currentLyricIndex` / `isPlaying` 三个
//  `@Published`＋`vm.notchState` / `vm.screen`＋`NSApplication.didChangeScreenParametersNotification`
//  （屏参变化时 `screen` 的 localizedName 可能不变，光靠 `$screen` 接不到）＋
//  `LockScreenManager.$isLocked`＋`enableLyrics` 与 9 枚显示档键（共 10 条 `Defaults.publisher`）；
//  任一变化调 `sync()`（不自建第二套状态，docs/35 §做法 机制一）。
//  `vm` **由启动路径注入**（`configure(viewModel:)`，与 `LockScreenManager.configure(viewModel:)`
//  同口径）——不走 `AppDelegate.shared`：那条路在本 App 恒 nil（见属性注释），判据便永远为假。
//
//  **锚点**：岛所在屏（`DynamicIslandViewModel.screen` 的 localizedName 匹配，回落
//  `NSScreen.main`，与 `FlyoutWindowPresenter.resolveScreen` 同口径）的 `frame.midX` 居中、
//  岛底边下方一档间距（8pt），再叠加 `lyricsOverlayOffsetX/Y`（AppKit 屏幕坐标系的位移，
//  向下拖 = y 变小 = 负偏移）。屏参变化 / `screen` 变化时重算锚点、偏移原样保留。
//
//  **拖拽保护**：拖拽进行中（`isDragging`）`sync()` **只跳过重排**——位置由 `dragChanged`
//  直接驱动，此时按「锚点 + 已存偏移」设帧会把拖到一半的窗口拉回上一次落点（播放中每 ~300ms
//  一次行切换的 sync 都会触发），靠下一次 `dragChanged` 弹回来。显隐判断与 `rootView`
//  更新不跳过：拖拽中歌词照常推进、需要藏时照常藏。
//

#if os(macOS)
import AppKit
import Combine
import Defaults
import SwiftUI
import os

@MainActor
final class LyricsOverlayWindowManager: ObservableObject {

    static let shared = LyricsOverlayWindowManager()

    /// 岛底边到歌词层顶边的间距（docs/35「岛下方一档间距」）。取 8 与
    /// `FlyoutFrameCalculator.screenInset` / 岛 hover 的 8pt 档同值。
    private static let anchorSpacing: CGFloat = 8

    /// 位置夹回时的日志（`log show --info --predicate 'subsystem == "com.cmeng.gourd.music"'`）。
    private let log = os.Logger(subsystem: "com.cmeng.gourd.music", category: "lyrics-overlay")

    private var window: NSPanel?
    private var hostingView: NSHostingView<LyricsOverlayView>?
    private var cancellables = Set<AnyCancellable>()
    private var isStarted = false

    /// 当前锚点（窗口左上角、未叠加偏移，已取整）——拖拽把落点折算成相对它的偏移。
    private var anchorOrigin: CGPoint?
    /// 拖拽起点（窗口左上角）：拖动期间窗口 origin = 起点 + 位移。
    private var dragStartOrigin: CGPoint?
    /// 拖拽进行中：`sync()` 此时**只跳过重排**（位置由 `dragChanged` 直接驱动），
    /// 否则播放中每 ~300ms 一次的行切换 sync 都会把窗口按「锚点 + **已存**偏移」拉回去、
    /// 靠下一次 `dragChanged` 弹回来（拖拽抖动）。显隐判断与 `rootView` 更新不受它影响。
    private var isDragging = false

    private init() {}

    /// 应用主 VM（岛状态与所在屏）——**由启动路径注入**（`configure(viewModel:)`，与
    /// `LockScreenManager.configure(viewModel:)` 同一口径）。`weak`：VM 由 App 侧持有。
    ///
    /// 为什么不走 `AppDelegate.shared?.vm`：`@NSApplicationDelegateAdaptor` 包的那一层不落在
    /// `NSApplication.shared.delegate` 上，那条路径在本 App 里**恒为 nil**（2026-09-29 实测注释见
    /// `ContentView.swift:1191`；2026-10-10 上屏取证再证 `vmNil=true appDelegateNil=true`）。
    /// 取不到 VM → `islandClosed` 恒 false → 悬浮层永不建窗（终审 Critical）。
    private weak var viewModel: DynamicIslandViewModel?
    /// `notchState` / `screen` 两条订阅是否已装：`configure` 与 `start` 都可能触发装配，
    /// 用它在整个生命周期里只装一份（重复注入不叠订阅）。
    private var viewModelObserversAttached = false

    // MARK: - 启动

    /// 注入应用主 VM。**先注入、再 `start()`**（本仓唯一调用点：
    /// `DynamicIslandApp.applicationDidFinishLaunching`，`setupAudioTapMusicObservers()` 旁）。
    /// 注入后立刻 `sync()` 一次——否则要等到下一次状态变化才建窗；若 `start()` 已经跑过，
    /// 这里顺带补装 VM 的两条订阅。vm 未注入时 `sync()` 按「不显示」处理（判据取不到就不显示）。
    func configure(viewModel: DynamicIslandViewModel) {
        self.viewModel = viewModel
        observeViewModelStateChanges()
        sync()
    }

    /// 装观察链并立刻同步一次。重复调用是空操作（不叠第二份订阅）。
    /// 调用点：`DynamicIslandApp.applicationDidFinishLaunching`（`setupAudioTapMusicObservers()` 旁），
    /// 在 `configure(viewModel:)` 之后。
    func start() {
        guard !isStarted else { return }
        isStarted = true
        observeStateChanges()
        sync()
    }

    private func observeStateChanges() {
        let music = MusicManager.shared
        var sources: [AnyPublisher<Void, Never>] = [
            music.$syncedLyrics.map { _ in () }.eraseToAnyPublisher(),
            music.$currentLyricIndex.map { _ in () }.eraseToAnyPublisher(),
            music.$isPlaying.map { _ in () }.eraseToAnyPublisher(),
            LockScreenManager.shared.$isLocked.map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
                .map { _ in () }.eraseToAnyPublisher(),
        ]

        // 总开关 + 9 枚显示档键（字体 / 行数 / 透明度 / 颜色模式 / 自定义色 / 高亮 / 锁定 / 偏移 X / 偏移 Y）
        // ——共 10 条 publisher。
        sources.append(Defaults.publisher(.enableLyrics, options: []).map { _ in () }.eraseToAnyPublisher())
        sources.append(Defaults.publisher(.lyricsFontSize, options: []).map { _ in () }.eraseToAnyPublisher())
        sources.append(Defaults.publisher(.lyricsLineCount, options: []).map { _ in () }.eraseToAnyPublisher())
        sources.append(Defaults.publisher(.lyricsOpacity, options: []).map { _ in () }.eraseToAnyPublisher())
        sources.append(Defaults.publisher(.lyricsColorMode, options: []).map { _ in () }.eraseToAnyPublisher())
        sources.append(Defaults.publisher(.lyricsCustomColorHex, options: []).map { _ in () }.eraseToAnyPublisher())
        sources.append(Defaults.publisher(.lyricsHighlightCurrent, options: []).map { _ in () }.eraseToAnyPublisher())
        sources.append(Defaults.publisher(.lyricsOverlayLocked, options: []).map { _ in () }.eraseToAnyPublisher())
        sources.append(Defaults.publisher(.lyricsOverlayOffsetX, options: []).map { _ in () }.eraseToAnyPublisher())
        sources.append(Defaults.publisher(.lyricsOverlayOffsetY, options: []).map { _ in () }.eraseToAnyPublisher())

        Publishers.MergeMany(sources)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.sync() }
            .store(in: &cancellables)

        observeViewModelStateChanges()
    }

    /// `vm.notchState` / `vm.screen` 两条订阅（VM 由 `configure(viewModel:)` 注入；与既有链同口径，
    /// 任一变化 `sync()`）。单列的理由：注入可能发生在 `start()` 之前或之后，两处都调它，
    /// `viewModelObserversAttached` 保证只装一份；vm 未注入时是空操作（不崩）。
    private func observeViewModelStateChanges() {
        guard !viewModelObserversAttached, let viewModel else { return }
        viewModelObserversAttached = true

        Publishers.MergeMany(
            viewModel.$notchState.map { _ in () }.eraseToAnyPublisher(),
            viewModel.$screen.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.sync() }
        .store(in: &cancellables)
    }

    // MARK: - 显隐（幂等）

    /// 按判据显示 / 隐藏，按「锚点 + 偏移」布局。判据、渲染输入与显示档都在这里现读，
    /// 所以改任一档当场生效（≤1 次重绘）。
    func sync() {
        let music = MusicManager.shared
        let mapped = LyricsOverlayRules.displayLines(synced: music.syncedLyrics)
        // 显隐的唯一判据（五输入）。VM 未注入（启动路径漏调 `configure(viewModel:)`）时
        // `islandClosed` 落 false——取不到就不显示，不崩；下面的 `guard let viewModel`
        // 再把「该显示但没有 VM 可用」的情形一并兜成隐藏。
        let shouldShow = LyricsOverlayRules.shouldShow(
            enableLyrics: Defaults[.enableLyrics],
            hasActiveSession: music.hasActiveSession,
            hasRealLyrics: !music.syncedLyrics.isEmpty,
            islandClosed: viewModel?.notchState == .closed,
            screenLocked: LockScreenManager.shared.isLocked
        )

        guard shouldShow else {
            // 总开关关掉时整窗退役（register 的对称面 unregister 在这里）；
            // 其余「暂时不该显示」的情形只 orderOut，留着窗口给下一次显示。
            if !Defaults[.enableLyrics] {
                tearDownWindow()
            } else {
                hideIfNeeded()
            }
            return
        }

        guard let viewModel, let screen = resolveScreen(from: viewModel) else {
            hideIfNeeded()
            return
        }

        let locked = Defaults[.lyricsOverlayLocked]

        let content = LyricsOverlayView(
            lines: mapped.lines,
            isSynced: mapped.isSynced,
            // 当前行（行窗口的居中锚）与「高亮当前行」档分开喂：关掉高亮只改字重与明暗，
            // 行窗口仍跟着播放推进（否则会永远停在第一行）。
            highlightIndex: LyricsOverlayRules.highlightIndex(
                isSynced: mapped.isSynced,
                currentIndex: music.currentLyricIndex
            ),
            emphasizeCurrent: Defaults[.lyricsHighlightCurrent],
            fontSize: CGFloat(Defaults[.lyricsFontSize]),
            lineCount: Defaults[.lyricsLineCount],
            opacity: Defaults[.lyricsOpacity],
            colorMode: Defaults[.lyricsColorMode],
            customHex: Defaults[.lyricsCustomColorHex],
            albumArtColor: music.avgColor,
            locked: locked,
            onToggleLock: { Defaults[.lyricsOverlayLocked].toggle() },
            onResetPosition: { [weak self] in self?.resetOffset() },
            onCloseLyrics: { Defaults[.enableLyrics] = false },
            onDragChanged: { [weak self] translation in self?.dragChanged(translation) },
            onDragEnded: { [weak self] translation in self?.dragEnded(translation) }
        )

        let hosting = ensureHostingView()
        hosting.rootView = content

        let window = ensureWindow()
        if window.contentView !== hosting {
            window.contentView = hosting
        }
        window.ignoresMouseEvents = locked

        // 拖拽进行中只跳过重排：窗口位置这段由 `dragChanged` 直接驱动，`sync()` 若按
        // 「锚点 + 已存偏移」设帧会把拖到一半的窗口拉回上一次落点（播放中每 ~300ms 一次
        // `$currentLyricIndex` 的 sync 都会触发）。上面的显隐判断与本行的 `rootView`
        // 更新都不跳过——拖拽时歌词照常随播放推进，只是位置不动。
        guard !isDragging else { return }

        let size = measuredSize(for: hosting)
        let origin = anchorOrigin(on: screen, windowSize: size, viewModel: viewModel)
        self.anchorOrigin = origin
        apply(origin: origin, size: size, to: window)
    }

    private func hideIfNeeded() {
        dragStartOrigin = nil
        anchorOrigin = nil
        isDragging = false
        guard let window, window.isVisible else { return }
        window.orderOut(nil)
    }

    // MARK: - 位置（拖动与偏移）

    /// 拖拽落点写入偏移（两枚 `Defaults` 键）；写盘触发的 `sync()` 会按「锚点 + 新偏移」
    /// 重排——落点与重排结果逐位相同（偏移是取整后的差值），所以不会回跳。
    func commitOffset(_ offset: CGSize) {
        Defaults[.lyricsOverlayOffsetX] = Double(offset.width)
        Defaults[.lyricsOverlayOffsetY] = Double(offset.height)
    }

    /// 「重置位置」：偏移回 0 / 0（岛下方居中）。
    func resetOffset() {
        commitOffset(.zero)
    }

    /// 拖拽进行中（视图 `DragGesture.onChanged`）：窗口原点 = 拖拽起点 + 位移，
    /// 并竖起 `isDragging`（`sync()` 从这一刻起不重排）。SwiftUI 的 y 向下，AppKit 的窗口
    /// y 向上，所以高度取反。
    func dragChanged(_ translation: CGSize) {
        guard !Defaults[.lyricsOverlayLocked], let window, anchorOrigin != nil else { return }
        isDragging = true
        let start = dragStartOrigin ?? window.frame.origin
        dragStartOrigin = start
        let origin = CGPoint(
            x: (start.x + translation.width).rounded(),
            y: (start.y - translation.height).rounded()
        )
        if window.frame.origin != origin {
            window.setFrameOrigin(origin)
        }
    }

    /// 拖拽结束（视图 `DragGesture.onEnded`）：把落点折算成相对锚点的偏移并落盘，随后
    /// **主动完整 sync() 一次**——按新偏移归位（写盘触发的 sync 与这次同帧幂等，不重复动窗）。
    func dragEnded(_ translation: CGSize) {
        guard let window else { return }
        dragChanged(translation)
        let origin = window.frame.origin
        dragStartOrigin = nil
        guard let anchorOrigin else {
            isDragging = false
            return
        }
        // 先落旗再写盘：`Defaults.publisher` 触发的 sync 必须是「完整」的那一次。
        isDragging = false
        commitOffset(CGSize(width: origin.x - anchorOrigin.x, height: origin.y - anchorOrigin.y))
        sync()
    }

    // MARK: - 窗口

    /// 窗口配方逐条照抄 `FlyoutWindowPresenter.ensureWindow` 的常量组（见文件头）。
    private func ensureWindow() -> NSPanel {
        if let window {
            return window
        }

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.ignoresMouseEvents = Defaults[.lyricsOverlayLocked]
        window.isMovable = false
        window.alphaValue = 1

        // 隐私口径（D-11）：交给 manager 逐窗刷 `sharingType`（它自己订阅
        // `hideDynamicIslandFromScreenCapture`），本层不另写一份判断。
        ScreenCaptureVisibilityManager.shared.register(window, scope: .entireInterface)

        self.window = window
        return window
    }

    /// 整窗退役（总开关关掉时）：unregister + 断掉内容视图，下次显示重新建。
    private func tearDownWindow() {
        guard let window else { return }
        ScreenCaptureVisibilityManager.shared.unregister(window)
        window.contentView = nil
        window.orderOut(nil)
        hostingView = nil
        self.window = nil
        dragStartOrigin = nil
        anchorOrigin = nil
        isDragging = false
    }

    /// 只建一次 `NSHostingView`（`rootView` 每次 `sync()` 整体重建，docs/35 §做法 机制一）。
    private func ensureHostingView() -> NSHostingView<LyricsOverlayView> {
        if let hostingView {
            return hostingView
        }
        let view = NSHostingView(rootView: LyricsOverlayView.empty)
        hostingView = view
        return view
    }

    private func measuredSize(for hosting: NSHostingView<LyricsOverlayView>) -> CGSize {
        let size = hosting.fittingSize
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    /// 幂等应用：同帧 + 已可见 → 什么都不做（300ms 的歌词推进不走 orderFront 路径）。
    private func apply(origin: CGPoint, size: CGSize, to window: NSPanel) {
        let frame = NSRect(origin: origin, size: size)
        if window.frame != frame {
            window.setFrame(frame, display: true)
        }
        if !window.isVisible {
            window.orderFrontRegardless()
        }
    }

    // MARK: - 屏幕与锚点

    /// 屏取 `DynamicIslandViewModel.screen` 的 localizedName 匹配（与 `FlyoutWindowPresenter`
    /// 同口径），回落 `NSScreen.main`。
    private func resolveScreen(from viewModel: DynamicIslandViewModel) -> NSScreen? {
        if let screenName = viewModel.screen,
           let targetScreen = NSScreen.screens.first(where: { $0.localizedName == screenName }) {
            return targetScreen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    /// 锚点 = 该屏 `frame.midX` 居中、岛底边（`frame.maxY − effectiveClosedNotchHeight`）
    /// 下方一档间距，再叠加两个偏移键；结果**夹回屏内**（见 `clampedOrigin`）。返回窗口左上角
    /// （AppKit 坐标，取整）。
    private func anchorOrigin(on screen: NSScreen, windowSize: CGSize, viewModel: DynamicIslandViewModel) -> CGPoint {
        let screenFrame = screen.frame
        let islandBottom = screenFrame.maxY - viewModel.effectiveClosedNotchHeight
        let x = screenFrame.midX - windowSize.width / 2 + CGFloat(Defaults[.lyricsOverlayOffsetX])
        let y = islandBottom - Self.anchorSpacing - windowSize.height + CGFloat(Defaults[.lyricsOverlayOffsetY])
        let origin = CGPoint(x: x.rounded(), y: y.rounded())
        let clamped = Self.clampedOrigin(origin, windowSize: windowSize, screenFrame: screenFrame)
        if clamped != origin {
            log.info("歌词层位置夹回屏内：\(Int(origin.x), privacy: .public),\(Int(origin.y), privacy: .public) → \(Int(clamped.x), privacy: .public),\(Int(clamped.y), privacy: .public)（偏移 \(Int(Defaults[.lyricsOverlayOffsetX]), privacy: .public),\(Int(Defaults[.lyricsOverlayOffsetY]), privacy: .public)）")
        }
        return clamped
    }

    /// 整窗必须与目标屏**至少相交 `minimumVisibleExtent`**（两轴各自算）——不够就夹回来。
    ///
    /// 为什么需要这道闸（2026-10-16 实测）：位置 = 锚点 + 用户拖拽写下的两个偏移键，而偏移是**自由
    /// 值**、还会跟着屏幕布局变化重新套用。用户那次把歌词层拖到了 `偏移 (+247, +143)`，窗口落到
    /// `y = −170`（屏顶在 `−35`）——**整层完全在屏幕之外**，于是「歌词开关开着、歌词也取到了、
    /// 屏幕上却什么都没有」，而且**鼠标再也抓不到它**（唯一退路是设置页的「重置位置」）。夹一道以后，
    /// 拖过头最多贴边，不会消失。
    static func clampedOrigin(_ origin: CGPoint, windowSize: CGSize, screenFrame: CGRect) -> CGPoint {
        let extent = min(minimumVisibleExtent, windowSize.width, windowSize.height)
        let minX = screenFrame.minX - windowSize.width + extent
        let maxX = screenFrame.maxX - extent
        let minY = screenFrame.minY - windowSize.height + extent
        let maxY = screenFrame.maxY - extent
        return CGPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }

    /// 至少留多少可见（pt）：够鼠标抓住去拖回来（窗口只有十几行字，40 已经是一大块）。
    static let minimumVisibleExtent: CGFloat = 40
}

private extension LyricsOverlayView {
    /// 建 `NSHostingView` 时的占位内容（还没 sync 到真实行表；建完立刻被 `rootView` 覆盖）。
    static let empty = LyricsOverlayView(
        lines: [],
        isSynced: true,
        highlightIndex: nil,
        emphasizeCurrent: false,
        fontSize: 18,
        lineCount: 1,
        opacity: 1,
        colorMode: .white,
        customHex: "#FFFFFF",
        albumArtColor: nil,
        locked: true,
        onToggleLock: {},
        onResetPosition: {},
        onCloseLyrics: {},
        onDragChanged: { _ in },
        onDragEnded: { _ in }
    )
}

#endif
