//
//  NotificationsModule.swift
//  Gourd 内置模块 · 通知上岛（P2c 列表 + P2d 浮层）
//
//  设计依据：docs/09-features-and-mechanisms.md §5.5（本轮风险最高的一项）+ docs/12-p1-batches.md P2c。
//  P2c 交付 = 可行性探针 + 模块骨架 + 展开列表；**P2d 交付 = 折叠态瞬时浮层**（内核 `presentHUD`，
//  见 `Kernel/ModuleHUDView.swift` 与 13 号文档 D-22）。
//
//  ## 数据源与权限
//  - 数据源：`~/Library/Group Containers/group.com.apple.usernoted/db2/db`（SQLite，**只读**，
//    见 `NotificationCenterReader`；schema 是私有的，Apple 改版即失效）；
//  - 权限：**需要完全磁盘访问**。该权限**无法程序化申请**，因此本模块不做任何授权弹窗：
//    读不到时只在面板上显示提示 + 一颗「打开系统设置」按钮（跳到隐私与安全性 → 完全磁盘访问）；
//  - **严禁**为了触发提示去读其它受保护路径（本机实测：通知库自身被拒即可判定）。
//
//  ## 能力边界（09 §5.5「必须接受」，UI 上有一行 footer 明示）
//  ① **只能读**：不能回复、不能在系统通知中心里操作真实通知（那需要 AX 或私有 API，属降级方案）。
//     **岛上能做的只有「关闭 / 清除」= 仅从岛上移除**（本地隐藏 + `dismissedNotificationIDs` 持久化）：
//     系统通知中心里的条目**不由本应用增删**（只读原则，见 `NotificationCenterReader` 头注释），
//     库里的记录也一条不动；若要连系统通知一起清掉，需走设计稿的 AX 降级路径
//     （`AXPress` 关掉真实通知，**尚未实现**）；
//  ② 需要完全磁盘访问；③ schema 私有、系统改版可能失效；
//  ④ 内容敏感：浮层**默认显示正文**（`showBodyInHUD` 默认 true——**用户 2026-09-28 口径，
//    覆盖设计稿原口径的 false**）；不想要正文的用户在设置页（Live Activities → Notifications）
//    关掉该项即可，关掉后浮层第二行只留「新通知」。
//
//  ## 增量策略（09 §5.5）
//  **文件事件驱动（主路径）+ 60s 兜底轮询（第二道闸门）**——2026-09-28 把原来的 30s 轮询换掉：
//  - 主路径：`NotificationCenterReader.startWatching` 监听 `db` / `db-wal` 的写入事件，
//    事件到齐（去抖 0.3s）后立刻按 `record.rec_id > 基线` 取增量 → 有新记录就弹浮层。
//    **这就是「实时」**（本机实测：库里落盘 → 浮层 0.303s）；
//  - 兜底：每 60s 仍按 `rec_id > 基线` 取一次（**不过 mtime 闸门**）——事件可能漏报
//    （`O_EVTONLY` 被 TCC 拒绝、`db-wal` 被 checkpoint 清掉后重建的空档里没有 source 可挂）；
//  - **不做 1s 全表扫**（该库可能很大）：两条路径都只做 `rec_id > 基线` 的索引查询。
//  **链路前端有一段不由本应用控制的延迟**（实测记录见 09 §5.5）：usernoted 把通知**批量落盘**——
//  `osascript display notification` 到 `db-wal` 出现该记录实测 5.0～5.1s（退出本应用后单测也得
//  5.10s，故与本应用无关）。所以「造一条通知 → 岛上出现」端到端约 5.3s，其中 0.3s 是我们的管道；
//  原先的 30s 轮询口径下最坏要等 30s+，且 mtime 闸门看错文件（只看主库）时**永远不会**触发。
//  **首次 `activate()` 建基线**（`refreshAll()` 把基线推到当前 `MAX(rec_id)`）：激活前就在库里的
//  通知不算「新增」，因此不会为旧通知弹浮层、也不会一装上就冒出几十条未读。
//
//  ## 配置
//  `config: nil`——模块侧仍不读 manifest 配置（`appsFilter` / `maxItems` / `pollIntervalSeconds`
//  见 [14](../../docs/14-module-manifests.md) 的 notifications 行）。呈现开关
//  `showBodyInHUD` 是**宿主设置**（`Defaults.Keys.showBodyInHUD`，默认 true）；
//  已关闭集合 `dismissedNotificationIDs` 也是宿主设置键（由本模块读写，上限 500）。
//  09 §5.5 里**尚未做**的部分：按 App 分组、ax 降级路径（含「连系统通知一起清除」）、
//  `appsFilter` 黑白名单。
//
//  ## 本批形态
//  - 展开面板：标题行（模块名 + 状态 + **清除**（列表非空时）+ 刷新）+ 可滚动通知列表
//    （点击左侧内容 → 打开对应 App；行右侧 `xmark.circle.fill` → **关闭这一条，仅从岛上移除**）
//    + 一行能力边界说明；
//  - 折叠态**瞬时浮层**：新通知到达时 `bell.badge` + App 显示名 + 标题/正文，4s 后自动消失
//    （内核 `ModuleRegistry.presentHUD`；一次取数多条新通知只弹最新一条）；
//  - 折叠态中央槽位：`bell` 图标 + 自上次打开面板以来的新增条数（内存态，0 时无数字）。
//    **注意**：中央槽位当前由 todos（order 20）占用，本模块（order 40）只是候选之一，
//    在默认配置下这个视图不会被渲染（`ModuleRegistry.compactSlotContent()` 只转发第一个候选）。
//
//  ## 颜色（本项目已踩过两次的坑）
//  面板是黑底、系统外观可为浅色——本模块所有文字与图标**一律显式浅色**
//  （`Color.white` / `.white.opacity(...)`），不用 `.primary` / `.secondary`。
//
//  文案走 Localizable key：`module.notifications.name` / `.summary` / `.empty` /
//  `.needsFullDiskAccess` / `.openSettings` / `.recent` / `.justNow` / `.minutesAgo` /
//  `.hoursAgo` / `.daysAgo` / `.readOnlyNote` / `.newNotification` / `.clearAll` / `.dismiss`。
//

import AppKit
import Defaults
import SwiftUI

// MARK: - Store

/// 通知列表 / 增量计数 / 可读性状态的持有者（模块自己持有，不进 `ModuleRegistry`）。
@MainActor
final class NotificationStore: ObservableObject {
    /// 列表条数上限（本批是常量：第一版不读配置，见文件头）。
    static let maxItems = 40
    /// 兜底轮询间隔（秒）。**60s，不是 1s**——实时性由文件事件保证（见文件头「增量策略」），
    /// 这条轮询只用来兜「事件漏报」。
    static let fallbackPollInterval: TimeInterval = 60
    /// 已关闭 id 的持久化上限：**只保留最近 500 个**（写入 `Defaults` 前裁剪）。
    /// 500 远超列表上限（40）×10，日常使用永远够；限制的是「用一年以后 UserDefaults 里
    /// 堆了几万个 id」这种只增不减的增长。
    ///
    /// `nonisolated`：`trimmed(_:limit:)` 是纯函数、不碰主 actor 状态，默认参数要能引用它。
    nonisolated static let dismissedLimit = 500

    /// 最新通知（新的在前），最多 `maxItems` 条。
    @Published private(set) var items: [NotificationItem] = []
    /// 最近一次读取的可读性判定（UI 据此显示「最近 N 条 / 需要完全磁盘访问 / 错误」）。
    @Published private(set) var state: NotificationReadState = .ok
    /// 自上次打开面板以来的新增条数（**内存态**，不落盘；打开面板即清零）。
    @Published private(set) var unseenCount = 0
    /// 最近一次成功取数的时刻（只进日志与状态行，不改变呈现）。
    @Published private(set) var lastRefreshedAt: Date?
    /// 已关闭（**仅从岛上移除**）的 `rec_id` 集合。系统通知中心里的那一条仍在——
    /// 本应用**只读**通知库，不增删其中的任何条目（09 §5.5 只读原则）。
    @Published private(set) var dismissedRecordIDs: Set<Int64> = []

    /// 最近一次失败的可读原因（= `state` 的 `.failure` 载荷；UI 截断显示）。
    var failureReason: String? {
        if case .failure(let reason) = state { return reason }
        return nil
    }

    /// 浮层出口（**模块在 `init` 里注入**）：store 只把「这次新增里最新的那一条」交出去，
    /// 视图与 ttl 属模块的 UI 决策——store 因此不认识 `UIHandle`，也不依赖 SwiftUI 视图，
    /// 基线/增量这套逻辑仍可单测。
    var presentHUD: ((NotificationItem) -> Void)?

    /// 一次取数的浮层候选：**只取 `id > baseline` 里 id 最大的那个**。
    ///
    /// - 基线之外的一律不算（激活前就存在的通知、以及被 `refreshAll` 推进基线时一起算进「已见」的
    ///   旧记录，都不会弹浮层）；
    /// - 多条新通知只弹**最新一条**（09 §5.5：避免刷屏），其余只进未读计数。
    ///
    /// **纯函数**（生产路径与单测共用）：单测直接喂「基线 + 新记录集合」，不必起监听或轮询。
    static func hudCandidate(in items: [NotificationItem], above baseline: Int64) -> NotificationItem? {
        newRecords(in: items, above: baseline).last
    }

    /// **纯函数**：给定基线 `rec_id` 与一批记录 → 只返回 `id > 基线` 的，**按 id 升序**去重。
    ///
    /// 口径与 SQL 侧的 `WHERE rec_id > ? ORDER BY rec_id ASC` 严格一致（这是单测钉住它的理由：
    /// SQL 那条路需要真实库，这条不需要）：
    /// - 等于基线的不算新增（`>` 而不是 `>=`）；
    /// - **去重按 id**：同一批里重复出现的同一条只算一条（重复计数会让未读数虚高）；
    /// - 升序：调用方按到达顺序处理（`hudCandidate` 取 `.last` = 最新那一条）。
    static func newRecords(in items: [NotificationItem], above baseline: Int64) -> [NotificationItem] {
        var seen: Set<Int64> = []
        return items
            .filter { $0.id > baseline && seen.insert($0.id).inserted }
            .sorted { $0.id < $1.id }
    }

    private let reader: NotificationCenterReader
    private let log: ModuleLogger
    /// 增量基线：已见过的最大 `rec_id`（09 §5.5 的「按单调 id 取新增」）。
    private var baselineRecordID: Int64 = 0
    /// 上次看到的库文件 mtime（**只用于日志与「库真的不在」的判定**，不再是取数闸门：
    /// 事件驱动下闸门只会帮倒忙——事件说变了、mtime 还没落地时它会挡住取数）。
    private var lastModificationDate: Date?
    /// 串行闸：探针 / 全量 / 增量共用同一把（都是主线程状态，重入会写乱基线）。
    private var isFetching = false
    /// 取数期间到来的文件事件（**丢事件比慢更糟**：记下来，取完立刻补一次增量）。
    private var pendingIncrementalRefresh = false
    /// 事件监听的取消闭包（`reader.startWatching` 的返回值；由本 store 持有）。
    private var watchCancel: (() -> Void)?
    /// 已关闭 id 的**有序**序列（最近关闭的在后）——`Defaults` 里存的就是它。
    /// 与 `dismissedRecordIDs` 同源，两处只在 `persistDismissed()` 里一起写。
    private var dismissedOrder: [Int64] = []
    /// bundleIdentifier → App 本地化显示名（含「解析不到」的空串缓存，避免每次轮询重查）。
    private var appNameCache: [String: String] = [:]

    init(logger: ModuleLogger, reader: NotificationCenterReader = NotificationCenterReader()) {
        self.log = logger
        self.reader = reader
        // 启动时装载「已关闭」：不装载的话，之前关掉的条目会在下一次取数时又回到列表里。
        // 装载时顺手裁剪（旧版本可能留下超长的列表），裁剪过就立刻写回。
        // 类型在**落盘边界**转一次：`Defaults` 键是 `[Int]`（键的口径见 Constants），
        // 内存里一律用 `Int64`（`rec_id` 的类型）。
        let stored: [Int64] = Defaults[.dismissedNotificationIDs].map { Int64($0) }
        dismissedOrder = Self.trimmed(stored, limit: Self.dismissedLimit)
        dismissedRecordIDs = Set(dismissedOrder)
        if dismissedOrder.count != stored.count { persistDismissed() }
    }

    // MARK: 探针

    /// 首次 `activate()` 跑一次可行性探针：报告落盘（`~/Library/Logs/Gourd/notifications-probe.log`）
    /// + `.debug` 摘要；判定回写到 `state`（未授权时面板直接显示提示）。
    func runProbe() async {
        let reader = self.reader
        let report = await Task.detached(priority: .utility) { reader.probe() }.value
        state = report.readState
        lastModificationDate = reader.modificationDate
        log.info("探针完成 — \(report.summary)")
    }

    // MARK: 取数

    /// 起文件事件监听（**实时化的主路径**）：`db` / `db-wal` 一有写入，去抖 0.3s 后立刻取增量。
    ///
    /// 幂等（已在监听时直接返回）；watcher 的回调在它自己的串行队列上，这里跳回主 actor
    /// （store 的 `@Published` 只能在主线程写）。
    func startWatching() {
        guard watchCancel == nil else { return }
        let reader = self.reader
        watchCancel = reader.startWatching { [weak self] in
            Task { @MainActor in
                await self?.handleDatabaseChange()
            }
        }
        log.info("已起通知库文件事件监听（db + db-wal）")
    }

    /// 停监听（`deactivate()` 调；取消闭包同时释放 watcher）。
    func stopWatching() {
        watchCancel?()
        watchCancel = nil
    }

    /// **事件驱动的取数**（主路径）：库文件刚被写过 → 立刻取增量 → 有新记录就弹浮层。
    ///
    /// 正在取数时（面板刷新 / 兜底轮询撞上）**不丢事件**：记一个待办，取完立刻补一次
    /// （丢了就等于这条通知永远不弹浮层——兜底轮询只补列表、不会补浮层）。
    func handleDatabaseChange() async {
        if isFetching {
            pendingIncrementalRefresh = true
            return
        }
        await refreshIncremental(reason: "文件事件")
        await drainPendingIncrementalRefresh()
    }

    /// 取数收尾：若取数期间又来过文件事件，补一次增量（见 `pendingIncrementalRefresh`）。
    private func drainPendingIncrementalRefresh() async {
        while pendingIncrementalRefresh {
            pendingIncrementalRefresh = false
            await refreshIncremental(reason: "文件事件（取数期间排队）")
        }
    }

    /// 全量刷新：最新 `maxItems` 条进列表，并把增量基线推到 `MAX(rec_id)`
    /// （**既有通知不算「新增」**——否则一装上就冒出几十条未读）。
    func refreshAll() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        let reader = self.reader
        let limit = Self.maxItems
        let dismissed = dismissedRecordIDs  // 快照：跨 await 后读到的是同一份
        let fetched = await Task.detached(priority: .utility) {
            reader.fetchRecent(limit: limit, dismissing: dismissed)
        }.value

        apply(fetched, from: reader)
        log.info("全量刷新：\(fetched.count) 条，判定 \(String(describing: reader.lastState))")
        await drainPendingIncrementalRefresh()
    }

    /// 兜底轮询一次（60s）。**刻意不过 mtime 闸门**：它要救的正是「文件事件漏报」，
    /// 而闸门（mtime 没变就不取）会让它跟着一起漏——一分钟一次 `rec_id > 基线` 的索引查询，
    /// 成本可以忽略，换来的是「事件全挂也不丢通知」。
    ///
    /// 唯一保留的判定是「库文件元数据完全读不到」（stat 都不行 = 库真的不在）：
    /// 那时只更新面板判定，不进增量。
    func pollOnce() async {
        guard !isFetching else { return }
        let reader = self.reader
        let mtime = await Task.detached(priority: .utility) { reader.modificationDate }.value

        guard let mtime else {
            // stat 都失败（TCC 通常不拦 stat，所以这只在库真的不在时发生）
            log.warn("库文件元数据不可读：\(reader.databasePath)")
            state = .failure("库文件不可访问：\(reader.databasePath)")
            return
        }
        lastModificationDate = mtime
        await refreshIncremental(reason: "兜底轮询")
        await drainPendingIncrementalRefresh()
    }

    /// 增量：取 `rec_id > 基线` 的新通知；有新条目才累加未读数并刷新列表。
    ///
    /// 两条路径共用（文件事件 / 兜底轮询），`reason` 只进日志——**实时性的证据就是这两行日志的
    /// 时间差**（见 docs/09 §5.5 的实测记录）。
    private func refreshIncremental(reason: String) async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        let reader = self.reader
        let limit = Self.maxItems
        let baseline = baselineRecordID
        let dismissed = dismissedRecordIDs  // 快照：跨 await 后读到的是同一份
        let newItems = await Task.detached(priority: .utility) {
            reader.fetchNew(after: baseline, limit: limit, dismissing: dismissed)
        }.value

        lastModificationDate = reader.modificationDate
        state = reader.lastState
        if let maxID = reader.lastMaxRecordID { baselineRecordID = max(baseline, maxID) }
        guard !newItems.isEmpty else { return }

        unseenCount += newItems.count
        let fetched = await Task.detached(priority: .utility) {
            reader.fetchRecent(limit: limit, dismissing: dismissed)
        }.value
        apply(fetched, from: reader)
        log.info("\(reason)：新增 \(newItems.count) 条通知，最新 rec_id=\(newItems.map(\.id).max() ?? -1)（未读累计 \(unseenCount)）")

        // 浮层：只弹**最新一条**，且必须严格晚于**本次取数前的基线**（`hudCandidate` 的判据）。
        // 用取数前的 `baseline` 而不是刚更新的 `baselineRecordID`——后者已经把新条目算进去了。
        if let latest = Self.hudCandidate(in: newItems, above: baseline) {
            presentHUD?(resolveAppNames(for: [latest]).first ?? latest)
        }
    }

    /// 面板打开：未读数清零（「自上次打开面板以来」的口径）。
    func markPanelOpened() {
        guard unseenCount != 0 else { return }
        unseenCount = 0
    }

    // MARK: 关闭 / 清除（**仅从岛上移除**）

    /// 关闭一条：立即从列表里去掉 + 记进「已关闭」集合 + 落盘。
    ///
    /// **只从岛上移除**——系统通知中心里的那一条仍在，库里的记录也仍在（只读原则：
    /// 本应用不增删系统通知，见文件头「能力边界」）。幂等（重复关同一条不重复记账）。
    func dismiss(_ item: NotificationItem) {
        guard !dismissedRecordIDs.contains(item.id) else {
            items.removeAll { $0.id == item.id }  // 已在集合里（例如上一次运行关过）：只保证列表里没有
            return
        }
        dismissedOrder.append(item.id)
        dismissedRecordIDs.insert(item.id)
        items.removeAll { $0.id == item.id }
        persistDismissed()
        log.info("关闭通知 rec_id=\(item.id)，仅从岛上移除（系统通知中心不动）")
    }

    /// 一键清除：把**当前列表**里的条目全部标记为已关闭（等价于逐条关闭，一次落盘一次日志）。
    func dismissAll() {
        guard !items.isEmpty else { return }
        let ids = items.map(\.id)
        dismissedOrder.append(contentsOf: ids.filter { !dismissedRecordIDs.contains($0) })
        dismissedRecordIDs.formUnion(ids)
        let count = ids.count
        items = []
        persistDismissed()
        log.info("清除全部 \(count) 条，仅从岛上移除（系统通知中心不动）")
    }

    /// 落盘（**写入时裁剪**到最近 `dismissedLimit` 个）+ 同步内存集合。
    ///
    /// 两处状态（有序序列 / 集合）只在这里一起写，避免「集合里有、序列里没有」的错位。
    private func persistDismissed() {
        dismissedOrder = Self.trimmed(dismissedOrder, limit: Self.dismissedLimit)
        dismissedRecordIDs = Set(dismissedOrder)
        // 落盘边界转回 `[Int]`（键的类型；`rec_id` 实际远小于 Int.max）
        Defaults[.dismissedNotificationIDs] = dismissedOrder.map(Int.init)
    }

    /// **纯函数**：把已关闭 id 序列裁剪到**最近** `limit` 个（保留尾部，最近关闭的在尾部），
    /// 并去掉重复 id（保序：重复只留第一次出现的位置……末尾的重复会顶掉更早的那次）。
    ///
    /// 单测钉住边界：不超过上限时原样、超限只留最近 N 个、重复 id 去重、`limit <= 0` 给空。
    static func trimmed(_ ids: [Int64], limit: Int = dismissedLimit) -> [Int64] {
        guard limit > 0 else { return [] }
        var seen: Set<Int64> = []
        let deduped = ids.filter { seen.insert($0).inserted }
        return deduped.count > limit ? Array(deduped.suffix(limit)) : deduped
    }

    /// 打开一条通知对应的 App（**公开 API**：取 bundleIdentifier → `NSWorkspace.openApplication(at:)`）。
    func openApp(for item: NotificationItem) {
        guard !item.bundleIdentifier.isEmpty else {
            log.warn("打开跳过：这条通知没有 bundleIdentifier（rec_id=\(item.id)）")
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleIdentifier) else {
            log.warn("打开跳过：解析不到 App（\(item.bundleIdentifier)，rec_id=\(item.id)）")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [log] _, error in
            if let error {
                log.warn("打开 App \(item.bundleIdentifier) 失败：\(String(describing: error))")
            }
        }
    }

    // MARK: 内部

    /// 落一批取数结果（列表 + App 显示名 + 判定 + 基线 + 时间戳同一处写，避免五处各写一半）。
    private func apply(_ fetched: [NotificationItem], from reader: NotificationCenterReader) {
        items = resolveAppNames(for: fetched)
        state = reader.lastState
        lastModificationDate = reader.modificationDate
        if let maxID = reader.lastMaxRecordID { baselineRecordID = max(baselineRecordID, maxID) }
        if reader.lastState == .ok { lastRefreshedAt = Date() }
    }

    /// 补 App 显示名。**探针实测校准（2026-09-28）**：`app` 表只有 `app_id` / `identifier` / `badge`，
    /// **没有显示名列**——09 §5.5 写的「app 表给 bundle id ↔ 显示名」在 macOS 27 上不成立。
    /// 因此显示名改走 `NSWorkspace`（公开 API）解析 App 包的 `CFBundleDisplayName`；
    /// 解析不到时保留 reader 的兜底（bundle id 最后一段）。
    private func resolveAppNames(for items: [NotificationItem]) -> [NotificationItem] {
        items.map { item in
            guard !item.bundleIdentifier.isEmpty else { return item }
            if let cached = appNameCache[item.bundleIdentifier] {
                return cached.isEmpty ? item : item.withAppName(cached)
            }
            let name = Self.localizedAppName(for: item.bundleIdentifier) ?? ""
            appNameCache[item.bundleIdentifier] = name
            return name.isEmpty ? item : item.withAppName(name)
        }
    }

    /// App 包的本地化显示名（`CFBundleDisplayName` → `CFBundleName`）；解析不到返回 nil。
    private static func localizedAppName(for bundleIdentifier: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
              let bundle = Bundle(url: url)
        else { return nil }
        let info = bundle.localizedInfoDictionary ?? bundle.infoDictionary
        if let name = info?["CFBundleDisplayName"] as? String, !name.isEmpty { return name }
        if let name = info?["CFBundleName"] as? String, !name.isEmpty { return name }
        return nil
    }
}

// MARK: - 模块

/// 通知上岛模块（09 §5.5）。
@MainActor
final class NotificationsModule: GourdModule {
    /// 静态元数据（06 §2.2 的本批子集）。
    ///
    /// - `surfaces`：`expanded`（通知列表）+ `compact`（bell + 未读数）；
    /// - `defaultPlacement`：`slot: .center` / `order: 40`——排在 todos（20）与 progress（30）之后，
    ///   因此**默认配置下拿不到中央槽位**（`compactSlotContent()` 只转发第一个候选）；
    /// - `defaultEnabled: true`；
    /// - `permissions: []`：本批不改 06 §7.1 的白名单，而 docs/14 给本模块标注的
    ///   `notifications:read` **尚未落进白名单**（06 §7.1 只有无参数的 `notifications`）。
    ///   完全磁盘访问是**系统 TCC 授权**、不是模块 capability；等白名单正式增补后再改这一行
    ///   （同 todos 的 `permissions: []` 口径）；
    /// - `config: nil`：第一版不读配置（`appsFilter` / `maxItems` / `pollIntervalSeconds` /
    ///   `showBodyInHUD` 都还没有配置入口，见 [14](../../docs/14-module-manifests.md) 的 notifications 行）。
    static let manifest = ModuleManifest(
        manifestVersion: 1,
        id: "com.cmeng.gourd.notifications",
        name: LocalizedText(key: "module.notifications.name"),
        summary: LocalizedText(key: "module.notifications.summary"),
        icon: IconSpec(type: "symbol", name: "bell.badge"),
        version: "1.0.0",
        apiVersion: HostInfo.currentAPIVersion,
        kind: "builtin",
        surfaces: [.expanded, .compact],
        defaultPlacement: Placement(slot: .center, order: 40),
        defaultEnabled: true,
        permissions: [],
        config: nil
    )

    private let context: ModuleContext
    private let store: NotificationStore
    private var pollTask: Task<Void, Never>?
    /// 探针只跑一次（**首次 activate**）。`deactivate()` 不会重置它——重新激活不重复探针。
    private var didRunProbe = false

    /// 浮层的 ttl（秒）。4s：够看清「谁发的 + 标题」，又不至于挡住其它 live activity。
    private static let hudTTL: TimeInterval = 4

    init(context: ModuleContext) {
        self.context = context
        let store = NotificationStore(logger: context.logger)
        self.store = store
        // 浮层出口：store 只交「最新一条新增」，视图（含 `showBodyInHUD` 的读值）与 ttl 在这里定。
        store.presentHUD = { [weak self] item in
            guard let self else { return }
            self.presentNotificationHUD(for: item)
        }
    }

    /// 起**文件事件监听（主路径）+ 兜底轮询（60s）**，两者都幂等；首个 tick 前先跑一次探针 + **建基线**。
    ///
    /// 探针与取数都在**后台任务**里跑（`NotificationCenterReader` 无共享可变状态、可安全跨线程）——
    /// 库在 TCC 拒绝下会立刻失败，授权后也只是读一个几百 KB 的 SQLite，但一律不占主线程。
    ///
    /// **建基线是浮层语义的前提**：`refreshAll()` 把基线推到当前 `MAX(rec_id)`，激活前就躺在
    /// 库里的通知因此不算「新增」——不建基线的话，装上后第一次取数会把最近 40 条全当新通知
    ///（还会为其中最旧的一条弹浮层）。
    ///
    /// 顺序有讲究：**先起监听再建基线**。反过来的话，建基线那几百毫秒里到达的通知会既不算新增
    /// （被 `refreshAll` 推进基线）也没有浮层——先挂事件，事件驱动的取数会与 `refreshAll` 串行
    /// （`isFetching` 闸）且排队补一次（`drainPendingIncrementalRefresh`）。
    func activate() async throws {
        guard pollTask == nil else { return }
        let store = self.store
        let shouldProbe = !didRunProbe
        didRunProbe = true

        store.startWatching()
        pollTask = Task { [store] in
            if shouldProbe {
                await store.runProbe()
            }
            await store.refreshAll()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(NotificationStore.fallbackPollInterval))
                } catch {
                    return  // 被取消（deactivate）：正常退出，不记错误
                }
                await store.pollOnce()
            }
        }
        context.logger.info(
            "notifications 模块已激活（db/db-wal 文件事件驱动 + 兜底轮询 "
                + "\(Int(NotificationStore.fallbackPollInterval))s，已建增量基线）"
        )
    }

    func deactivate() async {
        pollTask?.cancel()
        pollTask = nil
        store.stopWatching()
    }

    /// 两个 surface 各给一份内容；未声明的 `lockscreen` 返回 `.none`（不占位、不算失败）。
    func content(for request: ContentRequest) -> ModuleContent {
        switch request.surface {
        case .compact:
            return .view(AnyView(NotificationsCompactView(store: store)))
        case .expanded:
            return .view(AnyView(NotificationsModuleView(store: store)))
        case .lockscreen:
            return .none
        }
    }

    /// 弹一条通知浮层（`store.presentHUD` 的唯一消费者）。
    ///
    /// 视图在**这一刻**按当前设置快照构造：`showBodyInHUD` 是模块配置的呈现口径，
    /// 浮层只活 `hudTTL` 秒，不需要为它维护一条「设置改了要重渲」的观察链。
    private func presentNotificationHUD(for item: NotificationItem) {
        let showsBody = Defaults[.showBodyInHUD]
        context.logger.info("弹通知浮层：rec_id=\(item.id)，正文\(showsBody ? "显示" : "隐藏")")
        context.ui.presentTransient(
            view: AnyView(NotificationHUDView(item: item, showsBody: showsBody)),
            ttl: Self.hudTTL
        )
    }
}

// MARK: - 展开面板视图

/// 展开面板：标题行（模块名 + 状态 + 刷新）+ 通知列表（点击整行打开对应 App）+ 能力边界说明。
///
/// `.task` 做两件事：取一次最新数据（**不碰权限**）+ 把未读数清零（「自上次打开面板以来」）。
private struct NotificationsModuleView: View {
    @ObservedObject var store: NotificationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            body(for: store.state)
            footer
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            await store.refreshAll()
            store.markPanelOpened()
        }
    }

    /// 标题行：模块名 + 状态（「最近 N 条」/「需要完全磁盘访问」/ 错误原因截断）
    /// + 「清除」（列表非空时才出现，一键把当前列表全部关闭）+ 刷新按钮。
    private var header: some View {
        HStack(spacing: 6) {
            Text(LocalizedStringKey("module.notifications.name"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)

            Text(NotificationText.status(store.state, count: store.items.count))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(store.state == .needsFullDiskAccess ? 0.85 : 0.6))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            // 一键清除：只在有内容时出现（空列表上放一颗无效按钮只会让人以为坏了）。
            // **只把当前列表标记为已关闭**，系统通知中心里的条目一条都不动。
            if !store.items.isEmpty {
                Button {
                    store.dismissAll()
                } label: {
                    Text(LocalizedStringKey("module.notifications.clearAll"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.12)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(NotificationText.localized("module.notifications.clearAll"))
            }

            Button {
                Task { await store.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help(NotificationText.localized("module.notifications.refresh"))
        }
    }

    @ViewBuilder
    private func body(for state: NotificationReadState) -> some View {
        switch state {
        case .needsFullDiskAccess:
            NotificationPermissionPrompt()
        case .failure(let reason):
            // 失败原因**截断显示**（完整串在日志与探针报告里，面板上留两三行足够定位）
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(reason)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .ok:
            if store.items.isEmpty {
                Text(LocalizedStringKey("module.notifications.empty"))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NotificationListView(store: store)
            }
        }
    }

    /// 能力边界（09 §5.5「必须接受」的四条）——一行小字，别让用户以为能在岛上操作通知。
    private var footer: some View {
        Text(LocalizedStringKey("module.notifications.readOnlyNote"))
            .font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.35))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 通知列表：一行一条，点击整行按 `bundleIdentifier` 打开对应 App。
private struct NotificationListView: View {
    @ObservedObject var store: NotificationStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(store.items) { item in
                    NotificationRow(item: item, store: store)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// 列表的一行：`App 名（粗体）· 相对时间` + 标题 + 正文（最多 2 行）+ 右侧「关闭」按钮。
///
/// **两个手势刻意不重叠**：点击区（打开 App）只盖左侧内容列，关闭按钮在它右侧、自己的 frame 里。
/// 这样两个动作天然互不干扰——不需要靠「谁的手势优先级高」这种版本相关的规则。
/// （常见写法是在整行上挂 `.onTapGesture`、按钮叠在里面，那样点按钮时点击区仍可能吃到触摸。）
private struct NotificationRow: View {
    let item: NotificationItem
    @ObservedObject var store: NotificationStore

    /// 整行 hover（背景高亮 + 关闭按钮提亮）。
    @State private var isHovered = false
    /// 关闭按钮自身的 hover（鼠标停在按钮上 → 直接到 `.white`）。
    @State private var isDismissHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            content
            dismissButton
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(isHovered ? 0.08 : 0))
        )
        .onHover { isHovered = $0 }
    }

    /// 左侧内容 = 「打开对应 App」的点击区。
    private var content: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(item.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))

                if let delivered = item.deliveredDate {
                    Text(NotificationText.relative(delivered))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer(minLength: 2)
            }

            if !item.title.isEmpty {
                Text(item.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if !item.body.isEmpty {
                Text(item.body)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { store.openApp(for: item) }
    }

    /// 关闭按钮：**只从岛上移除这一条**（系统通知中心不动，见文件头「能力边界」）。
    /// 常态 `.white.opacity(0.6)`，鼠标进入（行内或按钮上）提亮到 `.white`。
    private var dismissButton: some View {
        Button {
            store.dismiss(item)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(isHovered || isDismissHovered ? 1 : 0.6))
                .padding(3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isDismissHovered = $0 }
        .help(NotificationText.localized("module.notifications.dismiss"))
    }
}

// MARK: - 折叠态瞬时浮层视图

/// 折叠态瞬时浮层（09 §5.5 呈现 ①）：`bell.badge` + 「App 显示名」+ 「标题 + 正文」。
///
/// **默认显示正文**（`showBodyInHUD` 默认 true——用户 2026-09-28 明确要求，覆盖设计稿原口径的
/// false）；关掉后第二行只留一条「新通知」文案，正文仍可在展开列表里看。
///
/// 颜色：面板是黑底、系统外观可为浅色——与模块其余视图同口径，文字**一律显式浅色**
///（`.white` / `.white.opacity(...)`），不用 `.primary` / `.secondary`。
///
/// 宽度：关闭态刘海只有一格（`closedNotchWidth`，本机 100pt），故给正文列一个上界，
/// 让长标题/长正文按 `.tail` 截断而不是把内容撑出可见区域。
private struct NotificationHUDView: View {
    let item: NotificationItem
    /// `Defaults[.showBodyInHUD]`（在 `presentNotificationHUD` 里取一次快照）。
    let showsBody: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bell.badge")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 1) {
                Text(appName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(secondLine)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: 220, alignment: .leading)
        }
    }

    /// App 显示名：`NSWorkspace` 解析出的显示名（store 已回填到 `appName`）优先，
    /// 取不到时退回 bundle id 的**最后一段**（`faceTime` 而非 `com.apple.FaceTime`）。
    private var appName: String {
        if !item.appName.isEmpty { return item.appName }
        let fallback = NotificationCenterReader.appDisplayName(bundleIdentifier: item.bundleIdentifier, appMap: [:])
        return fallback.isEmpty ? item.displayName : fallback
    }

    /// 第二行：`showBodyInHUD` 为真时是「标题 + 正文」，否则是「新通知」这一行文案。
    private var secondLine: String {
        NotificationText.hudDetail(title: item.title, body: item.body, showsBody: showsBody)
    }
}

// MARK: - 权限提示

/// 未授权（完全磁盘访问未授予）时的占位：说明 + 「打开系统设置」。
///
/// **不请求、也不试探**：完全磁盘访问无法程序化申请，这里只给一个跳转（PRD 的「不打扰」策略）。
private struct NotificationPermissionPrompt: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell.badge")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            Text(LocalizedStringKey("module.notifications.needsFullDiskAccess"))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                NotificationPermissionPrompt.openFullDiskAccessSettings()
            } label: {
                Text(LocalizedStringKey("module.notifications.openSettings"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 系统设置 → 隐私与安全性 → 完全磁盘访问（`x-apple.systempreferences:` 是系统既定的跳转 scheme）。
    static func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - 折叠态中央槽位视图

/// 折叠态中央槽位：`bell` 图标 + 自上次打开面板以来的新增条数（0 时只有图标）。
///
/// 自带 30s `TimelineView`（宿主不为这一格起定时器，口径同 progress / todos）；数字变化另有
/// `@ObservedObject` 的 `@Published` 驱动，`TimelineView` 负责的是「面板长时间不动时这一格仍会被重算」。
private struct NotificationsCompactView: View {
    @ObservedObject var store: NotificationStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            HStack(spacing: 4) {
                Image(systemName: "bell")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)

                if store.unseenCount > 0 {
                    Text("\(store.unseenCount)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

// MARK: - 文案出口

/// 模块内动态文案的唯一出口（06 §3.3 R5：视图内不写字面量文案）。
///
/// 状态行的三段文案与相对时间都**先拼成 String 再给 `Text`**（走 `Text(_: String)` 的 verbatim
/// 重载，不会把这些形态当成本地化 key 去查表），与 `ProgressText` / `TodoText` 同口径。
enum NotificationText {
    /// 状态行：`最近 N 条` / `需要完全磁盘访问` / 错误原因（截断到 60 字）。
    static func status(_ state: NotificationReadState, count: Int) -> String {
        switch state {
        case .ok:
            return String(format: localized("module.notifications.recent"), count)
        case .needsFullDiskAccess:
            return localized("module.notifications.needsFullDiskAccess")
        case .failure(let reason):
            return truncate(reason, limit: 60)
        }
    }

    /// 相对时间文案（09 §5.5 的列表要求：「3 分钟前」形态）。
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let parts = relativeParts(since: date, now: now)
        return String(format: localized(parts.key), parts.value)
    }

    /// 相对时间 →（本地化 key, 数字）。**纯函数**，边界由单测钉住：
    /// `< 60s` → justNow；`< 1h` → 分钟；`< 24h` → 小时；`≥ 24h` → 天。
    /// 未来时间（时钟回拨 / 记录时间戳超前）一律按「刚刚」。
    static func relativeParts(since date: Date, now: Date = Date()) -> (key: String, value: Int) {
        let interval = now.timeIntervalSince(date)
        if interval < 60 {
            return ("module.notifications.justNow", 0)
        }
        if interval < 3600 {
            return ("module.notifications.minutesAgo", Int(interval / 60))
        }
        if interval < 86_400 {
            return ("module.notifications.hoursAgo", Int(interval / 3600))
        }
        return ("module.notifications.daysAgo", Int(interval / 86_400))
    }

    /// `module.notifications.<field>` 形态的 key → 当前语言文案（查不到时 `Bundle` 原样返回 key）。
    static func localized(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }

    /// 浮层第二行的文案口径（`showBodyInHUD` 的呈现规则，**纯函数**，单测直接钉）：
    ///
    /// - `showsBody == true`（**默认**）：`标题 · 正文`，逐段去首尾空白、空段忽略；
    /// - `showsBody == false`：只给「新通知」（正文不进浮层，但展开列表照旧显示全文）；
    /// - 两边都空（plist 缺 `titl` / `body`）时同样给「新通知」，不留一行空白。
    static func hudDetail(title: String, body: String, showsBody: Bool) -> String {
        let newNotification = localized("module.notifications.newNotification")
        guard showsBody else { return newNotification }
        let text = [title, body]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return text.isEmpty ? newNotification : text
    }

    /// 按字数截断（错误串可能很长：SQLite 的 errmsg 会带上整条 SQL）。
    static func truncate(_ text: String, limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }
}
