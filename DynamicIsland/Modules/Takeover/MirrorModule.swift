//
//  MirrorModule.swift
//  Gourd 内置模块 · 镜子接管（P2 接管批次 / T4）
//
//  docs/20-component-page.md §接口与数据形状 5 的 mirror 行逐字落地：**接管 = 模块拥有渲染点 +
//  启用真源是上游键**（D-01）。上游 `HomeStripView` 里那个写死的镜子块（`mirrorIsVisible` 判据 +
//  `case .mirror` 分支 + `mirrorBlockWidth`）同批删除——首页 strip 的镜子块从此由**本模块的投影**
//  产出，一对一替换，不允许并存（并存就是两个镜子块）。
//
//  四条刻意写死的口径（改动前先读）：
//
//  1. **只声明 `home`**（§已知限制：本批所有接管模块都不声明 `compact`——折叠态左右槽位已按
//     用户 2026-09-29 的决定降级）：`.expanded` / `.compact` / `.lockscreen` 一律答 `.none`
//     （不占位、不算失败，06 §3.2）。因为不声明 `expanded`，`isTabVisible()` 对本模块无意义
//     （投影先按 `surfaces` 过滤），因此**不重写**它。
//  2. **启用真源是 `showMirror`**（`takeoverEnableKey`）：组合根的启用门直接读它，
//     `moduleEnableOverrides` 与 `manifest.defaultEnabled` 都不再看——「模块开不开」与
//     「镜子功能开不开」是同一个布尔量，不存在第二份状态（D-01）。
//  3. **存在性判据不带展开态**（docs/20 §做法 机制一末段）：`.home` 的定义就是「展开面板首页的
//     一条 strip 块」，块只会在展开态被渲染，所以判据是 `showMirror && cameraAvailable`——
//     不重复 `vm.notchState == .open`（旧内置块的写法），判据抽成纯函数 `isVisible(showMirror:
//     cameraAvailable:)` 以便单测；答 `.none` 的块**不占位**（「是/否」而不是透明度）。
//  4. **`config` 只登记不接管**（D-03 / §已知限制 1）：三个键的键名与上游默认值写进 manifest
//     供审计，读写仍走上游 `Defaults`（`ConfigHandle` 对它们不生效）。默认值**从上游键取**
//     （`Defaults.Keys.<键>.defaultValue`），不另抄一个字面量——两处各写一个数就会漂。
//
//  文案走 Localizable key（06 §3.3 R5）：`module.mirror.name` / `module.mirror.summary`。
//

import Defaults
import SwiftUI

// MARK: - MirrorModule

/// 镜子接管模块（`docs/20` §接口与数据形状 5 的 mirror 行；`docs/14` §1 的 `com.cmeng.gourd.mirror`）。
///
/// 渲染点 = 上游那个 `CameraPreviewView(webcamManager: WebcamManager.shared)`（首页 strip 的镜子块），
/// 除它之外本模块不占任何 surface。
@MainActor
final class MirrorModule: GourdModule {
    /// 模块 id 的**唯一字面量**（manifest 与 `HomeBlockOrdering.migratingLegacyIDs` 的接收方都用它，
    /// 后者因「纯逻辑文件不认模块类型」写字面量，两处一致由用例钉住）。
    static let moduleID = "com.cmeng.gourd.mirror"

    /// 静态元数据（docs/20 §接口与数据形状 5 + T-12 的取值口径）。
    ///
    /// - `surfaces: [.home]`：**只声明首页块**——折叠槽位本批不占（口径 1）；声明 `.home` 与
    ///   「有没有展开 tab」互不蕴含，因此本模块不进 tab 投影；
    /// - `defaultPlacement: Placement(slot: nil, order: 2)`：`slot` 只在含 `compact` 时有意义，
    ///   这里只用 `order` 这个排序键（首页块序），**2 = 被接管的内置镜子块原本的默认序号**
    ///   （`HomeBlockOrdering.BuiltinBlock.mirror.defaultOrder`）——接管后顺序与接管前一致；
    /// - `defaultEnabled: false` = **上游键的默认值**（`showMirror` 上游默认 `false`）：它只在
    ///   「接管键读不到」时不生效，填它是为了让卡片上那行「默认关闭」出现在镜子卡
    ///   （接管模块的启用状态由启用门直接读上游键，见口径 2）；
    /// - `permissions: []`：本批只搬渲染归属与开关真源。**摄像头权限是上游 `WebcamManager`
    ///   本来就有的那条**，本模块不新增、不申请（全局约束：不新增 TCC 权限）。
    static let manifest = ModuleManifest(
        manifestVersion: 1,
        id: moduleID,
        name: LocalizedText(key: "module.mirror.name"),
        summary: LocalizedText(key: "module.mirror.summary"),
        icon: IconSpec(type: "symbol", name: "camera"),
        version: "1.0.0",
        apiVersion: HostInfo.currentAPIVersion,
        kind: "builtin",
        surfaces: [.home],
        defaultPlacement: Placement(slot: nil, order: 2),
        defaultEnabled: false,
        permissions: [],
        config: ConfigSchema(
            type: "object",
            properties: [
                // 上游总开关（= 本模块的 `takeoverEnableKey`）。默认值取上游键的默认值
                "showMirror": ConfigNode(
                    type: "boolean",
                    title: nil,
                    default: .bool(Defaults.Keys.showMirror.defaultValue),
                    values: nil,
                    itemType: nil
                ),
                // 镜子形状：`Rectangular` / `Circular`。**按枚举声明顺序列出**（`MirrorShapeEnum`
                // 不是 `CaseIterable`，故显式给两个 case）；上游设置页的 Picker 展示顺序是
                // Circle → Square，与本登记无关（config 不参与渲染）
                "mirrorShape": ConfigNode(
                    type: "enum",
                    title: nil,
                    default: .string(Defaults.Keys.mirrorShape.defaultValue.rawValue),
                    values: [MirrorShapeEnum.rectangle.rawValue, MirrorShapeEnum.circle.rawValue],
                    itemType: nil
                ),
                // 选中的摄像头（`AVCaptureDevice.uniqueID`，空串 = 跟随第一台；上游设置页在下拉里写它）。
                // 设备 id 是运行期发现的值，因此只登记键名与默认值，不列 `values`——读写仍走上游键
                "selectedCameraID": ConfigNode(
                    type: "string",
                    title: nil,
                    default: .string(Defaults.Keys.selectedCameraID.defaultValue),
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
    static var takeoverEnableKey: Defaults.Key<Bool>? { .showMirror }

    // 接管三件套之二 `isTabVisible()`：本模块**不重写**它——它不声明 `expanded`，投影先按
    // `surfaces` 过滤，可见性钩子对它永远不被问到（`docs/20` §接口与数据形状 5 的 mirror 行同口径）。
    // 这里刻意留白：写一条 `= true` 只会让读者以为本模块有 tab。

    /// 接管三件套之三：宽度声明 = **被接管块原本的宽度**（D-10）——接管是「接住原来的呈现」，
    /// 不是顺手把镜子块从 140/160 改成宿主统一值 180/240。
    static var homeBlockWidth: ModuleHomeBlockWidth? { ModuleHomeBlockWidth(min: 140, ideal: 160) }

    /// 镜子块的**存在性判据**（纯函数，便于单测：口径 3）。
    ///
    /// 两段是「且」：功能开关（上游键）与**运行期条件**（有没有可用摄像头——摄像头拔掉时
    /// 块要消失，不是画一个空壳）。**不含展开态**：`.home` 块只在展开面板的首页渲染，
    /// 重复判一次 `notchState` 是旧内置块的写法（docs/20 §做法 机制一末段点名删除）。
    static func isVisible(showMirror: Bool, cameraAvailable: Bool) -> Bool {
        showMirror && cameraAvailable
    }

    /// 只记一条日志：镜子没有常驻副作用（采集会话由上游 `WebcamManager` 持有，
    /// 本批只搬渲染归属，不搬生命周期）。
    func activate() async throws {
        context.logger.info(
            "mirror 模块已激活（takeover=true，showMirror=\(Defaults[.showMirror])，cameraAvailable=\(WebcamManager.shared.cameraAvailable)）"
        )
    }

    /// 没有要收的东西：本模块不起 Task、不订阅、不持有视图外的资源（见 `activate()`）。
    func deactivate() async {}

    /// 只答 `home` 且**判据成立**才给 `.view`；不成立答 `.none`（不占位，口径 3）。
    /// `.expanded` / `.compact` / `.lockscreen` 一律 `.none`（口径 1：不占位、不算失败）。
    func content(for request: ContentRequest) -> ModuleContent {
        switch request.surface {
        case .home:
            // 判据读**当下**值（上游键 + 摄像头可用性）：投影与内容每一次都现问，不缓存——
            // 摄像头拔掉 / 开关关掉时块随之消失（重排由 `HomeStripView` 对 `WebcamManager` 的
            // 观察驱动，见那里的注释）。
            guard Self.isVisible(
                showMirror: Defaults[.showMirror],
                cameraAvailable: WebcamManager.shared.cameraAvailable
            ) else {
                return .none
            }
            return .view(AnyView(MirrorHomeBlockView()))
        case .expanded, .compact, .lockscreen:
            return .none
        }
    }
}

// MARK: - 首页块内容

/// 镜子块的视图：**与改动前的内置块逐字相同**（`CameraPreviewView(webcamManager:)`），
/// 只是搬运到了模块这一侧（一对一替换）。
///
/// 文件内私有：它是本模块的渲染细节，不进任何名单、不给别的模块用。
///
/// **自己观察 `WebcamManager`**（`@ObservedObject`）：采集会话起来 / 摄像头被拔掉时
/// 预览层与 `isSessionRunning` 变化，块内要跟着重画（与 `HomeStripView` 那一层对
/// `cameraAvailable` 的观察各管一件事：这里管「块里画什么」，那里管「块在不在」）。
private struct MirrorHomeBlockView: View {
    @ObservedObject var webcam = WebcamManager.shared

    var body: some View {
        CameraPreviewView(webcamManager: webcam)
    }
}
