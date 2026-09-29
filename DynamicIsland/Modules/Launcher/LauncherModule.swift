//
//  LauncherModule.swift
//  Gourd 内置模块 · 启动台（P2 批次 / T2）
//
//  docs/19-launcher.md §接口与数据形状 4 + §改动点设计 2/3/4 的落点：
//  manifest + 展开 tab（搜索框 + 应用网格）+ 点图标启动并收起 + 右键固定 / 取消固定。
//  扫描与排序的纯函数在 T1 的两个文件里（`LauncherAppScanner` / `LauncherRanking`），本文件不重写它们。
//
//  四条刻意写死的口径（改动前先读）：
//
//  1. **只声明 `expanded`**（D-02 / 控制器裁决 1）：折叠态左右槽位未落地、用户也没要求首页块，
//     本批**不占**折叠槽位与首页——`.compact` / `.lockscreen` / `.home` 一律答 `.none`
//     （不占位、不算失败，06 §3.2）。首页与折叠态因此与改动前逐字一致。
//  2. **固定项是本地数据，恒优先**（§改动点设计 4 的陷阱）：Spotlight 查询失败 / 超时 /
//     `showRecents = false` / 使用数据为空，影响到的只有"固定项**之后**的顺序"（回落按名称），
//     **不影响固定项本身**——排序由 `LauncherRanking.rank` 一次算完，固定判据只认 `LauncherApp.id`。
//  3. **图标按可见项惰性取并缓存**（§横切关注点）：取图标的唯一时机是"一个格子真的要画出来"
//     （`LazyVGrid` 只为可见行建视图），取过的按 `.app` 路径缓存。**不做**"进 tab 就为几百个
//     应用取一遍图标"——那是本批的失败信号之一（进 tab 明显卡顿）。
//  4. **不自己记账使用次数**（控制器裁决 2 / §备选与取舍）：只用 Spotlight 的
//     `kMDItemLastUsedDate` / `kMDItemUseCount`；查不到就按名称排，不新增第二套统计。
//
//  规格来源逐条对应：
//  - manifest（id / name / icon / surfaces / defaultEnabled / permissions / config 三个键）
//    = §接口与数据形状 4；
//  - 网格：搜索框 + 图标 + 名称、列数按面板宽度自适应 = §改动点设计 2 + §做法 机制三；
//  - 启动：`NSWorkspace.shared.openApplication(at:configuration:)`（`activates = true`）→
//    `context.ui.requestCollapse()`（与待办 / 通知同口径）= §处理链路的两步；
//  - 固定：`.contextMenu` 固定 / 取消固定、键 = `LauncherApp.id`、**先落盘再刷新**
//    = §改动点设计 3；
//  - 排序接入：先按名称（空 `usage`）立即渲染，Spotlight 回来再重排 = §改动点设计 4。
//
//  文案走 Localizable key（06 §3.3 R5）：`module.launcher.name` / `.summary` /
//  `.searchPlaceholder` / `.pin` / `.unpin` / `.empty` / `.noMatch`。
//  **颜色**：面板是黑底、系统外观可为浅色——本模块内所有文字与图标一律显式浅色
//  （`Color.white` / `.white.opacity(...)`），不用 `.primary` / `.secondary`（同 ProgressModule 的教训）。
//

import AppKit
import Defaults
import SwiftUI

// MARK: - 配置默认值

/// manifest `config` 三个键的**默认值**（唯一一份：manifest 字面量与 `LauncherSettings.read`
/// 的兜底都用它——两处各写一个数就会漂）。
enum LauncherConfigDefaults {
    /// 单个格子（图标 + 名称）的目标宽度（pt）。44 是本机 770pt 面板下的实测档：一行 10 列左右，
    /// 图标与名称都看得清（视图侧还要经 `LauncherGridMetrics` 夹取到 28…96）。
    static let iconSize: Double = 44
    /// 格子间距的**倍率**（1 = 基准 10pt；视图侧夹取到 0.6…1.6）。
    static let density: Double = 1
    /// 是否用 Spotlight 的使用数据（最近使用 / 使用次数）排序。**默认 true**：
    /// 关掉 = 固定 → 名称，是"我不想让排序跟着系统跑"的用户才需要的档。
    static let showRecents = true
}

/// 本模块 config 的**一次快照**（三个键都经 `ConfigHandle` 解析：manifest 默认值 + 用户覆盖）。
///
/// 取快照的时机是"每次取内容 / 每次读设置"：用户改了值，**下一次进 tab 就是新值**
/// （不需要重启，也不需要模块自己订阅配置变更——`configChanged` 那条事件链属 P1-3）。
struct LauncherSettings: Equatable {
    var iconSize: Double
    var density: Double
    var showRecents: Bool

    /// 读一次 config。`get` 在「schema 里没有这个键」时给 nil（本批不做 schema 迁移），
    /// 因此三处都兜到 `LauncherConfigDefaults`——缺键的呈现与 manifest 默认值一致。
    @MainActor
    static func read(from config: ConfigHandle) -> LauncherSettings {
        LauncherSettings(
            iconSize: config.get("iconSize", as: Double.self) ?? LauncherConfigDefaults.iconSize,
            density: config.get("density", as: Double.self) ?? LauncherConfigDefaults.density,
            showRecents: config.get("showRecents", as: Bool.self) ?? LauncherConfigDefaults.showRecents
        )
    }
}

// MARK: - 固定项（纯函数 + 读写接缝）

/// 固定表的**纯函数口径**（docs/19 §接口与数据形状 3 + §验收标准「重复固定 / 取消不产生重复项」）。
///
/// 三项都只读不改（`[String]` 是值类型），因此可以直接用构造的表钉住幂等性。
enum LauncherPinning {

    /// 是否已固定（视图的图钉角标与右键菜单文案都读它）。
    static func isPinned(_ id: String, in pinned: [String]) -> Bool {
        pinned.contains(id)
    }

    /// 固定：追加到**表尾**。已在表里 → 原样返回（幂等，不产生重复项）。
    ///
    /// 顺序（表尾追加）本身不影响排序——`LauncherRanking.rank` 只把这张表当集合用；
    /// 保留动作顺序是为了让盘上的值与用户的操作顺序一致（将来若做"固定项按固定先后排"不必迁移数据）。
    static func adding(_ id: String, to pinned: [String]) -> [String] {
        guard !pinned.contains(id) else { return pinned }
        return pinned + [id]
    }

    /// 取消固定：移除**所有**同 id 的项（手改 `UserDefaults` 塞进重复项时一并清掉）。不在表里 → 原样返回。
    static func removing(_ id: String, from pinned: [String]) -> [String] {
        pinned.filter { $0 != id }
    }

    /// 取反（右键菜单的唯一入口）。
    static func toggled(_ id: String, in pinned: [String]) -> [String] {
        isPinned(id, in: pinned) ? removing(id, from: pinned) : adding(id, to: pinned)
    }
}

/// 固定项的**读写接缝**：全模块唯一碰 `Defaults` 的地方（也是单测唯一的注入点——
/// 用例给内存假体，**不碰开发机真实的 `com.apple.*` 域**）。
///
/// 形态是「读 → 改 → **落盘** → 返回落盘后的表」：调用方拿到返回值时盘上已是新值，
/// 把它赋给 `@Published pinned` 之后屏幕才重排——**先落盘再刷新**（§改动点设计 3），
/// 于是"屏上有、盘上没有"的窗口不存在（重启后固定项消失的失败信号就堵在这一层）。
struct LauncherPins {
    private let read: () -> [String]
    private let write: ([String]) -> Void

    init(read: @escaping () -> [String], write: @escaping ([String]) -> Void) {
        self.read = read
        self.write = write
    }

    /// 生产形态：`Defaults[.pinnedApps]`（缺键 = `[]` = 没有固定项）。
    static var live: LauncherPins {
        LauncherPins(
            read: { Defaults[.pinnedApps] },
            write: { Defaults[.pinnedApps] = $0 }
        )
    }

    /// 盘上的固定项（模块激活与首次进 tab 时读一次）。
    func load() -> [String] { read() }

    /// 固定一个 id（幂等；表没变就不写盘）。返回落盘后的表。
    @discardableResult
    func pin(_ id: String) -> [String] { update { LauncherPinning.adding(id, to: $0) } }

    /// 取消固定（幂等；表没变就不写盘）。返回落盘后的表。
    @discardableResult
    func unpin(_ id: String) -> [String] { update { LauncherPinning.removing(id, from: $0) } }

    /// 取反（右键菜单走它）。返回落盘后的表。
    @discardableResult
    func toggle(_ id: String) -> [String] { update { LauncherPinning.toggled(id, in: $0) } }

    /// 读 → 改 → 落盘 → 返回。**表没变就不写**：重复固定 / 重复取消不该产生一次多余的写盘
    /// （幂等的另一半——表不变，盘也就不动）。
    private func update(_ transform: ([String]) -> [String]) -> [String] {
        let current = read()
        let updated = transform(current)
        guard updated != current else { return current }
        write(updated)
        return updated
    }
}

// MARK: - Spotlight 使用数据（取数 + 映射）

/// 一个应用的**使用数据样本**（Spotlight 的原始读数，键是**路径**）。
///
/// 键为什么是路径而不是 `LauncherApp.id`：`NSMetadataQuery` 给的就是路径，映射由
/// `LauncherUsageQuery.usageByID(for:samples:)` **一处**做——键在这一层是"文件系统身份"，
/// 出了那一处就只剩 `LauncherApp.id`（与固定项同源，§改动点设计 3 的陷阱）。
struct LauncherUsageSample: Equatable {
    let path: String
    let lastUsed: Date?
    let useCount: Int?
}

/// Spotlight 使用数据的取数（§做法 机制二 / §横切关注点「性能」「可观测性」）。
///
/// **整个类型是 `@MainActor`**（不是随手加的）：`NSMetadataQuery` 由**调用线程的 run loop**
/// 驱动——在协作线程池上 `start()` 之后它永远收集不完（`isGathering` 一直为 true），
/// 表现为"等了 3s 超时、使用数据永远为空、排序永远按名称"。主 actor 上有主 run loop 在跑，
/// 查询与 `Task.sleep` 的让出因此能正常交替推进。T2 取证时实测踩到过一次，别再摘掉。
@MainActor
enum LauncherUsageQuery {

    /// `kMDItemUseCount` 的属性名。**SDK 只导出了 `kMDItemLastUsedDate` 的常量**
    /// （`NSMetadataItemLastUsedDateKey`），使用次数只有文档里的属性名——它是一个**公开的
    /// Spotlight 元数据属性**（`mdfind "kMDItemUseCount > 0"` 可复现），不是私有 API，
    /// 因此这里写字符串字面量而不是 `kMDItem*` 常量（那个常量在 SDK 里不存在）。
    static let useCountAttribute = "kMDItemUseCount"

    /// `.app` 的内容类型（与 `mdfind "kMDItemContentType == 'com.apple.application-bundle'"` 同口径）。
    static let applicationBundleContentType = "com.apple.application-bundle"

    /// 查询的等待上限（秒）：超过就按**无使用数据**回落（固定 → 名称），绝不把首屏拖住。
    /// 本机实测三个根目录首次收集 ~20ms，3s 是给"索引正忙 / 大目录"留的余量。
    static let defaultTimeout: TimeInterval = 3

    /// 轮询间隔（秒）：等 `isGathering` 变 false。
    private static let pollInterval: TimeInterval = 0.05

    /// 在 `rootURLs` 上取 `.app` 的使用数据（**键 = 路径**）。
    ///
    /// 超时 / Spotlight 未开索引 / 一个都没收录 → 返回空表（调用方据此回落成按名称），**不抛错**。
    ///
    /// 等待方式是**轮询 `isGathering`**（每次让出主 actor 一个间隔，主 run loop 因此有机会推进查询）：
    /// 不用 `NSMetadataQueryDidFinishGathering` 观察者——观察者要么不摘（泄漏）要么要多一层
    /// 生命周期容器，而这里只需要回答"这次查询结束了没有"。
    ///
    /// 两个细节是实测出来的（本机 macOS 26）：
    /// - 必须跑在**主 actor** 上（类型级 `@MainActor`，见该注释）——否则永远等不到结果；
    /// - `isGathering` 在 `start()` 之后可能先给一帧 `false`，所以判据是"**见到 true 之后再见 false**"
    ///   （外加 `resultCount > 0` 的早退）；只看"当前是 false"会立刻返回空表，
    ///   在界面上就是"最近使用永远不生效"。
    static func fetch(
        rootURLs: [URL],
        timeout: TimeInterval = defaultTimeout
    ) async -> [String: LauncherUsageSample] {
        guard !rootURLs.isEmpty else { return [:] }

        let query = NSMetadataQuery()
        query.searchScopes = rootURLs
        query.predicate = NSPredicate(format: "kMDItemContentType == '\(applicationBundleContentType)'")
        query.valueListAttributes = [
            NSMetadataItemPathKey,
            NSMetadataItemLastUsedDateKey,
            useCountAttribute,
        ]
        guard query.start() else { return [:] }

        let deadline = Date().addingTimeInterval(max(0, timeout))
        var sawGathering = false
        while Date() < deadline {
            if query.isGathering {
                sawGathering = true
            } else if sawGathering || query.resultCount > 0 {
                break
            }
            try? await Task.sleep(for: .seconds(pollInterval))
        }

        // 先读结果再 stop：`stop()` 之后查询不再更新，结果表按"停之前的那一帧"取。
        let samples = samples(from: query)
        query.stop()
        return samples
    }

    /// 查询结果 → 样本表（键 = 路径）。取不到的属性一律留空（**不猜**）。
    private static func samples(from query: NSMetadataQuery) -> [String: LauncherUsageSample] {
        var samples: [String: LauncherUsageSample] = [:]
        for index in 0..<query.resultCount {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
            else { continue }

            samples[path] = LauncherUsageSample(
                path: path,
                lastUsed: item.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date,
                useCount: (item.value(forAttribute: useCountAttribute) as? NSNumber)?.intValue
            )
        }
        return samples
    }

    /// 样本（键 = 路径）→ 使用数据表（键 = `LauncherApp.id`，与固定项**同一个键**）。
    ///
    /// 清单里没有的路径直接忽略（已卸载 / 不在三个根目录里的 App：Spotlight 可能收录了，
    /// 但启动台不列它）；没有样本的 App 不进表（`rank` 按"无数据"处理）。
    ///
    /// **同 id 合并**：同一个 bundle id 的两份拷贝（例如 `/Applications` 与 `~/Applications`
    /// 各一份）在表里只能有一条——最近使用取更晚的一次、使用次数取更大的一个。排序只用这两项，
    /// 合并因此不改变"这个 id 有多活跃"的结论，也不会让清单里两项互相覆盖出随机顺序。
    static func usageByID(
        for apps: [LauncherApp],
        samples: [String: LauncherUsageSample]
    ) -> [String: LauncherUsage] {
        var usage: [String: LauncherUsage] = [:]
        for app in apps {
            guard let sample = samples[app.url.path] else { continue }
            let previous = usage[app.id]
            usage[app.id] = LauncherUsage(
                lastUsed: [previous?.lastUsed, sample.lastUsed].compactMap { $0 }.max(),
                useCount: [previous?.useCount, sample.useCount].compactMap { $0 }.max()
            )
        }
        return usage
    }
}

/// 取数的注入点：默认走 `LauncherUsageQuery.fetch`（真查询），单测给空表 / 构造样本
/// （用例因此不必等一次真查询，也不受本机 Spotlight 状态影响）。
typealias LauncherUsageFetcher = @MainActor (_ rootURLs: [URL]) async -> [String: LauncherUsageSample]

// MARK: - LauncherStore

/// 启动台的取数与状态：扫描（缓存）、固定项（本地数据）、使用数据（Spotlight，异步）。
///
/// 只做"拿数据 + 改数据"，**排序与过滤一律走 T1 的纯函数**（`LauncherRanking`）——
/// 视图里不另写匹配或排序逻辑，两个出口（排序 / 过滤）因此可以被单测逐字钉住。
@MainActor
final class LauncherStore: ObservableObject {

    /// 扫描结果（按路径升序；用户可见顺序由 `ranked` 定）。
    @Published private(set) var apps: [LauncherApp] = []
    /// 固定项（键 = `LauncherApp.id`）——`Defaults[.pinnedApps]` 的内存镜像。
    @Published private(set) var pinned: [String] = []
    /// 使用数据（键 = `LauncherApp.id`）。空表 = 没有 Spotlight 数据 → 排序回落成 固定 → 名称。
    @Published private(set) var usage: [String: LauncherUsage] = [:]
    /// 首次扫目录中（网格位置显示一个小转圈，避免"点进去一片空白"）。
    @Published private(set) var isScanning = false

    /// 视野里的清单：**固定 → 最近使用 → 使用次数 → 名称**（`LauncherRanking.rank`，唯一排序出口）。
    ///
    /// 每次读都现算（同 `ModuleRegistry` 的投影口径）：`apps` / `pinned` / `usage` 各自的变更
    /// 都会经 `@Published` 触发重绘，缓存反而会让三者不一致。
    var ranked: [LauncherApp] {
        LauncherRanking.rank(apps, pinned: pinned, usage: usage)
    }

    private let logger: ModuleLogger
    /// config 快照的读取（每次读盘前问一次，用户改了 `showRecents` 立刻生效）。
    private let settings: () -> LauncherSettings
    private let roots: [URL]
    private let pins: LauncherPins
    private let fetchUsage: LauncherUsageFetcher
    /// 启动后收起面板（模块侧注入的 `context.ui.requestCollapse()`；视图不碰窗口）。
    private let collapse: () -> Void

    private var hasLoaded = false
    private var hasLoadedUsage = false

    init(
        logger: ModuleLogger,
        roots: [URL] = LauncherAppScanner.defaultRoots,
        pins: LauncherPins = .live,
        settings: @escaping () -> LauncherSettings = { LauncherSettings(
            iconSize: LauncherConfigDefaults.iconSize,
            density: LauncherConfigDefaults.density,
            showRecents: LauncherConfigDefaults.showRecents
        ) },
        collapse: @escaping () -> Void = {},
        fetchUsage: LauncherUsageFetcher? = nil
    ) {
        self.logger = logger
        self.roots = roots
        self.pins = pins
        self.settings = settings
        self.collapse = collapse
        self.fetchUsage = fetchUsage ?? { await LauncherUsageQuery.fetch(rootURLs: $0) }
    }

    // MARK: 取数

    /// 模块激活时读一次**本地数据**（固定项）——不扫目录（扫目录属"首次进 tab"，见 `load()`）。
    func prepare() {
        pinned = pins.load()
    }

    /// 进 tab 时调用：首次扫目录（结果缓存在 `apps`）、之后只补使用数据。**幂等**。
    ///
    /// 顺序刻意如此（§改动点设计 4）：先让"固定 → 名称"这一版立即可渲染，再异步等 Spotlight——
    /// 查询回来的顺序变化是**重排**，不是"等它回来才画"，首屏因此不被索引拖住。
    func load() async {
        if !hasLoaded {
            hasLoaded = true
            pinned = pins.load()
            isScanning = true

            // 扫目录放到**主 actor 之外**：三个目录 + 每个 `.app` 读一次 Info.plist（本机几百个包），
            // 在展开动画里同步做完会看到一次可见的卡顿（§横切关注点「性能」）。
            let roots = self.roots
            let startedAt = Date()
            let scanned = await Task.detached(priority: .userInitiated) {
                LauncherAppScanner.scan(rootURLs: roots)
            }.value

            apps = scanned
            isScanning = false
            logger.info("扫描完成：\(apps.count) 个应用，耗时 \(Int(Date().timeIntervalSince(startedAt) * 1000))ms；固定项 \(pinned.count) 个")
        }

        await loadUsage()
    }

    /// 取 Spotlight 使用数据（**每次模块激活只取一次**：`hasLoadedUsage` 闸门）。
    ///
    /// 失败与空表都不算错误：只记一条 warning 说明"顺序回落成 固定 → 名称"，面板照常可用。
    private func loadUsage() async {
        guard !hasLoadedUsage else { return }
        hasLoadedUsage = true

        guard settings().showRecents else {
            logger.info("showRecents = false：不查 Spotlight，顺序 = 固定 → 名称")
            return
        }

        let samples = await fetchUsage(roots)
        guard !samples.isEmpty else {
            logger.warn("Spotlight 没有给出使用数据（索引未开 / 应用未收录 / 查询超时）：顺序回落成 固定 → 名称")
            return
        }

        usage = LauncherUsageQuery.usageByID(for: apps, samples: samples)
        logger.info("使用数据：\(usage.count)/\(apps.count) 个应用有记录（最近使用 \(usage.values.filter { $0.lastUsed != nil }.count) 个）")
    }

    // MARK: 动作

    /// 右键菜单：固定 / 取消固定（**先落盘再刷新**，幂等——重复调用表不变）。
    func togglePin(_ app: LauncherApp) {
        let wasPinned = LauncherPinning.isPinned(app.id, in: pinned)
        let updated = pins.toggle(app.id)
        pinned = updated   // 落盘之后才换内存值，屏幕与盘不会有一帧的分歧
        logger.info("\(wasPinned ? "取消固定" : "固定")：\(app.name)（\(app.id)），现有固定项 \(updated.count) 个")
    }

    /// 点图标：启动 App → **收起面板**（与待办 / 通知同口径：动作完成即收起，不要求用户再按一次）。
    ///
    /// - 启动走 `NSWorkspace.shared.openApplication(at:configuration:)`，`activates = true`
    ///   **显式写出**（同通知卡片的口径）：点图标的目的就是"去那个 App"，目标必须被带到前台；
    /// - **先发启动、再收起**（§处理链路的两步顺序）：不等启动完成——否则点一下要等系统往返；
    ///   完成回调只用来记失败（包已被删 / 系统拒绝时日志里留一行，不静默、也不假装成功）；
    /// - 重复点击是幂等的：`openApplication` 对已启动的 App 只是激活，不会开出第二个实例。
    func launch(_ app: LauncherApp) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        logger.info("启动：\(app.name)（\(app.id)）")
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { [logger] _, error in
            if let error {
                logger.warn("启动失败：\(app.name)（\(app.url.path)）：\(String(describing: error))")
            }
        }
        collapse()
    }
}

// MARK: - 图标缓存

/// 应用图标的**惰性缓存**（§改动点设计 2 的陷阱：不要在主线程为几百个应用同步取图标）。
///
/// 取图标的唯一时机是"一个格子真的要画出来"（`LazyVGrid` 只为可见行建视图），取过的按 `.app`
/// **路径**缓存（图标是文件级的东西，同一个包的两份拷贝本来就该有两张图）；换搜索词、重排、
/// 重进 tab 都不再读盘。缓存挂在**模块**上（不是视图上）：面板每次重构视图，视图持有的缓存等于没有。
@MainActor
final class LauncherIconCache {
    private var images: [String: NSImage] = [:]

    /// 某个 `.app` 的图标（同路径只读一次）。
    func icon(for app: LauncherApp) -> NSImage {
        if let cached = images[app.url.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: app.url.path)
        images[app.url.path] = image
        return image
    }

    /// 已缓存的张数（只给用例与排查读；生产路径不需要）。
    var cachedCount: Int { images.count }
}

// MARK: - 网格尺寸口径（纯函数）

/// 网格的**尺寸口径**（纯值：由 `iconSize` / `density` 算出视图要用的尺寸）。
///
/// 夹取在这里做（同 `notificationHUDScale` 的口径）：用户直接改 UserDefaults 写了 3 或 -1
/// 也要有确定的呈现，不在一处除以零、另一处画出一个 300pt 的图标。
struct LauncherGridMetrics: Equatable {
    /// `GridItem(.adaptive(minimum:))` 的最小格子宽（列数由面板宽度自适应该值）。
    let minimumItemWidth: CGFloat
    /// 格子间距（列间距 = 行间距）。
    let itemSpacing: CGFloat
    /// 图标边长。
    let iconSide: CGFloat
    /// 名称字号（小图标配小字，避免名称与相邻格子挤在一起）。
    let labelFontSize: CGFloat

    /// `iconSize` 的合法区间（pt）：比 28 还小图标认不出、比 96 还大一屏放不下几列。
    static let iconSizeRange: ClosedRange<Double> = 28...96
    /// `density` 的合法区间（间距倍率）：0.6 = 紧凑、1.6 = 宽松。
    static let densityRange: ClosedRange<Double> = 0.6...1.6
    /// 基准间距（`density = 1` 时的格距，pt）。
    static let baseSpacing: CGFloat = 10
    /// 图标两侧留给名称的余量（算进最小格子宽：名称再长也由 `.tail` 截断收）。
    static let labelMargin: CGFloat = 12

    /// `iconSize` / `density` → 视图尺寸（两项都先夹取到合法区间）。
    static func metrics(iconSize: Double, density: Double) -> LauncherGridMetrics {
        let side = iconSize.clamped(to: iconSizeRange)
        let scale = density.clamped(to: densityRange)
        return LauncherGridMetrics(
            minimumItemWidth: CGFloat(side) + labelMargin,
            itemSpacing: baseSpacing * CGFloat(scale),
            iconSide: CGFloat(side),
            labelFontSize: side >= 40 ? 10 : 9
        )
    }
}

private extension Comparable {
    /// 夹取到区间（越界值取端点；同 `notificationHUDScale` / `hudTTLRange` 的口径）。
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - LauncherModule

/// 启动台模块（`docs/19`；`docs/14` 的 `launcher` 行）。
///
/// 本批只声明 `expanded`（D-02）：展开面板多一个「启动台」tab，折叠态与首页**一行不加**。
@MainActor
final class LauncherModule: GourdModule {
    /// 静态元数据（docs/19 §接口与数据形状 4 逐条对应）。
    ///
    /// - `surfaces: [.expanded]`：**只声明展开 tab**——折叠态左右槽位未落地、用户没要求首页块，
    ///   声明它们会与待办抢中央槽位 / 让首页再多一块；
    /// - `defaultPlacement: nil`：placement 只在含 `compact` 时有意义，本批不声明 `compact`，
    ///   因此不给值（tab 顺序随之取 `Int.max`，排在既有 tab 之后）；
    /// - `defaultEnabled: false`：新增模块一律默认关（docs/14 T-12 / D-04），用户在「组件」里显式打开；
    /// - `permissions: []`：零权限（扫公开应用目录 + 公开的启动接口，不新增 TCC）。
    static let manifest = ModuleManifest(
        manifestVersion: 1,
        id: "com.cmeng.gourd.launcher",
        name: LocalizedText(key: "module.launcher.name"),
        summary: LocalizedText(key: "module.launcher.summary"),
        icon: IconSpec(type: "symbol", name: "square.grid.2x2"),
        version: "1.0.0",
        apiVersion: HostInfo.currentAPIVersion,
        kind: "builtin",
        surfaces: [.expanded],
        defaultPlacement: nil,
        defaultEnabled: false,
        permissions: [],
        config: ConfigSchema(
            type: "object",
            properties: [
                // 格子目标宽度（pt）。视图侧夹取到 28…96（`LauncherGridMetrics.iconSizeRange`）
                "iconSize": ConfigNode(
                    type: "number",
                    title: nil,
                    default: .double(LauncherConfigDefaults.iconSize),
                    values: nil,
                    itemType: nil
                ),
                // 格子间距倍率。视图侧夹取到 0.6…1.6（`LauncherGridMetrics.densityRange`）
                "density": ConfigNode(
                    type: "number",
                    title: nil,
                    default: .double(LauncherConfigDefaults.density),
                    values: nil,
                    itemType: nil
                ),
                // 是否用 Spotlight 的使用数据排序；关掉 = 固定 → 名称（固定项恒优先，不受它影响）
                "showRecents": ConfigNode(
                    type: "boolean",
                    title: nil,
                    default: .bool(LauncherConfigDefaults.showRecents),
                    values: nil,
                    itemType: nil
                ),
            ]
        )
    )

    private let context: ModuleContext
    private let store: LauncherStore
    /// 图标缓存在**模块**上（见 `LauncherIconCache` 的注释：视图每次重构，缓存不能挂在视图上）。
    private let iconCache = LauncherIconCache()

    init(context: ModuleContext) {
        self.context = context
        let config = context.config
        self.store = LauncherStore(
            logger: context.logger,
            roots: LauncherAppScanner.defaultRoots,
            pins: .live,
            settings: { LauncherSettings.read(from: config) },
            collapse: { context.ui.requestCollapse() },
            fetchUsage: { await LauncherUsageQuery.fetch(rootURLs: $0) }
        )
    }

    /// 读一次本地数据（固定项）+ 记一条启动日志。**不扫目录、不查 Spotlight、不请求权限**——
    /// 那三件事都属于"用户真的要打开启动台"（首次进 tab），激活本身要轻。
    func activate() async throws {
        store.prepare()
        context.logger.info(
            "launcher 模块已激活（固定项 \(store.pinned.count) 个；根目录 \(LauncherAppScanner.defaultRoots.map(\.path).joined(separator: ", "))）"
        )
    }

    /// 没有常驻副作用（不订阅通知、不起定时器），所以没有要收的东西。
    func deactivate() async {}

    /// 只答 `expanded`：`.compact` / `.lockscreen` / `.home` 一律 `.none`（不占位、不算失败）。
    ///
    /// 这三条**不是**"暂时没实现"——是本批的契约（D-02 / 控制器裁决 1）：折叠槽位与首页块
    /// 本批不占，改动前先读文件头口径 1。
    func content(for request: ContentRequest) -> ModuleContent {
        switch request.surface {
        case .expanded:
            return .view(AnyView(LauncherModuleView(
                store: store,
                icons: iconCache,
                settings: LauncherSettings.read(from: context.config)
            )))
        case .compact, .lockscreen, .home:
            return .none
        }
    }
}

// MARK: - 展开面板视图（搜索框 + 应用网格）

/// 展开面板的启动台（本批唯一的 surface）：**顶部搜索框 + 应用网格**。
///
/// 三件事各归各处，视图这一层只做呈现：
/// - 取数与状态（扫描缓存 / 固定项 / 使用数据）在 `LauncherStore`；
/// - 排序与过滤是 T1 的纯函数（`LauncherRanking.rank` / `.filter`）——视图里**不另写**
///   匹配或排序逻辑（否则"搜索命中的顺序"与"网格的顺序"会变成两套口径）；
/// - 图标在 `LauncherIconCache`（按可见项惰性取 + 缓存）。
///
/// 搜索词是 **UI 局部 `@State`**（不进 Defaults）：面板重开 = 干净的一屏。
private struct LauncherModuleView: View {
    @ObservedObject var store: LauncherStore
    let icons: LauncherIconCache
    let settings: LauncherSettings

    @State private var query = ""

    private var metrics: LauncherGridMetrics {
        LauncherGridMetrics.metrics(iconSize: settings.iconSize, density: settings.density)
    }

    /// 视野里的清单：先 `ranked`（固定 → 最近 → 次数 → 名称），再过搜索。
    private var visibleApps: [LauncherApp] {
        LauncherRanking.filter(store.ranked, query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LauncherSearchField(query: $query)

            Group {
                if store.isScanning {
                    LauncherPlaceholder(kind: .loading)
                } else if store.apps.isEmpty {
                    LauncherPlaceholder(kind: .noApps)
                } else if visibleApps.isEmpty {
                    LauncherPlaceholder(kind: .noMatch)
                } else {
                    grid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 每次进 tab 都调一次：首次扫目录 + 查使用数据，之后走缓存（幂等，见 `LauncherStore.load`）。
        .task { await store.load() }
    }

    /// 应用网格：列数按面板宽度**自适应**（`GridItem(.adaptive(minimum:))`），
    /// 最小格子宽与间距由 `iconSize` / `density` 决定。
    ///
    /// 用 `LazyVGrid`（不是 `VGrid`）：只有可见的行会被建出来，`icons.icon(for:)` 于是
    /// 只对**真的要画**的格子读盘——"进 tab 为几百个应用取一遍图标"就卡在这一层。
    private var grid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: metrics.minimumItemWidth), spacing: metrics.itemSpacing)],
                spacing: metrics.itemSpacing
            ) {
                ForEach(visibleApps) { app in
                    LauncherGridCell(
                        app: app,
                        icon: icons.icon(for: app),
                        metrics: metrics,
                        isPinned: LauncherPinning.isPinned(app.id, in: store.pinned),
                        onLaunch: { store.launch(app) },
                        onTogglePin: { store.togglePin(app) }
                    )
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// 顶部搜索框：放大镜 + 输入框 + 清除按钮（有内容时才出现）。
private struct LauncherSearchField: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))

            TextField(LocalizedStringKey("module.launcher.searchPlaceholder"), text: $query)
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
    }
}

/// 网格里的一个格子：**图标 + 名称**，点一下启动；右键固定 / 取消固定。
///
/// 图标由调用方（网格）按需取好传进来（见 `LauncherIconCache`）；固定项右上角一枚小图钉
/// （"哪些是固定的"要一眼能看出来，否则右键菜单里的状态是唯一的线索）。
private struct LauncherGridCell: View {
    let app: LauncherApp
    let icon: NSImage
    let metrics: LauncherGridMetrics
    let isPinned: Bool
    let onLaunch: () -> Void
    let onTogglePin: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onLaunch) {
            VStack(spacing: 4) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: metrics.iconSide, height: metrics.iconSide)
                    .overlay(alignment: .topTrailing) {
                        if isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 7, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(3)
                                .background(Circle().fill(.black.opacity(0.6)))
                                .offset(x: 2, y: -2)
                        }
                    }

                Text(app.name)
                    .font(.system(size: metrics.labelFontSize))
                    .foregroundStyle(.white.opacity(isHovered ? 1 : 0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(isHovered ? 0.09 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(app.name)   // 名称被截断时，悬停给全名
        .contextMenu {
            Button(action: onTogglePin) {
                Text(LocalizedStringKey(isPinned ? "module.launcher.unpin" : "module.launcher.pin"))
            }
        }
    }
}

/// 空态 / 加载态的占位。**不在这里引导授权，也不做"重试"按钮**：扫描失败（三个目录都读不到）
/// 与"这台机器上就是没有 .app"在界面上是同一件事——一句说明，不弹窗、不报错。
private struct LauncherPlaceholder: View {
    enum Kind {
        /// 首次扫目录中（面板刚打开的那一瞬）。
        case loading
        /// 扫完了但一个应用都没有（三个根都不存在 / 都读不到）。
        case noApps
        /// 有应用，但搜索词一个都没命中。
        case noMatch
    }

    let kind: Kind

    var body: some View {
        VStack(spacing: 8) {
            if kind == .loading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: kind == .noApps ? "square.grid.2x2" : "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Text(LocalizedStringKey(labelKey))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var labelKey: String {
        switch kind {
        case .loading: return "module.launcher.loading"
        case .noApps: return "module.launcher.empty"
        case .noMatch: return "module.launcher.noMatch"
        }
    }
}
