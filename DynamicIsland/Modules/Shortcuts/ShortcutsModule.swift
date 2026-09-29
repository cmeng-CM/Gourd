//
//  ShortcutsModule.swift
//  Gourd 模块 · 快捷指令（p2-shortcuts-frontapp / T2）
//
//  docs/22-shortcuts-and-frontapp.md 的落点：manifest（§接口与数据形状 2）+ 展开 tab
//  （搜索框 + 刷新按钮 + 列表 + 底部结果行，§做法 机制一/机制二）。
//  解析与过滤是 T1 的纯函数（`ShortcutListParser` / `ShortcutFiltering`），
//  取数与运行是 T1 的两个注入点（`ShortcutsListing` / `ShortcutsRunning`）——本文件不重写它们。
//
//  五条刻意写死的口径（改动前先读）：
//
//  1. **只声明 `expanded`**（§接口与数据形状 2）：折叠态左右槽位未落地、也没有首页块形态，
//     本批**不占**折叠槽位与首页——`.compact` / `.lockscreen` / `.home` 一律答 `.none`
//     （不占位、不算失败，06 §3.2）；
//  2. **进 tab 不起子进程**（§机制一）：只有「首次进入且 `cachedShortcuts` 为空」与「点刷新」
//     两处会取数。`load()` 有 `hasLoaded` 闸门，因此进进出出只有那一次；
//  3. **缓存存原始行**（D-01）：`cachedShortcuts` 里是命令输出的原样行，读缓存与读命令走同一条
//     解析路（`ShortcutListParser.parse`）——格式化或解析规则将来变了不会与缓存格式打架；
//  4. **先落盘再发布**（§机制一 + 失败信号「固定项重启后消失」）：`refresh()` 先把原始行写回
//     `cachedShortcuts` 再换内存里的清单；`togglePin` 同理先写 `pinnedShortcuts` 再换 `pinned`；
//  5. **禁止并发**（§机制二）：`isRunning` 是模块级闸门，运行期间第二次 `run` 直接返回；
//     视图里运行按钮与刷新按钮**都**禁用（刷新会换掉正在跑的那条的 identifier 语义）。
//     限时用 `timeoutSeconds`（默认 30s），超时的判定在 T1 的 `shortcutsRun` 里（`terminate()`，不重试）。
//
//  输出的**截断在 T1 的 runner 侧**做（`ShortcutRunResult.maxOutputLines` = 40 行，超了追加一条截断提示）：
//  视图只显示 `output`、不重算行数——重算会把 runner 追加的那行提示本身切掉。
//
//  文案走 Localizable key（06 §3.3 R5）：`module.shortcuts.*` 十五个 key；
//  **颜色**：面板是黑底、系统外观可为浅色——本模块内所有文字与图标一律显式浅色
//  （`Color.white` / `.white.opacity(...)`），不用 `.primary` / `.secondary`（同 LauncherModule 的教训）。
//

import SwiftUI

// MARK: - 配置默认值

/// manifest `config` 四个键的**默认值**（唯一一份：manifest 字面量与 `ShortcutsSettings.read`
/// 的兜底都用它——两处各写一个数就会漂）。
enum ShortcutsConfigDefaults {
    /// 固定表的 identifier（顺序 = 用户固定顺序；`ShortcutFiltering.visible` 按它排固定区）。
    static let pinnedShortcuts: [String] = []
    /// 是否把运行输出回显到结果行（默认关：大多数指令没有输出，开着反而多一块空白）。
    static let showOutput = false
    /// 单次运行的限时（秒）。
    static let timeoutSeconds = 30
    /// 清单缓存（**原始行**，见口径 3）。
    static let cachedShortcuts: [String] = []
}

/// 本模块 config 的**一次快照**（两个只在**运行那一刻**读的键）。
///
/// `pinnedShortcuts` / `cachedShortcuts` 不走这里：那两键是**状态**（`load()` / `refresh()` /
/// `togglePin` 读写），每次动作都现读现写；这两个是**本次运行怎么跑**的参数。
struct ShortcutsSettings: Equatable {
    var showOutput: Bool
    var timeoutSeconds: TimeInterval

    /// 读一次 config。`get` 在「schema 里没有这个键」时给 nil（本批不做 schema 迁移），
    /// 因此两处都兜到 `ShortcutsConfigDefaults`——缺键的呈现与 manifest 默认值一致。
    @MainActor
    static func read(from config: ConfigHandle) -> ShortcutsSettings {
        ShortcutsSettings(
            showOutput: config.get("showOutput", as: Bool.self) ?? ShortcutsConfigDefaults.showOutput,
            timeoutSeconds: TimeInterval(
                config.get("timeoutSeconds", as: Int.self) ?? ShortcutsConfigDefaults.timeoutSeconds
            )
        )
    }
}

// MARK: - 固定项（纯函数）

/// 固定表的**纯函数口径**（同启动台 `LauncherPinning` 的三条：幂等、追加在表尾、取消清干净）。
///
/// 顺序（表尾追加）在这里**有语义**：`ShortcutFiltering.visible` 把固定区排在前面，区内的顺序
/// 就是这张表的顺序（用户固定的先后），所以不是"当集合用"。
enum ShortcutsPinning {

    /// 是否已固定（右键菜单的文案与行内的图钉都读它）。
    static func isPinned(_ identifier: String, in pinned: [String]) -> Bool {
        pinned.contains(identifier)
    }

    /// 固定：追加到**表尾**。已在表里 → 原样返回（幂等，不产生重复项）。
    static func adding(_ identifier: String, to pinned: [String]) -> [String] {
        guard !pinned.contains(identifier) else { return pinned }
        return pinned + [identifier]
    }

    /// 取消固定：移除**所有**同 identifier 的项（手改盘上的表塞进重复项时一并清掉）。不在表里 → 原样返回。
    static func removing(_ identifier: String, from pinned: [String]) -> [String] {
        pinned.filter { $0 != identifier }
    }

    /// 取反（右键菜单的唯一入口）。
    static func toggled(_ identifier: String, in pinned: [String]) -> [String] {
        isPinned(identifier, in: pinned) ? removing(identifier, from: pinned) : adding(identifier, to: pinned)
    }
}

// MARK: - 一次运行的记录

/// 结果行要显示的东西：跑的是**哪一条**（identifier 是身份、name 只用于给人看）与这次的结果。
struct ShortcutRunRecord: Equatable {
    let identifier: String
    let name: String
    let result: ShortcutRunResult
}

// MARK: - ShortcutsStore

/// 快捷指令的取数、固定与运行：全是"拿数据 + 改数据"，过滤与排序一律走 T1 的纯函数
/// （`ShortcutFiltering.visible`）——视图里不另写匹配或排序逻辑。
///
/// 取数与运行都是**注入点**（D-03）：默认真实现（T1 的 `shortcutsListLines` / `shortcutsRun`），
/// 用例给假体，于是单测不跑真命令、不依赖本机装了什么快捷指令。
@MainActor
final class ShortcutsStore: ObservableObject {

    /// 清单（解析后的；顺序 = 命令给出的顺序）。用户可见顺序由 `ShortcutFiltering.visible` 定。
    @Published private(set) var shortcuts: [Shortcut] = []
    /// 固定表（identifier 的顺序 = 用户固定顺序）——`pinnedShortcuts` 的内存镜像。
    @Published private(set) var pinned: [String] = []
    /// **模块级并发闸门**：为真时 `run` 直接返回（不排队、不放弃前一条）。
    @Published private(set) var isRunning = false
    /// 正在跑的那一条（行内 spinner 的判据）；跑完清空——跑完之后的行状态由 `lastResult` 承载。
    @Published private(set) var runningIdentifier: String?
    /// 最近一次运行的结果（含跑的是哪一条）。
    @Published private(set) var lastResult: ShortcutRunRecord?
    /// 取数中（刷新按钮的转圈与禁用判据）。
    @Published private(set) var isLoading = false

    private let config: ConfigHandle
    private let logger: ModuleLogger
    private let list: ShortcutsListing
    private let runShortcut: ShortcutsRunning
    private let settings: () -> ShortcutsSettings

    /// 首次进入的闸门：`load()` 只做一次（自动刷新挂在这一档上，口径 2）。
    private var hasLoaded = false

    /// 取数与运行都从 `ShortcutsModule.init` 注入（缺省 = T1 的真实现：起 `/usr/bin/shortcuts`）；
    /// 用例直接构造本类型并给假体。
    init(
        config: ConfigHandle,
        logger: ModuleLogger,
        list: ShortcutsListing? = nil,
        runShortcut: ShortcutsRunning? = nil,
        settings: (() -> ShortcutsSettings)? = nil
    ) {
        self.config = config
        self.logger = logger
        self.list = list ?? { await shortcutsListLines() }
        self.runShortcut = runShortcut ?? { identifier, timeout, captureOutput in
            await shortcutsRun(identifier: identifier, timeout: timeout, captureOutput: captureOutput)
        }
        self.settings = settings ?? { ShortcutsSettings.read(from: config) }
    }

    // MARK: 取数

    /// 进 tab 时调用（**幂等**）：读盘上的缓存与固定表 → 发布；**首次进入且缓存为空**时再自动拉一次。
    ///
    /// 这是「进 tab 不起子进程」的落点（口径 2）：读盘不算取数，自动刷新只有这一处、且只有一次
    /// （`hasLoaded` 闸门）——用户下次进来看到的是缓存，想要新的就点刷新。
    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        let cached = config.get("cachedShortcuts", as: [String].self) ?? ShortcutsConfigDefaults.cachedShortcuts
        pinned = config.get("pinnedShortcuts", as: [String].self) ?? ShortcutsConfigDefaults.pinnedShortcuts
        shortcuts = ShortcutListParser.parse(lines: cached)
        logger.info("读缓存：\(shortcuts.count) 条快捷指令（\(cached.count) 行）、固定 \(pinned.count) 条")

        guard cached.isEmpty else { return }
        logger.info("缓存为空：首次进入自动拉一次清单（之后只在点刷新时取数）")
        await refresh()
    }

    /// 点刷新：取一次**原始行** → **先写回 config 的 `cachedShortcuts`，再发布解析后的清单**（口径 3/4）。
    ///
    /// 空结果也照写：取数失败在真实现里就是 `[]`（T1 把原因写进日志），写下去与"本机真的没有指令"
    /// 呈现一致——不在这里编造"失败就不更新"的第二套语义（否则屏幕与盘会各有一份不同的表）。
    func refresh() async {
        isLoading = true
        let lines = await list()
        isLoading = false

        if !config.set("cachedShortcuts", to: lines) {
            logger.warn("刷新：缓存写盘失败（键不在 schema 里？），本次只更新内存")
        }
        shortcuts = ShortcutListParser.parse(lines: lines)
        logger.info("刷新：取到 \(lines.count) 行、解析出 \(shortcuts.count) 条")
    }

    // MARK: 动作

    /// 右键菜单：固定 / 取消固定（**先落盘再刷新**，幂等）。
    ///
    /// 基线从盘上现读（不是内存里的 `pinned`）：模块激活后没进过 tab 时内存还是空的，
    /// 那时固定一项不该把盘上原有的表覆盖掉（同 `LauncherPins` 的"读 → 改 → 落盘 → 返回"）。
    func togglePin(_ shortcut: Shortcut) {
        let current = config.get("pinnedShortcuts", as: [String].self) ?? pinned
        let updated = ShortcutsPinning.toggled(shortcut.identifier, in: current)
        let wasPinned = ShortcutsPinning.isPinned(shortcut.identifier, in: current)

        if !config.set("pinnedShortcuts", to: updated) {
            logger.warn("固定失败：\(shortcut.identifier) 写盘不成功（键不在 schema 里？）")
        }
        pinned = updated   // 落盘之后才换内存值，屏幕与盘不会有一帧的分歧
        logger.info("\(wasPinned ? "取消固定" : "固定")：\(shortcut.name)（\(shortcut.identifier)），现有固定项 \(updated.count) 条")
    }

    /// 跑一条（§机制二）：**模块级闸门**——`isRunning` 为真时直接返回。
    ///
    /// 限时与是否回显输出在**这一刻**从 config 读一次（`ShortcutsSettings`），传进注入的运行器；
    /// 跑完把结果记进 `lastResult`（成功/失败/超时的判定与 stderr 摘要都在 T1 的 `shortcutsRun` 里）。
    func run(_ shortcut: Shortcut) async {
        guard !isRunning else {
            logger.warn("已有运行中的快捷指令（\(runningIdentifier ?? "?")），忽略对 \(shortcut.identifier) 的这次请求")
            return
        }

        isRunning = true
        runningIdentifier = shortcut.identifier
        let settings = settings()
        logger.info(
            "运行：\(shortcut.name)（\(shortcut.identifier)），限时 \(Int(settings.timeoutSeconds.rounded()))s、回显输出 \(settings.showOutput)"
        )

        let result = await runShortcut(shortcut.identifier, settings.timeoutSeconds, settings.showOutput)

        lastResult = ShortcutRunRecord(identifier: shortcut.identifier, name: shortcut.name, result: result)
        runningIdentifier = nil
        isRunning = false
        logger.info("运行结束：\(String(describing: result.outcome))，耗时 \(Int(result.duration * 1000))ms")
    }
}

// MARK: - ShortcutsModule

/// 快捷指令模块（`docs/22` §接口与数据形状 2；`docs/14` §1 的 `com.cmeng.gourd.shortcuts`）。
///
/// 本批只声明 `expanded`（口径 1）：展开面板多一个「快捷指令」tab，折叠态与首页**一行不加**。
@MainActor
final class ShortcutsModule: GourdModule {
    /// 模块 id 的**唯一字面量**（manifest 与用例都读它，不各写一份）。
    static let moduleID = "com.cmeng.gourd.shortcuts"

    /// 静态元数据（docs/22 §接口与数据形状 2 逐条对应）。
    ///
    /// - `surfaces: [.expanded]`：**只声明展开 tab**——折叠槽位已被用户降级、本模块也没有首页块形态；
    /// - `defaultPlacement: nil`：placement 只在含 `compact` 时有意义，因此不给值
    ///   （tab 顺序随之取 `Int.max`，落在模块 tab 段）；
    /// - `defaultEnabled: false`：新增模块一律默认关（docs/14 T-12 / docs/22 D-06）；
    /// - `permissions: ["shortcuts:run"]`：06 §7.1 已登记的能力条目（`/usr/bin/shortcuts` 是系统
    ///   自带的命令行入口，零私有 API；首次运行可能弹系统自动化提示，属既有边界，见 §已知限制 1）；
    /// - `config` 四键：状态两键（`pinnedShortcuts` / `cachedShortcuts`）+ 运行参数两键
    ///   （`showOutput` / `timeoutSeconds`），默认值只有 `ShortcutsConfigDefaults` 一处。
    static let manifest = ModuleManifest(
        manifestVersion: 1,
        id: moduleID,
        name: LocalizedText(key: "module.shortcuts.name"),
        summary: LocalizedText(key: "module.shortcuts.summary"),
        icon: IconSpec(type: "symbol", name: "bolt.square"),
        version: "1.0.0",
        apiVersion: HostInfo.currentAPIVersion,
        kind: "builtin",
        surfaces: [.expanded],
        defaultPlacement: nil,
        defaultEnabled: false,
        permissions: ["shortcuts:run"],
        config: ConfigSchema(
            type: "object",
            properties: [
                // 固定表（identifier 的顺序 = 用户固定顺序）。状态键：`load()` / `togglePin` 读写
                "pinnedShortcuts": ConfigNode(
                    type: "list",
                    title: nil,
                    default: .strings(ShortcutsConfigDefaults.pinnedShortcuts),
                    values: nil,
                    itemType: "string"
                ),
                // 是否把运行输出回显到结果行。运行参数：`run` 那一刻读一次
                "showOutput": ConfigNode(
                    type: "boolean",
                    title: nil,
                    default: .bool(ShortcutsConfigDefaults.showOutput),
                    values: nil,
                    itemType: nil
                ),
                // 单次运行的限时（秒）。运行参数：`run` 那一刻读一次（超时的判定在 T1 的 runner 里）
                "timeoutSeconds": ConfigNode(
                    type: "integer",
                    title: nil,
                    default: .int(ShortcutsConfigDefaults.timeoutSeconds),
                    values: nil,
                    itemType: nil
                ),
                // 清单缓存（**原始行**，见口径 3）。状态键：`refresh()` 写、`load()` 读
                "cachedShortcuts": ConfigNode(
                    type: "list",
                    title: nil,
                    default: .strings(ShortcutsConfigDefaults.cachedShortcuts),
                    values: nil,
                    itemType: "string"
                ),
            ]
        )
    )

    private let context: ModuleContext
    private let store: ShortcutsStore

    /// 取数与运行**在这里注入**（缺省 = T1 的真实现：真起 `/usr/bin/shortcuts`）。
    init(context: ModuleContext) {
        self.context = context
        let config = context.config
        self.store = ShortcutsStore(
            config: config,
            logger: context.logger,
            list: { await shortcutsListLines() },
            runShortcut: { identifier, timeout, captureOutput in
                await shortcutsRun(identifier: identifier, timeout: timeout, captureOutput: captureOutput)
            },
            settings: { ShortcutsSettings.read(from: config) }
        )
    }

    /// 激活很轻：**不读盘、不取数、不起子进程**（那些属于"用户真的要打开这个 tab"，口径 2）。
    func activate() async throws {
        context.logger.info("shortcuts 模块已激活（进 tab 读缓存；首次缓存为空或点刷新才起子进程）")
    }

    /// 没有常驻副作用（不订阅通知、不起定时器），所以没有要收的东西。
    func deactivate() async {}

    /// 只答 `expanded`：`.compact` / `.lockscreen` / `.home` 一律 `.none`（不占位、不算失败）。
    ///
    /// 这三条**不是**"暂时没实现"——是本批的契约（口径 1）：折叠槽位与首页块本批不占。
    func content(for request: ContentRequest) -> ModuleContent {
        switch request.surface {
        case .expanded:
            return .view(AnyView(ShortcutsModuleView(
                store: store,
                settings: ShortcutsSettings.read(from: context.config)
            )))
        case .compact, .lockscreen, .home:
            return .none
        }
    }
}

// MARK: - 展开面板视图（搜索框 + 刷新 + 列表 + 结果行）

/// 展开面板的快捷指令 tab（本批唯一的 surface）：**顶部搜索框 + 刷新按钮 + 列表 + 底部结果行**。
///
/// 三件事各归各处，视图这一层只做呈现：
/// - 取数与状态（清单 / 固定表 / 运行态 / 结果）在 `ShortcutsStore`；
/// - 过滤与排序是 T1 的纯函数（`ShortcutFiltering.visible`）——视图里**不另写**匹配逻辑；
/// - 截断在 T1 的 runner 侧做完（文件头末段），视图只显示 `output`。
///
/// 搜索词是 **UI 局部 `@State`**（不进 Defaults）：面板重开 = 干净的一屏。
private struct ShortcutsModuleView: View {
    @ObservedObject var store: ShortcutsStore
    let settings: ShortcutsSettings

    @State private var query = ""

    /// 视野里的清单：固定项在前（保持固定表顺序）+ 搜索（`ShortcutFiltering.visible`，唯一排序出口）。
    private var visible: [Shortcut] {
        ShortcutFiltering.visible(store.shortcuts, pinned: store.pinned, query: query)
    }

    /// 刷新按钮能不能按：运行期间**不能**（刷新会换掉正在跑的那条的 identifier 语义，§机制二）。
    private var canRefresh: Bool { !store.isRunning && !store.isLoading }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            Group {
                if store.shortcuts.isEmpty {
                    ShortcutsPlaceholder(kind: .empty)
                } else if visible.isEmpty {
                    ShortcutsPlaceholder(kind: .noMatch)
                } else {
                    list
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let record = store.lastResult {
                ShortcutsResultRow(record: record, showsOutput: settings.showOutput)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 每次进 tab 都调一次：首次读缓存（缓存为空时自动拉一次），之后直接返回（幂等，见 `load`）。
        .task { await store.load() }
    }

    /// 顶部一行：搜索框 + 刷新按钮。
    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))

                TextField(LocalizedStringKey("module.shortcuts.searchPlaceholder"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.08)))

            Button {
                Task { await store.refresh() }
            } label: {
                Group {
                    if store.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(canRefresh ? 0.85 : 0.3))
                    }
                }
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canRefresh)
            .help(LocalizedStringKey("module.shortcuts.refresh"))
        }
    }

    /// 列表：`LazyVStack`（只建可见行——清单可能很长，本机实测两条也照这个口径写）。
    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(visible) { shortcut in
                    ShortcutsRow(
                        shortcut: shortcut,
                        isPinned: ShortcutsPinning.isPinned(shortcut.identifier, in: store.pinned),
                        isThisRunning: store.runningIdentifier == shortcut.identifier,
                        canRun: !store.isRunning,
                        onRun: { Task { await store.run(shortcut) } },
                        onTogglePin: { store.togglePin(shortcut) }
                    )
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// 列表里的一行：**名称 + identifier（次要小字）+ 运行按钮 / 运行中 spinner**；
/// 右键固定 / 取消固定；悬停高亮。
///
/// identifier 也要显示：它是身份（名称可重复、可随时改），排查"跑的是哪一条"时只有它说了算。
private struct ShortcutsRow: View {
    let shortcut: Shortcut
    let isPinned: Bool
    /// 正在跑的就是这一条（行内 spinner 的判据）。
    let isThisRunning: Bool
    /// 此刻允许运行（`!store.isRunning`：任何一条在跑时，所有行的运行按钮都禁用）。
    let canRun: Bool
    let onRun: () -> Void
    let onTogglePin: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Text(shortcut.name)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(shortcut.identifier)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            if isThisRunning {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small)
                    Text(LocalizedStringKey("module.shortcuts.running"))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                }
            } else {
                Button(action: onRun) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(canRun ? 0.85 : 0.3))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canRun)
                .help(LocalizedStringKey("module.shortcuts.run"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(isHovered ? 0.09 : 0)))
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onHover { isHovered = $0 }
        .help(shortcut.identifier)   // 名称被截断时，悬停给全名与身份
        .contextMenu {
            Button(action: onTogglePin) {
                Text(LocalizedStringKey(isPinned ? "module.shortcuts.unpin" : "module.shortcuts.pin"))
            }
        }
    }
}

/// 底部结果行：**成功 / 失败 / 超时** + 说明（`failureMessage`，系统原话）+ `showOutput` 时的输出。
///
/// 「失败时把系统的原话摆出来」是 §机制二 的硬口径，因此这一栏**不吞**：
/// 失败 / 超时时若结果里没有说明（`failureMessage` 空串），退到 `module.shortcuts.runFailed`
/// 一句——空着等于把失败说成"没有原因"。
private struct ShortcutsResultRow: View {
    let record: ShortcutRunRecord
    let showsOutput: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)

                Text(LocalizedStringKey(outcomeKey))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tint)

                Text(record.name)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                Text(durationText)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
            }

            if !messageText.isEmpty {
                Text(messageText)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

            if showsOutput, !record.result.output.isEmpty {
                // 截断已在 T1 的 runner 侧做完（含末尾那行截断提示）：这里只显示、不再切行数。
                ScrollView(.vertical, showsIndicators: true) {
                    Text(record.result.output)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 76)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.06)))
    }

    private var outcomeKey: String {
        switch record.result.outcome {
        case .success: return "module.shortcuts.success"
        case .failure: return "module.shortcuts.failure"
        case .timedOut: return "module.shortcuts.timedOut"
        }
    }

    private var iconName: String {
        switch record.result.outcome {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case .timedOut: return "clock.badge.exclamationmark"
        }
    }

    private var tint: Color {
        switch record.result.outcome {
        case .success: return .white.opacity(0.85)
        case .failure: return .orange
        case .timedOut: return .yellow
        }
    }

    /// 说明栏：成功时通常为空（没有要解释的东西）；失败 / 超时时是系统原话，
    /// 系统没给原话（空串）时退到 `runFailed`。
    private var messageText: String {
        let message = record.result.failureMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty { return message }
        return record.result.outcome == .success ? "" : String(localized: "module.shortcuts.runFailed")
    }

    private var durationText: String {
        String(format: "%.1fs", record.result.duration)
    }
}

/// 空态 / 无命中的占位（同启动台的 `LauncherPlaceholder` 口径：一句说明，不弹窗、不引导授权）。
private struct ShortcutsPlaceholder: View {
    enum Kind {
        /// 清单是空的（还没刷新过 / 本机没有快捷指令）——文案里带"点刷新"。
        case empty
        /// 有清单，但搜索词一个都没命中。
        case noMatch
    }

    let kind: Kind

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: kind == .empty ? "bolt.square" : "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))

            Text(LocalizedStringKey(kind == .empty ? "module.shortcuts.empty" : "module.shortcuts.noMatch"))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
