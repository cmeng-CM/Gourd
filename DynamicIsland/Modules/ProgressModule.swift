//
//  ProgressModule.swift
//  Gourd 内置模块 · 日/周/月/季/年进度（P1 批次 / T4）
//
//  P1 的试点模块（D-07）：零私有 API、零依赖，只声明 `expanded` surface——它同时是
//  「新增一个模块 = 实现 `GourdModule` + 往 `KernelBootstrap.builtinModules` 加一行」
//  （验收 A3）里那「一行」的样本。
//
//  文案走 Localizable key（06 §3.3 R5）：`module.progress.name` / `module.progress.summary`。
//  视图内**不含任何非本地化文案**——行首是 SF Symbol 图标，数值是百分比文本。
//

import SwiftUI

/// `style` 配置的取值（09 §5.3：ring / bar / text）。
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
    /// - `surfaces` 只声明 `expanded`（D-07）：compact 槽位本批不做，故不声明；
    /// - `defaultPlacement` 只给 `order`（`slot` 仅在声明 compact 时有意义，故不给）；
    /// - `config` 三项只声明类型与默认值：本批**没有用户可见的配置入口**（docs/13「明确不做」），
    ///   读取侧拿到的恒是这里的 `default`。
    static let manifest = ModuleManifest(
        manifestVersion: 1,
        id: "com.cmeng.gourd.progress",
        name: LocalizedText(key: "module.progress.name"),
        summary: LocalizedText(key: "module.progress.summary"),
        icon: IconSpec(type: "symbol", name: "chart.pie"),
        version: "1.0.0",
        apiVersion: HostInfo.currentAPIVersion,
        kind: "builtin",
        surfaces: [.expanded],
        defaultPlacement: Placement(slot: nil, order: 30),
        defaultEnabled: true,
        permissions: [],
        config: ConfigSchema(
            type: "object",
            properties: [
                "visibleScopes": ConfigNode(
                    type: "list",
                    title: nil,
                    default: .strings(ProgressCalculator.Scope.allCases.map(\.rawValue)),
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

    /// 只在展开面板给内容；`compact` / `lockscreen` 未声明 → `.none`
    ///（06 §3.2 的「该 surface 此刻无内容」：不占位、也不算失败）。
    ///
    /// 配置在**每次请求时重读**：宿主 `requestRedraw()` 触发重算时，视图拿到的是新的
    /// `visibleScopes` / `style`（本批没有配置入口，读到的是 manifest 默认值）。
    func content(for request: ContentRequest) -> ModuleContent {
        guard request.surface == .expanded else { return .none }
        return .view(AnyView(ProgressModuleView(scopes: scopes, style: style)))
    }

    // MARK: - 配置读取

    /// `visibleScopes`（list<string>）：解析不出任何已知尺度时回落到**全部五种**——
    /// 配置被改坏不该让面板空白（07 §2 规则 4 的「回落默认值、不崩」口径）。
    /// 去重是为 `ForEach(id: \.self)`：重复 id 会让 SwiftUI 少渲染行。
    private var scopes: [ProgressCalculator.Scope] {
        let declared = (context.config.get("visibleScopes", as: [String].self) ?? [])
            .compactMap(ProgressCalculator.Scope.init(rawValue:))
        var seen: Set<ProgressCalculator.Scope> = []
        let unique = declared.filter { seen.insert($0).inserted }
        return unique.isEmpty ? ProgressCalculator.Scope.allCases : unique
    }

    /// `style`（enum ring|bar|text）：未知取值回落 `ring`。
    private var style: ProgressStyle {
        context.config.get("style", as: String.self).flatMap(ProgressStyle.init(rawValue:)) ?? .ring
    }
}

// MARK: - 展开面板视图

/// 展开面板里的 progress 内容：五个进度 + 百分比文本，按分钟重算。
///
/// 刷新粒度是**粗粒度**的 60s（docs/13「已知限制」14）：日进度 1 分钟粒度足够，
/// 周/月/季/年统一按 60s 重算（成本可忽略），也**未监听 `NSSystemClockDidChange`**
/// ——系统的时钟 / 时区变更最多 60s 内被感知，超过 60s 的跳变在下一个周期校正。
private struct ProgressModuleView: View {
    let scopes: [ProgressCalculator.Scope]
    let style: ProgressStyle

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            VStack(alignment: .leading, spacing: 8) {
                ForEach(scopes, id: \.self) { scope in
                    ProgressRow(
                        scope: scope,
                        // 日历**在渲染时**才取 `.autoupdatingCurrent`（09 §5.3 的默认参数）：
                        // 用户改系统时间 / 时区后，最迟下一个刷新周期就跟上，不留住旧日历。
                        progress: ProgressCalculator.progress(for: scope, now: timeline.date),
                        style: style
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// 单行：尺度图标 + 进度指示 + 百分比文本。行内没有需要本地化的文案（R5）——
/// 尺度由图标表达，数值是百分比。
private struct ProgressRow: View {
    let scope: ProgressCalculator.Scope
    let progress: Double
    let style: ProgressStyle

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: scope.symbolName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            indicator

            Spacer(minLength: 8)

            Text(percentText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var indicator: some View {
        switch style {
        case .ring:
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
        case .bar:
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .frame(width: 120)
        case .text:
            EmptyView()
        }
    }

    /// 走 `Text(_: String)` 的 verbatim 重载（不是 `LocalizedStringKey`），
    /// 因此不会去 Localizable 里查 `%lld%%` 这类 key。
    private var percentText: String {
        "\(Int((progress * 100).rounded()))%"
    }
}

extension ProgressCalculator.Scope {
    /// 行首图标。纯观感，不参与计算；单测对系统符号表逐个校验可用性
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
}
