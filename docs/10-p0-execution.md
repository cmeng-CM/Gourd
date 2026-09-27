# P0 执行方案（壶中天 / Gourd 基座落地）

> 本文件是工作流 `p0-foundation` 的设计文档，只写 **docs/08 未定的增量**。
> **P0 的 of-record 清单是 [08-p0-checklist.md](08-p0-checklist.md)**（10 张任务卡 P0-1…P0-10、改名表 A1–A12、刻意冻结项 B、上游接触白名单、验收命令 P0-8）——本文不复述它。

## 一句话方案

以"接上游历史 + 一次性改名"的方式把 Atoll 基线 `v2.3.3-beta.3` 引入本仓库，使本机能构建出名为 **壶中天 / Gourd**（Bundle ID `com.cmeng.gourd`）的应用，同时把合规、依赖治理与 CI 配置一次做到位——**不写业务代码、不改动上游功能**。

## 背景与目标

**问题现状**：`~/workspace/github/lagoon`（已于 2026-09-27 改名 `~/workspace/github/gourd`）当时**只有文档与脚本，零提交、无远端、无 CI**；应用工程尚未引入。不改的话，后面每一步（模块化、插件、分发）都没有落脚点。

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

1. **远端与 CI 的边界**：GitHub 账号为 `cmeng-CM`，仓库 `cmeng-CM/gourd` **尚不存在**。建仓与推送属外部动作，本次只落 **CI 配置文件 + 本地等价验证**，实跑 CI 待你授权后单独进行。（追记 2026-09-27：远端已建为 `cmeng-CM/Gourd` 并首推 `main`，CI 首跑随推送触发）
2. **项目目录名不改**（`~/workspace/github/lagoon` → `gourd`）：agent-memory 的项目键与工作区路径绑定，直接 `mv` 会让既有跨会话记忆失联。已记入 [08](08-p0-checklist.md) P0-2 作为后续步骤。（追记 2026-09-27：该决策已反转——目录已改名 `gourd`，agent-memory 项目目录同步迁移，见「已知限制」末条）
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

> 终审核对（2026-09-27）：D-01…D-11 均有行、来源标注与计划决策表一致（另含计划里以「规模取舍」段呈现的 D-12）。一处落实口径需注意：**D-11 的「`NS*UsageDescription` 一并收尾」只覆盖了 `Info.plist` 文件内那三条**，`project.pbxproj` 里同名同义的 10 条 `INFOPLIST_KEY_NS*UsageDescription`（会进产物的系统权限弹窗文案）仍写 "Atoll ..."，未被任何任务覆盖——已记入「已知限制」与「遗留项」，建议并入 P3 文案收尾。

## 接口与数据形状

**改名目标值（终态，来源：`xcodebuild -showBuildSettings` + 产物 `Info.plist` 实测）**：

| 项 | 终态值 | 落点 |
|---|---|---|
| `PRODUCT_NAME` | `Gourd`（二进制名与路径用 ASCII，避免中文路径问题） | `project.pbxproj`（app target Debug/Release） |
| `PRODUCT_MODULE_NAME` | `Atoll`（**刻意不等于产品名**，D-10） | 同上；4 个上游单测文件写的是 `@testable import Atoll` |
| `INFOPLIST_KEY_CFBundleDisplayName` | `"壶中天"`（带引号的 UTF-8 字面量；裸字面量会让整个工程解析失败） | 同上 |
| Release Bundle ID | `com.cmeng.gourd` | 同上 |
| Debug Bundle ID | `com.cmeng.gourd.dev` | 同上 |
| 单测 / UI 测试 target Bundle ID | `com.cmeng.gourd.tests` / `com.cmeng.gourd.uitests`（各 2 处） | 同上（T9） |
| 日志 subsystem | 统一 `com.cmeng.gourd`（8 个落点、4 种上游写法；含 `com.atoll.dynamicisland` 变体） | 见 docs/08 A12 的 11 个文件 |
| 运行期更新源 | **无**：`feedURLString(for:)` 返回 `nil`、`startingUpdater: false`、`SUFeedURL`/`SUPublicEDKey` 置空、`SUEnable*Service=false` | `AtollUpdaterDelegate.swift` / `DynamicIslandApp.swift:43` / `Info.plist` |
| 测试 host | `$(BUILT_PRODUCTS_DIR)/Gourd.app/Contents/MacOS/Gourd`（同型**字面量**，未改用 `$(PRODUCT_NAME)` 变量） | `project.pbxproj` 单测 target 两处配置 + `fix_test_host.rb` / `add_unit_test_target.rb` |
| 产品页 URL | `https://github.com/cmeng-CM/gourd` | `strings/constants.swift:21` |

**产物路径**：`~/Library/Developer/Xcode/Gourd/Build/Products/Debug/Gourd.app`（116 MB = `MacOS/Gourd` 40 KB 启动壳 + `Gourd.debug.dylib` 105 MB）。`Info.plist` 文件内三条 `NS*UsageDescription` 已改为 `壶中天`。

**依赖形态（pin 后）**：`project.pbxproj` 中 4 条 `XCRemoteSwiftPackageReference` 由 `{branch = main}` 改为 `{kind = revision; revision = <已解析值>}`（AtollExtensionKit `e2d30af` / LaunchAtLogin-Modern `a04ec1c` / SkyLightWindow `4a7e862` / LottieUI `0cd5b54`，**未升级任何版本**）；`open-meteo` 的定义块、`packageReferences` 条目与 pin 全部删除（对象 ID 零残留）；`Package.resolved` 共 15 条 pin。唯一残留的 `"branch": "main"` 是**传递依赖** `lottie-spm`——LottieUI 的 `Package.swift` 以 `branch: "main"` 声明它，pbxproj 与 Package.resolved 层面都钉不住（见「已知限制」）。

**接触白名单的最终范围**（口径：`git diff --name-status c7305ec HEAD`，A/M/D 分类）：

- **`M` 21 项** = P0-7 白名单 19 项（`ci.yml`、`project.pbxproj`、`Package.resolved`、scheme、`DynamicIslandApp.swift`、`Info.plist`、`audio/AudioTap.swift`、`SpotifyLoginSheet.swift`、`AntigravityUsageProvider.swift`、`CodexQuotaClient.swift`、`ReminderLiveActivityManager.swift`、`SystemTimerBridge.swift`、`TimerManager.swift`、`UpdateChannel.swift`、`AtollUpdaterDelegate.swift`、`strings/constants.swift`、`utils/Logger.swift`、`add_unit_test_target.rb`、`fix_test_host.rb`）+ T1 冲突处置文件 2 项（`.gitignore`、`NOTICE`）
- **`D` 6 项** = 5 个无关 workflow + `ReadMe.md`（大小写改名，非删除功能）
- **`A` 17 项**（新增文件一律豁免）= `README.md`、`docs/00`–`docs/10`、`Frameworks/LICENSE`、`mediaremote-adapter/LICENSE`、`tools/*.sh` ×2、`upstreams.tsv`
- **白名单内但本次没用到**（不需要改）：`DynamicIsland.entitlements`、`models/Constants.swift`、`fix_module_name.rb`——A12 曾把 `models/Constants.swift` 记为 subsystem 落点，实测该文件无上游串，T7 已在 docs/08 更正
- **B 表冻结项一字未动**：mach service `com.ebullioscopic.Atoll.xpc`（entitlements + `ExtensionXPCServiceHost.swift:25`）、3 个 `com.ebullioscopic.Atoll.extensions.*` 通知名、RPC 端口 9020、`AtollExtensions` 目录、Keychain service（`com.Ebullioscopic.Atoll.Cider` / `.SpotifyLibrary` / `.new-api`）、12 个 `extension*`/`enable*` Defaults 键

## 验收标准

以 docs/08 P0-8 的命令序列为准，外加：CI 配置文件存在且结构可解析、`git merge-base main c7305ec` 成立、`grep -c 'kind = branch' project.pbxproj` 为 0、`NOTICE` 同时含 boring.notch 署名与基线 commit。

## 已知限制

- **「可复现构建」实际达成 14/15**：`lottie-spm` 是 `lottieui` 的**传递依赖**（LottieUI 的 `Package.swift:19` 以 `branch: "main"` 声明），`project.pbxproj` 与 `Package.resolved` 层面都钉不住，只能 fork LottieUI 才能治。当前靠**已提交的 `Package.resolved`** 锁 `04f2fd1`（实测：删掉 SPM 解析状态后重新解析，复现同一 revision 且文件字节不变；本机 SPM 缓存里该仓库 `main` 头部已前进到 `0aff162`，解析仍锁 `04f2fd1`）。上游 `main` 前进时，下一次全新解析会改写该文件，需人工 review 该 diff。
- **CI 从未实跑**（本仓库无 origin remote，D-01）：`ci.yml` 只做了本地结构校验与「同命令同环境」等价复现。**最大未知量是 headless runner 上 `TEST_HOST=Gourd.app` 能否启动**——测试宿主是 `LSUIElement` 的刘海面板，需要 WindowServer；首次实跑最可能红在这里（`test` job 已按此写注释并 `-skip-testing:DynamicIslandUITests`，但宿主仍需启动）。
- ⚠️ **`release.yml` 未改，且触发面比早先记的更宽**：实测 `on: push: branches: [nightly, alpha, beta, main]`（另已有 `workflow_dispatch`）。**授权推送后首推 `main` 就会执行上游那套签名 / 公证 / DMG 发布（含上游 `APP_NAME: Atoll` 与上游 TEAM ID）**。推送前必须先删掉 `push` 段（保留手动触发）或删除该文件——本次刻意不动（D-08/D-03），也不会被自动发现。
- **`tools/verify-upstreams.sh` 不比对非 dependency 行的 `clone_commit`**：基座行（Atoll）的登记漂移永不告警（实测本机 clone 停在 `ad6834e` 仍输出 OK）；dependency 行的 pin 一致性是本次新加的检查，非 dependency 行尚未覆盖。
- **用户可见的上游字样残留**（不影响功能，属 docs/08 §C「文案相关」类）：`components/Settings/SettingsView.swift:3756` 的 "Made with ❤️ by Ebullioscopic" 及其 8 条本地化、`strings/constants.swift:22` 的 `sponsorPage`（buymeacoffee/kryoscopic）、`.github/FUNDING.yml`（`github: Ebullioscopic`）、两处 onboarding 的 `ebullioscopic.github.io` 隐私政策链接。
- **`project.pbxproj` 的 10 条 `INFOPLIST_KEY_NS*UsageDescription` 仍写 "Atoll ..."**（`NSAppleEvents` / `NSBluetoothAlways` / `NSDesktopFolder` / `NSDocumentsFolder` / `NSDownloadsFolder` / `NSLocation` / `NSLocationWhenInUse` / `NSMicrophone` / `NSReminders` / `NSRemindersFullAccess`）：这些设置会进产物 `Info.plist`（**系统权限弹窗的用户可见文案**），实测产物里 10 条全为上游句式。D-11 与 T9 只点名并改了 `Info.plist` **文件内**那三条（`NSAppleMusic` / `NSAudioCapture` / `NSScreenCapture`），pbxproj 侧的同型落点未被任何任务覆盖——由终审发现，未修（本次终审禁改工程文件），建议并入 P3 文案收尾。
- **`managers/LLMUsage/ModelPricingManager.swift:59` 在 `init()` 里抓上游 feature 分支的 raw URL 取未受信 JSON**（`https://raw.githubusercontent.com/Ebullioscopic/Atoll/feat/dynamic-pricing-workflow/.../pricing.json`）。**非启动路径**：触发链是 `NotchLLMUsageView`（`.onAppear` → `manager.refreshAll()`）→ `LLMUsageManager` → provider → `JSONLUsageParser:113` → `ModelPricing.cost` → `ModelPricingManager.shared`，即**展开 LLM 用量视图才触发**。未修（该文件不在白名单），建议后续任务改为随包 `pricing.json` + 删远程 URL。
- **`LICENSE` 未进 app bundle**：`project.pbxproj` 里没有任何指向 `LICENSE` 或两份 vendored `LICENSE` 的引用，且它们不在 `fileSystemSynchronizedGroups`（仅 `Contents` / `DynamicIsland`）内。P5 分发前必须让许可文本搭上分发物（GPL 与 BSD-3 的二进制分发义务）。
- **arm64-only 的 `Contents/Helpers/NowPlayingTestClient` 保留**（D-07）：与 framework 的三架构（x86_64 + arm64 + arm64e）不一致，x86_64 上不可用。
- **`scripts/add_ui_test_target.rb:26` 仍写 `com.atoll.DynamicIslandUITests`**：开发期辅助脚本（不在构建路径、不在白名单），重跑它会把上游 bundle id 注入工程；与 T9 已改的 `add_unit_test_target.rb` 口径不一致。
- **GUI 行为未验**（D-05）：刘海面板折叠/展开、菜单栏退出、权限弹窗文案属人工验收；自动化只能到「构建成功 + 产物身份正确」。
- 基线是上游 prerelease 版（`-beta.3`），品质需自测兜底（ADR-0009 已接受）。
- `project.pbxproj` 必然被改，是未来季度同步的主要冲突面（接触白名单已将其记录在案）。
- **Swift 模块名保持 `Atoll`**（D-10）：「模块名 ≠ 产品名」是刻意取舍。若 P1 把模块名改回 `Gourd`，必须同步改 4 个测试文件的 `@testable import Atoll`。
- `PBXFileReference … path = Atoll.app` 三处（`:89` / `:259` / `:337`）仍在：按派发明令不手改（Xcode 会按 `PRODUCT_NAME` 重生成），`FULL_PRODUCT_NAME` / `WRAPPER_NAME` 实测均为 `Gourd.app`，构建不受影响。
- **签名配置已去上游化（2026-09-27）**：Debug/Release 曾写死上游 Team（`9Y64TRM77N`），Release 且要求 `Developer ID Application`（Manual）——已统一为 ad-hoc（`CODE_SIGN_STYLE = Manual`、team 置空）；entitlements 的 `mach-services`（上游 kit XPC 名 `com.ebullioscopic.Atoll.xpc`，ad-hoc 产物会被 amfid 杀）已从仓库移除，CI 的 plutil 剥离步骤自此恒为幂等跳过。**本地打包**：`sh tools/build.sh`（`--install` 装 /Applications，`--dmg` 出拖拽安装式 DMG 到 `dist/`）；Release 首打实测 `BUILD SUCCEEDED`（产物 `com.cmeng.gourd` / 2.3.3），本机 `xcodebuild test` 亦无需签名覆盖。
  > **稳定签名身份升级（同日稍后）**：ad-hoc 没有稳定身份——系统按每次构建产物的哈希认应用，**每次重新构建 TCC 授权全部作废、重新弹窗**（用户实测反馈）。已改用自签 10 年期证书 **`Gourd Local`**（`tools/setup-signing.sh` 一次性生成 + 用户域信任；身份写在 pbxproj 的 `CODE_SIGN_IDENTITY`，只作用于 app target，SPM 依赖包不受影响），TCC 按「证书 + Bundle ID」记忆：**装一次、逐个授权后，后续所有构建/升级不再弹授权**。CI 侧不变（仍覆盖 `CODE_SIGN_IDENTITY="-"`，runner 不装该证书）。打包全流程本机完成，不依赖 GitHub。
- 项目目录名（D-02）：~~仍为 `~/workspace/github/lagoon`，改名连同记忆迁移留给后续~~ **已完成（2026-09-27）**：目录改名 `~/workspace/github/gourd`，agent-memory 项目目录迁移为 `gourd-1c47bd2beca69533`（键 = `sha256(绝对路径)` 前 16 位，旧目录 `lagoon-4a28976c8efbc2b5` 保留备份）。

## 实际交付

> **提交范围**：`6db7382`(L0) → **`9611eac`**(HEAD)，共 10 个提交（T1–T9 九个任务 + 1 个执行中计划变更提交），**未 push、未建远端**。终审复核（2026-09-27）以 `git diff --name-status c7305ec HEAD` 逐项重算：`A=17 / M=21 / D=6`，**越界 0**；并独立复跑验证命令（退出码 0，工作区保持干净）。

### 交付物

| # | 交付物 | 落点 / 证据 |
|---|---|---|
| 1 | **上游历史接入** | merge 提交 `afe4451`（parents = `c7305ec` `6db7382`）；`git merge-base main c7305ec` = `c7305ec`；上游 1336 个提交可达、无文件丢失；`l0` tag 保留（T5 依赖 `git show l0:NOTICE`）。季度同步此后是原生 `git merge atoll/dev` |
| 2 | **改名：应用身份** | `PRODUCT_NAME=Gourd`、`INFOPLIST_KEY_CFBundleDisplayName="壶中天"`、Release/Debug bundle id `com.cmeng.gourd` / `.dev`、scheme 三处 `BuildableName=Gourd.app`、测试 target 4 处 bundle id、`add_unit_test_target.rb`/`fix_test_host.rb` 的 `Atoll.app`→`Gourd.app`。产物实测：`CFBundleDisplayName=壶中天` / `CFBundleIdentifier=com.cmeng.gourd.dev` / `CFBundleExecutable=Gourd` |
| 3 | **改名：日志子系统** | 11 个文件的 8 处 subsystem（4 种上游写法，含 `com.atoll.dynamicisland`）→ `com.cmeng.gourd`；`DynamicIslandApp.swift:1194/1208/1223/1229` 的导出日志筛选与 `Gourd_Logs.zip` 同步改（否则「导出日志」会静默失效）。`grep -rn --include='*.swift' subsystem DynamicIsland/ \| grep -icE 'ebullioscopic\|com\.atoll'` = **0** |
| 4 | **运行期更新源关闭（安全项）** | 三层同时断开：`AtollUpdaterDelegate.feedURLString(for:)` → `nil`（并按类型层面保证）、`DynamicIslandApp.swift:43` `startingUpdater: false`、`Info.plist` `SUFeedURL`/`SUPublicEDKey` 置空 + `SUEnable*Service=false`。产物 `SUFeedURL=""` / `SUPublicEDKey=""`；`UpdateChannel.feedURL` 的基底换成 `cmeng-CM/gourd` 占位且**无运行期读取方** |
| 5 | **依赖治理** | 4 条 `branch = main` → `kind = revision`（AtollExtensionKit `e2d30af` / LaunchAtLogin-Modern `a04ec1c` / SkyLightWindow `4a7e862` / LottieUI `0cd5b54`，零版本升级）；删 `open-meteo` 死依赖（定义块 + `packageReferences` + pin，对象 ID 零残留）。`grep -c 'kind = branch' project.pbxproj` = **0**；`Package.resolved` 15 条 pin |
| 6 | **合规** | `NOTICE` 合并（**116 行插入 / 0 删除**：上游 boring.notch 署名段逐字保留 + 壶中天 fork 声明含基线 `c7305ec` + 取回我们的登记表 + 新增 §五）；`Frameworks/LICENSE`、`mediaremote-adapter/LICENSE`（BSD-3-Clause 全文，取自上游 `master`，与上游 `LICENSE` 逐字比对 sha256 一致）；vendored 产物一个未删（D-07）；`upstreams.tsv` 新增 `AtollExtensionKit` 依赖行 |
| 7 | **CI 与 workflow 清理** | `ci.yml` 重写为 **build / test / format 三 job**（matrix `macos-15`/`macos-26`；MetalToolchain 重试下载；**转义点号**的 mach-services 剥离；`-only-testing:DynamicIslandTests` + `-skip-testing:DynamicIslandUITests`；`SUFeedURL` 禁止指向上游的断言；`swift-format` advisory）。删除 5 个无关/有副作用 workflow（`update-pricing` / `nightly-merge` / `mirror-release` / `triage-slash-commands` / `validate-changelog`）。**`release.yml` 未改** |
| 8 | **上游登记与工具** | `upstreams.tsv`：Atoll 行基线 → `c7305ec (v2.3.3-beta.3)`，新增 `AtollExtensionKit` 行（许可按事实登记 **LGPL-3.0**）；两个自有脚本 `git mv` 到 `tools/`（与上游 9 个 ruby 脚本隔离），`verify-upstreams.sh` 新增「dependency 行豁免本地目录 + `Package.resolved` pin 一致性」检查（`bash tools/verify-upstreams.sh` exit 0，负向测试 4 条通过） |
| 9 | **构建产物与实测** | `~/Library/Developer/Xcode/Gourd/Build/Products/Debug/Gourd.app`，116 MB；全线 `BUILD SUCCEEDED`（T7 全量重建：退出码 0、0 error / 249 warning；终审复跑同命令退出码 0 且构建后 `git status --porcelain` 为空）。冻结项实测仍在原位 |
| 10 | **文档回写** | `docs/08`：新增实测记录节 + A 表 10 行的行号按基线 `c7305ec` 逐行校正 + 接触面断言换 `--name-status` 口径 + 上游脚本迁移记录；`docs/10`：本文件 |

### 与计划的偏离（逐条给原因）

| # | 偏离 | 原因 |
|---|---|---|
| 1 | `.gitignore` 末尾加 2 行例外 `!scripts/*.sh` / `!tools/*.sh`（T1） | 上游 `.gitignore` 含 `*.sh`，而本仓库把 `.sh` 当正式产物；不加例外则新增脚本被静默忽略（`git status` 不报、无法 `add`）。已 probe 验证：只有这两个目录被豁免 |
| 2 | `NOTICE` 对取回的登记表改了 3 行（`c7305ec` 收敛为 fork 声明一处、§一「修改」行的旧口径改写） | 验收硬断言 `grep -c c7305ec NOTICE == 1` 与「登记表逐字保留」在原表上互斥（原表已有 2 行含该串）；取可测断言 + 单一真源 |
| 3 | `ci.yml` 的 test job 用 `CODE_SIGNING_ALLOWED=YES` + `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=YES` | 全局约束那条是为**本地 build** 写的；CI 的测试必须能启动 `TEST_HOST`，否则单测根本跑不起来 |
| 4 | `plutil -remove` 用**转义点号** key（`'com\.apple\.security\.mach-services'`） | 实测上游未转义写法是**静默 no-op**（"No value to remove"），entitlement 会留在原地 |
| 5 | **接触白名单执行中扩容**（4c76c7e 单独提交、已重新审批）：`Package.resolved`、`audio/AudioTap.swift`、`DynamicIslandApp.swift`、scheme、`ci.yml`；T9 追加 `scripts/add_unit_test_target.rb` | T2 审查发现 Sparkle 的运行期落点、A12 漏了第 4 种 subsystem 变体、测试宿主/测试 bundle id 无任务拥有 |
| 6 | T8 越权改 `docs/08`（P0-2 收尾块改为完成态记录），并把 `upstreams.tsv` 的 KeyboardShortcuts 行登记值改为 pin `045cf174` | 验收 `grep -rn 'scripts/verify-upstreams' README.md docs/` 必须为 0；且该行 `usage=dependency`，原值（本地浅 clone HEAD `772133d`）会被新加的 pin 一致性检查判为 drift → exit 1 |
| 7 | T7 仍在 canonical 路径 `~/Library/Developer/Xcode/Gourd` 构建，并把过期的 `SourcePackages` 整体移开（重命名为 `SourcePackages.pre-T7`，未删） | 验收① 的判据写死了该路径；隔离既满足「干净 DerivedData」，又留下「重新解析能否复现已提交 `Package.resolved`」的强证据 |
| 8 | T7 回写 A 表 7 行（计划只点名 A1/A9/A8/A12），含 A5/A6/A7 的过期行号 | 同属「A 表现值/落点过期」，一并校正并标注来源（基线实测 vs 早先记的 dev HEAD 行号） |
| 9 | `verify-upstreams.sh` 的依赖判定取「`mode` 或 `usage` 任一为 dependency」；`sync-upstreams.sh` 只对 `mode` 短路 | 现网既有依赖行把 `dependency` 写在 `usage` 列（`mode=shallow`），双列判定让两种落点都生效；两个脚本口径不完全对称，已写进脚本注释 |
| 10 | T9 未按「预期」实跑 GUI 抓启动日志 | D-05 已定 GUI 行为人工验收；改用静态 + 产物级证据（源码唯一入口 + 产物无上游 appcast 字面量 + 产物 `SUFeedURL` 空）。「启动后无外连」仍列人工验收 |

### 遗留项（不在本次范围内，按优先级）

| 项 | 状态 | 归属 |
|---|---|---|
| **`release.yml` 的 `push` 触发**（首推 `main` 会跑上游签名/公证/DMG） | **未改**，推送前必须先改手动触发或删除 | **阻断「授权推送」这一动作**，不阻断本次交付 |
| CI 实跑（含 headless 上的 `TEST_HOST` 启动） | 未跑（无 remote） | 授权后首次推送 |
| `project.pbxproj` 的 10 条 `INFOPLIST_KEY_NS*UsageDescription` 仍是 "Atoll ..."（进产物的权限弹窗文案） | 未改（终审禁改工程文件）；**终审新发现** | 建议并入 P3 文案收尾 |
| `ModelPricingManager.swift:59` 抓上游 feature 分支 raw JSON | 未改（白名单外） | 后续任务：随包 `pricing.json` + 删远程 URL |
| `LICENSE` 未进 app bundle | 未改（白名单外） | P5 分发前必须解决 |
| 用户可见署名（`SettingsView:3756` + 8 条本地化、`sponsorPage`、`FUNDING.yml`、onboarding 隐私政策链接） | 未改 | P3 文案收尾 |
| `scripts/add_ui_test_target.rb:26` 仍 `com.atoll.DynamicIslandUITests` | 未改（白名单外） | 随手修 |
| `tools/verify-upstreams.sh` 不比对非 dependency 行的 `clone_commit` | 已记已知限制 | 后续任务 |
| docs/08 §C 类文案（菜单标识 `Atoll.Focus.Menu`、无障碍标识 `AtollNotch`、`Atoll_Virtual_Tap`、Notes 同步文件夹名、Codex UA、`caffeinate` 理由串、`getatoll.app/marketplace` 市场链接） | 未改 | 「随手改」类，见 docs/08 §C |
| 项目目录名 `lagoon` → `gourd` | 未改（D-02） | 需先备份 agent-memory 项目键 |
