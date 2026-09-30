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
//  P2 丢块提示批次 / T1 增量：`plan` 多一个入参 `tailReserve`（缺省 0 = 改动前的行为）与两个出参
//  `droppedCount` / `tailReserveUsed`——「这次会不会丢块、丢了几块」由**纯函数**回答，视图只负责画
//  那个 `＋N`（`HomeStripView.droppedHintWidth` 是预留位宽度的唯一取值）。三条规则本体一行未动，
//  搬进私有 `distribute`（基线与预留版共用）；判定三步见 `plan` 的文档（docs/21 §做法 机制一、D-02）。
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
        ///
        /// **预留版的 `leftover` 不把预留位加回来**：它按缩减后的宽度算
        /// （`max(0, available − tailReserve − used)`），口径与基线是同一个式子——
        /// 「这一份 plan 的未使用尾部空间」。**渲染侧不得拿它反推提示位坐标**
        ///（[docs/17](../../docs/17-nookx-adoption.md) 已知限制 11：它不是对齐依据）。
        public let leftover: CGFloat
        /// **被整块丢掉的块数**：`items.count - visibleCount`（空数组为 0）。
        /// 与 `tailReserve` 无关——预留版这个数可能比基线更大（边界处多丢一块，docs/21 §已知限制 6），
        /// 条尾的 `＋N` 显示的就是它。
        public let droppedCount: Int
        /// 本次是否**真的占了**尾部预留位：真 = 下面这份宽度是按 `available − tailReserve` 分配出来的；
        /// 假 = 预留位不存在（那份宽度一个字节都没用上，`widths` 来自完整可用宽度的基线）。
        /// 判定见 `plan(items:available:spacing:tailReserve:)` 的三步。
        public let tailReserveUsed: Bool
    }

    /// 分配入口：**尾部预留位在纯函数里定，不在视图里拍脑袋**（docs/21 §做法 机制一）。
    ///
    /// `tailReserve == 0`（缺省）时**逐字等于改动前的行为**（就是 `distribute` 的返回值）——
    /// 既有用例与生产布局的宽度分配都不变（D-02）。
    ///
    /// **三步判定**（顺序固定，①②③）：
    /// 1. 按**完整** `available` 算一次（**基线**）。基线没丢块 → 原样返回、`tailReserveUsed = false`：
    ///    不丢块的时候预留位不存在（`tailReserve` 传了也不生效——它是为「有块被丢」准备的）。
    /// 2. 基线丢了块、且 `tailReserve > 0` → 按 `max(0, available - tailReserve)` 再算一次（**预留版**）。
    ///    预留版还能显示 ≥ 1 块 → 返回预留版、`tailReserveUsed = true`（`visibleCount` 已扣掉预留位）。
    ///    **首块放得下时预留不会让块变窄**：规则 ③ 下每块取各自的 `min`（与可用宽度无关），因此只可能改变
    ///    丢块数；可用宽 < 首块最小宽时规则 ③ 的 `max(0, available)` 兜底会让预留版更窄（调用方违约、生产不可达）。
    /// 3. 预留版一块都放不下（宽度太小）→ 退回基线、`tailReserveUsed = false`：连块都没有的时候，
    ///    一个孤零零的 `＋N` 没有意义。
    ///    **今天这条分支不可达**：规则 ③ 对非空 `items` 至少保住第一块（`keep` 停在 1），
    ///    因此预留版的 `visibleCount >= 1` 恒成立；留着它是契约的一部分，也给规则将来的变化一条确定行为。
    ///
    /// - Parameter tailReserve: 尾部预留位宽度（`<= 0` 视为不预留）。
    public static func plan(
        items: [Item],
        available: CGFloat,
        spacing: CGFloat,
        tailReserve: CGFloat = 0
    ) -> Plan {
        // ① 基线：完整可用宽度
        let baseline = distribute(items: items, available: available, spacing: spacing)
        guard baseline.droppedCount > 0, tailReserve > 0 else { return baseline }

        // ② 预留版：把尾位从可用宽度里扣掉再算一次
        let reserved = distribute(items: items, available: max(0, available - tailReserve), spacing: spacing)
        // ③ 预留版一块都放不下 → 提示不显示（退回基线）
        guard reserved.visibleCount >= 1 else { return baseline }

        return Plan(
            widths: reserved.widths,
            visibleCount: reserved.visibleCount,
            leftover: reserved.leftover,
            droppedCount: reserved.droppedCount,
            tailReserveUsed: true
        )
    }

    /// 分配规则本体（三条，**按序判定**，命中即返回）——`plan` 的基线与预留版都走这一份：
    /// 差别只在传进来的 `available`（`tailReserveUsed` 恒为 `false`，预留判定在外层）。
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
    private static func distribute(items: [Item], available: CGFloat, spacing: CGFloat) -> Plan {
        guard !items.isEmpty else {
            return Plan(widths: [], visibleCount: 0, leftover: available, droppedCount: 0, tailReserveUsed: false)
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
        return Plan(
            widths: widths,
            visibleCount: visibleCount,
            leftover: max(0, available - used),
            droppedCount: count - visibleCount,
            tailReserveUsed: false
        )
    }
}
