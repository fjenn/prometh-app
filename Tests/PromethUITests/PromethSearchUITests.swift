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
        draft.click()
        draft.typeText("What happened in the news today?")
        draft.typeKey(.return, modifierFlags: [])

        let sources = app.staticTexts["Sources"]
        // Cold Safe-model load + SearXNG + local page reads can exceed a minute.
        XCTAssertTrue(sources.waitForExistence(timeout: 180))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Source '")).firstMatch.waitForExistence(timeout: 10))
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
