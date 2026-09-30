# 壶中天 · Gourd

> **自用 + 开源**的 macOS **刘海工作台**：把屏幕顶部那一小块（刘海 / 刘海位）做成命令面板——媒体、歌词、系统状态、文件暂存、快捷启动、快捷控制、通知与自建小工具都收在这里，**一切功能皆可开关、可扩展**。
>
> **这是一个修改版本（modified version）**：本项目 fork 自 [Atoll](https://github.com/Ebullioscopic/Atoll)（GPL-3.0），基线 tag `v2.3.3-beta.3`（commit `c7305ec`），自 **2026-09-27** 起由本仓库维护修改；上游版权声明与 GPL-3.0 全文原样保留（见 [LICENSE](LICENSE)、[NOTICE](NOTICE)）。
>
> 「壶中天」取意壶中天地——一个小容器里装下一整块工作台；屏幕顶部那个小口展开，就是你的全部工具。

<p align="center"><img src="docs/guide/assets/01-home-strip.png" width="920"></p>

## 与 Atoll 的关系

- **代码来路**：应用工程 fork 自 [Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll)（GPL-3.0），基线锁定 tag **`v2.3.3-beta.3`**（commit `c7305ec`）；上游完整历史保留在 `main`，季度同步走原生 `git merge`。
- **改了哪些**：改名与重打包（产品名 **壶中天 / Gourd**、Bundle ID `com.cmeng.gourd`、产物 `壶中天-<版本>.dmg`）；版本号改为自有序列（本版本 **0.1.0**）；加模块化内核与自建模块（启动台 / 农历 / 进度 / 待办 / 快捷指令 / 通知 / 前台应用）；默认值收敛与界面中文化。**上游功能一个未删**——不需要的用「默认关」表达。
- **改的时间**：首次修改 **2026-09-27**，后续改动见 git 历史与 [CHANGELOG.md](CHANGELOG.md) 顶部的自有变更段。
- **与上游的关系**：`Atoll` 仅用于指明代码来源。**本项目与 Atoll 项目及其维护者无隶属关系，也未获其背书**（nominative use；见 [TRADEMARKS](TRADEMARKS)）。

## 功能

- **首页工作台（strip）**：媒体块、前台应用块、通知块、待办块、镜子块各占一格；宽度不够时按顺序丢块，条尾给 `＋N` 而不是静默消失。
- **首页日历行**：整月网格 + 当天清单，与展开面板的「日历」tab 由同一个开关控制。
- **展开面板**：顶部 tab 栏 + 各功能页（主页 / 文件暂存 / 统计 / 备注 / 终端 / 调色盘 / 日历 / 启动台…），tab 由模块注册表投影产出。
- **媒体与歌词**：正在播放的曲目、进度与控制，锁屏媒体 widget，逐行歌词（默认关）。
- **系统指标与 HUD**：CPU / 内存 / 网络 / 磁盘 / GPU / 温度；音量、亮度、键盘背光、电池的 HUD 直接在刘海处显示。
- **效率工具**：剪贴板历史与固定片段、倒计时（计时器 tab）、日历与提醒、待办（写回系统提醒事项）。
- **文件暂存（暂存器）**：把文件拖进刘海暂存，再拖出或 AirDrop。
- **自建模块**：快捷启动（可搜索、可固定的应用网格）、农历、日 / 周 / 月 / 季 / 年进度、系统「快捷指令」上岛、通知上岛、外部终端（Ghostty 等）。
- **组件页**：一个模块一张卡——默认开 / 关、「开了会在哪看到什么」、能拨的配置直接拨；改不了的键明确标「由上游设置管理」。
- **一切皆开关**：每个功能可独立开关、独立配置、独立崩溃隔离（模块协议见 [docs/06](docs/06-module-protocol.md)）。

## 安装

1. **构建**（全程本机完成，不依赖 GitHub；需要 Xcode）：
   ```bash
   sh tools/build.sh --install     # 构建并装到 /Applications/壶中天.app
   sh tools/build.sh --dmg         # 或在 dist/ 产出 壶中天-0.1.0.dmg
   ```
2. **安装**：`--install` 已装好；用 DMG 的话把「壶中天」拖进「应用程序」。
3. **放行**：首次打开若被 Gatekeeper 拦下，右键 → 打开（或到「系统设置 → 隐私与安全性」点「仍要打开」）。

应用是**菜单栏小工具**（没有 Dock 图标）：启动后看屏幕顶部（刘海 / 刘海位），鼠标悬停即展开。

## 使用说明

**装上之后怎么用**——安装、权限清单、每个模块做什么、设置页怎么用、快捷键、常见问题、更新与卸载，全在用户手册：**[docs/guide/README.md](docs/guide/README.md)**（7 张实机截图，红圈序号逐条对应）。
给发布者的自检清单一页：[docs/25-release-smoke.md](docs/25-release-smoke.md)。

## 常见问题

- **功能开了却没反应？** 接管模块的启用真源是**上游那个开关键**（如 `enableTimerFeature` / `showMirror` / `showStandardMediaControls`）——组件页与上游设置页拨的是同一个开关；卡片上标了「由上游设置管理（改了不生效）」的项，请到上游设置页改。
- **面板窄的时候首页条少了几块？** 宽度不够时按顺序从尾部丢块，条尾 `＋N` 就是「还有几块没显示」；拉宽面板即可（含媒体的四块约需面板 ≥892pt）。
- **为什么要摄像头 / 完全磁盘访问这类权限？** 功能是本地实现的（媒体走私有框架 + 子进程、通知读本机通知库、镜子直开摄像头）；**本项目不新增出站请求、不上传数据**。权限可以不给——对应功能降级（例如通知块显示「不可读」）而不是崩溃。
- **通知的 × 为什么有时只从岛上移除？** 只有近 10 秒内有 AX 句柄的通知才能顺手把系统那条也关掉，更早的只能从列表移除——文案会如实分档说明（[docs/21](docs/21-strip-honesty.md)）。
- **版本号为什么是 0.1.0？** 它是「第一个冻结的自用版」：功能面已成型，但接管模块配置的写路径、tab 排序等仍留着空档，报 1.0.0 会误导将来的自己（[docs/24](docs/24-release-freeze.md) §备选与取舍 ①）。

## 归属与致谢

- **上游基座**：[Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll)（GPL-3.0）——应用工程 fork 自它，其内嵌的 boring.notch 署名原样保留。
- **组件与参考**：[boring.notch](https://github.com/TheBoredTeam/boring.notch)（GPL-3.0）、[exelban/stats](https://github.com/exelban/stats)（MIT）、[MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter)（BSD-3-Clause）、[NotchDrop](https://github.com/Lakr233/NotchDrop)（MIT）等，完整清单在 [NOTICE](NOTICE) 与 [docs/03](docs/03-license-matrix.md)。

## 文档

- [docs/00-decisions.md](docs/00-decisions.md)（ADR）、[docs/01-architecture.md](docs/01-architecture.md)（架构 + 术语 + 目录约定）、[docs/02-roadmap.md](docs/02-roadmap.md)（路线图）。
- 用户手册 [docs/guide/README.md](docs/guide/README.md)；发布自检 [docs/25-release-smoke.md](docs/25-release-smoke.md)。

## 许可证

**GNU General Public License v3.0**（[LICENSE](LICENSE)）。本项目是 Atoll 的修改版本（fork，首次修改 **2026-09-27**），以 GPL-3.0 分发：分发二进制须同时提供完整源码、保留上游署名并标注修改；禁止并入闭源产品（含上架 Mac App Store 的商业版本）。
