import Foundation

struct PromethSearchHit: Equatable, Sendable {
    var title: String
    var snippet: String
}

/// What an assistant row should show. Empty tool-call carriers are omitted.
/// A finished news turn with no prose falls back to the search snippets.
enum PromethTranscript {
    static func visibleText(
        content: String,
        reasoning: String,
        hasToolCalls: Bool,
        isStreaming: Bool,
        isLastAssistantInTurn: Bool,
        searchHits: [PromethSearchHit]
    ) -> String? {
        let body = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty {
            return scrubInternals(unwrapOuterMarkdownFence(content))
        }
        if hasToolCalls && !isLastAssistantInTurn {
            return nil
        }
        let thought = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        if !thought.isEmpty {
            return scrubInternals(unwrapOuterMarkdownFence(reasoning))
        }
        if isLastAssistantInTurn && !isStreaming && !searchHits.isEmpty {
            return groundedSummary(searchHits)
        }
        if isStreaming {
            return ""
        }
        return nil
    }

    static func searchHits(from bodies: [String]) -> [PromethSearchHit] {
        var hits: [PromethSearchHit] = []
        for body in bodies {
            let jsonLine = body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                .first
                .map(String.init) ?? body
            guard let data = jsonLine.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = object["results"] as? [[String: Any]]
            else { continue }
            for result in results {
                let title = (result["title"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let snippet = ((result["snippet"] as? String) ?? (result["content"] as? String) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let url = (result["url"] as? String) ?? ""
                if title.isEmpty && snippet.isEmpty { continue }
                hits.append(PromethSearchHit(title: title.isEmpty ? url : title, snippet: snippet))
            }
        }
        return hits
    }

    static func groundedSummary(_ hits: [PromethSearchHit]) -> String {
        hits.enumerated().map { offset, hit in
            let marker = "[\(offset + 1)]"
            if hit.snippet.isEmpty {
                return "\(hit.title) \(marker)"
            }
            return "\(hit.title) \(marker)\n\(hit.snippet)"
        }.joined(separator: "\n\n")
    }

    /// Models often wrap a whole markdown reply in ```markdown … ```, which makes
    /// Workspace's fence splitter treat lists/bold as a single code card. Unwrap
    /// document fences so nested ```python``` and list markers render normally.
    static func unwrapOuterMarkdownFence(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return value }
        var lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first else { return value }
        let lang = String(first.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let wrappers: Set<String> = ["", "markdown", "md", "text", "txt"]
        guard wrappers.contains(lang) else { return value }
        guard trimmed.hasSuffix("```") else { return value }
        lines.removeFirst()
        while lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeLast()
        }
        guard lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" else { return value }
        lines.removeLast()
        let unwrapped = lines.joined(separator: "\n")
        let hasStructure = unwrapped.contains("```")
            || unwrapped.contains("\n*")
            || unwrapped.contains("\n-")
            || unwrapped.contains("**")
        return hasStructure ? unwrapped : value
    }

    /// Drops attachment IDs / UUID dumps that models sometimes echo from tool JSON.
    static func scrubInternals(_ value: String) -> String {
        var text = value
        let uuid = #"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"#
        text = text.replacingOccurrences(
            of: #"(?i)[,.]?\s*(?:the\s+)?(?:new\s+)?version is available with the attachment id(?:\s+`?#uuid#`?)?\.?"#
                .replacingOccurrences(of: "#uuid#", with: uuid),
            with: ".",
            options: .regularExpression
        )
        // Word boundaries on view|see|open so "seen" / "opening" are not eaten
        // (judge bug: "has seen clashes" → "has.n clashes").
        text = text.replacingOccurrences(
            of: #"(?i)[,.]?\s*(?:you can )?\b(?:view|see|open)\b(?:\s+it)?(?:\s+using)?(?:\s+the)?(?:\s+attachment\s*id)(?:\s+`?#uuid#`?)?\.?"#
                .replacingOccurrences(of: "#uuid#", with: uuid),
            with: ".",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?i)(?:with\s+)?(?:the\s+)?attachment\s*id\s*`?#uuid#`?"#
                .replacingOccurrences(of: "#uuid#", with: uuid),
            with: "",
            options: .regularExpression
        )
        // Bare or backticked UUIDs left behind by partial phrasing.
        text = text.replacingOccurrences(
            of: #"`?#uuid#`?"#.replacingOccurrences(of: "#uuid#", with: uuid),
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // Empty inline code / brackets left after ID removal (e.g. "dusk. ``.").
        // Do not touch triple-backtick fences — `(?<!`)`…`(?!`)` keeps ``` intact.
        text = text.replacingOccurrences(of: #"(?<!`)`\s*`(?!`)"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[\s*\]"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\(\s*\)"#, with: "", options: .regularExpression)
        // Citation remapper can drop [n] chips and leave "available on and."
        text = text.replacingOccurrences(
            of: #"(?i)[,.]?\s*these summaries are drawn from the reports available on(?:\s+and)?\.?"#,
            with: ".",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?i)\s+available on(?:\s+and)?\.?\s*$"#,
            with: ".",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: #"(?i)\s+using\.?\s*$"#, with: ".", options: .regularExpression)
        // Collapse horizontal whitespace only — never eat newlines. Markdown lists
        // and fenced code blocks need blank lines / line-start markers intact.
        text = text.replacingOccurrences(of: #"[\t ]+([.,;:!?])"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\.[ \t]*\."#, with: ".", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[\t ]{2,}"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
