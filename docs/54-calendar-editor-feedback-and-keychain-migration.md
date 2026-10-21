# 日历编辑器四项反馈与 AI 凭据迁移（2026-10-19）

> **2026-10-21 更新**：生产凭据已改为 Application Support 文件（`AIFileSecretStore`）；本文的 Keychain v1→v2 迁移只保留为静默迁移/历史回归，不再是生产主路径。详见 [docs/45 同日小节](45-ai-calendar-and-meeting-actions.md)。

状态：已实施；本轮验证为定向 XCTest + Release 构建，真实钥匙串弹框与鼠标手感仍待人工确认。承接 [docs/45](45-ai-calendar-and-meeting-actions.md)（AI 配置 / Keychain 引用）与 [docs/49](49-calendar-list-actions-fonts-and-generation.md)（编辑档表单、大文本框行数）。用户提供三张编辑档截图并反馈四条问题。

## 背景

用户安装含「启动台快捷启动排序」的构建后，在日历编辑 / 新建档遇到：

1. 每次点「生成」都会弹出钥匙串密码框；
2. 编辑档的内容没有铺满剩余高度，表单下方留出一大片空白；
3. 编辑既有事项时看不到「用文字生成」，无法再次输入文本让模型分析；
4. 新建时多行输入框看起来像单行输入框，且默认类型是「待办」，期望默认「日程」。

## 做法

### 1. AI 凭据：v1 → v2 迁移 + 会话缓存

**根因判断**：旧密钥条目创建于 2026-10-14，由当时的构建（可能是 DerivedData / 另一签名）写入 legacy Keychain；条目的 ACL 不认当前 `/Applications` 构建。`SecItemCopyMatching` 每次读取都会要求系统授权，而 `AIConfigurationStore.credential(for:)` 原先在每个 AI 请求前都读一次，所以「每次生成」都弹。

**修复**：

- `AIKeychainSecretStore` 的服务名从 `com.cmeng.gourd.ai.credentials.v1` 升为 `...v2`，并把服务名做成注入参数；
- 新增 `AIMigratingSecretStore` 装饰器：
  - 先读 v2；命中即返回；
  - v2 未命中 → 读 v1；读到后以**当前签名的 App** 新建 v2（旧条目保留，回滚旧版本仍可读）；
  - 同一次启动内缓存已读到的凭据，后续生成不再碰 Keychain；
  - `write` 只写 v2；`delete` 两代一起删；读取失败（含用户在系统框里点取消）原样抛出，不伪装成「未配置」。
- 生产路径 `AIConfigurationStore(defaults:secretStore:)` 默认使用迁移装饰器。

**代价**：升级后第一次生成仍可能提示一次（旧条目读取 + 迁移）；允许后不再提示。若用户不想看到这一次，可在「AI 模型」设置里重新保存一次密钥——新密钥直接写 v2，不经过旧条目。密钥仍只存 Keychain，配置只存 UUID 引用。

### 2. 编辑页：大文本框吃剩余高度

- `CalendarGrowingTextEditor` 新增 `fillsAvailableHeight`：true 时 2 行只是**下限**，父布局给多少就长多少；false 保持定高（既有调用方不受影响）。
- `editorPage` 用 `GeometryReader` 取视口高度，给表单 `.frame(minHeight: proxy.size.height, alignment: .top)`；原文区与备注各带 `.frame(maxHeight: .infinity)`，富余高度由它们吸收。
- 内容仍超过视口时退回 2 行下限，整页照旧滚动；备注内容再多也只在框内滚动，不会把整页顶高。

### 3. 编辑既有事项也能再次生成

- 去掉 `if draft.eventID == nil` 的生成区门槛，四种入口（新建日程 / 新建待办 / 编辑日程 / 编辑待办）都渲染 `CalendarSourceGeneration`。
- 解析结果的合并口径不变：只覆盖「与快照相同」的字段；用户手动改过的字段不被候选覆盖。

### 4. 新建默认日程

- 「+」入口从 `beginCreate(kind: .reminder, ...)` 改为 `.event`，并使用 `preferredEventCalendarID`；分段控件仍可切换到待办。
- 多行输入框由第 2 条的铺满模式承担「文本域」观感，单行标题 / 地点 / 链接保持原有输入框样式。

## 决策与取舍

| # | 决策 | 来源 | 理由与代价 |
|---|---|---|---|
| 1 | 用 v2 服务 + 迁移装饰器，而不是把密钥改存文件 | agent | 保留「秘密只进 Keychain」的既有安全口径；旧条目保留可回滚。代价：首次迁移可能提示一次 |
| 2 | 凭据按会话缓存 | agent | 直接消除「每次生成都读」的重复授权；同一进程内密钥常驻内存，退出即释放 |
| 3 | 2 行只是下限，有富余就铺满 | 用户 | 用户要「内容铺满剩余高度」；字段多到装不下时仍能滚动，不牺牲小屏可用性 |
| 4 | 编辑档保留生成区 | 用户 | 用户明确要「编辑的时候再次输入文本做模型分析」；合并仍只覆盖未改过的字段 |
| 5 | 新建默认日程 | 用户 | 用户原话「默认改为日程，不是待办」；待办仍可一键切换 |

## 测试

定向 XCTest 共 **172 条，0 失败**（第一批 71：`AIConfigurationTests` / `CalendarPageLayoutTests` / `CalendarGenerationAndMeetingActionTests` / `CalendarNativeTextSystemTests`；第二批 101：`CalendarQuickAddTests` / `CalendarInteractionTests`），其中：

- `testMigratingSecretStoreReadsLegacyOnceAndCachesForTheSession`：v1 首次读 → 写 v2 → 缓存命中不再读；写入只落 v2；删除两代一起清；
- `testNotesEditorDrawsAVisibleBoxWithPlaceholderInsideIt`：备注框至少 2 行、有富余时铺满；20 行内容不把框顶高；
- `testUnifiedEditorFormPairsFieldsAndHidesBoilerplate`：四种入口都有生成区；
- `testCalendarAddDefaultsToEventAndEditKeepsGenerationControls`：新建默认日程 + 编辑档保留生成区的源码接线。

全量 `DynamicIslandTests`：**950 条，0 失败**。原始日志见本轮实施记录的证据目录。

## 已知限制

1. **真实钥匙串弹框路径未自动化**：单测用替身，无法证明 macOS 一定不再弹框；需用户在真实 AI 请求上确认「迁移一次后不再弹」。
2. **布局为离屏 / 宿主挂载验证**：备注框高度与内容滚动有 XCTest 覆盖；原文区、按钮顶对齐与真实鼠标手感仍需上屏确认。
3. 旧 v1 条目保留未删：回滚旧版本仍可读；若用户彻底不需要旧版本，可后续单独做清理入口。
