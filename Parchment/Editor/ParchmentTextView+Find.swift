import AppKit

/// Find and replace through the standard macOS find bar, which sits at the top of the
/// enclosing scroll view (`usesFindBar` is set in `configure()`).
///
/// SwiftUI's default Edit > Find menu sends its actions down the responder chain, which
/// doesn't reliably reach a text view hosted in an `NSViewRepresentable`. A window offers
/// key equivalents to its views before the menu bar, so the text view claims the find
/// shortcuts here. They work whichever view has focus, the find bar's own fields included.
extension ParchmentTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.isKeyWindow == true, let action = Self.finderAction(for: event) {
            performFind(action)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Runs a find bar action. Replace falls back to plain find while the text is read-only
    /// (reading mode, or while Claude Code works on the file).
    func performFind(_ action: NSTextFinder.Action) {
        var action = action
        if action == .showReplaceInterface, !isEditable {
            action = .showFindInterface
        }
        let item = NSMenuItem()
        item.action = #selector(NSResponder.performTextFinderAction(_:))
        item.tag = action.rawValue
        // Skip actions that don't apply now, such as Find Next before anything was searched.
        guard validateUserInterfaceItem(item) else {
            if action != .showFindInterface { NSSound.beep() }
            return
        }
        performTextFinderAction(item)
    }

    /// The find bar action for the standard Mac shortcuts:
    /// ⌘F find, ⌥⌘F find and replace, ⌘G / ⇧⌘G next and previous match,
    /// ⌘E use selection for find.
    private static func finderAction(for event: NSEvent) -> NSTextFinder.Action? {
        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        switch (key, modifiers) {
        case ("f", [.command]): return .showFindInterface
        case ("f", [.command, .option]): return .showReplaceInterface
        case ("g", [.command]): return .nextMatch
        case ("g", [.command, .shift]): return .previousMatch
        case ("e", [.command]): return .setSearchString
        default: return nil
        }
    }
}
