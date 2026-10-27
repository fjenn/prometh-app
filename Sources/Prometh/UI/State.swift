import AppKit
import Foundation

enum Hardware: String, CaseIterable, Codable {
    case capable = "Studio Mac"
    case everyday = "Everyday Mac"
    case storage = "Low storage"
}

enum BehaviorMode: String, Codable, CaseIterable {
    case safe = "Safe Mode"
    case evil = "Evil Mode"
}

enum JobStatus: String, Codable {
    case queued = "Queued"
    case preparing = "Preparing"
    case downloading = "Downloading"
    case checking = "Checking"
    case ready = "Ready"
    case paused = "Paused"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

struct Preparation: Codable {
    var progress: Double = 0
    var status: JobStatus = .queued
}

enum Connection: String, Codable {
    case disconnected
    case connecting
    case connected
    case expired

    var label: String {
        switch self {
        case .connected: "Authorized connection"
        case .expired: "Connection expired"
        case .connecting: "Waiting for sign-in…"
        case .disconnected: "Not connected"
        }
    }

    var buttonTitle: String {
        switch self {
        case .connected: "Disconnect"
        case .expired: "Reconnect"
        case .connecting: "Waiting…"
        case .disconnected: "Connect"
        }
    }
}

struct Attachment: Identifiable, Codable, Equatable {
    var id = UUID()
    var filename: String
    var storedName: String
    var bundled = false
}

struct SourceLink: Codable, Equatable, Identifiable {
    var id: String { url }
    let title: String
    let url: String
    var index: Int? = nil
    var published: String? = nil
}

struct Message: Identifiable, Codable, Equatable {
    var id = UUID()
    var role: String
    var text: String
    var status = "complete"
    var attachments: [Attachment] = []
    var artifact: PromethArtifact?
    var sources = false
    var jobKind: String?
    var sourceArtifact: PromethArtifact?
    var trimRange: [Double]?
    var appliedSkillNames: [String]?
    var sourceLinks: [SourceLink]?
}

struct Conversation: Identifiable, Codable {
    var id = UUID()
    var title = "New conversation"
    var mode: BehaviorMode = .safe
    var messages: [Message] = []
    var draft = ""
    var attachments: [Attachment] = []
    var updated = Date()
}

struct SkillRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var instructions: String
    var isEnabled = true
}

struct MacSpecs {
    let memoryGB: Int
    let freeStorageGB: Int
    let chip: String

    static func read() -> MacSpecs {
        let memory = Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
        let cache = PromethIdentity.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let values = try? FileManager.default.attributesOfFileSystem(forPath: cache.path)
        let free = (values?[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0)
        return MacSpecs(
            memoryGB: memory,
            freeStorageGB: Int(free / 1_000_000_000),
            chip: String(cString: bytes)
        )
    }

    var summary: String { "\(chip) · \(memoryGB) GB memory · \(freeStorageGB) GB available" }
}

struct Snapshot: Codable {
    var version = 2
    var modelSelections: [String:String]?
    var modelOverrides: [String:String]?
    var modelSelectionReasons: [String:String]?
    var onboardingComplete = false
    var step = 0
    var selected: Set<Capability> = [.chat]
    var preparations: [String: Preparation] = [:]
    var hardware: Hardware = .capable
    var evilEnabled = false
    var defaultMode: BehaviorMode = .safe
    var connections: [String: Connection] = [:]
    var appearance = "Light"
    var webSearch = true
    var selectedChatID: UUID?
    var skills: [SkillRecord] = []
    var fileReadingEnabled: Bool?
    var connectorBrokerURL: String?
    var drafts: [String: String] = [:]
    var modes: [String: BehaviorMode] = [:]
    var stoppedMessageIDs: [String] = []
}

struct Persistence {
    let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? PromethIdentity.applicationSupportDirectory
    }

    private var file: URL { directory.appendingPathComponent("state-v1.json") }

    func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: file),
              var snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        if snapshot.version < 2 {
            snapshot.webSearch = true
            snapshot.version = 2
        }
        return snapshot
    }

    func save(_ state: Snapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: file, options: .atomic)
    }

    private var revealedFile: URL { directory.appendingPathComponent("revealed-chats.json") }

    func loadRevealed() -> Set<String> {
        guard let data = try? Data(contentsOf: revealedFile),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }

    func saveRevealed(_ ids: Set<String>) {
        guard let data = try? JSONEncoder().encode(ids.sorted()) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: revealedFile, options: .atomic)
    }
}
