/// The inline role of a stretch of text within a line.
public enum SpanKind: Hashable, Sendable {
    /// Markdown punctuation such as `**`, `#`, or `](`, drawn faded so the words lead.
    case syntax
    case strong
    case emphasis
    case strikethrough
    /// The content of an inline code span, without its backticks.
    case code
    case linkText(destination: String)
    case linkDestination(destination: String)
    case listMarker
    case quoteMarker
    /// The `[ ]` or `[x]` of a task list item.
    case taskBox(isChecked: Bool)
    /// The text of a checked task.
    case completedTask
    case tableHeader
    case codeToken(CodeTokenKind)
}
