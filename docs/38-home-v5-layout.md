# 38 · 首页 v5：环境带 + 今天带 + 可变流

> 批次：`p13-home-v5`。**规格 = 用户 2026-10-11 点头的 v5 设计稿**
> （`~/workspace/temp/20261011/gourd-home-v5.svg`，面板 887 × 456 = 用户当前宽度）。
> 本文件是这一版的**唯一口径源**：六块内容与尺寸、三带结构、排序模型、退出首页的两样
> （月历行 / 镜子块），以及配套的**退出机制**（模块退休、死开关清理）。改动前先读本文件。

## 背景与目标

改前的首页（docs/37 之后）是**一条可换行的流 + 一排全宽日历行**：块高由模块申报、按用户
顺序换行，日历行在流下方。七个块（音乐 / 前台应用 / 待办 / 镜子 / 工作日统计 / 通知 / 统计）
挤在一条流里，实际观感（用户 2026-10-11 圈红的截图与三轮 v3→v5 迭代）暴露四件事：

1. **一主一辅说不清**：七个块平铺，没有「常看的」与「偶尔看的」之分——用户想一眼看到的是
   环境（音乐 / 前台应用 / 系统读数）与今天（日期 / 下一个日程 / 今日清单 / 通知），
   而它们被拆散在流的换行里；
2. **今天的大字交代缺失**：「今天还剩什么、下一个日程还有多久」这类**当务之急**没有位置，
   唯一的日历行又整月铺开（用户 2026-10-11：「月历的内容和第一排的内容明显重复」）；
3. **低价值块占大块面积**：工作日统计占 347 × 220 却不产生行动（用户：「意义不大，
   特别是今日、本周这两个」）；
4. **镜子占着首页组件**，而它本来就有标题栏按钮（用户：「镜子不要占用首页组件了，
   点击右上角的镜子按钮的时候，浮动一个镜子显示」）。

**目标**（v5 定稿）：首页 = **环境带（固定第一排）+ 今天带（宿主直渲的第二排）+ 可变流
（其余块，用户可排）**。八条改动见下面的决策摘要。

## 决策摘要

| 编号 | 决策 | 一句话理由 |
|---|---|---|
| **D-01** | 首页分成**三带**：环境带（固定第一排）/ 今天带（宿主直渲）/ 可变流（其余块换行） | 一主一辅说得清：常看的两排固定，其余按用户顺序 |
| **D-02** | 环境带成员 = **音乐 + 前台应用 + 系统读数**（三块，`.environment` 区） | 用户：「环境带放第一排，这个操作频率是最高的」 |
| **D-03** | 区的归属由模块申报（`homeZone` 钩子，缺省 `.flow`）；**带内顺序仍按用户的 `homeBlockOrder`** | 区是「在哪一排」，顺序是「谁先谁后」，两者不混 |
| **D-04** | **弹性块吃富余**（`homeBlockAbsorbsSurplus`）：一行里声明的块按声明宽、富余按弹性块的 `ideal` 等比分配 | 「cpu 那三个宽度要降低，把第一排大部分内容留给前台应用」 |
| **D-05** | 今天带 = **日期行（公历 · 农历 · 节假日）+ 工作日剩余一行小字 + 下一个日程 + 倒计时**，宿主直渲、**不吃板** | 今天带是**排版**不是组件：没有交互、没有 hover，画一块板只是噪音 |
| **D-06** | 工作日剩余**降为一行小字**（只留 本月 / 本季 / 今年），原「工作日统计」模块**退场** | 用户：「意义不大，特别是今日、本周」，占大块面积价值低 |
| **D-07** | **月历退出首页**：全宽日历行（`HomeCalendarRow`）整条退休；月历入口仍是面板「日历」页 | 用户：「月历的内容和第一排的内容明显重复」 |
| **D-08** | **镜子退出首页组件**：模块不再占任何 surface；顶栏镜子按钮改为**面板内的浮动镜子**（`MirrorFloatingPreview`，不是 popover） | 用户：「点击右上角的镜子按钮的时候，浮动一个镜子显示」；popover 在非激活面板里撑不住（上屏实测 0.3s 自收，见「做法 四」）。**p17 补记**：浮层的上内缩原写死 8，小于顶栏那排图标的下沿（8 + 30 = 38）——浮层压住镜子按钮、又因 `allowsHitTesting(true)` 先吃命中，于是「再点同一枚按钮收起」点不动。现改为派生值 `MirrorFloatingPreview.topInset()` = `8 + 30 + 8` = **46**（派生自顶栏几何，含一处回退），浮层上沿落在按钮下方、不再遮挡。**上一轮为何没验出**：p13 的浮动镜子开关验收用的是 `AXPress`（按元素直接派发动作，**不经命中测试**），遮挡在 AX 下完全不体现。故「浮层盖住自己的入口」这类验收**必须用鼠标真点**（开 → 再点同一枚按钮 → 关），不能只靠 AX。**两条已知边界（独立审查指出，本批不改）**：① `topInset()` 建模的是**保守界**（前导 tab 区的 `8 + 30`），而顶栏图标排实际在 `max(24, effectiveClosedNotchHeight)` 的框里居中——当前刘海高度下净空约 8–11pt；**若将来顶栏或刘海高度变大到 H ≥ 54，这个内缩就不够了，遮挡会静默回来**，届时需要同步抬高内缩。② 回归用例（`ModuleKernelTests` 的 `testMirrorFloatingPreviewTopInsetClearsHeaderIconRow`）只钉住 `topInset` 的公式与下界，**钉不住它和顶栏真实常量的耦合**（顶栏那些数字目前是视图里的字面量，没有可引用的具名常量）——它防的是「有人把内缩偷偷改小或删掉」，不是「顶栏几何漂移」。 |
| **D-09** | 前台应用块 = **一整片图标网格**（当前应用是**第一格带选中环**，不再单开一行名字） | 「显示全部已打开的应用是硬性需求」——省下那一行给网格 |
| **D-10** | 系统读数 = **三行「圆点 + 标签 …… 数值」**（不用进度条） | 用户：「不要用进度条展示，没意义，改展现形式」 |
| **D-11** | 通知 = **最近 6 条**，仍两行式（App 名 · 相对时间 / 标题 · 正文预览），列内**铺满**；**标题按画出来的条数说**（`通知 · 最近 6 条（共 40 条）`）；**后续 p14 / [40](40-home-notifications-scroll.md)：列表不再裁剪（全部已保留条目可块内滚动），视口 6 行与块高 225 不变** | 用户：「通知改为最近 6 条」+ 宽度铺满后两行式不留空档；标题口径由用户 2026-10-11 当场纠正（改前写的是列表总数 40，与下面的 6 行对不上） |
| **D-12** | 今日清单 = 待办模块的混合清单（今日日程 + 今日待办，docs/37 D-05 起就是它），**加宽到与通知并排** | 一行两块的并排是 v5 的第三排 |
| **D-13** | `showCalendar` 键随日历行**一并退休**（设置项、搜索项、tab 可见性判据全部清理） | 不留「拨了没反应」的死开关（D-16 既有口径） |
| **D-14** | 首页 tab **恒可见**（不再是「音乐/日历/镜子至少开一个」的函数） | 环境带与今天带恒在，首页永远有内容 |

## 做法

### 一、三带结构（D-01 / D-02 / D-03）

    ┌──────────────────────────────────────────────────────────┐
    │ 顶栏（TabSelectionView + 右侧图标行，镜子按钮改浮动预览）    │
    ├──────────────────────────────────────────────────────────┤
    │ 环境带：音乐 260 │ 前台应用（弹性，吃富余）│ 系统 145       │  96pt
    ├──────────────────────────────────────────────────────────┤
    │ 今天带：10月10日 周六 · 九月初十 · 国庆节（班）  本月剩 15 天…│  56pt（无板）
    │         下一个 · 评审会 · 14:00–15:00        还有 1 小时 20 分│
    ├──────────────────────────────────────────────────────────┤
    │ 可变流：今日清单 470 │ 通知 377（两块都弹性；更多块换行）      │  行高 = 行内最高块
    └──────────────────────────────────────────────────────────┘

三带的渲染归属：

- **环境带**：宿主视图 `HomeEnvironmentBand`（`Host/HomeStripView.swift`）。名单 =
  `homeEntries` 里申报 `.environment` 的块（过 `HomeBlockCatalog.resolve` 的同一道
  内容表态），**仍是用户顺序**（D-03）——排序覆盖表一个字没改，区只决定「进哪一排」。
  行高 = 行内块申报高的最大值（与流同一条规则），今天就是三块都申报的 96。
- **今天带**：宿主视图 `HomeTodayBand`（`Host/HomeTodayBand.swift`）。**它不是模块**——
  它的数据来自三处既有来源（`Calendar.autoupdatingCurrent` / `Calendar(identifier: .chinese)` /
  `WorkdayCalendar` / `CalendarManager`），跨的是「日历 + 节假日 + 工作日」三个域，
  做成模块只会把它拆成三份。不吃板、不可排、不参与 `homeBlockOrder`。
- **可变流**：`HomeFlowView` + `HomeFlowLayout`（P4 起的那一条），名单 = 其余块。
  行为只有一处变化：**行内宽度分配多了弹性块**（D-04）。

### 二、弹性块吃富余（D-04）

`HomeStripLayoutMath` 的三条规则**一条没改**，只多一条 **①′**（只在规则 ① 命中、
即「富余」时生效）：

> **①′ 富余按弹性块等比分配**：`available ≥ sum(ideal) + gaps` 时，先给每块 `ideal`，
> 再把 `leftover = available − sum(ideal) − gaps` 按**弹性块的 `ideal`** 等比分给它们
> （向下取整到 0.5pt，与规则 ② 同一档精度）。**没有弹性块时余量留在尾部**——即改动前的行为。

为什么不是「所有块等比放大」：那样关掉前台应用后音乐块会被拉成半个面板宽（不成比例）；
为什么不是「按最大值给一块」：窄到只剩两块时最大的那块会吞掉整行。“谁是弹性的”是
**模块的自我描述**，与「我多宽」一样由模块声明，宿主不猜（同 `homeFormFactor` /
`homeBlockHeight` 的口径）。

弹性声明只有三处：前台应用（吃环境带的富余）、今日清单与通知（并排时的富余）。
**音乐 / 系统读数不弹性**（260 / 145，固定）。

### 三、今天带（D-05 / D-06）

四段文案，两条线（左对齐主信息 + 右对齐次要信息）：

| 位置 | 内容 | 来源 | 纯函数 |
|---|---|---|---|
| 左上 | `10月10日 周六 · 九月初十 · 国庆节（班）` | 公历 + `Calendar(identifier: .chinese)` + 节假日名表 | `TodayHeadline.text(for:calendar:lunar:)` |
| 右上 | `本月剩 15 天 · 本季剩 59 天 · 今年剩 59 天` | `WorkdayCalendar.spanStats(.month/.quarter/.year)` 的 `remainingWorkdays` | `WorkdayRemainderLine.text(...)` |
| 左下（大字） | `下一个 · 评审会 · 14:00–15:00` | `CalendarManager` 当天窗口里**还没结束**的下一条定时日程 | `TodayNextEvent.pick(events:now:)` |
| 右下（强调色） | `还有 1 小时 20 分` / `进行中 · 还有 40 分` / `今天没有更多日程` | 上一条 + `now` | `TodayCountdown.text(for:now:)` |

四条口径：

1. **农历与节假日名按中文输出、不分语言**：它们是中文日历的专名（`甲辰年九月初十` 翻成
   `the 9th day of the 9th lunar month` 没有意义）。周围那几段文案（`下一个` / `还有…` /
   `本月剩`）走 Localizable 的 zh + en 两栏；
2. **节假日名表只覆盖 2026**（与 `WorkdayCalendar.holidayTables` 同一个年份边界）：
   表外年份不画那一段（不画「未知」也不猜），跨年时补表；
3. **只在定时日程里找「下一个」**：全天条目不是一个「几点开始」的对象；今天只剩全天条目时
   这一行说「今天没有更多日程」；
4. **倒计时按分钟刷新**（`TimelineView(.everyMinute)` 只包住今天带，不包整页）：
   「还有 1 小时 20 分」这类文案不刷新就是错的。

工作日剩余那一行的**工作量口径**：`WorkdayCalendar` 默认工作日（ISO 一~五）+ 表内节假日。
**不再读**原「工作日统计」模块的 `workStart` / `workEnd` / `workdays` 配置（模块退场，
D-06）——这是本批的一处**能力收缩**（见「已知限制」）。

### 四、退出机制（D-07 / D-08 / D-13）

**月历行退休**（`HomeCalendarRow.swift` 整文件删除）：

- 首页不再有全宽日历行，「今日清单」由待办块承担（`docs/37 D-05` 起它就是**今日日程 +
  今日待办**的混合清单）；
- 月历入口不变——面板「日历」页（`CalendarModule` → `StandaloneCalendarView`）从
  docs/24 起就是这个孤儿视图的家；
- `Defaults[.showCalendar]` 随之退休：**设置页「日历」页那一项、`All-Day Events` 一组的三处
  `.disabled(!showCalendar)`、组件页那张「首页的日历行」卡、设置搜索项、`Home` tab 的可见性
  判据、`DynamicIslandApp` / `DynamicIslandViewCoordinator` 的两条 publisher 全数删除**。
  键定义本身留着（盘上已有的值不会被读，也不会崩）——与「删掉不是写默认值」的既有口径一致。

**镜子块退休**（`MirrorModule` 退出 `builtinModules`）：

- 它的渲染点是首页块；块退休后它**一个 surface 都不占**（不含折叠槽位、不含展开 tab）。
  保留一个「注册了但什么都不渲染」的模块只会让组件页多一张拨了没反应的卡，因此整条
  **退出内置名单**（文件与它的用例保留，可逆：把 `builtinModules` 那一行加回即恢复）；
- **镜子功能本身不变**：`showMirror` 键、形状、摄像头选择都还在「外观 → 镜子」那一页，
  采集会话仍由 `WebcamManager` 持有；
- 顶栏那枚按钮（`DynamicIslandHeader`，docs/24 起就在）从「只起采集会话」改成**弹一块浮动镜子**：
  `MirrorFloatingPreview`（200 × 200 的 `CameraPreviewView` + 深色圆角底 + 柔影）挂在
  **面板内容之上**（`ContentView` 的 `mainLayoutBase` 上、`clipShape` **之内**），显隐由
  `vm.isCameraExpanded` 决定——那个标记本来就是为镜子准备的（上游留着、此前没有消费者）。
  点一次浮出、再点一次收起（收起时停会话）。
- **为什么不是 popover**（p13 上屏实测的改判）：改前那版用的是 `.popover`，实测在**非激活面板**里
  浮层出现后 **≈0.3s 被系统收掉**（同一块面板里另外三枚 popover 也是这个处境，只是它们的入口在
  用户档位下不可达）。面板内浮层没有这条不确定性——它就在面板自己的窗口里。
- **按钮必须「按下就有可见反应」**（`toggleCameraPreview()` 的两条改动）：改前只有
  「已授权 **且** `cameraAvailable`」才起会话，其余情况一个像素都不变（实测：点了没反应）。
  现在**先翻标记**（浮层出来），摄像头可用才起会话；占位块自己会说清状态
  （未起会话 `镜像` / 被拒 `Access Denied`，点它一次即重试授权）。`.notDetermined` 那一档
  先把应用唤到前台再请求（与 `.denied` 那条先例一致），否则非激活面板里发出的请求
  不保证压得住别的窗口。

**工作日统计模块退休**（`ProgressModule` 退出 `builtinModules`）：读数搬进今天带（D-06），
块本身退场；组件页少一张卡、设置页少四行配置（`visibleScopes` / `workStart` / `workEnd` /
`workdays`）。文件与它的用例保留（同镜子的可逆口径）。

### 五、六块的尺寸与形态（D-04 / D-09 ~ D-12）

| 块 | 宽（min / ideal / 弹性） | 高（申报） | 形态 |
|---|---|---|---|
| 音乐 | 260 / 260 / 否 | 96（环境带档） | 封面 44 + 标题/歌手 + 进度条 + 时间 + 四个控制键（逐字未改） |
| 前台应用 | 300 / 434 / **是** | 96（环境带档） | 一整片图标网格：格 26（图标 22 + 2 内边距）/ 间距 4；**列数按宽**（上限 16），行数按高（上限 4）；当前应用 = 第一格 + 选中环；装不下给 `…` |
| 系统读数 | 145 / 145 / 否 | 96（环境带档） | 三行「圆点 7 + 标签 10.5 + 数值 12 等宽」纵向居中，行距 8；**无进度条** |
| 今日清单 | 420 / 470 / **是** | 225（表头 + 6 行 × 30 + 内缩 + 3） | docs/37 D-05 的混合清单（日程色条行 / 待办状态圈行），**只读**。**p15 / [41](41-home-and-calendar-scale.md)：ideal 改取 420**（与通知同值 → 该行等分） |
| 通知 | 340 / 377 / **是** | 225（表头 + 6 条 × 30 + 5 × 4 + 内缩 5） | 最近 **6** 条，两行式（App 名 · 相对时间 / 标题 · 正文预览），整条可点开 App。**p14 / [40](40-home-notifications-scroll.md)：列表不再裁剪，条目进块内竖向滚动（视口 6 行），块高 225 不变**。**p15 / [41](41-home-and-calendar-scale.md)：ideal 改取 420**（与今日同值 → 该行等分） |
| 今天带 | 占满整行 | 56 | 见「三」；**不吃板** |

行高恒 = 行内最高块（既有规则）：第三排两块都申报 225 → 两块的板等高，短的那块内容
顶部对齐、余量留在板底。

## 接口与数据形状

```swift
// Kernel/ModuleTypes.swift
public enum ModuleHomeZone: Sendable, Equatable {
    case environment   // 环境带：固定第一排
    case flow          // 可变流（缺省）
}

// Kernel/GourdModule.swift（协议要求 + 扩展缺省）
static var homeZone: ModuleHomeZone { get }        // 缺省 .flow
static var homeBlockAbsorbsSurplus: Bool { get }   // 缺省 false

// Host/HomeStripLayoutMath.swift
public struct Item: Equatable {
    public let min: CGFloat
    public let ideal: CGFloat
    public let flexible: Bool                      // 缺省 false（init 有默认值）
}

// Host/HomeFlowLayout.swift
public struct Metrics { /* … */ }                  // 不变
public static func plan(items:availableWidth:availableHeight:metrics:) -> Plan
                                                   // calendarHeight 参数与 showsCalendarRow 已删

// Host/HomeEnvironmentBand.swift（新增）
enum HomeEnvironmentBand { static let height: CGFloat = HomeFlowView.compactBlockHeight }  // 96

// Host/HomeTodayBand.swift（新增）
enum HomeTodayBandLayout { static let height: CGFloat = 56; … }
enum TodayHeadline / WorkdayRemainderLine / TodayNextEvent / TodayCountdown / LunarDateLabel / HolidayName
```

**宿主常量**：`HomeStripLayout.spacing`（块间距 8）、`HomeTodayBandLayout.height`（56）、
`HomeEnvironmentBand.height`（96）——今天带与两侧带之间的缝**仍是 8**（`HomeCalendarRow.rowSpacing`
退休后，这个数由 `HomeTodayBandLayout.rowSpacing` 承接，值不变）。

## 验收

| 判据 | 怎么验 | 结果 |
|---|---|---|
| 三带齐活、顺序对 | 上屏（面板 887 × 490，AUX 树 + 截图）：环境带三块（音乐 / 前台应用 / CPU·内存·GPU 三行）、今天带两行、流里今日清单 + 通知并排 | **通过**（证据 `.workflow/p13-home-v5/evidence/panel-887.png`） |
| 今天带四段文案 | AX 树读出 `10月11日 · 周日 · 九月初二` / `本月剩 15 天 · 本季剩 59 天 · 今年剩 59 天` / `今天没有更多日程` | **通过** |
| 弹性块吃富余 | 单测：无弹性块时余量留尾（`leftover = 442`）、一块弹性吃满、两块弹性按 ideal 等比 | **通过**（`testFlexibleItemsAbsorbTheRowSurplus`） |
| 关掉通知 → 今日清单铺满整行 | 单测：`470 + 8 + 377 = 855` 恰好吃满；更宽时按 ideal 分富余；800 时压缩不丢块 | **通过**（`testFlowDistributionAtUserPanelSize`） |
| 面板贴内容 | 上屏：auto 档面板高 **490**（含表头与内边距；= 两带 168 + 流 228 + 表头 ≈34 + 内边距 40） | **通过** |
| 死开关清零 | 组件页无「首页的日历行」卡、无镜子卡、无工作日统计卡；设置页「日历」页无「Show calendar」；`showCalendar` 键定义删除 | **通过**（`grep showCalendar` 只剩文档与历史注释） |
| 通知标题不说假话 | 上屏：`通知 · 最近 6 条（共 40 条）`，与块里画出的 6 行一致 | **通过**（`testNotificationsHomeBlockLayoutLimitsRowsAndLabelsHeader`）；后由 p14 / [40](40-home-notifications-scroll.md) 取代——通知块不再裁剪列表，改为把全部已保留条目放进 6 行视口的块内滚动区（块高 225 不变），标题相应变为「通知 · 最近 N 条」且不再出现「（共 M 条）」。此行为 v5 当次上屏结论，原样保留。 |
| 浮动镜子 | AXPress 顶栏镜子按钮 → 面板右上浮出 212 × 212 的镜子（占位态）；再按一次收起（暗像素计数 12 → 3794 → 12） | **通过**（证据 `.workflow/p13-home-v5/evidence/`） |
| 摄像头出画面 | 需要摄像头授权（本机授权状态未决，见「已知限制 7」） | **待用户**（真人项） |
| 单测 | `xcodebuild test -only-testing:DynamicIslandTests` | **572 条 0 失败** |

## 已知限制

1. **工作日配置能力收缩**（D-06）：原模块的 `workStart` / `workEnd` / `workdays` 三键随模块
   退场不再可配；今天带那一行按默认工作日（一~五）+ 表内节假日算。要恢复就把模块注册加回，
   并把今天带那一行的数据源改成模块的 config（今天是直接调 `WorkdayCalendar`）。
2. **节假日名只覆盖 2026**（与 `WorkdayCalendar.holidayTables` 同年）：表外年份日期行不画
   节假日那一段。跨年前需补表。
3. **今天带在手动高度下可能被挤**：三带里今天带与流都不参与「让位」协商——面板高度不足以
   放下环境带 + 今天带时，`auto` 档会把面板长到装得下（上限 850），`manual` 档拖着不放时
   流先丢行、再不够就由面板自己裁。
4. **前列数上限 16**：前台应用块在超宽面板下最多一行 16 格（再宽不加列）——这是**选定的**
   上限（一行 16 格以上的图标墙不好点），装不下的给 `…`。
5. **农历不是会话级缓存**：`Calendar(identifier: .chinese)` 每次现算（一天一次的成本级），
   不为它加缓存层。
6. **退休模块的用例仍在**：`ProgressModule` / `MirrorModule` 的文件与用例保留（可逆），
   因此 `builtinModules` 的名单用例要改（少两条），这是本次唯一的「测试口径变更」。
7. **摄像头的授权提示在非激活面板下不保证弹出**（p13 上屏实测：点镜子按钮后系统提示没出现）。
   代码侧已按 `.denied` 那条先例补上「先把应用唤到前台再请求」，但本机这一次**没能证伪**——
   授权状态仍是未决。用户侧的两条出口都在：① 面板「设置 → 外观 → 附加功能」里的镜子那一节
   用系统设置授权；② 浮层里的占位块点一下会重试请求。**授权后画面本身未在本批验收覆盖**。
8. **今天带的「今天」按自然日算，不跟面板里的日历选中日**：在面板「日历」页翻到别的日期时
   今天带仍显示今天（它读的是自己那条当天窗口，接缝在打开面板时把它对齐到今天）。
9. **前台应用「点了没反应」的原委与修法（p13b，2026-10-11）**：用户报「有的应用点击会打开对应的
   应用，有的就没反应」。上屏取证（`NSWorkspace` × `CGWindowListCopyWindowInfo` 逐应用取样 +
   `open -b` / 进程内 API 的对照实验，脚本与读数在 `.workflow/p13-home-v5/evidence/`）后，
   真相是**「激活」与「屏幕上出现东西」是两件事**，三种状态各要一种处理：

   | 应用的状态 | 实测样本 | 点一下该发生什么 |
   |---|---|---|
   | 窗口最小化 / 在别的空间 | 邮件（屏幕内 0 → 1） | **激活并还原**：`activate(options: [.activateAllWindows])`。无参 `activate()` 只换前台应用、**不动最小化的窗口**——这是改前的第一处真错（用户看到的就是没反应） |
   | 一个用户窗口都没有 | Ghostty（真实窗 0 个） | **重新打开（reopen）**：程序坞点一个没在跑/没窗口的应用就是这个行为 |
   | 窗口停在**已断开的显示器**坐标上 | 微信 −1353 / 飞书 −1353 / Safari −1152 / Code −1833 | 激活之后屏幕上仍然什么都没有 → 也走 reopen，让应用把窗口救回当前屏 |

   两条实现要点（都是实测逼出来的）：

   - **reopen 只能由 `open(1)` 送**：同一个无窗口的应用（Ghostty）上，
     `NSWorkspace.openApplication`（含显式带 `kAEOpenApplication` 的 `appleEvent` 配置）
     **一个窗口都不开**，而 `open -b com.mitchellh.ghostty` 立刻开出来。自己发 Apple Event 要
     **自动化授权**（会弹「想要控制 XX」）——本项目不新增权限面，故走 `Process` 直接 exec
     `/usr/bin/open`（参数由纯函数 `reopenArguments` 给，没有拼接）。
   - **什么时候补 reopen 由「激活后的复检」决定**（0.35s 宽限期）：判据是纯函数
     `showsNothingOnScreen(windows:screens:)`——① 先按 `onscreen` 过滤（上游），② 再按
     尺寸挡掉辅助窗（实测有 1512×33 的菜单栏条、296×17 的提示条、54×54 的状态项），
     ③ 最后要求窗口与某块屏幕的 frame **几何相交**。**为什么必须复检而不是入口判**：
     「窗口最小化」与「窗口在别的屏」从列表上看不出区别，而前者激活就会自己还原——
     入口判会多开一个窗口（复检实测拦住了：Ghostty 已有窗口时再点两次，窗口数仍是 1）。
   - 另补**启动 / 退出**两条工作区观察者：`switcherApps` 是现取的 computed，但视图只在 store
     发布时重算——此前应用启动 / 退出不改 `current` / `recent`，没人叫醒视图，退出的应用会一直
     留在格子里（点它必然没反应）、新开的要等下一次切换才出现。上屏复验：后台启动计算器 →
     网格立刻多一格；退出 → 立刻少一格（都不经过任何切换）。

   **仍然做不到的**：应用自己不响应 reopen 时（少数没有 reopen 语义的应用），一个窗口都没有的
   状态下点了就是没有任何视觉变化——第三方进程没有别的办法（Dock 也只是发同一个事件）。

## 实际交付

- **代码**：内核两条新钩子（`homeZone` / `homeBlockAbsorbsSurplus`）；`HomeStripLayoutMath` 规则 ①′；
  `HomeFlowLayout` 去日历行 + 弹性；新增 `Host/HomeTodayBand.swift`（含农历 / 节假日名 / 下一个日程 /
  倒计时 / 工作日剩余四个纯函数出口）与 `Host/HomeEnvironmentBand.swift`；`HomeBandedHomeView` 改成三带；
  `HomeCalendarRow.swift` 删除；`MirrorModule` / `ProgressModule` 退出 `builtinModules`；
  `MirrorFloatingPreview` + `ContentView` 的面板内浮层；`showCalendar` 键与它的六处读者全数删除。
- **测试**：`xcodebuild test -only-testing:DynamicIslandTests` → **572 条 0 失败**
  （新增 `HomeTodayBandTests` 10 条：农历字表 / 农历自洽 + 真值 / 两张节假日表互校 / 调休假名 /
  日期行形状 / 下一个日程三态 / 倒计时七档 / 工作日剩余三段；`HomeStripLayoutTests` 新增
  规则 ①′、区劈分、带高算式三条）。
- **上屏**：面板 887 × **490**（auto 档），三带齐活；证据 `.workflow/p13-home-v5/evidence/`
  （`panel-887.png` + `crop-header.png` + 浮动镜子的开 / 关读数）。
- **遗留（真人复核）**：摄像头授权后的画面；hover 观感（浮起 / hover 底）；关掉通知或今日清单后
  的「独占整行」观感。
