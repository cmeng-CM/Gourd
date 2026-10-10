# 两处日历条目统一为卡片 + 悬停/点击看全文详情 + 两处新增待办与日程

| 项 | 值 |
|---|---|
| 状态 | 已实现 |
| 最后更新 | 2026-10-10 |
| 关联来源 | 用户 2026-10-10 反馈（三个问题）与同日的六项决策 + 四条执行口径（本文件 §决策摘要 D-01…D-16）；承接 docs/24 D-12 与 §已知限制 7（日历 tab 原样接住孤儿视图 `StandaloneCalendarView`）、docs/17 D-25…D-27（首页整宽日历行与 `MonthGridView` 抽取复用）、docs/30 §做法 机制六/机制七（自然高布局与「纯展示块」）、docs/34 §做法 机制一（显示日历 `Calendar.gourdDisplay`）、docs/21 §已知限制 14（非激活面板 `.help()` tooltip 秒级延迟） |
| 工作流 | `.workflow/p11-calendar-cards/` |

> **怎么读**：§背景与目标 / §明确不做 / §备选与取舍 是这场改动的判断依据；
> §接口与数据形状 是参考型小节（执行者与机器查考），人审可跳过；
> §已知限制 / §实际交付 是留给后来人的。

**读者分界**：§一句话方案 / §背景与目标 / §备选与取舍 / §明确不做 / §验收标准 / §决策摘要 给人读；§接口与数据形状 / §做法 是给执行者与模型的契约，边界按 **Always / Ask first / Never** 三档写在各条里。

## 一句话方案

把两个日历（首页整宽日历行的右栏 + 展开面板「日历」页）的条目渲染**统一成同一款卡片**；条目支持**悬停预览 + 点击钉住**的详情浮层（完整标题 / 时间 / 地点 / 备注 / 打开系统 App）；并在两处都补上**新增**——给选中日期加一条待办（写系统「提醒事项」）或一条日程（写系统「日历」，含起止时间与目标日历选择）。

## 背景与目标

**问题现状**（用户 2026-10-10 反馈三条 + 代码查证）：

1. **两处条目的样式不一致**。两个日历是同一份数据、两套渲染组件：首页行右栏用 `EventListView`（2026-09-29 为首页做的紧凑行：19pt 行高、单行标题、无卡片底、勾选圈在行右端、只显示开始时间），面板页右栏用 `StandaloneEventCardList`（上游孤儿视图原样接住：卡片底、2 行标题、地点、色条、起止时间、勾选圈在左端）。连带一处实质口径漏洞：设置里的「显示完整事件标题」只作用于面板卡片——首页行的 `lineLimit(1)` 是硬编码的，开了开关也不生效。
2. **首页行看不到全文**。首页行标题单行尾部截断（右栏宽约 250pt，减去 36pt 时间列后只剩约 200pt ≈ 20 个汉字），且**没有任何悬停或设置途径**能把全文读出来；备注（`notes`）两处日历都不显示。面板卡片默认也只给 2 行（需要用户自己知道去开设置）。
3. **两处都不能新增**。两个日历都没有添加入口（点击条目只是打开系统 App）；app 内的「待办」页能加提醒，但日期只有「今天 / 明天 / 无日期」三档——**没法给某个指定日期加**；日程事件（`EKEvent`）在全 app 没有任何创建路径。

**预期结果**：首页行与面板页的条目长得一样（同款卡片，含标题换行、地点、起止时间）；鼠标停一下就能看到完整标题/备注，点一下钉住，钉住的浮层里有「打开系统日历/提醒」；两处都有「+」——选中某天后能直接加一条当天的待办或日程，写完立刻出现在两个日历里（真写进系统提醒/日历）。

**承接关系**：本次**改判** docs/24 §已知限制 7 的一半——「日历 tab 是原样接住的孤儿视图」在渲染层不再成立（右栏卡片将换成共享组件、并加「+」入口与详情浮层），但「不重写 `StandaloneCalendarView` 的双栏结构 / 自然高布局」不变。docs/17 D-09 的「不做 2 行 chip / 竖向多行」结论在**首页行右栏**被本次覆盖：载体从紧凑行换成卡片（用户 2026-10-10 拍板）。docs/30 §机制七「本行是纯展示块」的口径随「新增入口 + 详情浮层」两处交互而放宽——见 §明确不做 里对边界的重述。术语沿用既有名单：`HomeCalendarRow` / `StandaloneCalendarView` / `MonthGridView` / `CalendarManager` / `EventModel` / `showFullEventTitles` / `hideCompletedReminders` / `hideAllDayEvents`。

**关键约束**：月历网格与翻月口径、行高算式（`36N + 52`）、右下角拖动把手的 36pt 让位、`showCalendar` 单一门控、待办模块本身、锁屏与极简播放器的事件展示——**一律不动**（见 §明确不做）。

**为什么现在做**：用户正在使用两个日历，三条反馈都指向「同一份数据、两种体验」的结构性分叉；不统一就会继续在两处各修一遍，且「新增」能力缺失是日常使用最硬的缺口。

## 做法

整体图景（一次「看/加」的链路）：

```
CalendarManager（单日窗口 events / 按月 monthEvents，既有）
      │ ①过滤（同一套偏好）与排序
      ▼
共享卡片（CalendarEventCard / ReminderCard）──┬── 首页行右栏（滚动卡片列，条目多时栏内滚动）
      │ ②悬停 0.3s / 点击钉住                    └── 面板页右栏（全天芯片条 + 可滚动卡片 List）
      ▼
详情浮层（CalendarEventDetailCard：完整标题/时间/地点/备注/Join/打开系统 App）
      ▲
      │ ③「+」→ 内联表单（待办 / 日程）
CalendarManager.createReminder / createEvent ──→ EKEventStore.save(commit: true)
      │ ④写后显式刷新（updateEvents(force:) + 锁屏 + 按月快照）
      └──→ 两个日历同时看到新条目
```

### 机制一 · 共享卡片（两处同款）

把面板卡片的本体抽成两个独立组件（`CalendarEventCard` / `ReminderCard`，形态逐字搬家），两处宿主只决定**列表容器**：面板页沿用「全天芯片条 + 可滚动 `List` + 自动滚到下一个事件」；首页行右栏换成**可滚动的卡片列**（`ScrollView` + `VStack`，栏内滚动、无 `+N` 与容量算式——卡片高度随标题/地点变化，定高算式算不准，D-13）。首页的「全天」条目**合并进卡片列表**（全天在前、各自按开始时间升序，卡片的收尾时间列显示「All-day」）。时间格式统一为跟随系统 locale 的 `.time` 样式（首页原固定 24 小时制 `clockLabel` 随旧组件一起退休）；「显示完整事件标题」因组件同源而两处同时生效（首页列由宿主读 `Defaults` 传入，组件按内容自适应高度）。

### 机制二 · 详情浮层（悬停 + 点击）

两处宿主各持一个 `CalendarEventDetailsModel`（悬停 id / 钉住 id / 条目锚点表；显示对象 = 钉住优先于悬停）。条目经 `anchorPreference` 上报自己在宿主坐标系里的 frame；宿主在列表之外画**一张**浮层——悬停约 0.3 秒出现（`.allowsHitTesting(false)`，鼠标穿透回卡片、避免 hover 抖动），点击钉住后同一张浮层变为可交互（含「Open in Calendar」按钮，执行旧点击行为）。钉住期间把 `vm.isCalendarDetailsPinned` 并入 `ContentView.hasAnyActivePopovers()` 的收起抑制组；宿主销毁 / 收面板 / 切页时显式归位（`onDisappear` 教训同 `isHoveringCalendar`）；条目离开当日窗口（换选中日）/ 被偏好过滤 / 被表单替换的列表带走时锚点消失、浮层不渲染，抑制标志随 `isPinRenderable`（钉住**且**锚点仍在）自动复位（T8b），不会悬空。不用系统 `.help()`：非激活面板的 tooltip 有秒级延迟（docs/21 §已知限制 14）。全天芯片条（面板页）接同一条链路。

### 机制三 · 新增（待办 / 日程）

一个「+」入口 + 内联表单（形态对齐待办页 composer：出现即聚焦、成功收起、失败留一行提示），表单内「待办 / 日程」二选一（默认待办），**日期一律 = 月历选中日**（改日期点月历，表单不重复放日期输入）。待办写 `EKReminder`（`dueDateComponents` 只带年月日，全天口径；目标列表 = `defaultCalendarForNewReminders()` 兜第一个可用列表）；日程写 `EKEvent`（起止时间由两个文本框**宽松解析**——`15:30` / `1530` / `9:5` 都收、带秒秒归零、越界拒；默认 09:00–10:00、选中日=今天时取下一个整点；「全天」开关走「当天 00:00 → 次日 00:00」口径；目标日历默认 `defaultCalendarForNewEvents`，可切换、只列可写日历）。写入走 `CalendarService` 同一个 `EKEventStore` + `commit: true`（磁盘 I/O 不在主线程，口径照 `setReminderPriority`）；**写成功后显式刷新**（`updateEvents(force:)` + `updateLockScreenEvents` + `refreshRequestedMonthEvents`），不依赖 `EKEventStoreChanged`（自诱发变更可能落在 `ignoreEventStoreChangesUntil` 抑制窗内被丢掉）。授权形态（D-12）：入口「+」**常显**；表单里未授权的档禁用并给「Request Access」（**点击才**请求系统授权，口径同待办模块），被拒时改显「Open System Settings」；判据一律**实时读 EventKit**（`liveCalendarAuthorization` / `liveReminderAuthorization`），不用冷启动不可信的 `@Published` 状态。

### 机制四 · 口径统一的收口清单

时间格式（两处都 `Text(_, style: .time)`）；点击行为（两处都「点击 → 详情钉住」，打开系统 App 改由浮层按钮执行）；「显示完整事件标题」（两处都生效）；弱化档（沿用卡片既有 0.55/0.6 与 `EventListView` 的 0.5 → 统一为卡片口径）；勾选圈位置（统一左端，卡片形态）；`filteredEvents` 过滤函数从 `EventListView` 静态成员迁为独立 `CalendarEventFilters`（组件退休后它仍是两处共用的过滤口径）。

## 备选与取舍

| 分叉 | 选了什么 | 被否的与理由 |
|---|---|---|
| 样式口径 | **以面板卡片为准**（两处卡片） | 以紧凑行为准（面板失去色条/地点/起止时间/Join，且与「想看更多内容」相逆）；保留两档只统一语义（视觉不一致仍在，用户明确要消掉） |
| 看全文交互 | **悬停（预览）+ 点击（钉住）** | 系统 `.help()` tooltip（非激活面板秒级延迟，docs/21 §已知限制 14）；只做点击 popover（多一次点击，用户最初就想要悬停） |
| 新增范围 | **提醒 + 日程一起做** | 只做提醒（日程缺口仍在）；只做跳转系统 App（能力最弱，等于把问题推回用户） |
| 时间输入 | **轻量 `HH:mm` 文本框 + 全天开关** | 系统 `DatePicker`（非激活 NSPanel 的弹层与键盘焦点是项目刻意绕开的坑，见 `TodosModule.swift` 文件头）；步进器 + 时长档（任意时刻要多点几下） |
| 首页全天条目 | **合并进卡片列表** | 与面板完全同构的顶部芯片条（吃掉约 29pt，可见条数再降） |
| 首页列溢出 | **可滚动**（D-13） | 定高卡片 + `+N`：卡片高度随标题/地点变化（约 50–66pt），定高会裁掉开「显示完整事件标题」的内容；容量算式只能按最大高度保守估算、白浪费一档——独立审查发现本矛盾后由用户改判 |
| 时间解析宽容度 | **宽松**（D-11） | 严格只收 `HH:mm`：`1530` 这类常见敲法会被拒 |
| 无授权时入口 | **「+」常显 + 点击才请求**（D-12） | 不渲染「+」：冷启动授权状态读不到（`@Published` 只在设置页链路有真值），会两处都不可见、无从发现；常显但只管禁用：第一次用不知道怎么开 |
| 首页可见条数 | **接受 5 → 3~4（3 周月 1~2）** | 维持 5 条就得留在紧凑行——与「以卡片为准」冲突；用户当面确认接受 |

## 接口与数据形状

**共享卡片**（`DynamicIsland/components/Calendar/CalendarEventCards.swift`）：

```swift
/// 日程卡片（原 StandaloneEventCardList.calendarEventCard 逐字搬家）。
struct CalendarEventCard: View {
    let event: EventModel
    let showFullEventTitles: Bool      // 标题 lineLimit(nil) vs 2
}

/// 待办卡片（原 reminderCard 逐字搬家；勾选圈左置）。
struct ReminderCard: View {
    let event: EventModel
    let showFullEventTitles: Bool
    let onToggle: (Bool) -> Void       // 勾选写回走 CalendarManager.setReminderCompleted
}

/// 可滚动的卡片列（首页行右栏用；条目多于栏高时栏内滚动、无 +N）。
struct CalendarEventCardList: View {
    let events: [EventModel]           // 宿主传**未过滤**的原始条目；组件内读两偏好走 CalendarEventFilters.filtered
    let showFullEventTitles: Bool      // 宿主读 Defaults 后传入（与面板同源）
    @ObservedObject var details: CalendarEventDetailsModel   // 悬停 / 点击 / 锚点上报（组件交互接线）
    static let headerHeight: CGFloat = 26                    // 表头高（原 collapsedHeaderHeight 原值迁入）
    static func ordered(_ events: [EventModel]) -> [EventModel]      // 全天在前、各自按 start 升序（纯函数）
}

/// 两处共用的过滤口径（自由函数化的 EventListView.filteredEvents）。
enum CalendarEventFilters {
    static func filtered(events: [EventModel], hideCompletedReminders: Bool, hideAllDayEvents: Bool) -> [EventModel]
}
```

**首页卡片列的旧口径收口**：`HomeTodayListLayout` 与旧 `EventListView` 已随 T7 退休；其 `collapsedHeaderHeight`（26）迁为 `CalendarEventCardList.headerHeight`，过滤口径迁为 `CalendarEventFilters.filtered`（两者同在这一个文件）。

**详情浮层**（`DynamicIsland/components/Calendar/CalendarEventDetail.swift`）：

```swift
/// 详情内容卡：色条 + 完整标题（不限行）+ 起止时间（或 All-day）+ 地点 + 备注（≤6 行尾部截断）
/// + Join（有 conferenceURL 时）+「Open in Calendar」按钮（执行旧点击行为）
/// + 钉住档右上角 × 关闭按钮（`isPinned` 时显示，`onClose` 解钉）。
struct CalendarEventDetailCard: View {
    let event: EventModel
    let isPinned: Bool
    let onClose: () -> Void
}

/// 锚点表：条目 id → 在宿主坐标系里的 bounds（anchorPreference 上报，宿主 reduce）。
struct CalendarEventAnchorKey: PreferenceKey { static var defaultValue: [String: Anchor<CGRect>] }

@MainActor final class CalendarEventDetailsModel: ObservableObject {
    @Published var hoveredID: String?
    @Published var pinnedID: String?
    // 不持锚点表：定位在修饰符内部闭环（overlayPreferenceValue 现场解析 Anchor + 实测高）。
    @Published private(set) var isPinRenderable: Bool = false   // 钉住**且**锚点仍在（T8b；宿主据此同步收起抑制标志）
    var activeID: String? { pinnedID ?? hoveredID }
    func hover(_ id: String?)
    func endHover(_ id: String)     // 行销毁时收口：仅当 hoveredID == id 才清（T3 fix）
    func togglePin(_ id: String)
    func refreshPinRenderable(pinnedAnchorPresent: Bool)   // 修饰符在锚点表 / pinnedID 变化时各算一次（T8b）
    func clear()                                  // 归位：onDisappear / 收面板 / 切页
}

/// 悬停接线：包一张卡片，悬停满约 0.3s 写 `model.hover(id)`；离开取消并 `hover(nil)`；
/// onDisappear 取消在飞任务并 `endHover(id)`。
struct CalendarEventHoverTarget<Content: View>: View { init(id: String, model: CalendarEventDetailsModel, content: () -> Content) }

/// 宿主级修饰符：在内容之上画浮层。定位按**实测高**（组件内 `CalendarEventDetailHeightKey`，初值 120）：
/// 优先条目下方 → 放不下翻上方 → 上下都放不下贴条目夹取；高度上限 = 宿主高 − 16（裁剪兜底）。
extension View { func calendarEventDetails(model: CalendarEventDetailsModel) -> some View }
```

**新增（服务层）**：

```swift
// CalendarService（具体类型；不进 CalendarServiceProviding 协议——本批不改对外契约）
func createReminder(title: String, dueDateComponents: DateComponents?) async -> Bool
func createEvent(title: String, start: Date, end: Date, isAllDay: Bool, calendarID: String?) async -> Bool
func writableEventCalendars() -> [CalendarModel]        // allowsContentModifications 过滤
func defaultEventCalendarID() -> String?                // 只取 defaultCalendarForNewEvents；「?? 第一个可写」的兜底在 Manager 侧

// CalendarManager（写后显式刷新；不依赖 EKEventStoreChanged）
func createReminder(title: String, due: Date) async -> Bool
func createEvent(title: String, start: Date, end: Date, isAllDay: Bool, calendarID: String?) async -> Bool
func creatableEventCalendars() async -> [CalendarModel]
var preferredEventCalendarID: String? { get }           // defaultEventCalendarID() ?? writableEventCalendars().first?.id
var liveCalendarAuthorization: EKAuthorizationStatus { get }    // 直读 EventKit——冷启动的 @Published 状态不可信（D-12 判据）
var liveReminderAuthorization: EKAuthorizationStatus { get }
```

**纯函数**（`DynamicIsland/components/Calendar/CalendarQuickAdd.swift`；不读 Defaults、不碰 EventKit，可直接单测）：

```swift
enum CalendarQuickAdd {
    // AddKind（reminder / event）实际以 extension 落在 CalendarQuickAddBar.swift；类型仍是 CalendarQuickAdd.AddKind。
    /// "15:30" / "1530" / "9:5" → 选中日上的 Date（秒归零）；纯 1–2 位数字 = 整点（"9" → 09:00）、
    /// 3–4 位 = 时+分（"930" → 09:30）、带秒秒归零（"15:30:45"）；5 位+ / 越界 / 不可解析 → nil。
    static func parseTime(_ text: String, on day: Date, calendar: Calendar) -> Date?
    /// 选中日 == 今天 → 下一个整点（now ≥ 23:00 回退 09:00）；否则 09:00。
    static func defaultStart(on day: Date, now: Date, calendar: Calendar) -> Date
    static func defaultEnd(start: Date) -> Date                          // +1h
    static func isValidRange(start: Date, end: Date, calendar: Calendar) -> Bool   // end > start 且同自然日
    static func allDayRange(on day: Date, calendar: Calendar) -> (start: Date, end: Date)  // 次日零点为端
    static func reminderDueComponents(on day: Date, calendar: Calendar) -> DateComponents  // 只带 y/m/d
}
```

**表单与入口**（`DynamicIsland/components/Calendar/CalendarQuickAddBar.swift`）：`CalendarQuickAddBar(selectedDate:onDismiss:)`——内部持 `kind/title/startText/endText/isAllDay/calendarID/失败行`，提交直接调 `CalendarManager`；出现即聚焦标题（口径照 `TodosModule` 的 composer）；未授权档禁用并给「Request Access」（点击才请求）/ 被拒改显「Open System Settings」，入口「+」常显（D-12）。入口：首页行日期头一行右侧「+」、面板页右栏顶部一行（约 22pt）右侧「+」；表单展开时**替换**该栏列表区，取消/完成后恢复列表。三处按代码口径记的形态（T8b；上屏核实后如有出入再校正）：未授权档的引导按钮（`Request Access` / `Open System Settings`）**占末行确认位**（不另起一行——表单要整条塞进列表区）；起止时间框的 prompt **兼作标签**、框内有初值时不可见；`.writeOnly`（仅写授权）下写入成功但读取路径不可用 → 新条目可能不显示（授权档口径，不是写入失败）。

**收起抑制标志**：`DynamicIslandViewModel` 新增 `@Published var isCalendarDetailsPinned: Bool = false`，并入 `ContentView.hasAnyActivePopovers()`。

**文案键**（`DynamicIsland/Localizable.xcstrings`，新增键必须同时补 `en` 与 `zh-Hans`，能复用既有条目就复用）：

| 键 | en | zh-Hans |
|---|---|---|
| `calendar.quickAdd.addNew` | New | 新增 |
| `calendar.quickAdd.kindReminder` | To-do | 待办 |
| `calendar.quickAdd.kindEvent` | Event | 日程 |
| `calendar.quickAdd.title` | Title | 标题 |
| `calendar.quickAdd.start` | Start | 开始 |
| `calendar.quickAdd.end` | End | 结束 |
| `calendar.quickAdd.failed` | Couldn't save. Please try again. | 写入失败，请重试 |

（共 7 个新键。`Open in Calendar`（详情浮层的打开按钮，含 zh-Hans「在日历中打开」）、`All-day`、`Request Access`、`Open System Settings` 等**复用既有条目**，不新增、不重写。）

## 明确不做

- **不做**日程的重复规则 / 闹钟 / 邀请人 / 地点与备注输入（当天快速加一条是本批的全部；其余字段去系统 App 补）。
- **不做**待办的具体时刻（只有日期，全天口径）。
- **不做**已有事件的编辑与删除（待办页既有的删除能力不动；日历里的条目仍然只读除勾选外）。
- **不动**面板页的全天芯片条形态（首页合并卡片是首页的口径；面板保留芯片条 + 可滚动列表）。
- **不动**月历网格、翻月口径（首页不挪选中日 / 面板挪）、行高算式 `36N + 52`、右下角把手的 36pt 让位、`showCalendar` 单一门控、待办模块、锁屏面板与极简播放器的事件展示。
- **不做**整行的滚动/marquee 等「抽奖式」全文呈现——全文归详情浮层。

## 实际交付

**交付物**（提交 T1…T8b，范围 `40ff9b35..84c0a67c`：T1–T7 代码 + T8a 手册与回写 + T8b 终审修复；全量测试 559 条 0 失败）：

- 新文件：`DynamicIsland/components/Calendar/CalendarEventCards.swift`（共享卡片 + 滚动卡片列 + 过滤口径）、`CalendarEventDetail.swift`（详情浮层四件套）、`CalendarQuickAdd.swift`（六条纯函数）、`CalendarQuickAddBar.swift`（「+」按钮 + 内联表单 + `AddKind`）。
- 改动：`DynamicIslandCalendar.swift`（面板页接入卡片 / 详情 / 表单，旧卡片 builder 退休）、`HomeCalendarRow.swift`（右栏换卡片列 + 「+」入口 + 详情接线）、`CalendarServiceProviding.swift`（`CalendarService` 四条新增写 / 读）、`CalendarManager.swift`（转调 + 写后显式刷新 + 实时授权读）、`DynamicIslandViewModel.swift`（`isCalendarDetailsPinned`）、`ContentView.swift`（并入 `hasAnyActivePopovers()`）、`Localizable.xcstrings`（+7 键，均含 `en` 与 `zh-Hans`）、`HomeStripView.swift`（注释引用清扫，T7 fix）、`ModuleKernelTests.swift`（新增与改造用例）。
- 退休：`EventListView`（含 `clockLabel`）与 `HomeTodayListLayout`（含 `rowHeight`/`rowSpacing`/`maxItemRows`/`timeColumnWidth`/旧 `capacity`）；过滤口径迁为 `CalendarEventFilters.filtered`，表头高迁为 `CalendarEventCardList.headerHeight`（26）。用例账：删 4 条旧口径用例（3 容量 + 1 `clockLabel`），`HomeTodayListLayoutTests` 的日期轮 5 条重挂为 `WheelPickerIndexMathTests`（内容未变），`HomeCalendarRowLayoutTests` 保留行高 232/206 断言、判据改 `headerHeight`。

**与计划的偏离及原因**：

1. `CalendarEventCardList` 签名追加 `details: CalendarEventDetailsModel`（T3）——悬停 / 点击钉住 / 锚点上报需要宿主一份浮层状态，卡片列是唯一上报方。
2. `CalendarQuickAdd.AddKind` 以 extension 落在 `CalendarQuickAddBar.swift`（类型与文档一致）——T5 的纯函数文件只落六条函数，档位类型随表单文件落地。
3. 首页列溢出由「定高卡片 + `+N` 容量算式」改判为**滚动**（D-13，计划门补问拍板）——卡片高度随标题 / 地点变化，定高算式算不准。
4. 详情浮层相对初稿多两处：钉住档右上角 `×` 关闭按钮（浮层会压住条目，「同卡再点取消」不一定可点）与按**实测高**定位（固定估值下翻转判据恒真、浮层被夹在列顶）——均 T3 fix。
5. `CalendarView`（仅 `#Preview`）改渲染 `CalendarEventCardList` + 自有 `details` 模型；`.fixedSize(vertical:)` 由整块移到日期头行（`ScrollView` 需要确定高度）——T7 退休收口。

**遗留项**：

- **上屏验收已完成**（2026-10-10，Release 配置自建包）：首页右栏卡片列（含全天卡片）、面板页「全天芯片条 + 卡片」、两处「+」表单（待办/日程两档、默认起止 16:00–17:00、目标日历「工作」、日期标签）、点击条目钉住详情（两处，含备注位、`在日历中打开`、`×`）、`×` 解钉均上屏通过；两处各真写一条待办与一条日程并经系统侧独立确认（「提醒事项」显示「今天/计划 = 2 个提醒事项」、「日历」显示「【验收可删】Gourd 日程测试 16:00–17:00」；测试待办已删除并进「最近删除」30 天）。证据在 `.workflow/p11-calendar-cards/evidence/`。
- hover 观感（0.3s 延迟 / 穿透 / 抖动）无法用合成事件驱动，需用户真人复核（上屏以「点击钉住」同款浮层代替取证）。
- 首页列**滚动行为**未在数据量小时上屏触发（当天条目 4 条不足以溢出）；面板页 `List` 行内锚点随滚动跟随同理未实测——两者按代码审查 + 用户按需复核。

## 已知限制

1. 首页右栏**同屏可见**的卡片数比原紧凑行少（首页行宿主高约 160–268pt；卡片约 50–66pt/张，5 周月同屏约 2–3 张、3 周月 1–2 张）——条目多时需在栏内滚动（D-13 改判：不再有 `+N` 与容量算式）。这是 D-01 的直接代价。
2. 首页卡片宽约 250pt（面板约 340pt），标题 / 地点截断更早——由详情浮层兜底。
3. 点击行为变更（原「打开系统 App」→「弹出详情并钉住」）会改变既有习惯；手册与 FAQ 已明示（T8）。
4. 非激活面板的悬停态无法用合成事件驱动（p6 起已知），hover 观感验收 = 代码审查 + 用户真人复核。
5. 新建日程不做重复 / 闹钟 / 邀请人；新建待办不含具体时刻（只到日）。
6. 钉住态详情浮层会压住其下方条目（可命中的顶层）——出口 = 浮层右上角 `×` / 切页 / 收面板；「点其它卡转移」只在未被压住的条子上可达。条目离开当日窗口 / 被偏好过滤 / 表单替换列表时锚点消失 → 浮层不渲染，收起抑制标志随 `isPinRenderable` 自动复位（T8b）——`×` 出口不悬空。
7. 极端长备注（6 行）在小列高宿主（3 周月 ≈134pt 视口）下会被浮层高度上限（宿主高 − 16）从底部裁掉——刻意兜底，完整内容去系统 App。
8. 详情浮层首帧按测量初值（120）定位、次帧按实测高修正：极端「高卡 + 底部条目」有 1 帧（约 40pt 内）位置瞬移（接受档）。
9. 钉住档关闭按钮（×）命中区约 13×13pt（`contentShape` 在 padding 之内）——偏小但可用；若上屏复核手感不佳再放大。
10. `defaultStart` 的「下一个整点」用「整点起点 + 1 小时」推算：DST 切换日的极端情形与逐日推进不完全等价（Asia/Shanghai 无影响；23 点分支已挡跨日）。
11. 两处滚动容器（面板 `List` / 首页列 `ScrollView`）的在途锚点与浮层在滚动期的行为未自动化验证——以代码审查与上屏滚动目测代替。
12. 首页卡片在 T2 提交（T3 接入钉住之前）曾处于「点击无行为」的中间态——批次内部态，无用户可见影响。
13. 未授权档表单的引导按钮（`Request Access` / `Open System Settings`）占末行确认位（不另起一行——表单要整条塞进列表区）；起止时间框的 prompt 兼作标签、有初值时不可见；`.writeOnly`（仅写授权）下写入成功但读取路径不可用——新条目可能不显示（授权档口径，不是写入失败）。

## 验收标准

1. `xcodebuild test`（`DynamicIslandTests`）全绿，含新增用例：`CalendarEventCardList.ordered` 排序、`CalendarQuickAdd` 全部纯函数（含宽松解析、默认时段边界、全天/提醒口径）。
2. 上屏截图（`.workflow/p11-calendar-cards/evidence/`）：两处同款卡片；悬停浮层（含备注）与点击钉住；两处「+」各新增一条待办与一条日程并在系统「提醒事项」/「日历」侧复核真写入；失败路径（如无默认可写目标时的一行提示）。
3. `grep -rnw -e EventListView -e clockLabel DynamicIsland/ DynamicIslandTests/` 零命中（D-10；`-w` 词边界不误伤 `MinimalisticReminderEventListView`）。
4. 手册三处与 `docs/36` 与实际形态一致（T8）。

## 决策摘要

| ID | 决策 | 来源 | 理由 |
|---|---|---|---|
| D-01 | 两处日历条目统一为面板卡片形态（首页行右栏改卡片列；全天合并进卡片列表） | 用户 | 三选一中拍板「以面板卡片为准」；代价（可见条数下降）当面确认接受 |
| D-02 | 看全文 = 悬停预览（约 0.3s）+ 点击钉住，自绘浮层、不用系统 tooltip | 用户 | 用户选「悬停 + 点击都能开」；`.help()` 非激活面板秒级延迟已被 docs/21 §已知限制 14 记录 |
| D-03 | 新增范围 = 提醒 + 日程事件一起做（都写系统） | 用户 | 用户选「提醒 + 日程事件一起做」；权限（full access）与写回链已就绪 |
| D-04 | 新增入口两处都放（首页行日期头 + 面板页右栏顶部） | 用户 | 用户选「两处都放」，与「两处同款」一致 |
| D-05 | 时间输入 = 轻量 `HH:mm` 文本框 + 全天开关（不引 `DatePicker`） | 用户 | 用户选「轻量文本输入」；绕开 `DatePicker` 在非激活面板的焦点坑（TodosModule 文件头口径） |
| D-06 | 首页「全天」条目合并进卡片列表（收尾时间位显示「All-day」） | 用户 | 用户选「合并进卡片列表」；芯片条会再吃掉约 29pt |
| D-07 | 新增表单 = 一个「+」入口 + 内联表单（与待办 composer 同构），「待办 / 日程」二选一、默认待办、日期 = 选中日 | 用户 | 方案草案写死、用户「进行吧」整体确认 |
| D-08 | 待办只有日期（全天口径）；日程默认 09:00–10:00（选中日=今天时取下一个整点，≥23:00 回退 09:00） | 用户 | 同上 |
| D-09 | 点击行为变更：卡片点击从「直接打开系统 App」改为「弹出详情并钉住」，打开按钮移进浮层 | 用户 | 同上（交互取舍已在方案中陈述） |
| D-10 | `EventListView` 视图与 `clockLabel` 退休；`filteredEvents` 迁为独立 `CalendarEventFilters` | 用户 | 同上；退休口径 = 运行时调用点归零（仓库「不留无调用点形态」惯例） |
| D-11 | 时间解析宽容度 = **宽松**（`15:30` / `1530` / `9:5` 都收、首尾空白容忍、带秒秒归零、越界拒） | 用户 | 计划门补问（输入容错类）；解析规则写进单测钉死 |
| D-12 | 无授权形态 = 「+」**常显**、未授权档禁用 + 「Request Access」（点击才请求）/ 被拒显「Open System Settings」；门控判据**实时读 EventKit** | 用户 | 计划门补问；不打扰且可发现，同时修掉冷启动授权状态读不到的坑（独立审查发现） |
| D-13 | 首页列溢出 = **可滚动**、卡片按内容高（不再有 `+N` 与容量算式） | 用户 | 计划门补问；卡片高度随标题/地点变化，定高容量算式算不准（独立审查发现），滚动同时完整保留「显示完整事件标题」 |
| D-14 | 钉住档详情浮层增加右上角 `×` 关闭按钮（`CalendarEventDetailCard.onClose` 解钉） | 执行期（T3 fix） | 浮层会压住条目（窄宿主下尤其），「同卡再点取消」不一定可点——D-02 / D-09 的落地细化（浮层内的确定出口） |
| D-15 | 详情浮层定位按**实测高**（卡片经 preference 上报，初值 120、首帧后修正） | 执行期（T3 fix） | 固定估值（200）下翻转判据恒真、夹取把浮层恒钉列顶；首页行宿主高只有 160–268pt |
| D-16 | `collapsedHeaderHeight`（26）迁为 `CalendarEventCardList.headerHeight` | 执行期（T7） | `HomeTodayListLayout` 整体退休，但行高换算（`rowHeight − headerHeight`）与 `#Preview` 视口仍需这个数 |

执行期核对：D-01…D-13 与实现逐条一致（无改判）；D-14…D-16 为执行期新增判断（编号接续）。
