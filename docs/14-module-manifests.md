# 内置模块清单（15 个模块 + 终端条目；2026-09-28 增补 `todos` → 16 个模块 + 终端条目；2026-09-30 增补 `music` → 17 个模块 + 终端条目；2026-09-30 再增补 `frontapp` → 18 个模块 + 终端条目）

这份文档回答一件事：**18 个内置模块（接管 10 + 新增 8）与终端条目，各自的 manifest 声明什么。**（口径注：`com.cmeng.gourd.music` 在本表算「新增 id」——它是本批新造的模块 id、替代原清单里的 `nowplaying` 行；[09](09-features-and-mechanisms.md) §8.1 的枚举把它归在「音乐/接管」那一项里。两处指同一份 manifest，分组口径不同而已。） 它是 P1-0 前置清障第 3 项（[12-p1-batches.md](12-p1-batches.md) §P1-0）的产物，也是 [09-features-and-mechanisms.md](09-features-and-mechanisms.md) §8.1 已拍板模块化边界的逐项落地。**2026-09-28**：新增第 6 个新增模块 `com.cmeng.gourd.todos`（见 §1 的 todos 行与开头说明），本文的「16 份 manifest」相应变成 17 份。**2026-09-30**：`p2-takeover` 批次落地的音乐块用的是**新增模块 id `com.cmeng.gourd.music`**（不是 §1 原清单里的 `nowplaying`，见 §1 的 music 行与表下说明）——「17 份 manifest」相应变成 18 份。**2026-09-30 同日再增补**：`p2-shortcuts-frontapp` 批次落地 `com.cmeng.gourd.shortcuts`（快捷指令，原清单已有此行）与**原清单没有的** `com.cmeng.gourd.frontapp`（前台应用，见 §1 的 frontapp 行）——「18 份 manifest」相应变成 **19 份**；两个模块都只声明一个既有 surface、默认关、零新增 capability。**2026-09-30 再补（批次 `p3-widgets`）**：本批落地的是**原清单里已有的 `stats` 行**（不是新模块 id：`com.cmeng.gourd.stats` 落成首页小组件，`compact` / `expanded` 改判为 **`[.home]`**）并把 `progress` 由 `expanded` 改 `[.home]`——**「19 份 manifest」的计划数不变**，而**实测已落地 11 份**（`calendar` 由 `p3-freeze`、`stats` 由本批落地，见开头的「计数口径」段）。

> **计数口径（2026-09-30 起，读这份文档前先读这一段）**：本文的清单是**计划口径**——§1 表里每一行都是「打算声明什么」，其中大部分**还没落地**。**今天真正已落地的 manifest 有 11 份**，按实测取数（`grep -c` 按文件逐行打印，十一个 `1` 之和 = 11）：
> ```
> $ grep -c "static let manifest = ModuleManifest" DynamicIsland/**/*.swift | grep -v ':0$'
> DynamicIsland/Modules/FrontApp/FrontAppModule.swift:1
> DynamicIsland/Modules/Shortcuts/ShortcutsModule.swift:1
> DynamicIsland/Modules/Takeover/StatsModule.swift:1
> DynamicIsland/Modules/Launcher/LauncherModule.swift:1
> DynamicIsland/Modules/ProgressModule.swift:1
> DynamicIsland/Modules/NotificationsModule.swift:1
> DynamicIsland/Modules/Takeover/CalendarModule.swift:1
> DynamicIsland/Modules/Takeover/MusicModule.swift:1
> DynamicIsland/Modules/Takeover/TimerModule.swift:1
> DynamicIsland/Modules/Takeover/MirrorModule.swift:1
> DynamicIsland/Modules/TodosModule.swift:1
> ```
> 这十一份是 `frontapp` / `shortcuts` / `stats` / `launcher` / `progress` / `notifications` / `calendar` / `music` / `timer` / `mirror` / `todos`（等价写法：`grep -rn "static let manifest = ModuleManifest" DynamicIsland/ | wc -l` → `11`）。**「9 份」是 2026-09-30 早些时候（`p2-shortcuts-frontapp` 之后、`p3-freeze` 与 `p3-widgets` 之前）的数**——`calendar`（`p3-freeze`）与 `stats`（`p3-widgets`）之后各多一份。**凡本文出现「16 个模块 / 17 份 manifest」这类写死的总数，一律按实测口径读**（那是各批当时的计划数，不是今天的落地数）；要核对「报的模块到底在不在」，以 `grep` 与 §1 各行状态为准。


与其它文档的分工：

| 文档 | 管什么 |
|---|---|
| [06-module-protocol.md](06-module-protocol.md) | **字段级契约**：`ModuleManifest` / `GourdModule` / surface / slot / capability / ConfigSchema 的词表与校验规则。本文不复制、不改写 |
| [09-features-and-mechanisms.md](09-features-and-mechanisms.md) | **功能与机制**：每个模块做什么、靠什么实现、配置键叫什么、优先级多高 |
| [13-runtime-kernel.md](13-runtime-kernel.md) | **P1 批次的范围与裁定**（D-07 试点模块、D-09 清单口径、D-12 不声明锁屏、D-14 平台台账口径） |
| [15-platform-dependencies.md](15-platform-dependencies.md) | 这些模块落到哪条私有 API / 子进程 / 外部域名上 |

**取值一律逐字引 06 号与 09 号文档**：`surfaces` 取 06 §2.2 的四个取值（本清单用到 `compact` / `expanded` / `home`——`home` 今天出现在 `todos` / `notifications` / `mirror` / `music` / `frontapp` 五行，见 §1 表下说明；锁屏取值见 T-5）；`slot` 取 06 §6.2 的 `left` / `right` / `center`；`permissions` 取 06 §7.1 的白名单词；`config` 键名取 09 §5 原文（新增模块）或上游 `Defaults` 键（接管模块）。本文**不新造字段名、不新造取值词汇**。

已有落地样本：`com.cmeng.gourd.progress`（`DynamicIsland/Modules/ProgressModule.swift`，P1 批次 T4）与 `com.cmeng.gourd.todos`（`DynamicIsland/Modules/TodosModule.swift`，P1 批次 T5）——表内对应行的 `surfaces` / `permissions` / `config` 键名与它们一致；`defaultPlacement` 的**当前值**见各自行注与 T-1（本批 `order` 还被兼作 expanded tab 的排序键，见 [13](13-runtime-kernel.md) 已知限制 25）。

**2026-09-28 增补**：`com.cmeng.gourd.todos`（待办）不在 P1-0 定稿的 16 份 manifest 内——它是用户当日判定「进度无行动价值」后新增的**第 17 份**（模块计 16 个：接管 10 + 新增 6；终端仍是独立条目），并接过 `progress` 空出的折叠态中央槽位（[13](13-runtime-kernel.md) D-20）。下表按模块逐个列出，`todos` 行紧跟 `progress` 之后。

**2026-09-29 变更**：P2 批次 `p2-home-strip` 给 `todos` 加了 `home` surface（首页 strip 的一块）——**该批没有新增模块**（只是 `todos` 多了一个 `surfaces` 取值；`notifications` 的 `home` 由次日的 `p2-p0-visible` 批次补上，故「`progress` 与 `notifications` 均不声明 `home`」这句**只在 2026-09-29 当天成立**）；`progress` **不声明** `home`（默认关、声明了也没内容），理由与逐条口径见 §1 表下说明与 [17-nookx-adoption.md](17-nookx-adoption.md)。**当时写的「仍 16 个模块 / 17 份 manifest」是按当时的计划清单说的**——2026-09-30 起模块数与落地数以开头「计数口径」段与 §1 各行状态为准（实测已落地 manifest **11 份**）。

---

## 1. 清单

**列含义**：`surfaces` 与 `slot` 见 06 §6.1/§6.2（`slot` 只在 `surfaces` 含 `compact` 时有意义）；`permissions` 见 06 §7.1；`config 关键项` 只列关键键名（完整 schema 在各自落地批次按 06 §5 写全，见 T-10/T-13）；`优先级/依赖` 取 09 §6 路线图。

| id | surfaces | slot | permissions | config 关键项 | 优先级/依赖 |
|---|---|---|---|---|---|
| `com.cmeng.gourd.nowplaying` | `compact`、`expanded` | `center` / order 10 | `media:read`、`media:control`、`network:itunes.apple.com` | `playerColorTinting`、`useMusicVisualizer`、`visualizerBarCount`、`enableWaveformScrubber`（接管映射，见 T-3） | P2a 首批；依赖 15 号文档 §1 的 `MediaRemote.framework` / `MediaRemoteAdapter.framework`。**注（2026-09-30）**：它的 `home` 形态（首页音乐块）**已由下一行的 `com.cmeng.gourd.music` 落地**——本行**不动**（那是另一个模块 id）：`compact` / `expanded`、`media:read` / `media:control` / `network:itunes.apple.com` 三个 capability 与 `visualizerBarCount` / `enableWaveformScrubber` 两键**均待后续批次** |
| `com.cmeng.gourd.music` | `home` | — | `[]` | `playerColorTinting`、`useMusicVisualizer`（接管映射，见 T-3） | **已落地（2026-09-30，批次 `p2-takeover`）**：首页音乐块（渲染点 = 上游 `MusicPlayerView(albumArtNamespace:)`，判据 = `showStandardMediaControls && (!autoHideInactiveNotchMediaPlayer \|\| hasActiveSession)`）；`surfaces` = **`[.home]`**、`defaultPlacement: Placement(slot: nil, order: 0)`（= 被接管的内置音乐块原本的默认序号）、`defaultEnabled: true`（= `showStandardMediaControls` 上游默认）、`permissions: []`、块宽继承 300 / 420；启用真源 = `showStandardMediaControls`（接管模块，口径见 T-12）。**本批真正新增的模块 id 是它**（原清单里没有这一行：本批只落「首页音乐块」这一处渲染点，因此没有占用 `nowplaying` 的 id）；`compact` / `expanded` 不声明（本批不占折叠槽位），后台播放会话仍由上游 `MusicManager` 承担 |
| `com.cmeng.gourd.lyrics` | `compact`、`expanded` | `center` / order 20 | `media:read`、`events:subscribe:media.playbackChanged`、`network:lrclib.net` | `enableLyrics`、`lyricsPanelWidth`、`lyricsPanelOffset` + 歌词磁盘缓存开关（09 §2 A 的 🔧 缺陷修复） | P2a；曲目变化经 EventBus 订阅，不做模块间直接引用（06 §3.3 R4） |
| `com.cmeng.gourd.stats` | **`home`**（**已落地（2026-09-30，批次 `p3-widgets`）**：首页小组件 = CPU / 内存 / GPU **三环**并排——环心百分比、环下 9pt 标签、按指标分色（青 / 紫 / 琥珀）；`compact` / `expanded` / `lockscreen` 一律不声明，**展开 tab 已摘**（用户明确「不需要单独面板」；完整图在设置页的统计页做预览）） | — | `[]`（接管：只搬渲染归属与开关真源，不新增能力） | `enableStatsFeature`（**真源键**）、`showCpuGraph`、`showMemoryGraph`、`showGpuGraph`（后三个是**登记键**——上游统计设置页仍在读写它们，是完整图的可见性来源） | **已落地（2026-09-30，批次 `p3-widgets`）**：`surfaces` = **`[.home]`**、`defaultPlacement: Placement(slot: nil, order: 50)`（= 现有模块序号最大值 40 + 10，落在 notifications 之后）、`defaultEnabled` = `enableStatsFeature` 的上游默认值（`false`）、`permissions: []`、块宽声明 **220 / 300**（`StatsRingMetrics` 钉住「220pt 最小块宽下三环 158pt 不裁」）；启用真源 = `enableStatsFeature`（接管模块，口径见 T-12 与 [26](26-home-widgets-and-settings.md)）。**采样驱动在模块侧**（块可见期间 1s 看门狗 + `onDisappear` 停）——上游「停在 stats tab 才采样」那条路径随 tab 摘除已不可达。原计划行的 `compact` / `slot: left` / `system:metrics` capability 与本行的 `statsUpdateInterval` / `statsStopWhenNotchCloses` 两键**均待后续批次**。依赖 15 号文档 §1 的 AppleSMC（温度）/ `IOReport.framework`（频率） |
| `com.cmeng.gourd.calendar` | `expanded`（**已落地（2026-09-30，批次 `p3-freeze`）**：展开面板一个「日历」tab，渲染点 = 上游孤儿视图 `StandaloneCalendarView()`，启用真源 = `showCalendar`（与首页日历行同一个键）；`p3-widgets` / T4 又给它加了两处呈现修正——首页行与面板都传 `showsScrollFades: false`（上下两条渐变两处都没有了）、月历日格多一行农历 / 节假日名） | — | `[]`（事件标题/地点的细粒度读取另需 `calendar:read-titles`，**待落 06 号文档 §7.1**，见 T-8 / §3） | `showCalendar`、`hideCompletedReminders`、`hideAllDayEvents`（接管映射；`config` 不登记——没有本模块自己的键） | **已落地（2026-09-30，批次 `p3-freeze`；增强见 `p3-widgets` / T4）**；事件与提醒读取走 EventKit，依赖日历 / 提醒 TCC 授权 |
| `com.cmeng.gourd.shelf` | `expanded` | — | `files:picker`、`files:shelf`、`network:local`（**待落 06 号文档 §7.1**） | `dynamicShelf`（接管映射）+ LocalSend 传输开关（09 §2 D） | P2a；依赖本地网络 TCC（`NSLocalNetworkUsageDescription`，09 §7 必办项） |
| `com.cmeng.gourd.timer` | `compact`、`expanded` | `right` / order 10 | `timers`、`notifications` | `enableTimerFeature`、`timerDisplayMode`、`timerPresets` + 计时器持久化与到点通知（09 §2 C 的 🔧 缺陷修复） | **已落地（2026-09-30，批次 `p2-takeover`）**：`surfaces` 收敛为**只 `expanded`**（展开面板的计时器 tab，渲染点 = 上游 `NotchTimerView`）、`defaultPlacement: nil`（tab 落模块 tab 段）、`defaultEnabled: true`（= `enableTimerFeature` 上游默认）、`permissions: []`；启用真源 = `enableTimerFeature`，`isTabVisible()` = `timerDisplayMode == .tab`；**`compact` / `slot: right` 待折叠态左右槽位落地后再声明**（T-4 的分配口径不变）。P2a；到点通知依赖 `notifications` capability |
| `com.cmeng.gourd.clipboard` | `compact`、`expanded` | `right` / order 20 | `clipboard:read`、`clipboard:write` | `enableClipboardManager`、`clipboardDisplayMode` + 电池上降频（09 §2 D 的 🔧 缺陷修复） | P2a；`clipboard:read` 只给元数据（06 §7 硬性规则 2） |
| `com.cmeng.gourd.controls` | `expanded` | — | `power:control` | `enableSystemHUD`、`enableVolumeHUD`、`enableBrightnessHUD`、`enableKeyboardBacklightHUD`、`enableCustomOSD`（接管映射；surfaces 口径见 T-2） | P2a；依赖辅助功能 TCC（媒体键 / 亮度键拦截） |
| `com.cmeng.gourd.weather` | `compact`、`expanded` | `left` / order 20 | `network:api.open-meteo.com`、`network:air-quality-api.open-meteo.com`、`network:wttr.in` | `lockScreenWeatherProviderSource`、`lockScreenWeatherTemperatureUnit`、`lockScreenWeatherRefreshInterval`（接管映射） | P2a；依赖位置 TCC |
| `com.cmeng.gourd.mirror` | `expanded` | — | `[]` | `showMirror`、`mirrorShape`、`selectedCameraID`（接管映射） | **已落地（2026-09-30，批次 `p2-takeover`）**：`surfaces` 收敛为 **`[.home]`**（首页 strip 的镜子块，渲染点 = `CameraPreviewView(webcamManager:)`，判据 = `showMirror && cameraAvailable`）、`defaultPlacement: Placement(slot: nil, order: 2)`（= 被接管的内置镜子块原本的默认序号）、`defaultEnabled: false`（= `showMirror` 上游默认）、`permissions: []`、块宽继承 140 / 160；启用真源 = `showMirror`。P2a；依赖相机 TCC（上游 `WebcamManager` 本来就有的那条，本模块不新增） |
| `com.cmeng.gourd.launcher` | `compact`、`expanded` | `right` / order 30 | `[]` | `showRecents`、`iconSize`、`density`（`pinnedApps` **不是** manifest config：它是 `Defaults` 键，见 [09](09-features-and-mechanisms.md) §5.1）（09 §5.1） | P2b 第 4；全局热键用上游 `KeyboardShortcuts`（**2026-09-30 已落地**：`surfaces` 收敛为**只 `expanded`**——`compact`/`slot: right` 待折叠态左右槽位落地后再声明；`defaultEnabled: false`） |
| `com.cmeng.gourd.lunar` | `compact` | `left` / order 30 | `[]` | `displayFormat`、`showFestivals`（09 §5.2） | P2b 第 1；展开区归属见 T-6 |
| `com.cmeng.gourd.progress` | **`home`**（**已落地（2026-09-30，批次 `p3-widgets`）**：首页块 = **紧凑清单**——一行一个尺度：图标 + 标签 + 细进度条 + 百分比；块宽 180 / 240，放置后宽 ≥ 220pt 画两行、否则一行。~~展开态 = 剩余量清单~~（视图代码保留、**不挂 surface**，可逆）。~~`compact`（折叠态中央槽位常驻百分比）~~ **2026-09-30 撤销**（批次 `p3-freeze`）：那枚「尺度图标 + 百分比」在关闭态与亮度 HUD 同形） | `slot: nil` / order 30（`slot` 只在含 `compact` 时有意义；`order` **保留 30**——它今天的含义是**首页块顺序**：[13](13-runtime-kernel.md) 已知限制 25 的双语义，落在 todos 20 与 notifications 40 之间） | `[]` | `visibleScopes`（默认 `day` + `year`）、`style`、`baseCalendar`（09 §5.3；已落地三键） | **已落地（2026-09-30，批次 `p3-widgets`）/ 默认关（`defaultEnabled = false`，2026-09-28 用户判定「时间进度」无行动价值，见 [13](13-runtime-kernel.md) D-20）**：代码与 manifest 保留、可手动开回（**开回后只在首页出一块**，关闭态不挂 pill、展开面板不再有 tab）。它不是接管模块（没有上游总开关）：启用仍走 `moduleEnableOverrides` → `manifest.defaultEnabled`。落地：P1-4 提前消化 P2b 第 2；折叠态中央槽位 2026-09-27 落地、**2026-09-30 撤销**（口径与 launcher / shortcuts / frontapp / calendar 一致） |
| `com.cmeng.gourd.todos` | `compact`、`expanded`、`home`（折叠态 = 图标 + **今日**的 `已办/总量`；展开态 = 顶部三环「今日 / 本周 / 所有」+ 下方该类别清单，环本身是筛选器；**首页块 = 三环横排 + 今日清单前 5 条，块宽 < 220pt 时只画三环**，2026-09-29 加） | `center` / order 20 | `[]` | **无（第一版不做配置）** | **已落地（P1 批次 T5，2026-09-28；`home` 由 P2 批次 `p2-home-strip` 于 2026-09-29 加）**；`defaultEnabled: true`——它是折叠态中央槽位的默认内容（`order` 20 < progress 的 30，见 [13](13-runtime-kernel.md) D-20）；依赖提醒 TCC（系统授权，不是模块 capability，故 `permissions` 为空集）（2026-09-29 起展开面板为四视图左导航 + 右看板 + 行内优先级胶囊） |
| `com.cmeng.gourd.shortcuts` | `expanded`（**已落地（2026-09-30，批次 `p2-shortcuts-frontapp`）：只声明展开 tab**；原「折叠态槽位可选，见 T-1」的那一半**不声明**——T-1 预留的 `right` / order 40 未启用，仍随折叠态左右槽位那批） | — | `shortcuts:run` | `pinnedShortcuts`、`showOutput`、`timeoutSeconds`、**`cachedShortcuts`**（缓存存**原始行**；四键全落地，09 §5.4） | **已落地（2026-09-30，批次 `p2-shortcuts-frontapp`）**：`defaultPlacement: nil`（tab 落模块 tab 段）、`defaultEnabled: false`、`permissions` 照旧 `["shortcuts:run"]`（06 §7.1 既有条目，**零新增 capability**）；取数 `/usr/bin/shortcuts list --show-identifiers` 与运行 `shortcuts run <identifier>` 都限时、模块级禁并发，解析与运行分两个注入点（设计 [22](22-shortcuts-and-frontapp.md)）。**原列「依赖 shelf 的文件输入联动（`--input-path`）」本批未做**（没有输入源，Shelf 联动仍挂 shelf 模块） |
| `com.cmeng.gourd.frontapp` | `home`（**已落地（2026-09-30，批次 `p2-shortcuts-frontapp`）**：首页一块——当前前台应用的大图标 + 名称，下面一排最近切换过的小图标，点一下切回去；`compact` / `expanded` / `lockscreen` 一律不声明） | — | `[]` | `maxRecentApps`（`integer`，默认 `5`，运行时夹取 `3...8`） | **已落地（2026-09-30，批次 `p2-shortcuts-frontapp`）**：**本批新增的模块 id（原清单里没有这一行）**；事件源 = `NSWorkspace.shared.notificationCenter` 的 `didActivateApplicationNotification` + `NSRunningApplication`（**公开 API、零 TCC、零私有 API**）、`defaultPlacement: Placement(slot: nil, order: 30)`（首页块顺序，待办 20 与通知 40 之间）、`defaultEnabled: false`、`homeBlockWidth` 不重写（宿主统一值 180/240）。**折叠态侧槽形态仍随左右槽位那批**（[16](16-nookx-reference.md) §4.2 A5 的另一半）；设计 [22](22-shortcuts-and-frontapp.md) |
| `com.cmeng.gourd.notifications` | `expanded`、`compact`、`home`（2026-09-29 起声明首页块；浮层用 `presentation: hud`，见 T-7） | — | `notifications:read`（**待落 06 号文档 §7.1**） | `showBodyInHUD`、`appsFilter`、`maxItems`、`pollIntervalSeconds`（09 §5.5） | P2c（先做可行性探针）；依赖完全磁盘访问 TCC |
| `com.cmeng.gourd.terminal`（终端，独立条目） | `expanded` | — | `[]` | `mode`、`externalApp`、`openMode`、`workingDirectory`、`extraArguments`（09 §5.6） | P2b 最后；依赖 Ghostty 启动参数验证（09 §5.6 的实测项） |

**2026-09-30 的三行落地（批次 `p2-takeover`）**：`timer` / `mirror` 两行标了「已落地」，音乐那一处渲染点落在
**新增的 `music` 行**（`nowplaying` 行只留了一条指向它的注记），三处的**落地粒度不同**，别读成「这些模块都做完了」：

- **音乐 = `music` 行的 `home` 形态**（首页音乐块）——`nowplaying` 本行**一行未动**：它的 surface（`compact` /
  `expanded`）与 `media:read` / `media:control` / `network:itunes.apple.com` 三个 capability、
  `visualizerBarCount` / `enableWaveformScrubber` 两个 config 键**都待后续批次**；后台的播放会话仍由上游
  `MusicManager` 承担（本批只搬渲染归属与开关真源）。
- **`timer` 只落了 `expanded`**（展开 tab）：`compact` / `slot: right` 与 `timers` / `notifications`
  两个 capability 待折叠态左右槽位落地时再声明；到点提醒仍是上游 `TimerManager` 的行为。
- **`mirror` 落的是 `home`**（首页块）：它本来就只有这一处渲染点，故这一行最接近「做完」；
  但摄像头采集会话仍由上游 `WebcamManager` 持有。

三行的 `config` 都**只登记键名与上游默认值**（读侧仍读上游键，见 T-3 的 2026-09-30 落地行）。

**2026-09-30 的两行落地（批次 `p2-shortcuts-frontapp`）**：`shortcuts`（原清单已有此行）与 `frontapp`
（**新增行**，见上文）都标了「已落地」，两行的落地粒度都**只覆盖一个 surface**：

- **`shortcuts` 只落了 `expanded`**（展开面板一个 tab：搜索框 + 刷新按钮 + 列表 + 结果行）：
  取数走 `/usr/bin/shortcuts list --show-identifiers`、运行走 `shortcuts run <identifier>`
  （`showOutput` 时加 `--output-path` 读回），**限时 + 模块级禁并发**；`config` 是本批**第一次真读真写**
  `com.cmeng.gourd.module.shortcuts` 域的四键（含缓存键 `cachedShortcuts`，存**原始行**）。
  折叠态槽位与「Shelf 文件输入联动」都**未做**（前者随左右槽位、后者没有输入源）。
- **`frontapp` 落的是 `home`**（首页块）：事件源是公开通知，零 TCC；折叠态侧槽那半**未做**
  （同样随左右槽位那批）。它**不在 P1-0 的清单里**——本批发现"首页块形态不依赖已降级的左右槽位"
  才补的行（先例：`music` 也是接管批次补的行）。

两行的 `config` 都是**可读可写**的（不像 `timer` / `mirror` / `music` 只登记、读写走上游键）：
它们没有上游键可映射，就用自己的域 `com.cmeng.gourd.module.<shortID>`，默认值只有代码里那一处常量。

**2026-09-29 的 `home` 取值（P2 批次 `p2-home-strip`，后由 `p2-p0-visible` 增补）**：`home` 目前出现在 **todos 与 notifications 两行**——`todos` 是首批（三环横排 + 今日清单前 N 条），`notifications` 在 2026-09-29 的 `p2-p0-visible` 批次补上（「通知 · 最近 N 条」+ 最近 3 条，点条目开 App 并收起）。**`progress` 保留代码与 manifest 但不声明 `home`**（它默认关、声明了也没内容，组件卡已标注"暂不出现在首页"）。原说明（17-nookx-adoption.md](17-nookx-adoption.md) 已知限制 9）。**本批没有新增模块**（`todos` / `notifications` 各只是多了一个 `home` 取值）——那一批的「16 个模块 / 17 份 manifest」是**当时的计划数**。**2026-09-30 补充**：本批之后 `home` 出现在四行（上述两行 + `mirror` 与 `music`），而这一批**确实新增了一个模块 id**——`com.cmeng.gourd.music`（见 §1 的 music 行），因为本批把接管的音乐块落在一个新 id 上而不是 `nowplaying`；**今天的落地数按开头的「计数口径」段读（实测已落地 manifest 11 份）**，写死的总数一律以那份口径为准。**2026-09-30 同日再补（批次 `p2-shortcuts-frontapp`）**：`home` 增加到**五行**——新增的 `frontapp` 也声明 `home`（首页一块：当前前台应用 + 最近切换，见 §1 的 frontapp 行），本批**新增的模块 id 是它**（`shortcuts` 是原清单里已有的行、本批落地）。**2026-09-30 再补（批次 `p3-widgets`）**：`home` 增加到**七行**——`progress` 由 `expanded` 改 `[.home]`（首页块 = 紧凑清单，§1 的 progress 行）、新增的 `stats` 也声明 `home`（三环，§1 的 stats 行）。同日**首页分带**落地：声明 `home` 的模块按 manifest 的 `homeFormFactor` 进两条带——缺省 `.compact` 进**小组件带**（进度 / 统计 / 待办 / 通知 / 前台应用），音乐 / 镜子显式 `.large` 进**主块带**；设计见 [26](26-home-widgets-and-settings.md) §做法 机制六。

**两处「不是模块」的说明**（避免清单被读成"全部功能都模块化"）：

- **终端是独立条目**：它不是 `GourdModule` 的渲染单元，而是上游终端功能的"外部 App 模式"配置载体（09 §5.6）；列在表内是为了让清单的模块边界闭合（D-09），落地时按同一份 manifest 模型声明。
- **锁屏五面板群不在表内**：音乐 / 天气 / 日历 / 提醒 / 计时器的锁屏面板维持上游现状（09 §0 原则 P4），不归入任何模块，见 T-5。

---

## 2. 未决口径裁定（T-1…T-13）

调研标记的 13 处未决口径逐条给结论。每条的**理由都指向已定契约或已实测证据**，不引入新词汇。

### T-1 槽位分配

- **结论**：`center`（主内容，独占 1）：nowplaying（order 10）、lyrics（order 20）；`left`（状态类，默认上限 3）：stats（10）、weather（20）、lunar（30）、progress（40）；`right`（动作类，默认上限 3）：timer（10）、clipboard（20）、launcher（30）。shortcuts 的折叠态槽位**默认不声明**，其落地时若声明则记 `right` / order 40。落在默认上限之外的模块（progress、shortcuts）**不进槽位但保持 active**，用户调高 `config.layout.compact.maxPerSide` 或禁用他人后自动补位。（**2026-09-27 回写**：中央槽位先行落地——progress 以 `slot: center` / order 30 常驻居中，本表 `left` / order 40 的分配与每侧上限仍是三槽布局落地时的口径，见 [13](13-runtime-kernel.md) D-19 与「明确不做」。）（**2026-09-30 回写**：`shortcuts` 已落地为**只声明 `expanded`**——上面预留的 `right` / order 40 **未启用**，折叠槽位仍随左右槽位那批；见 §1 的 shortcuts 行。）（**2026-09-30 再回写（`p3-widgets`）**：`progress` 已改判为**只声明 `home`**——本表给它预留的 `left` / order 40 与折叠槽位那半一样**不生效**（它今天既不占折叠槽、也没有展开 tab）；它的 `order 30` 只剩一个含义：**首页块顺序**（落在 todos 20 与 notifications 40 之间）。`stats` 同批也改判为 `[.home]`，本表给它的 `left` / order 10 同样不生效，见 §1 的 stats 行。）
- **理由**：06 §6.2 已给类别语义与示例（`left` 状态类 stats / weather、`right` 动作类 timer / clipboard、`center` 独占主内容 nowplaying / lyrics），其余模块按同类别归入，超出上限的处置也是 06 §6.2 原文；progress 本批未声明 `compact`（D-07），故表中 `slot` 记 —，其分配值在折叠态落地后生效。**注意 progress 的 `order` 有两个值不要混**：本表 `left` 行写的 **40** 是折叠态槽位的预留值；当前代码里 `defaultPlacement.order` 是 **30**，它在本批被兼作 expanded tab 的排序键（[13](13-runtime-kernel.md) 已知限制 25）——折叠态落地时必须拆字段或同步改写，不能沿用同一字段的双关语义。（**已处理**：中央槽位落地时按「明确写下双语义」分支处理，`order` 仍同时供两处排序，见 [13](13-runtime-kernel.md) 已知限制 25 的落地回写。）

### T-2 controls 的 surfaces

- **结论**：controls 只声明 `expanded`，不声明 `compact`。
- **理由**：它在 09 §2 E 里的上游形态是 HUD 与媒体键（音量 / 亮度 / 键盘背光 / 防休眠 / 外接屏亮度），是密集交互面板而非"一个图标能表达的状态"，塞进 06 §6.2 的图标槽只会做一个反复展开的开关。

### T-3 接管模块 config schema 缺口

- **结论**：接管 10 个模块的 config **不新发明键**，一律映射上游既有 `Defaults` 键（如 `enableLyrics`、`dynamicShelf`、`enableClipboardManager`、`statsUpdateInterval`、`showCalendar`、`timerPresets`、`showMirror`、`enableSystemHUD`、`lockScreenWeatherProviderSource`、`playerColorTinting`）；缺口（`type` / `default` / 取值范围）在各自 P2a 落地时按 06 §5.2/§5.3 的词汇表补齐，读侧口径照 06 §5.4（`config.json` 只存用户显式设过的值）。
- **理由**：上游这些键已有默认值与含义，用 06 §5 重新发明一遍会立刻产生"上游设置页改了、模块配置没跟"的双份真源（09 §0 原则 P1 要求上游功能维持现状）。
- **2026-09-30 落地（批次 `p2-takeover`，`timer` / `mirror` / `music` 三个接管模块）**：本批落地为**只登记键名与上游默认值**——`ConfigSchema` 的 `type` / `default`（`mirrorShape` 另有 `values`）按 06 §5.2/§5.3 写全，**读写仍走上游键**：`ConfigHandle`（写 `com.cmeng.gourd.module.<shortID>`）对它们不生效，`config.json` 里不落这三个模块的值。默认值一律从 `Defaults.Keys.<键>.defaultValue` 取，不另抄字面量（`music.useMusicVisualizer` 的上游真值是 `true`，`DynamicIsland/models/Constants.swift:989`）。登记的价值是**声明与审计一致性**（变更前先看这里能不能对上真源）；写路径接管属配置层（P1-3 的 ConfigStore），见 [20](20-component-page.md) §已知限制 1 与 §决策摘要 D-03 / D-15。

### T-4 timer 折叠态位置

- **结论**：`right`（动作类），order 10。
- **理由**：06 §6.2 的槽位语义表把 timer 直接列为 `right` 的示例。

### T-5 锁屏归属

- **结论**：清单里每一行（**本批后 19 行**：18 个模块 + 终端条目；含 2026-09-30 新增的 `frontapp`）**全部不声明锁屏 surface**（D-12）；锁屏五面板群（音乐 / 天气 / 日历 / 提醒 / 计时器）与锁屏计时器面板维持上游现状，不归入任何模块 manifest。
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
- **2026-09-30 落地（批次 `p2-shortcuts-frontapp`）**：`ShortcutsModule.manifest.permissions` 逐字
  `["shortcuts:run"]`（`DynamicIsland/Modules/Shortcuts/ShortcutsModule.swift`），零新增 capability；
  **"首次运行会不会弹系统自动化提示"本批没有现场证据**（用例不跑真命令，也没有人工点过一次）——
  口径保持 T-9 原文的"可能触发"，见 [22](22-shortcuts-and-frontapp.md) §已知限制 1。

### T-10 内置声明粒度

- **结论**：粒度 = **一个模块一份 manifest、一行六列摘要**；模块内部不再细分（launcher 不拆"扫描 / 搜索 / 图标"），完整字段与默认值以各模块落地时的 Swift 声明为真源，本文不复制 06 §2.2 全表。
- **理由**：06 §6.1/§6.2 的 slot 与 tab 归属单位就是模块，拆细会争抢同一槽位；而 06 §1 已定"内置模块的 manifest 也能导出为 JSON"，文档手抄全字段只会变成第二份真源。

### T-11 LocalSend 局域网 capability

- **结论**：新增 capability **`network:local`**（局域网出站：组播发现 + 同网段 HTTP 传输），shelf 的 `permissions` 声明它，标注「**待落 06 号文档 §7.1**」；系统侧的本地网络访问仍由 TCC 与 `NSLocalNetworkUsageDescription` 承载。
- **理由**：06 §7.1 硬性规则 1 明确 `network:<host>` 只接受小写域名、不接受 IP 与通配符，而 LocalSend 的对端是同网段任意 IP（组播 `224.0.0.167` + 自带 HTTP server，09 §2 D），局域网能力在现表里无处表达。

### T-12 内置 manifest 取值口径

- **结论**：清单里的每一份 manifest（计划 18 个模块 + 终端条目 = 19 份；**已落地实测 11 份**，见开头「计数口径」）统一取 `manifestVersion` 1、`version` `"1.0.0"`、`apiVersion` = `HostInfo.currentAPIVersion`（当前 `1.0`）、`kind` `builtin`、`entry` 缺省、`icon.type` 取 `symbol`、`name`/`summary` 用 `LocalizedText` 的 `key` 形态（`module.<shortID>.name` / `module.<shortID>.summary`）；`defaultEnabled` 接管模块映射上游开关默认值，新增模块除 progress 外取 `false`。
- **理由**：前六项是 06 §2.2/§2.3/§2.4/§2.5 对内置的强制约束（`kind == builtin`、`entry` 出现即 `E_UNEXPECTED_FIELD`、内置 `icon` 必须 `symbol`），progress 已按此落地（D-11）；`defaultEnabled` 取保守值，与 06 §2.2「装了自动上屏不可接受」的取向一致。
- **2026-09-28 修订**：`progress` 由 `true` 改 `false`（用户判定「时间进度」无行动价值，[13](13-runtime-kernel.md) D-20）；新增的 `todos` 取 `true`——它是折叠态中央槽位的默认内容，上屏是它的存在理由（同为 D-20）。因此本批 `defaultEnabled` 的实际判据收敛成一条：**占中央槽位者取 `true`（现为 `todos`），其余一律 `false`（含被替换下来的 `progress`）**。
- **2026-09-30 补充（批次 `p2-takeover`）**：**接管模块**的 `defaultEnabled` 映射为**各自上游键的默认值**——`timer` = `enableTimerFeature` 默认 `true`、`mirror` = `showMirror` 默认 `false`、`music` = `showStandardMediaControls` 默认 `true`。它只在「接管键读不到」时才被见到（启用门直接读上游键，见 [20](20-component-page.md) §接口与数据形状 2），填它的唯一作用是把「默认开启 / 关闭」如实写在 manifest 与卡片上。**上一段那条判据（占中央槽位者 `true`、其余 `false`）只适用于新增模块**，不覆盖接管模块。
- **2026-09-30 计数口径同步**：本条的「份数」不改变上面任何取值的正确性——**「11 份已落地」与「清单 19 份」是两件事**（`music` 是接管批次新增的模块 id、`frontapp` 是快捷指令与前台应用批次新增的模块 id、`calendar` 与 `stats` 是原清单里已有的行在 `p3-freeze` / `p3-widgets` 落地，见 §1 的 music / frontapp / calendar / stats 四行），要数「今天有几份 manifest 真在代码里」用开头那段实测命令，不要用本文任何写死的总数。
- **2026-09-30 落地补充（批次 `p2-shortcuts-frontapp`）**：本条判据在新增模块上的最新样本——`shortcuts` 与
  `frontapp` 都取 `defaultEnabled: false`（不占中央槽位，落上一段那条"占中央槽位者取 `true`、其余 `false`"
  的判据）、`kind "builtin"`、`icon.type "symbol"`（`bolt.square` / `app.badge`）、`version "1.0.0"`、
  `apiVersion HostInfo.currentAPIVersion`、`name`/`summary` 走 `module.<shortID>.*` 两个 key
  （`LocalizedText`）；两份 manifest 都过 `validate()`（用例断言）。
- **2026-09-30 落地补充（批次 `p3-widgets`）**：本条判据在**接管模块**上的新样本——`stats`
  （`com.cmeng.gourd.stats`）取 `surfaces [.home]`、`defaultPlacement: Placement(slot: nil, order: 50)`、
  `defaultEnabled` = 真源键 `enableStatsFeature` 的上游默认值（`false`）、`permissions: []`、
  `config` 四键（真源键 + 三个图表可见性登记键）、`kind "builtin"`、`icon.type "symbol"`
  （`chart.xyaxis.line`）、`version "1.0.0"`、`apiVersion HostInfo.currentAPIVersion`、
  `name`/`summary` 走 `module.stats.*` 两个 key（`LocalizedText`）；manifest 过 `validate()`（用例断言）。

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

`launcher`、`lunar`、`progress`、`todos`、`shortcuts`、`terminal`（09 §3.1 明示"本轮 6 项新增功能里有 5 项零私有 API"+ 2026-09-28 增补的 `todos` 同样零私有 API）+ **`frontapp`**（2026-09-30 新增：只用 `NSWorkspace` 的通知与 `NSRunningApplication`，零 TCC、零私有 API）+ 接管的 `lyrics`、`calendar`、`shelf`、`timer`、`clipboard`、`mirror`、`weather`。

> **`shortcuts` 的"零私有 API"要说清**：它确实零私有 API，但**不是零子进程**——取数与运行都起
> `/usr/bin/shortcuts`（系统自带的 CLI，09 §3.2 的子进程清单/15 号文档的台账口径），
> 本批因此多了一条"限时 + 禁并发"的子进程调用（设计 [22](22-shortcuts-and-frontapp.md)）。

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
