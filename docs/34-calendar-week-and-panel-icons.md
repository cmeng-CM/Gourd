# 34 · 面板日历的周起点（固定周一）与面板图标（隔空投送自绘字形、笔记换装）

**状态**：p9 批次的长期设计记录（工作流的计划/账本/报告在 `.workflow/p9-calendar-week-icon/`，收尾后消失；本文档留在版本库）。
**承接**：`docs/09` §C 时间（日历 / 农历 / 面板呈现的机制记录）、`docs/17` §做法 改判表与 D-25…D-27（首页日历行与 `MonthGridView` 的抽取复用）、`docs/29` T5（设置页「面板组件」节的行 chip 取「该元素**在面板上**的那一枚」图标）、`docs/30` §已知限制 5（剪贴板的 `notchTab` 档位）、`docs/31` 第 8 条（进度块「本周」的周区间**跟随系统** `firstWeekday`——本次不动，见 §明确不做）。
**改判留痕**：
- ~~面板月历的周起点跟随系统 `firstWeekday`（本机 zh_CN = 1 即周日）~~ **2026-10-09 p9 改判：固定周一（`firstWeekday = 2`）**——用户 2026-10-09 反馈「两个日历面板，开始时间都是从周一开始」。原口径的代码落点是 `MonthGridView.calendar = Calendar.current` 一族（三处 `Calendar.current` + `MonthGridLayout` 纯函数的默认参数），未在任何文档里被显式承诺过，本次把它写成唯一一条规则。
- ~~隔空投送（投送暂存）tab 的图标 = `tray.fill` 托盘~~ **2026-10-09 p9 改判：自绘的 macOS 隔空投送字形（圆心点 + 三段同心弧、底部开口）**——用户 2026-10-09 反馈「日历和隔空投送两个图片没有区别……隔空投送使用 mac 系统这种图标」（附 macOS 控制中心的隔空投送字形截图）。

## 一句话方案

两个日历面板（首页整宽日历行 + 展开面板日历页）的**周起点固定为周一**，唯一落点是新的 `Calendar.gourdDisplay`（`Calendar.current` + `firstWeekday = 2`），消费点改默认值（含两处视图持有的日历）与按月取数窗口都从它取数；tab 条上「隔空投送（投送暂存）」那枚由 `tray.fill` 托盘换成**自绘的 macOS 隔空投送字形**（圆心点 + 三段同心弧、底部开口 ±35°），并把与日历 tab 撞脸的**笔记 tab 换一枚轮廓可分的字形**（`square.and.pencil`）。

## 背景与目标

**为什么做**：用户 2026-10-09 一次性给两条视觉口径（附三张截图 + 一张目标字形）：

1. 「两个日历面板，开始时间都是从周一开始」——两张截图分别是展开面板的日历页与首页的整宽日历行，表头都是「日 一 二 三 四 五 六」，网格首格落在周日。
2. 「日历和隔空投送两个图片没有区别，要调整，隔空投送使用 mac 系统这种图标」——截图上用红框圈住了 tab 条第 4、5 枚（`calendar` 与 `note.text`），另附 macOS 控制中心那枚隔空投送字形。

**问题现状**：

- **周起点**：`MonthGridView.calendar`、`StandaloneCalendarView.calendar` 两处都是 `Calendar.current`，`MonthGridLayout` 一族纯函数的 `calendar:` 默认参数也是 `.current`，`CalendarManager.updateMonthEvents` 走默认值——于是整条链路都跟随系统 `firstWeekday`。本机 zh_CN 下 `Calendar.current.firstWeekday = 1`（周日），用户看到的就是周日开头。**没有任何地方能改它**：既没有设置项，也没有产品口径。
- **图标撞脸**：第 4 枚（日历 tab，`calendar`）与第 5 枚（笔记 tab，`note.text`）在 13pt 下**轮廓逐字同形**——都是一张圆角卡片加一条实心顶带，差别只在卡内的点阵（日历）与横线（笔记），1x 上读不出。第 8 枚隔空投送是 `tray.fill` 托盘：与日历不像，但它既不表达「隔空投送」，也与 macOS 上那枚同心弧字形没有任何关系（用户点名要后者）。
- 截图与实测的对应关系留档在 `.workflow/p9-calendar-week-icon/evidence/`（`bar-sim-vs-live.png` 把代码里的图标清单渲染成一条，与用户截图的 tab 条逐格吻合，身份因此钉死：4 = `calendar`、5 = `note.text`、8 = `tray.fill`）。

**预期结果**：

1. 两个面板的月历表头变为「一 二 三 四 五 六 日」，网格首格 = 当月 1 日所在周的**周一**，末格 = 月末所在周的**周日**；按月取数窗口跟着两端各挪（否则网格里多出来的那一天永远不会有事件点）。
2. tab 条上：日历（卡片 + 点阵）、笔记（方框 + 铅笔）、隔空投送（同心弧）三枚一眼可分；隔空投送那枚与用户给的控制中心字形同构。

**关键约束**：

- **范围只有这两处视觉口径**：进度块「本周」的周区间（docs/31 第 8 条）不动——它跟随系统自然周，改了会动「剩 N 天」的数字，而用户没有提（见 §明确不做）。
- 纯函数 `MonthGridLayout` 的**签名一个字不改**（只改默认值）：既有用例绝大多数显式注入 `Calendar`，口径不动；**唯一的例外是一条渲染用例**——`HomeStripLayoutTests.testHomeCalendarGridViewportFitsTheMonthAtItsRowHeight` 把 `MonthGridView` 塞进 `NSHostingView` 量视口，而视图的日历**不由外部注入**（`private let calendar`），所以它的夹具与「月份 → 周数」表必须随产品档一起切到周一（2026-11 由 5 周变 6 周）。这是本次改动**唯一**需要动的既有用例。
- 不引入任何第三方图标资源、不抠系统私有资源；字形是自绘矢量。

## 做法

### 机制一 · 显示日历（周起点的唯一落点）

新增一枚**显示日历**，作为面板日历唯一的周起点来源：

```
Calendar.gourdDisplay = Calendar.current，但 firstWeekday = 2（Foundation 的 1-based 口径：1 = 周日、2 = 周一）
```

消费点全部从它取数（**改默认值而不是改调用点**，让「跟随」这件事只写一遍）：

| 消费点 | 现状 | 改动 |
|---|---|---|
| `MonthGridLayout.days(forMonth:calendar:)` | 默认 `.current` | 默认 `.gourdDisplay` |
| `MonthGridLayout.weekCount(forMonth:calendar:)` | 默认 `.current` | 默认 `.gourdDisplay` |
| `MonthGridLayout.monthGridHeight(forMonth:calendar:)` | 默认 `.current` | 默认 `.gourdDisplay` |
| `MonthGridLayout.monthWindow(forMonth:calendar:)` | 默认 `.current` | 默认 `.gourdDisplay` |
| `MonthGridLayout.daysWithEvents(inMonth:events:calendar:)` / `eventDays(forDisplayedMonth:snapshot:calendar:)` | 默认 `.current` | 默认 `.gourdDisplay` |
| `MonthGridLayout.firstDay(ofMonth:calendar:)` | 默认 `.current` | 默认 `.gourdDisplay`（结果与周起点无关，统一口径便于读） |
| `MonthGridView.calendar` | `Calendar.current` | `.gourdDisplay` |
| `StandaloneCalendarView.calendar` | `Calendar.current` | `.gourdDisplay` |
| `HomeCalendarRow.rowHeight(forMonth:calendar:)` | 默认 `.current` | 默认 `.gourdDisplay`（`rowHeight` 静态入口与 `HomeStripView` 的三处预算自动跟随） |
| `CalendarManager.updateMonthEvents` | `MonthGridLayout.monthWindow(forMonth:)` 走默认值 | **不写代码**：默认值改掉即自动跟随，只补注释 |

**为什么「按月窗口必须同源」**：`MonthGridView` 画的是「该月整张网格」（含跨月补格），事件点由 `MonthGridLayout.eventDays` 在同一张网格上筛出；而事件数据是 `CalendarManager.updateMonthEvents` 按 `monthWindow` 抓的。两处的周起点一旦不同，网格末端那一天（周一起始时是**下月 1 日**那一格）永远不会有事件点——这正是本机制要把「一个 Calendar 走到底」写成规则的原因。

**周数会变，行高跟着变**（既有行为，非本次新增）：同一月份的周数随周起点变。例：2026-11 在周日起始下是 5 周、周一起始下是 6 周 → 首页日历行高 232 → 268。docs/30 §做法 机制六 已接受「面板高随月变化」，本次只是换一档起点。

**表头顺序**：`MonthGridView.weekdaySymbols` 现在把 `veryShortStandaloneWeekdaySymbols` 按 `calendar.firstWeekday` 旋转。本次把这段旋转**抽成纯函数** `MonthGridLayout.weekdaySymbols(for:)`（视图与用例共用一条算式，「表头顺序」因此第一次变得可断言），视图改为调用它。

**这次连带的既有承诺**（写在这里以免下次读到时以为是漏的）：

- `MonthGridLayout` 的**签名**不变、**显式传日历的调用点**一处不改——它们表达的正是「算式与周起点无关」，本次只是把默认值指向产品档。
- 同文件里 `EventListView.clockLabel(for:calendar:)` 也是 `calendar: Calendar = .current`，但它算的是**事件行的时刻文案**（按日粒度），与周起点无关，**不动**。
- 唯一要跟着改的既有用例是 `HomeStripLayoutTests.testHomeCalendarGridViewportFitsTheMonthAtItsRowHeight`（理由见 §背景与目标 · 关键约束）。

### 机制二 · 面板图标：一枚自绘字形 + 一个图标类型

**先定的三件事**（都在本机 macOS 27 上实测）：

1. SF Symbols **没有** AirDrop 这一枚——`NSImage(systemSymbolName: "airdrop")` 返回 `nil`（`airdrop.circle` 等变体同样没有）。
2. `NSSharingService(named: .sendViaAirDrop).image` 存在，但它是那枚**彩色 App 图标**（蓝色圆角方块 + 白色扇形），tab 条是单色模板底，放上去与其余七枚不是一套。
3. `dot.radiowaves.left.and.right` 一类现成符号的弧**每侧 3 条、共 6 条弧 + 圆心点**，只在**左右两个方向**张开、**没有底部开口**，与控制中心那枚「同心三段弧 + 底部开口」不同构。

因此字形**自绘**：`AirDropGlyph`（SwiftUI `Canvas`，`.foreground` 着色 → 自动跟随 tab 的选中/未选中档）。几何按用户给的控制中心截图量取，以字形外缘半径 `R` 为单位：

| 元素 | 取值 | 来处 |
|---|---|---|
| 圆心点半径 | `0.13R` | 参考图中心行/列亮度扫描（半宽 2px / 外缘 15.5px） |
| 三段弧环心半径 | `0.33R` / `0.65R` / `0.90R` | 同上（5.1 / 10.1 / 14.0 px） |
| 线宽 | `0.113R` | 同上（1.75px，圆头线帽） |
| 底部开口 | 每侧 35°（合计 70°） | 参考图 16 倍放大下量弧端位置（atan(9/12.6) ≈ 35.5°） |

图标在代码里第一次有了类型（此前是裸 `String` 的 SF Symbol 名）：

```
enum PanelIcon: Equatable { case symbol(String); case airDrop }
```

`Image(systemName:)` 的渲染点改成 `PanelIconView`（`.symbol` → `Image(systemName:)`、`.airDrop` → `AirDropGlyph`），tab 条与设置页行 chip 都走它——**同一枚面板元素在任何地方都是同一枚图标**（docs/29 T5 的既有口径）。

**接线清单**：

| 位置 | 现状 | 改动 |
|---|---|---|
| tab 条 · 投送暂存（`TabSelectionView.slots` 的 `shelf`） | `tray.fill` | `.airDrop`（取自 `PanelIconTable.shelf`） |
| tab 条 · 笔记 / 剪贴板（`clipboard` 槽） | 笔记开 = `note.text`、关 = `doc.on.clipboard` | 笔记开 = `PanelIconTable.notes`（`square.and.pencil`）、关 = `PanelIconTable.clipboard`（不动） |
| 设置页「面板组件」节 · 投送暂存行 chip | `tray.fill` | `PanelIconTable.shelf`（`.airDrop`） |
| 设置页「面板组件」节 · 笔记行 chip | `note.text` | `PanelIconTable.notes` |
| 日历 tab（模块 manifest `CalendarModule`） | `calendar` | **不动**——日历那枚是最标准的日历表示，本次换的是「跟它撞脸的那一枚」 |
| 设置页侧栏「笔记」页图标（`SettingsTab.notes`） | `note.text` | 不动——侧栏图标是**设置页**的图标，不是面板元素（docs/29 T5 只把「面板元素」的口径钉在行 chip 上） |

**唯一图标来源**：表收的是**面板条上的宿主元素 + 设置页宿主行表里引用它的四条宿主行**（投送暂存 / 终端 / 剪贴板 / 笔记），每个字面量只收在一处，视图取它、用例钉它：

```swift
// DynamicIsland/components/Tabs/PanelIcon.swift
enum PanelIconTable {
    static let home: PanelIcon = .symbol("house.fill")
    static let shelf: PanelIcon = .airDrop
    static let usage: PanelIcon = .symbol("chart.bar.doc.horizontal")
    static let clipboard: PanelIcon = .symbol("doc.on.clipboard")
    static let notes: PanelIcon = .symbol("square.and.pencil")
    static let terminal: PanelIcon = .symbol("apple.terminal")
    static let extensionFallback: PanelIcon = .symbol("puzzlepiece.extension")
}
```

`TabSelectionView.slots(...)` 与 `ModuleSettingsSection.hostPanelRows` 都引用这张表（不再各自写字面量），用例直接断言表——这就是「改回 `tray.fill` 会红」的依据。**表外还有两类既有来源**：取色器行（`ModuleSettingsSection.swift` 的 `.symbol("eyedropper")`）与首页内置日历行的 chip（同文件 `HomeCalendarSettingsRow` 的 `.symbol("calendar")`）是直接字面量；**模块 tab 的图标不在这张表里**：它们与模块行 chip 一样由 manifest 投影（`ModuleRegistry.tabEntries` 的 `symbolName` / `manifest.icon.name`），链路不变。

**设置页 chip 的第三个调用点**（`ModuleSettingsSection` 的模块行）传的是 `manifest.icon.name ?? ""`，现状靠「空名不画」——改型后该参数是 `PanelIcon?`（`nil` = 不画），行为逐字保留。

## 备选与取舍

**周起点**

1. **跟随系统 `firstWeekday`（现状）**：不选。本机 zh_CN 的系统口径就是周日（`Calendar.current.firstWeekday == 1`），照抄系统等于照抄出用户要改的那个结果；而且「系统怎么设」与「产品要什么」是两件事。
2. **做成设置项（周一 / 周日 / 跟随系统）**：不选。用户要的是「从周一开始」，不是「能选」；新增一个配置面要付的代价（默认值、迁移、文档、验收）远大于收益。真要选，等有第二个地区性诉求再说。
3. **硬编码周一（本次）**：选它。一个常量 `firstWeekday = 2` 写在唯一一处，全局一致；代价是产品口径不再跟随区域设置（记 §已知限制）。

**隔空投送字形**

1. **找现成 SF Symbol**：不选。这一枚在本机 macOS 27 上不存在（实测 `nil`）。
2. **用 `NSSharingService` 的彩色 App 图标**：不选。单色面板条上它与其余七枚不同套，且选中/未选中档无法跟随 `foregroundStyle`。
3. **抠系统资源 / 私有 API**：不选。脆（系统版本一动路径就变），且与 ADR-0010「私有 API 收敛而非清零」的方向相反。
4. **自绘字形（本次）**：选它。模板着色、比例可控、零依赖；代价是「近似 Apple 那枚」而不是逐像素一致（记 §已知限制）。

**「与日历撞脸的那一枚」怎么处理**

1. **只换隔空投送图标，两枚撞脸的不管**：不选。用户的原话是「两个图片没有区别，要调整」——撞脸那对没动，他下轮还会看到同一个问题。
2. **改日历 tab 的图标**：不选。日历那枚（卡片 + 点阵）是它最标准的表示，而且日历 tab 是本次另一条任务的主角（周起点），一起动会让两次改动的观感混在一起。
3. **换掉笔记 tab 的图标（本次）**：选它。候选里 `square.and.pencil` 轮廓带一支铅笔、与「圆角卡片」一眼可分，且是 macOS 上「新建/编辑笔记」的惯用符号；`note`（折角纸）仍是卡片形，`list.bullet.rectangle` 更是原样，都不解决问题。

**笔记换装的披露**：这一枚的换装是**本次唯一的视觉裁量**（用户点名要的是隔空投送那一枚）。它由「两个图片没有区别，要调整」直接覆盖，记为 D-07，收尾报告里单独点名——用户若要保留原样，回滚只需一行。

## 接口与数据形状

```swift
// DynamicIsland/extensions/Calendar+Display.swift（新文件）
extension Calendar {
    /// 面板日历（首页整宽日历行 + 展开面板日历页 + 按月取数窗口）唯一的**显示日历**：
    /// 周起点固定周一（`firstWeekday = 2`，Foundation 的 1-based 口径）。
    static var gourdDisplay: Calendar { /* Calendar.current + firstWeekday = 2 */ }
}
```

```swift
// DynamicIsland/components/Calendar/DynamicIslandCalendar.swift · enum MonthGridLayout
// 签名全部不变，只有 `calendar:` 的默认值从 `.current` 改成 `.gourdDisplay`
static func days(forMonth month: Date, calendar: Calendar = .gourdDisplay) -> [Date]
static func weekCount(for month: Date, calendar: Calendar = .gourdDisplay) -> Int
static func monthGridHeight(forMonth month: Date, calendar: Calendar = .gourdDisplay) -> CGFloat
static func firstDay(ofMonth month: Date, calendar: Calendar = .gourdDisplay) -> Date
static func monthWindow(forMonth month: Date, calendar: Calendar = .gourdDisplay) -> DateInterval?
static func daysWithEvents(inMonth month: Date, events: [EventModel], calendar: Calendar = .gourdDisplay) -> Set<Date>
static func eventDays(forDisplayedMonth month: Date, snapshot: MonthEventSnapshot, calendar: Calendar = .gourdDisplay) -> Set<Date>

/// 新增（从 MonthGridView.weekdaySymbols 抽出的纯函数，视图与用例共用一条算式）：
/// 返回按 `calendar.firstWeekday` 旋转过的极短星期表头（本产品口径下 = ["一","二","三","四","五","六","日"]）。
static func weekdaySymbols(for calendar: Calendar = .gourdDisplay) -> [String]
```

```swift
// DynamicIsland/components/Tabs/PanelIcon.swift（新文件）
/// 面板图标：SF Symbol 之外，隔空投送用自绘字形。
enum PanelIcon: Equatable {
    case symbol(String)
    case airDrop
}

/// 渲染层：`.symbol` → `Image(systemName:)`（**不加框**——既有符号的排布逐字不变）、
/// `.airDrop` → `AirDropGlyph().frame(width: 13, height: 13)`（交付尺寸，记 D-10）。
/// 13×13 的判据 = **与相邻 13pt 符号视觉等高**（T3 渲图实测：字形墨迹 12.4×11.3pt，
/// 落在实拍 tab 条图标墨迹 11–13pt 的区间内）。
struct PanelIconView: View { let icon: PanelIcon }

/// 隔空投送字形（自绘）：圆心点 + 三段同心弧、底部开口 ±35°。
/// 几何（以字形外缘半径 R 为单位）：点 0.13R，弧环心 0.33R / 0.65R / 0.90R，线宽 0.113R，圆头线帽。
/// 颜色走 `.foreground` 着色（Canvas 的 `Shading.foreground`），因此跟随 `foregroundStyle`。
///
/// **开口方向按视觉描述定，不按角度约定定**：开口居中在**正下方**（两段端点在正下方两侧各 35°）。
/// 角度常量的正方向随坐标系而定，因此 T3 以「渲染出的 PNG」为准——判据是「下缘中线无墨迹、上缘有墨迹」，
/// 由 `glyph-structure.py` 的像素检查自动判定（T5 的几何断言只管开口宽度 70° 与三段半径）。
struct AirDropGlyph: View { var body: some View { /* Canvas */ } }

/// 隔空投送字形的几何度量（**四个量取值是契约**：`AirDropGlyphMetricsTests` 逐字钉，记 D-11）。
/// 以字形**外缘半径 R** 为单位；取值出处 = 用户 2026-10-09 给的控制中心参考图（中心行 / 列亮度
/// 扫描 + 16 倍放大下量弧端位置；与 Apple 那枚不保证逐像素一致，见 §已知限制 1）。
struct AirDropGlyphMetrics {
    static let dotRadiusFactor: CGFloat = 0.13                    // 圆心点半径
    static let ringRadiusFactors: [CGFloat] = [0.33, 0.65, 0.90]  // 三段弧环心（内 → 外）
    static let strokeFactor: CGFloat = 0.113                      // 线宽（圆头线帽）
    static let gapDegrees: CGFloat = 70                           // 底部开口总跨度（每侧 35°）

    // 四个实例只读镜像（`var dotRadiusFactor: CGFloat { Self.dotRadiusFactor }` …）：纯转发，
    // 只为「视图按实例读几何」与「用例按静态常量钉几何」两种读法都能被断言（D-11）。
}

/// 面板图标表（唯一一份面板图标字面量）：视图取它、用例钉它。
/// 表收的是**面板条上的宿主元素 + 设置页宿主行表里引用它的四条宿主行**——面板条上的宿主元素 =
/// Home / 投送暂存 / 用量 / 笔记 / 剪贴板档 / 终端 / 扩展 tab 缺名回落（`extensionFallback`），
/// 四条宿主行 = 投送暂存 / 终端 / 剪贴板 / 笔记；取色器行与首页内置日历行的 chip 是表外的直接
/// 字面量，模块 tab / 模块行的图标仍由 manifest 投影（`ModuleRegistry.tabEntries`）。
enum PanelIconTable { … }   // 取值见 §做法 机制二「唯一图标来源」
```

```swift
// DynamicIsland/components/Tabs/TabSelectionView.swift
struct TabModel { let label: String; let icon: PanelIcon; … }   // icon: String → PanelIcon
struct TabButton { let icon: PanelIcon; … }                       // 参数类型同上
```

```swift
// DynamicIsland/components/Settings/ModuleSettingsSection.swift
struct HostSurfaceRow {
    let id: String
    let nameKey: String
    let icon: PanelIcon          // 原 `symbolName: String`（改名 + 改类型；语义从「符号名」变成「面板上那一枚图标」）
    let key: Defaults.Key<Bool>
    let panelTab: PanelHostTab?
}

// 同一文件的 ModuleSymbolChip（三个调用点：宿主行 :966、首页内置日历行 :1563、模块行 :1612）
// 参数由 `symbolName: String` 改 `icon: PanelIcon?`——`nil` = 不画（保住模块行
// `manifest.icon.name ?? ""` 的「空名不画」口径），渲染走 `PanelIconView(icon:)`。
```

**形状不变量（用例按它断言）**：

- `Calendar.gourdDisplay.firstWeekday == 2`；`gourdDisplay.veryShortStandaloneWeekdaySymbols` 本身仍是系统顺序（`["日","一",…]`），旋转发生在 `weekdaySymbols(for:)` 里。
- `weekdaySymbols()` = `["一","二","三","四","五","六","日"]`。
- 2026-10：网格 = 2026-09-28（周一）… 2026-11-01（周日），5 周，行高 232；按月窗口 = `[2026-09-28, 2026-11-02)`。
- 2026-11：周一起始 6 周（周日起始 5 周）——同一月份两档周数不同，正是本次改动的可观察结果。

## 明确不做

1. **进度块「本周」与待办模块的「本周」分桶都不动**（都随系统 `firstWeekday`：docs/31 第 8 条 + `TodoBucketing` 的 `.weekOfYear`，由 `TodosModule` 传 `autoupdatingCurrent`）。用户点的是「两个日历面板」；改了它们会让「本周剩 N 天」的数字与待办「本周」桶里的条目变化，那不是他要求的。**这两处要在收尾报告里一起点名**（2026-10-09 T1 审查补出 todos 那一处），供用户决定是否下一轮一并改。
2. **不做「周起始日」设置项**（见 §备选与取舍 周起点·2）。
3. **日历 tab 的图标与 `CalendarModule` 的 manifest 图标不动**（仍是 `calendar`）。
4. **不动其余 tab 的图标**（Home / 启动台 / 通知 / 待办 / 终端 / 用量 / 扩展 / 剪贴板档的 `doc.on.clipboard`），也不动设置页侧栏的页图标。
5. **不动 `EventListView.clockLabel(for:calendar:)`**（同文件里另一处 `calendar: Calendar = .current`，2026-10-09 复核：它的宿主是 `EventListView`，本节初稿写成 `HomeTodayListLayout`）：它算事件行的时刻文案（按日粒度），与周起点无关。**判据要把它排除在外**，否则「源码里不再有 `.current` 默认值」这条检查永远不成立。
6. **`tray.fill` / `note.text` 另外三处同义落点本轮不动**（它们不是「面板元素的图标」）：`ShelfInlineLiveActivity.swift` 的折叠态投送反馈图标（描述的是「文件正落进暂存」这个动作）、`NotchNotesView.swift` 的笔记页空态提示图标、`MinimalisticMusicPlayerView.swift` 的 Notes 明细行图标。**收尾报告里点名**，用户要一并换再说。
7. **不引入第三方图标资源、不抠系统私有资源**；不改 `mediaremote-adapter` 等上游件。
8. **不动日期轮（`WheelPickerIndexMath`）与农历 / 节假日链路**：它们与「周起点」无关（按日粒度）。
9. **不改 `MonthGridLayout` 任何函数的签名**，也不改既有用例里显式注入的 `Calendar`（唯一例外：渲染用例 `testHomeCalendarGridViewportFitsTheMonthAtItsRowHeight` 的夹具随产品档切换，见 §背景与目标 · 关键约束）。

## 实际交付

**已实现并提交**（2026-10-09，p9 批次；本节与 §已知限制 / §决策摘要 的回写由收尾前的整体终审清单驱动）。实现批次 = `9c378bce..bc8d95b0` 的十个提交；本节的回写与其伴生的 `PanelIcon.swift` 注释对齐是随后的两次文档面提交（不改任何行为）。

**改动文件清单**（`git log --oneline 9c378bce..bc8d95b0` 与 `git diff --stat 9c378bce..bc8d95b0` 逐字核对；`+` / `−` 为实现批次的行数）：

| 文件 | 改动 |
|---|---|
| `DynamicIsland/extensions/Calendar+Display.swift`（新，+48） | `Calendar.gourdDisplay`（`Calendar.current` + `firstWeekday = 2`） |
| `DynamicIsland/components/Calendar/DynamicIslandCalendar.swift`（+36/−21） | `MonthGridLayout` 七函数默认值 `.current` → `.gourdDisplay` + 新纯函数 `weekdaySymbols(for:)`（原 `MonthGridView.weekdaySymbols` 私有属性逐字抽出、随后删除）；`MonthGridView` / `StandaloneCalendarView` 持有的日历改 `.gourdDisplay` |
| `DynamicIsland/Host/HomeCalendarRow.swift`（+5/−1） | `rowHeight(forMonth:calendar:)` 默认值改 `.gourdDisplay`（静态入口 `rowHeight` 与 `HomeStripView` 三处预算自动跟随；+注释） |
| `DynamicIsland/managers/CalendarManager.swift`（+3） | `updateMonthEvents` 只补注释——`monthWindow(forMonth:)` 走默认值自动同源 |
| `DynamicIsland/components/Tabs/PanelIcon.swift`（新，+136） | `PanelIcon` / `PanelIconTable` / `AirDropGlyphMetrics` / `AirDropGlyph` / `PanelIconView` |
| `DynamicIsland/components/Tabs/TabSelectionView.swift`（+17/−10） | `TabModel.icon`（含 init）改 `PanelIcon` + 七条接线（含扩展 tab 缺名回落 `PanelIconTable.extensionFallback`、模块投影 `.symbol(entry.symbolName)`） |
| `DynamicIsland/components/Tabs/TabButton.swift`（+4/−3） | `icon: PanelIcon` + 渲染点改 `PanelIconView` |
| `DynamicIsland/components/Settings/ModuleSettingsSection.swift`（+44/−17） | `HostSurfaceRow.symbolName → icon: PanelIcon`、`hostPanelRows` 五行取表、`ModuleSymbolChip.icon: PanelIcon?` 与三个调用点（宿主行 / 首页内置日历行 / 模块行） |
| `DynamicIslandTests/ModuleKernelTests.swift`（+151） | `CalendarWeekStartTests`（5 条：①–④、⑥；⑤ 按计划不写成用例）+ `AirDropGlyphMetricsTests`（2 条） |
| `DynamicIslandTests/TakeoverEnablementTests.swift`（+155） | `PanelIconTests`（3 条：表七项逐字 / 五行同源 / 符号可解析） |
| `DynamicIslandTests/HomeStripLayoutTests.swift`（+28/−3） | 渲染用例夹具随产品档切换（`firstWeekday: 2`、2026-11 → 6 周）+ 新增 `testHomeCalendarRowHeightDefaultsToTheDisplayCalendar` |
| `docs/00-decisions.md`（+34） | ADR-0016 / ADR-0017 |
| `docs/09-features-and-mechanisms.md`（±1） | §C 时间「月历格的第二行」一行补 p9 口径 |
| `docs/guide/README.md`（±1） | 标签栏那句补「『文件暂存』那枚 tab 的图标是 macOS 隔空投送样式的同心弧」 |
| `docs/guide/modules.md`（±1） | 日历节补「月历**周一起始**（表头 一…日）」 |
| `docs/34-calendar-week-and-panel-icons.md`（+282） | 本文档（P 轮） |

**交付物**（与 §做法 的两张表逐条对上）：

- **周起点**：唯一落点 `Calendar.gourdDisplay`；消费点 = `MonthGridLayout` 七函数的 `calendar:` 默认值（含新纯函数 `weekdaySymbols(for:)`）+ `MonthGridView` / `StandaloneCalendarView` 持有的日历 + `HomeCalendarRow.rowHeight(forMonth:calendar:)` 默认值 + `CalendarManager.updateMonthEvents` 的按月窗口（不写代码、走 `monthWindow` 默认值）。
- **面板图标**：tab 条「投送暂存」= `.airDrop`（自绘字形，13×13 交付尺寸）、「笔记」= `square.and.pencil`（剪贴板档 `doc.on.clipboard` 不动）；设置页三处 chip 都走 `PanelIconView`，投送暂存行与笔记行与面板**同图**（A7）。
- **用例**：`CalendarWeekStartTests` / `PanelIconTests` / `AirDropGlyphMetricsTests`（位置与条数见上表）；渲染取证脚本 `glyph-structure.py`（像素判据，退出码 0）与渲图留档在 `.workflow/p9-calendar-week-icon/evidence/`（不入库）。
- **长期记录**：ADR-0016 / ADR-0017；`docs/09` 一行；用户手册两处（README 标签栏、modules 日历节）。

**与计划的偏离**（逐条；均为实现级，结论与边界未变）：

1. `AirDropGlyphMetrics` 在四个静态常量之外**增了四个实例只读镜像**（计划只列静态常量）——为「视图按实例读几何 / 用例按静态常量钉几何」两种读法都能被断言（后记 D-11）。
2. 扩展 tab 缺名回落的**字面形态**：实现取表内常量 `PanelIconTable.extensionFallback`（计划片段写的是内联 `"puzzlepiece.extension"`）——行为等价，扩展自带符号名仍逐字优先（T3 审查采纳）。
3. **「唯一一份图标字面量」的口径收敛**：初稿的绝对说法已限定为「表收的是面板条上的宿主元素 + 设置页宿主行表里引用它的四条宿主行」，并显式列出表外来源（取色器行、首页内置日历行的 chip、模块 tab / 模块行的 manifest 投影）——见 §做法 机制二「唯一图标来源」与 ADR-0017，与实现逐字一致。
4. `HomeStripLayoutTests` 的渲染用例：夹具切到产品档、「月份 → 周数」表重算（计划内明定的唯一既有用例改动；环境前提记 §已知限制 8）。

**遗留项**：

1. **上屏观感待用户过目**：A1（两个面板表头「一…日」/ 网格首格周一）与 A5 / A6 / A7（tab 条两枚与设置行 chip 的观感）尚无「改动后」的上屏截图；本批留档的是渲图取证（字形结构像素判据、与参考图并排、13pt 交付尺寸）。上屏与观感由用户复看（计划 §不验证的部分）。
2. **13×13 热区与 chip 等高待上屏复核**：13pt 使「投送暂存」tab 的视图宽 18 → 13pt（点击热区随之变小）；`ModuleSymbolChip` 里 `.airDrop` 与相邻 `.symbol` 不等高（矮 1.38pt、中心偏上 0.5pt）。上屏判定，必要时把 13×13 改 14×14（一行）。
3. **todos「本周」仍随系统未改**：`TodoBucketing` 的 `.weekOfYear`（`TodosModule` 传 `autoupdatingCurrent`）与进度块「本周」（`WorkdayCalendar`，docs/31 第 8 条）都仍随系统 `firstWeekday`——§明确不做 1 点名，供用户决定是否下一轮一并改。
4. 本文档 §接口与数据形状 的行号注释已漂移（`:966/:1563/:1612` → 实际 `:986/:1587/:1639`），本轮未动（T6-fix 披露项）。

## 已知限制

1. **字形是近似**：`AirDropGlyph` 的比例按用户给的控制中心截图量取（点 0.13R、弧 0.33/0.65/0.90R、线宽 0.113R、开口 ±35°），与 Apple 那枚**不保证逐像素一致**；参考图本身是低分辨率截图（字形 ≈30px 宽），量取有 ±1px 级误差。
2. **周起点不跟随区域设置**：产品口径固定周一。切到「周日起始」习惯的地区/语言时，面板日历仍从周一开始——这是 D-01 的代价，明记在此。
3. **面板高会随月份变**（既有行为）：周一起始下 2026-11 是 6 周 → 首页日历行 268（周日起始下 232）。docs/30 §做法 机制六 已接受该行为，本次不改。
4. **笔记 tab 的换装是视觉裁量**（D-07）：用户点名的是隔空投送那一枚；笔记这枚换 `square.and.pencil` 是为了消掉「两枚同形」，若用户要保留原样，回滚是一行。
5. **`HostSurfaceRow.symbolName` 改名为 `icon` 且类型变 `PanelIcon`**：这是行表字段的一次小改型，任何外部（未来）按字符串读它的代码要一起改；今天仓内只有渲染点与用例，已一并更新。
6. **快照语义**：`Calendar.gourdDisplay` 是 `Calendar.current` 的**值拷贝**（不是 `autoupdatingCurrent`）；会话中途改系统时区 / 区域要等视图重建才跟随（周起点本就不跟随，见 D-01；改动前的 `private let calendar = Calendar.current` 是同一形态，非本次引入）。
7. **`.symbol("")` 会画出空的 24×24 强调色底**：`ModuleSymbolChip` 只判 `nil`，不再做空串防御；今天不可达（`ModuleManifest` 解析期已拒空名 + 模块行调用点已折 `nil`），责任在调用点。
8. **渲染用例的环境前提**：`HomeStripLayoutTests` 那条量视口的用例（`testHomeCalendarGridViewportFitsTheMonthAtItsRowHeight`），夹具按 **GMT** 造月首、视图按本机时区归月——宿主机需**东于 GMT**（本机 UTC+8 满足）；换西半球机器会红（既有耦合，本轮沿用）。
9. **日粒度路径仍走 `Calendar.current`**：滚动落点与月首 / 日首归一化（`HomeCalendarRow` 的滚动靶、`MonthGridView` 的 `.id` 与 `startOfMonth`）与周起点无关，本次**不动**（两枚日历同时区，日粒度结果逐字相同）。

## 验收标准

- **A1** 两个面板的月历表头 = 「一 二 三 四 五 六 日」（日历页与首页日历行各一次，上屏可见）。
- **A2** 网格首格 = 当月 1 日所在周的周一（2026-10 → 2026-09-28），末格 = 月末所在周的周日（2026-10 → 2026-11-01）。
- **A3** 按月取数窗口与网格两端逐字一致（`monthWindow` = `[首格, 末格 + 1 天)`）——否则网格末端那天不会有点。
- **A4** `Calendar.gourdDisplay.firstWeekday == 2`，且 `MonthGridLayout` 一族带 `calendar:` 的函数**不再**默认 `.current`。
- **A5** tab 条第 8 枚（投送暂存）显示为同心弧字形：一眼可读出「圆心点 + 三段弧 + 底部开口」，非选中档灰、选中档跟随强调色；与参考图并排同构。
- **A6** tab 条第 5 枚（笔记）不再是「圆角卡片 + 实心顶带」的轮廓，与第 4 枚（日历）一眼可分。
- **A7** 设置页「面板组件」节的投送暂存行与笔记行 chip 与面板上那两枚**同图**。
- **A8** 全量单测绿（`xcodebuild test … -only-testing:DynamicIslandTests`），且除那条渲染用例（`testHomeCalendarGridViewportFitsTheMonthAtItsRowHeight`，其夹具与月份 / 周数表随产品档切换）外，既有用例口径零改。
- **A9** 未列入改动的图标逐字不变（Home / 启动台 / 通知 / 待办 / 终端 / 日历 / 剪贴板档）。

## 决策摘要

| ID | 决策 | 来源 | 理由 |
|----|------|------|------|
| D-01 | 面板日历的周起点**固定周一**（不再跟随系统 `firstWeekday`） | 用户 | 用户 2026-10-09：「两个日历面板，开始时间都是从周一开始」 |
| D-02 | 周起点的唯一落点 = 新增的 `Calendar.gourdDisplay`（`Calendar.current` + `firstWeekday = 2`），消费点改**默认值**而不是改调用点 | agent | 一个常量只写一处；`MonthGridLayout` 签名不变，除那条渲染用例（`testHomeCalendarGridViewportFitsTheMonthAtItsRowHeight`，其夹具与月份 / 周数表随产品档切换）外，既有用例口径零改 |
| D-03 | 进度块「本周」的周区间**不动**（仍随系统自然周） | agent | 用户点的是「两个日历面板」；改了会动「剩 N 天」的数字（§明确不做 1，收尾报告点名） |
| D-04 | 隔空投送（投送暂存）tab 的图标改为 macOS 控制中心那枚字形 | 用户 | 用户 2026-10-09：「隔空投送使用 mac 系统这种图标」+ 目标截图 |
| D-05 | 字形**自绘**（`AirDropGlyph`，Canvas + `.foreground` 着色），不用 SF Symbol / 不用彩色 App 图标 / 不抠系统资源 | agent | 本机 macOS 27 无 `airdrop` 符号（实测 nil）；共享服务 `.image` 是彩色 App 图标（单色条上不同套） |
| D-06 | 图标获得类型：`enum PanelIcon { case symbol(String), airDrop }` + `PanelIconView` 统一渲染；`TabModel.icon` / `TabButton.icon` / `HostSurfaceRow.symbolName→icon` 跟着改型 | agent | 裸字符串表达不了自绘字形；类型化后「同一面板元素同一枚图标」可断言 |
| D-07 | 与日历撞脸的**笔记 tab** 一并换成 `square.and.pencil`（tab 与设置行 chip 同改） | agent | 用户红框圈的就是日历与笔记这两枚并说「两个图片没有区别，要调整」；只换隔空投送那枚不解决他看到的那对（本次唯一视觉裁量，收尾报告点名） |
| D-08 | `MonthGridView` 的表头旋转抽成纯函数 `MonthGridLayout.weekdaySymbols(for:)` | agent | 让「表头顺序」第一次可断言（否则它埋在视图私有属性里，回归测试钉不住） |
| D-09 | 设置页侧栏的页图标（`SettingsTab.notes` 等）不改 | agent | docs/29 T5 的口径只把「跟面板走」钉在「面板组件」节的行 chip 上；侧栏图标是设置页的图标 |
| D-10 | `.airDrop` 的**交付尺寸 13×13pt**（判据 = 与相邻 13pt 符号**视觉等高**；出处 = T3 渲图实测：字形墨迹 12.4×11.3pt，落在实拍 tab 条 11–13pt 区间）；`PanelIconView` 只给 `.airDrop` 加框、`.symbol` 档**不加框**（既有符号的排布逐字不变） | agent（T3 渲图实测） | 13pt 与相邻最小符号（`terminal` 11.7pt）同档；14pt 会高过 `terminal` / `notes` 一档——热区与 chip 等高待上屏复核（§实际交付 · 遗留项 2） |
| D-11 | `AirDropGlyphMetrics` 的四个量取值（`0.13` / `[0.33, 0.65, 0.90]` / `0.113` / `70°`）是**契约**（`AirDropGlyphMetricsTests` 逐字钉）；实例只读镜像只为「视图按实例读几何、用例按静态常量钉几何」两种读法都能被断言而存在（沿用仓库既有先例：为可断言的契约放开可见性，而不是为测试改行为） | agent（T5） | 量取值来自参考图量取、不是可推导的比例——只断言「递增 / 落在某区间」会放过把比例换成别的量取值 |
