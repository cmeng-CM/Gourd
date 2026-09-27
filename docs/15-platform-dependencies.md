# 平台依赖台账与 ATS 对外域名清单

这份文档回答一件事：**壶中天落到 macOS 之上的那些"非公开契约"分别是什么、失效时怎么办、收窄网络面要动哪些域名。** 它是 [12-p1-batches.md](12-p1-batches.md) §P1-0 的两条前置清障（私有 API 台账 + ATS 域名清单）的产物，收录口径见 [13-runtime-kernel.md](13-runtime-kernel.md) D-14。

三节的来源与用途：

| 节 | 来源 | 用途 |
|---|---|---|
| §1 私有 API 台账 | [09-features-and-mechanisms.md](09-features-and-mechanisms.md) §3.1 的 11 项 | 每项必须**有失效降级路径**（09 §3.1 的要求；[01-architecture.md](01-architecture.md) §9 的"私有 API 诱惑"升级为台账 + 降级实现） |
| §2 外部子进程清单 | 09 §3.2 全部条目 + 新增 `/usr/bin/shortcuts` | 登记限时 / 节流 / 失效影响 / 降级路径 |
| §3 ATS 对外域名清单 | 09 §8.2（"维持现状，但建一份清单为收窄留依据"）+ D-14 的收录口径 | 收窄 `NSAllowsArbitraryLoads` 时的逐条依据 |

---

## 1. 私有 API 台账（11 项）

行数、条目名与 09 §3.1 的 11 项一一对应；「加载方式」列附实测 `file:line`。

| 私有目标 | 用途 | 加载方式（file:line） | 失效影响 | 降级路径 | 所属模块 |
|---|---|---|---|---|---|
| `MediaRemote.framework` | 媒体控制与元数据（`MRMediaRemoteSendCommand` / `SetElapsedTime` / `SetShuffleMode` / `SetRepeatMode`） | `CFBundleCreate` 指向 `/System/Library/PrivateFrameworks/MediaRemote.framework` + `CFBundleGetFunctionPointerForName`（`MediaControllers/NowPlayingController.swift:60`、`MediaControllers/AmazonMusicController.swift:64-73`） | **旗舰功能失效**（媒体控制与正在播放） | 退到 vendored `MediaRemoteAdapter.framework` 一路（下表第 2 条，上游本就双路）；两路都失效 → 媒体区返回 `ModuleContent.unavailable`，歌词 / 进度等只读模块不受影响，系统媒体键仍可用 | `nowplaying` |
| `MediaRemoteAdapter.framework`（vendored） | 媒体元数据主路（曲名 / 艺术家 / 封面 / 进度，`--micros` 精度） | perl 子进程执行 bundle 内 `mediaremote-adapter.pl`（`MediaControllers/NowPlayingController.swift:152-164`、`helpers/MediaChecker.swift:34-45`；二进制在 `Frameworks/`，见 [03-license-matrix.md](03-license-matrix.md)） | 同上 | 退到上表第 1 条 dlopen 直调；仍失效 → 显式启用上游保留的其余播放器适配器（AppleScript 等，09 §2 A 的"默认不启用"），或媒体区 `unavailable` | `nowplaying` |
| `CoreBrightness.framework` | 亮度（内建屏）、键盘背光 | `Bundle(path:)` + 反射内部类名（`helpers/CoreBrightnessDisplayClient.swift:49-66`；键盘背光见 `managers/KeyboardBrightnessSensor.swift:163-167`） | 亮度控制、键盘背光失效 | 亮度退到 `DisplayServices`（下表第 4 条）→ 再退公开的 `IODisplaySetFloatParameter`；键盘背光退 IORegistry 只读；全不可用时滑杆置灰并提示使用系统亮度键 | `controls` |
| `DisplayServices.framework` | 亮度回退路径 | `dlopen` + `dlsym`（`helpers/DisplayServicesDynamic.swift:34`；调用见 `managers/SystemMediaControllers.swift:710-711`） | 回退路径失效 | 走公开的 `IODisplaySetFloatParameter`；再失效 → 亮度控件置灰，提示使用系统键盘亮度键 | `controls` |
| `IOReport.framework` | CPU 频率 | `dlopen` + `dlsym`（`utils/IOReportBridging.swift:31`；调用见 `utils/CPUSensorCollector.swift:43-165`） | 该指标失效（CPU 频率） | 隐藏频率行；CPU 温度仍由 AppleSMC 读（`utils/SMC.swift:171-185` 的 `IOServiceOpen`）、负载仍由 `getloadavg` / `host_processor_info` 读（09 §2 B 的其余机制不受影响） | `stats` |
| CGS 私有 C 函数（09 §3.1 记 7，本处实测 10） | 专用 Space、窗口层级 | `@_silgen_name`（`private/CGSSpace.swift:72-86` 8 个符号行；消费方 `managers/NotchSpaceManager.swift:25-32`；另 `managers/ScreenRecordingManager.swift:29-32` 的 `CGSIsScreenWatcherPresent` / `CGSRegisterNotifyProc` 2 个） | 窗口定位异常 | 不建专用 Space，窗口退回公开 `NSWindow.level` + 常规 Space；录屏检测的 CGS 通知失效 → 退到 `CGEventTap` + `killall screencapture` 既有路径；仍异常 → 相关窗口不显示（刘海主功能不受影响） | 内核窗口层（`managers/NotchSpaceManager.swift`，非模块）；视觉面见 09 §2 H |
| SkyLight 私有 API | 锁屏窗口代理 | SPM 依赖 `SkyLightWindow`（`DynamicIslandApp.swift:25`、`managers/LockScreenTimerWidgetManager.swift:24/245`、`managers/FullScreenArtworkWindowManager.swift:1237/1300/1396`） | 锁屏面板失效 | 锁屏面板维持上游现状（09 §0 原则 P4、D-12）；失效即锁屏相关面板不显示，刘海与展开面板不受影响，无需代码级降级 | 未模块化（锁屏面，维持现状） |
| `com.apple.mobiletimerd` | 系统 Clock 计时器镜像 | 私有 plist（`managers/SystemTimerBridge.swift:74-76`）+ `log stream`（同文件 `:279`）+ AX 读 UI | 该功能失效 | 该功能按 09 §2 C 已定「不投入」；失效不影响本地 `timer` 模块（自建 `Timer` + UserNotifications 到点通知） | 未模块化（不投入）；本地计时归 `timer` |
| DoNotDisturb DB | Focus 状态只读 | 直读 JSON（`managers/DoNotDisturbManager.swift:46`、`:323`、`:1413`；权限自检同路径见 `helpers/FullDiskAccessPermissionStore.swift:28`） | 只读失效（Focus 状态不可知） | 退到 `log stream` 监听（`managers/DoNotDisturbManager.swift:549`、`:1133`）；两路都失效 → 隐藏 Focus 指示器，不显示错误态 | `controls`（Focus 只读属系统控制面） |
| 11 个 `com.apple.Bluetooth.*` 私有通知 | 蓝牙设备状态（电量 / 连接 / 聆听模式） | `DistributedNotificationCenter`（`managers/BluetoothAudioManager.swift:111-125`；该数组共 15 个通知名，其中 bluetooth 前缀家族 11 个） | 蓝牙电量失效 | 退到 `system_profiler` + `pmset` + `ioreg` 三子进程轮询（见 §2 第 5～7 条）；三路都失效 → 隐藏蓝牙电量项（该功能按 09 §0 原则 P5 属不投入） | 未模块化（蓝牙耳机管理，不投入） |
| 通知中心数据库（新增） | 通知上岛 | 只读 SQLite（`~/Library/Group Containers/group.com.apple.usernoted/db2/db`，`SQLITE_OPEN_READONLY`）；**尚未落地**，机制见 09 §5.5；需完全磁盘访问 | **通知上岛失效**（09 §3.1 标注） | 退到 Accessibility 读通知中心 UI（`AXPress` 点击真实通知；上游已有 AX 基建与权限流程，09 §5.5 的降级方案）；探针不通过则按 09 §6 P2c 推迟或不做 | `notifications` |

---

## 2. 外部子进程清单

09 §3.2 的全部条目 + 新增 `/usr/bin/shortcuts`。09 §3.2 列名但**当前源码零命中**的条目（`lsof`、`networksetup`）一并登记并标注实测结果，避免这份台账被读成"源码里全都有"。

| 子进程 | 用途 | 调用点（file:line） | 限制 / 频率 | 失效影响 | 降级路径 |
|---|---|---|---|---|---|
| `perl`（`/usr/bin/perl`） | 媒体元数据（执行 `mediaremote-adapter.pl`） | `MediaControllers/NowPlayingController.swift:164`、`MediaControllers/AmazonMusicController.swift:162`、`helpers/MediaChecker.swift:53` | 按需起停（上游模式）；09 §3.2 记为"Apple 已不推荐" | 媒体元数据与封面失效 | 退到 `MediaRemote.framework` dlopen 直调（§1 第 1 条）；两路都失效 → 媒体区 `unavailable` |
| `launchctl`（`/bin/launchctl`） | OSD 抑制、HUD 调试、壁纸 / 录屏进程控制 | `managers/SystemOSDManager.swift:122/151/274`、`helpers/SystemHUDDebugger.swift:67/79` | 低频（状态切换时） | 原生 OSD 抑制失效（系统 OSD 与自绘 HUD 重叠） | 关闭自绘 OSD（`enableCustomOSD` 置 false），回落系统 OSD |
| `killall`（`/usr/bin/killall`） | 暂停 / 恢复系统进程（OSDUIHelper、WallpaperAgent、screencapture） | `managers/SystemOSDManager.swift:108/199/446/459`、`managers/FullScreenArtworkWindowManager.swift:502/1750` | 低频；`-STOP` 属 09 §3.2 记的"赌它不会坏" | 抑制 / 停止功能失效 | 不做暂停动作，功能降级为"不抑制"（不阻塞其余功能） |
| `log`（`/usr/bin/log`，`log stream`） | Focus 状态、系统计时器、蓝牙聆听模式、日志导出 | `managers/DoNotDisturbManager.swift:549/1133`、`managers/SystemTimerBridge.swift:279`、`managers/BluetoothAudioManager.swift:2196`、`DynamicIslandApp.swift:1215` | Focus / 计时器为**常驻流**（09 §3.2 记为持续 CPU 开销） | 对应状态源不可知 | Focus → 直读 JSON（§1 第 9 条）；系统计时器镜像本就"不投入"；蓝牙 → 三子进程轮询；日志导出 → 手动收集导出 |
| `system_profiler`（`/usr/sbin/system_profiler`） | 蓝牙设备信息（含电量详情） | `managers/BluetoothAudioManager.swift:1589` | 节流：`pmsetRefreshCooldown` 5s（同文件 `:76/931`） | 蓝牙详情缺失 | `pmset` / `ioreg` 两路补（本节第 6、7 条） |
| `pmset`（`/usr/bin/pmset`） | 蓝牙设备电量 | `managers/BluetoothAudioManager.swift:1466` | 同上节流 | 电量缺失 | `system_profiler` / IOKit 电源源兜底 |
| `ioreg`（`/usr/sbin/ioreg`） | 蓝牙设备 VendorID / ProductID | `managers/BluetoothAudioManager.swift:2113` | 低频 | 设备识别缺失 | `system_profiler` 兜底 |
| `screencapture`（`/usr/sbin/screencapture`） | 截图（AI 助手取屏） | `components/ScreenAssistant/ScreenshotSnippingTool.swift:102` | 用户触发 | 截图失效 | 提示屏幕录制授权；或用系统截图快捷键后拖入 |
| `security`（`/usr/bin/security`） | 读 Keychain 项（Antigravity 额度） | `managers/LLMUsage/AntigravityUsageProvider.swift:78` | 低频 | 该项额度读不到 | 隐藏该 provider 的额度面板（其余 provider 不受影响） |
| `zip`（`/usr/bin/zip`） | 日志导出、暂存架打包 | `DynamicIslandApp.swift:1239`、`components/Shelf/Services/TemporaryFileStorageService.swift:159` | 用户触发 | 导出失败 | 提示改用 Finder 压缩（源文件已落在临时目录） |
| `arp`（`/usr/sbin/arp`） | LocalSend 邻居 IP 探测 | `components/Shelf/Services/LocalSendService.swift:390` | 传输前一次 | 邻居探测缺失 | 退到 `NWMulticastGroup` 组播发现（同文件 `:94`），本条为补充路径 |
| `ps`（`/bin/ps`） | 进程列表、进程识别 | `managers/StatsManager.swift:1456`、`managers/LLMUsage/AntigravityUsageProvider.swift:200` | 进程列表独立节流 2s（09 §2 B） | 进程列表缺失 | 退到 `proc_pidinfo`（09 §2 B 的进程列表主路） |
| `pgrep`（`/usr/bin/pgrep`） | 系统进程存活探测（OSDUIHelper 等） | `managers/SystemOSDManager.swift:423/473` | 已做防抖（同文件 `:357-358` 注释记"否则 8 小时睡眠内约 19.2 万次 spawn"） | 探测失效 | 退到 `killall` 的返回码判定 |
| `corebrightnessdiag`（`/usr/libexec/corebrightnessdiag`） | 键盘背光 / 显示诊断数据 | `managers/KeyboardBrightnessSensor.swift:113`、`managers/SystemDisplayManager.swift:63` | 低频 | 背光传感器数据缺失 | IORegistry 只读（09 §2 E 的第三条路） |
| `zsh`（`/bin/zsh`，键 `terminalShellPath`） | 岛内终端 shell | `models/Constants.swift:1152`（默认值）；`managers/TerminalManager.swift:288-291` 起 shell 进程 | 用户开启终端时 | 岛内终端不可用 | 终端外部化：`mode = external` 唤起 Ghostty（09 §5.6，默认形态），岛内终端代码保留但不作为目标形态 |
| `/usr/bin/shortcuts`（**新增**） | 快捷指令枚举（`shortcuts list --show-identifiers`）与运行（`shortcuts run <identifier>`） | 尚未落地；机制见 09 §5.4 | **限时 30s + 禁止并发**（09 §3.2 / §5.4） | 枚举 / 执行失效 | 枚举结果回落配置缓存（09 §5.4「结果缓存进配置 + 手动刷新」）；运行失败在面板内提示原因 |
| `lsof`、`networksetup`（09 §3.2 列名） | — | **当前源码零命中**：`grep -rn 'lsof\|networksetup'`（`*.swift` / `*.sh` / `*.pl` / `*.rb`）无结果，本文档写作时实测 | — | 无（未使用） | 若将来引入，按本节既有模式登记（限时 + 节流 + 降级路径），不得裸起子进程 |

---

## 3. ATS 对外域名清单

### 3.1 收录口径与实测命令

口径（D-14）：**清单 = 字面量命令结果 ∪ 源码内插值域名**。三条命令按下述实测口径使用（① 已覆盖当前源码全部出站 host，②③ 为保险与无 scheme 宿主名的兜底）。

```sh
# ① 字面量：以引号开头的 http(s) URL（命令结果里含 GPL 版权头的 www.gnu.org 与 plist DTD 的 www.apple.com，均非网络请求）
grep -rn '"https\?://' --include='*.swift' DynamicIsland/

# ② 放宽到「不要求前置引号」的同一并集（补 Markdown 链接 ](https://…) 等形态，并完整取出被转义的正则 host）
grep -rno 'https\?://[A-Za-z0-9._%(){}\\-]*[A-Za-z0-9._%}\\-]' --include='*.swift' DynamicIsland/ | sort -u

# ③ 无 scheme 的宿主名（黑名单 / 会议链接识别规则等，非出站请求；③ 的 TLD 白名单会漏 .us/.gg/.si 这类，逐条人工补）
grep -rno '[a-z0-9-]\+\.[a-z0-9.-]*\.\(com\|net\|org\|sh\|io\|dev\|in\)' --include='*.swift' DynamicIsland/ | sort -u
```

**口径更正（实测）**：命令 ① **已能取到"host 字面 + 尾部插值"的 URL** —— `MusicManager.swift:1525` 的 `lrclib.net`、`AnimatedArtworkManager.swift:187` 的 `mvod.itunes.apple.com`（正则 host）、`UpdateChannel.swift:57` 的 `raw.githubusercontent.com` 都在 ① 的结果里（`"https://` 前紧邻的就是引号，插值在 URL 尾部）。① 真正会漏的是两类：

1. **host 本身由插值拼出**（例如 `"https://\(host)/path"` 形态）——**当前源码 0 处**；
2. **URL 前不是引号**的形态 —— 实测 ② 相对 ① 的增量只有 `betterdisplay.pro`、`lunar.fyi`（设置页 Markdown 链接 `](https://…)`）与正则字面量里被转义的 `mvod\.itunes\.apple\.com` 完整形态。

因此并集规则（D-14）保留为**保险**：① 已覆盖当前源码的全部出站 host，② / ③ 用来兜住上述两类与无 scheme 的宿主名。

### 3.2 出站请求域名（App 自身发起）

| 域名 | 用途 | file:line | 是否可关闭 / 关闭方式 |
|---|---|---|---|
| `lrclib.net` | 逐行歌词主源（`/api/search`） | `managers/MusicManager.swift:1525` | 可关：歌词功能开关 `enableLyrics`（默认 false） |
| `itunes.apple.com` | iTunes Search 补曲目元数据 / 封面 | `managers/MusicManager.swift:136`、`MediaControllers/AppleMusicController.swift:183` | 可关：停用媒体模块即不再发起（只在元数据 / 封面缺失时补，非主路） |
| `api.open-meteo.com` | 天气（免 key 主源） | `managers/LockScreenWeatherManager.swift:712` | 可关：关闭天气组件，或把 `lockScreenWeatherProviderSource` 切到 `wttr` |
| `air-quality-api.open-meteo.com` | 空气质量 | `managers/LockScreenWeatherManager.swift:798` | 可关：`lockScreenWeatherShowsAQI` 置 false |
| `wttr.in` | 天气备用源 | `managers/LockScreenWeatherManager.swift:626` | 可关：`lockScreenWeatherProviderSource` 切回 `openMeteo` |
| `api.music.apple.com` | Apple Music 动态封面（catalog `editorialVideo`） | `managers/AnimatedArtworkManager.swift:159` | 可关：关闭动态封面（`AnimatedArtworkManager` 的启用开关） |
| `mvod.itunes.apple.com` | 动态封面 HLS 视频流（正则匹配 m3u8） | `managers/AnimatedArtworkManager.swift:187` | 可关：同上 |
| `api.spotify.com` | Spotify 曲目 / 曲库 API | `MediaControllers/SpotifyController.swift:431`、`managers/Spotify/SpotifyLibraryAPI.swift:27` | 可关：不用 Spotify 适配器（09 §2 A：其余 6 个适配器默认不启用） |
| `open.spotify.com` | embed 页取曲目 / Canvas、token、登录页 | `MediaControllers/SpotifyController.swift:475`、`managers/MusicManager.swift:292`、`managers/SpotifyAuthManager.swift:37/155`、`components/Settings/SpotifyLoginSheet.swift:26`、`components/Settings/SpotifyAuthSettingsSection.swift:92/98` | 可关：同上 |
| `accounts.spotify.com` | Spotify OAuth 授权与换 token | `managers/Spotify/SpotifyOAuthService.swift:39/40`、`components/Settings/SpotifyLoginSheet.swift:25/36` | 可关：同上（用户不登录即不发起） |
| `spclient.wg.spotify.com` | Spotify Canvas 缓存接口 | `MediaControllers/SpotifyController.swift:576` | 可关：同上 |
| `raw.githubusercontent.com` | ① Sparkle appcast 占位 feed；② Spotify secret 字典 | `models/UpdateChannel.swift:57`；`managers/SpotifyAuthManager.swift:36` | 可关：feed 现状已被 `services/AtollUpdaterDelegate.swift:28-29` 返回 `nil` 关闭；secret 字典随 Spotify 适配器停用而消失 |
| `generativelanguage.googleapis.com` | AI 对话（Gemini） | `managers/ScreenAssistantManager.swift:418` | 可关：`enableScreenAssistant`（D-08 首启写 false） |
| `api.openai.com` | AI 对话（OpenAI） | `managers/ScreenAssistantManager.swift:441` | 可关：同上 |
| `api.groq.com` | AI 对话（Groq） | `managers/ScreenAssistantManager.swift:470` | 可关：同上 |
| `api.anthropic.com` | AI 对话（Claude）、Claude 额度 | `managers/ScreenAssistantManager.swift:498`、`managers/LLMUsage/Quota/ClaudeQuotaClient.swift:95` | 可关：对话同上；额度面板关 `enableLLMUsageFeature` |
| `platform.claude.com` | Claude 额度 OAuth 换 token | `managers/LLMUsage/Quota/ClaudeQuotaClient.swift:148` | 可关：同上 |
| `chatgpt.com` | Codex 额度 | `managers/LLMUsage/Quota/CodexQuotaClient.swift:39` | 可关：同上 |
| `cursor.com`、`api2.cursor.sh` | Cursor 额度 | `managers/LLMUsage/Quota/CursorQuotaClient.swift:41`、`:31` | 可关：同上 |
| `cloudcode-pa.googleapis.com`、`daily-cloudcode-pa.googleapis.com` | Antigravity 额度 | `managers/LLMUsage/AntigravityUsageProvider.swift:413`、`:412` | 可关：同上 |
| `assets9.lottiefiles.com` | 空闲动画远程 JSON（自带示例） | `components/Music/LottieAnimationView.swift:29`、`components/Settings/AnimationEditorView.swift:634` | 可关：删除 / 替换该动画条目；远程 URL 由用户导入（`components/Settings/IdleAnimationsSettingsSection.swift:471` 的输入框） |

**口径说明（「是否可关闭 / 关闭方式」列）**：开关名 / 键名均为**源码实测存在**（可按同行 `file:line` 复核定义），但**默认值未逐条核对**——本列只回答"能不能关、怎么关"，不承诺当前默认状态；实施关闭动作前按 `DynamicIsland/models/Constants.swift` 的定义行复核（只有 `enableLyrics` 默认 false、`lockScreenWeatherShowsAQI` 默认 true 等少数几条在本批次抽查过）。

### 3.3 非 HTTPS 的请求端点

（ATS 收窄时必须单独处理，见 §3.6）

| 端点 | 用途 | file:line | 是否可关闭 / 关闭方式 |
|---|---|---|---|
| `http://localhost:11434` | 本地模型端点（Ollama 兼容） | `models/Constants.swift:1213`（键 `localModelEndpoint`） | 可关：不启用本地 provider；键值可改 |
| `http://localhost:26538` | YouTube Music 本地桥 | `MediaControllers/YouTube Music Controller/YouTubeMusicModels.swift:33` | 可关：不用 YouTube Music 适配器（默认不启用） |
| `localhost:23803`（TCP，非 HTTP） | Lunar 外接屏亮度桥 | `managers/LunarManager.swift:158-160` | 可关：不安装 / 不联动 Lunar（09 §2 E 的外接屏亮度两条路之一） |
| 局域网（组播 `224.0.0.167` + 同网段主机 HTTP） | LocalSend 设备发现与传输 | `components/Shelf/Services/LocalSendService.swift:60/94/627` | 可关：不使用局域网互传；需 `NSLocalNetworkUsageDescription`（09 §7 必办项） |
| 入站监听（非出站）：扩展 RPC WebSocket 9020、XF 监听口 | 第三方扩展通道 / 本地回环 | `services/Extensions/ExtensionRPCServer.swift:43/100-115` | 可关：关闭第三方扩展（`enableThirdPartyExtensions`） |

### 3.4 动态域名来源（运行时才确定，无法用字面量穷举）

收窄 ATS 时这几处要按运行时白名单处理，不能只靠本清单的字面量：

| 来源 | 说明 | file:line |
|---|---|---|
| 媒体封面 / 动画资源 URL | 由媒体源给出（Apple Music 的 artwork 走 `mzstatic.com` 一类 CDN），App 只负责下载 | `managers/ImageService.swift:62`（`fetchImageData(from:)`）、`managers/FullScreenArtworkWindowManager.swift:1080`（`downloadRemoteVideo(from:)`） |
| 扩展 WebView 内容 | 上游已实现域名白名单；我们只读取已声明字段（06 §9.1） | `components/Extensions/ExtensionLockScreenWidgetView.swift:239-282` |
| 用户自定义远程资源 | 空闲动画远程 JSON、本地模型端点 | `components/Settings/IdleAnimationsSettingsSection.swift:471`、`models/Constants.swift:1213` |

### 3.5 源码出现但不发起出站请求的域名

| 域名 | 出现位置 | 为什么不产生请求 |
|---|---|---|
| `github.com`（含 `github.com/cmeng-CM/gourd`、`/th-ch/youtube-music`、`/Paxsenix0/Spotify-Canvas-API`、`/waydabber/BetterDisplay`、`/migueldeicaza/SwiftTerm`、`/ZephyrCodesStuff/rtaudio`） | `strings/constants.swift:21`、`models/UpdateChannel.swift:57`、`components/Onboarding/WelcomeView.swift:79`、`components/Onboarding/OnboardingFinishView.swift:65`、`components/Settings/SettingsView.swift:2823`、`components/Settings/SpotifyAuthSettingsSection.swift:99`、`components/Onboarding/MusicControllerSelectionView.swift:112`、`managers/BetterDisplayManager.swift`、`managers/TerminalManager.swift:4` | 文档 / 设置页链接：由默认浏览器打开（`NSWorkspace.open` 或 `Link`），App 自身不请求；`TerminalManager.swift:4` 是许可注释 |
| `developer.spotify.com`、`aistudio.google.com`、`www.linkedin.com` | `components/Settings/SpotifyLikeButtonSettingsSection.swift:73`、`components/Settings/SettingsView.swift:7800`、`components/Onboarding/ProOnboarding.swift:61` | 同上（跳转链接） |
| `betterdisplay.pro`、`lunar.fyi` | `components/Settings/SettingsView.swift:2287`、`components/Settings/SettingsView.swift:2295` | 设置页集成提示里的 Markdown 链接（外部屏亮度联动），点击才由浏览器请求 |
| `accounts.google.com`、`accounts.youtube.com` | `components/Settings/SpotifyLoginSheet.swift:35` | OAuth 登录**黑名单**（`blockedOAuthHostSuffixes`），不请求 |
| `www.spotify.com` | `components/Settings/SpotifyLoginSheet.swift:219` | WebView 登录完成判定的 host 分支（与 `open.spotify.com` 并列），判定本身不请求 |
| `zoom.us`、`teams.microsoft.com`、`meet.google.com`、`webex.com`、`gotomeeting.com`、`bluejeans.com`、`whereby.com`、`meet.jit.si`、`discord.gg`、`discord.com`、`facetime.apple.com` | `Providers/CalendarServiceProviding.swift:320-336`（`isConferenceURL` 的 `conferenceHosts` 全表）、`components/Calendar/DynamicIslandCalendar.swift:1349-1360`（同族的 `hostIdentifiers` 映射） | 日历会议链接**识别规则**与图标映射；这些 host 不进入任何请求，点击后交系统打开 |
| `apple.com` | `components/Shelf/Services/QuickShareService.swift:67` | AirDrop 分享的占位 URL，不请求 |
| `example.com` | `components/Settings/IdleAnimationsSettingsSection.swift:471` | 输入框 placeholder 文案 |
| `www.apple.com`（`/DTDs/PropertyList-1.0.dtd`） | `components/Shelf/Services/TemporaryFileStorageService.swift:250` | 生成 plist 的 DOCTYPE 声明，不请求 |
| `www.gnu.org` | 全仓库 GPL 版权头（`grep` 命中最多的一项；`DynamicIsland/strings/constants.swift:16` 是其中一处，其余同名头同款） | 许可注释，不请求 |

**两处口径修正**（收录时发现，逐条记录以免清单被当成"覆盖了全部规划项"）：

- `music.163.com`：09 §2 A 把 NetEase 记为歌词备用源，但**源码零命中**（`grep -rn '163\.com\|netease' --include='*.swift' DynamicIsland/` 无结果）——当前实现只有 LRCLIB 一路。将来补备用源时，同步在 `lyrics` 的 `permissions` 声明 `network:music.163.com`（06 §7.1）。
- `open-meteo` SPM 包：09 §7 记为"声明了但未链接、零 import"的死依赖（P0 删除项），不是域名问题，此处仅留档。

### 3.6 `NSAllowsArbitraryLoads = true` 现状与收窄前提

**现状**（`DynamicIsland/Info.plist:5-8`）：

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

即全局关闭 ATS（上游行为）。另外两处相关事实：`SUFeedURL` / `SUPublicEDKey` 为空串且 `services/AtollUpdaterDelegate.swift:28-29` 返回 `nil`（更新通道运行期不解析 URL）；`NSLocalNetworkUsageDescription` 尚未声明（09 §7 必办项，P2 补——LocalSend 实际需要）。

**收窄前提**（三条同时满足才可移除全局开关）：

1. **出站已全 HTTPS**：§3.2 的表内除本机 / 局域网端点外全部是 `https://`，这条已满足。
2. **本机与局域网明文要有例外**：`localhost:11434`（HTTP）、`localhost:26538`（HTTP）、LocalSend 的同网段 HTTP 传输与组播发现都需要保留 → 用 `NSAllowsLocalNetworking` 替代全局开关，并补 `NSLocalNetworkUsageDescription`；Lunar 的 23803 是裸 TCP，不受 ATS 约束。
3. **用户可自定义的远程资源要限定**：空闲动画远程 URL（`IdleAnimationsSettingsSection.swift:471` 的输入框）、`localModelEndpoint`、扩展 WebView 内容（09 §9.1 的 `allowWebInteraction` 白名单）在收窄后受 ATS 默认策略约束 —— 要么只接受 HTTPS，要么逐域名声明例外。

**结论**：维持现状（09 §8.2 的建议），本清单作为将来收窄时的逐条依据；收窄动作本身不是 P1 的内容（本批只建立台账）。
