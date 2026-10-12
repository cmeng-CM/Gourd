# 40 · 首页通知块：与今日块一致的块内滚动

| 项 | 值 |
|---|---|
| 状态 | 已实现 |
| 最后更新 | 2026-10-12 |
| 关联来源 | 用户 2026-10-12 反馈（截图圈红通知区 +「参考今日区域的设计，增加滚动下拉能力」）；承接 [38-home-v5-layout.md](38-home-v5-layout.md)（首页 v5 三带、六块尺寸、通知块 D-11「最近 6 条」）与 [39-calendar-light-interactions.md](39-calendar-light-interactions.md)（今日区全量滚动与 hover 抑制） |
| 工作流 | `.workflow/p14-notif-scroll/` |

> **怎么读**：§背景与目标 / §明确不做 / §备选与取舍 是这场改动的判断依据；
> §接口与数据形状 是参考型小节（执行者与机器查考），人审可跳过；
> §已知限制 / §实际交付 是留给后来人的。

**读者分界**：§一句话方案 / §背景与目标 / §备选与取舍 / §明确不做 / §验收标准 / §决策摘要 给人读；§做法 / §接口与数据形状 是给执行者与模型的契约。

## 一句话方案

首页通知块**保留既有块高与可视行数**，把「只画最近 6 条」改成「把已保留的通知全部放进一个**块内竖向滚动区**」——与今日清单块同一套交互：列表可滚动查看，悬停/滚动期间不触发面板收回。

## 背景与目标

**问题现状**：首页 v5 的第三排是「今日清单 + 通知」并排（docs/38 D-12）。今日清单块自 docs/39 起是**全量滚动**：块高固定、内容全部在内部滚动区里（D-01，「容量只决定滚动区高度，不裁剪数据」）。通知块却还是 docs/38 D-11 的固定裁剪——`NotificationsHomeBlockLayout.listedItems` 只取 `prefix(maxListRows)`（前 6 条），第 7 条起**不可达**，而读取层其实已保留最多 40 条。两块并排、形态却不一致：用户 2026-10-12 圈红通知区，要求「参考今日区域的设计，增加滚动下拉能力」。

**预期结果**：通知多于视口行数时，可在块内滚动看到**全部已保留的通知**（≤ 40 条）；表头如实（沿用既有 shown/total 口径，不再人为砍计数）。

**关键约束**：块高（225）、可视行数（6）、与今日清单并排时的宽度分配（docs/38 D-04 弹性块吃富余）**都不变**；只读、无新定时器、颜色与点击行为不变。

## 做法

机制三条：

1. **列表不再裁剪**：`NotificationsHomeBlockLayout.listedItems(_:)` 去掉 `prefix(maxListRows)`，返回传入的全部条目（顺序原样＝`rec_id DESC`，新的在前）。`maxListRows` 的语义从「列表上限」**收窄为「视口行数」**——块高算式与视口行数不变，只是不再拿它裁数据。这与今日块「容量只决定滚动区高度，不裁剪数据」是同一条口径。
2. **条目区进滚动容器**：`NotificationsHomeBlockView` 里把条目 `ForEach` 包进 `ScrollView(.vertical)`，并沿用今日块的 idiom——`@State scrollToken`、`.onHover { vm.setScrollGestureSuppression($0, token:) }`、`.onDisappear` 复位 token。滚动时鼠标停在块内即压住面板的 hover-exit 收回（与剪贴板/笔记/终端视图同款接缝）。需要取 `vm`（`@EnvironmentObject`）。
3. **表头不变**：`NotificationText.homeHeader(shown:total:)` **一个字不改**；`shown` 现在是全部可达条数，标题因此自然变成「通知 · 最近 N 条」，`total > shown` 时才带的「（共 M 条）」在不再裁剪后自然消失——D-11「标题不说假话」的原始口径继续保持。

## 备选与取舍

| 选择 | 理由 |
|---|---|
| 加高块体、多画几行 | 不选：与今日清单并排，选高会连带动另一块板高（行高恒 = 行内最高块）；用户要的是「参考今日区」的滚动，不是变高 |
| 提高读取保留上限（> 40） | 不选：那是 reader 的既有口径（`fetchRecent(limit:)`），超出本次范围；先给滚动能力，能滚到的就是列表里有的 |
| 不裁但让块高随内容增长 | 不选：面板高度会随通知条数抖动，与「块高恒 = 行内最高块」的既有规则冲突 |
| 复用 `session.homeScrollAnchor` 记滚动位置 | 不选：那个锚点只服务「详情页返回时恢复列表位置」；通知块没有详情页，引入只会多一条没有消费者的状态 |

## 接口与数据形状

```swift
// Modules/NotificationsModule.swift —— NotificationsHomeBlockLayout（纯函数，单测直接钉）
static let maxListRows = 6                       // 语义收窄：**视口行数**（块高算式不变，值仍为 6）
static let entryHeight: CGFloat = 30             // 一条通知两行的高度
static let entrySpacing: CGFloat = 4             // 条与条之间的间距
static let headerHeight: CGFloat = 16            // 表头行高
static let listSpacing: CGFloat = 4              // 表头与第一条之间的间距（外侧）
static func listedItems(_ items: [NotificationItem]) -> [NotificationItem]
    // 改前：Array(items.prefix(maxListRows))（只画前 6 条，第 7 条起不可达）
    // 改后：items（全部；顺序原样＝rec_id DESC，新的在前）
static var blockHeight: CGFloat                  // 不变（= 内容顶部内缩 5 + 表头 16 + 间距 4 + 6×30 + 5×4 = 225）

// Modules/NotificationsModule.swift —— NotificationsHomeBlockView（SwiftUI，实际结构）
@EnvironmentObject private var vm: DynamicIslandViewModel   // 新增：只为 hover 抑制接缝
@State private var scrollToken = UUID()                     // 新增

VStack(alignment: .leading, spacing: NotificationsHomeBlockLayout.listSpacing) {
    header                                                     // 表头：滚动区**之外**
    if let hint = NotificationText.homeHint(store.state) { … }  // 权限 / 不可读提示：滚动区**之外**
    ScrollView(.vertical) {                                    // 只有条目进滚动区
        VStack(alignment: .leading, spacing: NotificationsHomeBlockLayout.entrySpacing) {
            ForEach(NotificationsHomeBlockLayout.listedItems(store.items)) { item in
                row(item)
            }
        }
    }
    .onHover { vm.setScrollGestureSuppression($0, token: scrollToken) }   // 挂在 ScrollView 上
}
.padding(.top, HomeBlockChrome.contentInsetTopText)                       // 内容顶部内缩 5
.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) // 视口＝6 行 200pt 区
.onDisappear { vm.setScrollGestureSuppression(false, token: scrollToken) }// 挂在块上
```

**滚动区（视口）**：`225 − 顶部内缩 5 − 表头 16 − 外侧间距 4 = 200pt ≡ 6 × 条目 30 + 5 × 条间距 4`。
条与条之间的 4pt 由**内层** `VStack(spacing: entrySpacing)` 提供——`ForEach` 搬进 `ScrollView`
后它不再是外层 `VStack` 的直接子视图，外侧间距不会落到条目之间（见 §已知限制 1，T1fix 修的就是这一处）。
`header` 与提示行留在滚动区外，因此滚动只动条目、表头恒在。

**不动的**：`NotificationText.homeHeader(shown:total:)` / `sourceLabel` / `detailLabel` / `minimumBlockWidth`(340) / `idealBlockWidth`(377) / 读取层 `NotificationsModule.maxItems`(40) 与 `NotificationCenterReader.fetchRecent`。

**不引入**：`CalendarPanelSession.homeScrollAnchor`（通知块无详情页，没有锚点消费者）。

## 明确不做

不做关闭 / 清除 / 回复 / 新通知高亮；不引入新定时器（重绘仍靠 `store` 的 `@Published`）；不改展开 tab 的列表与状态行；不改通知读取上限、`dismissed` 过滤与权限引导；不做跨面板的滚动位置记忆；不做通知块与今日块之间的滚动联动。

## 实际交付

**代码**（文件 `DynamicIsland/Modules/NotificationsModule.swift`）：

- `NotificationsHomeBlockLayout.listedItems(_:)` 由 `Array(items.prefix(maxListRows))` 改为 `items`
  ——返回全部、顺序原样；`maxListRows = 6` 取值不变、语义收窄为「视口行数」；`blockHeight` 算式逐字不变（225）。
- `NotificationsHomeBlockView`：新增 `@EnvironmentObject private var vm: DynamicIslandViewModel` 与
  `@State private var scrollToken = UUID()`；条目 `ForEach` 包进 `ScrollView(.vertical)`，
  挂 `.onHover { vm.setScrollGestureSuppression($0, token: scrollToken) }`，块末尾
  `.onDisappear { vm.setScrollGestureSuppression(false, token: scrollToken) }`；表头与提示行留在滚动区外。
  未引入 `CalendarPanelSession.homeScrollAnchor`、无新定时器；读取层（`maxItems` = 40、`fetchRecent`）
  与 `homeHeader` 函数体未动。
- 同文件内的 stale 文档注释顺带更新（枚举头 / `maxListRows` / `blockHeight` / `listedItems` /
  视图类型头 / 模块头 `surfaces` 与 `defaultPlacement` 说明 / `NotificationRowMetrics` 的「定高 96 内画 3 行」）。

**测试**（`DynamicIslandTests/ModuleKernelTests.swift`）：更新
`testNotificationsHomeBlockLayoutLimitsRowsAndLabelsHeader`（「裁到 6 条」断言改为「全量返回、顺序不变、
空→空」，`maxListRows == 6` 与 `blockHeight` 断言与 `homeHeader` 三档保留）；新增
`testNotificationsHomeBlockLayoutListsEveryItemUncropped`（40 条与 10 条全量、顺序不变）。

**提交**：`3b802228`（T1）、`fac3b52b`（T1fix）。

**与计划的偏离**：计划（§做法 2）只说「把条目 `ForEach` 包进 `ScrollView`」；实际必须再加一层
`VStack(alignment: .leading, spacing: entrySpacing)`——`ForEach` 进滚动容器后不再是外层 `VStack` 的直接子视图，
外层那 4pt 条间距不落到条目之间，6 行只量出 180pt（视口 200pt，第 7 行会露头）。这是独立审查发现的
唯一一处 Important 缺陷，`fac3b52b` 修复后复审 PASS（见 §已知限制 1）。

**遗留项**：

- **单测只编译未执行**：`xcodebuild build-for-testing` 与 `sh tools/build.sh` 均 exit 0、打出
  `** TEST BUILD SUCCEEDED **` / `** BUILD SUCCEEDED **`（日志 `.workflow/p14-notif-scroll/reports/`），
  但 `xcodebuild test` 未运行——按用户「桌面保持不动」的既有约束，且今天重装应用后首跑单元测试有触发 TCC 弹窗的风险。
  因此 §元信息 的「已实现」指代码已落地并通过编译，**不等于单测实测通过**。
- **上屏复核未做**：滚动到底、滚动 / 悬停期间面板不收回、块高不变三项人眼验收需桌面，留待用户空闲时执行。

**验证证据**：`.workflow/p14-notif-scroll/reports/`（`T1-build-for-testing.log` exit 0、
`T1-release.log` exit 0、`T1fix-build-for-testing.log`、`T1fix-release.log` 均 exit 0）。

## 已知限制

1. **滚动视口是 6 行的 200pt 区**（`225 − 顶部内缩 5 − 表头 16 − 外侧间距 4`）：条目行距必须由滚动区
   **内层** `VStack(spacing: entrySpacing)` 显式给，不能指望外层 `VStack`——`ForEach` 搬进 `ScrollView`
   后不再是外层的直接子视图，外层那 4pt `entrySpacing` 不落到条目之间，6 行只量出 180pt，第 7 行会露头。
   这是 T1 首次实现踩到、`fac3b52b` 修掉的唯一一处实现缺陷。
2. **`homeHeader` 的「（共 M 条）」一支在首页块上不可达**：`total > shown` 要求列表画得比数据少，而首页块
   现在把 `store.items` 原样交给 `listedItems`，`shown == total` 恒成立。该分支**保留**只为纯函数契约与
   单测（函数本身不改）；将来若再出现「列表画得比数据少」的块可复用。`homeHeader` 的三档断言（0 条 /
   `shown == total` / `shown < total`）仍在单测里钉着。
3. **滚动可达范围仍受保留上限约束**：能滚到的是列表里已有的（≤ 40 条）；更早的通知不在列表里，
   本批不改读取口径（D-04）。
4. **两块各自独立滚动**：通知块与今日块各有自己的滚动区，没有联动，滚动互不影响。

## 验收标准

- 通知多于视口行数（> 6）时，块内可竖向滚动看到**全部已保留条目**；滚动/悬停块内时面板不因 hover-exit 收回。
- 块高（225）、并排宽度分配、点击打开 App 的行为、只读语义**都不变**。
- 纯函数单测：`listedItems` 不再裁剪（返回全部、顺序不变）；原 `testNotificationsHomeBlockLayoutLimitsRowsAndLabelsHeader` 口径随之更新（从「列表上限 6」改为「视口 6、列表全量」）。
- Release 构建通过；上屏复核（需桌面，见 §已知限制与工作流收尾）。

## 决策摘要

| ID | 决策与来源 | 理由 |
|---|---|---|
| D-01 | agent：通知块列表**不再裁剪**，列出全部已保留条目；块高与视口行数不变 | 与今日块「容量只决定滚动区高度，不裁剪数据」同一条口径（docs/39 D-01）；用户要的是滚动不是变高 |
| D-02 | agent：采用今日块的滚动 idiom（`ScrollView` + hover 抑制 token），**不**引入 `session.homeScrollAnchor` | 通知块无详情页、无锚点消费者；多引一条无消费者的状态只会增加耦合 |
| D-03 | agent：表头沿用既有 `homeHeader(shown:total:)`，不新增文案取值 | D-11「标题不说假话」的原始逻辑本身已自适应（shown 与画出的条数同源），不裁剪后自然如实 |
| D-04 | 用户：滚动可达范围保持现有读取上限（≤40 条），本轮不改 `NotificationCenterReader` 读取口径 | 用户 2026-10-12 确认「保持现有 40 条」——只给既有列表加滚动能力，更早通知不在列表（见 §已知限制） |
