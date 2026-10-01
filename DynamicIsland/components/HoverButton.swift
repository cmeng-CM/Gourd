/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI

struct HoverButton: View {
    var icon: String
    var iconColor: Color = .white
    var scale: Image.Scale = .medium
    var pressEffect: PressEffect? = nil
    var contentTransition: ContentTransition = .symbolEffect
    var externalTriggerToken: Int? = nil
    var externalTriggerEffect: PressEffect? = nil
    var action: () -> Void
    
    @State private var isHovering = false
    @State private var pressOffset: CGFloat = 0
    @State private var wiggleAngle: Double = 0
    @State private var wiggleToken: Int = 0
    @State private var lastExternalTriggerToken: Int?

    /// 尺寸档 → 边长（pt）的**唯一取值处**（p6-ui-polish / T2 抽成纯函数，供测试钉档）。
    ///
    /// 三档对应 `Image.Scale` 的三个既有取值（不新造枚举，调用点写 `scale: .small` 与系统语义同名）：
    /// - `.large` = 40（展开面板的播放键）、`.medium` = 30（缺省档，展开面板的其余键）——**两档是
    ///   既有值，不动**：展开面板等处的键尺寸必须与 T2 改动前逐字一致；
    /// - `.small` = 26（**T2 新增**）：首页音乐块紧凑控制行的键径——
    ///   `MusicControlsView.CompactMetrics.controlKeyDiameter` 引用同一档，五键装宽度
    ///   `5×26 + 4×6 + 36 + 6 = 196 ≤ min 200` 见那边的算式注释。
    ///
    /// `@unknown default` 落到 `.medium` 的 30：将来 SwiftUI 若加新档，行为等于缺省档而不是崩溃。
    static func buttonSize(for scale: Image.Scale) -> CGFloat {
        switch scale {
        case .small:
            return 26
        case .medium:
            return 30
        case .large:
            return 40
        @unknown default:
            return 30
        }
    }

    var body: some View {
        let size = Self.buttonSize(for: scale)
        
        Button(action: {
            triggerPressEffect()
            action()
        }) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .frame(width: size, height: size)
                .overlay {
                    Capsule()
                        .fill(isHovering ? Color.gray.opacity(0.2) : .clear)
                        .frame(width: size, height: size)
                        .overlay {
                            let baseImage = Image(systemName: icon)
                                .foregroundColor(iconColor)
                                .contentTransition(contentTransition)
                                .font(scale == .large ? .largeTitle : .body)

                            if case .wiggle = pressEffect {
                                if #available(macOS 15.0, *) {
                                    baseImage
                                        .symbolEffect(
                                            .wiggle.byLayer,
                                            options: .nonRepeating,
                                            value: wiggleToken
                                        )
                                } else {
                                    baseImage
                                }
                            } else {
                                baseImage
                            }
                        }
                }
        }
        .buttonStyle(PlainButtonStyle())
        .offset(x: pressOffset)
        .rotationEffect(.degrees(wiggleAngle))
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.3)) {
                isHovering = hovering
            }
        }
        .onChange(of: externalTriggerToken) { _, newToken in
            guard let newToken, newToken != lastExternalTriggerToken else { return }
            lastExternalTriggerToken = newToken
            triggerPressEffect(override: externalTriggerEffect)
        }
    }

    private func triggerPressEffect(override: PressEffect? = nil) {
        guard let effect = override ?? pressEffect else { return }

        switch effect {
        case .nudge(let amount):
            withAnimation(.spring(response: 0.2, dampingFraction: 0.55)) {
                pressOffset = amount
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                    pressOffset = 0
                }
            }
        case .wiggle(let direction):
            guard #available(macOS 14.0, *) else { return }
            wiggleToken += 1
            let angle: Double = direction == .clockwise ? 10 : -10

            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) {
                wiggleAngle = angle
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    wiggleAngle = 0
                }
            }
        }
    }

    enum PressEffect {
        case nudge(CGFloat)
        case wiggle(WiggleDirection)
    }

    enum WiggleDirection {
        case clockwise
        case counterClockwise
    }
}
