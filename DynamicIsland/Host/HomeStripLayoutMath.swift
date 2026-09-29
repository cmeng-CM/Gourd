//
//  HomeStripLayoutMath.swift
//  Gourd 宿主 · 首页 strip 宽度分配（P2 批次 / T1）
//
//  **纯几何，无 SwiftUI**：本文件只做算术，不引入任何 SwiftUI 符号（P2 全局约束）——
//  分配规则与渲染分离，规则才能被单测穷举（`DynamicIslandTests/HomeStripLayoutTests.swift`）。
//
//  规格逐字沿用 docs/17-nookx-adoption.md §接口与数据形状 5（三条规则 + 四条不变量）。
//  决策：D-02（富余不拉伸：块保持理想宽度、余量留尾部）、D-03（不足不滚动不分页：
//  按最小宽度收敛，仍不足则按 `order` 从尾部丢块）。
//

import CoreGraphics

/// 首页 strip 的宽度分配：给定每块的 `min` / `ideal` 与可用宽度，算出每块拿多少 pt。
///
/// 输入顺序即**显示顺序**（宿主传 `homeEntries` 的顺序，已按 `(order, id)` 排好）：
/// 规则 ③ 丢块丢的是数组尾部，也就是 `order` 大的一端（D-03）。
public enum HomeStripLayoutMath {

    /// 一块的宽度约束（由 `HomeBlockWidthKey` 声明或测量得到）。
    public struct Item: Equatable {
        /// 该块能接受的最小宽度（低于它就不如不显示）。
        public let min: CGFloat
        /// 该块的理想宽度（富余时就用它，不放大）。
        public let ideal: CGFloat

        public init(min: CGFloat, ideal: CGFloat) {
            self.min = min
            self.ideal = ideal
        }
    }

    /// 一次分配的结果。
    public struct Plan: Equatable {
        /// 每块的分配宽度：下标与**输入 `items` 的前 `visibleCount` 项**一一对应。
        public let widths: [CGFloat]
        /// 从头开始可见的块数（恒等于 `widths.count`，分开给出是为了渲染侧可读）。
        public let visibleCount: Int
        /// 尾部余量：走规则 ① 时是 `available - sum(ideal) - spacing × (n-1)`（恰好放满时为 0），
        /// 其余情况恒为 0（规则 ② / ③ 都把宽度用满或主动丢弃）。
        public let leftover: CGFloat
    }

    /// 分配规则（三条，**按序判定**，命中即返回）：
    ///
    /// 1. **富余**（`available >= sum(ideal) + spacing × (n-1)`）：`widths == ideal`——
    ///    块保持理想宽度、**不拉伸**（D-02），余量留在尾部（`leftover`）。
    /// 2. **不足但够最小宽度和**（`available >= sum(min) + spacing × (n-1)`）：按可压缩量等比压缩，
    ///    每块 `min + (ideal - min) × (1 - deficit / compressible)`，再**向下取整到 0.5pt**
    ///   （`floor(x × 2) / 2`：向上取整会让总和越过可用宽度，违反不变量）。
    ///    其中 `deficit = sum(ideal) - (available - spacing × (n-1))`、
    ///    `compressible = sum(ideal - min)`；`compressible == 0` 时全部取 `min`（防御分支）。
    /// 3. **连最小宽度和都不够**：从**尾部**逐块丢弃，直到
    ///    `sum(min) + spacing × max(0, k-1) <= available`（D-03：丢块比压扁更可读）；
    ///    若单块也放不下，则只保留第一块、宽度为 `max(0, available)`（不为负）。
    ///
    /// 空数组：`widths == []`、`visibleCount == 0`、`leftover == available`。
    ///
    /// **不变量**（三条，规则 ① 与 ③ 的单块兜底同样满足）：
    /// `widths.count == visibleCount`；`widths.allSatisfy { $0 >= 0 }`；
    /// `sum(widths) + spacing × max(0, count-1) <= available`。
    public static func plan(items: [Item], available: CGFloat, spacing: CGFloat) -> Plan {
        guard !items.isEmpty else {
            return Plan(widths: [], visibleCount: 0, leftover: available)
        }

        let count = items.count
        // 间隙只存在于块与块之间（n-1 个）：单块与空数组都不乘 spacing。
        let gaps = spacing * CGFloat(max(0, count - 1))
        let sumIdeal = items.reduce(CGFloat.zero) { $0 + $1.ideal }
        let sumMin = items.reduce(CGFloat.zero) { $0 + $1.min }

        // ① 富余：不放大，余量留尾部
        if available >= sumIdeal + gaps {
            return Plan(
                widths: items.map(\.ideal),
                visibleCount: count,
                leftover: available - sumIdeal - gaps
            )
        }

        // ② 不足但够最小宽度和：按可压缩量等比压缩，向下取整到 0.5pt
        if available >= sumMin + gaps {
            let compressible = items.reduce(CGFloat.zero) { $0 + ($1.ideal - $1.min) }
            let deficit = sumIdeal - (available - gaps)
            let widths: [CGFloat]
            if compressible == 0 {
                // 无可压缩量（理论上进不来：compressible == 0 意味着 sumMin == sumIdeal，
                // 与本分支的 available < sumIdeal + gaps 矛盾）——真进来了就按最小宽度给。
                widths = items.map(\.min)
            } else {
                let scale = 1 - deficit / compressible
                widths = items.map { item in
                    let raw = item.min + (item.ideal - item.min) * scale
                    return (raw * 2).rounded(.down) / 2
                }
            }
            return Plan(
                widths: shavingOverflow(widths, gaps: gaps, available: available),
                visibleCount: count,
                leftover: 0
            )
        }

        // ③ 连最小宽度和都不够：从尾部逐块丢弃
        var keep = count
        var keptMinSum = sumMin
        while keep > 1, keptMinSum + spacing * CGFloat(keep - 1) > available {
            keptMinSum -= items[keep - 1].min
            keep -= 1
        }
        if keptMinSum + spacing * CGFloat(max(0, keep - 1)) <= available {
            return Plan(widths: items.prefix(keep).map(\.min), visibleCount: keep, leftover: 0)
        }

        // 单块也放不下：只保留第一块，宽度 = 可用宽度（不为负）
        return Plan(widths: [max(0, available)], visibleCount: min(1, count), leftover: 0)
    }

    /// 仲裁 #1 的兜底：向下取整后若总和仍越界（浮点残差），把差距从**最宽的那一块**继续扣，
    /// 每次 0.5pt，扣到不为负为止，直到 `sum(widths) + gaps <= available` 重新成立。
    ///
    /// **内部可见（非 public）**：规格里的 public 面只有 `plan(...)`。这条兜底在精确算术下
    /// 不可达（等比压缩的总和恰好等于可用宽度，向下取整只会更小），只有浮点残差才可能踩到，
    /// 因此留一个可直测的接缝由单测钉住（`HomeStripLayoutTests` 的 `shavingOverflow` 用例）。
    ///
    /// 终止性：调用点的分支判定保证 `available - gaps >= 0`，每轮要么把某块降 0.5、
    /// 要么在「最宽的一块已是 0」（即全部为 0）时退出——全部为 0 时总和必不越界。
    static func shavingOverflow(_ widths: [CGFloat], gaps: CGFloat, available: CGFloat) -> [CGFloat] {
        guard !widths.isEmpty else { return widths }

        var result = widths
        var total = result.reduce(CGFloat.zero) { $0 + $1 }
        while total + gaps > available {
            guard
                let widest = result.indices.max(by: { result[$0] < result[$1] }),
                result[widest] > 0
            else { break }
            result[widest] = max(0, result[widest] - 0.5)
            total = result.reduce(CGFloat.zero) { $0 + $1 }
        }
        return result
    }
}
