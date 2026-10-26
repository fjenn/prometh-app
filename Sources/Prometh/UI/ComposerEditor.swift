import SwiftUI
import AppKit

// Independently implemented AppKit editor; Nativ's marked-text and Shift-Return pattern informed this boundary.
struct ComposerEditor: NSViewRepresentable {
    @Binding var text: String
    var onSend:()->Void
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeNSView(context:Context)->NSScrollView {
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.drawsBackground=false
        let view=SubmitTextView();view.delegate=context.coordinator;view.isRichText=false;view.isAutomaticQuoteSubstitutionEnabled=false;view.allowsUndo=true;view.drawsBackground=false;view.font=NSFont.systemFont(ofSize:15);view.textColor = .labelColor;view.insertionPointColor = .labelColor;view.textContainerInset=NSSize(width:3,height:7);view.isVerticallyResizable=true;view.autoresizingMask=[.width];view.textContainer?.widthTracksTextView=true;view.string=text;view.send={context.coordinator.parent.onSend()};view.setAccessibilityLabel("Message draft");view.setAccessibilityIdentifier("prometh.draft");scroll.setAccessibilityIdentifier("prometh.composer");scroll.documentView=view;return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context){context.coordinator.parent=self;guard let view=scroll.documentView as? SubmitTextView else{return};if view.string != text{view.string=text};view.textColor = .labelColor;view.insertionPointColor = .labelColor}
    class Coordinator:NSObject,NSTextViewDelegate {var parent:ComposerEditor;init(_ parent:ComposerEditor){self.parent=parent};func textDidChange(_ notification:Notification){if let v=notification.object as? NSTextView{parent.text=v.string}}}
}
class SubmitTextView:NSTextView {
    var send:(()->Void)?
    override func keyDown(with event:NSEvent){if (event.keyCode==36 || event.keyCode==76) && !hasMarkedText(){if event.modifierFlags.contains(.shift){insertNewlineIgnoringFieldEditor(nil)}else{send?()};return};super.keyDown(with:event)}
}
