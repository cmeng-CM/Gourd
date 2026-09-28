/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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

import Foundation
import Defaults

#if canImport(AppKit)
import AppKit
#endif

enum AppleNotesSyncError: LocalizedError {
    case automationDenied
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .automationDenied:
            return String(localized: "Allow Gourd to control Notes in System Settings → Privacy & Security → Automation.")
        case .scriptFailed(let message):
            return message
        }
    }
}

struct RemoteAppleNote: Sendable {
    let id: String
    let title: String
    let content: String
    let creationDate: Date
    let modificationDate: Date
    let atollId: UUID?
    /// 笔记所在容器（文件夹）名，用于剔除「最近删除」里的条目；旧格式记录（无该字段）解析为空串。
    /// 取法必须分两步：`set c to container of n` 再 `name of c`——写成一个式子
    /// `name of container of n` 会被 Notes 拒（-1728 不能获得）。
    /// sdef 里 `container` 的类型是 `folder`（cocoa key = `folder`），即文件夹而非账号。
    let containerName: String
}

/// 「最近删除」容器名判定。
///
/// 已知局限：Apple Notes 的 AppleScript 字典**不暴露**「是否在回收站」的语言无关标识
/// （`container` 只给容器名，且「最近删除」是随系统语言本地化的）。因此这里按语言枚举已知名称：
/// 命中即视为已删除；**未命中（含系统语言不在表内、容器名为空）一律按未删除处理**，
/// 即保持旧行为——宁可漏过滤，也不误删用户仍在的笔记。若新增语言出现同名重复问题，
/// 按同样格式往 `trashedFolderNames` 里补一条即可。
///
/// 实测（macOS 27，本机系统语言 zh-Hans-CN）：AppleScript 侧该文件夹名返回的是**英文**
/// `Recently Deleted`，而不是 UI 上的「最近删除」。所以 en 与各本地化名都要留着——
/// 只留 UI 语言对应的那一条会在真机上漏判。
enum AppleNotesTrashFilter {
    /// Apple Notes「最近删除」文件夹在各语言下的名称（逐字照抄系统实际显示值）。
    private static let trashedFolderNames: Set<String> = [
        "最近删除",              // zh-Hans
        "最近刪除",              // zh-Hant
        "Recently Deleted",      // en
        "最近削除した項目",        // ja
        "최근 삭제된 항목",        // ko
        "Zuletzt gelöscht",      // de
        "Supprimés récemment",   // fr
        "Eliminadas recientemente", // es
        "Eliminati di recente",  // it
        "Excluídos recentemente", // pt
        "Onlangs verwijderd",    // nl
        "Недавно удаленные",     // ru
        "Ostatnio usunięte",     // pl
        "Son Silinenler",        // tr
        "Нещодавно видалені",    // uk
        "Nemrég törölt",         // hu
        "Nedávno smazané",       // cs
        "เร็วๆ นี้ถูกลบ",          // th
        "المحذوفة مؤخرًا",        // ar
    ]

    /// 大小写不敏感的比较用表（`lowercased()` 与 locale 无关）。
    private static let normalizedTrashedFolderNames: Set<String> =
        Set(trashedFolderNames.map { $0.lowercased() })

    /// 容器名是否为「最近删除」。首尾空白与大小写无关；空串（旧格式记录 / 取不到容器名）不算。
    static func isTrashed(containerName: String) -> Bool {
        let normalized = containerName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return false }
        return normalizedTrashedFolderNames.contains(normalized)
    }
}

@MainActor
final class AppleNotesSyncManager: ObservableObject {
    static let shared = AppleNotesSyncManager()

    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?

    private static let syncFolderName = "壶中天"
    private static let fieldSeparator = "\u{241F}"
    private static let recordSeparator = "\u{241E}"
    private static let atollTagPattern = #"<!--atoll:id=([0-9A-Fa-f-]{36})-->"#

    private var syncTask: Task<Void, Never>?

    private init() {}

    func requestSync(localNotes: [NoteItem]) {
        guard Defaults[.enableAppleNotesSync] else { return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.sync(localNotes: localNotes)
        }
    }

    @discardableResult
    func sync(localNotes: [NoteItem]) async -> [NoteItem]? {
        guard Defaults[.enableAppleNotesSync] else { return nil }
        guard !isSyncing else { return nil }

        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        do {
            let remoteNotes = try await fetchRemoteNotes()
            var merged = try await merge(localNotes: localNotes, remoteNotes: remoteNotes)
            merged = try await pushUnlinkedLocalNotes(merged)
            Defaults[.appleNotesLastSyncDate] = Date()
            return merged
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func pushNote(_ note: NoteItem) async -> NoteItem? {
        guard Defaults[.enableAppleNotesSync] else { return nil }

        do {
            if let appleNotesId = note.appleNotesId {
                try await updateRemoteNote(id: appleNotesId, note: note)
                return note
            } else {
                let newId = try await createRemoteNote(note)
                var updated = note
                updated.appleNotesId = newId
                return updated
            }
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func deleteRemoteNote(appleNotesId: String) async {
        guard Defaults[.enableAppleNotesSync] else { return }

        do {
            try await deleteRemoteNote(id: appleNotesId)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Merge

    private func merge(localNotes: [NoteItem], remoteNotes: [RemoteAppleNote]) async throws -> [NoteItem] {
        var notes = localNotes
        // Apple Notes 可能回吐同 id 的重复条目（跨账户/重复抓取），uniqueKeysWithValues 遇重复会 fatalError。
        // 改用 uniquingKeysWith，冲突时保留修改时间更新的一条。
        var remoteById = Dictionary(
            remoteNotes.map { ($0.id, $0) },
            uniquingKeysWith: { lhs, rhs in rhs.modificationDate > lhs.modificationDate ? rhs : lhs }
        )
        var linkedRemoteIds = Set<String>()

        for index in notes.indices {
            guard let appleNotesId = notes[index].appleNotesId,
                  let remote = remoteById[appleNotesId] else { continue }

            linkedRemoteIds.insert(appleNotesId)

            if remote.modificationDate > notes[index].modificationDate {
                applyRemote(remote, to: &notes[index])
            } else if notes[index].modificationDate > remote.modificationDate {
                try await updateRemoteNote(id: appleNotesId, note: notes[index])
            }
        }

        // 遍历去重后的 remoteById.values 而非原始 remoteNotes：否则同 id 的旧副本可能先被
        // 处理并占位，新副本被跳过，atollId 匹配与新笔记导入的结果就会依赖数组顺序。
        for remote in remoteById.values where !linkedRemoteIds.contains(remote.id) {
            if let atollId = remote.atollId,
               let index = notes.firstIndex(where: { $0.id == atollId }) {
                linkedRemoteIds.insert(remote.id)
                notes[index].appleNotesId = remote.id
                if remote.modificationDate > notes[index].modificationDate {
                    applyRemote(remote, to: &notes[index])
                }
                continue
            }

            let imported = NoteItem(
                title: sanitizedTitle(remote.title),
                content: remote.content,
                creationDate: remote.creationDate,
                modificationDate: remote.modificationDate,
                colorIndex: 0,
                appleNotesId: remote.id
            )
            notes.append(imported)
            linkedRemoteIds.insert(remote.id)
        }

        notes.removeAll { note in
            guard let appleNotesId = note.appleNotesId else { return false }
            return !linkedRemoteIds.contains(appleNotesId) && remoteById[appleNotesId] == nil
        }

        return notes.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            return lhs.modificationDate > rhs.modificationDate
        }
    }

    private func pushUnlinkedLocalNotes(_ notes: [NoteItem]) async throws -> [NoteItem] {
        var updated = notes
        for index in updated.indices where updated[index].appleNotesId == nil {
            let newId = try await createRemoteNote(updated[index])
            updated[index].appleNotesId = newId
        }
        return updated
    }

    private func applyRemote(_ remote: RemoteAppleNote, to note: inout NoteItem) {
        note.title = sanitizedTitle(remote.title)
        note.content = remote.content
        note.creationDate = remote.creationDate
        note.modificationDate = remote.modificationDate
        note.appleNotesId = remote.id
    }

    private func sanitizedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Untitled Note") : trimmed
    }

    // MARK: - AppleScript bridge

    private func fetchRemoteNotes() async throws -> [RemoteAppleNote] {
        let script = """
        set fieldSep to "\(Self.fieldSeparator)"
        set recordSep to "\(Self.recordSeparator)"
        tell application "Notes"
            set epoch to (current date)
            set hours of epoch to 0
            set minutes of epoch to 0
            set seconds of epoch to 0
            set year of epoch to 1970
            set month of epoch to January
            set day of epoch to 1
            set chunks to {}
            repeat with n in notes of default account
                if password protected of n is false then
                    set notePlain to plaintext of n
                    set notePlain to my sanitizeField(notePlain, fieldSep, recordSep)
                    set atollId to my extractAtollId(body of n)
                    -- 必须分两步取容器名：`name of container of n` 一个式子会被 Notes 拒（-1728 不能获得）。
                    set noteContainerRef to container of n
                    set noteContainer to my sanitizeField((name of noteContainerRef), fieldSep, recordSep)
                    set chunk to (id of n) & fieldSep & (name of n) & fieldSep & ((creation date of n) - epoch as string) & fieldSep & ((modification date of n) - epoch as string) & fieldSep & notePlain & fieldSep & atollId & fieldSep & noteContainer
                    set end of chunks to chunk
                end if
            end repeat
            set AppleScript's text item delimiters to recordSep
            return chunks as text
        end tell

        on sanitizeField(txt, fieldSep, recordSep)
            set AppleScript's text item delimiters to fieldSep
            set parts to text items of txt
            set AppleScript's text item delimiters to " "
            set txt to parts as text
            set AppleScript's text item delimiters to recordSep
            set parts to text items of txt
            set AppleScript's text item delimiters to " "
            return parts as text
        end sanitizeField

        on extractAtollId(noteBody)
            if noteBody does not contain "atoll:id=" then return ""
            set AppleScript's text item delimiters to "atoll:id="
            set tail to item 2 of (text items of noteBody)
            set AppleScript's text item delimiters to "-->"
            return item 1 of (text items of tail)
        end extractAtollId
        """

        let output = try await runScriptReturningString(script)
        let fetched = parseRemoteNotes(output)

        // `notes of default account` 连「最近删除」里的笔记一起枚举出来。这些条目若进入 merge，
        // 会被当作有效远端写进 `linkedRemoteIds`，末尾的 `removeAll` 就永远清不掉它们——
        // 用户在系统里删掉的笔记会一直留在岛上（且与活跃笔记同名时显示为重复）。
        // 因此过滤必须发生在 merge **之前**：merge 之后既有的 removeAll 自然会移除本地对应项。
        let active = fetched.filter { !AppleNotesTrashFilter.isTrashed(containerName: $0.containerName) }
        let skipped = fetched.count - active.count
        if skipped > 0 {
            Logger.log("笔记同步：跳过 \(skipped) 条「最近删除」笔记（本次取回 \(fetched.count) 条）", category: .debug)
        }
        return active
    }

    private func parseRemoteNotes(_ payload: String) -> [RemoteAppleNote] {
        guard !payload.isEmpty else { return [] }

        return payload
            .split(separator: Character(Self.recordSeparator), omittingEmptySubsequences: true)
            .compactMap { record in
                // 字段：id ␟ title ␟ creationDate ␟ modificationDate ␟ plaintext ␟ atollId ␟ containerName
                // maxSplits = 6 → 至多 7 段，正文里的分隔符已被 AppleScript 侧 sanitizeField 清掉。
                let fields = record.split(separator: Character(Self.fieldSeparator), maxSplits: 6, omittingEmptySubsequences: false)
                guard fields.count >= 5 else { return nil }

                let id = String(fields[0])
                let title = String(fields[1])
                guard let created = parseAppleScriptSeconds(String(fields[2])),
                      let modified = parseAppleScriptSeconds(String(fields[3])) else { return nil }

                let content = String(fields[4])
                let atollId = fields.count > 5
                    ? UUID(uuidString: String(fields[5]))
                    : extractAtollId(from: content)
                // 旧格式记录（无容器名）给空串：`isTrashed` 对空串返回 false，等价旧行为。
                let containerName = fields.count > 6 ? String(fields[6]) : ""

                return RemoteAppleNote(
                    id: id,
                    title: title,
                    content: content,
                    creationDate: created,
                    modificationDate: modified,
                    atollId: atollId,
                    containerName: containerName
                )
            }
    }

    private func parseAppleScriptSeconds(_ raw: String) -> Date? {
        let normalized = raw
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "E+", with: "e")
        guard let seconds = Double(normalized) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private func extractAtollId(from content: String) -> UUID? {
        guard let regex = try? NSRegularExpression(pattern: Self.atollTagPattern) else { return nil }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, range: range),
              let idRange = Range(match.range(at: 1), in: content) else { return nil }
        return UUID(uuidString: String(content[idRange]))
    }

    private func createRemoteNote(_ note: NoteItem) async throws -> String {
        try await ensureSyncFolderExists()

        let title = appleScriptEscape(sanitizedTitle(note.title))
        let body = appleScriptEscape(htmlBody(for: note))

        let script = """
        tell application "Notes"
            set newNote to make new note at folder "\(Self.syncFolderName)" of default account with properties {name:"\(title)", body:"\(body)"}
            return id of newNote
        end tell
        """

        return try await runScriptReturningString(script)
    }

    private func updateRemoteNote(id: String, note: NoteItem) async throws {
        let title = appleScriptEscape(sanitizedTitle(note.title))
        let body = appleScriptEscape(htmlBody(for: note))
        let escapedId = appleScriptEscape(id)

        let script = """
        tell application "Notes"
            set targetNote to first note whose id is "\(escapedId)"
            set name of targetNote to "\(title)"
            set body of targetNote to "\(body)"
        end tell
        """

        try await runScriptVoid(script)
    }

    private func deleteRemoteNote(id: String) async throws {
        let escapedId = appleScriptEscape(id)
        let script = """
        tell application "Notes"
            set matches to every note whose id is "\(escapedId)"
            if (count of matches) > 0 then
                delete item 1 of matches
            end if
        end tell
        """
        try await runScriptVoid(script)
    }

    private func ensureSyncFolderExists() async throws {
        let script = """
        tell application "Notes"
            try
                set _folder to folder "\(Self.syncFolderName)" of default account
            on error
                make new folder at default account with properties {name:"\(Self.syncFolderName)"}
            end try
        end tell
        """
        try await runScriptVoid(script)
    }

    private func htmlBody(for note: NoteItem) -> String {
        let escaped = note.content
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        let html = escaped
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                if line.isEmpty { return "<div><br></div>" }
                return "<div>\(line)</div>"
            }
            .joined()

        return html + "<!--atoll:id=\(note.id.uuidString)-->"
    }

    private func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
    }

    private func runScriptReturningString(_ script: String) async throws -> String {
        let descriptor = try await executeScript(script)
        guard let value = descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw AppleNotesSyncError.scriptFailed(String(localized: "Notes returned an empty response."))
        }
        return value
    }

    private func runScriptVoid(_ script: String) async throws {
        _ = try await executeScript(script)
    }

    private func executeScript(_ script: String) async throws -> NSAppleEventDescriptor {
        do {
            guard let descriptor = try await AppleScriptHelper.execute(script) else {
                throw AppleNotesSyncError.scriptFailed(String(localized: "Notes script returned no result."))
            }
            return descriptor
        } catch let error as NSError {
            if error.domain == "AppleScriptError", (error.userInfo["NSAppleScriptErrorNumber"] as? Int) == -1743 {
                throw AppleNotesSyncError.automationDenied
            }
            let message = (error.userInfo["NSAppleScriptErrorMessage"] as? String) ?? error.localizedDescription
            throw AppleNotesSyncError.scriptFailed(message)
        }
    }
}
