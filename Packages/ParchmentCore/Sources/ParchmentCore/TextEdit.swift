/// A single text replacement plus where the selection should end up afterwards.
///
/// Editing commands return one of these instead of mutating anything, so they are easy to
/// test and the app can apply them through `NSTextView` to get undo for free.
public struct TextEdit: Hashable, Sendable {
    public var range: TextRange
    public var replacement: String
    /// The selection after the edit, in the coordinates of the edited text.
    public var selection: TextRange

    public init(range: TextRange, replacement: String, selection: TextRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }

    /// Applies the edit to a string, which is how the tests check results.
    public func applied(to text: MarkdownText) -> String {
        var units = text.units
        units.replaceSubrange(range.range, with: Array(replacement.utf16))
        return String(decoding: units, as: UTF16.self)
    }
}
