//
//  ModuleHUDView.swift
//  Gourd 模块内核 · 折叠态瞬时浮层宿主（P2d / D-22）
//
//  接缝：`ContentView.swift` 关闭态优先级链里插入的**中优先**分支（判据是
//  `ModuleRegistry.activeHUD != nil`，即「模块刚请求过一条浮层」）时才走到这里。
//
//  与 `ModuleCompactSlotView` 的分工：那个是**常驻**内容（模块答什么显示什么，槽位共享
//  优先级链的低位）；本视图是**瞬时**条目（`presentHUD` 造、到期由注册表清），
//  插入位置更靠前——通知要盖过音乐 / 计时器等常态 live activity。
//
//  职责边界：只做「取当前浮层 + 渲染」——不持有计时器（到期在注册表）、不做尺寸协商。
//

import SwiftUI
import os

/// 把 `ModuleRegistry.activeHUD` 的视图渲染进关闭态刘海。
///
/// 观察注册表是**必需**的（同 `ModuleHostView` / `ModuleCompactSlotView`）：
/// `presentHUD` / `clearHUD` 只改注册表的 `@Published activeHUD`，不观察就不会重绘。
struct ModuleHUDView: View {
    @ObservedObject private var registry = ModuleRegistry.shared

    private static let log = os.Logger(subsystem: "com.cmeng.gourd.kernel", category: "hud")

    var body: some View {
        if let hud = registry.activeHUD {
            let _ = Self.noteRender(hud)
            hud.view
        }
    }

    /// 渲染点日志（`.debug`，不进默认日志流）：`presentHUD` 的日志只证明「模块请求了浮层」，
    /// 而浮层是否真的走到关闭态这条链上还要看宿主视图有没有重算——这一行让实测能分辨两者
    ///（关闭态链的判据读的是注册表，宿主不观察它时判据不会被重算，见 D-22 的取舍）。
    private static func noteRender(_ hud: ModuleHUD) {
        log.debug("HUD 渲染：模块 \(hud.moduleID, privacy: .public)，到期 \(hud.expiresAt, privacy: .public)")
    }
}
