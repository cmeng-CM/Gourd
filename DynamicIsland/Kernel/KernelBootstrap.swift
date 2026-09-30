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
//  P2 接管批次 / T1 增量（docs/20-component-page.md §做法 机制一/机制二 + §接口与数据形状 2）：
//  启用门改成**三段判定**（接管键 → overrides → manifest 默认），并新增
//  `startTakeoverBridge(registry:)`——为每个接管模块订阅它那一个上游键，
//  键被别处（上游设置页）改动时把注册表状态拉回来。
//
//  P2 接管批次 / T2：`builtinModules` 加 `TimerModule`（第一个真接管模块）——上游那条
//  计时器 tab 分支与其 `+1` 计数同批删除，tab 由模块投影产出（docs/20 §做法 机制一）。
//
//  P2 接管批次 / T4：`builtinModules` 加 `MirrorModule`（第二个真接管模块）——上游首页 strip 里
//  那条写死的镜子块分支（判据 + 分支 + 块宽 + `@Default(.showMirror)`）同批删除，首页块由模块
//  投影 + `content(for: .home)` 产出，块宽由 `homeBlockWidth` 钩子继承（docs/20 §做法 机制一）。
//
//  P3 冻结批次 / T6：`builtinModules` 加 `CalendarModule`——给孤儿视图 `StandaloneCalendarView`
//  接线（展开面板的「日历」tab），启用真源 = 上游那颗总开关 `showCalendar`；上游首页那条全宽
//  日历行**不动**（它仍由 `NotchHomeView` 直接渲染），两处呈现共用一个开关
//  （docs/24-release-freeze.md §做法 机制三）。
//

import Combine
import Defaults
import Foundation
import os

/// 组合根。模块的注册、启用门、激活与首启默认值都收在这一处。
@MainActor
public enum KernelBootstrap {
    /// 内置模块清单。T4 落 `ProgressModule`，T5 落 `TodosModule`，P2c 落 `NotificationsModule`，
    /// P2 启动台批次落 `LauncherModule`，P2 接管批次 / T2 落 `TimerModule`、T4 落 `MirrorModule`、
    /// T5 落 `MusicModule`，P2 快捷指令与前台应用批次 / T2 落 `ShortcutsModule`、T4 落 `FrontAppModule`，
    /// P3 冻结批次 / T6 落 `CalendarModule`——即「新增模块 = 加一行」的那一行。
    ///
    /// 顺序与用户可见顺序**无关**（那个由 `defaultPlacement.order` 定，见 `ModuleRegistry.tabEntries`）；
    /// 它只影响 `register` 的落表顺序与日志可读性，这里按批次先后排。
    static let builtinModules: [any GourdModule.Type] = [
        ProgressModule.self, TodosModule.self, NotificationsModule.self, LauncherModule.self,
        TimerModule.self, MirrorModule.self, MusicModule.self, ShortcutsModule.self,
        FrontAppModule.self, CalendarModule.self,
    ]

    private static let log = os.Logger(subsystem: "com.cmeng.gourd.kernel", category: "bootstrap")

    /// 重同步桥的订阅表：id → 该接管模块那个上游键的订阅（docs/20 §接口与数据形状 2）。
    ///
    /// **是字典、不是 `Set<AnyCancellable>`**：`AnyCancellable.store(in:)` 只有 `Set` 与
    /// `RangeReplaceableCollection<AnyCancellable>` 两个重载，字典两个都不匹配，因此
    /// `startTakeoverBridge` 里是**显式赋值**；按 id 存也让排查时能看出「哪个模块的订阅在不在」。
    private static var takeoverSubscriptions: [String: AnyCancellable] = [:]

    /// 当前订阅条数（只为可测性，docs/20 §接口与数据形状 2）：用例据它断言起桥的幂等。
    static var takeoverSubscriptionCount: Int { takeoverSubscriptions.count }

    /// 注册内置模块 + 落首启默认值 + **起重同步桥** + 激活。幂等，可在启动流程里安全重复调用。
    ///
    /// `collapse` 由**应用侧**在此注入（`UIHandle.requestCollapse()` 的唯一实现落点）：
    /// 组合根本身不认识窗口，只把闭包透传给注册表（docs/13 D-28）。
    /// 默认 `{}` = 没有接线时收起请求是空操作（单测与「注释掉一行」的启动路径都不必改）。
    public static func bootstrap(collapse: @escaping () -> Void = {}) async {
        // 首启默认值先落：模块 `activate()` 里读宿主设置时看到的已是最终值。
        applyFirstLaunchDefaults()

        let registry = ModuleRegistry.shared
        // 启用门 = `enablementGate`（docs/17 §接口与数据形状 3）：先看接管真源，再看用户显式选择，最后回落 manifest。
        registry.register(builtinModules, enabled: enablementGate(registry: registry))
        // 桥在注册之后、激活之前起：激活那一刻的 `states` 由门判定，桥只负责之后的「别处改键」。
        startTakeoverBridge(registry: registry)
        await registry.bootstrap(collapse: collapse)
    }

    /// 组合根注入的启用门（docs/17 §接口与数据形状 3；docs/20 §接口与数据形状 2 的三段判定）：
    ///
    /// 1. **接管键**（`registry.takeoverEnableKey(for:)` 非 nil）→ **直接读它**：
    ///    `moduleEnableOverrides` 与 `manifest.defaultEnabled` 都不再看（D-01：真源唯一才不会漂）；
    /// 2. **键在 `moduleEnableOverrides` 里就取键值**（用户显式表达，压过 manifest）；
    /// 3. **缺键回落 `manifest.defaultEnabled`**，未注册的 id 回落 `false`（06 §2.2 缺省 false）。
    ///
    /// 为什么在组合根而不是注册表：门是「怎么判定启用」，读偏好属组合根职责——注册表只接收
    /// 一个闭包，不知道用户偏好的存在（D-05 / 放 `ModuleRegistry` 上会把偏好读取漏进内核）。
    /// internal 便于单测直接验三档回落，不必跑整个 `bootstrap()`。
    ///
    /// **不写任何偏好**：门只读（写是设置页 / 组件页的事，见 `ModuleEnablementWrite`）。
    static func enablementGate(registry: ModuleRegistry) -> (String) -> Bool {
        { id in
            if let takeoverKey = registry.takeoverEnableKey(for: id) {
                return Defaults[takeoverKey]
            }
            return Defaults[.moduleEnableOverrides][id] ?? (registry.manifests[id]?.defaultEnabled ?? false)
        }
    }

    /// 为每个**接管模块**订阅它那一个上游键，键被改动时把注册表状态拉回来（docs/20 §做法 机制二）。
    ///
    /// 为什么需要这条桥：启用真源是上游键以后，**上游设置页也是这个开关的一个入口**——
    /// 不订阅就会出现「计时器已经关了、tab 还在」。桥走的正是设置页那条同一条路径
    /// （`ModuleRegistry.setEnabled(_:for:)`），而 `setEnabled` **本身不写偏好**，因此不会自激。
    ///
    /// 三条口径（改动前先读）：
    /// - **幂等**：进入先 `removeAll()`，重复调用不会让订阅翻倍；
    /// - **`options: []`**（不加 `.initial`）：本项目 `Defaults` 包只有 `.initial` / `.prior` 两个
    ///   `ObservationOption`，`.initial` 会在**订阅瞬间**发一次当前值、凭空改变激活次序——
    ///   仓库里既有写法一律 `options: []`（见 `DynamicIslandApp.swift` 的同款订阅）；
    /// - **只处理「已激活 ↔ 已关闭」这一维**：`failed` 仍是终态（D-13），桥既不救活它、
    ///   也不把它降级——`setEnabled` 自己就带着这条语义。
    static func startTakeoverBridge(registry: ModuleRegistry) {
        takeoverSubscriptions.removeAll()

        // id 升序：订阅建立顺序稳定（便于复现，也让日志可读）。
        for id in registry.manifests.keys.sorted() {
            guard let key = registry.takeoverEnableKey(for: id) else { continue }
            takeoverSubscriptions[id] = Defaults.publisher(key, options: [])
                .removeDuplicates { $0.newValue == $1.newValue }
                .sink { change in Task { @MainActor in await registry.setEnabled(change.newValue, for: id) } }
        }

        log.info("重同步桥已起：\(takeoverSubscriptions.count, privacy: .public) 个接管模块（id：\(takeoverSubscriptions.keys.sorted().joined(separator: ", "), privacy: .public)）")
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
