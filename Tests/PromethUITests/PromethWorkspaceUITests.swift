import AppKit
import XCTest

@MainActor
final class PromethWorkspaceUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testFreshWelcomeKeepsSelectionsAndAddsImageSize() {
        let app = XCUIApplication()
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("prometh-welcome-\(UUID().uuidString)", isDirectory: true)
        app.launchArguments = ["--prometh-flags=promethShell"]
        app.launchEnvironment = ["PROMETH_SUPPORT_DIR": support.path]
        app.launch()

        XCTAssertTrue(app.staticTexts["AI that you own."].waitForExistence(timeout: 20))
        for line in ["Fully private.", "No accounts.", "Full control.", "Your choice of models.", "Runs on your Mac."] {
            XCTAssertTrue(app.staticTexts[line].exists, line)
        }
        XCTAssertTrue(app.staticTexts["1 / 4"].waitForExistence(timeout: 5))
        XCTAssertTrue(identified(app, "prometh.step").exists)

        let start = app.buttons["Get started"]
        let hittableDeadline = Date().addingTimeInterval(8)
        while Date() < hittableDeadline, !start.isHittable {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(start.isHittable, "Get started frame \(start.frame)")
        start.click()
        let advanced = app.staticTexts["What capabilities do you want to enable?"].waitForExistence(timeout: 10)
        if !advanced {
            let labels = app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
            XCTFail("Did not reach capabilities. Visible text: \(labels)")
        }
        XCTAssertTrue(app.staticTexts["2 / 4"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Chat is the default."].exists)
        XCTAssertTrue(app.staticTexts["5.18 GB"].waitForExistence(timeout: 5))
        let images = app.buttons["Images, not selected, 4.62 GB. Make photos"]
        XCTAssertTrue(images.waitForExistence(timeout: 5))
        images.click()
        XCTAssertTrue(app.staticTexts["9.80 GB"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Images, selected, 4.62 GB. Make photos"].waitForExistence(timeout: 5))

        app.buttons["Back"].click()
        XCTAssertTrue(app.staticTexts["1 / 4"].waitForExistence(timeout: 5))
        app.buttons["Get started"].click()
        XCTAssertTrue(app.buttons["Images, selected, 4.62 GB. Make photos"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["9.80 GB"].exists)
    }

    func testWorkspaceChatAndHiddenChrome() throws {
        let app = XCUIApplication()
        let export = FileManager.default.temporaryDirectory.appendingPathComponent("prometh-export-\(UUID().uuidString).md")
        app.launchArguments = ["--prometh-flags=promethShell"]
        app.launchEnvironment = ["PROMETH_EXPORT_PATH": export.path]
        app.launch()

        let draft = app.textViews["prometh.draft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 30))
        XCTAssertTrue(identified(app, "prometh.sidebar").waitForExistence(timeout: 5))
        XCTAssertTrue(identified(app, "prometh.composer").exists)
        XCTAssertTrue(identified(app, "prometh.mode").exists)

        identified(app, "prometh.sidebar").click()
        draft.click()
        app.typeText("Say hello in five words.")
        let replies = app.descendants(matching: .any).matching(identifier: "prometh.reply")
        let before = replies.count
        XCTAssertTrue(identified(app, "prometh.send").waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])
        let deadline = Date().addingTimeInterval(90)
        var ready = false
        while Date() < deadline {
            if replies.count > before, replyLooksReady(app) {
                ready = true
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(ready, replyDiagnostics(app))

        draft.click()
        app.typeText("Write a long story about the ocean in many paragraphs.")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitUntilStoppable(app, timeout: 90))
        identified(app, "prometh.send").click()
        XCTAssertTrue(app.staticTexts["Stopped"].waitForExistence(timeout: 20))

        app.buttons["Edit"].firstMatch.click()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        app.typeKey("a", modifierFlags: [.command])
        app.typeText("Say hello in four words.")
        app.buttons["Save & send"].click()
        XCTAssertTrue(waitForReply(in: app, timeout: 180))

        app.buttons["Regenerate response"].firstMatch.click()
        XCTAssertTrue(waitForReply(in: app, timeout: 180))

        app.buttons["Copy response"].firstMatch.click()
        let copied = copiedText()
        XCTAssertFalse(copied.isEmpty, "clipboard was empty after Copy response")

        let conversationName = "Ocean notes \(String(UUID().uuidString.prefix(4)))"
        identified(app, "prometh.conversation.menu").click()
        app.menuItems["Rename conversation"].click()
        let title = app.textFields["Conversation title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.click()
        app.typeKey("a", modifierFlags: [.command])
        app.typeText(conversationName)
        app.buttons["Save"].click()
        XCTAssertTrue(app.staticTexts[conversationName].waitForExistence(timeout: 5))

        let search = app.textFields["prometh.search"]
        search.click()
        search.typeText(conversationName)
        XCTAssertTrue(app.staticTexts[conversationName].waitForExistence(timeout: 5))
        search.typeText("zzzz-missing")
        XCTAssertTrue(app.staticTexts["No conversations found"].waitForExistence(timeout: 5))
        search.typeKey("a", modifierFlags: [.command])
        search.typeKey(.delete, modifierFlags: [])
        search.typeText(conversationName)
        XCTAssertTrue(app.staticTexts[conversationName].waitForExistence(timeout: 5))

        identified(app, "prometh.conversation.menu").click()
        app.menuItems["Export conversation"].click()
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.path))
        let exported = try String(contentsOf: export, encoding: .utf8)
        XCTAssertTrue(exported.contains("Say hello"))

        let actions = identified(app, "prometh.conversation.actions")
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.click()
        let deletes = app.menuItems.matching(identifier: "Delete")
        let opened = Date().addingTimeInterval(5)
        var clickedDelete = false
        while Date() < opened, !clickedDelete {
            let count = deletes.count
            for index in 0..<count {
                let item = deletes.element(boundBy: index)
                if item.isHittable {
                    item.click()
                    clickedDelete = true
                    break
                }
            }
            if !clickedDelete { Thread.sleep(forTimeInterval: 0.2) }
        }
        XCTAssertTrue(clickedDelete, "Delete menu item count \(deletes.count)")
        let confirmations = app.buttons.matching(identifier: "Delete conversation")
        let confirmDeadline = Date().addingTimeInterval(5)
        var confirmed = false
        while Date() < confirmDeadline, !confirmed {
            let count = confirmations.count
            for index in 0..<count {
                let button = confirmations.element(boundBy: index)
                if button.isHittable, frameIsInMainWindow(button, app: app) {
                    button.click()
                    confirmed = true
                    break
                }
            }
            if !confirmed { Thread.sleep(forTimeInterval: 0.2) }
        }
        XCTAssertTrue(confirmed, "Delete conversation button count \(confirmations.count)")
        let removed = Date().addingTimeInterval(10)
        while Date() < removed, app.staticTexts[conversationName].exists {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertFalse(app.staticTexts[conversationName].exists)

        app.buttons["Settings"].click()
        for tab in ["Appearance", "Capabilities", "Privacy & data"] {
            XCTAssertTrue(identified(app, "prometh.settings.\(tab)").waitForExistence(timeout: 5))
        }
        assertHiddenChrome(in: app)
        app.buttons["Close settings"].click()

        draft.click()
        app.typeText("unsent draft line")
        app.terminate()
        app.launch()
        XCTAssertTrue(draft.waitForExistence(timeout: 30))
        let draftDeadline = Date().addingTimeInterval(15)
        var restored = false
        var seen = ""
        while Date() < draftDeadline {
            seen = draft.value as? String ?? ""
            if seen.contains("unsent draft line") {
                restored = true
                break
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(restored, "draft value [\(seen)]")
        assertHiddenChrome(in: app)
    }

    private func frameIsInMainWindow(_ element: XCUIElement, app: XCUIApplication) -> Bool {
        let windows = app.windows.allElementsBoundByIndex
        guard let host = windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            return false
        }
        return host.frame.intersects(element.frame)
    }

    private func identified(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func textOf(_ element: XCUIElement) -> String {
        if !element.label.isEmpty { return element.label }
        return (element.value as? String) ?? ""
    }

    private func buttonContaining(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        for element in app.buttons.allElementsBoundByIndex where textOf(element).contains(text) {
            return element
        }
        return app.buttons[text]
    }

    private func gigabyteLabel(_ app: XCUIApplication) -> String {
        for element in app.staticTexts.allElementsBoundByIndex {
            let text = textOf(element)
            if text.hasSuffix(" GB"), text.count < 16 { return text }
        }
        for element in app.staticTexts.allElementsBoundByIndex {
            let text = textOf(element)
            if text.contains("GB"), text.count < 24 { return text }
        }
        return ""
    }

    private func number(in label: String) -> Double {
        let digits = label.filter { $0.isNumber || $0 == "." }
        return Double(digits) ?? -1
    }

    private func waitForReply(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if replyLooksReady(app) { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    /// macOS pasteboard privacy can hide NSPasteboard reads from the test runner.
    /// pbpaste sees the general clipboard the app just wrote.
    private func copiedText() -> String {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if let direct = NSPasteboard.general.string(forType: .string), !direct.isEmpty {
                return direct
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pbpaste")
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            let pasted = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !pasted.isEmpty { return pasted }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return ""
    }

    private func replyLooksReady(_ app: XCUIApplication) -> Bool {
        let replies = app.descendants(matching: .any).matching(identifier: "prometh.reply")
        let count = replies.count
        guard count > 0 else { return false }
        for index in 0..<count {
            let label = replies.element(boundBy: index).label
            if label.localizedCaseInsensitiveContains("hello"), !label.contains("Say hello") {
                return true
            }
        }
        return false
    }

    private func replyDiagnostics(_ app: XCUIApplication) -> String {
        let replies = app.descendants(matching: .any).matching(identifier: "prometh.reply")
        let count = replies.count
        var labels: [String] = []
        if count > 0 {
            for index in 0..<count {
                labels.append(replies.element(boundBy: index).label)
            }
        }
        return "replies \(count) labels \(labels) notReady \(app.staticTexts["The local model is not ready yet."].exists)"
    }

    private func waitUntilStoppable(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let button = identified(app, "prometh.send")
        while Date() < deadline {
            if button.label == "Stop" || app.staticTexts["· Writing"].exists {
                return true
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    private func assertHiddenChrome(in app: XCUIApplication) {
        let forbidden = [
            "Scheduled", "Dashboard", "Dev", "Models", "Integrations", "Routines",
            "Terminal", "Worktree", "Claude Code", "Codex", "Cursor", "Artifacts", "Nativ"
        ]
        for window in app.windows.allElementsBoundByIndex {
            var found: [String] = []
            collect(window, into: &found)
            for text in found {
                for word in forbidden where text.contains(word) {
                    XCTFail("Forbidden label \(word) in \(text)")
                }
            }
        }
    }

    private func collect(_ element: XCUIElement, into found: inout [String]) {
        if !element.label.isEmpty { found.append(element.label) }
        if let value = element.value as? String, !value.isEmpty { found.append(value) }
        for child in element.children(matching: .any).allElementsBoundByIndex {
            collect(child, into: &found)
        }
    }
}
