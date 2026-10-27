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
            return content
        }
        if hasToolCalls && !isLastAssistantInTurn {
            return nil
        }
        let thought = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        if !thought.isEmpty {
            return reasoning
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
}
