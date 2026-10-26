import Foundation

/// Runs catalog downloads for the onboarding rows and records pause offsets.
@MainActor
final class PreparationCoordinator {
    private weak var store: PromethStore?
    private var tasks: [String: Task<Void, Never>] = [:]
    private var controls: [String: TransferControl] = [:]
    private var started = Date()
    private var lastUI = Date.distantPast
    private var didAutoPause = false

    func attach(_ store: PromethStore) {
        self.store = store
    }

    func resume(_ capability: Capability) {
        guard let store else { return }
        guard store.state.selected.contains(capability) else { return }
        if let reason = store.blockReason(capability) {
            store.applyPreparation(capability.rawValue, Preparation(progress: 0, status: .failed), detail: reason)
            return
        }
        if capability == .chat, store.catalogReady(.chat) {
            store.markReady(capability)
            return
        }
        begin(capability.rawValue, models: store.preparationModels(capability), capability: capability)
    }

    func pause(_ capability: Capability) {
        controls[capability.rawValue]?.pause()
        store?.notePaused(capability)
    }

    func cancel(_ capability: Capability) {
        controls[capability.rawValue]?.cancel()
        tasks[capability.rawValue]?.cancel()
        tasks[capability.rawValue] = nil
        store?.applyPreparation(capability.rawValue, Preparation(progress: 0, status: .cancelled), detail: "Cancelled")
    }

    func verify(_ capability: Capability) {
        resume(capability)
    }

    private func begin(_ key: String, models: [CatalogModel], capability: Capability?) {
        tasks[key]?.cancel()
        let control = TransferControl()
        controls[key] = control
        started = Date()
        tasks[key] = Task { [weak self] in
            await self?.run(key: key, models: models, capability: capability, control: control)
        }
    }

    private func run(
        key: String,
        models: [CatalogModel],
        capability: Capability?,
        control: TransferControl
    ) async {
        guard let store else { return }
        let support = store.persistence.directory
        do {
            let catalog = try ModelCatalogLoader.bundled()
            for model in models {
                store.applyPreparation(key, Preparation(progress: 0, status: .preparing), detail: "Preparing")
                try await CatalogDownloader.prepare(
                    model: model,
                    support: support,
                    headroom: catalog.storagePolicy.macOSHeadroomBytes,
                    control: control,
                    log: { line in CatalogLog.append(line, support: support) },
                    progress: { [weak self] update in
                        Task { @MainActor in
                            self?.show(key: key, update: update, name: model.name)
                        }
                    }
                )
                if capability == .chat, model.id == "safe" {
                    store.pinCatalogModel(model)
                }
            }
            store.markReady(capability, key: key)
            CatalogLog.append("stage=ready key=\(key)", support: support)
            await store.finishSelfTestIfNeeded(key: key)
        } catch is CancellationError {
            return
        } catch CatalogTransferError.paused(let path, let offset) {
            CatalogLog.append("pause path=\(path) offset=\(offset)", support: support)
            CatalogLog.append("stage=paused key=\(key) path=\(path) offset=\(offset)", support: support)
            store.notePaused(capability, key: key)
            await store.finishPauseSelfTestIfNeeded(key: key, path: path, offset: offset)
        } catch CatalogTransferError.cancelled {
            store.applyPreparation(key, Preparation(progress: 0, status: .cancelled), detail: "Cancelled")
        } catch CatalogTransferError.interrupted(let message) {
            CatalogLog.append("stage=failed key=\(key) message=\(message)", support: support)
            store.applyPreparation(key, Preparation(progress: store.preparationProgress(key), status: .failed), detail: message)
            await store.finishFailureSelfTestIfNeeded(key: key, message: message)
        } catch {
            let message = CatalogDownloader.interruptedMessage
            CatalogLog.append("stage=failed key=\(key) message=\(error.localizedDescription)", support: support)
            store.applyPreparation(key, Preparation(progress: store.preparationProgress(key), status: .failed), detail: message)
            await store.finishFailureSelfTestIfNeeded(key: key, message: message)
        }
    }

    private func show(key: String, update: CatalogTransferProgress, name: String) {
        guard let store else { return }
        let fraction = update.total > 0 ? Double(update.completed) / Double(update.total) : 0
        if !didAutoPause,
           ProcessInfo.processInfo.environment["PROMETH_PREP_AUTOPAUSE"] == "1",
           fraction >= 0.10,
           update.stage == "downloading" {
            didAutoPause = true
            controls[key]?.pause()
        }
        if update.stage == "downloading", Date().timeIntervalSince(lastUI) < 0.25 {
            return
        }
        lastUI = Date()
        let status: JobStatus = update.stage == "checking" ? .checking : .downloading
        let percent = Int((fraction * 100).rounded(.down))
        let elapsed = Date().timeIntervalSince(started)
        let detail: String
        if elapsed > 1, update.completed > 0, update.completed < update.total {
            let speed = Double(update.completed) / elapsed
            let seconds = Double(update.total - update.completed) / speed
            detail = "\(status.rawValue) \(percent)% · \(Self.remaining(seconds))"
        } else {
            detail = "\(status.rawValue) \(percent)%"
        }
        _ = name
        store.applyPreparation(
            key,
            Preparation(progress: fraction, status: status),
            detail: detail
        )
    }

    private static func remaining(_ seconds: Double) -> String {
        if seconds < 90 { return "about a minute left" }
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes) min left"
    }
}
