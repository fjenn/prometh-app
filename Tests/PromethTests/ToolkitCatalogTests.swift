import XCTest
import AppKit

final class ToolkitCatalogTests: XCTestCase {
    private let payload = Data(#"{"ok":true,"items":[{"slug":"github","name":"GitHub","meta":{"description":"Repositories and issues","logo":"https://example.com/github.png","categories":[{"id":"dev","name":"developer tools"}]}},{"slug":"gmail","name":"Gmail","meta":{"description":"Email","categories":[{"name":"email"}]}},{"slug":"github","name":"GitHub","meta":{"description":"Repositories and issues","logo":"https://example.com/github.png","categories":[{"name":"developer tools"}]}}]}"#.utf8)

    func testParsingDeduplicatesAndKeepsMetadata() throws {
        let catalog = try ToolkitCatalog.parse(payload)
        XCTAssertEqual(catalog.items.map(\.slug), ["github", "gmail"])
        XCTAssertEqual(catalog.items.first?.logo?.absoluteString, "https://example.com/github.png")
        XCTAssertEqual(catalog.categories, ["developer tools", "email"])
    }
    func testSearchMatchesAllWordsAcrossMetadataAndCategory() throws {
        let catalog = try ToolkitCatalog.parse(payload)
        XCTAssertEqual(catalog.filtered(search:"  GITHUB issues  ").map(\.slug), ["github"])
        XCTAssertEqual(catalog.filtered(search:"repositories",category:"email"), [])
        XCTAssertEqual(catalog.filtered(search:"",category:"email").map(\.slug), ["gmail"])
        XCTAssertEqual(catalog.filtered(search:"developer").map(\.slug), ["github"])
        XCTAssertTrue(catalog.filtered(search:"not-a-plugin").isEmpty)
    }
    func testInvalidAndFailedResponsesDoNotBecomeAnEmptySuccess() {
        for raw in ["{}", "[]", #"{"items":[]}"#, #"{"items":[{"slug":"broken"}]}"#, #"{"ok":false,"error":"composio status 401"}"#] {
            XCTAssertThrowsError(try ToolkitCatalog.parse(Data(raw.utf8)))
        }
    }
    func testCacheRoundTripFreshnessAndCorruption() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:directory) }
        let url = directory.appendingPathComponent("catalog.json")
        let now = Date()
        let catalog = try ToolkitCatalog.parse(payload,at:now)
        try catalog.writeCache(at:url)
        XCTAssertEqual(try ToolkitCatalog.readCache(at:url),catalog)
        XCTAssertTrue(catalog.isFresh(at:now.addingTimeInterval(60)))
        XCTAssertFalse(catalog.isFresh(at:now.addingTimeInterval(86400)))
        XCTAssertFalse(catalog.isFresh(at:now.addingTimeInterval(-1)))
        try Data("corrupt".utf8).write(to:url)
        XCTAssertThrowsError(try ToolkitCatalog.readCache(at:url))
    }
    func testInlineEditKeysPreserveNewlinesModifiersAndInputMethods() {
        XCTAssertEqual(InlineEditKeys.action(keyCode:53,modifiers:[],markedText:false),.cancel)
        XCTAssertEqual(InlineEditKeys.action(keyCode:36,modifiers:.command,markedText:false),.send)
        XCTAssertEqual(InlineEditKeys.action(keyCode:76,modifiers:[.command,.numericPad],markedText:false),.send)
        for flags: NSEvent.ModifierFlags in [[], .shift, .option, [.command,.shift], .control] {
            XCTAssertEqual(InlineEditKeys.action(keyCode:36,modifiers:flags,markedText:false),.text)
        }
        XCTAssertEqual(InlineEditKeys.action(keyCode:36,modifiers:.command,markedText:true),.text)
        XCTAssertEqual(InlineEditKeys.action(keyCode:53,modifiers:[],markedText:true),.text)
    }
}
