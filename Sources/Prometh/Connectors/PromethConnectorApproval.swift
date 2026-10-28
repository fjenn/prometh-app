import Foundation

/// Approval token and launch plan for the connectors MCP server.
/// The token file is mode 0600. The model never learns the value: the app
/// overwrites `approval_token` after the app policy permits execution.
enum PromethConnectorApproval {
    static let catalogID = "prometh.composio"
    static let keychainService = "studio.prometh.Prometh.connectors"
    static let executeTool = "connectors_execute"
    static let searchTool = "connectors_search"

    /// Legacy modal sheet is kept compiled but never presented.
    static var usesModalSheet: Bool { PromethFlags.legacyConnectorApprovalSheet }

    /// Synced from Prometh persisted state (`Snapshot.connectorAlwaysAllow`).
    nonisolated(unsafe) static var alwaysAllowed: Set<String> = []

    static func isExecute(_ name: String?) -> Bool {
        guard let name else { return false }
        return name == executeTool || name.hasSuffix("__" + executeTool)
    }

    static func isSearch(_ name: String?) -> Bool {
        guard let name else { return false }
        return name == searchTool || name.hasSuffix("__" + searchTool)
    }

    /// Action slug from a `connectors_execute` arguments JSON blob.
    static func actionSlug(from argumentsJSON: String?) -> String? {
        PromethConnectorActionPolicy.parse(argumentsJSON: argumentsJSON)?.slug
    }

    static func hintsFile(in support: URL) -> URL {
        support.appendingPathComponent("connectors/tool-hints.json", isDirectory: false)
    }

    static func hint(for slug: String, in support: URL = PromethIdentity.applicationSupportDirectory) -> PromethConnectorActionPolicy.Hint? {
        guard let data = try? Data(contentsOf: hintsFile(in: support)),
              let hints = try? JSONDecoder().decode([String: PromethConnectorActionPolicy.Hint].self, from: data)
        else { return nil }
        return hints[slug.uppercased()]
    }

    /// Looks back through earlier `connectors_search` tool results for tags on `slug`.
    static func tags(for slug: String, in messages: [(toolName: String?, content: String)]) -> [String]? {
        let needle = slug.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !needle.isEmpty else { return nil }
        for message in messages.reversed() {
            guard isSearch(message.toolName) else { continue }
            guard let data = message.content.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let items = (root["items"] as? [[String: Any]])
                ?? (root["tools"] as? [[String: Any]])
                ?? []
            for item in items {
                let itemSlug = (item["slug"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .uppercased()
                guard itemSlug == needle else { continue }
                if let tags = item["tags"] as? [String] {
                    return tags
                }
                return []
            }
        }
        return nil
    }

    static func syncAlwaysAllowed(_ keys: [String]) {
        alwaysAllowed = Set(keys.map { $0.lowercased() })
    }

    static func isAlwaysAllowed(slug: String) -> Bool {
        alwaysAllowed.contains(
            PromethConnectorActionPolicy.alwaysAllowKey(for: slug).lowercased()
        )
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
