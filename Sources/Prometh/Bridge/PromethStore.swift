import AppKit
import Combine
import NativServerKit
import SwiftUI
import UniformTypeIdentifiers

/// Prometh screens talk to this store. Conversations are Nativ chat sessions.
@MainActor
final class PromethStore: ObservableObject {
    @Published var state: Snapshot {
        didSet {
            PromethWebPrefetch.enabled = state.webSearch
            persist()
        }
    }
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
    @Published var requestedMode: BehaviorMode?
    @Published var dictating = false
    @Published var pendingTool: PendingTool?
    @Published var pendingConnectorApproval: PromethConnectorConsent?
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
    private let connectorHost: PromethConnectorHost
    private let sessions = ChatSessionStore()
    private let preparation = PreparationCoordinator()
    private var selfTestRetried = false
    private var drafts: [String: String] = [:]
    private var composerAttachments: [String: [Attachment]] = [:]
    private var modes: [String: BehaviorMode] = [:]
    private var stopped: Set<UUID> = []
    private var revealed: Set<String> = []
    private var localMedia: [UUID: [Message]] = [:]
    private var cancellable: AnyCancellable?

    init(model: NativModel) {
        self.model = model
        persistence = Persistence()
        #if DEBUG
        isPreview = ProcessInfo.processInfo.arguments.contains("--prometh-preview")
        #endif
        chat = ChatViewModel()
        connectorHost = PromethConnectorHost()
        connectorHost.attach(chat)
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
        if Self.evilWeightsInstalled(support: persistence.directory) {
            restored.preparations["Evil"] = Preparation(progress: 1, status: .ready)
            restored.evilEnabled = true
        }
        for key in Array(restored.preparations.keys) {
            guard var preparation = restored.preparations[key] else { continue }
            if preparation.status == .downloading || preparation.status == .preparing || preparation.status == .checking {
                preparation.status = .paused
                restored.preparations[key] = preparation
            }
        }
        state = restored
        PromethWebPrefetch.enabled = restored.webSearch
        drafts = restored.drafts
        modes = restored.modes
        publishModes()
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
        connectorHost.apply(brokerURL: brokerURL)
        refreshConnections()
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

    var brokerURL: String? {
        let configured = state.connectorBrokerURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let environment = ProcessInfo.processInfo.environment["PROMETH_BROKER_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (configured?.isEmpty == false ? configured : nil) ?? environment
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    var connectorsAvailable: Bool { brokerURL != nil || PromethConnectorSecret.hasAPIKeyFile() }

    func setBroker(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        state.connectorBrokerURL = trimmed.isEmpty ? nil : trimmed
        connectorHost.apply(brokerURL: brokerURL)
    }

    func approveConnector() {
        guard let id = pendingConnectorApproval?.id else { return }
        chat.confirmToolConsent(id)
    }

    func denyConnector() {
        guard let id = pendingConnectorApproval?.id else { return }
        chat.denyToolConsent(id)
    }

    /// A swipe-away denies only while the tool is still waiting. An approval
    /// that already moved the tool to running is left alone.
    func connectorSheetDismissed() {
        guard let id = pendingConnectorApproval?.id else { return }
        let stillWaiting = chat.messages.contains { $0.id == id && $0.toolStatus == .awaitingConsent }
        guard stillWaiting else { return }
        chat.denyToolConsent(id)
    }

    var current: Conversation? { chats.first { $0.id == state.selectedChatID } }

    var displayedMode: BehaviorMode {
        let raw = PromethModeTable.displayed(
            chatMode: current?.mode.rawValue,
            requested: requestedMode?.rawValue,
            defaultMode: state.defaultMode.rawValue
        )
        return BehaviorMode(rawValue: raw) ?? .safe
    }

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
        if enabled {
            preparation.resumeModel(key: "Evil", modelID: "evil")
        }
        if revealInChat {
            setMode(enabled ? .evil : .safe)
            revealInChat = false
        } else {
            state.step = 3
            resumePreparation(.chat)
        }
    }

    func setMode(_ mode: BehaviorMode) {
        if mode == .evil {
            state.evilEnabled = true
            if state.preparations["Evil"]?.status != .ready {
                if Self.evilWeightsInstalled(support: persistence.directory) {
                    state.preparations["Evil"] = Preparation(progress: 1, status: .ready)
                    error = nil
                } else {
                    error = "Evil Mode is not ready yet."
                    prepareEvil()
                }
            }
        }
        guard let id = state.selectedChatID else {
            requestedMode = mode
            return
        }
        requestedMode = nil
        modes[id.uuidString] = mode
        PromethModeTable.set(id, mode.rawValue)
        if let index = chats.firstIndex(where: { $0.id == id }) {
            chats[index].mode = mode
        }
        persist()
        if mode == .evil, state.preparations["Evil"]?.status != .ready {
            prepareEvil()
            error = nil
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
        preparation.resumeModel(key: "Evil", modelID: "evil")
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
        let requested = requestedMode?.rawValue
        requestedMode = nil
        let opening = PromethModeTable.openingMode(
            existingChats: chats.count,
            defaultMode: state.defaultMode.rawValue,
            requested: requested
        )
        modes[id.uuidString] = BehaviorMode(rawValue: opening) ?? .safe
        PromethModeTable.set(id, opening)
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

    func send(_ typed: String? = nil) {
        if current == nil { newChat() }
        PromethPromptAdditionsMode.current = current?.mode.rawValue ?? BehaviorMode.safe.rawValue
        guard let id = state.selectedChatID else { return }
        if chat.currentSessionID != id { select(id) }
        if modes[id.uuidString] == .evil, state.preparations["Evil"]?.status != .ready {
            prepareEvil()
            error = "Evil Mode is still getting ready."
            scheduleSendWhenReady()
            return
        }
        let stored = drafts[id.uuidString] ?? current?.draft ?? ""
        let raw = (typed?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? typed! : stored
        let text = PromethChatTitle.collapseExactRepeat(raw)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        drafts[id.uuidString] = text
        chat.draft = text
        guard readyToSend() else {
            error = "The local model is not ready yet."
            scheduleSendWhenReady()
            return
        }
        if !deliver(id) {
            error = "The local model is not ready yet."
            scheduleSendWhenReady()
        }
    }

    private var waitingToSend = false

    private func readyToSend() -> Bool {
        !model.isModelLoading && chat.canSend(
            isRunning: model.isRunning,
            selectedModelID: model.settings.languageModelID
        )
    }

    private func scheduleSendWhenReady() {
        guard !waitingToSend else { return }
        waitingToSend = true
        guard let id = state.selectedChatID else {
            waitingToSend = false
            return
        }
        let captured = drafts[id.uuidString] ?? ""
        Task { @MainActor in
            for _ in 0..<120 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard waitingToSend, state.selectedChatID == id else { return }
                let live = drafts[id.uuidString] ?? ""
                let text = live.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? captured : live
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    waitingToSend = false
                    return
                }
                if chat.currentSessionID != id { select(id) }
                drafts[id.uuidString] = text
                chat.draft = text
                if modes[id.uuidString] == .evil, state.preparations["Evil"]?.status != .ready {
                    continue
                }
                if readyToSend(), deliver(id) {
                    return
                }
            }
            waitingToSend = false
        }
    }

    @discardableResult
    private func deliver(_ id: UUID) -> Bool {
        let text = (drafts[id.uuidString] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        chat.draft = text
        chat.send(using: model, languageModelSupportsTools: true, languageModelSupportsVision: false)
        let saved = chat.messages.contains {
            $0.role == .user && $0.content.trimmingCharacters(in: .whitespacesAndNewlines) == text
        }
        guard saved else { return false }
        drafts[id.uuidString] = ""
        composerAttachments[id.uuidString] = []
        waitingToSend = false
        error = nil
        persist()
        return true
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
        voice.denied = false
        voice.phase = "Listening"
        voice.recovery = ""
        if let text = PromethVoiceDefaults.fileTranscript() {
            applyTranscript(text, fromFile: true)
            return
        }
        Task { await startMicrophone() }
    }

    func finishDictation() {
        let url = recorder.stop()
        guard dictating else { return }
        voice.finishRecording()
        guard let url else {
            dictating = false
            return
        }
        Task { await transcribeRecording(url) }
    }

    func cancelDictation() {
        _ = recorder.stop()
        dictating = false
        voice.end()
    }

    func copyResponse(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        if let path = ProcessInfo.processInfo.environment["PROMETH_COPY_LOG"], !path.isEmpty {
            try? text.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        }
    }

    func stopSpeech() {
        speechToken += 1
        speechPlayer?.stop()
        speechPlayer = nil
        if voice.phase == "Speaking" {
            voice.phase = voice.denied ? "Microphone unavailable" : "Listening"
        }
    }

    func speak(_ text: String) {
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return }
        voice.readAloud(spoken)
        speechToken += 1
        let token = speechToken
        Task { @MainActor in
            do {
                let wav = try await PromethPocketSpeech.synthesize(spoken)
                guard token == speechToken, !voice.muted else {
                    if token != speechToken, voice.phase == "Speaking" {
                        voice.phase = voice.denied ? "Microphone unavailable" : "Listening"
                    }
                    return
                }
                speechPlayer = NSSound(contentsOf: wav, byReference: false)
                speechPlayer?.play()
                while token == speechToken, speechPlayer?.isPlaying == true {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                if token == speechToken, voice.phase == "Speaking" {
                    voice.phase = voice.denied ? "Microphone unavailable" : "Listening"
                }
            } catch {
                if token == speechToken {
                    voice.phase = "Listening"
                    voice.recovery = "Speech could not be played. Try again."
                }
            }
        }
    }

    private let recorder = VoiceAudioRecorder()
    private var speechPlayer: NSSound?
    private var speechToken = 0

    private func applyTranscript(_ text: String, fromFile: Bool) {
        voice.finishRecording()
        voice.transcript = text
        let existing = drafts[state.selectedChatID?.uuidString ?? ""] ?? current?.draft ?? ""
        let separator = existing.isEmpty ? "" : " "
        setDraft(existing + separator + text)
        dictating = false
        if fromFile, let answer = PromethVoiceDefaults.selfTestAnswer(for: text) {
            appendVoiceExchange(text, answer)
            speak(answer)
            return
        }
        voice.phase = fromFile ? "Speaking" : "Listening"
    }

    private func startMicrophone() async {
        do {
            _ = try await recorder.start()
            guard dictating else {
                _ = recorder.stop()
                return
            }
            voice.phase = "Listening"
        } catch {
            dictating = false
            voice.denied = true
            voice.phase = "Microphone unavailable"
            voice.recovery = "Open System Settings and allow the microphone."
        }
    }

    private func transcribeRecording(_ url: URL) async {
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let data = try Data(contentsOf: url)
            let settings = model.settings.normalized()
            let client = NativAudioClient(
                baseURL: settings.serverBaseURL,
                apiKey: settings.serverAPIKey,
                timeout: 60
            )
            let modelID = PromethVoiceDefaults.speechModel(current: settings.speechToTextModelID)
            let result = try await client.transcribe(audioData: data, fileName: "dictation.wav", model: modelID)
            applyTranscript(result.text, fromFile: false)
        } catch {
            dictating = false
            voice.phase = "Listening"
            voice.recovery = "Dictation did not catch that. Try again."
        }
    }

    func appendVoiceExchange(_ user: String, _ reply: String) {
        guard !reply.isEmpty, let id = state.selectedChatID else { return }
        let replyMessage = Message(role: "assistant", text: reply, status: "complete")
        localMedia[id, default: []].append(replyMessage)
        reload()
    }

    func chooseAttachment() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let id = state.selectedChatID else { return }
        if chat.currentSessionID != id { select(id) }
        guard chat.attachFiles(fromURLs: [url]) else {
            error = "That file couldn't be read."
            return
        }
        composerAttachments[id.uuidString] = chat.pendingImageAttachments.map { attachment in
            Attachment(id: attachment.id, filename: attachment.filename, storedName: attachment.filename)
        }
        reload()
    }

    func removeAttachment(_ attachment: Attachment) {
        guard let id = state.selectedChatID else { return }
        chat.removePendingImageAttachment(attachment.id)
        var chips = composerAttachments[id.uuidString] ?? []
        chips.removeAll { $0.id == attachment.id }
        composerAttachments[id.uuidString] = chips
        reload()
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
        refreshConnections()
    }

    func connect(_ provider: Provider) {
        consent = nil
        error = nil
        Task {
            let result = await PromethConnectorClient.link(provider)
            if let url = result.redirectURL {
                NSWorkspace.shared.open(url)
                await pollConnection(provider)
            } else {
                error = result.message ?? "The authorization page did not open."
            }
        }
    }

    func disconnect(_ provider: Provider) {
        state.connections[provider.rawValue] = .disconnected
        Task {
            _ = await PromethConnectorClient.disconnect(provider)
            state.connections[provider.rawValue] = .disconnected
        }
    }

    func refreshConnections() {
        guard connectorsAvailable else { return }
        Task {
            for provider in Provider.allCases {
                await applyConnectionStatus(provider)
            }
        }
    }

    private func pollConnection(_ provider: Provider) async {
        for _ in 0..<30 {
            if await applyConnectionStatus(provider) { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    @discardableResult
    private func applyConnectionStatus(_ provider: Provider) async -> Bool {
        let result = await PromethConnectorClient.status(provider)
        if result.status == "connected" {
            state.connections[provider.rawValue] = .connected
            return true
        }
        if result.status == "expired" {
            state.connections[provider.rawValue] = .expired
            return true
        }
        return false
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
        let url = artifactURL(artifact)
        let poster = artifact.kind == "video"
            ? url.deletingPathExtension().appendingPathExtension("png")
            : url
        if let image = NSImage(contentsOf: poster), image.size.width > 1 {
            return image
        }
        return NSImage(size: NSSize(width: 16, height: 9))
    }

    func artifactURL(_ artifact: PromethArtifact) -> URL {
        if artifact.kind == "image" {
            return artifact.filename.split(separator: "/").reduce(
                persistence.directory.appendingPathComponent("MediaAssets", isDirectory: true)
            ) { url, part in
                url.appendingPathComponent(String(part))
            }
        }
        let direct = persistence.directory.appendingPathComponent(artifact.filename)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        return persistence.directory
            .appendingPathComponent("Media", isDirectory: true)
            .appendingPathComponent(artifact.filename)
    }

    private static func showsToolCard(_ name: String?) -> Bool {
        name == PromethGenerateVideoTool.toolName || name == "generate_image" || name == "edit_image"
    }

    private static func imageArtifact(_ message: ChatTranscriptMessage, in messages: [ChatTranscriptMessage]) -> PromethArtifact? {
        guard let attachment = message.imageAttachments.first,
              let relative = attachment.asset?.relativePath,
              !relative.isEmpty
        else { return nil }
        let imageMessages = messages.filter { $0.toolName == "generate_image" || $0.toolName == "edit_image" }
        let index = imageMessages.firstIndex { $0.id == message.id } ?? 0
        let parent = index > 0 ? imageMessages[index - 1].imageAttachments.first?.id : nil
        return PromethArtifact(
            id: attachment.id,
            kind: "image",
            filename: relative,
            prompt: attachment.generation?.prompt ?? "",
            parentID: message.toolName == "edit_image" ? parent : nil,
            version: index + 1,
            modelID: attachment.generation?.modelID
        )
    }

    func offerVideo() {
        state.selected.insert(.video)
        modelDetails["Video"] = "Video is not ready yet. Your draft is still here."
        settingsTab = "Capabilities"
        settingsOpen = true
        resumePreparation(.video)
    }

    func saveArtifact(_ artifact: PromethArtifact) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = artifact.filename
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            try? FileManager.default.copyItem(at: self.artifactURL(artifact), to: destination)
        }
    }

    func editArtifact(_ artifact: PromethArtifact, prompt: String, trim: (Double, Double)?) {
        guard artifact.kind == "video", let trim,
              let duration = PromethVideoPlan.trimDuration(start: trim.0, end: trim.1)
        else {
            error = "Images and video are not available yet."
            return
        }
        let source = artifactURL(artifact)
        let filename = "clip-\(UUID().uuidString).mp4"
        let dest = persistence.directory.appendingPathComponent(filename)
        let chatID = state.selectedChatID
        Task {
            do {
                try await PromethMediaWorker.trim(source: source, dest: dest, start: trim.0, end: trim.1)
                var next = artifact
                next.id = UUID()
                next.parentID = artifact.id
                next.version = artifact.version + 1
                next.filename = filename
                next.trimStart = trim.0
                next.trimEnd = trim.1
                next.duration = duration
                next.prompt = prompt.isEmpty ? artifact.prompt : prompt
                var message = Message(role: "assistant", text: "", status: "complete", artifact: next)
                message.id = next.id
                if let chatID {
                    self.localMedia[chatID, default: []].append(message)
                }
                self.reload()
            } catch {
                self.error = PromethInterruptedError.llamaUnavailable.errorDescription
            }
        }
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
        let waiting = liveMessages.first {
            $0.toolStatus == .awaitingConsent && PromethConnectorApproval.isExecute($0.toolName)
        }
        if waiting?.id != pendingConnectorApproval?.id {
            pendingConnectorApproval = waiting.map { PromethConnectorConsent(id: $0.id) }
        }
    }

    private func conversation(_ session: ChatSession, messages: [ChatTranscriptMessage]) -> Conversation {
        let key = session.id.uuidString
        let visible = messages.filter { message in
            message.role == .user || message.role == .assistant || message.role == .error
                || (message.role == .tool && Self.showsToolCard(message.toolName))
        }
        let prompts = messages.filter { $0.role == .user }.map(\.content)
        return Conversation(
            id: session.id,
            title: PromethConversationTitle.title(
                custom: session.customTitle,
                preserveStored: session.scheduledTaskID != nil,
                stored: session.title,
                prompts: prompts
            ),
            mode: modes[key] ?? .safe,
            messages: visible.compactMap { message in
                var item = present(message)
                if message.role == .assistant {
                    let hasToolCalls = !message.toolCalls.isEmpty || !message.streamingToolCalls.isEmpty
                    let lastInTurn = isLastAssistantInTurn(message.id, in: messages)
                    if let text = PromethTranscript.visibleText(
                        content: message.content,
                        reasoning: message.reasoningContent,
                        hasToolCalls: hasToolCalls,
                        isStreaming: message.isStreaming,
                        isLastAssistantInTurn: lastInTurn,
                        searchHits: PromethTranscript.searchHits(from: searchBodies(around: message.id, in: messages))
                    ) {
                        item.text = text
                    } else {
                        let decision = PromethVisibleReply.row(
                            content: message.content,
                            streaming: message.isStreaming,
                            hasToolCalls: hasToolCalls,
                            laterAnswer: !lastInTurn
                        )
                        if decision.omit { return nil }
                        item.text = decision.text
                        if item.status == "complete" { item.status = decision.status }
                    }
                    item.sourceLinks = SourcesExtractor.links(
                        before: message.id,
                        in: messages,
                        assistantText: item.text
                    ) ?? PromethWebPrefetch.storedLinks(before: message.id, in: messages)
                }
                if message.toolName == PromethGenerateVideoTool.toolName {
                    item.artifact = PromethVideoResult.artifact(from: message.content, prompt: "")
                    if message.toolStatus == .running || message.toolStatus == .preparing {
                        item.text = "Making the clip…"
                        item.status = "preparing"
                    } else if item.artifact != nil {
                        item.text = ""
                    } else if message.content.contains("cancelled") || message.toolStatus == .cancelled {
                        item.text = "The clip was stopped."
                        item.status = "stopped"
                    } else {
                        item.text = "The clip didn't come through. Please try again."
                        item.status = "failed"
                    }
                }
                if message.toolName == "generate_image" || message.toolName == "edit_image" {
                    if let artifact = Self.imageArtifact(message, in: messages) {
                        item.artifact = artifact
                        item.text = ""
                    } else if message.toolStatus == .running || message.toolStatus == .preparing {
                        item.text = "Making the image…"
                        item.status = "preparing"
                    } else if message.toolStatus == .failed {
                        item.text = "The image didn't come through. Please try again."
                        item.status = "failed"
                    } else {
                        return nil
                    }
                }
                return item
            } + (localMedia[session.id] ?? []),
            draft: drafts[key] ?? "",
            attachments: composerAttachments[key] ?? [],
            updated: session.updatedAt
        )
    }

    private func isLastAssistantInTurn(_ messageID: UUID, in messages: [ChatTranscriptMessage]) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return true }
        guard index + 1 < messages.count else { return true }
        for later in messages[(index + 1)...] {
            if later.role == .user { break }
            if later.role == .assistant { return false }
        }
        return true
    }

    private func searchBodies(around messageID: UUID, in messages: [ChatTranscriptMessage]) -> [String] {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return [] }
        var start = index
        while start > 0 && messages[start - 1].role != .user {
            start -= 1
        }
        var end = index
        while end + 1 < messages.count && messages[end + 1].role != .user {
            end += 1
        }
        return messages[start...end].compactMap { message in
            guard message.role == .tool, message.toolName == "web_search" else { return nil }
            return message.content
        }
    }

    /// Size match against the pinned catalog. A full hash of the GGUF would stall launch.
    private static func evilWeightsInstalled(support: URL) -> Bool {
        guard let evil = try? ModelCatalogLoader.bundled().model(id: "evil"), !evil.files.isEmpty else {
            return false
        }
        let folder = CatalogPaths.folder(root: CatalogPaths.modelsRoot(support: support), model: evil)
        for file in evil.files {
            guard CatalogHash.byteCount(folder.appendingPathComponent(file.path)) == file.size else {
                return false
            }
        }
        return true
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
        if message.role == .error { return "failed" }
        return "complete"
    }

    private func publishModes() {
        for (key, mode) in modes {
            if let id = UUID(uuidString: key) {
                PromethModeTable.set(id, mode.rawValue)
            }
        }
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
