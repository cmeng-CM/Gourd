// Modified for Gourd (2026-10-11)
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
//  HomeEnvironmentBand.swift
//  Gourd 宿主 · 首页的**环境带**（p13-home-v5 / docs/38-home-v5-layout.md §做法 一 / D-01）
//
//  首页自 p13 起的第一排：**音乐 + 前台应用 + 系统读数**（三块，顺序仍按用户的 `homeBlockOrder`）。
//  它是「常看的那一排」——**固定在最上面**，不参与可变流的换行：用户在设置页开了更多组件时，
//  环境三块不会被挤到第二排去（用户 2026-10-11「环境带放第一排，这个操作频率是最高的」）。
//
//  与可变流的关系：**同一个名单（`HomeBandCatalog.blocks`）按区劈开**，带内顺序与流内顺序都是
//  那一条全局序——区只决定「在哪一排」（D-03）。
//
//  摆放与宽度分配复用流的那一套（`HomeStripLayoutMath` + `HomeStripLayoutMath.Item.flexible`）：
//  本带是**一行**，行高 = 带内块申报高的最大值（今天三块都申报 96 = `HomeEnvironmentBand.height`）。
//  声明了 `homeBlockAbsorbsSurplus` 的块吃掉这一行的余量（D-04：前台应用独占）——
//  「没有弹性块时余量留行尾」这条旧行为因此逐字保留给未来只开音乐 + 系统读数的人。
//

import SwiftUI

/// 环境带的**宿主常量**：这一排的档高（三块申报高的同源值）。
///
/// 三个环境块都以 `.points(HomeEnvironmentBand.height)` 申报（音乐沿用形态档 `.compact`，同值）——
/// 「环境带三块等高」这条观感因此是**算出来的**（行高 = 最高块），不是宿主硬填的。
enum HomeEnvironmentBand {
    /// 环境带档高 = 紧凑档档高（`HomeFlowView.compactBlockHeight` = 96）。
    static let height: CGFloat = HomeFlowView.compactBlockHeight
}

/// 环境带的一行：块按声明宽摆放，弹性块吃余量（`HomeStripLayoutMath` 规则 ①′）。
///
/// **不用 `HomeFlowView`**（那条路带换行与行高取舍，本带只有一行、高度也不参与取舍），
/// 但宽度分配是**同一个纯函数**——两处的「谁多宽」因此不可能出现两套口径。
struct HomeEnvironmentBandView: View {
    /// 环境带的块名单（**已排序**，由接缝从 `HomeBandCatalog` 里筛出）。
    let blocks: [HomeBandBlock]
    let albumArtNamespace: Namespace.ID

    /// 这一行要摆的块宽（顺序即显示顺序）：同一个数组既喂 `plan` 也喂格子。
    private var items: [HomeStripLayoutMath.Item] {
        blocks.map {
            HomeStripLayoutMath.Item(min: $0.width.min, ideal: $0.width.ideal, flexible: $0.absorbsSurplus)
        }
    }

    /// 本带的行高 = 带内块申报高的最大值（与流同一条规则；空带 = 0）。
    private var rowHeight: CGFloat {
        blocks.map { HomeFlowView.blockHeight(for: $0) }.max() ?? 0
    }

    var body: some View {
        GeometryReader { proxy in
            let plan = HomeStripLayoutMath.plan(
                items: items,
                available: max(0, proxy.size.width),
                spacing: HomeStripView.widgetColumnSpacing
            )
            HStack(alignment: .top, spacing: HomeStripView.widgetColumnSpacing) {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    // 规则 ③ 丢掉的块拿零提案（不摆放 = 会以容器尺寸居中叠画，见 `HomeStripLayout`）——
                    // 本带的行高是「装得下就都在」，丢块只会发生在面板窄到连最小宽之和都放不下的极端档。
                    if index < plan.widths.count {
                        HomeBandCell(block: block, albumArtNamespace: albumArtNamespace)
                            .frame(width: plan.widths[index], height: rowHeight, alignment: .topLeading)
                            .homeBlockFloat()
                    } else {
                        HomeBandCell(block: block, albumArtNamespace: albumArtNamespace)
                            .frame(width: 0, height: 0)
                            .hidden()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: rowHeight, alignment: .topLeading)
    }
}
