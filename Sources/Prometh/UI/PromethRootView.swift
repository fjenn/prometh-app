import AppKit
import SwiftUI

struct PromethRootView: View {
    @StateObject private var store: PromethStore
    @Environment(\.colorScheme) private var scheme

    init(model: NativModel) {
        _store = StateObject(wrappedValue: PromethStore(model: model))
    }

    var body: some View {
        Group {
            if store.state.onboardingComplete {
                WorkspaceView(store: store)
            } else {
                OnboardingView(store: store)
            }
        }
        .tint(scheme == .dark ? Color.lavender : Color(hex: PromethDesign.appTintLight))
        .frame(minWidth: PromethDesign.windowMinWidth, minHeight: PromethDesign.windowMinHeight)
        .preferredColorScheme(colorScheme)
        .accessibilityIdentifier("prometh.root")
        .onAppear(perform: placeWindowOnScreen)
        .onReceive(NotificationCenter.default.publisher(for: .promethNewChat)) { _ in
            if store.state.onboardingComplete { store.newChat() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .promethOpenSettings)) { _ in
            store.settingsOpen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .promethOpenCustomize)) { _ in
            store.openCustomize()
        }
        .sheet(isPresented: $store.settingsOpen) { PromethSettingsView(store: store) }
        .sheet(isPresented: $store.customizeOpen) { CustomizeView(store: store) }
        .sheet(item: consentBinding) { provider in
            ConsentView(store: store, provider: provider)
        }
        .sheet(item: $store.previewArtifact) { artifact in
            PromethArtifactPreview(store: store, artifact: artifact)
        }
        .sheet(item: $store.previewAttachment) { attachment in
            AttachmentPreview(store: store, attachment: attachment)
        }
        .overlay(alignment: .top) {
            if let message = store.error {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                    Text(message).font(.system(size: 12))
                    Spacer()
                    Button("Dismiss") { store.error = nil }.buttonStyle(.borderless)
                }
                .padding(15)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.orange.opacity(0.25)))
                .padding(20)
                .frame(maxWidth: 720)
                .shadow(radius: 12)
            }
        }
    }

    private func placeWindowOnScreen() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: \.canBecomeMain) ?? NSApp.windows.first else { return }
            let screen = NSScreen.main ?? NSScreen.screens.first
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let size = reviewFrame() ?? NSSize(width: min(1280, visible.width - 40), height: min(830, visible.height - 40))
            let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
            window.setFrame(NSRect(origin: origin, size: size), display: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// `--prometh-frame=1280x860` is the review window size, including the title bar.
    private func reviewFrame() -> NSSize? {
        guard let spec = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--prometh-frame=") }) else { return nil }
        let parts = spec.dropFirst("--prometh-frame=".count).split(separator: "x")
        guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]), width >= 960, height >= 650 else { return nil }
        return NSSize(width: width, height: height)
    }

    private var colorScheme: ColorScheme? {
        switch store.state.appearance {
        case "Dark": .dark
        case "Light": .light
        default: nil
        }
    }

    private var consentBinding: Binding<Provider?> {
        Binding(
            get: { store.settingsOpen || store.customizeOpen ? nil : store.consent },
            set: { if !store.settingsOpen && !store.customizeOpen { store.consent = $0 } }
        )
    }
}

extension Notification.Name {
    static let promethNewChat = Notification.Name("prometh.newChat")
    static let promethOpenSettings = Notification.Name("prometh.openSettings")
    static let promethOpenCustomize = Notification.Name("prometh.openCustomize")
}
