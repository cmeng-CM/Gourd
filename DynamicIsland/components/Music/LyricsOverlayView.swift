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
//  LyricsOverlayView.swift
//  Gourd 音乐 · 桌面歌词悬浮层的**渲染 + 交互**（p10 悬浮层批次 / T3）
//
//  歌词自 docs/35-desktop-lyrics-overlay.md 起不再画在灵动岛面板里，而是由 Gourd 自绘一层
//  桌面悬浮窗（只在**岛不展开**时出现）。本文件是那一层的全部「画什么」与鼠标交互：
//  行窗口渲染（字体 / 加粗 / 颜色 / 不透明度）、右键菜单三项、未锁定档的拖拽手势。
//
//  **收参数、不读单例**（docs/35 §做法 机制一）：本视图不碰 `Defaults` / `MusicManager` /
//  `DynamicIslandViewModel`——行表、显示档、颜色源与三个菜单动作都以参数传入，由
//  `LyricsOverlayWindowManager.sync()` 读键装配。于是渲染能被 `ImageRenderer` 独立驱动
//  （取证用例 `LyricsOverlayViewRenderTests`），显隐与位置判断一条都不进视图。
//
//  **渲染由规则决定**：行窗口 = `LyricsOverlayRules.visibleWindow`（当前行居中、越界留空），
//  颜色 = `LyricsOverlayRules.resolvedColor`（跟封面 / 白 / 自定义），两者由入参喂进来的
//  `lines` / `highlightIndex` 直接驱动——视图不读键、不比占位串、不做「要不要高亮」的判断。
//
//  **两个入参分工**：`highlightIndex`（`LyricsOverlayRules.highlightIndex` 的输出）是**行窗口的
//  居中锚**，同时也是「哪一行是当前行」；`emphasizeCurrent`（`lyricsHighlightCurrent` 键）只决定
//  **要不要强调**。分成两个是因为「高亮当前行」关掉时不能连行窗口一起冻住（那会永远停在第一行）；
//  plain 歌词的「不高亮」则由 rules 的 `highlightIndex == nil` 承载（D-08），与开关无关。
//  `nil` = 没有当前行（plain / 还没轮到第一句）→ 窗口按第一行居中。
//
//  **「提亮」的实现**：当前行满不透明度 + 加粗，其余行按同一颜色压到 `dimmedAlpha`——
//  同一颜色上的相对提亮，白档 / 自定义档 / 跟封面档天然同款，不需要逐档另算亮色。
//  强调关掉 = 整层 `dimmedAlpha` 之上的原色原字重（同色同字重，见 `Defaults.Keys.lyricsHighlightCurrent`）。
//

import AppKit
import SwiftUI

struct LyricsOverlayView: View {
    /// 行表（`LyricsOverlayRules.displayLines` 的输出）：`index` 与 `highlightIndex` 同坐标。
    let lines: [(index: Int, text: String)]
    /// 是否有时间轴（`displayLines` 的第二返回值）。plain 档静态显示、不滚动——行切换动画只在
    /// 时间轴档启用；不做任何几何判断。
    let isSynced: Bool
    /// 当前行（`LyricsOverlayRules.highlightIndex` 的输出；`nil` = 没有「当前行」，行窗口按第一行居中）。
    /// 它同时是行窗口的**居中锚**——高亮档关掉只影响 `emphasizeCurrent`，不影响这里传什么。
    let highlightIndex: Int?
    /// 「高亮当前行」档（`lyricsHighlightCurrent`）。false = 整层同色同字重；true = 当前行加粗提亮、
    /// 其余行压暗。与 `highlightIndex` 分开是因为**关闭高亮不能冻住行窗口**（那会永远停在第一行）。
    let emphasizeCurrent: Bool
    let fontSize: CGFloat
    let lineCount: Int
    let opacity: Double
    let colorMode: LyricsColorMode
    let customHex: String
    let albumArtColor: NSColor?
    /// 锁定位置档：true = 窗口鼠标穿透（由 manager 置 `ignoresMouseEvents`），拖拽手势在这里关掉。
    let locked: Bool

    /// 右键菜单三项：锁定 / 重置位置 / 关闭歌词（写 `enableLyrics = false`）。
    let onToggleLock: () -> Void
    let onResetPosition: () -> Void
    let onCloseLyrics: () -> Void
    /// 未锁定档的拖拽：`translation` 是 SwiftUI 坐标系（y 向下）的位移；结束时报一次落点。
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: (CGSize) -> Void

    /// 非当前行的压暗系数（「提亮」的另一半，见文件头）。
    private static let dimmedAlpha: Double = 0.72
    /// 单行歌词的窗口上限：再长的行截尾，不把窗口撑到屏外。
    private static let maximumWidth: CGFloat = 860
    /// 行高 = 字号 × 该系数：保证三档行数（1 / 3 / 5）的窗口高度逐档不同、行间留白不贴死。
    private static let rowHeightFactor: CGFloat = 1.4

    private var rowHeight: CGFloat { (fontSize * Self.rowHeightFactor).rounded() }

    var body: some View {
        content
            .opacity(opacity)
            // 行切换淡入淡出（D-09 的短 easeInOut）；plain 档位置不动，不给动画。
            .animation(isSynced ? .easeInOut(duration: 0.2) : nil, value: highlightIndex)
            .contextMenu { menuItems }
            .gesture(dragGesture, including: locked ? .none : .all)
    }

    // MARK: - 渲染

    private var content: some View {
        let window = LyricsOverlayRules.visibleWindow(
            lineCount: lineCount,
            currentIndex: highlightIndex ?? 0,
            lines: lines
        )

        return VStack(alignment: .center, spacing: 0) {
            ForEach(Array(window.enumerated()), id: \.offset) { _, slot in
                row(for: slot)
            }
        }
    }

    /// 一行歌词（或空槽位——越界与行数不足处画空，不补行，行高照留）。
    ///
    /// 宽度上限挂在**行**上而不是外层：`NSHostingView.fittingSize` 量的是理想宽度
    /// （最长一行的固有宽、封顶 `maximumWidth`），越长的行在真实布局里被截尾。
    @ViewBuilder
    private func row(for slot: (index: Int, text: String)?) -> some View {
        if let slot {
            Text(slot.text)
                .font(.system(size: fontSize, weight: isEmphasized(slot) ? .bold : .regular))
                .foregroundStyle(textColor(for: slot))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: Self.maximumWidth)
                .frame(height: rowHeight)
        } else {
            Color.clear.frame(width: 0, height: rowHeight)
        }
    }

    /// 当前行满不透明度、其余行压暗；高亮档关掉（或没有当前行）时整层同色（见文件头）。
    private func textColor(for slot: (index: Int, text: String)) -> Color {
        let base = LyricsOverlayRules.resolvedColor(mode: colorMode, hex: customHex, albumArt: albumArtColor)
        guard emphasizeCurrent, let highlightIndex else { return base }
        return slot.index == highlightIndex ? base : base.opacity(Self.dimmedAlpha)
    }

    /// 加粗那一行：高亮档开着、且这一行就是当前行。
    private func isEmphasized(_ slot: (index: Int, text: String)) -> Bool {
        emphasizeCurrent && slot.index == highlightIndex
    }

    // MARK: - 右键菜单（三项）

    @ViewBuilder
    private var menuItems: some View {
        Button(locked ? "Unlock position" : "Lock position") { onToggleLock() }
        Button("Reset position") { onResetPosition() }
        Divider()
        Button("Turn Off Lyrics") { onCloseLyrics() }
    }

    // MARK: - 拖拽（未锁定档）

    /// 全局坐标系（y 向下）：窗口跟着手势移动时局部坐标会自反馈抖动，所以用 `.global`。
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { onDragChanged($0.translation) }
            .onEnded { onDragEnded($0.translation) }
    }
}

// MARK: - 预览

#if DEBUG
struct LyricsOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        LyricsOverlayView(
            lines: (0..<5).map { (index: $0, text: "第 \($0 + 1) 行歌词 · preview") },
            isSynced: true,
            highlightIndex: 2,
            emphasizeCurrent: true,
            fontSize: 18,
            lineCount: 3,
            opacity: 0.9,
            colorMode: .white,
            customHex: "#FFFFFF",
            albumArtColor: nil,
            locked: false,
            onToggleLock: {},
            onResetPosition: {},
            onCloseLyrics: {},
            onDragChanged: { _ in },
            onDragEnded: { _ in }
        )
        .padding(24)
        .background(Color.black)
    }
}
#endif
