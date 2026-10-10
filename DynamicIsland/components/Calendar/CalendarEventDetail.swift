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
//  1. `CalendarEventDetailCard` —— 详情内容卡（纯展示）：色条 + 完整标题（不限行）+ 起止时间
//     （或 `All-day`）+ 地点 + 备注（≤6 行尾部截断）+ 有 `conferenceURL` 时 Join
//     + 「Open in Calendar」按钮（执行旧点击行为 `openURL(event.calendarAppURL())`）。
//  2. `CalendarEventAnchorKey` —— 锚点表：条目 id → 在宿主坐标系里的 bounds（`anchorPreference`
//     上报，`reduce` 合并字典）。
//  3. `CalendarEventDetailsModel` —— 浮层状态（悬停 id / 钉住 id / 锚点表；显示对象 = 钉住优先）。
//  4. `CalendarEventHoverTarget` + `View.calendarEventDetails(model:)` —— 悬停接线（0.3s 延迟）
//     与宿主级修饰符（`overlayPreferenceValue` + 内层 `GeometryReader` 解析锚点、就近定位）。
//
//  **两档命中（防抖动）**：悬停档浮层 `.allowsHitTesting(false)`——鼠标穿透回下面的卡片，
//  否则浮层一出现就吃掉 hover、鼠标「离开卡片」→ 浮层消失 → 又进入卡片，来回抖；
//  钉住档允许命中——`Open in Calendar` / `Join` 按钮可点，且浮层挡住底下的卡片、点击不会穿透成「再点一次换钉住对象」。
//
//  **定位口径**：优先条目**下方**（`y = rect.maxY + 8`）；下方放不下（`rect.maxY + 8 + 200 > bounds.maxY`）
//  翻到**上方**（`y = rect.minY − 8 − 200`）；水平 `x = rect.minX` 夹取到 `[8, bounds.maxX − 8 − width]`；
//  竖直再夹到宿主内。浮层宽 = `min(bounds.width − 24, 320)`。**200 是定位估值高**：详情卡真实高度由
//  内容定（`.fixedSize(horizontal: false, vertical: true)`），这个数只参与「翻上方」与竖直夹取两处决策——
//  偏差只在极端长备注时表现为向下越界半行（备注已限 6 行，实际高约 ≤190pt，估值 200 略保守、不会越界）。
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

/// 条目详情卡（浮层里画的那一张；纯展示，交互（悬停 / 钉住 / 点击穿透）在修饰符与宿主包装层）。
///
/// 形态与条目卡同族（`CalendarEventCards.swift`）：左色条 4pt（同款圆角 2、高 36；详情卡内容更高，
/// 色条按条目卡口径钉 36 作「标记」而不拉满）、正文列间距 10、卡底圆角 14（`.continuous`）。
/// 差异（按内容量）：水平内边距同为 11，垂直取 10（条目卡是 8，备注最多 6 行时上下略松更透气）；
/// 卡底 `white.opacity(0.07)`（比条目卡 0.05 略实——浮层压盖在别的卡片上，要能读出来）
/// + 一圈 `white.opacity(0.08)` 的 1pt 细边（`strokeBorder` 内描边，与卡底同形同界）。
struct CalendarEventDetailCard: View {
    let event: EventModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(event.calendar.color))
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                // 完整标题：**不限行**（不写 `lineLimit` —— 详情浮层存在的理由就是读全文）。
                Text(event.title)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                timeRow

                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.65))
                        .lineLimit(1)
                }

                if let notes = event.notes, !notes.isEmpty {
                    // 备注全部内容：**最多 6 行**、尾部截断（口径来自 docs/36 §接口与数据形状；
                    // 详情卡不做滚动——控制器裁决 1）。
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.75))
                        .lineLimit(6)
                }

                if let conferenceURL = event.conferenceURL {
                    // 直接复用既有 Join 按钮（`DynamicIslandCalendar.swift`，同模块可见）。
                    ConferenceJoinButton(url: conferenceURL, event: event)
                }

                openButton
            }

            Spacer(minLength: 0)
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
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
        } else {
            HStack(spacing: 4) {
                Text(event.start, style: .time)
                    .foregroundColor(.white)
                Text(verbatim: "–")
                    .foregroundColor(Color(white: 0.65))
                Text(event.end, style: .time)
                    .foregroundColor(Color(white: 0.65))
            }
            .font(.caption)
        }
    }

    /// 「Open in Calendar」：执行旧点击行为（打开系统 App——`calendarAppURL()` 里按偏好走
    /// Fantastical / Notion / Apple 日历；提醒条目返回的是提醒事项深链）。**复用既有键**，
    /// 图标沿用 `MinimalisticMusicPlayerView` 里同一动作的 `arrow.up.right.square`。
    private var openButton: some View {
        Button {
            if let url = event.calendarAppURL() {
                openURL(url)
            }
        } label: {
            Label("Open in Calendar", systemImage: "arrow.up.right.square")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.12))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
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

/// 详情浮层状态（一处宿主一份；悬停 id / 钉住 id / 锚点表）。
///
/// 显示对象 = `activeID`（**钉住优先于悬停**）：鼠标从钉住的卡片移开时 `hover(nil)` 只清悬停，
/// 浮层仍因 `pinnedID` 留着；`togglePin` 同 id 再点置 nil（取消钉住）、换 id 覆盖（转移）。
@MainActor
final class CalendarEventDetailsModel: ObservableObject {
    /// 悬停中的条目 id（悬停满 0.3s 后写入；鼠标离开立即清）。
    @Published var hoveredID: String?
    /// 钉住的条目 id（点击切换；与悬停并存时优先）。
    @Published var pinnedID: String?
    /// 条目锚点表：id → 宿主坐标系里的 frame（由宿主经 `GeometryProxy` 解析后写入）。
    ///
    /// 共享修饰符 `.calendarEventDetails(model:)` 自持同一份几何——`overlayPreferenceValue` +
    /// 内层 `GeometryReader` 直接解析当期 `Anchor<CGRect>`（每次布局都是新值，少一次
    /// `@Published` 回写 / 回读往返，滚动时不落后一帧），因此**首页接线不写、不读本表**；
    /// 本表按 docs/36 §接口与数据形状 保留，留给需要跨层读取锚点的宿主
    /// （面板页 T4 的浮层若画在 `List` 行外另做外部分辨，可把解析结果写在这里）。
    @Published var anchors: [String: CGRect] = [:]

    /// 当前显示对象：钉住优先于悬停。
    var activeID: String? { pinnedID ?? hoveredID }

    /// 悬停进入 / 离开（`nil` = 离开当前条目）。
    func hover(_ id: String?) {
        hoveredID = id
    }

    /// 点击钉住 / 取消：同 id 再点置 nil，换 id 覆盖。
    func togglePin(_ id: String) {
        pinnedID = (pinnedID == id) ? nil : id
    }

    /// 归位（宿主销毁 / 收面板 / 切页）：悬停与钉住双清。
    func clear() {
        hoveredID = nil
        pinnedID = nil
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
/// 不必随悬停 / 钉住变化重画。`onDisappear` 里取消在飞的延迟任务（行被拆掉时别再把 hover 写进来）。
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
            }
    }
}

// MARK: - 宿主级修饰符

extension View {
    /// 在内容之上画**一张**详情浮层（就近定位：优先条目下方、空间不足翻上方、水平 / 竖直夹在宿主内）。
    ///
    /// 用法（两处宿主各持一份 `CalendarEventDetailsModel`，挂在**列 / 页面级**——浮层因此不落在
    /// 滚动视口里）：`todayListColumn.calendarEventDetails(model: details)`。
    /// 条目的锚点由卡片侧 `.anchorPreference(key: CalendarEventAnchorKey.self, value: .bounds)` 上报。
    func calendarEventDetails(model: CalendarEventDetailsModel) -> some View {
        overlayPreferenceValue(CalendarEventAnchorKey.self) { anchors in
            CalendarEventDetailsOverlay(model: model, anchors: anchors)
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

    /// 定位估值高（pt）：只参与「下方放不下就翻上方」与竖直夹取两处决策，见文件头「定位口径」。
    private static let estimatedHeight: CGFloat = 200

    var body: some View {
        GeometryReader { proxy in
            if let id = model.activeID,
               let anchor = anchors[id],
               proxy.size.width > 24,
               let event = calendarManager.events.first(where: { $0.id == id }) {
                let rect = proxy[anchor]
                // 浮层宽 = min(宿主宽 − 24, 320)：两侧各留 12 不贴边，上限 320 保阅读行宽。
                let width = min(proxy.size.width - 24, 320)
                let x = min(max(rect.minX, 8), max(8, proxy.size.width - 8 - width))
                let belowY = rect.maxY + 8
                let aboveY = rect.minY - 8 - Self.estimatedHeight
                let flippedY = belowY + Self.estimatedHeight > proxy.size.height ? aboveY : belowY
                let y = min(max(flippedY, 8), max(8, proxy.size.height - 8 - Self.estimatedHeight))

                CalendarEventDetailCard(event: event)
                    .frame(width: width, alignment: .leading)
                    // 真实高度由内容定（备注行数 / 地点有无 / 标题行数）：估值只用于上面的翻转与夹取。
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(x: x, y: y)
                    // 悬停档穿透（鼠标回到条目上，不抖）；钉住档可点（Open in Calendar / Join）。
                    .allowsHitTesting(model.pinnedID != nil)
            }
        }
    }
}
