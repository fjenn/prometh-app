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
        let query = PromethSearchContext.searchQuery(from: text)
        guard !query.isEmpty else { return }
        await SearXNGSupervisor.shared.start()
        await ReaderSupervisor.shared.start()
        let results = await Self.search(query)
        guard !results.isEmpty else { return }
        let mapped = results.map {
            PromethSearchContext.Result(title: $0.title, url: $0.url, snippet: $0.snippet)
        }
        // Distinct domains (3–5) so Sources and [n] chips are not all one site.
        let selected = PromethSearchContext.preferDistinctDomains(mapped, limit: 5)
        guard !selected.isEmpty else { return }
        // Publish Sources as soon as search returns so the UI is not blocked on reads.
        var hits = PromethSearchContext.indexedHits(selected: selected, bodies: [:])
        store(
            userID: userID,
            links: hits.map { SourceLink(title: $0.title, url: $0.url, index: $0.index) },
            note: PromethSearchContext.promptNote(hits: hits)
        )
        let pages = await Self.readPages(selected.map(\.url), focus: String(text.prefix(500)))
        let bodies = Dictionary(uniqueKeysWithValues: pages.compactMap { page -> (String, (title: String?, content: String))? in
            guard let content = page.content, !content.isEmpty else { return nil }
            return (page.url, (page.title, content))
        })
        hits = PromethSearchContext.indexedHits(selected: selected, bodies: bodies)
        store(
            userID: userID,
            links: hits.map { SourceLink(title: $0.title, url: $0.url, index: $0.index) },
            note: PromethSearchContext.promptNote(hits: hits)
        )
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
        await withTimeout(seconds: 25) {
            (try? await WebBrowsingRuntime().search(query: query, limit: 8)) ?? []
        } ?? []
    }

    private static func readPages(_ urls: [String], focus: String) async -> [WebReadPage] {
        guard !urls.isEmpty else { return [] }
        // Sidecar only (trafilatura chain). Skip WKWebView here so a JS shell
        // cannot stall the prefetch ahead of the model turn.
        await ReaderSupervisor.shared.start()
        // Five parallel sidecar reads; give the group enough wall time to finish.
        return await withTimeout(seconds: 22) {
            await withTaskGroup(of: WebReadPage?.self, returning: [WebReadPage].self) { group in
                for url in urls {
                    group.addTask {
                        guard let page = await ReaderSupervisor.shared.extract(url: url),
                              !page.text.isEmpty else { return nil }
                        var body = page.text
                        if let published = page.published, !published.isEmpty {
                            body = "Published: \(published)\n\n" + body
                        }
                        return WebReadPage(
                            url: page.url,
                            title: page.title,
                            content: PromethSearchContext.excerpt(body, limit: 3_500),
                            truncated: page.text.count > 3_500,
                            error: nil
                        )
                    }
                }
                var pages: [WebReadPage] = []
                for await page in group {
                    if let page { pages.append(page) }
                }
                return pages
            }
        } ?? []
    }

    private static func withTimeout<T: Sendable>(
        seconds: UInt64,
        operation: @escaping @Sendable () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? nil
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
