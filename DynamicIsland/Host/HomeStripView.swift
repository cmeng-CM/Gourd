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
//  - **主块带**（`HomeStripView`，上）：大块（**T3 起只剩镜子**——音乐同批降为紧凑档，D-09）——
//    一条横向 strip，宽度按声明自适应、
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
/// **接管模块声明被接管块原本的那一档**——音乐 `200 / 250`、镜子 `140 / 140`
/// （两边都是**当前生产值**：音乐在 p5-home-blocks / T3 从 `300 / 420` 降到 `240 / 300`、
/// p6-ui-polish / T2 再缩为 `200 / 250`；镜子在 p5 同批从 `140 / 160` 收敛成方形；
/// 两处声明分别在 `MusicModule` / `MirrorModule` 的 `homeBlockWidth`，
/// 宿主经 `ModuleRegistry.homeBlockWidth(for:)` 取回）；**新增模块**用宿主统一声明的 `180 / 240`
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
    /// **单条流的名单**（P4 / docs/28 §4）：全部块按**同一条全局顺序**排——大块与紧凑块
    /// **不再分开**，分开就回不到用户排的那条顺序里了（流的行内可以同时有大块与紧凑块）。
    let blocks: [HomeBandBlock]

    /// 旧两条带的两份投影（T7 起的分带口径）。**生产路径已不再读它们**（接缝改走 `blocks` +
    /// `HomeFlowLayout`），保留是因为用例还在钉"形态声明把块分得对"这条不变式；
    /// 等分带那批用例整体迁到流口径后一并删除。
    var main: [HomeBandBlock] { blocks.filter { $0.formFactor == .large } }
    var widgets: [HomeBandBlock] { blocks.filter { $0.formFactor == .compact } }

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
        return HomeBandCatalog(blocks: sorted)
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
            // **内容内缩**（p7c / T2 / D-20）：内容与**板缘**（= 块框）之间留出可见余量——用户
            // 2026-10-02 反馈「每个玻璃块要比内容宽一些，现在都紧挨着显示了」。内缩加在**内容上**
            // （`HomeStripBlock` 的 content 层），格子的 `.frame(width:height:)`、两条布局的间距与
            // 板的矩形因此一概不动（板仍 = 块框）；取值见 `HomeBlockChrome`。
            HomeBandBlockContent(content: block.content)
                .padding(HomeBlockChrome.contentInsets(includeVertical: true))
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

// MARK: - 带级容器与块级 hover（T8 / docs/26 §做法 机制七 / D-10）

/// 首页的**视觉常量**：带级容器的横向内边距与块级 hover 的**唯一取值处**（T8 / D-10）。
///
/// 调研结论（机制七）是**不做每块的永久卡片**（Atoll 与 Nook X 都没有 per-block 容器；每块卡片
/// 要吃 8–16pt 内边距，而宽度预算正是最紧的）。分带时期那层「整条带共用一个极淡圆角底」的
/// 大底已撤（p6-ui-polish / docs/30 §做法 机制一 / D-02）：底把内容糊在一个大盒子里、块与块
/// 之间不可区分，正是用户第 1 条反馈；区分改由**每块自己的浮起层**（`homeBlockFloat()`）做
/// ——**p7b 起按底色档分两套、p7c 起玻璃档改判为「玻璃板」**：黑档仍是白光柔光池 + 白内容辉光，
/// 玻璃档是极淡整块底（板 + 柔影 + 顶缘微光，见 `HomeBlockFloatMetrics.plateOpacity` 一族与
/// docs/32 §做法 机制一）。**「不做卡片墙」的口径在 p7c 由用户放宽为「不加描边、可用极淡整块底」**
/// （留痕见 docs/32 头部；本节描述的「撤掉整条带的大底」仍然成立——板是**每块一块**，不是整条带）。
/// 「可交互的条目」仍在 hover 时给淡底——条目自己的 hover 状态由各自模块持有，**形状与浓度只有
/// 这一处**（三个调用点：前台应用格子 / 通知条目 / 待办条目——收敛前它们是 0.18+r5、0.08+r6、0.06+r6）。
enum HomeBandChrome {
    // **横向内边距已撤**（2026-10-07 / docs/32 D-23）：T8 起带级容器给内容左右各 8pt，底自 p6 起就不画了
    // （当时 `HomeBandContainerChrome` 只剩这道内边距，本次连同它一并删除）。用户 2026-10-07 反馈「首页本身的大背景框
    // 区域和里面的组件的边距有点大」——流的块因此外移 8pt，与日历行（从来不吃这道内缩）左缘对齐，
    // 面板内容四周的可见留白统一成 15pt（上 14 / 左右 15，见 docs/32 §D-24 的上屏读数）。
    // 机制连同常量一并删除（不留恒 0 的死旋钮）：`HomeBandedHomeView` 直接把整幅可用宽喂给流。

    /// 可交互条目的 hover 底浓度（机制七：0.06）。
    static let hoverOpacity: Double = 0.06

    /// 可交互条目的 hover 底圆角（机制七：与既有 `LauncherGridCell` 同形 = 8）。
    static let hoverCornerRadius: CGFloat = 8
}

// MARK: - 内容内缩（p7c / T2 / docs/32 §决策摘要 D-20）

/// **「内容四周内缩」一族常量的唯一取值处**（与 `HomeBandChrome` 同风格）：左右下三面由宿主装配、
/// 上面由各模块自装（原因见下）。
///
/// **为什么是内缩内容、不是放大板**（用户 2026-10-02 反馈原话「每个玻璃块要比内容宽一些，现在都
/// 紧挨着显示了」）：板自 T1 起**等于块框**（`.frame(width:height:)`、`HomeStripView.swift` 的
/// `HomeFlowView` 格子），而块框的宽度是布局分出来的——板往外长一圈就会吃掉块间那 8pt 缝
/// （`HomeStripLayout.spacing` / `HomeFlowLayout` 的 `columnSpacing`），把「块与块之间有 8pt」
/// 这条既有观感破掉。所以「板比内容宽」只能由**内容往里缩**得到：块的尺寸、位置、间距与板的矩形
/// 一概不动，只有内容的内边距新增这一层。
///
/// 起点值是**估的**，上屏实测后**定档在水平 5 / 垂直 0**（T2 报告与
/// `.workflow/p7c-home-plates/evidence/inset-measure.txt` 有逐块数据）：
///
/// - **水平 6 → 5**：起点 6 时进度块（用户反馈里圈的那一块）的内容区宽从 191 掉到 **179**，
///   低于 `ProgressHomeBlockLayout.allScopesWidth`（**180**，模块自己声明的「到这个宽就排得完五档」
///   门槛）→ 模块走「窄块退化」分支，五档只画 **3** 行，用户勾的「本季 / 今年」消失。
///   5 时内容区 **181 ≥ 180**（五档齐），而左右余量仍 ≥ 5pt（这正是验收判据的下界）。
///   **边界是算出来的**：模块要 180pt 内容宽，所以进度块的**分到宽必须 ≥ 180 + 2 × 内缩**——
///   5pt 对应 **≥ 190**（今天 191，只剩 1pt 余量）；分到宽落到 **≤ 189** 时它会退化成 3 行
///   （这是**既有**行为：内缩把这条门槛从 180 抬到了 190）。
/// - **垂直 4 → 0**（**宿主这一份**；2026-10-07 / docs/32 D-22 起顶部留白改由模块自装，见本节末）：
///   紧凑块只有 **96pt** 高，而进度块的五档当时是**按 96 紧配**的（5×14 + 4×6 = **94**，只余 2pt）。
///   按模块的高度档算式（`floor((H + 6) / 20)`）五档要求内容高 **≥ 94**，即**总内缩 ≤ 2pt
///   （每侧 ≤ 1pt）仍然安全**；上屏实测垂直内缩 4pt（总 8pt）→ 第五行掉出去。
///   取 **0** 而不是 1pt：省下的那 1pt 在视觉上等于零，却要把算式顶在 `94 = 94` 的边界上，不值当。
///
/// 改前实测余量 **0.0…1.5pt**（音乐 / 待办 / 通知 / 统计四块内容贴板缘）。
///
/// **与底色档无关**：内缩是**布局**（不在 `homeBlockFloat()` 的视觉层里），两档共用同一份——
/// 纯黑档（`.solidBlack`）的内容因此同获内缩，这是**预期**（黑档的池/辉光机制逐字未动）。
///
/// **2026-10-07 增补：上面这一维**（docs/32 D-22）。用户原话「除了 cpu 和镜像，其他组件的内容和背景玻璃块
/// 区域的上部分都挨的太近了，按照 cpu 那几个的上边距修改下」——统计块的 8pt（D-21）成了参照，
/// 其余各块的内容此前是**贴板顶**的（上屏实测 0.0…3.5pt 的墨迹余量）。三条取值都指向同一个
/// **可见结果**：块内首行内容的**墨迹上缘**落在板顶下 **≈7pt**（= 统计块环顶的实测值，
/// `.workflow/p7d-top-margins/evidence/` 有改前逐块读数）。
/// **墨迹 ≠ 内容框**：文字行自带行首留白（11pt 行 +2、10pt 居中表头行 +3.5），图形（封面 / 图标）
/// 的墨迹就是内容框上缘——三类因此取值不同，判据是「改后上屏读数一致」，不是「常量相等」。
/// 代价一处：进度块的行距 6 → 5（腾出 4pt 给上留白，五行仍在 96 里），见
/// `ProgressHomeBlockLayout.rowSpacing`。
enum HomeBlockChrome {
    /// 内容与板缘之间的**水平**余量（左右各一份）。**当前档位下的上界**（进度块分到 191pt 时 6 就把它
    /// 顶到模块 180pt 门槛之下——见上面的算术；分到宽 ≥ 190 是 5pt 成立的前提）。
    static let contentInsetHorizontal: CGFloat = 5
    /// 内容与板缘之间的**垂直**余量（上下各一份）。**恒 0**：紧凑块 96pt 而五档要 94pt
    /// （总内缩 ≤ 2pt 仍安全，但省下的 1pt 视觉上等于零、还要顶在算式边界上——见上面的算术）。
    static let contentInsetVertical: CGFloat = 0

    /// 两个站点**共用**的内缩装配（唯一算式）：单条流格子取**带垂直**的一份，日历行取**只水平**的一份。
    ///
    /// 日历行为什么不做垂直内缩：它的高度 `HomeCalendarRow.rowHeight` 是**按当月周数精算**出来的
    /// （`36N + 52`），月历网格按它精确排满——垂直再缩 4pt 会把网格的末行或题头裁掉（T2 的失败信号
    /// 之一）。板 = 行框、行框高度不变，因此只做水平。
    ///
    /// **顶部不走这里**（docs/32 D-22）：`contentInsetVertical` 恒 0（进度块的高度算术不许动），各块的
    /// 上留白由模块自己装（下面三条常量 + 统计块的 `StatsRingMetrics.homeBlockTopInset`）——
    /// 宿主代劳就无法按「首行是图形还是文字」分开取值。
    static func contentInsets(includeVertical: Bool) -> EdgeInsets {
        EdgeInsets(
            top: includeVertical ? contentInsetVertical : 0,
            leading: contentInsetHorizontal,
            bottom: includeVertical ? contentInsetVertical : 0,
            trailing: contentInsetHorizontal
        )
    }

    // MARK: - 内容顶部内缩（docs/32 D-22；模块自装，三条常量各按「首行是什么」）

    /// 图形起始的块（音乐的小封面 36 / 前台应用的应用图标 28）：墨迹 = 内容框上缘 → 取 7。
    ///
    /// 7 的来源是**上屏读数**：统计块的环顶墨迹（同一探针、同一判据）落在板顶下 **7.0pt**
    /// （`.workflow/p7d-top-margins/evidence/`），这两块取 7 后与它逐值一致。
    static let contentInsetTopGraphics: CGFloat = 7

    /// 文字起始的块（进度清单的首行 / 通知的表头与行）：11pt 文字在 14pt 行里自带 **+2.0pt** 行首
    /// 留白（上屏实测）→ 取 5 让墨迹同样落在 7.0pt。
    static let contentInsetTopText: CGFloat = 5

    /// 待办块的**表头行**（`TodoHomeHeader`，10pt 字 + 细进度条在 16pt 行里居中）：自带的行首留白是
    /// **+3.5pt**（上屏实测）→ 取 4 让墨迹落在 7.5pt（这一类没有更小的整数可取）。
    static let contentInsetTopListHeader: CGFloat = 4
}

/// 可交互条目的 **hover 底**（T8 的唯一一条 hover 规则，机制七）。
///
/// `isHovered` 由调用方给（它自己的 hover 状态；前台应用按 **id** 记，一格里悬停不能点亮整排）——
/// 本修饰符只定**形状与浓度**，不持有状态：模块侧的 `@State` 因此一行不用改，只把原来那两笔
/// 各自为政的 `.background(RoundedRectangle(cornerRadius: N).fill(.white.opacity(x)))` 换成本调用。
///
/// **纯展示块不套它**（机制七）：音乐封面 / 进度 / 统计环**不加永久边框**，也不给 hover 底——
/// 它们没有可点的东西，亮起来只会骗人。
struct HomeBlockHoverBackground: ViewModifier {
    let isHovered: Bool

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: HomeBandChrome.hoverCornerRadius, style: .continuous)
                .fill(Color.white.opacity(isHovered ? HomeBandChrome.hoverOpacity : 0))
        )
    }
}

extension View {
    /// 可交互条目的 hover 底（T8 的唯一一条规则）。调用方传自己的 hover 状态。
    func homeBlockHoverBackground(isHovered: Bool) -> some View {
        modifier(HomeBlockHoverBackground(isHovered: isHovered))
    }
}

// MARK: - 块级浮起（p6-ui-polish / docs/30 §做法 机制一 / D-01 · D-02；p7b 底色档自适应，docs/31 D-22）

/// 首页每块「浮起」样式的**唯一取值处**（p6 / docs/30 §做法 机制一；p7b / p7c 两轮改判见下）。
///
/// **当前口径（p7c）**：黑档 = 白光柔光池（块背后的径向渐变）+ 白内容辉光；玻璃档 = **极淡整块底
/// （玻璃板）** + 既有内容软影；两档的 hover 都再叠轻微放大 / 提亮。**不加描边**——p6 的原始约束是
/// 「不加区域块与边线」，p7c 经用户**放宽为「不加描边、可用极淡整块底」**（α14，留痕见 docs/32 头部），
/// 板因此没有 stroke / 发丝线，仍不是卡片墙。
///
/// 调研结论（机制一）：Apple 当前的层级语言是「界面元素浮起并区分其下内容」（HIG），macOS 26 的
/// 浮起件用**柔影**而不是描边；同类 notch 应用（boring.notch / NotchNook / Alcove）也无一使用
/// 卡片边框或 3D。因此静态区分靠「撤掉整条带的大底（T8 的带级容器自 p6 起不再画底，docs/32 D-23 连同
/// 它仅剩的横向内边距一并删除）+ 每块的
/// 浮起层」，hover 只做**视觉**提升——`scaleEffect` / `brightness` / `shadow` / 底（池或板）都不
/// 参与布局（邻居不被挤开，docs/30 §失败信号里「hover 时布局跳动」那条的判据就是它）。
///
/// **为什么黑档是白光而不是黑影**（T1 首轮独立审查实测）：面板底色是纯黑（`ContentView` 的
/// `Color.black`），黑 `.shadow` 在黑底上恒为零效果——静态区分与 hover「加深」都看不见。
/// **为什么光池为主**（Checkpoint 二轮实机测量）：纯内容辉光在空区只抬 0.07–0.5/255，仍不可见，
/// 故静态区分交给柔光池，辉光只作内容边缘的辅光。两者都是**无填充边界、无描边**的光。
///
/// **p7b 起按底色档分成两套**（`Surface` / docs/31 D-22）：上面这条「白光池」的论证前提是**纯黑底**
/// ——毛玻璃底（behindWindow 材质、采样屏后内容）是**亮底**，白光池在它上面只贡献 ≈ +11/255、
/// 被材质自身的 ±4–5 起伏淹没（p7 T1 已测到，本次复现一致；数字见 docs/31 §接口 1）。亮底上做
/// 区分要**减亮**：p7b 因此给玻璃档改用黑色柔影池 + 黑色软影。
///
/// **p7c 再改判玻璃档的机制**（docs/32 / D-01 · D-08）：黑色柔影池**同样不表达边界**（p7b 上屏实测
/// 块心相对本地基线 −16~−18/255、纵向 ±96px 平滑单谷、**无台阶**——到块边缘已归零，缝两侧一样暗）。
/// 玻璃档的浮起因此改成**玻璃板**（见下面 `plate*` 常量族）：极淡整块底 + 柔影 + 顶缘掩码微光，
/// 板缘是一条**台阶**；玻璃档的 `poolOpacity` 恒 0（不画池）。黑档（`.solidBlack`）白光两层逐字不变。
///
/// **brightness 的口径**：`hoverBrightness` 是「1.0 = 不改」的乘性口径（与 `hoverScale` 同形），
/// 组装成**增量**才交给 `.brightness(_:)`（它的入参是增量，0 = 不改）——`effects(hovered:surface:interactive:)`
/// 里 `- 1`，把 1.06 直接传进去会白到看不清（A1 的「块的可读性不降」）。
///
/// 常量是**上屏调参后的定稿值**（起点值见 docs/31 §接口与数据形状第 1 小节的留痕口径；本组先按
/// p6 的一轮实机调参：辉光 0.05/4 → 0.08/5、hover 0.10/10 → 0.16/11；p7 再按用户「不 hover 也要
/// 能分清区域」的反馈整组上调：辉光 0.08/5 → **0.10/6**、柔光池 0.06 → **0.13**、hover 池 0.12 →
/// **0.20**、hover 辉光 0.16/11 → **0.20/12**，池系数放到不变量上限 **0.50**）；本文件不再有第二份。
/// 测试钉 **`effects(hovered:surface:interactive:)` 两档 × 两底色档**（不是单钉常量）：常驻中性 +
/// 半径 / 不透明度为正，hover 两项更大、增量落在可读区间（1.005…1.05 / 0.02…0.12）。
enum HomeBlockFloatMetrics {
    /// 常驻辉光的不透明度（白，低透明度 = 无填充的深度感）。
    ///
    /// 留痕：起点 0.05（实机几乎不可见）→ p6 调参 **0.08** → p7 再上调 **0.10**（静态区分加强）。
    static let idleGlowOpacity: Double = 0.10
    /// 常驻辉光的半径（留痕：起点 4 → p6 **5** → p7 **6**，与不透明度同批上调）。
    static let idleGlowRadius: CGFloat = 6
    /// hover 的辉光不透明度（比常驻大 = 「加深」的一半；留痕：起点 0.10 → p6 **0.16** → p7 **0.20**）。
    static let hoverGlowOpacity: Double = 0.20
    /// hover 的辉光半径（比常驻大 = 「加深」的另一半；留痕：起点 10 → p6 **11** → p7 **12**）。
    static let hoverGlowRadius: CGFloat = 12
    /// 柔光池中心的白色不透明度（径向渐变到全透明）。**静态区分的主力**：纯辉光在实机屏幕上
    /// 空区只抬 0.07–0.5/255（p6 Checkpoint 二轮测量），池给出可见的一圈光。
    ///
    /// 留痕：起点 0.06（p6 实机仍近不可见，用户 p7 反馈「不悬浮分不清区域」）→ p7 上调 **0.13**。
    /// **上屏实测已完成**（2026-10-01）：首轮即达标（缝 0.00 / 块内 27.9/255、峰 33 / 扫描无台阶），
    /// **0.13 即最终值**，未再上调到 0.18 档（数字与证据见 docs/31 §接口第 1 小节与 T1 报告）。
    static let poolOpacity: Double = 0.13
    /// hover 的柔光池中心不透明度（比常驻大 = 池变亮；留痕：0.12 → p7 **0.20**）。
    static let hoverPoolOpacity: Double = 0.20
    /// 柔光池的半径系数：`endRadius = min(w, h) × factor`——唯一算式在 `poolEndRadius(width:height:)`。
    ///
    /// **系数必须 ≤ 0.5**：格子的**最近边**在 `0.5 × min(w, h)` 处，系数过大会让渐变在边缘还没走完
    /// ——0.7 时边缘仍残留 28.6% 强度（idle ≈4.4/255、hover ≈8.7/255），在格子边缘形成**直角台阶**
    /// = 变相底板（p6 T1 三轮独立重审实测；且与「渐变到全透明、无边界」的口径不符）。
    ///
    /// 留痕：p6 收敛到 **0.45**（留余量）；p7 用户仍反馈区分不足，放到**不变量上限 0.50**——渐变
    /// 恰在最近边归零（三停渐变让尾部更软，边缘不留强度），系数不再有上调空间（> 0.5 即破不变量）。
    ///
    /// **不设最小半径下界**（终审修复）：曾写成 `max(48, …)`，`min(w, h) < 96` 的格子（如矮块
    /// 40pt 档）会被下界顶过最近边（`48 > 0.5 × 40 = 20`）——渐变在边缘还没归零，又变回直角台阶
    /// = 变相底板。下界就此删掉，短边再小也按同一系数走。
    static let poolEndRadiusFactor: CGFloat = 0.50

    /// 柔光池的**有效** endRadius（唯一算式；`HomeBlockFloatModifier` 只消费它）。
    ///
    /// `min(w, h) × factor` + **非负 guard**（GeometryReader 的尺寸理论上非负，但 0 也不该产生
    /// 负半径）——**无下界**：任何尺寸下都 ≤ `0.5 × min(w, h)`，渐变**必然在最近边之前归零**
    /// （终审修复；这条不变量由 `testHomeBlockPoolRadiusNeverCrossesTheNearestEdge` 按块高
    /// 40 / 96 / 140 三档钉住，不只钉系数）。**两档共用这条算式**（p7b）：玻璃档的暗影池与黑档的
    /// 白光池是同一个几何——只换颜色与不透明度，半径不变量不因档位而变。
    static func poolEndRadius(width: CGFloat, height: CGFloat) -> CGFloat {
        max(0, min(width, height) * poolEndRadiusFactor)
    }

    // MARK: - 底色档（p7b / docs/31 §接口 1 · D-22）

    /// 面板**底色档**：浮起效果按「底是暗还是亮」自适应（p7b 修复的机制核心）。
    ///
    /// - `.dark`（面板 `.solidBlack`）：沿用 p6/p7 的白光两层（白光柔光池 + 白色内容辉光），
    ///   **数值逐字不变**——暗底加亮是这套常量的原始前提；
    /// - `.glass`（面板 `.frostedGlass` / `.liquidGlass`，behindWindow 材质、采样屏后内容）：
    ///   **p7c 起是「玻璃板」**（极淡整块底 + 柔影 + 顶缘微光，`plate*` 常量族）——亮底上的区分改由
    ///   **板缘的台阶**给出；p7b 的黑色柔影池已撤（池恒 0，见下面的常量注）。
    ///
    /// 为什么必须分档：p7 T1 已在毛玻璃底上测到白光池只贡献 ≈ **+11/255**，而玻璃底的自身起伏
    /// 就有 ±4–5/255（同一块内不同角落的本地基线可差 ≈11）——贡献被材质淹没，肉眼不可辨
    /// （复现数字与「修复前」证据见 docs/31 §接口 1 与 `.workflow/p7b-glass-float/evidence/`）。
    enum Surface: Equatable {
        case dark
        case glass
    }

    /// 面板底色档 → 浮起效果档（三档映射的唯一权威处；两个玻璃档同走 `.glass`——
    /// 两者的材质细节不同，但「亮底减亮」的机制与取值同源）。
    static func surface(for style: NotchPanelBackgroundStyle) -> Surface {
        switch style {
        case .solidBlack: return .dark
        case .frostedGlass, .liquidGlass: return .glass
        }
    }

    // **p7c 起玻璃档不画池**：块心柔光池（p7b 的黑色柔影池：定稿 0.13 / hover 0.20，起点值经一轮
    // 上屏调参上调的过程见 docs/31 §接口 1 与 `.workflow/p7b-glass-float/evidence/p7b-measure.txt`）
    // 在毛玻璃底上两轮实测都**不表达边界**（p7b 实测块心相对本地基线 −16~−18/255、纵向平滑单谷、
    // 无台阶），已被**玻璃板**取代（docs/32 §做法 机制一）——取自 p7b 的 `glassPoolOpacity` /
    // `glassHoverPoolOpacity` 两个常量因此已删（p7b 的取值与结论仍留在 docs/31 与那份 evidence 里）。
    /// 玻璃档内容软影的黑色不透明度（起点 0.18 → **0.22**）。
    static let glassShadowOpacity: Double = 0.22
    /// 玻璃档内容软影的半径（起点 9 → 定稿仍 9；未观察到文字糊边）。
    static let glassShadowRadius: CGFloat = 9
    /// 玻璃档内容软影的 y 偏移（起点 1，带一点「浮起」方向；**黑档恒 0，逐字不变**）。
    static let glassShadowYOffset: CGFloat = 1
    /// 玻璃档 hover 的影黑不透明度（起点 0.28 → **0.34**）。
    static let glassHoverShadowOpacity: Double = 0.34
    /// 玻璃档 hover 的影半径（起点 13 → 定稿仍 13）。
    static let glassHoverShadowRadius: CGFloat = 13
    /// 玻璃档 hover 的影 y 偏移（起点 2 → 定稿仍 2）。
    static let glassHoverShadowYOffset: CGFloat = 2

    // MARK: - 玻璃板（p7c / docs/32 §做法 机制一 · §接口 1）

    /// 玻璃档的「浮起」自 **p7c** 起由**块心柔光池**改判为**极淡整块底（玻璃板）**：板 = 块的完整
    /// 框（`RoundedRectangle` 黑填充 + 同形柔影 + 顶缘掩码微光），因此**板缘就是一条台阶**——
    /// 正是旧池缺的东西（旧池从块心向外衰减，到块边缘已归零，缝两侧一样亮）。
    ///
    /// **板不是描边、也不是卡片底**（守用户 p6 起的「不加边线」）：三层全是填充 / 影 / 掩码软渐变，
    /// 没有 stroke、没有发丝线；α 由用户在 α10/α14/α18 合成预览上选定 **0.14**。
    ///
    /// 纯黑档（`.solidBlack`）不画板（`plateOpacity = 0`），仍走白光池 + 白辉光，**逐字不变**。
    /// 板填充的黑不透明度（起点 = 用户选定 α14）。
    static let plateOpacity: Double = 0.14
    /// hover 的板不透明度（比常驻深一档 = 「hover 加深」；放大 / 提亮两档不动）。
    static let hoverPlateOpacity: Double = 0.19
    /// 板的圆角（面板圆角 − 内容内边距的近似；与块框同形，不参与布局）。
    static let plateCornerRadius: CGFloat = 15
    /// 板柔影的色不透明度（**× 板的 α** → 有效影深 ≈ 0.126）：把两块之间的缝压成一条浅谷。
    static let plateShadowOpacity: Double = 0.9
    /// 板柔影的半径。
    static let plateShadowRadius: CGFloat = 10
    /// 板柔影的 x 偏移（与 y 一起给「浮起」一个方向）。
    static let plateShadowX: CGFloat = 1
    /// 板柔影的 y 偏移。
    static let plateShadowY: CGFloat = 2
    /// 板**顶缘微光**的白不透明度（镜面高光那一笔；**掩码软渐变，不是描边**——D-05）。
    static let plateTopHighlightOpacity: Double = 0.06
    /// 顶缘微光在**板高**上的覆盖比例（自上而下到 `.clear`）。
    static let plateTopHighlightFraction: CGFloat = 0.45

    /// hover 的放大倍率（1.0 = 不改；只做视觉缩放，不动 frame）。
    static let hoverScale: CGFloat = 1.02
    /// hover 的提亮（乘性口径，1.0 = 不改；组装时减 1 成增量）。
    static let hoverBrightness: Double = 1.06
    /// hover 进出的动画时长（`.smooth`）。
    static let duration: Double = 0.2

    /// 修饰符**真正消费**的那份效果值（`homeBlockFloat()` 只读它，不自己碰常量——常量到应用的
    /// 算式因此可被纯函数测试钉住：改错映射（如去掉 brightness 的 `- 1`、把两档接反）会让
    /// `testHomeBlockFloatMetricsStayInTheLegibleRange` 变红；档位映射改错会让
    /// `testGlassSurfaceUsesDarkVeilEffects` 变红）。
    ///
    /// 五项与 SwiftUI 一一对应：`scale` → `.scaleEffect`、`brightness` → `.brightness`（**增量**）、
    /// `glowRadius`/`glowOpacity` → `.shadow(color: 档位色.opacity(glowOpacity), radius: glowRadius,
    /// y: shadowYOffset)`（黑档白辉光 + y 恒 0 = 逐字不变；玻璃档黑影 + y 1/2）、
    /// `poolOpacity` → 柔光池径向渐变的中心色 `opacity`（黑档白、玻璃档黑，由 `poolIsDark` 选；
    /// **p7c 起玻璃档恒 0** = 不画池）。
    ///
    /// 三个档位字段（p7b）：`poolIsDark` / `shadowIsDark` 给**颜色语义**（`true` = 黑/暗），
    /// `shadowYOffset` 给内容影的 y——修饰符只按它们选色与摆影，不自己写常量。
    ///
    /// **玻璃板字段（p7c）**：`plateOpacity` → 板的填充 α（黑档 = 0 = 不画板）、
    /// `plateCornerRadius` → 板的圆角、`plateShadow*` → 板柔影、`plateTopHighlight*` → 顶缘微光的
    /// 不透明度与覆盖比例（掩码软渐变）、`plateIsDark` → 板的颜色语义（本批两档都是黑板，只有 α 分档）。
    struct FloatEffects: Equatable {
        let scale: CGFloat
        let brightness: Double
        let glowRadius: CGFloat
        let glowOpacity: Double
        let poolOpacity: Double
        /// 池的颜色语义（`true` = 黑/暗色池；`false` = 白/亮色池）。
        let poolIsDark: Bool
        /// 内容影（`.shadow` 那一层）的颜色语义（黑档白辉光 = `false`；玻璃档黑影 = `true`）。
        let shadowIsDark: Bool
        /// 内容影的 y 偏移（黑档恒 0——逐字不变；玻璃档 1 / hover 2）。
        let shadowYOffset: CGFloat

        // MARK: 玻璃板字段（p7c / docs/32 §接口 2）

        /// 板填充的黑不透明度（玻璃档 = 板 α，hover 更深；**黑档 = 0 = 不画板**）。
        let plateOpacity: Double
        /// 板的圆角。
        let plateCornerRadius: CGFloat
        /// 板柔影的色不透明度 / 半径 / x / y（板不画时无消费者）。
        let plateShadowOpacity: Double
        let plateShadowRadius: CGFloat
        let plateShadowX: CGFloat
        let plateShadowY: CGFloat
        /// 顶缘微光的不透明度与它在板高上的覆盖比例（掩码软渐变）。
        let plateTopHighlightOpacity: Double
        let plateTopHighlightFraction: CGFloat
        /// 板的颜色语义（`true` = 黑/暗色板——两档都是「黑板」，改动点只有 α：黑档恒 0）。
        let plateIsDark: Bool
    }

    /// 两档（常驻 / hover）× 底色档（暗 / 玻璃）的效果值：常驻档是**中性**（scale = 1、brightness = 0），
    /// 光的两层（柔光池 + 内容辉光）常驻可见。
    ///
    /// `surface` 只决定**光的颜色与取哪一套常量**：`.dark` 走白光两层、五个数值与 p7 定稿逐字相同；
    /// `.glass` 走**玻璃板**（p7c：板 + 既有内容软影；池恒 0）。放大 / 提亮两档不动
    /// （`hoverScale` / `hoverBrightness` 与底色无关——它们作用在内容上，不是「底」）。
    ///
    /// **`interactive`（p7c / D-13）**：`false` 的站点（日历行——纯展示块、自带 `onHover`）拿的是
    /// **常驻档**——effects 与 `hovered` 无关、`scale` / `brightness` 恒中性（由 `active` 一处收口）。
    static func effects(hovered: Bool, surface: Surface, interactive: Bool = true) -> FloatEffects {
        // 纯展示站点：hovered 不参与（`active` 恒 false）——effects 因此与 `hovered` 无关。
        let active = interactive && hovered
        switch surface {
        case .dark:
            return FloatEffects(
                scale: active ? hoverScale : 1,
                brightness: active ? hoverBrightness - 1 : 0,
                glowRadius: active ? hoverGlowRadius : idleGlowRadius,
                glowOpacity: active ? hoverGlowOpacity : idleGlowOpacity,
                poolOpacity: active ? hoverPoolOpacity : poolOpacity,
                poolIsDark: false,
                shadowIsDark: false,
                shadowYOffset: 0,
                plateOpacity: 0,
                plateCornerRadius: plateCornerRadius,
                plateShadowOpacity: plateShadowOpacity,
                plateShadowRadius: plateShadowRadius,
                plateShadowX: plateShadowX,
                plateShadowY: plateShadowY,
                plateTopHighlightOpacity: plateTopHighlightOpacity,
                plateTopHighlightFraction: plateTopHighlightFraction,
                plateIsDark: true
            )
        case .glass:
            return FloatEffects(
                scale: active ? hoverScale : 1,
                brightness: active ? hoverBrightness - 1 : 0,
                glowRadius: active ? glassHoverShadowRadius : glassShadowRadius,
                glowOpacity: active ? glassHoverShadowOpacity : glassShadowOpacity,
                // p7c：玻璃档**不再画柔光池**（被板取代——两轮实测证明池心池不表达边界）。
                poolOpacity: 0,
                poolIsDark: true,
                shadowIsDark: true,
                shadowYOffset: active ? glassHoverShadowYOffset : glassShadowYOffset,
                plateOpacity: active ? hoverPlateOpacity : plateOpacity,
                plateCornerRadius: plateCornerRadius,
                plateShadowOpacity: plateShadowOpacity,
                plateShadowRadius: plateShadowRadius,
                plateShadowX: plateShadowX,
                plateShadowY: plateShadowY,
                plateTopHighlightOpacity: plateTopHighlightOpacity,
                plateTopHighlightFraction: plateTopHighlightFraction,
                plateIsDark: true
            )
        }
    }
}

/// 首页块的**浮起**样式（p6 / docs/30 §做法 机制一）：常驻柔光池（为主）+ 内容辉光（为辅），
/// hover 时两层一起加深、再叠轻微放大 / 提亮。**p7b 起按面板底色档自适应**（docs/31 D-22）：
/// 黑档白光两层（逐字不变）、p7b 的玻璃档黑色柔影两层。**p7c 起玻璃档再改判**
/// （docs/32 §做法 机制一 / D-01 · D-08）：玻璃档的浮起由**块心柔光池**改为**极淡整块底（玻璃板）**
/// ——板 = 块的完整框（同形圆角矩形黑填充 + 同形柔影 + 顶缘掩码微光），板缘因此是一条**台阶**；
/// 池在玻璃档恒 0（不画）。黑档路径一个字节没动。
///
/// **`interactive` 分两种装配**（p7c / D-13 · D-14）：`true`（单条流格子）= 内容装饰（scale /
/// brightness / compositingGroup / 内容影）+ 底（黑档池、玻璃档板）+ 顶缘微光 + hover；
/// `false`（日历行 = 纯展示站点）= **只画板**（玻璃档）/ **一层都不装**（纯黑档不画板）——
/// 不装内容软影、不装 hover、不装 scale / brightness（`docs/32 §做法 机制二` 对该站点的口径是
/// 「只给板，不给 hover 放大 / 提亮」；该站点在改动前本来就没有任何浮起层）。
///
/// 状态（`hovered`）**就地持有**：它是纯视觉状态、没有第二处消费者（与 `HomeBlockHoverBackground`
/// 的「状态由调用方给」不同——那条规则要按 id 区分行内条目，这条规则一格一态）。
///
/// 效果值一律走 `HomeBlockFloatMetrics.effects(hovered:surface:interactive:)`——本修饰符不碰常量、
/// 不写算式；只有三处「选色」按 `FloatEffects` 的档位字段做（`poolIsDark` / `shadowIsDark` /
/// `plateIsDark` → `Color`）。
/// 底色档读 `Defaults[.notchPanelBackgroundStyle]`（`@Default` 是 `DynamicProperty`——设置页拨档
/// 后这里立即重绘；同 `ParallaxMotionModifier` 先例）。**不存在第二处读这份偏好**：块的视觉只此一处。
///
/// **`compositingGroup()` 在辉光之前**：不合成的话 `.shadow` 会逐个子视图各画一道（块内的字与
/// 图标各自带影，正是 docs/30 §失败信号里「块内容被辉光糊住」的样子）；合成后整格只有一道轮廓
/// 光（面板级阴影在 `ContentView` 里也是这么用的）。它只改绘制、不改布局。
///
/// **两层底画在 `.shadow` 之后**（`.background` / `.overlay` 永远画在被修饰视图之下 / 之上）：
/// 它们因此**不参与**缩放与提亮、也不进辉光的轮廓（辉光仍只描内容）；两层都不参与命中
/// （`allowsHitTesting(false)`），且铺满整格 = 零布局成本。
/// - **黑档**：池的 `endRadius` 用**格子的**短边算且系数 ≤ 0.5（最近边在 `0.5 × min(w, h)` 处）
///   ——渐变**在边缘之前就归零**，没有填充边界、没有描边、也不留直角台阶（不是卡片底）。
/// - **玻璃档（p7c）**：板刻意**与块框同框**（不内缩）——这正是「台阶」的来源；板不进命中、
///   不改尺寸，内容的包围盒因此必然落在板内（D-03）。
///
/// **池的渐变自 p7 起是三停**（`0 → poolOpacity`、`0.6 → poolOpacity × 0.35`、`1 → .clear`，见
/// docs/31 §做法 机制一）：两停时亮度到尾巴才塌，三停把中段压平、尾段拉长，光晕更软更长（仍到
/// 全透明归零，不出现边界）。**p7c 起这三停只有黑档用**（玻璃档的 `poolOpacity` 恒 0 = 不画池）。
struct HomeBlockFloatModifier: ViewModifier {
    /// 是否**装 `onHover`**（`false` = 纯展示站点：effects 与 hover 无关、不装 hover——D-13，日历行用）。
    let interactive: Bool

    @State private var hovered = false
    /// 面板底色档（p7b / docs/31 D-22）：经 `HomeBlockFloatMetrics.surface(for:)` 映射到效果档。
    @Default(.notchPanelBackgroundStyle) private var panelStyle

    init(interactive: Bool = true) {
        self.interactive = interactive
    }

    func body(content: Content) -> some View {
        let surface = HomeBlockFloatMetrics.surface(for: panelStyle)
        let effects = HomeBlockFloatMetrics.effects(
            hovered: hovered,
            surface: surface,
            interactive: interactive
        )
        // 档位着色：黑档白（`.white`，y 恒 0 = 逐字不变）、玻璃档黑（亮底减亮）。只读 effects 字段。
        let shadowColor: Color = effects.shadowIsDark ? .black : .white
        let poolColor: Color = effects.poolIsDark ? .black : .white
        let plateColor: Color = effects.plateIsDark ? .black : .white

        if !interactive {
            // **纯展示站点（日历行）：只画板**（docs/32 §做法 机制二「只给板，不给 hover 放大 / 提亮」·
            // D-13 · D-14）——不装内容软影（该站点在改动前没有任何浮起层，「只给板」就是没有软影这一层）、
            // 不装 hover；scale / brightness 也不装（effects 的 `active` 已恒中性，这里索性不装）。
            if surface == .dark {
                // 纯黑档不画板（`plateOpacity = 0`）→ 该站点**一层都不装**，与改动前逐字相同
                // （D-06 零回归：照「常驻档」原样消费会给它凭空长出一圈白光池，半径 ≈116）。
                content
            } else {
                content
                    .background {
                        HomeBlockPlateBackground(effects: effects, color: plateColor)
                    }
                    .overlay {
                        HomeBlockPlateTopHighlight(effects: effects)
                    }
            }
        } else {
            content
                .scaleEffect(effects.scale)
                .brightness(effects.brightness)
                .compositingGroup()
                .shadow(
                    color: shadowColor.opacity(effects.glowOpacity),
                    radius: effects.glowRadius,
                    y: effects.shadowYOffset
                )
                .background {
                    if surface == .dark {
                        // 黑档：白光柔光池（p7 定稿，逐字不变）。
                        GeometryReader { geo in
                            RadialGradient(
                                stops: [
                                    .init(color: poolColor.opacity(effects.poolOpacity), location: 0),
                                    .init(color: poolColor.opacity(effects.poolOpacity * 0.35), location: 0.6),
                                    .init(color: .clear, location: 1),
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: HomeBlockFloatMetrics.poolEndRadius(
                                    width: geo.size.width,
                                    height: geo.size.height
                                )
                            )
                        }
                        .allowsHitTesting(false)
                    } else {
                        // 玻璃档：板（p7c）——同形圆角矩形黑填充 + 同形柔影。
                        HomeBlockPlateBackground(effects: effects, color: plateColor)
                    }
                }
                .overlay {
                    // 玻璃档的顶缘微光（p7c / D-05）：掩码软渐变，**不是 stroke**。黑档不装（逐字不变）。
                    if surface == .glass {
                        HomeBlockPlateTopHighlight(effects: effects)
                    }
                }
                .animation(.smooth(duration: HomeBlockFloatMetrics.duration), value: hovered)
                // `onHover` 只装在**交互站点**上（D-13：纯展示站点自带一条 `onHover`——日历行的
                // `vm.isHoveringCalendar` 面板收起遮罩——两层叠加会打架；上面那个分支因此整段不装它）。
                .onHover { hovered = $0 }
        }
    }
}

/// 玻璃板的**板底**（p7c / docs/32 §做法 机制一 1–2）：同形圆角矩形黑填充（`plateOpacity`）+
/// 同形柔影（`plateShadowOpacity` / `plateShadowRadius` / x / y）——填充**均匀**（不是径向渐变），
/// 因此**板缘就是一条台阶**，影把两块之间的缝压成一条浅谷。**无描边**。板不进命中、不改尺寸。
private struct HomeBlockPlateBackground: View {
    let effects: HomeBlockFloatMetrics.FloatEffects
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: effects.plateCornerRadius, style: .continuous)
            .fill(color.opacity(effects.plateOpacity))
            .shadow(
                color: .black.opacity(effects.plateShadowOpacity),
                radius: effects.plateShadowRadius,
                x: effects.plateShadowX,
                y: effects.plateShadowY
            )
            .allowsHitTesting(false)
    }
}

/// 玻璃板的**顶缘微光**（p7c / docs/32 §做法 机制一 3）：白 `plateTopHighlightOpacity` → `.clear`
/// 的 `LinearGradient`（自上而下到 `plateTopHighlightFraction`）**掩码**到同形圆角矩形——「镜面
/// 高光」的那一笔。**必须是掩码软渐变，禁止 stroke**（用户 p6 起的持续约束 / D-05）。
private struct HomeBlockPlateTopHighlight: View {
    let effects: HomeBlockFloatMetrics.FloatEffects

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(effects.plateTopHighlightOpacity), location: 0),
                .init(color: .clear, location: effects.plateTopHighlightFraction),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .mask {
            RoundedRectangle(cornerRadius: effects.plateCornerRadius, style: .continuous)
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// 首页块的浮起样式（p6 / docs/30 §做法 机制一；p7c 起玻璃档是**玻璃板**，板 = 站点的 frame）。
    /// 两个调用点：`HomeFlowView` 的格子（默认档，套在格子的 `.frame(width:height:)` 之后——视觉修饰
    /// 不改格子尺寸）与 `HomeCalendarRow` 的根帧（`interactive: false`——板 = 行框，见 D-13 / D-14）。
    func homeBlockFloat(interactive: Bool = true) -> some View {
        modifier(HomeBlockFloatModifier(interactive: interactive))
    }
}

// MARK: - 主块带

/// 首页的**主块带**（大块：**T3 起只剩镜子**）：一条横向 strip，规格逐字沿用 P2 批次
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
    /// **数值 = 大块档高度 `HomeFlowView.largeBlockHeight`（140）**，不再是一个独立挑出来的数：
    /// 大块带里最高的那个块就是档高，带至少要装得下它。**来源在 T3 换过**——
    /// 上一版是 152，从音乐块（当时唯一的大块，宽 300/420、形态 `.large`）的封面量出来：
    /// `18`（块内顶部偏移，封面起点）+ `133`（420 宽下封面边长）≈ 151.5 → 取整 152
    /// （实测截图见 `.workflow/p2-calendar-row/reports/` §6.5）。
    ///
    /// **T3 起音乐降为紧凑档**（`240/300` / `.compact`，D-09；p6 / T2 再缩为 `200/250`），
    /// 那个来源随之消失；今天的档高由
    /// **镜子的方形边长**选定（`MirrorModule.homeBlockWidth` 的 `min`/`ideal`，同一批收敛成方形）：
    /// 圆的直径 `= min(分到的宽, 行高)`，所以取块的最小宽 = 档高 = 圆的直径，一个数管三件事。
    /// **不能「实测」**：镜子的块体是 `CameraPreviewView`（`GeometryReader` + `.aspectRatio(1, .fit)`），
    /// 没有固有高度——「量自然高」量到的就是当时的档高，是循环（docs/29 §已知限制 7）。
    /// 低于阈值即整条不画（这一档由 `HomeVerticalFit` 让位给小组件带）。
    static let minimumUsableHeight: CGFloat = HomeFlowView.largeBlockHeight

    /// 条尾 `＋N` 提示的**预留位宽度**（docs/21 §备选与取舍 ②：固定，不按块数伸缩）。
    ///
    /// **唯一取值在这里**：两带都拿它喂 `plan(…:tailReserve:)` / 喂 `HomeStripLayout(tailHintWidth:)`
    /// ——两处必须同值，否则「预留出来的位置」与「画提示的位置」会不是同一个 34pt。
    /// 取值依据：`＋N` 的 N 是一位到两位数（32~36pt 足够放下，docs/21 §已知限制 1）。
    static let droppedHintWidth: CGFloat = 34

    /// 小组件带**每行的高度**（定值：紧凑块是等高网格，行不随可用高度伸缩）。
    ///
    /// 取值依据（T7 的高度预算，docs/26 §做法 机制六的「代价」一节）：默认面板 1154×630 的可内容高
    /// ≈562pt，日历行（当时固定 294；**现为按当月的 `36N + 52`，10 月 232**，见
    /// `HomeCalendarRow.rowHeight(forMonth:calendar:)`）+ 主块带最小高度（当时 152；**现为大块档
    /// 140**）+ 两个间距（16）之后只剩 **100pt**——96 是
    /// **既不挤掉日历行、又高得下紧凑块内容**的一档（统计三行 ≈64、进度两行 ≈52、待办三环 52 +
    /// 一行清单）。再高一档（如 112）会把默认高度下的日历行挤掉，而那正是用户要保留的行（T4 还要给它
    /// 加农历与节假日）——宁可让网格矮一点，也不让默认档先丢日历行。
    ///
    /// **这张预算表是分带时代的**（tune 后核过一遍）：单条流接手后这条带**不在生产路径上**，
    /// 96 今天的身份是「紧凑档」的块高（`HomeFlowView.compactBlockHeight`，见 docs/26 §已知限制 7）。
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

// MARK: - 单条流（P4 / docs/28 §4）

/// 首页的**单条流**：把 `HomeFlowLayout` 算出来的行摆出来。
///
/// 每条行 = 一个 `HStack`（格宽由 `plan` 定，**不是**由 Layout 反推）；行高 = 该行最高块，
/// 格子在行内**顶对齐、不拉伸**（P4 之前大块会把整条带撑高，其余块被迫挤在另一条带里）。
///
/// **为什么不用自定义 `Layout`**：旧主块带那条路上有一个尺寸反馈环（`sizeThatFits` 上报的宽度
/// 被下一趟当成提案宽 → plan 重算缩水，见 `HomeStripLayoutMath` 的注释与 docs/23 的 770pt 复现）。
/// 这里每个格子都带**显式 `.frame(width:)`**，`HStack` 的总宽就是"各格宽 + 间隙"，不存在
/// "上报宽度再被拿来当输入"的那条回路——环因此不存在，不需要再钉提案宽。
struct HomeFlowView: View {
    /// 流的名单（**未切带**的全局顺序；`plan.rows[].indices` 是它在 `items` 里的下标）。
    let blocks: [HomeBandBlock]
    let plan: HomeFlowLayout.Plan
    let albumArtNamespace: Namespace.ID
    let columnSpacing: CGFloat

    /// 大块/紧凑块**各自的高度档**：块的形态声明（`homeFormFactor`）→ 高度。
    ///
    /// `large` 取 **140**（T3 起）：它是**选定**的，不是量出来的——首页上唯一的大块是镜子
    /// （音乐同批降为紧凑档），它的块体是 `CameraPreviewView`（`GeometryReader` + `aspectRatio(1, .fit)`），
    /// **没有固有高度**（圆的直径 = `min(分到的宽, 行高)`，实测只会量到当前档高，是循环）。
    /// 故选「镜子的方形边长 = 块的最小宽 = 140」为档高，并与 `MirrorModule.homeBlockWidth`
    /// 同源（那边直接引用本常量）；`HomeStripView.minimumUsableHeight` 也取本常量——
    /// **这三个数是一个数**（docs/29 §做法 机制四 / §已知限制 7；改动前是 152，来源是音乐封面，
    /// 那个来源已随音乐降档消失）。
    /// `compact` 取 **96**：与旧小组件带的行高同值，紧凑块们本来就按这一档画的。
    static func blockHeight(for formFactor: HomeFormFactor) -> CGFloat {
        switch formFactor {
        case .large: return largeBlockHeight
        case .compact: return compactBlockHeight
        }
    }

    static let largeBlockHeight: CGFloat = 140
    static let compactBlockHeight: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: plan.rowSpacing) {
            ForEach(Array(plan.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(Array(row.indices.enumerated()), id: \.offset) { position, blockIndex in
                        HomeBandCell(block: blocks[blockIndex], albumArtNamespace: albumArtNamespace)
                            .frame(width: row.widths[position], height: row.height, alignment: .topLeading)
                            // 每块「浮起」（p6 / docs/30 §做法 机制一；p7c 起玻璃档是**玻璃板**）：
                            // 黑档 = 常驻柔光池（为主）+ 内容辉光（为辅）；玻璃档 = 板 + 内容软影，
                            // hover 时一起加深再叠轻微放大 / 提亮。套在 `.frame`
                            // **之后**——判据（`hovered`）与视觉效果都只作用在格子的最终形状上，
                            // `scaleEffect` / `shadow` / 底（不参与命中的 `.background` / `.overlay`）
                            // 都不改布局尺寸，邻居的位置仍由上面的 plan 定死。
                            .homeBlockFloat()
                    }

                    if row.showsHint {
                        HomeBandDroppedHint(count: plan.droppedCount, names: droppedNames)
                            .frame(maxHeight: row.height, alignment: .top)
                    }
                }
                .frame(height: row.height, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 被丢掉的块名（`＋N` 的悬停文案）：名单里没进任何一行 `indices` 的那些——
    /// 名单与 plan 同一份输入，所以提示列的块与真正没显示的块必然是同一批（D-03「名单同源」）。
    private var droppedNames: [String] {
        let visible = Set(plan.rows.flatMap(\.indices))
        return blocks.enumerated().filter { !visible.contains($0.offset) }.map(\.element.name)
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
    /// 高度模式与手动高度（p5-home-blocks / T6）：**观测源**——读到它们，尺寸层的重算才会与
    /// 「设置页拨了模式 / 拖了滑块」落到同一帧上（触发链见 `DynamicIslandApp` 里那五条 publisher）。
    @Default(.panelHeightMode) private var panelHeightMode
    @Default(.openNotchHeight) private var openNotchHeight
    let albumArtNamespace: Namespace.ID
    /// **面板表头高**（`max(24, vm.effectiveClosedNotchHeight)`，由 `NotchHomeView` 从 vm 算好传入）：
    /// 「面板高度 − 流可用高度」那份宿主开销里随屏变化的那一半（另一半是
    /// `PanelAutoHeight.homeVerticalPadding`，常量）。
    ///
    /// **必须与 `ContentView` 给表头钉的那个高同源**（`max(24, vm.effectiveClosedNotchHeight)`，
    /// 本值就是它的转发）：面板高 = 内容自然高 + 上下内边距，而画出来的那一份 plan 拿的是
    /// 「面板高 − 表头 − 内边距」——少算表头就会让可用高比内容矮一截，最后一行被流方案整行丢掉。
    /// 所以这个数只能由知道 vm 的那一层给，不能在 `PanelAutoHeight` 里写死。
    let panelHeaderHeight: CGFloat
    /// 光标是否停在面板里（边界 ①「不缩」的判据）：由 `NotchHomeView` 用宿主的既有 hover 判定
    /// （`vm.isMouseHovering()`）算好传入——本视图拿不到 vm，也不该自己再写一份几何。
    let pointerInsidePanel: Bool

    var body: some View {
        // 名单在本轮渲染里**只取一次**：块的 `content(for:request:)`（它同时决定「有没有块」——
        // 答 `.none` 的不生成格、不留空壳）与排序都在 `HomeBandCatalog.resolve` 里算完。
        let catalog = HomeBandCatalog.resolve(registry: registry, overrides: homeBlockOrder)
        let blocks = catalog.blocks

        GeometryReader { geometry in
            // **流的可用宽 = 整幅容器宽**（docs/32 D-23 起）：T8 的带级容器横向 8pt 已撤（容器自 p6 起
            // 就不画底了，这道内边距是它最后的遗留）——流的块因此与日历行左缘对齐，见 `HomeBandChrome`。
            let bandWidth = max(0, geometry.size.width)
            let items = blocks.map {
                HomeFlowLayout.Item(
                    min: $0.width.min,
                    ideal: $0.width.ideal,
                    height: HomeFlowView.blockHeight(for: $0.formFactor)
                )
            }
            // **画出来的那一份** plan 用的仍是当前可用高（今天那条，逐字未变）：面板多高就画多满，
            // 预算里装不下的行不画（`HomeFlowLayout` 的整行进出）。
            let plan = HomeFlowLayout.plan(
                items: items,
                availableWidth: bandWidth,
                availableHeight: geometry.size.height,
                calendarHeight: showCalendar ? HomeCalendarRow.rowHeight : 0,
                metrics: Self.flowMetrics
            )

            // —— 「面板贴内容」的高度账本（p5-home-blocks / T6，docs/29 §做法 机制六）——
            // 尺寸层要的是**内容自然高**：按「流允许的最大预算」另算一份（不是无界——上界函数给的
            // 就是有限数），流在这个预算下画满全部行与日历行。
            //
            // **为什么探针不按「当前面板高」算**（口径判断，见报告 §候选决策）：流方案在预算里装不下
            // 的行会**整行丢掉**（那是画的口径），拿它当内容高就是一条单向棘轮——面板越小 → 丢的行
            // 越多 → 算出来的内容高越小 → 面板再缩，越缩越少，最后停在「一行都不画」的不动点上；
            // 而块的高度是**声明值**（`HomeFlowView.blockHeight`），不随面板变，所以「内容自然高」
            // 本来就是与预算无关的一个数。收敛本身仍是双向的（见 `convergedPanelHeight`）：
            // 种子高于它 → 收缩、低于它 → 长高，唯一单向的规则只有「光标在面板内时不缩」。
            let hostChrome = panelHeaderHeight + PanelAutoHeight.homeVerticalPadding
            let naturalContentHeight = PanelAutoHeight.contentHeight(
                from: HomeFlowLayout.plan(
                    items: items,
                    availableWidth: bandWidth,
                    availableHeight: PanelAutoHeight.naturalFlowBudget(
                        hostChrome: hostChrome,
                        screenVisibleHeight: NSScreen.main?.visibleFrame.height
                    ),
                    calendarHeight: showCalendar ? HomeCalendarRow.rowHeight : 0,
                    metrics: Self.flowMetrics
                ),
                calendarHeight: HomeCalendarRow.rowHeight,
                calendarSpacing: HomeCalendarRow.rowSpacing,
                headerHeight: panelHeaderHeight
            )
            // 种子 = **权威的当前面板高**（`openNotchSize.height`，也就是尺寸层此刻生效的那个值），
            // 不在这里由 `geometry.size.height + 假设的宿主开销` 反推。
            //
            // 为什么必须取权威值（T6 评审 P1）：种子同时是 `heldForPointer` 的「当前值」——光标在
            // 面板里（悬浮展开时必然如此）且内容变矮时，它会把**种子**原样写回账本。种子只要与
            // 真实面板高差 Δ，写回的就是「真值 + Δ」，下一次重算又拿它当种子——**每个 resize 事件
            // 都把面板推高 Δ，直到撞上上界**。§已知限制 1 接受的只是「看起来偏大直到移开鼠标」，
            // 不是每次事件都长一点。`openNotchSize` 是唯一权威源（`calculateRequiredNotchSize`、
            // 打开面板那条、`ContentView.dynamicNotchSize` 都读它），读它不引入任何新状态。
            let seedPanelHeight = openNotchSize.height
            let convergedPanelHeight = PanelAutoHeight.convergedPanelHeight(
                seedPanelHeight: seedPanelHeight,
                mode: panelHeightMode,
                manualHeight: openNotchHeight,
                screenVisibleHeight: NSScreen.main?.visibleFrame.height,
                contentHeight: { _ in naturalContentHeight }
            )
            // 边界 ①（光标在面板里时不缩）在这里落地：收敛值比当前小、而光标还在面板里 → 保持当前。
            let heldPanelHeight = PanelAutoHeight.heldForPointer(
                converged: convergedPanelHeight,
                currentPanelHeight: seedPanelHeight,
                pointerInsidePanel: pointerInsidePanel
            )
            // 写账本（`PanelContentHeight.shared`，Kernel 层）：尺寸层（`openNotchSize`）读它。
            // **两种模式都写**——auto 下它决定面板高；manual 下尺寸层不读它，但写下来模式切换那一刻
            // 的值就是新鲜的（切模式的那条 publisher 会重算窗口，见 `DynamicIslandApp`）。
            // 账本的口径是「尺寸层再加 `homeVerticalPadding` 就得到面板高」，所以这里减掉它：
            // 收敛值与被光标按住时的现值因此都能被尺寸层逐字还原（`clamp(内容 + homeVerticalPadding)`）。
            // 首页那一份是**权威**（`setHomeContentHeight`）：量出来的值（其它 tab 的上报）碰不到它。
            // `let _ =`：`ViewBuilder` 不接受 Void 类型的表达式语句（`type '()' cannot conform to 'View'`），
            // 绑定给 `_` 是声明、不是语句，这条约束因此绕开（包的 `writeHomeContentHeight` 只是语法桥）。
            let _ = writeHomeContentHeight(heldPanelHeight - PanelAutoHeight.homeVerticalPadding)

            // 流 + 日历行自上而下；接缝间距与 `HomeCalendarRow.rowSpacing` 同值（取舍算的就是这个数）。
            // 流**不再包带级容器**（docs/32 D-23：那道横向 8pt 内边距已撤，两行的左缘因此都落在内容区左缘，
            // 与日历行一致）——分界由每块的浮起层做（黑档柔光池 + 辉光、玻璃档玻璃板，见
            // `homeBlockFloat()`）；日历行同样不包（它不是流的一部分）。
            VStack(spacing: HomeCalendarRow.rowSpacing) {
                if !plan.rows.isEmpty {
                    HomeFlowView(
                        blocks: blocks,
                        plan: plan,
                        albumArtNamespace: albumArtNamespace,
                        columnSpacing: Self.flowMetrics.columnSpacing
                    )
                    .frame(height: plan.heightUsed, alignment: .topLeading)
                }

                if showCalendar, plan.showsCalendarRow {
                    HomeCalendarRow()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// 流的度量（宿主常量的唯一装配点，传给 `HomeFlowLayout`）。
    private static var flowMetrics: HomeFlowLayout.Metrics {
        HomeFlowLayout.Metrics(
            columnSpacing: HomeStripLayout.spacing,
            rowSpacing: HomeStripView.widgetRowSpacing,
            tailReserve: HomeStripView.droppedHintWidth
        )
    }

    /// 把算出来的内容高写进高度账本（`PanelContentHeight.shared.setHomeContentHeight(_:)`）。
    ///
    /// 包一层函数是**语法上的必须**：写入点在 `GeometryReader` 的 `ViewBuilder` 里，那里放不下
    /// 一条裸赋值语句（`type '()' cannot conform to 'View'`）；调用一个返回 Void 的函数则是
    /// 合法的表达式语句。`@MainActor`：`View.body` 本就在主 actor 上（账本是主 actor 隔离的）。
    private func writeHomeContentHeight(_ height: CGFloat) {
        PanelContentHeight.shared.setHomeContentHeight(height)
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
