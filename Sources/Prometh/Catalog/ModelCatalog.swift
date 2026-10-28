import CryptoKit
import Foundation

/// Pinned `model-catalog.json`. Friendly names come from `name`. Repository ids
/// stay in this model and are not shown in the onboarding rows.
struct ModelCatalog: Decodable, Sendable {
    var storagePolicy: StoragePolicy
    var models: [CatalogModel]

    struct StoragePolicy: Decodable, Sendable {
        var macOSHeadroomBytes: Int64
        var partialFileSuffix: String
    }

    func model(id: String) -> CatalogModel? {
        models.first { $0.id == id }
    }

    func preparationModels(for capability: Capability) -> [CatalogModel] {
        switch capability {
        case .chat:
            models.filter { $0.id == "safe" && $0.enabled }
        case .voice:
            models.filter { $0.enabled && $0.capability == "Voice" && $0.id != "tts" }
        case .images:
            models.filter { $0.enabled && $0.capability == "Images" }
        case .video:
            models.filter { $0.id == "video" && $0.enabled }
        }
    }
}

struct CatalogModel: Decodable, Sendable, Identifiable {
    var id: String
    var name: String
    var capability: String
    var repo: String
    var runtime: String
    var enabled: Bool
    var workingMemoryGB: Double
    var revision: String
    var files: [CatalogFile]
    var downloadBytes: Int64
}

struct CatalogFile: Decodable, Sendable {
    var path: String
    var size: Int64
    var hashAlgorithm: String
    var hash: String
    var sha256: String?
    var oid: String?
    var contentID: String
    var url: String

    var expectedDigest: String? {
        if let sha256, !sha256.isEmpty { return sha256 }
        if let oid, !oid.isEmpty { return oid }
        return hash.isEmpty ? nil : hash
    }

    var usesGitBlobSHA1: Bool { sha256?.isEmpty != false }
}

enum ModelCatalogLoader {
    static func load(from url: URL) throws -> ModelCatalog {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ModelCatalog.self, from: data)
    }

    static func bundled() throws -> ModelCatalog {
        if let url = Bundle.main.url(forResource: "model-catalog", withExtension: "json") {
            return try load(from: url)
        }
        #if DEBUG
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/model-catalog.json")
        return try load(from: source)
        #else
        throw CocoaError(.fileNoSuchFile)
        #endif
    }
}

enum CatalogSize {
    /// Decimal gigabytes, two places, matching the onboarding cards.
    static func decimalGigabytes(_ bytes: Int64) -> String {
        String(format: "%.2f GB", Double(bytes) / 1_000_000_000)
    }
}

enum CatalogPaths {
    static func modelsRoot(support: URL) -> URL {
        support.appendingPathComponent("Models", isDirectory: true)
    }

    static func hub(support: URL) -> URL {
        modelsRoot(support: support).appendingPathComponent("hub", isDirectory: true)
    }

    static func folder(root: URL, model: CatalogModel) -> URL {
        let revision = String(model.revision.prefix(12))
        let name = model.repo.replacingOccurrences(of: "/", with: "--") + "--" + revision
        return root.appendingPathComponent(name, isDirectory: true)
    }

    static func blob(root: URL, contentID: String) -> URL {
        let safe = contentID.replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_")
        return root.appendingPathComponent("blobs", isDirectory: true).appendingPathComponent(safe)
    }

    static func repoCacheName(_ repo: String) -> String {
        "models--" + repo.replacingOccurrences(of: "/", with: "--")
    }

    static func snapshotFile(hub: URL, model: CatalogModel, path: String) -> URL {
        hub.appendingPathComponent(repoCacheName(model.repo), isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent(model.revision, isDirectory: true)
            .appendingPathComponent(path)
    }

    static func mainRef(hub: URL, model: CatalogModel) -> URL {
        hub.appendingPathComponent(repoCacheName(model.repo), isDirectory: true)
            .appendingPathComponent("refs", isDirectory: true)
            .appendingPathComponent("main")
    }
}

enum CatalogHash {
    static func sha256(of file: URL) throws -> String {
        try digest(file: file, gitBlob: false)
    }

    static func gitBlobSHA1(of file: URL) throws -> String {
        try digest(file: file, gitBlob: true)
    }

    static func byteCount(_ url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return nil }
        return size.int64Value
    }

    static func matches(_ file: CatalogFile, at url: URL) throws -> Bool {
        guard let expected = file.expectedDigest else { return false }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return false }
        guard (attributes[.type] as? FileAttributeType) == .typeRegular else { return false }
        guard (attributes[.size] as? NSNumber)?.int64Value == file.size else { return false }
        let actual = file.usesGitBlobSHA1 ? try gitBlobSHA1(of: url) : try sha256(of: url)
        return actual == expected
    }

    private static func digest(file: URL, gitBlob: Bool) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let size = byteCount(file) ?? 0
        if gitBlob {
            var hasher = Insecure.SHA1()
            hasher.update(data: Data("blob \(size)\0".utf8))
            while let chunk = try handle.read(upToCount: 8 * 1024 * 1024), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 8 * 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum CatalogFit {
    static let simulatedFreeBytesKey = "PROMETH_SIMULATED_FREE_BYTES"

    static func freeBytes(at url: URL) -> Int64 {
        if let raw = ProcessInfo.processInfo.environment[simulatedFreeBytesKey],
           let simulated = Int64(raw) {
            return simulated
        }
        let values = try? FileManager.default.attributesOfFileSystem(forPath: url.path)
        return (values?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }

    /// Memory uses the largest model that would be resident. Disk uses the
    /// download size plus the catalog headroom (8 GB).
    static func reason(
        capability: Capability,
        models: [CatalogModel],
        headroom: Int64,
        memoryGB: Int,
        freeBytes: Int64
    ) -> String? {
        let requiredMemory = models.map(\.workingMemoryGB).max() ?? 0
        if Double(memoryGB) + 0.05 < requiredMemory {
            return "\(capability.rawValue) needs more memory."
        }
        let needed = models.reduce(Int64(0)) { $0 + $1.downloadBytes } + headroom
        if freeBytes < needed {
            return "Not enough space for \(capability.rawValue.lowercased())."
        }
        return nil
    }
}

enum CatalogLog {
    static func append(_ line: String, support: URL) {
        let url = support.appendingPathComponent("preparation.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "\(stamp) \(line)\n"
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
        } else {
            try? Data(text.utf8).write(to: url)
        }
        print(text, terminator: "")
        fflush(stdout)
    }
}
