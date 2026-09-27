# 模块协议与描述符（字段级设计）

本文回答一件事：**一个模块（内置或第三方）对宿主暴露什么、宿主对模块承诺什么。** 所有字段、类型、默认值、校验规则在此定稿，实现按此文档写，不按感觉写。

上位文档：[00-decisions.md](00-decisions.md)（ADR-0004 双宿主）、[01-architecture.md](01-architecture.md) §4/§6。上游事实基线见本文 §0。

---

## 0. 上游事实基线（先纠正一个前提）

设计前对 Atoll 基座（`v2.3.3-beta.3`，见 [08-p0-checklist.md](08-p0-checklist.md) §1）做了完整勘察，结论与 ADR-0002 的措辞有偏差，必须先说清，否则后面每一处设计都会站错地基：

| 能力 | ADR-0002 暗示 | 实际（file:line） |
|---|---|---|
| 描述符校验 | 已有 | **有，但校验的是"内容描述符"**：`ExtensionDescriptorValidator.swift:22-62`，校验 `AtollLiveActivityDescriptor` / `AtollLockScreenWidgetDescriptor` / `AtollNotchExperienceDescriptor` 三类**运行时内容** |
| 描述符**文件** | 有 `descriptor.json` | **不存在**。全仓库无 `descriptor.json` / `manifest.json`。等价物是第三方 App 用 Swift Codable struct 编码后经 XPC 传 `Data`，或经 WebSocket 传 JSON |
| 插件包 / 安装 / 卸载 | 有 | **不存在**。没有 `.appex`、没有插件目录、没有发现机制。设置页的 "Remove" 只删授权记录（`ExtensionAuthorizationManager.swift:134-139`） |
| `apiVersion` / 版本协商 | 有 | **不存在**。`grep -rn apiVersion` 零命中；宿主没有任何支持区间 |
| 看门狗 / 崩溃重启 | 有（架构 §6.4 承诺 5s 超时） | **不存在**。XPC 侧无任何超时；唯一定时器是 RPC listener 失败后 3 秒重启（`ExtensionRPCServer.swift:149-162`） |
| 签名校验 | 有 | **不存在**。无 `SecStaticCode` / `codeSigningRequirement` / auditToken；XPC 侧只比对 bundle identifier，RPC 侧 bundle id **由客户端自报**（`ExtensionRPCServer.swift:386-392`） |
| 授权模型 | 有 | **有，且可复用**：`ExtensionPermissionScope{liveActivities, lockScreenWidgets, notchExperiences, fileSharing}`（`Constants.swift:143-147`）、`ExtensionAuthorizationEntry`（`:173-182`）、Defaults 键 `extensionAuthorizationEntries`（`:1388`） |
| XPC 宿主骨架 | 有 | **有，且可复用**：`NSXPCListener(machServiceName:)` + `shouldAcceptNewConnection` 反查 bundle id（`ExtensionXPCServiceHost.swift:24-99`） |
| 进程外**插件代码**执行 | 有 | **不存在**。扩展是**独立第三方 App**，不跑在我们的进程模型里；宿主只接收声明式内容 |

**一句话**：Atoll 给的不是"插件宿主"，而是一套**内容推送 API + 授权模型 + 声明式渲染管线**。这三样恰好是我们最缺的地基（渲染管线尤其值钱），但"插件"这一层——包格式、发现、校验、版本、看门狗——**全部要从零建**。

**后果**：P4（插件生态）的工量比路线图字面所示更大，且 P1 必须先把 `ModuleManifest` 定死，否则 P4 会被迫改两次协议。本文即为该协议。

### 0.1 上游的另一项事实：描述符类型不在本仓库

三种内容描述符与 XPC 协议都定义在**外部 SPM 包** `Ebullioscopic/AtollExtensionKit`，宿主不持有类型定义：

- 依赖声明：`project.pbxproj:1000-1007`，`requirement = { branch = main; kind = branch; }`
- 实际锁定：`Package.resolved` → revision `e2d30afedbbcc259bec7eeb1bea0757e52f4ca01`
- 该 revision 与我们基线 tag `v2.3.3-beta.3` 记录的 revision 一致，且 `v2.3.3-beta.3 → dev HEAD`（155 文件漂移）之间 `Package.resolved` **零差异**

这与 [04-upstreams.md](04-upstreams.md) §2 "依赖锁定 minor 版本区间、不要用分支依赖" 自相矛盾——上游自己就用了分支依赖。处置见 [08-p0-checklist.md](08-p0-checklist.md) §4。

---

## 1. 三层概念分离（本设计的核心决定）

现有文档把"描述符"一词混用于三件事。分开之后，其余设计自然落位：

```
① ModuleManifest   静态、可序列化、可在不认识实现的情况下读
   ├─ 内置模块：Swift 里声明（ModuleManifest 值）
   └─ 插件：磁盘上的 descriptor.json
                    │  宿主校验 → 授权 → 决定加载
                    ▼
② GourdModule     运行时协议 + ModuleContext（依赖注入面）
   ├─ 内置模块：进程内，可返回 SwiftUI 视图
   └─ 插件：进程外，只能返回 ③
                    │  渲染时产出
                    ▼
③ ContentDescriptor  声明式内容（"画什么"），宿主在**自己进程内**渲染
   └─ 复用 Atoll 已有渲染管线（ExtensionLiveActivityViews / Widget / Tab 三条）
```

**决定与理由**

| 决定 | 理由 |
|---|---|
| ① 内置与插件**共用同一份** manifest 模型 | 架构 §4 要求；配置驱动 UI（架构 §4 末）只有单一模型才能驱动 |
| 内置模块的 manifest 也**能导出为 JSON** | 设置页、文档、测试、`docs/` 的功能清单都从同一份数据生成，不手抄 |
| 插件**不得返回视图**，只能返回 ③ | ADR-0004 禁止 `dlopen`；跨进程不可能传 SwiftUI 视图。Atoll 已验证"声明式内容"足够表达 live activity / 锁屏 widget / notch tab 三类形态 |
| 渲染发生在**宿主进程内** | 复用上游管线，插件崩溃不影响渲染；内容大小受描述符上限约束（上游已有 480×280、5MB 图标、20000 字节 HTML 等上限） |
| ② 对两种模块**是同一个协议** | ModuleRegistry 只有一条注册路径、一套生命周期、一套失败隔离（架构 §4 硬性规则） |

> ③ 的字段级定义**不在本文**：上游 `AtollExtensionKit` 已有完整类型（`AtollLiveActivityDescriptor` 等），我们不重造，只做映射与兼容读取（§9）。本文定义的是 ① 与 ②。

---

## 2. ModuleManifest：字段级定义

### 2.1 完整示例（插件 `descriptor.json`）

```json
{
  "manifestVersion": 1,
  "id": "com.example.pomodoro",
  "name": { "en": "Pomodoro", "zh-Hans": "番茄钟" },
  "summary": { "en": "Focus timer with breaks", "zh-Hans": "专注与休息计时" },
  "icon": { "type": "symbol", "name": "timer" },
  "version": "1.0.0",
  "apiVersion": "1.0",
  "minHostVersion": "0.1.0",
  "kind": "js",
  "entry": { "runtime": "js", "main": "main.js" },
  "surfaces": ["compact", "expanded"],
  "defaultPlacement": { "slot": "right", "order": 30 },
  "defaultEnabled": false,
  "permissions": ["notifications", "timers", "storage"],
  "config": {
    "type": "object",
    "properties": {
      "focusMinutes": {
        "type": "integer", "title": { "en": "Focus length", "zh-Hans": "专注时长" },
        "default": 25, "minimum": 5, "maximum": 120, "step": 5,
        "unit": "minute", "control": "stepper", "order": 10
      },
      "breakMinutes": {
        "type": "integer", "default": 5, "minimum": 1, "maximum": 60, "order": 20
      },
      "sound": {
        "type": "enum", "default": "chime", "order": 30,
        "values": [
          { "value": "chime", "title": { "en": "Chime", "zh-Hans": "铃声" } },
          { "value": "none",  "title": { "en": "Silent", "zh-Hans": "静音" } }
        ]
      }
    }
  },
  "author": { "name": "example", "url": "https://github.com/example" },
  "homepage": "https://github.com/example/pomodoro",
  "license": "MIT",
  "limits": { "maxTimers": 4, "minTimerIntervalMs": 1000, "maxStorageBytes": 262144 }
}
```

### 2.2 字段全表

`必填` 列中「内置」/「插件」区分两种来源；「默认」列仅对可选字段有意义。

| 字段 | 类型 | 必填 | 默认 | 约束与校验规则 |
|---|---|---|---|---|
| `manifestVersion` | int | 是 | — | 必须 == 1。**manifest 结构自身**的版本，与 `apiVersion` 解耦：前者管"这份 JSON 的字段集"，后者管"运行时 API" |
| `id` | string | 是 | — | 反域名 `^[a-z0-9]+(\.[a-z0-9-]+)+$`；长度 3–128；不得以 `com.cmeng.gourd.` 开头（该前缀保留给内置）；全局唯一，重复 → `E_DUPLICATE_ID` |
| `name` | LocalizedText | 是 | — | §2.3；每个 locale 值长度 ≤ 40 |
| `summary` | LocalizedText | 否 | — | 每个 locale 值长度 ≤ 120；设置页副标题 |
| `icon` | IconSpec | 是 | — | §2.4。内置模块必须为 `symbol` 类型 |
| `version` | string | 是 | — | 严格 semver `^\d+\.\d+\.\d+$`（插件升级比较用） |
| `apiVersion` | string | 是 | — | `^\d+\.\d+$`（**不含 patch**）。语义见 §8 |
| `minHostVersion` | string | 否 | — | 严格 semver；宿主 `CFBundleShortVersionString` 低于此值 → `E_HOST_TOO_OLD`（不加载，设置页可读地提示） |
| `kind` | enum | 是 | — | `builtin` / `xpc` / `js`。插件必须非 `builtin`；内置必须 == `builtin` |
| `entry` | EntryPoint | 插件必填 | — | §2.5。`kind == builtin` 时必须缺省（出现则 `E_UNEXPECTED_FIELD`） |
| `surfaces` | string[] | 是 | — | 非空子集，元素 ∈ `compact` / `expanded` / `lockscreen`。见 §6 |
| `defaultPlacement` | Placement | 否 | 见 §6.2 | `{slot, order}`；仅当 `surfaces` 含 `compact` 时有意义，否则忽略 |
| `defaultEnabled` | bool | 否 | `false` | 插件声明 `true` → 宿主**忽略并记 warning**（不报错：这不是安全边界，但"装了自动上屏"不可接受，必须用户显式开启）。内置模块可 `true` |
| `permissions` | string[] | 否 | `[]` | 能力白名单，见 §7。元素必须命中宿主支持集，否则 `E_UNKNOWN_PERMISSION` |
| `config` | ConfigSchema | 否 | `{type:"object",properties:{}}` | §5 |
| `author` | object | 否 | — | `{name: string(≤64), url?: URL}` |
| `homepage` | URL | 否 | — | 仅 `https` |
| `license` | string | 否 | — | SPDX 标识符（如 `MIT`）。**插件若内嵌第三方代码，须列出**；分发合规检查读此字段 |
| `limits` | object | 否 | 见右 | 插件自报上限，宿主取 `min(自报, 宿主硬上限)`；内置忽略。字段见 §2.6 |
| `x-*` | any | 否 | — | 前缀 `x-` 的字段一律保留并忽略，供上游/未来扩展 |

### 2.3 LocalizedText

```
LocalizedText = { "key": "<本地化 key>" }              // 内置模块用
              | { "<BCP-47 语言>": "<文本>", ... }      // 插件用；必须含 "en"
```

- 判别方式：**`key` 存在且是唯一成员** → key 形态；否则按 locale 表解析。两者混用 → `E_INVALID_LOCALIZED_TEXT`。
- 语言匹配回退链：精确（`zh-Hans`）→ 语言前缀（`zh`）→ `en` → 按 locale key 字典序取第一个（保证确定性，禁止依赖字典遍历顺序）。
- 长度上限见字段表，超限 → 校验失败（防止设置页被撑爆）。
- 内置模块的 key 统一为 `module.<shortID>.<field>`，例如 `module.nowplaying.name`。

### 2.4 IconSpec

```
{ "type": "symbol", "name": "timer" }                        // SF Symbol
{ "type": "image",  "path": "Resources/icon.png", "size": [20,20] }
{ "type": "appIcon","bundleIdentifier": "com.apple.Music" }
```

- `symbol`：`name` 必须能被 `NSImage(systemSymbolName:)` 解析（宿主校验时实测一次，失败 → `E_INVALID_ICON`）。
- `image`：`path` 相对插件包根，**禁止绝对路径与 `..`**（防目录穿越）；文件 ≤ 1MB，支持 png/jpeg/heic；`size` 每维 8–128。
- `appIcon`：仅内置模块与已安装 App 可用；未安装则运行时回退为 `symbol: "app"`。

### 2.5 EntryPoint

```
{ "runtime": "js",  "main": "main.js" }
{ "runtime": "xpc", "serviceName": "com.example.pomodoro.xpc", "teamID": "ABCDE12345" }
```

| 字段 | js | xpc | 校验 |
|---|---|---|---|
| `runtime` | 必填 `js` | 必填 `xpc` | 必须 == manifest 的 `kind`，否则 `E_KIND_MISMATCH` |
| `main` | 必填 | 禁止 | 相对路径、`..` 禁止、后缀必须 `.js`、≤ 2MB |
| `serviceName` | 禁止 | 必填 | 反域名；与 `id` 同前缀（防冒充他人） |
| `teamID` | 禁止 | 必填 | 10 位 `[A-Z0-9]{10}`；用于签名校验（P4 实现） |

`runtime` 的生命周期差异（P4 实现细节，此处仅定契约）：

| | js | xpc |
|---|---|---|
| 进程 | 宿主进程内的 JavaScriptCore 沙箱（**独立 `JSContext` + 独立 `JSVirtualMachine`**，禁止共享） | 独立进程（`NSXPCConnection`，mach service 由插件包内 `LaunchAgent` 或插件 App 提供） |
| 初始化 | `main.js` 求值后调用约定的 `gourd.activate(ctx)` | 实现 `GourdPluginXPCProtocol` |
| 超时 | 任何同步调用 > 200ms → 中断并记 `degraded` | 调用 > 2s → `degraded` |
| 内存 | `JSContext` 堆上限 32MB，超出终止该插件 | 由系统管理；RSS > 256MB 记为异常并禁用 |
| 崩溃 | JS 异常隔离在插件内，宿主不受影响 | `interruptionHandler` / 连接失效 → 走 §4 状态机 |

### 2.6 limits 子字段

| 字段 | 默认 | 宿主硬上限 | 语义 |
|---|---|---|---|
| `maxContentBytes` | 65536 | 262144 | 单次提交的内容描述符序列化后字节数 |
| `maxTimers` | 4 | 16 | 同时活跃的定时器数 |
| `minTimerIntervalMs` | 1000 | — | 宿主按 `max(自报, 1000)` 强制 |
| `maxStorageBytes` | 262144 | 1048576 | 插件私有 KV 配额 |

---

## 3. GourdModule 协议（字段级）

```swift
@MainActor
public protocol GourdModule: AnyObject {
    /// 静态元数据。builtin 在类型上直接给值；插件由 PluginModuleAdapter 从 descriptor.json 读入。
    static var manifest: ModuleManifest { get }

    /// 依赖注入在构造期完成 —— 模块不存在"未注入"的中间态。
    init(context: ModuleContext)

    /// 幂等：重复调用须直接返回。副作用（起 Task、申请权限、订阅）放这里。
    func activate() async throws

    /// 幂等，且必须在 1s 内返回；超时宿主继续拆其他模块并记警告。
    func deactivate() async

    /// **同步**返回。渲染路径上禁止 async（见 §3.3 规则 R3）。
    func content(for request: ContentRequest) -> ModuleContent

    /// 事件回调。每个订阅者串行、不重入（§见 07 中的投递语义）。
    func onEvent(_ event: GourdEvent) async
}
```

`activate()` 抛错 → 宿主记录并将模块**置为禁用**（不是崩溃、不是重试），其余模块照常（架构 §4 硬性规则 1）。

### 3.1 ContentRequest

```swift
public struct ContentRequest: Sendable {
    public let surface: Surface              // compact | expanded | lockscreen
    public let phase: NotchPhase              // collapsed | hoverPreview | expanded | dragging
    public let slot: Slot?                    // 仅 surface == .compact 时非 nil
    public let sizeHint: CGSize               // 宿主可提供的目标尺寸（模块可忽略）
    public let reason: ContentRequestReason   // initial | event | configChanged | tick | redraw
    public let isLowPower: Bool               // 低功耗模式（架构 §7 要求动画可关）
}
```

### 3.2 ModuleContent

```swift
public enum ModuleContent {
    case view(AnyView)                    // 仅内置模块（kind == builtin）
    case descriptor(ContentDescriptor)    // 内置与插件均可
    case none                             // 该 surface 此刻无内容（不占位）
    case unavailable(reason: String)      // 优雅降级：显示占位与原因，不算失败
}
```

规则：
- `kind != builtin` 的模块返回 `.view` → 宿主断言失败并降级为 `.unavailable`（这是插件越权的硬边界，不允许静默通过）。
- `.descriptor` 的三种形态与 Atoll 现成渲染管线一一对应（§9.1）。

### 3.3 协议级硬性规则

| 编号 | 规则 | 违反后果 |
|---|---|---|
| R1 | 不得直接创建/持有窗口；需要弹层走 `context.ui.present(_:)`（内核 `OverlayHost`） | 编译期不可达（`context` 不提供 `NSWindow`/`NSPanel`），运行期如有绕道则记 `violation` 日志 |
| R2 | 不得持有全局单例；依赖一律经 `ModuleContext` | 面试清单项 + code review；单测用假 context 即可不启宿主 |
| R3 | `content(for:)` 必须同步返回；需要异步准备的用 `onEvent` 预取（`notch.phaseChanged` 就是为此设计） | 渲染超时（>2s）记警告；连续 3 次 → `degraded` |
| R4 | 模块间的直接引用禁止；协作一律通过 EventBus 或 `context.host` 提供的受限服务 | 模块可独立注释掉（P1 验收标准） |
| R5 | 所有文案走 Localizable key，禁止硬编码（架构 §7） | lint：源码中面向用户的字符串字面量需带 `// i18n-ignore` 注解 |

### 3.4 ModuleContext（注入面，字段级）

```swift
@MainActor
public struct ModuleContext {
    public let moduleID: String
    public let host: HostInfo             // appVersion, apiVersion, macOSVersion, buildKind, epoch
    public let config: ConfigHandle        // 只读写本模块作用域（§见 07 §2）
    public let events: EventHandle         // publish / subscribe，受权限门控（§见 07 §3）
    public let logger: ModuleLogger        // 自动带 moduleID 与 subsystem 前缀
    public let storage: ModuleStorage      // 插件私有 KV，配额 = limits.maxStorageBytes
    public let scheduler: ModuleScheduler  // 定时器，受 timers 权限门控 + minTimerIntervalMs
    public let permissions: PermissionHandle  // state(of:) -> notRequested|granted|denied
    public let ui: UIHandle                // requestRedraw() / present(Overlay) / isLowPower
    public let notch: NotchHandle          // 只读几何 + requestExpand/Collapse，不碰窗口
    public let secrets: SecretHandle       // Keychain 读写（值永不落 config.json）
    public let clock: any Clock            // 可注入，单测用假时钟
}
```

**为什么是 struct 而不是 protocol**：`ModuleContext` 是**数据载体**（一堆句柄），不是行为契约。struct 便于构造测试假体，也避免插件作者去实现它。行为契约分布在各个 Handle 上。

`NotchHandle` 只暴露：
```swift
public protocol NotchHandle {
    var phase: NotchPhase { get }
    var geometry: NotchGeometrySnapshot { get }   // 只读快照
    func requestExpand(reason: String)            // 内核决定是否响应（可被用户设置否决）
    func requestCollapse(reason: String)
}
```

---

## 4. 模块生命周期状态机

```
discovered ──parse──▶ parsed ──validate──▶ valid ──compat──▶ compatible
     │                   │E_PARSE           │E_*               │E_HOST_TOO_OLD / E_API_*
     ▼                   ▼                  ▼                  ▼
  ignore             invalid            invalid          needsHostUpdate
                                          │
                            consent ──────┴──────▶ needsConsent
                                          │
                            enabled? ─────┴──────▶ disabled
                                          │
                     activate() ──────────┴──────▶ activating ──ok──▶ active
                                          │                     │
                                          └──throw──▶ failed ◀──┘
                                                        │
                            运行期连续 3 次超时/崩溃 ────▶ degraded ──backoff──▶ disabled
```

| 状态 | 设置页呈现 | 是否占槽位 | 是否收事件 |
|---|---|---|---|
| `active` | 开 | 是 | 是 |
| `degraded` | 降级中（黄） | 是（保留，避免闪烁） | tick 类停投，state 类继续 |
| `failed` / `disabled` | 关（可点开看原因） | 否 | 否 |
| `needsConsent` | 待授权（橙） | 否 | 否 |
| `needsHostUpdate` | 需更新宿主/插件（红） | 否 | 否 |
| `invalid` | 无效（红 + 校验错误原文） | 否 | 否 |

**关键选择**：`degraded` **保留槽位**。理由：模块短暂故障时若槽位消失再恢复，折叠态图标会跳动，比"图标还在但内容空着"更糟。

---

## 5. ConfigSchema 词汇表（字段级）

架构 §4 要求"configSchema 驱动设置界面自动生成"。词汇表如下，是 JSON Schema 的一个**受限子集**（不是完整 JSON Schema，不引入 `$ref` / `oneOf` / 条件分支——那些会让设置界面生成器变成解释器）。

### 5.1 顶层

```json
{ "type": "object", "properties": { "<key>": <Node> }, "required": ["<key>"] }
```

- `properties` 的 key：`^[a-z][a-zA-Z0-9]{0,31}$`。
- 未知的 schema 关键字 → `E_INVALID_SCHEMA`（detail 写明未知关键字名）。**严格**：拼错的 schema 会让设置界面静默少一个控件，必须报错。
- 嵌套 `object` **不允许**（避免无限层级）；分组用节点的 `group` 字段表达。

### 5.2 Node 通用字段

| 字段 | 类型 | 适用 type | 说明 |
|---|---|---|---|
| `type` | enum | 全部 | `boolean`/`integer`/`number`/`string`/`enum`/`color`/`hotkey`/`appPicker`/`filePath`/`dateRange`/`duration`/`secret`/`list` |
| `title` | LocalizedText | 全部 | 控件标签；缺省时回退为 key 的人类化形式 |
| `description` | LocalizedText | 全部 | 副文本；≤ 200 字符 |
| `default` | 按 type | 全部 | 缺省即"无默认"，此时该 key 必须出现在 `required` 或允许为 null |
| `order` | int | 全部 | 排序，升序；相同则按 key 字典序。范围 0–999 |
| `group` | string | 全部 | 同组控件归入一个视觉区块；≤ 32 字符 |
| `requiresRestart` | bool | 全部 | 默认 false；为 true 时设置页标记"重启后生效" |
| `advanced` | bool | 全部 | 默认 false；为 true 时默认折叠在"高级"里 |
| `permission` | string | 全部 | 依赖某能力才可用（§7）。未授予时控件置灰 + 显示申请入口 |

### 5.3 各 type 的专属字段

| type | 专属字段 | 值形态（config.json 里） | 校验 |
|---|---|---|---|
| `boolean` | — | `true/false` | — |
| `integer` | `minimum`, `maximum`, `step`, `unit` | 整数 | 越界 → **clamp + 警告**（不 fail） |
| `number` | `minimum`, `maximum`, `step`, `unit`, `precision` (0–6) | 浮点 | 同上 |
| `string` | `minLength`, `maxLength`, `pattern`, `placeholder`, `multiline` | 字符串 | `pattern` 为 RE2 子集（禁回溯构造）；不匹配 → 用 default + 警告 |
| `enum` | `values: [{value, title, icon?}]`（非空，≤ 32 项） | 字符串 | 不在 `values` → 用 default + 警告 |
| `color` | — | `{"r":0-1,"g":,"b":,"a":}` 或 `"accent"` | `"accent"` 为哨兵，随主题变化；越界 clamp |
| `hotkey` | — | `{"key":"k","modifiers":["cmd","shift","opt","ctrl"]}` 或 `null` | 由 KeyboardShortcuts 库解析；冲突检测→设置页提示 |
| `appPicker` | `multiple` (bool, 默认 false) | `{"bundleIdentifier":"..."}` 或数组 | 未安装的 bundle id 保留但置灰 |
| `filePath` | `mode`: `file`\|`directory`, `allowMultiple` | 字符串或数组 | 存**安全作用域书签的 base64**，不存裸路径（沙箱/权限重启后仍有效） |
| `dateRange` | — | `{"start":"HH:mm","end":"HH:mm"}` | `start > end` 表示跨午夜；`start == end` → 视为全天 |
| `duration` | `minSeconds`, `maxSeconds`, `displayUnit` | **整数秒** | 用整数秒统一存储，展示单位由 `displayUnit` 决定（避免 25 分钟存成 `"25m"` 之类的歧义字符串） |
| `secret` | `keychainKey`（缺省 = property key） | **不在 `config` 里**，在平行的 `secrets.<key>`，值为引用串 `"keychain:<moduleID>/<key>"` | **值永不落 config.json**（[07](07-config-and-events.md) §1.5）；导出时剔除；设置页生成安全输入框 |
| `list` | `itemType`（仅 `string`\|`integer`\|`appPicker`）, `maxItems` (≤ 64) | 数组 | 超长截断 + 警告 |

### 5.4 默认值物化规则（影响迁移，很关键）

- **config.json 只存"用户显式设过的值"**，不物化全量默认。
- 读取时的解析顺序：用户值 → schema `default` → `nil`。
- 理由：模块升级改了 schema 默认值时，未显式设置过的用户能自动拿到新默认值；若物化全量默认，用户会被永久钉在旧默认值上。
- 因此 `resetToDefault(key)` 的语义是**删除该 key**，而不是写入默认值。

---

## 6. Surface 与槽位模型

### 6.1 三个 Surface

| Surface | 语义 | 承载 | 上游对应（§9） |
|---|---|---|---|
| `compact` | 折叠态。刘海两侧图标槽 + 中央主区域 | 槽位（`left`/`right`/`center`） | 上游无独立"槽位"概念；其刘海内 live activity 对应中央区域 |
| `expanded` | 展开面板（点击/悬停后展开） | 展开区的 tab | `AtollNotchExperienceDescriptor`（tab） |
| `lockscreen` | 锁屏小组件 | 锁屏上的 widget | `AtollLockScreenWidgetDescriptor` |

**不新增 `hud` 之类 surface**：瞬时浮层（HUD）是 `expanded` 的一种**呈现方式**，用内容描述符上的 `presentation: "hud"` + `ttlMs` 表达，避免 surface 数量膨胀。上游 `AtollLiveActivityDescriptor` 的 `estimatedDuration` / `durationHint` 正是这个语义。

### 6.2 Slot 模型

```json
"defaultPlacement": { "slot": "right", "order": 30 }
```

| slot | 位置 | 同时可见上限（默认） | 说明 |
|---|---|---|---|
| `left` | 刘海左侧图标槽 | 3 | 状态类（stats / weather） |
| `right` | 刘海右侧图标槽 | 3 | 动作类（timer / clipboard） |
| `center` | 刘海中央主区域 | **1（独占）** | 主内容（nowplaying / lyrics）。多模块竞争 → 按 manifest `order` 排序，取第一个 `active` 且有内容的 |

- 上限可在 `config.layout.compact.maxPerSide` 调（1–5）；超出的模块**不进槽位但保持 `active`**（用户改上限或禁用别人后自动补位）。
- 用户的排序（`config.layout.compact.left/right` 数组）**优先于** `defaultPlacement.order`；`order` 只决定"从未被用户排过"的插入位置。
- `center` 独占是刻意的：两块内容抢同一区域只会做出糟糕的视觉。

### 6.3 与上游 surfaces 的差异显式化

上游 `ExtensionPermissionScope` 是 `liveActivities / lockScreenWidgets / notchExperiences / fileSharing`——它把"能力"和"区域"混在一层。我们的 `surfaces`（区域）与 `permissions`（能力）**分开**：

- `surfaces` 声明"这个模块会出现在哪"，用于布局与设置页展示（安装时以"将出现在：折叠态、展开面板"的形式让用户看见）。
- `permissions` 只列**需要显式同意**的能力（§7）。surface 不重复出现在 permissions 里（避免同一事实两处存储）。
- 上游的 `fileSharing` 在我们的模型里是 `files:picker` + `files:shelf` 两项（更细，且能分别拒绝）。

---

## 7. 权限（Capability）白名单

### 7.1 命名规则

`<family>` 或 `<family>:<arg>`。`family` 必须命中下表；`:` 后为参数。**不支持通配符**。

| capability | 授予后的能力 | 用户可见风险等级 | 默认（插件） |
|---|---|---|---|
| `notifications` | 经宿主发 UserNotifications 通知（标题/正文由宿主模板渲染，插件不能自定义 logo/图标） | 低 | 未授予 |
| `timers` | 注册定时器 / 唤醒；最小间隔 1000ms，低功耗模式下降频至 1/4 | 低 | 未授予 |
| `storage` | 插件私有 KV，配额 `limits.maxStorageBytes` | 低 | 未授予 |
| `clipboard:read` | 读剪贴板**元数据**（类型、长度、hash）；读内容需用户在设置页显式勾选"允许读取内容" | 高 | 拒绝（**不可授予**内容读取，见下） |
| `clipboard:write` | 写剪贴板（触发写入节流：≥500ms 间隔） | 中 | 未授予 |
| `files:picker` | 通过系统面板获得用户**当次选择**的文件访问权（安全作用域书签） | 低 | 未授予 |
| `files:shelf` | 读写文件暂存架（shelf 模块的数据），含增删 | 中 | 未授予 |
| `network:<host>` | 向**指定 host**（含其子域）出站请求；每 host 一条 capability | 高 | 未授予 |
| `media:control` | 播放/暂停/上下曲/跳转 | 中 | 未授予 |
| `media:read` | 读取当前曲目元数据（标题/艺术家/封面 hash） | 中 | 未授予 |
| `system:metrics` | 读 CPU/内存/磁盘/网络指标 | 中 | 未授予 |
| `power:control` | 防休眠（`IOPMAssertion`）等电源断言 | 中 | 未授予 |
| `shortcuts:run` | 触发系统快捷指令（需用户再次确认具体指令名） | 中 | 未授予 |
| `ai:complete` | 调宿主 AI 服务（**消耗用户自有 token**） | 高 | 未授予 |
| `events:subscribe:<eventName>` | 订阅指定内核事件（§见 07 §3.5 的裁剪规则） | 视事件 | 未授予 |

硬性规则：

1. `network` 必须以 `network:<host>` 形式出现，host 为小写域名（**不接受 IP、不接受通配符、不接受端口**）。裸 `network` → `E_INVALID_PERMISSION`。
2. `clipboard:read` 只给元数据。内容读取是宿主设置页里**每插件一项的额外勾选**，不进 descriptor（插件无法通过 manifest 索取内容读取权）——理由：剪贴板内容是最容易泄漏的隐私面，索取它必须是用户主动动作，而不是一次"安装即同意"。
3. 权限**只增不减地**在安装/升级时重算：升级若新增权限 → 状态回到 `needsConsent`，旧授权不自动继承。
4. 权限撤销是**运行时生效**：宿主停止投递对应能力并通知模块（`module.permissionChanged`），不要求重启。
5. 内置模块**不经过** capability 授予流程（用户装了就是信任），但其 manifest 仍须如实声明 `permissions`——用于设置页展示与代码审计的一致性检查。

---

## 8. apiVersion 与兼容策略

### 8.1 版本语义

- `apiVersion` 形如 `MAJOR.MINOR`，**不含 patch**（patch 留给宿主自身版本）。
- 宿主维护 `supportedAPIRange = 1.0 ... 1.<N>`（`N` 为当前宿主实现的最高 minor）。
- 判定：
  - `major != 宿主 major` → `E_API_MAJOR` → 拒绝加载，设置页显示"该插件需要 apiVersion 2.x，当前宿主支持 1.x"。
  - `major == 且 minor > N` → `E_API_MINOR` → 拒绝加载，提示"请升级壶中天"。
  - `major == 且 minor <= N` → 通过。
- **只保证"新宿主跑旧插件"**（向后兼容）。旧宿主跑新插件**明确不支持**（靠 `minor > N` 拒绝）。

### 8.2 minor 内禁止破坏性变更

`apiVersion` 的 minor 递增意味着**只增不改**：
- 可以：新增事件、新增权限、新增 ConfigSchema type、新增 ContentDescriptor 可选用法、新增 ModuleContext Handle。
- 不可以：改字段类型、改字段语义、删事件字段、改默认值语义、改渲染契约。

违反者按 major 递增处理，并在宿主里为旧 major 保留 shim（P4 起，shim 表写在 `docs/` 而非代码注释里，便于对照）。

### 8.3 与 `manifestVersion` / `minHostVersion` 的分工

| 字段 | 管什么 | 变化频率 | 不匹配时 |
|---|---|---|---|
| `manifestVersion` | descriptor.json 的**字段集** | 极少（目前 == 1） | 拒绝加载 |
| `apiVersion` | **运行时 API**（事件/权限/Handle/内容协议） | 每个宿主 minor | 拒绝加载 |
| `minHostVersion` | 插件作者要求的最低宿主版本（用于需要新宿主**修正**的场景，不用于 API） | 作者自行决定 | 拒绝加载 |
| `version` | 插件自身版本 | 作者发版 | — |

---

## 9. 与 Atoll 的兼容读取（docs/04 §3.3 的落地）

[04-upstreams.md](04-upstreams.md) §3.3 要求"优先保持能读懂上游扩展"。落点是**内容描述符**这一层（因为上游只有这一层）：

### 9.1 映射表

| 上游类型 | 我们的 ContentDescriptor | 备注 |
|---|---|---|
| `AtollLiveActivityDescriptor` | `.compactActivity` | 刘海中央区域内容。`trailingContent`/`progressIndicator`/`badgeIcon` 原样传透 |
| `AtollNotchExperienceDescriptor` | `.expandedPanel` | tab 形态；`sections`/`webContent` 原样 |
| `AtollLockScreenWidgetDescriptor` | `.lockscreenWidget` | `layoutStyle`/`position`/`content` 原样 |

上游字段的取舍（**必须显式记录，避免"看起来兼容实际丢字段"**）：

| 上游字段 | 处置 | 理由 |
|---|---|---|
| `sneakPeekConfig` / `sneakPeekTitle` | **保留并透传** | 悬停预览，正是折叠态核心交互 |
| `allowsMusicCoexistence` | 保留 | 媒体共存策略，与 `center` 独占规则交互（共存时中央区域让位） |
| `allowWebInteraction` / webView HTML | 保留，但受宿主开关约束 | 上游已实现域名白名单（`ExtensionLockScreenWidgetView.swift:352-393`）；**注意上游未声明的 `allowRemoteRequests` 字段能绕过白名单**，我们只读取已声明字段，不透传该键 |
| `metadata: [String:String]` | 保留，≤ 32 键 | 与上游同一上限 |
| widget 尺寸校验 | 取 **480×280**（上游宿主侧值）而非 640×360（kit 侧值） | 上游两处不一致（`ExtensionDescriptorValidator.swift` vs kit 的 `isValid`）；取更严的一方，避免渲染溢出 |

### 9.2 线协议的两个不可省略的细节（fork 后仍要复刻）

若要继续接受上游生态的 App（P0～P3 期间保持打通），这两处行为必须逐字保留：

1. **枚举整形**（仅 WebSocket RPC 路径）：客户端发 `{"type":"symbol","name":"timer"}`，宿主需重写为 `{"symbol":{"name":"timer"}}`；未命名首参还原规则见 `ExtensionRPCService.swift:621-724`（`text|marquee` 的 `text`→`_0`、`icon` 的 `icon`→`_0`、`progress` 的 `indicator`→`_0`、`webView` 的 `content`→`_0`）。XPC 路径**不做**该变换（直接传 `JSONEncoder` 产物）。
2. **XPC 传 `Data` 而非对象**：宿主全程零 `NSXPCInterface.setClasses` 调用，自定义类型靠 `Data` 过线。改这一点会立刻破坏与上游 kit 的互通。

### 9.3 我们**不**兼容的部分（明确不做）

上游 `AtollExtensionKit` 里的类型定义我们**不 fork、不修改**（它 pin 在外部仓库，见 [08-p0-checklist.md](08-p0-checklist.md) §4）。因此：

- 上游 kit 里硬编码的宿主查找（`AtollXPCConnectionManager.swift` 里的 `serviceName = "com.ebullioscopic.Atoll.xpc"` 与 `com.ebullioscopic.Atoll`）在我们改名后会失配 → **上游 kit 写成的第三方 App 无法连上 Lagoon**。这是已知且接受的后果：能读出它们的描述符 ≠ 能冒充上游身份。真实打通需要对方用我们的 SDK 重编（P4 的 `PluginSDK`），或我们提供一个改了常量名的 community kit。
- 三方 App 与"插件"是两回事：App 推内容是**单向、无宿主生命周期**；插件是**双向、有生命周期与看门狗**。P4 之前不承诺第三方 App 互通。

---

## 10. 校验规则与错误码

### 10.1 校验顺序（短路，报第一个错）

1. JSON 可解析 → `E_PARSE`
2. `manifestVersion` == 1 → `E_MANIFEST_VERSION`
3. 必填字段存在且类型正确 → `E_MISSING_FIELD` / `E_TYPE`
4. 未知字段（除 `x-*`）→ `E_UNKNOWN_FIELD`
5. `id` 格式与保留前缀 → `E_INVALID_ID`
6. `kind` 与 `entry` 互相一致 → `E_KIND_MISMATCH` / `E_UNEXPECTED_FIELD`
7. `surfaces` 非空合法 → `E_INVALID_SURFACE`
8. `permissions` 全部命中白名单 → `E_UNKNOWN_PERMISSION` / `E_INVALID_PERMISSION`
9. `config` schema 合法 → `E_INVALID_SCHEMA`
10. `icon` 可解析 → `E_INVALID_ICON`
11. `entry.main` / `icon.path` 路径安全（无 `..`、无绝对路径、无符号链接逃逸）→ `E_UNSAFE_PATH`
12. `apiVersion` 兼容 → `E_API_MAJOR` / `E_API_MINOR`
13. `minHostVersion` ≤ 宿主 → `E_HOST_TOO_OLD`
14. 全局 `id` 唯一 → `E_DUPLICATE_ID`

### 10.2 错误码表

| 码 | 触发 | 用户可见文案 |
|---|---|---|
| `E_PARSE` | JSON 语法错误 | 描述符无法解析（第 row:col 行） |
| `E_MANIFEST_VERSION` | 版本不支持 | 描述符版本 N 不受支持 |
| `E_MISSING_FIELD` | 缺必填 | 缺少必填字段 `<field>` |
| `E_TYPE` | 类型错 | 字段 `<field>` 期望 `<type>` |
| `E_INVALID_LOCALIZED_TEXT` | LocalizedText 同时给了 `key` 与 locale 表，或缺少 `en` | 字段 `<field>` 的本地化文本不合法（须二者择一，且含 `en`） |
| `E_UNKNOWN_FIELD` | 未知字段 | 未知字段 `<field>`（可能拼写错误） |
| `E_UNEXPECTED_FIELD` | 不该出现的字段 | `builtin` 模块不得声明 `<field>` |
| `E_INVALID_ID` | id 不合规 | 模块 id `<id>` 不合法或使用保留前缀 |
| `E_DUPLICATE_ID` | id 冲突 | 已存在同 id 模块（安装位置：…） |
| `E_KIND_MISMATCH` | kind/entry 冲突 | `kind` 与 `entry.runtime` 不一致 |
| `E_INVALID_SURFACE` | surface 非法 | 未知 surface `<value>` |
| `E_UNKNOWN_PERMISSION` | 权限不在白名单 | 未知权限 `<value>` |
| `E_INVALID_PERMISSION` | 权限格式错 | 权限 `<value>` 格式不合法（如 `network` 必须指定 host） |
| `E_INVALID_SCHEMA` | schema 非法 | 配置项 `<key>` 的 schema 非法：<detail> |
| `E_INVALID_ICON` | 图标不可解析 | 图标 `<value>` 无法解析 |
| `E_UNSAFE_PATH` | 路径逃逸 | 路径 `<path>` 不被允许 |
| `E_API_MAJOR` / `E_API_MINOR` | API 版本不匹配 | 需要 apiVersion `X.Y`，当前宿主支持 `1.0–1.N` |
| `E_HOST_TOO_OLD` | 宿主版本太低 | 需要壶中天 ≥ `<version>` |

**校验失败一律拒绝加载**（不做"部分可用"降级）。理由：manifest 是安全边界，静默跳过坏字段等于把拼错的权限声明变成"看起来申请了但没生效"。

### 10.3 与上游错误枚举的关系

上游的 `ExtensionValidationError`（`ExtensionActivityModels.swift:58-85`：`featureDisabled/unauthorized/invalidDescriptor/rateLimited/exceedsCapacity/duplicateIdentifier/unsupportedContent`）是**运行时内容提交**的错误面，与我们的**静态 manifest 校验**错误面正交，两套并存、互不替代。

其中 `rateLimited` 上游**定义了但从未抛出**（`ExtensionRateLimitRecord` 也只记录不判定）。我们补上真正的实现：令牌桶，每插件 `present` 10 次/10s、`update` 60 次/min，超限返回 `rateLimited`，并在设置页显示当前用量（上游设置页已有"近 5 分钟计数"的展示位，`ExtensionsSettings.swift`）。

---

## 11. 待拍板 / 待实现清单

| 编号 | 事项 | 影响面 | 建议 |
|---|---|---|---|
| D-1 | 插件进程模型：ADR-0004 定 XPC 优先，但上游**没有插件进程先例**（其 XPC 是"接内容"不是"跑代码"）。XPC 的启动/签名/LaunchAgent 成本对单人维护偏高 | P4 | 保留 XPC 为第一实现；若 P4 启动时发现 XPC 打包成本压过收益，改用 **LSP 风格 stdio JSON-RPC 子进程**（宿主 `Process` + pipe，插件可用任意语言写，崩溃隔离天然、无需 LaunchAgent）。切换到 P4 kickoff 时再定，**不影响本文的 manifest 与内容协议**（两者与进程模型正交） |
| D-2 | `center` 独占是否允许用户强制并列（如 nowplaying + lyrics 同屏） | P3 布局 | 先独占。若实测觉得浪费，改为"用户可在设置里把 center 扩为 2 槽" |
| D-3 | 插件签名校验的严格度（P4） | P4 安全 | 未签名插件允许安装但**默认禁用**，需用户显式"启用未签名插件"；已签名校验 teamID 与 `entry.teamID` 一致 |
| D-4 | `clipboard:read` 的元数据范围（是否含 hash，会让插件能比对已知内容） | P2 | 先给类型+长度，不给 hash |
