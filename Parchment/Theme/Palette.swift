import AppKit
import ParchmentCore

/// The Ink color tokens. Every token is a dynamic color that resolves per appearance.
///
/// Tokens are computed properties because `NSColor` is not `Sendable`, so it cannot live in
/// a static stored property of a nonisolated type.
nonisolated enum Palette {
    static var paper: NSColor { dynamic(light: 0xF7F3EA, dark: 0x121110) }
    static var ink: NSColor { dynamic(light: 0x17130F, dark: 0xF3EDE3) }
    static var muted: NSColor { dynamic(light: 0x6B6155, dark: 0xA39788) }
    static var marker: NSColor { dynamic(light: 0xA89C8B, dark: 0x5E544A) }
    static var accent: NSColor { dynamic(light: 0xC8441F, dark: 0xFF7A4D) }
    static var dimmed: NSColor { dynamic(light: 0xD3C9BA, dark: 0x3A342E) }
    static var codeBackground: NSColor { dynamic(light: 0x1C1814, dark: 0x24201C) }
    static var codeText: NSColor { dynamic(light: 0xEDE6DA, dark: 0xEDE6DA) }
    static var codeFence: NSColor { dynamic(light: 0x6E6458, dark: 0x6E6458) }
    static var rule: NSColor { dynamic(light: 0xE5DCCD, dark: 0x2C2723) }

    /// Accent at 11% alpha in light mode, 14% in dark mode.
    static var inlineCodeBackground: NSColor {
        dynamic(light: 0xC8441F, lightAlpha: 0.11, dark: 0xFF7A4D, darkAlpha: 0.14)
    }

    /// Accent at 18% alpha in light mode, 28% in dark mode.
    static var selection: NSColor {
        dynamic(light: 0xC8441F, lightAlpha: 0.18, dark: 0xFF7A4D, darkAlpha: 0.28)
    }

    /// Syntax colors inside code blocks. They sit on a dark background in both modes.
    static func color(for token: CodeTokenKind) -> NSColor {
        switch token {
        case .keyword: srgb(0xFF8A5C)
        case .string: srgb(0xB7D67E)
        case .comment: srgb(0x8A7F72)
        case .number: srgb(0xF2C46B)
        case .type: srgb(0x8EC3E6)
        }
    }

    private static func dynamic(
        light: UInt32,
        lightAlpha: Double = 1,
        dark: UInt32,
        darkAlpha: Double = 1
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                srgb(dark, alpha: darkAlpha)
            } else {
                srgb(light, alpha: lightAlpha)
            }
        }
    }

    private static func srgb(_ hex: UInt32, alpha: Double = 1) -> NSColor {
        NSColor(
            srgbRed: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
