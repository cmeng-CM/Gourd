//
//  ModuleRegistry.swift
//  Gourd 模块内核 · 注册表与生命周期（P1 批次 / T2）
//
//  形态仿写上游既有的同构先例 `managers/Extensions/ExtensionNotchExperienceManager.swift`
//  （`@Published` 投影 + 按 id 查找内容 + 启用门 + 优先级排序）：D-03 定为**仿写形态、不继承**——
//  那套是扩展通道的线协议身份（B 表冻结项），混用会把两条生命周期绑在一起。
//
//  06 §3.3 的硬性规则落点：单个模块 `activate()` 抛错**只把自己置为失败**（不崩、不重试），
//  其余模块照常激活——P1 验收 A6 / docs/13 失败信号「抛错模块不得让 bootstrap() 提前返回」。
//

import Combine
import Foundation
import SwiftUI
import os

// MARK: - 运行时状态与 tab 投影

/// 模块的运行时状态（06 §4 状态机的**本批子集**）。
///
/// 与 06 §4 相比缺 `degraded` 与运行期超时计数（docs/13「已知限制」11）：本批的失败隔离
/// 只覆盖 `activate()` 抛错。
public enum ModuleRuntimeState: Equatable {
    /// 已注册但未启用（`defaultEnabled == false`）：不实例化、不激活、不进 tab。
    case disabled
    /// `activate()` 执行中。在 `@Published` 投影里只于切换的一瞬间可见。
    case activating
    /// 已激活：`content(for:)` 转发给它；`surfaces` 含 `.expanded` 时进 tab 列表。
    case active
    /// `activate()` 抛错——**终态**，模块被禁用、不重试（06 §3.3 硬性规则 1）。
    case failed(reason: String)
}

/// 展开面板的一个 tab 条目（模块清单在 UI 上的投影；06 §3.2）。
public struct ModuleTabEntry: Identifiable, Equatable {
    /// 模块 id（`com.cmeng.gourd.<shortID>`）。
    public let id: String
    /// 已本地化标题（解析顺序见 `ModuleRegistry.label(for:)`）。
    public let label: String
    /// SF Symbol 名（生产路径不调 `validate()`，本批未校验符号可解析性，见 docs/13「已知限制」17）。
    public let symbolName: String
    /// `defaultPlacement.order`，无 placement 时 `Int.max`（排在最后）。
    public let order: Int
}

/// 一条**瞬时浮层**（09 §5.5 呈现 ①：新事件到达时在折叠态刘海上短暂展示）。
///
/// 与 `ModuleCompactSlotView` / `ModuleHostView` 的关系：那两处渲染的是**常驻内容**
/// （模块答什么就显示什么，由模块自己的状态驱动）；浮层是**宿主托管的短命条目**——
/// 谁先请求谁显示、到期自动消失，模块不持有它的生命周期。
///
/// `id` 与模块 id 无关：它是「这一次弹出」的身份，`presentHUD` 的到期任务据此判断
/// 「我这条还在不在台前」（见 `presentHUD` 的只清自己那一条）。
public struct ModuleHUD: Identifiable {
    public let id: UUID
    public let moduleID: String
    public let view: AnyView
    /// 到期时刻（由 `presentHUD` 按夹取后的 ttl 算好，日志与测试读它）。
    public let expiresAt: Date
}

// MARK: - ModuleRegistry

/// 模块注册表：注册 → 启用门 → 激活 → 内容转发 → UI 投影。
///
/// 单例（`shared`）：06 §3.3 R2 要求模块不持全局单例，全局状态收在宿主这一层。
/// 生命周期由组合根 `KernelBootstrap` 驱动（注册 + `bootstrap()`）。
@MainActor
public final class ModuleRegistry: ObservableObject {
    public static let shared = ModuleRegistry()

    /// 每个模块的运行状态。**注册了但尚未 `bootstrap()` 的启用模块不在这里**——
    /// 状态只记「已判定」的结果（active / failed / disabled），判定由 `bootstrap()` 落。
    @Published public private(set) var states: [String: ModuleRuntimeState] = [:]
    /// 注册表：id → manifest。同 id 只留先注册者（06 §10.1 第 14 步的全局 id 唯一）。
    public private(set) var manifests: [String: ModuleManifest] = [:]

    /// 当前正在展示的瞬时浮层；nil = 无（关闭态自然回落到 live activity 链的其它分支）。
    @Published public private(set) var activeHUD: ModuleHUD?

    /// 浮层 ttl 的夹取区间（秒）。**下界 1s**：低于它的浮层肉眼看不见（等于没弹）；
    /// **上界 15s**：09 §5.5 的浮层是「瞬时」的，不能变成常驻占位（那会让关闭态
    /// 永久让位给一条通知）。模块传什么都会落在这个区间内。
    public static let hudTTLRange: ClosedRange<TimeInterval> = 1...15

    /// 已激活的实例。只在 `activate()` 成功后入驻，失败即摘除。
    private var instances: [String: any GourdModule] = [:]
    /// id → 类型。`manifests` 只够判启用与排序，实例化还需要元类型。
    private var moduleTypes: [String: any GourdModule.Type] = [:]
    private let log = os.Logger(subsystem: "com.cmeng.gourd.kernel", category: "registry")

    private init() {}

    // MARK: - 注册

    /// 注册模块类型。**幂等**：同 id 重复注册记 warning 并忽略（不覆盖先注册者）。
    ///
    /// `enabled` 是组合根注入的启用门（`KernelBootstrap` 传
    /// `manifests[$0]?.defaultEnabled ?? false`——06 §2.2 的 `defaultEnabled` 缺省 `false`）。
    /// 因此判启用时**该模块的 manifest 必须已在表内**：本方法先落全部 manifest，再逐个过门；
    /// 未过门的落 `.disabled`，过门的**不写状态**（首个终态由 `bootstrap()` 落）。
    public func register(_ types: [any GourdModule.Type], enabled: @escaping (String) -> Bool) {
        var accepted: [ModuleManifest] = []
        for type in types {
            let manifest = type.manifest
            guard manifests[manifest.id] == nil else {
                log.warning("忽略重复注册的模块 \(manifest.id, privacy: .public)")
                continue
            }
            manifests[manifest.id] = manifest
            moduleTypes[manifest.id] = type
            accepted.append(manifest)
        }
        for manifest in accepted where !enabled(manifest.id) {
            states[manifest.id] = .disabled
        }
    }

    // MARK: - 生命周期

    /// 逐个实例化并 `activate()`。
    ///
    /// **跳过规则**：`states` 里已有判定结果的 id 一律跳过——`active` 跳过（不重复激活）、
    /// `disabled` 跳过（不实例化）、`failed` 跳过（**不重试**）。因此本方法幂等，
    /// 可在启动流程里安全重复调用。
    ///
    /// 单个模块抛错只把自己置 `.failed(reason:)` 并继续下一个（06 §3.3 硬性规则 1）。
    /// 迭代顺序按 id 升序（稳定，便于复现「失败模块之后的兄弟模块仍被激活」）。
    public func bootstrap() async {
        for manifest in manifests.values.sorted(by: { $0.id < $1.id }) {
            guard states[manifest.id] == nil, let type = moduleTypes[manifest.id] else { continue }

            states[manifest.id] = .activating
            let instance = type.init(context: ModuleContextFactory.make(
                manifest: manifest,
                // requestRedraw 的路由：注册表是模块与 UI 之间唯一的可观测点，
                // T3 的 ModuleHostView 观察注册表即可被模块的重绘请求驱动。
                redraw: { [weak self] in
                    guard let self else { return }
                    self.objectWillChange.send()
                }
            ))

            do {
                try await instance.activate()
                instances[manifest.id] = instance
                states[manifest.id] = .active
            } catch {
                // 半激活的实例不留：先摘出注册表，再兜底 deactivate 清理它已起的副作用。
                instances[manifest.id] = nil
                states[manifest.id] = .failed(reason: String(describing: error))
                await instance.deactivate()
                log.error("模块 \(manifest.id, privacy: .public) activate() 抛错：\(String(describing: error), privacy: .public)")
            }
        }
    }

    /// 停用全部模块并**清空注册表**（instances / states / manifests / moduleTypes）。
    ///
    /// 语义是「组合根的对称收尾」：应用退出或内核重置时调用。单测也用它做用例间隔离——
    /// 注册表是单例，`manifests` / `states` 不清会互相污染。
    public func deactivateAll() async {
        for id in instances.keys.sorted() {
            await instances[id]?.deactivate()
        }
        instances.removeAll()
        states.removeAll()
        manifests.removeAll()
        moduleTypes.removeAll()
        // 浮层属于「某个模块的一次弹出」：注册表清空后它没有归属，必须一并撤掉
        //（否则单测之间会串味，退出路径上也会留下一帧孤儿视图）。
        clearHUD()
    }

    /// 已激活的模块实例；未注册 / 未启用 / 已失败 / 尚未 `bootstrap()` → nil。
    public func instance(for id: String) -> (any GourdModule)? {
        instances[id]
    }

    // MARK: - UI 投影

    /// 展开面板的 tab 列表：仅 `active` 且 `surfaces` 含 `.expanded`，
    /// 按 `order` 升序、同 `order` 按 id 字典序（`order` 缺省 = `Int.max`，排最后）。
    public var tabEntries: [ModuleTabEntry] {
        manifests.values
            .filter { states[$0.id] == .active && $0.surfaces.contains(.expanded) }
            .map { manifest in
                ModuleTabEntry(
                    id: manifest.id,
                    label: Self.label(for: manifest),
                    symbolName: manifest.icon.name ?? "",
                    order: manifest.defaultPlacement?.order ?? Int.max
                )
            }
            .sorted { ($0.order, $0.id) < ($1.order, $1.id) }
    }

    /// 折叠态中央槽位的候选：`active` 且 `surfaces` 含 `.compact`，
    /// 按 `order` 升序、同 `order` 按 id 字典序（与 `tabEntries` 同一比较器）。
    ///
    /// 本批**只有中央槽位**：06 §6.2 的三槽布局（`slot` 的 left/right 与每侧上限）
    /// 仍需重构关闭态的 HStack，仍推 P2（docs/13「明确不做」）。
    public var compactEntries: [ModuleTabEntry] {
        manifests.values
            .filter { states[$0.id] == .active && $0.surfaces.contains(.compact) }
            .map { manifest in
                ModuleTabEntry(
                    id: manifest.id,
                    label: Self.label(for: manifest),
                    symbolName: manifest.icon.name ?? "",
                    order: manifest.defaultPlacement?.order ?? Int.max
                )
            }
            .sorted { ($0.order, $0.id) < ($1.order, $1.id) }
    }

    /// 折叠态中央槽位的内容：取 `compactEntries` 的**第一个**转发；无候选、或模块答 `.none` → `.none`
    ///（不占位，关闭态自然回落到人脸动画 / 空矩形等既有分支）。
    ///
    /// 请求按 06 §3.1 填成「compact + 折叠 + 中央槽位」：`sizeHint` 用 `.zero`（槽位不做尺寸协商，
    /// 模块自报高度属 P2）、`reason` 用 `.initial`（宿主尚未记录「第几次评估」，与 `ModuleHostView` 同一口径）。
    public func compactSlotContent() -> ModuleContent {
        guard let entry = compactEntries.first else { return .none }
        return content(for: entry.id, request: Self.compactSlotRequest)
    }

    /// 折叠态中央槽位的定值请求（`compactSlotContent()` 的唯一生产点）。
    private static let compactSlotRequest = ContentRequest(
        surface: .compact,
        phase: .collapsed,
        slot: .center,
        sizeHint: .zero,
        reason: .initial,
        isLowPower: false
    )

    /// tab 标题的解析顺序：Localizable key 形态 → locale 表（`en`）→ `shortID`。
    ///
    /// key 拿不到译文时 `Bundle.localizedString(forKey:value:table:)` **原样返回 key**，
    /// 借此判「解析不到」——T4 把 `module.<shortID>.name` 写进 `Localizable.xcstrings` 后
    /// 这里自然切到本地化文案，无需改代码。
    static func label(for manifest: ModuleManifest) -> String {
        if let key = manifest.name.key, !key.isEmpty {
            let localized = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
            if !localized.isEmpty, localized != key { return localized }
        }
        if let english = manifest.name.table?["en"], !english.isEmpty { return english }
        return manifest.shortID
    }

    // MARK: - 内容转发

    /// 把内容请求转给已激活的模块。**未知 id / 未激活（disabled / failed / 尚未 bootstrap）
    /// 一律返回 `.unavailable`**——不崩、也不返回空内容，渲染侧据此显示占位与原因（06 §3.2）。
    ///
    /// `.view` 仅限内置模块的硬边界判定（06 §3.2）**属 P4**：本批只有 `kind == builtin`
    /// 的内置模块（`register()` 不校验 manifest，见 docs/13「已知限制」17），插件越权边界
    /// 随 `PluginModuleAdapter` 一起实现；本批注册表只做「是否激活」的裁剪。
    public func content(for id: String, request: ContentRequest) -> ModuleContent {
        guard let instance = instances[id], states[id] == .active else {
            let reason = manifests[id] == nil ? "模块未注册：\(id)" : "模块未激活：\(id)"
            log.warning("content 请求降级：\(reason, privacy: .public)")
            return .unavailable(reason: reason)
        }
        return instance.content(for: request)
    }

    // MARK: - 瞬时浮层（HUD）

    /// 弹出瞬时浮层（模块侧入口是 `UIHandle.presentTransient`）。
    ///
    /// **覆盖语义**：已有浮层直接被新的一条替换——不排队、不叠加。理由：刘海关闭态只有
    /// 一格位置（见 `ContentView` 关闭态优先级链的插入注释），两条浮层同时到达时「后到者
    /// 就是最新事件」，排队只会让先到的那条在过期后突然冒出来。
    ///
    /// `ttl` 一律夹取到 `hudTTLRange`（1…15s）：模块给 0.2s 等于没弹，给 600s 等于常驻。
    ///
    /// 到期清除**只清自己那一条**：任务醒来时先比对 `activeHUD?.id`，被后来者替换过就直接返回——
    /// 否则「先弹 A（短 ttl）、再弹 B（长 ttl）」会让 A 的旧任务把 B 提前清掉。
    public func presentHUD(moduleID: String, view: AnyView, ttl: TimeInterval) {
        let clamped = min(max(ttl, Self.hudTTLRange.lowerBound), Self.hudTTLRange.upperBound)
        let hud = ModuleHUD(id: UUID(), moduleID: moduleID, view: view, expiresAt: Date().addingTimeInterval(clamped))
        activeHUD = hud
        log.info("presentHUD：模块 \(moduleID, privacy: .public)，ttl \(clamped, privacy: .public)s")

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(clamped))
            guard let self, self.activeHUD?.id == hud.id else { return }
            self.clearHUD()
        }
    }

    /// 撤掉当前浮层（用户侧无入口；到期任务、模块显式收尾与 `deactivateAll()` 走这里）。
    ///
    /// 语义是**幂等**的：没有浮层时是空操作（到期任务的 `guard` 之后可能重复到达）。
    public func clearHUD() {
        guard activeHUD != nil else { return }
        activeHUD = nil
    }
}
