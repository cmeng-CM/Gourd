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
//  p7 追加一层（`LauncherPartition` / `LauncherQuickDrop`，docs/31 §接口与数据形状 2）：
//  **上区（快捷启动）的顺序 = 固定先后**（`pinnedIDs` 的表序，2026-10-19 起可在上区拖动重排），
//  **不**用 rank 序——上区只回答「我固定的先后」，Spotlight 数据与下区的重排都影响不到它。`rank` 的「固定项恒在前」服务的是
//  「固定项还混在网格里」时的旧行为（下区如今由分区剔除固定项），是另一件事：分区在 `rank`
//  之外另起一层，`rank` 的既有语义一行不改。两区都是纯函数：不读 `Defaults`、不落盘。
//
//  2026-10-19 追加 `LauncherQuickReorder`：上区内部可**拖动排序**——落点仍是那张
//  `pinnedIDs` 表（顺序即用户看到的顺序），因此不新增第二份状态；纯函数只算新表，落盘仍走
//  `LauncherPins`。方向判定见 `moving(_:onto:in:)` 的注释。
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

// MARK: - 启动台两区（p7：上区「快捷启动」/ 下区网格）

/// 排名清单 → 上下两区（docs/31-home-workday-launcher.md §接口与数据形状 2）。
///
/// 纯函数：`ranked` 与 `pinnedIDs` 都只读不改；不碰 `Defaults`、不落盘（见文件头契约）。
enum LauncherPartition {

    /// quick = `pinnedIDs` 顺序（过滤掉本次扫描里不存在的 id；重复 id 保留首次）；
    /// grid  = `ranked` 中剔除固定项后的原顺序（**保序**，不重排）。
    static func split(ranked: [LauncherApp], pinnedIDs: [String])
        -> (quick: [LauncherApp], grid: [LauncherApp]) {
        // id → 清单里那一项（同 id 在 `ranked` 里出现多次时只认第一次出现的那个）
        var appsByID: [String: LauncherApp] = [:]
        for app in ranked where appsByID[app.id] == nil {
            appsByID[app.id] = app
        }

        var quick: [LauncherApp] = []
        var emitted: Set<String> = []
        for id in pinnedIDs {
            // 未知 id 不占位（已卸载 / 已移动的 App 留下的残留）；同 id 的重复项保留首次
            guard !emitted.contains(id), let app = appsByID[id] else { continue }
            emitted.insert(id)
            quick.append(app)
        }

        let pinnedSet = Set(pinnedIDs)
        return (quick: quick, grid: ranked.filter { !pinnedSet.contains($0.id) })
    }
}

/// 拖放落在哪一区（`onDrop` 容器一侧的目标，docs/31 §接口与数据形状 2）。
enum LauncherDropRegion { case quick, grid }

/// 拖放 → 新的固定表（**纯函数、不落盘**——落盘由 `LauncherStore` 经 `LauncherPins` 完成）。
enum LauncherQuickDrop {

    /// 返回新的 pinned 表；**no-op（返回 nil）四种**：未知 id（含外来文本）；`quick` 收到已固定；
    /// `grid` 收到未固定；空 id。
    ///
    /// quick：`LauncherPinning.adding(draggedID, to: pinnedIDs)`（追加表尾）；
    /// grid ：`LauncherPinning.removing(draggedID, from: pinnedIDs)`（移除全部同 id）。
    ///
    /// **返回值是「这次拖放等价于哪种写入」的判定结果，不是消费方要赋的值**：消费者（视图）只用
    /// 非 nil / nil 分流——非 nil 时改叫 `LauncherStore.pin` / `.unpin`，落盘由 store 经
    /// `LauncherPins` 完成（先落盘再刷新）。那条写入与本函数返回的表**等价**：两个入口
    /// （拖放、右键菜单）的语义同源于 `LauncherPinning` 的 adding / removing，因此盘上的值
    /// 与这里的判定一致，且全模块只有一条落盘路径。
    ///
    /// 「未知」的判据是 `knownIDs`（调用方传本次扫描的 `Set(apps.map(\.id))`）——本函数因此
    /// 不查 Spotlight、不读 `Defaults`，「纯函数、无副作用」的文件头契约不破。
    static func resolve(draggedID: String, target: LauncherDropRegion,
                        pinnedIDs: [String], knownIDs: Set<String>) -> [String]? {
        guard !draggedID.isEmpty, knownIDs.contains(draggedID) else { return nil }

        switch target {
        case .quick:
            guard !LauncherPinning.isPinned(draggedID, in: pinnedIDs) else { return nil }
            return LauncherPinning.adding(draggedID, to: pinnedIDs)
        case .grid:
            guard LauncherPinning.isPinned(draggedID, in: pinnedIDs) else { return nil }
            return LauncherPinning.removing(draggedID, from: pinnedIDs)
        }
    }
}

// MARK: - 启动台上区手动排序

/// 上区「快捷启动」内部的**拖动排序**（2026-10-19 用户要求）。
///
/// 数据仍是同一张 `pinnedIDs` 表：上区的显示顺序 = 表序，手动排序 = 改表序，
/// 因此不需要第二份「顺序」状态，也不会出现「屏幕上一套、盘上另一套」。
///
/// 纯函数、不落盘：只回答「这次拖动等价于哪张新表」，写入由 `LauncherStore.reorder`
/// 经 `LauncherPins.move` 完成（先落盘再刷新，与固定 / 取消固定同一条接缝）。
enum LauncherQuickReorder {

    /// 把 `draggedID` 挪到 `targetID` 的位置，返回新表；**nil = 不写盘**。
    ///
    /// **方向**（拖拽项当前在目标之前 / 之后决定落点在目标之后 / 之前）：
    /// - 拖拽项在目标**之前** → 落在目标**之后**（往后拖一格就是互换，拖到最后一项 = 移到表尾；
    ///   否则永远「差一格」，把首项拖到末项会停在倒数第二位）；
    /// - 拖拽项在目标**之后** → 落在目标**之前**（往前拖同理：拖到首项 = 移到表首）。
    ///
    /// 这等价于「占目标那一格」：相邻两项双向拖动都是互换，非相邻拖动落在目标的近侧。
    ///
    /// 返回 nil 的四种（与 `LauncherQuickDrop.resolve` 同口径的 no-op）：
    /// 拖拽项与目标相同；拖拽项不在表里（未固定 / 外来 id）；目标不在表里；挪完与挪前相同。
    /// 同 id 的脏数据（手改 `UserDefaults` 塞重复项）一并清掉、只留一份——与
    /// `LauncherPinning.removing` 的重复项口径一致。
    static func moving(_ draggedID: String, onto targetID: String,
                       in pinnedIDs: [String]) -> [String]? {
        guard draggedID != targetID,
              let draggedIndex = pinnedIDs.firstIndex(of: draggedID),
              let targetIndex = pinnedIDs.firstIndex(of: targetID)
        else { return nil }

        // 先移除拖拽项（连同重复项），再在**剩下的表**里找目标：目标的下标因此不会因移除而错位。
        let remaining = pinnedIDs.filter { $0 != draggedID }
        guard let targetIndexInRemaining = remaining.firstIndex(of: targetID) else { return nil }

        let insertIndex = draggedIndex < targetIndex
            ? targetIndexInRemaining + 1   // 往后拖：落在目标之后
            : targetIndexInRemaining       // 往前拖：落在目标之前
        var updated = remaining
        updated.insert(draggedID, at: insertIndex)

        return updated == pinnedIDs ? nil : updated
    }
}
