//
//  ModuleManifest.swift
//  Gourd 模块内核 · manifest 类型层（P1 批次 / T1）
//
//  字段与取值逐字沿用 docs/06-module-protocol.md §2；本批实现子集见
//  docs/13-runtime-kernel.md §接口与数据形状（未列出的字段即「明确不做」）。
//

import AppKit
import Foundation

// MARK: - LocalizedText（06 §2.3）

/// 06 §2.3 的两种形态：
/// - `{ "key": "module.<shortID>.<field>" }` —— 内置模块用，`key` 存在且为**唯一成员**；
/// - `{ "<BCP-47 语言>": "<文本>", ... }` —— 插件用（本批只解析，不参与渲染）。
///
/// 解码是**宽容**的（`key` 与 locale 表都收下来），合法性判定统一放在
/// `ModuleManifest.validate()` 里报 `ModuleManifestError.badLocalizedText`——
/// 这样「混用」在解码路径与直接构造值对象两条路徑上都会被拒。
public struct LocalizedText: Codable, Sendable, Equatable {
    /// 内置模块的本地化 key（形态：`module.<shortID>.<field>`）。
    public let key: String?
    /// 插件用的 locale → 文本表。
    public let table: [String: String]?

    public init(key: String? = nil, table: [String: String]? = nil) {
        self.key = key
        self.table = table
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        var key: String?
        var table: [String: String] = [:]
        for codingKey in container.allKeys {
            if codingKey.stringValue == "key" {
                key = try container.decode(String.self, forKey: codingKey)
            } else {
                table[codingKey.stringValue] = try container.decode(String.self, forKey: codingKey)
            }
        }
        self.key = key
        self.table = table.isEmpty ? nil : table
    }

    /// 按形态原样写回：key 形态写 `{"key": ...}`，locale 形态把 locale 平铺成顶层键。
    /// locale 键排序后写入，保证「manifest 可导出为 JSON」时输出稳定（06 §1）。
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        if let table = table {
            for locale in table.keys.sorted() {
                try container.encode(table[locale], forKey: AnyCodingKey(stringValue: locale))
            }
        }
        if let key = key {
            try container.encode(key, forKey: AnyCodingKey(stringValue: "key"))
        }
    }
}

// MARK: - IconSpec / Placement（06 §2.4 / §6.2）

/// 06 §2.4 的图标声明。本批只使用 `symbol` 形态（内置模块必须为 `symbol`）；
/// `image` / `appIcon` 的专属字段（`path` / `size` / `bundleIdentifier`）不在本批字段集内，
/// 解码时被忽略。
public struct IconSpec: Codable, Sendable, Equatable {
    public let type: String
    public let name: String?
}

/// 06 §6.2：`{slot, order}`；仅当 `surfaces` 含 `compact` 时有意义。
public struct Placement: Codable, Sendable, Equatable {
    public let slot: Slot?
    public let order: Int?
}

// MARK: - ConfigValue（06 §5.3 的默认值形态）

/// 06 §5 受限子集中的**默认值**。
///
/// **`default` 在 manifest JSON 里是裸值**（对齐 06 §5.3：`"ring"` / `true` / `1` / `["a","b"]`），
/// 所以这里必须自定义 `Codable`：合成的关联值编码会写成 `{"string":"ring"}`，
/// 那样既不是 06 的形状、也解不回来。
public enum ConfigValue: Codable, Sendable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case strings([String])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // 顺序有意义：`true`/`1` 在 JSONDecoder 里互不兼容（Bool 只认 true/false），
        // 整数先于浮点，保证 `1` 解成 `.int(1)` 而不是 `.double(1.0)`。
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String].self) {
            self = .strings(value)
        } else {
            throw DecodingError.typeMismatch(
                ConfigValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "配置默认值不是 boolean/integer/number/string/list 中的任何一种"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .strings(let value): try container.encode(value)
        }
    }
}

/// 06 §5 的一个配置节点。本批只支持 `boolean` / `integer` / `number` / `string` /
/// `enum` / `list` 六种 `type`，不做 `$ref` / `oneOf` / 条件分支与 `required`；
/// `default` 是 `ConfigHandle` 的唯一默认值来源（本批）。
///
/// 与 06 §5.3 的差异（已记在 docs/13-runtime-kernel.md「已知限制」13）：
/// `values` 是 `[String]?`（06 为 `[{value,title,icon?}]`）、`itemType` 未收在
/// 06 的 `string|integer|appPicker` 内、无 `required`、不做未知关键字校验。
public struct ConfigNode: Codable, Sendable, Equatable {
    public let type: String
    public let title: LocalizedText?
    public let `default`: ConfigValue?
    /// `enum` 的可选值。
    public let values: [String]?
    /// `list` 的元素类型。
    public let itemType: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case title
        case `default`
        case values
        case itemType
    }
}

/// 06 §5.1 的顶层：`{"type": "object", "properties": {...}}`。
public struct ConfigSchema: Codable, Sendable, Equatable {
    public let type: String
    public let properties: [String: ConfigNode]
}

// MARK: - ModuleManifestError（06 §10.2 的本批子集）

/// manifest 校验错误。每个分支都对应 06 §10.2 的一个错误码：
///
/// | 本类型 | 06 错误码 |
/// |---|---|
/// | `badVersion` | `E_MANIFEST_VERSION` |
/// | `badID` | `E_INVALID_ID` |
/// | `badAPIVersion` | `E_API_MAJOR` / `E_API_MINOR`（本批合并为一个分支） |
/// | `emptySurfaces` | `E_INVALID_SURFACE` |
/// | `badIcon` | `E_INVALID_ICON` |
/// | `badLocalizedText` | `E_INVALID_LOCALIZED_TEXT` |
/// | `unexpectedEntry` | `E_UNEXPECTED_FIELD` |
/// | `unsupportedKind` | `E_KIND_MISMATCH` 的本批形态（只支持 `builtin`） |
/// | `unknownPermission` | `E_UNKNOWN_PERMISSION` / `E_INVALID_PERMISSION` |
///
/// 本批**没有** `E_MISSING_FIELD` / `E_TYPE` / `E_UNKNOWN_FIELD` / `E_INVALID_SCHEMA`
/// 的分支：缺字段与类型错由 `JSONDecoder` 以 `DecodingError` 抛出，schema 校验属 P1-3。
public enum ModuleManifestError: Error, Equatable {
    case badVersion(Int)
    case badID(String)
    case badAPIVersion(String)
    case emptySurfaces
    case badIcon(String)
    case badLocalizedText(String)
    case unexpectedEntry
    case unsupportedKind(String)
    case unknownPermission(String)
}

// MARK: - 权限白名单常量（06 §7.1 全表）

/// 06 §7.1 的能力白名单，逐行抄成常量。本批**只做集合校验，不做授权**
/// （授权流程、`PermissionHandle`、隐私面判定见 docs/13「明确不做」）。
public enum ModulePermissionCatalog {
    /// 无参数的 capability 族（06 §7.1 表格的前 13 行）。
    public static let exactCapabilities: Set<String> = [
        "notifications",
        "timers",
        "storage",
        "clipboard:read",
        "clipboard:write",
        "files:picker",
        "files:shelf",
        "media:control",
        "media:read",
        "system:metrics",
        "power:control",
        "shortcuts:run",
        "ai:complete",
    ]

    /// 带参数的 capability（06 §7.1 表格后两行，字面照抄，含占位符）。`:` 后为参数，
    /// **不支持通配符**。
    public static let parameterizedCapabilities: [String] = [
        "network:<host>",
        "events:subscribe:<eventName>",
    ]

    /// 全表（15 行，与 06 §7.1 逐字一致，供设置页展示/审计用）。
    public static var allCapabilities: Set<String> {
        exactCapabilities.union(parameterizedCapabilities)
    }

    /// 命中白名单 = 无参数族精确相等，或参数形态且**参数非空**。
    /// 裸 `network` 因此不命中（06 §7 硬性规则 1：裸 `network` 不合法，必须 `network:<host>`）。
    ///
    /// 本批只做集合校验：`<host>` / `<eventName>` 的**形态**（小写域名、不含 IP/通配符/端口、
    /// 事件名是否在内核事件表内）属授权与事件裁剪，见 docs/13「明确不做」。
    public static func isKnown(_ capability: String) -> Bool {
        if exactCapabilities.contains(capability) { return true }
        return parameterizedCapabilities.contains { documented in
            guard let prefix = parameterPrefix(of: documented) else { return false }
            return capability.hasPrefix(prefix) && capability.count > prefix.count
        }
    }

    /// `"network:<host>"` → `"network:"`；`"events:subscribe:<eventName>"` → `"events:subscribe:"`。
    private static func parameterPrefix(of documented: String) -> String? {
        guard let placeholder = documented.firstIndex(of: "<") else { return nil }
        let head = documented[..<placeholder]
        return head.isEmpty ? nil : String(head)
    }
}

// MARK: - ModuleManifest（06 §2.2 字段全表的本批子集）

/// 静态、可序列化、可在不认识实现的情况下读的模块元数据（06 §1 的 ①）。
public struct ModuleManifest: Codable, Sendable, Equatable {
    public let manifestVersion: Int
    public let id: String
    public let name: LocalizedText
    public let summary: LocalizedText?
    public let icon: IconSpec
    public let version: String
    public let apiVersion: String
    /// 本批只允许 `builtin`（06 §2.2 / docs/13「明确不做」：插件运行时属 P4）。
    public let kind: String
    public let surfaces: [Surface]
    public let defaultPlacement: Placement?
    public let defaultEnabled: Bool?
    /// 06 §2.2：可省略，缺省 `[]`（兜底见下方扩展的 `init(from:)`）。
    public let permissions: [String]
    /// 缺省 = `{object, properties:{}}`（06 §2.2）；本批缺省为 nil，读取侧等价于空 schema。
    public let config: ConfigSchema?

    /// 显式声明（JSON 键名即字段名），供扩展里的自定义解码使用。
    public enum CodingKeys: String, CodingKey {
        case manifestVersion
        case id
        case name
        case summary
        case icon
        case version
        case apiVersion
        case kind
        case surfaces
        case defaultPlacement
        case defaultEnabled
        case permissions
        case config
    }
}

public extension ModuleManifest {
    /// 06 §2.2：`permissions` 可省略、缺省 `[]`；其余必填字段缺失即 `DecodingError`
    /// （本批的 `ModuleManifestError` 没有 `E_MISSING_FIELD` 分支，故不换算成自有错误）。
    ///
    /// 自定义解码放在**扩展**里是刻意的：写在类型体内会抑制 memberwise 初始化器，
    /// 而内置模块正是用字面量构造 manifest 的（T4 的 `ProgressModule.manifest`）。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.manifestVersion = try container.decode(Int.self, forKey: .manifestVersion)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(LocalizedText.self, forKey: .name)
        self.summary = try container.decodeIfPresent(LocalizedText.self, forKey: .summary)
        self.icon = try container.decode(IconSpec.self, forKey: .icon)
        self.version = try container.decode(String.self, forKey: .version)
        self.apiVersion = try container.decode(String.self, forKey: .apiVersion)
        self.kind = try container.decode(String.self, forKey: .kind)
        self.surfaces = try container.decode([Surface].self, forKey: .surfaces)
        self.defaultPlacement = try container.decodeIfPresent(Placement.self, forKey: .defaultPlacement)
        self.defaultEnabled = try container.decodeIfPresent(Bool.self, forKey: .defaultEnabled)
        self.permissions = try container.decodeIfPresent([String].self, forKey: .permissions) ?? []
        self.config = try container.decodeIfPresent(ConfigSchema.self, forKey: .config)
    }

    /// 内置模块 id 的保留前缀（D-11 / 06 §2.2）：内置必须用，插件必须不用。
    static let builtinIDPrefix = "com.cmeng.gourd."
    /// 本批唯一允许的 `kind`（06 §2.2）。
    static let builtinKind = "builtin"
    /// 本批唯一支持的 `manifestVersion`（06 §2.2）。
    static let supportedManifestVersion = 1

    /// JSONDecoder + 校验（06 §10.1 的短路语义）。
    ///
    /// 额外一步：`kind == builtin` 时顶层**不得**出现 `entry`（06 §2.2 的 `E_UNEXPECTED_FIELD`）。
    /// `entry` 不在本批字段集内，故用一次顶层键探测来给出 `unexpectedEntry`，
    /// 而不是把插件字段混进 `ModuleManifest`。`kind != builtin` 时该键不参与判定——
    /// 那时更根本的问题是 `kind` 不受支持，`validate()` 会报 `unsupportedKind`。
    static func decode(from data: Data) throws -> ModuleManifest {
        let manifest = try JSONDecoder().decode(ModuleManifest.self, from: data)
        if manifest.kind == builtinKind, hasTopLevelKey("entry", in: data) {
            throw ModuleManifestError.unexpectedEntry
        }
        try manifest.validate()
        return manifest
    }

    /// 校验短路：命中第一个错就抛，不做收集。本批的步序是**自定的**，**未逐字对齐** 06 §10.1——
    /// 06 的顺序是 id → kind → surfaces → permissions → icon → apiVersion，本批实际是
    /// manifestVersion → id → 保留前缀 → kind → icon → name/summary → surfaces → apiVersion → permissions
    /// （icon 提到 surfaces/permissions 之前，且 manifestVersion 排在最前；`entry` 探测在 `decode(from:)` 里、更早）。
    /// 该差异只影响**多个错并存时报出哪一个**，不影响任一单项的判定结果。
    /// 本批跳过的 06 §10.1 步骤：4（未知字段）、11（路径安全，无 `path` 字段）、13（`minHostVersion`）、
    /// 14（全局 id 唯一，属 `ModuleRegistry`）。
    func validate() throws {
        // 1. manifestVersion == 1
        guard manifestVersion == Self.supportedManifestVersion else {
            throw ModuleManifestError.badVersion(manifestVersion)
        }

        // 2. id：反域名 `^[a-z0-9]+(\.[a-z0-9-]+)+$`，长度 3–128
        guard id.range(of: #"^[a-z0-9]+(\.[a-z0-9-]+)+$"#, options: .regularExpression) != nil,
              (3...128).contains(id.count)
        else {
            throw ModuleManifestError.badID(id)
        }

        // 3. 保留前缀：内置必须带 `com.cmeng.gourd.`，非内置必须不带
        let usesBuiltinPrefix = id.hasPrefix(Self.builtinIDPrefix)
        switch (kind == Self.builtinKind, usesBuiltinPrefix) {
        case (true, false), (false, true):
            throw ModuleManifestError.badID(id)
        default:
            break
        }

        // 4. kind 本批只支持 builtin
        guard kind == Self.builtinKind else {
            throw ModuleManifestError.unsupportedKind(kind)
        }

        // 5. icon：内置必须 symbol（06 §2.2），且 name 必须能被系统符号表解析（06 §2.4 实测一次）
        guard icon.type == "symbol" else {
            throw ModuleManifestError.badIcon(icon.type)
        }
        guard let symbolName = icon.name, !symbolName.isEmpty else {
            throw ModuleManifestError.badIcon("symbol 缺少 name")
        }
        guard NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil else {
            throw ModuleManifestError.badIcon(symbolName)
        }

        // 6. name / summary：长度上限（06 §2.2：name ≤ 40、summary ≤ 120）
        try Self.validateLocalizedText(name, field: "name", limit: 40)
        if let summary = summary {
            try Self.validateLocalizedText(summary, field: "summary", limit: 120)
        }

        // 7. surfaces 非空（元素合法性由 `Surface` 的解码保证）
        guard !surfaces.isEmpty else {
            throw ModuleManifestError.emptySurfaces
        }

        // 8. apiVersion：`^\d+\.\d+$` 且落在宿主支持区间内（06 §8.1）
        guard Self.isSupportedAPIVersion(apiVersion) else {
            throw ModuleManifestError.badAPIVersion(apiVersion)
        }

        // 9. permissions 全部命中白名单（06 §7.1）
        for permission in permissions where !ModulePermissionCatalog.isKnown(permission) {
            throw ModuleManifestError.unknownPermission(permission)
        }
    }

    /// `"com.cmeng.gourd.progress"` → `"progress"`。
    /// 非内置 id 无 shortID 概念，原样返回（本批的本地化 key 形态只对内置生效）。
    var shortID: String {
        guard id.hasPrefix(Self.builtinIDPrefix) else { return id }
        return String(id.dropFirst(Self.builtinIDPrefix.count))
    }

    // MARK: - 内部判定

    /// `^\d+\.\d+$`（不含 patch，06 §8.1）+ 宿主支持区间 `1.0 ... 1.<currentAPIMinor>`。
    static func isSupportedAPIVersion(_ raw: String) -> Bool {
        guard raw.range(of: #"^\d+\.\d+$"#, options: .regularExpression) != nil else { return false }
        let parts = raw.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let major = Int(parts[0]), let minor = Int(parts[1]) else { return false }
        return major == HostInfo.currentAPIMajor && minor <= HostInfo.currentAPIMinor
    }

    /// 06 §2.3 的形态与长度规则：
    /// 二者必须**择一**（同时给 → 混用；都不给 → 空文本），locale 形态必须含 `en`。
    /// key 形态的长度上限由 key 自身（`module.<shortID>.<field>`）约束，06 未另给数值。
    static func validateLocalizedText(_ text: LocalizedText, field: String, limit: Int) throws {
        switch (text.key, text.table) {
        case let (key?, table?):
            throw ModuleManifestError.badLocalizedText("\(field) 混用 key(\(key)) 与 locale 表(\(table.keys.sorted()))")
        case (nil, nil):
            throw ModuleManifestError.badLocalizedText("\(field) 既无 key 也无 locale 表")
        case (.some(let key), nil):
            guard !key.isEmpty else { throw ModuleManifestError.badLocalizedText("\(field) 的 key 为空") }
        case (nil, .some(let table)):
            guard table["en"] != nil else {
                throw ModuleManifestError.badLocalizedText("\(field) 的 locale 表缺少 en（现有 \(table.keys.sorted())）")
            }
            for locale in table.keys.sorted() {
                let value = table[locale] ?? ""
                guard value.count <= limit else {
                    throw ModuleManifestError.badLocalizedText("\(field).\(locale) 超长（\(value.count) > \(limit)）")
                }
            }
        }
    }

    /// 顶层键探测（只用于 `entry`）。JSON 本身不可解析时返回 false，
    /// 由 `JSONDecoder` 报告结构错误。
    static func hasTopLevelKey(_ key: String, in data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            return false
        }
        return dictionary[key] != nil
    }
}

// MARK: - 动态 CodingKey

/// `LocalizedText` 的 locale 键是任意 BCP-47 字符串，无法用静态 `CodingKeys` 表达。
private struct AnyCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        nil
    }
}
