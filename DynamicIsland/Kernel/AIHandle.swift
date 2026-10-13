// Copyright (C) 2026 Gourd Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// 内置模块共用的模型接口；调用方 Task 的取消只影响该次请求。
@MainActor
public protocol AIHandle: AnyObject {
    func complete(_ request: AIRequest) async throws -> AIResponse
}

public enum AICapability: String, Codable, CaseIterable, Sendable {
    case text, vision
}

public enum AIRole: String, Codable, Sendable {
    case system, user, assistant
}

public struct AIImage: Equatable, Sendable {
    public let data: Data
    public let mimeType: String

    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

public struct AIMessage: Equatable, Sendable {
    public let role: AIRole
    public let text: String
    public let images: [AIImage]

    public init(role: AIRole, text: String, images: [AIImage] = []) {
        self.role = role
        self.text = text
        self.images = images
    }
}

public struct AIRequest: Equatable, Sendable {
    public let purpose: String
    public let messages: [AIMessage]
    public let profileID: UUID?
    public let requiredCapability: AICapability
    public let maxOutputTokens: Int

    public init(purpose: String, messages: [AIMessage], profileID: UUID? = nil,
                requiredCapability: AICapability = .text, maxOutputTokens: Int = 2048) {
        self.purpose = purpose
        self.messages = messages
        self.profileID = profileID
        self.requiredCapability = requiredCapability
        self.maxOutputTokens = maxOutputTokens
    }
}

public struct AIResponse: Equatable, Sendable {
    public let text: String

    public init(text: String) { self.text = text }
}

/// 只携带固定错误分类和状态码；不回显底层错误、原文或凭据。
public enum AIError: Error, Equatable, LocalizedError, Sendable {
    case missingDefault(AICapability)
    case profileNotFound
    case capabilityMismatch
    case invalidEndpoint
    case invalidConfiguration
    case configurationReadFailed
    case configurationWriteFailed
    case secretReadFailed
    case secretWriteFailed
    case secretDeleteFailed
    case rollbackFailed
    case invalidRequest
    case missingCredential
    case timedOut
    case cancelled
    case transportFailed
    case redirectRejected
    case responseTooLarge
    case httpStatus(Int)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .missingDefault: return "请先选择默认 AI 模型。"
        case .profileNotFound: return "所选 AI 配置已不存在。"
        case .capabilityMismatch: return "所选模型未声明所需能力。"
        case .invalidEndpoint: return "端点须为 HTTPS 或本机 HTTP，且不能包含账户信息、查询或片段。"
        case .invalidConfiguration: return "AI 配置格式无效。"
        case .configurationReadFailed: return "无法读取 AI 配置。"
        case .configurationWriteFailed: return "无法保存 AI 配置。"
        case .secretReadFailed: return "无法读取 AI 凭据。"
        case .secretWriteFailed: return "无法保存 AI 凭据。"
        case .secretDeleteFailed: return "无法删除 AI 凭据。"
        case .rollbackFailed: return "保存失败且无法恢复凭据，请重新检查配置。"
        case .invalidRequest: return "AI 请求内容或输出限额无效。"
        case .missingCredential: return "请先配置 AI 凭据。"
        case .timedOut: return "AI 请求超时。"
        case .cancelled: return "AI 请求已取消。"
        case .transportFailed: return "无法连接 AI 端点。"
        case .redirectRejected: return "AI 端点跳转已拒绝。"
        case .responseTooLarge: return "AI 响应超过 1 MiB 限额。"
        case .httpStatus(let status): return "AI 端点返回 HTTP \(status)。"
        case .invalidResponse: return "AI 响应格式无效或没有文本。"
        }
    }
}
