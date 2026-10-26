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
        let app = XCUIApplication()
        app.launchArguments = ["--prometh-flags=none"]
        app.launch()

        XCTAssertTrue(app.buttons["New chat"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Models"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.descendants(matching: .any)["prometh.root"].exists)

        let placeholder = app.staticTexts["Message"]
        XCTAssertTrue(placeholder.waitForExistence(timeout: 30))

        placeholder.click()
        app.typeText("Say hello in five words.")
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(waitForReply(in: app, timeout: 120))
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
