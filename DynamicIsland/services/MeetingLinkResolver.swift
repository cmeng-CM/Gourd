// Copyright (C) 2026 Gourd Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum MeetingProvider: String, CaseIterable, Sendable {
    case huawei, tencent, feishu
    case zoom, teams, meet, webex, facetime, gotomeeting, bluejeans, whereby, jitsi, discord
}

/// A labeled code is evidence for copying, never authority for constructing a URL.
struct MeetingCode: Equatable, Hashable, Sendable {
    let value: String
    let sourceText: String
}

/// Immutable validated evidence. Only the resolver may construct an opening plan.
struct MeetingJoinTarget: Equatable, Identifiable, Sendable {
    let provider: MeetingProvider?
    let sourceURL: URL?
    let nativeURL: URL?
    let httpsURL: URL?
    let urlIdentifier: String?
    let meetingCodes: [MeetingCode]
    let sourceText: String

    var id: String { sourceURL?.absoluteString ?? sourceText }
    var canOpen: Bool { nativeURL != nil || httpsURL != nil }

    fileprivate init(provider: MeetingProvider?, sourceURL: URL?, nativeURL: URL?, httpsURL: URL?,
                     urlIdentifier: String?, meetingCodes: [MeetingCode], sourceText: String) {
        self.provider = provider
        self.sourceURL = sourceURL
        self.nativeURL = nativeURL
        self.httpsURL = httpsURL
        self.urlIdentifier = urlIdentifier
        self.meetingCodes = meetingCodes
        self.sourceText = sourceText
    }
}

struct MeetingLinkResolver {
    static let maximumSourceCharacters = 20_000

    /// Returns every candidate; callers must ask for a choice when count > 1.
    func resolve(text: String) -> [MeetingJoinTarget] {
        guard text.count <= Self.maximumSourceCharacters else { return [] }
        let codes = meetingCodes(in: text)
        let regex = try? NSRegularExpression(pattern: #"[A-Za-z][A-Za-z0-9+.-]*://[^\s<>\"“”]+"#)
        let matches = regex?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
        var targets: [MeetingJoinTarget] = []
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let raw = String(text[range])
            let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "。，；、！!）)」】,;."))
            // Preserve a valid original URL byte-for-byte. Trim prose punctuation only if validation fails.
            let evidence = Self.validated(URL(string: raw)) != nil ? raw : trimmed
            guard let url = URL(string: evidence), let parsed = Self.validated(url) else { continue }
            guard !targets.contains(where: { $0.sourceURL == url }) else { continue }
            targets.append(MeetingJoinTarget(
                provider: parsed.provider, sourceURL: url,
                nativeURL: parsed.isNative ? url : nil, httpsURL: parsed.isNative ? nil : url,
                urlIdentifier: parsed.identifier, meetingCodes: codes, sourceText: evidence
            ))
        }
        // A fallback is associated only when both native and HTTPS sides are unique for the same identity.
        // Differing Huawei invitation/link codes stay independent evidence.
        var consumed: Set<String> = []
        var combined: [MeetingJoinTarget] = []
        for target in targets {
            guard !consumed.contains(target.id) else { continue }
            if target.nativeURL != nil, let identifier = target.urlIdentifier {
                let alternatives = targets.filter {
                    $0.provider == target.provider && $0.httpsURL != nil && $0.urlIdentifier == identifier
                }
                let nativeCandidates = targets.filter {
                    $0.provider == target.provider && $0.nativeURL != nil && $0.urlIdentifier == identifier
                }
                if nativeCandidates.count == 1, alternatives.count == 1, let alternative = alternatives.first {
                    consumed.insert(alternative.id)
                    combined.append(MeetingJoinTarget(
                        provider: target.provider, sourceURL: target.sourceURL, nativeURL: target.nativeURL,
                        httpsURL: alternative.httpsURL, urlIdentifier: identifier,
                        meetingCodes: codes, sourceText: target.sourceText
                    ))
                    continue
                }
            }
            // A HTTPS target may precede its native partner in the invitation.
            if target.httpsURL != nil, let identifier = target.urlIdentifier,
               targets.filter({ $0.nativeURL != nil && $0.provider == target.provider && $0.urlIdentifier == identifier }).count == 1,
               targets.filter({ $0.httpsURL != nil && $0.provider == target.provider && $0.urlIdentifier == identifier }).count == 1 {
                continue
            }
            combined.append(target)
        }
        if combined.isEmpty, !codes.isEmpty {
            combined.append(MeetingJoinTarget(provider: nil, sourceURL: nil, nativeURL: nil,
                                             httpsURL: nil, urlIdentifier: nil, meetingCodes: codes, sourceText: text))
        }
        return combined
    }

    func uniqueOpenTarget(text: String) -> MeetingJoinTarget? {
        let candidates = resolve(text: text).filter(\.canOpen)
        return candidates.count == 1 ? candidates.first : nil
    }

    /// 入会密码（仅用于华为深链的 `enter_code`）：标签限定 `入会密码|会议密码|password`，
    /// 返回冒号后 4–8 位字母数字；无标签、超长或纯中文一律 nil。
    func passcode(in text: String) -> String? {
        let pattern = #"(?i)(?:入会密码|会议密码|(?<![A-Za-z])password)\s*[:：]\s*([A-Za-z0-9]{4,8})(?![A-Za-z0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    static func provider(for url: URL) -> MeetingProvider? { validated(url)?.provider }

    private struct ValidatedURL {
        let provider: MeetingProvider
        let identifier: String?
        let isNative: Bool
    }

    private static func validated(_ url: URL?) -> ValidatedURL? {
        guard let url, let decoded = url.absoluteString.removingPercentEncoding,
              decoded.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil else { return nil }
        if parts.scheme?.lowercased() == "cloudlink" { return validatedHuaweiNative(parts) }
        if parts.scheme?.lowercased() == "wemeet" { return validatedWemeetNative(parts) }
        guard parts.scheme?.lowercased() == "https", let host = parts.host?.lowercased(),
              parts.port == nil || parts.port == 443 else { return nil }
        let path = parts.percentEncodedPath
        func matches(_ pattern: String, _ value: String = "") -> Bool {
            (value.isEmpty ? path : value).range(of: pattern, options: .regularExpression) != nil
        }
        func domain(_ expected: String, subdomains: Bool = false) -> Bool {
            host == expected || (subdomains && host.hasSuffix("." + expected))
        }
        func target(_ provider: MeetingProvider, _ identifier: String? = nil) -> ValidatedURL {
            ValidatedURL(provider: provider, identifier: identifier, isNative: false)
        }
        if (domain("meeting.huaweicloud.com") || domain("intl.meeting.huaweicloud.com")), path == "" || path == "/",
           let fragment = parts.fragment, matches(#"^/j/[0-9]{9,12}$"#, fragment) {
            return target(.huawei, fragment.components(separatedBy: "/").last)
        }
        if domain("meeting.tencent.com"), matches(#"^/dm/[A-Za-z0-9_-]+/?$"#) { return target(.tencent) }
        if domain("vc.feishu.cn"), matches(#"^/j/[0-9]+/?$"#) { return target(.feishu, url.lastPathComponent) }
        if domain("zoom.us", subdomains: true), matches(#"^/(j/[0-9]+|wc/[0-9]+/join|my/[A-Za-z0-9._-]+)/?$"#) { return target(.zoom) }
        if domain("teams.microsoft.com"), matches(#"^/l/meetup-join/[^/]+(/[^/]+)?/?$"#) { return target(.teams) }
        if domain("meet.google.com"), matches(#"^/[a-z]{3}-[a-z]{4}-[a-z]{3}/?$"#) { return target(.meet) }
        if domain("webex.com", subdomains: true), matches(#"^/(meet/[^/]+|[^/]+/j\.php|wbxmjs/joinservice/sites/[^/]+/meeting/download/[^/]+)$"#) { return target(.webex) }
        if domain("facetime.apple.com"), matches(#"^/join/?$"#), parts.queryItems?.contains(where: { $0.name == "v" && !($0.value ?? "").isEmpty }) == true { return target(.facetime) }
        if domain("gotomeeting.com", subdomains: true), matches(#"^/(join/)?[0-9]+/?$"#) { return target(.gotomeeting) }
        if domain("bluejeans.com", subdomains: true), matches(#"^/[0-9]+/?$"#) { return target(.bluejeans) }
        if domain("whereby.com"), matches(#"^/[A-Za-z0-9_-]+/?$"#) { return target(.whereby) }
        if domain("meet.jit.si"), matches(#"^/[A-Za-z0-9_-]+/?$"#) { return target(.jitsi) }
        if domain("discord.gg"), matches(#"^/[A-Za-z0-9_-]+/?$"#) { return target(.discord) }
        if domain("discord.com"), matches(#"^/(invite/[A-Za-z0-9_-]+|channels/[0-9]+/[0-9]+)/?$"#) { return target(.discord) }
        return nil
    }

    private static func validatedHuaweiNative(_ parts: URLComponents) -> ValidatedURL? {
        guard parts.host?.lowercased() == "welinksoftclient", parts.path == "/h5page", parts.port == nil,
              parts.fragment == nil, let items = parts.queryItems else { return nil }
        let allowed: Set<String> = ["page", "server_url", "port", "conf_id", "enter_code", "name", "open_mic", "open_camera"]
        let names = Set(items.map(\.name))
        guard names.count == items.count, names.isSubset(of: allowed),
              Set(["page", "conf_id", "name"]).isSubset(of: names),
              items.allSatisfy({ item in
                  guard let value = item.value else { return false }
                  return value.rangeOfCharacter(from: .controlCharacters) == nil
              }) else { return nil }
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value!) })
        guard ["joinConfByLink", "joinTmpConfByLink"].contains(values["page"] ?? ""),
              let code = values["conf_id"], code.range(of: #"^[0-9]{9,12}$"#, options: .regularExpression) != nil,
              !(values["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let server = values["server_url"],
           !["meeting.huaweicloud.com", "intl.meeting.huaweicloud.com"].contains(server.lowercased()) { return nil }
        if let rawPort = values["port"] {
            guard rawPort.range(of: #"^[0-9]{1,5}$"#, options: .regularExpression) != nil,
                  let port = Int(rawPort), (1...65535).contains(port) else { return nil }
        }
        for name in ["open_mic", "open_camera"] {
            if let value = values[name], !["true", "false"].contains(value) { return nil }
        }
        return ValidatedURL(provider: .huawei, identifier: code, isNative: true)
    }

    /// 腾讯客户端深链：`wemeet://page/inmeeting?meeting_code=<9–12 位>`。
    /// 参数白名单写死为一个键，任何多余参数、非官方 host/path 一律拒绝。
    private static func validatedWemeetNative(_ parts: URLComponents) -> ValidatedURL? {
        guard parts.host?.lowercased() == "page", parts.path == "/inmeeting",
              parts.port == nil, parts.fragment == nil,
              let items = parts.queryItems, items.count == 1, items[0].name == "meeting_code",
              let code = items[0].value,
              code.range(of: #"^[0-9]{9,12}$"#, options: .regularExpression) != nil else { return nil }
        return ValidatedURL(provider: .tencent, identifier: code, isNative: true)
    }

    private func meetingCodes(in text: String) -> [MeetingCode] {
        // Label is mandatory. Ordinary phone numbers and unlabeled digit strings do not qualify.
        let pattern = #"(?i)(?:#腾讯会议|腾讯会议|会议\s*(?:ID|号)|meeting\s*(?:ID|code))\s*[:：]\s*([0-9](?:[0-9 -]{3,18})[0-9])(?![0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var result: [MeetingCode] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text), let digits = Range(match.range(at: 1), in: text) else { continue }
            let value = text[digits].filter(\.isNumber)
            guard (6...12).contains(value.count) else { continue }
            let code = MeetingCode(value: value, sourceText: String(text[range]))
            if !result.contains(code) { result.append(code) }
        }
        return result
    }
}
