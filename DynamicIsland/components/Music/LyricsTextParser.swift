// Modified for Gourd (2026-10-16)
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
//  LyricsTextParser.swift
//  Gourd 音乐 · LRC 时间轴解析（2026-10-16 / docs/50 D-15）
//
//  从 `MusicManager.parseLRC`（上游）提出来变成纯函数，理由有两条：
//  1. **当时它有个真错**：正则写作 `\[(\d{1,2}):(\d{2})(?:\.(\d{1,2}))?\]`——只认 1～2 位小数，
//     而真实词条里 **3 位毫秒**极常见（LX Music 本地缓存里就是 `[00:06.100]芭蕉雨夜的蝉声`）。
//     结果是**整行被跳过**：2026-10-16 实测，一首 27 行的歌词只解出 5 行（恰好是那 5 行的时间轴
//     写成 1～2 位），屏幕上就少了 22 行。小数位因此改成 1～3 位、按位数换算（`.1` = 100ms、
//     `.10` = 10ms、`.100` = 1ms）；
//  2. 解析器要能被单测钉住——数据链上游（LRCLIB 与 LX Music 本地缓存）都会喂它，格式差异只有
//     用例能挡。
//
//  **改动点小结**（相对上游那份 `MusicManager.parseLRC`）：
//  1. 小数位 1～3 位（原来只认 1～2 位）；
//  2. 一行里的多个**行首**时间轴标签全吃掉、每个时间点各出一条歌词行（原来只认第一个、且把后面的
//     标签留在文本里——`[00:01.00][00:31.00]同一句` 会显示成 `[00:31.00]同一句`）。
//
//  **保留的上游口径**：时间轴之外的空行 / 无时间轴的行不进结果（纯文本歌词由调用方按「整段 plain」
//  处理，见 `LyricsOverlayRules.displayLines` 的 plain 判据）。
//

import Foundation

enum LyricsTextParser {

    /// 行首的一个时间轴标签：`[m:ss]` / `[mm:ss]` / `[mm:ss.x]` / `[mm:ss.xx]` / `[mm:ss.xxx]`，
    /// 小数分隔符 `.` 与 `:` 都收（社区里 `[00:12:34]` 这种写法存在）。分钟数允许 1～3 位。
    private static let tagPattern = "\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?\\]"

    /// LRC 文本 → 按时间排序的歌词行。
    static func parseLRC(_ lrc: String) -> [LyricLine] {
        guard let tagRegex = try? NSRegularExpression(pattern: tagPattern, options: []) else { return [] }

        var lyrics: [LyricLine] = []
        for line in lrc.components(separatedBy: .newlines) {
            let nsLine = line as NSString
            var index = 0
            var timestamps: [TimeInterval] = []

            // 反复吃**行首**的标签：一行多标签 = 同一句在多个时间点出现（副歌常用写法）。
            while index < nsLine.length,
                  let match = tagRegex.firstMatch(
                      in: line,
                      options: [.anchored],
                      range: NSRange(location: index, length: nsLine.length - index)
                  ) {
                let minutes = Double(substring(nsLine, match.range(at: 1))) ?? 0
                let seconds = Double(substring(nsLine, match.range(at: 2))) ?? 0
                let fraction = fractionSeconds(substring(nsLine, match.range(at: 3)))
                timestamps.append(minutes * 60 + seconds + fraction)
                index = match.range.location + match.range.length
            }

            guard !timestamps.isEmpty else { continue }
            let text = nsLine.substring(from: index).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            for timestamp in timestamps {
                lyrics.append(LyricLine(timestamp: timestamp, text: text))
            }
        }

        return lyrics.sorted(by: { $0.timestamp < $1.timestamp })
    }

    /// 小数部分 → 秒：**按位数**换算（`"1"` = 0.1s、`"10"` = 0.10s、`"100"` = 0.100s）。
    static func fractionSeconds(_ text: String) -> TimeInterval {
        let digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !digits.isEmpty, let value = Double(digits) else { return 0 }
        return value / pow(10, Double(digits.count))
    }

    private static func substring(_ line: NSString, _ range: NSRange) -> String {
        range.location == NSNotFound ? "" : line.substring(with: range)
    }
}
