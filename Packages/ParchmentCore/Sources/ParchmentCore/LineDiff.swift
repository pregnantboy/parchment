/// Finds which lines changed between two parses, so the editor restyles only those.
public enum LineDiff {
    /// Indices into `newLines` that differ from `oldLines`.
    ///
    /// Lines are compared by text, kind, line break, block position and continuation, so a change that
    /// alters a neighbour's role (like opening a code fence) widens the range automatically.
    public static func changedLines(
        old oldText: MarkdownText,
        oldLines: [MarkdownLine],
        new newText: MarkdownText,
        newLines: [MarkdownLine]
    ) -> Range<Int> {
        let shared = min(oldLines.count, newLines.count)
        var prefix = 0
        while prefix < shared, same(oldLines[prefix], in: oldText, newLines[prefix], in: newText) {
            prefix += 1
        }
        var suffix = 0
        while suffix < shared - prefix,
              same(oldLines[oldLines.count - 1 - suffix], in: oldText, newLines[newLines.count - 1 - suffix], in: newText) {
            suffix += 1
        }
        return prefix..<max(prefix, newLines.count - suffix)
    }

    private static func same(_ old: MarkdownLine, in oldText: MarkdownText, _ new: MarkdownLine, in newText: MarkdownText) -> Bool {
        guard old.kind == new.kind,
              old.range.length == new.range.length,
              old.lineBreakLength == new.lineBreakLength,
              old.blockPosition == new.blockPosition,
              old.isContinuation == new.isContinuation,
              old.contentStart - old.range.location == new.contentStart - new.range.location else {
            return false
        }
        return oldText.units[old.range.range] == newText.units[new.range.range]
    }
}
