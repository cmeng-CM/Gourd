// Copyright (C) 2026 Gourd Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

@MainActor
protocol MeetingURLOpening {
    /// True only means that the system accepted URL dispatch, never that a participant joined.
    func open(_ url: URL) async -> Bool
}

@MainActor
struct SystemMeetingURLOpener: MeetingURLOpening {
    func open(_ url: URL) async -> Bool {
        guard !Task.isCancelled else { return false }
        return NSWorkspace.shared.open(url)
    }
}

enum MeetingOpenResult: Equatable, Sendable {
    case accepted(URL)
    case fallback(URL)
    case refused([URL])
    case unavailable
    case cancelled
}

@MainActor
struct MeetingOpening {
    private let opener: any MeetingURLOpening

    init(opener: (any MeetingURLOpening)? = nil) {
        self.opener = opener ?? SystemMeetingURLOpener()
    }

    func open(_ target: MeetingJoinTarget) async -> MeetingOpenResult {
        guard !Task.isCancelled else { return .cancelled }
        var attempted: [URL] = []
        if let native = target.nativeURL {
            attempted.append(native)
            let accepted = await opener.open(native)
            // An accepted dispatch cannot be undone. Cancellation prevents any later fallback.
            if accepted { return .accepted(native) }
            guard !Task.isCancelled else { return .cancelled }
        }
        if let https = target.httpsURL {
            guard !Task.isCancelled else { return .cancelled }
            attempted.append(https)
            let accepted = await opener.open(https)
            if accepted { return target.nativeURL == nil ? .accepted(https) : .fallback(https) }
            guard !Task.isCancelled else { return .cancelled }
        }
        return attempted.isEmpty ? .unavailable : .refused(attempted)
    }

    /// 只有会议号时的入口：先按平台拼深链，拼不出来（位数不符、平台没有文档依据）即 `.unavailable`。
    /// 这里没有可退的 HTTPS 兜底 —— 号码本身不是地址，打不开的结果交回调用方去复制。
    func openByNumber(provider: MeetingProvider, number: String,
                      displayName: String, passcode: String?) async -> MeetingOpenResult {
        guard !Task.isCancelled else { return .cancelled }
        guard let url = MeetingJoinURLBuilder.url(provider: provider, number: number,
                                                 displayName: displayName, passcode: passcode) else {
            return .unavailable
        }
        guard !Task.isCancelled else { return .cancelled }
        let accepted = await opener.open(url)
        guard !Task.isCancelled else { return .cancelled }
        return accepted ? .accepted(url) : .refused([url])
    }
}
