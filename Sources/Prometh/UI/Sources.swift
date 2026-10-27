import AppKit
import SwiftUI

enum PromethSearchCredits {
    static let searxngSourceURL = "https://github.com/searxng/searxng/tree/1412926f5c80ffabc90719450578eb98fda9e161"
}

struct PromethCitationText: View {
    let text: String
    let links: [SourceLink]?
    var onCite: (Int) -> Void = { _ in }

    var body: some View {
        Text(PromethReplyMarkup.attributed(
            markdown: text,
            cited: Set((links ?? []).compactMap(\.index))
        ))
            .font(.system(size: 15))
            .lineSpacing(6)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "prometh-cite", let host = url.host, let number = Int(host) else {
                    return .systemAction
                }
                onCite(number)
                return .handled
            })
    }
}

struct PromethSourcesRow: View {
    let links: [SourceLink]
    var messageID: UUID?
    var focused: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sources").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            ScrollViewReader { proxy in
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
                            .id(anchor(link))
                        }
                    }
                }
                .onChange(of: focused) { _, number in
                    guard let number else { return }
                    withAnimation { proxy.scrollTo(anchor(number), anchor: .center) }
                }
            }
        }
    }

    private func anchor(_ link: SourceLink) -> String { anchor(link.index ?? 0) }

    private func anchor(_ index: Int) -> String {
        "\(messageID?.uuidString ?? "sources")-\(index)"
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
        .overlay {
            if focused == link.index {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.sky, lineWidth: 1.5)
            }
        }
    }

    private func label(_ link: SourceLink) -> String {
        "Source \(link.index ?? 0), \(link.title), \(Self.domain(link.url))"
    }

    private static func domain(_ url: String) -> String {
        URL(string: url)?.host ?? url
    }
}
