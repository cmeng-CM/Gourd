// Modified for Gourd (2026-10-10)
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
//  CalendarEventDetail.swift
//  Gourd 日历 · 条目详情浮层（P11 批次 / T3）
//
//  **为什么自绘**：非激活 NSPanel 里系统 `.help()` tooltip 有秒级延迟（docs/21 §已知限制 14），
//  而用户要的是「鼠标停一下就能看到完整标题 / 备注」。本文件因此自绘一张详情卡，由宿主在
//  **面板内**定位（用 `anchorPreference` 上报条目 frame、在宿主坐标系里就近摆放），不碰系统 tooltip。
//
//  **四个部件**（口径见 docs/36-calendar-cards-and-add.md §做法 机制二 / §接口与数据形状）：
//  1. `CalendarEventDetailCard` —— 详情内容卡（纯展示 + 一个回调）：色条 + 完整标题（不限行）+ 起止时间
//     （或 `All-day`）+ 地点 + 备注（≤6 行尾部截断）+ 有 `conferenceURL` 时 Join
//     + 「Open in Calendar」按钮（执行旧点击行为 `openURL(event.calendarAppURL())`）
//     + 钉住档右上角关闭按钮（×，`isPinned` 时才显示；点击回调解钉——见「钉住出口」）。
//  2. `CalendarEventAnchorKey` —— 锚点表：条目 id → 在宿主坐标系里的 bounds（`anchorPreference`
//     上报，`reduce` 合并字典）。
//  3. `CalendarEventDetailsModel` —— 浮层状态（悬停 id / 钉住 id；显示对象 = 钉住优先）。
//  4. `CalendarEventHoverTarget` + `View.calendarEventDetails(model:)` —— 悬停接线（0.3s 延迟）
//     与宿主级修饰符（`overlayPreferenceValue` + 内层 `GeometryReader` 解析锚点、就近定位）。
//
//  **两档命中（防抖动）**：悬停档浮层 `.allowsHitTesting(false)`——鼠标穿透回下面的卡片，
//  否则浮层一出现就吃掉 hover、鼠标「离开卡片」→ 浮层消失 → 又进入卡片，来回抖；
//  钉住档允许命中——`Open in Calendar` / `Join` / 关闭按钮可点，且浮层挡住底下的卡片、点击不会穿透成「再点一次换钉住对象」。
//
//  **钉住出口**：钉住档浮层会压住条目（窄宿主下尤其），「同卡再点取消」因此不一定可点；详情卡右上角的
//  关闭按钮（×）是浮层内的确定出口：`isPinned`（= `model.pinnedID == event.id`）时显示，点击解钉。
//
//  **抑制标志随可渲染性（T8b）**：条目离开当日窗口（换选中日）/ 被偏好过滤隐藏 / 被表单替换的列表
//  带走时锚点消失、浮层不渲染——模型 `isPinRenderable`（钉住**且**锚点仍在）随之落 false，宿主的
//  `vm.isCalendarDetailsPinned` 一并复位；否则标志悬空为 true，面板再也收不起来、× 出口也不可达。
//
//  **定位口径（T3 fix：按实测高）**：条目 rect 由 `Anchor<CGRect>` 解析（宿主坐标），浮层真实高度 h 由
//  卡片自身上报（卡片根视图 `.background(GeometryReader { …preference… })` + `onPreferenceChange`
//  写 `measuredHeight`，初值 120、首帧后修正）；竖向内边距 8，H = 宿主高：
//  - `rect.maxY + 8 + h <= H − 8` → `y = rect.maxY + 8`（放条目**下方**）；
//  - 否则 `rect.minY − 8 − h >= 8` → `y = rect.minY − 8 − h`（翻**上方**）；
//  - 否则 `y = min(max(8, rect.minY), max(8, H − 8 − h))`（贴条目夹取）。
//  水平 `x = rect.minX` 夹取到 `[8, bounds.maxX − 8 − width]`；浮层宽 = `min(bounds.width − 24, 320)`。
//  **兜底裁剪（刻意）**：h 上限 = `H − 16`（`.frame(maxHeight: H − 16, alignment: .top)` + `.clipped()`）——
//  3 周月的宿主只有 160pt、备注 6 行的卡可到约 210pt，不夹就会越出行框被面板下缘裁掉；这里主动裁在
//  浮层自己的框内（顶部对齐、底部裁），越界量因此封顶在浮层里，不再漏到行外。
//
//  历史（T3 首版）：定位曾用固定估值高 200pt 只做翻转 / 夹取决策；独立审查证明首页行宿主高只有
//  160–268pt ⇒ 翻转判据恒真、夹取把 y 恒钉在 8（浮层永远贴在列顶、不贴条目）。T3 fix 改成实测高。
//
//  **浮层内容从哪来**：`CalendarEventAnchorKey` 只带 `Anchor<CGRect>`（锚点即几何，docs/36 的接口
//  形状），不带 `EventModel`；浮层因此按 id 到 `CalendarManager.shared.events`（两处宿主渲染卡片的
//  同一个单日窗口）反查条目。这样两处宿主都只用把 `.calendarEventDetails(model:)` 挂上，不必再传
//  一份「id → 条目」表；条目在钉住期间刷新时浮层还跟着更新。
//
//  说明：本文件不含任何 EventKit 写入；「Open in Calendar」按钮**复用既有本地化键**（`Open in Calendar`，
//  含 zh-Hans），本任务零 `Localizable.xcstrings` 改动（时间行分隔符用 `Text(verbatim:)`，不产生新键）。
//

import SwiftUI

// MARK: - 详情内容卡

/// 条目详情卡（浮层里画的那一张；纯展示 + 一个关闭回调；悬停 / 钉住 / 点击穿透在修饰符与宿主包装层）。
///
/// 形态与条目卡同族（`CalendarEventCards.swift`）：左色条 4pt（同款圆角 2、高 36；详情卡内容更高，
/// 色条按条目卡口径钉 36 作「标记」而不拉满）、正文列间距 10、卡底圆角 14（`.continuous`）。
/// 差异（按内容量）：水平内边距同为 11，垂直取 10（条目卡是 8，备注最多 6 行时上下略松更透气）；
/// 卡底 `white.opacity(0.07)`（比条目卡 0.05 略实——浮层压盖在别的卡片上，要能读出来）
/// + 一圈 `white.opacity(0.08)` 的 1pt 细边（`strokeBorder` 内描边，与卡底同形同界）。
/// 浮层卡片底部的动作集（H2 设计图 / D-20：**图标形态**，文字只在悬停提示与无障碍标签里）。
///
/// 由**宿主**按记录类型填：日程 = 打开系统日历 / 编辑 / 删除；待办 = 打开提醒 / 完成 / 删除
/// （本批不给岛内编辑提醒，D-10）；只读记录只有「打开系统日历」一枚（`canModifyInIsland` 判据，
/// D-12）。`meeting` 有会议信息时给（点 = 打开 / 复制、右键 = 菜单，与列表行同款一枚按钮）。
struct CalendarEventDetailActions {
    var openSystem: (() -> Void)?
    var complete: (() -> Void)?
    var edit: (() -> Void)?
    var delete: (() -> Void)?
    var meeting: (() -> MeetingActionView)?
    /// 就地删除确认（首页浮窗用：那里没有「行下方确认条」可用）。非空时卡片底部换成
    /// 一行确认 + 删除 / 取消（C2 硬规则①「删除必须先确认」在浮窗里也成立）。
    var deleteConfirmation: (onConfirm: () -> Void, onCancel: () -> Void)?

    var isEmpty: Bool {
        openSystem == nil && complete == nil && edit == nil && delete == nil && meeting == nil
    }
}

struct CalendarEventDetailCard: View {
    let event: EventModel
    /// 钉住档标记（T3 fix）：`true` 时右上角出关闭按钮（×）。悬停档整层 `.allowsHitTesting(false)`，
    /// 本来就点不到，这里不再显示按钮。
    let isPinned: Bool
    /// 关闭按钮动作（解钉；由宿主 / 修饰符接到 `model.togglePin(event.id)`）。
    let onClose: () -> Void
    /// 底部动作集（默认空 = 不画动作行）。
    var actions = CalendarEventDetailActions()
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(event.calendar.color))
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                // 完整标题：**不限行**（不写 `lineLimit` —— 详情浮层存在的理由就是读全文）。
                Text(event.title)
                    .font(CalendarPanelTypography.cardTitle)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                timeRow

                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(CalendarPanelTypography.cardSecondary)
                        // p18：改前固定中灰 `Color(white: 0.65)`——浅色 / 中间调玻璃上对比度归零。
                        .foregroundColor(.white.opacity(MonthGridLayout.cardSecondaryOpacity))
                        .lineLimit(1)
                }

                if let notes = event.notes, !notes.isEmpty {
                    // 备注全部内容：**最多 6 行**、尾部截断（口径来自 docs/36 §接口与数据形状；
                    // 详情卡不做滚动——控制器裁决 1）。
                    Text(notes)
                        .font(CalendarPanelTypography.cardSecondary)
                        // p18：改前固定中灰 `Color(white: 0.75)`——备注是正文延伸，取卡片里更靠近主文字的一档。
                        .foregroundColor(.white.opacity(MonthGridLayout.cardSecondaryStrongOpacity))
                        .lineLimit(6)
                }

                if let conferenceURL = event.conferenceURL {
                    // 直接复用既有 Join 按钮（`DynamicIslandCalendar.swift`，同模块可见）。
                    ConferenceJoinButton(url: conferenceURL, event: event)
                }

                actionRow
            }

            Spacer(minLength: 0)

            // 关闭按钮（T3 fix / 钉住出口）：放在 HStack 尾部（顶端对齐、占位而非压盖——标题横排
            // 因此不会钻到按钮底下）。文案复用既有键 `Close`（xcstrings 已含，含 zh-Hans）。
            if isPinned {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        // p18：改前固定中灰 `Color(white: 0.6)`——关闭图标同为次要一档。
                        .foregroundColor(.white.opacity(MonthGridLayout.cardSecondaryOpacity))
                        .contentShape(Rectangle())
                        .padding(2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    /// 时间行：非全天 `start–end`（两段都跟随系统 `.time` 样式——locale / 12-24 时制由系统定），
    /// 全天显示 `All-day`（复用既有本地化键）。分隔符用 `Text(verbatim:)`（不生成新文案键）。
    @ViewBuilder
    private var timeRow: some View {
        if event.isAllDay {
            Text("All-day")
                .font(CalendarPanelTypography.cardSecondary)
                .fontWeight(.medium)
                .foregroundColor(.white)
        } else {
            HStack(spacing: 4) {
                Text(event.start, style: .time)
                    .foregroundColor(.white)
                Text(verbatim: "–")
                    // p18：改前固定中灰 `Color(white: 0.65)`——分隔符与止时间同为次要一档。
                    .foregroundColor(.white.opacity(MonthGridLayout.cardSecondaryOpacity))
                Text(event.end, style: .time)
                    .foregroundColor(.white.opacity(MonthGridLayout.cardSecondaryOpacity))
            }
            .font(CalendarPanelTypography.cardSecondary)
        }
    }

    /// 待办是否已完成（「完成 / 取消完成」那一枚据此换图标与文案）。
    private var reminderIsCompleted: Bool {
        if case .reminder(let completed) = event.type { return completed }
        return false
    }

    /// 底部动作行（H2 / D-20）：图标 + 顶上一道细分隔线；`actions` 为空时整行不画。
    @ViewBuilder
    private var actionRow: some View {
        if let deleteConfirmation = actions.deleteConfirmation {
            Divider().overlay(Color.white.opacity(0.16))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(event.type.isReminder ? "calendar.panel.deleteReminderConsequence"
                                           : "calendar.panel.deleteEventConsequence")
                    .font(CalendarPanelTypography.cardSecondary)
                    .foregroundColor(.white.opacity(MonthGridLayout.cardSecondaryOpacity))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("calendar.panel.delete") { deleteConfirmation.onConfirm() }
                    .font(CalendarPanelTypography.action).foregroundColor(.red)
                    .accessibilityIdentifier("calendar-delete-confirm")
                Button("Cancel") { deleteConfirmation.onCancel() }
                    .font(CalendarPanelTypography.action)
                    .accessibilityIdentifier("calendar-delete-cancel")
            }
            .buttonStyle(.plain)
        } else if !actions.isEmpty {
            Divider().overlay(Color.white.opacity(0.16))
            HStack(spacing: 6) {
                if let meeting = actions.meeting { meeting() }
                iconAction("calendar.panel.openCalendar", systemImage: "arrow.up.right.square", action: actions.openSystem)
                if let complete = actions.complete {
                    iconAction(reminderIsCompleted ? "calendar.panel.markIncomplete" : "calendar.panel.markComplete",
                               systemImage: reminderIsCompleted ? "checkmark.circle.fill" : "circle",
                               action: complete)
                }
                iconAction("calendar.panel.editItem", systemImage: "pencil", action: actions.edit)
                iconAction("calendar.panel.delete", systemImage: "trash", action: actions.delete)
            }
        }
    }

    /// 一枚动作图标：文字只进 `.help` 与无障碍标签（D-20）。`action` 为 nil 时这一枚不画。
    @ViewBuilder
    private func iconAction(_ labelKey: LocalizedStringKey, systemImage: String, action: (() -> Void)?) -> some View {
        if let action {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.16)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text(labelKey))
            .accessibilityLabel(Text(labelKey))
        }
    }
}

// MARK: - 锚点表

/// 条目锚点表：`event.id` → 该条目在宿主坐标系里的 bounds（`anchorPreference(value: .bounds)` 上报）。
///
/// `reduce` 合并字典（后到者覆盖同键——`ForEach` 的 id 唯一，同键不会出现两次）。
struct CalendarEventAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [String: Anchor<CGRect>],
        nextValue: () -> [String: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - 浮层状态

/// 详情浮层状态（一处宿主一份；悬停 id / 钉住 id）。
///
/// 显示对象 = `activeID`（**钉住优先于悬停**）：鼠标从钉住的卡片移开时 `hover(nil)` 只清悬停，
/// 浮层仍因 `pinnedID` 留着；`togglePin` 同 id 再点置 nil（取消钉住）、换 id 覆盖（转移）。
///
/// 说明：本模型**不持锚点表**（T3 fix 删掉无写无读的 `anchors`）——浮层定位走
/// `overlayPreferenceValue` + `GeometryReader` 现场解析 `Anchor<CGRect>`，浮层真实高度由详情卡
/// 经 preference 上报（`CalendarEventDetailHeightKey`），都在修饰符内部闭环，不走模型。
@MainActor
final class CalendarEventDetailsModel: ObservableObject {
    /// 悬停中的条目 id（悬停满 0.3s 后写入；鼠标离开立即清）。
    @Published var hoveredID: String?
    /// 钉住的条目 id（点击切换；与悬停并存时优先）。
    @Published var pinnedID: String?

    /// 钉住档**是否可渲染**（T8b）：`pinnedID != nil` **且**该 id 当前仍在锚点表里。
    ///
    /// **为什么单独成字段**：钉住后条目可能离开当日窗口（换选中日）、被偏好过滤隐藏、或被
    /// 表单替换的列表带走——锚点消失后浮层什么都不画，但 `pinnedID` 还在。宿主的收起抑制标志
    /// 若只看 `pinnedID != nil` 就会悬空为 true（面板再也收不起来、浮层里的 × 出口也不可达）；
    /// 改看本字段，锚点一消失即自动复位。写回只在 `calendarEventDetails(model:)` 的回调里
    /// （锚点表变化 / `pinnedID` 变化各算一次），**不在 body 求值期**改 `@Published`。
    @Published private(set) var isPinRenderable: Bool = false

    /// 当前显示对象：钉住优先于悬停。
    var activeID: String? { pinnedID ?? hoveredID }

    /// 悬停进入 / 离开（`nil` = 离开当前条目）。
    func hover(_ id: String?) {
        hoveredID = id
    }

    /// 某条目被拆掉（行消失）时的收口：**仅当悬停的正是它**才清（避免误清别的条目的悬停态，
    /// 也避免 `onDisappear` 把「此刻悬停在别的卡上」的状态抹掉）。
    func endHover(_ id: String) {
        if hoveredID == id {
            hoveredID = nil
        }
    }

    /// 点击钉住 / 取消：同 id 再点置 nil，换 id 覆盖。
    func togglePin(_ id: String) {
        pinnedID = (pinnedID == id) ? nil : id
    }

    /// 重算 `isPinRenderable`（T8b；由 `calendarEventDetails(model:)` 的两个回调调用）：
    /// `pinnedID != nil` **且**其锚点仍在表里（查不到 → false）。值不变不发布（避免多余重画）。
    func refreshPinRenderable(pinnedAnchorPresent: Bool) {
        let renderable = pinnedID != nil && pinnedAnchorPresent
        if isPinRenderable != renderable {
            isPinRenderable = renderable
        }
    }

    /// 归位（宿主销毁 / 收面板 / 切页）：悬停与钉住双清、可渲染性一并复位（T8b）。
    func clear() {
        hoveredID = nil
        pinnedID = nil
        isPinRenderable = false
    }
}

// MARK: - 悬停目标

/// 条目悬停目标：包一张卡片，悬停满约 0.3s 写 `model.hover(id)`，离开立即取消并 `hover(nil)`。
///
/// 为什么要延迟：用户从卡片上「扫过」不该闪出浮层（docs/36 机制二的「悬停预览」口径）。
/// 离开时**无条件** `hover(nil)`：若这张卡正被钉住，`activeID` 取 `pinnedID`、浮层不受影响
/// （见 `CalendarEventDetailsModel.activeID`）。
///
/// `model` 用普通 `let`（不 `@ObservedObject`）：本视图只**写**模型、不读它的任何已发布状态，
/// 不必随悬停 / 钉住变化重画。`onDisappear` 里取消在飞的延迟任务，并 `endHover(id)` 收口
/// （T3 fix：卡片被拆掉时不再残留悬停 id——只当悬停的正是它才清）。
struct CalendarEventHoverTarget<Content: View>: View {
    let id: String
    let model: CalendarEventDetailsModel
    let content: Content
    @State private var hoverTask: Task<Void, Never>?

    init(id: String, model: CalendarEventDetailsModel, @ViewBuilder content: () -> Content) {
        self.id = id
        self.model = model
        self.content = content()
    }

    var body: some View {
        content
            .onHover { inside in
                hoverTask?.cancel()
                if inside {
                    hoverTask = Task {
                        try? await Task.sleep(for: .seconds(0.3))
                        guard !Task.isCancelled else { return }
                        model.hover(id)
                    }
                } else {
                    model.hover(nil)
                }
            }
            .onDisappear {
                hoverTask?.cancel()
                model.endHover(id)
            }
    }
}

// MARK: - 详情卡高度

/// 详情卡**实测高**上报（浮层内部用；不对外）：`CalendarEventDetailsOverlay` 在卡片根视图上量
/// `proxy.size.height`，定位算法按真实高度决定「下方 / 上方 / 贴条目夹取」（T3 fix：不再用固定估值）。
private struct CalendarEventDetailHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - 宿主级修饰符

extension View {
    /// 在内容之上画**一张**详情浮层（就近定位：优先条目下方、放不下翻上方、否则贴条目夹取；水平夹在宿主内）。
    ///
    /// 用法（两处宿主各持一份 `CalendarEventDetailsModel`，挂在**列 / 页面级**——浮层因此不落在
    /// 滚动视口里）：`todayListColumn.calendarEventDetails(model: details)`。
    /// 条目的锚点由卡片侧 `.anchorPreference(key: CalendarEventAnchorKey.self, value: .bounds)` 上报。
    ///
    /// **钉住可渲染性重算（T8b）**：锚点表一变就按「pinnedID 是否仍有锚点」重算 `isPinRenderable`
    /// （条目离开当日窗口 / 被偏好过滤 / 表单替换列表 → 查不到 → false；宿主据此复位收起抑制标志，
    /// 否则标志悬空、面板再也收不起来）。`pinnedID` 自身的变化由浮层内层那条
    /// `.onChange(of: model.pinnedID)` 用同一口径补算（锚点表在那一刻不一定会变）。
    /// - Parameter lookup: 按 id 取条目。缺省用 `CalendarManager.events`（选中日的单日窗口，面板两侧都用它）。
    ///   **首页必须传自己的那份**：今日带的行来自 `todayEvents` + `store.reminderRecords`，
    ///   里面包含「到期在过去且未完成」这类**不在当日窗口**的条目——缺省查找会找不到、浮层什么都不画
    ///   （用户看到的是「点了没反应」）。
    func calendarEventDetails(model: CalendarEventDetailsModel,
                             actions: @escaping (EventModel) -> CalendarEventDetailActions = { _ in .init() },
                             lookup: ((String) -> EventModel?)? = nil) -> some View {
        overlayPreferenceValue(CalendarEventAnchorKey.self) { anchors in
            CalendarEventDetailsOverlay(model: model, anchors: anchors, actions: actions, lookup: lookup)
        }
        .onPreferenceChange(CalendarEventAnchorKey.self) { anchors in
            model.refreshPinRenderable(
                pinnedAnchorPresent: model.pinnedID.flatMap { anchors[$0] } != nil
            )
        }
    }
}

/// 浮层本体（修饰符内部用；不对外）。
///
/// `GeometryReader` 铺满宿主：把 active 条目的 `Anchor<CGRect>` 解析成宿主坐标 rect，按定位口径
/// 摆放详情卡。无 active 条目（或宿主窄到放不下）时**不渲染任何东西**——通透，不吃鼠标。
private struct CalendarEventDetailsOverlay: View {
    @ObservedObject var model: CalendarEventDetailsModel
    /// 浮层内容按 id 反查条目：两处宿主渲染卡片用的是**同一个**单日窗口（`CalendarManager.shared.events`）。
    @ObservedObject private var calendarManager = CalendarManager.shared
    let anchors: [String: Anchor<CGRect>]
    /// 宿主给的动作集（按记录类型填；本层只透传给卡片）。
    let actions: (EventModel) -> CalendarEventDetailActions
    /// 宿主给的取数兜底（nil = 用 `CalendarManager.shared.events` 的单日窗口）。
    let lookup: ((String) -> EventModel?)?

    /// 详情卡实测高（T3 fix）：初值 120 是保守档（首帧先用它定位），卡片量出真实高后经
    /// `CalendarEventDetailHeightKey` 修正——差的只是一帧，换来「翻转 / 夹取」都按真实高度判。
    @State private var measuredHeight: CGFloat = 120

    var body: some View {
        GeometryReader { proxy in
            let resolve: (String) -> EventModel? = lookup
                ?? { id in calendarManager.events.first { $0.id == id } }
            if let id = model.activeID,
               let anchor = anchors[id],
               proxy.size.width > 24,
               let event = resolve(id) {
                let rect = proxy[anchor]
                let hostHeight = proxy.size.height
                let h = measuredHeight
                // 浮层宽 = min(宿主宽 − 24, 320)：两侧各留 12 不贴边，上限 320 保阅读行宽。
                let width = min(proxy.size.width - 24, 320)
                let x = min(max(rect.minX, 8), max(8, proxy.size.width - 8 - width))
                let belowY = rect.maxY + 8
                let aboveY = rect.minY - 8 - h
                // 竖直定位（三分支；写成闭包立即求值——ViewBuilder 里不能用语句级 if/else 赋值）：
                // ① 下方放得下（按**实测高**判）→ 放条目下方；
                // ② 下方放不下、上方放得下 → 翻上方（按实测高贴条目上缘）；
                // ③ 上下都放不下（宿主比浮层高不了多少）→ 贴条目夹取，不恒钉列顶。
                let y: CGFloat = {
                    if belowY + h <= hostHeight - 8 {
                        return belowY
                    }
                    if aboveY >= 8 {
                        return aboveY
                    }
                    return min(max(8, rect.minY), max(8, hostHeight - 8 - h))
                }()

                CalendarEventDetailCard(
                    event: event,
                    isPinned: model.pinnedID == event.id,
                    onClose: { model.togglePin(event.id) },
                    actions: actions(event)
                )
                .frame(width: width, alignment: .leading)
                // 真实高度由内容定（备注行数 / 地点有无 / 标题行数），先量再定位（见上）。
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { cardProxy in
                        Color.clear.preference(
                            key: CalendarEventDetailHeightKey.self,
                            value: cardProxy.size.height
                        )
                    }
                )
                .onPreferenceChange(CalendarEventDetailHeightKey.self) { newHeight in
                    measuredHeight = newHeight
                }
                // **兜底裁剪（刻意）**：h 上限 = 宿主高 − 16。3 周月宿主只有 160pt、备注 6 行的卡可到
                // 约 210pt——不夹就会越出行框、被面板下缘裁掉；这里顶部对齐、把溢出裁在浮层自己的框内
                // （极端长备注时卡底「Open in Calendar」可能被裁，属刻意的兜底口径）。
                .frame(maxHeight: max(0, hostHeight - 16), alignment: .top)
                .clipped()
                .offset(x: x, y: y)
                // 悬停档穿透（鼠标回到条目上，不抖）；钉住档可点（Open in Calendar / Join / 关闭按钮）。
                .allowsHitTesting(model.pinnedID != nil)
            }
        }
        // **钉住可渲染性补算（T8b）**：`pinnedID` 变化时用本层拿到的锚点表重算一次（锚点表自身的
        // 变化由宿主修饰符的 `onPreferenceChange` 负责——那一刻 `pinnedID` 不一定变）。挂在这一层
        // （GeometryReader 永远在树上，即使当前无可渲染条目）。写回在回调里，不在 body 求值期。
        .onChange(of: model.pinnedID) { _, _ in
            model.refreshPinRenderable(
                pinnedAnchorPresent: model.pinnedID.flatMap { anchors[$0] } != nil
            )
        }
    }
}
