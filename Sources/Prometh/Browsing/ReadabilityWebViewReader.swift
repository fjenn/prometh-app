import AppKit
import Foundation
import WebKit

/// Off-screen page load for JavaScript-rendered articles. No shared cookies.
/// Reads are serialized: a shared continuation cannot be overwritten mid-flight.
@MainActor
final class ReadabilityWebViewReader: NSObject, WKNavigationDelegate {
    static let shared = ReadabilityWebViewReader()

    private var webView: WKWebView?
    private var window: NSWindow?
    private var continuation: CheckedContinuation<ReadabilityPage, Error>?
    private var timeout: Task<Void, Never>?
    private var chain: Task<Void, Never> = Task {}

    func read(url: URL) async throws -> ReadabilityPage {
        let prior = chain
        let gate = Task<ReadabilityPage, Error> {
            _ = await prior.result
            return try await self.readExclusive(url: url)
        }
        chain = Task { _ = try? await gate.value }
        return try await gate.value
    }

    private func readExclusive(url: URL) async throws -> ReadabilityPage {
        try await withCheckedThrowingContinuation { continuation in
            // Drop any stale waiter before taking this slot.
            if let stale = self.continuation {
                self.continuation = nil
                stale.resume(throwing: ReadabilityReaderError.timedOut)
            }
            self.continuation = continuation
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = true
            let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 1600), configuration: configuration)
            view.navigationDelegate = self
            self.webView = view
            let window = NSWindow(
                contentRect: NSRect(x: -4000, y: -4000, width: 1280, height: 1600),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.contentView = view
            self.window = window
            self.timeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                await MainActor.run {
                    self?.finish(.failure(ReadabilityReaderError.timedOut))
                }
            }
            view.load(URLRequest(url: url, timeoutInterval: 12))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await self.extract(from: webView) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    private func extract(from webView: WKWebView) async {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let script = Self.injectionScript()
        do {
            let value = try await webView.evaluateJavaScript(script)
            let data = try JSONSerialization.data(withJSONObject: value as Any)
            let page = try JSONDecoder().decode(ReadabilityPage.self, from: data)
            finish(.success(page))
        } catch {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<ReadabilityPage, Error>) {
        timeout?.cancel()
        timeout = nil
        let continuation = self.continuation
        self.continuation = nil
        webView?.stopLoading()
        webView = nil
        window?.close()
        window = nil
        continuation?.resume(with: result)
    }

    private static func injectionScript() -> String {
        let source = readabilitySource()
        return """
        \(source)
        (function() {
          var article = null;
          try { article = new Readability(document.cloneNode(true)).parse(); } catch (error) {}
          var text = article && article.textContent ? article.textContent : (document.body ? document.body.innerText : "");
          return {
            title: article && article.title ? article.title : document.title,
            text: text || "",
            published: article && article.publishedTime ? article.publishedTime : ""
          };
        })()
        """
    }

    private static func readabilitySource() -> String {
        if let url = Bundle.main.url(forResource: "Readability", withExtension: "js"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        #if DEBUG
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Readability.js")
        return (try? String(contentsOf: repo, encoding: .utf8)) ?? ""
        #else
        return ""
        #endif
    }
}

struct ReadabilityPage: Decodable, Sendable {
    let title: String?
    let text: String
    let published: String?
}

enum ReadabilityReaderError: Error {
    case timedOut
}
