/// A styled stretch of text produced by the parser.
public struct MarkdownSpan: Hashable, Sendable {
    public var kind: SpanKind
    public var range: TextRange

    public init(_ kind: SpanKind, _ range: TextRange) {
        self.kind = kind
        self.range = range
    }
}
