//
//  HomeVerticalFit.swift
//  Gourd 宿主 · 首页两排的高度取舍（P2 批次 / T2）
//
//  展开面板首页的**标准路径**是两排：上排一条横向 strip（模块块），下排一条全宽日历行。两排都要高度，
//  面板高度不够时就得放弃一排。**放弃哪一排是产品默认值**（不是用户旋钮），本文件是那一条判据的
//  唯一落点。
//
//  口径（2026-09-30 用户实测反馈第 2 条 / docs/23-home-fit.md §做法 机制二，D-02）：
//  **先收日历行、保住 strip**——strip 是「扫一眼」的主内容，日历行是「展开看」的次内容。
//  改动前是反的（`NotchHomeView.standardHomeContent` 的旧算式：日历行拿固定档、strip 拿剩下的，
//  剩下的不够 `HomeStripView.minimumUsableHeight` 就整条不画 strip、日历行照画）。
//
//  为什么是**纯函数**（无 SwiftUI、无偏好、无单例）：取舍只有三条边界，值得穷举；放在视图里就只能
//  靠改高度、截图、肉眼比，判错一位也没人知道。视图侧只剩「按 plan 画哪几行」的机械动作。
//
//  本文件**不读** `Defaults[.showCalendar]`：日历行开不开是用户偏好，由接缝
//  （`NotchHomeView.standardHomeContent`）先判，再把「日历行要占的高度」作为入参传进来
//  （关掉时传 0——只有一排时不存在取舍，strip 拿全部可用高度，与改动前的口径一致）。
//

import CoreGraphics

/// 首页两排（strip + 全宽日历行）在给定可用高度下的取舍结果。
///
/// 判据是**两段问句**，顺序即优先级（先问 strip 放不放得下、再问两排一起放不放得下）：
/// 1. `available < stripMinimumHeight` → **`.calendarOnly` 档**：strip 一条都不画（判据「画不满就不画」
///    的既有裁决），日历行在行高放得下时才画；
/// 2. 否则 strip 单独放得下：两排一起放得下（`available ≥ stripMinimumHeight + rowSpacing +
///    calendarRowHeight`）→ **`.both` 档**，strip 拿扣掉日历行与间距的剩余高度；
/// 3. 两排一起放不下 → **`.stripOnly` 档**：日历行整行不画、**strip 拿全部可用高度**（这是本次
///    改动的核心：让出去的是日历行，不是 strip）。
enum HomeVerticalFit {

    /// 取舍落在哪一档。
    ///
    /// 档名描述的是**画出来的东西**（不是「谁被放弃」）：
    /// - `.both`：两排都画；
    /// - `.stripOnly`：只有 strip（日历行让位，D-02 的那一档）；
    /// - `.calendarOnly`：只有日历行（strip 连最小可用高度都放不下）。
    enum Layout: Equatable {
        case both
        case stripOnly
        case calendarOnly
    }

    /// 一次取舍的完整结果：视图只需要读它，不再自己算高度。
    struct Plan: Equatable {
        /// 落在哪一档（判据见 `HomeVerticalFit` 的文档）。
        let layout: Layout
        /// strip 的高度：`.both` 档 = 扣掉日历行与间距的剩余；`.stripOnly` 档 = **全部**可用高度；
        /// `.calendarOnly` 档 = `0`（不画，见 `showsStrip`）。
        let stripHeight: CGFloat
        /// 日历行画不画。**调用方仍需自己与「用户有没有开日历行」相与**
        /// （本类型不认偏好，见文件头注释）。
        let showsCalendarRow: Bool

        /// strip 画不画。`.both` / `.stripOnly` 两档成立时 `stripHeight` 按构造 ≥ 最小可用高度，
        /// 因此这里只看档位（不是再看一遍高度判据——两处都判就会有两份阈值）。
        var showsStrip: Bool { layout != .calendarOnly }
    }

    /// 按可用高度决定两排的取舍（纯函数：同样入参永远同样结果）。
    ///
    /// - Parameters:
    ///   - available: 分给这两排的**全部**可用高度（已扣掉宿主内边距等），负值按 0 处理。
    ///   - calendarRowHeight: 日历行要占的高度（关掉日历行时传 `0`）。
    ///   - rowSpacing: 两排之间的间距（关掉日历行时传 `0`）。
    ///   - stripMinimumHeight: strip 的**最小可用高度**（`HomeStripView.minimumUsableHeight`，
    ///     「画不满就不画」的阈值）。
    /// - Returns: 三档之一的 `Plan`。**阈值是闭区间**：`available` 恰好等于某个阈值时算「放得下」，
    ///   不留一档只有 0.0001pt 宽的缝。
    static func plan(
        available: CGFloat,
        calendarRowHeight: CGFloat,
        rowSpacing: CGFloat,
        stripMinimumHeight: CGFloat
    ) -> Plan {
        let available = max(0, available)

        // ① strip 连单独放都放不下：整条不画，让日历行（它能放下就画——行高放不下就什么都没有，
        //    面板只剩其它元素）。
        guard available >= stripMinimumHeight else {
            return Plan(layout: .calendarOnly, stripHeight: 0, showsCalendarRow: available >= calendarRowHeight)
        }

        // ② 两排一起放得下：日历行拿固定档、strip 拿剩下的（这一档是改动前的唯一一档，算式未变）。
        let stripHeightWithCalendarRow = available - calendarRowHeight - rowSpacing
        if stripHeightWithCalendarRow >= stripMinimumHeight {
            return Plan(layout: .both, stripHeight: stripHeightWithCalendarRow, showsCalendarRow: true)
        }

        // ③ 只有 strip 放得下：**日历行整行让位**（不是削日历行的高度——它是一整张月历，
        //    削一半两排都不可读），strip 拿全部可用高度。
        return Plan(layout: .stripOnly, stripHeight: available, showsCalendarRow: false)
    }
}
