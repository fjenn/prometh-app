import Foundation

enum CatalogTransferError: Error, Equatable {
    case paused(path: String, offset: Int64)
    case cancelled
    case interrupted(String)
    case unsafePath
}

struct CatalogTransferProgress: Sendable {
    var completed: Int64
    var total: Int64
    var file: String
    var stage: String
    var offset: Int64
}

/// Pause and cancel are checked between network chunks. The `.partial` file
/// stays on disk so a later call continues at the logged byte offset.
final class TransferControl: @unchecked Sendable {
    enum Signal: Equatable { case run, pause, cancel }

    private let lock = NSLock()
    private var signal = Signal.run

    func pause() { lock.withLock { signal = .pause } }
    func cancel() { lock.withLock { signal = .cancel } }
    func reset() { lock.withLock { signal = .run } }
    func current() -> Signal { lock.withLock { signal } }
}

enum CatalogDownloader {
    static let interruptedMessage = "Preparation interrupted. Try again."

    static func prepare(
        model: CatalogModel,
        support: URL,
        headroom: Int64,
        control: TransferControl,
        log: @escaping @Sendable (String) -> Void,
        progress: @escaping @Sendable (CatalogTransferProgress) -> Void
    ) async throws {
        let root = CatalogPaths.modelsRoot(support: support)
        let folder = CatalogPaths.folder(root: root, model: model)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let total = model.files.reduce(Int64(0)) { $0 + $1.size }
        var completed = Int64(0)
        for file in model.files {
            let destination = try safeFile(file.path, under: folder)
            if try CatalogHash.matches(file, at: destination) {
                completed += file.size
                try linkVerified(file: file, model: model, source: destination, support: support)
                progress(CatalogTransferProgress(
                    completed: completed, total: total, file: file.path, stage: "checking", offset: file.size
                ))
                continue
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
                log("corrupt removed path=\(file.path)")
            }
            let blob = CatalogPaths.blob(root: root, contentID: file.contentID)
            if try CatalogHash.matches(file, at: blob) {
                try linkItem(from: blob, to: destination)
                try linkVerified(file: file, model: model, source: destination, support: support)
                completed += file.size
                log("deduped contentID=\(file.contentID) path=\(file.path)")
                continue
            }
            try await transfer(
                file: file,
                model: model,
                destination: destination,
                blob: blob,
                support: support,
                headroom: headroom,
                completedBefore: completed,
                total: total,
                control: control,
                log: log,
                progress: progress
            )
            completed += file.size
        }
        try writeMainRef(model: model, support: support)
        log("verified model=\(model.id) revision=\(model.revision) files=\(model.files.count)")
    }

    static func corruptFiles(model: CatalogModel, support: URL) throws -> [String] {
        let folder = CatalogPaths.folder(root: CatalogPaths.modelsRoot(support: support), model: model)
        var broken: [String] = []
        for file in model.files {
            let destination = try safeFile(file.path, under: folder)
            if (try? CatalogHash.matches(file, at: destination)) != true {
                broken.append(file.path)
            }
        }
        return broken
    }

    private static func transfer(
        file: CatalogFile,
        model: CatalogModel,
        destination: URL,
        blob: URL,
        support: URL,
        headroom: Int64,
        completedBefore: Int64,
        total: Int64,
        control: TransferControl,
        log: @escaping @Sendable (String) -> Void,
        progress: @escaping @Sendable (CatalogTransferProgress) -> Void
    ) async throws {
        if PrepFault.shared.consume() {
            log("stage=failed reason=injected")
            throw CatalogTransferError.interrupted(interruptedMessage)
        }
        guard let remote = URL(string: file.url) else {
            throw CatalogTransferError.interrupted(interruptedMessage)
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: blob.deletingLastPathComponent(), withIntermediateDirectories: true)
        let partial = destination.appendingPathExtension("partial")
        var offset = CatalogHash.byteCount(partial) ?? 0
        if offset > file.size {
            try? FileManager.default.removeItem(at: partial)
            offset = 0
        }
        if offset > 0 {
            log("resume path=\(file.path) offset=\(offset)")
        }
        if offset < file.size {
            let free = CatalogFit.freeBytes(at: support)
            if free < (file.size - offset) + headroom {
                log("stage=failed reason=space free=\(free)")
                throw CatalogTransferError.interrupted("Not enough space for \(model.capability.lowercased()).")
            }
            log("stage=downloading path=\(file.path) offset=\(offset)")
            try await stream(
                url: remote,
                partial: partial,
                label: file.path,
                expected: file.size,
                offset: offset,
                headroom: headroom,
                volume: support,
                control: control,
                onChunk: { written in
                    progress(CatalogTransferProgress(
                        completed: completedBefore + written,
                        total: total,
                        file: file.path,
                        stage: "downloading",
                        offset: written
                    ))
                }
            )
        }
        log("stage=checking path=\(file.path)")
        progress(CatalogTransferProgress(
            completed: completedBefore + file.size, total: total, file: file.path, stage: "checking", offset: file.size
        ))
        guard try CatalogHash.matches(file, at: partial) else {
            let size = CatalogHash.byteCount(partial) ?? -1
            try? FileManager.default.removeItem(at: partial)
            log("checksum failed path=\(file.path) size=\(size) expected=\(file.size)")
            throw CatalogTransferError.interrupted(interruptedMessage)
        }
        if FileManager.default.fileExists(atPath: blob.path) {
            try FileManager.default.removeItem(at: blob)
        }
        try FileManager.default.moveItem(at: partial, to: blob)
        try linkItem(from: blob, to: destination)
        try linkVerified(file: file, model: model, source: destination, support: support)
    }

    /// curl writes the partial file and honors `Range` on resume. Polling the
    /// file size is the pause point: interrupt leaves the bytes already saved.
    private static func stream(
        url: URL,
        partial: URL,
        label: String,
        expected: Int64,
        offset: Int64,
        headroom: Int64,
        volume: URL,
        control: TransferControl,
        onChunk: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let transfer = CurlTransfer(
            url: url, partial: partial, label: label, expected: expected, offset: offset,
            headroom: headroom, volume: volume, control: control, onChunk: onChunk
        )
        try await transfer.run()
    }

    private static func safeFile(_ path: String, under folder: URL) throws -> URL {
        if path.hasPrefix("/") || path.contains("..") || path.contains("\\") {
            throw CatalogTransferError.unsafePath
        }
        let url = folder.appendingPathComponent(path)
        let root = folder.standardizedFileURL.path
        let target = url.standardizedFileURL.path
        guard target == root || target.hasPrefix(root + "/") else {
            throw CatalogTransferError.unsafePath
        }
        return url
    }

    private static func linkItem(from source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        do {
            try FileManager.default.linkItem(at: source, to: destination)
        } catch {
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private static func linkVerified(file: CatalogFile, model: CatalogModel, source: URL, support: URL) throws {
        let destination = CatalogPaths.snapshotFile(hub: CatalogPaths.hub(support: support), model: model, path: file.path)
        try linkItem(from: source, to: destination)
    }

    private static func writeMainRef(model: CatalogModel, support: URL) throws {
        let ref = CatalogPaths.mainRef(hub: CatalogPaths.hub(support: support), model: model)
        try FileManager.default.createDirectory(at: ref.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(model.revision.utf8).write(to: ref, options: .atomic)
    }
}

/// Owns the curl process for one file. `@unchecked Sendable` because the
/// process is touched only from the task that calls `run()`.
private final class CurlTransfer: @unchecked Sendable {
    let url: URL
    let partial: URL
    let label: String
    let expected: Int64
    let offset: Int64
    let headroom: Int64
    let volume: URL
    let control: TransferControl
    let onChunk: @Sendable (Int64) -> Void
    let process = Process()
    let errors = Pipe()

    init(
        url: URL, partial: URL, label: String, expected: Int64, offset: Int64,
        headroom: Int64, volume: URL, control: TransferControl,
        onChunk: @escaping @Sendable (Int64) -> Void
    ) {
        self.url = url
        self.partial = partial
        self.label = label
        self.expected = expected
        self.offset = offset
        self.headroom = headroom
        self.volume = volume
        self.control = control
        self.onChunk = onChunk
    }

    func run() async throws {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        var arguments = [
            "--fail", "--location", "--silent", "--show-error", "--no-buffer",
            "--user-agent", "Prometh/0.4",
            "--output", partial.path,
            url.absoluteString
        ]
        if offset > 0 {
            arguments.insert(contentsOf: ["--continue-at", "-"], at: 0)
        }
        process.arguments = arguments
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        if !FileManager.default.fileExists(atPath: partial.path) {
            FileManager.default.createFile(atPath: partial.path, contents: nil)
        }
        try process.run()

        while process.isRunning {
            let size = Self.fileSize(partial)
            onChunk(size)
            if CatalogFit.freeBytes(at: volume) < headroom {
                process.terminate()
                process.waitUntilExit()
                throw CatalogTransferError.interrupted(CatalogDownloader.interruptedMessage)
            }
            switch control.current() {
            case .pause:
                try await stop()
                throw CatalogTransferError.paused(path: label, offset: Self.fileSize(partial))
            case .cancel:
                try await stop()
                throw CatalogTransferError.cancelled
            case .run:
                break
            }
            try await Task.sleep(nanoseconds: 15_000_000)
        }
        process.waitUntilExit()
        let saved = Self.fileSize(partial)
        onChunk(saved)
        guard process.terminationStatus == 0, saved == expected else {
            let note = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            print("prometh curl failed status=\(process.terminationStatus) saved=\(saved)/\(expected) \(note)")
            throw CatalogTransferError.interrupted(CatalogDownloader.interruptedMessage)
        }
    }

    private func stop() async throws {
        if process.isRunning { process.interrupt() }
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

/// One-shot preparation failure used by `--prometh-selftest prep-fail`.
final class PrepFault: @unchecked Sendable {
    static let shared = PrepFault()
    private let lock = NSLock()
    private var armed: Bool

    private init() {
        let environment = ProcessInfo.processInfo.environment["PROMETH_PREP_FAIL_ONCE"] == "1"
        let arguments = CommandLine.arguments.contains("prep-fail")
        armed = environment || arguments
    }

    func consume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard armed else { return false }
        armed = false
        return true
    }
}
