# 32 · 首页块的「玻璃板」分区（p7c）

**状态**：p7c 批次的长期设计记录（工作流的计划/账本/报告在 `.workflow/p7c-home-plates/`，收尾后消失；本文档留在版本库）。
**承接**：`docs/29`（首页块清单结构、高度账本、`HomeFlowLayout` 骨架）、`docs/30`（「浮起」机制一 / D-01 / D-02、上屏像素判据手法）、`docs/31`（D-22 底色档自适应）、`docs/26` D-10（不做每块永久卡片）。
**改判留痕**：
- ~~「不加区域块与边线」~~ **2026-10-02 p7c 改判：放宽为「不加描边、可用极淡整块底」**——用户在看到 α10/α14/α18 合成预览后选定 **α14**，并给出硬要求「内容不能超过玻璃区域」。原约束出处：docs/30 D-01（用户 p6 原话「不加区域块与边线，加样式（3D / 阴影 / 浮动之类）」）+ docs/31 D-01。
- ~~玻璃档的「浮起」＝块心柔光池（p7 白光池 / p7b 暗影池）~~ **2026-10-02 p7c 改判：改判为「极淡整块底（玻璃板）」**——两轮实测证明块心池（到块边缘归零）在毛玻璃上不表达边界；见本文 §背景与目标。

## 一句话方案

毛玻璃档（`.frostedGlass` / `.liquidGlass`）下，首页每块不再画「块心柔光池」，改为**一层极淡的整块底（玻璃板）**：黑 **0.14**、圆角 **15pt**、**无描边**，板外一圈柔和暗影、板顶缘一丝微光——**板就是块的完整框**，因此**轴对齐意义上**内容必然落在板内（板圆角弧内区的两处越界见 §已知限制 9）；hover 保留放大/提亮并把板加深到 **0.19**。纯黑档（`.solidBlack`）白光两层**逐字不变**。

## 背景与目标

**为什么做**：用户从 p7 起反复要求「鼠标不悬浮时也能分清每个区域」。p7（黑档白光池整组上调）与 p7b（玻璃档改暗影池）两轮都没做到；用户连续两次反馈「完全看不出区别」。

**根因（本轮查实，几何而非强度）**：
1. 现有机制是**块心柔光池**——径向渐变画在块**中心**，到块边缘已衰减归零（`poolEndRadius = 0.5 × min(w,h)`，渐变恰在最近边归零）。于是**块与块之间的接缝处，两侧一样亮，没有任何对比**。
2. 人眼靠**边界处的突变（台阶）**识别区域；平滑的低频明暗（跨 100+px、幅度 ≤25/255）会被视觉系统归一化，叠加毛玻璃底自身的空间漂移（同一面板不同角落差 10+/255）与桌面穿透噪声（±4–5）后彻底读不出来。
3. 取证：p7b 的暗影池**确实在用户屏幕上渲染**——在用户截图里量到块心相对本地基线 **−16~−18/255**、纵向 ±96px 平滑单谷、**无台阶**（`.workflow/p7c-region-design/evidence/`），用户仍反馈看不出。即：不是"没画出来"，是"这种画法不表达边界"。

**目标**：不 hover 时每块**一眼可辨**——板的边缘与块间缝之间出现可见台阶；且板完整包住内容、不越出面板玻璃；观感仍守「不加描边、不做卡片墙」。

**依据（2026-10 检索）**：
- Apple 对 Liquid Glass 的修正方向：**"a darkened edge and brighter specular highlights establish more depth and separation"**（更暗的边缘 + 更亮的镜面高光建立深度与区隔）——与本次"给边界一个台阶"同构（MacRumors 2026-06）。
- Apple HIG「Materials」（2026）：材料的作用是把前景与背景分开；**内容层不要用 Liquid Glass，要用 standard materials 做区分**——即"内容层的分组"靠**块状材料/底**，不是光晕。
- Gestalt「共同区域」（NN/g）：归组最强的手段是**可见的边界/容器**，且只在"留白本身不够"时才必须用它——首页是密排面板，等距留白本来就不够。
- 用户侧证据：macOS Tahoe 的公开批评里就有「看不出控件/内容从哪开始到哪结束」的同款抱怨。

**本次增量**：玻璃档的"浮起"由**块心柔光池**改判为**极淡整块底（玻璃板）**；并首次把「内容 ⊆ 板 ⊆ 面板玻璃」写成硬约束与上屏判据。黑档路径不动。

## 做法

### 机制一 · 玻璃板（新；取代玻璃档的块心柔光池）

板 = 块框上的三层视觉，全部在 `.background` / `.overlay` 里、不参与布局、不参与命中：

1. **填充**：`RoundedRectangle(cornerRadius: plateCornerRadius, style: .continuous).fill(.black.opacity(plateOpacity))`——起点 **0.14**（用户在 α10/α14/α18 合成预览上选定）。**均匀**填充（不是径向渐变），因此**板缘就是一条台阶**，这正是旧池缺的东西。
2. **柔影**：同形 `.shadow(color: .black.opacity(plateShadowOpacity), radius: plateShadowRadius, x: plateShadowX, y: plateShadowY)`——把两块之间的缝压成一条浅谷，让"两块之间的分离"在缝里也有信号（深度感）。
3. **顶缘微光**：`LinearGradient`（白 0.06 → clear，自上而下）**掩码**到同形圆角矩形，从内侧提亮板的上缘——这是"镜面高光"的那一笔。**必须用掩码软渐变，禁止 stroke**（用户从 p6 起的持续约束是「不加描边」，本批只放开「极淡无描边整块底」这一档）。

板与块的框**同框、不内缩**（**日历行也是「板 = 行框」**——D-14 的退法落地，见 D-16）：修饰符套在格子的 `.frame(width:height:)` 之后（现有结构），所以**内容在轴对齐意义上必然落在板内**（硬要求 D-03；圆角弧内区的两处越界见 §已知限制 9）；块框本身在面板内容带内，所以**板不越出面板玻璃**（D-04）。

**玻璃档的既有内容软影保留**（D-12）：p7b 给玻璃档加的内容软影（黑 0.22 / 半径 9 / y 1 → hover 0.34 / 13 / 2，经 `glow` 字段消费）**逐字不变**——它作用在**板内**的内容边缘、与板影（作用在板外的缝里）不叠加；本批只把 `.background` 的径向池换成板。**但它只装在交互站点**（D-17，见机制三）。

**内容内缩（D-20）——"板比内容宽"只能靠内缩内容**：板 = 块框，所以要让板显得比内容宽一圈，做法是**块内容在板内四周留出余量**（唯一取值处 `HomeBlockChrome.contentInsetHorizontal` / `contentInsetVertical`，加在格子与日历行的内容外层）；**板的矩形、格的尺寸与 8pt 缝一概不动**。实测夹出的取值：**水平 5pt / 垂直 0pt**——起点 6/4 都不成立：
- 6pt 时进度块（用户圈的那块）内容区 = 191 − 12 = **179pt < 180pt**（`ProgressModule` 自己声明的五档门槛）→ 五档塌成 3 行；5pt 时 181pt、余量仍有 5pt+。
- 垂直 4pt 时紧凑块（高 96pt，五档内容需 `5×14 + 4×6 = 94pt`）掉第五行 → 取 0；**上下余量沿用各块既有内边距**（再要就得改模块行高门槛/块高，另开一批）。
- **边界**：进度块分到宽须 **≥ 190pt**（180 + 2×5）；≤ 189pt 时它退化成 3 行。
- 效果（上屏实测）：7/7 块内容 ↔ 板缘左右余量 **≥ 5pt**（改前 0.0…1.5pt：音乐 0.0→5.0、统计 0.5→5.5、待办/通知 0.5→5.5）；板外窄带 0 内容像素；**T1 遗留的两处角部越界随之归零**（内容离开圆角弧内区）。

### 机制二 · 应用站点（已核实：只有两处是活的）

| 站点 | 位置 | 说明 |
|---|---|---|
| **单条流格子（唯一活块站点）** | `DynamicIsland/Host/HomeStripView.swift` 的 `HomeFlowView` 格子（`.homeBlockFloat()`，`:1216`） | 紧凑块与大块（音乐 / 待办 / 前台应用 / 进度 / 通知 / 统计；镜子若在也是大块）都走这里 |
| **日历行** | `DynamicIsland/Host/HomeCalendarRow.swift` 的根帧（`HomeCalendarRow.swift:195`） | 日历行从来不在块里（整月网格要宽度）；**只给板，不给 hover 放大/提亮**（纯展示块口径：docs/30 机制七；且它自带 `onHover`）——见 D-13；板取**「板 = 行框」**（不内缩 8pt，见 D-16） |
| `HomeStripView` / `HomeWidgetBandView` | 同文件 `:975` / `:1105` | **死代码**（全仓库零实例化，2026-10-02 核实）——**不接板**；将来若有调用方，须同时接板（见 §已知限制 7） |

日历行的板按 D-14 实测取**「板 = 行框」**（首选的内缩 8pt 会让月历题头「十月」的最左笔画落在板外 1pt，与 D-03 冲突，故走退法）——代价是日历板比上下两条流的块外缘宽 **8pt/侧**（D-16）。

### 机制三 · hover、非交互站点与黑档

- hover（交互站点）：板加深（`plateOpacity` 0.14 → `hoverPlateOpacity` 0.19）+ 既有 `scaleEffect 1.02` / `brightness 1.06` 不变；动画时长不变。
- **非交互站点**（日历行，`interactive: false`）：**只装板层**——玻璃档 = 板 + 顶缘微光；纯黑档 = **一层不装**（否则会凭空长出白光池）。不装内容软影、不装 `onHover`、scale / brightness 恒中性（D-13 / D-17）。
- 玻璃档**不再画旧柔光池**（被板取代，`poolOpacity` 恒 0）；`poolEndRadius ≤ 0.5×min(w,h)` 不变量仅黑档继续使用。
- **纯黑档（`.solidBlack`）逐字不变**：白光池 + 白内容辉光的常量、颜色、断言全部保留（零回归；用户不使用该档）。

## 备选与取舍

| 备选 | 结论 | 理由 |
|---|---|---|
| **A 玻璃板（极淡整块底 + 柔影 + 顶缘微光）** | **采纳** | 唯一在亮玻璃上给出"边界台阶"的低调机制；与 Apple 2026 的修正方向（暗边 + 镜面高光）同构 |
| B 静谧块（板 + 块内背景加厚模糊） | 不采纳（留作后续） | 边界更稳、但块内透视感变弱且实现更重；A 在合成预览上已足够（用户选定 α14） |
| C 零装饰（间距 8→16~20 + 每块 10.5pt 题头） | 不采纳 | 不碰"底/线"约束，但加字占高、边界感仍弱于 A |
| D 极淡描边（0.5pt） | 不采纳 | 边界最清楚也最省空间，但用户 p6 明确否过「边线」 |
| 把旧池"调更强" | 不采纳 | p7（白光 +11）与 p7b（黑影 −18）两轮实测都是**平滑无台阶**；加强度只加"深"，不加"边"——这正是两轮白费的原因 |
| α 取值 | **0.14** | 用户在 α10（偏轻）/ α14（清楚）/ α18（略重）三档合成预览上选定；上屏实测台阶幅度随底色浮动（7.7…29.4/255，比值恒 ≈14%），未上调（D-15） |

## 明确不做

- 不加任何描边（stroke / 发丝线 / 亮边线）；顶缘微光必须是掩码软渐变
- 不动布局：块宽 / 块高 / 间距 8pt / `HomeFlowLayout` / `HomeStripLayout` 骨架 / 面板尺寸
- 不动黑档观感（`.solidBlack` 白光两层逐字不变）
- 不做 B（块内加厚模糊）、C（题头/间距）、D（描边）
- 不动 hover 的 `hoverScale` / `hoverBrightness` 口径（只加深板）
- 不给日历行加 hover 放大/提亮、不给非交互站点加内容软影（纯展示块口径）
- 不新增 TCC 权限、不新增网络请求、不引第三方库
- 本批无新增/改动文案（不动 `Localizable.xcstrings`）
- 不改面板底色三档本身（`NotchPanelBackgroundStyle`、`PanelFrostedGlassBackground` 不动）
- 不给两个死结构（`HomeStripView` / `HomeWidgetBandView`）接板
- 本批**不修**圆角弧内区的两处内容越界（§已知限制 9）——修法都属改设计或动布局
- 不做"每块内容各自换排版"（内容布局不在本批范围）

## 决策摘要

| 编号 | 决策 | 来源 |
|---|---|---|
| D-01 | 玻璃档改「极淡整块底（玻璃板）+ 柔影 + 顶缘微光」，取代块心柔光池 | 用户（选定 α14 档；方向 A 为 agent 推荐、经用户采纳）+ agent |
| D-02 | 取值：板黑 0.14 / hover 0.19；圆角 15pt；影 10 / x1 / y2 / 黑 0.9；顶缘微光白 0.06 | 用户（α14）+ agent（其余取值） |
| D-03 | 板 = 块的完整框，**内容必须全部落在板内**（轴对齐口径；角部见 §已知限制 9） | 用户（原话「要考虑内容不能超过玻璃区域」） |
| D-04 | 板不得越出面板玻璃（板框 ⊆ 面板可见玻璃区） | 用户 + agent |
| D-05 | 顶缘微光用掩码软渐变实现，不用 stroke | agent（守「不加边线」） |
| D-06 | 纯黑档白光两层逐字不变（零回归） | agent |
| D-07 | 应用站点 = 单条流格子（`HomeFlowView`）+ 日历行（`HomeCalendarRow`）；两个零实例化的死结构不接板并记账 | agent（经独立计划审查核实） |
| D-08 | 玻璃档不再画旧柔光池；`poolEndRadius` 不变量仅黑档沿用 | agent |
| D-09 | hover 保留 scale 1.02 / brightness 1.06，只加深板 | agent |
| D-10 | 本批无新增/改动文案（不动 catalog） | agent |
| D-11 | 逐块上屏核验三层包含（内容 ⊆ 板 ⊆ 面板玻璃） | agent（用户硬要求的验证方式） |
| D-12 | 玻璃档既有内容软影（0.22/9/1 → hover 0.34/13/2）逐字保留（**仅交互站点**） | agent（任务审查 W2） |
| D-13 | 日历行的板**不带 hover**（不装 `onHover`、scale/brightness 恒中性）——纯展示块口径 | agent（任务审查 W1） |
| D-14 | 日历行的板优先与单条流块外缘对齐（左右各内缩 8pt）；与内容冲突则退到行框，实测记账 | agent（任务审查 W1） |
| D-15 | **A1 判据改相对口径**（台阶幅度 ≥ 12% 局部基线 + 跃变 ≤ 4px；绝对幅度随底色浮动，实测 7.7…29.4）；板 α 保持用户选定的 0.14，不上调 | agent（首轮任务审查 Important；用户选定值不变） |
| D-16 | 日历行的板最终取 **「板 = 行框」**（D-14 的退法落地）：内缩 8pt 时月历题头最左笔画落在板外 1pt，D-03 优先 | agent（D-14 预授权 + 上屏证据 `glass-plate-inset8-conflict.png`） |
| D-17 | **非交互站点只装板层**（玻璃档：板 + 顶缘微光；纯黑档：一层不装）——不装内容软影、不装 hover | agent（守 §机制二「只给板」；修复波） |
| D-18 | 删 `glassPoolOpacity` / `glassHoverPoolOpacity`（零引用，取值仍留 `docs/31` 与 p7b 证据）；`plateIsDark` 保留（当前两档同值 true，语义为"板色"，黑档靠 α = 0 生效） | agent（修复波卫生 + 审查 Minor 8） |
| D-19 | 圆角弧内区的两处内容越界（音乐块左上 15 / 通知块左上 5 个内容像素，其余 26 角 0）**本批不修**，记 §已知限制 9 | agent（终审裁定；修法属改设计/动布局） |
| D-20 | 首页块**内容内缩**（板比内容宽）：水平 **5pt** / 垂直 **0pt**（起点 6/4 均被实测否掉：6 破进度块 180pt 门槛、4 掉第五行），日历行只做水平；板的尺寸、位置与 8pt 间距一概不动 | 用户（原话「每个玻璃块要比内容宽一些，现在都紧挨着显示了」；板 = 块框，故只能内缩内容） |

## 接口与数据形状

### 1. `HomeBlockFloatMetrics`（唯一取值处）——玻璃板常量族

```swift
// 玻璃板（p7c / docs/32 §做法 机制一）——逐值与上屏实现一致
static let plateOpacity: Double = 0.14             // 板填充的黑不透明度（用户选定 α14）
static let hoverPlateOpacity: Double = 0.19        // hover 加深一档
static let plateCornerRadius: CGFloat = 15         // 板圆角（面板圆角 − 内容内边距的近似）
static let plateShadowOpacity: Double = 0.9        // .shadow 色不透明度（× 板 α → 有效影深 ≈ 0.126，为推断值）
static let plateShadowRadius: CGFloat = 10
static let plateShadowX: CGFloat = 1
static let plateShadowY: CGFloat = 2
static let plateTopHighlightOpacity: Double = 0.06 // 顶缘微光（掩码软渐变，非描边）
static let plateTopHighlightFraction: CGFloat = 0.45 // 微光在板高上的覆盖比例（自上而下到 clear）
// 已删（D-18）：glassPoolOpacity / glassHoverPoolOpacity——玻璃档 p7c 起不画池
```

### 1b. `HomeBlockChrome`（内容内缩；D-20）

```swift
enum HomeBlockChrome {
    static let contentInsetHorizontal: CGFloat = 5   // 块内容与板缘的水平余量（板 = 块框，故靠内容内缩）
    static let contentInsetVertical: CGFloat = 0     // 垂直 0：紧凑块 96pt、五档内容需 94pt，再让会掉行
    static func contentInsets(includeVertical: Bool) -> EdgeInsets  // 两个站点共用的唯一工厂
}
```
- 两处应用：`HomeFlowView` 格子（`HomeBandCell` 内容外层，`includeVertical: true`）与 `HomeCalendarRow` 根（`includeVertical: false`——月历网格按行高精确排，垂直内缩会裁）。
- 上屏实测（`evidence/inset-measure.txt`）：左右余量 7/7 块 ≥ 5pt、无裁切/溢出、缝仍 8pt、黑档同形（布局共享，黑档内容同获内缩）。

### 2. `FloatEffects` 新增字段与两档语义

```swift
let plateOpacity: Double        // 玻璃档 = 板 α（hover 更深）；黑档 = 0（不画板）
let plateCornerRadius: CGFloat
let plateShadowOpacity: Double
let plateShadowRadius: CGFloat
let plateShadowX: CGFloat
let plateShadowY: CGFloat
let plateTopHighlightOpacity: Double
let plateTopHighlightFraction: CGFloat
let plateIsDark: Bool           // 板色语义（当前两档同值 true；黑档靠 plateOpacity == 0 不画板）
// 既有字段语义：黑档沿用 pool 与 glow；玻璃档 poolOpacity = 0（不画池）、
// glow 字段**仍被消费但仅在交互站点**（内容软影 0.22/9/1 → hover 0.34/13/2，逐字不变——D-12 / D-17）。
static func effects(hovered: Bool, surface: Surface, interactive: Bool = true) -> FloatEffects
// interactive == false（日历行）：返回**常驻档**（与 hovered 无关），scale / brightness 恒中性（D-13）。
//   注意：黑档的这份常驻档在**非交互站点上无消费者**——只装板的站点在黑档不消费任何层（D-17 / §已知限制 10）。
```

### 3. `HomeBlockFloatModifier` 契约

- **交互站点**（`interactive == true`）：
  - `.glass`：既有内容 `.shadow`（0.22/9/1 → hover 0.34/13/2）+ `.background`（板：圆角矩形黑填充 + 上述 `.shadow`）+ `.overlay`（顶缘微光：`LinearGradient(white 0.06 → clear)` 到 `plateTopHighlightFraction`，`.mask` 到同形圆角矩形）。不画池；`.scaleEffect` / `.brightness` / `.compositingGroup()` / `.animation` / `.allowsHitTesting(false)` 语义不变。
  - `.dark`：白光池 + 白内容辉光**逐字不变**。
- **非交互站点**（`interactive == false`，日历行）：**只装板层**——玻璃档 = `background(板)` + `overlay(顶缘微光)`；纯黑档 = 原 `content`（一层不装）。无内容软影、无 `onHover`、无 scale / brightness（D-17）。
- 入口：`func homeBlockFloat(interactive: Bool = true)`。底色档来源不变：`@Default(.notchPanelBackgroundStyle)` → `HomeBlockFloatMetrics.surface(for:)`。

### 4. 应用站点（逐字）

活站点两处：`HomeStripView.swift` 的 `HomeFlowView` 格子（`.homeBlockFloat()`，`:1216`；`interactive` 默认 true）与 `HomeCalendarRow.swift:195`（`.homeBlockFloat(interactive: false)`，板取「板 = 行框」，见 D-16）。两个死结构（`HomeStripView` `:975` / `HomeWidgetBandView` `:1105`）不接板。

### 5. 测试

`DynamicIslandTests/HomeStripLayoutTests.swift`：
- `testHomeBlockFloatMetricsStayInTheLegibleRange`（`:2151`）：黑档全部既有断言**逐字保留**（含 `idle.poolOpacity ≥ 0.08` 这类**只对黑档成立**的区间）；玻璃档分支（板 0.14 / hover 0.19 且 hover − idle ≥ 0.03、板 α ∈ 0.10…0.22、圆角 ∈ 10…20、板影半径 > 0、微光 ∈ (0, 0.2) 且 fraction ∈ (0, 1)、玻璃档 `poolOpacity == 0`、`plateIsDark == true`、`interactive == false` 时与 hover 无关）；
- `testGlassSurfaceUsesDarkVeilEffects`（`:2253`）：玻璃档板 α > 0、hover 严格更深、内容软影三值逐字（0.22 / 9 / 1 → 0.34 / 13 / 2）、玻璃档池为 0；黑档板为 0 且 `poolOpacity == HomeBlockFloatMetrics.poolOpacity`、`poolIsDark == false`；
- `testHomeBlockPoolRadiusNeverCrossesTheNearestEdge`（`:2295`）：保留（黑档池不变量）。

## 验收标准

- **A1** 毛玻璃档：板缘与相邻缝之间存在**台阶**——幅度 **≥ 12% 局部基线**（机制 = 按局部底色固定比例暗化，比值恒 ≈14%；绝对幅度随底色浮动，本机实测 **7.7…29.4/255**）且跃变宽度 **≤ 4px**（实测 0…1pt；对比：旧池跨 100+px 平滑、无台阶）。D-15。
- **A2** 板心均匀：板内不同位置的差值 ≤ 5/255（实测中心 − 两侧 ±1.5/255；旧池同测法 −13.0）。
- **A3** 逐块核验：每块**内容包围盒 ⊆ 板框**（轴对齐口径；板外 4pt 窄带 0 内容像素，7/7 块）——圆角弧内区另见 §已知限制 9。
- **A4** 板框 ⊆ 面板可见玻璃区（含右缘与下缘；实测最小余量 14.5pt）。
- **A5** 纯黑档逐字回归：缝 0.00 / 块内落光区 27.9（min 22 / max 33）/ 扫描单调归零——与 p7b 留档一致。
- **A6** 单测：玻璃板常量与两档语义（含 hover 更深、`interactive: false` 与 hover 无关、黑档不受影响）、池半径不变量。
- **A7** 全量测试 ≥ 502 用例全绿、退出码 0。
- **A8** hover 观感：列「需真人鼠标复核」（不可合成驱动）。
- **A9** 证据：上屏截图（毛玻璃全幅 + ≥2 处 1:1 特写）、逐值测量记录（台阶 / 三层包含 / 板心均匀度 / 日历行板取法 / 角部核验）、黑档回归截图、`notchPanelBackgroundStyle` 还原读回。

## 已知限制

1. hover 不可合成驱动（CUA 限制，p6/p7 既有口径）→ 纯函数钉住 + 真人复核。
2. `.liquidGlass` 档未上屏（本机不使用；与 `frostedGlass` 同走 `.glass`，机制同源）。
3. 黑档仍是块心白光池（旧机制）——它在"表达边界"这件事上同样不成立，本轮未动（零回归优先）；要统一另开一批。
4. 板不透明度在**极亮桌面**（满屏白色窗口）下观感可能偏轻；反向地，**暗桌面**上绝对台阶小（实测最弱 7.7/255）——调参窗口 0.14 → 0.16/0.17。
5. 顶缘微光在低亮度屏 / 高亮桌面下的观感需真人复核；它也会吃掉一点上缘的台阶幅度（上缘实测 11.3…17.2，弱于左/右/下缘的 13.7…29.4）。
6. 板本身不带"可点"语义（纯展示块沿用既有口径：不做 hover 底、不加边框）。
7. 两个死结构（`HomeStripView` / `HomeWidgetBandView`）不接板——**将来若有调用方，须同时接板**，否则会出现"有的块有板、有的没有"。
8. 日历行与单条流块的外缘差 8pt/侧：本批取「板 = 行框」（D-16）。
9. **圆角弧内区的两处内容越界**（D-19）：按实际形状模型（连续圆角 n=5），`行1·音乐块左上` 15 个、`行2·通知块左上` 5 个内容像素落在**板形状之外**（其余 26 角为 0）。成因：这两块的**内容本身贴着块框**（板内余量 0.0 / 0.5pt，是既有排版），而新板的 15pt 圆角把角切掉——**内容位移未变，但"内容画在板外"这一现象由本批的板形状引入**。量与视觉影响都极小（14% 黑纱上约 7.5 / 2.5 pt²）。修法（缩小圆角 / 给内容加内边距 / 把板立到内容之外）都属改设计或动布局，本批不做；D-03 的「内容 ⊆ 板」是**轴对齐口径**。
10. `effects(hovered:surface:interactive:)` 在 `interactive == false × .dark` 下返回一份**无人消费**的常驻档（含黑档白光池 0.13）——黑档的非交互站点在 modifier 里一层不装（D-17）。将来若有人复用 `effects` 画黑档非交互站点，会凭空长出白光池，需在此处挡差。
11. 板影的有效深度（≈0.126）是**推断值**（`plateShadowOpacity × plateOpacity`），未逐像素实测。
12. **垂直余量为 0**（D-20）：上下沿用各块既有内边距（2.5 / 4.0 / 8.5 / 0.5pt 不等）；要再加垂直余量必须先改模块的行高门槛或块高——不在本批范围。
13. **内缩与进度块门槛耦合**：进度块分到宽 ≤ 189pt 时会从五档退化成 3 行（内容区 = 宽 − 2×5 必须 ≥ 180）。块序/宽度分配一变就可能命中（`Plan` 的宽度分配改了要复核）。
14. **内容辉光/软影随内缩内移**（D-20 的自然结果）：玻璃档的内容软影与黑档的内容辉光照的是**内容剪影**，位置随内容内移 5pt；黑档白光池按 frame 短边算、位置不变。本批未量这一层的像素差。

## 实际交付

**交付物**
- 代码（T1：commit `cb27903..90bb280`；T2：commit `fef3d9b1..9c44e442`）：`DynamicIsland/Host/HomeStripView.swift`（T1 常量族 + `FloatEffects` 板字段 + `effects(hovered:surface:interactive:)` + 修饰符两分支 + `homeBlockFloat(interactive:)` + 删两个死常量；T2 `HomeBlockChrome` 内容内缩 + 格子内容外层 padding）、`DynamicIsland/Host/HomeCalendarRow.swift`（T1 根帧接板 `interactive: false`；T2 水平内缩套在 `GeometryReader` 外）、`DynamicIslandTests/HomeStripLayoutTests.swift`（黑档断言逐字保留 + 玻璃档分支 + 两条用例改钉 + T2 的 `testHomeBlockContentInsetStaysInRange`（含两条**行为观测**：流站点按探针断言内容宽、日历行站点按网格宿主坐标位移断言））。
- 常量族（9 值）：`plateOpacity 0.14` / `hoverPlateOpacity 0.19` / `plateCornerRadius 15` / `plateShadowOpacity 0.9` / `plateShadowRadius 10` / `plateShadowX 1` / `plateShadowY 2` / `plateTopHighlightOpacity 0.06` / `plateTopHighlightFraction 0.45`。
- 证据（`.workflow/p7c-home-plates/evidence/`）：`glass-plate-full.png`、`glass-plate-closeup-{row1,row2,calendar,seam-6x,leftedge-6x}.png`、`glass-plate-inset8-conflict.png`（D-16 的上屏依据）、`black-regression.png`、`glass-plate-restored.png`、`restored-glass.txt`、`plate-measure.txt`（台阶 / 三层包含 / 板心均匀度 / 角部核验 / 去软影前后 / 日历行取法）、探针与测量脚本 `p7c-{probe,rects,ratio,measure}.py`。
- 测试：全量单测 `Executed 502 tests, with 0 failures`（退出码 0）。
- 文档：本文档。

**与计划的偏离**
1. **D-14 取「板 = 行框」退法**（口径变化 + 上屏依据见 D-16）。
2. 实现中一度引入的 `plateHorizontalInset` 参数**已删除**（恒 0、无消费者）。
3. 非交互站点由「玻璃档保留内容软影」收紧为「只装板层」（D-17，守 §机制二「只给板」）。

**遗留项**
- hover 实际观感（需真人鼠标复核；不可合成驱动）。
- `.liquidGlass` 档未上屏（机制同源）。
- 极亮 / 极暗桌面下的板强度（调参窗口 0.14 → 0.16/0.17；见 §已知限制 4/5）。
- 圆角弧内区两处内容越界（§已知限制 9，D-19：本批不修）。
- 两个死结构未接板（§已知限制 7）。
- 黑档非交互站点的一份无消费者 effects 常驻档（§已知限制 10）。
- 板影有效深度为推断值、未逐像素实测（§已知限制 11）。
