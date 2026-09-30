// Modified for Gourd (2026-09-30)
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
//  HomeAlbumArtNamespace.swift
//  Gourd 宿主 · 首页块的 matchedGeometry 命名空间注入（P2 接管批次 / T5）
//
//  展开面板里「折叠态播放器 ↔ 展开态封面」这对 matchedGeometry 动画只有**一条**命名空间：
//  持有者是 `ContentView`（`@Namespace var albumArtNamespace`），它经 `NotchHomeView` 的
//  `albumArtNamespace` 属性传到 `HomeStripView`——音乐块与它后面的播放器共享这一条，
//  配对才成立。
//
//  T5 音乐接管以后，首页的音乐块搬到模块侧（`MusicModule` 的 `MusicHomeBlockView`），
//  模块**拿不到**宿主这条命名空间（它不在视图树的那一段里持有它）。因此宿主经**环境键**
//  把这一份注入进去（docs/20-component-page.md §接口与数据形状 6 / D-08）：
//
//  - **谁注入**：`HomeStripView`——它本来就是这条命名空间的持有者，在模块块那个
//    `HomeStripBlock` 上写 `.environment(\.homeAlbumArtNamespace, albumArtNamespace)`
//    （块是模块产出的，但块的外壳与它所在的环境由宿主给）；
//  - **取不到时**：模块用**自带的 `@Namespace`** 兜底（`MusicModule.MusicHomeBlockView`），
//    配对动画因此静默失效，但**不崩、不空白**（docs/20 §已知限制 4）。缺省值 `nil` 就是
//    「没人注入」这一档的语义——取值处按 `?? 自带命名空间` 处理。
//
//  为什么是环境键而不是把 `Namespace.ID` 塞进模块内核的 API：`Namespace.ID` 是**渲染层**的
//  概念，而 `GourdModule` / `ModuleContext` 属内核（不该认识 SwiftUI / D-08）；环境键让
//  「宿主注入、模块可选消费」这条依赖只落在视图层。
//

import SwiftUI

/// 展开面板 matchedGeometry 命名空间的环境键（**缺省 `nil` = 没人注入**）。
///
/// `private` 是刻意的（docs/20 §接口与数据形状 6 逐字给出这一形态）：它只服务于本文件的
/// 环境值，外部要读写一律走 `EnvironmentValues.homeAlbumArtNamespace`——键类型不外流，
/// 将来换实现（比如改成 `@Entry`）不必动调用点。
private struct HomeAlbumArtNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// 首页块要用的 matchedGeometry 命名空间（折叠态播放器与展开态封面配对的**唯一一份**）。
    ///
    /// - 由 `HomeStripView` 注入（它持有宿主那条命名空间）；
    /// - 模块侧按 `@Environment(\.homeAlbumArtNamespace)` 读，读到 `nil`（没人注入，例如
    ///   将来在别处渲染）时用模块自带的 `@Namespace` 兜底——配对失效但不崩、不空白。
    var homeAlbumArtNamespace: Namespace.ID? {
        get { self[HomeAlbumArtNamespaceKey.self] }
        set { self[HomeAlbumArtNamespaceKey.self] = newValue }
    }
}
