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
//  LyricsOverlayRules.swift
//  Gourd 音乐 · 桌面歌词悬浮层的判据与渲染映射（p10 悬浮层批次 / T2）
//
//  歌词自 docs/35-desktop-lyrics-overlay.md 起不再画在灵动岛面板里，而是由 Gourd 自绘一层
//  桌面悬浮窗（只在**岛不展开**时出现）。本文件是那一层的**全部判断**——显隐判据、行表映射、
//  高亮下标、行窗口、颜色解析——五个纯函数（签名逐字照 docs/35 §接口与数据形状）。
//
//  **为什么都是纯函数**：窗口（`LyricsOverlayWindowManager`）、视图（`LyricsOverlayView`）与
//  设置页（T4）只做「读键 → 调这里 → 画」，判断一条都不进视图的私有属性，于是全部能被
//  `DynamicIslandTests/HomeStripLayoutTests.swift` 末尾的 `LyricsOverlayRulesTests` 钉住，
//  不需要跑起 App（与 `HomeStripLayoutMath` / `HomeVerticalFit` 同一条纪律）。
//
//  **数据链**（零新增抓取，docs/35 §做法 机制一）：只读 `MusicManager` 既有的
//  `syncedLyrics` / `currentLyricIndex`（LRCLIB 单源；逐行由既有的 300ms `lyricSyncTask` 推进）。
//  `hasRealLyrics` 由消费方喂 `!syncedLyrics.isEmpty`——「Loading lyrics...」/「No lyrics found」
//  两种占位态都伴随空数组，所以这里不去比占位串。
//
//  **plain（无时间轴）歌词**：LRCLIB 只有 `plainLyrics` 时既有链路产出**单条
//  `LyricLine(timestamp: 0, text: 整段文本)`**（`MusicManager.fetchLyricsFromAPI` 的 plain 分支），
//  不拆行会糊成一团。「`count == 1 && timestamp == 0`」这个形状就是本文件的 plain 判据
//  （D-08：拆行 + 静态显示，不高亮、不滚动——「plain 不高亮」由 `highlightIndex` 承载）。
//

import AppKit
import Foundation
import SwiftUI

enum LyricsOverlayRules {

    // MARK: - 显隐（D-07）

    /// 悬浮层显隐的**唯一**判据：总开关 && 有活跃音乐会话 && 拿到真实歌词行 && 岛不展开 && 屏幕未锁。
    ///
    /// 五个输入之外没有隐含通道：**不跟 `hideOnClosed`**（全屏 app 上仍显示是桌面歌词的常见用法）、
    /// 不读占位串（见文件头）。锁屏归锁屏媒体面板自己那一行（D-04）。
    static func shouldShow(
        enableLyrics: Bool,
        hasActiveSession: Bool,
        hasRealLyrics: Bool,
        islandClosed: Bool,
        screenLocked: Bool
    ) -> Bool {
        enableLyrics && hasActiveSession && hasRealLyrics && islandClosed && !screenLocked
    }

    // MARK: - 行表（plain 拆行 / 时间轴原样）

    /// 把既有链路的歌词行映射成「屏幕上要画的行」。
    ///
    /// - **plain**（`count == 1 && timestamp == 0`，见文件头）：按换行拆行、逐行 trim、丢空行，
    ///   返回 `isSynced == false`（消费方据此静态显示：不高亮、不滚动，见 D-08）。
    ///   拆行用 `CharacterSet.newlines`——`\r\n`（CRLF）与单独 `\r` 都不会把符号留在行尾。
    /// - **时间轴**（其余非空情形）：原样返回非空行（顺序、文本不动），`isSynced == true`。
    ///   `index` **沿用输入数组下标**（与 `MusicManager.currentLyricIndex` 同一坐标系，
    ///   `visibleWindow` 直接拿它找当前行）；`parseLRC` 不产空行，所以真实数据里下标连续
    ///   0…n−1——丢空行是防御，真丢了也只是下标出现间隙，`visibleWindow` 按行表找，不受影响。
    /// - **空数组**：空行表、`isSynced == true`（没有「plain」这回事；`hasRealLyrics` 由消费方判）。
    static func displayLines(synced: [LyricLine]) -> (lines: [(index: Int, text: String)], isSynced: Bool) {
        guard !synced.isEmpty else { return ([], true) }

        if synced.count == 1, let only = synced.first, only.timestamp == 0 {
            let texts = only.text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return (texts.enumerated().map { (index: $0.offset, text: $0.element) }, false)
        }

        let lines: [(index: Int, text: String)] = synced.enumerated()
            .map { (index: $0.offset, text: $0.element.text) }
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return (lines, true)
    }

    // MARK: - 高亮当前行（D-08）

    /// 当前行（要加粗提亮的那一行）在**输入坐标**里的下标；`nil` = 不高亮。
    ///
    /// 「plain 不高亮」由它承载，不给视图留判断：`isSynced == false`（无时间轴，静态显示）
    /// 或 `currentIndex < 0`（还没轮到第一行）一律 `nil`。0 号行是合法输入（首行也该高亮）。
    static func highlightIndex(isSynced: Bool, currentIndex: Int) -> Int? {
        guard isSynced, currentIndex >= 0 else { return nil }
        return currentIndex
    }

    // MARK: - 行窗口（当前行居中）

    /// 行窗口：以当前行居中，返回长度恒为 `lineCount` 的行窗口；越界（含行数不足）的槽位为
    /// `nil`（画空，不补行）。
    ///
    /// `currentIndex` 用的是 `lines[i].index` 坐标（与 `highlightIndex` 同源）；找不到匹配行时
    /// 按「当前行 = 第一行」处理。窗口位置 = `[p − before, p + after]`，其中 `p` 是匹配行在
    /// `lines` 里的**位置**（`lines.firstIndex { $0.index == currentIndex } ?? 0`）、
    /// `before = (lineCount − 1) / 2`、`after = lineCount − 1 − before`——合法档 1 / 3 / 5 都
    /// 居中，算式对偶数也定义良好（给将来加档留口）。`lines` 为空 → 全 `nil`、长度 `lineCount`。
    ///
    /// **返回的是行窗口本身**（`(index, text)` 或 `nil`），不是下标：坐标契约因此编进类型——
    /// `displayLines` 的时间轴档会丢空行但保留下标间隙，消费方只管画 `window`，不需要再判
    /// 「`total` 该传 `lines.count` 还是 `synced.count`」。
    static func visibleWindow(
        lineCount: Int,
        currentIndex: Int,
        lines: [(index: Int, text: String)]
    ) -> [(index: Int, text: String)?] {
        guard lineCount > 0 else { return [] }
        let before = (lineCount - 1) / 2
        let after = lineCount - 1 - before
        let center = lines.firstIndex { $0.index == currentIndex } ?? 0
        let start = center - before
        let end = center + after
        return (start...end).map { position in
            lines.indices.contains(position) ? lines[position] : nil
        }
    }

    // MARK: - 颜色（三档）

    /// 按档解析歌词颜色（docs/35 §做法 机制一「颜色按档解析（跟封面取色 / 白 / 自定义）」）。
    ///
    /// - `.albumArt`：封面平均色经 `ensureMinimumBrightness(factor: 0.6)`（`Color` 扩展，
    ///   与既有封面取色同款下限——深色封面上的字也读得清）；`albumArt == nil` 回落白。
    /// - `.white`：纯白。
    /// - `.custom`：解析 `#RRGGBB`（`#` 可省、大小写皆可；**校验严格 6 位十六进制字符**，
    ///   所以 `"+12345"` 这类 `UInt32(_:radix:)` 会收下的串不算数）；非法串（长度不对 /
    ///   非十六进制）回落白——不崩、不吞行（`lyricsCustomColorHex` 是用户可见的自由输入框）。
    static func resolvedColor(mode: LyricsColorMode, hex: String, albumArt: NSColor?) -> Color {
        switch mode {
        case .albumArt:
            guard let albumArt = albumArt else { return .white }
            return Color(nsColor: albumArt).ensureMinimumBrightness(factor: 0.6)

        case .white:
            return .white

        case .custom:
            let raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            let digits = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
            guard digits.count == 6, digits.allSatisfy(\.isHexDigit),
                  let rgb = UInt32(digits, radix: 16) else { return .white }
            return Color(
                red: Double((rgb >> 16) & 0xFF) / 255,
                green: Double((rgb >> 8) & 0xFF) / 255,
                blue: Double(rgb & 0xFF) / 255
            )
        }
    }
}
