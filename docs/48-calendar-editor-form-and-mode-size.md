# 日历面板：一个表单、显式生成、编辑档变宽

| 项目 | 内容 |
|---|---|
| 状态 | 已实现（T1–T4 落地；整体终审回写） |
| 最后更新 | 2026-10-14 |
| 关联来源 | 承接 [docs/39](39-calendar-light-interactions.md)（单草稿、保存前校验、右栏三页）与 [docs/46](46-calendar-page-text-layout.md)（页级文字布局）；本文件的设计来源是用户逐张审阅过的设计图 ④⑤（`~/workspace/temp/20261014/svg/04-calendar-panel-preview.svg`、`05-event-form.svg`）与定位报告 |
| 读者 | 实现者看「接口与数据形状」；维护者看「已知限制 / 实际交付 / 决策摘要」 |

## 一句话方案

把日历面板右栏的「新建/编辑」从**两套字段、一列排不开**改成**一个表单**（字段并排：目标+全天 / 开始+结束 / 地点+链接），删掉常驻的 5 行说明文案，把「输入即自动解析」换成**显式「生成」按钮**，并让**编辑档**这一页的自然高报到 400（左栏让位成 260pt 的「回到月历 + 当日清单」）。**可达入口是三种**（新建日程 / 新建待办 / 编辑日程）——第四种「编辑待办」在代码里不可达（见 §已知限制）。高度只在 **auto 高度档**下变成面板 452（测试桩表头）/ 456（真机，可见黑框），对应设计图 ⑤ 的 474（窗口高 = 可见黑框 + 阴影带 18）。

## 背景与目标

**问题现状**（用户 2026-10-14 实测与逐条反馈）：

- 新建/编辑时「无意义的显示内容较多，这个块本身就不大」：列表档右栏只有约 **437pt** 宽，却常驻 `仅发送此原文及参考日期/时区…`、`使用「AI 模型」设置中的默认文字模型。`、`AI 模型设置` 按钮、状态词一行、失败时两行，外加「补充信息」这个下面只挂一个「地点」的区标题。
- **日程与待办各一套版式**（字段条数 10 / 7），换个类型就要重新找位置。
- **输入即触发 AI 解析**：停止输入 800ms 就自动解析（`CalendarSourceDebouncer`），结果会合并进正在编辑的草稿；半句话必然满足不了模型的输出契约 → 报「模型返回的日程格式无效」并阻断保存。
- **编辑区太小**：约 437 × 278，一屏看不到「链接 / 备注」，用户原话「日历编辑页面也要放大，现在操作起来很不方便」。

**预期结果（按实际实现修订）**：

- 一个表单承载三种可达入口，差异只有 3 处且都在内容层：类型控件可点 / 锁定、生成行出现 / 不出现、时间块 2 格 / 1 格 + 地点有 / 无。
- 常驻文案 5 行 → 0 行（失败时才 1 行）。
- 生成由用户点「生成」或按 ⌘↩ 触发（不再自动）；打字阶段不产生任何解析与草稿写入。
- 编辑档：左栏 260pt 当日清单、两栏各钉 400；右栏编辑区宽 = 给到日历页的内容宽 − 260 − 12 − 该栏自身水平内边距（挂载宽 887 时约 611，**关系式，不写死**）。面板高只在 auto 档随内容贴高（真机可见黑框 456 / 窗口 474）。

**承接关系**：承接 docs/39 的「单草稿 + 保存前校验 + 右栏 list/detail/editor 三页」与 docs/46 的「页级文字布局/测量」；本次不改草稿模型、不改保存校验、不改会议入口（那批已在 [docs/47](47-meeting-entry-and-one-click-open.md) 完成）。**术语沿用**：`CalendarDraft` / `CalendarPanelSession` / `CalendarPanelPages` / `generationMode` / `confirmations`。

## 做法

1. **表单**（`CalendarPanelPages.editorPage`，`components/Calendar/CalendarPanelPages.swift:368`）：两列网格 —— 类型分段（新建可点 / 编辑锁定）→ 生成行（仅新建）→ 标题整宽 → `目标｜全天` → 时区信息行（条件）→ `开始｜结束`（待办只有 `截止` 一格 + 右格 `Color.clear` 占位）→ `地点｜链接`（待办无地点）→ 备注整宽 → `confirmationControls` → 授权说明。每格由 `fieldRow`（`:447`，标签在上、控件在下、占满列宽）承载，两列用 `HStack(spacing: 8)` + 两个 `.frame(maxWidth: .infinity, alignment: .leading)`。类型分段**常驻渲染** + `.disabled(draft.eventID != nil)`（`:373-379`），不再隐藏。去掉「补充信息」区标题。
2. **文案**（`:726-778`）：删 `calendar.generation.sendingScope`、`calendar.generation.model` 两行（键一并删）；`calendar.generation.settings`（「AI 模型设置」）**键保留**、从按钮降级为生成行右端的齿轮（`Image(systemName: "gearshape")`，`:753-756`，`.help` 与无障碍标签都用该键）；状态词**只在失败时**出现——失败行是一个 `HStack`：`生成失败：<generationError>`（红，`:764`）+「重新生成」（`calendar.generation.retry`，`:768`）+「改为手工填写」（`:771`）；非失败且 `generationMode == .required` 或 `.cancelled` 时只留「改为手工填写」（`:774-776`）。
3. **显式生成**（`models/CalendarPanelSession.swift` + 视图）：输入文本放**视图本地 `@State`**（`CalendarSourceGeneration.sourceDraft`，`CalendarPanelPages.swift:729`）；点「生成」（`:748`，`.keyboardShortcut(.return, modifiers: .command)`）或失败行的「重新生成」都走同一个 `generate()`（`:787-790`）= `session.commitSourceForGeneration(sourceDraft)` + `Task { await session.generateDraft() }`。编辑页**不再持有调度器**（`@StateObject sourceDebouncer` 与三处调用已摘除，`:443` 的 `.onAppear` 只留焦点口径）；`CalendarSourceDebouncer` 类保留（`CalendarPanelSession.swift:723`，生产消费者已为 0）；`sourceRevision` / `parsingID` / 草稿合并那套过期防护原样保留。
4. **编辑档尺寸**（`components/Calendar/DynamicIslandCalendar.swift` + `ContentView.swift` + `Kernel/PanelContentHeight.swift`）：日历页**按档两键**——列表 / 详情档 = `CalendarModule.moduleID`（现键不变），编辑档 = 新页键 `PanelContentHeight.calendarEditorTab`（`"calendarEditor"`，`PanelContentHeight.swift:151`，**在 `measuredTabs` 之内**，`:212`）；判据 `ContentView.calendarPanelTabKey(route:)`（`ContentView.swift:319`，与 `notesPanelTabKey(for:)` 同形），`selectedPanelTabKey` 的 `.module` 分支（`:1641-1643`）与探针的 `tab:` / `isCurrent`（`:1980-1992`）都由它派生。编辑档左栏从整月网格换成 260pt 的「回到月历 + 当日清单」（`CalendarEditorSidebar`，`DynamicIslandCalendar.swift:1269`），**两栏都钉 400**（左 `:1418` 含 `.clipped()`、右 `:1457` 按档取值），因此整页自然高 = 400。

## 备选与取舍

| 备选 | 为什么不选 |
|---|---|
| 保留自动解析、只把延时拉长 | 用户要的是「输完再生成」；半句话的解析结果必然是废的（模型输出契约要求 12 个键齐 + 合法时区） |
| 保留两套版式、只做视觉对齐 | 用户明确「不能出现两种」 |
| 编辑档左栏整栏隐藏（编辑区吃满全宽） | 会丢掉月份上下文；收成 260pt 的当日清单既省宽度又保住「回到月历」 |
| 编辑档高度由内容决定 | 在备注里打字会让面板一直长高；必须固定声明（与 docs/30 §做法 机制六 同口径） |
| `.scaleEffect` 缩放整个面板 | 文字会糊、控件失真（用户已接受的放大方案另见设计图 ⑦⑧，本次不做） |

## 接口与数据形状

**视图（`components/Calendar/CalendarPanelPages.swift`）**

| 符号 | 行 | 口径 |
|---|---|---|
| `private var editorPage: some View` | `:368` | 两列网格；常驻文案 0 行；`.padding(.trailing, 4)`（该栏右内边距 = 4） |
| `private func fieldRow(_ label: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View` | `:447` | 一格 = 标签在上 + 控件在下 + `.frame(maxWidth: .infinity, alignment: .leading)` |
| `private func generationControls(_ draft: CalendarDraft) -> some View` | `:466` | 沿用现名；返回 `CalendarSourceGeneration(...).id(session.draftIdentity)`（`:467-468`） |
| `private struct CalendarSourceGeneration: View` | `:726` | `@State private var sourceDraft: String`（`:729`）；输入框绑 `$sourceDraft`；`hasSource`（`:781`）为空时不出「生成」 |
| `private func generate()` | `:787` | `commitSourceForGeneration(sourceDraft)` + `Task { await generateDraft() }`，两步、无调度 |
| 生成行控件 | `:745-756` | 解析中 / 防抖中 → `Cancel`（`cancelSourceParsing`）；非失败且有原文 → `calendar.generation.generate`（⌘↩）；右端齿轮 → `CalendarAISettingsNavigation.open()` |
| 失败行 | `:761-777` | `calendar.generation.state.failed` + `generationError` / `retry` / `manual` |
| `private func targetPicker(_ draft:)` | `:566` | 左格标签沿用 `calendar.panel.calendar` / `calendar.panel.list`（没有新造「目标」键） |

**会话（`models/CalendarPanelSession.swift`）**

| 符号 | 行 | 口径 |
|---|---|---|
| `var draftIdentity: UUID?` | `:116` | `draftID` 的只读映射；供视图 `.id`（二次保险，权威机制是编辑页子树被卸载） |
| `func updateSourceText(_:)` | `:173` | 保留；生产侧只由 `commitSourceForGeneration` 调，仍会把状态打到 `.debouncing` |
| `func commitSourceForGeneration(_ text: String)` | `:180-184` | 同步写回原文 + **立刻**置 `.parsing`（不闪 `.debouncing`）；`guard draft != nil` |
| `func generateDraft() async` | `:188` | `await parseSource()`；不做任何调度 |
| `func parseSource()` / `parseSource(using:)` | `:203` / `:212` | 保留（测试注入用）；`sourceRevision` / `parsingID` / 草稿合并原样 |
| `enum CalendarGenerationState` | `:20` | 六个 case 都在；`labelKey` 计算属性**已删**（T4，无读者） |
| `final class CalendarSourceDebouncer` | `:723` | 类保留；生产消费者为 0（只剩 `ModuleKernelTests` 两条用例） |
| `retrySourceParsing()` | — | **已删**（与 `parseSource()` 逐字等价） |

**面板尺寸（`ContentView.swift` + `Kernel/PanelContentHeight.swift`）**

| 符号 | 行 | 口径 |
|---|---|---|
| `func calendarPanelTabKey(route: CalendarPanelRoute) -> String` | `ContentView.swift:319` | `.editor` → `PanelContentHeight.calendarEditorTab`；`.list` / `.detail` → `CalendarModule.moduleID` |
| `static let calendarEditorTab = "calendarEditor"` | `PanelContentHeight.swift:151` | 页键风格（与 `notesFixedTab` 同类）；**在 `measuredTabs` 内**（`:212`） |
| `selectedPanelTabKey` 的 `.module` 分支 | `ContentView.swift:1641-1643` | 仅当模块 = 日历，才按 `calendarSession.route` 分档；其它模块逐字仍是 `selectedModuleID ?? ""` |
| `.module` 探针 | `ContentView.swift:1980-1992` | `tab:` 与 `isCurrent` 同一枚函数派生；`isCurrent` 追加「档位一致」（切档过渡里旧档上报被挡下） |

**页面（`components/Calendar/DynamicIslandCalendar.swift`）**

| 符号 | 行 | 口径 |
|---|---|---|
| `struct CalendarEditorSidebar: View` | `:1269` | 顶部「回到月历」（`calendar.panel.backToMonth`，`:1294` → `session.showList(on:)`）+ 当日清单（`manager.events` + `CalendarEventFilters.filtered` + `CalendarEventCardList.ordered`，与列表页同一份）；日程卡只读（`:1328`）、提醒勾选走 `manager.setReminderCompleted`（`:1321-1324`） |
| `static let paneSpacing: CGFloat = 12` | `:1364` | 由 `private` 升为 internal（关系式要用同一常量断言） |
| `static let editorSidebarWidth: CGFloat = 260` | `:1368` | 编辑档左栏宽 |
| `static let editorPaneHeight: CGFloat = 400` | `:1376` | 编辑档两栏高，**400 的唯一真源**（账本用例引用它，不另立常量） |
| 两栏钉高 | `:1418` / `:1457` | 左栏 `.frame(width: 260, height: 400).clipped()`；右栏 `.frame(height: route == .editor ? 400 : monthGridHeight)`——列表 / 详情档逐字未变 |

**自然高与面板高（auto 档口径链）**：账本值 = 列高 + 表头 − 16（`sizing/PanelAutoHeight.swift:125-129`）→ 面板（可见黑框）= 账本值 + `homeVerticalPadding`(40)（`:169`）；表头 = `max(24, effectiveClosedNotchHeight)`（`:137`）。编辑档：测试桩表头 28 → 账本 412 → 面板 **452**；真机表头 32 → 账本 416 → 面板 **456**；设计图 ⑤ 的 **474** = 456 + `notchShadowPaddingStandard`(18)（`sizing/matters.swift:199`）。列表档：278 + 28 − 16 + 40 = 330（桩）/ 278 + 32 − 16 + 40 = 334（真机，+18 = 352）。**manual 档**：`panelHeight(...)` 原样返回 `openNotchHeight`（`:166`），上述换算一概不生效。

**本地化（`Localizable.xcstrings` + `tests/test_general_ai_configuration.py` 的 `LOCALE_KEYS`，三处同批）**

| 键 | 去向 |
|---|---|
| `calendar.generation.generate`（Generate / 生成） | 新造；消费者 `CalendarPanelPages.swift:748` |
| `calendar.panel.backToMonth`（Back to month / 回到月历） | 新造；消费者 `DynamicIslandCalendar.swift:1294` |
| `calendar.generation.sendingScope` / `calendar.generation.model` | 键与渲染都删（T2） |
| `calendar.panel.additional`（补充信息） | 删键（T2；不在 `LOCALE_KEYS`，它与基线逐字相同） |
| `calendar.generation.state.{idle,debouncing,parsing,ready,cancelled}` | 删键 + 删 `CalendarGenerationState.labelKey`（T4） |
| `calendar.generation.settings` | 键保留；消费者从按钮换成齿轮的 `.help` / 无障碍标签（`:755-756`） |
| `calendar.generation.retry` / `manual` / `state.failed` | 键保留；消费者分别挪到失败行的重试 / 改为手工填写 / 失败前缀 |
| `calendar.panel.kind` / `title` / `notes` / `location` / `url` / `calendar` / `list` / `start` / `end` / `dueDate` / `sourceTimeZoneFormat`、`All-day`、`calendar.quickAdd.*` | 复用（只改排列与调用位置） |

## 明确不做

- **整体面板放大与「内容缩放」倍数**（设计图 ⑥⑦⑧⑨）：用户 2026-10-14 明确「先不考虑放大的问题了」。本次**只**让编辑档这一页的自然高报到 400，列表档与其它的尺寸一个都不动。⑥⑦⑧⑨ 这批设计图**已 park**（是范围决定，不是遗漏）。
- **面板尺寸变化的丝滑过渡**（设计图 ⑧）：一并搁置；编辑档切换沿用既有的单步缓动。
- 不改会议入口（docs/47 已完成）、不改草稿模型字段、不改保存校验规则、不改列表/详情档的版式。
- 保留 `CalendarSourceDebouncer` 类本身（其它测试仍在构造），只从编辑页摘除自动调度。

## 实际交付

**交付物**

| 提交 | 内容 |
|---|---|
| `f4fd365f` + `1531cb60`（T1） | 显式生成：`CalendarSourceGeneration` 本地 `@State` 输入、`commitSourceForGeneration` / `generateDraft`、编辑页摘除调度器、`draftIdentity` + `.id`、删 `retrySourceParsing` |
| `815941d3`（T2） | 统一表单两列网格 + `fieldRow`；删 3 键（sendingScope / model / additional）、加 `calendar.generation.generate`；齿轮化 AI 设置；失败合并成一行；类型控件锁定 |
| `942e4639`（T2） | 起草本设计记录 |
| `dbe58cc0` + `4396197e` + `bdb3cab4`（T3） | `calendarPanelTabKey(route:)` + `.module` 分支 + 探针档位闸门；`PanelContentHeight.calendarEditorTab` 进名单；`CalendarEditorSidebar`（260 当日清单 + 回到月历 + 提醒勾选写回）；两栏钉 400；`paneSpacing` 升 internal；自然高口径两轮更正 |
| `0e3b4e1d` + `e1db6a7a`（T4） | 指南按新行为重写（三入口、显式生成、齿轮、失败一行、编辑档左栏）；删 5 条僵尸状态键与 `labelKey`；`LOCALE_KEYS` 同批 |

**与计划的偏离及原因**

| 偏离 | 原因 |
|---|---|
| `fieldRow` 的标签类型写成 `LocalizedStringKey`（派发正文写的是不存在的 `LocalizableStringKey`） | 拼写以真实类型为准 |
| 编辑档页键**在** `measuredTabs` 之内（文档原写「之外」） | 编辑档**有**自然高 400；放名单外等于回落手动值，与本工作流目的相反（D-10） |
| 400 的真源放在视图常量 `StandaloneCalendarView.editorPaneHeight`，`PanelContentHeight` 只拿键 | 高度属「视图声明的内容高」，放在声明者一侧才不会与钉的 400 漂 |
| 左栏提醒勾选**接真实写回**（文档原写「只读摘要」） | 空 `onToggle` 是用户可见死控件；不新造写回路径（D-11） |
| 「生成」按钮**新造键** `calendar.generation.generate`（T1 曾复用 `retry`） | 「重新生成」语义错位；T2 与本地化清单同批改（D-14） |
| 待办时间块把 `截止` 放左格、缺格用 `Color.clear` 占位；`链接` 占半宽 | 与设计图 ⑤ 的逐格小样对齐、列位置固定 |
| 保留条件行 `calendar.panel.sourceTimeZoneFormat`（整宽，设计图未画） | 源时区与当前时区不同才出现的信息行；整宽不破坏网格 |
| 文档 / 计划里的「四种入口」→ 交付三种可达入口 | 「编辑待办」不可达（见 §已知限制） |

**遗留项**

- 设计图 ⑥⑦⑧⑨（整体放大 / 内容缩放倍数 / 丝滑过渡）：**park**，见 §明确不做。
- 上屏人工复核（V8 / V9）：编辑档一屏放完（链接 / 备注可见）、切档面板变高的实际手感、齿轮与「回到月历」的观感——**均未上屏**，由人工兜底。
- `⌘↩` 在原生 `NSTextView` 聚焦时是否被文本系统先吞：只有上屏能确认（预期 SwiftUI 键等价先到按钮）。
- 「点击生成按钮 → 只解析一次」由会话层断言 + 源码检索合成，无字面点击（SwiftUI 按钮不是 `NSButton`）。
- `CalendarSourceDebouncer` 现为纯测试消费者；若将来确认不再需要，应与 T7 那两条用例同批清理。

## 已知限制

- **474 / 452 / 456 / 334 全部是 auto 高度档的口径**：账本值 = 列高 + 表头 − 16，可见黑框 = 账本值 + 40，窗口高 = 可见黑框 + 阴影带 18。manual 档下面板高由 `openNotchHeight` 说了算（本机当下 `panelHeightMode = manual`、`openNotchHeight = 697`），此时编辑档两栏仍是 400 的内容声明，但**面板不会随编辑档变高**——「编辑时一屏放完」的收益只在 auto 档兑现。
- **编辑档左栏的提醒勾选会真实写回**（`manager.setReminderCompleted`，与列表页同一条写回链路）；日程卡是只读的（`detailEnabled: false`），左栏**不**在里面编辑日程。左栏与该日列表页共用同一份数据与偏好口径（`manager.events` + `CalendarEventFilters.filtered` + `CalendarEventCardList.ordered`，含订阅 / 只读日历的条目），本栏不新增刷新调用。
- **「编辑待办」入口不可达**：`beginEdit` 硬编码 `kind: .event`（`CalendarPanelSession.swift:440-445`），详情页铅笔只对非提醒渲染（`CalendarPanelPages.swift:601-603`）。「同一表单」的第四臂只在测试里按**注入草稿**覆盖，且那份草稿不可保存（`save()` 拒绝改已保存提醒，承接 docs/39 D-03）。用户要改已保存提醒走系统「提醒事项」。
- **备注写长了仍会滚**：两栏各钉 400（右栏的 400 含它自己的页头 24 与底部动作 28，表单本体在栏内滚动），两列布局只是让**典型内容**一屏放完，不是把备注钉死。
- **编辑档左栏钉高靠「定高 + `clipped()`」**：清单条目多在**栏内**滚动，绝不顶高整页理想高（那是「面板跟着内容长」的反馈环）。
- **显式生成之后，「生成」按钮在草稿已就绪时仍可再点**（再解析一次）；失败态下主按钮让位给失败行的「重新生成」——文案不同，动作是同一个 `generate()`。
- **僵尸状态键已清理**：`calendar.generation.state.{idle,debouncing,parsing,ready,cancelled}` 五键与 `CalendarGenerationState.labelKey` 已删（视图侧自 T2 起不再渲染状态词）；枚举 case 仍在，但已无任何渲染消费者——将来若要恢复状态词，必须与 catalog 和 `LOCALE_KEYS` 同批重建。
- **齿轮「点击打开设置」只有源码级证据**（用例断言源码含 `CalendarAISettingsNavigation.open()`），无点击模拟与上屏验证。
- **`.id(session.draftIdentity)` 是二次保险、未被独立验证**：今天不存在「不卸载编辑页的同 route 换稿」路径（换稿的两条路径都先经过编辑页不渲染：冲突页占位 / `suspend()` 切走 route），真正复位输入框的是子树被卸载。
- **非日历模块逐字未变**：探针 `tab:` 对非日历模块仍是 `selectedModuleID ?? ""`，`isCurrent` 的合取语义等价；本轮无回归。
- **两档两键链路的端到端覆盖缺口**：`calendarPanelTabKey(route:)` → `ContentView.selectedPanelTabKey` → 探针 `tab:` / `isCurrent` 这条链的**首末两环缺机器可复核证据**。现有用例只到**纯函数**（直接断言 `calendarPanelTabKey(route:)` 的返回值）与**账本级**（测试里自己调 `ledger.report(...)`）两层，全仓**没有**一条「真实 `selectedPanelTabKey` 派生出键、探针按该键与 `isCurrent` 命中上报」的端到端用例。终审读码核实链路闭环、`isCurrent` 的档位闸门确实挡下旧档上报，但那是**读码结论、不是用例结论**，留作后续补测。
- **两处刻意保留、生产侧已无消费者**：`CalendarPanelSession.updateSourceText(_:)` 生产侧已无独立调用者（显式生成走 `commitSourceForGeneration`，其内部调一次），仅测试直接使用；`CalendarSourceDebouncer` 生产消费者为 **0**（计划明确保留类本身，只摘除编辑页调度）。两者均按计划保留，不做删除。
- **`updateSourceText` 仍会把状态打到 `.debouncing`**（`CalendarSourceDebouncer.schedule` 的前置条件），生产侧只由 `commitSourceForGeneration` 调、且紧接着覆盖成 `.parsing`，因此这一帧不上屏。
- **编辑档左栏的「回到月历」会静默丢掉待确认的第二份新建请求**（冲突页在场时点它 → `showList` → `changeNavigation()` 清 `pendingDraft`）；这是**既有行为、非本次引入**——与既有 `back()` 同款语义，草稿本身不丢，本轮不作修正。

## 验收标准

- 单元测试：显式生成（打字不解析、点生成才解析一次）、两列布局的字段数 / 并排关系 / 类型控件编辑时锁定、失败只一行、编辑档页键与自然高 400（账本 412 / 面板 452）、列表档 278→290 不变、编辑档左栏钉高（8 条记录仍 400）、编辑区宽度关系式（Δ 读数 = Δ 宿主宽）。
- `python3 -m unittest tests.test_general_ai_configuration` 通过（本地化增删与 `LOCALE_KEYS` 同批）。
- Release 构建通过；用户上屏复核：三种入口同一个版式、编辑档一屏放完（链接 / 备注可见）。

## 决策摘要

| ID | 决策 | 来源 |
|---|---|---|
| D-01 | 新建/编辑日程与待办共用一个表单版式，差异只有 3 处（类型可点/锁定、生成行有无、时间块 2/1 格 + 地点有无）。**执行期更正：可达入口三种**（「编辑待办」不可达，见 §已知限制） | 用户 |
| D-02 | 字段并排三组：目标＋全天、开始＋结束、地点＋链接；标题与备注整宽 | 用户 |
| D-03 | 删掉常驻 5 行文案；AI 模型设置降级为齿轮图标；失败只留 1 行 | 用户 |
| D-04 | 去掉「补充信息」区标题 | 用户 |
| D-05 | 编辑已有记录时类型控件**锁定而不是消失** | 用户 |
| D-06 | 显式「生成」按钮 + ⌘↩ 取代 800ms 自动解析；输入文本先放视图本地 state | 用户 |
| D-07 | 编辑档：左栏 260 当日清单、右栏表单；日历页按档各报自然高（列表 `monthGridHeight` / 编辑 400）。**执行期更正口径**：编辑区宽 = 宿主内容宽 − 260 − 12 − 该栏内边距（关系式）；「474」是 auto 档**窗口高**（可见黑框 456 + 阴影带 18） | 用户（设计图 ⑤） |
| D-08 | 整体放大、内容缩放倍数、丝滑过渡**本次不做**（⑥⑦⑧⑨ 已 park） | 用户 |
| D-09 | 编辑档宽度用**关系式**而非常量：左栏固定 260、编辑区 = 宿主宽 − 260 − 12；将来若做「按页宽度」编辑档随之变宽 | agent |
| D-10 | 编辑档页键用**页键风格** `PanelContentHeight.calendarEditorTab = "calendarEditor"`（与 `notesFixedTab` 同类），不按模块 id 点分派生；且该键**进** `measuredTabs`（因为编辑档有自然高） | agent（执行期） |
| D-11 | 编辑档左栏**提醒勾选接真实写回**（`manager.setReminderCompleted`，与列表页同路径），放弃计划 T3④ 字面的「只读渲染」；日程卡仍只读 | 控制器裁决（`4396197e`） |
| D-12 | 编辑档面板高的口径链（**auto 档前提**）：账本 = 列高 + 表头 − 16；可见黑框 = 账本 + 40；桩 452 / 真机 456；474 = 456 + 阴影带 18；manual 档由 `openNotchHeight` 决定 | 控制器裁决（`4396197e` + `bdb3cab4`） |
| D-13 | 显式生成的会话侧拆成同步前半段 `commitSourceForGeneration(_:)`（写回 + 同步进 `.parsing`，不闪 `.debouncing`）与 `generateDraft() async`（只触发一次解析）；`updateSourceText` 与 `.debouncing` 保留 | agent（T1 审查修复） |
| D-14 | 「生成」按钮**新造键** `calendar.generation.generate`（Generate / 生成）；`calendar.generation.retry` 降为失败行的「重新生成」 | agent（T2） |
| D-15 | 编辑档左栏的当日清单**沿用列表页同一份数据与偏好口径**（`manager.events` + `CalendarEventFilters.filtered` + `CalendarEventCardList.ordered`），不新造取数路径、本栏不新增刷新调用 | agent（T3 裁决 4） |
