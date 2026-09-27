//
//  ModuleContextFactory.swift
//  Gourd 模块内核 · 注入面工厂（P1 批次 / T2）
//
//  docs/13-runtime-kernel.md D-05：本批 `ModuleContext` 只有 host / config / logger / ui 四个面 + moduleID，
//  `notch` / events / storage / scheduler / permissions / secrets / clock 七个面属 P1-2/P1-3。
//  本文件是 config / ui 两个句柄的唯一实现落点——模块侧只拿到协议。
//

import Foundation
import os

/// 构造模块的 `ModuleContext`。
///
/// `redraw` 由宿主注入：注册表（T2）把 `requestRedraw` 接到自己的 `objectWillChange` 上，
/// T3 的 `ModuleHostView` 观察注册表即可重绘；单测注入计数器即可断言转发。
@MainActor
public enum ModuleContextFactory {
    public static func make(manifest: ModuleManifest, redraw: @escaping () -> Void) -> ModuleContext {
        let logger = ModuleLogger(moduleID: manifest.id, shortID: manifest.shortID)
        return ModuleContext(
            moduleID: manifest.id,
            host: hostInfo(),
            config: ManifestConfigHandle(manifest: manifest, logger: logger),
            logger: logger,
            ui: RedrawUIHandle(redraw: redraw)
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

/// 宿主给模块的 UI 能力（06 §3.4 的本批子集：`present(Overlay)` 属 P1-2 的 OverlayHost）。
private final class RedrawUIHandle: UIHandle {
    private let redraw: () -> Void

    init(redraw: @escaping () -> Void) {
        self.redraw = redraw
    }

    /// 转发宿主注入的重绘闭包（注册表 → `objectWillChange`）。
    func requestRedraw() {
        redraw()
    }

    /// 低功耗信号属 P1-3，本批恒 false。
    var isLowPower: Bool { false }
}
