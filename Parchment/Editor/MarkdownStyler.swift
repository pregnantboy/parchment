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

    /// The text view whose typing attributes and storage this styler manages.
    weak var textView: NSTextView?

    /// The text of the most recent parse, in sync with the storage after every `restyle`.
    private(set) var text = MarkdownText(units: [])
    private(set) var lines: [MarkdownLine] = []

    /// Horizontal room for images, measured from the gutter edge to the window's right side.
    private var availableImageWidth = Double.infinity
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
        let changed: Range<Int> = if full || lines.isEmpty {
            0..<newLines.count
        } else {
            LineDiff.changedLines(old: text, oldLines: lines, new: newText, newLines: newLines)
        }
        text = newText
        lines = newLines

        var indices = IndexSet(integersIn: changed)
        if !full, let selection = textView?.selectedRange(), selection.location != NSNotFound {
            indices.formUnion(lineIndices(touching: selection))
        }
        restyleLines(indices, in: storage)
        updateTypingAttributes()
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

    private func updateTypingAttributes() {
        guard let textView, !textView.hasMarkedText() else { return }
        textView.typingAttributes = bodyAttributes
    }

    private func restyleLines(_ indices: IndexSet, in storage: NSTextStorage) {
        guard !indices.isEmpty else { return }
        storage.beginEditing()
        for index in indices where index < lines.count {
            style(lines[index], in: storage)
        }
        storage.endEditing()
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

    private func style(_ line: MarkdownLine, in storage: NSTextStorage) {
        let fullRange = NSRange(line.fullRange)
        guard fullRange.length > 0, NSMaxRange(fullRange) <= storage.length else { return }
        let body = FontBook.shared.text(size: metrics.fontSize)

        switch line.kind {
        case .blank:
            storage.setAttributes(attributes(font: body, color: Palette.ink, paragraph: bodyParagraph(spacingAfter: 0)), range: fullRange)

        case .paragraph:
            storage.setAttributes(attributes(font: body, color: Palette.ink, paragraph: bodyParagraph(spacingAfter: metrics.paragraphSpacing)), range: fullRange)

        case .heading(let level):
            styleHeading(line, level: level, in: storage)

        case .listItem, .task:
            styleListItem(line, in: storage)

        case .quote:
            styleQuote(line, in: storage)

        case .fence:
            styleCode(line, color: Palette.codeFence, in: storage)

        case .code:
            styleCode(line, color: Palette.codeText, in: storage)

        case .tableHeader, .tableDelimiter, .tableRow:
            styleTable(line, in: storage)

        case .rule:
            storage.setAttributes(attributes(font: body, color: Palette.marker, paragraph: bodyParagraph(spacingAfter: metrics.paragraphSpacing)), range: fullRange)
            let lineRange = NSRange(line.range)
            if lineRange.length > 0 {
                storage.addAttribute(.parchmentRule, value: NSNumber(value: true), range: lineRange)
            }

        case .image(let source):
            styleImage(line, source: source, in: storage)
        }

        applySpans(MarkdownParser.spans(for: line, in: text), line: line, in: storage)
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
            storage.addAttributes([.font: prefixFont, .foregroundColor: Palette.accent], range: prefix)
        }
        let tracking = Self.headingTracking(level: level) * size
        let content = NSRange(line.contentRange)
        if tracking != 0, content.length > 0 {
            storage.addAttribute(.tracking, value: NSNumber(value: tracking), range: content)
        }
    }

    /// Lists and tasks hang their whole prefix (indent, marker, and box) in the gutter, and
    /// nested items move the text edge right by 1.5em per four columns of indentation.
    private func styleListItem(_ line: MarkdownLine, in storage: NSTextStorage) {
        let body = FontBook.shared.text(size: metrics.fontSize)
        let prefix = text.string(in: line.prefixRange)
        let nesting = Double(Self.indentColumns(of: prefix)) * metrics.fontSize * 0.375
        let headIndent = gutter + nesting
        let paragraph = paragraphStyle(ParagraphKey(
            firstLineHeadIndent: max(0, headIndent - width(of: prefix, font: body)),
            headIndent: headIndent,
            lineSpacing: metrics.lineSpacing,
            spacingBefore: 0,
            spacingAfter: (metrics.paragraphSpacing * 0.35).rounded()
        ))
        storage.setAttributes(attributes(font: body, color: Palette.ink, paragraph: paragraph), range: NSRange(line.fullRange))
    }

    /// Quotes are set larger and semibold. The `>` hangs left of the bar at the gutter edge,
    /// and a kern on the last prefix character carries the text to its indented edge.
    private func styleQuote(_ line: MarkdownLine, in storage: NSTextStorage) {
        let size = metrics.fontSize * 1.28
        let font = FontBook.shared.text(size: size, weight: .semibold)
        let prefixWidth = width(of: text.string(in: line.prefixRange), font: font)
        let firstIndent = max(0, gutter - Self.quoteMarkerGap - prefixWidth)
        let textEdge = gutter + Self.quoteTextOffset
        let isLast = line.blockPosition.isLast

        let paragraph = paragraphStyle(ParagraphKey(
            firstLineHeadIndent: firstIndent,
            headIndent: textEdge,
            lineSpacing: (size * 0.35).rounded(),
            spacingBefore: 0,
            spacingAfter: isLast ? metrics.paragraphSpacing : 0
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

    private func styleTable(_ line: MarkdownLine, in storage: NSTextStorage) {
        let font = FontBook.shared.mono(size: metrics.fontSize * 0.85)
        let paragraph = paragraphStyle(ParagraphKey(
            firstLineHeadIndent: gutter,
            headIndent: gutter,
            lineSpacing: (metrics.lineSpacing * 0.6).rounded(),
            spacingBefore: 0,
            spacingAfter: line.blockPosition.isLast ? metrics.paragraphSpacing : 0
        ))
        let color = line.kind == .tableDelimiter ? Palette.marker : Palette.ink
        storage.setAttributes(attributes(font: font, color: color, paragraph: paragraph), range: NSRange(line.fullRange))
    }

    /// Image lines show their source in marker color. A loaded image reserves its height as
    /// paragraph spacing; the layout manager draws it there. The last line of a document has
    /// no paragraph spacing to reserve, so its image appears once the line ends with a break.
    private func styleImage(_ line: MarkdownLine, source: String, in storage: NSTextStorage) {
        let body = FontBook.shared.text(size: metrics.fontSize)
        var spacingAfter = metrics.paragraphSpacing
        var image: NSImage?
        if line.lineBreakLength > 0, let loaded = loadedImage(for: source) {
            image = loaded.image
            spacingAfter = loaded.height + Self.imageVerticalPadding
        }
        storage.setAttributes(attributes(font: body, color: Palette.marker, paragraph: bodyParagraph(spacingAfter: spacingAfter)), range: NSRange(line.fullRange))
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

        for span in ordered {
            let range = NSRange(span.range)
            guard range.length > 0, NSMaxRange(range) <= storage.length else { continue }

            switch span.kind {
            case .syntax:
                // Fence lines keep their code colors, and the hanging heading `#`s stay accent.
                if isCode { continue }
                if let headingContentStart, span.range.location < headingContentStart { continue }
                storage.addAttribute(.foregroundColor, value: Palette.marker, range: range)

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
                    .backgroundColor: Palette.inlineCodeBackground,
                ], range: range)

            case .linkText(let destination):
                var linkAttributes: [NSAttributedString.Key: Any] = [
                    .foregroundColor: Palette.ink,
                    .underlineStyle: NSNumber(value: NSUnderlineStyle.thick.rawValue),
                    .underlineColor: Palette.accent,
                ]
                if !destination.isEmpty { linkAttributes[.parchmentLink] = destination }
                storage.addAttributes(linkAttributes, range: range)

            case .linkDestination(let destination):
                storage.addAttribute(.foregroundColor, value: Palette.marker, range: range)
                if !destination.isEmpty {
                    storage.addAttribute(.parchmentLink, value: destination, range: range)
                }

            case .listMarker, .quoteMarker:
                storage.addAttribute(.foregroundColor, value: Palette.marker, range: range)

            case .taskBox(let isChecked):
                storage.addAttributes([
                    .foregroundColor: NSColor.clear,
                    .parchmentTaskBox: NSNumber(value: isChecked),
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
