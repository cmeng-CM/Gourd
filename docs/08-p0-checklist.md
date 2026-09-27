# P0 工程改造清单（可执行）

对应 [02-roadmap.md](02-roadmap.md) 的 P0。「基座落地」在这里被拆成 10 张任务卡，每张都有**可执行的验收判据**。前置阅读：[06-module-protocol.md](06-module-protocol.md) §0（上游事实基线）、[04-upstreams.md](04-upstreams.md)（同步策略）。

## 0. P0 的目标与边界

**目标**：本机能编译运行改名后的壶中天（Gourd），刘海面板可折叠/展开，CI 绿灯，上游可跟随。

**明确不做**（避免 P0 变成架构重构）：

| 不做 | 推到 |
|---|---|
| 不改扩展通道的线协议名（mach service / 分布式通知名 / RPC 端口 / Application Support 子目录） | P4（该层会整体重写） |
| 不改模块架构、不动 `ContentView` 的渲染逻辑 | P1 |
| 不减上游任何功能（我们的原则是"先原样跑起来再替换"） | 持续 |
| 不签名、不公证、不发版 | P5 |

**一条贯穿 P0 的原则**：**把对上游文件的修改压到最小**。新代码进新目录，上游文件只做「改名」与「接线」两件事。上游 5 周漂移 155 文件（实测），接触面积越小，季度同步越便宜。

---

## P0-1 基线冻结与环境前置

**目标**：钉一个确定的 commit 作为一切工作的起点，并把两个已实测的环境坑先填掉。

### 环境前置（先做这两件事，否则后面每一步都会误判）

| # | 前置 | 命令 / 规则 | 依据 |
|---|---|---|---|
| E1 | **安装 Metal Toolchain**（Xcode 26+ 起为独立按需组件） | `xcodebuild -downloadComponent MetalToolchain` | ✅ **已完成**（2026-09-27 实测 `Status: installed`）。缺它必失败：`error: cannot execute tool 'metal' due to missing Metal Toolchain` |
| E2 | **DerivedData 不放 `/tmp`** | 一律 `-derivedDataPath ~/Library/Developer/Xcode/<name>` | 实测放 `/tmp` 会让包解析服务**永久挂起**（无报错、无超时），详见文末诊断 |

### 实测工具链（2026-09-27，本机）

| 项 | 值 |
|---|---|
| Xcode | 27.0（27A266a） |
| Swift | 6.4（swiftlang-6.4.0.34.1） |
| macOS SDK | 27.0 |
| 本机系统 | macOS 27.0（26A428） |
| 上游要求 | app target 部署目标 `14.6`（`project.pbxproj:754,829`）；上游 CI 注释称"源码需要 Swift 6.1+" |

→ 路线图里"确认 Xcode / macOS SDK 版本（Atoll 要求 macOS 14+）"一项**完成**：工具链显著高于要求。

### 基线候选（实测漂移数据）

| 候选 | commit | 日期 | 相对 dev HEAD | 扩展子系统 | 结论 |
|---|---|---|---|---|---|
| `v2.3.3` | `e21cdf7` | 2026-07-24 | 211 文件 / +59425 −16355 | **落后**：RPC server 差 182 行、ExtensionsSettings 差 43 行 | ✗ 扩展层过旧 |
| **`v2.3.3-beta.3`** | **`c7305ec`** | **2026-08-20** | 155 文件 / +44051 −21595 | **与 dev HEAD 一致**（仅 `Constants.swift` 差 222 行，属其它功能） | ✅ **采用** |
| `dev` HEAD | `ad6834e` | 2026-09-27 | — | 同上 | ✗ 未发布的开发分支 |

**决定：基线 = `v2.3.3-beta.3`（`c7305ec`）**。理由：① 扩展子系统与 dev HEAD **字节级一致**，我们 [06-module-protocol.md](06-module-protocol.md) §0 的勘察结论可直接用于该基线；② 避开 `v2.3.3` 的 182 行 RPC 差异；③ `Package.resolved` 在 `v2.3.3-beta.3 → dev HEAD` 之间**零差异**，依赖面稳定。

**代价**：基线是 prerelease 版本号，且不是最新。接受——上游处于 5 周 155 文件的开发速度，任何基线都会迅速落后，关键是**同步机制**而非起点。

**验收**
```bash
cd ~/workspace/github/Atoll && git rev-parse --short v2.3.3-beta.3   # → c7305ec
git worktree list                                                    # 基线检出可复现
```

**收尾**：更新 [upstreams.tsv](../upstreams.tsv) 的 Atoll 行（`clone_commit` → `c7305ec (v2.3.3-beta.3)`）；[04-upstreams.md](04-upstreams.md) §1 表格同步。

---

## P0-2 工程引入（git 结构）

**现状**：本仓库**尚无任何提交**（`git log` 为空，文件全部未跟踪）。这反而是最干净的机会——用一次 merge 把两条历史接起来，之后 `git merge upstream/...` 是原生操作。

### 步骤

```bash
cd ~/workspace/github/lagoon

# 1) 先把现有文档与工具提交成 L0，并打 tag（下一步 merge 要用到它的 sha）
git add -A && git commit -m "docs: 决策/架构/路线图/许可证矩阵/上游清单/协议设计"
git tag l0

# 2) 接上游历史
git remote add atoll https://github.com/Ebullioscopic/Atoll.git
git fetch atoll --tags

# 3) 以基线 tag 为起点建 main，再把 L0 叠上来
git switch -c main c7305ec
git merge --allow-unrelated-histories l0
```

**预期冲突与处置**

| 冲突项 | 上游内容 | 处置 |
|---|---|---|
| `ReadMe.md` ↔ `README.md` | 上游顶层文件名是 **`ReadMe.md`**（大小写不同），我们的是 `README.md`——**本机文件系统大小写不敏感，两者只能存在一个** | **取我们的**：`git checkout l0 -- README.md` + `git rm --cached ReadMe.md`；极性与收尾步骤详见 plan T1（`--ours/--theirs` 在此 merge 里极性反直觉，一律用显式 ref） |
| `NOTICE` | **boring.notch 署名声明**（Atoll 的 GPL 义务） | **合并，不覆盖**：保留上游段 + 加"壶中天（Gourd）基于 Atoll 修改" + 我们的登记表。详见 P0-6 |
| `LICENSE` | GPL-3.0 | **无冲突**（已实测与我们的字节相同） |
| `.gitignore` | 上游规则 | 合并（取并集） |
| `scripts/` | 9 个 ruby 脚本（构建辅助） | 无同名文件冲突。**但**按 P0-2 下一步把我们的工具迁走 |
| `docs/` | **上游无此目录** | 无冲突 |

**收尾：把仓库自身工具从 `scripts/` 迁到 `tools/`**

上游 `scripts/` 是 Xcode 构建辅助脚本（`add_unit_test_target.rb` / `fix_test_host.rb` 等），与我们的"上游同步与校验"脚本职责完全不同。混在一起会让未来的合并冲突难以判断归属。

```bash
git mv scripts/sync-upstreams.sh tools/sync-upstreams.sh
git mv scripts/verify-upstreams.sh tools/verify-upstreams.sh
# 同步更新 references: README.md / docs/04-upstreams.md 里的路径
```

### 分支模型

| 分支 / ref | 角色 |
|---|---|
| `main` | 我们的集成线。**始终包含完整上游历史** |
| `atoll/*` tags | 上游 tag 原样保留（merge base 与追溯用） |
| `sync/atoll-YYYYMMDD` | 季度同步的试合并分支（[04-upstreams.md](04-upstreams.md) §2） |
| `upstream` / `atoll` remote | **只读**，禁止 push |

**验收**
```bash
git log --oneline | head -3                       # 顶部是我们的提交
git log --oneline c7305ec | head -3               # 基线可达
git merge-base main c7305ec                        # → c7305ec
git status --porcelain                             # 干净
```

---

## P0-3 身份改造清单

分两张表：**A 运行相关**（不改就出 bug）与 **B 冻结项**（P0 刻意不改）与 **C 文案相关**（不影响功能，可缓）。

### A. 必改（运行相关）

| # | 项 | 现值（上游） | 文件:行 | 新值 |
|---|---|---|---|---|
| A1 | Release Bundle ID | `com.Ebullioscopic.Atoll`（`project.pbxproj:907`） | `project.pbxproj:832,907` | `com.cmeng.<应用名>`（域名根已定，后缀见 D-9） |
| A2 | Debug Bundle ID | `com.Ebullioscopic.Atoll.dev`（`:832`） | 同上 | `com.cmeng.<应用名>.dev` |
| A3 | `PRODUCT_NAME` | `Atoll` | `project.pbxproj:833,908` | `Gourd`（二进制名/路径用 ASCII，避免中文路径） |
| A4 | `CFBundleDisplayName` | `Atoll` | `project.pbxproj:808,883` | **`壶中天`**（用户可见名；也可先设 `Gourd`，后续走 InfoPlist.strings 本地化） |
| A5 | **Sparkle feed URL** | `raw.githubusercontent.com/Ebullioscopic/Atoll/main/Updates/appcast.xml` | `DynamicIsland/Info.plist:21` | **P0 必须处理**：指向本仓库的空 appcast，或清空 + 关闭自动更新 |
| A6 | **Sparkle EdDSA 公钥** | `q2YQaJ1umGkaIJWMGN9Isj5fx/...` | `DynamicIsland/Info.plist:23` | P0 置空；P5 生成我们自己的密钥对 |
| A7 | Sparkle 下载/安装服务 | `SUEnableDownloaderService`/`SUEnableInstallerLauncherService = true` | `DynamicIsland/Info.plist` | P0 改 `false` |
| A8 | 测试 host 路径 | `$(BUILT_PRODUCTS_DIR)/Atoll.app/Contents/MacOS/Atoll` | `scripts/fix_test_host.rb:9`、`scripts/add_unit_test_target.rb:38` | 跟随 `PRODUCT_NAME` |
| A9 | CI 产品名 + **日志导出筛选的消费方** | `APP_NAME: Atoll`、DMG 名、`Atoll Logs.zip`、`exportLogs` 里按 `subsystem == 'com.Ebullioscopic.Atoll'` 与 `contains("Atoll")` 筛选（**基线 c7305ec 实为 `DynamicIslandApp.swift:1211,1223,1229`**，docs 早先记的 1321/1347/1353 来自 dev HEAD） | `.github/workflows/release.yml`、`DynamicIsland/DynamicIslandApp.swift` | `Gourd` / `com.cmeng.gourd` |
| A10 | CI 里 entitlements 路径 | `DynamicIsland/DynamicIsland.entitlements` | `.github/workflows/ci.yml`（Build 步骤） | 保持不变即可（文件路径不含产品名，仅需确认） |
| A11 | 应用图标 | `AppIcon` / `AppIconDev` / `AppIconAlpha/Beta/Nightly` 五套 | `Assets.xcassets/` | 替换 `AppIcon`（Release）与 `AppIconDev`（Debug）；其余可先留 |
| ~~A13~~ | ~~Swift 模块名~~ | — | — | **不改**：加 `PRODUCT_MODULE_NAME = Atoll` 保持模块名不变（D-10）——改了会让 4 个上游单测文件的 `@testable import Atoll` 编译失败，而本地只构建 app、CI 不实跑，看不见 |
| A12 | 日志 subsystem | `com.ebullioscopic.Atoll`（`Logger.swift:66` 等）、`com.Ebullioscopic.Atoll`（`TimerManager.swift:131` 等）、`com.atoll.DynamicIsland`（`CodexQuotaClient.swift:6`） | 见左 | 统一 `<反域名>.Lagoon` |

> **A5/A6/A7 是 P0 里唯一有安全后果的改动**：不处理的话，Sparkle 会按照上游 feed 检查更新，并有可能把 **Atoll 的包安装到壶中天（Gourd）上**（公钥仍是上游的，签名校验会通过）。必须在第一次分发前修掉，P0 就修。
>
> 副作用：改 A1/A2 会让 **UserDefaults 域随之改变**（域 = bundle id），上游已有的用户设置会"消失"（仍在旧 plist 里）。自用项目接受；若要保留，P1 加一次性迁移：从 `com.Ebullioscopic.Atoll` 域读取指定键导入新域。

### B. 冻结项（P0 刻意不改，P4 一次性重写）

这些名字构成扩展通道的**线协议身份**。P0 改它们没有任何收益（P4 之前没有第三方在使用），却会引入"上游兼容读取"的破坏。

| 项 | 值 | 文件:行 |
|---|---|---|
| XPC mach service 名 | `com.ebullioscopic.Atoll.xpc` | `services/Extensions/ExtensionXPCServiceHost.swift:25` |
| mach-services entitlement | 同上 | `DynamicIsland.entitlements:11` |
| RPC 端口 / 绑定 | `9020` / `127.0.0.1` + `::1` | `ExtensionRPCServer.swift:85-98` |
| 分布式通知名（3 个桥通道） | `com.ebullioscopic.Atoll.extensions.*` | `ExtensionEventBridge.swift:157-166` |
| 生命周期通知名 | `com.ebullioscopic.Atoll.lifecycle.*` | `AtollDistributedNotifications.swift:14-15` |
| Application Support 子目录 | `AtollExtensions/` | `ExtensionEventBridge.swift:116-128` |
| RPC 临时目录 | `temporaryDirectory/AtollExtensionFiles` | `ExtensionRPCService.swift:574` |
| Defaults 键（12 个 `extension*` / `enable*`） | `extensionAuthorizationEntries` 等 | `models/Constants.swift:1381-1394` |
| Keychain service | `com.Ebullioscopic.Atoll.Cider` / `.SpotifyLibrary` / `.new-api` | `CiderTokenStore.swift:25` 等 |

**已知不一致（记录，不在 P0 修）**：mach service 名与 kit 查找宿主用的 bundle id 写作 `com.ebullioscopic.Atoll`（小写 e），而真实 `PRODUCT_BUNDLE_IDENTIFIER` 是 `com.Ebullioscopic.Atoll`（大写 E）。上游 kit 的 `isAtollInstalled` 因此一直靠 `/Applications/Atoll.app` 兜底路径工作。我们改名后，**依赖上游 kit 的第三方 App 将无法连上 Lagoon**（见 [06-module-protocol.md](06-module-protocol.md) §9.3）。这是明确接受并记录在案的后果。

### C. 文案相关（不影响功能，随手改）

`os.Logger` category、菜单标识 `Atoll.Focus.Menu` 等（`DynamicIslandApp.swift:1120-1311`）、无障碍标识 `AtollNotch`（`ContentView.swift:688`，**UI 测试依赖它，改了要同步改测试**）、音频设备名 `Atoll_Virtual_Tap`（`audio/AudioTap.swift:285`）、Apple Notes 同步文件夹名 `Atoll`（`AppleNotesSyncManager.swift:56`）、Codex User-Agent（`CodexQuotaClient.swift:42`）、`caffeinate` 理由字符串（`CaffeinateManager.swift:155`）、Localizable.xcstrings 里的 "Atoll"、市场链接 `getatoll.app/marketplace`（`ExtensionsSettings.swift:72`，应改为我们自己的插件清单仓库或直接移除）。

**验收**
```bash
xcodebuild -showBuildSettings -project DynamicIsland.xcodeproj -scheme DynamicIsland \
  | grep -E 'PRODUCT_NAME|PRODUCT_BUNDLE_IDENTIFIER|MACOSX_DEPLOYMENT_TARGET'
# 期望: Gourd / com.cmeng.gourd / 14.6
plutil -p DynamicIsland/Info.plist | grep -iE 'SUFeedURL|SUPublicEDKey'   # feed 不再是上游地址
grep -rn "com.ebullioscopic.Atoll.xpc" DynamicIsland/services DynamicIsland/DynamicIsland.entitlements
# 期望: 仍为原值（冻结项，证明没被误改）
```

---

## P0-4 依赖治理

### 现状

`Project.resolved` 共 16 条依赖，其中 **4 条使用 `branch = main`**（违反 [04-upstreams.md](04-upstreams.md) §2 自己的规则"锁定 minor 版本区间、不要用分支依赖"）：

| 依赖 | 当前 requirement | 已解析 revision | P0 处置 |
|---|---|---|---|
| `Ebullioscopic/AtollExtensionKit` | `branch = main`（`project.pbxproj:1000-1007`） | `e2d30afe…` | **pin revision**（我们的内容协议对齐它） |
| `sindresorhus/LaunchAtLogin-Modern` | `branch = main` | `a04ec1c3…` | pin revision |
| `Lakr233/SkyLightWindow` | `branch = main`（`:932-937`） | `4a7e8628…` | pin revision |
| `jasudev/LottieUI` | `branch = main` | `0cd5b54a…` | pin revision |

其余 9 条已是 `upToNextMajorVersion` 语义（版本号），不动。另有 **1 条死依赖要删**：`open-meteo/open-meteo` 1.4.16 在 `project.pbxproj:992-998` 有声明，但**不在 `packageProductDependencies` 里、全仓库零 `import OpenMeteo`**——实际天气功能是裸 `URLSession` 打的 public API。（顺手可省一个供应链面。）

### 步骤

1. 在 `project.pbxproj` 的 `XCRemoteSwiftPackageReference` 里把上述 4 条的 `requirement` 从 `{kind = branch; branch = main}` 改为 `{kind = revision; revision = <已解析值>}`。
2. 提交 `Package.resolved`，并在 `tools/verify-upstreams.sh` 里加一条：`Package.resolved` 与该清单一致（防 CI 静默漂移）。
3. `upstreams.tsv` 增加一目（`AtollExtensionKit`，`mode = dependency`，用途"上游内容描述符与 XPC 协议定义"）。
4. `NOTICE` 登记该依赖。
5. **许可缺口（已实测，须记录并推进）**：该仓库 README 挂了 MIT 徽章并指向 `LICENSE`，但**仓库里没有 LICENSE 文件**（checkout 内无 `LICENSE` / `LICENSE.md` / `LICENSE.txt` / `COPYING`）。处置：在 [03-license-matrix.md](03-license-matrix.md) 登记为"⚠️ 有条件使用：待上游补文件"；**首次分发二进制前必须解决**（向上游提 issue/PR 补 LICENSE，或改按 wire 语义自实现类型）。P0 本身不阻塞（P0 不分发），但必须现在登记，避免 P5 才发现。

**为什么不 fork AtollExtensionKit**：ADR-0003「能当依赖就不 fork」。我们只需**读得懂**它的类型（[06-module-protocol.md](06-module-protocol.md) §9），不需要改它。真正需要改的时刻是 P4（那时我们自己定义 `ContentDescriptor` 并做映射），届时再决定 fork 或自建。

**验收**
```bash
grep -c 'kind = branch' DynamicIsland.xcodeproj/project.pbxproj     # → 0
bash tools/verify-upstreams.sh                                       # 全绿
```

---

## P0-5 构建、签名与 CI

### 本机构建

```bash
xcodebuild build -project DynamicIsland.xcodeproj -scheme DynamicIsland \
  -destination "platform=macOS" \
  -derivedDataPath ~/Library/Developer/Xcode/Gourd \   # ← 必须：不要用 /tmp（P0-1 E2）
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

**实测结果：✅ BUILD SUCCEEDED**（2026-09-27，装好 Metal Toolchain 后完整跑通）。产物 `Atoll.app` 116MB，零 Swift 编译错误。诊断过程与进程栈证据见文末"构建验证结果"。

**entitlements 注意事项**：上游 CI 在 Build 前执行
`plutil -remove com.apple.security.mach-services DynamicIsland/DynamicIsland.entitlements`
（注释原文：*Strip mach-services entitlement (amfid kills ad-hoc app)*）。**我们的 CI 沿用该步骤**；本机 ad-hoc 构建若遇到启动即被杀，同样处理。

**已知事实**（记录，避免日后误判）：entitlements **没有 app-sandbox**。因此我们读写 `~/Library/Application Support/Gourd/`、插件目录、Keychain 都不需要额外授权；反过来说，**一旦将来要上沙箱，配置与插件目录访问都要重做**。ADR-0001 已排除上架，因此保持不入沙箱。

**部署目标保持 14.6**：液态玻璃（macOS 26+）等新 API 用 `if #available` 门控（[01-architecture.md](01-architecture.md) §7 已有"材质降级"设计），不要把最低版本抬到 26。

### CI（`.github/workflows/`）

| workflow | P0 动作 |
|---|---|
| `ci.yml` | 上游已有：构建 + 两个 python unittest（`test_privacy_configuration` / `test_timer_lifecycle`）。**改造为**：构建 + `xcodebuild test`（单测）+ `swift-format` 检查，matrix 保留 `macos-15` / `macos-26` |
| `release.yml` | P0 **不动**（35KB，含签名/公证/DMG；P5 再改）。先确保它不会被误触发：确认触发的 tag 规则与 `APP_NAME` 一起放到 P5 |
| 其余 5 个（`mirror-release` / `nightly-merge` / `triage-slash-commands` / `update-pricing` / `validate-changelog`） | 与我们的分发无关，**P0 直接删除**（`update-pricing` 会向上游仓库写回数据；`nightly-merge` 会改上游分支——留着有害） |
| `release.yml` 的触发条件（**更正**） | 实测上游是 **`on: push: branches: [nightly, alpha, beta, main]`**（**不是 tag 触发**，早先文档记错）。⚠️ 因此**授权推送后首推 `main` 就会跑完整的签名/公证/DMG 发布**（用上游 `APP_NAME: Atoll` 与上游 TEAM_ID）。推送前必须先改为 `workflow_dispatch` 或删除 |
| CI 必须先下载 Metal Toolchain | `sudo xcodebuild -downloadComponent MetalToolchain`（上游 ci.yml 已有、带重试）。**缺它 macOS 26 runner 上 Metal 编译必失败**，而因 CI 不实跑，这个坑不会被自动发现 |

**验收**：GitHub Actions 上 `ci.yml` 绿灯（构建 + 测试 + 格式）。

---

## P0-6 合规与署名

| 项 | 动作 |
|---|---|
| `LICENSE` | 无需改动（实测与上游字节相同，均为 GPL-3.0 全文） |
| `NOTICE` | **合并**：① 保留上游原有的 **boring.notch 署名段**（这是 Atoll 的 GPL 义务，删掉即违规）② 增加"壶中天（Gourd）是 Atoll 的修改版本（fork）"声明，注明基线 commit `c7305ec` ③ 保留我们已有的上游登记表 ④ 登记 `AtollExtensionKit` 依赖（P0-4） |
| 修改标注（**口径已定 D-09**） | **以 `NOTICE` 总声明 + 每任务提交信息满足 GPL-3.0 §5(a)**，不逐文件加行内注释：`project.pbxproj`（`/* */`）、`Info.plist`（XML 注释）逐一加注释不可行且噪音大，而提交信息 + git 历史是可核查的修改记录。`NOTICE` 里写明「本仓库为 Atoll 修改版本（基线 `c7305ec`），改动范围见 git 历史」 |
| `README.md` | 已有 fork 说明与命名注解（壶中天 / Gourd，含"壶中天地"典故与 GPL fork 关系）——补上基线版本号即可 |
| **vendored 二进制的许可补齐** | 🔴 **上游不合规，我们要补**：`Frameworks/MediaRemoteAdapter.framework` 与 `mediaremote-adapter/MediaRemoteAdapter.framework`（两份逐字节相同的副本）+ `Contents/Helpers/NowPlayingTestClient` 均**无许可文件**，而配套 perl 脚本头声明 BSD-3-Clause（`Copyright (c) 2025 Jonas van den Berg`）→ BSD-3 要求二进制分发时复现版权声明与许可全文。四个动作：① 两个目录各补一份 LICENSE（版权行 + 三条款全文）② ~~删掉重复的那份 framework~~ **不删**（**D-07**：`FRAMEWORK_SEARCH_PATHS` 同时指向 `Frameworks/` 与 `mediaremote-adapter/` 两处，删副本有破坏链接的风险）③ `NowPlayingTestClient` **保留**并记为已知限制（仅 arm64，x86_64 上不可用；本机为 arm64 暂不影响）④ `NOTICE` 登记。详见 [03-license-matrix.md](03-license-matrix.md) §2 |
| `open-meteo` 死依赖 | 该 SPM 依赖**声明了但未链接、全仓库零 `import OpenMeteo`**，实际天气是裸 `URLSession` 实现 → P0-4 里删掉（同时减一个依赖面） |
| 源码归档 | P5 分发时的义务，此处仅登记 |

**验收**
```bash
grep -c "boring.notch" NOTICE            # ≥ 1（上游署名未被覆盖）
grep -c "c7305ec" NOTICE                 # = 1（基线 commit 已记）
```

---

## P0-7 为 P1 预留的骨架（只建接缝，不写实现）

**目标**：P1 一开工就能直接往里填，不需要先做目录决策。

### 目录规划（新代码全部进新目录，与上游目录不重叠）

```
DynamicIsland/
├── Kernel/      ← L0：NotchWindow / NotchGeometry / NotchStateMachine / EventBus / ConfigStore / ThemeCenter / PermissionCenter
├── Runtime/     ← L1：ModuleRegistry / ModuleManifest / GourdModule / ModuleContext / ConfigSchema
├── Modules/     ← L2：内置模块，一个模块一个子目录（NowPlaying/ Lyrics/ Shelf/ Stats/ …）
└── （上游既有：managers/ services/ models/ components/ enums/ audio/ … 原样保留）
```

**关键发现（降低合并成本）**：上游用的是 Xcode 16 **同步文件夹**（`fileSystemSynchronizedGroups = (Contents, DynamicIsland)`，`project.pbxproj:374-377`）。**新增文件与目录会自动加入 target，不需要改 `project.pbxproj`**。这意味着我们的新目录几乎不产生 pbxproj 冲突——P0-7 的核心收益。

### P1 才落地的最小骨架（P0 不做）

> **P0 不做这一节**：P0 只做基座落地，不写任何协议/业务代码。下面 5 个纯数据类型文件是 **P1 的第一批交付**（无副作用、无依赖、可单测），列在此处是为了让 P1 开工即有明确清单。

| 文件 | 内容 | 依据 |
|---|---|---|
| `Runtime/ModuleManifest.swift` | `ModuleManifest` / `LocalizedText` / `IconSpec` / `EntryPoint` / `Placement` / `Surface` / `Capability` / `limits` | [06-module-protocol.md](06-module-protocol.md) §2 |
| `Runtime/ConfigSchema.swift` | `ConfigSchema` + 13 种 type 的 Node 模型 | [06-module-protocol.md](06-module-protocol.md) §5 |
| `Runtime/ModuleContent.swift` | `ContentRequest` / `ModuleContent` / `NotchPhase` / `ContentRequestReason` | [06-module-protocol.md](06-module-protocol.md) §3.1-3.2 |
| `Runtime/GourdEvent.swift` | 事件信封 + 首批 13 个事件的 payload 类型 | [07-config-and-events.md](07-config-and-events.md) §3-4 |
| `Runtime/ManifestValidator.swift` | 14 条校验规则 + 19 个错误码 | [06-module-protocol.md](06-module-protocol.md) §10 |

**不写**：`ModuleRegistry` 的启停逻辑、`EventBus` 的投递、`ConfigStore` 的迁移链——这些是 P1 的主体，P0 写会缺测试与场景。

### P0 期间的上游文件接触白名单

除以下文件，**不许修改任何上游文件**（新增文件不算）。这份清单同时是季度同步时的冲突预期范围：

```
DynamicIsland.xcodeproj/project.pbxproj      (产品名 / bundle id / 依赖 pin)
DynamicIsland/Info.plist                     (显示名 / Sparkle)
DynamicIsland/DynamicIsland.entitlements     (mach-services，仅 CI 剥离需要时)
DynamicIsland/models/Constants.swift         (日志 subsystem 等命名)
scripts/fix_test_host.rb / add_unit_test_target.rb / fix_module_name.rb   (产品名)
DynamicIsland/utils/Logger.swift、managers/TimerManager.swift、managers/SystemTimerBridge.swift、
managers/ReminderLiveActivityManager.swift、components/Settings/SpotifyLoginSheet.swift、
managers/LLMUsage/Quota/CodexQuotaClient.swift、managers/LLMUsage/AntigravityUsageProvider.swift
                                                       (A12 日志 subsystem；全部为字符串级替换)
DynamicIsland/DynamicIslandApp.swift                   (A9 日志导出筛选)
DynamicIsland.xcodeproj/xcshareddata/xcschemes/DynamicIsland.xcscheme   (BuildableName → Gourd.app)
DynamicIsland/audio/AudioTap.swift                     (A12 第 4 种 subsystem 变体 com.atoll.dynamicisland)
DynamicIsland.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved   (依赖 pin)
DynamicIsland/services/AtollUpdaterDelegate.swift      (A5 的真实落点：运行期覆盖 feedURLString)
DynamicIsland/models/UpdateChannel.swift               (A5 的真实落点：硬编码上游 appcast 地址)
DynamicIsland/strings/constants.swift                  (productPage 等用户可见串仍指上游)
.github/workflows/ci.yml                     (我们的 CI)
```

**验收**：`git diff --name-only c7305ec HEAD | grep -v '^DynamicIsland/Kernel\|^DynamicIsland/Runtime\|^DynamicIsland/Modules' | wc -l` —— 结果应只包含白名单内的文件。

---

## P0-8 验收清单（整体）

```bash
# 1) 基线可复现
cd ~/workspace/github/Atoll && git rev-parse --short v2.3.3-beta.3    # c7305ec

# 2) 工作区干净、历史完整
cd ~/workspace/github/lagoon
git status --porcelain                                                 # 空
git merge-base main c7305ec                                            # c7305ec

# 3) 产品身份正确
xcodebuild -showBuildSettings -project DynamicIsland.xcodeproj -scheme DynamicIsland \
  | grep -E 'PRODUCT_NAME|PRODUCT_BUNDLE_IDENTIFIER'                    # Gourd / com.cmeng.gourd

# 4) 构建通过（前置：P0-1 E1 已装 Metal Toolchain；E2 不要用 /tmp 作 DerivedData）
xcodebuild build -project DynamicIsland.xcodeproj -scheme DynamicIsland \
  -destination "platform=macOS" -derivedDataPath ~/Library/Developer/Xcode/Gourd \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# 5) 手动验收（路线图 P0 验收标准）
open ~/Library/Developer/Xcode/Gourd/Build/Products/Debug/Gourd.app
#   → 刘海面板出现；鼠标移入展开、移出折叠；菜单栏（LSUIElement=YES 无 Dock 图标）可退出

# 6) 依赖已 pin、合规已登记
grep -c 'kind = branch' DynamicIsland.xcodeproj/project.pbxproj        # 0
grep -c 'boring.notch' NOTICE                                          # ≥1
bash tools/verify-upstreams.sh

# 7) CI 绿灯（GitHub Actions）
```

| 里程碑判据（[02-roadmap.md](02-roadmap.md)） | P0 结束时 |
|---|---|
| M0：跑起来了，但和 Atoll 没区别 | ✅ 应达成 |

---

## P0-9 风险与回退

| 风险 | 影响 | 对策 |
|---|---|---|
| 基线是 prerelease（`-beta.3`） | 可能有未修缺陷 | 接受；[02-roadmap.md](02-roadmap.md) 已把"接受 Atoll 的 alpha/beta 品质、做好自测"列为 ADR-0002 的后果 |
| macOS 27 + Xcode 27 编 14.6 部署目标的项目 | 可能遇到废弃 API 告警甚至错误 | P0-5 的冷构建即为验证；若失败，可临时抬高部署目标（记 ADR） |
| Sparkle 误更新（A5/A6/A7） | **拉上游包覆盖本应用** | P0-3 明确处置，且在 CI 里加一条断言：`Info.plist` 的 `SUFeedURL` 不得指向 `Ebullioscopic` |
| 上游 5 周漂移 155 文件 | 合并成本高 | ① 基线冻结 ② 接触白名单（P0-7）③ 季度同步（[04-upstreams.md](04-upstreams.md) §2） |
| 目录/脚本重名（`scripts/` 等） | 合并冲突难判 | P0-2 已把我们的工具迁到 `tools/` |
| **回退方案** | — | P0 阶段没有自有实现，回退成本极低：删掉 `main`，从基线 tag 重建分支，保留 `docs/` 与 `tools/` 即可。**这是刻意安排的**——P0 不写业务代码，就是为了让"重来一次"便宜 |

---

## P0-10 待拍板

| 编号 | 事项 | 建议 |
|---|---|---|
| D-9 | Bundle ID（反写域名 + 应用名）。**已定：`com.cmeng.gourd`**（2026-09-27；Debug `com.cmeng.gourd.dev`）。应用名 壶中天 / Gourd，命名过程与撞名排查见 [09](09-features-and-mechanisms.md) §8.3。它决定 **UserDefaults 域、Keychain 归属、TCC 权限记录、Sparkle 更新识别**，定下后基本不该再改（改了等于换一个新 App）。同生态实例：`com.Ebullioscopic.Atoll`、`wiki.qaq.NotchDrop`、`org.p0deje.Maccy`、`jacklandrin.OnlySwitch` | Debug 建议加 `.dev` 后缀（上游也是分开的）。**需一并定模块 id 的保留前缀**（[06](06-module-protocol.md) §2.2 现写作 `com.cmeng.gourd.`，建议与 Bundle ID 对齐，避免工程里出现两套命名空间） |
| D-10 | 是否在 P0 就做 UserDefaults 旧域迁移（从 `com.Ebullioscopic.Atoll` 导入既有设置） | 建议 P1 做，且只导白名单键（媒体源偏好、窗口行为），不做全量 |
| D-11 | 五个无关 workflow 是否直接删（P0-5） | 建议删：`update-pricing` / `nightly-merge` 会向上游写数据，留着有副作用 |
| D-12 | 应用图标：自绘还是先用占位 SF Symbol 风格 | 建议 P0 用占位（纯色 + 字母），图标设计不阻塞基座落地 |
| ~~D-13~~ | ~~是否安装 Metal Toolchain~~ | ✅ **已解决**（2026-09-27）：用户已安装，基线构建跑通（`** BUILD SUCCEEDED **`，产物 116MB） |

---

## 实测记录

| 日期 | 项 | 结果 |
|---|---|---|
| 2026-09-27 | 工具链 | Xcode 27.0 (27A266a) / Swift 6.4 / SDK 27.0 / macOS 27.0 (26A428) |
| 2026-09-27 | 基线构建（`v2.3.3-beta.3`，未改名的原样工程） | ✅ **BUILD SUCCEEDED**（装上 Metal Toolchain 后完整跑通），产物 `Atoll.app` 116MB，零编译错误 |
| 2026-09-27 | 上游漂移量 | `v2.3.3-beta.3 → dev HEAD` = 155 文件 / +44051 −21595 |
| 2026-09-27 | 依赖 | 16 条，其中 4 条 `branch = main` |
| 2026-09-27 | `LICENSE` 与上游一致性 | 字节相同（无合并冲突） |
| 2026-09-27 | `AtollExtensionKit` 许可 | README 声明 MIT，**仓库缺 LICENSE 文件**（见 P0-4 第 5 条） |

### 构建验证结果与两个环境前置条件（2026-09-27，已定位到根因）

**结论**：基座在 Xcode 27 上**完整编译通过（BUILD SUCCEEDED，产物 116MB）**，全程零编译错误。两个环境前置：需要 Metal Toolchain；**DerivedData 路径不能放在 `/tmp`**（后者是非显然的坑，见下）。

#### 前置 1：DerivedData 必须在 `~/Library/Developer/Xcode/` 下，不能用 `/tmp`

实测对照（同一工程、同一条命令，只变 DerivedData 路径）：

| DerivedData | destination | 结果 |
|---|---|---|
| `/tmp/atoll-dd` | `platform=macOS` | ❌ 永久挂在 `Resolve Package Graph`（等 >4.5 min，CPU 累计 0.04 s，无子进程、无编译进程） |
| `/tmp/atoll-dd`（**禁用 agent 沙箱**） | `platform=macOS` | ❌ 完全复现 → **与 agent 沙箱无关** |
| 默认（`~/Library/Developer/Xcode/DerivedData`） | `generic/platform=macOS` | ✅ 越过解析，编译至 Metal 报错 |
| `~/Library/Developer/Xcode/DD-gourd-test` | `platform=macOS` | ✅ 越过解析，编译至 Metal 报错 |

进程栈证据（卡住时 `sample`）：

```
-[Xcode3CommandLineBuildTool run]
  -[Xcode3CommandLineBuildTool _resolveInputOptionsWithTimingSection:]
    -[Xcode3CommandLineBuildTool waitForRemoteSourcePackagesToFinishLoading]
      +[DVTKVOConditionValidator waitForCondition:...timeout:]
        __CFRunLoopServiceMachPort → mach_msg        ← 停在这里，不返回也不超时
```

**根因**：Xcode 27 把包加载交给独立的 build service 进程，该进程受路径沙箱约束；DerivedData 指向 `/tmp`（实质是 `/private/tmp` 符号链接）时它读不到该目录，于是既不报错也不返回。

**已排除的其它因素**：网络（`curl github.com` → 200；首次尝试即成功下载 `SourcePackages/repositories` 285 MB）、首次启动组件/许可（`-checkFirstLaunchStatus` → exit 0）、非 GUI 会话（`launchctl managername` → `Aqua`）、宏/插件校验弹窗（已加 `-skipMacroValidation -skipPackagePluginValidation`，无变化）。
**无效的绕过**：`-disableAutomaticPackageResolution`、`-onlyUsePackageVersionsFromResolvedFile`、`-skipPackageUpdates`、分离 `-resolvePackageDependencies` 步骤、禁用 agent 沙箱。

> **P0 规则**：所有 `xcodebuild` 调用都显式指定 `-derivedDataPath ~/Library/Developer/Xcode/<name>`，**绝不指向 `/tmp`**。CI 不受影响（GitHub runner 用的是标准路径）。

#### 前置 2：安装 Metal Toolchain

```
error: cannot execute tool 'metal' due to missing Metal Toolchain; use: xcodebuild -downloadComponent MetalToolchain
```
`xcodebuild -showComponent MetalToolchain` → `Status: uninstalled`。

Xcode 26 起 Metal 编译工具链改为**按需下载的独立组件**，上游 CI 也有这一步（`.github/workflows/ci.yml` 里"下载 Metal Toolchain"）。失败文件位于**依赖** `SwiftTerm` 内（`Sources/SwiftTerm/Apple/Metal/Shaders.metal`），不是 Atoll 自己的代码。

> ✅ **本机已安装**（2026-09-27 实测：`Status: installed`，toolchain `com.apple.dt.toolchain.Metal.32023.921.5`）。装好之后同一命令完整跑通：`** BUILD SUCCEEDED **`。

#### 已验证通过的部分

- 依赖图解析完成，16 个包全部 checkout。
- 以下依赖目标构建通过：`AtollExtensionKit` / `Defaults` / `KeyboardShortcuts` / `LaunchAtLogin` / `MacroVisionKit` / `SkyLightWindow` / `SwiftTerm` / `SwiftUIIntrospect` / `swift-collections` 各模块 / Lottie（stub）。
- **`DynamicIsland` 主目标已进入构建阶段**。
- **全程仅 1 个 error**，即上述 Metal 组件缺失。

#### 已验证到哪一步

- **构建**：✅ 完整通过（含链接），产物 `~/Library/Developer/Xcode/DD-verify/Build/Products/Debug/Atoll.app`（116MB）。
- **运行**：未验证（这是原样未改名的上游工程，跑起来与 Atoll 无异；改名后的运行验收按 P0-8 第 5 步做）。

命令备忘（成功那次用的参数）：
```bash
xcodebuild build -project DynamicIsland.xcodeproj -scheme DynamicIsland \
  -destination "platform=macOS" -derivedDataPath ~/Library/Developer/Xcode/DD-verify \
  -skipMacroValidation -skipPackagePluginValidation \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

> 这条记录本身就是 P0 的一项产出：**先解决工具链，再动代码**。若不先解决这两个前置条件就开始改名，会把"环境问题"误判成"改名改坏了"，白白浪费调试时间。
