//
//  NotificationsModule.swift
//  Gourd 内置模块 · 通知上岛（P2c 列表 + P2d 浮层）
//
//  设计依据：docs/09-features-and-mechanisms.md §5.5（本轮风险最高的一项）+ docs/12-p1-batches.md P2c。
//  P2c 交付 = 可行性探针 + 模块骨架 + 展开列表；**P2d 交付 = 折叠态瞬时浮层**（内核 `presentHUD`，
//  见 `Kernel/ModuleHUDWindow.swift` 与 13 号文档 D-22 / D-23）。
//
//  ## 数据源与权限
//  - 数据源：`~/Library/Group Containers/group.com.apple.usernoted/db2/db`（SQLite，**只读**，
//    见 `NotificationCenterReader`；schema 是私有的，Apple 改版即失效）；
//  - 权限：**需要完全磁盘访问**。该权限**无法程序化申请**，因此本模块不做任何授权弹窗：
//    读不到时只在面板上显示提示 + 一颗「打开系统设置」按钮（跳到隐私与安全性 → 完全磁盘访问）；
//  - **严禁**为了触发提示去读其它受保护路径（本机实测：通知库自身被拒即可判定）。
//
//  ## 能力边界（09 §5.5「必须接受」，UI 上有一行 footer 明示）
//  ① **AX 通道能真关掉系统通知，DB 通道只能从岛上移除**（2026-09-28 加 AX 通道后收窄的口径）：
//     浮层上的 × 命中 AX 横幅时执行「关闭」动作（`NotificationBannerObserver`），失败或没有
//     关闭控件时退化为「仅从岛上隐藏」；展开列表的 × 默认仍是**仅从岛上移除**
//     （本地隐藏 + `dismissedNotificationIDs` 持久化），只在近 10 秒内有同指纹的 AX 横幅句柄时
//     顺带真关那一条。库里一条记录都不动（只读原则）；
//  ② 需要完全磁盘访问（DB 通道）；AX 通道需要辅助功能权限（**调用方已具备**，未授权时静默降级）；
//  ③ 两条通道都可能随系统改版失效：DB 是 schema 私有，AX 是元素树/动作名随版本变
//     （探针原文落盘 `~/Library/Logs/Gourd/ax-banner-probe.log` 就是为此）；
//  ④ 内容敏感：浮层**默认显示正文**（`showBodyInHUD` 默认 true——**用户 2026-09-28 口径，
//     覆盖设计稿原口径的 false**）；不想要正文的用户在设置页（Live Activities → Notifications）
//     关掉该项即可，关掉后浮层第二行只留「新通知」。
//
//  ## 双通道口径（09 §5.5，2026-09-28 加 AX 通道后定稿）
//  | 通道 | 职责 | 代价 |
//  |---|---|---|
//  | **AX**（`NotificationBannerObserver`） | **实时**（横幅一出现就在屏上，实测亚秒级）+ **可真关闭** | 依赖通知中心的 AX 树（role/subrole/自定义动作名），随系统版本可能失效 |
//  | **DB**（`NotificationCenterReader`） | **历史列表**、未读计数、点击打开 App、**降级**（AX 不可用时浮层照弹） | 实时性受 macOS 批量落盘延迟限制（本机实测 5.0～5.1s） |
//  两条通道会为同一条通知各触发一次 → 用「appName + title + body 指纹 + 10s 窗口」去重
//  （`NotificationBannerLedger`，**AX 优先**）：AX 先到弹了浮层，5s 后 DB 那条同指纹事件
//  在窗口期内不再弹浮层、只进列表；AX 没拿到（未授权 / 树变了）时 DB 照常弹，两条都不断。
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
//  **AX 通道不需要任何新设置键**：去重窗口与轮询间隔都是代码常量
//  （`NotificationBannerLedger.window` = 10s、`NotificationBannerObserver.pollInterval` = 0.5s）。
//  09 §5.5 里**尚未做**的部分：按 App 分组、`appsFilter` 黑白名单。
//
//  ## 本批形态
//  - 展开面板：标题行（模块名 + 状态 + **清除**（列表非空时）+ 刷新）+ 可滚动通知列表
//    （点击左侧内容 → 打开对应 App；行右侧 `xmark.circle.fill` → **关闭这一条，仅从岛上移除**；
//    近 10 秒内有同指纹的 AX 横幅句柄时顺带真关掉那条系统通知）
//    + 一行能力边界说明；
//  - 折叠态**瞬时浮层**：通知到达时 `bell.badge` + App 名 + 标题/正文 + **×**，4s 后自动消失
//    （内核 `ModuleRegistry.presentHUD`；一次取数多条新通知只弹最新一条）。
//    **两条来源**：AX 横幅（实时，× 可真关）/ DB 增量（降级，× 只从岛上隐藏）；
//    × 走 `.highPriorityGesture`（同一层上压过祖先的 `openNotch()` 普通手势，见
//    `NotificationHUDView` 的手势优先级说明），点掉后调 `UIHandle.dismissTransient()` **立刻**撤浮层
//    （内核 `ModuleRegistry.dismissHUD(id:)`），不等 ttl；
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
//  `.hoursAgo` / `.daysAgo` / `.readOnlyNote` / `.newNotification` / `.clearAll` / `.dismiss` /
//  `.closeSystemNotification`（AX 通道真关闭时浮层 × 的提示文案）。
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

    /// 双通道去重台账（AX + DB）：同指纹 10s 内只弹一次浮层，并短期保留 AX 的真关闭句柄。
    /// **纯逻辑**（时间由调用方注入）——判定规则全在 `NotificationBannerLedger` 里，可单测。
    private var ledger = NotificationBannerLedger()

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
            let resolved = resolveAppNames(for: [latest]).first ?? latest
            // 去重（**AX 优先**）：AX 通道刚为同一条通知弹过浮层时，这条晚到约 5s 的 DB 记录
            // 在 10s 窗口内不再弹浮层——但仍进列表与未读计数（列表归 DB 通道管）。
            if shouldPresentDatabaseItem(resolved) {
                presentHUD?(resolved)
            } else {
                log.info("浮层跳过（10s 内已有同指纹的 AX 浮层）：rec_id=\(resolved.id)")
            }
        }
    }

    // MARK: 双通道（AX 实时 / DB 降级）的接缝

    /// **纯函数**：一条 DB 通知对应的去重指纹（`appName + title + body`，归一化在指纹里做）。
    static func fingerprint(for item: NotificationItem) -> NotificationFingerprint {
        NotificationFingerprint(appName: item.displayName, title: item.title, body: item.body)
    }

    /// AX 横幅是否该弹浮层（顺手把真关闭句柄登记进窗口，供列表行 × 复用）。
    ///
    /// 口径：同一指纹 10s 内只弹一次（两条通道共用一个窗口），**AX 优先**
    /// （AX 命中后同指纹的 DB 事件在窗口期内只进列表）。
    func shouldPresentBanner(_ event: BannerEvent, now: Date = Date()) -> Bool {
        ledger.shouldPresent(
            event.fingerprint,
            source: .ax,
            closeHandle: event.closeHandle,
            now: now
        )
    }

    /// DB 增量是否该弹浮层（与 AX 通道同一把尺子；DB 没有句柄，故只登记来源）。
    func shouldPresentDatabaseItem(_ item: NotificationItem, now: Date = Date()) -> Bool {
        ledger.shouldPresent(Self.fingerprint(for: item), source: .database, now: now)
    }

    /// 近 10 秒内该条通知对应的 AX 真关闭句柄（`nil` = 没有 / 已过期 / 是 DB 来源的那一条）。
    ///
    /// 已过期的句柄不会返回；返回的句柄也可能在执行时失效（横幅早已自动消失）——
    /// 那种情况由 `performAndVerify()` 判负，调用方只记日志、退化为「仅从岛上隐藏」。
    func closeHandle(for item: NotificationItem, now: Date = Date()) -> NotificationBannerCloseHandle? {
        ledger.closeHandle(for: Self.fingerprint(for: item), now: now)
    }

    /// **真关闭一条系统通知**（AX 动作，**必须在后台队列执行**：AX 是同步 IPC）。
    ///
    /// 成功 = 动作返回成功且元素失效（见 `NotificationBannerCloseHandle.performAndVerify`）。
    /// 失败**不弹错误**：只记一条日志，浮层/列表那边已经做了「仅从岛上隐藏」。
    func closeSystemBanner(_ handle: NotificationBannerCloseHandle, reason: String) {
        let log = self.log
        DispatchQueue.global(qos: .utility).async {
            let closed = handle.performAndVerify()
            if closed {
                log.info("\(reason)：已真关掉系统通知（\(handle.label)）")
            } else {
                log.warn("\(reason)：关闭系统通知失败（\(handle.label)），仅从岛上隐藏")
            }
        }
    }

    /// 面板打开：未读数清零（「自上次打开面板以来」的口径）。
    func markPanelOpened() {
        guard unseenCount != 0 else { return }
        unseenCount = 0
    }

    // MARK: 关闭 / 清除（**岛上移除为主，命中 AX 句柄时一并真关**）

    /// 关闭一条：立即从列表里去掉 + 记进「已关闭」集合 + 落盘。
    ///
    /// **岛上行为不变**（本地隐藏 + `dismissedNotificationIDs` 持久化，库里一条不动）。
    /// 增量部分（2026-09-28）：若该条与**近 10 秒内的 AX 横幅**指纹匹配且仍有可用的关闭句柄，
    /// 一并执行 AX 关闭动作**真关掉系统通知中心里的那一条**——这是「能真正关掉系统通知」的
    /// 列表侧入口（浮层侧的入口是浮层右上角的 ×）。匹配不到 / 句柄失效 → 只隐藏，不报错。
    func dismiss(_ item: NotificationItem) {
        let handle = closeHandle(for: item)
        guard !dismissedRecordIDs.contains(item.id) else {
            items.removeAll { $0.id == item.id }  // 已在集合里（例如上一次运行关过）：只保证列表里没有
            return
        }
        dismissedOrder.append(item.id)
        dismissedRecordIDs.insert(item.id)
        items.removeAll { $0.id == item.id }
        persistDismissed()
        log.info("关闭通知 rec_id=\(item.id)，仅从岛上移除（系统通知中心不动）")
        if let handle {
            closeSystemBanner(handle, reason: "列表关闭 rec_id=\(item.id)")
        }
    }

    /// 一键清除：把**当前列表**里的条目全部标记为已关闭（等价于逐条关闭，一次落盘一次日志）。
    ///
    /// **只从岛上移除**（不逐条 AX 关闭）：用户点「清除」的语义是「把岛上这一屏清掉」，
    /// 不是「把系统通知中心清空」——多条真关闭会连续打十几个 AX 动作，且清单里多数条目
    /// 早就过了 10s 窗口（句柄已失效）。要真关某一条，用该行的 × 或浮层的 ×。
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
    /// AX 横幅通道（**实时 + 可真关闭**那条路，见文件头「双通道口径」）。
    /// `bannerCancel` 是 `start()` 的取消闭包（拆 AXObserver + 轮询 timer），`bannerObserver`
    /// 只为持有它——模块停用/重新激活都走 `deactivate()` → `startBannerObservation()`。
    private var bannerObserver: NotificationBannerObserver?
    private var bannerCancel: (() -> Void)?
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
        startBannerObservation()
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
            "notifications 模块已激活（AX 横幅实时通道 + db/db-wal 文件事件驱动 + 兜底轮询 "
                + "\(Int(NotificationStore.fallbackPollInterval))s）"
        )
    }

    func deactivate() async {
        pollTask?.cancel()
        pollTask = nil
        store.stopWatching()
        // AX 通道也要拆干净：observer 的 run loop source 与轮询 timer 都归这个闭包管，
        // 不拆的话模块停用后 handler 还活着（会继续扫窗口、继续弹浮层）。
        bannerCancel?()
        bannerCancel = nil
        bannerObserver = nil
    }

    /// 起 AX 横幅通道（**实时 + 可真关闭**那条路，见文件头「双通道口径」）。
    ///
    /// - 未授权（`AXIsProcessTrusted() == false`）时 `start()` 返回空闭包、记一条日志，
    ///   模块侧什么都不用管：DB 通道照常弹浮层（只是慢 ~5s），这是**静默降级**；
    /// - 回调在主队列（`@MainActor` 的 store 直接可写），每次只做「去重 → 弹浮层」。
    private func startBannerObservation() {
        guard bannerObserver == nil else { return }
        let observer = NotificationBannerObserver { [weak self] event in
            self?.handleBanner(event)
        }
        bannerObserver = observer
        bannerCancel = observer.start()
    }

    /// AX 横幅到达（**这条路径不碰数据库**：列表与历史仍归 DB 通道）。
    ///
    /// 去重：同指纹 10s 内只弹一次（`NotificationBannerLedger`，AX 优先）。
    private func handleBanner(_ event: BannerEvent) {
        guard store.shouldPresentBanner(event) else {
            context.logger.info("AX 横幅跳过浮层（10s 内已有同指纹）：title=\(event.title)")
            return
        }
        presentBannerHUD(event)
    }

    /// 弹一条通知浮层（`store.presentHUD` 的唯一消费者）。
    ///
    /// 视图在**这一刻**按当前设置快照构造：`showBodyInHUD` 是模块配置的呈现口径，
    /// 浮层只活 `hudTTL` 秒，不需要为它维护一条「设置改了要重渲」的观察链。
    private func presentNotificationHUD(for item: NotificationItem) {
        let showsBody = Defaults[.showBodyInHUD]
        let handle = store.closeHandle(for: item)
        let ui = context.ui
        context.logger.info("弹通知浮层（DB）：rec_id=\(item.id)，正文\(showsBody ? "显示" : "隐藏")")
        context.ui.presentTransient(
            view: AnyView(
                NotificationHUDView(
                    appName: Self.hudAppName(for: item),
                    title: item.title,
                    bodyText: item.body,
                    showsBody: showsBody,
                    closeHelpKey: handle == nil ? "module.notifications.dismiss" : "module.notifications.closeSystemNotification",
                    onClose: { [store, ui] in
                        // ① **内核侧撤浮层（先做）**：注册表里那一条被清掉 → 浮层窗口淡出
                        //   （D-23 后浮层是独立窗口，`isHidden` 只是让卡片当场变空的那一帧；
                        //   真正让浮层消失的是这一步）。
                        ui.dismissTransient()
                        // ② 真关闭（AX 动作，`closeSystemBanner` 甩到后台队列）：没有句柄时
                        //    这一步就是「仅从岛上隐藏」的前一半，退化为空操作。
                        guard let handle else { return }
                        store.closeSystemBanner(handle, reason: "浮层关闭 rec_id=\(item.id)")
                    }
                )
            ),
            ttl: Self.hudTTL
        )
    }

    /// AX 横幅浮层（**实时路径**）：内容直接来自横幅，不查库、不等落盘。
    ///
    /// × 的口径：有句柄 → 真关掉系统通知；没有 → 仅从岛上隐藏（内核侧撤掉浮层后浮层窗口
    /// 当场淡出，两条路都是「点完立刻看不见」）。
    private func presentBannerHUD(_ event: BannerEvent) {
        let showsBody = Defaults[.showBodyInHUD]
        let ui = context.ui
        context.logger.info(
            "弹通知浮层（AX）：app=\(event.appName)，标题=\(event.title)，正文\(showsBody ? "显示" : "隐藏")"
        )
        context.ui.presentTransient(
            view: AnyView(
                NotificationHUDView(
                    appName: event.appName,
                    title: event.title,
                    bodyText: event.body,
                    showsBody: showsBody,
                    closeHelpKey: event.closeHandle == nil ? "module.notifications.dismiss" : "module.notifications.closeSystemNotification",
                    onClose: { [store, ui] in
                        // 与 DB 路径同口径：内核侧撤浮层在前（窗口随即淡出），真关闭在后。
                        ui.dismissTransient()
                        guard let handle = event.closeHandle else { return }
                        store.closeSystemBanner(handle, reason: "浮层关闭 AX 横幅")
                    }
                )
            ),
            ttl: Self.hudTTL
        )
    }

    /// 浮层左上的 App 名：`NSWorkspace` 解析出的显示名优先，退回 bundle id 最后一段
    /// （与 `NotificationHUDView.appName` 的兜底链同口径）。
    private static func hudAppName(for item: NotificationItem) -> String {
        if !item.appName.isEmpty { return item.appName }
        let fallback = NotificationCenterReader.appDisplayName(bundleIdentifier: item.bundleIdentifier, appMap: [:])
        return fallback.isEmpty ? item.displayName : fallback
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

/// 浮层卡片的尺寸口径（**纯函数**，单测直接钉边界）。
///
/// 为什么需要它：浮层改由内核的独立窗口渲染（D-23）之后，尺寸不再由刘海宽度决定，
/// 而是由「用户设置的倍率 `notificationHUDScale`（默认 1.3）+ 卡片自己的上界」决定——
/// 把这条算式从视图里抽出来，边界（0.8 / 2.0）才有地方钉住。
///
/// 取值口径：
/// - **倍率夹取**到 0.8…2.0（用户直接改 UserDefaults 写了个离谱值时也有确定呈现）；
/// - 所有尺寸 = 基准值 × 倍率，**保留两位小数**（避免 0.8 × 12 = 9.600000000000001 这类
///   浮点尾巴，也让 `Equatable` 与单测的等值断言有意义）；
/// - 卡片总宽 = `textMaxWidth` + 图标 + 两个间距 + × + 两侧内边距，其中 `textMaxWidth` 由
///   「卡片最大宽度 − 其它元素」反推（不是独立常量），因此改任一项都不会撑破卡片；
/// - **`cardMaxWidth` 有绝对上限** `cardMaxWidthCeiling`：倍率 2.0 时卡片已经接近半屏宽，
///   再宽就该改布局而不是继续放大。
enum NotificationHUDCardLayout {
    /// 倍率的可用区间（与设置滑块 `Slider(value:in: 0.8...2.0)` 同源）。
    static let scaleRange: ClosedRange<Double> = 0.8...2.0

    /// 基准值（倍率 = 1.0 时的一档；都按「独立窗口里的浮层」重新定过，不再是刘海尺寸）。
    private enum Base {
        static let icon: CGFloat = 14
        static let title: CGFloat = 12
        static let body: CGFloat = 11
        static let close: CGFloat = 11
        static let padding: CGFloat = 10
        static let iconSpacing: CGFloat = 8
        static let lineSpacing: CGFloat = 2
        static let cornerRadius: CGFloat = 10
        /// 卡片最大宽度的基准：刘海屏收窄一档（浮层挂在刘海正下方，太宽会横跨整条菜单栏），
        /// 非刘海屏给到 360pt（用户 2026-09-28 反馈「外接屏太小」的落点）。
        static let cardMaxWidthNotched: CGFloat = 320
        static let cardMaxWidthPlain: CGFloat = 360
        /// 文字列的下限宽度：任何倍率下都要能放下一行几个字，否则卡片会缩成一条。
        static let textMinWidth: CGFloat = 160
    }

    /// 卡片最大宽度的绝对上限（pt，倍率乘完再夹）。
    static let cardMaxWidthCeiling: CGFloat = 480

    struct Metrics: Equatable {
        let iconSize: CGFloat
        let titleSize: CGFloat
        let bodySize: CGFloat
        let closeSize: CGFloat
        /// 卡片四周的内边距（卡片背景与内容之间）。
        let padding: CGFloat
        /// 图标与文字列之间的间距。
        let iconSpacing: CGFloat
        /// 文字列两行之间的间距。
        let lineSpacing: CGFloat
        /// 文字列的最大宽度：超出即按 `lineLimit(2)` 截断。
        let textMaxWidth: CGFloat
        /// 卡片整体最大宽度（含内边距）。
        let cardMaxWidth: CGFloat
        let cornerRadius: CGFloat
    }

    /// 给定倍率与「是否刘海屏」→ 卡片尺寸。`isNotchScreen` 只影响卡片最大宽度的基准档。
    static func metrics(scale: Double, isNotchScreen: Bool) -> Metrics {
        let s = CGFloat(min(max(scale, scaleRange.lowerBound), scaleRange.upperBound))

        let icon = round2(Base.icon * s)
        let title = round2(Base.title * s)
        let body = round2(Base.body * s)
        let close = round2(Base.close * s)
        let padding = round2(Base.padding * s)
        let iconSpacing = round2(Base.iconSpacing * s)
        let lineSpacing = round2(Base.lineSpacing * s)
        let cornerRadius = round2(Base.cornerRadius * s)

        let baseCardMax = isNotchScreen ? Base.cardMaxWidthNotched : Base.cardMaxWidthPlain
        let cardMaxWidth = round2(min(baseCardMax * s, cardMaxWidthCeiling))
        let textMaxWidth = max(
            round2(cardMaxWidth - (padding * 2 + icon + iconSpacing * 2 + close)),
            Base.textMinWidth
        )

        return Metrics(
            iconSize: icon,
            titleSize: title,
            bodySize: body,
            closeSize: close,
            padding: padding,
            iconSpacing: iconSpacing,
            lineSpacing: lineSpacing,
            textMaxWidth: textMaxWidth,
            cardMaxWidth: cardMaxWidth,
            cornerRadius: cornerRadius
        )
    }

    /// 保留两位小数（口径见类型文档）。
    private static func round2(_ value: CGFloat) -> CGFloat {
        (value * 100).rounded() / 100
    }
}

/// 折叠态瞬时浮层（09 §5.5 呈现 ①）：`bell.badge` + 「App 名」+ 「标题 + 正文」+ **×**。
///
/// **两个来源共用这一个视图**（内容都是纯字符串，不依赖 `NotificationItem`）：
/// - AX 横幅（实时通道，`presentBannerHUD`）：× 有真关闭句柄 → 执行 AX 关闭动作；
/// - DB 增量（降级通道，`presentNotificationHUD`）：× 没有句柄 → 仅从岛上隐藏。
///
/// **默认显示正文**（`showBodyInHUD` 默认 true——用户 2026-09-28 明确要求，覆盖设计稿原口径的
/// false）；关掉后第二行只留一条「新通知」文案，正文仍可在展开列表里看。
///
/// 颜色：渲染在**独立窗口**里（窗口透明、桌面/任意 App 在后），文字**一律显式浅色**
///（`.white` / `.white.opacity(...)`）并自带深色圆角底 —— 不用 `.primary` / `.secondary`
///（那会随系统外观变成深色字，浮在浅色壁纸上就看不见了）。
///
/// 尺寸：字号 / 图标 / 内外边距 / 卡片最大宽度**全部**来自
/// `NotificationHUDCardLayout.metrics(scale:isNotchScreen:)`（用户设置 `notificationHUDScale`，
/// 默认 1.3）。**不再有「必须塞进 189pt 刘海」这一条**——那是关闭态链内渲染时期的约束
/// （`presentNotificationHUD` 的旧注释与 docs/13 已知限制 27 都已回写）。
///
/// 「仅从岛上隐藏」的落点：`isHidden` 让这一格**立刻**渲染成空，并配合 `UIHandle.dismissTransient()`
/// 把浮层从内核撤掉（内核撤 → 浮层窗口淡出，所以是本视图与窗口一起消失，不只是这一格变空）。
///
/// ## × 的手势优先级（2026-09-28 修正；D-23 后仍保留）
/// 关闭态时期 × 收不到点击的根因是**祖先**的 `.onTapGesture { openNotch() }` 先吃掉了事件。
/// 浮层搬进独立窗口后祖先手势已不在同一条链上，但 `.highPriorityGesture` 保留：换来的是
/// 「窗口内任何一层再挂普通手势也不会抢走 ×」这条稳定性，成本为零。
private struct NotificationHUDView: View {
    let appName: String
    let title: String
    /// 通知正文（**不叫 `body`**：那个名字被 SwiftUI 的 `View.body` 占了）。
    let bodyText: String
    /// `Defaults[.showBodyInHUD]`（在模块侧取一次快照）。
    let showsBody: Bool
    /// × 的提示文案 key：有真关闭句柄时是「关闭系统通知」，否则是「关闭（仅从岛上移除）」。
    let closeHelpKey: String
    /// 点击 ×：真关闭（有句柄时）——**「仅从岛上隐藏」由本视图的 `isHidden` 自己完成**。
    let onClose: () -> Void

    /// 点过 × 之后不再渲染这一格（浮层 ttl 到期后内核自然清掉它）。
    @State private var isHidden = false
    @State private var isCloseHovered = false

    /// 尺寸倍率（用户设置）。浮层只活 4s，不需要为它维护「设置改了要重渲」的观察链——
    /// 每次弹出时取一次当前值即可（同 `showsBody` 的口径）。
    @Default(.notificationHUDScale) private var scale: Double

    var body: some View {
        if isHidden {
            EmptyView()
        } else {
            content
        }
    }

    /// 当前这一档尺寸。`isNotchScreen` 按**内核窗口宿主的取屏规则**（鼠标所在屏）判定：
    /// 浮层窗口正是落在那一块屏上，两者由同一条规则保证一致。判错也只是卡片最大宽度差
    /// 一档（320 vs 360 基准），不影响可读性。
    private var metrics: NotificationHUDCardLayout.Metrics {
        NotificationHUDCardLayout.metrics(scale: scale, isNotchScreen: Self.isNotchScreenUnderMouse)
    }

    private var content: some View {
        let card = metrics
        return HStack(spacing: card.iconSpacing) {
            Image(systemName: "bell.badge")
                .font(.system(size: card.iconSize, weight: .medium))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: card.lineSpacing) {
                Text(appName)
                    .font(.system(size: card.titleSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(secondLine)
                    .font(.system(size: card.bodySize))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            // 文字列的上界由卡片最大宽度反推（见 `NotificationHUDCardLayout`）：超出的部分
            // 按 `lineLimit` 截断，× 永远留在卡片内。
            .frame(maxWidth: card.textMaxWidth, alignment: .leading)

            closeButton(size: card.closeSize)
        }
        .padding(card.padding)
        .background(
            RoundedRectangle(cornerRadius: card.cornerRadius, style: .continuous)
                .fill(.black.opacity(0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: card.cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    /// 浮层当前落在的屏是否带刘海：**与 `ModuleHUDWindowHost.targetScreen()` 同一条规则**
    /// （鼠标所在屏 → 主屏），因此两者指向同一块屏。
    private static var isNotchScreenUnderMouse: Bool {
        let screen = ModuleHUDWindowHost.targetScreen()
        return (screen?.safeAreaInsets.top ?? 0) > 0
    }

    /// × ：**先本地隐藏（立刻生效）+ 内核撤浮层（窗口随之淡出），再交给上层做真关闭**——
    /// AX 动作是同步 IPC，放在点击回调里做会把主线程卡一下，所以上层（`closeSystemBanner`）
    /// 甩到后台队列。失败不弹错误：这一步已经不是「浮层消不消失」的前提了。
    ///
    /// 手势用 `.highPriorityGesture`（见类型文档）：按钮外观与动作体共用同一个 `dismiss()`。
    private func closeButton(size: CGFloat) -> some View {
        Button(action: dismiss) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(isCloseHovered ? 1 : 0.7))
                .padding(2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .highPriorityGesture(TapGesture().onEnded { dismiss() })
        .onHover { isCloseHovered = $0 }
        .help(NotificationText.localized(closeHelpKey))
    }

    /// × 的动作体（按钮与高优先级手势共用）。`isHidden` 既是「这一格立刻变空」的本地效果，
    /// 也充当**幂等闸**：两个入口在同一轮事件里都触发时只走一次（`onClose` 里的 AX 关闭
    /// 只该发一次）。
    private func dismiss() {
        guard !isHidden else { return }
        isHidden = true
        onClose()
    }

    /// 第二行：`showBodyInHUD` 为真时是「标题 + 正文」，否则是「新通知」这一行文案。
    private var secondLine: String {
        NotificationText.hudDetail(title: title, body: bodyText, showsBody: showsBody)
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
