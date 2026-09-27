# 配置模型与事件契约（字段级设计）

本文定义 L1 的两个基础设施：**ConfigStore**（配置怎么存、怎么迁移、怎么不丢）与 **EventBus**（事件长什么样、怎么投、丢了怎么办）。两者是模块协议（[06-module-protocol.md](06-module-protocol.md)）的运行底座。

上位文档：[01-architecture.md](01-architecture.md) §3（`ConfigStore` / `EventBus` / 事件契约首批）。术语沿用 06 号文档：`Surface` / `Slot` / `NotchPhase` / `Capability` / `ContentDescriptor`。

---

# 第一部分：配置模型

## 1. ConfigStore

### 1.1 存储位置与形态

| 项 | 值 |
|---|---|
| 主文件 | `~/Library/Application Support/Gourd/config.json` |
| 备份 | `config.json.bak`（保留 1 份，每次成功写入前滚动） |
| 损坏现场 | `config.corrupt-<yyyyMMdd-HHmmss>.json`（解析失败时改名保留，不删） |
| 密钥 | **不进配置文件**，走 Keychain（§1.5） |
| 写入 | 原子：写 `config.json.tmp` → `fsync` → `rename` → 滚动 `.bak` |
| 编码 | UTF-8 无 BOM，2 空格缩进，key 按字典序（便于 git diff / 人工比对） |

**为什么用单文件 JSON 而不是 `UserDefaults` 或 SQLite**：架构 §3 已定 JSON + `schemaVersion` + 迁移链。补充理由：需要**导出/导入**（P3 验收标准"导出配置能在另一台机器导入还原"）、需要**迁移链**（`UserDefaults` 无法表达顺序迁移）、需要**人工可读**（自用项目，出问题要能直接看）。

### 1.2 顶层结构（字段级）

```json
{
  "schemaVersion": 3,
  "createdWith": "0.1.0",
  "updatedAt": "2026-09-27T09:57:12.345+08:00",
  "hostState": { "epoch": 7, "lastLaunchAt": "2026-09-27T09:50:00.000+08:00" },

  "general":  { "language": "auto", "launchAtLogin": true, "lowPowerMode": "auto", "diagnostics": false },
  "display":  { "strategy": "builtinFirst", "preferredScreenID": null, "virtualNotchOnClamshell": false },
  "layout": {
    "compact":  { "left": ["com.cmeng.gourd.stats"], "right": ["com.cmeng.gourd.timer"], "center": ["com.cmeng.gourd.nowplaying"],
                  "maxPerSide": 3 },
    "expanded": { "tabs": ["com.cmeng.gourd.nowplaying", "com.cmeng.gourd.calendar"], "defaultTab": null }
  },
  "theme":    { "material": "liquidGlass", "cornerRadius": 22, "accent": "accent", "motion": "normal",
                "degradeInLowPower": true },
  "modules": {
    "com.cmeng.gourd.nowplaying": { "enabled": true, "config": { "pollIntervalMs": 500 } },
    "com.cmeng.gourd.ai":         { "enabled": false,
                               "config": { "provider": "openai", "model": "gpt-4o-mini" },
                               "secrets": { "apiKey": "keychain:com.cmeng.gourd.ai/apiKey" } }
  },
  "plugins": {
    "com.example.pomodoro": { "enabled": true, "version": "1.0.0", "installedAt": "2026-09-27T10:00:00+08:00",
                              "granted": ["timers", "storage", "notifications"],
                              "grantHistory": [ { "capability": "notifications", "at": "2026-09-27T10:02:00+08:00" } ] }
  },
  "analytics": { "crashes": 0, "lastCrashAt": null, "moduleFailures": { "com.cmeng.gourd.stats": 2 } }
}
```

### 1.3 顶层字段表

| 字段 | 类型 | 默认 | 约束 |
|---|---|---|---|
| `schemaVersion` | int | — | 必填。**单调递增**。见 §1.4 处理规则 |
| `createdWith` | semver | — | 首次创建时的宿主版本，诊断用，不参与判定 |
| `updatedAt` | ISO8601 | — | 每次写入更新；用于"配置被外部改动"的检测（与 `mtime` 交叉验证） |
| `hostState.epoch` | int | 0 | 宿主会话号，每次启动 +1；用于事件时效判定（§2.1）与崩溃自愈计数 |
| `general.language` | enum | `auto` | `auto` / `zh-Hans` / `en`。`auto` 跟随系统 |
| `general.launchAtLogin` | bool | false | 由 LaunchAtLogin-Modern 落地 |
| `general.lowPowerMode` | enum | `auto` | `auto` / `always` / `never`。影响动画与采样频率（架构 §7） |
| `general.diagnostics` | bool | false | 打开后事件与插件调用写详细日志（上游已有 `extensionDiagnosticsLoggingEnabled`，同义） |
| `display.strategy` | enum | `builtinFirst` | `builtinFirst` / `preferredScreen` / `allScreens`。对应架构 §9 的多屏策略 |
| `display.preferredScreenID` | string? | null | 仅 `strategy == preferredScreen` 时有效；屏幕消失 → 回退 `builtinFirst` 并记日志 |
| `display.virtualNotchOnClamshell` | bool | **false** | 合盖场景默认关闭虚拟刘海（架构 §9 明确点名上游至今有此 issue） |
| `layout.compact.left/right/center` | string[] | `[]` | 模块 id 有序数组；未知 id **保留**（模块被卸载后重装能恢复位置） |
| `layout.compact.maxPerSide` | int | 3 | 1–5（06 号文档 §6.2） |
| `layout.expanded.tabs` | string[] | `[]` | 展开面板 tab 顺序 |
| `layout.expanded.defaultTab` | string? | null | null = 记住上次打开的 tab |
| `theme.*` | — | — | 令牌见 §1.6 |
| `modules.<id>.enabled` | bool | 按 manifest `defaultEnabled` | — |
| `modules.<id>.config` | object | `{}` | **只存显式设置过的值**（06 号文档 §5.4） |
| `modules.<id>.secrets` | object | `{}` | 值恒为 `"keychain:<moduleID>/<key>"` 引用串 |
| `plugins.<id>.*` | — | — | 插件额外有 `granted`（已授权能力）与 `grantHistory`（审计：谁在什么时候被授权） |

**内置与插件分开两个顶层键**（`modules` / `plugins`）的理由：生命周期不同（插件要授权、要版本、要卸载清理），混在一起会让"卸载插件时该删哪些键"变得含糊。

### 1.4 `schemaVersion` 与迁移链

```
读取 → 解析失败? → 尝试 .bak → 仍失败 → 改名保存 → 默认配置启动 + 通知（不静默丢数据）
     ↓
v == 当前 → 直接用
v <  当前 → 顺序执行 migrate[v→v+1] ... 直到当前
v >  当前 → **拒绝启动**，提示"配置由更新版本的壶中天写入"
```

- 迁移函数签名：`(inout JSONObject) throws -> Void`，**纯函数**，不改外部状态、不做 IO。
- 每个迁移必须**幂等**（重跑不出错）且**不依赖网络**。
- 迁移失败 → **不写入**（保持原文件），按"损坏"流程处理。理由：写入半成品比不迁移更糟。
- 迁移完成后的首次写入前，额外存一份 `config.pre-migration-v<N>.json`（一次性，保留 1 份）。
- 单测要求（架构 §8 测试重点）：每个迁移一段 fixture——`v(N)` 输入 JSON + 期望的 `v(N+1)` 输出 JSON，存 `Tests/Fixtures/ConfigMigrations/`。**新增迁移必须同时提交两个 fixture**。

**为什么"更高版本拒绝启动"**：配置是用户唯一不可再生的资产。旧版程序读新版配置时，未知字段虽然会被保留（§1.7），但语义变化的字段会读错——宁可让用户看到明确提示，也不要把配置改坏。

### 1.5 密钥（secret）处理

| 环节 | 行为 |
|---|---|
| 存储 | Keychain，`kSecClass = genericPassword`，`service = "com.cmeng.gourd.secrets"`，`account = "<moduleID>/<key>"` |
| 配置文件中 | 只存引用串 `"keychain:com.cmeng.gourd.ai/apiKey"`，**永不存值** |
| 读取 | `SecretHandle.get(key) -> String?`；Keychain 无该项 → 返回 nil 并标记该配置项"未设置" |
| 导出 | 引用的值**替换为 `null`**，并附 `"_secretsOmitted": ["com.cmeng.gourd.ai/apiKey"]` 清单 |
| 导入 | 遇到 `null` 的 secret → 保持未设置，设置页高亮提示"请重新填写" |
| 写入节流 | Keychain 写入 ≥ 200ms 间隔（避免设置页拖滑杆时刷爆 Keychain） |

**为什么导出要剔除而不是加密**：加密导出需要用户设密码 + 引入密钥管理，而收益仅是"换个机器不用重填"。自用项目选简单且明确安全的方案：**导出不含密钥，导入后提示重填**。

### 1.6 主题令牌（`theme.*`）

架构 §3 要求"供模块取令牌而非硬编码"。字段：

| 字段 | 类型 | 默认 | 取值 |
|---|---|---|---|
| `material` | enum | `liquidGlass` | `liquidGlass`（macOS 26+）/ `frosted` / `solid`。系统不支持时**自动降级**为 `frosted` 并在设置页标注 |
| `cornerRadius` | number | 22 | 8–40；按屏幕缩放的基准值，模块用 `theme.radius(.panel)` 这类语义取，不直接读数值 |
| `accent` | color | `"accent"` | 同 06 号文档 §5.3 的 color 值形态（`"accent"` 哨兵 = 跟随系统强调色） |
| `motion` | enum | `normal` | `full` / `normal` / `reduced`。`reduced` 关闭常驻动画（架构 §7 动画预算） |
| `degradeInLowPower` | bool | true | 低功耗/低电量时自动把 `material` 降为 `solid` 且 `motion` 降为 `reduced` |

令牌以**语义名**暴露（`ThemeCenter.radius(.panel)` / `.gap(.s)` / `.color(.secondary)`），模块**不得**直接读 `theme.cornerRadius` 数值——否则全局改版时无法统一调整。

### 1.7 前向兼容：未知字段保留

读取时保留所有未知字段，写回时**原样输出**（含未知顶层键、未知模块键、未知配置项）。

- 实现约束：**不能用纯 `Codable` struct 做顶层模型**（会丢未知字段）。顶层用 `JSONValue` 树持有 `raw`，已知键映射为类型化视图；写入时以 `raw` 为基底合并变更。
- 配置项层面同理：模块 config 的未知 key 保留（`x-unknown` 标记仅用于设置页折叠显示）。
- 与 06 号文档 §10.1 的"manifest 未知字段严格拒绝"**不矛盾**：manifest 是安全边界（要严），配置值是用户数据（要宽）。

### 1.8 写入路径与并发

| 项 | 规则 |
|---|---|
| 变更来源 | 设置界面、模块 `config.set`、导入、迁移 |
| 去抖 | 默认 500ms 合并（同类按键连击不产生 500 次写盘） |
| 立即写 | 迁移、导入、退出前（`applicationWillTerminate`）跳过去抖 |
| 写入队列 | 单一串行队列，禁止并发写（否则 `.tmp` 互相踩） |
| 锁 | 写前 `flock(config.json.lock, LOCK_EX)`，跨进程兜底；锁超时 2s → 放弃写入并记错误 |
| 多实例 | 宿主强制单实例（`LSMultipleInstancesProhibited = true` + 启动时检测同 bundle id 进程）；检测到第二个实例 → 提示并退出 |
| 变更通知 | 成功写入后发 `config.changed`（§2.6），**去抖合并到 100ms**，同一 scope 的多次变更合并为一条 |

### 1.9 导入 / 导出

| 项 | 规则 |
|---|---|
| 文件名 | `Gourd-config-v<schemaVersion>-<yyyyMMdd>.json` |
| 导出内容 | 全量（除 secret 值，§1.5）；含 `exportedAt` / `exportedBy`（宿主版本）/ `hostModel`（机型，诊断用） |
| 导入模式 | **默认按 module id 合并**（保留本机未涉及的部分）；另提供"完全替换"选项 |
| 导入前置校验 | manifest 无关；配置侧做 ① JSON 可解析 ② `schemaVersion` ≤ 当前 ③ 所有值过 schema 校验 |
| 导入失败 | 逐条报告失败项，**不部分应用**（要么全成功要么不变） |
| 导入后 | 立即写盘（跳过去抖）+ 发 `config.changed(origin: "import")` |

---

## 2. ConfigHandle（模块视角）

```swift
public protocol ConfigHandle {
    func get<T: Decodable>(_ key: String, as type: T.Type) -> T?
    func set<T: Encodable>(_ key: String, to value: T?)     // nil == 重置为默认（删除该 key）
    func observe<T: Decodable>(_ key: String, as type: T.Type) -> AsyncStream<T>
    func schema() -> ConfigSchema                            // 本模块的 schema，用于自校验/调试
}
```

规则：

1. **作用域自动收窄**：模块拿到的 handle 只能读写 `modules.<自身 id>.config`，传给它的 `key` 会被宿主加前缀。越界的 key（含 `..`、`/`）→ 抛错并记 `violation` 日志。
2. `set(nil)` = 删 key（回到默认），与 06 号文档 §5.4 一致。
3. `observe` 的初值语义：**先发当前值，再发变更**（订阅者无需自己先 `get` 一次）。相同值不重复发（按 `JSONValue` 深度比较）。
4. 值类型错误（文件被手工改坏）→ 读时回落到 default 并记 warning，**不崩、不清空**。

---

## 3. 事件契约

### 3.1 事件信封（线上形态）

```json
{
  "name": "media.playbackChanged",
  "v": 1,
  "seq": 8412,
  "source": "com.cmeng.gourd.nowplaying",
  "ts": "2026-09-27T09:57:12.345+08:00",
  "monotonicNs": 1934425100000,
  "epoch": 7,
  "class": "state",
  "payload": { }
}
```

| 字段 | 类型 | 必填 | 语义 |
|---|---|---|---|
| `name` | string | 是 | `<domain>.<subject><Verb>`，见 §3.2 |
| `v` | int | 是 | **该事件 payload 的版本**。同一 `name` 的 payload 发生破坏性变更时 +1；消费者按 `v` 选解析分支 |
| `seq` | int | 是 | **per-source 单调递增**（从 1 开始）。用于检测丢事件（gap 计数），跨 source 无意义 |
| `source` | string | 是 | 产生者 id：内置模块 → `com.cmeng.gourd.<short>`；插件 → 插件 id；内核 → `kernel` |
| `ts` | ISO8601 | 是 | 墙上时钟。**仅用于展示**，禁止用于计算间隔（用户改时间会出错） |
| `monotonicNs` | int | 是 | `DispatchTime.now().uptimeNanoseconds`。**一切间隔/倒计时/进度插值必须用它** |
| `epoch` | int | 是 | 宿主会话号（= `hostState.epoch`）。订阅者据此丢弃上一次会话的陈旧事件 |
| `class` | enum | 是 | `critical` / `state` / `tick`，决定投递与背压策略（§3.2） |
| `payload` | object | 是 | 事件专属字段，见 §4。大小上限 16KB（超出截断 payload 并记 warning） |

`class` 冗余在信封里而不只在内核表里：插件与外部消费者（未来可能有 CLI/脚本）拿不到内核表，需要自描述。

### 3.2 命名与分级

**命名规则**：`^[a-z][a-zA-Z]*(\.[a-zA-Z][a-zA-Z0-9]*)+$`。domain 固定集合：`media` / `system` / `power` / `calendar` / `focus` / `screen` / `display` / `notch` / `config` / `module` / `plugin` / `ai` / `kernel`。插件自定义事件强制在 `plugin.<pluginID>.<name>` 下（§3.6）。

| class | 判定标准 | 例子 | 缓冲 | 溢出策略 | 合并窗口 |
|---|---|---|---|---|---|
| `critical` | 丢了会造成状态错乱 | `screen.locked` / `power.sourceChanged` / `display.configurationChanged` | 无界（有上限保护 4096） | **不丢**，满则丢弃新事件并记错误（宁可日志报警） | 不合并 |
| `state` | 丢了会显示旧值，下一秒可被纠正 | `media.playbackChanged` / `focus.modeChanged` / `config.changed` | 64 | 丢最旧 | 100ms 末值合并 |
| `tick` | 高频采样，丢了无所谓 | `system.metricsTick` / `media.progressTick` | 1 | 覆盖（只留最新） | 强制合并（默认 1s，可配 100ms–5s） |

**为什么合并窗口对 tick 类是强制而非可选**：这是"折叠态 CPU <1%"（架构 §8 性能基线）的关键机制。1Hz 的指标事件在慢订阅者上会堆积，合并后订阅者每窗口最多处理一次。

### 3.3 投递语义（逐条）

| 项 | 规则 |
|---|---|
| 模型 | broadcast，每个订阅者**独立队列**（慢订阅者不拖累别人） |
| 保序 | **per-source FIFO**；跨 source 无序（明确不承诺全局顺序） |
| 交付 | **at-most-once**。不重放、不补发；错过即错过（订阅者需在 `activate` 里主动 `get` 一次当前状态，而不是等事件补齐） |
| 重入 | 同一订阅者的 `onEvent` **串行、不重入**；不同订阅者并发 |
| 超时 | 单次 `onEvent` > 2s 记 warning；连续 3 次 → 订阅者降级（停投 `tick`，保留 `critical`/`state`），并发 `module.stateChanged` |
| 线程 | 默认投递到 `@MainActor`；声明 `nonisolatedDelivery: true` 的订阅者投到独立串行队列 |
| epoch 过滤 | 投递前丢弃 `epoch != 当前` 的事件（防止宿主重启瞬间的陈旧事件） |
| 自环 | 订阅者收到自己 `source` 的事件**照常投递**（便于"确认写入生效"）；但 `publish` 在自己 `onEvent` 内产生的事件进入**下一帧**投递，防止递归风暴 |
| 风暴保护 | 每个 source 每 tick 最多 `publish` 64 条；超出丢弃并记 warning（含被丢弃的 name 计数） |

### 3.4 EventBus API

```swift
public protocol EventBus: AnyObject, Sendable {
    func publish(_ event: GourdEvent)                                  // 内核/内置模块
    func subscribe(_ names: [EventName], policy: SubscriptionPolicy) -> EventSubscription
}
public protocol EventSubscription: AnyObject, Sendable {
    var stats: SubscriptionStats { get }   // received / dropped / coalesced / timeouts
    func cancel()
}
public struct SubscriptionPolicy: Sendable {
    public var delivery: Delivery              // .mainActor | .serialQueue(label:)
    public var minClass: EventClass            // 重要性下限：只接收 >= 该等级的事件。等级序 tick < state < critical
    public var onOverflow: OverflowBehaviour   // .dropOldest | .coalesce | .crash  // 默认 .dropOldest
    public var bufferSize: Int                 // 默认按 class 给
}
```

- `minClass` 的用法：只关心状态不关心采样 → `.state`（**不接收 `tick`**，省电且省 CPU）；连省电也不在乎 → `.tick` 收全部；只想知道锁屏/电源这类关键变化 → `.critical`。
- 等级序 **tick < state < critical**（按"丢了有多严重"排序），故 `minClass` 是下限而非上限。

- **插件不走这套 API**：插件通过 XPC/RPC 的回调通道收事件（宿主侧把 `EventSubscription` 桥接成 RPC 通知），插件侧看不到 `AsyncStream`。
- `stats` 暴露给设置页与诊断：能看出"哪个模块在丢事件"，比日志更好用。
- `EventName` 是 `struct` 而非 `String`（带预解析的 domain/subject），避免字符串拼错。内部用 `String` 缓存 rawValue 走热路径。

### 3.5 订阅收窄（privacy 裁剪）

插件订阅内核事件需 `events:subscribe:<name>` 权限（06 号文档 §7.1），且投递前做**字段级裁剪**：

| 事件 | 默认裁剪 | 授予额外能力后 |
|---|---|---|
| `calendar.upcoming` | 只给 `startISO` / `isAllDay` / 数量 | `calendar:read-titles` → 给 `title` / `location` |
| `media.playbackChanged` | 只给 `isPlaying` | `media:read` → 给 `track.*`（`artworkHash` 仍不给） |
| `system.metricsTick` | 完全不投（未授权） | `system:metrics` → 全量 |
| `screen.locked` / `focus.modeChanged` | 只给"状态" | 无更细粒度（状态本身即信息） |
| `plugin.*`（自己的命名空间） | 不裁剪 | — |
| `plugin.<他人ID>.*` | 完全不投 | — |

裁剪在**宿主侧**做（不是插件侧自律），实现为每个事件的 `func redact(for capabilities: Set<Capability>) -> Payload`。

### 3.6 插件事件

- 命名空间：`plugin.<pluginID>.<name>`，宿主校验前缀与来源 id 一致（不符 → 丢弃 + `violation` 日志）。
- 插件**不能**声明 `critical` class（只能 `state` / `tick`），避免插件用高频 critical 淹没总线。
- 速率：每插件 ≤ 20 条/s（状态类）+ 1 条/s（tick 类），超限丢弃并发 `rateLimited`（复用上游错误码语义）。
- payload 必须能 JSON 序列化且 ≤ 16KB。
- P4 之前**只有内核与内置模块**能 publish；插件通道预留但关闭。

---

## 4. 首批事件（字段级）

约定：所有时间为 ISO8601 字符串（含时区偏移）；所有时长为**毫秒整数**（除 `monotonicNs`）；百分比为 0–100 的浮点；字节为整数。

### 4.1 `media.playbackChanged`

class `state` · 触发：播放状态、曲目、来源 App 变化时（**不含进度**）· 频率：≤ 2/s

| 字段 | 类型 | 说明 |
|---|---|---|
| `isPlaying` | bool | — |
| `track` | object? | null = 无曲目 |
| `track.title` / `track.artist` / `track.album` | string | 缺失时为空串（不用 null，避免消费方到处判空） |
| `track.durationMs` | int | 0 表示未知（直播/电台） |
| `track.artworkHash` | string? | 封面内容 hash（省电：同封面不重绘） |
| `sourceBundleID` | string? | `com.apple.Music` / `com.spotify.client` / `com.cider.app` … |
| `capabilities` | string[] | 该来源支持的操作子集：`play` / `pause` / `next` / `previous` / `seek` / `rate` / `shuffle` / `repeat` |

### 4.2 `media.progressTick`

class `tick` · 默认 1s（低功耗 4s）· **插值契约见下**

| 字段 | 类型 | 说明 |
|---|---|---|
| `positionMs` | int | 本 tick 采样时刻的位置 |
| `durationMs` | int | 0 = 未知 |
| `rate` | double | 1.0 正常，0 暂停，>1 快进 |

**插值契约（必须写进 SDK 文档）**：
```
当前进度 ≈ positionMs + (now_monotonic_ns - event.monotonicNs) / 1e6 * rate
```
消费者**不得**把 `positionMs` 直接当"当前进度"用。这是 1Hz 事件能撑起 60fps 进度条的前提，也是架构 §7"折叠态常驻动画 CPU <1%"的实现方式。

### 4.3 `media.lyricsChanged`

class `state` · 触发：曲目切换或歌词加载完成 · **整份替换，无增量**

| 字段 | 类型 | 说明 |
|---|---|---|
| `trackKey` | string | 与 `track` 匹配用的键（title+artist+duration 的 hash） |
| `format` | enum | `lrc` / `lrclib` / `ttml` |
| `offsetMs` | int | 全局偏移（用户手动校正） |
| `isWordLevel` | bool | 是否逐字（决定渲染方式，lyrimuse 那类逐字同步） |
| `lines` | array | `{ startMs, endMs?, text, translation? }`；`endMs` 缺省 = 下一行 `startMs` |
| `lines[].words` | array? | 仅 `isWordLevel`：`{ startMs, endMs, text }` |

上限：1000 行、单行 200 字符（超出截断 + warning）。繁体/简体转换**不在事件里**（由渲染方按设置做，避免同一份歌词产生两个事件）。

### 4.4 `power.sourceChanged`

class `critical`

| 字段 | 类型 | 说明 |
|---|---|---|
| `onAC` | bool | 是否接电源 |
| `isCharging` | bool | — |
| `percentage` | int | 0–100 |
| `isLowPowerMode` | bool | 系统低电量模式 |
| `timeRemainingMin` | int? | null = 计算中/未知 |
| `health` | string? | `normal` / `serviceRecommended` / … |
| `thermalState` | enum | `nominal` / `fair` / `serious` / `critical` |

### 4.5 `system.metricsTick`

class `tick` · 默认 1s（低功耗 4s）· 架构 §5 的 `stats` 模块数据源

| 字段 | 类型 | 说明 |
|---|---|---|
| `dtMs` | int | **距上次采样间隔**。所有速率必须用它换算，因为间隔可能被降频拉长 |
| `cpu` | object | `{ userPct, sysPct, idlePct }` |
| `memory` | object | `{ usedBytes, totalBytes, pressure: "normal"\|"warn"\|"critical" }` |
| `network` | object | `{ rxBytesPerSec, txBytesPerSec }` |
| `disk` | object | `{ readBytesPerSec, writeBytesPerSec, freeBytes }` |
| `gpuPct` | double? | 取不到则缺省（Apple Silicon 上指标有限） |
| `temperatureC` | double? | 同上 |

速率定义：`(本 tick 累计量 - 上 tick 累计量) * 1000 / dtMs`，**不得**用采样瞬时值除以固定 1s。

### 4.6 `calendar.upcoming`

class `state` · 触发：日程增删改、跨过某个日程的开始时间 · 非轮询

| 字段 | 类型 | 说明 |
|---|---|---|
| `items` | array | `{ id, title, startISO, endISO, isAllDay, calendarID, location?, isReminder }`，按 `startISO` 升序 |
| `nextStartInMs` | int? | 距下一个日程开始的毫秒数（**由 `monotonicNs` 推算**，用户改系统时间不影响） |
| `leadTimeMs` | int | 提前提醒阈值（用户配置） |
| `generatedAt` | ISO8601 | 事件生成时刻 |

上限：20 条（超出只取最近的 20 条，`items` 里不含"还有 N 条"标记——需要计数的用 `items.count`）。

### 4.7 `focus.modeChanged`

class `state` · `{ isActive: bool, modeName: string?, untilISO: string? }`

### 4.8 `screen.locked` / `screen.unlocked`

class `critical` · 两个独立事件名（不是 `screen.lockChanged`）· `{ at: ISO8601, sessionID: string }`

**为什么拆两个名字**：订阅者通常只关心其中一个（锁屏要暂停计时器；解锁要刷新数据），拆开可以让 `maxClass`/订阅集合直接表达意图，无需在回调里判方向。

### 4.9 `display.configurationChanged`

class `critical`

| 字段 | 类型 | 说明 |
|---|---|---|
| `reason` | enum | `added` / `removed` / `resized` / `moved` / `mainChanged` |
| `screens` | array | `{ id, name, frame, visibleFrame, hasNotch, scale, isBuiltin, isMain }` |

这是 `NotchGeometry` 的唯一屏变来源（架构 §3 的 `NSApplication.didChangeScreenParametersNotification` 在宿主侧转成此事件，模块不直接监听 AppKit 通知）。

### 4.10 `notch.phaseChanged`

class `state` · 替代架构 §3 里的 `notch.hover(phase)`

| 字段 | 类型 | 说明 |
|---|---|---|
| `from` / `to` | enum | `collapsed` / `hoverPreview` / `expanded` / `dragging` |
| `surface` | enum | 目标 surface（`compact` / `expanded`） |
| `pointerDistancePx` | double? | 指针到刘海下沿的距离，仅 hover 相关转换时有值 |

**预加载契约**：需要预加载的模块应在 `from == .collapsed && to == .hoverPreview` 时启动准备（这正是架构 §3 设计 `notch.hover` 的目的）。只保留一个事件名，避免两个名字表达同一件事。

### 4.11 `config.changed`

class `state`

| 字段 | 类型 | 说明 |
|---|---|---|
| `scope` | enum | `general` / `display` / `layout` / `theme` / `module` / `plugin` |
| `moduleID` | string? | `scope == module/plugin` 时必填 |
| `keys` | string[] | 变更的 key 列表（去抖合并后的） |
| `origin` | enum | `user` / `import` / `migration` / `module` |

**payload 不含值**：值可能含敏感信息（API base、路径），事件会进日志与插件通道。订阅者收到后自行 `config.get`。

### 4.12 `module.stateChanged`

class `state` · `{ moduleID, from, to, reason? }` —— 驱动设置页的状态点与降级可见性（06 号文档 §4）。

---

## 5. 内核侧事件产生点（谁发什么）

| 事件 | 产生者 | 说明 |
|---|---|---|
| `media.*` | `nowplaying` 模块（播放器适配器） | 适配器可插拔（架构 §5）；Apple Music 优先，其他降级为"仅显示曲名"（路线图风险项） |
| `system.metricsTick` | `stats` 模块 | 采样与节流都在模块内，内核只做投递 |
| `power.sourceChanged` | 内核（`IOKit` 电源源） | 因为电池状态影响全局行为（低电量降级），内核自己持有 |
| `screen.*` | 内核（`NSWorkspace` 通知） | 同上 |
| `display.configurationChanged` | 内核（`NotchGeometry`） | 几何变化影响所有模块 |
| `notch.phaseChanged` | 内核（`NotchStateMachine`） | — |
| `focus.modeChanged` | 内核 | 影响动画与通知抑制 |
| `calendar.upcoming` | `calendar` 模块 | — |
| `config.changed` | 内核（`ConfigStore`） | — |
| `module.stateChanged` | 内核（`ModuleRegistry`） | — |

**判定原则**：**影响全局行为或内核自身状态的 → 内核发；有明确功能归属的 → 模块发。** 这样模块可以整个删掉，内核事件面不受影响（对应 P1 验收"注释掉任意模块应用仍能启动"）。

---

## 6. 待拍板

| 编号 | 事项 | 建议 |
|---|---|---|
| D-5 | `system.metricsTick` 的默认频率与低功耗降频倍数（1s / 4s） | 先按 1s + 4s；实测 CPU 后调整 |
| D-6 | 是否给事件加 `traceID`（跨模块追踪一次用户动作的全链路） | 暂不加，等出现真实调试需求（自用项目，加字段要还债） |
| D-7 | `calendar:read-titles` 是否独立成 capability（06 号文档未列） | 建议加，与裁剪表（§3.5）配套；否则裁剪表实现不完整 |
| D-8 | 配置里 `layout.compact.center` 允许多个 id（先到先得）还是强制单个 | 允许数组（用户可预排），运行期只取第一个有内容的 |
