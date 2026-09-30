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
//  CalendarModule.swift
//  Gourd 内置模块 · 日历接管（P3 冻结批次 / T6）
//
//  docs/24-release-freeze.md §做法 机制三 的落点：给**孤儿视图** `StandaloneCalendarView`
//  （双栏月历：左整月网格 + 右当日清单，此前只有 `#Preview`、运行期无入口）接一个家——
//  展开面板多一个「日历」tab，一对一接住那个视图，不重写、不裁剪。
//
//  上游首页里那条全宽日历行**不动**（它仍是首页的一部分，由 `showCalendar` 门控、
//  由 `NotchHomeView` 直接渲染——它的渲染接管不在本批，见 docs/20 §明确不做）：
//  于是「日历」两处呈现（首页行 / 展开 tab）由**同一个开关**控制，
//  关掉 `showCalendar` 两处一起消失（docs/24 §已知限制 3 点名接受的耦合）。
//
//  三条刻意写死的口径（改动前先读）：
//
//  1. **只声明 `expanded`**：折叠态左右槽位已按用户 2026-09-29 的决定降级、首页块另有主人，
//     `.compact` / `.lockscreen` / `.home` 一律答 `.none`（不占位、不算失败，06 §3.2）。
//  2. **启用真源是 `showCalendar`**（`takeoverEnableKey`）：组合根的启用门直接读它，
//     `moduleEnableOverrides` 与 `manifest.defaultEnabled` 都不再看——本模块不新增第二个开关，
//     用户在这颗上游开关上看到的状态就是「日历 tab 在不在」的状态（D-01 / D-05）。
//     **本模块不加 `isTabVisible()`**：日历没有「另一种显示方式」那一档（与计时器不同），
//     功能开着就该有 tab。
//  3. **不登记 `config`**（与 timer / mirror / music 三个接管模块不同，是有意的）：
//     本模块没有「自己的」配置键——唯一相关的那个上游键就是 `takeoverEnableKey` 本身，
//     再往 manifest 的 `config` 里抄一遍是重复登记（docs/24 §接口与数据形状 的 calendar 片段
//     只列了 manifest 的五个字段，没有 config）。将来若给日历加了本模块自己的键
//     （比如「周起始日」），按 D-03 的口径登记进 `config` 即可。
//
//  文案走 Localizable key（06 §3.3 R5）：`module.calendar.name` / `module.calendar.summary`。
//

import Defaults
import SwiftUI

// MARK: - CalendarModule

/// 日历接管模块（`docs/24` §做法 机制三 / §接口与数据形状 的 calendar 片段；D-05）。
///
/// 渲染点 = 那个孤儿视图 `StandaloneCalendarView`（展开面板的日历页），除它之外本模块不占任何 surface。
/// 视图自己要 `@EnvironmentObject var vm: DynamicIslandViewModel`：展开面板的模块内容由
/// `ModuleHostView` 渲染在 `ContentView` 这棵树上（根部 `.environmentObject(vm)`），
/// 因此这里**不需要**（也不该）自己包一层 `environmentObject`——上游视图拿 vm 的方式逐字相同。
@MainActor
final class CalendarModule: GourdModule {
    /// 模块 id 的**唯一字面量**（manifest 与用例都用它，两处不可能漂）。
    static let moduleID = "com.cmeng.gourd.calendar"

    /// 静态元数据（docs/24 §接口与数据形状 的 calendar 片段逐条落地）。
    ///
    /// - `surfaces: [.expanded]`：**只声明展开 tab**——折叠槽位与首页块本批不占（口径 1）；
    /// - `defaultPlacement: nil`：placement 只在含 `compact` 时有意义，本批不声明 `compact`；
    ///   tab 顺序随之取 `Int.max`，落在**模块 tab 段**（与计时器 / 启动台同一段，按 id 字典序）；
    /// - `defaultEnabled: true` = **上游键的默认值**（`showCalendar` 上游默认 `true`）：它只在
    ///   「接管键读不到」时不生效，填它是为了让卡片上那行「默认关闭」不在日历卡出现
    ///   （接管模块的启用状态由启用门直接读上游键，见口径 2）；
    /// - `permissions: []`：本批只搬渲染归属，不新增任何能力请求（日历数据的读取仍走上游
    ///   `CalendarManager` 本来就有的那条 EventKit 权限，与本模块无关）；
    /// - `config: nil`：口径 3——没有本模块自己的键可登记。
    static let manifest = ModuleManifest(
        manifestVersion: 1,
        id: moduleID,
        name: LocalizedText(key: "module.calendar.name"),
        summary: LocalizedText(key: "module.calendar.summary"),
        icon: IconSpec(type: "symbol", name: "calendar"),
        version: "1.0.0",
        apiVersion: HostInfo.currentAPIVersion,
        kind: "builtin",
        surfaces: [.expanded],
        defaultPlacement: nil,
        defaultEnabled: true,
        permissions: [],
        config: nil
    )

    private let context: ModuleContext

    init(context: ModuleContext) {
        self.context = context
    }

    /// 接管三件套之一：**启用真源 = 上游那颗日历总开关本身**（口径 2）。
    ///
    /// 与首页那条日历行共用同一个键：本模块不是「再开一个开关」，而是「让这个开关多管一处呈现」。
    static var takeoverEnableKey: Defaults.Key<Bool>? { .showCalendar }

    /// 只记一条日志：日历没有常驻副作用（事件数据与刷新都在上游 `CalendarManager` 里，
    /// 本批只搬渲染归属，不搬生命周期）。
    func activate() async throws {
        context.logger.info(
            "calendar 模块已激活（takeover=true，showCalendar=\(Defaults[.showCalendar])）"
        )
    }

    /// 没有要收的东西：本模块不起 Task、不订阅、不持有视图外的资源（见 `activate()`）。
    func deactivate() async {}

    /// 只答 `expanded`：那个孤儿视图逐字接住（`StandaloneCalendarView()`，零参数）。
    /// `.compact` / `.lockscreen` / `.home` 一律 `.none`（口径 1：不占位、不算失败）。
    func content(for request: ContentRequest) -> ModuleContent {
        switch request.surface {
        case .expanded:
            return .view(AnyView(StandaloneCalendarView()))
        case .compact, .lockscreen, .home:
            return .none
        }
    }
}
