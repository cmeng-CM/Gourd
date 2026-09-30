// Modified for Gourd (2026-09-30)
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
//  LauncherAppScanner.swift
//  Gourd 内置模块 · 启动台应用扫描（P2 批次 / T1）
//
//  docs/19-launcher.md §接口与数据形状 1 + §改动点设计 1 的落点：
//  应用清单**来自目录扫描**（不用 LaunchServices 数据库 / 私有 API，docs/15 的「零私有 API」口径）——
//  每个根目录只扫**一层**子项，只留扩展名 `.app`，然后用 `Bundle(url:)` 读 Info.plist 取 id 与名称。
//
//  四条刻意写死的口径（改动前先读）：
//
//  1. **不递归**：只列举根目录的直接子项，`.app` 内部的嵌套包（`Foo.app/Contents/.../Bar.app`）
//     不是独立应用——它属于外层那个包，出现在网格里就是重复项（docs/19 §改动点设计 1 的陷阱）。
//  2. **单个根失败只跳过它**：不存在、是文件、无权限（例如未授权的 `~/Applications`）时
//     `try?` 让这一根为空表，**不影响其它根**，也不抛错——「一个目录读不到 → 整表空」是失败信号。
//  3. **根目录可注入**：`scan(rootURLs:)` 的根由调用方给，`defaultRoots` 只是默认值；
//     单测一律传临时目录树 fixture，**绝不扫真实 `/Applications`**（机器状态会让断言抖动）。
//  4. **id 是稳定的用户数据键**：`CFBundleIdentifier` 优先、缺失（空壳 / 无 plist 的 `.app`）时
//     用 `url.path`。`pinnedApps` 存的也是这个值（docs/19 §改动点设计 3），两处必须同源。
//

import Foundation

/// 启动台里的一个应用。
///
/// `id` 同时是固定项（`pinnedApps`）与使用数据（`usage`）的键——
/// 「同一 App 用两种键写两次 → 固定判据分裂」的坑就在这一层堵住（docs/19 §改动点设计 3）。
struct LauncherApp: Identifiable, Equatable, Sendable {
    /// `CFBundleIdentifier` 优先；缺失时回落 `url.path`（无 id 的 `.app` 也允许存在）。
    let id: String
    /// `CFBundleDisplayName` → `CFBundleName` → 文件名（去 `.app`）。
    let name: String
    /// `.app` 的绝对路径（已 `standardizedFileURL`，无尾斜杠）。
    let url: URL
}

enum LauncherAppScanner {

    /// 默认根目录：`/Applications`、`~/Applications`、`/System/Applications`。
    ///
    /// 不存在的目录由 `scan` 自然跳过（不抛错、不影响其它根），因此这里不做存在性检查；
    /// 扫描器本身**不硬编码**这三个路径，它们只是调用方可省的默认值。
    static var defaultRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
        ]
    }

    /// 扫若干根目录的**一层**子项，返回其中的 `.app`（纯 I/O，不排序用户可见顺序）。
    ///
    /// - 只留扩展名 `.app`（大小写不敏感；不校验包是否可执行——空壳包也列出，名称回落文件名）；
    /// - 按 `url.standardizedFileURL` 去重（同一个根被传两次、或两个根指向同一路径，只留一次）；
    /// - 单个根读失败（不存在 / 是文件 / 无权限）只跳过该根；
    /// - 结果按路径升序（文件系统枚举顺序不稳定，给调用方一个可复现的清单；
    ///   用户可见的先后由 `LauncherRanking.rank` 决定）。
    static func scan(rootURLs: [URL], fileManager: FileManager = .default) -> [LauncherApp] {
        var seen: Set<String> = []
        var apps: [LauncherApp] = []

        for root in rootURLs {
            // 单根失败只跳过：`try?` 而不是 `try`（见文件头口径 2）
            guard let entries = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: []
            ) else { continue }

            for entry in entries {
                guard entry.pathExtension.lowercased() == "app" else { continue }
                let url = entry.standardizedFileURL
                guard seen.insert(url.path).inserted else { continue }
                apps.append(makeApp(at: url))
            }
        }

        return apps.sorted { $0.url.path < $1.url.path }
    }

    /// 一个 `.app` 目录 → `LauncherApp`：读 Info.plist 取 id 与显示名，读不到就回落。
    private static func makeApp(at url: URL) -> LauncherApp {
        // `Bundle(url:)` 对「存在但不成包」的目录也可能返回非 nil（infoDictionary 为空），
        // 因此两个键都用 `object(forInfoDictionaryKey:)` 取空安全的可选值。
        let bundle = Bundle(url: url)
        let identifier = nonBlank(bundle?.bundleIdentifier)
        let plistName = nonBlank(bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName"))
            ?? nonBlank(bundle?.object(forInfoDictionaryKey: "CFBundleName"))

        return LauncherApp(
            id: identifier ?? url.path,
            name: plistName ?? url.deletingPathExtension().lastPathComponent,
            url: url
        )
    }

    /// 空串与纯空白等同于「没有这个键」（plist 里写空的显示名不该在网格里留一行看不见的标题）。
    private static func nonBlank(_ value: Any?) -> String? {
        guard let text = value as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return text
    }
}
