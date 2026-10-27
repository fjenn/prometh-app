import XCTest

final class PromethTranscriptTests: XCTestCase {
    func testBoldAndBulletsAreNotLeftAsRawMarkdown() {
        let blocks = PromethMarkdown.blocks(in: "**bold** text\n- one\n* two")
        XCTAssertEqual(
            blocks,
            [
                .paragraph([.strong("bold"), .text(" text")]),
                .bullet([.text("one")]),
                .bullet([.text("two")]),
            ]
        )
        XCTAssertFalse(String(describing: blocks).contains("**"))
        XCTAssertFalse(String(describing: blocks).contains("- one"))
    }

    func testInlineCodeDropsTheBackticks() {
        let blocks = PromethMarkdown.blocks(in: "Use `code` here")
        XCTAssertEqual(blocks, [.paragraph([.text("Use "), .code("code"), .text(" here")])])
    }

    func testEmptyNewsReplyUsesSearchSnippets() {
        let body = """
        {"results":[{"title":"Day in the news","url":"https://example.com/a","snippet":"Markets rose."}]}
        <search_results>
        <result index="1" title="Day in the news" url="https://example.com/a" />
        </search_results>
        """
        let hits = PromethTranscript.searchHits(from: [body])
        XCTAssertEqual(hits, [PromethSearchHit(title: "Day in the news", snippet: "Markets rose.")])
        let text = PromethTranscript.visibleText(
            content: "",
            reasoning: "",
            hasToolCalls: false,
            isStreaming: false,
            isLastAssistantInTurn: true,
            searchHits: hits
        )
        XCTAssertEqual(
            text,
            """
            Day in the news [1]
            Markets rose.
            """
        )
        XCTAssertNotEqual(text?.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    func testEmptyToolCarrierIsHiddenWhenAnAnswerFollows() {
        XCTAssertNil(PromethTranscript.visibleText(
            content: "",
            reasoning: "",
            hasToolCalls: true,
            isStreaming: false,
            isLastAssistantInTurn: false,
            searchHits: [PromethSearchHit(title: "Day in the news", snippet: "Markets rose.")]
        ))
    }

    func testReasoningFillsAFinishedEmptyReply() {
        XCTAssertEqual(
            PromethTranscript.visibleText(
                content: "  ",
                reasoning: "Here is the news.",
                hasToolCalls: false,
                isStreaming: false,
                isLastAssistantInTurn: true,
                searchHits: []
            ),
            "Here is the news."
        )
    }

    func testFinishedNewsTurnWithoutAFollowUpStillShowsSnippets() {
        let hits = [PromethSearchHit(title: "Bulletin", snippet: "The vote passed.")]
        let text = PromethTranscript.visibleText(
            content: "",
            reasoning: "",
            hasToolCalls: true,
            isStreaming: false,
            isLastAssistantInTurn: true,
            searchHits: hits
        )
        XCTAssertEqual(text, "Bulletin [1]\nThe vote passed.")
    }

    func testTitleUsesOnlyTheFirstPrompt() {
        let title = PromethConversationTitle.title(
            custom: nil,
            preserveStored: false,
            stored: "",
            prompts: [
                "What happened in the news today?",
                "What happened in the news yesterday?",
            ]
        )
        XCTAssertEqual(title, "What happened in the news today?")
        XCTAssertFalse(title.contains("yesterday"))
    }

    func testJammedSecondPromptIsCutAtTheQuestionMark() {
        let title = PromethConversationTitle.title(
            custom: nil,
            preserveStored: false,
            stored: "",
            prompts: ["What happened in the news today?What happened in the news tomorrow?"]
        )
        XCTAssertEqual(title, "What happened in the news today?")
    }

    func testCustomTitleWinsOverThePrompt() {
        XCTAssertEqual(
            PromethConversationTitle.title(
                custom: "Morning brief",
                preserveStored: false,
                stored: "Other",
                prompts: ["What happened in the news today?What happened"]
            ),
            "Morning brief"
        )
    }

    func testGeneratedTitleStripsMarkdownMarkers() {
        XCTAssertEqual(
            PromethConversationTitle.title(
                custom: nil,
                preserveStored: false,
                stored: "",
                prompts: ["Use **bold** and `code` here"]
            ),
            "Use bold and code here"
        )
        XCTAssertEqual(
            PromethConversationTitle.stripMarkdown("# Heading with __emphasis__"),
            "Heading with emphasis"
        )
        let truncated = PromethConversationTitle.title(
            custom: nil,
            preserveStored: false,
            stored: "",
            prompts: [
                "Use **bold markers that would otherwise survive truncation mid-token**",
            ]
        )
        XCTAssertFalse(truncated.contains("*"))
        XCTAssertFalse(truncated.contains("`"))
        XCTAssertFalse(truncated.contains("#"))
    }
}
