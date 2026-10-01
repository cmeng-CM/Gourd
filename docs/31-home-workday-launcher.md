# 首页静态区分、工作日统计与启动台快捷启动（p7 批次）

| 项 | 值 |
|---|---|
| 状态 | **已实现**（工作流 `p7-workday-launcher` 六任务，2026-10-01 一天内完成；实现提交范围 `4ff1a4c7..44c0fba9`，回写提交紧随其后） |
| 最后更新 | 2026-10-01 |
| 关联来源 | `docs/29-home-blocks-and-panel.md`（p5：首页块结构、进度模块机制二）、`docs/30-ui-polish-and-shelf.md`（p6：块「浮起」样式与常量、D-20 取证降级先例）、`docs/19-launcher.md`（启动台契约） |

> **怎么读**：§背景与目标 / §明确不做 / §备选与取舍 是这场改动的判断依据；
> §接口与数据形状 是参考型小节（执行者与机器查考），人审可跳过；
> §已知限制 / §实际交付 是留给后来人的。
> 读者分界：§一句话方案~§验收标准 给人读；§接口与数据形状 是给执行者与模型的契约，**精确到不用再做设计决策**。

## 一句话方案

三条用户反馈一批落地：① 首页每个块在**不 hover 时**也有可见的无边界光区分（柔光池加亮 + 三停渐变 + 池半径放到不变量上限，**仍不加区域块与边线**）；②「时间进度」模块就地改造为「工作日统计」（今天行＝工作时长进度＋距上/下班倒计时，周/月/季/年行＝已过工作日占比＋「剩 N 天」；工作日判定带内置 2026 国务院节假日与调休表）；③ 启动台面板分上下两区——上区「快捷启动」（数据＝既有 `pinnedApps`，拖上固定、拖下取消，与右键菜单共用接缝），下区＝现有应用网格但**不再含固定项**。

## 背景与目标

**问题现状**

1. p6 已把首页改成「每块柔光池（0.06）+ 内容辉光（0.08/5）」的浮起样式，但常驻档在实机上几乎不可见（p6 证据截图裁切比对），块与块的区分实际只靠 hover——用户本轮反馈「鼠标悬浮有额外状态，不悬浮的情况能不能有个显示，能够分清每个区域是每个区域」。
2. 「时间进度」模块（`com.cmeng.gourd.progress`）画的是**自然时间百分比**（今天已过 87% / 本周 70% / 本月 3%）。用户判定「就是个百分比统计……完全理解不到有什么意义」，并提出「如果是工作日统计还有点意义」——这等于把 `docs/29` D-03「进度 = 自然时间进度……不引节假日与调休」的旧裁决提回来改判。
3. 启动台（`docs/19`）的「固定」当下只体现为「排最前 + 右上角图钉角标 + 右键菜单」，固定项仍混在下区网格里；用户要求分成上下两个区域：上区＝快捷启动（可设置哪些应用固定在里面），设置方式＝**从下区拖到上区加入、从上区拖到下区取消**。

**预期结果**（做完后看到的）

- 首页不 hover 也能一眼看出每个块的范围（块周围一圈柔和的光、块与块之间一条更暗的缝），hover 观感不降级；仍然没有任何描边、卡片底与直角台阶。
- 首页「工作日统计」块：假期当天显示「今天 休息日」；工作日显示「距下班 2h20m」类倒计时与时长进度条；本周/本月等行显示「剩 N 天」。设置卡里能改上班/下班时间与工作日集合。
- 启动台顶部出现「快捷启动」区：空时是一枚虚线提示格（「将应用拖到这里固定」）；固定后应用出现在上区、从下区消失；拖拽或右键都能「上下走」；重启后保持。

**承接关系**：`docs/29`（首页块的清单结构、`ProgressHomeBlockLayout` 的行数算术、`visibleScopes` 配置入口——本次全部继承，只改行语义与文案）；`docs/30`（「浮起」的两层形态与不加区域块/边线的裁决、上屏调参与像素判据手法、CUA 取证降级先例——本次继承；浮起常量数值本次上调，以本文档 §接口与数据形状 为准）；`docs/19`（`pinnedApps` 键、`LauncherPins` 读写接缝、rank 排序——本次继承；「固定项仍留在网格里」与「不做拖拽」被本次改判，改判留痕在 T6 落）。本次增量 = 上述三条反馈本身。

## 做法

**机制一 · 首页静态光分离。** 沿用 p6 的「柔光池（为主）+ 内容辉光（为辅）」两层，不加任何新形态：常驻档提亮（池中心 0.06 → 0.13、辉光 0.08/5 → 0.10/6），池半径系数从 0.45 放到不变量上限 0.50（渐变恰好在格子的最近边归零，不会出现直角台阶 = 变相底板），池的径向渐变由两停改三停（0.6 处留 0.35× 的比例）让光晕尾部更长更软；hover 档同步上调（池 0.20、辉光 0.20/12）保持「hover 一定比常驻更亮」的可辨差。块间距、块宽、布局骨架一律不动——加大间距会改宽度预算、可能触发尾部丢块，改动面超出反馈。起点值上屏实测后微调，判据是像素而不是观感（见 §验收标准 A1）。

**机制二 · 工作日统计。** 模块身份与持久化键不变（id、`module.progress.*` 文案键族、`visibleScopes` 配置照旧），显示名改「工作日统计」；行语义：**今天行** = 工作时长进度条 + 行动化文案（工作日为「距上班 1h20m / 距下班 2h20m / 已下班」，非工作日为「休息日」）；**本周/本月/本季/今年行** = 已过工作日占比进度条 + 「剩 N 天」（今天之后仍在区间内的工作日个数）。工作日判定 = 星期集合（默认一~五、组件卡可改）× 内置国务院节假日表（**先查表**：调休上班日恒为工作日、放假日恒为休息日，查不到才看星期）；2026 年表来自国办发明电〔2025〕7号（§接口 3 逐日期列出），表外年份退化为纯星期判定。工作时间为整点小时、可配置（默认 9–18，下班 ≤ 上班等非法值回落默认），数字刷新沿用既有 60 秒 `TimelineView` 心跳。未挂载的旧展开视图保留但注释标注语义已失效（不删代码）。

**机制三 · 启动台两区与拖放。** 不新增数据：「快捷启动区」就是既有 `pinnedApps` 的可视化——上区＝固定项（顺序＝**固定先后**，即 `pinnedApps` 表序），下区＝排名列表剔除固定项后的网格（保序）。拖拽是两区之间的唯一新语义：拖上＝固定（追加表尾）、拖下＝取消固定；与右键菜单、幂等写盘共用 `LauncherPins` 这条唯一接缝（先落盘再刷新）。拖放用 SwiftUI `onDrag`/`onDrop`，载体是应用 id 的纯文本（`NSItemProvider(object: NSString)`），接收侧校验「是本次扫描里已知的应用」，外来文本与未知 id 一律丢弃（no-op）。上区空态给一枚虚线提示格 + 小标题「快捷启动」，两区之间一条 0.08 白的细分隔线；搜索只过滤下区（上区是「固定」语义，不受搜索影响）。上区随固定数量自适应换行，长出的高度自然进高度账本（启动台本来就是被测量的页）。

## 备选与取舍

| # | 备选 | 为什么没选 |
|---|---|---|
| 1 | 加大块间距（8 → 12）来区分块 | 宽度预算收紧会触发尾部丢块（`HomeStripLayoutMath` 规则③），且用户要的是「有个显示」不是布局改动；间距不动 |
| 2 | 常驻卡片底 / 描边 / 3D 倾角 | 用户 p6 与 p7 两轮都明确「不增加区域块、边线」；3D 小字会糊（docs/30 已论证） |
| 3 | 只调 hover 更亮 | 反馈就是 hover 之外看不见——方向相反 |
| 4 | 直接删掉「进度」块 | 用户原话「如果是工作日统计还有点意义」是要改造，不是删除 |
| 5 | 新建一个「工作日」模块替换 | id/键/配置/测试的迁移面远大于收益；语义就是同一个「进度」，就地改造 |
| 6 | 工作日不识别节假日（纯星期） | 发布当天就是国庆假期——第一天就会显示错；且调休在中国的普遍性使纯星期口径长期失真 |
| 7 | 从系统日历读节假日 | 需要新增日历 TCC 权限，全局约束不允许 |
| 8 | 启动台拖拽用 AppKit `NSDraggingSource` | 架子用它是因为要跨 App 拖文件；面板内应用拖拽 SwiftUI `onDrag/onDrop` 足够，且同仓有 `onDrop` 先例、无模型拖拽先例可循 |
| 9 | 上区单行横向滚动 | 面板内横向滚动难用；自适应换行 + 随数量长高（有 850 顶格兜底） |
| 10 | 搜索同时过滤上区 | 上区是「固定」语义；搜索是找**未固定**应用的主路径，上区常驻恰是「搜索不到」的兜底 |
| 11 | 固定项保留在下区（复制一份到上区） | 与用户描述的拖拽模型矛盾（拖下＝取消要求下区就是「未固定」的家）；复制一份还会出现同一应用两处存在的一致性负担 |

## 明确不做

- 不做 3D / 卡片底 / 描边 / 圆角矩形底板；不动块间距、块宽与 `HomeFlowLayout` 布局骨架。
- 不做 2027 及以后的节假日表（表外年份按星期判定，年度更新随发版）；不做按用户自定义节假日文件。
- 不做工作时间的分钟/半小时粒度、跨天班次或弹性工时（整点滑块，默认 9–18）。
- 不做进度模块的展开面板恢复与折叠槽位（维持 p3 起「只有首页块」的契约）。
- 启动台不做拖拽排序（上区内部顺序＝固定先后、不可拖动重排）、不做文件夹/分组、不做固定区独立开关（无固定 = 显示提示格）。
- 不做外部（Finder 等）拖应用进面板固定——载体只认本次扫描的应用 id，外来数据丢弃。
- 不解决 CUA 驱动 hover / 拖拽的限制本身（沿 docs/30 D-20 的降级先例）。
- 不清理 p6 遗留项（旧分带渲染器残留、用量 tab 遗留洞）。

## 已知限制

1. **节假日表只含 2026 年**（国办发明电〔2025〕7号）：2027 年及以后退化为纯星期判定——调休周六会被算作休息日、法定假日会被算作工作日；年度更新需发版。
2. **工作时间为整点**（0–23 的整数滑块）：不支持 8:30 这类半小时粒度；不支持跨天班次。
3. 周/月/季/年的进度条分子包含「今天按工作时长比例」的部分完成，与「剩 N 天」（只数整天、不含今天）是两套口径并存的显示——是刻意的：前者是进度、后者是计数。
4. **CUA 取证限制**：hover 仍不可驱动（p6 实测；本批首页 hover 观感照旧列真人复核）；**面板内拖拽经合成事件可送达**（T5 复测：下区→上区固定、上区→下区取消，日志 + `defaults read` + 截图三证）；**右键菜单路径与真实鼠标手感**仍列真人复核（右键固定/取消从未被真人走过，见第 10 条）。
5. 启动台上区随固定数量换行长高，会压缩下区网格可视行数（面板 850 顶格内滚动）；固定项很多时上区可能占掉大半面板。
6. 调休上班日的「今天」行按工作时长正常推进（与普通工作日无异，无特殊标注）。
7. 周起止随系统日历 `firstWeekday`（不强制周一起始）；「本周剩 N 天」按同一周区间计算。
8. 首页静态光的观感因显示器亮度/夜览而异；验收用像素判据（块间 ≤3/255、块内 ≥10/255）替代主观评分。
9. **拖拽抑制有 30 秒兜底窗口**：`onDrag` 没有「拖拽取消」回调——拖拽被取消 / 在面板外结束时，令牌靠 30 秒有界看门狗释放（正常 drop / 面板关闭 / 视图消失三条立即释放）。窗口内「悬停自动收起」被抑制：拖拽真的没落下时，面板最长多站 30 秒才收起。
10. **右键菜单路径未验证**：格子菜单文案由 `isPinned` 决定，但它与面板根 `.contextMenu`（`ContentView.swift:1403`）的遮挡关系未知，右键固定 / 取消固定从未真人验证过（p2 起即如此）；本批固定态取证走的是应用自身读路径（`defaults write` + 重启），不是右键路径。

## 实际交付

**批线与结构**：2026-10-01 一天内完成；**六个任务（T1–T5 五个实现 + T6 回写）**，实现提交范围 `4ff1a4c7..44c0fba9`（**12 个提交**，含六个 fix 提交——T1–T5 各一轮、T5 两轮——与一条文档回写 `1c03e210`；全部本地、未 push）。全量单测 490 → **501 条 0 失败**；改动文件新增编译告警 0。上屏证据在 `.workflow/p7-workday-launcher/evidence/`（`t1-static-blocks.{png,txt}` + `t1-static-blocks-glass.png`、`t3-workday-block*.png` + `t3-settings-controls*.png` + `t3-verify.txt`、`t5-quick-launch-*.png` + `t5-restored-empty.png` + `t5-drag*.png` + `t5-drag.txt`、`fix2-autoclose*.png` + `fix2-log.txt`），随 `.workflow/` 消失。

**交付物清单**（逐条对着报告与代码核过）：

| 类 | 落点 | 交付物 |
|---|---|---|
| 首页静态区分 | `DynamicIsland/Host/HomeStripView.swift`、`HomeStripLayoutTests.swift` | `HomeBlockFloatMetrics` 定稿常量（`idleGlowOpacity 0.10` / `idleGlowRadius 6` / `poolOpacity 0.13` / `hoverGlowOpacity 0.20` / `hoverGlowRadius 12` / `hoverPoolOpacity 0.20` / `poolEndRadiusFactor 0.50`）+ 柔光池径向渐变两停改**三停**（0.6 处 `×0.35`）；形态零改动（无描边 / 填充 / 圆角底）；`testHomeBlockFloatMetricsStayInTheLegibleRange` 档位扩展（池区间、hover−idle 差、`effects(hovered:)` 与常量同源） |
| 工作日判定与统计（纯函数） | `DynamicIsland/Modules/WorkdayCalendar.swift`（新）、`ModuleKernelTests.swift` | 常量（`defaultWorkdays` / `defaultWorkStartHour` / `defaultWorkEndHour` / `workHourRange = 0...23`）、`HolidayTable` + `holidayTables`（2026 表：holidays 33 条 + makeupWorkdays 6 条，逐日期照抄国办发明电〔2025〕7号）、`isWorkday`（先查表后看星期）、`resolveWorkdays` / `resolveWorkHours`（坏值回落）、`TodayState` + `todayState` / `todayFraction`、`spanStats` |
| 进度模块改造 | `DynamicIsland/Modules/ProgressModule.swift` | manifest 六键（新增 `workStart` / `workEnd` / `workdays`，默认值取 `WorkdayCalendar` 常量）、icon `chart.pie` → `briefcase`（显示名 / 简介换值在 catalog）；行语义 = 今天行 `todayFraction` + 行动文案、周月季年行 `spanStats`；纯函数出口 `WorkdayRowText`（`compactDuration` / `todayKey` / `todayTrailing` / `leftDays`）；旧展开视图 `ProgressModuleView` / `ProgressScopeRow` 保留 + 死代码标注（「语义已由工作日口径取代」） |
| 设置三行 | `DynamicIsland/components/Settings/ModuleSettingsSection.swift` | `configControls` +3：`workStart` / `workEnd` `.integer(range: WorkdayCalendar.workHourRange)`、`workdays` `.multiSelect`（`multiSelectEffectiveSet` 指向 `WorkdayCalendar.resolveWorkdays`，最后一枚胶囊拒绝写空） |
| 启动台分区与拖放（纯函数） | `DynamicIsland/Modules/Launcher/LauncherRanking.swift`、`ModuleKernelTests.swift` | `LauncherPartition.split(ranked:pinnedIDs:)`、`LauncherDropRegion`、`LauncherQuickDrop.resolve(...)`（四种 no-op、纯函数不落盘）+ 独立测试类 `LauncherPartitionDropTests`（两条用例） |
| 启动台两区视图与拖放接线 | `DynamicIsland/Modules/Launcher/LauncherModule.swift` | `LauncherStore.quickApps` / `gridApps`（同一私有 `partition` 现算）/ `pin(_:)` / `unpin(_:)`（走 `LauncherPins`，先落盘再刷新、幂等）；两区视图（小标题 + 上区网格 / 虚线提示格 + 0.08 白分隔线 + 下区网格）；两处 `onDrop` + `handleDrop` / `applyDrop` 收口；图钉角标删除；`adaptiveColumns` 两区共用 |
| 拖拽自动收起抑制（计划外） | 同上 | `@EnvironmentObject vm` + 每拖拽一枚 `UUID` 令牌（`vm.setAutoCloseSuppression(_:token:)`）；起拖置位 + 30 秒有界看门狗（代数 + 令牌双判据）；两处 `onDrop` 第一行 `defer` 释放 + 顶部同步 `vm.dropEvent = true`；三道护栏（面板关闭 / 视图消失 / 看门狗） |
| 文案 | `DynamicIsland/Localizable.xcstrings`（进包那份；根那份一个字未动） | 改值 3 条 + 新增 17 条（progress 15 + launcher 2），逐条见 §接口与数据形状 5；根 catalog 对这 20 键 grep 计数全 0 |
| 测试 | `DynamicIslandTests/{ModuleKernelTests,TakeoverEnablementTests,HomeStripLayoutTests}.swift` | 全量 490 → 501（+11）：T2 四枚（`testWorkdayCalendarMatchesThe2026StateCouncilTable` / `…TodayStateBoundaries` / `…SpanStatsCountCompletedAndRemaining` / `…ResolveFallsBackOnInvalidConfig`）、T3 三枚（`testWorkdayRowTrailingTextMatrix` / `testProgressModuleWorkdayConfigReadsThroughTheRealHandle` / `testProgressWorkdayControlsMatchManifestAndCatalog`）、T4 两条（`testLauncherPartitionSplitsQuickAndGridStably` / `testLauncherQuickDropResolveMatrix`）、T5 两条（`testLauncherStorePinUnpinUpdatesPartitions` / `testLauncherQuickLaunchKeysLiveOnlyInTheInPackageCatalog`） |

**与计划的偏离及原因**（逐条给理由；「文档写的是预期，代码是真的」）：

1. **`resolveWorkHours` 越界口径：夹取 → 一律整体回落默认**（§接口 3 原稿写「夹取」）：T2 审查裁定驱动——夹取会产出「有效但荒谬」的班次（如 9–23 班），坏值一律回落 `(9, 18)`；测试与 §接口 3 已同步（回写提交 `1c03e210`）。
2. **分区 / 拖放用例归置独立测试类 `LauncherPartitionDropTests`**（计划未指定落点）：审查 Minor——类名与承载内容必须相符；`LauncherScannerRankingTests` 回到「扫描 / 排序 / 过滤」名义（T4 fix `bc4f04d1`）。
3. **计划外新增「面板内拖拽自动收起抑制」修复**（计划与 §接口 6 原稿均未写）：T5 首轮上屏发现面板级 `dragDetector` 把面板内拖拽的 targeted 进出当收起信号（拖拽穿非投放区即收起、`onDrop` 收不到抬手）→ `T5 fix` 挂抑制令牌；独立审查 1 Important（释放面三泄漏）+ 3 Minor → `T5 fix2` 收口（`defer` 第一行、`dropEvent` 同步置位、30 秒看门狗 + 两道护栏、`adaptiveColumns` 去重）。复测：拖上固定 / 拖下取消两向送达并落盘。
4. **T3 顺带修正 `ModuleSettingsSection` 一处陈旧注释**（在点名文件内、但是注释非功能）：描述 `progress` surfaces 的注释自 p3-widgets 起与实现不符（`[.compact,.expanded]` → 实际 `[.home]`），就地更正，避免本批读者以为旧口径还在。

**遗留项**（本批明确未做；逐条有出处）：

1. **真人复核清单（四项）**：① 首页 hover 观感（池 / 辉光加深、轻微放大提亮，且邻居不被挤开；CUA 驱动不出 hover，同 docs/30 D-20）；② 右键菜单路径（与面板根 `.contextMenu` 的遮挡关系未知，p2 起即未真人验证，见 §已知限制 10）；③ 「搜索只过滤下区」的上屏证据缺（键盘 / 滚轮合成事件进不了 SwiftUI 绑定，仅代码结构保证 + 纯函数用例）；④ 真实鼠标手感下的拖拽-点击边界与上区悬停高亮一帧。
2. **2027 及以后的节假日表**：表外年份按纯星期判定，年度更新随发版（§已知限制 1、§明确不做 2）。
3. **p6 遗留项未动**：旧分带渲染器残留、用量 tab 遗留口子等（沿用 docs/29 §遗留 / docs/30 §遗留清单，本批不清理）。

## 验收标准

- **A1** 首页静态区分：不 hover 的截图中，相邻块之间有可辨暗缝、每块被无边界柔光包着；像素测量：块间空隙 ≤3/255、块内落光区 ≥10/255、跨格扫描无直角台阶（测量输出留 txt）；无任何描边/矩形底。
- **A2** 浮起常量单测两枚全绿：`testHomeBlockFloatMetricsStayInTheLegibleRange`（扩展档位后）、`testHomeBlockPoolRadiusNeverCrossesTheNearestEdge`（40/96/140 三档不变）；hover 各值仍全面高于常驻。
- **A3** 工作日判定：2026 抽查断言全过（10/1 休息、9/20 与 10/10 上班、10/8 上班、10/11 休息、2/14 上班、5/4 休息；10 月共 18 个工作日；10/12 12:00 时本月剩 14 天）；2027 无表年份按星期退化且不崩。
- **A4** 今天行四态（休息日 / 距上班 m / 距下班 m / 已下班）与坏配置回落由纯函数测试钉住。
- **A5** 上屏：首页块在假期当天显示「今天 休息日」 + 各档「剩 N 天」；设置页进度卡出现「上班时间（时）/ 下班时间（时）/ 工作日」三行、拨动即时生效；模块名显示「工作日统计」。
- **A6** 启动台分区与拖放纯函数测试全绿：上区顺序 = 固定先后（不随 Spotlight 抖动）、下区剔除固定项保序、四象限解析（上→加 / 下→删 / 重复→no-op / 未知与外来→no-op）。
- **A7** 启动台上屏：空态提示格 → 右键固定后应用出现在上区且下区不再含它（`defaults read` 留证）→ 重启保持 → 取消固定后回落。
- **A8** 拖拽取证的如实记录：CUA 能驱动则给过程截图；不能则 `t5-drag.txt` 写明尝试与降级结论，并列「需真人鼠标复核」项。
- **A9** 验证命令退出码 0（全量测试通过，无新增告警）。
- **A10** docs/31 十节齐全、§实际交付与§接口按实现回写；CHANGELOG 有 p7 段；docs/19、docs/29、docs/30 的改判指针就位可检索。

## 接口与数据形状

### 1. 首页浮起常量（`HomeBlockFloatMetrics`，上屏调参后定稿值）

| 常量 | 旧值（p6） | 新值（起点） | 定稿值（2026-10-01 上屏实测） |
|---|---|---|---|
| `idleGlowOpacity` | 0.08 | **0.10** | 0.10 |
| `idleGlowRadius` | 5 | **6** | 6 |
| `poolOpacity` | 0.06 | **0.13** | **0.13**（首轮即达标：块内 mean 27.9 / 峰 33 每 255，未上调） |
| `hoverGlowOpacity` | 0.16 | **0.20** | 0.20 |
| `hoverGlowRadius` | 11 | **12** | 12 |
| `hoverPoolOpacity` | 0.12 | **0.20** | 0.20 |
| `poolEndRadiusFactor` | 0.45 | **0.50**（不变量上限，不得 >0.5） | 0.50 |
| 池渐变 | 两停 `[poolOpacity, .clear]` | **三停** `[(0, poolOpacity), (0.6, poolOpacity×0.35), (1, .clear)]` | 三停 |
| 上屏实测（纯黑底，判据：缝 ≤3、块内 ≥10、扫描无台阶） | — | 缝 0.00 / 块内 27.9（峰 33）/ 扫描单调归零、相邻差 ≤4 | 三条全过 → 起点值即定稿（证据 `.workflow/p7-workday-launcher/evidence/t1-static-blocks.txt`） |

其余不变：`hoverScale 1.02`、`hoverBrightness 1.06`（组装时 −1）、`duration 0.2`、`poolEndRadius = max(0, min(w,h) × factor)`（无下界）。上屏调参**已完成**（2026-10-01）：首轮实测即达标（缝 **0.00**、块内 **27.9/255**、峰 **33**、跨格扫描单调归零无台阶），`poolOpacity` 停在 **0.13**（未上调到 0.18 档）——最终值即起点值；`hoverPoolOpacity > poolOpacity` 与「系数 ≤ 0.5」两条不变量未破。

### 2. 启动台分区与拖放纯函数（`LauncherRanking.swift` 追加）

```swift
enum LauncherPartition {
    /// quick = pinnedIDs 顺序（过滤掉本次扫描里不存在的 id；重复 id 保留首次）；
    /// grid  = ranked 中剔除固定项后的原顺序（保序）。
    static func split(ranked: [LauncherApp], pinnedIDs: [String])
        -> (quick: [LauncherApp], grid: [LauncherApp])
}

enum LauncherDropRegion { case quick, grid }

enum LauncherQuickDrop {
    /// 返回新的 pinned 表（**纯函数、不落盘**——落盘由 `LauncherStore.pin/unpin` 经 `LauncherPins` 完成）；
    /// no-op（返回 nil）四种：未知 id；quick 收到已固定；grid 收到未固定；空 id。
    /// quick：LauncherPinning.adding(draggedID, to: pinnedIDs)（追加表尾）；
    /// grid ：LauncherPinning.removing(draggedID, from: pinnedIDs)。
    static func resolve(draggedID: String, target: LauncherDropRegion,
                        pinnedIDs: [String], knownIDs: Set<String>) -> [String]?
}
```

`LauncherStore` 追加（T5）：`var quickApps: [LauncherApp]`（= `split(...).quick`）、`var gridApps: [LauncherApp]`（= `split(...).grid`）、`func pin(_ app: LauncherApp)`、`func unpin(_ app: LauncherApp)`（走 `pins.pin/unpin`，先落盘再刷新，与 `togglePin` 同口径）。视图网格数据源改 `LauncherRanking.filter(store.gridApps, query:)`。

### 3. `WorkdayCalendar`（新文件 `DynamicIsland/Modules/WorkdayCalendar.swift`）

```swift
enum WorkdayCalendar {
    static let defaultWorkdays: Set<Int>        // ISO：1=周一 … 7=周日，默认 [1,2,3,4,5]
    static let defaultWorkStartHour: Int        // 9
    static let defaultWorkEndHour: Int          // 18
    static let workHourRange: ClosedRange<Int>  // 0...23 —— 区间**单一来源**：设置控件与读侧夹取共用（照 LauncherGridMetrics.iconSizeRange 先例，禁第二份字面量）

    struct HolidayTable { let holidays: Set<String>; let makeupWorkdays: Set<String> }  // "M/d"
    static let holidayTables: [Int: HolidayTable]      // 2026 表见下；表外年份走纯星期

    static func isWorkday(_ date: Date, workdays: Set<Int>, calendar: Calendar = .autoupdatingCurrent) -> Bool
        // 顺序：makeup 含 → true；holidays 含 → false；否则 ISO 星期 ∈ workdays
    static func resolveWorkdays(from raw: [String]) -> Set<Int>     // 空/全坏 → defaultWorkdays
    static func resolveWorkHours(start: Int?, end: Int?)
        -> (start: Int, end: Int)   // 任一值不在 workHourRange、或 end ≤ start → 回落 (9, 18)（不夹取：坏值一律回落默认）

    enum TodayState: Equatable {
        case restDay                       // 非工作日
        case beforeStart(minutes: Int)     // 工作日、现在 < 上班
        case working(minutesToEnd: Int)    // 工作日、上班 ≤ 现在 < 下班
        case afterEnd                      // 工作日、已过下班
    }
    static func todayState(now: Date, workdays: Set<Int>, workStartHour: Int,
                           workEndHour: Int, calendar: Calendar) -> TodayState
    static func todayFraction(
        now: Date, workdays: Set<Int>, workStartHour: Int, workEndHour: Int, calendar: Calendar
    ) -> Double                                                     // 0…1；休息日 / 上班前 = 0

    /// scope ∈ [.week, .month, .quarter, .year]（.day 由 todayState/todayFraction 承担）
    /// progress = (今天之前的工作日数 + 今天(工作日时)的 todayFraction) / 区间工作日总数（总数为 0 → 0）
    /// remainingWorkdays = 今天之后（不含今天）仍在区间内的工作日数
    static func spanStats(scope: ProgressCalculator.Scope, now: Date, workdays: Set<Int>,
                          workStartHour: Int, workEndHour: Int, calendar: Calendar)
        -> (progress: Double, remainingWorkdays: Int)
}
```

**2026 年表（国办发明电〔2025〕7号，逐日期照抄；格式 `"M/d"`）**

- `holidays`（放假日）：`1/1,1/2,1/3`；`2/15,2/16,2/17,2/18,2/19,2/20,2/21,2/22,2/23`；`4/4,4/5,4/6`；`5/1,5/2,5/3,5/4,5/5`；`6/19,6/20,6/21`；`9/25,9/26,9/27`；`10/1,10/2,10/3,10/4,10/5,10/6,10/7`。
- `makeupWorkdays`（调休上班）：`1/4`、`2/14`、`2/28`、`5/9`、`9/20`、`10/10`。

### 4. `ProgressModule` / `ProgressCalculator` 变更

- manifest：`name` 键不变、值改 zh「工作日统计」/ en “Workday Stats”；`summary` 值改 zh「工作日统计：工作时长进度与剩余工作日」/ en “Workday stats: hours progress and workdays left”；`icon` `chart.pie` → `briefcase`；`config` 由三键扩为六键——新增：
  - `workStart`：`type: "integer"`，默认 `.int(9)`；读侧 `resolveWorkHours`。
  - `workEnd`：`type: "integer"`，默认 `.int(18)`。
  - `workdays`：`type: "list"`，`default: .strings(["1","2","3","4","5"])`，`itemType: "string"`（ISO 编号）。
  - `id` / `surfaces` / `defaultPlacement` / `defaultEnabled` / `visibleScopes` 面不变。
- 行文案（纯函数出口 `WorkdayRowText`，视图只消费）：
  - 时长格式：`compactDuration(minutes:) -> String`——`≥60` 分 → `"2h20m"`（整点 `"3h"`）；`<60` → `"45m"`；`0` → `"0m"`。
  - 今天行 trailing：`rest` → 休息日；`beforeStart(m)` → `toStart %@`（@ = compactDuration）；`working(m)` → `toEnd %@`；`afterEnd` → 已下班。
  - 其余行 trailing：`leftDays %d`（`剩 N 天`；N ≥ 0）。
- 进度条 value：今天行 = `todayFraction`；其余行 = `spanStats.progress`。
- 设置控件（`ModuleSettingsSection.configControls` 追加三行，moduleID `"com.cmeng.gourd.progress"`）：`workStart` `kind: .integer(range: WorkdayCalendar.workHourRange)`、`workEnd` 同（区间从这个常量取，不写字面量——口径见 `ModuleSettingsSection.swift:355-357` 的既有先例）、`workdays` `kind: .multiSelect(options: ["1"…"7"], titleKeys: [7 个 weekday key], multiSelectEffectiveSet: { WorkdayCalendar.resolveWorkdays(from: $0).sorted().map(String.init) })`。

### 5. 文案（`Localizable.xcstrings`；先 grep 两份——**已存在于两份的键必须两份同改**，全新键落 `DynamicIsland/Localizable.xcstrings`）

| key | zh-Hans | en |
|---|---|---|
| `module.progress.name`（改值） | 工作日统计 | Workday Stats |
| `module.progress.summary`（改值） | 工作日统计：工作时长进度与剩余工作日 | Workday stats: hours progress and workdays left |
| `settings.modules.effect.progress`（改值） | 首页块里的工作日统计：工作时长进度 + 本周 / 本月剩余工作日 | Workday stats in the home block: hours progress plus workdays left this week / month |
| `module.progress.workday.rest`（新） | 休息日 | Day off |
| `module.progress.workday.clockedOut`（新） | 已下班 | Off work |
| `module.progress.workday.toStart`（新） | 距上班 %@ | %@ to start |
| `module.progress.workday.toEnd`（新） | 距下班 %@ | %@ to end |
| `module.progress.workday.leftDays`（新） | 剩 %d 天 | %d days left |
| `module.progress.weekday.1`…`.7`（新，7 键） | 周一…周日 | Mon…Sun |
| `settings.modules.progress.workStart`（新） | 上班时间（时） | Work start (hour) |
| `settings.modules.progress.workEnd`（新） | 下班时间（时） | Work end (hour) |
| `settings.modules.progress.workdays`（新） | 工作日 | Workdays |
| `module.launcher.quickLaunch`（新） | 快捷启动 | Quick Launch |
| `module.launcher.quickLaunchHint`（新） | 将应用拖到这里固定 | Drag apps here to pin |

### 6. 启动台视图形状（T5）

- 结构：搜索框（不动）→ 上区（小标题 + `LazyVGrid`(同一 metrics) 或虚线提示格）→ 细分隔线（0.08 白、1pt 高）→ 下区网格（现有 `LazyVGrid`，数据源换 `filter(gridApps)`）。
- 拖放：格子 `.onDrag { NSItemProvider(object: app.id as NSString) }`；上区容器 `.onDrop(of: [.utf8PlainText], isTargeted:)` → `resolve(target: .quick)` → `store.pin`；下区容器 `.onDrop` → `resolve(target: .grid)` → `store.unpin`；`knownIDs = Set(store.apps.map(\.id))`。上区 `isTargeted` 时叠 `RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06))` 高亮。落点判定全在 `handleDrop` / `applyDrop` 一处收口：`resolve` 判 nil（外来文本 / 反向拖 / 未知 id）不落盘、不刷新。
- **拖拽的自动收起抑制（T5 实际实现，计划未写）**：`LauncherModuleView` 用 `@EnvironmentObject vm` + **每拖拽一枚 `UUID` 抑制令牌**（`vm.setAutoCloseSuppression(_:token:)`；先例 `ShelfView.swift:283` / `NotchClipboardView.swift:95`）：`onDrag` 起拖时置位并**武装 30 秒看门狗**（代数 + 令牌双判据，先例 `ClipboardManager.markDragStart`）；两个 `onDrop` 处理器**第一行** `defer { endDragSuppression() }` 释放（早退 / 异步失败也释放），顶部**同步** `vm.dropEvent = true`（赶得上当次 `!isTargeted`）；另有三道护栏——`onChange(of: vm.notchState)` 到 `.closed`、`onDisappear`、看门狗超时。原因是面板级 `dragDetector`（`ContentView.swift:2666` 一带）会把**面板内拖拽**的 targeted 进出当成收起信号：不抑制时拖拽穿过分隔线 / 标题 / 边距即收起面板，两区 `onDrop` 永远等不到抬手（T5 首轮上屏实测）。
- `LauncherGridCell`：图钉角标删除（下区已无固定项）；`isPinned` 参数保留（右键菜单文案 固定/取消固定）。
- 两区共用的 `GridItem`：`.adaptive(minimum:spacing:)` 抽成 `adaptiveColumns`（列宽 / 间距逐字一致，上区格子与下区格子不许有尺寸差）。
- 虚线提示格：`RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(.white.opacity(0.18))` + 居中文案（`quickLaunchHint`），高度与一格同高。

## 决策摘要

| ID | 决策 | 来源 | 理由 |
|----|------|------|------|
| D-01 | 首页块不 hover 也要能分清区域，仍不加区域块与边线 | 用户 | 第 1 条原话；「不增加区域块，边线」自 p6 起是持续约束 |
| D-02 | 手段 = 柔光池/辉光加强 + 三停渐变 + 池系数放到 0.5 上限；间距与布局骨架不动 | agent | 黑底上唯一无边界可行路径（docs/30 已论证黑影不可见）；加大间距改动宽度预算、可能触发尾部丢块 |
| D-03 | 目标常量与像素判据（块间 ≤3/255、块内 ≥10/255、无直角台阶） | agent | 观感不可测；p6 的像素测量手法已建立（docs/30 机制一） |
| D-04 | 「进度统计」改造为工作日口径，不删除 | 用户 | 第 2 条原话「如果是工作日统计还有点意义」 |
| D-05 | 识别为 `ProgressModule`（保留 id 与 `module.progress.*` 键族，改显示名/图标/文案） | agent | 用户机首页唯一「百分比 + 时间语义」的块；「统计」环是 CPU/内存/GPU 与工作日无关；换 id 迁移面大而无益 |
| D-06 | 行语义：今天 = 工作时长进度 + 行动化文案；周/月/季/年 = 工作日占比 + 「剩 N 天」 | 用户 | 第 2 条「就是个百分比统计」——行动化信息是「有意义」的直接读取；条仍表比例 |
| D-07 | 工作日 = 星期集合（默认一~五，可配置）× 2026 国务院节假日表；表外年份退化纯星期 | 用户 | 第 2 条；发布当天即国庆（表是「有意义」的前提）；不引 TCC（否决读系统日历） |
| D-08 | 工作时间整点可配置（默认 9–18）；非法值回落默认 | agent | 输入容错沿用既有口径（07 §2 规则 4 回落默认不崩）；整点是现有控件（整数滑块）的支持范围 |
| D-09 | 右侧文案改行动化（距上班/距下班 2h20m、已下班、休息日、剩 N 天），百分比不再显示 | 用户 | 第 2 条「完全理解不到有什么意义」；条本身表比例，文字给行动信息 |
| D-10 | 未挂载的旧展开视图保留但注释标注「语义已失效」，不删代码 | agent | 不夹带无关删除；但不清误述会留下「重挂即可」的假承诺 |
| D-11 | 启动台分上下两区：下区现有内容、上区快捷启动；拖上固定、拖下取消 | 用户 | 第 3 条原话（含 3.1 / 3.2 两个子条） |
| D-12 | 数据沿用 `pinnedApps`；上区顺序 = 固定先后；下区 = 排名剔除固定项保序 | agent | 不新增第二份状态；「固定先后」稳定，不受 Spotlight 数据抖动 |
| D-13 | 拖放 = SwiftUI `onDrag/onDrop` + 纯文本 id 载体 + 接收侧校验、未知/外来丢弃 | agent | 同仓 `onDrop` 先例（架子）；`NSDraggingSource` 是为跨 App 拖文件，此处过重 |
| D-14 | 右键菜单保留为并行入口；两入口共用 `LauncherPins` 接缝（先落盘再刷新、幂等） | agent | 既有功能不回退；单一写路径防两份状态 |
| D-15 | 上区空态虚线提示格 + 小标题「快捷启动」 + 细分隔线；搜索只过滤下区 | agent | 拖拽的可发现性靠空态提示；上区是「固定」语义，不该被搜索清空 |
| D-16 | 拖拽取证按降级预案记账（纯函数 + 右键菜单路径上屏 + 真人复核清单） | agent | CUA hover 先例（docs/30 D-20）；不为取证改交互 |
| D-17 | 全局约束沿用：不新增 TCC/网络/依赖；不改手动高度语义；完成即本地提交不 push；界面改动上屏留证 | agent | 项目既有批次口径（p5/p6 一致） |
| D-18 | 文案落点：已存在于两份 catalog 的键两份同改；全新键只落进包那份（`DynamicIsland/Localizable.xcstrings`） | agent | 根 catalog 不在任何 target（docs/30 口径），且根那份对本批**全部新增/改值键** grep 计数为 0（进包那份含既有的 `module.progress` / `module.launcher` 键族——本批要改的那几个正是在它里面改值）；跨 catalog 一致性测试只盯两边都有的键 |

### 执行期判断（2026-10-01 回写，D-19 起续号）

> 来源都是 `agent（执行期）`：由实现者提出、控制器裁决接受（拍板时间见 `.workflow/p7-workday-launcher/ledger.md` 的裁决区；本节只留结论、理由与代价）。

| ID | 决策 | 来源 | 理由与代价 |
|----|------|------|------|
| D-19 | 面板内拖拽经既有 `setAutoCloseSuppression` 令牌抑制自动收起 + 30 秒看门狗兜底 | agent | 面板级 `dragDetector` 把面板内拖拽的 targeted 进出当收起信号——合成拖拽修复前无法送达、修复后两向送达（T5 实测）。代价：取消拖拽后抑制最长存活 30 秒（正常 drop / 面板关闭 / 视图消失三条立即释放） |
| D-20 | `resolveWorkHours` 越界一律回落默认、不夹取 | agent | 夹取会产生「有效但荒谬」的班次（如 9–23 班）；T2 审查驱动（实现 / 测试 / §接口 3 三处同步） |
| D-21 | 本模块拖放处 `vm.dropEvent` 同步无条件置位 | agent | 异步置位赶不上当次 `!isTargeted`；代价：no-op 投放也跳过一次性收起，同既有四处口径 |
