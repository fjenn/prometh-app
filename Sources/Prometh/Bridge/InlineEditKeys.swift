import AppKit

/// Keep ordinary Return multiline, and let the input method finish marked text.
enum InlineEditKeys {
    enum Action { case cancel, send, text }
    static func action(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, markedText: Bool) -> Action {
        guard !markedText else { return .text }
        let flags = modifiers.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if keyCode == 53 && flags.isEmpty { return .cancel }
        if (keyCode == 36 || keyCode == 76) && flags == .command { return .send }
        return .text
    }
}
