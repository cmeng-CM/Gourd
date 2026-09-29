//
//  LauncherRanking.swift
//  Gourd 内置模块 · 启动台排序与搜索（P2 批次 / T1）
//
//  docs/19-launcher.md §接口与数据形状 2 的落点：**纯函数、无副作用**——
//  不读 `Defaults`（固定项由调用方从 `pinnedApps` 读好传进来）、不碰文件系统、不查 Spotlight。
//  使用数据（最近使用时间 / 使用次数）由调用方从 `NSMetadataQuery` 取好传进来（取数属 T2），
//  因此本文件可以完全用构造的数据测。
//
//  排序键（**固定优先 → 最近使用降序 → 使用次数降序 → 名称升序**，docs/19 §验收标准）：
//
//  | 键 | 方向 | 缺数据的口径 |
//  |---|---|---|
//  | 是否在 `pinned` 里 | 固定项恒在前 | — |
//  | `lastUsed` | 降序（新的在前） | `nil` = 无数据，排在有数据的**之后** |
//  | `useCount` | 降序（多的在前） | `nil` = 无数据，排在有数据的**之后** |
//  | `name` | `localizedStandardCompare` 升序 | — |
//
//  三条不变量：
//
//  1. **没有使用数据时一律按名称排**——`usage` 整个为空、某几项缺失、某项两个字段都是 `nil`，
//     都退化成「固定 → 名称」。扫描成功但清单乱序（例如按字典序渲染成 1, 10, 2）是失败信号。
//  2. **`pinned` 里的未知 id 一律忽略**——固定项是用户数据，会残留已卸载 / 已移动的 App 的 id；
//     排序只以「清单里真的有这一项」为准，既不崩也不把清单挤乱。
//  3. **排序结果可复现**——四项键全相等（同名又都没使用数据）时按 `id` 定序；
//     否则同样输入的输出顺序取决于文件系统枚举顺序，界面上会看到随机跳动。
//

import Foundation

/// 一个应用的使用数据（来自 Spotlight 的 `kMDItemLastUsedDate` / `kMDItemUseCount`）。
///
/// 两个字段都可能缺：Spotlight 未开索引、未收录该 App、或查询失败时调用方传 `nil` / 空表。
struct LauncherUsage: Equatable, Sendable {
    let lastUsed: Date?
    let useCount: Int?
}

enum LauncherRanking {

    /// 排好序的清单（固定 → 最近使用 → 使用次数 → 名称）。
    ///
    /// 输入不被修改（纯函数）；`usage` 里没有的项按「无数据」处理。
    static func rank(
        _ apps: [LauncherApp],
        pinned: [String],
        usage: [String: LauncherUsage]
    ) -> [LauncherApp] {
        let pinnedIDs = Set(pinned)

        return apps.sorted { lhs, rhs in
            let lhsPinned = pinnedIDs.contains(lhs.id)
            let rhsPinned = pinnedIDs.contains(rhs.id)
            if lhsPinned != rhsPinned { return lhsPinned }

            let lhsUsage = usage[lhs.id]
            let rhsUsage = usage[rhs.id]
            if let decided = isDescendingFirst(lhsUsage?.lastUsed, rhsUsage?.lastUsed) { return decided }
            if let decided = isDescendingFirst(lhsUsage?.useCount, rhsUsage?.useCount) { return decided }

            let order = lhs.name.localizedStandardCompare(rhs.name)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.id < rhs.id   // 同名（且前面各键相等）：按 id 定序，保证可复现
        }
    }

    /// 搜索过滤：大小写不敏感，匹配**显示名或文件名**（文件名 = `url.lastPathComponent` 去掉 `.app`）。
    ///
    /// 空查询 / 纯空白返回**原列表**（同一顺序，不重排、不复制模型）。
    static func filter(_ apps: [LauncherApp], query: String) -> [LauncherApp] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return apps }

        return apps.filter { app in
            app.name.localizedCaseInsensitiveContains(keyword)
                || app.url.deletingPathExtension().lastPathComponent
                    .localizedCaseInsensitiveContains(keyword)
        }
    }

    /// 降序比较，**`nil`（无数据）恒排在有数据之后**。
    ///
    /// 返回 `nil` = 这一键分不出先后（相等或两边都没数据）→ 交给下一个键。
    private static func isDescendingFirst<T: Comparable>(_ lhs: T?, _ rhs: T?) -> Bool? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return lhs == rhs ? nil : lhs > rhs
        case (nil, nil):
            return nil
        case (nil, _):
            return false   // 无数据排在有数据之后
        case (_, nil):
            return true
        }
    }
}
