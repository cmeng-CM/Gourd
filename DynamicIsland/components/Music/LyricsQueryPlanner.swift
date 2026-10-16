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
//  LyricsQueryPlanner.swift
//  Gourd 音乐 · 取词的**查询计划**与**失败分类**（2026-10-16 / docs/50）
//
//  为什么会多出这一层：用户 2026-10-16 报「歌词的标志不管用，打开也不显示歌词」。查证结论是
//  两条**取词侧**的毛病（`MusicManager` 原来的单次查询没有兜底）：
//
//  1. **一次查不到就永久没有**：LRCLIB 只按 `(track_name, artist_name)` 过滤，而播放器报上来的
//     歌名/歌手串常常带「版本标注」与「别名」——实测：「慕夏」的歌手是 `邓寓君(等什么君)`，LRCLIB
//     里存的却是 `等什么君`（同样的歌，改一个字面量就查不到）；「我也可以是流浪诗人」的歌手报成
//     `好妹妹乐队`，词库里是 `好妹妹`。
//  2. **瞬时故障被当成「词库没有这条」**：LRCLIB 会回 `503 ServerOverloaded`（本机实测 30 次
//     查询里 8 次），原来的实现把非 200 一律 `return []`，与「确实没有」不可区分——于是 503 的
//     结果被写进缓存，之后**连点歌词按钮也不会再去问**（缓存命中直接放回空数组）。
//
//  本文件只做两件纯事（不碰网络、不读键、不知道调用方是谁）：
//  - `LyricsQueryPlanner`：把 `(title, artist)` 展开成**有序、去重、有上限**的候选查询，
//    并给出**变体结果的接受闸**（变体只许拿同名曲 + 相关歌手）；
//  - `LyricsFetchPolicy`：HTTP 状态码 → 「正常 / 瞬时故障（值得重试）/ 确定性失败」，以及重试间隔。
//
//  **原样那条查询的匹配口径一字未改**（仍走 `MusicManager.bestLyricsMatch` 的打分取最高分）——
//  本次只**增加**兜底查询，不改既有命中行为；变体才过 `accepts` 那道闸。
//

import Foundation

// MARK: - 查询计划

enum LyricsQueryPlanner {

    /// 一次取词里的一条候选查询。
    ///
    /// `isExact` = 「原样那条」（歌名与歌手都是播放器报上来的原值）。它**恒在第一位**且**唯一**：
    /// 它沿用既有的打分匹配（行为零变化）；其余变体必须过 `accepts(...)`。
    struct Query: Equatable {
        let title: String
        let artist: String
        let isExact: Bool
    }

    /// 一次取词最多问几条查询（**含**原样那条）。
    ///
    /// 依据：本机实测的歌手串变体最多也就 2～3 条（别名 1 条 + 去后缀 1 条 + 拆多歌手 1 条），
    /// 4 条足以覆盖；再往上加只会让「词库里确实没有」的歌多打几次网络请求（LRCLIB 是公共免费
    /// 服务，本机实测已经有 503，不该把重试当默认策略）。
    static let maximumQueryCount = 4

    /// 候选查询阶梯：**原样 → 歌手变体 → 歌名变体**。
    ///
    /// 顺序有依据：中文歌的查不到更多来自**歌手串**（别名/多歌手/乐队后缀，实测「慕夏」「我也可以
    /// 是流浪诗人」都是这一类），版本标注（歌名那侧）次之，所以歌手变体排在歌名变体前面——
    /// 上限 `maximumQueryCount` 截断时，先被砍掉的是收益更低的那一类。
    static func variants(title: String, artist: String) -> [Query] {
        let baseTitle = normalizedSpacing(title)
        let baseArtist = normalizedSpacing(artist)
        guard !baseTitle.isEmpty, !baseArtist.isEmpty else { return [] }

        var queries: [Query] = []
        var seen = Set<String>()

        func append(title: String, artist: String, isExact: Bool) {
            let title = normalizedSpacing(title)
            let artist = normalizedSpacing(artist)
            guard !title.isEmpty, !artist.isEmpty else { return }
            guard queries.count < maximumQueryCount else { return }
            let key = normalizedKey(title) + "\u{1}" + normalizedKey(artist)
            guard seen.insert(key).inserted else { return }
            queries.append(Query(title: title, artist: artist, isExact: isExact))
        }

        append(title: baseTitle, artist: baseArtist, isExact: true)

        let artists = artistVariants(baseArtist)
        let titles = titleVariants(baseTitle)

        for variant in artists { append(title: baseTitle, artist: variant, isExact: false) }
        for variant in titles { append(title: variant, artist: baseArtist, isExact: false) }
        // 交叉只在还有余量时才补（两条都带毛病的歌很少，但真遇上就不必拆成两轮取词）
        for variant in titles {
            for artistVariant in artists {
                append(title: variant, artist: artistVariant, isExact: false)
            }
        }

        return queries
    }

    // MARK: 变体结果的接受闸

    /// **变体**查询的结果能不能用。
    ///
    /// 两道闸，缺一不可：
    /// 1. **同名**（`normalizedKey` 相等，不是包含）：变体查询会放松歌手串，若不钉住歌名就会
    ///    拿回别人的同名曲——实测「可乐」在 LRCLIB 里有 `半吨兄弟` 的版本，而 `赵紫骅` 的那首
    ///    **词库里根本没有**；放行就等于给他看别人的歌词。
    /// 2. **相关歌手**（归一化后互相包含）：挡掉「搜别名却拿回另一个团体」这种。
    ///
    /// **原样那条不走这里**（`isExact` → 真）：它沿用既有打分匹配，行为与改动前逐字一致。
    static func accepts(resultTitle: String, resultArtist: String, query: Query) -> Bool {
        guard !query.isExact else { return true }
        let resultTitleKey = normalizedKey(resultTitle)
        let queryTitleKey = normalizedKey(query.title)
        guard !resultTitleKey.isEmpty, resultTitleKey == queryTitleKey else { return false }

        let resultArtistKey = normalizedKey(resultArtist)
        let queryArtistKey = normalizedKey(query.artist)
        guard !resultArtistKey.isEmpty, !queryArtistKey.isEmpty else { return false }
        return resultArtistKey.contains(queryArtistKey) || queryArtistKey.contains(resultArtistKey)
    }

    // MARK: 归一化

    /// 比较用的**归一化 key**：小写、全角 ASCII → 半角、**只留字母与数字**（标点、空白、
    /// `、&／,` 一类分隔符全部丢掉）。
    ///
    /// 两个真实例子（本机实测）：
    /// - `许嵩、何曼婷`（播放器报的）与 `许嵩&何曼婷`（LRCLIB 存的）→ 都是 `许嵩何曼婷`；
    /// - `樱花(现场吉他版）` 里开括号是半角、闭括号是全角（上游输入就这样）——所以**不能**按
    ///   「左右括号成对」去匹配，只能按字符集丢。
    static func normalizedKey(_ value: String) -> String {
        var output = ""
        for scalar in value.lowercased().unicodeScalars {
            var code = scalar.value
            if code == 0x3000 { code = 0x20 }                       // 全角空格
            else if (0xFF01...0xFF5E).contains(code) { code -= 0xFEE0 }  // 全角 ASCII
            guard let mapped = Unicode.Scalar(code) else { continue }
            let character = Character(mapped)
            if character.isLetter || character.isNumber { output.append(character) }
        }
        return output
    }

    /// 去首尾空白 + 把连续空白压成一个空格（与 `MusicManager.normalizedLyricsRequestComponent` 同口径）。
    static func normalizedSpacing(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    // MARK: 歌手变体

    /// 歌手串的变体（按「离原样最近」排序，去重）：
    ///
    /// 1. 括号里的**别名**：`邓寓君(等什么君)` → `等什么君`（全角括号同理）；
    /// 2. 去掉括号（保留括号外的名字）：`邓寓君(等什么君)` → `邓寓君`；
    /// 3. 去掉**团体后缀**：`好妹妹乐队` → `好妹妹`（后缀表见 `bandSuffixes`）；
    /// 4. 拆多歌手：按 `、,，&/／;；| 与 及` 与 `feat./ft.` 拆，取每一段（至少两段才拆）；
    /// 5. 上面几步的结果再各做一次「去团体后缀 / 拆多歌手」的组合（只做一层，避免组合爆炸）。
    static func artistVariants(_ artist: String) -> [String] {
        let base = normalizedSpacing(artist)
        guard !base.isEmpty else { return [] }

        var output: [String] = []
        var seen = Set<String>([normalizedKey(base)])

        func append(_ candidate: String) {
            let value = normalizedSpacing(candidate)
            guard !value.isEmpty else { return }
            let key = normalizedKey(value)
            guard !key.isEmpty, seen.insert(key).inserted else { return }
            output.append(value)
        }

        var seeds = [base]

        // 括号里的别名 / 去掉括号
        for inside in parenthesizedParts(base) { append(inside) }
        let withoutParentheses = removingParenthesizedParts(base)
        if withoutParentheses != base { append(withoutParentheses); seeds.append(withoutParentheses) }
        for inside in parenthesizedParts(base) { seeds.append(inside) }

        // 团体后缀 / 拆多歌手（对原串与上面两步的产物各来一次）
        for seed in seeds {
            if let stripped = strippingBandSuffix(seed), stripped != seed { append(stripped) }
            if hasCollaboratorSeparator(seed) {
                for part in splittingCollaborators(seed) { append(part) }
            }
        }

        return output
    }

    /// 团体后缀表（唯一取值处）。只在「原样查询已经查不到」之后才用，且要用过 `accepts` 那道闸。
    static let bandSuffixes = ["乐队", "乐团", "组合", "合唱团", "合唱队", "工作室"]

    private static func strippingBandSuffix(_ value: String) -> String? {
        for suffix in bandSuffixes where value.hasSuffix(suffix) {
            let stripped = String(value.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            // 只剩一个字的「歌手」不留（`好妹妹乐队` → `好妹妹` 是想要的；`X乐队` → `X` 太短，收益低风险高）
            if stripped.count >= 2 { return stripped }
        }
        return nil
    }

    private static let collaboratorSeparators: [Character] = ["、", ",", "，", "&", "/", "／", ";", "；", "|"]

    private static func hasCollaboratorSeparator(_ value: String) -> Bool {
        value.contains { collaboratorSeparators.contains($0) }
            || value.range(of: "\\s+(feat\\.?|ft\\.?)\\s+", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// 拆多歌手：分隔符切段；`feat.` 之后的部分丢掉（那是客串，不是主歌手）。
    private static func splittingCollaborators(_ value: String) -> [String] {
        var head = value
        if let range = head.range(of: "\\s+(feat\\.?|ft\\.?)\\s+", options: [.regularExpression, .caseInsensitive]) {
            head = String(head[head.startIndex..<range.lowerBound])
        }
        let parts = head
            .split(whereSeparator: { collaboratorSeparators.contains($0) })
            .map { normalizedSpacing(String($0)) }
            .filter { !$0.isEmpty }
        return parts.count >= 2 ? parts : []
    }

    // MARK: 歌名变体

    /// 歌名变体：**去掉尾部的版本标注**（`樱花(现场吉他版）` → `樱花`；`丢了幸福的猪 (烟嗓版)` →
    /// `丢了幸福的猪`），最多剥 2 层（`X (Live) (Remastered)` 这一类）。
    ///
    /// 判据是「**尾部**有一个闭括号，且它前面存在同类开括号」——按字符集配，不要求左右成对
    /// （上游的括号常常一半半角一半全角，见 `normalizedKey` 的注释）。剥掉的只是标注，
    /// 歌名主体不动；能不能用仍由 `accepts` 的同名闸决定。
    static func titleVariants(_ title: String) -> [String] {
        var output: [String] = []
        var current = normalizedSpacing(title)
        for _ in 0..<2 {
            guard let stripped = strippingTrailingBracketedSuffix(current), stripped != current else { break }
            output.append(stripped)
            current = stripped
        }
        return output
    }

    private static let closingBrackets: [Character: [Character]] = [
        ")": ["(", "（"],
        "）": ["(", "（"],
        "]": ["[", "【"],
        "】": ["[", "【"],
    ]

    /// 剥掉形如 `(…)` / `（…）` / `[…]` / `【…】` 的**尾部**片段；找不到配对开括号则原样返回。
    static func strippingTrailingBracketedSuffix(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last, let openers = closingBrackets[last] else { return nil }
        let body = trimmed.dropLast()
        guard let openIndex = body.lastIndex(where: { openers.contains($0) }) else { return nil }
        let stripped = String(body[body.startIndex..<openIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }

    private static func parenthesizedParts(_ value: String) -> [String] {
        var output: [String] = []
        var depth = 0
        var buffer = ""
        for character in value {
            switch character {
            case "(", "（", "[", "【":
                if depth > 0 { buffer.append(character) }
                depth += 1
            case ")", "）", "]", "】":
                depth = max(0, depth - 1)
                if depth == 0 {
                    let part = normalizedSpacing(buffer)
                    if !part.isEmpty { output.append(part) }
                    buffer = ""
                } else {
                    buffer.append(character)
                }
            default:
                if depth > 0 { buffer.append(character) }
            }
        }
        return output
    }

    private static func removingParenthesizedParts(_ value: String) -> String {
        var output = ""
        var depth = 0
        for character in value {
            switch character {
            case "(", "（", "[", "【":
                depth += 1
            case ")", "）", "]", "】":
                depth = max(0, depth - 1)
            default:
                if depth == 0 { output.append(character) }
            }
        }
        return normalizedSpacing(output)
    }
}

// MARK: - 失败分类与重试节奏

enum LyricsFetchPolicy {

    /// 一次 HTTP 往返的三种结论。
    enum Answer: Equatable {
        /// 200：拿到了应答（**空数组也算**——那是「词库确实没有这条」）。
        case ok
        /// 瞬时故障（超时 / 断网 / 429 / 5xx）：**不能**当成「没有这条」，值得重试。
        case transient
        /// 确定性失败（4xx 里除 408/425/429 之外的）：请求本身不对，重试没有意义。
        case permanent
    }

    /// 状态码 → 结论。分界线是**「再问一次有没有可能变好」**：408（请求超时）、425（太早）、
    /// 429（限流）与 5xx（服务端）都会随时间自愈，其余 4xx 不会。
    static func classify(statusCode: Int) -> Answer {
        if statusCode == 200 { return .ok }
        if statusCode == 408 || statusCode == 425 || statusCode == 429 { return .transient }
        if (500...599).contains(statusCode) { return .transient }
        return .permanent
    }

    /// 重试间隔（毫秒）。**长度 = 重试次数**，所以一次查询最多打 `1 + count` 次。
    ///
    /// 实测依据：LRCLIB 的 503 是秒级的抖动（连打两次常常第二次就 200），0.7s 起步够快；
    /// 2s 那次留给「刚被限流」的情形。总预算 ≈2.7s，比换一首歌的时间短。
    static let retryDelaysMilliseconds: [Int] = [700, 2000]

    /// 瞬时故障之后**自动再试一次**的延迟（秒）：换首歌之前用户什么都不用做。
    /// 只自动重试一次（不是轮询）——重试这件事不该变成常驻流量。
    static let transientAutoRetryDelaySeconds: Double = 20
}
