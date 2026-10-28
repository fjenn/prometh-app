import XCTest

final class WebMappingTests: XCTestCase {
    func testPreparationUsesWebStatusSpelling() {
        let value = PromethWebMapping.preparation(Preparation(progress: 0.42, status: .downloading))
        XCTAssertEqual(value["status"] as? String, "downloading")
        XCTAssertEqual(value["progress"] as? Double, 0.42)
    }
    func testConversationUsesWebFieldNamesAndEpochMilliseconds() {
        let chat = Conversation(title: "A chat", mode: .evil, messages: [Message(role: "user", text: "Hi")], updated: Date(timeIntervalSince1970: 123))
        let value = PromethWebMapping.conversation(chat)
        XCTAssertEqual(value["id"] as? String, chat.id.uuidString)
        XCTAssertEqual(value["mode"] as? String, "evil")
        XCTAssertEqual(value["updated"] as? Double, 123000)
        XCTAssertEqual((value["messages"] as? [[String: Any]])?.first?["text"] as? String, "Hi")
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: value))
    }
    func testSourcesAndConnectorIDsSurviveJSON() throws {
        var message = Message(role: "assistant", text: "")
        message.sourceLinks = [SourceLink(title: "Example", url: "https://example.com")]
        message.connectorCard = ConnectorCard(toolkit: "gmail", action: "SEND", summary: "Send a draft", phase: "awaitingConsent")
        let value = PromethWebMapping.extras([message])
        XCTAssertEqual(value.first?["id"] as? String, message.id.uuidString)
        XCTAssertEqual((value.first?["connector"] as? [String: String])?["phase"], "awaitingConsent")
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: value))
    }
    func testBridgeArgumentsRoundTripUntrustedText() throws {
        let text = "\"\\\n</script>\u{2028} 💬"
        let json = try PromethWebMapping.jsonArguments(["id", ["value": text]])
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any])
        XCTAssertEqual((decoded[1] as? [String: String])?["value"], text)
    }
}

extension WebMappingTests {
    func testScopedFilesRejectTraversalAndAbsolutePaths() throws {
        let root = URL(fileURLWithPath: "/tmp/prometh-web-test", isDirectory: true)
        for name in ["", ".", "..", "../private", "/etc/passwd", "nested/file", "nested\\file"] {
            XCTAssertThrowsError(try PromethWebFiles.file(root, name), name)
        }
        XCTAssertEqual(try PromethWebFiles.file(root, "clip-123.mp4").lastPathComponent, "clip-123.mp4")
    }
    func testScopedFilesRejectSymlinkEscape() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("escape").path, withDestinationPath: "/etc/passwd")
        XCTAssertThrowsError(try PromethWebFiles.file(root, "escape"))
    }
}

extension WebMappingTests {
    func testLoadedQwenMapsToQwenInsteadOfPreferredGemma() throws {
        let catalog = try ModelCatalogLoader.bundled()
        let repo = "mlx-community/Qwen3.5-9B-4bit"
        let health: [String: Any] = ["loaded_model": "stale-legacy-value", "loaded_models": ["text_generation": ["model": repo]]]
        let result = try XCTUnwrap(PromethWebMapping.runtimeModel(health: health, catalog: catalog))
        XCTAssertEqual(result["id"] as? String, "safe-qwen9b")
        XCTAssertEqual(result["label"] as? String, "Qwen3.5 9B")
        XCTAssertEqual(result["repo"] as? String, repo)
        XCTAssertEqual(result["sizeGB"] as? Double, Double(try XCTUnwrap(catalog.model(id: "safe-qwen9b")).downloadBytes) / 1e9)
    }
    func testRuntimeMappingHandlesUnloadedUnknownAndLegacyModels() throws {
        let catalog = try ModelCatalogLoader.bundled()
        XCTAssertNil(PromethWebMapping.runtimeModel(health: ["loaded_models": [:], "loaded_model": "image-model"], catalog: catalog))
        XCTAssertNil(PromethWebMapping.runtimeModel(health: [:], catalog: catalog))
        let unknown = try XCTUnwrap(PromethWebMapping.runtimeModel(health: ["loaded_model": "custom/model"], catalog: catalog))
        XCTAssertEqual(unknown["label"] as? String, "custom/model")
        XCTAssertNil(unknown["sizeGB"])
    }
    func testSourceURLsAllowOnlyExternalWebLinks() {
        XCTAssertEqual(PromethWebMapping.externalURL("https://example.com/article?q=test")?.host, "example.com")
        XCTAssertNotNil(PromethWebMapping.externalURL("http://example.com"))
        for raw in ["javascript:alert(1)", "file:///etc/passwd", "prometh-ui://app/", "/relative", "https://user:pass@example.com/"] {
            XCTAssertNil(PromethWebMapping.externalURL(raw), raw)
        }
    }
}
