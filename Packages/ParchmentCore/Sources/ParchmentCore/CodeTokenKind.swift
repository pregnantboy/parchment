/// Syntax-highlighting categories for code inside fenced blocks.
public enum CodeTokenKind: Hashable, Sendable {
    case keyword
    case string
    case comment
    case number
    case type
}
