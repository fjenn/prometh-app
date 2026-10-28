import Foundation

enum PromethRuntimeLocator {
    static func url(relative: String) -> URL? {
        let manager = FileManager.default
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("PromethRuntime", isDirectory: true)
            .appendingPathComponent(relative),
            manager.fileExists(atPath: bundled.path) {
            return bundled
        }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PromethRuntime")
            .appendingPathComponent(relative)
        if manager.fileExists(atPath: repo.path) {
            return repo
        }
        return nil
    }
}

