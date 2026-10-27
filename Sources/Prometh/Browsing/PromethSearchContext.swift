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

    /// Rebuild hits from pages that were actually read (non-empty body), reindexed
    /// from 1 so `[n]` chips match the Sources row. Unread search snippets are omitted.
    static func indexedHits(
        selected: [Result],
        bodies: [String: (title: String?, content: String)]
    ) -> [Hit] {
        var withBody: [Hit] = []
        for result in selected {
            let page = bodies[result.url]
            let content = page?.content ?? ""
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let pageTitle = page?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = PromethHTML.decode(
                (pageTitle?.isEmpty == false ? pageTitle! : result.title)
            )
            withBody.append(Hit(
                index: 0,
                title: title,
                url: result.url,
                snippet: PromethHTML.decode(result.snippet),
                body: content
            ))
        }
        return withBody.enumerated().map { offset, hit in
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
        // Only pages with fetched body text may be numbered sources.
        let read = hits.filter { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !read.isEmpty else { return "" }
        let today = date.formatted(date: .complete, time: .omitted)
        let named = read.map { "[\($0.index)] \($0.title)" }.joined(separator: "; ")
        let block = CitationMarkup.searchResultsBlock(
            read.map { CitationMarkup.Item(title: $0.title, url: $0.url) }
        )
        var sections: [String] = [
            """
            Searched the web for this question on \(today). The pages below were fetched with the local reader. \
            These are the only sources you may cite or name: \(named). Do not mention any other outlet, site, or publisher. \
            Cite them with [n]. State only facts present in the Page text below — never invent claims that are not there. \
            Cite each fact with the index of the page that contains it; reusing the same [n] is fine when one page supports several facts. \
            Summarize 3–5 concrete headlines from the page text; do not only list site names or tell the user to visit the links.
            """,
            block,
        ]
        for hit in read {
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
