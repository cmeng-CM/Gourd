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
//  P1 批次 / T3 增量：卡片下方多一节「首页块顺序」——每个**会出现在首页**的块一行（名称 + 上移 /
//  下移），写 `Defaults[.homeBlockOrder]`。名单是「内置块（按开关）+ 模块块（按 `homeEntries`）」
//  合成的一张表，排序算式与首页 strip **逐字同一条**（`HomeBlockOrdering.sorted`）——
//  这一页显示的顺序就是首页渲染的顺序，不存在第二套口径。
//

import Defaults
import SwiftUI

/// 设置页「组件」卡片页（`SettingsTab.modules` 的 detail）。
struct ModuleSettingsSection: View {
    /// **必须自己观察注册表**：`states` 是 `@Published`，卡片的重绘由它驱动。不观察的话
    /// 开关点完不重绘（`SettingsView` 自己并不观察注册表，它只换 detail 视图）。
    @ObservedObject private var registry = ModuleRegistry.shared

    /// 首页块的用户排序覆盖（P1 / T3）。**用 `@Default` 而不是本地 `@State`**：它是
    /// `DynamicProperty`，写盘即重绘本页（本地状态那一路），首页 strip 读同一个键、同一步重排——
    /// 「先落盘再刷新」因此是**一次写操作**，不存在两份状态对不上的窗口。
    @Default(.homeBlockOrder) private var homeBlockOrder

    /// 内置块的**开关级**门控（这一页只看开关，不看运行期条件，理由见 `orderRows`）。
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.showMirror) private var showMirror

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

            // 顺序节**放在卡片之后**：上面那行提示说「内置块不出现在这里的卡片里」，顺序节却要列出
            // 内置块（它们也能排）——放最后 + 脚注说明「开关在各自的设置项里」，两句话才不会互相打架。
            orderSection
        }
        .navigationTitle(Text(LocalizedStringKey("settings.modules.title")))
    }

    // MARK: 首页块顺序

    /// 顺序行的一项：内置块或模块块（这一页只关心身份 / 名称 / 图标 / 默认序号）。
    private struct OrderRow: Identifiable {
        let id: String
        let name: String
        let symbolName: String
        let defaultOrder: Int
    }

    /// 顺序行的名单：**只列当前会出现在首页的块**——内置块按开关（`showStandardMediaControls` /
    /// `showMirror`），模块块按 `homeEntries`（= 已激活且声明 `home` 的模块）。
    ///
    /// **判据比首页少一档、是刻意的**：首页还叠加运行期条件（音乐要有会话、镜子要在展开态且摄像头
    /// 可用、模块块要 `content(for: .home)` 不答 `.none`）。这一页只用**配置级判据**，否则列表会随
    /// 「有没有在放歌」「面板是不是展开着」抖动，用户刚点的行会跳走。代价：列表里可能出现此刻首页
    /// 看不到的块（音乐没会话时），反之首页也可能画出这里没列的块（模块答 `.none` 的那个不在此列）。
    private var orderRows: [OrderRow] {
        var rows: [OrderRow] = []

        // 内置块的名称沿用它自己的设置项文案（"Music" / "Mirror"）——与用户在设置里认识的词一致，
        // 不另起一套说法。日历块已移除（首页日历走全宽日历行），这里**不生成**它。
        if showStandardMediaControls {
            rows.append(
                OrderRow(
                    id: HomeBlockOrdering.BuiltinBlock.music.id,
                    name: String(localized: "Music"),
                    symbolName: "music.note",
                    defaultOrder: HomeBlockOrdering.BuiltinBlock.music.defaultOrder
                )
            )
        }

        if showMirror {
            rows.append(
                OrderRow(
                    id: HomeBlockOrdering.BuiltinBlock.mirror.id,
                    name: String(localized: "Mirror"),
                    symbolName: "camera",
                    defaultOrder: HomeBlockOrdering.BuiltinBlock.mirror.defaultOrder
                )
            )
        }

        for entry in registry.homeEntries {
            rows.append(
                OrderRow(
                    id: entry.id,
                    name: entry.label,
                    symbolName: entry.symbolName,
                    defaultOrder: entry.order
                )
            )
        }

        return HomeBlockOrdering.sorted(
            rows,
            defaultOrder: { $0.defaultOrder },
            id: { $0.id },
            overrides: homeBlockOrder
        )
    }

    private var orderSection: some View {
        Section {
            if orderRows.isEmpty {
                Text(LocalizedStringKey("settings.modules.order.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(orderRows.enumerated()), id: \.element.id) { index, row in
                    HomeBlockOrderRow(
                        name: row.name,
                        symbolName: row.symbolName,
                        isFirst: index == 0,
                        isLast: index == orderRows.count - 1,
                        moveUp: { move(row, direction: .up) },
                        moveDown: { move(row, direction: .down) }
                    )
                }
            }
        } header: {
            Text(LocalizedStringKey("settings.modules.order.title"))
        } footer: {
            Text(LocalizedStringKey("settings.modules.order.footer"))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 上移 / 下移一行：**先落盘、再刷新**（docs/18 §处理链路）。
    ///
    /// 写的是**整表序号**（口径与理由见 `HomeBlockOrdering.table(for:)`）；名单在点击这一刻现取
    /// （而不是捕获渲染时的那一份），因此「点之前名单刚好变了」（模块被开关）也按最新名单算。
    /// 名单没变（已在顶 / 底，或该行已不在名单里）**不写盘**——用户没表达就不留痕迹。
    private func move(_ row: OrderRow, direction: HomeBlockOrdering.MoveDirection) {
        let ids = orderRows.map(\.id)
        let moved = HomeBlockOrdering.moved(ids, moving: row.id, direction: direction)
        guard moved != ids else { return }
        Defaults[.homeBlockOrder] = HomeBlockOrdering.table(for: moved)
    }
}

// MARK: - 首页块顺序的一行

/// 顺序行：图标 chip + 名称 + 上移 / 下移（与组件卡同一套排版：图标 chip 在左、动作在右、
/// 相同的行内边距；按钮文案沿用既有 `Move Up` / `Move Down` 两条 key，不新增说法）。
private struct HomeBlockOrderRow: View {
    let name: String
    let symbolName: String
    let isFirst: Bool
    let isLast: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ModuleSymbolChip(symbolName: symbolName)

            Text(name)
                .fontWeight(.medium)

            Spacer(minLength: 12)

            Button(action: moveUp) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(isFirst)
            .help(Text(LocalizedStringKey("Move Up")))
            .accessibilityLabel(Text(LocalizedStringKey("Move Up")))

            Button(action: moveDown) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(isLast)
            .help(Text(LocalizedStringKey("Move Down")))
            .accessibilityLabel(Text(LocalizedStringKey("Move Down")))
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 图标 chip

/// 组件卡与顺序行共用的图标 chip（24×24、accent 底的圆角方块）。
///
/// **取不到图标名就不画**（不画占位方框）——这是 `ModuleSettingsCard` 改动前的口径，抽出来共用，
/// 视觉一个像素都没动。
private struct ModuleSymbolChip: View {
    let symbolName: String

    var body: some View {
        if !symbolName.isEmpty {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
        }
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
            ModuleSymbolChip(symbolName: manifest.icon.name ?? "")

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
