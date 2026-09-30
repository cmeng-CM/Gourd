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
//  HomeStripView.swift
//  Gourd 宿主 · 首页两条带的渲染器 + 块封装（P2 批次 / T3；P3 组件批次 / T7 分带）
//
//  展开面板首页从「音乐 + 日历两栏写死」改成**两条带**（P2 批次），T7 起按块的形态再分一次
//  （docs/26-home-widgets-and-settings.md §做法 机制六 / D-09）：
//
//  - **主块带**（`HomeStripView`，上）：大块（音乐 / 镜子）——一条横向 strip，宽度按声明自适应、
//    **富余时不拉伸**（D-02），放不下时按最小宽度收敛、仍不足则按 `order` 从尾部丢块（D-03：
//    不滚动、不分页、不加 `ScrollView`）；
//  - **小组件带**（`HomeWidgetBandView`，下）：紧凑块（进度 / 统计 / 待办 / 通知 / 前台应用）——
//    按可用宽铺网格、**放不下换行**，行数由分给这条带的高度决定（`HomeBandedLayout`）；
//    **只有连一行都放不下时才丢块**；
//  - **日历行**（`HomeCalendarRow`，下下）：整月网格需要宽度，因此从来不在块里（2026-09-29 起）。
//
//  两带的名单、宽度、形态与高度取舍的唯一权威源是 `HomeBandCatalog`（名单）+ `HomeBandedLayout`
//  （宽度摆放）+ `HomeVerticalFit`（高度档位）；本文件只做「取名单 → 交给纯函数 → 按结果摆放」。
//  接缝是 `HomeBandedHomeView`（`NotchHomeView` 的标准路径直接用它的一个实例）——它是本文件里
//  唯一持有注册表 / 偏好观察的地方。
//
//  为什么分带（用户 2026-09-30）：「不要把所有小组件都放在第一排，窄宽度下会被整排丢掉」。一条 strip
//  要装 6–8 块时规则 ③ 从尾部丢到只剩前几块——而默认面板宽 1154pt 下可用宽只有 ≈1086，六块最小宽之和
//  加间隙已经是 1280：**这不是窄宽度才有的问题，默认宽度就已经在丢**。换行让紧凑块不必争那一条宽度。
//
//  历史（P2 接管批次 / T4 镜子、T5 音乐先后搬走）：本文件里最后两条内置块分支已随接管删除，
//  今天**没有任何宿主内置块**——块名单 = `homeEntries` 投影 + 「`content(for: .home)` 答不答 `.none`」
//  这一道内容表态（口径见 `HomeBandCatalog.resolve`）；音乐块还要的那条 matchedGeometry 命名空间由
//  `HomeBandCell` **注入**（`.environment(\.homeAlbumArtNamespace,…)`，D-08 / docs/20 §接口与数据形状 6）
//  ——它本来就是这条命名空间的持有者。`autoHideInactiveNotchMediaPlayer` 的 `@Default` 以**观测源**
//  身份留在接缝上（它不是判据——判据在 `MusicModule.isVisible(...)`，只是「上游拨了这个开关要有人
//  叫醒块名单重算」的那个观察者）。
//
//  规格：docs/17-nookx-adoption.md §做法 机制三（宽度 = 声明 + 收敛）、§接口与数据形状 6（块宽声明与
//  固定取值）、§改动点设计 1/2/3；docs/20-component-page.md §做法 机制一（渲染点归属 / 块宽继承）；
//  docs/21-strip-honesty.md（丢块与 `＋N` 的既有契约）；docs/26 §做法 机制六（分带与四档）。
//
//  块的**存在性**用「是/否」而不是透明度：条件不满足的块根本不生成——否则它仍占宽度、
//  仍参与布局（P2 裁决 1）。块的**名单**只有一个权威源：`homeEntries` 投影（机制二）。
//
//  P2 丢块提示批次 / T1 增量（两带共用）：**丢块不再无声**。主块带沿用 `plan(…:tailReserve:)`
//  的判定（`droppedCount` / `tailReserveUsed`）；小组件带的判定在 `HomeBandedLayout`（行数不够 +
//  行内规则 ③，汇总成一个 `droppedCount`）。提示用的宽度是**额外预留**的 `droppedHintWidth`（34pt）：
//  只有本来就会丢块时才预留，边界处可能因此多丢一块（docs/21 §已知限制 6，D-01 / D-02）。
//  丢块规则本身一字未动（主块带仍从尾部丢、不滚动、不压扁，D-03）。
//

import Defaults
import SwiftUI

// MARK: - 块宽声明

/// 一块的宽度约束：`min` 是「低于它不如不显示」的下界，`ideal` 是「富余时就用它」的期望值。
///
/// 取值来源有两处（docs/17 §接口与数据形状 6 + docs/20 §做法 机制一「块宽继承」）：
/// **接管模块声明被接管块原本的那一档**——音乐 `300 / 420`、镜子 `140 / 160`（T4 / T5 已先后
/// 搬到 `MirrorModule` / `MusicModule` 的 `homeBlockWidth`，宿主经
/// `ModuleRegistry.homeBlockWidth(for:)` 取回）；**新增模块**用宿主统一声明的 `180 / 240`
/// （D-11 的口径收窄为「新增模块不参与宽度决策」）。
struct HomeBlockWidth: Equatable {
    let min: CGFloat
    let ideal: CGFloat
}

/// 块把自己的宽度约束递给 `HomeStripLayout` 的通道。
///
/// **含 `GeometryReader` 的视图在 `.unspecified` 测量下只报约 10pt**，靠测量会算出约 6pt 的块
/// （docs/17「机制三」）——所以块都显式声明本键，测量只作取不到声明时的回退。
///
/// **P2 丢块提示批次 / T1 起这条通道降为退路**：生产路径的宽度由**名单**（`HomeBandBlock.width`）
/// 解析成非可选值后经 `HomeStripLayout(items:)` 直接传入（D-03 同源），Layout 只在 `items` 为空时
/// 才回过头来读本键 / 测量（今天没有这样的调用点）。声明这一侧因此逐字不变，测量仍不当主力。
struct HomeBlockWidthKey: LayoutValueKey {
    static let defaultValue: HomeBlockWidth? = nil
}

// MARK: - 布局

/// 首页一条横向带的 `Layout`：把宽度分配结果摆成一行（**两带共用**：主块带是一行，
/// 小组件带的每一行也是它）。
///
/// 高度**不协商**（沿用 docs/13 的既有裁定）：块拿到的是整条带的高度，自己决定内部怎么排；
/// 因此 `sizeThatFits` 原样接受提案高度，横向的分配才是本布局唯一做的事。
///
/// **一次布局只算一次 `plan`**：`sizeThatFits` 把结果连同输入（`items` / `available`）写进 cache，
/// `placeSubviews` 读它、**不重算**。两边各算一次的失败案例是规则 ②——`sizeThatFits` 的输入是
/// `proposal.width`，而 `placeSubviews` 能看到的 `bounds.width` 是上一份 plan 的**已压缩输出**，
/// 规则 ② 不幂等（实测 available 684 → 上报 `[414.5, 257.0]`；用 683.5 重算得 `[414.0, 257.0]`），
/// 于是「摆放用的宽度」与「上报的宽度」不是同一组数。所以这里用 `Layout` 的 cache 传递结果，
/// 而不是靠「同一算式重算一遍」这种假设。
///
/// **P2 丢块提示批次 / T1 增量**：块宽不再由本布局从 subviews 取声明（生产路径改由调用方传入
/// `items`，D-03 同源：同一个非可选数组既喂 `plan` 也喂块壳）；`tailHintWidth` 与 `items` 一起
/// 进 cache 的复用判据，plan 用的是与调用方**同值**的尾部预留位（`tailReserve`）。
struct HomeStripLayout: Layout {
    /// 本次要摆的块宽（**由调用方传入**：调用方已经把每块的宽度解析成确定值，Layout 不再从 subviews
    /// 取声明、也不测量）。空数组 = 走「声明优先、测量回退」的旧路径（退路，今天无生产调用）。
    var items: [HomeStripLayoutMath.Item] = []
    /// 尾部预留位宽度（与 `plan(…:tailReserve:)` 同值；唯一取值在 `HomeStripView.droppedHintWidth`）
    var tailHintWidth: CGFloat = 0

    /// 块间距：单一常量（docs/17「做法」机制三）。T1 的用例与算式也共用这个数。
    ///
    /// **2026-09-29 由 12 改为 8**（T2+T3 修复轮）：770pt 面板的可用宽 **≈702**——这个数是
    /// **内边距常量链推导**出来的（`ContentView.swift:524` 的 `opened.top − 5` = `sizing/matters.swift:250`
    /// 的 `19` 减 5 = 14、`ContentView.swift:750` 的 12、`NotchHomeView.swift:871` 的 8，两侧各 34）；
    /// 像素反推这次落在 **≈703**（早前那版 ≈705–706 是更粗的估计）。**两个口径都 < 704**
    /// （= 三块最小宽 `300 + 200 + 180 = 680` + `2×12`），所以间距必须小于 12。
    ///
    /// 行为证据（屏上实拍，比精确值更硬）：间距 12 时 770pt 下第三块（待办）被规则 ③ 整块丢弃
    /// （丢掉的块拿 `.zero` 提案，见 `placeSubviews`）；改成 8 后 `680 + 16 = 696 ≤ 702`，三块齐活、
    /// 各自拿到最小宽度——模块块 180 ≥ 160，待办首页块因此能走 `.compact` 档显示今日标题。
    ///
    /// **770pt 面板只能容三块**（内置音乐 / 日历 + 一个模块块）：`homeEntries` 里排在前面的模块块
    /// 先占名额，尾部多出来的块会被规则 ③ 丢弃（这是设计行为，不是故障——D-03 丢块比压扁更可读）。
    /// 要同时看到更多模块块，得把面板拉宽（4 块最小宽度和 + 间隙 = `860 + 24 = 884`，
    /// 即可用宽 ≥ 884 → 面板 ≈ 952pt 起）。**T7 起这条只对主块带成立**（紧凑块改走小组件带的换行网格）。
    static let spacing: CGFloat = 8

    /// 一次布局的输入形状与算出的结果。
    struct Cache {
        /// 本轮的宽度约束：`items` 非空时就是调用方传进来的那一份（D-03 同源）；
        /// 调用方没传（空数组）时才是「声明优先、测量回退」的旧结果。子视图变化时由 `updateCache` 重新取一次。
        var items: [HomeStripLayoutMath.Item] = []
        /// 下面这份 `plan` 是拿哪个可用宽度算出来的（`plan == nil` 时无意义）。
        var available: CGFloat = .nan
        /// 上面那份 `plan` 是拿哪个尾部预留位宽度算出来的——**复用判据的一部分**：
        /// 只看 `available` 会在预留位变化时复用旧 plan（两份 plan 的 `visibleCount` /
        /// `tailReserveUsed` 可能不同）。`plan == nil` 时无意义。
        var tailHintWidth: CGFloat = .nan
        /// nil = 还没有任何人为当前的输入算过。
        var plan: HomeStripLayoutMath.Plan?
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(items: resolvedItems(subviews: subviews))
    }

    /// 子视图变了（块被加上 / 去掉、宽度声明变了）→ 重新取一次宽度约束，并把宽度分配结果作废，
    /// 由下一次 `sizeThatFits` 按新的输入重算。测量只在这里（和 `makeCache`）发生。
    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.items = resolvedItems(subviews: subviews)
        cache.available = .nan
        cache.tailHintWidth = .nan
        cache.plan = nil
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        // 无宽提案（`.unspecified`）时按「各块理想宽度之和」当可用宽度：命中规则 ①（富余），
        // 于是向上报的就是这条带的自然宽度——`plan` 的前置条件要求有限数，不能传 `.infinity`。
        let available = proposal.width ?? Self.naturalWidth(of: cache.items)
        let plan = resolvedPlan(available: available, cache: &cache)
        // 间隙只存在于**可见**的块之间：规则 ③ 丢块后 n 是 `visibleCount`，不是 `subviews.count`。
        let gaps = Self.spacing * CGFloat(max(0, plan.visibleCount - 1))
        return CGSize(width: plan.widths.reduce(CGFloat.zero, +) + gaps, height: proposal.height ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        // 摆放用的就是 `sizeThatFits` 当初决定上报宽度的那一份结果（那是本布局唯一的分配）。
        // cache 为空属极端情况（这次布局没经过 `sizeThatFits`），按 `bounds` 现算一份兜底。
        let plan: HomeStripLayoutMath.Plan
        if let cached = cache.plan {
            plan = cached
        } else {
            plan = resolvedPlan(available: bounds.width, cache: &cache)
        }

        var x = bounds.minX
        for index in subviews.indices {
            guard index < plan.widths.count else {
                // **被规则 ③ 丢掉的尾部块必须显式摆放**（提案为零，什么都不画）：
                // `place(at:anchor:proposal:)` 的文档写明——没为某个 subview 调用它时，该 subview
                // 会**以容器的尺寸提案居中叠画在容器中央**。即「不摆放」不等于「不显示」，
                // 而是把被丢掉的块铺满整条带叠在已摆放块之上；默认 `openNotchWidth = 640`
                // 且镜子打开时（三块最小宽度和 664 > 可用 ≈572）就会命中规则 ③，T4 加上待办块后
                // 四块更是常态。零提案让被丢的块既不占位也不可见。
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY), proposal: .zero)
                continue
            }
            let width = plan.widths[index]
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + Self.spacing
        }
    }

    /// 取本次布局的 `plan`：输入形状（**`available` 与 `tailHintWidth` 两个**）与 cache 里记的
    /// 一致就直接复用，否则按 cache 里的宽度约束算一次并写回。`items` 的失效由 `updateCache` 负责。
    private func resolvedPlan(available: CGFloat, cache: inout Cache) -> HomeStripLayoutMath.Plan {
        if let plan = cache.plan, cache.available == available, cache.tailHintWidth == tailHintWidth {
            return plan
        }
        let plan = HomeStripLayoutMath.plan(
            items: cache.items,
            available: available,
            spacing: Self.spacing,
            tailReserve: tailHintWidth
        )
        cache.available = available
        cache.tailHintWidth = tailHintWidth
        cache.plan = plan
        return plan
    }

    /// 本轮实际要摆的块宽：**调用方传了就用调用方的**（D-03 同源，生产路径）；只有 `items` 为空时
    /// 才回退到旧路径——每个 subview 的声明优先、取不到声明才测量（`ideal` = 测得的宽度、
    /// `min = ideal × 0.6`，设计文档给未声明块的回退口径）。
    private func resolvedItems(subviews: Subviews) -> [HomeStripLayoutMath.Item] {
        items.isEmpty ? Self.measuredItems(of: subviews) : items
    }

    private static func measuredItems(of subviews: Subviews) -> [HomeStripLayoutMath.Item] {
        subviews.map { subview in
            if let declared = subview[HomeBlockWidthKey.self] {
                return HomeStripLayoutMath.Item(min: declared.min, ideal: declared.ideal)
            }
            let ideal = subview.sizeThatFits(.unspecified).width
            return HomeStripLayoutMath.Item(min: ideal * 0.6, ideal: ideal)
        }
    }

    private static func naturalWidth(of items: [HomeStripLayoutMath.Item]) -> CGFloat {
        let sum = items.reduce(CGFloat.zero) { $0 + $1.ideal }
        return sum + spacing * CGFloat(max(0, items.count - 1))
    }
}

// MARK: - 块封装

/// 一条带里的一格：声明自己的宽度约束，并把自己在**分配到的**宽高里顶部对齐。
///
/// 内置块与模块块**同构**地套这一层：两者的差别只在「宽度声明是谁给的」与「里面画什么」，
/// 摆放机制只有一套（docs/17 §改动点设计 2）。**两带也共用这一层**（T7）。
struct HomeStripBlock<Content: View>: View {
    /// nil = 不声明，由 `HomeStripLayout` 回退到测量（本批生产路径不用）。
    let width: HomeBlockWidth?
    let content: Content

    init(width: HomeBlockWidth?, @ViewBuilder content: () -> Content) {
        self.width = width
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        // 横向铺满**分配到的**宽度（不超过声明宽度），纵向拿满这条带的高度并从顶部开始画：
        // 面板里不再用会把内容摊开的纵向 `Spacer`，留白自然留在块的下方。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // **块的外框必须裁剪**（2026-09-29 实测发现，修复轮 1）：被规则 ③ 丢掉的块拿 `.zero` 提案，
        // 但外框不裁剪时固定尺寸的内容（三环 / 图标 / 占位三角）仍按**固有尺寸**溢出绘制——
        // 770pt 面板下「待办块明明被丢了，屏上却出现三环、只是没有清单」就是这条溢出残影
        // （docs/17 §已知限制 19 原记为「当前配置不触发」，本次证伪）。
        // **T7 起它也多守一道门**：小组件带的行高（`HomeStripView.widgetRowHeight`）比旧 strip
        // 矮，块内容比行高时由它兜底，不会画到下一行上（`HomeBandedLayout` 的用例覆盖这一档）。
        // 放在 `.frame(...)` **之后**：裁的是这个块分配到的边界，块内画在边界里的内容不受影响；
        // 在 `.layoutValue` 之前，宽度声明的传递路径因此逐字不变。
        .clipped()
        .layoutValue(key: HomeBlockWidthKey.self, value: width)
    }
}

// MARK: - 块名单（唯一权威源）

/// 首页的一条带里的一块：`homeEntries` 投影里的一行 + 这一刻的内容表态 + 宽度与形态声明。
///
/// 四层分开是刻意的（`ModuleRegistry.homeEntries` 的函数注释同口径）：投影是**声明**
/// （manifest 说愿意在首页占一块），内容是**表态**（这一刻有没有东西可画），宽度与形态是
/// **模块的自我描述**（`homeBlockWidth` / `homeFormFactor` 两条钩子）——四者分开才不会让
/// 一次 `.none` 影响后续刷新，也不会让宽度去反推形态（D-09）。
struct HomeBandBlock: Identifiable {
    /// 覆盖表的键与宽度 / 形态查询键：模块 id。
    let id: String
    /// 条尾 `＋N` 的悬停文案里列的块名（**已本地化**：`ModuleHomeEntry.label` 与 tab 条目同一份）。
    let name: String
    /// 缺键时的默认序号（= `entry.order`，`manifest.defaultPlacement.order`）。
    let defaultOrder: Int
    /// 该模块这一刻答的首页内容（`.view` / `.descriptor` / `.unavailable`；`.none` 已被过滤掉，
    /// 不会走到这里）。
    let content: ModuleContent
    /// 宽度声明（模块钩子的取值，缺省 = 宿主统一值 180/240）。
    let width: HomeBlockWidth
    /// 形态声明（`homeFormFactor` 钩子：`.large` 进主块带、`.compact` 进小组件带）。
    let formFactor: HomeFormFactor
}

/// 首页两条带的**名单**：投影 → 内容表态 → 排序 → 按形态切带。
///
/// 块的存在判据 = 投影里有它（声明 + 已激活）**且** `content(for: .home)` 不答 `.none`
/// （表态）——**接管模块的运行期门控就在这一答里**：音乐看
/// `showStandardMediaControls && (!autoHideInactiveNotchMediaPlayer || hasActiveSession)`、
/// 镜子看 `showMirror && cameraAvailable`（两条判据都在各自模块里，本层不重复一份）。
///
/// 顺序的**唯一权威源**也是这一层（覆盖值 + 默认序号，后者先过历史键映射），设置页展示用的是
/// 同一条算式；切带在**排序之后**做——两带各自保持同一条全局顺序（主块带里 `order` 小的在前，
/// 小组件带同理），用户改顺序时看到的相对次序因此与组件页一致。
struct HomeBandCatalog {
    /// 主块带（`.large`，按同一条顺序）。
    let main: [HomeBandBlock]
    /// 小组件带（`.compact`，按同一条顺序）。
    let widgets: [HomeBandBlock]

    /// 模块块的**缺省**宽度由宿主统一声明（模块不参与「我在首页占多宽」的决策，D-11）：
    /// 声明值必须存在——模块块内容多为 `GeometryReader`，测量回退会把它们算成约 6pt。
    /// **接管模块例外**：它接住的是被接管块原本的宽度（D-10），走 `homeBlockWidth` 钩子取。
    static let moduleBlockWidth = HomeBlockWidth(min: 180, ideal: 240)

    /// 解析本轮的块名单（纯读：不改注册表、不写偏好）。
    ///
    /// `@MainActor`：注册表的四条查询（`homeEntries` / `content(for:request:)` / 两条钩子查询）
    /// 都是主线程隔离的（`ModuleRegistry` 是 `@MainActor` 类）——调用方是视图的 body，本来就在
    /// 主线程上；标注只是把这件事写明，不引入任何切换。
    @MainActor
    static func resolve(registry: ModuleRegistry, overrides: [String: Int]) -> HomeBandCatalog {
        var blocks: [HomeBandBlock] = []
        for entry in registry.homeEntries {
            let content = registry.content(for: entry.id, request: ModuleRegistry.home)
            if case .none = content { continue }
            let declared = registry.homeBlockWidth(for: entry.id)
            blocks.append(
                HomeBandBlock(
                    id: entry.id,
                    name: entry.label,
                    defaultOrder: entry.order,
                    content: content,
                    width: declared.map { HomeBlockWidth(min: $0.min, ideal: $0.ideal) } ?? moduleBlockWidth,
                    formFactor: registry.homeFormFactor(for: entry.id)
                )
            )
        }
        let sorted = HomeBlockOrdering.sorted(
            blocks,
            defaultOrder: { $0.defaultOrder },
            id: { $0.id },
            overrides: overrides
        )
        return HomeBandCatalog(
            main: sorted.filter { $0.formFactor == .large },
            widgets: sorted.filter { $0.formFactor == .compact }
        )
    }
}

// MARK: - 一格（两带共用）

/// 一条带里的一格：块壳 + 模块内容 + 命名空间注入。两带的格**同构**（只有宽度来源不同：
/// 主块带的宽度来自 `HomeStripLayoutMath.plan`，小组件带来自 `HomeBandedLayout` 的行方案）。
struct HomeBandCell: View {
    let block: HomeBandBlock
    let albumArtNamespace: Namespace.ID

    var body: some View {
        HomeStripBlock(width: block.width) {
            HomeBandBlockContent(content: block.content)
        }
        // 音乐块要的那条 matchedGeometry 命名空间在这里注入（D-08 / docs/20 §接口与数据形状 6）：
        // 宿主（本文件）持有折叠态播放器共享的那一条，模块拿不到它；读不到时模块用自带
        // `@Namespace` 兜底（配对静默失效，不崩不空白）。注入**只加在块上**——块壳与它
        // 所在的环境由宿主给，块里画什么由模块说。
        .environment(\.homeAlbumArtNamespace, albumArtNamespace)
    }
}

/// 四个分支逐条对应 06 §3.2（与 `ModuleHostView` 同口径）：`.view` 渲染模块给的视图；
/// `.descriptor` 本批不渲染（占位说明）；`.unavailable` 显示降级文案（**不算失败**）；
/// `.none` 不占位（生成格之前已过滤，这里只为 switch 穷尽）。
struct HomeBandBlockContent: View {
    let content: ModuleContent

    var body: some View {
        switch content {
        case .view(let view):
            view
        case .descriptor:
            HomeStripModulePlaceholder(reason: "首页块不支持描述符渲染")
        case .unavailable(let reason):
            HomeStripModulePlaceholder(reason: reason)
        case .none:
            EmptyView()
        }
    }
}

/// 条尾的 `＋N` 小胶囊（**两带共用**）：告诉用户「这里还有 N 块没显示」（把面板拉宽 / 拉高就能看见）。
///
/// **刻意低调**（`white.opacity` 的边与字）：它是「这里还有东西」的线索，不是主内容，
/// 也不可点击（docs/21 §明确不做：做入口要先定「点了去哪」）。
///
/// 文字用 `Text(verbatim:)`：`＋N` 是符号 + 数字、语言无关，走本地化 key 会让 string catalog
/// 凭空多出一条待翻译条目（与 `DynamicIslandCalendar.overflowRow` 的 `+N` 同一口径）。
/// 悬停文案只列**已被注册表本地化**的块名（`HomeBandBlock.name`），本身不含待翻译句子。
struct HomeBandDroppedHint: View {
    let count: Int
    let names: [String]

    var body: some View {
        Text(verbatim: "＋\(count)")
            .font(.caption2)
            .fontWeight(.semibold)
            .monospacedDigit()
            .foregroundColor(.white.opacity(0.55))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .help(Text(verbatim: names.joined(separator: "、")))
    }
}

// MARK: - 主块带

/// 首页的**主块带**（大块：音乐、镜子）：一条横向 strip，规格逐字沿用 P2 批次
/// （docs/17 §改动点设计 2 / D-02 / D-03，见 `HomeStripLayoutMath` 的三条规则）。
///
/// 块顺序 = 名单按 `HomeBlockOrdering` 排序后的**大块子序列**（覆盖值优先 → 缺键回落默认序号 →
/// 同值按 id 字典序，P1 / T3；覆盖表先过历史键映射，P2 / T4）。默认序号下音乐块（0）在前、
/// 镜子块（2）在后——两个序号都等于**被它们取代的内置块**当年的默认序号，**未调过顺序的用户看到
/// 的就是改动前的那条 strip**。
///
/// **丢块规则不变**（D-03）：宽度不够时仍按**排好序的**尾部丢——顺序改了，丢的对象随之改，
/// 这是排序生效的正常结果（docs/18 §改动点设计 4 的陷阱栏）。**T7 起它只对「大块」生效**：
/// 紧凑块改走下面的小组件带（换行不丢块），主块带因此在默认宽度下通常只装一两块。
struct HomeStripView: View {
    /// 主块带的块名单（**已排序的大块**，由 `HomeBandedHomeView` 解析后传入）。
    let blocks: [HomeBandBlock]
    let albumArtNamespace: Namespace.ID

    /// 这条带要摆的块宽（顺序即显示顺序）：同一个数组既喂 `HomeStripLayout` 也喂 `plan`。
    private var items: [HomeStripLayoutMath.Item] {
        blocks.map { HomeStripLayoutMath.Item(min: $0.width.min, ideal: $0.width.ideal) }
    }

    /// 主块带的**最小可用高度**：低于它就不生成这条带（判据在 `HomeVerticalFit` 里）——
    /// **判据是「画不满就不画」**（2026-09-29 复审裁决）：高度不足以**完整渲染**带内的块时，
    /// 整条不画，而不是画一条被切一半的封面。
    ///
    /// **数值来源（同一批实测截图，见 `.workflow/p2-calendar-row/reports/` 的 §6.5）**：音乐块（今天
    /// 最矮的那一档仍是它——宽 300/420 的块，T5 接管后宽度不变）从上到下需要 `18`（块内顶部偏移，
    /// 封面起点）+ `133`（封面边长，受块宽 420 下的宽度份额约束）≈ **151.5pt**，留半 pt 取整 = **152**：
    /// - 面板 544 → strip 174：封面下沿 + 角标 + 控制三键全在，完整 ✓（留 ~22pt 余量）；
    /// - 面板 522 → strip 152：按此阈值刚好画满；
    /// - 面板 504 → strip 134：封面下沿被切、角标只剩半个（`strip-hidden-panel460.png` 之前的
    ///   `strip-clipped-panel460.png` 是同一现象的更矮一档）→ 因此 134 **不够**，阈值取 152。
    ///
    /// 低于阈值即整条不画（这一档由 `HomeVerticalFit` 让位给小组件带）；其它大块（镜子）比音乐块矮，
    /// 本阈值对它们偏保守——宁可少画一条，不画残片。
    static let minimumUsableHeight: CGFloat = 152

    /// 条尾 `＋N` 提示的**预留位宽度**（docs/21 §备选与取舍 ②：固定，不按块数伸缩）。
    ///
    /// **唯一取值在这里**：两带都拿它喂 `plan(…:tailReserve:)` / 喂 `HomeStripLayout(tailHintWidth:)`
    /// ——两处必须同值，否则「预留出来的位置」与「画提示的位置」会不是同一个 34pt。
    /// 取值依据：`＋N` 的 N 是一位到两位数（32~36pt 足够放下，docs/21 §已知限制 1）。
    static let droppedHintWidth: CGFloat = 34

    /// 小组件带**每行的高度**（定值：紧凑块是等高网格，行不随可用高度伸缩）。
    ///
    /// 取值依据（T7 的高度预算，docs/26 §做法 机制六的「代价」一节）：默认面板 1154×630 的可内容高
    /// ≈562pt，日历行（294）+ 主块带最小高度（152）+ 两个间距（16）之后只剩 **100pt**——96 是
    /// **既不挤掉日历行、又高得下紧凑块内容**的一档（统计三行 ≈64、进度两行 ≈52、待办三环 52 +
    /// 一行清单）。再高一档（如 112）会把默认高度下的日历行挤掉，而那正是用户要保留的行（T4 还要给它
    /// 加农历与节假日）——宁可让网格矮一点，也不让默认档先丢日历行。
    static let widgetRowHeight: CGFloat = 96

    /// 小组件带的**行间距**（与列间距、与日历行的接缝同值：面板里一套 8pt 的呼吸感）。
    static let widgetRowSpacing: CGFloat = HomeCalendarRow.rowSpacing

    /// 小组件带的**列间距**（同一行内格与格之间）——与主块带的块间距同一个常量：
    /// 「块与块之间是 8」这条在两条带上不该有两个数。
    static let widgetColumnSpacing: CGFloat = HomeStripLayout.spacing

    var body: some View {
        // 宽度声明（`items`）在本轮渲染里只取一次：下面 `plan` 与 `HomeStripLayout` 是同一个来源。
        let items = self.items

        // 可用宽度从 `GeometryReader` 取：它与 `HomeStripLayout` 拿到的 `proposal.width` 是**同一条
        // 带的宽度**（ZStack 把自身尺寸原样提案给子视图），所以这份 plan 与 Layout 那份 plan
        // 的输入完全相同——两边各自算一次同一道题，不需要把结果从视图传进 Layout。
        GeometryReader { proxy in
            let available = proxy.size.width
            let plan = HomeStripLayoutMath.plan(
                items: items,
                available: available,
                spacing: HomeStripLayout.spacing,
                tailReserve: Self.droppedHintWidth
            )

            ZStack(alignment: .topLeading) {
                HomeStripLayout(items: items, tailHintWidth: Self.droppedHintWidth) {
                    ForEach(blocks) { block in
                        HomeBandCell(block: block, albumArtNamespace: albumArtNamespace)
                    }
                }
                // **提案宽钉在可用宽上**（2026-09-30 T4 取证后的修复，唯一一处）：`HomeStripLayout`
                // 上报的宽度是「可见块宽 + 间隙」（丢块时比可用宽窄，见 D-02/D-03），SwiftUI 的下一趟
                // 布局会把**这个上报宽度**当作新提案再问它一次（尺寸反馈）——于是 plan 的输入从 702
                // 变成 488、预留 34pt 后 `visibleCount` 从 2 掉到 1，屏上只剩第一块，而视图那份按可用宽
                // 算的 plan 仍显示 ＋2（770pt 面板的实测复现：`.workflow/p2-home-fit/evidence/probe-770/`）。
                // 这一行让每趟布局提案的都是这条带的可用宽（`plan` 与 Layout 因此拿到**同一个宽度输入**，
                // 与 T1「D-03 同源」同一条口径）；带的**绘制**不变——块仍按 plan 分配宽从左上角摆，
                // 富余仍留在尾部。小组件带的每一行有同一句（那里钉的是「行宽 − 提示位」）。
                .frame(width: available, alignment: .topLeading)

                if plan.tailReserveUsed {
                    // 提示位**锚在尾部边缘**（`x = available − droppedHintWidth`，D-01）：**不要用
                    // `plan.leftover` 反推**——它的口径是「未被使用的尾部空间总量」，丢块路径下按缩减后
                    // 的宽度算，拿它算坐标既可能越界也不是对齐依据（docs/17 已知限制 11）。
                    // `tailReserveUsed` 为真 ⟹ 这份 plan 是按 `max(0, available − 34)` 分配的，于是
                    // **在 `available >= droppedHintWidth` 这个前提下**（生产路径恒成立：面板宽度有
                    // 下限，可用宽远大于 34）它的总宽不超过 `available − 34`，x 因此非负、提示也不与
                    // 任何可见块重叠。**前提不成立时 x 会为负**（可用宽 < 34：分配那一侧被 `max(0, …)`
                    // 钳到 0，坐标这一侧仍按完整的 `available` 算）——那条路径今天不可达（规则 ③ 对
                    // 非空 `items` 至少保住第一块，`visibleCount >= 1` 恒成立，见 `HomeStripLayoutMath.plan`
                    // 的第 ③ 步），写在这里只为别把「非负」读成无条件结论。
                    HomeBandDroppedHint(count: plan.droppedCount, names: droppedNames(visibleCount: plan.visibleCount))
                        .frame(width: Self.droppedHintWidth, alignment: .trailing)
                        .offset(x: available - Self.droppedHintWidth)
                }
            }
        }
        // 带本身**不铺满**：`HomeStripLayout` 报出的宽度就是「各块分配宽度 + 间隙」，
        // 这里只负责把带按左上角放在面板里（富余的宽度留在尾部，D-02；不居中、不对齐）。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 被丢掉的块名（`.help()` 的文案来源）：名单是**排好序的**那份，`visibleCount` 之后的就是
    /// 被规则 ③ 丢掉的那些——名单与 plan 都来自上面这一份输入，所以提示列的块与真正没显示的块
    /// 必然是同一批（D-03「名单同源」）。
    private func droppedNames(visibleCount: Int) -> [String] {
        blocks.dropFirst(max(0, visibleCount)).map(\.name)
    }
}

// MARK: - 小组件带

/// 首页的**小组件带**（紧凑块：进度、统计、待办、通知、前台应用）：网格换行、行数由高度定。
///
/// 摆放算术全在 `HomeBandedLayout`（纯函数、已单测）；本视图只做「按行方案摆格子、给每行钉
/// 提案宽、在有丢弃的那一行末尾画 `＋N`」。每行都是一条横向带，因此与主块带**共用同一个
/// `HomeStripLayout`**（摆放机制只有一套）——行内宽度的自适应（富余不拉伸 / 不足压缩 / 单行
/// 也放不下时兜底）因此与主块带逐字同一条规则。
///
/// **行高与行距**（`HomeStripView.widgetRowHeight` / `widgetRowSpacing`）由宿主声明；
/// 多出来的高度留在尾部（行从顶部开始排），不摊到行上——行高一致，网格才是网格。
struct HomeWidgetBandView: View {
    /// 小组件带的块名单（**已排序的紧凑块**）。
    let blocks: [HomeBandBlock]
    /// 这一带的行方案（`HomeBandedLayout.plan` 的 `widgets` 部分）。
    let plan: HomeBandedLayout.WidgetBandPlan
    /// 这一带的可用宽（行宽与提示位坐标都用它，见下方注释）。
    let availableWidth: CGFloat
    let albumArtNamespace: Namespace.ID

    private var items: [HomeStripLayoutMath.Item] {
        blocks.map { HomeStripLayoutMath.Item(min: $0.width.min, ideal: $0.width.ideal) }
    }

    var body: some View {
        let items = self.items

        VStack(alignment: .leading, spacing: HomeStripView.widgetRowSpacing) {
            ForEach(Array(plan.rows.enumerated()), id: \.offset) { _, row in
                rowView(row, items: items)
            }
        }
        // 一条带整体按左上角放：行从上往下排，多出来的高度留在带尾（不摊到行上）。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 一行：格子按行方案摆（提案宽钉在「行宽 − 提示位」上，尺寸反馈因此不会改答案），
    /// 有丢弃时在行尾画 `＋N`（坐标与主块带同构：`x = availableWidth − droppedHintWidth`）。
    private func rowView(_ row: HomeBandedLayout.WidgetRow, items: [HomeStripLayoutMath.Item]) -> some View {
        let hintWidth = HomeStripView.droppedHintWidth
        // 行内格子的可用宽：留了提示位就从行宽里扣掉（与 `HomeBandedLayout` 的算式同源——
        // 那里的 `rowAvailable` 就是这一份）。本视图**不重算 plan**，只读方案里的 `showsHint`。
        let cellsWidth = row.showsHint ? max(0, availableWidth - hintWidth) : availableWidth

        return ZStack(alignment: .topLeading) {
            HomeStripLayout(items: row.indices.map { items[$0] }) {
                ForEach(row.indices, id: \.self) { index in
                    HomeBandCell(block: blocks[index], albumArtNamespace: albumArtNamespace)
                }
            }
            .frame(width: cellsWidth, alignment: .topLeading)

            if row.showsHint {
                HomeBandDroppedHint(
                    count: plan.droppedCount,
                    names: droppedNames
                )
                .frame(width: hintWidth, alignment: .trailing)
                .offset(x: availableWidth - hintWidth)
            }
        }
        .frame(width: availableWidth, height: row.height, alignment: .topLeading)
    }

    /// 被丢掉的小组件名（`.help()` 的文案来源）：可见的格恒是名单的**前缀**
    /// （行按顺序画、行内丢的是尾巴），因此 `visibleCount` 之后的就是被丢掉的那些。
    private var droppedNames: [String] {
        blocks.dropFirst(max(0, plan.visibleCount)).map(\.name)
    }
}

// MARK: - 标准路径首页（接缝）

/// 展开面板**标准路径**的首页：主块带（上）+ 小组件带（下）+ 全宽日历行（`showCalendar` 开时）。
///
/// 三条职责收在这一处（这是本文件里**唯一**持有注册表与偏好观察的地方）：
/// 1. **名单**：`HomeBandCatalog.resolve`（投影 + 表态 + 排序 + 切带，唯一权威源）；
/// 2. **高度**：`HomeVerticalFit.plan`（四档：三样都在 → 收日历行 → 收主块带 → 空）；
/// 3. **摆放**：`HomeBandedLayout.plan`（主块带沿用旧 strip 语义，小组件带网格换行）。
///
/// 三个纯函数的调用顺序是 T7 的核心（`HomeBandedLayout` 的文件头有同一份说明）：
/// 先按**宽度**铺出小组件要几行 → 再按**高度**决定这条带拿多少（以及画不画日历行 / 主块带）→
/// 最后按分到的高度定真正画几行。
///
/// 为什么接缝在这一层而不是 `NotchHomeView`：高度取舍要知道「小组件要几行」，而那是**宽度**的函数
/// ——名单与宽度都在这一层（注册表投影 + 块宽声明），把它们再搬进 `NotchHomeView` 只会多一处
/// 重复解析。`NotchHomeView` 保留的是更外面那层接缝：**极简 UI / 侧歌词 / 首发动画都不走这里**。
struct HomeBandedHomeView: View {
    @ObservedObject private var registry = ModuleRegistry.shared
    /// **观测源**（不是判据）：音乐块 / 镜子块的**存在性**由 `content(for: .home)` 答不答 `.none`
    /// 决定，而那两条判据里各有一段运行期条件（音乐 `MusicManager.shared.hasActiveSession`、
    /// 镜子 `WebcamManager.shared.cameraAvailable`）——起播 / 停播、摄像头插 / 拔时除了这两个观察者
    /// 没人会叫醒本视图，块就既不会出现也不会消失（小组件带的行数也会跟着变）。
    @ObservedObject private var musicManager = MusicManager.shared
    @ObservedObject private var webcamManager = WebcamManager.shared
    /// **观测源**：音乐块的存在性判据里有一段是 `Defaults[.autoHideInactiveNotchMediaPlayer]`
    /// （判据本身在 `MusicModule.isVisible(...)`，这里不重复一份）。
    @Default(.autoHideInactiveNotchMediaPlayer) private var autoHideInactiveNotchMediaPlayer
    /// 用户排序覆盖（P1 / T3）：`@Default` 是 `DynamicProperty`——设置页写盘后**这里立即重绘**。
    @Default(.homeBlockOrder) private var homeBlockOrder
    /// 日历行开不开（偏好，本视图读它，取舍算术本身不认偏好，见 `HomeVerticalFit` 文件头）。
    @Default(.showCalendar) private var showCalendar
    let albumArtNamespace: Namespace.ID

    var body: some View {
        // 名单在本轮渲染里**只取一次**：块的 `content(for:request:)`（它同时决定「有没有块」——
        // 答 `.none` 的不生成格、不留空壳）与排序都在 `HomeBandCatalog.resolve` 里算完。
        let catalog = HomeBandCatalog.resolve(registry: registry, overrides: homeBlockOrder)
        let metrics = Self.metrics

        GeometryReader { geometry in
            let availableWidth = max(0, geometry.size.width)
            let mainItems = catalog.main.map { HomeStripLayoutMath.Item(min: $0.width.min, ideal: $0.width.ideal) }
            let widgetItems = catalog.widgets.map { HomeStripLayoutMath.Item(min: $0.width.min, ideal: $0.width.ideal) }
            // 空带**不进取舍**：没有大块 / 没有紧凑块时传 0，那一条带既不占高度也不占带间间距
            // （`HomeVerticalFit` 因此没有「半条带」这种状态）。
            let rowsNeeded = catalog.widgets.isEmpty ? 0 : HomeBandedLayout.rowsNeeded(
                items: widgetItems,
                availableWidth: availableWidth,
                columnSpacing: metrics.widgetColumnSpacing
            )
            let plan = HomeVerticalFit.plan(
                available: geometry.size.height,
                calendarRowHeight: showCalendar ? HomeCalendarRow.rowHeight : 0,
                rowSpacing: HomeCalendarRow.rowSpacing,
                mainBandMinimumHeight: catalog.main.isEmpty ? 0 : HomeStripView.minimumUsableHeight,
                widgetRowHeight: catalog.widgets.isEmpty ? 0 : metrics.widgetRowHeight,
                widgetRowSpacing: metrics.widgetRowSpacing,
                widgetRowsNeeded: rowsNeeded
            )
            let bands = HomeBandedLayout.plan(
                mainItems: mainItems,
                widgetItems: widgetItems,
                availableWidth: availableWidth,
                widgetBandHeight: plan.widgetBandHeight,
                metrics: metrics
            )

            // 三样自上而下；接缝间距与 `HomeCalendarRow.rowSpacing` 同值（高度取舍算的就是这个数）。
            // `if` 与 plan 的档位一一对应：档位不给高度的带不进 VStack（不占间距、不占位置）。
            VStack(spacing: HomeCalendarRow.rowSpacing) {
                if plan.showsMainBand, !catalog.main.isEmpty {
                    HomeStripView(blocks: catalog.main, albumArtNamespace: albumArtNamespace)
                        .frame(height: plan.mainBandHeight, alignment: .topLeading)
                }

                if plan.showsWidgetBand, !catalog.widgets.isEmpty {
                    HomeWidgetBandView(
                        blocks: catalog.widgets,
                        plan: bands.widgets,
                        availableWidth: availableWidth,
                        albumArtNamespace: albumArtNamespace
                    )
                    .frame(height: plan.widgetBandHeight, alignment: .topLeading)
                }

                if showCalendar, plan.showsCalendarRow {
                    HomeCalendarRow()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// 两带的度量（宿主常量的唯一装配点，传给 `HomeBandedLayout`）。
    private static var metrics: HomeBandedLayout.Metrics {
        HomeBandedLayout.Metrics(
            mainSpacing: HomeStripLayout.spacing,
            mainTailReserve: HomeStripView.droppedHintWidth,
            widgetColumnSpacing: HomeStripView.widgetColumnSpacing,
            widgetRowSpacing: HomeStripView.widgetRowSpacing,
            widgetRowHeight: HomeStripView.widgetRowHeight,
            widgetTailReserve: HomeStripView.droppedHintWidth
        )
    }
}

// MARK: - 模块块的降级占位

/// 模块块画不出来时的浅色占位：只解释原因，不带交互。
///
/// 文字**显式浅色**（`.white.opacity`）：本项目在浅色系统外观下踩过 `.primary` / `.secondary`
/// 变黑的坑（与 `EventListView` 同一条约定）。
private struct HomeStripModulePlaceholder: View {
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.55))

            Text(reason)
                .font(.caption)
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
