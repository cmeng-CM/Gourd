# 壶中天 · Gourd

> **自用 + 开源**的 macOS **刘海工作台**：把屏幕顶部那一小块（刘海 / 刘海位）做成命令面板——媒体、日历、系统状态、文件暂存、待办、快捷启动、通知与自建小工具都收在这里，**一切功能皆可开关、可扩展**。
>
> **这是一个修改版本（modified version）**：本项目 fork 自 [Atoll](https://github.com/Ebullioscopic/Atoll)（GPL-3.0），基线 tag `v2.3.3-beta.3`（commit `c7305ec`），自 **2026-09-27** 起由本仓库维护修改；上游版权声明与 GPL-3.0 全文原样保留（见 [LICENSE](LICENSE)、[NOTICE](NOTICE)）。
>
> 「壶中天」取意壶中天地——一个小容器里装下一整块工作台；屏幕顶部那个小口展开，就是你的全部工具。

## 与 Atoll 的关系

- **代码来路**：应用工程 fork 自 [Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll)（GPL-3.0），基线锁定 tag **`v2.3.3-beta.3`**（commit `c7305ec`）；上游完整历史保留在 `main`，季度同步走原生 `git merge`。
- **改了哪些**：改名与重打包（产品名 **壶中天 / Gourd**、Bundle ID `com.cmeng.gourd`；本地产物 `dist/壶中天-<版本>.dmg`，Release 附件用 ASCII 名 `Gourd-<版本>.dmg`）；版本号改为自有序列（本版本 **0.1.0**）；加模块化内核与自建模块（启动台 / 农历 / 工作日统计 / 待办 / 快捷指令 / 通知 / 前台应用）；设置重新分组、界面中文化、默认值收敛。**上游功能一个未删**——不需要的用「默认关」表达。
- **改的时间**：首次修改 **2026-09-27**，后续改动见 git 历史与 [CHANGELOG.md](CHANGELOG.md) 顶部的自有变更段。
- **与上游的关系**：`Atoll` 仅用于指明代码来源。**本项目与 Atoll 项目及其维护者无隶属关系，也未获其背书**（nominative use；见 [TRADEMARKS](TRADEMARKS)）。

## 功能

- **首页工作台**：一条可换行的块流——音乐、镜子、前台应用、待办、通知、工作日统计、CPU / 内存 / GPU 三环各占一块；块窄了**换行**而不是消失，只有连一行都放不下才从尾部丢块并在条尾给 `＋N`。
- **整宽日历行**：左整月网格（含**农历**与订阅的**节假日**）+ 右当天清单。
- **展开面板**：顶部 tab 栏 + 各功能页（主页 / 文件暂存 / 终端 / 待办 / 通知 / 日历 / 启动台 / 计时器…），tab 由模块注册表投影产出，右侧是剪贴板 / 取色 / 计时器 / 设置等固定按钮。
- **媒体**：正在播放的曲目、进度与控制（可自定义按钮排布），音乐上岛、快速预览、侧边歌词（可关），锁屏媒体面板与全屏封面。
- **系统指标与 HUD**：CPU / 内存 / GPU / 网络 / 磁盘等指标；音量、亮度、键盘背光、电池的提示可在四种形态里选（灵动岛 / 自定义 OSD / 垂直条 / 圆形），第三方 DDC App（BetterDisplay / Lunar）也能接进来。
- **效率工具**：剪贴板历史与固定片段、计时器（含预设与系统时钟同步）、日历与提醒、待办（写回系统「提醒事项」）、暂存器（拖文件进岛，隔空投送 / 快速共享）。
- **自建模块**：启动台（可搜索、可固定的应用网格）、**工作日统计**（工作时间进度 + 本周 / 本月剩余工作日，按系统日历里的节假日与调休算）、系统「快捷指令」上岛、通知上岛、前台应用块。
- **组件页**：一个模块一张卡——默认开 / 关、**开了会在哪看到什么**、能拨的配置直接拨；改不了的键明确标「由上游设置管理」。
- **一切皆开关**：每个功能可独立开关、独立配置（模块协议见 [docs/06](docs/06-module-protocol.md)）。

## 安装

**方式一 · DMG**（推荐）：到 [Releases](../../releases) 下载 `Gourd-0.1.0.dmg`，打开后把「壶中天」拖进「应用程序」。第一次打开若被 Gatekeeper 拦下，右键 → **打开**。

**方式二 · 自己构建**（需要 Xcode；全程本机完成，不依赖 GitHub）：

```bash
sh tools/build.sh --install     # 构建并装到 /Applications/壶中天.app
sh tools/build.sh --dmg         # 或在 dist/ 产出 Gourd-0.1.0.dmg
```

应用是**菜单栏小工具**（没有 Dock 图标）：启动后看屏幕顶部（刘海 / 刘海位），鼠标悬停即展开。

## 文档

| 文档 | 给谁看 |
|---|---|
| **[用户手册 docs/guide/](docs/guide/README.md)** | **使用者**：安装、权限、界面速览、组件页、快捷键、常见问题、更新与卸载 |
| [用户手册 · 设置参考](docs/guide/settings.md) | **每一项设置**是什么、默认值、互斥与灰显条件（逐页列举） |
| [用户手册 · 组件页与各模块](docs/guide/modules.md) | 总控台怎么用；每个模块默认开不开、出现在哪、能配什么 |
| [用户手册 · 快捷键](docs/guide/shortcuts.md) / [常见问题](docs/guide/faq.md) | 默认键一览；装好之后最容易遇到的坑 |
| [开发文档 docs/00~32](docs/00-decisions.md) | **贡献者 / 未来的自己**：ADR、架构、模块协议、各批次的设计记录与已知限制（不是给使用者看的） |
| [发布自检清单 docs/25](docs/25-release-smoke.md) | 打开发包前跑一遍（给发布者） |

## 常见问题（选摘）

- **功能开了却没反应？** 组件页每张卡片都写着「开了会在哪看到什么」；标了「由上游设置管理（改了不生效）」的项，真源在设置里的另一页（卡片上的开关与它是同一个）。
- **面板窄的时候首页块少了几块？** 块会换行；只有连一行都放不下才从尾部丢，条尾 `＋N` 就是「还有几块没显示」——拉宽面板即可。
- **通知块显示「不可读」？** 缺**完全磁盘访问**（系统设置 → 隐私与安全性）；给不给都行，不给就降级显示，不会崩。
- **为什么要摄像头 / 完全磁盘访问这类权限？** 功能都是**本地实现**的（媒体走系统框架与子进程、通知读本机通知库、镜子直开摄像头）；**本项目不新增任何出站请求、不上传数据**。
- 更多见 [用户手册 · 常见问题](docs/guide/faq.md)。

## 贡献

- 提 issue / PR 都欢迎；提交信息请写清「改了什么、为什么、怎么验证的」。
- 动代码前先看 [docs/00-decisions.md](docs/00-decisions.md)（12 条 ADR）与 [docs/01-architecture.md](docs/01-architecture.md)；模块相关改动读 [docs/06-module-protocol.md](docs/06-module-protocol.md) 与 [docs/07-config-and-events.md](docs/07-config-and-events.md)。
- 本地门禁：`xcodebuild test … -only-testing:DynamicIslandTests` 全绿 + `sh tools/build.sh` 能出包。

## 归属与致谢

- **上游基座**：[Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll)（GPL-3.0）——应用工程 fork 自它，其内嵌的 boring.notch 署名原样保留。
- **组件与参考**：[boring.notch](https://github.com/TheBoredTeam/boring.notch)（GPL-3.0）、[exelban/stats](https://github.com/exelban/stats)（MIT）、[MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter)（BSD-3-Clause）、[NotchDrop](https://github.com/Lakr233/NotchDrop)（MIT）等，完整清单在 [NOTICE](NOTICE) 与 [docs/03](docs/03-license-matrix.md)。

## 许可

**GPL-3.0-or-later**（沿用上游）。完整文本见 [LICENSE](LICENSE)；修改说明见本文档「与 Atoll 的关系」与 [CHANGELOG.md](CHANGELOG.md)。
