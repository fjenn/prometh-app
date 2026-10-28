import Foundation

enum PromethPocketSpeechError: Error {
    case unavailable
    case failed
}

/// Pocket TTS does not ship an mlx-audio `config.json`. Speech goes through the
/// Kyutai loader in `voice/pocket_speak.py` and the weights already on disk.
enum PromethPocketSpeech {
    static func synthesize(_ text: String) async throws -> URL {
        guard let script = PromethRuntimeLocator.url(relative: "voice/pocket_speak.py") else {
            throw PromethPocketSpeechError.unavailable
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("prometh-speech", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent(UUID().uuidString + ".wav")
        guard let python = PromethPython.interpreter(override: "PROMETH_POCKET_PYTHON"),
              PromethRuntimeLocator.url(relative: "voice/site-packages/pocket_tts") != nil
                || ProcessInfo.processInfo.environment["PROMETH_POCKET_PYTHON"] != nil else {
            throw PromethPocketSpeechError.unavailable
        }
        let child = Process()
        child.executableURL = python
        child.arguments = [script.path, output.path]
        var environment = PromethPython.environment(runtime: "voice")
        environment["PYTHONNOUSERSITE"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["HF_HUB_OFFLINE"] = "1"
        child.environment = environment
        let input = Pipe()
        child.standardInput = input
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        if let data = text.data(using: .utf8) {
            input.fileHandleForWriting.write(data)
        }
        try input.fileHandleForWriting.close()
        let code: Int32 = await Task.detached {
            child.waitUntilExit()
            return child.terminationStatus
        }.value
        guard code == 0, FileManager.default.fileExists(atPath: output.path),
              (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0 > 44
        else { throw PromethPocketSpeechError.failed }
        return output
    }
}

/// One resident Kokoro process. Its serial queue owns the pipe protocol, including warm-up.
enum PromethKokoroSpeech {
    private static let worker = PromethKokoroWorker()
    static func synthesize(_ text: String, voice: String = "af_heart") async throws -> URL {
        try await worker.synthesize(text, voice: voice)
    }
    static func warm() async throws {
        let url = try await synthesize("Ready.")
        try? FileManager.default.removeItem(at: url)
    }
}

private final class PromethKokoroWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "studio.prometh.kokoro")
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?

    func synthesize(_ text: String, voice: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do { continuation.resume(returning: try render(text, voice: voice)) }
                catch { reset(); continuation.resume(throwing: error) }
            }
        }
    }
    private func line() throws -> [String: Any] {
        var data = Data()
        while let byte = try output?.read(upToCount: 1), !byte.isEmpty {
            if byte.first == 10 {
                guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { break }
                return value
            }
            data.append(byte)
            if data.count > 4096 { break }
        }
        throw PromethPocketSpeechError.failed
    }
    private func start() throws {
        if process?.isRunning == true { return }
        reset()
        guard let script = PromethRuntimeLocator.url(relative: "voice/kokoro_speak.py"),
              let python = PromethVoiceRuntime.python else { throw PromethPocketSpeechError.unavailable }
        let model = try PromethVoiceRuntime.folder("kokoro")
        let child = Process(), stdin = Pipe(), stdout = Pipe()
        child.executableURL = python
        child.arguments = [script.path, model.path, "--serve"]
        var environment = PromethPython.environment()
        environment["HF_HUB_OFFLINE"] = "1"
        environment["PYTHONNOUSERSITE"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        child.environment = environment
        child.standardInput = stdin; child.standardOutput = stdout
        child.standardError = FileHandle.nullDevice
        try child.run()
        process = child; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        guard try line()["ready"] as? Bool == true else { throw PromethPocketSpeechError.failed }
    }
    private func render(_ text: String, voice: String) throws -> URL {
        try start()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kokoro-\(UUID().uuidString).wav")
        do {
            var data = try JSONSerialization.data(withJSONObject: ["text": text, "voice": voice, "output": url.path])
            data.append(10)
            try input?.write(contentsOf: data)
            guard try line()["ok"] as? Bool == true,
                  (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 > 44 else { throw PromethPocketSpeechError.failed }
            return url
        } catch { try? FileManager.default.removeItem(at: url); throw error }
    }
    private func reset() {
        try? input?.close(); try? output?.close()
        if process?.isRunning == true { process?.terminate() }
        input = nil; output = nil; process = nil
    }
}
