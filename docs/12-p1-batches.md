# P1 批次计划（09 功能清单 × P0 交付现状）

> 输入：[09](09-features-and-mechanisms.md) §6 路线图与 §8.1 已拍板边界、[02](02-roadmap.md) P1 条目、[06](06-module-protocol.md) / [07](07-config-and-events.md) 字段级规范、P0 交付（[10](10-p0-execution.md) / [11](11-verification.md)）。
> 节奏沿用 [02](02-roadmap.md) 的原则：**每周交付一个能用的小东西**。每批伴随：单测进 `DynamicIslandTests`、`sh tools/build.sh` 出包、CI 绿。

---

## P1-0 · 设计定稿与前置清障（0.5～1 周）

P1 开工前必须补齐的三项设计（[02](02-roadmap.md) 已列为前置）：

1. **新运行时与上游 UI 的接缝**：折叠态槽位在 `ContentView` 的渲染点、展开面板 tab 列表如何由 `ModuleRegistry` 驱动（上游 `NotchViews` 是硬编码枚举 + `TabSelectionView`）、`ModuleContent.view` 挂载点。与上游耦合最高、最易返工。
2. **`NotchStateMachine` 与上游 `DynamicIslandViewModel.notchState` 的归属**：替换（动上游，风险高）还是包装/观测（四态中 hover/dragging 上游已有部分实现）。先定，防止两种做法间反复。
3. **内置模块逐项 manifest 清单**：10 个接管（nowplaying/lyrics/stats/calendar/shelf/timer/clipboard/controls/weather/mirror）+ 5 个新增（launcher/lunar/progress/shortcuts/notifications）+ 终端配置，逐项写 `id` / `surfaces` / `slot` / `permissions` / `config schema`（模板 [06](06-module-protocol.md) §2.1）。

前置清障：

- [ ] **私有 API 台账**：把 [09](09-features-and-mechanisms.md) §3.1 的 11 项走查成"用途 + 降级路径"台账（落 `docs/`）。
- [ ] **ATS 对外域名清单**（[09](09-features-and-mechanisms.md) §8.2）：lrclib.net、music.163.com、open-meteo、raw.githubusercontent.com…（维持全局 ATS 现状，清单为将来收窄留依据）。
- [x] ~~**CI 单测 job 复跑确认**~~ → **CI 已关闭（2026-09-28，用户要求）**：GitHub Actions 停用，打包与验证全在本地（`sh tools/build.sh` + `xcodebuild test`）。原 runner 侧挂起结论见 [11](11-verification.md) §5；工作流文件保留未删，日后可一键恢复。
- [ ] **待用户拍板**：`AtollExtensionKit` 抬 pin 换 LGPL-3.0 的许可决策（阻塞的是 P4/P5 分发合规，不阻塞 P1 开发）。

**验收**：三份设计补进 [06](06-module-protocol.md)（或新文档）；manifest 清单逐项过审。

## P1-1 · 内核骨架（约 1 周）

- [ ] `GourdModule` 协议 + `ModuleContext` 注入落地（[06](06-module-protocol.md) §3/§3.4 字段级照做）
- [ ] `ModuleRegistry`：注册、启停、失败隔离、视图超时保护
- [ ] 新代码根目录 `DynamicIsland/{Kernel,Runtime,Modules}`——新代码全部进新目录（上游文件只做「接线」，沿用 P0 原则）
- [ ] `swift-format` 门禁升级为对 `{Kernel,Runtime,Modules}` blocking（`ci.yml` 注释里已预告此节奏）

**验收**（[02](02-roadmap.md)）：新增一个空模块 = 实现协议 + 注册一行。

## P1-2 · 几何与状态机（约 1 周）

- [ ] `NotchGeometry`：多屏、无刘海回退、屏变监听
- [ ] `NotchStateMachine`：折叠/悬停/展开/拖拽四态 + 单元测试（归属按 P1-0 定稿执行）

**验收**：刘海在主屏/副屏/无刘海屏上定位正确；四态迁移有单测覆盖。

## P1-3 · 事件与配置（约 1 周）

- [ ] `EventBus`：类型化事件 + 首批 13 个事件（字段级见 [07](07-config-and-events.md) §4）
- [ ] `ConfigStore`：JSON + `schemaVersion` + 迁移链 + 导入导出
- [ ] **"不投入"功能的默认值落地**：首启把 `enableScreenAssistant` 等写为 `false`（在 `ConfigStore` 初始化时写入，**不改上游源码**，[09](09-features-and-mechanisms.md) §8.1 已拍板）

**验收**：配置文件手改 `schemaVersion` 触发迁移链；导出的 JSON 能在另一台机器导入。

## P1-4 · 试点模块走通全链路（0.5～1 周）

- [ ] 选 **`progress`**（日/周/月/季/年进度，零私有 API、工作量极低）作为第一个 `GourdModule`：manifest → 注册 → 槽位渲染 → 配置生效，全链路走通
- [ ] 顺带把 `lunar` 做掉（1～2 天，同为零私有 API）——P2b 由此提前消化两项

**验收**（P1 总验收，[02](02-roadmap.md)）：注释掉任意一个模块后应用仍正常启动；新增模块零上游文件改动。

---

## 本批已完成（P0 收尾扩展，2026-09-27 晚）

不属于 P1，但在开工前一并落掉：

| 项 | 内容 |
|---|---|
| **Atoll 字样清扫** | 用户可见文案/品牌标识/内部标识全清：权限文案（pbxproj 10 条 ×2）、本地化（xcstrings 键+值、tr InfoPlist）、Settings 署名与链接（About 署名改「壶中天 / Gourd」，Donate/隐私政策改指本仓库）、菜单/无障碍/通知名/队列名等内部标识、上游赞助 FUNDING、`add_ui_test_target.rb` bundle id。**保留**：GPL 版权头、B 表冻结项（XPC/RPC 线协议名、Keychain service、`AtollExtensions/`）、`atoll-spotify` 回调 scheme、笔记 `atoll:id` 数据标记、kit 类型名（`AtollXxxDescriptor`）、pbxproj 派发产物引用 `Atoll.app` ×3。清后盘点：Swift 可见残留 0、xcstrings 0、权限文案 0 |
| **模块名反转（D-10 → Gourd）** | `PRODUCT_MODULE_NAME = Gourd`，4 个测试文件 `@testable import` 同步；季度同步在 pbxproj 该行的冲突为接受代价 |
| **上游定价远程拉取砍除** | `ModelPricingManager` 不再拉上游 feature 分支 raw URL；bundle 内 `pricing.json` 兜底既有 |
| **壶中天图标** | `AppIcon`（Release）/ `AppIconDev`（Debug，绿色 DEV 角标）十档全换 + 新 `GourdLogo` imageset（菜单/引导页用）；上游 `logo/logo2/ebullioscopic/LinkedIn` imageset 删除；SVG 源存 `tools/icons/` |
| **启动期主线程阻塞修复 ×2** | ① `DownloadManager`：init 在主线程同步枚举 TCC 保护的 `~/Downloads`，授权弹窗未响应即死锁（本地冷启 + CI headless 双杀）② `BluetoothAudioManager`：`IOBluetoothHostController.default()` 在 XCTest 宿主下 dispatch_once 卡死主队列。两处均已改为后台队列探测；本地单测恢复 **27/27**。**CI "test runner hung" 高度疑似同根因**，推送后观察 |
| **稳定签名身份 + 本地打包闭环** | ① 自签 10 年期证书 **`Gourd Local`**（`tools/setup-signing.sh`，pw 用户域信任；身份写入 pbxproj app target）——修复「ad-hoc 每次构建都变哈希 → TCC 授权反复弹」：**装一次、授一次，升级不再弹**；② `sh tools/build.sh` 支持 `--install` / `--dmg`（拖拽安装式 DMG 出到 `dist/`，`*.dmg` 已 ignore）——**打包全在本机完成，不依赖 GitHub**（`release.yml` 早已摘 push 触发、仅手动；其内容是上游签名/公证流程，本项目不采用） |

---

## 已交付批次记录

### P2 批次 · `p2-home-strip`（2026-09-29）

**范围**（用户定稿）：首页从「音乐 + 日历两栏写死」改为「已开启组件的横向 strip」（manifest 驱动、富余不拉伸、不滚动），并补上模块运行期开关与设置页「组件」卡片，让"开关即拼装"闭环。设计文档 [17-nookx-adoption.md](17-nookx-adoption.md)（D-01…D-14）。上下文：它是 [16-nookx-reference.md](16-nookx-reference.md) §4.2 A 组 6 项里**第 1 项与第 3 项**的落地。

提交范围 `1e8c8c0c..5b9c3c8b`（`1e8c8c0c` 是设计文档先行提交，`701452a0`…`5b9c3c8b` 是 5 个实现任务及跟随的文档回写；本批的文档回写提交在其后）。

| # | 任务 | 一句话结果 |
|---|---|---|
| T1 | 内核：`.home` surface + `homeEntries` 投影 + 布局纯函数 | `Surface` 加 `home`（校验规则未变）；注册表加 `ModuleHomeEntry` / `homeEntries`（排序键 `(order, id)`，与另两条投影同一比较器）；`HomeStripLayoutMath.plan` 三条规则（富余不拉伸 / 比例压缩取整 0.5pt / 尾部丢块）落成纯函数，契约与浮点边界写进 [17](17-nookx-adoption.md) 已知限制 10~11 |
| T2 | 内核：运行期模块开关 | `ModuleRegistry.setEnabled(_:for:)`（幂等；未知 id 记 warning 返回 `.disabled`）＋偏好键 `Defaults[.moduleEnableOverrides]`（**缺键 = 用户未表达**，回落 `manifest.defaultEnabled`）＋组合根启用门 `KernelBootstrap.enablementGate(registry:)`；**`failed` 定为不可逃逸终态**（置开不重试、置关不降级，D-13），`.activating` 期间的异步写回由**全局单调代次**作废 |
| T3 | 首页 strip 渲染器 + `NotchHomeView` 接缝（内置块） | 新建 `HomeStripView` + `HomeStripLayoutMath`；`NotchHomeView` 的**标准分支**改为渲染 strip，minimalistic UI 与歌词侧栏两条路径未动；内置三块（音乐 `300/420`、日历 `200/260`、镜子 `140/160`）就其位；日历块**自建**（日期头 + hover 日期轮 + 竖向多行），保留翻日期能力；`sizeThatFits`/`placeSubviews` 共用缓存 plan、丢块显式零提案两条硬约束写进 [17](17-nookx-adoption.md) 已知限制 12~15 |
| T4 | 待办模块的首页块 | `com.cmeng.gourd.todos` 的 `surfaces` 加上 `home`；首页块 = 三环横排（复用同一个 `TodoScopeRing`）+ 今日清单前 5 条，**块宽 < 220pt 时只画三环**（判据取放置后实测宽度）。默认面板宽下只有三环，已知限制 16~19 |
| T5 | 设置页「组件」卡片（新增 tab） | 新增 `SettingsTab.modules`（第 21 个 tab，第 22 个是 `about`）：一张卡 = 一个已注册模块（数据源 `ModuleRegistry.manifests` **全量**）；写路径定死「先落盘 `moduleEnableOverrides` 再 `setEnabled`」，失败回弹只把偏好写回 `false`；卡片 = 图标 + 名称 + 摘要 + surfaces 徽标 + 开关 |
| T6 | 文档回写 | 本表 + [06](06-module-protocol.md)（`home` 入词表）/ [09](09-features-and-mechanisms.md) §5.8（首页 strip）/ [13](13-runtime-kernel.md)（本批小节与已知限制 31~35）/ [14](14-module-manifests.md)（todos 行）/ [16](16-nookx-reference.md)（§4.2 本批状态列） |

**本批边界（零新增权限）**：没有新 capability、没有新 TCC 授权、没有新出站请求。首页块都是进程内视图，组件开关只写本机偏好。

**本批没做**：折叠态左右槽位的图标网格、待办面板"左导航 + 右看板"重构、前台应用联动、充电瞬浮（见下表）。

**测试**：`DynamicIslandTests` **199 条**（本批新增 `HomeStripLayoutTests` 16 条 + `ModuleToggleTests` 14 条，`ModuleKernelTests` 增补 todos 与首页投影断言）。

### 已交付 · `p2-launcher`（2026-09-30）

启动台/快捷启动：扫三目录一层 + Spotlight 使用数据排序，展开面板 tab（搜索 + 应用网格 + 点一下启动并收起 + 右键固定），只声明 `expanded`、默认关、零权限。设计 [19](19-launcher.md)。执行期发现并修掉一个静默失效缺陷（NSMetadataQuery 依赖主线程 run loop）。**快捷指令（Shortcuts）仍是另一个未落地模块**（P2b 第 3）。

### 已交付 · `p2-takeover`（2026-09-30）

组件页看得见、管得着：**计时器 / 镜子 / 音乐三个已实现功能真接管为模块**（模块拥有渲染点、**启用真源就是上游那个开关键本身**，上游三处写死的分支删除、不并存），**剪贴板 / 日历 / 锁屏天气 / 统计 / 文件架 / 终端 / 便签七个做成上游开关卡**（纯登记，不改渲染归属）。设计 [20](20-component-page.md)（D-01…D-16）。它同时把 [16](16-nookx-reference.md) §4.4 P1 第 6 项「组件化继续」往前推了一格：这一次补的不是"看得见"，而是"组件页管着的是不是真的那件事"。

提交范围 `1de20d4d..6e70fc23`（`1de20d4d` 是设计文档先行的方案门提交，其后 9 个提交：内核三件套 / 计时器模块 / **T1 修复** / 计时器第二入口 / 镜子模块 / 音乐模块 / 组件页两段 / 文档回写 / **T6 修复**）；**本批还有一次终审修复波提交在其后**（M1 首页块存在性的观测源 + [20](20-component-page.md) 的文档事实校正），本行写的范围截至 `6e70fc23`。

| # | 任务 | 一句话结果 |
|---|---|---|
| T1 | 内核：接管三件套 + 门 + 重同步桥 + 开关写路径 | 三条钩子（`takeoverEnableKey` / `isTabVisible()` / `homeBlockWidth`，**协议要求 + 扩展缺省**）、`ModuleHomeBlockWidth`；启用门改**三段判定**（接管键 → `moduleEnableOverrides` → `manifest.defaultEnabled`）；`startTakeoverBridge` 订阅每个接管模块那一个上游键（`options: []` + `change.newValue`）把注册表状态拉回来；`ModuleEnablementWrite` / `ModuleEnablementRollback`（回弹对接管模块是空操作） |
| T2 | 计时器接管模块 + tab 表移除 + 计数回归 | `TimerModule`（只声明 `expanded`，渲染点 = 上游 `NotchTimerView`，`isTabVisible()` = `timerDisplayMode == .tab`）；`TabSelectionView` 的 timer 分支与 `enabledStandardTabCount()` 的 `+1` 同批删除，对计数的贡献 1 / 0 / 0 由用例钉住 |
| T3 | 计时器的第二入口与高度 | 新增 `DynamicIslandViewCoordinator.isTimerSurfaceSelected()`；**三处赋值点**（悬浮聚焦 / 点预设 / `startCustomTimer`）改走 `selectModule(TimerModule.moduleID)`；两处 250pt 高度档改判据（否则「计时器在跑 + 悬浮展开」会落到"内容在、无 tab 高亮 + 默认高度"） |
| T4 | 镜子接管模块 + 顺序表历史键映射 | `MirrorModule`（只声明 `home`，判据 `showMirror && cameraAvailable`，块宽 140/160）；`HomeBlockOrdering.migratingLegacyIDs`（`builtin.music` / `builtin.mirror` → 模块 id，仅当新键缺席、只读不写） |
| T5 | 音乐接管模块 + 命名空间环境注入 | `MusicModule`（只声明 `home`，判据沿用旧内置块表达式但**不含展开态**，块宽 300/420）；`EnvironmentValues.homeAlbumArtNamespace`（本仓第一处 `EnvironmentKey`：宿主注入、模块自带 `@Namespace` 兜底） |
| T6 | 组件页功能卡段 + 接管卡写路径与文案 | 第一段七张卡（四张既有 + 三个接管，各多一行 `settings.modules.effect.*`）；第二段「功能」七张卡（`settings.features.*`）；写路径收在 `ModuleEnablementWrite`、回弹问 `ModuleEnablementRollback`；顺序节只剩模块块；xcstrings +18 条 |
| T7 | 文档回写 | 本文 + [09](09-features-and-mechanisms.md) §5.8/§8.1 + [14](14-module-manifests.md) §1/T-3/T-12 + [16](16-nookx-reference.md) §4.4 + [17](17-nookx-adoption.md) 已知限制 5/7 与块宽取值 + [18](18-p1-todos-and-order.md) 接口节 + [20](20-component-page.md) 终稿 |

**本批边界（零新增权限、零新出站）**：没有新 capability、没有新 TCC 授权、没有新出站请求、没有新子进程——只搬渲染归属与开关真源（与 `p2-home-strip` 同一条边界）。

**本批没做**：日历行 / 锁屏天气 / 剪贴板 / 统计 / 文件架 / 终端 / 便签的**渲染接管**（只给功能卡）、tab 排序机制、`config` 写路径接管（仍只登记键名，读写走上游键）。逐条见 [20](20-component-page.md) §明确不做 / §实际交付 · 遗留项。

**测试**：`DynamicIslandTests` 293 → **311 条 0 失败**（`TakeoverEnablementTests` 9 → **27** 条；311 / 27 是 T6 修复提交 `6e70fc23` 上的最后一次全量结果，终审修复波复跑同值）。

### 已交付 · P1 第一批 `p2-todos-facelift`（2026-09-29）

待办展开面板四视图左导航 + 右看板 + 行内优先级胶囊（异步写回系统提醒）；首页块顺序可在设置页上移/下移。设计文档 [18](18-p1-todos-and-order.md)。**A2（折叠态左右槽位）未随批落地**：它依赖状态/动作类模块（农历 / 计时器 / 剪贴板 / 启动台，属 P2a），做出来会是空槽位。

### 已交付 · `p2-honesty`（2026-09-30）

两处「界面没说清楚」各修一处，设计 [21](21-strip-honesty.md)（D-01…D-08）。

- **首页丢块不再无声**：条尾 `＋N` 小胶囊（悬停列被丢块名，用户据此知道"把面板拉宽就能看见"）。预留位在**纯函数**里定（`plan(…:tailReserve:)` 第四参 + `Plan.droppedCount` / `tailReserveUsed`，缺省 0 = 改动前行为）；视图与 Layout 的宽度声明**同源**（视图先把每块宽度解析成非可选数组，同一个数组既喂块壳也喂 `HomeStripLayout(items:tailHintWidth:)`，Layout 不再从 subviews 取声明/测量）。**丢块规则一字未动**（仍从尾部丢、不滚动、不压扁，[17](17-nookx-adoption.md) D-02/D-03 不变）；边界处可能因此多丢一块（[21](21-strip-honesty.md) §已知限制 6）。
- **通知的 × 说实话**：只动文案与文档，**不动取数与关闭实现**（D-04）。列表行 × 的 `.help` 与**新增的 `.accessibilityLabel`**（此前只有 `.help`、读屏读不到）按 `NotificationStore.willAlsoCloseSystemBanner(for:)` 分档——判据与 `dismiss` 内部那条**同一份**（抽成私有 `listRowCloseHandle` 两处共用）：有句柄 → 「同时关掉系统通知」、否则 → 新 key `module.notifications.removeFromList`（中英 `translated`）；`readOnlyNote` 中英同步。四格语义表落在 [09](09-features-and-mechanisms.md) §5.5。
- **测试**：`DynamicIslandTests` **315 条 0 失败**（`HomeStripLayoutTests` 17 → **21**：新增四组预留位用例——不丢块不预留 / 生产档 702 可见块数不变 / 边界档 660 多丢一块 / 缺省 0 等价）。改动文件新增告警 0。
- **覆盖审计**：`workflow.py check p2-honesty` 零 ERROR；本条覆盖表五行的产物（`DynamicIslandTests/HomeStripLayoutTests.swift`、`DynamicIsland/Host/HomeStripView.swift`、`DynamicIsland/Modules/NotificationsModule.swift`、`docs/21-strip-honesty.md`）均在；验收 grep 全命中（`blockWidths` / `droppedHintWidth` 在 `HomeStripView.swift`；`removeFromList` 在模块与 xcstrings 各一处；`willAlsoCloseSystemBanner` 有定义 `:422` 与调用点 `:1272`）。
- **零权限边界**：不新增 TCC 权限、不引入私有 API、不新增出站请求、不新增子进程（与 `p2-home-strip` / `p2-takeover` 同一条）。
- **遗留**（详见 [21](21-strip-honesty.md) §实际交付）：实机 `＋1` 观感与「点通知 × 之后 `performAndVerify` 的返回」都**没有本批的现场证据**（后者受已装实例的 DB 通道被 TCC 拒绝 + 本机无横幅上屏所限）；通知谓词无断言（`HomeStripLayout` 的 Cache 复用判据也没有）；**新 key 已有断言**（`ModuleKernelTests` 的解析名单，删 catalog 该 key 会红）；浮层 × 的无障碍标签仍是缺口。

提交范围 `682b4bd8..c6799692`（T1 `8eafb8be`：纯函数预留位 + 同源重构 + 提示视图 + 4 条用例；T2 `d23ede48`：只读谓词分档文案 + `docs/09` §5.5 四格表；T3 `14261efe`：文档回写；末尾 `c6799692`：**T2 修复**——新 key 进 `ModuleKernelTests` 解析名单。范围非连续，修复那一笔夹在 T3 之后）。`docs/17` 已知限制 22 已就地改判（"strip 没有 `+N` 提示"那条关闭）。

### 已交付 · `p2-shortcuts-frontapp`（2026-09-30）

两个**新增内置模块**：**快捷指令**（展开面板一个 tab：搜系统快捷指令、点一下跑、固定常用的——取数与运行都走 `/usr/bin/shortcuts`，限时 + 模块级禁并发、缓存存原始行）与**前台应用联动**（首页一块：当前前台应用的图标与名称 + 最近切换的一排小图标，点一下切回去——事件源是 `NSWorkspace` 的"某应用被激活"通知，公开 API、零 TCC）。设计 [22](22-shortcuts-and-frontapp.md)（含 D-01…D-21）。它落的是 [16](16-nookx-reference.md) §4.2 A5「前台应用联动显示」的**首页块**一半（**侧槽一半仍留**），同时把 `docs/14` §1 里原位挂着零实现的 `shortcuts` 行做成真模块。

提交范围 `412f72e3..4480f453`（T1 `412f72e3` 解析/过滤/子进程接缝 · T2 `8c2df58b` 快捷指令模块与 tab UI · T3 `67bf8431` 前台历史纯函数与事件源 store · T4 `4480f453` 前台应用模块与首页块；**本批的文档回写提交在其后**）。

| # | 任务 | 一句话结果 |
|---|---|---|
| T1 | 快捷指令：解析、过滤与子进程接缝 | `ShortcutListParser.parse`（**从行尾往回找第一个 ` (`**，形状不符即丢、不猜）/ `ShortcutFiltering.visible`（固定在前保持固定表顺序，搜索对 name 与 identifier 大小写不敏感）/ `ShortcutRunResult`；两个注入点（`ShortcutsListing` / `ShortcutsRunning`）+ 两个真实现（`list` 与 `run` 都限时、`Task` 竞速 + 超时 `terminate()`、输出走 `--output-path` 读回即删） |
| T2 | 快捷指令模块与 tab UI | manifest（`[.expanded]` / 默认关 / `["shortcuts:run"]` / config 四键）+ `ShortcutsStore`（`load` 读缓存、`refresh` **先写回原始行再发布**、`togglePin` 先落盘再刷新、`run` 走 `isRunning` 闸门）+ tab 视图（搜索框 / 刷新 / 列表 / 结果行 / 空态）；`builtinModules` 加一行；xcstrings +15 键 |
| T3 | 前台应用历史纯函数与事件源 store | `FrontAppSnapshot` / `FrontAppHistory`（去重移前、截到上限、排除自身、夹取 3…8 的 `clampedLimit`）**不依赖 AppKit**；`FrontAppStore` 订阅 `didActivateApplicationNotification`、初值取 `frontmostApplication`（只种 `current`）、夹取只做一次、按 id 缓存图标 |
| T4 | 前台应用模块与首页块 | `FrontAppModule`（`[.home]` / `order 30` / 默认关 / `[]` / config 一键 `maxRecentApps`）+ 同文件的首页块视图（当前应用图标 28 + 名称、最近一排 20pt 小图标可点回切、空态画 `—`、块内 `capacity(forWidth:)` 排版预算）；`builtinModules` 加一行；xcstrings +5 键 |
| T5 | 文档回写 | 本文 + [22](22-shortcuts-and-frontapp.md) 终稿（接口签名 / 已知限制 9~14 / 实际交付 / D-08…D-21）+ [14](14-module-manifests.md) §1 两行与 §4.1、开头与 T-1/T-5/T-9/T-12 计数 + [09](09-features-and-mechanisms.md) §5.4/§5.8/§8.1 + [16](16-nookx-reference.md) §4.2 A5 与 §4.4 P1-8 |

**本批边界（零新增权限、零新增 capability）**：快捷指令声明的是 06 §7.1 **既有**的 `shortcuts:run`，前台应用 `permissions: []`；两个都零 TCC、零私有 API、`defaultEnabled: false`。**唯一的既有面扩展**是快捷指令会起 `/usr/bin/shortcuts` 子进程（限时 + 禁并发，沿用 §3.2 既有模式）——`docs/15` 的台账口径不变（系统 CLI，不是私有 API）。

**本批没做**（[22](22-shortcuts-and-frontapp.md) §明确不做）：`--input-path`（Shelf 联动，没有输入源）、文件夹分组、快捷指令的折叠态槽位与前台应用的**折叠态侧槽**（都随左右槽位那批）、大输出落盘 + 「在 Finder 中显示」、窗口标题、按 App 的信息模板、持久历史。

**测试**：`DynamicIslandTests` 315 → **341 条 0 失败**（新增 `ShortcutsFrontAppTests` **26 条**：解析 5 / 过滤 4 / 快捷指令 manifest 契约 2 / 快捷指令取数与并发闸门 5 / `RecordingConfigHandle` 假体自检 1 / 前台历史 6 / 前台模块 3；`ModuleKernelTests` 内置清单 8 → **9 行**并同步两段投影断言）。改动文件新增告警 0。

**覆盖审计**：`workflow.py check p2-shortcuts-frontapp` **零 ERROR**（一条 WARN：D-01…D-07 七条决策来源是 agent、未逐条经用户确认）；D-07 的四个不做项（`input-path` / `folders` / `windowTitle` / `showInFinder`）在 `DynamicIsland/` 与 `DynamicIslandTests/` 全域 grep **零命中**、用例文件里 `Process(` 零命中；`func parse(lines` 在 `ShortcutCatalog.swift:43`；`clampedLimit` 定义 `FrontAppHistory.swift:87`、调用点唯一（`FrontAppStore.swift:70`）；`capacity(forWidth:)` 在 `FrontAppModule.swift:265`。

**遗留**（详见 [22](22-shortcuts-and-frontapp.md) §实际交付 末段与 §已知限制 1/10/13）：真跑一条系统快捷指令、首次运行的系统自动化提示、首页块的点小图标回切、前台事件的真实投递、列表缓存的过期行为——**都没有本批的现场证据**（用例不跑真命令、前台样本全是手造快照）。两条实现期实测的边界：**超时是软界**（`terminate()` 后仍要等子进程真的退出，子进程忽略 `SIGTERM` 时实际用时超过 `timeoutSeconds`）；**前台块窄块里最多画 6 格**（180pt 下，配 7/8 时超出的静默不画、没有 `＋N` 提示）。

### 已交付 · `p2-home-fit`（2026-09-30）

按用户 2026-09-30 的**五条实测反馈**修首页，设计 [23](23-home-fit.md)（D-01…D-11）。五条都**改了用户可见行为**，
其中一条（最小宽度下的空白块）先取证再改：① 首页日历行的两条渐变遮罩**按需**（`showsScrollFades`，独立日历那一档保留）；
② 高度不足时**先收日历行、保住 strip**（判据收成纯函数 `HomeVerticalFit`，改动前是反的）；
③ 前台应用块内容 = **所有打开的常规 App**（现取 `NSWorkspace.runningApplications`，过滤 `.regular` / 无效 pid / 空名 →
排除自身 → 排序 → 同 id 去重；`recent` 降级为排序依据）；④ 修最小宽度（770pt）下"块被分配宽度却空白"
（根因实测是**尺寸反馈**——`sizeThatFits` 上报的宽度被下一趟当提案宽，修法是视图侧把提案宽钉在可用宽上，一行）；
⑤ 音乐封面可配置（模块 config 新增 `showAlbumArt`，组件页音乐卡多一行「显示封面」开关）。

提交范围 `f56c8a54..ac9a9aeb`（`cdbaa197` T1+T2+T5 · `f78d8a8c` T3 · `13ceebb9` T4 · `ac9a9aeb` T5 修复；本批的文档回写提交在其后）。

| # | 任务 | 一句话结果 |
|---|---|---|
| T1+T2+T5 | 日历渐变按需 + 高度取舍反转 + 封面开关 | `MonthGridView(showsScrollFades:)`（默认 `true` = 独立日历现状，首页行传 `false`）；新文件 `HomeVerticalFit`（三档 `.both` / `.stripOnly` / `.calendarOnly`，阈值闭区间：面板 ≥470 → 两排 / 168…469 → 只有 strip / ≤167 → 空面板）；`MusicModule` 的 `showAlbumArt`（boolean，默认 `true`，关档走 `MusicControlsView` 不留空洞） |
| T3 | 前台应用块改成"所有打开的常规 App" | `FrontAppStore.switcherApps`（**每次访问现取一次**，注入点 `FrontAppRunningAppsProvider` / 值类型 `FrontAppRunningApp` —— 摊成值类型是为了让 `.regular` 过滤可被用例钉住）；块内下半改成网格，格数由 `FrontAppGridBudget`（**宽 × 高两维**）定；`maxRecentApps` 降级为"`recent` 的记忆长度"；两条激活失败路径都记 `warn` |
| T4 | 修最小宽度下的空白块 | 探针取证（`evidence/probe-770/`）钉死根因后**只改一处**：`HomeStripView` 的 `.frame(width: available, alignment: .leading)`；`HomeStripLayout` 的规则与 cache 一字未动；新增**宿主级用例**（真 `HomeStripView` 挂 `NSHostingView`，断言"被判可见的块都拿到宽度、空白块数 == `＋N`"） |
| T5 修复 | 封面开关的界面入口 | 组件页音乐卡一行「显示封面」（`ModuleSettingsSection.configControls` 逐字段写死的**一条**，不做通用 config 渲染器）；写路径 = `config.set` 落盘 → `objectWillChange`，模块侧现读 config，**面板开着也立刻变样** |

**测试**：`DynamicIslandTests` 341 → **362 条 0 失败**（`HomeStripLayoutTests` 21 → **34**：T2 的三档/阈值/顺序反转 +
T4 的两条宿主级用例；`TakeoverEnablementTests` 27 → **30**；`ShortcutsFrontAppTests` 26 → **31**）。
五段变异各有红（判据反转 4 条 / 封面恒 true 1 条 / `.regular` 政策 3 断言 / 去掉那行修复 9 断言 / T5-fix 写反 5 断言）。
改动文件新增告警 0。

**上屏证据**（`.workflow/p2-home-fit/evidence/`，每条改完都看过）：`t1-home-no-fade.png` + `t1-fade-counterfactual.png`
（反事实：打回 `true` 两条暗带复现）+ `t1-fade-profile.txt`（亮度剖面 0.348 → 0.602）；`t2-both.png` / `t2-strip-only.png` /
`t2-calendar-only.png`（三档高度）；`t3-switcher.png` / `t3-cell-hover.png` / `t3-after-click.png` /
`t3-switcher-after-switch.png` + `t3-running-apps-probe.txt`（18 个常规 App 直读，台前调度是 `.accessory` 被挡在外）；
`probe-770/repro-770-blank.png` → `t4-770-fixed.png` / `t4-900.png` / `t4-1088.png`（修复前 vs 后三档宽度）；
`t5-albumart-on/off.png` + `t5-ui-toggle.png` + `t5-ui-albumart-on/off.png`（同一帧里开关与块内容一起变）。

**零权限边界**：不新增 TCC 权限、不引入私有 API、不新增出站请求、不新增子进程（`NSWorkspace.runningApplications`
是公开 API）——与 `p2-home-strip` / `p2-takeover` 同一条。

**遗留**（详见 [23](23-home-fit.md) §实际交付 遗留项）：独立日历的"渐变保留"**无运行期入口**（`StandaloneCalendarView`
无调用点、`CalendarView` 只有 `#Preview`），只能按代码默认档 + 反事实截图论证；770pt 下只显示 2 块 + `＋N = 2`
是**宽度预算的必然**（四块需可用宽 ≥864，面板 ≈932pt 起）而不是缺陷；封面关掉后块宽仍 300/420；块内网格溢出静默不画；
`showsScrollFades` 的默认值与 `MusicHomeBlockView` 的分档**没有自动化断言**（靠唯一实参 / 截图）。

### 已交付 · `p3-freeze`（2026-09-30）

**冻结 v0.1.0**（设计 [24](24-release-freeze.md)，9 个任务 / 15 条决策）。范围：① 版本身份分家
（`VERSION` / `MARKETING_VERSION` = `0.1.0`，构建号 1197，DMG 名 `壶中天-0.1.0.dmg`）；② 许可与归属合规四笔
（NOTICE 日期与改名、TRADEMARKS 无背书、COPYRIGHT_ASSETS、自建文件版权头）+ `docs/03`/`04` 口径；
③ CHANGELOG 分家（顶部自有段 + 上游历史保留）；④ 冒烟清单 `docs/25-release-smoke.md` 成文；
⑤ 独立日历接线成日历模块的展开 tab（`showCalendar` 一个开关管两处）；⑥ 组件页配置编辑口（允许清单 7 条 / 4 模块，
接管键标「由上游设置管理」）；⑦ README 重写 + 带图例的用户手册（`docs/guide/` + 7 张仓库内截图）；
⑧ 通知 × 谓词的自动化断言 + `＋N` tooltip 时延记档。**收尾时另修一枚关闭态「日进度 pill」**（见下）。

**本批追加的缺陷修复（收尾取证）**：用户报「收起态长期挂着一枚亮度 HUD」——取证落在 **`progress` 模块的
折叠态中央槽位**（`sun.max` + 日进度百分比，`ProgressModule.swift` 的 `ProgressCompactView`），
关闭态与亮度 HUD 同形；`inlineHUD` / `enableBrightnessHUD` 与它无关（那两条管的是亮度 HUD 自己的链）。
修法是该模块**不再占折叠槽位**（`surfaces` 只留 `expanded`、`slot` 记 `nil`、`order 30` 仍供展开 tab 排序），
进度改在展开面板看；`docs/09` §5.3 / `docs/14` / CHANGELOG 同步。证据：收起态 0/15/30/45/60/75 秒逐张干净
（`evidence/hud-fix-collapsed.png`）、亮度 HUD 仍正常弹（`evidence/hud-fix-brightness-works.png`）、
变异（把 `surfaces` 改回）pill 复现（`evidence/hud-fix-mutation-repro.png`）、偏好前后逐键一致。

| # | 任务 | 一句话结果 |
|---|---|---|
| T1 | 版本身份分家 | `VERSION` / 两处 `MARKETING_VERSION` = `0.1.0`、构建号 1197；应用与 `dist/壶中天-0.1.0.dmg` 自报 0.1.0 |
| T2 | 许可与归属合规补口 | NOTICE 加首次修改日期与改名重打包；TRADEMARKS 加 nominative use 一句、删「以 Atoll 之名营销」；COPYRIGHT_ASSETS 分段；自建 `.swift` 统一版权头（上游文件头一字未动） |
| T3 | CHANGELOG 分家 | 顶部 `[0.1.0] - 2026-09-30` 自有段（本批又补 2 条新增 + 1 条缺陷修复）；上游历史保留并注明来源 |
| T4 | 冒烟清单成文 | `docs/25-release-smoke.md`：逐条「动作 → 期望 → 证据」+ 前置条件 |
| T5 | 两处断言/观感缺口 | `TakeoverEnablementTests` 给 `willAlsoCloseSystemBanner` 补可构造用例（句柄台账两态）+ 变异红；`＋N` 悬停时延写进 `docs/21` |
| T6 | 日历展开 tab | `Modules/Takeover/CalendarModule.swift`（`surfaces [.expanded]`、真源 `showCalendar`、内容 = 孤儿视图 `StandaloneCalendarView()`）；内置清单 9 → 10 |
| T7 | 组件页配置编辑口 | 允许清单 7 条 / 4 模块（music / launcher / shortcuts / frontapp），读写共用 `ManifestConfigHandle`；另修「写完本行不重画」（行级 `@State refreshToken`） |
| T8 | README + 带图例手册 | `README.md` 68 行（顶部一句话写「修改版本」、归属小节给上游版本号与不背书、不挂徽章）；`docs/guide/README.md` 七节 + 7 张实机截图（①②③ 烧进图里） |
| T9 | 文档回写 | 本段 + [24](24-release-freeze.md) 的 §实际交付 / §已知限制 6·7 / §决策摘要 D-10…D-15；CHANGELOG 补口 |

**测试**：`DynamicIslandTests` **367 条 0 失败**（本轮只动 `ModuleKernelTests` 里 progress 的三组断言）。
五段变异各有红（T5 谓词、T6 日历接管键、T7 配置键可解析 / 写路径、本批 `surfaces`）。

**上屏证据**（`.workflow/p3-freeze/evidence/`）：`t1-*`、`t2-*`、`t5-*`、`t6-calendar-tab.png` / `t6-calendar-month-nav.png`、
`t7-config-controls.png` / `t7-launcher-config.png` / `t7-launcher-effect.png` / `t7-stale-value-before-fix.png`、
`t8-raw-*.png`（7 张）+ `docs/guide/assets/*.png`、`hud-fix-*.png`（收起态 75 秒采样 / 亮度 HUD / 变异复现）。

**遗留**：`dist/壶中天-0.1.0.dmg` 与本地 `v0.1.0` 标签由控制器收尾（本批不做远端动作）；
`docs/guide` 的图与手册靠纪律保持一致（[24](24-release-freeze.md) §已知限制 4）；日历 tab 下方留白见 §已知限制 7；
配置控件的 `list` / `enum` 型仍只能改配置文件（§已知限制 1·2）。

### 下一批 · 登记（2026-09-29）

> **2026-09-29 增补**：下一批的完整优先级清单（含本批暴露的缺口）已收在 [16](16-nookx-reference.md) **§4.4**，按 P0 / P1 / P2 分档并给了成本、依赖与判据。**P0 四项**：~~① 通知组件在首页有块~~、~~② 组件卡片说清"开了会看到什么、在哪看"~~、~~③ 待办块窄宽度下也显示清单~~（**三项已在 `p2-p0-visible` 批次落地，2026-09-29**）；**④ 月历入口回归仍待做**（需要先定形态：点日期头进月历 vs 加一个 calendar tab——这是产品选择，等用户拍板）。下面四项属 **P1**。

四项都来自 [16-nookx-reference.md](16-nookx-reference.md) §4.2 A 组（"值得参考"6 项）里本批未落地的部分；本批的「明确不做」已逐条给过排除理由（[17](17-nookx-adoption.md)）。**2026-09-30 更新**：其中 **A5 的首页块一半已落地**（`p2-shortcuts-frontapp`，其**内容口径随后由 `p2-home-fit` 改判**为"所有打开的常规 App"——[23](23-home-fit.md) §做法 机制三），侧槽一半仍留；其余三项不变。

| # | 项 | 来源 |
|---|---|---|
| A2 | 折叠态两侧槽位的"可视化图标选择网格" | [16](16-nookx-reference.md) §4.2 A 组第 2 项 |
| A4 | 待办面板的"左导航 + 右看板"与优先级胶囊（**2026-09-29 已落地**，批次 `p2-todos-facelift`） | [16](16-nookx-reference.md) §4.2 A 组第 4 项 |
| ~~A5~~ | ~~前台应用联动显示~~ **首页块形态已落地（`p2-shortcuts-frontapp`，2026-09-30）**：首页一块显示当前前台应用 + 最近切换（点小图标切回，事件源 = `NSWorkspace` 前台变化通知）；**折叠态侧槽形态仍留**（随 A2 那批） | [16](16-nookx-reference.md) §4.2 A 组第 5 项 |
| A6 | 充电接入时的瞬浮 | [16](16-nookx-reference.md) §4.2 A 组第 6 项 |
