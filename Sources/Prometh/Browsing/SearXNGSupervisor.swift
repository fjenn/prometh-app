import Foundation
import Security

enum PromethPython {
    /// Reader packages live in a provisioned venv, never in a committed vendor tree.
    static func reader() -> URL? {
        executable(
            override: "PROMETH_READER_PYTHON",
            relatives: [
                "reader/.venv/bin/python3",
                "searxng/dist/runtime/python/bin/python3",
            ]
        )
    }

    static func composio() -> URL? {
        executable(
            override: "PROMETH_COMPOSIO_PYTHON",
            relatives: ["composio_mcp/.venv/bin/python3"]
        )
    }

    static func searxng() -> URL? {
        executable(
            override: "PROMETH_SEARXNG_PYTHON",
            relatives: [
                "searxng/dist/runtime/python/bin/python3",
                "searxng/.venv/bin/python3",
            ]
        )
    }

    private static func executable(override: String, relatives: [String]) -> URL? {
        if let path = ProcessInfo.processInfo.environment[override],
           FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        for relative in relatives {
            if let url = PromethRuntimeLocator.url(relative: relative) {
                return url
            }
        }
        return nil
    }
}

enum PromethRuntimeLocator {
    static func url(relative: String) -> URL? {
        let manager = FileManager.default
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("PromethRuntime", isDirectory: true)
            .appendingPathComponent(relative),
            manager.fileExists(atPath: bundled.path) {
            return bundled
        }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PromethRuntime")
            .appendingPathComponent(relative)
        if manager.fileExists(atPath: repo.path) {
            return repo
        }
        return nil
    }
}

/// Unmodified SearXNG, separate process, 127.0.0.1 only.
final class SearXNGSupervisor: @unchecked Sendable {
    static let shared = SearXNGSupervisor()

    private let lock = NSLock()
    private var process: Process?
    private var port: Int?
    private var state = "Stopped"

    var statusText: String {
        lock.lock()
        defer { lock.unlock() }
        if let port {
            return "\(state) · 127.0.0.1:\(port)"
        }
        return state
    }

    func baseURL() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        guard let port else { return nil }
        return URL(string: "http://127.0.0.1:\(port)")
    }

    func start() async {
        if baseURL() != nil { return }
        setState("Starting")
        do {
            let python = try await interpreter()
            let settings = try writeSettings()
            let port = try Self.reservePort()
            let process = Process()
            process.executableURL = python
            var arguments = [
                "-m", "granian",
                "--interface", "wsgi",
                "--host", "127.0.0.1",
                "--port", String(port),
                "--workers", "1",
                "searx.webapp:application",
            ]
            if let launcher = PromethRuntimeLocator.url(relative: "searxng/launch.py") {
                arguments = [
                    launcher.path,
                    "--parent", String(ProcessInfo.processInfo.processIdentifier),
                    "--",
                ] + arguments
            }
            process.arguments = arguments
            process.environment = Self.childEnvironment(settings: settings)
            process.currentDirectoryURL = python
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            lock.lock()
            self.process = process
            self.port = port
            lock.unlock()
            let healthy = await Self.waitForHealth(port: port)
            setState(healthy ? "Listening" : "Started without healthz")
        } catch {
            setState("Failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        lock.lock()
        let process = self.process
        self.process = nil
        self.port = nil
        lock.unlock()
        process?.terminate()
        setState("Stopped")
    }

    private func setState(_ value: String) {
        lock.lock()
        state = value
        lock.unlock()
    }

    private func interpreter() async throws -> URL {
        if let existing = PromethPython.searxng() {
            return existing
        }
        guard let archive = PromethRuntimeLocator.url(
            relative: "searxng/dist/mermaid-searxng-macos-aarch64.tar.zst"
        ) else {
            throw SearXNGSupervisorError.missingRuntime
        }
        let destination = PromethIdentity.applicationSupportDirectory
            .appendingPathComponent("searxng/runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let python = destination.appendingPathComponent("python/bin/python3")
        if FileManager.default.fileExists(atPath: python.path) {
            return python
        }
        try Self.unpack(archive: archive, to: destination)
        guard FileManager.default.fileExists(atPath: python.path) else {
            throw SearXNGSupervisorError.missingRuntime
        }
        return python
    }

    private func writeSettings() throws -> URL {
        let directory = PromethIdentity.applicationSupportDirectory
            .appendingPathComponent("searxng", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("settings.yml")
        let secret = Self.existingSecret(at: url) ?? Self.randomSecret()
        let yaml = """
        use_default_settings: true
        server:
          secret_key: "\(secret)"
          limiter: false
          public_instance: false
          bind_address: "127.0.0.1"
          image_proxy: false
        search:
          formats:
            - html
            - json
          suspended_times:
            SearxEngineAccessDenied: 30
            SearxEngineCaptcha: 120
            SearxEngineTooManyRequests: 30
            cf_SearxEngineCaptcha: 300
            cf_SearxEngineAccessDenied: 300
        valkey:
          url: false
        engines:
          - name: google
            disabled: true
          - name: google news
            disabled: true
          - name: google images
            disabled: true
          - name: google videos
            disabled: true
          - name: google scholar
            disabled: true
          - name: google cse
            disabled: true
          - name: google cse images
            disabled: true
          - name: google play apps
            disabled: true
          - name: google play movies
            disabled: true
          - name: bing
            disabled: true
          - name: bing news
            disabled: true
          - name: bing images
            disabled: true
          - name: bing videos
            disabled: true
          - name: qwant
            disabled: true
          - name: qwant news
            disabled: true
          - name: qwant images
            disabled: true
          - name: qwant videos
            disabled: true
          - name: startpage
            disabled: true
          - name: startpage news
            disabled: true
          - name: startpage images
            disabled: true
          - name: duckduckgo
            disabled: false
          - name: duckduckgo web
            disabled: false
          - name: duckduckgo news
            disabled: false
          - name: brave
            disabled: false
          - name: brave.news
            disabled: false
          - name: wikipedia
            disabled: false
          - name: wikidata
            disabled: false
          - name: mojeek
            disabled: false
          - name: github
            disabled: false
          - name: arxiv
            disabled: false
        """
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func existingSecret(at url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        guard let line = text.split(separator: "\n").first(where: { $0.contains("secret_key:") }) else {
            return nil
        }
        let value = line.split(separator: "\"", maxSplits: 2, omittingEmptySubsequences: false)
        guard value.count >= 2 else { return nil }
        let secret = String(value[1])
        return secret.count >= 32 ? secret : nil
    }

    private static func randomSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func childEnvironment(settings: URL) -> [String: String] {
        var environment = [
            "PATH": "/usr/bin:/bin:/opt/homebrew/bin",
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "TMPDIR": NSTemporaryDirectory(),
            "LANG": "en_US.UTF-8",
            "SEARXNG_SETTINGS_PATH": settings.path,
        ]
        if ProcessInfo.processInfo.environment["PROMETH_OFFLINE"] == "1" {
            let proxy = "http://127.0.0.1:9"
            environment["HTTP_PROXY"] = proxy
            environment["HTTPS_PROXY"] = proxy
            environment["ALL_PROXY"] = proxy
            environment["NO_PROXY"] = "127.0.0.1,localhost,::1"
        }
        return environment
    }

    private static func reservePort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw SearXNGSupervisorError.noPort }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = "127.0.0.1".withCString { inet_addr($0) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { throw SearXNGSupervisorError.noPort }
        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &boundAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard named == 0 else { throw SearXNGSupervisorError.noPort }
        return Int(UInt16(bigEndian: boundAddress.sin_port))
    }

    private static func unpack(archive: URL, to destination: URL) throws {
        let zstd = ["/opt/homebrew/bin/zstd", "/usr/bin/zstd"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
        guard let zstd else { throw SearXNGSupervisorError.missingRuntime }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "\"\(zstd)\" -dc \"\(archive.path)\" | /usr/bin/tar -xf - -C \"\(destination.path)\""]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw SearXNGSupervisorError.missingRuntime }
    }

    private static func waitForHealth(port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/healthz") else { return false }
        for _ in 0 ..< 40 {
            var request = URLRequest(url: url, timeoutInterval: 2)
            request.httpMethod = "GET"
            if let (_, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return true
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return false
    }
}

enum SearXNGSupervisorError: Error {
    case missingRuntime
    case noPort
}
