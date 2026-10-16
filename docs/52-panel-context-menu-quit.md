# 52 · 面板右键菜单加「退出」

| 项 | 值 |
|---|---|
| 状态 | 已实现（上屏已自测：合成右键出菜单、点「退出」应用完全退出） |
| 最后更新 | 2026-10-16 |
| 关联来源 | 用户 2026-10-16 的现场要求（右键展开的面板，截图圈出菜单里的「设置」）：「在这个上增加一个退出按钮，可以完全退出应用的按钮」；承接 [31-home-workday-launcher.md](31-home-workday-launcher.md) §已知限制 11（面板根 `.contextMenu` 会盖住模块格子的右键菜单，p2 起既有） |
| 读者 | 实现者看 §做法；维护者看 §已知限制 |

## 一句话方案

面板根上的 `.contextMenu`（`ContentView.configuredMainLayout` 末端）原来只有一项「设置」，现在
加一条**分隔线 + 「退出」**——走 `NSApplication.shared.terminate(nil)`，与菜单栏菜单那条
`Button("Quit")` **同一个终止链**（`AppDelegate.applicationShouldTerminate` 里还有日历会话的收尾）。

## 背景与目标

本应用只有两个入口：菜单栏图标（`menubarIcon`，**可以关掉**）与刘海面板。没有 Dock 图标
（`LSUIElement`），所以**菜单栏图标一关，「完全退出」就没有出口了**——⌘Q 也不作数：面板是非激活
窗口、没有键窗，按下去没人接。右键退出是这类「只有面板」的应用最小可用的一条出口。

面板根右键菜单本身是上游留下的（p2 起就在，只有「设置」），也是 docs/31 记过的那条
「盖住模块格子菜单」的当事人（见 §已知限制）。

## 做法

`DynamicIsland/ContentView.swift` 的 `configuredMainLayout` 末端：

```swift
.contextMenu {
    Button("Settings") { SettingsWindowController.shared.showWindow() }
    Divider()
    Button("Quit", role: .destructive) { NSApplication.shared.terminate(nil) }
}
```

四条口径：

- **必须走 `terminate`**：`applicationShouldTerminate` 里挂着日历会话的收尾（有未落盘的编辑时会
  问「保存并退出 / 放弃并退出 / 取消」，有写入在进行就先等）——`exit(0)` 之类会绕过它，那才是
  「退不干净」。
- **文案复用既有键 `Quit`**（catalog 里已有 18 种语言，`zh-Hans` = 退出）→ **不动本地化表**，
  因此也不需要往本地化守卫里登记新键。
- **`role: .destructive`**：与菜单栏那条同款。**实测本机这个菜单里并没有渲染成红字**（两项都是
  白字）——保留它要的是读屏（VoiceOver）那边的「破坏性动作」播报，不是为了颜色。
- **不给 ⌘Q 快捷键**：面板没有键窗，提示一个按不动的快捷键比不提示更糟。

## 已知限制

1. **面板根菜单会盖住模块格子的右键菜单**（docs/31 §已知限制 11，p2 起既有的行为）：在首页块或
   启动台格子上右键，出的是这条面板菜单（「设置 / 退出」），不是格子的「固定 / 取消固定」。
   本批**没有改这条遮挡关系**——只多了一项，不是新引入的问题。
2. **只在展开态验证过**：本批的上屏取证（合成右键 + 点「退出」）是在**展开的面板**上做的；
   折叠态岛本身上下也挂着同一个菜单（同一棵视图），但没有单独取证。
3. **菜单的观感（圆角、分隔线粗细、是否红字）随系统版本走**：那是 `NSMenu` 的原生渲染，
   本项目不接管它的样式。

## 实际交付

| 文件 | 改动 |
|---|---|
| `DynamicIsland/ContentView.swift` | 面板根 `.contextMenu` 加 `Divider()` + `Button("Quit", role: .destructive)`；注释写明「为什么必须 terminate / 为什么不要快捷键 / 键复用」 |
| `docs/guide/README.md`、`docs/guide/faq.md` | 用户可见的两处口径：菜单栏图标可以关掉，关掉之后**右键面板**里有「设置 / 退出」 |

**上屏取证**（2026-10-16，本机）：`CGEvent` 合成——先 `mouseMoved` 悬停主屏刘海正中 ~2.4s 展开面板，
再 `rightMouseDown/Up` 在面板内空白处右键 → 截图见菜单两项「设置 ── 退出」；
随后 `leftMouseDown/Up` 点在「退出」上 → `ps` 里 `壶中天.app/Contents/MacOS/Gourd` **进程消失**
（完全退出，不是收起面板）。截图与方法留在
`~/workspace/temp/20261016/gourd-panel-menu-quit/`（`面板右键菜单-设置与退出.png` 与 `菜单特写.png`）。

## 决策摘要

| 编号 | 决策 | 依据 |
|---|---|---|
| D-01 | 就加在**面板根已有的那条右键菜单**里（新起一条会与它争位置） | 用户原话是「在这个上增加」；面板根菜单也是唯一两态（展开 / 折叠）都可达的菜单点 |
| D-02 | 终止走 `NSApplication.shared.terminate(nil)`，与菜单栏那条同源 | 日历会话的收尾挂在 `applicationShouldTerminate` 上；换个更"狠"的退出方式会绕过它 |
| D-03 | 复用既有 `Quit` 键，不新增本地化键 | 该键已是 18 语言齐全；新增键还要动本地化守卫的登记表，收益为零 |
| D-04 | 不挂 ⌘Q。`role: .destructive` 保留（尽管本机菜单不渲染红字） | 前者会提示一个按不动的快捷键；后者是读屏语义，与颜色无关 |
