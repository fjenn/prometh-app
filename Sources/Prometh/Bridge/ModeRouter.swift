import Foundation

/// One chat model stays resident when the Mac has 16 GiB or less.
enum PromethMemoryPolicy {
    static let limitBytes: UInt64 = 16 * 1024 * 1024 * 1024

    static func shouldUnloadOther(_ physicalMemoryBytes: UInt64) -> Bool {
        physicalMemoryBytes <= limitBytes
    }
}

enum PromethInterruptedError: LocalizedError {
    case llamaUnavailable

    var errorDescription: String? {
        "Something interrupted that. Your request is saved. Try again when you're ready."
    }
}

enum PromethModeTable: @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var modes: [UUID: String] = [:]

    static func set(_ id: UUID, _ mode: String) {
        lock.lock()
        modes[id] = mode
        lock.unlock()
    }

    static func mode(for id: UUID) -> String {
        lock.lock()
        defer { lock.unlock() }
        return modes[id] ?? "Safe Mode"
    }

    /// The first conversation follows onboarding. Every later conversation starts Safe.
    static func modeForNewChat(existingChats: Int, defaultMode: String) -> String {
        existingChats == 0 ? defaultMode : "Safe Mode"
    }

    /// A mode picked in the menu before a chat exists is the one that chat opens in.
    static func openingMode(existingChats: Int, defaultMode: String, requested: String?) -> String {
        if let requested, !requested.isEmpty {
            return requested
        }
        return modeForNewChat(existingChats: existingChats, defaultMode: defaultMode)
    }

    /// The menu shows the open chat. With no chat yet, it shows the pending choice.
    static func displayed(chatMode: String?, requested: String?, defaultMode: String) -> String {
        if let chatMode, !chatMode.isEmpty {
            return chatMode
        }
        if let requested, !requested.isEmpty {
            return requested
        }
        return defaultMode
    }
}

enum PromethMemory {
    static func unloadMLX(baseURL: URL, apiKey: String?) async {
        var request = URLRequest(url: baseURL.appendingPathComponent("unload"))
        request.httpMethod = "POST"
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 3
        _ = try? await URLSession.shared.data(for: request)
    }
}

/// Serializes heavy media jobs against chat engines so image/video picks can
/// use `residentGB = 0`. Stops Evil llama.cpp and posts `/unload` to the Safe
/// mlx-vlm server before a media job; chat reloads on the next message.
enum PromethMediaGate {
    /// Live server locator filled by `PromethSearchBootstrap` / AppDelegate.
    nonisolated(unsafe) static var resolveServer: (() -> (baseURL: URL, apiKey: String?))?
    /// Stops Evil llama.cpp; wired from bootstrap so ModeRouter stays test-linkable.
    nonisolated(unsafe) static var stopEvilServer: (() -> Void)?

    static func unloadChatEngines(reason: String) async {
        stopEvilServer?()
        let resolved = resolveServer?()
        let base = resolved?.baseURL ?? URL(string: "http://127.0.0.1:8080")!
        let key = resolved?.apiKey
        await PromethMemory.unloadMLX(baseURL: base, apiKey: key)
        // Console evidence for measurement runs (no secrets).
        print("prometh media-gate: unloaded chat before \(reason)")
    }
}
