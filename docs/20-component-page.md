# 组件页与接管：让已实现的功能看得见、管得着

| 项 | 值 |
|---|---|
| 状态 | 已实现（2026-09-30） |
| 最后更新 | 2026-09-30 |
| 关联来源 | [12-p1-batches.md](12-p1-batches.md) §已交付 · `p2-p0-visible` 的下一批；[14-module-manifests.md](14-module-manifests.md) §1 与 T-3/T-12；[16-nookx-reference.md](16-nookx-reference.md) §4.4 里「组件页列不全」那条尾账 |

> **怎么读**：§背景与目标 / §明确不做 / §备选与取舍 是这场改动的判断依据（人审先看这三节）；
> §接口与数据形状 是参考型小节（执行者与机器查考），人审可跳过；§已知限制 / §实际交付 是留给后来人的。
>
> **读者分界**：§背景与目标、§备选与取舍、§明确不做、§已知限制 给人读；
> §做法 的机制描述与 §接口与数据形状 是给执行者与模型的契约，精确到不用再做设计决策。

## 一句话方案

**接管三个、登记七个**：计时器 / 镜子 / 音乐从「上游写死的渲染点」变成**真模块**——模块提供那个 tab 或首页块，
**启用真源就是上游那个开关键本身**（用户在组件页和在上游设置页拨的是同一个开关）；剪贴板 / 日历 / 锁屏天气 /
统计 / 文件架 / 终端 / 便签这七个暂时不改渲染归属的功能，在组件页第二段各得一张**上游开关卡**
（卡即那个 `Defaults` 键的镜像 + 一行「开了会在哪看到什么」）。

## 背景与目标

### 现状（改前）

上游功能分成两类落点：一类**已经在模块内核里**（待办 / 通知 / 进度 / 启动台，四张卡在设置页「组件」里），
另一类**还是上游写死的分支**——它们的开关散在各自的设置页，开关本身是 `Defaults` 键，
渲染点是 `TabSelectionView` 的一个 `if` 或 `HomeStripView` 的一个内置块。于是出现两件事：

1. **组件页只列得出四张卡**。用户 2026-09-29 的原话是「音乐/日历/计时器/剪贴板/天气/镜子都在用却不在组件页」——
   他日常在用的六个功能里，五个在组件页**没有任何痕迹**。`p2-p0-visible` 那批给这四张卡补了「效果 / 出现位置」一行，
   让已有的卡说实话；**没解决的是卡本身不在那里**（[17](17-nookx-adoption.md) §已知限制 5 的缓解措施只是页面顶部一行
   「内置块在各自的设置项里开关」，用户看不到自己用的功能在哪）。
2. **同一件事有两个开关名**。模块的开关是 `Defaults[.moduleEnableOverrides]`（本机偏好），上游功能的开关是各自的
   `Defaults` 键（`enableTimerFeature` / `showMirror` / …）。同一个功能既「能不能出现」又「模块开不开」，
   一旦要模块化，两份状态就会互相打架——**必须先定哪一份是真源**。

### 预期结果（改后）

- 组件页第一段（组件）：待办 / 通知 / 进度 / 启动台 **+ 计时器 / 镜子 / 音乐**，共七张卡；前三张新卡背后是**真模块**：
  计时器的展开 tab、镜子的首页块、音乐的首页块都由模块提供，上游那三处写死的分支**已删除**（不是并存）。
- 新卡片的开关**就是上游那个开关键**：在组件页关掉计时器 = `enableTimerFeature = false`（上游设置页里同一项也变关，
  Timer tab 消失）；在上游设置页关掉，组件页的开关与 tab 也会跟着变（重同步，见 §做法 机制二）。
- 组件页第二段（功能）：剪贴板 / 日历 / 锁屏天气 / 统计 / 文件架 / 终端 / 便签各一张卡，卡面写清「开了在哪看到什么」，
  开关直接写上游键——**这一段是纯登记，不改任何渲染归属**。
- **零回归**：tab 数（决定刘海最小宽度）与改动前逐字相同；首页 strip 的块名单、顺序、丢块规则与改动前相同
  （只有块的身份从「内置块」换成「模块块」，顺序表的旧键做了映射，见 §做法 机制四）。

### 承接关系与本次增量

**承接** [14](14-module-manifests.md)：§1 的 `timer` / `mirror` / `nowplaying` 三行按 T-12 的取值口径落地
（`manifestVersion 1` / `version "1.0.0"` / `apiVersion = HostInfo.currentAPIVersion` / `kind builtin` /
`icon.type symbol` / `name`·`summary` 用 `module.<shortID>.*` key 形态）；T-3 的「接管模块 config 不新发明键、
一律映射上游 `Defaults` 键名」在本批落地为**只登记键名与默认值**（读侧仍读上游键，见 §已知限制 1）。

**本次增量**（承接之外新做的判断，逐条进 §决策摘要）：

| 增量 | 是什么 |
|---|---|
| 接管语义 | 定下「接管 = 模块拥有渲染点 + 启用真源是上游键」这一条，并给出三条落地钩子（§接口与数据形状 1） |
| 重同步 | 上游键被别处改动（上游设置页）时把注册表状态拉回来，避免「关了功能但 tab 还在」 |
| 功能卡段 | 七个暂不接管的功能在组件页的登记形态（卡 = 上游键镜像） |
| 顺序键迁移 | 首页块顺序表里的 `builtin.music` / `builtin.mirror` 映射到模块 id（读取时映射一次） |
| tab 落位 | 接管后该 tab 落在「模块 tab 段」（末尾），顺序变化被显式接受（§已知限制 2） |

## 做法

### 机制一：接管三件套（启用真源 / 渲染点归属 / tab 可见性）

**启用真源是上游键**：接管模块在类型上声明 `takeoverEnableKey`（`Defaults.Key<Bool>?`）。组合根的启用门
（`KernelBootstrap.enablementGate`）见到这个键就**直接读它**，不再看 `moduleEnableOverrides`、也不看
`manifest.defaultEnabled`。于是「模块开不开」与「功能开不开」是同一个布尔量，**不存在第二份状态**，也就
不存在第一次打开时的迁移（老用户把计时器关着 → 模块本来就是关的）。

**渲染点归属**：模块按 `surfaces` 提供内容，上游那一处写死的分支删除——一对一替换，不允许并存（并存就是两个 tab
或两个块）。本批两种形态各一例：

- `expanded`（tab）：计时器模块的 `content(for: .expanded)` 返回上游那个 `NotchTimerView`，`TabSelectionView` 里
  建 Timer tab 的那条 `if` 与 `enabledStandardTabCount()` 里对应的 `+1` 同时删除（tab 由模块投影产出，计数由
  `tabEntries.count` 承担，见机制五）。
- `home`（首页块）：镜子与音乐模块的 `content(for: .home)` 返回与内置块逐字相同的视图，`HomeStripView` 里对应的
  内置块分支删除。

**tab 可见性**：上游「tab 出不出来」这件事不总是等价于「功能开没开」——计时器还要求 `timerDisplayMode == .tab`
（另一种显示方式是折叠态里的倒计时）。所以模块另有一个 `isTabVisible()` 钩子（缺省 `true`），由模块自己回答
「此刻我该不该在 tab 列表里」；投影每次读都问一次（投影不缓存），因此它读到的是当下值。

**块宽继承**：首页块由宿主统一声明宽度（180/240，[17](17-nookx-adoption.md) D-11），但接管是「接住原来的呈现」，
不是顺手把音乐块从 420 压到 240。所以模块多一个 `homeBlockWidth` 钩子（缺省 `nil` = 用宿主统一值）：
接管模块声明它接管的那一块**原本**的宽度（镜子 140/160、音乐 300/420），`HomeStripView` 优先用它。
D-11 的口径因此收窄为「**新增**模块不参与宽度决策；接管模块继承被接管块的宽度」。

**存在性判据不再重复展开态**：`.home` surface 的定义就是「展开面板首页的一条 strip 块」，块只会在展开态被渲染，
所以镜子模块的判据是 `showMirror && cameraAvailable`——不重复 `vm.notchState == .open`（旧的重复是内置块的写法，
见 [17](17-nookx-adoption.md) 已知限制 7 的第二句，本批同批回写）。

### 机制二：重同步桥（上游键 → 注册表状态）

启用真源是上游键以后，**上游设置页也是这个开关的一个入口**。键被改动时注册表的 `states` 必须跟上，
否则会出现「计时器已经关了、tab 还在」。组合根因此在 `bootstrap()` 里为每个接管模块订阅它那一个键
（`Defaults.publisher(key, options: [])`——本项目 Defaults 包只有 `.initial` / `.prior` 两个选项，
`.initial` 会在订阅瞬间改变激活次序，故禁用；取值写 `change.newValue`），变化时调
`ModuleRegistry.setEnabled(_:for:)`——用的就是设置页那条同一条路径（`setEnabled` 本身**不写偏好**，所以不会自激）。

订阅只处理「已激活 ↔ 已关闭」这一维；`failed` 仍是终态（[17](17-nookx-adoption.md) D-13 不变：
重同步不会把一个失败模块救活，也不会把它降级）。

### 机制三：功能卡段（上游键的镜像，不改渲染归属）

组件页在「组件」卡片之后新增一段「功能」：一行一个**尚未模块化的上游功能**，卡面 = 图标 + 名称 +
一行「效果 / 出现位置」+ 开关。开关直接读写那一个 `Defaults` 键，**没有模块、没有内核状态**——
它是「把散在上游设置页的总开关收拢到一页」的登记表，作用与收益都只到「看得见、拨得动」为止；
它的渲染归属、详细设置仍在上游那一处（卡面文案必须写明这一点，否则又会造出「打开开关但界面没变化」的错觉）。

### 机制四：首页块顺序表的历史键迁移

首页块顺序（`Defaults[.homeBlockOrder]`）以块 id 为键。音乐与镜子从内置块变成模块块以后，块 id 从
`builtin.music` / `builtin.mirror` 变成模块 id。表里存着旧键的用户（点过上移/下移的人）会突然发现顺序回到默认——
因此读取时做**一次映射**（旧键 → 新 id，仅当新 id 没有自己的值时；旧键保留在盘上不动，不做写回），
让「用户排过的顺序」在接管前后看起来一样。日历块的旧键（`builtin.calendar`）不迁移：它今天已经不在任何名单里。

### 机制五：tab 落位与计数

模块 tab 一直排在「上游 tab 之后」（`tabEntries` 是追加段），接管之后计时器 tab 因此从原来的第三位移到模块段。
**这是被显式接受的顺序变化**（§已知限制 2）：做精确定位需要一套 tab 排序机制，本批不做。
计数上必须**一一对应**——上游分支删一个、模块投影加一个，`enabledStandardTabCount()`（决定刘海最小宽度）
在任意开关组合下都必须与改动前相同。**判据落在 `enabledStandardTabCount()` 上**：它对计时器的贡献恒为
1 / 0 / 0（`enableTimerFeature` × `timerDisplayMode` 的三种组合），上游那一支删掉后由模块投影补位。
`TabSelectionView.tabs` 是私有计算属性，拿不到「条数相同」的直接断言，因此那一半靠 T2 的三条 `grep`
（上游分支已删）与这条计数用例共同承担。

### 机制六：计时器还有第二条入口（悬浮聚焦）与它自己的高度

计时器不是只有 tab 一个入口：计时在跑时**悬浮刘海会自动展开并聚焦计时器**（`ContentView` 的
`shouldFocusTimerTab` → `currentView = .timer`），另外 `.timer` 这个视图在**两个地方**拿到 250pt 的高度档
（`ContentView` 与 `DynamicIslandApp` 各一处）。接管后这条入口改走**模块 tab**
（`coordinator.selectModule(TimerModule.moduleID)`），两处高度判据也认模块路径——否则计时器一旦跑起来，
悬浮展开看到的是「内容在、tab 条上没有任何一个 tab 高亮」，面板高度也回落到默认档。
`.timer` 这个枚举成员与 `case .timer: NotchTimerView()` 分支**保留**（删除会牵动 `NotchViews` 的哈希与
`tabOrder` 的动画方向语义），但**不再有生产路径指向它**，代码注释要写明这一点。

### 机制七：接管模块的开关回弹是空操作

非接管模块 `activate()` 失败时，设置页把用户偏好写回 `false`（回弹）。接管模块**不能**照做：
它的偏好就是上游那个总开关（`enableTimerFeature` / `showStandardMediaControls` / `showMirror`），
回弹等于「因为模块激活失败，把用户的功能关了」——`showStandardMediaControls` 还会连带关掉 Home tab 的判据。
所以接管模块的回弹**什么都不写**（偏好本就等于用户表达），只由卡片显示失败态；这是 §已知限制 7 之外的独立口径。

## 备选与取舍

**① 全部 10 个接管模块一次做完（[14](14-module-manifests.md) §1 的清单）还是 3 + 7？**
选 **3 + 7**。剩下七个里，日历（首页日历行由 `NotchHomeView` 直接渲染）与锁屏天气（渲染点在锁屏管线，
`lockscreen` surface 尚未落地）**今天没有「模块可以拥有的渲染点」**；剪贴板有四种显示方式
（`popover` / `panel` / `separateTab` / `notchTab`，其中 `separateTab` 与便签共用一个 tab），
接管它要先决定「一个 tab 两个主人」怎么办；统计 / 文件架 / 终端是干净的单键单点，但用户没在用，
优先级低于上述三者。硬做会为了形状统一而发明一堆特例——**先让它们能被看见与拨动（功能卡段），
接管留到各自的渲染归属能一句话说清时**。

**② 只加卡片、三个也不接管？** 否。功能卡段解决「看得见」，解决不了「组件页管着的是不是真的那件事」：
音乐 / 镜子 / 计时器是本项目最核心的三个功能，如果它们的开关在组件页写着 `showMirror`、
却在别的代码路径里被另一份模块状态压着，那张卡就是假的。**接管的成本只在三处钩子 + 一对一的代码替换**，
收益是「组件页说的就是真的」——这个交换值得。

**③ 启用真源用上游键，还是把上游键的值一次性迁进 `moduleEnableOverrides`？** 选**上游键**。
迁移只解决第一次，之后两份状态仍会漂（用户在上游设置页改一下就漂）；真源唯一则漂不起来。
代价是老用户没法「上游关着、单独把模块打开」——那本来也是无意义的组合（功能没开，模块渲染什么？）。

**④ config 字面接管（`ConfigHandle` 直接读写上游 `Defaults` 键）还是只登记键名？** 本批**只登记**。
接管写路径要动 `ConfigHandle` 的存储（今天写 `com.cmeng.gourd.module.<shortID>` 命名空间），
属于配置层（P1-3 的 ConfigStore）的事，塞进本批会把「渲染归属接管」和「配置存储接管」两件事混在一起，
而后者没有任何用户可见收益（上游设置页已经能改这些值）。**登记的价值是声明与审计一致性**（[14](14-module-manifests.md) T-3）。

**⑤ tab 精确定位（按上游位置插回）还是落模块段？** 落模块段。精确定位要在 `TabSelectionView` 里引入
「上游 tab 排位表 + 模块 tab 按同一尺度插值」，而 `order` 这个字段今天已经兼着折叠槽位序、展开 tab 序、
首页块序三个语义（[13](13-runtime-kernel.md) 已知限制 25）——再加一层尺度会把它彻底变成玄学。顺序变化写进
§已知限制，等 tab 排序机制（需要 UI）再一起做。

## 接口与数据形状

### 1. 模块侧的三条钩子（`DynamicIsland/Kernel/GourdModule.swift`）

**落地形态 = 协议要求 + 扩展缺省**（实现期实测，D-14）：三条钩子在 `GourdModule` **协议体内**声明为
要求，同时在文件末尾的 `public extension GourdModule` 里给缺省实现（即下面这个代码块）。
只写扩展不行——注册表一律经 `any GourdModule.Type`（`moduleTypes` 的取值形态）取用元类型成员，
而协议扩展的静态成员走**静态派发**：只写在扩展里时，`(any GourdModule.Type).homeBlockWidth` 拿到的是
缺省值（`nil`），模块自己的声明被**静默忽略**（无编译错误、无警告，只有行为不对）。
协议体里的三条要求与扩展里的三条缺省**逐字同形**，既有四个内置模块因此一行未改。

```swift
public extension GourdModule {
    /// 接管模块的**启用真源**：非 nil 时，本模块的启用状态由这个上游 `Defaults` 键承载——
    /// 组合根的启用门直接读它，`moduleEnableOverrides` 与 `manifest.defaultEnabled` 都不再看。
    /// 缺省 nil = 非接管模块（走既有口径）。
    static var takeoverEnableKey: Defaults.Key<Bool>? { nil }

    /// 本模块此刻是否出现在**展开面板的 tab 列表**里（缺省 true）。
    /// 只在「启用之外还有别的可见性条件」时才需要重写（本批唯一一例：计时器的
    /// `timerDisplayMode == .tab`）。**每次读都问一次**（投影不缓存）。
    static func isTabVisible() -> Bool { true }

    /// 首页块的宽度声明（缺省 nil = 用宿主统一值 180/240，`docs/17` D-11）。
    /// **只有接管模块需要重写**：它接住的是被接管块原本的宽度（镜子 140/160、音乐 300/420），
    /// 不是为了形状统一把老块改小。类型是内核侧的 `ModuleHomeBlockWidth`（Host 的
    /// `HomeBlockWidth` 由 `HomeStripView` 自己映射，内核不引用渲染层类型）。
    static var homeBlockWidth: ModuleHomeBlockWidth? { nil }
}
```

```swift
/// 首页块宽度的**内核侧**取值形态（`min` = 低于它不如不显示，`ideal` = 富余时用它）。
/// Host 的 `HomeBlockWidth` 与它同形不同名，映射在 `HomeStripView`（一处，3 行）。
public struct ModuleHomeBlockWidth: Sendable, Equatable {
    public let min: CGFloat
    public let ideal: CGFloat
}
```

**没有显式 `public init`**（照上面代码块逐字落地）：`public struct` 的 memberwise init 是 internal，
所以它只能在 app target 内构造（三个接管模块与 `HomeStripView` 的映射都在这个 target 里）。
将来若要让模块声明出到独立 target/SDK，需要补一个 `public init`。

### 2. 注册表与组合根（`ModuleRegistry.swift` / `KernelBootstrap.swift`）

```swift
// ModuleRegistry（public）
public func takeoverEnableKey(for id: String) -> Defaults.Key<Bool>?   // moduleTypes[id]?.takeoverEnableKey
public func homeBlockWidth(for id: String) -> ModuleHomeBlockWidth?    // moduleTypes[id]?.homeBlockWidth
// tabEntries 的过滤条件追加 `&& (moduleTypes[id]?.isTabVisible() ?? true)`（比较器与排序不动）

// KernelBootstrap（internal：单测直接验三档回落，不必跑整个 bootstrap()）
// enablementGate(_:) 的判定顺序（三段）
//   1. registry.takeoverEnableKey(for: id) 非 nil → Defaults[key]（overrides 与 defaultEnabled 都不再看）
//   2. 否则 Defaults[.moduleEnableOverrides][id] ?? registry.manifests[id]?.defaultEnabled ?? false
static func enablementGate(registry: ModuleRegistry) -> (String) -> Bool
// 为每个接管模块订阅它那一个键，变化 → await registry.setEnabled(change.newValue, for: id)
static func startTakeoverBridge(registry: ModuleRegistry)   // 幂等：进入先 removeAll()
// 只为可测性：当前订阅条数，用例据它断言幂等
static var takeoverSubscriptionCount: Int { get }
```

**调用次序**（`bootstrap()` 内）：落首启默认值 → `register(builtinModules, enabled: enablementGate(...))`
→ `startTakeoverBridge(registry:)` → `await registry.bootstrap(collapse:)`。桥必须在 `register` **之后**
起（它按 `registry.manifests.keys` 找接管模块），在激活 **之前** 起（激活那一刻的 `states` 由门判定，
桥只负责之后的「别处改键」）。

**订阅的既有形态**（本项目 Defaults 包只提供 `.initial` / `.prior` 两个 `ObservationOption`，
`options: []` 是仓库里唯一的既有写法，见 `DynamicIslandApp.swift` 的同款订阅）：

```swift
takeoverSubscriptions[id] =                                      // [String: AnyCancellable]，进入前先 removeAll()
    Defaults.publisher(key, options: [])                         // 不加 .initial：订阅瞬间不得改变激活次序
        .removeDuplicates { $0.newValue == $1.newValue }
        .sink { change in Task { @MainActor in await registry.setEnabled(change.newValue, for: id) } }
```

**容器是字典、不是 `Set<AnyCancellable>`**：`AnyCancellable.store(in:)` 只有 `Set` 与
`RangeReplaceableCollection<AnyCancellable>` 两个重载，字典不匹配，所以这里是显式赋值
（按 id 存也让调试能看出「哪个模块的订阅在不在」）。

### 3. 开关的写路径（`DynamicIsland/Kernel/ModuleEnablementWrite.swift`，新文件）

```swift
/// 组件页写开关的**唯一入口**：接管模块写上游键，非接管模块写 `moduleEnableOverrides`。
enum ModuleEnablementWrite {
    /// 接管键非 nil → `Defaults[key] = enabled`（覆盖上游键）；否则整字典读改写 overrides。
    @MainActor static func write(_ enabled: Bool, for id: String, takeoverKey: Defaults.Key<Bool>?)
}

/// 回弹策略（D-13）：`activate()` 失败时应当写回的偏好值；**nil = 什么都不写**。
enum ModuleEnablementRollback {
    /// 非接管模块 → `false`（把用户的开关拨回去）；接管模块 → `nil`
    /// （它的偏好就是上游总开关，回弹等于「因为模块激活失败，把用户的功能关了」）。
    static func preferenceToWrite(takeoverKey: Defaults.Key<Bool>?) -> Bool?
}
```

### 4. 首页块顺序的历史键映射（`HomeBlockOrdering.swift`）

```swift
/// 历史键 → 模块 id 的映射（读取时做一次，不写回盘）：
/// `builtin.music` → `com.cmeng.gourd.music`、`builtin.mirror` → `com.cmeng.gourd.mirror`。
/// 仅当新 id 在表里没有自己的值时生效；`sorted(...)` 内部先过它。
static func migratingLegacyIDs(_ overrides: [String: Int]) -> [String: Int]
```

**「加一条」不是「换一条」**：返回的表里**旧键仍然在**（别名语义，见 §已知限制 11），
`sorted` 只查名单里出现过的 id，故留下的旧键无害。模块 id 在映射表里是字面量
（`legacyIDToModuleID`——本文件是纯逻辑、不认模块类型），两处一致由用例拿 `MirrorModule.moduleID` /
`MusicModule.moduleID` 查表钉住。

### 5. 三个接管模块的 manifest（逐字取值）

| 模块 id | `surfaces` | `defaultPlacement` | `icon.name` | `defaultEnabled` | `takeoverEnableKey` | `homeBlockWidth` | `isTabVisible()` | 渲染点 |
|---|---|---|---|---|---|---|---|---|
| `com.cmeng.gourd.timer` | `[.expanded]` | nil（tab 落模块段） | `timer` | `true`（= `enableTimerFeature` 默认） | `Defaults.Keys.enableTimerFeature` | nil | `Defaults[.timerDisplayMode] == .tab` | `NotchTimerView()`（展开 tab） |
| `com.cmeng.gourd.mirror` | `[.home]` | `Placement(slot: nil, order: 2)` | `camera` | `false`（= `showMirror` 默认） | `Defaults.Keys.showMirror` | `140 / 160` | —（不声明 `expanded`） | `CameraPreviewView(webcamManager: WebcamManager.shared)`，门控 = `showMirror && WebcamManager.shared.cameraAvailable`（答 `.none` 不占位） |
| `com.cmeng.gourd.music` | `[.home]` | `Placement(slot: nil, order: 0)` | `music.note` | `true`（= `showStandardMediaControls` 默认） | `Defaults.Keys.showStandardMediaControls` | `300 / 420` | — | `MusicPlayerView(albumArtNamespace:)`（命名空间经环境注入，见 6），门控 = `showStandardMediaControls && (!autoHideInactiveNotchMediaPlayer \|\| MusicManager.shared.hasActiveSession)` |

三个模块一律：`manifestVersion 1`、`version "1.0.0"`、`apiVersion = HostInfo.currentAPIVersion`、`kind "builtin"`、
`icon.type "symbol"`、`permissions []`、`name`/`summary` 用 `module.<shortID>.name` / `.summary`；
每个模块还有一个 `static let moduleID`（模块 id 的**唯一字面量**，供 `selectModule(...)` 等调用点用）；
`defaultEnabled` **填上游键的默认值**（[14](14-module-manifests.md) T-12 对接管模块的口径——它只在
「接管键读不到」时不生效，填它是为了让卡片上那行「默认关闭」只在镜子卡出现）；
`config` 只登记上游键名与上游默认值（`timer`：`enableTimerFeature` / `timerDisplayMode` / `timerPresets`；
`mirror`：`showMirror` / `mirrorShape` / `selectedCameraID`；`music`：`playerColorTinting` / `useMusicVisualizer`），
**读写仍走上游键**（§已知限制 1）。**默认值一律从 `Defaults.Keys.<键>.defaultValue` 取**（不抄字面量，
D-15）；`timerPresets` 因类型是 `[TimerPreset]` 而只登记 `type: list` / `itemType: string`、不给 `default`。

**勘误（`music.config` 的一项）**：本批计划里把 `useMusicVisualizer` 写成了 `(boolean, false)`，
**以上游真源为准 = `true`**（`DynamicIsland/models/Constants.swift:989` 是
`Key<Bool>("useMusicVisualizer", default: true)`；同段的 `playerColorTinting` 也是 `true`）。
登记值必须等于真源值，否则这份登记的审计价值当场失效（D-15）。

### 6. 音乐块的命名空间注入（`DynamicIsland/Host/HomeStripView.swift` + 模块）

```swift
/// 展开面板的 matchedGeometry 命名空间（折叠态播放器与展开态封面配对的唯一一份）。
/// 首页块由 `HomeStripView` 注入（它本来就是这条命名空间的持有者）。
private struct HomeAlbumArtNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}
extension EnvironmentValues {
    var homeAlbumArtNamespace: Namespace.ID? { get/set }
}
```

模块侧读不到时用一个自己的 `@Namespace` 兜底（配对失效，但不会崩、不会空白）。

### 7. 功能卡段的数据形状（`DynamicIsland/components/Settings/ModuleSettingsSection.swift`）

```swift
/// 一段上游功能的登记行：开关就是那个 `Defaults` 键，没有模块、没有内核状态。
struct FeatureCard: Identifiable {          // internal（不是 private：见下）
    let id: String            // 上游键名，同时是效果文案 key 的后缀
    let nameKey: String       // 上游设置页里的同一个名称（`String(localized:)` 同源）
    let symbolName: String
    let key: Defaults.Key<Bool>
    let effectKey: String     // `settings.features.effect.<id>`
}
// 表本身挂在视图类型上：static let featureCards: [FeatureCard]（七行，逐字见下）
```

**`FeatureCard` 与 `featureCards` 是 internal、不是 `private`**（D-16）：解析用例
（`TakeoverEnablementTests.testFeatureCardKeysResolve`）直接读**生产表本身**——表侧把 `id` / `effectKey` /
`nameKey` 的任一个写错才会红（变异实测会红）；测试另抄一份键表则查不出「表写错、文案对」。
这是本批唯一为可测性放宽的可见性，不新增公开 API、不改行为。

本批七行（`effectKey` → `nameKey`），`nameKey` **逐字沿用上游设置页里那一项的名称字面量**（同一个 key，
不另起说法；执行时在 `SettingsView.swift` 里那一项旁边取证）：
`settings.features.effect.enableClipboardManager` → `"Enable Clipboard Manager"`、
`settings.features.effect.showCalendar` → `"Show calendar"`、
`settings.features.effect.enableLockScreenWeatherWidget` → `"Show lock screen weather"`、
`settings.features.effect.enableStatsFeature` → `"Enable system stats monitoring"`、
`settings.features.effect.dynamicShelf` → `"Enable shelf"`、
`settings.features.effect.enableTerminalFeature` → `"Enable terminal"`、
`settings.features.effect.enableNotes` → `"Enable Notes"`。
`symbolName` 取各功能自己那套图标（`clipboard` / `calendar` / `cloud.sun.fill` / `chart.xyaxis.line` /
`tray.and.arrow.down` / `apple.terminal` / `note.text`）。

> **与本文档早先一版正文的差异**：原文的表格示例给的是短名（`"Clipboard"` / `"Calendar"` / …），
> 与同段「逐字沿用上游字面量」的指令互相矛盾；实现按指令取**上游字面量**（见 §决策摘要 D-16 与
> §已知限制 13——这条取舍的代价是七个名称 key 在 catalog 里没有 `en` 值）。

**接管模块的效果行**在同一张卡片上用另一个映射（`ModuleSettingsCard.effectKey(for:)`）：
`com.cmeng.gourd.timer` → `settings.modules.effect.timer`（展开面板的计时器标签页——只在
「计时器控制显示为 = 标签页」时出现）、`…mirror` → `settings.modules.effect.mirror`（首页块——摄像头可用时出现）、
`…music` → `settings.modules.effect.music`（首页块——有播放会话时出现；关掉「无会话自动隐藏」则常驻）；
非接管模块仍走既有 `settings.modules.effect.<shortID>`（待办 / 通知 / 进度那三条）。

### 8. 计时器第二入口的判据（`DynamicIslandViewCoordinator.swift`）

```swift
/// 「计时器这个页面此刻是不是被选中」——三条赋值点与两处高度档共用这一条判据。
func isTimerSurfaceSelected() -> Bool {
    currentView == .timer || (currentView == .module && selectedModuleID == TimerModule.moduleID)
}
```

**赋值点实为三处**（实现期 grep 实测，本文档机制六一节只写了悬浮聚焦一处）：
`ContentView` 的悬浮聚焦（`shouldFocusTimerTab` → `selectModule(TimerModule.moduleID)`）、
`NotchTimerView` 的点预设、以及同文件的 `startCustomTimer`——后两处都改走
`DynamicIslandViewCoordinator.selectModule(_:)`（它同时置 `selectedModuleID` 与 `currentView = .module`）。
高度档仍是两处（`ContentView` / `DynamicIslandApp` 各一），两处都改问 `isTimerSurfaceSelected()`。
`.timer` 这一档是**旧路径**，三条生产路径改走模块后已无生产调用者——保留它是为了不动 `NotchViews`
的哈希与 `tabOrder` 的方向语义（§已知限制 10）。

## 明确不做

| 不做的事 | 为什么 |
|---|---|
| 日历行 / 锁屏天气的**渲染接管** | 今天没有「模块可以拥有」的渲染点：日历行由 `NotchHomeView` 直接渲染，锁屏天气在锁屏管线（`lockscreen` surface 尚未落地）。本批只给功能卡 |
| 剪贴板的渲染接管 | 四种显示方式，其中 `separateTab` 与便签共用一个 tab——「一个 tab 两个主人」要先定归属规则。本批只给功能卡 |
| 统计 / 文件架 / 终端 / 便签的渲染接管 | 干净但用户没在用；接管它们不改变任何可观察行为，推下一批 |
| 剩下的接管模块（`nowplaying` / `lyrics` / `shelf` / `controls` 的完整形态） | 见 [14](14-module-manifests.md) §4.3：依赖私有 API 或子进程的部分不在本批 |
| `config.json` 写路径接管（`ConfigHandle` 读上游键） | 属配置层（P1-3 ConfigStore）；本批只在 manifest 里登记键名（§备选与取舍 ④） |
| tab 排序机制 / tab 拖动 | 需要新 UI 与新排序语义；本批接受「接管后 tab 落模块段」（§已知限制 2） |
| 折叠态左右槽位 | 用户 2026-09-29 已决定降级（依赖左右两侧的模块先齐）；本批不声明任何 `compact` |
| 功能卡段的「详细设置」内嵌 | 卡只给开关与效果行，详细项仍在上游设置页（不复制上游表单） |

## 实际交付

**已交付**（工作流 `p2-takeover`，2026-09-30；提交 `1de20d4d`…`423e0918`，`1de20d4d` 是设计文档先行的
方案门提交，其后 7 个提交是本批的实现与回写）。

| 类 | 落点 | 交付物 |
|---|---|---|
| 三个接管模块 | `Modules/Takeover/TimerModule.swift` / `MirrorModule.swift` / `MusicModule.swift`（均新） | manifest（§接口与数据形状 5 逐字）、三条钩子、`content(for:)`、`static let moduleID`；文件内私有的块视图（`MirrorHomeBlockView` / `MusicHomeBlockView`）与判据纯函数（`MirrorModule.isVisible(showMirror:cameraAvailable:)`、`MusicModule.isVisible(showStandardMediaControls:autoHideInactive:hasActiveSession:)`） |
| 内核三件套 | `Kernel/GourdModule.swift`、`Kernel/ModuleTypes.swift`、`Kernel/ModuleRegistry.swift` | 三条钩子（协议要求 + 扩展缺省）、`ModuleHomeBlockWidth`、`takeoverEnableKey(for:)` / `homeBlockWidth(for:)`、`tabEntries` 追加 `isTabVisible()` 过滤 |
| 组合根 | `Kernel/KernelBootstrap.swift` | 三段启用门 `enablementGate`、重同步桥 `startTakeoverBridge` + `takeoverSubscriptionCount`；`builtinModules` 七行（progress / todos / notifications / launcher / **timer / mirror / music**） |
| 开关写路径 | `Kernel/ModuleEnablementWrite.swift`（新） | `ModuleEnablementWrite.write(_:for:takeoverKey:)` + `ModuleEnablementRollback.preferenceToWrite(takeoverKey:)`（D-13） |
| 命名空间注入 | `Host/HomeAlbumArtNamespace.swift`（新） | `EnvironmentKey` + `EnvironmentValues.homeAlbumArtNamespace`（本仓第一处 `EnvironmentKey`）；`HomeStripView` 注入、`MusicHomeBlockView` 消费并按 `?? 自带 @Namespace` 兜底 |
| 顺序表迁移 | `Host/HomeBlockOrdering.swift` | `migratingLegacyIDs(_:)` + `legacyIDToModuleID`；`sorted(...)` 第一步先过它 |
| 上游分支删除 | `components/Tabs/TabSelectionView.swift`、`sizing/matters.swift`、`Host/HomeStripView.swift` | Timer tab 的 `if` 与两个 `@Default`、`enabledStandardTabCount()` 的 `+1`；镜子块与音乐块各四件（判据 / 分支 / 块宽常量 / `@Default`）。`HomeStripView` 因此**再无宿主内置块**：`HomeBlock` 的 `Payload` 枚举随最后一块删除，收成 `(id, defaultOrder, content)` |
| 计时器第二入口 | `DynamicIslandViewCoordinator.swift`、`ContentView.swift`、`DynamicIslandApp.swift`、`components/Notch/NotchTimerView.swift` | 新增 `isTimerSurfaceSelected()`；三处赋值点改走 `selectModule(TimerModule.moduleID)`；两处 250pt 高度档改判据 |
| 组件页两段 | `components/Settings/ModuleSettingsSection.swift` | 第一段**七张卡**（四张既有 + 计时器 / 镜子 / 音乐，各多一行 `settings.modules.effect.*`）；第二段「功能」**七张卡**（段头 `settings.features.title` + 脚注 `.footer` + 七条 `effectKey`）；写路径改调 `ModuleEnablementWrite`、回弹改问 `ModuleEnablementRollback`；顺序节删掉 `builtin.music` / `builtin.mirror` 两行与两个 `@Default`，只剩模块块 |
| 文案 | `DynamicIsland/Localizable.xcstrings` | 新增 **18 条**（`module.{timer,mirror,music}.{name,summary}` 六条 + `settings.features.title` / `.footer` / 七条 `effect` + 三条 `settings.modules.effect.*`），中英双语 `state = translated`；键数 **1520 → 1538**。另改写 `settings.modules.builtinHint` 中英两值 |
| 测试 | `DynamicIslandTests/TakeoverEnablementTests.swift`（T1 新建）、`DynamicIslandTests/ModuleKernelTests.swift` | 新文件 9 → **26** 条用例（启用真源 read-through、桥的幂等与 `failed` 终态、`isTabVisible`、三模块 manifest 契约、判据纯函数、迁移与排序、计数 1·0·0、`homeBlockWidth` 与回落、环境键缺省、文案可解析）；`ModuleKernelTests` 内置清单四行 → 七行并补三模块的 `states` / 投影期望；`project.pbxproj` 四处登记新测试文件。**全量 293 → 310 条，0 失败** |

**与计划的偏离及原因**：

1. **三条钩子同时声明为协议要求**（计划只给扩展缺省）——只写扩展会被静态派发静默忽略（D-14）。
2. **`music.config.useMusicVisualizer` 取上游真值 `true`**（计划写的 `false` 是勘误，D-15）。
3. **计时器的第二入口实为三处赋值点**（计划与机制六只写了「悬浮聚焦」一处；另两处是 `NotchTimerView`
   的点预设与 `startCustomTimer`）。判据函数 `isTimerSurfaceSelected()` 是 T3 产出的接口（§接口与数据形状 8）。
4. **`HomeStripView.HomeBlock.Payload` 收成 `content`**：最后一个内置块删除后单 case 枚举 + 重复的 id 是死结构；
   `sorted` 的用法逐字不变（D-10 的取宽度那半改走 payload 里的模块 id）。
5. **`MirrorModule.config.mirrorShape.values` 按枚举声明顺序**登记为 `["Rectangular", "Circular"]`
   （与上游设置页 Picker 的展示顺序相反；config 不参与渲染）。
6. **`FeatureCard` 与 `featureCards` 放宽为 internal + `nameKey` 取上游字面量**（D-16；文档 §7 原有表格
   与同段指令互相矛盾，实现按指令执行）。
7. **`.timer` 枚举成员只补注释、不动结构**（D-11 的保留口径；纯注释，随本批回写落地）。

**遗留项**（本批明确未做，逐条有出处）：

1. **日历行 / 锁屏天气 / 剪贴板 / 统计 / 文件架 / 终端 / 便签七项的渲染接管**——本批只给功能卡（§明确不做）。
2. **tab 排序机制 / tab 拖动**——接管后计时器 tab 落模块段（§已知限制 2；要做精确定位得先有排序机制）。
3. **`config` 写路径接管**——登记与真源仍是「只登记、读写走上游键」（§已知限制 1，属 P1-3 的 ConfigStore）。
4. **四处接线 / 赋值点没有自动化断言**（变异实测「改坏不红」）：卡片回弹接线、`settings.modules.effect.*`
   三条映射、`homeAlbumArtNamespace` 的环境注入、三条赋值点与两处高度档（§已知限制 12）。
5. **三处保留 / 过时项，本批刻意不动**：`.timer` 枚举与 `case .timer` 分支（§已知限制 10）；
   `HomeStripView` 的 `@EnvironmentObject var vm`（已无读点，改动前既有）；`HomeBlockOrdering.migratingLegacyIDs`
   注释里「设置页顺序节仍有 `builtin.*` 行」的理由（顺序节已收敛，该理由已过时，行为不受影响）。
6. **UI 层未目视**：组件页三段顺序、功能卡拨动方向、接管卡落点不写 `moduleEnableOverrides`、顺序节内容、
   悬浮聚焦的 tab 高亮与 250pt 档——人工验收清单见本批各任务报告。

## 已知限制

1. **接管模块的 `config` 只声明、不接管读写**：三个模块的 `config` 是上游键名与上游默认值的登记，
   模块行为直接读 `Defaults`（同一份真源），`ConfigHandle`（写 `com.cmeng.gourd.module.<shortID>`）对它们不生效。
   要真正接管写路径，得等配置层搬进 ConfigStore。
2. **接管后 tab 落模块段**：「Home → (上游 tab) → (模块 tab)」这个顺序里，计时器 tab 从第三位挪到模块段末尾，
   与待办 / 通知 / 启动台相邻（用户可见顺序变化）。要做精确定位需要 tab 排序机制，本批不做。
3. **重同步是异步的**：上游设置页关掉功能后，组件页的开关与 tab 在下一个主线程回合才变（订阅回调 → `setEnabled`），
   不是同一帧。极短窗口内两处显示可能不一致（毫秒级，无用户可见影响）。
4. **音乐块的命名空间注入靠环境键**：模块块如果拿不到 `homeAlbumArtNamespace`（例如将来在别处渲染），
   封面配对动画静默失效（不崩、不空白）。这是兜底而非正确形态——契约在 §接口与数据形状 6。
5. **功能卡不搬运上游设置**：卡上只有开关与一行效果说明；上游设置页里的细项（显示方式、预设、来源等）不在卡上，
   卡面文案必须显式指向那些页面。
6. **旧顺序键只在读取时映射**：`homeBlockOrder` 里 `builtin.music` / `builtin.mirror` 的旧值不会被改写或清理，
   一直保留在盘上（读取时映射一次生效）。将来清理它需要一次写回，本批不做。
7. **接管模块的 `failed` 仍是终态**：重同步桥不会重试失败模块（[17](17-nookx-adoption.md) D-13 不变）。
   若某个接管模块 `activate()` 抛错，用户重启应用仍走同一条路径（同一份上游键、同一段代码）。
8. **功能卡的开关是裸 `Binding`（不是 `@Default`）**：本页开着时，从**别处**（上游设置页）改同一个键，
   这张卡的显示不会即时刷新（关掉重开本页即可）。理由：动态键无法用 `@Default`，为七行各挂一个订阅不值当。
9. **选中的模块 tab 被关掉时，内容区停在原来的模块页**：`TabSelectionView.ensureValidSelection` 只在
   `.onAppear` 跑（上游既有行为），因此「正在看计时器 → 在设置里关掉计时器 → tab 消失但内容区还停在模块视图」
   会出现（内容区显示 `.unavailable` 的降级文案，不崩）。改这条要动 tab 选中态的刷新时机，不属本批。
10. **`.timer` 枚举成员与 `case .timer` 分支成了无生产路径的保留代码**：为了不动 `NotchViews` 的哈希语义与
    `tabOrder` 的动画方向，它们保留在原地（代码注释写明「新路径经模块 tab」）。删它们的收益只有清洁度，
    代价是一次跨枚举语义的改动。

**回写期补充（2026-09-30，实现期真正踩到的边界）**：

11. **旧顺序键保留在映射结果里（别名语义）**：`migratingLegacyIDs` 是「加一条」不是「换一条」——
    返回的表里 `builtin.music` / `builtin.mirror` 仍在（盘上也从不写回）。今天唯一的消费者 `HomeStripView`
    按名单里的 id 查表、未知 id 不参与排序，故无害；代价是表里长期多两条对已改名块无效的键
    （`HomeBlockOrdering.swift:111-117`，查表在 `:83-87`）。**同一函数注释里「设置页顺序节仍有 `builtin.*` 行」
    这条理由已过时**（T6 顺序节收敛成只剩模块块行），行为不受影响——下次动该文件时顺手删那半句。
12. **四处接线 / 赋值点没有自动化断言**（各由变异实测证实「改坏仍全绿」，不是推测）：
    ① **卡片回弹的接线**——策略函数 `ModuleEnablementRollback.preferenceToWrite` 有用例，但视图里那句
    「回弹时去问策略、而不是无条件写 `false`」（`ModuleSettingsSection.swift:482-485`）跑在 `Binding` 闭包
    的 `Task` 里、且需要一次 `activate()` 失败才触发，测试进程里没有可驱动路径；
    ② **`settings.modules.effect.*` 三条映射**（`ModuleSettingsSection.swift:522` 的 `effectKey(for:)`）——
    `ModuleSettingsCard` 是 `private struct`，用例够不到，映射里打错字只能靠组件页肉眼；
    ③ **宿主的环境注入**——`HomeStripView` 上那条 `.environment(\.homeAlbumArtNamespace, …)` 被注释掉
    仍是全绿（测试进程里没有宿主视图树，任何「读回刚写的环境值」的断言都只是把修饰符抄进用例）；
    ④ **计时器的三条赋值点与两处 250pt 高度档**——它们位于 SwiftUI 闭包与 `NSSize` 计算里，单测驱动不到，
    现有护栏是 `grep -rn "currentView = .timer" DynamicIsland/` 无命中 + 人工验收。
13. **七条功能卡名称在英语宿主下判据退化**：`nameKey` 逐字取上游设置页字面量，而这七个 key 在
    `Localizable.xcstrings` 里只有 `ko` / `nl` / `ru` / `th` / `tr` / `zh-Hans` / `zh-Hant`（**没有 `en`**）。
    `testFeatureCardKeysResolve` 的判据是 `Bundle.main.localizedString(forKey:value:nil,table:) != key`——
    英语语言环境下它原样返回 key（= 上游英文原文），断言不成立。这是「逐字沿用上游字面量」的必然结果（D-16），
    不是实现缺陷；代价是这套用例只在宿主能解析出非英语译文时有效。
14. **`isTimerSurfaceSelected()` 的模块分支在极简 UI 下不可达**：`DynamicIslandViewCoordinator.currentView` 的
    `didSet` 在 `enableMinimalisticUI` 开着时把非 `.home` 的赋值强制打回 `.home`
    （`DynamicIslandViewCoordinator.swift:118-122`），因此该模式下 `currentView == .module` 永远不成立——
    判据只剩 `.timer` 那一档（它同样无生产路径）。正常模式下两档都有效；记下来是因为「一条判据的两档在某个
    配置下都到不了」读判据本身看不出来，只有读 `didSet` 才知道。
15. **登记与真源的两处小落差（都是刻意）**：① `MirrorModule.config.mirrorShape.values` 按枚举声明顺序登记
    `["Rectangular", "Circular"]`，与上游设置页 Picker 的展示顺序相反（config 不参与渲染，见 §接口与数据形状 5）；
    ② `ModuleHomeBlockWidth` 没有显式 `public init`，memberwise init 是 internal——只能在 app target 内构造
    （当前三个接管模块与 `HomeStripView` 的映射都满足），将来要出到独立 target 就得补一个 `public init`。

## 验收标准

1. `xcodebuild test`（`DynamicIslandTests`）全绿，新增用例覆盖：启用真源 read-through、重同步桥的幂等与
   不被 `failed` 用、`isTabVisible` 契约、三模块的 `surfaces` 不含 `.compact`、顺序表历史键映射、
   计时器对 `enabledStandardTabCount()` 的贡献恒为 1 / 0 / 0、`homeBlockWidth` 钩子的取值与回退。
   （`TabSelectionView.tabs` 是私有计算属性，拿不到「条数一一对应」的直接断言——那一半由
   `enabledStandardTabCount()` 的用例与三条 `grep`（上游分支已删）共同承担。）
2. `TabSelectionView` / `HomeStripView` 里**不再有**计时器 tab、镜子块、音乐块的上游分支（一对一替换，不并存）。
3. 组件页第一段出现计时器 / 镜子 / 音乐三张卡、第二段出现七张功能卡，每张卡都有一行效果说明。
4. 在组件页关掉计时器 → 上游设置页的「计时器」开关也是关的；在上游设置页改 → 组件页跟着变（重启前后都不漂）。
5. 首页 strip 的可见块名单与顺序在接管前后一致（含用户排过顺序的场景，靠 §接口与数据形状 4 的映射）。
6. 面板宽度足够时，首页同时能看到音乐块与镜子块（与改动前同一门控条件下的同一结果）。

## 决策摘要

| ID | 决策 | 来源 | 理由 |
|---|---|---|---|
| D-01 | 接管 = **模块拥有渲染点 + 启用真源是上游键**（一对一替换，不并存） | agent | §备选与取舍 ③：真源唯一才不会漂；并存就是两个 tab 或两个块 |
| D-02 | 本批只接管**计时器 / 镜子 / 音乐**三个，其余七个走功能卡 | agent | §备选与取舍 ①：日历行与锁屏天气今天没有可拥有的渲染点；剪贴板的 tab 与便签共用；其余用户没在用 |
| D-03 | 接管模块的 `config` **只登记上游键名**，读写仍走上游键 | agent | §备选与取舍 ④：写路径接管属配置层，本批无用户可见收益 |
| D-04 | 接管后 tab 落**模块段**（顺序变化接受） | agent | §备选与取舍 ⑤：`order` 已兼三语义，再加尺度会让它变玄学 |
| D-05 | 上游键被别处改动时，由**重同步桥**拉回注册表状态 | agent | §做法 机制二：否则「关了功能 tab 还在」；复用 `setEnabled` 同一条路径 |
| D-06 | 首页块顺序表的 `builtin.music` / `builtin.mirror` **读取时映射**到模块 id，不写回 | agent | §做法 机制四：用户排过的顺序在接管前后应看起来一样；写回是额外的一次数据迁移，收益为零 |
| D-07 | 功能卡段是**纯登记**（卡 = 上游键镜像，不改渲染归属），卡面必须写明详细设置仍在上游页 | agent | §做法 机制三：不给用户造出「组件页管着一切」的错觉 |
| D-08 | 音乐块的命名空间**经环境键注入**，取不到时模块用自带 `@Namespace` 兜底 | agent | §接口与数据形状 6：不把 `Namespace.ID` 塞进模块内核的 API（那是渲染层的概念） |
| D-09 | 本批**不声明任何 `compact`**（不占折叠槽位） | agent | 折叠态左右槽位已被用户降级（2026-09-29）；中央槽位仍由待办持有 |
| D-10 | 接管模块**继承被接管块原本的宽度**（新增 `homeBlockWidth` 钩子；D-11 of [17](17-nookx-adoption.md) 的口径收窄为「新增模块不参与宽度决策」） | agent | 计划评审实测：模块块统一 180/240 会把音乐块从 420 压到 240、镜子从 160 压到 240——用户要的是「看得见、管得着」，不是顺手改变首页呈现 |
| D-11 | 计时器的**悬浮聚焦入口与 250pt 高度档改走模块 tab**（`selectModule`），`.timer` 枚举与 `case .timer` 分支保留但无生产路径 | agent | 计划评审实测：只删 tab 会让「计时器在跑 + 悬浮展开」落到「内容在、无 tab 高亮」且高度回落到默认档 |
| D-12 | `.home` surface **蕴含展开态**：镜子块判据 = `showMirror && cameraAvailable`，不重复 `vm.notchState == .open` | agent | `.home` 的定义就是「展开面板首页的一条 strip 块」；[17](17-nookx-adoption.md) 已知限制 7 的第二句在本批同批回写 |
| D-13 | 接管模块的开关**回弹是空操作**（不得因 `activate()` 失败把上游总开关写 `false`） | agent | 计划评审实测：照搬非接管模块的回弹会把用户的计时器 / 音乐功能关掉，`showStandardMediaControls` 还会连带关掉 Home tab 判据 |
| D-14 | `GourdModule` 的三条钩子**必须同时声明为协议要求**（扩展只提供缺省实现），不能只写在扩展里 | agent | 实现期最小复现（`swiftc -swift-version 5`）：只写扩展时经 `any GourdModule.Type` 取用一律走静态派发拿到缺省值（`nil` / `true`），接管模块声明的接管键 / 可见性 / 块宽被**静默忽略**——无编译错误、无警告，只有行为不对 |
| D-15 | 接管模块 `config` 的默认值一律取**上游真源**的 `Defaults.Keys.<键>.defaultValue`，不抄计划里的字面量（`useMusicVisualizer` = `true`，计划写的 `false` 作废） | agent | 登记的价值是「声明 = 真源」（§备选与取舍 ④）；两处各写一个字面量就会漂（`Constants.swift:988-989` 是 `true` / `true`） |
| D-16 | 功能卡 `nameKey` 取**上游设置页字面量**（不是本文档 §7 早先表格里的短名），`FeatureCard` / `featureCards` 因此放宽为 internal 供用例直读生产表 | agent | §7 同段指令（「逐字沿用上游那一项的名称字面量」）与表格示例的短名互相矛盾，取指令；解析用例读**生产表本身**才能钉住「表写错、文案对」这类故障（变异实测：表侧改一个字符即红）；代价是七条名称在英语宿主下判据退化（§已知限制 13） |
