//
//  NotificationBannerObserver.swift
//  Gourd 内置模块 · AX 横幅通道（实时捕获 + 探针落盘）
//
//  设计依据：docs/09-features-and-mechanisms.md §5.5「AX = 实时 + 可真关闭」。
//  解决的问题：数据库通道（`NotificationCenterReader`）要等 macOS 把通知**批量落盘**
//  （本机实测固定 5.0～5.1s），所以「造一条通知 → 上手浮层」端到端约 5.3s。
//  通知中心把横幅画在屏幕上时**立刻**就有 AX 元素可读，所以这条通道亚秒级到达。
//
//  ## 双通道口径（09 §5.5）
//  - **AX = 实时 + 可真关闭**：依赖通知中心的 AX 树（角色/子角色/自定义动作名），
//    随系统版本可能失效——所以每个新窗口的**完整树**都要落盘（`ax-banner-probe.log`），
//    schema 变了以后靠这份原文校准；
//  - **DB = 历史列表与降级**：实时性受 macOS 落盘延迟（~5s）限制，但它是**稳定的兜底**，
//    列表 / 未读计数 / 点击打开 App 都归它。
//
//  ## 本机实测（macOS 27，2026-09-28，探针记录）
//  横幅树（`osascript display notification "正文" with title "标题" [subtitle]`）：
//  ```
//  role=AXWindow subrole=AXSystemDialog title="Notification Center"
//    role=AXGroup subrole=AXHostingView
//      role=AXGroup
//        role=AXScrollArea
//          role=AXGroup subrole=AXNotificationCenterBanner desc="脚本编辑器 标题, 副标题, 正文"
//            role=AXStaticText value="标题"
//            role=AXStaticText value="副标题"
//            role=AXStaticText value="正文"
//  ```
//  三条实测结论（都影响实现，**别按「教科书 AX」写**）：
//  1. **App 名不在静态文本里**，只在横幅容器的 `AXDescription` 首段（`"<App 名> <标题>, ..."`）；
//  2. **关闭不是 `AXButton`**：横幅容器的动作表里有一个**自定义动作**，名字长这样
//     `Name:关闭\nTarget:0x0\nSelector:(null)`——要对**横幅容器**执行**这个名字**的动作用才关得掉
//     （对 `AXPress` 只是「显示详细信息」）。带副标题的横幅偶尔会额外暴露 `AXButton desc=关闭`
//     （本机只观察到一次），所以两条路都认：**先找关闭按钮，再找自定义动作**；
//  3. **动作返回值不可信**：`AXUIElementPerformAction` 传一个**不存在的动作名**也返回 `0`（成功）。
//     因此 `performAndVerify()` 的成功判据是「动作返回成功 **且** 元素随后失效」，不能只看返回值。
//
//  ## 挂载方式（两条路互为兜底）
//  - `AXObserver`：监听 `kAXWindowCreatedNotification`（事件到了立刻扫，标称 0 延迟）；
//  - **0.5s 轻量轮询**：比对通知中心 app 的 `kAXWindowsAttribute` 窗口集合与上次的差异，取新增窗口。
//    AXObserver 在本机**不是每条横幅都触发**（实测多次只来一次），轮询是必需的第二条路。
//  两条都做「按窗口签名去重」：同一个窗口不会被扫两次（否则轮询每 0.5s 都报一遍）。
//
//  ## 进程重启
//  通知中心的 `com.apple.notificationcenterui` **会被系统重启**（本机实测：`killall NotificationCenter`
//  后 pid 813 → 44809）——每次 tick 重新解析 pid，变了就**重挂** AXObserver（旧 observer 连同
//  run loop source 一起拆掉）。不重挂的话进程一重启这条通道就永久哑掉。
//
//  ## 权限
//  `AXIsProcessTrusted() == false` 时**不启动**：返回空取消闭包 + 记一条日志（静默降级——
//  DB 通道仍可用，模块侧的列表与历史不受影响）。本模块**不申请、不提示**任何权限。
//
//  ## 只读原则
//  除了 `AXPress` / 自定义「关闭」动作本身（用户点浮层或列表的 × 时才发生），
//  本文件对通知中心界面**只读**：只读属性、不做任何其它写操作、不改通知库。
//

import AppKit
import ApplicationServices
import Foundation
import os

// MARK: - AX 快照（探针与解析的公共输入）

/// 一棵 AX 元素树的**纯数据快照**。
///
/// 为什么要有它：解析逻辑必须是**纯函数**才能单测（单测里没有真横幅、也不该起 AX IPC），
/// 所以真机路径先 `snapshot(of:)` 把 AX 元素读成快照，解析与探针渲染都只吃快照。
struct AXNodeSnapshot: Equatable, Sendable {
    var role: String = ""
    var subrole: String = ""
    var title: String = ""
    var description: String = ""
    var value: String = ""
    /// 该元素支持的动作名（`AXUIElementCopyActionNames`）——macOS 27 的「关闭」就在这里。
    var actionNames: [String] = []
    var children: [AXNodeSnapshot] = []

    /// 最省事的「这一格有没有文字」判据（探针与解析共用）。
    var text: String {
        if !value.isEmpty { return value }
        if !title.isEmpty { return title }
        return description
    }
}

// MARK: - 解析结果

/// 从一棵横幅树里解析出来的内容（**纯数据**，不持有 AX 句柄 → 可单测）。
struct NotificationBannerContent: Equatable, Sendable {
    /// App 显示名（通常只有横幅容器的 `AXDescription` 里才有，见文件头实测 ①）。
    var appName = ""
    var title = ""
    var subtitle = ""
    var body = ""
    /// 命中的关闭控件描述（`nil` = 没找到关闭按钮/动作 → 只能「仅从岛上隐藏」）。
    var closeLabel: String?
    /// 关闭要执行的动作名：`AXPress`（真按钮）或自定义动作名（macOS 27 实测形态）。
    var closeActionName: String?
    /// 树里**真的**有 `AXNotificationCenterBanner`（false = 这不是一条横幅，探针照记、不上报）。
    var foundBannerRoot = false

    /// 一条横幅最少的可呈现内容（全空 = 不值得弹浮层）。
    var hasContent: Bool {
        !(title.isEmpty && subtitle.isEmpty && body.isEmpty)
    }
}

// MARK: - 关闭句柄

/// 「真关闭一条系统通知」的句柄：`AXUIElement` + 动作名。
///
/// **为什么不是 `AXButton`**：macOS 27 的横幅关闭是**容器上的自定义动作**（文件头实测 ②），
/// 所以句柄记的是「对哪个元素执行哪个动作」，按钮只是其中一种形态。
/// `@unchecked Sendable`：`AXUIElement` 是 CF 类型、本身没有 Sendable 标注，但 AX API 是
/// 跨线程安全的（我们只在后台队列上同步执行一次），因此显式承担这个标注。
struct NotificationBannerCloseHandle: @unchecked Sendable {
    let element: AXUIElement
    let actionName: String
    /// 日志与探针用的可读描述（如 `AXButton desc=关闭` / `自定义动作 关闭`）。
    let label: String

    /// 元素是否还有效（横幅被关掉后 AX 元素会失效——这是**唯一可信**的成功信号，
    /// 因为动作返回值对不存在的动作也返回成功，见文件头实测 ③）。
    var isValid: Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success
    }

    /// 同步执行关闭（AX IPC，**调用方负责放到后台队列**）。
    ///
    /// 返回「动作返回成功 **且** 元素已失效」。元素仍有效时返回 false —— 那说明没关掉，
    /// 调用方退化为「仅从岛上隐藏」（不弹错误，只记日志）。
    ///
    /// 判定**要轮询**（不是测一次）：关闭有动画与异步清理，本机实测按下后元素在
    /// ≤ 0.6s 内从树里消失；只测一次会把「已经关掉、只是还没清理完」误判成失败。
    /// 轮询全程在后台队列上，最长 ~0.6s，不占主线程、不影响浮层（浮层点完即本地隐藏）。
    func performAndVerify(timeout: TimeInterval = 0.64, step: TimeInterval = 0.08) -> Bool {
        let result = AXUIElementPerformAction(element, actionName as CFString)
        guard result == .success else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            usleep(useconds_t(step * 1_000_000))
            if !isValid { return true }
        }
        return !isValid
    }
}

// MARK: - 横幅事件

/// 一条 AX 横幅（模块侧据此**立即**弹浮层，不等数据库）。
struct BannerEvent: Sendable {
    let appName: String
    let title: String
    let subtitle: String
    let body: String
    /// 真关闭句柄（nil = 这条横幅没有可用的关闭控件）。
    ///
    /// 注：设计稿写的是 `closeButton: AXUIElement?`；macOS 27 实测关闭是**自定义动作**
    /// （不是 `AXButton`），所以这里换成「元素 + 动作名」的句柄，语义不变。
    let closeHandle: NotificationBannerCloseHandle?
    /// 捕获时刻（模块侧弹浮层与去重都用它）。
    let receivedAt: Date

    /// 指纹用的三段（去重口径：appName + title + body，见 `NotificationFingerprint`）。
    var fingerprint: NotificationFingerprint {
        NotificationFingerprint(appName: appName, title: title, body: body)
    }
}

// MARK: - 解析器（纯函数）

/// 横幅树的解析器与渲染器：**全部是纯函数**（输入快照，输出内容/文本），
/// 因此可以在单测里用构造的树钉住口径，不需要真机也不需要 AX 权限。
enum NotificationBannerParser {
    /// 通知横幅容器的子角色（唯一稳定的识别标志）。
    static let bannerSubrole = "AXNotificationCenterBanner"
    /// 关闭控件的候选关键词（大小写不敏感；`Close` / `关闭` / `Dismiss` / `清除`）。
    static let closeKeywords = ["close", "dismiss", "关闭", "清除"]
    /// 树的上限：深度 8、节点 200（探针要「完整树」，但不是「无限树」——
    /// 通知中心面板开着时窗口里有几百行，不设上限会把这条通道拖卡）。
    static let maxDepth = 8
    static let maxNodes = 200

    // MARK: 定位

    /// 在快照里定位「横幅容器」的**子索引路径**（nil = 树里没有横幅容器）。
    ///
    /// 返回路径而不是节点：真机路径要按同一条路径取回**真 AX 元素**去执行关闭动作，
    /// 让「纯解析」与「真句柄」永远指向同一个元素。
    static func bannerPath(in root: AXNodeSnapshot) -> [Int]? {
        var count = 0
        return bannerPath(in: root, path: [], depth: 0, count: &count)
    }

    private static func bannerPath(
        in node: AXNodeSnapshot,
        path: [Int],
        depth: Int,
        count: inout Int
    ) -> [Int]? {
        guard depth <= maxDepth, count < maxNodes else { return nil }
        count += 1
        if node.subrole == bannerSubrole { return path }
        for (index, child) in node.children.enumerated() {
            if let hit = bannerPath(in: child, path: path + [index], depth: depth + 1, count: &count) {
                return hit
            }
        }
        return nil
    }

    /// 按路径取节点（越界返回 nil）。
    static func node(at path: [Int], in root: AXNodeSnapshot) -> AXNodeSnapshot? {
        var current = root
        for index in path {
            guard index >= 0, index < current.children.count else { return nil }
            current = current.children[index]
        }
        return current
    }

    // MARK: 解析

    /// 快照 → 内容。**防御式**：任何一步取不到都给空值/`nil`，绝不抛错也绝不崩。
    static func parse(_ root: AXNodeSnapshot) -> NotificationBannerContent {
        var content = NotificationBannerContent()
        let path = bannerPath(in: root)
        content.foundBannerRoot = path != nil
        // 没有横幅容器时退回整棵树解析：探针仍要给出「尽力解析」的结果供校准。
        let scope = path.flatMap { node(at: $0, in: root) } ?? root

        let texts = staticTexts(in: scope)
        content.title = texts.first ?? ""
        if texts.count >= 3 {
            content.subtitle = texts[1]
            content.body = texts[2]
        } else if texts.count == 2 {
            content.body = texts[1]
        }
        content.appName = appName(fromDescription: scope.description, title: content.title, body: content.body)

        if let button = firstCloseButton(in: scope) {
            content.closeLabel = "AXButton: \(button.text)"
            content.closeActionName = kAXPressAction as String
        } else if let action = firstCloseAction(in: scope) {
            content.closeLabel = "自定义动作: \(action)"
            content.closeActionName = action
        }
        return content
    }

    /// App 名：横幅容器的 `AXDescription` 形如 `"<App 名> <标题>, <副标题>, <正文>"`，
    /// 而 App 名**没有**独立的静态文本元素（文件头实测 ①）。
    ///
    /// 所以从**首段**里把已知的标题（或正文）后缀剥掉：
    /// - 剥得掉 → 剩下的就是 App 名（两端空白清掉）；
    /// - 剥不掉 / 剥空了 → 给空串（**不猜**：宁可让上层退化为通用文案，也不要把标题当 App 名）。
    static func appName(fromDescription description: String, title: String, body: String) -> String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let firstSegment = trimmed
            .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? trimmed
        let segment = firstSegment.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [title, body] where !suffix.isEmpty {
            guard segment.hasSuffix(suffix) else { continue }
            let rest = String(segment.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty { return rest }
        }
        return ""
    }

    /// 深度优先收集静态文本（**保持树序**：实测顺序是 标题 → 副标题 → 正文）。
    static func staticTexts(in root: AXNodeSnapshot) -> [String] {
        var values: [String] = []
        var count = 0
        collect(root, depth: 0, count: &count) { node in
            guard node.role == "AXStaticText" else { return }
            let text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { values.append(text) }
        }
        return values
    }

    /// 第一个关闭按钮（`AXButton` 且 `AXDescription`/`AXTitle` 命中关闭关键词）。
    static func firstCloseButton(in root: AXNodeSnapshot) -> AXNodeSnapshot? {
        var found: AXNodeSnapshot?
        var count = 0
        collect(root, depth: 0, count: &count) { node in
            guard found == nil, node.role == "AXButton" else { return }
            let label = [node.description, node.title].joined(separator: " ")
            if matchesCloseKeyword(label) { found = node }
        }
        return found
    }

    /// 第一个关闭**自定义动作**（横幅容器自己的动作表里命中关闭关键词的那个）。
    ///
    /// 实测名字是 `"Name:关闭\nTarget:0x0\nSelector:(null)"`，所以只按「含关闭关键词」认，
    /// 执行时**原样**把这个名字传回 `AXUIElementPerformAction`（截断过就执行不了）。
    static func firstCloseAction(in root: AXNodeSnapshot) -> String? {
        root.actionNames.first { matchesCloseKeyword($0) }
    }

    /// 关键词匹配（大小写不敏感）：`Close` / `关闭` / `Dismiss` / `清除`。
    static func matchesCloseKeyword(_ text: String) -> Bool {
        let lower = text.lowercased()
        return closeKeywords.contains { lower.contains($0) }
    }

    // MARK: 渲染（探针）

    /// 快照 → 探针文本（带缩进、受深度/节点上限约束）。行内尽量把**所有**有用字段写全：
    /// 校准靠的就是这份原文（role / subrole / title / description / value / 动作名 / 前 80 字符）。
    static func render(_ root: AXNodeSnapshot) -> [String] {
        var lines: [String] = []
        var count = 0
        renderNode(root, depth: 0, count: &count, lines: &lines)
        if count >= maxNodes {
            lines.append("  …（节点数达到上限 \(maxNodes)，其余省略）")
        }
        return lines
    }

    private static func renderNode(
        _ node: AXNodeSnapshot,
        depth: Int,
        count: inout Int,
        lines: inout [String]
    ) {
        guard depth <= maxDepth, count < maxNodes else { return }
        count += 1
        let indent = String(repeating: "  ", count: depth)
        var line = "\(indent)role=\(node.role)"
        if !node.subrole.isEmpty { line += " subrole=\(node.subrole)" }
        line += " title=\"\(escaped(node.title, limit: 80))\""
        line += " description=\"\(escaped(node.description, limit: 80))\""
        line += " value=\"\(escaped(node.value, limit: 80))\""
        if !node.actionNames.isEmpty {
            let names = node.actionNames.map { $0.replacingOccurrences(of: "\n", with: "\\n") }
            line += " actions=\(names)"
        }
        lines.append(line)
        for child in node.children {
            renderNode(child, depth: depth + 1, count: &count, lines: &lines)
        }
    }

    /// 前 `limit` 个字符 + 换行/引号转义（探针是**追加的单文件**，一行一个元素才便于 grep）。
    static func escaped(_ text: String, limit: Int) -> String {
        let clipped = text.count > limit ? String(text.prefix(limit)) + "…" : text
        return clipped
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }

    private static func collect(
        _ node: AXNodeSnapshot,
        depth: Int,
        count: inout Int,
        visit: (AXNodeSnapshot) -> Void
    ) {
        guard depth <= maxDepth, count < maxNodes else { return }
        count += 1
        visit(node)
        for child in node.children {
            collect(child, depth: depth + 1, count: &count, visit: visit)
        }
    }

    // MARK: 真机路径（AX 元素 ↔ 快照 / 句柄）

    /// AX 元素 → 快照（受同样的深度/节点上限约束）。**会做 IPC**，只在后台队列调用。
    static func snapshot(of element: AXUIElement, depth: Int = 0, count: inout Int) -> AXNodeSnapshot {
        var node = AXNodeSnapshot()
        guard depth <= maxDepth, count < maxNodes else { return node }
        count += 1
        node.role = AXBridge.string(element, kAXRoleAttribute)
        node.subrole = AXBridge.string(element, kAXSubroleAttribute)
        node.title = AXBridge.string(element, kAXTitleAttribute)
        node.description = AXBridge.string(element, kAXDescriptionAttribute)
        node.value = AXBridge.string(element, kAXValueAttribute)
        node.actionNames = AXBridge.actionNames(element)
        for child in AXBridge.children(element) {
            node.children.append(snapshot(of: child, depth: depth + 1, count: &count))
            if count >= maxNodes { break }
        }
        return node
    }

    /// 便捷形态（从这里开始一律用计数上限）。
    static func snapshot(of element: AXUIElement) -> AXNodeSnapshot {
        var count = 0
        return snapshot(of: element, depth: 0, count: &count)
    }

    /// 真机路径：按 `bannerPath` 取回**真元素**（关闭动作要打在它上面）。
    static func bannerElement(in root: AXUIElement, path: [Int]) -> AXUIElement? {
        var current = root
        for index in path {
            let kids = AXBridge.children(current)
            guard index >= 0, index < kids.count else { return nil }
            current = kids[index]
        }
        return current
    }

    /// 真机路径：找关闭控件 → 句柄。
    ///
    /// 顺序与纯解析严格一致：**先按钮、后自定义动作**（同 `parse`），
    /// 因此单测钉住的判定规则对真机同样成立。
    static func closeHandle(in root: AXUIElement, bannerPath: [Int]?) -> NotificationBannerCloseHandle? {
        let banner = bannerPath.flatMap { bannerElement(in: root, path: $0) } ?? root
        if let button = firstCloseButtonElement(in: banner) {
            return NotificationBannerCloseHandle(
                element: button,
                actionName: kAXPressAction as String,
                label: "AXButton: \(AXBridge.string(button, kAXDescriptionAttribute))"
            )
        }
        if let action = firstCloseActionName(in: banner) {
            return NotificationBannerCloseHandle(element: banner, actionName: action, label: "自定义动作: \(action)")
        }
        return nil
    }

    private static func firstCloseButtonElement(in root: AXUIElement) -> AXUIElement? {
        var count = 0
        return firstCloseButtonElement(in: root, depth: 0, count: &count)
    }

    private static func firstCloseButtonElement(
        in node: AXUIElement,
        depth: Int,
        count: inout Int
    ) -> AXUIElement? {
        guard depth <= maxDepth, count < maxNodes else { return nil }
        count += 1
        if AXBridge.string(node, kAXRoleAttribute) == "AXButton" {
            let label = AXBridge.string(node, kAXDescriptionAttribute) + " " + AXBridge.string(node, kAXTitleAttribute)
            if matchesCloseKeyword(label) { return node }
        }
        for child in AXBridge.children(node) {
            if let hit = firstCloseButtonElement(in: child, depth: depth + 1, count: &count) { return hit }
        }
        return nil
    }

    private static func firstCloseActionName(in element: AXUIElement) -> String? {
        AXBridge.actionNames(element).first { matchesCloseKeyword($0) }
    }
}

// MARK: - AX 调用小工具

/// AX API 的薄封装（**只读**：读属性、读子元素、读动作名）。
enum AXBridge {
    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    /// 属性 → 字符串（非字符串属性给空串：探针不需要 `AXValue` 的几何数据）。
    static func string(_ element: AXUIElement, _ name: String) -> String {
        guard let value = attribute(element, name) else { return "" }
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    static func actionNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return (names as? [String]) ?? []
    }

    static func windows(_ app: AXUIElement) -> [AXUIElement] {
        (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }
}

// MARK: - 观察器

/// 监听通知中心横幅的观察器（AXObserver + 0.5s 轮询兜底）。
///
/// 线程模型（三条约定）：
/// 1. `start` / `stop` **可从任意线程调用**——AXObserver 的建/拆与 run loop source 的
///    增删都在内部串行队列上做（CFRunLoop 的 source 增删自身是同步的），observer 的
///    run loop source 挂在**主 run loop** 上，所以回调在主线程触发；
/// 2. 回调本身**不做 AX 调用**，只把扫描甩回内部串行队列（AX IPC 不能占主线程）；
/// 3. `onBanner` 回调**回主队列**投递（模块侧是 `@MainActor`，这样接进去不用再跳一次）。
final class NotificationBannerObserver: @unchecked Sendable {
    /// 通知中心 App 的 bundle id（**按 id 匹配，不用显示名**：显示名是「通知中心」这种本地化串）。
    static let notificationCenterBundleID = "com.apple.notificationcenterui"
    /// 轮询间隔（秒）：AXObserver 会漏，这条是必需的第二条路。0.5s 的 AX 属性读很廉价。
    static let pollInterval: TimeInterval = 0.5

    /// 横幅树的探针原文（追加写）。schema 私有 → 这份原文是后续校准的唯一依据。
    static let bannerProbeLogPath = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Gourd/ax-banner-probe.log")
        .path
    /// 解析结果（与数据库探针同一个文件，便于对照两条通道）。
    static let parseLogPath = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Gourd/notifications-probe.log")
        .path
    /// 单个探针日志的上限：超过就轮转一次（窗口每次变化都写树，不设限会无限增长）。
    static let logSizeLimit = 4 * 1024 * 1024

    /// 诊断日志**刻意不走宿主 `Logger`**（那条路受设置里的 `logLevel` 闸门控制，默认全静默），
    /// 直出统一日志：`log stream --info --predicate 'subsystem BEGINSWITH "com.cmeng.gourd"'`。
    private static let logger = os.Logger(
        subsystem: "com.cmeng.gourd.module.notifications",
        category: "ax-banner"
    )

    private let queue = DispatchQueue(label: "com.cmeng.gourd.notifications.ax-banner")
    private let lock = NSLock()
    private let onBanner: (BannerEvent) -> Void

    private var timer: DispatchSourceTimer?
    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    /// 已见过的窗口签名（`scan` 里与**当前**窗口集合求交，窗口消失后同签名可再次上报）。
    private var seenSignatures: Set<String> = []
    private var isStopped = false
    private var isScanning = false

    init(onBanner: @escaping (BannerEvent) -> Void) {
        self.onBanner = onBanner
    }

    deinit { stop() }

    /// 开始观察。返回值是**取消闭包**（幂等；`deactivate()` 调它）。
    ///
    /// 未授权（`AXIsProcessTrusted() == false`）时**直接不启动**：返回空闭包 + 记一条日志，
    /// 不申请权限、不弹提示、不抛错（DB 通道仍照常工作）。
    func start() -> () -> Void {
        guard AXIsProcessTrusted() else {
            Self.logger.warning("辅助功能未授权：AX 横幅通道不启动（DB 通道仍可用，静默降级）")
            return {}
        }
        lock.lock()
        if isStopped {
            lock.unlock()
            return {}
        }
        lock.unlock()
        Self.logger.info("AX 横幅通道启动（AXObserver + \(Self.pollInterval, privacy: .public)s 轮询兜底）")

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.pollInterval, repeating: Self.pollInterval, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.scan(reason: "轮询") }
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.timer = timer
            self.lock.unlock()
            // 起 timer 前先扫一次：启动瞬间可能已经有横幅在屏上。
            timer.resume()
            self.scan(reason: "启动")
        }
        return { [weak self] in self?.stop() }
    }

    /// 停止观察：拆 AXObserver（含 run loop source）+ 取消 timer（幂等）。
    func stop() {
        lock.lock()
        guard !isStopped else {
            lock.unlock()
            return
        }
        isStopped = true
        seenSignatures.removeAll()
        let timer = self.timer
        self.timer = nil
        let observer = self.observer
        self.observer = nil
        lock.unlock()

        timer?.cancel()
        if let observer { detach(observer) }
        Self.logger.info("AX 横幅通道已停止")
    }

    // MARK: 扫描（全部在 `queue` 上）

    private func scan(reason: String) {
        lock.lock()
        let stopped = isStopped
        if !stopped {
            guard !isScanning else {
                lock.unlock()
                return  // 上一轮还没扫完（AX 卡住时会发生）：丢掉这次 tick，不排队堆积
            }
            isScanning = true
        }
        lock.unlock()
        guard !stopped else { return }
        defer {
            lock.lock()
            isScanning = false
            lock.unlock()
        }

        guard let pid = Self.notificationCenterPID() else {
            // 通知中心没在跑：不是错误（无横幅可观察），下次 tick 再看。
            remountObserver(pid: 0)
            return
        }
        remountObserver(pid: pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        let windows = AXBridge.windows(app)

        var currentSignatures: Set<String> = []
        for window in windows {
            let snapshot = NotificationBannerParser.snapshot(of: window)
            let signature = Self.signature(of: snapshot)
            currentSignatures.insert(signature)
            let isNew = lock.withLock { !seenSignatures.contains(signature) }
            guard isNew else { continue }
            lock.withLock { _ = seenSignatures.insert(signature) }
            handleNewWindow(snapshot: snapshot, root: window, reason: reason)
        }
        // 窗口消失 → 从「已见」里去掉（同一条通知再来一次仍要能上报）
        lock.withLock { seenSignatures.formIntersection(currentSignatures) }
    }

    /// 新窗口：**先落探针原文**（探针是这一批的第一目的），再解析 → 上报。
    private func handleNewWindow(snapshot: AXNodeSnapshot, root: AXUIElement, reason: String) {
        let content = NotificationBannerParser.parse(snapshot)
        Self.appendLog(
            Self.bannerProbeLogPath,
            """
            ===== AX 横幅探针 @ \(Self.timestamp())（\(reason)，pid \(Self.notificationCenterPID() ?? 0)）=====
            \(NotificationBannerParser.render(snapshot).joined(separator: "\n"))
            """
        )
        Self.appendLog(Self.parseLogPath, Self.parseReport(content))

        guard content.foundBannerRoot else {
            Self.logger.debug("新窗口不是通知横幅（树里没有 \(NotificationBannerParser.bannerSubrole, privacy: .public)）：已记探针，不上报")
            return
        }
        guard content.hasContent || content.closeActionName != nil else {
            Self.logger.debug("横幅没有可呈现内容：已记探针，不上报")
            return
        }

        let event = BannerEvent(
            appName: content.appName,
            title: content.title,
            subtitle: content.subtitle,
            body: content.body,
            closeHandle: NotificationBannerParser.closeHandle(
                in: root,
                bannerPath: NotificationBannerParser.bannerPath(in: snapshot)
            ),
            receivedAt: Date()
        )
        Self.logger.info(
            "AX 横幅：app=\(event.appName, privacy: .public) title=\(event.title, privacy: .public) 关闭控件=\(event.closeHandle?.label ?? "无", privacy: .public)"
        )
        DispatchQueue.main.async { [onBanner] in onBanner(event) }
    }

    /// 解析结果 → `notifications-probe.log` 的一段（与数据库探针同文件，便于对照）。
    private static func parseReport(_ content: NotificationBannerContent) -> String {
        var lines: [String] = []
        lines.append("===== Gourd AX 横幅解析（09 §5.5 AX 通道）=====")
        lines.append("时间: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("命中横幅容器(subrole=\(NotificationBannerParser.bannerSubrole)): \(content.foundBannerRoot ? "是" : "否")")
        lines.append("解析: appName=\"\(content.appName)\" title=\"\(content.title)\" "
            + "subtitle=\"\(content.subtitle)\" body=\"\(content.body)\"")
        lines.append("关闭控件: \(content.closeLabel ?? "无（只能「仅从岛上隐藏」）")")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// 窗口签名（去重口径）：`自身与子树里最长的那个 description/value` + 结构摘要。
    ///
    /// **刻意不含窗口坐标**：横幅有滑入动画（本机实测同一横幅的 x 从 1508 变到 1152），
    /// 带上坐标会把同一条横幅当成两个窗口反复上报。代价是同文案的两条横幅会被并成一条——
    /// 但模块侧还有「指纹 + 10 秒窗口」去重，本来也只弹一次，所以这个代价可以接受。
    private static func signature(of snapshot: AXNodeSnapshot) -> String {
        var parts: [String] = []
        var count = 0
        collectSignature(snapshot, depth: 0, count: &count, parts: &parts)
        return parts.joined(separator: "|")
    }

    private static func collectSignature(
        _ node: AXNodeSnapshot,
        depth: Int,
        count: inout Int,
        parts: inout [String]
    ) {
        guard depth <= NotificationBannerParser.maxDepth, count < NotificationBannerParser.maxNodes else { return }
        count += 1
        if !node.subrole.isEmpty { parts.append(node.subrole) }
        if !node.description.isEmpty { parts.append(node.description) }
        if !node.value.isEmpty { parts.append(String(node.value.prefix(60))) }
        for child in node.children {
            collectSignature(child, depth: depth + 1, count: &count, parts: &parts)
        }
    }

    // MARK: AXObserver 挂载 / 重挂

    /// 目标 pid 与当前挂载不一致时重挂（进程重启、首次挂载、进程消失都走这里）。
    private func remountObserver(pid: pid_t) {
        lock.lock()
        let current = observedPID
        let existing = observer
        lock.unlock()
        guard pid != current else { return }
        if let existing { detach(existing) }
        guard pid > 0 else {
            lock.withLock { observedPID = 0; observer = nil }
            return
        }
        guard let observer = makeObserver(pid: pid) else {
            lock.withLock { observedPID = 0; self.observer = nil }
            return
        }
        lock.lock()
        observedPID = pid
        self.observer = observer
        lock.unlock()
        Self.logger.info("已挂 AXObserver：pid \(pid, privacy: .public)（kAXWindowCreatedNotification）")
    }

    /// 建 observer 并把 run loop source 加到**主 run loop**（`start` 已在主线程）。
    private func makeObserver(pid: pid_t) -> AXObserver? {
        var observer: AXObserver?
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverCreate(pid, notificationBannerObserverCallback, &observer) == .success,
              let observer else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        let added = AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, context)
        guard added == .success || added == .notificationAlreadyRegistered else {
            Self.logger.warning("AXObserverAddNotification 失败：\(added.rawValue, privacy: .public)")
            return nil
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        return observer
    }

    /// 拆 observer：run loop source 与 observer 一起释放（`stop` 与重挂共用）。
    private func detach(_ observer: AXObserver) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    /// AXObserver 回调（**主线程**）：只把扫描甩到串行队列，绝不在主线程做 AX IPC。
    fileprivate func handleWindowCreatedNotification() {
        queue.async { [weak self] in self?.scan(reason: "AXObserver") }
    }

    // MARK: 常量与工具

    /// 通知中心进程（按 bundle id 匹配；可能不在运行 → nil）。
    static func notificationCenterPID() -> pid_t? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == notificationCenterBundleID }
            .map(\.processIdentifier)
    }

    /// 追加一条带时间戳的记录（先确保目录存在；超过上限先轮转一次）。
    /// 写失败只记日志，**不影响观察**（探针是诊断手段，不是功能前提）。
    static func appendLog(_ path: String, _ text: String) {
        let directory = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
            try rotateIfNeeded(path)
            let chunk = text.hasSuffix("\n") ? text : text + "\n"
            guard let data = chunk.data(using: .utf8) else { return }
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: data)
                return
            }
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            logger.warning("探针写入失败（\(path, privacy: .public)）：\(String(describing: error), privacy: .public)")
        }
    }

    /// 单文件上限：超了就把当前文件挪成 `.1`（只留一代），再写新的。
    private static func rotateIfNeeded(_ path: String) throws {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        guard let size = (attributes?[.size] as? NSNumber)?.intValue, size > logSizeLimit else { return }
        let rotated = path + ".1"
        try? FileManager.default.removeItem(atPath: rotated)
        try? FileManager.default.moveItem(atPath: path, toPath: rotated)
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}

/// AXObserver 的 C 回调（**必须**是全局函数：`AXObserverCreate` 只收 C 函数指针）。
private func notificationBannerObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    Unmanaged<NotificationBannerObserver>.fromOpaque(context).takeUnretainedValue()
        .handleWindowCreatedNotification()
}

// MARK: - 去重台账（纯逻辑 + 单测）

/// 通知指纹：`appName + title + body` 归一化（去首尾空白、折叠内部空白、转小写）。
///
/// 归一化是必要的：AX 通道的 App 名来自横幅 `AXDescription` 的解析，DB 通道的 App 名来自
/// `NSWorkspace` 解析 + 库里的 bundle id，两者**同一 App 的大小写/空格可能不同**。
struct NotificationFingerprint: Hashable, Sendable {
    let appName: String
    let title: String
    let body: String

    init(appName: String, title: String, body: String) {
        self.appName = Self.normalized(appName)
        self.title = Self.normalized(title)
        self.body = Self.normalized(body)
    }

    /// 归一化（**纯函数**）：trim → 内部连续空白折成一个空格 → 小写。
    static func normalized(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// 「同一指纹 10 秒内只弹一次浮层」的台账 + AX 真关闭句柄的短期索引。
///
/// 三条规则（**纯逻辑**，时间由调用方注入 → 可单测）：
/// 1. 同一指纹在 `window` 秒内只弹一次（AX 与 DB 两条通道共用同一个窗口）；
/// 2. **AX 优先**：AX 通道先到并弹了浮层，随后（约 5s 后）到达的同指纹 DB 事件在窗口期内
///    不再弹浮层，只进列表——反之 AX 没到（未授权 / 树变了）时 DB 照常弹，通道永远不会死锁；
/// 3. 窗口期内保留 AX 横幅的**真关闭句柄**：列表行的 × 命中同一指纹时一并真关掉系统通知。
struct NotificationBannerLedger {
    /// 去重窗口（秒）。10s ≈ DB 落盘延迟（~5s）的两倍：足够覆盖「AX 先到、DB 后到」，
    /// 又短到不会把用户故意连发的两条同文案通知永久吞掉。
    static let window: TimeInterval = 10

    enum Source: String, Sendable {
        case ax
        case database
    }

    private struct Entry {
        let source: Source
        let presentedAt: Date
        let closeHandle: NotificationBannerCloseHandle?
    }

    private var entries: [NotificationFingerprint: Entry] = [:]

    /// 是否该为本指纹弹浮层（顺手登记；窗口期外先清理）。
    ///
    /// - `source` 只影响登记的来源与句柄（`database` 没有句柄），判定对两条通道一致；
    /// - 返回 false 表示「窗口期内已经弹过」——调用方**只跳过浮层**，列表/未读计数照旧。
    mutating func shouldPresent(
        _ fingerprint: NotificationFingerprint,
        source: Source,
        closeHandle: NotificationBannerCloseHandle? = nil,
        now: Date = Date()
    ) -> Bool {
        prune(now: now)
        if entries[fingerprint] != nil { return false }
        entries[fingerprint] = Entry(source: source, presentedAt: now, closeHandle: closeHandle)
        return true
    }

    /// 窗口期内该指纹的真关闭句柄（`nil` = 没有 AX 横幅 / 已经过期 / 是 DB 来源的那一条）。
    mutating func closeHandle(
        for fingerprint: NotificationFingerprint,
        now: Date = Date()
    ) -> NotificationBannerCloseHandle? {
        prune(now: now)
        return entries[fingerprint]?.closeHandle
    }

    /// 清掉窗口外的登记（台账只保存最近 `window` 秒，不随运行时长增长）。
    mutating func prune(now: Date = Date()) {
        entries = entries.filter { now.timeIntervalSince($0.value.presentedAt) < Self.window }
    }

    /// 当前登记条数（**只给单测**看窗口清理是否生效）。
    var count: Int { entries.count }
}
