/// An open fenced code block, remembered while the parser walks through its lines.
struct Fence: Hashable, Sendable {
    var marker: UInt16
    var length: Int
    var language: String

    /// Reads an opening fence such as ```` ```swift ```` or `~~~`.
    static func opening(in text: MarkdownText, line: MarkdownRange) -> Fence? {
        let end = line.upperBound
        var index = line.location
        while index < end, index - line.location <= 3, text[index] == Unit.space {
            index += 1
        }
        guard index < end, index - line.location <= 3 else { return nil }
        let marker = text[index]
        guard marker == Unit.backtick || marker == Unit.tilde else { return nil }

        let runStart = index
        while index < end, text[index] == marker {
            index += 1
        }
        let length = index - runStart
        guard length >= 3 else { return nil }

        // Backtick fences cannot contain backticks in their info string.
        if marker == Unit.backtick, text.units[index..<end].contains(Unit.backtick) {
            return nil
        }
        while index < end, text[index] == Unit.space || text[index] == Unit.tab {
            index += 1
        }
        var infoEnd = index
        while infoEnd < end, text[infoEnd] != Unit.space, text[infoEnd] != Unit.tab, text[infoEnd] != Unit.openBrace {
            infoEnd += 1
        }
        let language = text.string(in: MarkdownRange(index..<infoEnd)).lowercased()
        return Fence(marker: marker, length: length, language: language)
    }

    /// True when `line` closes this fence: the same marker, at least as long, and nothing after it.
    func isClosed(by text: MarkdownText, line: MarkdownRange) -> Bool {
        let end = line.upperBound
        var index = line.location
        while index < end, index - line.location <= 3, text[index] == Unit.space {
            index += 1
        }
        guard index - line.location <= 3 else { return false }
        let runStart = index
        while index < end, text[index] == marker {
            index += 1
        }
        guard index - runStart >= length else { return false }
        while index < end {
            if text[index] != Unit.space && text[index] != Unit.tab { return false }
            index += 1
        }
        return true
    }
}
