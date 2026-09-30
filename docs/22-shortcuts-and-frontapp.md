# 快捷指令与前台应用联动：两个新内置模块

| 项 | 值 |
|---|---|
| 状态 | 已实现（2026-09-30） |
| 最后更新 | 2026-09-30 |
| 关联来源 | [14-module-manifests.md](14-module-manifests.md) §1 的 `shortcuts` 行与 §4.1；[09-features-and-mechanisms.md](09-features-and-mechanisms.md) §5.4；[16-nookx-reference.md](16-nookx-reference.md) §4.2 A 组第 5 项（A5 前台应用联动）/ §4.4 P1 第 8 项；[12-p1-batches.md](12-p1-batches.md) §下一批登记 |

> **怎么读**：§背景与目标 / §明确不做 / §备选与取舍 是判断依据；
> §接口与数据形状 是执行者的契约（参考型，可跳过）；§已知限制 / §实际交付 留给后来人。
>
> **读者分界**：给人读的是背景、取舍、不做的部分与限制；§做法 的机制与 §接口与数据形状
> 是给执行者与模型的契约，精确到不用再做设计决策。

## 一句话方案

给刘海加**两个新模块**：**快捷指令**（展开面板一个 tab：搜系统快捷指令、点一下跑、固定常用的；
取数走 `/usr/bin/shortcuts list --show-identifiers` 并把结果缓存进配置，运行时 `shortcuts run <identifier>`
限时 30s、禁止并发）；**前台应用联动**（首页一块：当前前台应用的图标与名称 + 最近切换过的几个，
点小图标切回去——事件源是 `NSWorkspace` 的「某应用被激活」通知，零私有 API）。两个都默认关，
在设置 → 组件里打开。

## 背景与目标

### 现状（改前）

- **快捷指令**：`docs/14` §1 早就登记了 `com.cmeng.gourd.shortcuts`（P2b 第 3），`shortcuts:run` 也在
  06 §7.1 的能力白名单里，但**一行实现都没有**（[16](16-nookx-reference.md) §4.1 的审计把"已对齐"那条
  更正过）。用户日常在系统「快捷指令」里编好的流程，今天没有任何上岛的入口。
- **前台应用联动**：`docs/16` §4.2 A 组第 5 项——Nook X 前后两次迭代都在做它（2026.06.13 / 08.21），
  说明"岛跟着前台应用变"是被需要的；我们完全没有。它在 `docs/12` 的下一批登记里，与"折叠态左右槽位"同批
  讨论过：**槽位形态**（在岛侧显示前台应用图标）随左右槽位一起被降级（用户 2026-09-29 决定），
  但**首页块形态**不受那个依赖影响，本批就做它。

### 预期结果（改后）

- 设置 → 组件里多两张卡：**快捷指令**（默认关）与**前台应用**（默认关）；打开后：
  - 快捷指令：展开面板多一个「快捷指令」tab——搜索框 + 刷新按钮 + 列表（固定项在最前）；
    点一行的运行按钮跑它，行内出现运行中状态与结果（成功/失败/超时 + 输出前几行，输出回显受 `showOutput` 控制）；
    右键固定/取消固定；**首次打开且缓存为空时自动拉一次列表**，之后只在点刷新时起子进程。
  - 前台应用：首页多一块——当前前台应用的大图标 + 名称，下面是最近切换过的几个小图标；
    点小图标把那个应用切到前台。刚启动还没有历史时只显示当前应用。
- 两个模块都**不新增任何权限**：快捷指令零 TCC（首次运行可能弹系统自动化提示，属既有边界），
  前台应用只用公开的 `NSWorkspace` 通知与 `NSRunningApplication`。

### 承接关系与本次增量

**承接** `docs/09` §5.4 的四条硬口径（用 identifier 而不是名称、结果缓存进配置并提供手动刷新、
子进程限时 30s + 禁止并发、`--output-path` 读回输出）与 `docs/14` T-12 的 manifest 取值口径；
前台应用联动承接 `docs/16` §4.2 A5 的"建议形态"里的**首页块**一半。

**本次增量**：缓存键 `cachedShortcuts`（存**原始行**，解析只有一份）、结果模型与超时/并发闸门、
前台应用历史（去重 + 上限 + 排除自身）与首页块形态；槽位形态（折叠态侧槽）仍属左右槽位那批。

## 做法

### 机制一：快捷指令的取数、缓存与解析

**取数只有一条命令**：`/usr/bin/shortcuts list --show-identifiers`，输出每行 `<名称> (<identifier>)`
（本机实测：`外观-浅色 (24D4F870-7022-4ECA-B2C0-8BBF3A434398)`）。名称里可以含空格，甚至含括号，
因此解析规则定死：**从行尾往回找第一个 ` (`**，"(" 之前是名称、括号内是 identifier；不满足这个形状的行
直接丢弃（不猜）。

**缓存存原始行**：配置键 `cachedShortcuts`（`list` of `string`，默认 `[]`）保存的是**命令输出的原始行**，
不是解析后的对象——解析函数只有一份，读缓存与读命令走同一条路（`ShortcutListParser.parse(lines:)`），
格式化或解析规则将来变了不会与缓存格式打架。**进入 tab 不取数（不起子进程）**：
`load()` 只读一次本地 config 里的 `cachedShortcuts`（读偏好，不扫盘、不起子进程），
只有「首次进入且缓存为空」与「点刷新」两处会起子进程。

### 机制二：运行、限时与禁止并发

运行 = `shortcuts run <identifier>`；`showOutput` 为真时追加 `--output-path <临时文件>`，跑完读回临时文件
（读完即删），过大只取前 N 行并在结果里注明截断。**限时**用 `timeoutSeconds`（默认 30s）：
超时 → `terminate()` 并把这次结果记成「超时」，**不重试**；
失败时把 stderr 摘要放进 `failureMessage`（系统原话，不吞、不猜）。**禁止并发**是模块级的一个闸门
（`isRunning`）：一次只允许一条在跑，运行期间其它行的运行按钮禁用、刷新按钮也禁用
（刷新会换掉正在跑的那条的 identifier 语义）。

### 机制三：前台应用的历史与首页块

事件源是 `NSWorkspace.shared.notificationCenter` 的 `didActivateApplicationNotification`
（公开 API，零权限）。取应用名与图标走 `NSRunningApplication`（`localizedName` / `bundleURL` →
`NSWorkspace.icon(forFile:)`）；**排除本应用自己**（否则每次点开刘海都把壶中天自己记成"最近应用"）。

历史的口径是纯函数：**按 id 去重 + 移到最前 + 截到上限**（`maxRecentApps`，默认 5，夹取 3…8）。
当前应用与历史都放在 store 里（`@Published`），首页块视图只读它；点一个小图标 =
`NSRunningApplication(processIdentifier:)?.activate()`（已是前台的点了是空操作，不报错）。

### 机制四：两个模块都是"普通模块"，不碰内核

两个模块都走既有内核：`manifest` 字面量 + `content(for:)` + `builtinModules` 加一行 +
`defaultEnabled = false`。**不新增 surface、不新增 capability、不改内核**：
快捷指令用 `expanded`（展开 tab），前台应用用 `home`（首页块），两者都在
`docs/06`/`docs/14` 已定的词汇表内。

## 备选与取舍

**① 快捷指令的标识：名称还是 identifier？** 选 **identifier**（`docs/09` §5.4 已定）。
名称可重复、可随时改；identifier 稳定。代价是列表里必须把名称一起解析出来给人看（机制一）。

**② 运行用 `run` 还是 `open`？** 用 `shortcuts run`（可限时、可读输出、可传 `--input-path` 给将来的
shelf 联动）。`open` 会把快捷指令 App 拉到前台，与"岛内跑一条流程"的产品意图不符。

**③ 输出：`--output-path` 读回，还是捕标准输出？** 读回文件（`docs/09` §5.4 已定）。
`shortcuts run` 的标准输出不是所有动作都会写（"显示结果"类动作才写），而 `--output-path` 是统一契约。

**④ 前台应用联动：首页块还是折叠态侧槽？** 首页块。侧槽形态依赖"折叠态左右槽位"，那一项已被用户
降级（2026-09-29）；首页块不依赖它，且不抢中央槽位（那块归待办）。侧槽留给左右槽位那批。

**⑤ 首页块里放几个最近应用？** 默认 5、可配 3…8。放太多会挤掉"当前应用"这个主角
（块宽固定 180/240，图标一行排不下几个）。

## 接口与数据形状

### 1. 快捷指令：解析、取数、运行与落点（`DynamicIsland/Modules/Shortcuts/`）

> **回写（2026-09-30）**：本节按落地代码校正。文件落点是 `ShortcutCatalog.swift`（纯逻辑：条目 / 解析 /
> 过滤 / 结果模型）、`ShortcutRunner.swift`（两个注入点与两个真实现）、`ShortcutsModule.swift`（manifest 与
> store、视图）；实现比设计多出 `ShortcutRunResult.maxOutputLines` / `ShortcutsStore` / `ShortcutsModuleView`
> 三件，**既有签名一个未改**。

```swift
/// 一条系统快捷指令（`identifier` 是稳定身份，`name` 只用于显示）。
struct Shortcut: Equatable, Identifiable { let identifier: String; let name: String; var id: String { identifier } }

enum ShortcutListParser {   // 落点：ShortcutCatalog.swift（无 Process、不 import AppKit / SwiftUI）
    /// `shortcuts list --show-identifiers` 的原始行 → 条目。
    /// 规则：从行尾找第一个 ` (`；名称非空、identifier 非空；形状不符的行丢弃（不猜）。
    /// **两侧都去首尾空白后再判空**（`"   (0F0F)"` 这种「名叫空格」的行不是条目）。
    static func parse(lines: [String]) -> [Shortcut]
}

/// 搜索与排序（纯函数，视图不另写逻辑）：固定项在前（保持固定表顺序），其余保持命令给出的顺序；
/// 搜索对 `name` 与 `identifier` 都做不区分大小写的包含匹配。
enum ShortcutFiltering {
    /// 三条实现口径（§决策摘要 D-08）：**搜索先于排序**（固定项也要过搜索）/ 固定表里已不在清单里的
    /// id 跳过（同一 id 只出现一次）/ 查询词去首尾空白后为空即不过滤。
    static func visible(_ shortcuts: [Shortcut], pinned: [String], query: String) -> [Shortcut]
}

/// 一次运行的结果。
struct ShortcutRunResult: Equatable {
    enum Outcome: Equatable { case success, failure, timedOut }
    /// 输出回显的行数上限：**截断在 runner 侧做一次**，视图直接显示 `output`、不重算行数
    /// （§决策摘要 D-11 / §已知限制 9）。
    static let maxOutputLines = 40
    let outcome: Outcome
    let output: String          // showOutput 关时是空串；开时是输出文件内容（截断到 maxOutputLines 行）
    /// 失败/超时的**说明**：失败时是 stderr 摘要（系统给的原话，见 §已知限制 1）——去空白、最多 3 行、
    /// 多了加省略号；**系统没给 stderr 时是 `exit <退出码>`**（不编一句像人说的话，见 §决策摘要 D-13）。
    /// 超时时是 `module.shortcuts.timedOut` + ` · <限值>s`（复用结果标签那条 key，不另造新 key）。
    /// 成败都要显示它——这一栏是"失败时把系统的原话摆出来"的载体。
    let failureMessage: String
    let duration: TimeInterval
}

/// 取数的注入点（默认走真命令；单测给构造的行）
typealias ShortcutsListing = @MainActor () async -> [String]
/// 运行的注入点（默认走真子进程；单测给构造的结果）
typealias ShortcutsRunning = @MainActor (_ identifier: String, _ timeout: TimeInterval, _ captureOutput: Bool) async -> ShortcutRunResult
```

**落点（比设计多出两件，都是实现口径）**：`ShortcutsStore`（`@MainActor ObservableObject`：六个
`@Published` —— `shortcuts` / `pinned` / `isRunning` / `runningIdentifier` / `lastResult` / `isLoading`；四个
动作 —— `load()` 幂等读缓存、`refresh()` 先落盘再发布、`togglePin(_:)` 先落盘再换内存、`run(_:)` 走闸门；
取数与运行两个注入点在 `init` 里给默认真实现，用例给假体）与 `ShortcutsModuleView`（顶部搜索框 + 刷新按钮
+ 列表 + 底部结果行；搜索词是 **UI 局部 `@State`**，不进 `Defaults`）都在 `ShortcutsModule.swift`。
`ShortcutsModule.moduleID` = `"com.cmeng.gourd.shortcuts"` 是模块 id 的**唯一字面量**（manifest 与用例都读它）。
`runningIdentifier` 是 `isRunning` 的伴生量（行内 spinner 要能知道"跑的是哪一行"——`lastResult` 按契约
跑完才写）；**`isRunning` 仍是唯一闸门**。

**真实现的三条要点**：`/usr/bin/shortcuts list --show-identifiers` 与
`/usr/bin/shortcuts run <identifier> [--output-path <tmp>]` 都走 `Process`；
**stdout/stderr 的读取照仓库既有先例 `DynamicIsland/helpers/MediaChecker.swift:69-88`**（Task 竞速 + 超时 `terminate()`，
在**退出之后再读 pipe**——子进程在退出前写满 64KB 管道时会**卡到超时**（写阻塞 → 退不出去），
先例与本模块都接受这条边界：`list` 每行约 60 字节、`run` 的输出走 `--output-path` 文件，两条命令都不走这条路）；
超时用 `Task` 竞速 + `terminate()`（**不用 `waitUntilExit` 阻塞主 actor**）。
`shortcuts list` 的限时**不是** `timeoutSeconds`，而是固定的 `shortcutsListTimeout`（30s，§决策摘要 D-10）。

### 2. 快捷指令：manifest（`com.cmeng.gourd.shortcuts`）

| 字段 | 取值 |
|---|---|
| `surfaces` | `[.expanded]` |
| `defaultPlacement` | `nil`（tab 落模块段，与其它模块同口径） |
| `icon.name` | `bolt.square` |
| `defaultEnabled` | `false`（新增模块一律默认关，docs/14 T-12） |
| `permissions` | `["shortcuts:run"]`（06 §7.1 已登记） |
| `config` | `pinnedShortcuts`（`list` / itemType `string`，默认 `[]`）、`showOutput`（`boolean`，默认 `false`）、`timeoutSeconds`（`integer`，默认 `30`）、`cachedShortcuts`（`list` / itemType `string`，默认 `[]`，缓存原始行） |
| `name` / `summary` | `module.shortcuts.name` / `.summary` |

**回写（2026-09-30）**：表内取值逐条落地未改；`id` 的唯一字面量是 `ShortcutsModule.moduleID`
（`DynamicIsland/Modules/Shortcuts/ShortcutsModule.swift:248`，manifest 与用例都读它，不各写一份）；
`config` 四键的默认值只有 `ShortcutsConfigDefaults` 一处（manifest 字面量与 `ShortcutsSettings.read`
的兜底同源）。`defaultPlacement: nil` 的后果是 tab 顺序键取 `Int.max`，落在模块 tab 段。

### 3. 前台应用：模型与历史（`DynamicIsland/Modules/FrontApp/`）

```swift
/// 一次前台快照（`bundleID` 缺失时用 `pid` 兜底做身份）。
struct FrontAppSnapshot: Equatable, Identifiable {
    let bundleID: String?
    let name: String
    let pid: pid_t
    var id: String { bundleID ?? "pid:\(pid)" }
}

enum FrontAppHistory {
    /// 去重（同 id 只留一条）→ 移到最前 → 截到 `limit`。`limit` **严格生效**（非正值给空表，
    /// 不夹取——夹取只有下面 `clampedLimit` 一处，见 §决策摘要 D-15）。
    static func updated(_ recent: [FrontAppSnapshot], activating: FrontAppSnapshot, limit: Int) -> [FrontAppSnapshot]
    /// 排除本应用自己（`selfBundleID`）；`selfBundleID` 为 nil 时原样返回（没有判据就不猜）。
    static func excludingSelf(_ items: [FrontAppSnapshot], selfBundleID: String?) -> [FrontAppSnapshot]
    /// `maxRecentApps` 的夹取区间与默认值。
    static let limitRange: ClosedRange<Int> = 3...8
    static let defaultLimit = 5
    /// **全项目唯一一处夹取**（回写 2026-09-30 补，落地代码里的成员）：store 读 config（缺键兜
    /// `defaultLimit`）之后调它一次，`recentLimit` 就是那个唯一值，视图不再夹（§决策摘要 D-15）。
    static func clampedLimit(_ raw: Int) -> Int
}
```

**store**：`FrontAppStore: ObservableObject`（`@MainActor`）持 `@Published current` / `@Published recent`
与 `private(set) recentLimit`（夹取后的历史上限，在 `start` 里定一次、之后不变，故不做 `@Published`）；
`start(selfBundleID:maxRecentApps:)` 里订阅 `NSWorkspace.shared.notificationCenter` 的
`didActivateApplicationNotification`（观察者 token 存起来；`userInfo` 里取 `NSRunningApplication` 的写法照
`DynamicIsland/DynamicIslandApp.swift:214-219` 的既有先例），初值取 `NSWorkspace.shared.frontmostApplication`
——**只种 `current`、不种 `recent`**（§决策摘要 D-16）；`maxRecentApps` 缺省 `nil` = 从 config 读
（§决策摘要 D-18），**夹取在 store 读 config 之后做一次**（`FrontAppHistory.clampedLimit`，`limitRange` 3…8），
视图不再夹；`deactivate()` 幂等摘观察者；`activate(_ snapshot:)` → `NSRunningApplication(processIdentifier:)?.activate()`；
图标取值 `func icon(for snapshot:) -> NSImage?`（`NSWorkspace.shared.icon(forFile:)`，按 id 缓存；路径优先用
映射快照时记下的 `bundleURL`，快照不是本 store 产生的才按 pid 现查——pid 会被复用）——
**视图只调 `store.icon(for:)`，不自己取图标**（接口里没有第二个图标来源）。
模块 id 的唯一字面量是 `FrontAppModule.moduleID` = `"com.cmeng.gourd.frontapp"`（manifest 与用例同源）。

**视图的排版预算**（`FrontAppHomeBlockView`，回写 2026-09-30 补）：当前应用图标 28pt、最近图标 20pt、
图标间距 4、两行间距 6；最近一行画几个由**块内预算** `capacity(forWidth:)` 定（每格 = 图标 20 + 悬停底色
左右内边距各 2 + 间距 4 = 24：`max(1, min(maxRecentApps, Int((宽 + 4) / 28)))`）——它在 180pt 的宿主最小块宽
下最多画 6 个、240pt 下 8 个，因此**配到 7 / 8 时超出的格子会被静默不画**（§已知限制 13）。
**它不是第二处夹取**：容量只会画得更少，永不超 `recentLimit`。
`current == nil`（拿不到前台应用）时画一行浅色 `—`；`recent` 为空时最近那一行**整行不画**。

### 4. 前台应用：manifest（`com.cmeng.gourd.frontapp`）

| 字段 | 取值 |
|---|---|
| `surfaces` | `[.home]` |
| `defaultPlacement` | `Placement(slot: nil, order: 30)`（首页块顺序；与待办 20 / 通知 40 之间） |
| `icon.name` | `app.badge` |
| `defaultEnabled` | `false` |
| `permissions` | `[]`（`NSWorkspace` 通知与 `NSRunningApplication` 都是公开 API） |
| `config` | `maxRecentApps`（`integer`，默认 `5`，运行时夹取到 `3...8`） |
| `homeBlockWidth` | `nil`（用宿主统一值 180/240） |
| `name` / `summary` | `module.frontapp.name` / `.summary` |

**回写（2026-09-30）**：表内取值逐条落地未改；`id` 的唯一字面量是 `FrontAppModule.moduleID`
（`DynamicIsland/Modules/FrontApp/FrontAppModule.swift:44`）；`config` 一键的默认值取
`FrontAppHistory.defaultLimit`（与夹取区间 `limitRange` 同在纯函数里，不写第二个 `5`）；
`homeBlockWidth` 按协议缺省**不重写**（表里的 `nil` = 宿主对新增模块的统一声明 180/240
——[09](09-features-and-mechanisms.md) §5.8 那条收窄口径）。

### 5. 文案（`DynamicIsland/Localizable.xcstrings`，全部中英双语 `translated`）

`module.shortcuts.name` / `.summary` / `.searchPlaceholder` / `.refresh` / `.run` / `.running` /
`.pin` / `.unpin` / `.empty` / `.noMatch` / `.success` / `.failure` / `.timedOut` / `.outputTruncated` /
`.runFailed`；`module.frontapp.name` / `.summary` / `.current` / `.recent` / `.emptyRecent`。

**回写（2026-09-30）**：20 个 key 全部落地（catalog 共 1559 键，只追加、不重排）。三处**落点**是文档空白
（§接口与数据形状 5 只给了 key 名），实现口径如下：
`module.frontapp.current` 是当前应用那一行的**可访问性标签**（`current` + 空格 + 应用名，视觉上不新增文字）；
`module.frontapp.recent` 是最近图标那一排的**可访问性标签**（同样不新增可见文字——块宽只有 180pt，
加标题行会挤掉"当前应用"这个主角）；`module.frontapp.emptyRecent` 只作**空态那一行 `—` 的 `.help` 与
`.accessibilityLabel`**（可见文案仍是 `—`，不是一句文字）。
`module.shortcuts.outputTruncated` 是 runner 侧截断时追加在 `output` 末尾的那一行；
`module.shortcuts.runFailed` 是"失败/超时但系统没给说明"的兜底句（§决策摘要 D-13）；
`module.shortcuts.timedOut` 一 key 两用（结果行标签 + 超时说明的句头，§决策摘要 D-13）。

## 明确不做

| 不做的事 | 为什么 |
|---|---|
| 快捷指令的 `--input-path`（Shelf 文件输入联动） | `docs/14` §1 把这一步挂在 shelf 模块上（shelf 未落地）；没有输入源时 `--input-path` 无从取值 |
| 快捷指令文件夹（`--folders` / `--folder-name`） | 本机只有无文件夹的指令；分组 UI 需要先定交互（折叠/分节），不属本批 |
| 快捷指令的折叠态槽位（最近使用的一个） | 依赖折叠态左右槽位（用户已降级）；本批只声明 `expanded` |
| **大输出落盘 + 「在 Finder 中显示」**（`docs/09` §5.4 的硬口径之一） | 本批只做"输出前 40 行 + 截断提示"（§已知限制 4）。落盘与 Finder 入口要先定"落在哪、留多久、怎么清理"，属后续批次 |
| 前台应用的折叠态侧槽形态 | 同上（`docs/16` §4.2 A5 的槽位一半随左右槽位那批） |
| 「按前台应用显示对应信息」（Nook X 那种"每个 App 一套信息模板"） | 需要"应用 → 信息模板"的映射表与模板引擎，本批只做**应用本身**（图标/名称/最近切换） |
| 记录窗口标题 / 文档名 | 需要辅助功能权限（TCC）才能读窗口标题；本批零权限 |
| 前台应用的持久历史（跨启动） | 历史是"刚才在干什么"的短期记忆，重启后从当前应用重新开始即可；持久化要引入新键与清理策略 |
| 给两个模块加首页块顺序之外的自定义 | 顺序在设置页「组件」里已可调（`homeBlockOrder`），不新增界面 |

## 实际交付

**已实现（批次 `p2-shortcuts-frontapp`，2026-09-30）**，提交范围 `412f72e3..4480f453`
（T1 解析/过滤/子进程接缝 · T2 快捷指令模块与 tab UI · T3 前台历史与事件源 store · T4 前台应用模块与
首页块；本批的文档回写提交在其后）。

**新增文件（6 个实现 + 1 个用例）**：

| 文件 | 内容 |
|---|---|
| `DynamicIsland/Modules/Shortcuts/ShortcutCatalog.swift` | `Shortcut` / `ShortcutListParser.parse` / `ShortcutFiltering.visible` / `ShortcutRunResult`（纯逻辑，无 `Process` / 无 SwiftUI） |
| `DynamicIsland/Modules/Shortcuts/ShortcutRunner.swift` | 两个注入点 + 两个真实现（`shortcutsListLines()` / `shortcutsRun(identifier:timeout:captureOutput:)`）、`ShortcutRunResult.maxOutputLines = 40`、`shortcutsListTimeout = 30` |
| `DynamicIsland/Modules/Shortcuts/ShortcutsModule.swift` | manifest（`surfaces [.expanded]` / `defaultEnabled false` / `permissions ["shortcuts:run"]` / config 四键）+ `ShortcutsStore` + 展开 tab 视图 |
| `DynamicIsland/Modules/FrontApp/FrontAppHistory.swift` | `FrontAppSnapshot` / `FrontAppHistory`（`updated` / `excludingSelf` / `clampedLimit` / `limitRange` 3…8 / `defaultLimit 5`） |
| `DynamicIsland/Modules/FrontApp/FrontAppStore.swift` | 事件源（`NSWorkspace` 通知 + `frontmostApplication` 初值）、映射、发布、`activate(_:)`、`icon(for:)` |
| `DynamicIsland/Modules/FrontApp/FrontAppModule.swift` | manifest（`surfaces [.home]` / `order 30` / `defaultEnabled false` / `permissions []` / config 一键 `maxRecentApps`）+ 首页块视图 |
| `DynamicIslandTests/ShortcutsFrontAppTests.swift` | **26 条用例**（解析 5 / 过滤 4 / 快捷指令 manifest 契约 2 / 快捷指令取数与并发闸门 5 / 会落盘的 `RecordingConfigHandle` 假体自检 1 / 前台历史 6 / 前台模块 3） |

**改动文件**：`DynamicIsland/Kernel/KernelBootstrap.swift`（`builtinModules` 加两行：`ShortcutsModule.self`、
`FrontAppModule.self`）；`DynamicIsland/Localizable.xcstrings`（追加 20 键，共 1559 键，中英双语 `translated`）；
`DynamicIslandTests/ModuleKernelTests.swift`（内置清单 8 → 9 行与两段投影断言按具体行同步）；
`DynamicIsland.xcodeproj/project.pbxproj`（四处登记新用例文件）。

**验证结论**：`xcodebuild test -only-testing:DynamicIslandTests` → `** TEST SUCCEEDED **`，
`DynamicIslandTests` **341 条 0 失败**（本批前 315，+26 = `ShortcutsFrontAppTests` 全部），
其中 `ShortcutsFrontAppTests` 26 / `ModuleKernelTests` 154 / `TakeoverEnablementTests` 27。
`workflow.py check p2-shortcuts-frontapp` **零 ERROR**（一条 WARN：D-01…D-07 七条决策来源为 agent，
未逐条经用户确认）。改动文件新增告警 0。

**覆盖审计**（`D-01`…`D-07` 逐条对应的脚本化证据）：`ShortcutListParser.parse` 定义在
`ShortcutCatalog.swift:43`；两个注入点在 `ShortcutRunner.swift`（`ShortcutsListing` / `ShortcutsRunning`），
用例文件里 `Process(` **0 命中**；`clampedLimit` 定义 `FrontAppHistory.swift:87`、调用点唯一
（`FrontAppStore.swift:70`）；`capacity(forWidth:)` 定义 `FrontAppModule.swift:265` 且是块内预算、
不写回 store；D-07 的四个不做项在 `DynamicIsland/` 与 `DynamicIslandTests/` 全域
`grep -rn "input-path\|--folders\|--folder-name\|--output-type\|windowTitle\|showInFinder"` **零命中**
（`AXUIElement` 只在 `FrontAppStore.swift:14` 的一句"没有它"注释里），
`DynamicIsland/Modules/Shortcuts/*.swift` 的 `grep -n "input-path\|--folders"` 同为空。

**没有现场证据的部分**（见 §已知限制 1 与每条"人工验收"）：真跑一条系统快捷指令、首次运行的系统
自动化提示、首页块的点小图标回切、前台事件的真实投递、列表缓存的过期行为——都不在自动化范围内。

## 已知限制

1. **快捷指令首次运行可能弹系统提示**：`shortcuts run` 在部分系统上会触发"允许壶中天运行快捷指令"的
   自动化提示（`docs/14` T-9 已记）。本批不预先请求、不引导授权——失败时**把系统给的原话显示出来**
   （结果行显示 stderr 摘要），不猜、不吞。**本批无现场证据**（用例不跑真命令，也没有人工点过一次）：
   口径保持"可能触发"，未被实测推翻也未证实。
2. **列表缓存可能过期**：缓存只在刷新时更新；在系统「快捷指令」里改了名称/删了指令，岛上的列表要
   点一次刷新才跟上。这是 `docs/09` §5.4「不要每次进岛都起子进程」的代价。
3. **超时只终止直接子进程**：`terminate()` 杀掉的是 `shortcuts` 进程本身，它内部再拉起的动作
   （例如某个脚本动作）不保证一起结束——这是 CLI 边界的既有事实，不做进程组管理。
4. **输出截断**：`showOutput` 打开时只显示前 `maxOutputLines`（实现取 40 行）并在结果里注明截断；
   `docs/09` §5.4 提的"大输出落盘 + 在 Finder 中显示"本批不做（§明确不做）。
5. **前台历史不含窗口**：只有应用级（图标/名称）；窗口标题要辅助功能权限，不做。
6. **前台历史跨启动清空**：重启后从当前应用开始累积（§明确不做）。
7. **首页块"看得见"有条件**：首页 strip 放不下时按 `order` 从尾部丢块（[17](17-nookx-adoption.md) D-03），
   本模块 `order 30` 排在待办（20）之后、通知（40）之前——**开着音乐会话（音乐块 min 300）且镜子开着时，
   770pt 面板（可用宽 ≈702）下它会被丢掉**。要看它请关掉其中一个或把面板拉宽（4 块最小宽度和 860 + 间隙
   需可用宽 ≥ 884 → 面板 ≈952pt 起）。丢块时条尾有 `＋N` 提示（[21](21-strip-honesty.md)），不算静默。
8. **首页块不显示"切回去"的快捷键**：点小图标即切，不给每个应用配全局热键（那要新权限面与冲突处理）。

**以下 9~14 是回写（2026-09-30）按落地代码补的实现期边界**：

9. **输出截断只在 runner 侧做一次**：`shortcutsRun` 读回 `--output-path` 文件时截到
   `ShortcutRunResult.maxOutputLines`（40 行）并在末尾追加一行 `module.shortcuts.outputTruncated`；
   视图**直接显示 `output`、不重算行数**（`ShortcutsResultRow`）——再切一次会把 runner 追加的那行提示
   本身切掉。依据：`ShortcutRunner.truncatedOutput` / `ShortcutsModule.swift` 的 `ShortcutsResultRow`。
10. **超时是软界，不是硬闸**：竞速的两条子任务在 `withTaskGroup` 返回前会被收完，等 `waitUntilExit`
    的那条一直等到子进程**真的退出**才结束。因此子进程忽略 `SIGTERM` 时，实际用时会超过
    `timeoutSeconds`（`terminate()` 之后还要等它退）。与先例 `MediaChecker.swift:69-88` 同形，
    不做进程组管理（另见本表第 3 条：只杀直接子进程）；那一档的 `duration` 如实记实际耗时。
11. **解析的退化边界**（`ShortcutListParser.parse`，都不猜，但有一条可预知的误报）：
    ① **行尾多一个空格就整行丢**——`"名称 (ID) "` 的尾随空白让 `tail.hasSuffix(")")` 不成立，
    整行被丢弃（不是"去掉空白再解析"）；真命令的输出不带尾空白（本机实测两行都不带），所以这条只在
    缓存被手改时才可能见到。② 形如 `整理 (旧)` 的**「无 identifier 的名字行」**会被解成
    name=`整理` / identifier=`旧`——形状上它和真行无法区分，"从行尾找第一个 ` (`"的代价就是这一条。
12. **两个短边界：亚秒限值显示成 `0s`、异常刷新会清掉旧缓存**：
    ① 超时那一句取整到秒（`Int(timeout.rounded())`），**亚秒的 `timeoutSeconds` 会显示 `0s`**
    ——manifest 的 `integer` 挡住了正常的亚秒值（`0` 或负数则一睡就到点、等于"刚起就终止"），
    但注入点与手改的 config 能走进这一档；② `refresh()` **空结果也写盘**（D-12），
    所以一次失败的刷新（起不来 / 非零退出 / 超时在真实现里都是 `[]`）会把上一份缓存清掉、
    屏幕上变成空态——恢复办法是再点一次刷新。
13. **前台应用块在窄块里会少画最近应用**：`FrontAppHomeBlockView` 按块宽算容量
    （`capacity(forWidth:)`，格子 24 + 间距 4 的精确上界）——宿主最小块宽 180pt 下最多画 **6** 个、
    240pt 下画 **8** 个。用户把 `maxRecentApps` 配成 7 或 8 时，**超出的格子会被静默不画，且没有
    `＋N` 之类的提示**（与首页 strip 的丢块提示不是一回事：这里丢的是块内的格子，不是整块）。
    依据：`FrontAppModule.swift:265-268` 与 `HomeStripView.swift:307` 的 `moduleBlockWidth(180, 240)`
    + `:175` 的显式宽度提案。它**不是第二处夹取**（容量永不超 `recentLimit`）。自动化的范围只到
    "模块答不答 `.view`"，格数只能靠肉眼（见 §验收标准 4）。
14. **D-07 的判据是「代码字面量无命中」，注释可以照实写**：D-07 的四个不做项靠 grep 钉
    （`input-path` / `--folders` / `windowTitle` / `showInFinder`）。grep **分不出代码与注释**——
    把 `--input-path` 写进一句"本模块不用 `--input-path`"的注释是允许的，它不构成"顺手做了进来"；
    靠 grep 判这件事因此只能约束**代码字面量与命令行开关字符串**：判据按这个读法执行（见 §验收标准 5），
    要更强的证据得读代码而不是 grep。（本批的文件头刻意只写中文描述、连开关字面量都没写——
    那是写法选择，不是判据的要求。）

## 验收标准

1. `xcodebuild test`（`DynamicIslandTests`）全绿，新增用例覆盖：`ShortcutListParser.parse`
   （正常行 / 名称含空格 / 名称含括号 / 形状不符丢弃 / 空表）、`ShortcutFiltering.visible`
   （固定在前且保持固定表顺序 / 搜索命中名称 / 搜索命中 identifier / 无命中）、
   `FrontAppHistory.updated`（去重移前 / 截到上限 / limit 夹取）、`excludingSelf`、
   两个模块的 manifest 校验（过 `validate()`）与 `surfaces` 取值。
2. 设置 → 组件里出现「快捷指令」与「前台应用」两张卡（默认关）。
3. 打开快捷指令模块后：展开面板有 tab；点刷新后列表出现本机快捷指令（名称 + identifier 解析正确）；
   点运行跑完给出结果行；右键固定后重启仍固定在前面。
4. 打开前台应用模块后（**前提：关掉音乐与镜子，或把面板拉到 ≥952pt**——否则该块按 order 30 被规则 ③ 从尾部丢，见 §已知限制 7）：
   首页出现一块，显示当前前台应用；切换 App 后块内跟着变；最近应用的小图标点一下能切回去。
5. **D-07 的四个不做项在代码里无命中**：`grep -rn "input-path\|--folders\|folder-name\|output-type\|windowTitle\|showInFinder" DynamicIsland/Modules/Shortcuts/ DynamicIsland/Modules/FrontApp/` 无命中
   （等价的老判据是 `grep -n "input-path\|--folders" DynamicIsland/Modules/Shortcuts/*.swift`）。
   **注释不算**：这四条判据管的是代码字面量与命令行开关字符串，注释里照实写"不做 `--input-path`"
   是允许的、也不该为它改别名（§已知限制 14）。

## 决策摘要

| ID | 决策 | 来源 | 理由 |
|---|---|---|---|
| D-01 | 快捷指令用 **identifier** 作身份、名称只用于显示；缓存存**原始行** | agent | docs/09 §5.4 已定 identifier；缓存存原始行让解析只有一份（§备选与取舍 ①） |
| D-02 | 运行走 `shortcuts run` + `--output-path` 读回；**限时 30s、禁止并发** | agent | docs/09 §5.4 的四条硬口径（§备选与取舍 ②③） |
| D-03 | 子进程的取数与运行都做成**注入点**（`ShortcutsListing` / `ShortcutsRunning`） | agent | 单测不跑真命令、不依赖本机装了什么快捷指令（同 Launcher 的取数注入口径） |
| D-04 | 前台应用联动本批做**首页块**形态，不做折叠态侧槽 | agent | 侧槽依赖左右槽位（用户已降级）；首页块不依赖它（§备选与取舍 ④） |
| D-05 | 历史口径 = 去重 + 移到最前 + 截到 `maxRecentApps`（夹取 3…8），**排除本应用自己** | agent | 纯函数、可单测；不排除自己会让每次点开刘海都污染历史（§做法 机制三）。**默认 5 与夹取区间是本批自定的旋钮**（用户未指定），取值小且可逆 |
| D-06 | 两个模块都 `defaultEnabled: false`，都不新增 surface / capability | agent | docs/14 T-12（新增模块默认关）；用既有的 `expanded` / `home` 即可（§做法 机制四） |
| D-07 | 不做 `--input-path`（Shelf 联动）、不做文件夹、不做窗口标题、不做持久历史 | agent | §明确不做：各自缺前置条件或需要新权限面 |

**D-08 起是执行期自定的读法（回写 2026-09-30）**——设计文档没写到的边界，实现时各定了一种读法，
逐条落在这里，免得后来人以为只有一种解释：

| ID | 决策 | 来源 | 理由 / 代价 |
|---|---|---|---|
| D-08 | 过滤**搜索先于排序**：固定项也要过搜索；固定表里已不在清单里的 id **跳过**（同一 id 只出现一次）；查询词去首尾空白后为空即不过滤 | agent | 入参是整张清单而不是"固定 + 其余"两摞，固定 ≠ 永远显示；已删的指令不该凭空出现。代价：搜别的名字时看不到与自己无关的固定项（这是刻意） |
| D-09 | **解析两侧都去首尾空白后再判空**：名称侧 trim、identifier 侧 trim；`"   (0F0F)"` 这种「名叫空格」的行丢弃 | agent | 名称可含空格，但"只有空白的名字"不是条目。代价：`"名称 (ID) "` 这类**行尾**带空白的行会**整行丢**（§已知限制 11 ①） |
| D-10 | `shortcuts list` 的限时是**固定 30s**（`shortcutsListTimeout`），不读 `timeoutSeconds` | agent | `timeoutSeconds` 按契约是**运行**的限时；列一次清单同样不能无限等（卡住的是 tab）。代价：这一档用户不可调，超时只表现为"缓存没更新"（不弹错、不写半张表） |
| D-11 | 输出截断（40 行 + 截断提示行）**在 runner 侧做一次**，视图只显示、不重算 | agent | runner 是输出文件唯一的读者；两处各切一次会把 runner 追加的提示行本身切掉。代价：`maxOutputLines` 成了视图也依赖的常量（提成 `ShortcutRunResult` 的静态常量，视图要引用不必再写一份 40） |
| D-12 | `refresh()` **空结果也写** `cachedShortcuts` | agent | 注入点这一层「取数失败」与「本机真的没有指令」同形（真实现失败时返回 `[]` 并把原因写日志），写下去让屏幕与盘同源。代价：一次异常刷新会清掉旧缓存（§已知限制 12 ②；要"失败保留旧缓存"得给 `ShortcutsListing` 加"这次是否失败"的返回） |
| D-13 | 失败 / 超时且 `failureMessage` 去空白后为空时，结果行退到 `module.shortcuts.runFailed`；而 `failureMessage` 侧**系统没给 stderr 时给 `exit <码>`**，超时时给 `module.shortcuts.timedOut` + ` · <限值>s` | agent | 那一栏是"失败时把系统的原话摆出来"的载体：留空等于把失败说成"没有原因"。代价：`exit 64` 这样的英文字样会直接出现在结果行（可核对的事实，好过编一句像人说的话）；`.timedOut` 一 key 两用（标签 + 说明句头），显示上略重 |
| D-14 | 运行闸门是**纯拒绝**：`isRunning` 为真时后到的 `run` 直接返回（不排队、不放弃前一条），并新增 `runningIdentifier` 做行内 spinner 的判据 | agent | §机制二只说"一次只允许一条在跑"，"后到的怎么办"未定；界面上按钮本来就禁用。代价：将来要做队列得改这里（用例 `testShortcutsStoreRunIsGatedWhileRunning` 钉住拒绝语义）；`runningIdentifier` 比片段列的 store 字段多一个 `@Published` |
| D-15 | `maxRecentApps` 的夹取**只在 `FrontAppStore.start` 一处**（`FrontAppHistory.clampedLimit`，3…8）；`updated` 严格按传进来的 `limit` 截断；视图用 `recentLimit`、不再夹 | agent | 夹取两处会让"哪个值说了算"有两个答案；`recentLimit` 是唯一值，配置页与首页块不会各显示一个数量 |
| D-16 | 初值**只种 `current`、不种 `recent`** | agent | `recent` 的语义是"**切换**过谁"，启动时的前台应用还没被切换过；块只有 180pt 宽，同一个应用在"当前"与"最近"各出现一次很浪费。代价：模块刚打开时 `recent` 为空、首页块只显示当前应用 |
| D-17 | 前台变成本应用自己时**整条忽略**：`current` 保持上一次的真前台（不回退、不清空），不进 `recent` | agent | 点开刘海让壶中天成为前台时，用户想看的仍是"刚才那个应用"；清空会让块在每次点开时闪一下空白。代价：极端情况下 `current` 停在最后一个真正的第三方应用上（是刻意的） |
| D-18 | `start(selfBundleID:maxRecentApps:)` 的 `maxRecentApps` **默认 `nil`**（nil = store 从 config 读）；模块侧**显式**读 config 原样传值 | agent | 契约同时给了"签名带参数"与"store 读 config"两句，默认值让两种调用形态都合法、夹取点仍只有一处；显式传值让"读点"与"显示点"对得上（缺键兜 `defaultLimit`，与 manifest 默认值同源） |
| D-19 | 视图内有**块内排版预算** `capacity(forWidth:)`：每格 = 20（图标）+ 4（悬停底色内边距）+ 4（间距），至少 1 个、不超过 `maxRecentApps` | agent | 夹取上界 8 时 8 格 ≈188pt > 宿主最小块宽 180，不裁会溢出（块是 `.clipped()`，被裁掉的是最后几个图标）。代价：配 7 / 8 时窄块里静默少画（§已知限制 13）；**它不是第二处夹取**（只会画得更少） |
| D-20 | 空态 / 无命中的图标与文案自定：`bolt.square` / `magnifyingglass`；`noMatch` 文案 = "没有匹配的快捷指令"（key 在契约里、文案不在） | agent | 契约只给了 key 名；`empty` 的文案逐字照 §预期结果（"没有快捷指令（点刷新）"）。代价：这两条英文措辞是本批自定的 |
| D-21 | 前台应用名的兜底链 `localizedName ?? bundleIdentifier ?? "pid:\(pid)"`；图标路径优先用映射快照时记下的 `bundleURL`，快照不是本 store 产生的才按 pid 现查 | agent | 不编造应用名——两样都没有时用身份串顶上，用户至少能看出是哪个进程；pid 会被复用，用当场记下的包路径不会画错图标。代价：块里可能出现英文/数字串（五键里没有"未知应用"这条）；`iconCache` 只增不删（一次会话见过的应用数量级） |
