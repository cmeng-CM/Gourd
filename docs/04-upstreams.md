# 上游仓库清单与同步策略

所有上游仓库已拉取到 `/Users/cm/workspace/github/`（与本项目同级）。机器可读清单见 [`../upstreams.tsv`](../upstreams.tsv)。

## 1. 已拉取的仓库

| 目录 | 仓库 | 模式 | 用途 | 许可 | 使用方式 |
|---|---|---|---|---|---|
| `Atoll` | Ebullioscopic/Atoll | full | **代码基座**（基线 `v2.3.3-beta.3` / `c7305ec`） | GPL-3.0 | fork |
| `boring.notch` | TheBoredTeam/boring.notch | full | 功能对照实现（媒体、HUD、手势、日历） | GPL-3.0 | 局部合并 |
| `NotchDrop` | Lakr233/NotchDrop | shallow | 文件暂存 + AirDrop | MIT | 局部代码 |
| `OpenYoink` | MuQY1818/OpenYoink | shallow | 拖拽暂存与岛形态 | MIT | 局部代码 |
| `DynamicNotchKit` | mrkai77/DynamicNotchKit | shallow | 刘海窗口/几何实现（备选） | MIT | SPM 依赖 |
| `stats` | exelban/stats | shallow | CPU/内存/网络/磁盘指标 | MIT | 局部代码 |
| `OnlySwitch` | jacklandrin/OnlySwitch | shallow | 快捷开关 | MIT | 局部代码 |
| `Maccy` | p0deje/Maccy | shallow | 剪贴板历史 | MIT | 局部代码 |
| `LyricsX` | ddddxxx/LyricsX | shallow | 歌词渲染与同步 | MPL-2.0 | 局部代码（保持 MPL） |
| `lyrimuse` | Yudaotor/lyrimuse | shallow | 逐字歌词、国内音乐源 | GPL-3.0 | 局部代码 |
| `KeyboardShortcuts` | sindresorhus/KeyboardShortcuts | shallow | 全局快捷键库 | MIT | SPM 依赖 |
| `alt-tab-macos` | lwouis/alt-tab-macos | shallow | 窗口切换参考（非目标） | GPL-3.0 | 仅参考 |
| `LaunchNext` | RoversX/LaunchNext | shallow | 启动台数据与交互参考 | GPL-3.0 | 参考 |
| `KeepingYouAwake` | newmarcel/KeepingYouAwake | shallow | 防休眠 | MIT | 局部代码 |
| `MonitorControl` | MonitorControl/MonitorControl | shallow | 外接显示器亮度/音量 | MIT | 局部代码（可选） |
| `SwiftBar` | swiftbar/SwiftBar | shallow | 脚本化状态条能力（可选） | MIT | 局部代码（可选） |
| `CodeIsland` | wxtsky/CodeIsland | shallow | AI agent 状态面板（可选） | MIT | 局部代码（可选） |

**刻意不拉取**（无许可或 AGPL，仅按需在线阅读）：`shobhit99/SuperIsland`（无 LICENSE）、`sk-ruban/notchi`（AGPL-3.0）。

## 2. 同步策略

**基座（Atoll）——跟随上游，但要有节奏**

> Atoll 的默认分支是 **`dev`（不是 `main`）**，同步时合并 `upstream/dev`。
> 本项目基线锁定为 `v2.3.3-beta.3`（`c7305ec`，2026-08-20），选型依据见 [00-decisions.md](00-decisions.md) ADR-0009。

```bash
cd ~/workspace/github/gourd         # 应用工程目录（2026-09-27 由 lagoon 改名）
git remote add atoll https://github.com/Ebullioscopic/Atoll.git   # 远程名用 atoll，避免与 fork 关系混淆
git fetch atoll --tags
# 在一个独立分支上试合并，验证通过再进主干
git switch -c sync/atoll-$(date +%Y%m%d)
git merge atoll/dev
```

- 节奏：**每季度一次**，只跟随已发布的 tag，不追 dev 的每个提交。
- 每次同步前先跑一遍自测清单（多屏、合盖、展开动画、现有模块）。
- 上游改动集中在扩展宿主时（那是我们改动最多的区域），优先手工挑选提交而不是整树合并。
- **同步成本取决于接触面积**：我们对上游文件的修改只允许落在 [08-p0-checklist.md](08-p0-checklist.md) P0-7 的白名单内，其余改动一律进新目录（`DynamicIsland/Kernel|Runtime|Modules`）。

**同步后检查单（合并成功、验证通过之后，逐条改完再提交）**

1. **上游版本号**：把 `NOTICE` fork 声明块的 `基线: tag …` 换成本次跟到的上游 tag（上游 tag 形态见
   `git -C ~/workspace/github/Atoll tag`）；`NOTICE` §一 的"Atoll"登记行的 tag 一并改（同一事实两处出现）。
2. **基线 commit**：把 `NOTICE` fork 声明块 `基线:` 行里的 commit 短 hash 换成新基线的短 hash
   （`git -C ~/workspace/github/Atoll rev-parse --short <tag>`）；本文件 §1 表格里 `Atoll` 行的
   `（基线 \`v2.3.3-beta.3\` / \`c7305ec\`）` 同批改。⚠️ 基线一变，[03-license-matrix.md](03-license-matrix.md)
   §1 的「本仓库的 GPL 义务落点」表与 §2 的 Atoll 行也要跟着核一遍。
3. **修改日期**：`NOTICE` 的 `首次修改日期:` **保持首次值不动**（§5(a) 要的"相关日期"以它为准，
   见 [03-license-matrix.md](03-license-matrix.md) §1 的 GPL 行）；本次同步若带进了新的改动，
   在同一行追加最近一次修改日期（形如 `首次修改日期: 2026-09-27；最近同步: <YYYY-MM-DD>`）。
   这三个字段都是**手工维护**的，没有自动校验（见 [24](24-release-freeze.md) §已知限制 5）。

**参考仓库——按需刷新，不必保留历史**

```bash
git -C ~/workspace/github/NotchDrop fetch --depth 1 origin
git -C ~/workspace/github/NotchDrop reset --hard FETCH_HEAD
```

- 引进某段实现前，先记录当时的 commit hash 到 `NOTICE`，以便日后追溯与对比。

**依赖（SPM）**：本仓库根目录**没有 `Package.swift`**——应用工程的依赖声明落在 `DynamicIsland.xcodeproj/project.pbxproj` 的 `XCRemoteSwiftPackageReference`，解析结果落在 `DynamicIsland.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`（两者都已 committed）。规则：**不用分支依赖**，用 `kind = revision` + `revision = <sha>` 钉住已解析版本（P0 已把 4 条 `branch = main` 全部改为 revision）；改完必须提交 `Package.resolved`，并跑 `bash tools/verify-upstreams.sh` 校验「登记的 dependency 行 ↔ pin 的 revision」一致。注意传递依赖钉不住：`lottie-spm` 由 LottieUI 的 manifest 以 `branch: main` 声明，只能靠 committed `Package.resolved` 锁定（见 [10-p0-execution.md](10-p0-execution.md) 的已知限制）。

## 3. 与上游的关系原则

1. **不追求与上游功能对等**——我们是"刘海命令面板"，不是"第二个 Atoll"。上游有的功能如果我们不需要，就不合并。
2. **能给上游提 PR 的就提**：修通用 bug 优先贡献回上游，减少自己的维护面。
3. **扩展系统的差异要显式化**：Atoll 的扩展描述符如果与本项目设计冲突，优先保持"能读懂上游扩展"的兼容读取，再谈扩展字段。
4. 上游若某天停止维护：本项目的模块边界已经把它锁在 L0/L1 之内，可以按模块逐个替换实现（这是选择"能当依赖就不 fork"的直接收益）。
