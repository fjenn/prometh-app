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
            return scrubInternals(content)
        }
        if hasToolCalls && !isLastAssistantInTurn {
            return nil
        }
        let thought = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        if !thought.isEmpty {
            return scrubInternals(reasoning)
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

    /// Drops attachment IDs / UUID dumps that models sometimes echo from tool JSON.
    static func scrubInternals(_ value: String) -> String {
        var text = value
        text = text.replacingOccurrences(
            of: #"(?i)[,.]?\s*(?:the\s+)?(?:new\s+)?version is available with the attachment id(?:\s+`?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}`?)?\.?"#,
            with: ".",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"(?i)(?:with\s+)?(?:the\s+)?attachment\s*id\s*`?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}`?"#,
            with: "",
            options: .regularExpression
        )
        // Bare or backticked UUIDs left behind by partial phrasing.
        text = text.replacingOccurrences(
            of: #"`?[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}`?"#,
            with: "",
            options: .regularExpression
        )
        // Empty inline code / brackets left after ID removal (e.g. "dusk. ``.").
        text = text.replacingOccurrences(of: #"`\s*`"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[\s*\]"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\(\s*\)"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+([.,;:!?])"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\.\s*\."#, with: ".", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
