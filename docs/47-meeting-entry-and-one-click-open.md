# 会议入口：一次点击（打开或复制）

| 项目 | 内容 |
|---|---|
| 状态 | 草稿（P 轮起草；实现后回写） |
| 最后更新 | 2026-10-14 |
| 关联来源 | 承接 [docs/45](45-ai-calendar-and-meeting-actions.md) §3「复制与会议入口」；本轮设计稿 `~/workspace/temp/20261014/svg/01…05` 与定位报告 `~/workspace/temp/20261014/gourd-calendar-meeting-issues.md`（用户逐张审阅后授权开工） |
| 读者 | 实现者与审查者看「接口与数据形状」；维护者看「已知限制 / 实际交付 / 决策摘要」 |

## 一句话方案

把首页与日历里的会议入口从「一条被拉伸的宽按钮 + 一张最多 15 项的系统菜单」改成「22pt 图标，点一下直接执行主动作（能打开就打开会议、打不开就复制会议号），次要动作收进右键 4 项」，同时去掉「开始前 15 分钟才能打开」的时间闸门、删掉实测无效的「用 AI 识别会议」，并补上按会议号打开（华为官方深链 / 腾讯客户端 scheme）与不带井号的「腾讯会议：」标签识别。

## 背景与目标

**问题现状**（2026-10-14 用户实测，证据见定位报告）：

- 会议入口按钮是 `NSViewRepresentable` 包的 `NSButton`，代码只给了 `.frame(height: 24)`、没给宽度，被 SwiftUI 拉伸到约 187pt（首页行宽的 44%），把 `maximumLines: 1` 的日程标题挤到约 130pt 并截断（`MeetingActionView.swift:189-193`，`TodosModule.swift:1731`）。
- 点它弹出的是**系统 NSMenu**，最多 15 项：其中 6 项是纯说明（点了没有动作）；候选行的标题是原始证据串（可多行，`NSMenuItem` 会把换行渲染成额外的行）；同一个号码在不同标签下会产出两条 `codes`。
- 打开被一道时间闸门挡住：`isJoinable = start − 15min <= now`，未到时间则「打开」不可用。
- 有「用 AI 识别会议」兜底动作，但它**在任何情况下都帮不上忙**（见「备选与取舍」）。

**预期结果**：

- 首页那一行：会议图标只占 22pt，标题拿回约 150pt；点一下就是结果（打开会议或复制号码），结果由图标自身表达（转圈 / 对勾），随时可点。
- 右键：4 项，每项都有实际动作。
- 只有会议号的邀请也能「打开会议」：华为走官方文档的 `cloudlink` 深链（`conf_id` + `name`，可选 `enter_code` 装密码），腾讯走客户端 scheme `wemeet://page/inmeeting?meeting_code=`。
- 识别范围补全：不带井号的「腾讯会议：939130533」也能识别。

**承接关系**：本文件承接 [docs/45](45-ai-calendar-and-meeting-actions.md) §3 已定的结论 —— 严格 scheme/域名/路径校验、原 HTTPS 是可靠入口、多候选须选择、系统接受打开只表示接受请求、普通「会议室/会议资料」不显示入口。**本次修正其中一条**：docs/45 写「无可验证深链参数时不从会议号拼地址」，本轮改为「**只按已归档的官方或可验证文档拼两种地址**（华为 cloudlink 官方文档、腾讯 wemeet 客户端 scheme），参数白名单写死、号码必须 9–12 位、不接收其它参数」——这不是放开，而是把「一律不拼」换成「按文档拼」。术语与字段名沿用 docs/45（`MeetingJoinTarget` / `MeetingLinkResolver` / `sourceText`）。

## 做法

分三层，各自可单独测试：

1. **证据层**（`MeetingLinkResolver` / `CalendarMeetingEvidence`）：会议号标签正则补 `腾讯会议`（覆盖不带井号的写法）；新增 `passcode(in:)` 解析 `入会密码 / 会议密码 / password` 标签（**只喂给华为深链**，不新增复制项）。
2. **打开层**（`MeetingJoinURLBuilder` + `MeetingOpening`）：把「只有会议号」的邀请按平台拼成可入会深链，参数白名单写死并**复用现有校验器**（华为那条必须过 `validatedHuaweiNative`，腾讯新增一条 `wemeet` 校验分支），再交给 `NSWorkspace.open`；打不开就退回复制。
3. **动作层**（`MeetingActionModel` + 视图）：主动作二选一（打开 / 复制号码），瞬时状态（idle / opening / opened / copied / failed）映射到图标与 tooltip，右键 4 项；**记住**用户为「只有会议号」的邀请选过的客户端，下次主动作直接用它打开。

面板与首页共用同一个视图，用 `style`（`.icon` / `.row`）区分：首页是 22pt 图标，日历卡片/详情是一行两键（provider + 号码 + 打开/复制）。

## 备选与取舍

| 备选 | 为什么不选 |
|---|---|
| 保留系统菜单当一级入口 | 多一步；而且菜单里 6 项纯说明没有任何动作 —— 用户实测后要求点一下就有结果 |
| 保留「用 AI 识别会议」兜底 | **实测它在任何情况下都帮不上忙**：`recognize` 要求模型返回的片段既能定位到原文、又能被同一个正则解析成候选，而那个正则已经扫过整段原文 → 产不出新候选；正则认不出的写法（如不带井号的「腾讯会议：」）AI 给的片段同样解析不出候选，只会抛 `invalidEvidence`。修法是补正则，不是留一个必然报错的按钮 |
| 从任意会议号拼地址 | 只按**已归档文档**拼两种：华为 `conf_id`/`name`/`enter_code` 是官方文档写明的参数契约，腾讯 `wemeet://` 有腾讯云问答与 SDK `handleScheme` 两处印证（非官方对外文档，实现后需真机验一次） |
| 解析腾讯的密码参数 | 没有依据，不猜 |
| 结果用行内状态行展示 | 首页那行高度固定 34pt，塞不下一行状态文字 |

## 接口与数据形状

> 以下按**实际实现**（HEAD `b0450527`）校正；方案五节（一句话方案 / 背景与目标 / 做法 / 备选与取舍 / 明确不做）保持批准时的原文不动。

```swift
// 证据层（MeetingLinkResolver.swift，均为 private / 经 resolve 间接使用）
// 会议号标签：两处同义副本必须同步改（MeetingLinkResolver.meetingCodes(in:) 与
//   CalendarMeetingEvidence.patterns）——只改一处会让「腾讯会议：939130533」得 0 候选
private func meetingCodes(in text: String) -> [MeetingCode]
func passcode(in text: String) -> String?          // 入会密码/会议密码/password(?<![A-Za-z])
private static func validated(_ url: URL?) -> ValidatedURL?   // 含严格 wemeet 分支
// 已删除：recognize(text:using:) 与 MeetingRecognitionError（resolver 不再依赖 AIHandle）

// 打开层
enum MeetingJoinURLBuilder {
    static func digits(_ raw: String) -> String?            // 去空格/连字符后必须 9–12 位纯数字
    static func huawei(confID: String, displayName: String, passcode: String?) -> URL?
    static func tencent(meetingCode: String, passcode: String?) -> URL?   // passcode 被忽略
    static func url(provider: MeetingProvider, number: String,
                    displayName: String, passcode: String?) -> URL?
    static let fallbackDisplayName = "Gourd"
}
extension MeetingOpening {
    func openByNumber(provider: MeetingProvider, number: String,
                      displayName: String, passcode: String?) async -> MeetingOpenResult
}

// 动作层
enum MeetingActionFeedback: Equatable { case idle, opening, opened, copied, failed }
enum MeetingPrimaryAction: Equatable { case open(MeetingJoinTarget, MeetingProvider), copyCode(String), choose, none }
enum MeetingActionGlyph { static func symbol(for: MeetingActionFeedback) -> String }
final class MeetingActionModel: ObservableObject {
    var primary: MeetingPrimaryAction { get }
    @Published private(set) var feedback: MeetingActionFeedback
    var rememberedProvider: MeetingProvider? { get }   // 计算属性：读 Defaults，只白名单 huawei/tencent
    var determinedProvider: MeetingProvider? { get }   // 本条链接/候选自身的平台
    func performPrimary()                              // .choose 时 no-op（由视图弹菜单）
    func open(_ target: MeetingJoinTarget)             // 带链接的候选（保留）
    func openByNumber(provider: MeetingProvider)       // 按号码打开，并写入记住的客户端
    func copy(_ value: String) / func copySource()
}

// 视图层
enum MeetingActionStyle { case icon, row }
struct MeetingActionView: View {
    init(source: CalendarMeetingSource, session: CalendarPanelSession, style: MeetingActionStyle = .icon)
    init(event: EventModel, url: URL? = nil, session: CalendarPanelSession, style: MeetingActionStyle = .icon)
}
// 另有：MeetingActionRowKey（.open/.copy/.choose/.none 决定 .row 画哪些键）、
//       MeetingActionMenuEntry（含逐候选的 .openTarget）、MeetingActionPresentation（几何/文案派生）、
//       MeetingActionMenuPresenter（图标与 .row 共用的菜单弹出器）、MeetingActionIconButton（22×22 固有尺寸）

// 持久化：Defaults.Keys.meetingCodeOpener: Key<String?>（"huawei" / "tencent"）
// 首页分组：TodoText.groupHeaders(for:) -> [TodoText.Group]（可运行时断言的纯函数）
//           + TodoText.groupHeaderTitle(_:count:bundle:)
```

## 明确不做

- **整体面板尺寸不动**：面板宽度是全局值、auto 高度按页给，本次都不改；`openNotchHeight = 682` 的回落值问题、日历页最小宽都**不在本次范围**（用户明确「整体尺寸先不变」）。
- **日历编辑页不动**：统一表单、字段并排、编辑档 474 高度、显式「生成」按钮等归**另一个工作流**，本工作流不碰 `CalendarPanelPages` 的编辑器。
- 不解析腾讯的密码参数；不新增「复制入会密码」菜单项。
- 不做「已加入会议」的确认 —— 系统接受打开只表示接受了请求。

## 实际交付

（2026-10-14 终审后按实现回写；提交范围 `1592b24f..b0450527`）

**交付物**

- **证据层**（`DynamicIsland/services/MeetingLinkResolver.swift`）：`meetingCodes(in:)` 的会议号标签补 `腾讯会议` 分支，并与 `DynamicIsland/components/Calendar/CalendarSelectableText.swift:16` 的第二处同义副本**逐字同步**（计划要求的两处副本都改了）；新增 `passcode(in:)`；`validated(_:)` 增严格 `wemeet` 分支（host `page`、path `/inmeeting`、只允许 `meeting_code` 一个键且 9–12 位）；删除 `recognize(text:using:)` 与 `MeetingRecognitionError`。
- **打开层**：新增 `DynamicIsland/services/MeetingJoinURLBuilder.swift`（`digits` / `huawei` / `tencent` / `url` / `fallbackDisplayName`）；`MeetingOpening.openByNumber(provider:number:displayName:passcode:)`。
- **动作层**：`MeetingActionFeedback` / `MeetingPrimaryAction`（含 `.choose`）/ `MeetingActionGlyph`；`MeetingActionModel` 的 `primary` / `feedback` / `rememberedProvider`（计算属性 + 白名单）/ `performPrimary()` / `open(_:)` / `openByNumber(provider:)` / `copy` / `copySource`；`Defaults.Keys.meetingCodeOpener`。
- **视图层**：`MeetingActionStyle`（`.icon` / `.row`）；自绘 `MeetingActionIconButton`（**22×22 固有尺寸**、圆角 6、白 14% 底、无障碍 element + role）；`.row`（provider + 号码/链接 + 状态位 + 按 `MeetingActionRowKey` 画键）；`MeetingActionMenuPresenter`（图标与 `.row` 共用）。
- **调用点**：首页 `TodosModule.swift:1723`/`:1759` 走 `.icon`；`CalendarPanelPages.swift:353` 与 `DynamicIslandCalendar.swift:1497` 走 `.row`。
- **首页分组标题**：`TodoText.groupHeaders(for:)` / `groupHeaderTitle(_:count:bundle:)`，标题变 `日程 · N` / `待办 · N`；`TodoHomeHeader` 一字未改。
- **本地化与守卫**：新增 `openIn.*` / `provider.*` / `row.*` / `tooltip.*` 若干键，删除 16 个孤儿键（`calendar.meeting.accepted/cancelled/choose/configure/copyLink/fallback/menuHelp/opening/recognitionFailed/recognize/recognizing/refused/sendingScope/sourceTooLarge/tooEarly/open`）；`tests/test_general_ai_configuration.py` 重冻清单并把消费者判据改成**精确字面量**匹配。
- **文档**：`docs/guide/modules.md` 的「会议动作」段按新行为重写。
- **证据**：XCTest 851 / 0 失败；`python3 -m unittest tests.test_general_ai_configuration` 4 tests OK（`test_privacy_configuration` / `test_timer_lifecycle` 亦 OK）；`sh tools/build.sh` 退出码 0。

**与计划的偏离及原因**

| 偏离 | 原因 |
|---|---|
| T1 越出文件清单，删了 `MeetingActionView.swift` 的 `recognize()` 与菜单项 | 被删的 `MeetingLinkResolver.recognize` 唯一调用者在该文件；T1 要自己跑绿必然跨文件。净 −25 行，未动别的成员 |
| T3 额外删掉死存储 `start` / `now`；`rememberedProvider` 落为计算属性而非存储 | 时间闸门删除后两者已无读取点；计算属性便于读盘 + 白名单 |
| T4 实际新增 9 个本地化键（计划 5 个）；无号码证据时菜单只有 3 项 | 计划只列了必要键；「恰好 4 项」只对「单号码 + 单可打开候选」成立 |
| T5 用纯函数 `TodoText.groupHeaders(for:)` 取代计划里的视图 `groupHeader(key:count:)` | 让「哪些组渲染、各带几」进入运行时可断言面，去掉脆弱的源码 grep 断言 |
| T6（审查后）新增 `.choose` 与多候选逐条、抽 `MeetingActionMenuPresenter` | 修复终审发现的「多候选被静默折叠」，恢复 docs/45 已定的保证 → 记为 D-14 |

**遗留项**

- **人工上屏待复核（本次关闭时未做，需用户确认或豁免）**：右键菜单项数（3–4 项，视场景）且无「用 AI 识别会议」（V9）；首页点一下 = 打开或复制；面板/详情一行两键的像素形态（设计图 ④）；首页分组标题 `日程 · N` / `待办 · N`。
- **腾讯 `wemeet://` 真机唤起未验**（可选）：非官方对外文档，验不过即退回复制；已在「已知限制」登记。
- **华为深链真机入会未验**：只验了参数构造与自家校验通过。

## 已知限制

- 腾讯 `wemeet://page/inmeeting?meeting_code=` 来自腾讯云问答与 SDK `handleScheme` 文档，**不在腾讯对外 API 文档里**：未做真机验证（列在验证覆盖的**可选**项 V10）。能唤起就留，不能接受就退回复制——当前行为是「记不住就给复制」。
- 华为深链要求客户端已安装；`name` 必填（用 `NSFullUserName()`，空/空白回落 `Gourd`），入会显示名与客户端自身默认一致。只验了参数构造与自家校验通过，**未做真机入会**。
- 号码位数超出 9–12 位、或标签写法未收录时仍然只能复制（菜单会少一条「打开」）。
- **一条邀请里出现两个不同会议号时，只有第一个会被使用**（`code`/`codeValue`/`number(in:)` 取 `.first`，而 `resolve` 会把全部号码塞进每个候选）。D-14 的「多候选不猜」只覆盖可**打开**的候选。
- **面板/详情那一行没有右键菜单**：菜单是首页图标形态的交互；纯号码邀请在面板里要么先记住客户端（点一次「打开」即写入），要么回首页用右键。这是有意的取舍（面板宽度有限），指南亦不再暗示面板行有右键。
- `.row` 的「选择入口」每次点击新建一个 `MeetingActionMenuPresenter`（图标侧由 Coordinator 常驻持有），且该路径的 `CalendarTextInteraction` 依赖 `menuDidClose` 释放保护、未显式 `stop()`——今天无害，但两种生命周期并存。
- 首页那一行固定 34pt：结果只能由**图标自身**表达（转圈 / 对勾 / 感叹号）+ tooltip，放不下原因文字；面板 `.row` 有状态位与 `.help`。
- 记住的客户端是**全局**的（一个 `meetingCodeOpener` 键），不是「每条邀请各记一个」；指南已按全局口径表述。
- `.open` 的 tooltip 不带「· 右键更多」后缀（只有判不出平台的复制态带）——设计图 ② 画的是带后缀的版本，此处以计划文案口径为准。
- **本工作流的自动验证命令只跑 XCTest**，不含 `tests/test_general_ai_configuration.py` 这条真实的本地化/清单守卫（T4 新增键曾把它打红）。各任务已把它列入自检并跑绿，但**计划里的 `## 验证命令` 未覆盖它**——下次给这类改动写计划时应把该 Python 守卫并入验证命令。
- 首页分组标题走 `Bundle.main.localizedString`（而非 SwiftUI `Text(LocalizedStringKey)`）：前提是全仓没有运行时覆盖 `\.locale`；引入运行时切 locale 时这条会脱队。

## 2026-10-21 行标只按本条证据（用户反馈）

- 行标 provider 名只取**本条证据**：链接平台或原文里的平台标签；不再回落到全局 `meetingCodeOpener`。没有会议内容的记录、只有「会议ID」且没有平台标签的记录，不显示平台名（不会被默认贴成腾讯）。
- 原文含「化小易 / 华为云会议 / 华为会议 / WeLink」识别为华为；「腾讯会议」识别为腾讯；同一段出现多家视为判不出，不猜。
- 只有会议号且原文带平台标签时，主动作按该标签平台打开；判不出标签时才使用用户记住的客户端（D-09）。

## 验收标准

- 单元测试：正则/密码解析、URL 构造与校验、主动作选择、状态机与「记住客户端」、首页分组计数。
- Release 构建通过；用户上屏复核：首页点一下能打开或复制、右键 4 项、面板卡片一行两键。

## 决策摘要

| ID | 决策 | 来源 |
|---|---|---|
| D-01 | 一级动作 = 点一下直接执行（打开会议 / 复制会议号），不弹菜单、不弹页面 | 用户 |
| D-02 | 去掉「开始前 15 分钟才能打开」的时间闸门，随时可点 | 用户 |
| D-03 | 右键菜单只留 4 项：复制会议号 / 在腾讯会议中打开 / 在华为云会议中打开 / 复制邀请原文 | 用户 |
| D-04 | 删除「用 AI 识别会议」及其 AI 模型设置入口 | 用户 |
| D-05 | 会议号标签正则补 `腾讯会议`（覆盖不带井号的写法） | agent |
| D-06 | 按会议号打开：华为 `cloudlink` 官方深链、腾讯 `wemeet://`，参数白名单写死、号码 9–12 位 | 用户 |
| D-07 | 入会密码只用于华为深链的 `enter_code`，不新增复制项 | agent |
| D-08 | 入会显示名用 macOS 用户名（空则回落 `Gourd`） | agent |
| D-09 | 记住用户选过的客户端，下次同类邀请的主动作直接用它打开 | 用户 |
| D-10 | 结果由图标自身表达（转圈 / 对勾）+ tooltip，不加行内状态行 | 用户 |
| D-11 | 首页今日块分组标题带计数（`日程 · N` / `待办 · N`），表头保持 `0/2 · N 项日程` | 用户 |
| D-12 | 不改整体面板尺寸、不改 682 回落、不加日历页最小宽；编辑页另开工作流 | 用户 |
| D-13 | 面板卡片里的会议入口改成一行两键（provider + 号码 + 打开/复制） | 用户 |
| D-14 | **多候选不猜**：≥2 个可**打开**候选时主动作不打开（`.choose`，左键弹菜单），菜单逐条列出每个候选、不再折叠；1 个候选仍直接打开。恢复 docs/45「多候选须选择」 | agent（T6 终审 I-2） |
| D-15 | 本地化守卫 `tests/test_general_ai_configuration.py` 的消费者判据由子串 `key in sources` 改成精确字面量 `'"%s"' % key in sources`（防 `calendar.meeting.open` 借 `openIn.*` 前缀蒙混），并把该 Python 守卫纳入每任务自检 | agent（T6 审查 I-1） |
| D-16 | 记住的客户端只白名单 `huawei` / `tencent`，其它 rawValue 视为未记住 | agent（T3 审查 M-3） |
| D-17 | `.row` 按主动作画键：`.open → [打开, 复制]`、`.copyCode → [复制]`、`.choose → [选择入口]`、`.none → 不画键 + noEvidence 说明行` | agent（T4 审查 C-1/I-1） |
| D-18 | 面板 `.row` 同样有瞬时状态位 + 逐键 `.help`（让 D-10 在两种形态都成立） | agent（T4 审查 I-4） |
| D-19 | `MeetingJoinURLBuilder` **不**复核号码归属平台：`provider` 是调用方的断言；未判定平台时不得凭猜选客户端 | agent（T2 审查 I2） |
| D-20 | 入会密码只喂华为 `enter_code`，腾讯分支显式忽略 passcode | agent（D-07 的落地细节） |
| D-21 | 百分号编码用最小 unreserved 字符集写死（防显示名里的 `&`/`=`/`#` 改写参数结构）；已有变异验证的用例兜底 | agent（T2 审查 I1/M3） |
| D-22 | 打开失败回退口径：`.refused` 与 `.unavailable` 一并归入「退回复制号码」，只有连号码都没有才 `.failed` | agent（T2 遗留 / T3） |
| D-23 | 首页分组计数不进表头口径；「为空不画组」由纯函数 `TodoText.groupHeaders(for:)` 判定（可运行时断言，替代源码 grep） | agent（T5 审查 I-1） |
