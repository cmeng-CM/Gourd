# 许可证矩阵与合并规则

本项目以 **GPL-3.0** 分发（见 ADR-0001）。下表决定"哪些代码能进这个仓库、以什么方式进"。

## 1. 规则

| 上游许可 | 能否并入本工程 | 方式与义务 |
|---|---|---|
| **MIT / BSD / ISC** | ✅ 可以 | 保留原版权声明与许可文本（进 `NOTICE` 或随文件保留 `LICENSE`） |
| **Apache-2.0** | ✅ 可以 | 保留版权与许可、保留上游 `NOTICE`（若有）、注意专利授权条款；修改文件需标注 |
| **MPL-2.0** | ✅ 可以 | **文件级 copyleft**：MPL 文件必须保持 MPL 并保留声明；修改过的 MPL 文件其源码需公开（其余文件可用 GPL） |
| **GPL-2.0 / GPL-3.0** | ✅ 可以 | 整体按 GPL-3.0 分发；提供完整源码；保留版权与许可；标注修改 |
| **AGPL-3.0** | ❌ 不并入 | 除非整个项目接受 AGPL。仅可阅读思路 |
| **无 LICENSE 文件** | ❌ 不并入 | 默认保留所有权利。仅可阅读思路与文档 |
| **README 声明许可但缺 LICENSE 文件** | ⚠️ 有条件使用 | 声明本身是该作者的授权意图，但缺许可文本属不合规状态。**可先用**，但必须在首次分发二进制前解决：向上游提 issue/PR 补齐文件，或换实现。登记时须标注"待上游补文件" |
| **专有 / 未知** | ❌ 不并入 | 同上 |

## 2. 本项目涉及项目的判定

| 项目 | 许可 | 用途 | 使用方式 | 需要做的事 |
|---|---|---|---|---|
| [Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll) | GPL-3.0 | **代码基座** | fork | 保留原版权头；改名的同时保留 LICENSE 与署名；标注"基于 Atoll 修改" |
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
| [Ebullioscopic/AtollExtensionKit](https://github.com/Ebullioscopic/AtollExtensionKit) | ⚠️ **README 声明 MIT，但仓库缺 LICENSE 文件**（实测 2026-09-27：checkout 内无 LICENSE/LICENSE.md/LICENSE.txt/COPYING） | 上游内容描述符与 XPC 协议定义（内容推送的 wire 契约） | SPM 依赖（pin revision） | ① `NOTICE` 登记时标注"待上游补 LICENSE" ② **首次分发二进制前必须解决**：向上游提 issue/PR 补文件 ③ 若上游不补，则改为按 wire 语义自实现类型（[06](06-module-protocol.md) §9 的映射关系即为此准备） |
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
