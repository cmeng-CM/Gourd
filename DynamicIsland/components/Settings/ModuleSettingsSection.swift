// Modified for Gourd (2026-09-30)
// Copyright (C) 2026 Gourd Contributors
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
//

//
//  ModuleSettingsSection.swift
//  Gourd 设置页 · 「组件」卡片页（P2 批次 / T5）
//
//  组件（模块）的运行期开关页：**一张卡 = 一个已注册模块（含未启用）**——数据源是注册表的
//  全量 manifest，不是 `tabEntries`（那份只有已激活的；用它会让「关掉的组件从列表里消失」，
//  用户就再也开不回来）。
//
//  **写路径的顺序是定死的**（docs/17 §处理链路）：先把用户选择落到它该落的那一份偏好
//  （`ModuleEnablementWrite`——接管模块写上游键，其余写 `Defaults[.moduleEnableOverrides]`），
//  再 `await ModuleRegistry.setEnabled(_:for:)` 改内存状态。
//  activate 失败时状态是终态 `failed`、开关回弹——回弹**只把偏好写回**（接管模块连偏好都不写，
//  见 D-13），绝不再调 `setEnabled(false)`：那会把 `failed` 降级成 `.disabled`，等于给 failed
//  开出一条隐藏的「关一下再打开」重试通道，与 D-13（failed 不可逃逸）矛盾。
//
//  规格：docs/17-nookx-adoption.md §改动点设计 5（卡片页）、§接口与数据形状 3/4（`setEnabled`
//  语义与偏好键语义）、§已知限制 5（内置块不在此页——页面顶部那行说明是它的缓解措施）。
//
//  P2 批次 / T2 增量：卡片在 surfaces 徽标下方多两行说明——「效果 / 出现位置」
//  （`settings.modules.effect.<shortID>`，按模块 id 映射、只覆盖内置三块）与
//  「默认关闭」（`manifest.defaultEnabled == false` 时；`progress` 的形态）。
//  这两行只加文案，不动图标 / 名称 / 摘要 / 徽标 / 开关。
//
//  P1 批次 / T3 增量：卡片下方多一节「首页块顺序」——每个**会出现在首页**的块一行（名称 + 上移 /
//  下移），写 `Defaults[.homeBlockOrder]`。名单是「内置块（按开关）+ 模块块（按 `homeEntries`）」
//  合成的一张表，排序算式与首页 strip **逐字同一条**（`HomeBlockOrdering.sorted`）——
//  这一页显示的顺序就是首页渲染的顺序，不存在第二套口径。
//
//  P2 接管批次 / T6 增量（接管卡的写路径与文案 + 功能卡段 + 顺序节收敛）：
//  - **写路径改走唯一入口**：开关落盘调 `ModuleEnablementWrite.write(_:for:takeoverKey:)`——
//    接管模块写的是**上游那个总开关**，非接管模块写 `moduleEnableOverrides`（本文件不再自己
//    读改写字典）；activate 失败的回弹值由 `ModuleEnablementRollback.preferenceToWrite(takeoverKey:)`
//    给出：返回 `nil`（接管模块）**什么都不写**——它的偏好就是上游总开关，回弹等于「因为模块
//    激活失败，把用户的功能关了」；返回 `false`（非接管）才把用户的开关拨回去（D-13）。
//  - **新增「功能」段**：**尚未模块化**的上游功能各一行（图标 + 名称 + 一行效果 + 开关），
//    开关直接读写那一个 `Defaults` 键——纯登记，不改渲染归属；详细设置仍在上游那一页，
//    卡面文案（段脚注）写明这一点（docs/20 §做法 机制三 / D-07）。
//    **T6 收尾**：原七行里的**笔记**那一张（`Enable Notes`）**摘掉**——笔记页与
//    `TabSelectionView` 的 Notes tab 分支都已摘除、键惰性，卡片留着就是「拨了没反应」的那类
//    （键名与判定见 docs/09 §5.9 的判定表）；段内今天是**六行**，键与文案（名称 / 效果行）
//    都保留未删，恢复笔记入口时把那一行加回本表即复活。
//  - **顺序节收敛**：接管后首页块只认模块 id，内置块里只剩首页日历行且它**不在 strip 里**
//    （全宽日历行，不进顺序表），因此不再生成 `builtin.music` / `builtin.mirror` 两行。
//
//  P2 接管批次 / T6 **修复**：「效果 / 出现位置」的映射（原先是 `ModuleSettingsCard` 私有的
//  `effectKey(for:)` switch）提成 `ModuleSettingsSection.effectKeysByModuleID` 这张 **internal
//  静态表**，`effectKey(for:)` 只做一次查表——理由与 `featureCards` 逐字相同：映射表自己写错一个字
//  必须能被用例抓到（上一轮「把 `settings.modules.effect.music` 改成错字」是全绿的，
//  见 T6 报告 §3 变异 ②b）。
//
//  P2 首页修正批次 / T5 **修复轮**（本文件本轮的增量，范围评审的 Important）：
//  **音乐卡多一行「显示封面」**（`ModuleSettingsSection.configControls` + `ModuleConfigControlRow`）
//  ——T5 加的 `showAlbumArt` 原先只有 config、界面上没有入口（用户今天只能 `defaults write` + 重启），
//  而用户原话是「音乐播放区域这个封面应该是可以配置是否显示」，因此必须给这一个键开一个口子：
//  - 登记表**逐字段写死**（模块 id / config 键 / 文案 key / 回落值），**不做**按 manifest schema
//    自动生成控件的通用渲染器（那是另一个批次的活，本轮只开这一个键）；
//  - 读写走 `ModuleContextFactory.configHandle(for:)`（与模块侧同一个句柄实现）→ suite 名与
//    存储编码只有一处；**先落盘、再叫醒首页 strip**（注册表的 `objectWillChange`），
//    模块下一次 `content(for: .home)` 现读 config 即生效——**不需要重启**；
//  - 本文件同时补一句口径：卡片主开关仍然是「模块开不开」，这一行是**卡片内部的子设置**，
//    两者不共用一个开关（关掉封面 ≠ 关掉音乐块）。
//
//  P3 冻结批次 / T7 增量（模块配置编辑口：**允许清单**，docs/24-release-freeze.md §做法 机制四 / D-06）：
//  把那一个口子扩成一条**逐键声明的允许清单**（`ModuleSettingsSection.configControls` 七条起步：
//  music 一条、launcher 三条、shortcuts 两条、frontapp 一条），并支持四种控件类型
//  （`ModuleConfigControl.Kind` = boolean / integer / number / string）——`enum` 仍不渲染
//  （§明确不做）：
//  - **区间取模块侧既有常量**（`LauncherGridMetrics.iconSizeRange` / `.densityRange`、
//    `FrontAppHistory.limitRange`）：读写两侧各夹一次——UI 拨不出去范围外的值，
//    手改配置文件写进去的越界值也会被读侧夹回来（`shortcuts.timeoutSeconds` 没有既有区间 → 不夹）；
//  - **接管模块登记的上游键不进清单**（`enableTimerFeature` / `showMirror` / `playerColorTinting`
//    一类：`ConfigHandle` 对它们不生效、拨了没人读），改由卡片上一行灰字
//    （`settings.modules.upstreamManaged`）说清；
//  - **不自己带默认值**：缺键回落交给 `ManifestConfigHandle.get`（= manifest config 的 `default`），
//    卡上显示什么与模块读到什么因此是同一个判定，不存在第二个默认档。
//
//  p5 批次 / T2 增量（docs/29-home-blocks-and-panel.md §做法 机制二 / D-05）：
//  **多选是允许清单的第五种控件类型**（`ModuleConfigControl.Kind.multiSelect(options:titleKeys:)`），
//  第一条登记项是进度卡的「显示的尺度」（模块 id + 键名 `visibleScopes`，选项与文案都取自
//  `ProgressCalculator.Scope.allCases`）。三处口径与既有四条**逐字相同**（只收模块真读的键、
//  区间/取值取模块侧常量、不自己带默认值），另有两条是多选独有的：
//  - **写盘顺序恒 = 选项的声明顺序**（勾选先后不参与）——模块侧 `resolveScopes` 是「顺序按输入」，
//    而用户眼里的顺序就是在卡上看到的那一排，写盘顺序跟着它才对得上（「画前三个」这条口径也因此确定）；
//  - **读出来的值也按声明顺序收敛**（野值不落进 UI：与数值型的「读侧再夹一次」同一条理由）。
//  `list` 型仍**只有多选这一个渲染形态**（键必须逐条登记，不按 manifest schema 自动生成控件）。
//
//  P3 组件批次 / T3 增量（**两节 + 两套排序**，docs/26-home-widgets-and-settings.md §做法 机制三 / D-03）：
//  - 页面从「一张卡 = 一个模块」的平铺改成两节：**首页组件**（声明 `home` 的模块，doc 里也叫
//    「内置块 + 声明 home 的模块」——内置块今天为空，见 `homeRows`）与**面板组件**（声明 `expanded`
//    的模块）。名单来源仍是**全量 manifest**（含未启用）——关掉的组件必须还在这份名单里，
//    否则用户再也开不回来（`progress` / `stats` 默认关，这条是它们的唯一入口）。
//  - **两节的顺序写两个键**：首页写 `homeBlockOrder`（沿用）、面板写**新键** `panelOrder`
//    （D-03：两组顺序是两件事，共用一个键会让它们互相踩）。面板那一节的比较器与
//    `ModuleRegistry.tabEntries` **同一算式**（`ModuleRegistry.panelRank`），不存在第二套口径。
//  - **两节的开关只管各自的 surface**（节头写明的口径）：模块同时有 home 与 panel 两面时
//    （待办 / 通知），在一个面上关掉只写 `hiddenHomeModules` / `hiddenPanelModules`，
//    模块本身继续开着（另一个面照旧）；只有一个面的模块写的是**既有启用真源**
//    （`ModuleEnablementWrite`——进度 / 统计的开关口径：不新增第二份状态）。
//    这一步的语义与写路径收在 `ModuleSurfaceSwitch` + `ModuleSurfaceToggleWriter`（纯函数 +
//    唯一写入口），视图只负责把 UI 事件转成一次调用，用例直接钉这两处。
//  - 卡片的**其余内容一个字没动**（图标 / 名称 / surfaces 徽标 / 效果行 / 默认关闭 / 摘要 /
//    config 控件 / 上游管理 / 失败态）——只是每张卡多了「上移 / 下移」两个按钮（沿用既有
//    `Move Up` / `Move Down` 文案），并知道自己属于哪一节。
//

import Defaults
import SwiftUI

/// 设置页「组件」卡片页（`SettingsTab.modules` 的 detail）。
struct ModuleSettingsSection: View {
    /// **必须自己观察注册表**：`states` 是 `@Published`，卡片的重绘由它驱动。不观察的话
    /// 开关点完不重绘（`SettingsView` 自己并不观察注册表，它只换 detail 视图）。
    @ObservedObject private var registry = ModuleRegistry.shared

    /// 首页块的用户排序覆盖（P1 / T3）。**用 `@Default` 而不是本地 `@State`**：它是
    /// `DynamicProperty`，写盘即重绘本页（本地状态那一路），首页 strip 读同一个键、同一步重排——
    /// 「先落盘再刷新」因此是**一次写操作**，不存在两份状态对不上的窗口。
    @Default(.homeBlockOrder) private var homeBlockOrder

    /// 面板块的用户排序覆盖（P3 / T3，**新键**）：与 `homeBlockOrder` 各自独立（D-03）。
    @Default(.panelOrder) private var panelOrder

    // 内置块的开关级门控（`showStandardMediaControls` / `showMirror`）在 T6 收敛后**不再需要**：
    // 音乐与镜子已是模块块，两节的名单里只有模块（详见 `homeRows`）。

    /// 数据源 = 注册表**全量** manifest（含未启用），按 `id` 升序（docs/17 §改动点设计 5）。
    private var manifests: [ModuleManifest] {
        registry.manifests.values.sorted { $0.id < $1.id }
    }

    var body: some View {
        Form {
            // 内置块里只剩首页日历行不在两节的名单里（音乐 / 镜子已是模块）——docs/17
            // §已知限制 5 的缓解措施：日历行由上游 `Defaults` 键门控，开关在下方「功能」段。
            Section {
                Text(LocalizedStringKey("settings.modules.builtinHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 两节：首页组件（控制「在不在首页」）在前，面板组件（控制「单不单独出面板/tab」）在后
            // ——首页是用户最常看的那一面（机制三）。
            surfaceSection(.home)

            surfaceSection(.panel)

            // 「功能」段**跟在两节之后**（D-07：先看得见模块、再看得见还没模块化的上游功能）。
            // 顺序节已被两节吸收（每行自己的上移 / 下移），不再单列一节。
            featuresSection
        }
        .navigationTitle(Text(LocalizedStringKey("settings.modules.title")))
    }

    // MARK: 功能（上游总开关的登记表）

    /// **五张**功能卡：一行一个**尚未模块化**的上游功能，开关直接读写那一个 `Defaults` 键。
    /// （T6 收尾摘掉了**笔记**那一张（`Enable Notes`）——它是原七行里唯一「拨了看不到任何变化」
    /// 的一行，判据见 docs/09 §5.9 的判定表与 docs/26 §已知限制 5；键与文案保留未删。
    /// **2026-09-30 又摘掉 `showCalendar` 一张**：它是首页上的一个块（全宽日历行），用户要求
    /// 「日历也要在首页组件里开关」，于是搬进「首页组件」节成为 `HomeCalendarSettingsRow`——同一个键，
    /// 换了位置，见 docs/28 §5。）
    ///
    /// `nameKey` **逐字沿用上游设置页那一项的名称字面量**（在 `SettingsView.swift` 里那一项
    /// 旁边取证）——用户在别处认识的词与这里看到的必须是同一个 key，不另起说法
    /// （docs/20 §接口与数据形状 7）。
    ///
    /// **不是 `private`**（文档 §7 写的是 `private struct FeatureCard`）：解析用例直接读这张表
    /// （`TakeoverEnablementTests.testFeatureCardKeysResolve`），表侧把键写错才会红——测试另抄
    /// 一份键表的话，「表写错、文案对」这条谁都发现不了。
    static let featureCards: [FeatureCard] = [
        FeatureCard(
            id: "enableClipboardManager",
            nameKey: "Enable Clipboard Manager",
            symbolName: "clipboard",
            key: .enableClipboardManager,
            effectKey: "settings.features.effect.enableClipboardManager"
        ),
        FeatureCard(
            id: "enableLockScreenWeatherWidget",
            nameKey: "Show lock screen weather",
            symbolName: "cloud.sun.fill",
            key: .enableLockScreenWeatherWidget,
            effectKey: "settings.features.effect.enableLockScreenWeatherWidget"
        ),
        FeatureCard(
            id: "enableStatsFeature",
            nameKey: "Enable system stats monitoring",
            symbolName: "chart.xyaxis.line",
            key: .enableStatsFeature,
            effectKey: "settings.features.effect.enableStatsFeature"
        ),
        FeatureCard(
            id: "dynamicShelf",
            nameKey: "Enable shelf",
            symbolName: "tray.and.arrow.down",
            key: .dynamicShelf,
            effectKey: "settings.features.effect.dynamicShelf"
        ),
        FeatureCard(
            id: "enableTerminalFeature",
            nameKey: "Enable terminal",
            symbolName: "apple.terminal",
            key: .enableTerminalFeature,
            effectKey: "settings.features.effect.enableTerminalFeature"
        ),
    ]

    // MARK: 模块卡「效果 / 出现位置」一行

    /// 组件卡那行「效果 / 出现位置」的本地化 key：**模块 id → 效果行 key**（唯一的取值处）。
    ///
    /// 覆盖**六个**已注册模块——这六行写的是**本项目里这些组件实际的渲染点**（以 manifest 的
    /// `surfaces` 与实际视图为准），不是从 manifest 推导出来的通用句子：
    /// - `todos`：`[.expanded, .compact, .home]` → 折叠态中央槽位 + 首页块 + 展开面板待办页；
    /// - `notifications`：`[.expanded, .compact, .home]` → 折叠态铃铛 + 首页通知块 + 展开面板通知列表
    ///   （另有 HUD：新通知在刘海上短暂浮现，`presentHUD` 那条链，受浮层总开关控制）；
    /// - `progress`：`[.compact, .expanded]`（**无 `home`**）→ 折叠态中央槽位 + 展开面板进度页。
    ///
    /// 接管三块（P2 / T6）：它们的渲染点由模块拥有，且都带自己的运行期门控，因此这一行要写清
    /// 「什么时候看得到」：
    /// - `timer` → 展开面板的计时器 tab（**仅当**「显示方式 = 标签页」，`isTabVisible()` 的口径）；
    /// - `mirror` / `music` → 首页块（镜子要摄像头可用；音乐要有播放会话，除非关掉了无会话即隐藏）。
    ///
    /// **表不是 `private`**（T6 修复）：解析用例直接迭代这张表
    /// （`TakeoverEnablementTests.testModuleEffectKeysMatchTableAndCatalog`），表侧把任何一个值
    /// 写成错字才会红——上一轮这段映射是宿于 `private struct ModuleSettingsCard` 的
    /// `private static func effectKey(for:)` 里的 switch，用例够不到，于是「把
    /// `settings.modules.effect.music` 改成错字」全绿（T6 报告 §3 变异 ②b），与本文件
    /// `featureCards` 同一条口径（表侧写错必须能被用例抓到）。
    ///
    /// 未命中（将来注册的第三方模块）返回 nil，**整行不显示**——不猜它出现在哪。
    static let effectKeysByModuleID: [String: String] = [
        "com.cmeng.gourd.todos": "settings.modules.effect.todos",
        "com.cmeng.gourd.notifications": "settings.modules.effect.notifications",
        "com.cmeng.gourd.progress": "settings.modules.effect.progress",
        "com.cmeng.gourd.timer": "settings.modules.effect.timer",
        "com.cmeng.gourd.mirror": "settings.modules.effect.mirror",
        "com.cmeng.gourd.music": "settings.modules.effect.music",
    ]

    // MARK: 模块 config 控件（允许清单，逐键声明）

    /// 组件卡上的**模块 config 控件**登记表（docs/24-release-freeze.md §做法 机制四 / D-06）。
    ///
    /// **不是通用 config 渲染器**（按 manifest schema 自动生成控件）——那是另一个批次的活
    /// （docs/24 §明确不做：`list` / `enum` / `appPicker` 的「哪些键是真源」未定）。
    /// 这里是**允许清单**：一张**逐字段写死**的表（模块 id / config 键 / 类型与区间 / 文案 key），
    /// 卡片按 `moduleID` 命中后渲染对应控件。判据与 `effectKeysByModuleID` / `featureCards` 逐字同款：
    /// **表不是 `private`**，解析用例直接读这一份生产表——把模块 id 或键名写错一个字、
    /// 类型与 manifest 声明不符、或文案没进 catalog，必须有用例红（表侧写错必须能被用例抓到）。
    ///
    /// 三条口径（改动前先读）：
    ///
    /// 1. **只收「模块自己真的读」的键**——八条都是模块侧现读现用的：
    ///    `music.showAlbumArt`（块内画不画封面）、`launcher.iconSize` / `.density` / `.showRecents`、
    ///    `shortcuts.showOutput` / `.timeoutSeconds`、`frontapp.maxRecentApps`、
    ///    `progress.visibleScopes`（首页块画哪几行尺度）。
    ///    **生效时机分两档**（别混为一谈）：`iconSize` / `density` / `showAlbumArt` /
    ///    `maxRecentApps`（下一次读）、`visibleScopes`（下一次 `content(for:)`，即宿主重取内容的那一帧）、
    ///    `timeoutSeconds` / `showOutput`（下一次运行）是「下一次取用时就生效」；`launcher.showRecents`
    ///    慢一档——一次激活只查一次 Spotlight，关掉再开模块（或重启）才换档（见 `LauncherSettings`
    ///    的注释）。
    /// 2. **接管模块登记的上游键不进清单**（`enableTimerFeature` / `showMirror` /
    ///    `playerColorTinting` 一类）：它们的真源在上游 `Defaults`，`ConfigHandle` 对它们不生效
    ///    （`get` 拿不到覆盖值、`set` 写进去也没人读），拨了不会有反应——卡片上改由
    ///    `settings.modules.upstreamManaged` 那行灰字说清（判据 = `upstreamManagedKeys(for:takeoverKeyName:)`）。
    /// 3. **取值一律取模块侧既有常量**（`LauncherGridMetrics.iconSizeRange` / `.densityRange`、
    ///    `FrontAppHistory.limitRange`、`ProgressCalculator.Scope.allCases`）：UI 拨不出范围外的值，
    ///    手改配置文件写进去的越界值也会被读侧夹回来——两处各写一个区间就会漂，故这里**一个字面量
    ///    都不写**。`shortcuts.timeoutSeconds` **没有**既有区间常量 → `range: nil`（不夹取、输入框形态）：
    ///    发明一个区间等于替模块做它没做过的裁决（§候选决策）。
    ///
    /// **`enum` 不渲染**（§明确不做）：shortcuts 的 `pinnedShortcuts` / `cachedShortcuts`、
    /// timer 的 `timerPresets`、mirror 的 `mirrorShape` 仍只能改配置文件（§已知限制 2）；
    /// `list` 型今天**只有多选**这一个形态（`.multiSelect`），没有「自由输入一串值」的入口。
    static let configControls: [ModuleConfigControl] = [
        ModuleConfigControl(
            moduleID: MusicModule.moduleID,
            key: "showAlbumArt",
            kind: .boolean,
            titleKey: "settings.modules.music.showAlbumArt"
        ),
        // 启动台三键。**模块 id 是字面量**：`LauncherModule` 没有 `moduleID` 常量（它的 manifest
        // 里直接写的字面量），此处逐字对齐——解析用例把它对回注册表，写错即红。
        ModuleConfigControl(
            moduleID: "com.cmeng.gourd.launcher",
            key: "iconSize",
            kind: .number(range: LauncherGridMetrics.iconSizeRange),
            titleKey: "settings.modules.launcher.iconSize"
        ),
        ModuleConfigControl(
            moduleID: "com.cmeng.gourd.launcher",
            key: "density",
            kind: .number(range: LauncherGridMetrics.densityRange),
            titleKey: "settings.modules.launcher.density"
        ),
        ModuleConfigControl(
            moduleID: "com.cmeng.gourd.launcher",
            key: "showRecents",
            kind: .boolean,
            titleKey: "settings.modules.launcher.showRecents"
        ),
        ModuleConfigControl(
            moduleID: ShortcutsModule.moduleID,
            key: "showOutput",
            kind: .boolean,
            titleKey: "settings.modules.shortcuts.showOutput"
        ),
        // 秒数：**没有夹取区间**（模块侧本来就没夹，见口径 3），整数输入框
        ModuleConfigControl(
            moduleID: ShortcutsModule.moduleID,
            key: "timeoutSeconds",
            kind: .integer(range: nil),
            titleKey: "settings.modules.shortcuts.timeoutSeconds"
        ),
        ModuleConfigControl(
            moduleID: FrontAppModule.moduleID,
            key: "maxRecentApps",
            kind: .integer(range: FrontAppHistory.limitRange),
            titleKey: "settings.modules.frontapp.maxRecentApps"
        ),
        // 进度卡：**尺度多选**（p5-home-blocks / T2，docs/29 §做法 机制二 / D-05）。
        // 选项与文案 key 都取自 `ProgressCalculator.Scope.allCases`（模块侧的**声明顺序**）——
        // 卡上从左到右那一排就是块里从上到下那几行，勾满而块放不下时「画前三个」的顺序因此确定。
        // 模块 id 写**字面量**（与启动台三行同口径）：`ProgressModule` 没有 `moduleID` 常量，
        // 解析用例把它对回注册表，写错即红。
        ModuleConfigControl(
            moduleID: "com.cmeng.gourd.progress",
            key: "visibleScopes",
            kind: .multiSelect(
                options: ProgressCalculator.Scope.allCases.map(\.rawValue),
                titleKeys: ProgressCalculator.Scope.allCases.map(\.labelKey)
            ),
            titleKey: "settings.modules.progress.visibleScopes"
        ),
    ]

    /// 命中本卡片的 config 控件（**可能多行**：启动台卡三行、快捷指令卡两行）。
    /// 数据源仍是上面那张唯一的生产表，本函数只做一次筛选。
    static func configControls(forModuleID id: String) -> [ModuleConfigControl] {
        configControls.filter { $0.moduleID == id }
    }

    /// 本卡片上**登记了但这里不可编辑**的上游键——`settings.modules.upstreamManaged`
    /// 那行灰字的判据（docs/24 §做法 机制四：**把话说清楚**，而不是让用户拨一个不生效的开关）。
    ///
    /// 判据两段，缺一不可：
    /// - **非接管模块一律空表**：它们那些没进清单的键（`list` / `enum` 型，如 shortcuts 的两个
    ///   清单键、timer 的 `timerPresets`）是「只能改配置文件」那一档（§已知限制 1/2），
    ///   **不是**「由上游设置管理」——那句话只在真源确实落在上游 `Defaults` 时才成立；
    /// - **接管模块**（`takeoverKeyName != nil`）= manifest 里登记的键**减去**允许清单里已开的键。
    ///   例如音乐卡：`playerColorTinting` / `useMusicVisualizer` 留下（→ 标注一行），
    ///   `showAlbumArt` 被减掉（→ 它是一个真的有控件的键）。日历卡没有 `config` → 空表
    ///   （没有登记过任何不可编辑的键，就没有什么要标注的）。
    ///
    /// **取键名（`String?`）而不是 `Defaults.Key<Bool>`**：本函数是纯函数——用例拿几个字符串
    /// 就能把三段判据各钉一条，不必造注册表、不读偏好。
    static func upstreamManagedKeys(for manifest: ModuleManifest, takeoverKeyName: String?) -> [String] {
        guard takeoverKeyName != nil else { return [] }
        let editable = Set(configControls(forModuleID: manifest.id).map(\.key))
        let registered = (manifest.config?.properties.keys).map { Array($0) } ?? []
        return registered.filter { !editable.contains($0) }.sorted()
    }

    private var featuresSection: some View {
        Section {
            ForEach(Self.featureCards) { card in
                FeatureCardRow(card: card)
            }
        } header: {
            Text(LocalizedStringKey("settings.features.title"))
        } footer: {
            Text(LocalizedStringKey("settings.features.footer"))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 两节的行（首页组件 / 面板组件）

    /// 两节里的一行：一个**声明了本节 surface** 的模块（P3 / T3）。
    ///
    /// 名单来源是**全量 manifest**（`manifests`，含未启用）而不是 `homeEntries` / `tabEntries`
    /// 那两条投影——理由与卡片页逐字相同：投影只含已激活的，用它会让关掉的组件从名单里消失
    /// （`progress` / `stats` 默认关，这里的行就是它们唯一的入口）。
    ///
    /// **判据比首页少一档、是刻意的**：首页还叠加运行期条件（音乐要有会话、镜子要摄像头可用、
    /// 模块块要 `content(for: .home)` 不答 `.none`）。这一页只用**配置级判据**，否则列表会随
    /// 「有没有在放歌」「摄像头在不在」抖动，用户刚点的行会跳走。代价：名单里可能出现此刻首页
    /// 看不到的块（音乐没会话时），反之首页也可能画出这里没列的块（模块答 `.none` 的那个不在此列）。
    private struct SurfaceRow: Identifiable {
        let manifest: ModuleManifest
        /// 该模块的默认序号（`defaultPlacement?.order ?? Int.max`）——两节的排序键都用它兜底。
        let defaultOrder: Int

        var id: String { manifest.id }
    }

    private func surfaceRow(_ manifest: ModuleManifest) -> SurfaceRow {
        SurfaceRow(manifest: manifest, defaultOrder: manifest.defaultPlacement?.order ?? Int.max)
    }

    /// **首页组件**那节的名单：全量 manifest 里声明 `.home` 的，按**首页那条唯一算式**排序
    /// （`HomeBlockOrdering.sorted` + `homeBlockOrder` 覆盖）——这一页显示的顺序就是首页渲染的顺序，
    /// 不存在第二套口径。
    ///
    /// **内置块今天为空**（「内置块 + 声明 `home` 的模块」这句话在今天的产品里只剩后半句）：
    /// strip 上的音乐 / 镜子已是模块块，唯一的内置块是**首页日历行**——它是 strip 之外的全宽行
    /// （`HomeCalendarSettingsRow`），顺序固定在最下、不在 `homeBlockOrder` 的语义里（给它两个点不动的
    /// 上移 / 下移比不列它更坏），它的开关仍在下面「功能」段（`showCalendar` 那张卡）。
    /// 将来若有内置块真的进 strip，在 `homeRows` 里补一行、并让 `HomeBlockOrdering` 认它即可。
    private var homeRows: [SurfaceRow] {
        HomeBlockOrdering.sorted(
            manifests.filter { $0.surfaces.contains(.home) }.map(surfaceRow),
            defaultOrder: { $0.defaultOrder },
            id: { $0.id },
            overrides: homeBlockOrder
        )
    }

    /// **面板组件**那节的名单：全量 manifest 里声明 `.expanded` 的，按 `ModuleRegistry.panelRank`
    /// 与 id 字典序排——与 `ModuleRegistry.tabEntries` **同一算式**（那个投影还多一条
    /// `isTabVisible()` 与启用过滤，见 `SurfaceRow` 的注释）。
    private var panelRows: [SurfaceRow] {
        manifests
            .filter { $0.surfaces.contains(.expanded) }
            .map(surfaceRow)
            .sorted {
                let lhs = ModuleRegistry.panelRank($0.id, defaultOrder: $0.defaultOrder, panelOrder: panelOrder)
                let rhs = ModuleRegistry.panelRank($1.id, defaultOrder: $1.defaultOrder, panelOrder: panelOrder)
                return (lhs, $0.id) < (rhs, $1.id)
            }
    }

    /// 一节的全部内容：卡（图标 + 名称 + 开关 + 上移 / 下移 + 卡片原有的每一行）+ 节头 / 节脚注。
    private func surfaceSection(_ group: ModuleSurfaceGroup) -> some View {
        let rows = group == .home ? homeRows : panelRows
        return Section {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                ModuleSettingsCard(
                    registry: registry,
                    manifest: row.manifest,
                    group: group,
                    isFirst: index == 0,
                    isLast: index == rows.count - 1,
                    moveUp: { move(row, in: group, direction: .up) },
                    moveDown: { move(row, in: group, direction: .down) }
                )
            }
            // 首页的**内置块**（不是模块）：全宽日历行。列在本节末尾——它是流下方那一条全宽行，
            // 与"块与块之间"的顺序表（`homeBlockOrder`）不是一回事，因此**只有开关、没有 ↑↓**
            // （docs/28 §5；用户 2026-09-30：「首页的日历组件也要在首页组件控制区域进行开关控制」）。
            if group == .home {
                HomeCalendarSettingsRow()
            }
        } header: {
            Text(LocalizedStringKey(group.titleKey))
        } footer: {
            Text(LocalizedStringKey(group.footerKey))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 上移 / 下移一行：**先落盘、再刷新**（docs/18 §处理链路）。
    ///
    /// 写的是本节的**整表序号**（口径与理由见 `HomeBlockOrdering.table(for:)`，两节共用
    /// `ModuleSurfaceGroup.orderTable`）；名单在点击这一刻现取（而不是捕获渲染时的那一份），
    /// 因此「点之前名单刚好变了」（模块被开关 / 被摘掉）也按最新名单算。
    private func move(_ row: SurfaceRow, in group: ModuleSurfaceGroup, direction: HomeBlockOrdering.MoveDirection) {
        let ids = (group == .home ? homeRows : panelRows).map(\.id)
        guard let table = ModuleSurfaceGroup.orderTable(ids: ids, moving: row.id, direction: direction) else {
            // 名单没变（已在顶 / 底，或该行已不在名单里）**不写盘**——用户没表达就不留痕迹。
            return
        }
        group.writeOrderTable(table)
    }
}

// MARK: - 两节（首页组件 / 面板组件）

/// 组件页的两节（P3 批次 / T3，docs/26-home-widgets-and-settings.md §做法 机制三 / D-03）。
///
/// **本枚举是两节的唯一身份**：节头 / 节脚注的文案 key、进哪一节的判据（`surface`）、
/// 「另一个面」的判据（`hasOtherSurface`）、两个偏好键的落点（`writeOrderTable` / `setHidden`）
/// 都从它取——视图与用例共用，两处各写一份就会漂。
///
/// **两节不是互斥的**（节头文案写明的口径）：日历 / 待办 / 通知这类模块同时声明 `home` 与
/// `expanded`，因此两节里各有一行；两行的开关**各管各自的 surface**（见 `ModuleSurfaceSwitch`）。
enum ModuleSurfaceGroup: String, CaseIterable, Identifiable {
    /// 首页组件：控制「在不在首页」。
    case home
    /// 面板组件：控制「单不单独出面板 / tab」。
    case panel

    var id: String { rawValue }

    /// 本节的判据：manifest 的 `surfaces` 含它才进这一节。
    var surface: Surface {
        switch self {
        case .home: return .home
        case .panel: return .expanded
        }
    }

    /// 节头 / 节脚注的本地化 key（`settings.modules.group.<raw>` / `…<raw>.footer`）。
    var titleKey: String { "settings.modules.group.\(rawValue)" }
    var footerKey: String { "settings.modules.group.\(rawValue).footer" }

    /// 「另一个面」判据：关掉本节开关时，模块是否还留在别处——决定关的是**表面**还是**模块本身**。
    ///
    /// 只有 home ↔ panel 互为他面：`compact`（折叠态中央槽位）是常驻展示、没有自己的开关
    /// （06 §6.2 的三槽布局属 P2+，本批未落地），把它算成「还有别处」会让一个只声明
    /// `compact + home` 的模块两节都关不掉——那是个关不掉的开关。
    ///
    /// 纯函数（吃 `[Surface]` 不吃 manifest），用例拿几个字面量就能把两档钉住。
    static func hasOtherSurface(_ surfaces: [Surface], in group: ModuleSurfaceGroup) -> Bool {
        surfaces.contains(group == .home ? .expanded : .home)
    }

    /// 本节开关的 get 半边（纯函数）：模块**开着**且**没在本节被摘掉**。
    ///
    /// `moduleEnabled` 由调用方按注册表状态判定（`.active` / `.activating` → true，其余 false，
    /// 与卡片既有那一条逐字一致）；`isHidden` 取自本节的摘除名单。
    static func isOn(moduleEnabled: Bool, isHidden: Bool) -> Bool {
        moduleEnabled && !isHidden
    }

    /// 一组顺序的**翻盘算式**（两节共用）：返回要落盘的整表；名单没变（已在顶 / 底、id 不在名单里）
    /// 返回 `nil`——「用户没表达就不留痕迹」那一条的判据，视图据此不写盘。
    ///
    /// 整表覆盖（而不是只写被移动的那一格）的口径与理由见 `HomeBlockOrdering.table(for:)`。
    static func orderTable(
        ids: [String],
        moving id: String,
        direction: HomeBlockOrdering.MoveDirection
    ) -> [String: Int]? {
        let moved = HomeBlockOrdering.moved(ids, moving: id, direction: direction)
        guard moved != ids else { return nil }
        return HomeBlockOrdering.table(for: moved)
    }

    /// 本节的**顺序覆盖键**落盘：首页 → `homeBlockOrder`、面板 → `panelOrder`（**两个键**，D-03）。
    func writeOrderTable(_ table: [String: Int]) {
        switch self {
        case .home: Defaults[.homeBlockOrder] = table
        case .panel: Defaults[.panelOrder] = table
        }
    }

    /// 本节的**摘除名单**落盘：首页 → `hiddenHomeModules`、面板 → `hiddenPanelModules`。
    func setHidden(_ hidden: Bool, for id: String) {
        switch self {
        case .home: Defaults[.hiddenHomeModules] = Self.updated(Defaults[.hiddenHomeModules], id: id, hidden: hidden)
        case .panel: Defaults[.hiddenPanelModules] = Self.updated(Defaults[.hiddenPanelModules], id: id, hidden: hidden)
        }
    }

    /// 名单的增删（纯函数，用例直接钉）：置真 = 追加到尾部（没有重复项就不动）、置假 = 滤掉它。
    ///
    /// **不排序**：存的是集合语义（谁被摘掉了），渲染时的先后由块的顺序决定——名单里留着一个
    /// 早已不在注册表里的 id（模块被移除 / 改名）也没有接收者，与 `homeBlockOrder` 的未知 id 同口径。
    static func updated(_ ids: [String], id: String, hidden: Bool) -> [String] {
        if hidden { return ids.contains(id) ? ids : ids + [id] }
        return ids.filter { $0 != id }
    }
}

/// 一节里那一次「开关拨动」的**语义**（纯函数；写路径见 `ModuleSurfaceToggleWriter`）。
///
/// **两节各自的开关只管各自的 surface**（节头写明的口径）：模块同时有 home 与 panel 两面时，
/// 在一个面上关掉只摘掉**那个面**；只有一个面的模块没有「另一个面」可去，关掉它就是关掉模块。
enum ModuleSurfaceSwitch {
    /// 一次拨动要做的三件事之一。
    enum Effect: Equatable {
        /// 置开：确保模块启用 + 把 id 从本节摘除名单里去掉（幂等）。
        case enableAndShow
        /// 置关，且模块**还有另一个面**：只在本节摘掉它——模块继续开着，另一个面照旧。
        case hideOnSurface
        /// 置关，且本节是它**唯一的面**：关掉模块本身（写既有启用真源，不新增第二份状态）。
        case disableModule
    }

    /// 拨动的判据（纯函数，两档 `hasOtherSurface` × 两个方向 = 三种结果）。
    static func effect(turningOn: Bool, hasOtherSurface: Bool) -> Effect {
        if turningOn { return .enableAndShow }
        return hasOtherSurface ? .hideOnSurface : .disableModule
    }
}

/// 一次拨动的**唯一写路径**（视图只负责把 UI 事件转成这次调用，用例直接钉这三步）。
///
/// 三步的顺序与卡片原先那条逐字一致（**先落盘、再改内存**，docs/17 §处理链路）：
/// 1. **落盘**：按 `ModuleSurfaceSwitch.effect` 分档——`enableAndShow` 写启用真源为真并取消本节
///    摘除；`hideOnSurface` **只**写本节摘除名单（启用真源一个字节不动）；`disableModule` 写启用
///    真源为假，并把本节摘除记录一并清掉（模块关了，留着那条记录只会在下次打开时让它「莫名其妙
///    地不出现」）；
/// 2. **改内存**：`await registry.setEnabled(...)`；
/// 3. **失败回弹**沿用既有两档（D-13）：接管模块什么都不写（它的偏好就是上游总开关）、
///    非接管模块写回 `false`——绝不再调 `setEnabled(false)`（那会把 `failed` 降级成 `.disabled`）。
///
/// 收尾发一次 `objectWillChange`：摘除名单那一条改动**没有别的观察者**（首页 strip 与 tab 条
/// 观察的是注册表，不是那个偏好键），不叫醒它们的话，拨完开关首页不会重排
/// （与 `ModuleConfigControlRow.commit` 同一条理由）。
@MainActor
enum ModuleSurfaceToggleWriter {
    static func write(
        _ on: Bool,
        manifest: ModuleManifest,
        group: ModuleSurfaceGroup,
        registry: ModuleRegistry
    ) async {
        let takeoverKey = registry.takeoverEnableKey(for: manifest.id)
        let effect = ModuleSurfaceSwitch.effect(
            turningOn: on,
            hasOtherSurface: ModuleSurfaceGroup.hasOtherSurface(manifest.surfaces, in: group)
        )

        switch effect {
        case .enableAndShow:
            group.setHidden(false, for: manifest.id)
            ModuleEnablementWrite.write(true, for: manifest.id, takeoverKey: takeoverKey)
            let state = await registry.setEnabled(true, for: manifest.id)
            rollBackIfNeeded(state, manifest: manifest, takeoverKey: takeoverKey)
        case .hideOnSurface:
            group.setHidden(true, for: manifest.id)
        case .disableModule:
            group.setHidden(false, for: manifest.id)
            ModuleEnablementWrite.write(false, for: manifest.id, takeoverKey: takeoverKey)
            let state = await registry.setEnabled(false, for: manifest.id)
            rollBackIfNeeded(state, manifest: manifest, takeoverKey: takeoverKey)
        }

        registry.objectWillChange.send()
    }

    /// 启动失败 → 开关回弹：**只把偏好写回**（不碰内核状态，D-13）。写什么由策略给出：
    /// 接管模块 → `nil`（什么都不写）、非接管模块 → `false`（把用户的开关拨回去）。
    private static func rollBackIfNeeded(
        _ state: ModuleRuntimeState,
        manifest: ModuleManifest,
        takeoverKey: Defaults.Key<Bool>?
    ) {
        guard case .failed = state else { return }
        guard let rollback = ModuleEnablementRollback.preferenceToWrite(takeoverKey: takeoverKey) else { return }
        ModuleEnablementWrite.write(rollback, for: manifest.id, takeoverKey: takeoverKey)
    }
}

// MARK: - 功能卡（上游键的登记行）

/// 一段上游功能的登记行：**开关就是那个 `Defaults` 键**，没有模块、没有内核状态
/// （docs/20 §接口与数据形状 7）。
///
/// **本类型不是 `private`**（文档 §7 的片段写的是 `private struct FeatureCard`）：解析用例
/// 直接读 `ModuleSettingsSection.featureCards`（同一张表），表侧把键写错才会红——测试另抄一份
/// 键表的话，「表写错、文案对」这条谁都发现不了（见 T6 报告 §候选决策）。
struct FeatureCard: Identifiable {
    /// 上游键名，同时是效果文案 key 的后缀。
    let id: String
    /// 上游设置页里的同一个名称（`String(localized:)` 同源）；**本段不另起说法**。
    let nameKey: String
    /// SF Symbol 名（与上游那一项所在设置页的图标同一套：剪贴板 / 日历 / 天气 / 统计 / 架子 /
    /// 终端）。
    let symbolName: String
    /// 这个功能的总开关——裸 `Binding` 直读写它（动态键无法用 `@Default`，§已知限制 8）。
    let key: Defaults.Key<Bool>
    /// `settings.features.effect.<id>`。
    let effectKey: String
}

// MARK: - 模块 config 控件（允许清单）

/// 一条**模块 config 控件**的读写实现（登记在 `ModuleSettingsSection.configControls` 这张生产表里）。
///
/// 读写都经宿主给模块的**同一个 `ConfigHandle` 实现**
/// （`ModuleContextFactory.configHandle(for:)` → `ManifestConfigHandle`）：suite 名
/// （`com.cmeng.gourd.module.<shortID>`）与「值按 JSON 字节存」的口径只有一处，
/// 「设置页写了一份、模块读另一份」这类静默故障在构造上就不可能发生。
///
/// **五种类型**（docs/24 §接口与数据形状 + docs/29 §接口与数据形状）：`boolean` / `integer` /
/// `number` / `string` / `multiSelect`（多选，写盘类型是 `[String]`）。`enum` 不在此列（§明确不做）。
///
/// **值类型必须与模块读的那一种一致**（改动前先读）：`ManifestConfigHandle` 把值按 JSON 字节存，
/// 模块侧用 `config.get(key, as: T.self)` 读——`number` 键（launcher 的 `iconSize`）必须写
/// `Double`、`integer` 键（frontapp 的 `maxRecentApps` / shortcuts 的 `timeoutSeconds`）必须写 `Int`、
/// `multiSelect` 键（progress 的 `visibleScopes`）必须写 `[String]`。JSON 的 `30.0` 解不进 `Int`
/// （`DecodingError`），写错类型就是「拨得动、模块读不到」的静默故障，因此**读写两条路各自按 kind
/// 分档**，不共用一条泛型通道。
///
/// **缺键回落 manifest 默认值**：`get` 本来就先查覆盖值、再回落 `manifest.config.properties[key].default`
/// （`ManifestConfigHandle` 的既有语义），所以控件**不自己带一份默认值**——卡上显示的值与模块读到的
/// 值因此是同一个判定（表里再抄一个默认值就会漂，见 T7 报告 §候选决策）。键名漂出 schema 时
/// `get` 给 nil：控件回落 0 / false / "" / 空表，而**键名漂了要用例红**（解析用例逐条对 manifest），
/// 不是让用户看一条错误提示。
///
/// **本类型不是 `private`**：解析用例直接读这张表（与 `FeatureCard` 同一条口径）。
struct ModuleConfigControl: Identifiable {
    /// 控件支持的五种类型。区间是**模块侧的既有常量**（口径 3），`nil` = 模块侧本来就没夹取区间。
    /// `integer` / `number` 分开是因为**写盘的 JSON 类型不同**（见类型注释）；
    /// `multiSelect` 的 `options` 是**写盘的字面量清单**、`titleKeys` 是它们一一对应的文案 key
    /// （两条等长、顺序即展示顺序，见 `Option`）。
    enum Kind: Equatable {
        case boolean
        case integer(range: ClosedRange<Int>?)
        case number(range: ClosedRange<Double>?)
        case string
        case multiSelect(options: [String], titleKeys: [String])
    }

    /// 多选型的一个选项：**值**（写进 config 的字面量，也是模块侧认的那一个）+ **文案 key**。
    /// id 取值本身（同一控件内选项不重复，由解析用例钉住）。
    struct Option: Equatable, Identifiable {
        let value: String
        let titleKey: String

        var id: String { value }
    }

    /// 模块 id：卡片按它命中（启动台三行、快捷指令两行、音乐 / 前台应用 / 进度各一行）。
    let moduleID: String
    /// 该模块 manifest config 里的键名——**逐字一致**（解析用例拿 manifest 的 `properties` 对，
    /// 写错一个字就红；`ConfigHandle.set` 对 schema 之外的键也不落盘）。
    let key: String
    /// 类型与区间（区间取模块侧常量，见 `Kind`）。
    let kind: Kind
    /// 这一行文案的本地化 key。
    let titleKey: String

    var id: String { "\(moduleID).\(key)" }

    /// 多选型的选项（值 + 文案 key，一一对应）；其他类型是空表。
    /// **顺序即展示顺序**——视图照它从左到右排，写盘也照它收敛。
    var multiSelectOptions: [Option] {
        guard case .multiSelect(let options, let titleKeys) = kind else { return [] }
        return zip(options, titleKeys).map { Option(value: $0.0, titleKey: $0.1) }
    }

    // MARK: 读（缺键回落 manifest 默认；数值型夹取到区间）

    /// 卡上开关的 get：缺键回落 manifest 默认值（`ManifestConfigHandle.get` 的既有语义）。
    func boolValue(from config: ConfigHandle) -> Bool {
        config.get(key, as: Bool.self) ?? false
    }

    /// 整数的 get：先夹取到区间——用户直接改 `UserDefaults` 写了 99 也要有确定的呈现
    /// （同 `LauncherGridMetrics.metrics` / `FrontAppHistory.clampedLimit` 的口径）。
    func intValue(from config: ConfigHandle) -> Int {
        clamp(config.get(key, as: Int.self) ?? 0)
    }

    /// 小数的 get（`integer` 型也走它：滑杆要的是连续量，写回时才取整——见 `writeInt`）。
    func doubleValue(from config: ConfigHandle) -> Double {
        clamp(config.get(key, as: Double.self) ?? 0)
    }

    func stringValue(from config: ConfigHandle) -> String {
        config.get(key, as: String.self) ?? ""
    }

    /// 多选的 get：读 `[String]`（缺键回落 manifest 默认值，同上），再收敛成
    /// **「清单里声明过的取值」∩「勾中的」**并按声明顺序排——手改配置文件写进去的野值不会在卡上
    /// 变成一个点不掉的勾（与数值型的「读侧再夹一次」同一条理由）。
    func selectedOptions(from config: ConfigHandle) -> [String] {
        let chosen = Set(config.get(key, as: [String].self) ?? [])
        return multiSelectOptions.map(\.value).filter { chosen.contains($0) }
    }

    // MARK: 写（只写模块专属 suite 的覆盖值；manifest 默认值一个字不动）

    /// 返回 `false` = 这个键不在该模块 manifest 的 config schema 里（键名漂了就会这样，
    /// `ManifestConfigHandle.set` 的既有语义）——用例断掉它；卡面不做错误态：
    /// 本批的键是逐字段写死的，漂了要用例红，不是让用户看一条错误提示。
    @discardableResult
    func writeBool(_ value: Bool, config: ConfigHandle) -> Bool {
        config.set(key, to: value)
    }

    /// 整数写回：**夹取后**落盘（越界值取端点），写的是 `Int`（`integer` 型模块读的就是 `Int`）。
    @discardableResult
    func writeInt(_ value: Int, config: ConfigHandle) -> Bool {
        config.set(key, to: clamp(value))
    }

    /// 小数写回：夹取后落盘，写的是 `Double`（`number` 型模块读的就是 `Double`）。
    @discardableResult
    func writeDouble(_ value: Double, config: ConfigHandle) -> Bool {
        config.set(key, to: clamp(value))
    }

    @discardableResult
    func writeString(_ value: String, config: ConfigHandle) -> Bool {
        config.set(key, to: value)
    }

    /// 多选写回：**先按声明顺序收敛**再落盘（写的是 `[String]`，`multiSelect` 模块读的就是它）。
    /// 顺序恒 = `options` 的声明顺序（勾选先后不参与）——模块侧 `resolveScopes` 是「顺序按输入」，
    /// 而用户眼里的顺序就是卡上那一排，两边因此对得上。
    /// 非多选型调用它是**空操作 + false**（与 `set` 的「写不动就答 false」同形，不误写别的类型）。
    @discardableResult
    func writeMultiSelect(_ values: [String], config: ConfigHandle) -> Bool {
        guard case .multiSelect = kind else { return false }
        let chosen = Set(values)
        return config.set(key, to: multiSelectOptions.map(\.value).filter { chosen.contains($0) })
    }

    /// 某一个选项**翻面**（未勾 → 勾上；已勾 → 取消），落盘同上。多选行的每一次点击就是这一下。
    @discardableResult
    func toggleMultiSelect(_ value: String, config: ConfigHandle) -> Bool {
        var chosen = selectedOptions(from: config)
        if let index = chosen.firstIndex(of: value) {
            chosen.remove(at: index)
        } else {
            chosen.append(value)
        }
        return writeMultiSelect(chosen, config: config)
    }

    // MARK: 区间（唯一入口：kind 里那个常量）

    private func clamp(_ value: Int) -> Int {
        guard case .integer(let range) = kind, let range else { return value }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private func clamp(_ value: Double) -> Double {
        switch kind {
        case .number(let range):
            guard let range else { return value }
            return min(max(value, range.lowerBound), range.upperBound)
        case .integer(let range):
            guard let range else { return value }
            return min(max(value, Double(range.lowerBound)), Double(range.upperBound))
        case .boolean, .string, .multiSelect:
            return value
        }
    }
}

/// 模块 config 控件的一行：按 `kind` 分档渲染 —— 布尔 = 小开关、有区间的数值 = 滑杆 + 当前值、
/// 没区间的数值 = 数字输入框、字符串 = 文本框、多选 = 一排可点的胶囊（选中填色）。
///
/// **句柄每次现取**：`ModuleContextFactory.configHandle(for:)` 只是薄壳（schema 快照 + 一次
/// `UserDefaults(suiteName:)`），而本批 config 没有 `observe`（07 §2 属 P1-3）——「改完立刻生效」
/// 靠的是三件事：写路径落盘、这里现读、**宿主重取内容**（模块的 `content(for:)` 每次现读 config，
/// 见 `MusicModule.showsAlbumArt(from:)`）。因此每次写完都叫醒观察注册表的宿主视图
/// （`ModuleRegistry.shared.objectWillChange.send()`）——**不需要重启**。
private struct ModuleConfigControlRow: View {
    let control: ModuleConfigControl
    let manifest: ModuleManifest

    /// 本行的**自刷新令牌**：写完 config 之后，本行要重画一次（值文本与滑杆位置都来自 config）。
    ///
    /// 为什么需要它（2026-09-30 上屏实测的缺陷）：`commit` 里那句
    /// `ModuleRegistry.objectWillChange.send()` 覆盖的是**观察注册表的宿主视图**（首页 strip 那一侧
    /// ——它每次渲染现问模块要内容），**不包括本行自己**：点一下滑杆的轨道，拇指跟着点走、
    /// 而右侧那个数值文本还是旧值（`44` 明明已经写成了 `89.47`）——正是「拨了没反应」的错觉。
    /// 本批 config 没有 `observe`（07 §2 属 P1-3），所以本行只能自己叫醒自己：
    /// 令牌在 `body` 里被读一次（见 `body` 首行），写完自增 → SwiftUI 重画本行 → 现读 config。
    /// 代价：多一个只增不减的 `Int`（视图级，不进偏好、不跨渲染保存语义）。
    ///
    /// **多选那一行同样靠它**（p5-home-blocks / T2）：勾选的选中态就是本行自己读 config 画的，
    /// 缺了这句「勾了不会变色」——与滑杆那一档的缺陷逐字同形。
    @State private var refreshToken = 0

    private var config: ConfigHandle { ModuleContextFactory.configHandle(for: manifest) }

    var body: some View {
        // 读一次令牌：它变了就等于「本行需要重画」，见 `refreshToken` 的注释。
        _ = refreshToken
        return content
    }

    @ViewBuilder
    private var content: some View {
        switch control.kind {
        case .boolean:
            booleanRow
        case .integer(let range):
            if let range {
                sliderRow(in: Double(range.lowerBound)...Double(range.upperBound), step: 1) { value in
                    control.writeInt(Int(value.rounded()), config: config)
                }
            } else {
                integerFieldRow
            }
        case .number(let range):
            if let range {
                sliderRow(in: range, step: nil) { value in
                    control.writeDouble(value, config: config)
                }
            } else {
                doubleFieldRow
            }
        case .string:
            stringRow
        case .multiSelect:
            multiSelectRow
        }
    }

    // MARK: 布尔

    private var booleanRow: some View {
        Toggle(isOn: Binding(
            get: { control.boolValue(from: config) },
            set: { newValue in commit { control.writeBool(newValue, config: config) } }
        )) {
            Text(LocalizedStringKey(control.titleKey))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        // 开关自己带得出名字（辅助功能口径与卡片主开关 / 功能卡那几行一致：AX 里那个 checkbox
        // 的 description 就是这一行的文案，而不是一个没有名字的开关）。
        .accessibilityLabel(Text(LocalizedStringKey(control.titleKey)))
    }

    // MARK: 数值

    /// 有区间的数值：**滑杆 + 当前值**——区间取模块侧那个常量（口径 3），用户拨到端点就停住
    /// （没有「拨出去、读侧再夹回来」的错觉）。整型带 `step: 1`（不会拨出「3.7 个应用」那种值）；
    /// 小数型连续，显示时按最多两位小数收口（`numberText`）。
    private func sliderRow(
        in range: ClosedRange<Double>,
        step: Double?,
        write: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(LocalizedStringKey(control.titleKey))

            slider(in: range, step: step, write: write)
                .frame(width: 150)
                // 辅助功能：滑杆在 AX 里报得出名字（与开关那条同口径）
                .accessibilityLabel(Text(LocalizedStringKey(control.titleKey)))

            Text(numberText(min(max(control.doubleValue(from: config), range.lowerBound), range.upperBound)))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    /// 滑杆本体：有 `step` 用步进式、没有用连续式（两种初始化器在 SwiftUI 里是两个方法，
    /// 因此这一处按需分叉，绑定与写路径共用）。
    @ViewBuilder
    private func slider(
        in range: ClosedRange<Double>,
        step: Double?,
        write: @escaping (Double) -> Void
    ) -> some View {
        // get 也夹一次：手改 `UserDefaults` 写了越界值时，滑杆停在端点上而不是空掉。
        let binding = Binding(
            get: { min(max(control.doubleValue(from: config), range.lowerBound), range.upperBound) },
            set: { newValue in commit { write(newValue) } }
        )
        if let step {
            Slider(value: binding, in: range, step: step)
        } else {
            Slider(value: binding, in: range)
        }
    }

    /// 没区间的整数：数字输入框（回车 / 失焦提交）。**不发明区间**（口径 3）。
    private var integerFieldRow: some View {
        HStack(spacing: 8) {
            Text(LocalizedStringKey(control.titleKey))

            Spacer(minLength: 8)

            TextField(value: Binding(
                get: { control.intValue(from: config) },
                set: { newValue in commit { control.writeInt(newValue, config: config) } }
            ), format: .number) {
                Text(LocalizedStringKey(control.titleKey))
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(width: 70)
            .multilineTextAlignment(.trailing)
            .accessibilityLabel(Text(LocalizedStringKey(control.titleKey)))
        }
    }

    private var doubleFieldRow: some View {
        HStack(spacing: 8) {
            Text(LocalizedStringKey(control.titleKey))

            Spacer(minLength: 8)

            TextField(value: Binding(
                get: { control.doubleValue(from: config) },
                set: { newValue in commit { control.writeDouble(newValue, config: config) } }
            ), format: .number) {
                Text(LocalizedStringKey(control.titleKey))
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(width: 70)
            .multilineTextAlignment(.trailing)
            .accessibilityLabel(Text(LocalizedStringKey(control.titleKey)))
        }
    }

    /// 当前值的显示形态：整数不带小数点、小数最多两位（`44` / `1` / `0.95`）。
    private func numberText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    // MARK: 字符串

    private var stringRow: some View {
        HStack(spacing: 8) {
            Text(LocalizedStringKey(control.titleKey))

            Spacer(minLength: 8)

            TextField(text: Binding(
                get: { control.stringValue(from: config) },
                set: { newValue in commit { control.writeString(newValue, config: config) } }
            )) {
                Text(LocalizedStringKey(control.titleKey))
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(width: 160)
            .accessibilityLabel(Text(LocalizedStringKey(control.titleKey)))
        }
    }

    // MARK: 多选（一排可点的胶囊）

    /// 多选行：左边是这一行的标题（「显示的尺度」），右边是一排**可点的胶囊**——选中填色 + 白字、
    /// 未选中只有描边（观感与两节的 `surfaceBadge` 同一族：小、圆角、可点）。
    ///
    /// 点一下 = 把这一项翻面（`toggleMultiSelect`）→ 走 `commit` 落盘 + 叫醒本行与宿主。
    /// **没有「确定」按钮**：勾上就写、写就生效（这就是 D-05 要的「勾了立刻上屏」）。
    private var multiSelectRow: some View {
        let selected = Set(control.selectedOptions(from: config))

        return HStack(spacing: 8) {
            Text(LocalizedStringKey(control.titleKey))

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ForEach(control.multiSelectOptions) { option in
                    chip(option, isOn: selected.contains(option.value))
                }
            }
        }
    }

    /// 一枚胶囊。`isOn` 只决定长相；点它的动作在 `multiSelectRow` 那一层统一说明。
    private func chip(_ option: ModuleConfigControl.Option, isOn: Bool) -> some View {
        Button {
            commit { control.toggleMultiSelect(option.value, config: config) }
        } label: {
            Text(LocalizedStringKey(option.titleKey))
                .font(.caption)
                .fontWeight(isOn ? .semibold : .regular)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(isOn ? Color.accentColor : Color.clear))
                .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.45), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        // 辅助功能：胶囊自己报得出名字（与滑杆 / 开关那两条同口径）。
        .accessibilityLabel(Text(LocalizedStringKey(option.titleKey)))
    }

    // MARK: 写路径

    /// **先落盘、再刷新**（docs/18 §处理链路），两处刷新各管一件事：
    /// - `ModuleRegistry.shared.objectWillChange.send()` 叫醒**观察注册表的宿主视图**
    ///   （`HomeStripView.resolvedHomeBlocks()` 每次渲染都现问模块要内容，模块再现读 config）；
    /// - `refreshToken` 叫醒**本行自己**（值文本 / 滑杆都读 config，见那个属性的注释）。
    private func commit(_ write: () -> Void) {
        write()
        refreshToken &+= 1
        ModuleRegistry.shared.objectWillChange.send()
    }
}

/// 功能卡的一行：图标 chip + 名称 + 一行「效果 / 出现位置」+ 开关。
///
/// 排版与组件卡逐字同形（chip 在左、开关在右、行内边距一致），但**没有 surfaces 徽标、
/// 没有摘要、没有失败态**：这里没有模块，也就没有「激活 / 失败」这一维（D-07）。
private struct FeatureCardRow: View {
    let card: FeatureCard

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ModuleSymbolChip(symbolName: card.symbolName)

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(card.nameKey))
                    .fontWeight(.medium)

                // 「效果 / 出现位置」：这一段只登记上游总开关，卡面必须写清「拨下去会看到什么」，
                // 否则又是「打开开关但界面没变化」的错觉（docs/20 §做法 机制三）。
                Text(LocalizedStringKey(card.effectKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            // **裸 `Binding`，不是 `@Default`**：`Defaults.Key` 是运行期取值，`@Default` 装不上；
            // 为六行各挂一个订阅不值当。代价见 docs/20 §已知限制 8：本页开着时从上游设置页改同键，
            // 这张卡不即时刷新（关掉重开本页即可）。
            Toggle(isOn: Binding(
                get: { Defaults[card.key] },
                set: { Defaults[card.key] = $0 }
            )) {
                Text(LocalizedStringKey(card.nameKey))
            }
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 首页块顺序的一行

// MARK: - 图标 chip

/// 组件卡与顺序行共用的图标 chip（24×24、accent 底的圆角方块）。
///
/// **取不到图标名就不画**（不画占位方框）——这是 `ModuleSettingsCard` 改动前的口径，抽出来共用，
/// 视觉一个像素都没动。
private struct ModuleSymbolChip: View {
    let symbolName: String

    var body: some View {
        if !symbolName.isEmpty {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
        }
    }
}

// MARK: - 首页的内置块：全宽日历行

/// 首页的**内置块**（它不是模块）：整月网格 + 当日清单的那条**全宽行**。
///
/// **在本节里的行形态与模块卡一致**（图标 + 名称 + 效果行 + 开关），但**没有上移 / 下移**：
/// `homeBlockOrder` 是「块与块之间」的顺序表，而日历行是首页下方那一整条全宽行，不在那份名单里
/// ——给它两个点不动的箭头比不给更坏（docs/26 §实际交付 10、docs/28 §5）。等首页改成单条流
/// （docs/28 §4）它进了流，再补排序。
///
/// 开关读写上游那一个 `showCalendar`：**同一个键同时管首页这条行与展开面板的「日历」页**
/// （docs/26 §做法 机制四），效果行因此必须把两处都写出来。
///
/// 本行原先只是「功能」段里的一张卡（`featureCards` 的 `showCalendar`），用户 2026-09-30 要求
/// 「首页的日历组件也要在首页组件控制区域进行开关控制」之后搬到这里——**键没有变、也没有第二份状态**。
///
/// **两个 key 是 `static let`（不是内联字面量）**：解析用例直接读它们，与本文件其余两张表的
/// 口径一致（表侧写错字才会红）。
struct HomeCalendarSettingsRow: View {
    /// 名称 key：**逐字沿用上游设置页那一项的字面量**（与其余组件卡的取名口径一致）。
    static let nameKey = "Show calendar"
    /// 效果行 key（随本行从「功能」段搬进「首页组件」段）。
    static let effectKey = "settings.modules.calendarRow.effect"

    @Default(.showCalendar) private var showCalendar

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ModuleSymbolChip(symbolName: "calendar")

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(Self.nameKey))
                    .fontWeight(.medium)

                Text(LocalizedStringKey(Self.effectKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle(isOn: $showCalendar) {
                Text(LocalizedStringKey(Self.nameKey))
            }
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }
}

// MARK: - 卡片

/// 一个组件一张卡：SF Symbol 图标 + 名称 + 摘要 + surfaces 徽标 + 上移 / 下移 + 开关。
///
/// 图标与文案的解析顺序与 `ModuleRegistry` 的投影**逐字同序**（名称走 `label(for:)`、
/// 摘要走同一套 key → `table["en"]` 回落）：卡片上显示的必须与展开 tab / 首页块认的是同一份。
///
/// **P3 / T3 起卡片属于某一节**（`group`）：同一个模块可能同时出现在两节（声明了 home 与 expanded），
/// 那时两节各有一张同形的卡，**两节的开关各管各自的 surface**（见 `ModuleSurfaceGroup` /
/// `ModuleSurfaceSwitch`），上移 / 下移也只在本节内重排（写本节的顺序键）。
private struct ModuleSettingsCard: View {
    @ObservedObject var registry: ModuleRegistry
    let manifest: ModuleManifest
    /// 本卡片在哪一节（决定：开关读哪张摘除名单、写哪个顺序键、上移 / 下移重排哪一份名单）。
    let group: ModuleSurfaceGroup
    /// 本节里的位置（两端置灰那两个按钮）。
    let isFirst: Bool
    let isLast: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void

    /// 本节的**摘除名单**（两节的开关各读各自的那一张；`@Default` 是 `DynamicProperty`，
    /// 写盘即重绘本卡片——另一个面那一节的卡也会重绘，因为读的是同一个键的两条路）。
    @Default(.hiddenHomeModules) private var hiddenHomeModules
    @Default(.hiddenPanelModules) private var hiddenPanelModules

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ModuleSymbolChip(symbolName: manifest.icon.name ?? "")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(ModuleRegistry.label(for: manifest))
                        .fontWeight(.medium)
                    ForEach(manifest.surfaces, id: \.rawValue) { surface in
                        surfaceChip(surface)
                    }
                }

                // 「效果 / 出现位置」——**徽标正下方**的一行（P2 / T2，docs/17 §已知限制 16 同批改判）：
                // 三个组件里只有待办有首页效果，卡片必须自己讲清「开它之后会在哪看到什么」，
                // 否则「打开开关但界面没变化」看起来就是坏的。文案按模块 id 映射（不是通用模板）。
                if let effectKey = Self.effectKey(for: manifest) {
                    Text(LocalizedStringKey(effectKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // `defaultEnabled == false` 的模块另标一行「默认关闭」：它的开关本来就是关的，
                // 而「卡片开着但首页/槽位没效果」是它**默认**的合法形态，不是故障。
                // 判据取 manifest 字段（不写死 id——将来默认关的模块也自动拿到这一行）；
                // `nil`（manifest 没写这个键）不标——缺失不是「默认关闭」的证据。
                if manifest.defaultEnabled == false {
                    Text(LocalizedStringKey("settings.modules.defaultOff"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let summary = Self.summary(for: manifest) {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // **模块 config 控件**（允许清单：音乐 / 启动台 / 快捷指令 / 前台应用四张卡）——
                // 卡片自己的子设置行，放在描述行之后、失败态之前。命中判据是登记表里的模块 id：
                // **不按 manifest schema 自动生成控件**（通用渲染器是另一个批次的活，见 `configControls`）。
                ForEach(ModuleSettingsSection.configControls(forModuleID: manifest.id)) { control in
                    ModuleConfigControlRow(control: control, manifest: manifest)
                }

                // **登记了但这里不可编辑的上游键**：一行灰字说清（docs/24 §做法 机制四）——
                // 那句「改了不生效」必须写在卡上，否则用户看到的是「组件页管着一切」的错觉。
                // 判据取 manifest 的登记键（纯函数，见 `upstreamManagedKeys`）：只有接管模块
                // 才可能非空（它们的真源在上游 `Defaults`）。
                if !upstreamManagedKeys.isEmpty {
                    Text(LocalizedStringKey("settings.modules.upstreamManaged"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 失败态只回显**一行**：`failed` 是终态、要恢复只能重启（D-13），
                // 具体原因是调试信息，卡片不放（裁决 2）。
                if isFailed {
                    Text(LocalizedStringKey("settings.modules.failed"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer(minLength: 12)

            // 上移 / 下移：**在本节里**重排这一行（写本节的顺序键，见 `move(_:in:direction:)`）。
            // 按钮形态与文案沿用既有那条顺序行的口径（`Move Up` / `Move Down`，`borderless` +
            // 两端置灰），**不引入拖拽**（docs/26 §明确不做）。
            orderButtons

            Toggle(isOn: toggle) {
                Text(ModuleRegistry.label(for: manifest))
            }
            .labelsHidden()
            .disabled(isFailed)
        }
        .padding(.vertical, 4)
    }

    /// 卡片右侧的两个排序按钮（在开关左边、与开关同一行）。
    private var orderButtons: some View {
        HStack(spacing: 4) {
            Button(action: moveUp) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(isFirst)
            .help(Text(LocalizedStringKey("Move Up")))
            .accessibilityLabel(Text(LocalizedStringKey("Move Up")))

            Button(action: moveDown) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(isLast)
            .help(Text(LocalizedStringKey("Move Down")))
            .accessibilityLabel(Text(LocalizedStringKey("Move Down")))
        }
    }

    // MARK: 开关

    /// 本节的开关 get（P3 / T3）：**模块开着 **且** 没在本节被摘掉**（两节各自的开关只管各自的
    /// surface，见 `ModuleSurfaceGroup.isOn`）。前半截只读注册表状态（偏好不是真源，内存状态才是）：
    /// `.active` / `.activating` → on；`.disabled` → off；**`nil`（已注册未判定）也按 off**；
    /// `.failed` → off（并见 `isFailed`：开关同时被禁用）。
    private var isOn: Bool {
        let moduleEnabled: Bool
        switch registry.states[manifest.id] {
        case .some(.active), .some(.activating): moduleEnabled = true
        case .some(.disabled), .some(.failed), .none: moduleEnabled = false
        }
        return ModuleSurfaceGroup.isOn(moduleEnabled: moduleEnabled, isHidden: isHiddenOnSurface)
    }

    /// 本节是否被用户显式摘掉（`hiddenHomeModules` / `hiddenPanelModules`）。
    ///
    /// **本卡片两节的开关各读各自的那一张名单**（`@Default` 观察的是同一个键，两节因此都会重绘）。
    private var isHiddenOnSurface: Bool {
        switch group {
        case .home: return hiddenHomeModules.contains(manifest.id)
        case .panel: return hiddenPanelModules.contains(manifest.id)
        }
    }

    /// `failed` 是终态：开关不可点（06 §3.3 硬性规则 1「不重试」的 UI 面）。
    private var isFailed: Bool {
        if case .some(.failed) = registry.states[manifest.id] { return true }
        return false
    }

    /// 本卡片上**登记了但这里不可编辑**的上游键（唯一判据在
    /// `ModuleSettingsSection.upstreamManagedKeys(for:takeoverKeyName:)`，本处只把注册表里那个
    /// 接管键的**名字**递进去——非接管模块传 nil，函数据此一律答空表）。
    private var upstreamManagedKeys: [String] {
        ModuleSettingsSection.upstreamManagedKeys(
            for: manifest,
            takeoverKeyName: registry.takeoverEnableKey(for: manifest.id)?.name
        )
    }

    /// set：**一次拨动 = 一次 `ModuleSurfaceToggleWriter.write`**（先落盘再改内存，docs/17 §处理链路）。
    ///
    /// 写什么由那一处按 `ModuleSurfaceSwitch.effect` 裁决（P3 / T3）：置开 → 启用真源 + 取消本节摘除；
    /// 置关且模块还有另一个面 → **只**写本节的摘除名单；置关且本节是唯一的面 → 写既有启用真源
    /// （`ModuleEnablementWrite`，接管模块写上游总开关、非接管写 `moduleEnableOverrides`）。
    /// `localizedError` 那一档（启动失败的回弹）也在写路径里（D-13 的两档），本处不再重一遍。
    private var toggle: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { newValue in
                Task {
                    await ModuleSurfaceToggleWriter.write(
                        newValue,
                        manifest: manifest,
                        group: group,
                        registry: registry
                    )
                }
            }
        )
    }

    // MARK: 呈现

    /// surfaces 徽标：命中一个取值就一枚小 chip。
    ///
    /// key 用**先拼成 `String` 再构造 `LocalizedStringKey`**：把插值直接写进
    /// `LocalizedStringKey` 字面量会被编译成 `%@` 占位形态的 key，查不到文案。
    private func surfaceChip(_ surface: Surface) -> some View {
        Text(LocalizedStringKey("settings.modules.surface." + surface.rawValue))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }

    /// 「效果 / 出现位置」一行的本地化 key：查 `ModuleSettingsSection.effectKeysByModuleID`
    /// 这张**唯一的表**（键 = 模块 id、值 = 效果行 key；每行写的是什么、为什么按模块逐块映射，
    /// 都记在表上，本函数只做一次查表）。
    ///
    /// 未命中（将来注册的第三方模块）返回 nil，**整行不显示**——不猜它出现在哪。
    private static func effectKey(for manifest: ModuleManifest) -> String? {
        ModuleSettingsSection.effectKeysByModuleID[manifest.id]
    }

    /// 摘要的解析顺序与 `ModuleRegistry.label(for:)` **逐字同序**：key 形态查 `Bundle.main`
    /// （查不到时 `Bundle` 原样返回 key，据此判定）、再查 `table["en"]`；两者都取不到则
    /// **整行不显示**——摘要缺失是合法形态（`label` 的 shortID 兜底只属于名称）。
    private static func summary(for manifest: ModuleManifest) -> String? {
        guard let summary = manifest.summary else { return nil }
        if let key = summary.key, !key.isEmpty {
            let localized = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
            if !localized.isEmpty, localized != key { return localized }
        }
        if let english = summary.table?["en"], !english.isEmpty { return english }
        return nil
    }
}
