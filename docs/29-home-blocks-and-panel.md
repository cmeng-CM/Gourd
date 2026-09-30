# 首页块、面板与设置的重做（七项反馈）

| 项 | 值 |
|---|---|
| 状态 | **已实现**（工作流 `p5-home-blocks` 九任务三阶段，2026-09-30 开工、2026-10-01 收口；实现提交范围 `efecc332..c2949c46`，回写提交紧随其后） |
| 最后更新 | 2026-10-01 |
| 触发 | 用户 2026-09-30 一轮七条反馈（待办、进度、设置去重、面板开关、音乐过大、Nook X 效果、高度自适应） |
| 关联 | [28](28-home-layout-redesign.md)（单条流已落地）、[26](26-home-widgets-and-settings.md)（分带与 D-10~D-12）、[16](16-nookx-reference.md) §5（Nook X 首页）、[21](21-strip-honesty.md)（丢块与 `＋N`）、[17](17-nookx-adoption.md)（块宽声明）、[27](27-acceptance-2026-09-30.md)（上一轮验收） |

> **怎么读**：§背景与目标 / §明确不做 / §备选与取舍 是这场改动的判断依据（拍板看这三节 + §决策摘要）；
> §接口与数据形状 是参考型小节（执行者与机器查考），人审可跳过；
> §已知限制 / §实际交付 是留给后来人的。

---

## 反馈 → 决策对照

七条反馈与本文的落点（编号即用户原话的顺序）：

| # | 用户原话（摘） | 落点 |
|---|---|---|
| 1 | 首页待办只显示今日的就行，不需要其他的；那三个圈不要了，看怎么设计下 | 机制一 / D-01 D-02 |
| 2 | 进度只显示今日和今年，没按说明显示日周季度；也没地方控制开关；从设计、交互、目的考虑它是用来做什么的、显示什么单位 | 机制二 / D-03 D-04 D-05 |
| 3 | 组件设置里首页组件和功能模块都有统计，重复了，功能里的开关也没什么作用；锁屏应该在锁屏的菜单里，终端应该在面板组件里 | 机制三 / D-06 D-07 |
| 4 | 并不是所有面板组件都可以开关，隔空投送那个就不可以；除了首页，都要可以控制开关、是否显示 | 机制三 / D-07 D-08 |
| 5 | 音乐占比太大了，要缩小，可以不显示那个图片 | 机制四 / D-09 D-10 |
| 6 | 截图是 Nook X 的首页效果，这个显示效果就很好，不是照抄，是考虑怎么在现在的功能基础上实现类似的效果 | 机制五 / D-14 §备选与取舍 ⑤ |
| 7 | 这个高度会自适应变化，这个也可以参考；可以初始设计一版完美的模式；如果修改后想换回来，可以在外观的地方重置为系统默认 | 机制六 机制七 / D-11 D-12 D-13 |

---

## 一句话方案

把首页从「两条带 + 一条日历行」收敛成**每块只讲一件事**的密排流（待办只讲今日、进度只讲时间、音乐缩成一条），把面板上的**每一个 tab 与图标**都收进「面板组件」节里开关，并让展开面板的高度**贴住内容**——设置页里那张模块与上游开关重复的「功能」登记表随之撤销，它的每一行各自回到真正管它的那一页。

---

## 背景与目标

### 问题现状

上一批（[28](28-home-layout-redesign.md) §4）已把首页改成单条流：块按声明宽度贪心装行、行高取行内最高块、装不下换行不丢块。它解决了「第一排只有音乐、其他全挤第二排」，但**块的形态与内容口径**没动，于是用户看到的仍是七个问题：

1. **待办块**：三环（今日/本周/所有）+ 今日清单。三环是**聚合计数**（今日与本周刻意重叠，见 `TodoBucketing` 文件头），一行 `1/4` 读不出「哪件事该做」；用户要的是今日那几条。
2. **进度块**：`ProgressCalculator` 算的其实是**自然时间进度**（`日/周/月/季/年` 五个尺度，区间取 `Calendar.dateInterval`），但模块把 `visibleScopes` 的**默认值**写死成 `[.day, .year]` 并直接读 manifest（`ProgressModule.scopes` 的注释："本版直接读 manifest：没有用户可见的配置入口"）。于是**模块自己的简介写着「日/周/月/季/年进度」，屏上只有两行**，且没有任何入口能改——这就是第 2 条的「没按说明显示」「没地方控制」。
3. **设置重复**：「组件」页同时有 ①首页组件节的**统计模块卡**（开关走 `ModuleEnablementWrite` → `StatsModule.takeoverEnableKey`）②「功能」段的**统计卡**（开关直接写 `Defaults[.enableStatsFeature]`）——两个开关写同一个键。同类还有终端（「功能」段 + 终端页）、暂存器（「功能」段 + 暂存器页）。
4. **面板开关不全**：「面板组件」节的名单**只由模块 manifest 投影**（`surfaces.contains(.expanded)`），而面板上还有四个**宿主 tab/图标**——暂存器（`dynamicShelf`）、终端（`enableTerminalFeature`）、剪贴板（`enableClipboardManager`）、取色器（`enableColorPickerFeature`）——它们都不在这一节里。用户说的「隔空投送那个」，就是暂存器页里那个分享方块（AirDrop 是它的 Quick Share 提供方）。
5. **音乐块**：声明 `300/420` 且形态为 `.large`（行高 152），封面在 420 宽下被拉成约 133pt 见方——一块占掉首行近半宽度与整行高度。
6. **Nook X 效果**：见 §备选与取舍 ⑤ 的调研结论——它的可迁移之处不是视觉皮肤，而是**一块一件事 + 块形随内容 + 面板贴内容**三条。
7. **高度不贴合**：面板高度是用户滑块（`openNotchHeight`，默认 200，范围 120…850），首页填不满时下方留大片空白；用户要「高度自适应 + 能一键回到默认」。

### 预期结果

- 待办块：**只有今日**——一行「今日 · 1/4 + 细进度条」+ 今日清单（条数随块高），无三环。
- 进度块：**默认三行（今天 / 本周 / 本月）**，五档（加 本季 / 今年）可在组件卡里勾选；它是**时间进度**（自然日历口径），不表达任务完成度。
- 设置：「功能」段整段撤销；统计不再有第二个开关；锁屏天气回到锁屏页；终端 / 暂存器 / 剪贴板 / 取色器进「面板组件」，与模块行一样有开关。
- 面板：**面板上的每一个 tab 与图标都能关**——具体到「面板组件」节接管四条宿主行（暂存器 / 终端 / 剪贴板 / 取色器），模块行已有；镜子归首页组件的镜子卡，计时器归模块行，用量/齿轮/状态指示器/扩展 tab 各归原处（见 §做法 机制三的枚举表）。
- 音乐块：宽度降到 `240/300`、高度降到紧凑档（96），**默认不画封面**（打开则画 40pt 小封面）。
- 高度：新增「自适应」模式（默认），展开面板高度 = 内容自然高 + 宿主内边距，夹在 `[120, min(850, 0.9×屏高)]`；外观页给「恢复默认」。

---

## 做法

### 机制一 · 待办块：三环换成「一行计数 + 今日清单」

首页块不再画三环，改成**表头一行 + 清单**：表头是类别名（`今天`）+ `已办/总量` 计数 + 一条细进度条（宽度吃掉剩余空间）；清单是今日条目，沿用现有的 `TodoHomeRow`（完成圈 + 标题 + 过期红字）与紧凑行（只标题）。**清单行数由块的可用高度算**（`floor((高度 − 表头 − 间距) / 行高)`），不再由块宽分三档——块高变了行数跟着变，这是「内容贴容器」的第一步。三环（`TodoScopeRing` / `TodoRingPicker` / `TodoRingLayout`）**代码保留但不挂任何 surface**（与笔记、进度展开页同一条可逆口径）。今日 0 条时画一行浅色空态（新增一个文案 key），不再「只留三个 0/0 的环」。
> 依据：D-01 / D-02；`TodoBucketing.classify` 的今日成员口径（含逾期未完成、含今天完成的）一字不改——只换画法。

### 机制二 · 进度块：把「自然时间进度」这件事说清并交出去配

**它是什么**（第 2 条的「从设计、交互、目的考虑」）：进度块回答的是**「这段时间过去多少了」**——一种时间感/节奏感，不是任务完成度（那是待办的事），也不是工作量（没有数据源）。**单位是自然时间**：`Calendar` 的 `.day` / `.weekOfYear` / `.month` / 自算季度 / `.year`，跟着系统日历与 `firstWeekday` 走，**不是小时、不是工作日**（工作日需要节假日表与调休规则，本产品不引入该数据源；`remaining(for:)` 给出的「小时/分钟」只服务展开面板那份剩余量清单）。故模块显示名从「进度」改为**「时间进度」**，简介保留五档说法但改成与默认一致。

**怎么配**（原本的缺口）：默认尺度从 `[.day, .year]` 改为 **`[.day, .week, .month]`**（三行刚好填满 96 高的紧凑块）；模块改为读 `context.config`（`ConfigHandle` 已支持 `[String]` 往返与「覆盖值优先、坏值回落默认」），设置侧在组件卡的「显示的尺度」一行给**多选控件**（五档胶囊，勾选即写）。多选是 `configControls` 允许清单里的**新控件种类**（今天只有 boolean / number / integer），它按模块 id + 键名逐条登记，与既有三条口径（只收模块真读的键、接管键不进清单、区间取模块常量）逐字相同。块内行数按可用高度裁剪：勾了五档而块只放得下三行时，**按声明顺序画前三行**，不缩字。
> 依据：D-03 / D-04 / D-05。

### 机制三 · 设置：撤销「功能」段，面板组件收全

**「功能」段整段撤销**（`featuresSection` 与 `featureCards` 表一起删），五张卡逐张归位：

| 卡 | 去向 | 为什么 |
|---|---|---|
| 统计 `enableStatsFeature` | **删**（不再有第二张卡） | 首页组件节的统计模块卡写的就是这个键 |
| 终端 `enableTerminalFeature` | 面板组件节（宿主行） | 它管的是「展开面板有没有终端页」 |
| 暂存器 `dynamicShelf` | 面板组件节（宿主行） | 同上；用户点名的「隔空投送那个」 |
| 剪贴板 `enableClipboardManager` | 面板组件节（宿主行） | 同上（面板上有它的图标或 tab） |
| 锁屏天气 `enableLockScreenWeatherWidget` | **锁屏设置页** | 用户原话：锁屏应该在锁屏的菜单里 |

**「面板组件」节的名单**由「声明 `.expanded` 的模块」扩成**模块行 + 宿主行**：宿主行是面板上那四个由 `Defaults` 直接门控、不经模块注册表的 tab/图标（暂存器、终端、剪贴板、取色器）。宿主行**只有开关、没有 ↑↓**——面板上它们的先后是写死的（`TabSelectionView` 的拼装顺序），给两个点不动的箭头比不给更坏（与首页日历行同一条先例，[28](28-home-layout-redesign.md) §5）。节脚注据此改写：**这一节是「面板上出现什么」的全量清单**——四条宿主行 + 声明 `.expanded` 的模块行；其余面板元素（镜子 / 计时器 / 用量 / 齿轮 / 状态指示器 / 扩展）各有归属，见下方枚举表。

**键 → 行的映射**：宿主行复用**上游设置页那一项的名称字面量**（`Enable shelf` / `Enable terminal` / `Enable Clipboard Manager` / `Enable Color Picker`——四条的 key 都已在 `Localizable.xcstrings` 里），与模块行逐字同一条口径（用户在别处认识的词与这里看到的必须是同一个 key）。

**D-08 的边界枚举（防「全部门槛键」这条断言不可达）**：这一节管的是「面板上出现什么」——具体是**四个宿主行 + 声明 `.expanded` 的模块行**。面板上其余门槛键各有归属，本节**不重复**：

| 面板元素 | 门槛键 | 归属 |
|---|---|---|
| 左列 暂存器 tab | `dynamicShelf` | 面板组件 · 宿主行 |
| 左列 终端 tab | `enableTerminalFeature` | 面板组件 · 宿主行 |
| 左列 剪贴板 tab / 右侧剪贴板图标 | `enableClipboardManager`（+ `clipboardDisplayMode` / `showClipboardIcon` 决定形态） | 面板组件 · 宿主行 |
| 右侧 取色器图标 | `enableColorPickerFeature`（+ `showColorPickerIcon`） | 面板组件 · 宿主行 |
| 右侧 计时器图标 | `enableTimerFeature`（+ `timerDisplayMode`） | 面板组件 · **计时器模块行**（同一个键，模块卡已在） |
| 右侧 镜子图标 | `showMirror` | **首页组件 · 镜子模块卡**（`MirrorModule` 只声明 `.home`，它的开关天然在那一节） |
| 左列 用量 tab | `enableLLMUsageFeature` | **不进本节**：上一批「删页留码」的裁决保留——它默认关、无入口，面板上不会出现它（[26](26-home-widgets-and-settings.md) D-08） |
| 右侧 齿轮 | `settingsIconInNotch` | 外观页既有开关，**不算组件开关**，不进本节 |
| 右侧 录屏 / 勿扰 / 电池指示器 | `showRecordingIndicator` / `showDoNotDisturbIndicator` / `showBatteryIndicator` | 各自的既有设置页，**不进本节** |
| 左列 扩展 tab | `enableThirdPartyExtensions` 三连 | 扩展设置页，**不进本节** |
| 左列 首页 tab | 无（常驻） | —— |

「形态键」（`clipboardDisplayMode` / `timerDisplayMode` / `showClipboardIcon` / `showColorPickerIcon`）仍留在各自的上游设置页：本节管的是**在不出现**，形态是「以什么形式出现」。
> 依据：D-06 / D-07 / D-08。

### 机制四 · 音乐块：从「大块」降到「一条」

音乐块三处声明一起改：宽度 `300/420` → **`240/300`**、形态 `.large` → **`.compact`**、封面 `showAlbumArt` 默认 **false**（打开则画 40pt 小封面）。**紧凑条要自己的密度**（T3 阶段 Checkpoint 实测改判，见 D-17）：`MusicControlsView` 的标准档内容（曲名 + 艺人 + 进度 + 控制）约 127pt，装不进 96 的紧凑档——把它的**艺人行、歌词行、大内边距交给展开面板**，紧凑档只留「曲名（单行，截断）+ 进度条 + 控制三键」，因此四个元素都在块内、不裁不溢。它是首页唯一一个**因为太大而把整行撑到 152 高**的块（`HomeStripView.minimumUsableHeight` 的 152 就是从它的封面量出来的），它降到紧凑档后「大块档」就没有成员了——**大块档的高度改由镜子定义，而且必须是显式选定值、不是实测值**：镜子块体是 `CameraPreviewView`（`GeometryReader` + `.aspectRatio(1, .fit)`），**没有固有高度**，圆的直径 = `min(分到的宽, 行高)`；「实测」只会量到当前档高，是循环。故取 **大块档 = 镜子的方形边长 `140`**（= 镜子块的最小宽），并把镜子块的宽度声明收敛成 `140/140`：圆恰好是方形、块内不留横向空档，档高与块形同源。封面开关**不新增状态**：它已经是音乐模块 manifest 里的 `showAlbumArt`，只是默认值翻面。
> 依据：D-09 / D-10 / D-17。

### 机制五 · Nook X 的三条可迁移原则（不是照抄它的皮肤）

读它的官方截图与版本历史（[16](16-nookx-reference.md) §5.1）后，只取三条能落在我们功能上的：

1. **一块一件事**：它的每块只表达一个量（时间、天气、待办清单、笔记、番茄钟环、应用图标）。本批把我们的块逐个收到这一条上——待办去掉三环只讲今日、进度只讲时间、音乐缩成一条、统计保持三环（三个数是同一件事的三个维度）。
2. **块形随内容**：它的块宽高由内容定，不是等分网格。我们已有「宽度由模块声明 + 流按内容装行」（[28](28-home-layout-redesign.md) §4），本批补上**高度也随内容**（机制六）与**形态由模块自己画**（镜子是圆、封面是圆角方、其余是文字条）。
3. **面板贴内容**：它的面板高度跟着块走。见机制六。

**不抄的**：Free/Pro 门控、AI 对话、应用启动台的双指翻页、逐块卡片皮肤（理由见 §备选与取舍 ⑤）。
> 依据：D-14。

### 机制六 · 面板高度自适应

新增偏好 `panelHeightMode`（`auto` 默认 / `manual`）：

- **manual**：今天的行为——用户拖右下角 / 用外观页滑块（`openNotchHeight`），逐字不变。
- **auto**：展开面板的高度 = **内容自然高 + 宿主内边距**，夹在 `[openNotchHeightRange.lowerBound, effectiveOpenNotchHeightUpperBound(屏高)]`（与滑块同一个上界函数，不另立一套）。首页那一份**不需要额外测量**——流的方案里已经算好 `heightUsed`（各行的行高 + 行距），加日历行与容器内边距就是答案；其它 tab（待办、通知、日历、启动台、快捷指令、计时器、暂存器、终端…）用内容上报（`onGeometryChange` → 一个宿主侧的高度账本），**带 8pt 滞回**：只在高度差超过阈值时改窗口，避免「内容一变→面板一缩→内容重排」的抖动。

四个必须写下的边界：① **光标在面板里时不缩**（只允许长高）——否则鼠标停在下方会把面板从光标底下抽走；② **切换 tab 时才重新取高度**，同一 tab 内容微动（如秒数跳动）不改窗口；③ **右下角的拖动把手只在 manual 模式出现**——auto 下拖动写的那个键当场没有效果，留着它就是本仓已经明确规避的「拖了没用」（`ContentView` 的极简模式隐藏把手是同一条先例）；④ **`calculateRequiredNotchSize` 里那几条 per-tab 覆盖**（计时器 / 便签 / 剪贴板 / 终端的高度下限）在 auto 下**取 `max(覆盖值, 内容高)`**——它们是某些 tab 的下限，不是上限。

**高度怎么收敛**（首页那一份的种子口径）：内容高按**当前面板高度**算一次（`availableHeight` 用当前值），然后**双向**向不动点收敛——高于不动点就收缩、低于就长高（**不是**单向棘轮：种子低于内容高时若只许收缩，面板永远长不上去，日历行与后半行会永久不画）；夹取后不再回头改内容（避免「算出的高 → 重排 → 又算」的振荡）。唯一的单向规则是「光标在面板内时不缩」。因此首页没有滞回、但**仍有首帧一拍**，如实记在 §已知限制。
> 依据：D-11 / D-12。

### 机制七 · 外观页的「恢复默认」

外观页新增一组**「面板布局」**：高度模式（自适应 / 手动）+ **恢复默认**按钮（带确认对话框）。恢复默认**只重置布局与显示那一组键**（清单见 §接口与数据形状），不动账号、权限、内容类设置（提醒授权、日历选择、剪贴板历史、快捷指令清单…）——判据是「这个键丢了会不会让用户丢东西/要重新授权」。按钮的语义在按下时用一句副标题说清（"把首页/面板的排布与尺寸恢复出厂，不动你的账号与内容"）。
> 依据：D-13。

---

## 备选与取舍

① **待办保留三环、只把「本周/所有」换掉** —— 否决：用户明确说「那三个圈不要了」；且环表达聚合计数，与「今日清单」是两种读数，留一个更清楚。
② **进度块改成环（像 Nook X 的番茄钟 / 我们的统计块）** —— 否决：五档环并排会挤成噪声，且统计已是三环——首页上两种环会互相干扰。细条 + 百分比在 96 高的块里能放三到五行。
③ **进度改成「工作日」口径** —— 否决：工作日要节假日表 + 调休规则（中国节假日各年不同、还要处理跨年调休），是新的数据源与维护面；而这块的用途是「时间感」，自然时间已经够。写在 §明确不做 里，防以后有人当缺失来补。
④ **设置页保留「功能」段、只在重复项上标注「同上」** —— 否决：重复的开关本身是坑（拨了一个不知道另一个在哪），且用户说它「没什么作用」；归位比标注便宜，也不会留两份真源。
⑤ **给每块加永久卡片底（照 Nook X 的观感）** —— 否决：上一批调研过（[26](26-home-widgets-and-settings.md) D-10）——每块卡片要吃 8~16pt 内边距，而宽度预算是最紧的一项（默认面板宽 1154 下可用宽 ≈1086，六块最小宽之和已达 1280）；Nook X 本身也不是每块都有卡（只有备注卡有细边），它靠的是留白与字号分层。本批改走机制五那三条。
⑥ **高度自适应用「测量一切」的统一方案（首页也靠上报）** —— 否决：首页的自然高是**算得出来的**（流方案在渲染前就有），用测量反而引入首帧跳动；两条路各用其长，代价是两套入口（已在 §接口与数据形状 写明）。
⑦ **「恢复默认」做成整域重置（`removePersistentDomain`）** —— 否决：会连提醒授权、日历来源、剪贴板历史一起丢；用户要的是「布局改丑了能回去」，不是「清空我的设置」。

---

## 接口与数据形状

> 参考型：执行者的契约。本节按**落地后的实际签名**写（回写时逐条对着代码核过，不是计划稿）。
> 角色分工：**模块侧**只声明形态与宽度，**宿主侧**只摆放，**尺寸层**只做算术。

### 新增 / 变更的偏好键（`Defaults`）

| 键 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `panelHeightMode` | `Key<String>` | `"auto"` | 面板高度模式（裸字符串，与 `timerDisplayMode` 同形）。`PanelAutoHeight.isAuto` 只把 `"manual"` 认作手动档——**未知值按默认档 auto** |

### 「恢复默认」的重置清单（`PanelLayoutDefaults`）

```swift
enum PanelLayoutDefaults {
    static let resetKeys: [String]                                     // 17 键，逐项取自强类型键的 .name（顺序即下表）
    static func reset()                                                // = Defaults.reset(resetKeys)：逐键 removeObject，不是写默认值
    static func expandHeightSliderEnabled(heightMode: String) -> Bool  // = !PanelAutoHeight.isAuto(heightMode)
}
```

清单（顺序即代码里的顺序）：`openNotchWidth`、`openNotchHeight`、`panelHeightMode`、`homeBlockOrder`、`panelOrder`、`hiddenHomeModules`、`hiddenPanelModules`、`moduleEnableOverrides`、`showCalendar`、`enableStatsFeature`、`dynamicShelf`、`enableTerminalFeature`、`enableClipboardManager`、`enableColorPickerFeature`、`showMirror`、`showStandardMediaControls`、`enableTimerFeature`。

**明确不在清单里**：`enableScreenAssistant`、`quickShareProvider`、`enableLLMUsageFeature`（功能入口类——关掉是丢入口）；提醒 / 日历授权相关与 `calendarSelectionState`；`ClipboardHistory` / `ClipboardPinnedItems` / `ColorPickerHistory` / `ScreenAssistantFiles`（内容类）；`pinnedShortcuts` / `cachedShortcuts`（在模块自己的 suite `com.cmeng.gourd.module.shortcuts` 里，本清单连够都够不着）。
三条口径：① **唯一清单**（别处不再抄第二份）；② 每项取强类型键的 `.name`（改名 / 删键编译期就断）；③ `reset()` 是**删掉**键、不是写默认值（「未设置 = 出厂默认」由库保证；写一个等于默认值的值会让「盘上有没有这个键」不可判）。

### 面板高度的算术（`DynamicIsland/sizing/PanelAutoHeight.swift`，纯函数、不持有状态）

```swift
enum PanelAutoHeight {
    static let modeAuto = "auto"; static let modeManual = "manual"
    static func isAuto(_ mode: String) -> Bool                          // != "manual"

    static let notchLayoutSpacing: CGFloat = 8                          // NotchLayout 里表头↔内容那道缝（具名）
    static let homeVerticalPadding: CGFloat = 16 + 12 + 4 + notchLayoutSpacing       // = 40（逐项见下表）
    static let panelVerticalPadding: CGFloat = 12 + 4 + notchLayoutSpacing           // = 24（所有 tab 共享）
    static let homeOnlyVerticalPadding: CGFloat = homeVerticalPadding - panelVerticalPadding  // = 16（首页独有）

    static func panelHeaderHeight(effectiveClosedNotchHeight: CGFloat) -> CGFloat    // max(24, …)
    static func measuredContentHeight(naturalHeight:headerHeight:) -> CGFloat        // = 自然高 + 表头 − 16
    static func naturalFlowBudget(hostChrome:screenVisibleHeight:) -> CGFloat        // 上界 − 宿主开销（有限数，不是无界）
    static func panelHeight(contentHeight:mode:manualHeight:screenVisibleHeight:) -> CGFloat
    static func contentHeight(from:calendarHeight:calendarSpacing:headerHeight:) -> CGFloat
    static func mergedTabHeight(override:current:mode:) -> CGFloat                   // manual 逐字替换 / auto max
    static let convergenceMaxIterations = 6; static let convergenceEpsilon: CGFloat = 0.5
    static func convergedPanelHeight(seedPanelHeight:mode:manualHeight:screenVisibleHeight:contentHeight:) -> CGFloat
    static func heldForPointer(converged:currentPanelHeight:pointerInsidePanel:) -> CGFloat
}
```

**`homeVerticalPadding` = 40 的四个具名来源**（面板内、可见黑框以内的四处内边距逐项求和）：

| 项 | 出处 |
|---|---|
| **+16** | `NotchHomeView` 的 `.padding(8)`（上下各一，非极简档）——**只有首页有** |
| **+12** | `ContentView` 展开态底边 `.padding([.horizontal, .bottom], 12)` |
| **+4** | 刘海屏顶出血 `notchTopScreenBleedAmount`（浮动药丸模式顶部不占） |
| **+8** | `NotchLayout()` 里表头↔内容那道缝（`notchLayoutSpacing`；T6 实机测量发现漏算，后果是日历行整行被丢） |

**刻意不计入**：`notchShadowPaddingStandard = 18`（加在返回值**之上**；实测确认在可见黑框之外——窗口 588 = 黑框 570 + 18，折进来就是双重计数）、`adjustedSizeForScreen` 的面板外顶出血 4（与面板内那 4 是同一份量的两侧）。口径：**可见黑框 ≈ `panelHeight(...)` 返回值 + 4**；面板底部可见留白 = 8 + 12 = **20pt**。

**读取点**（唯一权威源是 `sizing/matters.swift` 的 `openNotchSize.height`——`calculateRequiredNotchSize` / 打开面板那条 / `ContentView.dynamicNotchSize` 都读它）：

```swift
openNotchSize.height = clampedOpenNotchHeight(
    PanelAutoHeight.panelHeight(
        contentHeight: PanelContentHeight.shared.current ?? .nan,   // 账本口径（含面板表头）
        mode: panelHeightMode,
        manualHeight: openNotchHeight,
        screenVisibleHeight: NSScreen.main?.visibleFrame.height
    )
)
```
manual 档 `panelHeight(...)` 原样返回手动值 → 那条链逐字是改动前那条。

### 高度账本（`DynamicIsland/Kernel/PanelContentHeight.swift`）

```swift
@MainActor final class PanelContentHeight: ObservableObject {
    static let shared: PanelContentHeight
    static let homeTab = "home"
    static let hysteresis: CGFloat = 8
    static let measuredTabs: Set<String>       // todos / notifications / launcher / shortcuts（模块 id）
    static func isMeasuredTab(_ tab: String?) -> Bool

    var pointerInsidePanel: @MainActor () -> Bool     // 宿主注入 vm.isMouseHovering()
    private(set) var activeTab: String?
    private(set) var measuredHeight: CGFloat?
    private(set) var homeContentHeight: CGFloat?      // 首页那一份（权威；只接首页写入、刻意不发通知）
    var current: CGFloat?                             // 尺寸层只读它

    func selectTab(_ tab: String)                  // 切页声明：首页 → 读算出来的；名单内 → 保留旧值 + 第一份上报无条件；名单外 → 清值（nil → 手动值）
    func setHomeContentHeight(_ height: CGFloat?)  // 只写槽，不碰 activeTab
    func report(_ height: CGFloat, for tab: String) // 四条款：非有限忽略 / 同 tab <8pt 滞回 / 换 tab 无条件 / 同 tab 且光标在内只增
    func reset()                                   // 只给测试（把单例恢复到出厂态）
}

extension View {
    func panelContentHeightReport(tab: String, headerHeight: CGFloat,
                                  isCurrent: @escaping @MainActor () -> Bool) -> some View
}
```
**探针不是 `onGeometryChange`**：一个 `Layout`（`PanelNaturalHeightLayout`）在 `placeSubviews` 里按 `ProposedViewSize(width: bounds.width, height: nil)` 量这一页的**理想高**（宽按面板给的那个格子、高留空），`sizeThatFits` 逐字转发提案（渲染透明）。
**首页不走上报**：接缝 `HomeBandedHomeView` 把「流方案的内容高 + 日历行（画了才加）+ 面板表头」算出来写 `setHomeContentHeight(_:)`；双向收敛与「光标在面板内不缩」都在那一侧做完。

### 模块侧（逐条对代码）

```swift
// DynamicIsland/Modules/ProgressCalculator.swift
static let defaultVisibleScopes: [Scope] = [.day, .week, .month]      // 原 [.day, .year]
static func resolveScopes(from value: ConfigValue?) -> [Scope]        // 只做「拆出 .strings」再转调下一条（两条入口不可能漂）
static func resolveScopes(from raw: [String]) -> [Scope]              // 空表 / 全坏值 → 默认三档；坏值逐项忽略；顺序按输入；去重

// DynamicIsland/Modules/ProgressModule.swift
var scopes: [ProgressCalculator.Scope]     // internal（T2 起；原 private）：context.config.get("visibleScopes", as: [String].self) ?? []
enum ProgressHomeBlockLayout {
    static let rowHeight: CGFloat = 14         // 11pt 文字的自然行高（实测）
    static let rowSpacing: CGFloat = 6         // 5×14 + 4×6 = 94 ≤ 96：96 高的块放得下五档
    static let barHeight: CGFloat = 6          // 细条（把 .linear 的默认 20 压下来）
    static let allScopesWidth: CGFloat = 180   // 宽度档门槛（= 模块声明的最小宽；twoRowWidth = 220 已删）
    static func rowLimit(forWidth width: CGFloat) -> Int    // 非有限 → 1；≥180 → 5；更窄的有限宽（含 0）→ 3
    static func rowLimit(forHeight height: CGFloat) -> Int   // floor((height + rowSpacing) / (rowHeight + rowSpacing))，钳 0…5
    static func listedScopes(_:forWidth:height:) -> [Scope]  // 两档取小者，截传入那一组的前缀
}

// DynamicIsland/Modules/TodosModule.swift
enum TodosHomeBlockLayout {
    enum Tier { case full, compact }            // 语义 = 行形态（不再决定行数；没有 .ringsOnly）
    static let compactListWidth: CGFloat = 160  // ≥ 160 → .full；更窄 / 非有限 → .compact
    static let headerHeight: CGFloat = 16
    static let rowHeight: CGFloat = 16          // 完整行与紧凑行都钉在这（行数是按它算的，行高必须是真的）
    static let listSpacing: CGFloat = 4         // 表头↔清单一段；清单行间 spacing = 0（行高 16 已含行距）
    static let maximumRows = 8
    static func rowCount(fittingHeight height: CGFloat) -> Int   // floor((h − headerHeight − listSpacing) / rowHeight)，钳 0…8；非有限 → 0
    static func listTier(forWidth width: CGFloat) -> Tier
    static func listedItems(_ items: [TodoBucketing.Item], count: Int) -> [TodoBucketing.Item]
    enum TodayContent: Equatable { case rows([TodoBucketing.Item]), empty, nothing }
    static func todayContent(todayItems:hasFullAccess:rowCount:) -> TodayContent
    // 无完整授权 / rowCount == 0 → .nothing；放得下且今日 0 条 → .empty；否则 .rows(前 N 条)
}

// DynamicIsland/Modules/Takeover/MusicModule.swift
static var homeBlockWidth: ModuleHomeBlockWidth? { ModuleHomeBlockWidth(min: 240, ideal: 300) }
static var homeFormFactor: HomeFormFactor { .compact }
static let MusicConfigDefaults.showAlbumArt = false               // manifest 节点取同一常量
static func showsAlbumArt(from config: ConfigHandle) -> Bool      // 缺键 → 上面的默认值

// DynamicIsland/components/Notch/NotchHomeView.swift（MusicControlsView 的密度档）
enum Density { case regular, compact }        // 缺省 .regular = 展开面板那一档（逐字不变）
var density: Density = .regular
enum CompactMetrics {                         // 紧凑档六项预算的**唯一取值处**（body / 滑条 / 控制键都从这里取数）
    static let topPadding: CGFloat = 4
    static let titleRowHeight: CGFloat = 17   // 曲名行（1.3 × 13pt 的解析式）
    static let titleSliderSpacing: CGFloat = 4
    static let sliderRowHeight: CGFloat = 34  // MusicSliderView（stacked）的固有高：轨道 14 + 间距 6 + 时间行 14
    static let controlsSpacing: CGFloat = 6
    static let controlsRowHeight: CGFloat = 30   // .medium 档 HoverButton 的边长（播放键同档）
    static var contentHeight: CGFloat            // = 95 ≤ HomeFlowView.compactBlockHeight（96）
}

// DynamicIsland/Modules/Takeover/MirrorModule.swift
static var homeBlockWidth: ModuleHomeBlockWidth?    // min = ideal = HomeFlowView.largeBlockHeight（= 140）

// DynamicIsland/Host/HomeStripView.swift
enum HomeFlowView {
    static func blockHeight(for formFactor: HomeFormFactor) -> CGFloat   // .large → largeBlockHeight；.compact → compactBlockHeight
    static let largeBlockHeight: CGFloat = 140   // 「选定」的档高 = 镜子的方形边长；与 MirrorModule 编译期同源
    static let compactBlockHeight: CGFloat = 96
}
static let minimumUsableHeight: CGFloat = HomeFlowView.largeBlockHeight   // 140（改动前 152 = 音乐封面量出来的，来源已消失）
```

### 设置侧

```swift
// DynamicIsland/components/Settings/ModuleSettingsSection.swift
struct HostSurfaceRow: Identifiable {
    let id: String              // 稳定 id = 上游键名（用例按它反查「键真的在用」）
    let nameKey: String         // 逐字沿用上游设置页那一项的名称字面量
    let symbolName: String      // 取该元素**在面板上**的那一枚
    let key: Defaults.Key<Bool>
}
static let hostPanelRows: [HostSurfaceRow] = [
    ("dynamicShelf", "Enable shelf", "tray.fill", .dynamicShelf),
    ("enableTerminalFeature", "Enable terminal", "apple.terminal", .enableTerminalFeature),
    ("enableClipboardManager", "Enable Clipboard Manager", "doc.on.clipboard", .enableClipboardManager),
    ("enableColorPickerFeature", "Enable Color Picker", "eyedropper", .enableColorPickerFeature),
]   // 四条；排在模块行之后；只有开关、没有 ↑↓；用量不进本节（见 §做法 机制三枚举表）

// 允许清单新增种类（第四种）
enum ModuleConfigControl.Kind { case boolean, number(range:), integer(range:), multiSelect(options: [String], titleKeys: [String]) }
// 唯一的多选条目：moduleID "com.cmeng.gourd.progress" + key "visibleScopes"
//   options = ProgressCalculator.Scope.allCases.map(\.rawValue)（["day","week","month","quarter","year"]）
//   titleKeys = Scope.allCases.map(\.labelKey)；multiSelectEffectiveSet = 模块的公开解析
//   （{ ProgressCalculator.resolveScopes(from: $0).map(\.rawValue) }——卡片勾中的一组 = 块画的一组）
static let minimumOneHintKey = "settings.modules.multiSelect.minimumOne"   // 最后一枚亮着的胶囊：控件上锁，点击照旧发出（写路径拒绝清空）

// DynamicIsland/components/Tabs/TabSelectionView.swift（三个宿主门槛键从裸读改成 @Default 观察）
static let hostPanelGateKeys: [Defaults.Key<Bool>] = [.dynamicShelf, .enableTerminalFeature, .enableClipboardManager]
// DynamicIsland/components/Notch/DynamicIslandHeader.swift（剪贴板图标 / 取色器图标两处）
static let hostPanelGateKeys: [Defaults.Key<Bool>] = [.enableClipboardManager, .enableColorPickerFeature]
// 用例按「hostPanelRows ⊆ 两份名单的并集」这**一个方向**反查（反方向在真实键集上不可达）

// DynamicIsland/DynamicIslandViewCoordinator.swift（宿主元素关掉后把面板收回首页）
struct HostSurfaceGate { let key: Defaults.Key<Bool>; let views: [NotchViews] }
static let hostSurfaceGateViews: [HostSurfaceGate] = [
    .init(key: .dynamicShelf, views: [.shelf]),
    .init(key: .enableTerminalFeature, views: [.terminal]),
    .init(key: .enableClipboardManager, views: [.notes, .clipboard]),   // 面板 tab 走 .notes、刘海图标走 .clipboard
    .init(key: .enableColorPickerFeature, views: [.colorPicker]),
]   // .timer 刻意不在表里（计时器是模块行，收回走既有 handleTimerFeatureToggle）
static func isHostSurfaceGatedOff(_ view: NotchViews, offKeyNames: Set<String>) -> Bool
// 两个入口：四个键的 Defaults.publisher 订阅（已停在被关视图上时收回首页）+ currentView.didSet 守卫（连选都选不上）

// DynamicIsland/ContentView.swift（文件级纯函数，给用例够得到）
func showsPanelResizeHandle(isOpen: Bool, isMinimalistic: Bool, heightMode: String) -> Bool
// = isOpen && !isMinimalistic && !PanelAutoHeight.isAuto(heightMode)
```

### 文案（本批动过的 key，中英双语、`translated`）

- **新增 8 条**：`module.todos.home.empty`（今日无待办 / Nothing due today）、`settings.modules.progress.visibleScopes`（显示的尺度 / Scales shown）、`settings.modules.multiSelect.minimumOne`（至少要留一项不能全部取消 / At least one option has to stay on）、`settings.appearance.panelLayout`（面板布局 / Panel layout）、`settings.appearance.resetLayout`（恢复默认 / Reset to defaults）、`settings.appearance.resetLayout.footer`（一句说清重置什么、不动什么）、`settings.appearance.heightMode.auto` / `.manual`（自适应 / 手动）。
- **改写 4 条**：`module.progress.name`（时间进度 / Time progress）、`module.progress.summary`（时间进度：今天 / 本周 / 本月）、`settings.modules.effect.progress`（不再写「默认今天 + 今年」）、`settings.modules.group.panel.footer`（脚注改成「面板上出现什么」的全量清单口径）。
- **删除 7 条**：`settings.features.title` / `.footer` 与五条 `settings.features.effect.*`（dynamicShelf / enableClipboardManager / enableLockScreenWeatherWidget / enableStatsFeature / enableTerminalFeature）。
- **仍留在 catalog 但不可达**：`settings.features.effect.enableNotes` / `.showCalendar`（孤儿 key，见 §实际交付 遗留项）。

---

## 明确不做

1. **工作日 / 小时口径的进度**（备选 ③）——不引入节假日与调休数据源。
2. **每块的永久卡片底**（备选 ⑤）——宽度预算不够，且 Nook X 本身也不是卡片墙。
3. **面板 tab 的任意排序**（宿主行只给开关）——需要把宿主 tab 也纳入顺序表，本批不做；模块行的排序不变。
4. **整域重置 / 一键清空所有设置**（备选 ⑦）。
5. **折叠态（未展开那条）的高度自适应**——用户说的是展开面板；折叠态宽度/高度仍走既有逻辑。
6. **删掉三环 / 笔记 / 进度展开页的代码**——保留可逆（本项目的既有口径）。
7. **Nook X 的 Free/Pro 门控、AI 对话、启动台双指翻页**——功能面不同，不迁移。

---

## 实际交付

**批线与结构**：2026-09-30 23:28 开工、2026-10-01 凌晨收口；**九任务、四个阶段（三个实现阶段 + 回写）**，实现提交范围 `efecc332..c2949c46`（本地提交，未 push），全量单测 425 → **467 条 0 失败**，改动文件新增编译告警 0。

**D-15 的超限取舍（如实记）**：九个任务超过 8 的惯例上限，按「接受超限」执行——七条反馈是同一次需求且彼此耦合（音乐降档 ↔ 大块档高度 ↔ 自适应高度），拆开要让用户审两遍设计、走两道门；代价是两道门的审阅有效性下降（计划更长、更容易被扫过），用**三阶段 Checkpoint** 补偿：

| 阶段 | 任务 | Checkpoint（控制器核对；证据在 `.workflow/p5-home-blocks/evidence/`，收尾后随 `.workflow/` 消失） |
|---|---|---|
| Phase 1 首页块的内容与尺寸 | T1 待办块 / T2 进度块 / T3 音乐降档 + 大块档高度 | 881×598 实机：待办 = 「今日 0/3 + 细进度条 + 三条今日清单」、无三环；进度默认三行（今天 / 本周 / 本月）、勾「本季」立即多一行并落盘 `visibleScopes`；音乐条进度 + 时间 + 控制三键全在 96 内不裁、默认无封面、封面档是 40pt 小图 |
| Phase 2 设置与面板 | T5 面板组件节宿主行（先）/ T4 撤销功能段（后） | 结构由单测与 review 钉住（组件页只剩两节、四条宿主行的键与「登记 ⊆ 在用」、`featureCards` 一族已删）；**T4 / T5 的命名截图未落进 `evidence/`**（见 遗留项 13） |
| Phase 3 高度与重置 | T6 首页高度算 / T7 其它 tab 上报 / T8 外观页「面板布局」 | T6 由控制器**实机核对**（auto 档窗口 596、manual 598；**日历行回到 AX 树**——36 个日按钮；底部留白 ~300pt → 面板自己的 20pt；右下角把手在 auto 档隐藏）；T7 的判据由 11 条用例钉住；T8 另有三份 `defaults export` 逐键对（清单内 17 键回到改乱前、清单外 7 键未动），截图同样未落进 `evidence/` |
| Phase 4 回写 | T9 本节 + docs/26 / 17 / 20 的改判留痕 | `workflow.py check p5-home-blocks` 零 ERROR + 本文件已无草稿期的占位字样 |

**交付物清单**：

| 类 | 落点 | 交付物 |
|---|---|---|
| 待办首页块 | `DynamicIsland/Modules/TodosModule.swift` | `TodosHomeBlockLayout` 两档行形态 + `rowCount(fittingHeight:)` + `todayContent(...)`；`TodoHomeRingRow` / `ringSpacing` / `ringDiameter` / `listRows(for:)` / `.ringsOnly` 删除；**三环一族（`TodoScopeRing` / `TodoRingPicker` / `TodoRingLayout`）保留、不挂 surface（可逆）** |
| 进度块 | `DynamicIsland/Modules/{ProgressModule,ProgressCalculator}.swift` | 默认三档 `[.day, .week, .month]`；`resolveScopes(from: [String])` 新重载（原 `ConfigValue?` 版转调它）；模块改读 `context.config`；`ProgressHomeBlockLayout` 宽度档 180 + 高度档（14 / 6）；显示名改「时间进度」 |
| 「显示的尺度」多选 | `DynamicIsland/components/Settings/ModuleSettingsSection.swift` | `Kind.multiSelect(options:titleKeys:)`（允许清单第八条）+ `multiSelectEffectiveSet`（卡片与块同源）+ 最后一枚胶囊上锁 |
| 音乐块 | `DynamicIsland/Modules/Takeover/MusicModule.swift`、`DynamicIsland/components/Notch/NotchHomeView.swift` | 宽度 `240/300` + 形态 `.compact` + 封面默认关；`MusicControlsView.Density` + `CompactMetrics`（六项预算 95 ≤ 96）；打开封面画 40pt 小封面（`AlbumArtThumbnailView`，保留 `matchedGeometry` 配对） |
| 大块档高度 | `DynamicIsland/Host/HomeStripView.swift`、`DynamicIsland/Modules/Takeover/MirrorModule.swift` | `HomeFlowView.largeBlockHeight = 140`（唯一字面量）+ `MirrorModule.homeBlockWidth = 140/140`（编译期同源）；`HomeStripView.minimumUsableHeight` 改为引用同一常量 |
| 面板组件节（宿主行） | `ModuleSettingsSection.swift`、`DynamicIsland/components/Tabs/TabSelectionView.swift`、`DynamicIsland/components/Notch/DynamicIslandHeader.swift` | `hostPanelRows` 四条 + 两个消费视图各一份 `hostPanelGateKeys`；三处门槛从裸读改成 `@Default` 观察（拨完当场重绘）；节脚注改成「面板上出现什么」的全量清单 |
| 宿主元素归一化 | `DynamicIsland/DynamicIslandViewCoordinator.swift`、`DynamicIsland/ContentView.swift` | `HostSurfaceGate` / `hostSurfaceGateViews` + 纯函数 `isHostSurfaceGatedOff` + 两个入口（键订阅、`currentView.didSet` 守卫）；拖拽落点接上 `dynamicShelf` 观察 |
| 撤销「功能」段 | `ModuleSettingsSection.swift`、`DynamicIsland/components/Settings/SettingsView.swift`、`DynamicIsland/Localizable.xcstrings` | `featuresSection` / `featureCards` / `FeatureCard` / `FeatureCardRow` 删除 + 7 条 key 删除；锁屏天气那一行加锚常量 `LockScreenSettings.lockScreenWeatherRowKey`（仍是唯一入口） |
| 首页高度（算） | `DynamicIsland/sizing/PanelAutoHeight.swift`（新）、`sizing/matters.swift`、`models/Constants.swift`、`Host/HomeStripView.swift`、`components/Notch/NotchHomeView.swift`、`DynamicIslandApp.swift`、`ContentView.swift` | 纯函数族（见 §接口与数据形状）+ `panelHeightMode` 键 + 读取点落 `openNotchSize` + 五条 publisher 进既有防抖链 + 打开后一拍补推 + auto 档隐藏右下角把手（判据提成文件级纯函数） |
| 其它 tab 高度（量） | `DynamicIsland/Kernel/PanelContentHeight.swift`（新）、`ContentView.swift`、`DynamicIslandApp.swift` | 高度账本（四条款 + 切页声明 + 当班闸门）+ `Layout` 理想高探针 + `objectWillChange` 复用 0.15s 防抖链 |
| 外观页「面板布局」 | `DynamicIsland/components/Settings/SettingsView.swift`、`DynamicIsland/Kernel/PanelLayoutDefaults.swift`（新） | 高度模式两段选择 + 恢复默认（`confirmationDialog` + 一句副标题）+ 17 键清单 + `reset()`（逐键删）+ 滑块按实时模式禁用 + 两条搜索索引 |
| 测试 | `DynamicIslandTests/{ModuleKernelTests,TakeoverEnablementTests,HomeStripLayoutTests,PanelAutoHeightTests,PanelLayoutDefaultsTests}.swift` + `DynamicIsland.xcodeproj/project.pbxproj` | 新增两个测试文件（四处登记），全批净增 42 条用例；关键用例：`rowCount` 四边界、`todayContent` 门控、`resolveScopes` 两条入口相等、多选写路径与卡片/块同源、音乐三个声明值 +「档高 == 镜子方形边长 == 最小可用高」同源、宿主行键解析与「登记 ⊆ 在用」、归一化两个入口、`panelHeight` 四边界 + 收敛往返幂等、`report` 四条款、`resetKeys` 集合相等 + 重置是删不是写、行为护栏 `testAutoPanelHeightLeavesTheHomeTheHeightItsOwnPlanNeeds`（常数缩回 32 → 红） |
| 文案 | `DynamicIsland/Localizable.xcstrings` | 新增 8 条 / 改写 4 条 / 删除 7 条（逐条见 §接口与数据形状） |
| 文档 | `docs/29`（本节与 §接口与数据形状 / §已知限制 / §决策摘要）、`docs/26`、`docs/17`、`docs/20` | 本批的接口、限制、交付与执行期决策；被本批推翻的旧结论就地改判留痕 |

**与计划的偏离及原因**（逐条给理由；「文档写的是预期，代码是真的」）：

1. **高度模式的读取点落在 `openNotchSize`（`matters.swift`），不在 `calculateRequiredNotchSize` 里独占**（计划步骤 3 的字面落点）：`openNotchSize` 是当前展开尺寸的唯一权威源——打开面板那条（`calculateDynamicNotchSize`）与 `ContentView.dynamicNotchSize` 都读它；只改 `calculateRequiredNotchSize` 会让 auto 档**打开面板仍按手动高度画**，而防抖 publisher 只在偏好变化时触发 →「首帧一拍」会变成「一直不贴合」。`calculateRequiredNotchSize` 只改 per-tab 覆盖（走 `mergedTabHeight`）。
2. **其它 tab 的上报方式从 `onGeometryChange` 改成 `Layout` 量理想高**（机制六原文）：那几页根部是 `.frame(maxHeight: .infinity)`，摆放后的高恒等于「面板高 − 表头 − 内边距」，拿它当自然高是反馈环；且 `onGeometryChange` 要 macOS 15，本 target 的 deployment target 是 14.6。
3. **auto 档的覆盖范围是 4/8 页**（计划的验收里写了「切到日历 tab 面板变高」）：日历 / 计时器 / 暂存器 / 终端的自然高是**面板**的函数（日历 `.frame(height: maxTabContentHeight)`，量它每接受一次缩 12pt、一路缩到 130 下限——正是失败信号「切 tab 高度来回跳」），照今天的行为走「回落手动值」；grow 方向由启动台（App 数 → 网格自然高）覆盖。
4. **`NotchHomeView.swift` 未改**（派发片段的文件清单里有它）：首页那条路 T6 已接全（表头高与 hover 判据都由它传给接缝），T7 只换落点（写 → `HomeStripView`、读 → `matters.swift`）。
5. **宿主垂直开销 `homeVerticalPadding` 由 32 改成 40**（T6 评审 P2 先补到 32，实机测量又发现 `NotchLayout()` 里表头↔内容那道缝 8 漏算）：漏算它的后果是首页拿到的 frame 比 plan 的需求短 14pt、**日历行整行被丢**（AX 树 0 个日格）；那道缝因此提成具名常量 `notchLayoutSpacing`。阴影带 18 实测在可见黑框之外，**不计入是对的**。
6. **面板表头高折进「内容高」**（账本值 = 内容 + 表头）：`panelHeight(...)` 的签名里没有表头参数，而表头高随屏 / 配置变（`max(24, effectiveClosedNotchHeight)`）——留成常量会在表头更高的机器上少算，漏算表头是唯一会掉行的方向。
7. **光标规则取粗形态**（`vm.isMouseHovering()` 按当前尺寸判）：精确形态（判断收缩后光标会不会被甩出面板）要再写一份面板几何；§已知限制 1 明确接受粗形态的副作用。
8. **`ContentView` 补「打开面板后一拍再推一次窗口尺寸」**：账本由接缝的 body 写，而打开那条路是「先定尺寸、再渲染」，首开时账本还是 nil（回落手动值）；不补这一拍，auto 档第一次打开就停在手动高度。复用拖动那条实时推尺寸的既有函数，不是第二条 resize 链。
9. **紧凑档音乐条的滑条行取 34**（D-17 写的 28）：紧凑档保留的是同一份 `MusicSliderView` 的 stacked 布局，固有高实测 34（轨道 14 + 间距 6 + 时间行 14），28 只能靠裁 / 压时间行实现——违反 D-17 自己写的「不裁不溢」。
10. **进度块 96 高的行容量是 5 行**（D-04 的「三行填满 96」前提作废）：见 D-20；默认仍是三档。
11. **`resolveScopes(from: [String])` 的调用点带 `?? []`**（文档写的是直传 `get(...)`）：`get` 返回 `[String]?`，直接传会要求一个 `[String]?` 重载，而它会与既有 `ConfigValue?` 版在 `resolveScopes(from: nil)` 上编译歧义；空表分支本来就回落默认，语义等价。
12. **多选控件多了一条 key（`settings.modules.multiSelect.minimumOne`）与一个读侧钩子（`multiSelectEffectiveSet`）**（计划未写）：审查 Important 要求「卡片与块不许分叉」——卡片勾中的一组必须等于块会画的那一组，最后一枚胶囊拒绝写空并上锁显示。
13. **「功能段已删」的判据是替代形态**（计划写的 `featureCards` 解析用例已随表删除）：Swift 里没有断言「类型不存在」的手段，落成「七条 key 从 catalog 消失（打编译产物里的 plist）+ 五张卡的落点逐条钉死」。
14. **页顶提示 `settings.modules.builtinHint` 没有改**（派发说「按新结构重写」）：它在上一批就已改写成指向「首页组件」节，本就不指向功能段；本次只改了代码注释里两处仍说「开关在功能段」的地方。
15. **`XCTAssertDoesNotResolve` 放在既有测试文件里**（不新开文件）：不新增文件就不动 `pbxproj`。
16. **重置取证的偏好域是 Debug（`com.cmeng.gourd.dev`）**（切片写的 Release 域 `com.cmeng.gourd`）：跑测宿主就是 Debug 的 `Gourd.app`；`reset()` 走 `UserDefaults.standard`、与域无关，两档行为逐字相同（脚本头写明 Release 域的跑法）。

**遗留项**（本批明确未做；逐条有出处）：

1. **日历 / 计时器 / 暂存器 / 终端的 auto 高度**（偏离 3）：要补得二选一——由产品裁定「日历的偏好高」，或把 `StandaloneCalendarView` 的 `GeometryReader` + `.frame(height: maxTabContentHeight)` 改成理想高可传播的形态（会改动日历版面，需单独上屏）。
2. **名单内页切页的一次跳动**（§已知限制 3）：消掉它要付出「两次跳动」或「每页存一份量值」的代价。
3. **`Layout` 探针是偏好屏障**（§已知限制 13）：将来给那四页加「往上抛 preference」的机制要连探针一起改。
4. **用量 tab 的老口子**（§已知限制 15）：存量配置里 `enableLLMUsageFeature = true` 的用户看到一个应用内关不掉的 Usage tab。
5. **旧分带渲染器的遗留代码与滞后注释**（T3 不修并留痕，评审接受）：`HomeStripView.minimumUsableHeight` 与 `widgetRowHeight` 已无生产读者（旧分带渲染器 `HomeBandedLayout` / `HomeVerticalFit` 不在生产路径上）；`ModuleTypes.swift` / `GourdModule.swift` 的 `homeBlockWidth` 权威注释仍以「镜子 140/160、音乐 300/420」举例；`HomeVerticalFit.swift` / `HomeStripView.swift` / `FrontAppModule.swift` / `ModuleKernelTests.swift` 里还有把 152 当样本值的注释。
6. **两条孤儿 key**：`settings.features.effect.enableNotes`（笔记的恢复路径从「加回一行」退化成「重建表 + 行」——docs/26 §已知限制 5 已改判）与 `settings.features.effect.showCalendar`（日历行早已改取 `settings.modules.calendarRow.effect`）仍在 catalog 里、不可达。
7. **上锁的那一枚多选胶囊在浅色系统外观下的对比度**没有上屏证据（低置信、视觉项）。
8. **测试内部的一处时序**：测试 `defer` 里先还键后还 `currentView`，排队的 `resetHostSurfaceViewIfNeeded` 会落在还视图之后——需协调器进测试时恰好停在受门控视图上才触发（无生产影响）。
9. **账本侧的「名单外不得接受上报」只由探针门槛保证**（`report` 本身不拒名单外的键，无生产调用点、无测试护栏）。
10. **音乐 40pt 小封面是大封面的裁剪版**：不带角标 / 翻转 / 视差 / 模糊底 / 底光；动态封面在 40pt 上的渲染未验证（§已知限制 12）。
11. **「表头计数」与展开面板「今天」视图的条数可以是两个数**（非缺陷）：首页表头走 `TodoBucketing.Bucket.today`（含今天完成的、含逾期未完成，口径一字不改），展开面板「今天」视图走 `TodoViewKind.today`（只未完成）——默认数据上两者可能不等。
12. **T5 只做了「视图订阅」这半边的即时性**：设置窗与面板同时开着的叠放场景若看到 tab 不消失，说明还有第三条渲染路径没订阅（未复现）。
13. **记账口径的观察**：阶段 Checkpoint 的部分截图只留在了会话里、未全部落进 `evidence/`（T4 / T5 / T7 / T8 的命名截图在目录里缺席；ck1 / T1 / T2 / T3 / T6 与 reset 三份 export 在）——结论已在本节与 §已知限制 记下，证据本身随 `.workflow/` 消失，不影响实现。

---

## 已知限制

1. **自适应高度与 hover 判定共用同一个面板 frame**：内容变矮时若光标停在面板内，面板**不缩**（机制六的边界 ①）。实现取的是**粗形态**——`vm.isMouseHovering()` 按**当前**尺寸判，不预测收缩后的尺寸（精确形态要再写一份面板几何）。副作用：①「把面板从高内容切到矮内容、光标又在面板里」时看起来偏大，移开鼠标下一次重算才贴合；②打开面板时若账本还没有值（首开）、内容又比手动值矮，面板会先按手动高度站着，直到那一拍补推（第 4 条）。
2. **auto 档的高度覆盖是 4/8 页**：只有**待办 / 通知 / 启动台 / 快捷指令**四页上报自然高（它们的自然高是内容条数的函数）。**日历 / 计时器 / 暂存器 / 终端的自然高是「面板」的函数**（量它们 = 把面板高喂回自己：日历每接受一次缩 12pt、一路缩到 130 的下限），因此它们在 auto 档**回落手动值**（滑块高度）——「切到日历面板变高」本批做不到，要补得单独一轮（给日历声明偏好高，或改它的 `.frame(height: maxTabContentHeight)` 结构）。计时器另有 250 的 per-tab 下限兜着。
3. **名单内的页切页有一次跳动**：切到名单内某一页时先留着上一页量出来的值（若切页就清值会「先跳手动值再跳量值」= 两次跳动），新页量完那一拍**无条件覆盖**（`awaitsFirstReport`）。首页那一份是算出来的，不受此影响。
4. **首页在 auto 档仍有「首帧一拍」**：打开面板是「先定尺寸、再渲染」，首开时账本还没有值 → 回落手动高度；那一拍由 `ContentView` 打开后 ~60ms 的补推兜住（复用拖动那条实时推尺寸的既有函数）。
5. **进度块的行数受块高限制**：勾了五档而块放不下时只画**前 N 行**（按声明顺序），**不缩字也不滚动**——与流「装不下就不画」同口径。96 高的块今天放得下五档（行容量 5 是 T2 的改判，见 D-20）；默认三档在 96 高下留白 42pt（观感项，上屏核对过）。
6. **宿主行不参与排序**：面板上它们的先后仍是 `TabSelectionView` 里写死的顺序；只有模块行受 `panelOrder` 控制。
7. **「恢复默认」是布局复位，不是整域复位**：内容类设置（授权、来源、历史、清单）一定不动——刻意的取舍，写在按钮副标题里。另：`openNotchHeight` 的重置**不立即**改窗口（与两个滑块同一条：高度链路的下一次生效点在展开时）——auto 档下看不出差别，手动档要重新展开一次才看到滑块回到 200。
8. **音乐块降档后首页更矮**：块高 152 → 96，auto 档下面板自动收；手动高度模式下会留白——这是用户要的方向。
9. **大块档的高度是「选定的」不是「量出来的」**：镜子的块体没有固有高度（`aspectRatio(1, .fit)`，直径 = `min(宽, 行高)`），档高只能由我们选定——本批取 140（= 镜子的方形边长）。将来给镜子换形态（不再是正方形）或再加一个大块，**必须重新选一个值并把两边一起改**：只改档高会让圆的直径跟着变，只改镜子宽度会让块里留空档。今天大块档只有镜子一个成员。
10. **紧凑档音乐条只剩 1pt 余量**：六项预算合计 95/96（曲名行钉 17、控制行与滑条行都是固定高，余量不随内容浮动）。将来看着挤，第一刀是顶距 4 → 2。
11. **紧凑档的播放键比展开面板小一档**：`.large`（40）→ `.medium`（30）——同一次降档的另一处取舍（「键可以缩，但不另写一套控件」）。
12. **40pt 小封面是大封面的裁剪版**：只取封面来源那一层，不带 `AlbumArtView` 的角标 / 翻转 / 视差 / 模糊底 / 底光（那些是给 133pt 做的，40pt 里读不出也吃宽度）；动态封面（视频）在 40pt 上的渲染未验证。`matchedGeometry` 配对保留（展开后仍是配对目的地，跨度从 133pt 变 40pt，动画观感只能上屏确认）。
13. **测量探针是一个 `Layout`，而 `Layout` 是偏好屏障**：那四页今天都不用 preference；将来给它们加「往上抛 preference」的机制要连探针一起改。探针在 `placeSubviews` 里写账本（布局期副作用）——读者只有 Combine 订阅者（**没有任何视图 `@ObservedObject` 观察账本**）；将来若有视图观察账本，这条副作用会变成视图失效警告。
14. **尺寸层的口径与一处推导常数**：账本值（`current`）的口径是**内容 + 面板表头**（`max(24, effectiveClosedNotchHeight)`）；`panelHeight(...)` 只再加 `homeVerticalPadding`（40）。非首页 tab 的测量值进账本前要按 `measuredContentHeight` **减 16**（首页独有的那一份）——这是推导常数（40 − 24），诊断口径：从首页切到「填满」的页，面板整体跳 16pt = 这个常数错；跳 8 = `notchLayoutSpacing`；跳 4 = 顶出血。
15. **用量 tab 的遗留口子**：`enableLLMUsageFeature` 默认关且应用内无入口（上一批「删页留码」），默认配置下面板上不会出现它；但**存量配置里被拨成 true 的用户**会看到一个在应用内关不掉的 Usage tab。本批不处理（要处理就是删 `TabSelectionView` 那条分支）。
16. **「功能段已删」的自动化判据是替代形态**：Swift 里没有「断言某个类型不存在」的手段——可判定的只有「那条只属于该段的文案 key 从编译产物消失（打 `Gourd.app` 里真实的 plist，实测 ABSENT、非恒真）+ 五张卡的落点各自有生产表断言」。代价：有人把表原样加回来、且不放回任何一行，用例不会红（靠上屏截图与 review）；「视图里真的只剩两节」这一层也没有自动化断言。
17. **宿主行的「真的在用」判据是两份声明**：`TabSelectionView` / `DynamicIslandHeader` 各一份 `hostPanelGateKeys`，用例按「登记 ⊆ 在用」**一个方向**反查——Swift 里没有从 `@Default` 反查键名的公开手段，反方向在真实键集上不可达。代价：声明与门槛 `if` 分处同文件两处，「删了门槛忘改名单」用例抓不到（靠 review 与变异核验）。
18. **账本侧「名单外不得接受上报」只由探针门槛保证**：`report` 本身不拒名单外的键（无生产调用点——探针先过 `isMeasuredTab`），低危、无测试护栏。
19. **两条孤儿 key 仍留在 catalog 里**：`settings.features.effect.enableNotes`、`settings.features.effect.showCalendar`——功能段已删，这两条不可达、未删除（上一批的可逆保留 / 搬家遗留）。
20. **上锁的那一枚多选胶囊在浅色系统外观下的对比度**没有上屏证据（低置信、视觉项；深色外观无影响）。
21. **切到名单外的页会跳到手动高度**（设计口径、非缺陷）：那一拍是「清值 → `current` = nil → 尺寸层回落手动值」，为的是不让日历拿待办量出来的高度画月历。

---

## 验收标准

| # | 判据 | 取证 |
|---|---|---|
| A1 | 首页待办块**只画今日**：表头计数 + 细条 + 今日清单，无三环；今日 0 条时是空态文案 | 单测（`TodosHomeBlockLayout` 行数/裁剪）+ 上屏截图 |
| A2 | 待办清单行数**随块高变**：96 高画 4 行、140 高画更多，且永不超过可用高 | 单测（`rowCount(fittingHeight:)` 边界：0 / 96 / 140 / 非有限） |
| A3 | 进度块默认显示 **今天 / 本周 / 本月** 三行，五档可在组件卡勾选，勾选后**立即**上屏（同一会话内） | 单测（`resolveScopes` 新重载 + 覆盖值优先 + 坏值回落）+ 上屏截图 |
| A4 | ~~勾五档而块放不下时只画前三行~~ **2026-10-01 改判（D-20 / D-21）：勾五档而块放不下时只画前 N 行（N = 宽度档 × 高度档取小者；96 高的块今天放得下五档）**、不溢出 | 单测（渲染行数裁剪） |
| A5 | 「组件」页**没有「功能」段**；统计只有一张卡；锁屏天气卡出现在锁屏页；终端 / 暂存器 / 剪贴板 / 取色器在「面板组件」节且能开关 | 单测（`featureCards` 已删、宿主行表解析键）+ 上屏截图（组件页 + 锁屏页） |
| A6 | 关掉暂存器行 → 面板上的暂存器 tab 消失；开回来即恢复 | 上屏截图（面板 tab 行前后各一张）+ 偏好评据 |
| A7 | 音乐块宽度 ≤300、行高 96、默认无封面；打开封面是 40pt 小图 | 单测（`homeBlockWidth` / `homeFormFactor` / `showAlbumArt` 默认）+ 上屏截图 |
| A8 | 自适应模式下，首页高度 = 算出来的内容高（面板不留大空白）；手动模式行为与改动前一致，且**右下角把手只在手动模式出现** | 上屏截图（两种模式各一张，量面板高度）+ 单测（高度换算纯函数） |
| A9 | 自适应模式下光标在面板内时高度只增不减；per-tab 覆盖值（计时器等）与内容高取 `max` | 人工/上屏（把光标停在面板里切换内容，观察高度不回缩）；单测（`max` 优先级） |
| A10 | 外观页「恢复默认」把 §接口与数据形状 清单里的键恢复到出厂，清单外的键**一个不动**（用 `defaults export` 逐键对） | 自动化（脚本：改乱 → 重置 → `defaults export` diff） |

---

## 决策摘要

| ID | 决策 | 来源 | 理由 |
|----|------|------|------|
| D-01 | 首页待办块**只画今日**（表头计数 + 细进度条 + 今日清单），三环从首页撤销 | 用户 | 用户：「只显示今日的就行，那三个圈不要了」；环是聚合计数、读不出「哪件事该做」 |
| D-02 | 待办清单行数**由块高算**（`rowCount(fittingHeight:)`），不再按块宽分三档 | agent | 块高本批起会变（音乐降档 + 自适应高度），按高度算才不会在小块里溢出 |
| D-03 | 进度 = **自然时间进度**，单位是自然日/周/月/季/年，**不是小时、不是工作日** | 用户 | 用户问「到底用来做什么、什么单位」；自然日历口径零新数据源、与 `Calendar` 一致 |
| D-04 | 进度默认尺度 `[.day, .year]` → **`[.day, .week, .month]`** | agent | ~~三行正好填满 96 高的紧凑块~~ **2026-10-01 改判：96 高的块实际放得下五行（行容量 5 见 D-20），默认仍是三档**；年进度在「本月」之后，用户要看可以勾 |
| D-05 | 进度新增**「显示的尺度」多选**（`configControls` 的新种类），模块改读 `context.config` 覆盖值 | 用户 | 用户：「没地方控制开关」；配置口径早有（manifest 的 `visibleScopes`），缺的是入口与读取 |
| D-06 | 「功能」段**整段撤销**；统计删重复卡、锁屏天气→锁屏页、终端/暂存器/剪贴板→面板组件 | 用户 | 用户原话：「重复了」「开关没什么作用」「锁屏应该在锁屏的菜单里，终端应该在面板组件里」 |
| D-07 | 「面板组件」节 = **模块行 + 宿主行**（四条：暂存器 / 终端 / 剪贴板 / 取色器）；宿主行只有开关、没有 ↑↓ | 用户 | 用户第 4 条；宿主 tab 的先后写死在代码里，给箭头比不给更坏（与首页日历行同先例）；「用量」不进本节——上一批已裁决它无入口、面板上不会出现 |
| D-08 | 面板上**除首页 tab 外，每个 tab 与图标按钮**都必须在「面板组件」节里能关——边界按机制三那张**枚举表**：四个宿主行 + 声明 `.expanded` 的模块行；镜子归首页组件卡、用量不进本节、齿轮与三个状态指示器不算组件开关 | 用户 | 用户原话：「除了首页，都要可以控制开关，是否显示」；枚举是为了让这条断言可判定（「全部门槛键」在真实键集上不可达） |
| D-09 | 音乐块宽度 `300/420`→`240/300`、形态 `.large`→`.compact`、封面默认关 | 用户 | 用户：「音乐占比太大了，要缩小，可以不显示那个图片」 |
| D-10 | 「大块档」高度改成**显式选定的镜子方形边长 140**（不再沿用音乐的 152，也不「实测」——镜子是 `aspectRatio(1, .fit)`、没有固有高度，实测只会量到当前档高），镜子块宽声明同步收敛为 `140/140` | agent | 152 是从音乐封面量出来的，音乐降档后这个数的来源消失；圆的直径 `= min(宽, 行高)`，档高与块宽必须同源，否则要么圆被行高卡住、要么块里留空档 |
| D-11 | 新增 `panelHeightMode`（auto 默认 / manual）；auto = 内容自然高 + 内边距，夹在既有高度区间 | 用户 | 用户第 7 条；上界复用 `effectiveOpenNotchHeightUpperBound`，不另立一套 |
| D-12 | 首页高度**算**（流方案直接给），其它 tab **测量**（8pt 滞回）；光标在面板内时不缩 | agent | 算的精确无跳动；测量有抖动风险，靠滞回与「不缩」两条边界兜住 |
| D-13 | 外观页新增「恢复默认」：只重置**布局与显示**键（清单唯一），不动内容/授权类 | 用户 | 用户：「改完后想换回来，可以在外观的地方重置为系统默认」；整域重置会丢用户的东西 |
| D-14 | 「Nook X 效果」取三条原则（一块一件事 / 块形随内容 / 面板贴内容），**不抄皮肤、不做每块卡片** | 用户 | 用户：「不是照抄，是考虑怎么在现在的功能基础上实现类似的效果」；卡片宽度预算不够（[26](26-home-widgets-and-settings.md) D-10） |
| D-15 | **接受超限**，九任务一个工作流（超过 8 的惯例上限） | agent | 七条反馈是同一次需求且彼此耦合（音乐降档 ↔ 大块档高度 ↔ 自适应高度），拆开要用户审两遍设计、走两道门；代价 = 两道门的审阅有效性下降（计划更长、更容易被扫过），用三阶段 Checkpoint 分段核对补偿 |
| D-16 | auto 模式下**隐藏右下角拖动把手**（把手 = manual 专属）；auto 下 per-tab 覆盖值与内容高取 `max` | agent | 拖动写的是 `openNotchHeight`，auto 下它当场没有效果——留着手把就是本仓明确规避的「拖了没用」（`ContentView` 极简模式隐藏把手是同一条先例）；覆盖值是下限不是上限 |
| D-17 | 紧凑档的音乐块要**自己的密度**：紧凑档只画「曲名（单行截断）+ 进度条 + 控制三键」，**艺人行 / 歌词行 / 大内边距留给展开面板**；`MusicControlsView` 加一个密度参数（默认标准档，展开面板逐字不变）而不是在模块里另写一套控制条 | agent | T3 阶段 Checkpoint 上屏实测：标准档内容 ≈127pt（10 顶距 + 17 曲名 + 17 艺人 + 41 滑条 + 8 间距 + ~30 控制），96 的紧凑档里**控制三键整行被裁**（AX 有元素、屏上没有）——这是 D-09「音乐降到紧凑档」与「保留曲名/艺人/进度/控制四件套」在 96pt 里不可能同时成立；另写一套控制条会让「音乐控制键」有两份实现，故用密度参数 |

### 执行期判断（2026-10-01 回写，D-18 起续号）

> 来源都是 `agent（执行期）`：每条由实现者提出、控制器裁决接受（账本 `.workflow/p5-home-blocks/ledger.md` 的裁决区记着拍板时间；本节记结论、理由与代价）。**过程记录不在这里，这里只留半年后还要读的结论。**

**首页三块（T1 / T2 / T3）**

| ID | 决策 | 来源 | 理由与代价 |
|----|------|------|------|
| D-18 | 待办清单的间距口径：`listSpacing = 4`（表头↔清单一段）、清单**行间 spacing = 0**、行高由行视图自己钉在 `rowHeight`（16） | agent | 文档算式只扣**一段** spacing；取 4 后 96 高 → 4 行、140 高 → 7 行，与验收「96 高画 4 行」一致；行间再留间距就会超出算式给的可用高（最后一行被裁）。代价：观感上行距比旧版（清单 `VStack(spacing: 4)`）紧 |
| D-19 | 「表头之下画什么」抽成纯函数 `TodosHomeBlockLayout.todayContent(todayItems:hasFullAccess:rowCount:)`：无完整授权 → `.nothing`；`rowCount == 0` → `.nothing`；放得下且今日 0 条 → `.empty` | agent | `store.items` 空是「读不到」不是「今天没事」——画「今日无待办」是正面假断言；块矮到一行都放不下时画空态行会溢出（与清单行同高）。行为契约散在视图里只能靠上屏看，抽成纯函数才钉得住。代价：`TodosHomeBlockLayout` 比文档多一个 `TodayContent` 与 `todayContent`（已回写）；折叠态 / 展开 tab 的未授权表现仍是它们自己那套（三处口径未统一） |
| D-20 | 进度块 96 高的**行容量取 5 行**（`rowHeight = 14` / `rowSpacing = 6` / `barHeight = 6`）；**D-04 的「三行填满 96」前提作废** | agent | 计划的预期之一是「勾上本季后立刻多一行」，而 96 高只放得下三行时勾第四档屏上没变化（正是失败信号「勾了没反应」）；14 = 实测的行自然高、6 = 与行高配合让五行装进 96、条高 6 = 把 `.linear` 的 20 压成细条。代价：默认三档在 96 高下留白 42pt（观感项）；文档旧例「只画前三行」改成「只画前 N 行」 |
| D-21 | 进度块宽度档门槛 `twoRowWidth = 220` → **`allScopesWidth = 180`**（= 模块声明的最小宽），删 `twoRowWidth` | agent | 实测宿主真分配的宽度是 **180.5…240**，旧门槛 220 在多数面板宽下会把块压成 1–2 行（默认三档都上不全）；宽度不是行数的真实约束（一行固定宽 ≈96pt），真正的刹车是高度档。代价：≥180 的档位内宽度不再限制行数——将来要「窄块少画」是另一条决策 |
| D-22 | 进度块的行内标签加 `.fixedSize()`（挤的是进度条，不是尺度名） | agent | 不加时 180 宽的英文块把「This month」显示成「This mo…」（正是失败信号「块内被裁出半个字」）；与展开行 `ProgressScopeRow` 的标签口径一致。代价：退化窄块（<140）里进度条被压得很短 |
| D-23 | `module.progress.summary` 只写出厂三档（放弃机制二「简介保留五档说法」）；顺手改 `settings.modules.effect.progress` | agent | 裁决要求「简介不再承诺块做不到的事」；旧 effect 文案「默认今天 + 今年」在默认被改后是**事实错误**。代价：卡片上不再一眼看出「还有本季 / 今年」（那排胶囊就在同一张卡上，比简介更直接） |
| D-24 | `ProgressModule.scopes` 由 `private` 改成 internal | agent | 单测要在假句柄与真句柄上钉「覆盖值优先 / 坏值回落」（同 `Scope.symbolName` 的既有口径）。代价：模块层多一个可被同文件读到的属性 |
| D-25 | 多选控件**读侧接模块的公开解析**（`multiSelectEffectiveSet` → `ProgressCalculator.resolveScopes(from:)`），最后一枚亮着的胶囊**拒绝写空**（控件上锁显示、点击照旧发出） | agent | 审查 Important：空表 / 全坏值时卡片与模块会分叉（卡显示「一个都没勾」而块画三行）；不写空表再靠模块回落会让那一次点击上再分叉一次。代价：多一枚 key（`settings.modules.multiSelect.minimumOne`）、一个只被视图与用例引用的钩子；上锁态的浅色外观对比度未上屏 |
| D-26 | 大块档档高的**唯一字面量**放宿主 `HomeFlowView.largeBlockHeight = 140`，模块侧 `MirrorModule.homeBlockWidth` 直接引用它 | agent | 宿主本来就是「形态 → 档高」表的持有者，且它全程 registry 驱动（反方向 = 宿主引用模块类，会破层向）；模块引用宿主常量在本仓有先例（`FrontAppModule` → `HomeBandChrome.hoverCornerRadius`）。「改一处两边跟着改」因此是**编译期**保证，不只是注释约定。代价：`MirrorModule` 与宿主视图常量产生编译期耦合（将来拆 target 要把常量提到中立处）；`ModuleHomeBlockWidth` 的语义从「登记被接管块原本的宽度」变成「派生自档高」 |
| D-27 | `HomeStripLayoutTests` 的「四块宽度样本」**保留旧值**（音乐 300/420、镜子 140/160），只在注释里写明「样本不是生产声明的真源」 | agent | 等比压缩那条用例要求样本每块都有可压缩量（`min < ideal`），140/140 会让「各块让出的比例一致」变成 0/0（NaN 断言必红）；尺寸反馈那一族的宽度阶梯按 300/420 设计，换 240/300 会让三档塌成 3/4/4。生产声明改由模块用例与新增的同源用例钉死。代价：测试文件里仍留着两个旧数字，评审时容易被当成漏改 |
| D-28 | 40pt 小封面：**保留 `matchedGeometry` 配对**；只取封面来源层（不带角标 / 翻转 / 视差 / 模糊底 / 底光）；圆角借 `HomeBandChrome.hoverCornerRadius`（8） | agent | 删配对等于静默砍掉一个既有动画；那些装饰是给 133pt 大封面做的，40pt 里读不出也吃宽度；圆角不新立数值，与块内既有 8pt 同一条。代价：与大封面相比少了角标；动态封面在 40pt 上的渲染未验证；配对两端跨度从 133pt 变 40pt（动画观感只能上屏确认） |
| D-29 | 紧凑档的滑条行取 **34**（D-17 写的 28 作废） | agent | 紧凑档保留的是同一份 `MusicSliderView` 的 stacked 布局，固有高实测 34（轨道 14 + 间距 6 + 时间行 14），28 只能靠裁 / 压时间行实现——违反 D-17 自己写的「不裁不溢」；改成 `.inline` 布局能压到 ≈16，但会改掉「时间在条下」的观感。代价：整条 95/96，只剩 1pt 余量（要腾空间第一刀是顶距 4 → 2） |
| D-30 | 紧凑档的播放键从 `.large`（40）降到 `.medium`（30）——仍走同一份 `slotView`，只换既有参数 | agent | D-17 明确「键可以缩，但不另写一套控件」；`HoverButton` 的尺寸由 `scale` 决定。代价：播放键图标从 `.largeTitle` 降到 `.body`，视觉上小一档（上屏判过） |

**设置与面板（T4 / T5）**

| ID | 决策 | 来源 | 理由与代价 |
|----|------|------|------|
| D-31 | 「功能段已删」落成「**七条 key 从 catalog 消失 + 五张卡落点逐条钉死 + 锁屏页那一行是唯一入口**」 | agent | Swift 里没有断言「类型不存在」的手段（`#if` 判不了符号，反射判不了未定义的 `struct`，源文件扫描在本仓没有先例）；负向断言打的是 `Gourd.app` 里真实编出来的 plist（实测 ABSENT、非恒真）。代价：「视图里真的只剩两节」这一层无自动化断言；有人把表原样加回来且不放回任何一行，用例不会红 |
| D-32 | 锁屏天气那一行的锚取生产常量 `LockScreenSettings.lockScreenWeatherRowKey`，且行内真的用它 | agent | 判据要落在「那一行」上就得有一个生产侧对象可指（与 `HomeCalendarSettingsRow.nameKey` / `hostPanelRows` 同族）。代价：为一个用例在生产代码里加了一个常量；删掉整行时常量变成无人使用（用例仍绿） |
| D-33 | `hostPanelRows` 的「真的在用」= **两个消费视图各一份 `hostPanelGateKeys` 声明**，用例按「登记 ⊆ 在用」一个方向反查 | agent | Swift 里没有从 `@Default` 反查键名的公开手段（`Defaults.Default.key` 是私有 stored property），源文件文本扫描在本仓没有先例；把「本视图真的读哪几个键」写成声明、读取点在同文件一屏可及，是能落成断言的最诚实形态。代价：声明与门槛 `if` 分处同文件两处，「删了门槛忘改名单」用例抓不到（靠 review 与变异核验） |
| D-34 | 宿主行的**图标取该元素在面板上那一枚**（`tray.fill` / `apple.terminal` / `doc.on.clipboard` / `eyedropper`） | agent | 这一行管的就是面板元素，用户拨完开关看的是面板（暂存器在面板上是 `tray.fill`，上游设置页侧栏是 `books.vertical`）——两块信息里名称已定死「认上游那一页」，图标选「认面板」。代价：同一个功能在设置页两处图标不同，并看时会以为不一致 |
| D-35 | 面板组件节的脚注把枚举**说全**（四条宿主行 + 模块行 + 其余元素归属逐类列出，含「用量默认关、面板上不会出现」） | agent | 用户第 4 条的原话就是「除首页外都要能控制开关」，脚注不写其余归属用户会以为漏了（镜子 / 齿轮 / 指示器在别处各有开关）。代价：中英两值都变长（en 285 → 792 字符），脚注在小窗口占 5–6 行 |
| D-36 | 宿主元素关掉后的归一化做**两个入口**：键变化订阅（已停在被关视图上时收回首页）+ `currentView.didSet` 守卫（连选都选不上）；**`.timer` 刻意不进表** | agent | `openShelfByDefault` 与剪贴板快捷键会在**不看门槛键**的情况下把面板开到 `.shelf` / `.notes`，只订阅键变化的话「打开面板就跳到一个已经关掉的元素上」这条还在；计时器是模块行、收回走既有的 `handleTimerFeatureToggle`，进表会与那条重复（`.timer` 可停留是别的用例依赖）。代价：`.notes` / `.clipboard` 被守卫后，剪贴板功能关着时那条快捷键变成空操作（原来是硬开一个已关功能的面板） |

**高度自适应（T6 / T7）**

| ID | 决策 | 来源 | 理由与代价 |
|----|------|------|------|
| D-37 | 内容高探针用**内容自然高**（按 `naturalFlowBudget` 预算跑一份流方案），**不是**按当前面板高跑一次流方案 | agent | 流方案在预算里装不下的行会**整行丢掉**，拿它当内容高就是单向棘轮（面板越小 → 丢的行越多 → 算出的内容高越小 → 面板再缩，最后停在「一行都不画」的不动点）；块高是声明值，自然高本来与预算无关。代价：`contentHeight` 闭包在首页这一路是常量探针（接口形状留给测量账本用） |
| D-38 | 面板表头高折进「内容高」（账本值 = 内容 + 表头），`panelHeight(...)` 只加 `homeVerticalPadding` | agent | 表头高随屏 / 配置变（`max(24, effectiveClosedNotchHeight)`），而 `panelHeight(...)` 的签名里没有表头参数；留成常量会在表头更高的机器上**少算**——漏算表头是唯一会掉行的方向（后果是最后一行被整行丢掉）。代价：账本值的语义是「内容 + 表头」（注释与 §已知限制 14 写明） |
| D-39 | 高度模式的**读取点落在 `openNotchSize`**（`matters.swift`），`calculateRequiredNotchSize` 只改 per-tab 覆盖 | agent | `openNotchSize` 是「当前展开尺寸」的唯一权威源（打开面板那条与 `ContentView.dynamicNotchSize` 都读它）；只改 `calculateRequiredNotchSize` 会让 auto 档打开面板仍按手动高度画，而防抖 publisher 只在偏好变化时触发 →「首帧一拍」会变成「一直不贴合」。代价：与计划步骤 3 的字面落点不同（`calculateRequiredNotchSize` 只是经它间接读） |
| D-40 | 光标规则取**粗形态**（`vm.isMouseHovering()` 按当前尺寸判），不用「收缩后光标会不会被甩出面板」的精确形态 | agent | 精确形态要自己再写一份面板几何（`isMouseHovering` 不认收缩后的新尺寸）；§已知限制 1 明确接受粗形态的副作用。代价：展开时鼠标就在面板里也会拦住收缩（首开时若账本还是 nil、内容又比手动值矮，面板会先按手动高度站着） |
| D-41 | `heldForPointer` 把「不缩」表达成「面板高不低于当前值」，写回账本时按同一条换算减去内边距 | agent | 尺寸层读到的是「内容高」再加内边距还原面板高，「不缩」的结论必须按同一条换算写回去；种子取权威值后**往返幂等**有用例钉住。代价：被按住的那一拍账本值大于真实内容高（差额 = 留着的那点空白），语义靠注释兜 |
| D-42 | 打开面板后**一拍再推一次窗口尺寸**（复用既有 `syncWindowSizeAfterPanelResize`） | agent | 账本由接缝的 body 写，而打开那条路是「先定尺寸、再渲染」，首开时账本还是 nil（回落手动值）；防抖 publisher 只在偏好变化时触发、打开面板不是偏好变化——不补这一拍，auto 档第一次打开就停在手动高度。代价：与「不新开第二条 resize 链」在字面上有张力（补的是一个**触发器**，链路仍是既有那条）；打开后 ~60ms 有一次尺寸贴合 |
| D-43 | 宿主垂直开销 = **40**（四项逐项求和 16 + 12 + 4 + 8，每项带出处；阴影带 18 与面板外的顶出血 4 刻意不计） | agent | T6 评审 P2 补齐两处内边距后仍差 14pt，实机测量发现 `NotchLayout()` 里表头↔内容那道缝（平台默认 8）漏算——它落在可见黑框以内、消耗首页可用高，后果是日历行整行被丢；实测确认 18 在可见黑框之外（窗口 588 = 黑框 570 + 18），折进来就是双重计数。代价：40 是「零富余」的等式解（闭区间判据下日历行仍画），面板底部可见留白只剩 20pt；改任何一个数都要连预算一起改 |
| D-44 | 其它 tab 的量法用 `Layout` 量**理想高**（`.unspecified` 提案），**不用** `onGeometryChange` | agent | 那几页根部是 `.frame(maxHeight: .infinity)`，摆放后的高恒等于「面板高 − 表头 − 内边距」——拿它当自然高是反馈环；且 `onGeometryChange` 要 macOS 15，本 target 的 deployment target 是 14.6。代价：探针是一个 `Layout`（**偏好屏障**，见 §已知限制 13），且在布局期写账本 |
| D-45 | 覆盖名单 = **待办 / 通知 / 启动台 / 快捷指令**四页；日历 / 计时器 / 暂存器 / 终端**不上报** | agent | 后四页的自然高是**面板**的函数（日历 `.frame(height: maxTabContentHeight)`，每接受一次缩 12pt、一路缩到 130 下限——正是失败信号「切 tab 高度来回跳」）；名单外不写值 → 回落手动值。代价：计划验收里的「切到日历 tab 面板变高」本批做不到（grow 方向改由启动台覆盖） |
| D-46 | 条款顺序：**换 tab 无条件接受** 判在 **光标在面板内只增** 之前 | agent | 用户点 tab 时手必然停在面板里——若光标规则也管换 tab，面板永远等不到「变矮」那一拍（预期里「切到待办面板变矮」直接不成立）。条款 ④ 的适用范围因此是**同一 tab 内的内容微动**。代价：两条规则的先后要读出来才完整（注释与用例各写了一遍） |
| D-47 | 加一道**「当班」闸门**（`isCurrent`）：挡住切 tab 那 0.3s 里还活着的旧页 | agent | transition 期间旧页仍在被重新布局，它一上报就是「换 tab」→ 无条件接受 → 账本被旧页抢回去 → 面板在新旧两页之间来回跳。代价：`report` 的语义里多一维「页是否当班」，账本与调用点要一起读 |
| D-48 | 测量值进账本前**减 16**（`homeOnlyVerticalPadding` 的推导值） | agent | 尺寸层只有一条换算（面板高 = 内容高 + 40），而首页独有 `NotchHomeView` 的 8 + 8；要让「整页填满」量完不动（不动点）、内容短的页贴合，测量值必须 −16。代价：推导常数，要实机核对（诊断口径见 §已知限制 14） |
| D-49 | 账本对「首页那一份」**不发通知**（只写槽）；测量那一份才发 | agent | 首页已有五条 publisher + 打开后一拍接进 resize 链，再响一次就是第二条 resize 链；测量那份没有别的触发器。代价：谁改首页内容谁负责触发（与 T6 同责，链的注释里写明） |
| D-50 | 探针的宽度按**面板给的那个格子**（`bounds.width`）、高度留 `.unspecified` | agent | 宽度自适应的页（启动台的 adaptive 网格）在没有宽度的提案下会按单列算，自然高被高估到几百行、把面板顶到 850（用例实测：700 宽 116 / 300 宽 212，差 96）。代价：提案要分两维说清（渲染仍是逐字转发） |
| D-51 | `setHomeContentHeight` 只写自己那个槽；「当前是哪一页」只由 `selectTab(_:)` 定 | agent | 切 tab 的过渡里还活着的首页再跑一次 body 会把刚量完的模块页顶掉；比再加一个 `isCurrent` 参数更省一处状态，且与模块侧的闸门同源。代价：写入方（视图 body）与「当班」声明分处两处，要一起读才完整 |

**外观页与重置（T8）**

| ID | 决策 | 来源 | 理由与代价 |
|----|------|------|------|
| D-52 | `PanelLayoutDefaults.resetKeys` **逐项取强类型键的 `.name`**，不写字面量字符串表 | agent | 键改名 / 被删时编译期就断，清单不会与 `Defaults.Keys` 悄悄漂移；对外仍是文档那 17 个键名（用例逐字钉着，两边任一漂移都红）。代价：代码里是 17 行 `.name` 取值，读起来隔了一层 |
| D-53 | 重置用库自身的 `Defaults.reset(_:)`（逐键 `removeObject`）——**不是** `removePersistentDomain`、**也不是**写默认值 | agent | 与 `@Default` / `Defaults.publisher` 读的是同一层（KVO），重置会走既有订阅链（面板尺寸 / tab 名单跟着重算）；「未设置 = 出厂默认」由库保证；写一个等于默认值的值会让「盘上有没有这个键」不可判（与用户的显式选择同形）。代价：没有「删键后重写一份显式默认」的余地（本仓不需要） |
| D-54 | `expandHeightSliderEnabled(heightMode:)` 提成 `PanelLayoutDefaults` 上的**可测契约**（视图只调用它） | agent | 外观页整页在单测里搭不起来（与 T6 把把手判据提成 `showsPanelResizeHandle` 同一条先例）。代价：多一个只被视图与用例引用的函数（已回写进 §接口与数据形状） |
| D-55 | 高度模式选择器是**无可见标签的 segmented**（标签取本组标题，`labelsHidden` + `accessibilityLabel`）；**未知存量值下两段显示「自适应」**（绑定归一化） | agent | 裁决给的 5 条新 key 里没有「高度模式」行标签的文案，两个分段自己就是文案，不再新增第 6 条 key；`panelHeightMode` 是裸字符串键、尺寸层对未知串按 auto——界面若显示「两段都没选中」就与行为对不上。代价：组的可读性靠标题与位置（观感靠截图）；控件不再逐字显示盘上的原始串（用户点一下即写回合法档名之一） |
| D-56 | 外观页的两处「顺手」：搜索索引加两条（"Panel height mode" / "Reset panel layout"，含中文关键词）；「清单外」护栏多钉 `ColorPickerHistory` / `ScreenAssistantFiles` 两键 | agent | 外观页其余控件都在搜索表里，新组的两个控件不登记就是搜不到的死角；两个历史键与剪贴板历史同一条判据（内容类，丢了就是丢东西），且在同一偏好域里、是真会被误伤的那一类。代价：动了同文件的搜索表（越出「只加一组控件」的字面范围，删掉那两行即回退）；比文档多钉两个键（只在用例的护栏清单里，不改生产行为） |
