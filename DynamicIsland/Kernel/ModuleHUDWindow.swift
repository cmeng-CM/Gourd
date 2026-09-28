//
//  ModuleHUDWindow.swift
//  Gourd 模块内核 · 瞬时浮层的**独立窗口宿主**（P2d / D-23）
//
//  为什么从关闭态链里搬出来（D-22 的旧落点）：关闭态面板窗口的尺寸 = 折叠态刘海尺寸
//  （内置屏约 32pt 高、外接屏一个小组件），浮层渲染进去必然被**裁剪**（内置屏两行字被压在
//  菜单栏 / 刘海下方、下半截被裁）或**过小**（外接屏）；上游的瞬时提示（sneak peek）靠临时
//  撑大面板窗口腾地方，内核没有这条路径。06 §3.3 R1「模块不得自己创建窗口」→ 窗口归**内核**
//  所有：本文件是浮层窗口的唯一落点，模块只交视图（`UIHandle.presentTransient`），
//  创建 / 定位 / 尺寸 / 显隐都在这里。
//
//  与注册表的分工：ttl 与到期清除仍归 `ModuleRegistry`（本文件**不维护计时器**——只在
//  `activeHUD` 变 nil 时收起），宿主只负责「有浮层 → 显示、没有 → 淡出」。
//
//  ## 两条踩过的坑（都写进代码注释，别再踩）
//  ① **`@Published` 在 `willSet` 里发值**：订阅回调拿到的入参是「将要生效」的值，此刻
//     `ModuleRegistry.shared.activeHUD` 仍是**旧值**（首条浮层时是 nil）。因此 `start()` 的回调
//     不直接消费入参，统一挪到下一拍主线程读注册表真值——否则第一条浮层会渲染成空视图。
//  ② **`fittingSize` 只在 SwiftUI 为内容跑过布局之后才有意义**：在订阅回调里同步量，量到的
//     是**上一条**内容甚至 0×0（实测：首条浮层窗口尺寸量成兜底值、卡片完全不显示）。
//     现在的量尺寸时机是 `HUDSizingHostingView.layout()`（每次内容布局完回调）。
//
//  ## 显隐是状态机（2026-09-28 修「内置屏偶发只显示第一条」）
//  用户反馈是**间歇性**的（同一台机器上时好时坏），所以修法定在**根因**而不是打补丁：
//  显隐集中在 `HUDVisibilityStateMachine` 的纯函数里（动作只由当前状态决定），三处入口
//  （`present` / 内容布局回调 / 淡出完成）只负责「取动作 → 按序执行」。两个坏状态因此消失：
//  ① 淡出被新浮层接手后窗口停在 `alpha == 0`（下次 present 又跳过上台）；② 尺寸没变时
//  尺寸回调早退、窗口已被收起却没人再露出它。**没有定时器 / 重试**（约束）。
//

import AppKit
import Combine
import Defaults
import SwiftUI
import os

/// 内核自己的浮层 hosting view：`NSHostingView` + 两个必要的补丁。
///
/// ① `acceptsFirstMouse`：面板不是 key window 时，**第一次点击**也要落到视图上——浮层上的 ×
///    必须「点一下就生效」（通知到达时 Gourd 通常不是前台应用）。口径同上游
///    `FirstMouseHostingView`（`DynamicIslandApp.swift`，刘海面板的 contentView 也用它）。
/// ② `layout()` 回调：每次 SwiftUI 为内容跑完布局通知宿主，宿主借此做**幂等收尾**
///    （按固定尺寸校正窗口 + 显隐纠正 + 重新贴顶，见 `ModuleHUDWindowHost.contentDidLayout`）。
///    **尺寸不再取自 `fittingSize`**（2026-09-28 起窗口是固定尺寸，见 `contentSize(scale:)`）。
private final class HUDHostingView<Content: View>: NSHostingView<Content> {
    /// 内容跑完一次布局时的回调（在布局过程中调用，接收方自行安排到下一拍再动窗口）。
    var onContentLayout: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        onContentLayout?()
    }
}

/// 可见性状态机的**动作词汇**（`present` / 内容布局回调 / 淡出完成三处共用同一套）。
///
/// 数组顺序 = 执行顺序（`ModuleHUDWindowHost.apply(_:to:)` 按序执行）。
enum HUDVisibilityAction: Equatable {
    /// `orderFrontRegardless`：窗口上台（非前台应用上 `orderFront` 不保证露出来）。
    case orderFront
    /// 直接给 alpha 终态（不走动画；用于「上台前归零」与「把停在 0 / 半透明的补到 1」）。
    case setAlpha(CGFloat)
    /// 把 alpha 动画补到 1（淡入观感）。
    case fadeIn
    /// `orderOut`：真正下台（窗口留着复用）。
    case orderOut
    /// 重新贴顶居中（换屏、尺寸变化后都要）。
    case reposition

    /// 这条动作会把窗口**收起来**吗（只有一种）——淡出完成处据此决定要不要记「已收起」。
    var hidesWindow: Bool { self == .orderOut }
}

/// 浮层窗口可见性状态机的**纯函数内核**（单测直接钉；宿主只负责按序执行动作）。
///
/// **为什么要有它**（2026-09-28 用户反馈「主屏第一条显示、后面不显示」，且是**间歇性**的）：
/// 窗口的显隐此前散在 `present` / `dismiss` 完成回调 / 尺寸回调三处，每处只看自己关心的一两个
/// 条件，于是留下两个能停住的坏状态——
/// ① **淡出期间新浮层接手**：完成回调因「已不是当前代数 / 有 activeHUD」提前 return，
///    窗口 `isVisible == true` 但 alpha 停在 0；下一次 `present` 又因 `isVisible == true`
///    跳过 `orderFrontRegardless`，只靠 `fadeIn` 的 `guard alphaValue < 1` 恢复——
///    窗口层序异常时就表现为「看不到」；
/// ② **尺寸没变**：`contentSizeChanged` 直接 return，窗口若已被收起，没有任何路径把它重新露出。
///
/// **幂等的定义**：动作**只由「进入时的窗口状态」决定**（不看历史、不看过渡中间态），
/// 同一份状态永远给出同一份动作，执行完落在「有浮层 → 在台上 + alpha = 1 + 贴顶居中；
/// 无浮层 → 已下台」这个终态上。因此坏状态一旦被下一个事件观测到就被纠正，
/// **不需要定时器 / 重试兜底**（约束：这条路不准用）。
enum HUDVisibilityStateMachine {
    /// `present`（含「同尺寸重弹」）与内容布局回调要执行的动作。
    ///
    /// 三条不变量：
    /// ① 窗口不在台上 → `setAlpha(0)` + 上台 + 淡入（先归零是为了淡入看得见）；
    /// ② 窗口在台上但 alpha < 1（**淡出被打断后停在 0 / 半透明**，即坏状态 ①）→
    ///    `setAlpha(1)` **直接给终态**，不赌动画——`fadeIn` 不再是唯一恢复路径；
    /// ③ 每次 present 都重新贴顶居中（换屏 / 鼠标移动后仍然对）。
    static func presentActions(isVisible: Bool, alpha: CGFloat) -> [HUDVisibilityAction] {
        var actions: [HUDVisibilityAction] = []
        if !isVisible {
            actions.append(.setAlpha(0))
            actions.append(.reposition)   // 先摆位再上台：不会在旧位置闪一帧
            actions.append(.orderFront)
            actions.append(.fadeIn)
        } else if alpha < 1 {
            actions.append(.setAlpha(1))
            actions.append(.reposition)
        } else {
            // 已在台上且已不透明：唯一还需要的是「位置可能变了」（例如鼠标换到另一块屏）
            actions.append(.reposition)
        }
        return actions
    }

    /// 淡出完成时（`dismiss` 的完成回调）要执行的动作。
    ///
    /// - **代数不匹配**（`generationMatches == false`）：这期间有更新的浮层 `present` 过，
    ///   它自己会保证可见 → 什么都不做；尤其**不能** `orderOut`（会把新浮层一起藏掉）；
    /// - **有 activeHUD**（新浮层在台前）：不 `orderOut`、**也不把 alpha 留在 0**——
    ///   撤销这次淡出（恢复到不透明 + 重新贴顶居中），这正是坏状态 ① 的修复；
    /// - 否则：真正下台（`orderOut` + 归零，下次上台重新淡入）。
    static func dismissCompletionActions(generationMatches: Bool, hasActiveHUD: Bool) -> [HUDVisibilityAction] {
        guard generationMatches else { return [] }
        if hasActiveHUD { return [.setAlpha(1), .reposition] }
        return [.orderOut, .setAlpha(0)]
    }
}

/// 浮层窗口宿主：把 `ModuleRegistry.activeHUD` 渲染进一个**独立的固定尺寸窗口**。
///
/// 四条形态约束（对应 2026-09-28 的三条用户反馈）：
/// ① **固定尺寸**（用户反馈「尺寸不固定，要固定个初始大小」）：窗口内容尺寸 = `contentSize(scale:)`
///    = 320 × 64 再乘用户倍率（`notificationHUDScale`，默认 1.3），**不随内容变化**——
///    先后两条通知内容长短不同也不再宽窄跳动；超长内容在卡片内截断（分工见下方 ④）；
/// ② **跟随鼠标屏**：水平居中于鼠标所在屏、垂直贴在该屏可用顶边下方 `topGap`——外接屏
///    「太小、看不到」由此消除（不再依赖关闭态那把位置让给谁）；
/// ③ **不与岛内容同层**：窗口是独立的一格（`level = .screenSaver`），既不与关闭态优先级链
///    抢位置，也不再要求 hide-until-hover 豁免（D-22 的旧豁免随之删除）；
/// ④ **超长内容的分工**：浮层只显示「最新的一条」，两行内截断（`NotificationHUDView` 的
///    `lineLimit` + `truncationMode`）；**完整正文的位置是展开面板的通知列表**——
///    浮层是"刚发生了什么"的瞬时提示，不是阅读入口（一次多条新通知只在第二行末尾追加
///    「等 N 条」的计数，同样不展开）。
///
/// **显隐是状态机**（2026-09-28 修「内置屏偶发只显示第一条」）：三处入口
/// （`present` / 内容布局回调 / 淡出完成）都只做一件事——把当前状态喂给
/// `HUDVisibilityStateMachine` 拿到动作、按序执行（`apply(_:to:)`）。
/// 三条不变量：窗口的显隐**只由「有没有浮层」决定**，不由历史路径决定；
/// 每次 present 都重新贴顶居中；**没有定时器 / 重试兜底**（约束）。
@MainActor
public final class ModuleHUDWindowHost {
    public static let shared = ModuleHUDWindowHost()

    /// 窗口顶端距该屏**可用顶边**的固定间隙（pt）。可用顶边 = 屏顶往下的刘海高度（有刘海时）
    /// 或菜单栏高度（无刘海时）——见 `topInset(safeAreaTop:frameMaxY:visibleFrameMaxY:)`。
    static let topGap: CGFloat = 8

    /// 淡入 / 淡出时长（秒）：与关闭态链上原来的 `.opacity` 过渡同量级，肉眼是「轻轻出现 / 消失」。
    static let fadeInDuration: TimeInterval = 0.15
    static let fadeOutDuration: TimeInterval = 0.2

    /// 浮层卡片的**固定尺寸基准**（pt，倍率 1.0 时）：宽 320 / 高 64。
    ///
    /// **为什么固定**（2026-09-28 用户反馈「尺寸不固定」）：内容是「App 名 + 标题 · 正文」两行，
    /// 长短不一时按内容自适应的窗口会宽窄跳动；固定后观感是「同一张卡片换字」，
    /// 超长内容在卡片内截断（完整正文看展开面板列表，见类型文档 ④）。
    ///
    /// `nonisolated`：尺寸口径是**跨 actor 的纯数据**——模块侧的卡片（`NotificationHUDCardLayout`）
    /// 在视图构造期读它，不能要求先跳主 actor。
    nonisolated static let cardBaseSize = CGSize(width: 320, height: 64)

    /// 倍率的可用区间（与设置滑块的 0.8…2.0 同源）。**单一来源在这里**：窗口尺寸是内核定的，
    /// 模块侧的 `NotificationHUDCardLayout.scaleRange` 是本值的别名（避免两处各写一份漂移）。
    nonisolated static let hudScaleRange: ClosedRange<Double> = 0.8...2.0

    /// **纯函数**：浮层窗口 / 卡片的内容尺寸 = 基准尺寸 × 夹取后的倍率。
    ///
    /// - 倍率**夹取**到 `hudScaleRange`：用户直接改 UserDefaults 写了个离谱值时也有确定尺寸
    ///   （同 `ttl` 的夹取口径），不会把窗口设成 0 宽或整屏宽；
    /// - 保留两位小数：避开 `320 × 1.3 = 416.00000000000006` 这类浮点尾巴，
    ///   单测的等值断言与日志里的尺寸比较才有意义。
    nonisolated static func contentSize(scale: Double) -> CGSize {
        let s = CGFloat(min(max(scale, hudScaleRange.lowerBound), hudScaleRange.upperBound))
        return CGSize(width: round2(cardBaseSize.width * s), height: round2(cardBaseSize.height * s))
    }

    /// 保留两位小数（口径同上）。
    nonisolated private static func round2(_ value: CGFloat) -> CGFloat {
        (value * 100).rounded() / 100
    }

    /// 窗口 / 内容的持有者。**复用同一个窗口**：浮层是瞬时条目，反复创建窗口会闪。
    private var panel: NSWindow?
    private var hostingView: HUDHostingView<AnyView>?
    /// 对 `ModuleRegistry.$activeHUD` 的订阅（`start()` 挂一次，幂等）。
    private var subscription: AnyCancellable?
    /// 显示代数：淡出完成后据此判断「这期间有没有新浮层接手」——有则不做 `orderOut`
    ///（否则「A 淡出中、B 到达」会让 A 的收尾把 B 一起藏掉）。
    private var generation = 0
    private let log = os.Logger(subsystem: "com.cmeng.gourd.kernel", category: "hud-window")

    private init() {}

    // MARK: - 接线

    /// 挂上对注册表的订阅（**幂等**）。应用启动时调用一次
    /// （`DynamicIslandApp.applicationDidFinishLaunching`，与既有的 `Manager...shared.setup(...)` 一族同处）。
    ///
    /// 订阅的是 `@Published activeHUD`：有浮层 → 显示；被撤 / ttl 到期（注册表清）→ 淡出收起。
    /// 回调里**不消费入参**（`@Published` 的 willSet 时序，见文件头坑 ①）：统一挪到下一拍读真值。
    public func start() {
        guard subscription == nil else { return }
        subscription = ModuleRegistry.shared.$activeHUD.sink { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let hud = ModuleRegistry.shared.activeHUD {
                    self.present(hud)
                } else {
                    self.dismiss()
                }
            }
        }
        log.info("浮层窗口宿主已挂上（订阅 ModuleRegistry.activeHUD）")
    }

    // MARK: - 显示 / 收起

    private func present(_ hud: ModuleHUD) {
        generation += 1
        guard let panel = ensurePanel() else { return }

        // ① 尺寸：**固定尺寸**（320 × 64 × 倍率）先摆好——先后两条通知的内容长短不同也不跳。
        applyContentSize(to: panel)
        // ② 显隐：**每次 present 都按当前状态重算一遍动作**（幂等），不是「只有不可见时才处理」。
        //    这一步保证「present 返回后窗口一定在台上且不透明」——坏状态在这里被纠正，
        //    不依赖 `fadeIn` 的前置判断，也不依赖上一次 present 做过什么。
        apply(
            HUDVisibilityStateMachine.presentActions(isVisible: panel.isVisible, alpha: panel.alphaValue),
            to: panel
        )
        // ③ 逼一次布局：让**新内容**立刻排进固定尺寸的窗口（布局回调还会再做一次幂等收尾）。
        hostingView?.needsLayout = true
        hostingView?.layoutSubtreeIfNeeded()

        // 几何日志：窗口要等布局回调（还有它之后的尺寸应用）才会摆好，所以延后一拍再记真值——
        // 核对窗口落点看这一行（`screencapture` 的窗口几何也可用 CGWindowList 交叉验证）。
        // **记的是窗口的实际内容尺寸与 alpha**（不是算出来的常量）：这条日志是「同一屏连发多条
        // 通知，尺寸 / 可见性是否一致」的实测证据，因此必须是真实读回来的值。
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard let self, self.generation == generation, let panel = self.panel, panel.isVisible else { return }
            self.log.info("""
            浮层窗口显示：模块 \(hud.moduleID, privacy: .public)，\
            尺寸 \(NSStringFromSize(panel.contentLayoutRect.size), privacy: .public)，\
            alpha \(panel.alphaValue, privacy: .public)，\
            frame \(NSStringFromRect(panel.frame), privacy: .public)
            """)
        }
    }

    /// 收起：淡出 `fadeOutDuration` 后 `orderOut`（窗口留着复用）。
    ///
    /// **不维护 ttl**：`activeHUD` 变 nil 才会走到这里（到期任务 / 模块主动撤 / `deactivateAll()`）。
    /// 完成回调不做判断，只把「代数 / 有没有新浮层」交给状态机（见 `dismissCompletionActions`）：
    /// 新浮层接手时不 `orderOut`、也不把 alpha 留在 0。
    private func dismiss() {
        guard let panel, panel.isVisible else { return }
        let generation = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOutDuration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, let panel = self.panel else { return }
                let actions = HUDVisibilityStateMachine.dismissCompletionActions(
                    generationMatches: self.generation == generation,
                    hasActiveHUD: ModuleRegistry.shared.activeHUD != nil
                )
                self.apply(actions, to: panel)
                if actions.contains(where: \.hidesWindow) {
                    self.log.info("浮层窗口已收起（ttl 到期 / 被撤）")
                } else if actions.isEmpty {
                    self.log.debug("淡出完成：已有更新的浮层接手 / 更新的一次淡出在途，不做处理")
                } else {
                    self.log.info("淡出被接手：新浮层在台前，窗口不收起并恢复不透明")
                }
            }
        }
    }

    /// 内容布局回调（`HUDHostingView.layout()`）→ 幂等收尾：**按固定尺寸校正窗口** + 显隐纠正 +
    /// 重新贴顶。
    ///
    /// 回调发生在**布局过程中**，所以把动作挪到下一拍：在布局里改窗口尺寸会与这一次布局打架。
    /// 尺寸已是固定常量，这里主要是「窗口若被系统或别处改动过就拉回来」的兜底；
    /// **显隐纠正照走**：窗口被收起 / alpha 停在 0 这类坏状态也靠这里被观测到并纠正。
    private func contentDidLayout() {
        Task { @MainActor [weak self] in
            guard let self, let panel = self.panel else { return }
            self.applyContentSize(to: panel)
            guard ModuleRegistry.shared.activeHUD != nil else { return }
            self.apply(
                HUDVisibilityStateMachine.presentActions(isVisible: panel.isVisible, alpha: panel.alphaValue),
                to: panel
            )
        }
    }

    /// 按**固定尺寸**摆窗口（窗口尺寸的唯一来源：`contentSize(scale:)` 读当前倍率算出）。
    ///
    /// `panel.contentLayoutRect.size != size` 的闸门是必需的：`layout()` 回调 → 改尺寸 →
    /// 再布局 → 再回调，没有它就成了死循环。**只改尺寸，不摆位置**：位置由 `.reposition`
    /// 动作统一负责，两条路径因此不会各摆一半。
    private func applyContentSize(to panel: NSWindow) {
        let size = Self.contentSize(scale: Defaults[.notificationHUDScale])
        if panel.contentLayoutRect.size != size { panel.setContentSize(size) }
    }

    /// 执行状态机给出的动作（**唯一执行落点**：三处入口共用，避免每个入口各写一半）。
    private func apply(_ actions: [HUDVisibilityAction], to panel: NSWindow) {
        for action in actions {
            switch action {
            case .orderFront:
                // 用 `orderFrontRegardless`（与上游其它 HUD 窗口同口径）：通知到达时 Gourd 通常
                // 不是前台应用，`orderFront` 在非激活应用上不保证把窗口露出来。
                panel.orderFrontRegardless()
            case .setAlpha(let alpha):
                panel.alphaValue = alpha
            case .fadeIn:
                fadeIn(panel)
            case .orderOut:
                panel.orderOut(nil)
            case .reposition:
                position(panel)
            }
        }
    }

    /// 淡入：把 alpha 动画补到 1。**没有「已经是 1 就跳过」的前置判断**——这条函数的目标是
    /// 「结束时不透明」：从 1 动到 1 没有视觉差别（幂等），从 0 动到 1 才是淡入观感。
    private func fadeIn(_ panel: NSWindow) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeInDuration
            panel.animator().alphaValue = 1
        }
    }

    // MARK: - 窗口与内容

    /// 惰性创建唯一窗口。形态与上游 HUD 窗口一族同档（`CircularHUDWindowManager` / `ClipboardWindowManager`）。
    private func ensurePanel() -> NSWindow? {
        if let panel { return panel }

        // 内容 = 内核的浮层根视图（它自己观察注册表 → 浮层更替时重渲）。
        let hosting = HUDHostingView(
            rootView: AnyView(ModuleHUDView().environment(\.colorScheme, .dark))
        )
        hosting.onContentLayout = { [weak self] in
            self?.contentDidLayout()
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true   // 点浮层不抢键盘焦点（浮层里没有输入控件）
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true                // 独立窗口靠投影从桌面 / 壁纸上「托起」卡片
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver            // 与上游其它 HUD 窗口同档
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = false
        panel.contentView = hosting

        self.panel = panel
        self.hostingView = hosting
        return panel
    }

    // MARK: - 放置（几何是纯函数：单测直接钉，`NSScreen` 只用来喂入参）

    /// 把窗口放到**鼠标所在屏**（用户预期：浮层出现在正在操作的那块屏）。
    private func position(_ panel: NSWindow) {
        guard let screen = Self.targetScreen() else { return }
        let origin = Self.origin(
            windowSize: panel.frame.size,
            screenFrame: screen.frame,
            topInset: Self.topInset(
                safeAreaTop: screen.safeAreaInsets.top,
                frameMaxY: screen.frame.maxY,
                visibleFrameMaxY: screen.visibleFrame.maxY
            ),
            topGap: Self.topGap
        )
        panel.setFrameOrigin(origin)
    }

    /// 放置目标屏：鼠标所在屏 → `NSScreen.main`（鼠标不在任何屏上时，例如刚唤醒）。
    static func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// 该屏顶部要避开的**内边**高度（pt）：
    /// - 有刘海（`safeAreaInsets.top > 0`）→ 刘海高度（内置屏实测 32pt）：不避开就会压在刘海底下，
    ///   正是 2026-09-28 用户截图里「浮层被遮盖」的形态；
    /// - 没有刘海 → 菜单栏高度（屏顶与 `visibleFrame` 顶之差，外接屏实测 0～25pt）：不避开会被
    ///   菜单栏盖住上半行。
    static func topInset(safeAreaTop: CGFloat, frameMaxY: CGFloat, visibleFrameMaxY: CGFloat) -> CGFloat {
        if safeAreaTop > 0 { return safeAreaTop }
        return max(frameMaxY - visibleFrameMaxY, 0)
    }

    /// 窗口原点（AppKit 坐标，左下角）：**水平居中于该屏** + **顶端贴在该屏可用顶边下方 `topGap`**。
    ///
    /// 注意是**按顶对齐**而不是按中心对齐：浮层尺寸虽已固定，贴顶仍是「挂在菜单栏下方」的观感
    /// （改倍率时卡片向下长，而不是上下各长一半）。
    static func origin(windowSize: CGSize, screenFrame: CGRect, topInset: CGFloat, topGap: CGFloat) -> CGPoint {
        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.maxY - topInset - topGap - windowSize.height
        return CGPoint(x: x.rounded(), y: y.rounded())
    }
}
