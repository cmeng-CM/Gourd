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
//  ShelfInteractionTests.swift
//  Gourd 架子 cell · ✕（移除按钮）命中几何（p6-ui-polish / T5）
//
//  覆盖 docs/30-ui-polish-and-shelf.md §机制三 ✕ 修复：
//
//  **根因**：✕ 由 SwiftUI 画在 cell 内容右上，点击却由盖在上面的 AppKit 拖拽视图
//  （`DraggableClickView`）仲裁。裸 `NSView` 曾吃掉整个 HStack 槽位——比可见 cell 又宽又高
//  ——它的让位区按自己的 bounds 算，于是「画 ✕ 的矩形」与「让位区」不是同一个矩形：
//  点在 ✕ 上落到拖拽视图 → 只 `selectSingle`（看上去没反应）。
//
//  **本用例钉住的唯一算式** `ShelfRemoveButton.hitRect(in:)`（顶左原点语义；绘制侧的
//  `buttonRect(in:)` 与 `DraggableClickView.hitTest` 的让位判定 `yieldsHitTest(to:in:)`
//  都由它派生）：
//  - 顶右角、30 边、边界 case（区内四角让位、区外一点不让位）；
//  - 绘制的按钮（20×20，居中于 hitRect）必须完整落在让位区里；
//  - 让位判定与 hitRect 在整个 cell 上逐点一致——任一处改偏都会红；
//  - 非正方 / 非零原点 cell 上让位区仍贴顶右角（Y 原点写成 AppKit 的 bottom-left 会红）。

#if os(macOS)
import AppKit
import XCTest
@testable import Gourd

final class ShelfInteractionTests: XCTestCase {

    /// `ShelfItemView` 的可见 cell 内容 —— T5 后拖拽视图被显式约束到这个尺寸，
    /// 两处共用 `ShelfCellMetrics.size`，`hitRect` 才与「画 ✕ 的矩形」同处一个坐标系。
    private let cell = CGRect(origin: .zero, size: ShelfCellMetrics.size)

    func testRemoveButtonHitRectCoversTheDrawnButton() {
        // cell 尺寸：宽 105 + 2×5、高 56 + 2 + 30 + 2×10。
        XCTAssertEqual(cell.size, CGSize(width: 115, height: 108))

        // 顶右角、30 边。
        XCTAssertEqual(ShelfRemoveButton.hitRegion, 30)
        let rect = ShelfRemoveButton.hitRect(in: cell)
        XCTAssertEqual(rect, CGRect(x: 85, y: 0, width: 30, height: 30))
        XCTAssertEqual(rect.maxX, cell.maxX, "让位区必须贴 cell 右缘")
        XCTAssertEqual(rect.minY, cell.minY, "让位区必须贴 cell 顶缘")
        XCTAssertEqual(rect.width, ShelfRemoveButton.hitRegion)
        XCTAssertEqual(rect.height, ShelfRemoveButton.hitRegion)

        // 绘制的按钮（20×20，居中于让位区）完整落在让位区里。
        let button = ShelfRemoveButton.buttonRect(in: cell)
        XCTAssertEqual(button.size, CGSize(width: ShelfRemoveButton.size, height: ShelfRemoveButton.size))
        XCTAssertEqual(button.midX, rect.midX)
        XCTAssertEqual(button.midY, rect.midY)
        XCTAssertTrue(rect.contains(button), "hitRect \(rect) 未覆盖绘制的按钮 \(button)")

        // 边界 case：区内四角（含 maxX/maxY 前一点）与 ✕ 自身矩形都让位。
        let insidePoints = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX - 0.01, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY - 0.01),
            CGPoint(x: rect.maxX - 0.01, y: rect.maxY - 0.01),
            CGPoint(x: button.midX, y: button.midY),
            CGPoint(x: button.minX, y: button.minY),
            CGPoint(x: button.maxX - 0.01, y: button.maxY - 0.01),
        ]
        for point in insidePoints {
            XCTAssertTrue(ShelfRemoveButton.yieldsHitTest(to: point, in: cell), "\(point) 在让位区内却不让位")
        }
        // 区外一点不让位（含 cell 中心的图标处 —— 那里仍归拖拽视图）。
        let outsidePoints = [
            CGPoint(x: rect.minX - 0.5, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.maxY + 0.5),
            CGPoint(x: cell.midX, y: cell.midY),
        ]
        for point in outsidePoints {
            XCTAssertFalse(ShelfRemoveButton.yieldsHitTest(to: point, in: cell), "\(point) 在让位区外却让位")
        }

        // 同源：让位判定与 hitRect 在整个 cell 上逐点一致（绘制侧同样由 hitRect 派生）。
        for x in stride(from: 0.0, through: cell.width, by: 5) {
            for y in stride(from: 0.0, through: cell.height, by: 5) {
                let point = CGPoint(x: x, y: y)
                XCTAssertEqual(
                    ShelfRemoveButton.yieldsHitTest(to: point, in: cell),
                    rect.contains(point),
                    "\(point) 的让位判定与 hitRect 不一致"
                )
            }
        }

        // 非正方 / 非零原点 cell：让位区跟着 cell 的顶右角走。
        XCTAssertEqual(ShelfRemoveButton.hitRect(in: CGRect(x: 0, y: 0, width: 400, height: 300)),
                       CGRect(x: 370, y: 0, width: 30, height: 30))
        XCTAssertEqual(ShelfRemoveButton.hitRect(in: CGRect(x: 20, y: 40, width: 115, height: 108)),
                       CGRect(x: 105, y: 40, width: 30, height: 30))
    }

    /// 让位只在 ✕ 角落：cell 其余部分（图标、名字、空白）仍归拖拽视图，
    /// 拖拽出文件与双击打开不受影响。
    func testDragViewKeepsClicksOutsideTheRemoveCorner() {
        let iconCenter = CGPoint(
            x: cell.midX,
            y: cell.minY + ShelfCellMetrics.verticalPadding + ShelfCellMetrics.iconSize / 2
        )
        let points = [
            iconCenter,
            CGPoint(x: cell.minX, y: cell.minY),
            CGPoint(x: cell.maxX - 0.5, y: cell.maxY - 0.5),
            CGPoint(x: ShelfRemoveButton.buttonRect(in: cell).midX, y: ShelfRemoveButton.hitRect(in: cell).maxY + 1),
        ]
        for point in points {
            XCTAssertFalse(ShelfRemoveButton.yieldsHitTest(to: point, in: cell), "\(point) 不该让位给 ✕")
        }
    }
}
#endif
