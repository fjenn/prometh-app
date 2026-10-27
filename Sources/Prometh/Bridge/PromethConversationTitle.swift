import Foundation

/// Sidebar title. A custom name wins. Otherwise only the first prompt is used,
/// and a second prompt jammed against a `?` or `!` is cut off.
enum PromethConversationTitle {
    static func title(
        custom: String?,
        preserveStored: Bool,
        stored: String,
        prompts: [String]
    ) -> String {
        let customName = custom?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !customName.isEmpty {
            return display(customName)
        }
        let storedName = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if preserveStored, !storedName.isEmpty {
            return display(storedName)
        }
        guard let first = prompts.first else {
            return storedName.isEmpty ? "New chat" : display(storedName)
        }
        let line = first
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        if line.isEmpty {
            return storedName.isEmpty ? "New chat" : display(storedName)
        }
        return display(firstPrompt(in: line))
    }

    /// Cuts at the first `?` or `!` that is immediately followed by more text.
    static func firstPrompt(in line: String) -> String {
        let characters = Array(line)
        for index in characters.indices {
            let character = characters[index]
            guard character == "?" || character == "!" else { continue }
            let next = characters.index(after: index)
            guard next < characters.endIndex else { continue }
            if !characters[next].isWhitespace {
                return String(characters[...index])
            }
        }
        return line
    }

    /// Drops common markdown wrappers so window/sidebar titles stay plain text.
    /// Applied before truncation so a cut mid-marker cannot leave raw `**` visible.
    static func stripMarkdown(_ value: String) -> String {
        var text = value
        text = text.replacingOccurrences(
            of: #"^#{1,6}\s+"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"\*\*(.+?)\*\*"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"__(.+?)__"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"~~(.+?)~~"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"`([^`]+)`"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"\*(.+?)\*"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"_(.+?)_"#,
            with: "$1",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "__", with: "")
        text = text.replacingOccurrences(of: "~~", with: "")
        text = text.replacingOccurrences(of: "`", with: "")
        text = text.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
        return text
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func truncate(_ value: String, maxLength: Int = 56) -> String {
        guard value.count > maxLength else { return value }
        let keep = max(1, maxLength - 1)
        return "\(value.prefix(keep))…"
    }

    private static func display(_ value: String) -> String {
        truncate(stripMarkdown(value))
    }
}
