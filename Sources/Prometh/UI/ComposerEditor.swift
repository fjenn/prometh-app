import SwiftUI
import AppKit

// Independently implemented AppKit editor; Nativ's marked-text and Shift-Return pattern informed this boundary.
struct ComposerEditor: NSViewRepresentable {
    @Binding var text: String
    var onSend:(String)->Void
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeNSView(context:Context)->NSScrollView {
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.drawsBackground=false
        let view=SubmitTextView();view.delegate=context.coordinator;view.isRichText=false;view.isAutomaticQuoteSubstitutionEnabled=false;view.allowsUndo=true;view.drawsBackground=false;view.font=NSFont.systemFont(ofSize:15);view.textColor = .labelColor;view.insertionPointColor = .labelColor;view.textContainerInset=NSSize(width:3,height:7);view.isVerticallyResizable=true;view.autoresizingMask=[.width];view.textContainer?.widthTracksTextView=true;view.string=text;view.send={ context.coordinator.commit($0) };view.setAccessibilityLabel("Message draft");view.setAccessibilityIdentifier("prometh.draft");scroll.setAccessibilityIdentifier("prometh.composer");scroll.documentView=view;return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context){context.coordinator.parent=self;guard let view=scroll.documentView as? SubmitTextView else{return};if view.string != text {let editing=view.window?.firstResponder===view;if !editing || text.isEmpty {view.string=text}};view.textColor = .labelColor;view.insertionPointColor = .labelColor}
    class Coordinator:NSObject,NSTextViewDelegate {
        var parent:ComposerEditor
        init(_ parent:ComposerEditor){self.parent=parent}
        func textDidChange(_ notification:Notification){if let v=notification.object as? NSTextView{parent.text=v.string}}
        func commit(_ value: String) {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            parent.onSend(value)
            parent.text = ""
        }
    }
}
class SubmitTextView:NSTextView {
    var send:((String)->Void)?
    override func keyDown(with event:NSEvent){if (event.keyCode==36 || event.keyCode==76) && !hasMarkedText(){if event.modifierFlags.contains(.shift){insertNewlineIgnoringFieldEditor(nil)}else{submit()};return};super.keyDown(with:event)}
    override func insertNewline(_ sender: Any?) { if hasMarkedText() { super.insertNewline(sender) } else { submit() } }
    override func doCommand(by selector: Selector) {
        if selector == #selector(insertNewline(_:)) { submit(); return }
        super.doCommand(by: selector)
    }
    private func submit() {
        let value = string
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        string = ""
        send?(value)
    }
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if let text = insertString as? String, text == "\n" || text == "\r" {
            submit()
            return
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }
}
