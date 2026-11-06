import AppKit

/// Layout numbers derived from the user's text size. Everything scales with `fontSize`.
nonisolated struct EditorMetrics: Equatable, Sendable {
    static let defaultFontSize = 18.0
    static let fontSizeRange = 12.0...28.0

    let fontSize: Double
    let measure: Double
    let gutter: Double
    let codeFontSize: Double
    let lineSpacing: Double
    let paragraphSpacing: Double
    let topInset: Double

    /// Clamps `fontSize` into `fontSizeRange` before deriving the other values.
    init(fontSize: Double) {
        let size = min(max(fontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        self.fontSize = size
        measure = size * 36.7
        gutter = size * 3.55
        codeFontSize = size * 0.8
        lineSpacing = (size * 0.5).rounded()
        paragraphSpacing = size
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
