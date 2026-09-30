# 架构方案

## 1. 目标与非目标

**目标**
- 以刘海为唯一入口的"命令面板"：媒体、歌词、系统状态、文件暂存、快捷启动、快捷控制、剪贴板、AI 协作。
- **一切皆模块**：每个功能可独立开关、独立配置、独立崩溃隔离。
- **可扩展**：第三方能用 JSON 描述符 + 受限 API 写扩展，不需要改主程序。
- **可持续**：能跟随上游 Atoll 演进，而不是分叉即死。

**非目标（明说不做，避免范围蔓延）**
- 不做窗口管理（交给 AltTab / DockDoor 那类专门项目）。
- 不做通用启动器（不做 Raycast 替代品；只做"刘海里的快捷启动"，复杂搜索交给 Spotlight / 现成启动器）。
- 不碰需要特权或私有 API 才能做的菜单栏图标隐藏（Ice 那类用 SkyLight/CGS 私有 API，风险留给他们）。
- 不做商业化与 App Store 上架（见 ADR-0001）。

## 2. 分层总览

```
┌─────────────────────────────────────────────────────────────┐
│  L4 分发     Sparkle appcast · 公证 DMG · Homebrew cask      │
├─────────────────────────────────────────────────────────────┤
│  L3 插件层   PluginHost (XPC)  ── descriptor.json 校验       │
│              PluginSDK (Swift)  ·  JS 沙箱宿主（第二阶段）    │
├─────────────────────────────────────────────────────────────┤
│  L2 内置模块 NowPlaying · Lyrics · Shelf · Stats · Calendar   │
│              Launcher · Controls · Clipboard · Timer · AI     │
├─────────────────────────────────────────────────────────────┤
│  L1 模块运行时 ModuleRegistry · ConfigStore · PermissionCenter│
│              EventBus · ThemeCenter                          │
├─────────────────────────────────────────────────────────────┤
│  L0 内核     NotchWindow · NotchStateMachine · 多屏/刘海几何   │
└─────────────────────────────────────────────────────────────┘
```

**依赖方向严格单向向下**：模块可以订阅 L1 的事件、读配置，但不得直接操作 NotchWindow；内核不知道任何具体模块的存在。

## 3. L0 内核

| 组件 | 职责 | 实现要点 |
|---|---|---|
| `NotchWindow` | 承载折叠/展开面板的窗口 | `NSPanel` 子类，`.nonactivatingPanel`（不抢焦点）、`.statusBar` 级别、`isMovableByWindowBackground = false`；内容视图顶部贴合刘海下沿 |
| `NotchGeometry` | 计算刘海矩形与安全区 | `NSScreen.safeAreaInsets` + `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`；`NSApplication.didChangeScreenParametersNotification` 监听屏变；**无刘海机型回退为屏幕顶部居中的 floating 胶囊** |
| `NotchStateMachine` | 折叠 / 悬停预览 / 展开 / 拖拽 四态 | 显式状态枚举 + 事件驱动，禁止在视图里用布尔量拼状态；动画曲线统一由 ThemeCenter 提供 |
| `EventBus` | 类型化事件总线 | `AsyncStream` 广播；事件契约见下表；订阅者异常不得冒泡到内核 |
| `ConfigStore` | 配置读写与迁移 | `~/Library/Application Support/Gourd/config.json`，带 `schemaVersion` 与迁移函数链；支持导出/导入 |
| `ThemeCenter` | 外观令牌 | 材质（液态玻璃/毛玻璃）、圆角、间距、强调色、动画时长；供模块取令牌而非硬编码 |
| `PermissionCenter` | 权限收敛 | 媒体控制、日历/提醒、文件访问、相机（镜像）、通知、网络（仅出站）；全部集中在设置页一次性说明并请求 |

**事件契约（首批 13 个）**——字段级定义与投递语义见 [07-config-and-events.md](07-config-and-events.md) §3–§4：

```
media.playbackChanged     当前曲目、播放状态、来源 App（不含进度）
media.progressTick        播放进度（tick 类，默认 1s；消费者按下述插值契约推算当前位置）
media.lyricsChanged       逐行歌词与时间轴（整份替换）
power.sourceChanged       电源/电池/充电/热状态
system.metricsTick        CPU/内存/网络/磁盘/GPU/温度（tick 类，默认 1s，带 dtMs）
calendar.upcoming         下一个日程/提醒（含开始前提醒）
focus.modeChanged         专注模式
screen.locked             锁屏（独立事件，非 changed）
screen.unlocked           解锁
display.configurationChanged  屏幕增删改（NotchGeometry 的唯一屏变来源）
notch.phaseChanged        刘海四态转换（替代早期设计的 notch.hover，预加载契约见 07 §4.10）
config.changed            配置变更（不含值）
module.stateChanged       模块状态机变化（降级可见性）
```

## 4. L1 模块运行时

**模块协议**（内置模块与插件模块共用同一份元数据模型）：

> ⚠️ **本节的协议形态已被 [06-module-protocol.md](06-module-protocol.md) §2–§3 取代**（下面只是摘要，字段级定义以 06 为准）：
> 静态元数据从散落的 static 属性收敛为一个可序列化的 `ModuleManifest`；视图改为 `content(for:)` 同步返回 `ModuleContent`（内置给视图、插件给声明式内容描述符）。

```swift
@MainActor
public protocol GourdModule: AnyObject {
    static var manifest: ModuleManifest { get }                 // 静态元数据（可导出为 descriptor.json）
    init(context: ModuleContext)                                // 依赖注入在构造期完成
    func activate() async throws
    func deactivate() async
    func content(for request: ContentRequest) -> ModuleContent  // 同步；内置可返回视图，插件只能返回描述符
    func onEvent(_ event: GourdEvent) async
}
```

**ModuleRegistry 的硬性规则**
1. 模块 `activate` 抛错 → 记录并自动置为禁用，不影响其他模块。
2. 每个模块的视图在主线程外构建、主线程挂载；单模块视图渲染超时（>2s）记警告。
3. 模块不得持有全局单例，依赖通过 `ModuleContext` 注入（便于测试）。
4. 任何模块不得直接创建窗口；需要弹层的走内核提供的 `OverlayHost`。

**配置驱动 UI**：`configSchema` 是 JSON Schema 的受限子集——**13 种 type**（`boolean` / `integer` / `number` / `string` / `enum` / `color` / `hotkey` / `appPicker` / `filePath` / `dateRange` / `duration` / `secret` / `list`，字段级定义见 [06](06-module-protocol.md) §5），设置页据此生成控件。Nook X 那种"左侧图标槽 / 右侧图标槽 + 每个小组件 Free/Pro 开关"的界面，在本项目里就是模块注册表的直接渲染——**没有 Free/Pro，只有开/关**。

## 5. L2 内置模块

> ⚠️ **以下表格是早期的模块规划草案，机制与动作已被 [09-features-and-mechanisms.md](09-features-and-mechanisms.md) 取代**（以 09 为准）：
> 勘察后确认 **Atoll 已实现其中大部分功能**，P2 的主体是"接管 + 包装"而非从零写；且范围已冻结（ADR-0011/0012）——
> 接管 10 个（nowplaying / lyrics / stats / calendar / shelf / timer / clipboard / controls / weather / mirror）、
> **新增 5 个**（launcher / lunar / progress / shortcuts / notifications）+ 终端外部化，**AI 对话不投入**、照片与番茄钟不做。

| 模块 | 职责 | 数据源 | 代码来源 / 许可 |
|---|---|---|---|
| `nowplaying` | 媒体控制 + 进度 + 可视化 | 播放器适配器（Apple Music/Spotify/Cider 等） | 参照 boring.notch 的 `MediaControllers`（GPL） |
| `lyrics` | 逐字歌词、简繁转换 | LRCLIB 公共 API + 本地 LRC 缓存 | 参照 lyrimuse（GPL）/ LyricsX（MPL）的同步算法 |
| `shelf` | 文件暂存、拖入拖出、AirDrop | **上游实际用 `NSItemProvider`**（不是 `NSFilePromiseProvider`）+ `NSDraggingSource` + `NSSharingService` | 上游已实现；参照 NotchDrop（MIT）/ OpenYoink（MIT） |
| `stats` | CPU/GPU/内存/网络/磁盘/温度 | `host_statistics`、IOKit、`getifaddrs` 增量 | 参照 exelban/stats（MIT）/ NetSpeedMonitor（MIT） |
| `calendar` | 下一个日程 + 农历 + 今天待办 | EventKit + 内置万年历算法 | LunarBar（MIT）思路；农历算法自实现 |
| `launcher` | 快捷启动（常用 App / 最近使用 / Shortcuts） | Launch Services + `NSWorkspace` | 自建；Shortcuts 走 `shortcuts://` |
| `controls` | 快捷开关（音量、亮度、勿扰、蓝牙、防休眠） | `NSAppleScript`/IOKit/CoreAudio | 参照 OnlySwitch（MIT）/ KeepingYouAwake（MIT） |
| `clipboard` | 剪贴板历史 + 固定片段 | `NSPasteboard` 轮询 | 参照 Maccy（MIT） |
| `timer` | 番茄钟 / 倒计时 / 正计时 | 本地计时器 + 通知 | 自建（boring.notch 有用例可对照） |
| `ai` | AI 对话与快捷动作 | 上游已有 `ScreenAssistantManager`（5 家 provider，悬浮面板 + ⌘⇧A） | **不投入**：代码保留、首启关闭开关（[09](09-features-and-mechanisms.md) §2.F） |

> 逐功能的机制、上游现状与动作以 [09-features-and-mechanisms.md](09-features-and-mechanisms.md) 为准；对标 Nook X 的功能映射见 [05-feature-map.md](05-feature-map.md)。

## 6. L3 插件层

**描述符**（`descriptor.json`，由宿主持有并校验）：

> ⚠️ **字段级定义以 [06-module-protocol.md](06-module-protocol.md) §2 为准**（含 `manifestVersion` / `kind` / `entry{runtime,main}` / `limits` / `x-*` 等本文早期草案没有的字段）。摘要：

```json
{
  "manifestVersion": 1,
  "id": "com.example.pomodoro",
  "name": { "en": "Pomodoro", "zh-Hans": "番茄钟" },
  "version": "1.0.0",
  "apiVersion": "1.0",
  "kind": "js",
  "entry": { "runtime": "js", "main": "main.js" },
  "surfaces": ["compact", "expanded"],
  "permissions": ["notifications", "timers", "storage"],
  "config": { "type": "object", "properties": { "focusMinutes": { "type": "integer", "default": 25, "minimum": 5 } } }
}
```

**校验与授权（缺一不可）**
1. `ExtensionDescriptorValidator` 类职责：字段完整性、`id` 反域名、语义化版本、`apiVersion` 必须在宿主支持区间。
2. 权限白名单：只暴露 `notifications` / `timers` / `storage` / `clipboard-read` / `network:<host>` 这类能力，默认不给网络与文件系统。
3. `apiVersion` 兼容策略：宿主维护 shim 层，主版本不匹配直接拒绝加载并给出升级提示。
4. 失败隔离：插件运行在独立进程，宿主看门狗超时（默认 5s）即重启该插件或禁用，**不重启主程序**。

**两种宿主的取舍**

| | XPC（Swift 插件） | JS 沙箱（第二阶段） |
|---|---|---|
| 门槛 | 高（要写 Swift + 打包） | 低（一个 JS 包） |
| 能力 | 接近内置模块 | 受限 API 子集 |
| 安全 | 进程隔离 + 签名校验 | JavaScriptCore 沙箱 + 无网络默认 + 超时内存限制 |
| 适用 | 官方扩展 / 深度集成 | 社区小工具（番茄钟、比分、状态灯） |

## 7. 定制化与外观

- **布局**：折叠态是"左侧图标槽 + 右侧图标槽"（Nook X 截图里的形态），槽位由启用模块的 `surfaces` 决定，可拖拽排序，可隐藏。
- **形态**：胶囊 / 标准 / 悬浮（无刘海机型）；展开方向遵循系统语言（与 iOS 灵动岛一致）。
- **材质**：液态玻璃（macOS 26+）与毛玻璃两套令牌，低电量或低功耗模式自动降级为纯色。
- **动画预算**：折叠态常驻动画 CPU 占用目标 <1%，展开动画 60fps；每个模块的动画必须在"低功耗模式"下可关闭（借鉴 SuperIsland 的电源模式设计思路，代码不引用）。
- **本地化**：zh-Hans 为主 + en；所有文案走 Localizable，禁止硬编码。

## 8. 质量、性能与分发

- **CI**：GitHub Actions 三件套——构建（macOS runner + Xcode）、单元测试、`swift-format`/编译告警检查。可参考 boring.notch 的 workflow 结构。
- **测试重点**：内核几何与状态机（纯逻辑，可单测）、配置迁移、插件描述符校验、歌词时间轴解析。
- **性能基线**：空闲内存占用 <150MB，折叠态 CPU <1%，展开时无明显掉帧；每次 PR 记录基线。
- **分发**：Sparkle appcast（自建 appcast 仓库或 GitHub Release 附带）、Developer ID 公证（需要 99 美元/年开发者账号）、Homebrew cask。
- **许可证合规**：每次引入上游代码，在 `NOTICE` 登记来源与许可；发布时随二进制提供源码归档。

## 9. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| Atoll 处于 alpha/beta，升级可能引入回归 | 稳定性 | 锁一个可用 tag 作为基线，上游升级在独立分支验证后再合 |
| 上游分叉漂移（Atoll 仍在快速开发） | 合并成本 | 只 fork 基座，其余做依赖/目录引进；每季度评估一次上游变更 |
| 多屏与合盖（clamshell）场景 | 用户体验 | 明确"内置屏优先"策略 + 设置项；在 clamshell 下默认关闭虚拟刘海（这是 boring.notch 至今仍报 issue 的地方） |
| 私有 API 诱惑（媒体控制等） | 上架风险（本项目不分发到商店，风险降低） | 记录每处私有 API 用途与降级路径，走适配器模式隔离 |
| 插件生态做起来后失控 | 维护成本 | `apiVersion` 与权限从第一天就版本化；插件不做向后兼容承诺，只保证宿主不崩 |
| 单人维护精力 | 可持续性 | 模块之间零耦合，任何模块可以停下不管；优先做自己每天用的五个模块 |

## 10. 术语

> 2026-09-30 由 README 移入（[24](24-release-freeze.md) §做法 机制一：README 重写后按同类项目的骨架收窄，术语与目录约定属工程口径，归到这里）。内容与迁移前的 README 逐字一致。

| 词 | 指什么 |
|---|---|
| **上游 / upstream** | 我们 fork 的基座 **Atoll**（`Ebullioscopic/Atoll`），以及将来引进代码的第三方开源项目。文档里"上游有 / 上游没有"都是这个意思，不指任何云服务 |
| **基座** | 被 fork 的应用工程本身（Atoll） |
| **岛 / 刘海面板** | 壶中天自己的浮动面板窗口（折叠态=compact，展开态=expanded，另有 lockscreen 锁屏面） |
| **模块 / module** | 一个可独立开关、独立配置、独立崩溃隔离的功能单元（内置或插件，共用同一份 manifest 模型，见 [docs/06](06-module-protocol.md)） |

## 11. 目录约定

> 同上，2026-09-30 由 README 移入；目录树照搬，另加两处现状注记：`docs/` 下的 `guide/`（用户手册）与 `tools/` 的打包脚本。

```
~/workspace/github/
├── Atoll/                 ← 基座（fork 源，已拉取，含完整历史）
├── boring.notch/          ← 功能对照实现（GPL，可合并）
├── NotchDrop/ OpenYoink/ DynamicNotchKit/ ...   ← 功能来源（MIT/Apache/MPL）
└── gourd/                 ← 本项目仓库（应用名 壶中天 / Gourd；目录已于 2026-09-27 由 lagoon 改名）
    ├── DynamicIsland.xcodeproj/   ← 应用工程（Bundle ID com.cmeng.gourd；上游文件名保留不改）
    ├── docs/              ← 决策、架构、路线图、许可证矩阵、功能映射、P0 执行方案
    │                             （用户手册在 docs/guide/，发布自检在 docs/25）
    ├── tools/             ← 本仓库自身的工具：上游同步、校验与打包脚本
    ├── scripts/           ← 上游自带的构建辅助 ruby 脚本（随基线引入，不改）
    ├── upstreams.tsv      ← 机器可读的上游清单（用途 + 许可 + 使用方式）
    ├── NOTICE             ← 上游署名（GPL 义务之一）
    └── LICENSE            ← GPL-3.0
```
