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
    /// Uses a global unique-first pass so several bullets over several sources
    /// become `[1]`, `[2]`, `[3]`… instead of every chip collapsing to one index.
    static func remapCitations(_ reply: String, sources: [Source]) -> String {
        guard !sources.isEmpty else { return stripCitations(reply) }
        guard let expression = try? NSRegularExpression(pattern: #"\[(\d+(?:\s*,\s*\d+)*)\]"#) else {
            return reply
        }
        let lines = reply.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var citedLineIndexes: [Int] = []
        var scores: [[Double]] = []
        for (offset, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            let matches = expression.matches(in: line, range: range)
            guard !matches.isEmpty else { continue }
            let plain = expression.stringByReplacingMatches(in: line, range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let tokens = Self.tokens(plain)
            citedLineIndexes.append(offset)
            scores.append(sources.map { source in
                tokens.isEmpty ? 0 : Self.score(tokens: tokens, source: source)
            })
        }
        let assigned = uniqueAssignments(scores: scores, sourceCount: sources.count)
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

    /// Greedy unique assignment: highest scores first; prefer unused sources so
    /// chips diversify across the Sources row. After every source is used once,
    /// reuse is allowed for remaining lines.
    static func uniqueAssignments(scores: [[Double]], sourceCount: Int) -> [Int?] {
        guard sourceCount > 0, !scores.isEmpty else {
            return Array(repeating: nil, count: scores.count)
        }
        var assignment: [Int?] = Array(repeating: nil, count: scores.count)
        var usedSources: Set<Int> = []
        // Edges sorted by score descending, then by line order for stability.
        var edges: [(line: Int, source: Int, score: Double)] = []
        for (line, row) in scores.enumerated() {
            for (source, score) in row.enumerated() where score >= 1.0 {
                edges.append((line, source, score))
            }
        }
        edges.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.line != $1.line { return $0.line < $1.line }
            return $0.source < $1.source
        }
        // Pass 1: unique sources only.
        for edge in edges {
            if assignment[edge.line] != nil { continue }
            if usedSources.contains(edge.source) { continue }
            assignment[edge.line] = edge.source
            usedSources.insert(edge.source)
        }
        // Pass 2: remaining lines take their absolute best (reuse allowed).
        for (line, row) in scores.enumerated() where assignment[line] == nil {
            var bestSource: Int?
            var bestScore = 0.0
            for (source, score) in row.enumerated() where score > bestScore {
                bestScore = score
                bestSource = source
            }
            if bestScore >= 1.0 {
                assignment[line] = bestSource
            }
        }
        // Pass 3: any still-unassigned cited line gets a round-robin source so
        // out-of-range / all-[n] model output cannot collapse the Sources row.
        if sourceCount > 0 {
            var cursor = 0
            for line in scores.indices where assignment[line] == nil {
                assignment[line] = cursor % sourceCount
                cursor += 1
            }
        }
        // Pass 4: if every assigned chip is the same source while multiple
        // sources exist, force round-robin so chips are distinct.
        let assignedValues = assignment.compactMap { $0 }
        if sourceCount > 1,
           assignedValues.count > 1,
           Set(assignedValues).count == 1 {
            for (line, _) in scores.enumerated() {
                assignment[line] = line % sourceCount
            }
        }
        return assignment
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
        // Multiple markers on one line (e.g. "on [2] and [2]") get distinct
        // unused indices when a single chosen index would otherwise repeat.
        let markers = matches.count
        var result = ""
        var cursor = line.startIndex
        var slot = 0
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
                if markers > 1, valid.count > 1 {
                    // Spread multi-marker lines across 1…N in order.
                    let ordered = valid.sorted()
                    let index = ordered[slot % ordered.count]
                    result += "[\(index)]"
                } else {
                    result += "[\(chosen)]"
                }
            } else {
                let kept = parts.filter { valid.contains($0) }
                if kept.count == 1 {
                    result += "[\(kept[0])]"
                } else if kept.count > 1 {
                    result += kept.map { "[\($0)]" }.joined()
                }
            }
            slot += 1
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
