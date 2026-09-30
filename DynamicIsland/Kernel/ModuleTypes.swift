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
//  ModuleTypes.swift
//  Gourd 模块内核 · 类型层（P1 批次 / T1）
//
//  取值词汇表逐字沿用 docs/06-module-protocol.md（§3.1 / §6.1 / §6.2），
//  唯一增量是 P2 批次加的 `Surface.home`（docs/17-nookx-adoption.md §接口与数据形状 1）；
//  P2 接管批次 / T1 再加 `ModuleHomeBlockWidth`（docs/20-component-page.md §接口与数据形状 1）；
//  P3 组件批次 / T7 再加 `HomeFormFactor`（docs/26-home-widgets-and-settings.md §做法 机制六）；
//  本文件不含任何行为，只有共享的枚举与值类型。
//

import CoreGraphics
import Foundation

/// 一个首页块的**形态**：它属于哪条带（docs/26 §做法 机制六 / D-09）。
///
/// 首页自 T7 起分**两条带**：上面是主块带（沿用旧的 strip 语义——宽度不足时按序丢尾巴），
/// 下面是小组件带（网格换行、**放不下换行而不是丢块**）。归属哪条带由本取值**声明**，
/// **不由宽度反推**：宽度是布局的结果，不是块形态的原因。
///
/// - `.large`：需要面积的内容（音乐的封面 + 控制、镜子的摄像头画面）——主块带；
/// - `.compact`：一眼看得完的小组件（进度、统计、待办、通知、前台应用）——小组件带；**缺省值**。
///
/// 谁用：`GourdModule.homeFormFactor` 钩子（缺省 `.compact`）声明它；`ModuleRegistry.homeFormFactor(for:)`
/// 原样取给宿主，宿主按它把块名单切成两带（映射点只有 `HomeBandCatalog.resolve` 一处）。
public enum HomeFormFactor: String, Sendable, CaseIterable {
    /// 大块：主块带（上）。理想宽不拉伸、不足按最小宽压缩、仍不足按序丢块（旧 strip 语义）。
    case large
    /// 紧凑块：小组件带（下）。网格换行，**只有连一行都放不下时才丢块**。
    case compact
}

/// 首页块宽度的**内核侧**取值形态（`min` = 低于它不如不显示，`ideal` = 富余时用它）。
///
/// 谁用：接管模块的 `GourdModule.homeBlockWidth` 钩子（docs/20-component-page.md §接口与数据形状 1）
/// 声明它接住的那一块原本的宽度（镜子 140/160、音乐 300/420）；`ModuleRegistry.homeBlockWidth(for:)`
/// 原样取给宿主。缺省（钩子答 nil）= 用宿主统一值 180/240（docs/17 D-11）。
///
/// **与 Host 的 `HomeBlockWidth` 同形不同名**：那个是渲染层的布局值（`HomeBlockWidthKey`
/// 也是渲染层的 `LayoutValueKey`），内核不认识它——映射在 `HomeStripView` 一处（3 行）。
public struct ModuleHomeBlockWidth: Sendable, Equatable {
    /// 低于它不如不显示（`HomeStripLayoutMath` 判丢块用的下界）。
    public let min: CGFloat
    /// 富余时用它。
    public let ideal: CGFloat
}

/// 06 §6.1 的 surface：模块内容可以出现在哪里。
///
/// | 取值 | 语义 | 承载 |
/// |---|---|---|
/// | `compact` | 折叠态 | 槽位（`Slot`） |
/// | `expanded` | 展开面板 | 展开区的 tab |
/// | `lockscreen` | 锁屏小组件 | 锁屏 widget |
/// | `home` | 展开面板**首页的一条 strip 块** | 首页横向 strip（P2 批次新增） |
///
/// `home` 与 `compact` / `expanded` **并列**（docs/17-nookx-adoption.md §接口与数据形状 1）：
/// 声明它 = 「这个模块愿意在首页 strip 里占一块」，与「有没有展开 tab」（`expanded`）互不蕴含。
///
/// **既有校验规则不变**：`surfaces` 仍是非空子集，元素合法性由本枚举的解码保证
///（`ModuleManifest.validate()` 只管「非空」这一条，不认识有哪些取值）；`defaultPlacement`
/// 仍只在含 `compact` 时有意义，首页块的顺序只是复用 `defaultPlacement.order` 这个排序键（D-04）。
///
/// 不新增 `hud` 之类的 surface——瞬时浮层是 `expanded` 的一种呈现方式（06 §6.1）。
/// `lockscreen` 本批不声明（D-12，ADR-0011 第 4 条「锁屏维持现状」）。
public enum Surface: String, Codable, Sendable, CaseIterable {
    case compact
    case expanded
    case lockscreen
    case home
}

/// 06 §6.2 的槽位模型：仅在 `surface == .compact` 时有意义。
public enum Slot: String, Codable, Sendable, CaseIterable {
    case left
    case right
    case center
}

/// 06 §3.1 的四态。
///
/// **本批（D-04「包装 / 观测」路线）只有 `collapsed` / `expanded` 可达**：
/// - `hoverPreview` 需要把上游 `ContentView.isHovering`（`@State private`，类外不可观测）
///   提升为可观测量；
/// - `dragging` 需要内核订阅拖拽布尔量（`dragDetectorTargeting` / `anyDropZoneTargeting`）；
///
/// 两者都属 P1-2 的 `NotchStateMachine`（见 docs/13-runtime-kernel.md「已知限制」5）。
/// 本批先把四态定死，避免 P1-2 改协议。
public enum NotchPhase: String, Codable, Sendable, CaseIterable {
    case collapsed
    case hoverPreview
    case expanded
    case dragging
}

/// 06 §3.1：这一次 `content(for:)` 是被什么触发的。
/// 本批只有 `initial` 会被真实产生（唯一生产点 `ModuleHostView.swift:35`）；`redraw` 虽在
/// 枚举里、但宿主当前与 `initial` 走同一条同步取内容路径，`event` / `tick` / `configChanged`
/// 依赖 P1-3 的事件总线与配置存储。
public enum ContentRequestReason: String, Codable, Sendable {
    case initial
    case event
    case configChanged
    case tick
    case redraw
}
