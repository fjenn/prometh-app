import AppKit
import AVFoundation
import Foundation
import NativServerKit
import UniformTypeIdentifiers

@MainActor
extension PromethWebCoordinator {
    func handleMedia(_ method: String, _ params: [String: Any]) async throws -> Any {
        switch method {
        case "blob.put":
            guard let key = params["key"] as? String, let encoded = params["data"] as? String, let data = Data(base64Encoded: encoded) else { throw bridgeError("The image could not be saved.") }
            try FileManager.default.createDirectory(at: PromethWebFiles.blobs, withIntermediateDirectories: true)
            try data.write(to: PromethWebFiles.file(PromethWebFiles.blobs, key), options: .atomic)
            return NSNull()
        case "blob.delete":
            if let key = params["key"] as? String { try? FileManager.default.removeItem(at: PromethWebFiles.file(PromethWebFiles.blobs, key)) }; return NSNull()
        case "blob.clear":
            if FileManager.default.fileExists(atPath: PromethWebFiles.blobs.path) { try FileManager.default.removeItem(at: PromethWebFiles.blobs) }; return NSNull()
        case "blob.save", "media.save":
            let root = method == "blob.save" ? PromethWebFiles.blobs : PromethWebFiles.media
            let key = params["key"] as? String ?? params["filename"] as? String ?? ""
            let source = try PromethWebFiles.file(root, key)
            let panel = NSSavePanel(); panel.nameFieldStringValue = params["filename"] as? String ?? key
            if panel.runModal() == .OK, let destination = panel.url { try Data(contentsOf: source).write(to: destination, options: .atomic) }
            return NSNull()
        case "audio.start":
            PromethVoiceLatency.note("audio_start")
            let auth = AVCaptureDevice.authorizationStatus(for: .audio)
            PromethVoiceLatency.note("audio_auth_\(auth.rawValue)")
            if auth == .notDetermined {
                guard await AVCaptureDevice.requestAccess(for: .audio) else { throw bridgeError("Allow Prometh to use your microphone in System Settings.") }
            } else if auth != .authorized { throw bridgeError("Allow Prometh to use your microphone in System Settings.") }
            microphone.discard()
            PromethVoiceLatency.note("audio_discarded")
            microphoneToken = params["token"] as? String ?? UUID().uuidString
            let token = microphoneToken
            try webSilero.start(onFrame: { [weak self] probability, rms, elapsed in
                guard let self, self.microphoneToken == token else { return }
                self.emit("audio.frame", ["token": token, "probability": probability, "rms": rms, "elapsed": elapsed])
            }, onFailure: { [weak self] error in self?.emit("audio.error", ["token": token, "error": error]) })
            PromethVoiceLatency.note("audio_vad_started")
            microphone.onAudioBuffer = { [webSilero] buffer in webSilero.append(buffer) }
            microphone.onMeterUpdate = { [weak self] level, _ in
                guard let self, self.microphoneToken == token else { return }
                self.emit("audio.meter", ["token": token, "level": level])
            }
            microphone.onRecordingFailure = { [weak self] error, _ in self?.emit("audio.error", ["token": token, "error": error.localizedDescription]) }
            _ = try await microphone.start()
            PromethVoiceLatency.note("audio_started")
            return NSNull()
        case "audio.stop":
            guard params["token"] as? String == microphoneToken else { return "" }
            webSilero.stop()
            guard let url = microphone.stop() else { throw bridgeError("The microphone returned no recording.") }
            defer { VoiceAudioRetention.removeAudioFile(at: url) }
            if let error = microphone.lastRecordingError { throw error }
            return try Data(contentsOf: url).base64EncodedString()
        case "audio.cancel":
            if params["token"] as? String == microphoneToken { microphone.discard(); webSilero.stop(); microphoneToken = "" }; return NSNull()
        case "audio.transcribe":
            guard let encoded = params["data"] as? String, let data = Data(base64Encoded: encoded) else { throw bridgeError("No recording was captured.") }
            let settings = store.model.settings.normalized()
            let client = NativAudioClient(baseURL: settings.serverBaseURL, apiKey: settings.serverAPIKey, timeout: 120)
            let text = try await client.transcribe(audioData: data, fileName: "voice.wav", model: PromethVoiceDefaults.speechModel(current: settings.speechToTextModelID)).text
            PromethVoiceLatency.mark(params["turnId"] as? String, "whisper_final", chars: text.count)
            return text
        case "audio.warm":
            let sessionID = (params["chatId"] as? String).flatMap { nativeID($0) }
            let mode = params["mode"] as? String ?? "safe"
            // Warm-up is best effort: a failed or slow stage is logged and never blocks listening.
            let started = ProcessInfo.processInfo.systemUptime
            PromethVoiceLatency.note("warm_begin")
            async let speech: Bool = (try? await PromethKokoroSpeech.warm()) != nil
            async let prefix: Void = store.warmWebVoice(sessionID: sessionID, mode: mode)
            let spoke = await speech
            PromethVoiceLatency.note(spoke ? "warm_kokoro_ok" : "warm_kokoro_failed", since: started)
            await prefix
            PromethVoiceLatency.note("warm_prefix_done", since: started)
            return NSNull()
        case "audio.speech":
            guard let text = params["text"] as? String, !text.isEmpty else { return "" }
            let url = try await PromethKokoroSpeech.synthesize(text, voice: params["voice"] as? String ?? "af_heart")
            defer { try? FileManager.default.removeItem(at: url) }
            return try Data(contentsOf: url).base64EncodedString()
        case "media.image":
            guard let prompt = params["prompt"] as? String, !prompt.isEmpty else { throw bridgeError("Describe your image first.") }
            if PromethBlocklist.isBlocked(prompt) { throw bridgeError(PromethBlocklist.message) }
            let settings = store.model.settings.normalized()
            // Use the selected native FLUX model and native server credentials.
            var request = URLRequest(url: settings.serverBaseURL.appendingPathComponent("v1/images/generations"))
            request.httpMethod = "POST"; request.timeoutInterval = 600
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let apiKey = settings.serverAPIKey, !apiKey.isEmpty { request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization") }
            request.httpBody = try JSONSerialization.data(withJSONObject: ["model": store.selectedModel(.images)?.repo ?? PromethImageDefaults.modelID, "prompt": prompt, "n": 1, "response_format": "b64_json"])
            let job = params["jobId"] as? String ?? UUID().uuidString
            let task = Task<Data, Error> { @MainActor [self] in
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else { throw bridgeError("The image engine couldn’t finish the image.") }
                return data
            }
            imageTasks[job] = task
            defer { imageTasks[job] = nil }
            let data = try await task.value
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw bridgeError("The image engine returned an unreadable result.") }
            return json
        case "media.video":
            guard let prompt = params["prompt"] as? String, let job = params["jobId"] as? String else { throw bridgeError("Describe your video first.") }
            let body = String(decoding: try JSONSerialization.data(withJSONObject: ["prompt": prompt]), as: UTF8.self)
            let task = Task { try await PromethMediaWorker.generate(argumentsJSON: body, onProgress: { [weak self] progress in Task { @MainActor in self?.emit("media.progress", ["jobId": job, "progress": progress]) } }) }
            mediaTasks[job] = task
            defer { mediaTasks[job] = nil }
            let result = try await task.value
            guard let artifact = PromethVideoResult.artifact(from: result, prompt: prompt) else {
                let payload = (try? JSONSerialization.jsonObject(with: Data(result.utf8))) as? [String: Any]
                throw bridgeError(payload?["error"] as? String ?? "The video couldn’t finish.")
            }
            return ["filename": artifact.filename, "prompt": prompt, "duration": artifact.duration ?? 0, "version": artifact.version, "kind": "video"]
        case "media.cancel":
            if let job = params["jobId"] as? String { mediaTasks[job]?.cancel(); imageTasks[job]?.cancel() }; return NSNull()
        case "media.trim":
            guard let name = params["filename"] as? String, let start = params["start"] as? Double, let end = params["end"] as? Double, PromethVideoPlan.trimDuration(start: start, end: end) != nil else { throw bridgeError("Choose an end after the start.") }
            let source = try PromethWebFiles.file(PromethWebFiles.media, name)
            let output = PromethWebFiles.media.appendingPathComponent("clip-\(UUID().uuidString).mp4")
            try await PromethMediaWorker.trim(source: source, dest: output, start: start, end: end)
            return ["filename": output.lastPathComponent, "duration": end - start]
        default: throw bridgeError("Unknown media operation.")
        }
    }
}
