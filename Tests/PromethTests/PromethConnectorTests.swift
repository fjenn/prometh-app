import XCTest

final class PromethConnectorTests: XCTestCase {
    func testExecuteNamesRequireTheAppToken() throws {
        XCTAssertTrue(PromethConnectorApproval.isExecute("connectors_execute"))
        XCTAssertTrue(PromethConnectorApproval.isExecute("mcp__Connectors__connectors_execute"))
        XCTAssertFalse(PromethConnectorApproval.isExecute("connectors_search"))
        XCTAssertFalse(PromethConnectorApproval.isExecute(nil))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("prometh-connector-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tokenFile = PromethConnectorApproval.tokenFile(in: directory)
        let original = #"{"tool":"GITHUB_LIST_REPOS","arguments_json":"{}","approval_token":"guessed"}"#
        XCTAssertEqual(PromethConnectorApproval.stamp(original, tokenFile: tokenFile), original)

        try PromethConnectorApproval.rewriteToken(at: tokenFile)
        let stamped = try XCTUnwrap(PromethConnectorApproval.stamp(original, tokenFile: tokenFile))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(stamped.utf8)) as? [String: Any])
        let token = try XCTUnwrap(object["approval_token"] as? String)
        XCTAssertFalse(token.isEmpty)
        XCTAssertNotEqual(token, "guessed")
        XCTAssertEqual(object["tool"] as? String, "GITHUB_LIST_REPOS")
        let raw = try FileManager.default.attributesOfItem(atPath: tokenFile.path)[.posixPermissions]
        let mode = (raw as? NSNumber)?.intValue ?? (raw as? Int)
        XCTAssertEqual(mode, 0o600)
        try FileManager.default.removeItem(at: directory)
    }

    func testConnectionLabelsCoverWaitingState() {
        XCTAssertEqual(Connection.connecting.label, "Waiting for sign-in…")
        XCTAssertEqual(Connection.connecting.buttonTitle, "Waiting…")
        XCTAssertEqual(Connection.disconnected.label, "Not connected")
        XCTAssertEqual(Connection.connected.label, "Authorized connection")
        XCTAssertEqual(Connection.expired.label, "Connection expired")
    }

    func testPlanOmitsSecretsAndSkipsAnEmptyBroker() {
        XCTAssertNil(PromethConnectorPlan.make(
            python: "/usr/bin/python3",
            script: "server.py",
            broker: "  ",
            approvalFile: "/tmp/approval",
            installFile: "/tmp/install"
        ))
        let plan = PromethConnectorPlan.make(
            python: "/usr/bin/python3",
            script: "server.py",
            broker: "http://127.0.0.1:9",
            approvalFile: "/tmp/approval",
            installFile: "/tmp/install"
        )
        XCTAssertEqual(plan?.catalogID, "prometh.composio")
        XCTAssertEqual(plan?.environment, [:])
        XCTAssertEqual(plan?.arguments.contains("--broker"), true)
        XCTAssertFalse(plan?.arguments.contains("COMPOSIO_API_KEY") ?? true)

        let direct = PromethConnectorPlan.make(
            python: "/usr/bin/python3",
            script: "server.py",
            broker: "  ",
            approvalFile: "/tmp/approval",
            installFile: "/tmp/install",
            direct: true
        )
        XCTAssertEqual(direct?.environment, [:])
        XCTAssertEqual(direct?.arguments.contains("--broker"), false)
        XCTAssertEqual(direct?.arguments.contains("--install-file"), true)
    }
}
