/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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
import Lottie
import LottieUI
import Defaults

struct IdleAnimationView: View {
    @Default(.selectedIdleAnimation) var selectedAnimation
    @Default(.animationTransformOverrides) var overrides
    
    var body: some View {
        Group {
            // p6-ui-polish / T10 fix：内置动画的存储路径是**写入时刻的绝对路径**（换安装位置 / 卸载 DMG
            // 卷后失效），渲染期按名解析回当前 bundle 的同一条；解析出的身份仍是存储值
            // （`@Default` 的 id / overrides 的键都按存储 id 走，见 `resolvedAnimation(for:)`）。
            if let animation = selectedAnimation,
               let resolved = IdleAnimationManager.shared.resolvedAnimation(for: animation) {
                AnimationContentView(animation: resolved)
                    .id("\(animation.id)-\(overrides[animation.id.uuidString]?.hashValue ?? 0)")  // Force recreation when override changes
            } else {
                // No animation selected（或内置动画在当前 bundle 里已不存在 → 回落空）
                EmptyView()
            }
        }
    }
}

/// Internal view that renders the actual animation content
private struct AnimationContentView: View {
    let animation: CustomIdleAnimation
    
    var body: some View {
        let config = animation.getTransformConfig()
        
        // Debug logging
        let _ = print("🎨 [IdleAnimationView] Rendering animation: \(animation.name)")
        let _ = print("🎨 [IdleAnimationView] Config: scale=\(config.scale), offset=(\(config.offsetX), \(config.offsetY)), opacity=\(config.opacity)")
        
        switch animation.source {
        case .lottieFile(let url):
            LottieView(state: LUStateData(
                type: .loadedFrom(url),
                speed: animation.speed,
                loopMode: config.loopMode.lottieLoopMode
            ))
            .id(animation.id)  // Force reload when animation changes
            .frame(
                width: config.cropWidth * config.scale,
                height: config.cropHeight * config.scale
            )
            .offset(x: config.offsetX, y: config.offsetY)
            .rotationEffect(.degrees(config.rotation))
            .opacity(config.opacity)
            .padding(.bottom, config.paddingBottom)
            .clipped()
            
        case .lottieURL(let url):
            LottieView(state: LUStateData(
                type: .loadedFrom(url),
                speed: animation.speed,
                loopMode: config.loopMode.lottieLoopMode
            ))
            .id(animation.id)  // Force reload when animation changes
            .frame(
                width: config.cropWidth * config.scale,
                height: config.cropHeight * config.scale
            )
            .offset(x: config.offsetX, y: config.offsetY)
            .rotationEffect(.degrees(config.rotation))
            .opacity(config.opacity)
            .padding(.bottom, config.paddingBottom)
            .clipped()
        }
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.black
        IdleAnimationView()
    }
    .frame(width: 100, height: 50)
}
