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
            return customName
        }
        let storedName = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if preserveStored, !storedName.isEmpty {
            return storedName
        }
        guard let first = prompts.first else {
            return storedName.isEmpty ? "New chat" : storedName
        }
        let line = first
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        if line.isEmpty {
            return storedName.isEmpty ? "New chat" : storedName
        }
        return truncate(firstPrompt(in: line))
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

    static func truncate(_ value: String, maxLength: Int = 56) -> String {
        guard value.count > maxLength else { return value }
        let keep = max(1, maxLength - 1)
        return "\(value.prefix(keep))…"
    }
}
