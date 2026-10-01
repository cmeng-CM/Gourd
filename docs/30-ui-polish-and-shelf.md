# 首页样式、架子与面板高度的一批修正（p6）

| 项 | 值 |
|---|---|
| 状态 | **已实现**（工作流 `p6-ui-polish` 12 任务，2026-10-01 一天内完成；实现提交范围 `b4b1034e..a8e811c4`，回写提交紧随其后） |
| 最后更新 | 2026-10-01 |
| 关联来源 | [29](29-home-blocks-and-panel.md)（p5：首页块 / 组件页 / 高度自适应，本批的起点）、[26](26-home-widgets-and-settings.md)（D-10「不做每块卡片」、侧栏分组口径）、[16](16-nookx-reference.md) §5（Nook X 三原则）、[21](21-strip-honesty.md)（丢块契约）、[28](28-home-layout-redesign.md)（单条流） |

> **怎么读**：§背景与目标 / §明确不做 / §备选与取舍 是这场改动的判断依据；
> §接口与数据形状 是参考型小节（执行者与机器查考），人审可跳过；
> §已知限制 / §实际交付 是留给后来人的。

**读者分界**：§背景与目标·§备选与取舍·§明确不做 给人读；§做法与§接口与数据形状 是给执行者与模型的契约，写死到不再需要设计决策。

---

## 一句话方案

一批十项的用户可见修正：**首页每块加「浮起」样式**（常驻软阴影 + hover 放大/提亮，不加卡片底与边线）并把整条带的大底撤掉、**音乐块再缩宽**（200/250 档）、**通知面板字号整体 +1~2pt**；**架子**统一命名「隔空投送与文件暂存」、修好 ✕ 点不动的命中区、把左投送块缩成一枚小投放格并让文件区变成全宽多行网格；**面板高度切换**改为单步动画（窗口动画 + 每页高度缓存 + 启动台就绪前不塌陷）；**日历**按当月实际周数取高（首页行 ~~36N+78~~ **2026-10-01 T8 校准改判：36N+52（见 D-23）**、日历页自然高并进测量名单），首页底部留白随之收敛（实测 89 → 28）；**架子/终端/剪贴板**三个宿主 tab 并入排序设置；**空闲动画**修掉上游回归并让它按设置生效；**设置侧栏「组件」**移入「媒体与显示」分组。

## 背景与目标

### 触发

用户 2026-10-01 第二轮十条反馈（附 8 张截图）：

| # | 反馈（要点） |
|---|---|
| 1 | 首页每个内容没有任何区分；**不加区域块与边线**，加样式（3D / 阴影 / 浮动之类），要「查下什么合适」 |
| 2 | 首页音乐播放宽度可以进一步减小 |
| 3 | 架子：①为什么叫「架子」而不是「隔空投送和文件暂存」②点文件右上角 ✕ 不能从暂存区删除 ③左侧只放投送却占半屏，布局参考 Nook X（小投放格 + 全宽网格） |
| 4 | 消息（通知）面板字体太小 |
| 5 | 从窄的状态切到启动台高度不够；当前高度设置在不同面板切换时有卡顿 |
| 6 | 日历面板组件的高度为什么这么高 |
| 7 | 首页底部也有留白，是做什么的 |
| 8 | 「启用架子」及后面几个面板组件不在排序设置里 |
| 9 | 空闲动画设置不生效 |
| 10 | 「组件」设置在菜单里的位置放到「媒体与显示」模块 |

### 现状与问题（逐条给代码定位；实机观察 2026-10-01）

1. **块无区分**属实：`HomeStripBlock` 只有 `.clipped()`（`DynamicIsland/Host/HomeStripView.swift:264-281`），块壳无背景/圆角/阴影；唯一的面样式是**整条流共用一个**淡底（`homeBandContainer()`，白 0.05，T8 引入）。块级 hover 只覆盖三种行级元素（待办行 / 通知行 / 前台格），观感上「所有内容糊在一个大盒子里」。可复用的既有素材：面板级阴影（`ContentView.swift:858-864`）、`LiquidGlassBackground`、悬浮先例（`NotchColorPickerView.swift:220-222`、`NotchStatsView.swift:506-507`）。
2. **音乐块**声明 `240/300`（`MusicModule.swift:182`），紧凑控制行 5 键硬编码为 `5×30 + 4×8 = 182pt`（`HoverButton` `.medium`=30），封面开着时再吃 48（用户配置 `showAlbumArt = true`）→ 距声明的 min 240 只剩 10pt 余量；不开封面对比才宽松。
3. **架子**：代码名 Shelf，视图 `HStack{ FileShareView().aspectRatio(1,.fit); 文件区 }`（`components/Shelf/Views/ShelfView.swift:63-65`）；左投送块是**受高限制的正方形**，887 宽面板下实测约 445pt（半屏）；文件区是**单行横向 ScrollView**（不换行）。同一功能三个中文名并存：「启用架子」（设置行）/「暂存器」（侧栏、页标题）/「搁板」（`Open shelf tab by default…` 的译文），另有 4 条用户可见文案无中文（显示英文）。截图里的「System Share Menu」是**供应商 id 的回落硬编码英文**（`FileShareView.swift:43-45`、`QuickShareService.swift:136-138`）。
   - **✕ 删除 bug 的根因（本地同构复现已证实）**：✕ 画在 cell 内容右上，但 `DraggableClickHandler`（无 `sizeThatFits` 的裸 NSView，`ShelfItemView.swift:365-383`）吃掉了**整个 HStack 分给该 cell 的槽位**（宽=均分/理想宽、高=容器全高）；它的 `hitTest` 只让出**自己**右上 30×30。两者不是同一个 frame → 点在 ✕ 上实际落到拖拽视图 → `mouseUp` → `onClick` → 只 `selectSingle`（看上去「没反应」；点两下则走双击打开文件）。
4. **通知页**字号：模块名 12 / 标题 11 / 正文 10 / 时间 10 / 脚注 9（`Modules/NotificationsModule.swift` 内 11 处 `.system(size:)` 字面量），行内无固定行高、放大不受布局挡。**执行期**：展开页共 17 处字面量全数收进 `NotificationRowMetrics`（11 主项 + 6 状态项），见 §接口 机制四。
5. **高度切换**链：点 tab → `updateWindowSizeForTabSwitch`（`animated:false`）读账本**旧值**推一次 → 新页布局后探针上报 → 0.15s 防抖 → 第二次推。窗口侧**没有任何动画**（`resizeWindow` 的 `animated` 形参从未使用、`animationBehavior = .none`，`DynamicIslandApp.swift:618-642`），内容侧 0.3s 动画 → 观感是容器「啪」一下、内容还在路上。实测（通知页切换）：~0.9s 时窗口已 872 高而可见面板仍在 ~690，~2.4s 才贴合。**启动台首开还有三拍**：`store.load()` 前 `apps` 空 → 画 `.noApps` 占位（自然高 ~110）→ 首报无条件接受 → 面板先缩到 ~150 再长回去。
6. **日历页**不在测量名单（`PanelContentHeight.measuredTabs` 只有 待办/通知/启动台/快捷指令）→ auto 档回落**手动值**（本机 682），而页面内容 ~300 → 实测空白 ~380pt；这是 p5 已知限制 2/21 的既定缺口，本次补齐。
7. **首页底部留白**（实机测量）：auto 档面板 618 高、日历网格最后墨迹在 532 → **留白 89pt**；其中设计值只有 20（= 首页 padding 8 + ContentView 底 12），其余 ~69 来自日历行**固定 294**（按 6 周最坏月定，而 2026 年 10 月只有 5 周，公式 `36N+78` 下 5 周只需 258）。手动 682 档下留白 128pt（手动高度本身）。
8. **排序**：四个宿主行只有开关、无 ↑↓（p5 D-07 的刻意裁决）；tab 顺序写死在 `Tabs/TabSelectionView.swift:74-108`（Home → Shelf → Usage → Clipboard → Terminal → 扩展 → 模块），模块 tab 的序由 `panelOrder` 消费（`Kernel/ModuleRegistry.swift:394-426`）。设置页顺序（暂存器/终端/剪贴板/取色器）与面板实际顺序（…/剪贴板/终端）也不同。
9. **空闲动画**根因（决定性）：上游提交 `f9ad0282` 在动画分支前插入了一个**空体分支**（`ContentView.swift:1702`，条件恰是「面板关闭且无 expansion」这一正常情形）→ 动画分支（`:1703`，要求 `!isCurrentScreenExpansionVisible` 与空分支同义）实际不可达。另有次要因素：动画分支排在**架子行内**（`:1694`）与**模块折叠槽**（`:1697`，p5 新增）之后，本机（架子有 1 个文件、待办默认开）即便修好空分支也轮不到它。
10. **设置侧栏**：「组件」页挂在 `.integrations`（`SettingsView.swift:110`「扩展/组件同类必须相邻」是 docs/26 时期的口径），要移入 `.mediaAndDisplay`。

### 承接关系与目标

- **承接**：`docs/29`（p5 交付的组件页结构、高度自适应账本、音乐降档——本批在它们之上改）；`docs/26` D-10「不做每块卡片」的原因（宽度预算）**继续成立**，本批的样式走「不加卡片底」的浮起式；`docs/16` §5 的 Nook X 三条原则继续是设计语言来源；`docs/28` 单条流骨架不动。
- **本批改判**（就地留痕，见回写任务）：`docs/29` D-07 / 明确不做 3 / 已知限制 6（宿主行不参与排序 → 参与）；`docs/29` §已知限制 2 与 D-45 / §遗留 1（「日历/计时器/暂存器/终端不上报」——**暂存器与日历本次已进测量名单**，计时器/终端仍不上报）；`docs/29` T8 引入的「整条带共用一个大底」→ 撤掉；`docs/26`「扩展/组件必须相邻」→ 组件移入媒体与显示。
- **目标**：十条反馈各有可上屏核对的落点；auto 档下首页/日历/启动台的贴内容问题收敛；面板高度的两类跳变消失；两处既有 bug（✕、空闲动画）有回归测试或上屏证据。

## 做法

### 机制一 · 首页块「浮起」（第 1 条）

**研究结论**（2026-10-01，HIG/Liquid Glass 与同类应用现状）：Apple 当前的设计语言把层级表达为「界面元素**浮起**并区分其下内容」（HIG iOS 26 原文：*Establish a clear visual hierarchy where controls and interface elements elevate and distinguish the content beneath them*），macOS 26 的浮起件用**柔影**而不是描边；同类 notch 应用（boring.notch / NotchNook / Alcove 等）无一使用卡片边框或 3D，且评测里把「切换/动画不顺」列为通病。**因此选「浮起」：常驻柔和阴影 + hover 轻微放大/提亮/阴影加深**，不做 3D 倾角、不加卡片底与边线。

实现落在 `HomeFlowView` 的格子（`HomeStripView.swift:757-760`：这一层同时拿得到块形档高与行高，能按块形而不是按行高画），新增 `homeBlockFloat()` 修饰符，两层组成：**① 常驻「柔光池」**——每块背后一圈**径向渐变的白光**（中心低透明度 → 边缘完全透明，**无填充边界、无描边**，不是卡片）；**② 内容辉光**——围绕内容的白色低透明度 `.shadow`；hover 时：柔光池与内容辉光加深、`scaleEffect ≈ 1.02`、`brightness ≈ 1.06`，动画 `.smooth(0.18–0.22s)`。**不用黑色阴影**——面板底色是纯黑（`ContentView` 的 `Color.black`），黑影在黑底上恒不可见（T1 首轮独立审查实测发现）；单纯内容辉光在空区只抬 ~0.1/255、实测不可见（Checkpoint 数值比对），故静态区分以**柔光池**为主、内容辉光为辅。**整条带的大底撤掉**（`homeBandContainer()` 只留内边距），行级 hover 底色（`homeBlockHoverBackground`）保留。观感在阶段 Checkpoint 上屏定稿（含「静态区分是否够」的判断，容差写在验收标准 A1）。

### 机制二 · 音乐再缩宽（第 2 条）

`MusicModule.homeBlockWidth` `240/300 → 200/250`（±10 上屏定稿）；紧凑密度三处一起收：控制键 `30 → 26`、键距 `8 → 6`、封面 `40 → 36`（封面距 6）。约束（测试钉关系式，不只钉数值）：**封面档装备宽度 `5×26 + 4×6 + 36 + 6 = 196 ≤ min 200`（余量 ≥4，不裁）**。曲名仍是 marquee（宽随块宽），时间行只在高度上占位、不挤宽。

### 机制三 · 架子三件事（第 3 条）

- **命名**：统一为「隔空投送与文件暂存」口径——设置行 zh「启用隔空投送与文件暂存」、短名 zh「投送暂存」（`Shelf` key 同时供侧栏、页标题、tab 文案，不拆 key）、`Open shelf tab…`/`Remove from shelf…` 两条清零「搁板/架子」旧译；补齐四条无中文的文案；「System Share Menu」回落改为本地化文案（zh「系统分享菜单」）不再直出英文。EN 侧保留 Shelf / 补 AirDrop 语义（具体串见 §接口与数据形状）。
- **✕ 修复**：① `DraggableClickHandler` 的 frame 收敛到 **cell 内容格**（`ShelfItemView` 里给 representable 显式 frame，或实现 `sizeThatFits`，二者取一，以「NSView.frame == 可见 cell 内容」为判据）；② `hitTest` 的让位区改为**与 ✕ 按钮同一份矩形算式**（抽纯函数 `ShelfRemoveButton.hitRect(in:)`，按钮绘制与 hitTest 共用）；③ ✕ 的显示条件从 `isHovering` 扩为 `isHovering || isSelected`（鼠标点选后也能删——既是可用性修正，也让本机 CUA 能走通「点选 → ✕ 出现 → 点击 → 删除」的上屏取证链）。
- **布局**：撤掉左右分栏与 `aspectRatio(1)`；**投放格**缩成与文件格同尺寸的一枚虚线格（供应商图标 + 名字 + 点按换供应商），作为网格**首格**；文件区改为 `LazyVGrid`（item 115×108 不变）**全宽、多行、纵向滚动**；无文件时网格下居中一行空态文案。Nook X 截图里的面包屑/搜索/筛选**不迁移**（我们不是文件浏览器）。Marquee 选中框保持既有行为，网格化后若几何假设失效做最小修正。
- **高度**：`shelf` 进测量名单（**须同时把探针挂到架子页**——`panelContentHeightReport` 现只挂在 `.module` 分支，`.shelf` 分支要复用同一探针）；自然高 ≈ 行数×格子高 + 内边距，单行时不占半屏；上限仍被 850 夹住、超出滚动。

### 机制四 · 通知字号（第 4 条）

只动**展开面板的通知页**（`NotificationsModuleView` 一族）：主行 +2pt、次要 +1pt（逐项档位见 §接口与数据形状），行距内边距 3→4；字号抽成 metrics 常量（可测）。首页通知块（定高 96 内画 3 行）与 HUD 浮层卡片（固定 320×64×倍率）**不动**。

### 机制五 · 高度切换平滑（第 5 条）

三件事一起：① **窗口动画**——`resizeWindow` 兑现既有的 `animated` 形参（`NSAnimationContext` + `window.animator().setFrame`，时长/曲线与内容动画 0.3s 对齐；**拖拽/连续更新走瞬时**，不动画）；② **单步切换**——`PanelContentHeight` 增**每页高度缓存**（`heightCache[tab]`，每次接受上报即写），`selectTab(tab)` 直接 `current = heightCache[tab]`（有缓存一步到位；从没量过的页仍回落手动值），切页后新页的**首份上报免防抖**立即生效；③ **启动台就绪门**——`apps` 加载完成前**不回报**（空态占位高不再进账本），杜绝首开「先塌陷再长高」的三拍。

### 机制六 · 日历取高与首页底部留白（第 6、7 条）

- **首页日历行**：行高 `294 固定 → 36N + 52`（~~78~~ **2026-10-01 T8 校准改判：78 → 52，见 D-23**；N = 当月实际周数，把 `MonthGridView` 的周数算式抽成纯函数 `weekCount(for:calendar:)` 供两边共用），10 月 5 周 → 232（原稿 258）；面板高随月变化是接受的行为。
- **日历页**：改成**理想高可传播的自然布局**（现结构是 `GeometryReader` + `paneHeight` 两栏 frame，探针按无高提案量会答出 10pt 级理想高、面板落到下限——必须去掉几何高依赖：网格按固定格高自然堆叠、右栏事件列在可用高内滚动）；把**日历模块的 tab 键**（`CalendarModule.moduleID`，当前实测 `com.cmeng.gourd.calendar`）加进 `measuredTabs`，探针按自然理想高上报（不再回落手动值）。
- **结果**：auto 档首页底部可见留白从实测 89pt 收敛到 **28pt**（~~20±6~~ **2026-10-01 T8 校准改判：口径 = 设计 20 + 日历末行格内空档 ≈8，见 D-23 与 A10**）；日历页高 ≈ 内容高（实测内容 288 → 面板 310，原稿估算 340 作废）。

### 机制七 · 宿主行排序（第 8 条）

`panelOrder` 的可用 id 扩到三个**宿主 tab**：`shelf` / `terminal` / `clipboard`（模块 tab 仍用模块 id）。设置「面板组件」节把「模块行 + 宿主行」**合并成一份按当前有效序渲染的名单**，每行带 ↑↓（写 `panelOrder` 走既有 `writeOrderTable` 纯函数）；`TabSelectionView.tabs` 的拼装改为按同一张表排序。**默认序（表为空）必须与现状逐字一致**（含扩展 tab 与用量 tab 的位置；测试钉死）。`取色器`不是面板 tab（渲染在标题栏图标行），保持开关-only（报告里向用户说明）。

### 机制八 · 空闲动画（第 9 条）

删掉 `ContentView.swift:1702` 的空体分支；把动画分支**上移到架子行内与模块折叠槽之前**（条件：关闭态 + 无 expansion + 音乐空闲 + 开关开 + `selectedIdleAnimation != nil`）——该设置是 opt-in，开着就以它为准，被动指示（架子托盘计数、折叠槽）让位；关掉设置即恢复原链。开关打开而从未选过样式时，自动选中第一条内置动画（否则开了还是看不到）。

### 机制九 · 设置侧栏归位（第 10 条）

`SettingsView` 的 页→组 映射把 `.modules` 从 `.integrations` 移入 `.mediaAndDisplay`（三处代码 + 注释同步；`availableTabs` 的组内顺序放在 `.devices` 之后）。

## 备选与取舍

| # | 备选 | 否决理由 |
|---|---|---|
| ① | **3D 倾角**（指针跟随的 `rotation3DEffect`） | 小角度下小字会糊、大角度不适合生产力面板；HIG 的层级语言用浮起与柔影即可表达；同类应用无先例（研究结论见机制一） |
| ② | **每块加常驻卡片底/玻璃板** | 用户本轮明说「不增加区域块、边线」；docs/26 D-10 的宽度预算理由（每块吃 8–16pt 内边距）仍成立 |
| ③ | 给块加**白色填充底/辉光板**做静态区分 | 填充即变相底板（仍违用户「不加区域块」）；**采纳的形态是围绕内容的辉光**（`.shadow` 白色低透明度，无填充、无边界），见机制一 |
| ④ | 架子保留左右分栏、只调比例 | 用户给了 Nook X 参考且点明「只能放一个、不该占半屏」——问题在结构不在比例 |
| ⑤ | 日历**声明一个固定偏好高**（如 340） | 5 周与 6 周月份差 36pt，固定值必然在某一类月份留白或截断；按周数算更便宜（纯函数） |
| ⑥ | 只删空分支、不调优先级 | 本机（架子有文件、待办默认开）修了也看不到 → 等于「不生效」不修 |
| ⑦ | 切页「先跳手动值再跳量值」消两次跳动 | 两次跳动比一次更糟；选**每页高度缓存**（多一份状态，换来一步到位） |
| ⑧ | 排序列**含取色器** | 它不是面板 tab（标题栏图标行），排它需要另立「标题栏图标顺序」第二套语义；本次不做，报告说明 |
| ⑨ | 架子迁移 Nook X 的**面包屑/搜索/筛选** | 我们是暂存区不是文件浏览器；多出来的控件要吃高度且无真源 |
| ⑩ | 通知字号**连首页块一起放大** | 首页通知块定高 96 内画 3 行，放大必裁；用户反馈指向展开面板（截图即通知页） |

## 明确不做

1. **不改首页布局骨架**（单条流、块序机制、带级内边距保留）。
2. **不加卡片底与边线**（含玻璃板；用户本轮明确）。
3. **取色器行不做排序**；**不做面板 tab 完全自由排序**（Home 固定第一，扩展 tab 与用量 tab 不进排序名单）。
4. **不动手动高度档的语义**（手动 = 固定高，切页不变高；报告里解释「为什么手动档下日历/启动台/留白仍是原样」）。
5. **不改通知的 HUD 卡片与首页通知块的字号**。
6. **不做启动台的自然高适配**：物理上 850 顶格、超出滚动（如实写进已知限制，不改上界函数）。
7. **不做架子多行框选增强**（marquee 只做「网格化后不坏」的最小修正）。
8. **不清理旧分带渲染器**（`HomeVerticalFit` / `HomeBandedLayout` 等遗留，另批）。
9. **不解决 CUA 驱动 hover 的限制本身**（取证降级见已知限制 1）。

## 实际交付

**批线与结构**：2026-10-01 一天内完成；**12 个任务（11 实现 + 1 回写）、5 阶段**，实现提交范围 `b4b1034e..` 批末 HEAD（**30 个提交**，全部本地、未 push），全量单测 **468 → 490 条 0 失败**，改动文件新增编译告警 0。收尾核对（控制器）：`defaults read com.cmeng.gourd panelHeightMode` → 键不存在（manual 残留已清、出厂 auto 生效）；`defaults read com.cmeng.gourd panelOrder` → 键不存在（排序复位）；`showNotHumanFace = 1`（用户原值，已还原）。

**交付物清单**（按任务；逐条对着报告与代码核过）：

| 任务 | 落点 | 交付物 |
|---|---|---|
| T1 首页浮起 | `Host/HomeStripView.swift`、`HomeStripLayoutTests.swift` | `HomeBlockFloatMetrics`（辉光终值 + 柔光池 + `effects(hovered:)` + `FloatEffects`）+ `HomeBlockFloatModifier` + `homeBlockFloat()`；`homeBandContainer()` 去底、`containerOpacity` / `containerCornerRadius` 删除 |
| T2 音乐缩宽 | `Modules/Takeover/MusicModule.swift`、`components/Notch/NotchHomeView.swift`、`components/HoverButton.swift`、`HomeStripLayoutTests.swift`、`TakeoverEnablementTests.swift` | `200/250`（命名常量）；`CompactMetrics` 26/6/36/6；`HoverButton.buttonSize(for:)`（`.small` 26）；两个 picker 加 `scale` 形参；三条关系钉 |
| T3 通知字号 | `Modules/NotificationsModule.swift`、`ModuleKernelTests.swift` | `NotificationRowMetrics`（11 主项 + 6 状态项）；展开页 17 处 `.system(size:)` 字面量归零；行内边距 3→4；首页块 / HUD 零 diff |
| T4 架子命名 | 两份 `Localizable.xcstrings`、`Shelf/Services/QuickShareService.swift`、`Shelf/Views/FileShareView.swift`、`Settings/SettingsView.swift`、`Shelf/AirDropView.swift`、`TakeoverEnablementTests.swift` | 14 行旧译 / 无译落值 + `QuickShareProvider.displayName`（回落项不再直出英文）+ 3 条整句 key；`testShelfUserVisibleStringsUseTheUnifiedName`（含变异取证） |
| T5 ✕ 修复 | `Shelf/Views/ShelfItemView.swift`、新 `ShelfInteractionTests.swift`（pbxproj 四处登记） | `ShelfCellMetrics`（115×108 单一来源）；`ShelfRemoveButton` 的 `hitRect` / `buttonRect` / `yieldsHitTest` 三纯函数同源；`isHovering \|\| isSelected`；拖拽视图 frame 收敛；两条几何用例（两次变异各自报红） |
| T6 架子布局 | `Shelf/Views/ShelfView.swift`、`FileShareView.swift`、两份 catalog、`ShelfMarqueeSelectionView.swift`、`Notch/NotchShelfView.swift`、`Kernel/PanelContentHeight.swift`、`PanelAutoHeightTests.swift` | `ShelfGridMetrics` + `ShelfPanel` + `ShareTargetTile`（popover：供应商列表 +「选择文件投送…」）；`shelfTab` 进 `measuredTabs` + 探针挂 `NotchShelfView`；5 条新用例 |
| T7 高度切换 | `Kernel/PanelContentHeight.swift`、`DynamicIslandApp.swift`、`Launcher/LauncherModule.swift`、`PanelAutoHeightTests.swift` | `heightCache` / `lastChangeWasTabSwitch` / `isTabReportReady`；`resizeWindow(animated:)` 兑现（`NSAnimationContext` 0.25s）；启动台就绪门；2 条点名用例 + T7-fix |
| T8 日历取高 | `Calendar/DynamicIslandCalendar.swift`、`Host/HomeCalendarRow.swift`、`Kernel/PanelContentHeight.swift`、`HomeStripLayoutTests.swift`、`PanelAutoHeightTests.swift`、`ModuleKernelTests.swift` | `weekCount` / `monthGridHeight`（`36N + 52`）+ `StandaloneCalendarView` 自然高；日历进 `measuredTabs`；2 条点名用例 + 结构护栏；T8 tune 校准（回收 22 + 3 + 2） |
| T9 宿主行排序 | `Tabs/TabSelectionView.swift`、`Settings/ModuleSettingsSection.swift`、`TakeoverEnablementTests.swift` | `PanelHostTab` / `PanelTabSequence`（`slots` / `orderedIDs` / `sequence`）/ `panelMovableIDs`；默认序逐字（用例钉死）；面板节脚注 zh/en 同步 |
| T10 空闲动画 | `ContentView.swift`、`Settings/IdleAnimationsSettingsSection.swift`、`managers/IdleAnimationManager.swift`、`components/IdleAnimationView.swift`、`TakeoverEnablementTests.swift` | 空分支删除 + 优先级上移 + `selectedIdleAnimation != nil` 门；`selectFirstBundledIfNoneSelected()`；`resolvedAnimation(for:)`（按 name 渲染期解析）+ 设置页预览同修 |
| T11 侧栏归位 | `Settings/SettingsView.swift`、`TakeoverEnablementTests.swift` | `SettingsTabGroup.group(for:)` 静态化；`.modules → .mediaAndDisplay`；注释按 D-18 改写 |
| 回归修复 | `ContentView.swift`、`PanelAutoHeightTests.swift` | `shouldHonorHoverExit` 纯函数 + `finishHoverExit` 早退 + 轮询接入 + 接触位置观测（切日历页不再塌回关闭态） |
| T12 回写 | 本文档、`docs/29`、`docs/26`、`CHANGELOG.md` + 注释清扫 | 本节与各节按实现校正；改判留痕就地；过期注释清理（不改行为） |

**证据目录**：`.workflow/p6-ui-polish/evidence/` 已拍 **20 件**（17 张截图 + 3 份文本）——`t1-blocks-float.png`、`t2-music-narrow.png`、`t3-notifications-font.png`、`t4-shelf-strings.txt`（AX 文本，见图内说明）、`t5-shelf-remove.png`（点选→✕→删除前后对比）、`t6-shelf-grid.png`、`t7-launcher-cap.png`、`t7-switch-single-step.png` + `.txt`（四页高度汇总）、`t8-calendar-tab.png`、`t8-home-bottom.png` + `t8-home-bottom.txt`（`panel_bottom=559 last_ink=531 visible_blank=28px`，auto）、`t9-host-row-arrows.png`、`t9-order-changed.png`、`t10-idle-on/-off(-zoom).png` 4 张、`t11-sidebar.png`。**证据随 `.workflow/` 消失**。

**与计划的偏离**（逐条给理由；「文档写的是预期，代码是真的」）：

1. **T7 改判**：`awaitsFirstReport = isMeasured && cached == nil`（缓存命中时首报回滞回、消微跳）——计划写的是「切页后首报免防抖」的无条件豁免；控制器裁决采纳后收窄（详见 §接口 机制五）。
2. **T8 校准**：行高公式 `36N + 78` → **`36N + 52`**（上屏实测可见留白 53 → 28，回收「网格下方」三段多预留 22 + 3 + 2；见 §接口 机制六的构成表）。
3. **T6 三条实现判断**：① 不再把内容撑到视口高（`minHeight` 会让理想高恒等于视口高=不动点，面板永远缩不下来）；② 面板壳 `ShelfPanel` 的环由「根」改「覆盖层」（环当根时无高提案答 10pt，实测账本收到 18 → 面板压到 120 下限）；③ 列数用 `.adaptive` 而不是 `@State` 视口宽自算（第一遍布局就与量高对齐，否则撞「光标在面板内不缩」卡在错高度）。
4. **T10 三轮**：主轮（删空分支 + 上移 + nil 门 + 兜底选第一条内置）→ 修复轮（上屏复验发现存储值是写入时刻的绝对路径、卷卸载/换位置失效 → 内置动画按 `name` 渲染期解析）→ 补轮（设置页缩略图同病同修）。
5. **回归 bug 的 hover-exit 修复**（计划外）：auto 高度让「切页会大幅缩小面板」成为常态后，`finishHoverExit` 把「面板在指针底下缩走」读成「指针离开面板」→ 切日历页塌回关闭态（控制器实机复现 3/3）；判据改为「与指针最后接触时的面板 rect」（D-21）。

**遗留项**（本批明确未做；逐条有出处）：

1. **`.workflow/p6-ui-polish/` 报告台账**（`ledger.md` + 14 份任务报告 + 20 件证据）**随 `.workflow/` 消失**——结论已收进本节、§已知限制与 §决策摘要，过程记录不另存。
2. **`AirDropView` 死代码的 2 行显示改动仍在**（`:98` / `:125` 改成 `displayName`）：全仓无任何实例化点，改动不可达 UI（T4 裁决「目录级显示点清零」，保留只为一致性；要回到「死代码不动」口径回退这 2 行即可）。
3. **`NSOpenPanel` 两条整句 key**（`Select Files for %@` / `Choose files to share via %@`）：zh 的 title 取「选择共享服务」、不含供应商名（en 保留 `%@`）；message 带 `%@`。若希望标题也带供应商名，改一处 catalog 值即可。
4. **扩展 tab 不在排序名单**（不可排槽位，与用量 tab / Home 同档）：`PanelTabSequence.sequence` 只重排可排槽位，扩展 tab 停在原槽位索引上（D-16 的「位置不动」口径）。
5. **旧分带渲染器未清**（`HomeBandedLayout` / `HomeVerticalFit` / `widgetRowHeight` 一族遗留与滞后注释）：不在生产路径上，另批（§明确不做 8；本次只清了注释层面的过期陈述）。

**交用户可否决的两条收窄**（§做法 与 D-08 / D-12 已写明，批末显著呈现）：① 架子页从「回落手动值」改为**贴内容自然高**（单行不占半屏）；② 启动台保持 **850 顶格**、超出滚动。

## 已知限制

1. **本机 CUA 驱动不出 hover 态**（SwiftUI/AppKit tracking area 收不到合成事件——本次实机复现确认）。影响：机制一的 hover 提升、机制三的「hover 才显示 ✕」路径无法由上屏截图全证 → hover 相关取证降级为「纯函数/状态测试 + 直接可见部分截图」。**需真人用鼠标复核的两条**：① 首页块 hover 的浮起观感（轻微放大 / 提亮 / 辉光与柔光池加深，邻居不被挤开）；② 架子上 ✕ 的 hover 显示（不点选、只悬停即出现）。
2. **手动档下第 5/6/7 条的现象依旧存在**（手动 = 固定高是语义）：启动台只显示 5 行半、日历页下留白、首页底部留白 = 手动值 − 内容高。盘上 `panelHeightMode` 系上一批验收残留的 manual（产品默认是 auto），收尾已**清回出厂默认**（`defaults read` 报键不存在）；外观页可随时切回手动。
3. **启动台在 850 顶格时仍要滚动**（106 个 App + 用户把图标调到 81pt 的自然高 ≈1.6k），这是上界函数的既定行为，不是本次缺陷（D-12）。
4. **日历页高随月份变化**（5/6 周差 36pt：232 vs 268），面板高度会有月份级的台阶——接受（比全年按 6 周预留更贴内容）。另：首页日历行的行高**不随浏览翻月变化**（行与宿主预算读同一个「当前月」数；翻到 6 周月时网格在行内滚动）。
5. **剪贴板宿主行的排序值只在「分栏模式」下可见生效**（`clipboardDisplayMode == .notchTab` 时渲染在标题栏图标行）。
6. 机制五的窗口动画在**多屏/低电**下未验证；连续快速切页的动画行为是「追上最后一拍」（每次 `animator().setFrame` 替换同属性动画，不排队），留观察。
7. **首次打开面板仍有一拍「手动高度 → 贴合」**（既有形态，本次如实收）：打开是「先定尺寸、再渲染」，首开时账本还没有值 → 回落手动高度，随后那一拍补推。本次实测一次 ≈704 → 贴合；**稳态贴合 ≤ 0.35s**（换帧观测）。
8. **缓存命中且离开期间内容变矮时，光标在面板内不缩**（条款 ④ 的既有形态，T7 裁决后可见）：切回量过的页、而这一页在离开期间内容变矮 → 8pt 滞回 + 光标规则把它拦下，**移开鼠标才贴合**。无缓存那一档（第一次进这一页）不受影响。
9. **跨安装位置的存储资源路径会失效**：本次修了**内置**空闲动画的渲染期解析（盘上的值仍指向写入时刻的绝对路径，如 `/Volumes/壶中天/...`；渲染期按 `name` 从当前 bundle 重新解析）。**自定义动画不在此列**：`isBuiltIn == false` 原样返回存储路径——从 DMG / 移动卷时代导入的自定义动画，卷卸载或换安装位置后仍会加载失败（如实记；要修得给自定义动画另立「重定位」语义）。
10. **架构边界（逐条 5 项）**：① 通知页字号只覆盖**展开页**（首页通知块定高 96、HUD 卡片固定尺寸都不动，D-09）；② 日历页高随月份（5/6 周差 36pt，见 4）；③ 剪贴板排序只在分栏模式可见（见 5）；④ **取色器不参与排序**（不是面板 tab，渲染在标题栏图标行，D-16）；⑤ 启动台 850 顶格仍滚动（见 3）。
11. **两类取证受工具限制**（终审已裁定为「实现做了、证据降级」，如实收）：① D-10 的**换帧采样**未做——CUA 观测"等待稳定"，拿不到动画中间帧；替代证据 = 每页终值（Home 578 / Shelf 241 / Calendar 310 / Launcher 872，`t7-switch-single-step.txt`）+ 端到端「无先塌陷再长高」观察 + 代码链（`.workflow/p6-ui-polish/evidence/`）；② t4 命名证据里**设置行「启用隔空投送与文件暂存」的截图**未拍成——设置窗 Form 惰性渲染 + CUA 滚动推不动（event/a11y/PageUp 均试过），替代证据 = AX 元素文本（`t4-shelf-strings.txt`，含该行与脚注的机器可读面貌）+ catalog 用例 + `t6-shelf-grid.png` 里的「系统分享菜单」回落文案。

## 验收标准

- **A1** 首页：每块之间有可见区分（撤大底 + 浮起样式）且**无任何新增描边/底板**；hover 时块轻微放大、阴影加深（后者需真人复核，见已知限制 1）。上屏截图留证。
- **A2** 首页音乐块在声明 min（≈200）宽度下：封面打开时不裁、五键不重叠；理想宽度下比上一版（300）明显更窄（截图对比）。
- **A3** 设置 → 组件：四行宿主行的文案显示为「启用隔空投送与文件暂存 / 启用终端 / 启用剪贴板管理器 / 启用取色器」；设置侧栏与页标题不再出现「架子 / 暂存器 / 搁板」任一旧名（面板 tab 只画图标、无可见名）；新增文案无英文直出（含空态的「系统分享菜单」）。
- **A4** 架子：点选（或 hover）文件 → ✕ 出现 → 点击后**文件从暂存区消失**（截图前后对比）；拖拽出文件的行为不回归。
- **A5** 架子布局：投放格 ≈ 一格大小、文件区全宽多行；887 宽面板下单文件时文件区不再被左块吃掉一半；空架子有空态文案。
- **A6** 通知页：正文/标题/来源肉眼可读性提升（截图）；首页通知块与 HUD 不变。
- **A7** 面板高度切换：首页 → 启动台/通知/日历 各切一次，面板尺寸**单步、带动画**到位（换帧采样各 ≤2 次明显台阶，无「先塌陷再长高」）；从没量过的页回落手动值的行为不变。
- **A8** 启动台：首开不塌陷；auto 档到达 850 顶格（内容超出时滚动）。
- **A9** 日历：首页行高 = `36N+52`（10 月 = 232，单测覆盖 5/6 周；T8 校准轮回收 22+3+2 的多预留）；日历页面板高 ≈ 内容高（实测内容 288 → 面板 310，不再 682）。
- **A10** 首页 auto 档底部可见留白收敛（实测 89 → 校准后 **28**；口径 = 设计 20 + 日历末行格内空档 ≈8，为当前结构值；像素测量留证 `.workflow/p6-ui-polish/evidence/t8-home-bottom.txt`）。
- **A11** 排序：设置页把「架子」上移到「终端」之前（或任意两行互换）→ 面板 tab 顺序立即跟随；默认（不动任何行）顺序与改动前逐字一致（测试 + 截图）。
- **A12** 空闲动画：开关开 + 已选样式 → 面板关闭时看到动画；关掉开关 → 折叠槽/托盘计数恢复。**上屏实测**（2026-10-01）：开=刘海右端出现小狗动画、关=待办折叠槽「0/4」恢复（优先级压过被动槽位由链与用例保证；架子有文件时的让位同理）。
- **A13** 设置侧栏：「组件」出现在「媒体与显示」分组内（截图）；`扩展` 仍在「集成」。

## 接口与数据形状

> 执行者按本节取值；已按**落地后的实际签名**写（回写时逐条对着代码与报告核过，不是计划稿）。

**机制一（首页浮起）**

- 新修饰符 `homeBlockFloat()`（文件级，`HomeStripView.swift` 内）：效果值经纯函数 `HomeBlockFloatMetrics.effects(hovered:)` 组装出 `FloatEffects { scale / brightness / glowRadius / glowOpacity / poolOpacity }`（测试钉该函数；修饰符不碰常量、不写算式）。唯一调用点 = `HomeFlowView` 的格子，套在格子的 `.frame` **之后**（视觉修饰不改格子尺寸）。
- **终值**（Checkpoint 两轮上屏调参后定稿）：辉光 `idleGlowOpacity 0.08 / idleGlowRadius 5`（hover `0.16 / 11`）、`hoverScale 1.02 / hoverBrightness 1.06`（组装时减 1 成增量）/ `duration 0.2`；**无黑影项**（`idleShadow*` / `hoverShadow*` / `idleShadowY` 全部删除——面板底色是纯黑，黑影在黑底上恒不可见，T1 首轮审查实测）。
- 柔光池（**静态区分的主力**）：`poolOpacity 0.06`（hover `0.12`）、池半径经 `HomeBlockFloatMetrics.poolEndRadius(width:height:) = max(0, min(w,h) × 0.45)`（~~`max(48, min(w,h)×0.45)`~~ **2026-10-01 终审修复改判：去掉 48 下界**——min(w,h)<96 时 48 > 半短边，渐变在最近边之前不归零=变相底板；用例对 40/96/140 三档钉「有效半径 ≤ 0.5×min」。径向渐变到全透明；**系数必须 ≤0.5**——格子最近边在 `0.5 × min(w,h)` 处，系数 0.7 时边缘残留 28.6%、形成直角台阶；T1 三轮重审 0.7 → **0.45**）。池挂在块的 `.background`（`.shadow` 之后、`allowsHitTesting(false)`）：不参与缩放/提亮、也不进辉光轮廓，不参与命中、零布局成本。**纯辉光在空区只抬 0.07–0.5/255（Checkpoint 二轮实测），静态区分以池为主、辉光为辅。**
- 应用链（逐字）：`.scaleEffect` → `.brightness` → `.compositingGroup()` → `.shadow(color: .white.opacity(glowOpacity), radius: glowRadius)`（`y` 恒 0——不做位移）→ `.background { GeometryReader { RadialGradient } }` → `.animation(.smooth(duration:), value: hovered)`；`hovered` 由 `.onHover` 就地持有。
- `homeBandContainer()`：**去掉 `.background(...)`**（保留横向 8pt 内边距 `HomeBandChrome.containerInset`）；`HomeBandChrome.containerOpacity` / `containerCornerRadius` 两个常量已删除；行级 `hoverOpacity 0.06` / `hoverCornerRadius 8` 保留（`homeBlockHoverBackground(isHovered:)` 的唯一取值处）。

**机制二（音乐）**

- `MusicModule.homeBlockWidth = (min: 200, ideal: 250)`（两个数落成命名常量 `homeBlockMinWidth` / `homeBlockIdealWidth`；形态仍 `.compact`）。测试钉「min/ideal 取值 + 命名常量与声明同源」。
- 紧凑密度（`MusicControlsView.CompactMetrics`，`NotchHomeView.swift`）：控制键 **26**（`HoverButton.buttonSize(for: .small)`；`.medium 30` / `.large 40` 的既有取值与全部使用点未动）、键距 **6**、封面 **36**、封面距 **6**、控制行高 = 键径（26）。
- 测试钉的关系式（钉关系，不只钉数值）：封面档装备宽度 **`5×26 + 4×6 + 36 + 6 = 196 ≤ min 200`**（余量恰 4，另有一条 `196 + 4 == 200` 的余量钉防踩线）；紧凑内容高 **`4 + 17 + 4 + 34 + 6 + 26 = 91 ≤ 96`**。封面的 36 / 6 归 `CompactMetrics`（模块侧直接引它，单一真源）。
- 两个 picker 按钮（媒体输出 / AirPlay）加 `scale: Image.Scale = .medium` 形参（缺省 = 展开面板原档）——五键全配时才装得进 196。

**机制三（架子）**

- 命名（zh，已按 T4 落值）：`Enable shelf` → 启用隔空投送与文件暂存；`Shelf`（侧栏 / 页标题同一个 key，不拆）→ 投送暂存；`Open shelf tab by default if items added` → 添加项目时默认打开投送暂存标签；`Remove from shelf after dragging` → 拖拽后从暂存移除；补译：`Remove from Shelf` → 从暂存移除、`Shelf item` → 暂存项目、`Allow moving files when dragging out` → 拖出时允许移动文件；`System Share Menu` 回落 → zh「系统分享菜单」（新增 key，en 也落 `translated`）。EN 侧：`Enable shelf` → `Enable AirDrop & File Shelf`，其余保留 Shelf 词根。两份 catalog 都落（进包的是 `DynamicIsland/Localizable.xcstrings`；根 `Localizable.xcstrings` 不在任何 target，只改它命中的两条）。**执行期新增 3 条整句 key**：`Choose Files to Send…`（选择文件投送…）、`Select Files for %@`（选择共享服务）、`Choose files to share via %@`（选择要通过 %@ 共享的文件）。
- `ShelfCellMetrics`（cell 内容单一来源）：`contentWidth 105 / horizontalPadding 5 / verticalPadding 10 / iconSize 56 / contentSpacing 2 / textHeight 30` → `size = 115×108`。`DraggableClickHandler` 拿到 `.frame(ShelfCellMetrics.size)`——「NSView.frame == 可见 cell 内容」由它结构性保证。
- `ShelfRemoveButton`（由 private 升 internal）：`size 20` / `hitRegion 30`；三个纯函数同源——`hitRect(in:)`（cell 顶右 30×30，115×108 cell 下 = `(85, 0, 30, 30)`）、`buttonRect(in:)`（让位区内居中 20×20 = `(90, 5, 20, 20)`）、`yieldsHitTest(to:in:)`（= `hitRect.contains`；`DraggableClickView.hitTest` 先做 AppKit bottom-left → 顶左翻转再转发）。✕ 显示条件 **`isHovering || isSelected`**（`showsRemoveButton`）；**让位条件与显示条件绑成同一个值**（`removeButtonVisible`——否则选中态画出的 ✕ 在指针未触发 hover 的瞬间点不动）。
- 新版面：`ShelfView.body` = 单块 `ShelfPanel`（内容当根、圆角环改覆盖层）；内容 = 纵向 `ScrollView` + `LazyVGrid`（`ShelfGridMetrics`：列宽 = `ShelfCellMetrics.size.width` 115、项距 8、行距 8、`.adaptive(minimum:115, maximum:115)` 自适应列；`columnCount(forWidth:)` 是它的预测式），首格 = `ShareTargetTile`（115×108 虚线格：供应商图标 + 名称；**点按弹 popover：供应商列表（切换）+「选择文件投送…」按钮——保留原 NSOpenPanel 投送入口，调用链 `handleClick()` → `QuickShareService.showFilePicker` 未变**），其余为 `ShelfItemView`；`.onDrop` 仍挂容器/滚动区（拖到网格任意处可落；最内层优先——投放格 = 投送、其余 = 入库）；空态一行（复用 `Drop files here`）。`ShelfMarqueeSelectionView`：`hitTest` 增 `passThroughRects`（投放格让位）、自动滚动由 X 轴改 Y 轴（单行假设失效处的最小修正；marquee 只做「网格化后不坏」口径）。
- 高度：`PanelContentHeight.shelfTab = "shelf"` 加进 `measuredTabs`；`NotchShelfView` 挂同一探针（`panelContentHeightReport(tab: PanelContentHeight.shelfTab, headerHeight: panelHeaderHeight(...), isCurrent: { coordinator.currentView == .shelf })`）。**不再把内容撑到视口高**（`.frame(minHeight:)` 已删——撑高会让理想高恒等于当前视口高，是不动点，面板永远缩不下来）；面板壳的环由根改覆盖层（环当根时无高提案答 10pt，实测账本收到 18 → 面板压到 120 下限）。

**机制四（通知字号）**

`NotificationRowMetrics`（文件内 struct，测试钉表）的**实现值**：

| 元素 | 实现值 | 备注（起点 → 定稿） |
|---|---|---|
| 模块名 | 13 | 12 semibold → 13（权重留调用点） |
| 状态行「最近 N 条」 | 12 | 11 → 12 |
| 全部清除 | 11 | 10 → 11 |
| 刷新图标 | 12 | 11 → 12 |
| 来源 App 名 | 12 | 11 semibold → 12 |
| 分隔「·」 | 12 | 11 → 12 |
| 时间 | 11 | 10 rounded → 11 |
| 标题 | 13 | 11 → 13 |
| 正文 | 12 | 10 → 12 |
| 行内 × | 11 | 10 → 11 |
| 脚注 | 10 | 9 → 10 |
| 行内边距（垂直） | 4 | 3 → 4 |

**执行期扩口（T3 修复轮，共 6 项）**——失败态 / 空态 / 权限引导同页比邻的字号一并收进表内、按语义就近取档（不超过主行档 13）：

| 元素 | 实现值 | 旧值 → 新值 |
|---|---|---|
| 失败态图标 | `failureIconFontSize = 13` | 16 → 13（取标题档＝主行上限，保「图标 > 说明文字」层级） |
| 失败原因文案 | `failureReasonFontSize = 12` | 11 → 12（状态/提示类） |
| 空态文案 | `emptyStateFontSize = 12` | 12（值不变，仅收进表） |
| 权限引导图标 | `permissionIconFontSize = 13` | 18 → 13（同失败态图标） |
| 权限引导说明 | `permissionHintFontSize = 12` | 11 → 12 |
| 权限引导按钮 | `permissionActionFontSize = 12` | 11 → 12（空块里唯一的动作，不按「清除」11 档） |

首页通知块（定高 96 内画 3 行）与 HUD 浮层卡片（固定 320×64×倍率）**零改动**（独立代码路径，无共享字号常量）。

**机制五（高度切换）**

- `PanelContentHeight` 三件已按实现落地：**每页高度缓存** `heightCache: [String: CGFloat]`（`report(_:for:)` 每次**接受**即写；`reset()` 清空）；**切页首报免防抖** `lastChangeWasTabSwitch`（两档置位：`selectTab` 换掉当班值 / 新页**第一份**上报被接受；每个写入口开头先清，只在真发出 `objectWillChange` 且属于这两档时为真）；**就绪门** `isTabReportReady: @MainActor (String) -> Bool`（宿主注入，默认恒真——与 `pointerInsidePanel` 同一形态，探针的 `reportNaturalHeight` 多一道 `guard`）。
- `selectTab(_:)`：名单**内**的页量过 → 直接读 `heightCache[tab]`（**一步到位**）；没量过 → 走旧路径（留上一页量值 + 首份上报无条件）；名单**外**的页 → 清当班值回落手动值，**缓存按页留着**。
- **T7 裁决修正**：`awaitsFirstReport = isMeasured && cached == nil`——**无缓存**才走首报豁免；**缓存命中**的第一份上报回普通条款（8pt 滞回 + 光标规则），差 < 8pt 的微跳不再推第二次窗口。
- `resizeWindow(animated:)`：`animated == true` 时 `NSAnimationContext`（`duration = 0.25`、`.easeInEaseOut`）执行 `window.animator().setFrame`；`false` 时逐字保留 `window.setFrame(_:display:)`（瞬时路径：拖拽 / 初始化 / 例外档）。`animationBehavior = .none` 保留（只挡隐式动画，显式 animator 不受影响）。`shouldAnimateResize(for:)` 的既有例外**接续**生效（极简 UI + 活跃提醒 → 该档仍走瞬时），不删。
- 账本订阅分两档：`lastChangeWasTabSwitch` 为真 → `DispatchQueue.main.async { updateWindowSizeForTabSwitch() }`（**同一条**立即链、延后一拍读新值；`updateWindowSizeForTabSwitch` 由 `animated: false` 改走 `shouldAnimateResize(for:)`——切页必动画）；为假 → 原 `debouncedUpdateWindowSize()`（0.15s）。
- `LauncherModule` 就绪门：`LauncherStore` 新增 `private(set) var hasLoadedApps`（`apps` 落地后置位，**不是** `@Published`）；`LauncherModule` 暴露 `var hasLoadedApps: Bool`；宿主按模块 id 转发给 `isTabReportReady`（拿不到模块实例时恒真）。
- **回归修复（D-21，切日历页不再塌回关闭态）**：hover 退出判据抽成纯函数 `shouldHonorHoverExit(isOpen:lastContactRect:pointer:)`——展开态的「面板位置」= 面板与指针**最后一次接触**时观测到的窗口 rect；指针仍在这块位置里 ⇒ 这次退出是面板自己动的，不按退出收面板；没有接触记录 ⇒ 老口径（照收）。`finishHoverExit()` 顶部早退、轮询 `stillInside` 增「仍在最后接触位置里」或项；`panelWindowRect(containing:)` 只服务「记录面板位置」（只认 `DynamicIslandWindow`）。

**机制六（日历）**

- `MonthGridLayout.weekCount(for:calendar:)`（与网格渲染同源：= `days(forMonth:calendar:)` 的格数 / 7，不另写「按日历算周数」的算式）与 `monthGridHeight(forMonth:calendar:)` = `36 × N + 52`（N = 当月实际周数）。
- 行高公式（T8 tune 校准后的完整构成）：行高 = `36N − 6`（网格内容：`N × 30` + `(N−1) × 6`）+ `4`（网格 `.padding(.top, 4)`）+ `headerChromeHeight 34`（= 24 + 10）+ `weekdayChromeHeight 20`（= 14 + 6，含 1pt 防拉伸余量）→ **`36N + 52`**：3 周 160 / **5 周 232（2026-10）** / 6 周 268。备忘：旧链是固定 294（「最坏 6 周」）→ T8 首版 `36N + 78`（258）→ **T8 tune `36N + 52`（232）**（收回「网格下方」三段多预留 22 + 3 + 2 = 27，其中 1pt 作为防拉伸余量保留）。面板设计留白 20 是「可见留白」口径的独立一项（`NotchHomeView` 的 8 + `ContentView` 的 12），不计入行高公式。
- `HomeCalendarRow.rowHeight` = `static var`（**按当前月**，= `rowHeight(forMonth: Date())`）+ 纯函数入口 `rowHeight(forMonth:calendar:)`（转调 `MonthGridLayout.monthGridHeight`）。**翻月不改行高**（行与宿主预算读同一个数；翻到 6 周月时网格在行内滚动、不被裁）。
- `StandaloneCalendarView`：拆掉 `GeometryReader + paneHeight` 两栏定高 frame，改**自然高**布局——左栏 `MonthGridView` 显式 `frame(height: monthGridHeight)`、右栏拿同一个高度（事件列在里滚动/裁剪）、宽度两栏等分（`paneSpacing = 12`）。**实测**（收尾波上屏）：内容 ≈288 → 面板 ≈310（T8 tune 后 2026-10 档；旧口径回落手动值 682 不再出现）。
- `measuredTabs` 加入 **`CalendarModule.moduleID`**（实测字面量 `com.cmeng.gourd.calendar`；不是字符串 `"calendarTab"`）——日历页自然高进入账本。

**机制七（排序）**

- `PanelHostTab`（`TabSelectionView.swift`，文件作用域）：`shelf / clipboard / terminal`；`id` = `panelOrder` 的键（`shelf`、`terminal` 与 `ContentView.selectedPanelTabKey` / 账本键同词；**`clipboard` 是排序专用键——该面板页渲染 `.notes`、账本键为 `notes`**）；`gateKey`（`.dynamicShelf` / `.enableClipboardManager` / `.enableTerminalFeature`）；`defaultOrder = -30 / -20 / -10`（负值 = 缺键时恒在一切模块之前 = 改动前的实际顺序）。
- `PanelTabSequence`（`@MainActor`，视图与用例共用的**唯一**拼装与排序算式）：`Entry { id, defaultOrder }`、`Slot<Payload> { id, isSortable, defaultOrder, payload }`（`.fixed` / `.sortable` 两档构造）、`slots(home:shelf:usage:clipboard:terminal:extensions:modules:)`（**槽位骨架** = 改动前 `tabs` 的拼装顺序逐字）、`orderedIDs(_:panelOrder:)`（排序的**唯一算式** → `ModuleRegistry.panelRank`）、`sequence(_:panelOrder:)`（只重排**可排槽位**——宿主三 tab + 模块 tab；**不可排项 Home / 用量 / 扩展留在原槽位索引上**，这是「默认序逐字 + 位置不动」的落点）。
- 设置页：`ModuleSettingsSection.hostPanelEntries`（宿主三 tab 的 `Entry`）+ **`panelMovableIDs(moduleEntries:panelOrder:)`**（可排名单的键序，与面板条同一算式；取色器行不在名单里）。`panelOrder` 新增合法 id：`shelf` / `terminal` / `clipboard`（模块 tab 仍用模块 id）；行上 ↑↓ 复用 `writeOrderTable`。**默认序（表为空）与改动前逐字一致**（测试钉死；存量 `panelOrder`（只有模块 id）下宿主仍排最前 = 向后兼容）。
- `取色器`不是面板 tab（渲染在标题栏图标行），保持开关-only（备选⑧）。

**机制八（空闲动画）**

- `ContentView.swift`：删除关闭态中央槽位链上的**空体分支**；动画分支**上移**到架子行内 / 模块折叠槽之前（扩展 payload 之后）——条件 = 原条件（关闭态 + 无 expansion + 音乐空闲 + `showNotHumanFace` + `!hideOnClosed`）**尾部追加 `selectedIdleAnimation != nil`**；分支体 `DynamicIslandFaceAnimation()` 逐字未动。新增 `@Default(.selectedIdleAnimation)` 观察点（nil 门 + 叫醒：兜底写要让视图当场重绘）。
- `IdleAnimationManager.selectFirstBundledIfNoneSelected()`（`@discardableResult -> Bool`；**实现为挂在设置文件内的 extension**，语义上是 manager 的可直调方法）：选择为空时把库里**第一条 `isBuiltIn`** 的动画写进选择；已有选择 / 库里没有内置动画 → 不写。设置区 `.showNotHumanFace` 由关变开时 `onChange` 转发它（闭包不含判断）。
- **渲染期解析（T10 修复轮，修 `/Volumes` 死路径）**：`IdleAnimationManager.resolvedAnimation(for:)`——`isBuiltIn == true` 时按 **`name`**（**不是 id**：`loadBundledAnimations()` 每次加载都新生成 UUID，按 id 必 miss）从新鲜内置列表取同一条、只把 `source` 换成当前 bundle URL；身份（`id` / `speed` / `isBuiltIn` / `name`）原样保留，找不到同名 → `nil`（面动画视图走既有 `EmptyView()`）。`IdleAnimationView` 与设置页 `AnimationPreview` **同一解析**；进程内缓存 `cachedBundledAnimations`。不动存储格式、不做迁移。

**机制九（侧栏）**

- `SettingsView.swift`：页→组映射抽成静态函数 **`SettingsTabGroup.group(for:)`**（单值 switch = 唯一真源；`SettingsTab.group` 是其一行转发）；`.modules` 从 `.integrations` 移入 `.mediaAndDisplay`（`.integrations` 分支只剩 `.extensions`）；`availableTabs` 的组内顺序 `.modules` 移到 `.devices` 之后；注释按 D-18 口径改写。`SettingsTab` / `SettingsTabGroup` 两枚举去掉 `private`（测试直调所需的最小开放面）。

## 决策摘要

| ID | 决策 | 来源 | 理由 |
|----|------|------|------|
| D-01 | 首页每块要有视觉区分，且**不加区域块与边线**（样式方向：3D/阴影/浮动任选合适的） | 用户 | 第 1 条原话；「查下什么合适」授权代理选型 |
| D-02 | 形态选「浮起」：常驻**柔光池 + 内容辉光**、hover 放大/提亮/加深；**撤掉整条带的大底**；3D 不采纳 | agent | HIG/Liquid Glass 的层级语言与同类应用现状（机制一）；3D 小字会糊（备选①）；黑影黑底不可见（审查实测）、纯辉光空区不可见（Checkpoint 实测）→ 静态区分以无边界柔光池为主 |
| D-03 | 音乐块宽度进一步缩小 | 用户 | 第 2 条 |
| D-04 | 目标 `200/250`、控制键 26/键距 6/封面 36；钉「封面档下不裁」的关系式 | agent | 现 240 下封面档只剩 10pt 余量（音乐块 5 键 182 硬编码） |
| D-05 | 架子统一命名「隔空投送与文件暂存」（tab「投送暂存」）；缺译补齐；中文侧清掉「架子/暂存器/搁板」 | 用户 | 第 3.1 条原话「不是隔空投送和文件暂存么」 |
| D-06 | 架子布局：投放格缩为一枚小格、文件区全宽多行网格、空态一行（Nook X 结构，不做面包屑/搜索） | 用户 | 第 3.3 条 + 参考图 |
| D-07 | ✕ 修复 = 拖拽视图 frame 收敛 + hitRect 纯函数共用 + `isHovering \|\| isSelected` 显示 | agent | 根因是 frame 错位（本地复现）；「选中即显示」按文件管理器惯例扩了显示条件（取舍：多一个可达入口；取证可利用是其附带收益，非理由） |
| D-08 | 架子进高度测量名单（自然高，单行不占半屏） | agent | 新版面下 682 回落会让「不留白」诉求反弹；该收窄（架子页从回落手动值改为贴内容）在批末报告显著呈现，用户可否决 |
| D-09 | 通知面板字号 +1~2pt（档位表），仅展开页；首页块/HUD 不动 | 用户 | 第 4 条；首页块 96pt 定高放不下 |
| D-10 | 面板切页高度必须单步、带动画、不塌陷 | 用户 | 第 5 条「卡顿」「高度不够」 |
| D-11 | 实现：窗口动画（NSAnimationContext）+ 每页高度缓存 + 切页首报免防抖 + 启动台就绪门 | agent | 机制五；实测 0.9s 时窗口 872/内容 690 的脱节与三拍塌陷是直接证据 |
| D-12 | 启动台保持 850 顶格（不改上界函数） | agent | 物理上放不下（1.6k 自然高）；改上界会动到全局高度契约；**该收窄在批末报告显著呈现，用户可否决** |
| D-13 | 日历按当月实际周数取高：首页行 ~~36N+78~~ **36N+52（2026-10-01 T8 校准改判，见 D-23）**；日历页自然高 + 进测量名单 | 用户 | 第 6 条「为什么这么高」；实测内容 ~300 而面板 682 |
| D-14 | 首页底部留白收敛（实测 89 → 28，~~≈20~~ 见 D-23）；盘上 manual 残留清回出厂 auto，报告说明 | 用户 | 第 7 条；留白 89pt 的分解（20 设计 + ~69 日历行多预留）；manual 系上批验收残留 |
| D-15 | 三个宿主 tab（shelf/terminal/clipboard）并入 `panelOrder` 排序；设置页两节合并为一份有序名单 | 用户 | 第 8 条；推翻 p5 D-07「宿主行不参与排序」 |
| D-16 | 取色器不做排序（不是面板 tab）；默认序必须与现状逐字一致（测试钉死） | agent | 备选⑧的理由；防「排序一开就变序」；**该收窄在批末报告显著呈现，用户可否决** |
| D-17 | 空闲动画：删空分支 + 优先级上移到被动槽位之前 + 未选样式自动选第一条 | 用户 | 第 9 条；根因=上游空分支 + 槽位占位（机制八） |
| D-18 | 「组件」移入「媒体与显示」分组 | 用户 | 第 10 条；推翻 docs/26「扩展/组件相邻」口径 |
| D-19 | 十项跨模块，一个批次 12 任务执行（超 8 任务上限的取舍） | agent | 反馈天然一批；拆流增加协调面与两次收尾；分 5 阶段（含回写）控制单点跨度 |
| D-20 | hover 类取证降级：纯函数/状态测试 + 截图（能见的）+ 报告列「需真人鼠标复核」项 | agent | CUA 驱动不出 hover（本次实测）；不为此改交互语义 |

### 执行期判断（2026-10-01 回写，D-21 起续号）

> 来源都是 `agent（执行期）`：每条由实现者提出、控制器裁决接受（拍板时间见 `.workflow/p6-ui-polish/ledger.md` 的裁决区；本节只留结论、理由与代价）。**过程记录不在这里。**

| ID | 决策 | 来源 | 理由与代价 |
|----|------|------|------|
| D-21 | **回归修复：切页把面板缩走不再被误判成 hover 退出**。hover 退出判据抽成 `shouldHonorHoverExit(isOpen:lastContactRect:pointer:)`——展开态的「面板位置」= 面板与指针**最后一次接触**时观测到的窗口 rect；指针仍在这块位置里 ⇒ 这次退出是面板自己动的，不收面板；没有接触记录 ⇒ 老口径（照收） | agent | auto 高度让「切页会大幅缩小面板」成为常态后，`finishHoverExit` 只凭「指针此刻不在窗口里」判定 → 切到最矮的日历页（≈850 → ≈310，底边上移 ≈540pt）时 100% 误收（控制器实机复现 3/3）。修复只改这一处判据，切换语义 / 账本语义 / 动画语义一律未动。代价：面板缩走后有一段「粘滞区」——指针不回到面板、也不离开最后接触位置时面板保持打开，需移动指针才收（与拖动手柄那条既有形态相同） |
| D-22 | **内置空闲动画按 `name` 在渲染期解析**（`resolvedAnimation(for:)`），不按 id：`loadBundledAnimations()` 每次加载都新生成 UUID，同一份文件的「存储条目」与「新鲜条目」id 必然不同，按 id 必 miss | agent | 上屏复验发现第二层原因：存储值是写入时刻的**绝对路径**（`/Volumes/壶中天/...`），卷卸载 / 换安装位置后失效 → 面动画加载为空。`name`（= bundle 文件名，四条硬编码名单）才是内置动画的稳定身份；身份仍按存储值保留（只换 `source`），「已选择」判定与变换覆盖的键都不受影响。代价：解析不出（旧版本删过的样式）回落 `nil` → `EmptyView`（不偷偷用死路径）；设置页缩略图同病同修（补轮） |
| D-23 | **日历行高预留校准：`36N + 78` → `36N + 52`**——把「网格下方」的三段多预留（`pickerViewportHeight` 的 22、`datePicker` allowance 的 3、网格内容底部 `.padding(.bottom, 2)`）收回，并新增**防裁剪结构护栏**用例（在行高里挂真 `MonthGridView`，断言日格视口 == `36N − 6` 且网格底贴住行底） | agent | 上屏实测首页可见留白 53 = 20（设计）+ 33（行内多预留）；三处预留的来源逐项量出（真实 chrome = 标题行 24 + 间距 10 = 34；周标题行 13 + 间距 6 = 19），只能收回「多预留」不能动格内视觉。校准后 53 → 28（≤30），且不裁剪（5 周视口恰等于整月内容高）。代价：余下 ≈3.5（本地位图口径）/ ≈8（控制器口径）是 `36N` 格高、格内文字空档与抗锯齿差，再压只能动格内视觉或面板设计留白 |
| D-24 | **T6 三条实现判断**：① 不再把架子内容撑到视口高（删 `.frame(minHeight:)`）；② 面板壳 `ShelfPanel` 的圆角环由「根」改「覆盖层」；③ 网格列数用 `GridItem(.adaptive(...))` 而不是拿 `@State` 视口宽自算 | agent | ① 撑高让这一页的理想高恒等于当前视口高（不动点），面板永远缩不下来——正是本任务要修的「682 空半屏」；② 环当根时 `Shape` 在无高提案下答 10pt（实测账本收到 18）→ 面板压到 120 下限、内容反被裁；内容当根后同一夹具量到 148（= 108 + 32 + 24 − 16，逐项对得上）；③ 挂状态上第一遍布局（视口宽 0）会按 1 列量一遍，探针把「一列堆起来」的大高报进账本，等宽量到再缩又撞「光标在面板内不缩」→ 面板卡在错高度。代价：① 手动档 / 过渡帧里内容下方那块空白带不再能起框（auto 档下这块 ≈0，§明确不做 7 口径下接受） |
| D-25 | **首次打开的一拍「手动高度 → 贴合」记为既有语义**（不修）：打开是「先定尺寸、再渲染」，首开时账本还没有值 → 回落手动高度，随后那一拍补推 | agent | 本次收尾实测一次 ≈704 → 贴合、稳态贴合 ≤0.35s（§已知限制 7）；修它要让「打开」这条路等账本，等于给打开加延迟，收益不抵代价。口径与 p5 的「首帧一拍」（docs/29 §已知限制 4）同一条 |
