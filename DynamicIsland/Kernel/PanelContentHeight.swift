// Modified for Gourd (2026-10-01)
// Copyright (C) 2026 Gourd Contributors
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
//

//
//  PanelContentHeight.swift
//  Gourd 宿主 · 展开面板的高度账本（p5-home-blocks / T7）
//
//  docs/29 §做法 机制六 / §接口与数据形状。**两个来源、一个出口**：
//
//  - **首页**那一份是**算**出来的：`HomeBandedHomeView` 把流方案的 `heightUsed` + 日历行 + 缝 +
//    表头算好后写 `setHomeContentHeight(_:)`（T6 的收敛与「光标在面板内不缩」都在那一侧做完，
//    账本不参与、也**不覆盖**它——它只在首页那一页有效）；
//  - **其它 tab**那一份是**量**出来的：内容随条数变的模块页在根部挂
//    `panelContentHeightReport(tab:headerHeight:isCurrent:)`（本文件下半部分），量的是这一页的
//    **理想高**（`Layout` 的 `.unspecified` 提案，与面板当前多高**无关**——拿「摆放后的高」当自然高
//    就是反馈环：整页填满内容区时它的值恒等于当前面板高，缩小一次就再缩不回来）。
//
//  尺寸层只读 `current`（`matters.swift` 的 `openNotchSize` → `PanelAutoHeight.panelHeight(...)`）：
//  两路都折成同一个口径「内容高（**含面板表头**）」——`panelHeight(...)` 再加 `homeVerticalPadding`
//  就是面板高（T6）。测量值进账本前按 `PanelAutoHeight.measuredContentHeight(naturalHeight:headerHeight:)`
//  折（非首页 tab 少了 `NotchHomeView` 那一份 16pt，那里写明）。
//
//  **四条款**（`report(_:for:)`，docs/29 §做法 机制六 与派发片段的裁决）：
//  ① 非有限值忽略；② **同一 tab** 的高度差 < 8pt（`hysteresis`）忽略；③ **换 tab 无条件接受**
//  （含「光标在面板里」那一档——不然点在 tab 上的那只手永远等不到面板变矮）；
//  ④ 同一 tab 且**光标在面板 frame 内**时只接受变大的值（不把面板从光标底下抽走，§已知限制 1）。
//
//  **谁上报**（`measuredTabs`，逐条写理由）：
//  待办 / 通知 / 启动台 / 快捷指令 / 架子 / 日历——前四页的内容是**行数 / 格子数**的函数（自然高与
//  面板无关）；架子（`shelfTab`，p6-ui-polish / T6 进名单）是「投放格 + 文件格网格」，格数决定
//  行数、行数决定高，纵向 `ScrollView` 的理想高就是网格自然高——**不再是**旧版面那个「拖放区整块
//  填满」的形状（旧判断见 `measuredTabs` 的注释）。日历（`CalendarModule.moduleID`，
//  p6-ui-polish / T8 进名单）T8 起是两栏自然布局：左栏月网格按固定格高自然堆叠（`36N + 52`）、
//  右栏在其高内滚动——自然高 = 当月周数的函数，**不再是**旧版面那个「自己的高是面板高的函数」
//  的形状（`GeometryReader + paneHeight`；旧判断同样见 `measuredTabs` 的注释）。
//  **不上报的两页**：计时器（`.frame` 吃面板高 + 250 的 per-tab 下限）、终端（终端仿真块按屏高
//  比例，本来就没有自然高）。
//
//  **切页时谁说了算**（`selectTab(_:)`，T7 复核 P1）：换页**不只是换「值从哪来」**——名单外的页
//  必须**没有值**（`current` = nil → 尺寸层回落**手动值** = 今天的行为，宽松够用），否则会继承
//  上一页量出来的高度（首页 → 待办 ~200 → 计时器 / 终端：按 200 的画面高铺两排不可用）。名单**内**
//  的页保留上一页量出来的那一个数，直到新页量完——**且新页的第一份上报
//  无条件接受**（`awaitsFirstReport`：留着的那个数与新页无关，拿它比出来的差不是「同一页的微动」，
//  光标还压在面板上时也不该拦），因此是**一次**跳动而不是两次（若切页就清值会先跳手动值再跳量值）。
//
//  触发链（派发片段裁决 5）：接受一个新值时 `objectWillChange` 响一次，`DynamicIslandApp` 收到后
//  走**既有的** `debouncedUpdateWindowSize()`（0.15s 防抖那条，T6 接好的）——**不新开第二条 resize
//  链**；切 tab 那一刻的尺寸由既有 `updateWindowSizeForTabSwitch()` 经 `openNotchSize` 读本账本
//  （读到的就是 `selectTab` 刚定下来的那一份）。
//
//  **切页平滑三件**（p6-ui-polish / T7，docs/30 §做法 机制五；动画面在 `DynamicIslandApp` 那一侧）：
//  - **每页高度缓存**（`heightCache`）：每次**接受**上报都写；`selectTab(_:)` 对名单内的页直接读它
//    ——量过的页切回来**一步到位**（零次跳动），且它的第一份上报**回普通条款**（8pt 滞回 + 光标规则：
//    起点已是这一页自己的量值，差 < 8pt 的那点微跳不该再推第二次窗口，T7 裁决 T7-fix）；没量过的页
//    仍走「留上一页的量值 + 首份上报无条件」那条旧路径（名单外的页照旧清值回落手动值；缓存按页
//    留着，切回来还在）；
//  - **切页首报免防抖**（`lastChangeWasTabSwitch`）：`selectTab` 换掉当班值、或新页的**第一份**上报
//    被接受时置位。订阅见到它就不走 0.15s 防抖，改用**同一条**立即链（`updateWindowSizeForTabSwitch`，
//    内部延后一拍读新值）——**不新开 resize 链**；
//  - **就绪门**（`isTabReportReady`，宿主注入）：这一页此刻还**没有可量的内容**时探针不上报
//    （启动台 `apps` 首轮扫描完成前页面上是 loading / 空态占位，量它 = 首开「先塌陷再长高」三拍）。
//

import CoreGraphics
import Foundation
import SwiftUI

/// 展开面板的高度账本（`@MainActor` 单例，docs/29 §接口与数据形状）。
@MainActor
final class PanelContentHeight: ObservableObject {

    static let shared = PanelContentHeight()

    /// 首页那一路的键。首页**不走上报**（它有算出来的那一份，见 `setHomeContentHeight(_:)`）。
    static let homeTab = "home"

    /// **侧歌词档首页**的键（p5-home-blocks 终审 T-final，docs/29 §决策摘要 D-57）。
    ///
    /// `NotchHomeView` 的第二支（歌词 + 音乐 + 镜子）**没有自己的内容高**——写首页那一份的接缝
    /// （`HomeBandedHomeView`）不在屏幕上。落在首页键上，`current` 就会拿「上一次标准首页算出来的
    /// 值」当内容高（auto 档下面板高度 = 那个值 + 40，与侧歌词无关；且把手隐藏、滑块禁用，用户
    /// 没得改）。因此给它一个**没人上报**的键：`selectTab(_:)` 走到「名单外」那一档 →
    /// `current` = nil → 尺寸层回落**手动值**（D-45 对日历 / 计时器 / 终端同一条口径）。
    /// 判据（哪一支在屏幕上）由 `showsSideLyricsHomeLayout(...)` 给，标准路径的首页键逐字不变。
    static let sideLyricsHomeTab = "sideLyricsHome"

    /// 同一 tab 的滞回阈值（pt）：差在这个以内不改窗口（`docs/29 §做法 机制六` 的 8pt）。
    /// 秒数跳动这类「同一 tick 里十几分之一 pt」的微动因此不会碰窗口。
    static let hysteresis: CGFloat = 8

    /// 架子页的键（p6-ui-polish / T6。`ContentView.selectedPanelTabKey` 对 `.shelf` 传的
    /// 就是这个字面量，探针在 `NotchShelfView` 里用同一个常量挂上——两边不各写一份字符串）。
    static let shelfTab = "shelf"

    /// **有自然高、因此上报**的模块页（`ModuleHostView` 渲染的那几个 tab 的键 = 模块 id）
    /// 与**宿主页**（架子）。
    ///
    /// 判据是「这一页的自然高是不是**内容**的函数，而不是**面板**的函数」：
    /// - `todos`：表头 + 清单行（行数决定高）；
    /// - `notifications`：表头 + 通知行 + 脚注（条数决定高）；
    /// - `launcher`：搜索框 + 应用网格（App 数决定高，最高到上界后网格自己滚）；
    /// - `shortcuts`：表头 + 清单 + 结果行；
    /// - `shelf`（宿主页，键 `shelfTab`）：投放格 + 文件格网格（格数决定行数、行数决定高；
    ///   纵向 `ScrollView` 的理想高 = 网格自然高）。T6 前的「暂存器没有自然高」是**旧版面**
    ///   的判断（左投送块按容器高撑成正方形、文件区一行横滚）——投放格缩成一枚格子、
    ///   文件区改多行网格后，这一页的高就是内容高（docs/30 §做法 机制三）。
    /// - `calendar`（模块 id `CalendarModule.moduleID`，p6-ui-polish / T8）：两栏自然布局——
    ///   左栏月网格按**固定格高自然堆叠**（高 = `36N + 52`，与首页日历行同源
    ///   `MonthGridLayout.monthGridHeight`），右栏事件列拿同一个高度、在里面滚动；
    ///   这一页的高因此是「当月周数」的函数。T8 前的「日历没有自然高」是**旧版面**的判断
    ///   （`GeometryReader + paneHeight` 两栏填满面板高，探针按无高提案只会量到 10pt 级理想高、
    ///   面板落到手动回落值——682 空半屏）；改成自然布局后与上面几页同一口径
    ///   （docs/30 §做法 机制六）。
    ///
    /// 另外两页（`timer` / 终端）**刻意不在名单里**，理由逐条写在文件头。
    /// 名单外的 tab 不产生值：切到它们时 `selectTab(_:)` 把量出来的那份清掉 →
    /// 尺寸层回落手动值。
    static let measuredTabs: Set<String> = [
        "com.cmeng.gourd.todos",
        "com.cmeng.gourd.notifications",
        "com.cmeng.gourd.launcher",
        "com.cmeng.gourd.shortcuts",
        shelfTab,
        // p6-ui-polish / T8：两栏自然布局（左栏固定格高月网格、右栏在其高内滚动）——高 = 当月周数
        // 的函数。用模块 id 常量（不写第二份字面量）：`ContentView.selectedPanelTabKey` 的
        // `.module` 分支传的就是它。
        CalendarModule.moduleID,
    ]

    /// 这一页要不要上报（`nil` / 空串 = 还没选中模块 → 不上报）。
    static func isMeasuredTab(_ tab: String?) -> Bool {
        guard let tab, !tab.isEmpty else { return false }
        return measuredTabs.contains(tab)
    }

    /// 光标在不在面板 frame 里（条款 ④ 的判据）。**宿主注入**：`DynamicIslandApp` 接上宿主既有的
    /// `vm.isMouseHovering()`（`NotchHomeView` 给首页那条路用的同一条判定，不另写一份几何）。
    /// 默认「在外面」——测试与还没接上时**不拦任何变化**（比默认「在里面」保守：后者会让面板
    /// 永远只增不减）。
    var pointerInsidePanel: @MainActor () -> Bool = { false }

    /// 这一页此刻**能不能上报**（就绪门，p6-ui-polish / T7 机制五）。**宿主注入**：默认「都能」。
    ///
    /// 唯一的用例是启动台——`apps` 首轮扫描完成前页面上是 loading / 空态占位，**那不是这一页的
    /// 自然高**（进了账本 = 首开「先塌陷再长高」的三拍）。判据（扫完没有）住在模块侧
    /// （`LauncherModule.hasLoadedApps`），宿主把它按 tab 接进来；账本不认模块类型、也不存第二份
    /// 状态，只留一个判据闭包——与 `pointerInsidePanel` 是**同一条注入形态**（默认值也一样：
    /// 没接上时不拦任何上报，测量链条退回改动前的宽松口径）。
    var isTabReportReady: @MainActor (String) -> Bool = { _ in true }

    /// 上一次**被接受**的页（`report` 的 tab、或 `selectTab(_:)` 定下来的页）。`current` 靠它二选一。
    private(set) var activeTab: String?

    /// 量出来的那一份（`activeTab` 是名单内某一页时的 `current`）。`private(set)`：写入口只有
    /// `report` / `selectTab`，读出来是给用例与排查看的（生产读者一律走 `current`）。
    private(set) var measuredHeight: CGFloat?

    /// **每页量出来的高度**（p6-ui-polish / T7 机制五）：`report(_:for:)` 每次**接受**一个值就写进来，
    /// 于是「切回量过的页」不必先落在上一页的量值（或手动值）上再跳一次——`selectTab(_:)` 直接读它，
    /// **一步到位**。没量过的页没有条目 → 仍走旧路径（留上一页的量值 + 首份上报无条件接受）。
    ///
    /// 名单外的页（计时器 / 终端）不上报，因此**不会**有条目；缓存按页留着（切到名单外的页只
    /// 清「当班值」，不清别人的缓存）。**不是第二份「当前值」**：`current` 仍由 `activeTab` +
    /// （`homeContentHeight` / `measuredHeight`）二选一决定，缓存只改「切页那一刻的起点」。
    private(set) var heightCache: [String: CGFloat] = [:]

    /// 最近一次写入口之后，**这一声 `objectWillChange` 是不是「切页那一拍」**（T7 机制五的免防抖标记）。
    ///
    /// 「切页那一拍」两档：① `selectTab(_:)` 把当班值换成了另一页的（缓存一步到位 / 名单外清值 /
    /// 首页槽换了值）；② 新页的**第一份**上报被接受（`awaitsFirstReport`）。这两种变化都不该等
    /// 0.15s 防抖——页面已经换了，窗口晚一拍跟上就是用户说的「卡顿」。消费方
    /// （`DynamicIslandApp` 的订阅）**在 `send()` 的同步回调里**读它，见到为真就走**同一条**立即链
    /// （`updateWindowSizeForTabSwitch`，内部延后一拍读新值），**不新开 resize 链**。
    ///
    /// **一次性**：每个写入口（`report` / `selectTab`）**开头**先清掉，只有本次真的发出一声
    /// `objectWillChange` 且属于上面两档时才置位（被四条款拦下、或值没变的静默写因此读出来是假；
    /// 测试直接读它，生产读者只在订阅回调里读）。
    private(set) var lastChangeWasTabSwitch = false

    /// 刚切到一个**会上报、且还没量过**的页（`selectTab` 置位）：它的**第一份**上报要**无条件**接受
    /// （派发片段条款 ③ 的「换 tab 无条件接受」），滞回与光标规则都不参与。
    ///
    /// **缓存命中的页不置位**（T7 裁决 T7-fix）：`selectTab` 已经把起点放在这一页**自己的**量值上，
    /// 与它比出来的差就是「同一页的微动」——第一份上报因此回普通条款（8pt 滞回 + 光标规则），
    /// 差 < 8pt 的那点微跳不再推第二次窗口（「单步」目标）。
    ///
    /// 为什么需要这个位：切页时特意**保留**上一页的量值（一次跳动而不是两次），于是新页的第一份
    /// 上报与旧值之间「看起来像同一 tab 的微动」——少了这个位，光标停在面板里时新页连变矮都做不到
    /// （条款 ④ 拦下），滞回也会把小于 8pt 的差整个吃掉。位是**瞬时**的（消费一次即清）。
    private var awaitsFirstReport = false

    /// 首页**算**出来的那一份（含表头，口径见 `PanelAutoHeight.contentHeight(from:...)`）。
    ///
    /// **权威**：只有首页那一页写它，量出来的值一律碰不到它（派发片段裁决 4）。**刻意不发通知**：
    /// 首页的内容一变，T6 那五条 publisher 与「打开面板后一拍」已经会把窗口尺寸重算一次，
    /// 这里再响一次就是第二条 resize 链（裁决 5）。
    ///
    /// **也不碰 `activeTab`**（T7 复核 P2）：写入方是视图 body，切 tab 的过渡里旧首页还可能再跑一次
    /// body——若它顺手把「当前页」改回首页，刚量完的模块页就被顶掉了（面板跳回上一页的高度）。
    /// 「当前是哪一页」只由 `selectTab(_:)`（宿主按选中页声明）说了算。
    private(set) var homeContentHeight: CGFloat?

    /// 尺寸层读的那个值：首页 → `homeContentHeight`；名单内的页 → 量出来的那一份；
    /// 还没人写过 / 量过、或**当班的是名单外的页** → `nil`（尺寸层回落手动值，§已知限制 2）。
    var current: CGFloat? {
        guard let activeTab else { return nil }
        return activeTab == Self.homeTab ? homeContentHeight : measuredHeight
    }

    private init() {}

    // MARK: - 写入口

    /// **切页**（宿主在选中页变化时声明；`tab` = 选中那一页的键，`""` = 还没选中任何页 → 不声明）。
    /// `ContentView` 的展开分支每帧调一次（幂等：同键直接返回）。
    ///
    /// 三档（口径见文件头「切页时谁说了算」）：
    /// - 首页键 → `current` 读 `homeContentHeight`（首页自己在 body 里写）；
    /// - 名单**内**的页 → **量过的**直接读 `heightCache[tab]`（T7 机制五，**一步到位**）；
    ///   没量过的保留上一页量出来的值（新页量完那一拍无条件覆盖它，一次跳动）；
    /// - 名单**外**的页 → **清掉**量出来的值 → `current` = nil → 尺寸层回落手动值
    ///   （缓存按页留着：切回来还是量过的那一份）。
    func selectTab(_ tab: String) {
        guard !tab.isEmpty, tab != activeTab else { return }
        let isHome = tab == Self.homeTab
        let isMeasured = Self.isMeasuredTab(tab)
        // 缓存一步到位（T7 机制五）：量过的页用上次被接受的那一份；没量过的页 `cached` = nil →
        // 仍是旧路径（留上一页的量值，等首份上报）。名单外的页不读缓存（照旧清值）。
        let cached = isMeasured ? heightCache[tab] : nil
        let newCurrent: CGFloat? = isHome ? homeContentHeight : (isMeasured ? (cached ?? measuredHeight) : nil)
        lastChangeWasTabSwitch = false
        if newCurrent != current {
            // 切页那一拍：订阅见到这个标记就走立即链（免防抖），不等 0.15s。
            lastChangeWasTabSwitch = true
            objectWillChange.send()
        }
        activeTab = tab
        // 名单内：缓存的页一步到位；没缓存的页留着上一页的量值（一次跳动）——但它的第一份上报
        // 无条件接受（`awaitsFirstReport`）。名单外：清值 → `current` = nil → 尺寸层回落手动值。
        //
        // **缓存命中的页不置位**（T7 裁决 T7-fix）：豁免的存在理由只是「留着的那份属于**别的**页，
        // 拿它比出来的差不是同一页的微动」；缓存命中时起点就是这一页自己的量值，比较重新有意义——
        // 第一份上报回普通条款（8pt 滞回 + 光标规则），免得差 < 8pt 时还多推一次窗口（微跳）。
        awaitsFirstReport = isMeasured && cached == nil
        if let cached {
            measuredHeight = cached
        }
        if !isHome, !isMeasured {
            measuredHeight = nil
        }
    }

    /// 首页那一份（`HomeBandedHomeView` 的接缝写）。T6 的持有者升级成这个槽：
    /// `nil` = 还没算过（首帧）→ 尺寸层回落手动值。
    ///
    /// **只写槽、不改 `activeTab`**：当班与否由 `selectTab(_:)` 声明（见 `homeContentHeight` 的注释）。
    func setHomeContentHeight(_ height: CGFloat?) {
        homeContentHeight = height
    }

    /// 非首页 tab 的上报（四条款见文件头）。`height` 是**内容高口径**（含表头）——调用方按
    /// `PanelAutoHeight.measuredContentHeight(naturalHeight:headerHeight:)` 折好再报。
    func report(_ height: CGFloat, for tab: String) {
        // 免防抖标记**一次性**：每次写入口（本函数 / `selectTab`）开头先清掉，只有本次真的发出一声
        // `objectWillChange` 且属于「切页那一拍」时才重新置位（见 `lastChangeWasTabSwitch`）。
        lastChangeWasTabSwitch = false
        // 条款 ①：非有限值忽略（首帧的 0/NaN 不会把面板打掉）。
        guard height.isFinite else { return }
        // 首页那一份有自己的槽（算出来的），上报路径不接它的键。
        guard !tab.isEmpty, tab != Self.homeTab else { return }

        // 条款 ③：换 tab 无条件接受——**在光标规则之前**判，否则「点 tab 那只手」停在面板里，
        // 面板就永远等不到变矮那一拍。
        if tab != activeTab {
            accept(height, for: tab)
            awaitsFirstReport = false
            return
        }

        // 刚切到这一页的第一份上报：同样**无条件**（切页时留着的是上一页的量值，与它比出来的差
        // 不是「同一页的微动」，见 `awaitsFirstReport`）——而且它是**切页那一拍**：订阅见到标记就
        // 走立即链（免防抖），新页量到的那一拍窗口马上跟上（T7 机制五）。
        if awaitsFirstReport {
            awaitsFirstReport = false
            accept(height, for: tab, isTabSwitchFirstReport: true)
            return
        }

        // 同一 tab：第一次报（同一 tab 但还没有值）直接接受。
        guard let previous = measuredHeight else {
            accept(height, for: tab)
            return
        }

        // 条款 ②：滞回——差 < 8pt 不改窗口。
        guard abs(height - previous) >= Self.hysteresis else { return }

        // 条款 ④：光标在面板 frame 内时只接受**变大**（不把面板从光标底下抽走）。
        if height < previous, pointerInsidePanel() { return }

        accept(height, for: tab)
    }

    /// 只给测试用（把单例恢复到「什么都没有」的出厂态）。
    func reset() {
        activeTab = nil
        measuredHeight = nil
        homeContentHeight = nil
        awaitsFirstReport = false
        heightCache = [:]
        lastChangeWasTabSwitch = false
        pointerInsidePanel = { false }
        isTabReportReady = { _ in true }
    }

    /// 接受一个新值：**`current` 真的变了**才响一声 `objectWillChange`（尺寸层据此走 0.15s 防抖那条
    /// 既有的 resize 链；同 tab 内 8pt 以下的微动与「值没变」的切页因此一次都不响）。
    ///
    /// `isTabSwitchFirstReport` = 本次是「新页的第一份上报」（T7 机制五）→ 这一声通知配
    /// `lastChangeWasTabSwitch` 标记，订阅据此走立即链（免防抖）。
    ///
    /// 用户可见的落点：**每次接受都写 `heightCache`**（包括这一档）——下一次切回这一页就是一步到位。
    private func accept(_ height: CGFloat, for tab: String, isTabSwitchFirstReport: Bool = false) {
        let newCurrent = tab == Self.homeTab ? homeContentHeight : height
        lastChangeWasTabSwitch = false
        if newCurrent != current {
            lastChangeWasTabSwitch = isTabSwitchFirstReport
            objectWillChange.send()
        }
        activeTab = tab
        measuredHeight = height
        heightCache[tab] = height
    }
}

// MARK: - 页面侧：自然高探针（挂在这一页的**内容根部**）

extension View {
    /// 把这一页的**自然高**上报给账本（p5-home-blocks / T7，docs/29 §做法 机制六）。
    ///
    /// - `tab`：页的键（模块页 = 模块 id；名单在 `PanelContentHeight.measuredTabs`，名单外的页
    ///   **静默不上报**——调用点因此可以是统一的，覆盖范围仍只有一处权威）。
    /// - `headerHeight`：面板表头高（`PanelAutoHeight.panelHeaderHeight(effectiveClosedNotchHeight:)`，
    ///   由 `ContentView` 从 `vm` 算好传入）——内容高口径**含表头**，见 `measuredContentHeight`。
    /// - `isCurrent`：这一页此刻还是不是面板上的那一页。切 tab 的那 0.3s 里旧页还活着（transition），
    ///   而条款 ③ 是「换 tab 无条件接受」——旧页只要量到新尺寸就会把账本抢回去（判据 `tab != activeTab`
    ///   恰好成立），面板于是来回跳。这个闸门把**已经不当班**的页整个挡在账本外。
    ///
    /// 另有一道**就绪门**（T7 机制五）：`PanelContentHeight.isTabReportReady` 为假时同样不上报
    /// （判据由宿主按 tab 注入，唯一用例是启动台首轮扫描完成前那份 loading / 空态占位高）。
    func panelContentHeightReport(
        tab: String,
        headerHeight: CGFloat,
        isCurrent: @escaping @MainActor () -> Bool
    ) -> some View {
        modifier(
            PanelContentHeightProbe(
                tab: tab,
                headerHeight: headerHeight,
                isCurrent: isCurrent
            )
        )
    }
}

/// 自然高探针：**不改渲染**，只在布局时把子视图的**理想高**报给账本。
///
/// 为什么不用 `onGeometryChange`：它量的是**摆放后的高**。这些页的根部都是
/// `.frame(maxHeight: .infinity)`（填满面板），摆放后的高恒等于「面板高 − 表头 − 内边距」——
/// 拿它当自然高就是反馈环（账本接受一次，窗口按同一个数重算一次，永远是当前值；
/// 而任何一点系统性偏差都会被下一次接受放大成漂移）。`Layout` 的 `.unspecified` 提案问的是
/// **内容自己要多高**（`HomeStripLayout` 量块宽用的是同一条手法），与容器多大无关：内容短 → 面板
/// 变矮；内容长 → 面板长高（到上界后由内容自己滚）；整页本来就没有内在高度（终端那种，以及
/// T8 前的日历）就**不上报**（名单见 `PanelContentHeight.measuredTabs`）。
///
/// 摆放用的是**提案的原尺寸**（子视图拿到的提案与不加这一层时逐字相同），因此本探针是纯观察者。
private struct PanelContentHeightProbe: ViewModifier {
    let tab: String
    let headerHeight: CGFloat
    let isCurrent: @MainActor () -> Bool

    func body(content: Content) -> some View {
        PanelNaturalHeightLayout(onNaturalHeight: { naturalHeight in
            // `Layout` 的协议方法是非隔离的（协议要求如此），而 SwiftUI 的布局**总在主线程上**跑：
            // 这里把隔离补回来再去碰账本（`assumeIsolated` 在非主线程上会当场断言失败——
            // 那是「布局跑到别的线程去了」这种绝不该发生的事，早炸好过静默漏报）。
            MainActor.assumeIsolated {
                reportNaturalHeight(naturalHeight)
            }
        }) {
            content
        }
    }

    /// 上报一次（探针的判据都收在这里：当班 → 名单内 → **这一页就绪** → 折成内容高口径 → 交账本）。
    private func reportNaturalHeight(_ naturalHeight: CGFloat) {
        guard isCurrent() else { return }
        guard PanelContentHeight.isMeasuredTab(tab) else { return }
        // 就绪门（T7 机制五）：这一页还没有可量的内容时一次都不报（启动台首轮扫描完成前是
        // loading / 空态占位，量它 = 面板「先塌陷再长高」三拍）。默认「都能」——没接上时不影响。
        guard PanelContentHeight.shared.isTabReportReady(tab) else { return }
        PanelContentHeight.shared.report(
            PanelAutoHeight.measuredContentHeight(
                naturalHeight: naturalHeight,
                headerHeight: headerHeight
            ),
            for: tab
        )
    }
}

/// 单子视图的测量容器：`sizeThatFits` 逐字收下提案（渲染与不加这一层时同形）、
/// `placeSubviews` 顺手把子视图的**理想高**交给回调——提案是「面板给的宽 + 高度留空」，
/// 宽度自适应的那几页因此按真实布面量（T7 复核 P2，见 `placeSubviews` 的注释）。
///
/// `placeSubviews` 里回调属**观察**：账本的 `report` 只写自己的字段并在值变化时发一次
/// `objectWillChange`，读者是 `DynamicIslandApp` 的 Combine 订阅（0.15s 防抖后异步重算窗口），
/// **没有任何视图观察它**——因此不会在视图更新里触发视图失效（`@Published` 的经典警告来源）。
/// 回调本身声明成**非隔离**的（`Layout` 的协议方法就是非隔离的），补隔离在调用侧。
private struct PanelNaturalHeightLayout: Layout {
    let onNaturalHeight: (CGFloat) -> Void

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // **逐字转发**：提案原样给子视图、答复原样往上报——不加这一层时父级看到的就是这个数。
        // （面板给的是定值那一档因此与改动前同形；缺维时子视图自己答它的理想值，
        //  硬填 0 或硬填提案都会在过渡 / 测量期间把内容挤变形。）
        subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            // **宽度按面板给的那个格子量**（`bounds.width` = 内容区的实际宽，T7 复核 P2）：自适应
            // 布面的页（启动台的 `GridItem(.adaptive(minimum:))`）在**没有宽度**的提案下会按最窄的
            // 那一档算（单列）→ 量出来的自然高是单列的高（几百行的量级），面板被顶到上界；
            // 高度仍留 `.unspecified`——那才是「这一页要多高」，给个值就变成量容器了。
            onNaturalHeight(
                subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            )
            // 摆放用**上一步报出去的那个尺寸**（就是子视图自己接受的尺寸），左上角对齐——
            // 与不加这一层时逐字相同（居中会让内容在页面里飘）。
            subview.place(
                at: bounds.origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(bounds.size)
            )
        }
    }
}
