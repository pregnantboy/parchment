import AppKit

/// Draws the decorations that make the Ink look: code block backgrounds, inline code pills,
/// quote bars, rule lines, task circles, and inline images.
///
/// `NSLayoutManager` is not main-actor isolated, so this class is `nonisolated` and its drawing
/// reads only the text storage's attributes, `Palette`, `BlockDecoration`, `FontBook`, and its
/// own `gutter`, which the text view sets on the main actor before drawing.
nonisolated final class MarkdownLayoutManager: NSLayoutManager {
    /// The hanging gutter width, in container coordinates. Code backgrounds and quote bars align to it.
    var gutter: CGFloat = 64

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

    private func drawDecorations(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage, storage.length > 0, glyphsToShow.length > 0,
              let context = NSGraphicsContext.current?.cgContext else { return }
        let characters = storage.mutableString
        let length = storage.length

        enumerateLineFragments(forGlyphRange: glyphsToShow) { rect, usedRect, container, glyphRange, _ in
            let charRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            guard charRange.location < length, charRange.length > 0 else { return }

            let end = NSMaxRange(charRange)
            let line = LineFragment(
                rect: rect,
                usedRect: usedRect,
                containerWidth: container.size.width,
                startsLine: charRange.location == 0 || characters.character(at: charRange.location - 1) == Self.newline,
                endsLine: end >= length || characters.character(at: end - 1) == Self.newline,
                endsWithBreak: end <= length && characters.character(at: end - 1) == Self.newline
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
            if line.endsWithBreak, let image = attributes[.parchmentImage] as? NSImage,
               let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle {
                self.drawImage(image, line: line, paragraph: paragraph, origin: origin, in: context)
            }
            storage.enumerateAttribute(.parchmentInlineCode, in: charRange, options: []) { value, codeRange, _ in
                guard value != nil else { return }
                self.drawInlineCodePill(codeRange, fragmentRect: rect, container: container, origin: origin, in: context)
            }
            storage.enumerateAttribute(.parchmentTaskBox, in: charRange, options: []) { value, boxRange, _ in
                guard let isChecked = (value as? NSNumber)?.boolValue else { return }
                self.drawTaskCircle(boxRange: boxRange, isChecked: isChecked, fragmentRect: rect, container: container, origin: origin, in: context)
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
    /// height of the hyphens.
    private func drawRule(_ line: LineFragment, font: NSFont, baseline: CGFloat, origin: NSPoint, in context: CGContext) {
        let startX = origin.x + line.usedRect.maxX + Self.ruleGap
        let endX = origin.x + line.containerWidth
        guard endX > startX else { return }
        let midY = origin.y + baseline - font.xHeight / 2
        Palette.rule.setFill()
        context.fill(CGRect(x: startX, y: (midY - 0.5).rounded(), width: endX - startX, height: 1))
    }

    // MARK: - Tasks

    /// Replaces the transparent `[ ]` or `[x]` with a circle centered on the box glyphs and on
    /// the text's cap-height midline.
    private func drawTaskCircle(boxRange: NSRange, isChecked: Bool, fragmentRect: CGRect, container: NSTextContainer, origin: NSPoint, in context: CGContext) {
        guard let storage = textStorage, NSMaxRange(boxRange) <= storage.length else { return }
        let glyphs = glyphRange(forCharacterRange: boxRange, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return }
        let boxRect = boundingRect(forGlyphRange: glyphs, in: container)
        let font = (storage.attribute(.font, at: boxRange.location, effectiveRange: nil) as? NSFont) ?? FontBook.shared.text(size: 18)

        let diameter = max(10, font.pointSize.rounded())
        let baseline = fragmentRect.minY + location(forGlyphAt: glyphs.location).y
        let center = CGPoint(x: origin.x + boxRect.midX, y: origin.y + baseline - font.capHeight / 2)
        let circle = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        let scale = font.pointSize / 18

        context.saveGState()
        if isChecked {
            Palette.accent.setFill()
            context.fillEllipse(in: circle)

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
            Palette.ink.setStroke()
            context.setLineWidth(lineWidth)
            context.strokeEllipse(in: circle.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
        }
        context.restoreGState()
    }

    // MARK: - Images

    /// Draws an image in the paragraph spacing the styler reserved below its line. The spacing
    /// is the image height plus 24pt of padding, so the size is recovered from it exactly.
    private func drawImage(_ image: NSImage, line: LineFragment, paragraph: NSParagraphStyle, origin: NSPoint, in context: CGContext) {
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
        context.addPath(Self.roundedPath(destination, radius: Self.imageRadius))
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
