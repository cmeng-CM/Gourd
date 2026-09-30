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

    /// 接管三件套之三：首块宽度声明 = **26 §做法 机制一 给统计的定值 220 / 300**（口径 3）——
    /// 比模块统一值（180 / 240）宽一档：三行「标签 + 值 + 细条」需要更多固定宽度。
    static var homeBlockWidth: ModuleHomeBlockWidth? { ModuleHomeBlockWidth(min: 220, ideal: 300) }

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

// MARK: - 三环的尺寸与取舍

/// 三环的**尺寸与取舍**（纯函数，无 SwiftUI 依赖；单测在 `TakeoverEnablementTests` 的统计一节）。
///
/// 口径（docs/26-home-widgets-and-settings.md §做法 机制八 / D-11，用户 2026-09-30 追加指示）：
/// 三个环并排，直径 **46pt**（块宽 < 200 时退 **40pt**），环间距 **10pt**；
/// 进度 = 2pt 亮描边叠在 5pt 主环上，环轨 `white.opacity(0.12)`；环心百分比、环下 9pt 标签。
///
/// **「不裁」是一句可断言的话**（不是感觉）：宿主给统计块的最小宽是 220
/// （`StatsModule.homeBlockWidth.min`），而 `rowWidth(forWidth: 220) = 3 × 46 + 2 × 10 = 158 ≤ 220`。
/// 块更窄时直径退一档（40）——算得出来、钉得住，因此不必靠上屏目测。
enum StatsRingMetrics {
    /// **环直径的唯一判据**：块宽 < `compactThreshold` 退一档。
    ///
    /// 宽取不到（首帧 0 / NaN / 无穷）时给**小档**：宁可画小一点，也不要画出被裁的三个环。
    static func ringDiameter(forWidth width: CGFloat) -> CGFloat {
        guard width.isFinite else { return compactRingDiameter }
        return width < compactThreshold ? compactRingDiameter : regularRingDiameter
    }

    /// 常规档直径（26 §做法 机制八 的定值）。
    static let regularRingDiameter: CGFloat = 46
    /// 紧凑档直径（块宽不到 `compactThreshold` 时）。
    static let compactRingDiameter: CGFloat = 40
    /// 常规 / 紧凑两档的**分界**（`< 200` 退档；200 本身仍是常规档，阈值取闭区间下界）。
    static let compactThreshold: CGFloat = 200

    /// 三个环的间距（机制八 的定值：`46 × 3 + 10 × 2 = 158`）。
    static let ringSpacing: CGFloat = 10

    /// 主环线宽（5pt）——亮描边（2pt）压在它上面，读起来像「通电的环」。
    static let mainLineWidth: CGFloat = 5
    /// 亮描边线宽（2pt）：**比主环亮**，是进度的那一笔。
    static let highlightLineWidth: CGFloat = 2
    /// 主环的不透明度：比亮描边暗一档（同一支指标色，"环带 + 灯丝"的层次）。
    static let mainRingOpacity: Double = 0.45
    /// 环轨不透明度（与既有 `TodoScopeRing` 的 `white.opacity(0.15)` 同族，机制八 取 0.12）。
    static let trackOpacity: Double = 0.12
    /// 亮描边的发光半径（2.5 ≈ 机制八 的 2–3）。
    static let glowRadius: CGFloat = 2.5

    /// 环心百分比的字号：直径退档时**跟着退**（对齐 `TodoScopeRing` 的「环心字号随直径退档」）。
    ///
    /// 46 → 11 而不是 12：`22.8%` 这类值在 46 的环里用 12pt 会顶到 5pt 环带的内侧（实测宽 38.5 >
    /// 内径 36），11pt 才是「读数即焦点」又不压环带的那一档。
    static func counterFontSize(forDiameter diameter: CGFloat) -> CGFloat {
        diameter >= regularRingDiameter ? 11 : 10
    }

    /// 环心文字的**可用宽度**（= 环内径 − 两侧各 2pt 呼吸）。
    ///
    /// 视图把这条件当作 `Text` 的最大宽：`100.0%` 这种偏长的值靠 `minimumScaleFactor` 收进来，
    /// **永远不压到 5pt 的环带上**（这条与 `counterFontSize` 一起保证环心可读）。
    static func counterMaxWidth(forDiameter diameter: CGFloat) -> CGFloat {
        max(0, diameter - 2 * (mainLineWidth + 2))
    }

    /// 三环横排的总宽（含间距）——**「不裁」的判据**：任何块宽下都该 `<= 块宽`
    /// （生产档：220 → 158、180 → 140）。
    static func rowWidth(forWidth width: CGFloat, spacing: CGFloat = ringSpacing) -> CGFloat {
        3 * ringDiameter(forWidth: width) + 2 * max(0, spacing)
    }
}

// MARK: - 首页块（三环并排）

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

/// 首页块：**三环并排**——CPU / 内存 / GPU 各一个环（环心百分比、环下标签）。
///
/// 只读、无控件（这正是用户判定「没有控制按钮 → 改为首页小部件」的理由）、无空态：
/// `StatsManager` 的三个用量在没有采样时是 `0.0`（首帧），采样一起来就是真值。
///
/// **形态为什么是环**（用户 2026-09-30 追加指示 / 机制八）：三行横条太占空间，环在同样信息量下
/// 更矮、且「读数即焦点」（百分比在环心）；形态与配色对齐既有 `TodoScopeRing` 先例。
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
        // 宽度用 `GeometryReader` 读**放置后**的尺寸（不是测量）：直径据此退档（`StatsRingMetrics`），
        // 三个环的总宽因此永远 ≤ 块宽——「不裁」由纯函数保证，视图不再自己算。
        GeometryReader { proxy in
            let diameter = StatsRingMetrics.ringDiameter(forWidth: proxy.size.width)

            HStack(alignment: .top, spacing: StatsRingMetrics.ringSpacing) {
                ForEach(StatsHomeBlockLayout.rows) { row in
                    StatsRingView(
                        row: row,
                        valueText: row.valueText(in: stats),
                        progress: row.progressValue(in: stats),
                        diameter: diameter
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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

/// 一个指标环：**环轨 + 主环（5pt）+ 亮描边（2pt + 淡发光）+ 环心百分比 + 环下 9pt 标签**。
///
/// 「科技风」只做三件事（机制八，克制、可维护、不引第三方）：
/// ① 按指标分色（`Row.ringColor`，取自面板既有的系统色家族）；
/// ② 细描边 + 淡发光（2pt 的亮描边压在 5pt 的主环上，外加深色 `shadow`）；
/// ③ 等宽数字（`monospacedDigit()`，刷新时不跳动）。
///
/// 直径与字号都由 `StatsRingMetrics` 给（纯函数，有用例）；环心文字的可用宽度也由它给
/// （`counterMaxWidth`）——超长的值（如 `100.0%`）在这条宽度里缩放，**不压环带、不撑破环**。
private struct StatsRingView: View {
    let row: StatsHomeBlockLayout.Row
    let valueText: String
    let progress: Double
    let diameter: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                // ① 环轨（与既有 `TodoScopeRing` 同一族的白，机制八 取 0.12）。
                Circle()
                    .stroke(.white.opacity(StatsRingMetrics.trackOpacity), lineWidth: StatsRingMetrics.mainLineWidth)

                // ② 主环（进度那一笔的底色，同一支指标色但暗一档）。
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        row.ringColor.opacity(StatsRingMetrics.mainRingOpacity),
                        style: StrokeStyle(lineWidth: StatsRingMetrics.mainLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                // ③ 亮描边 + 淡发光：叠在主环上的细一笔，「通电的环」。
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        row.ringColor,
                        style: StrokeStyle(lineWidth: StatsRingMetrics.highlightLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: row.ringColor.opacity(0.8), radius: StatsRingMetrics.glowRadius)

                // 环心：百分比（先拼 String 再给 Text，走 verbatim 重载，不做本地化查表）。
                Text(verbatim: valueText)
                    .font(.system(
                        size: StatsRingMetrics.counterFontSize(forDiameter: diameter),
                        weight: .semibold,
                        design: .rounded
                    ))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: StatsRingMetrics.counterMaxWidth(forDiameter: diameter))
            }
            .frame(width: diameter, height: diameter)

            Text(LocalizedStringKey(row.labelKey))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
    }
}
