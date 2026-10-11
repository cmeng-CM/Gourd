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
//  FrontAppModule.swift
//  Gourd 模块 · 前台应用联动（p2-shortcuts-frontapp / T4）
//
//  docs/22-shortcuts-and-frontapp.md 的落点：manifest（§接口与数据形状 4）+ 首页块
//  （§做法 机制三/机制四）。事件源、历史与图标取值是 T3 的 `FrontAppStore` / `FrontAppHistory`，
//  本文件不重写它们——只做三件事：**声明**（manifest）、**接线**（activate / deactivate / content）、
//  **画块**（`FrontAppHomeBlockView`）。
//
//  **首页块的内容**（docs/23-home-fit.md §做法 机制三，2026-09-30 改）：上半仍是当前应用，
//  下半从"最近切换过的那几个"改成 **`store.switcherApps`（所有打开的常规 App）**——用户原话
//  「不是只有台前调度的内容，而是所有打开的软件都要显示」。画几格由**块内的排版预算**
//  `FrontAppGridBudget`（本文件末尾）定：宽决定一行几格、高决定几行；`recent` 从此只当排序依据，
//  它的上限 `recentLimit` 因此**不再决定块里画几格**（见口径 3 的新口径）。
//
//  五条刻意写死的口径（改动前先读）：
//
//  1. **只声明 `home`**（§接口与数据形状 4 / D-06）：折叠态左右槽位、展开 tab 与锁屏本批都不占——
//     `.compact` / `.expanded` / `.lockscreen` 一律答 `.none`（不占位、不算失败，06 §3.2）。
//     `defaultPlacement` 仍给 `Placement(slot: nil, order: 30)`：首页块的排序键复用
//     `placement.order`（§接口与数据形状 4 / docs/17 D-04），**它不蕴含 tab**——`expanded`
//     没声明，因此 `tabEntries` 里没有它（`order` 只对声明了 `expanded` 的模块是 tab 顺序）；
//  2. **默认关、零权限**（D-06 / docs/14 T-12）：`defaultEnabled = false`；`permissions = []`
//     ——`NSWorkspace` 通知与 `NSRunningApplication` 都是公开 API，没有新增权限面；
//  3. **夹取只有一处**（T3 口径 3）：模块把 config 的 `maxRecentApps` **原样**传给
//     `start(selfBundleID:maxRecentApps:)`，`FrontAppHistory.clampedLimit`（3…8）在 store 里夹一次。
//     **2026-09-30 起它管的是 `recent` 的长度**（= 排序依据的记忆条数），**不再决定块里画几格**
//     ——块里的格子数由 `FrontAppGridBudget` 按分配到的宽高算（"所有打开的软件都要显示"）。
//     视图因此不再需要 `recentLimit`，也不再夹、不再截；
//  4. **显式传 config 值**（T3 报告 §6 的建议形态）：`activate()` 自己读一次 `maxRecentApps` 传进去，
//     不依赖 store 内部那条「参数为 nil 时读 config」的兜底路径——读点与显示点因此可以对上
//     （缺键兜 `FrontAppHistory.defaultLimit`，与 manifest 默认值同源）；
//  5. **订阅在 `activate()` 起、`deactivate()` 摘**（T3 的 store 已幂等）：模块关掉后不再收前台
//     事件、不再画块；重开时 `start` 再种一次初值。
//
//  文案走 Localizable key（06 §3.3 R5）：`module.frontapp.*` 六个 key（name / summary 由 manifest
//  引用，current / switcher / recent / emptyRecent 是本视图的可访问性标签与悬停说明）；
//  **颜色**：面板是黑底、系统外观可为浅色——块内文字一律显式浅色（`Color.white` / `.white.opacity(…)`），
//  不用 `.primary` / `.secondary`（同 `ShortcutsModule` / `LauncherModule` 的教训）。
//

import AppKit
import SwiftUI

// MARK: - FrontAppModule

/// 前台应用模块（`docs/22` §接口与数据形状 4）：**只在首页 strip 里占一块**——
/// 上半是当前前台应用（图标 + 名称），下半是所有打开的常规 App（小图标，点一下切过去）。
@MainActor
final class FrontAppModule: GourdModule {
    /// 模块 id 的**唯一字面量**（manifest 与用例都读它，不各写一份）。
    static let moduleID = "com.cmeng.gourd.frontapp"

    /// 静态元数据（docs/22 §接口与数据形状 4 逐条对应）。
    ///
    /// - `surfaces: [.home]`：**只声明首页块**——本批不做折叠态侧槽（那条路依赖已降级的左右槽位，
    ///   §备选与取舍 ④），也不做展开 tab；
    /// - `defaultPlacement: Placement(slot: nil, order: 30)`：`slot` 只在含 `compact` 时有意义，
    ///   本模块不占槽位，故 `nil`；`order 30` 是首页块的位置（待办 20 与通知 40 之间）；
    /// - `defaultEnabled: false`：新增模块一律默认关（docs/14 T-12 / docs/22 D-06）；
    /// - `permissions: []`：`NSWorkspace` 的通知与 `NSRunningApplication` 都是公开 API（零权限）；
    /// - `config` 一键 `maxRecentApps`：默认值取 `FrontAppHistory.defaultLimit`（与夹取区间
    ///   `limitRange` 同在 T3 的纯函数里，不写第二个字面量）。
    static let manifest = ModuleManifest(
        manifestVersion: 1,
        id: moduleID,
        name: LocalizedText(key: "module.frontapp.name"),
        summary: LocalizedText(key: "module.frontapp.summary"),
        icon: IconSpec(type: "symbol", name: "app.badge"),
        version: "1.0.0",
        apiVersion: HostInfo.currentAPIVersion,
        kind: "builtin",
        surfaces: [.home],
        defaultPlacement: Placement(slot: nil, order: 30),
        defaultEnabled: false,
        permissions: [],
        config: ConfigSchema(
            type: "object",
            properties: [
                // 首页块里最多画几个最近应用（运行时夹取到 `FrontAppHistory.limitRange` 3…8）
                "maxRecentApps": ConfigNode(
                    type: "integer",
                    title: nil,
                    default: .int(FrontAppHistory.defaultLimit),
                    values: nil,
                    itemType: nil
                ),
            ]
        )
    )

    private let context: ModuleContext
    private let store: FrontAppStore

    /// 首页块**宽度申报**（p13 / docs/38-home-v5-layout.md D-04）：`300 / 434` + **弹性**。
    ///
    /// 它是环境带里唯一吃余量的块——用户 2026-10-11 的原话是「cpu 那三个宽度要降低，可以把第一排
    /// 大部分内容留给前台应用」。434 是 v5 设计稿在 887 面板下的那一档（音乐 260 + 434 + 系统 145
    /// + 两道 8 = 887 − 两侧内边距）；面板更宽时余量整份归它（`HomeStripLayoutMath` 规则 ①′）。
    static var homeBlockWidth: ModuleHomeBlockWidth? {
        ModuleHomeBlockWidth(min: FrontAppGridBudget.minimumBlockWidth, ideal: FrontAppGridBudget.idealBlockWidth)
    }

    /// 首页块**高度申报**（p13 / docs/38 D-02）：环境带档高（96）——三块等高，第一排才是一条带。
    static var homeBlockHeight: ModuleHomeBlockHeight { .points(HomeEnvironmentBand.height) }

    /// 首页块的**区**（docs/38 D-02）：前台应用是**环境带**第二块。
    static var homeZone: ModuleHomeZone { .environment }

    /// **吃余量**（docs/38 D-04）：环境带里唯一弹性的一块。宽一点 = 一行多放几格图标 = 少一轮
    /// 「装不下」，这正是「显示全部已打开的应用」那条硬需求的几何前提。
    static var homeBlockAbsorbsSurplus: Bool { true }

    /// 依赖注入在构造期完成（06 §3.3 R2）：store 只拿到 config 与 logger，**不订阅、不读前台**
    /// ——那些是 `activate()` 的副作用（口径 5）。
    init(context: ModuleContext) {
        self.context = context
        self.store = FrontAppStore(config: context.config, logger: context.logger)
    }

    // MARK: 生命周期

    /// 起订阅：读一次 config → `start` 种初值 + 订阅前台变化（口径 3/4/5）。
    ///
    /// 幂等由 store 保证（`start` 里 `guard activationToken == nil`）：重复激活不会挂两个观察者。
    func activate() async throws {
        let raw = context.config.get("maxRecentApps", as: Int.self) ?? FrontAppHistory.defaultLimit
        store.start(selfBundleID: Bundle.main.bundleIdentifier, maxRecentApps: raw)
        context.logger.info("frontapp 模块已激活（历史上限 \(store.recentLimit)，本应用 \(Bundle.main.bundleIdentifier ?? "无 bundleID")）")
    }

    /// 摘订阅（**幂等**，由 store 保证）：模块关掉后不再收前台事件、不再画块。
    ///
    /// 不清 `store.recent`：重开时 `start` 会把 `current` 换成当下的前台应用，而"刚才切过谁"
    /// 在关掉再打开之间仍然成立（T3 口径：不持久化，只活在本次运行的内存里）。
    func deactivate() async {
        store.deactivate()
    }

    // MARK: 内容

    /// 只答 `home`：首页块 = 当前应用 + 所有打开的常规 App。
    ///
    /// 三条 `.none` **不是**"暂时没实现"——是本批的契约（口径 1）：折叠槽位、展开 tab 与锁屏都不占。
    /// 视图只拿 store（口径 3 的新口径：画几格由 `FrontAppGridBudget` 按块宽高算，不经 config）。
    func content(for request: ContentRequest) -> ModuleContent {
        switch request.surface {
        case .home:
            return .view(AnyView(FrontAppHomeBlockView(store: store)))
        case .compact, .expanded, .lockscreen:
            return .none
        }
    }
}

// MARK: - 首页块视图

/// 首页块：**一整片图标网格**（p13 / docs/38-home-v5-layout.md D-09）。
///
/// 三件事各归各处，视图这一层只做呈现（没有过滤、没有排序、没有夹取、没有上限）：
/// - 状态（`current` / `switcherApps`）与图标都在 `FrontAppStore`（图标只走 `store.icon(for:)`——
///   接口里没有第二个来源）；
/// - 过滤与排序（`.regular` / 排除自身 / 无效条目；当前应用 → `recent` → 名称）是纯函数
///   `FrontAppSwitcher.apps(...)`（T3 的 `FrontAppStore.swift`），视图不重算也不重排；
/// - 画几格只看**块被分配到的宽高**（`FrontAppGridBudget`，本文件末尾）：宽决定一行几格、
///   高决定几行。
///
/// **形态改判（p13）**：改前是「上半当前应用（图标 28 + 名称）+ 下半其余 App 的网格」——
/// 用户 2026-10-11 的硬需求是「显示全部已打开的应用」，而那一行名字吃掉 34pt（≈一行图标）。
/// 改后**只有一片网格**：当前应用就是**第一格**（`switcherApps` 的排序保证它在最前），
/// 用一圈**选中环**标出来，名字走 `.help`（悬停可见）。
///
/// **装不下的那些**：行尾给一个 `…`（`hiddenCount` 走 `.help`），不静默丢——与 `＋N` 的诚实性口径同向。
///
/// **颜色**：面板黑底 + 系统外观可为浅色 → 一律显式浅色（`Color.white` / `.white.opacity(…)`）。
private struct FrontAppHomeBlockView: View {
    @ObservedObject var store: FrontAppStore
    /// 当前悬停的那一格（`nil` = 没悬停在任何一格上；按 **id** 记，见 `cell(_:)`）。
    @State private var hoveredID: String?

    var body: some View {
        GeometryReader { proxy in
            // 现取一次（`switcherApps` 每次都问一遍 `NSWorkspace.runningApplications`，实测 0.02ms）：
            // 一轮渲染只取一次。
            let apps = store.switcherApps
            grid(
                apps,
                // 排版预算扣掉**内容顶部内缩**（D-22）：图标上缘因此落在板顶下 7pt，
                // 行数按「真正拿到的高度」算，不会多算一行再被块壳裁掉。
                fitting: CGSize(
                    width: proxy.size.width,
                    height: proxy.size.height - HomeBlockChrome.contentInsetTopGraphics
                )
            )
                // **内容顶部内缩**（`HomeBlockChrome.contentInsetTopGraphics`，与图形起始的各块同档）。
                .padding(.top, HomeBlockChrome.contentInsetTopGraphics)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// 图标网格：列数按宽（上限 `maximumColumns`）、行数按高（上限 `maximumRows`），
    /// 装不下的尾部格子在行尾给一个 `…` 提示。
    private func grid(_ apps: [FrontAppSnapshot], fitting size: CGSize) -> some View {
        let columns = FrontAppGridBudget.cellsPerRow(forWidth: size.width)
        let capacity = FrontAppGridBudget.capacity(forWidth: size.width, forHeight: size.height)
        let items = Array(apps.prefix(capacity))
        let hiddenCount = apps.count - items.count
        let currentID = store.current?.id

        return Group {
            if columns > 0, !items.isEmpty {
                VStack(alignment: .leading, spacing: FrontAppGridBudget.rowSpacing) {
                    // 每 `columns` 个一格 `HStack`（用起点做 `ForEach` 的 id：行数随 App 数变化，行本身没有身份）
                    ForEach(Array(stride(from: 0, to: items.count, by: columns)), id: \.self) { start in
                        HStack(spacing: FrontAppGridBudget.cellSpacing) {
                            ForEach(items[start ..< min(start + columns, items.count)]) { snapshot in
                                cell(snapshot, isCurrent: snapshot.id == currentID)
                            }
                            // 最后一行还有装不下的：行尾一个 `…`（预告「还有 N 个没画」；点不开，
                            // 与 `＋N` 同一条诚实性口径——提示存在，但没有第二套交互面板）。
                            if hiddenCount > 0, start + columns >= items.count {
                                Text(verbatim: "…")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.45))
                                    .frame(width: FrontAppGridBudget.cellSize, height: FrontAppGridBudget.cellSize)
                                    .help(Text(verbatim: "+\(hiddenCount)"))
                                    .accessibilityLabel(Text(verbatim: "+\(hiddenCount)"))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text(LocalizedStringKey("module.frontapp.switcher")))
            }
        }
    }

    /// 一格（图标 + 内边距）：悬停底色 + 整格可点；**当前应用那一格多加一圈选中环**。
    ///
    /// 悬停态按 **id** 记（不是 `Bool`）：一排格子共用一个视图状态，`Bool` 会让悬停一个时整排都亮。
    ///
    /// **底色走首页那条唯一的 hover 规则**（T8 / docs/26 §做法 机制七，`homeBlockHoverBackground`）：
    /// 本格原先自己写的是 `cornerRadius: 5` + `opacity 0.18`，与通知 / 待办两处各写一套——
    /// 三处现已收敛成 `HomeBandChrome` 里那一组常量（r8 / 0.06）。`contentShape` 用同一条规则的
    /// 圆角，热区与亮起的形状因此是同一个。
    ///
    /// 点击 = `store.activate(snapshot)`（切到那个应用）。当前应用那一格**照样可点**——
    /// 它已经是前台，点它不是危险操作，为它单开一条「点了没反应」的分支只会多一处要解释的行为。
    private func cell(_ snapshot: FrontAppSnapshot, isCurrent: Bool) -> some View {
        appIcon(snapshot, size: FrontAppGridBudget.cellIconSize)
            .padding(FrontAppGridBudget.cellPadding)
            .overlay {
                // 选中环：当前应用。**只在有当前应用时画**（取不到前台应用时没有「谁在前台」）。
                if isCurrent {
                    RoundedRectangle(cornerRadius: HomeBandChrome.hoverCornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.85), lineWidth: FrontAppGridBudget.currentRingLineWidth)
                }
            }
            .homeBlockHoverBackground(isHovered: hoveredID == snapshot.id)
            // 整格（图标 + 内边距）都能点到，而不是只有图形的非透明像素。
            .contentShape(RoundedRectangle(cornerRadius: HomeBandChrome.hoverCornerRadius))
            .onHover { hoveredID = $0 ? snapshot.id : (hoveredID == snapshot.id ? nil : hoveredID) }
            .onTapGesture { store.activate(snapshot) }
            .help(snapshot.name)   // 只有图标时，悬停给应用名（同 `ShortcutsRow` 的 `.help` 口径）
            .accessibilityLabel(Text(snapshot.name))
    }

    // MARK: 图标

    /// 应用图标：**只走 `store.icon(for:)`**（§接口与数据形状 3 的唯一图标来源）；取不到时画占位，
    /// 而不是留一块空白（无 bundleURL 的进程、已退出的进程都会回到这里）。
    @ViewBuilder
    private func appIcon(_ snapshot: FrontAppSnapshot, size: CGFloat) -> some View {
        if let image = store.icon(for: snapshot) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(.white.opacity(0.15))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "app.dashed")
                        .font(.system(size: size * 0.5))
                        .foregroundStyle(.white.opacity(0.5))
                )
        }
    }
}

// MARK: - 排版预算

/// 前台应用块的**排版预算**（纯函数 + 唯一一组常量）。
///
/// **p13 起是「宽决定列、高决定行」的自适应网格**（docs/38-home-v5-layout.md D-09）：块在环境带里
/// 是**弹性**的那一块（宽随面板走），因此列数必须跟着宽变——固定列数会让宽出来的那一段白留。
///
/// 沿革：固定 4 列 × 4 行（docs/37 D-02，为「不受邻居影响」把几何钉死）→ 本批放宽为
/// 「列按宽（上限 16）、行按高（上限 4）」。**「不受邻居影响」这条目标是靠块高申报拿到的**
/// （`homeBlockHeight` 让行高只由本块决定），列数跟着块**自己**的宽变不违背它——变的只是宽，
/// 而宽正是用户希望它吃满的那一维。
///
/// 常量：一格 = 图标 24 + 内边距 2（悬停底 / 选中环都画在这一格里）= 28；格间距 0
/// （相邻图标之间的可见缝 = 两侧各 2pt 内边距 = 4）；行间距 4。
enum FrontAppGridBudget {
    /// 一格的图标边长。
    static let cellIconSize: CGFloat = 24
    /// 一格的悬停底色内边距（四周各 2）——选中环也画在这一圈里。
    static let cellPadding: CGFloat = 2
    /// 格与格之间的水平间距（0：可见缝由内边距给出，见类型注释）。
    static let cellSpacing: CGFloat = 0
    /// 行间距。
    static let rowSpacing: CGFloat = 4
    /// 当前应用那一格的选中环线宽。
    static let currentRingLineWidth: CGFloat = 1.5

    /// 一行的**列数上限**（docs/38 §已知限制 4）：再宽也不加列——一行 16 格以上的图标墙不好点。
    static let maximumColumns = 16
    /// 网格的**行数上限**。
    static let maximumRows = 4

    /// 块宽的下界（`FrontAppModule.homeBlockWidth.min`）：环境带三块最小宽之和 + 两道缝
    /// 必须装得进面板的最小可用宽；300 也是「一行放得下 10 格」的那一档。
    static let minimumBlockWidth: CGFloat = 300
    /// 块宽的理想值（v5 设计稿在 887 面板下的那一档，见 `homeBlockWidth` 的注释）。
    static let idealBlockWidth: CGFloat = 434

    /// 一格的边长（图标 + 四周内边距）。
    static var cellSize: CGFloat { cellIconSize + cellPadding * 2 }

    /// 一行最多放几格：`floor((宽 + 格距) / (格 + 格距))`，钳 `0…maximumColumns`。
    ///
    /// 宽取不到（首帧 0 / NaN）→ 0（一格都不画，下一帧就有真值）。
    static func cellsPerRow(forWidth width: CGFloat) -> Int {
        guard width.isFinite, width >= cellSize else { return 0 }
        let fits = Int(((width + cellSpacing) / (cellSize + cellSpacing)).rounded(.down))
        return min(max(fits, 0), maximumColumns)
    }

    /// 该高度下能画几行：`floor((高 + 行距) / (格 + 行距))`，钳 `0…maximumRows`。
    ///
    /// **调用方已扣掉内容顶部内缩**（视图那一层减的，与待办块同一条口径：按真正拿到的高算行数），
    /// 因此这里只做除法。
    static func rowCount(forHeight height: CGFloat) -> Int {
        guard height.isFinite else { return 0 }
        let fit = Int(((height + rowSpacing) / (cellSize + rowSpacing)).rounded(.down))
        return min(max(fit, 0), maximumRows)
    }

    /// 网格一共能放几格。
    static func capacity(forWidth width: CGFloat, forHeight height: CGFloat) -> Int {
        cellsPerRow(forWidth: width) * rowCount(forHeight: height)
    }
}
