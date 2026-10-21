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
///
/// 服务名分两代：v1 是 2026-10-14 起的旧条目，v2 由 `AIMigratingSecretStore` 在首次读取时
/// 以当前签名的 App 重新创建。旧条目若由另一个签名 / 路径的构建创建，legacy Keychain 的 ACL
/// 不认当前 App，每次读取都会弹一次系统授权框；新建的 v2 条目把当前 App 记为可信应用，
/// 之后读取不再弹框（2026-10-19 用户反馈「每次生成都弹钥匙串」）。
@MainActor
final class AIKeychainSecretStore: AISecretStore {
    static let currentService = "com.cmeng.gourd.ai.credentials.v2"
    static let legacyService = "com.cmeng.gourd.ai.credentials.v1"
    private let service: String

    init(service: String = AIKeychainSecretStore.currentService) {
        self.service = service
    }

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

/// 凭据读取的**迁移 + 会话缓存**层（详见 `AIKeychainSecretStore` 的类型注释）。
///
/// 顺序：
/// 1. 内存缓存命中 → 直接返回（同一次启动内不再碰 Keychain，生成多次也只读一次）；
/// 2. v2 条目命中 → 缓存并返回；
/// 3. v1 旧条目命中 → 以当前 App 新建一份 v2，缓存并返回（旧条目保留，回滚旧版本仍可读）；
/// 4. 都没有 → nil（调用方按「未配置凭据」处理，不弹框）。
///
/// `write` 只写 v2；`delete` 两代一起删（配置删除必须把秘密一起清掉）。
/// 迁移失败（例如用户在系统弹框里点了取消）原样抛出，不把失败伪装成「没有密钥」。
/// 运行时凭据文件存储（2026-10-21 用户选择不再使用 Keychain）。
///
/// 位置：`~/Library/Application Support/Gourd/AICredentials/<UUID>.key`；
/// 目录 0700、文件 0600。只在本机运行时存在，永不进入仓库、日志或安装包。
/// 旧 Keychain 条目不再读取；升级后第一次使用需要在设置里重新输入一次密钥。
@MainActor
final class AIFileSecretStore: AISecretStore {
    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Gourd", isDirectory: true)
            .appendingPathComponent("AICredentials", isDirectory: true)
    }

    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
    }

    private func fileURL(_ reference: UUID) -> URL {
        directory.appendingPathComponent("\(reference.uuidString).key", isDirectory: false)
    }

    func read(reference: UUID) throws -> String? {
        let url = fileURL(reference)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                guard let value = String(data: data, encoding: .utf8) else {
                    throw AIError.secretReadFailed
                }
                return value
            } catch let error as AIError {
                throw error
            } catch {
                throw AIError.secretReadFailed
            }
        }
        return nil
    }

    func write(_ secret: String, reference: UUID) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let url = fileURL(reference)
            try Data(secret.utf8).write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw AIError.secretWriteFailed
        }
    }

    func delete(reference: UUID) throws {
        let url = fileURL(reference)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw AIError.secretDeleteFailed
        }
    }
}

/// 旧 v1 → v2 Keychain 迁移装饰器。2026-10-21 起生产默认改用 `AIFileSecretStore`；
/// 本类保留用于历史迁移回归，不再接入生产初始化路径。
@MainActor
final class AIMigratingSecretStore: AISecretStore {
    private let current: any AISecretStore
    private let legacy: any AISecretStore
    private var cache: [UUID: String] = [:]

    init(current: any AISecretStore, legacy: any AISecretStore) {
        self.current = current
        self.legacy = legacy
    }

    func read(reference: UUID) throws -> String? {
        if let cached = cache[reference] { return cached }
        if let value = try current.read(reference: reference) {
            cache[reference] = value
            return value
        }
        guard let value = try legacy.read(reference: reference) else { return nil }
        try current.write(value, reference: reference)
        cache[reference] = value
        return value
    }

    func write(_ secret: String, reference: UUID) throws {
        try current.write(secret, reference: reference)
        cache[reference] = secret
    }

    func delete(reference: UUID) throws {
        var firstError: Error?
        do { try current.delete(reference: reference) } catch { firstError = error }
        do { try legacy.delete(reference: reference) } catch { firstError = firstError ?? error }
        cache[reference] = nil
        if let firstError { throw firstError }
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
        // 2026-10-21：生产凭据改存本机 Application Support 文件，不再走 Keychain 授权读取。
        try self.init(persistence: AIDefaultsConfigurationPersistence(defaults: defaults),
                      secretStore: secretStore ?? AIFileSecretStore())
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
