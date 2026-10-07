# 首页小组件与设置重构：进度/统计上首页、组件分组排序、日历接系统数据、设置去无用

| 项 | 值 |
|---|---|
| 状态 | **已实现（2026-09-30，批次 `p3-widgets`，提交范围 `982b80cc..997d3b35`，9 个提交；逐条见 §实际交付）** |
| 最后更新 | 2026-09-30 |
| 关联来源 | 用户 2026-09-30 六条反馈（含三张截图）；[09](09-features-and-mechanisms.md) §5.3/§5.8、[14](14-module-manifests.md)、[20](20-component-page.md)（组件页与接管）、[23](23-home-fit.md)（首页五条修正） |

> **怎么读**：§背景与目标 / §明确不做 / §备选与取舍 是判断依据；§接口与数据形状 是执行者契约；§已知限制 / §实际交付 留给后来人。
>
> **读者分界**：给人读的是背景、取舍、不做的与限制；§做法 机制与 §接口与数据形状 给执行者与模型。

## 一句话方案

把「只展示、没有控件」的功能从面板搬上首页，并让组件设置按"出现在哪里"分组：
**① 进度**（纯展示的日/周/月/季/年进度）改成**首页小组件**（不再单独占展开 tab）；
**② 统计**（CPU/内存/GPU 图，本来就没有控制按钮）改成**首页小组件 + 一个开关**；
**③ 组件设置分两组**——**首页组件**（控制首页是否展示）与**面板组件**（控制是否单独出面板/tab），**两组都能排序**；
**④ 日历**：去掉日历面板里残留的两条遮罩线，并把月历数据接成**系统日历**（公历 + 农历 + 节假日）；
**⑤ 设置页**：重排分组、删掉无用项（含"日历 / 笔记"两个设置页的存废判定）。

## 背景与目标

### 现状（六条，逐条对应代码）

| # | 用户的话 | 现状 |
|---|---|---|
| 1 | 「进度这个控制面板是用来做什么的，只显示时间吗…如果只是显示，就改为首页小组件」 | **是纯展示**：`ProgressModule.swift` 里没有任何 `Button`/`Toggle`/`Picker`，内容是"日/周/月/季/年"的剩余量清单与进度条；但它占着一个展开 tab（`surfaces: [.expanded]`） |
| 2 | 「cpu,内存,gpu 这个面板没有控制按钮…改为首页的小组件，增加开关」 | `NotchStatsView`（上游）只有图表与开关项，没有动作按钮；现由 `enableStatsFeature`（默认 false）门控成展开 tab；图表可见性另有 `showCpuGraph` 等上游键 |
| 3 | 「组件设置进行分组修改，分为首页组件和面板组件两类…两类都可以设置排序」 | 组件页现在是"一张卡 = 一个模块"的平铺 + **只对首页块**的一条顺序节（`homeBlockOrder`）；"哪些模块出面板/tab"没有单独的组与排序 |
| 4 | 「日历和笔记的设置功能是否有用，如果没用说明为什么，确定没有用就去掉」 | 设置侧栏有 `calendar` 与 `notes` 两个 tab（`SettingsView.swift:57`/`:67`）。**日历设置有用**（`showCalendar` 等键就是首页日历行与日历 tab 的开关）；**笔记设置大部分无用**（笔记是上游功能，`enableNotes` 默认关，本产品没有任何入口指向它，只有 `Apple 备忘录同步` 一类子项） |
| 5 | 「日历面板还存在两条线的遮罩，去掉；同时首页的日历和日历面板的日历取系统的日历数据，包含：公立，农历，节假日等数据」 | 遮罩线只在**首页行**去掉了（`showsScrollFades: false`），`StandaloneCalendarView` 里那份仍在（上屏截图有）；月历现在只画**公历**（`MonthGridLayout.days(forMonth:)`），没有农历与节假日 |
| 6 | 「设置里面的功能清单是否需要重新分组排序，同时分析是否存在无用的，无用的去掉」 | 侧栏 8 个分组 20+ 个 tab，混着"上游遗留功能"（笔记、屏幕助手、取色器、暂存器、LLM 用量…）与我们自己的（通用/外观/媒体/实时活动/锁屏/设备/控制/电池/计时器/日历/笔记/统计/剪贴板/屏幕助手/取色器/暂存器/组件/关于…）——需要按"我们真的用"重排 |

### 预期结果（改后）

1. 进度不再有展开 tab；作为**首页小组件**出现（可关、可在首页组件里排序）。
2. 统计同样是首页小组件，卡片上有开关（`enableStatsFeature` 仍是它的真源——沿用接管口径），点开关即上/下首页。
3. 组件设置页分两节：**首页组件**（列所有会出现在首页的块：内置 + 模块，可开关、可排序）与**面板组件**（列所有会单独出面板/tab 的模块，可开关、可排序）。排序沿用一套机制（`homeBlockOrder` 扩成两组各自的顺序表）。
4. 日历：首页行与日历面板都**没有**那两条渐变；月历每天显示**公历 + 农历**（初一显示月名，如"八月初一"），**节假日**当天给出名称与标记（数据源与降级写在 §做法 机制四）。
5. 设置侧栏按"我们真的用"重排；笔记设置页去掉（连同为它开的开关），日历设置页保留并精简。

## 做法

### 机制一：进度与统计搬上首页

两者都从"展开 tab"改成"首页块"：`surfaces: [.home]`（去掉 `expanded`），`takeoverEnableKey` 分别沿用它们各自的上游键（进度无上游键 → 用 `moduleEnableOverrides`；统计用 `enableStatsFeature`）。
块内呈现照首页块的既有约束写：**宽度由宿主声明**（`homeBlockWidth`：统计给 `220/300`、进度给 `180/240`），
内容必须能在最小块里**不裁不溢**。统计的形态按用户 2026-09-30 追加指示改为**环状**（三环并排、环心百分比、环下标签；横条太占空间）——形态与配色对齐既有 `TodoScopeRing` 先例，详见 §机制八。

### 机制二：统计的"开关"

统计的开关就是 `enableStatsFeature`（默认 false）——组件页那张卡拨它即上/下首页（沿用 [20](20-component-page.md) 的接管真源口径，不新增第二份状态）。

### 机制三：组件设置的两组与两套排序

组件页从"一张卡 = 一个模块"改成分两节：
- **首页组件**：行 = 会出现在首页的块（内置块 + 声明 `home` 的模块），每行一个开关 + 上移/下移；顺序写 `homeBlockOrder`（沿用）。
- **面板组件**：行 = 会单独出面板/tab 的模块（声明 `expanded` 的模块），每行一个开关 + 上移/下移；顺序写**新键** `panelOrder`（`[String: Int]`，键 = 模块 id），投影 `tabEntries` 按它排。
两节的"开关"语义写明：首页组控制"是否在首页显示"，面板组控制"是否单独出面板/tab"。**同一个模块可能同时出现在两节**（例如日历：首页行 + 面板 tab）——那时两节的开关各自管各自的 surface，节头要写清这一点。

### 机制四：日历数据接系统日历（公历 + 农历 + 节假日）

- **公历**：现状不变（`MonthGridLayout.days(forMonth:)`）。
- **农历**：`Calendar(identifier: .chinese)`（Foundation 自带，零依赖）把每天的农历日算出来——**初一显示月名**（如"八月初一"），其余显示"初二…廿九"这类日名；在日期格下方以 **9pt 次要色**一行显示（放不下就不显示，不挤压公历数字）。
- **节假日**：系统日历里订阅的"中国大陆节假日"日历本身就是 EventKit 的日历之一 —— **优先取它**（`EKEventStore` 的日历列表里名字含"节假日"的那个，取该日全天事件标题）；取不到（用户没订阅）则**降级**为只显示农历与事件点，并在文档里写明"节假日需要系统日历里订阅节假日日历"。
- 同一套数据同时供给**首页日历行**与**日历面板**（两者共用 `MonthGridView`，因此只改一处）。

### 机制五：设置的清理与重排

- **去掉**：笔记设置页（`SettingsTab.notes`）——理由：笔记是上游功能，本产品没有任何入口指向它（模块清单里没有它、首页块与 tab 都不出），`enableNotes` 默认关；保留它只会让设置页多一个"看不出效果"的页。同时把 `Apple 备忘录同步` 一类只服务于笔记的子项一并从设置面移除（**上游代码保留、不删文件**，只摘掉入口）。
- **保留**：日历设置页（它持 `showCalendar` / `hideCompletedReminders` / `hideAllDayEvents` 三个仍在生效的键），但把与日历面板无关的项精简。
- **重排（2026-09-30 用户追加）**：**不设「上游功能」分组**——实用工具类一律并入**效率**组；顺序按主题 + 使用频率：通用 / 外观 → 媒体与显示 → 效率（计时器、剪贴板、日历、统计、终端、暂存器、取色器、下载、屏幕助手）→ 系统（HUD 与 OSD、电池）→ 集成（扩展、~~组件~~）→ 关于。**2026-10-01 p6 改判（D-18）：「组件」页已移入「媒体与显示」分组（排「设备」之后），「集成」分组只剩「扩展」**——用户第 10 条反馈推翻了「扩展 / 组件同类必须相邻」的旧口径（该口径见 `SettingsView.swift` 当时的注释）。实现见 [30](30-ui-polish-and-shelf.md) §做法 机制九 / §接口 机制九。**逐页意义判定**：每页按「有读点 + 有可观察效果 + 有入口」三条判——三条齐才保留，否则删页留码（判定表落进 docs/09 与报告）。


### 机制六：首页分带（主块带 + 小组件带）——把"窄宽度整排被丢"变成"换行"

**问题**（用户 2026-09-30）：把进度/统计也搬上首页后，一条 strip 要装 6–8 个块；面板收窄时规则③从尾部丢块，
结果是「全被隐藏」——而"扫一眼"的价值恰恰在窄面板下最高。

**设计**：首页分**两条带**——
- **主块带**（上）：只放**大块**（音乐、镜子、日历一类需要面积的内容），沿用现有 strip 语义（理想宽不拉伸 → 按最小宽压缩 → 仍不足按序尾部丢块 + `＋N`）。
- **小组件带**（下）：放**紧凑块**（进度、统计、待办、通知、前台应用…），按可用宽度铺网格（每格 180–300pt，一行 1–4 格），**放不下就换行**，行数由剩余高度决定；**只有连一行都放不下时才丢块**并计入 `＋N`。
- 块的归属由 manifest 侧的新钩子 `homeFormFactor`（`.large` / `.compact`，缺省 `.compact`）**声明**，不由宽度反推（宽度是结果）。
- 高度不足时的收顺序由 `HomeVerticalFit` 扩成四档：`both` → `noCalendar` → `stripWidgetsOnly` → `widgetsOnly` → 空——**先收日历行，再收主块带，最后才动小组件带**。

**代价**：主块带与小组件带会争高度（面板矮时主块被压得比现在更早让位）；缓解是四档顺序里"主块先让位"（因为小组件更便宜、信息密度更高）。


### 机制七：分界的视觉（带级容器 + 块级 hover）——调研结论与取舍

**调研（用户问 Atoll / Nook X 有没有这类机制）**：**两家都没有 per-block 的卡片容器**。Atoll 的首页是平铺（封面 + 控件 + 日历并排）；Nook X 的首页块**密排、几乎不留白**，它的分界感来自**字号分层**（焦点数字最大、辅助信息缩成小 chip）+ **按内容自适应的宽度**，而不是边框或底色（见 [16](16-nookx-reference.md) §5.1）。

**取舍**：每块永久卡片有两层代价——① 每块吃 8–16pt 内边距（我们最紧的就是宽度预算，见机制六）；② 视觉噪声会切断 Nook X 那种密度优势。故本批采用**带级容器**：两带各一个极淡圆角底（`white.opacity(0.04~0.06)`、圆角 12、内边距 8）+ 带间留白；**可交互块在 hover 时**给淡底圆角（与既有 `LauncherGridCell` 同形）；**纯展示块不加永久边框**。若仍觉得糊，再退一步给每块淡底，届时两版各拍一张交用户选。

> **2026-10-01 p6 改判（用户第 1 条反馈）：撤掉「整条带共用一个大底」**——单条流上的 `homeBandContainer()` 不再画底（`HomeBandChrome.containerOpacity` / `containerCornerRadius` 删除，只剩横向 8pt 内边距 8 = `containerInset`）；「所有内容糊在一个大盒子里」正是该条反馈；块与块之间的区分改由**每块自己的浮起光**（柔光池为主 + 内容辉光为辅，`homeBlockFloat()`）做，用户本轮明说「不加区域块与边线」。行级 **hover 淡底保留**（`hoverOpacity 0.06` / `hoverCornerRadius 8`）。实现见 [30](30-ui-polish-and-shelf.md) §做法 机制一 / §接口 机制一 · D-02。


### 机制八：统计块的形态 = 环状（用户 2026-09-30 追加）

用户原话：「cpu 内存 gpu 这三项，不要用横线条去展示，太占空间了，改为环状展示，或者你考虑个合理的、显示有科技风的方式」。

**选择环状**，理由：① 我们已有先例 `TodoScopeRing`（待办三环）——同一套视觉语言，用户看惯了；② 环形在同样信息量下**比三行条矮 25–30pt**（三环 + 标签 ≈70pt，原来三行 ≈96pt），省下的高度正好留给分带布局的小组件带；③ 百分比放环心，**读数即焦点**，符合"扫一眼"。

**具体的"科技风"只做三件事**（克制、可维护、不引第三方）：
1. **按指标分色**：CPU 青 / 内存 紫 / GPU 琥珀——配色从面板既有 accent 家族里挑，**不新造一套**；
2. **细描边 + 淡发光**：`Circle().trim` 的进度用 2pt 描边叠在 5pt 主环上，外加 `shadow(radius: 2–3)`，读起来像"通电的环"；环轨 `white.opacity(0.12)`（与既有 ring 一致）；
3. **等宽数字**：环心百分比用 `monospacedDigit()`，刷新时不跳动。

尺寸：直径 46pt（宽 < 200 时退 40pt），纯函数 `StatsRingMetrics.ringDiameter(forWidth:)` 有用例钉住"220pt 最小宽下三环 + 间距 = 158 ≤ 220，不裁不溢"。

**顶部让位（2026-10-06 修复）**：环的**墨迹比布局框大**——`Circle().stroke(lineWidth:)` 以路径为中心，向框外各溢出 `mainLineWidth/2`（2.5pt），亮描边的发光再 2.5pt，合计 **5pt**；而块内容贴板顶（宿主纵向内缩恒 0），宿主又在块框上 `.clipped()` → 环顶的描边与发光**被齐平切掉**（用户反馈「cpu 这三个上边距太小，顶部被遮盖了」）。修法是模块自己让出 `StatsRingMetrics.homeBlockTopInset`（**8pt** = 外溢 5 + 3）。几何、上屏读数与代价见 [32](32-home-block-plates.md) D-21。

## 备选与取舍

**① 进度/统计：搬上首页 / 保留 tab / 直接删？** 搬上首页。用户两条都说"如果是只展示就改首页小组件"，且它们确实没有控件（§背景与目标 第 1/2 条）；删掉是丢功能。

**② 统计的完整面板（多图 + 图表可见性一堆开关）怎么办？** 首页只画**迷你版**（当前值 + 一行条），完整图**留在设置页的统计设置里做预览**（那里本来就有图表可见性开关），不保留独立 tab（用户说"不需要单独面板"）。

**③ 面板组件的排序：新键 `panelOrder` / 复用 `homeBlockOrder`？** 新键。两组顺序是两件事（同一个模块可能在两组里名次不同），共用一个键会让它们互相踩。

**④ 日历节假日：自算 / 取系统订阅日历 / 第三方库？** 取**系统订阅日历**（EventKit 里那份"节假日"），取不到就降级只显示农历。不引第三方库（GPL 与体积都要付代价），不自算（中国的调休每年变，规则数据本身要维护）。

**⑤ 笔记设置：整页去掉 / 只隐藏 / 保留？** 整页去掉（摘入口、留代码），理由见机制五；这也是用户"确定没有用就去掉"的直接要求。

## 接口与数据形状

> **本节是执行者契约**：下面每一条都按**落地后的实际签名**写（回写时逐条对着代码核过，不是计划稿）。

```swift
// 进度与统计：从 expanded 改 home
// ProgressModule.manifest: surfaces [.home]，defaultPlacement = Placement(slot: nil, order: 30)，
//   defaultEnabled = false（2026-09-28 的口径不变），homeBlockWidth = ModuleHomeBlockWidth(min: 180, ideal: 240)
//   content(.home) = ProgressHomeBlockView（紧凑清单：图标 + 标签 + 细条 + 百分比）
//   content(.expanded) = .none——展开清单视图（ProgressModuleView / ProgressScopeRow）保留在
//   文件里但不挂 surface（可逆，见 §已知限制 8）
//   进度**不是接管模块**（没有上游总开关）：启用真源仍走 moduleEnableOverrides → manifest.defaultEnabled
// StatsModule（新接管模块，id = com.cmeng.gourd.stats）: surfaces [.home]，
//   takeoverEnableKey = Defaults.Keys.enableStatsFeature（= 它唯一的启用真源），
//   homeBlockWidth = ModuleHomeBlockWidth(min: 220, ideal: 300)，
//   defaultPlacement = Placement(slot: nil, order: 50)（落在既有模块序号最大值 notifications 40 之后），
//   defaultEnabled = Defaults.Keys.enableStatsFeature.defaultValue（false），permissions []
//   content(.home) = StatsHomeBlockView（三环：CPU / 内存 / GPU，环心百分比、环下 9pt 标签）
//     环的**绘制比布局框大**（`drawingOverhang` = 2.5 描边 + 2.5 发光 = 5pt）→ 块内容在**顶部**让出
//     `homeBlockTopInset`（8pt），否则环顶被块框的 `.clipped()` 切平（2026-10-06；见 [32] D-21）

// 首页分带（Host 层新纯函数 + 内核第四条钩子）
// Kernel/ModuleTypes.swift
public enum HomeFormFactor: String, Sendable, CaseIterable { case large, compact }
// Kernel/GourdModule.swift：第四条同形钩子（**协议要求 + 协议扩展缺省**，与
//   takeoverEnableKey / isTabVisible / homeBlockWidth 同形）
static var homeFormFactor: HomeFormFactor { .compact }      // 缺省语义写在扩展里
// Kernel/ModuleRegistry.swift：宿主访问器（照 homeBlockWidth(for:) 的写法）
func homeFormFactor(for id: String) -> HomeFormFactor       // 每次现问一次、不缓存；未注册 id 答 .compact
//   显式声明 .large 的只有两个：MusicModule、MirrorModule（进度 / 统计 / 待办 / 通知 / 前台应用 = 缺省 .compact）
//   ~~显式声明 .large 的只有两个：MusicModule、MirrorModule~~ **2026-10-01 改判（p5-home-blocks / D-09 · D-10）：只剩 `MirrorModule` 一个大块**——
//   音乐本批降为 `.compact`（宽度 `300/420` → `240/300`、封面 `showAlbumArt` 默认关），大块档高度改由镜子的方形边长 140 定
//   （镜子块宽同步收敛为 `140/140`）。详见 [29](29-home-blocks-and-panel.md) §做法 机制四 / §已知限制 9。

// Host/HomeBandedLayout.swift（纯几何、无 SwiftUI，可单测）
enum HomeBandedLayout {
    static func rowsNeeded(items:available:columnSpacing:) -> Int
    static func wrappedRows(items:available:columnSpacing:) -> [[Int]]      // 贪心换行，**不丢块**
    static func affordableRows(bandHeight:rowHeight:rowSpacing:) -> Int
    static func plan(...) -> Plan            // Plan.mainBand（沿用 HomeStripLayoutMath.plan）+ Plan.widgets
}
// Host/HomeVerticalFit.swift：三档 → 四档
enum HomeVerticalFit.Layout { case both, noCalendar, widgetsOnly, none }    // 让位链：先日历行 → 再主块带 → 最后小组件带
// Host/HomeStripView.swift（带级容器 / 悬停的唯一取值处）
enum HomeBandChrome {
    // ~~static let containerOpacity: Double = 0.05   // 机制七的 0.04~0.06 取中~~
    // ~~static let containerCornerRadius: CGFloat = 12~~
    // ↑ **2026-10-01 p6 改判：这两个常量已删除**（整条带的大底撤掉，改每块柔光池——
    //   见 [30](30-ui-polish-and-shelf.md) §做法 机制一）
    // ~~static let containerInset: CGFloat = 8~~   // 只做横向（纵向 0，见 §已知限制 6）
    // ↑ **2026-10-07 复核修复（[32](32-home-block-plates.md) D-23）：连同 `HomeBandContainerChrome` /
    //   `homeBandContainer()` 一并删除**——用户反馈「大背景框和里面组件的边距有点大」，流的块左缘
    //   因此与日历行对齐（354.5 → 346.5）

    static let hoverOpacity: Double = 0.06
    static let hoverCornerRadius: CGFloat = 8
}
// HomeStripView.widgetRowHeight = 96（小组件带行高的**宿主常量**，不是统计块的高度，见 §已知限制 9）
// ~~小组件带行高 96~~ **2026-10-01 改判（p5-home-blocks / T1 · T2 · T3）：96 现在是「紧凑档」的块高**
// （`HomeFlowView.compactBlockHeight`，出处是「形态 → 档高」表）；旧分带渲染器（`HomeBandedLayout` / `HomeVerticalFit` /
// `widgetRowHeight`）已不在生产路径（[28](28-home-layout-redesign.md) 的单条流接手）。这一档里装的块本批都改过：
// 待办不再画三环、进度行高 14 + 行距 6（96 高放得下五行；**行距 2026-10-07 由 [32](32-home-block-plates.md) D-22 收到 5**——腾 4pt 给内容顶部内缩）、音乐紧凑条六项预算 95。详见 [29](29-home-blocks-and-panel.md) §实际交付。

// 面板顺序（新键）
Defaults.Keys.panelOrder: [String: Int]      // 键 = 模块 id，值 = 面板组的序号；缺键 = 用户未表达
// ModuleRegistry.tabEntries 的排序键改由纯函数给出：
//   static func panelRank(_ id: String, defaultOrder: Int, panelOrder: [String: Int]) -> Int
//     = panelOrder[id] ?? defaultOrder        （defaultOrder = defaultPlacement?.order ?? Int.max）
// 比较器其余部分（同值按 id 字典序）一字未动。设置页显示顺序读同一份算式。
// 面级摘除名单（"两节开关各管自己的 surface"的载体；只有"还有另一个面"的模块才写这两键）
Defaults.Keys.hiddenHomeModules: [String]    // 首页面上被单独摘掉的模块 id
Defaults.Keys.hiddenPanelModules: [String]   // 面板面上被单独摘掉的模块 id
// 单面模块不进名单：关掉 = 关模块，写既有启用真源（moduleEnableOverrides / 接管键），不新增第二份状态

// 农历与节假日（日历）
enum LunarDayLabel {                          // 纯函数，可单测
    static func label(for date: Date, calendar: Calendar = Calendar(identifier: .chinese)) -> String?
    static func monthName(for month: Int) -> String?     // 初一显示它
    static func dayName(for day: Int) -> String?         // 其余显示它
}
enum HolidayLookup {                          // 落地签名取本产品的日历模型，不是 EventKit 的 [EKCalendar]
    static func isHolidayCalendar(titled title: String) -> Bool      // 唯一的判定字符串
    static func holidayCalendar(in calendars: [CalendarModel]) -> CalendarModel?
    static func name(for date: Date, events: [EventModel], calendar: Calendar = .current) -> String?
}
enum MonthCellSubtitle {                      // 「放不下就不画」的判据（9pt 文字实测宽 + 余量 + 事件点让位）
    static func fits(_ label: String, cellWidth: CGFloat, fontSize: CGFloat = 9) -> Bool
}
// 月历日格 = 数字（+ 选中圆）一行 + 第二行（节假日名优先，否则农历日名，9pt 次要色、lineLimit 1）；
// 两个宿主（首页日历行 HomeCalendarRow / 面板 StandaloneCalendarView）都传 showsScrollFades: false。

// 统计环的尺寸与取舍（纯函数，可单测）
enum StatsRingMetrics {
    static func ringDiameter(forWidth:) -> CGFloat        // 46；宽 < 200 退 40（非有限数也退小档）
    static let compactThreshold / regularRingDiameter / compactRingDiameter
    static let ringSpacing 10 / mainLineWidth 5 / highlightLineWidth 2
    static let mainRingOpacity 0.45 / trackOpacity 0.12 / glowRadius 2.5
    static func counterFontSize(forDiameter:) -> CGFloat  // 46 → 11；退档 → 10
    static func counterMaxWidth(forDiameter:) -> CGFloat  // 环心文字可用宽（= 内径 − 两侧各 2）
    static func rowWidth(forWidth:spacing:) -> CGFloat    // **「不裁」的判据**：220 → 158 ≤ 220
}

// 进度块的取舍（纯函数，可单测）
enum ProgressHomeBlockLayout {
    static let twoRowWidth: CGFloat = 220
    static func rowLimit(forWidth:) -> Int                // ≥ 220 → 2；更窄 / 非有限数 → 1
    static func listedScopes(_:forWidth:) -> [Scope]      // 按 visibleScopes 声明顺序取前 N 个
}
```

> ~~`twoRowWidth = 220`（≥220 → 2 行）~~ **2026-10-01 改判（p5-home-blocks / D-21 · D-20）：宽度档门槛改成 `allScopesWidth = 180`（= 模块声明的最小宽；`twoRowWidth` 已删）**，行数由「宽度档 × **高度档**」取小者定，并新增 `rowHeight = 14` / `rowSpacing = 6`（**2026-10-07 → 5**，见 [32](32-home-block-plates.md) D-22）/ `barHeight = 6`（96 高的块放得下五行——本批实测宿主真分配的块宽是 180.5…240，旧门槛 220 在多数面板宽下会把块压成 1–2 行，默认三档都上不全）。详见 [29](29-home-blocks-and-panel.md) §接口与数据形状。

**文件**（实际改动到的；新增文件带 Gourd 版权头）：
`DynamicIsland/Modules/ProgressModule.swift`、`create DynamicIsland/Modules/Takeover/StatsModule.swift`、
`create DynamicIsland/Host/HomeBandedLayout.swift`、`DynamicIsland/Host/{HomeStripView,HomeVerticalFit}.swift`、
`DynamicIsland/Kernel/{ModuleTypes,GourdModule,ModuleRegistry,KernelBootstrap}.swift`、
`DynamicIsland/Modules/Takeover/{MusicModule,MirrorModule}.swift`（只各加一行 `homeFormFactor { .large }`）、
`DynamicIsland/components/Notch/NotchHomeView.swift`（接缝换成 `HomeBandedHomeView`）、
`DynamicIsland/components/Settings/{ModuleSettingsSection,SettingsView}.swift`（两节 + 两套排序 / 侧栏重排与摘笔记入口）、
`DynamicIsland/models/Constants.swift`（`panelOrder` + 两张面级摘除名单）、
`create DynamicIsland/components/Calendar/LunarDayLabel.swift`、`DynamicIsland/components/Calendar/DynamicIslandCalendar.swift`（两处遮罩 + 日格第二行）、
`DynamicIsland/Modules/{FrontApp/FrontAppModule,NotificationsModule,TodosModule}.swift`（hover 收敛，行为未变）、
`DynamicIsland/components/Tabs/TabSelectionView.swift` + `DynamicIsland/sizing/matters.swift`（统计 / 笔记两条 tab 分支摘除）、
`DynamicIsland/Localizable.xcstrings`、
`DynamicIslandTests/{ModuleKernelTests,TakeoverEnablementTests,ModuleToggleTests,HomeStripLayoutTests}.swift` + `create DynamicIslandTests/LunarTests.swift`。

## 明确不做

| 不做的事 | 为什么 |
|---|---|
| 删掉笔记功能的上游代码 | 上游代码保留（GPL 与将来可能用），只摘设置入口；删代码属另一件事 |
| 自算中国节假日（调休规则） | 规则每年变、要维护数据；改取系统订阅日历，取不到就降级（机制四） |
| 保留统计的独立展开 tab | 用户明确"不需要单独面板"；完整图挪到设置页的预览 |
| 农历做"宜忌/生肖/节气"一整套 | 首页与月历格只需"初一显示月名、其余显示日名"；更多内容要新数据源（§明确不做） |
| 给两组排序做拖拽 | 沿用现有"上移/下移"两级按钮（与首页块顺序一致），拖拽属另一批 UI 工作 |
| 改上游设置页里那些"图表可见性"子项的语义 | 它们是上游键，本批只搬位置 |

## 实际交付

**提交范围**：`982b80cc..997d3b35`（**9 个提交**，全部本地、未 push；`982b80cc` 是本批基线，也是功能实现的第一个提交）。
逐条证据落在 `.workflow/p3-widgets/evidence/`（**收尾后随 `.workflow/` 一起消失**，结论已在 §已知限制 与本节记下）。
`DynamicIslandTests` 逐批增量：367（批前）→ 371（T1+T2）→ 382（T7）→ 398（T4）→ 401（T9）→ 415（T3/T5 与收尾修复）→ **415 条 0 失败**（全批终态）；改动文件新增编译告警 0。

| # | 提交 | 一句话 | 关键证据（`evidence/`） |
|---|---|---|---|
| 1 | `9aefb92e` T1+T2 | 进度与统计改首页小组件：进度 `surfaces [.home]` + 紧凑清单（180/240、≥220 两行）；新建 `StatsModule`（接管键 `enableStatsFeature`、220/300、`order 50`、三行迷你条）；删 `TabSelectionView` 的 Stats 分支并同步 `enabledStandardTabCount()` | `t1-progress-home.png`、`t1-progress-home-two-rows.png`、`t2-stats-on.png`、`t2-stats-off.png`、`t2-no-stats-tab.png`、`t2-stats-live-a/b.png`、`t2-stats-at-min-width.png`、`t2-default-width-all-blocks.png`；变异 `t1-mutation-progress-surfaces-red.log`（红 5）/ `t2-mutation-stats-key-red.log`（红 5） |
| 2 | `4ec823d0` T7 | 首页分带：`HomeBandedLayout`（主块带沿用旧 strip 规则 / 小组件带贪心换行不丢块）+ `HomeFormFactor` 第四条钩子（协议要求 + 扩展缺省 `.compact`，音乐 / 镜子显式 `.large`）+ `HomeVerticalFit` 四档 + 接缝 `HomeBandedHomeView` | `t7-banded-1154/1088/900/770.png`、`t7-short-height.png`、`t7-shorter-widgets-only.png`、`t7-test-restored-green.log`；变异 `t7-mutation1-no-wrap-red.log`（红 26、第 4 块实到 0.0）/ `t7-mutation2-formfactor-default-red.log`（红 6） |
| 3 | `6bb9e2ae` docs(26) | 设计文档先行（机制六/七/八与 D-09/D-10/D-11 的追加写入） | 本文件自身 |
| 4 | `892b9ae5` T4 | 日历两处去遮罩（面板那份也传 `showsScrollFades: false`）+ 月历接系统数据：`LunarDayLabel` / `HolidayLookup` / `MonthCellSubtitle` + 日格第二行；新增 `LunarTests` 16 条（pbxproj 四处登记） | `t4-calendar-panel-no-fade(-crop).png`、`t4-calendar-lunar(-crop).png`、`t4-calendar-fade-before-after.png`、`t4-test-green.log`；变异 `t4-mutation1-holidayCalendar-nil-red.log`（红 3）/ `t4-mutation2-extra-holidayJudge-false-red.log`（红 9） |
| 5 | `6ed06309` T9 | 统计块改环状：`StatsRingMetrics`（46 / <200 退 40）+ `Row.ringColor`（青 / 紫 / 琥珀）+ `StatsRingView`（5pt 主环 + 2pt 亮描边 + 淡发光 + 环心等宽百分比 + 环下 9pt 标签），删横条视图 | `t9-stats-rings(-min220).png`、`t9-stats-before-after.png`、`t9-restored-default.png`、`t9-test-restored-green.log`；变异 `t9-mutation1-ringDiameter-always46-red.log`（红 8） |
| 6 | `7434bd02` T3 | 组件页分两节（**首页组件** / **面板组件**）各带 ↑↓ 与开关；`panelRank` 排序键 + 新键 `panelOrder` + 两张面级摘除名单 | `t3-home-group.png`、`t3-panel-group.png`、`t3-panel-reorder-live.png`、`t3-panelorder-tabbar-compare.png`、`t3-panel-order-after-restart.png`；变异 `t3-mutation-panelorder-oldkey-red.log` |
| 7 | `e8ea83a3` T5 | 设置侧栏重排（6 组、不设「上游功能」组）+ 逐页意义判定（判定表落 `docs/09` §5.9）+ 删页留码：笔记设置页、统计页 LLM 用量段 + 5 条搜索项、日历页与锁屏页重复的 12 个控件 | `t5-settings-sidebar.png`、`t5-no-notes-tab.png`、`t5-stats-no-llm-section.png`、`t5-test-green.log`；变异 `t5-mutation-notes-back-green.log`（**如实记：侧栏无用例覆盖**） |
| 8 | `ad1c55b1` 收尾修复 | 笔记 tab 分支摘除（`TabSelectionView` 合并分支只看剪贴板 + `enabledStandardTabCount()` 同步）——摘页后 `enableNotes=1` 的机器上 Notes tab 再无处可关；键从此惰性 | `fix-notes-tab-gone(-tabs).png`、`fix-clipboard-tab-kept(-tabs).png`、`notes-fix-test-green.log` |
| 9 | `997d3b35` T8 | 分界视觉：带级容器（`HomeBandChrome` 0.05 / r12 / 横向内边距 8）+ 块级 hover 收敛成一条规则（前台应用格 / 通知条目 / 待办条目，通知首页块的行是本次新加） | `t8-bands-1154(-contrast).png`、`t8-hover.png`、`t8-hover-cell(-contrast).png`、`t8-bands-770(-contrast).png`；变异 `t8-mutation2-container-inset-zero-red.log`（红 3）/ `t8-mutation1-container-opacity-zero.log`（**如实记：容器浓度无断言**） |

**与计划的偏离**（逐条给理由；计划的文件清单与派发片段在本批里有几处写窄了）：

1. **`HomeStripLayoutMath.swift` 一行未动**（计划文件清单里写了 `modify`）：分带把丢弃**限制在主块带**，主块带仍原样调用 `plan(items:available:spacing:tailReserve:)`，小组件带的行内宽度走同一个分配器——分配语义一字未改。
2. **多改了三个内核文件与两个接管模块**（T7）：`ModuleTypes.swift` / `GourdModule.swift` / `ModuleRegistry.swift`（钩子与访问器）与 `MusicModule` / `MirrorModule`（各一行 `.large`）——派发点名了它们，计划的文件清单没列全。
3. **接缝落在 `HomeBandedHomeView`（写在 `HomeStripView.swift` 里）而不是 `NotchHomeView`**：高度取舍要知道「小组件要几行」，而那是**宽度**的函数——名单与宽度都在块解析那一层。`NotchHomeView` 保留更外面那层接缝（`standardHomeContent` 一行），三条支路（极简 UI / 侧歌词 / 首发）不动。同一批把 `HomeStripView` 的块名单解析搬进 `HomeBandCatalog`（两带共用一份），并删掉它那条从未被读过的 `vm` 观测。
4. **T8 多改了三个模块文件**（`FrontAppModule` / `NotificationsModule` / `TodosModule`）：块级 hover 要「一条规则」就得把原来各写一套的底色（0.18+r5 / 0.08+r6 / 0.06+r6）收敛到 `homeBlockHoverBackground(isHovered:)`；通知**首页块的行**原来根本没有 hover（可点却无反馈），按同一条规则补上（按 id 记悬停态，不加内边距以免把三行推出 96pt 带高）。`LauncherGridCell`（启动台那一格，0.09）**未收敛**——它属展开面板的另一个 surface。
5. **T9 的「矮 25–30pt」与实测不符**（机制八 第 3 条）：实测**块内容**是 74.5 → **59pt**（布局高）/ 64.8 → **58pt**（墨迹高）；机制八 里那个 **96 是小组件带的行高**（宿主常量），不是统计块的高度。环心字号取 **11pt**（不是 11–12 的上沿）：12pt 的 `22.8%` 实测宽 38.5 > 46 环的内径 36，会压到 5pt 环带。
6. **`HolidayLookup` 的落地签名取本产品日历模型**（`[CalendarModel]` / `[EventModel]`），不是计划稿里的 `[EKCalendar]`：展示路径手上只有已加载的事件（`CalendarManager.monthEvents`），拉 EventKit 要多一层依赖且单测要造 `EKEventStore`；`isHolidayCalendar(titled:)` 是唯一的判定字符串。
7. **双行档的选中圆缩到 19pt**（计划未写）：日格恒 30pt（`HomeCalendarRow` 的 `36 × 周数 + 78` 依赖它），30pt 里「28pt 圆 + 一行 9pt 字」几何上必然重叠——`19 + 11 = 30` 是唯一不溢出、不被 ScrollView 裁顶边的解；单行档仍是 28pt。
8. **进度的展开清单视图保留不挂 surface**（计划只写 `.expanded` 改 `.none`）：删掉等于丢一份可用呈现，留着则「把 `.expanded` 加回 `surfaces` 与 `content(for:)` 两处」即可复原。
9. **收尾把笔记的 tab 分支也摘了**（派发原话是「只摘设置入口、上游代码保留」）：T5 报告实测本机 `enableNotes = 1` 时面板上真有一个 Notes tab，而摘掉设置页后它**再没有关闭入口**——这是 T3+T5 报告里那条 concern，控制器裁定按统计的先例（T1+T2 删 Stats 分支）一并摘掉；笔记代码与偏好键一个字没删，该键从此惰性（见 §已知限制 5）。
10. **「首页组件节 = 内置块 + 声明 home 的模块」在实现里是「只有模块」**（机制三 的那句描述）：宿主内置块今天为空（音乐 / 镜子已是模块块），唯一的内置面是**首页日历行**——它是 strip 之外的全宽行，不在 `homeBlockOrder` 的语义里、给不了排序，其开关在组件页的「功能」段。首页节实际只有 7 个模块行（音乐 / 镜子 / 待办 / 前台应用 / 进度 / 通知 / 统计）。
    **2026-10-01 改判（p5-home-blocks / D-06）：组件页的「功能」段已整段撤销**（`featuresSection` / `featureCards` / `FeatureCard` / `FeatureCardRow` 与七条文案 key 一起删除）：日历行那一行的开关现在是「首页组件」节末尾的 `HomeCalendarSettingsRow`；终端 / 暂存器 / 剪贴板 / 取色器进了「面板组件」节（宿主行，只有开关、没有 ↑↓）。详见 [29](29-home-blocks-and-panel.md) §做法 机制三。
11. **机制六 的第三档在文档里有两个名字**（`stripWidgetsOnly` / `widgetsOnly`）——实现取 **`widgetsOnly`**，让位链是 `both → noCalendar → widgetsOnly → none`；`HomeVerticalFit` 的旧 `.calendarOnly` 档**删除**（四档链里日历行是第一个让位的，没有「只剩日历行」这一档）。
12. **`settings.modules.effect.progress` 的文案在 T1+T2 一并改了**（派发未点名）：原文写「折叠态中央槽位 + 展开面板进度页——暂不出现在首页」，三个分句全错，改为「首页块里的紧凑进度条：日 / 周 / 月 / 季 / 年（默认今天 + 今年）」。
13. **派发要的「统计块 min220 上屏档」取不到正好 220**：面板有强制最小宽（本机 770 → 可用 702），最紧的一档是「三块一行被压缩」下的统计块 ≈261pt（> 200，仍是 46 档）——220 那一档由用例钉住（`rowWidth(forWidth: 220) == 158 ≤ 220`，即 T9 变异的靶子）。
14. **`showsScrollFades` 的默认 `true` 今天没有生产调用方**（计划/派发都以为「仅 `#Preview` 用」）：实际两个宿主都传 `false`，`#Preview` 里也没有 `MonthGridView`。默认值保留、参数在，注释已按事实写。
15. **T6 收尾按事实再收敛两处产品文案**（派发只点名统计一条，其余是**同表审计**的结果）：① `settings.features.effect.enableStatsFeature` 改「首页小组件带里的统计环（CPU / 内存 / GPU 三环，环心是百分比）」——原文写「展开面板的统计页」，统计早在本批 T2 就改成首页块；② `settings.features.effect.showCalendar` 补上「展开面板的「日历」页」——原文只有首页那一行，而日历接管（`p3-freeze` / T6）后这一个开关同时管两处；③ `settings.features.effect.enableNotes` 改成「本版无效果（…）」并**摘掉组件页那一张卡**（键惰性，卡片留着就是「拨了没反应」的那类；表与 catalog 的键都保留）。同表其余四张卡（剪贴板 / 锁屏天气 / 文件架 / 终端）的效果行逐条核过、与实现一致，未动。

**遗留项**（人工验收或后续批次；凡是「没有现场证据」的都如实写）：

1. **统计的采样驱动改在模块侧**（机制一/机制二 未提，但不做就是「环心永远 0.0%」）：上游 `StatsManager.startMonitoring()` 原先只由「展开面板停在统计 tab」触发，tab 摘掉后该路径不可达——落法是块的 `.task` 里一个 1s 看门狗 + `onDisappear` 停采样。**隐含依赖**：块必须真的走 `onDisappear`（本工程既有块都依赖 `.task` 生命周期，但本批没有专门取证「块不消失」这一档）。
2. **两行小组件带 + 日历行不能共存**：`294 + 8 + 152 + 8 + 2×96 + 8 = 662`，行高 96 是「不挤掉日历行」约束下的最高一档（见 §已知限制 7）；面板高 < ≈626 时日历行先让位（`t7-short-height.png` 实测）。
3. **镜子那一档（主块带两块）没有实拍**：`showMirror` 默认关 + 本机无摄像头可用性判据，丢块行为由纯函数用例覆盖。
4. **窄面板下「月历格只剩公历数字」的降级档没有实拍**：`MonthCellSubtitle` 的判据由用例钉住（12 / 50pt 不放行、70 / 78pt 放行、单调性），但面板 770 下首页日历行已被高度取舍让位，看不到网格。
5. **统计 40pt 环档与 `100.0%` 极小字号没有上屏证据**：在面板最小宽与块声明最小宽之间没有可达的版面，只有用例覆盖。
6. **容器的填充浓度（0.05 / 0.06）没有自动化断言**（视觉项，靠人工看图；实拍只有 +5/255 的台阶，`-contrast.png` 是放大给人看的）。纵向内边距为 0 的理由见 §已知限制 6。
7. **设置侧栏与组件页的改动没有回归用例**（`SettingsTab` / 组顺序是 `SettingsView.swift` 里的 `private` 视图枚举，单测碰不到）：变异实测「把 `.notes` 加回侧栏」仍全绿，删除与重排的证据 = 截图 + `grep` + `docs/09` §5.9；发布冒烟按 `docs/25` 的 S3 / S14 / S30 / S31 人工过。
8. **`module.stats.summary` 的文案仍写「mini bars / 迷你条」**（形态已改环状）：本批（T6）动的是**效果行**（统计 / 日历两条按事实改写，便签那条随卡片摘除改成「本版无效果」并从此不可达），这条摘要行**未改**，留给下一批或控制器（改法是中英各一句，key 不动）。
9. **组件页两节都列全量 manifest（含未启用）**：刻意的（关掉的组件必须还能开回来），代价是列表比实际内容长（默认关的模块也在名单里占一行）。
10. **组件页「功能」段的 `Enable Notes` 卡已在 T6 收尾摘除**（原先的第七行）：笔记页与 Notes tab 分支都已摘除、`enableNotes` 键惰性，卡片留着就是「拨了没反应」的那一类（判据同 §已知限制 5）。`featureCards` 表里那一行与 catalog 里的名称 / 效果行 key 都**保留未删**（效果行值已改成「本版无效果（…键惰性——卡片已摘，此文案暂不可达）」），恢复笔记入口时把那一行加回表即复活。**仍按七张写的旧计数**（不在本批文件清单里，未动）：[20](20-component-page.md)（§接口与数据形状 7 的表格、§改动点 3、§验收标准 3）与 [16](16-nookx-reference.md) §4「组件七张卡 + 功能七张卡」——留待下一批一并改。
    **2026-10-01 改判（p5-home-blocks / T4）：整段「功能」段已撤销**——`featureCards` 表与 `FeatureCard` / `FeatureCardRow` 两个类型、七条 `settings.features.*` key 一起删除（[20](20-component-page.md) 那一族旧计数已同批改判，[16](16-nookx-reference.md) §4 仍是旧计数、不在本次回写范围）。上面那句「把那一行加回表即复活」**不再成立**：恢复笔记入口要「重建表与行」（或把开关挂进现有两节）——这是一处真实的能力退化（可逆路径从「加一行」变成「重建一段」），见 [29](29-home-blocks-and-panel.md) §已知限制 19 / §实际交付 遗留项 6。

## 已知限制

1. **节假日依赖系统日历**：用户没订阅"中国大陆节假日"日历就没有节假日名（降级为只显示农历 + 事件点），界面上不提示订阅方法（写在用户手册里）。
2. **农历只在月历格里显示一行**：9pt 一行放不下时（格子过窄）不显示，避免挤压公历数字。
3. **统计首页块只显示当前值**：三环给的是「此刻的 CPU / 内存 / GPU 占用」，看不出历史趋势——完整图在**设置页的统计页**里预览（那里本来就有图表可见性开关）。
4. **两组排序是两套键**：`homeBlockOrder` 与 `panelOrder` 互不影响；同一个模块在两组里的名次可以不同。
5. **摘掉笔记入口后，笔记功能对用户不可达**：设置侧栏的笔记页（T5）与 `TabSelectionView` 的笔记 tab 分支（收尾修复）都已摘除，`enableNotes` 键从此**惰性**（拨它不再改变任何界面——今天**三处入口全无**：设置页、tab 分支、组件页卡片都已摘；偏好键、笔记代码与 `featureCards` / catalog 里那两行文案保留未删）。恢复路径是三处：把 `.notes` 加回 `availableTabs`、把笔记那一半条件加回 `TabSelectionView` 的合并分支（`enabledStandardTabCount()` 同步）、把 `enableNotes` 那一行加回 `ModuleSettingsSection.featureCards`——代码与键一个字没删。
    **2026-10-01 改判（p5-home-blocks / T4）**：第三条恢复路径**已失效**——`featureCards` 表在撤销「功能」段时连同两个类型一起删除，恢复要「重建表与行」（或把开关挂进现有两节）；键与代码仍是一个字没删。前两条路径不变。`settings.features.effect.enableNotes` 这条 key 仍留在 catalog 里、不可达（孤儿 key，见 [29](29-home-blocks-and-panel.md) §已知限制 19）。

**实现期补充（2026-09-30 回写，按代码与实测落）**：

6. **带级容器的内边距纵向为 0**（横向真 8）：默认档（1154×630）的高度预算 `日历行 294 + 缝 8 + 主块带最小 152 + 缝 8 + 小组件带 96 = 558`，可用高 ≈562——只剩 **4pt**；纵向真 padding 要 32pt，只能从「默认档先丢日历行」或「主块带掉到最小可用高之下（音乐封面被切）」里出。实现取「**横向真 8、纵向 0**」，纵向呼吸靠带内自然余量；容器高度 = 带高度，因此四档取值、`.clipped()` 与零提案三条硬约束一字未动。
   **2026-10-01 p6 改判**：本条预算是分带时代的数（日历行 294、主块带 152），已随单条流与 p5 / p6 失效（现为日历行 `36N + 52`、大块档 140）；容器**不再画底**（见本文件 §机制七 的改判与 [30](30-ui-polish-and-shelf.md) §做法 机制一）。
   **2026-10-07 再改判（[32](32-home-block-plates.md) D-23）**：**横向的 8pt 也撤了**（连同常量与修饰符一并删除），
   流的块与日历行左缘对齐、面板内容两侧留白统一 15pt——「纵向 0」的结论不复存在，因为横向这一维也归零了。
7. ~~**小组件带的行高是宿主常量 96pt**（`HomeStripView.widgetRowHeight`），**不是统计块的高度**~~ **2026-10-01 改判（p5-home-blocks / T1 · T2 · T3）：96 现在是「紧凑档」的块高**（`HomeFlowView.compactBlockHeight`，「形态 → 档高」表里的声明值）——[28](28-home-layout-redesign.md) 的单条流接手后两条带与 `widgetRowHeight` 已不在生产路径。**读数口径不变**：用户看到的「一块占 96pt」是**声明档高**（块内容自己没占满，不是被拉伸）。当时那两组实测数仍是有效读数（统计块内容 74.5 → 59pt 布局高 / 64.8 → 58pt 墨迹高）；本批装进这一档的块都改过：待办**不再画三环**（三环口径随 T1 撤销，`TodoScopeRing` 一族保留不挂 surface）、进度行高 14 + 行距 6（96 高放得下五行）、音乐紧凑条六项预算 95。详见 [29](29-home-blocks-and-panel.md) §实际交付。
8. **进度的展开清单视图保留但不挂 surface**：文件里多约 70 行不被任何 surface 渲染的代码（外加热度为它服务的两个私有出口）——这是**有意留的**（可逆：把 `.expanded` 加回 `surfaces` 与 `content(for:)` 两处即复原），将来清理时要知道它不是遗漏。
9. **枚举型 config 键的写入格式有两套，写错会静默回落默认值**（实现期为此烧掉约 20 分钟）：`Defaults` 库对**声明了 `Codable` 的枚举**走 `CodableBridge`——序列化成 **JSON 字符串（带引号）**、读时走 `Value(jsonString:)`；对**没有 `Codable` 的枚举**（如 `TimerDisplayMode`）走 `RawRepresentableBridge`——**裸串**即可。同一个应用里两种格式并存：`clipboardDisplayMode` 要写 `'"separateTab"'`，`timerDisplayMode` 写 `popover`。写错格式时**解不出来 → 静默回落默认**，屏上表现就是「改了没反应」；取证时按枚举的声明面挑格式。
10. **月历格第二行在 `hideAllDayEvents` 打开时一并消失**（含节假日名）：月历快照按该偏好过滤，全天条目不进快照——节假日名与它的事件点同进同出（与事件清单同一口径，但这是一条连锁，值得先知道）。
11. **`hiddenHomeModules` / `hiddenPanelModules` 是两张面级摘除名单**（不在原接口清单里，T3 落地时新增）：同时有 `home + expanded` 两面的模块在一节里被关，写的是名单（另一个面照旧）；单面模块才写既有启用真源。因此两节的「关」**不是一个语义**（关面 ≠ 关模块），读代码要连着 `ModuleSurfaceSwitch` / `ModuleSurfaceToggleWriter` 一起看。
12. **容器与悬停的浓度只在「首页两条带」这一个语境里是一条规则**：`LauncherGridCell`（启动台那一格，0.09）仍是例外——它属展开面板的另一个 surface；要统一只需把那一行的 `.background(...)` 换成 `homeBlockHoverBackground(isHovered:)`。
13. **节假日名的多候选取「更长标题」**：真实订阅日历里同一天常有节假日名与「休 / 班」单字标记（本机实测同日有 `国庆节（休）` 与节气名 `秋分`），取更长的那条更有信息量、且结论与事件顺序无关——这是**我们替用户定的呈现口径**，不是数据本身的顺序（若要改看「休 / 班」标记，改排序键即可）。
14. **`.noCalendar` 档的主块带容器会很高、内容只占顶部**（770pt 档实测 ≈495pt）：该档把剩余高度全给主块带（T7 的设计），容器只是把它显形了；要更好看需要给主块带设高度上限（属高度分配话题，不在本批）。

## 验收标准

> **回写注（2026-09-30）**：判据以**最终实现**为准——第 3 条的统计形态是环状（T9 改判，机制八 / D-11），第 6 条的两节即「首页组件 / 面板组件」+「功能」段。逐条结果见 §实际交付（哪条有截图、哪条只有用例、哪条留人工验收，都在那里写明）。
>
> **2026-10-01 改判（p5-home-blocks / D-06）**：第 6 条的判据改成「组件页**只剩**『首页组件 / 面板组件』两节、没有『功能』段」——「功能」段已整段撤销，五张卡逐张归位。详见 [29](29-home-blocks-and-panel.md) §做法 机制三 / §实际交付。

1. `xcodebuild test`（`DynamicIslandTests`）全绿；新增用例覆盖：`LunarDayLabel.label` 的五组（初一 / 十五 / 月末 / 闰月 / 普通日）、`HolidayLookup.holidayCalendar` 的三组（命中 / 无 / 多个候选）、`tabEntries` 按 `panelOrder` 排序、进度与统计的 manifest 取值、`HomeBandedLayout` 的换行与四档取舍、`StatsRingMetrics` 的三环不裁。
2. 进度不再有展开 tab，作为首页块出现；关掉后在首页组件里把它打开即回来（截图）。
3. 统计有开关（`enableStatsFeature`），开着时首页出现**三环**（CPU 青 / 内存 紫 / GPU 琥珀，环心百分比）、关掉即消失；设置页统计页仍有完整图预览（截图）。
4. 组件页分两节，各节都能上移/下移并即时重排（截图两张：首页组件、面板组件）。
5. 首页日历行与日历面板**都没有**那两条渐变；月历格里有农历（初一显示月名），订阅了节假日日历时当天显示节假日名（截图）。
6. 设置侧栏已重排、笔记设置页不再出现（截图对比）；笔记 tab 分支已摘（`enableNotes = 1` 的机器上也没有那张 tab）。

## 决策摘要

| ID | 决策 | 来源 | 理由 |
|---|---|---|---|
| D-01 | 进度改**首页小组件**（去掉展开 tab） | 用户 | 它没有控件、纯展示（§备选与取舍 ①） |
| D-02 | 统计改**首页小组件 + 开关**（开关仍是 `enableStatsFeature`） | 用户 | 无控制按钮、不需要单独面板；不新增第二份状态（机制二） |
| D-03 | 组件设置分**首页组件 / 面板组件**两节，各节可开关可排序（面板顺序新键 `panelOrder`） | 用户 | 用户原话；两组顺序是两件事（§备选与取舍 ③） |
| D-04 | 日历遮罩线在**首页行与日历面板**都去掉 | 用户 | 用户原话（上一批只去了首页行） |
| D-05 | 月历接**系统数据**：公历 + 农历（`Calendar(identifier: .chinese)`）+ 节假日（EventKit 里订阅的节假日日历），取不到就降级 | 用户 | 零依赖、零权限新增；中国节假日不自算（§备选与取舍 ④） |
| D-06 | **去掉笔记设置页**（摘入口、留代码），日历设置页保留并精简 | 用户 | 笔记在本产品里没有任何入口、默认关；日历的键仍在生效（机制五） |
| D-07 | 设置侧栏按使用频率与主题重排（**不设「上游功能」分组**） | 用户 | 用户 2026-09-30 追加：不要显示上游功能，这类都放到效率里（机制五） |
| D-08 | 逐页意义判定：有读点 + 有可观察效果 + 有入口 三条齐才保留，否则删页留码 | 用户 | 用户追加：看下是否有意义，有意义的保留，无实际设置意义的删除 |
| D-09 | 首页分**两条带**（主块带 + 小组件带，小组件换行不丢块）；块的形态由 `homeFormFactor` 声明 | 用户 | 用户：不要把所有小组件都放在第一排，窄宽度下会被全部隐藏（机制六） |
| D-10 | 分界视觉：带级容器 + 可交互块 hover 底，不做每块永久卡片 | 用户 | 用户问区域块样式；调研：两家都没有 per-block 卡片（机制七）。**2026-10-01 p6 改判：整条带的大底已撤**（`homeBandContainer()` 不再画底、`containerOpacity` / `containerCornerRadius` 删除），区分改由每块柔光池 + 内容辉光（`homeBlockFloat()`）做；「不做每块永久卡片」的口径**不变**（用户仍明说不加区域块与边线）——见 [30](30-ui-polish-and-shelf.md) §做法 机制一 / D-02 |
| D-11 | 统计块改环状（三环并排、环心百分比、按指标分色 + 细描边发光 + 等宽数字） | 用户 | 用户：横条太占空间，改环状或合理的科技风（机制八） |

**执行期判断（2026-09-30 回写，D-12 起续号；来源都是「agent（执行期）」，逐条对着报告里的候选决策落）**：

| ID | 决策 | 来源 | 理由 / 代价（代价写在这，别去报告里找） |
|---|---|---|---|
| D-12 | 小组件带行高取 **96pt 定值** | agent（执行期） | 默认档 `294 + 8 + 152 + 8 + 96 = 558 ≤ 562` 才留得住日历行；96 是「不挤掉日历行」约束下的最高一档。代价：面板高 < ≈626 时两行小组件带把日历行挤掉；`.widgetsOnly` 档富余高度留在带尾（§已知限制 7）。改这个数就是改跨任务常量与阈值用例。**2026-10-01 改判（p5-home-blocks）：分带渲染器已不在生产路径，96 现在是「紧凑档」的块高**（`HomeFlowView.compactBlockHeight`，见 §已知限制 7 的改判；[29](29-home-blocks-and-panel.md) 起 96 不再由「不挤掉日历行」的预算推出来） |
| D-13 | 四档定名 `both` / `noCalendar` / `widgetsOnly` / `none`；**删掉旧 `.calendarOnly` 档** | agent（执行期） | 机制六 里 `stripWidgetsOnly` 与 `widgetsOnly` 两个名字描述同一档，按语义取后者；四档链里日历行是第一个让位的，没有「只剩日历行」这一档（旧档在生产高度下从来不画日历行，行为等价）。代价：合成分支（可用高 < 152 却画日历行）没了，将来面板能更矮时要重新加档 |
| D-14 | **空带不进取舍**：没有大块 / 没有紧凑块时，四档退化成旧三档 | agent（执行期） | 这是「只有音乐的旧配置逐字不变」的保证——调用方按「有没有块」传 `mainBandMinimumHeight = 0` / `widgetRowHeight = 0`。代价：纯函数多一层「0 表示不存在」的约定，传错 0 会让一条带静默消失 |
| D-15 | 带级容器**只做横向内边距 8，纵向 0**（**2026-10-07 由 [32](32-home-block-plates.md) D-23 撤销：横向 8 也删了**） | agent（执行期） | 默认档高度预算只剩 4pt，纵向真 padding 会先丢日历行或把音乐块压到最小可用高之下（§已知限制 6）。代价：容器与内容在纵向可能贴边；要「四周都是 8」得先动行高 / 让位顺序。**D-23 起用户改判：这道横向内缩本身也偏大，撤掉后与日历行对齐** |
| D-16 | 块级 hover **收敛成一条规则**（`HomeBandChrome` 是唯一取值处），通知首页块的行补 hover、启动台那一格留作唯一例外 | agent（执行期） | 三处原来各写一套浓度（0.18+r5 / 0.08+r6 / 0.06+r6），不收敛就没有「一条规则」；通知首页块的行可点却无反馈，与同一带内的前台应用格不一致。代价：严格讲「一条规则」有一处例外（启动台 0.09，属另一个 surface）——要统一只需换那一行的 `.background(...)` |
| D-17 | 统计的**采样驱动放模块侧**：块 `.task` 里 1s 看门狗 + `onDisappear` 停 | agent（执行期） | 上游 `startMonitoring()` 原挂在「展开面板停在统计 tab」，tab 摘掉后该路径不可达；不改上游就只能由模块自己拉（与上游同一功率档）。代价：块可见期间每 1s 读一次布尔量；隐含依赖「块真的会消失」（§实际交付 遗留项 1） |
| D-18 | 统计的 `defaultPlacement.order` 取 **50**、`config` 登记**四键**（真源键 + 三个图表可见性登记键）、环心字号取 **11pt** | agent（执行期） | order 50 = 现有模块序号最大值（notifications 40）+ 10，老用户那条 strip 的前几块一位不动；三个图表键仍是上游设置页里活的键（完整图的可见性来源），登记后卡片会如实出现「由上游设置管理」；11pt 是「读数即焦点又不压环带」的那一档（12pt 会压到 5pt 环带）。代价：order 50 是本批最可能被改的数字；登记键在 tab 摘掉后与面板无关，若认为该删，从 manifest 的 `config` 删三条即可（用例键集合断言同步一行） |
| D-19 | 环状**按指标分色取面板既有 accent 家族**（CPU 青 / 内存 紫 / GPU 琥珀），与展开图不同族 | agent（执行期） | 机制八 给了三个色相且要求「从既有 accent 家族里挑」——取的是本产品里已在用的系统色（`.cyan` 磁盘图 / `.purple` GPU 详情 / `.orange` 待办与网络），未新造 hex。代价：首页环与设置页那张展开图不同色（改 `Row.ringColor` 三行即同色，用例会跟着红） |
| D-20 | `HolidayLookup` 落地签名取 `[CalendarModel]` / `[EventModel]`（不是计划稿的 `[EKCalendar]`）；多候选取更长标题 | agent（执行期） | 展示路径手上只有已加载的事件（`CalendarManager.monthEvents`），拉 EventKit 要多一层依赖且单测要造 `EKEventStore`；同一天常有节假日名与「休 / 班」标记，取更长的更有信息量且与事件顺序无关。代价：签名与计划稿不同（已在 §接口与数据形状 校正）；呈现口径是我们替用户定的 |
| D-21 | 双行档的选中圆缩到 **19pt**（单行档仍 28pt） | agent（执行期） | 日格必须恒 30pt（`HomeCalendarRow` 的 `36 × 周数 + 78` 依赖它），30pt 里「28pt 圆 + 11pt 第二行」几何上必然重叠；`19 + 11 = 30` 是唯一不溢出、不被裁的解。代价：选中视觉在能显示第二行的档位比上一批小一圈（另一条路要加高日格 → 把小组件带挤出默认高度，更贵） |
| D-22 | 进度的展开清单视图**保留不挂 surface**（可逆） | agent（执行期） | 删掉等于丢一份可用呈现；把 `.expanded` 加回两处即复原。代价：约 70 行静态看是死代码（§已知限制 8） |
| D-23 | 组件页两节的「关」用**两张面级摘除名单**（`hiddenHomeModules` / `hiddenPanelModules`），单面模块写既有启用真源 | agent（执行期） | 同时有两面的模块在一节里被关，直接写启用真源会把另一个面一起摘掉；单面模块不进名单 = 关掉就是关模块，不新增第二份状态。代价：多两个偏好键，两节的「关」不是一条语义（§已知限制 11） |
| D-24 | 收尾把**笔记的 tab 分支也摘掉**（`TabSelectionView` 只看剪贴板），键从此惰性 | agent（执行期，控制器裁定） | T5 摘掉设置页后，`enableNotes = 1` 的机器上面板仍有一个 Notes tab 且**再无关闭入口**（T3+T5 报告的 concern）；按统计的先例（T1+T2 删 Stats 分支）一并摘。代价：`enableNotes` 键不再产生任何入口（当时组件页那张卡还在但已写「本版无效果」；**T6 收尾连卡也摘了**——今天连可拨的开关都没有）；恢复要改三处（§已知限制 5） |
| D-25 | 首页「两节 + 全量 manifest」的列表**保留全量**（含未启用） | agent（执行期） | 关掉的组件必须还能开回来（用投影会让它从列表消失）。代价：列表比实际内容长（默认关的模块也占一行） |
