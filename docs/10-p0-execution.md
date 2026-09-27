# P0 执行方案（壶中天 / Gourd 基座落地）

> 本文件是工作流 `p0-foundation` 的设计文档，只写 **docs/08 未定的增量**。
> **P0 的 of-record 清单是 [08-p0-checklist.md](08-p0-checklist.md)**（10 张任务卡 P0-1…P0-10、改名表 A1–A12、刻意冻结项 B、上游接触白名单、验收命令 P0-8）——本文不复述它。

## 一句话方案

以"接上游历史 + 一次性改名"的方式把 Atoll 基线 `v2.3.3-beta.3` 引入本仓库，使本机能构建出名为 **壶中天 / Gourd**（Bundle ID `com.cmeng.gourd`）的应用，同时把合规、依赖治理与 CI 配置一次做到位——**不写业务代码、不改动上游功能**。

## 背景与目标

**问题现状**：`~/workspace/github/lagoon` 目前**只有文档与脚本，零提交、无远端、无 CI**；应用工程尚未引入。不改的话，后面每一步（模块化、插件、分发）都没有落脚点。

**承接来源**（本方案继承、不重述）：

| 来源 | 继承什么 |
|---|---|
| [08-p0-checklist.md](08-p0-checklist.md) | P0 的全部任务卡、改名清单 A1–A12（含目标值）、**刻意冻结项 B**（扩展通道线协议名一律不动）、上游接触白名单 P0-7、验收命令 P0-8、两个环境前置 E1/E2 |
| [ADR-0009](00-decisions.md) | 基线锁 `v2.3.3-beta.3`（`c7305ec`）及其理由 |
| [ADR-0008](00-decisions.md) | P0 只改 App 身份、冻结扩展通道名；Sparkle 三项为强制改动 |
| [ADR-0011](00-decisions.md) / [ADR-0012](00-decisions.md) | 范围：上游功能一个不删；不需要的功能用"默认不启用"表达；新增功能不在 P0 |
| [04-upstreams.md](04-upstreams.md) | 同步节奏与"上游默认分支是 `dev`" |
| [03-license-matrix.md](03-license-matrix.md) | 合并规则与 vendored 二进制的许可义务 |

**本次增量**（docs/08 未定的部分，也是本文件存在的理由）：

1. **远端与 CI 的边界**：GitHub 账号为 `cmeng-CM`，仓库 `cmeng-CM/gourd` **尚不存在**。建仓与推送属外部动作，本次只落 **CI 配置文件 + 本地等价验证**，实跑 CI 待你授权后单独进行。
2. **项目目录名不改**（`~/workspace/github/lagoon` → `gourd`）：agent-memory 的项目键与工作区路径绑定，直接 `mv` 会让既有跨会话记忆失联。已记入 [08](08-p0-checklist.md) P0-2 作为后续步骤。
3. **五个无关 workflow 的处置范围**、**图标策略**（docs/08 D-11 / D-12 只给了建议）。
4. **验证命令与"不验证的部分"**：明确写出本次接受的风险。

**预期结果**：`xcodebuild build` 产出 `Gourd.app`；`PRODUCT_NAME=Gourd`、`PRODUCT_BUNDLE_IDENTIFIER=com.cmeng.gourd`；`NOTICE` 合规；CI 配置就位且本地可校验；上游功能零删减。

## 做法

**历史接入（机制）**：把现有文档提交为 L0 并打 tag（供 merge 引用）→ 加 `atoll` remote、fetch tags → 以基线 commit 为起点建 `main` → `merge --allow-unrelated-histories` 把 L0 叠上去。冲突面已预判：`README.md` 取我们的、`NOTICE` 必须**合并**（上游那段的 boring.notch 署名是 Atoll 的 GPL 义务，删掉即违规）、`LICENSE` 已实测与上游字节相同（无冲突）、`.gitignore` 取并集。此后 `git merge atoll/dev` 是原生操作，季度同步不再需要人工比对。

**改名（机制）**：统一改本仓库自身的文档与配置，使"仓库里读到的名字"与"应用身份"一致；应用工程侧按 A1–A12 逐项落到 `project.pbxproj` / `Info.plist` / 脚本 / CI；**B 表冻结项一律不动**。改动集中在**接触白名单**内的文件，其余上游文件只做机械改名（不重构）。

**依赖与合规（机制）**：4 条 `branch: main` 依赖 pin 到已解析 revision（构建可复现）；删 `open-meteo` 死依赖（它既未链接也未 import）；vendored 二进制**只补 BSD-3 许可全文、保留产物**（D-07——`FRAMEWORK_SEARCH_PATHS` 同时指向 `Frameworks/` 与 `mediaremote-adapter/` 两处，删重复副本有破坏链接的风险；此决定取代 docs/08 P0-6② 与 docs/03 §2② 原先「删掉重复副本」的建议）。这几件都是「不做就会在 P5 分发时爆」的事，趁 P0 一次做掉。

**验证（机制）**：以 CI 的构建步骤为权威判据（GitHub runner 是干净环境），本地用同一条 `xcodebuild` 命令验证；两个环境前置（Metal Toolchain 已装、DerivedData 不放 `/tmp`）已在 docs/08 实测记录中，并已由我本机跑通 `BUILD SUCCEEDED`。

## 备选与取舍

| 备选 | 否决理由 |
|---|---|
| **vendor drop**：把 Atoll 源码复制进仓库，不接历史 | 季度同步会失去 merge-base，每次同步退化为手工比对——而实测上游 5 周漂移 155 文件，这是必然要付的成本 |
| 先改名再引入工程 | 改名的大多数落点（`project.pbxproj` / `Info.plist` / 脚本）在应用工程里，得先有文件才能改 |
| 本次一并建 GitHub 远端并跑绿 CI | 建仓/推送是外部动作，未经你授权不应执行；且 CI runner 环境与本地不同，排障成本应单独计 |
| 顺手把 `SettingsView`（9696 行）等热点重构掉 | 违反 ADR-0011「不重写上游实现」；重构会把 P0 的验收面撑大到无法收敛 |

## 明确不做

- **不建 GitHub 仓库、不 push、不 merge 远端**（外部动作，需你授权后单独进行）。
- **不改项目目录名**（agent-memory 项目键与路径绑定，会丢跨会话记忆；已列入 docs/08 作为后续步骤）。
- **不做 UserDefaults 旧域迁移**（docs/08 D-10，推 P1）。
- **不删除上游任何功能文件**（ADR-0011）；**不改扩展通道线协议名**（ADR-0008 冻结项 B）。
- **不写业务代码、不改模块架构**（P1 的事）；**不签名/不公证/不发版**（P5 的事）。
- **不做 docs/08 P0-7 的 5 个 Runtime 骨架文件**（`ModuleManifest.swift` / `ConfigSchema.swift` / `ModuleContent.swift` / `GourdEvent.swift` / `ManifestValidator.swift`）：那属 P1 的第一批交付，P0 只做基座落地。

## 决策摘要

> 与计划的决策表一一对应（计划里是执行视角，这里是合并视图）。

| ID | 决策 | 来源 |
|---|---|---|
| D-01 | 远端与 CI 边界：本次只落 CI 配置与本地等价校验；不建 GitHub 仓库、不 push、不 merge 远端 | 用户 |
| D-02 | 项目目录名本次不改（agent-memory 键与路径绑定） | 用户 |
| D-03 | 删除 5 个无关/有副作用的 workflow，保留 `release.yml` | 用户 |
| D-04 | 本次不动应用图标，与主题一并在 P3 做 | 用户 |
| D-05 | 验证以 CI 构建步骤为权威、本地同命令复现；GUI 行为人工验收 | agent |
| D-06 | `NOTICE` 必须合并：保留上游 boring.notch 署名段 + 加壶中天 fork 声明（含基线 `c7305ec`）+ 我们的登记表 | agent |
| D-07 | vendored 二进制**只补许可、不删产物**（`FRAMEWORK_SEARCH_PATHS` 同时指向两处，删副本有破坏链接风险）；重复副本与 arm64-only 的 `NowPlayingTestClient` 保留并记为已知限制 | agent（**范围边界，计划门需用户确认**） |
| D-08 | `ci.yml` 重写为构建+测试+格式三件套（含 mach-services 剥离、Metal Toolchain 下载、排除 UI 测试），`release.yml` 不动 | agent |
| D-09 | 修改标注以 `NOTICE` 总声明 + 提交信息满足，不逐文件加行内注释 | agent（合规口径，计划门确认） |
| D-10 | 给 app target 加 `PRODUCT_MODULE_NAME = Atoll`，保持 Swift 模块名不变 | agent（技术取舍） |
| D-11 | Sparkle 处置必须动**运行期**（`AtollUpdaterDelegate` + `UpdateChannel` 的上游 appcast 由 T9 清理）；连同测试 target bundle id、`strings/constants.swift`、`NS*UsageDescription` 一并收尾 | agent（执行 ADR-0008 已批准的要求，落点由 T2 审查发现） |
| D-12 | 接受计划 9 个任务超出 8 个上限（一次性基座落地，拆分会让历史接入窗口重复或有依赖断裂） | agent（规模取舍，计划门呈现） |

## 接口与数据形状

**改名目标值**（A 表目标侧的汇总，逐项落点见 docs/08）：

| 项 | 目标值 |
|---|---|
| `PRODUCT_NAME` | `Gourd`（二进制名与路径用 ASCII，避免中文路径问题） |
| `CFBundleDisplayName` | `壶中天` |
| Release Bundle ID | `com.cmeng.gourd` |
| Debug Bundle ID | `com.cmeng.gourd.dev` |
| 日志 subsystem | 统一 `com.cmeng.gourd` |
| Sparkle | feed 与公钥置空、`SUEnable*Service=false`（**安全项，必须改**） |

**产物路径**：`~/Library/Developer/Xcode/Gourd/Build/Products/Debug/Gourd.app`（本地构建）；
**依赖 pin**：4 条 branch 依赖 → `revision`（值取当前 `Package.resolved`）；
**接触白名单**：**以 docs/08 P0-7 为唯一权威**（已扩容：`project.pbxproj`（含 TEST_HOST/BUNDLE_LOADER、`PRODUCT_MODULE_NAME`）、`Info.plist`、entitlements、`Constants.swift`、三个 ruby 脚本、`ci.yml`、A12 的全部 subsystem 落点、A9 的 `DynamicIslandApp.swift`、scheme、`Package.resolved`）。

## 验收标准

以 docs/08 P0-8 的命令序列为准，外加：CI 配置文件存在且结构可解析、`git merge-base main c7305ec` 成立、`grep -c 'kind = branch' project.pbxproj` 为 0、`NOTICE` 同时含 boring.notch 署名与基线 commit。

## 已知限制

- **CI 实跑未验证**（无远端）：本次只保证配置文件正确，绿灯需授权后确认。
- **"刘海面板折叠/展开"属 GUI 人工验收**，自动化只能到"构建成功 + 产物存在"。
- 基线是上游 prerelease 版（`-beta.3`），品质需自测兜底（ADR-0009 已接受）。
- `project.pbxproj` 必然被改，是未来季度同步的主要冲突面（接触白名单已将其记录在案）。
- **Swift 模块名保持 `Atoll`**（D-10）：`PRODUCT_NAME` 改成 `Gourd` 后模块名会跟着变，而 4 个单测文件写的是 `@testable import Atoll`。选择加 `PRODUCT_MODULE_NAME = Atoll` 而不是改那 4 个上游测试文件——前者零扩散、后者要再扩白名单。代价是「模块名 ≠ 产品名」，属已知的刻意取舍。
- ⚠️ **`release.yml` 的触发条件是 `push` 到 `main`（不是 tag）**：一旦你授权推送，首推 `main` 就会执行上游那套签名 / 公证 / DMG 发布（含上游 `APP_NAME: Atoll` 与上游 TEAM_ID）。**推送前必须先把它改成手动触发（`workflow_dispatch`）或删掉**——已列为 T6 的待办记录，但本次不实跑，不会被自动发现。

## 实际交付

无（尚未实现——回写时补齐）
