/// Splits a document into classified lines and finds the inline spans inside each one.
///
/// The parser is deliberately line-oriented, like the editors it takes after (Bear, iA Writer):
/// a line's style depends only on its own text plus the fenced-code and table context around it.
/// That keeps parsing linear and lets the editor restyle only the lines that changed.
public enum MarkdownParser {
    /// Classifies every line of `text`.
    public static func lines(in text: MarkdownText) -> [MarkdownLine] {
        var result: [MarkdownLine] = []
        result.reserveCapacity(text.length / 32 + 1)

        var openFence: Fence?
        var lineStart = 0
        let count = text.length

        while lineStart <= count {
            var lineEnd = lineStart
            while lineEnd < count, text[lineEnd] != Unit.newline {
                lineEnd += 1
            }
            let hasNewline = lineEnd < count
            var contentEnd = lineEnd
            var breakLength = hasNewline ? 1 : 0
            if contentEnd > lineStart, text[contentEnd - 1] == Unit.carriageReturn {
                contentEnd -= 1
                breakLength += 1
            }
            let range = MarkdownRange(location: lineStart, length: contentEnd - lineStart)

            if let fence = openFence {
                if fence.isClosed(by: text, line: range) {
                    result.append(MarkdownLine(range: range, lineBreakLength: breakLength, kind: .fence(language: fence.language, isOpening: false), contentStart: range.upperBound))
                    openFence = nil
                } else {
                    result.append(MarkdownLine(range: range, lineBreakLength: breakLength, kind: .code(language: fence.language), contentStart: range.location))
                }
            } else if let fence = Fence.opening(in: text, line: range) {
                openFence = fence
                result.append(MarkdownLine(range: range, lineBreakLength: breakLength, kind: .fence(language: fence.language, isOpening: true), contentStart: range.upperBound))
            } else {
                let (kind, contentStart) = classify(text, line: range)
                result.append(MarkdownLine(range: range, lineBreakLength: breakLength, kind: kind, contentStart: contentStart))
            }

            if !hasNewline { break }
            lineStart = lineEnd + 1
        }

        markTables(in: &result, text: text)
        markContinuations(in: &result)
        assignBlockPositions(in: &result)
        return result
    }

    /// The inline spans of one line, in no particular order.
    public static func spans(for line: MarkdownLine, in text: MarkdownText) -> [MarkdownSpan] {
        var spans: [MarkdownSpan] = []
        switch line.kind {
        case .blank:
            break

        case .paragraph:
            InlineParser.parse(text, range: line.contentRange, into: &spans)

        case .heading:
            spans.append(MarkdownSpan(.syntax, line.prefixRange))
            var contentEnd = line.range.upperBound
            // Optional closing hashes, as in `## Title ##`.
            var index = contentEnd
            while index > line.contentStart, text[index - 1] == Unit.space { index -= 1 }
            let hashesEnd = index
            while index > line.contentStart, text[index - 1] == Unit.hash { index -= 1 }
            if index < hashesEnd, index > line.contentStart, text[index - 1] == Unit.space {
                spans.append(MarkdownSpan(.syntax, MarkdownRange(index..<hashesEnd)))
                contentEnd = index
            }
            InlineParser.parse(text, range: MarkdownRange(line.contentStart..<max(line.contentStart, contentEnd)), into: &spans)

        case .fence, .rule, .tableDelimiter, .image:
            if !line.range.isEmpty {
                spans.append(MarkdownSpan(.syntax, line.range))
            }

        case .code(let language):
            CodeHighlighter.highlight(text, range: line.range, language: language, into: &spans)

        case .quote:
            spans.append(MarkdownSpan(.quoteMarker, line.prefixRange))
            InlineParser.parse(text, range: line.contentRange, into: &spans)

        case .listItem:
            if let prefix = ListPrefix.parse(text, line: line.range) {
                spans.append(MarkdownSpan(.listMarker, prefix.markerRange))
            }
            InlineParser.parse(text, range: line.contentRange, into: &spans)

        case .task(let state):
            if let prefix = ListPrefix.parse(text, line: line.range), let box = prefix.taskBox {
                spans.append(MarkdownSpan(.listMarker, prefix.markerRange))
                spans.append(MarkdownSpan(.taskBox(state), box))
            }
            if state.isDone, !line.contentRange.isEmpty {
                spans.append(MarkdownSpan(.completedTask, line.contentRange))
            }
            InlineParser.parse(text, range: line.contentRange, into: &spans)

        case .tableHeader, .tableRow:
            if case .tableHeader = line.kind, !line.contentRange.isEmpty {
                spans.append(MarkdownSpan(.tableHeader, line.contentRange))
            }
            InlineParser.parse(text, range: line.contentRange, into: &spans)
            for index in line.range.range where text[index] == Unit.pipe {
                if index > line.range.location, text[index - 1] == Unit.backslash { continue }
                spans.append(MarkdownSpan(.syntax, MarkdownRange(location: index, length: 1)))
            }
        }
        return spans
    }

    // MARK: - Line classification

    private static func classify(_ text: MarkdownText, line: MarkdownRange) -> (LineKind, Int) {
        let end = line.upperBound
        var index = line.location
        var columns = 0
        while index < end, text[index] == Unit.space || text[index] == Unit.tab {
            columns += text[index] == Unit.tab ? 4 : 1
            index += 1
        }
        guard index < end else { return (.blank, end) }

        let first = text[index]
        if columns <= 3 {
            if first == Unit.hash, let heading = heading(text, at: index, end: end) {
                return heading
            }
            if isRule(text, from: index, to: end) {
                return (.rule, end)
            }
        }

        if let prefix = ListPrefix.parse(text, line: line) {
            switch prefix.marker {
            case .quote:
                return (.quote, prefix.contentStart)
            case .bullet:
                if prefix.isTask { return (.task(prefix.taskState), prefix.contentStart) }
                return (.listItem(isOrdered: false), prefix.contentStart)
            case .ordered:
                if prefix.isTask { return (.task(prefix.taskState), prefix.contentStart) }
                return (.listItem(isOrdered: true), prefix.contentStart)
            }
        }

        if first == Unit.exclamation, let source = imageSource(text, from: index, to: end) {
            return (.image(source: source), index)
        }

        return (.paragraph, index)
    }

    private static func heading(_ text: MarkdownText, at start: Int, end: Int) -> (LineKind, Int)? {
        var index = start
        while index < end, text[index] == Unit.hash {
            index += 1
        }
        let level = index - start
        guard level <= 6 else { return nil }
        guard index == end || text[index] == Unit.space || text[index] == Unit.tab else { return nil }
        while index < end, text[index] == Unit.space || text[index] == Unit.tab {
            index += 1
        }
        return (.heading(level: level), index)
    }

    private static func isRule(_ text: MarkdownText, from start: Int, to end: Int) -> Bool {
        let marker = text[start]
        guard marker == Unit.hyphen || marker == Unit.asterisk || marker == Unit.underscore else { return false }
        var count = 0
        for index in start..<end {
            let unit = text[index]
            if unit == marker {
                count += 1
            } else if unit != Unit.space && unit != Unit.tab {
                return false
            }
        }
        return count >= 3
    }

    /// Returns the image source when the line is exactly `![alt](source "optional title")`.
    private static func imageSource(_ text: MarkdownText, from start: Int, to lineEnd: Int) -> String? {
        var end = lineEnd
        while end > start, text[end - 1] == Unit.space || text[end - 1] == Unit.tab {
            end -= 1
        }
        guard end - start >= 5, text[start + 1] == Unit.openBracket, text[end - 1] == Unit.closeParen else { return nil }

        var index = start + 2
        var depth = 1
        while index < end {
            let unit = text[index]
            if unit == Unit.backslash {
                index += 2
                continue
            }
            if unit == Unit.openBracket { depth += 1 }
            if unit == Unit.closeBracket {
                depth -= 1
                if depth == 0 { break }
            }
            index += 1
        }
        guard index < end, depth == 0, index + 1 < end, text[index + 1] == Unit.openParen else { return nil }

        var sourceStart = index + 2
        let sourceLimit = end - 1
        while sourceStart < sourceLimit, text[sourceStart] == Unit.space { sourceStart += 1 }
        var sourceEnd = sourceStart
        if sourceStart < sourceLimit, text[sourceStart] == Unit.lessThan {
            sourceStart += 1
            sourceEnd = sourceStart
            while sourceEnd < sourceLimit, text[sourceEnd] != Unit.greaterThan { sourceEnd += 1 }
        } else {
            while sourceEnd < sourceLimit, text[sourceEnd] != Unit.space { sourceEnd += 1 }
        }
        guard sourceEnd > sourceStart else { return nil }
        return text.string(in: MarkdownRange(sourceStart..<sourceEnd))
    }

    // MARK: - Context passes

    /// Turns runs of paragraph lines into a table when the second line is a `---|---` delimiter.
    private static func markTables(in lines: inout [MarkdownLine], text: MarkdownText) {
        var index = 0
        while index + 1 < lines.count {
            guard lines[index].kind == .paragraph,
                  lines[index + 1].kind == .paragraph,
                  contains(Unit.pipe, in: lines[index].range, text: text),
                  isTableDelimiter(text, line: lines[index + 1].range) else {
                index += 1
                continue
            }
            lines[index].kind = .tableHeader
            lines[index].contentStart = lines[index].range.location
            lines[index + 1].kind = .tableDelimiter
            var row = index + 2
            while row < lines.count, lines[row].kind == .paragraph, contains(Unit.pipe, in: lines[row].range, text: text) {
                lines[row].kind = .tableRow
                lines[row].contentStart = lines[row].range.location
                row += 1
            }
            index = row
        }
    }

    private static func contains(_ unit: UInt16, in range: MarkdownRange, text: MarkdownText) -> Bool {
        range.range.contains { text[$0] == unit }
    }

    private static func isTableDelimiter(_ text: MarkdownText, line: MarkdownRange) -> Bool {
        var sawPipe = false
        var sawHyphen = false
        for index in line.range {
            switch text[index] {
            case Unit.pipe: sawPipe = true
            case Unit.hyphen: sawHyphen = true
            case Unit.colon, Unit.space, Unit.tab: break
            default: return false
            }
        }
        return sawPipe && sawHyphen
    }

    /// Marks the lines that carry on the paragraph above them. A plain line continues a
    /// paragraph, list item or quote; a quote line continues the quote. A blank line, an empty
    /// item, or any other kind of line ends the paragraph, as in CommonMark.
    private static func markContinuations(in lines: inout [MarkdownLine]) {
        // The kind of the line that started the open paragraph, if one is open.
        var head: LineKind?
        for index in lines.indices {
            let line = lines[index]
            let hasContent = !line.contentRange.isEmpty
            if let head, hasContent {
                if line.kind == .paragraph || (line.kind == .quote && head == .quote) {
                    lines[index].isContinuation = true
                    continue
                }
            }
            switch line.kind {
            case .paragraph, .listItem, .task, .quote:
                head = hasContent ? line.kind : nil
            default:
                head = nil
            }
        }
    }

    private enum Group {
        case code, quote, table
    }

    private static func group(of line: MarkdownLine) -> Group? {
        switch line.kind {
        case .fence, .code: .code
        case .quote: .quote
        case .tableHeader, .tableDelimiter, .tableRow: .table
        default: nil
        }
    }

    /// Marks each line as the first, middle, or last line of its code block, quote, or table.
    /// A plain line that continues a quote belongs to the quote.
    private static func assignBlockPositions(in lines: inout [MarkdownLine]) {
        var groups = lines.map(group(of:))
        for index in lines.indices.dropFirst() where lines[index].isContinuation && groups[index - 1] == .quote {
            groups[index] = .quote
        }
        var start = 0
        while start < lines.count {
            guard let kind = groups[start] else {
                start += 1
                continue
            }
            var end = start + 1
            while end < lines.count, groups[end] == kind {
                // A new opening fence or table header starts a new block.
                if case .fence(_, true) = lines[end].kind { break }
                if lines[end].kind == .tableHeader { break }
                if case .fence(_, false) = lines[end - 1].kind { break }
                end += 1
            }
            if end - start == 1 {
                lines[start].blockPosition = .single
            } else {
                lines[start].blockPosition = .first
                for index in (start + 1)..<(end - 1) {
                    lines[index].blockPosition = .middle
                }
                lines[end - 1].blockPosition = .last
            }
            start = end
        }
    }
}
