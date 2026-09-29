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

提交范围 `1de20d4d..423e0918`（`1de20d4d` 是设计文档先行的方案门提交，其后 7 个提交：内核三件套 / 计时器模块 / 计时器第二入口 / 镜子模块 / 音乐模块 / 组件页两段 / 文档回写）。

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

**测试**：`DynamicIslandTests` 293 → **310 条 0 失败**（`TakeoverEnablementTests` 9 → 26 条）。

### 已交付 · P1 第一批 `p2-todos-facelift`（2026-09-29）

待办展开面板四视图左导航 + 右看板 + 行内优先级胶囊（异步写回系统提醒）；首页块顺序可在设置页上移/下移。设计文档 [18](18-p1-todos-and-order.md)。**A2（折叠态左右槽位）未随批落地**：它依赖状态/动作类模块（农历 / 计时器 / 剪贴板 / 启动台，属 P2a），做出来会是空槽位。

### 下一批 · 登记（2026-09-29）

> **2026-09-29 增补**：下一批的完整优先级清单（含本批暴露的缺口）已收在 [16](16-nookx-reference.md) **§4.4**，按 P0 / P1 / P2 分档并给了成本、依赖与判据。**P0 四项**：~~① 通知组件在首页有块~~、~~② 组件卡片说清"开了会看到什么、在哪看"~~、~~③ 待办块窄宽度下也显示清单~~（**三项已在 `p2-p0-visible` 批次落地，2026-09-29**）；**④ 月历入口回归仍待做**（需要先定形态：点日期头进月历 vs 加一个 calendar tab——这是产品选择，等用户拍板）。下面四项属 **P1**。

四项都来自 [16-nookx-reference.md](16-nookx-reference.md) §4.2 A 组（"值得参考"6 项）里本批未落地的部分；本批的「明确不做」已逐条给过排除理由（[17](17-nookx-adoption.md)）。

| # | 项 | 来源 |
|---|---|---|
| A2 | 折叠态两侧槽位的"可视化图标选择网格" | [16](16-nookx-reference.md) §4.2 A 组第 2 项 |
| A4 | 待办面板的"左导航 + 右看板"与优先级胶囊 | [16](16-nookx-reference.md) §4.2 A 组第 4 项 |
| A5 | 前台应用联动显示 | [16](16-nookx-reference.md) §4.2 A 组第 5 项 |
| A6 | 充电接入时的瞬浮 | [16](16-nookx-reference.md) §4.2 A 组第 6 项 |
