import AppKit

/// Custom attributes the styler writes and the layout manager and text view read.
nonisolated extension NSAttributedString.Key {
    /// Value: `NSNumber(BlockDecoration.rawValue)`, on a line's full range.
    static let parchmentBlock = NSAttributedString.Key("app.parchment.block")
    /// Value: `NSNumber(Bool isChecked)`, on the 3-character `[ ]` or `[x]`.
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
    /// Value: `NSNumber(true)`, on the transparent `-`, `*` or `+` of a bullet in reading
    /// mode. The layout manager draws a dot or diamond in its place.
    static let parchmentBullet = NSAttributedString.Key("app.parchment.bullet")
}
