import Foundation

/// Builds the prefetched search + page-read block that reaches the model.
enum PromethSearchContext {
    struct Result: Equatable, Sendable {
        var title: String
        var url: String
        var snippet: String
    }

    struct Hit: Equatable, Sendable {
        var index: Int
        var title: String
        var url: String
        var snippet: String
        var body: String
    }

    /// Prefer article-like paths over bare homepage URLs when both exist.
    static func preferReadable(_ results: [Result], limit: Int = 4) -> [Result] {
        let articles = results.filter(isArticleURL)
        let ordered = articles.isEmpty ? results : articles + results.filter { !isArticleURL($0) }
        var seen: Set<String> = []
        var picked: [Result] = []
        for result in ordered {
            guard seen.insert(result.url).inserted else { continue }
            picked.append(result)
            if picked.count == limit { break }
        }
        return picked
    }

    /// Pick up to `limit` results from distinct registrable hosts so news answers
    /// are not trapped on a single aggregator domain (every chip becoming `[1]`).
    static func preferDistinctDomains(_ results: [Result], limit: Int = 5) -> [Result] {
        let articles = results.filter(isArticleURL)
        let ordered = articles.isEmpty ? results : articles + results.filter { !isArticleURL($0) }
        var seenURL: Set<String> = []
        var seenHost: Set<String> = []
        var picked: [Result] = []
        for result in ordered {
            guard seenURL.insert(result.url).inserted else { continue }
            let host = normalizedHost(result.url)
            if !host.isEmpty, !seenHost.insert(host).inserted { continue }
            picked.append(result)
            if picked.count == limit { break }
        }
        return picked
    }

    /// Rebuild hits from the selected pages only, reindexed from 1 so `[n]` chips
    /// match the Sources row. Pages with body text come first; empty slots stay so
    /// the Sources row still lists several distinct domains.
    static func indexedHits(
        selected: [Result],
        bodies: [String: (title: String?, content: String)]
    ) -> [Hit] {
        var withBody: [Hit] = []
        var withoutBody: [Hit] = []
        for result in selected {
            let page = bodies[result.url]
            let title = page?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let content = page?.content ?? ""
            let hit = Hit(
                index: 0,
                title: (title?.isEmpty == false ? title! : result.title),
                url: result.url,
                snippet: result.snippet,
                body: content
            )
            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                withoutBody.append(hit)
            } else {
                withBody.append(hit)
            }
        }
        return (withBody + withoutBody).enumerated().map { offset, hit in
            Hit(
                index: offset + 1,
                title: hit.title,
                url: hit.url,
                snippet: hit.snippet,
                body: hit.body
            )
        }
    }

    static func normalizedHost(_ urlString: String) -> String {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return "" }
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }

    static func searchQuery(from text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let strip = [
            #"cite sources\.?"#,
            #"use\s+\*\*bold\*\*\s+for one headline word\.?"#,
            #"use bold for one headline word\.?"#,
        ]
        for pattern in strip {
            value = value.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = value.lowercased()
        if lowered.contains("news") || lowered.contains("what happened") || lowered.contains("current events") {
            return "top world news headlines today"
        }
        return String(value.prefix(300))
    }

    static func promptNote(hits: [Hit], date: Date = Date()) -> String {
        guard !hits.isEmpty else { return "" }
        let today = date.formatted(date: .complete, time: .omitted)
        let block = CitationMarkup.searchResultsBlock(
            hits.map { CitationMarkup.Item(title: $0.title, url: $0.url) }
        )
        var sections: [String] = [
            "Searched the web for this question on \(today). The pages below were fetched with the local reader. Cite them with [n]. When \(hits.count) results are listed, use several different indices (for example [1], [2], [3]) — never reuse [1] for every fact. Summarize 3–5 concrete headlines from the page text; do not only list site names or tell the user to visit the links.",
            block,
        ]
        for hit in hits {
            var page = "[\(hit.index)] \(hit.title)\n\(hit.url)"
            if !hit.snippet.isEmpty {
                page += "\nSnippet: \(hit.snippet)"
            }
            let body = excerpt(hit.body)
            if !body.isEmpty {
                page += "\nPage text:\n\(body)"
            }
            sections.append(page)
        }
        return sections.joined(separator: "\n\n")
    }

    static func excerpt(_ text: String, limit: Int = 2_400) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count <= limit { return trimmed }
        return String(trimmed.prefix(limit - 1)) + "…"
    }

    private static func isArticleURL(_ result: Result) -> Bool {
        guard let url = URL(string: result.url), let host = url.host?.lowercased() else { return false }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty { return false }
        let aggregators = ["news.google.com", "news.yahoo.com", "msn.com"]
        if aggregators.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return path.contains("/")
        }
        return true
    }
}
