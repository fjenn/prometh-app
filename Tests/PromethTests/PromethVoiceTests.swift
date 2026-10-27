import XCTest

final class PromethVoiceTests: XCTestCase {
    func testWhisperReplacesAnEmptyOrParakeetSelection() {
        XCTAssertEqual(PromethVoiceDefaults.speechModel(current: nil), PromethVoiceDefaults.whisperModelID)
        XCTAssertEqual(
            PromethVoiceDefaults.speechModel(current: PromethVoiceDefaults.parakeetModelID),
            PromethVoiceDefaults.whisperModelID
        )
        XCTAssertEqual(PromethVoiceDefaults.speechModel(current: "custom/model"), "custom/model")
        XCTAssertEqual(PromethVoiceDefaults.pocketVoice, "alba")
        let body = PromethVoiceDefaults.ttsBody(text: "The answer is four.")
        XCTAssertEqual(body["voice"], "alba")
        XCTAssertEqual(body["model"], PromethVoiceDefaults.pocketRepo)
        XCTAssertEqual(PromethVoiceDefaults.selfTestAnswer(for: "What is two plus two?"), nil)
    }

    @MainActor
    func testInterruptLeavesListeningInsteadOfSpeaking() {
        let voice = PromethVoice()
        voice.open()
        voice.readAloud("The answer is four.")
        XCTAssertEqual(voice.phase, "Speaking")
        voice.interrupt()
        XCTAssertEqual(voice.phase, "Listening")
    }
}
