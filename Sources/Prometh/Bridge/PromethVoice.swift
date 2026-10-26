import Combine
import Foundation

/// Voice surface state for the workspace. Recording and speech land in a later milestone.
@MainActor
final class PromethVoice: ObservableObject {
    @Published var phase = "Listening"
    @Published var muted = false
    @Published var transcript = ""
    @Published var isOpen = false
    @Published var denied = false
    var onExchange: ((String, String) -> Void)?

    func open() {
        isOpen = true
        transcript = ""
        phase = denied ? "Microphone unavailable" : "Voice is not available yet."
    }

    func end() {
        isOpen = false
        phase = "Listening"
    }

    func sampleTurn() {}

    func toggleMute() {
        muted.toggle()
        phase = muted ? "Muted" : (denied ? "Microphone unavailable" : "Voice is not available yet.")
    }

    func interrupt() {}

    func finishRecording() {}

    func readAloud(_ text: String) {}
}
