# 冻结 v0.1.0：版本身份、许可合规、独立日历接线、模块配置口、README 与使用说明

| 项 | 值 |
|---|---|
| 状态 | **已实现（2026-09-30）**——范围内九项全部落地，逐条见 §实际交付；本批另外收掉一枚关闭态「日进度 pill」（用户报为亮度 HUD，见 §实际交付 末尾与 §已知限制 6） |
| 最后更新 | 2026-09-30 |
| 关联来源 | 用户 2026-09-30「整体分析…是否可以固定一个版本」+ 七条确认；README/归属调研结论（见 §做法 机制一）；[03-license-matrix](03-license-matrix.md)、[04-upstreams](04-upstreams.md)、[09](09-features-and-mechanisms.md)、[14](14-module-manifests.md)、[20](20-component-page.md)~[23](23-home-fit.md) |

> **怎么读**：§背景与目标 / §明确不做 / §备选与取舍 是判断依据；§接口与数据形状 是执行者契约；
> §已知限制 / §实际交付 留给后来人。
>
> **读者分界**：给人读的是背景、取舍、不做的与限制；§做法 机制与 §接口与数据形状 给执行者与模型。

## 一句话方案

把"能冻结"变成"冻得住"：**① 版本身份分家**（`MARKETING_VERSION`/`VERSION` 从继承来的 `2.3.3` 改成 `0.1.0`）；
**② 许可与归属补合规**（GPL-3.0 §5(a) 要求"显著标注修改 + 日期"：NOTICE 缺日期、README 无"修改版本"字样、
TRADEMARKS 还写着"以 Atoll 之名营销"、自建的 30+ 文件无版权头——逐条补）；
**③ CHANGELOG 分家**（现通篇是 Atoll 的、0 处提到 Gourd）；**④ 冒烟清单成文**；
**⑤ 给孤儿视图 `StandaloneCalendarView` 接线**（做成日历模块的展开 tab，正是 [14](14-module-manifests.md) 原计划）；
**⑥ 模块配置开口**（组件页按允许清单渲染几个键，其余标"由上游设置管理"）；**⑦ README 重写 + 带图例的使用说明**。

## 背景与目标

### 现状（逐条对应"能冻结但冻不住"的具体缺口）

| # | 缺口 | 证据 |
|---|---|---|
| 1 | 版本号是上游的 | `VERSION` / `MARKETING_VERSION` = `2.3.3`，安装包自报 2.3.3——与 Atoll 同号，"哪个是我的构建"分不出来 |
| 2 | 许可合规缺 3 处 | NOTICE 无修改日期（§5(a) 要求"giving a relevant date"）；README 全文无"这是修改版本"；`TRADEMARKS` 仍写 "the product is explicitly marketed as Atoll"（对我们不成立）。另：自建 30+ `.swift` **无版权头** |
| 3 | CHANGELOG 不是我们的 | `CHANGELOG.md:3` = "changes to **Atoll**"，全文提及 Gourd **0** 次 |
| 4 | 没有冒烟清单 | 这几轮的上屏验证动作只活在会话与报告里 |
| 5 | 孤儿视图 | `StandaloneCalendarView`（双栏月历）只有 `#Preview`，运行期无入口；而文档承诺它"保留滚动渐变" |
| 6 | 半接管配置 | 组件页只有"显示封面"一个键有开关；manifest 里登记的 `enableTimerFeature` 一类**改了不生效**（真源是上游键） |
| 7 | 两处断言/观感缺口 | 通知列表行 × 的谓词无自动化断言；`＋N` 悬停列名依赖 tooltip（非激活面板时延秒级） |

### 预期结果（改后）

- 应用与 DMG 自报 **0.1.0**（`壶中天-0.1.0.dmg`），本地有 `v0.1.0` 标签；README 第 3 段起就写明"这是 Atoll 的修改版本 + 基线 + 修改日期 + 不背书"。
- `CHANGELOG.md` 顶部是「Gourd 分支自有变更」，上游历史保留并注明来源。
- `docs/25-release-smoke.md` 一页可照着走；`docs/guide/README.md` 是带图例的用户手册，README 引用它。
- 设置 → 组件里：音乐/启动台/快捷指令/前台应用四个模块的**有效配置项**能直接拨；被登记但不可编辑的键明确标出"由上游设置管理"。
- 日历有第二个入口：展开面板的「日历」tab（月历 + 当日清单），由 `showCalendar` 同一个开关控制。

### 承接关系与本次增量

**承接**：`docs/03`（许可矩阵）、`docs/04`（上游同步）、`docs/14`（日历模块声明 `expanded` 的原计划）、`docs/09`（功能清单）。
**本次增量**：版本身份、许可合规补口、CHANGELOG 分家、冒烟清单、日历 tab、配置编辑口、README 与用户手册。

## 做法

### 机制一：README 与归属的写法（调研已定，不再自由发挥）

同类开源项目（Atoll / boring.notch / Ice / stats / NotchDrop）的 README **共性六条**：顺序恒为
身份 → 图 → 安装 → 功能 → 用法 → FAQ → 许可 → 致谢；安装永远在功能之前且给具体路径；
功能用 bullet 而**不用表格**；至少一张 hero 图；致谢要么独立小节要么独立文件；许可多为一行链到 LICENSE。
**没有一家把「本仓库是 X 的修改版」写进 License 节**——而 GPL-3.0 §5(a) 要求"显著标注修改 + 日期"，
所以我们的做法照 fork 的标准范式（Zen Browser）：**顶部一句话 + 归属小节给版本号**，两处都出现。

**GPL 义务的准确清单**（调研核过原文）：§5(a) 标注修改**并给日期**；§5(b) 标注以本许可发布且无担保；
§5(c) 整部作品按 GPL 授权；§4 逐字复制源码须保留版权与许可；§6 分发二进制须提供对应源码；
§5(d) 交互界面须显示 Appropriate Legal Notices，**但上游本就没有 → 有豁免，App 内无需许可窗**；
§7 的"不得暗示背书"**不是 GPL 义务**（是商标法与上游 `TRADEMARKS` 的约束）——别写错依据。

### 机制二：许可合规的四笔补口

1. `NOTICE`：加「首次修改日期 2026-09-27（后续见 git 历史）」与「改名与重打包（产品名 壶中天/Gourd、
   Bundle ID `com.cmeng.gourd`、DMG 名）」——这是最显眼却漏记的修改。
2. `TRADEMARKS`：加一句 nominative use——「`Atoll` 仅用于指明代码来源；本仓库与 Atoll 项目及其维护者
   无隶属关系，未获其背书」；删/改"以 Atoll 之名营销"那句。
3. `COPYRIGHT_ASSETS`：追加 Gourd 自建资产的版权行，并与上游资产分段。
4. 自建源文件加版权头（`Copyright (C) 2026 Gourd Contributors` + GPL-3.0 声明），**上游文件头一字不动**。
   这条不违反既有 D-09（D-09 豁免的是"在上游文件里逐个标注改动"）。

### 机制三：日历 tab（给孤儿视图一个家）

新增 `com.cmeng.gourd.calendar` 接管模块：`surfaces: [.expanded]`、`takeoverEnableKey = Defaults.Keys.showCalendar`、
`content(for: .expanded)` = `StandaloneCalendarView()`；上游那颗日历行**不动**（它仍是首页的一部分）。
于是"日历"两处呈现（首页行 / 展开 tab）由同一个开关控制，与 [14](14-module-manifests.md) 的声明一致。

### 机制四：模块配置的编辑口（按允许清单，不做通用渲染器）

组件页新增一节：**逐个模块按允许清单**渲染配置控件——只支持 `boolean` / `integer` / `number` / `string` 四种类型
（`list` / `enum` 暂不渲染，见 §明确不做），读写的域与模块共用同一份 `ManifestConfigHandle`（同一个 key 只有一处编码）。
允许清单**只收"模块自己真的读"的键**（如 music 的 `showAlbumArt`、launcher 的 `iconSize`/`density`/`showRecents`、
shortcuts 的 `showOutput`/`timeoutSeconds`、frontapp 的 `maxRecentApps`）；**接管模块登记的上游键**
（`enableTimerFeature` 一类）**不进清单**，卡片上以一行灰字注明「由上游设置管理（改了不生效）」——先把话说清楚，
通用渲染器与写路径接管留给后续批次。

### 机制五：冒烟清单与用户手册的分工

- `docs/25-release-smoke.md`：**给发布者**（我自己）的检查单，一页，逐条「动作 → 期望 → 证据」，
  覆盖这几批的新功能与你实测过的点（面板各块 / 组件页 / ＋N / 前台块点击 / 封面开关 / 通知 / 快捷指令 / 日历 tab / 锁屏 / 多屏）。
- `docs/guide/README.md`：**给使用者**的手册（七节：第一次打开 / 首页有什么 / 每个模块做什么 / 设置页怎么用 /
  快捷键 / 常见问题 / 更新与卸载），**图例**放 `docs/guide/assets/`（进仓库、相对路径、宽度 1600–2000px、
  ①②③ 标注烧进图里 + 图下逐条短说明），README 里只留两行并链接过来。

## 备选与取舍

**① 版本号取 `0.1.0` 还是 `1.0.0`？** 取 **`0.1.0`**（用户 2026-09-30 确认口径：自用固定版）。理由：功能面虽已成型，
但"接管模块配置写路径""tab 排序""Shelf 输入联动"都还空着，报 `1.0.0` 会让将来自己误判兼容承诺；
`0.1.0` 表达"第一个冻结的自用版"。

**② 独立日历：接线成 tab / 删掉视图 / 只标注未接线？** 取**接线成 tab**。理由：它是[14](14-module-manifests.md) 早就写定的形态
（calendar 模块声明 `expanded`），删掉是丢功能、只标注是把问题留给下一次；成本中等且可上屏验证。

**③ 模块配置：通用渲染器 / 允许清单 / 只标注？** 取**允许清单 + 标注**（机制四）。理由：通用渲染器要处理
`list`/`enum`/`appPicker` 与"哪些键是真源"两个难题，放进冻结批次是范围失控；允许清单能用最小面积解决
"用户改不了的现在能改、改不了的明确说清"。

**④ 用户手册：README 内联 / `docs/guide/` / 独立站点？** 取 **`docs/guide/` + README 两行引用**。
理由：同类项目 5 家全无 docs（内联或官网），但我们的模块多、还在动，内联必然立刻过期；独立站对自用项目是纯负担。

**⑤ 图片：外链图床 / 进仓库？** 取**进仓库**（相对路径）。上游 Atoll 用的是外链（postimg.cc），外链失效文档就瞎。

## 接口与数据形状

> **本节按落地校正（2026-09-30）**：下面两段代码块是**实到形状**（与 `CalendarModule.swift` /
> `ModuleSettingsSection.swift` 的现状逐字对齐）；计划稿与实到的差异写在每段下方的「落地差异」里。

```swift
// 机制三：日历接管模块（照 TimerModule/MirrorModule 的样板；文件 DynamicIsland/Modules/Takeover/CalendarModule.swift）
final class CalendarModule: GourdModule {
    static let moduleID = "com.cmeng.gourd.calendar"      // id 的唯一字面量（manifest 与用例共用）
    static let manifest = ModuleManifest(
        // …manifestVersion 1 / name.summary 走 module.calendar.* / icon "calendar" / version "1.0.0" / kind "builtin"
        surfaces: [.expanded],          // 只答展开 tab
        defaultPlacement: nil,          // placement 只在含 compact 时有意义
        defaultEnabled: true,           // = showCalendar 的上游默认（接管模块的启用真源仍是上游键）
        permissions: [], config: nil
    )
    static var takeoverEnableKey: Defaults.Key<Bool>? { .showCalendar }
    func content(for:) -> ModuleContent   // .expanded → .view(AnyView(StandaloneCalendarView()))
                                          // .compact / .lockscreen / .home → .none
}
```

**落地差异**：① `defaultPlacement` 按「只在含 `compact` 时有意义」记 **`nil`**（计划稿同口径、无偏差）；
② 加了一条计划稿没写的口径：`defaultEnabled: true` 只是让日历卡上不出现「默认关闭」那行灰字
（接管模块的启用状态由启用门直接读 `showCalendar`）；③ `config: nil`——没有本模块自己的键可登记。

```swift
// 机制四：组件页的配置控件（允许清单，逐键声明；文件 DynamicIsland/components/Settings/ModuleSettingsSection.swift）
struct ModuleConfigControl {
    let moduleID: String
    let key: String          // manifest config 的键名（与模块读的同一份）
    let kind: Kind           // .boolean / .integer(range:) / .number(range:) / .string
    let titleKey: String     // Localizable key
}
static let controls: [ModuleConfigControl] = [
    // music.showAlbumArt（boolean）· launcher.iconSize（number, LauncherGridMetrics.iconSizeRange）
    // launcher.density（number, …densityRange）· launcher.showRecents（boolean）
    // shortcuts.showOutput（boolean）· shortcuts.timeoutSeconds（integer，区间 nil = 不夹取）
    // frontapp.maxRecentApps（integer, FrontAppHistory.limitRange）
]   // 共 7 条、4 个模块；区间一律复用各模块自己的常量（不新造第二份数字）
```

**落地差异**：① 计划稿写「four modules」时把 `.integer(range:)` 与 `.number(range:)` 并列，
实到的 `timeoutSeconds` 区间是 **`nil`**（模块自己按 1…300 夹取，设置页不重复一份约束）；
② 计划稿的 `controls` 注释里没有 frontapp 之外的第 8 条——实到就是 **7 条**（无增减）。

**文件与产物**（实到）：`docs/25-release-smoke.md`、`docs/guide/README.md` + `docs/guide/assets/*.png`（7 张）、
`README.md`（重写，68 行）、`CHANGELOG.md`（分段 + 本批两条新增 + 一条缺陷修复）、
`NOTICE` / `TRADEMARKS` / `COPYRIGHT_ASSETS`（补口）、`VERSION` 与 `project.pbxproj` 的版本字段、
`DynamicIsland/Modules/Takeover/CalendarModule.swift`、`DynamicIsland/components/Settings/ModuleSettingsSection.swift`
（配置控件一节）、`docs/01-architecture.md`（原 README 的术语/目录约定两节移入）。

## 明确不做

| 不做的事 | 为什么 |
|---|---|
| 通用配置渲染器（`list` / `enum` / `appPicker`） | 范围失控；允许清单先解决"能改的能改、不能改的说清"（§备选与取舍 ③） |
| 接管模块 config 的**写路径**接管（让改 `enableTimerFeature` 真的生效） | 属配置层（ConfigStore）的活；本批只在卡片上标注"由上游设置管理" |
| Star History / Contributors / 徽章 / Roadmap 等 README 装饰 | 调研明确列在"可整节删掉"；本仓库 CI 从未实跑，挂徽章等于造假（README 自己写着这点） |
| 英文版用户手册 | 自用为主；README 的归属小节给中英对照即可 |
| 图例做成 GIF / 视频 | 只有 `boring.notch` 一家用 GIF；静态标注图维护成本低一个量级 |
| 在 App 内加许可窗（About 里显示 GPL） | GPL-3.0 §5(d) 明文豁免（上游本就没有交互式法律提示）——别把它当义务 |
| 推送 / 发布到 GitHub | 远端动作一律等用户明确要求 |

## 实际交付

**九项范围内全部落地**（含本批一并收掉的一枚关闭态 pill）。证据一律在 `.workflow/p3-freeze/evidence/`（该目录
按 `.workflow/.gitignore` 不进仓库，路径只作本机对账用）。

| 任务 | 落地物 | 证据 | 与计划的偏差 |
|---|---|---|---|
| T1 版本身份 | `VERSION` = `0.1.0`；`MARKETING_VERSION` 两处 = `0.1.0`；`CURRENT_PROJECT_VERSION` 1196 → **1197**；DMG 名 `dist/壶中天-0.1.0.dmg` | `t1-build-install.log`、`t1-build-dmg.log`、`defaults-{before,after}-install.plist`、`defaults-dev-*.plist` | 无（Sparkle 的更新 URL 未动，推送/发布不在本批） |
| T2 许可与归属合规 | `NOTICE`（首次修改日期 2026-09-27 + 改名与重打包）、`TRADEMARKS`（nominative use / 无隶属、未获背书）、`COPYRIGHT_ASSETS`（Gourd 自建资产行）、自建 `.swift` 统一版权头（上游文件头一字未动）、`docs/03` 条款号与 §5(d) 豁免、`docs/04` 同步检查单加三步 | `t2-scan-and-reverse-check.txt`（正反向扫描）、`t2-xcodebuild.log` | 无 |
| T3 CHANGELOG 分家 | `CHANGELOG.md` 顶部 `[0.1.0] - 2026-09-30` 自有段 + 上游历史保留并注明；第 3 行改为 "changes to Gourd (a fork of Atoll)" | 同上回归日志 | 无；**本批（T9）在该段又补了 2 条新增 + 1 条缺陷修复** |
| T4 冒烟清单 | `docs/25-release-smoke.md`（逐条「动作 → 期望 → 证据」+ 前置条件） | 文件本身 | 无 |
| T5 两处断言/观感缺口 | 通知列表行 × 的谓词 `willAlsoCloseSystemBanner` 补可构造用例（句柄台账两态）；`＋N` 悬停 tooltip 时延写进 `docs/21` 已知限制 | `t5-mutation-red.log`（变异红）、`t5-restored-green.log`、`t5-xcodebuild-test.log` | 无 |
| T6 日历展开 tab | `Modules/Takeover/CalendarModule.swift`（`surfaces [.expanded]`、`takeoverEnableKey = .showCalendar`、`content(.expanded) = StandaloneCalendarView()`）、`KernelBootstrap.builtinModules` 加一行、`ModuleKernelTests` 内置清单计数 9 → 10、xcstrings `module.calendar.*` | `t6-calendar-tab.png`、`t6-calendar-month-nav.png`、`t6t7-*.log`、`t6t7-*.plist` | 计划稿写 `defaultPlacement: nil` ✓ 一致；另加「`defaultEnabled true` 只为日历卡不显示『默认关闭』」一条（见 §接口与数据形状） |
| T7 组件页配置编辑口 | `components/Settings/ModuleSettingsSection.swift` 新增配置控件一节：**7 条 / 4 个模块**（music.showAlbumArt；launcher.iconSize/density/showRecents；shortcuts.showOutput/timeoutSeconds；frontapp.maxRecentApps），读写与模块共用同一份 `ManifestConfigHandle`；接管模块登记的上游键不进清单，卡上灰字「由上游设置管理」 | `t7-config-controls.png`、`t7-launcher-config.png`、`t7-launcher-effect.png`、`t7-stale-value-before-fix.png`、`t7-mutation-red.log` | **实现期多修一个缺陷**：写完 config 后本行不重画（`Slider` 动、右侧数值停在旧值）→ 行级 `@State refreshToken`，见 §已知限制 6 |
| T8 README 与手册 | `README.md` 重写（68 行、不挂徽章/Star History/Roadmap）、`docs/guide/README.md` 七节 + `docs/guide/assets/*.png` 7 张、原 README 的术语/目录约定移入 `docs/01` | `t8-raw-*.png`（7 张原图）、`t8-annotate.py`、`t8-xcodebuild-test.log`（367 tests / 0 failures）、`t8-defaults-{before,after,final}.plist` | 六处（图 7 张非 6；未重跑 `--install` 因无源码改动；齿轮改走 AXPress；设置窗口图 1.2× 上采样；README 节序照派发片段；`04` 与 `02` 同源裁切）——逐条见 `.workflow/p3-freeze/reports/T8.md` §5 |
| **本批追加（收尾时发现）** | **关闭态那枚「日进度 pill」退回展开面板**：`progress` 模块 `surfaces [.expanded]`、`defaultPlacement.slot = nil`（`order 30` 保留给展开 tab）、折叠槽位视图删除；`docs/09` §5.3、`docs/14`、`CHANGELOG` 同步 | `hud-fix-collapsed.png`（收起态 75s 采样，0/15/30/45/60/75 秒逐张干净）+ `hud-fix-collapsed-crop.png`、`hud-fix-brightness-works.png`（亮度 HUD 正常弹）+ `hud-fix-brightness-works-crop.png`、变异红 `hud-fix-mutation-red.log` + 改回前的 pill 原图 `hud-fix-pre-fix-pill-repro{,-2}.png` + 偏好快照 `/tmp/hud-fix-before.plist`（前后逐键一致） | **根因与 T8 §6 的猜测不同**：不是亮度 HUD、不是 sneak peek 触发链——是 `progress` 模块的折叠态中央槽位（`sun.max` + 日进度百分比），本机 `moduleEnableOverrides` 把它开回后常驻；详见 `.workflow/p3-freeze/reports/hud-fix-and-T9.md` |

**测试**：`DynamicIslandTests` **367 条 0 失败**（本批只动 `ModuleKernelTests` 里 progress 的三组断言；
变异验证另有红——见报告）。

**范围外（留给控制器）**：`sh tools/build.sh --dmg` 的产物名复核（`dist/壶中天-0.1.0.dmg` 已在 11:36 产出）、
按 `docs/25` 的关键项上屏过一遍、`git tag -a v0.1.0`（本地，不推送）。

## 已知限制

1. **允许清单是滞后的**：新加一个模块配置键时，要么同步加一条清单项，要么它只能改配置文件——清单本身没有"自动发现"机制（通用渲染器才有）。
2. **`list` / `enum` 型配置仍然只能改文件**（如 shortcuts 的 `pinnedShortcuts`、timer 的 `timerPresets`）。
3. **日历 tab 与首页日历行是同一个开关**（`showCalendar`）：关掉日历行也关掉 tab，不能只留一个。
4. **用户手册的图是"某一版的样子"**：UI 一改就旧；图片与手册同仓库、同批提交，靠纪律而不是机制保持一致（维护钩子写进 `docs/08` 的回写清单）。
5. **版本的"修改日期"是手工维护的字段**：NOTICE 里那个日期靠每次同步上游时手改（已写进 `docs/04` 的同步检查单，但不是自动的）。
6. **配置控件写完那一行不会自己重画**（实现期上屏逮到并已修）：`commit()` 只发
   `ModuleRegistry.objectWillChange`（那是给**观察注册表的宿主视图**用的），本行自己不在其中——
   `Slider` 的拇指跟着点走、右侧数值文本却停在旧值。修法是行级 `@State refreshToken`（视图级 `Int`，
   不进偏好）；根治要等 config 有 `observe`（`docs/07` §2）之后整体简化。反证截图
   `evidence/t7-stale-value-before-fix.png`（config 域已是 `89.472…`、界面仍显示 `44`）。
7. **日历 tab 是原样接住的孤儿视图，高度自持**：`StandaloneCalendarView` 自己
   `.frame(height: maxTabContentHeight)`（本机面板 1154×652 下约 290pt），**下方留白**，左栏底部还有一条
   该视图自带的横向滚动条（`MonthGridView(isScrollable: true)` 的既有提示）。本批只接线、不改视图
   （派发口径：一对一接住那个孤儿视图）；要收掉留白得动视图本身，属下一批的形态调整。

## 验收标准

1. `xcodebuild test`（`DynamicIslandTests`）全绿；新增用例覆盖：日历模块的 manifest 与接管键 read-through、
   配置允许清单里的每条键都能解析（Localizable + manifest 键存在）。
2. `defaults read /Applications/壶中天.app/Contents/Info.plist CFBundleShortVersionString` = **0.1.0**；
   `sh tools/build.sh --dmg` 产出 `dist/壶中天-0.1.0.dmg`；`git tag` 里有 `v0.1.0`。
3. `grep -c "Gourd\|壶中天" CHANGELOG.md` ≥ 1 且顶部是自有变更段；`grep -n "修改版本\|modified version" README.md` 命中；
   `grep -n "2026-09-27" NOTICE` 命中；`grep -c "Copyright (C) 2026 Gourd Contributors" -r DynamicIsland/` ≥ 25。
4. 设置 → 组件里：四个模块的有效配置项可拨、拨动即时生效；接管模块的上游键有"由上游设置管理"标注。
5. 展开面板出现「日历」tab（由 `showCalendar` 控制），月历可翻月、当日清单正确；上屏截图。
6. `docs/guide/README.md` 七节齐全、至少 6 张仓库内图片（相对路径可解析）；README 里链接到它。

## 决策摘要

| ID | 决策 | 来源 | 理由 |
|---|---|---|---|
| D-01 | 版本号取 `0.1.0`（`MARKETING_VERSION` / `VERSION` / DMG 名同步） | 用户 | 功能成型但仍有空档，"第一个冻结的自用版"（§备选与取舍 ①） |
| D-02 | 归属照 fork 标准范式：**顶部一句话 + 归属小节给版本号**，两处都出现 | agent | GPL §5(a) 要求"显著"；同类项目没一家这么写，因而必须自己补（§做法 机制一） |
| D-03 | 补合规四笔（NOTICE 日期与改名、TRADEMARKS 无背书声明、COPYRIGHT_ASSETS 版权行、自建文件版权头） | agent | 调研逐条核出的缺口（§做法 机制二） |
| D-04 | CHANGELOG 分家：顶部自有变更段 + 上游历史保留并注明 | 用户 | 冻结的核心产物是"这一版包含什么" |
| D-05 | 独立日历**接线成日历模块的展开 tab**（不是删掉、不是只标注） | 用户 | 正是 docs/14 早写定的形态；删掉是丢功能（§备选与取舍 ②） |
| D-06 | 模块配置走**允许清单 + 不可编辑键明确标注**，不做通用渲染器 | agent | 范围控制；先解决"能改的能改、不能改的说清"（§备选与取舍 ③） |
| D-07 | 用户手册放 `docs/guide/`，README 两行引用；图片进仓库、相对路径 | agent | 内联必然立刻过期；外链失效文档就瞎（§备选与取舍 ④⑤） |
| D-08 | README 不挂徽章 / Star History / Roadmap | agent | 本仓库 CI 从未实跑，挂徽章等于造假（§明确不做） |
| D-09 | 通知列表行 × 的谓词补一条自动化断言；`＋N` 悬停 tooltip 的时延记进 docs/21 已知限制 | 用户 | 用户「7 条全部处理」里的第 7 条 |
| D-10 | 配置控件允许清单实到 **7 条 / 4 个模块**，区间一律复用模块自己的常量；`timeoutSeconds` **不给区间**（模块自己 1…300 夹取，设置页不重复一份约束） | agent | 范围控制 + 「同一个约束只有一处编码」；实现期与计划稿的唯一差异见 §接口与数据形状 |
| D-11 | 「写完 config 本行不重画」用**行级 `@State refreshToken`** 修（视图级 `Int`、不进偏好），不引 config `observe` | agent | 最小改动；根治留给 config 层（`docs/07` §2 落地后整体简化，§已知限制 6） |
| D-12 | 日历 tab **原样接住**孤儿视图：不改它的自持高度、不删它的横向滚动条 | 派发口径（一对一接住） | 接线批次不动视图形态；代价（下方留白）记进 §已知限制 7 |
| D-13 | 关闭态那枚「日进度 pill」= **`progress` 模块不再占折叠槽位**（`surfaces` 只留 `expanded`），不是换图标、也不是只关本机偏好 | 用户（2026-09-30 报「收起态长期挂着一枚亮度 HUD」）+ agent（落点） | 那枚 pill 与亮度 HUD 同形（`sun.max` + 百分比），而 D-20 早就判定该模块无行动价值、槽位默认内容归 `todos`；换图标只改观感、pill 仍在，关偏好则不是产品修复（三个候选见本批报告 §候选决策） |
| D-14 | README 的节序照派发片段（**归属在功能之前**，与同类项目的通用顺序不同） | agent | GPL §3 / §5(a) 的「显著标注修改」优先于版式惯例（T8 报告 §7 候选决策 1） |
| D-15 | T8 的候选决策「拍干净收起态时临时关 `inlineHUD` / `enableBrightnessHUD`」**随本次修复作废**：默认观感里已无那枚 pill，`docs/guide/assets/06-closed-state.png` 不必重拍 | agent（随 D-13） | 图的差异点消失；图注本来只写「刘海（收起态）」、没有声称 HUD 常驻，故与原图一致 |
