/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AtollExtensionKit
import SwiftUI
import Defaults
import AppKit

struct TabModel: Identifiable {
    let id: String
    let label: String
    let icon: String
    let view: NotchViews
    let experienceID: String?
    let accentColor: Color?

    init(label: String, icon: String, view: NotchViews, experienceID: String? = nil, accentColor: Color? = nil) {
        self.id = experienceID.map { "extension-\($0)" } ?? "system-\(view)-\(label)"
        self.label = label
        self.icon = icon
        self.view = view
        self.experienceID = experienceID
        self.accentColor = accentColor
    }
}

// MARK: - 面板条的拼装与排序（p6-ui-polish / T9，docs/30 §做法 机制七 / D-15、D-16）

/// 面板左列三条**宿主 tab** 的排序词汇表：暂存器 / 剪贴板 / 终端——面板上由上游 `Defaults`
/// 直接门控、**不经模块注册表**的三条 tab。`取色器` 刻意不在此列：它渲染在标题栏图标行、
/// 不是面板 tab，因此不进排序名单（docs/30 §明确不做 3 / 备选⑧；它的设置行保持开关-only）。
///
/// **`id` 就是 `panelOrder` 的键**（与模块 tab 的键 = 模块 id 共用同一张表）。三个 id 取现有
/// 词汇、不新造名字：`shelf` / `terminal` 与 `ContentView.selectedPanelTabKey` 给这两个宿主页的
/// 稳定串**同词**（`PanelContentHeight` 账本侧也认）；`clipboard` 是**排序专用键**——它在面板条
/// 上的那条 tab 渲染 `.notes`，账本键因此是 `"notes"`（`"clipboard"` 只对应标题栏图标那条路径）。
///
/// **`defaultOrder` 取负值**：改动前的实际渲染顺序里（`TabSelectionView.tabs` 的拼装），宿主三
/// tab 恒排在一切模块 tab 之前（shelf → clipboard → terminal → 模块段），缺键回落时它们因此必须
/// 排在所有模块（`defaultPlacement.order` 非负）前面。表被写过一次后就是 `0…n-1` 的整表序号
/// （`writeOrderTable` 的口径），这组默认值只在「用户从没排过」时露面。
enum PanelHostTab: String, CaseIterable {
    case shelf
    case clipboard
    case terminal

    var id: String { rawValue }

    /// 该宿主 tab 的门槛键：与 `ModuleSettingsSection.hostPanelRows` 登记的是**同一个键对象**
    /// （用例按 `===` 反查两边一致；真正的读取点是 `TabSelectionView.tabs` 里那次 `slots(...)` 调用）。
    var gateKey: Defaults.Key<Bool> {
        switch self {
        case .shelf: return Defaults.Keys.dynamicShelf
        case .clipboard: return Defaults.Keys.enableClipboardManager
        case .terminal: return Defaults.Keys.enableTerminalFeature
        }
    }

    /// 缺键时的默认序（见类型注释：恒在模块 tab 之前）。
    var defaultOrder: Int {
        switch self {
        case .shelf: return -30
        case .clipboard: return -20
        case .terminal: return -10
        }
    }
}

/// 面板 tab 条的**拼装与排序算式**（p6-ui-polish / T9，docs/30 §做法 机制七）：**唯一一份**，
/// 视图（`TabSelectionView.tabs`）与用例共用——「默认序逐字一致」这条口径因此可判。
///
/// 三条口径（改动前先读）：
///
/// 1. **槽位骨架 = 改动前 `tabs` 的拼装顺序逐字**（`slots(...)`）：Home → 暂存器 → 用量 →
///    剪贴板 → 终端 → 扩展 tab → 模块 tab。每个参数对照改动前的一条分支，门控条件由调用方
///    （视图）在原位判定后传进来——本文件不读偏好。
/// 2. **可排项 = 宿主三 tab + 模块 tab**（`PanelHostTab` / 模块 id），共用 `panelOrder` 这一张表；
///    比较器与 `ModuleRegistry.tabEntries` / 设置页「面板组件」节**同一算式**
///    （`ModuleRegistry.panelRank` → 同值按 id 字典序）。Home / 用量 / 扩展 tab **不可排**：
///    它们不进排序名单（docs/30 §明确不做 3），排序只重排可排项在可排槽位里的先后。
/// 3. **非可排项的槽位索引一个字节不动**（`sequence(...)` 的填法）：表为空时整条 = 改动前逐字；
///    用户改序后，用量 / 扩展 tab 仍停在原来那几个槽位上（只是可排项换了位置）。
///
/// **`@MainActor` 是因为算式本身**：`ModuleRegistry.panelRank` 挂在 `@MainActor` 的注册表上
/// （那才是「唯一算式」的所在，不在这里另抄一份）。两个消费点（`TabSelectionView` 的 `tabs`、
/// `ModuleSettingsSection` 的 `panelSectionRows`）本来就在主 actor 上。
@MainActor
enum PanelTabSequence {

    /// 一格可排项：id（= `panelOrder` 的键）+ 缺键回落的默认序。
    struct Entry: Equatable {
        let id: String
        let defaultOrder: Int
    }

    /// 一条槽位。`isSortable == false` 的槽位（Home / 用量 / 扩展 tab）不参与排序，
    /// 槽位索引固定；`defaultOrder` 对它们没有接收者（记 `Int.max`）。
    struct Slot<Payload> {
        let id: String
        let isSortable: Bool
        let defaultOrder: Int
        let payload: Payload

        /// 不可排槽位（Home / 用量 / 扩展 tab）。
        static func fixed(_ id: String, _ payload: Payload) -> Slot<Payload> {
            Slot(id: id, isSortable: false, defaultOrder: Int.max, payload: payload)
        }

        /// 可排槽位（宿主三 tab / 模块 tab）——`defaultOrder` 是缺键回落值。
        static func sortable(_ id: String, defaultOrder: Int, _ payload: Payload) -> Slot<Payload> {
            Slot(id: id, isSortable: true, defaultOrder: defaultOrder, payload: payload)
        }
    }

    /// 面板条的**槽位骨架**（唯一一份）：顺序 = 改动前 `TabSelectionView.tabs` 逐字——
    /// Home（`enableMinimalisticUI || showStandardMediaControls || showCalendar || showMirror`）→
    /// 暂存器（`dynamicShelf`）→ 用量（`enableLLMUsageFeature`）→ 剪贴板
    /// （`enableClipboardManager && clipboardDisplayMode == .separateTab`）→ 终端（`enableTerminalFeature`）
    /// → 扩展 tab（`enableThirdPartyExtensions && enableExtensionNotchExperiences && enableExtensionNotchTabs`）
    /// → 模块 tab（`ModuleRegistry.tabEntries`，已按面板算式排好）。
    ///
    /// Timer tab / Stats tab 的分支**在改动前就没有**（已由模块投影产出 / 已删除，详见
    /// `TabSelectionView.tabs` 的注释）——计时器与统计今天都在 `modules:` 里出现。
    static func slots<Payload>(
        home: Payload?,
        shelf: Payload?,
        usage: Payload?,
        clipboard: Payload?,
        terminal: Payload?,
        extensions: [(id: String, payload: Payload)],
        modules: [(id: String, defaultOrder: Int, payload: Payload)]
    ) -> [Slot<Payload>] {
        var result: [Slot<Payload>] = []
        if let home { result.append(.fixed("home", home)) }
        if let shelf {
            result.append(.sortable(PanelHostTab.shelf.id, defaultOrder: PanelHostTab.shelf.defaultOrder, shelf))
        }
        if let usage { result.append(.fixed("usage", usage)) }
        if let clipboard {
            result.append(.sortable(PanelHostTab.clipboard.id, defaultOrder: PanelHostTab.clipboard.defaultOrder, clipboard))
        }
        if let terminal {
            result.append(.sortable(PanelHostTab.terminal.id, defaultOrder: PanelHostTab.terminal.defaultOrder, terminal))
        }
        for tab in extensions { result.append(.fixed(tab.id, tab.payload)) }
        for tab in modules {
            result.append(.sortable(tab.id, defaultOrder: tab.defaultOrder, tab.payload))
        }
        return result
    }

    /// 面板排序的**唯一算式**（两个消费点共用：本条的 `sequence(...)` 与设置页「面板组件」节的
    /// 名单 `ModuleSettingsSection.panelMovableIDs`）：用户覆盖 → 默认序 → 同值按 id 字典序，
    /// 转调 `ModuleRegistry.panelRank`（与 `tabEntries` 同一个键函数）；未知 id 在兜底上无效果
    /// （它不在名单里就没有接收者——与 `HomeBlockOrdering` 的「未知 id 不参与排序」同口径）。
    static func orderedIDs(_ entries: [Entry], panelOrder: [String: Int]) -> [String] {
        entries
            .sorted {
                let lhs = ModuleRegistry.panelRank($0.id, defaultOrder: $0.defaultOrder, panelOrder: panelOrder)
                let rhs = ModuleRegistry.panelRank($1.id, defaultOrder: $1.defaultOrder, panelOrder: panelOrder)
                return (lhs, $0.id) < (rhs, $1.id)
            }
            .map(\.id)
    }

    /// 消费点（`TabSelectionView.tabs`）：把**可排槽位**按同一张表重排后取载荷；不可排槽位
    /// 原样留在自己的索引上（口径 3）。表为空 + 骨架 = 改动前顺序时，返回值与改动前逐字一致。
    static func sequence<Payload>(_ slots: [Slot<Payload>], panelOrder: [String: Int]) -> [Payload] {
        let sortable = slots.filter(\.isSortable)
        let ordered = orderedIDs(
            sortable.map { Entry(id: $0.id, defaultOrder: $0.defaultOrder) },
            panelOrder: panelOrder
        )
        var payloadByID: [String: Payload] = [:]
        for slot in sortable { payloadByID[slot.id] = slot.payload }
        var iterator = ordered.makeIterator()
        return slots.map { slot in
            guard slot.isSortable, let id = iterator.next() else { return slot.payload }
            return payloadByID[id] ?? slot.payload
        }
    }
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject private var extensionNotchExperienceManager = ExtensionNotchExperienceManager.shared
    /// 模块注册表（接缝 S1）：**必须观察**——否则注册表变化后 tab 列表不重绘
    /// （与同文件 `extensionNotchExperienceManager` 同理；注册表空时本视图与改动前一致）。
    @ObservedObject private var moduleRegistry = ModuleRegistry.shared
    @StateObject private var quickShareService = QuickShareService.shared
    @Default(.quickShareProvider) private var quickShareProvider
    @State private var showQuickSharePopover = false
    @Default(.enableColorPickerFeature) var enableColorPickerFeature
    @Default(.enableThirdPartyExtensions) private var enableThirdPartyExtensions
    @Default(.enableExtensionNotchExperiences) private var enableExtensionNotchExperiences
    @Default(.enableExtensionNotchTabs) private var enableExtensionNotchTabs
    @Default(.showCalendar) private var showCalendar
    @Default(.showMirror) private var showMirror
    @Default(.showStandardMediaControls) private var showStandardMediaControls
    @Default(.enableMinimalisticUI) private var enableMinimalisticUI
    // **宿主门槛键**（p5-home-blocks / T5）：面板左列的暂存器 / 剪贴板 / 终端三条 tab 由它们直接门控。
    // 用 `@Default` 而不是裸 `Defaults[...]`：设置页「面板组件」节的宿主行拨了开关，本视图必须
    // **当场**重绘（裸读不订阅，得等下一次别的状态变化才轮到它）。名单见文件末尾的 `hostPanelGateKeys`。
    @Default(.dynamicShelf) private var dynamicShelf
    @Default(.enableClipboardManager) private var enableClipboardManager
    /// 备忘录总开关（笔记页里的那个）。用 `@Default` 而不是裸读：拨完必须**当场**让这条 tab
    /// 出现或消失，裸读要等下一次别的状态变化才轮到本视图重绘。
    @Default(.enableNotes) private var enableNotes
    @Default(.enableTerminalFeature) private var enableTerminalFeature
    /// 面板块的用户排序覆盖（p6-ui-polish / T9）：宿主三 tab 与模块 tab 共用**同一张表**
    /// （与设置页「面板组件」节、`ModuleRegistry.tabEntries` 同一个键）。用 `@Default` 而不是裸读：
    /// 设置页拨完 ↑↓ 写盘，本视图必须**当场**重排（这就是「顺序立即跟随」的消费端那一半）。
    @Default(.panelOrder) private var panelOrder
    @Namespace var animation
    
    private var tabs: [TabModel] {
        // **拼装结构收在 `PanelTabSequence.slots(...)`**（p6-ui-polish / T9，唯一一份、用例与视图共用；
        // 改动前的顺序与每个参数的 gate 见那里的注释）。本属性只负责：按当下 gate 造模型、
        // 把注册表投影读出来，然后按同一张 `panelOrder` 表取序（`sequence(...)`）。
        //
        // Timer tab：**已由模块投影产出**（`TimerModule`，docs/20 §做法 机制一）——上游那条
        // 「功能开着 + 显示方式选 tab」的分支已删除，不允许与模块并存（并存就是两个计时器 tab）。
        // 下方 `modules:` 的条目即计时器页。
        //
        // Stats tab：**已删除**（p3-widgets / T2，docs/26 §做法 机制一/机制二）——统计改成
        // **首页块**（`StatsModule`，启用真源不变：上游 `enableStatsFeature`），不再占展开 tab
        // 里的一个位置；`enabledStandardTabCount()` 里对应的 `+1` 同批删除。
        // 允许与模块段并存是不行的：并存就是两个统计入口。
        var extensionSlots: [(id: String, payload: TabModel)] = []
        if extensionTabsEnabled {
            for payload in extensionTabPayloads {
                guard let tab = payload.descriptor.tab else { continue }
                let accent = payload.descriptor.accentColor.swiftUIColor
                let iconName = tab.iconSymbolName ?? "puzzlepiece.extension"
                extensionSlots.append((
                    id: "extension-\(payload.descriptor.id)",
                    payload: TabModel(
                        label: tab.title,
                        icon: iconName,
                        view: .extensionExperience,
                        experienceID: payload.descriptor.id,
                        accentColor: accent
                    )
                ))
            }
        }

        let slots = PanelTabSequence.slots(
            home: homeTabVisible ? TabModel(label: "Home", icon: "house.fill", view: .home) : nil,
            shelf: dynamicShelf ? TabModel(label: "Shelf", icon: "tray.fill", view: .shelf) : nil,
            usage: Defaults[.enableLLMUsageFeature]
                ? TabModel(label: "Usage", icon: "chart.bar.doc.horizontal", view: .llmUsage)
                : nil,
            clipboard: notesOrClipboardTabVisible
                ? TabModel(
                    label: enableNotes ? "Notes" : "Clipboard",
                    icon: enableNotes ? "note.text" : "doc.on.clipboard",
                    view: .notes)
                : nil,
            terminal: enableTerminalFeature
                ? TabModel(label: "Terminal", icon: "apple.terminal", view: .terminal)
                : nil,
            extensions: extensionSlots,
            // 模块内核 tab（接缝 S1）：注册表投影，`experienceID` 复用为模块 id（`TabModel` 的 id
            // 由 experienceID 派生，`ForEach` 零改）。只含 active 且声明 `.expanded` 的模块；
            // 条目已按 `panelRank` 排好，`defaultOrder` 直接取投影的 `order`（同一算式，不重算）。
            modules: ModuleRegistry.shared.tabEntries.map { entry in
                (
                    id: entry.id,
                    defaultOrder: entry.order,
                    payload: TabModel(label: entry.label, icon: entry.symbolName, view: .module, experienceID: entry.id)
                )
            }
        )
        return PanelTabSequence.sequence(slots, panelOrder: panelOrder)
    }

    /// 笔记 / 剪贴板 tab 的可见性（含形态）——**一条 tab，两个来源**（2026-10-08 恢复笔记）：
    /// 上游原本就把备忘录与剪贴板合成一条 tab，由 `NotchNotesView` 自己按 `enableNotes` 决定画哪一半
    /// （两个都开时是「左剪贴板 + 分隔线 + 右笔记」的双栏）。所以这里认两个条件里的任一个：
    ///
    /// - `enableNotes`——备忘录总开关（`SettingsTab.notes` 页里的那个）；
    /// - `enableClipboardManager && clipboardDisplayMode == .separateTab`——剪贴板要独占这条 tab。
    ///
    /// 历史上这条条件曾被改成「只看剪贴板」并固定 label 为 Clipboard（`ad1c55b1`），起因是当时
    /// 笔记设置页被摘掉、`enableNotes` 置 1 的用户会看到一个**无处可关**的 tab。现在设置页回来了
    /// （见 `SettingsView.availableTabs`），那个理由不再成立，故恢复成上游的两来源语义。
    ///
    /// **图标模式（`clipboardDisplayMode != .separateTab` 且笔记关着）下这条 tab 不在面板条上**
    /// （渲染的是标题栏那枚图标，`DynamicIslandHeader`）：`panelOrder` 里 `clipboard` 这个键因此
    /// 没有接收者——它不影响别的项（未知 id 不参与排序），设置页那一行照旧能排（表是整表覆盖）。
    private var notesOrClipboardTabVisible: Bool {
        enableNotes || (enableClipboardManager && Defaults[.clipboardDisplayMode] == .separateTab)
    }
    var body: some View {
        HStack(spacing: 24) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { idx, tab in
                let isSelected = isSelected(tab)
                let activeAccent = tab.accentColor ?? .white

                // Render the tab button
                TabButton(label: tab.label, icon: tab.icon, selected: isSelected) {
                    if tab.view == .extensionExperience {
                        coordinator.selectedExtensionExperienceID = tab.experienceID
                    }
                    if tab.view == .module {
                        // 模块 tab：必须走 selectModule（同时设 selectedModuleID + currentView），
                        // 只设 currentView = .module 会让内容区渲染 EmptyView（接缝 S1 ④）。
                        coordinator.selectModule(tab.experienceID ?? "")
                    }
                    coordinator.currentView = tab.view
                }
                .frame(height: 26)
                .foregroundStyle(isSelected ? activeAccent : .gray)
                .background {
                    if isSelected {
                        Capsule()
                            .fill((tab.accentColor ?? Color(nsColor: .secondarySystemFill)).opacity(0.25))
                            .shadow(color: (tab.accentColor ?? .clear).opacity(0.4), radius: 8)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                            .hidden()
                    }
                }

                
            }
        }
        .clipShape(Capsule())
        .onAppear {
            ensureValidSelection(with: tabs)
        }
    }

    private var extensionTabsEnabled: Bool {
        enableThirdPartyExtensions && enableExtensionNotchExperiences && enableExtensionNotchTabs
    }

    private var extensionTabPayloads: [ExtensionNotchExperiencePayload] {
        extensionNotchExperienceManager.activeExperiences.filter { $0.descriptor.tab != nil }
    }

    private var homeTabVisible: Bool {
        if enableMinimalisticUI {
            return true
        }
        return showStandardMediaControls || showCalendar || showMirror
    }

    private func isSelected(_ tab: TabModel) -> Bool {
        if tab.view == .extensionExperience {
            return coordinator.currentView == .extensionExperience
                && coordinator.selectedExtensionExperienceID == tab.experienceID
        }
        // 模块 tab 与扩展 tab 同理：`currentView` 只表达「在模块视图」，还要比对模块 id
        // 才能区分同一个 `.module` 下的多个 tab（接缝 S1 ③）。
        if tab.view == .module {
            return coordinator.currentView == .module
                && coordinator.selectedModuleID == tab.experienceID
        }
        return coordinator.currentView == tab.view
    }

    private func ensureValidSelection(with tabs: [TabModel]) {
        guard !tabs.isEmpty else { return }
        if tabs.contains(where: { isSelected($0) }) {
            return
        }
        guard let first = tabs.first else { return }
        if first.view == .extensionExperience {
            coordinator.selectedExtensionExperienceID = first.experienceID
        } else {
            coordinator.selectedExtensionExperienceID = nil
        }
        // 模块 tab 落到首位时（其余 tab 全关）与扩展 tab 同构：不带上模块 id 就会渲染 EmptyView
        if first.view == .module {
            coordinator.selectedModuleID = first.experienceID
        }
        coordinator.currentView = first.view
    }
}

// MARK: - 宿主门槛键（设置页「面板组件」节的宿主行反查用）

extension TabSelectionView {
    /// 本视图**真的在读**的宿主门槛键（`docs/29` §机制三的枚举表）：面板左列那三条由上游键
    /// 直接门控的 tab——暂存器 `dynamicShelf`、剪贴板 `enableClipboardManager`、终端
    /// `enableTerminalFeature`。三个读取点就在同文件 `tabs` 里（`@Default` 的观察 + 传给
    /// `PanelTabSequence.slots(...)` 的那个参数，一屏可及）。
    ///
    /// **与 `PanelHostTab.gateKey` 必须是同一批键**（p6 / T9）：那份词汇表给出的 id ↔ gate 键映射
    /// 就是面板条排序用的 id（`shelf` / `clipboard` / `terminal`），两处各写一份就会漂——
    /// 用例按键名把两份钉在一起。
    ///
    /// **这份名单是给用例反查的方向**：设置页「面板组件」节的宿主行表
    /// （`ModuleSettingsSection.hostPanelRows`）登记的键必须落在本名单与
    /// `DynamicIslandHeader.hostPanelGateKeys` 的并集里——方向是「登记的键都真的在用」，
    /// **不是**「用到的全部门槛键都在这里」（用量 tab 的 `enableLLMUsageFeature`、镜子
    /// `showMirror` 等各有归属，见枚举表；删掉任何一条门槛时必须同步改这份名单）。
    ///
    /// **不是 `private`**：用例直接读它（与组件页那几张生产表同一条口径）。
    static let hostPanelGateKeys: [Defaults.Key<Bool>] = [
        .dynamicShelf,
        .enableClipboardManager,
        .enableTerminalFeature,
    ]
}

#Preview {
    DynamicIslandHeader().environmentObject(DynamicIslandViewModel())
}
