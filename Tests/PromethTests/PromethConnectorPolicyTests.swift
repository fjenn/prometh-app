import XCTest

final class PromethConnectorPolicyTests: XCTestCase {
    func testReadActionsRunWithoutConsent() {
        for slug in [
            "GITHUB_LIST_REPOSITORIES_FOR_THE_AUTHENTICATED_USER",
            "GITHUB_GET_A_REPOSITORY",
            "GITHUB_SEARCH_ISSUES_AND_PULL_REQUESTS",
            "GMAIL_FETCH_EMAILS",
            "GOOGLEDRIVE_FIND_FILE",
            "OUTLOOK_RETRIEVE_MESSAGE",
            "SLACK_READ_CHANNEL_HISTORY",
            "GITHUB_GET_POST",
            "GITHUB_GET_OR_CREATE_LABEL",
            "APP_DOWNLOAD_DATA",
        ] {
            XCTAssertEqual(PromethConnectorActionPolicy.classify(slug: slug), .read, slug)
            XCTAssertTrue(PromethConnectorActionPolicy.skipsConsent(slug: slug), slug)
        }
    }

    func testOutwardActionsAreWrites() {
        for slug in [
            "GITHUB_CREATE_AN_ISSUE",
            "GMAIL_SEND_EMAIL",
            "GITHUB_DELETE_A_REPOSITORY",
            "GITHUB_MERGE_A_PULL_REQUEST",
            "GITHUB_CREATE_A_PULL_REQUEST",
            "GITHUB_UPDATE_AN_ISSUE",
            "MERCURY_TRANSFER_FUNDS",
            "SLACK_INVITE_USER_TO_CHANNEL",
            "GOOGLEDRIVE_SHARE_FILE",
            "SLACK_POST_MESSAGE",
            "GMAIL_REPLY_TO_THREAD",
            "GITHUB_STAR_A_REPOSITORY_FOR_THE_AUTHENTICATED_USER",
            "GITHUB_WHOAMI",
            "APP_EXPORT",
            "UNKNOWN",
        ] {
            XCTAssertEqual(PromethConnectorActionPolicy.classify(slug: slug), .write, slug)
            XCTAssertFalse(PromethConnectorActionPolicy.skipsConsent(slug: slug), slug)
        }
    }

    func testComposioTagsOverrideTheName() {
        XCTAssertEqual(PromethConnectorActionPolicy.classify(
            slug: "GITHUB_CREATE_REPORT", tags: ["openWorldHint", "readOnlyHint"]), .read)
        XCTAssertEqual(PromethConnectorActionPolicy.classify(
            slug: "GITHUB_ISSUE_THING", tags: ["important", "createHint"]), .write)
        XCTAssertEqual(PromethConnectorActionPolicy.classify(
            slug: "GITHUB_LIST_THEN_WIPE", tags: ["destructiveHint"]), .write)
        XCTAssertEqual(PromethConnectorActionPolicy.classify(
            slug: "GITHUB_STAR_A_REPOSITORY_FOR_THE_AUTHENTICATED_USER", tags: ["updateHint"]), .write)
        XCTAssertEqual(PromethConnectorActionPolicy.classify(slug: "GITHUB_CREATE_AN_ISSUE", tags: []), .write)
        XCTAssertEqual(PromethConnectorActionPolicy.classify(slug: "GITHUB_GET_POST", tags: ["readOnlyHint", "deleteHint"]), .write)

    }

    func testTagsAreFoundInEarlierSearchResults() {
        let search = #"{"ok":true,"items":[{"slug":"GITHUB_CREATE_AN_ISSUE","tags":["createHint"]},{"slug":"GITHUB_LIST_ISSUES","tags":["readOnlyHint"]}]}"#
        let prior: [(toolName: String?, content: String)] = [
            (toolName: "mcp__Connectors__connectors_search", content: search),
            (toolName: "web_search", content: "{}"),
        ]
        XCTAssertEqual(PromethConnectorApproval.tags(for: "GITHUB_LIST_ISSUES", in: prior), ["readOnlyHint"])
        XCTAssertEqual(PromethConnectorApproval.tags(for: "github_create_an_issue", in: prior), ["createHint"])
        XCTAssertNil(PromethConnectorApproval.tags(for: "GMAIL_SEND_EMAIL", in: prior))
        XCTAssertEqual(
            PromethConnectorApproval.actionSlug(from: #"{"tool":" GITHUB_CREATE_AN_ISSUE ","arguments_json":"{}"}"#),
            "GITHUB_CREATE_AN_ISSUE")
        XCTAssertNil(PromethConnectorApproval.actionSlug(from: "not json"))
    }

    func testAlwaysAllowPersistsPerToolkitActionAndResets() throws {
        let key = PromethConnectorActionPolicy.alwaysAllowKey(for: "GITHUB_CREATE_AN_ISSUE")
        XCTAssertEqual(key, "github:GITHUB_CREATE_AN_ISSUE")
        var keys = PromethConnectorAlwaysAllow.adding(key, to: [])
        keys = PromethConnectorAlwaysAllow.adding(key, to: keys)
        keys = PromethConnectorAlwaysAllow.adding("gmail:GMAIL_SEND_EMAIL", to: keys)
        XCTAssertEqual(keys.count, 2)

        var snapshot = Snapshot()
        snapshot.connectorAlwaysAllow = keys
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Persistence(directory: directory).save(snapshot)
        let restored = try XCTUnwrap(Persistence(directory: directory).load())
        XCTAssertEqual(restored.connectorAlwaysAllow, keys)

        PromethConnectorApproval.syncAlwaysAllowed(restored.connectorAlwaysAllow ?? [])
        defer { PromethConnectorApproval.syncAlwaysAllowed([]) }
        XCTAssertTrue(PromethConnectorApproval.isAlwaysAllowed(slug: "GITHUB_CREATE_AN_ISSUE"))
        XCTAssertTrue(PromethConnectorActionPolicy.skipsConsent(
            slug: "GITHUB_CREATE_AN_ISSUE", alwaysAllowed: PromethConnectorApproval.alwaysAllowed))
        XCTAssertFalse(PromethConnectorActionPolicy.skipsConsent(
            slug: "GITHUB_DELETE_A_REPOSITORY", alwaysAllowed: PromethConnectorApproval.alwaysAllowed))

        let reset = PromethConnectorAlwaysAllow.resetting(toolkit: "github", in: keys)
        XCTAssertEqual(reset, ["gmail:GMAIL_SEND_EMAIL"])
        XCTAssertEqual(PromethConnectorAlwaysAllow.keys(for: "gmail", in: reset), ["gmail:GMAIL_SEND_EMAIL"])
        snapshot.connectorAlwaysAllow = reset
        try Persistence(directory: directory).save(snapshot)
        let reloaded = try XCTUnwrap(Persistence(directory: directory).load())
        XCTAssertEqual(reloaded.connectorAlwaysAllow, ["gmail:GMAIL_SEND_EMAIL"])
        PromethConnectorApproval.syncAlwaysAllowed(reloaded.connectorAlwaysAllow ?? [])
        XCTAssertFalse(PromethConnectorApproval.isAlwaysAllowed(slug: "GITHUB_CREATE_AN_ISSUE"))
    }

    func testOlderSavedStateWithoutAlwaysAllowStillDecodes() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(Snapshot())) as? [String: Any])
        object.removeValue(forKey: "connectorAlwaysAllow")
        let data = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNil(try JSONDecoder().decode(Snapshot.self, from: data).connectorAlwaysAllow)
    }

    func testDeclinedResultTellsTheModelNothingRan() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(PromethConnectorActionPolicy.declinedPayload(actionName: "Create an issue", appName: "GitHub").utf8)) as? [String: Any])
        XCTAssertEqual(object["ok"] as? Bool, false)
        XCTAssertEqual(object["executed"] as? Bool, false)
        XCTAssertEqual(object["declined"] as? Bool, true)
        XCTAssertTrue((object["error"] as? String ?? "").contains("Create an issue in GitHub"))
        XCTAssertTrue((object["error"] as? String ?? "").contains("Nothing was sent"))
    }

    func testCardDescriptionIsOnePlainLine() {
        let line = PromethConnectorDescription.line(
            slug: "GITHUB_CREATE_AN_ISSUE",
            argumentsJSON: #"{"tool":"GITHUB_CREATE_AN_ISSUE","arguments_json":"{\"owner\":\"fjenn\",\"repo\":\"prometh-app\",\"title\":\"test\"}"}"#)
        XCTAssertEqual(line, "Create an issue · fjenn/prometh-app · test")
        XCTAssertFalse(line.contains("\n"))
    }

    func testToolkitExtractionAndMetadataOverride() {
        XCTAssertEqual(PromethConnectorActionPolicy.toolkit(from: "GITHUB_GET_POST"), "github")
        XCTAssertEqual(PromethConnectorActionPolicy.toolkit(from: "GOOGLE_DRIVE_LIST_FILES"), "googledrive")
        XCTAssertEqual(PromethConnectorActionPolicy.toolkit(from: "ANY_CREATE_THING", metadata: "actual-app"), "actual-app")
        XCTAssertEqual(PromethConnectorActionPolicy.toolkit(from: "UNKNOWN"), "unknown")
    }

    func testExecuteArgumentParsingAndDetails() throws {
        let action = try XCTUnwrap(PromethConnectorActionPolicy.parse(argumentsJSON:
            #"{"tool":" GMAIL_SEND_EMAIL ","arguments_json":"{\"to\":\"you@example.com\",\"subject\":\"Hello\\nworld\"}"}"#))
        XCTAssertEqual(action.slug, "GMAIL_SEND_EMAIL")
        XCTAssertEqual(action.arguments["to"] as? String, "you@example.com")
        XCTAssertEqual(PromethConnectorDescription.detail(arguments: action.arguments), "you@example.com · Hello world")
        XCTAssertNil(PromethConnectorActionPolicy.parse(argumentsJSON: "not json"))
        XCTAssertNil(PromethConnectorActionPolicy.parse(argumentsJSON: #"{"tool":" "}"#))
    }

    func testDecisionRequiresCardOnlyForUnrememberedWrites() {
        XCTAssertEqual(PromethConnectorActionPolicy.decision(slug: "GITHUB_GET_POST"), .run)
        XCTAssertEqual(PromethConnectorActionPolicy.decision(slug: "GITHUB_CREATE_ISSUE"), .needsCard)
        XCTAssertEqual(PromethConnectorActionPolicy.decision(slug: "UNKNOWN"), .needsCard)
        let hint = PromethConnectorActionPolicy.Hint(tags: ["updateHint"], name: "Update", toolkit: "actual")
        XCTAssertEqual(PromethConnectorActionPolicy.decision(slug: "PREFIX_GET_DATA", hint: hint), .needsCard)
        XCTAssertEqual(PromethConnectorActionPolicy.decision(slug: "PREFIX_GET_DATA", hint: hint,
            alwaysAllowed: ["actual:PREFIX_GET_DATA"]), .run)
        XCTAssertEqual(PromethConnectorActionPolicy.decision(slug: "PREFIX_GET_DATA", hint: hint,
            alwaysAllowed: ["prefix:PREFIX_GET_DATA"]), .needsCard)
    }

    func testHintsFileSuppliesMetadataAndMissingCacheFallsBack() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertNil(PromethConnectorApproval.hint(for: "GITHUB_THING", in: directory))
        let file = PromethConnectorApproval.hintsFile(in: directory)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"GITHUB_THING":{"tags":["readOnlyHint"],"name":"View a thing","toolkit":"github"}}"#.utf8).write(to: file)
        let hint = try XCTUnwrap(PromethConnectorApproval.hint(for: "github_thing", in: directory))
        XCTAssertEqual(PromethConnectorActionPolicy.decision(slug: "GITHUB_THING", hint: hint), .run)
        XCTAssertEqual(PromethConnectorDescription.actionName(slug: "GITHUB_THING", hint: hint), "View a thing")
        XCTAssertNil(PromethConnectorApproval.hint(for: "MISSING", in: directory))
        try Data("broken".utf8).write(to: file)
        XCTAssertNil(PromethConnectorApproval.hint(for: "GITHUB_THING", in: directory))
    }

    func testPendingInlineCardKeepsTheTurnInFlight() {
        let assistant = UUID()
        let snapshots = [
            PromethVisibleReply.TurnSnapshot(id: UUID(), isUser: true, isTool: false, toolStatus: nil),
            PromethVisibleReply.TurnSnapshot(id: assistant, isUser: false, isTool: false, toolStatus: nil),
            PromethVisibleReply.TurnSnapshot(id: UUID(), isUser: false, isTool: true, toolStatus: "awaitingConsent"),
        ]
        let inFlight = PromethVisibleReply.turnInFlight(after: assistant, in: snapshots, requestActive: false)
        XCTAssertTrue(inFlight)
        let row = PromethVisibleReply.row(
            content: "", streaming: false, hasToolCalls: true, laterAnswer: false, turnInFlight: inFlight)
        XCTAssertNotEqual(row.text, PromethVisibleReply.retry)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        XCTAssertFalse(PromethFlags.isOn(.legacyConnectorApprovalSheet, defaults: defaults, arguments: []))
    }
}
