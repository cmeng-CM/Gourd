# 桌面歌词悬浮层（岛不展开时歌词显示在屏幕上）+ 实时波形采集白名单扩容

| 项 | 值 |
|---|---|
| 状态 | 已实现 |
| 最后更新 | 2026-10-10 |
| 关联来源 | 改判 docs/29 D-17 / D-57 的结论（面板内歌词）；承接 docs/00 ADR-0013 之后的决策编号 |
| 工作流 | `.workflow/p10-lyrics-overlay/` |

> **怎么读**：§背景与目标 / §明确不做 / §备选与取舍 是这场改动的判断依据；
> §接口与数据形状 是参考型小节（执行者与机器查考），人审可跳过；
> §已知限制 / §实际交付 是留给后来人的。

**读者分界**：§一句话方案 / §背景与目标 / §备选与取舍 / §明确不做 / §验收标准 / §决策摘要 给人读；§接口与数据形状 / §做法 是给执行者与模型的契约，边界按 **Always / Ask first / Never** 三档写在各条里。

## 一句话方案

歌词不再画在灵动岛面板里：新增一个 Gourd 自绘的**桌面歌词悬浮层**，只在**岛不展开**时出现在屏幕上（默认贴在岛下方，可拖拽并记住位置），配一套自定义显示档（字号 / 行数 / 透明度 / 颜色 / 高亮当前行 / 锁定位置）；面板内原有的三处歌词落点（侧歌词档、内嵌歌词行、极简播放器歌词行）一并退休。同时把实时波形（CoreAudio process tap）的采集白名单扩到含 lx-music、网易云、QQ音乐、酷狗。

## 背景与目标

**问题现状**（2026-10-10 逐条查证，结论见账本）：

1. **歌词在面板里已经无处可显**。面板内唯一的那条「艺人行下面的歌词行」判据是 `enableLyrics && showCalendar`，但它所在的 `MusicControlsView(density: .regular)` 只被侧歌词档渲染，而侧歌词档要求 `!showCalendar`——两个条件互斥，这行是死路（p5-home-blocks 把首页音乐块降成紧凑档时失去的，docs/29 D-17）。剩下的唯一面内落点是侧歌词档本身，它要求「日历行关」。于是设置页两个开关互相 `.disabled`：媒体页歌词开关被 `showCalendar` 挡住、日历页日历开关被 `enableLyrics` 挡住，**用户被锁死，两边都点不动**。
2. **用户的用法是「不占面板、直接在屏幕上看到歌词」**（桌面歌词的常见形态）——2026-10-10 原话：「歌词是否可以不显示在面板上，当灵动岛不展开的情况下，歌词直接显示在屏幕上……或者自定义一套歌词显示模式」，并在二选一里拍板**自绘悬浮层**。
3. **实时波形看不到效果**：tap 的白名单写死 11 个国外播放器（`AudioTap.targetBundleIDs`），用户在用 lx-music（`cn.toside.music.desktop`，已用 mediaremote 适配器实测当前 Now Playing 的 bundle id）——读数恒 0 → 柱子冻在 0.2 倍高（`RealTimeAudioSpectrum.updateBarsFromAudio` 的夹取），观感就是「可视化坏了」。

**预期结果**：用户播放带词条的曲目、岛保持不展开 → 屏幕上岛下方出现跟着播放逐行推进的歌词；展开岛 → 悬浮层消失；关掉总开关 → 不出现。实时波形在折叠态岛右侧的柱条随用户播放器的音频跳动。

**承接关系**：本次**改判** docs/29 的两条结论——D-17（紧凑档音乐块「艺人行 / 歌词行留给展开面板」：那句话预设展开面板仍有歌词落点，事实是它随侧歌词档一起被否掉）与 D-57（侧歌词档专用账本键 `sideLyricsHomeTab` + `showsSideLyricsHomeLayout` 一族：本次整条退休，含它的用例）。术语沿用既有名单：`MusicManager.syncedLyrics` / `currentLyricIndex` / `currentLyrics`、`LyricLine`、`enableLyrics`、`AudioTap`。

**关键约束**（用户 2026-10-10 第 3 条）：「**现在的首页布局不需要动**」——首页两条带 + 一行、音乐块的紧凑档形态、任何块的宽度/高度声明都不许因为本次改动变化（所以不采用「把歌词行加回首页音乐块」这条捷径）。

**为什么现在做**：用户点名「歌词、可视化这些都没有效果」，两处都卡在上述结构性原因上——不修就是三个开关（歌词 / 日历 / 实时波形）继续互相牵制且屏幕上什么也不出现。

## 做法

整体图景（一次播放里歌词怎么走到屏幕上）：

```
LRCLIB (lrclib.net)                      CoreAudio process tap
      │ ①既有链路，本次不动                    │ ③白名单 +4 个国内播放器
      ▼                                        ▼
MusicManager.syncedLyrics / currentLyricIndex   AudioTap.displayMagnitudes
      │ ②新读点（@Published，300ms 推进）        │ 既有读点
      ▼                                        ▼
LyricsOverlayWindowManager.sync()           折叠态岛右翼 / 锁屏面板（既有）
      │ ④按档渲染 + 按判据显隐
      ▼
屏幕上的一层无边框、非激活、置顶窗口（可拖拽、可锁定）
```

读法：①③ 是既有的两条数据链，本次只动 ③ 的名单；②④ 是新增的一层——歌词的**唯一**呈现出口从面板换到这里。

### 机制一 · 悬浮层（新增）

- **数据**：零新增抓取。只读 `MusicManager` 已有的 `syncedLyrics` / `currentLyricIndex`（`currentLyrics` 是既有链路的内部状态——占位串的载体，悬浮层不读它）；逐行同步由既有的 300ms `lyricSyncTask` 推进，缓存与 LRCLIB 拉取都不动。
- **窗口**：一个无边框、非激活（`styleMask: [.borderless, .nonactivatingPanel]`）、置顶（`CGShieldingWindowLevel()`）、`[.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]` 的 `NSPanel`——配方逐字沿用 `FlyoutWindowPresenter`（同一种窗口语义只留一份配方，但**不复用它的本体**：它的定位与动画是「贴着岛」的专用逻辑）。屏幕取岛所在屏（`DynamicIslandViewModel.screen` 的 localizedName 匹配，与 `FlyoutWindowPresenter.resolveScreen` 同口径）。
- **显隐**：判据提成一个纯函数（见 §接口与数据形状），五个输入之外没有隐含通道——其中 `hasRealLyrics = !syncedLyrics.isEmpty`（既有链路的两种占位态「Loading lyrics...」/「No lyrics found」都伴随 `syncedLyrics = []`，所以读 `syncedLyrics` 就够，不要去比占位串）；显隐由一条观察链（`MusicManager` 的 `syncedLyrics` / `currentLyricIndex` / `isPlaying` 三个 `@Published` + `vm.notchState` / `vm.screen` + 屏参变化通知 + 锁屏状态 + 总开关与 9 枚键，共 10 条 publisher）驱动，`sync()` 幂等。
- **渲染**：行数档 1 / 3 / 5；当前行取 `LyricsOverlayRules.highlightIndex(...)`（无时间轴时为 `nil`，即不高亮），`lineCount > 1` 时把当前行摆在**中间**（上下各露相邻行），越界处留空不补行；当前行按「高亮」档加粗提亮，颜色按档解析（跟封面取色 / 白 / 自定义）；整层套一档不透明度；行切换用短 `easeInOut` 淡入淡出。**无时间轴歌词**（LRCLIB 只有 `plainLyrics` 时既有链路产出 `[LyricLine(timestamp: 0, text: 整段)]`）按换行拆行、静态显示：不高亮、不滚动——不拆行会把整段歌词糊成一团。
- **位置与交互**：默认锚点 = 岛下方居中，用户拖拽写下相对锚点的偏移（两个 `Defaults` 值），窗口每次出现按锚点 + 偏移就位（屏参变化时重算锚点、保留偏移）。「锁定位置」档把 `ignoresMouseEvents` 置真（完全鼠标穿透，代价是不能拖）；未锁定时拖拽移动，并提供右键菜单三个动作（锁定 / 重置位置 / 关闭歌词）——不锁定时窗口会接到鼠标事件，这是拖拽的必然代价，记在 §已知限制。
- **隐私口径**：窗口建好后注册进 `ScreenCaptureVisibilityManager`（`scope: .entireInterface`）——该 manager 自己订阅「截屏 / 录屏时隐藏灵动岛」并逐窗刷 `sharingType = .none`，所以开关切换当场生效、本层不另写一份判断；歌词因此不漏进录制。

### 机制二 · 面板内歌词退休（改动既有行为）

三处落点整条删除，理由是「用户要的是屏幕上的歌词，面板里不再显示」：

| 落点 | 处置 |
|---|---|
| 侧歌词档（`showsSideLyricsHomeLayout` / `sideLyricsRequiredNotchWidth` / `NotchHomeView.sideLyricsContent` + `LyricsSidePanelView` / `SideLyricsLayout` / `PanelContentHeight.sideLyricsHomeTab` / `homePanelTabKey(showsSideLyricsLayout:)` 的分档 / `ContentView` 的 `.home` 分档与最小宽度项 / `DynamicIslandViewModel` 的三条 publisher） | 整条退休；首页在「歌词开 + 日历关」时不再变形，永远走标准两条带 + 一行 |
| `songInfoContent` 的内嵌歌词行（`enableLyrics && showCalendar`） | 删除（它已是死路，见 §背景与目标 1） |
| 极简播放器的歌词行（`MinimalisticMusicPlayerView` 的四处 `if enableLyrics` 渲染分支） | 删除（极简档也是岛面板）；**歌词按钮保留**，改为控制悬浮层总开关。注意它有**两个消费面**：`NotchHomeView` 的极简档与 `ExtensionLiveActivityViews` 的扩展实时活动兜底——后者的音乐格会跟着失去歌词行，由悬浮层接管 |
| 极简档的歌词加高（`matters.swift` 的 `minimalisticLyricsExtraHeight` = 40pt 与 `minimalisticOpenNotchSize` 的 `enableLyrics` 分支、`DynamicIslandViewModel` 里那条专为它重算尺寸的 observer） | 一并退休（D-17）：行删了高度留着就是「开歌词即一条 40pt 空带」 |
| 被动孤儿（因上面两条失去全部消费点的符号：`AlbumArtView`、`mirrorIsVisible` / `cameraPreview` / `webcamManager`、`MusicControlsView` 的 `.regular` 档、`NotchHomeView` 里两行 `lyricsPanelWidth/Offset` 的 `@Default`） | 逐符号 grep 确认零消费点后删除；仍有别处消费者的部分只删失去消费点的入口并在报告里写明 |

**两处设置耦合同时解除**：媒体页歌词开关不再被 `showCalendar` / `enableMinimalisticUI` / `showStandardMediaControls` 挡住（用户点得动）；日历页日历开关不再被 `enableLyrics` 挡住。这就是把「互相锁死」修掉的那一步。

**保留**（不在灵动岛面板上，与悬浮层不冲突）：锁屏媒体面板的歌词行、全屏作品窗口的歌词、`MusicSlotConfigurationView` 的 `.lyrics` 槽位按钮（点它 = 开关悬浮层，按钮激活配色仍读 `enableLyrics`）。

### 机制三 · 采集白名单唯一常量（改既有）

现在名单是**两份字面量副本**：`AudioTap.startCaptureSync` 一份、`DynamicIslandApp.setupAudioTapMusicObservers` 一份——任何一次「加一个播放器」都要改两处，漏一处就是「App 启停时重启采集」那条观察链不认这个播放器。本次把它提成**唯一常量** `AudioTapTargets.bundleIDs`，两处都读它，并加入四个 bundle id：`cn.toside.music.desktop`（lx-music）、`com.netease.163music`（网易云）、`com.tencent.QQMusicMac`（QQ音乐）、`com.kugou.mac.Music`（酷狗）。已有的 Safari 保留（浏览器播放同属「音乐来源」）。

## 备选与取舍

| # | 备选 | 否决理由 |
|---|---|---|
| 1 | 由 Gourd 去开关**播放器自带的桌面歌词**（AppleScript / AX） | 每个 App 要单独适配、对方改版即失效、还要额外的自动化权限；用户二选一里没选它（保留为将来可选叠加项） |
| 2 | 把歌词行加回首页音乐块（紧凑档） | 用户 2026-10-10 明确「现在的首页布局不需要动」 |
| 3 | 复用 `FlyoutWindowPresenter` 本体 | 它的定位与动画按「贴着岛」写死；歌词层要自由位置、拖拽与位置记忆——复用会把它拽成通用容器 |
| 4 | 歌词画在折叠态岛的翅膀里（像波形那样） | 折叠态翅膀宽度只有几十 pt，一行歌词也放不下；且会和波形 / 计时器等既有翅膀抢位置 |
| 5 | 白名单只加 lx-music | 用户拍板「四个国内播放器」——同一台机器上装的四个都覆盖，避免下次换播放器再来一轮 |
| 6 | 按用户给的第二个分支**删掉**实时波形配置 | 该分支的前提是「必须展开才显示」；实测它**不展开就显示**（折叠态岛右侧柱条 + 锁屏媒体面板）→ 前提不成立，配置保留并加白名单（D-13） |
| 7 | 歌词源换成别的（网易云 API / 自建曲库） | 引入新的外部依赖与合规面；LRCLIB 既有链路与缓存已够用（覆盖率限制记在 §已知限制） |

## 接口与数据形状

**新的 Defaults 键**（`DynamicIsland/models/Constants.swift`；旧键 `lyricsPanelWidth` / `lyricsPanelOffset` 删除）：

| 键 | 类型 | 默认 | 取值 |
|---|---|---|---|
| `enableLyrics` | Bool | false（沿用） | 语义改为「屏幕歌词总开关」 |
| `lyricsFontSize` | Double | 18 | 12…30，步长 1 |
| `lyricsLineCount` | Int | 3 | 1 / 3 / 5 |
| `lyricsOpacity` | Double | 0.9 | 0.3…1.0，步长 0.05 |
| `lyricsColorMode` | enum `LyricsColorMode` | `.albumArt` | `.albumArt` / `.white` / `.custom` |
| `lyricsCustomColorHex` | String | `"#FFFFFF"` | 6 位十六进制（`#` 可省；非法回落白。自定义档用；`Defaults` 不稳存 SwiftUI `Color`，用十六进制字符串） |
| `lyricsHighlightCurrent` | Bool | true | — |
| `lyricsOverlayLocked` | Bool | false | true = 鼠标穿透 |
| `lyricsOverlayOffsetX` / `lyricsOverlayOffsetY` | Double | 0 / 0 | 相对「岛下方居中」锚点的 pt 偏移；**AppKit 屏幕坐标位移**（向下拖 = Y 负），窗口 `origin = 锚点 + 偏移`（定位与拖拽同一坐标系，D-25） |

**纯函数（新文件，`DynamicIsland/components/Music/LyricsOverlayRules.swift`）**：

```swift
enum LyricsOverlayRules {
    /// 显隐的唯一判据（五个输入之外没有隐含通道）
    static func shouldShow(
        enableLyrics: Bool, hasActiveSession: Bool, hasRealLyrics: Bool,
        islandClosed: Bool, screenLocked: Bool
    ) -> Bool
    /// 无时间轴歌词按换行拆行——判据锚在既有链路的真实形状上：
    /// plain 落点 = syncedLyrics 里的一条 `LyricLine(timestamp: 0, text: 整段)`
    static func displayLines(synced: [LyricLine]) -> (lines: [(index: Int, text: String)], isSynced: Bool)
    /// D-08 的「plain 不高亮」由它承载：isSynced == false 或 currentIndex < 0 → nil
    static func highlightIndex(isSynced: Bool, currentIndex: Int) -> Int?
    /// 行窗口：以当前行居中，返回长度恒为 lineCount 的窗口；越界槽位为 nil（画空，不补行）
    /// currentIndex 用 lines[i].index 坐标（与 highlightIndex 同源）；找不到匹配行时按「当前行 = 第一行」
    /// **收 lines、回窗口行**（而非「输入下标 + total」）：坐标契约编进类型，index 有洞时消费方不会错位
    static func visibleWindow(lineCount: Int, currentIndex: Int,
                              lines: [(index: Int, text: String)]) -> [(index: Int, text: String)?]
    /// 颜色解析（跟封面时用 `ensureMinimumBrightness` 同款下限，保证深色封面上可读）
    static func resolvedColor(mode: LyricsColorMode, hex: String, albumArt: NSColor?) -> Color
}
```

**窗口 manager（新文件，`DynamicIsland/managers/LyricsOverlayWindowManager.swift`）**：

```swift
final class LyricsOverlayWindowManager: ObservableObject {
    static let shared: LyricsOverlayWindowManager
    /// 启动路径注入应用主 VM（岛状态与所在屏）——与 `LockScreenManager.configure(viewModel:)` 同口径。
    /// **先注入、再 `start()`**；注入即 `sync()` 一次。vm 未注入时 `sync()` 按「不显示」处理
    /// （判据取不到就不显示），不崩（D-33）
    func configure(viewModel: DynamicIslandViewModel)
    /// 启动一次：装观察链（只装一次）并跑一次 sync()——窗口由 `sync()` 在判据成立时建，总开关关着时反而走退役
    func start()
    /// 幂等：按判据决定显示 / 隐藏，按锚点 + 偏移布局；观察链变化时调用
    /// （拖拽进行中只跳过重排、不跳过显隐——D-26）
    func sync()
    /// 拖拽落点写入偏移（两个 Defaults 键）
    func commitOffset(_ offset: CGSize)
    func resetOffset()
    /// 拖拽进行中 / 结束（视图 `DragGesture` 的回调）：拖拽期窗口位置由 `dragChanged` 直接驱动；
    /// `dragEnded` 按「先落旗 → 写盘 → 补一次完整 `sync()`」归位（D-28）
    func dragChanged(_ translation: CGSize)
    func dragEnded(_ translation: CGSize)
}
```

**锚点**：岛所在屏（`vm.screen` 的 localizedName 匹配，回落 `NSScreen.main`）的 `frame.midX` 居中、岛底边（`frame.maxY − vm.effectiveClosedNotchHeight`）下方 **8pt**（`LyricsOverlayWindowManager.anchorSpacing`），再叠加 `lyricsOverlayOffsetX/Y`（AppKit 坐标位移；D-25）。

**视图（新文件，`DynamicIsland/components/Music/LyricsOverlayView.swift`）**：渲染 + 右键菜单（`Lock position` / `Reset position` / `Turn Off Lyrics`，zh-Hans 条目由 T4 补）+ 拖拽回调。**入参（全部显式、视图不读单例）**：`lines: [(index: Int, text: String)]`、`isSynced: Bool`、`highlightIndex: Int?`、`emphasizeCurrent: Bool`、`fontSize: CGFloat`、`lineCount: Int`、`opacity: Double`、`colorMode: LyricsColorMode`、`customHex: String`、`albumArtColor: NSColor?`、`locked: Bool`、`onToggleLock` / `onResetPosition` / `onCloseLyrics` / `onDragChanged` / `onDragEnded`。
两条实现级契约（D-20 / D-21）：**`highlightIndex` 同时是行窗口的居中锚**——高亮档关掉只把 `emphasizeCurrent` 置假（字重与明暗恢复一致），**锚点仍跟当前行**（折成 `highlightIndex = nil` 会让窗口冻在第一行，1 行档时恒显示第 1 句）；**「高亮当前行」落成「其余行相对压暗」**（当前行满不透明度、其余行同色 ×0.72，`dimmedAlpha`）——三档颜色同一条式子成立（白档无法更亮）。窗口尺寸由 `NSHostingView.fittingSize` 定：宽 = 最长行固有宽（封顶 860pt `maximumWidth`），高 = `lineCount × round(fontSize × 1.4)`（D-23）。

**白名单常量**：`AudioTapTargets.bundleIDs: [String]`（放 `AudioTap.swift` 顶部，**现 16 项** = 11 项原序 + 四个国内播放器 + lx-music 的 `.helper`（D-34，追加末尾）；两处消费：`AudioTap.startCaptureSync` 与 `DynamicIslandApp.setupAudioTapMusicObservers`）。

**退休符号**（删除，清单即契约）：`SideLyricsLayout`、`showsSideLyricsHomeLayout`、`sideLyricsRequiredNotchWidth`（含 `openNotchSize` 与 `ContentView.currentOpenNotchResizeBounds()` 两处 `minWidth` 里的调用）、`PanelContentHeight.sideLyricsHomeTab`、`homePanelTabKey(showsSideLyricsLayout:)` 的侧歌词分档、`NotchHomeView.sideLyricsContent` / `LyricsSidePanelView` / `shouldShowSideLyrics` / `MusicPlayerView`、`songInfoContent` 的内嵌歌词行、`MinimalisticMusicPlayerView` 的四处歌词渲染分支、`minimalisticLyricsExtraHeight` 与其两处消费（D-17）、`lyricsPanelWidth` / `lyricsPanelOffset`（键定义 + 两处 `@Default` + 两条 publisher + 两条滑杆）、`PanelAutoHeightTests.testSideLyricsHomeLayoutDoesNotResolveToTheHomeLedgerKey`。

## 明确不做

1. **首页布局一个字不动**（用户第 3 条）：两条带 + 一行的结构、音乐块紧凑档形态、各块宽度/高度声明、`HomeBandedHomeView` / `HomeVerticalFit` / `HomeBlockChrome` 全部零改动。
2. **不做逐字（卡拉OK）高亮**：只高亮当前行。
3. **不做多屏同时显示**：单实例，跟随岛所在屏；副屏不画第二份。
4. **不换歌词源**、不新增网络请求：仍 LRCLIB 单源。
5. **不动锁屏媒体面板的歌词行、不动全屏作品窗口的歌词**：它们不在灵动岛面板上。
6. **不动死代码** `MinimalisticMusicView.swift`（整个 struct 从未被实例化）：本次不清理，避免混入无关改动。
7. **不动 Spotify 的蓝牙/AVRCP 跳过逻辑**（`AudioTap` 里蓝牙路由跳过 Spotify 那一段）：与小白名单无关。
8. **不做字体族 / 描边 / 背景板自定义**：字号之外的外观留待后续。
9. **不做「按 App 单独开关歌词」**：总开关一个（用户选的实现路线不依赖具体 App）。
10. **不动进度块「本周」/ 统计 / 日历**（上一轮 p9 的边界继续有效）。

## 实际交付

**交付物**（提交链 `git log --oneline a88cdd6a..`：T1…T8 + 终审修复波）：

| 类 | 交付物 |
|---|---|
| 新文件 | `DynamicIsland/components/Music/LyricsOverlayRules.swift`（五个纯函数）、`DynamicIsland/components/Music/LyricsOverlayView.swift`（渲染 / 右键菜单 / 拖拽回调）、`DynamicIsland/managers/LyricsOverlayWindowManager.swift`（窗口 / 锚点 / 显隐 / 拖拽） |
| 新键与迁移 | 9 枚显示档键（字号 / 行数 / 透明度 / 颜色模式 / 自定义色 / 高亮 / 锁定 / 偏移 X / 偏移 Y）+ `LyricsColorMode` 枚举；`enableLyrics` 沿用、语义改「屏幕歌词总开关」；旧键 `lyricsPanelWidth` / `lyricsPanelOffset` 全链删除（键定义 + 两处 `@Default` + 两条 publisher + 两条滑杆） |
| 新接口 | `LyricsOverlayRules` 五个静态函数（签名见 §接口与数据形状）；`LyricsOverlayWindowManager.shared.configure(viewModel:) / start() / sync() / commitOffset(_:) / resetOffset() / dragChanged(_:) / dragEnded(_:)`；`AudioTapTargets.bundleIDs`（唯一常量，16 项，含 lx-music 的 `.helper`） |
| 接线 | `DynamicIslandApp.applicationDidFinishLaunching` 一处（`configure(viewModel:)` + `start()`，`!AppRuntimeEnvironment.isUITesting` 门控）；设置页媒体页新节「Lyrics on screen」+ 两处开关 disable 耦合解除；zh-Hans 补 12 条 |
| 面板内歌词退休 | 侧歌词档一族（`SideLyricsLayout` / `showsSideLyricsHomeLayout` / `sideLyricsRequiredNotchWidth` / `sideLyricsHomeTab` / `LyricsSidePanelView` / `MusicPlayerView` / `NotchHomeView.sideLyricsContent` 等）、`songInfoContent` 的内嵌歌词行、极简播放器四处 `if enableLyrics` 渲染分支与 `minimalisticLyricsExtraHeight`；被动孤儿同批清理（`AlbumArtView`、`NotchHomeView` 的 `webcamManager` / `mirrorIsVisible` / `cameraPreview` 与四条零读者 `@Default`、`MusicControlsView` 的 `.regular` 档）；终审修复波再清三处残留（`NotchHomeView.batteryModel`、`TypingLyricView`、`HomeStripView` 注释里的侧歌词字样） |
| 测试 | `HomeStripLayoutTests` 新增纯函数 / 渲染取证用例；`TakeoverEnablementTests` 新增白名单用例（含 `.helper` 一条）；`PanelAutoHeightTests` 随退休删侧歌词项 |
| 文档 | 本文件、`docs/00` ADR-0018、`docs/09` 机制条目、`docs/guide/` 三份（settings / faq / README）、`docs/29` / `docs/13` / `docs/26` 改判留痕（只增行）；`docs/33` 记签名身份口径（工作流侧） |

**与计划的偏离**（逐条给因由；细节与候选决策在各任务报告 `.workflow/p10-lyrics-overlay/reports/*.md`）：

1. **清单外改了 `MusicModule.swift`**：两处 `MusicControlsView(density: .compact)` → `MusicControlsView()`（`density` / `Density` 折叠为唯一档的必然连锁）与四处失真历史注释订正（D-31）。
2. **删了两处零消费缺省**：`MediaOutputPickerButton.scale` / `AirPlayPickerButton.scale` 的 `.medium` 缺省 → 必传（唯一消费方 `.regular` 档已退休；D-32）。
3. **尺寸重算链保留而非整链删**：`updateSideLyricsNotchSizeIfNeeded()` 与驱动它的 `MergeMany` 保留 8 个仍有效成员、只摘 `enableLyrics`（两枚旧键随键定义同批删；逐成员给出「哪一行读它」的代码证据；D-30）。
4. **终审修复波**：A1 悬浮层 VM 改启动路径注入（Critical：原 `AppDelegate.shared?.vm` 恒 nil → 判据永假、层永不出现；D-33）；A2 白名单补 lx-music 的 `.helper`（原按主进程匹配被静默跳过；D-34）；A3 清三处残留孤儿。
5. **实现级欠定 / 候选决策**（均已记账）：视图增 `emphasizeCurrent` 入参（D-20）、`enableLyrics=false` 整窗退役（D-22）、`visibleWindow` 收 `lines` 回窗口行（D-19）、hex 接受省略 `#`（D-18）、接线带 `isUITesting` 门控 + 右键菜单英文 literal（D-24，zh-Hans 由 T4 补齐）、设置页新节独立 Section（D-27）、`LyricsColorMode` 声明在 `Constants.swift` 末尾（文件作用域里离 9 枚键最近的落点）。

**遗留**（终审备注与各任务报告）：

1. **上屏取证五张未产出**：T3 的 `overlay-visible` / `overlay-hidden-expanded` / `overlay-dragged` / `overlay-1line` / `overlay-5lines` 被 A1 修的缺陷阻断（判据恒假 → 层不出现），**需在修复后的构建上重拍**（判读要点：岛下方居中、展开即消失、拖拽偏移落盘、1/5 行档）；T4/T5 六张因合成输入打不开设置面板标「人工」。现有旁证：22 张 `render-*.png`（渲染骨架）与 `audiotap-targets.log` / `audioapps-probe.log`（白名单）。
2. **白名单换播放器可能要再补**：`.helper` 按实测逐个列入（D-34）；网易云 / QQ音乐 / 酷狗的采集未逐个上屏取证（计划「不验证的部分」已声明接受）。
3. **死代码未清**：`MinimalisticMusicView.swift`（整个 struct 从未实例化）按 §明确不做 6 不动；`MusicModule.swift` 的历史引用注释保留（T6 已订正失真句）。
4. **回归基线**：全量单测 548 条 0 失败（`.workflow/p10-lyrics-overlay/evidence/fixwave-full-test-run.log`；p10 开工前基线 519 条）。

## 已知限制

- **歌词源单点**：LRCLIB 对冷门曲目（尤其华语独立/翻唱）常常查不到——`农夫渔夫 / 大乔小乔` 实测返回 `[]`。查不到时**静默不显示**（不显示 "No lyrics found" 常驻文案）。
  **2026-10-16 追加（[docs/50](50-music-lyrics-lookup-and-open-player.md)）**：取词侧改了两条口径——歌手的别名 / 团体后缀 / 多歌手 / 歌名的版本标注会走候选查询阶梯（词库里有词条的能捞回来了），LRCLIB 自己的瞬时故障（503）**不再**被当成「这首歌没有歌词」缓存下来（20s 后自动再试一次；点歌词键也会立刻再问一次）。词库**确实没有**的曲目仍然静默不显示。
- **只在拿到真实歌词行后出现**：加载中不显示占位（避免闪烁）；因此「看起来没反应」的第一嫌疑仍是词条缺失。
- **拖出屏幕找不回来**（2026-10-16 修，[docs/50](50-music-lyrics-lookup-and-open-player.md) D-16）：位置 = 锚点 + 偏移键，偏移是自由值，拖过头 / 屏幕布局变化都可能把整层送到屏外（实测 `(+247,+143)` → 窗口 `y=−170`，屏顶 `−35`），此时**鼠标抓不到它**、只能去设置页「重置位置」。现在显示前会**夹回屏内**（至少留 40pt 可见）。
- **未锁定档会接到鼠标事件**（拖拽的代价）：歌词条覆盖的屏幕区域点不到底下的内容；要完全穿透就锁定位。默认未锁定并给右键菜单，属于可发现性取舍。
- **单实例、跟随岛所在屏**：`showOnAllDisplays` 打开时，副屏不显示歌词层。
- **全屏 app 上前景可见**（有意，不跟 `hideOnClosed`）：桌面歌词的常见用法；代价是在全屏视频/演示上会盖住画面顶部一小条。
- **锁屏时不显示**：锁屏有媒体面板自己的那一行（解锁后悬浮层接管）。
- **plain（无时间轴）歌词**只是静态多行，不随播放推进。
- **不改 App 内其它歌词入口的语义**：锁屏面板与全屏作品窗口照旧（同一枚 `enableLyrics` 同时门控它们，关总开关会一起关）。
- **锁定档下右键菜单打不开**：锁定 = 整窗 `ignoresMouseEvents`（穿透），所以「Unlock position」那一项在锁定档不可达——解锁的正式入口是设置页的「Lock position」开关（T4）；菜单里保留该项纯属防御性。
- **拖拽期间不做重排**：拖拽中任何一次 `sync()`（如播放中每 ~300ms 的行切换）都会与拖拽抢窗口位置，故重排被挂起、拖拽结束再按新偏移归位一次（D-26）；拖拽中歌词行照常推进（只窗口不动）。**连带**：挂起的是「测量 + 锚点 + `setFrame`」整段，所以拖拽中窗口**尺寸**也不跟随行窗口（切到长行时按旧宽截尾，松手即恢复）——瞬时观感，与 D-26 自洽。
- **白名单按 bundle id 精确匹配（进程粒度）**：Electron 类播放器出声的可能不是名单里的主进程，而是其 `.helper` 子进程（bundle id 形如 `<main>.helper`）——lx-music 已按实测补上 `cn.toside.music.desktop.helper`（D-34）；换播放器可能还要按同一方式再补一项。
- **实时波形只修到「进 tap」为止**：白名单补上 lx-music 的 `.helper` 后，tap 能建立（`CATap flowing`、target 含 helper 的 AudioObjectID），但频带读数仍全零、折叠态柱条两帧逐像素相同（2026-10-10 上屏取证，`visualizer-lx-music.png` 为阴性证据）——**「柱条随音频跳动」本轮未达成**，疑点在 tap 的 mixdown 口径或 helper 的 CoreAudio 归属，留作下一轮定位（本次改动的交付边界是白名单本身）。
- **悬浮层的 view model 由启动路径注入**：不再走 `AppDelegate.shared`——本 App 里那条路径**恒为 nil**（`ContentView.swift:1191` 的实测注释；2026-10-10 上屏取证再证 `vmNil=true appDelegateNil=true`），不注入则 `islandClosed` 判据取不到值、层不显示（D-33）。

## 验收标准

1. **屏幕歌词**：播放带词条的曲目、岛不展开 → 屏上（岛下方）出现歌词，随播放逐行推进（当前行高亮）；**展开岛 → 悬浮层消失**；收起岛 → 重新出现。
2. **总开关**：关掉媒体页的歌词开关 → 悬浮层不再出现；同时媒体页「Show calendar」与日历页「Show calendar」两处开关都**点得动**（互相 disable 死锁解除）。
3. **面板内无歌词**：日历行关 + 歌词开时，首页仍是标准两条带 + 一行（不再变成侧歌词档）；`grep` 级：`showsSideLyricsHomeLayout` / `sideLyricsHomeTab` / `LyricsSidePanelView` 全仓零命中。
4. **显示档当场生效**：改字号 / 行数 / 透明度 / 颜色模式 / 高亮档 → 悬浮层立即（≤1 次重绘）跟随。
5. **位置**：拖拽移动 → 位置变更；重启 App 后位置保持；「重置位置」回到岛下方居中；锁定档下鼠标可穿透（点击落在下层窗口）。
6. **录屏口径**：「截屏/录屏时隐藏灵动岛」开着时，悬浮层不出现在截屏里。
7. **实时波形**：用 lx-music 播放 → 折叠态岛右侧柱条随音频跳动（上屏取证）；网易云 / QQ音乐 / 酷狗同为白名单成员（名单常量断言）。
8. **回归**：全量单测 0 失败；首页布局与改动前逐字（p7/p7d 的上屏读数不受影响）。

## 决策摘要

| ID | 决策 | 来源 | 理由 |
|----|------|------|------|
| D-01 | 歌词落点从面板改为**屏幕悬浮层**（自绘），岛不展开时显示 | 用户 | 2026-10-10 原话「歌词是否可以不显示在面板上，当灵动岛不展开的情况下，歌词直接显示在屏幕上……或者自定义一套歌词显示模式」；二选一拍板「Gourd 自绘悬浮歌词」 |
| D-02 | 数据源沿用既有 LRCLIB 链路（悬浮层只读 `syncedLyrics` / `currentLyricIndex`；`currentLyrics` 是既有链路的内部状态——占位串载体，悬浮层不读它），零新增抓取与缓存 | agent | 逐行同步（300ms）与缓存已存在；换源会引入新外部依赖与合规面（备选 7） |
| D-03 | 面板内三处歌词落点全部退休（侧歌词档一族、内嵌歌词行、极简播放器歌词行） | 用户 | 「不显示在面板上」是用户拍的范围；内嵌行在 docs/29 D-17 之后本就不可达 |
| D-04 | 保留锁屏媒体面板的歌词行与全屏作品窗口的歌词 | 用户 | 二者不在灵动岛面板上；锁屏与解锁互斥，与悬浮层不重叠 |
| D-05 | `enableLyrics` 键名沿用、语义改为「屏幕歌词总开关」；解除媒体页/日历页两处互相 disable 的耦合 | 用户 | 复用同一枚键避免两套开关；那个死锁是本次要修的毛病之一（用户 2026-10-10 抱怨的直接来源） |
| D-06 | 悬浮层窗口配方沿用 `FlyoutWindowPresenter` 的常量组，但**另写** manager | agent | 同一种窗口语义只留一份配方；FlyoutWindowPresenter 的定位/动画是「贴着岛」专用逻辑（备选 3） |
| D-07 | 显示判据 = 总开关 && 有活跃音乐会话 && 拿到真实歌词行 && 岛不展开 && 屏幕未锁；**不跟 `hideOnClosed`** | 用户 | 「Loading / No lyrics found」不常驻（避免闪烁与噪声）；锁屏归锁屏面板；全屏仍显示是桌面歌词的常见用法（记入 §已知限制） |
| D-08 | 无时间轴歌词按换行拆行、静态显示（不高亮、不滚动） | 用户 | LRCLIB 只有 plainLyrics 时既有链路产出单条整段文本，不拆行会糊成一团（2026-10-10 计划门逐条请用户确认，答复「可以」） |
| D-09 | 显示档 = 字号 / 行数(1·3·5) / 透明度 / 颜色模式(跟封面·白·自定义) / 高亮当前行 / 锁定位置 + 重置位置；默认 18pt / 3 行 / 0.9 / 跟封面 / 高亮开 / 未锁定 | 用户 | 用户给的维度原样落地；默认值取「贴在岛下方、不抢眼」（2026-10-10 计划门逐条请用户确认，答复「可以」） |
| D-10 | 位置 = 岛所在屏、默认岛下方居中；拖拽写偏移、可锁定（锁定档 `ignoresMouseEvents = true`） | 用户 | 用户选项文案已含「位置可拖拽记忆」；穿透是锁定档的附带语义 |
| D-11 | 截屏/录屏时与岛同口径隐藏（`sharingType = .none`） | 用户 | 与既有隐私口径一致，别让歌词漏进录制（2026-10-10 计划门逐条请用户确认，答复「可以」） |
| D-12 | 白名单提取为**唯一常量** `AudioTapTargets.bundleIDs`，并加入 lx-music / 网易云 / QQ音乐 / 酷狗四个 bundle id | 用户 | 用户「如果不展开可以显示就增加白名单」+ 拍板「四个国内播放器」；提取常量是防两处名单漂移（现状两份字面量副本） |
| D-13 | 实时波形配置**保留**（不删） | 用户 | 该分支前提「必须展开才显示」不成立——它不展开就显示（折叠态右翼 + 锁屏面板） |
| D-14 | 新增 ADR-0018，记录「歌词落点从面板移到屏幕」并作废 docs/29 D-57 的侧歌词档结论 | agent | 推翻既有结论必须留痕（文档会变：改判就地留痕） |
| D-15 | 悬浮层单实例、跟随岛所在屏；副屏不画第二份 | 用户 | 多实例要处理每屏锚点/拖拽状态与 `showOnAllDisplays` 的交互，收益低（备选 4 之外的范围控制） |
| D-16 | 不做逐字高亮、不做字体族/描边/背景板自定义、不做按 App 单独开关 | 用户 | 用户给的档位里没有这些；先把「能看、能调、能挪」做对（§明确不做 2/8/9；2026-10-10 方案门呈现的「明确不做」点名，用户答复「可以」） |
| D-18 | 自定义颜色档的十六进制**接受省略 `#`**（仍要求 6 位十六进制、非法回落白） | agent | 用户可见的自由输入：`FF0000` 写成不带 `#` 不该变成白（独立审查 T2-Minor 2 引出；代价：比本表原先写的 `#RRGGBB` 宽一档，已在表里改齐） |
| D-19 | `visibleWindow` 收 `lines`、回窗口行（去掉 `total`）——把「index 与 currentIndex 同坐标」编进类型 | agent | 独立审查 T2-Important 1：`displayLines` 丢空行时保留下标洞，消费方按位置取值会错位，而原签名（`[Int?]` + `total`）在类型上无约束（代价：签名多一个参数、`total` 概念消失，由 `lines` 隐式承担） |
| D-20 | 视图增 `emphasizeCurrent`：`highlightIndex` 兼作**行窗口居中锚**，高亮档只影响字重/明暗 | agent | T3 实现发现文档欠定：把 `lyricsHighlightCurrent=false` 折成 `highlightIndex = nil` 会让 `visibleWindow` 的 `currentIndex` 退回 `?? 0`，行窗口**永远停在第一行**（「关高亮」连带冻住滚动） |
| D-21 | 「高亮当前行」落成「**其余行相对压暗**」（当前行满不透明度、其余行 ×0.72） | agent | 三档颜色（跟封面 / 白 / 自定义）同一条式子成立；白档「更亮」已无空间，压暗是唯一一致的表达（观测上仍是「当前行最醒目」） |
| D-22 | 总开关 `enableLyrics` 关掉时**整窗退役**（`unregister` + 断内容视图 + 丢窗口），其余「暂不该显示」的情形只 `orderOut` 留窗 | agent | 给 `ScreenCaptureVisibilityManager.unregister` 一个收敛触发点，且不留一件 `CGShieldingWindowLevel` 的隐形窗口；代价 = 重开总开关要重建窗口（一次 `NSPanel` + `register`） |
| D-23 | 窗口尺寸取 `NSHostingView.fittingSize`（宽封顶 860pt；高 = `lineCount × round(fontSize × 1.4)`） | agent | 与 `FlyoutWindowPresenter` 同一测量口径；代价 = 歌词行宽变化时窗口宽度跟随（居中锚不变）、超长行截尾（刻意） |
| D-24 | 接线带 `if !AppRuntimeEnvironment.isUITesting`；右键菜单三项用英文 literal（zh-Hans 由 T4 补） | agent | 与相邻的 `ModuleHUDWindowHost.shared.start()` 逐字同口径（全局层不进 UI 测试界面栈）；本仓既有菜单同为英文 literal |
| D-25 | `lyricsOverlayOffsetX/Y` 存**AppKit 屏幕坐标位移**（向下拖 = Y 负），窗口 `origin = 锚点 + 偏移` | agent | 窗口定位与拖拽提交在同一坐标系里闭合成环：拖动落点与 `sync()` 重排结果逐位相同、不回跳（T3 报告第 7 条候选决策；代价 = 两枚键的符号语义要写清） |
| D-26 | 拖拽进行中 `sync()` 只跳过**重排**、不跳过显隐；拖拽结束补一次完整 `sync()` | agent | 独立审查 T3-Minor 4：播放中行切换触发的 sync 会把窗口拉回「锚点 + 已存偏移」，机制上必然抖动（上屏未证实——锁屏阻断）；显隐不能跳过，否则拖拽中该藏的窗口藏不掉 |
| D-27 | 媒体页新节做成**独立 Section**（header「Lyrics on screen」+ 一条 footer 说明「岛下方可拖拽悬浮层、展开岛即隐藏」），位置夹在「Media playback live activity」与「Music Visualizer」之间；同批清掉三行因旧块消失而成孤儿的 `@Default`（媒体页 `enableLyrics` / `showCalendar`、日历页 `enableLyrics`）；zh-Hans 除新节文案外一并补 T3 菜单的三条 + `Unlock position`，`Album art` 译作「跟随封面」 | agent | 旧块原嵌在「Media playback live activity」节内，就地替换会拆散该节的无关行；footer 是三条灰字提示的替代信息面（页脚文字，不算控件，不违反 D-16）；孤儿声明与 T5/T6 的被动孤儿同性质（独立审查复核零读者） |
| D-28 | 拖拽旗标 `isDragging` 的复位点（`dragEnded` + `hideIfNeeded` + `tearDownWindow`）与「先落旗 → 写盘 → 补一次完整 `sync()`」次序 | agent | 旗标一旦悬挂（拖拽被隐藏打断、或写盘触发的 sync 在旗标落下前跑），此后每次 `sync()` 都跳过重排、窗口永不归位；三个复位点覆盖「正常结束 / 拖拽中被隐藏 / 整窗退役」，次序保证写盘触发的那次 sync 是完整重排 |
| D-29 | 拖拽中被隐藏（岛展开 / 锁屏 / 无词条）后恢复按「锚点 + 已存偏移」归位、不保留悬挂拖拽态 | agent | 隐藏路径（`hideIfNeeded`）同时复位拖拽态：恢复显示时按已落盘的偏移重排，等价于「这次拖拽作废」——比把半途位移另存一份更简单，且与 D-22 / D-26 的语义一致 |
| D-30 | 尺寸重算链 `updateSideLyricsNotchSizeIfNeeded()` 保留 8 个仍有效成员、只摘 `enableLyrics`（两枚旧键随键定义同批删）；函数名不改，以注释钉住理由 | agent | 逐成员查证：8 个成员变化仍会改变 `calculateDynamicNotchSize()` 的输出（`enabledStandardTabCount()` 与首页块存在性判据两条路径）；唯一零效果成员是 `enableLyrics`。改名不在派发范围，用注释把「函数名是旧档遗留」钉在代码旁 |
| D-31 | `MusicControlsView` 折叠为唯一档（删 `Density` / `density`），`MusicModule.swift` 两处调用点改名 + 四处失真注释订正（清单外连锁） | agent | 参数只剩一个取值时，枚举 / 属性本身就是新的零消费者声明；紧凑值逐字未变（`CompactMetrics` 常量 + `.small` 键档），只改调用形状 |
| D-32 | 零消费缺省的清理口径：`MediaOutputPickerButton` / `AirPlayPickerButton.scale` 删 `.medium` 缺省成必传 | agent | 该缺省的唯一消费方是已退休的 `.regular` 档，现存两处调用点都显式传 `.small`；删缺省只改 API 形状，行为与数值零变化 |
| D-33 | 悬浮层的 view model 走启动路径注入（`configure(viewModel:)`，与 `LockScreenManager` 同口径） | agent | **终审 Critical 的修复**：`AppDelegate.shared` 在本 App 恒 nil（`ContentView.swift:1191` 实测注释 + 2026-10-10 上屏取证双证），原取值路径让 `islandClosed` 恒 false、层永不建窗；注入后 `sync()` 立刻跑一次，vm 未注入时按「不显示」处理 |
| D-34 | 白名单按**进程粒度**精确匹配：Electron 类播放器要把出声的 `.helper` 子进程也列入（`cn.toside.music.desktop.helper`，追加末尾） | agent | 上屏取证实测：lx-music 主进程在 CoreAudio 里没有进程对象（`getAudioObjectID` 返回 nil 被静默跳过），出声的是 `.helper`；名单只增不删（16 项），换播放器按同一方式再补 |
| D-17 | 极简档的歌词加高（`minimalisticLyricsExtraHeight` = 40pt 与其 observer）随极简歌词行一起退休 | 用户 | 那段高度只服务极简档那一行歌词；行删了高度留着就是「开歌词即一条 40pt 空带」（独立审查 F4 发现；2026-10-10 计划门逐条请用户确认，答复「可以」） |
