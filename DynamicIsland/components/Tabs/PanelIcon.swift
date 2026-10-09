// Modified for Gourd (2026-10-09)
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
//  PanelIcon.swift
//  Gourd 宿主 · 面板图标（类型 + 唯一图标表 + 隔空投送自绘字形）（p9 批次 / T3）
//
//  面板元素在渲染层的图标第一次有了类型：`PanelIcon`。SF Symbols **没有**隔空投送这一枚
//  （本机 macOS 26 实测 `NSImage(systemSymbolName: "airdrop")` 为 nil），共享服务的 `.image`
//  是彩色 App 图标（单色 tab 条上不同套），因此字形自绘：`AirDropGlyph`（SwiftUI `Canvas`，
//  圆心点 + 三段同心弧、底部开口 ±35°），颜色走 `.foreground` 着色以跟随 `foregroundStyle`。
//
//  规格：docs/34-calendar-week-and-panel-icons.md §做法 机制二、§接口与数据形状、§已知限制 1。
//

import SwiftUI

/// 面板图标：SF Symbol 之外，隔空投送用自绘字形。
enum PanelIcon: Equatable {
    case symbol(String)
    case airDrop
}

/// 面板图标表（**唯一一份**图标字面量）：视图取它、用例钉它；模块 tab 的图标仍由 manifest 投影
/// （`ModuleRegistry.tabEntries` 的 `symbolName`），不在这张表里。
enum PanelIconTable {
    static let home: PanelIcon = .symbol("house.fill")
    static let shelf: PanelIcon = .airDrop
    static let usage: PanelIcon = .symbol("chart.bar.doc.horizontal")
    static let clipboard: PanelIcon = .symbol("doc.on.clipboard")
    static let notes: PanelIcon = .symbol("square.and.pencil")
    static let terminal: PanelIcon = .symbol("apple.terminal")
    static let extensionFallback: PanelIcon = .symbol("puzzlepiece.extension")
}

/// 隔空投送字形的几何度量（以字形**外缘半径 R** 为单位）。
///
/// 量取来处 = 用户 2026-10-09 给的控制中心参考图
/// （`.workflow/p9-calendar-week-icon/evidence/macos-controlcenter-airdrop-x8.png`）：
/// 中心行/列亮度扫描（圆心点半宽 2px / 外缘 15.5px；三个弧环心 5.1 / 10.1 / 14.0px；线宽 1.75px，圆头线帽）；
/// 开口由 16 倍放大下的弧端位置量出（atan(9 / 12.6) ≈ 35.5°，两侧合计 70°）。
/// 与 Apple 那枚**不保证逐像素一致**（参考图本身是低分辨率截图，量取有 ±1px 级误差）。
struct AirDropGlyphMetrics {
    /// 圆心点半径：`0.13R`。
    static let dotRadiusFactor: CGFloat = 0.13
    /// 三段弧的环心半径：`0.33R` / `0.65R` / `0.90R`。
    static let ringRadiusFactors: [CGFloat] = [0.33, 0.65, 0.90]
    /// 弧的线宽：`0.113R`（圆头线帽）。
    static let strokeFactor: CGFloat = 0.113
    /// 底部开口的总跨度：`70°`（每侧 35°）。
    static let gapDegrees: CGFloat = 70

    // 两种读法等价（度量本身是常量，实例面只是「取一份度量再算几何」的读法）：
    // `AirDropGlyphMetrics.dotRadiusFactor` 与 `AirDropGlyphMetrics().dotRadiusFactor`。
    var dotRadiusFactor: CGFloat { Self.dotRadiusFactor }
    var ringRadiusFactors: [CGFloat] { Self.ringRadiusFactors }
    var strokeFactor: CGFloat { Self.strokeFactor }
    var gapDegrees: CGFloat { Self.gapDegrees }
}

/// 隔空投送字形（自绘）：圆心点 + 三段同心弧、底部开口 ±35°。
///
/// 颜色走 `.foreground` 着色（`GraphicsContext.Shading.foreground`），因此跟随外部的
/// `foregroundStyle`（tab 条的选中 / 未选中档即由此切换）。
///
/// **开口方向按渲染结果定，不按角度约定猜**（docs/34 §接口与数据形状）：画布是 y 向下的坐标系，
/// 角度 `0° = 正右`、`90° = 正下`；`clockwise: false` 沿**角度增大**方向扫（本坐标系下视觉上为顺时针）
/// ——同批渲图实证（`/tmp/gourd-icons/glyph2.swift` 的 AppKit 版与 `ImageRenderer` 的 SwiftUI 版
/// 各渲一张，缺口都居中在视觉正下方：下缘中线无墨迹、上缘有墨迹，见 p9 T3 报告与
/// `.workflow/p9-calendar-week-icon/evidence/glyph-vs-ref-final.png`）。
struct AirDropGlyph: View {
    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            let metrics = AirDropGlyphMetrics()
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            // 圆心点。
            let dotRadius = metrics.dotRadiusFactor * radius
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - dotRadius,
                                       y: center.y - dotRadius,
                                       width: dotRadius * 2,
                                       height: dotRadius * 2)),
                with: .foreground
            )

            // 三段同心弧 = 整圆减去底部缺口（`gapDegrees`，两侧各一半）。
            // 开口居中在正下方 → 从「正下 + 半个缺口」（`90° + gap/2`）起，绕行 `360° − gap`
            // 回到另一侧（`90° + 360° − gap/2`）——扫的是缺口之外的长弧，不是缺口那一段。
            let halfGap = Double(metrics.gapDegrees) / 2
            let stroke = StrokeStyle(lineWidth: metrics.strokeFactor * radius, lineCap: .round)
            for factor in metrics.ringRadiusFactors {
                var ring = Path()
                ring.addArc(center: center,
                            radius: factor * radius,
                            startAngle: .degrees(90 + halfGap),
                            endAngle: .degrees(90 + 360 - halfGap),
                            clockwise: false)
                context.stroke(ring, with: .foreground, style: stroke)
            }
        }
    }
}

/// 面板图标的渲染点：`.symbol` → `Image(systemName:)`（**不加框**，既有符号的排布逐字不变）、
/// `.airDrop` → `AirDropGlyph`。
struct PanelIconView: View {
    let icon: PanelIcon

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
        case .airDrop:
            // 13pt：与相邻的 13pt 符号视觉等高（字形外缘直径 ≈ 0.96 × 13pt ≈ 12.4pt，
            // 与 13pt 符号的墨迹高度同档）。
            AirDropGlyph()
                .frame(width: 13, height: 13)
        }
    }
}
