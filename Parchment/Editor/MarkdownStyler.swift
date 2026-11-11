import AppKit
import ParchmentCore

/// Turns the parse of a Markdown document into text attributes, restyling only the lines
/// that changed since the previous parse.
///
/// The styler also keeps that parse (`text` and `lines`) so the coordinator can hand it to
/// the window's controller without parsing the document a second time.
@MainActor
final class MarkdownStyler {
    var metrics: EditorMetrics {
        didSet {
            if metrics != oldValue { invalidateCaches() }
        }
    }

    /// The hanging gutter actually in use. It equals `metrics.gutter` unless the window is
    /// too narrow, in which case the text view shrinks it.
    var gutter: Double {
        didSet {
            if gutter != oldValue { invalidateCaches() }
        }
    }

    /// The document's location, used to resolve relative image and link paths.
    var documentURL: URL?

    /// Reading mode: Markdown symbols are hidden (inline ones take no room, hanging ones turn
    /// transparent so the text doesn't move). The text view restyles everything when it changes.
    var isReading = false

    /// The text view whose typing attributes and storage this styler manages.
    weak var textView: NSTextView?

    /// The text of the most recent parse, in sync with the storage after every `restyle`.
    private(set) var text = MarkdownText(units: [])
    private(set) var lines: [MarkdownLine] = []

    /// Horizontal room for images, measured from the gutter edge to the window's right side.
    private var availableImageWidth = Double.infinity
    /// Horizontal room for text, from the gutter edge to the right edge of the column. A table
    /// wider than this wraps its last column; if the earlier columns alone don't fit, it is
    /// left as typed, since its wrapped rows can't line up.
    private var textWidth = Double.infinity
    private var paragraphCache: [ParagraphKey: NSParagraphStyle] = [:]
    private var widthCache: [WidthKey: Double] = [:]
    private var pendingImages: Set<URL> = []

    /// Space reserved above and below an inline image, in total.
    private static let imageVerticalPadding = 24.0
    private static let maxImageHeight = 520.0
    /// Extra room an image may take beyond the right edge of the measure.
    private static let imageOverhang = 80.0
    /// How far quote text sits right of the gutter, leaving room for the bar.
    private static let quoteTextOffset = 22.0
    /// The gap between a quote's `>` and its bar.
    private static let quoteMarkerGap = 12.0
    /// Padding the code block background needs above its first and below its last line.
    private static let codeBlockPadding = 14.0

    init(metrics: EditorMetrics) {
        self.metrics = metrics
        self.gutter = metrics.gutter
    }

    // MARK: - Restyling

    /// Parses the storage and restyles the lines that changed since the last call, or every
    /// line when `full` is true. Lines touched by the selection are always restyled, which
    /// catches edits that replace text with identical text.
    func restyle(_ storage: NSTextStorage, full: Bool) {
        let newText = Self.snapshot(of: storage)
        let newLines = MarkdownParser.lines(in: newText)
        let isFull = full || lines.isEmpty
        let changed: Range<Int> = if isFull {
            0..<newLines.count
        } else {
            LineDiff.changedLines(old: text, oldLines: lines, new: newText, newLines: newLines)
        }
        text = newText
        lines = newLines

        var indices = IndexSet(integersIn: changed)
        if !isFull, let selection = textView?.selectedRange(), selection.location != NSNotFound {
            indices.formUnion(lineIndices(touching: selection))
        }

        restyleLines(indices, in: storage)
        updateTypingAttributes()
        (textView as? ParchmentTextView)?.stylingDidChange()
    }

    /// Restyles the image lines whose source resolves to `url`, or every image line when
    /// `url` is `nil`. Used when an image arrives, the document moves, or the width changes.
    func restyleImageLines(matching url: URL?) {
        guard let storage = textView?.textStorage else { return }
        if storage.length != text.length {
            restyle(storage, full: false)
        }
        var indices = IndexSet()
        for (index, line) in lines.enumerated() {
            guard case .image(let source) = line.kind else { continue }
            if url == nil || resolveURL(source) == url {
                indices.insert(index)
            }
        }
        guard !indices.isEmpty else { return }
        restyleLines(indices, in: storage)
        (textView as? ParchmentTextView)?.stylingDidChange()
    }

    /// Records how much horizontal room images have, restyling image lines when that changes
    /// the size they are drawn at.
    func updateAvailableImageWidth(_ width: Double) {
        guard abs(width - availableImageWidth) >= 1 else { return }
        let limit = metrics.measure + Self.imageOverhang
        let oldFit = min(availableImageWidth, limit)
        availableImageWidth = width
        if abs(min(width, limit) - oldFit) >= 1, !lines.isEmpty {
            restyleImageLines(matching: nil)
        }
    }

    /// Records how much horizontal room text has, realigning tables when it changes.
    func updateTextWidth(_ width: Double) {
        guard abs(width - textWidth) >= 1 else { return }
        textWidth = width
        guard let storage = textView?.textStorage, !lines.isEmpty else { return }
        if storage.length != text.length {
            restyle(storage, full: false)
            return
        }
        let tables = IndexSet(lines.indices.filter { lines[$0].kind.isTable })
        guard !tables.isEmpty else { return }
        restyleLines(tables, in: storage)
        (textView as? ParchmentTextView)?.stylingDidChange()
    }

    /// The attributes for newly typed text: body font, ink, and the body paragraph style.
    var bodyAttributes: [NSAttributedString.Key: Any] {
        attributes(
            font: FontBook.shared.text(size: metrics.fontSize),
            color: Palette.ink,
            paragraph: bodyParagraph(spacingAfter: metrics.paragraphSpacing)
        )
    }

    /// The paragraph style for text with no block syntax, also used for the empty last line.
    var bodyParagraphStyle: NSParagraphStyle {
        bodyParagraph(spacingAfter: metrics.paragraphSpacing)
    }

    /// Typing attributes follow the caret's line. Inline predictions and input methods draw
    /// their marked text with them, so plain body attributes would shrink a word being typed
    /// in a heading until it is committed.
    private func updateTypingAttributes() {
        guard let textView, !textView.hasMarkedText() else { return }
        textView.typingAttributes = typingAttributes(at: textView.selectedRange().location)
    }

    /// Body attributes, with the font, paragraph style and tracking of the character before
    /// `location` on its line (or the line's first character when `location` starts it).
    private func typingAttributes(at location: Int) -> [NSAttributedString.Key: Any] {
        var result = bodyAttributes
        guard let storage = textView?.textStorage, location != NSNotFound,
              location <= storage.length, !lines.isEmpty else { return result }
        let lineRange = NSRange(lines[lineIndex(containing: location)].range)
        guard lineRange.length > 0, NSMaxRange(lineRange) <= storage.length else { return result }
        let source = location > lineRange.location ? min(location, NSMaxRange(lineRange)) - 1 : lineRange.location
        let attributes = storage.attributes(at: source, effectiveRange: nil)
        for key in [NSAttributedString.Key.font, .paragraphStyle, .tracking] {
            if let value = attributes[key] { result[key] = value }
        }
        return result
    }

    /// Restyles the lines at `indices`. A table's columns depend on all of its rows, so a
    /// change to any table line restyles and realigns that whole table.
    private func restyleLines(_ indices: IndexSet, in storage: NSTextStorage) {
        guard !indices.isEmpty else { return }
        var all = IndexSet()
        var tables: [Range<Int>] = []
        for index in withParagraphs(indices) where !all.contains(index) {
            if lines[index].kind.isTable {
                let table = tableBlock(containing: index)
                tables.append(table)
                all.insert(integersIn: table)
            } else {
                all.insert(index)
            }
        }
        storage.beginEditing()
        for index in all {
            style(at: index, in: storage)
        }
        for table in tables {
            alignTable(table, in: storage)
        }
        // Each line's style covers its own line break, so the breaks are marked last.
        for index in all {
            styleBreak(before: index, in: storage)
        }
        storage.endEditing()
    }

    // MARK: - Hard-wrapped paragraphs

    /// The lines of a hard-wrapped paragraph style one another: a continuation takes its
    /// indent from the paragraph's first line, and a line's spacing depends on whether the next
    /// line continues it. So restyling a line restyles its whole paragraph and the line above.
    private func withParagraphs(_ indices: IndexSet) -> IndexSet {
        var result = IndexSet()
        for index in indices where index >= 0 && index < lines.count && !result.contains(index) {
            let head = paragraphHead(of: index)
            result.insert(integersIn: head...paragraphTail(of: index))
            if head > 0 { result.insert(head - 1) }
        }
        return result
    }

    /// The first line of the paragraph that holds line `index`.
    private func paragraphHead(of index: Int) -> Int {
        var head = index
        while head > 0, lines[head].isContinuation { head -= 1 }
        return head
    }

    /// The last line of the paragraph that holds line `index`.
    private func paragraphTail(of index: Int) -> Int {
        var tail = index
        while continues(after: tail) { tail += 1 }
        return tail
    }

    private func continues(after index: Int) -> Bool {
        index + 1 < lines.count && lines[index + 1].isContinuation
    }

    /// The space after line `index`, given the space `normal` puts after a line of its kind.
    /// While editing, the lines of one paragraph sit close together, with the space only after
    /// the last. Reading mode lays them out as one paragraph, so each line carries the space
    /// the paragraph ends with.
    private func spacingAfter(line index: Int, _ normal: (MarkdownLine) -> Double) -> Double {
        if isReading { return normal(lines[paragraphTail(of: index)]) }
        return continues(after: index) ? 0 : normal(lines[index])
    }

    /// In reading mode, marks the line break before a continuation so the layout manager lays it
    /// out as a space. Two spaces at the end of the line above keep the break, as in Markdown.
    private func styleBreak(before index: Int, in storage: NSTextStorage) {
        guard index > 0, index < lines.count else { return }
        let above = lines[index - 1]
        let range = NSRange(location: above.range.upperBound, length: above.lineBreakLength)
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }
        guard isReading, lines[index].isContinuation else {
            storage.removeAttribute(.parchmentSoftBreak, range: range)
            return
        }
        let end = above.range.upperBound
        let keepsLineBreak = above.range.length >= 2 && text[end - 1] == Self.space && text[end - 2] == Self.space
        storage.addAttribute(.parchmentSoftBreak, value: NSNumber(value: keepsLineBreak), range: range)
    }

    /// Styles a plain line that continues the paragraph, list item or quote above it. While
    /// editing it lines up under that block's text, its leading spaces hanging to the left. In
    /// reading mode those spaces are hidden and the line flows on from the one above.
    private func styleContinuation(at index: Int, in storage: NSTextStorage) {
        let line = lines[index]
        let head = lines[paragraphHead(of: index)]
        let font: NSFont
        let indent: Double
        let lineSpacing: Double
        var maxLineHeight = 0.0
        let spacing: Double
        switch head.kind {
        case .listItem, .task:
            font = FontBook.shared.text(size: metrics.fontSize)
            indent = listTextIndent(of: head)
            lineSpacing = metrics.lineSpacing
            maxLineHeight = metrics.maxLineHeight
            spacing = spacingAfter(line: index) { _ in listSpacingAfter }
        case .quote:
            let size = quoteFontSize
            font = FontBook.shared.text(size: size, weight: .semibold)
            indent = gutter + Self.quoteTextOffset
            lineSpacing = (size * 0.35).rounded()
            spacing = spacingAfter(line: index) { $0.blockPosition.isLast ? metrics.paragraphSpacing : 0 }
        default:
            font = FontBook.shared.text(size: metrics.fontSize)
            indent = gutter
            lineSpacing = metrics.lineSpacing
            maxLineHeight = metrics.maxLineHeight
            spacing = spacingAfter(line: index) { _ in metrics.paragraphSpacing }
        }

        let leading = width(of: text.string(in: line.prefixRange), font: font)
        let paragraph = paragraphStyle(ParagraphKey(
            firstLineHeadIndent: isReading ? indent : max(0, indent - leading),
            headIndent: indent,
            lineSpacing: lineSpacing,
            maxLineHeight: maxLineHeight,
            spacingBefore: 0,
            spacingAfter: spacing
        ))
        let fullRange = NSRange(line.fullRange)
        storage.setAttributes(attributes(font: font, color: Palette.ink, paragraph: paragraph), range: fullRange)
        if head.kind == .quote {
            storage.addAttribute(.parchmentBlock, value: NSNumber(value: Self.decoration(.quote, position: line.blockPosition).rawValue), range: fullRange)
        }
    }

    /// Hides a continuation's leading spaces (and a quote line's `>`) in reading mode, and
    /// strikes it through when it continues a ticked task.
    private func finishContinuation(at index: Int, in storage: NSTextStorage) {
        let line = lines[index]
        if case .task(.done) = lines[paragraphHead(of: index)].kind, !line.contentRange.isEmpty {
            storage.addAttributes([
                .strikethroughStyle: NSNumber(value: NSUnderlineStyle.single.rawValue),
                .strikethroughColor: Palette.muted,
                .foregroundColor: Palette.muted,
            ], range: NSRange(line.contentRange))
        }
        let prefix = NSRange(line.prefixRange)
        guard isReading, prefix.length > 0 else { return }
        storage.removeAttribute(.kern, range: prefix)
        storage.addAttribute(.parchmentHidden, value: NSNumber(value: true), range: prefix)
    }

    /// The lines of the table that holds line `index`, from its header to its last row.
    private func tableBlock(containing index: Int) -> Range<Int> {
        var start = index
        while start > 0, lines[start].kind != .tableHeader, lines[start - 1].kind.isTable {
            start -= 1
        }
        var end = index + 1
        while end < lines.count, lines[end].kind.isTable, lines[end].kind != .tableHeader {
            end += 1
        }
        return start..<end
    }

    /// Copies the storage's UTF-16 contents in one call, which is much faster than walking a `String`.
    private static func snapshot(of storage: NSTextStorage) -> MarkdownText {
        let string = storage.mutableString
        let length = string.length
        guard length > 0 else { return MarkdownText(units: []) }
        var units = [UInt16](repeating: 0, count: length)
        units.withUnsafeMutableBufferPointer { buffer in
            if let base = buffer.baseAddress {
                string.getCharacters(base, range: NSRange(location: 0, length: length))
            }
        }
        return MarkdownText(units: units)
    }

    /// Indices of the lines that overlap `range`, found by binary search.
    private func lineIndices(touching range: NSRange) -> IndexSet {
        guard !lines.isEmpty else { return IndexSet() }
        let first = lineIndex(containing: range.location)
        let last = lineIndex(containing: range.location + range.length)
        return IndexSet(integersIn: first...max(first, last))
    }

    private func lineIndex(containing offset: Int) -> Int {
        var low = 0
        var high = lines.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lines[middle].range.location <= offset {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    // MARK: - Line styles

    private func style(at index: Int, in storage: NSTextStorage) {
        let line = lines[index]
        let fullRange = NSRange(line.fullRange)
        guard fullRange.length > 0, NSMaxRange(fullRange) <= storage.length else { return }
        let body = FontBook.shared.text(size: metrics.fontSize)

        switch line.kind {
        case .blank:
            storage.setAttributes(attributes(font: body, color: Palette.ink, paragraph: bodyParagraph(spacingAfter: 0)), range: fullRange)

        case .paragraph where line.isContinuation:
            styleContinuation(at: index, in: storage)

        case .paragraph:
            let spacing = spacingAfter(line: index) { _ in metrics.paragraphSpacing }
            storage.setAttributes(attributes(font: body, color: Palette.ink, paragraph: bodyParagraph(spacingAfter: spacing)), range: fullRange)

        case .heading(let level):
            styleHeading(line, level: level, in: storage)

        case .listItem, .task:
            styleListItem(at: index, in: storage)

        case .quote:
            styleQuote(at: index, in: storage)

        case .fence:
            // Reading mode keeps the fence lines as padding inside the block, but blank.
            styleCode(line, color: isReading ? .clear : Palette.codeFence, in: storage)

        case .code:
            styleCode(line, color: Palette.codeText, in: storage)

        case .tableHeader, .tableDelimiter, .tableRow:
            styleTable(line, in: storage)

        case .rule:
            storage.setAttributes(attributes(font: body, color: isReading ? .clear : Palette.marker, paragraph: bodyParagraph(spacingAfter: metrics.paragraphSpacing)), range: fullRange)
            let lineRange = NSRange(line.range)
            if lineRange.length > 0 {
                storage.addAttribute(.parchmentRule, value: NSNumber(value: true), range: lineRange)
            }

        case .image(let source):
            styleImage(line, source: source, in: storage)
        }

        applySpans(MarkdownParser.spans(for: line, in: text), line: line, in: storage)
        if line.isContinuation {
            finishContinuation(at: index, in: storage)
        }
    }

    private func styleHeading(_ line: MarkdownLine, level: Int, in storage: NSTextStorage) {
        let size = metrics.headingSize(level: level)
        let font = FontBook.shared.text(size: size, weight: Self.headingWeight(level: level))
        let prefixFont = FontBook.shared.text(size: size, weight: .bold)
        let prefixWidth = width(of: text.string(in: line.prefixRange), font: prefixFont)

        let paragraph = paragraphStyle(ParagraphKey(
            firstLineHeadIndent: max(0, gutter - prefixWidth),
            headIndent: gutter,
            lineSpacing: (size * 0.12).rounded(),
            spacingBefore: metrics.headingSpacingBefore(level: level),
            spacingAfter: (metrics.fontSize * 0.75).rounded()
        ))
        storage.setAttributes(attributes(font: font, color: Palette.ink, paragraph: paragraph), range: NSRange(line.fullRange))

        let prefix = NSRange(line.prefixRange)
        if prefix.length > 0 {
            storage.addAttributes([.font: prefixFont, .foregroundColor: isReading ? NSColor.clear : Palette.accent], range: prefix)
        }
        let tracking = Self.headingTracking(level: level) * size
        let content = NSRange(line.contentRange)
        if tracking != 0, content.length > 0 {
            storage.addAttribute(.tracking, value: NSNumber(value: tracking), range: content)
        }
    }

    /// Lists and tasks hang their whole prefix (indent, marker, and box) in the gutter, and
    /// nested items move the text edge right by 1.5em per four columns of indentation.
    private func styleListItem(at index: Int, in storage: NSTextStorage) {
        let line = lines[index]
        let body = FontBook.shared.text(size: metrics.fontSize)
        let prefix = text.string(in: line.prefixRange)
        let headIndent = listTextIndent(of: line)
        let paragraph = paragraphStyle(ParagraphKey(
            firstLineHeadIndent: max(0, headIndent - width(of: prefix, font: body)),
            headIndent: headIndent,
            lineSpacing: metrics.lineSpacing,
            maxLineHeight: metrics.maxLineHeight,
            spacingBefore: 0,
            spacingAfter: spacingAfter(line: index) { _ in listSpacingAfter }
        ))
        storage.setAttributes(attributes(font: body, color: Palette.ink, paragraph: paragraph), range: NSRange(line.fullRange))
    }

    /// Where a list item's text starts: the gutter edge, moved right for nested items.
    private func listTextIndent(of line: MarkdownLine) -> Double {
        let nesting = Double(Self.indentColumns(of: text.string(in: line.prefixRange))) * metrics.fontSize * 0.375
        return gutter + nesting
    }

    private var listSpacingAfter: Double {
        (metrics.paragraphSpacing * 0.35).rounded()
    }

    private var quoteFontSize: Double {
        metrics.fontSize * 1.28
    }

    /// Quotes are set larger and semibold. The `>` hangs left of the bar at the gutter edge,
    /// and a kern on the last prefix character carries the text to its indented edge.
    private func styleQuote(at index: Int, in storage: NSTextStorage) {
        let line = lines[index]
        let size = quoteFontSize
        let font = FontBook.shared.text(size: size, weight: .semibold)
        let prefixWidth = width(of: text.string(in: line.prefixRange), font: font)
        let firstIndent = max(0, gutter - Self.quoteMarkerGap - prefixWidth)
        let textEdge = gutter + Self.quoteTextOffset

        let paragraph = paragraphStyle(ParagraphKey(
            firstLineHeadIndent: firstIndent,
            headIndent: textEdge,
            lineSpacing: (size * 0.35).rounded(),
            spacingBefore: 0,
            spacingAfter: spacingAfter(line: index) { $0.blockPosition.isLast ? metrics.paragraphSpacing : 0 }
        ))
        storage.setAttributes(attributes(font: font, color: Palette.ink, paragraph: paragraph), range: NSRange(line.fullRange))
        storage.addAttribute(.parchmentBlock, value: NSNumber(value: Self.decoration(.quote, position: line.blockPosition).rawValue), range: NSRange(line.fullRange))

        let prefix = NSRange(line.prefixRange)
        let kern = textEdge - firstIndent - prefixWidth
        if prefix.length > 0, kern > 0 {
            storage.addAttribute(.kern, value: NSNumber(value: kern), range: NSRange(location: NSMaxRange(prefix) - 1, length: 1))
        }
    }

    private func styleCode(_ line: MarkdownLine, color: NSColor, in storage: NSTextStorage) {
        let size = metrics.codeFontSize
        let font = FontBook.shared.mono(size: size)
        let position = line.blockPosition
        let paragraph = paragraphStyle(ParagraphKey(
            firstLineHeadIndent: gutter,
            headIndent: gutter,
            lineSpacing: (size * 0.45).rounded(),
            spacingBefore: position.isFirst ? Self.codeBlockPadding : 0,
            spacingAfter: position.isLast ? max(Self.codeBlockPadding, metrics.paragraphSpacing) : 0,
            tabInterval: width(of: "    ", font: font)
        ))
        let fullRange = NSRange(line.fullRange)
        storage.setAttributes(attributes(font: font, color: color, paragraph: paragraph), range: fullRange)
        storage.addAttribute(.parchmentBlock, value: NSNumber(value: Self.decoration(.code, position: position).rawValue), range: fullRange)
    }

    /// Tables are set in the body font; `alignTable` then lines up their columns. In reading
    /// mode the `---|---` row shrinks to a thin gap where the header rule is drawn.
    private func styleTable(_ line: MarkdownLine, in storage: NSTextStorage) {
        let isDelimiter = line.kind == .tableDelimiter
        let collapses = isDelimiter && isReading
        let font = FontBook.shared.text(size: collapses ? 4 : metrics.fontSize)
        let rowGap = collapses ? 0 : (metrics.fontSize * 0.35).rounded()
        let position = line.blockPosition
        let paragraph = paragraphStyle(ParagraphKey(
            firstLineHeadIndent: gutter,
            headIndent: gutter,
            lineSpacing: 0,
            spacingBefore: position.isFirst ? 0 : rowGap,
            spacingAfter: position.isLast ? metrics.paragraphSpacing : rowGap
        ))
        let color: NSColor = isDelimiter ? (isReading ? .clear : Palette.marker) : Palette.ink
        storage.setAttributes(attributes(font: font, color: color, paragraph: paragraph), range: NSRange(line.fullRange))
    }

    // MARK: - Table columns

    /// Lines up a table's columns: the last visible character of each cell is kerned so the
    /// pipe after it sits at the same x on every row. When the table is too wide for the
    /// column, the earlier columns still line up and each row's last cell wraps under itself.
    /// Only a table whose earlier columns alone don't fit is left as typed. In reading mode,
    /// rules go under the header and between rows.
    private func alignTable(_ block: Range<Int>, in storage: NSTextStorage) {
        guard !block.isEmpty else { return }
        if isReading, showRenderedTable(block, in: storage) { return }
        let cells = block.map { cellRanges(of: lines[$0]) }
        let widths = cells.map { $0.map { visibleWidth(of: $0, in: storage) } }
        let isDelimiter = block.map { lines[$0].kind == .tableDelimiter }
        // The last cell with text: the one before a closing pipe, or the line's last cell.
        let lastColumn: [Int] = cells.indices.map { row in
            let count = cells[row].count
            let closed = count > 1 && isBlank(cells[row][count - 1])
            return closed ? count - 2 : count - 1
        }

        var layout = columnLayout(cells: cells, widths: widths, isDelimiter: isDelimiter, lastColumn: lastColumn, wrapsLast: false, in: block, storage: storage)
        var wraps = false
        if layout.width > textWidth {
            let wrapped = columnLayout(cells: cells, widths: widths, isDelimiter: isDelimiter, lastColumn: lastColumn, wrapsLast: true, in: block, storage: storage)
            // The last column needs room for a few words before wrapping is worth it.
            let minimumLastColumn = metrics.fontSize * 8
            if wrapped.lastColumnStart + minimumLastColumn <= textWidth {
                layout = wrapped
                wraps = true
            }
        }
        let aligned = wraps || layout.width <= textWidth

        if aligned {
            for row in 0..<block.count {
                let line = lines[block.lowerBound + row]
                for (column, pad) in layout.pads[row].enumerated() where pad != 0 {
                    guard let anchor = kernAnchor(for: cells[row][column], line: line, in: storage) else { continue }
                    let existing = (storage.attribute(.kern, at: anchor, effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0
                    storage.addAttribute(.kern, value: NSNumber(value: existing + pad), range: NSRange(location: anchor, length: 1))
                }
            }
        }
        if wraps {
            // A wrapped row's later lines start where its last cell's text starts.
            for row in 0..<block.count where !isDelimiter[row] {
                let line = lines[block.lowerBound + row]
                let column = lastColumn[row]
                guard column > 0, column < cells[row].count else { continue }
                let cell = cells[row][column]
                let hang = layout.cellStarts[row][column] + leadingSpaceWidth(of: cell, in: storage)
                let range = NSRange(line.fullRange)
                guard range.length > 0,
                      let current = storage.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
                else { continue }
                let style = paragraphStyle(ParagraphKey(
                    firstLineHeadIndent: Double(current.firstLineHeadIndent),
                    headIndent: gutter + hang,
                    lineSpacing: Double(current.lineSpacing),
                    maxLineHeight: Double(current.maximumLineHeight),
                    spacingBefore: Double(current.paragraphSpacingBefore),
                    spacingAfter: Double(current.paragraphSpacing)
                ))
                storage.addAttribute(.paragraphStyle, value: style, range: range)
            }
        }

        guard isReading else { return }
        if !aligned {
            // Unaligned, the cells need their pipes to stay apart.
            for row in 0..<block.count where !isDelimiter[row] {
                for cell in cells[row].dropLast() {
                    storage.addAttribute(.foregroundColor, value: Palette.marker, range: NSRange(location: NSMaxRange(cell), length: 1))
                }
            }
        }
        let ruleWidth = NSNumber(value: aligned && !wraps ? layout.width : textWidth)
        for row in 0..<block.count {
            let line = lines[block.lowerBound + row]
            let range = NSRange(line.range)
            guard range.length > 0 else { continue }
            if isDelimiter[row] {
                storage.addAttribute(.parchmentTableRule, value: ruleWidth, range: range)
            } else if line.kind == .tableRow, !line.blockPosition.isLast {
                storage.addAttribute(.parchmentTableRowRule, value: ruleWidth, range: range)
            }
        }
    }

    /// Reading mode shows a table as a grid drawn by `TableRenderer`. Its source lines shrink
    /// to hairlines of transparent text, and the last one reserves the grid's height as
    /// paragraph spacing, where the layout manager draws it like an image. Returns false when
    /// the table can't be rendered, leaving the aligned text in place.
    private func showRenderedTable(_ block: Range<Int>, in storage: NSTextStorage) -> Bool {
        let source = block.map { text.string(in: lines[$0].range) }.joined(separator: "\n")
        let width = textWidth.isFinite ? textWidth : metrics.measure
        guard let rendered = TableRenderer.shared.render(source, width: width, fontSize: metrics.fontSize) else { return false }

        let tiny = FontBook.shared.text(size: 1)
        for index in block {
            let line = lines[index]
            let fullRange = NSRange(line.fullRange)
            guard fullRange.length > 0, NSMaxRange(fullRange) <= storage.length else { continue }
            let isLast = index == block.upperBound - 1
            let paragraph = paragraphStyle(ParagraphKey(
                firstLineHeadIndent: gutter,
                headIndent: gutter,
                lineSpacing: 0,
                spacingBefore: 0,
                spacingAfter: isLast ? rendered.height + Self.imageVerticalPadding : 0
            ))
            storage.addAttributes([.font: tiny, .foregroundColor: NSColor.clear, .paragraphStyle: paragraph], range: fullRange)
            storage.removeAttribute(.kern, range: fullRange)
            let lineRange = NSRange(line.range)
            if isLast, lineRange.length > 0 {
                storage.addAttributes([.parchmentImage: rendered.image, .parchmentTable: NSNumber(value: true)], range: lineRange)
            }
        }
        return true
    }

    /// Where a table's cells land once its columns are lined up.
    private struct ColumnLayout {
        /// The kern each cell needs after its last visible character.
        var pads: [[Double]]
        /// The x at which each cell starts, from the start of the row.
        var cellStarts: [[Double]]
        /// The widest row once padded, measured on rows with text.
        var width: Double
        /// The furthest x at which a row's last cell starts.
        var lastColumnStart: Double
    }

    /// Pads every cell but a line's last so the pipes after it line up. With `wrapsLast`, each
    /// row's last cell with text is left unpadded and doesn't push the columns before it, so
    /// it can wrap.
    private func columnLayout(
        cells: [[NSRange]],
        widths: [[Double]],
        isDelimiter: [Bool],
        lastColumn: [Int],
        wrapsLast: Bool,
        in block: Range<Int>,
        storage: NSTextStorage
    ) -> ColumnLayout {
        let rows = cells.count
        let gap = (metrics.fontSize * 0.5).rounded()
        var starts = [Double](repeating: 0, count: rows)
        var pads: [[Double]] = cells.map { [Double](repeating: 0, count: $0.count) }
        var cellStarts: [[Double]] = cells.map { [Double](repeating: 0, count: $0.count) }
        let columnCount = cells.map(\.count).max() ?? 0
        let isFree = { (row: Int, column: Int) in wrapsLast && column >= lastColumn[row] }
        for column in 0..<max(0, columnCount - 1) {
            var end = 0.0
            for row in 0..<rows where !isDelimiter[row] && column < cells[row].count - 1 && !isFree(row, column) {
                end = max(end, starts[row] + widths[row][column])
            }
            if end > 0 { end += gap }
            for row in 0..<rows where column < cells[row].count - 1 {
                cellStarts[row][column] = starts[row]
                let natural = starts[row] + widths[row][column]
                let canPad = !isFree(row, column)
                    && kernAnchor(for: cells[row][column], line: lines[block.lowerBound + row], in: storage) != nil
                let pad = canPad ? end - natural : 0
                pads[row][column] = pad
                let pipe = NSRange(location: NSMaxRange(cells[row][column]), length: 1)
                starts[row] = natural + pad + visibleWidth(of: pipe, in: storage)
            }
        }
        var width = 0.0
        var lastColumnStart = 0.0
        for row in 0..<rows where !isDelimiter[row] {
            if let last = cells[row].indices.last {
                cellStarts[row][last] = starts[row]
            }
            width = max(width, starts[row] + (widths[row].last ?? 0))
            let column = lastColumn[row]
            if column >= 0, column < cellStarts[row].count {
                lastColumnStart = max(lastColumnStart, cellStarts[row][column])
            }
        }
        return ColumnLayout(pads: pads, cellStarts: cellStarts, width: width, lastColumnStart: lastColumnStart)
    }

    /// Whether a cell holds nothing but spaces and tabs.
    private func isBlank(_ cell: NSRange) -> Bool {
        for index in cell.location..<NSMaxRange(cell) where text[index] != Self.space && text[index] != Self.tab {
            return false
        }
        return true
    }

    /// The width of the spaces at the start of a cell, so wrapped text lines up with its words.
    private func leadingSpaceWidth(of cell: NSRange, in storage: NSTextStorage) -> Double {
        var end = cell.location
        while end < NSMaxRange(cell), text[end] == Self.space || text[end] == Self.tab {
            end += 1
        }
        return visibleWidth(of: NSRange(location: cell.location, length: end - cell.location), in: storage)
    }

    /// The text between a table line's unescaped pipes: before the first, between each pair,
    /// and after the last.
    private func cellRanges(of line: MarkdownLine) -> [NSRange] {
        var cells: [NSRange] = []
        var start = line.range.location
        for index in line.range.range where text[index] == Self.pipe {
            if index > line.range.location, text[index - 1] == Self.backslash { continue }
            cells.append(NSRange(location: start, length: index - start))
            start = index + 1
        }
        cells.append(NSRange(location: start, length: line.range.upperBound - start))
        return cells
    }

    /// The character whose kern pads a cell: its last visible character, or the pipe before
    /// it when the cell is empty or fully hidden. `nil` for an empty cell at the line start.
    private func kernAnchor(for cell: NSRange, line: MarkdownLine, in storage: NSTextStorage) -> Int? {
        var index = NSMaxRange(cell) - 1
        while index >= cell.location {
            if storage.attribute(.parchmentHidden, at: index, effectiveRange: nil) == nil { return index }
            index -= 1
        }
        let previous = cell.location - 1
        return previous >= line.range.location ? previous : nil
    }

    /// The width a range takes when laid out, leaving out characters reading mode hides.
    private func visibleWidth(of range: NSRange, in storage: NSTextStorage) -> Double {
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return 0 }
        let piece = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        if isReading {
            var hidden: [NSRange] = []
            piece.enumerateAttribute(.parchmentHidden, in: NSRange(location: 0, length: piece.length), options: []) { value, subrange, _ in
                if value != nil { hidden.append(subrange) }
            }
            for subrange in hidden.reversed() {
                piece.deleteCharacters(in: subrange)
            }
        }
        guard piece.length > 0 else { return 0 }
        // Typographic bounds include trailing spaces, which take room between the pipes.
        let line = CTLineCreateWithAttributedString(piece)
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    private static let pipe: UInt16 = 124
    private static let space: UInt16 = 32
    private static let tab: UInt16 = 9
    private static let backslash: UInt16 = 92

    /// Image lines show their source in marker color. A loaded image reserves its height as
    /// paragraph spacing; the layout manager draws it there. On the document's last line,
    /// which has no line break, the text view reserves the room and draws the image itself.
    private func styleImage(_ line: MarkdownLine, source: String, in storage: NSTextStorage) {
        let body = FontBook.shared.text(size: metrics.fontSize)
        var spacingAfter = metrics.paragraphSpacing
        var image: NSImage?
        if let loaded = loadedImage(for: source) {
            image = loaded.image
            spacingAfter = loaded.height + Self.imageVerticalPadding
        }
        // Reading mode shows the picture without its source line.
        let color = isReading && image != nil ? NSColor.clear : Palette.marker
        storage.setAttributes(attributes(font: body, color: color, paragraph: bodyParagraph(spacingAfter: spacingAfter)), range: NSRange(line.fullRange))
        let lineRange = NSRange(line.range)
        if let image, lineRange.length > 0 {
            storage.addAttribute(.parchmentImage, value: image, range: lineRange)
        }
    }

    // MARK: - Spans

    private func applySpans(_ spans: [MarkdownSpan], line: MarkdownLine, in storage: NSTextStorage) {
        guard !spans.isEmpty else { return }
        let ordered = spans.sorted { Self.rank($0.kind) < Self.rank($1.kind) }
        let isCode = line.kind.isCodeBlock
        let headingContentStart: Int? = if case .heading = line.kind { line.contentStart } else { nil }
        // Inline symbols collapse in reading mode. Table pipes turn transparent instead, keeping
        // the columns lined up, and whole-line syntax (fences, rules, images, the table's
        // `---|---` row) is styled per line.
        let hidesInlineSyntax = isReading && Self.hidesInlineSyntax(line.kind)
        let hidden: [NSAttributedString.Key: Any] = [.parchmentHidden: NSNumber(value: true)]

        for span in ordered {
            let range = NSRange(span.range)
            guard range.length > 0, NSMaxRange(range) <= storage.length else { continue }

            switch span.kind {
            case .syntax:
                // Fence lines keep their code colors, and the hanging heading `#`s stay accent.
                if isCode { continue }
                if let headingContentStart, span.range.location < headingContentStart { continue }
                if hidesInlineSyntax, line.kind.isTable, range.length == 1, text[range.location] == Self.pipe {
                    // Pipes keep their width so columns stay lined up.
                    storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
                } else if hidesInlineSyntax {
                    storage.addAttributes(hidden, range: range)
                } else if isReading, Self.isWholeLineSyntax(line.kind) {
                    // The line style already decided its color (transparent, or marker for
                    // an image that hasn't loaded).
                    continue
                } else {
                    storage.addAttribute(.foregroundColor, value: Palette.marker, range: range)
                }

            case .strong:
                transformFonts(in: range, of: storage) { FontBook.shared.adding(bold: true, italic: false, to: $0) }

            case .emphasis:
                transformFonts(in: range, of: storage) { FontBook.shared.adding(bold: false, italic: true, to: $0) }

            case .strikethrough, .completedTask:
                storage.addAttributes([
                    .strikethroughStyle: NSNumber(value: NSUnderlineStyle.single.rawValue),
                    .strikethroughColor: Palette.muted,
                    .foregroundColor: Palette.muted,
                ], range: range)

            case .code:
                transformFonts(in: range, of: storage) { FontBook.shared.mono(size: Double($0.pointSize) * 0.88) }
                storage.addAttributes([
                    .foregroundColor: Palette.accent,
                    .parchmentInlineCode: NSNumber(value: true),
                ], range: range)
                // Room for the pill's side padding, so it never touches the faint backticks.
                // The kern after the opening backtick pads the left; after the last code
                // character, the right.
                let padding = NSNumber(value: Double(MarkdownLayoutManager.inlineCodePadding))
                // In reading mode the opening backtick takes no room, so the kern goes on the
                // character before it instead.
                let leftPadIndex = hidesInlineSyntax ? range.location - 2 : range.location - 1
                if leftPadIndex >= line.range.location {
                    storage.addAttribute(.kern, value: padding, range: NSRange(location: leftPadIndex, length: 1))
                }
                storage.addAttribute(.kern, value: padding, range: NSRange(location: NSMaxRange(range) - 1, length: 1))

            case .linkText(let destination):
                var linkAttributes: [NSAttributedString.Key: Any] = [
                    .foregroundColor: Palette.ink,
                    .underlineStyle: NSNumber(value: NSUnderlineStyle.thick.rawValue),
                    .underlineColor: Palette.accent,
                ]
                if !destination.isEmpty { linkAttributes[.parchmentLink] = destination }
                storage.addAttributes(linkAttributes, range: range)

            case .linkDestination(let destination):
                if hidesInlineSyntax {
                    storage.addAttributes(hidden, range: range)
                    continue
                }
                storage.addAttribute(.foregroundColor, value: Palette.marker, range: range)
                if !destination.isEmpty {
                    storage.addAttribute(.parchmentLink, value: destination, range: range)
                }

            case .listMarker:
                if !isReading {
                    storage.addAttribute(.foregroundColor, value: Palette.marker, range: range)
                } else if case .listItem(isOrdered: true) = line.kind {
                    // Numbers are content, so they stay, quieter than the text.
                    storage.addAttribute(.foregroundColor, value: Palette.muted, range: range)
                } else {
                    // Hanging markers turn transparent rather than collapsing, so the text
                    // doesn't move. A bullet is drawn in place of `-`; tasks show their circle.
                    storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
                    if case .listItem = line.kind, let bullet = firstNonSpace(in: range) {
                        storage.addAttribute(.parchmentBullet, value: NSNumber(value: true), range: NSRange(location: bullet, length: 1))
                    }
                }

            case .quoteMarker:
                storage.addAttribute(.foregroundColor, value: isReading ? NSColor.clear : Palette.marker, range: range)

            case .taskBox(let state):
                storage.addAttributes([
                    .foregroundColor: NSColor.clear,
                    .parchmentTaskBox: NSNumber(value: state.rawValue),
                ], range: range)

            case .tableHeader:
                transformFonts(in: range, of: storage) { FontBook.shared.adding(bold: true, italic: false, to: $0) }

            case .codeToken(let token):
                storage.addAttribute(.foregroundColor, value: Palette.color(for: token), range: range)
                if token == .comment {
                    storage.addAttribute(.font, value: FontBook.shared.mono(size: metrics.codeFontSize, italic: true), range: range)
                }
            }
        }
    }

    private static func hidesInlineSyntax(_ kind: LineKind) -> Bool {
        switch kind {
        case .paragraph, .heading, .quote, .listItem, .task, .tableHeader, .tableRow: true
        default: false
        }
    }

    private static func isWholeLineSyntax(_ kind: LineKind) -> Bool {
        switch kind {
        case .fence, .rule, .image, .tableDelimiter: true
        default: false
        }
    }

    private func firstNonSpace(in range: NSRange) -> Int? {
        for index in range.location..<NSMaxRange(range) where index < text.length {
            let unit = text[index]
            if unit != 32, unit != 9 { return index }
        }
        return nil
    }

    /// Broad spans first, so narrower ones (markers, links, boxes) win where they overlap.
    private static func rank(_ kind: SpanKind) -> Int {
        switch kind {
        case .completedTask, .tableHeader: 0
        case .strong, .emphasis: 1
        case .strikethrough: 2
        case .code, .codeToken: 3
        case .linkText: 4
        case .linkDestination: 5
        case .syntax, .listMarker, .quoteMarker: 6
        case .taskBox: 7
        }
    }

    private func transformFonts(in range: NSRange, of storage: NSTextStorage, _ transform: (NSFont) -> NSFont) {
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            storage.addAttribute(.font, value: transform(font), range: subrange)
        }
    }

    // MARK: - Images

    private func loadedImage(for source: String) -> (image: NSImage, height: Double)? {
        guard let url = resolveURL(source) else { return nil }
        guard let image = ImageStore.shared.image(for: url) else {
            requestImage(url)
            return nil
        }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let maxWidth = max(40, min(metrics.measure + Self.imageOverhang, availableImageWidth))
        var width = min(Double(size.width), maxWidth)
        var height = width * Double(size.height / size.width)
        if height > Self.maxImageHeight {
            height = Self.maxImageHeight
            width = height * Double(size.width / size.height)
        }
        return (image, height.rounded())
    }

    private func requestImage(_ url: URL) {
        let store = ImageStore.shared
        guard !pendingImages.contains(url), !store.hasFailed(url) else { return }
        pendingImages.insert(url)
        Task { [weak self] in
            let image = await store.load(url)
            guard let self else { return }
            self.pendingImages.remove(url)
            if image != nil {
                self.restyleImageLines(matching: url)
            }
        }
    }

    /// Resolves an image source or link destination to a URL: web and `file:` URLs as written,
    /// absolute and `~` paths as files, and anything else relative to the document's folder.
    func resolveURL(_ source: String) -> URL? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lowercased = trimmed.lowercased()
        if ["http://", "https://", "file:", "mailto:"].contains(where: { lowercased.hasPrefix($0) }) {
            if let url = URL(string: trimmed) { return url }
            return trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap { URL(string: $0) }
        }

        let path = trimmed.removingPercentEncoding ?? trimmed
        if path.hasPrefix("~") {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        guard let directory = documentURL?.deletingLastPathComponent() else { return nil }
        return directory.appending(path: path).standardizedFileURL
    }

    // MARK: - Attribute helpers

    private func attributes(font: NSFont, color: NSColor, paragraph: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
    }

    private func bodyParagraph(spacingAfter: Double) -> NSParagraphStyle {
        paragraphStyle(ParagraphKey(
            firstLineHeadIndent: gutter,
            headIndent: gutter,
            lineSpacing: metrics.lineSpacing,
            maxLineHeight: metrics.maxLineHeight,
            spacingBefore: 0,
            spacingAfter: spacingAfter
        ))
    }

    private func paragraphStyle(_ key: ParagraphKey) -> NSParagraphStyle {
        if let cached = paragraphCache[key] { return cached }
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = CGFloat(key.firstLineHeadIndent)
        style.headIndent = CGFloat(key.headIndent)
        style.lineSpacing = CGFloat(key.lineSpacing)
        if key.maxLineHeight > 0 {
            style.maximumLineHeight = CGFloat(key.maxLineHeight)
        }
        style.paragraphSpacingBefore = CGFloat(key.spacingBefore)
        style.paragraphSpacing = CGFloat(key.spacingAfter)
        style.lineHeightMultiple = 1
        style.lineBreakMode = .byWordWrapping
        if key.tabInterval > 0 {
            style.tabStops = []
            style.defaultTabInterval = CGFloat(key.tabInterval)
        }
        let frozen = (style.copy() as? NSParagraphStyle) ?? style
        paragraphCache[key] = frozen
        return frozen
    }

    private func width(of string: String, font: NSFont) -> Double {
        guard !string.isEmpty else { return 0 }
        let key = WidthKey(string: string, fontName: font.fontName, size: Double(font.pointSize))
        if let cached = widthCache[key] { return cached }
        if widthCache.count > 1024 { widthCache.removeAll(keepingCapacity: true) }
        let measured = Double((string as NSString).size(withAttributes: [.font: font]).width)
        widthCache[key] = measured
        return measured
    }

    private func invalidateCaches() {
        paragraphCache.removeAll()
        widthCache.removeAll()
    }

    private static func decoration(_ base: BlockDecoration, position: BlockPosition) -> BlockDecoration {
        var decoration = base
        if position.isFirst { decoration.insert(.isFirst) }
        if position.isLast { decoration.insert(.isLast) }
        return decoration
    }

    private static func headingWeight(level: Int) -> NSFont.Weight {
        switch level {
        case 1: .heavy
        case 2, 3: .bold
        default: .semibold
        }
    }

    /// Letter spacing in ems: large headings are set tighter.
    private static func headingTracking(level: Int) -> Double {
        switch level {
        case 1: -0.035
        case 2: -0.02
        default: 0
        }
    }

    /// Leading whitespace in columns, counting a tab as four.
    private static func indentColumns(of prefix: String) -> Int {
        var columns = 0
        for character in prefix {
            if character == " " {
                columns += 1
            } else if character == "\t" {
                columns += 4
            } else {
                break
            }
        }
        return min(columns, 24)
    }
}

/// The inputs of a cached paragraph style.
nonisolated private struct ParagraphKey: Hashable {
    var firstLineHeadIndent: Double
    var headIndent: Double
    var lineSpacing: Double
    var maxLineHeight: Double = 0
    var spacingBefore: Double
    var spacingAfter: Double
    var tabInterval: Double = 0
}

nonisolated private struct WidthKey: Hashable {
    var string: String
    var fontName: String
    var size: Double
}

private extension NSRange {
    init(_ textRange: MarkdownRange) {
        self.init(location: textRange.location, length: textRange.length)
    }
}
