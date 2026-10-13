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
        case .missingDefault: return String(localized: "ai.error.missingDefault")
        case .profileNotFound: return String(localized: "ai.error.profileNotFound")
        case .capabilityMismatch: return String(localized: "ai.error.capabilityMismatch")
        case .invalidEndpoint: return String(localized: "ai.error.invalidEndpoint")
        case .invalidConfiguration: return String(localized: "ai.error.invalidConfiguration")
        case .configurationReadFailed: return String(localized: "ai.error.configurationReadFailed")
        case .configurationWriteFailed: return String(localized: "ai.error.configurationWriteFailed")
        case .secretReadFailed: return String(localized: "ai.error.secretReadFailed")
        case .secretWriteFailed: return String(localized: "ai.error.secretWriteFailed")
        case .secretDeleteFailed: return String(localized: "ai.error.secretDeleteFailed")
        case .rollbackFailed: return String(localized: "ai.error.rollbackFailed")
        case .invalidRequest: return String(localized: "ai.error.invalidRequest")
        case .missingCredential: return String(localized: "ai.error.missingCredential")
        case .timedOut: return String(localized: "ai.error.timedOut")
        case .cancelled: return String(localized: "ai.error.cancelled")
        case .transportFailed: return String(localized: "ai.error.transportFailed")
        case .redirectRejected: return String(localized: "ai.error.redirectRejected")
        case .responseTooLarge: return String(localized: "ai.error.responseTooLarge")
        case .httpStatus(let status):
            return String(format: String(localized: "ai.error.httpStatus"), status)
        case .invalidResponse: return String(localized: "ai.error.invalidResponse")
        }
    }
}
