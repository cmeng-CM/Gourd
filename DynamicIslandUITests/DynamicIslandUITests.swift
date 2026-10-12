import AppKit
import XCTest

final class DynamicIslandUITests: XCTestCase {

    private let isolatedBundleIdentifier = "com.cmeng.gourd.calendar-tests.Gourd"
    private var launchedApplication: NSRunningApplication?
    private var launchedProcessIdentifier: pid_t?
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: isolatedBundleIdentifier)
        app.launchArguments = ["--uitesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if name.contains("Nine") { app.launchArguments.append("--calendar-fixture-count=9") }
        if name.contains("PermanentFailure") { app.launchArguments.append("--calendar-write-failure") }
        if name.contains("Retry") { app.launchArguments.append("--calendar-write-failure-once") }
        if name.contains("Delayed") { app.launchArguments.append("--calendar-write-delay-ms=2000") }
        app.launch()
        guard let process = isolatedApplicationProcess() else { return }
        launchedApplication = process
        launchedProcessIdentifier = process.processIdentifier
        guard requireIsolatedApplication() else { return }
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "Isolated AUT must be foreground before opening a draft")
        guard requireKeyboardApplication() else { return }
        XCTAssertTrue(element("GourdNotch").waitForExistence(timeout: 20))
        hover(element("GourdNotch"))
        XCTAssertTrue(element("calendar-fixture-ready").waitForExistence(timeout: 25))
    }

    override func tearDownWithError() throws {
        if let app, app.state != .notRunning, requireIsolatedApplication() {
            let attachment = XCTAttachment(string: app.debugDescription)
            attachment.name = "AX final state"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
        app = nil
        launchedApplication = nil
        launchedProcessIdentifier = nil
    }

    /// Public metadata identifies the unique live process for the explicit isolated bundle.
    private func isolatedApplicationProcess(file: StaticString = #filePath, line: UInt = #line) -> NSRunningApplication? {
        guard let app, app.state != .notRunning else {
            XCTFail("Isolated AUT must be running", file: file, line: line)
            return nil
        }
        let processes = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == isolatedBundleIdentifier && !$0.isTerminated
        }
        guard processes.count == 1, let process = processes.first else {
            XCTFail("Expected one isolated AUT for \(isolatedBundleIdentifier), found \(processes.count)", file: file, line: line)
            return nil
        }
        return process
    }

    /// Reject replacement processes; background hover and scroll remain valid.
    @discardableResult
    private func requireIsolatedApplication(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard let launchedApplication, let launchedProcessIdentifier else {
            XCTFail("No isolated AUT process recorded for this launch", file: file, line: line)
            return false
        }
        guard let process = isolatedApplicationProcess(file: file, line: line) else { return false }
        guard process.isEqual(launchedApplication), process.processIdentifier == launchedProcessIdentifier else {
            XCTFail("Isolated AUT process identity changed from this launch's PID \(launchedProcessIdentifier) to PID \(process.processIdentifier)", file: file, line: line)
            return false
        }
        return true
    }

    /// Keyboard events require both public foreground signals without reactivating mid-draft.
    @discardableResult
    private func requireKeyboardApplication(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard requireIsolatedApplication(file: file, line: line) else { return false }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == launchedProcessIdentifier,
              app.state == .runningForeground else {
            XCTFail("Keyboard input requires this launch's isolated AUT in the foreground", file: file, line: line)
            return false
        }
        return true
    }

    private func hover(_ target: XCUIElement) {
        guard requireIsolatedApplication() else { return }
        target.hover()
    }

    private func typeApplicationKey(_ key: String, modifiers: XCUIElement.KeyModifierFlags = []) {
        guard requireKeyboardApplication() else { return }
        app.typeKey(key, modifierFlags: modifiers)
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func wait(_ predicate: String, on target: XCUIElement, timeout: TimeInterval = 8) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: target)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, "\(target) did not satisfy \(predicate)")
    }

    private func visible(_ target: XCUIElement, in viewport: XCUIElement) -> Bool {
        guard target.exists, target.isHittable else { return false }
        return viewport.frame.contains(CGPoint(x: target.frame.midX, y: target.frame.midY))
    }

    private func scrollTo(_ id: String, in scrollID: String, down: Bool = true) {
        let scroll = element(scrollID)
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        hover(scroll)
        if visible(element(id), in: scroll) { return }
        if !down {
            for _ in 0..<15 {
                guard requireIsolatedApplication() else { return }
                scroll.scroll(byDeltaX: 0, deltaY: 240)
            }
        }
        for _ in 0..<45 {
            if visible(element(id), in: scroll) { return }
            guard requireIsolatedApplication() else { return }
            scroll.scroll(byDeltaX: 0, deltaY: -160)
        }
        screenshot("unreachable-\(id)")
        XCTFail("\(id) must be visible and hittable inside \(scrollID)")
    }

    private func click(_ id: String) {
        guard requireIsolatedApplication() else { return }
        XCTAssertTrue(element(id).waitForExistence(timeout: 8), id)
        XCTAssertTrue(element(id).isHittable, "\(id) must be hittable")
        guard requireIsolatedApplication() else { return }
        element(id).click()
    }

    private func replace(_ id: String, with value: String) {
        click(id)
        let field = element(id)
        guard requireKeyboardApplication() else { return }
        field.typeKey("a", modifierFlags: .command)
        guard requireKeyboardApplication() else { return }
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value, "Keyboard focus must edit the actual field")
    }

    private func openEvent(_ id: String = "fixture-event-01") {
        scrollTo("home-item-\(id)", in: "home-today-scroll", down: false)
        click("home-item-\(id)")
        XCTAssertTrue(element("calendar-detail-scroll").waitForExistence(timeout: 5))
        XCTAssertFalse(element("home-today-scroll").exists)
        XCTAssertFalse(element("calendar-list-scroll").exists)
    }

    private func editEvent() {
        openEvent()
        click("calendar-edit")
        XCTAssertTrue(element("calendar-editor-scroll").waitForExistence(timeout: 5))
    }

    private func calendarTab() {
        click("panel-tab-module-com.cmeng.gourd.calendar")
    }

    private func checkHomeTail(count: Int, reminderCount: Int) {
        let header = element("home-counts")
        XCTAssertNotNil(header.label.range(of: "(?<![0-9])1/\(reminderCount)(?![0-9])", options: .regularExpression), header.label)
        let originalHeader = header.frame
        let tailID = String(format: "fixture-reminder-%02d", count)
        scrollTo("home-item-\(tailID)", in: "home-today-scroll")
        XCTAssertEqual(header.frame.minY, originalHeader.minY, accuracy: 2)
        XCTAssertEqual(header.frame.height, originalHeader.height, accuracy: 2)
        screenshot("home-\(count)-tail-before")
        let circle = element("home-complete-\(tailID)")
        XCTAssertEqual(circle.label, "Mark complete")
        click("home-complete-\(tailID)")
        wait("label == 'Mark incomplete'", on: circle)
        XCTAssertNotNil(header.label.range(of: "(?<![0-9])2/\(reminderCount)(?![0-9])", options: .regularExpression), header.label)
        XCTAssertTrue(element("home-today-scroll").exists)
        XCTAssertFalse(element("calendar-detail-scroll").exists)
        XCTAssertTrue(visible(element("home-item-\(tailID)"), in: element("home-today-scroll")))
        screenshot("home-\(count)-tail-completed")
        click("home-item-\(tailID)")
        XCTAssertTrue(element("calendar-detail-scroll").waitForExistence(timeout: 5))
        click("calendar-back")
        XCTAssertTrue(element("home-today-scroll").waitForExistence(timeout: 5))
        XCTAssertTrue(visible(element("home-item-\(tailID)"), in: element("home-today-scroll")), "Return restores the home anchor")
    }

    func testNineItemsTailAndIndependentCompletion() { checkHomeTail(count: 9, reminderCount: 6) }
    func testThirtyItemsTailAndIndependentCompletion() { checkHomeTail(count: 30, reminderCount: 20) }

    func testHomePermanentFailureKeepsCircleAndCounts() {
        scrollTo("home-item-fixture-reminder-30", in: "home-today-scroll")
        let header = element("home-counts").label
        click("home-complete-fixture-reminder-30")
        XCTAssertTrue(element("home-error").waitForExistence(timeout: 8))
        XCTAssertEqual(element("home-complete-fixture-reminder-30").label, "Mark complete")
        XCTAssertEqual(element("home-counts").label, header)
        XCTAssertFalse(element("calendar-detail-scroll").exists)
        screenshot("completion-failure")
    }

    func testDetailFullNotesAndHomeAnchor() {
        openEvent()
        let backFrame = element("calendar-back").frame
        let editFrame = element("calendar-edit").frame
        scrollTo("calendar-notes-end", in: "calendar-detail-scroll")
        let fullNotes = app.staticTexts.containing(NSPredicate(format: "value CONTAINS %@", "END OF NOTES fixture-event-01")).firstMatch
        XCTAssertTrue(fullNotes.exists, "Complete note text must include its final source line")
        XCTAssertTrue(visible(element("calendar-notes-end"), in: element("calendar-detail-scroll")))
        XCTAssertEqual(element("calendar-back").frame.minY, backFrame.minY, accuracy: 2)
        XCTAssertEqual(element("calendar-edit").frame.minY, editFrame.minY, accuracy: 2)
        XCTAssertTrue(element("calendar-open-system").isHittable)
        screenshot("detail-full-notes-end")
        click("calendar-back")
        XCTAssertTrue(element("home-today-scroll").waitForExistence(timeout: 5))
        XCTAssertTrue(visible(element("home-item-fixture-event-01"), in: element("home-today-scroll")))
    }

    func testEditSaveAndDeleteOrdinaryEvent() {
        editEvent()
        replace("calendar-title", with: "Edited ordinary event")
        scrollTo("calendar-location", in: "calendar-editor-scroll")
        replace("calendar-location", with: "Edited room")
        scrollTo("calendar-notes", in: "calendar-editor-scroll")
        replace("calendar-notes", with: "Edited notes END")
        XCTAssertTrue(element("calendar-save").isHittable)
        click("calendar-save")
        XCTAssertTrue(element("calendar-detail-scroll").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Edited ordinary event"].exists)
        XCTAssertTrue(app.staticTexts["Edited room"].exists)
        screenshot("saved-ordinary-event")
        click("calendar-back")
        openEvent()
        XCTAssertTrue(app.staticTexts["Edited ordinary event"].exists, "Reopening the stable record ID must read the saved title")
        click("calendar-delete")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Edited ordinary event'")).firstMatch.exists)
        click("calendar-delete-cancel")
        XCTAssertTrue(element("calendar-edit").exists)
        click("calendar-delete")
        click("calendar-delete-confirm")
        XCTAssertTrue(element("home-today-scroll").waitForExistence(timeout: 8))
        XCTAssertFalse(element("home-item-fixture-event-01").exists)
        screenshot("deleted-ordinary-event")
    }

    func testRestrictedEventsHaveOnlySystemMaintenance() {
        calendarTab()
        for id in ["fixture-event-04", "fixture-event-07", "fixture-event-10", "fixture-event-13", "fixture-event-16"] {
            scrollTo("calendar-item-\(id)", in: "calendar-list-scroll", down: false)
            click("calendar-item-\(id)")
            XCTAssertTrue(element("calendar-detail-scroll").waitForExistence(timeout: 5))
            XCTAssertFalse(element("calendar-edit").exists, id)
            XCTAssertFalse(element("calendar-delete").exists, id)
            XCTAssertTrue(element("calendar-open-system").isHittable, id)
            screenshot("restricted-\(id)")
            click("calendar-back")
        }
    }

    func testDraftBackResumeCancelAndSingleDraftConflict() {
        editEvent()
        replace("calendar-title", with: "Unsaved preserved draft")
        click("calendar-back")
        XCTAssertTrue(element("calendar-detail-scroll").waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Unsaved preserved draft"].exists, "Back must not write the draft")
        click("calendar-back")
        calendarTab()
        click("calendar-resume-draft")
        XCTAssertEqual(element("calendar-title").value as? String, "Unsaved preserved draft")
        click("calendar-cancel")
        XCTAssertTrue(element("calendar-draft-discard").waitForExistence(timeout: 5))
        click("calendar-discard-cancel")
        XCTAssertEqual(element("calendar-title").value as? String, "Unsaved preserved draft")
        click("calendar-back")
        click("calendar-back")
        calendarTab()
        click("calendar-add")
        XCTAssertTrue(element("calendar-draft-conflict").waitForExistence(timeout: 5))
        click("calendar-conflict-cancel")
        XCTAssertTrue(element("calendar-resume-draft").exists)
        click("calendar-add")
        click("calendar-conflict-resume")
        XCTAssertEqual(element("calendar-title").value as? String, "Unsaved preserved draft")
        screenshot("single-draft-resumed")
        click("calendar-back")
        click("calendar-back")
        calendarTab()
        click("calendar-add")
        click("calendar-conflict-discard")
        XCTAssertTrue(element("calendar-editor-scroll").waitForExistence(timeout: 5))
        XCTAssertEqual(element("calendar-title").value as? String, "")
        click("calendar-cancel")
        XCTAssertFalse(element("calendar-resume-draft").exists)
    }

    func testDirtyDraftConfirmedDiscardKeepsOriginalRecord() {
        editEvent()
        replace("calendar-title", with: "Discard this draft")
        click("calendar-cancel")
        click("calendar-discard-confirm")
        XCTAssertTrue(element("calendar-detail-scroll").waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Discard this draft"].exists)
        click("calendar-back")
        calendarTab()
        XCTAssertFalse(element("calendar-resume-draft").exists)
    }

    func testSameDraftRetryWritesOnlyAfterSuccessfulSecondSave() {
        editEvent()
        replace("calendar-title", with: "Retried title")
        click("calendar-save")
        XCTAssertTrue(element("calendar-error").waitForExistence(timeout: 8))
        XCTAssertEqual(element("calendar-title").value as? String, "Retried title")
        XCTAssertTrue(element("calendar-editor-scroll").exists)
        screenshot("same-draft-first-save-failure")
        click("calendar-back")
        XCTAssertFalse(app.staticTexts["Retried title"].exists)
        click("calendar-back")
        calendarTab()
        click("calendar-resume-draft")
        XCTAssertEqual(element("calendar-title").value as? String, "Retried title")
        click("calendar-save")
        XCTAssertTrue(element("calendar-detail-scroll").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Retried title"].exists)
        screenshot("same-draft-second-save-success")
        click("calendar-back")
        calendarTab()
        scrollTo("calendar-item-fixture-event-01", in: "calendar-list-scroll", down: false)
        click("calendar-item-fixture-event-01")
        XCTAssertTrue(app.staticTexts["Retried title"].exists)
    }

    func testSavePermanentFailurePreservesInputAndEnablesRetry() {
        editEvent()
        replace("calendar-title", with: "Failed unsaved title")
        click("calendar-save")
        XCTAssertTrue(element("calendar-error").waitForExistence(timeout: 8))
        XCTAssertEqual(element("calendar-title").value as? String, "Failed unsaved title")
        XCTAssertTrue(element("calendar-save").isEnabled)
        click("calendar-save")
        XCTAssertTrue(element("calendar-error").exists)
        XCTAssertTrue(element("calendar-editor-scroll").exists)
        XCTAssertEqual(element("calendar-title").value as? String, "Failed unsaved title")
    }

    func testCreateDelayedSaveReturnsRealStableID() {
        calendarTab()
        click("calendar-add")
        XCTAssertTrue(element("calendar-kind").waitForExistence(timeout: 5))
        guard requireIsolatedApplication() else { return }
        app.descendants(matching: .any).matching(identifier: "Event").firstMatch.click()
        replace("calendar-title", with: "Created real fixture event")
        click("calendar-save")
        wait("enabled == false", on: element("calendar-save"), timeout: 1)
        XCTAssertFalse(element("calendar-title").isEnabled)
        screenshot("submission-disabled")
        XCTAssertTrue(element("calendar-detail-scroll").waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Created real fixture event"].exists)
        click("calendar-back")
        scrollTo("calendar-item-fixture-created-1", in: "calendar-list-scroll")
        click("calendar-item-fixture-created-1")
        XCTAssertTrue(app.staticTexts["Created real fixture event"].exists)
        screenshot("created-stable-record")
    }

    func testExternalFinderDepartureClosesAndResumesDraft() {
        editEvent()
        replace("calendar-title", with: "Draft survives Finder departure")
        hover(element("GourdNotch"))
        let openFrame = element("GourdNotch").frame
        guard requireIsolatedApplication() else { return }
        element("GourdNotch").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1))
            .withOffset(CGVector(dx: 0, dy: 80)).hover()
        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
        wait("exists == false", on: element("calendar-fixture-ready"), timeout: 10)
        XCTAssertFalse(element("calendar-editor-scroll").exists)
        XCTAssertLessThan(element("GourdNotch").frame.height, openFrame.height)
        XCTAssertNotEqual(app.state, .notRunning)
        screenshot("external-departure-closed")
        hover(element("GourdNotch"))
        XCTAssertTrue(element("calendar-fixture-ready").waitForExistence(timeout: 8))
        calendarTab()
        click("calendar-resume-draft")
        XCTAssertEqual(element("calendar-title").value as? String, "Draft survives Finder departure")
        screenshot("external-departure-resumed")
    }

    func testNativeQuitCancelKeepsDirtyDraft() {
        editEvent()
        replace("calendar-title", with: "Cancel native quit draft")
        typeApplicationKey("q", modifiers: .command)
        XCTAssertTrue(element("calendar-quit-cancel").waitForExistence(timeout: 8), "Cmd+Q must enter the normal AppDelegate termination decision")
        screenshot("native-quit-decision")
        click("calendar-quit-cancel")
        XCTAssertNotEqual(app.state, .notRunning)
        hover(element("GourdNotch"))
        XCTAssertTrue(element("calendar-fixture-ready").waitForExistence(timeout: 8))
        if !element("calendar-title").exists {
            calendarTab()
            click("calendar-resume-draft")
        }
        XCTAssertEqual(element("calendar-title").value as? String, "Cancel native quit draft")
    }

    func testAccessibilityProbe() {
        screenshot("home-probe")
        print("T6 AX HOME\n\(app.debugDescription)")
        click("home-item-fixture-event-01")
        XCTAssertTrue(element("calendar-detail-scroll").waitForExistence(timeout: 5))
        click("calendar-edit")
        XCTAssertTrue(element("calendar-title").waitForExistence(timeout: 5))
        click("calendar-title")
        screenshot("editor-probe")
        print("T6 AX EDITOR\n\(app.debugDescription)")
        click("calendar-target")
        print("T6 AX MENU\n\(app.debugDescription)")
        typeApplicationKey(XCUIKeyboardKey.escape.rawValue)
        XCTAssertTrue(element("calendar-editor-scroll").exists)
        click("calendar-start-date")
        print("T6 AX DATE\n\(app.debugDescription)")
        typeApplicationKey(XCUIKeyboardKey.escape.rawValue)
        XCTAssertTrue(element("calendar-editor-scroll").exists)
    }

    // App launches and stays alive without crashing.
    func testAppLaunchesWithoutCrashing() throws {
        let isRunning = app.wait(for: .runningForeground, timeout: 10.0)
            || app.wait(for: .runningBackground, timeout: 10.0)
        XCTAssertTrue(isRunning, "App should be running after launch.")
        XCTAssertNotEqual(app.state, .notRunning, "App should not have terminated.")
    }

    // The notch panel is present and exposed to accessibility.
    func testNotchExpansion() throws {
        let notch = app.descendants(matching: .any)["GourdNotch"]
        XCTAssertTrue(notch.waitForExistence(timeout: 15.0), "The Gourd notch should be visible.")
    }
}
