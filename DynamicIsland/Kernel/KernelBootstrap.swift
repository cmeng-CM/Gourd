//
//  KernelBootstrap.swift
//  Gourd 模块内核 · 组合根（P1 批次 / T2）
//
//  应用启动时唯一的模块接线点：T3 的 S6 在 `DynamicIslandApp.applicationDidFinishLaunching`
//  里以 `Task { await KernelBootstrap.bootstrap() }` 调用它（与上游既有的
//  `SomeManager.shared.setup(coordinator:)` 一族同构）。
//
//  P1 验收：**新增一个模块 = 实现 `GourdModule` + 往 `builtinModules` 加一行**（A3）；
//  注释掉任意一行后应用仍能启动（A4）——`register` 是逐项独立的，注册表空时
//  `tabEntries` 为空、展开面板与改动前一致。
//

import Defaults
import Foundation
import os

/// 组合根。模块的注册、启用门、激活与首启默认值都收在这一处。
@MainActor
public enum KernelBootstrap {
    /// 内置模块清单。T4 落 `ProgressModule`，T5 落 `TodosModule`，P2c 落 `NotificationsModule`——
    /// 即「新增模块 = 加一行」的那一行。
    static let builtinModules: [any GourdModule.Type] = [
        ProgressModule.self, TodosModule.self, NotificationsModule.self,
    ]

    private static let log = os.Logger(subsystem: "com.cmeng.gourd.kernel", category: "bootstrap")

    /// 注册内置模块 + 落首启默认值 + 激活。幂等，可在启动流程里安全重复调用。
    public static func bootstrap() async {
        // 首启默认值先落：模块 `activate()` 里读宿主设置时看到的已是最终值。
        applyFirstLaunchDefaults()

        let registry = ModuleRegistry.shared
        // 启用门逐字取 `defaultEnabled`（缺省 false，06 §2.2）。下一行的数组就是「新增模块 = 加一行」。
        registry.register(builtinModules, enabled: { registry.manifests[$0]?.defaultEnabled ?? false })
        await registry.bootstrap()
    }

    /// 首启默认值：把不需要的上游功能用**默认值**表达，不改上游源码（09 §8.1 / D-08）。
    ///
    /// 本批只有一条：`enableScreenAssistant = false`（上游默认 `true`，入口隐蔽——⌘⇧A 悬浮面板，
    /// 不在刘海 tab 里）。**一次性、幂等**：以 `Defaults.Keys.gourdFirstLaunchDefaultsApplied`
    /// 为闸门（接缝 S7），用户之后手动改回 `true` 不会被再覆盖。
    ///
    /// 已知限制（docs/13「已知限制」10）：引导流程选 developer 档时 `ProfileSelectionView`
    /// 会把该项写回 `true`，本批不动引导，口径留给 P1-3 的 ConfigStore。
    static func applyFirstLaunchDefaults() {
        // 闸门键在 `Constants.swift` 的 `Defaults.Keys`（S7）：读写都走同一份定义，无第二处字面量。
        guard !Defaults[.gourdFirstLaunchDefaultsApplied] else { return }

        Defaults[.enableScreenAssistant] = false
        Defaults[.gourdFirstLaunchDefaultsApplied] = true
        log.info("已落首启默认值：enableScreenAssistant = false，闸门 \(Defaults.Keys.gourdFirstLaunchDefaultsApplied.name, privacy: .public) = true")
    }
}
