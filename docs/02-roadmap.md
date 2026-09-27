# 实施路线图

原则：**每个阶段结束时都要有一个自己每天在用的可用版本**，不做"半年后一次性交付"。

---

## P0 · 基座落地（目标：1 周）

> **详细可执行清单见 [08-p0-checklist.md](08-p0-checklist.md)**（基线冻结 / git 结构 / 改名清单 / 依赖治理 / CI / 合规 / 验收命令）。

- [ ] 在 `~/workspace/github/lagoon/` 初始化工程（本目录先把文档与脚本放好，应用工程下一阶段引入）
- [x] 确认 Xcode / macOS SDK 版本（Atoll 要求 macOS 14+；boring.notch 编译需 macOS 15.6+ 与 Xcode 26+）
      → 实测：Xcode 27.0 / Swift 6.4 / SDK 27.0 / macOS 27.0，app target 部署目标 14.6，工具链显著高于要求
- [ ] 从 `Atoll` 拉出 `Gourd` 应用工程：保留 GPL 头与版权声明，改 Bundle ID / 应用名 / 图标
      → 基线锁定 `v2.3.3-beta.3`（`c7305ec`），见 [08](08-p0-checklist.md) P0-1
- [ ] 配置 `atoll` remote 指向 Atoll，记录基线 tag（注意：上游默认分支是 `dev` 不是 `main`）
- [ ] GitHub Actions：构建 + 测试跑通
- [ ] `NOTICE` 补齐 Atoll 署名（**并保留上游原有的 boring.notch 署名段**，那是 Atoll 的 GPL 义务）

**验收**：本机能编译运行改名后的应用，刘海面板能折叠/展开，CI 绿灯。

---

## P1 · 内核与模块协议（目标：2～3 周）

- [ ] 定稿 `GourdModule` 协议与 `ModuleContext` 注入
- [ ] `NotchGeometry`：多屏、无刘海回退、屏变监听
- [ ] `NotchStateMachine`：折叠 / 悬停 / 展开 / 拖拽四态 + 单元测试
- [ ] `EventBus`：类型化事件 + 首批 13 个事件（字段级见 [07](07-config-and-events.md) §4）
- [ ] `ConfigStore`：JSON + `schemaVersion` + 迁移链 + 导入导出
- [ ] `ModuleRegistry`：注册、启停、失败隔离、视图超时保护
- [ ] 把 Atoll 现有功能**按新协议逐个改造成模块**（媒体、日历、系统状态优先）

**P1 开工前必须先补的三项设计**（当前文档未覆盖，是不做就会在 P1 卡住的地方）：

- [ ] **新运行时与上游 UI 的接缝**：折叠态槽位在 `ContentView` 的哪个位置渲染、展开面板的 tab 列表如何由 `ModuleRegistry` 驱动（上游 `NotchViews` 是硬编码枚举 + `TabSelectionView`）、`ModuleContent.view` 的挂载点在哪。**这是与上游耦合度最高、也最容易返工的一处**
- [ ] **`NotchStateMachine` 与上游 `DynamicIslandViewModel.notchState` 的关系**：是替换上游状态管理（要动上游文件、风险高），还是包装/观测上游已有状态（四态里 `hover`/`dragging` 上游已有部分实现）。**必须先定，否则会在两种做法之间反复**
- [ ] **内置模块逐项 manifest 清单**：10 个接管模块 + 5 个新增模块的 `id` / `surfaces` / `slot` / `permissions` / `config schema` 逐项写出来（模板见 [06](06-module-protocol.md) §2.1）

**验收**：把任意一个模块注释掉后应用仍能正常启动；新增一个空模块只需要实现协议 + 注册一行。

---

## P2 · 接管已有功能 + 新增 6 项（目标：4～5 周）

> **三处重要修正**（2026-09-27）：
> ① 逐文件勘察后确认 **Atoll 已实现约 40 个用户可见功能**，下面 P2a 列的"模块"里**大半上游已有实现** → 主体工作是**接管与包装**，不是从零写。
> ② 范围已冻结（[ADR-0011](00-decisions.md)）：**不删除上游任何功能**；不需要的功能用"默认不启用"表达。
> ③ 按需新增（[ADR-0012](00-decisions.md)）：**6 项上游没有但我们要用的功能**——快捷启动、农历、进度、Shortcuts 上岛、通知上岛、终端外部化。
>
> 逐功能的机制、配置项、权限与工作量见 [09-features-and-mechanisms.md](09-features-and-mechanisms.md) §5。

### P2a · 接管（把已有功能按模块协议包装，约 2 周）

- [ ] `stats`：CPU / 内存 / 网络速率 / 磁盘（上游已实现，含"展开才采样"的省电策略，**只做模块化包装**）
- [ ] `calendar`：下一个日程 + 今日待办（上游 EventKit 已实现，含提醒勾选）
- [ ] `nowplaying`：媒体控制 + 进度（**数据源收敛为系统 Now Playing 一路**，其余 6 个适配器保留不启用）
- [ ] `lyrics`：逐行歌词（上游 LRCLIB + NetEase 已实现；**补磁盘缓存**，离线可用）
- [ ] `shelf`：文件暂存 + 拖出 + AirDrop（上游已实现，含 LocalSend 局域网互传）
- [ ] `timer`：倒计时（上游**退出即丢、无通知** → 补状态持久化与到点通知）
- [ ] `clipboard`：剪贴板历史（上游已实现，0.5s 轮询 → 补电源优化）
- [ ] `controls`：音量 / 亮度 / 防休眠（上游已实现；勿扰与蓝牙维持只读）
- [ ] `weather`：天气（上游已实现，open-meteo 免 key）
- [ ] HUD 体系（上游三种风格已实现）
- [ ] 模块化边界按 [09](09-features-and-mechanisms.md) §8.1 的"只模块化 10 个"执行（其余保持上游原样）

### P2b · 新增（按成本从低到高，约 1.5～2 周）

- [ ] `lunar` 农历：`Calendar(identifier: .chinese)` + 预置节气表 + 抽样单测
- [ ] `progress` 日/周/月/季/年进度：`Calendar.dateInterval` 计算
- [ ] `shortcuts` 系统快捷指令上岛：`shortcuts list/run` 枚举与执行，可与 Shelf 文件联动
- [ ] `launcher` 快捷启动：App 扫描 + 搜索 + 自建使用频次 + 全局热键
- [ ] `terminal` 走外部 App（Ghostty）：新增 `external` 模式并设为默认（**优先级最低，放最后**；先实测 Ghostty 启动参数）

### P2c · 通知上岛（约 1 周，风险最高）

- [ ] **第一步：可行性探针**（0.5 天）——完全磁盘访问下只读通知中心 SQLite 并打印 5 条记录，验证 macOS 27 schema 可读
- [ ] 探针通过 → 完整实现（浮层 + 列表 + 点击打开 App）；不通过 → 转 AX 方案或推迟到 P3

**验收**：连续使用 7 天不掉帧、不崩、内存 <150MB；折叠态 CPU <1%。

---

## P3 · 定制化与配置体系（目标：2 周）

- [ ] 配置 schema → 设置界面自动生成
- [ ] 左右图标槽拖拽排序 / 隐藏 / 每槽数量上限
- [ ] 主题令牌：液态玻璃 / 毛玻璃 / 纯色，浅色深色自适应
- [ ] 多屏策略设置（内置屏优先 / 指定屏 / 全部）
- [ ] 配置导入导出 + 迁移测试
- [ ] 中英双语，文案全部走 Localizable

**验收**：不改代码就能把界面调成 Nook X 截图那种布局；导出配置能在另一台机器导入还原。

---

## P4 · 插件生态（目标：4 周起，可长期推进）

- [ ] `PluginHost`（XPC）：描述符校验、权限授权、看门狗、崩溃隔离
- [ ] `PluginSDK`（Swift）+ 一个示例插件（如 GitHub 通知）
- [ ] 扩展设置页：安装（拖入 .gourdplugin）、启用、权限查看、卸载
- [ ] `apiVersion` 兼容层与拒绝策略
- [ ] 第二阶段：JavaScriptCore 沙箱宿主 + 两个 JS 示例（番茄钟、比分/状态灯）
- [ ] 插件清单仓库（单独的 GitHub repo，只放描述符与下载链接）

**验收**：一个不懂本项目源码的人，靠一份文档能写出可加载的插件。

---

## P5 · 分发（与 P2 并行推进）

- [ ] Sparkle appcast + 自动更新
- [ ] Developer ID 签名与公证脚本（需要 Apple 开发者账号）
- [ ] Homebrew cask 提交
- [ ] README 英文版 + 截图/GIF

---

## 里程碑与自检

| 里程碑 | 判断标准 |
|---|---|
| M0 | 跑起来了，但和 Atoll 没区别 |
| M1 | 能按开关关掉任意模块，且应用不崩 |
| M2 | 我已经不用 Nook X 了 —— ⚠️ **范围冻结后需实测重估**：Nook X 独有而本项目当前不做的项见 [09](09-features-and-mechanisms.md) §4.2。建议 P2 完成后连续用一周，让实际使用暴露真实缺口 |
| M3 | 界面布局我不改代码就能调 |
| M4 | 有人（不是我）给我的应用写了插件 |

## 时间与精力预期

单人 + AI 助手的前提下：P0+P1 约 3～4 周业余时间，P2 约 4～5 周（P2a 接管 2 周 + P2b 新增 1.5～2 周 + P2c 通知 1 周），P3 约 2 周，P4 是长期项。**建议节奏是"每周交付一个能用的小功能"**，而不是憋大招。

## 风险检查点

- 若 P1 结束时无法把 Atoll 现有功能干净地改造成模块 → 回退方案是保留 Atoll 原结构，只把新功能按模块做（混合架构），代价是内部不统一。
  - 已量化的证据：`MusicManager` 2341 行、`SettingsView` 9696 行单文件、`BluetoothAudioManager` 2949 行——这三处不是能干净切开的模块。**建议 P3 之前接受 `SettingsView` 保持原样**。
- 若 P2 的 `nowplaying` 适配器在目标播放器上不稳定 → 上游的 7 个 source 机制各异、稳定性差别很大（TIDAL/Amazon/YouTube Music 尤其脆）。**策略：默认只开"系统 Now Playing"，其余按需开启**；[09-features-and-mechanisms.md](09-features-and-mechanisms.md) §2.A 有逐 source 的稳定性评估。
- 私有 API 面比预期大（**11 项**，见 [09](09-features-and-mechanisms.md) §3.1）→ 上游的**全部保留**，对策是逐处留降级路径 + 建台账，不做清零式重构。好消息：本轮 6 项新增功能里 5 项零私有 API，只有通知上岛引入一个新的私有数据依赖。
