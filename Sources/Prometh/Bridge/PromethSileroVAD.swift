import AVFoundation
import Foundation

/// The bundled interpreter and pinned models are used by both voice workers.
enum PromethVoiceRuntime {
    static var python: URL? {
        PromethPython.bundled
    }

    static func folder(_ id: String) throws -> URL {
        guard let model = try ModelCatalogLoader.bundled().model(id: id) else {
            throw PromethPocketSpeechError.unavailable
        }
        return CatalogPaths.folder(root: CatalogPaths.modelsRoot(support: PromethIdentity.applicationSupportDirectory), model: model)
    }
}

/// Converts the real capture buffers to 16 kHz mono, then scores them with
/// Silero v5 on a separate process. Pipe writes never block the capture thread.
final class PromethSileroVAD: @unchecked Sendable {
    private let lock = NSLock()
    private let writes = DispatchQueue(label: "studio.prometh.vad.input")
    private var converter: AVAudioConverter?
    private var pending = Data()
    private var output = Data()
    private var child: Process?
    private var input: FileHandle?
    private var generation = UUID()
    private var queuedBytes = 0
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    @MainActor
    func start(onFrame: @escaping @MainActor @Sendable (Float, Float, TimeInterval) -> Void,
               onFailure: @escaping @MainActor @Sendable (String) -> Void) throws {
        stop()
        guard let python = PromethVoiceRuntime.python,
              let script = PromethRuntimeLocator.url(relative: "voice/silero_stream.py") else {
            throw PromethPocketSpeechError.unavailable
        }
        let model = try PromethVoiceRuntime.folder("vad").appendingPathComponent("onnx/model.onnx")
        guard FileManager.default.fileExists(atPath: model.path) else { throw PromethPocketSpeechError.unavailable }
        let process = Process()
        let stdin = Pipe(), stdout = Pipe()
        process.executableURL = python
        process.arguments = [script.path, model.path]
        var environment = PromethPython.environment()
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        process.environment = environment
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        let token = lock.withLock { generation }
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { handle.readabilityHandler = nil; return }
            let frames: [[String: Double]] = self.lock.withLock {
                guard self.generation == token else { return [] }
                self.output.append(data)
                var frames: [[String: Double]] = []
                while let newline = self.output.firstIndex(of: 10) {
                    let line = self.output.prefix(upTo: newline)
                    self.output.removeSubrange(...newline)
                    if let frame = try? JSONDecoder().decode([String: Double].self, from: line) { frames.append(frame) }
                }
                return frames
            }
            for frame in frames {
                Task { @MainActor in
                    guard self.lock.withLock({ self.generation == token }) else { return }
                    onFrame(Float(frame["probability"] ?? 0), Float(frame["rms"] ?? 0), frame["elapsed"] ?? 0)
                }
            }
        }
        process.terminationHandler = { [weak self] process in
            guard let self, self.lock.withLock({ self.generation == token }) else { return }
            Task { @MainActor in onFailure("Speech detection stopped (code \(process.terminationStatus)). Try reopening Voice.") }
        }
        try process.run()
        lock.withLock { child = process; input = stdin.fileHandleForWriting }
    }

    func stop() {
        let previous = lock.withLock { () -> (Process?, FileHandle?) in
            generation = UUID()
            let value = (child, input)
            child = nil; input = nil; converter = nil
            pending = Data(); output = Data(); queuedBytes = 0
            return value
        }
        try? previous.1?.close()
        if previous.0?.isRunning == true { previous.0?.terminate() }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        let packet: (Data, FileHandle, UUID)? = lock.withLock {
            guard let input, queuedBytes < 16000 * 4 * 2 else { return nil }
            if converter?.inputFormat != buffer.format {
                converter = AVAudioConverter(from: buffer.format, to: target)
            }
            guard let converter,
                  let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * 16000 / buffer.format.sampleRate) + 512) else { return nil }
            var supplied = false
            var failure: NSError?
            converter.convert(to: converted, error: &failure) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return buffer
            }
            guard failure == nil, converted.frameLength > 0, let samples = converted.floatChannelData?[0] else { return nil }
            let data = Data(bytes: samples, count: Int(converted.frameLength) * 4)
            queuedBytes += data.count
            return (data, input, generation)
        }
        guard let (data, input, token) = packet else { return }
        writes.async { [weak self] in
            guard let self, self.lock.withLock({ self.generation == token }) else { return }
            try? input.write(contentsOf: data)
            self.lock.withLock { if self.generation == token { self.queuedBytes -= data.count } }
        }
    }

    deinit { stop() }
}
