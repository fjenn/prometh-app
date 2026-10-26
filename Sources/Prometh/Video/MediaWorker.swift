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
        child.environment = environment
        let input = Pipe()
        let output = Pipe()
        child.standardInput = input
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        try child.run()
        let body = try JSONSerialization.data(withJSONObject: request)
        input.fileHandleForWriting.write(body)
        input.fileHandleForWriting.write(Data("\n".utf8))
        try input.fileHandleForWriting.close()
        let data = await Task.detached { output.fileHandleForReading.readDataToEndOfFile() }.value
        child.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\n").last.map(String.init) ?? #"{"ok":false,"error":"Video is not ready yet."}"#
    }
}
