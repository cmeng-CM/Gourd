// Copyright (C) 2026 Gourd Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import Foundation
import Security

/// 协议是数据格式，不是供应商白名单。
enum AIProtocol: String, Codable, CaseIterable, Sendable {
    case openAICompatible, anthropic, gemini, ollama
}

struct AIModelProfile: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var displayName: String
    var apiProtocol: AIProtocol
    var baseURL: String
    var modelID: String
    var capabilities: Set<AICapability>
    /// 独立 Keychain 命名空间里的 UUID，不包含密钥本身。
    var secretReference: UUID?

    init(id: UUID = UUID(), displayName: String, apiProtocol: AIProtocol,
         baseURL: String, modelID: String, capabilities: Set<AICapability> = [.text],
         secretReference: UUID? = nil) {
        self.id = id
        self.displayName = displayName
        self.apiProtocol = apiProtocol
        self.baseURL = baseURL
        self.modelID = modelID
        self.capabilities = capabilities
        self.secretReference = secretReference
    }
}

struct AIConfiguration: Codable, Equatable, Sendable {
    var profiles: [AIModelProfile] = []
    var defaultTextProfileID: UUID?
    var defaultVisionProfileID: UUID?
}

@MainActor
protocol AISecretStore: AnyObject {
    func read(reference: UUID) throws -> String?
    func write(_ secret: String, reference: UUID) throws
    func delete(reference: UUID) throws
}

@MainActor
protocol AIConfigurationPersistence: AnyObject {
    func read() throws -> Data?
    func write(_ data: Data) throws
}

@MainActor
final class AIDefaultsConfigurationPersistence: AIConfigurationPersistence {
    static let key = "gourd.ai.configuration.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }
    func read() throws -> Data? { defaults.data(forKey: Self.key) }
    func write(_ data: Data) throws { defaults.set(data, forKey: Self.key) }
}

/// 不读取或迁移屏幕助手旧 Defaults 凭据。
@MainActor
final class AIKeychainSecretStore: AISecretStore {
    private let service = "com.cmeng.gourd.ai.credentials.v1"

    private func query(_ reference: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: reference.uuidString]
    }

    func read(reference: UUID) throws -> String? {
        var request = query(reference)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { throw AIError.secretReadFailed }
        return value
    }

    func write(_ secret: String, reference: UUID) throws {
        let attributes = [kSecValueData as String: Data(secret.utf8)]
        let status = SecItemUpdate(query(reference) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(reference)
            item[kSecValueData as String] = Data(secret.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw AIError.secretWriteFailed }
        } else if status != errSecSuccess { throw AIError.secretWriteFailed }
    }

    func delete(reference: UUID) throws {
        let status = SecItemDelete(query(reference) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AIError.secretDeleteFailed }
    }
}

@MainActor
final class AIConfigurationStore: ObservableObject {
    @Published private(set) var configuration: AIConfiguration
    private let persistence: any AIConfigurationPersistence
    private let secretStore: any AISecretStore

    var profiles: [AIModelProfile] { configuration.profiles }

    init(persistence: any AIConfigurationPersistence, secretStore: any AISecretStore) throws {
        self.persistence = persistence
        self.secretStore = secretStore
        let data: Data?
        do { data = try persistence.read() } catch { throw AIError.configurationReadFailed }
        if let data {
            do { configuration = try JSONDecoder().decode(AIConfiguration.self, from: data) }
            catch { throw AIError.invalidConfiguration }
        } else { configuration = AIConfiguration() }
        try Self.validate(configuration)
    }

    convenience init(defaults: UserDefaults = .standard, secretStore: (any AISecretStore)? = nil) throws {
        try self.init(persistence: AIDefaultsConfigurationPersistence(defaults: defaults),
                      secretStore: secretStore ?? AIKeychainSecretStore())
    }

    func profile(for request: AIRequest) throws -> AIModelProfile {
        let id = request.profileID ?? (request.requiredCapability == .vision
            ? configuration.defaultVisionProfileID : configuration.defaultTextProfileID)
        guard let id else { throw AIError.missingDefault(request.requiredCapability) }
        guard let profile = profiles.first(where: { $0.id == id }) else { throw AIError.profileNotFound }
        return profile
    }

    func credential(for profile: AIModelProfile) throws -> String? {
        guard let reference = profile.secretReference else { return nil }
        let value: String?
        do { value = try secretStore.read(reference: reference) }
        catch { throw AIError.secretReadFailed }
        guard let value, !value.isEmpty else { throw AIError.missingCredential }
        return value
    }

    /// nil 保留密钥，空串移除密钥；保存新密钥时先建新引用，失败回滚非秘密配置。
    func save(_ profile: AIModelProfile, apiKey: String? = nil) throws {
        var candidate = profile
        let old = profiles.first { $0.id == profile.id }
        candidate.secretReference = old?.secretReference
        let newReference = apiKey.flatMap { $0.isEmpty ? nil : UUID() }
        if apiKey != nil { candidate.secretReference = newReference }
        var next = configuration
        if let index = next.profiles.firstIndex(where: { $0.id == candidate.id }) { next.profiles[index] = candidate }
        else { next.profiles.append(candidate) }
        try Self.validate(next)
        if let newReference, let apiKey {
            do { try secretStore.write(apiKey, reference: newReference) }
            catch { throw AIError.secretWriteFailed }
        }
        do { try persist(next) }
        catch {
            if let newReference {
                do { try secretStore.delete(reference: newReference) } catch { throw AIError.rollbackFailed }
            }
            throw AIError.configurationWriteFailed
        }
        if apiKey != nil, let oldReference = old?.secretReference {
            do { try secretStore.delete(reference: oldReference) }
            catch {
                do {
                    try persist(configuration)
                    if let newReference { try secretStore.delete(reference: newReference) }
                } catch { throw AIError.rollbackFailed }
                throw AIError.secretDeleteFailed
            }
        }
        configuration = next
    }

    func remove(profileID: UUID) throws {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { throw AIError.profileNotFound }
        var next = configuration
        next.profiles.removeAll { $0.id == profileID }
        if next.defaultTextProfileID == profileID { next.defaultTextProfileID = nil }
        if next.defaultVisionProfileID == profileID { next.defaultVisionProfileID = nil }
        // 先保存可回滚的配置；凭据删除失败则恢复原配置。
        try persist(next)
        if let reference = profile.secretReference {
            do { try secretStore.delete(reference: reference) }
            catch {
                do { try persist(configuration) } catch { throw AIError.rollbackFailed }
                throw AIError.secretDeleteFailed
            }
        }
        configuration = next
    }

    func setDefault(_ profileID: UUID?, for capability: AICapability) throws {
        if let profileID {
            guard let profile = profiles.first(where: { $0.id == profileID }) else { throw AIError.profileNotFound }
            guard profile.capabilities.contains(capability) else { throw AIError.capabilityMismatch }
        }
        var next = configuration
        if capability == .text { next.defaultTextProfileID = profileID }
        else { next.defaultVisionProfileID = profileID }
        try persist(next)
        configuration = next
    }

    private func persist(_ next: AIConfiguration) throws {
        do { try persistence.write(JSONEncoder().encode(next)) }
        catch { throw AIError.configurationWriteFailed }
    }

    private static func validate(_ configuration: AIConfiguration) throws {
        guard Set(configuration.profiles.map(\.id)).count == configuration.profiles.count else {
            throw AIError.invalidConfiguration
        }
        let references = configuration.profiles.compactMap(\.secretReference)
        guard Set(references).count == references.count else { throw AIError.invalidConfiguration }
        for profile in configuration.profiles {
            guard !profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !profile.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !profile.capabilities.isEmpty else { throw AIError.invalidConfiguration }
            _ = try AIEndpoint.url(for: profile)
        }
        for (id, capability) in [(configuration.defaultTextProfileID, AICapability.text),
                                 (configuration.defaultVisionProfileID, AICapability.vision)] {
            if let id {
                guard let profile = configuration.profiles.first(where: { $0.id == id }),
                      profile.capabilities.contains(capability) else { throw AIError.invalidConfiguration }
            }
        }
    }
}
