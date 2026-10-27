import Foundation

enum PromethModelFamily: String, CaseIterable {
    case safe, evil, listening, speaking, images, video

    var label: String {
        switch self {
        case .safe: "Safe chat"
        case .evil: "Evil chat"
        case .listening: "Listening"
        case .speaking: "Speaking"
        case .images: "Images"
        case .video: "Video"
        }
    }

    /// Best first; only shipped, enabled catalog records can be selected.
    var bestFirstIDs: [String] {
        switch self {
        case .safe: ["safe-qwen9b", "safe-qwen4b", "safe-qwen2b", "safe-llama1b"]
        case .evil: ["evil", "evil-4b"]
        case .listening: ["stt", "stt-base"]
        case .speaking: ["kokoro"]
        case .images: ["images-9b", "images"]
        case .video: ["video-14b", "video-5b", "video"]
        }
    }
}

struct PromethModelChoice {
    let model: CatalogModel?
    let reason: String
    let budgetGB: Double
}

enum PromethModelPicker {
    // Unified memory: leave 25% to macOS/apps and another 1 GiB of fixed
    // headroom. Subtract models that remain resident during this capability.
    static func budget(memoryGB: Int, residentGB: Double = 0) -> Double {
        max(0, Double(memoryGB) * 0.75 - 1 - residentGB)
    }

    static func options(_ family: PromethModelFamily, catalog: ModelCatalog) -> [CatalogModel] {
        var ids = family.bestFirstIDs
        if family == .safe { ids.append("safe") } // Gemma stays a manual option.
        return ids.compactMap { catalog.model(id: $0) }.filter(\.enabled)
    }

    static func choose(_ family: PromethModelFamily, catalog: ModelCatalog, memoryGB: Int,
                       freeBytes: Int64, residentGB: Double = 0, override: String? = nil, installedIDs: Set<String> = []) -> PromethModelChoice {
        let usable = budget(memoryGB: memoryGB, residentGB: residentGB)
        let options = options(family, catalog: catalog)
        if let override, let selected = options.first(where: { $0.id == override }) {
            return PromethModelChoice(model: selected,
                reason: "Manual choice: \(selected.name). \(String(format: "%.1f", usable)) GiB budget on your \(memoryGB) GB Mac.", budgetGB: usable)
        }
        let candidates = family.bestFirstIDs.compactMap { id in options.first { $0.id == id } }
        let diskFits = candidates.filter { (installedIDs.contains($0.id) ? 0 : $0.downloadBytes) <= max(0, freeBytes - catalog.storagePolicy.macOSHeadroomBytes) }
        let fitting = diskFits.first { $0.workingMemoryGB * 1.08 <= usable }
        // Like web modelFor: Safe falls back to the smallest. Other capabilities
        // become unavailable with a reason rather than loading an oversized model.
        let selected = fitting ?? (family == .safe ? diskFits.last : nil)
        guard let selected else {
            let reason = diskFits.isEmpty
                ? "\(family.label) needs more free disk space, including 8 GB for macOS."
                : "\(family.label) is unavailable: no model fits the \(String(format: "%.1f", usable)) GiB budget with an 8% margin."
            return PromethModelChoice(model: nil, reason: reason, budgetGB: usable)
        }
        let suffix = fitting == nil ? " Smallest-model fallback; close other apps if memory is tight." : ""
        return PromethModelChoice(model: selected,
            reason: "Picked \(selected.name) for your \(memoryGB) GB Mac (\(String(format: "%.1f", usable)) GiB budget; 8% margin)." + suffix,
            budgetGB: usable)
    }
}

/// Snapshot of persisted selections for runtime workers that do not own the UI.
enum PromethSelectedModels: @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var ids: [String: String] = [:]

    static func set(_ choices: [String: String]) { lock.withLock { ids = choices } }
    static func id(_ family: PromethModelFamily, fallback: String) -> String {
        lock.withLock { ids[family.rawValue] ?? fallback }
    }
}
