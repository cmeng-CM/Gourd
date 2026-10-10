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
//  `LockScreenManager.$isLocked`＋`enableLyrics` 与 9 枚显示档键的 `Defaults.publisher`；
//  任一变化调 `sync()`（不自建第二套状态，docs/35 §做法 机制一）。
//
//  **锚点**：岛所在屏（`DynamicIslandViewModel.screen` 的 localizedName 匹配，回落
//  `NSScreen.main`，与 `FlyoutWindowPresenter.resolveScreen` 同口径）的 `frame.midX` 居中、
//  岛底边下方一档间距（8pt），再叠加 `lyricsOverlayOffsetX/Y`（AppKit 屏幕坐标系的位移，
//  向下拖 = y 变小 = 负偏移）。屏参变化 / `screen` 变化时重算锚点、偏移原样保留。
//

#if os(macOS)
import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class LyricsOverlayWindowManager: ObservableObject {

    static let shared = LyricsOverlayWindowManager()

    /// 岛底边到歌词层顶边的间距（docs/35「岛下方一档间距」）。取 8 与
    /// `FlyoutFrameCalculator.screenInset` / 岛 hover 的 8pt 档同值。
    private static let anchorSpacing: CGFloat = 8

    private var window: NSPanel?
    private var hostingView: NSHostingView<LyricsOverlayView>?
    private var cancellables = Set<AnyCancellable>()
    private var isStarted = false

    /// 当前锚点（窗口左上角、未叠加偏移，已取整）——拖拽把落点折算成相对它的偏移。
    private var anchorOrigin: CGPoint?
    /// 拖拽起点（窗口左上角）：拖动期间窗口 origin = 起点 + 位移。
    private var dragStartOrigin: CGPoint?

    private init() {}

    /// 岛所在屏的设备 `vm`：与 `FlyoutWindowPresenter` 的入参同源（应用主 VM）。
    private var viewModel: DynamicIslandViewModel? { AppDelegate.shared?.vm }

    // MARK: - 启动

    /// 装观察链并立刻同步一次。重复调用是空操作（不叠第二份订阅）。
    /// 调用点：`DynamicIslandApp.applicationDidFinishLaunching`（`setupAudioTapMusicObservers()` 旁）。
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

        if let viewModel {
            sources.append(viewModel.$notchState.map { _ in () }.eraseToAnyPublisher())
            sources.append(viewModel.$screen.map { _ in () }.eraseToAnyPublisher())
        }

        // 总开关 + 9 枚显示档键（字体 / 行数 / 透明度 / 颜色模式 / 自定义色 / 高亮 / 锁定 / 偏移 X / 偏移 Y）。
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
    }

    // MARK: - 显隐（幂等）

    /// 按判据显示 / 隐藏，按「锚点 + 偏移」布局。判据、渲染输入与显示档都在这里现读，
    /// 所以改任一档当场生效（≤1 次重绘）。
    func sync() {
        let music = MusicManager.shared
        let mapped = LyricsOverlayRules.displayLines(synced: music.syncedLyrics)
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

        let size = measuredSize(for: hosting)
        let origin = anchorOrigin(on: screen, windowSize: size, viewModel: viewModel)
        self.anchorOrigin = origin
        apply(origin: origin, size: size, to: window)
    }

    private func hideIfNeeded() {
        dragStartOrigin = nil
        anchorOrigin = nil
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

    /// 拖拽进行中（视图 `DragGesture.onChanged`）：窗口原点 = 拖拽起点 + 位移。
    /// SwiftUI 的 y 向下，AppKit 的窗口 y 向上，所以高度取反。
    func dragChanged(_ translation: CGSize) {
        guard !Defaults[.lyricsOverlayLocked], let window, anchorOrigin != nil else { return }
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

    /// 拖拽结束（视图 `DragGesture.onEnded`）：把落点折算成相对锚点的偏移并落盘。
    func dragEnded(_ translation: CGSize) {
        guard let window else { return }
        dragChanged(translation)
        let origin = window.frame.origin
        dragStartOrigin = nil
        guard let anchorOrigin else { return }
        commitOffset(CGSize(width: origin.x - anchorOrigin.x, height: origin.y - anchorOrigin.y))
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
    /// 下方一档间距，再叠加两个偏移键。返回窗口左上角（AppKit 坐标，取整）。
    private func anchorOrigin(on screen: NSScreen, windowSize: CGSize, viewModel: DynamicIslandViewModel) -> CGPoint {
        let screenFrame = screen.frame
        let islandBottom = screenFrame.maxY - viewModel.effectiveClosedNotchHeight
        let x = screenFrame.midX - windowSize.width / 2 + CGFloat(Defaults[.lyricsOverlayOffsetX])
        let y = islandBottom - Self.anchorSpacing - windowSize.height + CGFloat(Defaults[.lyricsOverlayOffsetY])
        return CGPoint(x: x.rounded(), y: y.rounded())
    }
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
