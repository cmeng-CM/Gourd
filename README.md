# 壶中天 · Gourd — 可定制的 macOS 灵动岛工作台

> 自用 + 开源。以刘海（notch）为命令面板，把媒体、歌词、系统状态、文件暂存、快捷启动、快捷控制、AI 协作都收进屏幕顶部那一小块地方，并且**一切功能皆可开关、可扩展、可替换**。
>
>
> **名字取意：壶中天（壶中天地）**——一个小容器里装下一整个天地；屏幕顶部那个小口展开，就是你的整块工作台。
> 典出《后汉书·方术传》费长房入壶，壶中有玉堂严丽；李白"壶中别有日月天"、王维"坐知千里外，跳向一壶中"。
> 而"壶"在中国神话里本就是海上仙山之一（《列子·汤问》渤海之东五山：岱舆、员峤、**方壶**、瀛洲、蓬莱）——与代码基座 [Atoll](https://github.com/Ebullioscopic/Atoll)（环礁）同属海洋意象。
> 英文名 **Gourd**（取"壶"之意）；Bundle ID `com.cmeng.gourd`。

## 一句话现状

**当前只有设计与清单，没有应用代码。** 上游仓库已拉取到 `/Users/cm/workspace/github/`，本目录用于后续实现。

## 关键决策（详见 [docs/00-decisions.md](docs/00-decisions.md)）

| 决策 | 结论 |
|---|---|
| 许可证路线 | **GPL-3.0**（自用 + 开源）。因此可自由融合 MIT / Apache-2.0 / MPL-2.0 的代码，代价是**不能上 Mac App Store** |
| 代码基座 | fork **[Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll)**，因为它已有 XPC 扩展架构（boring.notch 的扩展系统还在路线图里未实现） |
| 上游使用方式 | **能当依赖就不 fork**：MIT 项目优先做 SPM 依赖或按目录引进，只有基座是真 fork |
| 插件宿主 | 先做进程外 XPC + JSON 描述符校验；JS 沙箱（JavaScriptCore）作为第二阶段 |
| 参考但**不可复制代码** | [SuperIsland](https://github.com/shobhit99/SuperIsland)（仓库无 LICENSE）、[notchi](https://github.com/sk-ruban/notchi)（AGPL-3.0） |

## 术语

| 词 | 指什么 |
|---|---|
| **上游 / upstream** | 我们 fork 的基座 **Atoll**（`Ebullioscopic/Atoll`），以及将来引进代码的第三方开源项目。文档里"上游有 / 上游没有"都是这个意思，不指任何云服务 |
| **基座** | 被 fork 的应用工程本身（Atoll） |
| **岛 / 刘海面板** | 壶中天自己的浮动面板窗口（折叠态=compact，展开态=expanded，另有 lockscreen 锁屏面） |
| **模块 / module** | 一个可独立开关、独立配置、独立崩溃隔离的功能单元（内置或插件，共用同一份 manifest 模型，见 [docs/06](docs/06-module-protocol.md)） |

## 目录约定

```
~/workspace/github/
├── Atoll/                 ← 基座（fork 源，已拉取，含完整历史）
├── boring.notch/          ← 功能对照实现（GPL，可合并）
├── NotchDrop/ OpenYoink/ DynamicNotchKit/ ...   ← 功能来源（MIT/Apache/MPL）
└── lagoon/                ← 本项目仓库（应用名 壶中天 / Gourd；目录名将在 P0 改为 gourd）
    ├── docs/              ← 决策、架构、路线图、许可证矩阵、功能映射
    ├── scripts/           ← 上游同步与校验脚本
    ├── upstreams.tsv      ← 机器可读的上游清单（用途 + 许可 + 使用方式）
    ├── NOTICE             ← 上游署名（GPL 义务之一）
    └── LICENSE            ← GPL-3.0
```

## 上手

```bash
# 1) 按清单校验上游是否齐全
bash scripts/verify-upstreams.sh

# 2) 拉取缺失的上游 / 更新已有上游
bash scripts/sync-upstreams.sh

# 3) 阅读设计，从 docs/02-roadmap.md 的 P0 开始
```

## 文档索引

| 文档 | 内容 |
|---|---|
| [docs/00-decisions.md](docs/00-decisions.md) | ADR（10 条）：许可证路线、基座选型、依赖策略、插件宿主、禁引清单、元数据分层、插件渲染边界、P0 冻结范围、基线锁定、功能策略 |
| [docs/01-architecture.md](docs/01-architecture.md) | 分层架构、模块协议、插件宿主、配置与主题、数据源、分发 |
| [docs/02-roadmap.md](docs/02-roadmap.md) | P0～P4 阶段任务、验收标准、风险 |
| [docs/03-license-matrix.md](docs/03-license-matrix.md) | 许可证矩阵与合并规则（含禁止清单） |
| [docs/04-upstreams.md](docs/04-upstreams.md) | 上游仓库清单、用途、同步策略 |
| [docs/05-feature-map.md](docs/05-feature-map.md) | Nook X 功能 → 本项目模块 → 代码来源 |
| [docs/06-module-protocol.md](docs/06-module-protocol.md) | **模块协议与描述符（字段级）**：Manifest / GourdModule / 内容描述符三层分离、descriptor.json 全字段表、ConfigSchema 词汇、权限白名单、apiVersion 策略、19 个校验错误码 |
| [docs/07-config-and-events.md](docs/07-config-and-events.md) | **配置模型与事件契约（字段级）**：config.json 结构与迁移链、密钥走 Keychain、事件信封与投递/背压语义、首批 13 个事件的 payload |
| [docs/08-p0-checklist.md](docs/08-p0-checklist.md) | **P0 工程改造清单**：基线冻结、git 结构、改名清单（含刻意冻结项）、依赖治理、CI、合规、上游接触白名单、可执行验收命令 |
| [docs/09-features-and-mechanisms.md](docs/09-features-and-mechanisms.md) | **功能清单与实现机制（范围已定稿）**：40+ 功能的实现机制 × 动作（保留接管 / 保留不投入 / 新增），6 项新增功能的详细设计、私有 API 与子进程代价清单、待讨论项 |

> 上游事实校正（三条）：① Atoll 的默认分支是 `dev` 而非 `main`；其"扩展系统"是**内容推送 API + 授权模型 + 声明式渲染管线**，**没有**插件包格式、descriptor.json、apiVersion 协商与看门狗——这部分要从零自建（[docs/06](docs/06-module-protocol.md) §0 与 ADR-0006）。② **上游已实现了约 40 个用户可见功能**，P2 的主体工作是接管、包装与模块化，而非从零写（[docs/09](docs/09-features-and-mechanisms.md)）。③ **范围已定稿**（ADR-0011 + ADR-0012）：**上游功能一个不删**（不需要的用"默认不启用"表达）；**按需新增 6 项**——快捷启动、农历、日/周/月/季/年进度、系统 Shortcuts 上岛、通知上岛、终端可配置为 Ghostty。新增部分全部做成独立模块，不改上游文件。

## 许可证

本项目以 **GPL-3.0** 分发。分发二进制时必须同时提供完整源码，保留 [NOTICE](NOTICE) 中的上游署名，并标注修改。禁止把本项目代码并入闭源产品（包括上架 App Store 的商业版本）。
