// Copyright (C) 2026 Gourd Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// 按会议号构造可入会深链（docs/47 D-06）。
///
/// 只覆盖两处有可查依据的写法：华为 `cloudlink://welinksoftclient/h5page`（官方文档的参数契约）
/// 与腾讯 `wemeet://page/inmeeting`（客户端 scheme）。白名单写死 —— 号码必须 9–12 位，参数只写
/// `page` / `conf_id` / `name` / `enter_code`，不写 `server_url` / `port` / `open_mic` / `open_camera`。
/// 构造结果一律回交 `MeetingLinkResolver.provider(for:)` 复核平台，不过校验即 nil：猜不出、也兜不住的一律不猜。
enum MeetingJoinURLBuilder {
    /// 显示名为空或全空白时的回落值（docs/47 D-08）。
    static let fallbackDisplayName = "Gourd"

    /// 只接受 9–12 位纯数字；先去空格与连字符（`940 948 346` → `940948346`），其余字符一律 nil。
    /// 全角数字等非 ASCII 数字不算数字，因为下游校验器只认 `[0-9]`。
    static func digits(_ raw: String) -> String? {
        let compact = raw.filter { !$0.isWhitespace && $0 != "-" }
        guard (9...12).contains(compact.count), compact.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return compact
    }

    /// 华为云会议深链：`cloudlink://welinksoftclient/h5page?page=joinConfByLink&conf_id=<id>&name=<显示名>[&enter_code=<密码>]`。
    /// `displayName` 为空或全空白时用 `Gourd`；密码为空则整条 `enter_code` 不写。
    static func huawei(confID: String, displayName: String, passcode: String?) -> URL? {
        guard let code = digits(confID), let name = encodedName(displayName) else { return nil }
        var query = "page=joinConfByLink&conf_id=\(code)&name=\(name)"
        if let passcode, !passcode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let enterCode = percentEncoded(passcode) else { return nil }
            query += "&enter_code=\(enterCode)"
        }
        guard let url = URL(string: "cloudlink://welinksoftclient/h5page?" + query),
              MeetingLinkResolver.provider(for: url) == .huawei else { return nil }
        return url
    }

    /// 腾讯会议客户端深链：`wemeet://page/inmeeting?meeting_code=<code>`。
    /// 密码没有依据可写（docs/47「不解析腾讯的密码参数」），入参只为止住调用方猜测而保留。
    static func tencent(meetingCode: String, passcode _: String?) -> URL? {
        guard let code = digits(meetingCode),
              let url = URL(string: "wemeet://page/inmeeting?meeting_code=\(code)"),
              MeetingLinkResolver.provider(for: url) == .tencent else { return nil }
        return url
    }

    /// 按平台分派；只有华为与腾讯有两种客户端深链，其余平台一律 nil（交给复制号码）。
    ///
    /// `provider` 是**调用方的断言**，builder 不复核号码属于哪个平台：华为的 `conf_id` 与腾讯的
    /// `meeting_code` 共用同一条 9–12 位数字空间，仅凭号码在这里原理上分不出来。未判定平台时
    /// 不得凭猜选一个 —— 猜错等于把用户送进另一个客户端。
    static func url(provider: MeetingProvider, number: String,
                    displayName: String, passcode: String?) -> URL? {
        switch provider {
        case .huawei: return huawei(confID: number, displayName: displayName, passcode: passcode)
        case .tencent: return tencent(meetingCode: number, passcode: passcode)
        default: return nil
        }
    }

    /// 只保留 RFC 3986 unreserved（`A-Za-z0-9-._~`），其余按 UTF-8 百分号编码。
    /// 逐字写出 ASCII unreserved —— **不能**用 `.alphanumerics`：它含 `蔡`、`９` 等非 ASCII 字母数字，
    /// 只因 `addingPercentEncoding` 对非 ASCII 一律编码才碰巧等价，注释与实现必须同构。
    /// 这是最保守的编码集合：显示名里的 `&` / `=` / `#` / `+` 不可能再去改写参数结构。
    private static let percentEncodingAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~-")

    private static func percentEncoded(_ raw: String) -> String? {
        raw.addingPercentEncoding(withAllowedCharacters: percentEncodingAllowed)
    }

    private static func encodedName(_ displayName: String) -> String? {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return percentEncoded(trimmed.isEmpty ? fallbackDisplayName : trimmed)
    }
}
