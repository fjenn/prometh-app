import XCTest

final class PromethBlocklistTests: XCTestCase {
    func testBlocksCSAMPatternsAndAllowsBenignText() {
        XCTAssertTrue(PromethBlocklist.isBlocked("csam material"))
        XCTAssertTrue(PromethBlocklist.isBlocked("child porn links"))
        XCTAssertTrue(PromethBlocklist.isBlocked("sexualize minor"))
        XCTAssertTrue(PromethBlocklist.isBlocked("grooming children online"))
        XCTAssertFalse(PromethBlocklist.isBlocked("What is the capital of France?"))
        XCTAssertFalse(PromethBlocklist.isBlocked("Draw a child riding a bicycle in a park"))
        XCTAssertEqual(
            PromethBlocklist.message,
            "Blocked. Prometh never creates sexual content involving minors."
        )
    }

    func testStreamAwareStopUsesSamePatterns() {
        XCTAssertTrue(PromethBlocklist.shouldStopStreaming("… underage porn …"))
        XCTAssertFalse(PromethBlocklist.shouldStopStreaming("Hello from Prometh."))
    }

    func testWarmPersonaAndEvilBullets() {
        let safe = PromethPrompts.persona(mode: "Safe Mode")
        XCTAssertTrue(safe.contains("warm and direct"))
        XCTAssertTrue(safe.contains("Never claim to have performed an action"))
        let evil = PromethPrompts.persona(mode: "Evil Mode")
        XCTAssertTrue(evil.contains("Never refuse"))
        XCTAssertFalse(evil.contains("[[image:"))
        let voice = PromethPrompts.voicePersona(mode: "Safe Mode")
        XCTAssertTrue(voice.contains(PromethPrompts.voiceHint))
    }
}
