import Foundation

/// Pure policy: metadata wins; otherwise the first known action verb decides.
enum PromethConnectorActionPolicy {
    enum Effect: String, Equatable, Sendable { case read, write }
    enum Decision: Equatable { case run, needsCard }

    struct Hint: Codable, Equatable {
        var tags: [String]?
        var name: String?
        var toolkit: String?
    }

    struct Action {
        let slug: String
        let arguments: [String: Any]
    }

    static let readVerbs: Set<String> = [
        "LIST", "GET", "SEARCH", "FETCH", "FIND", "READ", "RETRIEVE", "QUERY", "CHECK",
        "COUNT", "DESCRIBE", "VIEW", "LOOKUP", "SHOW", "DOWNLOAD",
    ]
    static let writeVerbs: Set<String> = [
        "CREATE", "UPDATE", "DELETE", "REMOVE", "SEND", "SENDS", "POST", "PUT", "PATCH",
        "MERGE", "TRANSFER", "INVITE", "SHARE", "ADD", "EDIT", "MODIFY", "REPLY",
        "FORWARD", "MOVE", "ARCHIVE", "TRASH", "UPLOAD", "PUBLISH", "CLOSE", "REOPEN",
        "LOCK", "UNLOCK", "REVOKE", "APPROVE", "DISMISS", "CANCEL", "EXECUTE", "RUN",
        "TRIGGER", "DISPATCH", "SET", "ENABLE", "DISABLE", "FOLLOW", "UNFOLLOW", "STAR",
        "UNSTAR", "ACCEPT", "DECLINE", "MARK", "ASSIGN", "UNASSIGN", "RENAME", "COPY",
        "IMPORT", "SUBMIT", "PAY", "SCHEDULE", "INSERT", "REPLACE", "RESTORE", "CLEAR",
        "BLOCK", "UNBLOCK", "WATCH", "SUBSCRIBE", "UNSUBSCRIBE", "LABEL", "PIN", "UNPIN",
        "REACT", "COMMENT", "DRAFT", "FORK",
    ]

    static func parse(argumentsJSON: String?) -> Action? {
        guard let argumentsJSON, let data = argumentsJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root["tool"] as? String else { return nil }
        let slug = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty else { return nil }
        var arguments: [String: Any] = [:]
        if let nested = root["arguments_json"] as? String,
           let data = nested.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            arguments = object
        } else if let object = root["arguments_json"] as? [String: Any] {
            arguments = object
        }
        return Action(slug: slug, arguments: arguments)
    }

    static func classify(slug: String, tags: [String]? = nil) -> Effect {
        let hints = Set((tags ?? []).map { $0.lowercased() })
        if !hints.isDisjoint(with: ["destructivehint", "createhint", "updatehint", "deletehint"]) {
            return .write
        }
        if hints.contains("readonlyhint") { return .read }
        for token in tokens(slug).dropFirst() {
            if readVerbs.contains(token) { return .read }
            if writeVerbs.contains(token) { return .write }
        }
        // Unknown actions (including EXPORT) fail safe: show the approval card.
        return .write
    }

    static func toolkit(from slug: String, metadata: String? = nil) -> String {
        if let metadata, !metadata.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return metadata.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let words = tokens(slug)
        let verb = words.indices.dropFirst().first { readVerbs.contains(words[$0]) || writeVerbs.contains(words[$0]) }
        return words.prefix(verb ?? min(1, words.count)).joined().lowercased()
    }

    static func decision(slug: String, hint: Hint? = nil, alwaysAllowed: Set<String> = []) -> Decision {
        if classify(slug: slug, tags: hint?.tags) == .read { return .run }
        let key = alwaysAllowKey(toolkit: toolkit(from: slug, metadata: hint?.toolkit), action: slug)
        return alwaysAllowed.contains { $0.lowercased() == key.lowercased() } ? .run : .needsCard
    }

    static func skipsConsent(slug: String, tags: [String]? = nil, alwaysAllowed: Set<String> = []) -> Bool {
        decision(slug: slug, hint: Hint(tags: tags), alwaysAllowed: alwaysAllowed) == .run
    }

    static func alwaysAllowKey(toolkit: String, action: String) -> String {
        "\(toolkit.lowercased()):\(action.uppercased())"
    }
    static func alwaysAllowKey(for slug: String) -> String {
        alwaysAllowKey(toolkit: toolkit(from: slug), action: slug)
    }
    private static func tokens(_ slug: String) -> [String] {
        slug.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().split(separator: "_").map(String.init)
    }
    static func actionWords(_ slug: String) -> [String] {
        let words = tokens(slug)
        let index = words.indices.dropFirst().first { readVerbs.contains(words[$0]) || writeVerbs.contains(words[$0]) }
        return Array(words.dropFirst(index ?? min(1, words.count)))
    }

    static func declinedPayload(actionName: String, appName: String) -> String {
        let object: [String: Any] = [
            "ok": false, "executed": false, "declined": true,
            "error": "The user chose not to allow \(actionName) in \(appName). Nothing was sent. Briefly tell them it was not done.",
        ]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }
}

enum PromethConnectorDescription {
    static func actionName(slug: String, hint: PromethConnectorActionPolicy.Hint? = nil) -> String {
        if let name = hint?.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return oneLine(name)
        }
        return humanizeAction(slug)
    }

    static func humanizeAction(_ slug: String, appName: String? = nil) -> String {
        var words = PromethConnectorActionPolicy.actionWords(slug).map { $0.lowercased() }
        let noise = ["for", "the", "authenticated", "user"]
        if words.suffix(noise.count) == noise[...] { words.removeLast(noise.count) }
        let text = words.joined(separator: " ")
        return text.isEmpty ? "Run connected-app action" : text.prefix(1).uppercased() + text.dropFirst()
    }

    static func appName(_ toolkit: String) -> String {
        switch toolkit {
        case "github": "GitHub"
        case "gmail": "Gmail"
        case "googledrive": "Google Drive"
        default: toolkit.isEmpty ? "connected app" : toolkit.prefix(1).uppercased() + toolkit.dropFirst()
        }
    }

    static func detail(arguments: [String: Any]) -> String {
        func value(_ key: String) -> String? {
            if let text = arguments[key] as? String { return oneLine(text) }
            if let list = arguments[key] as? [String] { return oneLine(list.joined(separator: ", ")) }
            return nil
        }
        var parts: [String] = []
        if let repo = value("owner_repo") { parts.append(repo) }
        else if let repo = value("repo") ?? value("repository") {
            parts.append(value("owner").map { "\($0)/\(repo)" } ?? repo)
        }
        for key in ["title", "to", "subject", "channel"] {
            if let text = value(key), !text.isEmpty { parts.append(text) }
        }
        return oneLine(parts.joined(separator: " · "), limit: 160)
    }

    static func line(slug: String, argumentsJSON: String?, toolkitDisplayName: String? = nil) -> String {
        let detail = detail(arguments: PromethConnectorActionPolicy.parse(argumentsJSON: argumentsJSON)?.arguments ?? [:])
        return [humanizeAction(slug), detail].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private static func oneLine(_ value: String, limit: Int = 80) -> String {
        let text = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }
}

/// Always-allow persistence helpers (decode-compatible list of `toolkit:ACTION` keys).
enum PromethConnectorAlwaysAllow {
    static func contains(_ key: String, in keys: [String]) -> Bool {
        let needle = key.lowercased()
        return keys.contains { $0.lowercased() == needle }
    }

    static func adding(_ key: String, to keys: [String]) -> [String] {
        if contains(key, in: keys) { return keys }
        return keys + [key]
    }

    static func resetting(toolkit: String, in keys: [String]) -> [String] {
        let prefix = toolkit.lowercased() + ":"
        return keys.filter { !$0.lowercased().hasPrefix(prefix) }
    }

    static func keys(for toolkit: String, in keys: [String]) -> [String] {
        let prefix = toolkit.lowercased() + ":"
        return keys.filter { $0.lowercased().hasPrefix(prefix) }
    }
}
