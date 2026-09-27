# 功能映射：Nook X → 壶中天模块

左列是 Nook X 的既有能力（来自其 App Store 描述与你提供的界面截图），右列是本项目的模块归属、优先级与代码来源。**本项目没有 Free/Pro 之分，模块只有开与关。**

> ⚠️ **这张表是"对标映射"，不是"待做清单"**（2026-09-27 修正）：逐文件勘察后确认，**Atoll 已实现约 40 个用户可见功能**，下表"代码来源"里写的多数目标**在基座里已经存在**——例如 stats、日历/提醒、Shelf、计时器、剪贴板、媒体与歌词、天气、笔记、取色器都已有可用实现。
>
> **范围已定稿（[ADR-0011](00-decisions.md) + [ADR-0012](00-decisions.md)）**：上游功能**全部保留、一项不删**；上游没有的按需新增——**要做的 6 项是快捷启动、农历、日/周/月/季/年进度、系统 Shortcuts 上岛、通知上岛、终端外部化**；仍不做的 3 项是照片浏览、番茄钟、AI agent 状态面板。逐项设计见 [09-features-and-mechanisms.md](09-features-and-mechanisms.md) §5。
>
> 逐功能的实现机制、上游现状、删除清单与待讨论项见 **[09-features-and-mechanisms.md](09-features-and-mechanisms.md)**；P2 的工作性质是"接管 + 包装 + 删除"（[02-roadmap.md](02-roadmap.md) P2）。

## 1. 顶部状态条（截图里左右两排图标）

| Nook X 状态项 | 壶中天模块 | 优先级 | 数据源 | 代码来源 / 许可 |
|---|---|---|---|---|
| 网速（上/下行） | `stats` | P2 | `getifaddrs` 增量采样 | exelban/stats（MIT）、NetSpeedMonitor（MIT） |
| 农历 | `calendar` | P2 | 内置万年历算法 | 算法自实现；LunarBar（MIT）参考 |
| 日历 / 星期 | `calendar` | P2 | EventKit | 自建 |
| 电量 / 充电 | `stats` | P2 | IOKit power sources | stats（MIT） |
| 处理器 / 内存 / 磁盘 | `stats` | P2 | `host_statistics` / IOKit / `statfs` | stats（MIT） |
| 天气情况 / 温度 / 湿度 / 风速 | `weather` | P2（可选） | Open-Meteo（免 key） | 自建 |
| 日/周/月/季/年进度 | `progress` | P3 | 本地日期计算 | 自建（并入 `stats` 或独立） |

> 这一排对应的就是"Nook X 的外观自定义 + 图标自由排列"。在壶中天里它是**模块注册表的直接渲染**：启用的模块把自己的折叠态视图交上来，用户拖拽排序。

## 2. 灵动方舱小组件（展开模式）

| Nook X 小组件 | 壶中天模块 | 优先级 | 代码来源 / 许可 |
|---|---|---|---|
| 流光声域（音乐歌词） | `lyrics` + `nowplaying` | P2 | lyrimuse（GPL-3.0）、LyricsX（MPL-2.0）、boring.notch 的 MediaControllers（GPL-3.0） |
| 日历天气 | `calendar` + `weather` | P2 | LunarBar（MIT）参考 + Open-Meteo |
| 快捷启动（启动应用） | `launcher` | P2 | 自建（Launch Services + NSWorkspace）；交互参考 LaunchNext（GPL） |
| 快捷指令（系统 Shortcuts 上岛） | `launcher` | P3 | 走 `shortcuts://` URL scheme；boring.notch 的 Shortcuts 目录可参考 |
| 待办事项 / Todo | `todo` | P2 | EventKit Reminders 为主，本地清单为辅 |
| 番茄钟 / 专注 | `timer` | P2 | 自建 |
| 临时笔记本 / 速记 | `notes` | P3 | 自建（本地 SQLite + Markdown） |
| 前置摄像头镜子 | `mirror` | P3 | AVFoundation；boring.notch 有 Mirror 实现可参考 |
| 照片浏览 | `photos` | P4（可选） | PhotoKit，优先级最低 |
| 文件暂存区 | `shelf` | P2 | NotchDrop（MIT）、OpenYoink（MIT） |
| 应用启动台 | — | 不做 | 交给 LaunchNext 等专门项目（见架构文档"非目标"） |
| AI 智能对话（多模型） | `ai` | P2 | 自建：OpenAI 兼容协议 + 用户自带 key，多 provider 可切换 |
| 实时通知（天气/喝水/久坐/入睡） | `timer` + 内核通知 | P3 | 自建（定时器 + UserNotifications） |
| 外观自定义 / 图标更换 | `ThemeCenter` + 设置 | P3 | 自建（主题令牌 + 图标集） |
| 灵动岛液态玻璃效果 | `ThemeCenter` | P3 | 自建（macOS 26 材质 API，低功耗降级） |

## 3. 本项目新增（Nook X 没有的）

| 能力 | 模块 | 优先级 | 说明 |
|---|---|---|---|
| 第三方插件生态 | `PluginHost` + SDK | P4 | 描述符 + XPC/JS 双宿主，见架构文档第 6 节 |
| AI 编码 agent 状态面板 | `aiagents` | P3 | 参考 CodeIsland（MIT）/ vibe-notch（Apache-2.0）/ open-vibe-island（GPL）；对接 Claude Code / Codex |
| 剪贴板历史 | `clipboard` | P2 | Maccy（MIT）的实现思路 |
| 外接显示器亮度/音量 | `controls` | P3 | MonitorControl（MIT） |
| 脚本化自定义项 | 插件 API | P4 | 参考 SwiftBar（MIT）的脚本插件模型（非直接引入） |

## 4. 第一批落地顺序（建议）

1. `nowplaying` + `lyrics` —— 每天用，且最能体现"灵动岛"的价值
2. `shelf` —— 文件拖拽是高频刚需
3. `stats` + `calendar` —— 把顶部状态条铺满
4. `launcher` + `controls` —— 补齐"快捷控制 / 快捷启动"这条线
5. `ai` + `clipboard` + `timer` + `todo`
6. 其余的按兴致推进

每做完一个模块，在 `docs/02-roadmap.md` 对应条目前打勾，并在 `NOTICE` 登记用到的上游代码。
