import Foundation

struct SearXNGBrowsingProvider: WebBrowsingProviderClient {
    let provider = WebSearchProvider.searxng
    let transport: WebBrowsingTransport

    func search(
        access: WebSearchProviderAccess,
        query: String,
        limit: Int
    ) async throws -> [WebSearchResult] {
        var instanceURL = try access.instanceURL(for: provider)
        // PROMETH-SEAM: S6 — the stored URL is the sentinel; the live port changes per launch.
        if instanceURL.host?.lowercased() == "prometh-embedded" {
            guard let resolved = await PromethSearXNGEndpoint.resolve?() else {
                throw WebBrowsingError.providerUnavailable(provider)
            }
            instanceURL = resolved
        }
        let searchURL = instanceURL.appendingPathComponent("search", isDirectory: false)
        guard var components = URLComponents(
            url: searchURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw WebBrowsingError.invalidResponse(provider)
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url else {
            throw WebBrowsingError.invalidResponse(provider)
        }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response: SearXNGSearchResponse = try await transport.response(
            for: request,
            provider: provider
        )
        let cap = max(limit, 8)
        let ranked = response.results.enumerated().sorted { lhs, rhs in
            let left = lhs.element.score ?? 0
            let right = rhs.element.score ?? 0
            if left == right { return lhs.offset < rhs.offset }
            return left > right
        }
        var seen: Set<String> = []
        var results: [WebSearchResult] = []
        for item in ranked {
            guard let result = WebSearchResult(
                title: item.element.title,
                url: item.element.url,
                snippet: item.element.content
            ), seen.insert(result.url).inserted else { continue }
            results.append(result)
            if results.count == cap { break }
        }
        return results
    }
}

/// Prometh's supervisor fills this in. Tests that talk to a stub instance never call it.
enum PromethSearXNGEndpoint {
    nonisolated(unsafe) static var resolve: (@Sendable () async -> URL?)?
}

private struct SearXNGSearchResponse: Decodable {
    let results: [SearXNGSearchResult]
}

private struct SearXNGSearchResult: Decodable {
    let title: String?
    let url: String?
    let content: String?
    let score: Double?

    enum CodingKeys: String, CodingKey {
        case title, url, content, score
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        if let number = try? container.decodeIfPresent(Double.self, forKey: .score) {
            score = number
        } else if let text = try? container.decodeIfPresent(String.self, forKey: .score), let number = Double(text) {
            score = number
        } else {
            score = nil
        }
    }
}
