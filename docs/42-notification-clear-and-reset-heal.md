# 42 · 首页通知块一键清除 + 已关闭集合自愈 + 安装后重新登记

| 项 | 值 |
|---|---|
| 状态 | 已实现 |
| 最后更新 | 2026-10-12 |
| 关联来源 | 用户 2026-10-12 三条要求：「首页的通知增加一键清除功能」「挂着的这两个处理掉」（指我上一轮列出的 `build.sh --install` 安装后重新登记、以及「已关闭集合」的持久化隐患）；承接 [40-home-notifications-scroll.md](40-home-notifications-scroll.md)（首页通知块形态）、[33-release-process.md](33-release-process.md)（安装/发布流程） |
| 工作流 | `.workflow/p16-notif-clear-heal/` |

> **怎么读**：§背景与目标 / §明确不做 / §备选与取舍 是这场改动的判断依据；
> §接口与数据形状 是参考型小节（执行者与机器查考），人审可跳过；
> §已知限制 / §实际交付 是留给后来人的。

**读者分界**：§一句话方案 / §背景与目标 / §备选与取舍 / §明确不做 / §验收标准 / §决策摘要 给人读；§做法 / §接口与数据形状 是给执行者与模型的契约。

## 一句话方案

三件独立的事：① 首页通知块的表头右侧加一个**「清除」**入口，语义与面板上的清除完全一致（只从岛上移除，系统通知中心一条不动）；② 「已关闭集合」加**水位线自愈**——持久记住见过的最大记录号，一旦发现通知库的最大记录号**回退**（库被重建、编号从头开始），就清空这个集合，避免历史 ID 撞上新通知把它们静默隐藏；③ `tools/build.sh --install` 结尾补一步 `lsregister -f`，装完即把应用重新登记到 LaunchServices。

## 背景与目标

**问题现状**（三条，前两条是同一件事的两面）：

1. **首页块没有清除入口**：面板（展开 tab）有「清除」，首页块却只能逐条点开或干看着——用户 2026-10-12 要求首页也能一键清除。
2. **已关闭集合会「毒化」将来的列表**：`dismissedNotificationIDs` 是宿主设置键里的一串通知库 record ID（上限 500），读取层按它过滤列表。它**只增不减**，而 macOS 的通知库 record ID 在库被重建（系统更新、库损坏重建等）后会**从头开始编号**——旧 ID 于是撞上新通知，把新通知静默隐藏。2026-10-12 用户实际遇到的「9 条未读、岛上一条不显示」就是这个集合积到 294 条后吃掉了列表；当时只能手工删掉那个键来恢复。
3. **装完的 `/Applications/壶中天.app` 可能处于半登记状态**：`tools/build.sh --install` 结尾会主动注销 DerivedData 副本的 LaunchServices 登记（「保 /Applications 唯一」），但**不重新登记装好的那一份**。2026-10-12 实测后果很重：从此 shell 或 Finder 启动都可能起成一个**没有 UI 会话**的实例（菜单栏无图标、退不掉、主线程在 AppKit 约束循环空转 26–46% CPU，且无崩溃报告），只有先 `lsregister -f` 再启动才恢复。

**预期结果**：① 首页块表头右侧点一下就能清空岛上列表；② 通知库编号回退时集合自动清空，列表不再被历史 ID 静默吃掉；③ `--install` 一次到位，装完直接启动即可用，不需要任何手工补救。

**关键约束**：清除语义与面板**逐字一致**（本地隐藏 + 持久化，系统通知不动）；自愈只在**确定**发生回退时动手（读库失败、库为空都不算）；不新增定时器、不新增权限面、不改通知库里的任何数据。

## 做法

**① 块内清除入口**：把首页块的表头从单个 `Text` 改成 `HStack`（文案在左、按钮在右），按钮复用面板那份文案键与字号档（`module.notifications.clearAll` / `NotificationRowMetrics.clearAll`），动作直接调 `store.dismissAll()`——与面板同一个方法，因此「只移除不真关」的语义自动一致。**显示条件抽成纯函数**（列表非空才显示），这样这条判断能被单测钉住，不必等上屏。

**② 水位线自愈**：读取层本来就在每次取数时算过一次 `SELECT MAX(rec_id)`（`NotificationCenterReader.lastMaxRecordID`），所以**不新增查询**。存储侧持久一个新键记「见过的最大记录号」（水位线），每次刷新后判一次：
- 读到的库最大号 **> 0 且 < 水位线** → 判定编号回退（库被重建）→ **清空已关闭集合**并把水位线落到新值；
- 否则水位线取两者较大值。

判定本身是一个**纯函数**，边界（水位线为 0 / 库为空 / 相等 / 回退）都在单测里钉住。

**③ 安装脚本**：`--install` 分支在覆盖安装、刷新 LaunchServices、注销 DerivedData 副本（`lsregister -u`）**之后**，补一条对**装好的那份**（`/Applications/壶中天.app`）的 `lsregister -f`。**顺序是硬要求**：`-u` 注销 DerivedData 副本时可能把该 bundle id 的登记整个抹掉，于是 /Applications 那份变成**半登记**——之后再启动就可能起成一个没有 UI 会话的实例（菜单栏无图标、退不掉）。重新登记必须排在 `-u` **之后**才补得回来：写在 `-u` 之前，收尾时又会被注销掉的那份盖过去。

## 备选与取舍

| 选择 | 理由 |
|---|---|
| 首页清除入口加二次确认 | 不选：面板上的同一个动作就是「一键」，两处语义不一致更糟；且只影响岛上显示，系统通知不动 |
| 自愈改成「按时间过期」（存 (id, 时间) 丢老条目） | 不选：要改存储形状并做迁移，而真正要防的是**编号回退**这一个确定性事件；水位线更小更准 |
| 自愈改成「丢掉大于当前最大号的条目」 | 不选：回退后新通知的号会**逐步爬回**旧区间，丢弃规则拦不住那次碰撞，必须靠水位线识别「回退」本身 |
| 自愈在库为空（`MAX(rec_id)` 取不到）时也清空 | 不选：读失败与真回退会混在一起，宁可漏一次也不误清（有记录后立刻能判出回退） |
| `build.sh` 里改成「不注销 DerivedData 副本」 | 不选：注销是为了避免同名两份都登记造成启动歧义，问题在**缺了装好那份的重新登记**，不是注销本身 |

## 接口与数据形状

```swift
// Modules/NotificationsModule.swift
func dismissAll()                                   // 已有：面板「清除」调它，块内入口复用它
private struct NotificationsHomeBlockView: View      // 表头改 HStack：文案 + 右侧「清除」按钮（纯文字，不带 capsule 底，见 §已知限制）
static func showsClearAction(itemCount: Int) -> Bool // 新增纯函数：列表非空才显示按钮（单测钉）

// modules/Constants.swift
static let notificationsRecordIDWatermark = Key<Int>("notificationsRecordIDWatermark", default: 0)
// 新增：见过的最大 record ID 水位线（与 dismissedNotificationIDs 一起构成自愈判据）

// Modules/NotificationCenterReader.swift
private(set) var lastMaxRecordID: Int64              // 已有：每次取数时 SELECT MAX(rec_id)，自愈直接读它

// Modules/NotificationsModule.swift —— 自愈判定（纯函数，单测直接钉）
enum NotificationDismissalPolicy {
    enum Outcome: Equatable {
        case keep(newWatermark: Int)                 // 保持：水位线推进到 newWatermark（未前进时＝原值）
        case resetDatabaseRolledOver                 // 库编号回退：清空已关闭集合
    }
    static func reconcile(watermark: Int, databaseMax: Int) -> Outcome
}

// tools/build.sh —— --install 分支结尾新增一步
// lsregister -f /Applications/壶中天.app（排在 lsregister -u 注销 DerivedData 副本之后）
```

**自愈判定在每次成功读取之后都跑一次**：`refreshAll()`（全量）与 `refreshIncremental()`（增量 / 60s 兜底轮询）各调一次 `reconcileDismissalWatermark(reader:)`——增量那次跑在「没有新条目」的早退**之前**。**刻意不集中到两条路径共用的 `apply()`**：回退那一档 `rec_id > 基线` 返回空、`apply` 根本不会被调用，把判定放进去等于永不触发。

**不动的**：`dismiss(_:)` / `dismissedLimit`(500) / `trimmed(_:limit:)` 的既有语义；读取层对通知库**只读**的立场（自愈也只动自己的设置键）；面板上的清除按钮与其文案；`--install` 之外的构建/打包分支。

## 明确不做

不改清除的语义（仍只从岛上移除，不关闭系统通知中心）；不给清除加二次确认；不做「撤销清除」；不动通知库里的任何数据；不改读取上限（40 条）；不把自愈扩成「定期清理或按时间过期」；不动 `build.sh` 的签名、公证或 DMG 分支。

## 实际交付

**代码**：

- `DynamicIsland/Modules/NotificationsModule.swift`（T1 / T1fix / T2 / T2fix）：
  - `NotificationsHomeBlockView.header` 由单个 `Text` 改为 `HStack`：文案在左、右侧「清除」按钮，动作直接调 `store.dismissAll()`（与面板同一方法，语义自动一致）；按钮**是纯文字、刻意不带面板那颗的 capsule 底**，并夹一道 `.frame(height: headerHeight)` 兜底进 16pt 表头（见 §已知限制）。
  - 新增纯函数 `NotificationsHomeBlockLayout.showsClearAction(itemCount:)`（`itemCount > 0`），视图只接这一条判据（与 `listedItems` 同一条纪律）。
  - 新增纯函数 `NotificationDismissalPolicy.reconcile(watermark:databaseMax:) -> Outcome`，`Outcome` = `.keep(newWatermark:)` / `.resetDatabaseRolledOver`。
  - 新增 `reconcileDismissalWatermark(reader:)`：判定回退则清空内存两处已关闭状态 + `persistDismissed()` 落盘 + 把水位线落到本次库最大号；否则只推进水位线（未前进时不写）。**每次成功读取之后都调**：`refreshAll()` 与 `refreshIncremental()`（后者在「没有新条目」的早退之前）。
- `DynamicIsland/models/Constants.swift`（T2）：新增 `Key<Int>` 设置键 `notificationsRecordIDWatermark`（默认 0）。
- `DynamicIslandTests/ModuleKernelTests.swift`（T1 / T2 / T2fix）：新增 `testNotificationsHomeBlockClearActionShowsOnlyWhenListNonEmpty`、`testNotificationDismissAllClearsLocalListAndPersistsWithoutTouchingDatabase`、`testNotificationDismissalPolicyReconcileBoundaries`、`testNotificationDismissedSetHealsOnRecordIDRolloverButNotOnStableDatabase`、`testNotificationsRecordIDWatermarkKeyShape`、`testNotificationDismissedSetHealsOnRolloverViaIncrementalPath`。
- `tools/build.sh` + `docs/33-release-process.md`（T3）：`--install` 分支在注销 DerivedData 副本之后，补一条对 `/Applications/壶中天.app` 的 `lsregister -f` 重新登记（失败不致命、只提示）；docs/33 对应步骤补一句说明。

**提交**：`86c78533`（T1）、`8871aa65`（T1fix）、`ed5017b6`（T2）、`f6bdf29d`（T2fix）、`828f146a`（T3）。

**与计划的偏离**：

- **T1fix —— 块内按钮收进 16pt 表头**：计划（§做法 ①）只说「复用面板那份文案键与字号档」。实际把面板那颗（带 capsule 底）照搬进块表头会因外框约 17pt 溢出固定 16pt 的 `headerHeight` 把块顶起来，于是块内这颗**去掉背景与纵向 padding、改成纯文字**，字号档 / 文案键 / 动作 / 提示仍与面板逐字一致。
- **T2fix —— 增量路径也判水位线**：计划（§做法 ②）只说「每次刷新成功后调用」。独立审查指出：库被重建后编号正从低位爬升的那一刻，`rec_id > 基线` 必然为空（`refreshIncremental` 走早退），而这正是**唯一**能观察到「库最大号 < 水位线」的窗口——只在 `refreshAll()` 里判会漏掉。于是把判定移到增量路径的早退**之前**（全量路径也保留）。**刻意不集中到共用的 `apply()`**：回退那一档 `rec_id > 基线` 返回空、`apply` 根本不执行，集中过去等于永不触发。
- **多出的测试覆盖**：`showsClearAction` 逐档（含负数防御式输入），`reconcile` 全边界（水位线 0 / 库为空 / 负 / 前进 / 相等 / 回退两档），新增键的形状用例，以及真存储侧「回退才清空 + 自愈后列表恢复」的全量与增量两条路径用例、读失败不重置。

**验证**：完整单测 **662/662、0 失败、exit 0**；`sh tools/build.sh` → `** BUILD SUCCEEDED **`；独立审查 PASS。

**遗留项**：

- **上屏复核未做（需用户）**：首页块「清除」按钮的位置 / 字号 / 观感，以及点一下之后列表真的空了——仍需用户上屏复核（判据与语义已由纯函数与真存储侧单测覆盖，观感无法自动断言）。
- 真实的通知库回退不做现场验证（要动系统通知库），自愈只由纯函数 + 夹具库单测覆盖判据（见工作流 §不验证的部分）。

## 已知限制

- **自愈只在「库最大号回退」这一种情形生效**：若通知库被重建后编号**没有**回退（例如系统保留了计数），历史 ID 的碰撞仍可能发生，本轮不覆盖。
- **回退检测需要一次读取才能发生**：水位线判定的输入是每次取数时算出的库最大号，所以「库被重建（编号跳低）」与「编号又爬回旧水位线以上」若落在**同一个轮询间隔内**（两次读取之间），这次回退会被漏掉。理论上存在，60s 兜底轮询把窗口限在一分钟内（期间任何一次全量刷新 / 文件事件会更早看到）。宁可漏一次，也不在无证据（读失败 / 库为空）时误清。
- **首页清除仍是不可逆的本地隐藏（无撤销）**：清掉之后没有撤销入口（与面板一致）；要恢复只能清空整个 `dismissedNotificationIDs`。
- **块内清除按钮刻意是纯文字、不带面板那颗的 capsule**：块表头是固定 16pt（`headerHeight`）的紧档，面板那颗（11pt 文字 + 上下 padding + capsule 底）外框约 17pt，照搬会溢出约 1pt 把块顶起来。块内这颗字号档 / 文案键 / 动作 / 提示都与面板逐字相同，**只差这颗底**——别为「统一风格」把 capsule 加回来。
- **`build.sh --install` 的重新登记只针对 `/Applications/壶中天.app`**：DMG / 其他分支不受影响，也不因此改变公证或签名行为。

## 验收标准

- 首页通知块在列表非空时表头右侧出现「清除」，点击后岛上列表清空、**系统通知中心一条不动**；按钮文案与面板同键同档。
- 纯函数单测：清除按钮的显示条件；水位线判定的四个边界（水位线 0 / 库为空 / 相等 / 回退）。
- 库最大号回退时，`dismissedNotificationIDs` 被清空且水位线落到新值；未回退时集合与水位线都不受影响。
- `tools/build.sh --install` 结尾实际执行了 `lsregister -f /Applications/壶中天.app`（安装日志可见），装完启动即正常（无需手工补救）。
- 完整单测通过；Release 构建通过；上屏复核（需用户）。

## 决策摘要

| ID | 决策与来源 | 理由 |
|---|---|---|
| D-01 | 用户：首页通知块增加一键清除 | 用户 2026-10-12 要求；与面板同一个动作 |
| D-02 | agent：入口放块表头右侧、复用面板文案与字号、不加二次确认；显示条件抽成纯函数 | 两处语义逐字一致最不容易出错；纯函数让「何时显示」可被单测钉住 |
| D-03 | agent：自愈用**记录号水位线**判定「库编号回退」，回退才清空；库为空不触发 | 只依赖一个确定性事件，不必改存储形状；宁可漏一次也不误清 |
| D-04 | agent：`build.sh --install` 结尾补 `lsregister -f` 重新登记装好的那一份 | 实测半登记状态会起成无 UI 会话的坏实例（不可见、退不掉），必须装完即登记 |
