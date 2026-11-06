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
    /// Value: `NSNumber(true)`, on a rule line.
    static let parchmentRule = NSAttributedString.Key("app.parchment.rule")
}
