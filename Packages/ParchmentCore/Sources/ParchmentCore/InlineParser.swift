/// Finds inline Markdown inside one line: code spans, links, autolinks, escapes and emphasis.
///
/// It follows CommonMark closely enough for styling, without building a syntax tree.
/// Emphasis never crosses a line, which keeps restyling local to the edited line.
enum InlineParser {
    static func parse(_ text: MarkdownText, range: TextRange, into spans: inout [MarkdownSpan]) {
        guard !range.isEmpty else { return }
        // Positions claimed by code spans, escapes, and link destinations.
        var claimed = [Bool](repeating: false, count: range.length)

        parseCodeAndEscapes(text, range: range, claimed: &claimed, spans: &spans)
        parseLinks(text, range: range, claimed: &claimed, spans: &spans)
        parseBareURLs(text, range: range, claimed: &claimed, spans: &spans)
        parseEmphasis(text, range: range, claimed: claimed, spans: &spans)
    }

    // MARK: - Code spans and escapes

    private static func parseCodeAndEscapes(_ text: MarkdownText, range: TextRange, claimed: inout [Bool], spans: inout [MarkdownSpan]) {
        let start = range.location
        let end = range.upperBound
        var index = start
        while index < end {
            let unit = text[index]
            if unit == Unit.backslash, index + 1 < end, Unit.isASCIIPunctuation(text[index + 1]) {
                spans.append(MarkdownSpan(.syntax, TextRange(location: index, length: 1)))
                claimed[index - start] = true
                claimed[index + 1 - start] = true
                index += 2
                continue
            }
            if unit == Unit.backtick {
                let runStart = index
                while index < end, text[index] == Unit.backtick { index += 1 }
                let runLength = index - runStart
                guard let close = closingBacktickRun(text, length: runLength, from: index, to: end) else {
                    continue
                }
                spans.append(MarkdownSpan(.syntax, TextRange(location: runStart, length: runLength)))
                if close > index {
                    spans.append(MarkdownSpan(.code, TextRange(index..<close)))
                }
                spans.append(MarkdownSpan(.syntax, TextRange(location: close, length: runLength)))
                for position in runStart..<(close + runLength) {
                    claimed[position - start] = true
                }
                index = close + runLength
                continue
            }
            index += 1
        }
    }

    private static func closingBacktickRun(_ text: MarkdownText, length: Int, from start: Int, to end: Int) -> Int? {
        var index = start
        while index < end {
            if text[index] == Unit.backtick {
                let runStart = index
                while index < end, text[index] == Unit.backtick { index += 1 }
                if index - runStart == length { return runStart }
            } else {
                index += 1
            }
        }
        return nil
    }

    // MARK: - Links

    private static func parseLinks(_ text: MarkdownText, range: TextRange, claimed: inout [Bool], spans: inout [MarkdownSpan]) {
        let start = range.location
        let end = range.upperBound
        var index = start
        while index < end {
            let unit = text[index]
            guard !claimed[index - start] else {
                index += 1
                continue
            }

            if unit == Unit.lessThan, let close = autolinkEnd(text, from: index, to: end, claimed: claimed, base: start) {
                let destination = TextRange((index + 1)..<close)
                let url = text.string(in: destination)
                spans.append(MarkdownSpan(.syntax, TextRange(location: index, length: 1)))
                spans.append(MarkdownSpan(.linkText(destination: url), destination))
                spans.append(MarkdownSpan(.syntax, TextRange(location: close, length: 1)))
                for position in index...close { claimed[position - start] = true }
                index = close + 1
                continue
            }

            guard unit == Unit.openBracket,
                  let textEnd = matchingBracket(text, from: index, to: end, claimed: claimed, base: start),
                  textEnd + 1 < end, text[textEnd + 1] == Unit.openParen,
                  let destinationEnd = matchingParen(text, from: textEnd + 1, to: end) else {
                index += 1
                continue
            }

            let isImage = index > start && text[index - 1] == Unit.exclamation && !claimed[index - 1 - start]
            let openerStart = isImage ? index - 1 : index
            let destinationRange = trimmedDestination(text, from: textEnd + 2, to: destinationEnd)
            let destination = text.string(in: destinationRange)

            spans.append(MarkdownSpan(.syntax, TextRange(openerStart..<(index + 1))))
            if textEnd > index + 1 {
                spans.append(MarkdownSpan(.linkText(destination: destination), TextRange((index + 1)..<textEnd)))
            }
            spans.append(MarkdownSpan(.syntax, TextRange(location: textEnd, length: 2)))
            if !destinationRange.isEmpty {
                spans.append(MarkdownSpan(.linkDestination(destination: destination), TextRange((textEnd + 2)..<destinationEnd)))
            }
            spans.append(MarkdownSpan(.syntax, TextRange(location: destinationEnd, length: 1)))

            for position in openerStart...index { claimed[position - start] = true }
            for position in textEnd...destinationEnd { claimed[position - start] = true }
            index = destinationEnd + 1
        }
    }

    private static func matchingBracket(_ text: MarkdownText, from open: Int, to end: Int, claimed: [Bool], base: Int) -> Int? {
        var depth = 0
        var index = open
        while index < end {
            if !claimed[index - base] {
                if text[index] == Unit.openBracket { depth += 1 }
                if text[index] == Unit.closeBracket {
                    depth -= 1
                    if depth == 0 { return index }
                }
            }
            index += 1
        }
        return nil
    }

    private static func matchingParen(_ text: MarkdownText, from open: Int, to end: Int) -> Int? {
        var depth = 0
        var index = open
        while index < end {
            let unit = text[index]
            if unit == Unit.backslash {
                index += 2
                continue
            }
            if unit == Unit.openParen { depth += 1 }
            if unit == Unit.closeParen {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return nil
    }

    /// The URL part of a link destination, without surrounding spaces, angle brackets, or title.
    private static func trimmedDestination(_ text: MarkdownText, from start: Int, to end: Int) -> TextRange {
        var lower = start
        while lower < end, text[lower] == Unit.space { lower += 1 }
        if lower < end, text[lower] == Unit.lessThan {
            var upper = lower + 1
            while upper < end, text[upper] != Unit.greaterThan { upper += 1 }
            return TextRange((lower + 1)..<upper)
        }
        var upper = lower
        while upper < end, text[upper] != Unit.space { upper += 1 }
        return TextRange(lower..<upper)
    }

    /// Matches `<scheme:...>` or `<name@example.com>` and returns the index of `>`.
    private static func autolinkEnd(_ text: MarkdownText, from open: Int, to end: Int, claimed: [Bool], base: Int) -> Int? {
        var index = open + 1
        var sawSeparator = false
        while index < end {
            let unit = text[index]
            if unit == Unit.greaterThan {
                return sawSeparator && index > open + 1 ? index : nil
            }
            if Unit.isWhitespace(unit) || unit == Unit.lessThan || claimed[index - base] { return nil }
            if unit == Unit.colon || unit == Unit.at { sawSeparator = true }
            index += 1
        }
        return nil
    }

    // MARK: - Bare URLs

    private static func parseBareURLs(_ text: MarkdownText, range: TextRange, claimed: inout [Bool], spans: inout [MarkdownSpan]) {
        let start = range.location
        let end = range.upperBound
        var index = start
        while index < end {
            guard !claimed[index - start],
                  text[index] == Unit.lowerH,
                  index == start || !Unit.isAlphanumeric(text[index - 1]),
                  text.matches("http://", at: index) || text.matches("https://", at: index) else {
                index += 1
                continue
            }
            var urlEnd = index
            while urlEnd < end, !Unit.isWhitespace(text[urlEnd]), text[urlEnd] != Unit.lessThan, !claimed[urlEnd - start] {
                urlEnd += 1
            }
            // Leave trailing punctuation, like a sentence's full stop, outside the link.
            while urlEnd > index, isTrailingURLPunctuation(text[urlEnd - 1]) {
                urlEnd -= 1
            }
            let urlRange = TextRange(index..<urlEnd)
            guard urlRange.length > 8 else {
                index = max(urlEnd, index + 1)
                continue
            }
            spans.append(MarkdownSpan(.linkText(destination: text.string(in: urlRange)), urlRange))
            for position in urlRange.range { claimed[position - start] = true }
            index = urlEnd
        }
    }

    private static func isTrailingURLPunctuation(_ unit: UInt16) -> Bool {
        unit == Unit.period || unit == Unit.comma || unit == Unit.colon || unit == Unit.semicolon
            || unit == Unit.exclamation || unit == Unit.question || unit == Unit.closeParen
            || unit == Unit.quote || unit == Unit.apostrophe || unit == Unit.asterisk || unit == Unit.underscore
    }

    // MARK: - Emphasis

    private struct Delimiter {
        var position: Int
        var length: Int
        var unit: UInt16
        var canOpen: Bool
        var canClose: Bool
        /// Delimiter characters not yet matched. Openers lose characters from their end, closers from their start.
        var remaining: Int
    }

    private static func parseEmphasis(_ text: MarkdownText, range: TextRange, claimed: [Bool], spans: inout [MarkdownSpan]) {
        let start = range.location
        let end = range.upperBound
        var openers: [Delimiter] = []
        var index = start

        while index < end {
            let unit = text[index]
            guard !claimed[index - start], unit == Unit.asterisk || unit == Unit.underscore || unit == Unit.tilde else {
                index += 1
                continue
            }
            let runStart = index
            while index < end, text[index] == unit, !claimed[index - start] { index += 1 }
            let runLength = index - runStart

            let before = runStart > start ? text[runStart - 1] : nil
            let after = index < end ? text[index] : nil
            var canOpen = !Unit.isWhitespace(after)
            var canClose = !Unit.isWhitespace(before)
            if unit == Unit.underscore {
                // Underscores inside words, like snake_case, are not emphasis.
                canOpen = canOpen && !Unit.isAlphanumeric(before)
                canClose = canClose && !Unit.isAlphanumeric(after)
            }
            if unit == Unit.tilde, runLength < 2 {
                continue
            }

            var closer = Delimiter(position: runStart, length: runLength, unit: unit, canOpen: canOpen, canClose: canClose, remaining: runLength)
            if closer.canClose {
                matchCloser(&closer, openers: &openers, spans: &spans)
            }
            if closer.remaining > 0, closer.canOpen {
                // Whatever is left over can still open later emphasis.
                let used = closer.length - closer.remaining
                closer.position += used
                closer.length = closer.remaining
                openers.append(closer)
            }
        }
    }

    private static func matchCloser(_ closer: inout Delimiter, openers: inout [Delimiter], spans: inout [MarkdownSpan]) {
        while closer.remaining > 0 {
            guard let openerIndex = openers.lastIndex(where: { $0.unit == closer.unit && $0.remaining > 0 }) else { return }
            var opener = openers[openerIndex]

            let use: Int
            if closer.unit == Unit.tilde {
                guard opener.remaining >= 2, closer.remaining >= 2 else { return }
                use = 2
            } else {
                use = min(2, opener.remaining, closer.remaining)
            }

            let openerMarker = TextRange(location: opener.position + opener.remaining - use, length: use)
            let closerMarker = TextRange(location: closer.position + (closer.length - closer.remaining), length: use)
            let content = TextRange(openerMarker.upperBound..<closerMarker.location)

            let kind: SpanKind
            if closer.unit == Unit.tilde {
                kind = .strikethrough
            } else {
                kind = use == 2 ? .strong : .emphasis
            }
            spans.append(MarkdownSpan(.syntax, openerMarker))
            spans.append(MarkdownSpan(.syntax, closerMarker))
            if !content.isEmpty {
                spans.append(MarkdownSpan(kind, content))
            }

            opener.remaining -= use
            closer.remaining -= use
            // Openers between this pair can no longer match anything.
            openers.removeSubrange((openerIndex + 1)...)
            if opener.remaining == 0 {
                openers.remove(at: openerIndex)
            } else {
                openers[openerIndex] = opener
            }
        }
    }
}
