import AppKit
import Foundation

struct PromethWebTurnResult: Sendable { let text: String; let stopped: Bool; let tps: Double? }

@MainActor
extension PromethWebCoordinator {
    func bridgeError(_ message: String) -> NSError { NSError(domain: "PromethBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    func nativeID(_ webID: String) -> UUID? {
        if let mapped = nativeChats[webID], let id = UUID(uuidString: mapped) { return id }
        if let id = UUID(uuidString: webID), store.chats.contains(where: { $0.id == id }) { return id }
        return nil
    }
    func runTurn(_ params: [String: Any]) async throws -> Any {
        guard let webID = params["chatId"] as? String, let text = params["text"] as? String, !text.isEmpty else { throw bridgeError("Write a message first.") }
        // Reuse the native conversation across turns and relaunches.
        if let id = nativeID(webID) { store.select(id) }
        else {
            store.newChat()
            guard let id = store.state.selectedChatID else { throw bridgeError("Couldn’t open a chat.") }
            nativeChats[webID] = id.uuidString
            UserDefaults.standard.set(nativeChats, forKey: "prometh.web.chatMap")
        }
        guard let id = store.state.selectedChatID else { throw bridgeError("Couldn’t open a chat.") }
        store.setMode(params["mode"] as? String == "evil" ? .evil : .safe)
        if let attachments = params["attachments"] as? [[String: Any]], !attachments.isEmpty {
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("prometh-web-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let files = try attachments.compactMap { item -> URL? in
                guard let key = item["blobKey"] as? String else { return nil }
                let source = try PromethWebFiles.file(PromethWebFiles.blobs, key)
                let ext = URL(fileURLWithPath: item["filename"] as? String ?? "image.png").pathExtension
                let name = UUID().uuidString + "." + (ext.isEmpty ? "png" : ext)
                let target = try PromethWebFiles.file(temporary, name)
                try FileManager.default.copyItem(at: source, to: target)
                return target
            }
            if !files.isEmpty, !store.attachWebFiles(files) { throw bridgeError("An attached image couldn’t be read.") }
        }
        let previous = Set(store.current?.messages.map(\.id) ?? [])
        let targetUserIndex = params["userIndex"] as? Int ?? Int.max
        let existingUsers = store.current?.messages.filter { $0.role == "user" } ?? []
        if targetUserIndex < existingUsers.count {
            guard store.editMessage(existingUsers[targetUserIndex], text: text) else { throw bridgeError(store.error ?? "Couldn’t resend the message.") }
        } else { store.send(text) }
        let task = Task<PromethWebTurnResult, Error> { @MainActor [self] in
            let deadline = Date().addingTimeInterval(600)
            var lastPayload = "", sawReply = false
            while Date() < deadline {
                try Task.checkCancellation()
                guard let conversation = store.chats.first(where: { $0.id == id }) else { throw bridgeError("The chat was closed.") }
                let additions = conversation.messages.filter { !previous.contains($0.id) }
                let assistants = additions.filter { $0.role == "assistant" && $0.connectorCard == nil && $0.artifact == nil }
                // An edited turn may reuse its assistant id; take messages after the revised user.
                let turn: [Message]
                if targetUserIndex < existingUsers.count, let userPosition = conversation.messages.firstIndex(where: { $0.id == existingUsers[targetUserIndex].id }) {
                    turn = Array(conversation.messages.dropFirst(userPosition + 1))
                } else { turn = additions }
                let textMessages = targetUserIndex < existingUsers.count ? turn.filter { $0.role == "assistant" && $0.connectorCard == nil && $0.artifact == nil } : assistants
                let answer = textMessages.map(\.text).joined(separator: "\n\n")
                sawReply = sawReply || !textMessages.isEmpty || turn.contains(where: { $0.artifact != nil })
                let payload: [String: Any] = ["chatId": webID, "text": answer, "extras": mappedExtras(turn), "title": conversation.title, "running": store.isRunning(id)]
                let json = try PromethWebMapping.jsonArguments([payload])
                if json != lastPayload { emit("chat.delta", payload); lastPayload = json }
                let waitingConnector = turn.contains { ["awaitingConsent", "running"].contains($0.connectorCard?.phase ?? "") }
                if !store.isRunning(id), sawReply, !waitingConnector {
                    if let failed = textMessages.last, failed.status == "failed" { throw bridgeError(failed.text) }
                    emit("chat.done", payload)
                    return PromethWebTurnResult(text: answer, stopped: textMessages.last?.status == "stopped", tps: store.webDecodeTokensPerSecond())
                }
                if !store.isRunning(id), !store.model.isModelLoading, !waitingConnector, let error = store.error { throw bridgeError(error) }
                try await Task.sleep(for: .milliseconds(60))
            }
            throw bridgeError("The local engine took too long to reply.")
        }
        let token = UUID()
        turnTokens[webID] = token
        turnTasks[webID] = task
        defer { if turnTokens[webID] == token { turnTasks[webID] = nil; turnTokens[webID] = nil } }
        do { let result = try await task.value; return ["text": result.text, "stopped": result.stopped, "tps": result.tps as Any? ?? NSNull()] }
        catch is CancellationError { return ["text": "", "stopped": true] }
        catch { emit("chat.error", ["chatId": webID, "error": error.localizedDescription]); throw error }
    }
    func pluginSnapshot() -> [String: Any] {
        ["items": (plugins.catalog?.items ?? []).map { item in
            ["slug": item.slug, "name": item.name, "description": item.description, "logo": item.logo?.absoluteString ?? "", "categories": item.categories, "status": plugins.statuses[item.slug] ?? "disconnected"] as [String: Any]
        }, "error": plugins.error ?? ""]
    }
}

@MainActor
extension PromethWebCoordinator {
    /// Native image tools store nested MediaAssets. Expose a scoped copy to the web's original ArtifactCard.
    func mappedExtras(_ messages: [Message]) -> [[String: Any]] {
        var extras = PromethWebMapping.extras(messages)
        for index in extras.indices {
            guard let raw = extras[index]["id"] as? String, let message = messages.first(where: { $0.id.uuidString == raw }), let artifact = message.artifact else { continue }
            let source = store.artifactURL(artifact)
            var value = extras[index]["artifact"] as? [String: Any] ?? [:]
            if artifact.kind == "image" {
                let key = "native-" + artifact.id.uuidString + "." + (source.pathExtension.isEmpty ? "png" : source.pathExtension)
                do {
                    try FileManager.default.createDirectory(at: PromethWebFiles.blobs, withIntermediateDirectories: true)
                    let destination = try PromethWebFiles.file(PromethWebFiles.blobs, key)
                    if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.copyItem(at: source, to: destination) }
                    if let image = NSBitmapImageRep(data: try Data(contentsOf: destination)) {
                        value["id"] = artifact.id.uuidString; value["blobKey"] = key; value["width"] = image.pixelsWide; value["height"] = image.pixelsHigh
                    }
                } catch { value["error"] = "The image file couldn’t be opened." }
            } else {
                do {
                    try FileManager.default.createDirectory(at: PromethWebFiles.media, withIntermediateDirectories: true)
                    let destination = try PromethWebFiles.file(PromethWebFiles.media, source.lastPathComponent)
                    if source.path != destination.path, !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.copyItem(at: source, to: destination) }
                    value["filename"] = source.lastPathComponent
                } catch { value["error"] = "The video file couldn’t be opened." }
            }
            extras[index]["artifact"] = value
        }
        return extras
    }
}
