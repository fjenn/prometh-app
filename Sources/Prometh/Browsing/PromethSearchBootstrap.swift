import Foundation
import NativServerKit

enum PromethPromptAdditionsMode: @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var mode = "Safe Mode"

    static var current: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return mode
        }
        set {
            lock.lock()
            mode = newValue
            lock.unlock()
        }
    }
}

enum PromethSearchBootstrap {
    static func start() {
        guard PromethFlags.promethShell, !PromethFlags.isRunningUnitTests else { return }
        ChatViewModel.PromethPromptAdditions.sections = {
            [
                PromethPrompts.persona(mode: PromethPromptAdditionsMode.current),
                PromethPrompts.citationRules(),
                PromethWebPrefetch.promptSection(),
            ].filter { !$0.isEmpty }
        }
        ChatViewModel.PromethPromptAdditions.prefetch = { userID, text in
            await PromethWebPrefetch.prepare(userID: userID, text: text)
        }
        PromethLocalReaderHook.read = { urls, _ in
            try await LocalPageReader.read(urls: urls, focus: nil)
        }
        PromethSearXNGEndpoint.resolve = {
            await SearXNGSupervisor.shared.start()
            return SearXNGSupervisor.shared.baseURL()
        }
        applyDefaultsIfUnset()
        PromethGenerateVideoTool.run = { arguments in
            try await PromethMediaWorker.generate(argumentsJSON: arguments)
        }
        ChatViewModel.ChatEndpointResolver.resolve = { settings, sessionID in
            let mode = PromethModeTable.mode(for: sessionID)
            let tight = PromethMemoryPolicy.shouldUnloadOther(ProcessInfo.processInfo.physicalMemory)
            guard mode == BehaviorMode.evil.rawValue else {
                ChatViewModel.ChatEndpointResolver.presentsLlamaErrors = false
                NativResponsesClient.adaptsLlamaResponses = false
                if tight { LlamaSupervisor.shared.stop() }
                return settings
            }
            ChatViewModel.ChatEndpointResolver.presentsLlamaErrors = true
            NativResponsesClient.adaptsLlamaResponses = true
            if tight {
                await PromethMemory.unloadMLX(baseURL: settings.serverBaseURL, apiKey: settings.serverAPIKey)
            }
            let endpoint = try await LlamaSupervisor.shared.ensureRunning()
            var routed = settings
            routed.serverHost = endpoint.host
            routed.serverPort = endpoint.port
            routed.serverAPIKey = endpoint.apiKey
            routed.languageModelID = endpoint.alias
            return routed
        }
        Task {
            await SearXNGSupervisor.shared.start()
            await ReaderSupervisor.shared.start()
        }
    }

    static func stop() {
        SearXNGSupervisor.shared.stop()
        ReaderSupervisor.shared.stop()
        LlamaSupervisor.shared.stop()
    }

    /// Writes the embedded search defaults only when the user has not chosen a provider.
    private static func applyDefaultsIfUnset() {
        let defaults = UserDefaults.standard
        let searchKey = "nativ.web-search.active-provider.v1"
        if defaults.object(forKey: searchKey) == nil {
            defaults.set(WebSearchProvider.searxng.rawValue, forKey: searchKey)
        }
        let endpointKey = "nativ.web-search.endpoint.v1.searxng"
        if defaults.object(forKey: endpointKey) == nil {
            defaults.set("http://prometh-embedded", forKey: endpointKey)
        }
        let readerKey = "nativ.web-browsing.page-reader-provider.v1"
        if defaults.object(forKey: readerKey) == nil {
            defaults.set(WebSearchProvider.local.rawValue, forKey: readerKey)
        }
    }
}

/// Runs a local search before the model answers questions about current events,
/// so the Sources row does not depend on the model choosing the web_search tool.
enum PromethWebPrefetch {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var searchEnabled = true
    nonisolated(unsafe) private static var linksByUser: [UUID: [SourceLink]] = [:]
    nonisolated(unsafe) private static var note = ""

    static var enabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return searchEnabled
        }
        set {
            lock.lock()
            searchEnabled = newValue
            lock.unlock()
        }
    }

    static func prepare(userID: UUID, text: String) async {
        clearNote()
        guard enabled, needsWeb(text) else { return }
        if ProcessInfo.processInfo.environment["PROMETH_OFFLINE"] == "1" { return }
        let query = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !query.isEmpty else { return }
        let results = await Self.search(query)
        guard !results.isEmpty else { return }
        let links = results.enumerated().map { offset, result in
            SourceLink(title: result.title, url: result.url, index: offset + 1)
        }
        let lines = results.enumerated().map { offset, result in
            "[\(offset + 1)] \(result.title)\n\(result.url)\n\(result.snippet)"
        }.joined(separator: "\n")
        store(userID: userID, links: links, note: "Searched the web for this question. Cite these sources with [n].\n\(lines)")
    }

    static func promptSection() -> String {
        lock.lock()
        defer { lock.unlock() }
        return note
    }

    static func storedLinks(before assistantID: UUID, in messages: [ChatTranscriptMessage]) -> [SourceLink]? {
        guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { return nil }
        var cursor = index - 1
        while cursor >= 0 {
            if messages[cursor].role == .user {
                lock.lock()
                defer { lock.unlock() }
                let links = linksByUser[messages[cursor].id]
                return links?.isEmpty == false ? links : nil
            }
            cursor -= 1
        }
        return nil
    }

    private static func search(_ query: String) async -> [WebSearchResult] {
        await withTaskGroup(of: [WebSearchResult]?.self) { group in
            group.addTask {
                (try? await WebBrowsingRuntime().search(query: query, limit: 5)) ?? []
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? []
        }
    }

    private static func needsWeb(_ text: String) -> Bool {
        let value = text.lowercased()
        let cues = ["news", "who won", "latest", "most recent", "what happened", "current events", "yesterday"]
        return cues.contains { value.contains($0) }
    }

    private static func clearNote() {
        lock.lock()
        note = ""
        lock.unlock()
    }

    private static func store(userID: UUID, links: [SourceLink], note next: String) {
        lock.lock()
        linksByUser[userID] = links
        if linksByUser.count > 20, let oldest = linksByUser.keys.first {
            linksByUser[oldest] = nil
        }
        note = next
        lock.unlock()
    }
}
