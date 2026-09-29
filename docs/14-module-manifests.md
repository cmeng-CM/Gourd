# 内置模块清单（15 个模块 + 终端条目；2026-09-28 增补 `todos` → 16 个模块 + 终端条目）

这份文档回答一件事：**15 个内置模块（接管 10 + 新增 5）与终端条目，各自的 manifest 声明什么。** 它是 P1-0 前置清障第 3 项（[12-p1-batches.md](12-p1-batches.md) §P1-0）的产物，也是 [09-features-and-mechanisms.md](09-features-and-mechanisms.md) §8.1 已拍板模块化边界的逐项落地。**2026-09-28**：新增第 6 个新增模块 `com.cmeng.gourd.todos`（见 §1 的 todos 行与开头说明），本文的「16 份 manifest」相应变成 17 份。

与其它文档的分工：

| 文档 | 管什么 |
|---|---|
| [06-module-protocol.md](06-module-protocol.md) | **字段级契约**：`ModuleManifest` / `GourdModule` / surface / slot / capability / ConfigSchema 的词表与校验规则。本文不复制、不改写 |
| [09-features-and-mechanisms.md](09-features-and-mechanisms.md) | **功能与机制**：每个模块做什么、靠什么实现、配置键叫什么、优先级多高 |
| [13-runtime-kernel.md](13-runtime-kernel.md) | **P1 批次的范围与裁定**（D-07 试点模块、D-09 清单口径、D-12 不声明锁屏、D-14 平台台账口径） |
| [15-platform-dependencies.md](15-platform-dependencies.md) | 这些模块落到哪条私有 API / 子进程 / 外部域名上 |

**取值一律逐字引 06 号与 09 号文档**：`surfaces` 取 06 §2.2 的四个取值（本清单用到 `compact` / `expanded` / `home`——`home` 只由 `todos` 声明，见 §1 表下说明；锁屏取值见 T-5）；`slot` 取 06 §6.2 的 `left` / `right` / `center`；`permissions` 取 06 §7.1 的白名单词；`config` 键名取 09 §5 原文（新增模块）或上游 `Defaults` 键（接管模块）。本文**不新造字段名、不新造取值词汇**。

已有落地样本：`com.cmeng.gourd.progress`（`DynamicIsland/Modules/ProgressModule.swift`，P1 批次 T4）与 `com.cmeng.gourd.todos`（`DynamicIsland/Modules/TodosModule.swift`，P1 批次 T5）——表内对应行的 `surfaces` / `permissions` / `config` 键名与它们一致；`defaultPlacement` 的**当前值**见各自行注与 T-1（本批 `order` 还被兼作 expanded tab 的排序键，见 [13](13-runtime-kernel.md) 已知限制 25）。

**2026-09-28 增补**：`com.cmeng.gourd.todos`（待办）不在 P1-0 定稿的 16 份 manifest 内——它是用户当日判定「进度无行动价值」后新增的**第 17 份**（模块计 16 个：接管 10 + 新增 6；终端仍是独立条目），并接过 `progress` 空出的折叠态中央槽位（[13](13-runtime-kernel.md) D-20）。下表按模块逐个列出，`todos` 行紧跟 `progress` 之后。

**2026-09-29 变更**：P2 批次 `p2-home-strip` 给 `todos` 加了 `home` surface（首页 strip 的一块）——**模块数与 manifest 份数不变**（仍 **16 个模块 / 17 份 manifest**，因为本批没有新增模块，只是 todos 多了一个 `surfaces` 取值）；`progress` 与 `notifications` 均**不声明** `home`，理由与逐条口径见 §1 表下说明与 [17-nookx-adoption.md](17-nookx-adoption.md)。

---

## 1. 清单

**列含义**：`surfaces` 与 `slot` 见 06 §6.1/§6.2（`slot` 只在 `surfaces` 含 `compact` 时有意义）；`permissions` 见 06 §7.1；`config 关键项` 只列关键键名（完整 schema 在各自落地批次按 06 §5 写全，见 T-10/T-13）；`优先级/依赖` 取 09 §6 路线图。

| id | surfaces | slot | permissions | config 关键项 | 优先级/依赖 |
|---|---|---|---|---|---|
| `com.cmeng.gourd.nowplaying` | `compact`、`expanded` | `center` / order 10 | `media:read`、`media:control`、`network:itunes.apple.com` | `playerColorTinting`、`useMusicVisualizer`、`visualizerBarCount`、`enableWaveformScrubber`（接管映射，见 T-3） | P2a 首批；依赖 15 号文档 §1 的 `MediaRemote.framework` / `MediaRemoteAdapter.framework` |
| `com.cmeng.gourd.lyrics` | `compact`、`expanded` | `center` / order 20 | `media:read`、`events:subscribe:media.playbackChanged`、`network:lrclib.net` | `enableLyrics`、`lyricsPanelWidth`、`lyricsPanelOffset` + 歌词磁盘缓存开关（09 §2 A 的 🔧 缺陷修复） | P2a；曲目变化经 EventBus 订阅，不做模块间直接引用（06 §3.3 R4） |
| `com.cmeng.gourd.stats` | `compact`、`expanded` | `left` / order 10 | `system:metrics` | `statsUpdateInterval`、`statsStopWhenNotchCloses`、`enableStatsFeature`（接管映射） | P2a；依赖 15 号文档 §1 的 AppleSMC（温度）/ `IOReport.framework`（频率） |
| `com.cmeng.gourd.calendar` | `expanded` | — | `[]`（事件标题/地点的细粒度读取另需 `calendar:read-titles`，**待落 06 号文档 §7.1**，见 T-8 / §3） | `showCalendar`、`hideCompletedReminders`、`hideAllDayEvents`（接管映射） | P2a；事件与提醒读取走 EventKit，依赖日历 / 提醒 TCC 授权 |
| `com.cmeng.gourd.shelf` | `expanded` | — | `files:picker`、`files:shelf`、`network:local`（**待落 06 号文档 §7.1**） | `dynamicShelf`（接管映射）+ LocalSend 传输开关（09 §2 D） | P2a；依赖本地网络 TCC（`NSLocalNetworkUsageDescription`，09 §7 必办项） |
| `com.cmeng.gourd.timer` | `compact`、`expanded` | `right` / order 10 | `timers`、`notifications` | `enableTimerFeature`、`timerDisplayMode`、`timerPresets` + 计时器持久化与到点通知（09 §2 C 的 🔧 缺陷修复） | P2a；到点通知依赖 `notifications` capability |
| `com.cmeng.gourd.clipboard` | `compact`、`expanded` | `right` / order 20 | `clipboard:read`、`clipboard:write` | `enableClipboardManager`、`clipboardDisplayMode` + 电池上降频（09 §2 D 的 🔧 缺陷修复） | P2a；`clipboard:read` 只给元数据（06 §7 硬性规则 2） |
| `com.cmeng.gourd.controls` | `expanded` | — | `power:control` | `enableSystemHUD`、`enableVolumeHUD`、`enableBrightnessHUD`、`enableKeyboardBacklightHUD`、`enableCustomOSD`（接管映射；surfaces 口径见 T-2） | P2a；依赖辅助功能 TCC（媒体键 / 亮度键拦截） |
| `com.cmeng.gourd.weather` | `compact`、`expanded` | `left` / order 20 | `network:api.open-meteo.com`、`network:air-quality-api.open-meteo.com`、`network:wttr.in` | `lockScreenWeatherProviderSource`、`lockScreenWeatherTemperatureUnit`、`lockScreenWeatherRefreshInterval`（接管映射） | P2a；依赖位置 TCC |
| `com.cmeng.gourd.mirror` | `expanded` | — | `[]` | `showMirror`、`mirrorShape`、`selectedCameraID`（接管映射） | P2a；依赖相机 TCC |
| `com.cmeng.gourd.launcher` | `compact`、`expanded` | `right` / order 30 | `[]` | `pinnedApps`、`showRecents`、`iconSize`、`density`（09 §5.1） | P2b 第 4；全局热键用上游 `KeyboardShortcuts` |
| `com.cmeng.gourd.lunar` | `compact` | `left` / order 30 | `[]` | `displayFormat`、`showFestivals`（09 §5.2） | P2b 第 1；展开区归属见 T-6 |
| `com.cmeng.gourd.progress` | `compact`、`expanded`（折叠态形态 = **中央槽位常驻百分比**；展开态 = **剩余量清单**——一行一个尺度：图标 + 标签 + 细进度条 + 剩余量 + 百分比，行悬停显示起止时刻） | `center` / order 30（2026-09-27 落地：`slot` 记 `center`，`order` 同时是 expanded tab 与 compact 槽位候选的排序键，双语义已按 [13](13-runtime-kernel.md) 已知限制 25 的「明确写下」分支处理，见 D-19；与 T-1 早期给折叠态预留的 `left` / order 40 不同——本版**只做中央槽位**，左/右槽位仍推 P2） | `[]` | `visibleScopes`（默认 `day` + `year`）、`style`、`baseCalendar`（09 §5.3；已落地三键） | **默认关（`defaultEnabled = false`，2026-09-28 用户判定「时间进度」无行动价值，见 [13](13-runtime-kernel.md) D-20）**；代码与 manifest 全部保留、可手动开回。落地：P1-4 提前消化 P2b 第 2；折叠态中央槽位 2026-09-27 落地 |
| `com.cmeng.gourd.todos` | `compact`、`expanded`、`home`（折叠态 = 图标 + **今日**的 `已办/总量`；展开态 = 顶部三环「今日 / 本周 / 所有」+ 下方该类别清单，环本身是筛选器；**首页块 = 三环横排 + 今日清单前 5 条，块宽 < 220pt 时只画三环**，2026-09-29 加） | `center` / order 20 | `[]` | **无（第一版不做配置）** | **已落地（P1 批次 T5，2026-09-28；`home` 由 P2 批次 `p2-home-strip` 于 2026-09-29 加）**；`defaultEnabled: true`——它是折叠态中央槽位的默认内容（`order` 20 < progress 的 30，见 [13](13-runtime-kernel.md) D-20）；依赖提醒 TCC（系统授权，不是模块 capability，故 `permissions` 为空集） |
| `com.cmeng.gourd.shortcuts` | `expanded`（折叠态槽位可选，见 T-1） | — | `shortcuts:run` | `pinnedShortcuts`、`showOutput`、`timeoutSeconds`（09 §5.4） | P2b 第 3；依赖 shelf 的文件输入联动（`--input-path`） |
| `com.cmeng.gourd.notifications` | `expanded`、`compact`、`home`（2026-09-29 起声明首页块；浮层用 `presentation: hud`，见 T-7） | — | `notifications:read`（**待落 06 号文档 §7.1**） | `showBodyInHUD`、`appsFilter`、`maxItems`、`pollIntervalSeconds`（09 §5.5） | P2c（先做可行性探针）；依赖完全磁盘访问 TCC |
| `com.cmeng.gourd.terminal`（终端，独立条目） | `expanded` | — | `[]` | `mode`、`externalApp`、`openMode`、`workingDirectory`、`extraArguments`（09 §5.6） | P2b 最后；依赖 Ghostty 启动参数验证（09 §5.6 的实测项） |

**2026-09-29 的 `home` 取值（P2 批次 `p2-home-strip`，后由 `p2-p0-visible` 增补）**：`home` 目前出现在 **todos 与 notifications 两行**——`todos` 是首批（三环横排 + 今日清单前 N 条），`notifications` 在 2026-09-29 的 `p2-p0-visible` 批次补上（「通知 · 最近 N 条」+ 最近 3 条，点条目开 App 并收起）。**`progress` 保留代码与 manifest 但不声明 `home`**（它默认关、声明了也没内容，组件卡已标注"暂不出现在首页"）。原说明（17-nookx-adoption.md](17-nookx-adoption.md) 已知限制 9）。**本批没有新增模块**，模块数与 manifest 份数**不变**（仍是 16 个模块 / 17 份 manifest，含终端独立条目）——变的是 todos 与 notifications 各多了一个 `home` 取值。

**两处「不是模块」的说明**（避免清单被读成"全部功能都模块化"）：

- **终端是独立条目**：它不是 `GourdModule` 的渲染单元，而是上游终端功能的"外部 App 模式"配置载体（09 §5.6）；列在表内是为了让 16 份 manifest 的边界闭合（D-09），落地时按同一份 manifest 模型声明。
- **锁屏五面板群不在表内**：音乐 / 天气 / 日历 / 提醒 / 计时器的锁屏面板维持上游现状（09 §0 原则 P4），不归入任何模块，见 T-5。

---

## 2. 未决口径裁定（T-1…T-13）

调研标记的 13 处未决口径逐条给结论。每条的**理由都指向已定契约或已实测证据**，不引入新词汇。

### T-1 槽位分配

- **结论**：`center`（主内容，独占 1）：nowplaying（order 10）、lyrics（order 20）；`left`（状态类，默认上限 3）：stats（10）、weather（20）、lunar（30）、progress（40）；`right`（动作类，默认上限 3）：timer（10）、clipboard（20）、launcher（30）。shortcuts 的折叠态槽位**默认不声明**，其落地时若声明则记 `right` / order 40。落在默认上限之外的模块（progress、shortcuts）**不进槽位但保持 active**，用户调高 `config.layout.compact.maxPerSide` 或禁用他人后自动补位。（**2026-09-27 回写**：中央槽位先行落地——progress 以 `slot: center` / order 30 常驻居中，本表 `left` / order 40 的分配与每侧上限仍是三槽布局落地时的口径，见 [13](13-runtime-kernel.md) D-19 与「明确不做」。）
- **理由**：06 §6.2 已给类别语义与示例（`left` 状态类 stats / weather、`right` 动作类 timer / clipboard、`center` 独占主内容 nowplaying / lyrics），其余模块按同类别归入，超出上限的处置也是 06 §6.2 原文；progress 本批未声明 `compact`（D-07），故表中 `slot` 记 —，其分配值在折叠态落地后生效。**注意 progress 的 `order` 有两个值不要混**：本表 `left` 行写的 **40** 是折叠态槽位的预留值；当前代码里 `defaultPlacement.order` 是 **30**，它在本批被兼作 expanded tab 的排序键（[13](13-runtime-kernel.md) 已知限制 25）——折叠态落地时必须拆字段或同步改写，不能沿用同一字段的双关语义。（**已处理**：中央槽位落地时按「明确写下双语义」分支处理，`order` 仍同时供两处排序，见 [13](13-runtime-kernel.md) 已知限制 25 的落地回写。）

### T-2 controls 的 surfaces

- **结论**：controls 只声明 `expanded`，不声明 `compact`。
- **理由**：它在 09 §2 E 里的上游形态是 HUD 与媒体键（音量 / 亮度 / 键盘背光 / 防休眠 / 外接屏亮度），是密集交互面板而非"一个图标能表达的状态"，塞进 06 §6.2 的图标槽只会做一个反复展开的开关。

### T-3 接管模块 config schema 缺口

- **结论**：接管 10 个模块的 config **不新发明键**，一律映射上游既有 `Defaults` 键（如 `enableLyrics`、`dynamicShelf`、`enableClipboardManager`、`statsUpdateInterval`、`showCalendar`、`timerPresets`、`showMirror`、`enableSystemHUD`、`lockScreenWeatherProviderSource`、`playerColorTinting`）；缺口（`type` / `default` / 取值范围）在各自 P2a 落地时按 06 §5.2/§5.3 的词汇表补齐，读侧口径照 06 §5.4（`config.json` 只存用户显式设过的值）。
- **理由**：上游这些键已有默认值与含义，用 06 §5 重新发明一遍会立刻产生"上游设置页改了、模块配置没跟"的双份真源（09 §0 原则 P1 要求上游功能维持现状）。

### T-4 timer 折叠态位置

- **结论**：`right`（动作类），order 10。
- **理由**：06 §6.2 的槽位语义表把 timer 直接列为 `right` 的示例。

### T-5 锁屏归属

- **结论**：16 行**全部不声明锁屏 surface**（D-12）；锁屏五面板群（音乐 / 天气 / 日历 / 提醒 / 计时器）与锁屏计时器面板维持上游现状，不归入任何模块 manifest。
- **理由**：09 §0 原则 P4 与 ADR-0011 第 5 条（「锁屏维持现状」，[00-decisions.md](00-decisions.md) §ADR-0011 决策表）均为「锁屏维持现状」，且 06 §6.1 的锁屏取值需要锁屏渲染管线先接入，本批没有该管线的消费者；加回路径是模块落地时按 06 §2.2 往 `surfaces` 追加锁屏取值。

### T-6 lunar 的 tab 注入

- **结论**：lunar 只声明 `compact` 单一 surface，「展开面板日历 tab 内增强」（09 §5.2）改由 calendar 模块的 tab 内容承担；lunar 不声明 `expanded`。
- **理由**：06 §6.1 把 `expanded` 定义为"展开区的 tab"，而 tab 在 06 §1/§4 的模型里归属唯一模块，两个模块共用一个 tab 会与 06 §3.3 R4（禁止模块间直接引用）冲突；等 P3 有"tab 内容插槽"再给 lunar 追加 `expanded`。

### T-7 notifications 浮层口径

- **结论**：新通知的折叠态瞬时浮层用内容描述符上的 `presentation: "hud"` + `ttlMs` 表达，**不新增 surface**；manifest 的 `surfaces` 只声明 `expanded`。
- **理由**：06 §6.1 已明文「不新增 `hud` 之类 surface：瞬时浮层（HUD）是 `expanded` 的一种呈现方式」，且上游 `AtollLiveActivityDescriptor` 的 `estimatedDuration` / `durationHint` 正是这个语义。

### T-8 读通知 capability 缺口

- **结论**：新增 capability **`notifications:read`**（读取系统通知内容与元数据，用于通知上岛），标注「**待落 06 号文档 §7.1**」；06 §7.1 现有的 `notifications` 只覆盖"经宿主发通知"，不能复用。**同批发现同类缺口**：07 号文档 §3.5 引用的 `calendar:read-titles` 同样不在 06 §7.1 表内，一并在该次补录时落表。
- **理由**：读取他人通知的隐私面显著大于发通知（09 §5.5 的能力边界与隐私提示），必须能与 `notifications` 分别拒绝，否则"允许发通知"会被读成"允许读通知"。

### T-9 shortcuts 权限冲突

- **结论**：以 06 §7.1 为准，shortcuts 声明 `shortcuts:run`；09 §5.4「无额外权限」的口径限定为**无系统 TCC 权限**（首次运行可能触发系统自动化提示）；执行前对具体指令名的二次确认由宿主承担（06 §7.1 该 capability 的定义原文）；内置模块不经过授予流程，但仍如实声明（06 §7 硬性规则 5）。
- **理由**：两处措辞不矛盾——09 §5.4 讲的是系统权限，06 §7.1 讲的是插件能力白名单；接管为内置模块后，声明的价值是设置页展示与代码审计一致性。

### T-10 内置声明粒度

- **结论**：粒度 = **一个模块一份 manifest、一行六列摘要**；模块内部不再细分（launcher 不拆"扫描 / 搜索 / 图标"），完整字段与默认值以各模块落地时的 Swift 声明为真源，本文不复制 06 §2.2 全表。
- **理由**：06 §6.1/§6.2 的 slot 与 tab 归属单位就是模块，拆细会争抢同一槽位；而 06 §1 已定"内置模块的 manifest 也能导出为 JSON"，文档手抄全字段只会变成第二份真源。

### T-11 LocalSend 局域网 capability

- **结论**：新增 capability **`network:local`**（局域网出站：组播发现 + 同网段 HTTP 传输），shelf 的 `permissions` 声明它，标注「**待落 06 号文档 §7.1**」；系统侧的本地网络访问仍由 TCC 与 `NSLocalNetworkUsageDescription` 承载。
- **理由**：06 §7.1 硬性规则 1 明确 `network:<host>` 只接受小写域名、不接受 IP 与通配符，而 LocalSend 的对端是同网段任意 IP（组播 `224.0.0.167` + 自带 HTTP server，09 §2 D），局域网能力在现表里无处表达。

### T-12 内置 manifest 取值口径

- **结论**：16 份 manifest 统一取 `manifestVersion` 1、`version` `"1.0.0"`、`apiVersion` = `HostInfo.currentAPIVersion`（当前 `1.0`）、`kind` `builtin`、`entry` 缺省、`icon.type` 取 `symbol`、`name`/`summary` 用 `LocalizedText` 的 `key` 形态（`module.<shortID>.name` / `module.<shortID>.summary`）；`defaultEnabled` 接管模块映射上游开关默认值，新增模块除 progress 外取 `false`。
- **理由**：前六项是 06 §2.2/§2.3/§2.4/§2.5 对内置的强制约束（`kind == builtin`、`entry` 出现即 `E_UNEXPECTED_FIELD`、内置 `icon` 必须 `symbol`），progress 已按此落地（D-11）；`defaultEnabled` 取保守值，与 06 §2.2「装了自动上屏不可接受」的取向一致。
- **2026-09-28 修订**：`progress` 由 `true` 改 `false`（用户判定「时间进度」无行动价值，[13](13-runtime-kernel.md) D-20）；新增的 `todos` 取 `true`——它是折叠态中央槽位的默认内容，上屏是它的存在理由（同为 D-20）。因此本批 `defaultEnabled` 的实际判据收敛成一条：**占中央槽位者取 `true`（现为 `todos`），其余一律 `false`（含被替换下来的 `progress`）**。

### T-13 只有字段名没有类型/默认值的项

- **结论**：09 §5.1～§5.6 里只有键名的配置项（launcher 的 `iconSize` / `density`、lunar 的 `displayFormat`、shortcuts 的 `timeoutSeconds`、notifications 的 `maxItems` / `pollIntervalSeconds`、terminal 的 `openMode` / `workingDirectory` 等）在各自落地批次按 06 §5.2/§5.3 的类型词表补齐类型与默认值；本文只登记键名与 09 原文已给枚举取值的键，**不在此处发明类型**。
- **理由**：06 §5 的类型词表（`boolean`/`integer`/`number`/`string`/`enum`/`color`/`hotkey`/`appPicker`/`filePath`/`dateRange`/`duration`/`secret`/`list`）已是唯一口径，doc 里再写一遍类型就与 Swift 声明形成双份真源（同 T-10 的理由）；已落地的 progress 三键（`list` + 两个 `enum`）是类型补全的样板。

---

## 3. 新 capability 待落清单

落地这些模块前，06 §7.1 的白名单需要先补下列条目（否则 manifest 校验会以 `E_UNKNOWN_PERMISSION` 拒绝）：

| capability | 用于 | 来源 |
|---|---|---|
| `notifications:read` | 读系统通知内容与元数据（通知上岛） | T-8 |
| `network:local` | 局域网出站（组播发现 + 同网段传输，LocalSend） | T-11 |
| `calendar:read-titles` | 事件标题 / 地点的细粒度读取（07 §3.5 的订阅裁剪表已引用） | T-8 附带发现 |

---

## 4. 一页速览

按"这份模块会碰到什么级别的平台面"分三类。**同一模块可出现在多类**（如 `controls` 既依赖 TCC 权限也依赖私有 API）。

### 4.1 零私有 API

`launcher`、`lunar`、`progress`、`todos`、`shortcuts`、`terminal`（09 §3.1 明示"本轮 6 项新增功能里有 5 项零私有 API"+ 2026-09-28 增补的 `todos` 同样零私有 API）+ 接管的 `lyrics`、`calendar`、`shelf`、`timer`、`clipboard`、`mirror`、`weather`。

> 注：`nowplaying` 依赖 `MediaRemote.framework`、`stats` 依赖 AppleSMC / `IOReport.framework`、`controls` 依赖 `CoreBrightness.framework` / `DisplayServices.framework`、`notifications` 依赖通知中心数据库——这 4 个不在此类，逐条见 [15-platform-dependencies.md](15-platform-dependencies.md) §1。

### 4.2 依赖 TCC 权限

| 模块 | 依赖的系统授权（09 §3.3） |
|---|---|
| `calendar` | 日历、提醒 |
| `todos` | 提醒（EventKit 取数 + 写回完成状态；`permissions` 仍为 `[]`——系统 TCC 不是模块 capability，见 06 §7.1） |
| `weather` | 位置 |
| `mirror` | 相机 |
| `notifications` | 完全磁盘访问（主）；辅助功能（降级方案） |
| `controls` | 辅助功能（媒体键 / 亮度键拦截）；完全磁盘访问（读 `~/Library/DoNotDisturb/DB/*` 的 Focus 只读，该路径同时是上游的 FDA 自检探针——`helpers/FullDiskAccessPermissionStore.swift:28`） |
| `shelf` | 本地网络（LocalSend） |
| `timer` | 通知（到点提醒的用户授权） |

### 4.3 依赖私有数据

| 模块 | 私有数据 | 台账条目 |
|---|---|---|
| `nowplaying` | `MediaRemote.framework` / `MediaRemoteAdapter.framework` 的媒体元数据与控制 | 15 号文档 §1 第 1、2 条 |
| `stats` | AppleSMC 温度、`IOReport.framework` 频率 | 15 号文档 §1 第 5 条（另第 6 条 CGS 私有函数属内核窗口层，不归模块） |
| `controls` | `CoreBrightness.framework`（亮度 / 键盘背光）、`DisplayServices.framework`（亮度回退）、DoNotDisturb DB（Focus 只读） | 15 号文档 §1 第 3、4、9 条 |
| `notifications` | 通知中心数据库（只读 SQLite） | 15 号文档 §1 第 11 条 |
