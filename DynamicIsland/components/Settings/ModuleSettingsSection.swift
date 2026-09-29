//
//  ModuleSettingsSection.swift
//  Gourd 设置页 · 「组件」卡片页（P2 批次 / T5）
//
//  组件（模块）的运行期开关页：**一张卡 = 一个已注册模块（含未启用）**——数据源是注册表的
//  全量 manifest，不是 `tabEntries`（那份只有已激活的；用它会让「关掉的组件从列表里消失」，
//  用户就再也开不回来）。
//
//  **写路径的顺序是定死的**（docs/17 §处理链路）：先把用户选择落到
//  `Defaults[.moduleEnableOverrides]`，再 `await ModuleRegistry.setEnabled(_:for:)` 改内存状态。
//  activate 失败时状态是终态 `failed`、开关回弹——回弹**只把偏好写回 `false`**，绝不再调
//  `setEnabled(false)`：那会把 `failed` 降级成 `.disabled`，等于给 failed 开出一条隐藏的
//  「关一下再打开」重试通道，与 D-13（failed 不可逃逸）矛盾。
//
//  规格：docs/17-nookx-adoption.md §改动点设计 5（卡片页）、§接口与数据形状 3/4（`setEnabled`
//  语义与偏好键语义）、§已知限制 5（内置块不在此页——页面顶部那行说明是它的缓解措施）。
//
//  P2 批次 / T2 增量：卡片在 surfaces 徽标下方多两行说明——「效果 / 出现位置」
//  （`settings.modules.effect.<shortID>`，按模块 id 映射、只覆盖内置三块）与
//  「默认关闭」（`manifest.defaultEnabled == false` 时；`progress` 的形态）。
//  这两行只加文案，不动图标 / 名称 / 摘要 / 徽标 / 开关。
//

import Defaults
import SwiftUI

/// 设置页「组件」卡片页（`SettingsTab.modules` 的 detail）。
struct ModuleSettingsSection: View {
    /// **必须自己观察注册表**：`states` 是 `@Published`，卡片的重绘由它驱动。不观察的话
    /// 开关点完不重绘（`SettingsView` 自己并不观察注册表，它只换 detail 视图）。
    @ObservedObject private var registry = ModuleRegistry.shared

    /// 数据源 = 注册表**全量** manifest（含未启用），按 `id` 升序（docs/17 §改动点设计 5）。
    private var manifests: [ModuleManifest] {
        registry.manifests.values.sorted { $0.id < $1.id }
    }

    var body: some View {
        Form {
            // 「宿主内置块（音乐 / 日历 / 镜子）在各自的设置项里开关」——docs/17 §已知限制 5 的
            // 缓解措施：它们不是模块，由上游 `Defaults` 键门控，因此不在这份名单里。
            Section {
                Text(LocalizedStringKey("settings.modules.builtinHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                ForEach(manifests, id: \.id) { manifest in
                    ModuleSettingsCard(registry: registry, manifest: manifest)
                }
            }
        }
        .navigationTitle(Text(LocalizedStringKey("settings.modules.title")))
    }
}

// MARK: - 卡片

/// 一个组件一张卡：SF Symbol 图标 + 名称 + 摘要 + surfaces 徽标 + 开关。
///
/// 图标与文案的解析顺序与 `ModuleRegistry` 的投影**逐字同序**（名称走 `label(for:)`、
/// 摘要走同一套 key → `table["en"]` 回落）：卡片上显示的必须与展开 tab / 首页块认的是同一份。
private struct ModuleSettingsCard: View {
    @ObservedObject var registry: ModuleRegistry
    let manifest: ModuleManifest

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            symbol

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(ModuleRegistry.label(for: manifest))
                        .fontWeight(.medium)
                    ForEach(manifest.surfaces, id: \.rawValue) { surface in
                        surfaceChip(surface)
                    }
                }

                // 「效果 / 出现位置」——**徽标正下方**的一行（P2 / T2，docs/17 §已知限制 16 同批改判）：
                // 三个组件里只有待办有首页效果，卡片必须自己讲清「开它之后会在哪看到什么」，
                // 否则「打开开关但界面没变化」看起来就是坏的。文案按模块 id 映射（不是通用模板）。
                if let effectKey = Self.effectKey(for: manifest) {
                    Text(LocalizedStringKey(effectKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // `defaultEnabled == false` 的模块另标一行「默认关闭」：它的开关本来就是关的，
                // 而「卡片开着但首页/槽位没效果」是它**默认**的合法形态，不是故障。
                // 判据取 manifest 字段（不写死 id——将来默认关的模块也自动拿到这一行）；
                // `nil`（manifest 没写这个键）不标——缺失不是「默认关闭」的证据。
                if manifest.defaultEnabled == false {
                    Text(LocalizedStringKey("settings.modules.defaultOff"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let summary = Self.summary(for: manifest) {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 失败态只回显**一行**：`failed` 是终态、要恢复只能重启（D-13），
                // 具体原因是调试信息，卡片不放（裁决 2）。
                if isFailed {
                    Text(LocalizedStringKey("settings.modules.failed"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer(minLength: 12)

            Toggle(isOn: toggle) {
                Text(ModuleRegistry.label(for: manifest))
            }
            .labelsHidden()
            .disabled(isFailed)
        }
        .padding(.vertical, 4)
    }

    // MARK: 开关

    /// get：**只读注册表状态**（偏好不是真源，内存状态才是）。
    /// `.active` / `.activating` → on；`.disabled` → off；**`nil`（已注册未判定）也按 off**；
    /// `.failed` → off（并见 `isFailed`：开关同时被禁用）。
    private var isOn: Bool {
        switch registry.states[manifest.id] {
        case .some(.active), .some(.activating): return true
        case .some(.disabled), .some(.failed), .none: return false
        }
    }

    /// `failed` 是终态：开关不可点（06 §3.3 硬性规则 1「不重试」的 UI 面）。
    private var isFailed: Bool {
        if case .some(.failed) = registry.states[manifest.id] { return true }
        return false
    }

    /// set：**先落盘再改内存**（docs/17 §处理链路）。
    private var toggle: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { newValue in
                Self.writeOverride(newValue, for: manifest.id)
                Task {
                    let state = await registry.setEnabled(newValue, for: manifest.id)
                    // 启动失败 → 开关回弹为关：**只把偏好写回 false**，不碰内核状态
                    // （`setEnabled(false)` 会把 failed 降级成 `.disabled`，D-13 禁止）。
                    // 界面刷新不需要额外触发：这一路必然伴随 `states` 的真变化
                    //（`nil` / `.disabled` → 写入 `.failed`），`@Published` 会重绘；
                    // 而「已是 failed」时开关本来就不可点。
                    if case .failed = state {
                        Self.writeOverride(false, for: manifest.id)
                    }
                }
            }
        )
    }

    /// 写 `Defaults[.moduleEnableOverrides]`（整字典读改写，与既有字典型 `Defaults` 写入同形）。
    /// **缺键 = 用户未表达**（回落 manifest）——因此这里只在用户真的动了开关时写键。
    private static func writeOverride(_ enabled: Bool, for id: String) {
        var overrides = Defaults[.moduleEnableOverrides]
        overrides[id] = enabled
        Defaults[.moduleEnableOverrides] = overrides
    }

    // MARK: 呈现

    /// manifest 的图标：取不到就**不画**（不画占位方框）。
    @ViewBuilder
    private var symbol: some View {
        if let name = manifest.icon.name, !name.isEmpty {
            Image(systemName: name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
        }
    }

    /// surfaces 徽标：命中一个取值就一枚小 chip。
    ///
    /// key 用**先拼成 `String` 再构造 `LocalizedStringKey`**：把插值直接写进
    /// `LocalizedStringKey` 字面量会被编译成 `%@` 占位形态的 key，查不到文案。
    private func surfaceChip(_ surface: Surface) -> some View {
        Text(LocalizedStringKey("settings.modules.surface." + surface.rawValue))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }

    /// 「效果 / 出现位置」一行的本地化 key：**按模块 id 逐块映射**，不是通用模板。
    ///
    /// 只覆盖内置三块——这三行写的是**本项目里这三个组件实际的渲染点**（以 manifest 的
    /// `surfaces` 与实际视图为准），不是从 manifest 推导出来的通用句子：
    /// - `todos`：`[.expanded, .compact, .home]` → 折叠态中央槽位 + 首页块 + 展开面板待办页；
    /// - `notifications`：`[.expanded, .compact, .home]` → 折叠态铃铛 + 首页通知块 + 展开面板通知列表
    ///   （另有 HUD：新通知在刘海上短暂浮现，`presentHUD` 那条链，受浮层总开关控制）；
    /// - `progress`：`[.compact, .expanded]`（**无 `home`**）→ 折叠态中央槽位 + 展开面板进度页。
    ///
    /// 未命中（将来注册的第三方模块）返回 nil，**整行不显示**——不猜它出现在哪。
    private static func effectKey(for manifest: ModuleManifest) -> String? {
        switch manifest.id {
        case "com.cmeng.gourd.todos":
            return "settings.modules.effect.todos"
        case "com.cmeng.gourd.notifications":
            return "settings.modules.effect.notifications"
        case "com.cmeng.gourd.progress":
            return "settings.modules.effect.progress"
        default:
            return nil
        }
    }

    /// 摘要的解析顺序与 `ModuleRegistry.label(for:)` **逐字同序**：key 形态查 `Bundle.main`
    /// （查不到时 `Bundle` 原样返回 key，据此判定）、再查 `table["en"]`；两者都取不到则
    /// **整行不显示**——摘要缺失是合法形态（`label` 的 shortID 兜底只属于名称）。
    private static func summary(for manifest: ModuleManifest) -> String? {
        guard let summary = manifest.summary else { return nil }
        if let key = summary.key, !key.isEmpty {
            let localized = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
            if !localized.isEmpty, localized != key { return localized }
        }
        if let english = summary.table?["en"], !english.isEmpty { return english }
        return nil
    }
}
