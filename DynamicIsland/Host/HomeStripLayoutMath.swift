//
//  HomeStripLayoutMath.swift
//  Gourd 宿主 · 首页 strip 宽度分配（P2 批次 / T1）
//
//  **纯几何，无 SwiftUI**：本文件只做算术，不引入任何 SwiftUI 符号（P2 全局约束）——
//  分配规则与渲染分离，规则才能被单测穷举（`DynamicIslandTests/HomeStripLayoutTests.swift`）。
//
//  规格逐字沿用 docs/17-nookx-adoption.md §接口与数据形状 5 的三条规则；`leftover` 的口径
//  按 T1 审查裁定改为「**未被使用的尾部空间总量**」（原「非规则 ① 恒为 0」的说法在恰好放满
//  与丢块路径下都与实际不符，见 `.workflow/p2-home-strip/reports/T1.md`）。
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
        /// **未被使用的尾部空间总量**：
        /// `max(0, available - sum(widths) - spacing × max(0, visibleCount-1))`。
        ///
        /// 三条规则共用这一个式子：规则 ① 是富余量、规则 ② 是向下取整剩下的零头
        ///（≤ 0.5 × 块数）、规则 ③ 是丢块空出来的空间（可达数百 pt；恰好用满时为 0）。
        /// **它不等于 0 不代表块被铺满**——丢块路径下宽度取的是各自 `min`，
        /// 与可用宽度无关，T3 若拿它做尾部对齐/铺满判据必须先看 `visibleCount`。
        public let leftover: CGFloat
    }

    /// 分配规则（三条，**按序判定**，命中即返回）：
    ///
    /// 1. **富余**（`available >= sum(ideal) + spacing × (n-1)`）：`widths == ideal`——
    ///    块保持理想宽度、**不拉伸**（D-02），余量留在尾部。
    /// 2. **不足但够最小宽度和**（`available >= sum(min) + spacing × (n-1)`）：按可压缩量等比压缩，
    ///    每块 `min + (ideal - min) × (1 - deficit / compressible)`，再**向下取整到 0.5pt**
    ///   （`floor(x × 2) / 2`：乘以 2 是精确的 2 的幂缩放，向下取整后每块必 ≤ 压缩前的值，
    ///    因此总和不越界、无需事后收敛）。其中
    ///    `deficit = sum(ideal) - (available - spacing × (n-1))`、
    ///    `compressible = sum(ideal - min)`；`compressible == 0` 时全部取 `min`（防御分支）。
    /// 3. **连最小宽度和都不够**：从**尾部**逐块丢弃，直到
    ///    `sum(min) + spacing × max(0, k-1) <= available`（D-03：丢块比压扁更可读）；
    ///    若单块也放不下，则只保留第一块、宽度为 `max(0, available)`（不为负）。
    ///
    /// 空数组：`widths == []`、`visibleCount == 0`、`leftover == available`。
    ///
    /// **前置条件（调用方保证，本函数不做防御）**：`items` 的 `min` / `ideal` 与 `available`
    /// 都是有限数，且 `0 <= min <= ideal`、`spacing >= 0`。本批不加运行时守卫——非有限输入
    ///（NaN / ±∞）会静默产出 NaN 宽度，坏输入应由调用点自己挡住（生产调用点的取值是宿主写死的
    /// 宽度声明，见 docs/17 §接口与数据形状 6）。
    ///
    /// **不变量**（三条）：`widths.count == visibleCount`；`widths.allSatisfy { $0 >= 0 }`；
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

        let widths: [CGFloat]
        let visibleCount: Int

        if available >= sumIdeal + gaps {
            // ① 富余：不放大，余量留尾部
            widths = items.map(\.ideal)
            visibleCount = count
        } else if available >= sumMin + gaps {
            // ② 不足但够最小宽度和：按可压缩量等比压缩，向下取整到 0.5pt
            let compressible = items.reduce(CGFloat.zero) { $0 + ($1.ideal - $1.min) }
            let deficit = sumIdeal - (available - gaps)
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
            visibleCount = count
        } else {
            // ③ 连最小宽度和都不够：从尾部逐块丢弃
            var keep = count
            var keptMinSum = sumMin
            while keep > 1, keptMinSum + spacing * CGFloat(keep - 1) > available {
                keptMinSum -= items[keep - 1].min
                keep -= 1
            }
            if keptMinSum + spacing * CGFloat(max(0, keep - 1)) <= available {
                widths = items.prefix(keep).map(\.min)
                visibleCount = keep
            } else {
                // 单块也放不下：只保留第一块，宽度 = 可用宽度（不为负）
                widths = [max(0, available)]
                visibleCount = min(1, count)
            }
        }

        // `leftover` 只有一个口径：**未被使用的尾部空间总量**（三条规则共用这个式子）
        let used = widths.reduce(CGFloat.zero) { $0 + $1 } + spacing * CGFloat(max(0, visibleCount - 1))
        return Plan(widths: widths, visibleCount: visibleCount, leftover: max(0, available - used))
    }
}
