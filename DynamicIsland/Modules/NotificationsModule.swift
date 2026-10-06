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
//  见 [14](../../docs/14-module-manifests.md) 的 notifications 行）。呈现口径都是**宿主设置**
//  （`Defaults.Keys`，设置页 Live Activities → Notification HUD）：
//  `showBodyInHUD`（默认 true：浮层是否显示正文）、`notificationHUDScale`（默认 1.3：字号 / 卡片
//  倍率）、**`notificationHUDDurationSeconds`**（默认 8：显示时长，见 `NotificationHUDPolicy`）、
//  **`enableNotificationHUD`**（总开关，默认 true：关掉后完全不弹浮层——列表与 AX / DB 通道照常）、
//  **`notificationHUDBackgroundStyle`**（默认 `.liquidGlass`：卡片底 = 液态玻璃 / 纯色）；
//  已关闭集合 `dismissedNotificationIDs` 也是宿主设置键（由本模块读写，上限 500）。
//  **AX 通道不需要任何新设置键**：去重窗口与轮询间隔都是代码常量
//  （`NotificationBannerLedger.window` = 10s、`NotificationBannerObserver.pollInterval` = 0.5s）。
//  09 §5.5 里**尚未做**的部分：按 App 分组、`appsFilter` 黑白名单。
//
//  ## 本批形态
//  - 展开面板：标题行（模块名 + 状态 + **清除**（列表非空时）+ 刷新）+ 可滚动通知列表
//    （点击左侧内容 → 打开对应 App **并收起刘海**；行右侧 `xmark.circle.fill` → **关闭这一条**：
//    近 10 秒内有同指纹的 AX 横幅句柄时**顺带真关掉那条系统通知**、否则只从列表移除；
//    结果由文案说清——悬停与无障碍标签按 `willAlsoCloseSystemBanner` 分档：
//    「同时关掉系统通知」/「从列表移除」，见 D-04 与 `docs/09` §5.5 的四格表）
//    + 一行能力边界说明；
//  - 折叠态**瞬时浮层**：通知到达时 `bell.badge` + App 名 + 标题/正文 + **×**，到期自动消失
//    （内核 `ModuleRegistry.presentHUD`；一次取数多条新通知只弹最新一条，其余在第二行末尾以
//    「等 N 条」计数交代）。**显示时长可配**（`notificationHUDDurationSeconds`，2026-09-28
//    用户反馈「显示时长太短」后从代码常量 4s 改为**默认 8s**，见 `NotificationHUDPolicy`）。
//    **固定尺寸**（320 × 64 × 用户倍率，内核 `ModuleHUDWindowHost` 定窗口、
//    本文件的 `NotificationHUDCardLayout` 定卡片，同一来源）：内容长短不跳；超长内容两行内截断，
//    完整正文看展开面板列表（口径见 `NotificationHUDView` 的「超长内容策略」）。
//    **多屏同时显示**（2026-09-28 用户反馈「应该是所有屏幕都显示才对」，内核 D-25）：
//    应用会显示岛的每块屏上各有一个浮层窗口，同一条浮层在所有屏同时出现 / 同时消失
//    （模块侧不用管——它只交一份视图）。
//    **两条来源**：AX 横幅（实时，× 可真关）/ DB 增量（降级，× 只从岛上隐藏）；
//    × 走 `.highPriorityGesture`（同一层上压过祖先的 `openNotch()` 普通手势，见
//    `NotificationHUDView` 的手势优先级说明），点掉后调 `UIHandle.dismissTransient()` **立刻**撤浮层
//    （内核 `ModuleRegistry.dismissHUD(id:)`），不等 ttl；
//    **卡片本体可点**（2026-09-29 用户反馈「直接点消息不能弹出对应的应用」）：整块卡片是
//    「打开对应 App（`activates = true`，把目标 App 带到前台）+ 撤浮层」的点击区，
//    动作与顺序收在 `NotificationClickPolicy.hudCard`（普通 `.onTapGesture`；× 是内部 Button，
//    会吃掉落在它身上的点击，故点 × 不会触发本体动作）。AX 通道没有 bundle id（`BannerEvent`
//    只有 App 名），按名反查（`bundleIdentifier(forAppName:in:runningApps:)`）后走同一条打开路径；
//  - 折叠态中央槽位：`bell` 图标 + 自上次打开面板以来的新增条数（内存态，0 时无数字）。
//    **注意**：中央槽位当前由 todos（order 20）占用，本模块（order 40）只是候选之一，
//    在默认配置下这个视图不会被渲染（`ModuleRegistry.compactSlotContent()` 只转发第一个候选）；
//  - **首页块**（T1，`surfaces` 的第三个取值）：标题行「通知 · 最近 N 条」+ 最近 3 条
//    （每行「App 名 · 标题」，单行尾部截断；**N = 列表里的条数**，与展开 tab 同源，
//    **不是**折叠态铃铛那个「自上次打开面板以来的新增数」）+ 不可读 / 无权限时的一行提示，
//    **只读**——点一行 = 打开对应 App + 收起刘海，不做关闭 / 清除 / 回复；
//    行数上限固定 3、不按块宽分档（见 `NotificationsHomeBlockView`）。
//
//  ## 颜色（本项目已踩过两次的坑）
//  面板是黑底、系统外观可为浅色——本模块所有文字与图标**一律显式浅色**
//  （`Color.white` / `.white.opacity(...)`），不用 `.primary` / `.secondary`。
//  浮层卡片的底也是同一条链的延伸（2026-09-28）：**默认液态玻璃**（`notificationHUDBackgroundStyle`
//  = `.liquidGlass`）时，玻璃在**浅色系统外观**下会渲染成浅色，白字就看不清了——因此
//  ① 窗口层面强制 `darkAqua`（`ModuleHUDWindowHost.ensureSlot`，口径同 `EditPanelView` 对
//  `hudWindow` 材质的处理）、② 玻璃内容上再压一层 `Color.black.opacity(0.35)`。
//
//  文案走 Localizable key：`module.notifications.name` / `.summary` / `.empty` /
//  `.needsFullDiskAccess` / `.openSettings` / `.recent` / `.justNow` / `.minutesAgo` /
//  `.hoursAgo` / `.daysAgo` / `.readOnlyNote` / `.newNotification` / `.clearAll` / `.dismiss`（浮层 ×
//  无句柄时的「关闭」）/
//  `.closeSystemNotification`（**有句柄时浮层 × 与列表行 × 共用**的「同时关掉系统通知」）/
//  `.removeFromList`（列表行 × 无句柄时的「从列表移除」，D-04）/
//  `.moreCount`（一次多条新通知时浮层第二行末尾的计数后缀，`and %d more` / `等 %d 条`）/
//  `.homeRecent`（首页块标题行的条数口径，`Notifications · %d recent` / `通知 · 最近 %d 条`；
//  0 条时不带这个后缀，标题行只剩 `.name`）/
//  `.homeNeedsPermission` / `.homeUnreadable`（首页块在无权限 / 不可读时标题行下的那一行提示）。
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
    ///
    /// 第二个入参是**除这一条之外还有几条新通知**（0 = 没有）：一次取数多条时浮层只展示最新
    /// 一条，其余几条由模块在第二行末尾以「等 N 条」交代（09 §5.5：不刷屏）。
    var presentHUD: ((NotificationItem, Int) -> Void)?

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
                // 除展示的这条之外还有几条：浮层第二行末尾以「等 N 条」交代（不逐条排队弹）。
                presentHUD?(resolved, max(newItems.count - 1, 0))
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

    /// 列表行 × 的**唯一一份判据**：这一刻命中的真关闭句柄（`nil` = 只从列表移除）。
    ///
    /// 行为侧（`dismiss` 真的拿它去关）与文案侧（`willAlsoCloseSystemBanner` 只问真假）都调这一个
    /// 函数——判据不复制第二份，文案与行为因此不会各说各话（D-04）。
    /// 判据本体仍在 `closeHandle(for:now:)` → `NotificationBannerLedger`（近 10s 同指纹窗口）。
    private func listRowCloseHandle(for item: NotificationItem, now: Date = Date()) -> NotificationBannerCloseHandle? {
        closeHandle(for: item, now: now)
    }

    /// **只读谓词**（D-04，文案专用）：列表行的 × 这一刻是否**也会真关掉系统通知**。
    ///
    /// 与 `dismiss` 里的那条判据**同一份**（`listRowCloseHandle`）——列表行 × 的文案按它分档：
    /// 真 → 「同时关掉系统通知」，假 → 「从列表移除」。
    /// **只查不改**：除台账自身的过期清理（`prune`）外不碰任何状态，因此视图在 body / `.help()`
    /// 里直接读它是安全的（不触发 `objectWillChange`）。
    ///
    /// 口径边界（如实说）：它回答的是**查询这一刻**的答案，句柄随 10s 窗口过期。
    /// `.help()` 的文案在视图渲染时求值一次，之后不会因为窗口过期而自己刷新——
    /// 渲染与悬停之间跨过了窗口边界时，文案可能比行为乐观（`docs/09` §5.5 的四格表）。
    func willAlsoCloseSystemBanner(for item: NotificationItem, now: Date = Date()) -> Bool {
        listRowCloseHandle(for: item, now: now) != nil
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
    ///
    /// 判据取自 `listRowCloseHandle`——**与文案谓词 `willAlsoCloseSystemBanner` 同一份**：
    /// 行内文案说「同时关掉系统通知」时，这里就一定拿得到句柄去关。
    func dismiss(_ item: NotificationItem) {
        let handle = listRowCloseHandle(for: item)
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
        openApp(bundleIdentifier: item.bundleIdentifier, label: "rec_id=\(item.id)")
    }

    /// 打开「某 App 名」对应的应用（**AX 通道的浮层卡片专用**）。
    ///
    /// `BannerEvent` 只有 App 名、没有 bundle id（见 `NotificationBannerParser`），因此按名反查
    /// （`bundleIdentifier(forAppName:in:runningApps:)`）后走**同一条**打开路径。反查不到时**不打开**：
    /// 打开一个同名的别的 App 比不打开更糟。
    func openApp(appNamed name: String) {
        guard let bundleID = Self.bundleIdentifier(
            forAppName: name,
            in: items,
            runningApps: Self.runningAppCandidates()
        ) else {
            log.warn("打开跳过：按 App 名「\(name)」解析不到 bundleIdentifier（AX 通道）")
            return
        }
        openApp(bundleIdentifier: bundleID, label: "app=\(name)")
    }

    /// **纯函数**：按 App 显示名反查一个可用的 bundle id（两条来源，**不猜**）。
    ///
    /// ① 列表里同名条目的 `bundleIdentifier`（列表来自 DB，带 bundle id）；
    /// ② 运行中 App 的候选（`runningApps`，由调用方取 `NSWorkspace`）——能弹通知的 App 必然
    ///    在运行，① 落空时（DB 还没落盘、列表为空）它几乎总能命中；判据是**本地化名**或
    ///    **包文件名**（`/Applications/Safari.app` → `Safari`，两者对不同 App 各有可能对上横幅
    ///    给的 App 名）。
    /// 两条都落空返回 nil。运行中 App 走形参注入（不是就地读 `NSWorkspace`）：这条函数因此
    /// 可以在单测里喂构造的候选，不受开发机上跑着什么影响。
    static func bundleIdentifier(
        forAppName name: String,
        in items: [NotificationItem],
        runningApps: [(localizedName: String?, bundleFileName: String?, bundleIdentifier: String?)] = []
    ) -> String? {
        guard !name.isEmpty else { return nil }
        if let match = items.first(where: { $0.appName == name || $0.displayName == name }),
           !match.bundleIdentifier.isEmpty {
            return match.bundleIdentifier
        }
        for app in runningApps where app.localizedName == name || app.bundleFileName == name {
            if let bundleID = app.bundleIdentifier, !bundleID.isEmpty { return bundleID }
        }
        return nil
    }

    /// 运行中 App 的候选三元组（`bundleIdentifier(forAppName:in:runningApps:)` 的默认来源）。
    static func runningAppCandidates()
        -> [(localizedName: String?, bundleFileName: String?, bundleIdentifier: String?)] {
        NSWorkspace.shared.runningApplications.map {
            ($0.localizedName, $0.bundleURL?.deletingPathExtension().lastPathComponent, $0.bundleIdentifier)
        }
    }

    /// 打开的核心（列表行与浮层卡片共用）：解析 App 包 → 打开。
    ///
    /// `activates = true`（2026-09-29 显式写出）：点通知的目的就是「去那个 App 看看」，
    /// 目标 App 必须被带到前台——这也是用户反馈「点消息不能弹出对应的应用」的一半诉求
    /// （另一半是卡片本体此前没有点击处理器）。开关（`configuration.activates`）默认就是 true，
    /// 写出来是为了不让它被后续改动顺手带走。
    private func openApp(bundleIdentifier: String, label: String) {
        guard !bundleIdentifier.isEmpty else {
            log.warn("打开跳过：没有 bundleIdentifier（\(label)）")
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            log.warn("打开跳过：解析不到 App（\(bundleIdentifier)，\(label)）")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        log.info("打开 App \(bundleIdentifier)（\(label)，activates=true）")
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [log] _, error in
            if let error {
                log.warn("打开 App \(bundleIdentifier) 失败：\(String(describing: error))")
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

// MARK: - 浮层时序策略

/// 浮层**显示时长**的纯策略（2026-09-28 用户反馈「显示时长太短」）：设置值 → ttl 的唯一映射点。
///
/// 为什么要单独抽出来：ttl 有两个口径必须一致——**用户设置**（`notificationHUDDurationSeconds`，
/// 默认 8s）与**内核夹取**（`ModuleRegistry.hudTTLRange`，1…15s）。映射写成纯函数后，
/// 边界（1 / 8 / 15 / 20）由单测直接钉，两条通道（AX / DB）也共用同一个出口、不会各算一份。
enum NotificationHUDPolicy {
    /// 设置滑块的可用区间（秒）——与 `Defaults.Keys.notificationHUDDurationSeconds` 的语义同源
    /// （设置页滑块 `Slider(value:in: 2...15, step: 1)` 用的是这一个常量，避免两处各写一份）。
    /// **下界 2s**：滑块不必为用户提供「1s」这种看不见的档位（内核的下界仍是 1s，防的是
    /// 直接改 UserDefaults 写个 0.2 这种值）。
    static let durationRange: ClosedRange<Double> = 2...15

    /// **纯函数**：设置里的显示时长（秒）→ 浮层 ttl（秒），夹取到 `ModuleRegistry.hudTTLRange`。
    ///
    /// 夹取发生在**这一层**（而不是抛错 / 忽略）：用户直接改 UserDefaults 写了个 0.2 或 600，
    /// 也要有确定行为——0.2 → 1s（等于没弹的下界）、600 → 15s（不得变成常驻占位，D-22 的口径）。
    static func ttl(forSettingSeconds seconds: Double) -> TimeInterval {
        min(max(seconds, ModuleRegistry.hudTTLRange.lowerBound), ModuleRegistry.hudTTLRange.upperBound)
    }

    /// 生产路径入口：读当前设置 → 夹取后的 ttl。两条通道（AX / DB）都走这里。
    static func ttlFromDefaults() -> TimeInterval {
        ttl(forSettingSeconds: Defaults[.notificationHUDDurationSeconds])
    }
}

// MARK: - 点击动作序列

/// 一条通知被点开后要做的动作（**词汇表**，不是行为）。
///
/// 2026-09-29 用户反馈驱动：「直接点消息不能弹出对应的应用」（浮层卡片本体此前没有任何点击
/// 处理器）与「在消息面板点击消息后，刘海要自动收起」。
enum NotificationClickAction: Equatable {
    /// 打开通知对应的 App（`NotificationStore.openApp(...)`，配置 `activates = true`）。
    case openApp
    /// 请求宿主收起刘海（`UIHandle.requestCollapse()`）。
    case collapseNotch
    /// 撤掉本模块的瞬时浮层（`UIHandle.dismissTransient()`，立刻撤、不等 ttl）。
    case dismissTransient
}

/// 两处点击（列表行 / 浮层卡片）的**动作序列**与执行器。
///
/// 为什么把顺序写成数据而不是在两处各写一次调用：**顺序是契约**——
/// - 列表行必须「先开应用、再收起刘海」：收起会触发面板动画，顺序反过来会让前台切换被动画
///   延迟到面板收完之后（用户看到的是「点了半天没反应」）；
/// - 浮层卡片必须「先开应用、再撤浮层」，且**不做 `collapseNotch`**：浮层出现时刘海本就是
///   收起态（浮层是独立窗口，见 D-23），再请求收起是空操作、徒增一次日志。
/// 顺序写成数组后，两处的差异只剩数据，单测直接断言数组与执行顺序。
enum NotificationClickPolicy {
    /// 列表行：打开 App → 收起刘海。
    static let row: [NotificationClickAction] = [.openApp, .collapseNotch]
    /// 浮层卡片本体：打开 App → 撤浮层（**不动刘海**）。
    static let hudCard: [NotificationClickAction] = [.openApp, .dismissTransient]

    /// 按序执行动作。未提供的闭包按空操作跳过（生产路径两处都齐备；单测只喂关心的那几个）。
    static func run(
        _ actions: [NotificationClickAction],
        openApp: () -> Void = {},
        collapseNotch: () -> Void = {},
        dismissTransient: () -> Void = {}
    ) {
        for action in actions {
            switch action {
            case .openApp: openApp()
            case .collapseNotch: collapseNotch()
            case .dismissTransient: dismissTransient()
            }
        }
    }
}

/// 浮层呈现的**纯决策**（2026-09-28 用户要求「做一个配置项，要包含总开关、显示时长、
/// 背景设置（是否为液态玻璃模式）这些」）：总开关关掉 → 这一次**完全不弹**（`nil`）；
/// 否则把这一次要用的呈现口径打成一份快照交给视图。
///
/// 为什么是纯函数：`resolve` 是「总开关决定弹 / 不弹」这条判据的**唯一落点**，两条通道
/// （AX 横幅 / DB 增量）与单测共用它——不必起真窗口、也不必读开发机上的 UserDefaults。
/// 快照形态（而不是让视图自己读设置）沿用既有口径：浮层只活几秒，不值得为它维护一条
/// 「设置改了要重渲」的观察链，弹出那一刻读一次即可。
struct NotificationHUDPresentation: Equatable {
    /// `showBodyInHUD`：第二行是否显示标题 / 正文（false 只留「新通知」，正文看展开列表）。
    let showsBody: Bool
    /// `notificationHUDBackgroundStyle`：卡片底（液态玻璃 / 纯色）。
    let backgroundStyle: NotificationHUDBackgroundStyle

    /// **纯函数**：总开关关掉（`enabled == false`）→ `nil` = **不弹浮层**。
    ///
    /// 注意「不弹」的边界：只有浮层不弹。列表 / 未读计数 / AX 真关闭 / DB 增量取数都不看这个
    /// 开关（它们由模块自身的激活状态决定），因此用户在设置里关掉浮层**不会**让通知列表变空。
    static func resolve(
        enabled: Bool,
        showsBody: Bool,
        backgroundStyle: NotificationHUDBackgroundStyle
    ) -> NotificationHUDPresentation? {
        guard enabled else { return nil }
        return NotificationHUDPresentation(showsBody: showsBody, backgroundStyle: backgroundStyle)
    }

    /// 生产路径入口：读当前设置（总开关 / 正文 / 背景）。
    static func fromDefaults() -> NotificationHUDPresentation? {
        resolve(
            enabled: Defaults[.enableNotificationHUD],
            showsBody: Defaults[.showBodyInHUD],
            backgroundStyle: Defaults[.notificationHUDBackgroundStyle]
        )
    }
}

// MARK: - 模块

/// 通知上岛模块（09 §5.5）。
@MainActor
final class NotificationsModule: GourdModule {
    /// 静态元数据（06 §2.2 的本批子集）。
    ///
    /// - `surfaces`：`expanded`（通知列表）+ `compact`（bell + 未读数）+ `home`（首页块：
    ///   「通知 · 最近 N 条」+ 最近 3 条 + 不可读时一行提示，见 `NotificationsHomeBlockView`）；
    /// - `defaultPlacement`：`slot: .center` / `order: 40`——排在 todos（20）与 progress（30）之后，
    ///   因此**默认配置下拿不到中央槽位**（`compactSlotContent()` 只转发第一个候选）；
    ///   首页 strip 里模块块按同一个 `order` 排（todos 块在前、通知块在后）；
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
        surfaces: [.expanded, .compact, .home],
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

    init(context: ModuleContext) {
        self.context = context
        let store = NotificationStore(logger: context.logger)
        self.store = store
        // 浮层出口：store 只交「最新一条新增 + 还有几条」，视图（含 `showBodyInHUD` 的读值）
        // 与 ttl 在这里定。
        store.presentHUD = { [weak self] item, moreCount in
            guard let self else { return }
            self.presentNotificationHUD(for: item, moreCount: moreCount)
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
    /// 视图在**这一刻**按当前设置快照构造（`NotificationHUDPresentation.fromDefaults()`：总开关 /
    /// 正文 / 背景三项一次读齐），浮层只活 `NotificationHUDPolicy` 给的 ttl 秒，
    /// 不需要为它维护一条「设置改了要重渲」的观察链。
    /// `moreCount` 直接用 store 给的「同批还有几条」（0 = 单条到达）。
    ///
    /// **总开关关掉时在这里返回**（`presentation == nil`）：连 `presentTransient` 都不调——
    /// 浮层窗口不会上台，也**不会有任何一个新窗口被创建**。列表 / 未读计数 / 去重台账都不受影响
    /// （它们在 `refreshIncremental` 的前半段就完成了）。
    private func presentNotificationHUD(for item: NotificationItem, moreCount: Int) {
        guard let presentation = NotificationHUDPresentation.fromDefaults() else {
            context.logger.info("浮层跳过（总开关关闭 enableNotificationHUD=false）：rec_id=\(item.id)")
            return
        }
        let handle = store.closeHandle(for: item)
        let ui = context.ui
        context.logger.info(
            "弹通知浮层（DB）：rec_id=\(item.id)，正文\(presentation.showsBody ? "显示" : "隐藏")，"
                + "背景=\(presentation.backgroundStyle.rawValue)，同批另有 \(moreCount) 条"
        )
        context.ui.presentTransient(
            view: AnyView(
                NotificationHUDView(
                    appName: Self.hudAppName(for: item),
                    title: item.title,
                    bodyText: item.body,
                    showsBody: presentation.showsBody,
                    backgroundStyle: presentation.backgroundStyle,
                    moreCount: moreCount,
                    closeHelpKey: handle == nil ? "module.notifications.dismiss" : "module.notifications.closeSystemNotification",
                    // 卡片本体（2026-09-29 用户反馈「直接点消息不能弹出对应的应用」）：打开 App + 撤浮层。
                    onOpenApp: { [store] in store.openApp(for: item) },
                    onDismissTransient: { [ui] in ui.dismissTransient() },
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
            ttl: NotificationHUDPolicy.ttlFromDefaults()
        )
    }

    /// AX 横幅浮层（**实时路径**）：内容直接来自横幅，不查库、不等落盘。
    ///
    /// × 的口径：有句柄 → 真关掉系统通知；没有 → 仅从岛上隐藏（内核侧撤掉浮层后浮层窗口
    /// 当场淡出，两条路都是「点完立刻看不见」）。
    /// `moreCount` 恒为 0：AX 通道是「一条横幅一次回调」，不存在一批多条。
    ///
    /// **总开关与 DB 路径同一道闸门**（`NotificationHUDPresentation.fromDefaults()`）：关掉后
    /// AX 通道也完全不弹浮层。注意 `handleBanner` 已经先跑了去重台账（`shouldPresentBanner`），
    /// 因此关掉浮层期间同一条通知不会「攒着」在开回开关后又冒出来——台账早已记过它。
    private func presentBannerHUD(_ event: BannerEvent) {
        guard let presentation = NotificationHUDPresentation.fromDefaults() else {
            context.logger.info("浮层跳过（总开关关闭 enableNotificationHUD=false）：app=\(event.appName)")
            return
        }
        let ui = context.ui
        context.logger.info(
            "弹通知浮层（AX）：app=\(event.appName)，标题=\(event.title)，"
                + "正文\(presentation.showsBody ? "显示" : "隐藏")，背景=\(presentation.backgroundStyle.rawValue)"
        )
        context.ui.presentTransient(
            view: AnyView(
                NotificationHUDView(
                    appName: event.appName,
                    title: event.title,
                    bodyText: event.body,
                    showsBody: presentation.showsBody,
                    backgroundStyle: presentation.backgroundStyle,
                    moreCount: 0,
                    closeHelpKey: event.closeHandle == nil ? "module.notifications.dismiss" : "module.notifications.closeSystemNotification",
                    // AX 通道的卡片本体：`BannerEvent` 只有 App 名 → 按名反查 bundle id 后打开
                    // （反查不到就只撤浮层、不猜一个 App 打开）。
                    onOpenApp: { [store] in store.openApp(appNamed: event.appName) },
                    onDismissTransient: { [ui] in ui.dismissTransient() },
                    onClose: { [store, ui] in
                        // 与 DB 路径同口径：内核侧撤浮层在前（窗口随即淡出），真关闭在后。
                        ui.dismissTransient()
                        guard let handle = event.closeHandle else { return }
                        store.closeSystemBanner(handle, reason: "浮层关闭 AX 横幅")
                    }
                )
            ),
            ttl: NotificationHUDPolicy.ttlFromDefaults()
        )
    }

    /// 浮层左上的 App 名：`NSWorkspace` 解析出的显示名优先，退回 bundle id 最后一段
    /// （与 `NotificationHUDView.appName` 的兜底链同口径）。
    private static func hudAppName(for item: NotificationItem) -> String {
        if !item.appName.isEmpty { return item.appName }
        let fallback = NotificationCenterReader.appDisplayName(bundleIdentifier: item.bundleIdentifier, appMap: [:])
        return fallback.isEmpty ? item.displayName : fallback
    }

    /// 三个 surface 各给一份内容；未声明的 `lockscreen` 返回 `.none`（不占位、也不算失败）。
    ///
    /// 展开面板多交一条 `onCollapse`：列表行点击的「收起刘海」出口——模块**只调注入的
    /// `UIHandle`**（`requestCollapse()` → 应用侧注入的闭包），自己不碰窗口（06 §3.3 R1）。
    /// 每次取内容时新建闭包：`content(for:)` 由 `ModuleHostView` 在 body 里调用，闭包不会跨渲染留存。
    /// 首页块同理，多交一条 `onOpen`（点击一行 = 打开对应 App + 收起刘海）。
    func content(for request: ContentRequest) -> ModuleContent {
        switch request.surface {
        case .compact:
            return .view(AnyView(NotificationsCompactView(store: store)))
        case .expanded:
            return .view(AnyView(NotificationsModuleView(
                store: store,
                onCollapse: { [weak self] in
                    guard let self else { return }
                    // 日志与请求成对：实测（`log stream`）能按时间戳看到「先开 App、后收起刘海」。
                    self.context.logger.info("列表行点击：已打开 App，请求收起刘海（requestCollapse）")
                    self.context.ui.requestCollapse()
                }
            )))
        case .home:
            return .view(AnyView(NotificationsHomeBlockView(
                store: store,
                onOpen: { [weak self] item in self?.openHomeBlockItem(item) }
            )))
        case .lockscreen:
            return .none
        }
    }

    /// 首页块的一行被点开：**打开对应 App → 收起刘海**（`NotificationClickPolicy.row`——与展开面板的
    /// 列表行**同一条动作序列**，只有那两个动作、只有那个顺序：先开应用再收面板，
    /// 反了会让前台切换被收起动画拖后）。
    ///
    /// 与浮层卡片（`.hudCard` = 开应用 → 撤浮层）的差别只在第二个动作：首页块是**面板里**的块，
    /// 收的是面板；浮层是独立窗口，撤的是浮层本身。**不做**关闭 / 清除 / 回复（控制器裁决：
    /// 首页块只读，那些动作留在展开 tab）。
    private func openHomeBlockItem(_ item: NotificationItem) {
        let ui = context.ui
        let log = context.logger
        NotificationClickPolicy.run(
            NotificationClickPolicy.row,
            openApp: { store.openApp(for: item) },
            collapseNotch: {
                log.info("首页块点击：已打开 App，请求收起刘海（requestCollapse）")
                ui.requestCollapse()
            }
        )
    }
}

// MARK: - 展开面板视图

/// 展开面板（`NotificationsModuleView` 一族）的**字号档位表**（T3 / D-09）。
///
/// 17 处字号字面量 + 行内垂直内边距收在这一处（原来散在视图里），单测按表逐项钉死
/// （`testNotificationRowMetricsMatchTheBumpedSizes`）——用户反馈「消息面板字体太小」，
/// 本批主行 +2pt、次要 +1pt；失败态 / 空态 / 权限引导（同属展开页，留旧值会与放大后的
/// 列表行明显不一致）随后并表，按语义就近取档；以后调档只动这里。
///
/// **只服务展开面板**：首页通知块（`NotificationsHomeBlockView`，定高 96 内画 3 行）
/// 与 HUD 浮层卡片（`NotificationHUDCardLayout`，按用户倍率缩放）各自有自己的字号口径，
/// **不读这里**——放大首页块必裁（docs/30 备选⑩），两者与展开页是不同代码路径。
struct NotificationRowMetrics {
    /// 模块名「通知」。
    static let moduleName: CGFloat = 13
    /// 状态行（「最近 N 条」/「需要完全磁盘访问」/ 错误原因截断）。
    static let status: CGFloat = 12
    /// 「全部清除」胶囊文案。
    static let clearAll: CGFloat = 11
    /// 刷新图标（`arrow.clockwise`）。
    static let refresh: CGFloat = 12
    /// 行内来源 App 名。
    static let appName: CGFloat = 12
    /// 行内「·」分隔符。
    static let separator: CGFloat = 12
    /// 行内相对时间。
    static let timestamp: CGFloat = 11
    /// 行内标题。
    static let title: CGFloat = 13
    /// 行内正文。
    static let body: CGFloat = 12
    /// 行内 × 关闭按钮。
    static let dismissIcon: CGFloat = 11
    /// 脚注（只读能力边界说明）。
    static let footnote: CGFloat = 10
    /// 行内垂直内边距（3 → 4：字号变大后行距跟着松一点，行高随之变高）。
    static let rowVerticalPadding: CGFloat = 4

    // MARK: 状态块（失败态 / 空态 / 权限引导——与列表行同属展开页，T3 修复轮并表）

    /// 失败态图标（`exclamationmark.triangle`）——状态块的视觉主元素，取**标题档 13**
    /// （旧 16：本次上限是主行档位 13，取大者既守住上限、又保住「图标 > 说明文字」的层级）。
    static let failureIconFontSize: CGFloat = 13
    /// 失败原因文案（截断显示）——状态/提示类，取 12（旧 11）。
    static let failureReasonFontSize: CGFloat = 12
    /// 可读但 0 条时的空态文案——状态/提示类，取 12（旧值 12，仅收进表、值不变）。
    static let emptyStateFontSize: CGFloat = 12
    /// 权限引导图标（`bell.badge`）——同失败态图标，取标题档 13（旧 18，理由同上）。
    static let permissionIconFontSize: CGFloat = 13
    /// 权限引导说明文案——状态/提示类，取 12（旧 11）。
    static let permissionHintFontSize: CGFloat = 12
    /// 权限引导的动作按钮文案——提示块的组成部分，取 12（旧 11；不按列表行的「清除」11 档，
    /// 因为它是整个空块里唯一的动作，是引导的主入口而不是角落里的次级按钮）。
    static let permissionActionFontSize: CGFloat = 12
}

/// 展开面板：标题行（模块名 + 状态 + 刷新）+ 通知列表（点击整行打开对应 App **并收起刘海**）+ 能力边界说明。
///
/// `.task` 做两件事：取一次最新数据（**不碰权限**）+ 把未读数清零（「自上次打开面板以来」）。
private struct NotificationsModuleView: View {
    @ObservedObject var store: NotificationStore
    /// 行点击的「收起刘海」出口（模块注入：`UIHandle.requestCollapse()`）。
    let onCollapse: () -> Void

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
                .font(.system(size: NotificationRowMetrics.moduleName, weight: .semibold))
                .foregroundStyle(.white)

            Text(NotificationText.status(store.state, count: store.items.count))
                .font(.system(size: NotificationRowMetrics.status))
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
                        .font(.system(size: NotificationRowMetrics.clearAll, weight: .medium))
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
                    .font(.system(size: NotificationRowMetrics.refresh, weight: .medium))
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
                    .font(.system(size: NotificationRowMetrics.failureIconFontSize, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(reason)
                    .font(.system(size: NotificationRowMetrics.failureReasonFontSize))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .ok:
            if store.items.isEmpty {
                Text(LocalizedStringKey("module.notifications.empty"))
                    .font(.system(size: NotificationRowMetrics.emptyStateFontSize))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NotificationListView(store: store, onCollapse: onCollapse)
            }
        }
    }

    /// 能力边界（09 §5.5「必须接受」的四条）——一行小字，别让用户以为能在岛上操作通知。
    private var footer: some View {
        Text(LocalizedStringKey("module.notifications.readOnlyNote"))
            .font(.system(size: NotificationRowMetrics.footnote))
            .foregroundStyle(.white.opacity(0.35))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 通知列表：一行一条，点击整行按 `bundleIdentifier` 打开对应 App，随后收起刘海。
private struct NotificationListView: View {
    @ObservedObject var store: NotificationStore
    /// 行点击的「收起刘海」出口（由模块注入，见 `NotificationsModule.content(for:)`）。
    let onCollapse: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(store.items) { item in
                    NotificationRow(item: item, store: store, onCollapse: onCollapse)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// 列表的一行：`App 名（粗体）· 相对时间` + 标题 + 正文（最多 2 行）+ 右侧「关闭」按钮。
///
/// **两个手势刻意不重叠**：点击区（打开 App **+ 收起刘海**）只盖左侧内容列，关闭按钮在它右侧、
/// 自己的 frame 里。这样两个动作天然互不干扰——不需要靠「谁的手势优先级高」这种版本相关的规则。
/// （常见写法是在整行上挂 `.onTapGesture`、按钮叠在里面，那样点按钮时点击区仍可能吃到触摸。）
///
/// 点击的动作与顺序由 `NotificationClickPolicy.row` 给（打开 App → 收起刘海），本视图只负责
/// 把两个闭包接上：`openApp` 走 store，收起走模块注入的 `onCollapse`。
private struct NotificationRow: View {
    let item: NotificationItem
    @ObservedObject var store: NotificationStore
    /// 行点击的「收起刘海」出口（模块注入）。
    let onCollapse: () -> Void

    /// 整行 hover（背景高亮 + 关闭按钮提亮）。
    @State private var isHovered = false
    /// 关闭按钮自身的 hover（鼠标停在按钮上 → 直接到 `.white`）。
    @State private var isDismissHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            content
            dismissButton
        }
        .padding(.vertical, NotificationRowMetrics.rowVerticalPadding)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 整行底色走首页那条唯一的 hover 规则（T8 / docs/26 §做法 机制七）——本行原先自己写的是
        // `cornerRadius: 6` + `opacity 0.08`；形状与浓度现由 `HomeBandChrome` 一处给（r8 / 0.06）。
        .homeBlockHoverBackground(isHovered: isHovered)
        .onHover { isHovered = $0 }
    }

    /// 左侧内容 = 「打开对应 App」的点击区。
    private var content: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(item.displayName)
                    .font(.system(size: NotificationRowMetrics.appName, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("·")
                    .font(.system(size: NotificationRowMetrics.separator))
                    .foregroundStyle(.white.opacity(0.4))

                if let delivered = item.deliveredDate {
                    Text(NotificationText.relative(delivered))
                        .font(.system(size: NotificationRowMetrics.timestamp, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer(minLength: 2)
            }

            if !item.title.isEmpty {
                Text(item.title)
                    .font(.system(size: NotificationRowMetrics.title))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if !item.body.isEmpty {
                Text(item.body)
                    .font(.system(size: NotificationRowMetrics.body))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            // 动作序列的唯一来源（顺序是契约：先开应用、再收起刘海，见 `NotificationClickPolicy`）。
            NotificationClickPolicy.run(
                NotificationClickPolicy.row,
                openApp: { store.openApp(for: item) },
                collapseNotch: onCollapse
            )
        }
    }

    /// 关闭按钮：**只从岛上移除这一条**（系统通知中心不动），**近 10 秒内有同指纹 AX 句柄时
    /// 顺带真关掉那一条**（判据见 `NotificationStore.willAlsoCloseSystemBanner`，与 `dismiss` 同一份）。
    /// 常态 `.white.opacity(0.6)`，鼠标进入（行内或按钮上）提亮到 `.white`。
    private var dismissButton: some View {
        Button {
            store.dismiss(item)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: NotificationRowMetrics.dismissIcon, weight: .semibold))
                .foregroundStyle(.white.opacity(isHovered || isDismissHovered ? 1 : 0.6))
                .padding(3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isDismissHovered = $0 }
        // 文案与无障碍标签**同源同口径**：句柄在 → 「同时关掉系统通知」，不在 → 「从列表移除」。
        // 悬停（`.help`）与读屏（`.accessibilityLabel`）各读一份，两处由 `dismissHelpKey` 一次决定。
        .help(NotificationText.localized(dismissHelpKey))
        .accessibilityLabel(NotificationText.localized(dismissHelpKey))
    }

    /// × 的文案 key（**唯一落点**）：按 store 的只读谓词分档（D-04）。
    /// 谓词为真 = 点下去会**顺带真关掉系统通知**，因此不说「从列表移除」；为假才退回「从列表移除」。
    /// 谓词本身与 `dismiss` 内的判据同一份（`NotificationStore.listRowCloseHandle`）。
    private var dismissHelpKey: String {
        store.willAlsoCloseSystemBanner(for: item)
            ? "module.notifications.closeSystemNotification"
            : "module.notifications.removeFromList"
    }
}

// MARK: - 首页块（通知 · 最近 N 条 + 最近 3 条）

/// 首页块的**取舍与文案**（纯函数，无 SwiftUI 依赖，单测直接钉）。
///
/// 规格（T1）：标题行「通知 · 最近 N 条」（N == 0 只显示「通知」）+ **最近 3 条**清单，
/// 每行「App 名 · 标题」。**行数上限固定 3、不按块宽分档**（按宽度分档是本批之后的事）。
/// 块宽由宿主 `HomeStripView` 统一声明（模块块 180 / 240），本模块**不声明、不读宽度**。
enum NotificationsHomeBlockLayout {
    /// 首页块最多画几条（规格：最近 3 条；超出的不显示——完整列表在展开 tab）。
    static let maxListRows = 3

    /// 清单要画的条目：**列表顺序的前 3 条**。
    ///
    /// 不在这里排序：`store.items` 本身就是「新的在前」（`NotificationCenterReader.fetchRecent`
    /// 走 `ORDER BY rec_id DESC`），再排一遍只会让首页块与展开 tab 的顺序出现两套口径。
    static func listedItems(_ items: [NotificationItem]) -> [NotificationItem] {
        Array(items.prefix(maxListRows))
    }

    /// 一行的文案：「App 名 · 标题」。
    ///
    /// - 标题先去空白并**压成单行**（复用 `NotificationText.singleLine`：通知标题里的换行会
    ///   白白吃掉 `lineLimit(1)` 的预算，截断位置也不可控）；
    /// - 任一边为空时**不留悬空的分隔符**（plist 缺 `titl` 时只有 App 名，反之亦然）；
    /// - 两边都空时给空串（`Text("")` 不画内容；这种条目在 DB 通道实际上不存在——
    ///   `displayName` 有 bundle id 兜底）。
    static func rowLabel(appName: String, title: String) -> String {
        let name = NotificationText.singleLine(appName)
        let subject = NotificationText.singleLine(title)
        guard !subject.isEmpty else { return name }
        guard !name.isEmpty else { return subject }
        return name + " · " + subject
    }
}

/// 首页块：**标题行「通知 · 最近 N 条」+ 最近 3 条**（每行「App 名 · 标题」）。
///
/// ## N 是什么（**口径说明，别读成「未读」**）
/// N = `store.items.count` = **列表里的条数**（reader 按 `rec_id DESC` 取回的最近 ≤ 40 条，
/// 已滤 `dismissedNotificationIDs`，见 `fetchRecent(limit:dismissing:)`），与展开 tab 状态行
/// 的「最近 N 条」是**同一个数、同一个来源**（控制器裁决 1：不在这里另算一遍）。
///
/// 它**不是**「自上次打开面板以来的新增数」——那是折叠态铃铛用的 `store.unseenCount`
/// （`refreshIncremental` 累加、只有展开 tab 的 `markPanelOpened()` 清零，从首页打开面板
/// 不清零）。两者口径不同是**有意的**：铃铛交代「刚来了几条」，本块交代「列表里现在有几条」，
/// 因此文案也刻意不同（「最近 N 条」而不是「未读 N」），不会让用户以为二者应当一致。
/// 本块的标题行**不读 `unseenCount`**。
///
/// ## 不可读 / 无权限
/// `store.state != .ok` 时在标题行下加**一行**浅色提示（`NotificationText.homeHint`：
/// 无权限 / 不可读两种），与「可读但 0 条」区分开——后者只留标题行一根（控制器裁决 3：
/// 不做空态插图）。提示只是一行字，详细的权限引导与失败原因仍在展开 tab
/// （`NotificationPermissionPrompt` / 失败原因截断显示）。
///
/// **只读**（控制器裁决 2/3）：不做关闭 / 清除 / 回复。
/// **不做新通知高亮 / 闪烁**：瞬时提示是浮层（HUD）的职责，块只做常驻展示。
/// **不引入定时器**：重绘靠 `store` 的 `@Published`。
///
/// 交互只有一处：整行点击 = 打开对应 App **并收起刘海**（动作与顺序收在模块的
/// `openHomeBlockItem`，走 `NotificationClickPolicy.row`）。
///
/// 颜色：面板是黑底、系统外观可能浅色——本模块所有文字**一律显式白色系**
/// （`Color.white` / `.white.opacity(...)`），不用 `.primary` / `.secondary`（见文件头「颜色」）。
///
/// 宽度：**不声明、不读**（`HomeStripBlock` 由宿主统一声明模块块 180 / 240，模块不参与
/// 「我在首页占多宽」的决策）。填充方式沿用待办块：占满分配到的框、内容左上对齐。
private struct NotificationsHomeBlockView: View {
    @ObservedObject var store: NotificationStore
    /// 行点击出口（模块注入：打开对应 App + 收起刘海）。
    let onOpen: (NotificationItem) -> Void
    /// 当前悬停的那一行（`nil` = 没有；按 **id**（`NotificationItem.id` = `Int64` 记录号）记——
    /// 与前台应用格子同款，`Bool` 会让三行一起亮）。
    @State private var hoveredID: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header

            // 不可读 / 无权限时加一行浅色提示（取数失败与「真的 0 条」必须能区分开）；
            // 可读但 0 条时这里什么都不画（控制器裁决 3：不做空态）。
            if let hint = NotificationText.homeHint(store.state) {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            ForEach(NotificationsHomeBlockLayout.listedItems(store.items)) { item in
                row(item)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // **让出板顶**（`HomeBlockChrome.moduleTopInset`，2026-10-06 全页体检：「通知 · 最近 N 条」
        // 那一行距板缘上屏实测只有 2.0pt）。行数固定 ≤ 3（`NotificationsHomeBlockLayout.listedItems`），
        // 不按高度算——让位只是把三行整体下移，96pt 档下三行仍装得下（实测内容 ≈57pt）。
        .padding(.top, HomeBlockChrome.moduleTopInset)
        // 与展开 tab 同口径：每次出现取一次数（首页块只在展开面板里存在，面板一开就是它出现的时刻）。
        // 不新建定时器：增量仍由模块的 AX 通道 / 文件事件 / 60s 兜底轮询推进。
        .task { await store.refreshAll() }
    }

    /// 标题行：有内容时「通知 · 最近 N 条」，0 条时只留模块名（**不画空态文案**）。
    private var header: some View {
        Text(NotificationText.homeHeader(count: store.items.count))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.95))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// 一行 = 「App 名 · 标题」，单行尾部截断；整行是「打开 App + 收起刘海」的点击区。
    ///
    /// **T8 起整行有 hover 底**（首页那条唯一的规则 `homeBlockHoverBackground`，docs/26 §做法 机制七）：
    /// 本行原来只有 `.contentShape` + 点击——首页块里它是**可交互的**（点一下打开 App），
    /// 悬停却没有任何反馈，与带内其它可交互格（前台应用格子）不一致。悬停态按 **id** 记
    /// （行视图共用一个 `@State`，`Bool` 会让三行一起亮；与前台应用格子同款）。
    ///
    /// 底色**就是这一行的 frame**（不额外加内边距）：行高 = 一行文字高，加竖向内边距会把
    /// 三行推出 96pt 的带高（块壳 `.clipped()` 会裁掉最后一行），因此这里只借现成的行距
    ///（`VStack(spacing: 4)`）做呼吸。
    private func row(_ item: NotificationItem) -> some View {
        Text(NotificationsHomeBlockLayout.rowLabel(appName: item.displayName, title: item.title))
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.8))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            // `.contentShape` 让整行（含文字右侧的空白）都能点到，而不是只有字形落在的地方
            .contentShape(Rectangle())
            .homeBlockHoverBackground(isHovered: hoveredID == item.id)
            .onHover { hoveredID = $0 ? item.id : (hoveredID == item.id ? nil : hoveredID) }
            .onTapGesture { onOpen(item) }
    }
}

// MARK: - 折叠态瞬时浮层视图

/// 浮层卡片的尺寸口径（**纯函数**，单测直接钉边界）。
///
/// 为什么需要它：浮层由内核的独立窗口渲染（D-23），尺寸不再由刘海宽度决定，而是
/// 「**固定基准 320 × 64** × 用户设置的倍率 `notificationHUDScale`（默认 1.3）」——
/// 把这条算式从视图里抽出来，边界（0.8 / 2.0）才有地方钉住。
///
/// 取值口径（2026-09-28 改「固定尺寸」后的口径）：
/// - **倍率夹取**到 0.8…2.0（用户直接改 UserDefaults 写了个离谱值时也有确定呈现）；
/// - **卡片尺寸 = 窗口尺寸**，同一个来源 `ModuleHUDWindowHost.contentSize(scale:)`
///   （内核定窗口、模块定卡片，两处引用同一个函数才不会出现「窗口 416pt、卡片 300pt」的错位）；
/// - 字号 / 图标 / 内外边距 / 圆角 = 基准值 × 倍率，**保留两位小数**
///   （避免 0.8 × 12 = 9.600000000000001 这类浮点尾巴，也让 `Equatable` 与单测的等值断言有意义）；
/// - `textMaxWidth` 由「卡片宽度 − 其它元素」反推（不是独立常量），因此改任一项都不会撑破卡片；
///   **超长内容**按 `lineLimit(2)` + `.truncationMode(.tail)` 在卡片内截断——浮层只负责
///   「刚发生了什么」，完整正文看展开面板的列表（分工见 `NotificationHUDView` 的类型文档）。
enum NotificationHUDCardLayout {
    /// 倍率的可用区间（与设置滑块 `Slider(value:in: 0.8...2.0)` 同源）。
    /// **单一来源在内核**（`ModuleHUDWindowHost.hudScaleRange`）：窗口是内核按它设的，
    /// 卡片只是跟着算，这里给模块侧留一个可读的别名。
    static let scaleRange: ClosedRange<Double> = ModuleHUDWindowHost.hudScaleRange

    /// 基准值（倍率 = 1.0 时的一档；都按「独立窗口里的浮层」定过，不再是刘海尺寸）。
    private enum Base {
        static let icon: CGFloat = 14
        static let title: CGFloat = 12
        static let body: CGFloat = 11
        static let close: CGFloat = 11
        /// × 按钮自身的点击余量（图标四周各 2pt，见 `closeButton(size:)` 的 `.padding(2)`）：
        /// 算文字列可用宽度时要把它扣掉，否则内容会比卡片宽出几 pt（固定尺寸下就是右侧被裁）。
        static let closePadding: CGFloat = 2
        /// **水平**内边距（卡片背景与内容之间）。
        static let padding: CGFloat = 10
        /// **垂直**内边距：比水平小一档。固定高度（64 × 倍率）要装「标题 + 正文最多 2 行」，
        /// 上下各 10pt（倍率 1.3 时 13pt）会把正文挤成 1 行（实测：长正文只显示一行 + `…`，
        /// 第二行被高度预算吃掉）；5pt（1.3 时 6.5pt）留出的余量刚好够两行。
        static let paddingVertical: CGFloat = 5
        static let iconSpacing: CGFloat = 8
        static let lineSpacing: CGFloat = 2
        static let cornerRadius: CGFloat = 10
    }

    struct Metrics: Equatable {
        let iconSize: CGFloat
        let titleSize: CGFloat
        let bodySize: CGFloat
        let closeSize: CGFloat
        /// 卡片左右的内边距（卡片背景与内容之间）。
        let padding: CGFloat
        /// 卡片上下的内边距（比左右小一档，见 `Base.paddingVertical`）。
        let verticalPadding: CGFloat
        /// 图标与文字列之间的间距。
        let iconSpacing: CGFloat
        /// 文字列两行之间的间距。
        let lineSpacing: CGFloat
        /// 文字列的可用宽度 = 卡片宽度 −（两侧内边距 + 图标 + 两个间距 + × 及其余量）。
        /// 固定尺寸下它是**确定值**：超出的部分按 `lineLimit(2)` 截断。
        let textMaxWidth: CGFloat
        /// 卡片（= 窗口内容）的**固定尺寸**，来自 `ModuleHUDWindowHost.contentSize(scale:)`。
        let cardSize: CGSize
        let cornerRadius: CGFloat
    }

    /// 给定倍率 → 卡片尺寸（固定，与内容无关）。
    static func metrics(scale: Double) -> Metrics {
        let s = CGFloat(min(max(scale, scaleRange.lowerBound), scaleRange.upperBound))

        let icon = round2(Base.icon * s)
        let title = round2(Base.title * s)
        let body = round2(Base.body * s)
        let close = round2(Base.close * s)
        let padding = round2(Base.padding * s)
        let verticalPadding = round2(Base.paddingVertical * s)
        let iconSpacing = round2(Base.iconSpacing * s)
        let lineSpacing = round2(Base.lineSpacing * s)
        let cornerRadius = round2(Base.cornerRadius * s)
        let closePadding = round2(Base.closePadding * s)

        let cardSize = ModuleHUDWindowHost.contentSize(scale: scale)
        let textMaxWidth = max(
            round2(cardSize.width - (padding * 2 + icon + iconSpacing * 2 + close + closePadding * 2)),
            0
        )

        return Metrics(
            iconSize: icon,
            titleSize: title,
            bodySize: body,
            closeSize: close,
            padding: padding,
            verticalPadding: verticalPadding,
            iconSpacing: iconSpacing,
            lineSpacing: lineSpacing,
            textMaxWidth: textMaxWidth,
            cardSize: cardSize,
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
/// 卡片底本身是**可配的**（`notificationHUDBackgroundStyle`，2026-09-28）：默认液态玻璃
/// （`.liquidGlass`，强制深色外观），可切成纯色（`.solid`）——两档的对比度前提都是
/// 「底足够深」，见 `cardBackground(cornerRadius:)`。
///
/// 尺寸：**固定**（= 窗口尺寸，`NotificationHUDCardLayout.metrics(scale:)` 的 `cardSize`，
/// 基准 320 × 64 × 倍率 `notificationHUDScale`，默认 1.3）。固定尺寸带来两个分工：
///
/// ## 超长内容策略（2026-09-28 用户：「消息内容过多考虑下怎么显示」）
/// - **第一行**：App 名（粗体、1 行、`.truncationMode(.middle)`）——App 名常带后缀，中间截断
///   比尾部截断更能保留辨识度；
/// - **第二行**：`标题 · 正文`（标题 / 正文里的换行**先替换成空格**，见
///   `NotificationText.hudDetail`），**最多 2 行**、`.truncationMode(.tail)`；
/// - **一次取数多条新通知**：浮层只展示**最新一条**（09 §5.5：避免刷屏），其余的在第二行末尾
///   以计数后缀交代（`module.notifications.moreCount` =「等 N 条」/「and N more」）——
///   计数是「还有几条」的可靠交代，比逐条排队弹更不打扰；
/// - **完整正文的位置是展开面板的通知列表**（`NotificationsModuleView` 的 `NotificationRow`：
///   App 名 + 相对时间 + 标题 + 正文最多 2 行 + 每行可点开 App）。浮层是「刚发生了什么」的
///   瞬时提示（到期自动消失，默认 8s），**不是阅读入口**——两行装不下的内容在这里截断，
///   用户要看全文就展开面板（这也是「截断」不会丢信息的前提）。
///
/// 「仅从岛上隐藏」的落点：`isHidden` 让这一格**立刻**渲染成空，并配合 `UIHandle.dismissTransient()`
/// 把浮层从内核撤掉（内核撤 → 浮层窗口淡出，所以是本视图与窗口一起消失，不只是这一格变空）。
///
/// ## × 的手势优先级（2026-09-28 修正；D-23 后仍保留）
/// 关闭态时期 × 收不到点击的根因是**祖先**的 `.onTapGesture { openNotch() }` 先吃掉了事件。
/// 浮层搬进独立窗口后祖先手势已不在同一条链上，但 `.highPriorityGesture` 保留：换来的是
/// 「窗口内任何一层再挂普通手势也不会抢走 ×」这条稳定性，成本为零。
///
/// ## 卡片本体可点（2026-09-29 用户反馈：「直接点消息不能弹出对应的应用」）
/// 改造前只有右上角 × 有处理器，卡片本体（图标 + 两行文字 + 内边距）点了没反应。现在整块卡片
/// （`.contentShape(Rectangle())`）是「**打开对应 App + 撤掉浮层**」的点击区（`NotificationClickAction`），
/// 动作与顺序由 `NotificationClickPolicy.hudCard` 给。
///
/// 与 × 的分工：**本体 = 去看看（打开 App）**，**× = 这条不要了（有句柄时真关掉系统通知）**。
/// 点 × 不会同时触发本体动作：× 是它内部的 `Button`（并且自己也挂了 `.highPriorityGesture`），
/// SwiftUI 的按钮会吃掉落在它身上的那一次点击——本体手势收不到。两处再各自用 `isHidden` 兜一层
/// 幂等（先点 × 再点本体不会打开 App，反之亦然）。
private struct NotificationHUDView: View {
    let appName: String
    let title: String
    /// 通知正文（**不叫 `body`**：那个名字被 SwiftUI 的 `View.body` 占了）。
    let bodyText: String
    /// `Defaults[.showBodyInHUD]`（在模块侧取一次快照；由 `NotificationHUDPresentation` 打包进来）。
    let showsBody: Bool
    /// `Defaults[.notificationHUDBackgroundStyle]`（同一份快照）：卡片底 = 液态玻璃 / 纯色。
    let backgroundStyle: NotificationHUDBackgroundStyle
    /// 这次取数里**除展示的这条之外**还有几条新通知（0 = 没有）。> 0 时第二行末尾追加「等 N 条」。
    let moreCount: Int
    /// × 的提示文案 key：有真关闭句柄时是「关闭系统通知」，否则是「关闭（仅从岛上移除）」。
    let closeHelpKey: String
    /// 点击**卡片本体**：打开通知对应的 App（DB 通道按 rec_id 解析、AX 通道按 App 名反查）。
    let onOpenApp: () -> Void
    /// 点击**卡片本体**：撤掉浮层（`UIHandle.dismissTransient()`）——**只撤浮层**
    /// （与 × 的区别：这里不真关系统通知，用户是「去看看」而不是「这条不要了」）。
    let onDismissTransient: () -> Void
    /// 点击 ×：真关闭（有句柄时）——**「仅从岛上隐藏」由本视图的 `isHidden` 自己完成**。
    let onClose: () -> Void

    /// 点过 × 之后不再渲染这一格（浮层 ttl 到期后内核自然清掉它）。
    @State private var isHidden = false
    @State private var isCloseHovered = false

    /// 尺寸倍率（用户设置）。浮层只活几秒，不需要为它维护「设置改了要重渲」的观察链——
    /// 每次弹出时取一次当前值即可（同 `showsBody` 的口径）。
    @Default(.notificationHUDScale) private var scale: Double

    var body: some View {
        if isHidden {
            EmptyView()
        } else {
            content
        }
    }

    /// 当前这一档尺寸（含**固定卡片尺寸** `cardSize`：内核窗口与卡片共用同一个来源）。
    private var metrics: NotificationHUDCardLayout.Metrics {
        NotificationHUDCardLayout.metrics(scale: scale)
    }

    private var content: some View {
        let card = metrics
        return HStack(spacing: card.iconSpacing) {
            Image(systemName: "bell.badge")
                .font(.system(size: card.iconSize, weight: .medium))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: card.lineSpacing) {
                // 第一行：App 名（粗体、1 行、**中间截断**）。
                Text(appName)
                    .font(.system(size: card.titleSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // 第二行：`标题 · 正文`（+ 多条时的计数后缀），**最多 2 行、尾部截断**。
                // 完整正文看展开面板列表（见类型文档的「超长内容策略」）。
                // `.fixedSize(horizontal: false, vertical: true)`：与列表行同口径——不让父级把
                // 两行文字挤成一行（实测过：固定高度下不给它，长正文只显示 1 行 + `…`）。
                Text(secondLine)
                    .font(.system(size: card.bodySize))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 文字列吃掉图标与 × 之间的剩余宽度（`textMaxWidth` 是它的上界）：固定卡片下
            // 「剩余宽度」就是设计值，超长内容在这里换行 / 截断，× 因此永远留在卡片内。
            .frame(maxWidth: card.textMaxWidth, alignment: .leading)

            closeButton(size: card.closeSize)
        }
        .padding(.horizontal, card.padding)
        .padding(.vertical, card.verticalPadding)
        // **固定尺寸**：卡片与内核窗口用同一个来源（`cardSize`），内容多少都不跳动。
        .frame(width: card.cardSize.width, height: card.cardSize.height, alignment: .leading)
        .background(cardBackground(cornerRadius: card.cornerRadius))
        // 卡片本体 = 「打开对应 App + 撤浮层」的点击区（2026-09-29）：`contentShape` 让**整块卡片**
        // （含图标、文字之间的空白与内边距）都可点——用户点的是「这条消息」，不是某一行文字。
        // 普通 `.onTapGesture` 与 × 的 `.highPriorityGesture` 分工见类型文档：点 × 时按钮吃掉事件。
        .contentShape(Rectangle())
        .onTapGesture { openAppFromCard() }
    }

    /// 卡片底：按 `notificationHUDBackgroundStyle` 二选一（2026-09-28 用户要求「背景设置
    /// （是否为液态玻璃模式）」）。
    ///
    /// - `.liquidGlass`（**默认**）：苹果私有的 `NSGlassEffectView`（`LiquidGlassBackground` 组件，
    ///   降级链在组件内部：老系统退回 `NSVisualEffectView`）。variant 用组件声明的默认档
    ///   `.v11`（`LiquidGlassVariant.defaultVariant`，组件作者标注「视觉上最讨喜」的一档，
    ///   锁屏面板 / OSD 的自定义玻璃也都在这个家族里取默认）——本卡片没有理由偏离默认；
    ///   **圆角与卡片一致**（`cornerRadius`，两档共同口径）；玻璃上再压一层深色
    ///   （`Color.black.opacity(0.35)`）保证白字对比度。
    ///   **强制深色外观**：浅色系统外观下玻璃会渲染成浅色，而本卡片文字一律显式白色（会看不清）——
    ///   窗口层面已由 `ModuleHUDWindowHost` 把 `panel.appearance` 设成 `darkAqua`
    ///   （口径同 `EditPanelView.VisualEffectView.forcedAppearance` 对 `hudWindow` 材质的处理），
    ///   这里再给玻璃的**内容**补一份 `.environment(\.colorScheme, .dark)`：`LiquidGlassBackground`
    ///   内部是**另一个** `NSHostingView`（它的内容不继承外层的环境）。
    /// - `.solid`：`Color.black.opacity(0.92)` + 一圈浅描边（改造前的观感）。
    @ViewBuilder
    private func cardBackground(cornerRadius: CGFloat) -> some View {
        switch backgroundStyle {
        case .liquidGlass:
            LiquidGlassBackground(variant: .defaultVariant, cornerRadius: cornerRadius) {
                Color.black.opacity(0.35)
                    .environment(\.colorScheme, .dark)
            }
        case .solid:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.black.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
        }
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

    /// 卡片本体的动作体（2026-09-29）：**打开 App → 撤浮层**，顺序由 `NotificationClickPolicy.hudCard`
    /// 给（与列表行的 `row` 只差最后一条：列表行收起刘海、浮层撤浮层）。
    ///
    /// 幂等闸与 × 共用 `isHidden`：先点 × 再点本体不会打开 App；先点本体（浮层随即被撤掉）
    /// 也不可能再点到 ×。
    private func openAppFromCard() {
        guard !isHidden else { return }
        isHidden = true
        NotificationClickPolicy.run(
            NotificationClickPolicy.hudCard,
            openApp: onOpenApp,
            dismissTransient: onDismissTransient
        )
    }

    /// 第二行：`showBodyInHUD` 为真时是「标题 · 正文（+ 多条计数后缀）」，否则是「新通知」。
    private var secondLine: String {
        NotificationText.hudDetail(title: title, body: bodyText, showsBody: showsBody, moreCount: moreCount)
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
                .font(.system(size: NotificationRowMetrics.permissionIconFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))

            Text(LocalizedStringKey("module.notifications.needsFullDiskAccess"))
                .font(.system(size: NotificationRowMetrics.permissionHintFontSize))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                NotificationPermissionPrompt.openFullDiskAccessSettings()
            } label: {
                Text(LocalizedStringKey("module.notifications.openSettings"))
                    .font(.system(size: NotificationRowMetrics.permissionActionFontSize, weight: .medium))
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
    /// **纯函数**：首页块标题行的文案（T1，审查后改口径）。
    ///
    /// - `count > 0` → `通知 · 最近 N 条`（`module.notifications.name` + `module.notifications.homeRecent`）；
    /// - `count == 0` → 只剩模块名（复用既有 `module.notifications.name`），**不画空态文案**。
    ///
    /// **刻意不叫「未读」**：`count` 是「列表里的条数」（生产路径 = `store.items.count`，
    /// 与展开 tab 状态行的「最近 N 条」同一个来源、同一个数），与折叠态铃铛的
    /// `store.unseenCount`（自上次打开面板以来的新增数）**不是一回事**——
    /// 用「未读」会让人以为二者应当一致，而它们本来就不该一致（见块视图的「N 是什么」）。
    /// 函数本身不碰 store，边界因此由单测直接钉。
    static func homeHeader(count: Int) -> String {
        guard count > 0 else { return localized("module.notifications.name") }
        let recent = String(format: localized("module.notifications.homeRecent"), count)
        return localized("module.notifications.name") + " · " + recent
    }

    /// **纯函数**：首页块在**不可读 / 无权限**时标题行下的那一行提示；可读（`.ok`）给 `nil`
    /// （= 不画那一行）。
    ///
    /// 判据直接用既有状态枚举的两个非 `ok` 分支，不另造条件：
    /// - `.needsFullDiskAccess`（`open(2)` 被 TCC 拒绝）→ 「需完全磁盘访问」；
    /// - `.failure`（库不存在 / schema 变了 / SQLite 打不开）→ 「通知不可读」。
    ///
    /// 为什么要这一行：没有它时「取不到数据」与「可读但 0 条」在块上长得一样（都只剩标题行），
    /// 而这两件事对用户的意义完全不同（前者要去授权 / 去查探针报告，后者只是没有新通知）。
    /// 详细的权限引导与失败原因仍在展开 tab（块里只有一行字的预算）。
    static func homeHint(_ state: NotificationReadState) -> String? {
        switch state {
        case .ok:
            return nil
        case .needsFullDiskAccess:
            return localized("module.notifications.homeNeedsPermission")
        case .failure:
            return localized("module.notifications.homeUnreadable")
        }
    }

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
    /// - 两边都空（plist 缺 `titl` / `body`）时同样给「新通知」，不留一行空白；
    /// - **`moreCount > 0`** 时在末尾追加 `module.notifications.moreCount` 的计数后缀
    ///   （「等 N 条」/「and N more」）：一次取数进来多条时浮层只展示最新一条，
    ///   其余几条靠这个后缀交代（见 `NotificationHUDView` 的「超长内容策略」）；
    /// - **段内换行先压成空格**：通知正文常带换行（多行摘要 / 列表），浮层第二行只有 2 行的
    ///   预算，换行会白白吃掉一行且截断位置不可控；压成空格后由 `.lineLimit(2)` +
    ///   `.truncationMode(.tail)` 统一截断（完整正文看展开面板列表）。
    static func hudDetail(title: String, body: String, showsBody: Bool, moreCount: Int = 0) -> String {
        let newNotification = localized("module.notifications.newNotification")
        let suffix = moreCount > 0
            ? " " + String(format: localized("module.notifications.moreCount"), moreCount)
            : ""
        guard showsBody else {
            // 关掉正文时同样带计数后缀：「还有几条」与正文显示与否无关
            return newNotification + suffix
        }
        let text = [title, body]
            .map { singleLine($0) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return (text.isEmpty ? newNotification : text) + suffix
    }

    /// 把任意多行文本压成**一行**：换行 / 制表符 → 空格，连续空白折成一个，首尾去净。
    ///
    /// 纯函数（口径见 `hudDetail`）：`.lineLimit(2)` 的预算要留给「真的两行文字」，
    /// 不该被正文里的换行符占掉；顺带把 `\r\n`、全角空格之外的连续空白也归一。
    static func singleLine(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// 按字数截断（错误串可能很长：SQLite 的 errmsg 会带上整条 SQL）。
    static func truncate(_ text: String, limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }
}
