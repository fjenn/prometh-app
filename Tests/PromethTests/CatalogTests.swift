import XCTest

private final class PauseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim(_ condition: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard condition, !claimed else { return false }
        claimed = true
        return true
    }
}

final class CatalogTests: XCTestCase {
    func testHashVectors() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prometh-hash-\(UUID().uuidString)")
        try Data("hello\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try CatalogHash.sha256(of: url), "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03")
        XCTAssertEqual(try CatalogHash.gitBlobSHA1(of: url), "ce013625030ba8dba906f756967f9e9ca394464a")
    }

    func testLowDiskBlocksChatAndLeavesAReason() throws {
        let catalog = try ModelCatalogLoader.bundled()
        let safe = try XCTUnwrap(catalog.model(id: "safe"))
        XCTAssertEqual(safe.revision, "475b9088d29754a3379866cf5aeb6b41acd313c2")
        XCTAssertEqual(catalog.storagePolicy.macOSHeadroomBytes, 8_000_000_000)
        let reason = CatalogFit.reason(
            capability: .chat,
            models: [safe],
            headroom: catalog.storagePolicy.macOSHeadroomBytes,
            memoryGB: 128,
            freeBytes: 1_000_000_000
        )
        XCTAssertEqual(reason, "Not enough space for chat.")
        XCTAssertNil(CatalogFit.reason(
            capability: .chat,
            models: [safe],
            headroom: catalog.storagePolicy.macOSHeadroomBytes,
            memoryGB: 128,
            freeBytes: safe.downloadBytes + catalog.storagePolicy.macOSHeadroomBytes
        ))
        XCTAssertEqual(
            CatalogFit.reason(capability: .video, models: catalog.preparationModels(for: .video), headroom: 0, memoryGB: 4, freeBytes: .max),
            "Video needs more memory."
        )
    }

    func testFriendlyCatalogNamesAreNotRepositoryIds() throws {
        let catalog = try ModelCatalogLoader.bundled()
        let repo = #/[A-Za-z0-9-]+\/[A-Za-z0-9._-]+/#
        for model in catalog.models where model.enabled {
            XCTAssertNil(model.name.firstMatch(of: repo), model.name)
        }
        XCTAssertEqual(catalog.model(id: "safe")?.name, "Gemma 4 E4B · Safe")
    }

    func testPauseResumesFromThePartialOffset() async throws {
        let payload = Data((0..<512_000).map { UInt8($0 % 251) })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("prometh-range-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("blob.bin")
        try payload.write(to: file)
        let port = try startRangeServer(file: file)
        defer { stopServer(port: port) }

        let digest = SHA256Hex(payload)
        let artifact = CatalogFile(
            path: "blob.bin",
            size: Int64(payload.count),
            hashAlgorithm: "sha256",
            hash: digest,
            sha256: digest,
            oid: nil,
            contentID: "sha256:\(digest)",
            url: "http://127.0.0.1:\(port)/blob.bin"
        )
        let model = CatalogModel(
            id: "fixture",
            name: "Fixture",
            capability: "Chat",
            repo: "prometh/fixture",
            runtime: "test",
            enabled: true,
            workingMemoryGB: 1,
            revision: "abcdef1234567890",
            files: [artifact],
            downloadBytes: artifact.size
        )
        let support = directory.appendingPathComponent("support", isDirectory: true)
        let control = TransferControl()
        let gate = PauseGate()
        do {
            try await CatalogDownloader.prepare(
                model: model,
                support: support,
                headroom: 0,
                control: control,
                log: { _ in },
                progress: { update in
                    if gate.claim(update.completed >= artifact.size / 10) {
                        control.pause()
                    }
                }
            )
            XCTFail("expected a pause")
        } catch CatalogTransferError.paused(let path, let offset) {
            XCTAssertEqual(path, "blob.bin")
            XCTAssertGreaterThanOrEqual(offset, artifact.size / 10)
            XCTAssertLessThan(offset, artifact.size)
            let partial = CatalogPaths.folder(root: CatalogPaths.modelsRoot(support: support), model: model)
                .appendingPathComponent("blob.bin.partial")
            let partialSize = try partial.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            XCTAssertEqual(Int64(partialSize), offset)
            CatalogLog.append("pause path=\(path) offset=\(offset)", support: support)
        }

        control.reset()
        try await CatalogDownloader.prepare(
            model: model,
            support: support,
            headroom: 0,
            control: control,
            log: { line in CatalogLog.append(line, support: support) },
            progress: { _ in }
        )
        let log = try String(contentsOf: support.appendingPathComponent("preparation.log"), encoding: .utf8)
        XCTAssertTrue(log.contains("offset="))
        XCTAssertTrue(log.contains("resume path=blob.bin offset="))
        let stored = CatalogPaths.folder(root: CatalogPaths.modelsRoot(support: support), model: model).appendingPathComponent("blob.bin")
        XCTAssertTrue(try CatalogHash.matches(artifact, at: stored))
    }

    func testCorruptFileIsReplacedOnVerify() async throws {
        let payload = Data(repeating: 7, count: 40_000)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("prometh-corrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("blob.bin")
        try payload.write(to: file)
        let port = try startRangeServer(file: file)
        defer { stopServer(port: port) }
        let digest = SHA256Hex(payload)
        let artifact = CatalogFile(
            path: "blob.bin", size: Int64(payload.count), hashAlgorithm: "sha256", hash: digest,
            sha256: digest, oid: nil, contentID: "sha256:\(digest)", url: "http://127.0.0.1:\(port)/blob.bin"
        )
        let model = CatalogModel(
            id: "fixture", name: "Fixture", capability: "Chat", repo: "prometh/fixture", runtime: "test",
            enabled: true, workingMemoryGB: 1, revision: "abcdef1234567890", files: [artifact], downloadBytes: artifact.size
        )
        let support = directory.appendingPathComponent("support", isDirectory: true)
        let control = TransferControl()
        try await CatalogDownloader.prepare(model: model, support: support, headroom: 0, control: control, log: { _ in }, progress: { _ in })
        let stored = CatalogPaths.folder(root: CatalogPaths.modelsRoot(support: support), model: model).appendingPathComponent("blob.bin")
        var broken = try Data(contentsOf: stored)
        broken[0] ^= 0xFF
        try broken.write(to: stored)
        XCTAssertEqual(try CatalogDownloader.corruptFiles(model: model, support: support), ["blob.bin"])
        control.reset()
        try await CatalogDownloader.prepare(model: model, support: support, headroom: 0, control: control, log: { _ in }, progress: { _ in })
        XCTAssertTrue(try CatalogHash.matches(artifact, at: stored))
        XCTAssertEqual(try CatalogDownloader.corruptFiles(model: model, support: support), [])
    }

    private func SHA256Hex(_ data: Data) -> String {
        // Match CatalogHash by writing through the same function in the assertion setup.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prometh-digest-\(UUID().uuidString)")
        try? data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return (try? CatalogHash.sha256(of: url)) ?? ""
    }

    private func startRangeServer(file: URL) throws -> Int {
        let script = directoryScript(file: file)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.availableData
        let port = Int(String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        guard let port else {
            process.terminate()
            XCTFail("range server did not print a port")
            return 0
        }
        servers[port] = process
        return port
    }

    private func stopServer(port: Int) {
        servers[port]?.terminate()
        servers[port] = nil
    }

    private var servers: [Int: Process] = [:]

    private func directoryScript(file: URL) -> String {
        """
import os, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
path = \(pythonString(file.path))
payload = open(path, 'rb').read()
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        header = self.headers.get('Range')
        if header and header.startswith('bytes='):
            start = int(header.split('=')[1].split('-')[0] or '0')
            body = payload[start:]
            self.send_response(206)
            self.send_header('Content-Range', f'bytes {start}-{len(payload)-1}/{len(payload)}')
        else:
            body = payload
            self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        step = 32 * 1024
        for index in range(0, len(body), step):
            self.wfile.write(body[index:index + step])
            self.wfile.flush()
            time.sleep(0.02)
    def log_message(self, fmt, *args):
        return
server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
print(server.server_address[1], flush=True)
server.serve_forever()
"""
    }

    private func pythonString(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        return "'\(escaped)'"
    }
}
