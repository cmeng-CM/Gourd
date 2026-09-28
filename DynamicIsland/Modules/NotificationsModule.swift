//
//  NotificationsModule.swift
//  Gourd 内置模块 · 通知上岛（P2c）
//
//  设计依据：docs/09-features-and-mechanisms.md §5.5（本轮风险最高的一项）+ docs/12-p1-batches.md P2c。
//  本批交付 = **可行性探针 + 模块骨架 + 展开列表一次落地**（折叠态瞬时浮层不在本批）。
//
//  ## 数据源与权限
//  - 数据源：`~/Library/Group Containers/group.com.apple.usernoted/db2/db`（SQLite，**只读**，
//    见 `NotificationCenterReader`；schema 是私有的，Apple 改版即失效）；
//  - 权限：**需要完全磁盘访问**。该权限**无法程序化申请**，因此本模块不做任何授权弹窗：
//    读不到时只在面板上显示提示 + 一颗「打开系统设置」按钮（跳到隐私与安全性 → 完全磁盘访问）；
//  - **严禁**为了触发提示去读其它受保护路径（本机实测：通知库自身被拒即可判定）。
//
//  ## 能力边界（09 §5.5「必须接受」，UI 上有一行 footer 明示）
//  ① **只能读**：不能关闭、回复、操作真实通知（那需要 AX 或私有 API，属降级方案）；
//  ② 需要完全磁盘访问；③ schema 私有、系统改版可能失效；
//  ④ 内容敏感：**默认不在浮层显示正文**（`showBodyInHUD` 默认 false——本批连浮层都未做）。
//
//  ## 增量策略（09 §5.5）
//  30s 轮询（`activate()` 起一个 Task，`deactivate()` 取消）→ **先看库文件 mtime**，没变直接返回；
//  变了才按 `record.rec_id > 基线` 取新增。**不做 1s 全表扫**（该库可能很大）。
//
//  ## 配置
//  本批 `config: nil`——**第一版不读配置**（`appsFilter` / `maxItems` / `pollIntervalSeconds` /
//  `showBodyInHUD` 都还没有配置入口，见 [14](../../docs/14-module-manifests.md) 的 notifications 行）。
//  接口边界与 09 §5.5 的差异（本批**没做**的部分）：折叠态瞬时浮层、按 App 分组、ax 降级路径、
//  `appsFilter` 黑白名单——前两项见下一条「本批形态」，后两项见 09 §5.5 的降级方案。
//
//  ## 本批形态
//  - 展开面板：标题行（模块名 + 状态 + 刷新按钮）+ 可滚动通知列表 + 一行能力边界说明；
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
//  `.hoursAgo` / `.daysAgo` / `.readOnlyNote`。
//

import AppKit
import SwiftUI

// MARK: - Store

/// 通知列表 / 增量计数 / 可读性状态的持有者（模块自己持有，不进 `ModuleRegistry`）。
@MainActor
final class NotificationStore: ObservableObject {
    /// 列表条数上限（本批是常量：第一版不读配置，见文件头）。
    static let maxItems = 40
    /// 轮询间隔（秒）。**30s，不是 1s**——增量另靠 mtime 闸门（09 §5.5）。
    static let pollInterval: TimeInterval = 30

    /// 最新通知（新的在前），最多 `maxItems` 条。
    @Published private(set) var items: [NotificationItem] = []
    /// 最近一次读取的可读性判定（UI 据此显示「最近 N 条 / 需要完全磁盘访问 / 错误」）。
    @Published private(set) var state: NotificationReadState = .ok
    /// 自上次打开面板以来的新增条数（**内存态**，不落盘；打开面板即清零）。
    @Published private(set) var unseenCount = 0
    /// 最近一次成功取数的时刻（只进日志与状态行，不改变呈现）。
    @Published private(set) var lastRefreshedAt: Date?

    /// 最近一次失败的可读原因（= `state` 的 `.failure` 载荷；UI 截断显示）。
    var failureReason: String? {
        if case .failure(let reason) = state { return reason }
        return nil
    }

    private let reader: NotificationCenterReader
    private let log: ModuleLogger
    /// 增量基线：已见过的最大 `rec_id`（09 §5.5 的「按单调 id 取新增」）。
    private var baselineRecordID: Int64 = 0
    /// 上次看到的库文件 mtime（mtime 未变 = 库没写过，连增量查询都不做）。
    private var lastModificationDate: Date?
    /// 串行闸：探针 / 全量 / 增量共用同一把（都是主线程状态，重入会写乱基线）。
    private var isFetching = false
    /// bundleIdentifier → App 本地化显示名（含「解析不到」的空串缓存，避免每次轮询重查）。
    private var appNameCache: [String: String] = [:]

    init(logger: ModuleLogger, reader: NotificationCenterReader = NotificationCenterReader()) {
        self.log = logger
        self.reader = reader
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

    /// 全量刷新：最新 `maxItems` 条进列表，并把增量基线推到 `MAX(rec_id)`
    /// （**既有通知不算「新增」**——否则一装上就冒出几十条未读）。
    func refreshAll() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        let reader = self.reader
        let limit = Self.maxItems
        let fetched = await Task.detached(priority: .utility) { reader.fetchRecent(limit: limit) }.value

        apply(fetched, from: reader)
        log.info("全量刷新：\(fetched.count) 条，判定 \(String(describing: reader.lastState))")
    }

    /// 30s 轮询一次：**先过 mtime 闸门**，库没变就什么都不做（09 §5.5：不要全表扫）。
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
        if let lastModificationDate, mtime <= lastModificationDate { return }
        await refreshIncremental()
    }

    /// 增量：取 `rec_id > 基线` 的新通知；有新条目才累加未读数并刷新列表。
    private func refreshIncremental() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        let reader = self.reader
        let limit = Self.maxItems
        let baseline = baselineRecordID
        let newItems = await Task.detached(priority: .utility) {
            reader.fetchNew(after: baseline, limit: limit)
        }.value

        lastModificationDate = reader.modificationDate
        state = reader.lastState
        if let maxID = reader.lastMaxRecordID { baselineRecordID = max(baseline, maxID) }
        guard !newItems.isEmpty else { return }

        unseenCount += newItems.count
        let fetched = await Task.detached(priority: .utility) { reader.fetchRecent(limit: limit) }.value
        apply(fetched, from: reader)
        log.info("新增 \(newItems.count) 条通知（未读累计 \(unseenCount)）")
    }

    /// 面板打开：未读数清零（「自上次打开面板以来」的口径）。
    func markPanelOpened() {
        guard unseenCount != 0 else { return }
        unseenCount = 0
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

    init(context: ModuleContext) {
        self.context = context
        self.store = NotificationStore(logger: context.logger)
    }

    /// 起轮询（30s 一次，**幂等**）：首个 tick 前先跑一次探针。
    ///
    /// 探针与取数都在**后台任务**里跑（`NotificationCenterReader` 无共享可变状态、可安全跨线程）——
    /// 库在 TCC 拒绝下会立刻失败，授权后也只是读一个几百 KB 的 SQLite，但一律不占主线程。
    func activate() async throws {
        guard pollTask == nil else { return }
        let store = self.store
        let shouldProbe = !didRunProbe
        didRunProbe = true

        pollTask = Task { [store] in
            if shouldProbe {
                await store.runProbe()
            }
            while !Task.isCancelled {
                await store.pollOnce()
                do {
                    try await Task.sleep(for: .seconds(NotificationStore.pollInterval))
                } catch {
                    return  // 被取消（deactivate）：正常退出，不记错误
                }
            }
        }
        context.logger.info("notifications 模块已激活（轮询 \(Int(NotificationStore.pollInterval))s）")
    }

    func deactivate() async {
        pollTask?.cancel()
        pollTask = nil
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

    /// 标题行：模块名 + 状态（「最近 N 条」/「需要完全磁盘访问」/ 错误原因截断）+ 刷新按钮。
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

/// 列表的一行：`App 名（粗体）· 相对时间` + 标题 + 正文（最多 2 行）。
private struct NotificationRow: View {
    let item: NotificationItem
    @ObservedObject var store: NotificationStore

    @State private var isHovered = false

    var body: some View {
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
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(isHovered ? 0.08 : 0))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { store.openApp(for: item) }
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

    /// 按字数截断（错误串可能很长：SQLite 的 errmsg 会带上整条 SQL）。
    static func truncate(_ text: String, limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }
}
