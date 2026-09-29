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
//  4. **`config` 只登记不接管**（D-03 / §已知限制 1）：两个键的键名与上游默认值写进 manifest
//     供审计，读写仍走上游 `Defaults`（`ConfigHandle` 对它们不生效）。默认值**从上游键取**
//     （`Defaults.Keys.<键>.defaultValue`），不另抄一个字面量——两处各写一个数就会漂。
//  5. **命名空间走环境键**（D-08 / §接口与数据形状 6）：折叠态播放器与展开态封面配对的
//     matchedGeometry 命名空间由宿主 `HomeStripView` 经 `EnvironmentValues.homeAlbumArtNamespace`
//     注入（它持有那一条），本模块的块读它；**读不到时用自带的 `@Namespace` 兜底**——配对
//     失效，但不崩、不空白（§已知限制 4）。
//
//  文案走 Localizable key（06 §3.3 R5）：`module.music.name` / `module.music.summary`。
//

import Defaults
import SwiftUI

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
            return .view(AnyView(MusicHomeBlockView()))
        case .expanded, .compact, .lockscreen:
            return .none
        }
    }
}

// MARK: - 首页块内容

/// 音乐块的视图：**与改动前的内置块逐字相同**（`MusicPlayerView(albumArtNamespace:)`），
/// 只是搬运到了模块这一侧（一对一替换）。
///
/// 文件内私有：它是本模块的渲染细节，不进任何名单、不给别的模块用。
///
/// **命名空间按「宿主注入 → 自带兜底」两档取**（口径 5 / D-08）：宿主 `HomeStripView` 注入的是
/// 折叠态播放器共享的那一条（`.environment(\.homeAlbumArtNamespace, …)`），配对动画因此与改动前
/// 一致；没人注入时（例如将来在别处渲染这个块）退回本视图自己的 `@Namespace`——同一块内的
/// 动画仍成立，跨视图的那一对静默失效，不崩、不空白。
///
/// **块内不自己观察 `MusicManager`**：`MusicPlayerView` 的部件（`AlbumArtView` /
/// `MusicControlsView`）本来就各自 `@ObservedObject` 它，这里再观察一次只是重复订阅；
/// 「块在不在」那件事由 `content(for: .home)` 的判据与 `HomeStripView` 的观察承担。
private struct MusicHomeBlockView: View {
    @Environment(\.homeAlbumArtNamespace) private var albumArtNamespace
    @Namespace private var fallbackNamespace

    var body: some View {
        MusicPlayerView(albumArtNamespace: albumArtNamespace ?? fallbackNamespace)
    }
}
