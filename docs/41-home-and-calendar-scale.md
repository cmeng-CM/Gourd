# 41 · 首页两块等分 + 日历页等比放大

| 项 | 值 |
|---|---|
| 状态 | 已实现 |
| 最后更新 | 2026-10-12 |
| 关联来源 | 用户 2026-10-12 两条要求（面板截图圈注：「今日和消息两个横向等分」「日历面板等比例放大一些」，幅度在 +10% / +20% / 只加高 三选项里选定 +20%）；承接 [38-home-v5-layout.md](38-home-v5-layout.md)（首页 v5 六块尺寸与规则 ①′）与 [39-calendar-light-interactions.md](39-calendar-light-interactions.md)（面板「日历」页布局；`MonthGridLayout` 高度算式） |
| 工作流 | `.workflow/p15-layout-scale/` |

> **怎么读**：§背景与目标 / §明确不做 / §备选与取舍 是这场改动的判断依据；
> §接口与数据形状 是参考型小节（执行者与机器查考），人审可跳过；
> §已知限制 / §实际交付 是留给后来人的。

**读者分界**：§一句话方案 / §背景与目标 / §备选与取舍 / §明确不做 / §验收标准 / §决策摘要 给人读；§做法 / §接口与数据形状 是给执行者与模型的契约。

## 一句话方案

① 首页第三排里「今日清单」与「通知」两块**等宽**（各占这一行的一半）；② 面板「日历」页的整体视觉尺寸**等比放大约 20%**——日格更高、字号更大、表头与间距同步放大，面板自动高度随之长高。

## 背景与目标

**问题现状**：首页第三排是「今日清单 + 通知」并排（docs/38 D-12）。两块都申报了 min/ideal 并让富余按 **ideal 比例**分配（规则 ①′，docs/38 D-04），而今日申报的 ideal（470）明显大于通知（377），所以今日拿得更宽、观感不齐——用户 2026-10-12 要求「今日和消息两个横向等分」。日历页则是另一回事：它所有尺寸都是硬编码常量（`MonthGridLayout.dayCellHeight = 30`、月历高 `36N + 52`、日期字 12pt、农历 9pt），在用户 887 宽的面板下左栏约 437pt 宽、日格量成 **57 × 30**（很扁），用户要求「日历面板等比例放大一些」。

**预期结果**：① 该行两块各 ≈423.5pt（行宽 855 时）；② 日历日格高 30 → 36、日期字 12 → 14、农历 9 → 11、星期行/表头/间距与右栏卡片行高同步 ×1.2，月历高 `36N + 52` → `43N + 63`（行距 30+6=36 → 43）。

**关键约束**：不改布局规则本身（仍走 `HomeStripLayoutMath` 的 ①②①′）、不改面板宽/高设置项（`openNotchWidth` / `openNotchHeight`）、不动其他块与其他页面。

## 做法

**① 等分（用既有机制，不加新规则）**：把两块的 `idealBlockWidth` 取同一个值 **420**（今日 470 → 420；通知 377 → 420），`minimumBlockWidth` 不动（今日 420 / 通知 340）。规则 ①′ 按**弹性块的 ideal 比例**分富余，ideal 相等 → 富余等分 → 两块等宽。行宽 855 时：`420 + 8 + 420 = 848 ≤ 855`，富余 7 按等比 → 各 +3.5 = **423.5**。

**② 日历等比放大（一个比例常量派生各档）**：在 `MonthGridLayout` 引入 `scale = 1.2`，把既有各档常量改为**由它派生**（日格高、单选/双选直径、副标行高、表头 chrome、星期 chrome、网格间距与网格左侧内缩、日期/农历字号、事件点），`monthGridHeight` 随新行高重算；右栏 `CalendarEventCards` 的行高/字号同步。这样以后调幅度只动一个数。

## 备选与取舍

| 选择 | 理由 |
|---|---|
| 把布局规则改成「同行弹性块一律等分」 | 不选：需求只涉及这两块，改规则会波及其他行；让 ideal 相等用既有机制就得到同一结果 |
| 同时把今日的 min 降到 380，使窄面板也能等分 | 不选：docs/38 记明今日 min 420 是「两行式文案在更窄列里只剩省略号」的下限 |
| 日历只加高日格、字号不动 | 用户否掉（三个选项里选了等比 +20%） |
| 日历各档直接改成新数字（30→36 逐处写） | 不选：留一处 `scale` 派生，幅度可一处调整；逐处写死以后无从追溯 |

## 接口与数据形状

```swift
// Modules/TodosModule.swift —— TodosHomeBlockLayout
static let minimumBlockWidth: CGFloat = 420     // 不变
static let idealBlockWidth: CGFloat = 420       // 改前 470（与通知取同值 → 等分）

// Modules/NotificationsModule.swift —— NotificationsHomeBlockLayout
static let minimumBlockWidth: CGFloat = 340     // 不变
static let idealBlockWidth: CGFloat = 420       // 改前 377（与今日取同值 → 等分）

// components/Calendar/DynamicIslandCalendar.swift —— MonthGridLayout
static let scale: CGFloat = 1.2                 // 新增：日历页等比放大比例
// 以下由 scale 派生（原值 × 1.2 后逐档取整到整点）
static let dayCellHeight / singleLineSelectionDiameter / twoLineSelectionDiameter
static let subtitleLineHeight / headerChromeHeight / weekdayChromeHeight
static let monthGridHeight(forMonth:calendar:)  // = 43N − 7 + 5 + 41 + 24 = 43N + 63

// components/Calendar/CalendarEventCards.swift —— CalendarEventCardList
// headerHeight / card minHeight 等行高与字号同步 ×1.2
```

**不动的**：`HomeStripLayoutMath` 的三条规则、`HomeStripLayout.spacing`(8)、两个模块的 `minimumBlockWidth`、面板宽高设置项、日历页三页面结构与交互。

## 明确不做

不改布局规则（①②①′）；不改面板宽/高设置项；不动今日/通知块的内容、文案与滚动；不动日历页的列表/详情/编辑三页结构与交互手势；不做用户可调的日历缩放档位（本轮是常量，不设开关）。

## 实际交付

两处尺寸改动都已落地并随工作流 `.workflow/p15-layout-scale/` 提交；完整单测 656/656 通过、Release 构建通过。交付物：

| 提交 | 内容 |
|---|---|
| `282fda1` | **T1** 两块 ideal 取同值 420（`TodosModule.swift` / `NotificationsModule.swift` + `HomeStripLayoutTests.swift`） |
| `b2195d01` | **T2** `MonthGridLayout.scale = 1.2` 与各档派生（`DynamicIslandCalendar.swift` / `CalendarEventCards.swift` + `HomeStripLayoutTests.swift`） |
| `e0a0a095` | **T2fix** 补同步连带受影响的测试期望（`ModuleKernelTests.swift` / `PanelAutoHeightTests.swift`） |
| `dc50ac02` | **T2fix2** 各档派生值取整到整点（保持整点几何） |
| `54d8022` | **T2fix3** 周标题行改由 `.frame(height: weekdayRowHeight)` 显式钉住，网格底与行底重新齐平 |

- **交付机制**：① 两块 `idealBlockWidth` 都取 420 → 规则 ①′ 按 ideal 等比分富余 → 该行等分（规则本身未动）；② `MonthGridLayout` 新增唯一旋钮 `scale = 1.2`，视觉各档常量与 `monthGridHeight` 全由它派生，右栏 `CalendarEventCardList.headerHeight` / 卡片 `minHeight` 引同一个 `scale`。
- **与计划的偏离**（均为执行期发现，非越界）：
  - `monthGridHeight` 取值变化连带打红**另外两个测试文件**（`ModuleKernelTests` 钉 268/232/206、`PanelAutoHeightTests` 钉 232/244），计划的任务文件清单漏了它们——由 `T2fix` 补提交。
  - 各档派生值**取整到整点**（`(原值 × scale).rounded()`，T2fix2）：AppKit 按整点落地分数帧，逐档 `43.2 / 7.2` 会让误差累加、网格底够不到行底；取整后整条链都是整点。
  - **周标题行新增显式 `.frame(height: MonthGridLayout.weekdayRowHeight)`**（T2fix3）：该行原先只由语义字号 `.caption2` 撑起，不随 `scale` 真实长高，与常量 `14 → 17` 差 2pt，导致网格底差 2pt 够不到行底；钉住行框后二者重新一致（护栏 278.0 = 278.0、321.0 = 321.0 通过）。
- **遗留项**：**上屏复核**（两块等宽的实际观感、日历放大后的视觉比例与面板高度是否合适）需用户执行，见 §已知限制。

## 已知限制

- 起草期先列，实现期按实际代码核对后补记：
  - **等分只在行宽放得下两块 ideal 时精确**（855 → 423.5 / 423.5）。更窄时按 min 收缩，两块 min 不同（今日 420 > 通知 340），通知先缩 → 不再精确等分。
  - **日历放大后面板变高**：`monthGridHeight` 由 `36N + 52` 变 `43N + 63`（5 周 232 → **278**、6 周 268 → **321**），自动高度随之长高；接近 `matters.swift` 的 850pt 上限时不再长。
  - 日历日格**宽度**仍由面板宽决定（≈57pt），放大只作用于高度与字号，所以日格是 57 × 36，不等于等比正方形。
  - **网格的水平 `.padding(.horizontal, 6)` 未随 `scale` 缩放**：随 `scale` 走的只有格宽内缩 `gridInset`（= `6 × gridSpacing` = **42**，改前 36）；`MonthGridView` 左右那圈 6pt 内边距是写死的字面量，放大后仍是 6。
  - **月标题 / 年份 / 星期标签用语义字号**（`.title3` / `.subheadline` / `.caption2`）——它们**不随 `scale` 生长**。两段 chrome 的行高确实长了（表头 `headerRowHeight` 24 → 29、周标题 `weekdayRowHeight` 14 → 17），但那些字形的**尺寸**不变：所谓「等比」对 header / weekday 的**文字**是部分的。
  - `LunarDayLabel.fits` 的 `fontSize` **缺省仍是 9**，而日历视图调用时传的是 `MonthGridLayout.subtitleFontSize`（**11**）——即两处因传入值而自洽，但**没有测试钉住这个调用点**（已知覆盖缺口：改默认值或改传参都不会被判据发现）。

## 验收标准

- 首页该行两块等宽（各 ≈423.5pt，误差 < 1pt）；关掉通知块时今日块仍独占整行；关掉今日块时通知块独占整行。
- 日历页：日格高 36、日期字 14、农历 11、月历高 `43N + 63`（5 周 **278**、6 周 **321**）；右栏卡片行高/字号同步放大。
- 纯函数单测更新并通过：`HomeStripLayoutTests` 的 ideal 组合与 `monthGridHeight` 各档（含「网格底贴住行底」结构护栏）。
- Release 构建通过；上屏复核（需用户，见 §已知限制与工作流收尾）。

## 决策摘要

| ID | 决策与来源 | 理由 |
|---|---|---|
| D-01 | 用户：首页「今日清单」与「通知」两块横向等分 | 用户 2026-10-12 截图圈注；两块等宽观感整齐 |
| D-02 | agent：等分用「两块 ideal 取同值 420」实现，**不改布局规则** | 规则 ①′ 按 ideal 比例分富余，ideal 相等即等分；不动规则避免波及其他行 |
| D-03 | 用户：日历页整体等比放大 **+20%** | 用户在 +10% / +20% / 只加高 三个幅度里选定 +20% |
| D-04 | agent：日历放大用**一个 `scale` 常量派生各档**，不逐处写死新数字 | 幅度要能一处调整与追溯；逐处写死以后没人知道基准 |
