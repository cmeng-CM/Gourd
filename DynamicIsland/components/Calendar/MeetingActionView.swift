// Copyright (C) 2026 Gourd Contributors
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Defaults
import SwiftUI

private struct CalendarMeetingSessionKey: EnvironmentKey {
    static let defaultValue: CalendarPanelSession? = nil
}

extension EnvironmentValues {
    var calendarMeetingSession: CalendarPanelSession? {
        get { self[CalendarMeetingSessionKey.self] }
        set { self[CalendarMeetingSessionKey.self] = newValue }
    }
}

/// Original record evidence and optional start; visibility is independent of calendar navigation.
struct CalendarMeetingSource: Equatable {
    let recordID: String
    let textFields: [String]
    let structuredURLs: [URL]
    let start: Date?

    init(event: EventModel, url: URL? = nil) {
        recordID = event.id
        textFields = [event.title, event.location, event.notes].compactMap { $0 }
        structuredURLs = [url, event.url, event.conferenceURL].compactMap { $0 }
        start = event.start == .distantFuture ? nil : event.start
    }

    init(item: TodoBucketing.Item) {
        recordID = item.id
        textFields = [item.title]
        structuredURLs = []
        start = item.dueDate
    }

    var text: String { (textFields + structuredURLs.map(\.absoluteString)).joined(separator: "\n") }
    var targets: [MeetingJoinTarget] {
        CalendarMeetingEvidence.resolve(textFields: textFields, structuredURLs: structuredURLs)
    }
    var identity: [String] {
        [recordID, start.map { String($0.timeIntervalSince1970) } ?? ""] + textFields + structuredURLs.map(\.absoluteString)
    }
    var hasMeetingInformation: Bool {
        if !targets.isEmpty { return true }
        // Exclude known place/material nouns, while allowing invitation follow-up actions.
        let hints = #"(?i)(会议邀请(?=$|[\s\p{P}])|会议(?:主题|链接)\s*[:：]|邀请[^\n]{0,40}(?:参加|加入)[^\n]{0,15}会议(?!室|记录|材料|纪要|资料|文档)|(?:请|欢迎)[^\n]{0,20}(?:参加|加入)[^\n]{0,20}会议(?!室|记录|材料|纪要|资料|文档)|\b(?:meeting|conference)\s+invit(?:ation|e)\b|\b(?:join|invited)\b[^\n]{0,40}\b(?:meeting|conference)\b(?![\s-]+(?:rooms?|notes|minutes|materials|documents)\b))"#
        return textFields.contains { $0.range(of: hints, options: .regularExpression) != nil }
    }
}

/// 一次点击的结果状态（docs/47 §接口与数据形状）。
///
/// 只由图标自身表达（D-10）——面板与首页那一行高度固定，塞不下状态文字，原因留给 tooltip。
enum MeetingActionFeedback: Equatable { case idle, opening, opened, copied, failed }

/// 点击一下要执行的动作（D-01）：打开一个候选、复制会议号，或没有可信动作。
///
/// `open` 的 `MeetingJoinTarget` 既可能是带链接的候选，也可能是「只有会议号」的兜底候选
/// （`provider == nil`、`canOpen == false`）——后者的打开由 `MeetingJoinURLBuilder` 按号码拼深链。
/// `choose` 表示有**多个**可打开候选：不许猜，左键直接弹出菜单让用户选（审查 I-2）。
enum MeetingPrimaryAction: Equatable {
    case open(MeetingJoinTarget, MeetingProvider)
    case copyCode(String)
    case choose
    case none
}

/// 状态到 SF Symbol 的纯映射（D-10）。
enum MeetingActionGlyph {
    static func symbol(for feedback: MeetingActionFeedback) -> String {
        switch feedback {
        case .idle: return "video.fill"
        case .opening: return "arrow.triangle.2.circlepath"
        case .opened: return "checkmark"
        case .copied: return "checkmark"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

/// An injected, offline-testable action controller. 派发只发生在用户点一下之后，模型自身不扫描也不自动打开。
@MainActor
final class MeetingActionModel: ObservableObject {
    @Published private(set) var targets: [MeetingJoinTarget]
    @Published private(set) var isOpening = false
    @Published private(set) var feedback: MeetingActionFeedback = .idle
    private let source: String
    /// 面板/首页共用的会话：由 `MeetingActionContent` 的构造路径传入，供后续的视图级接线使用。
    private let session: CalendarPanelSession
    private let opening: MeetingOpening
    private let copyText: (String) -> Void
    private var task: Task<Void, Never>?
    private var revision = 0

    /// 成功状态自动回 idle 的停留时长（docs/47 §做法 3「瞬时状态」）。
    static let feedbackDwell: Duration = .seconds(1.5)

    convenience init(event: EventModel, url: URL? = nil, session: CalendarPanelSession,
                     opener: (any MeetingURLOpening)? = nil,
                     copyText: @escaping (String) -> Void = {
                         NSPasteboard.general.clearContents()
                         NSPasteboard.general.setString($0, forType: .string)
                     }) {
        self.init(source: CalendarMeetingSource(event: event, url: url), session: session,
                  opener: opener, copyText: copyText)
    }

    init(source: CalendarMeetingSource, session: CalendarPanelSession,
         opener: (any MeetingURLOpening)? = nil,
         copyText: @escaping (String) -> Void = {
             NSPasteboard.general.clearContents()
             NSPasteboard.general.setString($0, forType: .string)
         }) {
        self.session = session
        self.copyText = copyText
        opening = MeetingOpening(opener: opener)
        self.source = source.text
        targets = source.targets
    }

    var hasSource: Bool { !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isBusy: Bool { isOpening }

    /// 用户为「只有会议号」的邀请选过的客户端（D-09），存 `Defaults[.meetingCodeOpener]`。
    /// 只认有深链依据的两个平台；盘上若有其它值（或将来加了新平台）一律当作没记住。
    var rememberedProvider: MeetingProvider? {
        guard let provider = Defaults[.meetingCodeOpener].flatMap(MeetingProvider.init(rawValue:)),
              provider == .huawei || provider == .tencent else { return nil }
        return provider
    }

    /// 点击一下要执行的动作（D-01 / 审查 I-2）。
    ///
    /// 有**恰好一个**可打开候选就打开；**两个及以上**可打开候选不猜（`.choose`，左键弹菜单让用户选）；
    /// 没有可打开候选时，只有会议号就「记住过客户端按号码打开、否则复制号码」；都没有则不臆造动作。
    /// 未判定平台时不得凭猜选客户端（`MeetingJoinURLBuilder.url(provider:...)` 不复核号码归属），
    /// 这类候选退到纯号码分支。
    var primary: MeetingPrimaryAction {
        let openable = targets.filter(\.canOpen)
        if openable.count >= 2 { return .choose }
        if let target = openable.first,
           let provider = target.provider ?? rememberedProvider {
            return .open(target, provider)
        }
        guard let target = targets.first(where: { !$0.meetingCodes.isEmpty }),
              let number = Self.number(in: target) else { return .none }
        if let provider = rememberedProvider { return .open(target, provider) }
        return .copyCode(number)
    }

    /// 可打开候选（≥2 时主动作是 `.choose`，菜单逐条列出）。
    var openTargets: [MeetingJoinTarget] { targets.filter(\.canOpen) }

    /// 证据里第一个带标签的会议号（`nil` 表示这份邀请只有链接或只有邀请意图）。
    var code: MeetingCode? { targets.first(where: { !$0.meetingCodes.isEmpty })?.meetingCodes.first }

    /// 证据里第一个会议号的纯数字值（`MeetingCode.value` 已剥掉空格与连字符）。
    var codeValue: String? { code?.value }

    /// 证据能判定的平台（**不含**「记住的客户端」）：带链接的候选优先，其次是有会议号候选的平台。
    /// 用于 `.row` 的 provider 名与 tooltip 的「平台判不出来 → 右键更多」分支。
    var determinedProvider: MeetingProvider? {
        targets.first(where: \.canOpen)?.provider ?? targets.first(where: { !$0.meetingCodes.isEmpty })?.provider
    }

    /// 按号码打开时使用的入会显示名（D-08）：macOS 用户名，空或全空白（含 U+00A0）回落 `Gourd`。
    static func resolvedDisplayName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? MeetingJoinURLBuilder.fallbackDisplayName : trimmed
    }

    /// 打开的入口一：带链接的候选（保留）。
    func open(_ target: MeetingJoinTarget) {
        guard !isBusy, target.canOpen, targets.contains(target) else { return }
        performOpen(target: target, provider: target.provider ?? rememberedProvider)
    }

    /// 打开的入口二：只有会议号时按平台拼深链，并**记住**这个客户端（D-09）供下次主动作直接用。
    ///
    /// 先写 `Defaults` 再尝试打开是**有意**的（D-09：「点了就记住用户的选择」）——即使这次因为号码位数
    /// 不合法（builder 只认 9–12 位）而打不开、退回复制，用户的平台选择照样留下来（终审 M-6）。
    func openByNumber(provider: MeetingProvider) {
        guard !isBusy, let target = targets.first(where: { !$0.meetingCodes.isEmpty }) else { return }
        Defaults[.meetingCodeOpener] = provider.rawValue
        performOpen(target: target, provider: provider)
    }

    /// 一级动作（D-01）：点一下就是结果。
    ///
    /// `.choose`（≥2 可打开候选）不在这里执行——视图侧左键改成弹菜单（审查 I-2），此处保持 no-op。
    func performPrimary() {
        guard !isBusy else { return }
        switch primary {
        case let .open(target, provider):
            performOpen(target: target, provider: provider)
        case let .copyCode(number):
            revision += 1
            copy(number)
            settle(with: .copied)
        case .choose:
            break
        case .none:
            feedback = .failed
        }
    }

    /// 两个入口共用的执行器：带链接的候选走 `MeetingOpening.open`，只有会议号时按号码拼深链。
    private func performOpen(target: MeetingJoinTarget, provider: MeetingProvider?) {
        revision += 1
        let current = revision
        isOpening = true
        feedback = .opening
        task = Task { [weak self] in
            guard let self else { return }
            let result: MeetingOpenResult
            if target.canOpen {
                result = await self.opening.open(target)
            } else if let provider, let number = Self.number(in: target) {
                // 入会密码只喂华为深链（D-07）：腾讯分支没有可查依据可写。
                result = await self.opening.openByNumber(
                    provider: provider, number: number,
                    displayName: Self.resolvedDisplayName(NSFullUserName()),
                    passcode: provider == .huawei ? MeetingLinkResolver().passcode(in: self.source) : nil)
            } else {
                result = .unavailable
            }
            guard self.revision == current, !Task.isCancelled else { return }
            self.task = nil
            self.apply(result, to: target)
            self.isOpening = false
        }
    }

    /// 打开结果落到瞬时状态（D-10）。打不开就退回复制号码（docs/47 §做法 3），不谎称已加入。
    private func apply(_ result: MeetingOpenResult, to target: MeetingJoinTarget) {
        switch result {
        case .accepted, .fallback:
            settle(with: .opened)
        case .refused, .unavailable:
            guard let number = Self.number(in: target) else {
                feedback = .failed
                return
            }
            copy(number)
            settle(with: .copied)
        case .cancelled:
            feedback = .idle
        }
    }

    /// 置状态并在 1.5 秒后回到 `idle`（成功态是瞬时反馈，不是「已加入」的确认）。
    private func settle(with value: MeetingActionFeedback) {
        feedback = value
        guard value == .opened || value == .copied else { return }
        let current = revision
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.feedbackDwell)
            guard let self, !Task.isCancelled, self.revision == current else { return }
            self.feedback = .idle
        }
    }

    /// 号码取证据里第一个会议号的纯数字值（`MeetingCode.value` 已剥掉空格与连字符）。
    private static func number(in target: MeetingJoinTarget) -> String? {
        target.meetingCodes.first.map(\.value)
    }

    func copySource() { copy(source) }

    func copy(_ value: String) { guard !value.isEmpty else { return }; copyText(value) }
    func cancel() {
        revision += 1
        task?.cancel()
        task = nil
        isOpening = false
        feedback = .idle
    }

    deinit { task?.cancel() }
}

/// 会议入口的呈现形态（docs/47 §接口与数据形状）：首页是 22pt 图标（`.icon`），
/// 日历卡片与详情是一行两键（`.row`：provider + 号码 + 打开 / 复制）。
enum MeetingActionStyle { case icon, row }

/// 右键菜单的一项（docs/47 D-03）。纯数据，便于在无 UI 的用例里断言「最多 4 项、没有 AI 项」。
enum MeetingActionMenuEntry: Equatable {
    /// 复制会议号：载荷是**号码本身**（`MeetingCode.value`，与主动作复制的东西一致）。
    case copyCode(String)
    /// 用指定客户端按会议号打开（证据里本条能直接打开时，视图改走 `open(_:)`）。
    case openIn(MeetingProvider)
    /// 打开一个**具体候选**（≥2 可打开候选时逐条列出，不再折叠 —— 审查 I-2）。
    case openTarget(MeetingJoinTarget)
    /// 复制整段邀请原文。
    case copySource
}

/// 呈现层的纯计算（菜单项、标题、tooltip、平台显示名）：视图只负责画，判据都在这里。
enum MeetingActionPresentation {
    /// 图标边长（docs/47 §背景与目标）：上一版 NSButton 没给宽度、被 SwiftUI 拉伸到约 187pt。
    static let iconSide: CGFloat = 22

    /// 右键菜单的项（D-03 / 审查 I-2）：复制会议号 / 「打开」/ 复制邀请原文。
    /// **恰好一个**可打开候选时两条「打开」合并成能用的那条；**两个及以上**可打开候选时逐条列出
    /// （不折叠，让用户自己选）；只抽得出一条「打开」的其它情况沿用平台判定（判不出时列两家）。
    @MainActor
    static func menuEntries(for model: MeetingActionModel) -> [MeetingActionMenuEntry] {
        var entries: [MeetingActionMenuEntry] = []
        // 载荷是号码本身（设计图 ③ 的「复制会议号：939130533」），不是带标签的证据原文。
        if let code = model.code { entries.append(.copyCode(code.value)) }
        let openable = model.openTargets
        if openable.count >= 2 {
            entries.append(contentsOf: openable.map { .openTarget($0) })
        } else {
            switch model.determinedProvider {
            case .tencent: entries.append(.openIn(.tencent))
            case .huawei: entries.append(.openIn(.huawei))
            default: entries.append(contentsOf: [.openIn(.tencent), .openIn(.huawei)])
            }
        }
        entries.append(.copySource)
        return entries
    }

    /// 菜单项标题。`复制会议号：<号码>` 复用既有键 `calendar.meeting.copyCodeFormat`（不新增同义键）。
    static func title(for entry: MeetingActionMenuEntry) -> String {
        switch entry {
        case let .copyCode(number):
            return String(format: NSLocalizedString("calendar.meeting.copyCodeFormat", comment: ""), number)
        case let .openIn(provider):
            return openInTitle(provider)
        case let .openTarget(target):
            return openTargetTitle(target)
        case .copySource:
            return NSLocalizedString("calendar.meeting.copySource", comment: "")
        }
    }

    /// 执行一个菜单项：能直接打开本条证据时优先 `open(_:)`，否则按号码拼深链（D-06 / D-09）。
    @MainActor
    static func perform(_ entry: MeetingActionMenuEntry, on model: MeetingActionModel) {
        switch entry {
        case let .copyCode(number):
            model.copy(number)
        case let .openIn(provider):
            if let target = model.targets.first(where: { $0.canOpen && $0.provider == provider }) {
                model.open(target)
            } else {
                model.openByNumber(provider: provider)
            }
        case let .openTarget(target):
            model.open(target)
        case .copySource:
            model.copySource()
        }
    }

    /// tooltip 由主动作决定（docs/47 D-10）：打开 → 「打开腾讯会议」；
    /// 只有会议号（复制）→ 「复制会议号 <号> · 右键更多」；多个可打开候选（不猜）→ 「多个会议入口 · 右键选择」。
    ///
    /// `.copyCode` 只在**没有任何可打开候选、也没记住客户端**时产生（终审 M-1）：此时本条必然判不出平台，
    /// 所以统一走 `tooltip.more`，原「记住的客户端」分支是死代码，已删。
    static func tooltip(primary: MeetingPrimaryAction) -> String {
        switch primary {
        case let .open(_, provider):
            return String(format: NSLocalizedString("calendar.meeting.tooltip.open", comment: ""), providerName(provider))
        case let .copyCode(number):
            return String(format: NSLocalizedString("calendar.meeting.tooltip.more", comment: ""), number)
        case .choose:
            return NSLocalizedString("calendar.meeting.tooltip.multiple", comment: "")
        case .none:
            return NSLocalizedString("calendar.meeting.noEvidence", comment: "")
        }
    }

    @MainActor
    static func tooltip(for model: MeetingActionModel) -> String {
        tooltip(primary: model.primary)
    }

    /// `.row`「复制」键的 help（终审 M-2）：说清复制的是号码还是入口链接，不再借用主动作的「打开…」。
    @MainActor
    static func copyHelp(for model: MeetingActionModel) -> String {
        guard let value = model.codeValue ?? model.targets.first(where: \.canOpen)?.sourceURL?.absoluteString,
              !value.isEmpty else { return NSLocalizedString("calendar.meeting.row.copy", comment: "") }
        return String(format: NSLocalizedString("calendar.meeting.tooltip.copyValue", comment: ""), value)
    }

    /// 菜单里「在 … 中打开」两项的标题。
    static func openInTitle(_ provider: MeetingProvider) -> String {
        switch provider {
        case .huawei: return NSLocalizedString("calendar.meeting.openIn.huawei", comment: "")
        case .tencent: return NSLocalizedString("calendar.meeting.openIn.tencent", comment: "")
        default: return String(format: NSLocalizedString("calendar.meeting.tooltip.open", comment: ""), providerName(provider))
        }
    }

    /// 逐候选列出时的标题（审查 I-2）：判定出平台就用「在 <平台> 中打开」，否则退回主机名（可打开候选一定有链接）。
    static func openTargetTitle(_ target: MeetingJoinTarget) -> String {
        if let provider = target.provider { return openInTitle(provider) }
        let host = target.sourceURL?.host ?? target.meetingCodes.first?.value ?? ""
        return String(format: NSLocalizedString("calendar.meeting.tooltip.open", comment: ""), host)
    }

    /// 平台显示名：两家能按号打开的平台用新增的中文键（设计图 ④ 的 provider 名），
    /// 其余沿用既有 `ConferenceProvider` 的品牌名口径（专有名词，两种语言一致）。
    static func providerName(_ provider: MeetingProvider?) -> String {
        switch provider {
        case .huawei: return NSLocalizedString("calendar.meeting.provider.huawei", comment: "")
        case .tencent: return NSLocalizedString("calendar.meeting.provider.tencent", comment: "")
        case .feishu: return "Feishu"
        case .zoom: return "Zoom"
        case .teams: return "Teams"
        case .meet: return "Meet"
        case .webex: return "Webex"
        case .facetime: return "FaceTime"
        case .gotomeeting: return "GoToMeeting"
        case .bluejeans: return "BlueJeans"
        case .whereby: return "Whereby"
        case .jitsi: return "Jitsi"
        case .discord: return "Discord"
        case .none: return ""
        }
    }

    /// `.row` 左侧的 provider 名：**与本条证据同源**（`primary` / tooltip 都用本条链接的平台），
    /// 只有本条判不出平台时才回落到记住的客户端（D-09）。
    ///
    /// 终审 I-1：`meetingCodeOpener` 是全局记忆，若在这里先取 `rememberedProvider`，一条带华为链接的邀请
    /// 会被贴成「腾讯会议」的行标，而 tooltip 与点开走的却是华为 —— 三者必须同源。
    @MainActor
    static func rowProviderName(for model: MeetingActionModel) -> String? {
        let name = providerName(model.determinedProvider ?? model.rememberedProvider)
        return name.isEmpty ? nil : name
    }

    /// `.row` 中间的「号码或链接」：优先会议号（设计图 ④ 显示 `939130533`），没有号码时退回入口链接。
    @MainActor
    static func rowValue(for model: MeetingActionModel) -> String? {
        model.codeValue ?? model.targets.first(where: \.canOpen)?.sourceURL?.absoluteString
    }

    /// `.row` 的状态位：`.idle` 不占位，其余复用 `MeetingActionGlyph.symbol(for:)`（D-10 ——
    /// 「转圈 / 对勾」在面板侧也要看得见，不能只有首页图标有反馈）。
    static func rowStatusSymbol(for feedback: MeetingActionFeedback) -> String? {
        feedback == .idle ? nil : MeetingActionGlyph.symbol(for: feedback)
    }

    /// `.row` 右端画哪些键（审查 I-1 / I-2）：键名必须与行为一致 ——
    /// 判不出平台时主动作就是复制，不画「打开」；连入口都没有（`.none`）时一个键都不画；
    /// **多个**可打开候选（`.choose`，不猜）时只留一个「选择入口」键，点了弹出菜单让用户选。
    @MainActor
    static func rowKeys(for model: MeetingActionModel) -> [MeetingActionRowKey] {
        switch model.primary {
        case .open: return [.open, .copy]
        case .copyCode: return [.copy]
        case .choose: return [.choose]
        case .none: return []
        }
    }
}

/// `.row` 右端的小键（设计图 ④ / 审查 I-2）。
enum MeetingActionRowKey: Equatable { case open, copy, choose }

/// 会议入口：证据层认出会议就显示，点一下就是结果（docs/47 D-01 / D-02 —— 已无「开始前 15 分钟」闸门）。
struct MeetingActionView: View {
    let source: CalendarMeetingSource
    let session: CalendarPanelSession
    let style: MeetingActionStyle

    init(event: EventModel, url: URL? = nil, session: CalendarPanelSession, style: MeetingActionStyle = .icon) {
        source = CalendarMeetingSource(event: event, url: url)
        self.session = session
        self.style = style
    }
    init(source: CalendarMeetingSource, session: CalendarPanelSession, style: MeetingActionStyle = .icon) {
        self.source = source
        self.session = session
        self.style = style
    }
    var body: some View {
        if source.hasMeetingInformation {
            MeetingActionContent(source: source, session: session, style: style)
                .id(source.identity)
        }
    }
}

private struct MeetingActionContent: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @StateObject private var model: MeetingActionModel
    private let style: MeetingActionStyle

    init(source: CalendarMeetingSource, session: CalendarPanelSession, style: MeetingActionStyle) {
        _model = StateObject(wrappedValue: MeetingActionModel(source: source, session: session))
        self.style = style
    }

    var body: some View {
        Group {
            switch style {
            case .icon:
                // 22×22 固定尺寸：不给宽度的 NSButton 会被 SwiftUI 拉伸（docs/47 §背景与目标）。
                MeetingActionIcon(model: model, vm: vm)
                    .frame(width: MeetingActionPresentation.iconSide, height: MeetingActionPresentation.iconSide)
                    .fixedSize()
            case .row:
                MeetingActionRow(model: model)
            }
        }
        .accessibilityIdentifier("calendar-meeting-actions")
        .onDisappear { model.cancel() }
    }
}

/// 会议**文字信息**（平台名 + 会议号）：面板列表行把这两项当信息留着（docs/49 D-19「平台名 + 会议号
/// 作为文字信息保留」），动作本身不再用两枚文字键——那是行右端那枚 22×22 图标按钮的事。
struct MeetingActionInfoText: View {
    let event: EventModel
    let session: CalendarPanelSession
    @StateObject private var model: MeetingActionModel

    init(event: EventModel, session: CalendarPanelSession) {
        self.event = event
        self.session = session
        _model = StateObject(wrappedValue: MeetingActionModel(event: event, session: session))
    }

    var body: some View {
        let provider = MeetingActionPresentation.rowProviderName(for: model)
        let value = MeetingActionPresentation.rowValue(for: model)
        if provider != nil || value != nil {
            HStack(spacing: 4) {
                if let provider {
                    Text(provider).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7)).lineLimit(1).fixedSize()
                }
                if let value {
                    Text(value).font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85)).lineLimit(1).truncationMode(.middle)
                }
            }
        }
    }
}

/// `.row`：设计图 ④ 的面板形态 —— 一行 `<provider 名> <号码或链接>` + 右端「打开 / 复制」两个小键。
///
/// 退化态（审查 I-1）：判不出平台时主动作就是复制，此时**不画「打开」**（键名与行为必须一致）；
/// 连入口都没有（`.none`）时两个键都不画，只留一句说明。
private struct MeetingActionRow: View {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @ObservedObject var model: MeetingActionModel

    var body: some View {
        HStack(spacing: 6) {
            if model.primary == .none {
                Text(LocalizedStringKey("calendar.meeting.noEvidence"))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55)).lineLimit(2)
                Spacer(minLength: 0)
            } else {
                if let provider = MeetingActionPresentation.rowProviderName(for: model) {
                    Text(provider)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75)).lineLimit(1).fixedSize()
                }
                if let value = MeetingActionPresentation.rowValue(for: model) {
                    Text(value)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9)).lineLimit(1).truncationMode(.middle)
                }
                // 状态位只在有反馈时占位，复用图标口径（D-10 / 审查 I-4）：面板里点了也看得见转圈/对勾。
                if let status = MeetingActionPresentation.rowStatusSymbol(for: model.feedback) {
                    Image(systemName: status)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85)).fixedSize()
                }
                Spacer(minLength: 4)
                let keys = MeetingActionPresentation.rowKeys(for: model)
                if keys.contains(.open) {
                    key("calendar.meeting.row.open", help: MeetingActionPresentation.tooltip(for: model)) {
                        model.performPrimary()
                    }
                }
                if keys.contains(.copy) {
                    // 每个键各自的 help（终审 M-2）：复制键不许再显示主动作的「打开…」。
                    key("calendar.meeting.row.copy", help: MeetingActionPresentation.copyHelp(for: model)) {
                        if let value = MeetingActionPresentation.rowValue(for: model) { model.copy(value) }
                    }
                }
                if keys.contains(.choose) {
                    key("calendar.meeting.row.choose", help: MeetingActionPresentation.tooltip(for: model)) { presentMenu() }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// ≥2 可打开候选（不猜）：面板里那一行同样弹出同一个「会议操作」菜单让用户选（审查 I-2）。
    private func presentMenu() {
        let presenter = MeetingActionMenuPresenter()
        presenter.configureSuppression(
            setProtection: { [weak vm] in vm?.setAutoCloseSuppression($0, token: $1) },
            recheckHover: { [weak vm] in vm?.shouldRecheckHover.toggle() })
        presenter.present(for: model, anchoredTo: nil)
    }

    private func key(_ titleKey: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(LocalizedStringKey(titleKey))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(model.isBusy)
        .help(help)
    }
}

/// 「会议操作」菜单的构建、弹出与自动收回抑制：首页图标与面板 `.row` 的「选择入口」键共用同一套
/// （审查 I-2 —— 多个可打开候选时两处都要能让用户选，不再各写一份）。
@MainActor
final class MeetingActionMenuPresenter: NSObject, NSMenuDelegate {
    private var interaction: CalendarTextInteraction?
    private var menu: NSMenu?
    private var actions: [() -> Void] = []

    /// 接上自动收回抑制（与文本选区同一套 token 机制）。
    func configureSuppression(setProtection: @escaping (Bool, UUID) -> Void,
                              recheckHover: @escaping () -> Void) {
        interaction = CalendarTextInteraction(setProtection: setProtection, recheckHover: recheckHover)
    }

    /// 在 `view` 的左上角弹出菜单；`view` 为 nil 时按当前鼠标位置弹出（`.row` 里没有可锚定的 NSView）。
    func present(for model: MeetingActionModel, anchoredTo view: NSView?) {
        depart()
        let menu = NSMenu()
        menu.autoenablesItems = false
        self.menu = menu
        menu.delegate = self
        actions.removeAll()
        for entry in MeetingActionPresentation.menuEntries(for: model) {
            // 设计图 ③：两条「打开」在上、两条「复制」在下，中间一条分隔线（旧实现也有）。
            if entry == .copySource { menu.addItem(.separator()) }
            add(MeetingActionPresentation.title(for: entry), to: menu) {
                MeetingActionPresentation.perform(entry, on: model)
            }
        }
        if let view {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.maxY), in: view)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    private func add(_ title: String, to menu: NSMenu, action: @escaping () -> Void) {
        let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
        item.target = self
        item.tag = actions.count
        actions.append(action)
        menu.addItem(item)
    }
    @objc private func choose(_ item: NSMenuItem) { if actions.indices.contains(item.tag) { actions[item.tag]() } }
    func menuWillOpen(_ menu: NSMenu) { interaction?.menuWillOpen(menu) }
    func menuDidClose(_ menu: NSMenu) { interaction?.menuDidClose(menu) }
    func depart() {
        interaction?.depart()
        clearDelegate(menu)
        menu?.cancelTracking()
        menu = nil
    }
    private func clearDelegate(_ menu: NSMenu?) {
        menu?.delegate = nil
        for item in menu?.items ?? [] { clearDelegate(item.submenu) }
    }
    func stop() {
        depart()
        interaction?.stop()
        interaction = nil
        actions.removeAll()
    }
}

/// 22×22 图标按钮（docs/47 §背景与目标）：AppKit 直接画并给出固定固有尺寸，绝不被 SwiftUI 拉伸；
/// 左键执行主动作（D-01；`.choose` 时改弹菜单），右键弹菜单（D-03）。control-click 与右键同义。
@MainActor
final class MeetingActionIconButton: NSView {
    /// 圆角 6、`rgba(255,255,255,.14)` 底（设计图 ②）。
    static let cornerRadius: CGFloat = 6
    static let fillAlpha: CGFloat = 0.14
    static let symbolPointSize: CGFloat = 11

    var symbolName: String = MeetingActionGlyph.symbol(for: .idle)
    var leftClick: (@MainActor () -> Void)?
    var rightClick: (@MainActor (NSView) -> Void)?

    override var intrinsicContentSize: NSSize {
        NSSize(width: MeetingActionPresentation.iconSide, height: MeetingActionPresentation.iconSide)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(Self.fillAlpha).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius).fill()
        let configuration = NSImage.SymbolConfiguration(pointSize: Self.symbolPointSize, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white.withAlphaComponent(0.9)]))
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let size = symbol.size
        symbol.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                               width: size.width, height: size.height),
                    from: .zero, operation: .sourceOver, fraction: 1)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightClick?(self) } else { leftClick?() }
    }
    override func rightMouseDown(with event: NSEvent) { rightClick?(self) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    /// 自绘 `NSView` 默认**不是**无障碍元素：必须显式声明，否则读屏看不到这个入口（审查 I-3）。
    func configureAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(NSLocalizedString("calendar.meeting.actions", comment: ""))
    }
}

/// Real NSMenu lifecycle, no popover pin. 保留 `CalendarTextInteraction` 的自动收回抑制与
/// `NSApplication.didResignActive` 观察者（docs/47 §做法 3、本任务 ⑤）。
private struct MeetingActionIcon: NSViewRepresentable {
    @ObservedObject var model: MeetingActionModel
    var vm: DynamicIslandViewModel

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> MeetingActionIconButton {
        let button = MeetingActionIconButton()
        button.configureAccessibility()
        context.coordinator.connect(button)
        return button
    }
    func updateNSView(_ button: MeetingActionIconButton, context: Context) {
        context.coordinator.parent = self
        button.symbolName = MeetingActionGlyph.symbol(for: model.feedback)
        button.toolTip = MeetingActionPresentation.tooltip(for: model)
        button.needsDisplay = true
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MeetingActionIconButton, context: Context) -> CGSize? {
        CGSize(width: MeetingActionPresentation.iconSide, height: MeetingActionPresentation.iconSide)
    }
    static func dismantleNSView(_ button: MeetingActionIconButton, coordinator: Coordinator) { coordinator.stop() }

    @MainActor final class Coordinator: NSObject {
        var parent: MeetingActionIcon
        private let presenter = MeetingActionMenuPresenter()
        private var observers: [NSObjectProtocol] = []
        init(_ parent: MeetingActionIcon) { self.parent = parent }
        func connect(_ button: MeetingActionIconButton) {
            let vm = parent.vm
            let model = parent.model
            presenter.configureSuppression(
                setProtection: { [weak vm] in vm?.setAutoCloseSuppression($0, token: $1) },
                recheckHover: { [weak vm] in vm?.shouldRecheckHover.toggle() })
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                                     object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.presenter.depart() }
            })
            button.leftClick = { [weak self] in
                guard let self else { return }
                // ≥2 可打开候选（不猜）：左键直接弹出菜单让用户选（审查 I-2）。
                if model.primary == .choose {
                    self.presenter.present(for: model, anchoredTo: button)
                } else {
                    model.performPrimary()
                }
            }
            button.rightClick = { [weak self] view in self?.presenter.present(for: model, anchoredTo: view) }
        }
        func stop() {
            presenter.stop()
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
        }
    }
}

/// Editable text sits in its own clip view: the box follows the text up to `maximumLines` and then
/// holds that height, so a pasted paragraph scrolls inside the box instead of stretching the form
/// (docs/49 D-04). The box draws its own outline + fill, so an empty field still reads as a place
/// to type. The page keeps a single scroll axis around it.
struct CalendarGrowingTextEditor: NSViewRepresentable {
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @Binding var text: String
    var label: String
    /// 空框时在框内画的占位文字（本地化键；复用既有键，不新增）。nil = 不画。
    var placeholder: String?
    var onFocus: (Bool) -> Void
    /// 可见高度上限（行数）：原文区与备注都收在这一档，再多就框内滚动。
    var maximumLines: Int = CalendarEditableTextView.defaultMaximumLines

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor.white.withAlphaComponent(CalendarEditableTextView.fillAlpha)
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = CalendarEditableTextView.cornerRadius
        scroll.layer?.cornerCurve = .continuous
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = NSColor.white
            .withAlphaComponent(CalendarEditableTextView.borderAlpha).cgColor
        scroll.layer?.masksToBounds = true

        let view = CalendarEditableTextView(frame: .zero, textContainer: nil)
        view.delegate = context.coordinator
        view.onFocus = onFocus
        // 底色与描边由外层框负责：文档视图比框高，自己画底会把描边一起滚走。
        view.drawsBackground = false
        // 文档视图只在这一处放开纵向自增长（SwiftUI 管的是**框**的高度，见 sizeThatFits）：
        // 内容超过 3 行时它比框高，多出来的部分在框内滚动（D-04）。
        // 高度下限走 `minSize`（布局参数），**不**在任何测量回调里对活视图改 frame。
        view.isVerticallyResizable = true
        view.autoresizingMask = [.width]
        view.minSize = NSSize(width: 0, height: view.cappedHeight(lines: maximumLines))
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.interaction = CalendarTextInteraction(
            setProtection: { [weak vm] in vm?.setAutoCloseSuppression($0, token: $1) },
            recheckHover: { [weak vm] in vm?.shouldRecheckHover.toggle() })
        view.setAccessibilityLabel(NSLocalizedString(label, comment: ""))
        view.placeholder = placeholder.map { NSLocalizedString($0, comment: "") }
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? CalendarEditableTextView else { return }
        view.onFocus = onFocus
        view.minSize = NSSize(width: 0, height: view.cappedHeight(lines: maximumLines))
        if view.string != text {
            view.string = text
            view.needsDisplay = true
        }
        // 删到空时占位那一笔要补上（AppKit 只失效被编辑的那块矩形）。
        if text.isEmpty { view.needsDisplay = true }
        view.setAccessibilityLabel(NSLocalizedString(label, comment: ""))
        view.placeholder = placeholder.map { NSLocalizedString($0, comment: "") }
    }
    /// **纯读**：框高恒为 `maximumLines` 行的定高；文档视图的伸缩交给 `minSize` + `isVerticallyResizable`，
    /// 测量回调里不对活视图改 frame（本文件的同类约定见 `CalendarSelectableText` 的注释）。
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let view = nsView.documentView as? CalendarEditableTextView else { return nil }
        // 宽度兜底取**clip 宽**（不是滚动视图宽：常显滚动条那一档会宽出 15pt）。
        let width = proposal.width ?? (nsView.contentSize.width > 0 ? nsView.contentSize.width : 200)
        return CGSize(width: width, height: view.cappedHeight(lines: maximumLines))
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        (scroll.documentView as? CalendarEditableTextView)?.stop()
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CalendarGrowingTextEditor
        init(_ parent: CalendarGrowingTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}

@MainActor
final class CalendarEditableTextView: NSTextView, NSMenuDelegate {
    /// 大文本框的视觉与高度口径（docs/49 D-04）：圆角 6 + 白 6% 底 + 白 18% 描边（由外层框画），
    /// 可见高度 = `defaultMaximumLines` 行（见 `cappedHeight`）。
    static let cornerRadius: CGFloat = 6
    static let fillAlpha: CGFloat = 0.06
    static let borderAlpha: CGFloat = 0.18
    static let defaultMaximumLines = 3
    static let defaultFontSize: CGFloat = CalendarPanelTypography.bigEditorPointSize

    var onFocus: (Bool) -> Void = { _ in }
    var interaction: CalendarTextInteraction?
    /// 空框时画的占位文字（D-04：新建时也看得出这里能写字）。
    var placeholder: String? { didSet { if placeholder != oldValue { needsDisplay = true } } }
    private var ownedMenus: [NSMenu] = []
    private var resignObserver: NSObjectProtocol?

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        if let textContainer {
            super.init(frame: frame, textContainer: textContainer)
        } else {
            // Match the read-only bridge: nil needs an owned, complete TextKit chain.
            let storage = NSTextStorage()
            let manager = NSLayoutManager()
            let container = NSTextContainer(containerSize: NSSize(width: frame.width, height: .greatestFiniteMagnitude))
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            super.init(frame: frame, textContainer: container)
        }
        isRichText = false
        isEditable = true
        isSelectable = true
        isHorizontallyResizable = false
        isVerticallyResizable = false
        wantsLayer = true
        layer?.masksToBounds = true
        drawsBackground = true
        backgroundColor = NSColor.white.withAlphaComponent(Self.fillAlpha)
        textColor = .white
        insertionPointColor = .white
        allowsUndo = true
        font = .systemFont(ofSize: Self.defaultFontSize)
        textContainerInset = NSSize(width: 4, height: 4)
        self.textContainer?.lineFragmentPadding = 0
        self.textContainer?.widthTracksTextView = true
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.depart() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    /// 可见高度**就是** `defaultMaximumLines` 行（含上下内缩）：不是下限而是定高——内容更多时框内滚动。
    /// 行高取布局管理器的默认行高（≈16pt @13），`boundingRectForFont` 会把字体的升部余量算进去（≈17pt），
    /// 三行就多出 3pt —— 那 3pt 正是编辑档可视区容不下的部分。
    func cappedHeight(lines: Int = CalendarEditableTextView.defaultMaximumLines) -> CGFloat {
        let font = self.font ?? .systemFont(ofSize: Self.defaultFontSize)
        let measured = layoutManager?.defaultLineHeight(for: font) ?? 0
        let lineHeight = measured > 0 ? measured : ceil(font.boundingRectForFont.height)
        return ceil(lineHeight) * CGFloat(lines) + 2 * textContainerInset.height
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        CalendarTextMeasurement.synchronize(self)
    }
    override func layout() {
        super.layout()
        CalendarTextMeasurement.synchronize(self)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        bounds.clip()
        super.draw(dirtyRect.intersection(bounds))
        drawPlaceholderIfEmpty()
        NSGraphicsContext.restoreGraphicsState()
    }
    /// 占位文字用与正文同一个 font 与内缩画，位置天然与输入起点重合。
    private func drawPlaceholderIfEmpty() {
        guard string.isEmpty, let placeholder, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: Self.defaultFontSize),
            .foregroundColor: NSColor.white.withAlphaComponent(0.35)
        ]
        (placeholder as NSString).draw(at: NSPoint(x: textContainerInset.width, y: textContainerInset.height),
                                      withAttributes: attributes)
    }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus(true) }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocus(false) }
        return accepted
    }
    override func mouseDown(with event: NSEvent) {
        let owner = interaction
        owner?.mouseDown()
        defer { owner?.trackingReturned() }
        super.mouseDown(with: event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }
        menu.delegate = self
        ownedMenus.append(menu)
        return menu
    }
    func menuWillOpen(_ menu: NSMenu) { interaction?.menuWillOpen(menu) }
    func menuDidClose(_ menu: NSMenu) {
        interaction?.menuDidClose(menu)
        menu.delegate = nil
        ownedMenus.removeAll { $0 === menu }
    }
    private func depart() {
        onFocus(false)
        interaction?.depart()
        for menu in ownedMenus { menu.delegate = nil; menu.cancelTracking() }
        ownedMenus.removeAll()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { depart() }
    }
    func stop() {
        depart()
        interaction?.stop()
        interaction = nil
        delegate = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }
    deinit {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        let owner = interaction
        MainActor.assumeIsolated { owner?.stop() }
    }
}
