import XCTest



@MainActor
final class VoiceLatencyBenchmarkTests: XCTestCase {
    func testExportRealHarnessVoiceBenchmarkRequests() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let chat = ChatViewModel(sessionDirectory: temporary.appendingPathComponent("Chat"))
        chat.createSession()
        var settings = NativSettings()
        settings.languageModelID = "mlx-community/Qwen3.5-9B-4bit"
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("build/VoiceLatencyBenchmark")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for voice in [false, true] {
            let request = try XCTUnwrap(chat.voiceLatencyBenchmarkRequest(settings: settings, voiceTurn: voice))
            XCTAssertFalse(request.tools?.isEmpty ?? true)
            let system = try XCTUnwrap(request.messages.first?.content)
            if case .text(let text) = system {
                XCTAssertEqual(text.contains(ChatWorkToolRegistry.sessionPrompt), !voice)
                XCTAssertTrue(text.contains(PromethPrompts.persona(mode: "Safe Mode")))
            }
            XCTAssertFalse(request.tools?.contains { $0.function.name == "chat_work" } ?? true)
            XCTAssertEqual(request.enableThinking, false)
            XCTAssertEqual(request.maxTokens, voice ? 300 : 2048)
            try JSONEncoder().encode(request).write(to: directory.appendingPathComponent(voice ? "after.json" : "before.json"))
        }
    }
}
