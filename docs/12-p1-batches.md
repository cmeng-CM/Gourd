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
- [ ] **CI 单测 job 复跑确认**：本批已定位并修复启动期主线程阻塞（见下「本批已完成」），疑似即 CI "test runner hung" 根因；推后看 CI，若仍红再按 runner 差异（WindowServer/TCC）单独处理。
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
