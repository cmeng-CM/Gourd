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
//  - 排序接入：先按名称（空 `usage`）立即渲染，Spotlight 回来再重排 = §改动点设计 4；
//  - 两区（p7 / T5，docs/31-home-workday-launcher.md §接口与数据形状 2/6）：上区「快捷启动」=
//    固定项（顺序 = **固定先后**，`LauncherPartition.split` 现算），下区 = 排名剔除固定项后过搜索；
//    拖上 = 固定、拖下 = 取消固定，与右键菜单**共用 `LauncherPins` 唯一接缝**（先落盘再刷新、幂等）。
//
//  文案走 Localizable key（06 §3.3 R5）：`module.launcher.name` / `.summary` /
//  `.searchPlaceholder` / `.pin` / `.unpin` / `.empty` / `.noMatch` / `.quickLaunch` /
//  `.quickLaunchHint`。
//  **颜色**：面板是黑底、系统外观可为浅色——本模块内所有文字与图标一律显式浅色
//  （`Color.white` / `.white.opacity(...)`），不用 `.primary` / `.secondary`（同 ProgressModule 的教训）。
//

import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

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
/// 取快照的时机：`iconSize` / `density` 是**每次 `content(for: .expanded)`** 现读现用——
/// 用户改了值，下一次进 tab（或任何一次重绘）就是新尺寸，不需要重启；
/// 但 `showRecents` **不是**同一档：它只在模块激活后的**第一次取数**被读一次
///（`LauncherStore.loadUsage` 的 `hasLoadedUsage` 闸门：一次激活只查一次 Spotlight），
/// 因此 **false → true 要关了再开模块（或重启应用）才生效**，改动时别把这两档混为一谈。
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

    /// `kMDItemPath` 的属性名（SDK 导出的常量，不抄字面量）。
    nonisolated static let pathAttribute = NSMetadataItemPathKey

    /// `kMDItemLastUsedDate` 的属性名（同上，SDK 导出）。
    nonisolated static let lastUsedAttribute = NSMetadataItemLastUsedDateKey

    /// `kMDItemUseCount` 的属性名。**SDK 只导出了 `kMDItemLastUsedDate` 的常量**
    /// （`NSMetadataItemLastUsedDateKey`），使用次数只有文档里的属性名——它是一个**公开的
    /// Spotlight 元数据属性**（`mdfind "kMDItemUseCount > 0"` 可复现），不是私有 API，
    /// 因此这里写字符串字面量而不是 `kMDItem*` 常量（那个常量在 SDK 里不存在）。
    nonisolated static let useCountAttribute = "kMDItemUseCount"

    /// `.app` 的内容类型（与 `mdfind "kMDItemContentType == 'com.apple.application-bundle'"` 同口径）。
    nonisolated static let applicationBundleContentType = "com.apple.application-bundle"

    /// 查询的等待上限（秒）：超过就按**无使用数据**回落（固定 → 名称），绝不把首屏拖住。
    /// 本机实测三个根目录首次收集 ~20ms，3s 是给"索引正忙 / 大目录"留的余量。
    nonisolated static let defaultTimeout: TimeInterval = 3

    /// 轮询间隔（秒）：等 `isGathering` 变 false。
    private static let pollInterval: TimeInterval = 0.05

    /// 一条 Spotlight 结果的**属性读数接缝**：给属性名，给值（`nil` = 这条结果没有该属性）。
    ///
    /// 抽这个接缝的理由是**可测性**：映射逻辑（含三个属性名常量）与 `NSMetadataQuery` 之间
    /// 只隔着这一个闭包，于是"属性名写错 / 取值类型变了"能被构造的数据钉住，而不是靠
    /// 一次真查询碰运气（真查询在没开索引的机器上照样返回空表，属性名写错会**静默**降级成
    /// "按名称排序"，套件全绿）。真实实现只有一行，见 `samples(from:)`。
    nonisolated static func sample(attribute: (String) -> Any?) -> LauncherUsageSample? {
        // 没有路径 = 这条结果用不上（路径同时是清单与使用数据之间的唯一桥梁）。
        guard let path = attribute(pathAttribute) as? String else { return nil }

        return LauncherUsageSample(
            path: path,
            lastUsed: attribute(lastUsedAttribute) as? Date,
            useCount: useCount(from: attribute(useCountAttribute))
        )
    }

    /// `kMDItemUseCount` 的读数 → `Int?`：`NSNumber` 与数字字符串两种形态都认，
    /// 其余（nil / 非数字字符串 / 别的类型）一律当**无数据**处理——不崩、不猜、不写成 0
    /// （0 与"没有这个属性"在排序里是两件事）。
    nonisolated static func useCount(from value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String {
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

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
            pathAttribute,
            lastUsedAttribute,
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

    /// 查询结果 → 样本表（键 = 路径）。
    ///
    /// 这里只剩"把 `NSMetadataItem` 变成属性读数接缝"这一件事，映射本身在 `sample(attribute:)`
    /// （纯函数，用例直接钉）。没有路径的结果直接跳过。
    private static func samples(from query: NSMetadataQuery) -> [String: LauncherUsageSample] {
        var samples: [String: LauncherUsageSample] = [:]
        for index in 0..<query.resultCount {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let sample = sample(attribute: { item.value(forAttribute: $0) })
            else { continue }
            samples[sample.path] = sample
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

/// 启动一个 App 的注入点（参数 = `.app` 的 URL）。默认实现走 `NSWorkspace`（见 `LauncherStore.init`）；
/// 单测注入记录型假体，于是"点图标 → 启动 → 收起"这条链路可以被断言，
/// 而不必在用例里真的拉起一个 App。
typealias LauncherAppOpener = @MainActor (_ appURL: URL) -> Void

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

    /// **`apps` 的首轮扫描是否已完成**（p6-ui-polish / T7 机制五的就绪门判据）。
    ///
    /// 与 `hasLoaded`（"扫过一次"）**不是一回事**：`hasLoaded` 在扫描**开始前**就置位（那是"只扫一次"
    /// 的闸门），本标记只在 `apps` 真的落地之后才置位。
    ///
    /// 用处只有一个：**探针的就绪门**——首轮扫描完成前页面上是 loading / 空态占位，那不是这一页的
    /// 自然高（进了高度账本 = 首开「先塌陷再长高」三拍，T7 的失败信号）。故意**不是** `@Published`：
    /// 唯一读者是就绪门闭包（`LauncherModule.hasLoadedApps`），而 `apps` 落地本来就会让视图重绘
    /// （探针在那一帧重新上报），不需要第二声通知。
    private(set) var hasLoadedApps = false

    /// 视野里的清单：**固定 → 最近使用 → 使用次数 → 名称**（`LauncherRanking.rank`，唯一排序出口）。
    ///
    /// 每次读都现算（同 `ModuleRegistry` 的投影口径）：`apps` / `pinned` / `usage` 各自的变更
    /// 都会经 `@Published` 触发重绘，缓存反而会让三者不一致。
    var ranked: [LauncherApp] {
        LauncherRanking.rank(apps, pinned: pinned, usage: usage)
    }

    /// 上区「快捷启动」：固定项，顺序 = **固定先后**（`pinnedApps` 表序）；本次扫描里不存在的
    /// 固定 id 由 `split` 丢掉。上区**不受搜索影响**（搜索是找未固定应用的主路径，D-15）。
    var quickApps: [LauncherApp] { partition.quick }

    /// 下区网格：`ranked` 剔除固定项后**保序**。视图再对它过 `LauncherRanking.filter` 接搜索。
    var gridApps: [LauncherApp] { partition.grid }

    /// 两区 = `LauncherPartition.split` 的现算结果（与 `ranked` 同一条「每次读现算」的口径：
    /// `apps` / `pinned` / `usage` 各自变更都会经 `@Published` 重绘，缓存反而要引失效逻辑）。
    private var partition: (quick: [LauncherApp], grid: [LauncherApp]) {
        LauncherPartition.split(ranked: ranked, pinnedIDs: pinned)
    }

    private let logger: ModuleLogger
    /// config 快照的读取。`iconSize` / `density` 是"每次取内容现读现用"，`showRecents` 另有一道闸门
    /// （见 `LauncherSettings` 的注释与 `loadUsage()`）。
    private let settings: () -> LauncherSettings
    private let roots: [URL]
    private let pins: LauncherPins
    private let fetchUsage: LauncherUsageFetcher
    /// 启动一个 App（默认走 `NSWorkspace`；注入点见 `LauncherAppOpener`）。
    private let openApp: LauncherAppOpener
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
        openApp: LauncherAppOpener? = nil,
        fetchUsage: LauncherUsageFetcher? = nil
    ) {
        self.logger = logger
        self.roots = roots
        self.pins = pins
        self.settings = settings
        self.collapse = collapse
        self.openApp = openApp ?? { [logger] appURL in
            // 生产实现（唯一一处 `NSWorkspace` 启动调用）：`activates = true` **显式写出**
            //（同通知卡片的口径）：点图标的目的就是"去那个 App"，目标必须被带到前台。
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                if let error {
                    logger.warn("启动失败：\(appURL.path)：\(String(describing: error))")
                }
            }
        }
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
            // 就绪门开（T7 机制五）：这一刻起页面上才是**这一页的内容**（网格 / 真实的空态），
            // 探针的量值才允许进高度账本。空目录同样算"已就绪"——那确实是这一页的高。
            hasLoadedApps = true
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

    /// 固定（拖到上区落这里）：走 `pins.pin` **先落盘再刷新**，幂等（重复固定表不变、不写盘）
    /// ——与 `togglePin` 同一口径，两个入口共用 `LauncherPins` 这条接缝。
    func pin(_ app: LauncherApp) {
        let updated = pins.pin(app.id)
        pinned = updated
        logger.info("固定：\(app.name)（\(app.id)），现有固定项 \(updated.count) 个")
    }

    /// 取消固定（拖到下区落这里）：同上，`pins.unpin` 幂等（重复取消不写盘）。
    func unpin(_ app: LauncherApp) {
        let updated = pins.unpin(app.id)
        pinned = updated
        logger.info("取消固定：\(app.name)（\(app.id)），现有固定项 \(updated.count) 个")
    }

    /// 点图标：启动 App → **收起面板**（与待办 / 通知同口径：动作完成即收起，不要求用户再按一次）。
    ///
    /// - 启动走注入的 `openApp`（默认实现 = `NSWorkspace.shared.openApplication(at:configuration:)`，
    ///   `activates = true` **显式写出**，同通知卡片的口径）：点图标的目的就是"去那个 App"，
    ///   目标必须被带到前台；
    /// - **先发启动、再收起**（§处理链路的两步顺序）：不等启动完成——否则点一下要等系统往返；
    ///   完成回调只用来记失败（包已被删 / 系统拒绝时日志里留一行，不静默、也不假装成功）；
    /// - 重复点击是幂等的：`openApplication` 对已启动的 App 只是激活，不会开出第二个实例。
    ///
    /// 两步各自的执行体都是**注入点**（`openApp` / `collapse`），因此这条链路可以被用例逐字断言：
    /// 打开的是哪一项的 URL、各调用了几次、先后顺序（见 `testLauncherLaunchOpensAppThenCollapses`）。
    func launch(_ app: LauncherApp) {
        logger.info("启动：\(app.name)（\(app.id)）")
        openApp(app.url)
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

    /// **就绪门的判据**（p6-ui-polish / T7 机制五）：`apps` 首轮扫描完成前，展开页上的量值
    /// （loading / 空态占位的高）不进高度账本。宿主把它接进 `PanelContentHeight.isTabReportReady`
    /// ——本模块不碰账本本身，只回答"我这页此刻有没有可量的内容"。
    var hasLoadedApps: Bool { store.hasLoadedApps }

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

// MARK: - 展开面板视图（搜索框 + 上区快捷启动 + 下区应用网格）

/// 展开面板的启动台（本批唯一的 surface）：**顶部搜索框 + 上下两区**（p7 / T5）。
///
/// - **上区「快捷启动」**：固定项（顺序 = 固定先后），小标题 + 网格或空态虚线提示格；
///   常驻、**不受搜索影响**（上区是「固定」语义，D-15）；是拖放的接收容器 → `store.pin`。
/// - **下区**：现有应用网格，数据源 = `LauncherRanking.filter(store.gridApps, query:)`
///   （排名剔除固定项后再过搜索）；搜索无命中**只替换这一区**；同样是拖放接收容器 → `store.unpin`。
/// - `isScanning` / `apps.isEmpty` 走既有整页占位、**不画上区**（扫不到应用时提示格是空承诺）。
///
/// 三件事各归各处，视图这一层只做呈现：
/// - 取数与状态（扫描缓存 / 固定项 / 使用数据）在 `LauncherStore`；
/// - 排序与过滤是 T1 的纯函数（`LauncherRanking.rank` / `.filter`），分区与拖放判定是 T4 的纯函数
///   （`LauncherPartition.split` / `LauncherQuickDrop.resolve`）——视图里**不另写**匹配、排序或
///   拖放判定逻辑（否则"拖下去的落点"与"屏幕上看到的区"会变成两套口径）；
/// - 图标在 `LauncherIconCache`（按可见项惰性取 + 缓存）。
///
/// 搜索词是 **UI 局部 `@State`**（不进 Defaults）：面板重开 = 干净的一屏。
private struct LauncherModuleView: View {
    @ObservedObject var store: LauncherStore
    let icons: LauncherIconCache
    let settings: LauncherSettings
    /// 面板级状态：拖拽期间的自动收起抑制令牌经它下发（模块内视图读 vm 的先例：
    /// `DynamicIslandCalendar` 的 `WheelPicker`；环境由面板根视图注入，缺失会崩——上屏验过）。
    @EnvironmentObject private var vm: DynamicIslandViewModel

    @State private var query = ""
    /// 上区是不是拖拽会话当前悬停的目标（上区高亮的唯一来源）。
    @State private var isQuickTargeted = false
    /// 面板内拖拽的**自动收起抑制令牌**（挂载见 `dragItem(for:)`，释放见 `endDragSuppression`）。
    @State private var dragSuppressionToken: UUID?
    /// 抑制看门狗的**代数**（每次起拖自增；看门狗只在「自己仍是最新那一代」时才有权释放）。
    @State private var dragSuppressionGeneration = 0

    /// 抑制看门狗时限（秒）。取舍同 `ClipboardManager.dragSafetyResetTimeout` 那段注释：
    /// 「`onDrag` 没有拖拽结束回调」时用一次有界延时兜底——短了会在慢拖中提前放掉抑制，
    /// 长了会在落点丢失时白挂抑制；30 秒只服务于「拖拽已经不可能再落下」的兜底，
    /// 正常路径（drop / 面板收起 / 视图消失）都是立即释放。
    private static let dragSuppressionWatchdogTimeout: TimeInterval = 30

    private var metrics: LauncherGridMetrics {
        LauncherGridMetrics.metrics(iconSize: settings.iconSize, density: settings.density)
    }

    /// 搜索词去掉空白后是不是空的（与 `LauncherRanking.filter` 的「空查询」同一口径：
    /// 决定下区空位里摆不摆 `noMatch` 那句提示，见 `gridSection`）。
    private var hasSearchKeyword: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 下区的内容：排名剔除固定项后，再过搜索（上区不受搜索影响，见 `quickSection`）。
    private var visibleGridApps: [LauncherApp] {
        LauncherRanking.filter(store.gridApps, query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LauncherSearchField(query: $query)

            if store.isScanning {
                LauncherPlaceholder(kind: .loading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.apps.isEmpty {
                // 扫不到应用时不画上区：提示格会是一句空承诺（docs/31 §接口 6 的占位态口径）。
                LauncherPlaceholder(kind: .noApps)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                quickSection

                // 两区之间的细分隔线（0.08 白、1pt 高）。
                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)

                gridSection
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 每次进 tab 都调一次：首次扫目录 + 查使用数据，之后走缓存（幂等，见 `LauncherStore.load`）。
        .task { await store.load() }
        // 泄漏护栏（`onDrag` 没有「取消」回调）：拖拽一旦拖出面板、松手落在面板外，`onDrop`
        // 不会来——面板收起与视图消失这两个「拖拽已经不可能再落下」的时刻兜底释放抑制。
        // 第三道是有界看门狗（起拖时武装，见 `dragItem(for:)`）：落点被别的 drop 目标吃掉
        // 这类「没人通知我们」的会话靠它兜底。
        .onChange(of: vm.notchState) { _, state in
            if state == .closed { endDragSuppression() }
        }
        .onDisappear { endDragSuppression() }
    }

    // MARK: 上区（快捷启动）

    /// 上区：小标题「快捷启动」+ 固定项网格（与下区**同一 `metrics`**：列宽 / 间距逐字一致）。
    ///
    /// 空时一枚虚线提示格（「将应用拖到这里固定」）——拖拽的可发现性全靠它。整区是拖放接收容器：
    /// 拖拽会话悬停时叠一层 0.06 白高亮（`isTargeted`），落点判定交给 `LauncherQuickDrop.resolve`。
    private var quickSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey("module.launcher.quickLaunch"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))

            if store.quickApps.isEmpty {
                quickHintCell
            } else {
                LazyVGrid(
                    columns: adaptiveColumns,
                    spacing: metrics.itemSpacing
                ) {
                    ForEach(store.quickApps) { app in
                        LauncherGridCell(
                            app: app,
                            icon: icons.icon(for: app),
                            metrics: metrics,
                            isPinned: LauncherPinning.isPinned(app.id, in: store.pinned),
                            dragItem: { dragItem(for: app) },
                            onLaunch: { store.launch(app) },
                            onTogglePin: { store.togglePin(app) }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onDrop(of: [.utf8PlainText], isTargeted: $isQuickTargeted) { providers in
            handleDrop(providers, target: .quick)
        }
        .overlay {
            if isQuickTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white.opacity(0.06))
                    .allowsHitTesting(false)
            }
        }
    }

    /// 空态提示格：虚线圆角框 + 居中文案，高度 ≈ 一格（图标 + 名称 + 上下留白）。
    ///
    /// 宽度取整区（不是一格宽）：9 字文案在一格宽里会折成三行、虚线框的可发现性也弱；
    /// 文档只钉了「高度与一格同高」（docs/31 §接口 6）。
    private var quickHintCell: some View {
        Text(LocalizedStringKey("module.launcher.quickLaunchHint"))
            .font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.4))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: quickHintHeight)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.white.opacity(0.18))
            )
    }

    /// 提示格的高度：图标边长 + 名称行 + 上下留白（≈ `LauncherGridCell` 的竖直堆叠高度）。
    private var quickHintHeight: CGFloat { metrics.iconSide + 26 }

    /// 两区共用的列定义（**同一份**：列宽 / 间距逐字一致——上区格子与下区格子不许有尺寸差）。
    private var adaptiveColumns: [GridItem] {
        [GridItem(.adaptive(minimum: metrics.minimumItemWidth), spacing: metrics.itemSpacing)]
    }

    // MARK: 下区（应用网格）

    /// 下区：网格；搜索无命中时**只**替换这一区（上区常驻）。
    ///
    /// 下区整块是拖放接收容器（拖到下区 = 取消固定）。数据源是 `store.gridApps` 过搜索后的结果。
    private var gridSection: some View {
        Group {
            if visibleGridApps.isEmpty {
                if hasSearchKeyword {
                    LauncherPlaceholder(kind: .noMatch)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // 全部应用都已固定到上区：下区没有内容可放——这不是「搜索无命中」，
                    // 不摆那句提示（上区已经把它们全画出来了）。
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                grid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onDrop(of: [.utf8PlainText], isTargeted: nil) { providers in
            handleDrop(providers, target: .grid)
        }
    }

    /// 应用网格：列数按面板宽度**自适应**（`GridItem(.adaptive(minimum:))`），
    /// 最小格子宽与间距由 `iconSize` / `density` 决定。
    ///
    /// 用 `LazyVGrid`（不是 `VGrid`）：只有可见的行会被建出来，`icons.icon(for:)` 于是
    /// 只对**真的要画**的格子读盘——"进 tab 为几百个应用取一遍图标"就卡在这一层。
    private var grid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: adaptiveColumns,
                spacing: metrics.itemSpacing
            ) {
                ForEach(visibleGridApps) { app in
                    LauncherGridCell(
                        app: app,
                        icon: icons.icon(for: app),
                        metrics: metrics,
                        isPinned: LauncherPinning.isPinned(app.id, in: store.pinned),
                        dragItem: { dragItem(for: app) },
                        onLaunch: { store.launch(app) },
                        onTogglePin: { store.togglePin(app) }
                    )
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: 拖放（上区 / 下区共用收口）

    /// 起拖：交出载体（应用 id 的纯文本），并在**第一次**起拖时挂上自动收起抑制令牌。
    ///
    /// **为什么要抑制**：面板背景有一块铺满面板的 `dragDetector`（`ContentView.swift` 的
    /// `dragDetector`），任何拖拽悬停到面板都会让它 `isTargeted` 进出一次；它 `!isTargeted` 那一支
    /// 会按常规收起面板（`shouldPreventAutoClose()` 不认识「面板内应用拖拽」）。于是拖拽从格子出发、
    /// 穿过分隔线 / 标题 / 边距这类**非投放区**再进投放区的一瞬间，面板就会收起，两区的 `onDrop`
    /// 永远等不到抬手。`setAutoCloseSuppression` 是架子（`ShelfView`）与剪贴板页的既有解法、
    /// 也是面板内唯一的「拖拽正在发生」信号源——令牌一挂，「离开投放区」不再被当成收起信号。
    /// 起拖时**每次**都自增代数并重新武装看门狗（旧看门狗随即作废），令牌只在第一次真正挂。
    private func dragItem(for app: LauncherApp) -> NSItemProvider {
        dragSuppressionGeneration += 1
        let generation = dragSuppressionGeneration

        if dragSuppressionToken == nil {
            let token = UUID()
            dragSuppressionToken = token
            vm.setAutoCloseSuppression(true, token: token)
        }

        // 有界看门狗（先例：`ClipboardManager.markDragStart`）：拖拽在面板外结束、或落点被
        // 别的 drop 目标（例如面板的 dragDetector，`{ _ in true }`）吃掉时，「拖拽已经结束」
        // 没有任何回调能通知本视图——代数仍是最新且令牌仍活跃才释放，正常 drop 早已把两者
        // 清掉，旧看门狗因此自动作废（不会误释放下一次拖拽的抑制）。
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dragSuppressionWatchdogTimeout) {
            guard generation == dragSuppressionGeneration, dragSuppressionToken != nil else { return }
            endDragSuppression()
        }
        return NSItemProvider(object: app.id as NSString)
    }

    /// 释放抑制（幂等）。挂四处：**drop 处理**（拖拽在面板内结束）、**面板收起**
    /// （`onChange(of: vm.notchState)`）、**视图消失**（`onDisappear`）与**看门狗超时**——
    /// `onDrag` 没有「拖拽取消」回调，后两处（超时 + 护栏）是「没人通知我们」那些会话的兜底，
    /// 否则令牌会一直挂着（抑制泄漏＝面板此后不自动收起）。
    ///
    /// **释放后若面板仍开着，补一次悬停复核**（`vm.shouldRecheckHover.toggle()`）——与架子
    /// 拖动收尾的同源解法（`ShelfItemView.swift` 的 `onDragEnded`，注释原文 "the hover-exit that
    /// would have closed it already came and went, so ask for a fresh evaluation"）。原因：
    /// 拖拽期间 `finishHoverExit` 已把面板的 `isHovering` 置 false、只因本令牌压制而没有收面板，
    /// 此后面板的轮询不再复查（`ContentView.swift` 的 `hiddenEdgeHoverPolling` 只在 `isHovering`
    /// 为真那一支看）——不补这一次，拖拽在面板外结束 / 被别的 drop 目标吃掉 / 看门狗兜底释放后，
    /// 面板会一直站着直到下一次悬停进出，而不是「按正常判据收起」。复核用的是**现行判据**
    /// （`isHovering` 与 `shouldPreventAutoClose()`）：仍判为在悬停就不收（面板留在原地让用户
    /// 看到结果），已离开才按正常悬停退出收起。
    /// 顺序要紧：先释放令牌，复核里的 `shouldPreventAutoClose()` 才不再被本令牌挡下。
    private func endDragSuppression() {
        guard let token = dragSuppressionToken else { return }
        vm.setAutoCloseSuppression(false, token: token)
        dragSuppressionToken = nil
        if vm.notchState == .open {
            vm.shouldRecheckHover.toggle()
        }
    }

    /// 拖拽落下的共同收口（两个区域的 `onDrop` 都调它）：先问 `LauncherQuickDrop.resolve`
    /// （**纯函数**，落点判定不在视图里），非 nil 才按区走 `store.pin` / `store.unpin`
    /// ——落盘在 store 里、经 `LauncherPins` 唯一接缝。
    ///
    /// 载体是应用 id 的纯文本（`NSItemProvider(object: NSString)`，见 `LauncherGridCell.onDrag`）；
    /// 未知 id（含 Finder 等外来文本）与反向拖（上区收到已固定、下区收到未固定）都由 `resolve`
    /// 判成 nil → no-op，不落盘、不刷新。
    ///
    /// 两件事在**函数第一行**做完、都在异步解析之前：
    /// - `defer { endDragSuppression() }`：`onDrop` 被调到就是「面板收到了这次抬手」——后面
    ///   无论早退（没有可加载的 provider）还是异步分支失败，抑制都在这里结束；
    /// - `vm.dropEvent = true` **同步**置位（同既有四处 dropEvent 的口径）：面板自己的
    ///   「这次抬手是落点、不是点空白」记账要赶得上当次 `!isTargeted`，等异步回来就晚了。
    private func handleDrop(_ providers: [NSItemProvider], target: LauncherDropRegion) -> Bool {
        defer { endDragSuppression() }
        vm.dropEvent = true

        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let draggedID = object as? String else { return }
                // 回调在后台队列，回到主线程再改 `@Published` 状态（同 `MusicSlotConfigurationView`）。
                DispatchQueue.main.async {
                    applyDrop(draggedID: draggedID, target: target)
                }
            }
            return true
        }
        return false
    }

    /// `resolve` 校验 + 落到 store（先落盘再刷新）。`knownIDs` = 本次扫描的**全量**清单
    /// （不经搜索过滤——搜索只影响下区画什么，不影响"这个 id 是否存在"）。
    ///
    /// 抑制的释放与 `dropEvent` 的置位都在 `handleDrop`（同步、第一行）完成，这里只做落点判定
    /// 与写入；`resolve` 判 nil（外来文本 / 反向拖 / 未知 id）就到此为止，不落盘、不刷新。
    private func applyDrop(draggedID: String, target: LauncherDropRegion) {
        guard LauncherQuickDrop.resolve(
            draggedID: draggedID,
            target: target,
            pinnedIDs: store.pinned,
            knownIDs: Set(store.apps.map(\.id))
        ) != nil, let app = store.apps.first(where: { $0.id == draggedID }) else { return }

        switch target {
        case .quick: store.pin(app)
        case .grid: store.unpin(app)
        }
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

/// 网格里的一个格子：**图标 + 名称**，点一下启动；右键固定 / 取消固定；可拖拽（两区共用这个格子）。
///
/// 图标由调用方（网格）按需取好传进来（见 `LauncherIconCache`）。`isPinned` 只决定右键菜单的
/// 文案（固定 / 取消固定）——右上角的图钉角标**已删**（p7：下区不再含固定项，上区本身就是
/// 「固定」的呈现，角标没有要标的东西了）。
///
/// **拖拽与点击共存**：`.onDrag` 挂最外层容器，`Button` 的点击启动不变——拖拽只在移动超过系统
/// 阈值后开始，原地按下抬起仍是"点一下启动"（上屏验证过，见 T5 报告）。
/// 载体是 `app.id` 的纯文本（`NSString`）；接收侧（两区容器）按 `LauncherQuickDrop.resolve` 校验。
/// `dragItem` 由容器注入（两区共用同一个闭包：起拖时挂自动收起抑制令牌，见 `dragItem(for:)`）。
private struct LauncherGridCell: View {
    let app: LauncherApp
    let icon: NSImage
    let metrics: LauncherGridMetrics
    let isPinned: Bool
    /// 起拖：返回拖拽载体（应用 id 的纯文本）。抑制令牌的挂载在容器侧完成。
    let dragItem: () -> NSItemProvider
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
        // 拖拽载体 = 应用 id 的纯文本；挂最外层、Button 的点击启动不变（见类型注释）。
        .onDrag(dragItem)
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
