# 运行时内核与接缝（P1 批次）

> 本文件是工作流 `p1-kernel` 的设计文档，承接 [06-module-protocol.md](06-module-protocol.md)（协议与字段**逐字沿用**，本文件不重复定义）、[12-p1-batches.md](12-p1-batches.md)（P1-0/P1-1 批次）、[09-features-and-mechanisms.md](09-features-and-mechanisms.md) §8.1（模块化边界，用户已拍板）。
> 状态机归属的三路证据来自本批次的三份只读调研（上游 UI 接缝 / 状态机归属 / manifest 清单），结论已并入本文与 [14-module-manifests.md](14-module-manifests.md)。

## 一句话方案

新建 `DynamicIsland/Kernel/`（协议与注册表，按 06 号文档逐字实现）与 `DynamicIsland/Modules/`（内置模块），用**三处最小上游接线**（展开面板 tab 列表、展开内容 switch、组合根 bootstrap）把模块注册表挂进现有 UI；以一个真实模块 `progress` 跑通「manifest → 注册 → 渲染」全链路，并把状态机归属裁定为**包装/观测**（本批只落裁定，实现属 P1-2）。

## 背景与目标

**问题现状**：协议只存在于纸面——[06](06-module-protocol.md) 有 593 行字段级规范，仓库里**零个 Swift 类型**。上游的展开面板 tab 列表硬编码在 `TabSelectionView.swift:65-115`（逐项 `append` + Defaults 条件门），内容视图是 `ContentView.swift:1086-1111` 的 `switch coordinator.currentView`（裸构造具体 View，无工厂、无协议）。这带来两个直接后果：**加一个功能要动上游渲染核心**（与 ADR-0011「不改上游文件」冲突），以及折叠态/展开态的视觉与逻辑继续不可拆解。

**预期结果**：模块可插拔——新增一个模块 = 实现 `GourdModule` 协议 + 在组合根注册一行；注释掉任意一个模块的注册行，应用仍能正常启动（P1 验收，[02](02-roadmap.md)）；上游渲染核心不被改写，只做接线。

**承接来源与本次增量**：

| 来源 | 继承什么 | 本次增量 |
|---|---|---|
| [06](06-module-protocol.md) §2/§3/§6 | `ModuleManifest` 字段全表、`GourdModule` 协议、`ModuleContext` 注入面、Surface/Slot 模型、生命周期状态机 | Swift 类型落地（本批实现子集见「明确不做」）、manifest 解析与校验 |
| [09](09-features-and-mechanisms.md) §8.1 | 模块化边界：接管 10 + 新增 5 + 终端配置；其余保持上游原样 | 本批只落内核与一个试点模块，不批量接管 |
| [12](12-p1-batches.md) P1-0/P1-1 | 三项前置设计、内核骨架任务 | 接缝定稿（含上游实测挂点与证据）、状态机归属裁定 |
| [07](07-config-and-events.md) | 事件与配置的字段级规范 | 本批只落 **manifest 默认值读取**（简化 `ConfigHandle`，方法名对齐 07 §2 的 `get`/`set`）；事件总线、`observe`/`schema` 与完整 ConfigStore 留 P1-3 |

## 做法

**内核（新代码，全在 `DynamicIsland/Kernel/`）**：类型层按 06 号文档逐字实现（协议、manifest、content、context 与句柄）；`ModuleRegistry` 的形态**仿写上游既有的同构先例** `managers/Extensions/ExtensionNotchExperienceManager.swift:25-229`（`@Published` 投影 + 按 id 查找内容 + 启用门 + 优先级排序），而不是发明新接缝类型——上游已经证明这套形态能与 `TabSelectionView` / `ContentView` / `DynamicIslandViewCoordinator` 协作。

**接缝（改上游文件，仅三处 + 两处必须同步）**：① `TabSelectionView.tabs` getter 末尾追加注册表投影（复用现成的 `TabModel`，`experienceID` 复用为模块 id，`ForEach` 零改）；② `ContentView` 的 switch 加**一个** case 指向 `ModuleHostView`；③ `DynamicIslandApp` 的 `applicationDidFinishLaunching`（上游已有 4 个同构先例：`SystemHUDManager.shared.setup(coordinator:)`、`BetterDisplayManager.shared.configure(coordinator:)`、`LunarManager.shared.configure(coordinator:)` 等）加一行 `KernelBootstrap.bootstrap()`。必须同步的两处：`sizing/matters.swift:enabledStandardTabCount()`（它注释里写明 "Mirrors the tab-building logic in TabSelectionView"，不同步会让刘海最小宽度算错）、`DynamicIslandViewCoordinator.tabOrder`（切换方向动画用）。

**试点模块**：`Modules/ProgressModule.swift`（日/周/月/季/年进度，[09](09-features-and-mechanisms.md) §5.3，零私有 API、零依赖），既是 P1-4 的试点，也证明「协议 + 注册一行」这条路径成立。

**首启默认值**：`KernelBootstrap` 在注册后执行一次幂等的「首启默认值」写入（本批一条：`enableScreenAssistant=false`），落地 [09](09-features-and-mechanisms.md) §8.1 已拍板的「不需要的上游功能用默认值表达、不改上游源码」。

## 备选与取舍

**状态机归属**（本批最重要的裁定，三路证据见下表）：选 **B 包装/观测**，替换路线留到 P2+ 内核真正接管渲染时。

| 维度 | A 替换 `DynamicIslandViewModel.notchState` | B 包装/观测（选定） |
|---|---|---|
| 改动面 | 126 处引用中**只有 5 处**编译器能发现（1 个穷举 switch + 1 个类型化形参 + 3 处 `onChange`），其余约 103 处二元比较需人工复评 | 新增内核类 + 订阅 `vm.$notchState`；为拿到 hover 需一次**极小**上游接线（`isHovering` 目前是 `ContentView.swift:214` 的 `@State private`） |
| 失败模式 | 用户直接可见的视觉回归（hover 时 tab 不渲染 `ContentView.swift:1084`、根 frame 尺寸跳变 `:724-729`、折叠态 HUD 链断裂 `:919-1002`），分散在 12 个文件 | 状态机少一个相位（可降级、可增补信号） |
| 收益时点 | `phaseChanged` 的完整语义在 P1 结束时**还没有消费者**（渲染仍在上游） | 立刻可用：`collapsed`/`expanded` 与上游严格一致，`dragging` 可复用 `anyDropZoneTargeting` |

另两条备选：**给 `NotchViews` 加关联值**（如 `.module(id:)`）——否决，会破坏 `DynamicIslandViewCoordinator.swift:108/120` 的 `tabOrder.firstIndex` 与 `ContentView.swift:1113` 的 `.id()`；改用新增**无关联值** case + coordinator 加 `selectedModuleID`。**继承 `ExtensionNotchExperienceManager` 类**——否决，那套是扩展通道的线协议身份（B 表冻结项），混用会把两条生命周期绑在一起；只仿写形态。

**折叠态**：本批**不做**槽位渲染。理由：折叠态不是"两侧槽位"而是 `ContentView.swift:917-989` 的 if/else 优先级链，三条"左图标槽 + 中央 + 右图标槽"布局必须重构 `:1219-1312` 的 HStack——这是整份调研里唯一无法零结构改动的地方（[12](12-p1-batches.md) P1-0 已把它列为首要接缝风险）。试点模块本批只进展开面板。

## 接口与数据形状

> 全部按 [06](06-module-protocol.md) 的字段名与取值词汇表；本节只列**本批实现**的部分，未列出的即为「明确不做」。

```swift
// ===== DynamicIsland/Kernel/ModuleTypes.swift =====
public enum Surface: String, Codable, Sendable, CaseIterable { case compact, expanded, lockscreen }
public enum Slot: String, Codable, Sendable, CaseIterable { case left, right, center }
/// 06 §3.1 的四态。本批只有 collapsed / expanded 可达（D-04 的包装路线），
/// 其余两态由 P1-2 的 NotchStateMachine 补齐。
public enum NotchPhase: String, Codable, Sendable, CaseIterable { case collapsed, hoverPreview, expanded, dragging }
public enum ContentRequestReason: String, Codable, Sendable { case initial, event, configChanged, tick, redraw }

// ===== DynamicIsland/Kernel/ModuleManifest.swift =====
public struct LocalizedText: Codable, Sendable, Equatable {   // 06 §2.3 两种形态
    public let key: String?                 // 内置用；存在且唯一成员 → key 形态
    public let table: [String: String]?     // 插件用（本批只解析，不使用）
}
public struct IconSpec: Codable, Sendable, Equatable { public let type: String; public let name: String? }
public struct Placement: Codable, Sendable, Equatable { public let slot: Slot?; public let order: Int? }
/// 06 §5 的受限子集：本批只支持 boolean/integer/number/string/enum/list 六种 type，
/// 不做 $ref/oneOf/条件分支与 `required`；`default` 是 ConfigHandle 的唯一默认值来源（本批）。
/// **`default` 在 manifest JSON 里是裸值**（对齐 06 §5.3：`"ring"` / `true` / `1` / `["a","b"]`），
/// 因此 `ConfigValue` 必须**自定义 `Codable`**（按 `ConfigNode.type` 判别解码），
/// 不能用 Swift 合成的关联值编码（那会写成 `{"string":"ring"}` 而解不出）。
public enum ConfigValue: Codable, Sendable, Equatable {
    case bool(Bool), int(Int), double(Double), string(String), strings([String])
}
public struct ConfigNode: Codable, Sendable, Equatable {
    public let type: String                  // boolean|integer|number|string|enum|list
    public let title: LocalizedText?
    public let `default`: ConfigValue?
    public let values: [String]?             // enum 的可选值
    public let itemType: String?             // list 的元素类型
}
public struct ConfigSchema: Codable, Sendable, Equatable {
    public let type: String                  // 必须 == "object"
    public let properties: [String: ConfigNode]
}
public struct ModuleManifest: Codable, Sendable, Equatable {
    public let manifestVersion: Int         // 必须 == 1
    public let id: String
    public let name: LocalizedText
    public let summary: LocalizedText?
    public let icon: IconSpec
    public let version: String
    public let apiVersion: String
    public let kind: String                 // 本批只允许 "builtin"
    public let surfaces: [Surface]
    public let defaultPlacement: Placement?
    public let defaultEnabled: Bool?
    public let permissions: [String]
    public let config: ConfigSchema?        // 缺省 = {object, properties:{}}
}
public enum ModuleManifestError: Error, Equatable {
    case badVersion(Int), badID(String), badAPIVersion(String), emptySurfaces,
         badIcon(String), badLocalizedText(String), unexpectedEntry, unsupportedKind(String),
         unknownPermission(String)
}
public extension ModuleManifest {
    static func decode(from data: Data) throws -> ModuleManifest   // JSONDecoder + validate()
    func validate() throws
    var shortID: String                    // "com.cmeng.gourd.progress" → "progress"
}

// ===== DynamicIsland/Kernel/GourdModule.swift =====
@MainActor
public protocol GourdModule: AnyObject {   // 06 §3 的**本批子集**：`onEvent` 未纳入（事件总线属 P1-3，见「明确不做」）
    static var manifest: ModuleManifest { get }
    init(context: ModuleContext)
    func activate() async throws
    func deactivate() async
    func content(for request: ContentRequest) -> ModuleContent
}
public struct ContentRequest: Sendable {   // 06 §3.1（本批去掉事件相关字段）
    public let surface: Surface
    public let phase: NotchPhase
    public let slot: Slot?
    public let sizeHint: CGSize
    public let reason: ContentRequestReason
    public let isLowPower: Bool
}
public enum ModuleContent {                // 06 §3.2 的本批子集
    case view(AnyView)
    case descriptor                  // 占位：本批无关联值、不渲染（P4 加回 payload，见「已知限制」）
    case unavailable(reason: String)
    case none
}

// ===== DynamicIsland/Kernel/ModuleContext.swift（本批实现子集，D-05）=====
// 本批**不含** notch / permissions / events / storage / scheduler / secrets 六个面：
// 它们需要 per-screen 的 DynamicIslandViewModel 或未定的设计（P1-2/P1-3），
// 试点模块不需要，故按 D-05 延后——延后项与加回时的破坏面见「明确不做」与「已知限制」。
@MainActor
public struct ModuleContext {
    public let moduleID: String
    public let host: HostInfo
    public let config: ConfigHandle
    public let logger: ModuleLogger
    public let ui: UIHandle
}
public struct HostInfo: Sendable, Equatable {
    public let appVersion: String          // CFBundleShortVersionString
    public let apiVersion: String          // "1.0"
    public let macOSVersion: String
}
/// 默认值来源：`manifest.config.properties[key]?.default`；覆盖值写 UserDefaults
/// 命名空间 `com.cmeng.gourd.module.<shortID>`（**临时落点**，P1-3 随 ConfigStore(JSON) 迁移，见「已知限制」12）。
/// 方法名对齐 07 §2 的 `get`/`set`（本批不做 `observe` / `schema` / nil 重置语义）。
public protocol ConfigHandle: AnyObject {
    func get<T: Codable & Sendable>(_ key: String, as: T.Type) -> T?
    func set<T: Codable & Sendable>(_ key: String, to value: T) -> Bool
}
public protocol UIHandle: AnyObject {
    func requestRedraw()                   // 宿主注入：触发 ModuleHostView 重绘
    var isLowPower: Bool { get }           // 本批恒 false（低功耗信号属 P1-3）
}
public final class ModuleLogger: @unchecked Sendable {   // 自动带 moduleID 与 subsystem 前缀 com.cmeng.gourd.module.<shortID>
    public func info(_ message: String); public func warn(_ message: String); public func error(_ message: String)
}
// 实现者：DynamicIsland/Kernel/ModuleContextFactory.swift（T2 交付）
@MainActor
public enum ModuleContextFactory {
    public static func make(manifest: ModuleManifest, redraw: @escaping () -> Void) -> ModuleContext
}

// ===== DynamicIsland/Kernel/ModuleRegistry.swift =====
public enum ModuleRuntimeState: Equatable { case disabled, activating, active, failed(reason: String) }
public struct ModuleTabEntry: Identifiable, Equatable {
    public let id: String            // module id
    public let label: String         // 已本地化标题
    public let symbolName: String    // SF Symbol
    public let order: Int            // defaultPlacement.order ?? Int.max
}
@MainActor
public final class ModuleRegistry: ObservableObject {
    public static let shared = ModuleRegistry()
    @Published public private(set) var states: [String: ModuleRuntimeState]
    public private(set) var manifests: [String: ModuleManifest]
    public func register(_ types: [any GourdModule.Type], enabled: @escaping (String) -> Bool)
    public func bootstrap() async                  // 实例化 + 逐个 activate；单个失败只禁用自己（06 §3 硬性规则）
    public func deactivateAll() async
    public func instance(for id: String) -> (any GourdModule)?
    public var tabEntries: [ModuleTabEntry]        // 仅 active 且 surfaces 含 .expanded，按 order 升序
    public func content(for id: String, request: ContentRequest) -> ModuleContent
}

// ===== DynamicIsland/Kernel/KernelBootstrap.swift（组合根）=====
@MainActor
public enum KernelBootstrap {
    public static func bootstrap() async           // 注册内置模块 + 首启默认值（幂等）
    static let builtinModules: [any GourdModule.Type]     // ← 新增模块 = 往这个数组加一行
    static func applyFirstLaunchDefaults()         // enableScreenAssistant=false，一次性
}
```

**接缝的精确改动**（上游文件，只接线）：

| # | 文件:位置 | 改动 |
|---|---|---|
| S1 | `components/Tabs/TabSelectionView.swift:65-115` 与 `:118-152` | ① 加 `@ObservedObject private var moduleRegistry = ModuleRegistry.shared`（**必须**——否则注册表变化后 tab 列表不重绘；同文件已有 `@ObservedObject private var extensionNotchExperienceManager` 的先例）；② `tabs` getter 末尾追加 `for e in ModuleRegistry.shared.tabEntries`；③ 选中判定改为 `tab.view == .module ? coordinator.selectedModuleID == tab.experienceID : coordinator.currentView == tab.view`；④ **点击路径**（`:123-128` 的 action，照 `:124-125` 对 extensionExperience 的写法同构）：`if tab.view == .module { coordinator.selectModule(tab.experienceID ?? "") }`——只设 `currentView = .module` 而不设 `selectedModuleID` 会让内容区渲染 EmptyView |
| S2 | `sizing/matters.swift:101-135` | `enabledStandardTabCount()` 加 `ModuleRegistry.shared.tabEntries.count`，并把该函数与其调用链（`currentRecommendedMinimumNotchWidth()` `:145`、`openNotchSize` `:69`、`enforceMinimumNotchWidth()` `:152`）标 `@MainActor`（同文件 `minimalisticOpenNotchSize` `:173` 已有先例）；`DynamicIslandViewCoordinator.swift:243/248` 两个非隔离调用点用 `MainActor.assumeIsolated { }` 跳转（仓库已有 4 处同款先例）。若编译期报隔离错误，**先按此方案改调用点，不得为绕过而读写非隔离镜像** |
| S3 | `enums/generic.swift:73-84` | `NotchViews` 追加**无关联值** case `module`（D-02：加关联值会破坏 `tabOrder.firstIndex` 与 `.id()`） |
| S4 | `DynamicIslandViewCoordinator.swift:103-135` | 新增 `@Published var selectedModuleID: String?`；`tabOrder` 追加 `.module`；新增 `func selectModule(_ id: String)`（设 `selectedModuleID` + `currentView = .module`） |
| S5 | `ContentView.swift:1083-1113` | switch 加 `case .module: ModuleHostView(moduleID: coordinator.selectedModuleID)`（无选中时 `EmptyView`）；`.id(coordinator.currentView)` 改为含模块 id 的复合值，否则模块间切换不重放过渡 |
| S6 | `DynamicIslandApp.swift:625` 附近 | `Task { await KernelBootstrap.bootstrap() }`（紧邻既有的 4 个同构 `Manager...shared.setup(...)` 调用） |
| S7 | `models/Constants.swift` | 追加 1 个 Key：`gourdFirstLaunchDefaultsApplied`（Bool, default false） |

**新增文件与被工程纳入的方式**：`DynamicIsland/` 是 `PBXFileSystemSynchronizedRootGroup`（`project.pbxproj:117-123`），**新目录 `Kernel/`、`Modules/` 下的文件自动进入 app target，无需改 pbxproj**。但 `DynamicIslandTests/` 是**普通 PBXGroup**（`:177-188`），新测试文件必须显式登记**四处**：`PBXFileReference` + `PBXBuildFile` + group `children` + test target 的 `Sources`（参照既有 `FlyoutFrameCalculatorTests.swift` 的四条记录，`:35`/`:83`/`:180` 与 Sources 段）。本批测试全部写进**一个**新文件 `DynamicIslandTests/ModuleKernelTests.swift`，把 pbxproj 编辑压到一次；新对象 ID 用不与既有冲突的 24 位十六进制（既有 ID 形如 `C0DEFACE1234567890ABCDEF`）。

## 明确不做

- **折叠态槽位渲染**（左/中/右三槽）——需重构 `ContentView.swift:1219-1312` 的 HStack，推 P2
- **状态机实现**——本批只落归属裁定（D-04）；`NotchStateMachine` 与四态迁移单测属 P1-2
- **`isHovering` 提升为可观测量**——D-04 认定的唯一必要上游编辑，留给 P1-2（本批没有 hover 相位的消费者）
- **事件总线与订阅**（`GourdModule.onEvent`、`EventHandle`、13 个事件）——属 P1-3；本批协议**不含** `onEvent`，加回时需同步所有已写模块（本批只有 1 个内置模块，成本可控，见「已知限制」9）
- **模块存储 / 调度器 / 密钥 / 权限句柄与 `NotchHandle`**——`ModuleStorage` / `ModuleScheduler` / `SecretHandle` / `PermissionHandle` / `NotchHandle`（含几何快照）属 P1-2/P1-3；本批 `ModuleContext` 只给 host/config/logger/ui 五个面
- **视图超时保护与 `degraded` 状态**（06 §3.3 R3 / §4）——依赖 P1-2 的降级状态机，本批 `ModuleRuntimeState` 只有 disabled/activating/active/failed
- **`swift-format` 门禁对 `{Kernel,Modules}` 转 blocking**（ci.yml 现为 advisory）——等内核目录稳定（本批之后）再做，随 P1-2 批次
- **其余"不需要的上游功能"的默认值**——[09](09-features-and-mechanisms.md) §8.1 的口径是"`enableScreenAssistant` **等**开关"，本批只落这一项；其余随 P1-3 的 ConfigStore 统一处理
- **模块自报高度**（preferredHeight）——本批模块内容按上游默认展开尺寸渲染
- **锁屏 surface**——维持上游现状（ADR-0011 第 4 条「锁屏维持现状」）
- **插件运行时**（`xpc` / `js`、`descriptor.json` 加载、`.descriptor` 渲染）——P4
- **设置页自动生成**——P3；本批**没有用户可见的配置入口**（只读 manifest 默认值；`ConfigHandle.set` 的覆盖值落 UserDefaults 临时命名空间，P1-3 迁 ConfigStore，见「已知限制」12）
- **扩展通道线协议名**（B 表冻结项）、**删除任何上游功能**（ADR-0011）

## 实际交付

无（尚未实现——回写时补齐）

## 已知限制

1. **`NotchViews` 不能加关联值**：`DynamicIslandViewCoordinator.swift:108/120` 的 `tabOrder.firstIndex(of:)` 与 `ContentView.swift:1113` 的 `.id()` 依赖它可比较、可哈希；本批用「无关联值 case + coordinator 侧 `selectedModuleID`」绕开。
2. **tab 列表有两份镜像**：`TabSelectionView.tabs`（S1）与 `matters.swift:enabledStandardTabCount()`（S2）必须同步，否则最小刘海宽度算错——这是上游既有技术债，本批不收敛。
3. **`NotchViews` 与 tab 列表已漂移**：`.colorPicker` case 存在但全仓库无人写 `currentView = .colorPicker`，`enableColorPickerFeature` 声明后从未被 `tabs` getter 使用（死代码）。
4. **展开高度有两条重复实现**：`DynamicIslandApp.swift:471-561` 与 `ContentView.swift:98-210` 各算一遍尺寸；模块高度接入需要同时动两处，本批因此不做。
5. **hover 与拖拽不是状态**：`isHovering` 是 `ContentView.swift:214` 的 `@State private`（类外不可观测）；拖拽只有 `dragDetectorTargeting` / `anyDropZoneTargeting` 布尔量，且折叠态拖拽被 `Defaults[.dynamicShelf] && !enableMinimalisticUI` 门控（`ContentView.swift:1866`）。四态里的 `hoverPreview` / `dragging` 在本批**不可达**。
6. **几何与状态是两条并行发布链**：`ViewModel.open()` 先 `ensureWindowSize`（`:371-384`）再改 `notchState`（`:387`），且 `DynamicIslandViewModel.swift:146-283` 有 7 个 sink 在 `.open` 期间自行改 `notchSize`——任何状态机都必须容忍"同态内尺寸变化"。
7. **模块内容视图的 `.id()` 过渡**：S5 若不把模块 id 并入 `.id()`，两个模块间切换不会重放过渡动画。
8. **CI 单测仍不可用**（advisory，见 [11](11-verification.md) §5）：本批所有单测以本地 `xcodebuild test` 为准。
9. **协议的加回有破坏面**：本批的 `GourdModule` 不含 `onEvent`、`ModuleContent.descriptor` 不带 payload——P1-3（事件）与 P4（插件）加回时必须同步所有已写模块与 `ModuleHostView` 的 switch；本批只有 1 个内置模块，代价可控，但**后续批次应尽早补齐，不宜堆积**。
10. **引导流程会覆盖 D-08 的默认值**：`ProfileSelectionView.swift:214` 在用户选 developer profile 时会把 `enableScreenAssistant` 写回 `true`。本批不动引导（避免扩大上游改动面），因此「首启关闭」在用户走完引导选开发者档后可能失效——需在 P1-3 的 ConfigStore 里统一口径，或由用户在设置页确认一次。
11. **`ModuleRuntimeState` 无 `degraded`**：与 06 §4 的状态机相比缺降级态与运行期超时计数（见「明确不做」），本批的失败隔离只覆盖 `activate()` 抛错。
12. **配置覆盖值的临时落点**：本批的 `ConfigHandle.set` 写 `UserDefaults(suiteName: "com.cmeng.gourd.module.<shortID>")`，而 P1-3 的 `ConfigStore` 定为「JSON + schemaVersion + 迁移链」（[07](07-config-and-events.md) §2）。本批**没有用户可见的配置入口**（只有 manifest 默认值会被读取），因此这次迁移在 P1-3 一并做，届时需写迁移：UserDefaults 覆盖值 → config.json。
13. **`config` 子集与 06 §5 的类型差异**（同名字段换型是漂移起点，故记在此）：`ConfigNode.values` 是 `[String]?`，而 06 §5.3 的 enum 取 `[{value,title,icon?}]`；`itemType` 未收在 06 的 `string|integer|appPicker` 内；`ConfigSchema` 无 `required`，也不做 06 §5.1 的「未知关键字 → `E_INVALID_SCHEMA`」校验。P1-3 落地完整 ConfigStore 时必须一并升级并同步已写模块（本批只有 progress）。
14. **刷新粒度是粗粒度**：progress 模块用 `TimelineView(.periodic(from: .now, by: 60))` 统一按 60s 重算，未按 [09](09-features-and-mechanisms.md) §5.3 的字面要求区分粒度（日 1 分钟、周/月/季/年 1 小时），也**未监听 `NSSystemClockDidChange`**——系统的时钟/时区变更最多 60s 内被感知，超过 60s 的时钟跳变会在下一个周期校正。

## 验收标准

| # | 标准 | 判定 |
|---|---|---|
| A1 | 内核单测与既有 27 项全绿 | `xcodebuild test -only-testing:DynamicIslandTests` 退出码 0 |
| A2 | manifest 校验规则有单测（id 正则、每个错误分支至少一例） | 单测用例名可查 |
| A3 | **新增一个空模块 = 实现协议 + 注册一行** | 试点模块的注册改动 diff 为 1 行（`builtinModules` 数组） |
| A4 | **注释掉任意模块后应用仍能启动** | 人工：注释 `progress` 注册行 → 构建 → 启动 → 刘海正常（不崩、tab 少一项） |
| A5 | 试点模块在展开面板可见、可切换、数值正确 | 人工目视 + 单测（进度计算） |
| A6 | 模块 `activate()` 抛错只禁用自己 | 单测：注入一个必抛错的假模块，断言其余模块仍 active |

## 决策摘要

| ID | 决策 | 来源 | 理由 |
|----|------|------|------|
| D-01 | 接缝选「三挂点最小接线」（S1/S5/S6），**不做**折叠态槽位 | agent | 折叠态三槽需重构 `ContentView.swift:1219-1312` HStack，是调研里唯一无法零结构改动处；P1 只求全链路可插拔 |
| D-02 | `NotchViews` 新增**无关联值** case `module`，模块选择走 `coordinator.selectedModuleID` | agent | 关联值会破坏 `tabOrder.firstIndex` 与 `.id()`（限制 1） |
| D-03 | `ModuleRegistry` 仿写 `ExtensionNotchExperienceManager` 的形态（不继承） | agent | 上游已有同构先例，避免发明新接缝类型；继承会把扩展线协议身份绑进来 |
| D-04 | 状态机归属 = **包装/观测**，替换留 P2+；本批只落裁定 | agent | A/B 对照表（改动面、失败模式、收益时点）；P1 结束时新语义无消费者 |
| D-05 | `ModuleContext` 本批只实现四个面 + moduleID（`host` / `config`(简化) / `logger` / `ui`）；`notch`/事件/存储/调度/密钥/权限延后 P1-2/P1-3 | agent | 试点模块（progress）不需要它们；先落最小可用面，避免设计未定的句柄被提前固化（延后面见「明确不做」、加回成本见「已知限制」9） |
| D-06 | `ModuleContent.descriptor` 本批只解析不渲染（渲染路径显示 unavailable 文案） | agent | descriptor 渲染对应上游扩展管线，属 P4 插件层 |
| D-07 | 试点模块选 `progress`，`surfaces: ["expanded"]`，`defaultEnabled: true` | agent（承接 ADR-0012 用户已批准的新增 6 项） | 零私有 API、零依赖、成本最低（[09](09-features-and-mechanisms.md) §5.3）；compact 槽位本批不做故不声明 |
| D-08 | 首启写入 `enableScreenAssistant=false`（一次性、幂等） | 用户 | [09](09-features-and-mechanisms.md) §8.1 已拍板「不需要的上游功能用上游开关默认值表达」；该功能上游默认 `true` 且入口隐蔽（⌘⇧A 悬浮面板，不在刘海 tab 里） |
| D-09 | 模块清单口径 = 15 个模块 + 终端独立条目（共 16 份 manifest），逐项裁定调研标记的 13 处未决口径（T-1…T-13，清单与结论见 [14](14-module-manifests.md)） | 用户（边界）+ agent（裁定） | 边界出自 [09](09-features-and-mechanisms.md) §8.1（用户已拍板）；未决口径在 [14](14-module-manifests.md) 逐条给结论 |
| D-10 | 新代码落 `DynamicIsland/Kernel/` 与 `DynamicIsland/Modules/`，靠同步组自动纳入；测试新增文件需登记 pbxproj 四处 | agent | `project.pbxproj:117-123` 的同步组已覆盖 `DynamicIsland/`；测试目录是普通 group |
| D-11 | 内置模块 id 与本地化 key 沿用 06 §2.2/§2.3：`com.cmeng.gourd.<shortID>`、`module.<shortID>.name` | 用户（[09](09-features-and-mechanisms.md) §8.3 已定命名）+ agent | 逐字沿用已定契约 |
| D-12 | 本批不声明 `lockscreen` surface | 用户 | ADR-0011 第 4 条「锁屏维持现状」 |
| D-13 | 本批的范围边界与实现面裁剪，由 agent 依调研证据裁定：① 不做折叠态槽位（D-01）② 不做状态机实现（D-04）③ 不声明锁屏（D-12）④ `ModuleContext` 只做四面 + moduleID（D-05）⑤ `ModuleContent.descriptor` 不带 payload（D-06）⑥ 试点模块默认启用（D-07）⑦ 13 处未决口径的逐项结论（D-09）⑧ 首启默认值只落一项（D-08 范围）。用户在本会话明确授权「两道门不需要审阅，直接执行」 | 用户 | 用户授权自主执行；每条裁定的证据落在本文件「备选与取舍」「已知限制」，无不可逆改动（后续批次可回退），且**加回路径已逐条写明**（「明确不做」与「已知限制」9/10/11/12） |
| D-14 | 平台依赖台账与 ATS 域名清单的收录口径：私有 API 11 项逐条带降级路径；子进程含新增 `/usr/bin/shortcuts`；域名清单 = `grep -rn '"https\?://'` 结果**并集**源码内插值域名（如 `MusicManager.swift:1525` 的 `lrclib.net`），每条指向 file:line | agent | 实测：正则要求 URL 后紧跟引号，漏掉插值字符串里的域名；把「清单 = 命令结果 ∪ 插值域名」写死可避免这份台账天生不全 |
