import AppKit
import MarkdownUI
import SwiftUI

/// Draws a Markdown table as a real grid for reading mode, using MarkdownUI. The result is a
/// picture the styler places like an inline image, so it scrolls and lays out with the text.
///
/// Each table is rendered once for light and once for dark, and the picture picks the
/// right one when it is drawn, so switching appearance needs no restyle.
@MainActor
final class TableRenderer {
    static let shared = TableRenderer()

    struct Rendered {
        let image: NSImage
        let height: Double
    }

    private struct Key: Hashable {
        let source: String
        let fontSize: Double
    }

    private var cache: [Key: Rendered] = [:]
    private static let cacheLimit = 64
    private static let scale = 2.0
    /// The widest a column grows, in ems (the text column is about 37). Longer cells wrap inside it, so a table with prose
    /// cells gets tall rows rather than a column wider than the window.
    private static let maxColumnEm = 30.0
    /// Tables wider than this aren't drawn as a grid, to keep the picture's memory in check.
    private static let maxImageWidth = 8000.0

    /// The table in `source` (its header, `---|---` row and body rows) rendered at its natural
    /// width, or `nil` if it can't be drawn. The picture doesn't depend on the window, so it
    /// is drawn once, not on every resize; the text view scrolls it sideways when it is wider
    /// than the column.
    func render(_ source: String, fontSize: Double) -> Rendered? {
        guard !source.isEmpty else { return nil }
        let key = Key(source: source, fontSize: fontSize)
        if let cached = cache[key] { return cached }

        guard let light = Self.snapshot(source, fontSize: fontSize, dark: false),
              let dark = Self.snapshot(source, fontSize: fontSize, dark: true) else { return nil }
        let size = NSSize(width: Double(light.width) / Self.scale, height: Double(light.height) / Self.scale)
        guard size.width > 0, size.height > 0, size.width <= Self.maxImageWidth else { return nil }

        let image = NSImage(size: size, flipped: false) { rect in
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            NSGraphicsContext.current?.cgContext.draw(isDark ? dark : light, in: rect)
            return true
        }
        // Redraw on every use, so the appearance is checked each time.
        image.cacheMode = .never

        let rendered = Rendered(image: image, height: Double(size.height).rounded(.up))
        if cache.count >= Self.cacheLimit { cache.removeAll() }
        cache[key] = rendered
        return rendered
    }

    private static func snapshot(_ source: String, fontSize: Double, dark: Bool) -> CGImage? {
        let colors = TableColors(dark: dark)
        // Sized to its content, not to a proposed width, so the picture is as wide as the table.
        let view = Markdown(source)
            .markdownTheme(theme(fontSize: fontSize, colors: colors))
            .fixedSize(horizontal: true, vertical: true)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = false
        return renderer.cgImage
    }

    private static func theme(fontSize: Double, colors: TableColors) -> Theme {
        let maxColumnEm = Self.maxColumnEm
        Theme()
            .text {
                FontFamily(.custom("Iowan Old Style"))
                FontSize(fontSize)
                ForegroundColor(colors.ink)
            }
            .strong {
                FontWeight(.bold)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.85))
                BackgroundColor(colors.codeBackground)
            }
            .link {
                ForegroundColor(colors.accent)
            }
            .table { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .markdownTableBorderStyle(TableBorderStyle(.allBorders, color: colors.border, width: 1))
                    .markdownTableBackgroundStyle(.alternatingRows(Color.clear, colors.stripe, header: colors.header))
            }
            .tableCell { configuration in
                configuration.label
                    .markdownTextStyle {
                        if configuration.row == 0 {
                            FontWeight(.bold)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: fontSize * maxColumnEm, alignment: .leading)
                    .padding(.vertical, (fontSize * 0.4).rounded())
                    .padding(.horizontal, (fontSize * 0.7).rounded())
            }
    }
}

/// Palette colors resolved for one appearance, since the rendered picture can't change later.
private struct TableColors {
    let ink: Color
    let accent: Color
    let border: Color
    let header: Color
    let stripe: Color
    let codeBackground: Color

    init(dark: Bool) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
        var resolved: [NSColor] = []
        appearance.performAsCurrentDrawingAppearance {
            let sources = [Palette.ink, Palette.accent, Palette.marker, Palette.sidebar, Palette.inlineCodeBackground]
            resolved = sources.map { $0.usingColorSpace(.sRGB) ?? $0 }
        }
        ink = Color(nsColor: resolved[0])
        accent = Color(nsColor: resolved[1])
        border = Color(nsColor: resolved[2]).opacity(0.7)
        header = Color(nsColor: resolved[3])
        stripe = Color(nsColor: resolved[3]).opacity(0.55)
        codeBackground = Color(nsColor: resolved[4])
    }
}
