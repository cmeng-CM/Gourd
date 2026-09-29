//
//  HomeStripView.swift
//  Gourd 宿主 · 首页 strip 渲染器 + 块封装（P2 批次 / T3）
//
//  展开面板首页从「音乐 + 日历两栏写死」改成**一条横向 strip**：块由模块 manifest 的 `home`
//  投影（`ModuleRegistry.homeEntries`）与宿主内置块（今天的唯一一个是音乐）共同提供，宽度按声明
//  自适应、**富余时不拉伸**（D-02），放不下时按最小宽度收敛、仍不足则按 `order` 从尾部丢块
//  （D-03：不滚动、不分页、不加 `ScrollView`）。分配算术全在 `HomeStripLayoutMath`（纯函数、
//  已单测）；本文件只做「取宽度声明 → 交给纯函数 → 按结果摆放」，以及每个块里画什么。
//
//  P2 接管批次 / T4 增量：**镜子块搬到了模块侧**（`DynamicIsland/Modules/Takeover/MirrorModule.swift`）
//  ——本文件里那条写死的分支（内联可见性判据 + `case .mirror` 载荷 + 块宽常量 +
//  `@Default(.showMirror)`）同批删除，镜子块今天由 `homeEntries` 投影产出（一对一替换，不并存）；
//  模块块的宽度因此改问 `registry.homeBlockWidth(for:)`（接管模块继承被接管块的宽度，D-10）。
//  音乐块的接管是 T5 的事，它今天仍是内置块。
//
//  规格：docs/17-nookx-adoption.md §做法 机制三（宽度 = 声明 + 收敛）、§接口与数据形状 6
//  （块宽声明与固定取值）、§改动点设计 1/2/3（接缝、渲染器、内置块）；
//  docs/20-component-page.md §做法 机制一（渲染点归属 / 块宽继承）。
//
//  块的**存在性**用「是/否」而不是透明度：条件不满足的块根本不生成——否则它仍占宽度、
//  仍参与布局（本批裁决 1）。块的**名单**只有一个权威源：`homeEntries` 投影（机制二）。
//

import Defaults
import SwiftUI

// MARK: - 块宽声明

/// 一块的宽度约束：`min` 是「低于它不如不显示」的下界，`ideal` 是「富余时就用它」的期望值。
///
/// 取值来源有两处（docs/17 §接口与数据形状 6 + docs/20 §做法 机制一「块宽继承」）：
/// 音乐 `300 / 420` 仍是宿主内置块的常量，**镜子 `140 / 160` 已搬到模块侧**
/// （`MirrorModule.homeBlockWidth`，宿主经 `ModuleRegistry.homeBlockWidth(for:)` 取回），
/// 模块块（宿主统一声明）`180 / 240`。
struct HomeBlockWidth: Equatable {
    let min: CGFloat
    let ideal: CGFloat
}

/// 块把自己的宽度约束递给 `HomeStripLayout` 的通道。
///
/// **含 `GeometryReader` 的视图在 `.unspecified` 测量下只报约 10pt**，靠测量会算出约 6pt 的块
/// （docs/17「机制三」）——所以本批**所有**块都显式声明本键，测量只作取不到声明时的回退。
struct HomeBlockWidthKey: LayoutValueKey {
    static let defaultValue: HomeBlockWidth? = nil
}

// MARK: - 布局

/// 首页 strip 的 `Layout`：把宽度分配结果摆成一行。
///
/// 高度**不协商**（沿用 docs/13 的既有裁定）：块拿到的是整条 strip 的高度，自己决定内部怎么排；
/// 因此 `sizeThatFits` 原样接受提案高度，横向的分配才是本布局唯一做的事。
///
/// **一次布局只算一次 `plan`**：`sizeThatFits` 把结果连同输入（`items` / `available`）写进 cache，
/// `placeSubviews` 读它、**不重算**。两边各算一次的失败案例是规则 ②——`sizeThatFits` 的输入是
/// `proposal.width`，而 `placeSubviews` 能看到的 `bounds.width` 是上一份 plan 的**已压缩输出**，
/// 规则 ② 不幂等（实测 available 684 → 上报 `[414.5, 257.0]`；用 683.5 重算得 `[414.0, 257.0]`），
/// 于是「摆放用的宽度」与「上报的宽度」不是同一组数。所以这里用 `Layout` 的 cache 传递结果，
/// 而不是靠「同一算式重算一遍」这种假设。
struct HomeStripLayout: Layout {
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
    /// 即可用宽 ≥ 884 → 面板 ≈ 952pt 起）。
    static let spacing: CGFloat = 8

    /// 一次布局的输入形状与算出的结果。
    struct Cache {
        /// 各块的宽度约束（声明优先、测量回退）。子视图变化时由 `updateCache` 重新取一次。
        var items: [HomeStripLayoutMath.Item] = []
        /// 下面这份 `plan` 是拿哪个可用宽度算出来的（`plan == nil` 时无意义）。
        var available: CGFloat = .nan
        /// nil = 还没有任何人为当前的输入算过。
        var plan: HomeStripLayoutMath.Plan?
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(items: Self.items(of: subviews))
    }

    /// 子视图变了（块被加上 / 去掉、宽度声明变了）→ 重新取声明，并把宽度分配结果作废，
    /// 由下一次 `sizeThatFits` 按新的输入重算。测量只在这里（和 `makeCache`）发生。
    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.items = Self.items(of: subviews)
        cache.available = .nan
        cache.plan = nil
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        // 无宽提案（`.unspecified`）时按「各块理想宽度之和」当可用宽度：命中规则 ①（富余），
        // 于是向上报的就是这条 strip 的自然宽度——`plan` 的前置条件要求有限数，不能传 `.infinity`。
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
                // 而是把被丢掉的块铺满整条 strip 叠在已摆放块之上；默认 `openNotchWidth = 640`
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

    /// 取本次布局的 `plan`：输入形状（`available`）与 cache 里记的一致就直接复用，
    /// 否则按 cache 里的声明算一次并写回。`items` 的失效由 `updateCache` 负责。
    private func resolvedPlan(available: CGFloat, cache: inout Cache) -> HomeStripLayoutMath.Plan {
        if let plan = cache.plan, cache.available == available {
            return plan
        }
        let plan = HomeStripLayoutMath.plan(items: cache.items, available: available, spacing: Self.spacing)
        cache.available = available
        cache.plan = plan
        return plan
    }

    /// 每个 subview 的宽度约束：声明优先，取不到才回退到测量（`ideal` = 测得的宽度，
    /// `min = ideal × 0.6`——设计文档给未声明块的回退口径）。
    private static func items(of subviews: Subviews) -> [HomeStripLayoutMath.Item] {
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

/// 一个 strip 块的壳：声明自己的宽度约束，并把自己在**分配到的**宽高里顶部对齐。
///
/// 内置块与模块块**同构**地套这一层：两者的差别只在「宽度声明是谁给的」与「里面画什么」，
/// 摆放机制只有一套（docs/17 §改动点设计 2）。
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
        // 横向铺满**分配到的**宽度（不超过声明宽度），纵向拿满 strip 高度并从顶部开始画：
        // 面板里不再用会把内容摊开的纵向 `Spacer`，留白自然留在块的下方。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // **块的外框必须裁剪**（2026-09-29 实测发现，修复轮 1）：被规则 ③ 丢掉的块拿 `.zero` 提案，
        // 但外框不裁剪时固定尺寸的内容（三环 / 图标 / 占位三角）仍按**固有尺寸**溢出绘制——
        // 770pt 面板下「待办块明明被丢了，屏上却出现三环、只是没有清单」就是这条溢出残影
        // （docs/17 §已知限制 19 原记为「当前配置不触发」，本次证伪）。
        // 放在 `.frame(...)` **之后**：裁的是这个块分配到的边界，块内画在边界里的内容不受影响；
        // 在 `.layoutValue` 之前，宽度声明的传递路径因此逐字不变。
        .clipped()
        .layoutValue(key: HomeBlockWidthKey.self, value: width)
    }
}

// MARK: - 首页 strip

/// 展开面板首页（标准路径）的那一条横向 strip。
///
/// 块顺序 = **内置块与模块块合成一张名单**，再按 `HomeBlockOrdering` 排序（覆盖值优先 → 缺键回落
/// 默认序号 → 同值按 id 字典序，P1 / T3；覆盖表先过历史键映射，P2 / T4）；默认序号下音乐块（0）
/// 在前、镜子模块块（2）在后，模块块按 `homeEntries` 顺序排——**未调过顺序的用户看到的就是
/// 改动前的那条 strip**（镜子块的默认序号与被它取代的内置块同为 2）。
/// 内置的音乐块由上游 `Defaults` 键门控，模块块由 manifest 的 `surfaces` 含 `home` + 用户开关
/// （接管模块就是那个上游开关）共同决定：名单来自投影，用户没开就不会出现在投影里。
///
/// **丢块规则不变**（D-03）：宽度不够时仍按**排好序的**尾部丢——顺序改了，丢的对象随之改，
/// 这是排序生效的正常结果（docs/18 §改动点设计 4 的陷阱栏）。
///
/// **日历不在 strip 里**（2026-09-29 起）：整月网格需要宽度，塞进块里格子只有约 26pt——首页的日历
/// 改由 strip 下面那条**全宽日历行**（`HomeCalendarRow`）承担。因此本视图不再生成日历块
/// （哪些块在条里，`showCalendar` 不再参与）；`builtin.calendar` 这个 id 只在
/// `HomeBlockOrdering.BuiltinBlock` 里保留语义，见那里的注释。
///
/// **镜子不在本文件里**（P2 接管批次 / T4 起）：它已是一块模块块（`MirrorModule`），
/// 条里的内置块只剩音乐（`builtin.music` 这个 id 也只剩历史含义，T5 会一并接管）。
struct HomeStripView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var registry = ModuleRegistry.shared
    @ObservedObject private var musicManager = MusicManager.shared
    /// **保留观察摄像头可用性**（P2 接管批次 / T4 起，`webcamManager` 已不再被本视图直接读）：
    /// 镜子块今天是模块块（`MirrorModule`），它的**存在性**由 `content(for: .home)` 答不答 `.none`
    /// 决定，而那条判据里有一段是 `WebcamManager.shared.cameraAvailable`——摄像头插上 / 拔掉时
    /// 除了这个观察者没人会叫醒本视图，块就既不会出现也不会消失（顺序表随之不重排）。
    /// 拨开关那条路径由 `@Default(.homeBlockOrder)` / 注册表驱动，与这里无关。
    @ObservedObject private var webcamManager = WebcamManager.shared
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.autoHideInactiveNotchMediaPlayer) private var autoHideInactiveNotchMediaPlayer
    /// 用户排序覆盖（P1 / T3）：`@Default` 是 `DynamicProperty`——设置页写盘后**这里立即重绘**，
    /// 不需要注册表发通知（顺序与 `moduleEnableOverrides` 的开关路径同形：偏好一个源）。
    @Default(.homeBlockOrder) private var homeBlockOrder
    let albumArtNamespace: Namespace.ID

    /// 内置音乐块的宽度声明（docs/17 §接口与数据形状 6 的取值，不得另取一套）。
    /// 镜子块的那一档（140/160）随接管搬到模块侧，见 `blockWidth(for:)`。
    private static let musicBlockWidth = HomeBlockWidth(min: 300, ideal: 420)

    /// 模块块的**缺省**宽度由宿主统一声明（模块不参与「我在首页占多宽」的决策，D-11）：
    /// 声明值必须存在——模块块内容多为 `GeometryReader`，测量回退会把它们算成约 6pt。
    /// **接管模块例外**：它接住的是被接管块原本的宽度（D-10），走 `blockWidth(for:)` 取模块的声明。
    private static let moduleBlockWidth = HomeBlockWidth(min: 180, ideal: 240)

    /// strip 的**最小可用高度**：低于它就不生成这条 strip（判据在接缝
    /// `NotchHomeView.standardHomeContent`）——**判据是「画不满就不画」**（2026-09-29 复审裁决）：
    /// 高度不足以**完整渲染**条内的块时，整条不画，而不是画一条被切一半的封面。
    ///
    /// **数值来源（同一批实测截图，见 `.workflow/p2-calendar-row/reports/` 的 §6.5）**：音乐块（当前
    /// 唯一的内置块）从上到下需要 `18`（块内顶部偏移，封面起点）+ `133`（封面边长，受块宽 420 下的
    /// 宽度份额约束）≈ **151.5pt**，留半 pt 取整 = **152**：
    /// - 面板 544 → strip 174：封面下沿 + 角标 + 控制三键全在，完整 ✓（留 ~22pt 余量）；
    /// - 面板 522 → strip 152：按此阈值刚好画满；
    /// - 面板 504 → strip 134：封面下沿被切、角标只剩半个（`strip-hidden-panel460.png` 之前的
    ///   `strip-clipped-panel460.png` 是同一现象的更矮一档）→ 因此 134 **不够**，阈值取 152。
    ///
    /// 低于阈值即整条不画（面板只剩日历行、干净）；模块块比音乐块矮，本阈值对它们偏保守——宁可
    /// 少画一条，不画残片。
    static let minimumUsableHeight: CGFloat = 152

    /// 音乐块门控：逐字沿用 `NotchHomeView` 的旧判据（开启 + 非「无会话即隐藏」）。
    private var shouldShowMusicPlayer: Bool {
        showStandardMediaControls && (!autoHideInactiveNotchMediaPlayer || musicManager.hasActiveSession)
    }

    /// 模块块的宽度：**接管模块继承被接管块的宽度**（D-10 / docs/20 §做法 机制一「块宽继承」），
    /// 非接管模块用宿主统一值——内核的 `ModuleHomeBlockWidth` 与渲染层的 `HomeBlockWidth`
    /// **同形不同名**，映射就在这一处（内核不认识渲染层类型）。
    private func blockWidth(for id: String) -> HomeBlockWidth {
        guard let declared = registry.homeBlockWidth(for: id) else { return Self.moduleBlockWidth }
        return HomeBlockWidth(min: declared.min, ideal: declared.ideal)
    }

    var body: some View {
        // 名单在本轮渲染里**只取一次**：内置块的开关判据、模块块的 `content(for:request:)`（它同时
        // 决定「有没有块」——答 `.none` 的不生成块、不留空壳）与排序都在 `resolvedHomeBlocks()`
        // 里算完；`ForEach` 只按结果摆放，不二次请求（本批裁决 5）。
        let blocks = resolvedHomeBlocks()

        HomeStripLayout {
            ForEach(blocks) { block in
                switch block.payload {
                case .music:
                    HomeStripBlock(width: Self.musicBlockWidth) {
                        MusicPlayerView(albumArtNamespace: albumArtNamespace)
                    }
                case .module(let moduleID, let content):
                    HomeStripBlock(width: blockWidth(for: moduleID)) {
                        moduleBlockContent(content)
                    }
                }
            }
        }
        // 条本身**不铺满**：`HomeStripLayout` 报出的宽度就是「各块分配宽度 + 间隙」，
        // 这里只负责把条按左上角放在面板里（富余的宽度留在尾部，D-02；不居中、不对齐）。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: 块名单

    /// 名单里的一项：内置块或模块块，**同构**地放在一张表里（docs/18 §改动点设计 4）。
    private struct HomeBlock: Identifiable {
        /// 覆盖表的键：内置块 = `HomeBlockOrdering.BuiltinBlock.id`，模块块 = 模块 id。
        /// **模块 id 在 `payload` 里再带一份**：摆放时要按它查 `homeBlockWidth` 钩子（D-10）。
        let id: String
        /// 缺键时的默认序号（内置块 = `BuiltinBlock.defaultOrder`，模块块 = `entry.order`）。
        let defaultOrder: Int
        let payload: Payload

        enum Payload {
            case music
            /// 模块块：`id` 是模块 id（= 上面那个 `id`，一并带上是为了让宽度查得到钩子）。
            case module(id: String, content: ModuleContent)
        }
    }

    /// 把内置块与模块块**合成一张名单**，交给 `HomeBlockOrdering` 排序后返回本轮真的要画的块。
    ///
    /// 内置块的生成判据是**开关 + 运行期条件**（音乐要有会话），与改动前逐字同序；模块块仍是
    /// 「`homeEntries` 里 `content(for: .home)` 不答 `.none`」的那几条（投影是**声明**、内容是
    /// **表态**，两者分开才不会让一次 `.none` 影响后续刷新）——**镜子块走的就是这条路**
    /// （P2 接管批次 / T4 起，`MirrorModule` 的判据里含摄像头可用性）。
    ///
    /// 顺序的**唯一权威源**是这一层（覆盖值 + 默认序号，后者先过历史键映射），设置页展示用的是
    /// 同一条算式。
    private func resolvedHomeBlocks() -> [HomeBlock] {
        var blocks: [HomeBlock] = []

        if shouldShowMusicPlayer {
            blocks.append(
                HomeBlock(
                    id: HomeBlockOrdering.BuiltinBlock.music.id,
                    defaultOrder: HomeBlockOrdering.BuiltinBlock.music.defaultOrder,
                    payload: .music
                )
            )
        }

        for entry in registry.homeEntries {
            let content = registry.content(for: entry.id, request: ModuleRegistry.home)
            if case .none = content { continue }
            blocks.append(
                HomeBlock(
                    id: entry.id,
                    defaultOrder: entry.order,
                    payload: .module(id: entry.id, content: content)
                )
            )
        }

        return HomeBlockOrdering.sorted(
            blocks,
            defaultOrder: { $0.defaultOrder },
            id: { $0.id },
            overrides: homeBlockOrder
        )
    }

    /// 四个分支逐条对应 06 §3.2（与 `ModuleHostView` 同口径）：`.view` 渲染模块给的视图；
    /// `.descriptor` 本批不渲染（占位说明）；`.unavailable` 显示降级文案（**不算失败**）；
    /// `.none` 不占位（生成块前已过滤，这里只为 switch 穷尽）。
    @ViewBuilder
    private func moduleBlockContent(_ content: ModuleContent) -> some View {
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
