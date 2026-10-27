import Foundation

/// Decides when SwiftUI's draft binding may replace the focused NSTextView string.
enum ComposerDraftSync {
    static func shouldApply(
        binding: String,
        view: String,
        editing: Bool,
        conversationChanged: Bool,
        lastBound: String
    ) -> Bool {
        if view == binding { return false }
        // Chat switches and non-empty bindings always apply.
        if conversationChanged || !binding.isEmpty || view.isEmpty { return true }
        // Empty binding while focused normally protects an AX/paste race — except
        // when the binding just cleared after holding the sent draft.
        if binding.isEmpty && !lastBound.isEmpty { return true }
        return !editing
    }
}
