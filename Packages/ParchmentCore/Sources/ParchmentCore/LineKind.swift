/// The block-level role of one line of Markdown.
public enum LineKind: Hashable, Sendable {
    case blank
    case paragraph
    case heading(level: Int)
    /// A ``` or ~~~ line. `language` is the opening fence's info string, lowercased.
    case fence(language: String, isOpening: Bool)
    /// A line inside a fenced code block.
    case code(language: String)
    case quote
    case listItem(isOrdered: Bool)
    case task(isChecked: Bool)
    case rule
    case tableHeader
    case tableDelimiter
    case tableRow
    /// A line holding nothing but an image, such as `![alt](photo.png)`.
    case image(source: String)

    public var isCodeBlock: Bool {
        switch self {
        case .fence, .code: true
        default: false
        }
    }

    public var isTable: Bool {
        switch self {
        case .tableHeader, .tableDelimiter, .tableRow: true
        default: false
        }
    }

    public var isListLike: Bool {
        switch self {
        case .listItem, .task: true
        default: false
        }
    }
}
