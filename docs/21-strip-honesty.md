# 首页丢块提示与「通知 × 到底关了什么」

| 项 | 值 |
|---|---|
| 状态 | **已实现**（2026-09-30；实机观感与「点下去之后真关闭的返回」两条现场证据未取得，见 §实际交付 遗留项） |
| 最后更新 | 2026-09-30（回写；实现提交 T1 `8eafb8be` / T2 `d23ede48`，末笔 T2 修复 `c6799692`；范围见 §实际交付） |
| 关联来源 | [17-nookx-adoption.md](17-nookx-adoption.md) §已知限制 22（丢块没有 `+N` 提示，**本批已落地**，该条已就地改判）/ §做法 机制三；[16-nookx-reference.md](16-nookx-reference.md) §4.2 的 A3 行；[12-p1-batches.md](12-p1-batches.md) §已交付 · `p2-honesty` |

> **怎么读**：§背景与目标 / §明确不做 / §备选与取舍 是判断依据；
> §接口与数据形状 是执行者的契约（参考型，可跳过）；§已知限制 / §实际交付 留给后来人。
>
> **读者分界**：给人读的是背景、取舍、不做的部分与限制；§做法 的机制与 §接口与数据形状
> 是给执行者与模型的契约，精确到不用再做设计决策。

## 一句话方案

两处「界面没说清楚」，各修一处：**首页 strip 因为放不下而整块丢掉的块，在条尾给一个小提示**
（`＋N`，悬停列名——拉宽面板就能看到它们）；**通知的 × 把「会不会真的关掉系统通知」说清楚**——
浮层与列表行各自都有两档（近 10 秒内有同指纹句柄时顺带真关闭、否则只从列表/岛上移除），
文案按同一个判据分档，用户点之前就能知道结果。

## 背景与目标

### 现状（改前）

**一、丢块是静默的。** 首页 strip 的规则 ③ 在宽度不够时从尾部整块丢弃
（[17](17-nookx-adoption.md) D-03：丢块比压扁更可读），这是设计行为；但**用户看不到"被丢了"**——
770pt 面板下最多三块，第四块开始无影无踪，界面上没有任何"这里还有东西"的线索。
`p2-p0-visible` 那批解决的是"开关开了却什么都没出现"的错觉（组件卡写了效果行），
**这一条是它的镜像**：东西存在、只是没地方放，而界面同样不说。

**二、通知的 × 有两种结果，界面只说一种。** 通知模块有两条取数通道：AX 通道（实时横幅，带"关闭句柄"）
与数据库通道（降级），见 [17](17-nookx-adoption.md) 与 `docs/09` §5.5。**浮层**的 × 在有句柄时真关闭系统通知、
无句柄时只能"从岛上隐藏"；**展开列表行**的 × 在近 10 秒内找到同指纹句柄时**也会顺带真关闭**
（`NotificationStore.dismiss` → `closeSystemBanner`），否则只从列表移除。两处入口看起来一模一样，
文案却都只有一句笼统的「关闭」——用户点下去之前无从判断，点完之后也无从知道"我的通知是不是还在"。

### 预期结果（改后）

- 首页 strip 放不下时，**条尾出现一个 `＋N` 小提示**（N = 被丢掉的块数）；鼠标悬停显示被隐藏的块名
  （例如「待办、通知」），用户据此知道"把面板拉宽就能看见"。
- 被丢块的**布局行为一字不变**：还是从尾部丢、还是不滚动、还是不压扁；提示用的宽度是**额外预留**的
  （只有本来就会丢块时才预留；边界处可能因此多丢一块，见 §已知限制 6）。
- 通知的 × **两处入口各自两档、共四格**（§做法 机制四的表）：句柄在 → 「同时关掉系统通知」，
  句柄不在 → 浮层「关闭」、列表行「从列表移除」；文案与无障碍标签同口径，`docs/09` §5.5 与
  `settings.modules.effect.notifications` 那行效果说明同步。

### 承接关系与本次增量

**承接** [17](17-nookx-adoption.md)：丢块规则（D-03）、`Plan.leftover` 的口径、stale 的 `.clipped()`/零提案
约定（已知限制 12~19）全部不变，本批只**在尾部加一个提示位**。通知那一半承接 `docs/09` §5.5 的能力边界
（"能显示、能点击打开 App"）与 [17](17-nookx-adoption.md) 的 AX/DB 双通道结论。

**本次增量**：`plan(…:tailReserve:)` 的预留语义与 `Plan.droppedCount` / `tailReserveUsed` 两个字段；
`HomeStripView` 的提示视图与"名单同源"重构；通知 × 的语义表与文案修正。

## 做法

### 机制一：预留尾位（纯函数里决定，不在视图里拍脑袋）

`plan` 多一个入参 `tailReserve: CGFloat`（缺省 0 = 今天的行为，既有用例逐字不变）与两个出参：
`droppedCount`（被丢块数）与 `tailReserveUsed`（这次是否真的占了尾部预留位）。判定**三步且确定**：

1. 先按完整可用宽度算一次（**基线**）。基线没丢块 → 原样返回，`tailReserveUsed = false`（预留位不存在）。
2. 基线丢了块、且 `tailReserve > 0` → 按 `available - tailReserve` 再算一次（**预留版**）。
   预留版还能显示 ≥1 块 → 返回预留版，`tailReserveUsed = true`。
3. 预留版一块都放不下（宽度太小）→ 返回基线（提示不显示：连块都没有的时候，一个孤零零的 `＋N` 没有意义）。

**为什么预留在算术里而不是在视图里**：视图只能看到"分配后的结果"，它不知道"如果不预留会不会一样丢"。
把判定放进纯函数，三条路径才都能被单测穷举（也避免"提示挤掉了本可显示的块"这种反向 bug）。

### 机制二：名单同源（视图与 Layout 不能各算一份）

`HomeStripView` 自己也要知道 `droppedCount`（它要画提示），而 Layout 内部同样算一次 plan。
让两者一致的办法不是"都调同一个函数"（那仍可能喂不同的输入），而是**把宽度声明收成一处**：
视图先算出**非可选**的 `[HomeBlockWidth]`（每块都有了确定值：内置块写死、模块块取
`registry.homeBlockWidth(for:)` 的声明、没有声明就回落宿主的 `180/240`），再把它转成
`[HomeStripLayoutMath.Item]` **交给 Layout**（`HomeStripLayout(items:tailHintWidth:)`）——
Layout 因此不再从 subviews 取声明，也不再测量（测量回退只在 `items` 为空时保留，当前无生产调用）。
同一个数组既喂 plan、也喂 `HomeStripBlock(width:)`，视图与 Layout 于是拿到同一组 items、
同一个宽度（视图取 `GeometryReader` 的宽、Layout 取 `proposal.width`，两者都是父级给的同一条 strip 宽度）。

### 机制三：提示视图长什么样

`＋N` 一枚小胶囊，**贴在条尾**（`x = available - droppedHintWidth`，顶部对齐）——
**不要用 `leftover` 反推坐标**：`leftover` 的口径是"未被使用的尾部空间总量"，[17](17-nookx-adoption.md)
已知限制 11 明确写了"宿主不得据此做居中或对齐"，而且丢块路径下按缩减后宽度算会越界。
悬停用 `.help()` 列出被隐藏块的名称（名称来自 `HomeBlock.name`——本批给 `HomeBlock` 加这个字段：
内置块取 `String(localized: "Music"/"Mirror")`，模块块取 `ModuleHomeEntry.label`）。
视觉上刻意低调（`white.opacity` 的边与字）：它是"这里还有东西"的线索，不是主内容。

### 机制四：通知 × 的结果写清楚（先取证，再改文案）

本批不动通知的取数与关闭实现，只**把结果说准**。**四种组合**（不是三档——列表行与浮层一样
也有「顺带真关闭」的情况，`NotificationStore.dismiss` 在近 10 秒内找到同指纹 AX 句柄时会调
`closeSystemBanner`，`docs/09` §5.5 早已写对）：

| 入口 | 有（近 10s 内同指纹）句柄 | 没有句柄 / DB 通道 |
|---|---|---|
| 折叠态浮层的 × | 真关闭系统通知（`performAndVerify` 轮询确认元素失效）+ 撤浮层；**失败**（横幅早已自动消失 / 动作名随系统改版失效）**不弹错误**，只在 `closeSystemBanner` 记一条 warning、退化为「仅从岛上隐藏」 | 仅从岛上隐藏（**不弹错误、也不写日志告警**），系统通知中心不动 |
| 展开列表行的 × | **顺带真关闭那一条** + 从列表移除（失败同上，退化为「只从列表移除」） | **只从列表移除**（不动系统通知） |
| 浮层卡片本体 | 打开对应 App + 撤浮层 | 同左 |

文案因此按**同一判据**分档：句柄在 → 「同时关掉系统通知」，句柄不在 → 「从列表移除」/「关闭」。
判据由 store 提供（一个只读谓词），文案与行为因此由同一个布尔量决定，不会各说各话。
`module.notifications.readOnlyNote` 那段「两条通道都可能随系统改版失效」的说明保留并核对。
**若实测发现本机 AX 真关闭失败**（报告里要有日志证据），文案降级成「尝试关闭系统通知，失败则仅隐藏」
并把这条写进 §已知限制——**不假装它一定关得掉**。

## 备选与取舍

**① 丢块提示：尾部 `＋N` / 覆盖在最后一块上的角标 / 不提示只改设置页文案？**
选 **尾部 `＋N` + 预留位**。角标会压住最后一块的内容（首页块都是"读一眼"的信息，压住就是损失）；
只改文案解决不了"此刻有东西没显示"这个当下问题。预留位的代价是**多一次纯函数计算 + 边界处可能多丢一块**
（**首块放得下时**——即可用宽 ≥ 首块最小宽——规则 ③ 在丢失路径下把每块宽度取各自的 `min`、与可用宽度无关，
所以预留**不会**让块变窄，只可能改变丢块数；可用宽 < 首块最小宽时规则 ③ 的「单块取 `max(0, available)`」
兜底会让预留版更窄，属调用方违约、生产不可达）——换来的是"提示永远不与块重叠"。

**② 预留位的宽度取值：固定 34pt / 按块数伸缩？** 选**固定**。提示只需要放下 `＋N`（N 是一位数到两位数，
32~36pt 足够）；按块数伸缩会让"预留多少"变成一个猜谜游戏，而且丢得越多提示越大、越挤——与目的相反。

**③ 通知那一半：顺手改成"列表行的 × 也真关闭"？** 否——**它本来就会**（近 10s 内有同指纹句柄时
`dismiss` 会顺带真关闭）。本批要做的只是**把这个既有事实写进文案**：句柄在 → 「同时关掉系统通知」，
句柄不在 → 「从列表移除」。**不动 `dismiss` 的条件真关闭**（那是行为，不是文案）。

**④ 通知实测做不到（机器锁屏 / 没有新通知）怎么办？** 那就只做**代码取证**（读两条通道的实现与既有实测注释），
文案按代码事实写，并在 §已知限制 里写明"真关闭这一条没有本批的现场证据，来自实现与历史实测"。

## 接口与数据形状

### 1. `HomeStripLayoutMath.plan`（纯函数，新增一个入参两个出参）

```swift
public struct Plan: Equatable {
    public let widths: [CGFloat]          // 既有：下标对应输入 items 的前 visibleCount 项
    public let visibleCount: Int          // 既有
    public let leftover: CGFloat          // 既有：未被使用的尾部空间总量
    public let droppedCount: Int          // 新增：items.count - visibleCount
    public let tailReserveUsed: Bool      // 新增：本次是否真的占了尾部预留位
}

/// - Parameter tailReserve: 尾部预留位宽度（`< = 0` 视为不预留）。
///   只在「基线会丢块、且预留后仍能显示 ≥1 块」时生效；`visibleCount` 已扣掉它。
public static func plan(
    items: [Item],
    available: CGFloat,
    spacing: CGFloat,
    tailReserve: CGFloat = 0        // 缺省 0 = 今天的行为（既有用例不改）
) -> Plan
```

**实现期补充（T1 报告 §6 候选 1，已按契约落进代码注释）**：判定第 ③ 步（预留版一块都放不下 →
退回基线）**今天不可达**——规则 ③ 对非空 `items` 至少保住第一块（`keep` 停在 1，落点
`visibleCount >= 1`），所以 `guard reserved.visibleCount >= 1` 恒真。它按契约保留为防御分支
（规则将来变化时有一条确定行为），**不是**可清理的死代码。`leftover` 的口径**未改**：
预留版按缩减后的宽度算——「这一份 plan 的未使用尾部空间」，渲染侧不得拿它反推提示位坐标（[17](17-nookx-adoption.md) 已知限制 11）。

### 2. `HomeStripLayout` / `HomeStripView`（宿主）

```swift
struct HomeStripLayout: Layout {
    /// 本次要摆的块宽（**由视图传入**：视图已经把每块的宽度解析成确定值，Layout 不再从 subviews 取声明、也不测量）
    var items: [HomeStripLayoutMath.Item] = []
    /// 尾部预留位宽度（与 `plan(…:tailReserve:)` 同值；唯一取值在 `HomeStripView.droppedHintWidth`）
    var tailHintWidth: CGFloat = 0
    // Cache 里的 plan 复用判据要**同时**包含 available 与 tailHintWidth（只看 available 会在预留位变化时复用旧 plan）；
    // items 的失效另由 updateCache 负责
}

// HomeStripView
static let droppedHintWidth: CGFloat = 34          // 预留位宽度（唯一取值，视图持有；Layout 只收 tailHintWidth）
private func blockWidths(for blocks: [HomeBlock]) -> [HomeBlockWidth]   // 非可选：模块取 registry.homeBlockWidth(for:) 的声明 ?? 宿主的 180/240
private func droppedNames(_ blocks: [HomeBlock], visibleCount: Int) -> [String]   // 名称来自 HomeBlock.name
// 提示视图（`plan.tailReserveUsed` 为真时画）：Text(verbatim: "＋\(count)") + 低调胶囊（white.opacity 的边与字）
// + .help(被丢块名以「、」连接)，frame(width: 34, alignment: .trailing)、offset(x: available - droppedHintWidth)

// HomeBlock 新增一个字段（本批）
private struct HomeBlock: Identifiable {
    let id: String
    let name: String        // `.help()` 的文案来源：**只取 `ModuleHomeEntry.label`**（宿主侧已无内置块，
                            // 机制三给的 `String(localized: "Music"/"Mirror")` 那一档**没有落点**，未写）
    let defaultOrder: Int
    let content: ModuleContent
}
```

**同源的另一半**：`items` 与 `HomeStripBlock(width:)` 用的是同一个 `[HomeBlockWidth]`（`body` 里解析一次），
Layout 只在 `items` 为空时才回头读 `HomeBlockWidthKey` / 测量——今天没有这样的生产调用点（退路保留）。
视图那一份 plan 取 `GeometryReader` 的宽、Layout 那份取 `proposal.width`，两者是同一条**确定性提案**的宽度。
Layout 在提案宽度为 `nil` 时走 `naturalWidth(of: cache.items)` 兜底（按各块理想宽度之和当可用宽度），
兜底那一份可能与视图这份 plan 不一致——生产提案恒为确定值，这条兜底只在非生产调用下可能命中。

### 3. 通知文案（`DynamicIsland/Localizable.xcstrings`）

| key | 用在哪 | 取值来源 | en | zh-Hans |
|---|---|---|---|---|
| `module.notifications.removeFromList`（新增） | 列表行 ×，无句柄 | 谓词为 false | "Remove from list" | "从列表移除" |
| `module.notifications.dismiss`（沿用） | 浮层 ×，无句柄 | `handle == nil` | "Dismiss" | "关闭" |
| `module.notifications.closeSystemNotification`（沿用） | 浮层 × 与**列表行 ×**，有句柄 | `handle != nil` / 谓词为 true | "Close the system notification too" | "同时关掉系统通知" |

谓词按**实现期定下的最终形态**（`NotificationStore` 上）：

```swift
/// 列表行 × 的**唯一一份判据**：这一刻命中的真关闭句柄（nil = 只从列表移除）。
/// 行为侧（`dismiss` 真的拿它去关）与文案侧（谓词只问真假）都调这一个函数。
private func listRowCloseHandle(for item: NotificationItem, now: Date = Date()) -> NotificationBannerCloseHandle?

/// **只读谓词**（文案专用）：近似于 `listRowCloseHandle(...) != nil`；只查不改
/// （视图在 body / `.help()` 里直接读它安全，不触发 `objectWillChange`）。
func willAlsoCloseSystemBanner(for item: NotificationItem, now: Date = Date()) -> Bool
```

落到视图上：列表行 × 的文案有**唯一落点** `dismissHelpKey`（谓词真 → `closeSystemNotification`、
假 → `removeFromList`），悬停（`.help`）与读屏（**本批新增的 `.accessibilityLabel`**，此前只有 `.help`）
同读这一份。浮层 × 仍是两个通道各自的 `closeHelpKey` 三元（DB 通道 / AX 通道各一处，**本批未动**——
它只有 `.help`、没有无障碍标签，留在 §实际交付 遗留项）。谓词的口径边界如实写进代码注释：
它回答的是**查询那一刻**的答案，句柄随 10 秒窗口过期（§已知限制 11）。

## 明确不做

| 不做的事 | 为什么 |
|---|---|
| 改丢块规则本身（横向滚动 / 分页 / 压到更小 / 换行） | [17](17-nookx-adoption.md) D-03 已定"丢块比压扁更可读"；本批只让丢块可见 |
| 提示做成可点击（点击跳设置页改顺序 / 展开被丢块） | 提示是"知道了"的线索，不是入口；做入口要先定"点了去哪"，不属本批 |
| 改通知的取数、去重、HUD 展示策略 / `NotificationStore.dismiss` 的条件真关闭行为 | 与本批目标无关（本批只动文案与措辞；条件真关闭是既有行为，文案负责把它说清） |
| 面板最小宽度/默认宽度调整 | 与"看得见丢块"无关；用户可自己拉宽（提示就是告诉他这一点） |
| 给设置页顺序节加"当前是否可见"标记 | 顺序节列的是**全部**块（不管此刻能不能显示），加标记要引入运行期条件，容易抖动 |

## 实际交付

**提交**：本批范围 `682b4bd8..c6799692`（**4 个提交**：T1 `8eafb8be` → T2 `d23ede48` → T3 文档回写 `14261efe` →
**T2 修复** `c6799692`（新 key 进解析名单），范围因此非连续——修复那一笔夹在 T3 之后；本批未 push）。

**交付物**：

| # | 产物 | 落点与形态 |
|---|---|---|
| 1 | `HomeStripLayoutMath` 的新入参与出参 | `plan(items:available:spacing:tailReserve:)`（第四参缺省 `0` = 改动前的行为）+ `Plan.droppedCount` / `Plan.tailReserveUsed`；三条规则本体**原样**搬进私有 `distribute`（基线与预留版共用），既有 17 条用例一行未改 |
| 2 | `HomeStripView` 的同源重构 | `droppedHintWidth = 34`（视图持有唯一取值）；`blockWidths(for:)` 非可选（同一个数组既喂 `HomeStripBlock(width:)` 也转成 `items`）；`HomeStripLayout` 改收 `items` + `tailHintWidth`（测量回退只在 `items` 为空时保留），Cache 复用判据同比 `tailHintWidth`；`body` 套 `GeometryReader` 算一次 plan |
| 3 | 条尾 `＋N` 胶囊 | `tailReserveUsed` 时画在 `x = available − droppedHintWidth`（顶部对齐、`white.opacity` 的低调胶囊、`Text(verbatim:)`）；悬停 `.help` 列被丢块名（`HomeBlock.name`，只取 `entry.label`） |
| 4 | `HomeStripLayoutTests` **+4 用例** | 不丢块不预留（富余档 + 压缩档）/ 生产档 702（基线 3 块、预留后仍 3 块、`droppedCount == 1`）/ 边界档 660（3 → 2 块）/ 缺省 0 与显式 0、负值等价；**17 → 21 条** |
| 5 | 通知侧谓词与两处文案 | `NotificationStore.listRowCloseHandle(for:now:)`（私有，唯一判据）+ 只读谓词 `willAlsoCloseSystemBanner(for:now:)`；`dismiss` 首行改调私有函数（行为一字未改）；列表行 × 的 `.help` + **新增 `.accessibilityLabel`** 按 `dismissHelpKey` 分档；新 key `module.notifications.removeFromList`（中英、`state = translated`，catalog 共 1539 key）；`readOnlyNote` 中英各改一句 |
| 6 | `docs/09` §5.5 四格表 | 「通知 × 的四种结果」小表（入口 × 有无句柄 → 行为 + 失败降级）+ 表下段（失败降级、单一谓词分档、「查询那一刻」的口径） |

**与计划的偏离及原因**：

1. **`HomeBlock.name` 只剩一个来源**（计划写了两档：内置块 `String(localized:)` + 模块块 `entry.label`）：
   宿主侧早已没有内置块（`p2-takeover` 把音乐 / 镜子搬成模块块），那一档**没有落点**——未写死代码，
   机制三那句描述在 §接口与数据形状 2 订正，并在 §已知限制 9 留一句指针。
2. **判定第 ③ 步不可达**（规则 ③ 至少保住第一块）：按契约保留为防御分支并注明不可达，
   见 §接口与数据形状 1 的补充。
3. **`＋N` 不进 xcstrings**（D-06）；悬停分隔符写死全角「、」（代价：英文界面上出现全角顿号。
   要修得给分隔符选一个 key，与 D-06 同批做）。
4. **真机点击取证未做**（D-05 触发，无现场证据）：本机跑着的 Gourd 是已安装的 Release 实例（不是本仓调试产物），
   它的 DB 通道当前被 TCC 拒绝（造不出列表行）；用 `osascript` 造的通知 10 秒内也没进 AX 探针
   （判断为本机此刻无横幅上屏）。因此「点下去之后 `performAndVerify` 的返回」这一条只有实现与
   `docs/09` 的 2026-09-28 实测记录支撑（§已知限制 4）。
5. **浮层 × 的 `.accessibilityLabel` 未补**：派发片段只点了列表行，未扩到浮层——同源的读屏缺口仍在（遗留项）。
6. **提示位的实机观感未确认**：`＋1` 只在纯函数与用例里验证（§已知限制 12）。

**遗留项**（人工验收或后续批次）：

- **实机 `＋1` 观测**：770pt 面板 + 四块 → 条尾 `＋1`、可见块数仍 3（需要「音乐有会话 + 摄像头可用 + 两个模块块都有内容 + 展开面板」这一组合）。
- **真机点击通知的现场证据**（`performAndVerify` 的返回）：本批无（偏离 4）。
- **两处无自动化断言**：`HomeStripLayout` 的 Cache 复用判据、通知侧**谓词**（新 key 的那一半已由 `c6799692` 补进解析名单，见 §已知限制 9/10）。
- **浮层 × 的无障碍标签缺口**（与谓词同源，一行改动即可补）。
- **提示位宽度若动态化**（按 `droppedCount` 变宽）必须同时补 Cache 判据的端到端验证（§已知限制 9）。

## 已知限制

1. **提示位宽度固定 34pt**：`＋N` 的 N 到三位数（>99 块）时会截断——现实中首屏块数不会到那个量级，
   发生也不影响"还有东西"这个信息。
2. **丢块的判定只看宽度**：面板高度不足时整条 strip 不画（`HomeStripView.minimumUsableHeight`），
   那种情况**没有**任何提示（条都不存在，也就没有"条尾"）。这是既有行为的延续，本批不改。
3. **列表行的 × 只在"近 10 秒内有同指纹句柄"时真关闭系统通知**：更早的通知（或数据库通道的那批）
   没有句柄，点 × 只从列表移除——这是**既有实现的事实**，本批用文案把它说清（不再伪装成"一律关闭"）。
   真正的"逐条 AX 查找 + 失败回退"属后续批次。
4. **通知 × 的真关闭行为本批以代码取证为准**：若实现期无法在真机上产生一条通知（锁屏 / 无新通知），
   "真关闭"这一条只有实现与历史实测的支撑，没有本批的现场证据。
5. **`.help()` 的悬停提示在刘海面板里依赖 AppKit 的 tooltip**：面板是非激活窗口，个别系统版本上 tooltip
   出现较慢（秒级）——文案本身仍可通过无障碍标签读到（列表行 × 的无障碍标签已随本批补上；**浮层 × 仍只有悬停
   文案**，见 §实际交付 遗留项）。
6. **预留位在边界处可能多丢一块**：基线已经丢块、且可用宽刚好够基线那几块时，预留 34pt 会把尾部再挤掉一块
   （例：可用宽 660、**三块**的最小宽 300 + 140 + 180 = 620 加两个间距 2×8 = **636** → 基线 3 块，
   预留后 626 → 2 块）。这是 D-02 的确定行为：
   **宁可少显示一块，也要把"还有 N 块"说出来**。770pt 面板（≈702）下不发生。
7. **提示只回答"有几块没显示"，不回答"怎么让它们显示"**：拉宽面板是唯一的办法，提示里没有入口（§明确不做）。

**回写期补充（2026-09-30，实现期真正踩到的边界）**：

8. **「浮层 × 无句柄」这一格不写任何日志**（实现事实，正文那张表回写时已按代码订正）：`presentNotificationHUD` /
   `presentBannerHUD` 的 `guard let handle else { return }` 之后没有日志，内核撤浮层只记一条 info。
   排查「点了 × 但系统通知还在」看的是「关闭系统通知失败」那一行有没有——**有** = 有句柄但 `performAndVerify`
   判负（退化为仅隐藏），**没有** = 这一格本来就只有「仅从岛上隐藏」。把两者混起来会让人去找一条不存在的日志。
9. **`HomeStripLayout` 的 Cache 复用判据没有自动化断言**：`Layout.Subviews` 无法手工构造（用例只能测纯函数），
   判据里漏掉 `tailHintWidth` **不会有用例变红**——变异验证实测（T1 报告 §3 ②：去掉该判据后全量仍 315 条全绿）。
   今天 `tailHintWidth` 是常量（恒 34），生产路径上没有「同 available、不同 tailHintWidth」的输入，因此那行判据
   目前是防御性的；**将来把提示位宽度变成动态值时，必须补端到端验证**。另：机制三那句「内置块取
   `String(localized:)`」随宿主内置块归零而过时，实际只有 `entry.label` 一个来源（§接口与数据形状 2）。
10. **通知侧的新谓词仍没有自动化断言，新 key 已有**：变异验证实测（T2 报告 §4）——谓词恒 false 时全量用例
    **无一条变红**（本批没有任何用例断言这个谓词，也没断言列表行文案分档）；**新 key 那一半已由 `c6799692` 处置**——
    `module.notifications.removeFromList` 已加进 `DynamicIslandTests/ModuleKernelTests.swift:3062` 的解析名单，
    同一变异（从 `Localizable.xcstrings` 删掉该 key）现在让 315 条里**恰 1 条变红**
    （`testNotificationsLocalizationKeysResolve`，实到值即原始 key——正是"漏编 catalog 时 `.help()` /
    `.accessibilityLabel` 把原始 key 直接显示给用户"这种静默降级形态）。文案分档本批只经人工核对
    （补断言的落点见 §实际交付 遗留项）。**→ 已补上（`p3-freeze` 的 T5，2026-09-30）**：
    `DynamicIslandTests/ModuleKernelTests.swift` 的 `testNotificationListRowClosePredicateFollowsCloseHandleWindow`
    覆盖谓词的三档（有句柄 → true / 无句柄 / 超 10 秒 → false），**同一变异（谓词改成恒 false）现在会红**；
    上面那句"无一条变红"是补口之前的实测记录，原样保留（它正是补口的理由）。
11. **`.help` 的文案在渲染时求值，可能比点击结果乐观**：谓词回答的是**查询那一刻**的答案，句柄随 10 秒窗口过期；
    行渲染与用户悬停之间跨过窗口边界时，文案会说「同时关掉系统通知」而点击实际只移除。接受它（不为它引入
    10s 级重渲的定时器，D-08），边界同时写在 `docs/09` §5.5 表下那段。
12. **提示位的观感与 `＋1` 没有本批的实机观测**：位置（`x = available − droppedHintWidth`）、配色与「不与可见块
    重叠」都是算术 + 用例保证的，屏上观感属人工验收；实机复现还需要「音乐有会话 + 摄像头可用 + 两个模块块
    都有内容 + 展开面板」这一组合（§实际交付 遗留项）。

**`p2-home-fit` 补充（2026-09-30，实测）**：

13. **`＋N` 与实际空白块数一致——已由实机截图 + 宿主级用例钉住**（`p2-home-fit` 的 T4，详见
    [23](23-home-fit.md) §已知限制 4/7）：770pt 面板 + 四块（音乐 300 + 三个 180/240 的模块块）→ 屏上 2 块 + `＋2`
    （另 2 块零尺寸）；900pt → 3 块 + `＋1`；1088pt → 四块齐、**无 `＋N`**。用例把**真的 `HomeStripView`** 挂进
    `NSHostingView` 跑布局，断言「拿到尺寸的块数 == `plan.visibleCount`、空白块数 == `plan.droppedCount`」
    （变异：去掉 `HomeStripView` 里那句把提案宽钉在可用宽上的 `.frame(width: available, …)` → **9 条断言红**）。
    这同时补上了第 12 条的**实机观感**：`＋N` 与"还有几块没显示"在屏上对得上（`evidence/t4-770-fixed.png` /
    `t4-900.png` / `t4-1088.png`）。**反向提醒**：`＋N` 为 0 不等于"块都画出来了"——`p2-home-fit` 修复前
    770pt 下就出现过"视图那份 plan 算 2 块、Layout 那份只摆 1 块，而视图照显 `＋2`"（两份 plan 的输入宽度
    不同：尺寸反馈，根因与修法见 [23](23-home-fit.md) §已知限制 4）。

**`p3-freeze` 补充（2026-09-30，冻结批次）**：

14. **`＋N` 的悬停 tooltip 在非激活面板里出现较慢，是观感而不是缺陷**：列被丢掉的块名靠 `.help(_:)`
    （AppKit tooltip），而刘海面板是**非激活窗口**——tooltip 由系统在"应用是否处于激活态"这套判定下调度，
    这里可能**秒级**才浮出来（与第 5 条同一根因，那条说的是通知列表行 × 的悬停文案；`＋N` 这一处的
    触发面积更小、更容易被读成"悬停没反应"）。**这是现有实现的观感边界，不是丢块的语义问题**：
    ① 提示本身（`＋N` 这个胶囊）在屏上照常可见，悬停只是"想知道是哪几块"的附加信息；
    ② 面板一旦是激活态（点过、正在交互）tooltip 就正常；
    ③ 拉宽面板让块自己显示出来仍然是唯一的信息入口（第 7 条）。
    本批**不改代码**（改它要自定义 tooltip 或自己起一个浮层，成本远超"秒级时延"这个代价；同 D-08 的取舍），
    只把它记在这里，并写进 [25-release-smoke.md](25-release-smoke.md) 的 S10 观感注——发布冒烟时
    **不要把"悬停半天才出列名"记成不通过**。

**`p3-widgets` 补充（2026-09-30，分带布局之后）**：

15. **「`＋N` 与空白块数一致」在分带之后仍成立**（第 13 条那条契约**没有被分带打破**）：分带把「丢块」**限制在主块带**（仍沿用旧 strip 的三条规则与 34pt 预留位），小组件带改走**贪心换行**——放不下就换行，**只有连一行都放不下时才丢块**并计入 `＋N`。实测（T7 上屏，面板 1154×630 / 900×630 / 770×630，开的是音乐 + 待办 + 前台应用 + 进度 + 通知 + 统计）：
    - **1154（默认档，可用宽 1086）**：主块带 1 块（音乐）、小组件带 **5 块一行**、日历行在、**`＋N` = 0**——修复前同一档是一条 strip 可见 5 块、第 6 块（统计）被丢且条尾 `＋1`（`t2-default-width-all-blocks.png` 是那半帧的反证）。
    - **900 / 770（可用宽 832 / 702）**：主块带 1 块、小组件带 **两行（3 + 2）**、`＋N` 都是 **0**——「换行而不是消失」的直接证据（702 下 `180×3 + 2×8 = 556 ≤ 702 < 180×4 + 24 = 744`）。
    - 高度档也有对应：560 高 → 日历行先让位（两带都在）；300 高 → 只留小组件带；两档的 `＋N` 仍是 0。
    - **用例侧**：宿主级渲染真值仍在守同一条契约——`testEveryPlanVisibleBlockGetsItsWidthAcrossPanelWidths` 沿用 `assertRenderedSizesMatchPlan`（可见块 == plan 的分配宽、被丢块 == 零尺寸、**空白块数 == `droppedCount`**），只是入参宽度在 T8 之后改为「带内可用宽 = 托管宽 − 2 × `containerInset`」（702 → 686，行内压缩解 228.5 → 223；**判据没变、代入的数变了**）；`testWidgetBandRendersTwoRowsAtNarrowPanelWidth` 另钉「四块都拿到尺寸、没有一块是零尺寸、行高恒 96」。**变异**：把 `HomeBandedLayout.wrappedRows` 的换行改回「放不下就丢」→ **26 条红**，其中渲染真值里第 4 块实到 **0.0**（就是"被隐藏掉"的复现）。
    - **仍要记住第 13 条的反向提醒**：`＋N` 为 0 只在「plan 说全可见」时有意义；分带之后这句话的检查点是**两条带各自的 plan**（主块带与小组件带各一份），宿主级那两条用例测的是主块带路径、小组件带走 `renderBandedWidgets` 的路径（两条都有渲染真值）。

## 验收标准

1. `xcodebuild test`（`DynamicIslandTests`）**退出码 0、315 条 0 失败**；`HomeStripLayoutTests` **21 条**
   （既有 17 条一行未改 + 新增 4 组）：不丢块不预留、丢块且预留生效（**可见块数与基线相同**）、
   丢块且预留把尾部再挤掉一块（可用宽 660 的边界用例）、`tailReserve` 缺省 = 今天的行为。
2. 预留位的三条路径由上面的用例逐值钉死（生产档 702 / 边界档 660 / 缺省 0 等价，见 §实际交付 交付物 4）；
   **770pt 面板下的 `＋1` 观感留人工验收**（§已知限制 12）。
3. `grep -n "module.notifications.removeFromList" DynamicIsland/Modules/NotificationsModule.swift DynamicIsland/Localizable.xcstrings`
   两处各命中（`NotificationsModule.swift:1274`、`Localizable.xcstrings:82032`）；列表行 × 的文案按 store 谓词分档
   （句柄在 → `closeSystemNotification`），判据取**新增的谓词名**
   （`grep -n "willAlsoCloseSystemBanner" DynamicIsland/Modules/NotificationsModule.swift`：定义 `:422` + 调用点 `:1272`）。
4. `docs/09` §5.5 的四格语义表与代码事实一致（含「列表行在近 10 秒内有同指纹句柄时顺带真关闭」这一格与失败降级）；
   `settings.modules.effect.notifications` **未改**——它只讲呈现位置（铃铛 / 首页块 / 列表），与关闭口径不冲突。

## 决策摘要

| ID | 决策 | 来源 | 理由 |
|---|---|---|---|
| D-01 | 丢块提示 = 条尾 `＋N` 胶囊（**锚在尾部边缘**，不用 `leftover` 反推坐标）+ 预留位 | agent | 提示不得压住块内内容；`leftover` 的口径是「未使用的尾部空间」，docs/17 已知限制 11 明令宿主不得据此对齐（§备选与取舍 ①②） |
| D-02 | 预留位只在「基线会丢块」且「预留后仍能显示 ≥1 块」时生效；`tailReserve` 缺省 0 = 今天的行为；边界处可能因此多丢一块（记已知限制 6） | agent | 不预留时布局一字不变；一块都放不下时提示没有意义（§做法 机制一） |
| D-03 | 宽度声明**同源**：视图把每块宽度解析成非可选值、转成 `items` 交给 `HomeStripLayout`，Layout 不再取声明/测量；`HomeBlock` 新增 `name`（悬停列名的来源） | agent | 避免「提示的 N 与真实丢块数不一致」与「Layout 与视图各算一份」（§做法 机制二） |
| D-04 | 通知的 × **只改文案、不改行为**：按 store 谓词分档——句柄在 → 「同时关掉系统通知」（列表行本来也会真关），句柄不在 → 列表行「从列表移除」、浮层「关闭」 | agent | 列表行的 × **本来就有条件真关闭**（`NotificationStore.dismiss` 近 10s 同指纹句柄），把它写成"只移除"会用一句假话换掉真话（§备选与取舍 ③） |
| D-05 | 真关闭若实现期无法现场复现，按代码取证写文案并记进已知限制 | agent | 宁可写「没有现场证据」，不假装它一定关得掉（§备选与取舍 ④） |
| D-06 | `＋N` **不进** `Localizable.xcstrings`（`Text(verbatim:)`）；悬停只列**已被注册表本地化**的块名 | agent（执行期） | 符号 + 数字语言无关，走 key 会让 catalog 凭空多一条待翻译条目；仓库先例 `DynamicIslandCalendar.overflowRow` 的 `+N`（代价：要写成句子时得新增 key，分隔符也一并本地化） |
| D-07 | 句柄判据**抽成私有函数两处共用**：`listRowCloseHandle` 同时服务 `dismiss`（行为）与 `willAlsoCloseSystemBanner`（文案） | agent（执行期） | 判据复制成两份就会「文案说真关、行为只移除」；两处共用一个布尔量是 D-04「文案不说假话」的机制保证 |
| D-08 | 悬停 / 无障碍文案接受「渲染时求值」的边界乐观：不为它引入 10s 级重渲 | agent（执行期） | `.help(_:)` 只吃固定串，悬停时求值要自定义 tooltip，成本远超本批；窗口仅 10s，且行渲染通常晚于句柄登记（DB 落盘晚于 AX 约 5s）。代价 = 跨窗口边界时文案偏向「会真关」一侧（§已知限制 11） |
