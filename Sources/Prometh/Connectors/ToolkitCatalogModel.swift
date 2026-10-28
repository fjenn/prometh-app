import Foundation
import Combine
import AppKit

@MainActor
final class ToolkitCatalogModel: ObservableObject {
    @Published var catalog: ToolkitCatalog?
    @Published var loading = false
    @Published var error: String?
    @Published var statuses: [String: String] = [:]
    @Published var connecting: Set<String> = []
    private var loaded = false
    private let cacheURL = PromethIdentity.applicationSupportDirectory.appendingPathComponent("connectors/toolkits-v1.json")

    func load(force: Bool = false) async {
        guard !loading, force || !loaded else { return }
        loaded = true
        if catalog == nil { catalog = try? ToolkitCatalog.readCache(at:cacheURL) }
        loading = true
        defer { loading = false }
        error = nil
        if force || catalog?.isFresh() != true {
            do {
                let fresh = try ToolkitCatalog.parse(try await PromethConnectorClient.request(extra:["--catalog"]))
                catalog = fresh
                do { try fresh.writeCache(at:cacheURL) }
                catch { self.error = "Plugins loaded, but the catalog could not be saved on this Mac." }
            } catch { self.error = error.localizedDescription }
        }
        await refreshStatuses()
    }

    func refreshStatuses() async {
        do {
            let data = try await PromethConnectorClient.request(extra:["--connections"])
            guard let root = try JSONSerialization.jsonObject(with:data) as? [String:Any], root["ok"] as? Bool == true,
                  let values = root["statuses"] as? [String:String] else { throw ToolkitCatalogError.invalid("Could not refresh connected apps. Try Refresh.") }
            statuses = values
        } catch { self.error = error.localizedDescription }
    }

    func connect(_ toolkit: ComposioToolkit) async {
        guard !connecting.contains(toolkit.slug) else { return }
        connecting.insert(toolkit.slug)
        defer { connecting.remove(toolkit.slug) }
        error = nil
        let result = await PromethConnectorClient.link(toolkit:toolkit.slug)
        guard let url = result.redirectURL, result.ok else { error=result.message ?? "The authorization page was not returned."; return }
        guard NSWorkspace.shared.open(url) else { error="macOS could not open the authorization page."; return }
        statuses[toolkit.slug] = "pending"
        for _ in 0..<60 {
            let current = await PromethConnectorClient.status(toolkit:toolkit.slug)
            if !current.ok { error=current.message ?? "Could not check the connection."; return }
            statuses[toolkit.slug] = current.status
            if current.status == "connected" || current.status == "expired" { return }
            do { try await Task.sleep(for:.seconds(2)) } catch { return }
        }
        error = "Sign-in timed out for \(toolkit.name). Choose Connect to try again."
    }
}
