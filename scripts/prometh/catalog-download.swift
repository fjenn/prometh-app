// Developer CLI: compile with ModelCatalog.swift and CatalogDownloader.swift.
// Uses the exact app downloader, immutable URLs, resume offsets, and hashes.
import Foundation

enum Capability { case chat, voice, images, video
    var rawValue: String { String(describing: self).capitalized }
}

@main struct Download {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let catalog = try ModelCatalogLoader.load(from: root.appendingPathComponent("Sources/Prometh/Resources/model-catalog.json"))
        let support = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Prometh")
        for id in CommandLine.arguments.dropFirst() {
            guard let model = catalog.model(id: id) else { throw CocoaError(.fileNoSuchFile) }
            try await CatalogDownloader.prepare(model: model, support: support,
                headroom: catalog.storagePolicy.macOSHeadroomBytes, control: TransferControl(),
                log: { print("\(id): \($0)") }, progress: { _ in })
            print("VERIFIED \(id) \(model.revision) \(model.downloadBytes) bytes")
        }
    }
}
