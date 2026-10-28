import SwiftUI
import AppKit

/// A measured NSTextView grows with wrapped lines, then scrolls for long edits.
struct InlineMessageEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var onCancel: () -> Void
    var onSend: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        let view = EditTextView()
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.drawsBackground = false
        view.font = .systemFont(ofSize: 15)
        view.textColor = .labelColor
        view.insertionPointColor = .labelColor
        view.textContainerInset = NSSize(width: 0, height: 5)
        view.isVerticallyResizable = true
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.string = text
        view.delegate = context.coordinator
        view.cancel = { context.coordinator.parent.onCancel() }
        view.send = { context.coordinator.parent.onSend($0) }
        view.measured = { context.coordinator.measure(view) }
        view.setAccessibilityLabel("Edit message inline")
        view.setAccessibilityIdentifier("prometh.inline-editor")
        scroll.documentView = view
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
            context.coordinator.measure(view)
        }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? EditTextView else { return }
        if view.string != text { view.string = text }
        view.textColor = .labelColor
        context.coordinator.measure(view)
    }
    @MainActor
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineMessageEditor
        init(_ parent: InlineMessageEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            measure(view)
        }
        func measure(_ view: NSTextView) {
            guard let layout = view.layoutManager, let container = view.textContainer else { return }
            layout.ensureLayout(for: container)
            let size = min(300, max(46, ceil(layout.usedRect(for: container).height + 14)))
            if abs(parent.height - size) > 1 {
                DispatchQueue.main.async { self.parent.height = size }
            }
        }
    }
}

final class EditTextView: NSTextView {
    var cancel: (() -> Void)?
    var send: ((String) -> Void)?
    var measured: (() -> Void)?
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); measured?() }
    override func keyDown(with event: NSEvent) {
        switch InlineEditKeys.action(keyCode: event.keyCode, modifiers: event.modifierFlags, markedText: hasMarkedText()) {
        case .cancel: cancel?()
        case .send:
            if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { send?(string) }
        case .text: super.keyDown(with: event)
        }
    }
}

struct MessageActionButton: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @State private var hovered = false
    @FocusState private var focused: Bool
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .frame(width: 30, height: 30)
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focused($focused)
        .overlay(RoundedRectangle(cornerRadius:8).strokeBorder(.primary.opacity(focused ? 0.6:0),lineWidth:2))
        .foregroundStyle(hovered || focused ? .primary : .secondary)
        .background(.primary.opacity(hovered ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 8))
        .onHover { hovered = $0 }
        .help(title)
        .accessibilityLabel(title)
    }
}
