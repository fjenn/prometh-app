import SwiftUI

// Layout adapted from Goose ToolApprovalButtons (Apache-2.0, block/goose) and LibreChat ToolApproval (MIT).
struct ConnectorApprovalCard: View {
    @ObservedObject var store: PromethStore
    let messageID: UUID
    let card: ConnectorCard

    private var app: String { card.appName ?? PromethConnectorDescription.appName(card.toolkit) }

    var body: some View {
        Group {
            if card.phase == "awaitingConsent" {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ToolkitLogo(toolkit: ComposioToolkit(
                            slug: card.toolkit, name: app, description: "",
                            logo: card.logoURL.flatMap(URL.init(string:)), categories: []
                        ))
                        Text(app).font(.system(size: 14, weight: .medium))
                    }
                    Text([card.summary, card.detail ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 14)).lineLimit(1).truncationMode(.tail)
                    Text("Prometh will do this in \(app) for you.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("Always allow remembers only this action in \(app).")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button("Allow once") { store.allowConnectorOnce(messageID) }
                            .buttonStyle(PrimaryButton())
                            .accessibilityIdentifier("prometh.connector.allowOnce")
                        Button("Always allow") { store.alwaysAllowConnector(messageID) }
                            .buttonStyle(.plain).padding(.horizontal, 13).padding(.vertical, 9)
                            .overlay(Capsule().strokeBorder(.primary.opacity(0.15)))
                            .accessibilityIdentifier("prometh.connector.alwaysAllow")
                        Button("Don't allow") { store.declineConnector(messageID) }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .accessibilityIdentifier("prometh.connector.decline")
                    }
                    .font(.system(size: 13, weight: .medium))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.07), lineWidth: 1))
            } else {
                Label("\(card.decision ?? "Allowed once") · \(card.summary)",
                      systemImage: card.phase == "declined" ? "xmark.circle" : "checkmark.circle")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("prometh.connector.card")
    }
}
