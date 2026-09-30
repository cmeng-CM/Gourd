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
//  MusicModule.swift
//  Gourd 内置模块 · 音乐接管（P2 接管批次 / T5）
//
//  docs/20-component-page.md §接口与数据形状 5 的 music 行逐字落地：**接管 = 模块拥有渲染点 +
//  启用真源是上游键**（D-01）。上游 `HomeStripView` 里那个写死的音乐块（`shouldShowMusicPlayer`
//  判据 + `case .music` 分支 + `musicBlockWidth` + 两个 `@Default`）同批删除——首页 strip 的
//  音乐块从此由**本模块的投影**产出，一对一替换，不允许并存（并存就是两个音乐块）。
//
//  五条刻意写死的口径（改动前先读）：
//
//  1. **只声明 `home`**（§已知限制：本批所有接管模块都不声明 `compact`——折叠态左右槽位已按
//     用户 2026-09-29 的决定降级）：`.expanded` / `.compact` / `.lockscreen` 一律答 `.none`
//     （不占位、不算失败，06 §3.2）。因为不声明 `expanded`，`isTabVisible()` 对本模块无意义
//     （投影先按 `surfaces` 过滤），因此**不重写**它。
//  2. **启用真源是 `showStandardMediaControls`**（`takeoverEnableKey`）：组合根的启用门直接读它，
//     `moduleEnableOverrides` 与 `manifest.defaultEnabled` 都不再看——「模块开不开」与
//     「音乐功能开不开」是同一个布尔量，不存在第二份状态（D-01）。这个键在 **Home tab 的判据**
//     里也出现（`ContentView` / `TabSelectionView`），所以它是「音乐块 + 首页那一支」的共同开关，
//     接管不得把它劈成两份。
//  3. **存在性判据逐字沿用旧内置块**（改动前的 `HomeStripView.shouldShowMusicPlayer`）：
//     `showStandardMediaControls && (!autoHideInactiveNotchMediaPlayer || hasActiveSession)`——
//     即「总开关开着」且「没有选『无会话即隐藏』或此刻真有会话」。**不含展开态**：`.home` 的定义
//     就是「展开面板首页的一条 strip 块」，块只会在展开态被渲染，重复判一次 `notchState` 是旧内置块
//     的写法（docs/20 §做法 机制一末段）。判据抽成纯函数 `isVisible(showStandardMediaControls:
//     autoHideInactive:hasActiveSession:)` 以便单测；答 `.none` 的块**不占位**（「是/否」而不是透明度）。
//  4. **`config` 里的键分两类**（D-03 / D-06 / §已知限制 1）：`playerColorTinting` /
//     `useMusicVisualizer` 是**登记键**——键名与上游默认值写进 manifest 供审计，读写仍走上游
//     `Defaults`（`ConfigHandle` 对它们不生效），默认值**从上游键取**
//     （`Defaults.Keys.<键>.defaultValue`），不另抄一个字面量——两处各写一个数就会漂；
//     `showAlbumArt` 是**本模块自己的呈现键**（2026-09-30 用户反馈第 5 条 / D-06），上游没有
//     对应的 `Defaults` 键，读写就走 `ConfigHandle`：manifest `default` 是唯一默认值来源、
//     用户覆盖落在模块专属 suite（`com.cmeng.gourd.module.music`）。
//  5. **命名空间走环境键**（D-08 / §接口与数据形状 6）：折叠态播放器与展开态封面配对的
//     matchedGeometry 命名空间由宿主 `HomeStripView` 经 `EnvironmentValues.homeAlbumArtNamespace`
//     注入（它持有那一条），本模块的块读它；**读不到时用自带的 `@Namespace` 兜底**——配对
//     失效，但不崩、不空白（§已知限制 4）。
//  6. **封面开关只切「块内画不画封面」**（D-06）：关掉后标题 / 进度 / 控制仍按原布局左对齐、
//     封面让出的宽度归它们；**块宽声明（300/420）与内容高度都不变**——「封面关掉要不要收窄块宽」
//     属块宽策略，留给后续反馈（docs/23-home-fit.md §明确不做 / §已知限制 5）。
//
//  文案走 Localizable key（06 §3.3 R5）：`module.music.name` / `module.music.summary`。
//

import Defaults
import SwiftUI

// MARK: - 本模块自己的配置键

/// 本模块 config 里**本模块自己发明**（无上游真源）的键的默认值：唯一一份，manifest 字面量与
/// 读取侧兜底都用它——两处各写一个数就会漂。
///
/// 与 `playerColorTinting` / `useMusicVisualizer` 两个**登记键**的区别见文件头口径 4：那两个的
/// 默认值必须等于上游 `Defaults` 键的默认值（登记值不等于真源值就是假的登记），这里的
/// `showAlbumArt` 没有上游真源，默认值只能落在本模块。
enum MusicConfigDefaults {
    /// 封面默认显示（用户 2026-09-30 问的是「能不能配置」——能力要加，但默认档维持现状：显示）。
    static let showAlbumArt = true
}

// MARK: - MusicModule

/// 音乐接管模块（`docs/20` §接口与数据形状 5 的 music 行）。
///
/// 渲染点 = 上游那个 `MusicPlayerView(albumArtNamespace:)`（首页 strip 的音乐块），
/// 除它之外本模块不占任何 surface。
@MainActor
final class MusicModule: GourdModule {
    /// 模块 id 的**唯一字面量**（manifest 与 `HomeBlockOrdering.migratingLegacyIDs` 的接收方都用它，
    /// 后者因「纯逻辑文件不认模块类型」写字面量，两处一致由用例钉住）。
    static let moduleID = "com.cmeng.gourd.music"

    /// 静态元数据（docs/20 §接口与数据形状 5 + §接口与数据形状 5 末段的取值口径）。
    ///
    /// - `surfaces: [.home]`：**只声明首页块**——折叠槽位本批不占（口径 1）；声明 `.home` 与
    ///   「有没有展开 tab」互不蕴含，因此本模块不进 tab 投影；
    /// - `defaultPlacement: Placement(slot: nil, order: 0)`：`slot` 只在含 `compact` 时有意义，
    ///   这里只用 `order` 这个排序键（首页块序），**0 = 被接管的内置音乐块原本的默认序号**
    ///   （`HomeBlockOrdering.BuiltinBlock.music.defaultOrder`）——接管后顺序与接管前一致；
    /// - `defaultEnabled: true` = **上游键的默认值**（`showStandardMediaControls` 上游默认 `true`）：
    ///   它只在「接管键读不到」时不生效，填它是为了让卡片上那行「默认开启」出现在音乐卡
    ///   （接管模块的启用状态由启用门直接读上游键，见口径 2）；
    /// - `permissions: []`：本批只搬渲染归属与开关真源——音乐播放由上游 `MusicManager`
    ///   本来就有的那条（本机私有媒体通道 / 用户自选来源）承担，本模块不新增任何能力请求。
    static let manifest = ModuleManifest(
        manifestVersion: 1,
        id: moduleID,
        name: LocalizedText(key: "module.music.name"),
        summary: LocalizedText(key: "module.music.summary"),
        icon: IconSpec(type: "symbol", name: "music.note"),
        version: "1.0.0",
        apiVersion: HostInfo.currentAPIVersion,
        kind: "builtin",
        surfaces: [.home],
        defaultPlacement: Placement(slot: nil, order: 0),
        defaultEnabled: true,
        permissions: [],
        config: ConfigSchema(
            type: "object",
            properties: [
                // 封面色 tint 是否跟随专辑封面取色（上游 `MusicPlayerView` / `MusicControlsView` 读它）。
                // 默认值取上游键的默认值（口径 4）
                "playerColorTinting": ConfigNode(
                    type: "boolean",
                    title: nil,
                    default: .bool(Defaults.Keys.playerColorTinting.defaultValue),
                    values: nil,
                    itemType: nil
                ),
                // 音乐可视化器开关（上游频谱视图读它）。默认值同上——**上游默认 `true`**，
                // 不按「可视化的东西默认关」的直觉改数：登记值必须等于真源值，否则这份登记就是假的
                "useMusicVisualizer": ConfigNode(
                    type: "boolean",
                    title: nil,
                    default: .bool(Defaults.Keys.useMusicVisualizer.defaultValue),
                    values: nil,
                    itemType: nil
                ),
                // **本模块自己的呈现键**（D-06 / 口径 4 的第二类）：首页音乐块画不画封面。
                // 默认值取本模块的 `MusicConfigDefaults`（没有上游真源可登记），读写走
                // `ConfigHandle`——用户在模块专属 suite 里的覆盖值由它解析。
                "showAlbumArt": ConfigNode(
                    type: "boolean",
                    title: nil,
                    default: .bool(MusicConfigDefaults.showAlbumArt),
                    values: nil,
                    itemType: nil
                ),
            ]
        )
    )

    private let context: ModuleContext

    init(context: ModuleContext) {
        self.context = context
    }

    /// 接管三件套之一：**启用真源 = 上游那个开关键本身**（D-01）。
    static var takeoverEnableKey: Defaults.Key<Bool>? { .showStandardMediaControls }

    // 接管三件套之二 `isTabVisible()`：本模块**不重写**它——它不声明 `expanded`，投影先按
    // `surfaces` 过滤，可见性钩子对它永远不被问到（`docs/20` §接口与数据形状 5 的 music 行同口径）。
    // 这里刻意留白：写一条 `= true` 只会让读者以为本模块有 tab。

    /// 接管三件套之三：宽度声明 = **被接管块原本的宽度**（D-10）——接管是「接住原来的呈现」，
    /// 不是顺手把音乐块从 300/420 压到宿主统一值 180/240。这个档位同时是首页 strip 高度阈值的
    /// 输入（`HomeStripView.minimumUsableHeight` 的实测来源就是 420 宽下的封面边长）。
    static var homeBlockWidth: ModuleHomeBlockWidth? { ModuleHomeBlockWidth(min: 300, ideal: 420) }

    /// 首页分带批次（T7）的第四条钩子：音乐块是**大块**——封面 + 控制需要面积，因此显式答
    /// `.large`（缺省 `.compact` 会把它挪进下方的小组件网格，封面会被压成一条）。
    /// 形态只声明「它是什么」，摆法（主块带的丢块语义、最小可用高度 152）仍是宿主的事
    /// （docs/26-home-widgets-and-settings.md §做法 机制六 / D-09）。
    static var homeFormFactor: HomeFormFactor { .large }

    /// 音乐块的**存在性判据**（纯函数，便于单测：口径 3）。
    ///
    /// 两段是「且」：功能总开关（上游键）与**运行期条件**（选了「无会话即隐藏」时必须真有会话——
    /// 没有会话时不画一个只有占位元数据的空壳）。表达式**逐字沿用**改动前的
    /// `HomeStripView.shouldShowMusicPlayer`，**不含展开态**（D-12：`.home` 块只在展开面板
    /// 首页渲染，重复判一次 `notchState` 是旧内置块的写法，本批删除）。
    static func isVisible(
        showStandardMediaControls: Bool,
        autoHideInactive: Bool,
        hasActiveSession: Bool
    ) -> Bool {
        showStandardMediaControls && (!autoHideInactive || hasActiveSession)
    }

    /// 块内**封面画不画**的解析（纯函数，便于单测：D-06）。
    ///
    /// 三档合一：schema 里没有这个键 / 用户没写过覆盖值 → `ConfigHandle.get` 给 `nil` → 回落
    /// `MusicConfigDefaults.showAlbumArt`（= 显示，缺键时的呈现与 manifest 默认值一致）；
    /// 用户写过覆盖值 → 读回来的就是它（覆盖值类型不符时 `ConfigHandle` 自己回落默认值并记 warning）。
    ///
    /// **调用点必须现读**（`content(for: .home)` 每次投影都调一次）：本批的 `ConfigHandle` 没有
    /// `observe`（07 §2 的 `observe` 属 P1-3），所以「改了 config 下一次重绘生效」这件事靠现读
    /// 保证，不靠缓存。
    static func showsAlbumArt(from config: ConfigHandle) -> Bool {
        config.get("showAlbumArt", as: Bool.self) ?? MusicConfigDefaults.showAlbumArt
    }

    /// 只记一条日志：音乐没有常驻副作用（播放会话由上游 `MusicManager` 持有，
    /// 本批只搬渲染归属，不搬生命周期）。
    func activate() async throws {
        context.logger.info(
            "music 模块已激活（takeover=true，showStandardMediaControls=\(Defaults[.showStandardMediaControls])，hasActiveSession=\(MusicManager.shared.hasActiveSession)）"
        )
    }

    /// 没有要收的东西：本模块不起 Task、不订阅、不持有视图外的资源（见 `activate()`）。
    func deactivate() async {}

    /// 只答 `home` 且**判据成立**才给 `.view`；不成立答 `.none`（不占位，口径 3）。
    /// `.expanded` / `.compact` / `.lockscreen` 一律 `.none`（口径 1：不占位、不算失败）。
    func content(for request: ContentRequest) -> ModuleContent {
        switch request.surface {
        case .home:
            // 判据读**当下**值（上游键 + 会话）：投影与内容每一次都现问，不缓存——
            // 会话起停 / 开关关掉时块随之消失（重排由 `HomeStripView` 对 `MusicManager` 的
            // 观察驱动，见那里的注释）。
            guard Self.isVisible(
                showStandardMediaControls: Defaults[.showStandardMediaControls],
                autoHideInactive: Defaults[.autoHideInactiveNotchMediaPlayer],
                hasActiveSession: MusicManager.shared.hasActiveSession
            ) else {
                return .none
            }
            return .view(AnyView(MusicHomeBlockView(showsAlbumArt: Self.showsAlbumArt(from: context.config))))
        case .expanded, .compact, .lockscreen:
            return .none
        }
    }
}

// MARK: - 首页块内容

/// 音乐块的视图：**封面档与改动前的内置块逐字相同**（`MusicPlayerView(albumArtNamespace:)`），
/// 只是搬运到了模块这一侧（一对一替换）。
///
/// 文件内私有：它是本模块的渲染细节，不进任何名单、不给别的模块用。
///
/// **命名空间按「宿主注入 → 自带兜底」两档取**（口径 5 / D-08）：宿主 `HomeStripView` 注入的是
/// 折叠态播放器共享的那一条（`.environment(\.homeAlbumArtNamespace, …)`），配对动画因此与改动前
/// 一致；没人注入时（例如将来在别处渲染这个块）退回本视图自己的 `@Namespace`——同一块内的
/// 动画仍成立，跨视图的那一对静默失效，不崩、不空白。
///
/// **封面关掉的那一档**（`showsAlbumArt == false`，D-06 / 口径 6）走 `MusicControlsView` 单独一块：
/// 它与 `MusicPlayerView` 里 HStack 的第二个孩子是**同一个视图、同一份自带布局**
///（`maxWidth: .infinity, alignment: .leading`），因此去掉 `AlbumArtView` 后标题 / 进度 / 控制
/// 仍是原来的位置与左对齐，封面让出的宽度归它们——不留空洞、也不塌成一列窄内容。
/// **块宽声明不改**（300/420）：本档只是块内变宽裕（§已知限制 5）。
///
/// **块内不自己观察 `MusicManager`**：`MusicPlayerView` 的部件（`AlbumArtView` /
/// `MusicControlsView`）本来就各自 `@ObservedObject` 它，这里再观察一次只是重复订阅；
/// 「块在不在」那件事由 `content(for: .home)` 的判据与 `HomeStripView` 的观察承担。
private struct MusicHomeBlockView: View {
    @Environment(\.homeAlbumArtNamespace) private var albumArtNamespace
    @Namespace private var fallbackNamespace
    /// 封面画不画：由 `MusicModule.showsAlbumArt(from:)` 在 `content(for: .home)` 里现读后传入
    /// （视图自己不碰 `ConfigHandle`——参数进来才是可测的分档）。
    let showsAlbumArt: Bool

    var body: some View {
        if showsAlbumArt {
            MusicPlayerView(albumArtNamespace: albumArtNamespace ?? fallbackNamespace)
        } else {
            MusicControlsView()
        }
    }
}
