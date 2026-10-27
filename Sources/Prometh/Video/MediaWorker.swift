import Foundation

enum PromethMediaWorker {
    static func generate(argumentsJSON: String) async throws -> String {
        guard let script = PromethRuntimeLocator.url(relative: "media/media_worker.py") else {
            return #"{"ok":false,"error":"Video is not ready yet."}"#
        }
        let prompt = prompt(from: argumentsJSON)
        let directory = PromethIdentity.applicationSupportDirectory
            .appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stem = UUID().uuidString
        let output = directory.appendingPathComponent("\(stem).mp4")
        let poster = directory.appendingPathComponent("\(stem).png")
        let request: [String: Any] = [
            "op": "generate",
            "prompt": prompt,
            "output": output.path,
            "poster": poster.path,
        ]
        let response = try await run(script: script, request: request)
        return response
    }

    static func trim(source: URL, dest: URL, start: Double, end: Double) async throws {
        guard let script = PromethRuntimeLocator.url(relative: "media/media_worker.py") else {
            throw PromethInterruptedError.llamaUnavailable
        }
        let request: [String: Any] = [
            "op": "trim",
            "source": source.path,
            "output": dest.path,
            "start": start,
            "end": end,
        ]
        let response = try await run(script: script, request: request)
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["ok"] as? Bool) == true
        else {
            throw PromethInterruptedError.llamaUnavailable
        }
    }

    private static func prompt(from argumentsJSON: String) -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let prompt = json["prompt"] as? String
        else { return "" }
        return prompt
    }

    private static func run(script: URL, request: [String: Any]) async throws -> String {
        let python = ProcessInfo.processInfo.environment["PROMETH_READER_PYTHON"] ?? "/usr/bin/python3"
        let child = Process()
        child.executableURL = URL(fileURLWithPath: python)
        child.arguments = [script.path]
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONNOUSERSITE"] = "1"
        environment["PYTHONUNBUFFERED"] = "1"
        if let checkout = PromethRuntimeLocator.url(
            relative: "media/fastvideo/examples/inference/basic/mlx_wan_prompt_to_video.py"
        ) {
            environment["PROMETH_FASTVIDEO_SRC"] = checkout
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .path
        }
        if let python = PromethRuntimeLocator.url(relative: "media/.venv/bin/python3") {
            environment["PROMETH_MEDIA_PYTHON"] = python.path
        }
        child.environment = environment
        let input = Pipe()
        let output = Pipe()
        child.standardInput = input
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        try child.run()
        let body = try JSONSerialization.data(withJSONObject: request)
        let writer = input.fileHandleForWriting
        writer.write(body)
        writer.write(Data("\n".utf8))
        let job = MediaJob(process: child, writer: writer)
        let data = await withTaskCancellationHandler {
            await Task.detached { output.fileHandleForReading.readDataToEndOfFile() }.value
        } onCancel: {
            job.cancel()
        }
        if child.isRunning { child.waitUntilExit() }
        if Task.isCancelled {
            return #"{"ok":false,"cancelled":true}"#
        }
        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\n").last.map(String.init) ?? #"{"ok":false,"error":"Video is not ready yet."}"#
    }
}

private final class MediaJob: @unchecked Sendable {
    private let process: Process
    private let writer: FileHandle
    private let lock = NSLock()
    private var didCancel = false

    init(process: Process, writer: FileHandle) {
        self.process = process
        self.writer = writer
    }

    func cancel() {
        lock.lock()
        let already = didCancel
        didCancel = true
        lock.unlock()
        guard !already else { return }
        if let line = "{\"op\":\"cancel\"}\n".data(using: .utf8) {
            try? writer.write(contentsOf: line)
        }
        if process.isRunning {
            process.terminate()
        }
    }
}
