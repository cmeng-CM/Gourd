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

import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

/// Layout budgets applied to the home view only while the side lyrics panel is active
enum SideLyricsLayout {
    /// Room the standard player needs for its album art and five-button control row
    static let minimumPlayerWidth: CGFloat = 380

    /// Room the webcam mirror needs to stay usable next to the player
    static let minimumMirrorWidth: CGFloat = 220

    /// Spacing between the player, mirror, and lyrics panel columns
    static let hStackSpacing: CGFloat = 20

    /// Combined home-view and notch content insets surrounding those columns
    static let combinedInset: CGFloat = 40
}

func sideLyricsRequiredNotchWidth() -> CGFloat {
    guard Defaults[.enableLyrics],
          !Defaults[.showCalendar],
          !Defaults[.enableMinimalisticUI],
          Defaults[.showStandardMediaControls],
          (!Defaults[.autoHideInactiveNotchMediaPlayer] || MusicManager.shared.hasActiveSession)
    else { return 0 }

    let panelWidth = max(0, Defaults[.lyricsPanelWidth])
    let offsetDistance = abs(Defaults[.lyricsPanelOffset])
    let mirrorWidth = Defaults[.showMirror] && WebcamManager.shared.cameraAvailable
        ? SideLyricsLayout.minimumMirrorWidth + SideLyricsLayout.hStackSpacing
        : 0

    // Include the home-view and notch content insets so the player receives
    // the same usable width it had before the panel was added.
    return SideLyricsLayout.minimumPlayerWidth
        + panelWidth
        + SideLyricsLayout.hStackSpacing
        + offsetDistance
        + mirrorWidth
        + SideLyricsLayout.combinedInset
}

/// 展开态高度的**可配范围**（用户可拖的区间，也是夹取的下界 + 绝对上界）。
///
/// 2026-09-28 用户反馈「这个高度最高就 400 吗，现在高度不够，这个要可以调」：上限从 400 提到 1000。
/// 2026-09-29 用户明确「展开的高度最高是 850」：上限收到 **850**（同一句话里也确认了 850 够用，
/// 再高只是空白）。改这一个常量即可——设置页滑块的上界与运行时夹取同源
/// （`effectiveOpenNotchHeightUpperBound`），不存在「滑块能拖到而尺寸被夹掉」的错位。
let openNotchHeightRange: ClosedRange<CGFloat> = 120...850

/// 展开态高度相对**当前屏** `visibleFrame.height` 的占比上限：屏幕矮（外接小屏 / 缩放分辨率）时，
/// 850pt 的面板会超出可用高度，因此再按屏高收敛一道。
let openNotchHeightScreenRatio: CGFloat = 0.9

/// 展开态高度的**有效上界** = `min(850, 屏 visibleFrame.height * 0.9)`；取不到屏（nil / 非正值）时
/// 回落 `openNotchHeightRange.upperBound`（850）。
///
/// **设置页滑块的上界就是它**（同一口径）：滑块能拖到 800 而 `openNotchSize` 把它夹成 810 以下的
/// 某一个值，用户会看到「拖了没用」；两边同源才不会出现这种自相矛盾。
func effectiveOpenNotchHeightUpperBound(screenVisibleHeight: CGFloat?) -> CGFloat {
    guard let screenVisibleHeight, screenVisibleHeight > 0, screenVisibleHeight.isFinite else {
        return openNotchHeightRange.upperBound
    }
    // 极矮的屏（visibleFrame 小到 90% 低于可配下界）时至少保留下界，否则区间会反向。
    let screenLimit = max(openNotchHeightRange.lowerBound, screenVisibleHeight * openNotchHeightScreenRatio)
    return min(openNotchHeightRange.upperBound, screenLimit)
}

/// 展开态高度的夹取（纯函数）：下界 120 恒定；上界是「可配上限 850」与「屏高 90%」里更小的那个。
///
/// 改造前这里是写死的 `min(max(值, 120), 400)`——400 是「高度不可调」时代的遗留上界，
/// 用户反馈「高度不够」后改为按屏收敛（2026-09-28）；上限 1000 → 850 见 `openNotchHeightRange`。
func clampedOpenNotchHeight(_ stored: CGFloat, screenVisibleHeight: CGFloat?) -> CGFloat {
    let upper = effectiveOpenNotchHeightUpperBound(screenVisibleHeight: screenVisibleHeight)
    guard stored.isFinite else { return openNotchHeightRange.lowerBound }
    return min(max(stored, openNotchHeightRange.lowerBound), upper)
}

@MainActor
var openNotchSize: CGSize {
    let storedWidth = Defaults[.openNotchWidth]
    let minWidth = currentRecommendedMinimumNotchWidth()
    let maxWidth = maxAllowedNotchWidth()
    let width = min(max(storedWidth, minWidth, sideLyricsRequiredNotchWidth()), maxWidth)
    // 高度按「当前屏可见高度的 90%」收敛（取不到屏时回落 850，同 `clampedOpenNotchHeight`）。
    let height = clampedOpenNotchHeight(
        Defaults[.openNotchHeight],
        screenVisibleHeight: NSScreen.main?.visibleFrame.height
    )
    return .init(width: width, height: height)
}

/// Maximum notch width based on the current screen's point width.
/// Prevents the notch from extending beyond the screen on scaled displays.
func maxAllowedNotchWidth(for screenName: String? = nil) -> CGFloat {
    let screen: NSScreen?
    if let screenName {
        screen = NSScreen.screens.first { $0.localizedName == screenName }
    } else {
        screen = NSScreen.main
    }
    guard let screenWidth = screen?.frame.width, screenWidth > 0 else {
        return 900
    }
    return max(screenWidth - 60, 400)
}

/// Convenience for the main screen.
func maxAllowedNotchWidth() -> CGFloat {
    maxAllowedNotchWidth(for: nil)
}

// MARK: - Tab-Based Notch Width

/// Counts the number of currently enabled standard notch tabs.
/// Mirrors the tab-building logic in ``TabSelectionView``.
///
/// `@MainActor`：模块条数取自 `ModuleRegistry.shared.tabEntries`，注册表是主 actor 隔离的单例
/// （docs/13 接缝 S2 的连锁——本函数与它的调用链一并标主 actor，而不是复制一份非隔离快照）。
@MainActor
func enabledStandardTabCount() -> Int {
    var count = 0

    // Home tab
    if Defaults[.showStandardMediaControls] || Defaults[.showCalendar] || Defaults[.showMirror] {
        count += 1
    }

    // Shelf tab
    if Defaults[.dynamicShelf] {
        count += 1
    }

    // Timer tab：**不再在这里计数**（P2 接管批次 / T2 起）——上游那一条「功能开着 + 显示方式选 tab」
    // 的 `+1` 已删除，计时器的贡献由下方 `ModuleRegistry.shared.tabEntries` 代为承担
    // （`TimerModule` 的投影：启用真源 = 上游总开关、可见性 = 显示方式选 tab，一一对应）。
    // 三种组合下的贡献因此仍是 1 / 0 / 0（docs/20 §做法 机制五），刘海最小宽度不回归。

    // Stats tab
    if Defaults[.enableStatsFeature] {
        count += 1
    }

    // Notes / Clipboard tab
    if Defaults[.enableNotes] || (Defaults[.enableClipboardManager] && Defaults[.clipboardDisplayMode] == .separateTab) {
        count += 1
    }

    // Terminal tab
    if Defaults[.enableTerminalFeature] {
        count += 1
    }

    // Module kernel tabs（接缝 S2）：追加段的镜像 = `ModuleRegistry.tabEntries`（仅 active 且
    // `surfaces` 含 `.expanded`，已按 order 排好）。不同步这段，刘海最小宽度会比实际 tab 少算。
    count += ModuleRegistry.shared.tabEntries.count

    return count
}

/// Returns the recommended minimum notch width for the given tab count.
func recommendedMinimumNotchWidth(forTabCount count: Int) -> CGFloat {
    if count >= 6 { return 770 }
    if count >= 5 { return 690 }
    return 640
}

/// Returns the recommended minimum notch width for the current tab configuration.
@MainActor
func currentRecommendedMinimumNotchWidth() -> CGFloat {
    recommendedMinimumNotchWidth(forTabCount: enabledStandardTabCount())
}

/// Enforces the minimum notch width based on current tab count.
/// Also clamps to screen width so the notch never exceeds the display.
/// Only adjusts when not in minimalistic mode.
@MainActor
func enforceMinimumNotchWidth() {
    guard !Defaults[.enableMinimalisticUI] else { return }
    let minWidth = currentRecommendedMinimumNotchWidth()
    let maxWidth = maxAllowedNotchWidth()
    var width = Defaults[.openNotchWidth]
    if width < minWidth { width = minWidth }
    if width > maxWidth { width = maxWidth }
    if Defaults[.openNotchWidth] != width {
        Defaults[.openNotchWidth] = width
    }
}
private let minimalisticBaseOpenNotchSize: CGSize = .init(width: 420, height: 180)
private let minimalisticLyricsExtraHeight: CGFloat = 40
let minimalisticTimerCountdownTopPadding: CGFloat = 12
let minimalisticTimerCountdownContentHeight: CGFloat = 82
let minimalisticTimerCountdownBlockHeight: CGFloat = minimalisticTimerCountdownTopPadding + minimalisticTimerCountdownContentHeight
let statsSecondRowContentHeight: CGFloat = 120
let statsGridSpacingHeight: CGFloat = 12
let notchShadowPaddingStandard: CGFloat = 18
let notchShadowPaddingMinimalistic: CGFloat = 12

@MainActor
func minimalisticOpenNotchSize(isDynamicIslandMode: Bool) -> CGSize {
    var size = minimalisticBaseOpenNotchSize

    if isDynamicIslandMode {
        size.width = 340 // Reduced from 420 for a narrower pill
        size.height = 144 // Exact height of the minimalistic music player view
    }

    if Defaults[.enableLyrics] {
        size.height += minimalisticLyricsExtraHeight
    }
    
    let reminderCount = ReminderLiveActivityManager.shared.activeWindowReminders.count
    if reminderCount > 0 {
        let reminderHeight = ReminderLiveActivityManager.additionalHeight(forRowCount: reminderCount)
        size.height += reminderHeight
    }

    if DynamicIslandViewCoordinator.shared.timerLiveActivityEnabled && TimerManager.shared.isExternalTimerActive {
        size.height += minimalisticTimerCountdownBlockHeight
    }

    return size
}
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 19, bottom: 24), closed: (top: 6, bottom: 14))
let minimalisticCornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 35, bottom: 35), closed: cornerRadiusInsets.closed)

// MARK: - Terminal tab clip (notch surface)

/// Padding on the terminal block inside the notch. Inner corner radius = outer shell radius on that edge, minus the matching edge padding.
let notchTerminalContentEdgePadding: (top: CGFloat, horizontal: CGFloat, bottom: CGFloat) = (4, 8, 8)

/// Inner margin (all edges) between the SwiftTerm view's glyphs and the terminal block edge.
/// Applied to the LocalProcessTerminalView frame only; the frosted blur underlay stays full-bleed.
let notchTerminalInnerTextInset: CGFloat = 6

/// Bottom radii for the shell (outer) and the terminal ``clipShape`` (inner), per design: inner = outer shell bottom radius − `notchTerminalContentEdgePadding.bottom`.
func notchTerminalBottomCornerRadii(
    isDynamicIslandMode: Bool,
    notchState: NotchState,
    cornerRadiusScaling: Bool,
    enableMinimalisticUI: Bool,
    closedNotchHeight: CGFloat
) -> (outerBottom: CGFloat, innerBottom: CGFloat) {
    let p = notchTerminalContentEdgePadding.bottom
    if isDynamicIslandMode {
        let outer: CGFloat
        if notchState == .open {
            outer = enableMinimalisticUI
                ? minimalisticCornerRadiusInsets.opened.top
                : dynamicIslandPillCornerRadiusInsets.opened
        } else {
            outer = max(closedNotchHeight / 2, dynamicIslandPillCornerRadiusInsets.closed.standard)
        }
        return (outer, max(0, outer - p))
    }
    let active: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = {
        if enableMinimalisticUI {
            return (opened: minimalisticCornerRadiusInsets.opened, closed: cornerRadiusInsets.closed)
        }
        return cornerRadiusInsets
    }()
    let outerBottom: CGFloat
    if notchState == .open && cornerRadiusScaling {
        outerBottom = active.opened.bottom
    } else {
        outerBottom = active.closed.bottom
    }
    return (outerBottom, max(0, outerBottom - p))
}

// MARK: - 滚动边缘渐隐遮罩的显示判据

/// 滚动容器的**上下边缘渐隐遮罩**是否显示。
///
/// 这两条遮罩是为**纯黑面板**做的：`Color.black.opacity(0.65) → .clear` 的 16pt 渐变压在内容上下两端，
/// 让滚动内容在黑底上"淡出"而不是被硬生生切断。面板底一旦切成玻璃档，同一层黑色渐变就从"保护性淡出"
/// 变成**两条突兀的黑带**（用户 2026-09-28 反馈，截图是笔记 tab 且面板已切液态玻璃）。
///
/// 因此判据只有一条：**只有纯黑档显示遮罩**；玻璃两档一律不显示。
/// 刻意**不**把遮罩改成玻璃材质——那会在内容与背景之间再引入一层新的对比问题（面板文字一律显式白色，
/// 任何半透明层都要重算对比度），而"不显示"在任何背景样式下都是安全的。
///
/// 消费点（仅这两处，见用户反馈的约束"只改这两个视图"）：
/// `NoteListView`（笔记 tab 的滚动网格）与 `NotchTimerView.presetColumn`（计时器预设列表）。
func shouldShowScrollFadeMask(panelBackgroundStyle: NotchPanelBackgroundStyle) -> Bool {
    panelBackgroundStyle == .solidBlack
}

func statsAdjustedNotchSize(
    from baseSize: CGSize,
    isStatsTabActive: Bool,
    secondRowProgress: CGFloat
) -> CGSize {
    guard isStatsTabActive, Defaults[.enableStatsFeature] else {
        return baseSize
    }

    let enabledGraphsCount = [
        Defaults[.showCpuGraph],
        Defaults[.showMemoryGraph],
        Defaults[.showGpuGraph],
        Defaults[.showNetworkGraph],
        Defaults[.showDiskGraph]
    ].filter { $0 }.count

    guard enabledGraphsCount >= 4 else {
        return baseSize
    }

    let clampedProgress = max(0, min(secondRowProgress, 1))
    guard clampedProgress > 0 else {
        return baseSize
    }

    var adjustedSize = baseSize
    let extraHeight = (statsSecondRowContentHeight + statsGridSpacingHeight) * clampedProgress
    adjustedSize.height += extraHeight
    return adjustedSize
}

func notchShadowPaddingValue(isMinimalistic: Bool) -> CGFloat {
    isMinimalistic ? notchShadowPaddingMinimalistic : notchShadowPaddingStandard
}

func addShadowPadding(to size: CGSize, isMinimalistic: Bool) -> CGSize {
    CGSize(width: size.width, height: size.height + notchShadowPaddingValue(isMinimalistic: isMinimalistic))
}

/// Determines whether a specific screen should render the Dynamic Island pill
/// shape instead of the standard notch shape.
///
/// Returns `true` only when ALL of these conditions are met:
/// 1. The user has selected `.dynamicIsland` in `externalDisplayStyle`
/// 2. The screen does NOT have a physical notch (safeAreaInsets.top == 0)
///
/// Screens with a physical notch always use the standard notch shape.
func shouldUseDynamicIslandMode(for screenName: String?) -> Bool {
    guard Defaults[.externalDisplayStyle] == .dynamicIsland else {
        return false
    }

    var selectedScreen: NSScreen? = NSScreen.main
    if let screenName {
        selectedScreen = NSScreen.screens.first(where: { $0.localizedName == screenName })
    }

    guard let screen = selectedScreen else {
        // No screen found — fallback to standard notch
        return false
    }

    // Physical notch screens always use standard notch shape
    return screen.safeAreaInsets.top <= 0
}

/// Corner radius insets for the Dynamic Island pill shape.
/// - closed: half the closed notch height for a true capsule look
/// - opened: generous radius for smooth expanded pill
let dynamicIslandPillCornerRadiusInsets: (opened: CGFloat, closed: (standard: CGFloat, minimalistic: CGFloat)) = (
    opened: 24,
    closed: (standard: 16, minimalistic: 16)
)

/// Extra window height past `screen.maxY` on physical-notch displays.
let notchTopScreenBleedAmount: CGFloat = 4

func notchTopScreenBleed(for screenName: String?) -> CGFloat {
    shouldUseDynamicIslandMode(for: screenName) ? 0 : notchTopScreenBleedAmount
}

/// Vertical offset from the top screen edge for the Dynamic Island pill.
/// Creates a visual gap so the pill floats below the menu bar, mimicking
/// the iPhone's Dynamic Island detachment from the physical screen edge.
let dynamicIslandTopOffset: CGFloat = 6

/// Extra horizontal padding applied OUTSIDE the pill clip shape in Dynamic
/// Island mode so the drop shadow has room to render without being clipped
/// by the outer frame constraint.
let dynamicIslandShadowInset: CGFloat = 14

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 13.0, closed: 4.0)
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
}

func getScreenFrame(_ screen: String? = nil) -> CGRect? {
    var selectedScreen = NSScreen.main

    if let customScreen = screen {
        selectedScreen = NSScreen.screens.first(where: { $0.localizedName == customScreen })
    }
    
    if let screen = selectedScreen {
        return screen.frame
    }
    
    return nil
}

func getClosedNotchSize(screen: String? = nil) -> CGSize {
    // Default notch size, to avoid using optionals
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = Defaults[.closedNotchWidth]

    var selectedScreen = NSScreen.main

    if let customScreen = screen {
        selectedScreen = NSScreen.screens.first(where: { $0.localizedName == customScreen })
    }

    // Check if the screen is available
    if let screen = selectedScreen {
        // Calculate and set the exact width of the notch
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
            
            if Defaults[.customizePhysicalNotchWidth] {
                notchWidth = Defaults[.closedNotchWidth]
            }
        }

        // Check if the Mac has a notch
        if screen.safeAreaInsets.top > 0 {
            // This is a display WITH a notch - use notch height settings
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        } else {
            // This is a display WITHOUT a notch - use non-notch height settings
            notchHeight = Defaults[.nonNotchHeight]
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}
