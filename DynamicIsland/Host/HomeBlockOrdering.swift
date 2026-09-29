//
//  HomeBlockOrdering.swift
//  Gourd 宿主 · 首页块顺序（覆盖表 + 默认序号）（P1 批次 / T3）
//
//  首页 strip 的块顺序不再写死：**用户覆盖优先、缺键回落默认序号、同序号按 id 字典序**。
//  默认序号有两个来源——内置块取它们写死的既有顺序（音乐 0 → 日历 1 → 镜子 2），模块块取
//  `manifest.defaultPlacement.order`（`ModuleHomeEntry.order`）。覆盖表是 `Defaults` 的
//  `homeBlockOrder`（键 = 块 id，值 = 序号），**只有用户真的点过设置页的上移 / 下移才写**。
//
//  本文件是**纯逻辑**：没有 SwiftUI / Defaults 依赖（`overrides` 由调用方读盘后注入），
//  因此 `sorted` / `moved` / `table` 都能用固定输入单测（docs/18 §接口与数据形状 1）。
//
//  规格：docs/18-p1-todos-and-order.md §接口与数据形状 1/2、§改动点设计 3/4、
//  §兼容迁移与回滚「旧数据语义」。
//

import Foundation

/// 首页块名单的排序与「上移 / 下移」的序号重算（纯函数）。
enum HomeBlockOrdering {

    // MARK: - 内置块词汇表

    /// 宿主内置块的稳定 id 与默认序号——**覆盖表的键**。
    ///
    /// **日历块已移除**（2026-09-29 起首页的日历改由 strip 下面那条全宽日历行
    /// `HomeCalendarRow` 承担，见 `HomeStripView` 文件头）：`.calendar` 只保留 id 与默认序号的
    /// **既有含义**（老用户表里可能已有这个键，它的名字不能被别的块占用），
    /// **任何名单都不再生成它**——别复活它。
    enum BuiltinBlock: String, CaseIterable {
        case music
        case calendar
        case mirror

        /// 覆盖表里的键：`builtin.music` / `builtin.calendar` / `builtin.mirror`。
        var id: String { "builtin.\(rawValue)" }

        /// 缺键时的默认序号：音乐 → 日历 → 镜子（= 改动前写死的三块顺序）。
        /// 日历不出现在任何名单里，它的 1 只留给老表里的历史值。
        var defaultOrder: Int {
            switch self {
            case .music: return 0
            case .calendar: return 1
            case .mirror: return 2
            }
        }
    }

    // MARK: - 排序

    /// 首页块名单排序：**覆盖值优先 → 缺键用 `defaultOrder` → 同值按 `id` 字典序**。
    ///
    /// - Parameters:
    ///   - items: 待排序的块（内置块 + 模块块合成的一张名单）。
    ///   - defaultOrder: 该块的默认序号（内置块给 `BuiltinBlock.defaultOrder`，模块块给
    ///     `ModuleHomeEntry.order`）。
    ///   - id: 该块的稳定 id（覆盖表的键）。
    ///   - overrides: 覆盖表（`Defaults[.homeBlockOrder]`）。
    ///
    /// **未知 id 不参与排序**：表里出现、而 `items` 里没有的键（模块被移除 / 改名 / 日历块这类
    /// 不再生成的块）不产生任何效果——既不占位、也不报错、更不会让某个块消失。
    /// 反向也成立：`items` 里的每一项都出现在返回值里（只定顺序，不丢条目）。
    ///
    /// 全键都比不出高下时（同序号又同 id，生产路径不可达：id 在名单里唯一）由 `sorted` 的
    /// 实现决定先后，不承诺稳定——两条不可区分的输入的相对顺序没有语义。
    static func sorted<T>(
        _ items: [T],
        defaultOrder: (T) -> Int,
        id: (T) -> String,
        overrides: [String: Int]
    ) -> [T] {
        items
            .map { (element: $0, rank: overrides[id($0)] ?? defaultOrder($0), id: id($0)) }
            .sorted { ($0.rank, $0.id) < ($1.rank, $1.id) }
            .map(\.element)
    }

    // MARK: - 上移 / 下移

    /// 调整方向（设置页只提供这两个动作，不引入拖拽——docs/18 §备选与取舍）。
    enum MoveDirection { case up, down }

    /// 把 `id` 在名单里上移 / 下移一位（与相邻的一项互换），返回新名单。
    ///
    /// **越界（已在顶 / 底）与 id 不在名单里 → 原样返回**：不抛错、不改动。设置页据此把首行的
    /// 「上移」、末行的「下移」置灰，但纯函数自身对这两种输入也必须有确定行为。
    static func moved(_ ids: [String], moving id: String, direction: MoveDirection) -> [String] {
        guard let index = ids.firstIndex(of: id) else { return ids }
        let destination = direction == .up ? index - 1 : index + 1
        guard ids.indices.contains(destination) else { return ids }
        var result = ids
        result.swapAt(index, destination)
        return result
    }

    /// 整表序号：名单顺序即序号（0 起）。
    ///
    /// **写入口径（本批选定「整表覆盖」）**：一次移动就把**当前可见名单整表**写成 `0…n-1`，
    /// 而不是只写被移动的那一格。理由：只写一格会与「没被写过的邻居仍拿默认序号」混在一起——
    /// 默认序号之间空隙很大（todos 20 / notifications 40），写进去的 0 / 1 会被挤到别处，
    /// 屏幕上看到的顺序与刚落盘的数值对不上；整表覆盖让「表里的值 = 屏幕上看到的顺序」，
    /// 重开也一致。代价：用户动过一次之后，未动过的块也不再享受 manifest 的默认序号
    /// （表里没有的块——比如关掉的内置块——仍完全回落默认序号；新装模块的默认序号会排在
    /// 整表序号之后，也就是落在末尾一侧）。
    ///
    /// 重复 id 取**首次出现**的序号（不崩：`Dictionary(uniqueKeysWithValues:)` 会在重复键上
    /// 触发陷阱，而名单是调用方给的，纯函数不该有可崩的输入）。
    static func table(for ids: [String]) -> [String: Int] {
        var table: [String: Int] = [:]
        for (index, id) in ids.enumerated() where table[id] == nil {
            table[id] = index
        }
        return table
    }
}
