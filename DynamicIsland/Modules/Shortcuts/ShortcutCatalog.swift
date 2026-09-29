//
//  ShortcutCatalog.swift
//  Gourd 模块 · 快捷指令（p2-shortcuts-frontapp / T1）
//
//  docs/22-shortcuts-and-frontapp.md §接口与数据形状 1 的三件**纯逻辑**：
//  本文件没有 `Process`、不 import AppKit / SwiftUI——子进程在 `ShortcutRunner.swift`，
//  视图在 T2 的 `ShortcutsModule.swift`。纯逻辑独立成文件的理由是可测：
//  解析与过滤是这两个模块里唯一会被写错、又最难在 UI 上看出来的地方（名字可变、缓存存的是原始行）。
//
//  - `Shortcut`：一条系统快捷指令。**身份是 identifier**（D-01）：名称可重复、可随时改，
//    identifier 稳定；`name` 只用于显示（§备选与取舍 ①）。
//  - `ShortcutListParser.parse(lines:)`：`shortcuts list --show-identifiers` 的**原始行** → 条目。
//  - `ShortcutFiltering.visible(_:pinned:query:)`：可见集与顺序的唯一出口（视图不另写逻辑）。
//  - `ShortcutRunResult`：一次运行的结果（`Outcome` / `output` / `failureMessage` / `duration`）。
//
//  解析规则**从行尾往回找第一个 ` (`**（机制一）：名称里可以有空格，**也可以有括号**——
//  `整理桌面 (旧) (2F1C…)` 这种行里只有最后一个 ` (` 是名称与 identifier 的分界；
//  从行首往右切会把名称后半段（`旧) (2F1C…`）当成 identifier，且它**看起来像一条合法结果**。
//  形状不符的行（没有 ` (`、不以 `)` 结尾、名称或 identifier 为空）**直接丢弃**：不猜、不补默认名——
//  名字可变，任何兜底（例如「拿不到 identifier 就用名称」）都只会把错的人静默跑起来。
//

import Foundation

// MARK: - 条目

/// 一条系统快捷指令（`identifier` 是稳定身份，`name` 只用于显示）。
struct Shortcut: Equatable, Identifiable {
    let identifier: String
    let name: String

    var id: String { identifier }
}

// MARK: - 解析

enum ShortcutListParser {
    /// `shortcuts list --show-identifiers` 的原始行 → 条目（丢掉的行走不进结果）。
    ///
    /// 每一行的形状是 `<名称> (<identifier>)`：**最后一个 ` (` 才是分界**，其前是名称、其后的括号内是
    /// identifier。首尾空白（名称侧、identifier 侧）都去掉后再判空——`"   (0F0F)"` 这种名称只有空白的行
    /// 也算形状不符（它不是「名叫空格的指令」）。
    static func parse(lines: [String]) -> [Shortcut] {
        lines.compactMap { line in
            // 从行尾往回找第一个 ` (`：`.backwards` 找的是**最后一次**出现。
            guard let separator = line.range(of: " (", options: .backwards) else { return nil }

            // 名称侧：分隔符之前，去首尾空白后必须非空。
            let name = line[line.startIndex..<separator.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }

            // identifier 侧：分隔符之后必须以 `)` 收尾（形状不符就丢，不去找下一个括号）。
            let tail = line[separator.upperBound...]
            guard tail.hasSuffix(")") else { return nil }
            let identifier = tail.dropLast().trimmingCharacters(in: .whitespaces)
            guard !identifier.isEmpty else { return nil }

            return Shortcut(identifier: identifier, name: name)
        }
    }
}

// MARK: - 搜索与排序

/// 可见集与顺序（纯函数，视图不另写逻辑）：固定项在前（**保持固定表顺序**），其余保持命令给出的顺序；
/// 搜索对 `name` 与 `identifier` 都做不区分大小写的包含匹配。
enum ShortcutFiltering {
    /// - Parameters:
    ///   - shortcuts: 解析后的清单（顺序 = 命令给出的顺序，即 `shortcuts list` 的输出顺序）。
    ///   - pinned: 固定表的 identifier（顺序 = 用户排的顺序；表里可能有已删掉的 id）。
    ///   - query: 搜索词；**去首尾空白后为空**（空串 / 只有空格）表示不过滤。
    ///
    /// 三条口径（写下来是因为它们都能被两种读法解释，这里定了其中一种）：
    /// 1. **搜索先于排序**：固定项也要过搜索——固定不等于「永远显示」，否则搜一个别的名字会看到一堆
    ///    无关的固定项（`visible(_, pinned:, query:)` 的入参是整张清单，不是「固定 + 其余」两摞）；
    /// 2. **固定表里已不在清单里的 id 直接跳过**（在系统里删掉 / 改名的指令不该凭空出现），
    ///    同一个 identifier 也只出现一次（固定项不再出现在「其余」那一段）；
    /// 3. **查询词去空白**：搜索框里多打一个空格不该变成「无命中」（那是输入法的日常，不是意图）。
    static func visible(_ shortcuts: [Shortcut], pinned: [String], query: String) -> [Shortcut] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched: [Shortcut]
        if needle.isEmpty {
            matched = shortcuts
        } else {
            matched = shortcuts.filter { shortcut in
                shortcut.name.localizedCaseInsensitiveContains(needle)
                    || shortcut.identifier.localizedCaseInsensitiveContains(needle)
            }
        }

        // 固定项在前：按**固定表顺序**取（不是按清单顺序），取不到的跳过。
        let byID = Dictionary(matched.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [Shortcut] = []
        var taken = Set<String>()
        for identifier in pinned {
            guard taken.insert(identifier).inserted, let shortcut = byID[identifier] else { continue }
            result.append(shortcut)
        }
        // 其余保持清单顺序（命令给的顺序）。
        for shortcut in matched where taken.insert(shortcut.identifier).inserted {
            result.append(shortcut)
        }
        return result
    }
}

// MARK: - 一次运行的结果

/// 一次运行的结果。
struct ShortcutRunResult: Equatable {
    enum Outcome: Equatable {
        case success
        case failure
        case timedOut
    }

    let outcome: Outcome
    /// `showOutput` 关时是空串；开时是输出文件内容（截断到 `maxOutputLines` 行，见 `ShortcutRunner`）。
    let output: String
    /// 失败 / 超时的**说明**：失败时是 stderr 摘要（系统给的原话，见 docs/22 §已知限制 1），
    /// 超时时是一句说明。成败都要显示它——这一栏是「失败时把系统的原话摆出来」的载体；
    /// 成功时没有要解释的东西，因此是空串。
    let failureMessage: String
    let duration: TimeInterval
}
