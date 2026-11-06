/// Bracket and backtick pairing while typing.
public enum AutoPair {
    private static let pairs: [UInt16: UInt16] = [
        Unit.openParen: Unit.closeParen,
        Unit.openBracket: Unit.closeBracket,
        Unit.openBrace: Unit.closeBrace,
        Unit.backtick: Unit.backtick,
    ]

    /// Characters that wrap a selection instead of replacing it.
    private static let wrappers: [UInt16: UInt16] = [
        Unit.openParen: Unit.closeParen,
        Unit.openBracket: Unit.closeBracket,
        Unit.openBrace: Unit.closeBrace,
        Unit.backtick: Unit.backtick,
        Unit.asterisk: Unit.asterisk,
        Unit.underscore: Unit.underscore,
        Unit.tilde: Unit.tilde,
        Unit.quote: Unit.quote,
    ]

    private static let closers: Set<UInt16> = [Unit.closeParen, Unit.closeBracket, Unit.closeBrace, Unit.backtick]

    /// The edit for typing `typed`, or `nil` to insert it normally.
    public static func insert(_ typed: String, in text: MarkdownText, selection: MarkdownRange) -> TextEdit? {
        let typedUnits = Array(typed.utf16)
        guard typedUnits.count == 1, let unit = typedUnits.first else { return nil }

        if !selection.isEmpty {
            guard let close = wrappers[unit] else { return nil }
            let closing = String(decoding: [close], as: UTF16.self)
            let inner = text.string(in: selection)
            return TextEdit(
                range: selection,
                replacement: typed + inner + closing,
                selection: MarkdownRange(location: selection.location + 1, length: selection.length)
            )
        }

        let caret = selection.location
        let next = text.unit(at: caret)
        let previous = text.unit(at: caret - 1)

        // Type over a closer that is already there.
        if closers.contains(unit), next == unit {
            return TextEdit(range: MarkdownRange(location: caret, length: 1), replacement: typed, selection: MarkdownRange(location: caret + 1, length: 0))
        }

        guard let close = pairs[unit] else { return nil }
        let nextAllowsPair = next == nil || Unit.isWhitespace(next) || closers.contains(next ?? 0)
        guard nextAllowsPair else { return nil }
        if unit == Unit.backtick {
            // Let ``` for code fences type naturally, and don't pair in the middle of a word.
            if previous == Unit.backtick || Unit.isAlphanumeric(previous) { return nil }
        }

        let replacement = typed + String(decoding: [close], as: UTF16.self)
        return TextEdit(range: selection, replacement: replacement, selection: MarkdownRange(location: caret + 1, length: 0))
    }

    /// Deletes both halves of an empty pair, like `(|)`, on Backspace.
    public static func deleteBackward(in text: MarkdownText, selection: MarkdownRange) -> TextEdit? {
        guard selection.isEmpty, selection.location > 0,
              let previous = text.unit(at: selection.location - 1),
              let next = text.unit(at: selection.location),
              let close = pairs[previous], close == next else { return nil }
        return TextEdit(
            range: MarkdownRange(location: selection.location - 1, length: 2),
            replacement: "",
            selection: MarkdownRange(location: selection.location - 1, length: 0)
        )
    }
}
