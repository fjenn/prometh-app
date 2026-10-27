import AppKit
import SwiftUI

/// Tokens from the Prometh reference `Design.swift`. `sovereignInk` is renamed
/// `promethInk` and kept as an alias so ported views can use either name.
enum PromethDesign {
    static let promethInk: UInt32 = 0x292B35
    static let sky: UInt32 = 0x83CFF0
    static let lavender: UInt32 = 0xB8ACE4
    static let coral: UInt32 = 0xF28779
    static let butter: UInt32 = 0xF5CE65
    static let sage: UInt32 = 0xA9CDB4
    static let readingSurfaceLight: UInt32 = 0xFAF9F6
    static let readingSurfaceDark: UInt32 = 0x20232B
    static let sidebarLight: UInt32 = 0xF4F3F1
    static let sidebarDarkTop: UInt32 = 0x29313C
    static let sidebarDarkMid: UInt32 = 0x302D3B
    static let sidebarDarkBottom: UInt32 = 0x2B2E32
    static let settingsLight: UInt32 = 0xF8F7F4
    static let settingsDark: UInt32 = 0x22252B
    static let appTintLight: UInt32 = 0x646491
    static let evilBorderStart: UInt32 = 0xE06B62
    static let evilBorderMid: UInt32 = 0xD4788C
    static let evilBorderEnd: UInt32 = 0xA67BB8
    static let evilReveal: UInt32 = 0x4A090C
    static let destructiveFill: UInt32 = 0x9B292A
    static let chatProgress: UInt32 = 0x3AA0D8
    static let voiceProgress: UInt32 = 0x6E5CC0
    static let imagesProgress: UInt32 = 0xD7A63A
    static let videoProgress: UInt32 = 0xE36B5C
    static let fluidOrbCore: UInt32 = 0xF3FAFF
    static let fluidOrbInner: UInt32 = 0x8ECAF6
    static let fluidOrbMid: UInt32 = 0x4C90EE
    static let fluidOrbOuter: UInt32 = 0x2F6FE4
    static let actionOrbStart: UInt32 = 0x5AA8F6
    static let actionOrbEnd: UInt32 = 0x2F6FE0
    static let voiceBarHeights = [7, 13, 9, 15, 8]
    static let composerRadius: CGFloat = 28
    static let windowMinWidth: CGFloat = 960
    static let windowMinHeight: CGFloat = 650
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 255) / 255,
            green: Double((hex >> 8) & 255) / 255,
            blue: Double(hex & 255) / 255,
            opacity: 1
        )
    }

    static let promethInk = Color(hex: PromethDesign.promethInk)
    static let sovereignInk = promethInk
    static let sky = Color(hex: PromethDesign.sky)
    static let lavender = Color(hex: PromethDesign.lavender)
    static let coral = Color(hex: PromethDesign.coral)
    static let butter = Color(hex: PromethDesign.butter)
    static let sage = Color(hex: PromethDesign.sage)
}

extension Capability {
    var color: Color {
        switch self {
        case .chat: .sky
        case .voice: .lavender
        case .images: .butter
        case .video: .coral
        }
    }
}

struct PrimaryButton: ButtonStyle {
    var coral = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(coral ? Color(hex: PromethDesign.destructiveFill) : .promethInk, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct ContrastButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .background(Color.primary.opacity(configuration.isPressed ? 0.82 : 1), in: Capsule())
    }
}

struct GlassPanel: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) var reduce

    func body(content: Content) -> some View {
        content
            .background {
                if reduce {
                    RoundedRectangle(cornerRadius: 28).fill(Color(nsColor: .windowBackgroundColor))
                } else {
                    RoundedRectangle(cornerRadius: 28).fill(.regularMaterial)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.55), lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 24, y: 12)
    }
}

extension View {
    func glassPanel() -> some View { modifier(GlassPanel()) }
}

struct Brand: View {
    var body: some View {
        Text(Product.name)
            .font(.custom("AvenirNext-DemiBold", size: 22))
            .tracking(-0.45)
    }
}

struct CapabilityIcon: View {
    let capability: Capability
    var size: CGFloat = 40

    var body: some View {
        Image(nsImage: Resources.image(capability.icon))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct PromethProviderLogo: View {
    let provider: Provider
    var size: CGFloat = 28

    var filename: String {
        switch provider {
        case .gmail: "provider-gmail.png"
        case .outlook: "provider-outlook.png"
        case .drive: "provider-drive.png"
        case .github: "provider-github.png"
        }
    }

    var body: some View {
        Image(nsImage: Resources.image(filename))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .padding(8)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel(provider.rawValue + " logo")
    }
}

struct IconButton: View {
    let symbol: String
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .font(.system(size: 15))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

struct FluidOrb: View {
    var speaking = false
    @Environment(\.accessibilityReduceMotion) var reduce

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduce)) { ctx in
            let t = reduce ? 0.0 : ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().fill(
                    RadialGradient(
                        colors: [
                            Color(hex: PromethDesign.fluidOrbCore),
                            Color(hex: PromethDesign.fluidOrbInner),
                            Color(hex: PromethDesign.fluidOrbMid),
                            Color(hex: PromethDesign.fluidOrbOuter),
                        ],
                        center: UnitPoint(x: 0.38, y: 0.32),
                        startRadius: 2,
                        endRadius: 96
                    )
                )
                Ellipse().fill(.white.opacity(0.62)).frame(width: 168, height: 46).blur(radius: 12)
                    .offset(x: sin(t * 0.55) * 16, y: 22 + cos(t * 0.37) * 5)
                Ellipse().fill(Color(hex: 0xF7FBFF).opacity(0.8)).frame(width: 112, height: 34).blur(radius: 9)
                    .offset(x: cos(t * 0.48) * 20, y: 6 + sin(t * 0.33) * 7)
                Ellipse().fill(Color(hex: 0xD7ECFF).opacity(0.55)).frame(width: 96, height: 30).blur(radius: 14)
                    .offset(x: sin(t * 0.41 + 1.2) * 14, y: -8 + cos(t * 0.29) * 4)
                Circle().fill(.white.opacity(0.34)).frame(width: 64, height: 64).blur(radius: 16)
                    .offset(x: -16 + sin(t * 0.25) * 5, y: -30)
            }
            .frame(width: 132, height: 132)
            .clipShape(Circle())
            .scaleEffect(speaking && !reduce ? 1 + 0.04 * (0.5 + 0.5 * sin(t * 2.2)) : 1)
            .shadow(color: Color(hex: 0x3B82F6).opacity(0.22), radius: speaking ? 28 : 18, y: 8)
        }
        .accessibilityLabel("Voice")
    }
}

struct ActionOrb: View {
    var body: some View {
        Circle().fill(
            LinearGradient(
                colors: [Color(hex: PromethDesign.actionOrbStart), Color(hex: PromethDesign.actionOrbEnd)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

struct VoiceGlyph: View {
    var body: some View {
        HStack(spacing: 2.2) {
            ForEach(Array(PromethDesign.voiceBarHeights.enumerated()), id: \.offset) { _, height in
                Capsule().fill(.white).frame(width: 2.4, height: CGFloat(height))
            }
        }
        .frame(width: 18, height: 16)
    }
}
