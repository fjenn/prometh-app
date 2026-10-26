import Foundation

/// Product identity for the Prometh fork. Nativ.app and Prometh.app must be able
/// to sit side by side, so support files, keychain items, and launch agents use
/// these names instead of Nativ's.
enum PromethIdentity {
    static let productName = "Prometh"
    static let bundleIdentifier = "studio.prometh.Prometh"
    static let supportDirectoryName = "Prometh"

    /// Throwaway profile for `scripts/prometh/launch.sh --fresh`.
    static var supportDirectoryOverride: URL? {
        guard let pointer = getenv("PROMETH_SUPPORT_DIR") else { return nil }
        let raw = String(cString: pointer).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Application Support root. Honors `PROMETH_SUPPORT_DIR` so a fresh launch
    /// never touches the real Prometh or Nativ folders.
    static var applicationSupportDirectory: URL {
        if let supportDirectoryOverride {
            return supportDirectoryOverride
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent(supportDirectoryName, isDirectory: true)
    }

    /// Replaces `base.appendingPathComponent("Nativ")`. When `PROMETH_SUPPORT_DIR`
    /// is set, every support and cache root collapses into that directory.
    static func appendingSupportDirectory(to base: URL) -> URL {
        if let supportDirectoryOverride {
            return supportDirectoryOverride
        }
        return base.appendingPathComponent(supportDirectoryName, isDirectory: true)
    }
}
