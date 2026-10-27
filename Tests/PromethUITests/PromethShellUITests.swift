import XCTest

@MainActor
final class PromethShellUITests: XCTestCase {
    func testPromethShellShowsTheRootWindow() {
        let app = XCUIApplication()
        app.launchArguments = ["--prometh-flags=promethShell"]
        app.launch()
        let root = app.descendants(matching: .any)["prometh.root"]
        XCTAssertTrue(root.waitForExistence(timeout: 15))
    }

    func testNativShellShowsControlPanelAndAWorkingChat() {
        // Welcome + launch splash both hide the ControlPanel AX tree when unset
        // (e.g. after `launch.sh --fresh` wiped the domain).
        for args in [
            ["write", "studio.prometh.Prometh", "hasCompletedWelcome1", "-bool", "YES"],
            ["write", "studio.prometh.Prometh", "hasViewedWorkspaceLaunchSplash2026", "-bool", "YES"],
        ] {
            let write = Process()
            write.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            write.arguments = args
            try? write.run()
            write.waitUntilExit()
        }

        let app = XCUIApplication()
        app.launchArguments = ["--prometh-flags=none"]
        app.launch()

        let newChat = app.descendants(matching: .any).matching(
            NSPredicate(format: "label ==[c] %@", "New chat")
        ).firstMatch
        XCTAssertTrue(newChat.waitForExistence(timeout: 45), "Nativ New chat missing")
        XCTAssertTrue(
            app.descendants(matching: .any)["Models"].waitForExistence(timeout: 45),
            "Nativ Models missing"
        )
        XCTAssertFalse(app.descendants(matching: .any)["prometh.root"].exists)

        let placeholder = app.staticTexts["Message"]
        if placeholder.waitForExistence(timeout: 30) {
            placeholder.click()
        } else {
            let draft = app.textViews.firstMatch
            XCTAssertTrue(draft.waitForExistence(timeout: 15), "Nativ composer missing")
            draft.click()
        }
        app.typeText("Say hello in five words.")
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(waitForReply(in: app, timeout: 180))
    }

    private func waitForReply(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if containsHello(app.staticTexts) || containsHello(app.textViews) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    private func containsHello(_ query: XCUIElementQuery) -> Bool {
        for element in query.allElementsBoundByIndex {
            let label = element.label
            if label.contains("Hello") && !label.contains("Say hello") {
                return true
            }
        }
        return false
    }
}
