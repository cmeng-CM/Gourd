//
//  ModuleContext.swift
//  Gourd 模块内核 · 注入面（P1 批次 / T1）
//
//  06 §3.4 的本批实现子集（docs/13-runtime-kernel.md D-05）：
//  本批**不含** notch / events / storage / scheduler / permissions / secrets / clock
//  七个面——它们需要 per-screen 的 DynamicIslandViewModel 或未定的设计（P1-2/P1-3），
//  试点模块不需要。延后项与加回时的破坏面见 docs/13「明确不做」与「已知限制」。
//

import Foundation
import os

/// 模块的依赖注入面。**struct 而非 protocol**：它是数据载体（一堆句柄），不是行为契约；
/// 行为契约分布在各个 Handle 上，struct 也便于构造测试假体（06 §3.4 末）。
@MainActor
public struct ModuleContext {
    /// 模块 id（`com.cmeng.gourd.<shortID>`）。
    public let moduleID: String
    public let host: HostInfo
    /// 只读写本模块作用域（06 §3.4）。
    public let config: ConfigHandle
    /// 自动带 moduleID 与 subsystem 前缀。
    public let logger: ModuleLogger
    public let ui: UIHandle
}

/// 宿主信息（06 §3.4 的本批子集：`buildKind` / `epoch` 未纳入）。
public struct HostInfo: Sendable, Equatable {
    /// 宿主 `CFBundleShortVersionString`。
    public let appVersion: String
    /// 宿主实现的 API 版本（06 §8.1：`MAJOR.MINOR`，不含 patch）。
    public let apiVersion: String
    public let macOSVersion: String
}

public extension HostInfo {
    /// 宿主当前实现的 API 主版本（本批只实现 1.0）。
    static let currentAPIMajor = 1
    /// 宿主当前实现的 API 次版本（`ModuleManifest.validate()` 的兼容上界）。
    static let currentAPIMinor = 0
    /// `"1.0"`——`manifest.apiVersion` 与 `HostInfo.apiVersion` 的共同基准。
    static var currentAPIVersion: String { "\(currentAPIMajor).\(currentAPIMinor)" }
}

/// 配置读写（06 §3.4 / 07 §2 的简化形态，docs/13 D-05）。
///
/// 默认值来源：`manifest.config.properties[key]?.default`；覆盖值写 UserDefaults 命名空间
/// `com.cmeng.gourd.module.<shortID>`（**临时落点**，P1-3 随 ConfigStore(JSON) 迁移，
/// 见 docs/13「已知限制」12）。方法名对齐 07 §2 的 `get`/`set`——
/// 本批**不做** `observe` / `schema` / nil 重置语义。
public protocol ConfigHandle: AnyObject {
    func get<T: Codable & Sendable>(_ key: String, as: T.Type) -> T?
    func set<T: Codable & Sendable>(_ key: String, to value: T) -> Bool
}

/// 宿主给模块的 UI 能力（06 §3.4 的本批子集：`present(Overlay)` 属 P1-2 的 OverlayHost）。
public protocol UIHandle: AnyObject {
    /// 触发 `ModuleHostView` 重绘。
    func requestRedraw()
    /// 低功耗信号（架构 §7 要求动画可关）。本批恒 false（P1-3）。
    var isLowPower: Bool { get }
}

/// 自动带 `moduleID` 与 subsystem 前缀 `com.cmeng.gourd.module.<shortID>` 的日志器。
public final class ModuleLogger: @unchecked Sendable {
    private let moduleID: String
    private let log: os.Logger

    /// - Parameters:
    ///   - moduleID: 模块 id，进日志行前缀，便于按模块过滤。
    ///   - shortID: manifest 的 `shortID`，只用于拼 subsystem。
    public init(moduleID: String, shortID: String) {
        self.moduleID = moduleID
        self.log = os.Logger(subsystem: "com.cmeng.gourd.module.\(shortID)", category: "module")
    }

    public func info(_ message: String) {
        log.info("[\(self.moduleID, privacy: .public)] \(message, privacy: .public)")
    }

    public func warn(_ message: String) {
        log.warning("[\(self.moduleID, privacy: .public)] \(message, privacy: .public)")
    }

    public func error(_ message: String) {
        log.error("[\(self.moduleID, privacy: .public)] \(message, privacy: .public)")
    }
}
