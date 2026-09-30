# 许可证矩阵与合并规则

本项目以 **GPL-3.0** 分发（见 ADR-0001）。下表决定"哪些代码能进这个仓库、以什么方式进"。

## 1. 规则

| 上游许可 | 能否并入本工程 | 方式与义务 |
|---|---|---|
| **MIT / BSD / ISC** | ✅ 可以 | 保留原版权声明与许可文本（进 `NOTICE` 或随文件保留 `LICENSE`） |
| **Apache-2.0** | ✅ 可以 | 保留版权与许可、保留上游 `NOTICE`（若有）、注意专利授权条款；修改文件需标注 |
| **MPL-2.0** | ✅ 可以 | **文件级 copyleft**：MPL 文件必须保持 MPL 并保留声明；修改过的 MPL 文件其源码需公开（其余文件可用 GPL） |
| **GPL-2.0 / GPL-3.0** | ✅ 可以 | 整体按 GPL-3.0 分发（§5(c)）；逐字复制源码须保留版权与许可声明（§4）；分发二进制须提供对应源码（§6）；**标注修改并给相关日期**（§5(a)）；标注以本许可发布及 §7 附加条款（§5(b)）。**§5(d) 豁免**——上游 Atoll 的交互界面本就未显示 Appropriate Legal Notices，依 §5(d) 末句"上游没有的，你的作品也不必加上"，**本仓库 App 内无需许可窗**（这不是遗漏，是豁免） |
| **AGPL-3.0** | ❌ 不并入 | 除非整个项目接受 AGPL。仅可阅读思路 |
| **无 LICENSE 文件** | ❌ 不并入 | 默认保留所有权利。仅可阅读思路与文档 |
| **README 声明许可但缺 LICENSE 文件** | ⚠️ 有条件使用 | 声明本身是该作者的授权意图，但缺许可文本属不合规状态。**可先用**，但必须在首次分发二进制前解决：向上游提 issue/PR 补齐文件，或换实现。登记时须标注"待上游补文件" |
| **专有 / 未知** | ❌ 不并入 | 同上 |

**本仓库的 GPL 义务落点**（fork 增量；条号逐条对应上表 **GPL-2.0 / GPL-3.0** 行的括号）：

| 条号 | 义务 | 本仓库落点 |
|---|---|---|
| §4 | 逐字复制源码时保留版权与许可声明 | 上游文件头（`Copyright (C) 2024-2026 Atoll Contributors` + GPL 全文声明）**一字未改**；资产版权分段见 `COPYRIGHT_ASSETS` |
| §5(a) | 标注修改**并给相关日期** | `NOTICE` 的 fork 声明块：基线 `v2.3.3-beta.3` / `c7305ec`、首次修改日期 **2026-09-27**（后续见 git 历史）、改名与重打包（壶中天 / Gourd、`com.cmeng.gourd`、`壶中天-<ver>.dmg`）；**自建 `.swift` 文件头**（`Modified for Gourd (2026-09-30)` + Gourd 版权行） |
| §5(b) | 标注以本许可发布、无担保、含 §7 附加条款（若有） | 上游文件头原文保留；`NOTICE` / `TRADEMARKS` 声明本仓库以 GPL-3.0 分发 |
| §5(c) | 整部作品按 GPL 授权 | `LICENSE` = GPL-3.0 全文，仓库根 |
| §6 | 分发二进制须提供对应源码 | `NOTICE` §四.1；发布时同步给出可编译源码归档 |
| §5(d) | 交互界面显示 Appropriate Legal Notices | **豁免**：上游没有，本仓库也不必加 → App 内无许可窗（见 §明确不做 的对应条目，[24](24-release-freeze.md)） |

⚠️ `TRADEMARKS` 里的"无隶属关系、未获背书"**不是 GPL 义务**（GPL-3.0 并未要求被许可人作此声明），
它是商标法与上游 `TRADEMARKS` 的约束——引用依据时别写错。

## 2. 本项目涉及项目的判定

| 项目 | 许可 | 用途 | 使用方式 | 需要做的事 |
|---|---|---|---|---|
| [Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll) | GPL-3.0 | **代码基座** | fork | 保留原版权头；改名的同时保留 LICENSE 与署名；标注"基于 Atoll 修改"（§5(a)：还要给**修改日期**与**改名与重打包**，落点见 `NOTICE` 的 fork 声明块） |
| [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) | GPL-3.0 | 功能对照/局部合并 | vendored 局部代码 | 同上；按文件登记来源 |
| [Lakr233/NotchDrop](https://github.com/Lakr233/NotchDrop) | MIT | 文件暂存 + AirDrop | 局部代码 | 保留 MIT 声明 |
| [MuQY1818/OpenYoink](https://github.com/MuQY1818/OpenYoink) | MIT | 拖拽暂存形态 | 局部代码 | 保留 MIT 声明 |
| [mrkai77/DynamicNotchKit](https://github.com/mrkai77/DynamicNotchKit) | MIT | 刘海窗口/几何（备选实现） | SPM 依赖 | 保留 MIT 声明 |
| [exelban/stats](https://github.com/exelban/stats) | MIT | 系统监控指标实现 | 局部代码 | 保留 MIT 声明 |
| [jacklandrin/OnlySwitch](https://github.com/jacklandrin/OnlySwitch) | MIT | 快捷开关实现 | 局部代码 | 保留 MIT 声明 |
| [p0deje/Maccy](https://github.com/p0deje/Maccy) | MIT | 剪贴板历史 | 局部代码 | 保留 MIT 声明 |
| [MonitorControl/MonitorControl](https://github.com/MonitorControl/MonitorControl) | MIT | 外接显示器亮度/音量 | 局部代码（可选） | 保留 MIT 声明 |
| [swiftbar/SwiftBar](https://github.com/swiftbar/SwiftBar) | MIT | 脚本化状态条（可选能力） | 局部代码（可选） | 保留 MIT 声明 |
| [newmarcel/KeepingYouAwake](https://github.com/newmarcel/KeepingYouAwake) | MIT | 防休眠 | 局部代码 | 保留 MIT 声明 |
| [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | MIT | 全局快捷键 | SPM 依赖 | 保留 MIT 声明 |
| [wxtsky/CodeIsland](https://github.com/wxtsky/CodeIsland) | MIT | AI agent 状态面板（可选） | 局部代码（可选） | 保留 MIT 声明 |
| [farouqaldori/vibe-notch](https://github.com/farouqaldori/vibe-notch) | Apache-2.0 | 通知形态参考 | 局部代码（可选） | 保留 NOTICE 与许可 |
| [ddddxxx/LyricsX](https://github.com/ddddxxx/LyricsX) | MPL-2.0 | 歌词渲染/同步算法 | 局部代码 | **保持这些文件为 MPL-2.0**，改动需公开对应文件 |
| [Yudaotor/lyrimuse](https://github.com/Yudaotor/lyrimuse) | GPL-3.0 | 逐字歌词同步 | 局部代码 | 按 GPL 登记来源 |
| [Ebullioscopic/AtollExtensionKit](https://github.com/Ebullioscopic/AtollExtensionKit) | **LGPL-3.0**（上游当前事实：仓库已含 LICENSE 全文，`gh api repos/.../license` 报 `spdx_id = LGPL-3.0`；由上游 `29656205`（2026-03-19，"Update LICENSE"）加入，读 README 徽章亦已由 MIT 改为 LGPL-3.0）。⚠️ 但我们 pin 的 revision `e2d30afe…`（2026-03-16）早于该 commit，**该 revision 的 tree 内没有 LICENSE 文件**——本节政策行说的"README 声明许可但缺 LICENSE 文件 / 待上游补"**不适用**：上游已补，缺文本的是我们钉住的旧 revision | 上游内容描述符与 XPC 协议定义（内容推送的 wire 契约） | SPM 依赖（pin revision） | ① **抬 pin** 到 ≥ `29656205`（含 LICENSE 的 revision），届时须履行 **LGPL-3.0 §4 的组合工作义务**（用户能用修改后的 LGPL 部分重新链接本组合）② 抬 pin 属**另行决策**（会改依赖 revision，需重跑构建与 pin 一致性校验），不是"求上游补文件" ③ 若抬 pin 引出 API 变化而不愿承担，备选是按 wire 语义自实现类型（[06](06-module-protocol.md) §9 的映射关系即为此准备）④ 首次分发二进制前必须解决 |
| [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) | ⚠️ **BSD-3-Clause**（perl 脚本头声明 `Copyright (c) 2025 Jonas van den Berg`，但**二进制目录内无任何许可文件**） | 系统级媒体元数据与播放控制（经私有 `MediaRemote.framework`） | vendored 二进制：`Frameworks/MediaRemoteAdapter.framework`（三架构）+ `mediaremote-adapter/MediaRemoteAdapter.framework`（**与前者逐字节相同的重复副本**）+ `Contents/Helpers/NowPlayingTestClient`（**仅 arm64**）+ `mediaremote-adapter/mediaremote-adapter.pl` | BSD-3 要求**二进制分发时复现版权声明与许可全文**。必办：① 在 `Frameworks/` 与 `mediaremote-adapter/` 各放一份 LICENSE（含版权行与三条款全文）并登记 `NOTICE` ② ~~删掉重复的那份 framework~~ **不删**（D-07：`FRAMEWORK_SEARCH_PATHS` 指向两处，删副本有破坏链接风险）③ `NowPlayingTestClient` 保留并记为已知限制（仅 arm64，与 framework 的三架构不一致；x86_64 上不可用——本机为 arm64，暂不影响） |
| [lwouis/alt-tab-macos](https://github.com/lwouis/alt-tab-macos) | GPL-3.0 | 窗口切换（非目标，仅参考） | 参考 | 不引入 |
| [RoversX/LaunchNext](https://github.com/RoversX/LaunchNext) | GPL-3.0 | 启动台数据/交互参考 | 参考或局部代码 | 引入则按 GPL 登记 |

## 3. 禁止清单（只可读文档与思路，代码一行不许进）

| 项目 | 原因 |
|---|---|
| [shobhit99/SuperIsland](https://github.com/shobhit99/SuperIsland) | 仓库内无 LICENSE 文件，默认保留所有权利 |
| [sk-ruban/notchi](https://github.com/sk-ruban/notchi) | AGPL-3.0 |
| 其他无 LICENSE / 未标注许可的仓库 | 同上 |

## 4. 每次引入代码的检查清单

1. `NOTICE` 增加一行：来源仓库、URL、许可、被引入的文件或模块、是否修改。
2. 保留原文件的版权头；**修改标注采用仓库级声明**（`NOTICE` 写明「本仓库为 Atoll 的修改版本，改动范围见 git 历史」+ 每个任务的提交信息），不逐文件加行内注释——`project.pbxproj`（`/* */`）与 `Info.plist`（XML 注释）逐一加注释不可行且噪音大（口径见 ADR 决策 D-09）。
3. 不复制没有明确许可的代码片段——包括 issue、PR 评论、论坛贴里的代码。
4. MPL 文件单独存放并保持其文件头与许可声明，不与 GPL 代码混写在同一文件里。
5. 发布二进制时同步提供可编译的源码归档（GPL 的实质义务）。

## 5. 工具建议

- 用 [LicensePlist](https://github.com/mono0926/LicensePlist)（MIT）自动生成 App 内的第三方许可清单，接进 CI。
- 用 `swift package show-dependencies` 导出 SPM 依赖树，作为 SBOM 的初版。
- 每次发布前跑一遍"许可证矩阵 vs 实际依赖"的人工核对（本项目项目数少，暂不引入重型合规工具）。
