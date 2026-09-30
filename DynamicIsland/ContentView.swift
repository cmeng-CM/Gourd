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

import AVFoundation
import Combine
import Defaults
import Foundation
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect
import AtollExtensionKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// 模块浮层（如通知）显示期间是否抑制「悬浮即展开面板」。
///
/// 关闭态有两条会抢跑「点浮层上按钮」这一下的路径，都读本判据：
/// ① `startHoverClickMonitor()` 装的 `mouseDown` 监听器（回调里直接 `openNotch()`）；
/// ② `handleHover` 的延时展开任务（`minimumHoverDuration` 后 `openNotch()`）。
/// 浮层是**瞬时**交互（通知 ttl 4s）：这期间用户的点击意图明确是操作浮层本身（× 或打开 App），
/// 而不是展开面板。ttl 到期浮层被内核清掉 → `activeHUD` 回到 nil → 本判据自动放行
/// （延时任务唤醒时浮层已消失则照旧展开，不重新计时）。
///
/// 抽成纯函数是为了可测：判据只依赖「当前有没有浮层」这一个入参，不读单例、不碰视图状态。
func shouldSuppressHoverOpen(activeHUD: ModuleHUD?) -> Bool {
    activeHUD != nil
}

/// 非刘海屏「不悬停就隐藏」的判据：关闭态内容是否该被整体挪出屏幕。
///
/// 上游的形态是「非刘海屏 + 关闭态 + 设置开启 + **当前没有上游瞬时提示**（sneakPeek：
/// 音量 / 亮度 / 音乐…）」才隐藏。
///
/// **模块瞬时浮层（如通知）不再是豁免项**（2026-09-28，D-23）：浮层改由内核的独立窗口
/// 承载（`Kernel/ModuleHUDWindow.swift`），压根不在关闭态这条链里——关闭态内容照常隐藏，
/// 浮层窗口自己出现在鼠标所在屏。此前的 `hasModuleHUD` 豁免（D-22 的补丁）随之删除。
///
/// 抽成纯函数是为了可测：入参都是纯值，调用点从视图状态取值后传进来，
/// 判据本身不读单例、不碰视图状态。
func shouldHideClosedContentUntilHover(
    hideSetting: Bool,
    isNonNotch: Bool,
    isClosed: Bool,
    hasSneakPeek: Bool
) -> Bool {
    hideSetting && isNonNotch && isClosed && !hasSneakPeek
}

/// 主面板背景是否该用**配置的样式**（纯黑 / 液态玻璃 / 毛玻璃），而不是恒定的纯黑。
///
/// **状态口径**（2026-09-28 用户要求给主面板背景加配置，见 `NotchPanelBackgroundStyle`）：
/// 玻璃两档**只在「展开态」或「非刘海屏的浮动药丸」上生效**；其余情况（刘海屏的折叠态）
/// 一律纯黑——折叠态的形态要与物理刘海对齐融合，玻璃会透出壁纸、在刘海下方形成一块突兀的
/// 方块，所以这条是**状态**层面的约束，不是用户可选项。
///
/// 两个入参对应面板的两个状态维度：
/// - `isOpen`：`vm.notchState == .open`（展开态：音乐 / 日历那一屏，也是用户截图里那一屏）；
/// - `isDynamicIslandMode`：`ContentView.isDynamicIslandMode`（非刘海屏的浮动药丸，
///   它本身就是一块独立悬浮的圆角面板，没有要与物理刘海融合的前提）。
///
/// 抽成纯函数是为了可测：入参都是纯值，调用点从视图状态取值后传进来，
/// 判据本身不读单例、不碰视图状态（同 `shouldSuppressHoverOpen` / `shouldHideClosedContentUntilHover`）。
func panelBackgroundUsesStyle(isOpen: Bool, isDynamicIslandMode: Bool) -> Bool {
    isOpen || isDynamicIslandMode
}

/// 面板背景**顶部不透明黑带**的高度（pt）——玻璃两档不得进入这一段。
///
/// **为什么必须有这一段**（2026-09-28 用户反馈「不能强硬拉伸，菜单栏里面的图标都变形了」）：
/// 玻璃两档都是 **behindWindow** 的材质——`NSGlassEffectView`（`LiquidGlassBackground`）与
/// `NSVisualEffectView`（`.hudWindow` + `.behindWindow`）采样的都是**窗口背后**的画面。
/// 而面板的顶边与**系统 UI 带**同高：刘海屏上窗口顶边在 `screen.maxY + notchTopScreenBleedAmount`，
/// 非刘海屏上浮动药丸的顶边在屏顶下方 `dynamicIslandTopOffset`。于是菜单栏图标被采进玻璃里，
/// 看上去就是「图标被糊成一团 / 被拉伸变形」。
///
/// 判据与 `ModuleHUDWindowHost.topInset(safeAreaTop:frameMaxY:visibleFrameMaxY:)` 同口径，
/// 但**取两者的较大值再 +1**（2026-09-29 用户反馈「顶部的高度不够，比系统的黑色区域要窄」）：
/// - **刘海屏**（`safeAreaTop > 0`）→ 刘海高度（`safeAreaInsets.top`）与菜单栏高度取大；
/// - **非刘海屏** → 菜单栏高度（屏顶与 `visibleFrame` 顶之差）。
///
/// **为什么要 max 再 +1**：刘海屏上 `safeAreaInsets.top`（本机内置屏实测 32）比「屏顶 −
/// `visibleFrame` 顶」（同一块屏实测 33）**小 1pt**——两者不是同一个量（前者是系统给的安全区，
/// 后者是菜单栏占掉的区域，含窗口顶边那一像素的取整差）。只取刘海高度时，玻璃从黑带下面露出的
/// 正是这 1pt，于是面板顶部与系统黑区之间露出一条缝（用户看到的「高度不够」）。
/// 取 `max(刘海, 菜单栏) + 1` 后这条带至少盖住系统黑区，并对两种屏、两种口径都对得上。
///
/// 这段是「系统的 UI 带」，面板在那里必须不透明：与折叠态纯黑同口径
/// （折叠态本来就是纯黑，见 `panelBackgroundUsesStyle`）。
///
/// **`panelTopBleed`：面板框的顶边比**屏顶**高出多少**（刘海屏 = `notchTopScreenBleedAmount`，
/// 非刘海屏的浮动药丸 = 0；见 `mainLayoutBase` 的 `.padding(.top, ...)`）。黑带是从**面板框顶边**
/// 往下画的，而「系统 UI 带」是从**屏顶**往下量的；两者起点不同，所以要把这段差额补进高度里，
/// 否则屏幕上能看到的黑带只有 `高度 − bleed`（本机实测：配 34 时屏幕上只有 0…29.5 这一段是黑的，
/// 露出 4pt 玻璃 —— 正是用户说的「比系统黑区窄」）。
///
/// 负值 / 非有限值一律夹到 0（= 不加黑带，退回改造前观感，不产生负高度）；
/// 系统 UI 带 ≤ 0 时同样返回 0（「取不到屏」与「根本没有系统 UI 带」都不该凭空多出一条黑边）。
///
/// 抽成纯函数是为了可测：入参都是**数值**，调用点从屏上取完再传进来，
/// 判据本身不读单例、不碰视图状态（同 `panelBackgroundUsesStyle`）。
/// 取屏的那层壳是 `panelTopOpaqueBandHeight(for:panelTopBleed:)`。
func panelTopOpaqueBandHeight(
    safeAreaTop: CGFloat,
    menuBarHeight: CGFloat,
    panelTopBleed: CGFloat = 0
) -> CGFloat {
    let notch = safeAreaTop.isFinite ? safeAreaTop : 0
    let menuBar = menuBarHeight.isFinite ? menuBarHeight : 0
    let systemUIBand = max(notch, menuBar, 0)
    guard systemUIBand > 0 else { return 0 }
    let bleed = panelTopBleed.isFinite ? max(panelTopBleed, 0) : 0
    return bleed + systemUIBand + 1
}

/// 某块屏上「面板顶部不透明黑带」的高度；**取不到屏时 0**（不加黑带，退回改造前观感）。
///
/// 两个数值的取法与 `ModuleHUDWindowHost.topInset` 一致：刘海屏用 `safeAreaInsets.top`，
/// 非刘海屏用 `frame.maxY - visibleFrame.maxY`（菜单栏高度）。
func panelTopOpaqueBandHeight(for screen: NSScreen?, panelTopBleed: CGFloat = 0) -> CGFloat {
    guard let screen else { return 0 }
    return panelTopOpaqueBandHeight(
        safeAreaTop: screen.safeAreaInsets.top,
        menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY,
        panelTopBleed: panelTopBleed
    )
}

// MARK: - 展开态「右下角拖动调宽高」的纯函数与可调范围

/// 展开态尺寸的**可调范围**（宽下界 / 宽上界 / 高下界 / 高上界），与 `openNotchSize` 的夹取**逐字同源**：
///
/// - 宽下界 = `max(currentRecommendedMinimumNotchWidth(), sideLyricsRequiredNotchWidth())`
///   ——`openNotchSize` 的 `min(max(storedWidth, minWidth, sideLyricsRequiredNotchWidth()), maxWidth)`
///   里那两个下界项；宽上界 = `maxAllowedNotchWidth()`（屏宽 − 60，最小 400）——同一个上界函数；
/// - 高下界 = `openNotchHeightRange.lowerBound`（120）；高上界 =
///   `effectiveOpenNotchHeightUpperBound(screenVisibleHeight:)`（`min(850, 屏 visibleFrame.height × 0.9)`）
///   ——与 `clampedOpenNotchHeight`、设置页滑块同一个上界函数。
///
/// **为什么必须同源**：拖出来的值会原样写进 `Defaults`，而 `openNotchSize` 每次还会再夹一遍；
/// 若这里放行一个会被夹回去的值，用户看到的是「拖了没用」（与设置页滑块上界的取舍同一条理由）。
/// 取屏口径也刻意与 `openNotchSize` 保持一致（`NSScreen.main`），否则读数会与实际生效的尺寸错开半个档。
@MainActor
func currentOpenNotchResizeBounds() -> (
    minWidth: CGFloat, maxWidth: CGFloat, minHeight: CGFloat, maxHeight: CGFloat
) {
    (
        minWidth: max(currentRecommendedMinimumNotchWidth(), sideLyricsRequiredNotchWidth()),
        maxWidth: maxAllowedNotchWidth(),
        minHeight: openNotchHeightRange.lowerBound,
        maxHeight: effectiveOpenNotchHeightUpperBound(screenVisibleHeight: NSScreen.main?.visibleFrame.height)
    )
}

/// 展开态「右下角拖动改宽高」的尺寸计算（纯函数）：**拖动起点尺寸 + 累计位移 → 夹取后的新尺寸**。
///
/// 位移方向（把手在面板右下角）：向右拖（`translation.width > 0`）变宽、向下拖（`translation.height > 0`）
/// 变高；向左 / 向上拖则缩小。两个方向都按 `min…max` 夹取，夹取式与
/// `openNotchSize` / `clampedOpenNotchHeight` 一致（`min(max(v, 下界), 上界)`；下界大于上界时上界生效）。
///
/// **起点必须由调用方在拖动开始时捕获一次**（不是每帧读当前值再累加）：拖动的每一帧都会写 `Defaults`
/// 并触发面板 / 窗口重排，把手自己会跟着鼠标跑；若用当前值累加，下一帧读到的是"已经追过一次"的尺寸，
/// 同一段位移被重复计入（越拖越快）。固定起点 + 累计位移是唯一稳定的口径。
///
/// **位移必须由屏幕光标量出来**（`panelResizeTranslation(from:to:)`），不能直接用 SwiftUI
/// `DragGesture` 的 `value.translation`：那套坐标空间会随着面板 / 窗口的**自身重排**移动
/// （把手贴右下角、面板扩宽时窗口居中改位），量出来的是「光标位移 − 把手位移」，于是拖动位移
/// 被自己放大或吃掉（本机实测 2026-09-29：光标右移 100pt，`openNotchWidth` 涨到 1106＝+136pt，
/// 即 1.36×，且中途还会随帧率抖）。用屏幕光标只保留「手移动了多少」这一个量。
///
/// 非有限值一律退回下界（同 `clampedOpenNotchHeight` 对 `NaN` 的处理）：不把 `NaN` / `∞`
/// 写进 `Defaults`（那会让面板尺寸整块失效），也不让一次异常事件把尺寸弹到边界。
///
/// 抽成纯函数是为了可测：入参都是纯值，不读 `Defaults`、不取屏、不碰视图状态
/// （同 `panelBackgroundUsesStyle` 一族）。
func resizedPanelSize(
    start: CGSize,
    translation: CGSize,
    minWidth: CGFloat,
    maxWidth: CGFloat,
    minHeight: CGFloat,
    maxHeight: CGFloat
) -> CGSize {
    let dx = translation.width.isFinite ? translation.width : 0
    let dy = translation.height.isFinite ? translation.height : 0
    let startWidth = start.width.isFinite ? start.width : minWidth
    let startHeight = start.height.isFinite ? start.height : minHeight
    return CGSize(
        width: min(max(startWidth + dx, minWidth), maxWidth),
        height: min(max(startHeight + dy, minHeight), maxHeight)
    )
}

/// 把「两次屏幕光标位置」换成 `resizedPanelSize` 要的位移（纯函数）：**正宽 = 向右、正高 = 向下**。
///
/// 为什么不用 `DragGesture.value.translation`：那个值是在**视图 / 窗口自身的坐标空间**里量的，
/// 而拖动过程中面板每帧都在重排、窗口还在居中改位（宽每涨 1pt，右边缘只走 0.5pt、左边缘反向走 0.5pt），
/// 于是量到的位移会把「面板自己动了多少」算进去——实测光标右移 100pt 得到 +136pt（1.36×，
/// 见 `resizedPanelSize` 的注释）。屏幕光标（`NSEvent.mouseLocation`，AppKit 全局坐标、y 向上）
/// 与视图 / 窗口怎么重排无关，量到的就是用户手移动了多少：这才是「1:1 跟手」的口径。
///
/// **y 取反**：AppKit 屏幕坐标 y 向上，而 `resizedPanelSize` 的 `height` 是「向下为正」——
/// 用户向下拖（y 变小）得到正的 `height`，面板变高。
///
/// 非有限值按 0 处理（同 `resizedPanelSize` 对非有限位移的处理）：不让一次异常读数把尺寸弹到边界。
func panelResizeTranslation(from start: CGPoint, to current: CGPoint) -> CGSize {
    let dx = current.x - start.x
    let dy = start.y - current.y
    return CGSize(width: dx.isFinite ? dx : 0, height: dy.isFinite ? dy : 0)
}

/// 展开态右下角拖动把手**是否出现**（纯函数，D-16）：**只在展开态、非极简、且手动高度模式**。
///
/// 两条否掉的档都是同一条理由——**拖了没用**：
/// - **极简模式**刻意不显示：那一档的尺寸来源是 `minimalisticOpenNotchSize`（固有基准 + 歌词 /
///   提醒 / 计时器的附加高度），`openNotchSize` 与 `Defaults[.openNotchWidth]/[.openNotchHeight]`
///   完全不参与——`DynamicIslandViewModel` 的宽度 sink 自己也带着 `!enableMinimalisticUI` 前置。
///   把手若照常出现，拖动只会写进一个**当场没有任何效果**的值（下次切回标准展开态才突然生效）。
/// - **自适应高度（auto）**同理：那一档的面板高度由**内容**决定（`PanelAutoHeight` 的收敛结果），
///   拖动写的 `openNotchHeight` 是手动档的值，当场同样没有任何效果（p5-home-blocks / T6，
///   docs/29 §做法 机制六 边界 ③ / §已知限制 6 的「手动高度模式下会留白」也是同一条）。
///
/// 抽成文件级纯函数的理由与 `resizedPanelSize` / `panelResizeTranslation` 一族相同：判据在视图里
/// 是 `private var`，用例够不到，D-16 就只能靠"测试里重抄一遍表达式"假通过。
/// `isOpen` 传 `vm.notchState == .open`、`isMinimalistic` 传 `Defaults[.enableMinimalisticUI]`、
/// `heightMode` 传 `Defaults[.panelHeightMode]`（`PanelAutoHeight.modeManual` 才出现）。
func showsPanelResizeHandle(isOpen: Bool, isMinimalistic: Bool, heightMode: String) -> Bool {
    isOpen && !isMinimalistic && !PanelAutoHeight.isAuto(heightMode)
}

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @EnvironmentObject var webcamManager: WebcamManager

    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var timerManager = TimerManager.shared
    @ObservedObject var reminderManager = ReminderLiveActivityManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var statsManager = StatsManager.shared
    @ObservedObject var recordingManager = ScreenRecordingManager.shared
    @ObservedObject var privacyManager = PrivacyIndicatorManager.shared
    @ObservedObject var doNotDisturbManager = DoNotDisturbManager.shared
    @ObservedObject var lockScreenManager = LockScreenManager.shared
    @ObservedObject var capsLockManager = CapsLockManager.shared
    @ObservedObject var extensionLiveActivityManager = ExtensionLiveActivityManager.shared
    @ObservedObject var extensionNotchExperienceManager = ExtensionNotchExperienceManager.shared
    @ObservedObject var localSendService = LocalSendService.shared
    @State private var downloadManager = DownloadManager.shared
    @ObservedObject var shelfState = ShelfStateViewModel.shared
    // 注：本视图**不再观察** `ModuleRegistry`（D-23）：模块瞬时浮层由内核的独立窗口渲染
    //（`Kernel/ModuleHUDWindow.swift`），关闭态链里既没有浮层分支、判据也不再读注册表。
    // 仍然读注册表的两处是 hover 抑制（`shouldSuppressHoverOpen(activeHUD:)`），
    // 它们在 mouseDown 回调 / 延时任务里取值，不需要视图观察。
    
    @Default(.enableStatsFeature) var enableStatsFeature
    // 拖拽落点的宿主门槛键（p5-home-blocks / T5 修复 P3）：`dragDetector` 原先裸读它，设置页
    // 「面板组件」节把暂存器关掉之后，落点要等本视图因别的原因重绘才消失（同表达式的
    // `enableMinimalisticUI` 本就有观察，见下方声明——这次把那半边也改成读属性）。
    @Default(.dynamicShelf) var dynamicShelf
    @Default(.showCpuGraph) var showCpuGraph
    @Default(.showMemoryGraph) var showMemoryGraph
    @Default(.showGpuGraph) var showGpuGraph
    @Default(.showNetworkGraph) var showNetworkGraph
    @Default(.showDiskGraph) var showDiskGraph
    @Default(.enableReminderLiveActivity) var enableReminderLiveActivity
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.timerDisplayMode) var timerDisplayMode
    @Default(.enableHorizontalMusicGestures) var enableHorizontalMusicGestures
    @Default(.reminderPresentationStyle) var reminderPresentationStyle
    @Default(.timerShowsCountdown) var timerShowsCountdown
    @Default(.timerShowsProgress) var timerShowsProgress
    @Default(.timerProgressStyle) var timerProgressStyle
    @Default(.timerIconColorMode) var timerIconColorMode
    @Default(.timerSolidColor) var timerSolidColor
    @Default(.timerPresets) var timerPresets
    @Default(.showCapsLockLabel) var showCapsLockLabel
    @Default(.capsLockIndicatorTintMode) var capsLockTintMode
    @Default(.enableDoNotDisturbDetection) var enableDoNotDisturbDetection
    @Default(.showDoNotDisturbIndicator) var showDoNotDisturbIndicator
    @Default(.enableScreenRecordingDetection) var enableScreenRecordingDetection
    @Default(.enableCapsLockIndicator) var enableCapsLockIndicator
    @Default(.enableExtensionLiveActivities) var enableExtensionLiveActivities
    @Default(.showStandardMediaControls) var showStandardMediaControls
    @Default(.externalDisplayStyle) var externalDisplayStyle
    @Default(.hideNonNotchUntilHover) var hideNonNotchUntilHover
    @Default(.terminalStickyMode) var terminalStickyMode
    
    // Battery settings reactivity
    @Default(.showPowerStatusNotifications) var showPowerStatusNotifications
    @Default(.showChargingBatteryHUD) var showChargingBatteryHUD
    @Default(.showLowBatteryHUD) var showLowBatteryHUD
    @Default(.showFullBatteryHUD) var showFullBatteryHUD
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.lowBatteryHUDStyle) var lowBatteryHUDStyle
    @Default(.fullBatteryHUDStyle) var fullBatteryHUDStyle
    
    // Dynamic sizing based on view type and graph count with smooth transitions
    var dynamicNotchSize: CGSize {
        let baseSize = Defaults[.enableMinimalisticUI] ? minimalisticOpenNotchSize(isDynamicIslandMode: isDynamicIslandMode) : openNotchSize
        
        // When inline sneak peek is active in closed notch, use the wider inline width
        // so the outer maxWidth frame doesn't clip the expanded content
        let airPodsListeningModeSneakActive = vm.notchState == .closed
            && coordinator.sneakPeek.show
            && coordinator.sneakPeek.type == .bluetoothAudio
            && coordinator.sneakPeek.value < 0
            && AirPodsListeningMode.fromHUDSymbol(coordinator.sneakPeek.icon) != nil
        let inlineSneakPeekActive = vm.notchState == .closed
            && (
                coordinator.expandingView.show
                    && (coordinator.expandingView.type == .music || coordinator.expandingView.type == .timer)
                    && Defaults[.sneakPeekStyles] == .inline
                || airPodsListeningModeSneakActive
            )
            && Defaults[.enableSneakPeek]
        if inlineSneakPeekActive {
            let inlineWidth: CGFloat = airPodsListeningModeSneakActive
                ? InlineHUD.airPodsListeningModeWidth(
                    closedNotchWidth: vm.closedNotchSize.width,
                    gestureProgress: gestureProgress,
                    minimalistic: Defaults[.enableMinimalisticUI]
                ) + notchHorizontalPadding * 2
                : 460
            return CGSize(width: max(baseSize.width, inlineWidth), height: baseSize.height)
        }
        
        // Handle battery HUD expansion sizing
        if vm.notchState == .closed && 
           coordinator.expandingView.show && 
           coordinator.expandingView.type == .battery &&
           isBatteryHUDVisibleOnCurrentScreen {
            
            if let kind = batteryModel.activeTemporaryHUDKind {
                let style: BatteryNotificationStyle = {
                    switch kind {
                    case .charging: return .compact
                    case .lowBattery: return Defaults[.lowBatteryHUDStyle]
                    case .fullBattery: return Defaults[.fullBatteryHUDStyle]
                    }
                }()
                
                var width = vm.closedNotchSize.width
                var height = vm.effectiveClosedNotchHeight
                
                switch (kind, style) {
                case (.charging, _), (.lowBattery, .compact), (.fullBattery, .compact):
                    width += 180
                case (.lowBattery, .standard):
                    width += 100
                    height += 75
                case (.fullBattery, .standard):
                    width += 80
                    height += 70
                }
                
                return CGSize(width: width, height: height)
            }
        }
        
        // 计时器的 250pt 高度档：判据认模块路径（docs/20 §做法 机制六），只比 `.timer` 会让
        // 「计时器在跑 + 悬浮展开」回落到默认高度档。
        if coordinator.isTimerSurfaceSelected() {
            return CGSize(width: baseSize.width, height: 250) // Extra height for timer presets
        }
        
        if coordinator.currentView == .notes {
            let preferredHeight = coordinator.notesLayoutState.preferredHeight
            let resolvedHeight = max(baseSize.height, preferredHeight)
            return CGSize(width: baseSize.width, height: resolvedHeight)
        }

        if coordinator.currentView == .clipboard {
            // Clipboard has its own fixed height source; don't inherit whatever notes
            // layout state happens to be set.
            let resolvedHeight = max(baseSize.height, NotesLayoutState.list.preferredHeight)
            return CGSize(width: baseSize.width, height: resolvedHeight)
        }

        if coordinator.currentView == .terminal {
            // Dynamic height: up to terminalMaxHeightFraction of screen, min 300pt
            let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
            let maxFraction = Defaults[.terminalMaxHeightFraction]
            let terminalHeight = min(screenHeight * maxFraction, max(300, screenHeight * maxFraction))
            return CGSize(width: baseSize.width, height: terminalHeight)
        }

        if coordinator.currentView == .extensionExperience {
            if let preferredHeight = extensionTabPreferredHeight(baseSize: baseSize) {
                return CGSize(width: baseSize.width, height: preferredHeight)
            }
            return baseSize
        }

        if enableMinimalisticUI,
           coordinator.currentView == .home,
           let preferredHeight = extensionMinimalisticPreferredHeight(baseSize: baseSize) {
            return CGSize(width: baseSize.width, height: preferredHeight)
        }
        
        guard coordinator.currentView == .stats else {
            return baseSize
        }
        
        let rows = statsRowCount()
        if rows <= 1 {
            return baseSize
        }
        
        let additionalRows = max(rows - 1, 0)
        let extraHeight = CGFloat(additionalRows) * statsAdditionalRowHeight
        return CGSize(width: baseSize.width, height: baseSize.height + extraHeight)
    }
    

    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var lastHapticTime: Date = Date()
    @State private var hoverClickMonitor: Any?
    @State private var hoverClickLocalMonitor: Any?
    @State private var stickyTerminalClickMonitor: Any?
    @State private var hiddenEdgeHoverPollingTask: Task<Void, Never>?
    @State private var isHoveringClosedMusicWaveformControl: Bool = false

    // 展开态右下角拖动把手（D-29）
    /// 拖动是否进行中（圆点提亮用，并让面板在拖动期间不因 hover 离开而收起，见 `shouldPreventAutoClose`）。
    @State private var isPanelResizing: Bool = false
    /// 拖动**起点**尺寸：第一次 `onChanged` 时捕获一次，整个拖动期间不再变（见 `resizedPanelSize` 的注释）。
    @State private var panelResizeDragStartSize: CGSize?
    /// 拖动**起点光标**（`NSEvent.mouseLocation`，屏幕坐标、y 向上）：位移由它和当前光标算
    /// （见 `panelResizeTranslation(from:to:)` 的注释——不能用 `DragGesture` 的坐标空间）。
    @State private var panelResizeDragStartMouseLocation: CGPoint?
    /// 读数胶囊当前显示的尺寸（`nil` = 不显示）。
    @State private var panelResizeReadout: CGSize?
    /// 读数淡出的延时任务（新的拖动会取消它）。
    @State private var panelResizeReadoutHideTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero
    @State private var skipGestureActiveDirection: MusicManager.SkipDirection?
    @State private var isMusicControlWindowVisible = false
    @State private var pendingMusicControlTask: Task<Void, Never>?
    @State private var musicControlHideTask: Task<Void, Never>?
    @State private var musicControlVisibilityDeadline: Date?
    @State private var isMusicControlWindowSuppressed = false
    @State private var hasPendingMusicControlSync = false
    @State private var pendingMusicControlForceRefresh = false
    @State private var musicControlSuppressionTask: Task<Void, Never>?

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.musicControlWindowEnabled) var musicControlWindowEnabled
    @Default(.showNotHumanFace) var showNotHumanFace
    @Default(.useModernCloseAnimation) var useModernCloseAnimation
    @Default(.enableMinimalisticUI) var enableMinimalisticUI
    /// 面板高度模式（p5-home-blocks / T6，默认 `"auto"`）：右下角拖动把手是**手动档专属**
    /// （D-16，判据在文件级 `showsPanelResizeHandle(...)`）——auto 下拖动写的键当场没有效果。
    /// 用 `@Default` 而不是裸读：设置页切档后本视图要**当场**重绘，把手跟着出现 / 消失。
    @Default(.panelHeightMode) var panelHeightMode
    /// 主面板背景样式（2026-09-28 新增，默认纯黑）；生效范围见 `panelBackgroundUsesStyle(isOpen:isDynamicIslandMode:)`。
    @Default(.notchPanelBackgroundStyle) var notchPanelBackgroundStyle

    private static let musicControlLogFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private func logMusicControlEvent(_ message: String) {
#if DEBUG
        let timestamp = Self.musicControlLogFormatter.string(from: Date())
        print("[MusicControl] \(timestamp): \(message)")
#endif
    }

    private func runAfter(_ delay: TimeInterval, _ action: @escaping @Sendable @MainActor () -> Void) {
        guard delay >= 0 else { return }
        Task { @MainActor in
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            action()
        }
    }

    private func requestMusicControlWindowSyncIfHidden(forceRefresh: Bool = false, delay: TimeInterval = 0) {
        guard !isMusicControlWindowVisible else { return }
        enqueueMusicControlWindowSync(forceRefresh: forceRefresh, delay: delay)
    }
    private var dynamicNotchResizeAnimation: Animation? {
        nil
    }
    
    private let zeroHeightHoverPadding: CGFloat = 10
    private let statsAdditionalRowHeight: CGFloat = statsSecondRowContentHeight + statsGridSpacingHeight
    private let musicControlPauseGrace: TimeInterval = 5
    private let musicControlResumeDelay: TimeInterval = 0.24

    // 展开态右下角拖动把手（D-29）的几何：9pt 圆点 + 32pt 命中框，命中框距面板右下角各 14pt。
    //
    // **命中框 20 → 32pt（2026-09-29，用户反馈「很费劲」）**：原来的 20pt 框「看着够大」，但
    // 可命中面积还被面板自己的内容形状（`NotchShape`）切掉一块——形状的右边在 `maxX − topR`
    // （开态 topR = 19）处收进去，右下角那圈是二次曲线（不是圆角矩形），而 `.contentShape`
    // 的裁剪对子树的手势命中同样生效。于是 20pt 框（距边 14pt、中心距边 24pt）实际只有
    // 约 15×20pt 能按到，右侧那 5pt 是死区。放大到 32pt 后（边距仍 14pt、圆点中心改到距边 30pt），
    // 可命中面积 ≈ 27×32pt（约 2.9×），只有最外那 5pt 仍压在裁剪线外。
    // 取值取舍：再放大收益递减（可命中区左/上边界已经推进到面板内容区里），32pt 是可命中面积
    // 接近翻三倍、而圆点只内移 6pt 的最小改动。
    private let panelResizeHandleDotDiameter: CGFloat = 9
    private let panelResizeHandleHitSize: CGFloat = 32
    private let panelResizeHandleEdgeInset: CGFloat = 14

    // MARK: - Tab switch direction for smooth transitions
    
    private var tabSwitchTransition: AnyTransition {
        if coordinator.tabSwitchForward {
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        } else {
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }

    /// 展开内容的过渡身份（接缝 S5）：`NotchViews.module` 无关联值（D-02），
    /// 所以「哪个模块」要单独并进来——只 `.id(currentView)` 的话，两个模块之间切换
    /// 身份不变、过渡不重放（docs/13 已知限制 7）。
    private struct ExpandedContentIdentity: Hashable {
        let view: NotchViews
        let moduleID: String?
    }

    private var expandedContentIdentity: ExpandedContentIdentity {
        ExpandedContentIdentity(view: coordinator.currentView, moduleID: coordinator.selectedModuleID)
    }
    
    private var standardMediaControlsActive: Bool {
        showStandardMediaControls && !enableMinimalisticUI
    }

    private var closedMusicContentEnabled: Bool {
        enableMinimalisticUI || showStandardMediaControls
    }

    private var isMusicHUDDeferredAfterUnlock: Bool {
        lockScreenManager.shouldDelayPostUnlockMusicHUD
    }

    private var interactionsEnabled: Bool {
        !lockScreenManager.isLocked
    }

    private var isIslandMode: Bool {
        isDynamicIslandMode
    }

    private var notchHorizontalPadding: CGFloat {
        guard vm.notchState == .open else {
            return activeCornerRadiusInsets.closed.bottom
        }
        if Defaults[.cornerRadiusScaling] {
            return activeCornerRadiusInsets.opened.top - 5
        }
        return activeCornerRadiusInsets.opened.bottom - 5
    }

    private var bodyHoverAreaPadding: CGFloat {
        if vm.notchState == .open && Defaults[.extendHoverArea] {
            return 0
        }
        return vm.effectiveClosedNotchHeight == 0 ? zeroHeightHoverPadding : 0
    }

    private var notchBottomPadding: CGFloat {
        currentShadowPadding + bodyHoverAreaPadding
    }

    private var pillTopOffset: CGFloat {
        isIslandMode ? dynamicIslandTopOffset : 0
    }

    private func closedMusicPairingEligible(hasActiveMusicSnapshot: Bool) -> Bool {
        vm.notchState == .closed
            && hasActiveMusicSnapshot
            && coordinator.musicLiveActivityEnabled
            && closedMusicContentEnabled
            && !vm.hideOnClosed
            && !lockScreenManager.isLocked
            && !isMusicHUDDeferredAfterUnlock
    }

    private var closedLiveActivitySwapTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.965, anchor: .center))
                .animation(.spring(response: 0.34, dampingFraction: 0.88)),
            removal: .opacity
                .combined(with: .scale(scale: 0.92, anchor: .center))
                .animation(.smooth(duration: 0.22))
        )
    }
    
    // Use minimalistic corner radius ONLY when opened, keep normal when closed
    private var activeCornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) {
        if enableMinimalisticUI {
            // Keep normal closed corner radius, use minimalistic when opened
            return (opened: minimalisticCornerRadiusInsets.opened, closed: cornerRadiusInsets.closed)
        }
        return cornerRadiusInsets
    }
    
    private var currentShadowPadding: CGFloat {
        notchShadowPaddingValue(isMinimalistic: enableMinimalisticUI)
    }

    private var currentNotchShape: NotchShape {
        let topRadius = (vm.notchState == .open && Defaults[.cornerRadiusScaling])
            ? activeCornerRadiusInsets.opened.top
            : activeCornerRadiusInsets.closed.top
        let bottomRadius = (vm.notchState == .open && Defaults[.cornerRadiusScaling])
            ? activeCornerRadiusInsets.opened.bottom
            : activeCornerRadiusInsets.closed.bottom
        return NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
    }

    /// Whether the current screen should render as a Dynamic Island pill
    /// rather than the standard notch shape. Always false on physical notch screens.
    private var isDynamicIslandMode: Bool {
        shouldUseDynamicIslandMode(for: currentScreenName)
    }

    private var currentScreenName: String {
        vm.screen ?? coordinator.selectedScreen
    }

    /// Whether the current screen lacks a physical notch.
    private var isNonNotchScreen: Bool {
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == currentScreenName }) else {
            return true
        }
        return screen.safeAreaInsets.top <= 0
    }

    /// Whether the global sneak peek is visible on this specific screen.
    private var isSneakPeekVisibleOnCurrentScreen: Bool {
        guard coordinator.sneakPeek.show else { return false }
        guard Defaults[.showOnAllDisplays] else { return true }
        guard let targetScreenName = coordinator.sneakPeek.targetScreenName else { return true }
        return currentScreenName == targetScreenName
    }

    /// Whether the notch/island should hide off-screen when closed on a non-notch display.
    /// Temporarily reveals the notch when a sneakPeek HUD (volume, brightness, music, etc.) is active.
    ///
    /// Modified for Gourd (2026-09-28, D-23)：模块瞬时浮层（如通知）**不再是**这里的豁免项——
    /// 它已由内核的独立窗口渲染（`Kernel/ModuleHUDWindow.swift`），不在关闭态链里，
    /// 所以外接屏上「关闭态照常隐藏 + 浮层窗口自己出现」两件事互不干扰。
    private var shouldHideUntilHover: Bool {
        shouldHideClosedContentUntilHover(
            hideSetting: hideNonNotchUntilHover,
            isNonNotch: isNonNotchScreen,
            isClosed: vm.notchState == .closed,
            hasSneakPeek: isSneakPeekVisibleOnCurrentScreen
        )
    }

    /// Whether the fallback top-edge hover detector should run.
    /// This is only needed when the notch is fully hidden off-screen and
    /// regular `.onHover` hit-testing may not trigger reliably.
    private var shouldUseHiddenEdgeHoverPolling: Bool {
        shouldHideUntilHover && !lockScreenManager.isLocked
    }
    
    /// Whether the LocalSend live activity should be shown
    private var localSendLiveActivityActive: Bool {
        localSendService.isSending || 
        localSendService.transferState == .completed ||
        isLocalSendFailedOrRejected
    }
    
    private var isLocalSendFailedOrRejected: Bool {
        if case .failed = localSendService.transferState { return true }
        if case .rejected = localSendService.transferState { return true }
        return false
    }

    /// Pill shape for Dynamic Island mode with animated corner radius transitions.
    private var currentPillShape: DynamicIslandPillShape {
        let radius: CGFloat
        if vm.notchState == .open {
            radius = enableMinimalisticUI
                ? minimalisticCornerRadiusInsets.opened.top
                : dynamicIslandPillCornerRadiusInsets.opened
        } else {
            // Use half the closed height for a true capsule shape
            radius = max(vm.closedNotchSize.height / 2, dynamicIslandPillCornerRadiusInsets.closed.standard)
        }
        return DynamicIslandPillShape(cornerRadius: radius)
    }

    private var isBatteryHUDVisibleOnCurrentScreen: Bool {
        guard coordinator.expandingView.show, coordinator.expandingView.type == .battery else { return false }
        guard showPowerStatusNotifications else { return false }
        guard batteryModel.activeTemporaryHUDKind != nil else { return false }
        if showOnAllDisplays { return true }
        guard let targetScreenName = batteryModel.activeTemporaryHUDTargetScreenName else { return true }
        return currentScreenName == targetScreenName
    }

    private var isCurrentScreenExpansionVisible: Bool {
        guard coordinator.expandingView.show else { return false }
        if coordinator.expandingView.type == .battery {
            return isBatteryHUDVisibleOnCurrentScreen
        }
        return true
    }

    private var currentScreenExpansionType: SneakContentType? {
        isCurrentScreenExpansionVisible ? coordinator.expandingView.type : nil
    }

    private var displayedBatteryHUDLevel: Int {
        let resolvedLevel = batteryModel.activeTemporaryHUDLevelOverride
            ?? Int(batteryModel.levelBattery.rounded())
        return min(max(resolvedLevel, 0), 100)
    }

    private var displayedBatteryHUDUsesLowPowerMode: Bool {
        batteryModel.activeTemporaryHUDLowPowerModeOverride ?? batteryModel.isInLowPowerMode
    }


    private var activeClosedBatterySurfaceShape: AnyShape? {
        guard vm.notchState == .closed else { return nil }
        guard isBatteryHUDVisibleOnCurrentScreen else { return nil }
        guard let kind = batteryModel.activeTemporaryHUDKind else { return nil }

        if isDynamicIslandMode {
            let radius = dynamicIslandPillCornerRadiusInsets.opened
            return AnyShape(DynamicIslandPillShape(cornerRadius: radius))
        } else {
            let topRadius = activeCornerRadiusInsets.closed.top
            let bottomRadius: CGFloat = {
                switch resolvedBatteryNotificationStyle(for: kind) {
                case .compact:
                    return activeCornerRadiusInsets.closed.bottom
                case .standard:
                    return kind == .fullBattery ? 36 : 40
                }
            }()
            return AnyShape(NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius))
        }
    }

    private func resolvedBatteryNotificationStyle(for kind: BatteryTemporaryHUDKind) -> BatteryNotificationStyle {
        switch kind {
        case .charging:
            return .compact
        case .lowBattery:
            return lowBatteryHUDStyle
        case .fullBattery:
            return fullBatteryHUDStyle
        }
    }


    /// Resolves the clip/content shape per-screen: pill on non-notch screens
    /// when dynamic island mode is active, standard notch shape otherwise.
    private var resolvedClipShape: AnyShape {
        if let activeClosedBatterySurfaceShape {
            return activeClosedBatterySurfaceShape
        }
        if isDynamicIslandMode {
            return AnyShape(currentPillShape)
        }
        return AnyShape(currentNotchShape)
    }

    var body: some View {
        installRootLifecycleHandlers(on: rootBodyView)
    }

    private var mainLayoutBase: some View {
        NotchLayout()
            .frame(alignment: .top)
            .padding(.horizontal, notchHorizontalPadding)
            .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
            .padding(.top, isIslandMode ? 0 : notchTopScreenBleedAmount)
            .background(panelBackground)
            .clipShape(resolvedClipShape)
            // 展开态右下角的拖动把手（D-29）：画在 `clipShape` **之后**（不受裁剪影响，位置由
            // `panelResizeHandleEdgeInset` 保证落在面板内）与 `compositingGroup` / `shadow` 之前。
            // 它不参与面板的尺寸计算（overlay 只是贴在 `mainLayoutBase` 的框上），
            // 也不影响下面 `configuredMainLayout` 里的 `onTapGesture` / `panGesture`（见
            // `panelResizeHandle` 的 `highPriorityGesture`）。**出现判据是文件级纯函数**
            // （展开 + 非极简 + 手动高度模式，三者缺一不出现；p5-home-blocks / T6 / D-16）。
            .overlay(alignment: .bottomTrailing) {
                if showsPanelResizeHandle(
                    isOpen: vm.notchState == .open,
                    isMinimalistic: enableMinimalisticUI,
                    heightMode: panelHeightMode
                ) {
                    panelResizeHandle
                        .padding(.trailing, panelResizeHandleEdgeInset)
                        .padding(.bottom, panelResizeHandleEdgeInset)
                }
            }
            .compositingGroup()
            .shadow(
                color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                    ? .black.opacity(0.6)
                    : .clear,
                radius: Defaults[.cornerRadiusScaling] ? 10 : 5
            )
            // Extra horizontal inset for Dynamic Island mode so the shadow
            // is not clipped by the outer frame constraint
            .padding(.horizontal, isIslandMode ? dynamicIslandShadowInset : 0)
            .padding(.bottom, isIslandMode ? dynamicIslandShadowInset : 0)
            .padding(.top, pillTopOffset)
            .accessibilityIdentifier("GourdNotch")
    }

    /// 主面板底：按 `notchPanelBackgroundStyle` 三选一（2026-09-28 用户反馈「看下这个显示的内容
    /// 是否可以走液态玻璃的模式…增加对应配置」）。
    ///
    /// **状态口径**：玻璃两档只在「展开态」或「非刘海屏的浮动药丸」上生效，其余情况（刘海屏的
    /// 折叠态）一律纯黑——折叠态要与物理刘海对齐融合，玻璃会露出壁纸、形成一块突兀的方块；
    /// 判据是纯函数 `panelBackgroundUsesStyle(isOpen:isDynamicIslandMode:)`（四条组合有单测）。
    ///
    /// 三档的落点与理由：
    /// - `.solidBlack`（**默认**）：`Color.black`——与改造前写死的 `.background(.black)` 逐字一致；
    /// - `.liquidGlass`：苹果私有的 `NSGlassEffectView`（`LiquidGlassBackground` 组件；老系统由组件
    ///   内部退回 `NSVisualEffectView`）。variant 用组件声明的默认档 `.defaultVariant`（= `.v11`，
    ///   组件作者标注「视觉上最讨喜」的一档，通知浮层卡片 / 锁屏自定义玻璃都取同一个默认）——
    ///   主面板没有理由偏离默认（同 `NotificationsModule.NotificationHUDView.cardBackground`）。
    ///   **强制深色外观**（口径同通知浮层卡片）：浅色系统外观下玻璃会渲染成浅色，而面板内的文字
    ///   一律显式白色（会看不清）→ 玻璃上再压一层 `Color.black.opacity(0.35)`；圆角交给下面的
    ///   `.clipShape(resolvedClipShape)`（玻璃半径取裁剪形状的半径，见 `panelGlassCornerRadius`）。
    ///   **关闭组件自带的边缘高光**（`hidesEdgeHighlight: true`，2026-09-29 用户反馈「glass 模式下
    ///   有两个白条」）：这条镜面高光紧贴玻璃轮廓（上边最亮、下边次之），面板上就是紧挨黑带下面是
    ///   一条亮白带、面板底部再来一条。只有**面板这一处用法**关掉它（其余玻璃用法是上游观感）。
    /// - `.frostedGlass`：`NSVisualEffectView` 的 `.hudWindow` + `.behindWindow`，材质层强制
    ///   `darkAqua`（口径同 `EditPanelView.VisualEffectView.forcedAppearance`：`hudWindow` 在浅色
    ///   系统外观下会渲染成浅色磨砂玻璃，与面板内的白字冲突）。
    ///
    /// 三种样式都**只换底**：`.clipShape` / 阴影 / padding / 内容布局一概不动。
    ///
    /// **玻璃两档的顶部另有不透明黑带**（2026-09-28 用户反馈「菜单栏里面的图标都变形了」）：
    /// 玻璃是 behindWindow 材质，会采样窗口背后的菜单栏图标 → 图标被糊成一片。因此玻璃底的构成是
    /// 「顶部黑带（高度见 `panelTopOpaqueBandHeight(safeAreaTop:menuBarHeight:)`）+ 其下的玻璃」
    /// （见 `panelOpaqueTopBand(_:)`，黑带压在玻璃上层）。`.solidBlack` **不受影响**
    /// （整块纯黑，本来就没有采样问题）。
    @ViewBuilder
    private var panelBackground: some View {
        if panelBackgroundUsesStyle(isOpen: vm.notchState == .open, isDynamicIslandMode: isDynamicIslandMode) {
            switch notchPanelBackgroundStyle {
            case .solidBlack:
                Color.black
            case .liquidGlass:
                panelOpaqueTopBand(
                    LiquidGlassBackground(
                        variant: .defaultVariant,
                        cornerRadius: panelGlassCornerRadius,
                        hidesEdgeHighlight: true
                    ) {
                        Color.black.opacity(0.35)
                            .environment(\.colorScheme, .dark)
                    }
                )
                // 玻璃是 AppKit 视图（`NSGlassEffectView`）：不参与命中测试，别吃掉面板上
                // 「点一下就收起 / 拖拽」这一类落在留白上的手势（口径同 `LockScreenMusicPanel`
                // 的 `customLiquidPanelBackdrop`）。顶部黑带一并不参与（保持玻璃档改造前的命中口径）。
                .allowsHitTesting(false)
            case .frostedGlass:
                panelOpaqueTopBand(PanelFrostedGlassBackground())
                    .allowsHitTesting(false)
            }
        } else {
            Color.black
        }
    }

    /// 玻璃底的**两段构成**：顶部不透明黑带 + 其下的玻璃（黑带压在玻璃**上面**，两段无缝）。
    ///
    /// 黑带高度取**当前这块屏**的口径（`max(刘海高度, 菜单栏高度) + 1 + 面板顶边相对屏顶的外扩`，
    /// 见 `panelTopOpaqueBandHeight(safeAreaTop:menuBarHeight:panelTopBleed:)`）：面板顶边与系统 UI 带
    /// 同高，玻璃若从顶边起画就会把菜单栏图标采进来（用户截图里「图标变形」的根因）。
    /// 整块背景仍由 `.clipShape(resolvedClipShape)` 裁剪——**面板形状一点没变**，
    /// 只是顶部那一条由不透明黑替代了玻璃。
    ///
    /// **为什么黑带画在玻璃上层**（2026-09-29 用户反馈「glass 模式下有两个白条」）：
    /// `NSGlassEffectView` 会在自己的轮廓上画一条镜面高光（上边最亮、下边次之，见
    /// `LiquidGlassBackground.hidesEdgeHighlight`）。液态玻璃这一档因此让玻璃四边外扩
    /// （`LiquidGlassEdgeHighlight.overhang`）：外扩之后玻璃的**上边沿被抬到黑带区间
    /// 之内**——`VStack` 里玻璃画在黑带**之后**，高光会浮在黑带上面（仍是白条）；只有把黑带放在
    /// 玻璃**上层**才能压住它。玻璃下边沿与左右两边则被面板自己的裁剪形状切掉。
    private func panelOpaqueTopBand<Glass: View>(_ glass: Glass) -> some View {
        // 黑带做成玻璃的**顶端 overlay**（画在玻璃上层），而不是 `VStack` 的兄弟节点：
        // 外扩之后玻璃的上边沿落在黑带区间内，`VStack` 里玻璃后画 → 高光会浮在黑带上面（白条照旧）。
        // overlay 的框 = 玻璃自己的框，不参与背景的尺寸计算（`ZStack` 会取各子视图最大值，
        // 背景根一超标就会被 `.background` 按居中摆放而整体上移，黑带跟着浮上去）。
        glass.overlay(alignment: .top) {
            Color.black
                .frame(height: panelTopOpaqueBandHeightOnCurrentScreen)
        }
    }

    /// 当前这块屏的顶部不透明黑带高度（`panelTopOpaqueBandHeight(for:panelTopBleed:)` 的取屏壳）。
    /// 取屏口径同 `isNonNotchScreen`：按 `currentScreenName` 在 `NSScreen.screens` 里找。
    /// `panelTopBleed` 取 `isIslandMode ? 0 : notchTopScreenBleedAmount`——与 `mainLayoutBase` 的
    /// `.padding(.top, ...)` 同源（面板框比屏顶高出多少，黑带就要多高才盖得住系统 UI 带）。
    ///
    /// 刻意**不**与全局函数同名：同名时 Swift 会把属性体里的裸名字解析成这个实例属性自己，
    /// 全局函数就调不到了（编译期报 "refers to instance method rather than global function"）。
    private var panelTopOpaqueBandHeightOnCurrentScreen: CGFloat {
        panelTopOpaqueBandHeight(
            for: NSScreen.screens.first { $0.localizedName == currentScreenName },
            panelTopBleed: isIslandMode ? 0 : notchTopScreenBleedAmount
        )
    }

    /// 玻璃背景的圆角：与 `resolvedClipShape` 的半径取**同一来源**，并取上下两档中的**较大值**。
    ///
    /// 为什么必须对齐：背景先画、再被 `.clipShape(resolvedClipShape)` 裁（最终可见形状是两者的交集），
    /// 玻璃自己的圆角若**小于**裁剪半径，角就由玻璃决定（比面板本身的角更方）；
    /// 取较大值则保证裁剪形状始终是决定方（相等或更大都不改变裁剪结果）。
    private var panelGlassCornerRadius: CGFloat {
        if isDynamicIslandMode {
            return currentPillShape.cornerRadius
        }
        let isOpenWithScaling = vm.notchState == .open && Defaults[.cornerRadiusScaling]
        let topRadius = isOpenWithScaling
            ? activeCornerRadiusInsets.opened.top
            : activeCornerRadiusInsets.closed.top
        let bottomRadius = isOpenWithScaling
            ? activeCornerRadiusInsets.opened.bottom
            : activeCornerRadiusInsets.closed.bottom
        return max(topRadius, bottomRadius)
    }

    // MARK: - 展开态右下角拖动把手（D-29）

    /// 右下角拖动把手：9pt 小圆点（拖动 / 悬停时提亮）+ 拖动期间浮在它上方的「宽 × 高」读数胶囊。
    ///
    /// **出现判据在文件级纯函数 `showsPanelResizeHandle(isOpen:isMinimalistic:heightMode:)`**
    /// （p5-home-blocks / T6 从本视图的 `private var` 抽出去的：判据在视图里用例够不到，
    /// D-16 就只能靠"测试里重抄一遍表达式"假通过）——调用点在 `mainLayoutBase` 的 `.overlay` 里。
    ///
    /// 形态与命中：圆点在 32pt 命中框正中，命中框距面板右下角各 `panelResizeHandleEdgeInset`（14pt）；
    /// 读数胶囊贴命中框的右上角、抬到圆点上方（`allowsHitTesting(false)`，不吃拖动）。
    private var panelResizeHandle: some View {
        Circle()
            .fill(Color.white.opacity(isPanelResizing ? 0.85 : 0.45))
            .frame(width: panelResizeHandleDotDiameter, height: panelResizeHandleDotDiameter)
            .frame(width: panelResizeHandleHitSize, height: panelResizeHandleHitSize)
            .contentShape(Rectangle())
            .animation(.smooth(duration: 0.15), value: isPanelResizing)
            .overlay(alignment: .bottomTrailing) {
                if let readout = panelResizeReadout {
                    panelResizeReadoutLabel(readout)
                        .offset(y: -(panelResizeHandleHitSize / 2 + 8))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            // `highPriorityGesture`：面板自己带着 `onTapGesture`（点一下展开 / 收起）与四条
            // `panGesture`（下拉收起等）。子视图的手势本就优先于祖先视图上的 `.gesture`，这里再显式
            // 提一档，保证按住圆点拖动时那几条手势一个都不抢——既不改动它们，也不需要它们配合。
            .highPriorityGesture(panelResizeDragGesture)
            // 把手被移除（收起面板 / 切到极简）时显式归位：拖动被外部打断时 `onEnded` 不会补发
            // （口径同日历行的 `onDisappear` 归位），否则 `isPanelResizing` 悬空为 true —— 面板
            // 之后再也收不起来，下一次拖动还会拿着上一轮的起点尺寸继续算。
            .onDisappear {
                panelResizeDragStartSize = nil
                panelResizeDragStartMouseLocation = nil
                isPanelResizing = false
            }
    }

    /// 读数胶囊：`840 × 400` 这样的纯数字（**不新增本地化 key**——只有数字与乘号）。
    ///
    /// `fixedSize()` 是必须的（2026-09-29 实测）：胶囊挂在把手的 `.overlay` 上，overlay 会把
    /// **把手自己的尺寸（20 / 32pt）**当提案量给子视图，`Text` 于是被截断成 `$`（20pt 框）或
    /// `…`（32pt 框）——读数胶囊是拖动时唯一的尺寸反馈，截断后整条交互就"看不出跟手"了。
    /// `fixedSize()` 让文字按理想尺寸排版，胶囊再按 `.bottomTrailing` 贴住把手右上角、向右伸出。
    private func panelResizeReadoutLabel(_ size: CGSize) -> some View {
        Text("\(Int(size.width.rounded())) × \(Int(size.height.rounded()))")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .fixedSize()
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.6), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
    }

    /// 拖动：起点尺寸与**起点光标**在第一次 `onChanged` 捕获一次，之后每次都用「起点 + 累计位移」算新尺寸。
    ///
    /// 位移取 `panelResizeTranslation(from:to:)`（屏幕光标之间量出来的），**不用** `value.translation`
    /// ——后者的坐标空间会跟着面板 / 窗口的自身重排走，量到的位移不 1:1（见该函数的注释）。
    private var panelResizeDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                let mouse = NSEvent.mouseLocation
                let start: CGSize
                let startMouse: CGPoint
                if let capturedSize = panelResizeDragStartSize,
                   let capturedMouse = panelResizeDragStartMouseLocation {
                    start = capturedSize
                    startMouse = capturedMouse
                } else {
                    // 起点取**当前生效**的展开尺寸（已被 `openNotchSize` 夹过），拖动因此从屏幕上的
                    // 现状开始，不会因为存量默认值超界而先跳一下。
                    start = openNotchSize
                    startMouse = mouse
                    panelResizeDragStartSize = start
                    panelResizeDragStartMouseLocation = startMouse
                    isPanelResizing = true
                    panelResizeReadoutHideTask?.cancel()
                }
                applyPanelResize(
                    resolvedPanelResizeSize(
                        start: start,
                        translation: panelResizeTranslation(from: startMouse, to: mouse)
                    )
                )
            }
            .onEnded { _ in
                let mouse = NSEvent.mouseLocation
                defer {
                    panelResizeDragStartSize = nil
                    panelResizeDragStartMouseLocation = nil
                    isPanelResizing = false
                }
                guard let start = panelResizeDragStartSize else { return }
                // 结束再写一次：拖动过程中的写入与最后一帧之间可能被系统合并（`Defaults` 是
                // UserDefaults 的写穿缓存），再写一遍保证落盘的就是松手时的尺寸。
                let translation = panelResizeTranslation(
                    from: panelResizeDragStartMouseLocation ?? mouse,
                    to: mouse
                )
                applyPanelResize(resolvedPanelResizeSize(start: start, translation: translation))
                schedulePanelResizeReadoutFadeOut()
            }
    }

    /// 位移 → 最终尺寸：先按 `resizedPanelSize` 夹取，再取整并**用同一组边界复夹一次**。
    ///
    /// 取整后再夹的原因：上界可能是分数（`effectiveOpenNotchHeightUpperBound` = 屏高 × 0.9，
    /// 例如 850.5），取整会越过它不到 1pt——复夹一次后读数与写入的尺寸永远一致
    /// （读数不是"显示一个值、实际用另一个值"）。
    private func resolvedPanelResizeSize(start: CGSize, translation: CGSize) -> CGSize {
        let bounds = currentOpenNotchResizeBounds()
        let clamped = resizedPanelSize(
            start: start,
            translation: translation,
            minWidth: bounds.minWidth,
            maxWidth: bounds.maxWidth,
            minHeight: bounds.minHeight,
            maxHeight: bounds.maxHeight
        )
        return resizedPanelSize(
            start: CGSize(width: clamped.width.rounded(), height: clamped.height.rounded()),
            translation: .zero,
            minWidth: bounds.minWidth,
            maxWidth: bounds.maxWidth,
            minHeight: bounds.minHeight,
            maxHeight: bounds.maxHeight
        )
    }

    /// 写入 + 重排（**与设置页两个滑块同一条链路**）：写 `Defaults[.openNotchWidth]` /
    /// `[.openNotchHeight]`，再 post `notchHeightChanged`（那条通知的观测者在 `DynamicIslandApp`，
    /// 与滑块完全一致地走一遍"设置已改"的既有收尾：重新定位窗口、同步多屏）。
    /// 值没变就不发通知（拖动中途反复落在同一个夹取值上是常态）。
    ///
    /// 通知之外**还要**推一次窗口尺寸（`syncWindowSizeAfterPanelResize`）：高度只有那一条会实时生效，
    /// 原因见该函数的注释。
    private func applyPanelResize(_ size: CGSize) {
        panelResizeReadout = size
        let changed = abs(Defaults[.openNotchWidth] - size.width) > 0.01
            || abs(Defaults[.openNotchHeight] - size.height) > 0.01
        Defaults[.openNotchWidth] = size.width
        Defaults[.openNotchHeight] = size.height
        guard changed else { return }
        NotificationCenter.default.post(name: Notification.Name.notchHeightChanged, object: nil)
        syncWindowSizeAfterPanelResize()
    }

    /// 把「当前要求的展开尺寸」推给刘海窗口（拖动时的高度**只有**这条链路会实时生效）。
    ///
    /// 为什么需要它：**宽度**有实时链路（`DynamicIslandApp` 自己订阅 `Defaults.publisher(.openNotchWidth)`
    /// → 0.15s 防抖后重算窗口尺寸），**高度没有**——`notchHeightChanged` 的观察者只做
    /// `positionWindow`（用当前 frame 的尺寸重新定位，不重算尺寸），所以高度是「下次展开才生效」
    /// （设置页滑块同样如此：改完要重新展开一次才看得到）。拖动是连续交互，等不到下次展开。
    ///
    /// **为什么不调 `AppDelegate.ensureWindowSize`**：本机实测（2026-09-29，注入拖动 + `log show` 取证）
    /// 从视图层取 `AppDelegate.shared` 取不到代理（`@NSApplicationDelegateAdaptor` 包的那一层不落在
    /// `NSApplication.shared.delegate` 上），那条调用是**静默 no-op**（`DynamicIslandViewModel` 里那几处
    /// 同形状的调用是否同样失效未逐一验证——宽度另有上面那条链路兜着，日常看不出来）。因此这里按
    /// `AppDelegate.resizeWindow` 的同一口径直接改 frame：
    /// 目标尺寸 = `addShadowPadding(to: 展开内容尺寸)`（+18pt 阴影），再按屏补外扩
    /// （浮动药丸 +`dynamicIslandTopOffset` 与两侧 `dynamicIslandShadowInset`；刘海屏 +`notchTopScreenBleed`），
    /// 宽按屏宽夹取，窗口**水平居中、顶边贴屏顶** —— 与那条私有实现逐字同一条式子。
    ///
    /// 多屏时与 `resizeWindow` 一样逐屏处理（`showOnAllDisplays` 下每屏一个窗口）。
    /// 尺寸没变就整条跳过（`force: false` 的等价物），宽度那条链路照旧重复调用也不会打架。
    private func syncWindowSizeAfterPanelResize() {
        let padded = addShadowPadding(to: dynamicNotchSize, isMinimalistic: Defaults[.enableMinimalisticUI])
        for window in NSApp.windows where window is DynamicIslandWindow {
            guard let screen = window.screen ?? NSScreen.main else { continue }
            var size = padded
            if shouldUseDynamicIslandMode(for: screen.localizedName) {
                size.width += dynamicIslandShadowInset * 2
                size.height += dynamicIslandTopOffset
            } else {
                size.height += notchTopScreenBleed(for: screen.localizedName)
            }
            let screenFrame = screen.frame
            let width = min(size.width, screenFrame.width).rounded()
            let height = min(size.height, screenFrame.height + notchTopScreenBleed(for: screen.localizedName)).rounded()
            let target = NSRect(
                x: (screenFrame.midX - width / 2).rounded(),
                y: (screenFrame.maxY + notchTopScreenBleed(for: screen.localizedName) - height).rounded(),
                width: width,
                height: height
            )
            guard window.frame != target else { continue }
            window.setFrame(target, display: true)
        }
    }

    /// 松手后 0.8s 让读数淡出（新的拖动会取消上一次的淡出）。
    private func schedulePanelResizeReadoutFadeOut() {
        panelResizeReadoutHideTask?.cancel()
        panelResizeReadoutHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.25)) {
                panelResizeReadout = nil
            }
        }
    }

    private var configuredMainLayout: some View {
        mainLayoutBase
            .conditionalModifier(!useModernCloseAnimation) { view in
                let hoverAnimation = Animation.bouncy.speed(1.2)
                let notchStateAnimation = Animation.spring(response: 0.42, dampingFraction: 1.0, blendDuration: 0)
                return view
                    .animation(hoverAnimation, value: isHovering)
                    .animation(notchStateAnimation, value: vm.notchState)
                    .animation(.smooth, value: gestureProgress)
                    .transition(.blurReplace.animation(.interactiveSpring(dampingFraction: 1.2)))
            }
            .conditionalModifier(useModernCloseAnimation) { view in
                let hoverAnimation = Animation.bouncy.speed(1.2)
                let openAnimation = Animation.spring(response: 0.42, dampingFraction: 1.0, blendDuration: 0)
                let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
                let notchAnimation = vm.notchState == .open ? openAnimation : closeAnimation
                return view
                    .animation(hoverAnimation, value: isHovering)
                    .animation(notchAnimation, value: vm.notchState)
                    .animation(.smooth, value: gestureProgress)
            }
            .conditionalModifier(interactionsEnabled) { view in
                view
                    .contentShape(resolvedClipShape)
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        if handleClosedMusicWaveformTapIfNeeded() {
                            return
                        }
                        if vm.notchState == .closed && Defaults[.enableHaptics] {
                            triggerHapticIfAllowed()
                        }
                        openNotch()
                    }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                            .panGesture(direction: .left) { translation, phase in
                                handleSkipGesture(direction: .forward, translation: translation, phase: phase)
                            }
                            .panGesture(direction: .right) { translation, phase in
                                handleSkipGesture(direction: .backward, translation: translation, phase: phase)
                            }
                    }
            }
            .conditionalModifier((Defaults[.closeGestureEnabled] || Defaults[.reverseScrollGestures]) && Defaults[.enableGestures] && interactionsEnabled) { view in
                view
                    .panGesture(direction: .up) { translation, phase in
                        handleUpGesture(translation: translation, phase: phase)
                    }
            }
            // Shadow bottom padding and hide-until-hover offset applied AFTER
            // interaction modifiers so .contentShape / .onHover only covers
            // the actual notch content, not the shadow clearance below it.
            .padding(.bottom, notchBottomPadding)
            .offset(y: shouldHideUntilHover && !isHovering
                ? -(vm.closedNotchSize.height + pillTopOffset + currentShadowPadding + 10)
                : 0
            )
            .onAppear(perform: {
                if coordinator.firstLaunch {
                    // Single open during first launch; closeHello() handles the timed close.
                    runAfter(1) {
                        openNotch()
                    }
                }
            })
            .onChange(of: vm.notchState) { _, newState in
                // Update smart monitoring based on notch state
                if enableStatsFeature {
                    let currentViewString = coordinator.currentView == .stats ? "stats" : "other"
                    statsManager.updateMonitoringState(
                        notchIsOpen: newState == .open,
                        currentView: currentViewString
                    )
                }

                // Reset hover state when notch state changes
                if newState == .closed && isHovering {
                    withAnimation {
                        isHovering = false
                    }
                }
                if newState != .closed {
                    isHoveringClosedMusicWaveformControl = false
                }
                if newState == .closed {
                    removeStickyTerminalClickMonitor()
                } else {
                    // Install the outside-click monitor for terminal opens that don't
                    // change `currentView` (e.g. shortcut re-opening with the terminal
                    // tab already selected, where the cursor never enters the notch).
                    syncStickyTerminalOutsideClickMonitor()
                }

                // **自适应高度（p5-home-blocks / T6，docs/29 §做法 机制六）**：打开面板的**第一拍**
                // 读到的内容高还是上一帧的值——过渡持有者（`PanelAutoHeight.homeContentHeight`）
                // 由 `HomeBandedHomeView` 的 body 写，展开这一帧才第一次写；而打开那条路
                // （`DynamicIslandViewModel.open`）是**先定尺寸、再渲染**。
                // 因此下一拍按已经写好的持有者再推一次窗口尺寸（`dynamicNotchSize` → `openNotchSize`
                // → 持有者），这就是 §已知限制 2 说的「先按旧高度画一帧再贴合」——防抖那条 publisher
                // 只在**偏好变化**时触发，打开面板本身不是偏好变化，所以这一拍只能由这里补。
                // manual 档跳过（滑块 / 拖动各自那条链路已经把它推到当天值）；极简档的尺寸来自
                // `minimalisticOpenNotchSize`，与持有者无关，同样跳过。
                if newState == .open, !enableMinimalisticUI, PanelAutoHeight.isAuto(panelHeightMode) {
                    runAfter(0.06) {
                        guard vm.notchState == .open, !enableMinimalisticUI else { return }
                        syncWindowSizeAfterPanelResize()
                    }
                }
            }
            .onChange(of: vm.isBatteryPopoverActive) { _, newPopoverState in
                runAfter(0.1) {
                    if !newPopoverState && !isHovering && vm.notchState == .open && !shouldPreventAutoClose() {
                        vm.close()
                    }
                }
            }
            .onChange(of: vm.isStatsPopoverActive) { _, newPopoverState in
                runAfter(0.1) {
                    if !newPopoverState && !isHovering && vm.notchState == .open && !shouldPreventAutoClose() {
                        vm.close()
                    }
                }
            }
            .onChange(of: vm.shouldRecheckHover) { _, _ in
                // Recheck hover state when popovers are closed
                runAfter(0.1) {
                    if vm.notchState == .open && !shouldPreventAutoClose() && !isHovering {
                        vm.close()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                runAfter(0.1) {
                    if vm.notchState == .open && !isHovering && !shouldPreventAutoClose() {
                        vm.close()
                    }
                }
            }
            .onChange(of: coordinator.sneakPeek.show) { _, sneakPeekShowing in
                // When sneak peek finishes, check if user is still hovering and open notch if needed
                if !sneakPeekShowing {
                    runAfter(0.2) {
                        if isHovering && vm.notchState == .closed && !coordinator.isHoverOpenSuppressed {
                            openNotch()
                        }
                    }
                }
            }
            .onChange(of: coordinator.currentView) { _, newValue in
                if enableStatsFeature {
                    let currentViewString = newValue == .stats ? "stats" : "other"
                    statsManager.updateMonitoringState(
                        notchIsOpen: vm.notchState == .open,
                        currentView: currentViewString
                    )
                }
                syncStickyTerminalOutsideClickMonitor()
            }
            .sensoryFeedback(.alignment, trigger: haptics)
            .contextMenu {
                Button("Settings") {
                    SettingsWindowController.shared.showWindow()
                }
//                Button("Edit") { // Doesnt work....
//                    let dn = DynamicNotch(content: EditPanelView())
//                    dn.toggle()
//                }
//                #if DEBUG
//                .disabled(false)
//                #else
//                .disabled(true)
//                #endif
//                .keyboardShortcut("E", modifiers: .command)
            }
    }

    private var rootBodyView: some View {
        ZStack(alignment: .top) {
            configuredMainLayout
        }
        .frame(
            maxWidth: (dynamicNotchSize.width + (vm.notchState == .open ? 24 : 0) + (isDynamicIslandMode ? dynamicIslandShadowInset * 2 : 0)).rounded(),
            maxHeight: (dynamicNotchSize.height + (vm.notchState == .open ? 12 : 0) + (isIslandMode ? 0 : notchTopScreenBleedAmount) + (isDynamicIslandMode ? dynamicIslandTopOffset + dynamicIslandShadowInset * 2 : currentShadowPadding)).rounded(),
            alignment: .top
        )
        .animation(nil, value: vm.notchState)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environmentObject(privacyManager)
        .background(dragDetector)
        .environmentObject(vm)
        .environmentObject(webcamManager)
    }

    private func installRootLifecycleHandlers<Content: View>(on view: Content) -> some View {
        installSecondaryRootLifecycleHandlers(
            on: installPrimaryRootLifecycleHandlers(on: view)
        )
    }

    private func installPrimaryRootLifecycleHandlers<Content: View>(on view: Content) -> some View {
        view
            .onAppear {
                isMusicControlWindowSuppressed = vm.notchState != .closed
                    || lockScreenManager.isLocked
                    || isMusicHUDDeferredAfterUnlock
                if musicManager.isPlaying || !musicManager.isPlayerIdle {
                    clearMusicControlVisibilityDeadline()
                }
                if let deadline = musicControlVisibilityDeadline, Date() > deadline {
                    clearMusicControlVisibilityDeadline()
                }
                enqueueMusicControlWindowSync(forceRefresh: true)
                startHiddenEdgeHoverPolling()
                // Deterministic teardown for borderless panels (`.onDisappear` is
                // unreliable); the window-cleanup path calls this before closing.
                vm.onViewTeardown = { performViewTeardown() }
            }
            .onChange(of: terminalStickyMode) { _, _ in
                syncStickyTerminalOutsideClickMonitor()
            }
            .onChange(of: vm.notchState) { _, state in
                if state == .open {
                    suppressMusicControlWindowUpdates()
                    cancelMusicControlWindowSync()
                    hideMusicControlWindow()
                } else {
                    releaseMusicControlWindowUpdates(after: musicControlResumeDelay)
                    enqueueMusicControlWindowSync(forceRefresh: true, delay: 0.05)
                }
            }
            .onChange(of: musicControlWindowEnabled) { _, enabled in
                if enabled {
                    if musicManager.isPlaying || !musicManager.isPlayerIdle {
                        clearMusicControlVisibilityDeadline()
                    }
                    enqueueMusicControlWindowSync(forceRefresh: true)
                } else {
                    cancelMusicControlWindowSync()
                    hideMusicControlWindow()
                    clearMusicControlVisibilityDeadline()
                    hasPendingMusicControlSync = false
                    pendingMusicControlForceRefresh = false
                }
            }
            .onChange(of: coordinator.musicLiveActivityEnabled) { _, enabled in
                if enabled {
                    enqueueMusicControlWindowSync(forceRefresh: true)
                } else {
                    cancelMusicControlWindowSync()
                    hideMusicControlWindow()
                    clearMusicControlVisibilityDeadline()
                    hasPendingMusicControlSync = false
                    pendingMusicControlForceRefresh = false
                }
            }
            .onChange(of: vm.hideOnClosed) { _, hidden in
                if hidden {
                    cancelMusicControlWindowSync()
                    hideMusicControlWindow()
                } else {
                    enqueueMusicControlWindowSync(forceRefresh: true, delay: 0.05)
                }
            }
            .onChange(of: lockScreenManager.isLocked) { _, locked in
                if locked {
                    suppressMusicControlWindowUpdates()
                    cancelMusicControlWindowSync()
                    hideMusicControlWindow()
                } else {
                    releaseMusicControlWindowUpdates(after: musicControlResumeDelay)
                    enqueueMusicControlWindowSync(forceRefresh: true, delay: 0.05)
                }
            }
            .onChange(of: lockScreenManager.shouldDelayPostUnlockMusicHUD) { _, deferred in
                if deferred {
                    suppressMusicControlWindowUpdates()
                    cancelMusicControlWindowSync()
                    hideMusicControlWindow()
                } else {
                    releaseMusicControlWindowUpdates(after: 0)
                    enqueueMusicControlWindowSync(forceRefresh: true, delay: 0.05)
                }
            }
    }

    private func installSecondaryRootLifecycleHandlers<Content: View>(on view: Content) -> some View {
        view
            .onChange(of: showStandardMediaControls) { _, _ in
                handleStandardMediaControlsAvailabilityChange()
            }
            .onChange(of: enableMinimalisticUI) { _, _ in
                handleStandardMediaControlsAvailabilityChange()
            }
            .onChange(of: gestureProgress) { _, _ in
                if shouldShowMusicControlWindow() {
                    enqueueMusicControlWindowSync(forceRefresh: true, delay: 0.05)
                }
            }
            .onChange(of: isHovering) { _, hovering in
                if shouldShowMusicControlWindow() {
                    enqueueMusicControlWindowSync(forceRefresh: true, delay: hovering ? 0.05 : 0.12)
                }
            }
            .onChange(of: musicManager.isPlaying) { _, isPlaying in
                handleMusicControlPlaybackChange(isPlaying: isPlaying)
            }
            .onChange(of: musicManager.isPlayerIdle) { _, isIdle in
                handleMusicControlIdleChange(isIdle: isIdle)
            }
            .onChange(of: vm.closedNotchSize) { _, _ in
                if shouldShowMusicControlWindow() {
                    enqueueMusicControlWindowSync(forceRefresh: true)
                }
            }
            .onChange(of: vm.effectiveClosedNotchHeight) { _, _ in
                if shouldShowMusicControlWindow() {
                    enqueueMusicControlWindowSync(forceRefresh: true)
                }
            }
            .onDisappear {
                performViewTeardown()
            }
    }

    @ViewBuilder
      func NotchLayout() -> some View {
          VStack(alignment: .leading) {
              VStack(alignment: .leading) {
                  if coordinator.firstLaunch {
                      Spacer()
                      HelloAnimation().frame(width: 200, height: 80).onAppear(perform: {
                          vm.closeHello()
                      })
                      .padding(.top, 40)
                      Spacer()
                  } else {
                        let hasMusicMetadata = !musicManager.songTitle.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                            || !musicManager.artistName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                      let hasActiveMusicSnapshot: Bool = {
                          if musicManager.isPlaying { return true }
                          return !musicManager.isPlayerIdle && hasMusicMetadata
                      }()
                      let musicPairingEligible = closedMusicPairingEligible(hasActiveMusicSnapshot: hasActiveMusicSnapshot)
                      let musicSecondary = resolveMusicSecondaryLiveActivity(isMusicPairingEligible: musicPairingEligible)
                      let extensionSecondaryPayloadID = extensionSecondaryPayloadID(for: musicSecondary)
                      let extensionStandalonePayload = resolvedExtensionStandalonePayload(excluding: extensionSecondaryPayloadID)
                      let activeSneakPeekStyle = resolvedSneakPeekStyle()
                      let expansionMatchesSecondary: Bool = {
                          guard let musicSecondary else { return false }
                          switch musicSecondary {
                          case .timer:
                              return currentScreenExpansionType == .timer
                          case .reminder:
                              return currentScreenExpansionType == .reminder
                          case .recording:
                              return currentScreenExpansionType == .recording
                          case .focus:
                              return currentScreenExpansionType == .doNotDisturb
                          case .capsLock:
                              return false
                          case .extensionPayload:
                              return false
                          case .shelf:
                              return false
                          }
                      }()
                      let canShowMusicDuringExpansion = !isCurrentScreenExpansionVisible
                          || currentScreenExpansionType == .music
                          || expansionMatchesSecondary
                      let isAirPodsListeningModeSneak = coordinator.sneakPeek.type == .bluetoothAudio
                          && coordinator.sneakPeek.value < 0
                          && AirPodsListeningMode.fromHUDSymbol(coordinator.sneakPeek.icon) != nil

                      if currentScreenExpansionType == .battery
                            && isBatteryHUDVisibleOnCurrentScreen
                            && vm.notchState == .closed
                            && Defaults[.showPowerStatusNotifications]
                            && batteryModel.activeTemporaryHUDKind != nil {
                        BatteryTemporaryActivityView(
                            kind: batteryModel.activeTemporaryHUDKind ?? .charging,
                            batteryLevel: displayedBatteryHUDLevel,
                            isLowPowerMode: displayedBatteryHUDUsesLowPowerMode,
                            closedNotchWidth: vm.closedNotchSize.width + (isHovering ? 8 : 0),
                            baseHeight: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0),
                            isDynamicIslandMode: isDynamicIslandMode,
                            topCornerRadius: activeCornerRadiusInsets.closed.top,
                            styleOverride: batteryModel.activeTemporaryHUDKind.map { resolvedBatteryNotificationStyle(for: $0) }
                        )
                        .id(batteryModel.activeTemporaryHUDToken)
                      } else if isSneakPeekVisibleOnCurrentScreen && (Defaults[.inlineHUD] || isAirPodsListeningModeSneak) && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && (coordinator.sneakPeek.type != .timer) && (coordinator.sneakPeek.type != .reminder) && !coordinator.sneakPeek.type.isExtensionPayload && ((coordinator.sneakPeek.type != .volume && coordinator.sneakPeek.type != .brightness && coordinator.sneakPeek.type != .backlight) || vm.notchState == .closed) {
                          InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(
                                  coordinator.sneakPeek.type == .capsLock
                                      ? AnyTransition.move(edge: .trailing).combined(with: .opacity)
                                      : AnyTransition.opacity
                              )
                      } else if vm.notchState == .closed && capsLockManager.isCapsLockActive && Defaults[.enableCapsLockIndicator] && !vm.hideOnClosed && !lockScreenManager.isLocked {
                          InlineHUD(type: .constant(.capsLock), value: .constant(1.0), icon: .constant(""), hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
                      } else if canShowMusicDuringExpansion && musicPairingEligible {
                          MusicLiveActivity(secondary: musicSecondary)
                              .id("closed-music-live-activity")
                              .transition(closedLiveActivitySwapTransition)
                      } else if (!isCurrentScreenExpansionVisible || currentScreenExpansionType == .timer) && vm.notchState == .closed && timerManager.isTimerActive && coordinator.timerLiveActivityEnabled && !vm.hideOnClosed {
                          TimerLiveActivity()
                      } else if (!isCurrentScreenExpansionVisible || currentScreenExpansionType == .reminder) && vm.notchState == .closed && reminderManager.isActive && enableReminderLiveActivity && !vm.hideOnClosed {
                          ReminderLiveActivity()
                      } else if (!isCurrentScreenExpansionVisible || currentScreenExpansionType == .recording) && vm.notchState == .closed && (recordingManager.isRecording || !recordingManager.isRecorderIdle) && Defaults[.enableScreenRecordingDetection] && !vm.hideOnClosed && !musicPairingEligible {
                          RecordingLiveActivity()
                      } else if (!isCurrentScreenExpansionVisible || currentScreenExpansionType == .download) && vm.notchState == .closed && downloadManager.isDownloading && Defaults[.enableDownloadListener] && !vm.hideOnClosed {
                          DownloadLiveActivity()
                              .transition(.blurReplace.animation(.interactiveSpring(dampingFraction: 1.2)))
                      } else if !isCurrentScreenExpansionVisible && vm.notchState == .closed && localSendLiveActivityActive && !vm.hideOnClosed {
                          LocalSendLiveActivity()
                              .transition(.blurReplace.animation(.interactiveSpring(dampingFraction: 1.2)))
                      } else if (!isCurrentScreenExpansionVisible || currentScreenExpansionType == .doNotDisturb) && vm.notchState == .closed && Defaults[.enableDoNotDisturbDetection] && Defaults[.showDoNotDisturbIndicator] && (doNotDisturbManager.isDoNotDisturbActive || doNotDisturbManager.isFocusToastDismissing) && !vm.hideOnClosed && !lockScreenManager.isLocked {
                          DoNotDisturbLiveActivity()
                    } else if (!isCurrentScreenExpansionVisible || currentScreenExpansionType == .lockScreen) && vm.notchState == .closed && (lockScreenManager.isLocked || !lockScreenManager.isLockIdle) && Defaults[.enableLockScreenLiveActivity] && !vm.hideOnClosed {
                        LockScreenLiveActivity()
                            .id("lock-screen-live-activity")
                            .transition(closedLiveActivitySwapTransition)
                    } else if (!isCurrentScreenExpansionVisible || currentScreenExpansionType == .privacy) && vm.notchState == .closed && privacyManager.hasAnyIndicator && (Defaults[.enableCameraDetection] || Defaults[.enableMicrophoneDetection]) && !vm.hideOnClosed {
                        PrivacyLiveActivity()
                      } else if let extensionPayload = extensionStandalonePayload {
                          let layout = extensionStandaloneLayout(
                              for: extensionPayload,
                              notchHeight: vm.effectiveClosedNotchHeight,
                              isHovering: isHovering
                          )
                          ExtensionLiveActivityStandaloneView(
                              payload: extensionPayload,
                              layout: layout,
                              isHovering: isHovering
                          )
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && !shelfState.isEmpty && !vm.hideOnClosed && !lockScreenManager.isLocked && !enableMinimalisticUI {
                          ShelfInlineLiveActivity()
                              .transition(.opacity.animation(.smooth(duration: 0.25)))
                      } else if vm.notchState == .closed && !vm.hideOnClosed && !isCurrentScreenExpansionVisible && !enableMinimalisticUI && !ModuleRegistry.shared.compactEntries.isEmpty {
                          // 模块的折叠态中央槽位：**低优先**——只在上面所有 live activity 都没占用
                          // 关闭态时显示（与它们共用一条优先级链，故有活动时自动让位）。
                          ModuleCompactSlotView()
                              .transition(.opacity.animation(.smooth(duration: 0.25)))
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                      } else if !isCurrentScreenExpansionVisible && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          DynamicIslandFaceAnimation().animation(.interactiveSpring, value: musicManager.isPlayerIdle)
                      } else if vm.notchState == .open {
                          DynamicIslandHeader()
                              .frame(height: (Defaults[.enableMinimalisticUI] && isDynamicIslandMode) ? nil : max(24, vm.effectiveClosedNotchHeight))
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                       }
                      
                      if isSneakPeekVisibleOnCurrentScreen {
                          if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && (coordinator.sneakPeek.type != .timer) && (coordinator.sneakPeek.type != .reminder) && (coordinator.sneakPeek.type != .capsLock) && !coordinator.sneakPeek.type.isExtensionPayload && !Defaults[.inlineHUD] && !isAirPodsListeningModeSneak && ((coordinator.sneakPeek.type != .volume && coordinator.sneakPeek.type != .brightness && coordinator.sneakPeek.type != .backlight) || vm.notchState == .closed) {
                              SystemEventIndicatorModifier(eventType: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, sendEventBack: { _ in
                                  //
                              })
                              .padding(.bottom, 10)
                              .padding(.leading, 4)
                              .padding(.trailing, 8)
                          }
                          // Old sneak peek music
                          else if coordinator.sneakPeek.type == .music {
                              if vm.notchState == .closed && !vm.hideOnClosed && activeSneakPeekStyle == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "music.note")
                                      GeometryReader { geo in
                                          MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName), textColor: .gray, minDuration: 1, frameWidth: geo.size.width)
                                      }
                                  }
                                  .foregroundStyle(.gray)
                                  .padding(.bottom, 10)
                              }
                          }
                          // Timer sneak peek
                          else if coordinator.sneakPeek.type == .timer {
                              if !vm.hideOnClosed && activeSneakPeekStyle == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "timer")
                                      GeometryReader { geo in
                                          MarqueeText(.constant(timerManager.timerName + " - " + timerManager.formattedRemainingTime()), textColor: timerManager.timerColor, minDuration: 1, frameWidth: geo.size.width)
                                      }
                                  }
                                  .foregroundStyle(timerManager.timerColor)
                                  .padding(.bottom, 10)
                              }
                          }
                          else if coordinator.sneakPeek.type == .reminder {
                              if !vm.hideOnClosed && activeSneakPeekStyle == .standard, let reminder = reminderManager.activeReminder {
                                  GeometryReader { geo in
                                      let chipColor = Color(nsColor: reminder.event.calendar.color).ensureMinimumBrightness(factor: 0.7)
                                      HStack(spacing: 6) {
                                          RoundedRectangle(cornerRadius: 2)
                                              .fill(chipColor)
                                              .frame(width: 8, height: 12)
                                          MarqueeText(
                                              .constant(reminderSneakPeekText(for: reminder, now: reminderManager.currentDate)),
                                              textColor: reminderColor(for: reminder, now: reminderManager.currentDate),
                                              minDuration: 1,
                                              frameWidth: max(0, geo.size.width - 14)
                                          )
                                      }
                                  }
                                  .padding(.bottom, 10)
                              }
                          }
                          // Extension live activity sneak peek
                          else if case let .extensionLiveActivity(bundleID, activityID) = coordinator.sneakPeek.type {
                              if !vm.hideOnClosed && activeSneakPeekStyle == .standard {
                                  let payload = extensionLiveActivityManager.payload(bundleIdentifier: bundleID, activityID: activityID)
                                  let descriptor = payload?.descriptor
                                  let accent = (descriptor?.accentColor.swiftUIColor ?? coordinator.sneakPeek.accentColor ?? .gray)
                                      .ensureMinimumBrightness(factor: 0.7)
                                  GeometryReader { geo in
                                      HStack(spacing: 6) {
                                          RoundedRectangle(cornerRadius: 2)
                                              .fill(accent)
                                              .frame(width: 8, height: 12)
                                          MarqueeText(
                                              .constant(
                                                  extensionSneakPeekText(
                                                      preferredTitle: coordinator.sneakPeek.title,
                                                      preferredSubtitle: coordinator.sneakPeek.subtitle,
                                                      descriptor: descriptor
                                                  )
                                              ),
                                              textColor: accent,
                                              minDuration: 1,
                                              frameWidth: max(0, geo.size.width - 14)
                                          )
                                      }
                                  }
                                  .padding(.bottom, 10)
                              }
                          }
                      }
                  }
              }
              .conditionalModifier(shouldFixSizeForSneakPeek()) { view in
                  view
                      .fixedSize()
              }
              .zIndex(2)
              
              ZStack {
                  if vm.notchState == .open {
                      Group {
                          switch coordinator.currentView {
                              case .home:
                                  NotchHomeView(albumArtNamespace: albumArtNamespace)
                              case .shelf:
                                  NotchShelfView()
                              case .timer:
                                  // **已无生产路径**：计时器接管成模块后，新路径经模块 tab
                                  // （`coordinator.selectModule(TimerModule.moduleID)`，docs/20 §做法 机制六）；
                                  // 这个枚举成员与分支保留（删除会牵动 `NotchViews` 的哈希与 `tabOrder`
                                  // 的动画方向语义），今天只有老路径 / 测试会落到这里。
                                  NotchTimerView()
                              case .stats:
                                  NotchStatsView()
                              case .llmUsage:
                                  NotchLLMUsageView()
                              case .colorPicker:
                                  NotchColorPickerView()
                            case .notes:
                                NotchNotesView()
                            case .clipboard:
                                NotchClipboardView()
                            case .terminal:
                                NotchTerminalView()
                            case .extensionExperience:
                                if let payload = currentExtensionTabPayload() {
                                    ExtensionNotchExperienceTabView(payload: payload)
                                } else {
                                    NotchHomeView(albumArtNamespace: albumArtNamespace)
                                }
                            case .module:
                                // 模块内核（接缝 S5）：当前选中的模块由 coordinator 持有，
                                // 未选中（selectedModuleID == nil）时 ModuleHostView 渲染 EmptyView。
                                ModuleHostView(moduleID: coordinator.selectedModuleID)
                          }
                      }
                      .id(expandedContentIdentity)
                      .transition(tabSwitchTransition)
                  }
              }
              .zIndex(1)
              .allowsHitTesting(vm.notchState == .open)
              .blur(radius: abs(gestureProgress) > 0.3 ? min(abs(gestureProgress), 8) : 0)
              .opacity(abs(gestureProgress) > 0.3 ? min(abs(gestureProgress * 2), 0.8) : 1)
              .animation(.smooth(duration: 0.3), value: coordinator.currentView)
          }
      }

    private func reminderColor(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> Color {
        if isReminderCritical(reminder, now: now) {
            return .red
        }
        return Color(nsColor: reminder.event.calendar.color).ensureMinimumBrightness(factor: 0.7)
    }

    private func reminderSneakPeekText(for entry: ReminderLiveActivityManager.ReminderEntry, now: Date) -> String {
        let title = entry.event.title.isEmpty ? "Upcoming Reminder" : entry.event.title
        let remaining = max(entry.event.start.timeIntervalSince(now), 0)
        let window = TimeInterval(Defaults[.reminderSneakPeekDuration])

        if window > 0 && remaining <= window {
            return "\(title) • \(String(format: String(localized: "now")))"
        }

        let minutes = Int(ceil(remaining / 60))
        let timeString = reminderTimeFormatter.string(from: entry.event.start)

        if minutes <= 0 {
            return "\(title) • \(String(format: String(localized: "now"))) • \(timeString)"
        } else if minutes == 1 {
            return "\(title) • \(String(format: String(localized: "in %@"), String(localized: "1 min"))) • \(timeString)"
        } else {
            return "\(title) • \(String(format: String(localized: "in %lld"), (minutes))) \(String(format: String(localized: "min plural"))) • \(timeString)"
        }
    }

    private func extensionSneakPeekText(preferredTitle: String, preferredSubtitle: String?, descriptor: AtollLiveActivityDescriptor?) -> String {
        let trimmedPreferredTitle = preferredTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptorTitle = descriptor?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Extension"
        let title = trimmedPreferredTitle.isEmpty ? descriptorTitle : trimmedPreferredTitle

        let trimmedPreferredSubtitle = preferredSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let descriptorSubtitle = descriptor?.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let subtitle = !trimmedPreferredSubtitle.isEmpty ? trimmedPreferredSubtitle : descriptorSubtitle

        guard !subtitle.isEmpty else { return title }
        return "\(title) • \(subtitle)"
    }

    private let reminderTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    @ViewBuilder
    func DynamicIslandFaceAnimation() -> some View {
        let sideSize = max(0, vm.effectiveClosedNotchHeight - 12)
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(width: sideSize, height: sideSize)
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                IdleAnimationView()
                    .frame(width: sideSize, height: sideSize)
            }
        }.frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0), alignment: .center)
    }

    @ViewBuilder
    private func MusicLiveActivity(secondary preResolvedSecondary: MusicSecondaryLiveActivity? = nil) -> some View {
        let secondary = preResolvedSecondary ?? resolveMusicSecondaryLiveActivity()
        let closedHeight = vm.effectiveClosedNotchHeight
        let outerHeight = closedHeight + (isHovering ? 8 : 0)
        let notchContentHeight = isHovering ? max(0, closedHeight) : max(0, closedHeight - 12)
        let wingBaseWidth = max(0, notchContentHeight + gestureProgress / 2)
        let artworkHeight = max(0, closedHeight - 12)
        let artworkSize = min(artworkHeight, wingBaseWidth)
        let rawCenterBaseWidth = vm.closedNotchSize.width + (isHovering ? 8 : 0)
        let centerBaseWidth = max(rawCenterBaseWidth, 96)
        let inlineSneakPeekActive = (
            coordinator.expandingView.show &&
            (coordinator.expandingView.type == .music || coordinator.expandingView.type == .timer) &&
            Defaults[.enableSneakPeek] &&
            Defaults[.sneakPeekStyles] == .inline
        )
        let rightWingWidth = resolvedRightWingWidth(
            for: secondary,
            baseWidth: wingBaseWidth,
            centerBaseWidth: centerBaseWidth,
            notchHeight: notchContentHeight
        )
        let effectiveCenterWidth = inlineSneakPeekActive ? 380 : centerBaseWidth
        let notchWidth = wingBaseWidth + effectiveCenterWidth + rightWingWidth
        let badgeBaseSize = max(13, artworkSize * 0.36)
        let badgeDisplaySize = badgeDisplaySize(for: secondary, baseSize: badgeBaseSize)
        let badgeOffset = badgeOverlayOffset(for: secondary, badgeSize: badgeDisplaySize)

        HStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                // Keep the matched-geometry source bounded to the closed
                // artwork square while the surrounding hover flap expands.
                ZStack(alignment: .bottomTrailing) {
                    Color.clear
                        .frame(width: artworkSize, height: artworkSize)
                        .background(
                            Image(nsImage: musicManager.albumArt)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: musicManager.albumArt.size.width/musicManager.albumArt.size.height > 1.0 ? MusicPlayerImageSizes.cornerRadiusInset.closed/3.0 : MusicPlayerImageSizes.cornerRadiusInset.closed))
                        )
                        .clipped()
                        .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                        .albumArtFlip(angle: musicManager.flipAngle)
                    albumArtBadge(for: secondary, badgeSize: badgeDisplaySize)
                        .offset(x: badgeOffset.width, y: badgeOffset.height)
                        .id(secondary?.id ?? "music-badge")
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: artworkSize, height: artworkSize, alignment: .bottomTrailing)
            }
            .frame(width: wingBaseWidth, height: notchContentHeight, alignment: .center)

            Rectangle()
                .fill(.black)
                .frame(width: effectiveCenterWidth, height: notchContentHeight)
                .overlay(
                    HStack(alignment: .top) {
                        if(coordinator.expandingView.show && coordinator.expandingView.type == .music) {
                            MusicTitleMarqueeView(
                                text: musicManager.songTitle,
                                isExplicit: musicManager.isCurrentTrackExplicit,
                                textColor: Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: max(0, (effectiveCenterWidth - vm.closedNotchSize.width) / 2 - 12),
                                badgeHeight: 13
                            )
                            .padding(.leading, 8)
                            .opacity((coordinator.expandingView.show && Defaults[.enableSneakPeek] && Defaults[.sneakPeekStyles] == .inline) ? 1 : 0)
                            Spacer(minLength: vm.closedNotchSize.width)
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : Color.gray)
                                .padding(.trailing, 8)
                                .opacity((coordinator.expandingView.show && coordinator.expandingView.type == .music && Defaults[.enableSneakPeek] && Defaults[.sneakPeekStyles] == .inline) ? 1 : 0)
                        } else if(coordinator.expandingView.show && coordinator.expandingView.type == .timer) {
                            MarqueeText(
                                .constant(timerManager.timerName),
                                textColor: timerManager.timerColor,
                                minDuration: 0.4,
                                frameWidth: max(0, (effectiveCenterWidth - vm.closedNotchSize.width) / 2 - 12)
                            )
                            .padding(.leading, 8)
                            .opacity((coordinator.expandingView.show && Defaults[.enableSneakPeek] && Defaults[.sneakPeekStyles] == .inline) ? 1 : 0)
                            Spacer(minLength: vm.closedNotchSize.width)
                            Text(timerManager.formattedRemainingTime())
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(timerManager.timerColor)
                                .padding(.trailing, 8)
                                .opacity((coordinator.expandingView.show && coordinator.expandingView.type == .timer && Defaults[.enableSneakPeek] && Defaults[.sneakPeekStyles] == .inline) ? 1 : 0)
                        } else if Defaults[.showSongMetadataInClosedNotch] && isNonNotchScreen && !musicManager.songTitle.isEmpty {
                            MarqueeText(
                                .constant("\(musicManager.songTitle) • \(musicManager.artistName)"),
                                textColor: Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 3,
                                frameWidth: max(0, effectiveCenterWidth - 16)
                            )
                            .padding(.horizontal, 8)
                        }
                    }
                    .clipped()
                )

            musicRightWing(for: secondary, notchHeight: notchContentHeight, trailingWidth: rightWingWidth)
                .frame(width: rightWingWidth, height: notchContentHeight, alignment: .center)
                .contentShape(Rectangle())
                .onHover { hovering in
                    guard shouldShowClosedMusicWaveformPlayPauseOverlay(for: secondary) else {
                        if isHoveringClosedMusicWaveformControl {
                            isHoveringClosedMusicWaveformControl = false
                        }
                        return
                    }
                    withAnimation(.smooth(duration: 0.16)) {
                        isHoveringClosedMusicWaveformControl = hovering
                    }
                }
                .id(secondary?.id ?? "music-spectrum")
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: notchWidth, height: notchContentHeight)
        .frame(height: outerHeight, alignment: .center)
        .animation(.smooth(duration: 0.25), value: secondary?.id)
    }

    private func resolveMusicSecondaryLiveActivity(isMusicPairingEligible: Bool = true) -> MusicSecondaryLiveActivity? {
        if coordinator.timerLiveActivityEnabled && timerManager.isTimerActive {
            return .timer
        }

        if enableReminderLiveActivity, reminderManager.isActive, let reminder = reminderManager.activeReminder {
            return .reminder(reminder)
        }

        if enableScreenRecordingDetection && (recordingManager.isRecording || !recordingManager.isRecorderIdle) {
            return .recording
        }

        if enableDoNotDisturbDetection && showDoNotDisturbIndicator && doNotDisturbManager.isDoNotDisturbActive {
            let mode = FocusModeType.resolve(identifier: doNotDisturbManager.currentFocusModeIdentifier, name: doNotDisturbManager.currentFocusModeName)
            return .focus(mode)
        }

        if enableCapsLockIndicator && capsLockManager.isCapsLockActive {
            return .capsLock(showLabel: showCapsLockLabel)
        }

        if isMusicPairingEligible, let extensionPayload = resolvedExtensionMusicPayload() {
            return .extensionPayload(extensionPayload)
        }

        // Shelf: show file count as lowest-priority secondary
        if !shelfState.isEmpty && !lockScreenManager.isLocked && !enableMinimalisticUI {
            return .shelf(count: shelfState.items.count)
        }

        return nil
    }

    private func resolvedRightWingWidth(for secondary: MusicSecondaryLiveActivity?, baseWidth: CGFloat, centerBaseWidth: CGFloat, notchHeight: CGFloat) -> CGFloat {
        guard let secondary else { return baseWidth }

        switch secondary {
        case .timer:
            return timerRightWingWidth(baseWidth: baseWidth, centerBaseWidth: centerBaseWidth)
        case .reminder(let entry):
            return reminderRightWingWidth(for: entry, baseWidth: baseWidth, notchHeight: notchHeight, now: reminderManager.currentDate)
        case .capsLock(let showLabel):
            return showLabel ? scaledWingWidth(baseWidth: baseWidth, centerBaseWidth: centerBaseWidth, factor: 0.4, extra: 12) : baseWidth
        case .focus:
            return focusRightWingWidth(baseWidth: baseWidth)
        case .recording:
            return recordingRightWingWidth(baseWidth: baseWidth)
        case .extensionPayload(let payload):
            let maxWidth = baseWidth + centerBaseWidth * 0.6
            return ExtensionLayoutMetrics.trailingWidth(for: payload, baseWidth: baseWidth, maxWidth: maxWidth)
        case .shelf:
            return baseWidth
        }
    }

    private func timerRightWingWidth(baseWidth: CGFloat, centerBaseWidth: CGFloat) -> CGFloat {
        if timerShowsCountdown {
            return timerCountdownWingWidth(baseWidth: baseWidth)
        }

        let showsProgress = timerShowsProgress
        let usesRingProgress = timerProgressStyle == .ring

        switch (showsProgress, usesRingProgress) {
        case (true, true):
            return scaledWingWidth(baseWidth: baseWidth, centerBaseWidth: centerBaseWidth, factor: 0.46, extra: 18)
        case (true, false):
            return scaledWingWidth(baseWidth: baseWidth, centerBaseWidth: centerBaseWidth, factor: 0.52, extra: 24)
        case (false, _):
            return scaledWingWidth(baseWidth: baseWidth, centerBaseWidth: centerBaseWidth, factor: 0.38, extra: 12)
        }
    }

    private func timerCountdownWingWidth(baseWidth: CGFloat) -> CGFloat {
        let padding: CGFloat = 18
        let ringWidth: CGFloat = (timerShowsProgress && timerProgressStyle == .ring) ? 30 : 0
        let spacing: CGFloat = (ringWidth > 0) ? 8 : 0
        let countdownText = timerManager.formattedRemainingTime()
        let countdownWidth = TimerSupplementMetrics.countdownFrameWidth(for: countdownText)
        return max(baseWidth, padding + ringWidth + spacing + countdownWidth)
    }

    private func reminderRightWingWidth(for entry: ReminderLiveActivityManager.ReminderEntry, baseWidth: CGFloat, notchHeight: CGFloat, now: Date) -> CGFloat {
        let padding: CGFloat = 16
        switch reminderPresentationStyle {
        case .ringCountdown:
            let diameter = ReminderSupplementMetrics.ringDiameter(for: notchHeight)
            return max(baseWidth, padding + diameter)
        case .digital:
            let countdownText = ReminderSupplementMetrics.digitalCountdownText(for: entry, now: now)
            let width = ReminderSupplementMetrics.digitalFrameWidth(for: countdownText)
            return max(baseWidth, padding + width)
        case .minutes:
            let minutesText = ReminderSupplementMetrics.minutesCountdownText(for: entry, now: now)
            let width = ReminderSupplementMetrics.minutesFrameWidth(for: minutesText)
            return max(baseWidth, padding + width)
        }
    }

    private func focusRightWingWidth(baseWidth: CGFloat) -> CGFloat {
        // Focus pairings now mirror the default music spectrum width to keep the notch compact.
        return baseWidth
    }

    private func recordingRightWingWidth(baseWidth: CGFloat) -> CGFloat {
        // Keep recording pairings compact by reducing the width relative to the notch height.
        let absoluteMin: CGFloat = 38
        let preferredWidth = max(baseWidth * 0.6, 0)
        let maxWidth = min(baseWidth - 6, 52)
        let clampedPreferred = min(preferredWidth, maxWidth)
        return min(baseWidth, max(absoluteMin, clampedPreferred))
    }

    private func scaledWingWidth(baseWidth: CGFloat, centerBaseWidth: CGFloat, factor: CGFloat, extra: CGFloat) -> CGFloat {
        max(baseWidth, max(centerBaseWidth * factor, baseWidth + extra))
    }

    @ViewBuilder
    private func albumArtBadge(for secondary: MusicSecondaryLiveActivity?, badgeSize: CGFloat) -> some View {
        if let secondary, badgeSize > 0 {
            ZStack {
                Circle()
                    .fill(Color.black)

                switch secondary {
                case .timer:
                    Image(systemName: "timer")
                        .font(.system(size: badgeSize * 0.55, weight: .semibold))
                        .foregroundStyle(timerAccentColor)
                case .reminder(let entry):
                    let accent = reminderColor(for: entry, now: reminderManager.currentDate)
                    Image(systemName: "clock")
                        .font(.system(size: badgeSize * 0.55, weight: .semibold))
                        .foregroundStyle(accent)
                case .focus(let mode):
                    mode.resolvedActiveIcon(usePrivateSymbol: true)
                        .renderingMode(.template)
                        .font(.system(size: badgeSize * 0.5, weight: .semibold))
                        .foregroundStyle(mode.accentColor)
                case .recording:
                    Circle()
                        .fill(Color.red)
                        .frame(width: badgeSize * 0.45, height: badgeSize * 0.45)
                        .modifier(PulsingModifier())
                case .capsLock:
                    Image(systemName: "capslock.fill")
                        .font(.system(size: badgeSize * 0.5, weight: .semibold))
                        .foregroundStyle(capsLockTintMode.color)
                case .extensionPayload(let payload):
                    ExtensionBadgeIconView(
                        descriptor: payload.descriptor.leadingIcon,
                        accent: payload.descriptor.accentColor.swiftUIColor,
                        size: badgeSize
                    )
                case .shelf:
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: badgeSize * 0.50, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: badgeSize, height: badgeSize)
            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
            .transition(.opacity.combined(with: .scale))
        } else {
            EmptyView()
        }
    }

    private func badgeDisplaySize(for secondary: MusicSecondaryLiveActivity?, baseSize: CGFloat) -> CGFloat {
        guard let secondary else { return baseSize }
        switch secondary {
        default:
            return baseSize
        }
    }

    private func badgeOverlayOffset(for secondary: MusicSecondaryLiveActivity?, badgeSize: CGFloat) -> CGSize {
        guard let secondary else { return CGSize(width: badgeSize * 0.2, height: badgeSize * 0.25) }
        switch secondary {
        default:
            return CGSize(width: badgeSize * 0.2, height: badgeSize * 0.25)
        }
    }

    @ViewBuilder
    private func musicRightWing(for secondary: MusicSecondaryLiveActivity?, notchHeight: CGFloat, trailingWidth: CGFloat) -> some View {
        switch secondary {
        case .timer:
            MusicTimerSupplementView(
                timerManager: timerManager,
                accentColor: timerAccentColor,
                showsCountdown: timerShowsCountdown,
                showsProgress: timerShowsProgress,
                progressStyle: timerProgressStyle,
                notchHeight: notchHeight
            )
        case .reminder(let entry):
            MusicReminderSupplementView(
                entry: entry,
                now: reminderManager.currentDate,
                style: reminderPresentationStyle,
                accent: reminderColor(for: entry, now: reminderManager.currentDate),
                notchHeight: notchHeight
            )
        case .capsLock(let showLabel):
            if showLabel {
                MusicCapsLockLabelView(color: capsLockTintMode.color)
            } else {
                spectrumView(forceSpectrum: true)
            }
        case .focus:
            spectrumView(forceSpectrum: true)
        case .recording:
            spectrumView(forceSpectrum: true, trailingInset: 6)
        case .extensionPayload(let payload):
            ExtensionMusicWingView(payload: payload, notchHeight: notchHeight, trailingWidth: trailingWidth)
        case .shelf(let count):
            // File count badge: bold white number, like a minimal pill
            Text("\(count)")
                .font(.system(.callout, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: false))
                .animation(.smooth(duration: 0.3), value: count)
                .frame(alignment: .center)
        case .none:
            spectrumView(
                forceSpectrum: false,
                enableClosedPlayPauseOverlay: shouldShowClosedMusicWaveformPlayPauseOverlay(for: secondary)
            )
        }
    }

    @ViewBuilder
    private func SpectrumVisualizer(
        useMusicVisualizer: Bool,
        forceSpectrum: Bool
    ) -> some View {
        let width = CGFloat(Defaults[.visualizerBarCount]) * 4
        if useMusicVisualizer || forceSpectrum {
            Rectangle()
                .fill((Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : Color.gray).spectrogramGradient())
                .frame(width: 50, alignment: .center)
                .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                .mask {
                    AudioVisualizerView(isPlaying: $musicManager.isPlaying)
                        .frame(width: width, height: 12)
                }
        }
    }

    @ViewBuilder
    private func spectrumView(
        forceSpectrum: Bool,
        trailingInset: CGFloat = 0,
        enableClosedPlayPauseOverlay: Bool = false
    ) -> some View {
        if useMusicVisualizer || forceSpectrum {
            SpectrumVisualizer(useMusicVisualizer: useMusicVisualizer, forceSpectrum: forceSpectrum)
                .blur(radius: (enableClosedPlayPauseOverlay && isHoveringClosedMusicWaveformControl) ? 2.4 : 0)
                .overlay {
                    if enableClosedPlayPauseOverlay {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(isHoveringClosedMusicWaveformControl ? 0.24 : 0.02))

                            Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(isHoveringClosedMusicWaveformControl ? 0.98 : 0.0))
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.trailing, trailingInset)
                .animation(.smooth(duration: 0.16), value: isHoveringClosedMusicWaveformControl)
                .animation(.smooth(duration: 0.2), value: musicManager.isPlaying)
        } else {
            LottieAnimationView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var timerAccentColor: Color {
        switch timerIconColorMode {
        case .adaptive:
            if let presetId = timerManager.activePresetId,
               let preset = timerPresets.first(where: { $0.id == presetId }) {
                return preset.color
            }
            return timerManager.timerColor
        case .solid:
            return timerSolidColor
        }
    }

    private func reminderIconName(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> String {
        isReminderCritical(reminder, now: now) ? ReminderLiveActivityManager.criticalIconName : ReminderLiveActivityManager.standardIconName
    }

    private func isReminderCritical(_ reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> Bool {
        let window = TimeInterval(Defaults[.reminderSneakPeekDuration])
        guard window > 0 else { return false }
        let remaining = reminder.event.start.timeIntervalSince(now)
        return remaining > 0 && remaining <= window
    }

    private func extensionSecondaryPayloadID(for secondary: MusicSecondaryLiveActivity?) -> String? {
        guard case let .extensionPayload(payload) = secondary else { return nil }
        return payload.id
    }

    private func resolvedExtensionMusicPayload() -> ExtensionLiveActivityPayload? {
        let candidates = extensionLiveActivityManager.sortedActivities(for: true)
        guard let payload = candidates.first else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .music,
                reason: "no eligible coexistence payloads",
                pendingCount: candidates.count
            )
            ExtensionRoutingDiagnostics.shared.reset(.music)
            return nil
        }

        guard enableExtensionLiveActivities else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .music,
                reason: "feature toggle disabled",
                pendingCount: candidates.count
            )
            return nil
        }

        guard closedMusicContentEnabled else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .music,
                reason: "music content disabled",
                pendingCount: candidates.count
            )
            return nil
        }

        guard vm.notchState == .closed else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .music,
                reason: "notch is \(vm.notchState)",
                pendingCount: candidates.count
            )
            return nil
        }

        guard !vm.hideOnClosed else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .music,
                reason: "hideOnClosed engaged (fullscreen)",
                pendingCount: candidates.count
            )
            return nil
        }

        guard !lockScreenManager.isLocked else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .music,
                reason: "lock screen currently active",
                pendingCount: candidates.count
            )
            return nil
        }

        guard !isMusicHUDDeferredAfterUnlock else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .music,
                reason: "waiting for lock screen unlock animation to finish",
                pendingCount: candidates.count
            )
            return nil
        }

        guard coordinator.musicLiveActivityEnabled else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .music,
                reason: "music live activity disabled in settings",
                pendingCount: candidates.count
            )
            return nil
        }

        ExtensionRoutingDiagnostics.shared.logDisplay(.music, payload: payload)
        return payload
    }

    private func resolvedExtensionStandalonePayload(excluding musicPayloadID: String?) -> ExtensionLiveActivityPayload? {
        let baseCandidates = extensionLiveActivityManager.sortedActivities()
        guard !baseCandidates.isEmpty else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .standalone,
                reason: "no active extension payloads",
                pendingCount: 0
            )
            ExtensionRoutingDiagnostics.shared.reset(.standalone)
            return nil
        }

        let candidates = baseCandidates.filter { $0.id != musicPayloadID }
        guard let payload = candidates.first else {
            if let musicPayloadID {
                ExtensionRoutingDiagnostics.shared.logSuppression(
                    .standalone,
                    reason: "all pending payloads are paired with music (\(musicPayloadID))",
                    pendingCount: baseCandidates.count
                )
            } else {
                ExtensionRoutingDiagnostics.shared.logSuppression(
                    .standalone,
                    reason: "no standalone payloads after filtering",
                    pendingCount: baseCandidates.count
                )
                ExtensionRoutingDiagnostics.shared.reset(.standalone)
            }
            return nil
        }

        guard enableExtensionLiveActivities else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .standalone,
                reason: "feature toggle disabled",
                pendingCount: candidates.count
            )
            return nil
        }

        guard vm.notchState == .closed else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .standalone,
                reason: "notch is \(vm.notchState)",
                pendingCount: candidates.count
            )
            return nil
        }

        guard !vm.hideOnClosed else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .standalone,
                reason: "hideOnClosed engaged (fullscreen)",
                pendingCount: candidates.count
            )
            return nil
        }

        guard !lockScreenManager.isLocked else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .standalone,
                reason: "lock screen currently active",
                pendingCount: candidates.count
            )
            return nil
        }

        guard vm.effectiveClosedNotchHeight > 0 else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .standalone,
                reason: "effective notch height is \(vm.effectiveClosedNotchHeight)",
                pendingCount: candidates.count
            )
            return nil
        }

        guard !isCurrentScreenExpansionVisible else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .standalone,
                reason: "expanding view \(String(describing: currentScreenExpansionType ?? coordinator.expandingView.type)) visible",
                pendingCount: candidates.count
            )
            return nil
        }

        ExtensionRoutingDiagnostics.shared.logDisplay(.standalone, payload: payload)
        return payload
    }

    private func extensionStandaloneLayout(for payload: ExtensionLiveActivityPayload, notchHeight: CGFloat, isHovering: Bool) -> ExtensionStandaloneLayout {
        let outerHeight = notchHeight
        let contentHeight = max(0, notchHeight - (isHovering ? 0 : 12))
        let leadingWidth = max(contentHeight, 44)
        let centerWidth: CGFloat = max(vm.closedNotchSize.width + (isHovering ? 8 : 0), 96)
        let trailingWidth = ExtensionLayoutMetrics.trailingWidth(
            for: payload,
            baseWidth: leadingWidth,
            maxWidth: leadingWidth + centerWidth * 0.6
        )
        let totalWidth = leadingWidth + centerWidth + trailingWidth
        return ExtensionStandaloneLayout(
            totalWidth: totalWidth,
            outerHeight: outerHeight,
            contentHeight: contentHeight,
            leadingWidth: leadingWidth,
            centerWidth: centerWidth,
            trailingWidth: trailingWidth
        )
    }

    @MainActor
    private final class ExtensionRoutingDiagnostics {
        static let shared = ExtensionRoutingDiagnostics()

        enum Channel: Hashable {
            case music
            case standalone

            var label: String {
                switch self {
                case .music:
                    return "music pairing"
                case .standalone:
                    return "standalone notch"
                }
            }
        }

        private var lastMessages: [Channel: String] = [:]

        func logSuppression(_ channel: Channel, reason: String, pendingCount: Int) {
            log("Extension \(channel.label) suppressed: \(reason) (pending: \(pendingCount))", channel: channel)
        }

        func logDisplay(_ channel: Channel, payload: ExtensionLiveActivityPayload) {
            log("Extension \(channel.label) showing \(payload.descriptor.id) from \(payload.bundleIdentifier)", channel: channel)
        }

        func reset(_ channel: Channel) {
            lastMessages.removeValue(forKey: channel)
        }

        private func log(_ message: String, channel: Channel) {
            guard Defaults[.extensionDiagnosticsLoggingEnabled] else { return }
            guard lastMessages[channel] != message else { return }
            lastMessages[channel] = message
            Logger.log(message, category: .extensions)
        }
    }
    
    @ViewBuilder
    var dragDetector: some View {
        if lockScreenManager.isLocked {
            EmptyView()
        } else if dynamicShelf && !enableMinimalisticUI {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: [.data], isTargeted: $vm.dragDetectorTargeting) { _ in true }
                .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
                    if isTargeted, vm.notchState == .closed {
                        coordinator.currentView = .shelf
                        openNotch()
                    } else if !isTargeted {
                        if vm.dropEvent {
                            vm.dropEvent = false
                            return
                        }

                        vm.dropEvent = false
                        if !shouldPreventAutoClose() {
                            vm.close()
                        }
                    }
                }
        } else {
            EmptyView()
        }
    }

    // MARK: - Private Methods
    private func openNotch() {
        vm.open()
    }

    private func shouldShowClosedMusicWaveformPlayPauseOverlay(for secondary: MusicSecondaryLiveActivity?) -> Bool {
        guard secondary == nil else { return false }
        return isClosedMusicGestureContext && !Defaults[.openNotchOnHover]
    }

    private var isClosedMusicGestureContext: Bool {
        vm.notchState == .closed
            && coordinator.musicLiveActivityEnabled
            && closedMusicContentEnabled
            && !vm.hideOnClosed
            && !lockScreenManager.isLocked
            && !isMusicHUDDeferredAfterUnlock
            && !isCurrentScreenExpansionVisible
            && (!musicManager.isPlayerIdle || musicManager.bundleIdentifier != nil)
            && !coordinator.firstLaunch
    }

    private func handleClosedMusicWaveformTapIfNeeded() -> Bool {
        guard shouldShowClosedMusicWaveformPlayPauseOverlay(for: nil),
              isHoveringClosedMusicWaveformControl else {
            return false
        }

        if Defaults[.enableHaptics] {
            triggerHapticIfAllowed()
        }
        musicManager.playPause()
        return true
    }

    private func hiddenHoverActivationContainsMouse(_ location: NSPoint = NSEvent.mouseLocation) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == currentScreenName }) else {
            return false
        }

        let horizontalPadding: CGFloat = 8
        let activationWidth = vm.closedNotchSize.width + horizontalPadding * 2
        let activationHeight = max(vm.closedNotchSize.height + zeroHeightHoverPadding, 14)

        let activationRect = CGRect(
            x: screen.frame.midX - activationWidth / 2,
            y: screen.frame.maxY - activationHeight,
            width: activationWidth,
            height: activationHeight
        )

        return activationRect.contains(location)
    }

    /// Cancels every long-lived task / event monitor this view owns. Called from
    /// `.onDisappear` and from `vm.onViewTeardown` on window close. Idempotent.
    private func performViewTeardown() {
        hoverTask?.cancel()
        stopHoverClickMonitor()
        removeStickyTerminalClickMonitor()
        stopHiddenEdgeHoverPolling()
        cancelMusicControlWindowSync()
        hideMusicControlWindow()
        cancelMusicControlVisibilityTimer()
        clearMusicControlVisibilityDeadline()
        musicControlSuppressionTask?.cancel()
        isHoveringClosedMusicWaveformControl = false
    }

    private func startHiddenEdgeHoverPolling() {
        guard hiddenEdgeHoverPollingTask == nil else { return }

        hiddenEdgeHoverPollingTask = Task { @MainActor in
            while !Task.isCancelled {
                if self.shouldUseHiddenEdgeHoverPolling {
                    let hovering = self.hiddenHoverActivationContainsMouse()
                    if hovering != self.isHovering {
                        self.handleHover(hovering)
                    }
                } else if self.isHovering && self.interactionsEnabled {
                    let stillInside = self.vm.notchState == .open
                        ? self.isPointInsideNotchWindow()
                        : self.isMouseOverClosedNotchHitArea()
                    if !stillInside {
                        self.hoverTask?.cancel()
                        self.stopHoverClickMonitor()
                        self.finishHoverExit()
                    }
                }

                try? await Task.sleep(for: .milliseconds(self.hiddenEdgeHoverPollingIntervalMs()))
            }

            self.hiddenEdgeHoverPollingTask = nil
        }
    }

    private func hiddenEdgeHoverPollingIntervalMs() -> Int {
        if shouldUseHiddenEdgeHoverPolling {
            return 50
        }
        if isHovering && interactionsEnabled {
            return 100
        }
        return 1_000
    }

    private func stopHiddenEdgeHoverPolling() {
        hiddenEdgeHoverPollingTask?.cancel()
        hiddenEdgeHoverPollingTask = nil
    }

    private func startHoverClickMonitor() {
        guard Defaults[.openNotchOnHover] else { return }
        guard hoverClickMonitor == nil else { return }

        let handleClick: @Sendable () -> Void = { [weak vm, weak lockScreenManager] in
            Task { @MainActor in
                guard let vm, let lockScreenManager else { return }
                guard !lockScreenManager.isLocked else { return }
                guard vm.notchState == .closed else { return }
                guard !self.coordinator.isHoverOpenSuppressed else { return }
                // Modified for Gourd (2026-09-28)：模块浮层（如通知）显示期间抑制「悬浮即展开」，
                // 否则 mouseDown 会抢走浮层上按钮的点击（浮层只有 4s，点击意图明确是操作浮层本身）。
                // 判据放在回调**内部**而不是「不装监听器」：装/卸与 hover 状态耦合，内部判断无生命周期问题。
                guard !shouldSuppressHoverOpen(activeHUD: ModuleRegistry.shared.activeHUD) else { return }
                guard self.isHovering else { return }
                guard !self.handleClosedMusicWaveformTapIfNeeded() else { return }
                if Defaults[.enableHaptics] {
                    self.triggerHapticIfAllowed()
                }
                self.openNotch()
            }
        }

        // Global monitor catches clicks outside the app window (e.g. when
        // the cursor is at the very top screen edge and the click goes to
        // the system rather than our panel).
        hoverClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { _ in
            handleClick()
        }

        // Local monitor catches clicks that DO hit our window — at the
        // screen edge SwiftUI's .onTapGesture may not fire reliably, but
        // the NSEvent local monitor will.
        hoverClickLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            handleClick()
            return event
        }
    }

    private func stopHoverClickMonitor() {
        if let hoverClickMonitor {
            NSEvent.removeMonitor(hoverClickMonitor)
            self.hoverClickMonitor = nil
        }
        if let hoverClickLocalMonitor {
            NSEvent.removeMonitor(hoverClickLocalMonitor)
            self.hoverClickLocalMonitor = nil
        }
    }

    /// Installs the global outside-click monitor whenever the Terminal tab is open
    /// (e.g. keyboard-opened terminal), regardless of sticky mode.
    ///
    /// Sticky mode only controls whether the terminal closes when the cursor leaves
    /// the notch (see `shouldPreventAutoClose`).  An outside click should always close
    /// the terminal — this covers the case where the terminal is opened via the
    /// shortcut and the cursor never enters the notch, so there's no hover-out event
    /// to trigger the normal auto-close.
    ///
    /// While the cursor is hovering inside the notch, hover handling owns close
    /// behavior, so the monitor is not installed; it is re-synced on hover-out.
    private func syncStickyTerminalOutsideClickMonitor() {
        guard vm.notchState == .open, coordinator.currentView == .terminal, !isHovering else {
            removeStickyTerminalClickMonitor()
            return
        }
        installStickyTerminalClickMonitor()
    }

    private func installStickyTerminalClickMonitor() {
        guard stickyTerminalClickMonitor == nil else { return }
        stickyTerminalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak vm] _ in
            Task { @MainActor in
                guard let vm, vm.notchState == .open else { return }
                let clickLocation = NSEvent.mouseLocation
                if self.isPointInsideNotchWindow(clickLocation) {
                    return
                }
                vm.close()
            }
        }
    }

    private func removeStickyTerminalClickMonitor() {
        if let stickyTerminalClickMonitor {
            NSEvent.removeMonitor(stickyTerminalClickMonitor)
            self.stickyTerminalClickMonitor = nil
        }
    }

    // MARK: - Hover Management
    
    /// Handle hover state changes with debouncing
    private func handleHover(_ hovering: Bool) {
        // Ignore false hover-exit when the cursor is parked on the screen's top pixel.
        if !hovering, shouldRetainHoverAtScreenTopEdge() {
            return
        }

        hoverTask?.cancel()

        if hovering {
            startHoverClickMonitor()
            removeStickyTerminalClickMonitor()
        } else {
            stopHoverClickMonitor()
            if isHoveringClosedMusicWaveformControl {
                withAnimation(.smooth(duration: 0.16)) {
                    isHoveringClosedMusicWaveformControl = false
                }
            }
        }

        if hovering {
            withAnimation(.bouncy.speed(1.2)) {
                isHovering = true
            }

            if vm.notchState == .closed && Defaults[.enableHaptics] {
                triggerHapticIfAllowed()
            }

            let shouldFocusTimerTab = enableTimerFeature && timerDisplayMode == .tab && timerManager.isTimerActive && !enableMinimalisticUI

            guard vm.notchState == .closed,
                !isSneakPeekVisibleOnCurrentScreen,
                (Defaults[.openNotchOnHover] || shouldFocusTimerTab) else { return }

            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.isSneakPeekVisibleOnCurrentScreen,
                          !self.coordinator.isHoverOpenSuppressed else { return }

                    // Modified for Gourd (2026-09-28)：模块浮层（如通知）显示期间抑制「悬浮即展开」，
                    // 否则 mouseDown 会抢走浮层上按钮的点击（浮层只有 4s，点击意图明确是操作浮层本身）。
                    // 延时到点后浮层若已消失（ttl 走完）则照旧展开——这是刻意的，不重新计时。
                    guard !shouldSuppressHoverOpen(activeHUD: ModuleRegistry.shared.activeHUD) else { return }

                    if shouldFocusTimerTab {
                        withAnimation(.smooth) {
                            // 计时器的第二入口（悬浮聚焦）：接管后计时器页是**模块 tab**，
                            // 走 `selectModule` 才有点亮 tab 与 250pt 高度档（docs/20 §做法 机制六）。
                            // `shouldFocusTimerTab` 的判据与随后的 `openNotch()` 保持原样。
                            self.coordinator.selectModule(TimerModule.moduleID)
                        }
                    }
                    self.openNotch()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    if self.shouldRetainHoverAtScreenTopEdge() {
                        return
                    }
                    self.finishHoverExit()
                }
            }
        }
    }

    private func finishHoverExit() {
        withAnimation(.bouncy.speed(1.2)) {
            isHovering = false
        }

        if vm.notchState == .open && !shouldPreventAutoClose() {
            vm.close()
        } else if vm.notchState == .open
                    && Defaults[.terminalStickyMode]
                    && coordinator.currentView == .terminal {
            // Re-sync monitor state through one code path to avoid
            // monitor lifecycle races between hover and state updates.
            syncStickyTerminalOutsideClickMonitor()
        }
    }

    private func shouldRetainHoverAtScreenTopEdge(_ location: NSPoint = NSEvent.mouseLocation) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == currentScreenName }) else {
            return false
        }
        guard isHovering || vm.notchState == .open else { return false }
        guard location.y >= screen.frame.maxY - 1.5 else { return false }

        if vm.notchState == .open {
            return isPointInsideNotchWindow(location)
        }
        return isMouseOverClosedNotchHitArea(location)
    }

    private func isMouseOverClosedNotchHitArea(_ location: NSPoint = NSEvent.mouseLocation) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == currentScreenName }) else {
            return false
        }

        let height = vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0) + 6
        let width = max(vm.closedNotchSize.width + (isHovering ? 8 : 0), 96) + 24
        let minX = screen.frame.midX - width / 2
        let minY = screen.frame.maxY - height

        return location.x >= minX && location.x <= minX + width
            && location.y >= minY && location.y <= screen.frame.maxY
    }

    private func isPointInsideNotchWindow(_ point: CGPoint = NSEvent.mouseLocation) -> Bool {
        if let appDelegate = AppDelegate.shared {
            if Defaults[.showOnAllDisplays] {
                return appDelegate.windows.values.contains(where: { frameContainsPointIncludingTopEdge($0.frame, point) })
            }
            if let window = appDelegate.window {
                return frameContainsPointIncludingTopEdge(window.frame, point)
            }
        }

        return NSApp.windows.contains(where: { frameContainsPointIncludingTopEdge($0.frame, point) })
    }

    /// `CGRect.contains` is half-open on max edges; the top pixel needs inclusive maxY.
    private func frameContainsPointIncludingTopEdge(_ frame: CGRect, _ point: CGPoint) -> Bool {
        point.x >= frame.minX && point.x <= frame.maxX
            && point.y >= frame.minY && point.y <= frame.maxY
    }
    
    // Helper function to check if any popovers are active
    private func hasAnyActivePopovers() -> Bool {
     return vm.isBatteryPopoverActive || 
         vm.isClipboardPopoverActive || 
         vm.isColorPickerPopoverActive || 
         vm.isStatsPopoverActive ||
         vm.isTimerPopoverActive ||
         vm.isMediaOutputPopoverActive ||
         vm.isReminderPopoverActive
    }

    private func shouldPreventAutoClose() -> Bool {
        // Dragging a shelf item out necessarily takes the cursor off the notch.
        // Without this, the hover-exit timer closes the panel mid-drag, tearing
        // down the NSView that is acting as the drag source and cancelling the
        // session — an independent second cause of "drag-out doesn't work".
        //
        // 2026-09-29（用户反馈「浏览很容易自动收回」）：「正在拖动右下角调整尺寸」是同一类情形，
        // 也并进这条判据。拖动把手必然会把光标带出面板——面板扩宽是**居中**的，右边缘只走位移
        // 的一半，光标只要往右多拖 ~40pt 就已经出了面板（本机实测：拖动 140ms 后 hover 离开
        // 就触发了 `finishHoverExit`）。照常收起会把把手视图一起拆掉，拖动手势当场中断，
        // 用户看到的就是「拖到一半自己收起来了」。抑制口径与 shelf / 剪贴板拖出**逐字同源**：
        // 只挡「因 hover 离开而自动收起」这一族，不碰 `vm.close()` 的显式调用方
        // （快捷键、锁屏、终端外侧点击等都不走这条判据）。
        // 手移开后补的那次 hover 复检（`hiddenEdgeHoverPolling`）同样读这条判据，因此松手瞬间
        // 也不会因为「光标还在面板外」而立刻收起——面板留在原地让用户看到结果，下一次真正的
        // hover 进入 / 离开照旧按原判据收起。
        coordinator.firstLaunch || hasAnyActivePopovers() || vm.isAutoCloseSuppressed || ShelfSelectionModel.shared.isDragging || ClipboardManager.shared.isDraggingItem || SharingStateManager.shared.preventNotchClose || (Defaults[.terminalStickyMode] && coordinator.currentView == .terminal) || isPanelResizing
    }
    
    // Helper to prevent rapid haptic feedback
    private func triggerHapticIfAllowed() {
        let now = Date()
        if now.timeIntervalSince(lastHapticTime) > 0.3 { // Minimum 300ms between haptics
            haptics.toggle()
            lastHapticTime = now
        }
    }
    
    // Helper to check if stats tab has 4+ graphs (needs expanded height)
    private func enabledStatsGraphCount() -> Int {
        var enabledCount = 0
        if showCpuGraph { enabledCount += 1 }
        if showMemoryGraph { enabledCount += 1 }
        if showGpuGraph { enabledCount += 1 }
        if showNetworkGraph { enabledCount += 1 }
        if showDiskGraph { enabledCount += 1 }
        return enabledCount
    }

    private func statsRowCount() -> Int {
        let count = enabledStatsGraphCount()
        if count == 0 { return 0 }
        return count <= 3 ? 1 : 2
    }

    private func currentExtensionTabPayload() -> ExtensionNotchExperiencePayload? {
        guard Defaults[.enableThirdPartyExtensions],
              Defaults[.enableExtensionNotchExperiences],
              Defaults[.enableExtensionNotchTabs] else {
            return nil
        }
        if let selectedID = coordinator.selectedExtensionExperienceID,
           let payload = extensionNotchExperienceManager.payload(experienceID: selectedID) {
            return payload
        }
        return extensionNotchExperienceManager.highestPriorityTabPayload()
    }

    private func extensionTabPreferredHeight(baseSize: CGSize) -> CGFloat? {
        guard let preferred = currentExtensionTabPayload()?.descriptor.tab?.preferredHeight else {
            return nil
        }
        let minHeight = baseSize.height
        let maxHeight = baseSize.height + statsAdditionalRowHeight
        return min(max(preferred, minHeight), maxHeight)
    }

    // Estimate the height required for minimalistic overrides (notably web content) and clamp it to the notch bounds.
    private func extensionMinimalisticPreferredHeight(baseSize: CGSize) -> CGFloat? {
        guard let configuration = extensionNotchExperienceManager.minimalisticReplacementPayload()?.descriptor.minimalistic else {
            return nil
        }

        let minHeight = baseSize.height
        let maxHeight = baseSize.height + statsAdditionalRowHeight

        var contentHeight: CGFloat = 0
        var blockCount = 0

        if configuration.headline != nil {
            contentHeight += 24
            blockCount += 1
        }

        if configuration.subtitle != nil {
            contentHeight += 20
            blockCount += 1
        }

        if !configuration.sections.isEmpty {
            let sectionEstimate: CGFloat = 98
            contentHeight += CGFloat(configuration.sections.count) * sectionEstimate
            blockCount += configuration.sections.count
        }

        if let webDescriptor = configuration.webContent {
            contentHeight += webDescriptor.preferredHeight
            blockCount += 1
        }

        guard blockCount > 0 else { return nil }

        let spacingAllowance = CGFloat(max(blockCount - 1, 0)) * 16
        let topPadding: CGFloat = 10
        let bottomPadding: CGFloat = configuration.webContent == nil ? 10 : 0
        let estimatedHeight = contentHeight + spacingAllowance + topPadding + bottomPadding

        let clampedHeight = min(max(estimatedHeight, minHeight), maxHeight)
        return clampedHeight > minHeight ? clampedHeight : nil
    }
    
    // MARK: - Gesture Handling
    
    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        handleScrollGesture(isDownward: true, translation: translation, phase: phase)
    }
    
    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        handleScrollGesture(isDownward: false, translation: translation, phase: phase)
    }

    private func handleScrollGesture(isDownward: Bool, translation: CGFloat, phase: NSEvent.Phase) {
        let reverse = Defaults[.reverseScrollGestures]
        let shouldOpen = isDownward ? !reverse : reverse

        if shouldOpen {
            handleOpenScrollGesture(translation: translation, phase: phase)
        } else {
            guard Defaults[.closeGestureEnabled] else { return }
            handleCloseScrollGesture(translation: translation, phase: phase)
        }
    }

    private func handleOpenScrollGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }

        withAnimation(.smooth) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if phase == .ended {
            withAnimation(.smooth) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                triggerHapticIfAllowed()
            }
            withAnimation(.smooth) {
                gestureProgress = .zero
            }
            openNotch()
        }
    }

    private func handleCloseScrollGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open, !vm.isHoveringCalendar, !vm.isScrollGestureActive else { return }

        withAnimation(.smooth) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(.smooth) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(.smooth) {
                gestureProgress = .zero
                isHovering = false
            }
            vm.close()

            if Defaults[.enableHaptics] {
                triggerHapticIfAllowed()
            }
        }
    }

    private func handleSkipGesture(direction: MusicManager.SkipDirection, translation: CGFloat, phase: NSEvent.Phase) {
        if phase == .ended {
            skipGestureActiveDirection = nil
            return
        }

        guard canPerformSkipGesture() else {
            skipGestureActiveDirection = nil
            return
        }

        if skipGestureActiveDirection == nil && translation > Defaults[.gestureSensitivity] {
            let effectiveDirection: MusicManager.SkipDirection
            if Defaults[.reverseSwipeGestures] {
                effectiveDirection = direction == .forward ? .backward : .forward
            } else {
                effectiveDirection = direction
            }
            skipGestureActiveDirection = effectiveDirection

            if Defaults[.enableHaptics] {
                triggerHapticIfAllowed()
            }

            musicManager.handleSkipGesture(direction: effectiveDirection)
        }
    }

    private func canPerformSkipGesture() -> Bool {
        let canSkipInOpenHome = vm.notchState == .open && coordinator.currentView == .home
        let canSkipInClosedMusic = !Defaults[.openNotchOnHover] && isClosedMusicGestureContext

        return enableHorizontalMusicGestures
            && (canSkipInOpenHome || canSkipInClosedMusic)
            && (!musicManager.isPlayerIdle || musicManager.bundleIdentifier != nil)
            && !lockScreenManager.isLocked
            && !hasAnyActivePopovers()
            && !vm.isHoveringCalendar
            && !vm.isScrollGestureActive
    }

    private func handleMusicControlPlaybackChange(isPlaying: Bool) {
        guard musicControlWindowEnabled else { return }

        if isPlaying {
            clearMusicControlVisibilityDeadline()
            requestMusicControlWindowSyncIfHidden()
        } else {
            extendMusicControlVisibilityAfterPause()
        }
    }

    private func handleMusicControlIdleChange(isIdle: Bool) {
        guard musicControlWindowEnabled else { return }

        if isIdle {
            if musicControlVisibilityDeadline == nil {
                extendMusicControlVisibilityAfterPause()
            }
        } else if musicManager.isPlaying {
            clearMusicControlVisibilityDeadline()
        }
    }

    private func handleStandardMediaControlsAvailabilityChange() {
        guard musicControlWindowEnabled else {
            hideMusicControlWindow()
            return
        }

        if standardMediaControlsActive {
            if musicManager.isPlaying || !musicManager.isPlayerIdle {
                clearMusicControlVisibilityDeadline()
            }
            enqueueMusicControlWindowSync(forceRefresh: true)
        } else {
            cancelMusicControlWindowSync()
            hideMusicControlWindow()
            clearMusicControlVisibilityDeadline()
            hasPendingMusicControlSync = false
            pendingMusicControlForceRefresh = false
        }
    }

    private func extendMusicControlVisibilityAfterPause() {
        let deadline = Date().addingTimeInterval(musicControlPauseGrace)
        musicControlVisibilityDeadline = deadline
        scheduleMusicControlVisibilityCheck(deadline: deadline)
        requestMusicControlWindowSyncIfHidden()
    }

    private func clearMusicControlVisibilityDeadline() {
        musicControlVisibilityDeadline = nil
        cancelMusicControlVisibilityTimer()
    }

    private func scheduleMusicControlVisibilityCheck(deadline: Date) {
        cancelMusicControlVisibilityTimer()

        let interval = max(0, deadline.timeIntervalSinceNow)

        musicControlHideTask = Task.detached(priority: .background) { [interval] in
            if interval > 0 {
                let nanoseconds = UInt64(interval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                if let currentDeadline = musicControlVisibilityDeadline, currentDeadline <= Date() {
                    musicControlVisibilityDeadline = nil
                }

                enqueueMusicControlWindowSync(forceRefresh: false)

                musicControlHideTask = nil
            }
        }
    }

    private func cancelMusicControlVisibilityTimer() {
        musicControlHideTask?.cancel()
        musicControlHideTask = nil
    }

    private func musicControlVisibilityIsActive() -> Bool {
        if musicManager.isPlaying {
            return true
        }

        guard let deadline = musicControlVisibilityDeadline else { return false }
        return Date() <= deadline
    }

    private func suppressMusicControlWindowUpdates() {
        isMusicControlWindowSuppressed = true
        musicControlSuppressionTask?.cancel()
        musicControlSuppressionTask = nil
    }

    private func releaseMusicControlWindowUpdates(after delay: TimeInterval) {
        musicControlSuppressionTask?.cancel()
        musicControlSuppressionTask = Task { [delay] in
            if delay > 0 {
                let nanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                if vm.notchState == .closed && !lockScreenManager.isLocked && !isMusicHUDDeferredAfterUnlock {
                    isMusicControlWindowSuppressed = false
                    triggerPendingMusicControlSyncIfNeeded()
                } else {
                    isMusicControlWindowSuppressed = true
                }
                musicControlSuppressionTask = nil
            }
        }
    }

    private func triggerPendingMusicControlSyncIfNeeded() {
        guard hasPendingMusicControlSync else { return }

        let shouldForce = pendingMusicControlForceRefresh
        hasPendingMusicControlSync = false
        pendingMusicControlForceRefresh = false

        logMusicControlEvent("Flushing pending floating window sync (force: \(shouldForce))")
        scheduleMusicControlWindowSync(forceRefresh: shouldForce, bypassSuppression: true)
    }

    private func shouldDeferMusicControlSync() -> Bool {
        vm.notchState != .closed
            || lockScreenManager.isLocked
            || isMusicHUDDeferredAfterUnlock
            || isMusicControlWindowSuppressed
    }

    private func enqueueMusicControlWindowSync(forceRefresh: Bool, delay: TimeInterval = 0) {
        if shouldDeferMusicControlSync() {
            hasPendingMusicControlSync = true
            if forceRefresh {
                pendingMusicControlForceRefresh = true
            }
            logMusicControlEvent("Queued floating window sync (force: \(forceRefresh)) while deferred")
            return
        }

        logMusicControlEvent("Scheduling floating window sync (force: \(forceRefresh), delay: \(delay))")
        scheduleMusicControlWindowSync(forceRefresh: forceRefresh, delay: delay)
    }

    private func shouldShowMusicControlWindow() -> Bool {
        guard musicControlWindowEnabled,
              coordinator.musicLiveActivityEnabled,
              standardMediaControlsActive,
              vm.notchState == .closed,
              !vm.hideOnClosed,
              !lockScreenManager.isLocked,
              !isMusicHUDDeferredAfterUnlock,
              !isMusicControlWindowSuppressed else {
            return false
        }

        return musicControlVisibilityIsActive()
    }

    private func scheduleMusicControlWindowSync(forceRefresh: Bool, delay: TimeInterval = 0, bypassSuppression: Bool = false) {
        #if os(macOS)
        cancelMusicControlWindowSync()

        guard shouldShowMusicControlWindow() else {
            hasPendingMusicControlSync = false
            pendingMusicControlForceRefresh = false
            hideMusicControlWindow()
            return
        }

        if !bypassSuppression && (isMusicControlWindowSuppressed || lockScreenManager.isLocked || isMusicHUDDeferredAfterUnlock) {
            hasPendingMusicControlSync = true
            if forceRefresh {
                pendingMusicControlForceRefresh = true
            }
            return
        }

        hasPendingMusicControlSync = false
        pendingMusicControlForceRefresh = false

        let syncDelay = max(0, delay)

        pendingMusicControlTask = Task.detached(priority: .userInitiated) { [forceRefresh, syncDelay] in
            if syncDelay > 0 {
                let nanoseconds = UInt64(syncDelay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                if shouldShowMusicControlWindow() {
                    logMusicControlEvent("Running floating window sync (force: \(forceRefresh))")
                    syncMusicControlWindow(forceRefresh: forceRefresh)
                } else {
                    logMusicControlEvent("Skipping floating window sync (conditions changed)")
                    hideMusicControlWindow()
                }

                pendingMusicControlTask = nil
            }
        }
        #endif
    }

    private func cancelMusicControlWindowSync() {
        pendingMusicControlTask?.cancel()
        pendingMusicControlTask = nil
    }

    #if os(macOS)
    private struct MusicControlWindowContentKey: Hashable {
        let isPlaying: Bool
        let isPlayerIdle: Bool
        let bundleIdentifier: String?
        let skipBehavior: String
        let skipGestureToken: Int?
    }

    private var musicControlWindowContentRevision: AnyHashable {
        AnyHashable(
            MusicControlWindowContentKey(
                isPlaying: musicManager.isPlaying,
                isPlayerIdle: musicManager.isPlayerIdle,
                bundleIdentifier: musicManager.bundleIdentifier,
                skipBehavior: Defaults[.musicSkipBehavior].rawValue,
                skipGestureToken: musicManager.skipGesturePulse?.token
            )
        )
    }

    private func currentMusicControlWindowMetrics() -> MusicControlWindowMetrics {
        MusicControlWindowMetrics(
            notchHeight: max(vm.closedNotchSize.height, vm.effectiveClosedNotchHeight),
            notchWidth: vm.closedNotchSize.width + (isHovering ? 8 : 0),
            rightWingWidth: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2),
            cornerRadius: activeCornerRadiusInsets.closed.bottom,
            spacing: 36,
            contentRevision: musicControlWindowContentRevision
        )
    }

    private func syncMusicControlWindow(forceRefresh: Bool = false) {
        let notchAvailable = vm.effectiveClosedNotchHeight > 0 && vm.closedNotchSize.width > 0
        let targetVisible = shouldShowMusicControlWindow() && notchAvailable

        if targetVisible {
            let metrics = currentMusicControlWindowMetrics()
            if !isMusicControlWindowVisible {
                let didPresent = MusicControlWindowManager.shared.present(using: vm, metrics: metrics)
                isMusicControlWindowVisible = didPresent
            } else if forceRefresh {
                let didRefresh = MusicControlWindowManager.shared.refresh(using: vm, metrics: metrics)
                if !didRefresh {
                    MusicControlWindowManager.shared.hide()
                    isMusicControlWindowVisible = false
                }
            }
        } else if isMusicControlWindowVisible {
            MusicControlWindowManager.shared.hide()
            isMusicControlWindowVisible = false
        }
    }

    private func hideMusicControlWindow() {
        if isMusicControlWindowVisible {
            MusicControlWindowManager.shared.hide()
            isMusicControlWindowVisible = false
        }
    }
    #else
    private func syncMusicControlWindow(forceRefresh: Bool = false) {}

    private func hideMusicControlWindow() {}
    #endif
    
    private func shouldFixSizeForSneakPeek() -> Bool {
        guard isSneakPeekVisibleOnCurrentScreen else { return false }
        let style = resolvedSneakPeekStyle()
        
        // Check for extension sneak peek
        if case .extensionLiveActivity = coordinator.sneakPeek.type {
            return vm.notchState == .closed && style == .standard
        }
        
        // Original logic for other types
        let isMusicSneak = coordinator.sneakPeek.type == .music && vm.notchState == .closed && !vm.hideOnClosed && style == .standard
        let isTimerSneak = coordinator.sneakPeek.type == .timer && !vm.hideOnClosed && style == .standard
        let isReminderSneak = coordinator.sneakPeek.type == .reminder && !vm.hideOnClosed && style == .standard
        let isOtherSneak = coordinator.sneakPeek.type != .music && coordinator.sneakPeek.type != .timer && coordinator.sneakPeek.type != .reminder && vm.notchState == .closed
        
        return isMusicSneak || isTimerSneak || isReminderSneak || isOtherSneak
    }

    private func resolvedSneakPeekStyle() -> SneakPeekStyle {
        if case .extensionLiveActivity = coordinator.sneakPeek.type {
            return .standard
        }
        return coordinator.sneakPeek.styleOverride ?? Defaults[.sneakPeekStyles]
    }
}

private enum MusicSecondaryLiveActivity: Equatable {
    case timer
    case reminder(ReminderLiveActivityManager.ReminderEntry)
    case recording
    case focus(FocusModeType)
    case capsLock(showLabel: Bool)
    case extensionPayload(ExtensionLiveActivityPayload)
    case shelf(count: Int)

    var id: String {
        switch self {
        case .timer:
            return "timer"
        case .reminder(let entry):
            return "reminder-\(entry.id)"
        case .recording:
            return "recording"
        case .focus(let mode):
            return "focus-\(mode.rawValue)"
        case .capsLock(let showLabel):
            return showLabel ? "caps-lock-label" : "caps-lock-icon"
        case .extensionPayload(let payload):
            return "extension-\(payload.id)"
        case .shelf(let count):
            return "shelf-\(count)"
        }
    }
}

private struct MusicTimerSupplementView: View {
    @ObservedObject var timerManager: TimerManager
    let accentColor: Color
    let showsCountdown: Bool
    let showsProgress: Bool
    let progressStyle: TimerProgressStyle
    let notchHeight: CGFloat

    private var clampedProgress: Double {
        min(max(timerManager.progress, 0), 1)
    }

    private var showsRingProgress: Bool {
        showsProgress && progressStyle == .ring
    }

    private var showsBarProgress: Bool {
        showsProgress && progressStyle == .bar
    }

    private var countdownText: String {
        timerManager.formattedRemainingTime()
    }

    private var countdownTextWidth: CGFloat {
        max(1, TimerSupplementMetrics.countdownTextWidth(for: countdownText))
    }

    private var countdownFrameWidth: CGFloat {
        TimerSupplementMetrics.countdownFrameWidth(for: countdownText)
    }

    private var timerNameFrameWidth: CGFloat {
        TimerSupplementMetrics.timerNameFrameWidth(for: timerManager.timerName)
    }

    private var ringDiameter: CGFloat {
        max(min(notchHeight - 4, 26), 20)
    }

    var body: some View {
        HStack(spacing: showsRingProgress && showsCountdown ? 8 : 0) {
            if showsRingProgress {
                ringView
            }

            if showsCountdown {
                countdownStack
            } else if showsBarProgress {
                standaloneBarView
            } else {
                timerNameView
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var countdownStack: some View {
        VStack(alignment: .trailing, spacing: showsBarProgress ? 4 : 0) {
            Text(countdownText)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(timerManager.isOvertime ? .red : .white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.25), value: timerManager.remainingTime)
                .frame(width: countdownFrameWidth, alignment: .trailing)

            if showsBarProgress {
                barView(width: countdownTextWidth)
            }
        }
        .padding(.trailing, 2)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var ringView: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.25), value: clampedProgress)
        }
        .frame(width: ringDiameter, height: ringDiameter)
        .frame(width: max(ringDiameter + 4, 30), height: notchHeight, alignment: .center)
    }

    private var standaloneBarView: some View {
        barView(width: 68)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var timerNameView: some View {
        Text(timerManager.timerName)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .lineLimit(1)
            .frame(width: timerNameFrameWidth, alignment: .trailing)
    }

    private func barView(width: CGFloat) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.15))
            .frame(width: width, height: 4)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(accentColor)
                    .frame(width: width * max(0, CGFloat(clampedProgress)), height: 4)
                    .animation(.smooth(duration: 0.25), value: clampedProgress)
            }
    }

}

private struct MusicReminderSupplementView: View {
    let entry: ReminderLiveActivityManager.ReminderEntry
    let now: Date
    let style: ReminderPresentationStyle
    let accent: Color
    let notchHeight: CGFloat

    var body: some View {
        Group {
            switch style {
            case .ringCountdown:
                ringCountdownView
            case .digital:
                digitalCountdownView
            case .minutes:
                minutesCountdownView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    private var ringCountdownView: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progressValue)
                .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.25), value: progressValue)
        }
        .frame(width: ringDiameter, height: ringDiameter)
        .frame(width: max(ringDiameter + 4, 26), height: notchHeight, alignment: .center)
    }

    private var digitalCountdownView: some View {
        Text(digitalCountdownText)
            .font(.system(size: 15, weight: .semibold, design: .monospaced))
            .foregroundColor(accent)
            .contentTransition(.numericText())
            .animation(.smooth(duration: 0.25), value: digitalCountdownText)
            .frame(width: digitalFrameWidth, alignment: .trailing)
            .frame(height: notchHeight, alignment: .center)
    }

    private var minutesCountdownView: some View {
        Text(minutesCountdownText)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(accent)
            .frame(width: minutesFrameWidth, alignment: .trailing)
            .frame(height: notchHeight, alignment: .center)
    }

    private var progressValue: Double {
        guard entry.leadTime > 0 else { return 1 }
        let remaining = max(entry.event.start.timeIntervalSince(now), 0)
        let elapsed = entry.leadTime - remaining
        return min(max(elapsed / entry.leadTime, 0), 1)
    }

    private var digitalCountdownText: String {
        ReminderSupplementMetrics.digitalCountdownText(for: entry, now: now)
    }

    private var minutesCountdownText: String {
        ReminderSupplementMetrics.minutesCountdownText(for: entry, now: now)
    }

    private var ringDiameter: CGFloat {
        ReminderSupplementMetrics.ringDiameter(for: notchHeight)
    }

    private var digitalFrameWidth: CGFloat {
        ReminderSupplementMetrics.digitalFrameWidth(for: digitalCountdownText)
    }

    private var minutesFrameWidth: CGFloat {
        ReminderSupplementMetrics.minutesFrameWidth(for: minutesCountdownText)
    }
}

private struct MusicCapsLockLabelView: View {
    let color: Color

    var body: some View {
        Text("Caps Lock")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .contentTransition(.opacity)
    }
}

#if canImport(AppKit)
private typealias MusicSupplementFont = NSFont
#elseif canImport(UIKit)
private typealias MusicSupplementFont = UIFont
#endif

private enum TimerSupplementMetrics {
    static func countdownTextWidth(for text: String) -> CGFloat {
        // Measure with a fully monospaced font (matching the `.monospaced` design used
        // to render) so hour-format times like 1:00:00 aren't under-measured and clipped.
        musicMeasureText(text, font: MusicSupplementFont.monospacedSystemFont(ofSize: 13, weight: .semibold))
    }

    static func countdownFrameWidth(for text: String) -> CGFloat {
        max(countdownTextWidth(for: text) + 16, 72)
    }

    static func timerNameFrameWidth(for text: String) -> CGFloat {
        guard !text.isEmpty else { return 64 }
        let width = musicMeasureText(text, font: MusicSupplementFont.systemFont(ofSize: 12, weight: .medium))
        return max(width + 14, 64)
    }
}

private enum ReminderSupplementMetrics {
    static func digitalCountdownText(for entry: ReminderLiveActivityManager.ReminderEntry, now: Date) -> String {
        let remaining = max(entry.event.start.timeIntervalSince(now), 0)
        let totalSeconds = Int(remaining.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func minutesCountdownText(for entry: ReminderLiveActivityManager.ReminderEntry, now: Date) -> String {
        let remaining = max(entry.event.start.timeIntervalSince(now), 0)
        let minutes = max(1, Int(ceil(remaining / 60)))
        return minutes == 1 ? "in 1 min" : "in \(minutes) min"
    }

    static func digitalFrameWidth(for text: String) -> CGFloat {
        let width = musicMeasureText(text, font: MusicSupplementFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold))
        return max(width + 18, 76)
    }

    static func minutesFrameWidth(for text: String) -> CGFloat {
        let width = musicMeasureText(text, font: MusicSupplementFont.systemFont(ofSize: 13, weight: .semibold))
        return max(width + 18, 88)
    }

    static func ringDiameter(for notchHeight: CGFloat) -> CGFloat {
        max(min(notchHeight - 12, 22), 16)
    }
}

private func musicMeasureText(_ text: String, font: MusicSupplementFont) -> CGFloat {
    guard !text.isEmpty else { return 0 }
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    return CGFloat(ceil(NSAttributedString(string: text, attributes: attributes).size().width))
}

/// 主面板的**毛玻璃底**（`NotchPanelBackgroundStyle.frostedGlass`）。
///
/// 用 `NSVisualEffectView` 的 `.hudWindow` + `.behindWindow`（`state = .active`）——这是工程里
/// 悬浮面板 / 弹窗一族一直在用的材质（`TimerPopover` / `ClipboardPanel` / `ChatPanels` …），
/// 取它能让主面板的观感与这些面板一致。
///
/// **强制深色外观**：口径同 `EditPanelView.VisualEffectView.forcedAppearance`——`hudWindow`
/// 材质在浅色系统外观下会渲染成**浅色**磨砂玻璃，与面板内的白色文字冲突（白字压浅底看不清）。
struct PanelFrostedGlassBackground: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.isEmphasized = true
        visualEffectView.appearance = NSAppearance(named: .darkAqua)
        return visualEffectView
    }

    func updateNSView(_ visualEffectView: NSVisualEffectView, context _: Context) {
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.appearance = NSAppearance(named: .darkAqua)
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }
}
