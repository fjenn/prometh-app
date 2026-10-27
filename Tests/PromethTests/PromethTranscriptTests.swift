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
            PromethConversationTitle.title(
                custom: nil,
                preserveStored: false,
                stored: "",
                prompts: ["Show markdown: one **bold** word, three fruit bullets"]
            ),
            "Show markdown: one bold word, three fruit bullets"
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

    func testStoredAndCustomTitlesAlsoStripMarkdown() {
        XCTAssertEqual(
            PromethConversationTitle.title(
                custom: nil,
                preserveStored: true,
                stored: "Reply with: a **bold** word",
                prompts: ["ignored"]
            ),
            "Reply with: a bold word"
        )
        XCTAssertEqual(
            PromethConversationTitle.title(
                custom: "Use **bold** title",
                preserveStored: false,
                stored: "Other",
                prompts: ["prompt"]
            ),
            "Use bold title"
        )
    }

    func testToolResultSanitizerHidesAttachmentIDs() {
        let raw = """
        {"ok":true,"operation":"edit","images":[{"attachment_id":"620E9990-6640-4D5A-A003-C25DDCDE3202","width":512,"height":512,"seed":1}]}
        """
        let scrubbed = PromethToolResultSanitizer.modelFacing(toolName: "edit_image", content: raw)
        XCTAssertFalse(scrubbed.contains("620E9990"))
        XCTAssertFalse(scrubbed.contains("attachment_id"))
        XCTAssertTrue(scrubbed.contains("ok"))
        XCTAssertTrue(scrubbed.lowercased().contains("version") || scrubbed.lowercased().contains("edited"))
    }

    func testVisibleReplyScrubsAttachmentIDs() {
        let leaked = "I have edited the picture to depict the scene at dusk. The new version is available with the attachment ID 620E9990-6640-4D5A-A003-C25DDCDE3202."
        let scrubbed = PromethTranscript.scrubInternals(leaked)
        XCTAssertFalse(scrubbed.contains("620E9990"))
        XCTAssertFalse(scrubbed.lowercased().contains("attachment id"))
        XCTAssertTrue(scrubbed.localizedCaseInsensitiveContains("dusk"))
    }

    func testVisibleReplyScrubsEmptyCodeSpanLeftByAttachmentID() {
        // Exact judge-visible artifact from final-image-edit.png after UUID scrub.
        let leaked = "I have edited the picture to depict the scene at dusk. ``."
        XCTAssertEqual(
            PromethTranscript.scrubInternals(leaked),
            "I have edited the picture to depict the scene at dusk."
        )
        let backticked = "I have edited the picture to depict the scene at dusk. `620E9990-6640-4D5A-A003-C25DDCDE3202`."
        XCTAssertEqual(
            PromethTranscript.scrubInternals(backticked),
            "I have edited the picture to depict the scene at dusk."
        )
        let usingPhrase = "I have generated a cinematic photograph of a glass house above the Atlantic at sunrise. You can view it using the attachment ID `254135D7-015D-422A-8530-7443BF111A6A`."
        XCTAssertEqual(
            PromethTranscript.scrubInternals(usingPhrase),
            "I have generated a cinematic photograph of a glass house above the Atlantic at sunrise."
        )
        let danglingCite = "Iran news [2]. These summaries are drawn from the reports available on and."
        XCTAssertEqual(
            PromethTranscript.scrubInternals(danglingCite),
            "Iran news [2]."
        )
        let withEmptyParen = "Edited the picture ( ). Done."
        XCTAssertEqual(
            PromethTranscript.scrubInternals(withEmptyParen),
            "Edited the picture. Done."
        )
    }

    func testScrubPreservesMarkdownListsAndFencedCode() {
        // Exact shape of the judge chat prompt / reply that collapsed in final-chat.png
        // when scrubInternals treated newlines as collapsible whitespace.
        let modelReply = """
        Here is a **bold** word.

        * apple
        * banana
        * cherry

        ```python
        print("hello")
        ```
        """
        let scrubbed = PromethTranscript.scrubInternals(modelReply)
        XCTAssertTrue(scrubbed.contains("**bold**"), scrubbed)
        XCTAssertFalse(
            scrubbed.contains("word. * apple"),
            "Intro must stay on its own line before the first bullet: \(scrubbed)"
        )
        XCTAssertTrue(scrubbed.contains("\n* apple\n"), scrubbed)
        XCTAssertTrue(scrubbed.contains("\n* banana\n"), scrubbed)
        XCTAssertTrue(scrubbed.contains("\n* cherry\n"), scrubbed)
        XCTAssertTrue(scrubbed.contains("```python\nprint(\"hello\")\n```"), scrubbed)
        XCTAssertFalse(
            scrubbed.contains("cherry ```python") || scrubbed.contains("cherry Use print"),
            "Fence must not glue onto the last bullet: \(scrubbed)"
        )

        let listPrepared = PromethReplyMarkup.lists(scrubbed)
        XCTAssertFalse(listPrepared.contains("* apple"), listPrepared)
        XCTAssertTrue(listPrepared.contains("• apple"), listPrepared)
        XCTAssertTrue(listPrepared.contains("• banana"), listPrepared)
        XCTAssertTrue(listPrepared.contains("• cherry"), listPrepared)

        // Fenced blocks are split out before markup; after scrub they must still
        // separate cleanly on ``` so Workspace can render a real code card.
        let fenceParts = scrubbed.components(separatedBy: "```")
        XCTAssertEqual(fenceParts.count, 3, "open + body + close: \(fenceParts)")
        guard fenceParts.count == 3 else { return }
        XCTAssertTrue(fenceParts[1].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("python"))
        XCTAssertTrue(fenceParts[1].contains("print(\"hello\")"))
    }

    func testScrubAndCitationRemapKeepListBreaksAndDistinctChips() {
        let modelReply = """
        Here are today's headlines:

        * The **Civilian** hardship in Oleshky continues, with residents surviving by eating weeds [1]
        * An Amnesty International report documents further abuses [2]
        * Peace talks advanced in Cambodia [1]

        ```python
        print("hello")
        ```
        """
        // Attachment-ID leftovers sometimes trail a news reply after tool scrubbing.
        let withLeak = modelReply + " The new version is available with the attachment ID 620E9990-6640-4D5A-A003-C25DDCDE3202."
        let scrubbed = PromethTranscript.scrubInternals(withLeak)
        XCTAssertFalse(scrubbed.contains("620E9990"), scrubbed)
        XCTAssertFalse(scrubbed.contains("word. *") || scrubbed.contains("headlines: *"), scrubbed)
        XCTAssertTrue(scrubbed.contains("\n* The **Civilian**"), scrubbed)
        XCTAssertTrue(scrubbed.contains("```python\nprint(\"hello\")\n```"), scrubbed)

        let sources = [
            CitationRemapper.Source(
                index: 1,
                title: "World | Latest News & Updates | BBC News",
                url: "https://www.bbc.com/news/world",
                body: "Civilian hardship in Russian-occupied Oleshky continues with residents surviving by eating weeds. Peace talks advanced in Cambodia.",
                snippet: "Oleshky weeds Cambodia"
            ),
            CitationRemapper.Source(
                index: 2,
                title: "World News: Top & Breaking World News Today | AP News",
                url: "https://apnews.com/",
                body: "An Amnesty International report documents further abuses across the region.",
                snippet: "Amnesty International report"
            ),
        ]
        let remapped = CitationRemapper.rewrite(scrubbed, sources: sources)
        let civilian = remapped.split(separator: "\n").first { $0.contains("Civilian") }.map(String.init) ?? ""
        let amnesty = remapped.split(separator: "\n").first { $0.contains("Amnesty") }.map(String.init) ?? ""
        let cambodia = remapped.split(separator: "\n").first { $0.contains("Cambodia") }.map(String.init) ?? ""
        XCTAssertTrue(civilian.contains("[1]"), "Oleshky claim → BBC: \(civilian)")
        XCTAssertTrue(amnesty.contains("[2]"), "Amnesty claim → AP: \(amnesty)")
        XCTAssertTrue(cambodia.contains("[1]"), "Cambodia claim → BBC: \(cambodia)")
        XCTAssertEqual(CitationMarkup.citedIndices(in: remapped), [1, 2])

        let rendered = PromethReplyMarkup.attributed(
            markdown: PromethReplyMarkup.lists(
                remapped.components(separatedBy: "```").first ?? remapped
            ),
            cited: [1, 2]
        )
        let plain = String(rendered.characters)
        XCTAssertFalse(plain.contains("* The"), "Raw list marker must not survive: \(plain)")
        XCTAssertTrue(plain.contains("•"), plain)
        let destinations = Set(rendered.runs.compactMap { $0.link?.absoluteString })
        XCTAssertTrue(destinations.contains("prometh-cite://1"), "\(destinations)")
        XCTAssertTrue(destinations.contains("prometh-cite://2"), "\(destinations)")
    }

    func testComposerClearsAfterSendButProtectsAXPaste() {
        // After send: binding goes from the sent draft to empty while focused.
        XCTAssertTrue(
            ComposerDraftSync.shouldApply(
                binding: "",
                view: "Trim that clip from 1.0 to 3.0 seconds and keep the original.",
                editing: true,
                conversationChanged: false,
                lastBound: "Trim that clip from 1.0 to 3.0 seconds and keep the original."
            )
        )
        // AX/paste race: empty binding must not wipe view text that was never bound.
        XCTAssertFalse(
            ComposerDraftSync.shouldApply(
                binding: "",
                view: "pasted via accessibility",
                editing: true,
                conversationChanged: false,
                lastBound: ""
            )
        )
        // Non-empty binding still applies while focused.
        XCTAssertTrue(
            ComposerDraftSync.shouldApply(
                binding: "hello",
                view: "",
                editing: true,
                conversationChanged: false,
                lastBound: ""
            )
        )
    }
}
