import Foundation

/// JSON shared by the WK host and the unchanged web state types.
enum PromethWebMapping {
    static func preparation(_ value: Preparation) -> [String: Any] {
        ["status": value.status.rawValue.lowercased(), "progress": value.progress]
    }
    static func conversation(_ value: Conversation) -> [String: Any] {
        ["id": value.id.uuidString, "title": value.title, "mode": value.mode == .evil ? "evil" : "safe",
         "messages": value.messages.filter { $0.role == "user" || $0.role == "assistant" }.map(message),
         "draft": value.draft, "attachments": [], "updated": value.updated.timeIntervalSince1970 * 1000]
    }
    static func message(_ value: Message) -> [String: Any] {
        ["id": value.id.uuidString, "role": value.role, "text": value.text, "status": value.status]
    }
    static func extras(_ messages: [Message]) -> [[String: Any]] {
        messages.compactMap { message in
            var item: [String: Any] = ["id": message.id.uuidString]
            if let sources = message.sourceLinks, !sources.isEmpty {
                item["sources"] = sources.map { ["title": $0.title, "url": $0.url] }
            }
            if let card = message.connectorCard {
                item["connector"] = ["toolkit": card.toolkit, "action": card.action, "summary": card.summary,
                                     "phase": card.phase, "detail": card.detail ?? "", "name": card.appName ?? card.toolkit]
            }
            if let artifact = message.artifact {
                item["artifact"] = ["kind": artifact.kind, "filename": artifact.filename, "prompt": artifact.prompt,
                                    "version": artifact.version, "duration": artifact.duration ?? 0]
            }
            return item.count > 1 ? item : nil
        }
    }
    static func jsonArguments(_ values: [Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: values, options: [.fragmentsAllowed, .sortedKeys]), as: UTF8.self)
    }
}

/// Only app-owned files are addressable from the web origin.
enum PromethWebFiles {
    static var blobs: URL { PromethIdentity.applicationSupportDirectory.appendingPathComponent("WebBlobs", isDirectory: true) }
    static var media: URL { PromethIdentity.applicationSupportDirectory.appendingPathComponent("Media", isDirectory: true) }
    static func resource(_ root: URL, relative: String) throws -> URL {
        // Foundation normalizes /private/tmp to /tmp. Apply the same
        // canonicalization to both sides of the containment check, including
        // symlinks, so a relocated app can serve its own nested web assets.
        let directory = root.standardizedFileURL.resolvingSymlinksInPath()
        let file = directory.appendingPathComponent(relative)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard file.path.hasPrefix(directory.path + "/") else {
            throw URLError(.noPermissionsToReadFile)
        }
        return file
    }
    static func file(_ root: URL, _ name: String) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains("\0") else { throw URLError(.badURL) }
        let result = root.appendingPathComponent(name).resolvingSymlinksInPath()
        guard result.deletingLastPathComponent().path == root.resolvingSymlinksInPath().path else { throw URLError(.noPermissionsToReadFile) }
        return result
    }
}


extension PromethWebMapping {
    /// Keep preferred/download catalog selections separate from the model actually resident in the server.
    static func runtimeModel(health: [String: Any], catalog: ModelCatalog) -> [String: Any]? {
        let repo: String?
        if let loaded = health["loaded_models"] as? [String: Any] {
            repo = (loaded["text_generation"] as? [String: Any])?["model"] as? String
        } else { repo = health["loaded_model"] as? String }
        guard let repo, !repo.isEmpty else { return nil }
        // Capability is human copy (Qwen uses "Chat option"); the runtime repository is the identity.
        let match = catalog.models.first { $0.enabled && $0.repo == repo }
        var result: [String: Any] = ["repo": repo, "label": match?.name ?? repo]
        if let match { result["id"] = match.id; result["sizeGB"] = Double(match.downloadBytes) / 1e9 }
        return result
    }

    static func externalURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}
