import Foundation

enum PromethMediaRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var lastVideoURL: URL?

    static func remember(_ url: URL) {
        lock.lock()
        lastVideoURL = url
        lock.unlock()
    }

    static func latestVideo() -> URL? {
        lock.lock()
        let remembered = lastVideoURL
        lock.unlock()
        if let remembered, FileManager.default.fileExists(atPath: remembered.path) {
            return remembered
        }
        let directory = PromethIdentity.applicationSupportDirectory
            .appendingPathComponent("Media", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let videos = files.filter { $0.pathExtension.lowercased() == "mp4" }
        // Prefer original generates over `clip-*` trims so chat trim uses the full source.
        let originals = videos.filter { !$0.lastPathComponent.lowercased().hasPrefix("clip-") }
        let pool = originals.isEmpty ? videos : originals
        return pool.max { a, b in
            let left = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }
    }
}

enum PromethMediaWorker {
    static func generate(argumentsJSON: String, onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        guard let script = PromethRuntimeLocator.url(relative: "media/media_worker.py") else {
            return #"{"ok":false,"error":"Video is not ready yet."}"#
        }
        let prompt = prompt(from: argumentsJSON)
        if PromethBlocklist.isBlocked(prompt) {
            return #"{"ok":false,"error":"\#(PromethBlocklist.message)"}"#
        }
        await PromethMediaGate.unloadChatEngines(reason: "video")
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
        let response = try await run(script: script, request: request, onProgress: onProgress)
        if let artifact = PromethVideoResult.artifact(from: response, prompt: prompt) {
            PromethMediaRegistry.remember(
                directory.appendingPathComponent(artifact.filename)
            )
        }
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
        PromethMediaRegistry.remember(dest)
        let sourcePoster = source.deletingPathExtension().appendingPathExtension("png")
        let destPoster = dest.deletingPathExtension().appendingPathExtension("png")
        if FileManager.default.fileExists(atPath: sourcePoster.path),
           !FileManager.default.fileExists(atPath: destPoster.path) {
            try? FileManager.default.copyItem(at: sourcePoster, to: destPoster)
        }
    }

    /// Chat `trim_video` entry point. Trims the latest clip and returns a generate-shaped plan.
    static func trimLatest(argumentsJSON: String) async throws -> String {
        guard let source = PromethMediaRegistry.latestVideo() else {
            return #"{"ok":false,"error":"No clip is available to trim. Generate a video first, or use Preview → Edit video."}"#
        }
        guard let start = number("start", in: argumentsJSON),
              let end = number("end", in: argumentsJSON),
              let duration = PromethVideoPlan.trimDuration(start: start, end: end)
        else {
            return #"{"ok":false,"error":"Provide start and end seconds with end after start."}"#
        }
        let directory = PromethIdentity.applicationSupportDirectory
            .appendingPathComponent("Media", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dest = directory.appendingPathComponent("clip-\(UUID().uuidString).mp4")
        do {
            try await trim(source: source, dest: dest, start: start, end: end)
        } catch {
            return #"{"ok":false,"error":"Trim failed. Try Preview → Edit video."}"#
        }
        let keepOriginal = bool("keep_original", in: argumentsJSON) ?? true
        let plan: [String: Any] = [
            "output": dest.path,
            "poster": dest.deletingPathExtension().appendingPathExtension("png").path,
            "seconds": duration,
            "width": PromethVideoPlan.width,
            "height": PromethVideoPlan.height,
            "version": 2,
            "trim_start": start,
            "trim_end": end,
            "keep_original": keepOriginal,
            "source": source.lastPathComponent,
        ]
        let payload: [String: Any] = [
            "ok": true,
            "event": "done",
            "plan": plan,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return #"{"ok":false,"error":"Trim failed."}"#
        }
        return text
    }

    private static func prompt(from argumentsJSON: String) -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let prompt = json["prompt"] as? String
        else { return "" }
        return prompt
    }

    private static func number(_ key: String, in argumentsJSON: String) -> Double? {
        guard let data = argumentsJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let value = json[key] as? Double { return value }
        if let value = json[key] as? Int { return Double(value) }
        if let value = json[key] as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func bool(_ key: String, in argumentsJSON: String) -> Bool? {
        guard let data = argumentsJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json[key] as? Bool
    }

    private static func run(script: URL, request: [String: Any], onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        let python = ProcessInfo.processInfo.environment["PROMETH_READER_PYTHON"] ?? "/usr/bin/python3"
        let child = Process()
        child.executableURL = URL(fileURLWithPath: python)
        child.arguments = [script.path]
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONNOUSERSITE"] = "1"
        environment["PYTHONUNBUFFERED"] = "1"
        let videoID = PromethSelectedModels.id(.video, fallback: "video")
        environment["PROMETH_VIDEO_MODEL_ID"] = videoID
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
            await Task.detached {
                var result = Data(), pending = Data()
                var progress = PromethVideoProgress()
                while true {
                    let chunk = output.fileHandleForReading.availableData
                    if chunk.isEmpty { break }
                    result.append(chunk); pending.append(chunk)
                    while let newline = pending.firstIndex(of: 10) {
                        let line = pending[..<newline]
                        if let fraction = progress.consume(String(decoding: line, as: UTF8.self)) { onProgress?(fraction) }
                        pending.removeSubrange(...newline)
                    }
                }
                if !pending.isEmpty, let fraction = progress.consume(String(decoding: pending, as: UTF8.self)) { onProgress?(fraction) }
                return result
            }.value
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
