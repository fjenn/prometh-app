import Foundation

/// Hard line kept in every mode (ported from the web app's catalog.ts):
/// no sexual content involving minors.
enum PromethBlocklist {
    static let message = "Blocked. Prometh never creates sexual content involving minors."

    private static let patterns: [NSRegularExpression] = {
        let sources = [
            #"\bchild\s+(porn|sex|eroti|nude|naked)"#,
            #"\b(kiddie|kiddy)\s+(porn|sex)"#,
            #"\bpedo(phile|philia)?\b"#,
            #"\bminor[s]?\s+(sex|eroti|nude|naked|porn)"#,
            #"\bunderage\s+(sex|eroti|nude|naked|porn)"#,
            #"\bcp\s+(link|vid|pic|image|download)"#,
            #"\bsexual(ly|ize[ds]?)?\s+(child|minor|underage|infant|toddler|pre-?teen|preteen)"#,
            #"\b(child|minor|underage|infant|toddler|pre-?teen|preteen)\s+sexual"#,
            #"\bchild\s+(exploit|abuse|molest|groom)"#,
            #"\b(molest|groom)(ing|ed|s)?\s+(child|children|kid|minor|underage)"#,
            #"\bcsam\b"#,
        ]
        return sources.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
        }
    }()

    static func isBlocked(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return patterns.contains { $0.firstMatch(in: text, options: [], range: range) != nil }
    }

    /// Stream-aware: true once the growing reply already matches a blocked pattern.
    static func shouldStopStreaming(_ partial: String) -> Bool {
        isBlocked(partial)
    }
}
