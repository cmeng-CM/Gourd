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

/// 首页块：**上半当前应用（图标 28 + 名称单行）、下半所有打开的常规 App（小图标 20，点一下切过去）**。
///
/// 三件事各归各处，视图这一层只做呈现（没有过滤、没有排序、没有夹取、没有上限）：
/// - 状态（`current` / `switcherApps`）与图标都在 `FrontAppStore`（图标只走 `store.icon(for:)`——
///   接口里没有第二个来源）；
/// - 过滤与排序（`.regular` / 排除自身 / 无效条目；当前应用 → `recent` → 名称）是纯函数
///   `FrontAppSwitcher.apps(...)`（T3 的 `FrontAppStore.swift`），视图不重算也不重排；
/// - 画几格只看**块被分配到的宽高**（`FrontAppGridBudget`，本文件末尾）：宽决定一行几格、
///   高决定几行，两者都不越界（"格子被裁 / 挤变形"正是本次要修的那类观感的对立面）。
///
/// **网格里画的是"除当前应用外"的其余 App**：当前应用在上半已经有一行，网格里不再重复一格。
/// `current` 为 nil（取不到前台应用）时上半画一行浅色 `—`、网格仍照画全部——这时"谁是当前应用"
/// 本来就不成立，画不出来的是那一行，不是这一块的内容。
///
/// **装不下的那些不画**：块就 180pt 宽 / 152pt 高那么点地方（最小档 = 4 行 × 6 格 = 24 格），
/// 溢出的格子静默不画；本批不做溢出提示（§明确不做「`＋N` 的观感」/ 已知限制见报告）。
///
/// **颜色**：面板黑底 + 系统外观可为浅色 → 一律显式浅色（`Color.white` / `.white.opacity(…)`）。
private struct FrontAppHomeBlockView: View {
    @ObservedObject var store: FrontAppStore
    /// 当前悬停的那一格（`nil` = 没悬停在任何一格上；按 **id** 记，见 `cell(_:)`）。
    @State private var hoveredID: String?

    var body: some View {
        GeometryReader { proxy in
            // 现取一次（`switcherApps` 每次都问一遍 `NSWorkspace.runningApplications`，实测 0.02ms）：
            // 一轮渲染只取一次，上半行与网格共用这一份。
            let apps = store.switcherApps
            VStack(alignment: .leading, spacing: FrontAppGridBudget.rowSpacing) {
                currentRow
                grid(apps, fitting: proxy.size)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: 上半：当前应用

    /// 当前应用一行：图标 28 + 名称单行（`white`）；
    /// 拿不到前台应用时退化成一行浅色 `—`（空态，不是错误）。
    @ViewBuilder
    private var currentRow: some View {
        if let current = store.current {
            HStack(spacing: 8) {
                appIcon(current, size: FrontAppGridBudget.currentIconSize)

                Text(current.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 可访问性标签把"这一行是什么"说全（图标 + 名称对读屏只是名字）——文案走 key。
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(LocalizedStringKey("module.frontapp.current")) + Text(" ") + Text(current.name))
        } else {
            Text(verbatim: "—")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(Text(LocalizedStringKey("module.frontapp.emptyRecent")))
                .accessibilityLabel(Text(LocalizedStringKey("module.frontapp.emptyRecent")))
        }
    }

    // MARK: 下半：所有打开的常规 App（网格）

    /// 其余打开的 App：**一行放几个由块宽定，放几行由块高定**（`FrontAppGridBudget`），
    /// 两者算完还有剩的格子才不画——预算之内一个不落，预算之外一个不画。
    ///
    /// 一格是按钮：**点一下 = `store.activate(snapshot)`**（切到那个应用；失败的两条路径都进日志，
    /// 见 `FrontAppStore.activate(_:)`）。悬停给底色（图标本身只有 20pt，没有底色看不出哪一格是热区）。
    @ViewBuilder
    private func grid(_ apps: [FrontAppSnapshot], fitting size: CGSize) -> some View {
        let columns = FrontAppGridBudget.cellsPerRow(forWidth: size.width)
        let items = Array(otherApps(apps).prefix(FrontAppGridBudget.capacity(forWidth: size.width, forHeight: size.height)))
        if columns > 0, !items.isEmpty {
            VStack(alignment: .leading, spacing: FrontAppGridBudget.rowSpacing) {
                // 每 `columns` 个一格 `HStack`（用起点做 `ForEach` 的 id：行数随块高变化，行本身没有身份）
                ForEach(Array(stride(from: 0, to: items.count, by: columns)), id: \.self) { start in
                    HStack(spacing: FrontAppGridBudget.cellSpacing) {
                        ForEach(items[start ..< min(start + columns, items.count)]) { snapshot in
                            cell(snapshot)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(LocalizedStringKey("module.frontapp.switcher")))
        }
    }

    /// 网格里的内容 = `switcherApps` 去掉当前应用（上半那一行已经有它了）。
    ///
    /// 判据是 **`id`**（`bundleID ?? "pid:\(pid)"`）：同一个应用在被切换时 pid 会变、bundleID 不变，
    /// 按 id 比对才认得出是同一个；`current` 为 nil 时没有要去掉的对象，原样返回。
    private func otherApps(_ apps: [FrontAppSnapshot]) -> [FrontAppSnapshot] {
        guard let currentID = store.current?.id else { return apps }
        return apps.filter { $0.id != currentID }
    }

    /// 一格（20pt 图标 + 2pt 内边距）：悬停底色 + 整格可点。
    ///
    /// 悬停态按 **id** 记（不是 `Bool`）：一排格子共用一个视图状态，`Bool` 会让悬停一个时整排都亮。
    private func cell(_ snapshot: FrontAppSnapshot) -> some View {
        appIcon(snapshot, size: FrontAppGridBudget.cellIconSize)
            .padding(FrontAppGridBudget.cellPadding)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(.white.opacity(hoveredID == snapshot.id ? 0.18 : 0))
            )
            // 整格（图标 + 2pt 内边距）都能点到，而不是只有图形的非透明像素。
            .contentShape(RoundedRectangle(cornerRadius: 5))
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

/// 前台应用块的**排版预算**（纯函数 + 唯一一组常量）：**宽决定一行几格、高决定几行**。
///
/// 单独立出来是为了可被判据穷举（先前的 `capacity(forWidth:)` 是视图里的 private 方法，只能靠肉眼看
/// 截图猜）：`FrontAppGridBudgetTests` 扫 0…400pt 每一档，钉住"画出来的格子绝不比块宽 / 块高更大"。
/// 视图只按它算出来的格数画，因此不会出现"挤变形"（格距是常量）或"被裁"（行列都在预算内）。
///
/// 常量来源：当前应用行高 = 它的图标 28（名称是 12pt 单行，行高由图标决定）；一格 = 图标 20 +
/// 悬停底色的左右内边距各 2 = 24；格间距 4；行间距 6（与上半行到网格之间用的是同一个间距）。
enum FrontAppGridBudget {
    /// 当前应用那一行的图标边长（也就是那一行的行高）。
    static let currentIconSize: CGFloat = 28
    /// 网格里一格的图标边长。
    static let cellIconSize: CGFloat = 20
    /// 一格的悬停底色内边距（左右各 2）。
    static let cellPadding: CGFloat = 2
    /// 格与格之间的水平间距。
    static let cellSpacing: CGFloat = 4
    /// 行间距（当前应用行 → 网格第一行、网格行与行之间都用它）。
    static let rowSpacing: CGFloat = 6

    /// 一格的边长（图标 + 左右内边距）——"画 n 格要占多宽"的唯一算法在下面两个纯函数里。
    static var cellSize: CGFloat { cellIconSize + cellPadding * 2 }

    /// 一行最多放几格：`(宽 + 间距) / (格 + 间距)` 向下取整（最后一格后面不留间距）。
    ///
    /// 宽到放不下一格就是 **0**：被丢的块（`HomeStripLayout` 的规则 ③ 会给它 `.zero` 提案）因此
    /// 一格都不画，而不是画一个越界的格子——越界的部分只会被块外框裁掉，看着就像"块坏了"。
    /// 生产档下宿主给模块块的最小宽度是 180 → 6 格、理想 240 → 8 格（与 docs/22 §3 记的旧预算同值）。
    static func cellsPerRow(forWidth width: CGFloat) -> Int {
        max(0, Int((width + cellSpacing) / (cellSize + cellSpacing)))
    }

    /// 网格最多放几行：**先扣掉上半的当前应用行，其余按 `格 + 行间距` 切**。
    ///
    /// 推导（k 行需要的高度）：`当前应用行 28 + 行间距 6 + k×24 + (k−1)×6 = 28 + 30k`，
    /// 于是 `k ≤ (高 − 28) / 30` —— 中间那个 `+6` 与 `(k−1)×6` 末尾的 `−6` 正好抵消，
    /// 所以公式就是 `(高 − 当前行) / (格 + 行间距)`，不需要额外项。
    ///
    /// 152pt（strip 的最小可用高度）→ **4 行**；再矮就一行行地减，放不下任何一行时是 0（不画网格）。
    static func rowCount(forHeight height: CGFloat) -> Int {
        max(0, Int((height - currentIconSize) / (cellSize + rowSpacing)))
    }

    /// 网格一共能放几格（0 = 一格都放不下 → 不画网格；块高够、块宽不够时同样是 0）。
    static func capacity(forWidth width: CGFloat, forHeight height: CGFloat) -> Int {
        cellsPerRow(forWidth: width) * rowCount(forHeight: height)
    }
}
