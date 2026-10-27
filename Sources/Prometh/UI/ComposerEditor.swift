import SwiftUI
import AppKit

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

// Independently implemented AppKit editor; Nativ's marked-text and Shift-Return pattern informed this boundary.
struct ComposerEditor: NSViewRepresentable {
    @Binding var text: String
    /// True when the NSTextView has non-whitespace content. Used so the SwiftUI
    /// placeholder cannot draw on top of text that has not yet synced into `text`.
    @Binding var hasContent: Bool
    /// Bumps when the selected chat changes so a focused empty draft can replace
    /// leftover NSTextView characters from the previous conversation.
    var conversationID: UUID?
    var onSend: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let view = SubmitTextView()
        view.delegate = context.coordinator
        view.isRichText = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.font = NSFont.systemFont(ofSize: 15)
        view.textColor = .labelColor
        view.insertionPointColor = .labelColor
        view.textContainerInset = NSSize(width: 3, height: 7)
        view.isVerticallyResizable = true
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.applyingExternalUpdate = true
        view.string = text
        view.applyingExternalUpdate = false
        context.coordinator.lastBoundText = text
        view.send = { context.coordinator.commit($0) }
        view.setAccessibilityLabel("Message draft")
        view.setAccessibilityIdentifier("prometh.draft")
        scroll.setAccessibilityIdentifier("prometh.composer")
        scroll.documentView = view
        DispatchQueue.main.async {
            context.coordinator.noteContent(view.string)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? SubmitTextView else { return }
        let conversationChanged = context.coordinator.conversationID != conversationID
        if conversationChanged {
            context.coordinator.conversationID = conversationID
        }
        if ComposerDraftSync.shouldApply(
            binding: text,
            view: view.string,
            editing: view.window?.firstResponder === view,
            conversationChanged: conversationChanged,
            lastBound: context.coordinator.lastBoundText
        ) {
            view.applyingExternalUpdate = true
            view.string = text
            view.applyingExternalUpdate = false
        }
        context.coordinator.lastBoundText = text
        let present = !view.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasContent != present {
            DispatchQueue.main.async {
                context.coordinator.noteContent(view.string)
            }
        }
        view.textColor = .labelColor
        view.insertionPointColor = .labelColor
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerEditor
        var conversationID: UUID?
        /// Last draft string applied from the SwiftUI binding (not from typing).
        var lastBoundText = ""
        init(_ parent: ComposerEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            noteContent(view.string)
        }

        func noteContent(_ value: String) {
            let present = !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if parent.hasContent != present {
                parent.hasContent = present
            }
        }

        func commit(_ value: String) {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            parent.onSend(value)
            parent.text = ""
            parent.hasContent = false
            lastBoundText = ""
        }
    }
}

class SubmitTextView: NSTextView {
    var send: ((String) -> Void)?
    var applyingExternalUpdate = false

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76) && !hasMarkedText() {
            if event.modifierFlags.contains(.shift) {
                insertNewlineIgnoringFieldEditor(nil)
            } else {
                submit()
            }
            return
        }
        super.keyDown(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        if hasMarkedText() {
            super.insertNewline(sender)
        } else {
            submit()
        }
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(insertNewline(_:)) {
            submit()
            return
        }
        super.doCommand(by: selector)
    }

    private var submitting = false
    private func submit() {
        guard !submitting else { return }
        let value = string
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        submitting = true
        applyingExternalUpdate = true
        string = ""
        applyingExternalUpdate = false
        send?(value)
        submitting = false
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if let text = insertString as? String, text == "\n" || text == "\r" {
            submit()
            return
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func didChangeText() {
        super.didChangeText()
        notifyDraftChanged()
    }

    /// AX / VoiceOver set the string without going through typing; push that into
    /// the SwiftUI draft binding so Send uses the pasted text.
    override func accessibilitySetValue(_ value: Any?, forAttribute attribute: NSAccessibility.Attribute) {
        super.accessibilitySetValue(value, forAttribute: attribute)
        if attribute == .value {
            notifyDraftChanged()
        }
    }

    override var string: String {
        get { super.string }
        set {
            super.string = newValue
            // Direct assignment (paste helpers / AX) must still sync the binding,
            // but updates pushed from SwiftUI must not re-enter the binding.
            if !applyingExternalUpdate {
                notifyDraftChanged()
            }
        }
    }

    private func notifyDraftChanged() {
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
    }
}
