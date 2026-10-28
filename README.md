# 壶中天 · Gourd

> **自用 + 开源**的 macOS **刘海工作台**：把屏幕顶部那一小块（刘海 / 刘海位）做成命令面板——媒体、日历、系统状态、文件暂存、待办、快捷启动、通知与自建小工具都收在这里，**一切功能皆可开关、可扩展**。
>
> **这是一个修改版本（modified version）**：本项目 fork 自 [Atoll](https://github.com/Ebullioscopic/Atoll)（GPL-3.0），基线 tag `v2.3.3-beta.3`（commit `c7305ec`），自 **2026-09-27** 起由本仓库维护修改；上游版权声明与 GPL-3.0 全文原样保留（见 [LICENSE](LICENSE)、[NOTICE](NOTICE)）。
>
> 「壶中天」取意壶中天地——一个小容器里装下一整块工作台；屏幕顶部那个小口展开，就是你的全部工具。

## 与 Atoll 的关系

- **代码来路**：应用工程 fork 自 [Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll)（GPL-3.0），基线锁定 tag **`v2.3.3-beta.3`**（commit `c7305ec`）；上游完整历史保留在 `main`，季度同步走原生 `git merge`。
- **改了哪些**：改名与重打包（产品名 **壶中天 / Gourd**、Bundle ID `com.cmeng.gourd`；本地产物 `dist/壶中天-<版本>.dmg`，Release 附件用 ASCII 名 `Gourd-<版本>.dmg`）；版本号改为自有序列（本版本 **0.5.0**）；加模块化内核与自建模块（启动台 / 农历 / 工作日统计 / 待办 / 快捷指令 / 通知 / 前台应用）；设置重新分组、界面中文化、默认值收敛。**上游功能一个未删**——不需要的用「默认关」表达。
- **改的时间**：首次修改 **2026-09-27**，后续改动见 git 历史与 [CHANGELOG.md](CHANGELOG.md) 顶部的自有变更段。
- **与上游的关系**：`Atoll` 仅用于指明代码来源。**本项目与 Atoll 项目及其维护者无隶属关系，也未获其背书**（nominative use；见 [TRADEMARKS](TRADEMARKS)）。

## 功能

- **首页工作台（三带）**：固定第一排**环境带**（音乐 · 前台应用 · CPU / 内存 / GPU 读数）+ **今天带**（日期与农历节假日、本月 / 本季 / 今年剩余工作日、下一个日程倒计时、右端 ＋ 直达新建）+ **可变流**（今日清单、通知等组件按设置排序换行排布，窄了换行、条尾 `＋N`）。
- **日历与 AI 日程生成**：月历（**农历** + 订阅**节假日**、周一起始；日格**橙 / 蓝分色点与数量角标**区分自己的日程与信息类日程）+ 右栏列表 / 编辑两档，新增与编辑是一张两列表单；**一句话生成日程**——原文交给模型直出日期时间（`⌘↩` 显式触发，不偷改输入；生成失败只留一行原因，不写坏已填内容）。AI 配置独立成页（OpenAI compatible / Anthropic / Gemini / Ollama，本机模型也行），**密钥只存本机文件，不进仓库与安装包**。
- **会议一键入口**：通知 / 日程 / 待办里认出华为云会议、腾讯会议、化小易等会议信息时，一枚按钮**点一下就成**——能打开就打开、只有号码就复制，多候选不猜（右键最多 4 项），识别全在本地。
- **通知**：折叠态铃铛 + 首页块（块内滚动）+ 完整列表三面；新通知**浮层**默认只上主屏（可在通知块表头一键开到外接屏）；读系统通知库需**完全磁盘访问**，缺了只是降级不崩。
- **展开面板**：顶部 tab 栏 + 各功能页（主页 / 文件暂存 / 终端 / 待办 / 通知 / 日历 / 启动台 / 计时器…），tab 由模块注册表投影产出，右侧是剪贴板 / 取色 / 计时器 / 设置等固定按钮。
- **媒体**：正在播放的曲目、进度与控制（可自定义按钮排布），音乐上岛、快速预览、**屏幕歌词悬浮层**（先读本机播放器的歌词缓存，再走公共词库的候选阶梯：歌手别名 / 多写法重试 / 时长吻合认领）；点一下首页音乐块 = 打开正在放歌的那个软件；锁屏媒体面板与全屏封面。
- **系统指标与 HUD**：CPU / 内存 / GPU / 网络 / 磁盘等指标；音量、亮度、键盘背光、电池的提示可在四种形态里选（灵动岛 / 自定义 OSD / 垂直条 / 圆形），第三方 DDC App（BetterDisplay / Lunar）也能接进来。
- **效率工具**：剪贴板历史与固定片段、计时器（含预设与系统时钟同步）、待办（写回系统「提醒事项」）、暂存器（拖文件进岛，隔空投送 / 快速共享）。
- **自建模块**：启动台（可搜索、可固定、**可拖动排序**的应用网格）、系统「快捷指令」上岛、通知上岛、前台应用块（窗口最小化 / 异屏 / 无窗口三种「点了没反应」都有自动处理）。
- **组件页**：一个模块一张卡——默认开 / 关、**开了会在哪看到什么**、能拨的配置直接拨；改不了的键明确标「由上游设置管理」。
- **一切皆开关**：每个功能可独立开关、独立配置（模块协议见 [docs/06](docs/06-module-protocol.md)）。

## 安装

要求 **macOS 15（Sequoia）及以上**、**Apple 芯片（arm64）**（液态玻璃观感需 macOS 26，低版本自动降级为普通模糊）。

**方式一 · DMG**（推荐给使用者）：到 [Releases](../../releases) 下载 `Gourd-0.5.0.dmg`，打开后把「壶中天」拖进「应用程序」。

应用**未公证**（本项目不付费走 Apple 开发者计划），所以第一次打开会被 Gatekeeper 拦下——**放行一次即可，之后不再拦**：

1. 双击「壶中天」，出现「无法打开，因为 Apple 无法验证其是否包含恶意软件」这类提示时点**完成**；
2. 打开**系统设置 → 隐私与安全性**，往下滚到「安全性」一栏，会看到刚被拦下的应用，点**仍要打开**；
3. 输入密码确认，再双击一次就进去了。

> 第 1 步不能跳：只有先试过一次、被拦下，「仍要打开」按钮才会出现在系统设置里。

**方式二 · 命令行**（装完不弹任何提示）：从浏览器下载的包会被打上隔离标记，`curl` 不会——这条路绕开了上面整段。

```bash
curl -fsSL https://raw.githubusercontent.com/cmeng-CM/Gourd/main/install.sh | bash
```

脚本只做五件事：判断架构 → 下载 → 校验 SHA256 → 拷进「应用程序」→ 清理；不写系统目录、不改系统设置。全文就在上面那个链接里，可以**先读再跑**。装指定版本：`| bash -s -- v0.5.0`。

**方式三 · 自己构建**（需要 Xcode；全程本机完成，不依赖 GitHub）：

```bash
sh tools/build.sh --install     # 构建并装到 /Applications/壶中天.app
sh tools/build.sh --dmg         # 或在 dist/ 产出 DMG
```

改完代码想装到本机看效果，走**一键安装**那条（等价于上面第一行，装完顺手启动一次）：

```bash
sh tools/install-local.sh       # 或直接双击仓库根的 install-local.command
```

应用是**菜单栏小工具**（没有 Dock 图标）：启动后看屏幕顶部（刘海 / 刘海位），鼠标悬停即展开。

## 文档

| 文档 | 给谁看 |
|---|---|
| **📖 [图文使用手册（单文件 HTML，含截图）](docs/manual/manual-0.5.0.html)** | **新装用户先看这个**：14 节图文手册（安装放行 → 基本交互 → 各功能 → 设置速查 → 权限 → FAQ）。[在线预览](https://htmlpreview.github.io/?https://github.com/cmeng-CM/Gourd/blob/main/docs/manual/manual-0.5.0.html)，或[下载文件](../../raw/main/docs/manual/manual-0.5.0.html)（约 0.9 MB，图片全部内嵌，双击即开、可离线传阅） |
| **[用户手册 docs/guide/](docs/guide/README.md)** | **使用者**：安装、权限、界面速览、组件页、快捷键、常见问题、更新与卸载 |
| [用户手册 · 设置参考](docs/guide/settings.md) | **每一项设置**是什么、默认值、互斥与灰显条件（逐页列举） |
| [用户手册 · 组件页与各模块](docs/guide/modules.md) | 总控台怎么用；每个模块默认开不开、出现在哪、能配什么 |
| [用户手册 · 快捷键](docs/guide/shortcuts.md) / [常见问题](docs/guide/faq.md) | 默认键一览；装好之后最容易遇到的坑 |
| [开发文档 docs/00~54](docs/00-decisions.md) | **贡献者 / 未来的自己**：ADR（20 条）、架构、模块协议、各批次的设计记录与已知限制（不是给使用者看的） |
| [发布自检清单 docs/25](docs/25-release-smoke.md) / [发布流程 docs/33](docs/33-release-process.md) | 打开发包前跑一遍；打包 → 上传 → Release 的完整步骤（给发布者） |

## 常见问题（选摘）

- **功能开了却没反应？** 组件页每张卡片都写着「开了会在哪看到什么」；标了「由上游设置管理（改了不生效）」的项，真源在设置里的另一页（卡片上的开关与它是同一个）。
- **面板窄的时候首页块少了几块？** 块会换行；只有连一行都放不下才从尾部丢，条尾 `＋N` 就是「还有几块没显示」——拉宽面板即可。
- **通知块显示「不可读」？** 缺**完全磁盘访问**（系统设置 → 隐私与安全性）；给不给都行，不给就降级显示，不会崩。
- **为什么要摄像头 / 完全磁盘访问这类权限？** 功能都是**本地实现**的（媒体走系统框架与子进程、通知读本机通知库、镜子直开摄像头）；**本项目不新增任何出站请求、不上传数据**。
- 更多见 [用户手册 · 常见问题](docs/guide/faq.md)。

## 贡献

- 提 issue / PR 都欢迎；提交信息请写清「改了什么、为什么、怎么验证的」。
- 动代码前先看 [docs/00-decisions.md](docs/00-decisions.md)（20 条 ADR）与 [docs/01-architecture.md](docs/01-architecture.md)；模块相关改动读 [docs/06-module-protocol.md](docs/06-module-protocol.md) 与 [docs/07-config-and-events.md](docs/07-config-and-events.md)。
- 本地门禁：`xcodebuild test … -only-testing:DynamicIslandTests` 全绿 + `sh tools/build.sh` 能出包。

## 归属与致谢

- **上游基座**：[Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll)（GPL-3.0）——应用工程 fork 自它，其内嵌的 boring.notch 署名原样保留。
- **组件与参考**：[boring.notch](https://github.com/TheBoredTeam/boring.notch)（GPL-3.0）、[exelban/stats](https://github.com/exelban/stats)（MIT）、[MediaRemoteAdapter](https://github.com/ungive/mediaremote-adapter)（BSD-3-Clause）、[NotchDrop](https://github.com/Lakr233/NotchDrop)（MIT）等，完整清单在 [NOTICE](NOTICE) 与 [docs/03](docs/03-license-matrix.md)。

## 许可

**GPL-3.0-or-later**（沿用上游）。完整文本见 [LICENSE](LICENSE)；修改说明见本文档「与 Atoll 的关系」与 [CHANGELOG.md](CHANGELOG.md)。
