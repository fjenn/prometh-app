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
