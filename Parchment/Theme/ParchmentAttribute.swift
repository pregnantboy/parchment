import AppKit

/// Custom attributes the styler writes and the layout manager and text view read.
nonisolated extension NSAttributedString.Key {
    /// Value: `NSNumber(BlockDecoration.rawValue)`, on a line's full range.
    static let parchmentBlock = NSAttributedString.Key("app.parchment.block")
    /// Value: `NSNumber(TaskState.rawValue)`, on the 3-character `[ ]`, `[/]`, `[!]` or `[x]`.
    static let parchmentTaskBox = NSAttributedString.Key("app.parchment.taskBox")
    /// Value: `NSImage`, on the image line's range.
    static let parchmentImage = NSAttributedString.Key("app.parchment.image")
    /// Value: `String` URL, on the link text and its destination.
    static let parchmentLink = NSAttributedString.Key("app.parchment.link")
    /// Value: `NSNumber(true)`, on the text of an inline code span (not its backticks).
    /// The layout manager draws a rounded pill behind it, one per line when it wraps.
    static let parchmentInlineCode = NSAttributedString.Key("app.parchment.inlineCode")
    /// Value: `NSNumber(true)`, on a rule line.
    static let parchmentRule = NSAttributedString.Key("app.parchment.rule")
    /// Value: `NSNumber(true)`, on Markdown symbols that reading mode hides. The layout
    /// manager gives their glyphs no width and draws nothing for them.
    static let parchmentHidden = NSAttributedString.Key("app.parchment.hidden")
    /// Value: `NSNumber(Bool keepsLineBreak)`, on the line break before a line that continues
    /// a paragraph, in reading mode only. The layout manager lays the break out as a space, so
    /// a hard-wrapped paragraph flows as one. When the line above ends in two spaces (a
    /// Markdown hard break), `keepsLineBreak` is true and the text starts a new line instead,
    /// still inside the paragraph.
    static let parchmentSoftBreak = NSAttributedString.Key("app.parchment.softBreak")
    /// Value: `NSNumber(true)`, on the transparent `-`, `*` or `+` of a bullet in reading
    /// mode. The layout manager draws a dot or diamond in its place.
    static let parchmentBullet = NSAttributedString.Key("app.parchment.bullet")
    /// Value: `NSNumber(Double width)`, on a table's `---|---` row in reading mode. The layout
    /// manager draws the header rule across that row, `width` points from the gutter edge.
    static let parchmentTableRule = NSAttributedString.Key("app.parchment.tableRule")
    /// Value: `NSNumber(Double width)`, on a table row (not the last) in reading mode. The
    /// layout manager draws a faint rule below it.
    static let parchmentTableRowRule = NSAttributedString.Key("app.parchment.tableRowRule")
    /// Value: `NSNumber(true)`, next to `parchmentImage` when that image is a rendered table.
    /// Tables are drawn with square corners so their borders aren't clipped.
    static let parchmentTable = NSAttributedString.Key("app.parchment.table")
}
