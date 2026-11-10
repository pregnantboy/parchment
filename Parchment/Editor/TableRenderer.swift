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
        let width: Int
        let fontSize: Double
    }

    private var cache: [Key: Rendered] = [:]
    private static let cacheLimit = 64
    private static let scale = 2.0

    /// The table in `source` (its header, `---|---` row and body rows) rendered at most
    /// `width` points wide, or `nil` if it can't be drawn.
    func render(_ source: String, width: Double, fontSize: Double) -> Rendered? {
        guard width >= 40, !source.isEmpty else { return nil }
        let key = Key(source: source, width: Int(width.rounded(.down)), fontSize: fontSize)
        if let cached = cache[key] { return cached }

        let fitWidth = Double(key.width)
        guard let light = Self.snapshot(source, width: fitWidth, fontSize: fontSize, dark: false),
              let dark = Self.snapshot(source, width: fitWidth, fontSize: fontSize, dark: true) else { return nil }
        let size = NSSize(width: Double(light.width) / Self.scale, height: Double(light.height) / Self.scale)
        guard size.width > 0, size.height > 0 else { return nil }

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

    private static func snapshot(_ source: String, width: Double, fontSize: Double, dark: Bool) -> CGImage? {
        let colors = TableColors(dark: dark)
        let view = Markdown(source)
            .markdownTheme(theme(fontSize: fontSize, colors: colors))
            .frame(width: width, alignment: .leading)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.isOpaque = false
        return renderer.cgImage
    }

    private static func theme(fontSize: Double, colors: TableColors) -> Theme {
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
