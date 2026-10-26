import Foundation

struct LlamaEndpoint: Equatable, Sendable {
    var host: String
    var port: Int
    var alias: String
    var apiKey: String

    var baseURL: URL {
        URL(string: "http://\(host):\(port)/v1")!
    }
}

/// Owns the llama.cpp supervisor. The binary and the GGUF stay out of git.
final class LlamaSupervisor: @unchecked Sendable {
    static let shared = LlamaSupervisor()

    private let lock = NSLock()
    private var process: Process?
    private var endpoint: LlamaEndpoint?

    func stop() {
        lock.lock()
        let running = process
        process = nil
        endpoint = nil
        lock.unlock()
        running?.terminate()
    }

    func ensureRunning() async throws -> LlamaEndpoint {
        lock.lock()
        if let endpoint, process?.isRunning == true {
            lock.unlock()
            return endpoint
        }
        lock.unlock()
        guard let script = PromethRuntimeLocator.url(relative: "llama/llama_supervisor.py") else {
            throw PromethInterruptedError.llamaUnavailable
        }
        guard let model = Self.modelPath() else {
            throw PromethInterruptedError.llamaUnavailable
        }
        let executable = ProcessInfo.processInfo.environment["PROMETH_LLAMA_BIN"]
            ?? PromethRuntimeLocator.url(relative: "llama/bin/llama-server")?.path
        guard let executable, FileManager.default.isExecutableFile(atPath: executable) else {
            throw PromethInterruptedError.llamaUnavailable
        }
        let support = PromethIdentity.applicationSupportDirectory
            .appendingPathComponent("llama", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let secret = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let python = ProcessInfo.processInfo.environment["PROMETH_READER_PYTHON"] ?? "/usr/bin/python3"
        let child = Process()
        child.executableURL = URL(fileURLWithPath: python)
        child.arguments = [
            script.path,
            "--parent", String(ProcessInfo.processInfo.processIdentifier),
            "--executable", executable,
            "--model", model,
            "--api-key", secret,
            "--support", support.path,
        ]
        let output = Pipe()
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        do {
            try child.run()
        } catch {
            throw PromethInterruptedError.llamaUnavailable
        }
        let listening = await Self.waitForListening(output.fileHandleForReading)
        guard listening else {
            child.terminate()
            throw PromethInterruptedError.llamaUnavailable
        }
        let endpointURL = support.appendingPathComponent("endpoint.json")
        guard let data = try? Data(contentsOf: endpointURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let host = json["host"] as? String,
              let port = json["port"] as? Int,
              let alias = json["alias"] as? String,
              let apiKey = json["apiKey"] as? String,
              host == "127.0.0.1"
        else {
            child.terminate()
            throw PromethInterruptedError.llamaUnavailable
        }
        let value = LlamaEndpoint(host: host, port: port, alias: alias, apiKey: apiKey)
        lock.lock()
        process = child
        endpoint = value
        lock.unlock()
        return value
    }

    private static func modelPath() -> String? {
        guard let catalog = try? ModelCatalogLoader.bundled(),
              let model = catalog.model(id: "evil"),
              let file = model.files.first
        else { return nil }
        let support = PromethIdentity.applicationSupportDirectory
        return CatalogPaths.folder(
            root: CatalogPaths.modelsRoot(support: support),
            model: model
        ).appendingPathComponent(file.path).path
    }

    private static func waitForListening(_ handle: FileHandle) async -> Bool {
        let deadline = Date().addingTimeInterval(8)
        var buffer = Data()
        while Date() < deadline {
            let chunk = handle.availableData
            if !chunk.isEmpty {
                buffer.append(chunk)
                if String(decoding: buffer, as: UTF8.self).contains("LISTENING ") {
                    return true
                }
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }
}
