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
//  ModuleContextFactory.swift
//  Gourd 模块内核 · 注入面工厂（P1 批次 / T2）
//
//  docs/13-runtime-kernel.md D-05：本批 `ModuleContext` 只有 host / config / logger / ui 四个面 + moduleID，
//  `notch` / events / storage / scheduler / permissions / secrets / clock 七个面属 P1-2/P1-3。
//  本文件是 config / ui 两个句柄的唯一实现落点——模块侧只拿到协议。
//
//  P2 首页修正批次 / T5 修复轮：多一个 `configHandle(for:)`——**宿主侧（设置页）**要读写某个
//  已注册模块的 config 时，拿的是与模块侧**同一个实现**的句柄（suite 名与存储编码因此只有一处）。
//  唯一的调用点是组件页给音乐卡「显示封面」开的口子，见那里的注释。
//

import Foundation
import SwiftUI
import os

/// 构造模块的 `ModuleContext`。
///
/// `redraw` 由宿主注入：注册表（T2）把 `requestRedraw` 接到自己的 `objectWillChange` 上，
/// T3 的 `ModuleHostView` 观察注册表即可重绘；单测注入计数器即可断言转发。
///
/// `collapse` 也由宿主注入（**应用侧**）：`UIHandle.requestCollapse()` 只是转给它，
/// 内核这一层不认识窗口、也不认识「哪块屏」（见 docs/13 D-28）。默认 `{}` 让既有调用点
/// （单测、未接线时的注册表）一字不改：没有注入时收起请求就是空操作。
@MainActor
public enum ModuleContextFactory {
    public static func make(
        manifest: ModuleManifest,
        redraw: @escaping () -> Void,
        collapse: @escaping () -> Void = {}
    ) -> ModuleContext {
        let logger = ModuleLogger(moduleID: manifest.id, shortID: manifest.shortID)
        return ModuleContext(
            moduleID: manifest.id,
            host: hostInfo(),
            config: ManifestConfigHandle(manifest: manifest, logger: logger),
            logger: logger,
            ui: RedrawUIHandle(moduleID: manifest.id, redraw: redraw, collapse: collapse)
        )
    }

    /// 宿主侧（设置页）读写**某个已注册模块自己的 config** 时拿的句柄。
    ///
    /// **与模块侧是同一个实现**（同一个 `ManifestConfigHandle`）：suite 名
    /// `com.cmeng.gourd.module.<shortID>` 与「值按 JSON 字节存」的口径因此只有一处，
    /// 「设置页写进 A 域、模块读 B 域」或「一边存 Data 一边读 String」这类静默故障在构造上
    /// 就不可能发生（`ManifestConfigHandle` 保持 `private`——宿主只经协议拿到读写两个方法）。
    ///
    /// 用途边界（P2 首页修正批次 / T5 修复轮的唯一调用点）：组件页给**音乐卡的「显示封面」**
    /// 这一个键开的口子。模块的 config 写入口不是通用能力——「按 manifest schema 自动生成
    /// 控件」是另一个批次的活（见 `.workflow/p2-home-fit/reports/T5-fix.md`）。
    ///
    /// 句柄是薄壳（manifest schema 快照 + 一次 `UserDefaults(suiteName:)`），调用点每次现取即可；
    /// 覆盖值读的仍是当前落盘值（`get` 不去缓存），因此「写完下一次读就变」成立。
    static func configHandle(for manifest: ModuleManifest) -> ConfigHandle {
        ManifestConfigHandle(
            manifest: manifest,
            logger: ModuleLogger(moduleID: manifest.id, shortID: manifest.shortID)
        )
    }

    /// 宿主信息：appVersion 取 `Bundle.main` 的 `CFBundleShortVersionString`，
    /// macOSVersion 取 `ProcessInfo` 的版本三元组，`apiVersion` 取宿主实现版本的单一常量
    /// （T1 的 `HostInfo.currentAPIVersion` = `"1.0"`，不再写第二份字面量）。
    static func hostInfo() -> HostInfo {
        HostInfo(
            appVersion: Bundle.main.releaseVersionNumber ?? "0",
            apiVersion: HostInfo.currentAPIVersion,
            macOSVersion: macOSVersion
        )
    }

    /// `"26.0.1"` 形态（major.minor.patch）。供模块做平台门控（06 §3.4 只要求一个版本串，未定形态）。
    static var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}

// MARK: - ConfigHandle 的本批实现

/// 简化 `ConfigHandle`（docs/13 D-05 / 07 §2 的字段级规范的本批子集）。
///
/// - 默认值来源：`manifest.config.properties[key]?.default`（唯一来源，本批不读配置文件）；
/// - 覆盖值来源：UserDefaults 的模块专属 suite `com.cmeng.gourd.module.<shortID>`
///   （**临时落点**，P1-3 随 ConfigStore(JSON) 迁移，见 docs/13「已知限制」12）；
/// - schema 之外的键：`get` 返回 nil、`set` 返回 false（schema 是本批的唯一契约）；
/// - 本批**不做** 07 §2 的 `observe` / `schema` / nil 重置语义。
private final class ManifestConfigHandle: ConfigHandle {
    private let properties: [String: ConfigNode]
    private let overrides: UserDefaults?
    private let logger: ModuleLogger

    init(manifest: ModuleManifest, logger: ModuleLogger) {
        self.properties = manifest.config?.properties ?? [:]
        self.overrides = UserDefaults(suiteName: "com.cmeng.gourd.module.\(manifest.shortID)")
        self.logger = logger
    }

    func get<T: Codable & Sendable>(_ key: String, as type: T.Type) -> T? {
        guard let node = properties[key] else { return nil }
        if let data = overrides?.data(forKey: key) {
            if let stored = try? JSONDecoder().decode(T.self, from: data) {
                return stored
            }
            // 07 §2 规则 4：覆盖值被改坏（类型不符）→ 回落 default 并记 warning，不崩、不清空。
            logger.warn("配置 \(key) 的覆盖值与请求类型不符，回落到 manifest 默认值")
        }
        guard let fallback = node.default else { return nil }
        return Self.decode(fallback, as: T.self)
    }

    func set<T: Codable & Sendable>(_ key: String, to value: T) -> Bool {
        guard properties[key] != nil else { return false }
        guard let overrides, let data = try? JSONEncoder().encode(value) else { return false }
        overrides.set(data, forKey: key)
        return true
    }

    /// 走 JSON 往返把 manifest 的 `ConfigValue` 转成模块请求的类型——两者是同一套 JSON 词汇。
    ///
    /// **int → Double 互认在这里自动成立**：`{"type": "number", "default": 2}` 的裸值 `2`
    /// 在 `ConfigValue` 里按裸值形态被判成 `.int(2)`（T1 的已知口径），而 `JSONDecoder`
    /// 认 JSON 的 `2` 为合法 `Double`——所以 `get("scale", as: Double.self)` 拿得到 `2.0`，
    /// 不会静默返回 nil（否则 `manifests` 里 `number` 型的整数默认值会读不出来）。
    private static func decode<T: Codable & Sendable>(_ value: ConfigValue, as type: T.Type) -> T? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - UIHandle 的本批实现

/// 宿主给模块的 UI 能力（06 §3.4 的本批子集：`present(Overlay)` 属 P1-2 的 OverlayHost；
/// 瞬时浮层按 D-22 加回）。`@MainActor` 与协议一致——两个出口都只从主线程可达。
@MainActor
private final class RedrawUIHandle: UIHandle {
    private let moduleID: String
    private let redraw: () -> Void
    private let collapse: () -> Void

    init(moduleID: String, redraw: @escaping () -> Void, collapse: @escaping () -> Void) {
        self.moduleID = moduleID
        self.redraw = redraw
        self.collapse = collapse
    }

    /// 转发宿主注入的重绘闭包（注册表 → `objectWillChange`）。
    func requestRedraw() {
        redraw()
    }

    /// 低功耗信号属 P1-3，本批恒 false。
    var isLowPower: Bool { false }

    /// 瞬时浮层：转发到注册表（**唯一实现落点**——覆盖与到期清除都在那边，
    /// 这里只负责补上 moduleID，模块自己不持有浮层的生命周期）。
    func presentTransient(view: AnyView, ttl: TimeInterval) {
        ModuleRegistry.shared.presentHUD(moduleID: moduleID, view: view, ttl: ttl)
    }

    /// 主动撤浮层：**先判归属**再撤——模块只能撤自己弹的那一条
    /// （`dismissHUD(id:)` 只认 id，归属判定在模块与 id 之间缺的一环，落在这里）。
    /// 当前浮层不是本模块的（被别的模块抢先 / 已经到期清空）时什么都不做。
    func dismissTransient() {
        let registry = ModuleRegistry.shared
        guard let hud = registry.activeHUD, hud.moduleID == moduleID else { return }
        registry.dismissHUD(id: hud.id)
    }

    /// 收起刘海：**只转发宿主注入的闭包**（唯一实现落点在应用侧——哪块屏、当前是否展开、
    /// 收起动画都由它定）。内核这一层不碰窗口（06 §3.3 R1），也不做裁决。
    func requestCollapse() {
        collapse()
    }
}
