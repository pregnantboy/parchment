/// Tokenizes one line of code for syntax colouring.
///
/// Highlighting is per line: a block comment or string that spans lines is only coloured on
/// the line where it starts. That trade-off keeps restyling instant while typing.
enum CodeHighlighter {
    static func highlight(_ text: MarkdownText, range: TextRange, language name: String, into spans: inout [MarkdownSpan]) {
        let language = CodeLanguage.named(name)
        if language.isMarkup {
            highlightMarkup(text, range: range, language: language, into: &spans)
            return
        }

        let end = range.upperBound
        var index = range.location
        while index < end {
            let unit = text[index]

            if let comment = language.lineComments.first(where: { text.matches($0, at: index) }),
               startsComment(comment, text: text, at: index, lineStart: range.location, end: end, language: language) {
                spans.append(MarkdownSpan(.codeToken(.comment), TextRange(index..<end)))
                return
            }

            if let block = language.blockComment, text.matches(block.open, at: index) {
                let closeStart = find(block.close, in: text, from: index + block.open.utf16.count, to: end)
                let commentEnd = closeStart.map { $0 + block.close.utf16.count } ?? end
                spans.append(MarkdownSpan(.codeToken(.comment), TextRange(index..<commentEnd)))
                index = commentEnd
                continue
            }

            if language.stringDelimiters.contains(unit) {
                let stringEnd = endOfString(text, delimiter: unit, from: index + 1, to: end)
                spans.append(MarkdownSpan(.codeToken(.string), TextRange(index..<stringEnd)))
                index = stringEnd
                continue
            }

            if Unit.isDigit(unit), index == range.location || !Unit.isIdentifierPart(text[index - 1]) {
                var numberEnd = index + 1
                while numberEnd < end, Unit.isIdentifierPart(text[numberEnd]) || text[numberEnd] == Unit.period {
                    // Stop at a range operator such as `0..<10`.
                    if text[numberEnd] == Unit.period, numberEnd + 1 < end, text[numberEnd + 1] == Unit.period { break }
                    numberEnd += 1
                }
                spans.append(MarkdownSpan(.codeToken(.number), TextRange(index..<numberEnd)))
                index = numberEnd
                continue
            }

            if Unit.isIdentifierStart(unit) || unit == Unit.hash {
                var wordEnd = index + 1
                while wordEnd < end, Unit.isIdentifierPart(text[wordEnd]) { wordEnd += 1 }
                let wordRange = TextRange(index..<wordEnd)
                let word = text.string(in: wordRange)
                if language.keywords.contains(word) {
                    spans.append(MarkdownSpan(.codeToken(.keyword), wordRange))
                } else if language.highlightsTypes, Unit.isUppercaseASCII(unit), wordRange.length > 1 {
                    spans.append(MarkdownSpan(.codeToken(.type), wordRange))
                }
                index = wordEnd
                continue
            }

            index += 1
        }
    }

    /// `#` only starts a comment at the start of a word, so `$#` or `a#b` in shell stay code,
    /// and C preprocessor lines like `#include` stay keywords.
    private static func startsComment(_ marker: String, text: MarkdownText, at index: Int, lineStart: Int, end: Int, language: CodeLanguage) -> Bool {
        guard marker == "#" else { return true }
        if index > lineStart, !Unit.isWhitespace(text[index - 1]) { return false }
        var wordEnd = index + 1
        while wordEnd < end, Unit.isIdentifierPart(text[wordEnd]) { wordEnd += 1 }
        let directive = text.string(in: TextRange(index..<wordEnd))
        return !language.keywords.contains(directive)
    }

    private static func endOfString(_ text: MarkdownText, delimiter: UInt16, from start: Int, to end: Int) -> Int {
        var index = start
        while index < end {
            let unit = text[index]
            if unit == Unit.backslash {
                index += 2
                continue
            }
            if unit == delimiter { return index + 1 }
            index += 1
        }
        return end
    }

    private static func find(_ literal: String, in text: MarkdownText, from start: Int, to end: Int) -> Int? {
        var index = start
        while index < end {
            if text.matches(literal, at: index) { return index }
            index += 1
        }
        return nil
    }

    /// Colours tag names as keywords, attribute values as strings, and `<!-- -->` as comments.
    private static func highlightMarkup(_ text: MarkdownText, range: TextRange, language: CodeLanguage, into spans: inout [MarkdownSpan]) {
        let end = range.upperBound
        var index = range.location
        var insideTag = false
        while index < end {
            let unit = text[index]
            if text.matches("<!--", at: index) {
                let close = find("-->", in: text, from: index + 4, to: end)
                let commentEnd = close.map { $0 + 3 } ?? end
                spans.append(MarkdownSpan(.codeToken(.comment), TextRange(index..<commentEnd)))
                index = commentEnd
                continue
            }
            if unit == Unit.lessThan {
                insideTag = true
                var nameStart = index + 1
                if nameStart < end, text[nameStart] == Unit.slash || text[nameStart] == Unit.question || text[nameStart] == Unit.exclamation {
                    nameStart += 1
                }
                var nameEnd = nameStart
                while nameEnd < end, Unit.isIdentifierPart(text[nameEnd]) || text[nameEnd] == Unit.hyphen || text[nameEnd] == Unit.colon {
                    nameEnd += 1
                }
                if nameEnd > nameStart {
                    spans.append(MarkdownSpan(.codeToken(.keyword), TextRange(nameStart..<nameEnd)))
                }
                index = nameEnd
                continue
            }
            if unit == Unit.greaterThan {
                insideTag = false
            } else if insideTag, language.stringDelimiters.contains(unit) {
                let stringEnd = endOfString(text, delimiter: unit, from: index + 1, to: end)
                spans.append(MarkdownSpan(.codeToken(.string), TextRange(index..<stringEnd)))
                index = stringEnd
                continue
            } else if insideTag, Unit.isASCIILetter(unit) {
                var nameEnd = index + 1
                while nameEnd < end, Unit.isIdentifierPart(text[nameEnd]) || text[nameEnd] == Unit.hyphen { nameEnd += 1 }
                spans.append(MarkdownSpan(.codeToken(.type), TextRange(index..<nameEnd)))
                index = nameEnd
                continue
            }
            index += 1
        }
    }
}
