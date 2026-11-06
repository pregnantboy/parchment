/// A styled stretch of text produced by the parser.
public struct MarkdownSpan: Hashable, Sendable {
    public var kind: SpanKind
    public var range: MarkdownRange

    public init(_ kind: SpanKind, _ range: MarkdownRange) {
        self.kind = kind
        self.range = range
    }
}
