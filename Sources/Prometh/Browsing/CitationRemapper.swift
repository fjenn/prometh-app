import Foundation

/// Deterministic post-processing for model replies: remap `[n]` chips to the
/// source whose fetched text best matches each cited sentence/bullet, clamp
/// out-of-range indices, and scrub outlet names that were never read.
enum CitationRemapper {
    struct Source: Equatable, Sendable {
        var index: Int
        var title: String
        var url: String
        var body: String
        var snippet: String

        var matchText: String {
            [title, snippet, body].joined(separator: "\n")
        }

        var displayName: String {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            return PromethSearchContext.normalizedHost(url)
        }
    }

    /// Rewrites citation chips and foreign outlet names after streaming finishes.
    static func rewrite(_ reply: String, sources: [Source]) -> String {
        guard !sources.isEmpty else {
            return stripCitations(reply)
        }
        let remapped = remapCitations(reply, sources: sources)
        return scrubForeignOutlets(remapped, sources: sources)
    }

    /// Assign each cited sentence/bullet to the best-matching source index.
    static func remapCitations(_ reply: String, sources: [Source]) -> String {
        guard !sources.isEmpty else { return stripCitations(reply) }
        let valid = Set(sources.map(\.index))
        let lines = reply.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.map { line in
            remapLine(line, sources: sources, valid: valid)
        }.joined(separator: "\n")
    }

    private static func remapLine(_ line: String, sources: [Source], valid: Set<Int>) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"\[(\d+(?:\s*,\s*\d+)*)\]"#) else {
            return line
        }
        let range = NSRange(line.startIndex..., in: line)
        let matches = expression.matches(in: line, range: range)
        guard !matches.isEmpty else { return line }

        let plain = expression.stringByReplacingMatches(in: line, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let best = bestSource(for: plain, sources: sources)

        var result = ""
        var cursor = line.startIndex
        for match in matches {
            guard let whole = Range(match.range, in: line),
                  let group = Range(match.range(at: 1), in: line) else { continue }
            result += line[cursor..<whole.lowerBound]
            let parts = line[group].split(separator: ",").compactMap {
                Int($0.trimmingCharacters(in: .whitespaces))
            }
            if parts.isEmpty {
                cursor = whole.upperBound
                continue
            }
            // One cited segment → one best source. Multiple slots in the same
            // marker get the same index so chips stay 1:1 with Sources.
            if let best {
                result += "[\(best.index)]"
            } else {
                // No content match: keep in-range indices, drop the rest.
                let kept = parts.filter { valid.contains($0) }
                if kept.count == 1 {
                    result += "[\(kept[0])]"
                } else if kept.count > 1 {
                    result += kept.map { "[\($0)]" }.joined()
                }
            }
            cursor = whole.upperBound
        }
        result += line[cursor...]
        return result
    }

    static func bestSource(for segment: String, sources: [Source]) -> Source? {
        let tokens = Self.tokens(segment)
        guard !tokens.isEmpty else { return nil }
        var best: Source?
        var bestScore = 0.0
        for source in sources {
            let score = Self.score(tokens: tokens, source: source)
            if score > bestScore {
                bestScore = score
                best = source
            }
        }
        // Require a real overlap so empty/boilerplate lines do not all become [1].
        return bestScore >= 1.0 ? best : nil
    }

    static func score(tokens segmentTokens: Set<String>, source: Source) -> Double {
        let bodyTokens = tokens(source.matchText)
        guard !bodyTokens.isEmpty else { return 0 }
        let overlap = segmentTokens.intersection(bodyTokens).count
        let titleBoost = Double(segmentTokens.intersection(tokens(source.title)).count) * 2.5
        return Double(overlap) + titleBoost
    }

    static func tokens(_ text: String) -> Set<String> {
        let lowered = text.lowercased()
        var result: Set<String> = []
        var current = ""
        for character in lowered {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if !current.isEmpty {
                if current.count >= 3, !stopwords.contains(current) {
                    result.insert(current)
                }
                current = ""
            }
        }
        if current.count >= 3, !stopwords.contains(current) {
            result.insert(current)
        }
        return result
    }

    private static let stopwords: Set<String> = [
        "the", "and", "for", "are", "but", "not", "you", "all", "can", "had", "her",
        "was", "one", "our", "out", "has", "have", "been", "from", "they", "this",
        "that", "with", "will", "what", "when", "your", "more", "into", "than",
        "then", "some", "them", "would", "there", "their", "about", "which", "could",
        "other", "after", "also", "over", "such", "only", "just", "like", "news",
        "today", "story", "stories", "source", "sources", "website", "according",
        "based", "information", "retrieved", "please", "note", "content", "readable",
        "snapshot", "current", "world", "latest", "breaking", "international",
    ]

    private static func stripCitations(_ text: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"\[(\d+(?:\s*,\s*\d+)*)\]"#) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .replacingOccurrences(of: "  ", with: " ")
    }

    /// Drop or rewrite outlet names that are not among the read sources.
    static func scrubForeignOutlets(_ reply: String, sources: [Source]) -> String {
        let allowed = allowedNames(sources)
        var text = reply
        for outlet in knownOutlets {
            let key = outlet.lowercased()
            if allowed.contains(key) { continue }
            // "from the BBC News website" → "from the sources below"
            text = replaceIgnoringCase(
                text,
                pattern: #"\bfrom the "# + NSRegularExpression.escapedPattern(for: outlet) + #" website\b"#,
                with: "from the sources below"
            )
            text = replaceIgnoringCase(
                text,
                pattern: #"\bfrom "# + NSRegularExpression.escapedPattern(for: outlet) + #"\b"#,
                with: "from the sources below"
            )
            text = replaceIgnoringCase(
                text,
                pattern: #"\b"# + NSRegularExpression.escapedPattern(for: outlet) + #"\b"#,
                with: ""
            )
        }
        // Collapse leftover double spaces and empty "  " after removals.
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        text = text.replacingOccurrences(of: " ,", with: ",")
        text = text.replacingOccurrences(of: " .", with: ".")
        return text
    }

    static func allowedNames(_ sources: [Source]) -> Set<String> {
        var names: Set<String> = []
        for source in sources {
            let title = source.title.lowercased()
            if !title.isEmpty { names.insert(title) }
            for outlet in knownOutlets where title.contains(outlet.lowercased()) {
                names.insert(outlet.lowercased())
            }
            let host = PromethSearchContext.normalizedHost(source.url)
            if !host.isEmpty {
                names.insert(host)
                let brand = host.split(separator: ".").first.map(String.init) ?? host
                names.insert(brand)
                for outlet in knownOutlets {
                    let key = outlet.lowercased()
                    if key.contains(brand) || brand.contains(key.replacingOccurrences(of: " ", with: "")) {
                        names.insert(key)
                    }
                }
            }
        }
        return names
    }

    /// Common outlets the model invents when it was not given that page.
    static let knownOutlets: [String] = [
        "BBC News", "BBC", "CNN", "AP News", "Associated Press", "Reuters",
        "The Guardian", "Guardian", "New York Times", "NYTimes", "NYT",
        "Washington Post", "Fox News", "Al Jazeera", "NPR", "Bloomberg",
        "Financial Times", "Wall Street Journal", "WSJ", "USA Today",
        "The Times", "Sky News", "CNBC", "ABC News", "CBS News", "NBC News",
        "Google News", "Yahoo News", "MSN",
    ]

    private static func replaceIgnoringCase(_ text: String, pattern: String, with template: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
