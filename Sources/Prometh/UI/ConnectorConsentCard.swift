import AppKit
import SwiftUI

/// Inline chat card for connected-app write approvals.
struct ConnectorConsentCard: View {
    @ObservedObject var store: PromethStore
    let messageID: UUID
    let card: ConnectorCard
    @Environment(\.colorScheme) private var scheme
    @State private var logo: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                logoView
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.summary)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    phaseCaption
                }
                Spacer(minLength: 0)
            }
            if card.phase == "awaitingConsent" {
                HStack(spacing: 10) {
                    Button("Allow once") { store.allowConnectorOnce(messageID) }
                        .buttonStyle(.borderedProminent)
                        .tint(.promethInk)
                        .accessibilityLabel("Allow once")
                        .accessibilityIdentifier("prometh.connector.allowOnce")
                    Button("Always allow") { store.alwaysAllowConnector(messageID) }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Always allow")
                        .accessibilityIdentifier("prometh.connector.alwaysAllow")
                    Button("Don't allow") { store.denyConnector(messageID) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Don't allow")
                        .accessibilityIdentifier("prometh.connector.deny")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 13, weight: .medium))
            }
        }
        .padding(16)
        .frame(maxWidth: 520, alignment: .leading)
        .background(
            (scheme == .dark
                ? Color(hex: PromethDesign.readingSurfaceDark)
                : Color(hex: PromethDesign.readingSurfaceLight)
            ).opacity(scheme == .dark ? 1 : 0.92),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("prometh.connector.card")
        .task(id: card.logoURL) { await loadLogo() }
    }

    @ViewBuilder private var phaseCaption: some View {
        switch card.phase {
        case "awaitingConsent":
            Text("Connected app action")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case "declined":
            Text("Not allowed")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        case "running", "preparing":
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Running…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        case "succeeded":
            Text("Done")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.sage)
        case "failed", "cancelled":
            Text("Couldn't complete")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private var logoView: some View {
        Group {
            if let logo {
                Image(nsImage: logo).resizable().scaledToFit()
            } else {
                Text(String(card.toolkit.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 28, height: 28)
        .padding(6)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }

    private func loadLogo() async {
        logo = nil
        guard let raw = card.logoURL, let url = URL(string: raw) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200, !Task.isCancelled else { return }
            logo = NSImage(data: data)
        } catch {
            // Monogram fallback remains.
        }
    }
}
