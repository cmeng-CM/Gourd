//
//  ModuleHUDView.swift
//  Gourd 模块内核 · 折叠态瞬时浮层的渲染根视图（P2d / D-22 → D-23）
//
//  接缝：**不再**插在 `ContentView.swift` 的关闭态优先级链里（那是 D-22 的旧落点，
//  关闭态面板的尺寸只有折叠态刘海那么大，浮层会被裁掉 / 缩得看不见）。
//  本视图现在是 `ModuleHUDWindow.swift` 那个独立窗口的 contentView 根视图。
//
//  与 `ModuleCompactSlotView` 的分工：那个是**常驻**内容（模块答什么显示什么，槽位共享
//  优先级链的低位）；本视图是**瞬时**条目（`presentHUD` 造、到期由注册表清），
//  渲染在一个独立窗口里——既不与岛内容抢位置，也不再受刘海 / 菜单栏尺寸裁剪。
//
//  职责边界：只做「取当前浮层 + 渲染」——不持有计时器（到期在注册表）、不做尺寸协商
//  （窗口按 `fittingSize` 自适应，见 `ModuleHUDWindowHost.resizeToFit`）。
//

import SwiftUI
import os

/// 把 `ModuleRegistry.activeHUD` 的视图渲染进浮层窗口。
///
/// 观察注册表是**必需**的（同 `ModuleHostView` / `ModuleCompactSlotView`）：
/// `presentHUD` / `clearHUD` 只改注册表的 `@Published activeHUD`，不观察就不会重绘
/// （浮层窗口是按内容定尺寸的：内容不重绘，窗口也就量不到新尺寸）。
struct ModuleHUDView: View {
    @ObservedObject private var registry = ModuleRegistry.shared

    private static let log = os.Logger(subsystem: "com.cmeng.gourd.kernel", category: "hud")

    var body: some View {
        if let hud = registry.activeHUD {
            let _ = Self.noteRender(hud)
            // `.fixedSize()`：浮层按**自身理想尺寸**呈现，不接受窗口给的尺寸建议。
            // 窗口尺寸正是由 `fittingSize` 反推的（`ModuleHUDWindowHost`），而 `fittingSize`
            // 只有在内容不受当前窗口尺寸牵制时才稳定——否则会「窗口多大、内容就报多大」，
            // 尺寸再也改不动（实测坑，见 `ModuleHUDWindow.swift` 文件头）。
            hud.view.fixedSize()
        }
    }

    /// 渲染点日志（`.debug`，不进默认日志流）：`presentHUD` 的日志只证明「模块请求了浮层」，
    /// 而浮层是否真的渲染出来还要看宿主视图有没有重算——这一行让实测能分辨两者
    ///（窗口宿主订阅的是同一个 `@Published`，`ModuleHUDWindow` 的 `.info` 那行给出窗口几何）。
    private static func noteRender(_ hud: ModuleHUD) {
        log.debug("HUD 渲染：模块 \(hud.moduleID, privacy: .public)，到期 \(hud.expiresAt, privacy: .public)")
    }
}
