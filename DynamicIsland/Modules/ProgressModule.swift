//
//  ProgressModule.swift
//  Gourd 内置模块 · 日/周/月/季/年进度（P1 批次 / T4）
//
//  P1 的试点模块（D-07）：零私有 API、零依赖——它同时是「新增一个模块 = 实现
//  `GourdModule` + 往 `KernelBootstrap.builtinModules` 加一行」（验收 A3）里那「一行」的样本。
//
//  **形态定稿（2026-09-27 用户反馈后重做，09 §5.3 呈现行）**：
//  - 折叠态（`compact` / `slot == .center`）= 中央槽位常驻**最关心的一个尺度**的百分比；
//  - 展开态（`expanded`）= **剩余量清单**：一行一个尺度（图标 + 标签 + 细进度条 + 剩余量 + 百分比），
//    默认只显示 **日 + 年**（`visibleScopes` 默认值，可配；解析见 `ProgressCalculator.resolveScopes`）。
//  旧的三态排版（等权五环 / 条形 / 纯文本）已不再使用：`style` 配置项**保留**（契约不变），
//  但本版**只实现清单这一种形态**，`ring` / `bar` / `text` 取值一律按清单渲染。
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
    /// - `surfaces`：`expanded`（展开面板一页剩余量清单）+ `compact`（折叠态中央槽位）；
    /// - `defaultPlacement`：`slot == .center`（折叠态槽位的归属，06 §6.2）、`order == 30`
    ///   （既排 tab、也排槽位，同序按 id 字典序；槽位只取 `compactEntries` 的第一个）；
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
        surfaces: [.compact, .expanded],
        defaultPlacement: Placement(slot: .center, order: 30),
        defaultEnabled: true,
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

    /// 无副作用（视图与计算都在 `content(for:)` 里按需取），因此只有一条激活日志。
    func activate() async throws {
        context.logger.info("progress 模块已激活（scopes=\(scopes.map(\.rawValue).joined(separator: ","))）")
    }

    func deactivate() async {}

    /// 两个 surface 各给一份内容；未声明的 `lockscreen` 返回 `.none`
    ///（06 §3.2 的「该 surface 此刻无内容」：不占位、也不算失败）。
    ///
    /// 配置在**每次请求时重读**：宿主 `requestRedraw()` 触发重算时，视图拿到的是新的
    /// `visibleScopes`（本批没有配置入口，读到的是 manifest 默认值）。
    func content(for request: ContentRequest) -> ModuleContent {
        switch request.surface {
        case .compact:
            return .view(AnyView(ProgressCompactView(scopes: scopes)))
        case .expanded:
            return .view(AnyView(ProgressModuleView(scopes: scopes)))
        case .lockscreen:
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

// MARK: - 展开面板视图（剩余量清单）

/// 展开面板里的 progress 内容：**剩余量清单**——一行一个尺度，主信息是「还剩多久」。
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

// MARK: - 折叠态中央槽位视图

/// 折叠态中央槽位的内容：尺度图标 + 百分比，尺度取 `visibleScopes` 的第一个（默认「今天」）。
///
/// 常驻在关闭态的刘海中央，所以**自带 60s 的 `TimelineView`**：宿主不会为这一格起定时器，
/// 没有它百分比会一直停在视图构造时的值（与展开面板同一粒度，见 docs/13「已知限制」14）。
///
/// 关闭态的槽位尺寸极窄，因此只有 11pt 图标 + 13pt 数值（`HStack(spacing: 5)`），
/// 不显示标签文案——尺度靠图标区分，最关心的那个由 `visibleScopes` 的首项决定。
private struct ProgressCompactView: View {
    let scopes: [ProgressCalculator.Scope]

    private var scope: ProgressCalculator.Scope { scopes.first ?? .day }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            HStack(spacing: 5) {
                Image(systemName: scope.symbolName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)

                Text(ProgressText.percent(ProgressCalculator.progress(for: scope, now: timeline.date)))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
    }
}

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
