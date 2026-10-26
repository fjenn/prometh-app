import Foundation

enum SourcesExtractor {
    static func links(
        before messageID: UUID,
        in messages: [ChatTranscriptMessage],
        assistantText: String
    ) -> [SourceLink]? {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return nil }
        var found: [SourceLink] = []
        var dates: [String: String] = [:]
        var cursor = index - 1
        while cursor >= 0 {
            let message = messages[cursor]
            if message.role == .user { break }
            if message.role == .tool, message.toolName == "web_search" {
                found = decodeSearch(message.content) + found
            }
            if message.role == .tool, message.toolName == "web_read" {
                dates.merge(decodeReadDates(message.content)) { current, _ in current }
            }
            cursor -= 1
        }
        guard !found.isEmpty else { return nil }
        let logged = logDates()
        let numbered = found.enumerated().map { offset, link in
            SourceLink(
                title: link.title,
                url: link.url,
                index: offset + 1,
                published: dates[link.url] ?? logged[link.url]
            )
        }
        let cited = citedIndices(in: assistantText)
        let shown = cited.isEmpty ? numbered : numbered.filter { cited.contains($0.index ?? 0) }
        return shown.isEmpty ? nil : shown
    }

    private static func decodeSearch(_ content: String) -> [SourceLink] {
        let json = content.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? content
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(SearchPayload.self, from: data) else {
            return []
        }
        return payload.results.map { SourceLink(title: $0.title, url: $0.url) }
    }

    private static func decodeReadDates(_ content: String) -> [String: String] {
        guard let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pages = (object["pages"] as? [[String: Any]]) ?? (object["results"] as? [[String: Any]]) else {
            return [:]
        }
        var dates: [String: String] = [:]
        for page in pages {
            guard let url = page["url"] as? String, let body = page["content"] as? String else { continue }
            if let date = publishedDate(in: body) {
                dates[url] = date
            }
        }
        return dates
    }

    private static func publishedDate(in text: String) -> String? {
        let prefix = "Published: "
        guard text.hasPrefix(prefix) else { return nil }
        let rest = text.dropFirst(prefix.count)
        let token = rest.prefix { $0 != "\n" }
        return token.isEmpty ? nil : String(token)
    }

    private static func logDates() -> [String: String] {
        var dates: [String: String] = [:]
        for line in ReaderLog.entries() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 6, !fields[3].isEmpty else { continue }
            dates[fields[5]] = fields[3]
        }
        return dates
    }

    private static func citedIndices(in text: String) -> Set<Int> {
        guard let expression = try? NSRegularExpression(pattern: "\\[(\\d+)\\]") else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return Set(expression.matches(in: text, range: range).compactMap { match in
            guard let slice = Range(match.range(at: 1), in: text) else { return nil }
            return Int(text[slice])
        })
    }
}

private struct SearchPayload: Decodable {
    let results: [SearchItem]
}

private struct SearchItem: Decodable {
    let title: String
    let url: String
}
