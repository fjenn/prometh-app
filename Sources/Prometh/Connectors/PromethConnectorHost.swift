import Foundation
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

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: PromethConnectorApproval.keychainService,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}

/// Registers `prometh.composio` only while a broker URL is set. The API key and
/// the approval token stay out of `MCPServerConfig.environment`.
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
        guard let plan = plan(for: brokerURL) else {
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
                environment: plan.environment,
                isEnabled: true
            ),
        ])
    }

    private func plan(for brokerURL: String?) -> PromethConnectorPlan? {
        guard let brokerURL,
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
            broker: brokerURL,
            approvalFile: approval.path,
            installFile: install.path
        )
    }
}
