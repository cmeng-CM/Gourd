# 决策记录（ADR）

每条决策只记"选了什么、为什么、后果是什么"。后续如果推翻，新增一条 ADR 而不是改旧条目。

---

## ADR-0001：许可证路线选 GPL-3.0

**状态**：已采纳（2026-09-27）

**背景**：目标是用开源组件复刻并超越 Nook X（付费订阅的 macOS 灵动岛工具），自用 + 开源。候选路线一是 GPL 伞下融合，二是 MIT 干净自建。

**决策**：选 GPL-3.0。基座与合并进来的 GPL 组件（Atoll、boring.notch、lyrimuse 等）天然是 GPL，MIT / Apache-2.0 / MPL-2.0 的代码可以合法并入 GPL 工程（MIT 与 Apache-2.0 与 GPLv3 兼容，MPL-2.0 为文件级 copyleft、允许与 GPL 混合）。

**后果**：
- 可以自由融合几乎所有目标组件，工程阻力最小。
- **不能上 Mac App Store**——GPL 要求用户可自由复制与再分发，与 App Store 的 DRM 及条款冲突（VLC 因此下架的先例）。分发渠道限定为 DMG + 公证 + Homebrew + Sparkle 自动更新。
- 分发义务：提供完整源码、保留版权与许可声明、标注修改（见 NOTICE 与 docs/03）。
- 若未来要商业化或上架，必须重新走 MIT 路线（另起工程，只借思路不借代码）。

---

## ADR-0002：代码基座选 Atoll，而不是 boring.notch

**状态**：已采纳（2026-09-27）

**背景**：两个候选基座的实测对比（2026-09-27 数据）：

| | boring.notch | Atoll |
|---|---|---|
| 星标 / 许可 | 10879★ / GPL-3.0 | 4777★ / GPL-3.0 |
| Swift 文件数 | 123 | 321 |
| 扩展系统 | **无**。README 路线图里 "Extension system 🧩" 未勾选，`extensions/` 目录只是 Swift 语言扩展 | **已有**：XPC 服务（ExtensionXPCService/ExtensionXPCServiceHost）、RPC（ExtensionRPCServer/ExtensionRPCService）、事件桥（ExtensionEventBridge）、描述符校验（ExtensionDescriptorValidator）、授权（ExtensionAuthorizationManager）、Live Activity 与锁屏小组件扩展、扩展设置界面 |
| 功能面 | 媒体可视化、日历/提醒、文件架、镜像、HUD、手势 | 媒体控制（Apple Music / Spotify / Cider）、Live Activities、锁屏小组件、CPU/GPU/内存/网络/磁盘监控、计时器、剪贴板、取色器、日历预览 |
| 发布状态 | nightly + v2.8-rc，Sparkle 自动更新 | 2.3.3 alpha/beta |

**决策**：以 Atoll 为 fork 基座，boring.notch 作为**功能对照实现**（同为 GPL，代码可合并）。

**理由**：本项目的核心诉求是"可定制化、可持续完善"，这等价于"插件架构 + 模块边界"，而 Atoll 已经有进程外扩展宿主、描述符校验与授权模型。在 boring.notch 上要先把这套地基造出来，且其上游提交极快（近期仍在密集推送），fork 后冲突成本高。

**后果**：
- 起点代码量更大（321 文件），前期读码成本高；但省掉自建插件宿主的工作量。
- 需要接受 Atoll 的 alpha/beta 品质，做好自测与回归。
- 必须保留 Atoll 的 GPL 声明与版权头。

---

## ADR-0003：能当依赖就不 fork

**状态**：已采纳（2026-09-27）

**决策**：上游分三类使用方式，优先级从高到低为 ①SPM 依赖 → ②按目录引进（vendored，保留原 LICENSE）→ ③真 fork（仅基座）。

- ①：DynamicNotchKit、KeyboardShortcuts、LaunchAtLogin-Modern、Defaults 等纯库。
- ②：NotchDrop、OpenYoink、stats、Maccy、OnlySwitch、LyricsX、lyrimuse 等应用型项目的**局部实现**（取文件/模块，不取整个工程）。
- ③：Atoll（唯一 fork，保留 upstream remote 以便跟随）。

**后果**：升级上游时只需 `git pull` 或改 SPM 版本号；代价是引进局部代码时需要做适配层与边界重构，不能直接吃整棵工程。

---

## ADR-0004：插件宿主先 XPC，JS 沙箱后置

**状态**：已采纳（2026-09-27）

**决策**：
- **第一阶段**：复用 Atoll 的进程外 XPC 宿主模式，插件以 `descriptor.json` 声明元数据、权限、apiVersion 与配置 schema，宿主侧做描述符校验与能力授权。
- **第二阶段**：为降低第三方扩展门槛，增加 JavaScriptCore 沙箱宿主（扩展用 JS 写，宿主提供受限 API）。
- **禁止**：直接 `dlopen` 加载第三方 dylib 到主进程。崩溃与权限都无法隔离。

**后果**：Swift 扩展门槛高但稳；JS 扩展门槛低但要设计 API 面与超时/内存限制。两者共用同一份 descriptor 与配置 schema，宿主实现不同。

---

## ADR-0005：只可参考、不可复制的项目

**状态**：已采纳（2026-09-27）

| 项目 | 原因 | 允许的做法 |
|---|---|---|
| [SuperIsland](https://github.com/shobhit99/SuperIsland) | **仓库无 LICENSE 文件**，默认保留所有权利 | 阅读其 `EXTENSIONS.md` 与目录结构，借鉴"JS 扩展 + 扩展清单 + 电源模式"设计；**代码一行都不能进本项目** |
| [notchi](https://github.com/sk-ruban/notchi) | AGPL-3.0 | 除非全项目接受 AGPL，否则只读思路 |
| 其他无 LICENSE 的仓库 | 同上 | 仅作需求参考 |

**执行要求**：任何引进代码的提交，必须在 `NOTICE` 中登记来源仓库、文件与许可；CI 里保留一次人工检查（见 docs/03 的检查清单）。

---
---

# 第二轮决策（协议设计与功能勘察期间）

以下五条来自 2026-09-27 的协议详细设计与功能勘察，字段级内容见 [06](06-module-protocol.md) / [07](07-config-and-events.md) / [08](08-p0-checklist.md)，功能与机制见 [09](09-features-and-mechanisms.md)。

---

## ADR-0006：模块元数据单一来源，概念分三层

**状态**：已采纳（2026-09-27）

**背景**：ADR-0002 称 Atoll "已有扩展系统：XPC 服务、RPC、描述符校验、授权、Live Activity 与锁屏小组件扩展"。**对基座做了逐文件勘察后，这个措辞高估了插件层**（证据见 [06-module-protocol.md](06-module-protocol.md) §0）：

- 描述符校验**存在**，但校验的是**运行时内容描述符**，不是插件清单。
- `descriptor.json` **不存在**——全仓库无此文件，也没有任何插件包格式、发现机制、安装/卸载。
- `apiVersion` **不存在**，没有任何版本协商。
- 看门狗/崩溃重启 **不存在**（架构文档 §6.4 承诺的 5s 超时在上游无先例）。
- 签名校验 **不存在**；XPC 侧只比对 bundle identifier，RPC 侧 bundle id 由客户端自报。

即：Atoll 给的是**内容推送 API + 授权模型 + 声明式渲染管线**，不是插件宿主。ADR-0002 选 Atoll 的结论**不变**（那三样正是我们最缺的地基，渲染管线尤其值钱），但其前提需要修正。

另外，原架构文档把"描述符"一词混用于三件不同的事，导致协议无法落笔。

**决策**：

1. 概念分三层，各层各有单一真源：
   - **① `ModuleManifest`** —— 静态元数据。内置模块在 Swift 里声明；插件在磁盘上是 `descriptor.json`。两者是**同一份模型**。
   - **② `GourdModule` + `ModuleContext`** —— 运行时协议与依赖注入面。两种模块共用同一协议、同一注册表、同一生命周期。
   - **③ `ContentDescriptor`** —— 声明式内容（"画什么"）。**不重造**，复用上游 `AtollExtensionKit` 的三种类型，只做映射（[06-module-protocol.md](06-module-protocol.md) §9）。
2. 内置模块的 manifest **可导出为 JSON**：设置页、文档、功能清单都从同一份数据生成。
3. 字段级规范以 [06-module-protocol.md](06-module-protocol.md) 为准（manifest 字段表、ConfigSchema 词汇、权限白名单、apiVersion 策略、19 个校验错误码）。

**后果**：

- **P4 的工量比路线图字面更大**：插件包格式、发现、安装卸载、签名校验、apiVersion 协商、看门狗——上游**全部为空**，要从零建。
- 因此 **P1 必须先落 `ModuleManifest` 类型**，否则 P4 会被迫改两次协议。
- 上游那三样仍被复用：授权模型（`ExtensionAuthorizationEntry`）、XPC/RPC 骨架、声明式渲染管线。
- 与上游的"兼容读取"要求（[04-upstreams.md](04-upstreams.md) §3.3）落点在 ③，映射表在 [06](06-module-protocol.md) §9.1。

---

## ADR-0007：插件只产出声明式内容，不在宿主进程执行

**状态**：已采纳（2026-09-27）

**背景**：ADR-0004 已禁止 `dlopen` 第三方 dylib。但"进程外"带来的直接问题是：跨进程无法传 SwiftUI 视图，插件若想上屏必须有别的表达方式。上游的三种内容描述符证明了**声明式表达足以覆盖刘海内的主要形态**（刘海内 live activity / 锁屏 widget / notch tab），包括文本、图标、进度、图表、仪表、Lottie 动画、受限 WebView。

**决策**：

- 插件（`kind = js` / `kind = xpc`）**只能**返回 `ContentDescriptor`；返回 `.view` 被宿主硬拒绝（降级为 `.unavailable` 并记 violation）。
- 内置模块（`kind = builtin`）可返回 SwiftUI 视图，也可返回描述符。
- 两者由同一个 `ModuleContent` 枚举承载，渲染**一律在宿主进程内**完成。

**后果**：

- 插件的表达力有**明确天花板**：受描述符字段集约束，做不了任意自定义视图。这是刻意接受的取舍（换进程隔离 + 复用上游渲染 + 插件崩溃不影响界面）。
- 新增表现形态 = 扩 `ContentDescriptor` 契约，受 `apiVersion` 管理（minor 只增不改）。
- 插件运行时与进程模型**正交**：无论最终选 XPC 还是 stdio 子进程（[06](06-module-protocol.md) §11 D-1），manifest 与内容协议都不变。

---

## ADR-0008：P0 冻结扩展通道的线协议名，只改 App 身份

**状态**：已采纳（2026-09-27）

**背景**：扩展通道里有一批"名字"构成线协议身份：XPC mach service 名 `com.ebullioscopic.Atoll.xpc`、3 个分布式通知名、RPC 端口 9020、`AtollExtensions` 落盘目录、12 个 Defaults 键、Keychain service 名。且上游 kit 把 `com.ebullioscopic.Atoll.xpc` 与宿主 bundle id **硬编码在外部包里**，我们改不动它（除非 fork）。

**决策**：P0 只改 **App 自身身份**（bundle id 前缀、`PRODUCT_NAME`、`CFBundleDisplayName`、图标、Sparkle 配置、日志 subsystem）；**扩展通道的名字全部冻结**，留给 P4 一次性重写该层（P4 本来就要补插件包格式与 apiVersion，那时改动是同一个原子操作）。

**强制项（不在"冻结"范围，P0 必须改）**：Sparkle 的 `SUFeedURL` + `SUPublicEDKey` + `SUEnable*Service`。上游 feed 与公钥组合会让 Sparkle 把 **Atoll 的更新包安装到壶中天（Gourd）上**（签名校验会用上游公钥通过）。不处理即有安全后果。

**后果**：

- P0 期间扩展通道与上游保持可互读（满足 [04-upstreams.md](04-upstreams.md) §3.3）。
- 改 bundle id 后，**依赖上游 kit 的第三方 App 连不上壶中天**（它们找的是 `com.ebullioscopic.Atoll`）。已记录并接受，见 [06](06-module-protocol.md) §9.3。
- 改 bundle id 会让 UserDefaults 域改变，上游既有设置不再继承（仍在旧 plist 里，可 P1 做白名单迁移，见 [08](08-p0-checklist.md) D-10）。

---

## ADR-0009：P0 基线锁 `v2.3.3-beta.3`

**状态**：已采纳（2026-09-27）

**背景**：实测漂移数据（2026-09-27）：

| 候选 | commit | 日期 | 相对 dev HEAD | 扩展子系统 |
|---|---|---|---|---|
| `v2.3.3` | `e21cdf7` | 2026-07-24 | 211 文件 / +59425 −16355 | 落后（RPC server 差 182 行） |
| `v2.3.3-beta.3` | `c7305ec` | 2026-08-20 | 155 文件 / +44051 −21595 | **与 dev HEAD 一致** |
| `dev` HEAD | `ad6834e` | 2026-09-27 | — | — |

`Package.resolved` 在 `v2.3.3-beta.3 → dev HEAD` 之间**零差异**（依赖面稳定）。

**决策**：基线 = `v2.3.3-beta.3`（`c7305ec`）。理由：① 扩展子系统与 dev HEAD 字节级一致，勘察结论可直接用；② 避开 `v2.3.3` 的 RPC 层差异；③ 用已发布 tag 而非未发布的开发分支。

**后果**：

- 基线版本号带 `-beta`，需接受上游 prerelease 品质（[02-roadmap.md](02-roadmap.md) 已把"接受 alpha/beta 品质"列为 ADR-0002 的后果）。
- 上游 5 周漂移 155 文件，任何基线都会迅速落后——所以真正要紧的是**同步机制与接触面积控制**（[08-p0-checklist.md](08-p0-checklist.md) P0-7 的接触白名单），而不是起点新旧。
- 后续同步策略修正：Atoll 的默认分支是 **`dev` 而非 `main`**，[04-upstreams.md](04-upstreams.md) 里 `git merge upstream/main` 的写法已修正为 `upstream/dev`。

---

## ADR-0010：功能策略——接管上游优先，私有 API 收敛而非清零

**状态**：已采纳（2026-09-27）

**背景**：对基线做功能勘察后发现两件与既有文档假设不符的事（明细见 [09-features-and-mechanisms.md](09-features-and-mechanisms.md)）：

1. **上游已实现约 40 个用户可见功能**（约 11.7 万行 Swift）。[01](01-architecture.md) / [02](02-roadmap.md) 把 stats、日历、Shelf、计时器、剪贴板、媒体、歌词、天气等列为"P2 待做"，实际它们已经存在于基座里。
2. **上游深度依赖非常规手段**：10 项私有 API / 私有框架（`MediaRemote`、`CoreBrightness`、`DisplayServices`、`IOReport`、CGS 私有函数、SkyLight、私有 plist 与私有通知），22 处外部子进程（`perl`、`log stream`、`launchctl`、`killall -STOP`、`system_profiler`…）。其中若干是脆弱实现——最典型的是 1288 行的系统 Clock 计时器镜像（私有 plist + 私有日志解析 + AXUIElement 控制三重依赖）。

**决策**：

1. **P2 主体是接管与包装上游已有功能，不是重写**。只有上游完全没有的才自建：Launcher、农历、番茄钟、逐字歌词 + 简繁转换、AI agent 状态面板。
2. **私有 API 收敛而非清零**：保留媒体与亮度（价值高、可设计降级路径），砍掉边缘项（IOReport 的 CPU 频率、系统 Clock 镜像、蓝牙耳机电量）。**每处私有 API 都要有失效降级路径与台账**——架构 §9 原本只要求"记录用途"，现升级为"台账 + 降级实现"。
3. **脆弱实现不带进 fork**：系统 Clock 计时器镜像明确不带（即使代码留着也不接线）。
4. **与定位无关的功能建议砍**，但第一批**只真删 3 个最贵的**（全屏视频壁纸 ~1800 行、系统计时器镜像 ~1300 行、蓝牙耳机管理 ~2900 行，合计约 6000 行），其余"留着默认关闭"，观察一个季度再定。**〔已被 ADR-0011 推翻：最终决定一项都不删，改为"默认不启用"〕**
5. 上游功能收敛范围、播放器 source 默认范围、锁屏面板去留等具体取舍列为待拍板（[09](09-features-and-mechanisms.md) §8）〔后续由 ADR-0011 / ADR-0012 全部拍板〕。

**后果**：

- **工作量重估**：P2 拆成 **P2a 接管（2 周）+ P2b 自建（2～3 周）**。接管比"重写"便宜，但上游耦合度比预期高。
- **耦合现实**：`MusicManager` 2341 行、`SettingsView` 9696 行单文件、`BluetoothAudioManager` 2949 行——不是能干净切开的模块。**P3 之前接受 `SettingsView` 保持原样**，否则 P1 会被无穷无尽的界面重构拖死。
- **"真删"与"默认关闭"的成本不同**：真删让代码库干净，但每次季度同步要重删（靠 [08](08-p0-checklist.md) P0-7 的接触白名单机制管理）；默认关闭零冲突，但保留权限面与误开风险。依据已记录，将来改主意不必重新论证。
- 媒体 source 默认只开"系统 Now Playing"（覆盖面最广、机制统一），其余按需开启——7 个 source 机制各异，单人维护不可能全保。

---

## ADR-0011：范围冻结——不删除上游功能（第 2 条已被 ADR-0012 修订）

**状态**：已采纳（2026-09-27，已修订）。**注意**：本 ADR 第 2 条（"上游没有的一律不实现"）**已被 ADR-0012（见本文末）反向修订**——改为"按需新增"6 项功能。其余条款（第 1 条不删除、第 3 条播放器单一源、第 4 条锁屏维持现状、第 5 条不投入的上游功能保留原样）**继续有效**。

**修订记录**：本 ADR 于 2026-09-27 当天被修订一次。初版第 3 条决定**删除 6 项**上游功能（全屏视频壁纸、系统 Clock 计时器镜像、蓝牙耳机管理、AI 对话、AI 用量面板、内嵌终端，约 8000 行）；修订后改为**一项都不删**，理由见下。修订依据："开源项目就有的功能不用删除，维持现状就可以，避免删除导致更大的工作量。"

**背景**：ADR-0010 决定"接管上游优先"，但对"上游没有的功能要不要自建"与"要不要砍功能"留了待拍板项。评审结论是**两头都收**：不新增、也不删除。这个项目的价值在可定制性与架构（模块化、插件），不在于功能数量；上游已有的 40 个功能足够日常使用。

> 与 ADR-0010 的关系：本 ADR **收窄**其第 1、4、5 条（自建范围、删除力度、待拍板项），**不推翻**其第 2、3 条（私有 API 处理策略、脆弱实现不带进 fork 的取向）。私有 API 台账与降级路径的要求继续有效——按本 ADR 第 1 条，上游的私有 API 实现全部保留。

**决策**：

1. **上游有的，全部保留、维持现状**——**不做任何删除**，不主动删减上游功能、不为它们重写实现。
2. **上游没有的，不实现**。取消全部自建计划：Launcher、农历、番茄钟、逐字歌词 + 简繁转换、AI agent 状态面板、照片浏览。
3. **不需要的功能用"不投入"表达，而不是删除**。AI 对话、AI 用量面板、内嵌终端、全屏视频壁纸、系统计时器镜像、蓝牙耳机管理这 6 项：代码保留，但**不进 P2 接管清单、不做维护承诺、默认不启用**。
4. **媒体数据源只用系统 Now Playing** 一路；其余 6 个播放器适配器保留代码、默认不启用、不纳入维护与验收。
5. **锁屏维持现状**：面板集合与布局完全不变。

**为什么"不删"优于"删"**：删除要付出三笔成本——① 清理接线（牵动 9696 行的 `SettingsView`、锁屏两个入口、菜单与热键）② 每次季度同步上游都要按清单重删一遍，是长期负担 ③ 删错会引入新 bug（例如锁屏那两个入口是活的交互路径）。而保留的成本只是"代码在场"，且同步零冲突。**用户侧的效果用"默认不启用"即可达成，工程成本接近于零。**

**后果**：

- **P2 只剩"接管 + 模块化"**：自建整段取消、删除整段取消，工作量降为约 **2 周**（另含三处已知缺陷修复：歌词磁盘缓存、计时器持久化 + 通知、剪贴板电源优化）。
- **本项目的差异化定位**为：可定制性、模块化边界、插件架构（而非功能数量）。**功能面等于上游 Atoll**。
- **M2 里程碑（"我已经不用 Nook X 了"）需要实测重新评估**：Nook X 独有的 7 项能力我们都没有（其中农历与"日/周/月/年进度"是纯本地计算、补回成本不到 100 行）。处置建议：先做减法，等 P2 接管完成后连续用一周，让实际使用暴露真实缺口，而不是现在猜。详见 [09](09-features-and-mechanisms.md) §8 与 §4.2。
- **锁屏不再受影响**（删除取消后，此前的两处牵连——锁屏天气的蓝牙电量、锁屏音乐面板的全屏按钮——自动消失）。已核实的牵连信息留档在 [09](09-features-and-mechanisms.md) §4.1，将来若要改主意不必重查。
- **私有 API 面保持 10 项、外部子进程保持约 22 处**：无法通过删除来收敛，只能靠"台账 + 降级路径"管理（[01-architecture.md](01-architecture.md) §9）。
- 仍有 1 项待定（ATS 是否收窄）与 1 项硬前置（Bundle ID 前缀），见 [09](09-features-and-mechanisms.md) §8.2 与 §8.3。

---

## ADR-0012：按需新增功能（含通知上岛与终端外部化）

**状态**：已采纳（2026-09-27）

**修订记录**：本 ADR 反向修订 ADR-0011 的第 2 条（"上游没有的一律不实现"）。ADR-0011 的第 1、3、4、5 条继续有效——**上游功能仍然全部保留、一项不删**。

**背景**：ADR-0011 冻结范围后重新审视，确认有 6 项功能对日常使用是必需的，而上游恰好没有（或不够用）。同时"基于 Atoll 实现"本身就意味着上游功能天然保留，不必也不该为了"净化"去删。

**决策**：新增以下 6 项，**全部做成独立模块**（[06](06-module-protocol.md) 协议下的 manifest + config schema + 事件），**不改上游文件**：

| # | 功能 | 机制要点 | 私有 API |
|---|---|---|---|
| 1 | **快捷启动 `launcher`** | 扫描 App 目录 + `NSWorkspace.openApplication` + 自建使用频次（不读 `.sfl3` 私有格式） | 无 |
| 2 | **农历 `lunar`** | Foundation `Calendar(identifier: .chinese)`（含闰月/干支）+ 预置节气表；不做黄历宜忌 | 无 |
| 3 | **进度 `progress`** | `Calendar.dateInterval(of:for:)` 算日/周/月/季/年进度；不手算天数 | 无 |
| 4 | **Shortcuts 上岛 `shortcuts`** | `/usr/bin/shortcuts list --show-identifiers` 枚举（已实测）+ `shortcuts run` 执行（已实测支持输入输出）；可与 Shelf 文件联动 | 无 |
| 5 | **通知上岛 `notifications`** | 只读通知中心 SQLite（`group.com.apple.usernoted/db2/db`，已实测容器在 macOS 27 仍在）→ 点击用 bundle id 打开对应 App；降级方案为 AX | **有**（私有数据格式） |
| 6 | **终端走外部 App `terminal`** | **`mode` 默认 `external`**，唤起已安装的 Ghostty（已实测装在 `/Applications/Ghostty.app`）；内嵌 SwiftTerm 代码保留但不作为目标形态。**优先级最低，放最后做** | 无 |

**能力边界（通知上岛，已确认接受）**：**只需"能显示通知、能点击打开 App"即可**，不要求关闭/回复操作真实通知；需要**完全磁盘访问**；依赖私有 schema；默认不在浮层显示正文。**先做可行性探针**（0.5 天）验证 macOS 27 上可读，再投入完整实现。

**一处事实澄清**：上游 Atoll 的 AI 对话（屏幕助手）**确实存在**（`ScreenAssistantManager`，5 家 provider、支持图片/文件/录音/截图、热键 `⌘⇧A`），但入口是**独立悬浮面板、不在刘海 tab 里**（`NotchViews` 无 AI 项），所以从界面看容易以为没有这个功能。按 P5"不投入"处理：上游已有 `enableScreenAssistant` 开关（默认 `true`），我们在首启写入 `false`——**不改上游源码**。

**后果**：

- **范围从"只接管"扩为"接管 + 6 项新增"**：P2 拆为 **P2a 接管（2 周）+ P2b 新增（1.5～2 周）+ P2c 通知（1 周）**。
- **新增部分几乎不增加私有 API 面**：6 项里 5 项零私有 API，只有通知引入新的私有数据依赖——这是刻意的（私有 API 面越薄，随 macOS 升级越省事）。
- **季度同步零冲突**：新增功能全部落在新目录（`DynamicIsland/Modules/`），不修改上游文件；这也兑现了 [08](08-p0-checklist.md) P0-7 的接触白名单原则。
- **通知上岛是本轮最大不确定性**：探针不通过则转 AX 方案或推迟到 P3，不影响其它功能。
- 仍不做的缩减为 3 项：照片浏览、番茄钟、AI agent 状态面板；逐字歌词 + 简繁转换不在本轮（若用起来觉得缺再单独提）。
- 新增功能的详细设计（数据源/关键 API/配置项/权限/降级/工作量）见 [09](09-features-and-mechanisms.md) §5。
- **待你选定的唯一硬前置**：Bundle ID 前缀（反写域名）。说明与同生态实例见 [09](09-features-and-mechanisms.md) §8.3——**已定：`com.cmeng.gourd`**（Debug 加 `.dev`）。它同时决定模块 id 的保留前缀，需一并定。

---

## ADR-0013：不付费公证——安装摩擦由「说明写准 + 命令行安装」承担

**状态**：已采纳（2026-10-08）

**背景**：项目面向所有人开源分发，但签名路线是自签证书 `Gourd Local` + 不公证、不付费 Apple 开发者计划。对**已发布的 v0.1.0** 逐项实测（2026-10-08）：

| 核验项 | 结果 |
|---|---|
| DMG 自身 | `code object is not signed at all`；无公证票据；`spctl` 判 rejected |
| 应用签名 | `Authority=Gourd Local`、`TeamIdentifier=not set`——自签，非 Apple 签发的 Developer ID |
| 签名完整性 | `codesign --verify --deep --strict` 通过（所以别人看到的是「无法验证开发者」，不是「已损坏」） |
| Apple 自带发布前检查 | `syspolicy_check distribution` 报 **Fatal：Notary Ticket Missing** |
| 本机为何「没问题」 | 钥匙串用户域把 `Gourd Local` 标了「代码签名」信任（`dump-trust-settings` 里的 Cert 6）——**这条信任只在开发机上有**，别人的机器没有 |
| Gatekeeper 何时拦 | 只在包带 `com.apple.quarantine` 隔离标记时拦。`curl` 落盘不带该标记（实测只有 `com.apple.provenance`）；Homebrew cask **反而会主动打上**（源码 `Quarantining ...`，来源写 "Homebrew Cask"），所以 brew 救不了 |

另外发现 `com.apple.security.get-task-allow = true` 被注入进了出厂包（Xcode 的 base entitlements），而它是 Apple 公证的硬性拒收项。

**决策**：**不付费**。安装摩擦由两件事承担，两者都零成本：

1. **DMG 路径**：安装说明写准放行步骤——双击被拦 →**系统设置 → 隐私与安全性 → 仍要打开**；删掉「右键 → 打开」。
2. **命令行安装**（[install.sh](../install.sh)）：`curl` 取包（不带隔离标记）→ 校验 `SHA256SUMS` → 装进「应用程序」。这条路首启无任何提示。

配套的三件必做：

- 出厂包**去掉 `get-task-allow`**（Release 配 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`）；它同时是将来公证的前置条件。
- `tools/build.sh --dmg` 加**发布门禁**：必须用稳定身份签（无身份时拒绝出包，不再静默退 ad-hoc）+ 出厂前 `codesign --verify --deep --strict` 自校验（查嵌套代码——本机没隔离标记，嵌套签名坏了照样能跑，本地试不出来）。
- **`Gourd Local` 私钥离线备份**：签名身份一换，全体用户的 TCC 授权与登录项整体重置；它现在是「全员权限不重置」的锚点。

发布流程据此成文：[docs/33-release-process.md](33-release-process.md)。

**后果**：

- **「下载双击就开」做不到**；零成本的上限是「拦一次 + 说明清楚」或「走命令行无提示」。已如实写进 README、用户手册与 Release 正文。
- **别指望免费公证**：Apple 的费用豁免只面向非营利 / 教育 / 政府机构，个人开源项目不在内。
- 将来若付 $99/年，路线是：Developer ID 重签（含内嵌 framework / helper / XPC）→ `notarytool` 公证 → `stapler staple`；届时**新增一条 ADR 修订本条目**，不要改这里。要注意换签名身份会让现有用户的授权重算一次。
- 应用只出 **arm64**，Intel 机器不支持——已在安装说明与 `install.sh` 前置检查里挡掉。

---

## ADR-0014：恢复备忘录面板（推翻 T5 的「删页留码」与收尾的「摘 tab」）

**状态**：已采纳（2026-10-08）

**背景**：2026-09-30 曾把上游的苹果备忘录功能从产品面摘掉，理由是「入口自举不算入口」——`enableNotes` 默认关、模块清单里没有它、首页块与热键都没有它，唯一入口就是设置里**笔记页自己那个开关**（`docs/26` D-06 + `docs/09` 判定表）。收尾修复（`ad1c55b1`）又把 `TabSelectionView` 那条合并分支改成只看剪贴板、label 固定为 Clipboard，起因是摘页之后「`enableNotes` 置 1 的用户会看到一个无处可关的 tab」。

用户于 2026-10-08 明确要求「备忘录面板要有」，并指出当时的判定留下了矛盾：`NotchNotesView` 仍在读 `enableNotes`，而剪贴板那条 tab 的 `view` 仍是 `.notes`——**键并没有真的惰性**，只要把剪贴板模式切到 `.separateTab`，那条标着「剪贴板」的 tab 就会画出备忘录内容（`enableNotes` 为真时甚至是双栏）。判定表里「键惰性」那句话与代码不符。

**决策**：恢复备忘录面板，四处一起改（缺一处就回到「无处可关」或「关不掉」的中间态）：

| # | 位置 | 改动 |
|---|---|---|
| 1 | `SettingsView.availableTabs` | 把 `.notes` 加回数组（笔记页与它的开关随之复活） |
| 2 | `TabSelectionView` | 合并分支的条件与 label / icon 恢复成上游的两来源语义：`enableNotes` 或（剪贴板 + `.separateTab`）；label 在笔记开着时为 Notes |
| 3 | `matters.swift` 的 `enabledStandardTabCount()` | 与 ② **逐字同条件**（有一条用例在比这一致性） |
| 4 | `DynamicIslandViewCoordinator` | `.notes` 与 `.clipboard` 共用视图，门槛从「剪贴板键」改成**复合**条件：两个键都关着才收回；`hostSurfaceOffKeyNames` 随之把 `enableNotes` 一并报进来（否则那个复合条件恒为假） |

**后果**：

- 备忘录与剪贴板是**同一条 tab 的两半**（上游原设计）：都开时是「左剪贴板 + 分隔线 + 右笔记」，只开笔记是纯笔记，只开剪贴板是纯剪贴板。不是两条并列的 tab。
- `enableNotes` 从「惰性」恢复为**真开关**；设置 → 笔记页是它的入口。
- 三条钉住旧行为的用例同步改写（不是为了让它们变绿，是把断言换成新语义）：`views` 数组那条、宿主门槛纯函数那条（改成三档：只关剪贴板 / 只关笔记 / 两者都关），以及端到端那条（补一条「只开笔记 → `.notes` 选得上」）。
- **与备忘录内容有关的边界**：备忘录正文是用户数据，只走 `~/Library/Preferences` 与苹果备忘录本身，**不进安装包、不进仓库**——`AppleNotesSyncManager` 同步的是运行期数据。恢复功能不改变这一点（发布前已核：出厂包与全部仓库历史里都搜不到备忘录条目标识）。
- [26](26-home-widgets-and-settings.md) 里的 D-06 与 [09](09-features-and-mechanisms.md) 判定表**保留原文**（那是当时的记录），本条是推翻它们的新记录。

---

## ADR-0015：自适应面板高度 = 账本槽位恒为「这一页的自然内容高」，撤销「光标在面板内不缩」

**状态**：已采纳（2026-10-08）

**背景**：用户反馈「不同面板切换的时候，自适应高度有卡顿……启动台回到首页，高度就不对，自适应要丝滑才行」，附截图：首页内容画在顶部、面板底部空一大片。

诊断构建（`GOURD_HEIGHT_LOG=1`，日志与取证见 `.workflow/p8-height-smooth/evidence/`）把链路读了出来：

```
selectTab tab=home  activeTab(before)=launcher  homeSlot=810.0      ← 首页槽位已经是「启动台的面板高 − 40」
homeSeam  natural=516.0  seed=850.0  converged=556.0  held=850.0  written=810.0
tabSwitchResize size=887.0x868.0   resizeWindow→noop h=872.0        ← 面板一步不退
```

两个原因叠在一起，都长在「光标在面板内时不缩」（p5-home-blocks 的边界 ① / [29](29-home-blocks-and-panel.md) D-40 · D-41 / `report` 原条款 ④）这条规则上：

1. **它把「面板此刻多高」写进了「这一页的内容高」这个槽**。首页那一路的落点是 `heldForPointer`：光标在面板里就写 `max(收敛值, 当前面板高) − 内边距`。而面板高在切页过渡里可能是**别的页**的高——上例就是「首页 → 启动台」的过渡里旧首页又跑了一次 body，把启动台的面板高（850）写进了首页槽（810 = 850 − 40）。切回首页时 `selectTab` 照读，面板自然一步不退。
2. **它拦在它「起作用」的地方，而拦下之后没有解**。判据 `vm.isMouseHovering()` 其实是**面板 rect 里的指针**（`notchSize` 在展开态就是面板尺寸）——点 tab 的那只手必然在里面，所以「切到矮页」被拦；账本只记「不缩」，实现里又**没有 hover 触发的重算**（[29](29-home-blocks-and-panel.md) §已知限制 1 自己写明「移开鼠标下一次重算就贴合**不成立**」）。于是错误的高度一直留着，直到别的什么事件把它重排一次。

**决策**：**账本槽位是「这一页的自然内容高」，不含「面板此刻多高」的任何成分**；面板高 = 槽位 + 宿主内边距，无状态、可反复读。四处一起改：

| # | 位置 | 改动 |
|---|---|---|
| 1 | `PanelAutoHeight` | 删除 `heldForPointer`（唯一读「当前面板高」的那条规则） |
| 2 | `PanelContentHeight.report` | 删除原条款 ④（「同一 tab 且光标在面板内只接受变大」）与 `pointerInsidePanel` 注入；`DynamicIslandApp` / `NotchHomeView` / `HomeBandedHomeView` 的接线一并撤掉 |
| 3 | `HomeBandedHomeView` 接缝 | 只写**收敛后的内容高**（`convergedPanelHeight − homeVerticalPadding`），不再经过指针规则 |
| 4 | `PanelContentHeight.setHomeContentHeight` | 值真的变了、且首页当班时响一声 `objectWillChange` → 走**既有**的 resize 链；**切页后的第一份写入**（`awaitsFirstHomeWrite`）走立即链（免防抖），与模块页的 `awaitsFirstReport` 同形 |

**后果**：

- **切页单步到位**（上屏实测窗口高轨迹：启动台 872 → 首页 578，一条 244ms 的缓动、无中途台阶）；启动台 / 日历 / 待办 / 架子 / 终端 / 笔记六页往返，每次都精确回到首页的 578。
- **同一页内容变了也跟手**（音乐块进出 / 翻月 / 块开关）：旧写法下首页的写入**刻意不发通知**，靠「五条 publisher + 打开面板后一拍」兜——它们都不覆盖「内容自然变化」这一档，面板会停在旧高度；今天走防抖链补上。
- **重开面板读到的就是真值**：槽位不再被污染，「打开面板先按手动高度站着再贴合」只剩**进程启动后的第一次展开**（账本在内存里、刚起时为空），[29](29-home-blocks-and-panel.md) §已知限制 4 的形态因此收窄。
- **代价（如实记）**：面板会在指针停在**内容区**时随内容变矮而收缩。这件事的另一半——「不把面板从光标底下抽走」——由 `ContentView.shouldHonorHoverExit`（p6 的 D-21）在**关面板**那一侧兜着：面板缩走不会被读成「指针离开」，所以最坏也只是面板变矮，不会塌回折叠态。
- 推翻的旧记录（原文保留、就地加改判）：[29](29-home-blocks-and-panel.md) §做法 机制六 边界 ① / §已知限制 1 / A9 / D-12 / D-40 / D-41，[30](30-ui-polish-and-shelf.md) §已知限制 8。两条钉旧规则的单测按新语义改写（删 `heldForPointer` 那组、把条款 ④ 那组换成「收缩照常接受」），并新增「首页写入的通知规则」一条。
