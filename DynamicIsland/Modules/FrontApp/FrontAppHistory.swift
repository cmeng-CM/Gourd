//
//  FrontAppHistory.swift
//  Gourd 模块 · 前台应用联动（p2-shortcuts-frontapp / T3）
//
//  docs/22-shortcuts-and-frontapp.md §接口与数据形状 3 的三件**纯逻辑**：
//  本文件没有 `NSImage`、不依赖 AppKit（也不依赖 SwiftUI）——事件源（`NSWorkspace` 通知）
//  与图标取值在 `FrontAppStore.swift`，首页块视图在 T4 的 `FrontAppModule.swift`。
//  纯逻辑独立成文件的理由是可测：「去重 + 移到最前 + 截到上限」与「排除自身」是首页块里唯二
//  会被写错、又最难在 UI 上看出来的地方（同一个应用切换两次出现两行、壶中天自己混进历史，
//  都要靠用例而不是肉眼；带上 `NSImage` 就得起真 `NSWorkspace` 才构造得出被驱动的值）。
//
//  三条刻意写死的口径（改动前先读）：
//
//  1. **快照不持有 `NSImage`**（§接口与数据形状 3）：图标由视图层按需向 `FrontAppStore.icon(for:)` 取；
//     界面形态变了（大图标 / 小图标 / 不画图标）不该改动数据模型，也不该让纯函数带上 AppKit；
//  2. **身份是 `id`**（`bundleID ?? "pid:\(pid)"`）：绝大多数应用有 bundleID（稳定、跨重启不变）；
//     无 bundleID 的进程（命令行工具、开发中的裸可执行文件）退到 pid 兜底——pid 会被复用，
//     那一条会被认错，但比「合并成一条没有身份的记录」更接近事实；
//  3. **夹取只发生一次**（§接口与数据形状 3 的 store 段）：`limitRange` 3…8 的夹取在 store
//     读 config 之后做一次（`clampedLimit`），`updated` 本身**严格按传进来的 `limit` 截断**
//     （给 1 就只留 1 条、给 0 就给空表）——纯函数再夹一遍就会让「到底哪个值说了算」有两处。
//

import Foundation

// MARK: - 快照

/// 一次前台快照（`bundleID` 缺失时用 `pid` 兜底做身份）。
///
/// `Equatable` 供用例与 store 比较、`Identifiable` 供 `ForEach` 直接用 `id` 做身份——
/// 两者都只看三个存储属性（`NSImage` 不在其中，见口径 1）。
struct FrontAppSnapshot: Equatable, Identifiable {
    /// 应用的 bundle identifier（无 bundleID 的进程是 nil）。
    let bundleID: String?
    /// 显示用的应用名（`NSRunningApplication.localizedName`，由 store 映射时兜底）。
    let name: String
    /// 进程号：既是身份的兜底，也是 `activate(_:)` 与「拿不到包路径时兜底取图标」的把手。
    let pid: pid_t

    /// 身份：有 bundleID 用它，没有就 `"pid:\(pid)"`（口径 2）。
    var id: String { bundleID ?? "pid:\(pid)" }
}

// MARK: - 历史（纯函数）

/// 前台应用历史的**纯函数口径**（§做法 机制三）：新在前、同 id 只一条、超上限从**尾部**挤掉。
///
/// 这三个函数是「最近切换」这块唯一会被写错的地方，因此不碰 `NSWorkspace`、不碰 `NSImage`：
/// 用例用手造快照就能驱动全部边界（空表 / 只有一条 / 超上限 / 自身 / pid 兜底）。
enum FrontAppHistory {

    /// 去重（同 id 只留一条）→ 移到最前 → 截到 `limit`。
    ///
    /// - 顺序：`activating` 在最前，其余保持 `recent` 原有顺序（新在前）；
    /// - 去重是**按 id 全局去重**（不止是"把 `activating` 的旧条目删掉"）：磁盘上被手改成两份
    ///   的同一 id 也会在这里并成一条，谁也不该在首页块里看到同一个应用两行；
    /// - 同 id 保留的是**这一份新快照**（名称变了、pid 变了都跟着更新）；
    /// - `limit` 严格生效（口径 3）：非正值给空表，不做任何"至少留几条"的兜底。
    static func updated(_ recent: [FrontAppSnapshot], activating: FrontAppSnapshot, limit: Int) -> [FrontAppSnapshot] {
        guard limit > 0 else { return [] }

        var seen = Set<String>()
        var next: [FrontAppSnapshot] = []
        for item in [activating] + recent where seen.insert(item.id).inserted {
            next.append(item)
        }
        return next.count > limit ? Array(next.prefix(limit)) : next
    }

    /// 排除本应用自己（`selfBundleID`）：否则每次点开刘海都把壶中天自己记成"最近应用"。
    ///
    /// `selfBundleID` 为 nil（本应用没有 bundleID）时**原样返回**：没有判据就不猜——
    /// 拿 nil 去比只会把所有无 bundleID 的进程误伤掉。无 bundleID 的条目同理不被某个具体 id 误伤。
    static func excludingSelf(_ items: [FrontAppSnapshot], selfBundleID: String?) -> [FrontAppSnapshot] {
        guard let selfBundleID else { return items }
        return items.filter { $0.bundleID != selfBundleID }
    }

    /// `maxRecentApps` 的夹取区间与默认值（§备选与取舍 ⑤：放太多会挤掉"当前应用"这个主角）。
    static let limitRange: ClosedRange<Int> = 3...8
    static let defaultLimit = 5

    /// 把 config 里的 `maxRecentApps` 夹到 `limitRange`——**全项目唯一一处夹取**（口径 3）。
    ///
    /// store 读 config（缺键时兜 `defaultLimit`）之后调它一次，视图不再夹：`recentLimit` 就是
    /// 那个唯一值，配置页面与首页块因此不会各显示一个数量。
    static func clampedLimit(_ raw: Int) -> Int {
        min(max(raw, limitRange.lowerBound), limitRange.upperBound)
    }
}
