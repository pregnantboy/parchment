import AppKit

/// Layout numbers derived from the user's text size and line height. Everything scales with `fontSize`.
nonisolated struct EditorMetrics: Equatable, Sendable {
    static let defaultFontSize = 15.0
    static let fontSizeRange = 12.0...28.0
    /// Body line height as a multiple of the text size.
    static let defaultLineHeight = 1.5
    static let lineHeightRange = 0.8...2.2

    let fontSize: Double
    let lineHeight: Double
    let measure: Double
    let gutter: Double
    let codeFontSize: Double
    let lineSpacing: Double
    /// The tallest a body line may be, or 0 for no limit. Set only when `lineHeight` is tighter
    /// than the font's own line height, since `lineSpacing` can only add space.
    let maxLineHeight: Double
    let paragraphSpacing: Double
    let topInset: Double

    /// Clamps `fontSize` and `lineHeight` into their ranges before deriving the other values.
    init(fontSize: Double, lineHeight: Double = defaultLineHeight) {
        let size = min(max(fontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        let height = min(max(lineHeight, Self.lineHeightRange.lowerBound), Self.lineHeightRange.upperBound)
        self.fontSize = size
        self.lineHeight = height
        measure = size * 36.7
        gutter = size * 3.55
        codeFontSize = size * 0.8
        // The font's own line height already includes some leading; add what is missing.
        let body = FontBook.shared.text(size: size)
        let natural = Double(body.ascender - body.descender + body.leading)
        let target = size * height
        lineSpacing = max(0, target - natural).rounded()
        maxLineHeight = target < natural ? target.rounded() : 0
        paragraphSpacing = (size * 0.9).rounded()
        topInset = 28
    }

    func headingSize(level: Int) -> Double {
        switch level {
        case 1: fontSize * 2.667
        case 2: fontSize * 1.556
        case 3: fontSize * 1.167
        default: fontSize
        }
    }

    func headingSpacingBefore(level: Int) -> Double {
        switch level {
        case 1: 0
        case 2: fontSize * 2.2
        case 3: fontSize * 1.6
        default: fontSize * 1.2
        }
    }

    /// Letter spacing in points (the design specifies it in em, relative to the heading size).
    func headingKern(level: Int) -> Double {
        switch level {
        case 1: -0.035 * headingSize(level: level)
        case 2: -0.02 * headingSize(level: level)
        default: 0
        }
    }

    func headingWeight(level: Int) -> NSFont.Weight {
        switch level {
        case 1: .heavy
        case 2, 3: .bold
        default: .semibold
        }
    }
}
