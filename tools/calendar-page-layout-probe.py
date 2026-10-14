#!/usr/bin/env python3
"""Hidden production calendar page fixture; requires explicit, testable Debug product.
Copyright (C) 2026 Gourd Contributors; SPDX-License-Identifier: GPL-3.0-or-later.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

SOURCES = [
    'DynamicIsland/components/Calendar/CalendarSelectableText.swift',
    'DynamicIsland/components/Calendar/CalendarPanelPages.swift',
    'DynamicIsland/components/Calendar/MeetingActionView.swift',
    'DynamicIsland/components/Calendar/CalendarEventCards.swift',
    'DynamicIsland/components/Calendar/DynamicIslandCalendar.swift',
]
STUBS = r'''
import AppKit
import Combine
import SwiftUI
import Defaults
@testable import Gourd
@MainActor final class DynamicIslandViewModel: ObservableObject {
    enum NotchState { case closed, open }
    @Published var notchState: NotchState = .open
    var shouldRecheckHover = false
    final class Coordinator { enum ViewKind { case home }; var currentView: ViewKind = .home }
    let coordinator = Coordinator()
    func setAutoCloseSuppression(_ active: Bool, token: UUID) {}
    func close() {}
}
@MainActor final class CalendarEditorLifecycle: ObservableObject {
    let ownerID = UUID()
    init(session: CalendarPanelSession) {}
    func connect(to vm: DynamicIslandViewModel) {}
    func setEditorFocus(_ value: Bool) {}
    func setDatePopoverPresented(_ value: Bool) {}
    func clearLocalInput() {}
    func setScrolling(_ value: Bool) {}
    func setOwnedMenuCount(_ value: Int) {}
    func stop() {}
}
struct CalendarEditorWindowReader: View {
    let lifecycle: CalendarEditorLifecycle
    var body: some View { Color.clear }
}
enum ProbeClock { static let now = ISO8601DateFormatter().date(from: "2026-10-14T15:30:00+08:00")! }
enum ProbePreferences {
    static let suite = UserDefaults(suiteName: "org.gourd.calendar-layout.preferences")!
    static let hideAllDayEvents = Defaults.Key<Bool>("hideAllDayEvents", default: false, suite: suite)
    static let hideCompletedReminders = Defaults.Key<Bool>("hideCompletedReminders", default: false, suite: suite)
    static let showFullEventTitles = Defaults.Key<Bool>("showFullEventTitles", default: false, suite: suite)
    static let autoScrollToNextEvent = Defaults.Key<Bool>("autoScrollToNextEvent", default: false, suite: suite)
}
// A background GeometryReader observes actual card bounds without participating in layout.
struct ProbeCardBounds: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
@MainActor enum ProbeGeometry { static var cards: [String: CGRect] = [:] }
struct ProbeCardReader: View {
    let id: String
    var body: some View {
        GeometryReader { proxy in Color.clear.preference(key: ProbeCardBounds.self, value: [id: proxy.frame(in: .named("fixture-page"))]) }
    }
}
private extension Date {
    var startOfMonth: Date { Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self))! }
}
'''
MAIN = r'''
@MainActor func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { descendants($0) }
}
@MainActor func pump(_ host: NSView) async {
    for _ in 0..<5 { host.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(30)) }
}
@main struct ProbeMain {
    @MainActor static func main() async throws {
        let out = URL(fileURLWithPath: CommandLine.arguments[1])
        let full = CommandLine.arguments[2] == "true"
        let gray = CommandLine.arguments[3] == "gray"
        var checks: [[String: Any]] = []
        var cases: [[String: Any]] = []
        func check(_ ok: Bool, _ name: String) { checks.append(["name": name, "passed": ok]) }
        let old = ProbePreferences.suite.persistentDomain(forName: "org.gourd.calendar-layout.preferences")
        defer {
            if let old { ProbePreferences.suite.setPersistentDomain(old, forName: "org.gourd.calendar-layout.preferences") }
            else { ProbePreferences.suite.removePersistentDomain(forName: "org.gourd.calendar-layout.preferences") }
        }
        Defaults[ProbePreferences.showFullEventTitles] = full
        Defaults[ProbePreferences.hideAllDayEvents] = false
        Defaults[ProbePreferences.hideCompletedReminders] = false
        Defaults[ProbePreferences.autoScrollToNextEvent] = false
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSTimeZone.default = TimeZone(identifier: "Asia/Shanghai")!
        let vm = DynamicIslandViewModel()
        let date = ProbeClock.now
        let calendar = CalendarModel(accountName: "Fixture", id: "fixture-calendar", title: "测试工作日历", color: .systemBlue, isSubscribed: false, isReminder: false)
        let title = "培训时间：10月14日 周三\n15:30–16:30 技术方案评审\n会议号：123456789 入会\n密码：123456 完整标题末行"
        let notes = (1...44).map { "\($0). 日程备注完整滚动验收。" }.joined(separator: "\n") + "\nTAIL45 备注末尾可见标记"
        func event(_ id: String, _ second: Bool) -> EventModel {
            EventModel(id: id, start: date.addingTimeInterval(second ? 3600 : 0), end: date.addingTimeInterval(second ? 7200 : 3600),
                       title: second ? "第二相邻日程卡\n架构与工程实践讨论\nNEXTCARD_END 完整第三行" : title,
                       location: "宽度测量夹具地址", notes: notes, url: nil, isAllDay: false,
                       type: .event(.unknown), calendar: calendar, participants: [], timeZone: TimeZone(identifier: "Asia/Shanghai"),
                       hasRecurrenceRules: false, priority: nil,
                       conferenceURL: URL(string: "https://meeting.huaweicloud.com/#/j/123456789"))
        }
        let records = [event("fixture-first", false), event("fixture-next", true)]
        let backend = CalendarInteractionMemoryService(records: records, calendars: [calendar])
        let manager = CalendarManager(service: backend, now: { date }, startMonitoring: false)
        await manager.updateCurrentDate(date)
        let session = CalendarPanelSession(selectedDate: date, now: { date },
            saveEvent: { try await backend.saveEvent(input: $0, eventID: $1) },
            createReminder: { try await backend.createReminderRecord(input: $0) },
            deleteEvent: { try await backend.deleteEvent(id: $0) },
            completeReminder: { try await backend.completeReminder(id: $0, completed: $1) },
            event: { backend.event(withID: $0) })
        let root = AnyView(StandaloneCalendarView(session: session, manager: manager)
            .padding(.horizontal, 16).background(gray ? Color(white: 0.35) : .black)
            .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
            .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
            .environment(\.colorScheme, .dark).environmentObject(vm)
            .coordinateSpace(name: "fixture-page")
            .onPreferenceChange(ProbeCardBounds.self) { ProbeGeometry.cards = $0 })
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 360), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 360)
        check(!window.isVisible, "window hidden before first layout")
        func textViews() -> [NSTextView] { descendants(host).compactMap { $0 as? NSTextView }.filter { $0 is CalendarReadOnlyTextView || $0 is CalendarEditableTextView } }
        func rectangle(_ view: NSView) -> CGRect { view.convert(view.bounds, to: host) }
        func rectJSON(_ rect: CGRect) -> [Double] { [rect.minX, rect.minY, rect.width, rect.height] }
        func proposals(_ name: String) {
            let views = textViews()
            check(!views.isEmpty, name + " has actual native text")
            for view in views {
                let originalSelection = view.selectedRanges
                view.setSelectedRange(NSRange(location: 0, length: min(2, (view.string as NSString).length)))
                let frame = view.frame, range = view.selectedRanges, text = view.string
                let width = view.textContainer?.containerSize.width ?? -1
                for proposed: CGFloat in [0, 200, 1, 374, 80, 0] {
                    if let v = view as? CalendarReadOnlyTextView { _ = v.measuredSize(width: proposed) }
                    if let v = view as? CalendarEditableTextView { _ = v.measuredSize(width: proposed) }
                }
                check(rectJSON(view.frame) == rectJSON(frame) && view.selectedRanges == range && view.string == text && view.textContainer?.containerSize.width == width,
                      name + " injected min/ideal/normal preserve live " + String(text.prefix(12)))
                view.selectedRanges = originalSelection
            }
        }
        func capture(_ name: String, tail: Bool = false, required: [(text: String, token: String)] = []) throws {
            check(!window.isVisible, name + " window stays hidden")
            let native = textViews()
            var geometry: [[String: Any]] = []
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = out.appendingPathComponent(name + ".png")
            try rep.representation(using: .png, properties: [:])!.write(to: png)
            for view in native {
                guard let container = view.textContainer, let lm = view.layoutManager else {
                    check(false, name + " complete TextKit"); continue
                }
                lm.ensureLayout(for: container)
                let frame = rectangle(view)
                let used = lm.usedRect(for: container)
                let effective = max(1, view.bounds.width - 2 * view.textContainerInset.width)
                check(abs(container.containerSize.width - effective) <= 0.5, name + " allocated content width " + String(view.string.prefix(12)))
                check(!view.isVerticallyResizable && used.height <= view.bounds.height + 0.5, name + " text stays in native slot " + String(view.string.prefix(12)))
                geometry.append(["text": view.string, "frame": rectJSON(frame), "containerWidth": container.containerSize.width,
                                 "inset": view.textContainerInset.width, "used": rectJSON(used), "maximumLines": container.maximumNumberOfLines])
            }
            if case .detail = session.route {
                let values = Set(native.map(\.string))
                check(values.contains(records[0].title) && values.contains(calendar.title) && values.contains("宽度测量夹具地址") && values.contains(notes), name + " all detail fields retain complete source content")
                check(native.count >= 6, name + " title/calendar/start/end/location/notes all mounted")
            }
            var cards: [[String: Any]] = []
            if session.route == .list {
                for record in records {
                    guard let frame = ProbeGeometry.cards[record.id] else { check(false, name + " actual card bounds " + record.id); continue }
                    cards.append(["id": record.id, "frame": rectJSON(frame)])
                }
                let titles = native.filter { records.map(\.title).contains($0.string) }
                let buttons = descendants(host).compactMap { $0 as? NSButton }.filter { $0.title == String(localized: "calendar.meeting.actions") }
                check(titles.count == 2 && buttons.count == 2, name + " both actual adjacent cards and meeting buttons")
                if titles.count == 2 && buttons.count == 2 {
                    for record in records {
                        guard let titleView = titles.first(where: { $0.string == record.title }) else { check(false, name + " actual card title found"); continue }
                        if let card = ProbeGeometry.cards[record.id] {
                            let title = rectangle(titleView)
                            check(card.insetBy(dx: -0.5, dy: -0.5).contains(title), name + " native title inside actual card " + record.id)
                            let candidates = buttons.filter { card.insetBy(dx: -0.5, dy: -0.5).contains(rectangle($0)) }
                            check(candidates.count == 1, name + " meeting button inside actual card " + record.id)
                            if let button = candidates.first {
                                check(button.visibleRect.height >= button.bounds.height - 0.5, name + " entire actual meeting entrance visible " + record.id)
                            }
                            cards.append(["id": record.id, "title": rectJSON(title), "meeting": candidates.map { rectJSON(rectangle($0)) }])
                        }
                    }
                    if let first = ProbeGeometry.cards[records[0].id], let second = ProbeGeometry.cards[records[1].id] {
                        check(!first.intersects(second), name + " actual adjacent cards disjoint")
                    }
                    let sortedTitles = titles.sorted { rectangle($0).minY < rectangle($1).minY }
                    let sortedButtons = buttons.sorted { rectangle($0).minY < rectangle($1).minY }
                    for (titleView, button) in zip(sortedTitles, sortedButtons) {
                        let t = rectangle(titleView), b = rectangle(button)
                        check(!t.intersects(b), name + " title and meeting do not overlap")
                        check(full ? titleView.textContainer?.maximumNumberOfLines == 0 : titleView.textContainer?.maximumNumberOfLines == 2, name + " requested title mode")
                        check(full ? t.height > 40 : t.height <= 40, name + " natural full / bounded two-line title height")
                    }
                    check(!rectangle(sortedTitles[0]).intersects(rectangle(sortedTitles[1])), name + " adjacent title slots disjoint")
                    check(rectangle(sortedButtons[0]).maxY <= rectangle(sortedTitles[1]).minY || rectangle(sortedButtons[1]).maxY <= rectangle(sortedTitles[0]).minY, name + " first card meeting outside next card title")
                }
            }
            // Raster evidence is mandatory: broad visible ink in each exposed native slot.
            // This works offline without Vision's sandbox-blocked recognition service.
            var visibleInk: [[String: Any]] = []
            func ink(_ rect: CGRect) -> (Int, Int) {
                let clipped = rect.intersection(host.bounds)
                guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return (0, 0) }
                let scaleX = CGFloat(rep.pixelsWide) / host.bounds.width
                let scaleY = CGFloat(rep.pixelsHigh) / host.bounds.height
                var count = 0, columns = Set<Int>()
                for x in max(0, Int(clipped.minX * scaleX))..<min(rep.pixelsWide, Int(clipped.maxX * scaleX)) {
                    for y in max(0, Int(clipped.minY * scaleY))..<min(rep.pixelsHigh, Int(clipped.maxY * scaleY)) {
                        if let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                           min(color.redComponent, color.greenComponent, color.blueComponent) > 0.62 {
                            count += 1; columns.insert(x)
                        }
                    }
                }
                return (count, columns.count)
            }
            for view in native {
                let visible = view.convert(view.visibleRect, to: host).intersection(host.bounds)
                if visible.isNull || visible.height < 5 || visible.width < 5 { continue }
                let pixels = ink(visible)
                check(pixels.0 > 10 && pixels.1 > 10, name + " visible raster ink " + String(view.string.prefix(12)))
                visibleInk.append(["text": String(view.string.prefix(20)), "visible": rectJSON(visible), "brightPixels": pixels.0, "inkColumns": pixels.1])
            }
            check(!visibleInk.isEmpty, name + " has visible native text ink")
            for field in required {
                let matches = native.filter { $0.string == field.text }
                check(matches.count == 1, name + " unique required field " + field.token)
                guard let view = matches.first, let manager = view.layoutManager, let container = view.textContainer else {
                    check(false, name + " required field complete TextKit " + field.token); continue
                }
                let characters = (view.string as NSString).range(of: field.token)
                check(characters.location != NSNotFound, name + " required complete character range " + field.token)
                guard characters.location != NSNotFound else { continue }
                let glyphs = manager.glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
                var fieldRect = manager.boundingRect(forGlyphRange: glyphs, in: container)
                fieldRect.origin.x += view.textContainerOrigin.x
                fieldRect.origin.y += view.textContainerOrigin.y
                let visible = view.visibleRect.intersection(fieldRect)
                check(!visible.isNull && visible.width >= fieldRect.width - 0.5 && visible.height >= fieldRect.height - 0.5,
                      name + " required entire character range in owning scroll viewport " + field.token)
                let hostField = view.convert(fieldRect, to: host)
                let visibleHost = host.bounds.intersection(hostField)
                check(!visibleHost.isNull && visibleHost.width >= hostField.width - 0.5 && visibleHost.height >= hostField.height - 0.5,
                      name + " required entire character range inside captured page " + field.token)
                let pixels = ink(hostField)
                check(pixels.0 > 30 && pixels.1 > 30, name + " required actual raster ink " + field.token)
                visibleInk.append(["required": field.token, "characters": [characters.location, characters.length],
                                   "nativeCharacterFrame": rectJSON(fieldRect), "owningScrollVisible": rectJSON(view.visibleRect),
                                   "frame": rectJSON(hostField), "brightPixels": pixels.0, "inkColumns": pixels.1])
            }
            if tail {
                let noteViews = native.filter { $0.string.contains("TAIL45") }
                check(noteViews.count == 1, name + " unique long notes text")
                if let note = noteViews.first, let manager = note.layoutManager, let container = note.textContainer {
                    let characters = (note.string as NSString).range(of: "TAIL45")
                    let glyphs = manager.glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
                    var endRect = manager.boundingRect(forGlyphRange: glyphs, in: container)
                    endRect.origin.x += note.textContainerOrigin.x
                    endRect.origin.y += note.textContainerOrigin.y
                    let visible = note.visibleRect
                    check(visible.intersection(endRect).height >= endRect.height - 0.5, name + " tail character range in scroll viewport")
                    let hostEnd = note.convert(endRect, to: host)
                    let pixels = ink(hostEnd)
                    check(pixels.0 > 15 && pixels.1 > 20, name + " TAIL45 actual raster ink visible")
                    visibleInk.append(["tail": "TAIL45", "frame": rectJSON(hostEnd), "brightPixels": pixels.0, "inkColumns": pixels.1])
                }
            }
            cases.append(["name": name, "png": png.path, "width": host.bounds.width, "route": String(describing: session.route),
                          "native": geometry, "cards": cards, "visibleInk": visibleInk])
        }
        for width: CGFloat in [640, 800, 1000] {
            host.frame.size.width = width
            session.showList(on: date)
            await pump(host)
            proposals("list-\(Int(width))")
            try capture("list-\(Int(width))")
            session.showDetail(records[0], source: .calendar(date: date, anchor: records[0].id))
            await pump(host)
            // Natural AppKit fitting queries are separate from the explicit min proposal injection.
            let before = textViews().map { [$0.frame.width, $0.textContainer?.containerSize.width ?? -1] }
            _ = host.fittingSize
            _ = host.intrinsicContentSize
            let after = textViews().map { [$0.frame.width, $0.textContainer?.containerSize.width ?? -1] }
            check(before == after, "detail-\(Int(width)) natural fitting purity")
            await pump(host)
            proposals("detail-\(Int(width))")
            try capture("detail-\(Int(width))")
            let scrolls = descendants(host).compactMap { $0 as? NSScrollView }.filter { ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height }
            check(scrolls.count == 1, "detail-\(Int(width)) one owning long content scroll")
            if let scroll = scrolls.first, let document = scroll.documentView {
                let locations = textViews().filter { $0.string == "宽度测量夹具地址" }
                check(locations.count == 1, "detail-mid-\(Int(width)) actual location field found")
                if let location = locations.first {
                    let rect = document.convert(location.bounds, from: location)
                    let y = max(0, min(rect.minY - 24, document.frame.height - scroll.contentView.bounds.height))
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    await pump(host)
                    try capture("detail-mid-\(Int(width))", required: [
                        (text: "宽度测量夹具地址", token: "宽度测量夹具地址"),
                        (text: notes, token: "1. 日程备注完整滚动验收。"),
                        (text: notes, token: "2. 日程备注完整滚动验收。")
                    ])
                }
                scroll.contentView.scroll(to: NSPoint(x: 0, y: document.frame.height - scroll.contentView.bounds.height))
                scroll.reflectScrolledClipView(scroll.contentView)
                await pump(host)
                try capture("tail-\(Int(width))", tail: true)
            }
            session.showList(on: date)
            await pump(host)
            try capture("back-\(Int(width))")
        }
        host.frame.size.width = 800
        session.beginCreate(kind: .event, on: date, calendarID: calendar.id)
        await pump(host)
        let editors = descendants(host).compactMap { $0 as? CalendarEditableTextView }
        check(editors.count == 2, "production editor source and notes present")
        if editors.count == 2 {
            let source = editors.first { $0.accessibilityLabel() == String(localized: "calendar.generation.source") }
            let notes = editors.first { $0.accessibilityLabel() == String(localized: "calendar.panel.notes") }
            check(source != nil && notes != nil, "production localized editor identities")
            source?.insertText("实际输入原文 SOURCE_INPUT\n明天讨论架构", replacementRange: NSRange(location: 0, length: 0))
            notes?.insertText("实际输入备注 NOTES_INPUT\n第二行说明", replacementRange: NSRange(location: 0, length: 0))
            await pump(host)
            check(session.draft?.sourceText.contains("SOURCE_INPUT") == true && session.draft?.notes.contains("NOTES_INPUT") == true, "actual native inputs update production draft bindings")
            proposals("editor")
            func expose(_ label: String, token: String, name: String) async throws {
                let current = textViews().compactMap { $0 as? CalendarEditableTextView }.first { $0.accessibilityLabel() == String(localized: String.LocalizationValue(label)) }
                let scrolls = descendants(host).compactMap { $0 as? NSScrollView }.filter { ($0.documentView?.frame.height ?? 0) > $0.contentView.bounds.height }
                check(current != nil && scrolls.count == 1, name + " actual editor and owning scroll found")
                if let view = current, let scroll = scrolls.first, let document = scroll.documentView {
                    let rect = document.convert(view.bounds, from: view)
                    let y = max(0, min(rect.minY - 24, document.frame.height - scroll.contentView.bounds.height))
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    await pump(host)
                    if let manager = view.layoutManager, let container = view.textContainer {
                        let characters = (view.string as NSString).range(of: token)
                        check(characters.location != NSNotFound, name + " inserted token retained")
                        if characters.location != NSNotFound {
                            let glyphs = manager.glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
                            var tokenRect = manager.boundingRect(forGlyphRange: glyphs, in: container)
                            tokenRect.origin.x += view.textContainerOrigin.x
                            tokenRect.origin.y += view.textContainerOrigin.y
                            check(view.visibleRect.intersection(tokenRect).height >= tokenRect.height - 0.5, name + " actual input entire first line visible")
                        }
                    } else { check(false, name + " complete editor TextKit") }
                    try capture(name)
                }
            }
            try await expose("calendar.generation.source", token: "实际输入原文 SOURCE_INPUT", name: "editor-source")
            try await expose("calendar.panel.notes", token: "实际输入备注 NOTES_INPUT", name: "editor-notes")
        }
        check(!window.isVisible, "window hidden through completion")
        let result: [String: Any] = ["passed": checks.allSatisfy { $0["passed"] as? Bool == true }, "checks": checks, "cases": cases,
            "fullTitles": full, "background": gray ? "gray" : "dark", "date": "2026-10-14T15:30:00+08:00",
            "natural": "actual host.fittingSize/intrinsicContentSize after detail allocation",
            "injection": "explicit production native measuredSize 0/200/1/374/80/0; not natural last-zero reproduction"]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("geometry.json"))
        window.close()
        if !checks.allSatisfy({ $0["passed"] as? Bool == true }) {
            for check in checks where check["passed"] as? Bool == false { print("FAIL", check["name"]!) }
            exit(1)
        }
        print("PASS", cases.count, "production page PNGs", checks.count, "checks")
    }
}
'''


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--debug-products', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--baseline-ref', help='optional historical source ref for explicit failing comparison only')
    args = parser.parse_args()
    root, products, out = args.repo.resolve(), args.debug_products.resolve(), args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    dylib = products / 'Gourd.app/Contents/MacOS/Gourd.debug.dylib'
    if not dylib.is_file() or not (products / 'Gourd.swiftmodule').exists():
        parser.error('explicit Debug products must contain testable Gourd.swiftmodule and Gourd.debug.dylib')
    def read(name):
        if args.baseline_ref:
            return subprocess.run(['git', 'show', args.baseline_ref + ':' + name], cwd=root, capture_output=True, text=True, check=True).stdout
        return (root / name).read_text()
    inputs = {name: read(name) for name in SOURCES}
    source = STUBS
    for name in SOURCES[:3]:
        source += inputs[name]
    cards = inputs[SOURCES[3]]
    card = cards[cards.index('struct CalendarEventCard: View'):cards.index('/// 待办卡片')]
    card = card.replace('.opacity(event.eventStatus', '.background(ProbeCardReader(id: event.id))\n        .opacity(event.eventStatus')
    source += card
    page = inputs[SOURCES[4]]
    source += page[page.index('struct StandaloneCalendarView: View'):page.index('struct EmptyEventsView: View')]
    source += page[page.index('struct ConferenceJoinButton: View'):page.rindex('#Preview')]
    # Dependency substitutions only: preserve all production layout expressions.
    for key in ('hideAllDayEvents', 'hideCompletedReminders', 'showFullEventTitles', 'autoScrollToNextEvent'):
        source = source.replace('@Default(.' + key + ')', '@Default(ProbePreferences.' + key + ')')
    source = source.replace('Date().startOfMonth', 'ProbeClock.now.startOfMonth')
    if args.baseline_ref:
        # The old editor's sizeThatFits requires SwiftUI Context. Expose its exact body on
        # that same native view for proposal injection; preserve every calculation.
        editor_source = inputs[SOURCES[2]]
        start = editor_source.index('        let width = max(1, proposal.width ?? 200)')
        end = editor_source.index('\n    }', start)
        body = editor_source[start:end].replace('proposal.width ?? 200', 'proposedWidth').replace('nsView.', 'self.')
        insertion = source.index('    override func becomeFirstResponder()')
        source = source[:insertion] + '    func measuredSize(width proposedWidth: CGFloat) -> CGSize {\n' + body + '\n    }\n' + source[insertion:]
    source += MAIN
    # A bare executable avoids LaunchServices .app registration in the sandbox.
    macos = out
    resources = out
    macos.mkdir(parents=True, exist_ok=True)
    resources.mkdir(parents=True, exist_ok=True)
    if not (products / 'Gourd.app/Contents/Resources/zh-Hans.lproj').is_dir():
        parser.error('Debug product must include actual zh-Hans localization resources')
    # Use built production localization, never fabricated translated strings.
    for localization in (products / 'Gourd.app/Contents/Resources').glob('*.lproj'):
        shutil.copytree(localization, resources / localization.name, dirs_exist_ok=True)
    generated = out / 'generated.swift'
    generated.write_text(source)
    command = ['xcrun', 'swiftc', '-disable-sandbox', '-parse-as-library', '-target', 'arm64-apple-macos26.0',
               '-module-name', 'CalendarPageProbe', '-module-cache-path', str(out / 'module-cache'),
               '-I', str(products), '-F', str(products), str(generated), str(dylib), '-o', str(macos / 'probe')]
    subprocess.run(command, check=True)
    env = dict(os.environ, DYLD_LIBRARY_PATH=str(dylib.parent), DYLD_FRAMEWORK_PATH=str(products),
               XCTestConfigurationFilePath=str(out / 'no-system-tests'), TZ='Asia/Shanghai')
    runs = []
    for full in ('false', 'true'):
        for background in ('dark', 'gray'):
            case = out / (full + '-' + background)
            case.mkdir(exist_ok=True)
            run = [str(macos / 'probe'), str(case), full, background, '--uitesting', '-AppleLanguages', '(zh-Hans)', '-AppleLocale', 'zh_CN']
            result = subprocess.run(run, env=env, capture_output=True, text=True)
            (case / 'run.log').write_text(result.stdout + result.stderr)
            runs.append({'command': run, 'exit': result.returncode, 'geometry': str(case / 'geometry.json')})
    manifest = {'sourceRef': args.baseline_ref or 'working tree', 'sources': {name: hashlib.sha256(value.encode()).hexdigest() for name, value in inputs.items()}, 'debugProducts': str(products),
                'actualApp': str(products / 'Gourd.app'),
                'actualAppInfoSHA256': sha(products / 'Gourd.app/Contents/Info.plist'),
                'actualAppExecutableSHA256': sha(products / 'Gourd.app/Contents/MacOS/Gourd'),
                'actualAppResources': {str(p.relative_to(products / 'Gourd.app/Contents/Resources')): sha(p) for p in (products / 'Gourd.app/Contents/Resources').rglob('*') if p.is_file()},
                'dylib': str(dylib), 'dylibSHA256': sha(dylib), 'generatedSHA256': sha(generated),
                'toolSHA256': sha(__file__), 'executableSHA256': sha(macos / 'probe'), 'compile': command, 'runs': runs,
                'files': {str(p.relative_to(out)): sha(p) for p in out.rglob('*') if p.is_file() and p.suffix in ('.png', '.json', '.strings', '.swift')},
                'stubs': ['empty DynamicIslandViewModel and Coordinator (no production singletons)',
                          'CalendarEditorLifecycle + CalendarEditorWindowReader (no lifecycle monitors)',
                          'CalendarInteractionMemoryService injected into actual CalendarManager/CalendarPanelSession',
                          'four Defaults keys use isolated org.gourd.calendar-layout.preferences suite, restored after each run',
                          'StandaloneCalendarView initial displayedMonth uses fixed fixture clock; no layout substitution',
                          'non-layout card background GeometryReader observes bounds in fixture root coordinate space',
                          'baseline only: exact original editor sizeThatFits body exposed as native measuredSize for injection' if args.baseline_ref else 'current production native measurement methods unchanged'],
                'limits': ['source-assembled production page linked to explicit actual Debug dylib; not AppMain/ContentView',
                           'mandatory raster ink distribution plus tail character-range viewport and pixels; no Vision OCR service',
                           'no orderFront, activation, mouse, AI, real calendar or meeting dispatch',
                           'natural last-zero production ordering and original list overflow remain unproven',
                           'gray screenshot is controlled gray backing, not a live liquid-glass system compositor'],
                'passed': all(r['exit'] == 0 for r in runs)}
    (out / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    print(json.dumps({'passed': manifest['passed'], 'manifest': str(out / 'manifest.json'), 'runs': runs}, ensure_ascii=False))
    return 0 if manifest['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
