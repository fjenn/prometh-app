import Foundation
import NativServerKit
import Security

/// One install id per Mac, stored in Keychain and mirrored to a mode-0600 file
/// the stdio server reads. The Composio API key is not stored here.
enum PromethConnectorSecret {
    static let account = "install-id"

    static func ensureInstallID(at file: URL) {
        let fromKeychain = (try? load())?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fromFile = (try? String(contentsOf: file, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let value = [fromKeychain, fromFile].compactMap { candidate -> String? in
            guard let candidate, !candidate.isEmpty else { return nil }
            return candidate
        }.first ?? UUID().uuidString
        try? save(value)
        try? write(value, to: file)
    }

    private static func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    private static func save(_ value: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let update = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        var item = baseQuery
        attributes.forEach { item[$0.key] = $0.value }
        _ = SecItemAdd(item as CFDictionary, nil)
    }

    private static func write(_ value: String, to file: URL) throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data((value + "\n").utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: file.path
        )
    }

    /// Path to the on-disk key file. The value inside is never returned.
    static func envFileURL() -> URL {
        let override = ProcessInfo.processInfo.environment["PROMETH_COMPOSIO_ENV"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let override, !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return URL(
            fileURLWithPath: (NSHomeDirectory() as NSString)
                .appendingPathComponent(".config/prometh/composio")
        ).appendingPathExtension("env")
    }

    /// True when a non-empty `COMPOSIO_API_KEY` is on disk (not process env).
    static func hasKeyOnDisk() -> Bool {
        guard let text = try? String(contentsOf: envFileURL(), encoding: .utf8) else { return false }
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let split = trimmed.firstIndex(of: "=") else { continue }
            let name = trimmed[..<split].trimmingCharacters(in: .whitespaces)
            guard name == "COMPOSIO_API_KEY" else { continue }
            let value = trimmed[trimmed.index(after: split)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return !value.isEmpty
        }
        return false
    }

    /// True when a key is present. The value is not kept or logged.
    static func hasAPIKeyFile() -> Bool {
        if let environment = ProcessInfo.processInfo.environment["COMPOSIO_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !environment.isEmpty {
            return true
        }
        return hasKeyOnDisk()
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: PromethConnectorApproval.keychainService,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}

/// Registers `prometh.composio` when a Composio key file exists, or when a
/// broker URL is set and no key file is. The API key and the approval token
/// stay out of `MCPServerConfig.environment`.
@MainActor
final class PromethConnectorHost {
    let manager = MCPHostManager()
    private var serverID = UUID()
    private var minted = false

    func attach(_ chat: ChatViewModel) {
        chat.mcpHost = manager
    }

    func apply(brokerURL: String?) {
        guard PromethFlags.promethShell, !PromethFlags.isRunningUnitTests else { return }
        let direct = PromethConnectorSecret.hasAPIKeyFile()
        guard let plan = plan(for: direct ? nil : brokerURL, direct: direct) else {
            manager.reload(servers: [])
            return
        }
        manager.reload(servers: [
            MCPServerConfig(
                id: serverID,
                catalogID: plan.catalogID,
                name: "Connectors",
                command: plan.command,
                arguments: plan.arguments,
                environment: PromethPython.environment(runtime: "composio_mcp", inheriting: ProcessInfo.processInfo.environment.merging(plan.environment) { _, value in value }),
                isEnabled: true
            ),
        ])
    }

    private func plan(for brokerURL: String?, direct: Bool) -> PromethConnectorPlan? {
        let trimmed = brokerURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard direct || !trimmed.isEmpty,
              let python = PromethPython.composio(),
              let script = PromethRuntimeLocator.url(relative: "composio_mcp/server.py") else {
            return nil
        }
        let support = PromethIdentity.applicationSupportDirectory
        let approval = PromethConnectorApproval.tokenFile(in: support)
        let install = PromethConnectorApproval.installFile(in: support)
        if !minted {
            try? PromethConnectorApproval.rewriteToken(at: approval)
            minted = true
        }
        PromethConnectorSecret.ensureInstallID(at: install)
        return PromethConnectorPlan.make(
            python: python.path,
            script: script.path,
            broker: trimmed,
            approvalFile: approval.path,
            installFile: install.path,
            direct: direct
        )
    }
}
