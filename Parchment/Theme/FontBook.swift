import AppKit

/// A thread-safe font cache. The layout manager asks for fonts off the main actor.
///
/// `text` fonts are an old-style serif; `mono` fonts are SF Mono.
nonisolated final class FontBook: @unchecked Sendable {
    static let shared = FontBook()

    private struct Key: Hashable {
        /// Point size doubled and rounded, so sizes are bucketed to 0.5.
        let halfPoints: Int
        let weight: Double
        let italic: Bool
        let mono: Bool
    }

    private let lock = NSLock()
    private var cache: [Key: NSFont] = [:]

    func text(size: Double, weight: NSFont.Weight = .regular, italic: Bool = false) -> NSFont {
        font(size: size, weight: weight, italic: italic, mono: false)
    }

    func mono(size: Double, weight: NSFont.Weight = .regular, italic: Bool = false) -> NSFont {
        font(size: size, weight: weight, italic: italic, mono: true)
    }

    /// Returns `font` made bold and/or italic, keeping its size and family kind (system or monospaced).
    func adding(bold: Bool, italic: Bool, to font: NSFont) -> NSFont {
        let isMono = font.fontDescriptor.symbolicTraits.contains(.monoSpace)
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        let current = (traits?[.weight] as? NSNumber)?.doubleValue ?? Double(NSFont.Weight.regular.rawValue)
        let weight = bold ? max(current, Double(NSFont.Weight.bold.rawValue)) : current
        let isItalic = italic || font.fontDescriptor.symbolicTraits.contains(.italic)
        return self.font(size: font.pointSize, weight: NSFont.Weight(rawValue: weight), italic: isItalic, mono: isMono)
    }

    private func font(size: Double, weight: NSFont.Weight, italic: Bool, mono: Bool) -> NSFont {
        let key = Key(halfPoints: Int((size * 2).rounded()), weight: Double(weight.rawValue), italic: italic, mono: mono)
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }

        let pointSize = Double(key.halfPoints) / 2
        let result: NSFont
        if mono {
            let upright = NSFont.monospacedSystemFont(ofSize: pointSize, weight: weight)
            if italic {
                let descriptor = upright.fontDescriptor.withSymbolicTraits(.italic)
                result = NSFont(descriptor: descriptor, size: pointSize) ?? upright
            } else {
                result = upright
            }
        } else {
            result = Self.serif(size: pointSize, weight: weight, italic: italic)
        }
        cache[key] = result
        return result
    }

    /// Text is set in Iowan Old Style, a bookish serif that ships with macOS. It has Roman,
    /// Bold and Black faces, so lighter weights use Roman, semibold and bold use Bold, and
    /// heavier weights use Black. If it is missing, New York (the system serif) stands in.
    private static func serif(size: Double, weight: NSFont.Weight, italic: Bool) -> NSFont {
        let face: String = switch weight.rawValue {
        case ..<0.29: italic ? "IowanOldStyle-Italic" : "IowanOldStyle-Roman"
        case ..<0.5: italic ? "IowanOldStyle-BoldItalic" : "IowanOldStyle-Bold"
        default: italic ? "IowanOldStyle-BlackItalic" : "IowanOldStyle-Black"
        }
        if let font = NSFont(name: face, size: size) {
            return font
        }
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        var descriptor = system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor
        if italic {
            descriptor = descriptor.withSymbolicTraits(.italic)
        }
        return NSFont(descriptor: descriptor, size: size) ?? system
    }
}
