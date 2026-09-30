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
//  待办 / 通知 / 启动台 / 快捷指令——这四页的内容是**行数 / 格子数**的函数（自然高与面板无关）；
//  **不上报**的四页：日历（`.frame(height: maxTabContentHeight)`，自己的高是面板高的函数，量它
//  等于把面板高喂回自己 → 每接受一次缩 12pt，一路缩到 130 的下限）、计时器（同形 + 250 的
//  per-tab 下限）、暂存器（拖放区整块填满，没有「内容高」）、终端（终端仿真块按屏高比例，本来就
//  没有自然高）。
//
//  **切页时谁说了算**（`selectTab(_:)`，T7 复核 P1）：换页**不只是换「值从哪来」**——名单外的页
//  必须**没有值**（`current` = nil → 尺寸层回落**手动值** = 今天的行为，宽松够用），否则会继承
//  上一页量出来的高度（首页 → 待办 ~200 → 日历：日历拿 200 画两栏月历，`max(130, 200 − 28 − 36)`
//  = 136pt）。名单**内**的页保留上一页量出来的那一个数，直到新页量完——**且新页的第一份上报
//  无条件接受**（`awaitsFirstReport`：留着的那个数与新页无关，拿它比出来的差不是「同一页的微动」，
//  光标还压在面板上时也不该拦），因此是**一次**跳动而不是两次（若切页就清值会先跳手动值再跳量值）。
//
//  触发链（派发片段裁决 5）：接受一个新值时 `objectWillChange` 响一次，`DynamicIslandApp` 收到后
//  走**既有的** `debouncedUpdateWindowSize()`（0.15s 防抖那条，T6 接好的）——**不新开第二条 resize
//  链**；切 tab 那一刻的尺寸由既有 `updateWindowSizeForTabSwitch()` 经 `openNotchSize` 读本账本
//  （读到的就是 `selectTab` 刚定下来的那一份）。
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

    /// 同一 tab 的滞回阈值（pt）：差在这个以内不改窗口（`docs/29 §做法 机制六` 的 8pt）。
    /// 秒数跳动这类「同一 tick 里十几分之一 pt」的微动因此不会碰窗口。
    static let hysteresis: CGFloat = 8

    /// **有自然高、因此上报**的模块页（`ModuleHostView` 渲染的那几个 tab 的键 = 模块 id）。
    ///
    /// 判据是「这一页的自然高是不是**内容**的函数，而不是**面板**的函数」：
    /// - `todos`：表头 + 清单行（行数决定高）；
    /// - `notifications`：表头 + 通知行 + 脚注（条数决定高）；
    /// - `launcher`：搜索框 + 应用网格（App 数决定高，最高到上界后网格自己滚）；
    /// - `shortcuts`：表头 + 清单 + 结果行。
    ///
    /// 另外四页（`calendar` / `timer` / 暂存器 / 终端）**刻意不在名单里**，理由逐条写在文件头。
    /// 名单外的 tab 不产生值：切到它们时 `selectTab(_:)` 把量出来的那份清掉 → 尺寸层回落手动值。
    static let measuredTabs: Set<String> = [
        "com.cmeng.gourd.todos",
        "com.cmeng.gourd.notifications",
        "com.cmeng.gourd.launcher",
        "com.cmeng.gourd.shortcuts",
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

    /// 上一次**被接受**的页（`report` 的 tab、或 `selectTab(_:)` 定下来的页）。`current` 靠它二选一。
    private(set) var activeTab: String?

    /// 量出来的那一份（`activeTab` 是名单内某一页时的 `current`）。`private(set)`：写入口只有
    /// `report` / `selectTab`，读出来是给用例与排查看的（生产读者一律走 `current`）。
    private(set) var measuredHeight: CGFloat?

    /// 刚切到一个**会上报**的页（`selectTab` 置位）：它的**第一份**上报要**无条件**接受
    /// （派发片段条款 ③ 的「换 tab 无条件接受」），滞回与光标规则都不参与。
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
    /// - 名单内的页 → **保留**上一页量出来的值（新页量完那一拍无条件覆盖它，一次跳动）；
    /// - 名单外的页 → **清掉**量出来的值 → `current` = nil → 尺寸层回落手动值。
    func selectTab(_ tab: String) {
        guard !tab.isEmpty, tab != activeTab else { return }
        let isHome = tab == Self.homeTab
        let isMeasured = Self.isMeasuredTab(tab)
        let newCurrent: CGFloat? = isHome ? homeContentHeight : (isMeasured ? measuredHeight : nil)
        if newCurrent != current {
            objectWillChange.send()
        }
        activeTab = tab
        // 名单内：留着上一页的量值（一次跳动）——但它的第一份上报无条件接受（`awaitsFirstReport`）。
        // 名单外：清值 → `current` = nil → 尺寸层回落手动值。
        awaitsFirstReport = isMeasured
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
        // 不是「同一页的微动」，见 `awaitsFirstReport`）。
        if awaitsFirstReport {
            awaitsFirstReport = false
            accept(height, for: tab)
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
        pointerInsidePanel = { false }
    }

    /// 接受一个新值：**`current` 真的变了**才响一声 `objectWillChange`（尺寸层据此走 0.15s 防抖那条
    /// 既有的 resize 链；同 tab 内 8pt 以下的微动与「值没变」的切页因此一次都不响）。
    private func accept(_ height: CGFloat, for tab: String) {
        let newCurrent = tab == Self.homeTab ? homeContentHeight : height
        if newCurrent != current {
            objectWillChange.send()
        }
        activeTab = tab
        measuredHeight = height
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
/// 变矮；内容长 → 面板长高（到上界后由内容自己滚）；整页本来就没有内在高度（终端 / 日历那种）
/// 就**不上报**（名单见 `PanelContentHeight.measuredTabs`）。
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

    /// 上报一次（探针的判据都收在这里：当班 → 名单内 → 折成内容高口径 → 交账本）。
    private func reportNaturalHeight(_ naturalHeight: CGFloat) {
        guard isCurrent() else { return }
        guard PanelContentHeight.isMeasuredTab(tab) else { return }
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
