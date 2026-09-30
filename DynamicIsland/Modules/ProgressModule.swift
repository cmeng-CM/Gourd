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
//  2026-09-30 本批（p3-widgets）改首页块，26 §做法 机制一；
//  2026-09-30 p5-home-blocks / T2 按 docs/29 §做法 机制二 定稿）**：
//  - **首页块（`home`，本模块今天唯一声明的 surface）= 紧凑清单**：一行一个尺度（图标 + 标签 +
//    细进度条 + 百分比）。**能画几行由块自己的尺寸定**（`ProgressHomeBlockLayout`：宽度档与高度档
//    取小者），不缩字、不滚动——96 高的紧凑块里五行放得下（5×14 + 4×6 = 94），因此默认三档
//    （今天 / 本周 / 本月）与勾上的第四、第五档**都会上屏**；再放不下就按声明顺序只画前几个。
//    **块宽由宿主声明**（`homeBlockWidth` = 180 / 240），模块不参与「我在首页占多宽」的决策
//    （D-11 口径），只按放置后的尺寸分档。
//  - **展示哪几档由用户定**（docs/29 §做法 机制二 / D-04、D-05）：默认 **今天 / 本周 / 本月**
//    （`ProgressCalculator.defaultVisibleScopes`），组件卡上新增的「显示的尺度」多选可以把
//    **本季 / 今年**勾出来——`scopes` 读的是 `context.config`（覆盖值优先、坏值回落默认），
//    不再是 manifest 的默认值。它是**自然时间进度**（`Calendar` 口径：日 / 周 / 月 / 季 / 年），
//    不是任务完成度（那是待办的事）、也不是工作日口径（不引节假日与调休表，docs/29 §明确不做 1）。
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
//  `module.progress.scope.<scope>`、`module.progress.remaining`、`module.progress.unit.<unit>`；
//  组件卡那一行的标题是 `settings.modules.progress.visibleScopes`（显示的尺度 / Scales shown）。
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
    /// - `config` 三项只声明类型与默认值；`visibleScopes` 的默认值即「出厂显示哪些尺度」
    ///   （**今天 / 本周 / 本月**，docs/29 §做法 机制二 / D-04）。**它今天有用户可见的配置入口**：
    ///   组件卡的「显示的尺度」多选（`ModuleSettingsSection.configControls`）写的是同一个键的
    ///   **覆盖值**，读取侧 `scopes` 先看覆盖值、取不到才回落到这里的默认值。
    ///   `style` / `baseCalendar` 仍**没有入口**（前者「只实现清单这一种形态」、后者算法口径未定）。
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
    /// `visibleScopes`——组件卡勾一下「本季」，首页块在同一会话里就多一行（不需要重启）。
    func content(for request: ContentRequest) -> ModuleContent {
        switch request.surface {
        case .home:
            return .view(AnyView(ProgressHomeBlockView(scopes: scopes)))
        case .expanded, .compact, .lockscreen:
            return .none
        }
    }

    // MARK: - 配置读取

    /// 展示哪些尺度 = **覆盖值优先**（组件卡的「显示的尺度」多选写的就是这个键的覆盖值），
    /// 取不到才回落到 manifest 的 `visibleScopes` 默认值（今天 / 本周 / 本月）。
    ///
    /// `ConfigHandle.get` 的既有语义就是「先查覆盖值、再回落 `manifest.config.properties[key].default`」
    /// （`ManifestConfigHandle` 一处实现），因此这里**不自己带第二份默认值**：组件卡读出来的勾中项
    /// 与块画出来的那几行是同一个判定。`?? []` 只兜「键漂出 schema」（`get` 给 nil）这一种退化——
    /// 空表在 `resolveScopes` 里同样回落默认，不崩、也不留空块。
    ///
    /// **本版改读 `context.config`**（docs/29 §做法 机制二 / D-05）：原实现直接读 manifest 的
    /// 默认值（「本版直接读 manifest：没有用户可见的配置入口」），配置真源本来就是这一个键，
    /// 缺的只是入口与读取——入口见 `ModuleSettingsSection.configControls`。
    ///
    /// **internal 而不是 private**：单测要在假句柄与真句柄（probe manifest）上钉「覆盖值优先 /
    /// 坏值回落」这两档（同 `ProgressCalculator.Scope.symbolName` 那条口径——为一条能被断言的
    /// 契约放开可见性，而不是为测试改行为）。
    var scopes: [ProgressCalculator.Scope] {
        ProgressCalculator.resolveScopes(from: context.config.get("visibleScopes", as: [String].self) ?? [])
    }
}

// MARK: - 首页块（紧凑清单）

/// 首页块的**取舍**（纯函数，无 SwiftUI 依赖，单测直接钉边界）。
///
/// 规格（[29](../../docs/29-home-blocks-and-panel.md) §做法 机制二 / D-03~D-05；原 26 §做法 机制一）：
/// 块内容是**紧凑清单**——一行一个尺度（图标 + 标签 + 细条 + 百分比），一行的高度钉在 `rowHeight`；
/// **能画几行由块的尺寸定**：**宽度档与高度档取小者**（`listedScopes(_:forWidth:height:)`），
/// 行数再按 `visibleScopes` 解析出来的那一组的**先后**取前 N 个——**不缩字、不滚动**（docs/29 §已知限制 3）。
/// （「那一组」的顺序：组件卡写进去的恒是选项的声明顺序，手改配置文件写别的顺序也照它来。）
/// 块宽由宿主 `HomeStripLayoutMath` 分配（本模块声明 180 / 240），模块**不读 `.layoutValue`、
/// 不自己测量**——分档取的是**放置后**的尺寸（`GeometryReader`），与待办块同一手法。
///
/// **两条档位各自管什么**（改动前先读）——**两条都只答「最多几行」这一个数**（`Int`），
/// 「画面上的哪几行」永远是拿这个数去截**用户当前那一组尺度**（`visibleScopes` 的解析结果）的**前缀**，
/// 不是「总能画全的固定三种」：
/// - **高度档**是真正的刹车：96 高的紧凑块里五行放得下（5×14 + 4×6 = 94），多出来的尺度画不下
///   就按那一组的先后截断——这保证了「块内不出现半个字」（块壳 `.clipped()` 会把溢出裁掉，
///   算错就是失败信号「块内被裁出半个字」）；
/// - **宽度档**只在两种退化情形出手：**非有限宽**（NaN / ±∞，取不到真值）→ **1 行**；
///   以及**低于声明最小宽 180 的窄块**（`HomeStripLayoutMath` 规则 ③ 的单块兜底、被压缩过的宽度，
///   **也包括首帧的 0**——0 是有限数，落这一档）→ **3 行**。因此 180 起一行就够排完五档
///   （一行的固定宽 ≈ 图标 12 + 两段间距 + 百分比 ≈ 28 + 标签），宽度**不是**行数的真实约束
///   ——不再按宽度少画行（旧版「≥220 画两行」会让「勾上本季」在窄块上看起来没反应）。
enum ProgressHomeBlockLayout {
    /// 一行的**行高**：11pt 文字（`ProgressHomeRow` 的字号）的自然行高（实测 14pt）。
    ///
    /// 行视图用 `.frame(height:)` 钉住它，进度条也钉在 `barHeight`——`.linear` 的默认高度是
    /// **20pt**，不钉住它行高就不是 14（行会互相压），高度档的算术也就不成立了。
    static let rowHeight: CGFloat = 14

    /// 行与行的间距。取 6 的理由只有一条：**96 高的紧凑块里五行放得下**（5×14 + 4×6 = 94 ≤ 96）
    /// ——「勾满五档」在屏上是五行都在，而不是「勾了第五个没反应」。
    static let rowSpacing: CGFloat = 6

    /// 细进度条的高度（观感值，与行高分开：条钉住后一行的高度才是确定的 14）。
    static let barHeight: CGFloat = 6

    /// **宽度档**的门槛：块宽到模块声明的**最小宽**（`homeBlockWidth.min` = 180）就够一行一个尺度地
    /// 排完全部五档（答 5 行，不再按宽度卡）；更窄的块是退化态（见类型注释），答 **3 行**。
    ///
    /// 数值写死（不写成 `ProgressModule.homeBlockWidth?.min`：那条读的是 `@MainActor` 类型的静态
    /// 属性，在这个纯函数命名空间里读会把 actor 隔离带进来）；「两处同值」由单测钉住
    /// （`allScopesWidth == ProgressModule.homeBlockWidth?.min`），漂了就红。
    static let allScopesWidth: CGFloat = 180

    /// **该块宽下最多画几行**（宽度档）——返回值是**行数上限**，不是「画哪几档」：
    /// - 宽度取不到（**非有限数**：NaN / ±∞）→ **1**：宁可少画一行也不赌，与旧版同一条口径；
    /// - 到 `allScopesWidth`（180；理想宽 240 与更宽的宽度都在这一档）→ **全部五档**（行数交给高度档刹车）；
    /// - 更窄的有限宽（**含 0** 与首帧）→ **3 行**（`defaultVisibleScopes.count`）——这一档拦的是
    ///   「块被压缩到低于自己的声明最小宽」这种退化态，**不是**「一定画出厂那三档」：
    ///   真正画哪几行由 `listedScopes` 拿这个数去截**用户当前那一组**的前缀（用户只勾了今年，
    ///   窄块里画的就是今年这一行）。
    static func rowLimit(forWidth width: CGFloat) -> Int {
        guard width.isFinite else { return 1 }
        return width >= allScopesWidth
            ? ProgressCalculator.Scope.allCases.count
            : ProgressCalculator.defaultVisibleScopes.count
    }

    /// **该块高下最多画几行**（高度档）：解 `N × rowHeight + (N−1) × rowSpacing ≤ height`，
    /// 即 `floor((height + rowSpacing) / (rowHeight + rowSpacing))`，钳 `0…5`
    /// （上限 = 尺度总数：再高也没有第 6 行这种东西）。
    ///
    /// 算式与 `TodosHomeBlockLayout.rowCount(fittingHeight:)` 同一条（N 行的总高反过来解 N）。
    /// 非有限高度 → **0**：高度取不到时一行都不画（下一帧就有真值），不拿 NaN 去解行数。
    static func rowLimit(forHeight height: CGFloat) -> Int {
        guard height.isFinite else { return 0 }
        let pitch = rowHeight + rowSpacing
        guard pitch > 0 else { return 0 }
        let fit = Int(((height + rowSpacing) / pitch).rounded(.down))
        return min(max(fit, 0), ProgressCalculator.Scope.allCases.count)
    }

    /// **该块尺寸下要画的尺度**：宽度档与高度档**取小者**得到行数上限，再按传入那一组（= 用户当前
    /// 勾选的解析结果）的**先后**取前 N 个（勾了五档而块只放得下三行时只画前三个，不缩字、不滚动
    /// ——docs/29 §已知限制 3）。**截断取前缀**：传入 `[.quarter, .year]` 就画这两个（不重排成原始顺序）。
    static func listedScopes(
        _ scopes: [ProgressCalculator.Scope],
        forWidth width: CGFloat,
        height: CGFloat
    ) -> [ProgressCalculator.Scope] {
        Array(scopes.prefix(min(rowLimit(forWidth: width), rowLimit(forHeight: height))))
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
/// 尺寸用 `GeometryReader` 读**放置后**的宽高（不是测量）：按 `ProgressHomeBlockLayout` 的两条档位
/// 取小者定行数（见那边的类型注释）。颜色一律显式白色系（面板黑底、系统外观可能浅色，见文件头「颜色」）。
private struct ProgressHomeBlockView: View {
    let scopes: [ProgressCalculator.Scope]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            GeometryReader { proxy in
                let rows = ProgressHomeBlockLayout.listedScopes(
                    scopes,
                    forWidth: proxy.size.width,
                    height: proxy.size.height
                )

                VStack(alignment: .leading, spacing: ProgressHomeBlockLayout.rowSpacing) {
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
/// 与展开行（`ProgressScopeRow`）的差别只有三处：**不画剩余量**、**不画悬停的起止时刻**（窄块里
/// 那两段固定宽度的文字会把进度条挤没，首页块是「一眼看多少」）、**行高与条高都被钉住**
/// （`rowHeight` / `barHeight`，行数算术与画出来的东西因此同源）。
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
                // **标签不截断**（`fixedSize` + `lineLimit(1)`，与展开行的标签同一条口径）：
                // 窄块里被挤的应该是**进度条**（百分比那一段是数的真身），不是尺度名——
                // 少了 `fixedSize` 时 180 宽的英文块会把「This month」显示成「This mo…」。
                .lineLimit(1)
                .fixedSize()

            ProgressView(value: ProgressCalculator.progress(for: scope, now: now))
                .progressViewStyle(.linear)
                .frame(height: ProgressHomeBlockLayout.barHeight)
                .frame(maxWidth: .infinity)

            Text(ProgressText.percent(ProgressCalculator.progress(for: scope, now: now)))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .fixedSize()
        }
        // 行高钉住：高度档算的就是这个数（`.linear` 的进度条默认 20pt 高，不钉住行高就不是 14）。
        .frame(height: ProgressHomeBlockLayout.rowHeight)
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
