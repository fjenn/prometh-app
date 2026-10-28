import Foundation

/// Keyless page reader. Sidecar first, then an off-screen WKWebView when the page is a shell.
enum LocalPageReader {
    static func read(urls: [String], focus: String?) async throws -> [WebBrowsingProviderDocument] {
        await ReaderSupervisor.shared.start()
        return try await readDocumentsIndividually(provider: .local, urls: urls) { url in
            try await readOne(url)
        }
    }

    private static func readOne(_ urlString: String) async throws -> WebBrowsingProviderDocument {
        guard WebReadURLPolicy.normalizedURL(urlString) != nil else {
            return refused(urlString)
        }
        let sidecar = await ReaderSupervisor.shared.extract(url: urlString)
        if let final = sidecar?.url, WebReadURLPolicy.normalizedURL(final) == nil {
            return refused(final)
        }
        let finalURL = sidecar?.url ?? urlString
        var text = sidecar?.text ?? ""
        var title = sidecar?.title
        var published = sidecar?.published
        var extractor = sidecar?.extractor ?? "none"
        var status = sidecar?.status ?? 0
        // WKWebView fallback is serialized and time-bounded inside the reader.
        if text.count < 500 || looksLikeShell(text), let url = URL(string: finalURL) {
            if let page = try? await ReadabilityWebViewReader.shared.read(url: url),
               page.text.count > text.count {
                text = page.text
                title = page.title ?? title
                if let date = page.published, !date.isEmpty { published = date }
                extractor = "wkwebview"
                status = 200
            }
        }
        ReaderLog.append(status: status, extractor: extractor, published: published, chars: text.count, url: finalURL)
        guard !text.isEmpty else {
            return WebBrowsingProviderDocument(
                url: finalURL,
                title: title,
                content: nil,
                error: WebReadPageError(code: "empty_content", message: "The page had no readable text.")
            )
        }
        var body = text
        if let published, !published.isEmpty {
            body = "Published: \(published)\n\n" + body
        }
        return WebBrowsingProviderDocument(url: finalURL, title: title, content: body, error: nil)
    }

    private static func refused(_ url: String) -> WebBrowsingProviderDocument {
        WebBrowsingProviderDocument(
            url: url,
            title: nil,
            content: nil,
            error: WebReadPageError(code: "invalid_url", message: "That address cannot be read.")
        )
    }

    private static func looksLikeShell(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return ["enable javascript", "enable js", "checking your browser", "just a moment"]
            .contains { lowered.contains($0) }
    }
}

struct ReaderExtraction: Sendable {
    var status: Int
    var url: String
    var title: String?
    var published: String?
    var text: String
    var extractor: String
}

final class ReaderSupervisor: @unchecked Sendable {
    static let shared = ReaderSupervisor()

    private let lock = NSLock()
    private var process: Process?
    private var port: Int?

    func start() async {
        let running = lock.withLock { process?.isRunning == true && port != nil }
        if running { return }
        guard let python = PromethPython.reader(),
              let script = PromethRuntimeLocator.url(relative: "reader/reader_server.py") else {
            return
        }
        guard let port = try? SearXNGPort.reserve() else { return }
        let process = Process()
        process.executableURL = python
        process.arguments = [script.path, String(port), "--parent", String(ProcessInfo.processInfo.processIdentifier)]
        var environment = [
            "PATH": "/usr/bin:/bin",
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "LANG": "en_US.UTF-8",
            "PYTHONNOUSERSITE": "1",
            "PYTHONDONTWRITEBYTECODE": "1",
        ]
        if ProcessInfo.processInfo.environment["PROMETH_OFFLINE"] == "1" {
            environment["HTTP_PROXY"] = "http://127.0.0.1:9"
            environment["HTTPS_PROXY"] = "http://127.0.0.1:9"
            environment["ALL_PROXY"] = "http://127.0.0.1:9"
        }
        process.environment = PromethPython.environment(runtime: "reader", inheriting: environment)
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return
        }
        lock.withLock {
            self.process = process
            self.port = port
        }
        _ = await Self.wait(port: port)
    }

    func extract(url: String) async -> ReaderExtraction? {
        await start()
        let port = lock.withLock { self.port }
        guard let port, let endpoint = URL(string: "http://127.0.0.1:\(port)/extract") else { return nil }
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["url": url])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["ok"] as? Bool == true else {
            return nil
        }
        return ReaderExtraction(
            status: object["status"] as? Int ?? 0,
            url: object["url"] as? String ?? url,
            title: object["title"] as? String,
            published: object["published"] as? String,
            text: object["text"] as? String ?? "",
            extractor: object["extractor"] as? String ?? "plain"
        )
    }

    func stop() {
        lock.lock()
        let process = self.process
        self.process = nil
        self.port = nil
        lock.unlock()
        process?.terminate()
    }

    private static func wait(port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/healthz") else { return false }
        for _ in 0 ..< 20 {
            if let (_, response) = try? await URLSession.shared.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }
}

enum SearXNGPort {
    static func reserve() throws -> Int {
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
}

enum ReaderLog {
    static func append(status: Int, extractor: String, published: String?, chars: Int, url: String) {
        let directory = PromethIdentity.applicationSupportDirectory
        let urlFile = directory.appendingPathComponent("reader.log")
        let line = "\(ISO8601DateFormatter().string(from: Date()))\t\(status)\t\(extractor)\t\(published ?? "")\t\(chars)\t\(url)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: urlFile.path),
               let handle = try? FileHandle(forWritingTo: urlFile) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: urlFile)
            }
        }
    }

    static func entries() -> [String] {
        let url = PromethIdentity.applicationSupportDirectory.appendingPathComponent("reader.log")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }
}
