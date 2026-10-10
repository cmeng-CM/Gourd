# 首页块高度改为按内容申报 + 四块形态改判 + 首页日历行与面板日历页解耦

| 项 | 值 |
|---|---|
| 状态 | 已实现（真人上屏复核待做） |
| 最后更新 | 2026-10-10 |
| 关联来源 | 用户 2026-10-10 反馈（四条界面反馈 + 一条补充 + 一条机制 bug）：前台应用「开镜子显示得多、关了显示得少」、通知「只能显示几条？不能显示内容」、统计「就三项占很大的区域」、首页布局「重新设计」、待办「应该显示今日日程」+「显示区域过小」、日历「两个开关关一个就都关了」；本文件 §决策摘要 D-01…D-07。承接 docs/28 §4（单条流）、docs/29 §做法 机制四/机制六（块高与档位）、docs/26 §做法 机制六/机制七（分带 → 形态）、docs/22 §接口与数据形状 4（前台应用块）、docs/32 D-20…D-24（内容内缩与顶部让位）、docs/21（`＋N` 诚实性）、docs/24 §已知限制 3（日历两处共用一个开关——本批解耦） |
| 工作流 | `.workflow/p12-home-layout-v2/` |

> **怎么读**：§背景与目标 / §备选与取舍 / §明确不做 是这场改动的判断依据；
> §接口与数据形状 是参考型小节（执行者与机器查考），人审可跳过；
> §已知限制 / §实际交付 是留给后来人的。

**读者分界**：§一句话方案 / §背景与目标 / §备选与取舍 / §明确不做 / §验收标准 / §决策摘要 给人读；§接口与数据形状 / §做法 是给执行者与模型的契约，边界按 **Always / Ask first / Never** 三档写在各条里。

## 一句话方案

首页「能看到多少内容」原先由**同一行里有没有大块（镜子）**间接决定（行高 = 该行最高块，块内按拿到的高算行数）；本批把块高改为**块自己申报**（新钩子 `homeBlockHeight`），四块（前台应用 / 通知 / 统计 / 待办）按各自内容答一个固定高——于是「显示多少」只由块自己决定。同时把待办块的今日清单扩成**今日日程 + 今日待办**（同一清单、两种行形态）、通知改两行式（正文可见）、统计收成单行、**首页日历行与面板日历页解耦**（两处各关各的）。

## 背景与目标

**问题现状**（用户 2026-10-10 六条反馈 + 代码查证）：

| # | 用户原话（要点） | 代码成因（查证结论） |
|---|---|---|
| 1 | 前台应用：开镜子显示得多、关了显示得少，「无论镜子开启与否都要显示全」 | 首页是**单条流**（`HomeFlowLayout`）：**行高 = 该行最高块**，块高由宿主按形态给（大块 140 / 紧凑 96）。镜子（大块）与前台应用同处一行时整行被顶到 140，前台应用块按「拿到的高 − 当前行」算网格行数（`FrontAppGridBudget.rowCount`）→ 3 行；镜子关掉后行高掉到 96 → 2 行。**显示多少由邻居决定** |
| 2 | 通知「只能显示几条？而且还不能显示内容」 | 行数写死 `maxListRows = 3`；每行只有「App 名 · 标题」一行，`NotificationItem.body`（正文）在数据里但首页块不画；块高还是紧凑档 96 |
| 3 | 统计「一共就三项，结果占了很大的区域」 | 三环形态（环 46 + 标签）内容约占 68pt，块高却申报 96；宽度声明 220/300 也让它在宽面板里占一大片 |
| 4 | 首页组件的布局「要重新设计下，先思考下怎么处理」 | 病根是 1/2/3 共用的那条：**块高被钉死在两个常数上**，块不能按内容要高度 |
| 5 | 待办「应该显示今日日程，而不是光待办」+「显示的区域过小」 | 首页块画的是待办聚合（表头「今天 已办/总量」+ 今日待办清单），数据源是提醒事项（`TodoStore`），**完全不读日历**——今天没有待办时就是「今日 0/0 · 今日无待办」，而日程（如「国庆节（班）」）只在下方整条日历行里 |
| 6 | 日历「虽然是两个开关，但关一个就都关了，这个地方应该是分开控制的」 | `CalendarModule.takeoverEnableKey == showCalendar`（接管口径，docs/24 §已知限制 3 点名接受的耦合）：**同一颗上游键同时管首页日历行与面板日历页** |

**预期结果**：块显示多少内容只由块自己决定（开关镜子不再影响前台应用的图标数）；通知能读到正文；统计不再占一大片；待办块能看到今天的日程；日历两处各关各的。

**承接关系**：本批**改判** docs/29 D-10 的「大块档高度是选定的 140」——那条仍成立（镜子仍靠它），但**紧凑块的 96 不再是四块的实际上限**（它们各自申报）；改判 docs/26 机制八（统计三环 → 单行紧凑）；改判 docs/22 的「画几格由块宽高算」（→ 固定 4 列 + 申报高）；改判 docs/24 §已知限制 3（日历两处解耦）。**不动**：单条流的换行与丢块语义（`HomeFlowLayout` 的三条规则）、`＋N` 诚实性、镜子 / 音乐 / 进度三块的形态与声明、日历行与月历网格本身。

**关键约束**：面板高度链（`PanelAutoHeight` / `PanelContentHeight` 账本）不新开第二条通路——块高进 `HomeFlowLayout.Item.height` 之后，行高与内容自然高**自动**跟着变（`naturalContentHeight` 那条链读的就是同一份 plan）。

## 备选与取舍

| 备选 | 结论 | 理由 |
|---|---|---|
| **A. 内容申报高度**（本批选的） | ✅ 采纳 | 块自己知道内容要多高（前台应用知道有几个 App、通知知道有几条）；行高取该行最大，其余块顶对齐。代价：行高会随内容变（多开一个 App 块长高一点）——与「显示全」的要求同向 |
| B. 保持固定档，只调数值（把 `maxListRows` 调大、网格行数 +1） | ❌ 否决 | 用户第 1 条的抱怨正是「开镜子显示得多」——只调数值仍是「显示多少由行高决定」，镜子那一行的老问题原样保留；待办加日程后 96 里也塞不下 |
| C. 先打样两块再推广 | ❌ 未走 | 用户在同一轮里把六条反馈一次给全，且第 4 条明确要「重新设计」；打样会多一轮往返 |
| D. 块高随可用面板高伸缩（把面板高当自变量） | ❌ 否决 | 与面板「贴内容」的既有裁决冲突（docs/29 机制六：内容是自然高、面板跟着内容走，不是反过来）；且会让「显示多少」重新变成间接量 |
| E. 固定列数 vs 固定宽度（前台应用） | ✅ 固定 4 列 | 列数固定后「装不装得下」与块宽无关（最小块宽 180 也放得下 4 列 = 108pt）；块宽只可能让列数**变少**（退化档），不可能变多——这是「开不开镜子都一样」的几何前提 |

## 明确不做

1. **不做每块的卡片底 / 描边**（docs/26 机制七与 docs/32 的口径继续有效）：本批只改高度与内容，视觉层（`homeBlockFloat()` / 玻璃板）一字不动。
2. **不做「块内滚动」**：首页块仍是「一眼看完」的定位，超出部分靠 `＋N`（整块）与固定上限（块内）如实交代，不引入 `ScrollView`（与 docs/21 同一裁决）。
3. **不做通知的按 App 分组 / 白名单**（docs/09 §5.5 的既有待办，仍挂着）。
4. **不改镜子 / 音乐 / 进度三块**：它们不申报高度（走 `.formFactor` 缺省），行为逐字不变（进度块 96 里装五档那条算术因此不受影响）。
5. **不改日历行 / 月历网格 / 面板日历页本体**：本批只解耦开关，视图与行高一字不动。
6. **不做「今日日程」的独立块**：用户口径是「直接显示就行，不用分为日程和待办两块，显示的方式不一样就可以」——两段同清单、行形态不同，不做第二个块。

## 做法

### 机制一 · 块高由块申报（本批的地基）

```
模块（GourdModule.homeBlockHeight）
   │  .formFactor（缺省，行为不变） / .points(n)（按内容自报）
   ▼
ModuleRegistry.homeBlockHeight(for:) ──→ HomeBandCatalog.resolve 放进 HomeBandBlock
   ▼
HomeBandedHomeView 把它交给 HomeFlowLayout.Item.height
   ▼
HomeFlowLayout.plan：行高 = 该行各块声明高的最大值（既有语义，未改）
   ▼
naturalContentHeight（同一份 plan）→ PanelContentHeight 账本 → 面板高
```

四块的申报值（都=「装下目标行数」的算式，常量收在各自模块）：

| 块 | 申报 | 算式 |
|---|---|---|
| 前台应用 | `.points(148)` | 当前应用行 28 + 间距 6 + 4 行 × 24 + 3 × 6 |
| 通知 | `.points(155)` | 表头 16 + 间距 4 + 4 条 × 30 + 3 × 5 |
| 统计 | `.points(36)` | 内容 ~22（点 12 / 文字行 14 取大者）+ 顶部让位 7 + 余量 |
| 待办 | `.points(210)` | 顶部内缩 7 + 表头 16 + 间距 4 + 6 × 30 + 3 |

**为什么「按理想宽量」而不是「按当前宽量」**：块宽是布局的结果（`HomeStripLayoutMath` 会压缩），按当前宽算高度会形成「宽 → 高 → 面板宽 → 宽」的回路；申报值是**常量**，回路不存在（前台应用的列数因此固定 4，见备选 E）。

### 机制二 · 前台应用：固定 4 列 × 最多 4 行

`FrontAppGridBudget` 从「宽决定列、高决定行」改成**固定几何**：列数恒 4（宽只可能让它变少）、行数上限 4、块高申报 = 装满 4 行的高。装不下的尾部格子在行尾给一个 `…`（悬停显示还有几个），不静默丢——与 `＋N` 同一条诚实性口径。

### 机制三 · 通知：4 条两行式

每条两行：第一行「App 名 · 相对时间」（10pt 弱色）、第二行「标题 · 正文预览」（11pt，单行截断）。正文来自 `NotificationItem.body`（此前首页块不读它）。完整正文仍在展开 tab 的列表里（浮层与列表的分工不变）。

### 机制四 · 统计：单行紧凑

三环（46pt）收成「指标色圆点（12pt，含用量 `trim` 弧）+ 标签 + 读数」，三项一行；宽度声明 220/300 → **220/240**、块高申报 36。恒三项、顺序、配色、读数口径全部不变。

### 机制五 · 待办：今日日程 + 今日待办（同一清单）

数据源两路：日程 = `CalendarManager.events`（**当天窗口**，与首页日历行右栏同一份数据）经 `CalendarEventFilters.filtered` 后**只留起点落在今天的那些**（`events` 的窗口跟月历选中日走，而本块的口径是「今天」）；待办 = `TodoBucketing.classify` 的今日类别（与展开 tab 同一份聚合）。

排版（`TodosHomeBlockLayout`）：日程在前（全天最前、各自按 `start` 升序）、待办在后，总数截到 `rowCount`。行形态两种：**日程行** = 日历色条 + 标题 + 时间列（视觉词汇与 `CalendarEventCard` 同族，收小到一行 30pt）；**待办行** = 状态圈 + 标题 + 已过期红字（原样）。空态判据 = 有完整授权 + 有一行位置 + 日程与待办都为空。

### 机制六 · 日历两处解耦

`CalendarModule.takeoverEnableKey` 从 `showCalendar` 改答 **nil**（非接管）：面板日历页的启用状态改由 `moduleEnableOverrides[calendar]` 承载（设置页「面板组件」节那张卡自己那颗开关），首页那条行仍由 `showCalendar` 控制。**兼容**：`defaultEnabled: true` + 老用户盘上没有 override 键 → 键缺省即启用，升级后面板日历页照常出现。

## 接口与数据形状

```swift
// Kernel/ModuleTypes.swift（新增）
public enum ModuleHomeBlockHeight: Sendable, Equatable {
    case formFactor          // 缺省：沿用形态档高（.large 140 / .compact 96）
    case points(CGFloat)     // 块按内容自报的固定高
}

// Kernel/GourdModule.swift（新增协议要求 + 扩展缺省）
static var homeBlockHeight: ModuleHomeBlockHeight { get }   // 缺省 .formFactor

// Kernel/ModuleRegistry.swift（新增查询，每次读现问一次）
public func homeBlockHeight(for id: String) -> ModuleHomeBlockHeight

// Host/HomeStripView.swift
struct HomeBandBlock { …; let height: ModuleHomeBlockHeight }
static func blockHeight(for block: HomeBandBlock) -> CGFloat   // .points 非有限/≤0 时回落形态档
```

```swift
// Modules/FrontApp/FrontAppModule.swift（FrontAppGridBudget）
static let columns = 4
static let maximumRows = 4
static var maximumCells: Int          // 16
static var maximumBlockHeight: CGFloat  // 148（模块 homeBlockHeight 引用它）
static func cellsPerRow(forWidth:) -> Int   // min(按宽装得下的列数, columns)

// Modules/NotificationsModule.swift（NotificationsHomeBlockLayout）
static let maxListRows = 4
static let entryHeight: CGFloat = 30
static var blockHeight: CGFloat        // 155
static func sourceLabel(appName:title:) -> String   // 第一行
static func detailLabel(title:body:) -> String      // 第二行（标题 · 正文预览）

// Modules/TodosModule.swift（TodosHomeBlockLayout）
enum ScheduleEntry: Equatable, Identifiable { case event(EventModel), todo(TodoBucketing.Item) }
static let eventRowHeight: CGFloat = 30
static let maximumScheduleRows = 6
static var blockHeight: CGFloat        // 210
static func listedEntries(events:todos:hasFullAccess:rowCount:) -> [ScheduleEntry]
static func emptyStateShows(hasFullAccess:rowCount:eventCount:todoCount:) -> Bool
enum TodoText { static func eventTimeLabel(for:) -> String }   // 全体→全天；同日→9:30 – 10:30

// Modules/Takeover/StatsModule.swift（StatsRingMetrics + 声明）
static let dotDiameter: CGFloat = 12; static let metricSpacing: CGFloat = 8
static let metricInnerSpacing: CGFloat = 4; static let homeBlockTopInset: CGFloat = 7
static var homeBlockWidth: ModuleHomeBlockWidth? { min: 220, ideal: 240 }
static var homeBlockHeight: ModuleHomeBlockHeight { .points(36) }
```

**新的文案 key**（`DynamicIsland/Localizable.xcstrings`，en + zh-Hans）：`module.todos.homeEventCount`（`%d events` / `%d 项日程`）、`module.todos.homeAllDay`（`All-day` / `全天`）；`settings.modules.calendarRow.effect` 的效果行改写（不再说「同一个开关管两处」）。

## 验收标准

1. 开关镜子前后，前台应用块显示的图标数**一致**（4 列 × 3 行 = 12 个可见 + `…` 提示）；上屏核对方式：开着镜子打开首页面板截图 → 关掉镜子再截 → 两图里该块的网格行数相同。
2. 通知块显示 4 条、每条两行，第二行含正文（截断）——且标题行有相对时间。
3. 统计块单行三项，块高明显小于其他块（36 vs 96/148/155/210）。
4. 待办块顶部显示今日日程（有日程时），下面接今日待办；两者行形态不同（色条 vs 状态圈）。
5. 面板组件节里关掉日历 → 首页日历行仍在（反之亦然）。
6. 全量单测 0 失败（564 条）。

## 决策摘要

| # | 决策 | 决策者 | 理由与代价 |
|---|---|---|---|
| D-01 | **块高由模块申报**（新钩子 `homeBlockHeight`，缺省 `.formFactor` = 行为逐字不变） | 用户（「重新设计」+ 第 1 条反馈的实质要求） | 病根是「块高由宿主写死 → 显示多少由邻居决定」。代价：行高随内容活（块长高/变矮时面板高跟着变）——这是「显示全」的必然代价，且在自适应高度模式下是既有行为的一部分 |
| D-02 | 前台应用：**固定 4 列**、行数上限 4、申报 148；装不下给 `…` | agent | 列数固定才是「开不开镜子一样多」的几何前提（宽只能让列数变少）。4 列 × 24 = 108 ≤ 最小块宽 180，任何生产宽度都成立。代价：宽块不再多画列（240pt 下网格只占 108pt，右侧留白）——留白由「当前应用行 + 名称」占据视觉重心缓解 |
| D-03 | 通知：**4 条两行式**（App·时间 / 标题·正文预览），申报 155 | 用户（「不能显示内容」） | 正文一直躺在 `NotificationItem.body` 里没被读。代价：块高从 96 涨到 155（六个块里第二高），面板整体高约 +59 |
| D-04 | 统计：**单行紧凑**（点 12 + 标签 + 读数），宽度 220/240、申报 36 | 用户（「就三项占很大的区域」） | 信息量不变（三项、三色、读数），占用从 96 高 + 300 宽收到 36 高 + 240 宽 |
| D-05 | 待办：**今日日程 + 待办同一清单**（日程在前），申报 210 | 用户（「应该显示今日日程」+「显示的区域过小」+「显示的方式不一样就可以，参考日历」） | 日程数据取 `CalendarManager.events` 的当天窗口（与日历行同源），只留起点落在今天的；行形态两种（色条 vs 状态圈）。代价：该块成为首页最高的一块（210），没有日程时下半是空的（待办行顶对齐，不做占位文案） |
| D-06 | 日历两处**解耦**：`CalendarModule.takeoverEnableKey` → nil（走 `moduleEnableOverrides`） | 用户（「关一个就都关了」） | 改前是 docs/24 §已知限制 3 点名的耦合并被接受；解耦的最小改动是让模块走非接管口径——`defaultEnabled: true` 保证老用户升级后行为不变。代价：面板组件节里日历卡那行「效果」文案要改（已改）；`PanelLayoutDefaults.resetKeys` 里的 `showCalendar` 现在只重置首页行（面板那一处由 `moduleEnableOverrides` 那条覆盖，本来就在清单里） |
| D-07 | 面板高度**不新开通路**：申报高进 `HomeFlowLayout.Item.height` 之后，自然内容高与面板高自动跟随 | agent | 账本链（`PanelContentHeight`）读的就是同一份 plan；两套高度来源必然漂 |

## 已知限制

1. **块高随内容轻微变化**：通知多一条（≤4）不变高，超过 4 条也不变（截断）；前台应用开/关 App 在 ≤15 个时不变（4 行内），超过 15 个才固定截断（`…`）。**待办块最活**：日程多的时候它会顶到 210 的上限然后截断，日程少的时候下半留白。
2. **`…` 提示不可点**（前台应用）：与 `＋N` 胶囊同一裁决——做入口要先定「点了去哪」，本批不做。
3. **待办块的日程不跟随月历选中日**：口径是「今天」（用户原话「今日日程」）；月历里点了别的日期，本块仍显示今天。
4. **统计块的读数在极长值时可能被压缩**：单行 220pt 宽里 `100.0%` 量级的三组刚好放得下（`testStatsSingleRowContentFitsItsBlock` 的算式），但四位数百分比（`1000.0%`，实际上不可能）会溢出——不做防御。
5. **面板高上限 850pt**：六块全开的自然高在 700–900 之间（视 App 数与日程数），达到上限后尾部整行不画（既有「整行进出」语义）——这是 docs/29 既有行为的延续，不是本批引入。
6. **日历解耦后 `showCalendar` 只管首页行**：设置页「日历」页那颗开关的文案（`Show calendar`）未改（它管的是首页行 + 该页的其余选项），面板组件节的日历卡才是面板页的开关。**上屏复核时注意这条措辞**。
7. **未做上屏验收**：本批的观感（四块的申报高是否合适、`…` 提示的观感、单行统计的密度）需真人复核——单测只钉常量与算式，钉不住「好不好看」。

## 实际交付

- **代码**：`Kernel/ModuleTypes.swift`（`ModuleHomeBlockHeight`）、`Kernel/GourdModule.swift`（钩子 + 缺省）、`Kernel/ModuleRegistry.swift`（查询）、`Host/HomeStripView.swift`（`HomeBandBlock.height` + `blockHeight(for:)`）、`Modules/FrontApp/FrontAppModule.swift`、`Modules/NotificationsModule.swift`、`Modules/Takeover/StatsModule.swift`、`Modules/TodosModule.swift`、`Modules/Takeover/CalendarModule.swift`、`Localizable.xcstrings`（+2 键、改 1 条效果行）。
- **测试**：`ShortcutsFrontAppTests`（固定几何）、`ModuleKernelTests`（通知两行式 + 待办混合清单三族）、`TakeoverEnablementTests`（统计单行几何 + 日历解耦三档）。全量 **564 条 0 失败**。
- **文档**：本文件；`docs/guide/settings.md` 与 `docs/guide/modules.md` 的对应段落回写。
