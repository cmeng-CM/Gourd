/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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
import AppKit
import AVFoundation

private final class DynamicIslandArtworkLoopController {
    let player: AVQueuePlayer
    private var looper: AVPlayerLooper?
    private var playbackStateCancellable: AnyCancellable?

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: player, templateItem: item)

        if MusicManager.shared.isPlaying {
            player.play()
        }

        playbackStateCancellable = MusicManager.shared.$isPlaying
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                guard let self else { return }
                if isPlaying {
                    self.player.play()
                } else {
                    self.player.pause()
                }
            }
    }

    deinit {
        player.pause()
        looper = nil
        playbackStateCancellable = nil
    }
}

private final class DynamicIslandArtworkVideoContainerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        // SwiftUI owns the enclosing transition timing. Prevent the video
        // layer from adding a second implicit frame animation during that
        // transition, which makes Canvas artwork lag behind static artwork.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

private struct DynamicIslandArtworkVideoView: NSViewRepresentable {
    let url: URL
    let videoGravity: AVLayerVideoGravity

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> DynamicIslandArtworkVideoContainerView {
        let view = DynamicIslandArtworkVideoContainerView(frame: .zero)
        context.coordinator.attach(layer: view.playerLayer, url: url, gravity: videoGravity)
        return view
    }

    func updateNSView(_ nsView: DynamicIslandArtworkVideoContainerView, context: Context) {
        context.coordinator.attach(layer: nsView.playerLayer, url: url, gravity: videoGravity)
    }

    final class Coordinator {
        private var controller: DynamicIslandArtworkLoopController?
        private var currentURL: URL?

        func attach(layer: AVPlayerLayer, url: URL, gravity: AVLayerVideoGravity) {
            layer.videoGravity = gravity

            if currentURL != url || controller == nil {
                currentURL = url
                controller = DynamicIslandArtworkLoopController(url: url)
            }

            if layer.player !== controller?.player {
                layer.player = controller?.player
            }
        }
    }
}

struct DynamicIslandArtworkSourceView: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.showLiveCanvasInDynamicIsland) private var showLiveCanvasInDynamicIsland

    let cornerRadius: CGFloat
    let contentMode: ContentMode

    private var liveCanvasURL: URL? {
        guard showLiveCanvasInDynamicIsland else { return nil }
        return musicManager.videoArtworkURL
    }

    var body: some View {
        Group {
            if let liveCanvasURL {
                DynamicIslandArtworkVideoView(url: liveCanvasURL, videoGravity: .resizeAspectFill)
            } else {
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Music Player Components

struct MusicControlsView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @State private var sliderValue: Double = MusicManager.shared.estimatedPlaybackPosition()
    @State private var dragging: Bool = false
    @State private var lastDragged: Date = .distantPast
    @State private var hudValue: Double = 0
    @State private var hudDragging: Bool = false
    @State private var hudLastDragged: Date = .distantPast
    @Default(.showShuffleAndRepeat) private var showCustomControls
    @Default(.musicControlSlots) private var slotConfig
    @Default(.showMediaOutputControl) private var showMediaOutputControl
    @Default(.musicSkipBehavior) private var musicSkipBehavior
    @Default(.enableLyrics) private var enableLyrics
    private let seekInterval: TimeInterval = 10
    private let skipMagnitude: CGFloat = 6

    /// 音乐区块（封面对侧的「标题 + 进度 + 控制按钮」）。
    ///
    /// **成组、顶部对齐**（2026-09-29 用户反馈「音乐播放的时候，控制按钮在最下面，不在播放的区域」）：
    /// 改造前这里是一个 `GeometryReader`（宽高双向贪婪）包住「标题 + 进度」，控制按钮行是它**外面**
    /// 的兄弟节点——面板高 400～850 时 `GeometryReader` 吃掉全部剩余高度，按钮行就被推到面板最底部，
    /// 与封面/标题之间隔出一大片空白。现在把控制按钮行**收进同一区块内的 `VStack`**、整个区块
    /// 顶部对齐（`maxHeight: .infinity, alignment: .topLeading`）：按钮紧跟进度条，未使用的空间
    /// 留在区块**下方**。
    ///
    /// 封面尺寸 / 圆角 / 进度条样式 / 按钮外观与顺序一概未动；`GeometryReader` 仍是宽度来源
    /// （只把读数上移一层，宽度换算见 `songInfo(width:)`）。
    ///
    /// **只剩紧凑档**（p5-home-blocks / T3 fix / D-17；T6 折叠）：本视图的唯一消费方是首页音乐块
    /// （`MusicHomeBlockView`）——旧 `regular` 档（展开面板那套）随 `MusicPlayerView` 退休后零消费点，
    /// 已删，`density` 参数与 `Density` 枚举一并消失。这一档只留「曲名（单行）+ 进度 + 控制行」：
    /// 艺人行 / 歌词行 / 大内边距都没有，控制行的键**五槽一档**（T2 起 `.small` = 26，播放键同档），
    /// 各段高度见 `CompactMetrics`（唯一取值处；总和 ≤ 96 与封面档装宽度 ≤ min 由单测钉住）。
    var body: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: CompactMetrics.controlsSpacing) {
                VStack(alignment: .leading, spacing: CompactMetrics.titleSliderSpacing) {
                    songInfo(width: max(0, geo.size.width - Self.songInfoLeadingInset))
                        .zIndex(1) // Ensure it draws above the waveform scrubber
                    musicSlider
                        .zIndex(0)
                }
                // 与原 `songInfoAndSlider` 的留白一致（`GeometryReader` 的读数比内容宽 5pt：
                // 这段 leading 内边距在读数里已经扣掉，见上面的 `- Self.songInfoLeadingInset`）。
                .padding(.top, CompactMetrics.topPadding)
                .padding(.leading, Self.songInfoLeadingInset)

                if shouldShowControlHUDRow {
                    controlHUDRow
                } else {
                    playbackControls
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 紧凑档的度量（p5-home-blocks / T3 fix / D-17；T6 起唯一档）

    /// 紧凑档的**高度预算**（D-17 的实现口径）：整条内容高 = 六项之和，必须
    /// ≤ `HomeFlowView.compactBlockHeight`（96）。**唯一取值处**——`body` / `musicSlider` /
    /// `slotView(for:)` / `MusicHomeBlockView`（封面那两档）都从这里取数，
    /// `HomeStripLayoutTests.testCompactMusicBarFitsTheCompactTier` 钉「总和 ≤ 96」、
    /// `testMusicBlockWidthAndCompactControlsFitTheMinimum`（T2）钉**装宽度关系式**
    /// （改任何一个数都要在这两处同步）。
    ///
    /// 六个数的依据都是**固有高**（不是拍出来的比例）：曲名行 17 = `MarqueeText` 的
    /// `1.3 × NSFont.headline.pointSize(13)`；进度行 34 = `MusicSliderView` 的 stacked 算式
    /// `轨道 14（max(8, 14)）+ 间距 6 + 时间行 14`；控制行 26 = `.small` 档 `HoverButton` 的边长（T2 起）。
    enum CompactMetrics {
        /// 顶部内边距。
        static let topPadding: CGFloat = 4
        /// 曲名行：单行。
        static let titleRowHeight: CGFloat = 17
        /// 「曲名 ↔ 进度」的组内间距。
        static let titleSliderSpacing: CGFloat = 4
        /// 进度行：`MusicSliderView`（stacked，同一份实现）的固有高。
        static let sliderRowHeight: CGFloat = 34
        /// 「进度组 ↔ 控制行」的间距。
        static let controlsSpacing: CGFloat = 6
        /// 控制键的键径（T2：30 → 26）：**每一个槽位**都是这一档
        /// （播放键同档）——真源是 `HoverButton.buttonSize(for: .small)`，
        /// 测试把两处钉在一起（改了 `HoverButton` 的档而不动这里，装宽度算式就是假的）。
        static let controlKeyDiameter: CGFloat = 26
        /// 控制行的键距（T2：8 → 6）。
        static let controlsKeySpacing: CGFloat = 6
        /// 控制行高 = 键径（一行全是同档方形键；`.none` 槽位给 `Spacer`，只占宽不占高）。
        static let controlsRowHeight: CGFloat = controlKeyDiameter
        /// 小封面边长（T2：40 → 36）：`MusicHomeBlockView` 直接引它，模块里不再自带一份。
        static let albumArtSide: CGFloat = 36
        /// 小封面与它右侧控制条的间距（T2：8 → 6，与键距同一条呼吸感）。
        static let albumArtSpacing: CGFloat = 6

        /// 整条内容高（不含宿主给的块高）——「不裁不溢」的判据就是它 ≤ 96：
        /// **`4 + 17 + 4 + 34 + 6 + 26 = 91 ≤ 96`**（T2 前是 95，控制行 30 → 26）。
        static var contentHeight: CGFloat {
            topPadding + titleRowHeight + titleSliderSpacing + sliderRowHeight
                + controlsSpacing + controlsRowHeight
        }

        /// **封面档的装宽度**（T2 / D-04）：封面打开那一档一行里要放下的全部横向宽度 =
        /// 「五键 + 四道键距」+「封面 + 封面距」= **`5×26 + 4×6 + 36 + 6 = 196`**。
        /// 它必须 **≤ 音乐块声明的 `min`**（`MusicModule.homeBlockMinWidth` = 200，余量 4）——
        /// 破了这条，封面打开时控制键就会被裁（T3 那次「控制三键整行被裁」的宽度版）。
        /// 五键的「五」= `MusicControlButton.slotCount`（最坏情形：五个槽位全是真键，没有 `.none`）。
        /// 块宽的真源在模块侧（这里不引用它，避免视图反向依赖模块）；两边的关系由
        /// `HomeStripLayoutTests.testMusicBlockWidthAndCompactControlsFitTheMinimum` 钉在一起。
        static var albumArtRowInstallWidth: CGFloat {
            CGFloat(MusicControlButton.slotCount) * controlKeyDiameter
                + CGFloat(MusicControlButton.slotCount - 1) * controlsKeySpacing
                + albumArtSide + albumArtSpacing
        }
    }

    /// 「标题」文字区相对音乐区块的 leading 内边距（pt）——宽度换算要用同一个值。
    private static let songInfoLeadingInset: CGFloat = 5

    /// 「标题」文字区：把曲名行**钉在预算那 17pt**（`CompactMetrics.titleRowHeight`）
    /// ——不钉的话这一行的高度由字体度量决定，`contentHeight ≤ 96` 就只是估算。
    private func songInfo(width: CGFloat) -> some View {
        songInfoContent(width: width)
            .frame(height: CompactMetrics.titleRowHeight, alignment: .leading)
    }

    private func songInfoContent(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MusicTitleMarqueeView(
                text: musicManager.songTitle,
                isExplicit: musicManager.isCurrentTrackExplicit,
                font: .headline,
                nsFont: .headline,
                textColor: .white,
                frameWidth: width,
                badgeHeight: 14
            )
        }
    }

    /// Whether the progress timeline should be paused (no ticks).
    private var isProgressTimelinePaused: Bool {
        !musicManager.isPlaying || musicManager.isLiveStream || musicManager.playbackRate <= 0
    }

    private var musicSlider: some View {
        TimelineView(.animation(paused: isProgressTimelinePaused)) { timeline in
            MusicSliderView(
                sliderValue: $sliderValue,
                duration: $musicManager.songDuration,
                lastDragged: $lastDragged,
                color: musicManager.avgColor,
                dragging: $dragging,
                currentDate: timeline.date,
                timestampDate: musicManager.timestampDate,
                elapsedTime: musicManager.elapsedTime,
                playbackRate: musicManager.playbackRate,
                isPlaying: musicManager.isPlaying,
                isLiveStream: musicManager.isLiveStream
            ) { newValue in
                guard !musicManager.isLiveStream else { return }
                MusicManager.shared.seek(to: newValue)
            }
            .frame(height: CompactMetrics.sliderRowHeight)
        }
    }

    private var playbackControls: some View {
        HStack(spacing: CompactMetrics.controlsKeySpacing) {
            ForEach(Array(displayedSlots.enumerated()), id: \.offset) { _, slot in
                slotView(for: slot)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var shouldShowControlHUDRow: Bool {
        guard vm.notchState == .open else { return false }
        guard coordinator.sneakPeek.show else { return false }
        guard Defaults[.enableSystemHUD] else { return false }
        guard !Defaults[.enableCustomOSD] && !Defaults[.enableVerticalHUD] && !Defaults[.enableCircularHUD] else { return false }

        switch coordinator.sneakPeek.type {
        case .volume:
            return Defaults[.enableVolumeHUD]
        case .brightness:
            return Defaults[.enableBrightnessHUD]
        case .backlight:
            return Defaults[.enableKeyboardBacklightHUD]
        default:
            return false
        }
    }

    private var controlHUDRow: some View {
        HStack(alignment: .center, spacing: 10) {
            if !controlLeftIconName.isEmpty {
                Image(systemName: controlLeftIconName)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22, height: 22, alignment: .center)
            }

            controlHUDSlider

            if !controlRightIconName.isEmpty {
                Image(systemName: controlRightIconName)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22, height: 22, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear { syncHUDValueIfNeeded(force: true) }
        .onChange(of: coordinator.sneakPeek.value) { _, _ in
            syncHUDValueIfNeeded(force: false)
        }
    }

    private var controlHUDSlider: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            CustomSlider(
                value: Binding(
                    get: { hudValue },
                    set: { newValue in
                        hudValue = newValue
                        updateControlHUDValue(newValue)
                    }
                ),
                range: 0...1,
                color: .white,
                dragging: $hudDragging,
                lastDragged: $hudLastDragged,
                onValueChange: { newValue in
                    updateControlHUDValue(newValue)
                },
                thumbSize: 10,
                restingTrackHeight: 4,
                draggingTrackHeight: 7
            )
            .frame(height: 7)
            Spacer(minLength: 0)
        }
        .frame(height: 22)
    }

    private func syncHUDValueIfNeeded(force: Bool) {
        guard shouldShowControlHUDRow else { return }
        guard force || !hudDragging else { return }
        hudValue = Double(coordinator.sneakPeek.value)
    }

    private func updateControlHUDValue(_ newValue: Double) {
        let clamped = max(0, min(1, newValue))
        switch coordinator.sneakPeek.type {
        case .volume:
            SystemVolumeController.shared.setVolume(Float(clamped))
        case .brightness:
            SystemBrightnessController.shared.setBrightness(Float(clamped))
        case .backlight:
            SystemKeyboardBacklightController.shared.setLevel(Float(clamped))
        default:
            break
        }
    }

    private var controlLeftIconName: String {
        switch coordinator.sneakPeek.type {
        case .volume:
            return SystemVolumeController.shared.isMuted ? "speaker.slash" : "speaker.wave.1"
        case .brightness:
            return "sun.min.fill"
        case .backlight:
            return "light.min"
        default:
            return ""
        }
    }

    private var controlRightIconName: String {
        switch coordinator.sneakPeek.type {
        case .volume:
            return SystemVolumeController.shared.isMuted ? "" : "speaker.wave.3"
        case .brightness:
            return "sun.max.fill"
        case .backlight:
            return "light.max"
        default:
            return ""
        }
    }

    private var brandAccentColor: Color {
        musicManager.brandAccentColor
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    private var repeatIconColor: Color {
        switch musicManager.repeatMode {
        case .off:
            return .white
        case .all, .one:
            return brandAccentColor
        }
    }

    private var displayedSlots: [MusicControlButton] {
        if showCustomControls {
            let normalized = slotConfig.normalized(allowingMediaOutput: showMediaOutputControl, isAppleMusicActive: musicManager.isAppleMusicActive, isSpotifyActive: musicManager.isSpotifyActive)
            return normalized.contains(where: { $0 != .none }) ? normalized : MusicControlButton.defaultLayout
        }

        switch musicSkipBehavior {
        case .track:
            return MusicControlButton.minimalLayout
        case .tenSecond:
            return [.none, .seekBackward, .playPause, .seekForward, .none]
        }
    }

    /// 控制行的槽位（**键的尺寸档五槽一档**：`.small` = 26，播放键同档；真源
    /// `HoverButton.buttonSize(for: .small)`，与 `CompactMetrics.controlKeyDiameter` 同值，
    /// 装宽度算式（`CompactMetrics.albumArtRowInstallWidth`）由此成立）。
    @ViewBuilder
    private func slotView(for control: MusicControlButton) -> some View {
        switch control {
        case .none:
            Spacer(minLength: 0)
        case .playPause:
            HoverButton(
                icon: musicManager.isPlaying ? (musicManager.isLiveStream ? "stop.fill" : "pause.fill") : "play.fill",
                scale: .small
            ) {
                MusicManager.shared.togglePlay()
            }
        case .trackBackward:
            playbackButton(
                icon: "backward.fill",
                press: .nudge(-skipMagnitude),
                trigger: skipGestureTrigger(for: .trackBackward)
            ) {
                musicManager.previousTrack()
            }
        case .trackForward:
            playbackButton(
                icon: "forward.fill",
                press: .nudge(skipMagnitude),
                trigger: skipGestureTrigger(for: .trackForward)
            ) {
                musicManager.nextTrack()
            }
        case .seekBackward:
            playbackButton(
                icon: "gobackward.10",
                press: .wiggle(.counterClockwise),
                trigger: skipGestureTrigger(for: .seekBackward)
            ) {
                musicManager.seek(by: -seekInterval)
            }
        case .seekForward:
            playbackButton(
                icon: "goforward.10",
                press: .wiggle(.clockwise),
                trigger: skipGestureTrigger(for: .seekForward)
            ) {
                musicManager.seek(by: seekInterval)
            }
        case .shuffle:
            HoverButton(
                icon: "shuffle",
                iconColor: musicManager.isShuffled ? brandAccentColor : .white,
                scale: .small
            ) {
                MusicManager.shared.toggleShuffle()
            }
        case .repeatMode:
            HoverButton(
                icon: repeatIcon,
                iconColor: repeatIconColor,
                scale: .small
            ) {
                MusicManager.shared.toggleRepeat()
            }
        case .mediaOutput:
            MediaOutputPickerButton(scale: .small)
        case .airPlay:
            AirPlayPickerButton(scale: .small)
        case .lyrics:
            HoverButton(
                icon: enableLyrics ? "quote.bubble.fill" : "quote.bubble",
                iconColor: enableLyrics ? brandAccentColor : .white,
                scale: .small
            ) {
                enableLyrics.toggle()
            }
        case .likeTrack:
            LikeTrackControl { presentation, toggle in
                HoverButton(
                    icon: presentation.iconName,
                    iconColor: presentation.isActive ? brandAccentColor : .white,
                    scale: .small
                ) {
                    toggle()
                }
            }
        }
    }

    private struct SkipTrigger {
        let token: Int
        let pressEffect: HoverButton.PressEffect
    }

    private func playbackButton(
        icon: String,
        press: HoverButton.PressEffect?,
        trigger: SkipTrigger?,
        action: @escaping () -> Void
    ) -> some View {
        HoverButton(
            icon: icon,
            scale: .small,
            pressEffect: press,
            externalTriggerToken: trigger?.token,
            externalTriggerEffect: trigger?.pressEffect
        ) {
            action()
        }
    }

    private func skipGestureTrigger(for control: MusicControlButton) -> SkipTrigger? {
        guard let pulse = musicManager.skipGesturePulse else { return nil }

        switch control {
        case .trackBackward where pulse.behavior == .track && pulse.direction == .backward:
            return SkipTrigger(token: pulse.token, pressEffect: .nudge(-skipMagnitude))
        case .trackForward where pulse.behavior == .track && pulse.direction == .forward:
            return SkipTrigger(token: pulse.token, pressEffect: .nudge(skipMagnitude))
        case .seekBackward where pulse.behavior == .tenSecond && pulse.direction == .backward:
            return SkipTrigger(token: pulse.token, pressEffect: .wiggle(.counterClockwise))
        case .seekForward where pulse.behavior == .tenSecond && pulse.direction == .forward:
            return SkipTrigger(token: pulse.token, pressEffect: .wiggle(.clockwise))
        default:
            return nil
        }
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var extensionNotchExperienceManager = ExtensionNotchExperienceManager.shared
    let albumArtNamespace: Namespace.ID

    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                mainContent
            }
        }
        .transition(.opacity.combined(with: .blurReplace))
    }

    private var mainContent: some View {
        Group {
            if Defaults[.enableMinimalisticUI] {
                if let overridePayload = minimalisticOverridePayload {
                    ExtensionMinimalisticExperienceView(
                        payload: overridePayload,
                        albumArtNamespace: albumArtNamespace
                    )
                } else {
                    MinimalisticMusicPlayerView(albumArtNamespace: albumArtNamespace)
                }
            } else {
                // 标准路径（2026-09-29 起）：首页是**两条带 + 一行**——上排主块带（大块：音乐 / 镜子，
                // 一条横向 strip，宽度按声明自适应且富余不拉伸），中排小组件带（紧凑块：进度 / 统计 /
                // 待办 / 通知 / 前台应用，网格换行、放不下换行而不是丢块），下排全宽日历行（左整月网格 /
                // 右今日清单，由 `showCalendar` 门控）。块与行的名单、门控与排版都在各自视图内，
                // 本视图只做这一支的接缝（docs/17-nookx-adoption.md §改动点设计 1；
                // docs/26-home-widgets-and-settings.md §做法 机制六 / D-09 是 T7 分带的规格）。
                standardHomeContent
            }
        }
        .transition(.opacity.animation(.smooth.speed(0.9))
            .combined(with: .blurReplace.animation(.smooth.speed(0.9)))
            .combined(with: .move(edge: .top)))
        .blur(radius: vm.notchState == .closed ? 30 : 0)
        .padding(Defaults[.enableMinimalisticUI] ? 0 : 8) //Putting the main padding for home view here for consistency
    }

    /// 标准路径首页的接缝：**主块带（上）+ 小组件带（下）+ 全宽日历行**（T7 起；改动前是
    /// 「上排 strip + 下排日历行」两排）。
    ///
    /// 渲染与取舍都不在这里——`HomeBandedHomeView`（`Host/HomeStripView.swift`）是那层接缝：
    /// 它拿 `homeEntries` 投影（+ 内容表态）切出两条带，按 `HomeVerticalFit` 的四档决定画哪几样、
    /// 各拿多少高度（**先收日历行 → 再收主块带 → 最后才动小组件带**，docs/26-home-widgets-and-settings.md
    /// §做法 机制六 / D-09），再按 `HomeBandedLayout` 摆放（主块带沿用旧 strip 语义——宽度不足时
    /// 按序丢尾巴；小组件带网格换行、**放不下换行而不是丢块**）。本视图保留的是更外面那层接缝：
    /// **极简 UI / 首发动画都不走这一支**。
    ///
    /// 日历行的「开不开」仍是用户偏好（`showCalendar`，那条键在接缝里的读者是 `HomeBandedHomeView`）；
    /// 高度取舍的判据只有一处（`HomeVerticalFit.plan`），本视图不再自己比一次高度——两处各判一次
    /// 就会有两份阈值。
    ///
    /// **p5-home-blocks / T6 起本视图给接缝一样宿主事实**（自适应高度要用，docs/29 §做法 机制六）：
    /// 面板表头高（`max(24, vm.effectiveClosedNotchHeight)`，`NotchLayout` 就是这么给它钉的），
    /// 接缝拿它把「面板高 → 流可用高」的差额算准。
    ///
    /// **2026-10-08（p8-height-smooth）撤掉第二样**（光标在不在面板里）：它只服务「光标在面板内不缩」
    /// 那条规则，而那条规则已删（理由见 `PanelContentHeight` 文件头与 docs/00 ADR-0015）。
    private var standardHomeContent: some View {
        HomeBandedHomeView(
            albumArtNamespace: albumArtNamespace,
            panelHeaderHeight: PanelAutoHeight.panelHeaderHeight(
                effectiveClosedNotchHeight: vm.effectiveClosedNotchHeight
            )
        )
    }

    private var minimalisticOverridePayload: ExtensionNotchExperiencePayload? {
        extensionNotchExperienceManager.minimalisticReplacementPayload()
    }
}

struct MusicSliderView: View {
    @Binding var sliderValue: Double
    @Binding var duration: Double
    @Binding var lastDragged: Date
    var color: NSColor
    @Binding var dragging: Bool
    let currentDate: Date
    let timestampDate: Date
    let elapsedTime: Double
    let playbackRate: Double
    let isPlaying: Bool
    let isLiveStream: Bool
    var onValueChange: (Double) -> Void
    var labelLayout: TimeLabelLayout = .stacked
    var trailingLabel: TrailingLabel = .duration
    var restingTrackHeight: CGFloat = 8
    var draggingTrackHeight: CGFloat = 14
    /// When set, bypasses Defaults[.sliderColor] (used by lock screen appearance).
    var tintOverride: Color? = nil

    enum TimeLabelLayout {
        case stacked
        case inline
    }

    enum TrailingLabel {
        case duration
        case remaining
    }

    var body: some View {
        Group {
            if isLiveStream {
                liveStreamView
            } else {
                switch labelLayout {
                case .stacked:
                    stackedContent
                case .inline:
                    inlineContent
                }
            }
        }
        .onAppear {
            guard !isLiveStream else { return }
            guard !dragging else { return }
            setSliderValueWithoutAnimation(MusicManager.shared.estimatedPlaybackPosition())
        }
        .onChange(of: currentDate) { newDate in
            guard !isLiveStream else { return }
            guard !dragging, timestampDate.timeIntervalSince(lastDragged) > -1 else { return }
            setSliderValueWithoutAnimation(MusicManager.shared.estimatedPlaybackPosition(at: newDate))
        }
        .onChange(of: isPlaying) { _, playing in
            // Snap slider to the exact position when music pauses so
            // the in-flight animation doesn't coast past the true value.
            if !playing {
                sliderValue = MusicManager.shared.estimatedPlaybackPosition()
            }
        }
        .onChange(of: isLiveStream) { isLive in
            if isLive {
                sliderValue = 0
            }
        }
    }

    private func setSliderValueWithoutAnimation(_ value: Double) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            sliderValue = value
        }
    }

    private var stackedContent: some View {
        VStack(spacing: 6) {
            sliderCore
                .frame(height: sliderFrameHeight)

            HStack {
                Text(timeString(from: sliderValue))
                Spacer()
                Text(trailingTimeText)
            }
            .fontWeight(.medium)
            .foregroundColor(timeLabelColor)
            .font(.system(size: 11, weight: .medium, design: .default).monospacedDigit())
        }
    }

    private var inlineContent: some View {
        HStack(spacing: 6) {
            Text(timeString(from: sliderValue))
                .font(inlineLabelFont)
                .foregroundColor(timeLabelColor)
                .frame(width: 36, alignment: .leading)

            sliderCore
                .frame(height: sliderFrameHeight)
                .frame(maxWidth: .infinity)

            Text(trailingTimeText)
                .font(inlineLabelFont)
                .foregroundColor(timeLabelColor)
                .frame(width: 42, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var liveStreamView: some View {
        switch labelLayout {
        case .stacked:
            LiveStreamProgressIndicator(tint: sliderTint)
                .frame(maxWidth: .infinity)
                .frame(height: sliderFrameHeight)
                
        case .inline:
            HStack(spacing: 6) {
                Spacer()
                    .frame(width: 36)
                LiveStreamProgressIndicator(tint: sliderTint)
                    .frame(maxWidth: .infinity)
                    .frame(height: sliderFrameHeight)

                Spacer()
                    .frame(width: 42)
            }
        }
    }

    private var sliderCore: some View {
        CustomSlider(
            value: $sliderValue,
            range: 0 ... duration,
            color: sliderTint,
            dragging: $dragging,
            lastDragged: $lastDragged,
            onValueChange: onValueChange,
            restingTrackHeight: restingTrackHeight,
            draggingTrackHeight: draggingTrackHeight
        )
    }

    private var sliderTint: Color {
        if let tintOverride {
            return tintOverride
        }
        switch Defaults[.sliderColor] {
        case .albumArt:
            return Color(nsColor: color).ensureMinimumBrightness(factor: 0.6)
        case .accent:
            return .accentColor
        case .white:
            return .white
        }
    }

    private var timeLabelColor: Color {
        if let tintOverride {
            return tintOverride
        }
        return Defaults[.playerColorTinting]
            ? Color(nsColor: color).ensureMinimumBrightness(factor: 0.6)
            : .gray
    }

    private var trailingTimeText: String {
        switch trailingLabel {
        case .duration:
            return timeString(from: duration)
        case .remaining:
            let remaining = max(duration - sliderValue, 0)
            return "-" + timeString(from: remaining)
        }
    }

    private var inlineLabelFont: Font {
        .system(size: 11, weight: .medium, design: .default).monospacedDigit()
    }

    private var sliderFrameHeight: CGFloat {
        max(restingTrackHeight, draggingTrackHeight)
    }

    func timeString(from seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }

}


struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var thumbSize: CGFloat = 12
    var restingTrackHeight: CGFloat = 8
    var draggingTrackHeight: CGFloat = 14
    
    @State private var isHovering: Bool = false
    @Default(.enableRealTimeWaveform) var enableRealTimeWaveform
    @Default(.enableWaveformScrubber) var enableWaveformScrubber

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let trackHeight = CGFloat(dragging ? draggingTrackHeight : restingTrackHeight)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width
            
            let showScrubber = isHovering && enableRealTimeWaveform && enableWaveformScrubber

            ZStack(alignment: .bottomLeading) {
                // Background track
                if showScrubber {
                    RealTimeWaveformScrubberView(
                        color: color,
                        secondaryColor: Defaults[.coloredSpectrogram] ? Color(nsColor: MusicManager.shared.secondaryColor) : nil,
                        progress: progress,
                        minHeight: trackHeight
                    )
                    .frame(height: trackHeight * 3.5)
                    .offset(y: trackHeight * 0.2)
                } else {
                    Rectangle()
                        .fill(.gray.opacity(0.3))
                        .frame(height: trackHeight)
                        .cornerRadius(trackHeight / 2)
                }

                // Filled track
                if !showScrubber {
                    Rectangle()
                        .fill(color)
                        .frame(width: filledTrackWidth, height: trackHeight)
                        .cornerRadius(trackHeight / 2)
                }
            }
            .frame(height: max(restingTrackHeight, draggingTrackHeight), alignment: .bottom)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.bouncy.speed(1.4), value: dragging)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = hovering
                }
            }
        }
    }
}

private struct MediaOutputPickerButton: View {
    @ObservedObject private var routeManager = AudioRouteManager.shared
    @StateObject private var volumeModel = MediaOutputVolumeViewModel()
    @State private var isPopoverPresented = false
    @State private var isHoveringPopover = false
    @EnvironmentObject private var vm: DynamicIslandViewModel

    /// 键的尺寸档（p6 / T2；T6 起**无缺省**）：唯一调用方 `MusicControlsView.slotView` 传 `.small`
    /// （26）——旧 `.medium` 缺省（展开面板那一档）随 `.regular` 档退休后零消费，已删。
    var scale: Image.Scale

    var body: some View {
        HoverButton(icon: buttonIcon, iconColor: .white, scale: scale) {
            isPopoverPresented.toggle()
            if isPopoverPresented {
                routeManager.refreshDevices()
            }
        }
        .accessibilityLabel("Media output")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            MediaOutputSelectorPopover(
                routeManager: routeManager,
                volumeModel: volumeModel,
                onHoverChanged: { hovering in
                    isHoveringPopover = hovering
                    updatePopoverActivity()
                }
            ) {
                isPopoverPresented = false
                isHoveringPopover = false
                updatePopoverActivity()
            }
        }
        .onAppear {
            routeManager.refreshDevices()
        }
        .onChange(of: isPopoverPresented) { _, presented in
            if !presented {
                isHoveringPopover = false
            }
            updatePopoverActivity()
        }
        .onDisappear {
            vm.isMediaOutputPopoverActive = false
        }
    }

    private var buttonIcon: String {
        routeManager.activeDevice?.iconName ?? "speaker.wave.2"
    }

    private func updatePopoverActivity() {
        vm.isMediaOutputPopoverActive = isPopoverPresented && isHoveringPopover
    }
}

private struct AirPlayPickerButton: View {
    @ObservedObject private var musicManager = MusicManager.shared
    @ObservedObject private var airPlayManager = AppleMusicAirPlayManager.shared
    @State private var isPopoverPresented = false
    @State private var isHoveringPopover = false
    @EnvironmentObject private var vm: DynamicIslandViewModel

    private var isAppleMusicActive: Bool {
        musicManager.bundleIdentifier == "com.apple.Music"
    }

    /// 键的尺寸档（p6 / T2；T6 起**无缺省**）：与 `MediaOutputPickerButton.scale` 同口径，由
    /// `slotView(for:)` 传 `.small`（26）。
    var scale: Image.Scale

    var body: some View {
        HoverButton(icon: "airplayaudio", iconColor: .white, scale: scale) {
            isPopoverPresented.toggle()
            if isPopoverPresented {
                Task { await airPlayManager.refreshDevices() }
            }
        }
        .accessibilityLabel("AirPlay")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            AirPlaySelectorPopover(
                airPlayManager: airPlayManager,
                onHoverChanged: { hovering in
                    isHoveringPopover = hovering
                    updatePopoverActivity()
                }
            ) {
                isPopoverPresented = false
                isHoveringPopover = false
                updatePopoverActivity()
            }
        }
        .onAppear {
            if isAppleMusicActive {
                Task { await airPlayManager.refreshDevices() }
            }
        }
        .onChange(of: isPopoverPresented) { _, presented in
            if !presented { isHoveringPopover = false }
            updatePopoverActivity()
        }
        .onChange(of: musicManager.bundleIdentifier) { _, newBundle in
            if newBundle == "com.apple.Music" {
                Task { await airPlayManager.refreshDevices() }
            }
        }
        .onDisappear {
            vm.isMediaOutputPopoverActive = false
        }
    }

    private func updatePopoverActivity() {
        vm.isMediaOutputPopoverActive = isPopoverPresented && isHoveringPopover
    }
}

struct MediaOutputSelectorPopover: View {
    @ObservedObject var routeManager: AudioRouteManager
    @ObservedObject var volumeModel: MediaOutputVolumeViewModel
    var onHoverChanged: (Bool) -> Void
    var dismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            volumeSection
            Divider()
            devicesSection
        }
        .frame(width: 240)
        .padding(16)
        .onHover { hovering in
            onHoverChanged(hovering)
        }
        .onDisappear {
            onHoverChanged(false)
        }
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    volumeModel.toggleMute()
                } label: {
                    Image(systemName: volumeIconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.secondary.opacity(0.18))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { Double(volumeModel.level) },
                        set: { newValue in
                            volumeModel.setVolume(Float(newValue))
                        }
                    ),
                    in: 0 ... 1
                )
                .tint(.accentColor)
            }

            HStack {
                Text("Output volume")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(volumePercentage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output devices")
                .font(.caption)
                .foregroundColor(.secondary)

            if routeManager.devices.isEmpty {
                Text("No audio outputs available")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(routeManager.devices) { device in
                            Button {
                                routeManager.select(device: device)
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: device.iconName)
                                        .font(.system(size: 14, weight: .medium))
                                    Text(device.name)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    if device.id == routeManager.activeDeviceID {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(device.id == routeManager.activeDeviceID ? Color.primary.opacity(0.12) : .clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
            }
        }
    }

    private var volumeIconName: String {
        if volumeModel.isMuted || volumeModel.level <= 0.001 {
            return "speaker.slash.fill"
        } else if volumeModel.level < 0.33 {
            return "speaker.wave.1.fill"
        } else if volumeModel.level < 0.66 {
            return "speaker.wave.2.fill"
        }
        return "speaker.wave.3.fill"
    }

    private var volumePercentage: String {
        "\(Int(round(volumeModel.level * 100)))%"
    }
}

struct AirPlaySelectorPopover: View {
    @ObservedObject var airPlayManager: AppleMusicAirPlayManager
    var onHoverChanged: (Bool) -> Void
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AirPlay")
                .font(.caption)
                .foregroundColor(.secondary)

            if airPlayManager.devices.isEmpty {
                Text("No AirPlay devices found")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(airPlayManager.devices) { device in
                            VStack(spacing: 4) {
                                Button {
                                    Task { await airPlayManager.toggleDevice(device) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: device.iconName)
                                            .font(.system(size: 14, weight: .medium))
                                        Text(device.name)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Spacer()
                                        if device.isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .bold))
                                        }
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(device.isSelected ? Color.primary.opacity(0.12) : .clear)
                                    )
                                }
                                .buttonStyle(.plain)

                                if device.isSelected {
                                    AirPlayVolumeSlider(
                                        airPlayManager: airPlayManager,
                                        deviceID: device.id
                                    )
                                    .padding(.horizontal, 8)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 240)
        .padding(16)
        .onHover { hovering in
            onHoverChanged(hovering)
        }
        .onDisappear {
            onHoverChanged(false)
        }
    }
}

/// Local @State slider decoupled from the manager's @Published state.
/// This prevents SwiftUI from resetting the slider position when other
/// published properties on the manager change during a drag.
struct AirPlayVolumeSlider: View {
    @ObservedObject var airPlayManager: AppleMusicAirPlayManager
    let deviceID: String

    @State private var sliderValue: Double = 0
    @State private var isSyncing = false

    var body: some View {
        Slider(value: $sliderValue, in: 0...100)
            .tint(.accentColor)
            .onAppear {
                isSyncing = true
                sliderValue = Double(airPlayManager.currentVolume(for: deviceID))
                isSyncing = false
            }
            .onChange(of: sliderValue) { _, newValue in
                guard !isSyncing else { return }
                airPlayManager.setVolume(Int(newValue), for: deviceID)
            }
    }
}

final class MediaOutputVolumeViewModel: ObservableObject {
    @Published var level: Float
    @Published var isMuted: Bool

    private let controller: SystemVolumeController
    private var cancellables: Set<AnyCancellable> = []

    init(controller: SystemVolumeController = .shared) {
        self.controller = controller
        controller.start()
        level = controller.currentVolume
        isMuted = controller.isMuted

        NotificationCenter.default.publisher(for: .systemVolumeDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self,
                      let value = notification.userInfo?["value"] as? Float,
                      let muted = notification.userInfo?["muted"] as? Bool else { return }
                self.level = value
                self.isMuted = muted
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .systemAudioRouteDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncFromController()
            }
            .store(in: &cancellables)
    }

    func setVolume(_ value: Float) {
        level = value
        if value > 0 {
            isMuted = false
        }
        controller.setVolume(value)
    }

    func toggleMute() {
        isMuted.toggle()
        controller.toggleMute()
    }

    private func syncFromController() {
        level = controller.currentVolume
        isMuted = controller.isMuted
    }
}

#Preview {
    NotchHomeView(
        albumArtNamespace: Namespace().wrappedValue
    )
    .environmentObject(DynamicIslandViewModel())
}
