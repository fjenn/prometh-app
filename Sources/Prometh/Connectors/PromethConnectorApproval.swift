import Foundation

/// Approval token and launch plan for the connectors MCP server.
/// The token file is mode 0600. The model never learns the value: the app
/// overwrites `approval_token` only after the user approves.
enum PromethConnectorApproval {
    static let catalogID = "prometh.composio"
    static let keychainService = "studio.prometh.Prometh.connectors"
    static let executeTool = "connectors_execute"

    static func isExecute(_ name: String?) -> Bool {
        guard let name else { return false }
        return name == executeTool || name.hasSuffix("__" + executeTool)
    }

    static func tokenFile(in support: URL) -> URL {
        support.appendingPathComponent("connectors/approval-token", isDirectory: false)
    }

    static func installFile(in support: URL) -> URL {
        support.appendingPathComponent("connectors/install-id", isDirectory: false)
    }

    /// Returns `arguments` unchanged when the token file is missing or empty.
    static func stamp(_ arguments: String?, tokenFile: URL) -> String? {
        guard let raw = try? String(contentsOf: tokenFile, encoding: .utf8) else { return arguments }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return arguments }
        var object: [String: Any] = [:]
        if let arguments,
           let data = arguments.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            object = parsed
        }
        object["approval_token"] = token
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            return arguments
        }
        return text
    }

    static func rewriteToken(at url: URL) throws {
        let token = UUID().uuidString
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data((token + "\n").utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: url.path
        )
    }
}

struct PromethConnectorConsent: Identifiable, Equatable {
    let id: UUID
}

struct PromethConnectorPlan: Equatable {
    var command: String
    var arguments: [String]
    var environment: [String: String]
    var catalogID: String

    /// A blank broker registers nothing unless `direct` is true. Direct mode
    /// calls Composio from the stdio server, which reads the key itself.
    /// The key is never an argument or an environment value.
    static func make(
        python: String,
        script: String,
        broker: String,
        approvalFile: String,
        installFile: String,
        direct: Bool = false
    ) -> PromethConnectorPlan? {
        let trimmed = broker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || direct else { return nil }
        var arguments = [
            script,
            "--approval-file", approvalFile,
            "--install-file", installFile,
        ]
        if !trimmed.isEmpty {
            arguments.append(contentsOf: ["--broker", trimmed])
        }
        return PromethConnectorPlan(
            command: python,
            arguments: arguments,
            environment: [:],
            catalogID: PromethConnectorApproval.catalogID
        )
    }
}
