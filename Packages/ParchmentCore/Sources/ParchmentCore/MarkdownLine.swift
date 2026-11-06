/// One classified line of a Markdown document.
public struct MarkdownLine: Hashable, Sendable {
    /// The line's text, excluding its line break.
    public var range: TextRange
    /// 0 for the last line without a break, 1 for `\n`, 2 for `\r\n`.
    public var lineBreakLength: Int
    public var kind: LineKind
    /// Where inline content starts, after any block syntax such as `## ` or `- [ ] `.
    public var contentStart: Int
    public var blockPosition: BlockPosition

    public init(range: TextRange, lineBreakLength: Int, kind: LineKind, contentStart: Int, blockPosition: BlockPosition = .none) {
        self.range = range
        self.lineBreakLength = lineBreakLength
        self.kind = kind
        self.contentStart = contentStart
        self.blockPosition = blockPosition
    }

    /// The line including its line break, which is what paragraph attributes must cover.
    public var fullRange: TextRange {
        TextRange(location: range.location, length: range.length + lineBreakLength)
    }

    /// The text after the block syntax.
    public var contentRange: TextRange {
        TextRange(location: contentStart, length: max(0, range.upperBound - contentStart))
    }

    /// The block syntax at the start of the line, including any indentation.
    public var prefixRange: TextRange {
        TextRange(location: range.location, length: max(0, contentStart - range.location))
    }
}
