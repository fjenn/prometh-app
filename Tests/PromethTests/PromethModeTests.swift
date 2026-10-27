import XCTest

final class PromethModeTests: XCTestCase {
    func testSixteenGibibytesUnloadsTheOtherModel() {
        let limit = PromethMemoryPolicy.limitBytes
        XCTAssertEqual(limit, 17_179_869_184)
        XCTAssertTrue(PromethMemoryPolicy.shouldUnloadOther(limit))
        XCTAssertTrue(PromethMemoryPolicy.shouldUnloadOther(8 * 1024 * 1024 * 1024))
        XCTAssertFalse(PromethMemoryPolicy.shouldUnloadOther(limit + 1))
    }

    func testInterruptedCopyMatchesTheProductString() {
        XCTAssertEqual(
            PromethInterruptedError.llamaUnavailable.errorDescription,
            "Something interrupted that. Your request is saved. Try again when you're ready."
        )
    }

    func testMenuChoiceOpensTheNextChatInThatMode() {
        XCTAssertEqual(
            PromethModeTable.openingMode(existingChats: 2, defaultMode: "Safe Mode", requested: "Evil Mode"),
            "Evil Mode"
        )
        XCTAssertEqual(
            PromethModeTable.openingMode(existingChats: 0, defaultMode: "Evil Mode", requested: nil),
            "Evil Mode"
        )
        XCTAssertEqual(
            PromethModeTable.openingMode(existingChats: 3, defaultMode: "Evil Mode", requested: nil),
            "Safe Mode"
        )
        XCTAssertEqual(
            PromethModeTable.displayed(chatMode: nil, requested: "Evil Mode", defaultMode: "Safe Mode"),
            "Evil Mode"
        )
        XCTAssertEqual(
            PromethModeTable.displayed(chatMode: "Safe Mode", requested: "Evil Mode", defaultMode: "Evil Mode"),
            "Safe Mode"
        )
    }

    func testOnlyTheOpeningChatInheritsEvil() {
        XCTAssertEqual(
            PromethModeTable.modeForNewChat(existingChats: 0, defaultMode: "Evil Mode"),
            "Evil Mode"
        )
        XCTAssertEqual(
            PromethModeTable.modeForNewChat(existingChats: 2, defaultMode: "Evil Mode"),
            "Safe Mode"
        )
        XCTAssertEqual(
            PromethModeTable.modeForNewChat(existingChats: 0, defaultMode: "Safe Mode"),
            "Safe Mode"
        )
    }

    func testEvilDownloadIsFivePointSixThreeGigabytes() throws {
        let catalog = try ModelCatalogLoader.bundled()
        let evil = try XCTUnwrap(catalog.model(id: "evil"))
        XCTAssertEqual(evil.name, "Qwen3.5 9B Heretic v2 · Evil")
        XCTAssertEqual(evil.downloadBytes, 5_627_044_800)
        XCTAssertEqual(CatalogSize.decimalGigabytes(evil.downloadBytes), "5.63 GB")
        let projector = try XCTUnwrap(catalog.model(id: "evil-vision-projector"))
        XCTAssertFalse(projector.enabled)
    }
}
