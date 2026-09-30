//
//  FrontAppModule.swift
//  Gourd 模块 · 前台应用联动（p2-shortcuts-frontapp / T4）
//
//  docs/22-shortcuts-and-frontapp.md 的落点：manifest（§接口与数据形状 4）+ 首页块
//  （§做法 机制三/机制四）。事件源、历史与图标取值是 T3 的 `FrontAppStore` / `FrontAppHistory`，
//  本文件不重写它们——只做三件事：**声明**（manifest）、**接线**（activate / deactivate / content）、
//  **画块**（`FrontAppHomeBlockView`）。
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
//     `start(selfBundleID:maxRecentApps:)`，`FrontAppHistory.clampedLimit`（3…8）在 store 里夹一次；
//     视图拿 **`store.recentLimit`**（= 夹取后的值）画，模块与视图都不再夹第二遍；
//  4. **显式传 config 值**（T3 报告 §6 的建议形态）：`activate()` 自己读一次 `maxRecentApps` 传进去，
//     不依赖 store 内部那条「参数为 nil 时读 config」的兜底路径——读点与显示点因此可以对上
//     （缺键兜 `FrontAppHistory.defaultLimit`，与 manifest 默认值同源）；
//  5. **订阅在 `activate()` 起、`deactivate()` 摘**（T3 的 store 已幂等）：模块关掉后不再收前台
//     事件、不再画块；重开时 `start` 再种一次初值。
//
//  文案走 Localizable key（06 §3.3 R5）：`module.frontapp.*` 五个 key（name / summary 由 manifest
//  引用，current / recent / emptyRecent 是本视图的可访问性标签与悬停说明）；
//  **颜色**：面板是黑底、系统外观可为浅色——块内文字一律显式浅色（`Color.white` / `.white.opacity(…)`），
//  不用 `.primary` / `.secondary`（同 `ShortcutsModule` / `LauncherModule` 的教训）。
//

import AppKit
import SwiftUI

// MARK: - FrontAppModule

/// 前台应用模块（`docs/22` §接口与数据形状 4）：**只在首页 strip 里占一块**——
/// 上半是当前前台应用（图标 + 名称），下半是最近切换过的那几个（小图标，点一下切回去）。
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

    /// 只答 `home`：首页块 = 当前应用 + 最近切换。
    ///
    /// 三条 `.none` **不是**"暂时没实现"——是本批的契约（口径 1）：折叠槽位、展开 tab 与锁屏都不占。
    /// 传进视图的是 **`store.recentLimit`**（夹取后的值，口径 3）：视图不再读 config、也不再夹。
    func content(for request: ContentRequest) -> ModuleContent {
        switch request.surface {
        case .home:
            return .view(AnyView(FrontAppHomeBlockView(store: store, maxRecentApps: store.recentLimit)))
        case .compact, .expanded, .lockscreen:
            return .none
        }
    }
}

// MARK: - 首页块视图

/// 首页块：**上半当前应用（图标 28 + 名称单行）、下半最近切换（一排小图标 20，点一下切回去）**。
///
/// 三件事各归各处，视图这一层只做呈现（没有过滤、没有排序、没有夹取）：
/// - 状态（`current` / `recent`）与图标都在 `FrontAppStore`（图标只走 `store.icon(for:)`——接口里
///   没有第二个来源）；
/// - 历史口径（去重 / 移到最前 / 截到上限 / 排除自身）是 T3 的纯函数，视图不重算；
/// - 上限是 **`store.recentLimit`**（模块传进来，口径 3）：这里只用它和块宽一起决定"画几个"。
///
/// **空态**（拿不到前台应用——`current` 为 nil）：画一行浅色 `—`。这时 `recent` 必为空
/// （历史只在一次真实的前台切换里追加，而那次切换一定同时更新 `current`），所以块里不会出现
/// "没有当前应用、却有一排历史"的怪状态。
///
/// **颜色**：面板黑底 + 系统外观可为浅色 → 一律显式浅色（`Color.white` / `.white.opacity(…)`）。
private struct FrontAppHomeBlockView: View {
    @ObservedObject var store: FrontAppStore
    /// 最近应用最多画几个（= `store.recentLimit`，"画几个"的**上限预算**；夹取已在 store 里做过）。
    let maxRecentApps: Int
    /// 当前悬停的那一格（`nil` = 没悬停在任何一格上；按 **id** 记，见 `recentIcon(_:)`）。
    @State private var hoveredID: String?

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: Self.rowSpacing) {
                currentRow
                recentRow(fitting: proxy.size.width)
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
                appIcon(current, size: Self.currentIconSize)

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

    // MARK: 下半：最近切换

    /// 最近切换一行：**能在块宽里放下几个就画几个**（不超过 `maxRecentApps`）；
    /// 一条历史都没有时这一行**不画**——块宽只有 180pt，这块的主角是"当前应用"（§备选与取舍 ⑤），
    /// 没有第二行可画时不留占位、不做空态文案。
    ///
    /// 图标是按钮：**点一下 = `store.activate(snapshot)`**（切回那个应用；已是前台的点了是空操作）。
    /// 悬停给底色（图标本身只有 20pt，没有底色看不出哪一格是热区）。
    @ViewBuilder
    private func recentRow(fitting width: CGFloat) -> some View {
        let items = Array(store.recent.prefix(capacity(forWidth: width)))
        if !items.isEmpty {
            HStack(spacing: Self.recentSpacing) {
                ForEach(items) { snapshot in
                    recentIcon(snapshot)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(LocalizedStringKey("module.frontapp.recent")))
        }
    }

    /// 一个小图标（20pt）：悬停底色 + 整格可点。
    ///
    /// 悬停态按 **id** 记（不是 `Bool`）：一排图标共用一个视图状态，`Bool` 会让悬停一个时全排都亮。
    private func recentIcon(_ snapshot: FrontAppSnapshot) -> some View {
        appIcon(snapshot, size: Self.recentIconSize)
            .padding(2)
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

    // MARK: 排版预算

    /// 图标边长 / 间距 / 行距（唯一取值在这几个常量里）。
    private static let currentIconSize: CGFloat = 28
    private static let recentIconSize: CGFloat = 20
    private static let recentSpacing: CGFloat = 4
    private static let rowSpacing: CGFloat = 6

    /// 块宽里最多放得下几个小图标（每格 = 图标 20 + 悬停底色的左右内边距各 2 + 间距 4）：至少 1 个
    /// ——块再窄也不该"一个都不画"（宿主给模块块的最小宽度是 180，这里只是不让图标行溢出被裁）。
    private func capacity(forWidth width: CGFloat) -> Int {
        let step = Self.recentIconSize + 4 + Self.recentSpacing
        return max(1, min(maxRecentApps, Int((width + Self.recentSpacing) / step)))
    }
}
