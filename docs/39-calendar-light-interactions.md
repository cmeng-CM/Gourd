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

真实首页使用单一 `ScrollView`，实时 ID 绑定保留在该滚动视图上；`ScrollViewReader` 在 `onAppear` 明确恢复会话保存的原锚点。内部完整 `VStack` 注册滚动目标，两组 `ForEach` 仅遍历各自条目并使用原始 `recordID`，不改 DTO 的带前缀 `ScheduleEntry.id` 或历史纯函数接口。30 项限定日志曾记录保存目标24、懒布局却恢复到18；提前测量全部今日行后原9/30项返回断言通过。恢复不改成点击行，不使用固定延迟，不增加像素状态或内容容量上限。

### 焦点、收回与退出

源码：[CalendarEditorLifecycle.swift](../DynamicIsland/components/Calendar/CalendarEditorLifecycle.swift)、[DynamicIslandApp.swift](../DynamicIsland/DynamicIslandApp.swift)、[ContentView.swift](../DynamicIsland/ContentView.swift)。生命周期复用 VM 的 `setAutoCloseSuppression(_:token:)` 和独立滚动抑制令牌，窗口销毁先释放本页 UUID；无任何聚合输入时才暂停编辑路由。窗口之间及其子窗口互认，真正外部离开才全局暂停；MainActor 同步完成检查和暂停，提交任务仍继续，宿主在页面销毁/切 tab 后保留提交保护。

`CalendarEditorLifecycle.closeForLock(session:closePanels:)` 先 `suspend()`，再关闭全部屏幕面板；`CalendarShortcutCloseProtection` 由实际 AppDelegate 实例注入取消闭包，在编辑/提交入场时取消旧快捷键收回定时器。`CalendarTerminationController.resolve(session:choose:restart:) async -> Bool` 合并重复退出裁决，`requestRestart()` 标记重启；AppDelegate 的 `applicationShouldTerminate(_:) -> NSApplication.TerminateReply` 先返回 `.terminateLater`，决策完成再回复。只有允许退出后才启动重启实例。

新增界面文案在 `Localizable.xcstrings` 提供 `en`、`zh-Hans`；四个退出提示键通过 `String(localized:)` 在真实 AppDelegate 取值。`ContentView` 在 `GourdNotch` 标识前使用 `.accessibilityElement(children: .contain)`，让根容器与页面子标识独立；保留真实布局，不能据 AX 根修复推断菜单、日期或退出已经通过。

### DEBUG 夹具与验收入口

源码：[CalendarInteractionFixtures.swift](../DynamicIsland/helpers/CalendarInteractionFixtures.swift)、[DynamicIslandUITests.swift](../DynamicIslandUITests/DynamicIslandUITests.swift)。`--uitesting` 启用 DEBUG 夹具，默认 30 条（日程 10、提醒 20），`--calendar-fixture-count=9` 为 9 条（日程 3、提醒 6），包含普通及五类受限日程、长备注。`--calendar-write-failure` 永久失败，`--calendar-write-failure-once` 仅下一次写入失败，`--calendar-write-delay-ms=N` 延迟（上限 60000 毫秒）；失败在修改记录字典前抛出，一次失败标志在锁内消费。

`CalendarInteractionFixtures.backend: CalendarInteractionMemoryService` 实现 `CalendarServiceProviding`，所有写入与刷新共用锁保护的同一字典，完成日期元数据也在同一锁下。后端 `allRecords() -> [EventModel]` 供 TodoStore 读取，`recordSystemOpen(_ id: String)` 只记录跳转，不启动真实系统或第三方应用；补 `createTodoReminder(title: String, due: Date?, listID: String? = nil) async throws -> EventModel`、`deleteReminder(id: String) async throws` 供既有待办模块测试调用，无日期用 `.distantFuture` 并在读回待办时映射为 nil。Manager 初始化直接选内存服务，跳过 EventKit 观察与真实授权读取；TodoStore 所有夹具读取/写入先短路真实调用，生产 `EKEventStore` 延迟初始化。

测试 app/unit/UI 包按 `com.cmeng.gourd.calendar-tests.$(PRODUCT_NAME:rfc1034identifier)` 分开标识，保留项目 `Gourd Local` 签名，不覆写 `CODE_SIGN_IDENTITY`。UI 分支在 VM/coordinator 属性构造前清自身隔离持久域并配置测试标准偏好，只启用 config 为 nil 的日历与待办；DEBUG 非 UI 单元宿主只在当前 bundle 具有 `com.cmeng.gourd.calendar-tests.` 前缀时清自身持久域一次，再保留 Clock/DDC/Lunar 四键 volatile 门控。不会用空 `moduleEnableOverrides` 覆盖 argumentDomain，也不清生产、普通 Debug 域或固定模块 suite；窗口与 bootstrap 双就绪后由 `CalendarFixtureReadiness` 打开真实首页并发布 `calendar-fixture-ready`，UI helper 再等待真实待办行，未另建演示宿主。测试模式跳过系统 HUD/Lunar 启动与退出恢复，提前关闭 DDC 与 `mirrorSystemTimer`，避免外部应用 suite 写入及真实 Clock 域读取。

UI 使用显式 `XCUIApplication(bundleIdentifier: "com.cmeng.gourd.calendar-tests.Gourd")`，输入前以公开 `NSWorkspace.runningApplications` 要求唯一隔离进程，并将公开 AX 根 PID 与该进程 PID 核对；身份失败停止输入。hover、click、scroll、type、quit/Esc 与 teardown 的 terminate 均消费此守卫，不用私有 KVC，也不关闭生产实例绕过同名。标题替换缓存真实字段，用 `field.typeKey` 发送 Cmd+A，保留真实 `typeText` 与精确 value 断言。长备注在 macOS AX 中读取 `StaticText.value`，用原末句的 `value CONTAINS` 查询，尾标可见、固定按钮及返回来源断言保留。

测试 host/fixture 在蓝牙管理器 init 最前端返回，`batteryReader` 改为 lazy，不构造 CBCentralManager 或启动初始扫描、观察、轮询。剪贴板 init/startMonitoring 的 guard 位于 pasteboard、历史载入、清理与监控之前；测试缓存目录先创建 `temporaryDirectory/GourdClipboardTests-<PID>-<UUID>` 再返回，随后才是生产 Documents 分支。PID 与 UUID 隔离进程并防历史临时内容复用，代价是留下无真实用户数据的测试临时文件夹，交给系统清理。下载管理器 init 与两处监控入口最先返回，不请求权限或打开 Downloads。此隔离针对线程采样发现的蓝牙/文件访问启动旁路，生产路径不变。

工作流单入口 `bash .workflow/calendar-interaction/verify.sh` 依次执行启动隔离 preflight、全量 unit、全量 UI、两套 Python 回归、Release 构建、diff 与退出文案核对；preflight 失败不得启动测试宿主。保留命令与日志管道退出码，最终导出 xcresult summary/tests/截图附件；导出失败不能标成功。结果校验要求非空、`passed == total > 0`、failed/skipped/expectedFailures 均为 0，测试树每项都为 Passed 且计数一致；UI 实际唯一名字集合必须与源码全部 16 例完全一致。编译、runner 错误条目、跳过或 synthetic 校验样本都不能计为 UI 通过。

## 明确不做

不实现复杂重复规则、邀请/参会人维护、提醒完整编辑、日历管理、跨进程草稿恢复；不自动保存草稿到 EventKit，不写真实用户数据做测试，不安装/替换用户当前应用，不推送或发布。

## 实际交付

T1–T5 功能及 T6 测试代码已本地提交；本节按 `3ac03dba` 回写，生产功能源码最近变化为 `2b22b670`，之后仅调整详情测试的 AX value 查询。没有安装替换当前应用、推送或发布。现已取得真实 UI、AX、截图和录屏；完整16项与全局验收仍未通过，不能由定向通过拼成全套成功。

| 交付 | 实现与提交 |
|---|---|
| T1 安全记录写入与今天快照 | `188c08aa`、`170fa526`：服务协议、真实 ID、同 store 写前权限/记录限制复核、仅写授权新建兼容、重复提醒完成兼容及独立 `todayEvents` |
| T2 单草稿会话与内存夹具 | `28af8f15`、`c2b338c2`：路由/来源/锚点、单稿基线与确认、代数与在途任务、退出裁决、同一内存后端与失败/延迟注入 |
| T3 右栏页面 | `65f22333`、`dc9b2867`：列表/全文详情/编辑替换，日期与目标控件，普通日程保存/确认删除、受限记录系统入口，新增与既有记录权限分开 |
| T4 首页完整清单与恢复修复 | `9366a099`、`6854a086`：固定计数、全量分组滚动、独立完成与详情；完整今日布局测量，Reader/onAppear 恢复保存的原 ID 锚点 |
| T5 焦点、锁屏、普通退出与测试入口 | `7a4c0d30`、`fca477dd`；`739cd4cc` 保留独立根/子 AX 标识，`2b22b670` 仅隔离单元宿主启动清自身 UI seed，保留真实测试写入 |
| T6 验收代码与启动隔离 | `d02ca836`、`69bb3a44`：16项 UI、启动隔离与严格结果校验；`cd93f1f8` 显式 AUT/PID 守卫及字段 Cmd+A；`3ac03dba` 按真实 AX value 核对长备注原末句 |
| T7 当前说明 | 本文件回写接口、交付、版本化证据及限制；[36](36-calendar-cards-and-add.md) 保留历史；[组件指南](guide/modules.md) 与 [手册](guide/README.md) 说明现行操作及验收状态 |

**实测记录（2026-10-11）**：原始命令、退出码、xcresult、AX 与附件留在 `.workflow/calendar-interaction/reports/`。各轮结果独立列示；文档回写不替代验收。

| 版本／运行 | 实际结果与证据 |
|---|---|
| 历史两轮全量单元 | `T6-unit-isolated`、`T6-unit-final` 各 exit0、651/651 Passed、failed/skipped/expectedFailures 0。第一轮 Clipboard 临时目录仅 PID，第二轮覆盖最终 PID+UUID；两轮都早于后续首页/测试域修复 |
| `69bb3a44` 后中断复验 | `T6-unit-69bb3a44` 编译最终测试源码后，host 等待 XCTest 配置会话，无实际case；中止自有进程，exit143、BUILD INTERRUPTED。未完成 xcresult 缺 Info.plist，summary 提取 exit64；该轮不通过 |
| `739cd4cc` 完整 UI／单元 | `T6-ui-final-739cd4cc` 全16实际执行：4 Passed、12 Failed、0 skipped/expectedFailures，exit65；同版本 unit 650 Passed、1 Failed，唯一失败为 kernel bootstrap（7个断言，仍是1个case）。截图与 AX 已存在 |
| `6854a086` 首页定向回归 | `T4-anchor-measured-ui` 原9/30两例整例 Passed，exit0、0 skipped/expectedFailures；两份返回后 AX 的末项均在真实视口内。不是完整16项结果 |
| `2b22b670` 同域单元复验 | `T5-fixture-domain-unit` 紧接上述 UI 同域 seed，651/651 Passed、0 failed/skipped/expectedFailures，exit0；原 Takeover64项及 kernel bootstrap Passed。不是最新完整16UI后再次运行单元 |
| `2b22b670` 最新完整16UI | `T6-ui-current-2b22b670` **16实际执行、6 Passed／10 Failed、0 skipped/expectedFailures，exit65**；summary/tree 名称集合与源码16声明完全相同。9/30、首页失败保持、五类受限日程入口和旧2例整例通过；失败进度见下表 |
| `3ac03dba` 详情定向复验 | `T6-notes-value-3ac03dba` 原详情完整case **1 Passed／0 Failed、0 skipped/expectedFailures，exit0**，实际23.816秒；原备注末句 value 查询、尾标可见、固定按钮及 Back 返回首页均通过。不能与上一轮拼成新的7/16通过套件 |
| Python／Release | `T6-python-current-2b22b670` 两模块7项 Passed、exit0；`T6-release-current-2b22b670` BUILD SUCCEEDED、exit0，产物 `~/Library/Developer/Xcode/Gourd/Build/Products/Release/Gourd.app`，未安装或运行。之后只有测试查询变更 |
| AX／截图／录屏 | 最新完整16UI导出214附件、12张 keepAlways PNG，目录 `reports/screenshots/T6-ui-current-2b22b670/`；详情定向复验也有真实附件。旧认证失败时0case/空附件是历史状态 |
| 完整 wrapper／全局 | **未通过**。preflight、各gate、结果拒绝校验有独立证据，但未获得全部16项成功及完整单入口exit0，尚未最终终审/指纹验收 |

最新完整16UI中的失败范围与详情单例复验分开记录：

| 范围 | 已观察／仍未验 |
|---|---|
| 8个输入case：新增延迟保存、编辑保存删除、脏稿确认、返回恢复与冲突、永久失败重试、同稿第二次保存、Finder离开、普通退出取消 | 已进入编辑并完成标题点击、Cmd+A及身份守卫；在 `field.typeText` 前重查时标题消失，最终 AX 为列表与继续编辑草稿。各case后续保存、删除、确认、重试、离开与退出步骤未执行，不能判它们已通过或已证产品写入失败 |
| `testAccessibilityProbe` | 目标菜单 Esc 后编辑页仍存在的断言通过；日期按钮 isHittable 失败，日期点击及后续 Esc 未验 |
| `testDetailFullNotesAndHomeAnchor` | 完整16UI旧 label 查询失败；改 value 查询后的原单例整例通过。其余上述9个UI用例尚未通过，仍需完整套件复验 |

系统认证先前阻挡runner，但用户认证后已恢复实际用例执行。用户明确将系统设置来源调查留待后续；当前输入页暂存及日期不可点击的根因未确认，不继续改设置或把它写成已证根因。下一步仍须解决剩余验收阻塞、执行全部16项并核对附件、通过完整 wrapper 和独立终审，再更新本节；停止来源调查不豁免本轮验收。

## 已知限制

- 草稿只在本次进程存活期间保留，切页、收回与锁屏不落盘；崩溃或强制结束不能恢复。普通退出保护只针对有修改的草稿，正在提交则先等待同一操作。
- 系统应用打开后由用户完整维护，回到岛内通过已有刷新链路读取；本轮未用真实账户验证同步，也未读写真实用户日历/提醒做测试。
- 已有首页9/30全量滚动、完成、详情返回与失败保持，以及五类受限入口的真实UI通过；长备注原单例也通过。普通改删、新增/保存失败重试、草稿冲突、Finder收回恢复和退出仍被输入前失败阻断，日期弹层未通过，不能由651单元通过推断这些系统交互成功。
- 首页完整 `VStack` 的初始测量/渲染成本随今日条目数增长；9/30项真实通过不等于超大清单性能已验证。内容没有容量上限。
- 最新完整16UI summary保留27条 runtimeWarnings：16条主线程方法调用、11条view更新内发布；首页定向两例有同类4条，详情定向有2条。旧739日志也已有两类警告，具体来源未确定，不归因本次锚点修复，不以Passed忽略。
- 物理锁屏与多屏设备未纳入本轮自动验证；已有生命周期单元检查只证明状态与调用顺序，不能代替设备实测。
- 定时与全天转换保留日期范围，全天切回定时使用首日09:00／最后日10:00，原时刻需手工恢复；岛内不维护提醒完整字段、重复规则、会议邀请或日历管理。
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
| D-18 | 用户委托控制器审核：验收受阻时先回写已实现代码与实际证据 | 初期阻塞为系统认证，目前已有实际UI但未全通过；文档应同步当前版本/失败进度，T6和全局验收仍待完成，不能据编译、单测或定向通过推断全套通过 |
| D-19 | agent／独立审核：根AX使用contain保留子标识 | 根标识曾覆盖子标识；保持真实布局与查询，代价是新增根无障碍容器 |
| D-20 | agent／独立审核：显式隔离AUT，公开bundle/PID/AX交叉核验，字段级Cmd+A | 旧同名快照曾落生产PID；未知身份停止输入，原字段精确断言保留，代价是每动作身份查询；此修复没有证明输入页后续失败根因 |
| D-21 | agent／独立审核：完整今日VStack测量，Reader/onAppear恢复原ID锚点 | 原30项保存24却由懒布局恢复到18；原9/30真实通过。代价是初次测量全部今日行，不限制容量、不改成点击行或加固定延迟 |
| D-22 | agent／独立审核：非UI隔离单元宿主仅启动时清自身持久域 | 前轮UI seed压过默认模块启用；同域后651通过。代价是专用测试域每次启动重置，不清生产或固定suites，不用volatile空override遮蔽后续写入 |
| D-23 | agent：详情末句断言按真实macOS AX value查询 | StaticText原长备注位于value；保留原END源句、可见尾标、固定按钮和返回断言，原单例已通过。仅换正确读取字段，不作为其余UI通过或全套通过依据 |
