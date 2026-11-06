/// The block syntax at the start of a list item, task, or quote line.
public struct ListPrefix: Hashable, Sendable {
    public enum Marker: Hashable, Sendable {
        case bullet(UInt16)
        case ordered(number: Int, delimiter: UInt16)
        case quote
    }

    /// The whitespace before the marker.
    public var indent: MarkdownRange
    public var marker: Marker
    /// The marker and the spaces after it, such as `- ` or `12. `.
    public var markerRange: MarkdownRange
    /// The `[ ]` or `[x]` of a task item.
    public var taskBox: MarkdownRange?
    public var isChecked: Bool
    /// Where the item's own text starts.
    public var contentStart: Int

    public var isTask: Bool { taskBox != nil }

    /// The marker the next item should use, without indentation.
    public var continuation: String {
        switch marker {
        case .bullet(let unit):
            let bullet = String(decoding: [unit], as: UTF16.self)
            return isTask ? "\(bullet) [ ] " : "\(bullet) "
        case .ordered(let number, let delimiter):
            let suffix = String(decoding: [delimiter], as: UTF16.self)
            return isTask ? "\(number + 1)\(suffix) [ ] " : "\(number + 1)\(suffix) "
        case .quote:
            return "> "
        }
    }

    /// Reads the list or quote syntax at the start of `line`, if there is any.
    public static func parse(_ text: MarkdownText, line: MarkdownRange) -> ListPrefix? {
        let end = line.upperBound
        var index = line.location
        while index < end, text[index] == Unit.space || text[index] == Unit.tab {
            index += 1
        }
        guard index < end else { return nil }
        let indent = MarkdownRange(location: line.location, length: index - line.location)
        let first = text[index]

        if first == Unit.greaterThan {
            guard indent.length <= 3 else { return nil }
            var contentStart = index + 1
            if contentStart < end, text[contentStart] == Unit.space { contentStart += 1 }
            return ListPrefix(
                indent: indent,
                marker: .quote,
                markerRange: MarkdownRange(location: index, length: contentStart - index),
                taskBox: nil,
                isChecked: false,
                contentStart: contentStart
            )
        }

        var marker: Marker
        var afterMarker: Int
        if first == Unit.hyphen || first == Unit.asterisk || first == Unit.plus {
            marker = .bullet(first)
            afterMarker = index + 1
        } else if Unit.isDigit(first) {
            var digitEnd = index
            while digitEnd < end, digitEnd - index < 9, Unit.isDigit(text[digitEnd]) {
                digitEnd += 1
            }
            guard digitEnd < end, text[digitEnd] == Unit.period || text[digitEnd] == Unit.closeParen else { return nil }
            let digits = String(decoding: text.units[index..<digitEnd], as: UTF16.self)
            marker = .ordered(number: Int(digits) ?? 1, delimiter: text[digitEnd])
            afterMarker = digitEnd + 1
        } else {
            return nil
        }

        // A marker must be followed by whitespace to start a list item.
        guard afterMarker < end, text[afterMarker] == Unit.space || text[afterMarker] == Unit.tab else { return nil }
        var contentStart = afterMarker
        while contentStart < end, contentStart - afterMarker < 4, text[contentStart] == Unit.space || text[contentStart] == Unit.tab {
            contentStart += 1
        }
        let markerRange = MarkdownRange(location: index, length: contentStart - index)

        var taskBox: MarkdownRange?
        var isChecked = false
        if contentStart + 2 < end,
           text[contentStart] == Unit.openBracket,
           text[contentStart + 2] == Unit.closeBracket {
            let mark = text[contentStart + 1]
            let afterBox = contentStart + 3
            let boxIsTerminated = afterBox >= end || text[afterBox] == Unit.space || text[afterBox] == Unit.tab
            if boxIsTerminated, mark == Unit.space || mark == Unit.lowerX || mark == Unit.upperX {
                taskBox = MarkdownRange(location: contentStart, length: 3)
                isChecked = mark != Unit.space
                contentStart = afterBox
                while contentStart < end, text[contentStart] == Unit.space || text[contentStart] == Unit.tab {
                    contentStart += 1
                }
            }
        }

        return ListPrefix(
            indent: indent,
            marker: marker,
            markerRange: markerRange,
            taskBox: taskBox,
            isChecked: isChecked,
            contentStart: contentStart
        )
    }
}
