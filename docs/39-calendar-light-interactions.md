# 首页与日历的轻量交互

状态：交互实现与文档已回写，界面验收待完成；2026-10-11。来源为用户逐项确认的交互方案及“按照方案继续吧”。本文件覆盖本轮全部范围；T6 与全局验收仍为待完成，当前通过证据见「实际交付」。

## 一句话方案

首页完整滚动展示今天的日程与待办；日历右栏在列表、详情、编辑之间切换，岛内处理完成、简单新增及普通日程修改删除，复杂维护交给系统应用；自动收回保留本次运行中的单份草稿。

## 背景与目标

首页当前按行数截断内容，待办圈没有动作，日历提醒还可能重复混入日程组；首页读取选中日快照，切换日期也会影响今天。日历详情浮层覆盖列表，钉住状态阻止收回；新增字段缺少明确标签，局部视图销毁会丢失输入。

承接 [36-calendar-cards-and-add.md](36-calendar-cards-and-add.md) 的月历网格、共享卡片、显示偏好、点击申请权限和写后显式刷新；本次明确覆盖其悬停预览、点击钉住、局部表单草稿与仅当天起止时间的结论。保留模块门控与现有刘海几何、拖动和终端抑制行为。

## 做法

### 首页

固定计数头，下方一条可滚动内容区，分为“日程”“待办”；不按容量截断。今日清单与“下一个日程”均读取独立今天快照，排除提醒类型，并包含今天仍在进行的跨日事件；待办按记录 ID 去重，保留完成与全天显示偏好。隐藏已完成只影响显示行，统计仍显示完整今日已办/总量。日程与标题点击进入日历右栏详情；待办圈独立写完成状态，失败保留原状态并展示该次完成操作错误。返回首页恢复锚点，完成后不重置滚动。

### 日历右栏

保留左月历，右栏只有列表、详情、编辑三种页面。悬停仅高亮；点击替换右栏，不叠浮层。页面头与动作区固定，列表、完整标题/地点/备注、表单均在中间滚动。详情提供返回、系统应用入口、提醒完成/撤销、普通可写日程编辑/删除；删除需原地确认标题与日期，成功返回邻近位置。

普通日程编辑标题、起止日期时间、全天、地点、备注，目标日历显示清楚。重复/分离事件、会议邀请、生日及只读日历不在岛内修改删除，由系统应用处理。新增可选择待办/日程及可写目标列表/日历；起止标签明确，位置和备注在补充区；保存与取消始终可见。全天结束采用 EventKit 的排他日期，界面显示包含的最后一天。保存成功进入真实写回记录的详情，失败保留输入与错误。

### 返回与草稿

进程级 `CalendarPanelSession` 持有路由、来源、日期与滚动锚点、单份草稿及基线。返回/Esc 暂存编辑并回到来源；取消表示放弃，脏草稿须确认。切日期不改草稿日期或目标；切 tab、收回、锁屏保留草稿，列表显示“有未保存的日程/待办 · 继续编辑”。已有草稿时新建/编辑另一项询问继续旧稿、放弃后开始、取消跳转。Esc 先关闭所属弹层或确认，再执行页面返回；详情 Esc 返回来源，列表 Esc 收回。

### 收回与退出

详情不持钉住标记。键盘焦点、所属菜单/日期弹层、提交期间持现有抑制令牌；外部应用/窗口失焦后暂存、释放令牌并复查 hover。滚动内容使用独立滚动抑制；编辑/提交取消快捷键延迟收回。锁屏先暂存，再关闭所有屏幕的面板。普通退出有脏草稿时提供保存并退出、放弃并退出、取消；正在提交只等待同一次操作，失败取消退出。重启也先走退出裁决，不能提前启动第二实例。

## 备选与取舍

| 选择 | 理由 |
|---|---|
| 固定右栏页面替换 | 浮层遮挡和钉住抑制会破坏轻量查看与收回 |
| 共享内存草稿 | 视图销毁和多屏重建不丢输入，又不落盘保存个人日程内容 |
| 同一 EventKit store 写前复查 | UI 状态可能过期，服务必须再次限制只读、重复和会议写入 |
| 闭包注入写入器与 DEBUG 数据 | 可以测试失败和异步竞争，无需改动真实日历/提醒 |
| 保留旧浮层组件给未启用的历史宿主 | 本轮更换实际首页与日历面板入口，避免扩成无关旧组件重构 |

## 接口与数据形状

### 写入、读取与日期

源码：[EventModel.swift](../DynamicIsland/models/EventModel.swift)、[CalendarServiceProviding.swift](../DynamicIsland/Providers/CalendarServiceProviding.swift)、[CalendarManager.swift](../DynamicIsland/managers/CalendarManager.swift)。以下五个记录接口已进入 `CalendarServiceProviding`；`CalendarService` 与 `CalendarManager` 的具体入口给新建参数提供 nil 默认值，协议要求调用方显式传参。

```swift
// CalendarService 与 CalendarManager
func saveEvent(input: CalendarEventInput, eventID: String? = nil) async throws -> EventModel
func createReminderRecord(title: String, due: Date, listID: String? = nil) async throws -> EventModel
func deleteEvent(id: String) async throws
func completeReminder(id: String, completed: Bool) async throws -> EventModel
func event(withID id: String) -> EventModel?
func writableReminderCalendars() -> [CalendarModel]
var preferredReminderCalendarID: String? { get }

// CalendarService / CalendarServiceProviding
func writableEventCalendars() -> [CalendarModel]
func defaultEventCalendarID() -> String?
func authorizationStatus(for type: EKEntityType) -> EKAuthorizationStatus

// CalendarManager
func creatableEventCalendars() async -> [CalendarModel]
var preferredEventCalendarID: String? { get }
var liveCalendarAuthorization: EKAuthorizationStatus { get }
var liveReminderAuthorization: EKAuthorizationStatus { get }
@Published private(set) var todayEvents: [EventModel]
func updateTodayEvents(force: Bool = false) async
```

`CalendarEventInput: Equatable` 含 `title: String`、`start/end: Date`、`isAllDay: Bool`、`location/notes/calendarID: String? = nil`；`validated(calendar: Calendar = .current) throws -> Self` 去标题首尾空白、拒绝空标题或 `end <= start`，全天要求两个端点均为自然日零点。`exclusiveAllDayEnd(including:calendar:)` 与 `includedAllDayEnd(exclusiveEnd:calendar:)` 返回 `Date?`，用 `Calendar` 按自然日加减一天，界面显示包含的最后一天，服务存排他尾日。跨日定时不要求同日，也不用固定 86400 秒表示自然日。

目标必须可写且类型正确，成功返回保存记录的真实稳定 ID。`eventID == nil` 新建；编辑时 `calendarID == nil` 保留原日历；新建未指定目标时取系统默认可写源，再兜第一个可写源。显式无效、只读或类型不符的 ID 抛错，不改投其他目标。表单层的 `CalendarDraft.validateTarget() throws` 更严格，要求非空目标 ID 及标题，缺失目标可在授权后填初始值，已经选择或外部失效的 ID 不会被替换。

`CalendarModel.allowsContentModifications: Bool` 保留实际源权限；`EventModel.isDetached: Bool`、`modificationRestriction: CalendarMutationError?`、`canModifyInIsland: Bool`、`canCompleteReminderInIsland: Bool` 给 UI 与服务共用。`CalendarMutationPolicy.performEventWrite<T>(event:write:) throws -> T` 在写闭包前拒绝只读、重复、分离、含参会人的会议、生日及错误类型；`performReminderWrite<T>(event:write:) throws -> T` 检查提醒类型和可写权限，**重复提醒仍可完成/撤销**。`targetCalendarID(requestedID:originalID:defaultID:calendars:isReminder:) throws -> String` 统一选择规则。真实服务在同一 `EKEventStore` 的串行 `writeQueue` 中重读、复核后 `commit: true`，编辑先检查原记录再更换目标，失败回滚内存修改；旧 Bool/Void 创建、完成、优先级入口也走该队列与守卫。

`CalendarAccessPolicy.canRead(status:)` 要求 `.fullAccess`；`canCreate(status:for:)` 对日程另接受 `.writeOnly`。页面 `CalendarPanelAccess.canSave(draft:authorization:)` 与服务一致，仅新建日程可用仅写授权，既有记录的详情与改删需完整读取权限。Manager 每次写成功显式刷新今天、选中日、锁屏及已请求的月份；`todayEvents` 是独立半开今天窗口的重叠快照，排除提醒，跨午夜旧响应重新抓取，不从 `events` 的选中日快照派生。

### 共享会话与页面

源码：[CalendarPanelSession.swift](../DynamicIsland/models/CalendarPanelSession.swift)、[CalendarPanelPages.swift](../DynamicIsland/components/Calendar/CalendarPanelPages.swift)。`CalendarDraft: Equatable` 与 `@MainActor CalendarPanelSession: ObservableObject` 已实现；会话入口如下：

```swift
enum CalendarPanelSource: Equatable { case home(anchor: String?); case calendar(date: Date, anchor: String?) }
enum CalendarPanelRoute: Equatable { case list, detail, editor }
enum CalendarDraftConflictChoice { case resume, discardAndStart, cancel }
enum CalendarTerminationChoice { case save, discard, cancel }
// CalendarDraft
// kind: Kind（event/reminder）；eventID: String?；originalDate/start/end: Date；
// title: String；isAllDay: Bool；location/notes: String = ""；calendarID: String?。
// 提醒目标同 calendarID；baseline 为独立值，不写回旧实体。
func eventInput(calendar: Calendar = .current) throws -> CalendarEventInput
func validateTarget() throws

// CalendarPanelSession
func showList(on date: Date, anchor: String? = nil)
func showDetail(_ event: EventModel, source: CalendarPanelSource)
func beginCreate(kind: CalendarDraft.Kind, on date: Date, calendarID: String?)
func beginEdit(_ event: EventModel)
func back() -> CalendarPanelSource? // 编辑退到先前详情/列表；详情退到来源；home返回值交宿主导航
func suspend() // 保稿，退出编辑路由，清输入ownership
func resumeDraft()
func requestCancel() // 脏稿设确认；干净直接返回
func discardDraft()
func resolveDraftConflict(_ choice: CalendarDraftConflictChoice)
func dismissConfirmation()
func openInSystemApp(_ event: EventModel? = nil)
func save() async -> Bool
func delete() async -> Bool // 详情已做删除确认后调用
func complete(_ event: EventModel, completed: Bool) async -> Bool
func resolveTermination(_ choice: CalendarTerminationChoice) async -> Bool
func waitForSubmission() async -> Bool // 等既有任务，不能发起第二次写入
// @Published 可修改：selectedDate: Date、calendarScrollAnchor/homeScrollAnchor: String?、draft: CalendarDraft?。
// @Published private(set)：route: CalendarPanelRoute、detailEvent: EventModel?、
// returnSource: CalendarPanelSource、baseline: CalendarDraft?、isSubmitting: Bool、
// error/completionError: String?、pendingConfirmation: Confirmation?（discardDraft/draftConflict）、
// editorHasFocus: Bool、ownedMenuCount: Int、datePopoverPresented: Bool。
// 派生：hasDirtyDraft: Bool、shouldProtectAutoClose: Bool。
func setEditorFocus(_ focused: Bool, ownerID: UUID)
func setOwnedMenuCount(_ count: Int, ownerID: UUID)
func setDatePopoverPresented(_ presented: Bool, ownerID: UUID)
func clearOwnership(_ ownerID: UUID)
// 每个页面稳定UUID；上述状态由所有活跃owner聚合，某窗口销毁不能清其他窗口焦点。
// shouldProtectAutoClose = 提交 || 编辑中(焦点 || 所属菜单 || 日期弹层)。
```

会话初始化支持 `selectedDate: Date = Date()`、`calendar: Calendar = .autoupdatingCurrent`、`now: () -> Date = Date.init`，注入 `saveEvent: (CalendarEventInput, String?) async throws -> EventModel`、`createReminder: (String, Date, String?) async throws -> EventModel`、`deleteEvent: (String) async throws -> Void`、`completeReminder: (String, Bool) async throws -> EventModel`、`event: (String) -> EventModel?` 与 `openSystemEvent: (EventModel) -> Void`（默认空动作）；`init(manager:)` 接生产 Manager，`shared` 在整个进程内共享。请求代数隔离旧异步结果，同一提交任务防重入；提交期间页面禁用字段。

暂存后恢复同一稿仍可接收成功详情或当前错误；提交后若输入被程序改动，保留新值，把新建稿绑定到真实记录 ID；已创建提醒的残留修改拒绝再次新建，提示系统维护。保存退出等待已有任务后检查剩余脏稿，另一项完成操作成功不能代替保存；放弃退出先等成功再清稿，等待或保存失败均取消退出。`completionError` 单独供首页完成动作读取，不混入旧保存错误。

`CalendarPanelPages(session:manager:onReturnSource:)` 消费共享会话，`StandaloneCalendarView` 保留左月历自然高与模块门控，右栏只接这一个页面入口。图形日期弹层与 `NSPopUpButton/NSMenuDelegate` 目标菜单按稳定页面 UUID 上报所有权；`CalendarPanelDates` 统一包含尾日转换。定时结束恰在次日零点不计入次日；全天切回定时保留日期跨度，设首日 09:00 至最后日 10:00，不保留隐藏旧时刻，用户需调整实际时间。

首页 [TodosModule.swift](../DynamicIsland/Modules/TodosModule.swift) 使用无容量参数的 `TodosHomeBlockLayout.listedEntries(events:todos:hasFullAccess:hideCompletedReminders:) -> [ScheduleEntry]` 与 `uniqueTodos(_:)` 按记录 ID 去重；旧 `rowCount` 重载仅兼容历史调用。表头统计用未隐藏的今日待办，清单与 [HomeTodayBand.swift](../DynamicIsland/Host/HomeTodayBand.swift) 的下一个日程均读独立今天快照；首页详情只在日历 tab 已启用时可打开。`anchor(afterRemoving:from:anchor:) -> String?` 对被隐藏的锚点取下一条、再兜上一条，其它完成动作不重置锚点。

### 焦点、收回与退出

源码：[CalendarEditorLifecycle.swift](../DynamicIsland/components/Calendar/CalendarEditorLifecycle.swift)、[DynamicIslandApp.swift](../DynamicIsland/DynamicIslandApp.swift)、[ContentView.swift](../DynamicIsland/ContentView.swift)。生命周期复用 VM 的 `setAutoCloseSuppression(_:token:)` 和独立滚动抑制令牌，窗口销毁先释放本页 UUID；无任何聚合输入时才暂停编辑路由。窗口之间及其子窗口互认，真正外部离开才全局暂停；MainActor 同步完成检查和暂停，提交任务仍继续，宿主在页面销毁/切 tab 后保留提交保护。

`CalendarEditorLifecycle.closeForLock(session:closePanels:)` 先 `suspend()`，再关闭全部屏幕面板；`CalendarShortcutCloseProtection` 由实际 AppDelegate 实例注入取消闭包，在编辑/提交入场时取消旧快捷键收回定时器。`CalendarTerminationController.resolve(session:choose:restart:) async -> Bool` 合并重复退出裁决，`requestRestart()` 标记重启；AppDelegate 的 `applicationShouldTerminate(_:) -> NSApplication.TerminateReply` 先返回 `.terminateLater`，决策完成再回复。只有允许退出后才启动重启实例。

新增界面文案在 `Localizable.xcstrings` 提供 `en`、`zh-Hans`；四个退出提示键通过 `String(localized:)` 在真实 AppDelegate 取值。

### DEBUG 夹具与验收入口

源码：[CalendarInteractionFixtures.swift](../DynamicIsland/helpers/CalendarInteractionFixtures.swift)、[DynamicIslandUITests.swift](../DynamicIslandUITests/DynamicIslandUITests.swift)。`--uitesting` 启用 DEBUG 夹具，默认 30 条（日程 10、提醒 20），`--calendar-fixture-count=9` 为 9 条（日程 3、提醒 6），包含普通及五类受限日程、长备注。`--calendar-write-failure` 永久失败，`--calendar-write-failure-once` 仅下一次写入失败，`--calendar-write-delay-ms=N` 延迟（上限 60000 毫秒）；失败在修改记录字典前抛出，一次失败标志在锁内消费。

`CalendarInteractionFixtures.backend: CalendarInteractionMemoryService` 实现 `CalendarServiceProviding`，所有写入与刷新共用锁保护的同一字典，完成日期元数据也在同一锁下。后端 `allRecords() -> [EventModel]` 供 TodoStore 读取，`recordSystemOpen(_ id: String)` 只记录跳转，不启动真实系统或第三方应用；补 `createTodoReminder(title: String, due: Date?, listID: String? = nil) async throws -> EventModel`、`deleteReminder(id: String) async throws` 供既有待办模块测试调用，无日期用 `.distantFuture` 并在读回待办时映射为 nil。Manager 初始化直接选内存服务，跳过 EventKit 观察与真实授权读取；TodoStore 所有夹具读取/写入先短路真实调用，生产 `EKEventStore` 延迟初始化。

测试 app/unit/UI 包按 `com.cmeng.gourd.calendar-tests.$(PRODUCT_NAME:rfc1034identifier)` 分开标识，保留项目 `Gourd Local` 签名，不覆写 `CODE_SIGN_IDENTITY`。AppDelegate 在 VM/coordinator 属性构造前配置测试标准偏好，只启用 config 为 nil 的日历与待办，不写不清固定生产模块 suite；窗口与 bootstrap 双就绪后由 `CalendarFixtureReadiness` 打开真实首页并发布 `calendar-fixture-ready`，UI helper 再等待真实待办行，未另建演示宿主。测试模式跳过系统 HUD/Lunar 启动与退出恢复，提前关闭 DDC 与 `mirrorSystemTimer`，避免外部应用 suite 写入及真实 Clock 域读取。

测试 host/fixture 在蓝牙管理器 init 最前端返回，`batteryReader` 改为 lazy，不构造 CBCentralManager 或启动初始扫描、观察、轮询。剪贴板 init/startMonitoring 的 guard 位于 pasteboard、历史载入、清理与监控之前；测试缓存目录先创建 `temporaryDirectory/GourdClipboardTests-<PID>-<UUID>` 再返回，随后才是生产 Documents 分支。PID 与 UUID 隔离进程并防历史临时内容复用，代价是留下无真实用户数据的测试临时文件夹，交给系统清理。下载管理器 init 与两处监控入口最先返回，不请求权限或打开 Downloads。此隔离针对线程采样发现的蓝牙/文件访问启动旁路，生产路径不变。

工作流单入口 `bash .workflow/calendar-interaction/verify.sh` 依次执行启动隔离 preflight、全量 unit、全量 UI、两套 Python 回归、Release 构建、diff 与退出文案核对；preflight 失败不得启动测试宿主。保留命令与日志管道退出码，最终导出 xcresult summary/tests/截图附件；导出失败不能标成功。结果校验要求非空、`passed == total > 0`、failed/skipped/expectedFailures 均为 0，测试树每项都为 Passed 且计数一致；UI 实际唯一名字集合必须与源码全部 16 例完全一致。编译、runner 错误条目、跳过或 synthetic 校验样本都不能计为 UI 通过。

## 明确不做

不实现复杂重复规则、邀请/参会人维护、提醒完整编辑、日历管理、跨进程草稿恢复；不自动保存草稿到 EventKit，不写真实用户数据做测试，不安装/替换用户当前应用，不推送或发布。

## 实际交付

T1–T5 的功能及 T6 测试代码已本地提交；本节与两份指南按 `69bb3a44` 的源码回写，旧方案顶部已声明覆盖。没有安装替换用户当前应用、推送或发布。界面验收阻塞仍在，不能据以下实现清单判定全部交互已经实测通过。

| 交付 | 实现与提交 |
|---|---|
| T1 安全记录写入与今天快照 | `188c08aa`、`170fa526`：服务协议、真实 ID、同 store 写前权限/记录限制复核、仅写授权新建兼容、重复提醒完成兼容及独立 `todayEvents` |
| T2 单草稿会话与内存夹具 | `28af8f15`、`c2b338c2`：路由/来源/锚点、单稿基线与确认、代数与在途任务、退出裁决、同一内存后端与失败/延迟注入 |
| T3 右栏页面 | `65f22333`、`dc9b2867`：列表/全文详情/编辑替换，日期与目标控件，普通日程保存/确认删除、受限记录系统入口，新增与既有记录权限分开 |
| T4 首页完整清单 | `9366a099`：固定计数、全量分组滚动、ID 去重、独立完成与详情、隐藏完成行仍保留总量、来源与邻近锚点恢复 |
| T5 焦点、锁屏与普通退出 | `7a4c0d30`、`fca477dd`：页面所有权与多窗口互认、局部离开暂存、提交保护、锁屏先暂存再收回、退出/重启、真实夹具双就绪入口及本地化 |
| T6 验收代码与启动隔离 | `d02ca836`、`69bb3a44`：保留旧 2 例并追加 14 例 UI，真实 tab AX 标识、一次失败注入、蓝牙/Clipboard/Downloads 隔离，首页计数断言数字边界；完整 wrapper 拒绝缺失、跳过与非 Passed 用例 |
| T7 当前说明 | 本文件回写精确接口、交付和限制；[36](36-calendar-cards-and-add.md) 保留历史并提示覆盖；[组件指南](guide/modules.md) 与 [手册](guide/README.md) 写现行操作、系统维护边界及草稿生命周期 |

**当前实测（2026-10-11）**：原始记录在 `.workflow/calendar-interaction/reports/T6.md` 及对应日志、退出码、xcresult 中；未用文档回写替代验收。

| 检查 | 实际结果与证据 |
|---|---|
| 已完成的两轮全量 XCTest | `T6-unit-isolated`、`T6-unit-final` 均 exit 0，**各 651/651 通过，failed 0、skipped 0**；对应最终生产源码及 PID+UUID 隔离代码，覆盖写入守卫、日期端点、单稿/异步/退出状态、所有权及首页数据与锚点等；这是单元证据 |
| `69bb3a44` 后全量复验 | 此提交仅改 UI 计数断言。`T6-unit-69bb3a44` 中最终 UI 源码 SwiftCompile 成功，unit host 在 `_prepareTestConfigurationAndIDESession` 等待超过 3 分钟仍无 case 启动；仅中止自有测试进程，exit **143 / BUILD INTERRUPTED**，该轮未通过。xcresult 未完成，缺 Info.plist，summary 提取 exit 64，不能生成该轮计数 |
| Python 回归 | `python3 -m unittest tests.test_privacy_configuration tests.test_timer_lifecycle` exit 0，**7 例通过** |
| Release | 最终 `sh tools/build.sh`（`T6-release-isolated`）exit 0，BUILD SUCCEEDED，产物 `~/Library/Developer/Xcode/Gourd/Build/Products/Release/Gourd.app`；未安装或运行 |
| 16 例 UI | 源码编译成功，**实际 UI 用例执行 0，未通过**。最新隔离 probe exit 65：runner 在启用 automation mode 时等待 60 秒后超时；summary 的总 1/错误 1 是初始化错误条目，不是执行了一个用例 |
| AX 与截图 | 最新 probe 未进入夹具宿主；附件导出 exit 0 但 `no matching attachments`，只有空 manifest，**没有真实 AX 探测结果或 UI 截图** |
| 完整 wrapper | **尚未通过**。preflight、结果校验和拒绝假 green 的自检分别通过，但全量 UI 与完整单入口仍待系统自动化恢复后执行；本地 synthetic 样本仅证明拒绝行为 |

先前两次 probe 的 `LocalAuthentication Code=-4 / System authentication is running.` 与最新 automation mode 超时是分开的失败，不能混作同一次原因。下一步需取得真实 AX/focus、执行全部 16 例并核对截图、通过完整 wrapper，再同步本节；T6 与全局验收保持待完成。

## 已知限制

- 草稿只在本次进程存活期间保留，切页、收回与锁屏不落盘；崩溃或强制结束不能恢复。普通退出保护只针对有修改的草稿，正在提交则先等待同一操作。
- 系统应用打开后由用户完整维护，回到岛内通过已有刷新链路读取；本轮未用真实账户验证同步，也未读写真实用户日历/提醒做测试。
- 原生日期弹层、目标菜单的 Esc 次序、非激活窗口焦点、实际收回/恢复及普通退出提示尚未取得 UI 证据，651 单元通过不能证明这些系统交互通过。AX 类型和全部 UI 断言仍需真实 probe 核实。
- 物理锁屏与多屏设备未纳入本轮自动验证；已有生命周期单元检查只证明状态与调用顺序，不能代替设备实测。
- 定时与全天转换保留日期范围，全天切回定时使用首日 09:00 / 最后日 10:00，原时刻需手工恢复；岛内不维护提醒完整字段、重复规则、会议邀请或日历管理。
- 旧浮层与局部 quick-add 组件仍保留给未启用的历史宿主，当前首页与日历页走本文件的共享会话入口；阅读旧 [36](36-calendar-cards-and-add.md) 时以顶部覆盖说明为准。

## 验收标准

- 9 项与 30 项今天数据都可滚到最后；无按标题去重或提醒重复；浏览其他日期不影响首页。
- 完成圈不打开详情，写失败原状保留；返回恢复来源与锚点。
- 详情长备注可读到底，右栏不覆盖列表；普通事件修改/删除成功、复杂/只读拒绝。
- 创建/编辑保存真实记录后进入详情，失败可重试；跨日与全天端点正确。
- 暂存、切页、浏览日期、收回、锁屏、冲突选择、退出都符合单草稿规则；异步结果不污染新上下文。
- XCTest、DEBUG fixture UI 测试、Python 回归与 Release 构建通过。真实系统账户同步、强杀恢复和物理锁屏/多屏设备不在自动验证范围，须在交付说明中列明。

## 决策摘要

| ID | 决策与来源 | 理由 |
|---|---|---|
| D-01 | 用户：首页全量滚动、分组、固定计数头、圈完成及标题详情 | 事项不能被截断且轻量动作容易发现 |
| D-02 | 用户：详情/编辑替换右栏，固定导航与动作，长内容滚动 | 消除覆盖和内容看不全 |
| D-03 | 用户：普通可写日程岛内维护，复杂维护交系统 | 控制岛内操作范围与误写风险 |
| D-04 | 用户：新建/编辑明确字段、保存回详情、失败保留 | 使操作结果与错误可理解 |
| D-05 | 用户：返回暂存、取消确认、来源与草稿目标稳定、单稿冲突选择 | 防误丢和误改日期 |
| D-06 | 用户：浏览可收回，输入/菜单/提交保护，离开暂存、锁屏强制收回 | 保留快速查看与输入安全 |
| D-07 | 用户：内存草稿、普通退出保存/放弃/取消 | 无持久化草稿但保护正常退出 |
| D-08 | agent：同 store 写前复核、真实 ID 返回、今天独立快照 | 过期 UI 与相同标题不能成为写入依据 |
| D-09 | agent：可注入会话写入器、DEBUG fixtures、本地签名测试 | 外部证据不触碰真实用户数据 |
| D-10 | agent：更新使用指南并标注覆盖旧方案 | 避免两个相互冲突的现行交互说明 |
| D-11 | agent：同一在途稿恢复可接收结果，新值保留且新建记录绑定真实 ID | 避免成功后空编辑页、失败不可见或再次保存重复建记录；页面提交期间仍禁用输入 |
| D-12 | agent：受控日期弹层与原生目标菜单；全天转定时采用可见的09:00/10:00默认值 | 所有权可准确上报，转换保留日期跨度；代价是原定时值需手工恢复 |
| D-13 | agent：夹具只启动日历与待办，生产模块配置suite不写不清 | 独立app标识不能隔离固定模块suite；减少测试对真实配置的影响 |
| D-14 | agent：保留旧布局纯函数，真实首页用全量入口；完成错误独立，隐藏行不减少统计总量 | 兼容旧调用且避免错误串页；夹具额外完成日期只用于模拟既有统计窗口 |
| D-15 | 用户委托控制器审核：T5接受额外本地化目录文件，仅四个退出文案键 | 退出提示与行为一并交付；超五文件的计划警告由独立语义及代码审查覆盖 |
| D-16 | agent：局部离开仅在无聚合输入时暂停；日历窗口互认；实际AppDelegate取消旧快捷计时器 | 满足单窗口恢复条与多窗口焦点保护，防旧定时器在保护结束后再次收回；代价是窗口注册与订阅需要确定清理 |
| D-17 | 用户委托控制器审核：T6接受额外ClipboardManager/DownloadManager两文件的测试启动隔离，测试缓存目录用PID+UUID | 采样证明真实Documents/Downloads访问会阻塞并有缓存清理副作用；init/monitor最先短路且临时分支早于Documents，PID+UUID避免进程与历史内容复用。代价是增加隔离代码并留下无真实数据的临时文件夹由系统清理；源码隔离经全量单元与Release验证，完整UI仍待验，生产路径不变 |
| D-18 | 用户委托控制器审核：系统认证阻塞界面验收时，先回写已有代码与实测证据 | 文档无需自动化权限；必须明确UI未验，T6和全局验收保留待完成，不能据编译成功或单测推断界面通过 |
