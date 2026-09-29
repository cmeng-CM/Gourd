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
    // 实现另有带默认值的 `public init`（GourdModule.swift:52-66，slot/sizeHint/isLowPower 可省）
    // ——这是 ModuleHostView 只传 surface/phase/reason 三个参数的原因。
}
public enum ModuleContent {                // 06 §3.2 的本批子集
    case view(AnyView)
    case descriptor                  // 占位：本批无关联值、不渲染（P4 加回 payload，见「已知限制」）
    case unavailable(reason: String)
    case none
}

// ===== DynamicIsland/Kernel/ModuleContext.swift（本批实现子集，D-05）=====
// 本批 `ModuleContext` 只给 **moduleID + 四个句柄**（host/config/logger/ui）；
// 其余**七个面**（notch/permissions/events/storage/scheduler/secrets/clock）延后——它们需要
// per-screen 的 DynamicIslandViewModel 或未定的设计（P1-2/P1-3），试点模块不需要，故按 D-05 延后；
// 延后项与加回时的破坏面见「明确不做」与「已知限制」。
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
    func presentTransient(view: AnyView, ttl: TimeInterval)   // D-22：瞬时浮层（实现落点 = 注册表）
    func dismissTransient()                // D-22 后续：撤本模块**自己**那条浮层（先判归属）
    func requestCollapse()                 // D-28：请求收起刘海（**06 §3.4 `NotchHandle.requestCollapse` 的过渡实现**；
                                           // 内核只转发应用侧注入的闭包，模块仍不得自己碰窗口）
}
public final class ModuleLogger: @unchecked Sendable {   // 自动带 moduleID 与 subsystem 前缀 com.cmeng.gourd.module.<shortID>
    public func info(_ message: String); public func warn(_ message: String); public func error(_ message: String)
}
// 实现者：DynamicIsland/Kernel/ModuleContextFactory.swift（T2 交付）
@MainActor
public enum ModuleContextFactory {
    public static func make(
        manifest: ModuleManifest,
        redraw: @escaping () -> Void,
        collapse: @escaping () -> Void = {}   // D-28：应用侧注入（默认 `{}` = 未接线时空操作）
    ) -> ModuleContext
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
    public func deactivateAll() async              // **回写补充**：实际语义是「停用 + 清空注册表四张表」
                                                   // （instances/states/manifests/moduleTypes），单测靠它做用例隔离；
                                                   // 名字只表达了前一半，P1-3 若需要"停用但保留注册"须另加接口
    public func instance(for id: String) -> (any GourdModule)?
    public var tabEntries: [ModuleTabEntry]        // 仅 active 且 surfaces 含 .expanded，按 order 升序（同 order 按 id 字典序）；
                                                   // label 的解析链：LocalizedText.key → en 表 → shortID（回写补充最后一级）
    public func content(for id: String, request: ContentRequest) -> ModuleContent
    // D-22 的瞬时浮层（`@Published activeHUD` + `presentHUD` / `clearHUD` / `dismissHUD`）仍在这一层：
    // **渲染面已换成 D-23 的独立窗口宿主**（`ModuleHUDWindowHost`），关闭态内容链里不再有浮层分支。
}

// ===== DynamicIsland/Kernel/KernelBootstrap.swift（组合根）=====
@MainActor
public enum KernelBootstrap {
    public static func bootstrap() async           // **回写补充**：除了注册内置模块与首启默认值，
                                                   // 还调用 registry.bootstrap() 完成激活（否则模块永不生效）
    static let builtinModules: [any GourdModule.Type]     // ← 新增模块 = 往这个数组加一行（当前 [ProgressModule.self]）
    static func applyFirstLaunchDefaults()         // enableScreenAssistant=false，一次性（幂等键 gourdFirstLaunchDefaultsApplied）
}

// ===== DynamicIsland/Kernel/ModuleHUDWindow.swift（D-23 建立 / D-24 固定尺寸 / D-25 每屏一个窗口）=====
// 瞬时浮层**不再**渲染在关闭态链里：关闭态面板窗口的尺寸 = 折叠态刘海尺寸，浮层会被裁剪
// （内置屏）或过小（外接屏）。窗口归内核所有（06 §3.3 R1），`ModuleHUDView` 是它的根视图。
// 内容宿主是内核自己的 `NSHostingView` 子类（不是上游的 `FirstMouseHostingView`）：多两个补丁
// ——`acceptsFirstMouse`（同上游口径，× 点一下就生效）与 `layout()` 回调（每次内容布局完做一次
// 幂等收尾：校正尺寸 + 显隐纠正 + 重新贴顶）。**两条实测坑**：① `@Published` 在 willSet
// 里发值，订阅回调拿到的入参是「将要生效」的值（此刻注册表里还是旧值）→ 回调统一挪到下一拍
// 读真值；② 尺寸只能等内容布局之后才算得出来（D-23 用 `fittingSize`，首条浮层量到 0×0 完全不显示；
// **D-24 起窗口是固定尺寸，`fittingSize` 那条链已删除**）。
@MainActor
public final class ModuleHUDWindowHost {
    public static let shared: ModuleHUDWindowHost
    public func start()                                          // 订阅 `ModuleRegistry.$activeHUD` + `didChangeScreenParametersNotification`（应用启动挂一次，幂等）
    static let topGap: CGFloat                                   // 8pt：窗口顶端距该屏可用顶边的间隙
    static let fadeInDuration: TimeInterval                      // 0.15s
    static let fadeOutDuration: TimeInterval                     // 0.2s（淡出后 orderOut；不维护 ttl——ttl 在注册表）
    static let cardBaseSize: CGSize                              // 320 × 64（固定尺寸基准，× 倍率）
    static let hudScaleRange: ClosedRange<Double>                // 0.8…2.0（与设置滑块同源）
    static let preferredScreenDefaultsKey: String                // "preferred_screen_name"（单屏模式读上游同一个键）
    static func contentSize(scale:) -> CGSize                    // 固定尺寸 = 基准 × 夹取后的倍率（纯函数，唯一来源）
    static func targetScreenNames(showOnAllDisplays:screenNames:mainScreenName:preferredScreenName:) -> Set<String>  // 该在哪些屏上显示（纯函数，D-25）
    static func topInset(safeAreaTop:frameMaxY:visibleFrameMaxY:) -> CGFloat   // 刘海高度 或 菜单栏高度（纯函数）
    static func origin(windowSize:screenFrame:topInset:topGap:) -> CGPoint     // 居中于该屏 + 顶端贴顶（纯函数）
    // 每屏一个 `NSPanel`，键 = `NSScreen.localizedName`（`slots: [String: PanelSlot]`）：
    // present → 逐屏「设尺寸 + 状态机动作」；dismiss → 逐屏淡出后 orderOut；屏变化 → 清理断开屏 + 补新屏。
}
```

**接缝的精确改动**（上游文件，只接线）：

| # | 文件:位置 | 改动 |
|---|---|---|
| S1 | `components/Tabs/TabSelectionView.swift:65-115` 与 `:118-152` | ① 加 `@ObservedObject private var moduleRegistry = ModuleRegistry.shared`（**必须**——否则注册表变化后 tab 列表不重绘；同文件已有 `@ObservedObject private var extensionNotchExperienceManager` 的先例）；② `tabs` getter 末尾追加 `for e in ModuleRegistry.shared.tabEntries`；③ 选中判定改为 `tab.view == .module ? coordinator.selectedModuleID == tab.experienceID : coordinator.currentView == tab.view`；④ **点击路径**（`:123-128` 的 action，照 `:124-125` 对 extensionExperience 的写法同构）：`if tab.view == .module { coordinator.selectModule(tab.experienceID ?? "") }`——只设 `currentView = .module` 而不设 `selectedModuleID` 会让内容区渲染 EmptyView。**回写补充**：实到还在 `ensureValidSelection`（`:211-213`）加了同构的 module 分支（把"当前视图是 `.module`"与 `selectedModuleID` 一起校验），比原计划多 2 行 |
| S2 | `sizing/matters.swift:101-135` | `enabledStandardTabCount()` 加 `ModuleRegistry.shared.tabEntries.count`，并把该函数与其调用链（`currentRecommendedMinimumNotchWidth()` `:145`、`openNotchSize` `:69`、`enforceMinimumNotchWidth()` `:152`）标 `@MainActor`（同文件 `minimalisticOpenNotchSize` `:173` 已有先例）。**回写更正**：原计划的"`DynamicIslandViewCoordinator.swift:243/248` 是非隔离调用点、需 `MainActor.assumeIsolated`"**前提失实**——该类的主 actor 身份来自 `@Default` 属性包装器（`Defaults` 包声明为 `@MainActor`，见 `DynamicIslandViewCoordinator.swift:140-141` 的两处 `@Default`）在 Swift 5 模式下的整类推断，两处调用点本就在隔离上下文内（全量编译零诊断，实测见工作流账本 T3 审查），故**未加** `assumeIsolated`（加了反而会把"`shared` 被非主线程首次触达"变成运行时陷阱）。**前向风险**：SE-0401 生效（Swift 6 语言模式）后包装器推断消失，该类将变为非隔离，两处调用与 `BluetoothAudioManager.swift:41` 都会成为硬错误——最小修法是给该类显式加 `@MainActor` |
| S3 | `enums/generic.swift:73-84` | `NotchViews` 追加**无关联值** case `module`（D-02：加关联值会破坏 `tabOrder.firstIndex` 与 `.id()`） |
| S4 | `DynamicIslandViewCoordinator.swift:103-135` | 新增 `@Published var selectedModuleID: String?`；`tabOrder` 追加 `.module`；新增 `func selectModule(_ id: String)`（设 `selectedModuleID` + `currentView = .module`） |
| S5 | `ContentView.swift:1083-1113` | switch 加 `case .module: ModuleHostView(moduleID: coordinator.selectedModuleID)`（无选中时 `EmptyView`）；`.id(coordinator.currentView)` 改为含模块 id 的复合值，否则模块间切换不重放过渡。**回写补充**：实到用私有结构体 `ExpandedContentIdentity(view:moduleID:)`（`ContentView.swift:297-303`）承载这个复合值，而非计划里说的字符串拼接 |
| S6 | `DynamicIslandApp.swift:684` | `Task { await KernelBootstrap.bootstrap() }`（紧邻既有的 4 个同构 `Manager...shared.setup(...)` 调用；该行是全仓库唯一的 `bootstrap()` 生产调用点，审查期用"删除闸门键 → 复跑 → 键回到 1"独立取证过它确实执行） |
| S7 | `models/Constants.swift` | 追加 1 个 Key：`gourdFirstLaunchDefaultsApplied`（Bool, default false） |
| S8 | `DynamicIslandApp.swift:684` 与 `453-477`（**D-23 追加**） | 启动调用 `ModuleHUDWindowHost.shared.start()`（紧邻 S6 的 `Task { await KernelBootstrap.bootstrap() }`；`AppRuntimeEnvironment.isUITesting` 时跳过，与相邻的 `ScreenRecordingManager` / `PrivacyIndicatorManager` 一族同口径）。同一提交里 `ContentView.swift` **删掉**关闭态链的浮层分支、并去掉 `shouldHideClosedContentUntilHover` 的 `hasModuleHUD` 形参（浮层不再占关闭态那一格） |

**新增文件与被工程纳入的方式**：`DynamicIsland/` 是 `PBXFileSystemSynchronizedRootGroup`（`project.pbxproj:117-123`），**新目录 `Kernel/`、`Modules/` 下的文件自动进入 app target，无需改 pbxproj**。但 `DynamicIslandTests/` 是**普通 PBXGroup**（`:177-188`），新测试文件必须显式登记**四处**：`PBXFileReference` + `PBXBuildFile` + group `children` + test target 的 `Sources`（参照既有 `FlyoutFrameCalculatorTests.swift` 的四条记录，`:35`/`:83`/`:180` 与 Sources 段）。本批测试全部写进**一个**新文件 `DynamicIslandTests/ModuleKernelTests.swift`，把 pbxproj 编辑压到一次；新对象 ID 用不与既有冲突的 24 位十六进制（既有 ID 形如 `C0DEFACE1234567890ABCDEF`）。

## 明确不做

- **折叠态槽位渲染**——**只做中央槽位**（2026-09-27 落地：D-19 / 已知限制 26）；左/右图标槽位与 06 §6.2 的三槽布局（含每侧上限）仍需重构 `ContentView.swift:1219-1312` 的 HStack，仍推 P2
- **状态机实现**——本批只落归属裁定（D-04）；`NotchStateMachine` 与四态迁移单测属 P1-2
- **`isHovering` 提升为可观测量**——D-04 认定的唯一必要上游编辑，留给 P1-2（本批没有 hover 相位的消费者）
- **事件总线与订阅**（`GourdModule.onEvent`、`EventHandle`、13 个事件）——属 P1-3；本批协议**不含** `onEvent`，加回时需同步所有已写模块（本批只有 1 个内置模块，成本可控，见「已知限制」9）
- **模块存储 / 调度器 / 密钥 / 权限句柄与 `NotchHandle`**——`ModuleStorage` / `ModuleScheduler` / `SecretHandle` / `PermissionHandle` / `NotchHandle`（含几何快照）属 P1-2/P1-3；本批 `ModuleContext` 只给 **moduleID + 四个句柄**（host/config/logger/ui），其余**七个面**（notch/permissions/events/storage/scheduler/secrets/clock）延后
- **视图超时保护与 `degraded` 状态**（06 §3.3 R3 / §4）——依赖 P1-2 的降级状态机，本批 `ModuleRuntimeState` 只有 disabled/activating/active/failed
- **`swift-format` 门禁对 `{Kernel,Modules}` 转 blocking**（ci.yml 现为 advisory）——等内核目录稳定（本批之后）再做，随 P1-2 批次
- **其余"不需要的上游功能"的默认值**——[09](09-features-and-mechanisms.md) §8.1 的口径是"`enableScreenAssistant` **等**开关"，本批只落这一项；其余随 P1-3 的 ConfigStore 统一处理
- **模块自报高度**（preferredHeight）——本批模块内容按上游默认展开尺寸渲染
- **锁屏 surface**——维持上游现状（ADR-0011 第 4 条「锁屏维持现状」）
- **插件运行时**（`xpc` / `js`、`descriptor.json` 加载、`.descriptor` 渲染）——P4
- **设置页自动生成**——P3；本批**没有用户可见的配置入口**（只读 manifest 默认值；`ConfigHandle.set` 的覆盖值落 UserDefaults 临时命名空间，P1-3 迁 ConfigStore，见「已知限制」12）
- **扩展通道线协议名**（B 表冻结项）、**删除任何上游功能**（ADR-0011）

## 实际交付

**交付物清单**（提交范围 `d77f358..4108ca6` 共 4 个实现提交 + 文档批次；每项都有独立审查）：

| # | 交付物 | 落点 |
|---|---|---|
| 1 | **内核类型层** | `DynamicIsland/Kernel/{ModuleTypes,ModuleManifest,GourdModule,ModuleContent,ModuleContext}.swift`（含 `ConfigValue/ConfigNode/ConfigSchema` 自定义 Codable、`ModulePermissionCatalog` 15 项与 06 §7.1 逐字一致、`ModuleManifestError` 九分支） |
| 2 | **注册表与组合根** | `DynamicIsland/Kernel/{ModuleRegistry,ModuleContextFactory,KernelBootstrap}.swift`（失败隔离、tab 投影、首启默认值） |
| 3 | **接缝接线** | 7 个上游文件按 S1–S7 改（`TabSelectionView` / `matters` / `generic` / `DynamicIslandViewCoordinator` / `ContentView` / `DynamicIslandApp` / `Constants`）+ `DynamicIsland/Kernel/ModuleHostView.swift` |
| 4 | **试点模块 progress** | `DynamicIsland/Modules/{ProgressModule,ProgressCalculator}.swift` + `KernelBootstrap.builtinModules` 恰一行 + `Localizable.xcstrings` 两条 key |
| 5 | **单元测试** | `DynamicIslandTests/ModuleKernelTests.swift`（19 → 32 用例；总数 27 → **59** 全绿） |
| 6 | **文档** | 本文件 + [14-module-manifests.md](14-module-manifests.md)（16 行 manifest 清单 + 13 处未决口径裁定）+ [15-platform-dependencies.md](15-platform-dependencies.md)（私有 API 台账 11 条 + 子进程 17 项 + 域名清单） |

**与计划的偏离及原因**：

1. **S2 的 `MainActor.assumeIsolated` 未执行**——计划的前提（coordinator 的两个调用点非隔离）经实测失实，该类已由 `@Default` 包装器推断为主 actor；加 `assumeIsolated` 反而有害。已在 S2 行回写更正并记录 Swift 6 前向风险。
2. **S1 实到多 2 行**（`ensureValidSelection` 的 module 分支）、**S5 用私有结构体** `ExpandedContentIdentity` 而非字符串拼接——都是实现期发现的必要修正，已在对应行回写。
3. **T1 的 `validate()` 顺序注释**在审查后修正为"本批自定、未对齐 06 §10.1"（原注释声称照 §10.1）。
4. **T5/T6 文档的 8 处精度问题**在审查后修正（含一处被实验证伪的方法论断言）。

**遗留项**（交接给后续批次）：

- 已知限制 15–25（三类 manifest 校验、`validate()` 顺序、register 不校验、本地化债、日志噪音、陈旧 `selectedModuleID`、progress 配置消费者缺口、单测批内契约、百分比取整、三个待落 capability、`defaultPlacement.order` 兼作 expanded tab 排序键）
- [14-module-manifests.md](14-module-manifests.md) 的 13 处裁定（T-1…T-13）需要在 P2a/P2b 逐条落地时复核
- **P1-2 起手项**：`NotchStateMachine`（纯逻辑 + 四态单测）、`isHovering` 提升为可观测量、模块自报高度、视图超时保护与 `degraded`、`swift-format` 门禁对 `{Kernel,Modules}` 转 blocking
- **P1-3 起手项**：`EventHandle`（含 `onEvent` 加回，破坏面见已知限制 9）、`ModuleStorage`/`ModuleScheduler`/`SecretHandle`/`PermissionHandle`/`NotchHandle`、完整 `ConfigStore(JSON)` 与 UserDefaults 覆盖值迁移（已知限制 12）、06 §7.1 补三个 capability

---

## 本批（p2-home-strip，2026-09-29）新增 / 变更的口径

> 本批的设计文档是 [17-nookx-adoption.md](17-nookx-adoption.md)（决策编号 D-01…D-14 属**该文件**，与本文 D-01…D-30 **不是同一套编号**，引用时写清文件）。本节只记落到内核面（协议 / 注册表 / 组合根 / 偏好键）的口径；渲染与布局规格见 [09](09-features-and-mechanisms.md) §5.8。

**1. `Surface.home`（协议层，[06](06-module-protocol.md) §6.1 的第四个取值）**

```swift
public enum Surface: String, Codable, Sendable, CaseIterable { case compact, expanded, lockscreen, home }
```

- **校验规则不变**：`surfaces` 仍是非空子集；元素合法性由 `Codable` 解码保证，`ModuleManifest.validate()` 仍只管"非空"这一条（它不认识有哪些取值）。
- **`home` 与 `compact` / `expanded` 并列**：声明它 = "愿意在首页 strip 占一块"，与"有没有展开 tab"互不蕴含。
- **不新增 `hud` 之类的 surface**：瞬时浮层仍是 `expanded` 的一种呈现方式（06 §6.1 原文，本批未动）。

**2. `ModuleRegistry.homeEntries`（注册表的第三条投影）**

```swift
public struct ModuleHomeEntry: Identifiable, Equatable {
    public let id: String
    public let label: String        // 复用 label(for:) 的解析顺序
    public let symbolName: String
    public let order: Int           // defaultPlacement.order，缺省 Int.max
}

/// active 且 surfaces 含 .home，排序键 (order, id)——与 tabEntries / compactEntries 同一比较器
public var homeEntries: [ModuleHomeEntry] { get }
```

- **声明与内容分离**：投影是"声明"（manifest 说愿意占一块），`content(for: .home)` 是"表态"（这一刻有没有东西可画）。宿主侧再过滤一次答 `.none` 的条目——**投影层不做这件事**，否则一次 `.none` 会影响后续刷新。
- **与另两条投影一样不做缓存**：每次读都现算（`manifests` / `states` 都是 `@Published` 的派生量，缓存会让"注册后 / 激活后 / 停用后"三个时刻的视图不一致）。
- `defaultPlacement.order` 由此**第三次**被当作排序键（前两次是 expanded tab 与 compact 槽位），双语义现状见已知限制 25；首页块顺序不新增字段（[17](17-nookx-adoption.md) D-04）。

**3. `ModuleRegistry.setEnabled(_:for:)` 的状态机**

```swift
/// 置开：与 bootstrap() 同一条实例化 + activate 路径；置关：deactivate 后摘除实例。
/// 幂等；failed 是终态，置开不再重试。返回迁移后的状态（供卡片回弹）。
@discardableResult
public func setEnabled(_ enabled: Bool, for id: String) async -> ModuleRuntimeState
```

| 入口状态 | 置开 | 置关 |
|---|---|---|
| 未注册 id（`manifests[id] == nil`） | 记 warning、返回 `.disabled`（不崩、不凭空造状态） | 同左 |
| `.active` / `.activating` | **原样返回**（幂等，不重复实例化） | `.active` → `deactivate()` + 摘实例 + 落 `.disabled`；`.activating` → 落 `.disabled`（其收尾由**代次比对**拦下，不写回任何状态） |
| `.failed` | **原样返回**（终态不重试，06 §3.3 硬性规则 1） | **原样返回**（不改状态、不碰实例） |
| `nil`（已注册未判定）/ `.disabled` | 走 `activateIfNeeded`（返回时通常是 `.active` / `.failed`；并发下可能拿到 `.activating`，调用方按"进行中"处理即可） | 落 `.disabled`（幂等） |

三条硬口径：

- **`failed` 不可逃逸**（[17](17-nookx-adoption.md) D-13）：置关**不把它降级成 `.disabled`**。写成 `disabled` 会让下一次置开真的重试，与 06 §3.3 硬性规则 1「`failed` 不重试」矛盾——也就是说**没有"关一下再打开"这条复活路径**，等价于"要恢复只能重启应用"（原本就写下的口径，现在代码也守它）。设置页的开关在 `.failed` 上同时**禁用点击**，失败回弹只把偏好写回 `false`、绝不再调 `setEnabled(false)`。
- **代次作废 `.activating` 期间的状态写回**：`activate()` 完成时比对 `activationGeneration[id]`，不匹配就**不写 `states` / `instances`**（只记一条日志）。取号器**全局单调、不回退**，因此同一 id 重新注册也拿不到旧号（无 ABA）。这是"置关之后那条在飞的 `activate()` 不会把状态改回 `.active`"的机制。
- **只改内存状态、不写偏好**：`Defaults[.moduleEnableOverrides]` 由设置页负责落盘，内核不知道"用户偏好"这一层。每次调用记一条 `os.Logger`（`setEnabled(id:on:from:to:)`），便于排查"关了还在跑"。

**4. `Defaults[.moduleEnableOverrides]` 的缺键语义**

```swift
// DynamicIsland/models/Constants.swift（// MARK: Module Kernel (P1) 段，键定义在 :1526）
/// 组件开关的用户显式选择。**缺键 = 用户未表达**（回落到 manifest.defaultEnabled），
/// 不是 false——升级用户的首次行为必须与升级前一致。
static let moduleEnableOverrides = Key<[String: Bool]>("moduleEnableOverrides", default: [:])
```

用**一个字典**而不是"每个模块一个键"：后者会凭空产生 17 个键与第二份真源（[17](17-nookx-adoption.md) D-05）。写入是全字典读改写（与既有字典型 `Defaults` 写入同形），只在用户真的动了开关时写键。

**5. `KernelBootstrap.enablementGate(registry:)`（组合根的启用门）**

```swift
/// 键在 `moduleEnableOverrides` 里就取键值（用户显式表达，压过 manifest），
/// 否则取 manifest.defaultEnabled，否则 false
static func enablementGate(registry: ModuleRegistry) -> (String) -> Bool

registry.register(builtinModules, enabled: enablementGate(registry: registry))
```

`register` 的签名不变（门仍是注入的闭包），**变化只在组合根传什么闭包**：由"纯 manifest 默认值"改为"先看用户显式选择，再回落 manifest"。偏好键的**消费点唯一**就是这里。

**6. 零新增权限 / 零出站请求**：没有新 capability、没有新 TCC 授权、没有新网络请求。首页块都是进程内视图，组件开关只写本机偏好（06 §7.1 词表 15 项本批未动）。

---

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
10. **引导流程会覆盖 D-08 的默认值**：`ProfileSelectionView.swift:214` 在用户选 developer profile 时会把 `enableScreenAssistant` 写回 `true`。本批不动引导（避免扩大上游改动面），因此「首启关闭」在用户走完引导选开发者档后可能失效——需在 P1-3 的 ConfigStore 里统一口径，或由用户在设置页确认一次。**另需注意本版本的「首启默认值」对既有安装同样生效**：闸门键 `gourdFirstLaunchDefaultsApplied` 是本批新引入的（默认 `false`），所以**升级后首次运行也会写入** `enableScreenAssistant = false`，即会覆盖老用户此前的显式开启。若日后要区分「真正全新安装」，可复用仓内已有的 `@AppStorage("firstLaunch")`（`DynamicIslandViewCoordinator.swift:135`，默认 `true`）；**本批不改行为**，只记录。
11. **`ModuleRuntimeState` 无 `degraded`**：与 06 §4 的状态机相比缺降级态与运行期超时计数（见「明确不做」），本批的失败隔离只覆盖 `activate()` 抛错。
12. **配置覆盖值的临时落点**：本批的 `ConfigHandle.set` 写 `UserDefaults(suiteName: "com.cmeng.gourd.module.<shortID>")`，而 P1-3 的 `ConfigStore` 定为「JSON + schemaVersion + 迁移链」（[07](07-config-and-events.md) §2）。本批**没有用户可见的配置入口**（只有 manifest 默认值会被读取），因此这次迁移在 P1-3 一并做，届时需写迁移：UserDefaults 覆盖值 → config.json。
13. **`config` 子集与 06 §5 的类型差异**（同名字段换型是漂移起点，故记在此）：`ConfigNode.values` 是 `[String]?`，而 06 §5.3 的 enum 取 `[{value,title,icon?}]`；`itemType` 未收在 06 的 `string|integer|appPicker` 内；`ConfigSchema` 无 `required`，也不做 06 §5.1 的「未知关键字 → `E_INVALID_SCHEMA`」校验。P1-3 落地完整 ConfigStore 时必须一并升级并同步已写模块（本批只有 progress）。
14. **刷新粒度是粗粒度**：progress 模块用 `TimelineView(.periodic(from: .now, by: 60))` 统一按 60s 重算，未按 [09](09-features-and-mechanisms.md) §5.3 的字面要求区分粒度（日 1 分钟、周/月/季/年 1 小时），也**未监听 `NSSystemClockDidChange`**——系统的时钟/时区变更最多 60s 内被感知，超过 60s 的时钟跳变会在下一个周期校正。
15. **manifest 校验是子集，三类校验未实现**（[06](06-module-protocol.md) §10.1/§2.2/§7.1 有规定而本批未做）：① 未知字段 → `E_UNKNOWN_FIELD`（拼错的字段会被静默接受，与 06 §10.2 末句"静默跳过坏字段等于把拼错的声明变成看起来申请了但没生效"的口径相抵）；② `version` 的严格 semver；③ `permissions` 的**参数形态**（`network:<host>` 的小写域名/禁 IP/禁端口规则、`events:subscribe:<event>` 的事件名存在性）——本批只做白名单集合校验，词表 15 项与 06 §7.1 逐字一致。三者的加回批次：②③ 随 P1-3 的完整 ConfigStore/权限门控，① 至少要在有第二个内置模块之前。
16. **`validate()` 的校验顺序是本批自定**，未逐字对齐 06 §10.1（实际顺序：`manifestVersion → id → 保留前缀 → kind → icon → name/summary → surfaces → apiVersion → permissions`）。差异只影响**多错并存时报出哪一个**，不影响任一单项判定。
17. **`ModuleRegistry.register()` 不调用 `validate()`**：内置模块的 manifest 是代码字面量，正确性由单测（`validate()` 用例 + 往返 + 符号表三条）与审查期独立探针兜住。加第二个内置模块前建议补一条 dev-only 断言。
18. **本地化债**：本批只加了 `module.progress.name` / `module.progress.summary` 两条 key；`ModuleHostView` 的 `.descriptor` 与 `.unavailable` 分支文案**未本地化**（后者用 `Text(String)` 非本地化初始化器）。P3 的双语批次一并处理。（2026-09-27 补充：进度模块重做时加了 9 条 key——`module.progress.scope.<scope>` / `.remaining` / `.unit.<day|hour|minute>`；`ModuleCompactSlotView` 的两条降级文案仍**未本地化**，属同一笔债。）
19. **日志噪音**：`ModuleRegistry.content(for:)` 对未知/非 `active` 模块每次调用记一条 warning，而 `ModuleHostView.body` 每次重算都会调它——选中 `.module` 且模块非 active 时会按渲染频率刷日志。
20. **`selectedModuleID` 在切走 `.module` 后不清空**：当前无功能影响（所有读取处都带 `currentView == .module` 前置），但展开内容的复合身份会携带陈旧模块 id；后续统一清理。
21. **progress 的配置项有两个缺口**：`baseCalendar` 已声明**无消费者**；`style` / `visibleScopes` 的坏值回落分支无测试覆盖。本批没有用户可见的配置入口，故无用户影响；P1-3 落配置入口时必须接上，否则会出现「有控件、无效果」。
22. **单测里 `builtinModules.count == 1` 是批内契约**：加第二个内置模块时该断言会红，需放宽为 `contains`。同一用例里还有一条 `ObjectIdentifier` 逐项相等断言（`ModuleKernelTests.swift:896-900`，断言数组恰为 `[ProgressModule.self]`），加第二个模块时**同样会红**，需一并放宽。**（2026-09-28 已按本条执行）**：T5 加 `TodosModule` 时两处一并放宽——现断言 `count == 2` 与 `[ProgressModule, TodosModule]`，并把该用例扩成「真启用门（progress 默认关 / todos 默认开）+ 手动全放行保 progress 内容路径」两段（见 D-20）。
23. **百分比取整的临景观感**：`Int((progress*100).rounded())` 在区间末段会显示 `100%`（如 12-31 23:59:30 的年进度）。
24. **三个新 capability 待落 [06](06-module-protocol.md) §7.1**：`notifications:read`（读通知中心）、`network:local`（LocalSend 局域网）、`calendar:read-titles`（07 §3.5 已引用但 06 §7.1 缺表）——已在 [14-module-manifests.md](14-module-manifests.md) 相应行标注。
25. **`defaultPlacement.order` 本批兼作 expanded tab 的确定性排序键**（对 06 §6.2 的语义扩展）：06 §2.2/§6.2 规定 `defaultPlacement` 仅当 `surfaces` 含 `compact` 时有意义、否则忽略，而 progress 本批未声明 `compact`（D-07），实现仍用 `manifest.defaultPlacement?.order ?? Int.max` 给 `tabEntries` 排序（`ModuleRegistry.swift:165`）。理由：本批没有 compact 消费者，而 tab 列表需要确定性顺序（同 `order` 再按 id 字典序）。代价：一个字段承载双关语义（"compact 槽位的插入序"与"expanded tab 排序键"）。**约束**：compact 槽位在 P2 落地时**必须**拆字段或明确写下双语义，否则同一个 `order` 会被两套布局逻辑读走；在此期间 progress 的 `slot` 恒为 nil（`Placement(slot: nil, order: 30)`，与 [14](14-module-manifests.md) 的 T-1 给折叠态预留的 `left` / order 40 不是同一个值）。**落地回写（2026-09-27）**：中央槽位走「明确写下双语义」这条路——`order` 同时是 expanded tab 与折叠态槽位候选的排序键，两处共用同一个比较器 `(order, id)`（`ModuleRegistry.swift` 的 `tabEntries` / `compactEntries`），`slot` 只记归属（progress 现为 `center`）；左/右槽位与三槽布局仍延后，若届时同一 `order` 要表达两套布局顺序，仍须拆字段。**第三次复用（p2-home-strip，2026-09-29）**：首页 strip 的块顺序**也**用同一个 `order`——`ModuleRegistry.homeEntries` 的排序键与 `tabEntries` / `compactEntries` **逐字同一个比较器** `(order, id)`（[17](17-nookx-adoption.md) D-04 明确不新增排序字段）。因此 `order` 现同时供**三处**排序（expanded tab / compact 槽位候选 / 首页块），三处共用 `(order, id)`；已知限制 31 的"尾部丢块"丢的是 strip 数组尾部——内置三块固定排在模块块之前（[09](09-features-and-mechanisms.md) §5.8），故模块块段按 `(order, id)` 大的一端先丢。

26. **折叠态中央槽位与 live activity 共用一条优先级链**：槽位是在 `ContentView` 关闭态的 `if/else if` 链里插的**低优先**分支（D-19 的落地方式，分支位置在 `showNotHumanFace` 人脸动画之前），因此**只在其它 live activity 都没占用关闭态时**显示——音乐 / 计时器 / 提醒 / 录屏 / 下载 / LocalSend / 专注 / 锁屏 / 隐私 / Shelf / 扩展载荷任意一个出现，槽位就自动让位（不叠加、不缩窄）。这是「不改 HStack 结构」的代价；真并存（左侧图标 + 中央模块 + 右侧图标）仍要等三槽布局。

27. **瞬时浮层是独立窗口，不再与岛内容同层**（2026-09-28 改口径，D-23；此前的「与优先级链共用一格」三条后果随之作废）：① 浮层**不再占用关闭态那一格**——被它盖住的 live activity 照常显示（音乐 / 计时器 / 提醒不再让位），浮层与岛是同屏的两个独立元素（浮层在岛下方、`level = .screenSaver`）；② 与 OSD 的撞车问题消失（不再共用一条链，音量 / 亮度 HUD 与浮层可同时出现）；③ **`hideOnClosed`（用户把刘海整个关掉）不再能关掉浮层**：浮层窗口不读这个设置，通知到达时浮层照常出现在应用会显示岛的每块屏上——~~反过来说，用户若想「完全不要浮层」，本批**没有**总开关~~（**2026-09-28 已补上**：`enableNotificationHUD` 总开关 + 显示时长 + 卡片背景等五项，见 D-25；模块的 `defaultEnabled` 仍是给新装用户的默认值，不是运行期开关）；④ **浮层显示期间「悬浮即展开面板」仍被抑制**（2026-09-28 修，判据 `ContentView.swift` 的 `shouldSuppressHoverOpen(activeHUD:)`，守卫加在 hover 的 `mouseDown` 监听回调与延时展开任务两处）：鼠标停在刘海上时「点浮层按钮（× / 打开 App）」的那一下不再被 `mouseDown` 监听或延时展开抢走；抑制随 `activeHUD` 变 nil 自动解除（浮层 ttl 有上限，通知侧默认 8s，见 D-25），延时任务唤醒时浮层已消失则照旧展开、不重新计时；⑤ **非刘海屏的 hide-until-hover 豁免已删除**（D-23）：该豁免是 D-22 时期的补丁（浮层渲染在关闭态链里，被 hide-until-hover 挪出屏幕就看不着），浮层搬进独立窗口后不再需要——外接屏上「关闭态内容照常隐藏 + 浮层窗口自己出现」互不干扰；⑥ **窗口几何是「贴顶 + 居中于**它自己那块**屏」**（**2026-09-28 第三次改口径，D-25**）：~~多屏时浮层跟着鼠标走（用户预期），但**不跟随岛所在的屏**~~——用户反馈「当鼠标在哪个屏幕，哪个屏幕才显示，而不是所有屏幕都显示，这个应该是所有屏幕都显示才对」后，改成**每屏一个窗口、所有目标屏同时显示**（`targetScreenNames`：`showOnAllDisplays` 为真取全集、为假取指定屏；屏变化时重建）。因此「浮层与岛不在同一块屏」这个旧缺口自然消失（岛在哪块屏，浮层就在那块屏上，其余屏也各有一份）；鼠标位置**不再**影响浮层落点；⑦ **浮层是固定尺寸**（2026-09-28 用户反馈「尺寸不固定，要固定个初始大小」后改口径，D-24）：窗口内容尺寸 = 320 × 64 × `notificationHUDScale`（默认 1.3），由 `ModuleHUDWindowHost.contentSize(scale:)` 计算、模块侧卡片（`NotificationHUDCardLayout`）引用**同一个函数**——先后两条通知内容长短不同也不再宽窄跳动（D-23 的「按内容自适应」由此作废：`fittingSize` 那条链在改固定尺寸时删除，`layout()` 回调只留幂等收尾）。**超长内容在卡片内截断、完整正文看展开面板的通知列表**：第一行 App 名（1 行、中间截断），第二行「标题 · 正文」（正文里的换行先压成空格，最多 2 行、尾部截断），一次取数进来的多条新通知只在第二行末尾追加计数后缀（`module.notifications.moreCount` =「等 N 条」/「and N more」）、浮层仍只展示最新一条；⑧ **显隐是幂等状态机**（2026-09-28 修「内置屏偶发只显示第一条」，间歇性而非必现）：`present` / 内容布局回调 / 淡出完成三处入口都只做「把当前窗口状态（在不在台上 / alpha / 代数是否匹配 / 有没有 activeHUD）喂给 `HUDVisibilityStateMachine` 的纯函数 → 按序执行动作」，不再各自只看一两个条件。修掉的两个坏状态：⒜ 淡出期间新浮层接手时旧回调因「有 activeHUD」提前 return，窗口 `isVisible == true` 但 alpha 停在 0，下一次 `present` 又因可见而跳过 `orderFrontRegardless`（只剩 `fadeIn` 一条恢复路径）；⒝ 尺寸没变时尺寸回调早退，窗口已被收起就没人再露出它。**没有定时器 / 重试兜底**（约束）。

28. **模块没有「主动撤浮层」的 API**（2026-09-28，通知 AX 通道的 × 落地时确认；**①已被 D-23 取代**）：`UIHandle` 只有 `presentTransient`（`ModuleRegistry` 有 `clearHUD()`，但不对模块开放）。因此通知浮层的 × 用**视图本地状态**（`@State isHidden`）把那**一格渲染成空**（`EmptyView`），而不是调内核撤掉浮层。三条后果：① ~~关闭态优先级链**仍认为有浮层**~~——**不再适用**（D-23：浮层不在关闭态链里了，而且 §28 后半段给的 `UIHandle.dismissTransient()` 已经落地，× 走的是它：内核撤浮层 → 窗口淡出，岛内容一直照常显示，"空的一格"这个形态不复存在）；② 被 × 关掉的那条**不会**因为同一指纹再次弹（10s 去重窗口仍在，由 `NotificationBannerLedger` 管），但**不同**通知到达会正常覆盖这一格；③ 真关闭失败时（AX 动作没生效、横幅已自动消失）语义仍成立——「从岛上隐藏」这一半永远做到，失败只记日志、不弹错误。~~要做成「撤掉浮层让位给下层 live activity」，需要给 `UIHandle` 加一条 `dismissTransient()`（内核改动，本批不动）。~~ **已落地**：`UIHandle.dismissTransient()` 已加（归属判定在 `RedrawUIHandle`，见 D-22 的后续提交）。

29. **AX 横幅通道的三条形态约束**（2026-09-28，macOS 27 实测，细节见 [09](09-features-and-mechanisms.md) §5.5「AX 通道形态」）：① **App 名只能从横幅容器的 `AXDescription` 首段剥标题得到**（没有独立元素），剥不出来就给空——浮层左上会退化成通用文案（不猜、不拿标题冒充 App 名）；② **关闭是容器上的自定义动作**（`Name:关闭\nTarget:0x0\nSelector:(null)`），不是 `AXButton`：句柄类型因此是「元素 + 动作名」（`NotificationBannerCloseHandle`）而不是设计稿写的 `AXButton`，动作名必须**原样**回传；对 `AXPress` 只是「显示详细信息」；③ **动作返回值不可信**（传不存在的动作名也返回 `0`），成功判据改成「返回成功 **且** 元素随后失效」——因此「真关闭」是**尽力而为**：失败时按「仅从岛上隐藏」处理，不弹错误。另：AXObserver 本机实测不是每条横幅都触发，**0.5s 轮询是必需的**（不是可选优化）；通知中心进程会被系统重启（实测 `killall NotificationCenter` 后 pid 813 → 44809），观察器按 pid 变化重挂。

30. **拖动把手的四条边界（含一条实测出来的既有缺陷）**（2026-09-29，D-29；① 按用户给的备选写法落地，②③④ 是落地时实测 / 推导出来的口径）：① **极简模式下把手不显示**（判据 `ContentView.showsPanelResizeHandle` = `notchState == .open && !enableMinimalisticUI`）。理由：那一档的尺寸来源是 `minimalisticOpenNotchSize`（固有基准 420×180、非刘海屏药丸 340×144，再叠加歌词 / 提醒 / 计时器的附加高度），`openNotchSize` 与 `Defaults[.openNotchWidth]/[.openNotchHeight]` **完全不参与**——vm 的宽度 sink 自己也带 `!enableMinimalisticUI` 前置；把手若照常出现，拖动只会写进一个**当场没有任何效果**的值（要等切回标准展开态才突然生效），与全篇在避免的「拖了没用」相悖。② **自有高度源的 tab 会盖掉拖动写入的高度**：`timer`（固定 250）、`notes` / `clipboard`（`max(默认高度, preferredHeight)`）、`terminal`（屏高 × `terminalMaxHeightFraction`）、`stats`（基准 + 行数 × 132）这几个分支在 `dynamicNotchSize` / `calculateRequiredNotchSize` 里另有加减法，因此这些 tab 上**宽度照常生效、高度可能看不出变化**（值已写进 `Defaults`，切回首页 / 模块 tab 即按拖动结果生效）。未按 tab 门控把手：判据只留「展开态 + 非极简」一条，避免把手在切 tab 时忽隐忽现。③ **拖动是「半程跟随」**：把手长在面板右下角、会随面板一起移动，`DragGesture` 的 `.local` 坐标系（把手自身）把面板的位移也算进 `translation`——实测比例（鼠标位移 → 尺寸变化）高度方向约 **0.5~1.0**（12 步 × 45ms 的合成拖动下测得 0.5~0.6，个别单步到 1.0），宽度方向约 **0.7~1.5**（面板水平居中，窗口左边界跟着动，放大方向会超过 1）。这是「固定起点 + 累计位移」口径的固有折损，换来的是**不会因窗口实时重排而抖动 / 越拖越快**（取舍见 D-29）。④ **`AppDelegate.shared` 在视图层取不到 → 高度原本没有实时链路**（实测发现，属既有缺陷）：本机注入拖动时，`ContentView.syncWindowSizeAfterPanelResize` 里 `guard let delegate = AppDelegate.shared else { return }` 直接走了 return（`log show` 看不到它之后的任何日志），也就是说**从视图层调 `ensureWindowSize` 是静默 no-op**。因此：**宽度**能实时跟随，靠的是 `DynamicIslandApp` 自己那条 `Defaults.publisher(.openNotchWidth)`（0.15s 防抖后重算窗口尺寸）兜底；**高度**原本无任何实时链路（`notchHeightChanged` 的观察者只做 `positionWindow`，用的是当前 frame 的尺寸，不重算）——设置页的高度滑块同样是「改完要重新展开一次才看得到」。把手上线时按 `AppDelegate.resizeWindow` 的同一口径**在视图层直接改窗口 frame**（+18 阴影与按屏外扩、宽按屏宽夹取、水平居中 + 顶边贴屏顶），高度这才随拖动实时生效。**未逐一验证**：`DynamicIslandViewModel` 里那几处 `AppDelegate.shared?.ensureWindowSize`（打开 / 关闭 / 歌词 / 笔记布局）是否同样失效——宽度与状态切换另有兜底路径，日常看不出问题，若要收敛应单独一笔。附实测得到的面板几何关系（可作为后续判断的尺子）：窗口高 = `addShadowPadding(内容高)`（+18）再按屏补外扩（刘海屏 +4），**面板的实际渲染高 = `min(内容高 + 12, 窗口高 − 22)`**——窗口尺寸正确时面板高 = `openNotchHeight`；窗口偏小时面板被裁（这正是④必须修的原因）。

### 本批（p2-home-strip，2026-09-29）新增

31. **首页 strip 不滚动、会丢块**：可用宽度压到各块最小宽度之和以下时，**尾部的块按 `order` 逐个消失**（丢块比压扁更可读，[17](17-nookx-adoption.md) D-03）。因此面板很窄（如宽度拖到 400pt）时首页只能看到前 1～2 块，且**被丢的块没有任何提示**。不滚动 / 不分页是刻意的：滚动与分页都会让首页"需要操作才能看全"，与"扫一眼就够"的定位相反。相关：`HomeStripLayoutMath.plan` 的浮点边界、丢块必须"显式零提案"、`sizeThatFits` 与 `placeSubviews` 必须复用同一份 plan 三条，见 [17](17-nookx-adoption.md) 已知限制 10/12/13。
32. **minimalistic UI 与歌词侧栏两条路径不接 strip**：`NotchHomeView` 只把**标准分支**换成 `HomeStripView`，`enableMinimalisticUI` 走极简播放器、`shouldShowSideLyrics` 走"播放器 + 歌词侧栏"，两条路径逐字未动（[17](17-nookx-adoption.md) D-10）。因此"首页 = 已开启组件的 strip"**只在标准路径成立**。
33. **宿主内置三块不出现在设置页「组件」页**：音乐 / 日历 / 镜子由上游 `Defaults` 键（`showStandardMediaControls` / `showCalendar` / `showMirror`）门控，不是模块，因此组件页只有模块卡片——用户会看到"组件页只有几张卡，但首页有更多块"的**不一致**。接受理由：提前把接管模块模块化会与上游设置页形成双份真源（[14-module-manifests.md](14-module-manifests.md) T-3）；缓解措施是卡片页顶部那一行说明。
34. **`failed` 只能"重启应用 + 再打开一次"恢复**：`failed` 不可逃逸（[17](17-nookx-adoption.md) D-13，见本文「本批新增 / 变更的口径」3），开关在 `.failed` 上禁用点击，失败回弹只把偏好写回 `false`。**本次运行内没有任何恢复路径**——不重试、不做指数退避、不提供"重试"按钮；用户要恢复只能重启应用再打开开关。
35. **待办块有 220pt 阈值，默认面板宽下只画三环**：首页块宽度由 `HomeStripLayoutMath` 分配，本机面板 770pt（tab 数 ≥6 时才给到这个宽度）时，胶囊内可用宽**实测 ≈705pt**（方法：由展开态截图的三环环心像素反推；**不按内边距常量推导**——那条链的常数分不清 702/706，而 702 会跨过规则② 与规则③ 的分界）。代入 `plan`（理想 420/260/240、最小 300/200/180、间距 12）得 ≈`[301, 200.5, 180.5]`，三块都压在最小宽度附近；待办块 < 220 → 只画三环。要让清单出现，可用宽需 ≥ 864（面板 ≈930pt）。**另注意新装默认面板是 690pt**（`openNotchWidth` 默认 640 被最小宽度抬到 tab 数对应的值）→ 可用 ≈622 → 规则③ 直接丢掉待办块，首页只有音乐 + 日历两块。也就是说默认配置下"首页看到待办清单"这一条**不成立**。这是宽度预算的必然结果而非缺陷，判据取放置后的实测宽度（`GeometryReader`）不是测量值。

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
| D-05 | `ModuleContext` 本批只实现四个面 + moduleID（`host` / `config`(简化) / `logger` / `ui`）；其余七个面（`notch`/`permissions`/`events`/`storage`/`scheduler`/`secrets`/`clock`）延后 P1-2/P1-3 | agent | 试点模块（progress）不需要它们；先落最小可用面，避免设计未定的句柄被提前固化（延后面见「明确不做」、加回成本见「已知限制」9） |
| D-06 | `ModuleContent.descriptor` 本批只解析不渲染（渲染路径显示 unavailable 文案） | agent | descriptor 渲染对应上游扩展管线，属 P4 插件层 |
| D-07 | 试点模块选 `progress`，`surfaces: ["expanded"]`，`defaultEnabled: true` | agent（承接 ADR-0012 用户已批准的新增 6 项） | 零私有 API、零依赖、成本最低（[09](09-features-and-mechanisms.md) §5.3）；compact 槽位本批不做故不声明 |
| D-08 | 首启写入 `enableScreenAssistant=false`（一次性、幂等） | 用户 | [09](09-features-and-mechanisms.md) §8.1 已拍板「不需要的上游功能用上游开关默认值表达」；该功能上游默认 `true` 且入口隐蔽（⌘⇧A 悬浮面板，不在刘海 tab 里） |
| D-09 | 模块清单口径 = 15 个模块 + 终端独立条目（共 16 份 manifest），逐项裁定调研标记的 13 处未决口径（T-1…T-13，清单与结论见 [14](14-module-manifests.md)） | 用户（边界）+ agent（裁定） | 边界出自 [09](09-features-and-mechanisms.md) §8.1（用户已拍板）；未决口径在 [14](14-module-manifests.md) 逐条给结论 |
| D-10 | 新代码落 `DynamicIsland/Kernel/` 与 `DynamicIsland/Modules/`，靠同步组自动纳入；测试新增文件需登记 pbxproj 四处 | agent | `project.pbxproj:117-123` 的同步组已覆盖 `DynamicIsland/`；测试目录是普通 group |
| D-11 | 内置模块 id 与本地化 key 沿用 06 §2.2/§2.3：`com.cmeng.gourd.<shortID>`、`module.<shortID>.name` | 用户（[09](09-features-and-mechanisms.md) §8.3 已定命名）+ agent | 逐字沿用已定契约 |
| D-12 | 本批不声明 `lockscreen` surface | 用户 | ADR-0011 第 4 条「锁屏维持现状」 |
| D-13 | 本批的范围边界与实现面裁剪，由 agent 依调研证据裁定：① 不做折叠态槽位（D-01）② 不做状态机实现（D-04）③ 不声明锁屏（D-12）④ `ModuleContext` 只做四面 + moduleID（D-05）⑤ `ModuleContent.descriptor` 不带 payload（D-06）⑥ 试点模块默认启用（D-07）⑦ 13 处未决口径的逐项结论（D-09）⑧ 首启默认值只落一项（D-08 范围）。用户在本会话明确授权「两道门不需要审阅，直接执行」 | 用户 | 用户授权自主执行；每条裁定的证据落在本文件「备选与取舍」「已知限制」，无不可逆改动（后续批次可回退），且**加回路径已逐条写明**（「明确不做」与「已知限制」9/10/11/12） |
| D-14 | 平台依赖台账与 ATS 域名清单的收录口径：私有 API 11 项逐条带降级路径；子进程含新增 `/usr/bin/shortcuts`；域名清单 = `grep -rn '"https\?://'` 的结果，**并集 host 本身由插值拼出的形态**（当前源码 0 处，作为保险规则保留），每条指向 file:line | agent | **审查期实测更正了初稿的说法**：`grep` 已能取到"host 字面、尾部插值"的 URL（如 `MusicManager.swift:1525` 的 lrclib）；真正的盲区只有 host 由插值拼出——明写规则可避免下次误判（记录在 [15-platform-dependencies.md](15-platform-dependencies.md) §3.1） |
| D-15 | `ModuleRegistry.register()` 不调用 `validate()`（内置 manifest 是代码字面量，正确性靠单测与审查期独立探针） | agent | 编译期同仓库的字面量再加一层运行期校验收益低；代价与「加第二个内置模块前补 dev-only 断言」记在已知限制 17 |
| D-16 | `deactivateAll()` 的语义定为「停用 + 清空注册表四张表」 | agent | 单测需要用例级隔离（`manifests`/`states` 是 `private(set)`）；名字只表达了前一半，已写进接口注释与已知限制；P1-3 若需要「停用但保留注册」须另加接口 |
| D-17 | progress 的刷新定为 `TimelineView(.periodic(from: .now, by: 60))`，取代 [09](09-features-and-mechanisms.md) §5.3 的分级刷新 | agent | 60s 对日进度足够，且免掉内核侧 tick 事件（属 P1-3）；时钟/时区变更的感知延迟与代价见已知限制 14 |
| D-18 | 三个新 capability（`notifications:read` / `network:local` / `calendar:read-titles`）本批只在 [14](14-module-manifests.md) 里标注「待落 06 §7.1」，**不改 06 号文档** | agent | 本批的执行约束是"只动白名单文件"；白名单的正式增补随 P1-3 / P2c（通知模块开工前必须落）。标注落点逐项写明：`notifications:read` / `network:local` 在各自 manifest 行的 `permissions` 格；`calendar:read-titles` 在 calendar 行的 `permissions` 格注与 T-8 / §3 待落清单——它是 07 §3.5 事件订阅裁剪项引出的缺口，**不是 calendar 行本批的声明项**（该行 `permissions` 仍是 `[]`） |
| D-19 | 折叠态**中央槽位**用「在 `ContentView` 关闭态优先级链里插一个**低优先**分支」落地（`ModuleRegistry.compactEntries` / `compactSlotContent()` + `ModuleCompactSlotView`），不改 HStack 结构 | 用户（方案定稿）+ agent（落点） | 三槽布局（左/中/右 + 每侧上限）要重构 `ContentView.swift:1219-1312` 的 HStack——这正是 D-01 / D-13 ① 当初不做折叠态槽位的理由；插分支是**零结构改动**的等价落地，成本低且可回退。代价写在已知限制 26（槽位与 live activity 共用优先级链，只在无其它活动时显示）。**左/右图标槽位与三槽布局仍延后**（见「明确不做」）；`order` 的双语义按已知限制 25 的「明确写下」分支处理 |
| D-20 | **待办模块 `todos` 取代 `progress` 作为中央槽位的默认内容**：`todos` 取 `defaultPlacement = {slot: .center, order: 20}`、`defaultEnabled: true`；`progress` **代码与 manifest 全部保留**，只把 `defaultEnabled` 改 `false` | 用户（判定）+ agent（落点） | 2026-09-28 用户判定「时间进度」无行动价值（看得到，但不构成"要做的事"），而待办的 `已办/总量` 是真实进度。落点不需要改内核排序逻辑：`compactEntries` 按 `(order, id)` 升序取第一个，`todos` 的 20 < `progress` 的 30，故槽位自然归 `todos`；已知限制 25 的 `order` 双语义照旧适用。代价：`progress` 从「默认可见」变成「要在设置里开回才可见」，且这条默认值的改动对既有安装同样生效（启用门每次启动都读 `defaultEnabled`，用户显式改过的话由 P1-3 的 ConfigStore 统一接管，见已知限制 12） |
| D-21 | 待办的**统计口径**：① 分子分母**同源**——某类别的成员条数 = `总量`，其中 `isCompleted` 的条数 = `已办`（不另立「应办」口径）；② **已完成只取最近 7 天**（`predicateForCompletedReminders(withCompletionDateStarting: 今天 00:00 − 7 天, ending: nil, calendars: nil)`）；③ **今日 / 本周刻意重叠计数**（今日 ⊆ 本周 ⊆ 所有，本周不是"本周减去今日"）；④ **无到期时间的条目只进「所有」** | 用户（口径）+ agent（取数落点） | ②：EventKit 没有「取全部已完成」的高效谓词，不设窗口会让「所有」环被陈年已完成条目拖成历史总量（一装就几百条已完成），首次取数也变慢；而今日 / 本周最早只到 6 天前，7 天窗口**完整覆盖**这两个类别的分子。③：三个环回答的是"今日 / 本周 / 全部各自做完多少"，互斥分割会让本周在周初看起来像"今天之外没有事"，用户明确要求「今日的重复出现在本周」。④：设计单列的硬规则，与「今天完成的也归今日」相抵时以它为准（只对有到期时间的条目生效）。实现见 `DynamicIsland/Modules/TodoBucketing.swift`（纯函数，口径逐条写在文件头） |
| D-22 | **内核新增「瞬时浮层」能力**（09 §5.5 呈现 ① 的宿主侧）：`ModuleRegistry` 加 `ModuleHUD`（id / moduleID / view / expiresAt）+ `@Published activeHUD` + `presentHUD(moduleID:view:ttl:)` / `clearHUD()`；`UIHandle` 加 `presentTransient(view:ttl:)`（协议标 `@MainActor`，实现落点唯一 = `RedrawUIHandle` 补 `moduleID` 后转发注册表）；渲染面新建 `Kernel/ModuleHUDView.swift`，`ContentView` 关闭态优先级链插**一个中优先分支**（判据 `vm.notchState == .closed && !vm.hideOnClosed && moduleRegistry.activeHUD != nil`，且 **`ContentView` 必须 `@ObservedObject` 观察注册表**） | 用户（要求落地 09 §5.5 呈现 ①）+ agent（落点与取舍） | **不走上游 `toggleSneakPeek`**：`SneakContentType` 是封闭枚举（无通知项），渲染散在 `NotchHomeView` / `MinimalisticMusicPlayerView` 的十余处 `switch` 里——加一种类型的侵入面远大于在关闭态链插一格，且会把「模块的浮层」绑死在音乐播放器的视图上。**优先级取舍**（插入位置 = OSD 类之后、音乐/计时器/提醒之前）：系统级反馈是用户**刚按下的键**（音量 / 亮度 / 大小写锁）必须压过通知；而通知是"刚发生的事"，要盖过常态驻留的 live activity（否则放着音乐时通知永远看不见）。不叠加：与既有各分支共用一条链，浮层期间被盖住的活动自动让位、到期即恢复（代价见已知限制 27）。**`ttl` 夹取 1…15s**：下界「短到看不见等于没弹」、上界「不得变成常驻占位」；**到期只清自己那一条**（任务醒来先比对 `activeHUD?.id`），否则「先弹短 ttl 的 A、再弹长 ttl 的 B」会让 A 的旧任务把 B 提前清掉。**实测得到的硬约束**：只写 `ModuleRegistry.shared.activeHUD` 而 `ContentView` 不观察它时，`presentHUD` 有日志、分支却永不取到（`@Published` 的变更只在被观察的视图里触发重算）——故 `ContentView` 加了一行 `@ObservedObject private var moduleRegistry`。**（渲染面已被 D-23 取代：浮层不再走关闭态链，那一行 `@ObservedObject` 与关闭态分支在该提交里一并删除；`ModuleHUD` / `activeHUD` / `presentHUD` / `ttl` 夹取 / 到期只清自己那一条这些**内核契约**仍是现行口径。）** |
| D-23 | **瞬时浮层改用「内核拥有的独立自适应窗口」渲染**（2026-09-28，用户实测反馈驱动）：新建 `Kernel/ModuleHUDWindow.swift` 的 `ModuleHUDWindowHost`——`NSPanel`（`[.borderless, .nonactivatingPanel]`、透明、`hasShadow`、`level = .screenSaver`、`.canJoinAllSpaces + .fullScreenAuxiliary + .stationary`、`ignoresMouseEvents = false`、`becomesKeyOnlyIfNeeded`），内容 = 内核自己的 `HUDSizingHostingView`（`NSHostingView` 子类：`acceptsFirstMouse` + `layout()` 回调）包 `ModuleHUDView().environment(\.colorScheme, .dark)`，**按内容自适应**（`layout()` 回调里的 `fittingSize` → `setContentSize`，内容更替后重算）并**水平居中于鼠标所在屏、顶端贴在该屏可用顶边下方 8pt**（内边 = 有刘海时的 `safeAreaInsets.top`，否则菜单栏高度 `frame.maxY - visibleFrame.maxY`）；宿主订阅 `ModuleRegistry.$activeHUD`（有 → 先 alpha 0 上台量尺寸、尺寸就绪即淡入 0.15s，无 → 淡出 0.2s 后 `orderOut`，**不自己维护 ttl**）；`DynamicIslandApp` 启动路径加一行 `ModuleHUDWindowHost.shared.start()`（S8）；同时**删除**关闭态链里的 `ModuleHUDView` 分支与 `shouldHideClosedContentUntilHover` 的 `hasModuleHUD` 形参、删除 `ContentView` 对注册表的 `@ObservedObject` | 用户（②内置屏「被遮盖、是不是离顶部太近」+ ①外接屏「太小」）+ agent（落点与取舍） | **根因**：浮层原本渲染在关闭态内容链里，而关闭态面板窗口的尺寸 = 折叠态刘海尺寸（内置屏 32pt 高、外接屏一个小组件）→ 内容被**裁剪**（内置屏：两行字压在菜单栏/刘海下方、下半截被裁）或**过小**（外接屏）；上游的瞬时提示（sneak peek）会临时撑大窗口，内核没有这条路径。**三个要解决的问题一一对应**：① 非刘海屏（外加 `hideNonNotchUntilHover`）不再靠豁免 hide-until-hover 露脸；② 内置屏不再被刘海裁剪；③ 「跟随鼠标屏」= 浮层出现在用户正在操作的那块屏。**实现期踩到并已修的两条时序坑（本行是唯一记录点）**：ⓐ `@Published` 在 **willSet** 里发值 → 订阅回调里读 `activeHUD` 拿到的是旧值（首条浮层渲染成空视图）→ `start()` 的回调统一挪到下一拍读注册表真值；ⓑ `fittingSize` 只在 SwiftUI 为内容跑过布局之后才有意义，在订阅回调里同步量会量到上一条内容甚至 **0×0**（实测首条浮层窗口卡在兜底尺寸、卡片完全不显示）→ 量尺寸时机改为 `layout()` 回调（内容布局完），且 `ModuleHUDView` 的根内容加 `.fixedSize()`（内容不受窗口当前尺寸牵制，`fittingSize` 才稳定）。**代价**：浮层不再与岛内容同层（已知限制 27 重写：不再占关闭态那格、不再让位/被压、也不再受 `hideOnClosed` 约束）；同一条浮层存活期间模块自改尺寸会被跟随（`layout()` 回调驱动），但**窗口位置按内容尺寸每次重算**（贴顶居中）。**窗口归内核**（06 §3.3 R1「模块不得自己创建窗口」）：模块只交视图，创建 / 定位 / 尺寸 / 显隐全在宿主 |
| D-24 | **浮层改「固定尺寸 + 超长内容截断」**（2026-09-28，用户实测反馈驱动，两笔落地）：① 尺寸 = **320 × 64 × `notificationHUDScale`**（默认 1.3），纯函数 `ModuleHUDWindowHost.contentSize(scale:)` 是唯一来源（内核据此设窗口、模块的 `NotificationHUDCardLayout` 据此算卡片与字号），`scale` 夹取 0.8…2.0 并保留两位小数；D-23 的 `fittingSize` 自适应链与 `sanitizedContentSize` / `fallbackContentSize` 随之删除（窗口尺寸不再由内容决定，`HUDSizingHostingView` 简化为 `HUDHostingView`，`layout()` 回调只做「校正尺寸 + 显隐纠正 + 重新贴顶」的幂等收尾）；② 超长内容策略：第一行 App 名（粗体、1 行、`.truncationMode(.middle)`）、第二行「标题 · 正文」（正文换行压成空格，最多 2 行、`.truncationMode(.tail)`），一次取数多条新通知**只展示最新一条**、其余在第二行末尾追加 `module.notifications.moreCount`（「等 N 条」/「and N more」）——**完整正文的位置是展开面板的列表**（浮层是 4s 的瞬时提示，不是阅读入口，因此截断不丢信息）；③ 同一次改动的**显隐幂等**（2026-09-28 修「内置屏偶发只显示第一条」）：三处入口（`present` / 内容布局回调 / 淡出完成）统一走 `HUDVisibilityStateMachine` 的两个纯函数，修掉 ①淡出被接手后停在 `alpha == 0`、②尺寸没变时早退导致「已收起没人再露出」两个坏状态；**不用定时器 / 重试** | 用户（「尺寸不固定，要固定个初始大小」「消息内容过多考虑下怎么显示」+「主屏第一条显示、后面不显示」）+ agent（落点与取舍） | 固定尺寸的理由：内容是两行文字，长短不一时自适应窗口会宽窄跳动；改固定后 `textMaxWidth` 由卡片宽度反推（不再有 `cardMaxWidthCeiling` 与刘海 / 非刘海两档基准），倍率仍由用户设置页的滑块控制（0.8…2.0）。截断位置的取舍：第一行用中间截断保留 App 名首尾（后缀可辨），第二行用尾部截断（正文从前往后读）；多条不排队弹是 09 §5.5「避免刷屏」的既定口径，计数后缀只补「还有几条」这一条信息。显隐改状态机的理由：问题**间歇**出现，说明是状态残留而不是稳定缺失——把「动作只由当前状态决定」写成纯函数后，坏状态一旦被下一个事件观测到就被纠正（动作集合有 5 条单测钉住：首次上台 / 淡出中被接手 / 淡出结束无接手 / 同尺寸重弹 / 有接手时不 orderOut） |
| D-25 | **浮层在所有屏同时显示 + 五个设置项**（2026-09-28，用户实测反馈驱动，三笔落地）：① **每屏一个窗口**（用户反馈「当鼠标在哪个屏幕，哪个屏幕才显示，而不是所有屏幕都显示，这个应该是所有屏幕都显示才对」）：`ModuleHUDWindowHost` 从「单个窗口、`present` 时挪到鼠标所在屏」改为 `slots: [String: PanelSlot]`（**键 = `NSScreen.localizedName`**，`NSScreen` 实例会被系统替换故不能当键），`present` / `dismiss` / 内容布局回调三处**逐窗口**执行（同一份内容、同一套状态机动作、各自算贴顶居中的几何）；目标屏由纯函数 `targetScreenNames(showOnAllDisplays:screenNames:mainScreenName:preferredScreenName:)` 决定——`Defaults[.showOnAllDisplays]` 为真（**用户当前设置**）取 `NSScreen.screens` 全集，为假只取该设置指定的那块屏（读上游既有的 `preferred_screen_name`，与岛同源），指定屏不在场时依次退到 `NSScreen.main` → 列表第一块（三档兜底：浮层不该因为设置里那台显示器没接就彻底不出现），空屏集合给空集合；屏幕配置变化（`NSApplication.didChangeScreenParametersNotification`）→ 清理已断开屏的窗口 + 有浮层时按新屏集合重弹一遍。**命中鼠标跟随的旧口径由此作废**（`targetScreen()` 删除）：浮层不再跟着指针跑，而是「应用显示岛的每一块屏各一份」。② **显示时长可配、默认 8s**（用户反馈「显示时长太短」）：新增 `Defaults.Keys.notificationHUDDurationSeconds`（Double，默认 8，原为模块里的代码常量 `hudTTL = 4`），映射与夹取收在纯函数 `NotificationHUDPolicy.ttl(forSettingSeconds:)`（夹到 `ModuleRegistry.hudTTLRange` 1…15s；设置滑块区间 2…15s 是同一处的 `durationRange`），AX / DB 两条通道共用 `ttlFromDefaults()`。③ **通知配置区**（用户要求「做一个配置项，要包含总开关、显示时长、背景设置（是否为液态玻璃模式）这些」）：新增 `enableNotificationHUD`（Bool，默认 true，**总开关**：关掉后连 `presentTransient` 都不调——判定收在纯函数 `NotificationHUDPresentation.resolve(enabled:showsBody:backgroundStyle:)` 返回 `nil`，两条通道同一道闸门；列表 / 未读计数 / AX 真关闭 / DB 增量全不受影响）与 `notificationHUDBackgroundStyle`（enum `NotificationHUDBackgroundStyle: String`：`.liquidGlass = "Liquid glass"`（**默认**）/ `.solid = "Solid"`，存 rawValue 同 `LockScreenGlassStyle`）；卡片底改为二选一（`NotificationHUDView.cardBackground(cornerRadius:)`：液态玻璃走 `LiquidGlassBackground(variant: .defaultVariant, cornerRadius:)` + `Color.black.opacity(0.35)` 压暗、纯色走 `Color.black.opacity(0.92)` + 浅描边，两档圆角都与卡片一致）；设置页把五项归到 Live Activities 的 **Notification HUD** Section（总开关 / 时长滑块 / 背景 Picker / 正文开关 / 字号滑块，时长与背景各加一条搜索索引），关掉总开关时其余四项灰显 | 用户（「所有屏幕都显示」「显示时长太短」「做一个配置项：总开关 + 显示时长 + 背景液态玻璃」）+ agent（落点与取舍） | **多屏的取舍**：① 为什么不「镜像主屏那一份」（一个窗口跨屏）——窗口只能属于一块屏，跨屏只能靠多个窗口；② 为什么按 `localizedName` 而不是 `CGDirectDisplayID`——前者是上游全程使用的口径（`showOnAllDisplays` 的屏挑选、`selectedScreen` / `preferredScreen`、`CircularHUDWindowManager.show(onScreen:)` 一族都按名字对齐），两套键会让「岛在哪块屏」与「浮层在哪块屏」在同一台机器上出现两套判定；屏幕改名（用户自己改显示器名）会命中「指定屏不在场」的兜底档，代价可接受；③ 屏变化时**主动重弹**而不是等下一次通知——拔掉一块屏后剩下的窗口必须重新贴顶（排列变了），新插上的屏也要立刻看到当前这条浮层。**背景默认液态玻璃但强制深色外观**（用户口径「是否液态玻璃」+ 本项目已有的坑）：关掉「强制深色」在浅色系统下玻璃会渲染成浅色，而卡片文字一律显式白色（09 §5.5 的既有口径）→ 白字看不见；做法是**窗口层** `panel.appearance = NSAppearance(named: .darkAqua)`（口径同 `EditPanelView.VisualEffectView.forcedAppearance` 对 `hudWindow` 材质的处理，`NSGlassEffectView` 是 AppKit 视图、只有窗口 / 视图的 appearance 能改它的材质取值）+ 玻璃内容上压一层 `Color.black.opacity(0.35)`（`LiquidGlassBackground` 内部是另一个 `NSHostingView`，不继承外层环境，故内容里再补一份 `.environment(\.colorScheme, .dark)`）。**总开关的边界**：只关浮层，不关功能——09 §5.5 的列表 / 未读 / 真关闭照常，这也是已知限制 27 ③「想完全不要浮层却没有开关」那条缺口的落地 |
| D-26 | **主面板背景可配（纯黑 / 液态玻璃 / 毛玻璃），玻璃只在展开态与浮动药丸生效**（2026-09-28，用户反馈驱动）：① 新增 `Defaults.Keys.notchPanelBackgroundStyle`（enum `NotchPanelBackgroundStyle: String`：`.solidBlack = "Solid black"`（**默认**）/ `.liquidGlass = "Liquid glass"` / `.frostedGlass = "Frosted glass"`，存 `rawValue` 同 `NotificationHUDBackgroundStyle`）；消费点唯一 = `ContentView.mainLayoutBase` 的 `.background(panelBackground)`（改造前是写死的 `.background(.black)`；用户原话「看下这个显示的内容是否可以走液态玻璃的模式，还是只能是黑色背景，如果可以走，增加对应配置，我现在没找到配置项」——截图是展开态的音乐 + 日历那一屏）。② **状态口径**：玻璃两档**只在「展开态」或「非刘海屏的浮动药丸」上生效**，刘海屏折叠态保持纯黑——判据是纯函数 `panelBackgroundUsesStyle(isOpen:isDynamicIslandMode:)`（四条组合有单测），背景 = `panelBackgroundUsesStyle(...) ? 配置样式 : Color.black`。③ 三档落点：纯黑 = `Color.black`（与改造前逐字一致）；液态玻璃 = `LiquidGlassBackground(variant: .defaultVariant, cornerRadius: panelGlassCornerRadius)`，玻璃内容压一层 `Color.black.opacity(0.35)`（带 `.environment(\.colorScheme, .dark)`）；毛玻璃 = `PanelFrostedGlassBackground`（`NSVisualEffectView`，`.hudWindow` + `.behindWindow`、`state = .active`、`isEmphasized`、`appearance = darkAqua`）；两档玻璃都 `.allowsHitTesting(false)`（AppKit 视图不参与命中测试，别吃掉落在留白上的「点一下收起 / 拖拽」手势，口径同 `LockScreenMusicPanel` 的 `customLiquidPanelBackdrop`）。④ 设置页落 **Appearance → Panel Background**（与 Notch Height / Notch Width 相邻）：三档 Picker（`Text(style.rawValue)`）+ 一条 caption（写明玻璃只作用于展开态与非刘海屏的浮动药丸、刘海屏折叠态仍为纯黑）+ 一条搜索索引（keywords: notch panel / liquid glass / frosted / background）。**`.clipShape(resolvedClipShape)` / 阴影 / padding / 内容布局一概不动**（三档只换底） | 用户（「看下这个显示的内容是否可以走液态玻璃…增加对应配置，我现在没找到配置项」）+ agent（落点与取舍） | **为什么默认纯黑**：主面板底改造前就是写死的 `.background(.black)`，新键的默认值不该改变任何老用户的观感（升级即变色是回归），纯黑档逐字复刻旧行为。**为什么玻璃要绑状态**：刘海屏折叠态不是一块独立面板——它要与物理刘海严丝合缝地融合，玻璃是半透明的、会露出壁纸，在刘海下方形成一块突兀的方块；展开态与非刘海屏的浮动药丸本身就是完整圆角面板，没有这个前提（这条口径也写进设置页 caption：避免用户以为「选了玻璃但折叠态没变」是 bug）。**为什么强制深色外观**：玻璃是「底」，面板内文字是显式白色（上游口径），浅色系统外观下 `NSGlassEffectView` 与 `hudWindow` 材质都会渲染成浅色 → 白字压在浅底上看不清；做法是玻璃上压一层深色（同 `NotificationsModule` 的卡片底）与材质层 `darkAqua`（口径同 `EditPanelView.VisualEffectView.forcedAppearance` 对 `hudWindow` 的处理）。**为什么圆角与裁剪形状同源**：背景在 `.clipShape` 之前，玻璃自己的圆角若小于裁剪半径，最终可见的角就由玻璃决定（比面板本身的角更方），故 `panelGlassCornerRadius` 与 `resolvedClipShape` 取同一来源、并取上下两档的较大值，保证裁剪形状始终是决定方。**v11 的理由**：`LiquidGlassVariant.defaultVariant`（= `.v11`，组件作者标注「视觉上最讨喜」）是通知浮层卡片与锁屏自定义玻璃的同一档默认，主面板没有理由偏离。**没验证的部分**：两档玻璃的**观感**（半透明强度、与面板内容的对比度）需用户实机确认——单测只能钉住「哪一档、什么时候生效」，钉不住好不好看 |
| D-27 | **面板玻璃去边缘高光 + 顶部黑带取 max(刘海,菜单栏)+1 + 首页音乐区块成组顶部对齐 + 展开高度上限收 850**（2026-09-29，用户反馈驱动，四笔落地）：① **玻璃档两条白带的来源是组件自带的边缘高光**（用户反馈「glass 模式下有两个白条…不需要这个遮罩层」）：`NSGlassEffectView`（`.regular`）会在自己的轮廓上画一条镜面高光（上边最亮、下边次之），面板上表现为紧挨黑带下方一条亮白带 + 面板底部一条；本机实测（`screencapture` 逐行取像素）顶边起 `+0pt` 亮度 167、`+4pt` 136、`+16pt` 128 → 内侧 ~110，高光连着内侧渐变约 16pt。**没有可关闭的开关**（`style = .clear` 能去掉高光但把磨砂变成透明、背后文字变清晰，不用），故改为**几何规避**：`LiquidGlassBackground` 新增 `hidesEdgeHighlight`（默认 `false`，四边约束外扩 `LiquidGlassEdgeHighlight.overhang = 20pt`），只在**主面板这一处**开启；同时 `panelOpaqueTopBand(_:)` 从 `VStack` 改为 `ZStack(alignment: .top)`（黑带画在玻璃**上层**）——否则外扩后浮到黑带区间的上边沿高光仍会压在黑带上。锁屏 / OSD / Vertical HUD 的玻璃用法一字未动。② **顶部不透明带高度**：`panelTopOpaqueBandHeight(safeAreaTop:menuBarHeight:panelTopBleed:)` 从「刘海屏取刘海高度」改为 **`面板顶边相对屏顶的外扩 + max(刘海, 菜单栏) + 1`**（用户反馈「顶部的高度不够，比系统的黑色区域要窄」）——本机内置屏刘海 32 / 菜单栏 33，只取刘海高度时玻璃正好从那 1pt 露出来；且黑带是从**面板框顶边**往下画的、而系统 UI 带是从**屏顶**量的，刘海屏面板框顶边比屏顶高 `notchTopScreenBleedAmount`（4pt）→ 不补这段差额时屏幕上能看到的黑带只有 `高度 − 4`（实测配 34 时只黑到 29.5pt，露出 4pt 玻璃）。补上后本机实测黑带覆盖 0…33.5pt（系统黑区 0…33），严丝合缝。两个输入都 ≤ 0 时仍返回 0（不凭空多出一条黑边）。③ **首页音乐区块成组顶部对齐**（用户反馈「音乐播放的时候控制按钮在最下面，不在播放的区域」）：根因是 `MusicControlsView` 里宽度测量用的 `GeometryReader`（宽高双向贪婪）把「标题+进度」撑满整个面板高度、而控制按钮行是它的**兄弟节点**；改为把按钮行收进同一个 `VStack` 并整体 `.frame(maxHeight: .infinity, alignment: .topLeading)`，按钮紧跟进度条、空白留在下方（封面尺寸 / 圆角 / 进度条 / 按钮外观顺序未动；日历侧本来就是固定 120pt + `.top` 对齐，未改）。④ **展开态高度可配上限 1000 → 850**（用户明确「展开的高度最高是 850」）：只改 `openNotchHeightRange`，设置页滑块与运行时夹取同源（`effectiveOpenNotchHeightUpperBound` = `min(850, 屏 visibleFrame.height × 0.9)`，下界 120 恒定） | 用户（「两个白条 / 不需要这个遮罩层」「顶部比系统黑区窄」「控制按钮在最下面」「展开高度最高 850」）+ agent（实测取证与落点） | **为什么用外扩而不是换 variant 或改 style**：20 个 variant 的差异只在材质浓淡，边缘高光是 `.regular` 玻璃的统一绘制；`.clear` 去除高光的代价是失去磨砂（本机实测背后文字变清晰），与「面板底」的用途相悖。外扩是**纯几何**手段：不依赖任何私有属性，高光随玻璃一起移出宿主可见区（上边沿隐没在黑带区间、下边沿与左右被 `resolvedClipShape` 裁掉），可见区只剩平坦材质，面板形状与圆角完全不变。代价：玻璃视觉上不再有边缘「包边」，且外扩区域仍参与 behindWindow 采样（多采 20pt，无观感影响）。**为什么黑带要压在上层**：外扩后玻璃的上边沿落在黑带区间内，`VStack` 里玻璃后画 → 高光浮在黑带上（白条照旧），只有层级颠倒才压得住。**`+1` 与 `+bleed` 的来历**：`+1` 只补「刘海高度 vs 菜单栏高度」这 1pt 的取整差，面板整体高度与折叠态形态都不变（多盖 1pt 系统黑区，肉眼不可辨但消除了露缝）；`+panelTopBleed` 补的是「黑带从面板框顶边画、系统黑区从屏顶量」这段错位（非刘海屏的浮动药丸没有这段外扩，故取 0）。**黑带用玻璃的顶端 `overlay` 画**（不是 `VStack` 里的兄弟节点）：外扩后的玻璃上边沿落在黑带区间内，只有把黑带放在玻璃上层才压得住；也刻意不用 `ZStack`（背景根由多子视图决定尺寸时，`.background` 的居中摆放会让黑带整体上浮 4pt——实测就是这样）。**为什么上限是 850 而不是继续按屏收敛**：850 之后用户认为「再高只是空白」，收敛到常量后滑块区间、夹取、设置页显示三处同源，不存在拖了没用。**没验证的部分**：① 外扩后玻璃边缘的观感（是否仍像玻璃）需用户实机确认；② 400/850 两档下控制按钮的相对位置由像素截图证明，但**面板内的音乐内容本身**需要用户开着音乐实测 |
| D-28 | **`UIHandle` 新增 `requestCollapse()`——06 §3.4 `NotchHandle.requestCollapse(reason:)` 的过渡实现**（2026-09-29，通知模块「点消息后刘海要自动收起」驱动）：① 协议加一条 `func requestCollapse()`（`docs/06` §3.4 写了 `requestCollapse(reason:)`，本批**不带 `reason`**——还没有诊断面板消费它，P1-2 的 `NotchStateMachine` 一起补）；② `ModuleContextFactory.make(manifest:redraw:collapse:)` 加第三个形参（**默认 `{}`**，向后最小：既有单测与「注释掉一行」的启动路径都不必改），`RedrawUIHandle` 原样转发；③ `ModuleRegistry.bootstrap(collapse:)`（默认 `{}`）只做透传，`KernelBootstrap.bootstrap(collapse:)`（默认 `{}`）是组合根的注入点；④ 应用侧接线在 `DynamicIslandApp.swift:684` 的 `Task { await KernelBootstrap.bootstrap(collapse:) }`——闭包按既有的 `activeVM` 口径解析「哪块屏」（`showOnAllDisplays` 下取鼠标所在屏的 VM，否则主 VM；与 `toggleNotchOpen` / clipboard 快捷键逐字同一套写法），`notchState == .open` 才 `close()`，**调用时**解析（启动阶段窗口未建好也无妨） | 用户（「点击可以打开应用，这个地方要做下处理，在消息面板点击消息后，刘海要自动收起」）+ agent（落点与取舍） | **为什么不做完整的 `NotchHandle`**：只做「收起」一条是因为**当前唯一消费者**是通知列表行点击（打开 App 后把面板收起来）；`requestExpand` / `phase` / `geometry` 的消费者（模块自己驱动展开、按 phase 分支渲染）本批不存在，提前固化只会让 P1-2 的状态机去适配一个猜出来的形状。**为什么闭包由应用侧注入、内核不做裁决**：06 §3.3 R1 的「模块不得自己碰窗口」在**内核**这一层同样成立——注册表拿不到 `DynamicIslandViewModel`，也拿不到「鼠标在哪块屏」；把闭包从组合根一路透传到 `RedrawUIHandle` 之后，内核只知道「有个模块请求收起」，「哪块屏、能不能收、收起动画」全在应用侧一处裁定，单测注入计数器即可断言转发。**默认 `{}` 的代价**：没有接线时这条请求静默无效（不崩、不降级），这与 D-05 的「未实现面先不给」同口径——但**不是**「先留着以后接」：应用侧的唯一调用点在同一笔改动里已接线。**没验证的部分**：收起动画与「先开应用再收起」的体感需实机确认（单测只钉「顺序是 openApp → collapse」与「闭包被转发」） |
| D-29 | **展开态右下角拖动把手：一个拖动同时改宽高**（2026-09-29，用户选定方案 B，见「已知限制」30）：① **把手**落在 `ContentView.mainLayoutBase` 的 `.overlay(alignment: .bottomTrailing)`（画在 `clipShape` 之后、`compositingGroup` 之前）——只在 `vm.notchState == .open && !enableMinimalisticUI` 时出现；形态是 9pt 圆点（`Color.white.opacity(0.45)`，拖动中提亮到 `0.85`）+ 20pt 命中框，命中框距面板右下角各 14pt（圆点中心因此落在右下圆角内侧）。② **交互**是 `DragGesture(minimumDistance: 0)` + `.highPriorityGesture`：面板自己带着 `onTapGesture`（点一下展开 / 收起）与四条 `panGesture`，子视图手势本就优先，这里再显式提一档，**这四条既有手势一字未改**；`onChanged` 用**拖动开始时捕获一次的起点尺寸**（第一次 `onChanged` 取当前生效的 `openNotchSize`）+ `value.translation` 算新尺寸，`onEnded` 再算一次并写一遍。③ **写入链路与设置页滑块同源**：`Defaults[.openNotchWidth]` / `[.openNotchHeight]` + post `notchHeightChanged`（值没变不发通知），宽度另有 vm 的 `Defaults.publisher(.openNotchWidth)` sink；④ **夹取复用既有函数**（`currentOpenNotchResizeBounds()`：宽 `max(currentRecommendedMinimumNotchWidth(), sideLyricsRequiredNotchWidth())` … `maxAllowedNotchWidth()`，高 `openNotchHeightRange.lowerBound` … `effectiveOpenNotchHeightUpperBound`），位移 → 新尺寸抽成纯函数 `resizedPanelSize(start:translation:minWidth:maxWidth:minHeight:maxHeight:)`，取整后再用同一组边界复夹一次（上界可能是 0.9×屏高这类分数）；⑤ **读数胶囊**贴在圆点上方（`宽 × 高`，12pt 白字 + 深色半透明底，`allowsHitTesting(false)`），松手 0.8s 后淡出，**不新增本地化 key**（纯数字与 `×`）；⑥ **补一次窗口尺寸同步**（`syncWindowSizeAfterPanelResize` → `AppDelegate.ensureWindowSize(addShadowPadding(to: dynamicNotchSize), animated: false, force: false)`）：宽度本来就有实时链路（vm 的 sink），**高度没有**——`notchHeightChanged` 的观察者只做 `positionWindow`（用当前 frame 尺寸重新定位，不重算尺寸），所以高度是「下次展开才生效」（设置页滑块同样如此），拖动是连续交互等不到下次展开 | 用户（「（这个高度）要可以调，同时看看能否**在刘海打开的情况下，直接拉动调整宽高**」→ 在 A/B 两案里选定 **B：右下角小圆点，一个拖动同时改宽高**）+ agent（落点、取舍与实测） | **为什么是「起点 + 累计位移」而不是每帧读当前值累加**：拖动每一帧都写 `Defaults` 并触发布局 / 窗口重排，把手自己会跟着鼠标跑；用当前值累加时下一帧读到的是「已经追过一次」的尺寸，同一段位移被重复计入（越拖越快 / 抖）。固定起点是唯一稳定口径，代价是**半程跟随**（把手自身在动，`.local` 坐标系把面板位移也计入 `translation`，稳态折损约一半；见「已知限制」30③）。**为什么把手放在 `mainLayoutBase` 的 overlay 而不是 `rootBodyView` 的 ZStack**：overlay 的框就是面板（含 `.padding([.horizontal,.bottom], 12)` 与背景 / 裁剪形状）的框，14pt 内缩即可稳定落在右下圆角内侧；放在根 ZStack 上则要自己减掉 `notchHorizontalPadding` / 阴影 padding / 刘海外扩，屏与模式一变就得重算。**为什么必须在 `clipShape` 之后**：overlay 不被裁剪，圆点与读数不会被圆角切掉；同时它不参与任何尺寸计算（overlay 不改变被贴视图的尺寸）。**为什么补 `ensureWindowSize` 而不是只发通知**：见 ⑥——只发通知等于「拖动时高度看不见变化」，与用户要的「打开的情况下直接拉动」相悖；这一句与 vm 各条 sink 是同一调用口径（`addShadowPadding(to:)` + `animated/force`），`force: false` 让尺寸没变的重复调用是 no-op，宽度那条链路不受影响。**为什么读数只显示数字**：`840 × 400` 是纯数字 + 乘号，不需要任何本地化 key（限制 18 的本地化债不再扩大）。**实测取证（2026-09-29，CGEvent 注入 + `defaults read` + 窗口 frame 列表）**：① 基准 840×850 → 左下拖 (−100,−120) 得 **773×790**，窗口同步为 773×812（= 高 + 22，即面板高确实跟着拖动走）；② 继续向左拖 → 宽度**停在 770**（本机 tab 数 ≥ 6 的推荐最小宽），窗口 770×812；③ 连续上拖 → 高度逐档 690→590→490→390→290→190→**120 停住**，每一档窗口高都 = 高度 + 22；④ 从 700 下拖 → 高度**停在 850**（= `min(850, 屏 949×0.9)`），再拖仍是 850；⑤ 水平拖动 840→1135 / 1135→934，宽度即时跟随。**没验证的部分**：① 拖动过程中宽度那条链路带 `.smooth` 动画（沿用 vm 的既有写法），连续拖动的手感需用户实机确认；② 反向拖动（拉大后立刻反向）的体感需用户确认（单测只钉纯函数的四个方向与夹取）；③ 自有高度源的 tab 上「拖高度看不出变化」是设计取舍（见限制 30②），未按 tab 门控；④ 副屏（1920×1080）窗口同步只做了「逐屏一并改 frame」，未在副屏上实拖验证。 |
| D-30 | **本批（p2-home-strip，2026-09-29）落进内核面的五条口径**（协议 / 注册表 / 组合根 / 偏好键，逐条见「本批新增 / 变更的口径」）：① `Surface.home`（第四取值，校验规则不变）② `ModuleRegistry.homeEntries` 第三条投影（声明与内容分离、不缓存、排序键复用 `(order, id)`）③ `setEnabled` 状态机：**`failed` 不可逃逸**（置关不降级、无隐藏重试通道）、**全局单调代次**作废 `.activating` 期间的状态写回、只改内存不写偏好 ④ `Defaults[.moduleEnableOverrides]` **缺键 = 用户未表达**（回落 `manifest.defaultEnabled`，不是 `false`）⑤ `KernelBootstrap.enablementGate(registry:)` 作为该偏好键的**唯一消费点**。**本批零新增 capability / TCC 授权 / 出站请求** | 用户（首页 strip + 开关闭环的定稿与「不许硬拉伸」）+ agent（状态机口径与代次机制） | 各条的理由与代价见 [17-nookx-adoption.md](17-nookx-adoption.md) D-02…D-14 与本节各项；`failed` 不可逃逸是对 06 §3.3 硬性规则 1 的守诺（T2 审查实测出"置关→置开"会给 failed 开出一条隐藏的重试通道，与承诺矛盾），代次机制则是"置关后那条在飞的 `activate()` 不能把状态改回 `.active`"的唯一保证。本批不动渲染路径以外的上游布局（minimalistic / 歌词侧栏逐字未动），可回退。 |
