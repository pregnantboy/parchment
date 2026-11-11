import AppKit
import ParchmentCore

/// Draws the decorations that make the Ink look: code block backgrounds, inline code pills,
/// quote bars, rule lines, task circles, bullets, inline images, and wet ink.
///
/// It is its own delegate, to hide the glyphs of Markdown symbols in reading mode.
///
/// `NSLayoutManager` is not main-actor isolated, so this class is `nonisolated` and its drawing
/// reads only the text storage's attributes, `Palette`, `BlockDecoration`, `FontBook`, and its
/// own settings, which the text view sets on the main actor before drawing.
nonisolated final class MarkdownLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    /// The hanging gutter width, in container coordinates. Code backgrounds and quote bars align to it.
    var gutter: CGFloat = 64
    /// Reading mode: rules span the whole measure, since their `---` is transparent.
    var isReading = false
    /// Wax-seal tasks, filigree rules, diamond bullets and a large quote mark.
    var ornaments = false
    /// Recently typed text still drying. The text view adds and expires drops.
    var inkDrops: [InkDrop] = []

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delegate = self
    }

    // Claude effects, set by the text view on the main actor before drawing.

    /// Line starts of the steps Claude is working on. Their open task circles turn vermilion and pulse.
    var activeTaskLines: Set<Int> = []
    /// 0...1: how far the current pulse ring has spread.
    var taskPulse: CGFloat = 0
    var animatesTasks = true
    /// Task boxes Claude just ticked, by the location of their `[`, with fill progress 0...1.
    var taskFills: [Int: CGFloat] = [:]

    /// Horizontal padding inside an inline code pill. The styler kerns the characters around
    /// the code by the same amount so the pill has room.
    static let inlineCodePadding: CGFloat = 4
    private static let inlineCodeRadius: CGFloat = 5
    /// How far the pill reaches above the ascender and below the descender.
    private static let inlineCodeVerticalPadding: CGFloat = 1

    private static let codeBlockOverhang: CGFloat = 22
    private static let codeBlockRadius: CGFloat = 12
    private static let codeBlockPadding: CGFloat = 10
    private static let quoteBarWidth: CGFloat = 4
    private static let ruleGap: CGFloat = 16
    private static let imageTopGap: CGFloat = 12
    private static let imageRadius: CGFloat = 12
    private static let newline: unichar = 10

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawDecorations(forGlyphRange: glyphsToShow, at: origin)
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        drawWetInk(forGlyphRange: glyphsToShow, at: origin)
    }

    // MARK: - Hidden syntax

    /// Gives characters marked `parchmentHidden` null glyphs, which take no room and draw nothing.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes charIndexes: UnsafePointer<Int>,
        font aFont: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let storage = layoutManager.textStorage, glyphRange.length > 0 else { return 0 }
        let count = glyphRange.length
        let first = charIndexes[0]
        let last = charIndexes[count - 1]
        guard first >= 0, last < storage.length, last >= first else { return 0 }

        var hasHidden = false
        storage.enumerateAttribute(.parchmentHidden, in: NSRange(location: first, length: last - first + 1), options: []) { value, _, stop in
            if value != nil {
                hasHidden = true
                stop.pointee = true
            }
        }
        guard hasHidden else { return 0 }

        var properties = Array(UnsafeBufferPointer(start: props, count: count))
        for index in 0..<count where storage.attribute(.parchmentHidden, at: charIndexes[index], effectiveRange: nil) != nil {
            properties[index] = .null
        }
        properties.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                layoutManager.setGlyphs(glyphs, properties: base, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
            }
        }
        return count
    }

    // MARK: - Hard-wrapped paragraphs

    /// In reading mode, a line break marked `parchmentSoftBreak` joins a hard-wrapped line to
    /// the one above: it is laid out as a space (or, after a Markdown hard break, as a line
    /// break inside the paragraph), so the joined lines share one paragraph and its indent.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt charIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        guard let storage = layoutManager.textStorage, charIndex < storage.length,
              let keepsLineBreak = storage.attribute(.parchmentSoftBreak, at: charIndex, effectiveRange: nil) as? NSNumber
        else { return action }
        // The `\r` of a `\r\n` takes no room; the `\n` does the joining.
        guard storage.mutableString.character(at: charIndex) == Self.newline else { return .zeroAdvancement }
        return keepsLineBreak.boolValue ? .lineBreak : .whitespace
    }

    /// A joined line break is as wide as a space in its font.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        boundingBoxForControlGlyphAt glyphIndex: Int,
        for textContainer: NSTextContainer,
        proposedLineFragment proposedRect: NSRect,
        glyphPosition: NSPoint,
        characterIndex charIndex: Int
    ) -> NSRect {
        guard let storage = layoutManager.textStorage, charIndex < storage.length else {
            return NSRect(origin: glyphPosition, size: .zero)
        }
        let font = (storage.attribute(.font, at: charIndex, effectiveRange: nil) as? NSFont) ?? FontBook.shared.text(size: 18)
        let width = (" " as NSString).size(withAttributes: [.font: font]).width
        return NSRect(x: glyphPosition.x, y: glyphPosition.y, width: width, height: 0)
    }

    /// Whether the character at `index` ends a paragraph: a line break reading mode doesn't join.
    private func endsParagraph(at index: Int, in storage: NSTextStorage) -> Bool {
        storage.mutableString.character(at: index) == Self.newline
            && storage.attribute(.parchmentSoftBreak, at: index, effectiveRange: nil) == nil
    }

    // MARK: - Wet ink

    /// Redraws drying text with a soft halo and extra density that fade as it dries, so a
    /// letter lands dark and blurred and settles into its crisp printed form.
    private func drawWetInk(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard !inkDrops.isEmpty, let storage = textStorage,
              let context = NSGraphicsContext.current?.cgContext else { return }
        let now = ProcessInfo.processInfo.systemUptime
        for drop in inkDrops {
            let progress = (now - drop.start) / InkDrop.duration
            guard progress >= 0, progress < 1, drop.range.length > 0,
                  NSMaxRange(drop.range) <= storage.length else { continue }
            let glyphs = NSIntersectionRange(glyphRange(forCharacterRange: drop.range, actualCharacterRange: nil), glyphsToShow)
            guard glyphs.length > 0 else { continue }

            let wetness = (1 - progress) * (1 - progress)
            let font = (storage.attribute(.font, at: drop.range.location, effectiveRange: nil) as? NSFont) ?? FontBook.shared.text(size: 18)
            let color = (storage.attribute(.foregroundColor, at: drop.range.location, effectiveRange: nil) as? NSColor) ?? Palette.ink
            guard color.alphaComponent > 0 else { continue }

            context.saveGState()
            context.setAlpha(CGFloat(0.6 * wetness))
            context.setShadow(offset: .zero, blur: font.pointSize * 0.4 * CGFloat(wetness), color: color.withAlphaComponent(0.9).cgColor)
            super.drawGlyphs(forGlyphRange: glyphs, at: origin)
            context.restoreGState()
        }
    }

    private func drawDecorations(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, storage.length > 0, glyphsToShow.length > 0,
              let context = NSGraphicsContext.current?.cgContext else { return }
        let length = storage.length

        enumerateLineFragments(forGlyphRange: glyphsToShow) { rect, usedRect, container, glyphRange, _ in
            let charRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            guard charRange.location < length, charRange.length > 0 else { return }

            let end = NSMaxRange(charRange)
            let line = LineFragment(
                rect: rect,
                usedRect: usedRect,
                containerWidth: container.size.width,
                startsLine: charRange.location == 0 || self.endsParagraph(at: charRange.location - 1, in: storage),
                endsLine: end >= length || self.endsParagraph(at: end - 1, in: storage),
                endsWithBreak: end <= length && self.endsParagraph(at: end - 1, in: storage)
            )
            let attributes = storage.attributes(at: charRange.location, effectiveRange: nil)
            let font = (attributes[.font] as? NSFont) ?? FontBook.shared.text(size: 18)
            let baseline = rect.minY + self.location(forGlyphAt: glyphRange.location).y

            if let raw = attributes[.parchmentBlock] as? NSNumber {
                let decoration = BlockDecoration(rawValue: raw.intValue)
                if decoration.contains(.code) {
                    self.drawCodeBackground(line, decoration: decoration, font: font, baseline: baseline, origin: origin, in: context)
                } else if decoration.contains(.quote) {
                    self.drawQuoteBar(line, decoration: decoration, font: font, baseline: baseline, origin: origin, in: context)
                }
            }
            if attributes[.parchmentRule] != nil {
                self.drawRule(line, font: font, baseline: baseline, origin: origin, in: context)
            }
            if let width = attributes[.parchmentTableRule] as? NSNumber, line.startsLine {
                self.drawTableRule(at: line.rect.midY, width: CGFloat(width.doubleValue), color: Palette.marker, origin: origin, in: context)
            }
            if let width = attributes[.parchmentTableRowRule] as? NSNumber, line.endsLine {
                self.drawTableRule(at: line.rect.maxY, width: CGFloat(width.doubleValue), color: Palette.rule, origin: origin, in: context)
            }
            if self.ornaments, line.startsLine, let raw = attributes[.parchmentBlock] as? NSNumber {
                let decoration = BlockDecoration(rawValue: raw.intValue)
                if decoration.contains(.quote), decoration.contains(.isFirst) {
                    self.drawQuoteMark(line, font: font, origin: origin)
                }
            }
            if line.endsWithBreak, let image = attributes[.parchmentImage] as? NSImage,
               let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle {
                let radius = attributes[.parchmentTable] == nil ? Self.imageRadius : 0
                self.drawImage(image, radius: radius, line: line, paragraph: paragraph, origin: origin, in: context)
            }
            storage.enumerateAttribute(.parchmentInlineCode, in: charRange, options: []) { value, codeRange, _ in
                guard value != nil else { return }
                self.drawInlineCodePill(codeRange, fragmentRect: rect, container: container, origin: origin, in: context)
            }
            storage.enumerateAttribute(.parchmentTaskBox, in: charRange, options: []) { value, boxRange, _ in
                guard let raw = (value as? NSNumber)?.intValue, let state = TaskState(rawValue: raw) else { return }
                self.drawTaskCircle(boxRange: boxRange, state: state, fragmentRect: rect, container: container, origin: origin, in: context)
            }
            storage.enumerateAttribute(.parchmentBullet, in: charRange, options: []) { value, bulletRange, _ in
                guard value != nil else { return }
                self.drawBullet(bulletRange, fragmentRect: rect, container: container, origin: origin, in: context)
            }
        }
    }

    // MARK: - Code blocks

    /// Fills one line fragment's slab of a code block. Each slab is clipped to its own rect and
    /// filled with a rounded rect stretched past any edge that continues into a neighbour, so
    /// only the block's outer corners round.
    private func drawCodeBackground(_ line: LineFragment, decoration: BlockDecoration, font: NSFont, baseline: CGFloat, origin: NSPoint, in context: CGContext) {
        let roundsTop = decoration.contains(.isFirst) && line.startsLine
        let roundsBottom = decoration.contains(.isLast) && line.endsLine
        let top = roundsTop ? baseline - font.ascender - Self.codeBlockPadding : line.rect.minY
        // Overlap the next slab by a point so antialiased edges never leave a seam.
        let bottom = roundsBottom ? baseline - font.descender + Self.codeBlockPadding : line.rect.maxY + 1
        guard bottom > top else { return }

        let left = origin.x + gutter - Self.codeBlockOverhang
        let right = origin.x + line.containerWidth + Self.codeBlockOverhang
        let slab = CGRect(x: left, y: origin.y + top, width: right - left, height: bottom - top)
        var shape = slab
        if !roundsTop {
            shape.origin.y -= Self.codeBlockRadius
            shape.size.height += Self.codeBlockRadius
        }
        if !roundsBottom {
            shape.size.height += Self.codeBlockRadius
        }

        context.saveGState()
        context.clip(to: slab)
        Palette.codeBackground.setFill()
        context.addPath(Self.roundedPath(shape, radius: Self.codeBlockRadius))
        context.fillPath()
        context.restoreGState()
    }

    // MARK: - Inline code

    /// Draws a rounded pill behind the part of an inline code span that sits on this line
    /// fragment. `enumerateAttribute` already clamps `codeRange` to the fragment, so wrapped
    /// code gets one snug pill per line instead of a slab reaching into the margin.
    private func drawInlineCodePill(_ codeRange: NSRange, fragmentRect: CGRect, container: NSTextContainer, origin: NSPoint, in context: CGContext) {
        guard let storage = textStorage else { return }
        let characters = storage.mutableString

        // Spaces at a wrap point hang past the line's edge; keep them out of the pill.
        var lower = codeRange.location
        var upper = NSMaxRange(codeRange)
        while lower < upper, Self.isSpace(characters.character(at: lower)) { lower += 1 }
        while upper > lower, Self.isSpace(characters.character(at: upper - 1)) { upper -= 1 }
        guard upper > lower else { return }
        let visible = NSRange(location: lower, length: upper - lower)

        let glyphs = glyphRange(forCharacterRange: visible, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        let bounds = boundingRect(forGlyphRange: glyphs, in: container)
        let font = (storage.attribute(.font, at: lower, effectiveRange: nil) as? NSFont) ?? FontBook.shared.mono(size: 15)
        let baseline = fragmentRect.minY + location(forGlyphAt: glyphs.location).y

        // The trailing kern only exists on the span's last character, so a piece that
        // continues onto the next line gets its right padding here instead.
        let endsSpan = upper == NSMaxRange(codeRange) && Self.hasKern(storage, at: upper - 1)
        let left = bounds.minX - Self.inlineCodePadding
        let right = endsSpan ? bounds.maxX : bounds.maxX + Self.inlineCodePadding
        let top = baseline - font.ascender - Self.inlineCodeVerticalPadding
        let bottom = baseline - font.descender + Self.inlineCodeVerticalPadding
        let pill = CGRect(x: origin.x + left, y: origin.y + top, width: right - left, height: bottom - top)

        context.saveGState()
        Palette.inlineCodeBackground.setFill()
        context.addPath(Self.roundedPath(pill, radius: Self.inlineCodeRadius))
        context.fillPath()
        context.restoreGState()
    }

    private static func isSpace(_ character: unichar) -> Bool {
        character == 32 || character == 9 || character == 10 || character == 13
    }

    private static func hasKern(_ storage: NSTextStorage, at index: Int) -> Bool {
        guard index >= 0, index < storage.length else { return false }
        return storage.attribute(.kern, at: index, effectiveRange: nil) != nil
    }

    // MARK: - Quotes

    private func drawQuoteBar(_ line: LineFragment, decoration: BlockDecoration, font: NSFont, baseline: CGFloat, origin: NSPoint, in context: CGContext) {
        let roundsTop = decoration.contains(.isFirst) && line.startsLine
        let roundsBottom = decoration.contains(.isLast) && line.endsLine
        let top = roundsTop ? baseline - font.ascender : line.rect.minY
        let bottom = roundsBottom ? baseline - font.descender : line.rect.maxY + 1
        guard bottom > top else { return }

        let radius = Self.quoteBarWidth / 2
        let slab = CGRect(x: origin.x + gutter, y: origin.y + top, width: Self.quoteBarWidth, height: bottom - top)
        var shape = slab
        if !roundsTop {
            shape.origin.y -= radius
            shape.size.height += radius
        }
        if !roundsBottom {
            shape.size.height += radius
        }

        context.saveGState()
        context.clip(to: slab)
        Palette.accent.setFill()
        context.addPath(Self.roundedPath(shape, radius: radius))
        context.fillPath()
        context.restoreGState()
    }

    // MARK: - Rules

    /// A hairline from just after the faint `---` to the right edge of the measure, at the
    /// height of the hyphens. In reading mode the `---` is transparent, so the line starts at
    /// the text edge. With ornaments, a filigree centered on the measure takes its place.
    private func drawRule(_ line: LineFragment, font: NSFont, baseline: CGFloat, origin: NSPoint, in context: CGContext) {
        let textEdge = origin.x + gutter
        let startX = isReading ? textEdge : origin.x + line.usedRect.maxX + Self.ruleGap
        let endX = origin.x + line.containerWidth
        guard endX > startX else { return }
        let midY = origin.y + baseline - font.xHeight / 2

        guard ornaments else {
            Palette.rule.setFill()
            context.fill(CGRect(x: startX, y: (midY - 0.5).rounded(), width: endX - startX, height: 1))
            return
        }
        // Centered on the measure, as wide as it can be without reaching the `---`.
        let center = (textEdge + endX) / 2
        let halfWidth = min(center - startX, (endX - textEdge) * 0.32)
        guard halfWidth > 12 else { return }
        let height = max(6, font.pointSize * 0.42)
        let rect = CGRect(x: center - halfWidth, y: midY - height / 2, width: halfWidth * 2, height: height)
        context.saveGState()
        Palette.accent.withAlphaComponent(0.75).setFill()
        context.addPath(OrnamentPath.flourish(in: rect))
        context.fillPath()
        context.restoreGState()
    }

    // MARK: - Tables

    /// A hairline across a table in reading mode, from the gutter edge.
    private func drawTableRule(at y: CGFloat, width: CGFloat, color: NSColor, origin: NSPoint, in context: CGContext) {
        guard width > 0 else { return }
        color.setFill()
        context.fill(CGRect(x: origin.x + gutter, y: (origin.y + y - 0.5).rounded(), width: width, height: 1))
    }

    // MARK: - Ornaments

    /// A large, faint opening quote mark behind the start of a quote block.
    private func drawQuoteMark(_ line: LineFragment, font: NSFont, origin: NSPoint) {
        let markFont = FontBook.shared.text(size: Double(font.pointSize) * 3.4, weight: .bold)
        let mark = NSAttributedString(string: "\u{201C}", attributes: [
            .font: markFont,
            .foregroundColor: Palette.accent.withAlphaComponent(0.16),
        ])
        let point = NSPoint(
            x: origin.x + gutter + Self.quoteBarWidth + 2,
            y: origin.y + line.rect.minY - markFont.pointSize * 0.22
        )
        mark.draw(at: point)
    }

    /// A dot, or a small accent diamond with ornaments, centered on a transparent bullet marker.
    private func drawBullet(_ range: NSRange, fragmentRect: CGRect, container: NSTextContainer, origin: NSPoint, in context: CGContext) {
        guard let storage = textStorage, NSMaxRange(range) <= storage.length else { return }
        let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        let bounds = boundingRect(forGlyphRange: glyphs, in: container)
        let font = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont) ?? FontBook.shared.text(size: 18)
        let baseline = fragmentRect.minY + location(forGlyphAt: glyphs.location).y
        let center = CGPoint(x: origin.x + bounds.midX, y: origin.y + baseline - font.xHeight / 2)

        context.saveGState()
        if ornaments {
            Palette.accent.setFill()
            context.addPath(OrnamentPath.diamond(center: center, radius: max(2.5, font.pointSize * 0.2)))
            context.fillPath()
        } else {
            Palette.muted.setFill()
            let radius = max(2, font.pointSize * 0.13)
            context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        context.restoreGState()
    }

    // MARK: - Tasks

    /// Replaces the transparent `[ ]`, `[/]`, `[!]` or `[x]` with a circle on the text's
    /// cap-height midline. It is centered on where an empty `[ ]` would sit, measured back from
    /// the box's right edge, so the circles line up even though the marks differ in width.
    /// In progress is a half-filled vermilion circle; blocked is a vermilion circle with a bar.
    private func drawTaskCircle(boxRange: NSRange, state: TaskState, fragmentRect: CGRect, container: NSTextContainer, origin: NSPoint, in context: CGContext) {
        guard let storage = textStorage, NSMaxRange(boxRange) <= storage.length else { return }
        let glyphs = glyphRange(forCharacterRange: boxRange, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        let boxRect = boundingRect(forGlyphRange: glyphs, in: container)
        let font = (storage.attribute(.font, at: boxRange.location, effectiveRange: nil) as? NSFont) ?? FontBook.shared.text(size: 18)

        let diameter = max(10, font.pointSize.rounded())
        let baseline = fragmentRect.minY + location(forGlyphAt: glyphs.location).y
        let emptyBoxWidth = ("[ ]" as NSString).size(withAttributes: [.font: font]).width
        let center = CGPoint(x: origin.x + boxRect.maxX - emptyBoxWidth / 2, y: origin.y + baseline - font.capHeight / 2)
        let circle = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        let scale = font.pointSize / 18
        let lineStart = storage.mutableString.lineRange(for: NSRange(location: boxRange.location, length: 0)).location
        let isChecked = state == .done
        let isActive = (state == .open || state == .inProgress) && activeTaskLines.contains(lineStart)

        context.saveGState()
        let fill = isChecked ? (taskFills[boxRange.location] ?? 1) : 0
        if state == .blocked {
            drawBlockedMark(in: circle, scale: scale, sealShaped: ornaments, context: context)
        } else if state == .inProgress {
            drawInProgressMark(in: circle, scale: scale, sealShaped: ornaments, context: context)
        } else if ornaments {
            drawWaxSeal(in: circle, isChecked: isChecked, fill: fill, isActive: isActive, scale: scale, context: context)
        } else if isChecked {
            // Claude just ticked it: the fill grows from the center, then the check appears.
            if fill < 1 {
                let lineWidth = max(1.5, 2 * scale)
                Palette.ink.setStroke()
                context.setLineWidth(lineWidth)
                context.strokeEllipse(in: circle.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
            }
            let eased = 1 - (1 - fill) * (1 - fill)
            let inset = diameter * (1 - eased) / 2
            Palette.accent.setFill()
            context.fillEllipse(in: circle.insetBy(dx: inset, dy: inset))

            context.setAlpha(min(1, max(0, (fill - 0.5) * 2)))
            NSColor.white.setStroke()
            context.setLineWidth(max(1.5, 2 * scale))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.move(to: CGPoint(x: circle.minX + diameter * 0.28, y: circle.minY + diameter * 0.53))
            context.addLine(to: CGPoint(x: circle.minX + diameter * 0.44, y: circle.minY + diameter * 0.68))
            context.addLine(to: CGPoint(x: circle.minX + diameter * 0.72, y: circle.minY + diameter * 0.36))
            context.strokePath()
        } else {
            let lineWidth = max(1.5, 2 * scale)
            (isActive ? Palette.accent : Palette.ink).setStroke()
            context.setLineWidth(lineWidth)
            context.strokeEllipse(in: circle.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
        }
        if isActive && animatesTasks {
            // A ring that spreads out and fades, once per pulse.
            let spread = 7 * scale * taskPulse
            context.setLineDash(phase: 0, lengths: [])
            Palette.accent.withAlphaComponent(0.55 * (1 - taskPulse)).setStroke()
            context.setLineWidth(max(1, 1.5 * scale))
            context.strokeEllipse(in: circle.insetBy(dx: -spread, dy: -spread))
        }
        context.restoreGState()
    }

    /// A vermilion disc (or seal) with a pale bar across it, like a no-entry sign.
    private func drawBlockedMark(in circle: CGRect, scale: CGFloat, sealShaped: Bool, context: CGContext) {
        let center = CGPoint(x: circle.midX, y: circle.midY)
        Palette.accent.setFill()
        if sealShaped {
            context.addPath(OrnamentPath.waxSeal(center: center, radius: circle.width / 2))
            context.fillPath()
        } else {
            context.fillEllipse(in: circle)
        }
        let barHeight = max(1.5, 2.2 * scale)
        let barWidth = circle.width * 0.52
        let bar = CGRect(x: center.x - barWidth / 2, y: center.y - barHeight / 2, width: barWidth, height: barHeight)
        Palette.paper.setFill()
        context.addPath(CGPath(roundedRect: bar, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2, transform: nil))
        context.fillPath()
    }

    /// A vermilion outline (or seal outline) with its left half filled.
    private func drawInProgressMark(in circle: CGRect, scale: CGFloat, sealShaped: Bool, context: CGContext) {
        let center = CGPoint(x: circle.midX, y: circle.midY)
        let lineWidth = max(1.5, 2 * scale)
        let outline: CGPath = sealShaped
            ? OrnamentPath.waxSeal(center: center, radius: circle.width / 2 - lineWidth / 2)
            : CGPath(ellipseIn: circle.insetBy(dx: lineWidth / 2, dy: lineWidth / 2), transform: nil)
        context.saveGState()
        context.addPath(outline)
        context.clip()
        Palette.accent.setFill()
        context.fill(CGRect(x: circle.minX, y: circle.minY, width: circle.width / 2, height: circle.height))
        context.restoreGState()
        Palette.accent.setStroke()
        context.setLineWidth(lineWidth)
        context.addPath(outline)
        context.strokePath()
    }

    /// Checked: a poured wax seal with a pressed ring and a pale gold check. Unchecked: the
    /// faint outline of where a seal will go.
    /// `fill` (0...1) grows a seal Claude just ticked from the center; `isActive` marks a step
    /// Claude is working on.
    private func drawWaxSeal(in circle: CGRect, isChecked: Bool, fill: CGFloat, isActive: Bool, scale: CGFloat, context: CGContext) {
        let center = CGPoint(x: circle.midX, y: circle.midY)
        let fullRadius = circle.width / 2
        guard isChecked else {
            let radius = fullRadius
            let lineWidth = max(1.2, 1.5 * scale)
            (isActive ? Palette.accent : Palette.muted).setStroke()
            context.setLineWidth(lineWidth)
            context.addPath(OrnamentPath.waxSeal(center: center, radius: radius - lineWidth / 2))
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [1.5 * scale, 2 * scale])
            context.setLineWidth(max(0.8, scale))
            context.strokeEllipse(in: circle.insetBy(dx: radius * 0.32, dy: radius * 0.32))
            return
        }

        let eased = 1 - (1 - fill) * (1 - fill)
        let radius = fullRadius * max(0.05, eased)
        Palette.wax.setFill()
        context.addPath(OrnamentPath.waxSeal(center: center, radius: radius * 1.05))
        context.fillPath()

        context.setAlpha(min(1, max(0, (fill - 0.5) * 2)))

        Palette.waxShade.setStroke()
        context.setLineWidth(max(0.8, scale))
        context.strokeEllipse(in: circle.insetBy(dx: fullRadius * 0.24, dy: fullRadius * 0.24))

        Palette.waxMark.setStroke()
        context.setLineWidth(max(1.3, 1.7 * scale))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let diameter = circle.width
        context.move(to: CGPoint(x: circle.minX + diameter * 0.32, y: circle.minY + diameter * 0.52))
        context.addLine(to: CGPoint(x: circle.minX + diameter * 0.45, y: circle.minY + diameter * 0.65))
        context.addLine(to: CGPoint(x: circle.minX + diameter * 0.69, y: circle.minY + diameter * 0.38))
        context.strokePath()
    }

    // MARK: - Images

    /// Draws an image in the paragraph spacing the styler reserved below its line. The spacing
    /// is the image height plus 24pt of padding, so the size is recovered from it exactly.
    private func drawImage(_ image: NSImage, radius: CGFloat, line: LineFragment, paragraph: NSParagraphStyle, origin: NSPoint, in context: CGContext) {
        let size = image.size
        let height = paragraph.paragraphSpacing - Self.imageTopGap * 2
        guard size.width > 0, size.height > 0, height > 1 else { return }
        let width = height * size.width / size.height
        let destination = CGRect(
            x: origin.x + gutter,
            y: origin.y + line.rect.maxY - Self.imageTopGap - height,
            width: width,
            height: height
        )

        context.saveGState()
        context.addPath(Self.roundedPath(destination, radius: radius))
        context.clip()
        image.draw(
            in: destination,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)]
        )
        context.restoreGState()
    }

    // MARK: - Helpers

    private static func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let corner = max(0, min(radius, rect.width / 2, rect.height / 2))
        return CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    }
}

/// Text typed moments ago, still drying.
nonisolated struct InkDrop: Sendable {
    /// How long ink takes to dry, in seconds.
    static let duration: TimeInterval = 0.7

    var range: NSRange
    /// `ProcessInfo.systemUptime` when the text was typed.
    var start: TimeInterval
}

/// One line fragment being decorated, in container coordinates.
nonisolated private struct LineFragment {
    var rect: CGRect
    var usedRect: CGRect
    var containerWidth: CGFloat
    /// The fragment begins a Markdown line rather than continuing a wrapped one.
    var startsLine: Bool
    /// The fragment holds the end of its Markdown line.
    var endsLine: Bool
    /// The line ends with a line break, so its paragraph spacing exists.
    var endsWithBreak: Bool
}
