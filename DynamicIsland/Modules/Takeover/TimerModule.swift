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
//  TimerModule.swift
//  Gourd 内置模块 · 计时器接管（P2 接管批次 / T2）
//
//  docs/20-component-page.md §接口与数据形状 5 的 timer 行逐字落地：**接管 = 模块拥有渲染点 +
//  启用真源是上游键**（D-01）。上游 `TabSelectionView` 里那条
//  `if enableTimerFeature && timerDisplayMode == .tab { … }` 与 `enabledStandardTabCount()`
//  里对应的 `+1` 同批删除——展开面板的计时器 tab 从此由**本模块的投影**产出，
//  一对一替换，不允许并存（并存就是两个计时器 tab）。
//
//  四条刻意写死的口径（改动前先读）：
//
//  1. **只声明 `expanded`**（D-09）：折叠态左右槽位已被用户降级（2026-09-29），
//     `.compact` / `.lockscreen` / `.home` 一律答 `.none`（不占位、不算失败，06 §3.2）。
//  2. **启用真源是 `enableTimerFeature`**（`takeoverEnableKey`）：组合根的启用门直接读它，
//     `moduleEnableOverrides` 与 `manifest.defaultEnabled` 都不再看——不存在第二份状态，
//     也就没有「模块开不开」与「功能开不开」打架的窗口（D-01）。
//  3. **tab 可见性另有条件**（`isTabVisible()`）：功能开着也可能不该有 tab——
//     上游「另一种显示方式」是折叠态里的倒计时（`timerDisplayMode == .popover`）。
//     投影每次读都问一次（不缓存），因此这里读到的是**当下**值。
//  4. **`config` 只登记不接管**（D-03 / §已知限制 1）：三个键的键名与上游默认值写进 manifest
//     供审计，读写仍走上游 `Defaults`（`ConfigHandle` 对它们不生效）。默认值**从上游键取**
//     （`Defaults.Keys.<键>.defaultValue`），不另抄一个字面量——两处各写一个数就会漂。
//
//  文案走 Localizable key（06 §3.3 R5）：`module.timer.name` / `module.timer.summary`。
//

import Defaults
import SwiftUI

// MARK: - TimerModule

/// 计时器接管模块（`docs/20` §接口与数据形状 5 的 timer 行；`docs/14` §1 的 `com.cmeng.gourd.timer`）。
///
/// 渲染点 = 上游那一个 `NotchTimerView`（展开面板的计时器页），除它之外本模块不占任何 surface。
@MainActor
final class TimerModule: GourdModule {
    /// 模块 id 的**唯一字面量**（给调用点用：T3 的悬浮聚焦入口走 `selectModule(TimerModule.moduleID)`，
    /// 避免在渲染层再抄一遍字符串）。manifest 也用它，因此两处不可能漂。
    static let moduleID = "com.cmeng.gourd.timer"

    /// 静态元数据（docs/20 §接口与数据形状 5 + T-12 的取值口径）。
    ///
    /// - `surfaces: [.expanded]`：**只声明展开 tab**——折叠槽位本批不占（口径 1），
    ///   声明 `.compact` 会与待办抢中央槽位；
    /// - `defaultPlacement: nil`：placement 只在含 `compact` 时有意义，本批不声明 `compact`；
    ///   tab 顺序随之取 `Int.max`，落在**模块 tab 段**（`docs/20` §已知限制 2 点名接受的顺序变化）；
    /// - `defaultEnabled: true` = **上游键的默认值**（`enableTimerFeature` 上游默认 `true`）：
    ///   它只在「接管键读不到」时不生效，填它是为了让卡片上那行「默认关闭」不在计时器卡出现
    ///   （接管模块的启用状态由启用门直接读上游键，见口径 2）；
    /// - `permissions: []`：本批只搬渲染归属与开关真源，不新增任何能力请求。
    static let manifest = ModuleManifest(
        manifestVersion: 1,
        id: moduleID,
        name: LocalizedText(key: "module.timer.name"),
        summary: LocalizedText(key: "module.timer.summary"),
        icon: IconSpec(type: "symbol", name: "timer"),
        version: "1.0.0",
        apiVersion: HostInfo.currentAPIVersion,
        kind: "builtin",
        surfaces: [.expanded],
        defaultPlacement: nil,
        defaultEnabled: true,
        permissions: [],
        config: ConfigSchema(
            type: "object",
            properties: [
                // 上游总开关（= 本模块的 `takeoverEnableKey`）。默认值取上游键的默认值
                "enableTimerFeature": ConfigNode(
                    type: "boolean",
                    title: nil,
                    default: .bool(Defaults.Keys.enableTimerFeature.defaultValue),
                    values: nil,
                    itemType: nil
                ),
                // 显示方式：`tab` = 展开面板一个 tab，`popover` = 折叠态里的倒计时（`isTabVisible()` 读它）
                "timerDisplayMode": ConfigNode(
                    type: "enum",
                    title: nil,
                    default: .string(Defaults.Keys.timerDisplayMode.defaultValue.rawValue),
                    values: TimerDisplayMode.allCases.map(\.rawValue),
                    itemType: nil
                ),
                // 预设清单（`[TimerPreset]`：结构比 06 §5.3 的标量词表复杂，只登记为 string 列表，
                // 不给 `default`——类型与默认值都在上游 `Defaults.Keys.timerPresets`，本批不复制）；
                // 读写仍走上游键（口径 4）
                "timerPresets": ConfigNode(
                    type: "list",
                    title: nil,
                    default: nil,
                    values: nil,
                    itemType: "string"
                ),
            ]
        )
    )

    private let context: ModuleContext

    init(context: ModuleContext) {
        self.context = context
    }

    /// 接管三件套之一：**启用真源 = 上游那个开关键本身**（D-01）。
    static var takeoverEnableKey: Defaults.Key<Bool>? { .enableTimerFeature }

    /// 接管三件套之二：功能开着也未必有 tab——`timerDisplayMode == .tab` 才在展开面板里出现
    ///（另一种显示方式是折叠态里的倒计时，与 tab 无关）。投影每次读都问一次，故这里读当下值。
    static func isTabVisible() -> Bool { Defaults[.timerDisplayMode] == .tab }

    /// 接管三件套之三：计时器没有首页块（本批只接 tab），因此用宿主统一宽度——**显式声明 nil**
    /// 是为了把「本模块不参与块宽决策」写在类型上，而不是靠缺省值兜。
    static var homeBlockWidth: ModuleHomeBlockWidth? { nil }

    /// 只记一条日志：计时器没有常驻副作用（定时器与到点通知都在上游 `TimerManager` 里，
    /// 本批只搬渲染归属，不搬生命周期）。
    func activate() async throws {
        context.logger.info(
            "timer 模块已激活（takeover=true，enableTimerFeature=\(Defaults[.enableTimerFeature])，timerDisplayMode=\(Defaults[.timerDisplayMode].rawValue)）"
        )
    }

    /// 没有要收的东西：本模块不起 Task、不订阅、不持有视图外的资源（见 `activate()`）。
    func deactivate() async {}

    /// 只答 `expanded`：上游那个 `NotchTimerView` 逐字接住。
    /// `.compact` / `.lockscreen` / `.home` 一律 `.none`（口径 1：不占位、不算失败）。
    func content(for request: ContentRequest) -> ModuleContent {
        switch request.surface {
        case .expanded:
            return .view(AnyView(NotchTimerView()))
        case .compact, .lockscreen, .home:
            return .none
        }
    }
}
