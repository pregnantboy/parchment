/// The smallest single edit that turns one snapshot of a document into another.
///
/// Used when a file changes on disk: only `oldRange` is replaced, with the text at `newRange`
/// of the new snapshot, so the rest of the document keeps its styling, selection and scroll.
public struct TextChange: Hashable, Sendable {
    /// The replaced range in the old text.
    public var oldRange: MarkdownRange
    /// Where the replacement sits in the new text.
    public var newRange: MarkdownRange

    public init(oldRange: MarkdownRange, newRange: MarkdownRange) {
        self.oldRange = oldRange
        self.newRange = newRange
    }

    /// `nil` when the texts are equal. Otherwise the common prefix and suffix are left out.
    /// The split never lands inside a surrogate pair, so both ranges are valid `NSString` ranges.
    public static func between(old: MarkdownText, new: MarkdownText) -> TextChange? {
        guard old != new else { return nil }
        let oldUnits = old.units
        let newUnits = new.units
        let shared = min(oldUnits.count, newUnits.count)

        var prefix = 0
        while prefix < shared, oldUnits[prefix] == newUnits[prefix] {
            prefix += 1
        }
        // Don't split a surrogate pair: step back if the prefix ends on a high surrogate.
        if prefix > 0, isHighSurrogate(oldUnits[prefix - 1]) {
            prefix -= 1
        }

        var suffix = 0
        while suffix < shared - prefix,
              oldUnits[oldUnits.count - 1 - suffix] == newUnits[newUnits.count - 1 - suffix] {
            suffix += 1
        }
        if suffix > 0, isLowSurrogate(oldUnits[oldUnits.count - suffix]) {
            suffix -= 1
        }

        return TextChange(
            oldRange: MarkdownRange(location: prefix, length: oldUnits.count - suffix - prefix),
            newRange: MarkdownRange(location: prefix, length: newUnits.count - suffix - prefix)
        )
    }

    private static func isHighSurrogate(_ unit: UInt16) -> Bool { unit >= 0xD800 && unit <= 0xDBFF }
    private static func isLowSurrogate(_ unit: UInt16) -> Bool { unit >= 0xDC00 && unit <= 0xDFFF }
}
