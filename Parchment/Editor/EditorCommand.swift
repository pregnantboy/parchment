/// A formatting or structure command sent from menus and shortcuts to the focused editor.
///
/// Each case maps to one `MarkdownEditing` operation in `ParchmentTextView.perform(_:)`.
nonisolated enum EditorCommand: Equatable, Sendable {
    case bold
    case italic
    case strikethrough
    case inlineCode
    case link
    /// Level 1...6 makes a heading; 0 turns the line back into body text.
    case heading(Int)
    case task
    case indent
    case outdent
}
