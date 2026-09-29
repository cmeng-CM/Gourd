//
//  HomeStripView.swift
//  Gourd 宿主 · 首页 strip 渲染器 + 块封装（P2 批次 / T3）
//
//  展开面板首页从「音乐 + 日历两栏写死」改成**一条横向 strip**：块由模块 manifest 的 `home`
//  投影（`ModuleRegistry.homeEntries`）与宿主内置块（音乐 / 日历 / 镜子）共同提供，宽度按声明
//  自适应、**富余时不拉伸**（D-02），放不下时按最小宽度收敛、仍不足则按 `order` 从尾部丢块
//  （D-03：不滚动、不分页、不加 `ScrollView`）。分配算术全在 `HomeStripLayoutMath`（纯函数、
//  已单测）；本文件只做「取宽度声明 → 交给纯函数 → 按结果摆放」，以及每个块里画什么。
//
//  规格：docs/17-nookx-adoption.md §做法 机制三（宽度 = 声明 + 收敛）、§接口与数据形状 6
//  （块宽声明与固定取值）、§改动点设计 1/2/3（接缝、渲染器、内置块）。
//
//  块的**存在性**用「是/否」而不是透明度：条件不满足的块根本不生成——否则它仍占宽度、
//  仍参与布局（本批裁决 1）。块的**名单**只有一个权威源：`homeEntries` 投影（机制二）。
//

import Defaults
import SwiftUI

// MARK: - 块宽声明

/// 一块的宽度约束：`min` 是「低于它不如不显示」的下界，`ideal` 是「富余时就用它」的期望值。
///
/// 取值在本批是**固定常量**（docs/17 §接口与数据形状 6）：音乐 `300 / 420`、日历 `200 / 260`、
/// 镜子 `140 / 160`、模块块（宿主统一声明）`180 / 240`。
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
struct HomeStripLayout: Layout {
    /// 块间距：单一常量（docs/17「做法」机制三）。T1 的用例与算式也共用这个数。
    static let spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let items = Self.items(of: subviews)
        // 无宽提案（`.unspecified`）时按「各块理想宽度之和」当可用宽度：命中规则 ①（富余），
        // 于是向上报的就是这条 strip 的自然宽度——`plan` 的前置条件要求有限数，不能传 `.infinity`。
        let available = proposal.width ?? Self.naturalWidth(of: items)
        let plan = HomeStripLayoutMath.plan(items: items, available: available, spacing: Self.spacing)
        // 间隙只存在于**可见**的块之间：规则 ③ 丢块后 n 是 `visibleCount`，不是 `subviews.count`。
        let gaps = Self.spacing * CGFloat(max(0, plan.visibleCount - 1))
        return CGSize(width: plan.widths.reduce(CGFloat.zero, +) + gaps, height: proposal.height ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // 与 `sizeThatFits` 同一条算式、同一份输入形状（宽度取 bounds 的）：`sizeThatFits` 报出的
        // 宽度就是各块分配宽度之和，因此这里重算得到的是同一组宽度。被规则 ③ 丢掉的尾部块
        // **不摆放**——`Layout` 允许不摆放所有 subview，被丢的块因此不显示、不占位。
        let plan = HomeStripLayoutMath.plan(
            items: Self.items(of: subviews),
            available: bounds.width,
            spacing: Self.spacing
        )
        var x = bounds.minX
        for (index, width) in plan.widths.enumerated() {
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.minY),
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + Self.spacing
        }
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
        .layoutValue(key: HomeBlockWidthKey.self, value: width)
    }
}

// MARK: - 首页 strip

/// 展开面板首页（标准路径）的那一条横向 strip。
///
/// 块顺序固定为「内置块：音乐 → 日历 → 镜子」+「模块块：`homeEntries` 顺序」；内置块由上游
/// `Defaults` 键门控（机制二：本批不把接管模块模块化），模块块由 manifest 的 `surfaces` 含
/// `home` + 用户开关共同决定（名单来自投影，用户没开就不会出现在投影里）。
struct HomeStripView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var registry = ModuleRegistry.shared
    @ObservedObject private var musicManager = MusicManager.shared
    @ObservedObject private var webcamManager = WebcamManager.shared
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.autoHideInactiveNotchMediaPlayer) private var autoHideInactiveNotchMediaPlayer
    @Default(.showCalendar) private var showCalendar
    @Default(.showMirror) private var showMirror
    let albumArtNamespace: Namespace.ID

    /// 内置三块的宽度声明（docs/17 §接口与数据形状 6 的取值，不得另取一套）。
    private static let musicBlockWidth = HomeBlockWidth(min: 300, ideal: 420)
    private static let calendarBlockWidth = HomeBlockWidth(min: 200, ideal: 260)
    private static let mirrorBlockWidth = HomeBlockWidth(min: 140, ideal: 160)

    /// 模块块的宽度由**宿主统一声明**（模块不参与「我在首页占多宽」的决策，D-11）：
    /// 声明值必须存在——模块块内容多为 `GeometryReader`，测量回退会把它们算成约 6pt。
    private static let moduleBlockWidth = HomeBlockWidth(min: 180, ideal: 240)

    /// 音乐块门控：逐字沿用 `NotchHomeView` 的旧判据（开启 + 非「无会话即隐藏」）。
    private var shouldShowMusicPlayer: Bool {
        showStandardMediaControls && (!autoHideInactiveNotchMediaPlayer || musicManager.hasActiveSession)
    }

    /// 镜子块门控：逐字沿用旧判据（开启 + 摄像头可用 + 面板已展开）。
    private var mirrorIsVisible: Bool {
        showMirror && webcamManager.cameraAvailable && vm.notchState == .open
    }

    var body: some View {
        // 模块块的内容在本轮渲染里**只取一次**：`content(for:request:)` 既决定「有没有块」
        // （答 `.none` 的不生成块，不留空壳），也决定块里画什么——取值后放在局部常量里，
        // 不在 `ForEach` 里二次请求（本批裁决 5）。
        let moduleBlocks = resolvedModuleBlocks()

        HomeStripLayout {
            if shouldShowMusicPlayer {
                HomeStripBlock(width: Self.musicBlockWidth) {
                    MusicPlayerView(albumArtNamespace: albumArtNamespace)
                }
            }

            if showCalendar {
                HomeStripBlock(width: Self.calendarBlockWidth) {
                    HomeStripCalendarBlock()
                }
            }

            if mirrorIsVisible {
                HomeStripBlock(width: Self.mirrorBlockWidth) {
                    CameraPreviewView(webcamManager: webcamManager)
                }
            }

            ForEach(moduleBlocks) { block in
                HomeStripBlock(width: Self.moduleBlockWidth) {
                    moduleBlockContent(block.content)
                }
            }
        }
        // 条本身**不铺满**：`HomeStripLayout` 报出的宽度就是「各块分配宽度 + 间隙」，
        // 这里只负责把条按左上角放在面板里（富余的宽度留在尾部，D-02；不居中、不对齐）。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: 模块块

    private struct ResolvedModuleBlock: Identifiable {
        let entry: ModuleHomeEntry
        let content: ModuleContent

        var id: String { entry.id }
    }

    /// 把 `homeEntries` 收成「本轮真的要画的块」：`content(for: .home)` 答 `.none` 的条目被过滤掉
    /// （投影是**声明**、内容是**表态**，两者分开才不会让一次 `.none` 影响后续刷新）。
    private func resolvedModuleBlocks() -> [ResolvedModuleBlock] {
        registry.homeEntries.compactMap { entry in
            let content = registry.content(for: entry.id, request: ModuleRegistry.home)
            if case .none = content { return nil }
            return ResolvedModuleBlock(entry: entry, content: content)
        }
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

// MARK: - 内置块：日历

/// 日历块：**一行日期头 + 今日竖向紧凑多行**（复用 `CalendarView` 收起态的两个部件）。
///
/// 为什么自建而不挂 `StandaloneCalendarView`：后者是「双栏月历 + 可滚动事件面板」（顶层
/// `GeometryReader` 宽度对半、高度取 `vm.notchSize`、右栏是滚动 `List`），塞进 200–260pt 的块里
/// 既横滚又撑高（docs/17 §改动点设计 3）。这里**不带** `WheelPicker` 日期选择轮——它是横向
/// 滚动控件，与「首页不横向滚动」的取向冲突；切日期与月历仍在独立日历 tab（已知限制 8）。
private struct HomeStripCalendarBlock: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.hideCompletedReminders) private var hideCompletedReminders
    @Default(.hideAllDayEvents) private var hideAllDayEvents

    /// 与 `CalendarView` 完全同一套过滤（已完成提醒 / 全天条目按偏好隐藏），
    /// 空态判据因此与首页日历栏一致。
    private var filteredEvents: [EventModel] {
        EventListView.filteredEvents(
            events: calendarManager.events,
            hideCompletedReminders: hideCompletedReminders,
            hideAllDayEvents: hideAllDayEvents
        )
    }

    /// 与 `CalendarView` 收起态逐字同形的一行日期头。
    private var headerText: String {
        let now = Date.now
        return now.formatted(.dateTime.weekday(.abbreviated))
            + ", " + now.formatted(.dateTime.month(.abbreviated))
            + " " + now.formatted(.dateTime.day())
    }

    var body: some View {
        // `GeometryReader` 取的是**放置后**的真实分配尺寸（不是测量值）：块拿到的是整条 strip
        // 的高度，减去日期头就是今日列表能用的高度。
        GeometryReader { geo in
            let listHeight = max(0, geo.size.height - HomeTodayListLayout.collapsedHeaderHeight)

            VStack(alignment: .leading, spacing: 0) {
                Text(headerText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.top, 2)
                    .frame(height: HomeTodayListLayout.collapsedHeaderHeight, alignment: .topLeading)

                if filteredEvents.isEmpty {
                    EmptyEventsView(selectedDate: Date.now)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                } else {
                    EventListView(
                        events: calendarManager.events,
                        selectedDate: Date.now,
                        availableHeight: listHeight
                    )
                    .padding(.top, 4)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        // 首次出现时确保日历数据是**今天**的：与 `CalendarView` / `StandaloneCalendarView` 的
        // `.onAppear` 同一条口径（块随面板展开而创建，因此每次展开都会对齐一次今天）。
        .onAppear {
            Task {
                await calendarManager.updateCurrentDate(Date.now)
            }
        }
        // 悬停遮罩（沿用旧 `NotchHomeView` 日历栏的 `onHover`）：`ContentView` 用它抑制
        // 「向下滚动收起面板」与横向切歌手势，避免用户在日历上操作时面板被误收起。
        .onHover { isHovering in
            vm.isHoveringCalendar = isHovering
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
