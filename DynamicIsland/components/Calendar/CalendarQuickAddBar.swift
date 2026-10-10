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
//  CalendarQuickAddBar.swift
//  Gourd 日历 · 「+」内联新增表单与入口按钮（P11 批次 / T6）
//
//  **是什么**：两处日历（首页整宽日历行的右栏 / 展开面板「日历」页右栏）共用的**新增表单**——
//  给**选中日**加一条待办（写系统「提醒事项」）或一条日程（写系统「日历」，含起止、全天与目标日历），
//  外加两处「+」入口共用的按钮 `CalendarQuickAddButton`（首页行日期头右端 / 面板页右栏顶部行）。
//
//  **形态与口径来源**：docs/36-calendar-cards-and-add.md §做法 机制三、§接口与数据形状·表单与入口，
//  决策 D-03（提醒 + 日程一起做）、D-04（两处都放「+」）、D-05（轻量 `HH:mm` 文本框，**不引
//  `DatePicker`**——非激活面板的弹层与键盘焦点是项目刻意绕开的坑，口径同 `TodosModule` 文件头）、
//  D-07（一个「+」+ 内联表单，待办 / 日程二选一、默认待办、日期 = 选中日）、D-08（待办只有日期；
//  日程默认 09:00–10:00、选中日=今天时取下一个整点）、D-12（「+」常显；未授权档禁用并给
//  「Request Access」/「Open System Settings」，判据**实时读 EventKit**）。
//
//  **日期一律 = 月历选中日**（D-07）：表单**不放**日期输入，只把选中日显示在首行右端（改日期点月历）。
//  起止的默认值与宽松解析、全天区间、待办到期组件全部走 T5 的纯函数 `CalendarQuickAdd`
//  （`CalendarQuickAdd.swift`）——本文件只做「取词 → 调 `CalendarManager` → 回显」。
//
//  **焦点**：表单出现即聚焦标题（口径照 `TodosModule` 的 composer：`@FocusState` + 出现时置位；
//  那边是 `onChange(of: isComposing)`，本组件由宿主以 `if isComposing` **整块创建**，所以是
//  `onAppear`——与 `NotchNotesView` 编辑器同一条现成写法）。
//
//  **提交链路**：`CalendarManager.createReminder(title:due:)` / `createEvent(title:start:end:isAllDay:calendarID:)`
//  （T5）——写成功后管理器内部**显式刷新**三处数据面（按日窗口 / 锁屏 / 按月快照），两处日历因此
//  立刻能看到新条目；这里成功 → 清空 + `onDismiss()`，失败 → 保留表单 + 末行一行红字
//  （细节由服务层 `print`，本文件不重复记账）。
//
//  **未授权档（D-12）**：内容区（标题 / 起止 / 全天 / 目标日历）禁用并降档，**末行确认按钮位**
//  改显引导按钮——`.notDetermined` → 「Request Access」（点击才请求系统授权，口径同待办模块）、
//  `.denied` / `.restricted` → 「Open System Settings」（按被拒的**档**给对应隐私面板）。
//  档位选择器**始终可切**：两档都没授权时，切档才看得到各自的引导。判据用
//  `calendarManager.liveReminderAuthorization` / `liveCalendarAuthorization`（**直读 EventKit**）——
//  `@Published` 的授权状态冷启动恒 `.notDetermined`（见 `CalendarManager` 里那两个 accessor 的注释），
//  不能当门控；直读不参与 SwiftUI 依赖追踪，所以请求返回后靠本地状态 `accessRefreshToken` toggle
//  一次逼 body 重算。
//
//  **高度**：本组件**不给自身设高度**（列宽内的自然高，约 126pt 上下）——首页行由 `HomeCalendarRow`
//  按列表区高度（`todayListHeight`）钉并裁，面板页由 `StandaloneCalendarView` 的右栏（`monthGridHeight`
//  框架内）承担：两处的行高 / 自然高因此都不因表单而变。
//
//  文案键：本批新增 7 个（`calendar.quickAdd.*`，见 `Localizable.xcstrings`）；确认 / 取消 / 授权两键
//  复用既有条目（`module.todos.add` / `Cancel` / `Request Access` / `Open System Settings`），
//  全天复用 `All-day`——不为同一文案造重复键。
//

import AppKit
import EventKit
import SwiftUI

extension CalendarQuickAdd {
    /// 表单的**档位**（待办 / 日程）——docs/36 §接口与数据形状 把这条记在 `CalendarQuickAdd.AddKind`。
    ///
    /// **为什么以扩展落在这里**：T5 的 `CalendarQuickAdd.swift` 只落了六条纯函数（该文件属 T5 产物、
    /// 本任务不可改），档位类型因此在表单自己的文件里以扩展落回**同一个类型**——调用点写
    /// `CalendarQuickAdd.AddKind`，与文档逐字一致（T8 回写时把这条对齐记进 §接口与数据形状）。
    /// 形态与文档一致：`String` raw、`CaseIterable`、默认档 `.reminder`（D-07）。
    enum AddKind: String, CaseIterable {
        case reminder
        case event
    }
}

/// 两处「+」入口共用的按钮（首页行日期头 / 面板页右栏顶部行）——形态只有这一份。
///
/// 常显、**不看授权**（D-12：冷启动授权状态读不到，按它决定显示会两处都不可见、无从发现）；
/// 表单展开期间同样是 plus，再点一次收起（`isComposing.toggle()`，收起动作由宿主给）。圆底
/// 直径 20pt，与 `TodosModule` 看板头那颗「+」同一形态（面板内自绘，不引系统按钮外观）。
struct CalendarQuickAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey("calendar.quickAdd.addNew")))
    }
}

/// 两处日历共用的**内联新增表单**（P11 / T6；整块由宿主以 `if isComposing` 创建 / 销毁）。
///
/// `selectedDate` 是月历的选中日（日期一律取它、只显示不编辑）；`onDismiss` 由宿主闭包负责
/// 把表单收回去（成功提交与取消都走它）。内部状态全为私有，宿主不需要知道表单里有什么。
struct CalendarQuickAddBar: View {
    /// 目标日期（月历选中日）：待办写它那一整天，日程写它那一整天里的起止时刻。
    let selectedDate: Date
    /// 收起表单（成功提交 / 取消 / 再点「+」都由宿主置 `isComposing = false`）。
    var onDismiss: () -> Void

    @ObservedObject private var calendarManager = CalendarManager.shared

    /// 待办 / 日程（默认待办，D-07）。
    @State private var kind: CalendarQuickAdd.AddKind = .reminder
    /// 标题草稿。
    @State private var title = ""
    /// 日程档的开始 / 结束时间文本（初值 = 默认时段，`HH:mm` 形态；解析走 `CalendarQuickAdd.parseTime`）。
    @State private var startText: String
    @State private var endText: String
    /// 全天开关（勾上时两个时间框禁用、提交走 `CalendarQuickAdd.allDayRange`）。
    @State private var isAllDay = false
    /// 目标日历 id（懒初始化：`creatableEventCalendars()` 是 async，`task` 里取一次并设默认）。
    @State private var calendarID: String?
    /// 可写日程日历（菜单数据源；空 = 没有可写日历，不渲染菜单，提交会走服务层兜底并失败回显）。
    @State private var availableCalendars: [CalendarModel] = []
    /// 写入失败（末行一行红字；表单保留——不丢用户敲的字与时间）。
    @State private var writeFailed = false
    /// 提交中（内容区与确认按钮禁用）。
    @State private var isSubmitting = false
    /// 授权状态重读令牌（见 `authorizationStatus` 的注释：直读 EventKit 不参与依赖追踪，
    /// 请求返回后 toggle 一次逼 body 重算）。
    @State private var accessRefreshToken = false
    /// 标题焦点（出现即聚焦，口径见文件头）。
    @FocusState private var titleFocused: Bool

    /// 自定 init 只为一件事：起止文本框的**初值**要按 `selectedDate` 算
    /// （`CalendarQuickAdd.defaultStart/defaultEnd`，选中日=今天时取下一个整点、否则 09:00–10:00）。
    init(selectedDate: Date, onDismiss: @escaping () -> Void) {
        self.selectedDate = selectedDate
        self.onDismiss = onDismiss

        let start = CalendarQuickAdd.defaultStart(on: selectedDate, now: Date(), calendar: .current)
        let end = CalendarQuickAdd.defaultEnd(start: start)
        _startText = State(initialValue: Self.timeText(start, calendar: .current))
        _endText = State(initialValue: Self.timeText(end, calendar: .current))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 首行：档位二选一 + 目标日期（只显示）。
            kindRow
            // 内容区：标题 + 日程档专属行（起止 / 全天 / 目标日历）。
            contentRows
            // 末行：确认 / 取消 / 未授权引导 / 失败红字。
            bottomRow
        }
        .task {
            // 目标日历懒初始化（裁决 4）：`creatableEventCalendars()` 是 async，出现时取一次；
            // `preferredEventCalendarID` 兜第一个可写日历（都没有 → nil，提交走服务层同一套兜底）。
            await loadCalendars()
        }
        .onAppear {
            // 出现即聚焦标题（口径照 `TodosModule` composer / `NotchNotesView`）。
            titleFocused = true
        }
    }

    // MARK: - 行

    /// 第一行：待办 / 日程（`.segmented`）+ 目标日期标签。
    ///
    /// 档位选择器**不参与**内容区禁用——未授权时也要能切档看到「Request Access」/「Open System
    /// Settings」分别是为哪一档准备的（D-12 的形态要求）。
    private var kindRow: some View {
        HStack(spacing: 6) {
            Picker("", selection: $kind) {
                Text(LocalizedStringKey("calendar.quickAdd.kindReminder"))
                    .tag(CalendarQuickAdd.AddKind.reminder)
                Text(LocalizedStringKey("calendar.quickAdd.kindEvent"))
                    .tag(CalendarQuickAdd.AddKind.event)
            }
            .pickerStyle(.segmented)
            .frame(width: 116)
            .controlSize(.mini)
            .disabled(isSubmitting)

            Spacer(minLength: 4)

            // 目标日期：说明这条会写到哪一天（日期一律 = 月历选中日，改日期点月历——D-07）。
            Text(selectedDate.formatted(.dateTime.month(.abbreviated).day()))
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.65))
                .lineLimit(1)
        }
    }

    /// 内容区：标题 + （日程档）起止 / 全天 / 目标日历；未授权 / 提交中整块禁用并降档。
    private var contentRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(LocalizedStringKey("calendar.quickAdd.title"), text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .focused($titleFocused)
                .onSubmit { submit() }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)))
                .disabled(contentDisabled)

            if kind == .event {
                timeRow
                calendarRow
            }
        }
        .opacity(contentDisabled ? 0.45 : 1)
    }

    /// 日程档专属行：开始 / 结束 `HH:mm` 文本框（各 52pt）+「全天」开关。
    ///
    /// 时间框的标签（`calendar.quickAdd.start` / `.end`）走 `TextField` 的 prompt——两个 52pt 的窄框
    /// 前再排队列标签会在首页右栏（约 214pt 可用宽）挤掉「全天」开关；prompt 同时是辅助功能标签。
    private var timeRow: some View {
        HStack(spacing: 6) {
            timeField(LocalizedStringKey("calendar.quickAdd.start"), text: $startText)
            timeField(LocalizedStringKey("calendar.quickAdd.end"), text: $endText)

            Spacer(minLength: 4)

            Toggle(isOn: $isAllDay) {
                Text("All-day")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(contentDisabled)
        }
    }

    /// 单个时间文本框（`.monospacedDigit()` 让数字滚动不抖；全天档禁用）。
    private func timeField(_ label: LocalizedStringKey, text: Binding<String>) -> some View {
        TextField(label, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 11).monospacedDigit())
            .multilineTextAlignment(.center)
            .frame(width: 52)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)))
            // 全天勾上时起止无意义（提交走当天 00:00 → 次日 00:00 的口径）。
            .disabled(isAllDay || contentDisabled)
    }

    /// 日程档专属行：目标日历菜单（只列**可写**日历；按账户分组、条目带日历色圆点）。
    ///
    /// 没有可写日历（全是订阅 / 只读）时不渲染这一行——提交会落到服务层的同一套兜底并失败，
    /// 由末行红字回显（docs/36 §验收标准 2 的「失败路径」）。
    @ViewBuilder
    private var calendarRow: some View {
        if let currentCalendar {
            Menu {
                ForEach(calendarGroups) { group in
                    Section {
                        ForEach(group.calendars) { calendar in
                            Button {
                                calendarID = calendar.id
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(nsColor: calendar.color))
                                        .frame(width: 8, height: 8)
                                    Text(calendar.title)
                                }
                            }
                        }
                    } header: {
                        // 账户名是用户数据（iCloud / 本地…），`verbatim` 不做本地化查表。
                        Text(verbatim: group.accountName)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(nsColor: currentCalendar.color))
                        .frame(width: 8, height: 8)
                    Text(currentCalendar.title)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.6))
                }
                .foregroundColor(.white.opacity(0.85))
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .disabled(contentDisabled)
        }
    }

    /// 末行：确认 + 取消（未授权时确认位改显引导按钮）+ 失败红字。
    ///
    /// 未授权档把引导按钮**放在这一行**（不另起一行）：表单要能整条塞进列表区（≈130pt，
    /// 首页 3 周月的右栏只有约 134pt），另起一行会溢出；内容区已按 D-12 禁用降档，
    /// 「Request Access」/「Open System Settings」就是这一行里唯一可点的动作。
    private var bottomRow: some View {
        HStack(spacing: 8) {
            if isAuthorized {
                Button(action: submit) {
                    Text(LocalizedStringKey("module.todos.add"))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canSubmit)
            } else {
                permissionButton
            }

            Button(action: cancel) {
                Text(LocalizedStringKey("Cancel"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer(minLength: 4)

            if writeFailed {
                Text(LocalizedStringKey("calendar.quickAdd.failed"))
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    /// 未授权档的引导按钮（D-12）：未问过 → 请求系统授权（**点击才请求**，口径同待办模块）；
    /// 被拒 / 受限 → 打开对应隐私面板。
    @ViewBuilder
    private var permissionButton: some View {
        switch authorizationStatus {
        case .notDetermined:
            Button(action: requestAccess) {
                Text("Request Access")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        case .denied, .restricted:
            Button(action: openPrivacySettings) {
                Text("Open System Settings")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        default:
            // 可写档（`.authorized` / `.fullAccess` / `.writeOnly`）不会走到这里（`isAuthorized` 为真）。
            EmptyView()
        }
    }

    // MARK: - 校验与授权

    /// 内容区（标题 / 起止 / 全天 / 目标日历）的禁用判据：未授权或提交中。
    private var contentDisabled: Bool {
        !isAuthorized || isSubmitting
    }

    /// 起止文本框的解析结果（宽松解析走 T5 的 `CalendarQuickAdd.parseTime`：`15:30` / `1530` / `9:5`
    /// 都收、越界 / 空 / 非数字为 `nil`）——都落在**选中日**上（时分为界内，不可能滚到次日）。
    private var parsedStart: Date? {
        CalendarQuickAdd.parseTime(startText, on: selectedDate, calendar: .current)
    }

    private var parsedEnd: Date? {
        CalendarQuickAdd.parseTime(endText, on: selectedDate, calendar: .current)
    }

    /// 确认按钮可用判据：授权可写、不在提交中、标题 trim 后非空、日程档时间合法。
    private var canSubmit: Bool {
        guard isAuthorized, !isSubmitting else { return false }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch kind {
        case .reminder:
            return true
        case .event:
            guard !isAllDay else { return true }
            guard let start = parsedStart, let end = parsedEnd else { return false }
            return CalendarQuickAdd.isValidRange(start: start, end: end, calendar: .current)
        }
    }

    /// 当前档的**实时**授权状态（D-12 的判据来源）。
    ///
    /// `live*Authorization` 是直读 `EKEventStore.authorizationStatus` 的普通属性，**不参与**
    /// SwiftUI 的依赖追踪——请求授权（TCC 弹窗）返回后状态可能已变，但没有任何 `@Published`
    /// 会推一次重渲。读一下 `accessRefreshToken` 让本计算属性依赖它：请求完成后 toggle 那个
    /// 本地状态即逼 body 重算、把新状态读进来（不再需要冷启动不可信的 `@Published` 状态）。
    private var authorizationStatus: EKAuthorizationStatus {
        _ = accessRefreshToken
        return kind == .reminder
            ? calendarManager.liveReminderAuthorization
            : calendarManager.liveCalendarAuthorization
    }

    /// 当前档能不能写。`.writeOnly` 算可写：macOS 的写档允许**新建**事件（本表单只写不读，
    /// 读不到新条目是 `.writeOnly` 本身的口径，不该把表单关上）。
    private var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .fullAccess, .writeOnly:
            return true
        default:
            return false
        }
    }

    // MARK: - 目标日历

    /// 可写日程日历（懒初始化，只取一次；`preferredEventCalendarID` **兜第一个**可写日历）。
    ///
    /// **目标日历归一（T8b）**：`calendarID` 必须落在**可写集合**里——`preferredEventCalendarID`
    /// 可能预选到「默认新事件日历」而它并不可写（菜单里根本没有这一项），会造成「菜单显示 A、
    /// 提交写 B」的错配；装载后不在集合里就退第一个可写（没有可写日历 → nil，提交走服务层
    /// 同一套兜底并失败回显）。
    private func loadCalendars() async {
        let calendars = await calendarManager.creatableEventCalendars()
        availableCalendars = calendars
        if calendarID == nil {
            calendarID = calendarManager.preferredEventCalendarID
        }
        if let current = calendarID, !calendars.contains(where: { $0.id == current }) {
            calendarID = calendars.first?.id
        }
    }

    /// 菜单按钮显示的当前目标日历（未预设 / id 失配时兜第一个可写日历）。
    private var currentCalendar: CalendarModel? {
        availableCalendars.first { $0.id == calendarID } ?? availableCalendars.first
    }

    /// 菜单的账户分组（按 `accountName` 排序，分组内保持服务层给的顺序）。
    private var calendarGroups: [CalendarQuickAddGroup] {
        Dictionary(grouping: availableCalendars, by: \.accountName)
            .sorted { $0.key < $1.key }
            .map { CalendarQuickAddGroup(accountName: $0.key, calendars: $0.value) }
    }

    /// 建（异步）：目标日历 / 全天区间 / 校验全部走 `CalendarManager` 与 `CalendarQuickAdd` 的口径，
    /// 本方法只负责「选哪条链路」。`title` 已在调用方 trim 过。
    private func create(kind: CalendarQuickAdd.AddKind, title: String) async -> Bool {
        switch kind {
        case .reminder:
            return await calendarManager.createReminder(title: title, due: selectedDate)
        case .event:
            if isAllDay {
                let range = CalendarQuickAdd.allDayRange(on: selectedDate, calendar: .current)
                return await calendarManager.createEvent(
                    title: title,
                    start: range.start,
                    end: range.end,
                    isAllDay: true,
                    calendarID: calendarID
                )
            }
            guard let start = parsedStart, let end = parsedEnd else { return false }
            return await calendarManager.createEvent(
                title: title,
                start: start,
                end: end,
                isAllDay: false,
                calendarID: calendarID
            )
        }
    }

    // MARK: - 动作

    /// 提交：成功 → 清空 + 收起；失败 → 表单保留 + 末行红字（细节由服务层 `print`）。
    ///
    /// 用调用瞬间的 `kind` / `title` 快照（提交途中用户仍可改状态，落库口径以点击那一刻为准）。
    private func submit() {
        guard canSubmit else { return }
        let submittedKind = kind
        let submittedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        isSubmitting = true
        writeFailed = false

        Task {
            let created = await create(kind: submittedKind, title: submittedTitle)
            isSubmitting = false
            if created {
                title = ""
                onDismiss()
            } else {
                NSLog("CalendarQuickAddBar: create \(submittedKind.rawValue) failed")
                writeFailed = true
            }
        }
    }

    /// 取消（末行的 `Cancel`）：清草稿 + 收起。
    private func cancel() {
        title = ""
        writeFailed = false
        onDismiss()
    }

    /// 请求当前档的系统授权（**点击才请求**，口径同 `TodosModule` 的授权提示：不自动弹窗）。
    /// 完成后 toggle 一次 `accessRefreshToken`，逼 body 重算读到新的实时状态。
    private func requestAccess() {
        let requestedKind = kind
        Task {
            switch requestedKind {
            case .reminder:
                await calendarManager.checkReminderAuthorization()
            case .event:
                await calendarManager.checkCalendarAuthorization()
            }
            accessRefreshToken.toggle()
        }
    }

    /// 打开当前档对应的隐私面板（`x-apple.systempreferences:` 是系统既定的跳转 scheme，
    /// 口径同设置页日历节与 `TodosModule` 的提醒设置入口）。
    private func openPrivacySettings() {
        let pane = kind == .reminder ? "Privacy_Reminders" : "Privacy_Calendars"
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 格式化

    /// 时间文本框的文本形态：固定 `HH:mm`（**不随 locale 变**——它是 `CalendarQuickAdd.parseTime`
    /// 的输入，`9:05 AM` 这类 locale 形态解析器不收，D-05 的口径就是 `HH:mm` 文本框）。
    private static func timeText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}

/// 目标日历菜单的账户分组（`Menu` 的 `Section` 用；`id` = 账户名，账户内保持服务层的日历顺序）。
private struct CalendarQuickAddGroup: Identifiable {
    let accountName: String
    let calendars: [CalendarModel]

    var id: String { accountName }
}
