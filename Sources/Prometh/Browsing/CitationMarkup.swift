import Foundation

/// `<search_results>` block shared by the web_search tool and the Sources row.
enum CitationMarkup {
    struct Item: Equatable, Sendable {
        var title: String
        var url: String
    }

    static func searchResultsBlock(_ items: [Item]) -> String {
        var lines = ["<search_results>"]
        for (index, item) in items.enumerated() {
            let title = xmlAttribute(item.title)
            let url = xmlAttribute(item.url)
            lines.append("<result index=\"\(index + 1)\" title=\"\(title)\" url=\"\(url)\" />")
        }
        lines.append("</search_results>")
        return lines.joined(separator: "\n")
    }

    static func citedIndices(in text: String) -> Set<Int> {
        guard let expression = try? NSRegularExpression(pattern: "\\[(\\d+)\\]") else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return Set(expression.matches(in: text, range: range).compactMap { match in
            guard let slice = Range(match.range(at: 1), in: text) else { return nil }
            return Int(text[slice])
        })
    }

    static func xmlAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
