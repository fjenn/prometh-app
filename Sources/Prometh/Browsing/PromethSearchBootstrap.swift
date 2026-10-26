import Foundation

enum PromethPromptAdditionsMode: @unchecked Sendable {
    private static let lock = NSLock()
    private static var mode = "Safe Mode"

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
            ]
        }
        PromethLocalReaderHook.read = { urls, _ in
            try await LocalPageReader.read(urls: urls, focus: nil)
        }
        PromethSearXNGEndpoint.resolve = {
            await SearXNGSupervisor.shared.start()
            return SearXNGSupervisor.shared.baseURL()
        }
        applyDefaultsIfUnset()
        ChatViewModel.ChatEndpointResolver.resolve = { settings, sessionID in
            let mode = PromethModeTable.mode(for: sessionID)
            let tight = PromethMemoryPolicy.shouldUnloadOther(ProcessInfo.processInfo.physicalMemory)
            guard mode == BehaviorMode.evil.rawValue else {
                ChatViewModel.ChatEndpointResolver.presentsLlamaErrors = false
                if tight { LlamaSupervisor.shared.stop() }
                return settings
            }
            ChatViewModel.ChatEndpointResolver.presentsLlamaErrors = true
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
