/// Editing commands that understand Markdown. Each returns the edit to make, or `nil` to let
/// the text view do its default behaviour.
public enum MarkdownEditing {
    /// The indent added by Tab inside a list. Four spaces nest both bullet and numbered lists.
    public static let listIndent = "    "

    // MARK: - Return, Tab, Shift-Tab

    /// Continues a list, task list or quote on Return, or ends it when the item is empty.
    /// Outside lists, keeps the current line's indentation (useful in code blocks).
    public static func newline(in text: MarkdownText, selection: MarkdownRange) -> TextEdit? {
        guard selection.isEmpty else { return nil }
        let caret = selection.location
        let line = text.lineRange(containing: caret)

        if let prefix = ListPrefix.parse(text, line: line), caret >= prefix.contentStart {
            let content = MarkdownRange(prefix.contentStart..<line.upperBound)
            if isBlank(text, content) {
                // Return on an empty item ends the list, like Notes and Bear.
                return TextEdit(range: line, replacement: "", selection: MarkdownRange(location: line.location, length: 0))
            }
            let insert = "\n" + text.string(in: prefix.indent) + prefix.continuation
            return TextEdit(range: selection, replacement: insert, selection: MarkdownRange(location: caret + insert.utf16.count, length: 0))
        }

        var indentEnd = line.location
        while indentEnd < line.upperBound, text[indentEnd] == Unit.space || text[indentEnd] == Unit.tab {
            indentEnd += 1
        }
        guard indentEnd > line.location, caret >= indentEnd else { return nil }
        let insert = "\n" + text.string(in: MarkdownRange(line.location..<indentEnd))
        return TextEdit(range: selection, replacement: insert, selection: MarkdownRange(location: caret + insert.utf16.count, length: 0))
    }

    /// Nests the selected list items one level deeper.
    public static func indentListItems(in text: MarkdownText, selection: MarkdownRange) -> TextEdit? {
        let operations = text.lineRanges(touching: selection).compactMap { line -> LineOperation? in
            guard let prefix = ListPrefix.parse(text, line: line), prefix.marker != .quote else { return nil }
            return LineOperation(line: line, offset: 0, deleteCount: 0, insert: listIndent)
        }
        return LineOperation.edit(applying: operations, to: text, selection: selection)
    }

    /// Moves the selected list items one level out.
    public static func outdentListItems(in text: MarkdownText, selection: MarkdownRange) -> TextEdit? {
        let operations = text.lineRanges(touching: selection).compactMap { line -> LineOperation? in
            guard let prefix = ListPrefix.parse(text, line: line), prefix.marker != .quote, prefix.indent.length > 0 else { return nil }
            let removal: Int
            if text[line.location] == Unit.tab {
                removal = 1
            } else {
                var spaces = 0
                while spaces < min(4, prefix.indent.length), text[line.location + spaces] == Unit.space { spaces += 1 }
                removal = spaces
            }
            guard removal > 0 else { return nil }
            return LineOperation(line: line, offset: 0, deleteCount: removal, insert: "")
        }
        return LineOperation.edit(applying: operations, to: text, selection: selection)
    }

    // MARK: - Inline formatting

    /// Wraps the selection in `marker` (like `**` or `_`), or removes it if already there.
    /// With nothing selected, inserts a pair and puts the caret between them.
    public static func toggleWrap(_ marker: String, in text: MarkdownText, selection: MarkdownRange) -> TextEdit {
        let length = marker.utf16.count

        if selection.isEmpty {
            let caret = selection.location
            if caret >= length, text.matches(marker, at: caret - length), text.matches(marker, at: caret) {
                return TextEdit(range: MarkdownRange(location: caret - length, length: length * 2), replacement: "", selection: MarkdownRange(location: caret - length, length: 0))
            }
            return TextEdit(range: selection, replacement: marker + marker, selection: MarkdownRange(location: caret + length, length: 0))
        }

        let target = trimmingWhitespace(selection, in: text)
        let inner = text.string(in: target)

        if target.location >= length, text.matches(marker, at: target.location - length), text.matches(marker, at: target.upperBound) {
            return TextEdit(
                range: MarkdownRange(location: target.location - length, length: target.length + length * 2),
                replacement: inner,
                selection: MarkdownRange(location: target.location - length, length: target.length)
            )
        }

        if target.length >= length * 2, text.matches(marker, at: target.location), text.matches(marker, at: target.upperBound - length) {
            let unwrapped = MarkdownRange(location: target.location + length, length: target.length - length * 2)
            return TextEdit(range: target, replacement: text.string(in: unwrapped), selection: MarkdownRange(location: target.location, length: unwrapped.length))
        }

        return TextEdit(range: target, replacement: marker + inner + marker, selection: MarkdownRange(location: target.location + length, length: target.length))
    }

    /// Makes the selected lines headings of `level`, or plain text when `level` is 0.
    /// Applying the level a line already has turns the heading off.
    public static func setHeading(level: Int, in text: MarkdownText, selection: MarkdownRange) -> TextEdit? {
        let lines = text.lineRanges(touching: selection)
        let candidates = lines.count == 1 ? lines : lines.filter { !isBlank(text, $0) }
        let existing = candidates.map { headingPrefix(in: text, line: $0) }
        let allAlreadyAtLevel = level > 0 && existing.allSatisfy { $0.level == level }
        let newPrefix = (level == 0 || allAlreadyAtLevel) ? "" : String(repeating: "#", count: level) + " "

        let operations = zip(candidates, existing).map { line, prefix in
            LineOperation(line: line, offset: 0, deleteCount: prefix.length, insert: newPrefix)
        }
        return LineOperation.edit(applying: operations, to: text, selection: selection)
    }

    /// Inserts a link. Selected text becomes the link text; a selected URL becomes the destination.
    public static func insertLink(in text: MarkdownText, selection: MarkdownRange) -> TextEdit {
        let selected = text.string(in: selection)
        if selected.isEmpty {
            return TextEdit(range: selection, replacement: "[]()", selection: MarkdownRange(location: selection.location + 1, length: 0))
        }
        let lowercased = selected.lowercased()
        let looksLikeURL = ["http://", "https://", "mailto:", "www."].contains { lowercased.hasPrefix($0) } && !selected.contains(" ")
        if looksLikeURL {
            return TextEdit(range: selection, replacement: "[](\(selected))", selection: MarkdownRange(location: selection.location + 1, length: 0))
        }
        let replacement = "[\(selected)]()"
        return TextEdit(range: selection, replacement: replacement, selection: MarkdownRange(location: selection.location + replacement.utf16.count - 1, length: 0))
    }

    // MARK: - Tasks

    /// Turns the selected lines into tasks, or checks and unchecks them if they already are.
    /// In-progress and blocked tasks count as unchecked, so toggling them ticks them.
    public static func toggleTask(in text: MarkdownText, selection: MarkdownRange) -> TextEdit? {
        let lines = text.lineRanges(touching: selection)
        let prefixes = lines.map { ListPrefix.parse(text, line: $0) }

        if let firstTask = prefixes.compactMap({ $0 }).first(where: \.isTask) {
            let newMark = firstTask.isChecked ? " " : "x"
            let operations = zip(lines, prefixes).compactMap { line, prefix -> LineOperation? in
                guard let box = prefix?.taskBox else { return nil }
                return LineOperation(line: line, offset: box.location + 1 - line.location, deleteCount: 1, insert: newMark)
            }
            return LineOperation.edit(applying: operations, to: text, selection: selection)
        }

        let operations = zip(lines, prefixes).compactMap { line, prefix -> LineOperation? in
            if let prefix, prefix.marker != .quote {
                return LineOperation(line: line, offset: prefix.contentStart - line.location, deleteCount: 0, insert: "[ ] ")
            }
            if lines.count > 1, isBlank(text, line) { return nil }
            let start = prefix?.contentStart ?? firstNonWhitespace(in: text, line: line)
            return LineOperation(line: line, offset: start - line.location, deleteCount: 0, insert: "- [ ] ")
        }
        return LineOperation.edit(applying: operations, to: text, selection: selection)
    }

    /// Checks or unchecks the task box whose `[` is at `boxLocation`.
    public static func toggleTaskBox(at boxLocation: Int, in text: MarkdownText, selection: MarkdownRange) -> TextEdit? {
        guard text.unit(at: boxLocation) == Unit.openBracket, text.unit(at: boxLocation + 2) == Unit.closeBracket,
              let mark = text.unit(at: boxLocation + 1) else { return nil }
        let newMark = TaskState(mark: mark)?.isDone == true ? " " : "x"
        return TextEdit(range: MarkdownRange(location: boxLocation + 1, length: 1), replacement: newMark, selection: selection)
    }

    // MARK: - Helpers

    static func isBlank(_ text: MarkdownText, _ range: MarkdownRange) -> Bool {
        range.range.allSatisfy { text[$0] == Unit.space || text[$0] == Unit.tab }
    }

    private static func firstNonWhitespace(in text: MarkdownText, line: MarkdownRange) -> Int {
        var index = line.location
        while index < line.upperBound, text[index] == Unit.space || text[index] == Unit.tab { index += 1 }
        return index
    }

    private static func trimmingWhitespace(_ range: MarkdownRange, in text: MarkdownText) -> MarkdownRange {
        var lower = range.location
        var upper = range.upperBound
        while lower < upper, Unit.isWhitespace(text[lower]) { lower += 1 }
        while upper > lower, Unit.isWhitespace(text[upper - 1]) { upper -= 1 }
        return lower == upper ? range : MarkdownRange(lower..<upper)
    }

    /// The length of an ATX heading prefix like `## `, and its level, or zero for other lines.
    private static func headingPrefix(in text: MarkdownText, line: MarkdownRange) -> (length: Int, level: Int) {
        var index = line.location
        while index < line.upperBound, index - line.location < 3, text[index] == Unit.space { index += 1 }
        let hashStart = index
        while index < line.upperBound, text[index] == Unit.hash { index += 1 }
        let level = index - hashStart
        guard (1...6).contains(level), index == line.upperBound || text[index] == Unit.space || text[index] == Unit.tab else {
            return (0, 0)
        }
        while index < line.upperBound, text[index] == Unit.space || text[index] == Unit.tab { index += 1 }
        return (index - line.location, level)
    }
}
