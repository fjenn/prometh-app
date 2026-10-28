import Foundation

struct ComposioToolkit: Codable, Equatable, Identifiable, Sendable {
    var slug: String
    var name: String
    var description: String
    var logo: URL?
    var categories: [String]
    var id: String { slug }
}

enum ToolkitCatalogError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { message } else { nil } }
}

struct ToolkitCatalog: Codable, Equatable, Sendable {
    var fetchedAt: Date
    var items: [ComposioToolkit]
    static let cacheLifetime: TimeInterval = 24 * 60 * 60
    func isFresh(at date: Date = Date()) -> Bool { (0..<Self.cacheLifetime).contains(date.timeIntervalSince(fetchedAt)) }
    var categories: [String] { Array(Set(items.flatMap(\.categories))).sorted() }

    func filtered(search: String, category: String = "All categories") -> [ComposioToolkit] {
        let words = search.split(whereSeparator: \.isWhitespace).map(String.init)
        return items.filter { item in
            (category == "All categories" || item.categories.contains(category)) && words.allSatisfy { word in
                ([item.name, item.slug, item.description] + item.categories).joined(separator: " ").localizedStandardContains(word)
            }
        }
    }

    static func parse(_ data: Data, at date: Date = Date()) throws -> Self {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ToolkitCatalogError.invalid("The catalog response was unreadable.") }
        if root["ok"] as? Bool == false { throw ToolkitCatalogError.invalid(root["error"] as? String ?? "Could not load plugins.") }
        guard let raw = root["items"] as? [[String: Any]], !raw.isEmpty else { throw ToolkitCatalogError.invalid("The connection service returned an empty catalog.") }
        var unique: [String: ComposioToolkit] = [:]
        for item in raw {
            guard let slug = item["slug"] as? String, !slug.isEmpty,
                  let name = item["name"] as? String, !name.isEmpty else { throw ToolkitCatalogError.invalid("A plugin is missing its name or identifier.") }
            let meta = item["meta"] as? [String: Any] ?? [:]
            let categories = (meta["categories"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            let logo = (meta["logo"] as? String).flatMap(URL.init(string:)).flatMap { $0.scheme == "https" ? $0 : nil }
            unique[slug] = ComposioToolkit(slug:slug,name:name,description:meta["description"] as? String ?? "",logo:logo,categories:categories)
        }
        return Self(fetchedAt:date,items:unique.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }

    static func readCache(at url: URL) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf:url))
        guard !value.items.isEmpty, Set(value.items.map(\.slug)).count == value.items.count else { throw ToolkitCatalogError.invalid("The saved catalog is invalid.") }
        return value
    }
    func writeCache(at url: URL) throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONEncoder().encode(self).write(to:url,options:.atomic)
    }
}
