import Foundation

/// Chat-bubble markdown: bold, inline code, and bullet lists.
/// Citation markers stay in the text so the bubble can turn them into chips.
enum PromethMarkdown {
    enum Span: Equatable, Sendable {
        case text(String)
        case strong(String)
        case code(String)
    }

    enum Block: Equatable, Sendable {
        case paragraph([Span])
        case bullet([Span])
    }

    static func blocks(in text: String) -> [Block] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var blocks: [Block] = []
        var paragraph: [String] = []

        func flush() {
            let joined = paragraph.joined(separator: "\n")
            paragraph.removeAll(keepingCapacity: true)
            let spans = inline(joined)
            if !spans.isEmpty {
                blocks.append(.paragraph(spans))
            }
        }

        for line in normalized.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
                continue
            }
            if let body = bulletBody(line) {
                flush()
                let spans = inline(body)
                blocks.append(.bullet(spans.isEmpty ? [.text("")] : spans))
                continue
            }
            paragraph.append(line)
        }
        flush()
        return blocks
    }

    static func bulletBody(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for prefix in ["- ", "* ", "• "] where trimmed.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count))
        }
        return nil
    }

    static func inline(_ line: String) -> [Span] {
        var spans: [Span] = []
        var cursor = line.startIndex

        func pushText(_ value: String) {
            guard !value.isEmpty else { return }
            if case .text(let existing) = spans.last {
                spans.removeLast()
                spans.append(.text(existing + value))
            } else {
                spans.append(.text(value))
            }
        }

        while cursor < line.endIndex {
            if line[cursor...].hasPrefix("**") {
                let start = line.index(cursor, offsetBy: 2)
                if let end = line[start...].range(of: "**") {
                    let inner = String(line[start..<end.lowerBound])
                    if !inner.isEmpty {
                        spans.append(.strong(inner))
                    }
                    cursor = end.upperBound
                    continue
                }
            }
            if line[cursor] == "`" {
                let start = line.index(after: cursor)
                if start < line.endIndex, let end = line[start...].firstIndex(of: "`") {
                    let inner = String(line[start..<end])
                    if !inner.isEmpty {
                        spans.append(.code(inner))
                    }
                    cursor = line.index(after: end)
                    continue
                }
            }
            let next = line.index(after: cursor)
            pushText(String(line[cursor..<next]))
            cursor = next
        }
        return spans
    }
}
