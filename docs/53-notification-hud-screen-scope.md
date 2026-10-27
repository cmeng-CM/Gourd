# 53 · 通知浮层的显示屏口径（主屏默认 + 外接屏开关）

| 项 | 值 |
|---|---|
| 状态 | 已实现（上屏已自测：两档真机样张见 §实际交付） |
| 最后更新 | 2026-10-27 |
| 关联来源 | 用户 2026-10-16 现场要求：「消息通知增加配置，消息通知打开的时候，主屏默认显示，增加开关，控制是否在外界显示器上显示消息通知」；承接 [13-runtime-kernel.md](13-runtime-kernel.md)（浮层窗口宿主）、[09-features-and-mechanisms.md](09-features-and-mechanisms.md) §5.5（通知浮层）、[ModuleHUDWindow.swift](../DynamicIsland/Kernel/ModuleHUDWindow.swift) 文件头的多屏段（2026-09-28 的「所有屏都显示」） |
| 读者 | 实现者看 §做法 / §接口与数据形状；维护者看 §已知限制 / §实际交付 / §决策摘要 |

> **怎么读**：§背景与目标 / §备选与取舍 是这场改动的判断依据；§接口与数据形状 是参考型小节；
> §已知限制 / §实际交付 是留给后来人的。

## 一句话方案

通知浮层（新通知到达时短暂浮现的那张卡片）**默认只显示在系统主屏**（`CGMainDisplayID()` 那块，
= 设置里标着「主显示器 / Main Display」的内建屏）；设置页「通知浮层」一节新增一个开关
**「在外接显示器上也显示」**（默认关），打开后 = 主屏 + 外接屏都出现。
**首页通知块表头（「清除」左边）还有一颗同款快捷开关**（2026-10-27 / D-08）：翻转的是同一个键，
点完下一条通知就换口径。
**岛本身的多屏口径（`showOnAllDisplays`）一个字没动**——两者的判据与代码路径都解耦了。

## 背景与目标

**旧口径**（`ModuleHUDWindowHost.targetScreenNames`，2026-09-28 定的）：浮层「哪些屏」只看
`showOnAllDisplays`——为真 → 全部屏；为假 → `preferred_screen_name` 指定的那块（用户没设时）
→ 退 `NSScreen.main` → 再退列表第一块。

**问题**（用户 2026-10-16）：`NSScreen.main` 是「**当前键窗所在的屏**」，不是「主屏」——
用户在外接显示器上干活时它会跟着跑（本机实测：同一台机器上它在内建屏与 VA2478 之间来回跳，
连我自己的悬停脚本都因此瞄错过屏）。于是「通知该在哪出现」变成了「取决于刚才在哪儿打字」。
用户要的是固定的那条：**通知固定落在主屏，外接屏由开关单独控制**。

**目标**：① 默认只在主屏；② 一个开关控制是否也上外接屏；③ **不碰岛、不碰展开面板**的多屏行为；
④ 改设置**当场生效**（下一条通知就是新口径），不用重启。

## 做法

一条链，四层各管一段（每层都是**唯一**落点）：

| 层 | 落点 | 职责 |
|---|---|---|
| 设置 | `Defaults.Keys.notificationHUDOnExternalDisplays`（默认 `false`） | 存一个 Bool |
| 模块 | `NotificationsModule.NotificationHUDPolicy.screenScope(onExternalDisplays:)` → `.mainDisplay(allowsExternalDisplays:)` | 设置 → **屏口径**（纯函数）；两条通道（DB / AX）都经 `screenScopeFromDefaults()` |
| 内核转发 | `UIHandle.presentTransient(view:ttl:screenScope:)` → `ModuleRegistry.presentHUD(…:screenScope:)` → `ModuleHUD.screenScope` | 把口径随这一条浮层存下来（**每条浮层自带口径**，不是全局状态） |
| 内核窗口 | `ModuleHUDWindowHost.targetScreenNames(scope:…)` → `mainDisplayTargetScreenNames(...)` | 屏口径 + 当前屏集合 → 目标屏名集合（纯函数，`NSScreen` 只在最外层转成入参） |

四条口径：

1. **每个模块自带屏口径**（`HUDScreenScope`）：`.followsIsland`（缺省）与
   `.mainDisplay(allowsExternalDisplays:)`（通知浮层）。**不是全局开关**——将来别的模块
   （计时器到点之类）要弹浮层时，可以各按各的语义选，不必被通知的选择绑住。
2. **旧签名保留**：`UIHandle` 的协议要求换成带 `screenScope` 的那条，但**协议扩展**补了一个
   `presentTransient(view:ttl:)` = `.followsIsland`——既有调用方与第三方模块**一行都不用改**，
   行为逐字不变（有专门用例钉）。
3. **主屏 = `CGMainDisplayID()`**（`primaryScreenName(for:)`）：系统的定义，也**永远不会跟着
   焦点窗口跑**。取不到（屏刚断开等）依次退 `NSScreen.main` → 列表第一块（与旧口径的兜底链同形）。
4. **改设置当场生效**：模块在**弹浮层那一刻**读设置（`screenScopeFromDefaults()`），
   没有观察链、没有缓存（与 ttl 那条同一形状）。

## 接口与数据形状

```swift
// Kernel（ModuleRegistry.swift）
public enum HUDScreenScope: Equatable {
    case followsIsland                                  // 缺省：与改动前逐字相同
    case mainDisplay(allowsExternalDisplays: Bool)      // 通知浮层
}
public struct ModuleHUD { …; public let screenScope: HUDScreenScope }
public func presentHUD(moduleID:view:ttl:screenScope: HUDScreenScope = .followsIsland)

// Kernel（ModuleContext.swift）——协议要求带口径，扩展补旧签名
protocol UIHandle { func presentTransient(view: AnyView, ttl: TimeInterval, screenScope: HUDScreenScope) }
extension UIHandle { func presentTransient(view: AnyView, ttl: TimeInterval) { ….followsIsland } }

// Kernel（ModuleHUDWindow.swift）——两条纯函数
targetScreenNames(scope:showOnAllDisplays:screenNames:primaryScreenName:mainScreenName:preferredScreenName:)
mainDisplayTargetScreenNames(allowsExternalDisplays:screenNames:primaryScreenName:fallbackScreenName:)
primaryScreenName(for: [NSScreen]) -> String?        // CGMainDisplayID() 那块

// 模块（NotificationsModule.swift）
NotificationHUDPolicy.screenScope(onExternalDisplays: Bool) -> HUDScreenScope
NotificationHUDPolicy.screenScopeFromDefaults() -> HUDScreenScope

// 设置（Constants.swift / SettingsView.swift）
Defaults.Keys.notificationHUDOnExternalDisplays      // Bool，默认 false
```

**每条浮层的窗口归属**：`present(_:)` 按**这一条**的口径算目标屏，再 `discardSlots(notIn:)`
清掉不在目标集合里的窗口，因此「开关从开 → 关」时外接屏上的旧窗口下一次弹浮层就会被收掉 ✓
（`isTargetScreen(_:)` 也改成读**台前那一条**浮层的口径，保证布局回调不会把该收的窗口又露出来）。

## 备选与取舍

| 备选 | 为什么不选 |
|---|---|
| **直接改 `targetScreenNames` 的「主屏」口径**（`.followsIsland` 也用 `CGMainDisplayID`） | 那会**改掉其它模块与既有用户的浮层行为**（他们现在跟着 `showOnAllDisplays` / 指定屏走）；用户只点名了「消息通知」，改动就该只落在通知上 |
| **复用 `showOnAllDisplays`**（岛开多屏 → 通知也上多屏） | 两者语义不同：那是「岛画在哪几块屏」。用户明确要「主屏默认 + 一个独立开关」；耦合起来会变成「想把岛放副屏就得连通知一起搬」 |
| 让内核按模块 id 特判（`moduleID == "…notifications"`） | 内核不认识模块 id（分层纪律）；口径应由模块**申报**、内核只消费 |
| 全局一个静/动态开关（不随浮层走） | 浮层是短命条目、会被后来者替换（覆盖语义）；口径随条目走才不会出现「前一条的口径把后一条的目标屏带偏」 |
| 让模块自己管窗口 / 自己算屏 | 06 §3.3 R1：模块不碰窗口；屏集合系统随时会变（拔插显示器），只有宿主层看得全 |

## 明确不做

- 不改 `showOnAllDisplays`、`preferred_screen_name`、岛与展开面板在多屏上的任何行为。
- 不给浮层加「跟随鼠标屏」（那是 2026-09-28 明确否掉过的旧口径）。
- 不做「主屏」的第三种定义（例如「岛所在的那块屏」）——用户要的是固定那块屏。
- 不顺手给别的模块换屏口径（计时器 / 音乐等浮层仍走 `.followsIsland`）。

## 已知限制

1. **主屏判定依赖 `CGMainDisplayID()`**：那是「主显示器 / Main Display」那一块，**不是**「岛所在
   的那块屏」。若用户把岛挪到外接屏（`preferred_screen_name`）且没开新开关，通知浮层仍出现在
   主屏——这是本次要求本身（「主屏默认显示」），但要抬头知道这个组合。
2. **外接屏旧窗口的回收时机**：把开关从「开」改回「关」后，外接屏上**当前正在显示**的那一条浮层
   不会立刻消失（没有「改设置即重排窗口」的观察链），而是**下一条通知**到来时被 `discardSlots`
   收掉。要立刻收，展开一次面板或等它 ttl 到点即可。
3. **`NSScreen.main` 仍在兜底链里**：主屏名万一取不到（屏刚断开的那一瞬）会退到它——那一档可能
   跟着焦点屏跑，但只在「主屏都认不出来」时生效（旧口径也有同样的兜底）。
4. **设置页那一节的界面语言**：本批顺手把「通知浮层」一节的 6 条文案 + 段脚注从**英文直显**补成
   中英双语（它们此前根本没进 `Localizable.xcstrings`），并因新口径改写了段脚注里
   「appears on every display at once」那句旧描述；其余未翻译的上游段落照旧。

## 实际交付

| 文件 | 改动 |
|---|---|
| `DynamicIsland/models/Constants.swift` | 新键 `notificationHUDOnExternalDisplays`（默认 false，含出处与「与 `showOnAllDisplays` 的区别」） |
| `DynamicIsland/Kernel/ModuleRegistry.swift` | `HUDScreenScope` 枚举、`ModuleHUD.screenScope`、`presentHUD(…:screenScope:)`（缺省 `.followsIsland`），并在 presentHUD 日志里带上屏口径 |
| `DynamicIsland/Kernel/ModuleContext.swift` | 协议要求换成带 `screenScope` 的 `presentTransient`；**协议扩展**保留旧签名 = `.followsIsland` |
| `DynamicIsland/Kernel/ModuleContextFactory.swift` | 转发时带上 `screenScope` |
| `DynamicIsland/Kernel/ModuleHUDWindow.swift` | `targetScreenNames(scope:…)` 分发；新增 `mainDisplayTargetScreenNames(...)` 与 `primaryScreenName(for:)`；`present` / `isTargetScreen` 改按**这一条浮层**的口径解析；文件头多屏段补一张口径表 |
| `DynamicIsland/Modules/NotificationsModule.swift` | `NotificationHUDPolicy.screenScope(onExternalDisplays:)` / `screenScopeFromDefaults()`；两处 `presentTransient` 带上屏口径 |
| `DynamicIsland/components/Settings/SettingsView.swift` | 通知浮层一节新增开关（总开关之下）+ 段脚注改写 |
| `DynamicIsland/Localizable.xcstrings` | 该节 6 条文案 + 新开关 + 段脚注的中英双语（新增 7 条、其余 5 条此前缺失） |
| `DynamicIslandTests/ModuleKernelTests.swift` | 新增 7 条：屏口径默认档 / 显式口径存档 / 主屏档（默认与开）/ 兜底链 / 分发点零回归 / 键默认值 / 模块映射 |
| `DynamicIslandTests/ShortcutsFrontAppTests.swift` | `SilentUIHandle` 跟新签名 |
| `tests/test_general_ai_configuration.py` | 两条既有守卫的**规程更新**：① 新键登记进 `LOCALE_KEYS`（那份守卫要求「catalog 的每一处改动都登记 + 双语 + 有消费者」）；② `Constants.swift` 的基线指纹重算（新增一个 Defaults 键，逐字核过只有那一处新增） |
| `docs/guide/settings.md`、`docs/guide/faq.md` | 该节现在有中文：表格改中文并加上新开关；FAQ 里「这一节是英文」的例子相应更正 |

**上屏取证**（2026-10-16，本机两块屏：内建视网膜显示器 + VA2478-H-2）：

| 档 | 内建屏 | 外接屏 | 内核日志 |
|---|---|---|---|
| **关（默认）** | 有浮层 | **无浮层** | `屏口径 mainDisplay(allowsExternalDisplays: false)` + 一行 `浮层窗口显示：… 屏 内建视网膜显示器` |
| **开** | 有浮层 | 有浮层 | `屏口径 mainDisplay(allowsExternalDisplays: true)` + 两行（VA2478-H-2 与内建屏各一行） |

现场造法：`osascript -e 'display notification …'`（AX 通道实时路径）→ 1.6s 后 `screencapture -D 1/-D 2`
（显示时长 5s，晚了抓不到）。截图与日志见 `~/workspace/temp/20261016/gourd-notification-hud-screen/`。

## 决策摘要

| 编号 | 决策 | 依据 |
|---|---|---|
| D-01 | 屏口径做成**每条浮层自带的属性**（`ModuleHUD.screenScope`），新增 `.mainDisplay(allowsExternalDisplays:)`，旧默认 `.followsIsland` | 「通知只上主屏」是通知的选择，不该变成所有浮层的规则；随条目走也避免覆盖语义下口径串台 |
| D-02 | 「主屏」= **`CGMainDisplayID()` 那块**（系统主显示器），退化链 = `NSScreen.main` → 第一块 | `NSScreen.main` 是「当前键窗所在的屏」，会跟着焦点跑（本机实测来回跳）；用户要的是固定那块 |
| D-03 | 与 `showOnAllDisplays` **解耦**：通知的口径只看新开关 | 那是「岛画在哪几块屏」；耦合会让「岛放副屏」被迫连通知一起搬 |
| D-04 | 旧签名 `presentTransient(view:ttl:)` 用**协议扩展**保留 = `.followsIsland` | 加参数不该逼所有调用方改动；「别的模块零回归」有专门用例钉住 |
| D-05 | 设置**不缓存**，弹浮层那一刻读（无观察链） | 与 ttl 同一形状；改设置下一条通知即生效，不需要重启 |
| D-06 | 顺带把设置页「通知浮层」一节补成中英双语，并改掉段脚注里过时的「每块屏都显示」 | 这 6 条文案此前根本没进 catalog（整节英文直显）；段脚注与新口径冲突，留下来就是错的用户可见事实 |
| D-07 | 注册新键进 `LOCALE_KEYS` 并重算 `Constants.swift` 的基线指纹 | 那两条 python 守卫是「catalog 改动必须登记 + 双语 + 有消费者」与「历史文件冻结」的执行者，本批按规程更新（不是绕过） |
| D-08 | 首页通知块表头加**快捷开关**（2026-10-27 用户要求「在通知这个位置加个按钮控制」）：翻转设置页同一个键 `notificationHUDOnExternalDisplays`，一处存储、两处入口；图标两态（开 = 实心 `rectangle.on.rectangle.fill`、关 = 空心），悬停两态各一句「现在怎样 + 点了会怎样」 | 用户圈的就是首页通知块表头「清除」左边那块空白；不嵌设置页那颗 macOS Toggle 是因为 16pt 紧档表头装不下开关控件（D-02 同批的 capsule 溢出教训），改成一颗图标按钮；总开关关掉时**不画**（设置页同判据是 `.disabled`，表头里一颗永远灰的图标更吵）；快捷开关的闸门 / 两态图标 / 说明键收在 `NotificationsHomeBlockLayout` 纯函数并有专门用例 |
