import AppKit
import SwiftUI

enum PromethSearchCredits {
    static let searxngSourceURL = "https://github.com/searxng/searxng/tree/1412926f5c80ffabc90719450578eb98fda9e161"
}

struct PromethCitationText: View {
    let text: String
    let links: [SourceLink]?

    var body: some View {
        WrappingCitationText(text: text, links: links ?? [])
            .font(.system(size: 15))
            .lineSpacing(6)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Inline `[n]` chips in the sky accent. Markers without a source are dropped.
private struct WrappingCitationText: View {
    let text: String
    let links: [SourceLink]

    var body: some View {
        Text(Self.pieces(text: text, links: links))
    }

    private static func pieces(text: String, links: [SourceLink]) -> AttributedString {
        let blocks = PromethMarkdown.blocks(in: text)
        guard !blocks.isEmpty else { return AttributedString(text) }
        var result = AttributedString()
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                result.append(AttributedString("\n"))
            }
            switch block {
            case .paragraph(let spans):
                result.append(rendered(spans, links: links, bullet: false))
            case .bullet(let spans):
                result.append(rendered(spans, links: links, bullet: true))
            }
        }
        return result
    }

    private static func rendered(_ spans: [PromethMarkdown.Span], links: [SourceLink], bullet: Bool) -> AttributedString {
        var result = AttributedString()
        if bullet {
            result.append(AttributedString("• "))
        }
        for span in spans {
            switch span {
            case .text(let value):
                result.append(cited(value, links: links, strong: false))
            case .strong(let value):
                result.append(cited(value, links: links, strong: true))
            case .code(let value):
                var code = AttributedString(value)
                code.font = .system(size: 13, design: .monospaced)
                result.append(code)
            }
        }
        return result
    }

    /// A single `[n]` marker becomes a sky chip. A marker with no source is dropped.
    private static func cited(_ text: String, links: [SourceLink], strong: Bool) -> AttributedString {
        let known = Set(links.compactMap(\.index))
        guard let expression = try? NSRegularExpression(pattern: "\\[(\\d+)\\]") else {
            return styled(text, strong: strong)
        }
        let ns = text as NSString
        let matches = expression.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var result = AttributedString()
        var cursor = 0
        for match in matches {
            let whole = match.range
            if whole.location > cursor {
                result.append(styled(ns.substring(with: NSRange(location: cursor, length: whole.location - cursor)), strong: strong))
            }
            let number = Int(ns.substring(with: match.range(at: 1))) ?? 0
            if known.isEmpty || known.contains(number) {
                var chip = AttributedString(" \(number) ")
                chip.font = .system(size: 10, weight: .semibold)
                chip.foregroundColor = Color.sky
                chip.backgroundColor = Color.sky.opacity(0.18)
                if let link = links.first(where: { $0.index == number }), let url = URL(string: link.url) {
                    chip.link = url
                }
                result.append(chip)
            }
            cursor = whole.location + whole.length
        }
        if cursor < ns.length {
            result.append(styled(ns.substring(from: cursor), strong: strong))
        }
        return result
    }

    private static func styled(_ text: String, strong: Bool) -> AttributedString {
        var value = AttributedString(text)
        if strong {
            value.font = .system(size: 15, weight: .semibold)
        }
        return value
    }
}

struct PromethSourcesRow: View {
    let links: [SourceLink]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(links) { link in
                        Button {
                            if let url = URL(string: link.url) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            card(link)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(label(link))
                    }
                }
            }
        }
    }

    private func card(_ link: SourceLink) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(link.index ?? 0)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.sky)
                .frame(width: 18, height: 18)
                .background(Color.sky.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(link.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                Text(Self.domain(link.url)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                if let published = link.published, !published.isEmpty {
                    Text(published).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(10)
        .frame(width: 220, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    private func label(_ link: SourceLink) -> String {
        "Source \(link.index ?? 0), \(link.title), \(Self.domain(link.url))"
    }

    private static func domain(_ url: String) -> String {
        URL(string: url)?.host ?? url
    }
}
