# 功能清单与实现机制（范围已定稿）

这份文档回答两个问题：**这个 app 有哪些功能**，以及**每个功能大致怎么实现的**。范围已由 ADR-0011 + ADR-0012 锁定（2026-09-27），本文是实现依据。

与其它文档的分工：[05-feature-map.md](05-feature-map.md) 是"Nook X 有什么 → 我们归到哪个模块"的对标映射；本文是"我们实际交付什么 + 靠什么机制实现 + 上游已有什么"的实现稿。协议与字段级规范见 [06](06-module-protocol.md) / [07](07-config-and-events.md)，工程改造见 [08](08-p0-checklist.md)。

上游事实基于基线 `v2.3.3-beta.3`（`c7305ec`）的逐文件勘察；新增功能的机制已完成可行性实测（标注"已实测"处）。日期：2026-09-27。

---

## 0. 范围原则（已拍板）

| # | 原则 | 含义 |
|---|---|---|
| P1 | **上游有的，全部保留、维持现状** | 不做任何删除。上游 40 个功能一个不动，不重写实现 |
| P2 | **需要的功能，按需新增** | 上游没有、但我们要用的功能，**做成独立模块**新增（见 §5），不侵入上游文件 |
| P3 | **播放器只看"正在播放"** | 媒体数据源只用系统 Now Playing 一路；其余 6 个适配器保留代码但不启用、不维护 |
| P4 | **锁屏维持现状** | 锁屏面板集合与布局完全不变 |
| P5 | **不用的上游功能：保留原样、不投入** | AI 对话、AI 用量面板、全屏视频壁纸、系统 Clock 计时器镜像、蓝牙耳机管理——代码与界面原样保留，不做维护承诺、不进 P2 接管清单 |
| P6 | **仍不做的** | 照片浏览、番茄钟、AI agent 状态面板 |

**范围定稿过程**：初版曾计划删除 6 项上游功能，后修订为不删（删除要清理接线、每次季度同步重删、且有引入 bug 的风险，而"保留"成本只是代码在场）；又曾一律不新增功能，随后修订为**按需新增**（快捷启动、农历、进度、Shortcuts 上岛、通知上岛、终端外部化 —— 见 §5）。**2026-09-28 增补第 7 项：待办 `todos`**（§5.7），它同时把「进度」挤下折叠态中央槽位（进度默认关，见 §5.3）。

**新增部分的共同要求**：全部做成 [06 号协议](06-module-protocol.md) 下的独立模块（声明 manifest + 配置 schema + 事件），**不改上游文件**——这样季度同步零冲突，也符合"一切皆模块"的目标。

---

## 1. 产品形态：用户看到的四个面

| 面 | 用户看到什么 | 交互 |
|---|---|---|
| **折叠态** `compact` | 刘海两侧图标槽（网速/电量/CPU/农历/进度…）+ 中央主区域（正在播放/歌词/计时器/通知浮层） | 悬停预览、点击展开、上下滑动手势 |
| **展开面板** `expanded` | 一排 tab：主页 / Shelf / 计时器 / 状态 / 日历 / 笔记 / 剪贴板 / 启动台 / 终端 / 通知 … | 点击 tab 切换，点外部或再点收起 |
| **锁屏** `lockscreen` | 锁屏 widget：音乐面板、天气、日历、提醒、计时器、第三方扩展 widget | 锁屏时自动出现 |
| **瞬时浮层** HUD | 音量/亮度条、Caps Lock、电量、下载完成、媒体键反馈、**新通知到达** | 短暂显示后自动消失 |

---

## 2. 功能总览：机制 × 动作

**动作图例**：✅ 保留并接管（进 P2 模块化）· 🔧 保留并修缺陷 / 增强 · ⬜️ 保留原样（不投入）· 🆕 新增（上游没有，要做）

### A. 媒体与歌词

| 功能 | 动作 | 机制 |
|---|---|---|
| 正在播放（曲名/艺术家/封面/进度） | ✅ | vendored `MediaRemoteAdapter` 私有框架 + perl 子进程吐 JSON Lines（`--micros` 精度） |
| 播放控制（播放/暂停/上下曲/跳转/随机/循环） | ✅ | `dlopen` 私有 `MediaRemote.framework` → `MRMediaRemoteSendCommand` |
| **媒体数据源** | ✅ | **只用系统 Now Playing 一路**（P3）。它覆盖所有走系统媒体键的播放器 |
| 其余 6 个播放器适配器（Apple Music / Spotify / YouTube Music / Amazon / TIDAL / Cider） | ⬜️ | 代码保留（AppleScript / 逆向 cookie 的 Web API / AXUIElement / 本地 HTTP），默认不启用 |
| 逐行歌词 | ✅ | LRCLIB（主）→ NetEase（备）；匹配打分 + 版本标记过滤 + 精确 sleep 到下一行时间戳（clamp 0.05–0.25s）+ 行内高亮扫过 + 间奏识别（5s） |
| 歌词缓存 | 🔧 | 上游**纯内存 LRU 80 条、不落盘** → 补磁盘缓存（离线可用） |
| 逐字歌词 / 简繁转换 | ⬜️ | 上游无（只有逐行两级）→ 不在本轮范围 |

### B. 系统状态与时间进度

| 功能 | 动作 | 机制 |
|---|---|---|
| CPU（总量/每核/负载均值） | ✅ | `host_statistics` / `host_processor_info` / `getloadavg` |
| CPU 温度 | ✅ | AppleSMC（`IOServiceOpen` 读 SMC key） |
| CPU 频率 | ✅ | 私有 `IOReport.framework`（dlopen + 13 个符号） |
| 内存（用量/压力/Swap） | ✅ | `host_statistics64` + `sysctlbyname` |
| 网络速率 | ✅ | `getifaddrs` 增量采样 |
| 磁盘 I/O | ✅ | IOKit `IOServiceMatching("IOStorage")` |
| GPU | ✅ | IOKit `IOAccelerator` → `PerformanceStatistics` |
| 电量/充电/健康 | ✅ | IOKit `IOPSCopyPowerSourcesInfo` + `IOPSNotificationCreateRunLoopSource` |
| 蓝牙设备电量 | ⬜️ | `system_profiler` + `pmset` + `ioreg` 三子进程（属蓝牙管理功能，不投入） |
| 进程列表 | ✅ | `proc_pidinfo` |
| **日/周/月/季/年进度** | 🆕 **默认关** | **零私有 API、零依赖**：`Calendar.current.dateInterval(of:for:)` 取区间算 elapsed/total。细节见 §5.3。**2026-09-28 用户判定「时间进度」无行动价值 → `defaultEnabled` 改 `false`**（代码保留、可手动开回；中央槽位的默认内容改由待办 `todos` 承担，见 §5.7） |
| **待办（今日/本周/所有）** | 🆕 | **零私有 API**：EventKit 取提醒（未完成 + 最近 7 天已完成）+ 写回 `EKReminder.isCompleted`，**并可新增 / 删除（写的是系统提醒）**；环心是 `已办/总量`。细节见 §5.7 |

**采样策略（上游已符合性能基线，沿用）**：默认 1s，clamp [1,60]；只在刘海展开且停在 stats tab 时采样，关闭后延迟 3s 停；进程列表独立节流 2s。

### C. 时间：日历 / 提醒 / 农历 / 计时器

| 功能 | 动作 | 机制 |
|---|---|---|
| 下一个日程 + 今日日程 | ✅ | EventKit `events(from:to:)` + `EKEventStoreChanged` 监听（带 debounce） |
| 提醒（含勾选完成） | ✅ | EventKit `fetchReminders` + 写回 `EKReminder.isCompleted`（上游面板维持现状）；**新增的待办 `todos`（§5.7）另有自己的取数、左侧三环视图与增删**（写入 / 删除系统提醒） |
| 日程提前提醒 | ✅ | `reminderLeadTime` + 独立 Live Activity 管理器 |
| 本地计时器 | 🔧 | `Timer.scheduledTimer` 1s tick → 上游**退出即丢状态、无 UserNotifications** → 补持久化 + 到点通知 |
| 锁屏计时器面板 | ✅ | 用 `TimerManager.shared` |
| **农历** | 🆕 | **零私有 API、零依赖**：Foundation 的 `Calendar(identifier: .chinese)` 拿农历月/日/闰月/干支；节气用预置表。细节见 §5.2 |
| 系统 Clock 计时器镜像 | ⬜️ | 私有 `com.apple.mobiletimerd` plist + `log stream` + AXUIElement（1288 行，三重不稳定）→ 不投入 |

### D. 文件与内容

| 功能 | 动作 | 机制 |
|---|---|---|
| 文件暂存架 | ✅ | `NSItemProvider` 拖入 + `NSDraggingSource` 拖出；JSON 落盘（逐条容错解码） |
| AirDrop / 分享 | ✅ | `NSSharingService(.sendViaAirDrop)` + `NSSharingServicePicker` |
| 局域网互传 | ✅ | 自实现 LocalSend v2 协议（组播 `224.0.0.167` + 自带 HTTP server + TLS）→ 需补 `NSLocalNetworkUsageDescription` |
| Quick Look 预览 | ✅ | `QLPreviewPanel` |
| 剪贴板历史 | 🔧 | 0.5s 轮询 `NSPasteboard.changeCount` → 补电源优化（电池上降频） |
| 下载文件夹监控 | ✅ | `DispatchSource` 文件系统事件 + 速度采样 + 未完成文件识别 |
| 速记 / Markdown 笔记 | ✅ | 自建编辑器 + 图片 + Apple Notes 双向同步（AppleScript 桥） |
| 取色器 | ✅ | `NSColorSampler()` |

### E. 快捷：启动 / 控制 / 热键

| 功能 | 动作 | 机制 |
|---|---|---|
| **快捷启动（Launcher）** | 🆕 | **零私有 API**：扫描 App 目录 + `NSWorkspace.openApplication` + 自建使用频次。细节见 §5.1 |
| **系统 Shortcuts 上岛** | 🆕 | **零私有 API**：`/usr/bin/shortcuts list --show-identifiers` 枚举 + `shortcuts run` 执行（支持输入输出）。细节见 §5.4 |
| 音量 | ✅ | CoreAudio `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` |
| 音量/亮度媒体键拦截 | ✅ | CGEventTap 解析 `NX_SYSDEFINED`（需辅助功能权限） |
| 亮度（内建屏） | ✅ | 三级回退：私有 `CoreBrightness` → dlopen 私有 `DisplayServices` → `IODisplaySetFloatParameter` |
| 键盘背光 | ✅ | 私有 `CoreBrightness` 反射 + IORegistry |
| 防休眠 | ✅ | IOKit `IOPMAssertionCreateWithName`（退出自动释放） |
| 音频输出切换 | ✅ | CoreAudio 枚举 + 设默认设备 |
| 每 App 音量 | ✅ | CoreAudio `CATapDescription` 进程 tap + 私有 stacked aggregate device |
| 勿扰（Focus）状态 | ✅ 只读 | 读 `~/Library/DoNotDisturb/DB/Assertions.json` + `log stream`；上游无法切换 |
| 蓝牙开关状态 | ✅ 只读 | IOBluetooth `powerState` |
| 外接屏亮度 | ✅ | 经第三方 App（Lunar TCP 23803 / BetterDisplay），上游不发 DDC |
| 抑制原生 OSD | ✅ | `launchctl` + `killall -STOP/-CONT OSDUIHelper` |
| 全局热键 | ✅ | SPM `KeyboardShortcuts`（MIT） |
| **终端** | 🔧 | 上游内嵌 SwiftTerm + `⌃\`` → **新增"外部 App"模式**，可配置为已安装的 Ghostty。细节见 §5.6 |

### F. 通知（新增模块）

| 功能 | 动作 | 机制 |
|---|---|---|
| **通知上岛** | 🆕 | **两条通道**：AX 横幅（实时 + 可真关闭，需辅助功能）与通知中心数据库（SQLite 只读，列表/历史/降级，需完全磁盘访问）+ `NSWorkspace` 打开对应 App。细节见 §5.5 |
| **点击打开对应应用** | 🆕 | 记录里的 `bundleIdentifier` → `NSWorkspace.openApplication(at:)`（公开 API，可靠） |

### G. AI

| 功能 | 动作 | 机制 |
|---|---|---|
| AI 对话（屏幕助手） | ⬜️ **默认关闭** | **上游确实有**：`ScreenAssistantManager` 1317 行，5 家 provider（Gemini / OpenAI / Claude / Groq / Ollama），支持图片/文件/录音/截图，热键 `⌘⇧A`。但入口是**独立悬浮面板而不是刘海 tab**（`NotchViews` 里没有 AI 项），所以从界面看容易以为"没有这个功能"。上游开关 `enableScreenAssistant` **默认 `true`** → 我们在首启把它写成 `false` 即可（不改上游源码） |
| AI 用量额度面板 | ⬜️ | 扫 `~/.claude/**/*.jsonl` + 拉各厂商私有额度端点 + Keychain token → 原样保留，不投入 |
| AI agent 状态面板 | 不做 | 上游只有用量额度、无运行状态（P6） |

### H. 视觉与场景

| 功能 | 动作 | 机制 |
|---|---|---|
| 锁屏面板群（音乐/天气/日历/提醒/计时器） | ✅ 维持现状 | `NSWindow` + `level = CGShieldingWindowLevel()` + SPM `SkyLightWindow` 私有代理 |
| 天气 | ✅ | 裸 URLSession 打 open-meteo（免 key）+ CoreLocation + WMO 图标映射 |
| 摄像头镜子 | ✅ | AVFoundation `AVCaptureSession` + 热插拔监听 |
| 隐私指示灯 | ✅ | CoreMediaIO + CoreAudio 双路探测 |
| 全屏封面 / 视频壁纸 | ⬜️ | `FullScreenArtworkWindowManager` 1801 行 + `killall -STOP WallpaperAgent` → 不投入 |
| 空闲动画（Lottie） | ✅ | 6 个内置 json + 用户导入 + 远程 URL |
| 三种 HUD 风格 | ✅ | 圆形 / OSD / 竖直，均 SkyLight 代理 |
| 屏幕录制检测/停止 | ✅ | CGEventTap + `killall screencapture` + 私有 `CGSRegisterNotifyProc` |
| 从截屏中隐藏刘海 | ✅ | `window.sharingType = .none` |
| 动态封面（Apple Music motion artwork） | ✅ | `AnimatedArtworkManager`（与"视频壁纸"是两件事） |
| 主面板背景（展开态 / 非刘海屏浮动药丸） | 🔧 **2026-09-28 可配** | 三档：**纯黑（默认，与上游写死的 `.background(.black)` 完全一致）** / 液态玻璃（私有 `NSGlassEffectView`，`LiquidGlassBackground` 组件）/ 毛玻璃（`NSVisualEffectView` `.hudWindow` + `.behindWindow`，材质层强制深色外观）。玻璃两档**只在「展开态」或「非刘海屏的浮动药丸」上生效**——刘海屏折叠态保持纯黑（要与物理刘海融合，玻璃会露出壁纸、形成一块突兀的方块）。**玻璃底顶部另有一条不透明黑带**（2026-09-28 用户反馈「菜单栏里面的图标都变形了」）：玻璃是 behindWindow 材质、采样窗口背后的画面，而面板顶边与系统 UI 带同高 → 菜单栏图标会被采进玻璃糊成一片；黑带高度 = 刘海高度（刘海屏）/ 菜单栏高度（非刘海屏），判据收在 `panelTopOpaqueBandHeight(safeAreaTop:menuBarHeight:)`，纯黑档不受影响。入口：设置页 **Appearance → Panel Background**；接线与取舍见 [13](13-runtime-kernel.md) D-26 |

### I. 工程与系统集成

| 功能 | 动作 | 机制 |
|---|---|---|
| 开机启动 | ✅ | SPM `LaunchAtLogin-Modern` |
| 自动更新 | ✅ | Sparkle 2.7.0 + appcast（**P0 必须换掉上游 feed 与公钥**） |
| 内存自愈 | ✅ | `MemoryUsageMonitor` 超限自重启（对应 <150MB 基线） |
| 权限引导 | ✅ | 辅助功能 / 完全磁盘访问 / 相机 / 日历 / 提醒的请求与检测 |
| 第三方扩展 | 🔧 | XPC + WebSocket RPC + 三种内容描述符渲染管线 → P4 补插件包/版本/看门狗 |
| 本地化 | 🔧 | 收敛为 zh-Hans 主 + en |

---

## 3. 代价清单（保留上游能力的真实成本）

### 3.1 私有 API / 私有框架（全部保留）

| 私有目标 | 用途 | 加载方式 | 失效影响 |
|---|---|---|---|
| `MediaRemote.framework` | 媒体控制与元数据 | `CFBundleCreate` + 函数指针 | **旗舰功能失效** |
| `MediaRemoteAdapter.framework`（vendored） | 同上 | perl 子进程 | 同上 |
| `CoreBrightness.framework` | 亮度、键盘背光 | `CFBundleCreate` + 反射内部类 | 亮度控制失效 |
| `DisplayServices.framework` | 亮度回退 | `dlopen` + `dlsym` | 回退路径失效 |
| `IOReport.framework` | CPU 频率 | `dlopen` + `dlsym` | 该指标失效 |
| CGS 私有 C 函数（7 个） | 专用 Space、窗口层级 | `@_silgen_name` | 窗口定位异常 |
| SkyLight 私有 API | 锁屏窗口代理 | SPM `SkyLightWindow` | 锁屏面板失效 |
| `com.apple.mobiletimerd` | 系统计时器镜像 | 私有 plist + `log stream` + AX | 该功能失效 |
| DoNotDisturb DB | Focus 状态只读 | 直读 JSON | 只读失效 |
| 11 个 `com.apple.Bluetooth.*` 私有通知 | 蓝牙设备状态 | DistributedNotificationCenter | 蓝牙电量失效 |
| **通知中心数据库**（新增） | 通知上岛（列表/历史/降级） | 只读 SQLite（`group.com.apple.usernoted/db2/db`） | **DB 通道失效** → 退到 AX 通道（仍能实时弹浮层与真关闭，只是没有列表与历史，见 §5.5） |
| **通知中心 AX 树**（新增） | 通知上岛（实时 + 真关闭） | `AXObserver` + 0.5s 轮询读 `com.apple.notificationcenterui` 的窗口 | **AX 通道失效**（元素树/动作名随版本变）→ 退到 DB 通道（约 5s 延迟），探针原文是校准依据（见 §5.5） |

**要求**：每处都要有**失效降级路径**，并建台账记录用途 + 替代路径（[01-architecture.md](01-architecture.md) §9 的"私有 API 诱惑"，升级为台账 + 降级实现）。
**好消息**：本轮 6 项新增功能里有 5 项**零私有 API**（Launcher、农历、进度、Shortcuts、终端外部化），只有通知上岛引入新的私有数据依赖。**2026-09-28 增补的待办 `todos`（§5.7）同样零私有 API**（EventKit + 系统 TCC），因此是「6 项新增里有 6 项零私有 API」。

### 3.2 外部子进程（约 22 处，新增 1 处）

`perl`（媒体）、`launchctl` + `killall`（OSD / 壁纸 / 录屏）、`log stream`（Focus / 系统计时器）、`system_profiler` + `pmset` + `ioreg`（蓝牙）、`screencapture`、`security`、`zip`、`arp`（LocalSend）、`ps`/`pgrep`/`lsof`、`networksetup`、`corebrightnessdiag`、`zsh`（终端），**新增 `/usr/bin/shortcuts`**（快捷指令枚举与运行）。

**风险**：`perl` 已不被 Apple 推荐；`log stream` 常驻是持续 CPU 开销；`killall -STOP` 系统进程属于"赌它不会坏"；`shortcuts run` 要限时（30s 超时 + 禁止并发）。

### 3.3 权限

相机、麦克风、日历、提醒、位置、**辅助功能**（媒体键/亮度键拦截、AX 读写）、**完全磁盘访问**（上游用于权限自检；**通知上岛将真正依赖它**）、AppleScript 自动化、音频录制（每 App 音量）、屏幕录制（截图）、局域网（LocalSend）。

**两个硬依赖**：辅助功能（不给则媒体键/亮度键/部分功能不可用）、完全磁盘访问（不给则通知上岛不可用——这是本轮新增的依赖）。另有 `disable-library-validation` entitlement（为加载 adhoc 签名的 vendored framework），决定了不能上架（ADR-0001 已排除上架，一致）。

**授权提示策略（2026-09-28 起，已落地）**：启动路径上的授权提示改为**每次安装最多申请一次**，不再"每次启动都问"——

| 提示 | 闸门 | 落点 |
|---|---|---|
| 辅助功能（媒体键拦截） | `didPromptAccessibilityOnce` | `managers/MediaKeyInterceptor.swift` |
| 定位（锁屏天气） | `didPromptLocationOnce` | `managers/LockScreenWeatherManager.swift` |

**默认关掉的高打扰功能**：锁屏「动态封面」（`lockScreenMusicFullscreenVideoArtwork`，需 Apple Music 授权）于 2026-09-28 改为**默认关**，并在 设置 → 锁屏 加了开关（`Fullscreen video artwork`）。理由：默认开启时，只要播放 Apple Music 就会触发系统的 Apple Music 授权弹窗（自动化/媒体资料库按"服务 × 目标应用"分别授权，Music / 备忘录 / Spotify 各一条），与"不需要的功能不打扰用户"的口径冲突。同理，任何**会触发系统授权弹窗**的新功能，默认值一律取关。

两条闸门都持久化在 UserDefaults（随 Bundle ID 保留，重装/升级不重置），且测试宿主（XCTest，含单测宿主）**一律不弹**（`helpers/AppRuntimeEnvironment.isRunningTests`）；下载目录探测同样在测试宿主下跳过。用户后续仍可主动授予：菜单「请求辅助功能权限／打开系统设置」，或系统设置 › 隐私与安全性 › 定位服务。

> **为什么要这样改**：上游的实现是"只要授权状态仍是未决定（或未授权）就每次启动都弹"（`didRequestAccessibilityPrompt` 是内存变量；定位侧只看 `.notDetermined`）。用户关掉弹窗后下次启动还会被问；叠加签名身份变更（ad-hoc → 自签证书）时系统会重新询问，表现为"授权永远授不完"。签名侧的处理见 [10-p0-execution.md](10-p0-execution.md)。

---

## 4. 不做的事

### 4.1 不删除上游任何功能

评审初期曾列 6 项删除候选（约 8000 行），最终决定一项都不删：删除要清理接线（牵动 9696 行的 `SettingsView`、锁屏两个入口、菜单与热键）、每次季度同步都要按清单重删、删错会引入新 bug；而保留的成本只是"代码在场"。**不需要的功能用"不投入"表达**（§0 P5）。

**已核实的信息留档**（若将来改主意要删，不必重查）：删蓝牙管理器会影响锁屏天气卡片的蓝牙电量分支（`LockScreenWeatherManager.lockScreenBatteryShowsBluetooth`）；删全屏壁纸会影响锁屏音乐面板的"全屏"按钮与 Spotify Canvas fallback 分支；删终端可移除 `SwiftTerm` 依赖但**不能免除 Metal Toolchain**（项目自身有 `metal/visualizer.metal`）；删 LLM 用量可连带删 `update-pricing.yml` workflow 与 `new-api` Keychain service。

### 4.2 仍不实现（3 项）

| 不实现 | 说明 |
|---|---|
| 照片浏览 | `PhotoKit` 全库浏览与岛上展示，优先级最低 |
| 番茄钟 | 上游计时器加循环即可、成本低，但当前不需要 |
| AI agent 状态面板 | 上游只有用量额度、无运行状态 |

**说明**：逐字歌词 + 简繁转换也**不在本轮**（上游只有逐行歌词）——如果实际用起来觉得缺，再单独提。

---

## 5. 新增功能的实现机制（本轮重点）

六项新增功能的详细设计（**2026-09-28 增补第 7 项：待办 `todos`，见 §5.7**）。共同点：**都做成独立模块**（[06 号协议](06-module-protocol.md) 的 manifest + config schema + 事件），不改上游文件；除通知外**全部零私有 API**。

### 5.1 快捷启动 `launcher`

| 项 | 设计 |
|---|---|
| 数据源 | 扫描 `/Applications`、`/System/Applications`（含 `Utilities`）、`~/Applications`（含子目录两层）找 `.app`；`Bundle(url:)` 读 `CFBundleDisplayName` / `CFBundleName` / `CFBundleIdentifier` |
| 图标 | `NSWorkspace.shared.icon(forFile:)`，异步预热 + 缓存（首次全量约百毫秒级，可接受） |
| 搜索 | 名称子串匹配 + 拼音首字母（`CFStringTransform` 转拼音，成本低）；结果按"使用频次 × 最近使用"排序 |
| 启动 | `NSWorkspace.shared.openApplication(at:configuration:)`（`activates = true`） |
| 常用/最近 | **自建使用计数**（记录从岛上启动的次数与时间）。不读 `com.apple.LSSharedFileList` 的 `.sfl3` 私有格式——私有格式随版本变，而我们只需要"我自己常用" |
| 呈现 | 折叠态槽位图标（点击展开）+ 展开面板一个 tab（网格 + 搜索框 + 固定区） |
| 热键 | KeyboardShortcuts 全局热键唤出（默认留空，避免与系统冲突） |
| 配置 | `pinnedApps`（appPicker 列表）、`showRecents`（bool）、`iconSize`、`density` |
| 权限 | **无**（全部公开 API） |
| 工作量 | 中（3～5 天） |

### 5.2 农历 `lunar`

| 项 | 设计 |
|---|---|
| 主算法 | **Foundation 的 `Calendar(identifier: .chinese)`**——系统内置、零依赖、Apple 负责维护。可拿农历月/日、**闰月**（`component(.isLeapMonth)`）、干支年（era/year 映射 60 甲子） |
| 生肖 | 由农历年推（12 年循环） |
| 24 节气 | **预置表方案**：把 2000–2100 的节气时刻预先算好存为数据（100 年 × 24 ≈ 2400 条，几十 KB）。理由：确定、可单测、避免自研天文算法（太阳黄经近似公式容易在边界出错） |
| 不做 | **黄历宜忌**不做（无权威数据源，且属民俗范畴） |
| 呈现 | 折叠态槽位（"八月十六"这类短文本，可配置显示格式）+ 展开面板日历 tab 内增强 |
| 配置 | `displayFormat`（enum：仅日期 / 日期+干支 / 日期+节气）、`showFestivals`（bool，节假日表可选） |
| 权限 | **无** |
| 测试 | 单测对照 1900–2100 抽样日期（与系统"日历"App 或权威万年历比对），**节气表要有校验用例** |
| 工作量 | 低（1～2 天） |

### 5.3 日/周/月/季/年进度 `progress`（**默认关**，2026-09-28）

> **状态**：`defaultEnabled = false`（2026-09-28 用户判定「时间进度」无行动价值——看得到但不构成要做的事；中央槽位默认内容改由 §5.7 的待办 `todos` 承担）。**代码、manifest 与配置项全部保留**，可手动开回；本节其余设计仍然有效，只是默认不上屏。

| 项 | 设计 |
|---|---|
| 算法 | `Calendar.current.dateInterval(of:for:)` 取区间（`.day` / `.weekOfYear` / `.month` / `.year`），`elapsed / total` 得比例；季度自定义（Q1 = 1–3 月）。**不手算天数**，交给 `Calendar` 处理闰年/跨年/时区 |
| 刷新 | 不需要定时器：按当前粒度的自然推进节奏刷新（日进度 1 分钟、周/月/季/年 1 小时），且只在槽位可见时刷新 |
| 呈现 | **折叠态 = 中央槽位**常驻「最关心的一个尺度」的百分比（尺度图标 + 数值；取 `visibleScopes` 首项，默认「今天」）；**展开态 = 剩余量清单**（一行一个尺度：图标 + 标签 + 细进度条 + **剩余量** + 百分比，行悬停补该尺度的起止时刻）。默认只显示 **日 + 年**，可配 `visibleScopes`（2026-09-27 定稿，取代原稿的「折叠态环形进度或百分比文本 / 展开面板多环 + 数字」） |
| 边界 | 用户改系统时间 / 时区切换 → 用 `Calendar.autoupdatingCurrent` + 监听 `NSSystemClockDidChange` |
| 配置 | `visibleScopes`（多选：day/week/month/quarter/year）、`style`（ring/bar/text）、`baseCalendar`（公历/农历周？默认公历） |
| 权限 | **无** |
| 工作量 | 极低（0.5～1 天） |

### 5.4 系统 Shortcuts 上岛 `shortcuts`

| 项 | 设计 |
|---|---|
| 枚举 | `/usr/bin/shortcuts list --show-identifiers`（**已实测**：支持 `--folders`、`--folder-name`）。结果**缓存进配置**，提供手动刷新按钮；不要每次进岛都起子进程 |
| 标识 | 用**identifier** 而不是名称（名称可重复、可随时改；identifier 稳定） |
| 运行 | `/usr/bin/shortcuts run <identifier>`（**已实测**：支持 `--input-path` / `--output-path` / `--output-type`）。子进程调用需**限时 30s + 禁止并发**（沿用 §3.2 既有模式） |
| 输入联动 | 把 **Shelf 暂存架的文件**作为 `--input-path` 传进去（"把文件拖到岛上 → 交给某个快捷指令处理"）——与已有功能自然联动 |
| 输出回显 | `--output-path` 写临时文件 → 读回 → 在岛上显示结果（适合"生成文本/查询类"快捷指令）；输出过大则只显示前 N 行并给"在 Finder 中显示" |
| 呈现 | 展开面板一个 tab（列表 + 搜索 + 固定）+ 可选折叠态槽位（最近使用的 1 个快捷指令） |
| 配置 | `pinnedShortcuts`（identifier 列表）、`showOutput`（bool）、`timeoutSeconds` |
| 权限 | 无额外权限（首次运行可能触发系统自动化提示，需实测定） |
| 工作量 | 低～中（2～3 天） |

### 5.5 通知上岛 `notifications`（本轮风险最高的一项）

| 项 | 设计 |
|---|---|
| **主方案** | 读通知中心数据库：`~/Library/Group Containers/group.com.apple.usernoted/db2/db`（SQLite，**已实测：该容器在 macOS 27 上仍存在**；读取被 TCC 拒绝 → 需要**完全磁盘访问**） |
| 读取方式 | **只读打开**（`SQLITE_OPEN_READONLY`），**绝不修改该库**。取 `record` 表的 `data` 列（二进制 plist：标题/副标题/正文/app id/时间）与 `app` 表（bundle id ↔ 显示名） |
| 增量策略 | 按 `record` 的单调 id 取新增 + **文件事件触发**（2026-09-28 用户反馈「要在灵动岛的位置直接实时显示」后落地）：`DispatchSource` 监听 `db` 与 `db-wal`（WAL 模式下新通知只写 `-wal`，只挂主库等于没挂）的 `[.write, .extend, .attrib, .delete, .rename]`，事件后去抖 0.3s 立刻取增量并弹浮层；**60s 兜底轮询**只用来兜事件漏报（**不过 mtime 闸门**——它要救的正是漏报），取数期间到来的事件排队补一次。**不做 1s 全表扫**（该库可能很大） |
| 点击行为 | 取记录里的 `bundleIdentifier` → `NSWorkspace.shared.openApplication(at:)` 打开对应 App（**公开 API，可靠**） |
| 关闭 / 清除 | **两种口径并存**（2026-09-28 加 AX 通道后收窄）：① **仅从岛上移除**（DB 侧默认口径）：行右侧 `xmark.circle.fill` 关一条、状态行「清除」关当前列表全部；关闭的 `rec_id` 存 `Defaults.dismissedNotificationIDs`（有序、**写入时裁剪到最近 500 个**），取数时按 id 滤掉；② **真关闭**（AX 侧，2026-09-28 落地）：浮层的 × 命中 AX 横幅的关闭控件时执行「关闭」动作，`AXPress` 关掉真实通知；列表行的 × 只在**近 10 秒内有同指纹的 AX 横幅句柄**时顺带真关那一条（多数条目早已过期 → 只隐藏）。库里一条记录都不动（只读原则：`record` 表只读），通知中心界面除该「关闭」动作外不做任何写操作 |
| 降级方案 | **两条通道并行**（2026-09-28 定稿，不再是「DB 不行才退到 AX」）：**AX = 实时 + 可真关闭**、**DB = 历史列表与降级** |
| 呈现 | ① 折叠态**瞬时浮层**：通知到达时短暂展示（复用上游 HUD / Live Activity 形态与 `ttlMs` 语义）——**已落地**（2026-09-28，P2d）：内核 `ModuleRegistry.presentHUD` + `UIHandle.presentTransient`（ttl 夹取 1…15s，通知侧取**设置项** `notificationHUDDurationSeconds`、**默认 8s**），~~关闭态优先级链插在 OSD 类（音量/亮度/大小写锁）之后、音乐/计时器/提醒之前~~（**已被 D-23 取代**：浮层是内核自己的独立窗口，不在关闭态链里），一次取数多条新增**只弹最新一条**。**两个来源共用同一个视图**（2026-09-28）：AX 横幅（实时）与 DB 增量（降级）；浮层右上一个 `xmark.circle.fill`——有 AX 句柄时**真关闭**，否则仅从岛上隐藏（`UIHandle.dismissTransient()` 撤浮层 → 窗口淡出）。~~浮层文字列上界 140pt（超出刘海宽的部分会被窗口裁掉）~~（**已被 D-24 取代**：固定尺寸 320 × 64 × 倍率 `notificationHUDScale`，超长内容在卡片内两行截断、完整正文看展开列表）。**多屏**（2026-09-28 用户反馈「当鼠标在哪个屏幕，哪个屏幕才显示，这个应该是所有屏幕都显示才对」，D-25）：**应用会显示岛的每一块屏上各有一个浮层窗口**，同一条浮层在所有屏同时出现 / 同时消失；目标屏 = `showOnAllDisplays` 为真时取 `NSScreen.screens` 全集、为假时只取该设置指定的那块屏（`preferred_screen_name`，与岛同源；指定屏不在场时退到主屏 → 列表第一块）。**五个设置项**（2026-09-28 用户要求「做一个配置项」）：总开关 / 显示时长 / 背景（液态玻璃或纯色）/ 正文 / 字号，入口是设置页 Live Activities → **Notification HUD** ② 展开面板一个通知列表（按 App 分组、可滚动）——列表已落地（含关闭 / 清除），**按 App 分组尚未做** |
| 能力边界（必须接受） | ① **DB 只能读**：不能回复、不能在系统通知中心里操作真实通知；**AX 能真关闭**（执行横幅的「关闭」动作）但只此一项写操作，库与界面其余部分一律只读 ② 需要完全磁盘访问（DB）+ 辅助功能权限（AX；上游已授予，未授权时**静默降级**——不申请、不提示）③ 两条都可能随系统改版失效：DB 是 schema 私有，AX 是元素树/动作名随版本变（**探针原文落盘就是为了校准**）④ 通知内容敏感，属隐私面——**默认在浮层显示正文**（`showBodyInHUD` 默认 **true**：用户 2026-09-28 明确要求，**覆盖设计稿原口径的 false**；关掉后浮层第二行只留一条「新通知」，展开列表照旧显示全文） |
| **实时性实测**（2026-09-28，Release 产物） | **DB 通道**：库里落盘 → 浮层 **0.303s**：`db-wal` 写入 15:54:10.884 → kqueue 事件 15:54:10.8835 → 去抖结束 15:54:11.1854 → 取到新记录并弹浮层 15:54:11.1866（截图 0.36s 后拍到浮层）。**链路前端有一段不由本应用控制的延迟**：usernoted 把通知**批量落盘**——`osascript display notification` 到 `db-wal` 出现该记录实测 5.0～5.1s；**退出本应用后的对照实验同样是 5.10s**（故与本应用无关，记录的 `delivered_date` 才是真实投递时刻）。因此「造一条通知 → 岛上出现」端到端约 5.3s，其中 0.3s 是我们的管道——原先 30s 轮询口径下最坏 30s+，且 mtime 闸门只看主库时**永远不触发**。**AX 通道**（2026-09-28）：横幅出现 → 捕获亚秒级（`osascript` 投递 16:12:05.3 → AX 窗口带横幅树 16:12:05.348，≈0.05s；同一秒内 `AXObserver` 未触发时由 0.5s 轮询兜住），**这就是「通知横幅一出现就上岛」**——不再等 macOS 落盘 |
| **AX 通道形态**（2026-09-28 探针实测，macOS 27） | 横幅树：`AXWindow subrole=AXSystemDialog title="Notification Center"` → `AXGroup subrole=AXHostingView` → `AXGroup` → `AXScrollArea` → **`AXGroup subrole=AXNotificationCenterBanner`**（`description` = `"<App 名> <标题>, <副标题>, <正文>"`）→ 依次 `AXStaticText`（标题 / 副标题 / 正文）。三条**反直觉**的实测结论：① **App 名没有独立元素**，只在横幅容器的 `AXDescription` 首段（实现用「剥掉已知标题后缀」取它，剥不出来就给空、不猜）；② **关闭不是 `AXButton`**：横幅容器的动作表里有一个**自定义动作** `Name:关闭\nTarget:0x0\nSelector:(null)`，对**容器**执行**这个名字**才关得掉（`AXPress` 只是「显示详细信息」）；带副标题的横幅偶尔额外暴露 `AXButton desc=关闭`，两条路都认（**先按钮后动作**）；③ **动作返回值不可信**：`AXUIElementPerformAction` 传不存在的动作名也返回 `0`，因此成功判据 = 「动作返回成功 **且** 元素随后失效」。挂载方式：`AXObserver(kAXWindowCreatedNotification)` **+ 0.5s 轮询兜底**（本机实测 AXObserver 不是每条都触发），两条都按窗口签名去重；通知中心进程会被系统重启（实测 `killall NotificationCenter` 后 pid 813 → 44809），pid 变了就**重挂**。探针原文：`~/Library/Logs/Gourd/ax-banner-probe.log`，解析结果：`notifications-probe.log`（超 4MB 轮转一代） |
| **两条通道去重**（2026-09-28） | 同一条通知会被 AX 与 DB 各触发一次 → 用「`appName + title + body` 指纹（归一化：trim / 折叠空白 / 小写）+ **10s 窗口**」去重（`NotificationBannerLedger`，纯逻辑可单测）。**AX 优先**：AX 先到弹了浮层，约 5s 后 DB 那条同指纹事件只进列表、不再弹浮层（未读数与列表不受影响）；AX 拿不到时 DB 照常弹——两条通道互不饿死。10s 窗口同时是真关闭句柄的存活期 |
| **先做探针** | 第一步只做一个**可行性探针**：只读库 + 打印最近 5 条通知的字段。在 macOS 27 + 完全磁盘访问下验证 schema 可用后，再投入完整功能。**避免做几天才发现读不出来**（2026-09-28 已落地：报告落盘 `~/Library/Logs/Gourd/notifications-probe.log`，本机实测可读） |
| 配置 | **五个浮层设置项**（2026-09-28 用户要求「做一个配置项，要包含总开关、显示时长、背景设置（是否为液态玻璃模式）这些」；都是宿主设置 `Defaults.Keys`，入口 = 设置页 Live Activities → **Notification HUD**）：`enableNotificationHUD`（bool，**默认 true**，**总开关**：关掉后完全不弹浮层——连 `presentTransient` 都不调，但列表 / 未读计数 / AX 真关闭 / DB 增量全部照常）、`notificationHUDDurationSeconds`（double，**默认 8**，显示时长；设置滑块 2…15s、内核仍夹取 1…15s）、`notificationHUDBackgroundStyle`（enum，**默认 `.liquidGlass`**：`Liquid glass` / `Solid`，液态玻璃档**强制深色外观**——浅色系统下玻璃会变浅、白色文字看不清）、`showBodyInHUD`（bool，**默认 true**——用户口径覆盖设计稿的 false）、`notificationHUDScale`（double，默认 1.3，字号 / 卡片倍率）。另有 `dismissedNotificationIDs`（`[Int]`，已关闭的 `rec_id`，模块读写、上限 500）、`appsFilter`（白/黑名单，**尚未做**）、`maxItems`、`pollIntervalSeconds`（后两项仍是代码常量——轮询已换成「文件事件 + 60s 兜底」，模块 manifest 本版不读配置） |
| 权限 | 完全磁盘访问（DB 通道）+ 辅助功能（AX 通道；上游媒体键拦截已在用，因此**不新增权限申请**——未授权时 AX 通道静默不启动、DB 照常） |
| 工作量 | 中～高（探针 0.5 天；完整 4～6 天，含降级路径）——2026-09-28 已完成探针 + 列表 + 瞬时浮层 + **文件事件实时化 + 岛上关闭/清除 + AX 实时通道（含探针落盘与真关闭）**；剩余：按 App 分组、`appsFilter` |

> **隐私提示**：通知上岛意味着读取系统通知内容。设计上做到：只读、不落盘（除必要的内存缓存）、App 级过滤可关掉某些来源（如密码类 App）。**浮层默认显示正文是用户 2026-09-28 的口径**（原设计稿的「默认不显示正文」按用户为准作废）；不想在关闭态看到正文的用户，在设置页 Live Activities → Notification HUD 关掉 `Show notification body in the notch HUD` 即可；连浮层本身都不想要（只留展开列表）就关掉同一区块的**总开关** `Show notification HUD`（2026-09-28 加）。
>
> **关闭/清除的落盘范围**（2026-09-28）：`Defaults.dismissedNotificationIDs` 里只有**数字 id**（`rec_id`），没有标题/正文/App 名；上限 500 个、写入时裁剪。它只用于「不再显示这几条」，不构成对通知内容的第二份拷贝。
>
> **AX 通道的探针落盘范围**（2026-09-28）：`~/Library/Logs/Gourd/ax-banner-probe.log` 里**有**横幅的可见文本（App 名 / 标题 / 副标题 / 正文的前 80 字符）——它是 schema 校准的唯一依据，因此**刻意落盘**；只写本地、不联网、单文件超 4MB 轮转一代。不想留这份日志的用户删掉该文件即可（下次有横幅时会重建）。

### 5.6 终端外部化 `terminal`

| 项 | 设计 |
|---|---|
| 目标 | **岛内不嵌终端**，唤起已安装的终端 App——目标 **Ghostty**（**已实测**装在 `/Applications/Ghostty.app`） |
| 上游现状 | 内嵌 SwiftTerm 终端视图 + `⌃\`` 唤出。**代码保留**（ADR-0011 不删），但不作为目标形态 |
| 实现 | `NSWorkspace.shared.openApplication(at:configuration:)` + `NSWorkspace.OpenConfiguration`（可传 `arguments` / `environment`）；工作目录用参数传给 Ghostty |
| 配置 | `mode`（enum：`builtin` / `external`，**默认 `external`**）、`externalApp`（appPicker，默认 `com.mitchellh.ghostty`）、`openMode`（`newWindow` / `activateOnly`）、`workingDirectory`（`home` / `currentContext`）、`extraArguments`（list&lt;string&gt;） |
| 呈现 | `external` → 岛上只显示一个"打开终端"入口；`builtin` → 岛内终端视图（可选） |
| 权限 | 无新权限 |
| **待实测** | Ghostty 接受哪些启动参数（`--working-directory=<path>` 是否生效、是否需要 `ghostty +new-window`） |
| 优先级 | **最低，放 P2b 最后**（用户指定） |
| 工作量 | 低（1～2 天） |

### 5.7 待办 `todos`（2026-09-28 增补）

| 项 | 设计 |
|---|---|
| 定位 | **取代进度成为折叠态中央槽位的默认内容**（13 号文档 D-20）：`已办/总量` 是真实进度，「今天过了 62%」不是 |
| 取数 | **模块自己持有 `EKEventStore`**（不改上游 `CalendarServiceProviding`，也不进 `CalendarManager`）。未完成 = `predicateForReminders(in: nil)`（跨所有列表，**含无到期时间**）；已完成 = `predicateForCompletedReminders(withCompletionDateStarting: 最近 7 天起点, ending: nil, calendars: nil)`。上游的 `fetchReminders(from:to:)` 只取「未完成 + 按 dueDate 过滤」的条目，拿不到无到期时间与已完成的，因此不复用 |
| 呈现 | **展开态 = 左侧竖排三环（今日 / 本周 / 所有）+ 右侧该类别清单**：环上限 52×52（按可用高度收缩，下限 30）、环心为 `已办/总量`，三个环同时是**筛选器**（点击切换清单类别，默认今日；选中态用类别色 + 标签加粗，未选中 `.white.opacity(0.4)`）。清单一行 = 勾选框（点击写回 `EKReminder.isCompleted`）+ 标题 + 到期时间（**有才显示**，过期红 + 「已过期」标）+ 所属列表名；已完成项排最后、置灰 + 删除线。**折叠态 = 图标 + 今日的 `已办/总量`**（自带 60s `TimelineView`，宿主不起定时器）。<br>**2026-09-28 用户改版**：三环从「顶部横排 + 下方清单」改为「**左侧竖排 + 右侧清单**」（「三个圈不要在最上面，占用可视区域太大的，放在左侧」），左列定宽 120 |
| 增删 | **可增删（写的是系统「提醒」里的真数据）**：① **新增** = 列表顶部 `+` 展开一行内联输入（`TextField` 标题 + 今天 / 明天 / 无日期三选一，**不引入 `DatePicker`**）→ 回车或「添加」建 `EKReminder`（标题 + 可选 `dueDateComponents`）写进 `defaultCalendarForNewReminders()`（取不到时兜到第一个可用列表）→ 重取；② **删除** = 每行 hover 出现的垃圾桶 → **确认对话框**（明说「会同时删除系统提醒中的该条」）→ `store.remove(reminder, commit: true)` → 重取。两者失败都在列表上方回显**一行**提示（`module.todos.writeFailed`，细节进日志），**不静默、不崩、不新增权限请求**；增删只重取数据，**当前尺度筛选保持不变** |
| 分类口径 | **今日** = ① 到期在今天 ∪ ② 已过期（到期 < 今天 00:00）且未完成 ∪ ③ 今天完成；**本周** = 到期落在 `dateInterval(of: .weekOfYear, for: now)` 内 ∪ 今日（**刻意重叠**：本周是更大窗口，今日 ⊆ 本周 ⊆ 所有）；**所有** = 全集。**无到期时间的待办只进「所有」**，不进今日 / 本周（单列的硬规则） |
| 已办/总量 | 分子分母**同源**：该类别的成员条数 = 总量，其中已完成的条数 = 已办（不做「应办」的另一套口径）。**已完成只取最近 7 天**——窗口理由与替代方案见 13 号文档 D-21 |
| 权限 | **提醒（系统 TCC）**。**不在模块初始化 / 视图出现时请求**（沿用「每次安装最多问一次 / 不打扰」策略）：未授权时展开面板显示一句说明 + 「请求访问提醒」（**点击才** `requestFullAccessToReminders()`）+ 「打开系统设置」（`x-apple.systempreferences:…?Privacy_Reminders`）两颗按钮。**增删不新增权限**：未授权时新增 / 删除入口都不渲染 |
| 配置 | **第一版不做配置**（`config: nil`，见 [14](14-module-manifests.md) 的 todos 行） |
| 测试 | `TodoBucketing` 是纯函数（注入 `Calendar` + `now`）：分类与计数、`0/0` 边界、周区间随 `firstWeekday`、自然日半开区间边界、manifest 契约、本地化 key 可解析。**增删的校验与构造同样是纯函数**（`TodoComposer` / `TodoRingLayout`）：标题去空白后为空 → 拒绝、今天 / 明天 → 当天 00:00 的年月日组件（不带时分 = 全天口径）、无日期 → nil、默认列表为 nil 的兜底、三环直径随可用高度收缩 |
| 工作量 | 低～中（1～2 天；**已落地**，P1 批次 T5） |

---

## 6. 路线图映射

| 阶段 | 内容 |
|---|---|
| **P0** | 不变（基座落地、改名、CI、合规）。**E1 已完成**：Metal Toolchain 已安装 |
| **P1** | 不变（内核与模块协议）+ 确定模块化边界（§8.2） |
| **P2a**（接管，约 2 周） | 把已有功能按模块协议包装：stats、日历、媒体、Shelf、计时器、剪贴板、天气、HUD；并修三处缺陷（歌词磁盘缓存、计时器持久化 + 通知、剪贴板电源优化） |
| **P2b**（新增，约 1.5～2 周） | 农历 → 进度 → Shortcuts 上岛 → Launcher → **终端走 Ghostty（最后）**（按成本从低到高；终端优先级最低） |
| **P2c**（通知，约 1 周） | 先探针（0.5 天）验证 macOS 27 上数据库可读；通过则完整实现，不通过则转 AX 方案或推迟 |
| **P3** | 不变（配置驱动 UI、槽位拖拽、主题令牌、多屏策略、双语） |
| **P4** | 不变，但改造量增加：上游扩展系统只有内容推送，插件层要新建 |

**验收**：连续使用 7 天不掉帧、不崩、内存 <150MB；折叠态 CPU <1%。

---

## 7. 本文引出的必办项

| 项 | 说明 | 去向 |
|---|---|---|
| 🔴 三个 vendored 二进制无 LICENSE | `Frameworks/MediaRemoteAdapter.framework` + `mediaremote-adapter/` 下重复的同一份 + `Contents/Helpers/NowPlayingTestClient`；脚本头声明 BSD-3-Clause 但二进制目录无许可文件 | 已登记 [03-license-matrix.md](03-license-matrix.md)，P0 补 |
| 🔴 `NowPlayingTestClient` 是 arm64 only | 与 framework 三架构不一致 | P0 决定去留 |
| `open-meteo` SPM 死依赖 | 声明了但未链接、零 import | P0 删除（唯一一处删除，无接线牵连） |
| ATS 全局关闭 | `NSAllowsArbitraryLoads = true` | P1 决定（§8.4） |
| 死代码 / 空文件 | `utils/SMC.swift` 风扇控制、`LockScreenDynamicIslandReplica.swift`（空壳）、`ColorPickerManager_Fixed.swift` | P2 清理 |
| 5 个 `branch: main` 依赖 | 构建不可复现 | P0-4 |
| `NSLocalNetworkUsageDescription` 缺失 | LocalSend 实际需要 | P2 补 |
| 私有 API 台账 | §3.1 的表要走查成降级路径 + `docs/` 台账（含新增的通知数据库） | P1 建立 |
| 三处实现缺陷 | 歌词磁盘缓存、计时器持久化 + 到点通知、剪贴板电源优化 | P2a |
| **通知上岛的可行性探针** | 完全磁盘访问下只读通知数据库并打印 5 条记录 | P2c 第一步 |
| **Ghostty 启动参数实测** | 确认 `--working-directory` 等参数的可用性 | P2b 第一步 |

---

## 8. 结论与待决项

### 8.1 已确认（2026-09-27 拍板）

| 项 | 结论 |
|---|---|
| **通知上岛的能力边界** | ✅ **接受**："能显示通知、能点击打开 App"即可，不要求关闭/回复。因此主方案（只读通知库 + `NSWorkspace` 打开 App）成立，AX 仅作降级 |
| **模块化边界** | ✅ **接受**：接管 10 个（nowplaying、lyrics、stats、calendar、shelf、timer、clipboard、controls、weather、mirror）+ 新增 5 个模块（launcher、lunar、progress、shortcuts、notifications）+ 终端配置；其余（HUD、取色器、下载监控、笔记、隐私指示灯、空闲动画、AI…）**保持上游原样**，不追求 100% 模块化。**2026-09-28 增补**：新增模块再添 `todos`（待办，§5.7，第 6 个新增模块），它是当前折叠态中央槽位的默认内容；`progress` 保留代码但 `defaultEnabled` 改 `false`（§5.3） |
| **"不需要的上游功能"如何落地** | ✅ **用上游已有开关的默认值**：首启时把 `enableScreenAssistant` 等开关写成 `false`（在 `Kernel/ConfigStore` 初始化时写入，**不改上游源码**）。比从界面移除便宜得多，也避免了删除接线 |
| **终端形态** | ✅ **走外部 App（Ghostty）**，`mode` 默认 `external`；内嵌 SwiftTerm 代码保留但不作为目标形态。**优先级最低，放 P2b 最后** |
| ~~Metal Toolchain~~ | ✅ **已安装**；基线构建已跑通（`BUILD SUCCEEDED`，产物 116MB） |

> 一处措辞澄清：本文所说的"**上游**"= 我们 fork 的基座 **Atoll**（以及将来引进代码的第三方项目），不是泛指某个 AI 服务。文中"上游有 / 上游没有"都是指 Atoll 里有没有。

### 8.2 ATS 全局关闭要不要收窄（待定）

上游 `NSAllowsArbitraryLoads = true` 全局关闭 HTTPS 保护。**建议维持现状**，但在 P1 建一份"对外域名清单"（lrclib.net、music.163.com、open-meteo…），为将来到期收窄留依据。

### 8.3 Bundle ID 与项目命名（域名根已定，名字待定论）

**✅ 已定（2026-09-27）**：中文名 **壶中天**（取"壶中天地"），英文名 **Gourd**，Bundle ID **`com.cmeng.gourd`**（Debug：`com.cmeng.gourd.dev`），内置模块 id 前缀 **`com.cmeng.gourd.`**。命名依据与撞名排查过程见本节下方（保留作为决策记录）。

**最终的命名意象**：**壶中天地**——一个小容器里装下一整个天地，与产品同构（屏幕顶部那个小口展开成整块工作台）；"壶"在中国神话里又是海上仙山"方壶"，与基座 Atoll（环礁）同属海洋意象，中西两套比喻在"海"上接得住。典出《后汉书·方术传》费长房入壶（壶中有玉堂严丽），李白"壶中别有日月天"、王维"坐知千里外，跳向一壶中"、刘禹锡"天地一壶中"。它还是中国园林美学的核心概念（在极小空间里造一个完整世界）。

**Bundle ID 是什么**：应用的全局唯一标识符（`CFBundleIdentifier`），macOS 用它区分应用。对我们特别重要的几处：**UserDefaults 的存储域**（改了 = 设置全部重来）、**Keychain 项归属**、**TCC 权限记录**（改了 = 系统重新询问权限）、**Sparkle 更新识别**、**签名与公证**、第三方扩展靠它查找宿主。这个名字**定下后基本不该再改**（改了等于换了个新 App）。

**已定：反写域名根 = `com.cmeng`**（2026-09-27）。因此 Release 为 `com.cmeng.<应用名>`，Debug 加 `.dev`。注意：**应用名后缀大小写任选但必须全程一致**（`com.cmeng.gourd` 与 `com.cmeng.Lagoon` 都合法，但不要混用）。

**命名评估（2026-09-27，含撞名排查）**

结论先说：**Lagoon 的意境成立，但有两个实际缺陷；赛道内更贴且干净的首选是 Cove。**

| 候选 | 意境／命中哪条轴 | 撞名排查结果 | 结论 |
|---|---|---|---|
| **Lagoon**（潟湖） | 与基座 Atoll 构成地貌家族：**环礁围出潟湖**，是"基座围出的自留地"，气质安静、自用——与 README 现有注解一致 | ⚠️ 与知名开源平台 **`uselagoon/lagoon`**（Apache-2.0，Docker/K8s 交付平台，已被 Mirantis 收购）**撞名**；另有 Blue Lagoon（冰岛温泉/鸡尾酒）等泛用联想 → **GitHub 搜索性差**。刘海赛道内无人使用 | 叙事最优，搜索性最差 |
| **Cove**（三面环陆的**凹形**海湾） | **形状即 notch**：cove 就是"岸线凹进去的那块"；同时是"隐蔽的静水小湾"，气质贴合；与 Atoll 同属海岸地貌，家族叙事不断 | ✅ **刘海赛道内确认无人使用**（两轮定向检索）。macOS 上有两个**不同类**同名应用：数据库客户端、工作区会话管理器 → 非同类，但不完全干净 | **推荐首选** |
| ~~Islet~~（小岛） | 岛链最小单元，与 Atoll 是母子关系 | ❌ **已是一个 macOS 刘海应用**（付费，功能高度重合：媒体控制、HUD、文件托盘、日历天气、13 项可开关） | 出局（同类占用） |
| ~~Perch~~（栖木/高处停歇） | 位置感最好："栖在屏幕顶端" | ❌ **已是同类应用**（Product Hunt：Perch — Dynamic Island for Mac Notch，功能重合） | 出局（同类占用） |
| ~~Alcove~~（壁龛） | 凹室 + 收纳 | ❌ 赛道头部付费应用（已被广泛使用） | 出局 |
| ~~Tessera~~（马赛克小片） | 贴"模块拼装"的产品本质 | ❌ macOS 上多个同名应用，含一个**菜单栏窗口管理器**（其命名理由同样是"马赛克小片"） | 出局 |
| ~~Atrium~~（被围合的内部空间） | 与 Atoll 围合潟湖的结构同构 | ❌ 已有 macOS 应用 `atrium`（AI coding agent 工作区管理器）等多个同名产品 | 出局 |

**行业观察（影响命名策略）**：这个赛道的描述性名字**已经饱和**——`NotchNook / NotchFlow / NotchNest / NotchPad / NotchBook / Notchly / NotchIA / NotchBox / DynamicLake / DynamicHorizon / DynamicNotch / Alcove / SuperIsland / Vibe Island / BooBar / Tuneful / MediaMate / Folder Hub / Dockside / QuakeNotch / TopNotch…`。因此**不要再取 `Notch*` / `Dynamic*` / `*Island` 形式的名字**（既撞车又同质）。另外：`Islet`、`Perch`、`Tessera`、`Atrium` 这些"好词"在 macOS 圈基本都被用掉了，再往下找边际收益递减。

**最终选择：`Gourd`（壶中天地）**。落选者与原因：`Cove`（次选，形状好但 macOS 上有两个不同类同名 app）、`Lagoon`（叙事优雅，但与 `uselagoon/lagoon` 撞名、搜索性差）、`Tarn`/`Mere`（未做撞名排查）、以及所有被同类占用的词（Islet / Perch / Eave / Alcove / Tessera / Atrium）。

#### 命名第二轮：从中国古诗词取意象（2026-09-27）

思路：不再找"描述性地理词"（已被扫光），改从古诗词里取**与产品同构的意象**，再转英文。

| 诗词意象 | 出处 | 为什么贴产品 | 英文转写 | 撞名状态 |
|---|---|---|---|---|
| **壶中天地** | 《后汉书·方术传》费长房见卖药翁跳入壶中，壶内有玉堂严丽；李白"壶中别有日月天"、王维"坐知千里外，跳向一壶中"、刘禹锡"天地一壶中" | **与产品同构**：一个小容器里装下完整天地 = 屏幕顶部那个小口展开成你的一整个工作台；"跳向一壶中"就是"点开刘海"。且它本是中国**园林美学**核心（在极小空间造完整世界） | **Gourd** | ✅ 检索无撞名（同类与其他类均无） |
| 茅檐低小 | 辛弃疾《清平乐·村居》；温庭筠"栖息消心象，檐楹溢艳阳" | 位置最准（顶部伸出的边沿） | Eave | ❌ **已被同类占用**：闭源免费的 macOS 刘海应用 Eave，功能几乎与我们重合（Now Playing / HUD / 文件架 + AirDrop / 剪贴板 / 番茄钟 / Claude Code 监控 / 外接屏 DDC） |
| 竹坞无尘水槛清 | 李商隐《宿骆氏亭寄怀崔雍崔崔衮》；毛滂"藏花小坞" | 凹入 + 泊船收纳，与 Atoll 海洋家族一致 | Berth | ⚠️ 已有同名 macOS 工具（开发者端口管理，Apache-2.0），非同类 |
| 半亩方塘一鉴开 | 朱熹《观书有感》 | 小而方、能映照天光云影 | Tarn / Mere | ❓ 未查 |
| 孤屿媚中川 | 谢灵运《登江中孤屿》 | 与 Atoll 同族（礁 / 岛） | Islet | ❌ 已被同类占用（付费刘海应用） |
| 山有小口，仿佛若有光 | 陶渊明《桃花源记》 | **形状最准**：一个小口是唯一入口，进去是另一个世界（"豁然开朗"） | Keyhole | ⚠️ keyhole 是常用词，且 Logitech 有同名工具 |
| 芥子纳须弥 | 《维摩诘经》；李渔的园子即名"芥子园" | 极小容极大 | Mustard / Kernel | ❌ 撞名严重（Mustard 品牌 / Kernel 是操作系统术语） |
| 栖木高处（Perch） | — | 顶部停靠 | Perch | ❌ 已被同类占用（Dynamic Island for Mac） |

**结论：首选 `Gourd`（壶中天地）**。三条理由：① **同构度最高**——"小壶装天地"就是"小缺口展开成工作台"；② **意象链没断**——"壶"在中国神话里本就是**海上仙山"方壶"**（《列子·汤问》渤海之东五山：岱舆、员峤、方壶、瀛洲、蓬莱），与基座 Atoll（环礁）同属海洋神话，中西方在"海"这个意象上接得上；③ **英文侧干净**——检索无撞名，短、独特、好记，图标也好做（葫芦，在一片"刘海/岛"图标里辨识度极高）。

**中文名不必直译**：可用 **壶中天** / **方壶**（更雅），或就叫 **葫芦**（更亲切）。App 名与 Bundle ID 用 `Gourd` → `com.cmeng.gourd`。

**这个赛道的现实（影响命名与定位）**：同类应用已查到的有 —— Alcove、NotchNook、Boring Notch、NotchDrop、DynamicNotch、VibeNotch、NotchPop、NotchIA、Notchly、MewNotch、uNotch、DynamicHorizon、NotchNest、LinkNotch、NotchMac、Islet、Perch、**Eave**、SuperIsland、BooBar、QuakeNotch、Dockside、Folder Hub、Tuneful、MediaMate…。其中 **Eave / NotchIA / Notchly / VibeNotch 已经在做 AI agent 监控（Claude Code / Codex）**，多数商业应用都已包含文件架、剪贴板、HUD、日历。**结论：功能上没有空位，我们的差异只能落在"模块化 + 完全可定制 + 插件架构"上**（这也反证了砍掉 AI agent 面板是对的）。

**改名执行情况（2026-09-27，已完成）**：趁"没有一行代码"的窗口一次性改完，动作清单如下（后续引用以此为准）：

| 项 | 值 |
|---|---|
| 中文名 / 英文名 | 壶中天 / **Gourd** |
| Bundle ID | **`com.cmeng.gourd`**（Debug `com.cmeng.gourd.dev`） |
| 内置模块 id 前缀 | **`com.cmeng.gourd.`**（例：`com.cmeng.gourd.nowplaying`） |
| 协议与类型 | `GourdModule` / `GourdEvent` / `GourdPluginXPCProtocol`；插件 JS API 命名空间 `gourd.*`；插件包后缀 `.gourdplugin` |
| 配置目录 | `~/Library/Application Support/Gourd/config.json` |
| Keychain service | `com.cmeng.gourd.secrets` |
| 修改标注 | `// Modified for Gourd (YYYY-MM-DD)` |
| 文档 | `docs/` 全部 + README + NOTICE 已同步 |

**改名已执行（2026-09-27）**：项目目录已改为 `~/workspace/github/gourd`；agent-memory 项目目录同步迁移为 `gourd-1c47bd2beca69533`（键 = `sha256(绝对路径)` 前 16 位；旧目录 `lagoon-4a28976c8efbc2b5` 保留备份）。教训：不要在会话进行中改名会话所在目录（shell cwd 指向已删除路径 → `spawn /bin/zsh ENOENT`）——先建软链或换新会话再改。
