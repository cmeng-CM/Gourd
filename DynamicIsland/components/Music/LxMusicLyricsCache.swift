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
//  LxMusicLyricsCache.swift
//  Gourd 音乐 · 从**本机播放器自己的歌词缓存**取词（2026-10-16 / docs/50 D-14）
//
//  为什么有这一层：用户 2026-10-16 问「应用里面有歌词，歌词开关也开着呢，为什么不显示，歌词不是从
//  应用拿的？」——播放器界面里的歌词**不是**系统能拿到的东西：macOS 的 Now Playing（MediaRemote）
//  载荷只有 title / artist / album / artwork / duration / 播放状态（本机实测，见 docs/50 §取证），
//  **没有任何歌词字段**；Gourd 原来的唯一歌词源是公共库 LRCLIB，而 LRCLIB 对国产曲目覆盖很差。
//
//  但本机在用的播放器 **LX Music**（`cn.toside.music.desktop`）自己把歌词缓存在本地 SQLite 里：
//  `~/Library/Application Support/lx-music-desktop/LxDatas/lx.data.db`
//  - `my_list_music_info`（歌单里的歌：`id` / `name` / `singer` / `interval`）——id ↔ 歌名/歌手/时长；
//  - `lyric`（`id` / `source` / `type` / `text`）：`type = 'lyric'` 是主歌词，`text` 是
//    **base64 的 UTF-8 LRC**。
//  本机实测：984 首歌有主歌词（`tlyric` 只有 151 首、`rlyric` 22 首非空，且**没有一首**是
//  「只有 lxlyric/tlyric 而没有 lyric」），用户正在听的「万水 / 李雨」就在里面，解出来与播放器
//  界面上显示的逐行一致。
//
//  三条口径（改动前先读）：
//  1. **只读**（同 `NotificationCenterReader` 的硬规矩）：一律 `SQLITE_OPEN_READONLY`，不写该库、
//     不在它旁边落临时文件。**取不到就当没有**——文件不存在 / schema 变了 / 读被拒 / 库里没有这首，
//     一律答 `nil`，由调用方回落 LRCLIB；本层任何情况下都不抛错、不崩；
//  2. **匹配在 Swift 侧做**：歌单表的 (name, singer) 与播放器报的歌名/歌手是**同一个来源**
//     （LX Music 自己写的），所以按归一化后的**同名**（`LyricsQueryPlanner.normalizedKey`）+ 歌手
//     互相包含匹配；候选多于一条时优先**时长吻合**（`interval` 是 `mm:ss`）的那条；
//  3. **只取 `type = 'lyric'`**：翻译（`tlyric`）与音译（`rlyric`）不读（口径见上）。
//
//  已知边界（docs/50 §已知限制）：只覆盖**在 LX Music 歌单里的歌**（映射表就是歌单表；本机
//  `music_info_other_source` 为空）；LX Music 自定义过数据目录时找不到；这一层是**为 LX Music 写的**，
//  别的播放器没有对应缓存。
//

import Foundation
import OSLog
import SQLite3

/// LX Music 本地歌词库的**只读**读取器。
final class LxMusicLyricsCache {

    /// 进程内共用一份（无状态，除了路径与 logger）。
    static let shared = LxMusicLyricsCache()

    /// LX Music 的默认数据目录（用户改过数据目录时这一层静默失效，由调用方回落 LRCLIB）。
    static var defaultDatabasePath: String {
        (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/lx-music-desktop/LxDatas/lx.data.db")
    }

    private let databasePath: String
    private let log = os.Logger(subsystem: "com.cmeng.gourd.music", category: "lyrics")

    init(databasePath: String = LxMusicLyricsCache.defaultDatabasePath) {
        self.databasePath = databasePath
    }

    /// 歌单里的一行（匹配只需要这四个字段）。
    struct Entry: Equatable {
        let id: String
        let name: String
        let singer: String
        /// `mm:ss` 形式的时长（可能为空串）。
        let interval: String
    }

    // MARK: - 取词

    /// 按歌名 / 歌手（+ 时长）取这首歌的主歌词（LRC 原文，base64 已解开）。
    ///
    /// - Parameters:
    ///   - titles: 候选歌名（调用方给原样与「剥掉版本标注」两种，与 LRCLIB 那条阶梯同源）。
    ///   - artist: 播放器报的歌手串。
    ///   - duration: 播放器报的时长（秒）；取不到传 0（那一档就不参与「时长吻合」的优先）。
    /// - Returns: LRC 原文；本机没有这首歌 / 库读不到 / 歌词为空 → `nil`。
    func lyricText(titles: [String], artist: String, duration: TimeInterval) -> String? {
        guard FileManager.default.fileExists(atPath: databasePath) else { return nil }

        var database: OpaquePointer?
        // **只读**打开（LX Music 自己是 WAL，只读连接照样看得见已提交的数据）。
        guard sqlite3_open_v2(databasePath, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            if let database { sqlite3_close(database) }
            log.notice("LX Music 歌词库只读打开失败，回落 LRCLIB")
            return nil
        }
        defer { sqlite3_close(database) }
        // 对方在写：短等一下（毫秒级），拿不到就这次认输（下一次取词还会再来）。
        sqlite3_busy_timeout(database, 300)

        let titleKeys = Set(titles.map(LyricsQueryPlanner.normalizedKey).filter { !$0.isEmpty })
        guard !titleKeys.isEmpty else { return nil }
        let artistKey = LyricsQueryPlanner.normalizedKey(artist)

        let candidates = entries(in: database).filter { entry in
            titleKeys.contains(LyricsQueryPlanner.normalizedKey(entry.name))
                && Self.artistMatches(entryKey: LyricsQueryPlanner.normalizedKey(entry.singer), queryKey: artistKey)
        }
        guard let entry = Self.pick(from: candidates, duration: duration) else { return nil }

        guard let raw = lyricRowText(in: database, id: entry.id),
              let text = Self.lyricText(fromStored: raw) else { return nil }
        return text
    }

    // MARK: - 匹配（纯函数，用例直接钉）

    /// 歌手算不算对上：归一化后**互相包含**（同 `LyricsQueryPlanner.accepts` 的口径）。
    /// 空歌手串算对不上——宁可回落 LRCLIB，也不拿「同名不同人」的歌词。
    static func artistMatches(entryKey: String, queryKey: String) -> Bool {
        guard !entryKey.isEmpty, !queryKey.isEmpty else { return false }
        return entryKey.contains(queryKey) || queryKey.contains(entryKey)
    }

    /// 多条候选里挑一条：**时长吻合**（±`LyricsQueryPlanner.durationTolerance`）的优先，
    /// 其次按表里的顺序取第一条。时长取不到 / 都不吻合时退化成「第一条」——本地库里同一位歌手
    /// 的同一首歌通常只有一条，退化不会放大误差。
    static func pick(from candidates: [Entry], duration: TimeInterval) -> Entry? {
        guard !candidates.isEmpty else { return nil }
        guard duration.isFinite, duration > 0 else { return candidates.first }
        let matched = candidates.first { entry in
            guard let seconds = seconds(fromInterval: entry.interval) else { return false }
            return abs(seconds - duration) <= LyricsQueryPlanner.durationTolerance
        }
        return matched ?? candidates.first
    }

    /// `mm:ss`（LX Music 的 `interval` 列格式）→ 秒；解析不了给 `nil`。
    static func seconds(fromInterval interval: String) -> TimeInterval? {
        let parts = interval.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":")
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]),
              minutes >= 0, seconds >= 0 else { return nil }
        return minutes * 60 + seconds
    }

    /// 库里存的 `text` → 歌词原文。
    ///
    /// 正常形态是 **base64 的 UTF-8**（本机 984 行全部如此）；解不开时再看一眼**裸 LRC**
    /// （含 `[mm:ss` 时间轴）——LX Music 换过编码也不至于整层失效。两者都不是 → `nil`
    /// （不拿乱码当歌词）。
    static func lyricText(fromStored stored: String) -> String? {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let decoded = decodeBase64Utf8(trimmed) {
            let text = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        if looksLikeLRC(trimmed) { return trimmed }
        return nil
    }

    /// base64 → UTF-8 字符串（失败给 `nil`）。
    static func decodeBase64Utf8(_ base64: String) -> String? {
        guard let data = Data(base64Encoded: base64, options: [.ignoreUnknownCharacters]) else { return nil }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    /// 像不像 LRC（有 `[数字:数字` 这种时间轴起点）。
    static func looksLikeLRC(_ text: String) -> Bool {
        text.range(of: "\\[\\d{1,3}:\\d{2}", options: .regularExpression) != nil
    }

    // MARK: - 读库（只读；任何失败都退成空，不抛错）

    /// 歌单表 + 备用来源表里的全部条目（两张表的字段名一致；备用来源表在本机为空）。
    func entries(in database: OpaquePointer) -> [Entry] {
        var rows: [Entry] = []
        for table in ["my_list_music_info", "music_info_other_source"] {
            var statement: OpaquePointer?
            let sql = "SELECT id, name, singer, interval FROM \(table)"
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                continue  // 表不在（schema 变了）→ 当这张表没有
            }
            defer { sqlite3_finalize(statement) }
            while sqlite3_step(statement) == SQLITE_ROW {
                rows.append(
                    Entry(
                        id: Self.string(statement, column: 0) ?? "",
                        name: Self.string(statement, column: 1) ?? "",
                        singer: Self.string(statement, column: 2) ?? "",
                        interval: Self.string(statement, column: 3) ?? ""
                    )
                )
            }
        }
        return rows.filter { !$0.id.isEmpty && !$0.name.isEmpty }
    }

    /// `lyric` 表里这首歌的主歌词（`text` 列原文）。
    private func lyricRowText(in database: OpaquePointer, id: String) -> String? {
        var statement: OpaquePointer?
        let sql = "SELECT text FROM lyric WHERE id = ?1 AND type = 'lyric' LIMIT 1"
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Self.string(statement, column: 0)
    }

    private static func string(_ statement: OpaquePointer, column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }
}
