import XCTest

/// Live search answers need the prepared Chat model and a network. Linux cannot
/// launch the app. Run this with the command in Docs/progress/M4/REPORT.md.
@MainActor
final class PromethSearchUITests: XCTestCase {
    func testNewsAnswerShowsAtLeastTwoSourceCards() {
        let app = XCUIApplication()
        app.launchArguments = ["--prometh-flags=promethShell"]
        app.launch()

        let draft = app.textViews["prometh.draft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 30))
        // Clear any restored draft from a prior launch so typeText has focus.
        draft.click()
        app.typeKey("a", modifierFlags: [.command])
        app.typeKey(.delete, modifierFlags: [])
        draft.click()
        app.typeText("What happened in the news today?")
        app.typeKey(.return, modifierFlags: [])

        let sources = app.staticTexts["Sources"]
        // Cold Safe-model load + SearXNG + local page reads can exceed a minute.
        XCTAssertTrue(sources.waitForExistence(timeout: 180))
        let cards = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Source '"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        let deadline = Date().addingTimeInterval(30)
        var count = cards.count
        while Date() < deadline, count < 2 {
            Thread.sleep(forTimeInterval: 0.5)
            count = cards.count
        }
        XCTAssertGreaterThanOrEqual(count, 2, "News answers need several distinct Sources, got \(count)")
    }

    func testAdvancedDoesNotRequireASearchKey() {
        let app = XCUIApplication()
        app.launchArguments = ["--prometh-flags=promethShell"]
        app.launch()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 30))
        app.buttons["Settings"].click()
        let advanced = app.descendants(matching: .any)["prometh.settings.Advanced"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        advanced.click()
        XCTAssertTrue(app.buttons["SearXNG source code"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Connect your apps"].exists)
    }
}
