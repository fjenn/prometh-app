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
        let python = ProcessInfo.processInfo.environment["PROMETH_POCKET_PYTHON"]
            ?? PromethRuntimeLocator.url(relative: "voice/.venv/bin/python3")?.path
            ?? "/usr/bin/python3"
        let child = Process()
        child.executableURL = URL(fileURLWithPath: python)
        child.arguments = [script.path, output.path]
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONNOUSERSITE"] = "1"
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
