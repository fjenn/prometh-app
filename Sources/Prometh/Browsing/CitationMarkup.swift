import Foundation
import SwiftUI

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

    /// `[1]`, `[1][4]`, and `[1, 4]` all count. The model often writes the last form.
    static func citedIndices(in text: String) -> Set<Int> {
        guard let expression = try? NSRegularExpression(pattern: #"\[(\d+(?:\s*,\s*\d+)*)\]"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var indices: Set<Int> = []
        for match in expression.matches(in: text, range: range) {
            guard let slice = Range(match.range(at: 1), in: text) else { continue }
            for part in text[slice].split(separator: ",") {
                if let number = Int(part.trimmingCharacters(in: .whitespaces)) {
                    indices.insert(number)
                }
            }
        }
        return indices
    }

    static func xmlAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// Sidebar titles use the first user prompt. A second prompt glued on with no
/// space, or the same prompt repeated, does not become part of the title.
enum PromethChatTitle {
    static func display(customTitle: String?, firstUserText: String?, fallback: String) -> String {
        if let customTitle {
            let trimmed = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        guard let firstUserText else { return fallback }
        let prompt = firstPrompt(firstUserText)
        return prompt.isEmpty ? fallback : prompt
    }

    static func firstPrompt(_ text: String) -> String {
        var value = collapseExactRepeat(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if let boundary = value.range(of: #"(?<=[.!?])(?=\p{Lu})"#, options: .regularExpression) {
            value = String(value[..<boundary.lowerBound])
        }
        value = value.split(whereSeparator: \.isNewline).first.map {
            String($0).trimmingCharacters(in: .whitespaces)
        } ?? value
        return truncate(value)
    }

    /// "Hello?Hello?" is one send that captured the draft twice.
    static func collapseExactRepeat(_ text: String) -> String {
        guard text.count >= 2, text.count.isMultiple(of: 2) else { return text }
        let mid = text.index(text.startIndex, offsetBy: text.count / 2)
        let head = text[..<mid]
        return head == text[mid...] ? String(head) : text
    }

    static func truncate(_ value: String, maxLength: Int = 56) -> String {
        guard value.count > maxLength else { return value }
        return "\(value.prefix(maxLength - 1))…"
    }
}

/// Tool-call rows are stored with an empty assistant body. That body is not a reply.
enum PromethVisibleReply {
    static let retry = "I didn't get that out. Please try again."

    /// Tool statuses that mean the turn is still working (approval sheet, prepare, run).
    static let inFlightToolStatuses: Set<String> = [
        "awaitingConsent", "preparing", "running",
    ]

    struct Row: Equatable {
        var text: String
        var status: String
        var omit: Bool
    }

    /// Lightweight turn slice for `turnInFlight` — keeps the helper pure and testable.
    struct TurnSnapshot: Equatable {
        var id: UUID
        var isUser: Bool
        var isTool: Bool
        var toolStatus: String?
    }

    /// True while the session request is active, or a later tool in the same turn is
    /// awaiting consent / preparing / running (before the next user message).
    static func turnInFlight(
        after messageID: UUID,
        in messages: [TurnSnapshot],
        requestActive: Bool
    ) -> Bool {
        if requestActive { return true }
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return false }
        guard index + 1 < messages.count else { return false }
        for later in messages[(index + 1)...] {
            if later.isUser { break }
            if later.isTool,
               let status = later.toolStatus,
               inFlightToolStatuses.contains(status) {
                return true
            }
        }
        return false
    }

    static func row(
        content: String,
        streaming: Bool,
        hasToolCalls: Bool,
        laterAnswer: Bool,
        turnInFlight: Bool
    ) -> Row {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if streaming {
            return Row(text: content, status: "streaming", omit: false)
        }
        if trimmed.isEmpty, hasToolCalls, laterAnswer {
            return Row(text: "", status: "complete", omit: true)
        }
        // Empty tool-call carrier while approval/run is still open is not a failed reply.
        if trimmed.isEmpty, hasToolCalls, turnInFlight {
            return Row(text: "", status: "complete", omit: true)
        }
        if trimmed.isEmpty {
            return Row(text: retry, status: "failed", omit: false)
        }
        return Row(text: content, status: "complete", omit: false)
    }
}

/// Markdown via `AttributedString`, with `[n]` and `[1, 4]` turned into sky chips.
enum PromethReplyMarkup {
    static func attributed(markdown: String, cited: Set<Int>) -> AttributedString {
        // `.full` drops paragraph breaks (`A.\n\nB` → `A.B`). Keep whitespace and
        // turn list markers into visible bullets before the inline-only parse.
        // ATX headings are rendered as sized bold lines (inline-only ignores `#`).
        var result = AttributedString()
        var segment: [String] = []
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        func flushSegment() {
            guard !segment.isEmpty else { return }
            let chunk = segment.joined(separator: "\n")
            segment.removeAll(keepingCapacity: true)
            let prepared = shield(lists(spacing(chunk)))
            let options = AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
            let parsed = (try? AttributedString(markdown: prepared, options: options)) ?? AttributedString(prepared)
            let chipped = chips(in: parsed, cited: cited)
            if !result.characters.isEmpty {
                result.append(AttributedString("\n"))
            }
            result.append(chipped)
        }

        for line in lines {
            if let heading = atxHeading(line) {
                flushSegment()
                if !result.characters.isEmpty {
                    result.append(AttributedString("\n"))
                }
                result.append(headingAttributed(heading))
            } else {
                segment.append(line)
            }
        }
        flushSegment()
        return result
    }

    struct ATXHeading: Equatable {
        var level: Int
        var text: String
    }

    /// `#`, `##`, `###` (up to six) at line start → heading body without markers.
    static func atxHeading(_ line: String) -> ATXHeading? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        var level = 0
        for character in trimmed {
            guard character == "#" else { break }
            level += 1
            if level > 6 { return nil }
        }
        guard level >= 1, level <= 6 else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.first?.isWhitespace == true else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return ATXHeading(level: level, text: text)
    }

    private static func headingAttributed(_ heading: ATXHeading) -> AttributedString {
        var value = AttributedString(heading.text)
        let size: CGFloat
        switch heading.level {
        case 1: size = 22
        case 2: size = 18
        case 3: size = 16
        default: size = 15
        }
        value.font = .system(size: size, weight: .semibold)
        return value
    }

    /// Soft spaces so emphasis and `[n]` chips are not glued to neighbors.
    static func spacing(_ text: String) -> String {
        var value = text
        let patterns: [(String, String)] = [
            (#"([.!?:,;])(\*\*)"#, "$1 $2"),
            (#"(\*\*)(\[)"#, "$1 $2"),
            (#"(\])(\*\*)"#, "$1 $2"),
            (#"(\])(\p{L})"#, "$1 $2"),
            (#"(\p{L}|\p{N})(\[\d)"#, "$1 $2"),
        ]
        for (pattern, template) in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(value.startIndex..., in: value)
            value = expression.stringByReplacingMatches(in: value, range: range, withTemplate: template)
        }
        return value
    }

    /// `.inlineOnlyPreservingWhitespace` leaves `*` / `-` / `1.` as literal text.
    /// Rewrite those markers into Unicode bullets / numbers with nesting indent.
    static func lists(_ text: String) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: #"^([ \t]*)([-*+]|\d{1,3}\.)[ \t]+(.*)$"#
        ) else { return text }
        let bullets = ["•", "◦", "▪"]
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            let value = String(line)
            let range = NSRange(value.startIndex..., in: value)
            guard let match = expression.firstMatch(in: value, range: range),
                  let indentRange = Range(match.range(at: 1), in: value),
                  let markerRange = Range(match.range(at: 2), in: value),
                  let bodyRange = Range(match.range(at: 3), in: value) else {
                return value
            }
            let indent = value[indentRange]
            let marker = String(value[markerRange])
            let body = String(value[bodyRange])
            let spaces = indent.reduce(0) { partial, character in
                partial + (character == "\t" ? 2 : 1)
            }
            let level = min(spaces / 2, bullets.count - 1)
            let pad = String(repeating: "  ", count: level)
            if marker.hasSuffix(".") {
                return "\(pad)\(marker) \(body)"
            }
            return "\(pad)\(bullets[level]) \(body)"
        }.joined(separator: "\n")
    }

    private static func shield(_ text: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"\[(\d+(?:\s*,\s*\d+)*)\]"#) else {
            return text
        }
        let ns = text as NSString
        let matches = expression.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        var result = ""
        var cursor = 0
        for match in matches {
            let whole = match.range
            if whole.location > cursor {
                result += ns.substring(with: NSRange(location: cursor, length: whole.location - cursor))
            }
            let group = ns.substring(with: match.range(at: 1))
            for part in group.split(separator: ",") {
                if let number = Int(part.trimmingCharacters(in: .whitespaces)) {
                    result += "⟦\(number)⟧"
                }
            }
            cursor = whole.location + whole.length
        }
        if cursor < ns.length {
            result += ns.substring(from: cursor)
        }
        return result
    }

    private static func chips(in parsed: AttributedString, cited: Set<Int>) -> AttributedString {
        let plain = String(parsed.characters)
        guard let expression = try? NSRegularExpression(pattern: "⟦(\\d+)⟧") else { return parsed }
        let matches = expression.matches(in: plain, range: NSRange(plain.startIndex..., in: plain))
        guard !matches.isEmpty else { return parsed }
        var result = AttributedString()
        var cursor = plain.startIndex
        for match in matches {
            guard let whole = Range(match.range, in: plain),
                  let group = Range(match.range(at: 1), in: plain) else { continue }
            if cursor < whole.lowerBound {
                result.append(slice(parsed, plain: plain, from: cursor, to: whole.lowerBound))
            }
            let number = Int(plain[group]) ?? 0
            if cited.isEmpty || cited.contains(number) {
                result.append(chip(number, linked: cited.contains(number)))
            }
            cursor = whole.upperBound
        }
        if cursor < plain.endIndex {
            result.append(slice(parsed, plain: plain, from: cursor, to: plain.endIndex))
        }
        return result
    }

    private static func slice(
        _ text: AttributedString,
        plain: String,
        from: String.Index,
        to: String.Index
    ) -> AttributedString {
        let startOffset = plain.distance(from: plain.startIndex, to: from)
        let endOffset = plain.distance(from: plain.startIndex, to: to)
        let start = text.characters.index(text.startIndex, offsetBy: startOffset)
        let end = text.characters.index(text.startIndex, offsetBy: endOffset)
        return AttributedString(text[start..<end])
    }

    private static let chipSky = Color(.sRGB, red: 131.0 / 255, green: 207.0 / 255, blue: 240.0 / 255, opacity: 1)

    private static func chip(_ number: Int, linked: Bool) -> AttributedString {
        var chip = AttributedString(" \(number) ")
        chip.font = .system(size: 10, weight: .semibold)
        chip.foregroundColor = chipSky
        chip.backgroundColor = chipSky.opacity(0.18)
        if linked {
            chip.link = URL(string: "prometh-cite://\(number)")
        }
        return chip
    }
}
