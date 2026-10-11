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
//  FrontAppStore.swift
//  Gourd 模块 · 前台应用联动（p2-shortcuts-frontapp / T3）
//
//  docs/22-shortcuts-and-frontapp.md §做法 机制三 + §接口与数据形状 3 的 store：
//  事件源是 `NSWorkspace.shared.notificationCenter` 的 `didActivateApplicationNotification`
//  （公开 API、零权限），初值取 `NSWorkspace.shared.frontmostApplication`；
//  历史的口径全在纯函数 `FrontAppHistory`（去重 / 移到最前 / 截到上限 / 排除自身），
//  本文件只管四件事：**订阅、映射、发布、动作**。
//
//  **块里画什么**（docs/23-home-fit.md §做法 机制三，2026-09-30 改）：不再是 `recent`（那是"本进程
//  活过的那几次切换"），而是 `switcherApps` —— **现取** `NSWorkspace.shared.runningApplications`，
//  只列可激活的常规 App。`recent` 保留，但**降级成排序依据**（当前应用 → `recent` → 名称）。
//  过滤与排序全在纯函数 `FrontAppSwitcher`（文件末尾），取数走注入点 `FrontAppRunningAppsProvider`
//  （默认真实现读 `NSWorkspace`，用例给假体，于是用例不依赖跑测试这台机器上开着什么）。
//
//  五条刻意写死的口径（改动前先读）：
//
//  0. **台前调度那类系统的 UI 进程不列**（2026-09-30 加，D-04）：它们不是 `.regular`
//     （`activationPolicy` 是 `.accessory` / `.prohibited`），对它们调 `activate()` 系统直接拒——
//     用户看到的「点了没反应」就是这里来的。**列一个点不动的行比不列更糟**，所以过滤放在数据层：
//     视图不会拿到"画得出但点不动"的条目。
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

    /// **运行名单的代次**（2026-10-11 / p13b 修复）：`switcherApps` 是**现取**的 computed 属性，
    /// 而视图只在 store 发布时才重算它——**启动 / 退出一个应用不改 `current` / `recent`**
    /// （只有「前台变了」才改），此前因此没有任何人叫醒视图：退出的应用会一直留在格子里、
    /// 新开的要等下一次切换才出现。这里代次 +1 只为发一次 `objectWillChange`，
    /// 读它的只有视图的重算（值本身不含语义）。
    @Published private(set) var runningGeneration = 0

    private let config: ConfigHandle
    private let logger: ModuleLogger
    /// 「取所有正在运行的 App」的**注入点**（先给默认值：生产走 `NSWorkspace`；用例给假体，见文件末尾）。
    private let runningAppsProvider: FrontAppRunningAppsProvider

    /// 观察者 token（`deactivate()` 清空，因此摘了还能再 `start`）。
    private var workspaceTokens: [NSObjectProtocol] = []
    /// 本应用的 bundleID（`excludingSelf` 的判据；nil = 本应用没有 bundleID，那时不排除任何东西）。
    private var selfBundleID: String?
    /// id → 应用包路径：映射快照时记下——`icon(forFile:)` 要的是路径，而快照里只有 bundleID / pid。
    private var bundlePaths: [String: String] = [:]
    /// id → 图标（`icon(forFile:)` 的结果按 id 缓存；首页块反复重绘时不重复取图）。
    private var iconCache: [String: NSImage] = [:]

    /// 额外接收"所有打开的常规 App"的注入点（`runningApps`）：**默认真实现**读
    /// `NSWorkspace.shared.runningApplications`，用例传构造的条目（口径 0 的过滤与排序因此可测）。
    init(
        config: ConfigHandle,
        logger: ModuleLogger,
        runningApps: @escaping FrontAppRunningAppsProvider = FrontAppStore.systemRunningApps
    ) {
        self.config = config
        self.logger = logger
        self.runningAppsProvider = runningApps
    }

    // MARK: 现取的"所有打开的常规 App"

    /// 所有打开的**常规** App（docs/23-home-fit.md §做法 机制三）：当前应用在前，其余按 `recent`
    /// 的次序、再按名称。**每次访问现取一次**（不用通知累积）——用户要的是"所有打开的软件"，
    /// 现取天然包含"本进程启动前就开着的 App"，历史做不到。
    ///
    /// 代价是每次绘制现取一次进程表（本机 159 个进程实测 **0.02ms**，与 `NSWorkspace` 的既有用法同级），
    /// 因此这个 getter 里没有缓存、没有时间窗：`recent` 在过滤排序里**只当排序依据**。
    /// 过滤与排序（含排除自身）全在纯函数 `FrontAppSwitcher.apps(...)` 里，这里只负责"取一次 + 传进去"。
    var switcherApps: [FrontAppSnapshot] {
        FrontAppSwitcher.apps(
            from: runningAppsProvider(),
            current: current,
            recent: recent,
            selfBundleID: selfBundleID
        )
    }

    // MARK: 生命周期

    /// 开始收前台变化事件（模块 `activate()` 调一次；重复调用是空操作）。
    ///
    /// `maxRecentApps` 给 nil 时从 config 读（缺键兜 `FrontAppHistory.defaultLimit`）——
    /// 无论来源是参数还是 config，**夹取只在这里做一次**（口径 3，`FrontAppHistory.clampedLimit`）。
    /// 初值取 `NSWorkspace.shared.frontmostApplication`：模块刚开就要有东西可画，不等第一次切换。
    func start(selfBundleID: String?, maxRecentApps: Int? = nil) {
        guard workspaceTokens.isEmpty else { return }
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
        guard !workspaceTokens.isEmpty else { return }
        for token in workspaceTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceTokens.removeAll()
        logger.info("已摘前台变化观察者")
    }

    // MARK: 动作

    /// 点一个小图标 = 把那个应用切到前台（§机制三）。
    ///
    /// **2026-10-11 / p13b 的两处修复**（用户：「有的应用点击会打开对应的应用，有的就没反应」——
    /// 上屏实测的根因有两条，见 docs/38 §已知限制 9）：
    ///
    /// 1. **`activate()` → `activate(options: [.activateAllWindows])`**：无参那一档只「让这个应用
    ///    成为前台」，**不动它最小化的窗口**——实测窗口在 0 个（最小化 / 收在别的空间）的应用点了
    ///    跟没点一样（菜单栏换了、屏幕上什么都不出现）。带 `.activateAllWindows` 会把它的窗口
    ///    一起提到前面（最小化的也还原），这才是「切过去」的完整语义；
    /// 2. **进程已不在时不再只记一条日志**：那条路径原先什么都不做（用户看到的就是「没反应」），
    ///    现在按记录的包路径**重新打开**它（Dock 点一个没在跑的应用就是这个行为）。pid 被别的进程
    ///    复用的情况同样走这一档——**先比 bundleID**，对不上就当成「已经不在了」。
    ///
    /// **失败路径仍然只记日志、不弹窗**（2026-09-30 起，D-04）：拿不到包路径、`open` 也失败时
    /// 用户看到的是「点了没反应」，但那一条一定在日志里——"没反应且日志里也没有"是最难查的状态。
    func activate(_ snapshot: FrontAppSnapshot) {
        let running = NSRunningApplication(processIdentifier: snapshot.pid)
        let alive = running.map {
            FrontAppSwitcher.isSameApp(
                snapshotBundleID: snapshot.bundleID,
                runningBundleID: $0.bundleIdentifier
            )
        } ?? false
        let path = bundlePaths[snapshot.id]

        switch FrontAppSwitcher.activationRoute(appAlive: alive, hasBundlePath: path != nil) {
        case .activate:
            guard let running else { return }
            if running.activate(options: [.activateAllWindows]) {
                logger.info("激活：\(snapshot.name)（\(snapshot.id) pid \(snapshot.pid)）")
            } else {
                logger.warn("激活失败：\(snapshot.name)（\(snapshot.id) pid \(snapshot.pid)）——系统拒绝了 activate()")
            }
        case .reopen:
            guard let path else { return }
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] app, error in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let error {
                        self.logger.warn("重新打开失败：\(snapshot.name)（\(snapshot.id)）——\(error.localizedDescription)")
                    } else {
                        self.logger.info("重新打开：\(snapshot.name)（\(snapshot.id) pid \(app?.processIdentifier ?? -1)）——原先那一份已退出")
                    }
                }
            }
        case .nothingToDo:
            logger.warn("激活失败：\(snapshot.name)（\(snapshot.id) pid \(snapshot.pid)）——进程已不在，且没有可用的包路径")
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

    /// 注入点的**默认实现**：读一次 `NSWorkspace.shared.runningApplications`，摊成可判定的字段
    /// （`FrontAppRunningApp` 的字段与 `NSRunningApplication` 的取法一一对应）。
    ///
    /// `runningApplications` 是公开 API（不新增权限、不新增出站请求），列的是"正在运行的 App"、
    /// 不含窗口（§已知限制 1）。**筛选不在这里**：`.regular` / 排除自身 / 名称都判在纯函数
    /// `FrontAppSwitcher.apps(...)` 里——"取数"与"筛选"因此各自可替换、可测试。
    @MainActor
    static func systemRunningApps() -> [FrontAppRunningApp] {
        NSWorkspace.shared.runningApplications.map { app in
            FrontAppRunningApp(
                pid: app.processIdentifier,
                bundleID: app.bundleIdentifier,
                name: app.localizedName,
                activationPolicy: app.activationPolicy
            )
        }
    }

    /// 订阅**三条**工作区通知（`queue: .main` → 回调已在主线程；写法照
    /// `DynamicIsland/DynamicIslandApp.swift:214-219` 的既有先例：`userInfo` 里取 `NSRunningApplication`）。
    ///
    /// - `didActivateApplicationNotification`：切换 → 更新 `current` / `recent`（原有那条）；
    /// - `didLaunchApplicationNotification` / `didTerminateApplicationNotification`：**只叫醒视图**
    ///   （`runningGeneration` +1）。2026-10-11 / p13b 补：`switcherApps` 是现取的 computed，
    ///   但视图只在 store 发布时重算——应用启动 / 退出不改 `current` / `recent`，
    ///   此前因此没人叫醒视图：退出的应用留在格子里（点了没反应）、新开的要等下一次切换才出现。
    ///   退出的若正是 `current`，顺手清空它（新前台马上会由 `didActivate` 顶上）。
    private func observeActivations() {
        let center = NSWorkspace.shared.notificationCenter
        func observe(_ name: NSNotification.Name, _ body: @escaping (NSRunningApplication?) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { notification in
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                // `queue: .main` 保证已在主线程，类型层的 `@MainActor` 由此落地（同 `TerminalManager` 的先例）。
                MainActor.assumeIsolated { body(app) }
            }
            workspaceTokens.append(token)
        }

        observe(NSWorkspace.didActivateApplicationNotification) { [weak self] app in
            guard let app else { return }
            self?.handleActivation(of: app)
        }
        observe(NSWorkspace.didLaunchApplicationNotification) { [weak self] _ in
            self?.handleRunningSetChange(terminated: nil)
        }
        observe(NSWorkspace.didTerminateApplicationNotification) { [weak self] app in
            self?.handleRunningSetChange(terminated: app)
        }
        logger.info("已订阅工作区通知（激活 / 启动 / 退出，共 \(workspaceTokens.count) 条）")
    }

    /// 运行名单变了（启动 / 退出）：叫醒视图重算 `switcherApps`；退出的是当前前台时顺手清空。
    private func handleRunningSetChange(terminated: NSRunningApplication?) {
        if FrontAppSwitcher.clearsCurrent(terminatedPid: terminated?.processIdentifier, currentPid: current?.pid) {
            logger.info("前台应用退出：\(current?.name ?? "?")——current 清空，等系统切下一个")
            current = nil
        }
        runningGeneration &+= 1
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

// MARK: - 现取"所有打开的常规 App"（注入点 + 纯函数口径）

/// 一次 `NSWorkspace.shared.runningApplications` 里的**可判定字段**——**不是 `NSRunningApplication`
/// 本身**：那个类没有公开构造器，用例造不出假体，而「筛 `.regular` / 丢无效 pid / 排除自身」这几条
/// 恰恰是最该被用例钉住的（块里列出来的每一格都必须点得动，D-04）。所以把它们摊成值类型。
///
/// 字段与取法一一对应：`pid` = `processIdentifier`、`bundleID` = `bundleIdentifier`、
/// `name` = `localizedName`（**可为 nil**，过滤在纯函数里做）、`activationPolicy` = `activationPolicy`。
/// **图标路径不在这里**：图标只有一条路（`icon(for:)`），不因数据来源变化多出第二条。
struct FrontAppRunningApp: Equatable {
    let pid: pid_t
    let bundleID: String?
    let name: String?
    let activationPolicy: NSApplication.ActivationPolicy

    init(pid: pid_t, bundleID: String?, name: String?, activationPolicy: NSApplication.ActivationPolicy) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.activationPolicy = activationPolicy
    }
}

/// 「取所有正在运行的 App」的**注入点**：生产实现 = `FrontAppStore.systemRunningApps`（读真
/// `NSWorkspace`），用例传构造的条目——于是用例既不依赖跑测试这台机器上开着什么，也不起真进程。
typealias FrontAppRunningAppsProvider = @MainActor () -> [FrontAppRunningApp]

/// `switcherApps` 的**纯函数口径**：过滤 → 排除自身 → 排序 → 去重。四条各管一件事（注释见实现）。
///
/// 顺序就是契约（docs/23-home-fit.md §做法 机制三 / §接口与数据形状）：
/// **当前应用 → `recent` 里的次序 → 名称（本地化比较）→ pid**；最后一项只为"稳定"兜底
/// （Swift 的 `sorted` 不保证稳定，同名同 id 时不能让两轮渲染给出不同次序）。
enum FrontAppSwitcher {

    // MARK: 点一格之后该做什么（p13b / 2026-10-11）

    /// 点一格的**三种结局**（纯值，用例直接钉）。
    ///
    /// 用户 2026-10-11 的反馈是「有的应用点击会打开对应的应用，有的就没反应」——
    /// 上屏实测两条根因（docs/38 §已知限制 9）：① 无参 `activate()` 不动最小化的窗口（窗口数为 0
    /// 的应用点了跟没点一样）；② 进程已不在时旧实现什么都不做。本枚举把「该做哪件事」写成一个
    /// 可测的判定，`FrontAppStore.activate(_:)` 只负责执行：
    enum ActivationRoute: Equatable {
        /// 进程还在、且那个 pid 仍是同一个应用 → `activate(options: [.activateAllWindows])`
        /// （把它的窗口一起提到前面，最小化的也还原）。
        case activate
        /// 进程已不在 / pid 已被别的应用拿走，但知道它的包路径 → **重新打开**（Dock 点没在跑的应用
        /// 就是这个行为）。
        case reopen
        /// 进程已不在、又没有包路径（命令行工具那类）→ 什么都做不了（只记一条日志）。
        case nothingToDo
    }

    /// 判据：**进程还在就切过去**；不在了就看有没有包路径。
    static func activationRoute(appAlive: Bool, hasBundlePath: Bool) -> ActivationRoute {
        if appAlive { return .activate }
        return hasBundlePath ? .reopen : .nothingToDo
    }

    /// pid 复用的判据（纯函数）：退出后新起的进程可能拿到同一个 pid，那时
    /// `NSRunningApplication(processIdentifier:)` 会给出**别的应用**——把它的 bundleID 与快照比，
    /// 对不上就当成「已经不在了」。快照没有 bundleID（命令行工具那类）时只认 pid。
    static func isSameApp(snapshotBundleID: String?, runningBundleID: String?) -> Bool {
        guard let expected = snapshotBundleID else { return true }
        return runningBundleID == expected
    }

    /// 退出的那个应用是不是**当前前台**（纯函数）：是就把 `current` 清掉（新的前台马上由
    /// `didActivate` 顶上，留着一个已退出的 pid 会让格子里第一位永远是点不动的幽灵）。
    static func clearsCurrent(terminatedPid: pid_t?, currentPid: pid_t?) -> Bool {
        guard let terminatedPid, let currentPid else { return false }
        return terminatedPid == currentPid
    }

    /// 条目 → 可画的 App 列表。`current` / `recent` / `selfBundleID` 都从参数进来（不读 store），
    /// 因此用例能用手造值驱动全部边界。
    static func apps(
        from running: [FrontAppRunningApp],
        current: FrontAppSnapshot?,
        recent: [FrontAppSnapshot],
        selfBundleID: String?
    ) -> [FrontAppSnapshot] {
        // ① 过滤 + 映射：三条判据各自挡住一类"列出来也点不动"的条目
        //    （非 `.regular`：台前调度那类系统 UI 进程；`pid <= 0`：没有可激活进程；
        //    名字 nil / 空 / 只有空白：画出来是一格空白图标，用户认不出是谁）。
        //    名字**原样带过来**（与 `snapshot(of:)` 同一条口径：显示用的名字不在这里改写）。
        var snapshots: [FrontAppSnapshot] = []
        for entry in running {
            guard entry.activationPolicy == .regular, entry.pid > 0 else { continue }
            guard let name = entry.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            snapshots.append(FrontAppSnapshot(bundleID: entry.bundleID, name: name, pid: entry.pid))
        }

        // ② 排除自身：「自身」的判据只有一处（`FrontAppHistory.excludingSelf`，口径 2）。
        let others = FrontAppHistory.excludingSelf(snapshots, selfBundleID: selfBundleID)

        // ③ 排序：当前应用置顶 → 最近切换过的按 `recent` 的次序 → 其余按名称。
        //    `recent` 里有重复 id 时取**更靠前的那次**（新在前），不崩、也不挑后面的。
        let recentRank = Dictionary(
            recent.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        // `recent` 的条目带着 **pid**：同一个 bundleID 跑了两份时，`recentRank` 分辨不出是哪一份
        // （它按 id 建索引），pid 才分得出"你刚用的是哪一份"——去重那一步（④）靠它挑对实例。
        let recentPids = Set(recent.map(\.pid))
        let currentID = current?.id
        let ordered = others.sorted { lhs, rhs in
            let lhsIsCurrent = lhs.id == currentID
            let rhsIsCurrent = rhs.id == currentID
            if lhsIsCurrent != rhsIsCurrent { return lhsIsCurrent }

            let lhsRank = recentRank[lhs.id] ?? Int.max
            let rhsRank = recentRank[rhs.id] ?? Int.max
            if lhsRank != rhsRank { return lhsRank < rhsRank }

            switch lhs.name.localizedStandardCompare(rhs.name) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame:
                // 同名（绝大多数是同 id 的两个实例）：优先留最近用过的那一份，其余按 pid 升序
                let lhsUsed = recentPids.contains(lhs.pid)
                let rhsUsed = recentPids.contains(rhs.pid)
                if lhsUsed != rhsUsed { return lhsUsed }
                return lhs.pid < rhs.pid
            }
        }

        // ④ 同一个 `id` 只留一格：同一个 .app 被 `open -n` 起两份时，两条条目的 `id` 会撞，
        //    而 `ForEach` 的 id 撞了会让 SwiftUI 认错格子。留下的是**排序里靠前的那一份**
        //    （因此"最近切换过的那一份"优先——它的 pid 才是该点的那个）。
        var seen = Set<String>()
        return ordered.filter { seen.insert($0.id).inserted }
    }
}
