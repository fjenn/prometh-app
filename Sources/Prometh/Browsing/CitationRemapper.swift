import Foundation

/// Deterministic post-processing for model replies: remap `[n]` chips to the
/// source whose fetched text best matches each cited sentence/bullet, drop chips
/// with no supporting overlap, clamp out-of-range indices, and scrub outlet
/// names that were never read.
enum CitationRemapper {
    /// Minimum token-overlap score required to keep a citation chip.
    static let minimumSupportScore: Double = 1.0

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

    /// Assign each cited sentence/bullet to a supported source index.
    /// Prefer the model's own chip when that source clears `minimumSupportScore`
    /// (keeps distinct Sources distinct). Otherwise fall back to best overlap.
    /// Unsupported chips are dropped. Repeated chips for one source stay when
    /// that source is the only one that supports the line.
    static func remapCitations(_ reply: String, sources: [Source]) -> String {
        guard !sources.isEmpty else { return stripCitations(reply) }
        guard let expression = try? NSRegularExpression(pattern: #"\[(\d+(?:\s*,\s*\d+)*)\]"#) else {
            return reply
        }
        let indexToOffset = Dictionary(uniqueKeysWithValues: sources.enumerated().map { ($0.element.index, $0.offset) })
        let lines = reply.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var citedLineIndexes: [Int] = []
        var modelPreferences: [Int?] = []
        var scores: [[Double]] = []
        for (offset, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            let matches = expression.matches(in: line, range: range)
            guard !matches.isEmpty else { continue }
            let plain = expression.stringByReplacingMatches(in: line, range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let tokens = Self.tokens(plain)
            let preferred: Int? = {
                guard let match = matches.first,
                      let group = Range(match.range(at: 1), in: line) else { return nil }
                let parts = line[group].split(separator: ",").compactMap {
                    Int($0.trimmingCharacters(in: .whitespaces))
                }
                return parts.first
            }()
            citedLineIndexes.append(offset)
            modelPreferences.append(preferred)
            scores.append(sources.map { source in
                tokens.isEmpty ? 0 : Self.score(tokens: tokens, source: source)
            })
        }
        let assigned = supportedAssignments(
            scores: scores,
            modelPreferences: modelPreferences,
            indexToOffset: indexToOffset
        )
        var resultLines = lines
        for (slot, lineIndex) in citedLineIndexes.enumerated() {
            let chosen: Int?
            if slot < assigned.count, let sourceOffset = assigned[slot] {
                chosen = sources[sourceOffset].index
            } else {
                chosen = nil
            }
            resultLines[lineIndex] = applyIndex(
                resultLines[lineIndex],
                chosen: chosen,
                valid: Set(sources.map(\.index)),
                expression: expression
            )
        }
        return resultLines.joined(separator: "\n")
    }

    /// Keep the model's chip when that source is supported; else best overlap.
    /// No balancing or round-robin — unsupported chips are still dropped.
    static func supportedAssignments(
        scores: [[Double]],
        modelPreferences: [Int?],
        indexToOffset: [Int: Int]
    ) -> [Int?] {
        guard !scores.isEmpty else { return [] }
        return scores.enumerated().map { slot, row in
            if slot < modelPreferences.count,
               let preferredIndex = modelPreferences[slot],
               let offset = indexToOffset[preferredIndex],
               offset < row.count,
               row[offset] >= minimumSupportScore {
                return offset
            }
            var bestSource: Int?
            var bestScore = 0.0
            for (source, score) in row.enumerated() where score > bestScore {
                bestScore = score
                bestSource = source
            }
            guard bestScore >= minimumSupportScore else { return nil }
            return bestSource
        }
    }

    /// Per-line best overlap. Kept for call sites/tests that still import it.
    static func bestOverlapAssignments(scores: [[Double]]) -> [Int?] {
        supportedAssignments(scores: scores, modelPreferences: [], indexToOffset: [:])
    }

    /// Legacy name kept for call sites/tests that still import the old API.
    static func uniqueAssignments(scores: [[Double]], sourceCount: Int) -> [Int?] {
        _ = sourceCount
        return bestOverlapAssignments(scores: scores)
    }

    private static func applyIndex(
        _ line: String,
        chosen: Int?,
        valid: Set<Int>,
        expression: NSRegularExpression
    ) -> String {
        let range = NSRange(line.startIndex..., in: line)
        let matches = expression.matches(in: line, range: range)
        guard !matches.isEmpty else { return line }
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
            if let chosen {
                // Honest remapping: every marker on the line points at the
                // best-overlap source for that line (repeats allowed).
                result += "[\(chosen)]"
            } else {
                // No supporting source — drop the chip entirely.
                _ = valid
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
        return bestScore >= minimumSupportScore ? best : nil
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
        "gathered", "major", "global", "events", "reports", "available", "drawn",
        "summaries", "these", "here", "some",
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
