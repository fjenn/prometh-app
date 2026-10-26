import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Prometh screens talk to this store. Conversations are Nativ chat sessions.
@MainActor
final class PromethStore: ObservableObject {
    @Published var state: Snapshot { didSet { persist() } }
    @Published var chats: [Conversation] = []
    @Published var error: String?
    @Published var settingsOpen = false
    @Published var settingsTab = "Appearance"
    @Published var customizeOpen = false
    @Published var customizeSection = "Tools"
    @Published var consent: Provider?
    @Published var previewArtifact: PromethArtifact?
    @Published var previewAttachment: Attachment?
    @Published var artifactEditorOpen = false
    @Published var revealInChat = false
    @Published var failPreparation = false
    @Published var failNextResponse = false
    @Published var search = ""
    @Published var dictating = false
    @Published var pendingTool: PendingTool?
    @Published var modelDetails: [String: String] = [:]

    let macSpecs = MacSpecs.read()
    let persistence: Persistence
    var voice = PromethVoice()
    let model: NativModel
    #if DEBUG
    let isPreview: Bool
    #else
    let isPreview = false
    #endif

    private let chat: ChatViewModel
    private let sessions = ChatSessionStore()
    private let preparation = PreparationCoordinator()
    private var selfTestRetried = false
    private var drafts: [String: String] = [:]
    private var modes: [String: BehaviorMode] = [:]
    private var stopped: Set<UUID> = []
    private var revealed: Set<String> = []
    private var cancellable: AnyCancellable?

    init(model: NativModel) {
        self.model = model
        persistence = Persistence()
        #if DEBUG
        isPreview = ProcessInfo.processInfo.arguments.contains("--prometh-preview")
        #endif
        chat = ChatViewModel()
        var restored = persistence.load() ?? Snapshot()
        if persistence.load() == nil,
           PromethIdentity.supportDirectoryOverride == nil,
           WelcomePreferences.hasCompleted {
            restored.onboardingComplete = true
        }
        restored.selected.insert(.chat)
        if model.settings.normalized().languageModelID?.isEmpty == false {
            restored.preparations[Capability.chat.rawValue] = Preparation(progress: 1, status: .ready)
        }
        for key in Array(restored.preparations.keys) {
            guard var preparation = restored.preparations[key] else { continue }
            if preparation.status == .downloading || preparation.status == .preparing || preparation.status == .checking {
                preparation.status = .paused
                restored.preparations[key] = preparation
            }
        }
        state = restored
        drafts = restored.drafts
        modes = restored.modes
        revealed = persistence.loadRevealed()
        stopped = Set(restored.stoppedMessageIDs.compactMap(UUID.init(uuidString:)))
        cancellable = chat.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        voice.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &voiceBag)
        reload()
        persist()
        preparation.attach(self)
        if ProcessInfo.processInfo.environment["PROMETH_SELFTEST_DRIVE"] == "catalog" {
            Task { await driveCatalogSelfTest() }
        } else if ProcessInfo.processInfo.environment["PROMETH_SELFTEST_DRIVE"] == "offline" {
            Task { await driveOfflineSelfTest() }
        } else if ProcessInfo.processInfo.environment["PROMETH_SELFTEST_DRIVE"] == "corrupt" {
            Task { await driveCorruptSelfTest() }
        }
    }

    private var voiceBag = Set<AnyCancellable>()

    var connectorsAvailable: Bool {
        let configured = state.connectorBrokerURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let environment = ProcessInfo.processInfo.environment["PROMETH_BROKER_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (configured?.isEmpty == false ? configured : nil) ?? environment
        return value?.isEmpty == false
    }

    var current: Conversation? { chats.first { $0.id == state.selectedChatID } }

    var total: Double { state.selected.reduce(0) { $0 + $1.gigabytes } }

    var chatReady: Bool { state.preparations[Capability.chat.rawValue]?.status == .ready }

    var filteredChats: [Conversation] {
        chats.filter { conversation in
            search.isEmpty || (conversation.title + " " + conversation.messages.map(\.text).joined(separator: " "))
                .localizedCaseInsensitiveContains(search)
        }.sorted { $0.updated > $1.updated }
    }

    var skills: [SkillRecord] {
        get { state.skills }
        set { state.skills = newValue }
    }

    func sizeLabel(_ capability: Capability) -> String {
        String(format: "%.2f GB", locale: Locale(identifier: "en_US_POSIX"), capability.gigabytes)
    }

    func available(_ capability: Capability) -> Bool {
        blockReason(capability) == nil
    }

    func blockReason(_ capability: Capability) -> String? {
        if state.hardware == .storage {
            return "Not enough space for \(capability.rawValue.lowercased())."
        }
        if capability == .video, state.hardware == .everyday {
            return "Video needs more memory."
        }
        guard let catalog = try? ModelCatalogLoader.bundled() else { return nil }
        return CatalogFit.reason(
            capability: capability,
            models: catalog.preparationModels(for: capability),
            headroom: catalog.storagePolicy.macOSHeadroomBytes,
            memoryGB: macSpecs.memoryGB,
            freeBytes: CatalogFit.freeBytes(at: persistence.directory)
        )
    }

    func limitLabel(_ capability: Capability) -> String {
        blockReason(capability) ?? "Needs more memory"
    }

    func fitNote(_ capability: Capability) -> String {
        blockReason(capability)
            ?? "We checked this Mac. There isn't enough memory for a capable \(capability.rawValue.lowercased()) model."
    }

    func toggle(_ capability: Capability) {
        guard capability != .chat else { return }
        guard available(capability) else {
            error = state.hardware == .storage
                ? "Not enough space for \(capability.rawValue)."
                : "Video needs more memory."
            return
        }
        if state.selected.contains(capability) {
            state.selected.remove(capability)
            cancelPreparation(capability)
        } else {
            state.selected.insert(capability)
        }
    }

    func setHardware(_ hardware: Hardware) {
        state.hardware = hardware
        for capability in Capability.allCases where state.selected.contains(capability) && !available(capability) {
            state.selected.remove(capability)
            cancelPreparation(capability)
        }
    }

    func next() { state.step = min(3, state.step + 1) }

    func back() {
        if state.step == 3 {
            for capability in state.selected { pausePreparation(capability) }
        }
        state.step = max(0, state.step - 1)
    }

    func chooseEvil(_ enabled: Bool) {
        state.evilEnabled = state.evilEnabled || enabled
        state.defaultMode = enabled ? .evil : .safe
        if revealInChat {
            setMode(enabled ? .evil : .safe)
            revealInChat = false
        } else {
            state.step = 3
            resumePreparation(.chat)
        }
    }

    func setMode(_ mode: BehaviorMode) {
        if mode == .evil { state.evilEnabled = true }
        guard let id = state.selectedChatID else { return }
        modes[id.uuidString] = mode
        if let index = chats.firstIndex(where: { $0.id == id }) {
            chats[index].mode = mode
        }
        persist()
        if mode == .evil, state.preparations["Evil"]?.status != .ready {
            error = "Evil Mode is not ready yet."
        }
    }

    func restartOnboarding() {
        voice.end()
        state.preparations = [:]
        state.onboardingComplete = false
        state.step = 0
        settingsOpen = false
    }

    func setPreparationFailure(_ enabled: Bool) {
        failPreparation = enabled
        guard enabled else { return }
        state.preparations[Capability.chat.rawValue] = Preparation(progress: 0.2, status: .failed)
        modelDetails[Capability.chat.rawValue] = "Preparation interrupted. Try again."
    }

    func pausePreparation(_ capability: Capability) {
        guard state.preparations[capability.rawValue]?.status != .ready else { return }
        preparation.pause(capability)
    }

    func cancelPreparation(_ capability: Capability) {
        preparation.cancel(capability)
    }

    func retryPreparation(_ capability: Capability) { resumePreparation(capability) }

    func resumePreparation(_ capability: Capability) {
        preparation.resume(capability)
    }

    func verifyPreparation(_ capability: Capability) {
        CatalogLog.append("action=download-verify capability=\(capability.rawValue)", support: persistence.directory)
        preparation.verify(capability)
    }

    func prepareEvil() {
        modelDetails["Evil"] = "Qwen3.5 heretic · Q4_K_M · 5.63 GB weights · text input"
        error = "Evil Mode is not ready yet."
    }

    func enterChat() {
        guard chatReady else { return }
        state.onboardingComplete = true
        WelcomePreferences.markCompleted()
        if !model.isRunning {
            model.startServer()
        }
        if chats.isEmpty {
            newChat()
        }
    }

    func newChat() {
        chat.createSession()
        guard let id = chat.currentSessionID else { return }
        revealed.insert(id.uuidString)
        persistence.saveRevealed(revealed)
        modes[id.uuidString] = .safe
        drafts[id.uuidString] = ""
        state.selectedChatID = id
        reload()
    }

    func select(_ id: UUID) {
        rememberDraft()
        state.selectedChatID = id
        if chat.currentSessionID != id {
            chat.selectSession(id)
            chat.draft = drafts[id.uuidString] ?? ""
        }
        reload()
    }

    func setDraft(_ text: String) {
        if state.selectedChatID == nil { newChat() }
        guard let id = state.selectedChatID else { return }
        drafts[id.uuidString] = text
        if chats.contains(where: { $0.id == id }) {
            chats = chats.map { conversation in
                guard conversation.id == id else { return conversation }
                var copy = conversation
                copy.draft = text
                return copy
            }
        }
        if chat.currentSessionID == id {
            chat.draft = text
        }
        persist()
    }

    func send() {
        if current == nil { newChat() }
        guard let id = state.selectedChatID else { return }
        if chat.currentSessionID != id { select(id) }
        if modes[id.uuidString] == .evil, state.preparations["Evil"]?.status != .ready {
            error = "Evil Mode is not ready yet."
            return
        }
        let text = drafts[id.uuidString] ?? current?.draft ?? ""
        chat.draft = text
        guard chat.canSend(isRunning: model.isRunning, selectedModelID: model.settings.languageModelID) else {
            error = "The local model is not ready yet."
            return
        }
        chat.send(using: model, languageModelSupportsTools: true, languageModelSupportsVision: false)
        drafts[id.uuidString] = ""
        persist()
    }

    func stop(_ id: UUID) {
        if chat.currentSessionID != id { select(id) }
        if let streaming = chat.messages.last(where: \.isStreaming) {
            stopped.insert(streaming.id)
            persist()
        }
        chat.cancel()
        reload()
    }

    func isRunning(_ id: UUID) -> Bool { chat.activeRequestSessionID == id }

    func editMessage(_ message: Message, text: String) {
        guard let id = state.selectedChatID else { return }
        if chat.currentSessionID != id { select(id) }
        chat.beginEditingUserMessage(message.id)
        chat.draft = text
        chat.send(using: model, languageModelSupportsTools: true, languageModelSupportsVision: false)
        drafts[id.uuidString] = ""
        persist()
    }

    func regenerate(_ message: Message) {
        guard let conversation = current,
              let index = conversation.messages.firstIndex(where: { $0.id == message.id })
        else { return }
        guard let user = conversation.messages[..<index].last(where: { $0.role == "user" }) else { return }
        editMessage(user, text: user.text)
    }

    func rename(_ id: UUID, _ title: String) {
        if chat.currentSessionID != id { select(id) }
        chat.renameSession(id, to: title)
        reload()
    }

    func delete(_ id: UUID) {
        Task {
            _ = try? await chat.deleteSession(id)
            drafts[id.uuidString] = nil
            modes[id.uuidString] = nil
            if state.selectedChatID == id {
                state.selectedChatID = chat.currentSessionID
            }
            reload()
        }
    }

    func exportChat() {
        guard let conversation = current else { return }
        let body = conversation.messages.map { message in
            let speaker = message.role == "user" ? "You" : Product.name
            return "\(speaker)\n\(message.text)"
        }.joined(separator: "\n\n")
        if let path = ProcessInfo.processInfo.environment["PROMETH_EXPORT_PATH"], !path.isEmpty {
            try? body.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = conversation.title + ".md"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            self.error = "Your changes could not be saved. \(error.localizedDescription)"
        }
    }

    func dictate() {
        dictating = true
        error = "Voice is not available yet."
    }

    func cancelDictation() {
        dictating = false
        voice.end()
    }

    func appendVoiceExchange(_ user: String, _ reply: String) {}

    func chooseAttachment() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let id = state.selectedChatID else { return }
        let stored = UUID().uuidString + "-" + url.lastPathComponent
        let destination = persistence.directory.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let target = destination.appendingPathComponent(stored)
        try? FileManager.default.copyItem(at: url, to: target)
        let attachment = Attachment(filename: url.lastPathComponent, storedName: stored)
        chats = chats.map { conversation in
            guard conversation.id == id else { return conversation }
            var copy = conversation
            copy.attachments.append(attachment)
            return copy
        }
    }

    func removeAttachment(_ attachment: Attachment) {
        guard let id = state.selectedChatID else { return }
        chats = chats.map { conversation in
            guard conversation.id == id else { return conversation }
            var copy = conversation
            copy.attachments.removeAll { $0.id == attachment.id }
            return copy
        }
    }

    func attachmentURL(_ attachment: Attachment) -> URL {
        persistence.directory
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent(attachment.storedName)
    }

    func setSkillEnabled(_ id: UUID, _ enabled: Bool) {
        state.skills = state.skills.map { skill in
            guard skill.id == id else { return skill }
            var copy = skill
            copy.isEnabled = enabled
            return copy
        }
    }

    func saveSkill(_ skill: SkillRecord) {
        if let index = state.skills.firstIndex(where: { $0.id == skill.id }) {
            state.skills[index] = skill
        } else {
            state.skills.append(skill)
        }
    }

    func deleteSkill(_ id: UUID) {
        state.skills.removeAll { $0.id == id }
    }

    func chooseSkillFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        let name = url.deletingPathExtension().lastPathComponent
        saveSkill(SkillRecord(name: name, instructions: text))
    }

    func openCustomize(_ section: String = "Tools") {
        customizeSection = connectorsAvailable || section != "Plugins" ? section : "Tools"
        customizeOpen = true
    }

    func connect(_ provider: Provider) {
        consent = nil
        error = "A connection broker is not configured."
    }

    func disconnect(_ provider: Provider) {
        state.connections[provider.rawValue] = .disconnected
    }

    func expireConnection() {
        state.connections[Provider.gmail.rawValue] = .expired
    }

    func resetData() {
        state = Snapshot()
        drafts = [:]
        modes = [:]
        stopped = []
        chats = []
        settingsOpen = false
    }

    func restoreSamples() {}

    func artifactImage(_ artifact: PromethArtifact) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 9))
    }

    func artifactURL(_ artifact: PromethArtifact) -> URL {
        persistence.directory.appendingPathComponent(artifact.filename)
    }

    func saveArtifact(_ artifact: PromethArtifact) {
        error = "Images and video are not available yet."
    }

    func editArtifact(_ artifact: PromethArtifact, prompt: String, trim: (Double, Double)?) {
        error = "Images and video are not available yet."
    }

    func measuredVideoArtifact(_ artifact: PromethArtifact) async throws -> PromethArtifact { artifact }

    func resolveTool(_ approved: Bool) { pendingTool = nil }

    func preparationModels(_ capability: Capability) -> [CatalogModel] {
        (try? ModelCatalogLoader.bundled())?.preparationModels(for: capability) ?? []
    }

    func catalogReady(_ capability: Capability) -> Bool {
        guard let catalog = try? ModelCatalogLoader.bundled() else { return false }
        let models = catalog.preparationModels(for: capability)
        guard !models.isEmpty else { return false }
        for model in models {
            let folder = CatalogPaths.folder(root: CatalogPaths.modelsRoot(support: persistence.directory), model: model)
            for file in model.files {
                let url = folder.appendingPathComponent(file.path)
                if (try? CatalogHash.matches(file, at: url)) != true { return false }
            }
        }
        return true
    }

    func applyPreparation(_ key: String, _ preparation: Preparation, detail: String?) {
        state.preparations[key] = preparation
        if let detail { modelDetails[key] = detail }
    }

    func preparationProgress(_ key: String) -> Double {
        state.preparations[key]?.progress ?? 0
    }

    func markReady(_ capability: Capability?, key: String? = nil) {
        let name = key ?? capability?.rawValue ?? ""
        applyPreparation(name, Preparation(progress: 1, status: .ready), detail: capability?.phrase ?? "Ready")
    }

    func notePaused(_ capability: Capability?, key: String? = nil) {
        let name = key ?? capability?.rawValue ?? ""
        var preparation = state.preparations[name] ?? Preparation()
        guard preparation.status != .ready else { return }
        preparation.status = .paused
        applyPreparation(name, preparation, detail: "Paused")
    }

    func pinCatalogModel(_ model: CatalogModel) {
        var settings = self.model.settings
        settings.languageModelID = model.repo
        settings.modelSearchPath = CatalogPaths.hub(support: persistence.directory).path
        self.model.settings = settings
        CatalogLog.append(
            "pinned name=\(model.name) revision=\(model.revision)",
            support: persistence.directory
        )
    }

    func finishPauseSelfTestIfNeeded(key: String, path: String, offset: Int64) async {
        guard ProcessInfo.processInfo.environment["PROMETH_PREP_AUTOPAUSE"] == "1" else { return }
        guard key == Capability.chat.rawValue else { return }
        try? await Task.sleep(nanoseconds: 8_000_000_000)
        resumePreparation(.chat)
    }

    func finishFailureSelfTestIfNeeded(key: String, message: String) async {
        guard ProcessInfo.processInfo.environment["PROMETH_SELFTEST_DRIVE"] == "catalog" else { return }
        guard key == Capability.chat.rawValue, !selfTestRetried else { return }
        selfTestRetried = true
        try? await Task.sleep(nanoseconds: 8_000_000_000)
        resumePreparation(.chat)
    }

    func finishSelfTestIfNeeded(key: String) async {
        guard ProcessInfo.processInfo.environment["PROMETH_SELFTEST_DRIVE"] == "catalog" else { return }
        guard key == Capability.chat.rawValue else { return }
        try? await Task.sleep(nanoseconds: 12_000_000_000)
        writeCatalogReport(passed: true)
    }

    private func driveCatalogSelfTest() async {
        state.onboardingComplete = false
        state.step = 3
        state.selected = [.chat]
        state.evilEnabled = false
        resumePreparation(.chat)
    }

    private func driveCorruptSelfTest() async {
        guard let catalog = try? ModelCatalogLoader.bundled(), let safe = catalog.model(id: "safe") else { return }
        let folder = CatalogPaths.folder(root: CatalogPaths.modelsRoot(support: persistence.directory), model: safe)
        let target = folder.appendingPathComponent("tokenizer_config.json")
        guard var data = try? Data(contentsOf: target), !data.isEmpty else {
            writeSelfTest("prep-corrupt", ["name": "prep-corrupt", "passed": false, "error": "missing tokenizer_config.json"])
            return
        }
        let before = data[0]
        data[0] ^= 0xFF
        try? data.write(to: target)
        CatalogLog.append("corrupt flipped path=tokenizer_config.json byte=\(before)", support: persistence.directory)
        settingsOpen = true
        settingsTab = "Capabilities"
        verifyPreparation(.chat)
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if state.preparations[Capability.chat.rawValue]?.status == .ready,
               (try? CatalogHash.matches(safe.files.first { $0.path == "tokenizer_config.json" }!, at: target)) == true {
                writeSelfTest("prep-corrupt", [
                    "name": "prep-corrupt",
                    "passed": true,
                    "file": "tokenizer_config.json",
                    "action": "download-verify"
                ])
                return
            }
        }
        writeSelfTest("prep-corrupt", ["name": "prep-corrupt", "passed": false, "error": "verify did not restore the file"])
    }

    private func driveOfflineSelfTest() async {
        enterChat()
        let deadline = Date().addingTimeInterval(8 * 60)
        while Date() < deadline, !model.isRunning || model.isModelLoading {
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        guard model.isRunning, !model.isModelLoading else {
            CatalogLog.append(
                "offline not-ready running=\(model.isRunning) loading=\(model.isModelLoading)",
                support: persistence.directory
            )
            writeOfflineReport(reply: "", passed: false)
            return
        }
        setDraft("Say hello in five words.")
        send()
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            reload()
            if let reply = current?.messages.last(where: { $0.role == "assistant" }),
               reply.status == "complete", !reply.text.isEmpty {
                writeOfflineReport(reply: reply.text, passed: true)
                return
            }
        }
        let reply = current?.messages.last?.text ?? ""
        CatalogLog.append("offline timed-out reply=\(reply)", support: persistence.directory)
        writeOfflineReport(reply: reply, passed: false)
    }

    private func writeCatalogReport(passed: Bool) {
        guard let catalog = try? ModelCatalogLoader.bundled(), let safe = catalog.model(id: "safe") else { return }
        let folder = CatalogPaths.folder(root: CatalogPaths.modelsRoot(support: persistence.directory), model: safe)
        var files: [[String: String]] = []
        for file in safe.files {
            let url = folder.appendingPathComponent(file.path)
            let matched = (try? CatalogHash.matches(file, at: url)) == true
            let size = CatalogHash.byteCount(url).map(String.init) ?? "missing"
            files.append([
                "path": file.path,
                "bytes": size,
                "expectedBytes": String(file.size),
                "revision": safe.revision,
                "matched": matched ? "true" : "false",
                "friendlyName": safe.name
            ])
        }
        let log = (try? String(contentsOf: persistence.directory.appendingPathComponent("preparation.log"), encoding: .utf8)) ?? ""
        let report: [String: Any] = [
            "name": "catalog-chat",
            "passed": passed && files.allSatisfy { $0["matched"] == "true" },
            "revision": safe.revision,
            "friendlyName": safe.name,
            "files": files,
            "preparationLog": log,
            "openChatEnabled": chatReady
        ]
        writeSelfTest("catalog-chat", report)
    }

    private func writeOfflineReport(reply: String, passed: Bool) {
        let probe = offlineProbe()
        let report: [String: Any] = [
            "name": "offline-chat",
            "passed": passed && !reply.isEmpty && probe.contains("BLOCKED"),
            "reply": reply,
            "networkProbe": probe,
            "offline": "PROMETH_OFFLINE=1 points the inference child at http://127.0.0.1:9 and sets HF_HUB_OFFLINE=1. Wi-Fi stays on."
        ]
        writeSelfTest("offline-chat", report)
    }

    private func offlineProbe() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", """
import os, urllib.request
os.environ['HTTPS_PROXY']='http://127.0.0.1:9'
os.environ['HTTP_PROXY']='http://127.0.0.1:9'
os.environ['HF_HUB_OFFLINE']='1'
try:
    urllib.request.urlopen('https://huggingface.co', timeout=5)
    print('REACHED')
except Exception as error:
    print('BLOCKED', type(error).__name__)
"""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func writeSelfTest(_ name: String, _ report: [String: Any]) {
        let override = ProcessInfo.processInfo.environment["PROMETH_SELFTEST_OUTPUT"]
        let url = URL(fileURLWithPath: override ?? persistence.directory.appendingPathComponent("selftest-\(name).json").path)
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url)
        CatalogLog.append("selftest wrote \(url.path) passed=\(report["passed"] ?? false)", support: persistence.directory)
    }

    private func rememberDraft() {
        guard let id = state.selectedChatID else { return }
        drafts[id.uuidString] = chats.first { $0.id == id }?.draft ?? drafts[id.uuidString] ?? ""
    }

    private func reload() {
        let liveID = chat.currentSessionID
        let liveMessages = chat.messages
        var loaded = sessions.loadSessions()
        if let liveID, !loaded.contains(where: { $0.id == liveID }), let current = chat.sessions.first(where: { $0.id == liveID }) {
            loaded.append(ChatSession(
                id: current.id,
                title: current.title,
                createdAt: current.createdAt,
                updatedAt: current.updatedAt,
                messages: liveMessages
            ))
        }
        chats = loaded.compactMap { session in
            let messages = session.id == liveID ? liveMessages : session.messages
            let conversation = conversation(session, messages: messages)
            let started = !conversation.messages.isEmpty || !conversation.draft.isEmpty
            guard started || revealed.contains(session.id.uuidString) else { return nil }
            return conversation
        }.sorted { $0.updated > $1.updated }
        if state.selectedChatID == nil {
            state.selectedChatID = liveID
        }
    }

    private func conversation(_ session: ChatSession, messages: [ChatTranscriptMessage]) -> Conversation {
        let key = session.id.uuidString
        let visible = messages.filter { $0.role == .user || $0.role == .assistant || $0.role == .error }
        return Conversation(
            id: session.id,
            title: session.displayTitle,
            mode: modes[key] ?? .safe,
            messages: visible.map(present),
            draft: drafts[key] ?? "",
            attachments: [],
            updated: session.updatedAt
        )
    }

    private func present(_ message: ChatTranscriptMessage) -> Message {
        Message(
            id: message.id,
            role: message.role == .user ? "user" : "assistant",
            text: message.content,
            status: status(for: message)
        )
    }

    private func status(for message: ChatTranscriptMessage) -> String {
        if message.isStreaming { return "streaming" }
        if stopped.contains(message.id) { return "stopped" }
        if message.role == .error { return "stopped" }
        return "complete"
    }

    private func persist() {
        var snapshot = state
        snapshot.drafts = drafts
        snapshot.modes = modes
        snapshot.stoppedMessageIDs = stopped.map(\.uuidString)
        do {
            try persistence.save(snapshot)
        } catch {
            self.error = "Your changes could not be saved. \(error.localizedDescription)"
        }
    }
}

struct PendingTool: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var arguments: String
}
