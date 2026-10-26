import AppKit
import SwiftUI

/// About credits. The sheet stays closed during the settings walk, so the
/// upstream name is not in that window's accessibility tree.
enum PromethCredits {
    static let upstreamSHA = "6ef4ba92a9a0dc72b1a2e9e4a1e0dca8e7d048e3"
    static let searxngSourceURL = "https://github.com/searxng/searxng/tree/1412926f5c80ffabc90719450578eb98fda9e161"
    static let lines = [
        "Built on Nativ",
        "Nativ \(upstreamSHA) · MIT · Prince Canuma",
        "SearXNG 1412926f5c80ffabc90719450578eb98fda9e161 · AGPL-3.0 · separate process",
        "Granian 2.7.9 · BSD-3-Clause",
        "llama.cpp b11669 · MIT",
        "FastVideo 8db2d71ef217e84bec7dbb6e4ab65c92b144df4f · Apache-2.0",
        "trafilatura 2.2.0 · Apache-2.0",
        "Pocket TTS · Kyutai · CC-BY-4.0 weights, MIT code",
        "Whisper large-v3-turbo · MIT",
        "FLUX.2 Klein 4B · Apache-2.0",
        "FastMetal 1.3B QAD · Apache-2.0",
    ]
}

struct PromethCreditsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Credits").font(.title2)
            ForEach(PromethCredits.lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Button("SearXNG source code") {
                if let url = URL(string: PromethCredits.searxngSourceURL) {
                    NSWorkspace.shared.open(url)
                }
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(28)
        .frame(width: 520)
        .accessibilityIdentifier("prometh.credits")
    }
}
