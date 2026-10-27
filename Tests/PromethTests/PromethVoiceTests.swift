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

    func testSilenceCannotStartATurnAndClickIsRejected() {
        var detector = PromethVoiceDetector()
        for i in 1...100 {
            XCTAssertFalse(detector.step(rms: i == 20 ? 0.1 : 0.001, elapsed: Double(i) * 0.05))
        }
        XCTAssertFalse(detector.heardSpeech)
    }

    func testSpeechEndsAfterSevenHundredMillisecondsOfSilence() {
        var detector = PromethVoiceDetector()
        for i in 1...20 { XCTAssertFalse(detector.step(rms: 0.05, elapsed: Double(i) * 0.05)) }
        XCTAssertTrue(detector.heardSpeech)
        XCTAssertFalse(detector.step(rms: 0.001, elapsed: 1.65))
        XCTAssertTrue(detector.step(rms: 0.001, elapsed: 1.71))
    }

    func testSileroRejectsRoomNoiseAndEndsSpeech() {
        var detector = PromethVoiceDetector()
        for i in 1...30 { XCTAssertFalse(detector.step(rms: 0.04, elapsed: Double(i) * 0.032, probability: 0.01)) }
        XCTAssertFalse(detector.heardSpeech)
        for i in 31...50 { XCTAssertFalse(detector.step(rms: 0.06, elapsed: Double(i) * 0.032, probability: 0.9)) }
        XCTAssertTrue(detector.heardSpeech)
        XCTAssertFalse(detector.step(rms: 0.04, elapsed: 2.2, probability: 0.01))
        XCTAssertTrue(detector.step(rms: 0.04, elapsed: 2.31, probability: 0.01))
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
