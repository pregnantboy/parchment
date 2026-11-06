/// A change at a fixed point within one line, such as adding `## ` or removing an indent.
struct LineOperation {
    var line: MarkdownRange
    /// Offset from the start of the line.
    var offset: Int
    var deleteCount: Int
    var insert: String

    var start: Int { line.location + offset }

    /// Combines operations on separate lines into one edit, mapping the selection through them.
    static func edit(applying operations: [LineOperation], to text: MarkdownText, selection: MarkdownRange) -> TextEdit? {
        guard let first = operations.first, let last = operations.last else { return nil }
        let blockStart = first.line.location
        let blockEnd = last.line.upperBound

        var replacement: [UInt16] = []
        var cursor = blockStart
        for operation in operations {
            replacement.append(contentsOf: text.units[cursor..<operation.start])
            replacement.append(contentsOf: operation.insert.utf16)
            cursor = operation.start + operation.deleteCount
        }
        replacement.append(contentsOf: text.units[cursor..<blockEnd])

        func map(_ position: Int) -> Int {
            var delta = 0
            for operation in operations {
                let insertLength = operation.insert.utf16.count
                if position < operation.start { break }
                if position < operation.start + operation.deleteCount {
                    return operation.start + delta + insertLength
                }
                delta += insertLength - operation.deleteCount
            }
            return position + delta
        }

        let lower = map(selection.location)
        let upper = map(selection.upperBound)
        return TextEdit(
            range: MarkdownRange(blockStart..<blockEnd),
            replacement: String(decoding: replacement, as: UTF16.self),
            selection: MarkdownRange(location: lower, length: max(0, upper - lower))
        )
    }
}
