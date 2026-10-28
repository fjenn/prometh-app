import AppKit
import AVFoundation
import NativServerKit
import Combine
import SwiftUI
import WebKit

struct PromethWebRootView: View {
    @StateObject private var store: PromethStore
    init(model: NativModel) { _store = StateObject(wrappedValue: PromethStore(model: model)) }
    var body: some View {
        PromethWebView(store: store, engineLoading: store.model.isModelLoading, progress: store.model.modelLoadingProgress, modelID: store.model.modelLoadingID)
            .frame(minWidth: 960, minHeight: 650)
            .ignoresSafeArea()
    }
}

private struct PromethWebView: NSViewRepresentable {
    let store: PromethStore
    let engineLoading: Bool
    let progress: Double?
    let modelID: String?
    func makeCoordinator() -> PromethWebCoordinator { PromethWebCoordinator(store: store) }
    func makeNSView(context: Context) -> WKWebView {
        let dark = store.state.appearance == "Dark" || (store.state.appearance == "System" && NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController.addUserScript(WKUserScript(source: """
        (() => {
          const apply = () => document.documentElement.dataset.theme = '\(dark ? "dark" : "light")';
          if (document.documentElement) apply();
          else { const observer = new MutationObserver(() => { if (document.documentElement) { apply(); observer.disconnect(); } }); observer.observe(document, { childList: true }); }
        })();
        if (!crypto.randomUUID) crypto.randomUUID = () => '10000000-1000-4000-8000-100000000000'.replace(/[018]/g, c => (c ^ crypto.getRandomValues(new Uint8Array(1))[0] & 15 >> c / 4).toString(16));
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.setURLSchemeHandler(PromethUISchemeHandler(), forURLScheme: "prometh-ui")
        config.userContentController.add(context.coordinator, name: "prometh")
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.underPageBackgroundColor = dark ? NSColor(calibratedRed: 0.1255, green: 0.1373, blue: 0.1686, alpha: 1) : NSColor(calibratedRed: 0.9804, green: 0.9765, blue: 0.9647, alpha: 1)
        web.uiDelegate = context.coordinator
        web.navigationDelegate = context.coordinator
        #if DEBUG
        web.isInspectable = true
        #endif
        context.coordinator.attach(web)
        web.load(URLRequest(url: URL(string: "prometh-ui://app/")!))
        return web
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.emit("engine", ["loading": engineLoading, "progress": progress ?? 0, "model": modelID ?? "", "text": store.model.modelLoadingStatusText ?? "Ready"])
    }
    static func dismantleNSView(_ web: WKWebView, coordinator: PromethWebCoordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "prometh")
        coordinator.detach()
    }
}

final class PromethUISchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { urlSchemeTask.didFailWithError(URLError(.badURL)); return }
        let file: URL
        do {
            if url.host == "blob" || url.host == "media" {
                file = try PromethWebFiles.file(url.host == "blob" ? PromethWebFiles.blobs : PromethWebFiles.media, String(url.path.dropFirst()))
            } else if url.host == "app", let root = Bundle.main.resourceURL?.appendingPathComponent("WebUI", isDirectory: true) {
                let path = url.path == "/" || url.path.isEmpty ? "index.html" : String(url.path.dropFirst())
                file = root.appendingPathComponent(path).standardizedFileURL
                guard file.path.hasPrefix(root.path + "/") else { throw URLError(.noPermissionsToReadFile) }
            } else { throw URLError(.badURL) }
            let data = try Data(contentsOf: file)
        var mime = ["html": "text/html", "js": "text/javascript", "css": "text/css", "json": "application/json", "png": "image/png", "jpg": "image/jpeg", "svg": "image/svg+xml", "woff2": "font/woff2", "webp": "image/webp", "mp4": "video/mp4", "wav": "audio/wav", "jpeg": "image/jpeg"][file.pathExtension] ?? "application/octet-stream"
        if mime == "application/octet-stream" {
            if data.starts(with: [137, 80, 78, 71]) { mime = "image/png" }
            else if data.starts(with: [255, 216, 255]) { mime = "image/jpeg" }
            else if data.count > 12, String(data: data[8..<12], encoding: .ascii) == "WEBP" { mime = "image/webp" }
        }
        var body = data
        var headers = ["Content-Type": mime, "Access-Control-Allow-Origin": "prometh-ui://app", "Accept-Ranges": "bytes"]
        var status = 200
        if let range = urlSchemeTask.request.value(forHTTPHeaderField: "Range"), range.hasPrefix("bytes="),
           let start = Int(range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false).first ?? ""), start >= 0, start < data.count {
            let parts = range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
            let end = min(data.count - 1, parts.count > 1 ? (Int(parts[1]) ?? data.count - 1) : data.count - 1)
            guard end >= start else { throw URLError(.badURL) }
            body = data.subdata(in: start..<(end + 1)); status = 206
            headers["Content-Range"] = "bytes \(start)-\(end)/\(data.count)"
        }
        headers["Content-Length"] = String(body.count)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else { throw URLError(.badServerResponse) }
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(body)
        urlSchemeTask.didFinish()
        } catch { urlSchemeTask.didFailWithError(error) }
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}

@MainActor
final class PromethWebCoordinator: NSObject, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
    let store: PromethStore
    weak var web: WKWebView?
    var observers: [NSObjectProtocol] = []
    var subscriptions = Set<AnyCancellable>()
    var nativeChats = UserDefaults.standard.dictionary(forKey: "prometh.web.chatMap") as? [String: String] ?? [:]
    var turnTasks: [String: Task<PromethWebTurnResult, Error>] = [:]
    let plugins = ToolkitCatalogModel()
    let microphone = VoiceAudioRecorder()
    let webSilero = PromethSileroVAD()
    var microphoneToken = ""
    var mediaTasks: [String: Task<String, Error>] = [:]
    var turnTokens: [String: UUID] = [:]
    var imageTasks: [String: Task<Data, Error>] = [:]
    init(store: PromethStore) { self.store = store }
    func attach(_ web: WKWebView) {
        self.web = web
        if store.state.selected.contains(.voice) {
            Task { try? await PromethKokoroSpeech.warm() }
        }
        store.$state.dropFirst().sink { [weak self] _ in
            Task { @MainActor in guard let self else { return }; self.emit("state", self.snapshot()) }
        }.store(in: &subscriptions)
        store.$chats.dropFirst().sink { [weak self] chats in
            Task { @MainActor in
                guard let self else { return }
                var titles: [String: String] = [:]
                for chat in chats {
                    titles[chat.id.uuidString] = chat.title
                    for (webID, nativeID) in self.nativeChats where nativeID == chat.id.uuidString { titles[webID] = chat.title }
                }
                self.emit("chats.metadata", titles)
            }
        }.store(in: &subscriptions)
        for (name, command) in [(Notification.Name.promethNewChat, "newChat"), (.promethOpenSettings, "settings"), (.promethOpenCustomize, "customize")] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.emit("menu", command) }
            })
        }
    }
    func detach() { observers.forEach(NotificationCenter.default.removeObserver); observers = []; subscriptions.removeAll(); turnTasks.values.forEach { $0.cancel() }; mediaTasks.values.forEach { $0.cancel() }; imageTasks.values.forEach { $0.cancel() }; microphone.discard(); webSilero.stop() }
    func emit(_ event: String, _ value: Any) { evaluate("window.__promethNative?.emit", arguments: [event, value]) }
    private func evaluate(_ function: String, arguments: [Any]) {
        guard let json = try? PromethWebMapping.jsonArguments(arguments) else { return }
        web?.evaluateJavaScript("\(function)(...\(json))", completionHandler: nil)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.scheme == "prometh-ui", message.frameInfo.request.url?.host == "app",
              let body = message.body as? [String: Any], let id = body["id"] as? String, let method = body["method"] as? String else { return }
        Task { @MainActor in
            do {
                let result = try await handle(method, body["params"] as? [String: Any] ?? [:])
                evaluate("window.__promethNative.resolve", arguments: [id, ["value": result]])
            } catch { evaluate("window.__promethNative.resolve", arguments: [id, ["error": error.localizedDescription]]) }
        }
    }
    func handle(_ method: String, _ params: [String: Any]) async throws -> Any {
        switch method {
        case "voice.begin":
            if let id = params["id"] as? String, UUID(uuidString: id) != nil { PromethVoiceLatency.begin(id, agoMs: params["agoMs"] as? Double ?? 0) }
            return NSNull()
        case "voice.mark":
            PromethVoiceLatency.mark(params["id"] as? String, params["stage"] as? String ?? "")
            return NSNull()
        case "voice.finish":
            let status = params["status"] as? String ?? "ended"
            PromethVoiceLatency.finish(params["id"] as? String, status: ["complete", "cancelled", "no_speech", "error"].contains(status) ? status : "ended")
            return NSNull()
        case "state.get": return snapshot()
        case "settings.sync":
            if let value = params["appearance"] as? String, ["Light", "Dark", "System"].contains(value), store.state.appearance != value { store.state.appearance = value }
            if let value = params["onboardingComplete"] as? Bool, store.state.onboardingComplete != value { store.state.onboardingComplete = value }
            if let value = params["evilEnabled"] as? Bool, store.state.evilEnabled != value { store.state.evilEnabled = value }
            if let value = params["readAttachments"] as? Bool, store.state.fileReadingEnabled != value { store.state.fileReadingEnabled = value }
            if let values = params["skills"] as? [[String: Any]] {
                let skills = values.compactMap { item -> SkillRecord? in
                    guard let raw = item["id"] as? String, let id = UUID(uuidString: raw), let name = item["name"] as? String, let instructions = item["instructions"] as? String else { return nil }
                    return SkillRecord(id: id, name: name, instructions: instructions, isEnabled: item["enabled"] as? Bool ?? true)
                }
                if store.state.skills != skills { store.state.skills = skills }
            }
            if let values = params["selected"] as? [String] {
                let selected = Set(Capability.allCases.filter { values.contains($0.rawValue.lowercased()) }).union([.chat])
                if store.state.selected != selected { store.state.selected = selected }
            }
            return NSNull()
        case "browser.open":
            guard let raw = params["url"] as? String, let url = PromethWebMapping.externalURL(raw), NSWorkspace.shared.open(url) else { throw bridgeError("The source couldn’t be opened in your browser.") }
            return NSNull()
        case "runtime.get":
            let settings = store.model.settings.normalized()
            var request = URLRequest(url: settings.serverBaseURL.appendingPathComponent("health"))
            request.timeoutInterval = 3
            request.cachePolicy = .reloadIgnoringLocalCacheData
            if let key = settings.serverAPIKey, !key.isEmpty { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let code = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(code),
                  let health = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw bridgeError("The loaded model is unavailable.") }
            let catalog = try ModelCatalogLoader.bundled()
            return ["model": PromethWebMapping.runtimeModel(health: health, catalog: catalog) as Any? ?? NSNull()]
        case "clipboard.write":
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(params["text"] as? String ?? "", forType: .string); return NSNull()
        case "data.deleteDownloads": try await store.deleteWebModelDownloads(); return snapshot()
        case "data.storage":
            let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
            let files = FileManager.default.enumerator(at: store.persistence.directory, includingPropertiesForKeys: Array(keys))
            var bytes: Int64 = 0
            while let file = files?.nextObject() as? URL {
                if let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true, values.isSymbolicLink != true { bytes += Int64(values.fileSize ?? 0) }
            }
            return ["bytes": bytes]
        case "settings.search":
            if let value = params["enabled"] as? Bool { store.state.webSearch = value }; return store.state.webSearch
        case "settings.model":
            if let raw = params["family"] as? String, let family = PromethModelFamily(rawValue: raw), let id = params["id"] as? String { store.chooseModel(family, id: id) }
            return snapshot()
        case "data.reset": try await store.resetWebData(); nativeChats = [:]; UserDefaults.standard.removeObject(forKey: "prometh.web.chatMap"); return snapshot()
        case "blob.put", "blob.delete", "blob.clear", "blob.save", "audio.start", "audio.stop", "audio.cancel", "audio.transcribe", "audio.speech", "audio.warm", "media.video", "media.cancel", "media.save", "media.trim", "media.image":
            return try await handleMedia(method, params)
        case "chat.send": return try await runTurn(params)
        case "chat.stop":
            if let webID = params["chatId"] as? String, let id = nativeID(webID) { store.stopWebTurn(id); turnTasks[webID]?.cancel() }
            return NSNull()
        case "chat.rename", "chat.delete":
            if let webID = params["chatId"] as? String, let id = nativeID(webID) {
                if method == "chat.delete" { store.delete(id) } else { store.rename(id, params["title"] as? String ?? "New chat") }
            }; return NSNull()
        case "connector.decide":
            guard let raw = params["id"] as? String, let id = UUID(uuidString: raw) else { throw bridgeError("This approval is unavailable.") }
            switch params["decision"] as? String { case "always": store.alwaysAllowConnector(id); case "once": store.allowConnectorOnce(id); default: store.declineConnector(id) }
            return NSNull()
        case "plugins.list":
            await plugins.load(force: params["refresh"] as? Bool ?? false)
            return pluginSnapshot()
        case "plugins.connect":
            if let slug = params["slug"] as? String, let item = plugins.catalog?.items.first(where: { $0.slug == slug }) { await plugins.connect(item) }
            return pluginSnapshot()
        case "plugins.disconnect":
            if let slug = params["slug"] as? String { let result = await PromethConnectorClient.disconnect(toolkit: slug); if !result.ok { throw bridgeError(result.message ?? "Couldn’t disconnect.") }; await plugins.refreshStatuses() }
            return pluginSnapshot()
        case "prep.resume", "prep.pause", "prep.cancel":
            let key = params["key"] as? String ?? "chat"
            if key == "evil" {
                switch method { case "prep.pause": store.pauseWebEvilPreparation(); case "prep.cancel": store.cancelWebEvilPreparation(); default: store.prepareEvil() }
            }
            else if let cap = Capability.allCases.first(where: { $0.rawValue.lowercased() == key }) {
                switch method { case "prep.pause": store.pausePreparation(cap); case "prep.cancel": store.cancelPreparation(cap); default: store.resumePreparation(cap) }
            }
            return snapshot()
        default: throw bridgeError("Unknown native method: \(method)")
        }
    }
    func snapshot() -> [String: Any] {
        var preps: [String: Any] = [:], models: [String: Any] = [:]
        for cap in Capability.allCases {
            let key = cap.rawValue.lowercased()
            let prep = store.state.preparations[cap.rawValue] ?? Preparation()
            preps[key] = PromethWebMapping.preparation(prep)
            let selected = store.preparationModels(cap)
            if let m = selected.first { models[key] = ["id": m.id, "label": m.name, "sizeGB": Double(selected.reduce(Int64(0)) { $0 + $1.downloadBytes }) / 1e9] }
        }
        let evil = store.state.preparations["Evil"] ?? Preparation()
        preps["evil"] = ["status": evil.status.rawValue.lowercased(), "progress": evil.progress]
        if let m = store.selectedModel(.evil) { models["evil"] = ["id": m.id, "label": m.name, "sizeGB": Double(m.downloadBytes) / 1e9] }
        let extras = store.chats.flatMap { $0.messages }.reduce(into: [String: [[String: Any]]]()) { result, message in result[message.id.uuidString] = mappedExtras([message]) }
        return ["engine": ["loading": store.model.isModelLoading, "progress": store.model.modelLoadingProgress ?? 0, "model": store.model.modelLoadingID ?? "", "text": store.model.modelLoadingStatusText ?? "Ready"], "onboardingComplete": store.state.onboardingComplete, "appearance": store.state.appearance, "evilEnabled": store.state.evilEnabled, "selected": store.state.selected.map { $0.rawValue.lowercased() }, "preps": preps, "models": models, "chats": store.chats.map(PromethWebMapping.conversation), "extras": extras, "skills": store.state.skills.map { ["id": $0.id.uuidString, "name": $0.name, "instructions": $0.instructions, "enabled": $0.isEnabled] }, "webSearch": store.state.webSearch, "modelOptions": PromethModelFamily.allCases.map { family in ["family": family.rawValue, "label": family.label, "selected": store.selectedModel(family)?.id ?? "", "options": store.modelOptions(family).map { ["id": $0.id, "label": $0.name] }] }, "specs": ["chip": store.macSpecs.chip, "memoryGB": store.macSpecs.memoryGB, "freeStorageGB": store.macSpecs.freeStorageGB, "summary": store.macSpecs.summary]]
    }
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        guard frame.request.url?.scheme == "prometh-ui", frame.request.url?.host == "app" else { completionHandler(nil); return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        completionHandler(panel.runModal() == .OK ? panel.urls : nil)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "prometh-ui", url.host == "app" { decisionHandler(.allow) }
        else if navigationAction.navigationType == .linkActivated, ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url); decisionHandler(.cancel) }
        else { decisionHandler(.cancel) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        return nil
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        decisionHandler(origin.protocol == "prometh-ui" && origin.host == "app" && type == .microphone ? .grant : .deny)
    }
}
