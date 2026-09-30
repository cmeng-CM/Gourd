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
//  ProgressModule.swift
//  Gourd 内置模块 · 日/周/月/季/年进度（P1 批次 / T4；p3-widgets / T1 改首页块）
//
//  P1 的试点模块（D-07）：零私有 API、零依赖——它同时是「新增一个模块 = 实现
//  `GourdModule` + 往 `KernelBootstrap.builtinModules` 加一行」（验收 A3）里那「一行」的样本。
//
//  **形态定稿（2026-09-27 用户反馈后重做，09 §5.3 呈现行；2026-09-30 折叠态撤销；
//  2026-09-30 本批（p3-widgets）改首页块，26 §做法 机制一 / D-01）**：
//  - **首页块（`home`，本模块今天唯一声明的 surface）= 紧凑清单**：一行一个尺度（图标 + 标签 +
//    细进度条 + 百分比），必须能在**最小块（180×152）里不裁不溢**；宽度 ≥
//    `ProgressHomeBlockLayout.twoRowWidth`（220）时画**两行**（默认 `visibleScopes` = 日 + 年），
//    窄于它只画第一行。**块宽由宿主声明**（`homeBlockWidth` = 180 / 240），模块不参与「我在首页
//    占多宽」的决策（D-11 口径），只按放置后的宽度分档。
//  - ~~展开态（`expanded`）= 剩余量清单~~ **本批改判**：进度是**纯展示**（没有 `Button` / `Toggle` /
//    `Picker`），用户判定「如果只是显示，就改为首页小组件」（26 §背景与目标 第 1 条）——
//    `.expanded` 不再声明，模块不再占展开 tab。那份展开清单（`ProgressModuleView` /
//    `ProgressScopeRow`）**保留在文件里但不挂任何 surface**（可逆：将来若要回面板，把 `.expanded`
//    加回 `surfaces` 与 `content(for:)` 的两处分支即可），本批不删代码。
//  - ~~折叠态（`compact` / `slot == .center`）= 中央槽位常驻「最关心的一个尺度」的百分比~~
//    **2026-09-30 撤销**：那枚「尺度图标 + 百分比」（默认 `sun.max` + `53%`）在关闭态与**亮度 HUD**
//    同形——用户 2026-09-30 报为「收起态长期挂着一枚亮度 HUD」并由本批（p3-freeze）定位到本模块。
//    故本模块**不再声明 `compact`**（与 launcher / shortcuts / frontapp / calendar 同口径），
//    折叠态中央槽位交回 `todos`（order 20，D-20 的口径）。
//  - `defaultPlacement`：`slot` 记 `nil`（`slot` 只在含 `compact` 时有意义，06 §6.2）；
//    `order` 保留 **30**——它今天的含义是**首页块顺序**（`defaultPlacement.order` 的双语义，
//    13 §已知限制 25）：落在 todos（20）之后、notifications（40）之前。
//  旧的三态排版（等权五环 / 条形 / 纯文本）已不再使用：`style` 配置项**保留**（契约不变），
//  但本版**只实现清单这一种形态**，`ring` / `bar` / `text` 取值一律按清单渲染。
//
//  **开关口径**：进度**没有上游总开关**，因此它**不是接管模块**（不声明 `takeoverEnableKey`）——
//  启用真源沿用既有那一条：`moduleEnableOverrides`（用户显式选择）→ `manifest.defaultEnabled`
//  （false，2026-09-28 用户判定「时间进度」无行动价值）。组件页那张卡拨的就是它。
//
//  **颜色**：面板是黑底，而系统外观可以是浅色——`.primary` / `.secondary` 在这种组合下就是
//  黑字黑底（上游其它面板视图都显式 `.foregroundStyle(.white)`）。因此本模块内**所有**文字与
//  图标一律显式浅色（`Color.white` / `.white.opacity(...)`），不再依赖语义色。
//
//  文案走 Localizable key（06 §3.3 R5）：`module.progress.name` / `module.progress.summary`、
//  `module.progress.scope.<scope>`、`module.progress.remaining`、`module.progress.unit.<unit>`。
//

import SwiftUI

/// `style` 配置的取值（09 §5.3：ring / bar / text）。
///
/// 本版**只渲染清单形态**：三个取值都能被解析、也都写进了 manifest 的 `values`（契约不变），
/// 但展开面板一律按剩余量清单渲染——等权多环被用户判定为「看不出在表达什么」。
enum ProgressStyle: String, CaseIterable {
    case ring
    case bar
    case text
}

/// `baseCalendar` 配置的取值（09 §5.3：公历 / 农历，默认公历）。
///
/// 本批只声明取值、**不参与计算**：`ProgressCalculator` 恒用 `Calendar.autoupdatingCurrent`
/// （09 §5.3 的边界要求），农历周的算法口径未定（09 §5.3 原文即带问号）；P1-3 落配置入口时再接消费者。
enum ProgressBaseCalendar: String, CaseIterable {
    case gregorian
    case chinese
}

// MARK: - ProgressModule

/// 09 §5.3 的 `progress` 模块。
@MainActor
final class ProgressModule: GourdModule {
    /// 静态元数据（06 §2.2 的本批子集）。
    ///
    /// - `surfaces`：**只声明 `home`**（首页块 = 紧凑清单）——折叠态中央槽位 2026-09-30 撤销
    ///   （那枚「图标 + 百分比」与亮度 HUD 同形，见文件头注）；展开面板 tab 同日撤销
    ///   （纯展示改首页小组件，D-01：`.expanded` 不再声明、`content(for: .expanded)` 答 `.none`）；
    /// - `defaultPlacement`：`slot == nil`（`slot` 只在含 `compact` 时有意义，06 §6.2）、
    ///   `order == 30`（今天是**首页块顺序**：13 §已知限制 25 的双语义）；
    /// - **`defaultEnabled` 为 `false`（2026-09-28 用户判定「时间进度」无行动价值）**：
    ///   代码与 manifest 全部保留（可在组件页手动开回）。本模块**不是接管模块**（没有上游总开关），
    ///   因此启用真源就是既有那一条——`moduleEnableOverrides` 压过这里的默认值；
    /// - `config` 三项只声明类型与默认值：本批**没有用户可见的配置入口**（docs/13「明确不做」），
    ///   读取侧拿到的恒是这里的 `default`；`visibleScopes` 的默认值即「出厂显示哪些尺度」（日 + 年）。
    static let manifest = ModuleManifest(
        manifestVersion: 1,
        id: "com.cmeng.gourd.progress",
        name: LocalizedText(key: "module.progress.name"),
        summary: LocalizedText(key: "module.progress.summary"),
        icon: IconSpec(type: "symbol", name: "chart.pie"),
        version: "1.0.0",
        apiVersion: HostInfo.currentAPIVersion,
        kind: "builtin",
        surfaces: [.home],
        defaultPlacement: Placement(slot: nil, order: 30),
        defaultEnabled: false,
        permissions: [],
        config: ConfigSchema(
            type: "object",
            properties: [
                "visibleScopes": ConfigNode(
                    type: "list",
                    title: nil,
                    default: .strings(ProgressCalculator.defaultVisibleScopes.map(\.rawValue)),
                    values: nil,
                    itemType: "string"
                ),
                "style": ConfigNode(
                    type: "enum",
                    title: nil,
                    default: .string(ProgressStyle.ring.rawValue),
                    values: ProgressStyle.allCases.map(\.rawValue),
                    itemType: nil
                ),
                "baseCalendar": ConfigNode(
                    type: "enum",
                    title: nil,
                    default: .string(ProgressBaseCalendar.gregorian.rawValue),
                    values: ProgressBaseCalendar.allCases.map(\.rawValue),
                    itemType: nil
                ),
            ]
        )
    )

    private let context: ModuleContext

    init(context: ModuleContext) {
        self.context = context
    }

    /// 接管三件套之三：**宽度声明**（D-10 的形态，虽然不是接管模块）——本模块**改判为首页块**后
    /// 必须自己声明宽度，否则宿主会按「未声明 → 统一值 180 / 240」兜底；而 26 §做法 机制一 给进度的
    /// 定值就是 `180 / 240`——两者同值，写出来是为了把「进度块占多宽」写在类型上，而不是靠缺省值。
    ///
    /// 另两条钩子**不重写**：本模块不是接管模块（`takeoverEnableKey` 缺省 nil，启用走
    /// `moduleEnableOverrides` + `defaultEnabled`）；它也不声明 `expanded`（`isTabVisible()` 永不被问到，
    /// 写一条 `= true` 只会让读者以为本模块有 tab——与 mirror / music 同一口径）。
    static var homeBlockWidth: ModuleHomeBlockWidth? { ModuleHomeBlockWidth(min: 180, ideal: 240) }

    /// 无副作用（视图与计算都在 `content(for:)` 里按需取），因此只有一条激活日志。
    func activate() async throws {
        context.logger.info("progress 模块已激活（scopes=\(scopes.map(\.rawValue).joined(separator: ","))）")
    }

    func deactivate() async {}

    /// 只答 `home`（首页块 = 紧凑清单，见 `ProgressHomeBlockView`）；
    /// 未声明的 `expanded` / `compact` / `lockscreen` 一律 `.none`（06 §3.2 的「该 surface 此刻无内容」：
    /// 不占位、也不算失败）。`.expanded` 是本批（p3-widgets / T1）**撤销**的那一条——它不再声明，
    /// 展开面板因此不再有「进度」tab；那份展开清单的视图代码保留在文件里（可逆），但不挂 surface。
    ///
    /// 配置在**每次请求时重读**：宿主 `requestRedraw()` 触发重算时，视图拿到的是新的
    /// `visibleScopes`（本批没有配置入口，读到的是 manifest 默认值）。
    func content(for request: ContentRequest) -> ModuleContent {
        switch request.surface {
        case .home:
            return .view(AnyView(ProgressHomeBlockView(scopes: scopes)))
        case .expanded, .compact, .lockscreen:
            return .none
        }
    }

    // MARK: - 配置读取

    /// 展示哪些尺度 = manifest 的 `visibleScopes` **默认值**经 `resolveScopes` 解析
    /// （默认 日 + 年；未知取值逐项忽略、空值回落默认）。
    ///
    /// 本版直接读 manifest：没有用户可见的配置入口，`context.config` 读到的也是同一个默认值
    /// （docs/13 已知限制 12/21）；P1-3 接上配置入口时改走 `context.config`（覆盖值优先）。
    private var scopes: [ProgressCalculator.Scope] {
        ProgressCalculator.resolveScopes(from: Self.manifest.config?.properties["visibleScopes"]?.default)
    }
}

// MARK: - 首页块（紧凑清单）

/// 首页块的**取舍**（纯函数，无 SwiftUI 依赖，单测直接钉边界）。
///
/// 规格（[26](../../docs/26-home-widgets-and-settings.md) §做法 机制一 / §验收标准 2）：块内容是
/// **紧凑清单**——一行一个尺度（图标 + 标签 + 细条 + 百分比），在最小块（180×152）里**不裁不溢**；
/// 宽度 ≥ `twoRowWidth` 时多画一行。块宽由宿主 `HomeStripLayoutMath` 分配（本模块声明 180 / 240），
/// 模块**不读 `.layoutValue`、不自己测量**——分档取的是**放置后**的宽度（`GeometryReader`），
/// 与 `TodosHomeBlockLayout.listTier(forWidth:)` 同一手法。
enum ProgressHomeBlockLayout {
    /// 画**两行**的最小块宽（规格：220）。窄于它只画第一行。
    ///
    /// 数值来源：最窄档（180）下「图标 + 标签 + 细条 + 百分比」一行要 ~96pt 固定宽，两行并排只会
    /// 让长标签（`This year` / `本年进度`）挤掉进度条；220 是宿主给本模块的 `ideal`（240）之下
    /// 一档的整数取整，也是待办块「完整行」用的同一个阈值（两处不必是同一个数，同值是巧合也是便利：
    /// 用户在 770pt 面板里看到的两块的分档线因此一致）。
    static let twoRowWidth: CGFloat = 220

    /// 该块宽下最多画几行：`>= 220` → 2；更窄或宽度取不到（非有限数 / 首帧 0）→ 1。
    ///
    /// 宽度取不到时退到最保守的档（只画一行）：一行一定放得下（最小块 180 也 ≥ 一行所需），
    /// 两行要按宽度取舍，因此宁可少画一行也不让内容溢出块宽。
    static func rowLimit(forWidth width: CGFloat) -> Int {
        guard width.isFinite else { return 1 }
        return width >= twoRowWidth ? 2 : 1
    }

    /// 该块宽下要画的尺度：按 `visibleScopes` 的**声明顺序**取前 N 个
    /// （默认 日 + 年 → 窄块画「今天」、宽块画「今天 + 今年」）。
    static func listedScopes(
        _ scopes: [ProgressCalculator.Scope],
        forWidth width: CGFloat
    ) -> [ProgressCalculator.Scope] {
        Array(scopes.prefix(rowLimit(forWidth: width)))
    }
}

/// 首页块：**紧凑清单**（图标 + 标签 + 细进度条 + 百分比，一行一个尺度）。
///
/// 与展开面板那份「剩余量清单」**同源**：进度值都是同一个 `ProgressCalculator.progress(for:now:)`
/// （不另写一套统计），刷新粒度也沿用同一个**粗粒度 60s**（docs/13 已知限制 14：清单最小单位是分钟；
/// 首页块只在展开面板里存在，`TimelineView` 的 60s 心跳只在块可见时跑）。
///
/// **只读**：块里不挂任何控件（这正是用户判定「只是显示 → 改为首页小组件」的理由）；
/// 没有空态、没有失败态——「今天」的进度在任何时刻都是有定义的。
///
/// 宽度用 `GeometryReader` 读**放置后**的尺寸（不是测量）：按 `rowLimit(forWidth:)` 分档，
/// 见 `ProgressHomeBlockLayout`。颜色一律显式白色系（面板黑底、系统外观可能浅色，见文件头「颜色」）。
private struct ProgressHomeBlockView: View {
    let scopes: [ProgressCalculator.Scope]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            GeometryReader { proxy in
                let rows = ProgressHomeBlockLayout.listedScopes(scopes, forWidth: proxy.size.width)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows, id: \.self) { scope in
                        ProgressHomeRow(scope: scope, now: timeline.date)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// 首页块的一行：图标 + 标签 + 细进度条 + 百分比。
///
/// 与展开行（`ProgressScopeRow`）的差别只有两处：**不画剩余量**、**不画悬停的起止时刻**
/// ——窄块里那两段固定宽度的文字会把进度条挤没（首页块是「一眼看多少」，主信息是百分比）。
private struct ProgressHomeRow: View {
    let scope: ProgressCalculator.Scope
    let now: Date

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: scope.symbolName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 12)

            Text(LocalizedStringKey(scope.labelKey))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)

            ProgressView(value: ProgressCalculator.progress(for: scope, now: now))
                .progressViewStyle(.linear)
                .frame(maxWidth: .infinity)

            Text(ProgressText.percent(ProgressCalculator.progress(for: scope, now: now)))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .fixedSize()
        }
    }
}

// MARK: - 展开面板视图（剩余量清单；本批已撤销该 surface，代码保留）

/// 展开面板里的 progress 内容：**剩余量清单**——一行一个尺度，主信息是「还剩多久」。
///
/// **本批（p3-widgets / T1）起不再被任何 surface 渲染**：`surfaces` 已改成 `[.home]`，
/// 展开面板不再有「进度」tab（D-01）。代码**保留**是为了可逆——将来要回到面板，
/// 把 `.expanded` 加回 manifest 的 `surfaces` 与 `content(for:)` 的 `.expanded` 分支即可。
///
/// 刷新粒度沿用**粗粒度**的 60s（docs/13「已知限制」14）：清单里最小单位是分钟，
/// 1 分钟粒度足够，也**未监听 `NSSystemClockDidChange`**——系统的时钟 / 时区变更最多 60s 内
/// 被感知，超过 60s 的跳变在下一个周期校正。
///
/// 排版口径（取代旧的「一排五个等权环」）：一行 = 图标 + 尺度标签 + 细进度条（占满剩余宽度）
/// + 剩余量（主信息、白色）+ 百分比（小字、`.white.opacity(0.6)`）；行悬停时在该行下方补一行
/// 起止时刻（`Date.FormatStyle` 本地化格式，无新增文案 key）。
private struct ProgressModuleView: View {
    let scopes: [ProgressCalculator.Scope]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            VStack(alignment: .leading, spacing: 10) {
                ForEach(scopes, id: \.self) { scope in
                    ProgressScopeRow(scope: scope, now: timeline.date)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

/// 清单的一行：图标 + 标签 + 进度条 + 剩余量 + 百分比；悬停时在下方补起止时刻。
///
/// 每行自带 `@State` 悬停标志，因此行必须是一个独立的 View（`ForEach` 里共享不了 `@State`）。
private struct ProgressScopeRow: View {
    let scope: ProgressCalculator.Scope
    let now: Date

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: scope.symbolName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 14)

                Text(LocalizedStringKey(scope.labelKey))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize()

                ProgressView(value: ProgressCalculator.progress(for: scope, now: now))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: .infinity)

                Text(ProgressText.remainingText(for: scope, now: now))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Text(ProgressText.percent(ProgressCalculator.progress(for: scope, now: now)))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
            }
            .onHover { isHovered = $0 }

            if isHovered, let interval = ProgressCalculator.interval(for: scope, now: now) {
                Text(ProgressText.interval(interval))
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.leading, 22)
            }
        }
    }
}

// MARK: - 折叠态中央槽位视图（2026-09-30 撤销，视图一并删除）

/// ~~折叠态中央槽位的内容：尺度图标 + 百分比（`visibleScopes` 首项，默认「今天」→ `sun.max`）~~
///
/// **已删除（2026-09-30，本批 p3-freeze）**：那枚 pill 在关闭态与亮度 HUD 同形——用户报
/// 「收起态长期挂着一枚亮度 HUD」；根因就是这里（11pt 尺度图标 + 13pt 百分比），而模块默认关、
/// 一旦被手动开回（`moduleEnableOverrides`）就在关闭态常驻。撤销口径见文件头注与 manifest 的
/// `surfaces`：**折叠态不再由本模块承担**，展开态的剩余量清单不受影响。

// MARK: - 文案出口

/// 模块内所有动态文案 / 数值的唯一出口（06 §3.3 R5：视图内不写字面量文案）。
///
/// 百分比与剩余量都**先拼成 String 再给 `Text`**——走 `Text(_: String)` 的 verbatim 重载，
/// 不会把 `%lld%%` / `%@` 这类形态当成本地化 key 去查表。
private enum ProgressText {
    /// `0.42` → `"42%"`。
    static func percent(_ progress: Double) -> String {
        "\(Int((progress * 100).rounded()))%"
    }

    /// 剩余量主信息：`remaining` 只给数值与单位，这里拼「数值 + 单位」再套 `module.progress.remaining`
    /// （en `%@ left` / zh-Hans `剩 %@`）。
    ///
    /// 小时档由 `remaining` 只给整点，**分钟余量在这里从同一区间取**（09 §5.3：「1 小时 ≤ 剩余 < 1 天
    /// → 小时 + 分钟，view 里拼 X 小时 Y 分钟」）；日历口径与 `ProgressCalculator` 一致，都用
    /// `.autoupdatingCurrent`。
    static func remainingText(for scope: ProgressCalculator.Scope, now: Date) -> String {
        let remaining = ProgressCalculator.remaining(for: scope, now: now)
        let amount: String
        switch remaining.unit {
        case .day:
            amount = "\(remaining.value) \(localized("module.progress.unit.day"))"
        case .hour:
            // 小时与余分钟**成对**取（同一个总分钟数拆分）——分别取会出现「13 小时 826 分钟」。
            let pair = ProgressCalculator.remainingHoursAndMinutes(for: scope, now: now)
            let hours = "\(pair.hours) \(localized("module.progress.unit.hour"))"
            amount = pair.minutes > 0
                ? hours + " \(pair.minutes) \(localized("module.progress.unit.minute"))"
                : hours
        case .minute:
            amount = "\(remaining.value) \(localized("module.progress.unit.minute"))"
        }
        return String(format: localized("module.progress.remaining"), amount)
    }

    /// 行悬停的起止时刻：`Date.FormatStyle` 的本地化格式（形如 `09-28 00:00 → 10-01 00:00`），
    /// 因此**不新增文案 key**。
    static func interval(_ interval: DateInterval) -> String {
        let momentStyle = Date.FormatStyle()
            .month(.twoDigits)
            .day(.twoDigits)
            .hour(.twoDigits(amPM: .omitted))
            .minute(.twoDigits)
        return "\(interval.start.formatted(momentStyle)) → \(interval.end.formatted(momentStyle))"
    }

    /// `module.<shortID>.<field>` 形态的 key → 当前语言文案。
    /// 查不到时 `Bundle` 原样返回 key（不崩、也不显示空串），与 `ModuleRegistry.label(for:)` 同一口径。
    private static func localized(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }
}

// MARK: - 尺度图标与标签

extension ProgressCalculator.Scope {
    /// 行首 / 槽位图标。纯观感，不参与计算；单测对系统符号表逐个校验可用性
    /// （internal 而非 private 就是为了让这条校验能写到单测里）。
    var symbolName: String {
        switch self {
        case .day: return "sun.max"
        case .week: return "calendar"
        case .month: return "calendar.circle"
        case .quarter: return "chart.pie"
        case .year: return "calendar.badge.clock"
        }
    }

    /// 标签的本地化 key（`module.progress.scope.<rawValue>`）。
    /// 走 key 而不是 `LocalizedText`：06 §3.3 R5 只约束 manifest 的 name/summary 形态。
    var labelKey: String { "module.progress.scope.\(rawValue)" }
}
