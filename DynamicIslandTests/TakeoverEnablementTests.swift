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
//  TakeoverEnablementTests.swift
//  Gourd 模块内核 · 接管三件套与重同步桥（P2 接管批次 / T1）
//
//  覆盖 docs/20-component-page.md §接口与数据形状 1/2/3 与 §做法 机制一/机制二：
//
//  - **启用真源 read-through**：接管键（`GourdModule.takeoverEnableKey`）压过
//    `moduleEnableOverrides` 与 `manifest.defaultEnabled`——两个方向都压（键 false + overrides true
//    → `.disabled`；键 true + overrides false → `.active`），缺 overrides 时也压 manifest 默认；
//  - **重同步桥**：模块 `.active` 后上游键被改 false → 让出主 actor 若干回合后 `states` 跟着变
//    （订阅回调走 `Task { @MainActor }`，不是同帧）；
//  - **`failed` 不被桥救活**：`activate()` 抛错的模块在键被置 true 后仍是 `.failed`、
//    `activate()` 不被第二次调用（D-13 / 06 §3.3 硬性规则 1）；
//  - **`isTabVisible()` 契约**：缺省 true 进 `tabEntries`；重写成 false 的假模块**不进**，
//    而它的 `states` 仍是 `.active`（可见性与启用是两件事）；
//  - **写路径**（`ModuleEnablementWrite`）：接管键非 nil → 只写上游键、连 overrides 键都不写出来；
//    nil → 只写 overrides、上游键一个字节不动；
//  - **桥幂等（进入时先清空）**：`startTakeoverBridge` 进入时先 `removeAll()`，再按当前注册表里的
//    接管模块逐个建订阅——重复起桥是**替换**不是翻倍，注册表清空后再起桥不会留下上一段的订阅，
//    非接管模块不建订阅；
//  - **块宽钩子**：声明了块宽的模块取值一致、未声明为 nil、未注册 id 为 nil；
//  - **回弹策略**（`ModuleEnablementRollback`，D-13）：接管模块 nil（什么都不写）、非接管模块 false。
//
//  P2 接管批次 / T2 追加（同一个真模块的声明与计数）：
//  - **`TimerModule` 的 manifest 契约**：`surfaces == [.expanded]`（不含 `.compact`）、
//    `moduleID == manifest.id`、`config` 只登记上游三键、两条取值型钩子（真源键 / 无块宽）；
//  - **计数回归**（docs/20 §做法 机制五）：上游那条 `+1` 删掉后，计时器对
//    `enabledStandardTabCount()` 的贡献仍是 1 / 0 / 0（启用 × 显示方式三种组合）。
//
//  P2 接管批次 / T3 追加（计时器页判据——第二入口与 250pt 高度档）：
//  - **`isTimerSurfaceSelected()`**（docs/20 §做法 机制六 / D-11）三档：
//    `.timer`（老路径，枚举成员按机制六保留）与 `.module` + `TimerModule.moduleID`
//    （今天唯一的生产形态：悬浮聚焦 / 点预设 / `startCustomTimer` 三条路径都走它）都答 true；
//    `.module` + 别的模块 id、以及 `.home`（哪怕 `selectedModuleID` 残留着计时器 id）答 false。
//
//  P2 接管批次 / T4 追加（镜子接管模块 + 首页块顺序表的历史键映射）：
//  - **`MirrorModule` 的 manifest 契约**：`surfaces == [.home]`（不含 `.expanded` / `.compact`）、
//    `defaultPlacement == Placement(slot: nil, order: 2)`、真源键 `showMirror`、块宽 140/140
//    （p5-home-blocks / T3 起：方形，与宿主的大块档高同源）、`config` 只登记上游三键；
//  - **`MirrorModule.isVisible(showMirror:cameraAvailable:)`** 四组：两段是「且」；
//  - **`HomeBlockOrdering.migratingLegacyIDs`** 四组：旧键 → 新 id、新键优先、非映射键逐字保留、
//    空表恒等；另有一条**经 `sorted(...)` 走一遍**的用例（映射是 `sorted` 的第一步——只测纯函数的话
//    「映射没接上」不会红）。
//
//  P2 接管批次 / T5 追加（音乐接管模块 + 命名空间环境键的默认值半边）：
//  - **`MusicModule` 的 manifest 契约**：`surfaces == [.home]`（不含 `.expanded` / `.compact`）、
//    `defaultPlacement == Placement(slot: nil, order: 0)`（= 被接管的内置音乐块的默认序号）、
//    真源键 `showStandardMediaControls`、**三条取值型声明**（p5-home-blocks / T3 起成套改，
//    块宽 p6-ui-polish / T2 再缩一档：200/250、形态 `.compact`、`showAlbumArt` 默认 false）、
//    `config` = 只登记上游两键 +
//    本模块自己的呈现键 `showAlbumArt`（P2 首页修正批次 / T5 追加，D-06）；
//  - **`MusicModule.isVisible(showStandardMediaControls:autoHideInactive:hasActiveSession:)`** 四组：
//    两段是「且」（表达式逐字沿用上游那个 `shouldShowMusicPlayer`）；
//  - **`EnvironmentValues().homeAlbumArtNamespace == nil`**（D-08 的默认值一半：没人注入时是 nil，
//    模块侧据此退回自带 `@Namespace`）。**注入那一半没有自动化断言**——注入点是 SwiftUI 视图修饰符
//    （`HomeStripView` 的 `.environment(\.homeAlbumArtNamespace, …)`），起作用与否只能人工验收
//    （封面配对动画：折叠态播放器 ↔ 展开态音乐块）；为它造一条「读回自己刚写的环境值」的断言
//    只是把修饰符抄进用例，不证明宿主真的注入了，故不写（见 T5 报告 §4）。
//
//  P2 首页修正批次 / T5 追加（音乐封面开关 `showAlbumArt`，docs/23-home-fit.md §做法 机制五 / D-06）：
//  - manifest 的 `showAlbumArt`：`boolean`、默认值 = `MusicConfigDefaults`
//    （**p5-home-blocks / T3 翻面成 `false`**，D-09：紧凑档默认不画封面）——键名 / 类型 / 默认值
//    三条都钉住，默认值再钉一次字面量 false（方向也要钉：用户要的是「可以不显示那个图片」）；
//  - **读取侧分档**（`MusicModule.showsAlbumArt(from:)`）三档：用户覆盖 false / 覆盖 true /
//    缺键（schema 里没这个键也一样）回落默认档。假体是内存 `RecordingConfigHandle`，不碰真实域。
//
//  P2 首页修正批次 / T5 **修复轮**追加（封面开关的界面入口——范围评审的唯一一条 Important）：
//  - **控件登记表对生产事实**（`testMusicAlbumArtControlMatchesManifestAndCatalog`）：模块 id =
//    真模块 id、config 键逐字命中 `manifest.config.properties`、类型 boolean、回落值 =
//    `MusicConfigDefaults.showAlbumArt`、文案 key 在 zh-Hans 里解析得出来；
//  - **写路径端到端**（`testMusicAlbumArtControlWriteIsReadableByTheModule`）：控件写 false →
//    模块自己的读侧（`MusicModule.showsAlbumArt(from:)`）立刻读到 false，落盘就在
//    `com.cmeng.gourd.module.<shortID>` 的 JSON 字节里。probe 域（`…module.probe-albumart`）
//    用完即删，**不碰**开发机真实的 `com.cmeng.gourd.module.music`。
//    视图接线（开关一拨就重绘首页 strip）没有自动化断言，只能人工验收（同 T5 那条的口径：
//    截图 `.workflow/p2-home-fit/evidence/t5-ui-*.png`）。
//
//  P2 接管批次 / T6 追加（组件页的文案解析——功能卡段 + 接管卡的效果行）：
//  - **功能卡的键解析**（P2 时七张；T6 收尾摘掉 `enableNotes` 那张、2026-09-30 又摘掉
//    `showCalendar` 一张；**p5 / T4 整段撤销**）：原数据源是生产表本身
//    （`ModuleSettingsSection.featureCards`，为了这条用例它没写成 `private`）——
//    `id` / `effectKey` / `nameKey` 写错或文案没进 catalog 都会红。T4 把段、表与两个类型一起删了，
//    这条用例因此改写成它的**负向承接形态**（`testFeatureSectionIsGoneAndItsOldKeysHaveASingleEntryPoint`：
//    七条 key 已从 catalog 删除 + 五张卡的落点各自钉死 + 锁屏页那一行是唯一入口）；
//  - **三个接管模块的名称 / 效果行 key 解析**：名称 key 取自真模块的 manifest（与 `label(for:)`
//    同源）；
//  - **回弹两档**用三个真模块的真源键再钉一遍（钉的是策略函数，不是视图接线——同见报告）。
//
//  P2 接管批次 / T6 **修复**（补齐上一轮两条覆盖缺口的第二条 + 测试本地化形态）：
//  - **效果行映射有断言了**：映射从 `ModuleSettingsCard` 的私有 switch 提成生产表
//    `ModuleSettingsSection.effectKeysByModuleID`（internal），`testModuleEffectKeysMatchTableAndCatalog`
//    迭代它——值写错（含写成另一条已存在的 key）与模块 id 写错都会红。上一轮「把
//    `settings.modules.effect.music` 改成错字」是全绿的（T6 报告 §3 变异 ②b）；
//  - **`XCTAssertResolves` 锁定语言**：改查宿主 bundle 的 **zh-Hans** 那一份。七条上游名称 key
//    没有 `en` 值，原先的 `Bundle.main.localizedString + != key` 跟着机器语言走（英语环境下红）。
//    Swift 在 Darwin 上没导入带 `localization:` 的四参重载，故用等价的 `.lproj` 子 bundle 形态。
//
//  p3-widgets / T3 追加（组件页两节：**分组 + 面板排序 + 两节各自的开关**，docs/26 §做法 机制三 / D-03）：
//  - **两节的判据对生产事实**：`ModuleSurfaceGroup.surface` = home / expanded 两条，真模块每一节都找得到
//    归属，待办 / 通知同时在两节里（节头那句「可能同时在两节」的实例）；四条节文案在 zh-Hans 里解析得出；
//  - **`panelRank` 纯函数**：用户覆盖 → 默认序号 → `Int.max`；`panelOrder` 影响 `tabEntries` 顺序
//    （端到端：真注册表 + 两个假模块 + 真偏好键）；新键的**名字 / 默认值 / 序列化往返**（临时 suite）；
//  - **两组写盘互不影响**：顺序键两个（`homeBlockOrder` / `panelOrder`）、摘除名单两张，写一组不碰另一组，
//    翻盘算式（`ModuleSurfaceGroup.orderTable`）的「名单没变返回 nil = 不写盘」三档；
//  - **一次拨动的语义**（`ModuleSurfaceSwitch.effect` 三档 + `hasOtherSurface` / `isOn` / `updated` 纯函数）；
//  - **写路径端到端**（`ModuleSurfaceToggleWriter`）：双面模块关首页 → 只写 `hiddenHomeModules`、
//    模块仍 active、面板 tab 照旧、启用真源一个字节没动；关面板 → 反过来；单面模块关 → 写
//    `moduleEnableOverrides`（既有启用真源，**不进摘除名单**）。
//
//  P3 冻结批次 / T7 追加（组件页的模块配置编辑口——**允许清单**，docs/24 §做法 机制四）：
//  - **清单对生产事实**（`testConfigControlAllowlistMatchesManifestsAndCatalog`）：十一条清单项逐条钉死，
//    每条都断言「模块 id 是已注册模块」「键在 manifest 的 `config.properties` 里」「kind 与声明的
//    `type` 一致」「文案在 zh-Hans 里解析得出」「(模块 id, 键) 不重复」——键名写错一个字即红
//    （T7 的变异验证靶子）；
//  - **两处边界**（`testConfigControlAllowlistExcludesTakeoverUpstreamKeys`）：接管模块登记的上游键
//    不进清单（真源在上游 `Defaults`，拨了没人读），且它们的卡片必须出那行
//    「由上游设置管理」；非接管模块（含没有 `config` 的日历）一律不出；
//  - **写路径端到端**（`testConfigControlWritePathsShareTheModuleConfigHandle`）：五种控件类型各写
//    一遍，落盘在 probe 域（`…module.probe-config` 用完即删），**模块自己的读侧**立刻看到同一个值；
//    另钉住「写盘的 JSON 类型」与「区间夹取读写各一次」。
//
//  p5-home-blocks / T2 追加（进度卡的**尺度多选**——允许清单的第五种控件类型，docs/29 §做法 机制二 / D-05）：
//  - **清单新条**：`com.cmeng.gourd.progress.visibleScopes`（`.multiSelect`）逐条对 manifest；
//    多选↔`list` 的类型配对、选项与文案 key 的 1:1、以及「manifest 默认值必须是可勾的选项」
//    都收在允许清单用例里；选项的具体取值与顺序由 `testProgressVisibleScopesControlMatchesManifestAndCatalog`
//    钉死（= `ProgressCalculator.Scope.allCases`）；
//  - **多选读写口径**：`toggleMultiSelect` 翻面、野值丢弃、**顺序恒按选项声明顺序**（写侧与读侧
//    各收敛一次）、非多选型调用写多选是空操作（见上面那条端到端用例的 ⑥ 档）；
//  - **卡片与模块同算一组**（T2 审查 Important 的回归）：读侧先经 `multiSelectEffectiveSet`
//    （登记表里接的是模块的 `ProgressCalculator.resolveScopes`）再按选项过滤——空表 / 全坏值 →
//    勾中的是出厂三档，不是「一个都没勾」；`toggleMultiSelect` 拒绝把最后一档也取消（不落盘）。
//    多选漏给解析函数由允许清单用例的非空断言拦下。
//
//  p7 / T3 追加（进度卡的**工作日三行**，docs/31-home-workday-launcher.md §接口与数据形状 4 / D-08）：
//  - **清单新三条**：`com.cmeng.gourd.progress.workStart` / `.workEnd`（`.integer`，区间 =
//    `WorkdayCalendar.workHourRange`）与 `.workdays`（`.multiSelect`，选项 = ISO 1…7、文案 key =
//    `module.progress.weekday.<ISO>`，`multiSelectEffectiveSet` 接 `WorkdayCalendar.resolveWorkdays`）；
//    类型 / 选项 / 默认值 / 有效值解析由 `testProgressWorkdayControlsMatchManifestAndCatalog` 钉死
//    （空表 / 全坏值 → 一~五，与块判定同一处）；
//  - **三条 titleKey 与七条 weekday 选项 key** 在允许清单用例的 ④ 档里逐个 `XCTAssertResolves`。
//
//  p7 / T5 追加（启动台上区**两条新 key**，docs/31-home-workday-launcher.md §接口与数据形状 5 / D-18）：
//  - `testLauncherQuickLaunchKeysLiveOnlyInTheInPackageCatalog`：`module.launcher.quickLaunch` /
//    `.quickLaunchHint` 的 zh-Hans / en 值与 `translated` 状态、宿主 bundle 的 zh-Hans 解析，
//    以及「只在进包那份 catalog」（根那份不得收这两条键）。
//
//  p5-home-blocks / T5 追加（「面板组件」节的**宿主行**——模块行之外的另一半，docs/29 §做法 机制三 / D-07、D-08）：
//  - **四条宿主行的键解析**（`testHostPanelRowsPinTheFourHostKeysAndResolveNameKeys`）：数据源是生产表
//    `ModuleSettingsSection.hostPanelRows`（与本页其余几张生产表同口径）——顺序 / 键名 / `nameKey`
//    四条上游字面量逐字钉死，`key` 必须是 `Defaults.Keys` 里那**一个对象**（`===`，不是另造的同名
//    字面量）；用量（`enableLLMUsageFeature`）刻意不在表里（上一批「删页留码」的裁决，重新登记
//    就是与已定决策矛盾）；
//  - **「登记的键真的在用」**（`testHostPanelRowKeysAreReallyInUseByTheTwoBackingViews`）：四条键必须
//    落在 `TabSelectionView.hostPanelGateKeys` ∪ `DynamicIslandHeader.hostPanelGateKeys` 里——
//    两份名单是那两个视图**真的在读**的门槛键声明（读取点就在它们各自的 `tabs` / `body` 里）。
//    方向只有一个（登记 ⊆ 在用），反方向在真实键集上不可达（枚举表逐条写明其余门槛键的归属）。
//
//  p6-ui-polish / T9 追加（**宿主三 tab 并入面板排序**，docs/30-ui-polish-and-shelf.md §做法 机制七 /
//  D-15、D-16——上面 T5 那条「宿主行只有开关、没有 ↑↓」的口径由此改写）：
//  - **一条用例三层**（`testHostPanelRowsJoinThePanelOrderAndDefaultSequenceIsUnchanged`）：
//    ① 宿主 id（`shelf` / `clipboard` / `terminal`）↔ gate 键的三方映射（`PanelHostTab` ↔ `hostPanelRows`
//    ↔ `TabSelectionView.hostPanelGateKeys`）；② 取色器不在排序名单（没有排序 id、也没有可写的表）；
//    ③ **默认序逐字**——喂给 `PanelTabSequence.slots(...)` 骨架的每个 gate 都写明来处，空表时输出
//    = 改动前 `TabSelectionView.tabs` 的实际渲染顺序；④ **写表后消费点跟随**：走真写路径
//    （`ModuleSurfaceGroup.panel.writeOrderTable`）+ 真 `panelOrder` 键，面板条（`sequence`）与设置页
//    名单（`ModuleSettingsSection.panelMovableIDs`）读同一张表，非可排项（用量 / 扩展 tab）槽位不动；
//    ⑤ 剪贴板图标模式下它没有槽位，残留的排序值不影响 tab 条。
//
//  p6-ui-polish / T10 追加（**空闲动画：开关打开而从未选过样式时的兜底写**，docs/30-ui-polish-and-shelf.md
//  §做法 机制八 / D-17——根因是上游 `f9ad0282` 插入的空体分支把关闭态中央槽位吞掉）：
//  - **一条用例三层**（`testEnablingIdleAnimationSelectsTheFirstBundledStyleWhenNoneChosen`）：
//    ① 写入——`IdleAnimationManager.selectFirstBundledIfNoneSelected()` 选中的是库里**第一条内置**
//    动画（用户动画排在最前也不选它）；② **叫醒**——写进去的值经 `selectedIdleAnimation` 键发出
//    （`ContentView` 的 `@Default(.selectedIdleAnimation)` 观察点靠它重绘），没写就没有新值经这个键
//    发出（按**值**断言，不数事件条数——同一次写实测会拆成 1~2 条 KVO 通知）；③ 不越权——已有选择 /
//    库里没有内置动画时一个字都不动。
//    链上的顺序与 nil 门（`ContentView` 关闭态中央槽位链）没有自动化断言：那是 SwiftUI 视图体里的
//    分支顺序，只能上屏验收（收尾波截图），计划书未要求为它造断言。
//
//  p6-ui-polish / T10 **修复轮**追加（**内置动画的渲染期源解析**——第二层根因：存储值里是写入时刻的
//  绝对路径，实锤 `/Volumes/壶中天/Gourd.app/…` 指向已卸载的卷 → `IdleAnimationView` 加载为空）：
//  - **一条用例三层**（`testBuiltInIdleAnimationResolvesToTheCurrentBundleFileAtRenderTime`）：
//    ① 死路径的内置动画经 `IdleAnimationManager.resolvedAnimation(for:)` 解析回**当前 bundle 里真实
//    存在的文件**（非 nil / 非空，= `Bundle.main` 的同一份资源）；② 身份仍取存储值（id / speed 不变，
//    覆盖与「已选择」判定按存储 id）——匹配键是 `name` 不是 id（`loadBundledAnimations()` 每次加载
//    都新生成 UUID，见 manager 里那段注释）；③ 自定义动画（`isBuiltIn == false`）不走内置解析、
//    原样返回；另加回落层：新鲜列表里没有同名条目 → nil。
//
//  p5-home-blocks / T5 **修复轮**（独立评审 P2：关掉宿主元素后面板还停在它上面；
//  `docs/29` §机制三那四条宿主行在协调器一侧的闭环）：
//  - **视图归一化表对键**（`testHostSurfaceGateViewsCoverTheSameFourKeysAsTheSettingsRows`）：
//    `DynamicIslandViewCoordinator.hostSurfaceGateViews` 与 `ModuleSettingsSection.hostPanelRows`
//    必须是同一批键、同序，且「一个视图只归一条」；四条映射逐条钉死（`.shelf` / `.terminal` /
//    `.notes` + `.clipboard` / `.colorPicker`）；
//  - **归一化两路各一条**（`testHostSurfaceGateNormalizationResetsGatedOffViews`）：纯函数
//    `isHostSurfaceGatedOff(_:offKeyNames:)` 五条 + 反例三档；端到端「停在 `.shelf` → 关暂存器 →
//    收回 `.home`」（订阅那一路）与「键关着时 `.terminal` / `.notes` / `.clipboard` 连选都选不上」
//    （`currentView.didSet` 守卫那一路）；另有一条反例断言「关一个不门控当前视图的键不许动它」。
//
//  P3 冻结批次 / T6 追加（日历接管模块——孤儿视图 `StandaloneCalendarView` 的展开 tab）：
//  - **`CalendarModule` 的 manifest 契约**：`surfaces == [.expanded]`（不含 `.compact` / `.home`）、
//    `defaultPlacement == nil`、真源键 `showCalendar`、无块宽、`config == nil`（口径 3：本模块没有
//    自己的配置键，唯一相关的上游键就是接管键本身）；
//  - **接管键 read-through**：`showCalendar` 关 → `.disabled` + 不进 tab 投影 + 展开请求降级
//    `.unavailable`；开 → `.active` + 进 tab 投影 + 展开请求拿到 `.view`。两个方向都走真门，
//    这是 T6 的变异验证靶子（换掉接管键 → 本条红）。
//
//  p3-widgets / T2 追加（统计接管模块——CPU / 内存 / GPU 的**首页块**）：
//  - **`StatsModule` 的 manifest 契约**：`surfaces == [.home]`（不含 `.expanded`——D-02
//    「不需要单独面板」，上游那条 Stats tab 分支与本批同删）、`defaultPlacement ==
//    Placement(slot: nil, order: 50)`、真源键 `enableStatsFeature`、块宽 220/300、`config` = 真源键
//    + 三格图表可见性键（登记键）；三环的标签 key / 值口径（`StatsHomeBlockLayout`）逐条钉住；
//  - **接管键 read-through**：`enableStatsFeature` 关 → `.disabled` + 首页块投影为空 +
//    首页请求降级 `.unavailable`；开 → `.active` + 进首页块投影 + 首页请求拿到迷你条（`.view`）。
//    两个方向都走真门，这是本批的变异验证靶子（换掉接管键 → 本条红）。
//
//  p3-widgets / T9 追加（统计块从三行横条改**环状**，docs/26 §做法 机制八 / D-11）：
//  - **尺寸纯函数 `StatsRingMetrics`**：直径 46（宽 < 200 退 40）、环间距 10、主环 5pt + 亮描边 2pt、
//    环轨 0.12、环心字号随直径退档、环心文字可用宽 = 内径 − 两侧各 2；
//  - **「不裁」有断言**：宿主给统计块的最小宽 220 下三环 + 间距 = 158 ≤ 220，180 下 140 ≤ 180
//    （这条是 T9 的变异验证靶子：直径恒 46 → 窄档那条红）；
//  - **分色取自面板既有的系统色家族**：CPU 青 / 内存 紫 / GPU 琥珀（不新造 hex）。
//
//  三条刻意写死的口径（改动前先读）：
//
//  1. **注册一律走真门 `KernelBootstrap.enablementGate(registry:)`**：用旧门
//     （`manifests[$0]?.defaultEnabled`）的话接管键根本不被读，read-through 用例永不可能过；
//  2. **不调 `KernelBootstrap.bootstrap()`**：那个入口会落首启默认值（写开发机真实的
//     `enableScreenAssistant`，见派发片段与 `KernelBootstrap.applyFirstLaunchDefaults`）。
//     用例只调注册表自己的 `bootstrap()`，桥直接调 `KernelBootstrap.startTakeoverBridge`；
//  3. **偏好卫生**：每个写真实键的用例进入时记下该键的**持久域原值**、`defer` 逐字还原
//     （原本有键写回原值、原本没键删键）——跑完 `defaults read com.cmeng.gourd.dev <键>`
//     （测试域是 Debug 域，不是 Release 域 `com.cmeng.gourd`）与跑之前相同。
//     不写 `Defaults.withoutPropagation`：桥要看的正是「键变了」，屏蔽掉就把被测行为一起屏蔽了。
//

import AppKit
import Defaults
import SwiftUI
import XCTest

@testable import Gourd

@MainActor
final class TakeoverEnablementTests: XCTestCase {

    /// 夹具 id（与 `TakeoverFixture.manifest(shortID:)` 同址派生）。
    private let id = "com.cmeng.gourd.probe-takeover"
    private let hiddenTabID = "com.cmeng.gourd.probe-takeover-hidden-tab"
    private let wideBlockID = "com.cmeng.gourd.probe-takeover-wide"
    private let failingID = "com.cmeng.gourd.probe-takeover-failing"
    private let baseID = "com.cmeng.gourd.probe-takeover-base"
    private let ghostID = "com.cmeng.gourd.probe-takeover-ghost"

    /// T3 两节用例的三个夹具 id（与 `TakeoverFixture.manifest(shortID:)` 同址派生）。
    private let surfaceAID = "com.cmeng.gourd.probe-surface-a"
    private let surfaceBID = "com.cmeng.gourd.probe-surface-b"
    private let surfaceDualID = "com.cmeng.gourd.probe-surface-dual"

    // MARK: - 隔离

    override func setUp() async throws {
        try await super.setUp()
        await ModuleRegistry.shared.deactivateAll()
        // `deactivateAll()` 连 `manifests` / `moduleTypes` 一起清（接管查询因此也一并清空），
        // 用例必须自己重新 `register(...)`（同 `ModuleToggleTests` 的坑）。订阅表在这里清干净：
        // 注册表空时起桥 = 只 `removeAll()`，上一个用例的桥不会把状态写进下一个用例。
        KernelBootstrap.startTakeoverBridge(registry: ModuleRegistry.shared)
        TakeoverLedger.reset()
    }

    override func tearDown() async throws {
        await ModuleRegistry.shared.deactivateAll()
        KernelBootstrap.startTakeoverBridge(registry: ModuleRegistry.shared)
        TakeoverLedger.reset()
        try await super.tearDown()
    }

    // MARK: - 启用真源（read-through）

    /// 接管键压过 overrides 与 manifest 默认——两个方向都压（「真源唯一」的判据）。
    func testTakeoverKeyBeatsOverridesAndManifestDefault() async {
        let preferences = snapshotPreferences()
        defer { restore(preferences) }

        let registry = ModuleRegistry.shared
        // 夹具的 manifest 默认**故意**是 `true`（与上游键的语义相反），overrides 也显式写着 true：
        // 门若还是旧口径（overrides → manifest），这里就会放行。
        Defaults[.enableTimerFeature] = false
        Defaults[.moduleEnableOverrides] = [id: true]

        registry.register(
            [TakeoverProbeModule.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )
        await registry.bootstrap()

        XCTAssertEqual(registry.states[id], .disabled, "接管键 false 压过 overrides true 与 manifest 默认 true")
        XCTAssertNil(registry.instance(for: id), "未启用的模块不实例化")
        XCTAssertTrue(registry.tabEntries.isEmpty, "未启用 → 不进 tab 投影")

        // 去掉 overrides（缺键 = 用户未表达）再走一遍：接管键 false 同样压过 manifest 默认 true。
        await registry.deactivateAll()
        Defaults.reset(Defaults.Keys.moduleEnableOverrides.name)
        registry.register(
            [TakeoverProbeModule.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )
        await registry.bootstrap()

        XCTAssertEqual(registry.states[id], .disabled, "缺 overrides 时接管键 false 仍压过 manifest 默认 true")
        XCTAssertNil(registry.instance(for: id))
    }

    /// 接管键是**唯一**真源：键 true 时，overrides 里的 false 与 manifest 默认都压不过它。
    func testTakeoverKeyIsTheOnlyTruthForEnablement() async {
        let preferences = snapshotPreferences()
        defer { restore(preferences) }

        let registry = ModuleRegistry.shared
        Defaults[.enableTimerFeature] = true
        Defaults[.moduleEnableOverrides] = [id: false]

        registry.register(
            [TakeoverProbeModule.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )
        await registry.bootstrap()

        XCTAssertEqual(registry.states[id], .active, "接管键 true 压过 overrides false")
        XCTAssertNotNil(registry.instance(for: id), "过门的模块照常激活")
        XCTAssertEqual(registry.tabEntries.map(\.id), [id], "激活后进 tab 投影")
    }

    // MARK: - 重同步桥

    /// 上游键被别处（上游设置页）改动 → 注册表状态跟上（docs/20 §做法 机制二）。
    func testBridgeResyncsStateWhenUpstreamKeyChanges() async {
        let preferences = snapshotPreferences()
        defer { restore(preferences) }

        let registry = ModuleRegistry.shared
        Defaults[.enableTimerFeature] = true
        registry.register(
            [TakeoverProbeModule.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )
        await registry.bootstrap()
        XCTAssertEqual(registry.states[id], .active, "前置：接管键 true → 活跃")

        KernelBootstrap.startTakeoverBridge(registry: registry)
        XCTAssertEqual(KernelBootstrap.takeoverSubscriptionCount, 1, "前置：桥为该模块建了一条订阅")

        Defaults[.enableTimerFeature] = false   // 上游设置页的那一次写

        let resynced = await waitUntil { registry.states[id] == .disabled }
        XCTAssertTrue(resynced, "上游键改 false 后注册表状态应跟上（桥的回调不是同帧）")
        XCTAssertNil(registry.instance(for: id), "重同步置关必须摘掉实例")
        XCTAssertEqual(deactivations(id), 1, "置关真的走到了模块的 deactivate()（不是只改状态 / 只摘实例）")
        XCTAssertTrue(registry.tabEntries.isEmpty, "tab 投影随之消失")
    }

    /// `failed` 是终态：桥把键置 true 也不把它救活（D-13 / 06 §3.3 硬性规则 1）。
    func testBridgeDoesNotReviveFailedModule() async {
        let preferences = snapshotPreferences()
        defer { restore(preferences) }

        let registry = ModuleRegistry.shared
        Defaults[.enableTimerFeature] = false
        registry.register(
            [TakeoverFailingProbeModule.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )
        await registry.bootstrap()
        XCTAssertEqual(registry.states[failingID], .disabled, "前置：键 false → 不激活")

        // 直接把开关打开：`setEnabled` 不读门（门只在注册那一刻判过），因此这里能造出 `.failed`。
        let failed = await registry.setEnabled(true, for: failingID)
        guard case .failed = failed else {
            return XCTFail("前置失败：期望 .failed，实到 \(failed)")
        }
        XCTAssertEqual(activations(failingID), 1, "前置：activate() 抛错一次")

        KernelBootstrap.startTakeoverBridge(registry: registry)
        Defaults[.enableTimerFeature] = true   // 桥上的一次置开

        // 「本不该发生」的断言：把在飞的回合跑完再看结果。
        await yieldTurns()

        guard case .failed? = registry.states[failingID] else {
            return XCTFail("failed 不得被桥救活，实到 \(String(describing: registry.states[failingID]))")
        }
        XCTAssertEqual(activations(failingID), 1, "终态不重试：activate() 全程只被调用一次")
        XCTAssertNil(registry.instance(for: failingID))
    }

    // MARK: - isTabVisible 契约

    /// 缺省 true 进 tab 列表；重写成 false 的模块**不进**，而它仍是 `.active`（可见性 ≠ 启用）。
    func testTabVisibilityHookFiltersTabEntries() async {
        let preferences = snapshotPreferences()
        defer { restore(preferences) }

        let registry = ModuleRegistry.shared
        Defaults[.enableTimerFeature] = true
        registry.register(
            [TakeoverProbeModule.self, TakeoverHiddenTabProbeModule.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )
        await registry.bootstrap()

        XCTAssertEqual(registry.states[id], .active)
        XCTAssertEqual(registry.states[hiddenTabID], .active, "可见性与启用是两件事：模块照常激活")
        XCTAssertEqual(registry.tabEntries.map(\.id), [id], "缺省 true 进投影，重写 false 的不进")
        XCTAssertNotNil(registry.instance(for: hiddenTabID), "不进 tab 不影响实例入驻")
        XCTAssertTrue(registry.homeEntries.isEmpty, "两者都只声明 expanded，home 投影不受影响")
    }

    // MARK: - 写路径与回弹

    /// 写路径：接管模块写上游键、非接管写 overrides——各写各的，互不越界（docs/20 §接口与数据形状 3）。
    func testWriteGoesToTakeoverKeyOrOverrides() {
        let preferences = snapshotPreferences()
        defer { restore(preferences) }

        Defaults[.enableTimerFeature] = false
        Defaults.reset(Defaults.Keys.moduleEnableOverrides.name)   // 干净起点：连 overrides 键都不存在

        ModuleEnablementWrite.write(true, for: id, takeoverKey: .enableTimerFeature)

        XCTAssertTrue(Defaults[.enableTimerFeature], "接管模块：开关就是上游那个键")
        XCTAssertNil(Defaults[.moduleEnableOverrides][id], "接管模块不得同时写 overrides")
        XCTAssertNil(
            persistedValue(of: Defaults.Keys.moduleEnableOverrides.name),
            "接管模块的写路径连 overrides 键都不该写出来"
        )

        // 非接管：只写 overrides，上游键一个字节都不动
        Defaults[.enableTimerFeature] = false
        ModuleEnablementWrite.write(true, for: id, takeoverKey: nil)

        XCTAssertFalse(Defaults[.enableTimerFeature], "非接管模块的写路径不得碰上游键")
        XCTAssertEqual(Defaults[.moduleEnableOverrides][id], true, "非接管模块写的是 overrides")
    }

    /// 回弹策略（D-13）：接管模块什么都不写、非接管写回 false。
    func testRollbackWritesNothingForTakeoverModules() {
        XCTAssertNil(
            ModuleEnablementRollback.preferenceToWrite(takeoverKey: .enableTimerFeature),
            "接管模块的偏好就是上游总开关：回弹等于因为激活失败把用户的功能关了"
        )
        XCTAssertEqual(
            ModuleEnablementRollback.preferenceToWrite(takeoverKey: nil),
            false,
            "非接管模块：把用户的开关拨回去"
        )
    }

    // MARK: - 桥幂等（进入时先清空）

    /// 它钉的是 `startTakeoverBridge` **进入时先清空**（`takeoverSubscriptions.removeAll()`）这一条：
    /// 清掉的是**本用例上一段自己起的桥**，与其它用例在订阅表里留下的残留无关——跑单条也成立。
    ///
    /// 两段刻意用**不同 id**：订阅表是 `[String: AnyCancellable]`，同一个 id 重复建桥是「替换」——
    /// 第二段若还注册第一段的 id，缺 `removeAll()` 也只有 2 条，区分不出「替换」与「先清空」。
    ///
    /// 本用例**不写**任何真实偏好：门只读（`Defaults[takeoverKey]`），判定结果与断言无关。
    func testStartTakeoverBridgeClearsOnEntryAndSubscribesOnlyTakeoverModules() async {
        let registry = ModuleRegistry.shared
        // ① 两个接管模块 + 一个非接管基类：只有接管模块建订阅。
        registry.register(
            [TakeoverProbeModule.self, TakeoverHiddenTabProbeModule.self, TakeoverProbeBase.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )
        XCTAssertEqual(registry.manifests.count, 3, "前置：三个夹具都已注册")
        XCTAssertNil(registry.takeoverEnableKey(for: baseID), "前置：基类是**非接管**模块（缺省 nil）")

        KernelBootstrap.startTakeoverBridge(registry: registry)
        XCTAssertEqual(KernelBootstrap.takeoverSubscriptionCount, 2, "只订阅两个接管模块")

        // ② 注册表清空 → 只注册一个**新 id** 的接管模块再起桥：进入时先清空的话订阅表里只剩这 1 条；
        //    缺 `removeAll()` 时上一段那 2 条仍挂在同一个字典上（新 id 不覆盖旧键），条数必然 > 1
        //    （本机单跑实测 4 = 本用例那 2 条 + 宿主进程启动时既有的计时器 1 条）。
        await registry.deactivateAll()
        XCTAssertEqual(registry.manifests.count, 0, "前置：注册表已清空（订阅表不随注册表收敛）")
        registry.register(
            [TakeoverWideBlockProbeModule.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )
        XCTAssertEqual(
            registry.takeoverEnableKey(for: wideBlockID)?.name,
            Defaults.Keys.enableTimerFeature.name,
            "前置：第二段这个新 id 也是接管模块"
        )

        KernelBootstrap.startTakeoverBridge(registry: registry)
        XCTAssertEqual(
            KernelBootstrap.takeoverSubscriptionCount,
            1,
            "重复起桥不得翻倍（进入先 removeAll）：上一段那 2 条订阅必须消失，实到 1"
        )
    }

    // MARK: - 块宽钩子

    /// 块宽钩子：声明的模块取值一致、未声明为 nil、未注册 id 为 nil（docs/20 §做法 机制一）。
    ///
    /// 本用例**不写**任何真实偏好（门只读）。
    func testHomeBlockWidthHookReadsDeclaredValueOrNil() {
        let registry = ModuleRegistry.shared
        registry.register(
            [TakeoverWideBlockProbeModule.self, TakeoverProbeModule.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )

        XCTAssertEqual(
            registry.homeBlockWidth(for: wideBlockID),
            ModuleHomeBlockWidth(min: 260, ideal: 340),
            "声明的宽度原样取给宿主（夹具样本档 260/340；真模块的档位在各自的用例里）"
        )
        XCTAssertNil(registry.homeBlockWidth(for: id), "未声明 → nil（宿主用统一值 180/240）")
        XCTAssertNil(registry.homeBlockWidth(for: ghostID), "未注册的 id → nil")
        XCTAssertNil(registry.takeoverEnableKey(for: ghostID), "未注册的 id 同样没有接管键")
        XCTAssertEqual(
            registry.takeoverEnableKey(for: id)?.name,
            Defaults.Keys.enableTimerFeature.name,
            "接管键按模块取，取到的是形参给的那一个键"
        )
    }

    // MARK: - 计时器接管模块（T2）

    /// docs/20 §接口与数据形状 5 的 timer 行：**这个真模块**的 manifest 声明值逐条对齐。
    ///
    /// 三条钩子与启用门的**行为**（真源压过 overrides / 可见性过滤 / 重同步）已由本文件上半段的
    /// 假模块覆盖，这里钉的是真模块的声明：`surfaces` 不含 `.compact`（D-09）、tab 落模块段
    /// （`defaultPlacement == nil`）、`config` 只登记上游三键（D-03）。
    func testTimerModuleManifestMatchesTakeoverContract() throws {
        let manifest = TimerModule.manifest
        XCTAssertNoThrow(try manifest.validate())

        XCTAssertEqual(manifest.id, TimerModule.moduleID, "moduleID 与 manifest.id 必须是同一份字面量")
        XCTAssertEqual(manifest.id, "com.cmeng.gourd.timer")
        XCTAssertEqual(manifest.shortID, "timer")
        XCTAssertEqual(manifest.name.key, "module.timer.name")
        XCTAssertEqual(manifest.summary?.key, "module.timer.summary")
        XCTAssertEqual(manifest.icon, IconSpec(type: "symbol", name: "timer"))
        XCTAssertEqual(manifest.kind, "builtin")
        XCTAssertEqual(manifest.surfaces, [.expanded], "只声明 expanded（D-09：本批不声明任何 compact）")
        XCTAssertFalse(manifest.surfaces.contains(.compact), "接管模块不占折叠槽位")
        XCTAssertNil(manifest.defaultPlacement, "tab 落模块段（无 placement → Int.max，docs/20 §已知限制 2）")
        XCTAssertEqual(manifest.defaultEnabled, true, "= 上游 `enableTimerFeature` 的默认值（接管键读不到时才不生效）")
        XCTAssertTrue(manifest.permissions.isEmpty, "本批只搬渲染归属与开关真源：零新增能力请求")

        let properties = try XCTUnwrap(manifest.config?.properties)
        XCTAssertEqual(properties.count, 3, "config 只登记上游三键，不新发明键（D-03）")
        XCTAssertEqual(properties["enableTimerFeature"]?.type, "boolean")
        XCTAssertEqual(properties["enableTimerFeature"]?.default, ConfigValue.bool(true))
        XCTAssertEqual(properties["timerDisplayMode"]?.type, "enum")
        XCTAssertEqual(properties["timerDisplayMode"]?.values, ["tab", "popover"])
        XCTAssertEqual(properties["timerDisplayMode"]?.default, ConfigValue.string("tab"))
        XCTAssertEqual(properties["timerPresets"]?.type, "list")
        XCTAssertEqual(properties["timerPresets"]?.itemType, "string")
        XCTAssertNil(properties["timerPresets"]?.default, "预设清单不给 default（结构比 06 §5.3 标量复杂，只登记键名）")

        // 两条取值型钩子：真源 = 上游总开关；本模块不接首页块 → 不声明块宽
        XCTAssertEqual(TimerModule.takeoverEnableKey?.name, Defaults.Keys.enableTimerFeature.name)
        XCTAssertNil(TimerModule.homeBlockWidth, "只接展开 tab（宿主统一宽度）")

        // 字面量 manifest 也能走 JSON（与宿主读 descriptor 同一条路）
        XCTAssertEqual(try ModuleManifest.decode(from: try JSONEncoder().encode(manifest)), manifest)
    }

    /// 计数回归（docs/20 §做法 机制五 / §验收标准 1）：上游那条「功能开着 + 显示方式选 tab」的 `+1`
    /// 从 `enabledStandardTabCount()` 删掉后，计时器对它的贡献必须仍是 **1 / 0 / 0**——
    /// 这一数是刘海最小宽度的唯一输入，错一位就是宽度回归。
    ///
    /// 三点刻意写死（改动前先读）：
    /// 1. **自己置全夹具**：`enabledStandardTabCount()` 读到的每条上游键都压到 false——
    ///    那一段读的是**测试域**（Debug 域 `com.cmeng.gourd.dev`，不是 Release 域 `com.cmeng.gourd`）
    ///    盘上的值，不能当常数用：这一域写这段注释时的读数是 `enableTimerFeature = 0`、
    ///    `timerDisplayMode` **缺键**（`defaults read com.cmeng.gourd.dev <键>`；缺键走 Defaults 默认
    ///    `.tab`）——不置夹具的话启用真源那条是 0：模块不激活、不进 tab 投影，① 期望 1 实到 0，直接红；
    /// 2. **注册走真门**（`KernelBootstrap.enablementGate`）：接管键是启用的唯一真源——
    ///    旧门（`manifests[$0]?.defaultEnabled` 或用户 overrides）根本读不到上游键；
    /// 3. 三种组合各自**重新注册**（`deactivateAll` → `register` → `bootstrap`）：门只在注册那一刻
    ///    判过（`setEnabled` 不重读门），重注册走的正是应用启动时 `bootstrap()` 的那条路；
    ///    运行期改键的路径（重同步桥）由 T1 的用例覆盖。
    func testTimerModuleKeepsEnabledStandardTabCountParity() async {
        // 夹具键：`enabledStandardTabCount()` 的上游输入穷举（Home / Shelf / Notes-Clipboard /
        // Terminal 四条，加计时器的启用与显示方式两条）。**Stats 那一条已随 p3-widgets / T2 删除**
        // （统计改首页块，不再贡献 tab 数——本文件 `testStatsFeatureAddsNoStandardTabCount` 钉住它），
        // 这里仍把它一起压假只是沿用「所有 tab 输入置假」的夹具形态，不影响结论。
        let upstreamKeys = [
            Defaults.Keys.showStandardMediaControls.name,
            Defaults.Keys.showCalendar.name,
            Defaults.Keys.showMirror.name,
            Defaults.Keys.dynamicShelf.name,
            Defaults.Keys.enableStatsFeature.name,
            Defaults.Keys.enableNotes.name,
            Defaults.Keys.enableClipboardManager.name,
            Defaults.Keys.enableTerminalFeature.name,
        ]
        let keys = upstreamKeys + [
            Defaults.Keys.enableTimerFeature.name,
            Defaults.Keys.timerDisplayMode.name,
        ]
        let originals = snapshotValues(of: keys)
        defer { restoreValues(originals, for: keys) }

        Defaults[.showStandardMediaControls] = false
        Defaults[.showCalendar] = false
        Defaults[.showMirror] = false
        Defaults[.dynamicShelf] = false
        Defaults[.enableStatsFeature] = false
        Defaults[.enableNotes] = false
        Defaults[.enableClipboardManager] = false
        Defaults[.enableTerminalFeature] = false

        let registry = ModuleRegistry.shared
        let timerID = TimerModule.moduleID

        // ① 功能开 + 显示方式选 tab → 贡献 1（与上游分支删掉之前同一结果）
        Defaults[.enableTimerFeature] = true
        Defaults[.timerDisplayMode] = .tab
        registry.register([TimerModule.self], enabled: KernelBootstrap.enablementGate(registry: registry))
        await registry.bootstrap()

        XCTAssertEqual(registry.states[timerID], .active, "接管键 true → 启用门放行")
        XCTAssertTrue(TimerModule.isTabVisible(), "显示方式选 tab → 此刻该在 tab 列表里")
        XCTAssertEqual(registry.tabEntries.map(\.id), [timerID], "接管的 tab 由模块投影产出（上游分支已删）")
        XCTAssertEqual(enabledStandardTabCount(), 1, "① 计时器的贡献 = 1")

        // ② 功能开 + 显示方式改选 popover → 贡献 0（模块仍 active：可见性 ≠ 启用）
        Defaults[.timerDisplayMode] = .popover
        XCTAssertEqual(registry.states[timerID], .active, "可见性只在投影层过滤，不改模块状态")
        XCTAssertFalse(TimerModule.isTabVisible(), "显示方式不是 tab → 不该在 tab 列表里")
        XCTAssertTrue(registry.tabEntries.isEmpty, "投影随之消失")
        XCTAssertEqual(enabledStandardTabCount(), 0, "② 计时器的贡献 = 0")

        // ③ 功能关 → 贡献 0（门直接读上游键 → 模块不激活）
        Defaults[.timerDisplayMode] = .tab
        Defaults[.enableTimerFeature] = false
        await registry.deactivateAll()
        registry.register([TimerModule.self], enabled: KernelBootstrap.enablementGate(registry: registry))
        await registry.bootstrap()

        XCTAssertEqual(registry.states[timerID], .disabled, "接管键 false → 启用门不放行（不看 overrides / manifest 默认）")
        XCTAssertEqual(enabledStandardTabCount(), 0, "③ 计时器的贡献 = 0")
    }

    // MARK: - 计时器页判据：第二入口与 250pt 高度档（T3）

    /// `isTimerSurfaceSelected()` 三档：① `.timer` → true（老路径，枚举成员按机制六保留）；
    /// ② `.module` + `TimerModule.moduleID` → true（今天唯一的生产形态）；③ `.module` + 别的 id
    /// **与** `.home` → false（判据两段是「且」，且第二段要比对 id）。
    ///
    /// 四项刻意写死（改动前先读）：
    /// 1. **判据是纯读**：三档只调 `isTimerSurfaceSelected()`，不写 `Defaults` 的计时器键、
    ///    不注册模块——`.timer` 与 `.module` 都是枚举成员，判定与注册表 / 上游开关无关；
    /// 2. **读写的是共享协调器**（`DynamicIslandViewCoordinator.shared`，`private init` 只能取单例）：
    ///    它同时被宿主 UI 观察，用例留下的 `.module` + 计时器 id 会变成别的用例的初始状态，
    ///    因此进入时记下 `currentView` / `selectedModuleID`、`defer` 逐字还原（T3 派发片段的要求）；
    /// 3. **`enableMinimalisticUI` 必须置假**：`currentView` 的 `didSet` 在极简 UI 开着时把非 `.home`
    ///    的选中**强制打回 `.home`**（`DynamicIslandViewCoordinator.currentView`），于是 `selectModule`
    ///    只剩 `selectedModuleID` 生效、第 ①② 档必红——这是「共享协调器 + 盘上偏好」这一对的固有坑
    ///    （同款处理见 `ModuleKernelTests.testSelectModuleSetsSelectedIDAndView`）。夹具与文件内其它键
    ///    同款：持久域原值 → 置定值 → `defer` 逐字还原（原本有键写回原值、原本没键删键）；
    /// 4. **三档各一条用例**：判据的每一段都要有能单独变红的断言（变异验证见 T3 报告 §3）。
    ///
    /// 本文件的三档用例**不写**任何计时器键（第 1 条），因此只做「协调器字段 + 极简 UI 开关」的卫生。
    func testTimerSurfaceSelectedOnLegacyTimerView() {
        let coordinator = DynamicIslandViewCoordinator.shared
        let snapshot = snapshotTimerSurface()
        defer { restoreTimerSurface(snapshot) }
        Defaults[.enableMinimalisticUI] = false

        coordinator.selectedModuleID = nil
        coordinator.currentView = .timer

        XCTAssertTrue(coordinator.isTimerSurfaceSelected(), "① 老路径 `.timer` 仍是计时器页")

        // 判据第一段短路：`.timer` 档下 `selectedModuleID` 是谁都不影响结论
        coordinator.selectedModuleID = id
        XCTAssertTrue(coordinator.isTimerSurfaceSelected(), "① `.timer` 档不依赖 `selectedModuleID`")
    }

    /// ② **模块 tab + 计时器 id → true**：这是接管后唯一的生产形态——悬浮聚焦、点预设与
    /// `startCustomTimer` 三条路径都改走 `selectModule(TimerModule.moduleID)`（docs/20 §做法 机制六），
    /// 判据不认它就会出现「内容在、tab 条上没有任何 tab 高亮」且高度回落到默认档（D-11）。
    func testTimerSurfaceSelectedOnTimerModuleTab() {
        let coordinator = DynamicIslandViewCoordinator.shared
        let snapshot = snapshotTimerSurface()
        defer { restoreTimerSurface(snapshot) }
        Defaults[.enableMinimalisticUI] = false

        coordinator.selectModule(TimerModule.moduleID)

        XCTAssertEqual(coordinator.selectedModuleID, TimerModule.moduleID, "前置：selectModule 同时记下模块 id")
        XCTAssertEqual(coordinator.currentView, .module, "前置：selectModule 切到模块视图")
        XCTAssertTrue(coordinator.isTimerSurfaceSelected(), "② 模块 tab + 计时器 id = 计时器页")
    }

    /// ③ **别的模块 tab 与首页都不是计时器页**：第二段要比对模块 id（同一个 `.module` 下可以有多个
    /// 模块 tab，与 `TabSelectionView.isSelected` 同一口径）；`.home` 即使 `selectedModuleID`
    /// 还留着计时器 id 也不是（两段是「且」不是「或」）。
    func testTimerSurfaceSelectedIsFalseForOtherModuleTabAndHome() {
        let coordinator = DynamicIslandViewCoordinator.shared
        let snapshot = snapshotTimerSurface()
        defer { restoreTimerSurface(snapshot) }
        Defaults[.enableMinimalisticUI] = false

        coordinator.selectModule(id)
        XCTAssertFalse(coordinator.isTimerSurfaceSelected(), "③ `.module` + 别的模块 id 不是计时器页")

        // 残留「上次选中的是计时器」也不能算：`.home` 档下判据第一段就不成立
        coordinator.selectedModuleID = TimerModule.moduleID
        coordinator.currentView = .home
        XCTAssertEqual(coordinator.selectedModuleID, TimerModule.moduleID, "前置：首页上仍挂着计时器 id（残留选择）")
        XCTAssertFalse(coordinator.isTimerSurfaceSelected(), "③ `.home` 不是计时器页")
    }

    // MARK: - 镜子接管模块（T4）

    /// docs/20 §接口与数据形状 5 的 mirror 行：**这个真模块**的 manifest 声明值逐条对齐。
    ///
    /// 与 `testTimerModuleManifestMatchesTakeoverContract` 同款：三条钩子的**行为**（真源压过
    /// overrides / 可见性过滤 / 重同步）由本文件上半段的假模块覆盖，这里钉的是真模块的声明——
    /// `surfaces == [.home]`（不声明 tab、不占折叠槽位）、`order 2`（= 被接管的内置块的默认序号，
    /// 接管前后首页顺序一致）、真源键 `showMirror`、块宽 140/140（T3 起方形，见下面的用例）。
    ///
    /// 本用例**不写**任何真实偏好（只读钩子与常量）。
    func testMirrorModuleManifestMatchesTakeoverContract() throws {
        let manifest = MirrorModule.manifest
        XCTAssertNoThrow(try manifest.validate())

        XCTAssertEqual(manifest.id, MirrorModule.moduleID, "moduleID 与 manifest.id 必须是同一份字面量")
        XCTAssertEqual(manifest.id, "com.cmeng.gourd.mirror")
        XCTAssertEqual(manifest.shortID, "mirror")
        XCTAssertEqual(manifest.name.key, "module.mirror.name")
        XCTAssertEqual(manifest.summary?.key, "module.mirror.summary")
        XCTAssertEqual(manifest.icon, IconSpec(type: "symbol", name: "camera"))
        XCTAssertEqual(manifest.kind, "builtin")
        XCTAssertEqual(manifest.surfaces, [.home], "只声明首页块（D-09：本批不声明任何 compact）")
        XCTAssertFalse(manifest.surfaces.contains(.expanded), "不声明 expanded → 不进 tab 投影")
        XCTAssertFalse(manifest.surfaces.contains(.compact), "接管模块不占折叠槽位")
        XCTAssertEqual(
            manifest.defaultPlacement,
            Placement(slot: nil, order: 2),
            "slot 只在含 compact 时有意义；order 2 = 被它取代的内置镜子块的默认序号"
        )
        XCTAssertEqual(
            manifest.defaultPlacement?.order,
            HomeBlockOrdering.BuiltinBlock.mirror.defaultOrder,
            "接管前后的默认序号必须相同（否则未调过顺序的用户会看到块跳位）"
        )
        XCTAssertEqual(manifest.defaultEnabled, false, "= 上游 `showMirror` 的默认值（接管键读不到时才不生效）")
        XCTAssertTrue(manifest.permissions.isEmpty, "本批只搬渲染归属与开关真源：零新增能力请求（含摄像头 TCC）")

        let properties = try XCTUnwrap(manifest.config?.properties)
        XCTAssertEqual(properties.count, 3, "config 只登记上游三键，不新发明键（D-03）")
        XCTAssertEqual(properties["showMirror"]?.type, "boolean")
        XCTAssertEqual(properties["showMirror"]?.default, ConfigValue.bool(false))
        XCTAssertEqual(properties["mirrorShape"]?.type, "enum")
        XCTAssertEqual(properties["mirrorShape"]?.values, ["Rectangular", "Circular"])
        XCTAssertEqual(properties["mirrorShape"]?.default, ConfigValue.string("Rectangular"))
        XCTAssertEqual(properties["selectedCameraID"]?.type, "string")
        XCTAssertEqual(properties["selectedCameraID"]?.default, ConfigValue.string(""), "空串 = 跟随第一台（上游键的默认值）")
        XCTAssertNil(properties["selectedCameraID"]?.values, "设备 id 是运行期发现的值，不列可选值")

        // 两条取值型钩子：真源 = 上游总开关；块宽 = 方形边长（T3 起收敛，见下一条用例的同源断言）
        XCTAssertEqual(MirrorModule.takeoverEnableKey?.name, Defaults.Keys.showMirror.name)
        XCTAssertEqual(
            MirrorModule.homeBlockWidth,
            ModuleHomeBlockWidth(min: 140, ideal: 140),
            "T3 起收敛成方形 140/140（不再是 140/160 的窄档——理想宽到不了，圆仍是 140，块里留 20pt 空档）"
        )

        // 字面量 manifest 也能走 JSON（与宿主读 descriptor 同一条路）
        XCTAssertEqual(try ModuleManifest.decode(from: try JSONEncoder().encode(manifest)), manifest)
    }

    /// 镜子块的**存在性判据**（docs/20 §做法 机制一末段）：`showMirror && cameraAvailable`——
    /// 两段是「且」，且**不含展开态**（`.home` 块只在展开面板首页渲染，旧内置块重复判一次
    /// `notchState == .open` 的写法本批一并删除）。
    ///
    /// 本用例**不写**任何真实偏好（判据是纯函数，两个入参都是形参）。
    func testMirrorVisibilityPredicate() {
        XCTAssertTrue(
            MirrorModule.isVisible(showMirror: true, cameraAvailable: true),
            "功能开 + 有摄像头 → 块在"
        )
        XCTAssertFalse(
            MirrorModule.isVisible(showMirror: true, cameraAvailable: false),
            "有开关但没摄像头 → 块消失（答 .none 不占位，不是画一个空壳）"
        )
        XCTAssertFalse(
            MirrorModule.isVisible(showMirror: false, cameraAvailable: true),
            "摄像头在但功能关着 → 块消失（与接管前的 `showMirror && …` 同序）"
        )
        XCTAssertFalse(
            MirrorModule.isVisible(showMirror: false, cameraAvailable: false),
            "两段都不成立 → 块消失"
        )
    }

    /// 注册表侧的接管查询对**真模块**同样成立（docs/20 §接口与数据形状 2）：`homeBlockWidth(for:)`
    /// 取回 140/140（`HomeStripView` 就靠它让镜子块是方形，且边长与宿主的大块档高同源，T3）、
    /// `takeoverEnableKey(for:)` 取回 `showMirror`（启用真源）。
    ///
    /// 注册走**真门**（`KernelBootstrap.enablementGate`），但**不 bootstrap**：门只读，
    /// 本用例不写任何真实偏好（镜子当前的启用状态与断言无关）。
    func testMirrorModuleHooksReadThroughTheRegistry() {
        let registry = ModuleRegistry.shared
        registry.register(
            [MirrorModule.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )

        XCTAssertEqual(
            registry.homeBlockWidth(for: MirrorModule.moduleID),
            ModuleHomeBlockWidth(min: 140, ideal: 140),
            "镜子块宽度声明经注册表原样取给宿主（140/140：方形，块里不留横向空档）"
        )
        XCTAssertEqual(
            registry.homeBlockWidth(for: MirrorModule.moduleID)?.min,
            HomeFlowView.largeBlockHeight,
            "镜子的方形边长 = 宿主的大块档高（同源：宿主改档高，镜子的声明跟着改）"
        )
        XCTAssertEqual(
            registry.takeoverEnableKey(for: MirrorModule.moduleID)?.name,
            Defaults.Keys.showMirror.name,
            "镜子的启用真源 = 上游 `showMirror` 键"
        )
    }

    // MARK: - 首页块顺序表的历史键映射（T4）

    /// `migratingLegacyIDs` 的四组口径（docs/20 §做法 机制四 / §接口与数据形状 4）：
    /// ① 旧键 → 新 id（新 id 缺席时生效）；② 新键优先（用户在新版里表达过）；③ 两个旧键都映射、
    /// 表里其它键（含不迁移的 `builtin.calendar`）逐字保留；④ 空表 / 无旧键 → 恒等。
    ///
    /// 新 id 一律用 `MirrorModule.moduleID` / 字面量查表：`HomeBlockOrdering` 是纯逻辑文件、
    /// 不认识模块类型（那边写的是字面量），两处一致由本用例钉住——id 任一处漂了这里就红。
    ///
    /// 本用例**不写**任何真实偏好（纯函数，入参是字典）。
    func testMigratingLegacyIDsMapsOnlyWhenNewIDIsAbsent() {
        let mirrorID = MirrorModule.moduleID

        // ① 旧键 → 新 id：老用户排过的位置跟着搬到改名后的块上
        let mapped = HomeBlockOrdering.migratingLegacyIDs(["builtin.mirror": -1])
        XCTAssertEqual(mapped[mirrorID], -1, "builtin.mirror 的值要落到镜子模块 id 上")
        XCTAssertEqual(mapped["builtin.mirror"], -1, "旧键**保留**在返回的表里（别名语义：设置页顺序节只列模块 id，旧键今天没有消费者，盘上那一条只在第一次重排前还在）")

        // ② 新键优先：新 id 已有自己的值 → 旧值不覆盖它
        let newWins = HomeBlockOrdering.migratingLegacyIDs(["builtin.mirror": -1, mirrorID: 3])
        XCTAssertEqual(newWins[mirrorID], 3, "只在新 id 缺席时才搬旧值")
        XCTAssertEqual(newWins["builtin.mirror"], -1, "旧键自身不动（它只是没人再查）")

        // ③ 两个旧键同时映射；非映射键（日历 / 模块 id / 任意键）逐字保留
        let mixed = HomeBlockOrdering.migratingLegacyIDs([
            "builtin.music": 1,
            "builtin.calendar": 0,
            "com.cmeng.gourd.todos": 5,
        ])
        XCTAssertEqual(mixed["com.cmeng.gourd.music"], 1, "builtin.music 同样映射（T5 接管音乐前先就位）")
        XCTAssertEqual(mixed["builtin.calendar"], 0, "日历不迁移（今天已不在任何名单里，迁移它没有接收者）")
        XCTAssertEqual(mixed["com.cmeng.gourd.todos"], 5, "表里的模块 id 逐字保留")
        XCTAssertEqual(mixed.count, 4, "只多出一条（新 id），不清理、不改写旧键")

        // ④ 空表与「没有旧键的表」恒等
        XCTAssertEqual(HomeBlockOrdering.migratingLegacyIDs([:]), [:], "空表 → 空表")
        let untouched = ["com.cmeng.gourd.progress": 2, "com.cmeng.gourd.todos": 0]
        XCTAssertEqual(HomeBlockOrdering.migratingLegacyIDs(untouched), untouched, "没有旧键 → 原样返回")
    }

    /// 映射是 **`sorted(...)` 的第一步**（docs/20 §接口与数据形状 4 末句）：只钉纯函数的话，
    /// 「映射没接上排序」不会红——这条用例整条经 `sorted` 走一遍。
    ///
    /// 输入表用的是**老表**（只有 `builtin.mirror`），名单用的是**接管后的名单**（镜子是模块 id）：
    /// 判据就是「老用户排过镜子 → 重启后镜子仍在最前」。
    ///
    /// 本用例**不写**任何真实偏好（`sorted` 是纯函数，覆盖表是形参）。
    func testSortedAppliesLegacyMigrationBeforeRanking() {
        let mirrorID = MirrorModule.moduleID
        let blocks: [(id: String, order: Int)] = [
            (id: "builtin.music", order: 0),
            (id: mirrorID, order: 2),
            (id: "com.cmeng.gourd.todos", order: 20),
        ]

        let sorted = HomeBlockOrdering.sorted(
            blocks,
            defaultOrder: { $0.order },
            id: { $0.id },
            overrides: ["builtin.mirror": -1]
        ).map(\.id)

        XCTAssertEqual(
            sorted,
            [mirrorID, "builtin.music", "com.cmeng.gourd.todos"],
            "老表里的 builtin.mirror = -1 要把镜子模块块提到最前（映射没接上时它按默认 2 排，会红）"
        )
    }

    // MARK: - 音乐接管模块（T5）

    /// docs/20 §接口与数据形状 5 的 music 行：**这个真模块**的 manifest 声明值逐条对齐。
    ///
    /// 与 `testTimerModuleManifestMatchesTakeoverContract` / `testMirrorModuleManifestMatchesTakeoverContract`
    /// 同款：三条钩子的**行为**（真源压过 overrides / 可用性过滤 / 重同步）由本文件上半段的假模块覆盖，
    /// 这里钉的是真模块的声明——`surfaces == [.home]`（不声明 tab、不占折叠槽位）、`order 0`
    /// （= 被接管的内置音乐块的默认序号，接管前后首页顺序一致）、真源键 `showStandardMediaControls`、
    /// **T3 的三条取值型声明各一条**（块宽 p6-ui-polish / T2 再缩一档）：块宽 200/250、形态
    /// `.compact`（从大块降为紧凑条）、封面默认关（`MusicConfigDefaults.showAlbumArt == false`）。
    ///
    /// `config` 两个键的默认值**取上游键的默认值**（D-03 / docs/20 §已知限制 1：登记值必须等于真源值，
    /// 否则这份登记就是假的）：`playerColorTinting` 与 `useMusicVisualizer` 在上游
    /// （`Constants.swift` 的 `Defaults.Keys`）**都是 `true`**——后者的名字带「可视化」，容易按直觉
    /// 记成默认关，本用例把它钉在真值上。
    ///
    /// 本用例**不写**任何真实偏好（只读钩子与常量），因此没有夹具与还原。
    func testMusicModuleManifestMatchesTakeoverContract() throws {
        let manifest = MusicModule.manifest
        XCTAssertNoThrow(try manifest.validate())

        XCTAssertEqual(manifest.id, MusicModule.moduleID, "moduleID 与 manifest.id 必须是同一份字面量")
        XCTAssertEqual(manifest.id, "com.cmeng.gourd.music")
        XCTAssertEqual(manifest.shortID, "music")
        XCTAssertEqual(manifest.name.key, "module.music.name")
        XCTAssertEqual(manifest.summary?.key, "module.music.summary")
        XCTAssertEqual(manifest.icon, IconSpec(type: "symbol", name: "music.note"))
        XCTAssertEqual(manifest.kind, "builtin")
        XCTAssertEqual(manifest.surfaces, [.home], "只声明首页块（D-09：本批不声明任何 compact）")
        XCTAssertFalse(manifest.surfaces.contains(.expanded), "不声明 expanded → 不进 tab 投影")
        XCTAssertFalse(manifest.surfaces.contains(.compact), "接管模块不占折叠槽位")
        XCTAssertEqual(
            manifest.defaultPlacement,
            Placement(slot: nil, order: 0),
            "slot 只在含 compact 时有意义；order 0 = 被它取代的内置音乐块的默认序号"
        )
        XCTAssertEqual(
            manifest.defaultPlacement?.order,
            HomeBlockOrdering.BuiltinBlock.music.defaultOrder,
            "接管前后的默认序号必须相同（否则未调过顺序的用户会看到块跳位）"
        )
        XCTAssertEqual(
            manifest.defaultEnabled,
            Defaults.Keys.showStandardMediaControls.defaultValue,
            "= 上游 `showStandardMediaControls` 的默认值（接管键读不到时才不生效）"
        )
        XCTAssertEqual(
            manifest.defaultEnabled,
            true,
            "上游这个开关默认是开的（方向也要钉住，避免它被悄悄改成保守值）"
        )
        XCTAssertTrue(manifest.permissions.isEmpty, "本批只搬渲染归属与开关真源：零新增能力请求")

        let properties = try XCTUnwrap(manifest.config?.properties)
        XCTAssertEqual(properties.count, 3, "config = 登记上游两键 + 本模块自己的呈现键 showAlbumArt（D-03 / D-06）")
        XCTAssertEqual(properties["playerColorTinting"]?.type, "boolean")
        XCTAssertEqual(properties["playerColorTinting"]?.default, ConfigValue.bool(true))
        XCTAssertEqual(properties["useMusicVisualizer"]?.type, "boolean")
        XCTAssertEqual(
            properties["useMusicVisualizer"]?.default,
            ConfigValue.bool(Defaults.Keys.useMusicVisualizer.defaultValue),
            "登记值必须等于上游键的默认值（上游为 true——不按「可视化默认关」的直觉填 false）"
        )
        // 本模块**自己的**呈现键（无上游真源可登记）：默认值取自 `MusicConfigDefaults`
        XCTAssertEqual(properties["showAlbumArt"]?.type, "boolean")
        XCTAssertEqual(
            properties["showAlbumArt"]?.default,
            ConfigValue.bool(MusicConfigDefaults.showAlbumArt),
            "默认值必须等于 MusicConfigDefaults.showAlbumArt（读取侧兜底用同一个常量）"
        )
        XCTAssertEqual(
            properties["showAlbumArt"]?.default,
            ConfigValue.bool(false),
            "T3 起默认**不显示**（D-09：用户要的是「可以不显示那个图片」——方向也要钉住，"
                + "防止它被悄悄翻回 true）"
        )

        // 三条取值型声明（T3 成套改；块宽 T2 再缩一档）：真源 = 上游总开关；块宽 200/250；形态紧凑档
        XCTAssertEqual(MusicModule.takeoverEnableKey?.name, Defaults.Keys.showStandardMediaControls.name)
        XCTAssertEqual(
            MusicModule.homeBlockWidth,
            ModuleHomeBlockWidth(min: 200, ideal: 250),
            "T2 起 200/250（T3 是 240/300、更早是 300/420：那两档是配大封面选的；"
                + "200 的下界由封面档装宽度 5×26 + 4×6 + 36 + 6 = 196 + 4pt 余量定，见 "
                + "MusicControlsView.CompactMetrics.albumArtRowInstallWidth）"
        )
        XCTAssertEqual(
            MusicModule.homeFormFactor, .compact,
            "T3 起紧凑档（96 高的一条）——音乐块仍占整行 152 就是这条没落地"
        )

        // 字面量 manifest 也能走 JSON（与宿主读 descriptor 同一条路）
        XCTAssertEqual(try ModuleManifest.decode(from: try JSONEncoder().encode(manifest)), manifest)
    }

    /// 音乐块的**存在性判据**（docs/20 §做法 机制一末段 / §接口与数据形状 5 的 music 行）：
    /// `showStandardMediaControls && (!autoHideInactiveNotchMediaPlayer || hasActiveSession)`
    /// ——表达式**逐字沿用**改动前的 `HomeStripView.shouldShowMusicPlayer`，且**不含展开态**。
    ///
    /// 四组：两段各自都能单独把结论翻成 false（总开关、运行期条件），第三组单独证明**第二段是「或」**
    /// （关掉「无会话即隐藏」后没有会话也该显示——这正是「显示占位元数据」那一档的语义）。
    ///
    /// 本用例**不写**任何真实偏好（判据是纯函数，三个入参都是形参）。
    func testMusicVisibilityPredicate() {
        XCTAssertTrue(
            MusicModule.isVisible(showStandardMediaControls: true, autoHideInactive: true, hasActiveSession: true),
            "总开关开 + 无会话即隐藏 + 真有会话 → 块在"
        )
        XCTAssertFalse(
            MusicModule.isVisible(showStandardMediaControls: true, autoHideInactive: true, hasActiveSession: false),
            "总开关开但没有会话（且选了「无会话即隐藏」）→ 块消失（答 .none 不占位）"
        )
        XCTAssertTrue(
            MusicModule.isVisible(showStandardMediaControls: true, autoHideInactive: false, hasActiveSession: false),
            "关掉「无会话即隐藏」后没有会话也显示（第二段是「或」：显示占位元数据那一档）"
        )
        XCTAssertFalse(
            MusicModule.isVisible(showStandardMediaControls: false, autoHideInactive: false, hasActiveSession: true),
            "总开关关着 → 会话在放也不显示（第一段是「且」的前置，与接管前的判据同序）"
        )
    }

    /// **封面开关的解析**（`MusicModule.showsAlbumArt(from:)`，docs/23-home-fit.md §做法 机制五 / D-06）：
    /// 三档——用户覆盖 `false` 读到 false、覆盖 `true` 读到 true（T3 起这才是「画 40pt 小封面」那一档）、
    /// 缺键（用户没写过，或 schema 里根本没有这个键）回落 `MusicConfigDefaults.showAlbumArt`
    /// （**T3 起 = 不画**）。
    ///
    /// 假体是内存 `RecordingConfigHandle`（只落自己的字典，**不碰**开发机真实的
    /// `com.cmeng.gourd.module.music` 域）——因此本用例没有偏好夹具、也没有还原动作。
    ///
    /// 本用例钉的是**读取侧**（config → 布尔量）；「布尔量 → 块内画不画封面」那一段是 SwiftUI
    /// 视图分档，单测里断言不到（视图是 `private`，也不该为测试放开），只能人工验收
    /// （T3 的截图：`.workflow/p5-home-blocks/evidence/t3-music-{bar,cover}.png`）。
    func testMusicShowsAlbumArtResolution() {
        let config = RecordingConfigHandle(schema: ["showAlbumArt"])
        XCTAssertFalse(MusicModule.showsAlbumArt(from: config), "用户没写过这个键 → 回落默认档：不画封面（T3 起）")

        XCTAssertTrue(config.set("showAlbumArt", to: false), "前置：覆盖值写进去了（键在 schema 内）")
        XCTAssertFalse(MusicModule.showsAlbumArt(from: config), "用户覆盖 false → 不画封面（默认档，显式写死也一样）")

        XCTAssertTrue(config.set("showAlbumArt", to: true))
        XCTAssertTrue(MusicModule.showsAlbumArt(from: config), "用户覆盖 true → 画封面（这一档现在是 40pt 小图）")

        XCTAssertFalse(
            MusicModule.showsAlbumArt(from: RecordingConfigHandle(schema: [])),
            "schema 里没有这个键（get 给 nil）→ 同一档回落：不画"
        )
    }

    // MARK: - 组件页的模块配置编辑口（P3 冻结批次 / T7：允许清单）

    /// **允许清单对生产事实**（docs/24-release-freeze.md §做法 机制四 / §验收标准 4）：迭代
    /// `ModuleSettingsSection.configControls` **这张生产表本身**（不是测试另抄的键表——同
    /// `effectKeysByModuleID` 口径），逐条断言：
    ///
    /// ① 模块 id 是**已注册模块**的 id（模块改名 / 表里 id 写错 → 红）；
    /// ② config 键在**那个模块 manifest 的 `config.properties` 里**（键名写错一个字 → 红；
    ///    这正是「拨得动、值不生效」那个静默故障的判据——《ManifestConfigHandle.set` 对
    ///    schema 之外的键返回 false、不落盘）；
    /// ③ **类型与 manifest 声明一致**（`.boolean` ↔ `boolean`、`.integer` ↔ `integer`、
    ///    `.number` ↔ `number`、`.string` ↔ `string`）：类型写错就是「写进去的类型模块读不出来」
    ///    （JSON 的 `30.0` 解不进 `Int`）；
    /// ④ 文案 key 在宿主 bundle 的 zh-Hans 里**解析得出来**（没进 catalog → 一行没有标签的控件）；
    /// ⑤ 表里 **(模块 id, 键) 不重复**（重复 = 两个控件写同一个键，是谁在生效说不清）。
    ///
    /// 另把**十一条清单项逐条钉死**（模块 id + 键名），因为「清单少了一条」在 ①~⑤ 下是**全绿**的
    /// ——少一条只是「那个键没入口」，不违反任何一条断言（§已知限制 1 点名接受：清单是滞后的，
    /// 没有自动发现机制；这里用一条显式名单把它钉住，去掉任意一条即红）。
    ///（p5-home-blocks / T2 从七条加到**八条**：进度卡的 `visibleScopes` 多选；
    ///  p7 / T3 从八条加到**十一条**：工作日统计的 `workStart` / `workEnd` / `workdays`。）
    ///
    /// 注册用 `enabled: { _ in true }`（不读任何偏好键、不落状态）、**不调** `bootstrap()`：
    /// 本用例只看 manifest 与文案，不激活任何模块。
    func testConfigControlAllowlistMatchesManifestsAndCatalog() throws {
        let controls = ModuleSettingsSection.configControls

        // ⑤ 不重复
        XCTAssertEqual(
            Set(controls.map(\.id)).count,
            controls.count,
            "允许清单里出现了重复的 (模块 id, 键)：两个控件写同一个键，谁生效说不清"
        )

        // ⑤′ 逐条钉死（去掉 / 改掉任意一条即红）
        XCTAssertEqual(
            controls.map(\.id),
            [
                "com.cmeng.gourd.music.showAlbumArt",
                "com.cmeng.gourd.launcher.iconSize",
                "com.cmeng.gourd.launcher.density",
                "com.cmeng.gourd.launcher.showRecents",
                "com.cmeng.gourd.shortcuts.showOutput",
                "com.cmeng.gourd.shortcuts.timeoutSeconds",
                "com.cmeng.gourd.frontapp.maxRecentApps",
                "com.cmeng.gourd.progress.visibleScopes",
                "com.cmeng.gourd.progress.workStart",
                "com.cmeng.gourd.progress.workEnd",
                "com.cmeng.gourd.progress.workdays",
            ],
            "十一条 = docs/24 §做法 机制四 点名的七个键 + docs/29 §做法 机制二 的 visibleScopes + docs/31 §接口与数据形状 4 的工作日三键（顺序不动，去/改任意一条都会红）"
        )

        // ①②③ 数据源 = 注册表里的真 manifest（先补注册：`setUp` 的 `deactivateAll()` 把
        // `manifests` 一起清空了，不注册的话 ① 恒红）。
        let registry = ModuleRegistry.shared
        registry.register(KernelBootstrap.builtinModules, enabled: { _ in true })
        let registeredIDs = Set(registry.manifests.keys)
        XCTAssertFalse(registeredIDs.isEmpty, "前置：注册后不能还是空表（setUp 刚清过注册表）")

        for control in controls {
            XCTAssertTrue(
                registeredIDs.contains(control.moduleID),
                "\(control.moduleID) 不是已注册模块的 id（模块改名漏改表 / 表里 id 写错？）"
            )
            let manifest = try XCTUnwrap(registry.manifests[control.moduleID], "① 前置：manifest 应当拿得到")
            let properties = try XCTUnwrap(
                manifest.config?.properties,
                "\(control.moduleID) 的 manifest 没有 config——清单却给它开了控件？"
            )
            let node = try XCTUnwrap(
                properties[control.key],
                "② `\(control.key)` 不在 \(control.moduleID) 的 manifest config.properties 里（键名写错一个字？）"
            )

            // ③ 类型 ↔ kind（五种一一对应；`enum` 不在清单里）
            switch control.kind {
            case .boolean:
                XCTAssertEqual(node.type, "boolean", "\(control.id) 的 kind 是 boolean，manifest 声明的是 \(node.type)")
            case .integer:
                XCTAssertEqual(node.type, "integer", "\(control.id) 的 kind 是 integer，manifest 声明的是 \(node.type)")
            case .number:
                XCTAssertEqual(node.type, "number", "\(control.id) 的 kind 是 number，manifest 声明的是 \(node.type)")
            case .string:
                XCTAssertEqual(node.type, "string", "\(control.id) 的 kind 是 string，manifest 声明的是 \(node.type)")
            case .multiSelect(let options, let titleKeys):
                // 多选 ↔ `list`（itemType string）：写盘的是一个字符串表
                XCTAssertEqual(node.type, "list", "\(control.id) 的 kind 是 multiSelect，manifest 声明的是 \(node.type)")
                XCTAssertEqual(node.itemType, "string", "\(control.id) 的多选项必须是字符串（itemType）")
                XCTAssertFalse(options.isEmpty, "\(control.id) 的多选没有选项——那一行会是空的")
                XCTAssertEqual(
                    Set(options).count,
                    options.count,
                    "\(control.id) 的选项有重复值（两个胶囊写同一个字面量）"
                )
                XCTAssertEqual(
                    titleKeys.count,
                    options.count,
                    "\(control.id) 的 options 与 titleKeys 必须一一对应（`multiSelectOptions` 靠它 zip）"
                )
                // **多选必须带「有效值解析」**（T2 审查的 Important）：不给的话卡片会在
                // 「空表 / 全是坏值」上显示「一个都没勾」而模块还在按自己的回落口径画行
                // （同一个键两个真相）。解析函数接的必须是模块那个公开纯函数。
                XCTAssertNotNil(
                    control.multiSelectEffectiveSet,
                    "\(control.id) 是多选但没给 `multiSelectEffectiveSet`——卡片会在空表/全坏值上与块分叉"
                )
                // 「至少要留一项」那条提示（上锁胶囊的 `.help`）也必须在 catalog 里解析得出：
                // 只对这一条**类型上的**常量断言（视图只用这个 key，不另抄字面量）。
                XCTAssertResolves(ModuleConfigControl.minimumOneHintKey)
                // 选项必须能落盘：manifest 的默认值里出现的取值都得是清单里的选项之一
                // （否则「出厂那几档」在卡上一个都勾不上，用户也改不回默认）
                if case .strings(let declared)? = node.default {
                    for value in declared {
                        XCTAssertTrue(
                            options.contains(value),
                            "\(control.id) 的默认值 `\(value)` 不在选项里——出厂档在卡上勾不上"
                        )
                    }
                }
            }

            // ④ 文案
            XCTAssertResolves(control.titleKey)
            for titleKey in control.multiSelectOptions.map(\.titleKey) {
                XCTAssertResolves(titleKey)
            }
        }
    }

    /// 允许清单的**两处边界**（T7 的失败信号逐条对应）：
    ///
    /// ① **接管模块登记的上游键不进清单**：`enableTimerFeature` / `showMirror` /
    ///    `playerColorTinting` 一类进了清单就是「拨得动、没人读」（`ConfigHandle` 对它们不生效）；
    /// ② **接管模块的卡片必须出那行灰字**（`settings.modules.upstreamManaged` 的判据
    ///    `upstreamManagedKeys(for:takeoverKeyName:)` 非空），非接管模块**一律不出**
    ///    （它们没进清单的键是 `list` / `enum` 那一档：只能改配置文件，不是「由上游设置管理」）。
    ///
    /// 上游键名单**逐条写死**（不拿 manifest 自己算——那样断言会变成同义反复）：这份名单就是
    /// 「`docs/20` §接口与数据形状 5 登记的键」在用例里的镜像，改 manifest 的登记键时这条会红，
    /// 提醒同步。
    ///
    /// 本用例**不写**任何真实偏好（只读表 / manifest / 纯函数），没有夹具与还原。
    func testConfigControlAllowlistExcludesTakeoverUpstreamKeys() throws {
        let controls = ModuleSettingsSection.configControls
        // 三个接管模块的真 manifest + 它们登记的上游键（逐条写死，见文档注释）
        let takeoverModules: [(manifest: ModuleManifest, upstreamKeys: [String])] = [
            (TimerModule.manifest, ["enableTimerFeature", "timerDisplayMode", "timerPresets"]),
            (MirrorModule.manifest, ["showMirror", "mirrorShape", "selectedCameraID"]),
            (MusicModule.manifest, ["playerColorTinting", "useMusicVisualizer"]),
        ]

        // ① 上游键一条都不得进清单
        for (manifest, upstreamKeys) in takeoverModules {
            for key in upstreamKeys {
                XCTAssertFalse(
                    controls.contains { $0.moduleID == manifest.id && $0.key == key },
                    "\(manifest.id) 的 `\(key)` 是**登记的上游键**（真源在上游 Defaults），不得进允许清单"
                )
            }
        }

        // ② 标注判据：接管模块非空（→ 卡片出灰字）、非接管模块恒空
        for (manifest, upstreamKeys) in takeoverModules {
            let managed = ModuleSettingsSection.upstreamManagedKeys(
                for: manifest,
                takeoverKeyName: TimerModule.takeoverEnableKey?.name
            )
            XCTAssertFalse(managed.isEmpty, "\(manifest.id) 是接管模块且有登记的键 → 卡片必须标一行「由上游设置管理」")
            for key in upstreamKeys {
                XCTAssertTrue(
                    managed.contains(key),
                    "\(manifest.id) 的上游键 `\(key)` 应在标注名单里（实到 \(managed)）"
                )
            }
        }

        // 非接管模块：一份键表都没有 → 空表（那一档是「只能改配置文件」，不是「由上游设置管理」）
        for manifest in [LauncherModule.manifest, ShortcutsModule.manifest, FrontAppModule.manifest, CalendarModule.manifest] {
            XCTAssertTrue(
                ModuleSettingsSection.upstreamManagedKeys(for: manifest, takeoverKeyName: nil).isEmpty,
                "\(manifest.id) 不是接管模块 → 那行灰字不得出现"
            )
        }

        // 音乐卡的具体分工：`showAlbumArt` 有控件（不标注），两个登记键留下（标注）
        XCTAssertEqual(
            ModuleSettingsSection.upstreamManagedKeys(for: MusicModule.manifest, takeoverKeyName: "x"),
            ["playerColorTinting", "useMusicVisualizer"],
            "音乐卡：一个键有控件、两个上游键留下——名单与顺序都钉住"
        )

        // 日历卡：`config == nil` → 没有可标注的键（口径 3）
        XCTAssertTrue(
            ModuleSettingsSection.upstreamManagedKeys(for: CalendarModule.manifest, takeoverKeyName: "x").isEmpty,
            "日历卡没有登记任何 config 键 → 不出那行灰字"
        )
    }

    /// 控件**写路径的端到端**（五种类型各走一遍）：写进 `com.cmeng.gourd.module.<shortID>`
    /// （probe 域，**不碰**开发机真实的模块域）→ **模块自己的读侧**立刻看到同一个值
    /// （`MusicModule.showsAlbumArt(from:)` / `LauncherSettings.read(from:)` / `ShortcutsSettings.read(from:)`）。
    ///
    /// 五件事因此被钉住：落盘的**域**（`ModuleContextFactory.configHandle(for:)` 与模块侧是同一个
    /// `ManifestConfigHandle` 实现）、**键名**、值的**类型**（`integer` 键写 `Int`、`number` 键写
    /// `Double`、`multiSelect` 键写 `[String]`——写错模块侧 `get` 就是 nil，本用例红）、
    /// **区间夹取**（越界值写进去读到的是端点）、以及多选独有的**顺序收敛**（恒按选项声明顺序）。
    ///
    /// 假 manifest 的 config 与五个真模块**同一形状**（键名 / 类型 / 默认值都照抄）：
    /// 本用例验的是读写口径，各模块自己的声明由各自的 manifest 用例覆盖。
    /// probe 域用完即删。
    func testConfigControlWritePathsShareTheModuleConfigHandle() throws {
        let suiteName = "com.cmeng.gourd.module.probe-config"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)          // 前置：清掉上次运行留下的覆盖值
        defer { suite.removePersistentDomain(forName: suiteName) }

        let manifest = try ModuleManifest.decode(from: Data(#"""
        {
          "manifestVersion": 1,
          "id": "com.cmeng.gourd.probe-config",
          "name": {"key": "module.probe-config.name"},
          "icon": {"type": "symbol", "name": "square"},
          "version": "1.0.0",
          "apiVersion": "1.0",
          "kind": "builtin",
          "surfaces": ["expanded"],
          "config": {
            "type": "object",
            "properties": {
              "showAlbumArt": {"type": "boolean", "default": true},
              "iconSize": {"type": "number", "default": 44},
              "density": {"type": "number", "default": 1},
              "showRecents": {"type": "boolean", "default": true},
              "showOutput": {"type": "boolean", "default": false},
              "timeoutSeconds": {"type": "integer", "default": 30},
              "maxRecentApps": {"type": "integer", "default": 5},
              "visibleScopes": {"type": "list", "itemType": "string", "default": ["day", "week", "month"]}
            }
          }
        }
        """#.utf8))

        let config = ModuleContextFactory.configHandle(for: manifest)
        let controls = ModuleSettingsSection.configControls

        /// 按 (模块 id, 键) 取一条清单项——数据源是生产表本身。
        func control(_ moduleID: String, _ key: String) throws -> ModuleConfigControl {
            try XCTUnwrap(
                controls.first { $0.moduleID == moduleID && $0.key == key },
                "清单里必须有 \(moduleID).\(key)"
            )
        }

        // ① 缺键 → 回落 manifest 默认值（`ManifestConfigHandle.get` 的既有语义）：
        //    卡上显示的就是模块读到的那一档
        let albumArt = try control(MusicModule.moduleID, "showAlbumArt")
        XCTAssertTrue(albumArt.boolValue(from: config), "缺键回落 manifest 默认（显示封面）")
        XCTAssertEqual(
            albumArt.boolValue(from: config),
            MusicModule.showsAlbumArt(from: config),
            "卡上显示的值与块画不画封面必须是同一个判定"
        )

        let iconSize = try control("com.cmeng.gourd.launcher", "iconSize")
        let density = try control("com.cmeng.gourd.launcher", "density")
        let showRecents = try control("com.cmeng.gourd.launcher", "showRecents")
        let launcherDefaults = LauncherSettings.read(from: config)
        XCTAssertEqual(launcherDefaults, LauncherSettings(
            iconSize: LauncherConfigDefaults.iconSize,
            density: LauncherConfigDefaults.density,
            showRecents: LauncherConfigDefaults.showRecents
        ), "缺键三件都回落各模块自己的常量")
        XCTAssertEqual(iconSize.doubleValue(from: config), launcherDefaults.iconSize)
        XCTAssertEqual(density.doubleValue(from: config), launcherDefaults.density)
        XCTAssertEqual(showRecents.boolValue(from: config), launcherDefaults.showRecents)

        let showOutput = try control(ShortcutsModule.moduleID, "showOutput")
        let timeout = try control(ShortcutsModule.moduleID, "timeoutSeconds")
        XCTAssertEqual(showOutput.boolValue(from: config), ShortcutsConfigDefaults.showOutput)
        XCTAssertEqual(
            Int(timeout.doubleValue(from: config)),
            ShortcutsConfigDefaults.timeoutSeconds,
            "缺键回落 30（`number` 形态读的是 `Double`，整数键也能互通）"
        )

        // ② 拨一个 `number` 值：写盘 → 模块读侧与卡上同时变（**写反了 / 写错类型这里就红**）
        XCTAssertTrue(iconSize.writeDouble(72, config: config), "键在 schema 内 → 落盘成功")
        XCTAssertEqual(iconSize.doubleValue(from: config), 72, "卡上立刻变 72")
        XCTAssertEqual(LauncherSettings.read(from: config).iconSize, 72, "启动台读侧同步：格子按 72pt 算")
        let storedNumber = try XCTUnwrap(suite.data(forKey: iconSize.key), "覆盖值应落在 \(suiteName) 的 \(iconSize.key)")
        XCTAssertEqual(try JSONDecoder().decode(Double.self, from: storedNumber), 72, "落盘类型必须是 Double（模块读 Double）")

        // ③ 区间夹取（读写两侧各一次）：越界值不落进盘、盘上的越界值读出来也是端点
        XCTAssertTrue(iconSize.writeDouble(500, config: config), "越界值照样落盘（夹取在写之前做）")
        XCTAssertEqual(iconSize.doubleValue(from: config), LauncherGridMetrics.iconSizeRange.upperBound, "500 → 夹到 96")
        XCTAssertEqual(
            try JSONDecoder().decode(Double.self, from: try XCTUnwrap(suite.data(forKey: iconSize.key))),
            LauncherGridMetrics.iconSizeRange.upperBound,
            "盘上存的也是夹取后的值（不是「写 500 读 96」）"
        )
        let recentApps = try control(FrontAppModule.moduleID, "maxRecentApps")
        XCTAssertTrue(recentApps.writeInt(99, config: config))
        XCTAssertEqual(recentApps.intValue(from: config), FrontAppHistory.limitRange.upperBound, "99 → 夹到 8")
        XCTAssertEqual(FrontAppHistory.clampedLimit(99), recentApps.intValue(from: config), "与模块侧的夹取同值")

        // ④ 整型键写的是 `Int`（写成 Double 模块侧就读不出来——这正是本用例要堵的静默故障）
        XCTAssertTrue(timeout.writeInt(45, config: config))
        XCTAssertEqual(ShortcutsSettings.read(from: config).timeoutSeconds, 45, "快捷指令读侧同步：限时 45s")
        XCTAssertEqual(
            try JSONDecoder().decode(Int.self, from: try XCTUnwrap(suite.data(forKey: timeout.key))),
            45,
            "落盘类型必须是 Int（模块读 Int；写 Double 会解码失败）"
        )

        // ⑤ 布尔与字符串两条路（字符串型本批清单里没有键，读写口径仍要能过）
        XCTAssertTrue(showOutput.writeBool(true, config: config))
        XCTAssertTrue(ShortcutsSettings.read(from: config).showOutput)
        let stringProbe = ModuleConfigControl(
            moduleID: manifest.id, key: "mirrorShape", kind: .string, titleKey: "settings.modules.upstreamManaged"
        )
        XCTAssertFalse(stringProbe.writeString("circle", config: config), "probe manifest 没有这个键 → set 返回 false")
        XCTAssertEqual(stringProbe.stringValue(from: config), "", "schema 之外的键读回空串（键名漂了的形态）")

        // ⑥ 多选（p5-home-blocks / T2 的第五种类型）：缺键回落 manifest 默认 → 翻面写回 → 顺序按选项声明
        let scopesProbe = ModuleConfigControl(
            moduleID: manifest.id,
            key: "visibleScopes",
            kind: .multiSelect(options: ["day", "week", "month", "quarter", "year"], titleKeys: ["a", "b", "c", "d", "e"]),
            titleKey: "settings.modules.progress.visibleScopes"
        )
        XCTAssertEqual(
            scopesProbe.selectedOptions(from: config),
            ["day", "week", "month"],
            "缺键回落 manifest 默认值（卡上勾中的就是模块读到的那一档）"
        )
        XCTAssertTrue(scopesProbe.toggleMultiSelect("quarter", config: config), "勾上「本季」")
        XCTAssertEqual(
            scopesProbe.selectedOptions(from: config),
            ["day", "week", "month", "quarter"],
            "翻面后按**选项声明顺序**收敛（本季排在默认三档之后）"
        )
        // 落盘类型必须是 `[String]`（模块侧读的就是它；写成别的类型就是「勾得动、模块读不到」）
        XCTAssertEqual(
            try JSONDecoder().decode([String].self, from: try XCTUnwrap(suite.data(forKey: scopesProbe.key))),
            ["day", "week", "month", "quarter"]
        )
        XCTAssertTrue(scopesProbe.toggleMultiSelect("day", config: config), "取消「今天」")
        XCTAssertEqual(
            scopesProbe.selectedOptions(from: config),
            ["week", "month", "quarter"],
            "取消一项后剩下的仍按声明顺序（不是按点击先后）"
        )
        // 写进去的野值（不在选项里的取值）不落盘：与数值型的「写侧夹取」同一条理由
        XCTAssertTrue(scopesProbe.writeMultiSelect(["day", "bogus", "day"], config: config))
        XCTAssertEqual(
            scopesProbe.selectedOptions(from: config),
            ["day"],
            "野值被丢掉、重复值被收敛成一项"
        )
        // 顺序与勾选先后无关：倒着写进去，读出来仍按声明顺序
        XCTAssertTrue(scopesProbe.writeMultiSelect(["year", "month", "day"], config: config))
        XCTAssertEqual(scopesProbe.selectedOptions(from: config), ["day", "month", "year"], "写侧也按声明顺序收敛")
        // 手改配置文件塞进野值 → 读侧只认选项里的那几个（卡上不会出现点不掉的勾）
        XCTAssertTrue(config.set("visibleScopes", to: ["bogus", "month", "month"]))
        XCTAssertEqual(scopesProbe.selectedOptions(from: config), ["month"], "读侧同样收敛")
        // 非多选型调用写多选 = 空操作 + false（不误写别的类型）
        XCTAssertFalse(showOutput.writeMultiSelect(["day"], config: config), "布尔控件不是多选型 → 不落盘")
        XCTAssertTrue(ShortcutsSettings.read(from: config).showOutput, "上一次的布尔值一个字节没动")
    }

    /// **音乐卡那一行的界面入口**（T5 修复轮补的口子，T7 挪进允许清单）：模块 id / config 键 /
    /// 类型 / 文案 key 四项对生产事实，另钉住「缺键回落」这一档在**假句柄**上的退化形态。
    ///
    /// **与 T7 之前的一处差别**（有意，见 T7 报告 §候选决策）：控件不再自带 `defaultValue`——
    /// 回落交给 `ConfigHandle`（真句柄回落到 manifest 的 `default`，见上一条用例的 ① 档）。
    /// 因此这里的假句柄（`RecordingConfigHandle`，没有 manifest 默认值、`get` 给 nil）读到的是
    /// `false`：这正是「键名漂出 schema」的退化形态，**由上面那条解析用例把它钉死在 schema 内**。
    ///
    /// 数据源是**生产表本身**（不是测试另抄的键表——同 `effectKeysByModuleID` 口径）。
    func testMusicAlbumArtControlMatchesManifestAndCatalog() throws {
        let control = try XCTUnwrap(
            ModuleSettingsSection.configControls.first { $0.moduleID == MusicModule.moduleID && $0.key == "showAlbumArt" },
            "音乐卡必须有一条「显示封面」控件（T5 修复轮补的就是这个界面入口）"
        )

        XCTAssertEqual(control.moduleID, MusicModule.moduleID, "模块 id 必须是真模块那一份字面量")
        XCTAssertEqual(control.key, "showAlbumArt", "落盘键名就是 `defaults write` 会写的那个字面量")
        XCTAssertEqual(control.kind, .boolean, "这一个开关写的是布尔值")
        XCTAssertEqual(control.titleKey, "settings.modules.music.showAlbumArt")

        let properties = try XCTUnwrap(MusicModule.manifest.config?.properties)
        let node = try XCTUnwrap(
            properties[control.key],
            "控件的键名必须与 manifest config 的那一键逐字一致（`\(control.key)` 不在 schema 里）"
        )
        XCTAssertEqual(node.type, "boolean", "这一个开关写的是布尔值")
        XCTAssertEqual(
            node.default,
            ConfigValue.bool(MusicConfigDefaults.showAlbumArt),
            "manifest 那一键的默认值 = MusicConfigDefaults.showAlbumArt（读取侧兜底用同一个常量）"
        )
        XCTAssertEqual(
            node.default,
            ConfigValue.bool(false),
            "T3 起默认不显示（方向也要钉住：用户要的是「可以不显示那个图片」）"
        )

        XCTAssertResolves(control.titleKey)
    }

    /// **进度卡那一行的界面入口**（p5-home-blocks / T2，docs/29 §做法 机制二 / D-05）：模块 id /
    /// config 键 / 控件类型 / 选项与文案 / 行标题五項对生产事实——数据源是**生产表本身**
    /// （同 `testMusicAlbumArtControlMatchesManifestAndCatalog` 的口径）。
    ///
    /// 选项与文案 key 都取自 `ProgressCalculator.Scope.allCases`：**顺序即模块的声明顺序**，
    /// 也即「勾满五档而块放不下时画前三个」那个顺序（模块侧 `listedScopes` 取的是前缀）。
    /// 类型那一档在允许清单用例里已按 kind 分档断言（`.multiSelect` ↔ manifest 的 `list`），
    /// 这里把**具体取值**钉死：选项写错一个字 / 少一档（比如漏了 quarter），这里就红。
    func testProgressVisibleScopesControlMatchesManifestAndCatalog() throws {
        let control = try XCTUnwrap(
            ModuleSettingsSection.configControls.first { $0.moduleID == "com.cmeng.gourd.progress" && $0.key == "visibleScopes" },
            "进度卡必须有一条「显示的尺度」控件（D-05 要的就是这个入口）"
        )

        XCTAssertEqual(control.moduleID, ProgressModule.manifest.id, "模块 id 必须是真模块那一份字面量")
        XCTAssertEqual(control.key, "visibleScopes", "落盘键名就是模块侧 `get` 读的那一个字面量")
        XCTAssertEqual(control.titleKey, "settings.modules.progress.visibleScopes")

        // 五档选项 + 一一对应的文案 key（都取自模块侧，不在设置页另抄一份）
        XCTAssertEqual(
            control.multiSelectOptions.map(\.value),
            ProgressCalculator.Scope.allCases.map(\.rawValue),
            "选项顺序 = `Scope.allCases`（勾满而块放不下时画前三个的那个顺序）"
        )
        XCTAssertEqual(
            control.multiSelectOptions.map(\.titleKey),
            ProgressCalculator.Scope.allCases.map(\.labelKey),
            "文案 key 复用模块侧的行标签（`module.progress.scope.<rawValue>`）"
        )
        XCTAssertEqual(
            control.multiSelectOptions.map(\.value),
            ["day", "week", "month", "quarter", "year"],
            "五档逐条写死（漏一档 / 改名即红）"
        )

        let properties = try XCTUnwrap(ProgressModule.manifest.config?.properties)
        let node = try XCTUnwrap(
            properties[control.key],
            "控件的键名必须与 manifest config 的那一键逐字一致（`\(control.key)` 不在 schema 里）"
        )
        XCTAssertEqual(node.type, "list", "这个键写的是字符串表")
        XCTAssertEqual(node.itemType, "string")
        XCTAssertEqual(
            node.default,
            ConfigValue.strings(["day", "week", "month"]),
            "manifest 那一键的默认值 = 出厂三档（`ProgressCalculator.defaultVisibleScopes`）"
        )

        XCTAssertResolves(control.titleKey)
    }

    /// **进度卡工作日三行**（p7 / T3，docs/31 §接口与数据形状 4 / D-08）：模块 id / config 键 /
    /// 控件类型与区间 / 选项与文案 / 行标题五项对生产事实——数据源是**生产表本身**
    /// （同 `testProgressVisibleScopesControlMatchesManifestAndCatalog` 的口径）。
    ///
    /// 三行各自钉死：
    /// - `workStart` / `workEnd`：`.integer(range: WorkdayCalendar.workHourRange)`
    ///   ——区间**单一来源**（模块读侧的越界回落与滑块共用这一个常量，这里再写一个数字即红）；
    /// - `workdays`：`.multiSelect`，选项 = ISO 1…7、文案 key = `module.progress.weekday.<ISO>`
    ///   （七条逐字写死，改名 / 漏一天即红），`multiSelectEffectiveSet` 接
    ///   `WorkdayCalendar.resolveWorkdays`——卡上勾中的一组 = 块判定用的那一组
    ///   （空表 / 全坏值 → 一~五；野值不会变成点不掉的勾）。
    ///
    /// 类型那一档在允许清单用例里已按 kind 分档断言（`.integer` ↔ manifest 的 `integer`、
    /// `.multiSelect` ↔ `list`），这里把**具体取值**钉死。
    func testProgressWorkdayControlsMatchManifestAndCatalog() throws {
        let controls = ModuleSettingsSection.configControls.filter { $0.moduleID == "com.cmeng.gourd.progress" }
        func control(_ key: String) throws -> ModuleConfigControl {
            try XCTUnwrap(
                controls.first { $0.key == key },
                "进度卡必须有一条 `\(key)` 控件（docs/31 §接口 4 的工作日三行）"
            )
        }

        // 上下班时间：整点滑块，区间取模块侧常量（不写第二份字面量）
        let start = try control("workStart")
        XCTAssertEqual(start.moduleID, ProgressModule.manifest.id, "模块 id 必须是真模块那一份字面量")
        XCTAssertEqual(start.kind, .integer(range: WorkdayCalendar.workHourRange), "区间 = workHourRange（单一来源）")
        XCTAssertEqual(start.titleKey, "settings.modules.progress.workStart")
        XCTAssertResolves(start.titleKey)
        let end = try control("workEnd")
        XCTAssertEqual(end.kind, .integer(range: WorkdayCalendar.workHourRange))
        XCTAssertEqual(end.titleKey, "settings.modules.progress.workEnd")
        XCTAssertResolves(end.titleKey)

        // 工作日：ISO 1…7 的七枚胶囊，文案 key 逐条钉死
        let workdays = try control("workdays")
        XCTAssertEqual(workdays.titleKey, "settings.modules.progress.workdays")
        XCTAssertResolves(workdays.titleKey)
        XCTAssertEqual(
            workdays.multiSelectOptions.map(\.value),
            ["1", "2", "3", "4", "5", "6", "7"],
            "选项 = ISO 编号 1…7（1 = 周一；漏一天 / 改名即红）"
        )
        XCTAssertEqual(
            workdays.multiSelectOptions.map(\.titleKey),
            (1...7).map { "module.progress.weekday.\($0)" },
            "文案 key 形态 `module.progress.weekday.<ISO>`"
        )
        for option in workdays.multiSelectOptions {
            XCTAssertResolves(option.titleKey)
        }

        // manifest 三键：类型与默认值（workStart / workEnd 的默认值 = 模块侧常量）
        let properties = try XCTUnwrap(ProgressModule.manifest.config?.properties)
        XCTAssertEqual(properties["workStart"]?.type, "integer")
        XCTAssertEqual(properties["workStart"]?.default, ConfigValue.int(WorkdayCalendar.defaultWorkStartHour))
        XCTAssertEqual(properties["workEnd"]?.type, "integer")
        XCTAssertEqual(properties["workEnd"]?.default, ConfigValue.int(WorkdayCalendar.defaultWorkEndHour))
        XCTAssertEqual(properties["workdays"]?.type, "list")
        XCTAssertEqual(properties["workdays"]?.itemType, "string")
        XCTAssertEqual(
            properties["workdays"]?.default,
            ConfigValue.strings(WorkdayCalendar.defaultWorkdays.sorted().map(String.init)),
            "默认值 = 模块侧 defaultWorkdays（ISO 一~五）"
        )

        // 多选的有效值解析：空表 / 全坏值 → 一~五；合法子集按 ISO 升序（= 选项声明顺序）
        let config = RecordingConfigHandle(schema: ["workdays"])
        XCTAssertEqual(workdays.selectedOptions(from: config), ["1", "2", "3", "4", "5"], "缺键 → 一~五")
        XCTAssertTrue(config.set("workdays", to: [String]()))
        XCTAssertEqual(workdays.selectedOptions(from: config), ["1", "2", "3", "4", "5"], "空表 → 一~五（与块判定同一处）")
        XCTAssertTrue(config.set("workdays", to: ["bogus", "0", "8"]))
        XCTAssertEqual(workdays.selectedOptions(from: config), ["1", "2", "3", "4", "5"], "全坏值 → 一~五")
        XCTAssertTrue(config.set("workdays", to: ["7", "bogus", "6", "6"]))
        XCTAssertEqual(
            workdays.selectedOptions(from: config),
            ["6", "7"],
            "野值丢弃 + 去重 + 按选项声明顺序（= ISO 升序）"
        )
        // 最后一枚不许关（与尺度多选同一条既有口径）：只剩「6」时点它是拒绝、盘上不动
        XCTAssertTrue(config.set("workdays", to: ["6"]))
        XCTAssertFalse(workdays.toggleMultiSelect("6", config: config), "最后一枚拒绝取消")
        XCTAssertEqual(workdays.selectedOptions(from: config), ["6"], "拒绝之后盘上一个字节没动")
    }

    /// **启动台上区两条新 key**（p7 / T5，docs/31 §接口与数据形状 5 / D-18）：`module.launcher.quickLaunch`
    /// 与 `.quickLaunchHint`——zh-Hans / en 两个值逐字写死、都落 `translated`，并在宿主 bundle 的
    /// zh-Hans 一份里**解析得出**（视图里是 `Text(LocalizedStringKey(...))` 直查，键写错 / 文案没编进去
    /// 就是一行没有标签的文字）。
    ///
    /// 判据读**两份 catalog 原文件**（`testShelfUserVisibleStringsUseTheUnifiedName` 同款口径，含
    /// `catalogTable` 那套解析）：落点是**只在进包那份**（`DynamicIsland/Localizable.xcstrings`）——
    /// 根 catalog 对本批新键 grep 计数为 0，这里把「不落根那份」也钉住（D-18：全新键只落进包那份）。
    func testLauncherQuickLaunchKeysLiveOnlyInTheInPackageCatalog() throws {
        let rootURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let inPackage = "DynamicIsland/Localizable.xcstrings"
        let rootCatalog = "Localizable.xcstrings"
        let tables = [
            inPackage: try Self.catalogTable(at: rootURL.appendingPathComponent(inPackage)),
            rootCatalog: try Self.catalogTable(at: rootURL.appendingPathComponent(rootCatalog)),
        ]

        let expected: [(key: String, zhHans: String, en: String)] = [
            ("module.launcher.quickLaunch", "快捷启动", "Quick Launch"),
            ("module.launcher.quickLaunchHint", "将应用拖到这里固定", "Drag apps here to pin"),
        ]

        for row in expected {
            let languages = try XCTUnwrap(
                tables[inPackage]?[row.key],
                "\(row.key) 不在进包那份 catalog 里（上区文案没落？）"
            )
            XCTAssertEqual(languages["zh-Hans"]?.value, row.zhHans, "\(row.key) 的 zh-Hans 值")
            XCTAssertEqual(languages["zh-Hans"]?.state, "translated", "\(row.key) 的 zh-Hans 未落 translated")
            XCTAssertEqual(languages["en"]?.value, row.en, "\(row.key) 的 en 值")
            XCTAssertEqual(languages["en"]?.state, "translated", "\(row.key) 的 en 未落 translated")
            XCTAssertNil(
                tables[rootCatalog]?[row.key],
                "\(row.key) 不该出现在根 catalog（D-18：全新键只落进包那份）"
            )
            XCTAssertResolves(row.key)
        }
    }

    /// **卡片与模块算的是同一组尺度**（T2 审查的 Important 的回归用例）：卡片上「勾中的那一组」
    /// 必须经模块的**公开解析**（`ProgressCalculator.resolveScopes`，登记在
    /// `multiSelectEffectiveSet`）算出，因此它按构造等于**块真正会画的那一组**——
    /// 空表 / 全是坏值 → 出厂三档（不是「一个都没勾」），有真值 → 按真值（去重 + 按选项声明顺序）。
    ///
    /// 另钉住「最后一档不许关」：`toggleMultiSelect` 在只剩一档时**拒绝**（返回 false、不落盘）
    /// ——一组都没有的块一行都不画，而「写空表 + 让模块回落」会让卡片与块在那一次点击上又分叉。
    ///
    /// 读侧只经 `ConfigHandle.get`，所以这里的假体（`RecordingConfigHandle`）够了：
    /// **不碰**开发机真实的 `com.cmeng.gourd.module.progress` 域。
    func testProgressVisibleScopesCardShowsTheEffectiveSet() throws {
        let control = try XCTUnwrap(
            ModuleSettingsSection.configControls.first { $0.moduleID == "com.cmeng.gourd.progress" && $0.key == "visibleScopes" },
            "进度卡必须有一条「显示的尺度」控件"
        )
        let config = RecordingConfigHandle(schema: ["visibleScopes"])

        // ① 一条覆盖值都没有（`get` 给 nil）→ 出厂三档
        //    （真句柄在同样情形下回落到 manifest 默认，值也是这三档——两条路都对得上）
        XCTAssertEqual(control.selectedOptions(from: config), ["day", "week", "month"], "缺键 → 出厂三档")

        // ② 覆盖值是**空表** → 仍然是出厂三档（修掉的那一条：旧实现只做过滤，这里给 []）
        XCTAssertTrue(config.set("visibleScopes", to: [String]()))
        XCTAssertEqual(
            control.selectedOptions(from: config),
            ["day", "week", "month"],
            "空表 → 有效值仍是出厂三档（与块画出来的三行一致，不是「一个都没勾」）"
        )

        // ③ 覆盖值**全是坏值** → 同上（模块侧的回落口径与卡片逐字同一处）
        XCTAssertTrue(config.set("visibleScopes", to: ["bogus", "Month"]))
        XCTAssertEqual(control.selectedOptions(from: config), ["day", "week", "month"], "全坏值 → 出厂三档")

        // ④ 有真值 → 按真值：野值丢弃、去重、顺序按选项声明顺序（不是写入顺序）
        XCTAssertTrue(config.set("visibleScopes", to: ["year", "bogus", "day", "day"]))
        XCTAssertEqual(
            control.selectedOptions(from: config),
            ["day", "year"],
            "野值丢弃 + 去重 + 按选项声明顺序（存进去的先后不参与）"
        )

        // ⑤ 只剩一档时**拒绝取消**（不落盘：盘上还是原来那一档）
        XCTAssertTrue(config.set("visibleScopes", to: ["year"]))
        XCTAssertEqual(control.selectedOptions(from: config), ["year"])
        XCTAssertFalse(control.toggleMultiSelect("year", config: config), "最后一档拒绝取消")
        XCTAssertEqual(control.selectedOptions(from: config), ["year"], "拒绝之后盘上一个字节没动")
        // 从一档出发**加**一档照常，写盘顺序仍按选项声明顺序
        XCTAssertTrue(control.toggleMultiSelect("day", config: config), "从一档加一档")
        XCTAssertEqual(control.selectedOptions(from: config), ["day", "year"])
        // 两档时取消回到一档；再到一档又拒绝
        XCTAssertTrue(control.toggleMultiSelect("day", config: config), "两档时可以取消")
        XCTAssertEqual(control.selectedOptions(from: config), ["year"])

        // ⑥ 手改配置文件写成空表之后点一下：**从有效三档出发**（不是从空表出发）
        XCTAssertTrue(config.set("visibleScopes", to: [String]()))
        XCTAssertTrue(control.toggleMultiSelect("quarter", config: config), "空表上勾一档")
        XCTAssertEqual(
            control.selectedOptions(from: config),
            ["day", "week", "month", "quarter"],
            "落盘的是「有效三档 + 本季」——空表在点击这一下就被治好"
        )
        XCTAssertEqual(
            try JSONDecoder().decode([String].self, from: try XCTUnwrap(config.storage["visibleScopes"])),
            ["day", "week", "month", "quarter"],
            "盘上也是这四项（顺序 = 选项声明顺序）"
        )
    }

    /// 注册表侧的接管查询对**音乐模块**同样成立（docs/20 §接口与数据形状 2）：`homeBlockWidth(for:)`
    /// 取回 200/250（`HomeStripView` 就靠它给音乐块 T2 缩宽后的宽度）、`takeoverEnableKey(for:)`
    /// 取回 `showStandardMediaControls`（启用真源）。
    ///
    /// 注册走**真门**（`KernelBootstrap.enablementGate`），但**不 bootstrap**：门只读，
    /// 本用例不写任何真实偏好（音乐当前的启用状态与断言无关）。
    func testMusicModuleHooksReadThroughTheRegistry() {
        let registry = ModuleRegistry.shared
        registry.register(
            [MusicModule.self],
            enabled: KernelBootstrap.enablementGate(registry: registry)
        )

        XCTAssertEqual(
            registry.homeBlockWidth(for: MusicModule.moduleID),
            ModuleHomeBlockWidth(min: 200, ideal: 250),
            "音乐块宽度声明经注册表原样取给宿主（200/250：T2 缩宽后的那一档）"
        )
        XCTAssertEqual(
            registry.takeoverEnableKey(for: MusicModule.moduleID)?.name,
            Defaults.Keys.showStandardMediaControls.name,
            "音乐的启用真源 = 上游 `showStandardMediaControls` 键"
        )
        XCTAssertNotEqual(
            registry.takeoverEnableKey(for: MusicModule.moduleID)?.name,
            Defaults.Keys.autoHideInactiveNotchMediaPlayer.name,
            "「无会话即隐藏」是**运行期条件**（判据的第二段），不是本模块的启用真源"
        )
    }

    /// 命名空间环境键的**默认值半边**（D-08 / docs/20 §接口与数据形状 6）：没有注入者时读到 `nil`，
    /// 模块侧据此退回自带 `@Namespace`（配对静默失效，不崩不空白）。
    ///
    /// **注入那一半没有自动化断言**：注入点是一条 SwiftUI 视图修饰符
    /// （`HomeStripView` 的 `.environment(\.homeAlbumArtNamespace, albumArtNamespace)`），
    /// 起作用与否只能靠人工验收（折叠态播放器 ↔ 展开态封面那对 matchedGeometry 动画）；
    /// 「读回自己刚写的环境值」那种断言只是把修饰符抄进用例，不证明宿主真的注入了，故不写。
    func testHomeAlbumArtNamespaceDefaultsToNil() {
        XCTAssertNil(
            EnvironmentValues().homeAlbumArtNamespace,
            "没人注入时缺省 nil（模块此时用自带 @Namespace 兜底）"
        )
    }

    // MARK: - 日历接管模块（P3 冻结批次 / T6）

    /// docs/24-release-freeze.md §接口与数据形状 的 calendar 片段：**这个真模块**的 manifest 声明值
    /// 逐条对齐（与 `testTimerModuleManifestMatchesTakeoverContract` 同款）。
    ///
    /// 与另外三个接管模块的两处**刻意不同**，都钉在这里：
    /// - `surfaces == [.expanded]`（只接展开 tab：不给首页加块、不占折叠槽位——首页那条全宽日历行
    ///   仍由上游 `NotchHomeView` 渲染，它的渲染接管不在本批）；
    /// - `config == nil`（口径 3）：本模块没有「自己的」配置键，唯一相关的上游键就是
    ///   `takeoverEnableKey` 本身，登记它是重复——因此组件页的日历卡上不会出现
    ///   「由上游设置管理」那行（没有登记过任何不可编辑的键，见 `testConfigControlAllowlist…`）。
    ///
    /// 本用例**不写**任何真实偏好（只读钩子与常量），因此没有夹具与还原。
    func testCalendarModuleManifestMatchesTakeoverContract() throws {
        let manifest = CalendarModule.manifest
        XCTAssertNoThrow(try manifest.validate())

        XCTAssertEqual(manifest.id, CalendarModule.moduleID, "moduleID 与 manifest.id 必须是同一份字面量")
        XCTAssertEqual(manifest.id, "com.cmeng.gourd.calendar")
        XCTAssertEqual(manifest.shortID, "calendar")
        XCTAssertEqual(manifest.name.key, "module.calendar.name")
        XCTAssertEqual(manifest.summary?.key, "module.calendar.summary")
        XCTAssertEqual(manifest.icon, IconSpec(type: "symbol", name: "calendar"))
        XCTAssertEqual(manifest.kind, "builtin")
        XCTAssertEqual(manifest.surfaces, [.expanded], "只声明展开 tab（不给首页加块、不占折叠槽位）")
        XCTAssertFalse(manifest.surfaces.contains(.compact), "接管模块不占折叠槽位")
        XCTAssertFalse(manifest.surfaces.contains(.home), "首页那条日历行仍由上游渲染，本模块不占首页块")
        XCTAssertNil(manifest.defaultPlacement, "tab 落模块段（无 placement → Int.max，按 id 字典序排在 launcher 之前）")
        XCTAssertEqual(
            manifest.defaultEnabled,
            Defaults.Keys.showCalendar.defaultValue,
            "= 上游 `showCalendar` 的默认值（接管键读不到时才不生效）"
        )
        XCTAssertEqual(
            manifest.defaultEnabled,
            true,
            "上游这个开关默认是开的（方向也要钉住，避免它被悄悄改成保守值）"
        )
        XCTAssertTrue(manifest.permissions.isEmpty, "本批只搬渲染归属：零新增能力请求（日历数据仍走上游那条权限）")
        XCTAssertNil(manifest.config, "口径 3：不登记 config（唯一相关的上游键就是 takeoverEnableKey 本身）")

        // 两条取值型钩子：真源 = 上游那颗日历总开关；不接首页块 → 不声明块宽
        XCTAssertEqual(CalendarModule.takeoverEnableKey?.name, Defaults.Keys.showCalendar.name)
        XCTAssertNil(CalendarModule.homeBlockWidth, "只接展开 tab（宿主统一宽度）")

        // 字面量 manifest 也能走 JSON（与宿主读 descriptor 同一条路）
        XCTAssertEqual(try ModuleManifest.decode(from: try JSONEncoder().encode(manifest)), manifest)
    }

    /// **接管键 read-through**：日历的启用真源是上游 `showCalendar`，不是它自己的 `defaultEnabled`
    /// （登记值 `true`）——两个方向都走一遍，且**经真组合根的门**（`KernelBootstrap.enablementGate`）。
    ///
    /// 三点刻意写死（改动前先读）：
    /// 1. **自己置全夹具**：`showCalendar` 读的是**测试域**（Debug 域 `com.cmeng.gourd.dev`）盘上的值，
    ///    本机该域**缺键**（缺键走上游默认 `true`）——缺键的机器与显式写过 `false` 的机器必须走同一条
    ///    断言，故两个方向都显式置定值，`defer` 逐字还原（原本有键写回原值、原本没键删键）；
    /// 2. **注册走真门**：旧门（`manifests[$0]?.defaultEnabled`）读不到上游键，键关闭时也会放行；
    /// 3. **不调 `KernelBootstrap.bootstrap()`**（文件头口径 2：那个入口会写开发机真实的
    ///    `enableScreenAssistant`），只调注册表自己的 `bootstrap()`。
    ///
    /// 变异验证（T6 报告 §3）：把 `CalendarModule.takeoverEnableKey` 换成别的键或去掉 → 本条红
    /// （第 ① 档的 `.disabled` 与 `tabEntries.isEmpty` 都会破）。
    func testCalendarModuleEnablementReadsThroughShowCalendar() async throws {
        let keys = [Defaults.Keys.showCalendar.name]
        let originals = snapshotValues(of: keys)
        defer { restoreValues(originals, for: keys) }

        let registry = ModuleRegistry.shared
        let id = CalendarModule.moduleID
        let expandedRequest = ContentRequest(surface: .expanded, phase: .expanded, reason: .initial)

        // ① 键关着 → 门不放行：**不看** manifest 的 `defaultEnabled`（登记值 true）
        Defaults[.showCalendar] = false
        registry.register([CalendarModule.self], enabled: KernelBootstrap.enablementGate(registry: registry))
        await registry.bootstrap()

        XCTAssertEqual(registry.states[id], .disabled, "接管键 false → 启用门不放行（不看过 manifest 默认 true）")
        XCTAssertNil(registry.instance(for: id), "未启用的模块不实例化")
        XCTAssertTrue(registry.tabEntries.isEmpty, "关掉 showCalendar → 日历 tab 不在投影里（与首页那条日历行一起消失）")
        guard case .unavailable = registry.content(for: id, request: expandedRequest) else {
            return XCTFail("未激活的模块，展开请求应降级为 .unavailable（06 §3.2）")
        }

        // ② 键开着 → 放行：进 tab 投影，展开请求拿到那个孤儿视图
        Defaults[.showCalendar] = true
        await registry.deactivateAll()
        registry.register([CalendarModule.self], enabled: KernelBootstrap.enablementGate(registry: registry))
        await registry.bootstrap()

        XCTAssertEqual(registry.states[id], .active, "接管键 true → 启用门放行")
        XCTAssertNotNil(registry.instance(for: id) as? CalendarModule, "过门的日历照常实例化")
        XCTAssertEqual(registry.tabEntries.map(\.id), [id], "日历的展开 tab 由模块投影产出")
        guard case .view = registry.content(for: id, request: expandedRequest) else {
            return XCTFail("日历的展开请求应拿到那个孤儿视图 StandaloneCalendarView（.view）")
        }
    }

    // MARK: - 统计接管模块（p3-widgets / T2）

    /// `StatsModule.manifest` 的契约：26 §接口与数据形状 的 stats 行逐条对齐——**首页块 + 一个开关**
    /// （D-02：用户说「不需要单独面板」，所以**不声明 `expanded`**）。
    ///
    /// 与另外四个接管模块的两处刻意不同，都钉在这里：
    /// - `surfaces == [.home]`（只接首页块：不占展开 tab、不占折叠槽位——上游那条 Stats tab 分支
    ///   与本批同删，统计的面板入口因此彻底消失）；
    /// - `config` 非空：`enableStatsFeature` 是**真源键**，另三格图表可见性键是**登记键**
    ///   （上游 `StatsSettings` 设置页仍读写它们）——因此组件页的统计卡上会出现
    ///   「由上游设置管理」那行（登记了三个不可编辑的键）。
    ///
    /// 本用例**不写**任何真实偏好（只读钩子与常量），因此没有夹具与还原。
    func testStatsModuleManifestMatchesTakeoverContract() throws {
        let manifest = StatsModule.manifest
        XCTAssertNoThrow(try manifest.validate())

        XCTAssertEqual(manifest.id, StatsModule.moduleID, "moduleID 与 manifest.id 必须是同一份字面量")
        XCTAssertEqual(manifest.id, "com.cmeng.gourd.stats")
        XCTAssertEqual(manifest.shortID, "stats")
        XCTAssertEqual(manifest.name.key, "module.stats.name")
        XCTAssertEqual(manifest.summary?.key, "module.stats.summary")
        XCTAssertEqual(manifest.icon, IconSpec(type: "symbol", name: "chart.xyaxis.line"))
        XCTAssertEqual(manifest.kind, "builtin")
        XCTAssertEqual(manifest.surfaces, [.home], "只声明首页块（D-02：不保留独立面板）")
        XCTAssertFalse(manifest.surfaces.contains(.expanded), "展开 tab 已删（统计不再有面板）")
        XCTAssertFalse(manifest.surfaces.contains(.compact), "接管模块不占折叠槽位")
        XCTAssertEqual(
            manifest.defaultPlacement,
            Placement(slot: nil, order: 50),
            "首页块序 50（排在 notifications 40 之后；统计没有可继承的内置块序号，取现有最大值 + 10）"
        )
        XCTAssertEqual(
            manifest.defaultEnabled,
            Defaults.Keys.enableStatsFeature.defaultValue,
            "= 上游 `enableStatsFeature` 的默认值（接管键读不到时才不生效）"
        )
        XCTAssertEqual(manifest.defaultEnabled, false, "上游这个开关默认是关的（方向也要钉住）")
        XCTAssertTrue(manifest.permissions.isEmpty, "只读进程内已有的采样结果：零新增能力请求（采样仍走上游那条 Mach / IOKit 通道）")

        let properties = try XCTUnwrap(manifest.config?.properties, "登记真源键 + 三格图表可见性键")
        XCTAssertEqual(
            properties.keys.sorted(),
            ["enableStatsFeature", "showCpuGraph", "showGpuGraph", "showMemoryGraph"],
            "config 只登记这四个上游键（真源键 + 三格图表的可见性键），不新发明键（D-03）"
        )
        XCTAssertEqual(properties["enableStatsFeature"]?.type, "boolean")
        XCTAssertEqual(properties["enableStatsFeature"]?.default, ConfigValue.bool(false))
        for key in ["showCpuGraph", "showMemoryGraph", "showGpuGraph"] {
            XCTAssertEqual(properties[key]?.type, "boolean", "\(key) 是登记键：类型照上游")
            XCTAssertEqual(
                properties[key]?.default,
                ConfigValue.bool(true),
                "\(key) 的登记默认值取上游键的默认值（上游默认开着）"
            )
        }

        // 三条取值型钩子：真源 = 上游那颗统计总开关；宽度 = 26 §做法 机制一 给统计的定值 220 / 300
        XCTAssertEqual(StatsModule.takeoverEnableKey?.name, Defaults.Keys.enableStatsFeature.name)
        XCTAssertEqual(
            StatsModule.homeBlockWidth,
            ModuleHomeBlockWidth(min: 220, ideal: 300),
            "首页块宽度声明（26 §做法 机制一：统计比进度宽一档）"
        )
        // 可见性钩子**刻意不重写**（缺省 true）：本模块不声明 `expanded`，投影先按 `surfaces` 过滤，
        // 它永远不被问到——写一条 `= true` 只会让读者以为本模块有 tab（与 mirror / music 同一口径，
        // 那两处也没写断言）。

        // 迷你条的三行：键 / 图标 / 值口径都要对得上（顺序 = 显示顺序 CPU → 内存 → GPU）
        XCTAssertEqual(StatsHomeBlockLayout.rows.map(\.id), ["cpu", "memory", "gpu"])
        XCTAssertEqual(StatsHomeBlockLayout.rows.map(\.labelKey), ["CPU", "Memory", "GPU"], "标签复用上游统计页那三条 key")
        XCTAssertEqual(
            StatsHomeBlockLayout.rows.map(\.ringColor),
            [.cyan, .purple, .orange],
            "三环分色（机制八：CPU 青 / 内存 紫 / GPU 琥珀；取面板既有的系统色家族，不新造一套）"
        )
        // 标签解析：**只对 `Memory` 用 `XCTAssertResolves`**——它的 zh-Hans 译名（`内存`）与 key 不同形；
        // 另两条（`CPU` / `GPU`）的 zh-Hans 译文就是 key 本身，helper 的「译文 != key」判据对它们不适用
        // （那两条的契约是「key 与上游统计页逐字一致」，已由上面那条相等断言钉住）。
        XCTAssertResolves("Memory")
        // 值文案走 `StatsManager` 的 `*UsageString`（同一份 `StatsFormatting` 口径：`%.1f%%`）
        XCTAssertEqual(StatsHomeBlockLayout.Row.cpu.valueText(in: StatsManager.shared), StatsManager.shared.cpuUsageString)
        XCTAssertEqual(
            StatsHomeBlockLayout.Row.memory.valueText(in: StatsManager.shared),
            StatsManager.shared.memoryUsageString
        )
        XCTAssertEqual(StatsHomeBlockLayout.Row.gpu.valueText(in: StatsManager.shared), StatsManager.shared.gpuUsageString)
        // 细条进度：用量是 0…100 的百分数 → 夹到 0…1（越界会画到框外）
        XCTAssertEqual(StatsHomeBlockLayout.Row.cpu.progressValue(in: StatsManager.shared), StatsManager.shared.cpuUsage / 100, accuracy: 1e-9)

        // 字面量 manifest 也能走 JSON（与宿主读 descriptor 同一条路）
        XCTAssertEqual(try ModuleManifest.decode(from: try JSONEncoder().encode(manifest)), manifest)
    }

    /// 三环的**直径分档**：宽 ≥ 200 用 46、更窄退 40；宽取不到（0 / NaN / 无穷）一律退小档
    /// ——宁可画小一点，也不要画出三个被裁的环。
    ///
    /// 变异验证（T9 §变异）：`ringDiameter(forWidth:)` 改成恒 46 → 本条与下面那条「不裁」一起红。
    func testStatsRingDiameterStepsDownInNarrowBlocks() {
        XCTAssertEqual(StatsRingMetrics.ringDiameter(forWidth: 300), 46)
        XCTAssertEqual(StatsRingMetrics.ringDiameter(forWidth: 220), 46, "宿主给的最小宽仍是常规档")
        XCTAssertEqual(StatsRingMetrics.ringDiameter(forWidth: 200), 46, "阈值取闭区间下界：200 不收缩")
        XCTAssertEqual(StatsRingMetrics.ringDiameter(forWidth: 199.9), 40, "刚过阈值就退一档")
        XCTAssertEqual(StatsRingMetrics.ringDiameter(forWidth: 180), 40)
        XCTAssertEqual(StatsRingMetrics.ringDiameter(forWidth: 0), 40, "首帧取不到宽")
        XCTAssertEqual(StatsRingMetrics.ringDiameter(forWidth: -10), 40)
        XCTAssertEqual(StatsRingMetrics.ringDiameter(forWidth: .nan), 40)
        XCTAssertEqual(StatsRingMetrics.ringDiameter(forWidth: .infinity), 40)
    }

    /// **「不裁」是一句可断言的话**：三环 + 两个间距的总宽必须 ≤ 块宽——生产档两处都过一遍
    /// （220 = `StatsModule.homeBlockWidth.min` → 158；180 = 模块统一最小档 → 140）。
    ///
    /// 变异验证（T9 §变异）：`ringDiameter(forWidth:)` 恒 46 → 窄档这条的 140 变 158（断言红）。
    func testThreeRingsNeverExceedTheAvailableBlockWidth() {
        XCTAssertEqual(StatsModule.homeBlockWidth, ModuleHomeBlockWidth(min: 220, ideal: 300), "口径 3 的定值")
        XCTAssertEqual(StatsRingMetrics.rowWidth(forWidth: 220), 158, "3 × 46 + 2 × 10")
        XCTAssertLessThanOrEqual(StatsRingMetrics.rowWidth(forWidth: 220), 220, "220 最小宽下不裁")
        XCTAssertEqual(StatsRingMetrics.rowWidth(forWidth: 180), 140, "3 × 40 + 2 × 10")
        XCTAssertLessThanOrEqual(StatsRingMetrics.rowWidth(forWidth: 180), 180, "180 档下也不裁")
        XCTAssertEqual(StatsRingMetrics.rowWidth(forWidth: 0), 140, "取不到宽时按小档算总宽")
    }

    /// 三环的**线宽 / 环轨 / 环心**三项刻度（机制八「科技风只做三件事」的可断言部分）：
    /// 主环 5pt + 亮描边 2pt、环轨 `white.opacity(0.12)`、环心字号随直径退档、
    /// 环心文字的可用宽**在环带内侧**（文字不压环带）。
    func testStatsRingLineWidthsAndCounterMetrics() {
        XCTAssertEqual(StatsRingMetrics.mainLineWidth, 5)
        XCTAssertEqual(StatsRingMetrics.highlightLineWidth, 2)
        XCTAssertEqual(StatsRingMetrics.trackOpacity, 0.12)
        XCTAssertEqual(StatsRingMetrics.ringSpacing, 10)

        XCTAssertEqual(StatsRingMetrics.counterFontSize(forDiameter: 46), 11)
        XCTAssertEqual(StatsRingMetrics.counterFontSize(forDiameter: 40), 10, "直径退档时字号跟着退")
        XCTAssertEqual(StatsRingMetrics.counterMaxWidth(forDiameter: 46), 32)
        XCTAssertLessThan(
            StatsRingMetrics.counterMaxWidth(forDiameter: 46),
            46 - 2 * StatsRingMetrics.mainLineWidth,
            "环心文字的可用宽必须落在 5pt 环带的内侧"
        )
    }

    /// **接管键 read-through**：统计的启用真源是上游 `enableStatsFeature`，不是它自己的
    /// `defaultEnabled`——两个方向都走一遍，且**经真组合根的门**（`KernelBootstrap.enablementGate`）。
    ///
    /// 与日历那条同款的三点刻意写死：
    /// 1. **自己置全夹具**：`enableStatsFeature` 读的是**测试域**（Debug 域 `com.cmeng.gourd.dev`）
    ///    盘上的值（本机可能是任意值，Release 域里它是 true）——两个方向都显式置定值，
    ///    `defer` 逐字还原（原本有键写回原值、原本没键删键）；
    /// 2. **注册走真门**：旧门（`manifests[$0]?.defaultEnabled`）读不到上游键，键关闭时也会放行
    ///    （登记值 false 会碰巧挡住，所以反向那一档尤其要有断言——键**开**时必须真的放行）；
    /// 3. **不调 `KernelBootstrap.bootstrap()`**（文件头口径 2：那个入口会写开发机真实的
    ///    `enableScreenAssistant`），只调注册表自己的 `bootstrap()`。
    ///
    /// 变异验证（本任务 §3 变异 ①）：把 `StatsModule.takeoverEnableKey` 换成别的键或去掉 →
    /// 本条红（第 ① 档的 `.disabled` 与 `homeEntries.isEmpty` 都会破）。
    func testStatsModuleEnablementReadsThroughEnableStatsFeature() async throws {
        let keys = [Defaults.Keys.enableStatsFeature.name]
        let originals = snapshotValues(of: keys)
        defer { restoreValues(originals, for: keys) }

        let registry = ModuleRegistry.shared
        let id = StatsModule.moduleID
        let homeRequest = ContentRequest(surface: .home, phase: .expanded, reason: .initial)

        // ① 键关着 → 门不放行：统计既不在首页块投影里，首页请求也降级为 `.unavailable`
        Defaults[.enableStatsFeature] = false
        registry.register([StatsModule.self], enabled: KernelBootstrap.enablementGate(registry: registry))
        await registry.bootstrap()

        XCTAssertEqual(registry.states[id], .disabled, "接管键 false → 启用门不放行")
        XCTAssertNil(registry.instance(for: id), "未启用的模块不实例化")
        XCTAssertTrue(registry.homeEntries.isEmpty, "关掉 enableStatsFeature → 首页块投影里没有统计")
        XCTAssertTrue(registry.tabEntries.isEmpty, "统计不声明 expanded → tab 投影恒为空（上游那条 Stats 分支已删）")
        guard case .unavailable = registry.content(for: id, request: homeRequest) else {
            return XCTFail("未激活的模块，首页请求应降级为 .unavailable（06 §3.2）")
        }

        // ② 键开着 → 放行：进首页块投影，首页请求拿到迷你条（.view），展开请求仍答 .none
        Defaults[.enableStatsFeature] = true
        await registry.deactivateAll()
        registry.register([StatsModule.self], enabled: KernelBootstrap.enablementGate(registry: registry))
        await registry.bootstrap()

        XCTAssertEqual(registry.states[id], .active, "接管键 true → 启用门放行")
        XCTAssertNotNil(registry.instance(for: id) as? StatsModule, "过门的统计照常实例化")
        XCTAssertEqual(registry.homeEntries.map(\.id), [id], "统计的首页块由模块投影产出")
        XCTAssertTrue(registry.tabEntries.isEmpty, "统计不声明 expanded → 即使开着也一个 tab 都不多出来（上游那条 Stats 分支已删）")
        guard case .view = registry.content(for: id, request: homeRequest) else {
            return XCTFail("统计的首页请求应拿到迷你条视图（.view）")
        }
        let expandedRequest = ContentRequest(surface: .expanded, phase: .expanded, reason: .initial)
        guard case .none = registry.content(for: id, request: expandedRequest) else {
            return XCTFail("统计不声明 expanded（D-02）→ 展开请求必须答 .none")
        }
    }

    /// 计数回归（docs/26 §做法 机制一 落地后的口径）：上游那条 Stats 的 `+1` 从
    /// `enabledStandardTabCount()` 删掉后，**统计开关从关到开，tab 计数一个数都不涨**——
    /// 这一数是刘海最小宽度的唯一输入（`currentRecommendedMinimumNotchWidth()`），
    /// 统计改成首页块后它不该再影响面板宽度。
    ///
    /// 写法上**不置全夹具**：两次测量之间只动 `enableStatsFeature`，其余输入（其它上游键、
    /// 注册表）逐字不动，因此 `on - off == 0` 这条不变量与开发机上的其它键值无关
    /// （同「关→开的差值」口径，比抄一组绝对数稳）。`defer` 逐字还原键值。
    func testStatsFeatureAddsNoStandardTabCount() async {
        let keys = [Defaults.Keys.enableStatsFeature.name]
        let originals = snapshotValues(of: keys)
        defer { restoreValues(originals, for: keys) }

        let registry = ModuleRegistry.shared

        Defaults[.enableStatsFeature] = false
        registry.register([StatsModule.self], enabled: KernelBootstrap.enablementGate(registry: registry))
        await registry.bootstrap()
        let countWithFeatureOff = enabledStandardTabCount()
        XCTAssertTrue(registry.tabEntries.isEmpty, "前置：统计关着时它当然不进 tab 投影")

        Defaults[.enableStatsFeature] = true
        await registry.deactivateAll()
        registry.register([StatsModule.self], enabled: KernelBootstrap.enablementGate(registry: registry))
        await registry.bootstrap()
        XCTAssertEqual(registry.states[StatsModule.moduleID], .active, "前置：夹具的键真的放行了统计")
        let countWithFeatureOn = enabledStandardTabCount()

        XCTAssertEqual(
            countWithFeatureOn,
            countWithFeatureOff,
            "统计开关不改变 tab 计数（上游那条 +1 已删；模块只声明 home → 不进 tabEntries 投影）"
        )
        XCTAssertEqual(registry.tabEntries.count, 0, "统计开着也不进 tab 投影（D-02）")
    }

    // MARK: - 组件页「功能」段已撤销（p5-home-blocks / T4；承接 T6 那条功能卡解析用例）

    /// 「功能」段整段撤销（docs/29-home-blocks-and-panel.md §做法 机制三 / D-06），五张卡各自归位。
    ///
    /// 这条用例是 T6 的 `testFeatureCardKeysResolve` 的**迁移形态**：那张生产表（`featureCards`）连同
    /// 它的两个类型（`FeatureCard` / `FeatureCardRow`）已随段一起从 `ModuleSettingsSection` 删除，
    /// 「表里的键逐条解析得出来」这一半因此不再可断言（表不存在）；留下的是三件别处没钉住的事：
    ///
    /// ① **七条文案 key 已随段一起从 catalog 消失**（段头 / 段脚注 + 五条
    ///    `settings.features.effect.<键名>`）——用「zh-Hans 里解析不出来」判定。段在视图里、
    ///    单测看不见，「它的文案 key 不再可达」是「段真的没了」唯一可自动判定的形态；
    /// ② **五张卡各自的落点**（机制三那张枚举表逐条）：
    ///    - 终端 / 暂存器 / 剪贴板 → 「面板组件」节的宿主行（`hostPanelRows`，T5 那张表）；
    ///    - 统计 → 「首页组件」节的统计模块卡（接管真源 `enableStatsFeature` 本身就是它，
    ///      且统计只声明 `.home` → 组件页里它只有那一张卡）；
    ///    - 锁屏天气 → 锁屏设置页那一行（组件页不再提供开关）；
    /// ③ **锁屏天气这个键只剩一处 UI**：锁屏页那一行的键就是 `Defaults.Keys.enableLockScreenWeatherWidget`
    ///    那一个对象（`===`：另造同名字面量即红），标签字面量仍在 catalog 里解析得出（那一行还在）。
    ///
    /// 刻意**不**断的：`settings.features.effect.enableNotes` 与 `.showCalendar` 两条 key 仍在 catalog
    /// 里（前者是上一批「恢复笔记入口」的可逆保留，后者是首页日历行搬走时留下的旧 key）——本批的
    /// 删除清单只有那七条（docs/26 §已知限制 5）。
    ///
    /// **语言无关**（沿用 T6 修复）：负向断言与 `XCTAssertResolves` 取同一份 zh-Hans bundle，
    /// 本机语言环境不参与。
    ///
    /// **边界如实记**：视图层面的接线（组件页真的只画两节）没有自动化断言——与
    /// `testHostPanelRowKeysAreReallyInUseByTheTwoBackingViews` 那类「读生产常量」的口径同级，
    /// 屏上那一半靠上屏截图验收（`.workflow/p5-home-blocks/evidence/t4-*.png`，控制器取证）。
    func testFeatureSectionIsGoneAndItsOldKeysHaveASingleEntryPoint() {
        // ① 七条 key 已从 catalog 里删掉（段与表一起撤销）
        let removedKeys = [
            "settings.features.title",
            "settings.features.footer",
            "settings.features.effect.enableClipboardManager",
            "settings.features.effect.enableLockScreenWeatherWidget",
            "settings.features.effect.enableStatsFeature",
            "settings.features.effect.dynamicShelf",
            "settings.features.effect.enableTerminalFeature",
        ]
        for key in removedKeys {
            XCTAssertDoesNotResolve(key, "\(key) 仍解析得出 zh-Hans 文案——功能段的文案 key 没有随段一起删除")
        }

        // ②a 终端 / 暂存器 / 剪贴板：落点是「面板组件」节的宿主行（T5 那张表）
        let hostIDs = Set(ModuleSettingsSection.hostPanelRows.map(\.id))
        XCTAssertTrue(
            hostIDs.isSuperset(of: ["dynamicShelf", "enableTerminalFeature", "enableClipboardManager"]),
            "终端 / 暂存器 / 剪贴板三张由「面板组件」节的宿主行承接（D-06 的枚举表）"
        )

        // ②b 统计：落点是「首页组件」的统计模块卡——接管真源就是同一个键，它只声明 home
        XCTAssertEqual(
            StatsModule.takeoverEnableKey?.name,
            Defaults.Keys.enableStatsFeature.name,
            "统计卡的开关写的就是 `enableStatsFeature` —— 组件页不再需要第二张卡"
        )
        XCTAssertEqual(
            StatsModule.manifest.surfaces,
            [.home],
            "统计只声明首页面 → 组件页里它只在「首页组件」有一张卡（不会在面板组件节再来一张）"
        )

        // ②c 锁屏天气：组件页两张表里都没有这个键（那张重复卡已删、也没有被改挂到别处）
        let registeredOnComponentsPage = Set(ModuleSettingsSection.hostPanelRows.map(\.key.name))
            .union(ModuleSettingsSection.configControls.map(\.key))
        XCTAssertFalse(
            registeredOnComponentsPage.contains(Defaults.Keys.enableLockScreenWeatherWidget.name),
            "锁屏天气不再由「组件」页提供开关（重复卡已删，归位到锁屏设置页）"
        )

        // ③ 锁屏页那一行仍在：键是同一个对象，标签字面量在 catalog 里
        XCTAssertTrue(
            LockScreenSettings.lockScreenWeatherRowKey === Defaults.Keys.enableLockScreenWeatherWidget,
            "锁屏页那一行的键必须是 `Defaults.Keys` 里那一个对象（另造同名字面量即红）"
        )
        XCTAssertResolves("Show lock screen weather")
    }

    /// **首页日历行**（`HomeCalendarSettingsRow`）的两个 key 能解析，且它**不在**「面板组件」的宿主行表里。
    ///
    /// 用户 2026-09-30：「首页的日历组件也要在首页组件控制区域进行开关控制」——它从「功能」段那张
    /// 卡搬进「首页组件」节，**键仍是同一个 `showCalendar`**（没有第二份状态）。这条用例钉三件事：
    /// ① 文案 key 能解析；② 它的效果行走 `settings.modules.*` 这一族（不再是功能段的
    /// `settings.features.effect.<键名>`）；③ 它**没有挂在别的表上**（两边都挂 = 同一页两个开关管一件事）
    /// ——功能段那张表已随段删除（见上一条用例），剩下可查的是「面板组件」的宿主行表（日历不是面板
    /// 宿主元素）。
    func testHomeCalendarSettingsRowKeysResolveAndItIsNotAHostPanelRow() {
        XCTAssertResolves(HomeCalendarSettingsRow.effectKey)
        XCTAssertResolves(HomeCalendarSettingsRow.nameKey)

        XCTAssertEqual(
            HomeCalendarSettingsRow.effectKey,
            "settings.modules.calendarRow.effect",
            "效果行 key 的形态与本页其余组件文案一致（settings.modules.*）"
        )
        XCTAssertFalse(
            ModuleSettingsSection.hostPanelRows.contains { $0.key.name == Defaults.Keys.showCalendar.name },
            "首页日历行不是面板宿主元素（它在「首页组件」节末），不该出现在宿主行表里"
        )
    }

    // MARK: - 「面板组件」节的宿主行（p5-home-blocks / T5）

    /// **宿主行四条**的键解析 + 名称字面量逐字钉死（docs/29-home-blocks-and-panel.md §做法 机制三 /
    /// D-07、D-08）。
    ///
    /// 数据源是生产表本身（`ModuleSettingsSection.hostPanelRows`——为了这条用例它没写成 `private`，
    /// 与 `effectKeysByModuleID` / `configControls` 同一条口径）：表里把 id / 键 /
    /// 文案 key / 顺序写错，这条都会红。
    ///
    /// 四条各自钉三件事：
    /// - **顺序与键名**：枚举表那四条 = 暂存器 / 终端 / 剪贴板 / 取色器——面板上由上游 `Defaults`
    ///   直接门控、不经模块注册表的 tab / 图标就这四个，顺序就是节里那四行的顺序；
    /// - **`id` 与键名同源**（id 就是上游键名），且 `key` 就是
    ///   `Defaults.Keys` 里那**一个对象**（`===`：将来谁把它换成另造的同名字面量，这条红）；
    /// - **`nameKey` 在 zh-Hans 里解析得出**，且就是那四条上游字面量：名称写串成**另一条已存在的
    ///   key**（比如指到 `Enable Notes`）时解析断言抓不到，字面量断言抓得到。
    ///
    /// 另有一条**刻意不在表里**的锚：用量（`enableLLMUsageFeature`）——上一批「删页留码」已裁决它
    /// 默认关、无入口、面板上不会出现（docs/26 D-08），本节重新登记一行就是与那条已定决策矛盾。
    func testHostPanelRowsPinTheFourHostKeysAndResolveNameKeys() {
        let rows = ModuleSettingsSection.hostPanelRows

        XCTAssertEqual(
            rows.map(\.id),
            ["dynamicShelf", "enableTerminalFeature", "enableClipboardManager", "enableColorPickerFeature"],
            "四条宿主行的顺序与键名（枚举表：暂存器 / 终端 / 剪贴板 / 取色器）"
        )
        XCTAssertEqual(
            rows.map(\.nameKey),
            ["Enable shelf", "Enable terminal", "Enable Clipboard Manager", "Enable Color Picker"],
            "名称逐字沿用上游设置页那一项的字面量（用户在别处认识的词与这里必须是同一个 key）"
        )

        for row in rows {
            XCTAssertEqual(row.key.name, row.id, "id 就是上游键名")
            XCTAssertResolves(row.nameKey)
        }

        XCTAssertTrue(rows[0].key === Defaults.Keys.dynamicShelf, "第一行（暂存器）的键")
        XCTAssertTrue(rows[1].key === Defaults.Keys.enableTerminalFeature, "第二行（终端）的键")
        XCTAssertTrue(rows[2].key === Defaults.Keys.enableClipboardManager, "第三行（剪贴板）的键")
        XCTAssertTrue(rows[3].key === Defaults.Keys.enableColorPickerFeature, "第四行（取色器）的键")

        XCTAssertFalse(
            rows.contains { $0.id == Defaults.Keys.enableLLMUsageFeature.name },
            "用量不进本节：上一批「删页留码」已裁决它默认关、无入口、面板上不会出现（docs/26 D-08）"
        )
    }

    /// **登记的键都真的在用**（T5 验收：「宿主行键解析」与「登记的键真的在用」两半里的后一半）：
    /// 四条宿主键必须落在两个消费方视图**真的在读**的门槛键名单里——
    /// `TabSelectionView.hostPanelGateKeys`（左列三条 tab）∪ `DynamicIslandHeader.hostPanelGateKeys`
    /// （右侧两枚图标）。
    ///
    /// **方向只有一个**（刻意写死）：本节登记的键都真的在用；**不是**「两个视图用到的全部门槛键都在
    /// 本节」——反方向在真实键集上不可达：镜子（首页组件的镜子卡）、计时器（计时器模块行）、齿轮与
    /// 三个状态指示器（各自设置页）、扩展 tab（扩展设置页）、用量（上一批裁决不进本节）都不在本表里，
    /// docs/29 §机制三那张枚举表逐条写明了归属（这正是那张表存在的理由，D-08）。
    ///
    /// 两份名单各自带注释写明**读取点在自己文件哪一行**（`tabs` 里那三个 `if` / `body` 里那两行
    /// `if`）：门槛删掉而不改名单，这条红；名单里混进没人读的键，同样红。
    func testHostPanelRowKeysAreReallyInUseByTheTwoBackingViews() {
        let registered = Set(ModuleSettingsSection.hostPanelRows.map(\.key.name))
        XCTAssertFalse(registered.isEmpty, "前置：宿主行表不能是空的")

        let inUse = Set(
            (TabSelectionView.hostPanelGateKeys + DynamicIslandHeader.hostPanelGateKeys).map(\.name)
        )
        XCTAssertFalse(inUse.isEmpty, "前置：两份消费方名单不能都是空的（否则下面的子集断言恒假）")

        for name in registered.sorted() {
            XCTAssertTrue(
                inUse.contains(name),
                "\(name) 登记在「面板组件」节，但不是 TabSelectionView / DynamicIslandHeader "
                    + "在读的门槛键——这一行拨下去面板上不会有任何变化（键错了 / 该行不该在本节）"
            )
        }
    }

    /// **宿主行的另一端**（T5 修复轮 P2）：协调器那张**视图归一化**表
    /// （`DynamicIslandViewCoordinator.hostSurfaceGateViews`）与设置页那四条宿主行必须是**同一批键**
    /// ——一端是「用户能拨的开关」，另一端是「拨完把停在被关视图上的面板收回首页」，两边各写一份
    /// 键表就会漂（枚举表已经把四条钉死，这里把两端钉在一起）。
    func testHostSurfaceGateViewsCoverTheSameFourKeysAsTheSettingsRows() {
        let gates = DynamicIslandViewCoordinator.hostSurfaceGateViews
        let rows = ModuleSettingsSection.hostPanelRows

        XCTAssertEqual(
            gates.map(\.id),
            rows.map(\.id),
            "归一化表的键与顺序 = 设置页四条宿主行（暂存器 / 终端 / 剪贴板 / 取色器）"
        )
        XCTAssertEqual(Set(gates.map(\.key.name)), Set(rows.map(\.key.name)), "同名的键也只能是同一批")

        // 每条都得真的门控到视图，且**一个视图只归一条**（否则「谁关掉了它」会有两个答案）
        var seen: [String: String] = [:]
        for gate in gates {
            XCTAssertFalse(gate.views.isEmpty, "\(gate.id) 没有登记它门控的视图——归一化对它就没有意义")
            for view in gate.views {
                XCTAssertNil(seen["\(view)"], "\(view) 同时挂在 \(seen["\(view)"] ?? "") 与 \(gate.id) 上")
                seen["\(view)"] = gate.id
            }
        }
        // 四条宿主键各自的视图逐个钉死（改映射必须改这条）
        XCTAssertEqual(gates.map(\.views), [[.shelf], [.terminal], [.notes, .clipboard], [.colorPicker]])
    }

    /// **宿主三 tab 并入面板排序**（p6-ui-polish / T9，docs/30-ui-polish-and-shelf.md §做法 机制七 /
    /// D-15、D-16；上面 T5 那条「宿主行只有开关、没有 ↑↓」的口径由此改写）：
    ///
    /// ① **宿主 id ↔ gate 键的映射**：`PanelHostTab`（排序词汇表）↔ `hostPanelRows`（登记表）↔
    ///    `TabSelectionView.hostPanelGateKeys`（视图真的在读的门槛键）三方按同一个键对象 / 键名钉住；
    /// ② **取色器不在排序名单**（它不是面板 tab：渲染在标题栏图标行，行上不该有死箭头）；
    /// ③ **默认序（`panelOrder` 为空）与改动前逐字一致**——输入是 `PanelTabSequence.slots(...)` 造出的
    ///    槽位骨架，每个参数的 gate 来处写在用例里（控制器裁决 2：以改动前的**实际渲染顺序**为准，
    ///    不照 docs/30 的描述序）；
    /// ④ **写表后消费点顺序跟随**：走真写路径（`ModuleSurfaceGroup.panel.writeOrderTable`）+ 真偏好键
    ///    （`Defaults[.panelOrder]`），面板条（`sequence`）与设置页名单（`panelMovableIDs`）读同一张表、
    ///    同一个顺序；不可排项（用量 / 扩展 tab）的**槽位索引不动**；
    /// ⑤ 剪贴板**图标模式**下那条 tab 不在条上：`clipboard` 的排序值没有接收者、不影响别的项。
    func testHostPanelRowsJoinThePanelOrderAndDefaultSequenceIsUnchanged() {
        // ① 宿主 id ↔ gate 键：id 在 `PanelHostTab`、键在 `hostPanelRows`，映射两边只能是同一批。
        XCTAssertEqual(
            PanelHostTab.allCases.map(\.id),
            ["shelf", "clipboard", "terminal"],
            "id 取 docs/30 §机制七 的三个字面量（与 ContentView.selectedPanelTabKey 的宿主页键同一批词）"
        )
        XCTAssertEqual(PanelHostTab.shelf.gateKey.name, "dynamicShelf", "暂存器 tab 的门槛键")
        XCTAssertEqual(PanelHostTab.clipboard.gateKey.name, "enableClipboardManager", "剪贴板 tab 的门槛键")
        XCTAssertEqual(PanelHostTab.terminal.gateKey.name, "enableTerminalFeature", "终端 tab 的门槛键")

        let hostRows = ModuleSettingsSection.hostPanelRows
        XCTAssertEqual(
            hostRows.compactMap(\.panelTab).map(\.id),
            ["shelf", "terminal", "clipboard"],
            "登记表序仍是枚举表序（暂存器 / 终端 / 剪贴板）——渲染序由排序键决定，不是这一行"
        )
        XCTAssertTrue(hostRows[0].key === PanelHostTab.shelf.gateKey, "暂存器：登记的是同一个键对象（.dynamicShelf）")
        XCTAssertTrue(hostRows[1].key === PanelHostTab.terminal.gateKey, "终端：.enableTerminalFeature")
        XCTAssertTrue(hostRows[2].key === PanelHostTab.clipboard.gateKey, "剪贴板：.enableClipboardManager")
        XCTAssertEqual(
            Set(PanelHostTab.allCases.map(\.gateKey.name)),
            Set(TabSelectionView.hostPanelGateKeys.map(\.name)),
            "词汇表的 gate 键 = 面板条真的在读的那份门槛键名单（视图侧删了读取点就会红）"
        )

        // ② 取色器不在排序名单：表里那一行没有排序 id，`panelOrder` 的合法词表里也没有它的键名。
        XCTAssertNil(hostRows[3].panelTab, "取色器不是面板 tab：没有排序 id（docs/30 §明确不做 3 / 备选⑧）")
        XCTAssertEqual(hostRows[3].key.name, "enableColorPickerFeature")
        XCTAssertFalse(
            PanelHostTab.allCases.contains { $0.id == hostRows[3].key.name },
            "取色器的键名不进 `panelOrder` 的 id 词表"
        )

        // ③ 默认序逐字（槽位骨架 = 改动前 `tabs` 的拼装顺序；每个槽位参数的 gate 来处见下方注释）。
        let todoID = "com.cmeng.gourd.todos"
        let progressID = "com.cmeng.gourd.progress"
        let defaultSlots = PanelTabSequence.slots(
            home: "home",             // homeTabVisible = enableMinimalisticUI || showStandardMediaControls || showCalendar || showMirror
            shelf: "shelf",           // dynamicShelf
            usage: "usage",           // enableLLMUsageFeature
            clipboard: "clipboard",   // enableClipboardManager && clipboardDisplayMode == .separateTab
            terminal: "terminal",     // enableTerminalFeature
            extensions: [(id: "extension-probe-t9", payload: "extension-probe-t9")],  // enableThirdPartyExtensions && enableExtensionNotchExperiences && enableExtensionNotchTabs
            modules: [                // ModuleRegistry.tabEntries（投影序：todos 20 → progress 30）
                (id: todoID, defaultOrder: 20, payload: todoID),
                (id: progressID, defaultOrder: 30, payload: progressID),
            ]
        )
        XCTAssertEqual(
            PanelTabSequence.sequence(defaultSlots, panelOrder: [:]),
            ["home", "shelf", "usage", "clipboard", "terminal", "extension-probe-t9", todoID, progressID],
            "默认序 = 改动前逐字：Home → 暂存器 → 用量 → 剪贴板 → 终端 → 扩展 tab → 模块 tab"
        )

        // 只留宿主三 tab + 模块（用量 / 扩展关着）——改动前那一条最常见配置的顺序同样逐字。
        let plainSlots = PanelTabSequence.slots(
            home: "home",
            shelf: "shelf",
            usage: nil,
            clipboard: "clipboard",
            terminal: "terminal",
            extensions: [],
            modules: [
                (id: todoID, defaultOrder: 20, payload: todoID),
                (id: progressID, defaultOrder: 30, payload: progressID),
            ]
        )
        XCTAssertEqual(
            PanelTabSequence.sequence(plainSlots, panelOrder: [:]),
            ["home", "shelf", "clipboard", "terminal", todoID, progressID],
            "用量 / 扩展关着时的默认序（改动前：Home → 暂存器 → 剪贴板 → 终端 → 模块）"
        )

        // ④ 写表后跟随：真写路径 + 真偏好键（`panelOrder`）。
        let keys = [Defaults.Keys.panelOrder.name]
        let snapshot = snapshotValues(of: keys)
        defer { restoreValues(snapshot, for: keys) }
        Defaults[.panelOrder] = [:]

        let moduleEntries = [
            PanelTabSequence.Entry(id: todoID, defaultOrder: 20),
            PanelTabSequence.Entry(id: progressID, defaultOrder: 30),
        ]
        XCTAssertEqual(
            ModuleSettingsSection.panelMovableIDs(moduleEntries: moduleEntries, panelOrder: [:]),
            ["shelf", "clipboard", "terminal", todoID, progressID],
            "设置页默认名单：前三行是宿主三 tab（T9 计划「前三行宿主行有 ↑↓」的那一条）"
        )

        let movableIDs = ["shelf", "clipboard", "terminal", todoID, progressID]
        let moved = ModuleSurfaceGroup.orderTable(ids: movableIDs, moving: "shelf", direction: .down)
        XCTAssertEqual(
            moved,
            ["clipboard": 0, "shelf": 1, "terminal": 2, todoID: 3, progressID: 4],
            "把「架子」下移一格：整表序号（既有 `writeOrderTable` 的翻盘算式）+ 宿主 id 是合法键"
        )
        ModuleSurfaceGroup.panel.writeOrderTable(moved ?? [:])
        XCTAssertEqual(Defaults[.panelOrder], moved ?? [:], "写的就是 `panelOrder` 这个键（重启后读到的同一份）")

        XCTAssertEqual(
            ModuleSettingsSection.panelMovableIDs(moduleEntries: moduleEntries, panelOrder: Defaults[.panelOrder]),
            ["clipboard", "shelf", "terminal", todoID, progressID],
            "设置页名单跟随新表"
        )
        XCTAssertEqual(
            PanelTabSequence.sequence(defaultSlots, panelOrder: Defaults[.panelOrder]),
            ["home", "clipboard", "usage", "shelf", "terminal", "extension-probe-t9", todoID, progressID],
            "面板条跟随新表；用量（索引 2）与扩展 tab（索引 5）原地不动"
        )

        // 消费点对表：面板条的**可排子序列**与设置页名单逐字相同（两处不存在第二套口径）。
        let barSortable = PanelTabSequence.sequence(defaultSlots, panelOrder: Defaults[.panelOrder])
            .filter { $0 != "home" && $0 != "usage" && $0 != "extension-probe-t9" }
        XCTAssertEqual(
            barSortable,
            ModuleSettingsSection.panelMovableIDs(moduleEntries: moduleEntries, panelOrder: Defaults[.panelOrder]),
            "条的排序子序列（宿主三 + 模块）= 设置页名单"
        )

        // 取色器没有死箭头：它不在可排名单里，翻盘算式对它是**空操作**（名单没变 → nil → 不写盘）。
        XCTAssertNil(
            ModuleSurfaceGroup.orderTable(
                ids: ModuleSettingsSection.panelMovableIDs(moduleEntries: moduleEntries, panelOrder: Defaults[.panelOrder]),
                moving: "enableColorPickerFeature",
                direction: .up
            ),
            "取色器不在名单里：没有 ↑↓ 行、也没有可写的表"
        )

        // ⑤ 剪贴板图标模式（`clipboardDisplayMode != .separateTab`）：条上没有 `clipboard` 槽位，
        //    表里残留的它没有接收者，不影响别的项（失败信号「排序值异常影响 tab 条」的反例）。
        let iconModeSlots = PanelTabSequence.slots(
            home: "home",
            shelf: "shelf",
            usage: nil,
            clipboard: nil,
            terminal: "terminal",
            extensions: [],
            modules: [
                (id: todoID, defaultOrder: 20, payload: todoID),
                (id: progressID, defaultOrder: 30, payload: progressID),
            ]
        )
        XCTAssertEqual(
            PanelTabSequence.sequence(
                iconModeSlots,
                panelOrder: ["clipboard": -1, "shelf": 0, "terminal": 1, todoID: 2, progressID: 3]
            ),
            ["home", "shelf", "terminal", todoID, progressID],
            "图标模式：剪贴板不在条上，它的排序值不改变 tab 条的先后"
        )
    }

    /// **宿主元素的视图归一化**（T5 修复轮 P2 的靶子）：四个宿主键关掉时，面板不许停在被它们门控的
    /// 视图上——「键变化」那一路（订阅）与「被排除的视图不许被选中」那一路（`currentView` 的 `didSet`
    /// 守卫）各钉一条。
    ///
    /// 三层断言：**纯函数**（四条映射逐条 + 反例）→ **端到端**（真协调器 + 真偏好键：停在 `.shelf`
    /// 把暂存器关掉 → 收回 `.home`）→ **反例**（关取色器不许动 `.terminal`；键关着时 `.terminal`
    /// 连选都选不上）。
    ///
    /// 卫生（同 T3 三档用例）：`snapshotTimerSurface()` 记下协调器两个字段 + `enableMinimalisticUI`
    /// 的持久域原值（极简 UI 开着会把非 `.home` 的选中打回首页，必须先置假），四个宿主键走
    /// `snapshotValues(of:)` / `restoreValues(_:for:)`；`defer` 里**先还原键、再还原字段**——反了的话
    /// 还原键会触发订阅、把刚写回的 `currentView` 又改掉。订阅是异步的（`receive(on: DispatchQueue.main)`），
    /// 故用 `waitUntil` 等条件成立。
    func testHostSurfaceGateNormalizationResetsGatedOffViews() async {
        // ① 纯函数：四条映射各一条
        XCTAssertTrue(
            DynamicIslandViewCoordinator.isHostSurfaceGatedOff(.shelf, offKeyNames: ["dynamicShelf"]),
            "暂存器关着 → `.shelf` 不许停留"
        )
        XCTAssertTrue(
            DynamicIslandViewCoordinator.isHostSurfaceGatedOff(.terminal, offKeyNames: ["enableTerminalFeature"]),
            "终端关着 → `.terminal` 不许停留"
        )
        XCTAssertTrue(
            DynamicIslandViewCoordinator.isHostSurfaceGatedOff(.notes, offKeyNames: ["enableClipboardManager"]),
            "剪贴板关着 → `.notes`（面板 tab 那一路）不许停留"
        )
        XCTAssertTrue(
            DynamicIslandViewCoordinator.isHostSurfaceGatedOff(.clipboard, offKeyNames: ["enableClipboardManager"]),
            "剪贴板关着 → `.clipboard`（刘海图标 notchTab 那一路）不许停留"
        )
        XCTAssertTrue(
            DynamicIslandViewCoordinator.isHostSurfaceGatedOff(.colorPicker, offKeyNames: ["enableColorPickerFeature"]),
            "取色器关着 → `.colorPicker` 不许停留"
        )

        // 反例三档：键都开着时五个视图全放行；`.home` 是兜底、永不被排除；计时器不在本表
        // （它的收回走既有那条 `handleTimerFeatureToggle()`，两处不重复）。
        let allGateNames = Set(DynamicIslandViewCoordinator.hostSurfaceGateViews.map(\.id))
        for view in [NotchViews.shelf, .terminal, .notes, .clipboard, .colorPicker] {
            XCTAssertFalse(
                DynamicIslandViewCoordinator.isHostSurfaceGatedOff(view, offKeyNames: []),
                "\(view)：四个键都开着时必须放行"
            )
        }
        XCTAssertFalse(
            DynamicIslandViewCoordinator.isHostSurfaceGatedOff(.home, offKeyNames: allGateNames),
            "`.home` 是兜底，永不被排除"
        )
        XCTAssertFalse(
            DynamicIslandViewCoordinator.isHostSurfaceGatedOff(.timer, offKeyNames: allGateNames),
            "计时器不在本表（同键的收回走计时器自己那一处）"
        )

        // ② 端到端：真协调器 + 真偏好键
        let hostKeys = DynamicIslandViewCoordinator.hostSurfaceGateViews.map(\.id)
        let originals = snapshotValues(of: hostKeys)
        let surface = snapshotTimerSurface()
        defer {
            restoreValues(originals, for: hostKeys)   // 先键
            restoreTimerSurface(surface)              // 再字段（最后写 currentView，顺序见用例注释）
        }
        let coordinator = DynamicIslandViewCoordinator.shared
        Defaults[.enableMinimalisticUI] = false
        Defaults[.dynamicShelf] = true
        Defaults[.enableTerminalFeature] = true
        Defaults[.enableClipboardManager] = true
        Defaults[.enableColorPickerFeature] = true

        coordinator.currentView = .shelf
        XCTAssertEqual(coordinator.currentView, .shelf, "前置：四个键都开着时 `.shelf` 是合法选中")

        Defaults[.dynamicShelf] = false                 // 设置页「面板组件」节的那一次拨动
        let reset = await waitUntil { coordinator.currentView == .home }
        XCTAssertTrue(reset, "暂存器关掉 → 正停着的 `.shelf` 必须收回首页（订阅那一路）")

        // 反例：关一个**不门控当前视图**的键，不许动它（防「一律打回首页」）
        coordinator.currentView = .terminal
        Defaults[.enableColorPickerFeature] = false
        await yieldTurns()
        XCTAssertEqual(coordinator.currentView, .terminal, "关取色器不许动 `.terminal`（只收被同一个键门控的视图）")

        // ③ 选中那一端的守卫：键关着时连选都选不上（`openShelfByDefault` / 剪贴板快捷键那两条
        //    入口把面板开到已关元素上的同一条兜底）
        Defaults[.enableTerminalFeature] = false
        let terminalReset = await waitUntil { coordinator.currentView == .home }
        XCTAssertTrue(terminalReset, "终端关掉 → 正停着的 `.terminal` 收回首页")
        coordinator.currentView = .terminal
        XCTAssertEqual(coordinator.currentView, .home, "终端键关着 → `.terminal` 连选都选不上（didSet 守卫）")
        Defaults[.enableClipboardManager] = false
        let clipboardReset = await waitUntil { coordinator.currentView == .home }
        XCTAssertTrue(clipboardReset, "剪贴板关掉 → 当前视图（此刻是 `.home`）保持首页")
        coordinator.currentView = .notes
        XCTAssertEqual(coordinator.currentView, .home, "剪贴板键关着 → `.notes`（面板 tab 那一路）也选不上")
        coordinator.currentView = .clipboard
        XCTAssertEqual(coordinator.currentView, .home, "剪贴板键关着 → `.clipboard`（刘海图标那一路）也选不上")
    }

    /// 三个接管模块的卡片文案也能解析：名称 key 取**真模块的 manifest**（卡片上那行名称走
    /// `ModuleRegistry.label(for:)`，读的就是它），效果行是 T6 新增的那三条。
    ///
    /// 效果行这三条**不再是用例里的字面量**（T6 修复）：它们改由
    /// `testModuleEffectKeysMatchTableAndCatalog` 从生产映射表里取，映射侧写错会红——
    /// 原先映射是宿于 `private struct ModuleSettingsCard` 的私有 switch，用例够不到，
    /// 「把 `settings.modules.effect.music` 改成错字」是全绿的（T6 报告 §3 变异 ②b）。
    /// 本用例保留「三条 key 在 catalog 里解析得出」这一半，值那一半交给映射表用例。
    func testTakeoverModuleCardKeysResolve() throws {
        // 日历（T6）与统计（p3-widgets / T2）也进来了：本用例的名单 = **接管模块**的名单（五个），
        // 不要求它们有「效果行」（日历卡没有 `effectKeysByModuleID` 那一条：出现位置已经写在 summary
        // 里；统计同款——它的出现位置同样写在 summary 里）。
        for manifest in [
            TimerModule.manifest, MirrorModule.manifest, MusicModule.manifest,
            CalendarModule.manifest, StatsModule.manifest,
        ] {
            let nameKey = try XCTUnwrap(manifest.name.key, "\(manifest.id) 的名称 key 必须写成 Localizable key")
            XCTAssertEqual(nameKey, "module.\(manifest.shortID).name", "名称 key 形态与 label(for:) 同源")
            XCTAssertResolves(nameKey)
        }

        for key in [
            "settings.modules.effect.timer",
            "settings.modules.effect.mirror",
            "settings.modules.effect.music",
        ] {
            XCTAssertResolves(key)
        }
    }

    /// 组件卡的「效果 / 出现位置」映射（`ModuleSettingsSection.effectKeysByModuleID`，T6 修复）：
    /// **表是唯一取值处**，用例直接迭代生产表——
    ///
    /// ① 表里每个值都能在宿主 bundle 里解析出 zh-Hans 文案（键写错 / 文案没进 catalog → 红），
    ///    并钉住 `settings.modules.effect.<模块短名>` 的 key 形态（值被写串成另一条**已存在**的
    ///    key——比如 todos 指到 progress 那条——解析断言抓不到，这一条抓得到）；
    /// ② 接管三块的值逐条钉住（`TimerModule.manifest.id` → `settings.modules.effect.timer`，镜子 /
    ///    音乐同形）——这一条就是上一轮缺的那条断言；
    /// ③ 表里每个**模块 id** 都是已注册模块的 id（模块改名 / 表里 id 写错 → 红）。
    ///
    /// **③ 先 `register` 再取集合**：`setUp` 的 `deactivateAll()` 把 `manifests` 一起清空了
    /// （注册表因此每次都是空的），不注册就取集合会恒为空表、断言恒红。注册用
    /// `enabled: { _ in true }` 过门（不读任何偏好键、不落状态），且**不调 `bootstrap()`**：
    /// 本用例只看 manifest 的 id 集合，不激活、不碰上游键。
    ///
    /// **不钉表的条数**：`LauncherModule` 这类没有「效果 / 出现位置」一行的模块**合法地**不在表里
    /// （未命中 = 整行不显示），拿 `builtinModules.count` 去比会把它变成假红。漏一条模块的效果行
    /// 由「组件页肉眼一条」兜底，见文件头 T6 段。
    func testModuleEffectKeysMatchTableAndCatalog() {
        let table = ModuleSettingsSection.effectKeysByModuleID

        // ③ 表里的模块 id 必须都是已注册模块（注册表是单例，先补注册再取 id 集合）。
        let registry = ModuleRegistry.shared
        registry.register(KernelBootstrap.builtinModules, enabled: { _ in true })
        let registeredIDs = Set(registry.manifests.keys)
        XCTAssertFalse(registeredIDs.isEmpty, "前置：注册后不能还是空表（setUp 刚清过注册表）")
        for moduleID in table.keys.sorted() {
            XCTAssertTrue(
                registeredIDs.contains(moduleID),
                "\(moduleID) 不是已注册模块的 id（模块改名漏改表 / 表里 id 写错？）"
            )
        }

        // ① 每个值都能解析出 zh-Hans 文案（语言锁在 `XCTAssertResolves` 里）。
        for (moduleID, effectKey) in table.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(
                effectKey,
                "settings.modules.effect." + String(moduleID.split(separator: ".").last ?? ""),
                "\(moduleID) 的效果行 key 形态：`settings.modules.effect.<模块短名>`"
            )
            XCTAssertResolves(effectKey)
        }

        // ② 接管三块逐条钉死（表里把这三条写错、或 key 形态被改，都会红）。
        XCTAssertEqual(
            table[TimerModule.manifest.id], "settings.modules.effect.timer",
            "计时器的效果行 key——上一轮这条在用例里是字面量，映射侧写错抓不到"
        )
        XCTAssertEqual(
            table[MirrorModule.manifest.id], "settings.modules.effect.mirror",
            "镜子的效果行 key（同形）"
        )
        XCTAssertEqual(
            table[MusicModule.manifest.id], "settings.modules.effect.music",
            "音乐的效果行 key（同形）"
        )
    }

    /// 回弹两档仍成立（D-13 / docs/20 §做法 机制七），这里用**四个真模块的真源键**再钉一遍：
    /// 组件卡把它们的真源键交给 `preferenceToWrite` 时必须拿到 `nil`（**什么都不写**）。
    ///
    /// 注意这条钉的是**策略函数**，不是视图接线：卡里「回弹时去问策略、而不是无条件写 false」
    /// 那一句没有自动化断言（视图的 `Binding` 闭包不可直接驱动——见 T6 报告的变异记录 ①）。
    func testRollbackStaysNilForRealTakeoverKeys() {
        for key in [
            TimerModule.takeoverEnableKey,
            MirrorModule.takeoverEnableKey,
            MusicModule.takeoverEnableKey,
            StatsModule.takeoverEnableKey,
        ] {
            XCTAssertNotNil(key, "四个接管模块必须声明真源键（声明缺失时它就不是接管模块了）")
            XCTAssertNil(
                ModuleEnablementRollback.preferenceToWrite(takeoverKey: key),
                "接管模块的回弹是空操作——写回偏好等于因为激活失败把用户的功能关了"
            )
        }

        XCTAssertEqual(
            ModuleEnablementRollback.preferenceToWrite(takeoverKey: nil),
            false,
            "非接管模块照旧回弹（把用户的开关拨回去）"
        )
    }

    // MARK: - 组件页两节：分组 / 面板排序 / 两节各自的开关（p3-widgets / T3）

    /// 两节的判据就是 `home` / `expanded` 这两个 surface，且**每一节在真模块里都找得到归属**
    /// （判据写在 `ModuleSurfaceGroup.surface` 上，表侧写错——比如把 panel 接到 `.compact`——
    /// 真模块的声明就对不上了）。
    func testSurfaceGroupCriteriaMatchRealModuleDeclarations() {
        XCTAssertEqual(ModuleSurfaceGroup.allCases.map(\.surface), [.home, .expanded], "两节的判据与顺序")
        XCTAssertEqual(ModuleSurfaceGroup.allCases.map(\.rawValue), ["home", "panel"])

        let manifests = [
            TodosModule.manifest,
            NotificationsModule.manifest,
            ProgressModule.manifest,
            StatsModule.manifest,
            MusicModule.manifest,
            MirrorModule.manifest,
            FrontAppModule.manifest,
            LauncherModule.manifest,
            ShortcutsModule.manifest,
            CalendarModule.manifest,
            TimerModule.manifest,
        ]
        for manifest in manifests {
            let groups = ModuleSurfaceGroup.allCases.filter { manifest.surfaces.contains($0.surface) }
            XCTAssertFalse(groups.isEmpty, "\(manifest.id) 两节都进不去（既没声明 home 也没声明 expanded）")
        }

        // 「同一个模块可能同时在两节」有实例：待办 / 通知声明 home + expanded → 两节各一行。
        for dual in [TodosModule.manifest, NotificationsModule.manifest] {
            XCTAssertEqual(
                ModuleSurfaceGroup.allCases.filter { dual.surfaces.contains($0.surface) },
                [.home, .panel],
                "\(dual.id) 应同时在两节里（节头那句「可能同时在两节」的实例）"
            )
        }
    }

    /// 四条节文案（两节各一条标题 + 一条脚注）在 zh-Hans 里解析得出——节头那句
    /// 「同一个模块可能同时在两节，各自的开关只管各自的 surface」就是脚注里写的。
    func testSurfaceGroupTextsResolve() {
        for group in ModuleSurfaceGroup.allCases {
            XCTAssertResolves(group.titleKey)
            XCTAssertResolves(group.footerKey)
        }
    }

    /// `panelRank`（面板组排序的**唯一算式**）：用户覆盖 → 默认序号 → `Int.max`（没有 placement）。
    func testPanelRankPrefersUserOverrideThenPlacementThenLast() {
        let overrides = ["a": 99, "b": 1]
        XCTAssertEqual(ModuleRegistry.panelRank("a", defaultOrder: 10, panelOrder: overrides), 99, "覆盖值优先")
        XCTAssertEqual(ModuleRegistry.panelRank("c", defaultOrder: 10, panelOrder: overrides), 10, "缺键回落默认序号")
        XCTAssertEqual(ModuleRegistry.panelRank("d", defaultOrder: Int.max, panelOrder: overrides), Int.max, "没有 placement → 排最后")
        XCTAssertEqual(ModuleRegistry.panelRank("a", defaultOrder: 10, panelOrder: [:]), 10, "空表 = 全回落默认")
    }

    /// `panelOrder` 影响 `tabEntries` 的顺序（端到端：真注册表 + 假模块 + 真偏好键）。
    /// 「重启后仍按它」的判据是这一条 + `testPanelOrderKeyRoundTripsThroughTheStore`（同一个键）。
    func testPanelOrderReordersTabEntries() async {
        let keys = [Defaults.Keys.panelOrder.name]
        let snapshot = snapshotValues(of: keys)
        defer { restoreValues(snapshot, for: keys) }

        let registry = ModuleRegistry.shared
        Defaults[.panelOrder] = [:]

        registry.register([SurfacePanelProbeA.self, SurfacePanelProbeB.self], enabled: { _ in true })
        await registry.bootstrap()

        // 缺键：按 `defaultPlacement.order`（A = 10 → B = 20）。
        XCTAssertEqual(registry.tabEntries.map(\.id), [surfaceAID, surfaceBID], "缺键时按 defaultPlacement.order")

        Defaults[.panelOrder] = [surfaceAID: 20, surfaceBID: 10]
        XCTAssertEqual(registry.tabEntries.map(\.id), [surfaceBID, surfaceAID], "panelOrder 覆盖后顺序翻转")

        // 只覆盖一个：被覆盖的排到另一个前面，另一个仍拿自己的默认序号。
        Defaults[.panelOrder] = [surfaceAID: -1]
        XCTAssertEqual(registry.tabEntries.map(\.id), [surfaceAID, surfaceBID], "只覆盖一个时另一个照旧回落默认序号")
    }

    /// `panelOrder` 键的**新键契约**：名字 + 声明默认值（空表 = 用户未表达）+ 序列化往返。
    ///
    /// 往返走一个**临时 suite**（不碰开发机真实域，同 `ModuleKernelTests` 的 `homeBlockOrder` 口径）。
    func testPanelOrderKeyRoundTripsThroughTheStore() throws {
        XCTAssertEqual(Defaults.Keys.panelOrder.name, "panelOrder")
        XCTAssertTrue(Defaults.Keys.panelOrder.defaultValue.isEmpty, "缺键 = 用户未表达（空表）")

        let suiteName = "com.cmeng.gourd.tests.panelOrder"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { suite.removePersistentDomain(forName: suiteName) }

        let key = Defaults.Key<[String: Int]>("panelOrder", default: [:], suite: suite)
        XCTAssertTrue(Defaults[key].isEmpty, "缺键时是空表")
        Defaults[key] = ["com.cmeng.gourd.probe-surface-a": 2, "com.cmeng.gourd.probe-surface-b": 0]
        XCTAssertEqual(
            Defaults[key],
            ["com.cmeng.gourd.probe-surface-a": 2, "com.cmeng.gourd.probe-surface-b": 0],
            "写盘 → 读回逐字相同（重启后读到的就是这一份）"
        )
    }

    /// 两组写盘**互不影响**：顺序键是两个（`homeBlockOrder` / `panelOrder`）、摘除名单也是两张——
    /// 移动 / 摘掉一组时，另一组一个字节都不动。算式用的是视图同一条
    /// （`ModuleSurfaceGroup.orderTable` + `writeOrderTable` / `setHidden`）。
    func testSurfaceOrderTablesAndHiddenListsAreIndependent() {
        let keys = [
            Defaults.Keys.homeBlockOrder.name,
            Defaults.Keys.panelOrder.name,
            Defaults.Keys.hiddenHomeModules.name,
            Defaults.Keys.hiddenPanelModules.name,
        ]
        let snapshot = snapshotValues(of: keys)
        defer { restoreValues(snapshot, for: keys) }

        Defaults[.homeBlockOrder] = [:]
        Defaults[.panelOrder] = [:]
        Defaults[.hiddenHomeModules] = []
        Defaults[.hiddenPanelModules] = []

        let ids = ["a", "b", "c"]
        // 翻盘算式：整表覆盖；名单没变（已在顶 / 底、id 不在名单里）返回 nil = 不写盘。
        XCTAssertEqual(ModuleSurfaceGroup.orderTable(ids: ids, moving: "b", direction: .up), ["b": 0, "a": 1, "c": 2])
        XCTAssertNil(ModuleSurfaceGroup.orderTable(ids: ids, moving: "a", direction: .up), "已在顶：不写盘")
        XCTAssertNil(ModuleSurfaceGroup.orderTable(ids: ids, moving: "c", direction: .down), "已在底：不写盘")
        XCTAssertNil(ModuleSurfaceGroup.orderTable(ids: ids, moving: "z", direction: .up), "不在名单里：不写盘")

        let moved = ModuleSurfaceGroup.orderTable(ids: ids, moving: "c", direction: .up) ?? [:]
        ModuleSurfaceGroup.panel.writeOrderTable(moved)
        XCTAssertEqual(Defaults[.panelOrder], ["a": 0, "c": 1, "b": 2], "面板那一组写的是 panelOrder")
        XCTAssertTrue(Defaults[.homeBlockOrder].isEmpty, "写面板那一组不动首页那一组")

        ModuleSurfaceGroup.home.writeOrderTable(moved)
        XCTAssertEqual(Defaults[.homeBlockOrder], ["a": 0, "c": 1, "b": 2], "首页那一组写的是 homeBlockOrder")
        XCTAssertEqual(Defaults[.panelOrder], ["a": 0, "c": 1, "b": 2], "……反过来也一样：面板那份没被动过")

        // 两张摘除名单同理：各写各的键。
        ModuleSurfaceGroup.home.setHidden(true, for: "a")
        XCTAssertEqual(Defaults[.hiddenHomeModules], ["a"])
        XCTAssertTrue(Defaults[.hiddenPanelModules].isEmpty, "关首页不动面板那张名单")

        ModuleSurfaceGroup.panel.setHidden(true, for: "a")
        XCTAssertEqual(Defaults[.hiddenPanelModules], ["a"])
        XCTAssertEqual(Defaults[.hiddenHomeModules], ["a"], "关面板不动首页那张名单")

        ModuleSurfaceGroup.home.setHidden(false, for: "a")
        XCTAssertTrue(Defaults[.hiddenHomeModules].isEmpty)
        XCTAssertEqual(Defaults[.hiddenPanelModules], ["a"], "取消首页摘除也不动面板那张名单")
    }

    /// 拨动的判据（纯函数，三档）：置开 → 启用 + 显示；置关且还有另一个面 → 只摘本节；
    /// 置关且本节是唯一的面 → 关模块本身。
    func testSurfaceSwitchEffectThreeWays() {
        XCTAssertEqual(ModuleSurfaceSwitch.effect(turningOn: true, hasOtherSurface: false), .enableAndShow)
        XCTAssertEqual(ModuleSurfaceSwitch.effect(turningOn: true, hasOtherSurface: true), .enableAndShow)
        XCTAssertEqual(ModuleSurfaceSwitch.effect(turningOn: false, hasOtherSurface: true), .hideOnSurface)
        XCTAssertEqual(ModuleSurfaceSwitch.effect(turningOn: false, hasOtherSurface: false), .disableModule)
    }

    /// 「还有另一个面」与开关 get 的判据（纯函数）：只有 home ↔ panel 互为他面，`compact` 不算
    /// （它没有自己的开关，算进去会让 `compact + home` 的模块两节都关不掉）。
    func testHasOtherSurfaceAndSwitchGet() {
        XCTAssertTrue(ModuleSurfaceGroup.hasOtherSurface([.home, .expanded], in: .home))
        XCTAssertTrue(ModuleSurfaceGroup.hasOtherSurface([.home, .expanded], in: .panel))
        // 每一节的「另一个面」就是另一节的那条判据（home ↔ panel）。
        XCTAssertTrue(ModuleSurfaceGroup.hasOtherSurface([.home], in: .panel), "面板那一边的「另一个面」是 home")
        XCTAssertTrue(ModuleSurfaceGroup.hasOtherSurface([.expanded], in: .home), "首页那一边的「另一个面」是 expanded")
        XCTAssertFalse(ModuleSurfaceGroup.hasOtherSurface([.home], in: .home), "只有 home → 首页是它唯一的面")
        XCTAssertFalse(ModuleSurfaceGroup.hasOtherSurface([.expanded], in: .panel), "只有 expanded → 面板是它唯一的面")
        XCTAssertFalse(ModuleSurfaceGroup.hasOtherSurface([.home, .compact], in: .home), "compact 不是「另一个面」")
        XCTAssertFalse(ModuleSurfaceGroup.hasOtherSurface([.expanded, .compact], in: .panel))
        XCTAssertFalse(ModuleSurfaceGroup.hasOtherSurface([], in: .home))

        XCTAssertTrue(ModuleSurfaceGroup.isOn(moduleEnabled: true, isHidden: false))
        XCTAssertFalse(ModuleSurfaceGroup.isOn(moduleEnabled: true, isHidden: true), "被本节摘掉 → 这一节的开关是关的")
        XCTAssertFalse(ModuleSurfaceGroup.isOn(moduleEnabled: false, isHidden: false))
    }

    /// 摘除名单的增删（纯函数）：置真追加（不重复）、置假滤掉；未知 id 也照办（没有接收者，无害）。
    func testHiddenListUpdateIsIdempotent() {
        XCTAssertEqual(ModuleSurfaceGroup.updated([], id: "a", hidden: true), ["a"])
        XCTAssertEqual(ModuleSurfaceGroup.updated(["a"], id: "a", hidden: true), ["a"], "重复置真不追加第二份")
        XCTAssertEqual(ModuleSurfaceGroup.updated(["a", "b"], id: "a", hidden: false), ["b"])
        XCTAssertEqual(ModuleSurfaceGroup.updated(["a"], id: "z", hidden: false), ["a"])
        XCTAssertEqual(ModuleSurfaceGroup.updated(["a"], id: "z", hidden: true), ["a", "z"])
    }

    /// 两节各自的开关只管各自的 surface（端到端：`ModuleSurfaceToggleWriter.write`）：
    /// 双面模块在**首页那一节**被关掉 → 只写 `hiddenHomeModules`（模块仍 `.active`、面板 tab 照旧、
    /// 启用真源一个字节没动）；再打开 → 首页块回来、别的键仍没被动过。
    func testHomeSwitchOnDualSurfaceModuleKeepsItsPanelTab() async {
        let keys = [
            Defaults.Keys.hiddenHomeModules.name,
            Defaults.Keys.hiddenPanelModules.name,
            Defaults.Keys.moduleEnableOverrides.name,
        ]
        let snapshot = snapshotValues(of: keys)
        defer { restoreValues(snapshot, for: keys) }

        let registry = ModuleRegistry.shared
        Defaults[.hiddenHomeModules] = []
        Defaults[.hiddenPanelModules] = []
        Defaults[.moduleEnableOverrides] = [:]

        registry.register([SurfaceDualProbeModule.self], enabled: { _ in true })
        await registry.bootstrap()
        XCTAssertEqual(registry.states[surfaceDualID], .active, "前置：双面模块已激活")
        XCTAssertEqual(registry.homeEntries.map(\.id), [surfaceDualID], "前置：首页投影里有它")
        XCTAssertEqual(registry.tabEntries.map(\.id), [surfaceDualID], "前置：面板投影里也有它")

        await ModuleSurfaceToggleWriter.write(
            false,
            manifest: SurfaceDualProbeModule.manifest,
            group: .home,
            registry: registry
        )

        XCTAssertEqual(Defaults[.hiddenHomeModules], [surfaceDualID], "关首页 = 只写首页那张摘除名单")
        XCTAssertTrue(Defaults[.hiddenPanelModules].isEmpty, "面板那张名单不动")
        XCTAssertNil(Defaults[.moduleEnableOverrides][surfaceDualID], "模块没被关（不写启用真源）")
        XCTAssertEqual(registry.states[surfaceDualID], .active, "模块仍活着")
        XCTAssertTrue(registry.homeEntries.isEmpty, "首页投影里没有了")
        XCTAssertEqual(registry.tabEntries.map(\.id), [surfaceDualID], "面板 tab 照旧")

        await ModuleSurfaceToggleWriter.write(
            true,
            manifest: SurfaceDualProbeModule.manifest,
            group: .home,
            registry: registry
        )

        XCTAssertTrue(Defaults[.hiddenHomeModules].isEmpty, "置开 = 取消本节的摘除")
        XCTAssertEqual(registry.homeEntries.map(\.id), [surfaceDualID], "首页块回来")
        XCTAssertEqual(registry.tabEntries.map(\.id), [surfaceDualID], "面板 tab 一直在")
    }

    /// 反方向：双面模块在**面板那一节**被关掉 → 只摘 tab，首页块照旧（`tabEntries` 里没有它、
    /// `homeEntries` 里还有它）。
    func testPanelSwitchOnDualSurfaceModuleKeepsItsHomeBlock() async {
        let keys = [
            Defaults.Keys.hiddenHomeModules.name,
            Defaults.Keys.hiddenPanelModules.name,
            Defaults.Keys.moduleEnableOverrides.name,
        ]
        let snapshot = snapshotValues(of: keys)
        defer { restoreValues(snapshot, for: keys) }

        let registry = ModuleRegistry.shared
        Defaults[.hiddenHomeModules] = []
        Defaults[.hiddenPanelModules] = []
        Defaults[.moduleEnableOverrides] = [:]

        registry.register([SurfaceDualProbeModule.self], enabled: { _ in true })
        await registry.bootstrap()

        await ModuleSurfaceToggleWriter.write(
            false,
            manifest: SurfaceDualProbeModule.manifest,
            group: .panel,
            registry: registry
        )

        XCTAssertEqual(Defaults[.hiddenPanelModules], [surfaceDualID], "关面板 = 只写面板那张摘除名单")
        XCTAssertTrue(Defaults[.hiddenHomeModules].isEmpty, "首页那张名单不动")
        XCTAssertNil(Defaults[.moduleEnableOverrides][surfaceDualID], "模块没被关")
        XCTAssertEqual(registry.states[surfaceDualID], .active, "模块仍活着")
        XCTAssertTrue(registry.tabEntries.isEmpty, "tab 投影里没有了")
        XCTAssertEqual(registry.homeEntries.map(\.id), [surfaceDualID], "首页块照旧")
    }

    /// 只有一个面的模块：关掉它就是关掉模块本身——写**既有启用真源**
    /// （`ModuleEnablementWrite` → 非接管模块写 `moduleEnableOverrides`），**不进摘除名单**
    /// （「不新增第二份状态」：进度 / 统计的开关口径）。
    func testSingleSurfaceModuleSwitchWritesTheExistingEnablementKey() async {
        let keys = [
            Defaults.Keys.hiddenPanelModules.name,
            Defaults.Keys.moduleEnableOverrides.name,
        ]
        let snapshot = snapshotValues(of: keys)
        defer { restoreValues(snapshot, for: keys) }

        let registry = ModuleRegistry.shared
        Defaults[.hiddenPanelModules] = []
        Defaults[.moduleEnableOverrides] = [:]

        registry.register([SurfacePanelProbeB.self], enabled: { _ in true })
        await registry.bootstrap()
        XCTAssertEqual(registry.tabEntries.map(\.id), [surfaceBID], "前置：面板投影里有它")

        await ModuleSurfaceToggleWriter.write(
            false,
            manifest: SurfacePanelProbeB.manifest,
            group: .panel,
            registry: registry
        )

        XCTAssertEqual(Defaults[.moduleEnableOverrides][surfaceBID], false, "非接管模块写 moduleEnableOverrides")
        XCTAssertTrue(Defaults[.hiddenPanelModules].isEmpty, "单面模块不进摘除名单（关掉就是关模块）")
        XCTAssertEqual(registry.states[surfaceBID], .disabled)
        XCTAssertTrue(registry.tabEntries.isEmpty, "投影随之消失")
        XCTAssertEqual(registry.homeEntries.map(\.id), [], "它本来就不在首页投影里")

        await ModuleSurfaceToggleWriter.write(
            true,
            manifest: SurfacePanelProbeB.manifest,
            group: .panel,
            registry: registry
        )

        XCTAssertEqual(Defaults[.moduleEnableOverrides][surfaceBID], true, "再打开 = 启用真源写回 true")
        XCTAssertEqual(registry.states[surfaceBID], .active)
        XCTAssertEqual(registry.tabEntries.map(\.id), [surfaceBID])
    }

    // MARK: - 架子统一命名（p6-ui-polish / T4）

    /// T4：架子统一命名——设置行「启用隔空投送与文件暂存」、短名「投送暂存」（`Shelf` 一个 key
    /// 同时供侧栏、页标题与 tab 文案，不拆 key），四条无中文的文案补齐，供应商回落不再直出英文。
    ///
    /// 判据读**两份 catalog 原文件**（设计文档 §接口与数据形状 · 机制三 命名表）：
    ///  1. 关键 key 的 zh-Hans / zh-Hant / en 逐条断言——`en` 的解析口径与运行时一致：有 `en` 条目
    ///     取条目值，缺条目时以 key 自身为值（catalog 的源语言口径；视图里都是 `Text(key)` 直查）；
    ///  2. 同一个 key 在两份 catalog 都有时逐语言一致（「两份 catalog 打架」的判据——`Shelf` 即其一）；
    ///  3. 全量负断言：每个 zh 值（含繁体形态）不得再出现「架子 / 搁板 / 暂存器」旧名。
    ///
    /// 面板 tab 只画图标（`TabButton` 不渲染 label），tab 名不在可观察判据里。
    func testShelfUserVisibleStringsUseTheUnifiedName() throws {
        let rootURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let catalogNames = ["DynamicIsland/Localizable.xcstrings", "Localizable.xcstrings"]
        var tables: [String: [String: [String: CatalogUnit]]] = [:]
        for name in catalogNames {
            tables[name] = try Self.catalogTable(at: rootURL.appendingPathComponent(name))
        }

        // 1) 命名表逐条：zh-Hans / zh-Hant / en 三个值都逐字断言。
        for row in Self.shelfNamingTable {
            let owners = catalogNames.filter { tables[$0]?[row.key] != nil }
            XCTAssertFalse(owners.isEmpty, "\(row.key) 在两份 catalog 里都查不到（key 被改名了？）")
            for name in owners {
                let languages = tables[name]?[row.key] ?? [:]
                XCTAssertNotNil(languages["zh-Hans"], "\(name) · \(row.key) 缺 zh-Hans 条目")
                XCTAssertEqual(languages["zh-Hans"]?.value, row.zhHans, "\(name) · \(row.key) 的 zh-Hans 不是统一名")
                XCTAssertEqual(languages["zh-Hans"]?.state, "translated", "\(name) · \(row.key) 的 zh-Hans 未落 translated")
                XCTAssertNotNil(languages["zh-Hant"], "\(name) · \(row.key) 缺 zh-Hant 条目")
                XCTAssertEqual(languages["zh-Hant"]?.value, row.zhHant, "\(name) · \(row.key) 的 zh-Hant 不是统一名")
                XCTAssertEqual(languages["zh-Hant"]?.state, "translated", "\(name) · \(row.key) 的 zh-Hant 未落 translated")
                XCTAssertEqual(
                    languages["en"]?.value ?? row.key,
                    row.en ?? row.key,
                    "\(name) · \(row.key) 的 en 不是统一名"
                )
            }
            // 两份 catalog 都收了这个 key：值必须逐语言一致。
            if owners.count == 2 {
                for language in ["zh-Hans", "zh-Hant", "en"] {
                    XCTAssertEqual(
                        tables[owners[0]]?[row.key]?[language]?.value,
                        tables[owners[1]]?[row.key]?[language]?.value,
                        "\(row.key) 的 \(language) 在两份 catalog 里打架"
                    )
                }
            }
        }

        // 2) 面板组脚注是整段文案：只钉「含新短名、不含旧名」。
        let footerKey = "settings.modules.group.panel.footer"
        let footer = tables["DynamicIsland/Localizable.xcstrings"]?[footerKey]?["zh-Hans"]?.value
        XCTAssertNotNil(footer, "\(footerKey) 缺 zh-Hans 文案")
        XCTAssertTrue(footer?.contains("投送暂存") ?? false, "面板组脚注没换成「投送暂存」：\(footer ?? "nil")")
        XCTAssertFalse(footer?.contains("暂存器") ?? true, "面板组脚注仍留着「暂存器」")

        // 3) 全量负断言：两份 catalog 的每个 zh 值都不再出现旧名。
        for name in catalogNames {
            for (key, languages) in tables[name] ?? [:] {
                for language in ["zh-Hans", "zh-Hant"] {
                    guard let value = languages[language]?.value else { continue }
                    for legacy in Self.legacyShelfNames {
                        XCTAssertFalse(
                            value.contains(legacy),
                            "\(name) · \(key)（\(language)）仍含旧名「\(legacy)」：\(value)"
                        )
                    }
                }
            }
        }
    }

    /// 一条命名断言（`en == nil` = catalog 里没有显式 `en` 条目，期望值就是 key 自身）。
    private struct ShelfNamingExpectation {
        let key: String
        let zhHans: String
        let zhHant: String
        var en: String? = nil
    }

    /// 设计文档 §接口与数据形状 · 机制三 命名表的逐字期望值——含 `Enable shelf` 的新英文
    /// （`Enable AirDrop & File Shelf`）、供应商回落 `System Share Menu`，以及根 catalog 那条
    /// 完全磁盘访问引导（它的旧译里也有「暂存器」）。
    private static let shelfNamingTable: [ShelfNamingExpectation] = [
        ShelfNamingExpectation(
            key: "Enable shelf",
            zhHans: "启用隔空投送与文件暂存",
            zhHant: "啟用隔空投送與檔案暫存",
            en: "Enable AirDrop & File Shelf"
        ),
        ShelfNamingExpectation(key: "Shelf", zhHans: "投送暂存", zhHant: "投送暫存", en: "Shelf"),
        ShelfNamingExpectation(
            key: "Open shelf tab by default if items added",
            zhHans: "添加项目时默认打开投送暂存标签",
            zhHant: "新增項目時預設開啟投送暫存標籤"
        ),
        ShelfNamingExpectation(
            key: "Remove from shelf after dragging",
            zhHans: "拖拽后从暂存移除",
            zhHant: "拖移後從暫存移除"
        ),
        ShelfNamingExpectation(key: "Remove from Shelf", zhHans: "从暂存移除", zhHant: "從暫存移除"),
        ShelfNamingExpectation(key: "Shelf item", zhHans: "暂存项目", zhHant: "暫存項目"),
        ShelfNamingExpectation(
            key: "Allow moving files when dragging out",
            zhHans: "拖出时允许移动文件",
            zhHant: "拖出時允許移動檔案"
        ),
        ShelfNamingExpectation(
            key: "Choose which service to use when sharing files from the shelf. Drag files onto the shelf or click the shelf button to pick files.",
            zhHans: "选择从投送暂存共享文件时使用的服务。将文件拖到投送暂存上或点击投送暂存按钮选择文件。",
            zhHant: "選擇從投送暫存共享檔案時使用的服務。將檔案拖到投送暫存上或點按投送暫存按鈕選擇檔案。"
        ),
        ShelfNamingExpectation(
            key: "Files dropped on the shelf will be shared via this service",
            zhHans: "拖放到投送暂存的文件将通过此服务共享",
            zhHant: "拖放到投送暫存的檔案將透過此服務共享"
        ),
        ShelfNamingExpectation(
            key: "Files shared from the shelf will use this service",
            zhHans: "从投送暂存共享的文件将使用此服务",
            zhHant: "從投送暫存共享的檔案將使用此服務"
        ),
        ShelfNamingExpectation(
            key: "System Share Menu",
            zhHans: "系统分享菜单",
            zhHant: "系統分享選單",
            en: "System Share Menu"
        ),
        ShelfNamingExpectation(
            key: "Without Full Disk Access, Shelf can only read files from Documents and Downloads. Grant Full Disk Access to make Shelf work globally.",
            zhHans: "如果没有完全磁盘访问权限，投送暂存只能读取文档和下载目录的文件。授予完全磁盘访问权限以使投送暂存在全局范围工作。",
            zhHant: "如果沒有完整磁碟取用權，投送暫存只能讀取文件和下載目錄的檔案。授予完整磁碟取用權以使投送暫存在全域範圍工作。"
        ),
    ]

    /// 旧名（D-05「旧译清零」）：zh 值里一律不再出现——含繁体形态。
    private static let legacyShelfNames = ["架子", "搁板", "擱板", "暂存器", "暫存器"]

    /// catalog 里一条语言条目的取值与状态。
    private struct CatalogUnit {
        let value: String
        let state: String
    }

    /// 解析一份 `.xcstrings` 原文件：key →（语言 → 条目）。文件读不到或结构不对就抛出——
    /// 「读不到文件」不该静默变成通过。
    private static func catalogTable(at url: URL) throws -> [String: [String: CatalogUnit]] {
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "\(url.path) 不是 JSON 对象"
        )
        let strings = try XCTUnwrap(root["strings"] as? [String: Any], "\(url.path) 缺 strings 表")
        var table: [String: [String: CatalogUnit]] = [:]
        for (key, rawEntry) in strings {
            guard let entry = rawEntry as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else { continue }
            var languages: [String: CatalogUnit] = [:]
            for (language, rawLocalization) in localizations {
                guard let unit = (rawLocalization as? [String: Any])?["stringUnit"] as? [String: Any],
                      let value = unit["value"] as? String else { continue }
                languages[language] = CatalogUnit(value: value, state: unit["state"] as? String ?? "")
            }
            table[key] = languages
        }
        return table
    }

    // MARK: - 空闲动画（p6-ui-polish / T10，docs/30 §机制八）

    /// `IdleAnimationManager.selectFirstBundledIfNoneSelected()`：「空闲动画」开关打开而**从未选过样式**
    /// 时的兜底写（docs/30-ui-polish-and-shelf.md §机制八 / D-17）。
    ///
    /// 三层：① **写入**——库里第一条**内置**动画进选择（不是第一条用户动画）；② **叫醒**——写进去的
    /// 值必须经由 `selectedIdleAnimation` 键发出（`ContentView` 的 `@Default(.selectedIdleAnimation)`
    /// 与 `IdleAnimationView` 都是靠这个键被叫醒的），**没写就不许有新值经这个键发出**；
    /// ③ **不越权**——已有选择 / 库里没有内置动画时一个字都不动。
    ///
    /// 叫醒**按值断言、不数事件条数**：同一次写在测试宿主里实测会拆成 1~2 条 KVO 通知（第一次全量
    /// 跑测时按条数断言红成假失败——那是投递细节，不是判据）。
    func testEnablingIdleAnimationSelectsTheFirstBundledStyleWhenNoneChosen() {
        let keys = [
            Defaults.Keys.customIdleAnimations.name,
            Defaults.Keys.selectedIdleAnimation.name,
        ]
        let snapshot = snapshotValues(of: keys)
        defer { restoreValues(snapshot, for: keys) }

        let bundledFirst = CustomIdleAnimation(
            name: "T10 Fixture Bundled A",
            source: .lottieFile(URL(fileURLWithPath: "/tmp/t10-fixture-bundled-a.json")),
            speed: 1.0,
            isBuiltIn: true
        )
        let bundledSecond = CustomIdleAnimation(
            name: "T10 Fixture Bundled B",
            source: .lottieFile(URL(fileURLWithPath: "/tmp/t10-fixture-bundled-b.json")),
            speed: 1.0,
            isBuiltIn: true
        )
        let userMade = CustomIdleAnimation(
            name: "T10 Fixture User",
            source: .lottieFile(URL(fileURLWithPath: "/tmp/t10-fixture-user.json")),
            speed: 1.0,
            isBuiltIn: false
        )

        // 叫醒的观察点：订阅 `selectedIdleAnimation` 键（与视图 `@Default` 同一套 KVO 通道）。
        var observedIDs: Set<UUID> = []
        let observation = Defaults.observe(.selectedIdleAnimation, options: []) { change in
            if let id = change.newValue?.id { observedIDs.insert(id) }
        }
        defer { observation.invalidate() }

        // ① 写入：用户动画排在最前，选中的仍是**第一条内置**动画。
        Defaults[.customIdleAnimations] = [userMade, bundledFirst, bundledSecond]
        Defaults[.selectedIdleAnimation] = nil

        XCTAssertTrue(
            IdleAnimationManager.shared.selectFirstBundledIfNoneSelected(),
            "从未选过样式 → 应当发生写入"
        )
        XCTAssertEqual(
            Defaults[.selectedIdleAnimation]?.id,
            bundledFirst.id,
            "写入的是**第一条内置**动画（不是排在前面的用户动画）"
        )
        XCTAssertTrue(
            observedIDs.contains(bundledFirst.id),
            "叫醒：写进去的那条动画经 `selectedIdleAnimation` 键发出（视图的 @Default 观察点靠它重绘）"
        )

        // ② 不越权：已有选择（哪怕是用户动画）不动。诱饵用**新 id**（`bundledForExisting`）——
        // 布置阶段从没写过它，方法若越权把它写进选择，它会第一次经 `selectedIdleAnimation` 键发出。
        let bundledForExisting = CustomIdleAnimation(
            name: "T10 Fixture Bundled B2",
            source: .lottieFile(URL(fileURLWithPath: "/tmp/t10-fixture-bundled-b2.json")),
            speed: 1.0,
            isBuiltIn: true
        )
        let userChoice = CustomIdleAnimation(
            name: "T10 Fixture User Choice",
            source: .lottieFile(URL(fileURLWithPath: "/tmp/t10-fixture-user-choice.json")),
            speed: 1.0,
            isBuiltIn: false
        )
        Defaults[.customIdleAnimations] = [bundledForExisting, userChoice]
        Defaults[.selectedIdleAnimation] = userChoice

        XCTAssertFalse(
            IdleAnimationManager.shared.selectFirstBundledIfNoneSelected(),
            "已有选择 → 不写"
        )
        XCTAssertEqual(Defaults[.selectedIdleAnimation]?.id, userChoice.id, "用户的选择被原地保留")
        XCTAssertFalse(
            observedIDs.contains(bundledForExisting.id),
            "不写 → 方法没有把内置动画写进选择（没有新值经 `selectedIdleAnimation` 键发出）"
        )

        // ③ 不越权：库里没有内置动画时不替用户乱选（选择保持 nil）。
        let userOnlyBait = CustomIdleAnimation(
            name: "T10 Fixture User Bait",
            source: .lottieFile(URL(fileURLWithPath: "/tmp/t10-fixture-user-bait.json")),
            speed: 1.0,
            isBuiltIn: false
        )
        Defaults[.customIdleAnimations] = [userOnlyBait]
        Defaults[.selectedIdleAnimation] = nil

        XCTAssertFalse(
            IdleAnimationManager.shared.selectFirstBundledIfNoneSelected(),
            "没有内置动画可写 → 不写"
        )
        XCTAssertNil(Defaults[.selectedIdleAnimation], "选择保持 nil（不越权选中自定义动画）")
        XCTAssertFalse(
            observedIDs.contains(userOnlyBait.id),
            "不写 → 诱饵的自定义动画没有经 `selectedIdleAnimation` 键发出"
        )
    }

    /// `IdleAnimationManager.resolvedAnimation(for:)`：**渲染期解析**内置动画的源（p6-ui-polish / T10 fix）。
    ///
    /// 实锤形态：`defaults read com.cmeng.gourd selectedIdleAnimation` 里存的是
    /// `file:///Volumes/壶中天/Gourd.app/Contents/Resources/Dog waiting.json`——写入时刻的绝对路径，
    /// 卷卸载 / 换安装位置后失效（`/Volumes/壶中天` 不存在），面动画加载为空。三层：
    /// ① 死路径的内置动画解析回**当前 bundle 里真实存在的文件**（非 nil / 非空）；② 身份仍取存储值
    /// （id 不变——变换覆盖与「已选择」判定按存储 id）；③ 自定义动画不走内置解析、原样返回；
    /// 另加回落层：新鲜列表里没有同名条目（旧版本删过的样式）→ nil。
    func testBuiltInIdleAnimationResolvesToTheCurrentBundleFileAtRenderTime() throws {
        // 存储值的实锤形态：内置 + 指向已卸载的 DMG 卷的绝对路径。
        let staleURL = URL(fileURLWithPath: "/Volumes/壶中天/Gourd.app/Contents/Resources/Dog waiting.json")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: staleURL.path),
            "前置：这条存储路径在盘上不存在（卷已卸载）"
        )

        let stored = CustomIdleAnimation(
            id: UUID(),
            name: "Dog waiting",
            source: .lottieFile(staleURL),
            speed: 1.0,
            isBuiltIn: true
        )

        // ① 解析到当前 bundle 的真实文件。
        let resolved = try XCTUnwrap(
            IdleAnimationManager.shared.resolvedAnimation(for: stored),
            "内置动画要解析出当前 bundle 的同一条，不能是 nil"
        )
        XCTAssertEqual(resolved.id, stored.id, "身份仍是存储值（覆盖 / 「已选择」判定按存储 id）")
        XCTAssertEqual(resolved.name, stored.name, "同名（name 是内置动画的稳定身份）")
        XCTAssertTrue(resolved.isBuiltIn, "仍是内置动画")
        XCTAssertEqual(resolved.speed, stored.speed, "速度等呈现字段仍取存储值")

        guard case .lottieFile(let resolvedURL) = resolved.source else {
            return XCTFail("解析结果的源形态仍是 .lottieFile")
        }
        XCTAssertFalse(resolvedURL.path.hasPrefix("/Volumes/"), "不再是死卷路径")
        XCTAssertFalse(resolvedURL.path.isEmpty, "非空路径")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: resolvedURL.path),
            "解析到当前 bundle 里真实存在的文件：\(resolvedURL.path)"
        )
        XCTAssertEqual(resolvedURL.lastPathComponent, "Dog waiting.json", "文件名不变")
        let bundleURL = try XCTUnwrap(
            Bundle.main.url(forResource: "Dog waiting", withExtension: "json"),
            "测试宿主（App）bundle 里应带这份内置资源"
        )
        XCTAssertEqual(resolvedURL.path, bundleURL.path, "解析结果 = 当前 bundle 的同一份资源")

        // ② 旧版本删过的样式（新鲜列表里没有同名条目）→ 回落 nil（不留旧路径、不揣测）。
        let orphan = CustomIdleAnimation(
            name: "T10 Fix Fixture Not In Bundle",
            source: .lottieFile(staleURL),
            speed: 1.0,
            isBuiltIn: true
        )
        XCTAssertNil(
            IdleAnimationManager.shared.resolvedAnimation(for: orphan),
            "新鲜内置列表里没有同名条目 → nil（候选决策：回落空不加戏）"
        )

        // ③ 自定义动画不走内置解析：同一个 URL 原样返回（哪怕它在盘上不存在）。
        let customURL = URL(fileURLWithPath: "/tmp/t10-fix-custom-not-installed.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: customURL.path), "前置：自定义路径也不存在")
        let custom = CustomIdleAnimation(
            name: "Dog waiting",
            source: .lottieFile(customURL),
            speed: 1.0,
            isBuiltIn: false
        )
        let resolvedCustom = try XCTUnwrap(
            IdleAnimationManager.shared.resolvedAnimation(for: custom),
            "自定义动画原样返回"
        )
        guard case .lottieFile(let resolvedCustomURL) = resolvedCustom.source else {
            return XCTFail("自定义动画的源形态不变")
        }
        XCTAssertEqual(resolvedCustom.id, custom.id)
        XCTAssertEqual(
            resolvedCustomURL.path,
            customURL.path,
            "自定义动画不走内置解析（名字与内置同名也不换源）"
        )
    }

    // MARK: - 设置侧栏归位（p6-ui-polish / T11，docs/30 §做法 机制九 / §接口「机制九」）

    /// 页 → 组的唯一映射（`SettingsTabGroup.group(for:)`，T11 抽出的静态函数）：
    /// **组件页归「媒体与显示」**（D-18：推翻 docs/26 时期「扩展 / 组件必须相邻」的口径），
    /// 而**扩展页留在「集成」**——两页不再同组。
    ///
    /// 断言打在映射本身（唯一真源）而不是侧栏渲染上：`groupedFilteredTabs` 完全由
    /// `tab.group` 驱动，映射对了，「媒体与显示」段与「集成」段两处渲染就都在对的位置；
    /// `availableTabs` 的组内顺序（`.modules` 排在 `.devices` 之后）不在这里钉。
    func testModulesSettingsPageSitsInMediaAndDisplayGroup() {
        XCTAssertEqual(SettingsTabGroup.group(for: .modules), .mediaAndDisplay)
        XCTAssertEqual(SettingsTabGroup.group(for: .extensions), .integrations)
    }

    // MARK: - 工具

    /// 让出主 actor 若干回合，直到条件成立（桥的回调是 `Task { @MainActor }`，不是同帧）。
    /// 上限 1000 回合：等不到就返回 false，由断言报出「等不到」而不是死在死循环里。
    @discardableResult
    private func waitUntil(_ condition: () -> Bool, limit: Int = 1_000) async -> Bool {
        for _ in 0..<limit {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }

    /// 让出主 actor 若干回合（用于「本不该发生」的断言：把在飞的回合跑完再看结果）。
    private func yieldTurns(_ times: Int = 100) async {
        for _ in 0..<times { await Task.yield() }
    }

    /// 账本读取：**没记过 = 0**（`TakeoverLedger` 只在第一次调用时落键，直接下标会拿到 nil）。
    private func activations(_ id: String) -> Int { TakeoverLedger.activations[id] ?? 0 }

    /// 账本读取：置关次数（同上）。钉「置关走到了模块的 `deactivate()`」这条。
    private func deactivations(_ id: String) -> Int { TakeoverLedger.deactivations[id] ?? 0 }

    /// 记下两个真实键在**持久域**里的原值（nil = 原本没有这个键）。
    private func snapshotPreferences() -> PreferenceSnapshot {
        PreferenceSnapshot(
            enableTimerFeature: persistedValue(of: Defaults.Keys.enableTimerFeature.name),
            moduleEnableOverrides: persistedValue(of: Defaults.Keys.moduleEnableOverrides.name)
        )
    }

    /// 逐字还原（见文件头「偏好卫生」）：原本有键写回原值、原本没键删键。
    private func restore(_ snapshot: PreferenceSnapshot) {
        restore(snapshot.enableTimerFeature, to: Defaults.Keys.enableTimerFeature.name)
        restore(snapshot.moduleEnableOverrides, to: Defaults.Keys.moduleEnableOverrides.name)
    }

    /// 持久域里那个键的原值（`nil` = 用户从未写过 / 已被 `reset`）。
    ///
    /// 为什么不用 `Defaults[...]`：`Defaults.Key` 的初始化会顺手把默认值注册进**注册域**，
    /// 于是 `object(forKey:)` 对任何已声明的键都恒非 nil——它答不出「盘上有没有」。
    private func persistedValue(of key: String) -> Any? {
        guard let domain = Bundle.main.bundleIdentifier else { return nil }
        return UserDefaults.standard.persistentDomain(forName: domain)?[key]
    }

    // MARK: - 协调器页面字段（T3）

    /// 共享协调器的页面字段 + `enableMinimalisticUI` 的持久域原值。
    ///
    /// 前者是 T3 三档用例读写的状态；后者是它们的前置条件（`currentView` 的 `didSet` 在极简 UI
    /// 开着时把非 `.home` 的选中打回 `.home`），因此也要纳入卫生——夹具取值见各用例的注释。
    private struct TimerSurfaceSnapshot {
        let currentView: NotchViews
        let selectedModuleID: String?
        let enableMinimalisticUI: Any?
    }

    /// 进入时记下协调器两个字段 + 极简 UI 键的**持久域**原值（不读 `Defaults[...]`，理由同 `persistedValue(of:)`）。
    private func snapshotTimerSurface() -> TimerSurfaceSnapshot {
        let coordinator = DynamicIslandViewCoordinator.shared
        return TimerSurfaceSnapshot(
            currentView: coordinator.currentView,
            selectedModuleID: coordinator.selectedModuleID,
            enableMinimalisticUI: persistedValue(of: Defaults.Keys.enableMinimalisticUI.name)
        )
    }

    /// 逐字还原（顺序有意）：先还原极简 UI 键（它决定 `didSet` 要不要打回 `.home`），再写回两个字段，
    /// 这样即使原 `currentView` 不是 `.home`，落盘的最后一个值也与进入前一致。
    private func restoreTimerSurface(_ snapshot: TimerSurfaceSnapshot) {
        restore(snapshot.enableMinimalisticUI, to: Defaults.Keys.enableMinimalisticUI.name)
        let coordinator = DynamicIslandViewCoordinator.shared
        coordinator.selectedModuleID = snapshot.selectedModuleID
        coordinator.currentView = snapshot.currentView
    }

    /// 一次记下若干键的持久域原值（**只装「盘上真有」的键**：缺的键不在表里 → 还原成删键）。
    private func snapshotValues(of keys: [String]) -> [String: Any] {
        var table: [String: Any] = [:]
        for key in keys {
            if let value = persistedValue(of: key) { table[key] = value }
        }
        return table
    }

    /// 按同一份键表逐字还原（表里没有的键 = 原本没有 → 删键）。
    private func restoreValues(_ snapshot: [String: Any], for keys: [String]) {
        for key in keys { restore(snapshot[key], to: key) }
    }

    /// 还原一个持久域原值：原本有键写回原值、原本没键删键（写 `[:]` 会在域里留下一个存在的键）。
    private func restore(_ value: Any?, to key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// 本地化 key 在**宿主 bundle 的 zh-Hans 那一份**里解析得出文案（查不到时 `Bundle` 原样返回 key，
    /// 据此判定）。
    ///
    /// **为什么锁定语言**（T6 修复）：catalog 里七条上游名称 key（`Enable Clipboard Manager` 等）
    /// **没有 `en` 值**（它们在 `en` 下以 key 自身为值），因此 `Bundle.main.localizedString(forKey:value:table:)`
    /// 的结果**跟着跑测机器的语言走**：本机是 zh-Hans 时返回译文（`!= key`，断言过），英语环境下原样
    /// 返回 key（断言红）。用例要判的是「文案已进 catalog」，与机器语言无关，所以查**具体的 zh-Hans 一份**。
    ///
    /// **形态说明**：Swift 在 Darwin 上只暴露三参的 `localizedString(forKey:value:table:)`
    /// （ObjC 那条带 `localization:` 的四参方法没有导入：`extra argument 'localization' in call`），
    /// 因此「指定语言」用等价写法落到 `zh-Hans.lproj` 子 bundle 上——解析结果就是 zh-Hans 那一份译文，
    /// 本机语言环境不再参与。
    ///
    /// 与 `ModuleKernelTests` 的同类断言**不再逐字相同**：那边仍是 `Bundle.main.localizedString` +
    /// `!= key`（同样的语言依赖），本文件只修自己这一段，不去改别的测试文件。
    private func XCTAssertResolves(
        _ key: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let localizationPath = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"),
              let bundle = Bundle(path: localizationPath) else {
            XCTFail("宿主 bundle 里找不到 zh-Hans.lproj（拿不到锁语言的解析口径）", file: file, line: line)
            return
        }
        let localized = bundle.localizedString(forKey: key, value: nil, table: nil)
        XCTAssertNotEqual(localized, key, "\(key) 没解析出 zh-Hans 文案（catalog 未编进宿主 bundle？）", file: file, line: line)
        XCTAssertFalse(localized.isEmpty, "\(key) 解析为空串", file: file, line: line)
    }

    /// 本地化 key **不能**在宿主 bundle 的 zh-Hans 那一份里解析出文案（`Bundle` 查不到时原样返回 key，
    /// 据此判定）——「这条 key 已从 catalog 里删掉」这一条的判据。
    ///
    /// 与 `XCTAssertResolves` 取同一份 bundle（语言锁定的理由见那里），只是断言方向相反。
    /// 用途是钉**负向**事实（p5 / T4：「功能」段那七条文案 key 已随段删除）——段本身在视图里、
    /// 单测够不到，可自动判定的形态就是「它的文案 key 不再可达」。
    private func XCTAssertDoesNotResolve(
        _ key: String,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let localizationPath = Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"),
              let bundle = Bundle(path: localizationPath) else {
            XCTFail("宿主 bundle 里找不到 zh-Hans.lproj（拿不到锁语言的解析口径）", file: file, line: line)
            return
        }
        let localized = bundle.localizedString(forKey: key, value: nil, table: nil)
        XCTAssertEqual(
            localized,
            key,
            message.isEmpty ? "\(key) 仍解析得出文案（应当已从 catalog 删除）" : message,
            file: file,
            line: line
        )
    }
}

// MARK: - 偏好快照（文件私有）

/// 用例读写过的两个真实键的原值（`TakeoverProbeModule` 的接管键 = `enableTimerFeature`；
/// 写路径的另一半是 `moduleEnableOverrides`）——本文件只用这两个，因此快照就两个字段。
private struct PreferenceSnapshot {
    let enableTimerFeature: Any?
    let moduleEnableOverrides: Any?
}

// MARK: - 假模块与账本（文件私有）

/// 假模块的 manifest 工厂（与 `ModuleKernelTests` / `ModuleToggleTests` 同一口径：字面量构造）。
private enum TakeoverFixture {
    static func manifest(
        shortID: String,
        surfaces: [Surface] = [.expanded],
        order: Int? = 10,
        defaultEnabled: Bool = false
    ) -> ModuleManifest {
        ModuleManifest(
            manifestVersion: 1,
            id: "com.cmeng.gourd.\(shortID)",
            name: LocalizedText(key: "module.\(shortID).name"),
            summary: nil,
            icon: IconSpec(type: "symbol", name: "square"),
            version: "1.0.0",
            apiVersion: HostInfo.currentAPIVersion,
            kind: "builtin",
            surfaces: surfaces,
            defaultPlacement: order.map { Placement(slot: nil, order: $0) },
            defaultEnabled: defaultEnabled,
            permissions: [],
            config: nil
        )
    }
}

/// `activate()` / `deactivate()` 的调用账本（计数型假模块的判据；`tearDown` 后不复用）。
@MainActor
private enum TakeoverLedger {
    static var activations: [String: Int] = [:]
    static var deactivations: [String: Int] = [:]

    static func reset() {
        activations.removeAll()
        deactivations.removeAll()
    }
}

/// 假模块基线：**非接管**（三条钩子都显式写成缺省语义，好让子类能 `override` 到别的实现——
/// 基类不声明、子类就只能走协议扩展的静态派发，接管模块的声明会被静默忽略）。
///
/// 注意 `takeoverEnableKey` 是**协议要求**（缺省实现在 `GourdModule` 的扩展里）：本类显式重写它，
/// 是为了让 `TakeoverProbeModule` 那一层能 `override`——经 `any GourdModule.Type` 取用时走的是
/// 具体模块的实现，不是扩展缺省。
@MainActor
private class TakeoverProbeBase: GourdModule {
    class var manifest: ModuleManifest {
        TakeoverFixture.manifest(shortID: "probe-takeover-base", surfaces: [.expanded])
    }

    class var takeoverEnableKey: Defaults.Key<Bool>? { nil }
    class func isTabVisible() -> Bool { true }
    class var homeBlockWidth: ModuleHomeBlockWidth? { nil }

    let context: ModuleContext

    required init(context: ModuleContext) {
        self.context = context
    }

    func activate() async throws {
        TakeoverLedger.activations[Self.manifest.id, default: 0] += 1
    }

    func deactivate() async {
        TakeoverLedger.deactivations[Self.manifest.id, default: 0] += 1
    }

    func content(for request: ContentRequest) -> ModuleContent { .none }
}

/// 接管模块：`takeoverEnableKey` 指向真的上游键 `.enableTimerFeature`（本批唯一被读写的真实键）。
private class TakeoverProbeModule: TakeoverProbeBase {
    /// `defaultEnabled = true`：**故意**与上游键的语义相反，好让「接管键压过 manifest 默认」可判
    /// （见 `testTakeoverKeyBeatsOverridesAndManifestDefault` 的第一个断言）。
    override class var manifest: ModuleManifest {
        TakeoverFixture.manifest(
            shortID: "probe-takeover",
            surfaces: [.expanded],
            order: 10,
            defaultEnabled: true
        )
    }

    override class var takeoverEnableKey: Defaults.Key<Bool>? { .enableTimerFeature }
}

/// 接管模块 + `isTabVisible() == false`（定时器那种「启用之外还有可见性条件」的形态）。
private final class TakeoverHiddenTabProbeModule: TakeoverProbeModule {
    override class var manifest: ModuleManifest {
        TakeoverFixture.manifest(shortID: "probe-takeover-hidden-tab", surfaces: [.expanded], order: 20)
    }

    override class func isTabVisible() -> Bool { false }
}

/// 接管模块 + 声明一块宽（**任意样本档** 260/340，docs/20 §接口与数据形状 5）——本夹具只证明
/// 「声明的宽度原样经注册表取给宿主」，与某个真模块的现行声明无关（镜子的 140/140 在它自己的
/// 用例里钉）。
private final class TakeoverWideBlockProbeModule: TakeoverProbeModule {
    override class var manifest: ModuleManifest {
        TakeoverFixture.manifest(shortID: "probe-takeover-wide", surfaces: [.home], order: 2)
    }

    override class var homeBlockWidth: ModuleHomeBlockWidth? {
        ModuleHomeBlockWidth(min: 260, ideal: 340)
    }
}

/// 接管模块 + `activate()` 必抛错（`failed` 终态的判据）；抛错前记一次调用，供「不重试」断言。
private final class TakeoverFailingProbeModule: TakeoverProbeModule {
    struct ActivationFailure: Error {}

    override class var manifest: ModuleManifest {
        TakeoverFixture.manifest(shortID: "probe-takeover-failing", surfaces: [.expanded], order: 30)
    }

    override func activate() async throws {
        TakeoverLedger.activations[Self.manifest.id, default: 0] += 1
        throw ActivationFailure()
    }
}

/// 两个**非接管**、只声明 `.expanded` 的假模块（p3-widgets / T3 的面板组排序用例）：
/// 默认序号差 10（A = 10 → B = 20），够判「缺键按 defaultPlacement.order」与「panelOrder 覆盖后翻转」。
///
/// 非接管（`takeoverEnableKey` 缺省 nil）是刻意的：写路径那一半要走 `moduleEnableOverrides`
/// （接管模块写的是上游键，那条另有既有用例）。
private final class SurfacePanelProbeA: TakeoverProbeBase {
    override class var manifest: ModuleManifest {
        TakeoverFixture.manifest(shortID: "probe-surface-a", surfaces: [.expanded], order: 10)
    }
}

/// 见 `SurfacePanelProbeA`（默认序号 20）。
private final class SurfacePanelProbeB: TakeoverProbeBase {
    override class var manifest: ModuleManifest {
        TakeoverFixture.manifest(shortID: "probe-surface-b", surfaces: [.expanded], order: 20)
    }
}

/// 一个**双面**模块（`home + expanded`）：两节各自的开关用例需要它——关掉一面时另一面必须照旧
/// （节头那句「各自的开关只管各自的 surface」的判据）。故意不含 `.compact`：本批只有 home / panel
/// 两个面有自己的开关（`ModuleSurfaceGroup.hasOtherSurface` 的口径）。
private final class SurfaceDualProbeModule: TakeoverProbeBase {
    override class var manifest: ModuleManifest {
        TakeoverFixture.manifest(shortID: "probe-surface-dual", surfaces: [.home, .expanded], order: 5)
    }
}
