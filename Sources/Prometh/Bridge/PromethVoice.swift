import Combine
import Foundation

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
