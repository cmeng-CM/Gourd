# 首页五处修正：日历遮罩线、收起顺序、前台应用块、最小宽度空白、封面开关

| 项 | 值 |
|---|---|
| 状态 | **已实现（2026-09-30）**；提交范围 `f56c8a54..ac9a9aeb`（4 个提交，未 push；范围与上屏证据见 §实际交付） |
| 最后更新 | 2026-09-30 |
| 关联来源 | 用户 2026-09-30 的五条反馈（截图：`.workflow/p2-home-fit/evidence/`）；[21](21-strip-honesty.md)（丢块提示）；[22](22-shortcuts-and-frontapp.md)（前台应用块）；[17](17-nookx-adoption.md)（strip 与日历行） |

> **怎么读**：§背景与目标 / §明确不做 / §备选与取舍 是判断依据；§接口与数据形状 是执行者契约（可跳过）；
> §已知限制 / §实际交付 留给后来人。
>
> **读者分界**：给人读的是背景、取舍、不做的部分与限制；§做法 机制与 §接口与数据形状 给执行者与模型。

## 一句话方案

按用户实测反馈修五处：**① 日历行不再画上下两条渐变遮罩**（那是滚动提示，只在独立日历里需要）；
**② 面板高度不够时先收日历行、保住 strip**（现在反了：先丢 strip）；**③ 前台应用块从"最近切换历史"
改成"所有打开的 App"**（来源换成 `NSWorkspace.runningApplications`，只列可激活的常规 App，
点一下必须切过去）；**④ 修最小宽度（770pt）下"块被分配了宽度却画不出来"的空白**（实测复现：
第二个之后的块空白、条尾 `＋2`）；**⑤ 音乐封面可配置显示**（模块 config 新增 `showAlbumArt`，默认显示）。

## 背景与目标

### 现状（五条，逐条对应代码）

| # | 现象（用户原话） | 现状 |
|---|---|---|
| 1 | 「日历的这两条遮罩线去掉」 | `MonthGridView`（`DynamicIslandCalendar.swift` 的 `datePicker(viewportHeight:)`）在网格上下各叠了一条 16pt 的 `LinearGradient`（黑 0.65 → 透明）作为滚动提示；首页日历行复用同一个视图、网格不滚动时它们看着就是两条脏线 |
| 2 | 「高度变小后，应该收起第二排的日历，而不是第一排」 | `NotchHomeView.standardHomeContent` 的取舍是：`stripHeight = available − 日历行高 − 间距`，`stripHeight < HomeStripView.minimumUsableHeight(152)` 时**不画 strip**，日历行照画——顺序反了 |
| 3 | 「台前调度显示了，但点击没反应；这里不是只有台前调度的内容，而是所有打开的软件都要显示」 | `FrontAppStore.recent` 是**前台切换历史**（只记本进程活过的那几个），来源是激活通知；条目按 pid 激活，对无窗口/系统类进程（台前调度那类）点不动；条数上限 `maxRecentApps`（3…8） |
| 4 | 「宽度最小 770，到了 770 后第一排就只显示播放器了，右侧还空着很多」 | **实测复现**：770pt 下 strip 显示音乐块，右侧整片空白、条尾 `＋2`——被 plan 判为"可见"的块没有画出来（`HomeStripLayout` 的摆放与块的 `GeometryReader` 内容之间有一处没对齐，见 §做法 机制四） |
| 5 | 「音乐播放区域这个封面应该是可以配置是否显示，看下现在是否有这个能力」 | **没有**：`Constants.swift` 里只有 slider/锁屏相关键，`MusicModule` 的 config 只有 `playerColorTinting` / `useMusicVisualizer`——封面恒定显示 |

### 预期结果（改后）

1. 首页日历行的网格上下**没有**那两条渐变；独立日历（`StandaloneCalendarView`）里保留（那里网格可滚，提示有用）。
2. 面板高度不足时：**先整行收起日历**（第二排），strip 只要还能完整显示就留着；两者都放不下时才只有 strip 或整条不画。
3. 前台应用块显示**所有打开的常规 App**（当前应用置顶 + 其余按最近使用排序），点任意一格切过去；
   不可激活的条目（无 bundle / 非 `.regular` 激活策略）**不列**，因此不存在"点了没反应"。
4. 任意宽度（含最小 770pt）下，凡是被 plan 判为可见的块都**真的画出来**；条尾 `＋N` 的 N 与"实际没画出来的块数"一致。
5. 音乐块的封面可以在模块 config 里关掉（`showAlbumArt = false`），关掉后封面位置让给标题/进度/控制，不留空洞。

## 做法

### 机制一：滚动提示改成"按需"

`MonthGridView` 的上下渐变只服务于"网格可滚"的场景。给它一个显式开关（视图参数，默认 `true` 保持独立日历现状），
首页日历行传 `false`；**不删渐变本身**（独立日历仍要用）。

### 机制二：高度不足时的取舍顺序反转

首页内容的分配从"先给日历行固定 294pt、strip 拿剩下的"改成**两段判定**：
① 先按 strip 的最小可用高度（`HomeStripView.minimumUsableHeight`）问一句"strip 留得下吗"；
② 留得下 → strip 拿 `available − 日历行高 − 间距`（现状不变）；留不下 → **日历行整行不画**，
strip 拿全部 `available`；③ 连 strip 都留不下（`available < minimumUsableHeight`）→ 只画日历行
（若其行高也放不下则不画，面板只剩其它元素）。判据集中在一处纯函数里，便于用例穷举三种档。

### 机制三：前台应用块改"所有打开的 App"

数据来源从"激活历史"换成 **`NSWorkspace.shared.runningApplications`**（每次需要时现取，不用通知累积）：
筛 `activationPolicy == .regular`、排除自身、按"当前应用 → 最近使用（`recent` 作为排序依据）→ 名称"排序；
点击仍走 `NSRunningApplication.activate(options:)`，激活失败记日志（不再出现"点了没反应还没记录"）。
历史（`recent`）保留，但降级成**排序依据**而不是内容来源。

### 机制四：最小宽度下的空白块

770pt 复现（截图 `.workflow/p2-home-fit/evidence/repro-770-blank.png`）：`plan` 判 `visibleCount == 3`、
条尾显示 `＋2`，但只有第一块画出来。**先取证再改**（不许猜）：按候选假设逐条排除——
① `HomeStripLayout.placeSubviews` 的零提案分支是否被误命中（`plan.widths.count` 与 `subviews` 数是否错位）；
② 块的 `GeometryReader` 内容在"被压缩到最小宽度"时的自报尺寸；③ `Cache` 的 plan 复用判据
（`available` + `tailHintWidth`）在宽度变化时是否复用了旧 plan；④ `ForEach` 的 `id` 顺序与 items 顺序是否一致。
找到根因后**只改一处**（最小修复），并把复现用例固化进 `HomeStripLayoutTests` / 一份可重跑的探针脚本。

### 机制五：音乐封面开关

`MusicModule` 的 manifest config 加 `showAlbumArt`（`boolean`，默认 `true`），视图读它决定是否画封面；
关掉时标题/进度/控制仍按现有布局左对齐，不留空洞。宿主侧的块宽声明（300/420）本批不动——
封面关掉只是块内变宽裕，是否收窄留给用户后续反馈（§明确不做）。

## 备选与取舍

**① 遮罩线：删掉 / 全局保留 / 按需显示？** 选**按需**（机制一）。独立日历里网格高于视口、渐变是有效提示；
删掉是拿一个场景的脏线换另一个场景的信息缺失。

**② 收起顺序：反转判定 / 让用户配 / 按内容重要性排序？** 选**反转判定**（机制二）。"谁先收"是产品默认值，
配置化会多一个没人调的旋钮；strip 是"扫一眼"的主内容，日历是"展开看"的次内容——所以先收日历。

**③ 前台应用块：通知历史 / `runningApplications` 现取？** 选**现取**（机制三）。用户要的是"所有打开的软件"，
现取天然包含"启动前就开着的 App"（历史做不到，除非扫全量进程）；代价是每次绘制现取一次数组
（系统调用，成本与 `NSWorkspace` 的既有用法同级）。

**④ 空白块：先修 plan 的摆放 / 先改块内容？** 先取证再定（机制四）。在根因未定前动任何一侧都可能是猜。

**⑤ 封面开关落在哪：模块 config / 上游 `Defaults` 键？** 落在**模块 config**（`showAlbumArt`）。
理由：它是接管模块自己的呈现开关，`config` 正是为此存在；上游键是"功能的开关"（`showStandardMediaControls`），
不该再塞一个呈现项。

## 接口与数据形状

> **回写（2026-09-30）：本节按落地代码校正**。与首稿示意不同的三处已就地改判并与理由一起写在各段下：
> 前台应用的**注入点摊成值类型**、`switcherApps` 的**落点是类内成员**、块内格数是**宽高两维预算**；
> 另补上首稿没有的**封面开关的组件页入口**。

```swift
// 机制一：`MonthGridView` 增加一个视图参数（末尾参数；默认值 = 独立日历现状）
struct MonthGridView: View {
    /// 日格网格上下那两条**滚动提示渐变**画不画（`datePicker(viewportHeight:)` 里两处 `LinearGradient`
    /// 的唯一开关）。只切「画不画」，不切样式 / 16pt 高 / 贴边位置。
    var showsScrollFades: Bool = true

    init(selectedDate: Binding<Date>,
         scrollTarget: Binding<Date?>,
         monthNavigationMovesSelection: Bool = false,
         monthEvents: MonthEventSnapshot,
         onDisplayedMonthChange: ((Date) -> Void)? = nil,
         showsScrollFades: Bool = true)
}

// 机制二：高度取舍的判据收成一个纯函数（新文件 `DynamicIsland/Host/HomeVerticalFit.swift`）
enum HomeVerticalFit {
    enum Layout: Equatable { case both, stripOnly, calendarOnly }

    struct Plan: Equatable {
        let layout: Layout
        /// `.both` = 可用高 − 日历行高 − 间距；`.stripOnly` = **全部**可用高；`.calendarOnly` = 0
        let stripHeight: CGFloat
        /// 日历行画不画。**调用方仍需自己与「用户有没有开日历行」相与**（本类型不认偏好）。
        let showsCalendarRow: Bool
        /// strip 画不画——只看档位（两处都判就会有两份阈值）
        var showsStrip: Bool { layout != .calendarOnly }
    }

    /// 两段问句（先问 strip 单独放不放得下、再问两排一起放不放得下）；**阈值闭区间**
    /// （`available` 恰好等于某个阈值算「放得下」）。
    static func plan(available: CGFloat,
                     calendarRowHeight: CGFloat,
                     rowSpacing: CGFloat,
                     stripMinimumHeight: CGFloat) -> Plan
}
```

三档语义（生产常量 `calendarRowHeight = 294` / `rowSpacing = 8` / `stripMinimumHeight = 152`）：

| `available` | 档 | `stripHeight` | `showsCalendarRow` |
|---|---|---|---|
| < 152 | `.calendarOnly` | 0 | `available >= calendarRowHeight`（生产档恒 `false`） |
| 152 … 453 | `.stripOnly` | `available`（全部） | `false` |
| ≥ 454 | `.both` | `available − 302` | **`true`** |

对应面板高度（`available = openNotchHeight − 16`）：**≥470 → 两排 / 168…469 → 只有 strip / ≤167 → 空面板**。

**`showsCalendarRow` 在 `.both` 且行高传 0 时也返 `true`（既有语义，明确不修）**：调用方在用户关掉日历行时
把 `calendarRowHeight` / `rowSpacing` 都传 0，那时 `available >= 152` 就走 `.both`、而该分支返回的是常数 `true`。
它不会变成"画了一行没有的日历"——`NotchHomeView.standardHomeContent` 拿这个字段时**还要与 `showCalendar` 相与**
（调用方相与，已注释）。字段本身没有被单独断言，但它的调用形态有用例钉住
（`testCalendarRowDisabledHandsAllHeightToStrip`：行高传 0 时走的就是 `.both` 分支、strip 拿全部可用高度）——
评审裁定**不修**（D-11），因为把偏好判据塞进纯函数会让它开始对偏好有意见。

```swift
// 机制三：前台应用的来源（`DynamicIsland/Modules/FrontApp/FrontAppStore.swift`）
/// 「取所有正在运行的 App」的**注入点**：生产实现 = `FrontAppStore.systemRunningApps`
/// （读 `NSWorkspace.shared.runningApplications`），用例传构造的条目。
typealias FrontAppRunningAppsProvider = @MainActor () -> [FrontAppRunningApp]

/// 一次进程表里的**可判定字段**——**不是 `NSRunningApplication`**（那个类没有公开构造器，用例造不出假体，
/// 「筛 `.regular` / 丢无效 pid / 排除自身」这几条恰恰最该被用例钉住——块里列出来的每一格都必须点得动，D-04）。
/// **摊成值类型就是为了可测**：变异实测去掉政策判断会让 3 条断言红。
struct FrontAppRunningApp: Equatable {
    let pid: pid_t
    let bundleID: String?
    let name: String?                                  // 可为 nil：过滤在纯函数里做
    let activationPolicy: NSApplication.ActivationPolicy
}

/// 过滤（`.regular` / `pid > 0` / 名字非空）→ 排除自身 → 排序（当前应用 → `recent` 次序 →
/// `localizedStandardCompare` 名称 → pid 兜底稳定）→ 同 id 去重（留排序靠前的那份）。纯函数，四条各管一件事。
enum FrontAppSwitcher {
    static func apps(from running: [FrontAppRunningApp],
                     current: FrontAppSnapshot?,
                     recent: [FrontAppSnapshot],
                     selfBundleID: String?) -> [FrontAppSnapshot]
}

@MainActor final class FrontAppStore: ObservableObject {
    /// **每次访问现取一次**（无缓存、无时间窗）：`recent` 只当排序依据，内容 = 所有打开的常规 App。
    /// 落点是**类内成员**（首稿示意的 `extension` 未采用——它要读 `private` 的 provider / `selfBundleID` / `current`）。
    var switcherApps: [FrontAppSnapshot] { get }

    /// 第三个参数给默认真实现，用例给假体。
    init(config: ConfigHandle,
         logger: ModuleLogger,
         runningApps: @escaping FrontAppRunningAppsProvider = FrontAppStore.systemRunningApps)
}

// 块内排版预算：**宽决定一行几格、高决定几行**（`DynamicIsland/Modules/FrontApp/FrontAppModule.swift` 末尾）
enum FrontAppGridBudget {
    static let currentIconSize: CGFloat = 28   // 上半当前应用行 = 它的行高
    static let cellIconSize: CGFloat = 20
    static let cellPadding: CGFloat = 2        // 悬停底色左右各 2
    static let cellSpacing: CGFloat = 4
    static let rowSpacing: CGFloat = 6
    static var cellSize: CGFloat { cellIconSize + cellPadding * 2 }      // 24
    static func cellsPerRow(forWidth width: CGFloat) -> Int              // max(0, ⌊(宽 + 4) / 28⌋)
    static func rowCount(forHeight height: CGFloat) -> Int               // max(0, ⌊(高 − 28) / 30⌋)
    static func capacity(forWidth:forHeight:) -> Int                     // 两者相乘，**可为 0**
}
```

**为什么是两维、为什么可为 0**：块宽（180 / 240）与块高（strip 高，最小 152）都约束格数——只按宽度算会让
18 个 App 在矮块里纵向溢出。`cellsPerRow` 放不下一格时返 **0**（被丢的块拿到 `.zero` 提案 → 一格都不画，
而不是画一个越界格子）；`rowCount(152) = 4`，因此生产档 `180×152 = 24` 格 / `240×152 = 32` 格，
超出的**静默不画**（`＋N` 是整块级提示，块内格子没有提示——§明确不做）。

```swift
// 机制五：music 模块 config 新增一键 + 组件页的一个入口（T5-fix）
enum MusicConfigDefaults { static let showAlbumArt = true }
// manifest.config.properties["showAlbumArt"] =
//     ConfigNode(type: "boolean", title: nil, default: .bool(true), values: nil, itemType: nil)
extension MusicModule {
    /// 解析（现读：`content(for: .home)` 每次投影都调一次；缺键 / 类型不符回落默认真）。
    static func showsAlbumArt(from config: ConfigHandle) -> Bool
}

// 组件页入口（`DynamicIsland/components/Settings/ModuleSettingsSection.swift`）：
// **逐字段写死的一张表**（不是按 manifest schema 自动生成的通用 config 渲染器——那是另一个批次）
static let configControls: [ModuleConfigControl]
struct ModuleConfigControl: Identifiable {
    let moduleID: String          // "com.cmeng.gourd.music"
    let key: String               // "showAlbumArt"（与 manifest 逐字段一致，漂一个字就红）
    let nameKey: String           // "settings.modules.music.showAlbumArt"（en / zh-Hans，state = translated）
    let defaultValue: Bool        // = MusicConfigDefaults.showAlbumArt
    func isOn(config: ConfigHandle) -> Bool                            // 与模块侧 `showsAlbumArt(from:)` 同式
    @discardableResult func write(_ value: Bool, config: ConfigHandle) -> Bool
}
// 宿主侧读写用的是**与模块侧同一个** `ManifestConfigHandle`：`ModuleContextFactory.configHandle(for:)`
//（suite 名 `com.cmeng.gourd.module.<shortID>` 与「值按 JSON 字节存」的口径只有一处）。
```

## 明确不做

| 不做的事 | 为什么 |
|---|---|
| 改独立日历（`StandaloneCalendarView`）的滚动提示 | 那里渐变有用（网格高于视口） |
| 面板宽度的最小/默认值调整、日历行高度改档 | 与五条无关；行高 294 是"整月不滚"的既有裁定 |
| 前台应用块显示窗口标题 / 预览 | 需要辅助功能权限（[22](22-shortcuts-and-frontapp.md) §明确不做） |
| 前台应用块改成"关闭 App"/"隐藏"等管理动作 | 本批只做"列全 + 能切"；管理动作要新交互与新权限面 |
| 首页块宽声明随封面开关收窄（300/420 → 更窄） | 属"块宽策略"，要有实测观感后再定；本批只做块内让位 |
| 丢块提示的样式改动（`＋N` 的观感） | 与本批五条无关 |

## 实际交付

**已实现（2026-09-30）**，提交范围 `f56c8a54..ac9a9aeb`（4 个提交、本地、**未 push**）：

| 提交 | 任务 | 范围 |
|---|---|---|
| `cdbaa197` | `T1+T2+T5` | 日历渐变按需 + 高度取舍反转 + 音乐封面开关（7 files / +472 −33） |
| `f78d8a8c` | `T3` | 前台应用块改成所有打开的常规 App（4 files / +513 −63） |
| `13ceebb9` | `T4` | 修最小宽度下的空白块（提案宽钉在可用宽上）（2 files / +257 −0） |
| `ac9a9aeb` | `T5-fix` | 音乐封面开关的界面入口（4 files / +274 −0；范围评审的唯一一条 Important） |

**① 日历行的两条渐变按需**（T1）：`MonthGridView` 新增 `showsScrollFades: Bool = true`（存储属性 + init 末位参数），
`datePicker(viewportHeight:)` 里两处 `LinearGradient` 包进 `if showsScrollFades`；`HomeCalendarRow` 传 `false`。
**渐变样式与 `ZStack` 结构一字未动**，独立日历那一档（默认 `true`）保持原样。

上屏证据：`.workflow/p2-home-fit/evidence/t1-home-no-fade.png`（首页日历行上下无暗带）、
`t1-home-no-fade-zoom.png`（网格区裁剪）、**反事实** `t1-fade-counterfactual.png`（把首页行临时打回 `true` 重建安装 →
两条 16pt 暗带复现 = 用户反馈的那两条线）、`t1-fade-profile.txt`（逐 10px 行亮度剖面：反事实 `y=650..670 → 0.348`，
修复版同位置 `0.602`）。

**② 高度不足先收日历行**（T2）：新增纯函数 `HomeVerticalFit`（`DynamicIsland/Host/HomeVerticalFit.swift`，同步根组、
无需 pbxproj 登记）；`NotchHomeView.standardHomeContent` 改为按 plan 决定画哪几行，视图侧不再自己比高度（阈值只有一处）。

上屏证据：`t2-both.png`（582 → strip 264 + 日历行都在）、`t2-strip-only.png`（400 → **日历行整行消失**、strip 拿全部 384）、
`t2-calendar-only.png`（160 → 两排都放不下 → 空面板）。阈值表见 §接口与数据形状。

**③ 前台应用块 = 所有打开的常规 App**（T3）：`switcherApps` 现取 `NSWorkspace.runningApplications`；
过滤 → 排除自身 → 排序 → 去重收在纯函数 `FrontAppSwitcher.apps(...)`；块内下半从"最近切换一排"改成**网格**
（格数由 `FrontAppGridBudget` 按块宽高算），`maxRecentApps` 降级为"`recent` 的记忆长度"、不再决定格数；
`activate(_:)` 两条失败路径都改记 `warn`（不再出现"点了没反应还没记录"）。

上屏证据：`t3-switcher.png` / `t3-switcher-zoom.png`（块内 8 列 × 3 行 = 17 格，与探针的 18 个常规 App 逐条对上）、
`t3-cell-hover.png`（悬停底色先证明热区坐标，再点）、`t3-after-click.png`（点一下**真的切到 Chrome**：菜单栏与窗口都变）、
`t3-switcher-after-switch.png`（切换后再展开：上半变成新 frontmost，网格第一格变成原当前应用）、
`t3-activate-log.txt`（`os_log` 摘录：激活 + 前台变化两条）、
`t3-running-apps-probe.txt`（`runningApplications` 直读：159 进程里 18 个常规；台前调度 `com.apple.WindowManager` 是
`.accessory`，**正是"点击没反应"的来源，现在被挡在数据层之外**）、
`t3-collation-order.txt`（网格次序与 `localizedStandardCompare`(zh_CN) 逐项相同——汉字按拼音排）。

**④ 最小宽度下的空白块**（T4）：根因**实测**为尺寸反馈（`sizeThatFits` 上报的宽度被下一趟布局当提案宽 → plan 重算 →
可见块缩水），修法是**视图侧把提案宽钉在可用宽上**（`HomeStripView` 的 `.frame(width: available, alignment: .leading)`，
一行 + 8 行注释）；`HomeStripLayout` 的规则与 cache 一字未动。可重跑取证在 `evidence/probe-770/`
（`instrument.patch` 探针补丁 + `run.sh` + `analyze.py` 对四条候选逐条判定 + `probe-770.log` / `probe-770-fixed.log` 两份逐趟日志）。

上屏证据：`probe-770/repro-770-blank.png`（修复前：只有音乐块 + 右侧整片空白 + 条尾 `＋2`）、
`t4-770-fixed.png`（修复后：音乐 + 待办都在，`＋2` = 实际空白 2 块）、`t4-900.png`（3 块 + `＋1`）、
`t4-1088.png`（四块齐、无 `＋N`，无回归也没有修过头）。

**⑤ 音乐封面可配置 + 界面入口**（T5 / T5-fix）：manifest config 加 `showAlbumArt`（boolean，默认 `true`）；
`content(for: .home)` 现读后传给视图分档（开 = `MusicPlayerView`，关 = `MusicControlsView`——标题 / 进度 / 控制左对齐、
**不留空洞**）；组件页音乐卡多一行「显示封面」小开关（`ModuleSettingsSection.configControls` 逐字段写死的**一条**，
**不是通用 config 渲染器**；同卡片的 `playerColorTinting` / `useMusicVisualizer` 不开——它们在上游设置页本来就有入口）。
写路径 = `config.set` 先落盘 → `objectWillChange`；模块侧每次现读 config，所以**面板开着也立刻变样**，不需要重启。

上屏证据：`t5-albumart-on.png` / `t5-albumart-off.png`（关档无封面、无空洞，标题与控制在块内容起点）、
`t5-ui-toggle.png`（组件页那一行开关）、`t5-ui-albumart-off.png` / `t5-ui-albumart-on.png`（**同一帧**里设置页开关与块内容一起变，
两次截图之间没有鼠标移动、面板一直开着）、`t5fix-ui/20..25-*.png`（可重跑全过程）。

**验证结论**：验证命令（`DynamicIslandTests` 全量）**退出码 0、362 条 0 失败**（`.workflow/p2-home-fit/t5fix-tests-final.log`；
本批起点 341 条 → +21：`HomeStripLayoutTests` 21 → **34**、`TakeoverEnablementTests` 27 → **30**、
`ShortcutsFrontAppTests` 26 → **31**）。三段变异各有红：T1/T2 判据反转 4 用例红、`showAlbumArt` 恒 true 1 用例红、
T3 政策判断 3 断言红、T4 去掉那一行 9 断言红、T5-fix 写反 5 断言红（逐份日志在 `.workflow/p2-home-fit/`）。
改动文件**新增告警 0**。**关键约束的边界未破**：不新增 TCC、不引入私有 API、不新增出站请求、不新增出站子进程
（`NSWorkspace.runningApplications` 是公开 API）；独立日历与最小化 UI / 歌词侧栏两条渲染路径未动。

**与计划的偏离及原因**：

1. **注入点摊成值类型**（首稿举例 `@MainActor () -> [FrontAppSnapshot]`）：`NSRunningApplication` 没有公开构造器，
   只给快照的话「筛 `.regular`」这条**无法被用例覆盖**（变异不红），而它正是 D-04 的核心。代价 = 多一个 data-only 类型。
2. **块内格数由宽 × 高两维预算定**（首稿只说"容量按块宽"）：实测 strip 高 264pt 时块内能放 7 行、最小 152pt 时 4 行，
   行数不进预算会纵向溢出（"格子被裁 / 挤变形"）。
3. **`switcherApps` 是类内成员，不是 `extension`**：它要读 `private` 的 provider / `selfBundleID` / `current`。
4. **新增两条文案 key 并校正一条**：`module.frontapp.switcher`（网格的可访问性标签）+ `settings.modules.music.showAlbumArt`；
   `module.frontapp.summary` 的值随语义校正（不再说"最近切换"）。旧 key `module.frontapp.recent` **暂时留而不用**
   （删它要动 catalog，且既有解析用例仍在断言它）。catalog 共 1561 键。
5. **同 id 去重是首稿没写的一条**（`open -n` 起两份时 `ForEach` 的 id 会撞）：留排序靠前的那一份（靠 `recent` 的 pid 判定）。
6. **`.calendarOnly` 档在生产常量下等于"面板什么都不画"**（行高 294 > 152，那一支放不下日历行）：与 §做法 机制二
   「若其行高也放不下则不画」一致，但后果（168…167pt 那一档是空面板）首稿没点明。
7. **T5 补了界面入口**（原计划只有 config）：范围评审的唯一一条 Important——用户问的是"是否可以配置"，只有 config
   等于用户改不了。**只开这一个键的口子**。
8. **探针以「补丁 + 脚本 + 日志」落盘、不进提交**：源码里的探针会污染生产代码与告警面。

**遗留项**（人工验收或后续批次）：

- **独立日历的渐变"保留"无法上屏验收**：`StandaloneCalendarView` 运行期无调用点（其 `#Preview` 实例化的是
  `CalendarView()`，不用 `MonthGridView`），见 §已知限制 6。验收 2 只能按代码默认档 + 反事实截图论证。
- **封面关掉后块宽仍是 300/420**（§已知限制 5）；**块内网格溢出仍静默不画**（§明确不做 `＋N` 的观感那一档）。
- **两处无自动化断言**：`showsScrollFades` 的**默认值**（SwiftUI 视图参数，靠唯一显式实参 + 反事实截图保护）、
  `MusicHomeBlockView` 的**分档**（`private` 视图，只看截图）——单测钉住的是「config → 布尔量」与「写路径 → 模块读侧」。
- **未验**：展开动画中间态（截图都取稳态）、极简模式 / 歌词侧栏 / 独立日历三条路径（本批不动）、
  真实拖拽把手连续改高度的观感（按 `openNotchHeight` 分档重启取证）、`activate()` 失败路径的真机日志。
- **`probe-770/instrument.patch` 只对 base `f78d8a8c` 验证过可干净应用**：提交之后重跑探针要 `git apply --3way`
  或先去掉那一行修复。
- **`＋N` 提示位宽度仍是常量 34**：将来若动态化，必须同时补 `HomeStripLayout` Cache 判据的端到端验证（[21](21-strip-honesty.md) §已知限制 9）。

## 已知限制

1. **`runningApplications` 不含"最小化到 Dock 之外"的东西**：它列的是运行中的 App，不列窗口；
   满屏窗口的应用只占一格（这是"列 App"的语义，不是缺陷）。
2. **非 `.regular` 的进程不列**（后台代理、输入法、台前调度那类系统的 UI 进程）——这正是"点击没反应"的来源，
   本批用过滤把它们挡在外面，代价是用户如果想切到某个后台代理也没有入口。
3. **排序里的"最近使用"只覆盖本进程启动之后**的切换；启动前就开着的 App 按名称排（`recent` 的既有边界）。
4. **最小宽度下"块被分配宽度却空白"的根因是尺寸反馈，不是缺兜底**（回写按实测改写；首稿猜的"给块加最小尺寸兜底"
   **已被证伪**——被丢的块是上层用 `.zero` 提案显式摆放的，加最小尺寸只会让它溢出或缩回去，`visibleCount` 与屏上块数仍不一致）。
   实测链条（770pt 面板 + 4 块，`evidence/probe-770/probe-770.log`）：`HomeStripLayout.sizeThatFits` 上报的宽度是
   「可见块宽 + 间隙」（丢块路径下 488 < 可用宽 702），**SwiftUI 的下一趟布局把这个上报宽度当新提案**再问它一次，
   于是 Layout 那份 plan 的输入从 702 变成 488——34pt 的 `＋N` 预留位把 `visibleCount` 从 2 再挤到 1，只有第 0 块带宽度摆放；
   而视图那份 plan 仍按 `proxy.size.width = 702` 算（照画 `＋2`），两趟在 2 块 ⇄ 1 块之间抖动，落定的是最后那趟。
   **修法是视图侧把提案宽钉在可用宽上**（`HomeStripView` 的 `.frame(width: available, alignment: .leading)`），
   `HomeStripLayout` 的规则与 cache 一字未动。代价：这是 SwiftUI 侧的隐式契约，纯函数用例测不到，
   只能靠**宿主级用例**钉住（去掉那一行会静默回归——变异实测 9 条断言红）。
5. **封面关掉后块宽仍是 300/420**：块内右侧会空出一段，属本批接受的取舍（§明确不做）。
6. **独立日历的"保留渐变"只有代码意义**：`MonthGridView` 只有**两个调用点**——`HomeCalendarRow`（传 `false`）与
   `StandaloneCalendarView`（不传 → 走默认档 `true`），而 `StandaloneCalendarView` **在运行期没有任何调用点**
   （全仓 grep：只有类型定义与注释；同文件的 `#Preview` 实例化的是另一个视图 `CalendarView()`，它不用 `MonthGridView`）。
   所以默认档 `true` 当前没有可见入口——"独立日历仍有渐变"这条无法在屏上验收，只能按代码默认档 + 反事实截图
   （= `true` 分支的渲染）论证。这不是本批引入的（[17](17-nookx-adoption.md) §已知限制 8 与
   [09](09-features-and-mechanisms.md) §5.8 的「日历块」行都记着）。
   **若将来 P2a 的 `calendar` tab 复用 `MonthGridView`，要确认它传哪一档**（默认 `true` 是"可滚网格"的口径）。
7. **770pt 下只显示 2 块、`＋N = 2` 是宽度预算的必然，不是缺陷**：四块（音乐 min 300 + 另三块各 180）的最小宽和
   `840` 加三个间隙 `24` = **需可用宽 ≥ 864**（面板 ≈932pt）；再扣 34pt 的提示预留位，770pt 面板的可用宽 702
   先扣预留只剩 668 < 676（前三块的最小宽和 + 两个间隙）→ 只放得下 2 块。实测阶梯：**770 → 2 块 + `＋2`、
   900（可用 832）→ 3 块 + `＋1`、1088（可用 1020）→ 四块齐、无 `＋N`**。
   本批修的是"被判可见的块必须真的画出来"，不是"多显示几块"——要看更多块得把面板拉宽（属面板宽度策略，§明确不做）。
8. **块内网格溢出仍静默不画**：`FrontAppGridBudget.capacity` 在最小档（180×152）是 24 格、240×152 是 32 格，
   常规 App 超过这个数时多出来的格子**既不画也不提示**（`＋N` 是整块级的提示，块内的格子没有提示）。
   本机 18 个常规 App 没到上限（3 行），因此这一档只有用例与预算断言覆盖，**没有实拍**（§明确不做「`＋N` 的观感」那一档）。

## 验收标准

1. `xcodebuild test`（`DynamicIslandTests`）全绿（**实测 362 条 0 失败**）；新增用例覆盖：`HomeVerticalFit.plan` 三档、
   `switcherApps` 的过滤/排序（含排除自身与非 `.regular`）、`showAlbumArt` 的 manifest 与**解析**分档
   （"布尔量 → 画不画封面"那一档在 `private` 视图里，只有截图，见 §实际交付 遗留项）、
   以及 T4 的两条**宿主级**用例（判可见的块必须拿到宽度、空白块数 == `＋N`）。
2. **按实测口径**：首页日历行上下**没有**渐变（截图 + 逐行亮度剖面：`t1-home-no-fade-zoom.png` /
   `t1-fade-profile.txt`，同位置的暗带在修复版里数值上不存在）。`showsScrollFades = true` 那一档
   **当前没有运行期入口可拍**（唯一走默认档的调用点 `StandaloneCalendarView` 无调用点，见 §已知限制 6），
   因此它按**反事实截图**验收：把首页行临时打回 `true` 重建安装，两条 16pt 暗带复现（`t1-fade-counterfactual.png`）
   = 默认档仍在画渐变。
3. 把面板高度逐步调小：**先消失的是日历行**，strip 到最后才让位（截图三档）。
4. **凡被判为可见的块都真的画出来，且条尾 `＋N` 等于实际空白块数**（T4 的替代判据）。
   首稿写的"750–800pt 区间内 `＋N` 为 0 时所有块都在"**在 770pt 不成立**：四块需可用宽 ≥864，
   扣 34pt 预留后 668 < 676，所以那一档 `＋N` 恒 > 0。实测判据：770 → 2 块 + `＋2`、
   900 → 3 块 + `＋1`、1088 → 四块齐无提示（`t4-770-fixed.png` / `t4-900.png` / `t4-1088.png`）；
   宿主级用例把这条判据钉住（挂真 `HomeStripView`，断言"拿到尺寸的块 == plan 的 `visibleCount`、
   空白块数 == `droppedCount`"），探针脚本可重跑（`evidence/probe-770/`）。
5. 前台应用块列出所有打开的常规 App，逐个可点、点击后前台切换（截图 + 日志）；
   台前调度那类不可激活条目**不出现在列表里**。
6. 组件页音乐卡的「显示封面」开关一拨，块内封面随之去 / 回、**无空洞**，且面板开着也立刻变样
   （`t5-ui-toggle.png` / `t5-ui-albumart-off.png` / `t5-ui-albumart-on.png`；直接改模块 config
   `showAlbumArt` 的等价路径见 `t5-albumart-off.png`）。

## 决策摘要

| ID | 决策 | 来源 | 理由 |
|---|---|---|---|
| D-01 | 渐变遮罩改成**按需**（首页行不画、独立日历保留） | 用户 | 用户要求去掉首页的这两条线；独立日历需要它（§备选与取舍 ①） |
| D-02 | 高度不足时**先收日历行**，strip 最后让位 | 用户 | 用户原话「应该收起第二排的日历，而不是第一排」（§备选与取舍 ②） |
| D-03 | 前台应用块内容 = **所有打开的常规 App**（`runningApplications` 现取），`recent` 降级为排序依据 | 用户 | 用户原话「所有打开的软件都要显示」+「点击没反应」（§备选与取舍 ③） |
| D-04 | 不可激活的条目（非 `.regular` / 无可激活进程）**不列**，而不是列出来点不动 | agent | 用户反馈的"点了没反应"就是这类条目；列一个点不动的行比不列更糟 |
| D-05 | 最小宽度空白**先取证再小改**，不预设根因 | agent | 计划评审纪律：未定根因前动布局任一侧都是猜（§做法 机制四） |
| D-06 | 封面开关落在**模块 config**（`showAlbumArt`，默认显示） | 用户 | 用户问"是否有这个能力"——没有，所以加；落在模块 config 而不是上游键（§备选与取舍 ⑤） |

**D-07 起是执行期自定的读法（回写 2026-09-30）**——五条的边界在动手时才显形，逐条落在这里，
免得后来人以为只有一种解释：

| ID | 决策 | 来源 | 理由 / 代价 |
|---|---|---|---|
| D-07 | `maxRecentApps` **降级为"`recent`（排序依据）的记忆长度"**：块内画几格改由 `FrontAppGridBudget` 按**块宽 × 块高**算，视图不再收 `recentLimit` | agent（执行期） | D-03「所有打开的软件都要显示」——沿用旧键当格数上限会让"列全"名不副实（默认 5 就只画 5 格）；行数不进预算会在矮块里纵向溢出。代价：这个 config 键的**可见效果变弱**（从 8 调到 3 时块里格数不变，只有"最近排前面"的范围变短）——docs/22 §4 与 §已知限制 13 已随之改判 |
| D-08 | 注入点摊成**可判定字段的值类型**（`FrontAppRunningApp` / `FrontAppRunningAppsProvider`），而不是 `[FrontAppSnapshot]` | agent（执行期） | `NSRunningApplication` 没有公开构造器，只给快照的话「筛 `.regular`」这条**无法被用例覆盖**（变异不红），而它正是 D-04 的核心。代价 = 多一个 data-only 类型；`.regular` 判定的真值仍只来自系统 |
| D-09 | 最小宽度空白的修法落在**视图侧把提案宽钉在可用宽上**（`HomeStripView` 的 `.frame(width: available, alignment: .leading)`），不改 `HomeStripLayout` 的规则与 cache | agent（执行期） | 根因是"布局的输入宽度来自它自己的输出"（尺寸反馈），一行、一个语义；纯函数的契约与既有用例逐字不变。代价：SwiftUI 侧的隐式契约，纯函数用例测不到，只能靠**宿主级用例**钉住（否则将来有人"清理"这一行会静默回归） |
| D-10 | 封面开关的界面入口**只给这一个键开一个口子**：`ModuleSettingsSection.configControls` 是逐字段写死的登记表（模块 id / config 键 / 文案 key / 回落值），**不做**按 manifest schema 自动生成的通用 config 渲染器；同卡片的 `playerColorTinting` / `useMusicVisualizer` 不开 | agent（执行期） | 用户问的是"是否可以配置"，只有 config 等于用户改不了（范围评审的唯一一条 Important）；通用渲染器是另一个批次的活，同卡片另两个键在上游设置页本来就有入口。代价：将来别的模块要开 config 入口时，这张表要逐条加（注释与文件头都写明"本批刻意只开这一个口子"） |
| D-11 | `Plan.showsCalendarRow` 在 `.both` 档恒返 `true`（含"用户关掉日历行、行高传 0"时）——**不修** | agent（执行期 / 评审裁定） | 该分支只由"两排一起放得下"成立，而调用方 `NotchHomeView.standardHomeContent` 还要与 `showCalendar` 相与，因此这个 `true` 永远不会变成"画了一行没有的日历"；把偏好判据塞进纯函数会让它对偏好有意见。代价：字段名读起来像"该画这一行"，实际语义是"这一档有它的位置"（已注释、已记 §接口与数据形状） |
