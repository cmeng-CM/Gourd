# Changelog

All notable changes to Gourd (a fork of Atoll) will be documented in this file; upstream history retained below.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-09-30

第一个冻结的自用版。本仓库是 [Atoll](https://github.com/Ebullioscopic/Atoll) 的**修改版本**
（基线 `v2.3.3-beta.3` / `c7305ec`，2026-08-20），此段以下列出的都是 Gourd（壶中天）分支
自 2026-09-27 起的**自有变更**，不出自上游；版本身份、归属与冻结口径见
[docs/24-release-freeze.md](docs/24-release-freeze.md)。

### 模块内核与组件页（docs/13 / 14 / 19 / 20）

- **模块内核**：`GourdModule` 协议（manifest / 生命周期 / 内容请求）与注册表落地，
  展开面板的 tab 列表与内容 switch 通过三处最小接线改为「从注册表读」——新增一个模块 =
  实现协议 + 组合根注册一行；启用真源是 manifest 的 `defaultEnabled` 加用户覆盖表。
- **三个接管模块**：计时器 / 镜子 / 音乐从上游写死的渲染点变成真模块（模块提供那个 tab 或首页块，
  **启用真源就是上游那个开关键本身**——在组件页与在上游设置页拨的是同一个开关）；
  首页块与模块块宽一一对应，接管后宿主侧不再保留内置块。
- **启动台**：新增 `com.cmeng.gourd.launcher` 展开 tab（应用网格 / 搜索 / 点一下启动并收起 /
  右键固定），扫描本机应用目录 + 按 Spotlight 使用数据排序，零权限、零私有 API。
- **组件页**：第二段给不改渲染归属的七个功能各一张上游开关卡（卡即那个 `Defaults` 键的镜像 +
  一行「开了会在哪看到什么」）；接管卡写出写路径与生效位置，跨模块顺序节按实现收敛。
- **日历展开 tab**（`p3-freeze`）：原本只有 `#Preview` 的独立月历（`StandaloneCalendarView`）接线成
  `com.cmeng.gourd.calendar` 模块的展开 tab——展开面板多一个「日历」入口（月历可翻月 + 当日清单），
  与首页日历行由**同一个 `showCalendar` 开关**控制。
- **组件页配置编辑口**（`p3-freeze`）：音乐 / 启动台 / 快捷指令 / 前台应用四个模块的**有效配置项**
  可以直接在组件页拨动并即时生效（按允许清单逐键渲染，只支持 boolean / integer / number / string 四种；
  接管模块登记的上游键不进清单，卡上以一行灰字标注「由上游设置管理」）。
- **关闭态的「日进度 pill」退回展开面板**（`p3-freeze`，缺陷修复）：`progress` 模块原本在关闭态中央槽位
  常驻一枚「尺度图标 + 百分比」（默认 `sun.max` + `53%`），**与亮度 HUD 同形**，容易被当成「收起态挂着一枚
  亮度 HUD」。该模块不再占折叠槽位（`surfaces` 只留 `expanded`），进度改在展开面板看；它与
  `inlineHUD` / `enableBrightnessHUD` 无关——那两条管的是亮度 HUD 自己的链。

### 首页条与 `＋N`（docs/21 / 23）

- **首页块顺序可调**：覆盖表 + 上下移（顺序的唯一权威源是宿主那一层，设置页展示用同一条算式）。
- **丢块提示 `＋N`**：首页条因宽度不够从尾部整块丢弃时，条尾给一个 `＋N` 小胶囊（悬停列出被丢掉的
  块名）——**丢块不再静默**。位置锚在尾部边缘，预留位只在「基线会丢块且预留后仍能显示 ≥1 块」时生效
  （`tailReserve` 缺省 0 = 不预留，此时布局与之前一字不差）。
- **名单同源 + 尺寸反馈修复**：`＋N` 列的块与真正没显示的块来自同一份输入；提案宽钉在 strip 的可用宽上，
  消除「视图那份 plan 显示 ＋2、Layout 那份只摆 1 块」的错位。

### 通知：× 到底关了什么（docs/09 §5.5 / docs/21 机制四）

- **四格语义写成两档文案**：列表行的 × 在「近 10 秒内有同指纹 AX 关闭句柄」时**同时真关掉系统通知**，
  否则只从岛上移除——两档文案按**同一个只读谓词**（`willAlsoCloseSystemBanner`）分档，
  与 `dismiss` 的判据同一份，文案与行为不会各说各话。
- **一键清除的语义收窄**：只清岛上这一屏，不逐条打 AX 动作真关。
- 通知这一块的其余能力（前几批落地的本单位工作，一并列在这里）：AX 实时通道 + 数据库降级通道
  （同指纹 10s 内去重、AX 优先）、浮层与列表两条关闭入口；关闭结果在日志里可查
  （`有句柄但执行失败` 与 `本来就没有句柄` 是两行不同的日志）。

### 快捷指令与前台应用（docs/22）

- **快捷指令模块**（默认关）：展开面板一个 tab——搜系统快捷指令、点一下跑、固定常用的；
  取数走 `/usr/bin/shortcuts list --show-identifiers` 并缓存进配置，运行时 `shortcuts run <identifier>`
  限时 30s、禁止并发。
- **前台应用模块**（默认关）：首页一块——当前前台应用的图标与名称 + 所有打开的常规 App 网格，
  点一格切过去；内容现取 `NSWorkspace.runningApplications`，零私有 API。

### 首页五条修正（docs/23，按实机反馈）

- 日历行不再画上下两条渐变遮罩（滚动提示只在独立日历里需要）。
- 面板高度不够时**先收日历行、保住首页条**（此前顺序相反）。
- 前台应用块从「最近切换历史」改成「所有打开的常规 App」（只列可激活的常规 App，点一下必须切过去）。
- 修最小宽度（770pt）下「块被分配了宽度却画不出来」的空白（实测复现：第二个之后的块空白、条尾 `＋2`）。
- 音乐封面可配置显示（模块 config 新增 `showAlbumArt`，默认显示）。

### 安装、改名与本次冻结

- 打包与安装产物改名为 **壶中天.app**（`tools/build.sh --install` / `--dmg`；构建产物仍叫 `Gourd.app`，
  `TEST_HOST` 依赖该路径），DMG 为 `dist/壶中天-<版本>.dmg`。
- 版本身份与继承来的上游版本号分家：`VERSION` / `MARKETING_VERSION` 由 `2.3.3` 改为 `0.1.0`
  （构建号 1196 → 1197），应用与 DMG 自报 0.1.0。
- 许可与归属补口（NOTICE 的修改日期与改名、TRADEMARKS 的无背书声明、自建文件的版权头）。

### 首页块与面板高度（p5-home-blocks，2026-09-30/10-01，docs/29）

- **首页待办块只讲今日**：表头「今日 + 已办/总量」+ 细进度条 + 今日清单（行数随块高），三环从首页撤销（代码保留可逆）。
- **进度块改「时间进度」**：自然日 / 周 / 月 / 季 / 年口径；默认三行（今天 / 本周 / 本月），组件卡新增
  「显示的尺度」多选（五档胶囊，勾选即写、即时生效）；简介只写出厂那三档。
- **音乐块降档**：`300/420 + .large` → `240/300 + .compact`，封面默认关（打开画 40pt 小封面）。
- **组件页重排**：撤销与「首页组件」重复的「功能」段；四个宿主元素（暂存器 / 终端 / 剪贴板 / 取色器）
  与模块行同节呈现，**面板上每个 tab 与图标都有开关**；锁屏天气归位锁屏页。
- **面板高度自适应**（默认档，`panelHeightMode = auto`）：展开面板贴内容取高（8pt 滞回），
  夹在 `[120, min(850, 0.9×屏高)]`；外观页新增「面板布局」组（自适应 / 手动 + **恢复默认**——
  只重置布局与显示键，不动账号、权限与内容）。

### 首页样式、架子与面板高度（p6-ui-polish，2026-10-01，docs/30）

- **首页每块「浮起」**：不做卡片底与边线，改常驻**柔光池**（无边界径向渐变白光）+ 内容辉光，hover 轻微放大 /
  提亮 / 加深；T8 引入的**整条带共用大底撤掉**（`HomeBandChrome.containerOpacity` 等删除），块与块之间因此可区分。
- **音乐块再缩宽**：`240/300 → 200/250`，紧凑档控制键 26 / 键距 6 / 封面 36（封面档装备宽 `196 ≤ 200` 不裁）。
- **架子**：统一命名「隔空投送与文件暂存」（tab 短名「投送暂存」，旧名「架子 / 暂存器 / 搁板」清零）；
  修好点 ✕ 删不掉文件的命中区 bug（拖拽视图 frame 收敛 + `hitRect` 纯函数同源，✕ 改为「悬停或选中」即显示）；
  版面改 Nook X 式——左侧投送块缩成一枚小投放格（点按弹供应商 popover，含「选择文件投送…」），文件区改全宽多行网格；
  架子页进入高度测量名单（贴内容，不再回落手动值）。
- **通知面板字号整体 +1~2pt**（档位表收进 `NotificationRowMetrics`）；首页通知块与 HUD 卡片不动。
- **面板高度切换平滑**：窗口动画（`NSAnimationContext` 0.25s）+ 每页高度缓存（切回量过的页一步到位）+
  切页首报免防抖 + 启动台就绪门（首开不再「先塌陷再长高」）。
- **日历取高**：首页日历行高由「最坏 6 周的固定 294」改为按当月实际周数 `36N + 52`；日历页拆掉几何高依赖、
  改自然高并进测量名单（不再回落 682）；首页 auto 档底部可见留白 89 → 28pt。
- **宿主 tab 排序**：架子 / 剪贴板 / 终端三个宿主 tab 并入 `panelOrder`，设置页「面板组件」节的模块行与宿主行
  合并为一份可 ↑↓ 的名单（默认序与改动前逐字一致）；取色器仍不参与排序。
- **空闲动画修复**：删掉上游插入的空体分支并上移优先级；开关打开而从未选样式时自动选第一条内置动画；
  内置动画改按名字在渲染期解析（修掉「换安装位置 / 卷卸载后动画空白」的存储绝对路径问题），设置页预览同修。
- **设置侧栏**：「组件」页从「集成」移入「媒体与显示」分组。
- **回归修复**：auto 高度下切换日历页（面板大幅缩小）不再被 hover 退出判据误判为「指针离开面板」而塌回关闭态。

### 首页静态区分、工作日统计与启动台快捷启动（p7-workday-launcher，2026-10-01，docs/31）

- **首页每块常驻柔光加深**：柔光池 0.06 → 0.13、内容辉光 0.08/5 → 0.10/6、池半径系数 0.45 → 0.50（不变量上限）、池渐变两停改三停；**不 hover 也能分清每个区域**，hover 档同步上调（仍不加卡片底与边线）。纯黑底实测：块间缝 0.00、块内 27.9/255（判据 ≤3 / ≥10）。
- **「时间进度」→「工作日统计」**：今天行 = 工作时长进度条 + 距上班 / 距下班 / 休息日 / 已下班；本周 / 本月 / 本季 / 今年行 = 已过工作日占比 + 「剩 N 天」；工作日判定内置 2026 国务院节假日与调休表（先查表后看星期，表外年份按星期退化）；上班 / 下班时间与工作日集合在组件卡可配置、拨动即时生效。
- **启动台分上下两区**：上区「快捷启动」= 固定项（顺序 = 固定先后；空时一枚虚线提示格），下区网格**不再含固定项**；拖上固定、拖下取消（拖拽载体 = 应用 id 纯文本，外来 / 未知一律丢弃），右键菜单保留为并行入口；固定项重启保持。

**以下为上游 Atoll 的历史变更，原样保留。**

## [Unreleased]

### Added
- Spotify "Like Song" media control: save or remove the current track from your Liked Songs directly from the notch, lock screen, and minimalist player, using the official Spotify Web API (OAuth 2.0 PKCE). Add the control to any media slot in settings. (#579)

- Show the current Claude subscription plan (e.g. `Max 5x`) as a badge next to the Claude card title in the LLM Usage view (#684).
- **AntiGravity Usage Tracking**: Track how much of Antigravity usage is left in the LLM Usage Monitor tab (both Gemini and Claude models)
- **Shelf item removal**: Hovering a Shelf item now reveals a × button that removes just that item, with a VoiceOver-accessible "Remove from Shelf" action that works without hovering (#461).
- **Draggable clipboard tab**: A `.notchTab` clipboard display mode shows clipboard history as a card grid inside the notch whose text, image, and single-file entries can be dragged straight out to Finder or other apps (drag = copy), with a hover × to delete a single item (#698).
- **Shelf marquee selection**: Dragging on empty space in the Shelf now draws a rubber-band rectangle that selects every item it touches, matching Finder. Holding Shift unions the marquee with the existing selection instead of replacing it (#682).
- **Shelf drag-out move toggle**: A new "Allow moving files when dragging out" setting (off by default) keeps drag-out copy-only. Offering a move operation previously let the receiving app relocate the original file out from under the user when the destination was on the same volume (#682).

- **Lyrics on the side**: Added ability to show lyrics of the current song when calendar is disabled (#741)

### Changed
- Improved the Dutch localization by adding missing translations, corrected terminology, and wording aligned with Apple's Dutch macOS conventions.
- Refreshing the LLM Usage card now skips session logs whose last write predates the seven-day window instead of re-reading the whole log history, and counts a repeated record when the copy inside the window would previously have been suppressed by a copy outside it (#691).
- The separate-tab clipboard now uses the same card grid (two columns) with drag-out and per-item delete, replacing the single-column list (#698).

### Fixed
- Fixed the LLM Usage card prompting for the login keychain password on every refresh when the Gemini language server is down. The app now tries the language server first (no keychain needed), and otherwise reads the Gemini CLI's token through the `security` CLI, which is covered by the item's `apple-tool:` partition grant and never triggers a password prompt.
- Fixed the timer being clipped behind the notch after the layout changes, and made the boxes in StatsView uniformly sized.
- Removed the separate floating timer control window; Pause/Stop buttons now render inline inside the notch, vertically centered with the timer countdown (#711).
- Fixed a launch crash (`BUG IN CLIENT OF LIBDISPATCH: trying to lock recursively`) that could trap while a Bluetooth audio device was connected. `BluetoothAudioManager`'s initialiser scanned connected devices synchronously, and that scan blocks on `Process.waitUntilExit()`, which spins the run loop — letting SwiftUI evaluate a view body that reads `BluetoothAudioManager.shared` and re-enter the initialiser that was still running. The scan now starts on the next main-queue turn instead.
- Fixed excessive memory usage by streaming LLM usage JSONL files instead of loading them entirely into memory
- Reduced idle CPU from always-on notch hover polling and OSDUIHelper process checks by backing off when the app is idle (#641).
- Rich-text clipboard entries now keep their formatting when dragged out of the notch. Rich content is captured as RTF at copy time — including web/HTML copies (browsers, GitHub) that expose only `public.html`, which is now converted to RTF — and the drag offers that styled RTF with a plain-text fallback. Rich-text editors (TextEdit, Pages, Word) receive the formatting; plain-text targets still get plain text. The exact result depends on what the destination app accepts (#717, closes #712).
- Fixed a hairline gap at the top of the notch during open animation, and hover-to-open flapping when the pointer sits on the top edge, on physical-notch Macs (#681).
- Fixed lock-screen widget readability on bright wallpapers by adding a Dark/Light appearance mode for widget text and controls.
- Fixed Codex Today and Week usage totals remaining at zero when parsing Codex session logs (#664).
- Recover the Claude quota display after Claude Code rotates its OAuth token, instead of showing "quota unavailable" until the app is restarted (#685).
- Fixed the Claude quota staying "quota unavailable" on recent Claude Code versions, which store the OAuth token under a per-install hash-suffixed Keychain item (`Claude Code-credentials-<hash>`) and no longer update the un-suffixed item the app read; the freshest matching item is now used (#699, follow-up to #685).
- Normalized Claude model IDs when pricing local usage so newer IDs are costed instead of showing `US$0.00+`, and show an explicit unavailable/partial estimate when a model isn't in the pricing table (#683, #664).
- Fixed an issue where `BluetoothHUDAnimations` (.mov files) were missing in release builds.
- Improved the GitHub Actions release workflow to use a monotonic build number allocator and automated patch versioning for stable releases.
- Fixed Cursor quota parsing and display to show the current Cursor Models and Other Models billing buckets with readable long reset durations.
- Fixed files dropped onto the Shelf silently disappearing on macOS 26 (Tahoe) by storing plain bookmarks instead of security-scoped ones, which a non-sandboxed app cannot create (#646).
- Fixed the AirPods pause gesture opening Siri instead of pausing Spotify: the real-time waveform no longer process-taps Spotify while a Bluetooth output route is active, and the tap is rebuilt whenever the output route changes.
- Fixed Noise Cancellation, Adaptive Audio, and Conversation Awareness labels being clipped behind the notch in the AirPods listening-mode HUD; every mode is now trailing-aligned and scales down instead of scrolling.
- Fix crash when Apple Notes sync encounters duplicate remote note IDs
- Stopped sending the track title and artist to LRCLIB on every track change while lyrics are switched off; the setting now gates the request, not just the placeholder text (#694).
- Fixed the Shelf freezing for seconds on every drop, and dragging items out delivering the file name as plain text instead of the file itself. Four call sites bridged to `@MainActor` members of `ShelfItem` with a `Task.detached` plus `DispatchSemaphore.wait`, which deadlocks by construction when called from the main actor and always burned its full 5-second timeout: the deduplication pass in `add()` paid that cost once per existing *and* incoming item, and `createPasteboardItem` timed out to a `nil` URL and fell through to writing plain text. Resolved paths are now cached on the item at drop time (and backfilled off the main actor for items persisted earlier), so deduplication, drag-out, and the context menu need no main-actor disk I/O (#682).
- Fixed Open, Open With, Show in Finder, Quick Look, Compress, Copy Path, and the image actions all missing from the Shelf file context menu, caused by `ShelfItem.fileURL` returning a hard-coded `nil` for files (#682).
- Fixed the notch auto-closing in the middle of a drag and cancelling the session: dragging an item out necessarily takes the cursor off the panel, which tore down the view acting as the drag source (#682).
- Fixed an issue where scrolling a long note inside the Dynamic Island returned the view to the home view instead of scrolling the note. (`#636`)
- Fixed Atoll being terminated by macOS when starting a voice recording in the Screen Assistant: the app now declares a microphone usage description, which it was missing entirely.
- Closed the extension RPC port to the local network. It was documented as listening on localhost but bound the wildcard address, so anything on the same Wi-Fi could reach port 9020 and drive the extension API — a client identifies itself simply by stating a bundle identifier. It now binds the loopback address of each family, and any connection from elsewhere is refused before it can send anything.
- Stopped the Bluetooth battery refresh from stalling the interface. It ran `system_profiler` and `pmset` on the main thread — about 200 ms each time — at launch and again on every connect, disconnect and refresh, four times in the first twenty seconds of a session here. Those two now run in the background, and the `system_profiler` reading is shared for 30 seconds instead of being taken separately for battery levels and for each device's model lookup, so a connect no longer spawns it twice. Battery levels are unchanged; on a cold start the percentage can arrive a moment after the device does, which the existing brief wait before showing the connection already covers.
- Fixed Notch expansion FPS stutter. Music and Timer managers now cache `NSHostingView` fitting sizes and reuse them for hover-only updates. When the panel size is unchanged, the window moves with `setFrameOrigin` instead of `setFrame`; `FlyoutFrameCalculator.swift` centralizes the flyout placement calculation (#741).
- Fixed Canvas desync during Notch transitions. Static artwork is rendered by SwiftUI, while Spotify Canvas uses an `AVPlayerLayer` hosted in an `NSViewRepresentable`. During close, the video layer implicitly animated its own frame in a separate Core Animation transaction, creating a second, slower slide-out that conflicted with SwiftUI’s transition (#741).

### Removed

## [2.3.2] - 2026-07-20

### Added

### Changed

### Fixed

### Removed

## [2.3.1] - 2026-07-20

### Added

### Changed

### Fixed

### Removed

## [2.3.0] - 2026-07-20

### Added
- **Lock Screen & Live Activities**: Full support for Lock Screen widgets, Live Activities, and expanding lock screen music players with flip animations.
- **Screen Assistant (AI)**: Introducing Screen Assistant with snipping capabilities and Gemini API integration.
- **Advanced System HUDs**: Dynamic polling HUDs for Volume (mute/unmute), Brightness, Bluetooth, and Privacy Access Indicators.
- **Clipboard Manager**: New floating clipboard manager panel with customizable settings and quick access.
- **System Stats Panel**: Real-time tracking of CPU usage, Memory, Disk Read/Write, and Network usage with circular progress graphs.
- **Custom Timer**: Dedicated Timer UI with custom timer capabilities.
- **Multi-channel Updates**: Switch seamlessly between Nightly, Alpha, Beta, and Stable update channels directly from Settings.
- **Automated CI/CD**: Full automated release pipeline via GitHub Actions using Sparkle.

### Changed
- **UI & Aesthetics**: Major overhaul to support a new Minimalistic UI option, as well as a Frutiger Aero aesthetic option.
- **Onboarding & Settings**: Revamped the onboarding experience and Settings window layout for a cleaner, native macOS feel.
- **Media Player**: Refined NowPlaying detection, expanded the Lock Screen music player, and smoothed out slider behavior.
- **Performance**: Disabled `OSDUIHelper` polling in favor of event-driven system HUD monitoring to drastically reduce CPU footprint.

### Fixed
- Fixed timeline reset and playback jumping issues in the Media Player.
- Fixed jittering animations on brightness and volume HUDs.
- Fixed corner radius clipping and window alignment bugs across multiple popup panels.
- Fixed double conversion network errors and memory usage spikes in the System Stats panel.
- Fixed lock screen GIF tracking via Git LFS.

### ❤️ Special Thanks to Our Contributors
A massive shoutout to everyone who contributed to this milestone release:
Hariharan Mudaliar, Jis G Jacob, Felipe Giacomini Cocco, delli, Federico Imberti, Dan Querido, Soham Sharma, 杨锟, DanFQ, Amir Zarrinkafsh, HerbJul, StellarSea, XiNian-dada, AkhilKonduru1, createthisnl, fatih ozdil, Santiago Quihui, Venkatesh, A-Akhil, Alex, JoelVR2k, Ninzorn, SSylvain1989, landuoduo, and dozens of others!

## [2.2.0] - 2026-05-30
### Added
- Initial release on the new update pipeline
