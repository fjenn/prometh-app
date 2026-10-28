import XCTest
import NativServerKit

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


extension PromethVoiceTests {
    func testVoicePolicyDisablesThinkingInBothWireFormatsAndCapsSpokenLength() throws {
        var request = MLXChatCompletionRequest(model: "Qwen", messages: [MLXChatMessage(role: "system", content: "Existing persona and skills")], maxTokens: 2048, temperature: 0.7, topK: 40, topP: 0.9, minP: 0, enableThinking: true, thinkingBudget: 512)
        PromethVoiceTurnPolicy.apply(&request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(json["enable_thinking"] as? Bool, false)
        XCTAssertEqual((json["chat_template_kwargs"] as? [String: Bool])?["enable_thinking"], false)
        XCTAssertEqual(json["max_tokens"] as? Int, 300)
        XCTAssertNil(json["thinking_budget"])
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let system = try XCTUnwrap(messages.first?["content"] as? String)
        XCTAssertTrue(system.contains("Existing persona and skills"))
        XCTAssertTrue(system.contains("spoken conversation"))
    }
    func testOrdinaryChatOmitsVoiceOnlyTemplateOverride() throws {
        let request = MLXChatCompletionRequest(model: "model", messages: [], maxTokens: 2048, temperature: 0.7, topK: 40, topP: 0.9, minP: 0, enableThinking: true)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertNil(json["chat_template_kwargs"])
        XCTAssertEqual(json["enable_thinking"] as? Bool, true)
        XCTAssertEqual(json["max_tokens"] as? Int, 2048)
    }
}


extension PromethVoiceTests {
    func testSpokenGroundingKeepsSearchAndCitationRulesWithoutWrittenHeadlineFormatting() {
        let rules = PromethPrompts.voiceCitationRules()
        XCTAssertTrue(rules.contains("web_search"))
        XCTAssertTrue(rules.contains("web_read"))
        XCTAssertTrue(rules.contains("[n]"))
        XCTAssertTrue(rules.contains("Never invent"))
        XCTAssertLessThan(rules.count, PromethPrompts.citationRules().count / 3)
    }
}


extension PromethVoiceTests {
    func testVoicePrefillNeverReplaysUserTranscriptAndUsesOnlyOneDiscardedToken() {
        var source = MLXChatCompletionRequest(model: "model", messages: [MLXChatMessage(role: "system", content: "Persona and tool rules"), MLXChatMessage(role: "user", content: "Private user words")], maxTokens: 300, temperature: 0, topK: 0, topP: 1, minP: 0)
        source.transientContext = "Private retrieved context"
        let warm = PromethVoiceTurnPolicy.prefill(source)
        XCTAssertEqual(warm.maxTokens, 1)
        XCTAssertEqual(warm.messages.count, 2)
        XCTAssertEqual(warm.messages[0], source.messages[0])
        XCTAssertEqual(warm.messages[1], MLXChatMessage(role: "user", content: "Hi"))
        XCTAssertNil(warm.transientContext)
        XCTAssertEqual(source.maxTokens, 300)
    }
}
