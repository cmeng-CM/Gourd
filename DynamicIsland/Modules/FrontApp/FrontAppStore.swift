//
//  FrontAppStore.swift
//  Gourd 模块 · 前台应用联动（p2-shortcuts-frontapp / T3）
//
//  docs/22-shortcuts-and-frontapp.md §做法 机制三 + §接口与数据形状 3 的 store：
//  事件源是 `NSWorkspace.shared.notificationCenter` 的 `didActivateApplicationNotification`
//  （公开 API、零权限），初值取 `NSWorkspace.shared.frontmostApplication`；
//  历史的口径全在纯函数 `FrontAppHistory`（去重 / 移到最前 / 截到上限 / 排除自身），
//  本文件只管四件事：**订阅、映射、发布、动作**。
//
//  四条刻意写死的口径（改动前先读）：
//
//  1. **不读窗口标题**（§明确不做）：那要辅助功能权限（TCC）；本批零权限，只做"应用本身"
//     （图标 / 名称 / 最近切换）——所以这里从头到尾没有 `AXUIElement`，也没有窗口名；
//  2. **排除本应用自己**（§机制三）：否则每次点开刘海都把壶中天自己记成"最近应用"。
//     自身的快照既不改 `current`（留着上一次的真前台）也不进 `recent`（整条忽略）；
//  3. **夹取一次**（§接口与数据形状 3）：`maxRecentApps` 到这里就夹到 `limitRange`（3…8），
//     `recentLimit` 就是那个唯一值，视图不再夹；
//  4. **订阅可摘、可重入**（§接口与数据形状 3）：`deactivate()` 幂等摘观察者（模块关掉后不再收
//     事件、不再画块），`start` 重复调用不会挂两个观察者（token 非 nil 就返回）——
//     否则"模块被重启/重新激活"会让一次切换处理两遍。
//
//  图标取值只有一条路（§接口与数据形状 3）：`NSWorkspace.shared.icon(forFile:)`，按 id 缓存；
//  视图只调 `self.icon(for:)`，不自己取图标（接口里没有第二个图标来源）。
//

import AppKit
import Combine

/// 前台应用的状态源（`@MainActor`：`@Published` 的读写与 AppKit 的激活动作都在主 actor 上）。
@MainActor
final class FrontAppStore: ObservableObject {

    /// 当前前台应用（拿不到前台应用、或前台就是本应用时保持 nil）。
    @Published private(set) var current: FrontAppSnapshot?
    /// 最近切换（新在前；已过 `FrontAppHistory.excludingSelf` + `updated`）。
    @Published private(set) var recent: [FrontAppSnapshot] = []
    /// **夹取后**的历史上限（`limitRange` 3…8）：视图读它，不再自己夹（口径 3）。
    private(set) var recentLimit = FrontAppHistory.defaultLimit

    private let config: ConfigHandle
    private let logger: ModuleLogger

    /// 观察者 token（非 nil = 已订阅；`deactivate()` 置回 nil，因此摘了还能再 `start`）。
    private var activationToken: NSObjectProtocol?
    /// 本应用的 bundleID（`excludingSelf` 的判据；nil = 本应用没有 bundleID，那时不排除任何东西）。
    private var selfBundleID: String?
    /// id → 应用包路径：映射快照时记下——`icon(forFile:)` 要的是路径，而快照里只有 bundleID / pid。
    private var bundlePaths: [String: String] = [:]
    /// id → 图标（`icon(forFile:)` 的结果按 id 缓存；首页块反复重绘时不重复取图）。
    private var iconCache: [String: NSImage] = [:]

    init(config: ConfigHandle, logger: ModuleLogger) {
        self.config = config
        self.logger = logger
    }

    // MARK: 生命周期

    /// 开始收前台变化事件（模块 `activate()` 调一次；重复调用是空操作）。
    ///
    /// `maxRecentApps` 给 nil 时从 config 读（缺键兜 `FrontAppHistory.defaultLimit`）——
    /// 无论来源是参数还是 config，**夹取只在这里做一次**（口径 3，`FrontAppHistory.clampedLimit`）。
    /// 初值取 `NSWorkspace.shared.frontmostApplication`：模块刚开就要有东西可画，不等第一次切换。
    func start(selfBundleID: String?, maxRecentApps: Int? = nil) {
        guard activationToken == nil else { return }
        self.selfBundleID = selfBundleID

        let raw = maxRecentApps ?? config.get("maxRecentApps", as: Int.self) ?? FrontAppHistory.defaultLimit
        recentLimit = FrontAppHistory.clampedLimit(raw)
        logger.info("前台应用联动启动：历史上限 \(recentLimit)（原始值 \(raw)）、本应用 \(selfBundleID ?? "无 bundleID")")

        seedFromFrontmost()
        observeActivations()
    }

    /// 摘观察者（**幂等**：没订阅过、或摘过之后再调都是空操作）。
    ///
    /// 只摘订阅，不清 `current` / `recent`：重新 `start` 时初值会把 `current` 换成当下的前台应用，
    /// 而"刚才切过谁"在模块关掉再打开之间仍然成立（不持久化，只活在本次运行的内存里）。
    func deactivate() {
        guard let token = activationToken else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(token)
        activationToken = nil
        logger.info("已摘前台变化观察者")
    }

    // MARK: 动作

    /// 点一个小图标 = 把那个应用切到前台（§机制三）。
    ///
    /// 已是前台的点了是**空操作**（系统返回 false，这里只记一条日志，不报错、不弹窗）；
    /// 进程已退出（应用重启后 pid 变了）时找不到 `NSRunningApplication`，同样只是空操作。
    func activate(_ snapshot: FrontAppSnapshot) {
        guard let app = NSRunningApplication(processIdentifier: snapshot.pid) else {
            logger.info("激活 \(snapshot.name)（\(snapshot.id)）：进程已不在")
            return
        }
        if app.activate() {
            logger.info("激活：\(snapshot.name)（\(snapshot.id)）")
        } else {
            logger.warn("激活失败：\(snapshot.name)（\(snapshot.id)）")
        }
    }

    /// 取图标——**视图唯一的图标来源**（§接口与数据形状 3）。
    ///
    /// 路径优先用映射快照时记下的包路径（那一条不会漂）；快照不是这里产生的（例如用例手造的）
    /// 才退到按 pid 现查。查不到包路径（命令行工具、进程已退出）时返回 nil，视图画占位而不是空白图。
    func icon(for snapshot: FrontAppSnapshot) -> NSImage? {
        if let cached = iconCache[snapshot.id] { return cached }
        guard let path = bundlePaths[snapshot.id]
            ?? NSRunningApplication(processIdentifier: snapshot.pid)?.bundleURL?.path else { return nil }

        let image = NSWorkspace.shared.icon(forFile: path)
        iconCache[snapshot.id] = image
        return image
    }

    // MARK: 内部

    /// 订阅前台变化（`queue: .main` → 回调已在主线程；写法照 `DynamicIsland/DynamicIslandApp.swift:214-219`
    /// 的既有先例：`userInfo` 里取 `NSRunningApplication`）。
    private func observeActivations() {
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            // `queue: .main` 保证已在主线程，类型层的 `@MainActor` 由此落地（同 `TerminalManager` 的先例）。
            MainActor.assumeIsolated {
                self?.handleActivation(of: app)
            }
        }
        activationToken = token
        logger.info("已订阅前台变化（didActivateApplicationNotification）")
    }

    /// 一次前台变化：映射 → 排除自身 → 发布（`current` 与 `recent` 同一份快照，口径 2）。
    private func handleActivation(of app: NSRunningApplication) {
        let snapshot = self.snapshot(of: app)
        guard !isSelf(snapshot) else {
            logger.info("前台变成本应用自己（\(snapshot.name)）：current 不动、也不记进 recent")
            return
        }

        current = snapshot
        recent = FrontAppHistory.updated(
            FrontAppHistory.excludingSelf(recent, selfBundleID: selfBundleID),
            activating: snapshot,
            limit: recentLimit
        )
        logger.info("前台应用：\(snapshot.name)（\(snapshot.id)），最近 \(recent.count) 条")
    }

    /// 初值：`NSWorkspace.shared.frontmostApplication` → `current`（§接口与数据形状 3）。
    ///
    /// 只种 `current`、**不种 `recent`**：`recent` 的语义是"**切换**过谁"，启动时的前台应用还没被
    /// 切换过；何况把它同时放进当前与最近，会让 180pt 宽的块里同一个应用出现两次。
    private func seedFromFrontmost() {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            logger.info("取不到前台应用（frontmostApplication 为 nil）：current 留空")
            return
        }
        let snapshot = snapshot(of: app)
        guard !isSelf(snapshot) else {
            logger.info("前台就是本应用（\(snapshot.name)）：current 留空，等真的切到别的应用")
            return
        }
        current = snapshot
        logger.info("初值：前台应用 \(snapshot.name)（\(snapshot.id)）")
    }

    /// `NSRunningApplication` → 快照（顺手记下应用包路径：`icon(forFile:)` 要用）。
    ///
    /// 名称兜底顺序：`localizedName` → bundleID → `"pid:\(pid)"`。都拿不到时**不编造应用名**，
    /// 用身份串顶上（用户至少能看出"这是哪个进程"，而不是看到一行空白）。
    private func snapshot(of app: NSRunningApplication) -> FrontAppSnapshot {
        let bundleID = app.bundleIdentifier
        let snapshot = FrontAppSnapshot(
            bundleID: bundleID,
            name: app.localizedName ?? bundleID ?? "pid:\(app.processIdentifier)",
            pid: app.processIdentifier
        )
        if let path = app.bundleURL?.path {
            bundlePaths[snapshot.id] = path
        }
        return snapshot
    }

    /// 是不是本应用自己（判据走纯函数，口径只有一处）。
    private func isSelf(_ snapshot: FrontAppSnapshot) -> Bool {
        FrontAppHistory.excludingSelf([snapshot], selfBundleID: selfBundleID).isEmpty
    }
}
