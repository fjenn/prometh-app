import Foundation

/// Whether a Composio action is a read or a mutating write.
enum PromethConnectorKind: String, Equatable, Sendable {
    case read
    case write
}

/// Classifies `connectors_execute` action slugs using Composio tags when present,
/// otherwise a write-verb heuristic on the slug words.
enum PromethConnectorActionPolicy {
    /// Composio / MCP hint tags. Either form is accepted.
    /// Composio tags seen live: readOnlyHint (LIST/FETCH), createHint (CREATE_AN_ISSUE,
    /// SEND_EMAIL), updateHint (STAR_A_REPOSITORY), destructiveHint (DELETE_*).
    static let destructiveHints: Set<String> = [
        "destructiveHint", "destructive_hint", "DestructiveHint",
        "createHint", "updateHint", "deleteHint",
    ]
    static let readOnlyHints: Set<String> = [
        "readOnlyHint", "read_only_hint", "ReadOnlyHint", "readonly",
    ]

    /// Verbs that mark a write. A write verb wins over any read word in the same slug.
    static let writeVerbs: Set<String> = [
        "CREATE", "UPDATE", "DELETE", "REMOVE", "SEND", "POST", "REPLY", "FORWARD",
        "MERGE", "CLOSE", "REOPEN", "TRANSFER", "PAY", "PAYMENT", "CHARGE", "REFUND",
        "INVITE", "SHARE", "ADD", "EDIT", "MODIFY", "PATCH", "PUT", "MOVE", "RENAME",
        "ARCHIVE", "TRASH", "STAR", "APPROVE", "DISMISS", "ASSIGN", "UNASSIGN",
        "LOCK", "UNLOCK", "FORK", "PUBLISH", "UPLOAD", "REVOKE", "CANCEL", "ACCEPT",
        "DECLINE", "SUBMIT", "DISPATCH", "RERUN", "TRIGGER", "ENABLE", "DISABLE",
        "SET", "BLOCK", "UNBLOCK", "FOLLOW", "UNFOLLOW", "MARK", "IMPORT", "REPLACE",
        "INSERT", "EXECUTE", "RUN", "DEPLOY", "WRITE", "COMMENT", "REACT", "VOTE",
        "SUBSCRIBE", "UNSUBSCRIBE", "MUTE", "SCHEDULE", "CLEAR", "RESET", "PURGE",
        "EMPTY", "DESTROY", "BATCH_MODIFY",
    ]

    /// Lowercase toolkit prefix before the first `_` (e.g. `github`).
    static func toolkit(from slug: String) -> String {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = trimmed.firstIndex(of: "_") else {
            return trimmed.lowercased()
        }
        return String(trimmed[..<index]).lowercased()
    }

    /// Persisted always-allow key: `toolkit:ACTION_SLUG`.
    static func alwaysAllowKey(toolkit: String, action: String) -> String {
        "\(toolkit.lowercased()):\(action.uppercased())"
    }

    static func alwaysAllowKey(for slug: String) -> String {
        alwaysAllowKey(toolkit: toolkit(from: slug), action: slug)
    }

    static func classify(slug: String, tags: [String]? = nil) -> PromethConnectorKind {
        if let tags, !tags.isEmpty {
            let normalized = Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            if !normalized.isDisjoint(with: destructiveHints) {
                return .write
            }
            if !normalized.isDisjoint(with: readOnlyHints) {
                return .read
            }
        }
        return classifyByName(slug)
    }

    /// Unknown names default to read: only clear write verbs or write hints ask first.
    /// True when the action should run without a consent prompt.
    static func skipsConsent(
        slug: String,
        tags: [String]? = nil,
        alwaysAllowed: Set<String> = []
    ) -> Bool {
        let kind = classify(slug: slug, tags: tags)
        if kind == .read { return true }
        let key = alwaysAllowKey(for: slug).lowercased()
        return alwaysAllowed.contains { $0.lowercased() == key }
    }

    private static func classifyByName(_ slug: String) -> PromethConnectorKind {
        let words = actionWords(slug)
        if words.contains(where: { writeVerbs.contains($0) }) {
            return .write
        }
        return .read
    }

    /// Words after the toolkit prefix, split on `_`.
    static func actionWords(_ slug: String) -> [String] {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let index = trimmed.firstIndex(of: "_") else { return [trimmed].filter { !$0.isEmpty } }
        let rest = trimmed[trimmed.index(after: index)...]
        return rest.split(separator: "_").map(String.init).filter { !$0.isEmpty }
    }
}

/// One-line plain description for the inline connector consent card.
enum PromethConnectorDescription {
    private static let preferredArgumentKeys = [
        "owner", "repo", "repository", "title", "to", "recipient", "subject",
        "name", "path", "channel", "channel_id", "issue_number", "pull_number",
        "query", "body",
    ]

    static func line(
        slug: String,
        argumentsJSON: String?,
        toolkitDisplayName: String? = nil
    ) -> String {
        let toolkit = PromethConnectorActionPolicy.toolkit(from: slug)
        let app = toolkitDisplayName ?? Self.defaultToolkitName(toolkit)
        let action = humanizeAction(slug, appName: app)
        let detail = argumentSummary(from: argumentsJSON)
        if detail.isEmpty {
            return action
        }
        return "\(action) \(detail)"
    }

    /// e.g. GITHUB_CREATE_AN_ISSUE → "Create a GitHub issue"
    static func humanizeAction(_ slug: String, appName: String? = nil) -> String {
        var words = PromethConnectorActionPolicy.actionWords(slug).map { $0.lowercased() }
        guard !words.isEmpty else { return "Run connected-app action" }
        // Drop trailing "for the authenticated user" noise.
        let noise = ["for", "the", "authenticated", "user"]
        while words.count >= noise.count,
              Array(words.suffix(noise.count)) == noise {
            words.removeLast(noise.count)
        }
        let app = appName ?? defaultToolkitName(PromethConnectorActionPolicy.toolkit(from: slug))
        // Insert the app name after the first article (or after the verb).
        if let articleIndex = words.firstIndex(where: { $0 == "a" || $0 == "an" || $0 == "the" }),
           articleIndex + 1 < words.count {
            if words[articleIndex] != "the" {
                let vowel = app.lowercased().first.map { "aeiou".contains($0) } ?? false
                words[articleIndex] = vowel ? "an" : "a"
            }
            words.insert(app, at: articleIndex + 1)
        } else if words.count >= 1 {
            words.insert(app, at: min(1, words.count))
        }
        return words.enumerated().map { index, word -> String in
            if index == 0 {
                return word.prefix(1).uppercased() + word.dropFirst()
            }
            switch word {
            case "a", "an", "the", "for", "of", "in", "to", "on", "by", "with":
                return word
            default:
                if word == app { return app }
                return word
            }
        }.joined(separator: " ")
    }

    private static func defaultToolkitName(_ toolkit: String) -> String {
        switch toolkit {
        case "github": return "GitHub"
        case "gmail": return "Gmail"
        case "slack": return "Slack"
        case "linear": return "Linear"
        case "notion": return "Notion"
        case "googledrive", "google_drive": return "Google Drive"
        default:
            guard !toolkit.isEmpty else { return "connected app" }
            return toolkit.prefix(1).uppercased() + toolkit.dropFirst()
        }
    }

    private static func argumentSummary(from argumentsJSON: String?) -> String {
        guard let object = nestedArguments(from: argumentsJSON) else { return "" }
        let owner = stringValue(object["owner"])
        let repo = stringValue(object["repo"]) ?? stringValue(object["repository"])
        var pieces: [String] = []
        if let owner, let repo, !owner.isEmpty, !repo.isEmpty {
            pieces.append("in \(owner)/\(repo)")
        } else if let repo, !repo.isEmpty {
            pieces.append("in \(repo)")
        }
        if let title = stringValue(object["title"]), !title.isEmpty {
            pieces.append("titled “\(truncate(title))”")
        }
        if let to = stringValue(object["to"]) ?? stringValue(object["recipient"]), !to.isEmpty {
            pieces.append("to \(truncate(to))")
        }
        if let subject = stringValue(object["subject"]), !subject.isEmpty {
            pieces.append("subject “\(truncate(subject))”")
        }
        if pieces.isEmpty {
            for key in preferredArgumentKeys {
                guard let value = stringValue(object[key]), !value.isEmpty else { continue }
                if key == "owner" || key == "repo" || key == "repository"
                    || key == "title" || key == "to" || key == "recipient" || key == "subject" {
                    continue
                }
                pieces.append("\(key.replacingOccurrences(of: "_", with: " ")) \(truncate(value))")
                break
            }
        }
        return pieces.joined(separator: " ")
    }

    /// Parses execute args; unwraps nested `arguments_json` string when present.
    static func nestedArguments(from argumentsJSON: String?) -> [String: Any]? {
        guard let argumentsJSON,
              let data = argumentsJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let nested = root["arguments_json"] as? String,
           let nestedData = nested.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: nestedData) as? [String: Any] {
            return object
        }
        if let nested = root["arguments"] as? [String: Any] {
            return nested
        }
        return root
    }

    private static func stringValue(_ raw: Any?) -> String? {
        switch raw {
        case let value as String: return value
        case let value as NSNumber: return value.stringValue
        default: return nil
        }
    }

    private static func truncate(_ value: String, limit: Int = 48) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit - 1)) + "…"
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
