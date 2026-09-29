# P1 第一批：待办面板重构 + 首页块顺序可调

| 项 | 值 |
|---|---|
| 状态 | 草稿 |
| 设计分级 | **档 2 · 标准**（待办模块内部重构 + 写回系统提醒的 `priority` 字段 + 首页块排序新增一个持久化覆盖；不改对外契约） |
| 最后更新 | 2026-09-29 |
| 关联来源 | [16-nookx-reference.md](16-nookx-reference.md) §4.4（P1 第 6、7 项）；[17-nookx-adoption.md](17-nookx-adoption.md)（首页 strip / 块模型的设计记录）；[09](09-features-and-mechanisms.md) §5.8；[14](14-module-manifests.md) §1 的 todos 行 |
| 讨论入口 | 本仓库会话 |
| 读者与分界 | §背景与目标 / §明确不做 / §备选与取舍 给人读；§接口与数据形状 / §改动点设计 是**给执行者的契约**；§已知限制 / §实际交付 给后来人 |
| 本文件同时作为工作流 `p2-todos-facelift`（2026-09-29）的设计记录 | |

> **怎么读**：判断依据在 §背景与目标、§明确不做、§备选与取舍；§接口与数据形状与 §改动点设计 供执行者查考；§已知限制、§实际交付、§决策摘要 留给后来人。

---

## 一句话方案

把待办展开面板从"左侧三环竖排 + 右侧清单"升级为**左导航四视图（今天 / 最近 7 天 / 清单 / 已完成）+ 右看板（分组标题 + 计数徽标 + 行内优先级胶囊与日期）**；并让**首页块的顺序可以在设置页「组件」里调整**（覆盖 manifest 的默认 `order`）。

---

## 背景与目标

**问题现状**：① 待办展开面板现在是"三环当筛选器 + 一份清单"——环只能表达"今天 / 本周 / 所有"三个聚合量，**没有"已完成"这个视图**，也没有分组标题与计数，条目多了只能靠一条长列表；Nook X 的做法是左导航 + 右看板（[16](16-nookx-reference.md) §4.2 A 组第 4 项，本批 P1-7）。② 首页块的顺序现在**写死在 manifest 的 `defaultPlacement.order` 里**（音乐 420/日历/模块块），用户在设置页只能开关组件、不能调顺序——而"设置里开关 + 排序 → 首页拼装"正是这套组件化的完整形态（[16](16-nookx-reference.md) §4.4 P1 第 6 项）。

**为什么是现在**：首页 strip 与组件页已落地（`p2-home-strip` / `p2-p0-visible`），块的数量与可见性已经能配置，差的就是顺序；待办是目前唯一"上了首页又有展开面板"的模块，它的面板质量直接影响日常使用。

**承接关系**：本批是 [17](17-nookx-adoption.md) 的增量，不改它的结构决策（strip + 日历行、块宽、丢块规则都不动）。首页排序沿用 17 号文档 D-04 的排序键 `(order, id)`，本批只是给 `order` 加一个**用户覆盖层**。

**目标与可衡量指标**：

| 目标项 | 描述 | 可衡量指标 |
|---|---|---|
| 待办有四个视图 | 展开面板左侧能在"今天 / 最近 7 天 / 清单 / 已完成"之间切换，右侧显示对应条目 | 单元测试覆盖四个视图的取数口径；目视一次 |
| 行上有优先级与日期 | 每行显示优先级胶囊（无 / 低 / 中 / 高）与日期；点胶囊可循环修改并**写回系统提醒** | 单元测试（优先级映射 0/1/5/9 ↔ 无/高/中/低）；目视一次 |
| 首页块可排序 | 设置页「组件」里能上移/下移首页块，顺序落盘、重启保持、首页立即重排 | 单元测试（排序纯函数 + 覆盖生效）；目视一次 |

**关键约束**：不新增权限（提醒授权已有）；不改 [17](17-nookx-adoption.md) 的块宽与丢块规则；不新增模块（本批不落地 P2a 的 状态/动作类模块）。

---

## 做法

**机制一 · 四个视图共用一套取数**。现在 `TodoBucketing` 产出"今日 / 本周 / 所有"三个聚合；本批把"视图"与"聚合"解耦：视图 = `今天 / 最近 7 天 / 清单 / 已完成`，**每个视图用同一份 `store.items` 过滤**（今天 = 今天到期、最近 7 天 = 未来 7 天到期、清单 = 全部未完成、已完成 = 已完成条目），分组标题与计数由过滤后的结果算——**不新增第二套统计**（沿用 17 号文档 D-11 的口径）。

**机制二 · 优先级是 EventKit 的既有字段**。`EKReminder.priority`（0 = 无、1–4 = 高、5 = 中、6–9 = 低）；读出来映射成三档胶囊显示，点胶囊按 无 → 低 → 中 → 高 → 无 循环并写回。**写回失败不静默**：保留旧值并把失败记进模块日志。

**机制三 · 首页顺序 = manifest 默认值 + 用户覆盖**。新增一个持久化键 `homeBlockOrder: [String: Int]`（键 = 块 id：内置块用 `builtin.music` / `builtin.calendar` 之类的固定 id，模块块用模块 id），排序时先取覆盖值、没有则回落 manifest 的 `order`；设置页只提供"上移 / 下移"两个按钮（不引入拖拽，见备选）。**2026-09-30 改判（批次 `p2-takeover`）**：音乐 / 镜子搬成模块块之后，**strip 里的块只剩模块块**（`builtin.music` / `builtin.mirror` 降级为"读取时映射一次"的历史键，`builtin.calendar` 早在日历行改造后就没有接收者）；排序算法与写入口径一字未改，见 §接口与数据形状 1/2。

---

## 处理链路

以"把待办块从第 3 位移到第 1 位"为例：

```mermaid
sequenceDiagram
    participant U as 用户
    participant S as 设置页「组件」
    participant D as Defaults<br/>homeBlockOrder
    participant R as ModuleRegistry / 内置块表
    participant H as HomeStripView
    U->>S: 点「上移」
    S->>D: 写整表 homeBlockOrder = HomeBlockOrdering.table(for: 移动后的名单)
    S->>R: 写 @Default（Default 包装器自带代通知，首页/设置页各自观察）
    R-->>H: 块名单顺序变化
    H->>H: 按 (覆盖值 ?? manifest.order, id) 重排并重绘
```

> 从这张图该读出什么：**顺序的唯一权威源是"覆盖值 + manifest 默认值"这一层**，设置页与首页读同一份；**任何会出现在首页 strip 里的块都要能被排序**，因此覆盖表的键必须覆盖当时的全部块 id。**2026-09-30 改判（批次 `p2-takeover`）**：接管后 strip 里**没有宿主内置块了**（音乐 / 镜子搬成模块块 `com.cmeng.gourd.music` / `com.cmeng.gourd.mirror`，日历移到下排的独立一行、本就不参与 strip 排序），所以覆盖表今天的键**只剩模块 id**；老用户表里的 `builtin.music` / `builtin.mirror` 由读取时的 `migratingLegacyIDs` 映射到模块 id（只读不写），`builtin.calendar` 没有接收者（它已不在任何名单里）。

链路的落点：设置页按钮（§改动点设计 3）、`homeBlockOrder`（§接口与数据形状 2）、首页排序（§接口与数据形状 1）。

## 模块划分与依赖

| 单元 | 负责 | 不负责 |
|---|---|---|
| `TodosModule.swift` | 四个视图的过滤口径、左导航、看板行（优先级胶囊 / 日期） | 不负责首页块（那是既有 `.home` 分支）；不改 `TodoBucketing` 的既有三环语义（首页块仍用三环） |
| `CalendarManager`（提醒写回） | 新增"设置提醒优先级"的写回入口 | 不负责 UI、不负责优先级映射（映射在模块内） |
| `HomeStripView` | 按"覆盖 + 默认"排序后的块名单渲染 | 不知道覆盖表怎么来（只读注入的排序结果） |
| 设置页「组件」 | 上移 / 下移按钮 + 写 `homeBlockOrder` | 不直接改 manifest、不直接改首页视图 |

**已确认不反向依赖**：`HomeStripView` 不 import 设置页；`TodosModule` 不 import `HomeStripView`（沿用 06 §3.3 R4）。

## 状态机与流程

无（本批不新增状态机；待办面板的"当前视图"是纯 UI 局部状态，不需要跨模块一致）。

**并发与幂等**：优先级写回是 `EKEventStore.save`，重复点击同一档位时先比对当前值、相同则不写（幂等）；写回走 `nonisolated async` + `Task.detached`（**离开主线程**），UI 侧先乐观更新、`await Task.yield()` 之后才发起写回（保证新档位先上屏）；**失败回滚**并在 UI 上纠正，同时记模块日志。

## 横切关注点

| 关注点 | 结论 |
|---|---|
| 性能 | 四个视图共用一次 `store.items` 过滤（O(n)，n = 提醒条数，通常 < 100）；不做额外轮询 |
| 可观测性 | 优先级写回失败记 `module.todos` 的 logger（含提醒 id 与目标值）；顺序覆盖不记日志（用户操作可见） |
| 安全 | **无（理由）**：提醒数据本来就由模块读写；本批不新增数据面、不新增权限、不新增出站请求 |
| 成本 | 无 |

## 兼容迁移与回滚

| 维度 | 既有行为 | 本批之后 |
|---|---|---|
| 待办展开面板 | 三环筛选 + 清单 | 左导航四视图 + 看板；**三环仍存在于首页块**，展开面板的环改为"视图切换"的一部分（见 §改动点设计 1） |
| 首页块顺序 | manifest `order` | 覆盖值优先，未设置时行为与之前完全一致 |
| 提醒数据 | 只读写完成状态与标题/时间 | **新增写回 `priority` 字段**；用户不点胶囊就不会被写 |
| 首页 strip / 日历行 | 既有契约 | 不变 |

**旧数据语义**：`homeBlockOrder` 缺键 = 用户未表达 → 完全回落 manifest 顺序（升级用户行为不变）；键里出现的未知 id 一律忽略（模块被移除/改名时不炸）。

**回滚**：`revert` 本批提交即可；`homeBlockOrder` 残留无消费者时被忽略。

## 实际交付

**已交付**（工作流 `p2-todos-facelift`，2026-09-29；提交 `cc98aee8`…`46827fea`）。

**代码**：`Modules/TodoBucketing.swift` 加 `TodoViewKind` 与 `items(in:from:now:calendar:)`（既有三环零改动）；`Modules/TodosModule.swift` 展开面板改四视图左导航 + 右看板、新增 `TodoPriority` / `TodoPriorityOverlay` / `TodoViewSource` / `TodoDueLabel`；`managers/CalendarManager.swift` + `Providers/CalendarServiceProviding.swift` 加 `setReminderPriority`（`nonisolated async`，`save` 进 `Task.detached`）；`Host/HomeBlockOrdering.swift`（新，排序纯函数）；`Host/HomeStripView.swift` 合成名单后排序；`components/Settings/ModuleSettingsSection.swift` 加上移/下移；`models/Constants.swift` 加 `homeBlockOrder`。

**测试**：新增 22 条（T1 13 / T2 7 / T2 修复 2），全量 **253 条 0 失败**。

**文档**：本文 + `docs/09` §5.8、`docs/14` todos 行、`docs/16` §4.4、`docs/12`。

**与计划的偏离及原因**：① 优先级写回落在 `CalendarService`（不新开第二条写回链）；② 排序按钮恒显示 / 单块置灰；③ 枚举嵌在 `TodoBucketing` 内、形参用既有 `Item`（计划里的 `TodoItem` 是笔误）；④ 目视只做了"进程内渲染生产视图"的替代证据（本机长时间锁屏）。

**遗留**：屏上点击（切视图 / 点胶囊循环并重启保持 / 调顺序）待用户确认；`TodoRingPicker` 现无生产调用者（保留）；跨零点瞬间徽标与行数可能差 1；**`@Default` 驱动首页/设置页重排这一机制既无单测也无渲染证据**（执行期点名的风险）；**设置页列块的判据比首页少运行期一档**（首页还会按丢块规则隐藏尾部块，设置页只按配置级判断）。

## 已知限制

1. **只有"上移 / 下移"**，没有拖拽排序（理由见 §备选与取舍）；块多于 5 个时要按很多次。
2. **优先级只有三档 + 无**：EventKit 的 1–9 被压缩成 高/中/低，用户若在系统提醒里设置过 2 或 7 这类值，显示会归并到就近档位（**写回只在用户点胶囊时发生**，不会主动改写既有值）。
3. **"最近 7 天"按到期日算**，不包含"已过期但未完成"的条目——后者在"清单"视图里。
4. 四视图的计数与首页块三环的口径**不同**（一个按视图过滤、一个按聚合），同名不同数是设计如此。

**回写期补充（`p2-todos-facelift`，2026-09-29）**：

5. **设置页的排序按钮恒显示**（单块时置灰），与设计期写的"多于 1 个块才出现"不同——裁定接受（置灰比隐藏更好发现）。
6. **「已完成」只覆盖近 7 天**（`completedWindowDays = 7`）：文案已改为「已完成（近 7 天）」与实现一致；更早完成的历史条目当前不可见。
7. **顺序改变会连带改变"谁被丢"**：被规则③ 丢弃的是排好序之后的尾部（算法一行未改）。
8. **排序一旦动过，写的是整表**：未动过的块会脱离 manifest 的默认序号（自动排到整数表之后），此后新增/重开的块也落在整数表尾部——用户看不出问题，但"默认顺序"不再回退（`HomeBlockOrdering.swift` 的注释里有同样说明）。

## 验收标准

| 不变量 | 保证方式 | 怎么测 |
|---|---|---|
| 四个视图各自口径正确 | 过滤口径抽成纯函数，按视图枚举取数 | 单元测试（固定提醒数据 + 固定"今天"） |
| 优先级映射可逆且幂等 | `TodoPriority` 映射纯函数；同级不写 | 单元测试（0/1/3/5/7/9 ↔ 无/高/高/中/中/低 + 重复点击不产生第二次写回） |
| 首页顺序：覆盖优先、缺键回落、未知 id 忽略 | 排序纯函数 | 单元测试（有覆盖 / 无覆盖 / 未知 id / 空表） |
| 既有行为不变 | 三环首页块、折叠槽位、块宽与丢块规则不动 | 全量单测回归 + 目视 |

**成功度量**：待办面板能在四视图间切换且"已完成"能被找到；首页块顺序改完立即生效、重启保持。

## 备选与取舍

| 取舍 | 选定的做法 | 备选与没选的理由 |
|---|---|---|
| 顺序调整的交互 | **上移 / 下移按钮** | 拖拽排序：需要自己实现拖放（SwiftUI 的 `onMove` 在自定义容器里不可用），且会与面板上的既有手势抢事件；按钮成本低、可测、无手势冲突。代价：块多时要按多次 |
| 优先级的深度 | **显示 + 写回系统提醒**（三档） | 只读显示：看不到就点不动，等于半个功能；完整 1–9 九档：与"扫一眼"的定位不符，且系统提醒 App 里用户自定义的档位会被我们改写 |
| 待办视图的取数 | **复用同一份 `store.items` 过滤** | 为每个视图单独查询 EventKit：多一次 IO、口径容易漂；复用既有数据 + 纯函数过滤更好测 |
| "最近 7 天"的定义 | 到期日在 `[今天, 今天+7天)` | 含已过期未完成：会让"最近 7 天"变成"待办清单"的同义词；过期条目仍在「清单」视图里可见 |
| 本批范围 | 见 §明确不做 | 把 A2（折叠态左右槽位）一起做：**没有左右模块可用，做出来是空槽位**，看不见效果（D-04） |

## 明确不做

- **折叠态左右槽位与图标选择网格**（P1 第 5 项）：依赖状态/动作类模块（农历 / 计时器 / 剪贴板 / 启动台，属 P2a），已登记依赖（D-04）
- **拖拽排序**：只做上移/下移（理由见上表）
- **提醒的重复规则 / 子任务 / 位置提醒编辑**：本批只碰优先级，其余字段保持只读
- **改首页块宽取值、间距（8）、丢块规则与日历行**
- **改 `TodoBucketing` 既有的三环语义**（首页块仍在用）
- **给待办加"统计/打卡"类视图**（Nook X 的番茄钟统计路线，`docs/16` §4.4 归入 P2 且不推荐）
- **多提醒列表选择**（始终用系统默认提醒列表，与既有写回口径一致）

## 接口与数据形状

### 1. 排序（宿主侧）

```swift
// DynamicIsland/Host/HomeBlockOrdering.swift（新，纯函数）
enum HomeBlockOrdering {
    /// 覆盖优先、缺键回落默认值、同值按 id 字典序；未知 id 不参与
    static func sorted<T>(_ items: [T],
                          defaultOrder: (T) -> Int,
                          id: (T) -> String,
                          overrides: [String: Int]) -> [T]

    /// 历史键 → 模块 id 的读取时映射（P2 接管批次 / T4 加，见 [20](20-component-page.md) §做法 机制四）：
    /// `builtin.music` → `com.cmeng.gourd.music`、`builtin.mirror` → `com.cmeng.gourd.mirror`。
    /// **仅当新 id 在表里没有自己的值**时才搬（用户在新版里重排过就压过历史值）；
    /// **只读不写**（盘上旧键一个字节不动）、**旧键保留在返回值里**（是"加一条"不是"换一条"）；
    /// `sorted(...)` 内部第一步先过它。
    static func migratingLegacyIDs(_ overrides: [String: Int]) -> [String: Int]
}
```

### 2. 持久化

```swift
// DynamicIsland/models/Constants.swift（// MARK: Module Kernel (P1) 段）
/// 首页块的用户排序覆盖：键 = 块 id（**本批之后只剩模块 id**；历史键 `builtin.music` /
/// `builtin.mirror` / `builtin.calendar` 可以被读到，但只有前两个有接收者——见 §接口与数据形状 1 的
/// `migratingLegacyIDs`）。**缺键 = 用户未表达**，回落 manifest 的 `defaultPlacement.order`。
static let homeBlockOrder = Key<[String: Int]>("homeBlockOrder", default: [:])

// 写入口径（回写校正）：一次移动写的是**整表**——`HomeBlockOrdering.table(for:)` 把
// 「移动后的完整名单」按 0,1,2… 编号后整体写入。理由：只写被移动那一键的话，它会与
// manifest 默认值（模块 order 是 20/30/40 这类大间隔）混在一起，"屏幕上的顺序"与
// "落盘的值"就对不上了。代价见 §已知限制 8。
```

**2026-09-30 覆盖表的键词汇表（批次 `p2-takeover` 之后）**：写入口径没变（整表覆盖），但**表里出现的
id 只剩两类**——接管进来的 `com.cmeng.gourd.music` / `com.cmeng.gourd.mirror`，以及各新增模块的 id
（`…todos` / `…notifications` 等）。宿主内置块已**不再产生任何键**：音乐 / 镜子用了模块 id，
`builtin.calendar` 早已不在名单里。旧键因此只以「**读取时映射的输入**」这一身份存在
（`builtin.music` / `builtin.mirror` 映射一次、`builtin.calendar` 无人接收），盘上不会被清理
（[20](20-component-page.md) §已知限制 6 / §已知限制 11）。

### 3. 待办视图与优先级（模块内）

```swift
// DynamicIsland/Modules/TodoBucketing.swift（扩展，保持既有三环不变）
enum TodoViewKind: String, CaseIterable, Identifiable { case today, next7Days, all, completed }
/// 纯函数：按视图过滤（`now` 注入，便于测试）
static func items(in view: TodoViewKind, from items: [TodoItem], now: Date, calendar: Calendar) -> [TodoItem]

// DynamicIsland/Modules/TodosModule.swift
enum TodoPriority: String, CaseIterable { case none, high, medium, low }   // 显示用
/// EventKit priority(0…9) ↔ TodoPriority 的双向映射（纯函数）
static func priority(fromEventKit: Int) -> TodoPriority
static func eventKitValue(of: TodoPriority) -> Int
```

### 4. 提醒写回（CalendarManager 侧，新增入口）

```swift
/// 设置提醒优先级；成功返回 true。真正实现是 `nonisolated async`（`save` 进 `Task.detached`），
/// 失败不抛错——调用方据此**回滚 UI** 并记模块日志（回写校正：原写"只记日志"已作废）。
@discardableResult
func setReminderPriority(_ reminderID: String, priority: Int) async -> Bool
```

### 改动点设计

| # | 改动点 | 终态 | 落点 | 关键实现约束 | 陷阱 |
|---|---|---|---|---|---|
| 1 | 待办展开面板 | 左导航（四视图，竖排，带计数徽标）+ 右看板（分组标题 + 行） | `TodosModule.swift` 的 `TodosModuleView` 一带 | **三环不删**（首页块仍用 `TodoScopeRing`）；展开面板的视图切换用新的四视图枚举，不要复用 `TodoBucketing.Scope` 的语义 | 既有 `TodoRingPicker` 若被移除，首页块会一起没了——首页块是独立视图，但要确认引用关系 |
| 2 | 看板行 | 行 = 完成圈 + 标题 + 优先级胶囊 + 日期 | `TodoRow`（既有） | 胶囊用 `highPriorityGesture`，别与**完成圈按钮**和面板的既有手势抢；写回是异步的，UI 先乐观更新、失败回滚 | 回写校正：`TodoRow` 并没有"打开提醒"手势（原文写错），真正要防的是完成圈与面板手势 |
| 3 | 设置页「组件」排序 | 每个块一行：名称 + 上移/下移 | `ModuleSettingsSection.swift` | 按钮只在有多于 1 个块时出现；顺序落盘后要触发首页重绘（注册表重绘或本地状态） | **2026-09-30 改判**：~~内置块也要能排——覆盖表的键必须包含内置块 id~~——顺序节已收敛为**只剩模块块**（`registry.homeEntries`，T6 删掉了 `builtin.music` / `builtin.mirror` 两行与两个 `@Default`），所以这一节的"块"就是模块块；**历史键仍然要能用**：`builtin.music` / `builtin.mirror` 由 `sorted` 内部的 `migratingLegacyIDs` 映射到模块 id（见 §接口与数据形状 1），否则老用户排过的顺序会看起来"回到默认" |
| 4 | 首页排序接入 | `HomeStripView` 的块名单按新排序 | `HomeStripView.swift` | ~~内置块与模块块**合成一张名单**再排序（现在内置块是写死的三块、模块块单独投影）~~ **2026-09-30 改判**：名单**只有模块块**（`registry.homeEntries` 一处权威源——音乐 / 镜子也搬成了模块块），"合成一张名单"这半条随内置块一起消失；`sorted` 的调用形态与比较器一字未改 | 丢块规则按排好序后的尾部丢（既有行为），顺序改了丢块对象也随之变——这是正确的，但要在报告里说清 |

---

## 决策摘要

| ID | 决策 | 来源 | 理由 |
|----|------|------|------|
| D-01 | 待办展开面板改成**四视图左导航 + 右看板**，环的聚合语义保留给首页块 | 用户 | [16](16-nookx-reference.md) §4.4 P1-7（用户已选定"按优先级做下一批"）；环只表达三个聚合量、找不到"已完成" |
| D-02 | 优先级**写回 EventKit** `priority`（点击胶囊循环 无/低/中/高） | agent | 只显示不写回等于假功能；写回的是既有字段、不新增权限。代价：会在用户的系统提醒里留下我们写的优先级 |
| D-03 | 首页顺序用 **`homeBlockOrder` 覆盖表 + manifest 默认值**，界面只给上移/下移 | agent | 覆盖表缺键即回落，升级用户行为不变；不引入拖拽（见备选） |
| D-04 | 本批**不做** P1 第 5 项（折叠态左右槽位 + 图标网格） | agent | 左右槽位是给状态类/动作类模块（农历 / 计时器 / 剪贴板 / 启动台）用的，那些模块属 P2a 尚未落地——现在做出来是**空槽位**，看不见效果。应与左右模块同批落地（已登记进 [12](12-p1-batches.md)） |
| D-05 | 优先级写回落在 `CalendarService`（`nonisolated async`），不在 `CalendarManager` 内另开一条链 | agent | `CalendarManager` 只有 `calendarService` 一条提醒写回路径（`setReminderCompleted` 同路）；新开一条会产生两条写同一库的链 |
| D-06 | 写回**真异步**（`Task.detached` 里 `save`），UI 先乐观更新并 `await Task.yield()` 后发起写回；**失败回滚** | agent | 复审实测原实现是主线程同步 save（乐观值不先上屏 + 磁盘 I/O 压主线程）；宁可回滚也不要让 UI 停在错误值 |
| D-07 | 排序按钮**恒显示、单块时置灰**；「已完成」文案限定为「近 7 天」 | agent | 置灰比隐藏更好发现；文案必须与 `completedWindowDays = 7` 一致 |

---

## 附录：改动索引

| 类别 | 文件 | 动作 |
|---|---|---|
| 模块 | `DynamicIsland/Modules/TodoBucketing.swift` | 加 `TodoViewKind` 与按视图过滤的纯函数 |
| 模块 | `DynamicIsland/Modules/TodosModule.swift` | 展开面板重构 + 看板行 + 优先级胶囊与写回 |
| 管理器 | `DynamicIsland/managers/CalendarManager.swift` | 加 `setReminderPriority(_:priority:)` |
| 宿主 | `DynamicIsland/Host/HomeBlockOrdering.swift`（新） | 排序纯函数 |
| 宿主 | `DynamicIsland/Host/HomeStripView.swift` | 块的名单按新顺序排（**2026-09-30 起名单只有模块块**——音乐 / 镜子也搬成了模块块，见 §接口与数据形状 1/2 的改判行） |
| 设置 | `DynamicIsland/components/Settings/ModuleSettingsSection.swift` | 每块一行 + 上移/下移 |
| 配置 | `DynamicIsland/models/Constants.swift` | 加 `homeBlockOrder` |
| 测试 | `DynamicIslandTests/ModuleKernelTests.swift` | 视图过滤 / 优先级映射 / 排序 三组用例 |
| 文档 | `docs/09` §5.8、`docs/14` §1（todos 行）、`docs/16` §4.4（P1-6/P1-7 状态）、`docs/12` | 回写 |
