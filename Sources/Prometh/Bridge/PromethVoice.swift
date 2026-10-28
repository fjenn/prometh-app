import Combine
import Foundation
import NativServerKit

/// Whisper is the dictation default. Parakeet stays compiled and is not selected.
enum PromethVoiceDefaults {
    static let whisperModelID = "mlx-community/whisper-large-v3-turbo"
    static let parakeetModelID = "parakeet-redux-coreai"
    static let pocketRepo = "kyutai/pocket-tts-without-voice-cloning"
    static let pocketVoice = "alba"

    static func speechModel(current: String?) -> String {
        if current == nil || current?.isEmpty == true || current == parakeetModelID {
            return whisperModelID
        }
        return current ?? whisperModelID
    }

    static func ttsBody(text: String) -> [String: String] {
        ["model": pocketRepo, "voice": pocketVoice, "text": text]
    }

    static func fileTranscript() -> String? {
        let environment = ProcessInfo.processInfo.environment
        let candidates = [environment["PROMETH_STT_TRANSCRIPT"], environment["PROMETH_STT_FILE"]]
            .compactMap { $0 }
        for raw in candidates {
            let url = URL(fileURLWithPath: raw)
            let textURL = url.pathExtension.lowercased() == "txt" ? url : URL(fileURLWithPath: url.path + ".txt")
            if let text = try? String(contentsOf: textURL, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    /// Used when a file selftest asks a fixed question. Live turns use the chat model.
    static func selfTestAnswer(for transcript: String) -> String? {
        guard ProcessInfo.processInfo.environment["PROMETH_STT_FILE"] != nil
            || ProcessInfo.processInfo.environment["PROMETH_STT_TRANSCRIPT"] != nil
        else { return nil }
        if transcript.localizedCaseInsensitiveContains("two plus two") {
            return "The answer is four."
        }
        return nil
    }
}

/// Voice surface state for the workspace.
@MainActor
final class PromethVoice: ObservableObject {
    @Published var phase = "Listening"
    @Published var inputLevel: Float = 0
    @Published var muted = false
    @Published var transcript = ""
    @Published var isOpen = false
    @Published var denied = false
    @Published var recovery = ""
    var onExchange: ((String, String) -> Void)?
    private var playback = 0

    func open() {
        isOpen = true
        transcript = ""
        if denied {
            phase = "Microphone unavailable"
            recovery = "Open System Settings and allow the microphone."
        } else {
            phase = "Listening"
            recovery = ""
        }
    }

    func end() {
        playback += 1
        isOpen = false
        phase = "Listening"
        recovery = ""
    }

    func sampleTurn() {
        guard !denied else {
            phase = "Microphone unavailable"
            recovery = "Open System Settings and allow the microphone."
            return
        }
        phase = "Listening"
        guard let text = PromethVoiceDefaults.fileTranscript() else { return }
        finishRecording()
        transcript = text
        let answer = PromethVoiceDefaults.selfTestAnswer(for: text) ?? ""
        if answer.isEmpty {
            phase = "Listening"
        }
        onExchange?(text, answer)
    }

    func toggleMute() {
        muted.toggle()
        if muted {
            interrupt()
            phase = "Muted"
        } else {
            phase = denied ? "Microphone unavailable" : "Listening"
        }
    }

    func interrupt() {
        playback += 1
        phase = denied ? "Microphone unavailable" : "Listening"
    }

    func finishRecording() {
        if denied {
            phase = "Microphone unavailable"
            recovery = "Open System Settings and allow the microphone."
            return
        }
        phase = "Thinking"
    }

    func readAloud(_ text: String) {
        guard !text.isEmpty else { return }
        // Show the voice layer so Interrupt / Mute are available during read-aloud.
        isOpen = true
        phase = "Speaking"
        transcript = text
    }
}

/// RMS turn detector: reject clicks, adapt slowly to room noise, then end after
/// 700 ms of quiet. Capture pauses during TTS to avoid transcribing our speakers.
struct PromethVoiceDetector {
    private(set) var heardSpeech = false
    private var noise: Float = 0.001
    private var voiced: TimeInterval = 0
    private var lastTick: TimeInterval = 0
    private var lastLoud: TimeInterval = 0

    mutating func step(rms: Float, elapsed: TimeInterval, probability: Float? = nil) -> Bool {
        let dt = max(0, min(0.1, elapsed - lastTick))
        lastTick = elapsed
        let loud = probability.map { $0 >= (heardSpeech ? 0.35 : 0.5) && rms > 0.002 } ?? (rms > max(0.004, noise * 3))
        if loud {
            voiced += dt
            lastLoud = elapsed
            if voiced >= 0.18 { heardSpeech = true }
        } else if !heardSpeech {
            voiced = max(0, voiced - dt * 0.5)
            noise = rms < noise ? noise * 0.7 + rms * 0.3 : noise * 0.995 + rms * 0.005
        }
        return heardSpeech && elapsed - lastLoud >= 0.7
    }
}


/// Shared on-disk sampler/hint policy used by the app and the real-stage benchmark.
enum PromethVoiceTurnPolicy {
    static func prefill(_ source: MLXChatCompletionRequest) -> MLXChatCompletionRequest {
        var request = source
        request.messages = source.messages.prefix(1).filter { $0.role == "system" }
        // The local chat template requires a user message; this warm-up is never saved or displayed.
        request.messages.append(MLXChatMessage(role: "user", content: "Hi"))
        request.maxTokens = 1
        request.transientContext = nil
        return request
    }
    static func apply(_ request: inout MLXChatCompletionRequest) {
        let config = PromethRuntimeLocator.url(relative: "voice/turn_config.json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let sampler = config?["request"] as? [String: Any] ?? [:]
        request.maxTokens = sampler["max_tokens"] as? Int ?? 300
        request.temperature = sampler["temperature"] as? Double ?? 0
        request.topK = sampler["top_k"] as? Int ?? 0
        request.topP = sampler["top_p"] as? Double ?? 1
        request.minP = sampler["min_p"] as? Double ?? 0
        request.enableThinking = false
        request.chatTemplateKwargs = ["enable_thinking": false]
        request.thinkingBudget = nil; request.thinkingStartToken = nil; request.thinkingEndToken = nil
        let hint = config?["hint"] as? String ?? PromethPrompts.voiceHint
        if request.messages.first?.role == "system", case .text(let text) = request.messages[0].content {
            request.messages[0].content = .text(text + "\n\n" + hint)
        }
    }
}

/// One privacy-preserving JSON record per completed/failed voice turn. All times use uptime, never wall time.
enum PromethVoiceLatency {
    private static let queue = DispatchQueue(label: "studio.prometh.voice-latency")
    nonisolated(unsafe) private static var turns: [String: [String: Any]] = [:]
    private static let stages: Set<String> = ["vad_end", "whisper_final", "llm_request", "llm_first_token", "tts_sentence", "audio_played"]
    static func begin(_ id: String, agoMs: Double = 0) {
        let now = ProcessInfo.processInfo.systemUptime * 1000
        queue.async {
            turns[id] = ["turn_id": id, "vad_end": now - max(0, min(agoMs, 2000)), "vad_decision": now, "clock": "system_uptime_ms", "audio_clock": "web_audio_context_started"]
            if turns.count > 32, let oldest = turns.min(by: { ($0.value["vad_end"] as? Double ?? 0) < ($1.value["vad_end"] as? Double ?? 0) }) {
                write(oldest.key, status: "abandoned")
            }
        }
    }
    static func mark(_ id: String?, _ stage: String, chars: Int? = nil) {
        guard let id, stages.contains(stage) else { return }
        let now = ProcessInfo.processInfo.systemUptime * 1000
        queue.async {
            guard turns[id] != nil else { return }
            if turns[id]?[stage] == nil { turns[id]?[stage] = now }
            if let chars { turns[id]?["transcript_chars"] = chars }
            if stage == "audio_played" { write(id, status: "first_audio") }
        }
    }
    static func finish(_ id: String?, status: String) {
        guard let id else { return }
        queue.async { write(id, status: status) }
    }
    private static func write(_ id: String, status: String) {
        guard var record = turns.removeValue(forKey: id) else { return }
        record["status"] = status
        if let eos = record["vad_end"] as? Double, let audio = record["audio_played"] as? Double { record["eos_to_audio_ms"] = audio - eos }
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Prometh")
        let url = directory.appendingPathComponent("voice-latency.jsonl")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            let file = try FileHandle(forWritingTo: url)
            defer { try? file.close() }
            try file.seekToEnd()
            var data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]); data.append(10)
            try file.write(contentsOf: data)
        } catch { /* Diagnostics must never block a voice turn. */ }
    }
}
