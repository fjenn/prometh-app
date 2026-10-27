import AppKit
import Foundation

enum Product {
    static let name = PromethIdentity.productName
    static let bundleID = PromethIdentity.bundleIdentifier
    static let headline = "AI that you own."
    static let supportName = PromethIdentity.supportDirectoryName
}

enum Capability: String, CaseIterable, Codable, Identifiable {
    case chat = "Chat"
    case voice = "Voice"
    case images = "Images"
    case video = "Video"

    var id: String { rawValue }

    /// Friendly download size in decimal gigabytes, from `model-catalog.json`
    /// `downloadBytes` for `enabled: true` models. Evil is a step-3 add-on, not
    /// part of the Chat card.
    var gigabytes: Double {
        switch self {
        case .chat: 5.18
        case .voice: 1.84
        case .images: 4.62
        case .video: 13.40
        }
    }

    var symbol: String {
        switch self {
        case .chat: "bubble.left.and.bubble.right.fill"
        case .voice: "waveform"
        case .images: "photo.on.rectangle.angled"
        case .video: "play.rectangle.fill"
        }
    }

    var icon: String {
        switch self {
        case .chat: "capability-chat.png"
        case .voice: "capability-voice.png"
        case .images: "capability-images.png"
        case .video: "capability-video.png"
        }
    }

    var phrase: String {
        switch self {
        case .chat: "Talk and write"
        case .voice: "Speak and listen"
        case .images: "Make photos"
        case .video: "Make clips"
        }
    }

    var detail: String {
        switch self {
        case .chat: "Think, write, ask and explore."
        case .voice: "Speak naturally. Hear your AI respond."
        case .images: "Create images and transform the ones you have."
        case .video: "Create clips and make them your own."
        }
    }
}

enum Provider: String, CaseIterable, Codable, Identifiable {
    case gmail = "Gmail"
    case outlook = "Outlook"
    case drive = "Google Drive"
    case github = "GitHub"

    var id: String { rawValue }

    var access: String {
        switch self {
        case .gmail, .outlook: "Read selected messages and draft replies"
        case .drive: "Find and read selected documents"
        case .github: "Read selected repositories and issues"
        }
    }

    var toolkit: String {
        switch self {
        case .gmail: "gmail"
        case .outlook: "outlook"
        case .drive: "googledrive"
        case .github: "github"
        }
    }
}

struct PromethArtifact: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: String
    var filename: String
    var prompt: String
    var parentID: UUID?
    var version = 1
    var trimStart: Double = 0
    var trimEnd: Double = 6
    var duration: Double?
    var modelID: String?
}

enum Resources {
    static func url(_ name: String) -> URL {
        Bundle.main.resourceURL?.appendingPathComponent(name)
            ?? URL(fileURLWithPath: name)
    }

    static func image(_ name: String) -> NSImage {
        NSImage(contentsOf: url(name)) ?? NSImage(size: NSSize(width: 800, height: 450))
    }
}
