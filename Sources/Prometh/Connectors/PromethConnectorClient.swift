import Foundation

struct PromethConnectorResult: Equatable {
    var ok: Bool
    var status: String
    var redirectURL: URL?
    var message: String?
}

/// Talks to the stdio connector helper. The API key stays in the helper.
enum PromethConnectorClient {
    static func link(_ provider: Provider) async -> PromethConnectorResult {
        await run(extra: ["--link", provider.toolkit])
    }

    static func status(_ provider: Provider) async -> PromethConnectorResult {
        await run(extra: ["--status", provider.toolkit])
    }

    static func disconnect(_ provider: Provider) async -> PromethConnectorResult {
        await run(extra: ["--disconnect", provider.toolkit])
    }

    private static func run(extra: [String]) async -> PromethConnectorResult {
        do { return parse(try await request(extra:extra)) }
        catch { return PromethConnectorResult(ok:false,status:"disconnected",message:error.localizedDescription) }
    }

    static func link(toolkit: String) async -> PromethConnectorResult { await run(extra:["--link",toolkit]) }
    static func status(toolkit: String) async -> PromethConnectorResult { await run(extra:["--status",toolkit]) }
    static func disconnect(toolkit: String) async -> PromethConnectorResult { await run(extra:["--disconnect",toolkit]) }

    static func request(extra: [String]) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            guard let python = PromethPython.composio(),
                  let script = PromethRuntimeLocator.url(relative: "composio_mcp/server.py") else {
                throw ToolkitCatalogError.invalid("Connectors are not ready.")
            }
            let support = PromethIdentity.applicationSupportDirectory
            let install = PromethConnectorApproval.installFile(in: support)
            PromethConnectorSecret.ensureInstallID(at: install)
            let process = Process()
            process.executableURL = python
            process.arguments = [script.path, "--install-file", install.path] + extra
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            var environment = PromethPython.environment(runtime: "composio_mcp")
            // Prefer the on-disk key file. Only strip the process env key when that
            // file is present so env-only setups still reach the helper.
            if PromethConnectorSecret.hasKeyOnDisk() {
                environment.removeValue(forKey: "COMPOSIO_API_KEY")
            }
            process.environment = environment
            do {
                try process.run()
            } catch {
                throw ToolkitCatalogError.invalid("Connectors are not ready.")
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw ToolkitCatalogError.invalid("The connection service stopped unexpectedly.") }
            return data
        }.value
    }

    private static func parse(_ data: Data) -> PromethConnectorResult {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return PromethConnectorResult(
                ok: false,
                status: "disconnected",
                message: "The connection service did not answer."
            )
        }
        let message = object["error"] as? String
        var url: URL?
        if let raw = object["redirect_url"] as? String {
            url = URL(string: raw)
        }
        return PromethConnectorResult(
            ok: object["ok"] as? Bool ?? false,
            status: object["status"] as? String ?? "disconnected",
            redirectURL: url,
            message: message
        )
    }
}
