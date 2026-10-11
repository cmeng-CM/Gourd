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
//  StatsModule.swift
//  Gourd 内置模块 · 系统统计（CPU / 内存 / GPU）首页块（p3-widgets / T2）
//
//  docs/26-home-widgets-and-settings.md §接口与数据形状 的 stats 行逐字落地：**首页块 + 一个开关**。
//  上游 `TabSelectionView` 里那条 `if enableStatsFeature { … view: .stats }` 与
//  `enabledStandardTabCount()` 里对应的 `+1` 同批删除——展开面板的统计 tab 从此不复存在，
//  统计只剩首页块这一处呈现（D-02：用户说「不需要单独面板」）。
//
//  六条刻意写死的口径（改动前先读）：
//
//  1. **只声明 `home`**（与 mirror / music 同口径）：`.expanded` / `.compact` / `.lockscreen`
//     一律答 `.none`（不占位、不算失败，06 §3.2）。因为不声明 `expanded`，`isTabVisible()`
//     对本模块无意义（投影先按 `surfaces` 过滤），因此**不重写**它——写一条 `= true` 只会让读者
//     以为本模块有 tab。
//  2. **启用真源是 `enableStatsFeature`**（`takeoverEnableKey`，D-02）：组合根的启用门直接读它，
//     `moduleEnableOverrides` 与 `manifest.defaultEnabled` 都不再看——「模块开不开」与
//     「统计功能开不开」是同一个布尔量，不存在第二份状态。组件页那张卡拨的就是它
//     （`ModuleEnablementWrite` 对非 nil 接管键写上游键）。
//  3. **宽度声明 = 220 / 300**（26 §做法 机制一 给统计的定值，比进度宽一档）：三个环
//     （`StatsRingMetrics.regularRingDiameter` 46）+ 两个间距（10）= **158 ≤ 220**——最小块里
//     不裁不溢，判据与用例都在 `StatsRingMetrics.rowWidth(forWidth:)`（T9 / 机制八）。
//     **模块不参与块宽决策**（D-11 口径），分档只按 26 的定值；宿主 `HomeStripLayoutMath` 恒给 ≥ `min`。
//  4. **`config` 只登记不接管**（D-03 / §已知限制 1）：`enableStatsFeature` 是**真源键**
//     （= 本模块的 `takeoverEnableKey`），另三格图表可见性键是**登记键**——上游
//     `StatsSettings` 设置页仍读写它们（完整图的入口在那里，26 §备选与取舍 ②），模块侧
//     与 `ConfigHandle` 都不碰。默认值**从上游键取**（`Defaults.Keys.<键>.defaultValue`），
//     不另抄一个字面量——两处各写一个数就会漂。
//  5. **内容 = 三环并排**（T9 / 26 §做法 机制八 / D-11）：CPU / 内存 / GPU 各一个环，**环心百分比、
//     环下 9pt 标签**，**不画历史曲线**（完整图在设置页的统计设置里看）。三个环的**顺序与标签**
//     **沿用上游 `NotchStatsView` 那一套**（标签 key 就是它用的 `CPU` / `Memory` / `GPU` 三条），
//     值走 `StatsManager` 的 `*UsageString`（同一份 `StatsFormatting` 口径）——两个呈现面因此不漂。
//     形态对齐既有先例 `TodoScopeRing`（线宽与环心字号随直径退档、环轨 `white.opacity(0.12)`）。
//     **不画行首图标**（环的形态里没有它的位置：环心是数值、环下是标签）；`Row.symbolName` 随之删除。
//     **分色只在首页这一面**（CPU 青 / 内存 紫 / GPU 琥珀，取的是面板既有的系统色家族，不新造
//     hex）：上游那三张图画的是蓝 / 绿 / 紫，两面不同色这件事在报告里记了候选决策。
//  6. **采样驱动挂在块自己的生命周期上**（本模块的裁决，见「采样驱动」一节）：上游的
//     `StatsManager.startMonitoring()` 原先只由「展开面板停在统计 tab」触发
//     （`ContentView` 的 `updateMonitoringState(notchIsOpen:currentView:)`）。tab 摘掉后
//     `currentView == .stats` 不可达，采样永远不启动——首页块会是一排 `0.0%`。因此块在**可见期间**
//     保证采样在跑、消失时停：只在用户看着它的时候花这份电（与上游「统计 tab 可见才采样」同一个
//     功率档，不新增常驻轮询）。
//
//  文案走 Localizable key（06 §3.3 R5）：`module.stats.name` / `module.stats.summary`；
//  三行标签复用上游那三条 key（口径 5），不新增 `module.stats.row.*` 之类的第二套说法。
//

import Defaults
import SwiftUI

// MARK: - StatsModule

/// 系统统计接管模块（26 §接口与数据形状 的 stats 行）。
///
/// 渲染点 = 首页 strip 上的一块迷你条（本文件内私有视图），除它之外本模块不占任何 surface；
/// 数据源是上游 `StatsManager.shared`（本模块不采样、不持有定时器、不新增状态）。
@MainActor
final class StatsModule: GourdModule {
    /// 模块 id 的**唯一字面量**（manifest 与本文件的调用点共用；与 `ModuleRegistry.label(for:)`
    /// 的 `module.<shortID>.name` 形态一致）。
    static let moduleID = "com.cmeng.gourd.stats"

    /// 静态元数据（26 §接口与数据形状 + 本文件头六条口径）。
    ///
    /// - `surfaces: [.home]`：**只声明首页块**——展开 tab 已随本批删除（D-02：用户明确
    ///   「不需要单独面板」），折叠槽位本批不占（口径 1）；
    /// - `defaultPlacement: Placement(slot: nil, order: 50)`：`slot` 只在含 `compact` 时有意义，
    ///   这里只用 `order` 这个排序键（首页块序）。**50 = 排在 notifications（40）之后**——
    ///   统计没有对应的宿主内置块可继承序号（`HomeBlockOrdering.BuiltinBlock` 只有 music /
    ///   calendar / mirror），取「现有模块序号的最大值 + 10」把新块放尾部，老用户那条 strip 的
    ///   前几块因此一位都不动；
    /// - `defaultEnabled` = **上游键的默认值**（`enableStatsFeature` 上游默认 `false`）：它只在
    ///   「接管键读不到」时不生效，填它是为了让卡片上那行「默认关闭」按真源值出现
    ///   （启用状态由启用门直接读上游键，见口径 2）；
    /// - `permissions: []`：本模块只读进程内已有的采样结果（CPU / 内存 / GPU 计数由
    ///   `StatsManager` 用 Mach / IOKit 取），**不新增任何能力请求**、不新增网络请求。
    static let manifest = ModuleManifest(
        manifestVersion: 1,
        id: moduleID,
        name: LocalizedText(key: "module.stats.name"),
        summary: LocalizedText(key: "module.stats.summary"),
        icon: IconSpec(type: "symbol", name: "chart.xyaxis.line"),
        version: "1.0.0",
        apiVersion: HostInfo.currentAPIVersion,
        kind: "builtin",
        surfaces: [.home],
        defaultPlacement: Placement(slot: nil, order: 50),
        defaultEnabled: Defaults.Keys.enableStatsFeature.defaultValue,
        permissions: [],
        config: ConfigSchema(
            type: "object",
            properties: [
                // 上游总开关（= 本模块的 `takeoverEnableKey`）。默认值取上游键的默认值（口径 4）
                "enableStatsFeature": ConfigNode(
                    type: "boolean",
                    title: nil,
                    default: .bool(Defaults.Keys.enableStatsFeature.defaultValue),
                    values: nil,
                    itemType: nil
                ),
                // 三格图表可见性：**登记键**（口径 4）——上游 `StatsSettings` 仍在读写它们，
                // 本模块的迷你条恒画三行、不看它们（首页块不按开关减行：那会让块高矮跳变）。
                "showCpuGraph": ConfigNode(
                    type: "boolean",
                    title: nil,
                    default: .bool(Defaults.Keys.showCpuGraph.defaultValue),
                    values: nil,
                    itemType: nil
                ),
                "showMemoryGraph": ConfigNode(
                    type: "boolean",
                    title: nil,
                    default: .bool(Defaults.Keys.showMemoryGraph.defaultValue),
                    values: nil,
                    itemType: nil
                ),
                "showGpuGraph": ConfigNode(
                    type: "boolean",
                    title: nil,
                    default: .bool(Defaults.Keys.showGpuGraph.defaultValue),
                    values: nil,
                    itemType: nil
                ),
            ]
        )
    )

    private let context: ModuleContext

    init(context: ModuleContext) {
        self.context = context
    }

    /// 接管三件套之一：**启用真源 = 上游那个开关键本身**（口径 2 / D-02）。
    static var takeoverEnableKey: Defaults.Key<Bool>? { .enableStatsFeature }

    // 接管三件套之二 `isTabVisible()`：本模块**不重写**它——它不声明 `expanded`，投影先按
    // `surfaces` 过滤，可见性钩子对它永远不被问到（与 mirror / music 同一口径）。这里刻意留白。

    /// 接管三件套之三：宽度声明——**p13 起固定 145**（docs/38-home-v5-layout.md D-04 / §做法 五）。
    ///
    /// 沿革：原 220/300 是三环口径；docs/37 D-04 单行形态收到 220/240；p13 改**三行纵向**形态后
    /// 内容宽只要「12 点 + 8 + 标签 + 弹性 + 读数」约 96（最坏；见 `StatsRingMetrics` 的算式），
    /// 因此按 v5 设计稿取 **145 且不弹性**——环境带第一排的余量整份留给前台应用（用户原话：
    /// 「cpu 那三个宽度要降低，可以把第一排大部分内容留给前台应用」）。
    static var homeBlockWidth: ModuleHomeBlockWidth? {
        ModuleHomeBlockWidth(min: StatsRingMetrics.blockWidth, ideal: StatsRingMetrics.blockWidth)
    }

    /// 首页块**高度申报**（p13 / docs/38 D-10）：三行纵向 = 环境带档高（96）。
    ///
    /// 改前是单行 36（docs/37 D-04 把三环压成一行）；p13 用户要求三块在环境带里等高，
    /// 而三行「点 + 标签 …… 读数」的内容高是 70（`StatsRingMetrics.contentHeight`），
    /// 在 96 里纵向居中——余量在上下两侧各 13pt，正是设计稿里那三道行的位置。
    static var homeBlockHeight: ModuleHomeBlockHeight { .points(HomeEnvironmentBand.height) }

    /// 首页块的**区**（docs/38 D-02）：系统读数是**环境带**第三块。
    static var homeZone: ModuleHomeZone { .environment }

    /// **不吃余量**（D-04）：固定 145。三行读数的右缘与标签左缘之间本来就是弹性空隙，
    /// 拉宽只会把读数推得更远、更不好扫读。
    static var homeBlockAbsorbsSurplus: Bool { false }

    /// 只记一条日志：本模块不采样、不起 Task、不持有定时器（数据源是上游 `StatsManager.shared`）。
    func activate() async throws {
        context.logger.info(
            "stats 模块已激活（takeover=true，enableStatsFeature=\(Defaults[.enableStatsFeature])，monitoring=\(StatsManager.shared.isMonitoring)）"
        )
    }

    /// 没有要收的东西：采样驱动的停止在块的 `onDisappear`（块消失时它已停过一次），这里不重复调
    /// `stopMonitoring()`——面板重新打开时块会自己把采样再拉起来（口径 6）。
    func deactivate() async {}

    /// 只答 `home`：三环（T9）。`.expanded` / `.compact` / `.lockscreen` 一律 `.none`（口径 1）。
    func content(for request: ContentRequest) -> ModuleContent {
        switch request.surface {
        case .home:
            return .view(AnyView(StatsHomeBlockView()))
        case .expanded, .compact, .lockscreen:
            return .none
        }
    }
}

// MARK: - 尺寸（三行纵向，p13 / docs/38 D-10）

/// 统计块的**尺寸**（纯函数，无 SwiftUI 依赖；单测在 `TakeoverEnablementTests` 的统计一节）。
///
/// 口径（docs/38-home-v5-layout.md §做法 五 / D-10，2026-10-11 改判）：**三行纵向**，一行 = 指标色
/// 圆点（直径 12，含用量弧）+ 标签，右端是等宽读数；行高 18、行距 8、点距标签 8。
///
/// 沿革：三环并排（docs/26）→ 单行横向（docs/37 D-04，「就三项占了很大的区域」）→ **三行纵向**
/// （本批，用户「cpu 那三个宽度要降低……不要用进度条展示，改展现形式」）。改回纵向不是回到三环：
/// **没有 46pt 的环**，只有 12pt 的点 + 一道用量弧，读数是文字（不是环心百分比）。
///
/// **块宽 145 的算式**（必须容得下最坏一行，改常量时一起看用例）：
/// `点 12 + 点距 8 + 最坏标签（Memory，10.5pt ≈ 44）+ 弹性 + 最坏读数（「100.0%」，12pt 等宽 ≈ 44）`
/// = **108 ≤ 145 − 2 × 内容内缩 5 = 135**，余 27pt 弹性（右对齐的读数因此不会贴到标签上）。
enum StatsRingMetrics {
    /// 指标圆点直径。
    static let dotDiameter: CGFloat = 12
    /// 圆点外圈的线宽（轨道 + 用量弧）。
    static let dotTrackLineWidth: CGFloat = 2
    /// 圆点中心的实心直径。
    static let dotCoreDiameter: CGFloat = 4

    /// 一行的行高（点 / 标签 / 读数在这一档里居中）。
    static let rowHeight: CGFloat = 18
    /// 行与行之间的间距。
    static let rowSpacing: CGFloat = 8
    /// 点与标签之间的间距。
    static let labelSpacing: CGFloat = 8

    /// 轨/弧的不透明度（与既有 `TodoScopeRing` 同族）。
    static let trackOpacity: Double = 0.12

    /// 块的固定宽（`StatsModule.homeBlockWidth` 两个数都取它）。
    static let blockWidth: CGFloat = 145

    /// 三行的内容高（`3 × 18 + 2 × 8 = 70`）——块高 96 时上下各余 13（纵向居中）。
    static var contentHeight: CGFloat {
        CGFloat(StatsHomeBlockLayout.rows.count) * rowHeight
            + CGFloat(max(0, StatsHomeBlockLayout.rows.count - 1)) * rowSpacing
    }
}

// MARK: - 首页块（三行纵向）

/// 三环的三个指标：**顺序即显示顺序（CPU → 内存 → GPU）**。
///
/// 顺序与标签**逐字沿用上游 `NotchStatsView` 那一套**（口径 5）：标签 key 就是它
/// `String(localized: "CPU")` / `"Memory"` / `"GPU"` 用的那三条——首页块与展开图（今天在设置页
/// 预览）在用户眼里必须是同一种说法。**环不画行首图标**（T9 起形态是环：环心数值 + 环下标签，
/// 图标只在展开图里出现），因此上游那三个 SF Symbol 不再登记在这里。
///
/// 抽成枚举（而不是在视图里写死三行）是为了让单测能直接钉住「键 / 分色 / 值口径」
/// （`TakeoverEnablementTests` 的 manifest 契约用例逐条查这三行）。
enum StatsHomeBlockLayout {
    /// 一个指标。
    enum Row: String, CaseIterable, Identifiable {
        case cpu
        case memory
        case gpu

        var id: String { rawValue }

        /// 行标签的本地化 key（= 上游统计页用的那一条，见类型注释）。
        var labelKey: String {
            switch self {
            case .cpu: return "CPU"
            case .memory: return "Memory"
            case .gpu: return "GPU"
            }
        }

        /// 这一格的**指标色**（26 §做法 机制八：CPU 青 / 内存 紫 / GPU 琥珀）。
        ///
        /// 取的是**面板既有的系统色家族**里的三支（`.cyan` / `.purple` / `.orange`——它们在本产品
        /// 里都在用：磁盘图 `.cyan`、GPU 详情 `.purple`、待办与网络 `.orange`），**不新造一套 hex**。
        var ringColor: Color {
            switch self {
            case .cpu: return .cyan
            case .memory: return .purple
            case .gpu: return .orange
            }
        }

        /// 这一格的当前值文案：取 `StatsManager` 的 `*UsageString`（`StatsFormatting.percentage`
        /// 的既有口径，`%.1f%%`）——**不在这里另发明一个格式**，首页环心与统计页因此不可能显示两个数。
        func valueText(in stats: StatsManager) -> String {
            switch self {
            case .cpu: return stats.cpuUsageString
            case .memory: return stats.memoryUsageString
            case .gpu: return stats.gpuUsageString
            }
        }

        /// 环的进度（0…1）：`StatsManager` 的三个用量都是 0…100 的百分数，
        /// 这里夹到 0…1（越界值会画到环外）。
        func progressValue(in stats: StatsManager) -> Double {
            let percent: Double
            switch self {
            case .cpu: percent = stats.cpuUsage
            case .memory: percent = stats.memoryUsage
            case .gpu: percent = stats.gpuUsage
            }
            return min(max(percent / 100, 0), 1)
        }
    }

    /// 首页块要画的环（顺序 = `allCases` 的顺序：CPU → 内存 → GPU）。
    ///
    /// **恒三个环、不按块宽或图表开关减环**（口径 4/5）：块高矮跳变比少画一个环更烦人，
    /// 而 220 的最小块宽本来就是按三环算出来的（口径 3 / `StatsRingMetrics.rowWidth(forWidth:)`）。
    static let rows: [Row] = Row.allCases
}

/// 首页块：**三行纵向**——CPU / 内存 / GPU 各一行「指标色圆点（含用量弧）+ 标签 …… 读数」
/// （2026-10-11 / docs/38 D-10）。
///
/// **形态改判沿革**：三环并排（docs/26，内容只占 68pt 而块高 96，观感是大片留白）→ 单行横向
/// （docs/37 D-04，块高 36）→ **本批三行纵向 + 环境带档高 96**。用户 2026-10-11 的两条原话是
/// 「cpu 那三个宽度要降低，可以把第一排大部分内容留给前台应用」与「不要用进度条展示，没意义，
/// 改展现形式」——因此本批量的是**窄列里的三行**：宽 145 固定、点 + 标签在左、读数右对齐。
///
/// 三条保留：**恒三项、顺序不变（CPU → 内存 → GPU）**、**指标色**（青 / 紫 / 琥珀）、
/// **读数口径**（`Row.valueText`，与统计页同一个 `StatsManager`）。**进度不用进度条**——
/// 它是圆点外圈的那道**用量弧**（`trim`，指标色）：环里只剩「有多少」这一层信息，
/// 读数走等宽数字右对齐。
///
/// **纵向居中**（不再有 `homeBlockTopInset`）：三行内容高 70，块高 96，上下各余 13——
/// 与 v5 设计稿里那三道行的位置一致；顶部那 7pt 内缩的旧口径专为「图形贴板顶」而设，
/// 纵向居中之后没有要守的边界了。
///
/// **采样驱动**（口径 6）：块的 `.task` 里跑一个只做一件事的看门狗——`isMonitoring` 为假就
/// `startMonitoring()`（上游 `ContentView` 在「面板打开且不在统计 tab」时会 0.1s 后停掉采样，
/// 因为 `currentView == .stats` 已不可达；看门狗把这份驱动接过来）。块消失（`onDisappear`）
/// 时停采样：只在用户真的看着这块的时候花这份电。
///
/// 重绘靠 `@ObservedObject` 观察 `StatsManager`：采样每次写值（`@Published`）都会重画本块，
/// **不需要 `TimelineView`**（与待办 / 通知块同一手法）。
private struct StatsHomeBlockView: View {
    @ObservedObject private var stats = StatsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: StatsRingMetrics.rowSpacing) {
            ForEach(StatsHomeBlockLayout.rows) { row in
                StatsMetricRow(
                    row: row,
                    valueText: row.valueText(in: stats),
                    progress: row.progressValue(in: stats)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .task { await driveSampling() }
        .onDisappear { StatsManager.shared.stopMonitoring() }
    }

    /// 采样看门狗（口径 6）：1s 一跳，只在「采样没在跑」时把它拉起来；块消失时 `.task` 被取消，
    /// 循环随之结束（`onDisappear` 再把已启动的那条停掉）。
    ///
    /// 为什么是轮询而不是订阅 `$isMonitoring`：订阅会在**面板关着**时也把采样重启
    /// （上游停采样的那条路径是谁都能触发的），常驻采样是功率回归；轮询只在块可见期间存在，
    /// 且每次醒来只读一个布尔量。
    private func driveSampling() async {
        while !Task.isCancelled {
            if !StatsManager.shared.isMonitoring {
                StatsManager.shared.startMonitoring()
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

/// 一个指标（三行纵向里的一行）：**指标色圆点（含用量弧）+ 标签 + 右对齐等宽读数**。
///
/// 视觉机制逐字沿用三环时代的「科技风」（按指标分色 + 等宽数字，`Row.ringColor` / `monospacedDigit()`），
/// 只是把 46pt 的环收成 12pt 的「点 + 弧」、把百分比从环心移到行尾——一行的高从 68 收到 18，
/// 宽从 46 收到「点 + 标签 + 读数」（docs/38 D-10）。
private struct StatsMetricRow: View {
    let row: StatsHomeBlockLayout.Row
    let valueText: String
    let progress: Double

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                // ① 外圈：暗轨道（与三环时代同一族的白）。
                Circle()
                    .stroke(.white.opacity(StatsRingMetrics.trackOpacity), lineWidth: StatsRingMetrics.dotTrackLineWidth)

                // ② 用量弧：从 12 点方向按比例画，指标色的细一笔（12pt 直径下仍可读）。
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        row.ringColor,
                        style: StrokeStyle(lineWidth: StatsRingMetrics.dotTrackLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                // ③ 中心实心点：指标色，把「这是哪个指标」钉在颜色上（标签之外的第二重编码）。
                Circle()
                    .fill(row.ringColor)
                    .frame(width: StatsRingMetrics.dotCoreDiameter, height: StatsRingMetrics.dotCoreDiameter)
            }
            .frame(width: StatsRingMetrics.dotDiameter, height: StatsRingMetrics.dotDiameter)

            Text(LocalizedStringKey(row.labelKey))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .fixedSize()
                .padding(.leading, StatsRingMetrics.labelSpacing)

            Spacer(minLength: 4)

            // 读数：先拼 String 再给 `Text`（走 verbatim 重载，不做本地化查表）；等宽数字刷新不跳。
            Text(verbatim: valueText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(height: StatsRingMetrics.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
