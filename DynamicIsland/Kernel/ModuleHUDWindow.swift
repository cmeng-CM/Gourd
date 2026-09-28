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

import AppKit
import Combine
import SwiftUI
import os

/// 内核自己的浮层 hosting view：`NSHostingView` + 两个必要的补丁。
///
/// ① `acceptsFirstMouse`：面板不是 key window 时，**第一次点击**也要落到视图上——浮层上的 ×
///    必须「点一下就生效」（通知到达时 Gourd 通常不是前台应用）。口径同上游
///    `FirstMouseHostingView`（`DynamicIslandApp.swift`，刘海面板的 contentView 也用它）。
/// ② `layout()` 回调：每次 SwiftUI 为内容跑完布局，把 `fittingSize`（内容的理想尺寸）回报宿主，
///    窗口尺寸就靠它自适应（见 D-23 的坑 ②）。
private final class HUDSizingHostingView<Content: View>: NSHostingView<Content> {
    /// 内容理想尺寸变化时的回调（在布局过程中调用，接收方自行安排到下一拍再改窗口）。
    var onContentSizeChange: ((CGSize) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        onContentSizeChange?(fittingSize)
    }
}

/// 浮层窗口宿主：把 `ModuleRegistry.activeHUD` 渲染进一个**独立的自适应窗口**。
///
/// 三条形态约束（对应 2026-09-28 的两条用户反馈）：
/// ① **按内容自适应**：窗口尺寸 = `NSHostingView.fittingSize`（内容布局后重算），不再受
///    刘海 / 菜单栏尺寸裁剪——内置屏「被遮盖、下半截被裁」由此消除；
/// ② **跟随鼠标屏**：水平居中于鼠标所在屏、垂直贴在该屏可用顶边下方 `topGap`——外接屏
///    「太小、看不到」由此消除（不再依赖关闭态那把位置让给谁）；
/// ③ **不与岛内容同层**：窗口是独立的一格（`level = .screenSaver`），既不与关闭态优先级链
///    抢位置，也不再要求 hide-until-hover 豁免（D-22 的旧豁免随之删除）。
@MainActor
public final class ModuleHUDWindowHost {
    public static let shared = ModuleHUDWindowHost()

    /// 窗口顶端距该屏**可用顶边**的固定间隙（pt）。可用顶边 = 屏顶往下的刘海高度（有刘海时）
    /// 或菜单栏高度（无刘海时）——见 `topInset(safeAreaTop:frameMaxY:visibleFrameMaxY:)`。
    static let topGap: CGFloat = 8

    /// 淡入 / 淡出时长（秒）：与关闭态链上原来的 `.opacity` 过渡同量级，肉眼是「轻轻出现 / 消失」。
    static let fadeInDuration: TimeInterval = 0.15
    static let fadeOutDuration: TimeInterval = 0.2

    /// 量不出内容尺寸时的兜底尺寸（pt）：只在 `fittingSize` 给出 0×0 / NaN 时用，
    /// 目的是「窗口别缩成 0×0 导致再也救不回来」，不是正常路径的尺寸。
    static let fallbackContentSize = CGSize(width: 240, height: 48)

    /// 窗口 / 内容的持有者。**复用同一个窗口**：浮层是瞬时条目，反复创建窗口会闪。
    private var panel: NSWindow?
    private var hostingView: HUDSizingHostingView<AnyView>?
    /// 对 `ModuleRegistry.$activeHUD` 的订阅（`start()` 挂一次，幂等）。
    private var subscription: AnyCancellable?
    /// 最近一次量到的**可用**内容尺寸（布局回调写、present 时读）。
    private var contentSize: CGSize?
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

        if !panel.isVisible {
            panel.alphaValue = 0
            // 用 `orderFrontRegardless`（与上游其它 HUD 窗口同口径）：通知到达时 Gourd 通常
            // 不是前台应用，`orderFront` 在非激活应用上不保证把窗口露出来。
            // 先以 alpha 0 上台：窗口上台才会为内容跑布局，我们也才量得到尺寸（见坑 ②）。
            panel.orderFrontRegardless()
        }
        // 已知尺寸（上一条浮层量到的）→ 立刻按它摆好；尺寸没变时窗口不会跳。
        if let contentSize { applyContentSize(contentSize, to: panel) }
        // 逼一次布局：`layout()` 回调随即把**新内容**的理想尺寸回报上来。
        hostingView?.needsLayout = true
        hostingView?.layoutSubtreeIfNeeded()

        // 内容已就绪（尺寸可用）→ 立刻淡入；否则等布局回调把它淡入（见 `contentSizeChanged`）。
        // 两条路都是幂等的：alpha 已是 1 时再动画一次没有视觉差别。
        if contentSize != nil { fadeIn(panel) }

        // 几何日志：窗口要等布局回调（还有它之后的尺寸应用）才会摆好，所以延后一拍再记真值——
        // 核对窗口落点看这一行（`screencapture` 的窗口几何也可用 CGWindowList 交叉验证）。
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard let self, self.generation == generation, let panel = self.panel, panel.isVisible else { return }
            if let size = self.contentSize {
                self.log.info("""
                浮层窗口显示：模块 \(hud.moduleID, privacy: .public)，\
                尺寸 \(NSStringFromSize(size), privacy: .public)，\
                frame \(NSStringFromRect(panel.frame), privacy: .public)
                """)
            } else {
                self.log.warning("浮层窗口：模块 \(hud.moduleID, privacy: .public) 未量到可用内容尺寸，窗口未出示内容")
            }
        }
    }

    /// 收起：淡出 `fadeOutDuration` 后 `orderOut`（窗口留着复用）。
    ///
    /// **不维护 ttl**：`activeHUD` 变 nil 才会走到这里（到期任务 / 模块主动撤 / `deactivateAll()`）。
    private func dismiss() {
        guard let panel, panel.isVisible else { return }
        let generation = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOutDuration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation, ModuleRegistry.shared.activeHUD == nil else { return }
                panel.orderOut(nil)
                // 下次上台要重新淡入：归零，别让 `present` 以为「已可见且已淡入」。
                panel.alphaValue = 0
                self.log.info("浮层窗口已收起（ttl 到期 / 被撤）")
            }
        }
    }

    /// 内容尺寸变化（`HUDSizingHostingView.layout()` 回调）→ 改窗口尺寸 + 重新贴顶 + （首次）淡入。
    ///
    /// 回调发生在**布局过程中**，所以把动作挪到下一拍：在布局里改窗口尺寸会与这一次布局打架。
    /// 尺寸没变就直接返回——`layout()` 每次布局都会回调，不设这道闸会变成「布局 → 改尺寸 →
    /// 再布局」的死循环。
    private func contentSizeChanged(_ size: CGSize) {
        let sanitized = Self.sanitizedContentSize(size, fallback: contentSize ?? Self.fallbackContentSize)
        guard sanitized != contentSize else { return }
        contentSize = sanitized
        Task { @MainActor [weak self] in
            guard let self, let panel = self.panel else { return }
            self.applyContentSize(sanitized, to: panel)
            if ModuleRegistry.shared.activeHUD != nil { self.fadeIn(panel) }
        }
    }

    /// 按内容尺寸摆窗口：先定尺寸（左上角不动），再按新尺寸贴顶居中。
    private func applyContentSize(_ size: CGSize, to panel: NSWindow) {
        if panel.contentLayoutRect.size != size { panel.setContentSize(size) }
        position(panel)
    }

    private func fadeIn(_ panel: NSWindow) {
        guard panel.alphaValue < 1 else { return }
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
        let hosting = HUDSizingHostingView(
            rootView: AnyView(ModuleHUDView().environment(\.colorScheme, .dark))
        )
        hosting.onContentSizeChange = { [weak self] size in
            self?.contentSizeChanged(size)
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

    /// 尺寸消毒：`fittingSize` 还没量出来时（首帧 / 内容为空）给一个兜底，避免把窗口设成 0×0
    /// 或者 NaN（那会让窗口消失且后续 setContentSize 也救不回来）。
    static func sanitizedContentSize(_ fittingSize: CGSize, fallback: CGSize) -> CGSize {
        let usable = fittingSize.width.isFinite && fittingSize.height.isFinite
            && fittingSize.width > 1 && fittingSize.height > 1
        guard usable else {
            let fallbackUsable = fallback.width.isFinite && fallback.height.isFinite
                && fallback.width > 1 && fallback.height > 1
            return fallbackUsable ? fallback : fallbackContentSize
        }
        return fittingSize
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
    /// 注意是**按顶对齐**而不是按中心对齐：浮层的高度随内容变（一条 / 两行），若按中心对齐，
    /// 内容变高时会同时向下长——贴顶才是「挂在菜单栏下方」的观感。
    static func origin(windowSize: CGSize, screenFrame: CGRect, topInset: CGFloat, topGap: CGFloat) -> CGPoint {
        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.maxY - topInset - topGap - windowSize.height
        return CGPoint(x: x.rounded(), y: y.rounded())
    }
}
