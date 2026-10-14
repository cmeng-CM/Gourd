# 日历页面文字布局修复

| 项目 | 内容 |
|---|---|
| 状态 | 已实现并安装；后置证据待最终核验 |
| 最后更新 | 2026-10-14 |
| 来源 | docs/45、docs/39；用户再次报告详情竖线与列表标题越界，并确认全页复现、截图验证和重新安装 |

## 一句话方案

文字测量使用独立排版环境，不修改可见文字容器；以完整日历页面验证容器宽度、标题边界和全量滚动，再安装。

## 背景与目标

承接docs/45的真选区、复制独立导航与原文/备注编辑，以及docs/39的单草稿和全量滚动。上一轮TextKit初始化及UTF-16选区修复已经交付，但827项测试不覆盖真实页面尺寸协商。用户截图显示详情正文近似竖线、列表多行标题与会议操作重叠。

完整StandaloneCalendarView→CalendarPanelPages探针确认：NSHostingView查询fittingSize后，可见frame宽374而文字容器宽200。模拟布局日志中存在的零宽探测作为最后一次测量，会把容器宽改为1，并得到同形竖线截图。这是故障注入及测量副作用的证据；尚未证明生产最后一次零宽提案的具体顺序。

## 做法

测量从当前内容/样式快照创建独立TextKit排版，不改可见容器、frame、选区或编辑存储。可见排版只跟实际分配的bounds同步。SwiftUI负责文字区域高度；原生视图不能自行扩张到卡片或邻接按钮之外。保留两行预览与完整标题偏好，详情全文及长原文/备注通过原外层ScrollView可滚达。

页级验证使用受控CalendarManager/service/session与真实生产页面，覆盖列表→详情→返回、窄宽变化、零/未指定/正常提案、重复刷新、两行/完整模式、长备注滚至末尾与编辑输入。直接构造控件的八例旧回归继续保留。每张截图注明生产源、测试依赖替身、提案序列和状态，避免把模拟故障说成自然复现。夹具采用独立应用偏好域及固定中文、本轮日期和时区；至少两张含会议入口的相邻卡，分别验证两行与完整标题、黑/灰背景、列表/详情/返回、窄宽变化、末尾滚达以及原文/备注输入，缺项不能静默跳过。

## 备选与取舍

- 继续修改live container再恢复：异步绘制与布局查询会交错，留下窄容器风险，因此选择独立测量。
- 固定所有标题/备注高度：会截掉完整内容，不采用。
- 整体换成不可选SwiftUI Text：会损失既定复制交互，不采用。

## 接口与数据形状

保持CalendarSelectableText、CalendarGrowingTextEditor和CalendarPanelPages现有用户接口。新增内部测量实现及页级探针，不新增产品设置、模型协议或日历字段。测量输出有限CGSize，live TextKit的容器宽度与最终bounds扣除既有textContainerInset的有效宽匹配（只读inset0、编辑左右各4）；UTF-16相同更新保选区规则继续沿用。

截图证据包含输入源码摘要、实际Debug产品、fixture依赖和执行命令、文件SHA、尺寸及测量/路由序列。夹具只替代非布局的服务与应用生命周期；必须逐项披露替身和未覆盖的实际宿主行为。初步探针需明确补齐本地化及真实卡片代码，不能用另写的相似VStack代替完整页面。

## 明确不做

不改变AI解析、会议打开、EventKit保存和屏幕助手，不修改真实会议/日历数据；不操作鼠标或系统设置，不运行旧UIRunner。原四类别人工验收与真实入会/线上模型质量仍不由离屏截图证明。

## 实际交付

T1 已实现独立 `NSTextStorage → NSLayoutManager → NSTextContainer` 快照测量。快照复制文本属性、行数上限和换行规则；零/负宽归一为1，非有限宽回退200，返回有限自然高度。测量不写live存储、选区、frame或container。两个native视图在实际frame变化及layout时按bounds扣除左右inset同步容器（只读0、编辑4+4）。

两个native视图的 `isVerticallyResizable` 改为false，SwiftUI的自然测量负责增长；layer边界与draw裁剪阻止原生绘制跨slot。旧八例保留，两个技术flag断言更新为false；增加 `CalendarPageLayoutTests` 三例覆盖测量纯度、两行/全文自然高度和多行实际输入Binding及不自主增长。卡片与页面布局源码无需改动：移除测量副作用并由SwiftUI单独分配高度后，真实卡片/邻接按钮边界矩阵通过，未用固定高度替代全文。

`tools/calendar-page-layout-probe.py --help` 提供明确的 `--debug-products` 与 `--output` 参数；可用 `--baseline-ref 417a7ee7` 生成旧源反事实失败对照。探针原样编译两个native控件、页面、会议入口与抽取的真实 `CalendarEventCard`、`StandaloneCalendarView`，链接指定Debug dylib的真实日期/模型/月历/service/session实现。隔离VM/Coordinator、editor生命周期/window reader；注入memory backend，四个偏好使用独立fixture suite并恢复，初始月固定为2026-10-14。卡片背景GeometryReader仅观测bounds，不参与尺寸分配。bare隐藏窗口从未orderFront/激活；原产物中文lproj、zh-Hans/AsiaShanghai环境用于呈现。

研究冻结材料证明实际fitting查询的live变化；T1旧源反事实四组均exit1，min提案注入后的纯度/有效宽等断言失败，而这组矩阵的natural fitting前后检查未失败，不能混为自然末次零宽复现。新源四组包含两行/全文、黑/灰、640/800/1000宽、list/detail/detail-mid/tail/back和原文/备注实际输入。native有效宽、真实card/title/meeting范围、两行/全文高度、全文保留、scroll可见字符范围与PNG可见墨迹均为必过断言；图像墨迹检查不依赖sandbox不可用的Vision服务。清单绑定源码、generated/tool/executable、实际Debug app/dylib/resources和PNG/geometry散列。T1阶段使用本日研究Debug支撑依赖；后续新完整宿主门、新Debug最终图、独立审查与安装事实见T2记录，不以研究Debug替代最终产物。

## 已知限制

真实全页离屏探针使用源码装配与明确的VM/生命周期隔离，与正在运行的AppMain/ContentView不同；源码中的布局表达式保留，卡片GeometryReader属于观测插桩。旧editor仅在baseline比较时暴露原 `sizeThatFits` 的逐字计算为测量入口；此插桩也写入manifest。灰背景是受控灰色承载，不代表实际liquid-glass系统合成器。图像可见墨迹与几何、实看共同验证，像素分布本身不识别文本语义。

自然停留零宽的最后调用顺序与用户原列表越界均未自然复现。旧源的width=1截图是明确的故障注入，不能标作正常生产窗口复现；实际fitting查询污染live的证据与其分开记录。修复已证明的测量副作用并控制原生自主resize/绘制边界，不宣称已证实全部列表越界根因。真实入会、模型质量、系统写入和安装后人工交互仍需原有验收。

## 验收标准

| 对象 | 可观察证据 |
|---|---|
| 测量纯度 | 已布局的真实文字区域在零宽/ideal查询后，live容器、frame、文本与选区保持；旧源码失败，新源码通过 |
| 列表 | 两行模式不越卡片，完整模式随内容长高；正文不覆盖会议按钮/时间/下一条 |
| 详情 | 标题、日历、地点和备注可见；合法宽度与实际bounds一致，长备注末尾可滚达 |
| 页面状态 | 列表/详情/返回及宽度变化后截图正常，编辑原文/备注可输入并保持草稿 |
| 交付 | 新完整XCTest/Python/Release签名、独立审查、当前源码与页面图绑定、安装字节与真实新进程 |

## 决策摘要

| ID | 决策 | 来源与理由 |
|---|---|---|
| D-01 | 本轮按全页复现、显示/边界/滚动修复、截图验证后重新安装 | 用户2026-10-14确认 |
| D-02 | 保留真选区、草稿和两行/完整偏好，不固定死长内容高度 | 承接用户已批准docs/39、docs/45 |
| D-03 | 测量不污染可见排版，实际bounds控制显示 | 已实测frame/container不一致与模拟零宽竖线；内部技术裁定 |
| D-04 | 图像与几何都验收，依赖替身与故障注入如实标注 | 前轮控件通过但页面仍坏的覆盖缺口 |
| D-05 | 新完整自动证据与整体审查后安装，不把旧827当本轮通过 | 用户确认测试/重新安装边界 |
| D-06 | 允许单任务七路径原子贯通控件、页面、真实探针、回归和记录 | 同一文字布局链；避免先改组件后遗漏页面覆盖 |

### T1 独立审查补验

独立审查 `T1-review.md` 的 I-01 指出：原56图只证明详情地点挂载，没有地点可见截图，不能由初始详情与尾部截图推断中段已验收。探针补齐每种宽度/标题/背景的 `detail-mid`，按真实地点native几何滚至中段；地点全文与备注第1、2行分别要求完整字符范围在所属scroll的 `visibleRect` 与截图范围内，且对应PNG墨迹必须通过。现四组各17场景，共68图、1888断言通过；这项补验没有更改生产源码、页面高度或既有断言。这项T1复审随后通过0/0/0；最终新Debug矩阵及独立审查另见T2记录。

## T1 机制裁定

| 对象 | 实际选择与依据 | 代价 |
|---|---|---|
| 测量接口 | 两个native控件共用内部 `CalendarTextMeasurement.size(of:width:minimumHeight:)`；外部用户接口保持 | 每次查询分配独立TextKit快照，避免恢复live状态的交错风险 |
| 原生高度 | SwiftUI独占承载高度，AppKit不垂直resize；新增实际多行增长、Binding与边界断言承接原行为 | 离屏图不能证明用户全部键盘/选区交互 |
| 卡片/页面 | 保留现有布局、两行/全文偏好和单外层ScrollView；无需修改这两个生产文件 | 原列表越界的自然触发顺序仍未知 |
| 图像证据 | 实际页PNG、card/native几何、可见墨迹和尾字符可滚达均检查；独立controller实看 | 使用隔离支撑依赖且灰色backing不是系统玻璃；T2已按新成功attempt的Debug重跑 |

## T2 证据状态与核验契约

T1 独立复审已通过（Critical/Important/Minor=0/0/0），复审覆盖新增中段地点与备注首段截图、完整68图和散列。当前本日研究Debug矩阵只属于T1证据；T2新完整宿主门现已取得成功attempt；新Debug最终页图的审阅摘要绑定、安装前整体终审、安装与真实新进程事实已记录；安装后文档差量的同一审查者复核与最终engine仍待完成。

交付核验器 `.workflow/calendar-page-layout/verify_delivery.py` 采用只读检查：先运行ai-calendar wrapper的证据复核，要求新attempt实际执行至少830个XCTest，8个原生与3个布局测试各方法在实际日志中恰好通过一次；独立T1/T2规格与质量JSON、整体ready JSON及报告摘要严格绑定baseline/HEAD。最终page-evidence必须包含四设置×17场景、全部源码/工具/generated/probe/新Debug app/dylib/resources/PNG摘要、严格True几何检查和根控制器28张代表原图的实看记录（四设置各7路由、合计覆盖三种宽度）；独立复审另须实看全部68张最终图。

安装沿现有七个命名checks、六个实际命令与日志摘要，以及installed snapshot/实时签名；新增进程证明必须来自精确PID的kernel ps（pid/start/comm），核旧进程不再运行和新PID的实际安装路径，不能用NSWorkspace缓存替代。后置仅允许docs/45与docs/46的祖先提交，逐提交检查禁止隐藏中间源码变化；纯文档回写不触发新的宿主循环。Ignored控制核验器本身的SHA写入T2与整体独立审查报告，核验时也必须匹配。缺失/空数组/假布尔值/错hash/路径逃逸/旧Debug或绑定错均拒绝，尚缺证据时不会宣称交付完成。

安装前执行记录：attempt `20261014T105658-28731d1e7f81437b89ec341b1fadb2df` 的XCTest实际830执行/0失败/0跳过，Python、Release与签名各阶段退出0，但完整wrapper末端因根目录 `default.profraw` 摘要变化而判定failed，不能用于交付。控制器定位为并行Debug页探针退出时的默认LLVM覆盖率输出；保持冻结生产源/探针，后续执行将由调用环境把 `LLVM_PROFILE_FILE` 定向至各页证据目录，并重新获取成功attempt及其实际Debug最终图。旧attempt和旧68图只保留为失败运行记录，不重标success或混入新最终证据。

安装前新完整门：attempt `20261014T110220-86f83961f6a1436a97866a52ca3e4750` 最终succeeded；XCTest实际830执行/0失败/0跳过，8个原生测试与3个布局测试各方法在实际日志中恰好通过一次，Python11例，十个阶段均退出0（包含Release与Debug/Release签名核验）。控制器在本次宿主启动前后精确查询Pear均false，未启动Pear。生产与探针源码仍冻结于T1，后续仅文档回写无需再运行宿主。

最终页证据位于 `.workflow/calendar-page-layout/reports/page-evidence/manifest.json`，使用上述成功attempt的实际Debug产品，并由调用环境将 `LLVM_PROFILE_FILE` 定向至页输出目录，根 `default.profraw` 保持稳定。当前干净重生成矩阵四组各17场景，共68 PNG/1888断言无失败；根控制器28张代表图记录已重绑最终manifest摘要，独立复审也核实全部68图与已实看图SHA一致，并验证新Debug/本地化/几何；没有套用旧manifest绑定。安装前整体终审已通过，安装事实另列如下；这些页级检查仍不等于完整产品人工验收。

页探针运行约束：output应为fresh目录，或至少不存在旧 `manifest.json`。producer收集输出文件时会把已有manifest本身纳入files，造成自摘要不一致；控制器的调用guard先保存旧manifest到输出目录之外，再删除自有ignored旧manifest后干净重生成。这是证据输出管理，不改变生产布局、冻结探针或产品行为；重跑页面不等于重跑宿主完整门。

### T2 安装与实际启动记录（后置文档复核待完成）

安装前整体独立审查覆盖 `417a7ee7..ea332b64`，Ready=Yes，Critical/Important/Minor=0/0/0。控制器随后按已验证成功attempt的Release执行 `tools/build.sh --install`；`local-install.json` status=succeeded，七个命名checks均严格true、六个命令均退出0。源产物安装前后匹配proof，安装包通过deep/strict与Gourd Local签名；Info仅 `CFBundleName` 改为“壶中天”，非签名资源/链接/模式及临时移除签名后的执行文件与已验证源产物相同。

`installed-snapshot.json` 绑定attempt `20261014T110220-86f83961f6a1436a97866a52ca3e4750`，digest=`c80c17e6797efe280079497bd0a1e85567daad39c1a0c51ba3aed359f70c0c98`。`new-launch.json` 与日志记录kernel ps事实：旧PID57700已退出，新PID6883于2026-10-14 11:20:35启动，实际可执行路径为 `/Applications/壶中天.app/Contents/MacOS/Gourd`，不以NSWorkspace缓存证明重启。

本次回写仅docs/45与docs/46，不改冻结生产源、探针或交付核验器；安装证据保留实际安装head `ea332b64`，通过纯文档祖先链允许后置回写，不伪改为新head。同一整体审查者将复核文档/安装差量后重绑最终JSON；最终engine verify/close尚未在此宣称通过。原四类别安装后人工确认、真实模型/会议/系统写入验证仍未完成，安装和kernel新进程不替代这些人工项。
