/// An immutable snapshot of a document as UTF-16 code units.
///
/// Working in UTF-16 keeps every offset compatible with `NSString` and `NSTextStorage`,
/// and indexing an array is far faster than walking `String.Index` values.
public struct MarkdownText: Sendable, Equatable {
    public let units: [UInt16]

    public init(_ string: String) {
        units = Array(string.utf16)
    }

    public init(units: [UInt16]) {
        self.units = units
    }

    public var length: Int { units.count }

    public subscript(index: Int) -> UInt16 { units[index] }

    /// The unit at `index`, or `nil` when the index is out of bounds.
    public func unit(at index: Int) -> UInt16? {
        index >= 0 && index < units.count ? units[index] : nil
    }

    public func string(in range: TextRange) -> String {
        String(decoding: units[range.location..<range.upperBound], as: UTF16.self)
    }

    /// Returns true when the text at `index` starts with `literal` (ASCII only).
    public func matches(_ literal: String, at index: Int) -> Bool {
        var position = index
        for unit in literal.utf16 {
            guard position < units.count, units[position] == unit else { return false }
            position += 1
        }
        return true
    }

    /// The range of the line containing `index`, excluding its line break.
    public func lineRange(containing index: Int) -> TextRange {
        var start = min(max(index, 0), units.count)
        while start > 0, units[start - 1] != Unit.newline {
            start -= 1
        }
        var end = min(max(index, 0), units.count)
        while end < units.count, units[end] != Unit.newline {
            end += 1
        }
        if end > start, units[end - 1] == Unit.carriageReturn {
            end -= 1
        }
        return TextRange(location: start, length: end - start)
    }

    /// The ranges of every line touched by `selection`, excluding line breaks.
    ///
    /// A selection that ends exactly at the start of a line does not include that line,
    /// matching how editors treat a fully selected line.
    public func lineRanges(touching selection: TextRange) -> [TextRange] {
        var end = selection.upperBound
        if selection.length > 0, unit(at: end - 1) == Unit.newline {
            end -= 1
        }
        var ranges: [TextRange] = []
        var line = lineRange(containing: selection.location)
        while true {
            ranges.append(line)
            guard selection.length > 0, let next = nextLineStart(after: line), next <= end else { break }
            line = lineRange(containing: next)
        }
        return ranges
    }

    private func nextLineStart(after line: TextRange) -> Int? {
        var index = line.upperBound
        if index < units.count, units[index] == Unit.carriageReturn { index += 1 }
        guard index < units.count, units[index] == Unit.newline else { return nil }
        return index + 1
    }
}
