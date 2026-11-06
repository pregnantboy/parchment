import Testing
@testable import ParchmentCore

/// Editing tests use `|` to mark the caret, or `«` and `»` to mark a selection.
@Suite("Markdown editing")
struct EditingTests {
    private func parse(_ marked: String) -> (MarkdownText, TextRange) {
        var units: [UInt16] = []
        var start: Int?
        var end: Int?
        for unit in marked.utf16 {
            switch unit {
            case UInt16(UInt8(ascii: "|")): start = units.count; end = units.count
            case 0x00AB: start = units.count // «
            case 0x00BB: end = units.count // »
            default: units.append(unit)
            }
        }
        let lower = start ?? units.count
        return (MarkdownText(units: units), TextRange(location: lower, length: (end ?? lower) - lower))
    }

    private func render(_ edit: TextEdit?, on text: MarkdownText) -> String? {
        guard let edit else { return nil }
        var units = Array(edit.applied(to: text).utf16)
        let marker: (Character) -> [UInt16] = { Array(String($0).utf16) }
        if edit.selection.isEmpty {
            units.insert(contentsOf: marker("|"), at: edit.selection.location)
        } else {
            units.insert(contentsOf: marker("»"), at: edit.selection.upperBound)
            units.insert(contentsOf: marker("«"), at: edit.selection.location)
        }
        return String(decoding: units, as: UTF16.self)
    }

    private func apply(_ marked: String, _ command: (MarkdownText, TextRange) -> TextEdit?) -> String? {
        let (text, selection) = parse(marked)
        return render(command(text, selection), on: text)
    }

    // MARK: Return

    @Test func returnContinuesBulletsTasksNumbersAndQuotes() {
        #expect(apply("- milk|", MarkdownEditing.newline) == "- milk\n- |")
        #expect(apply("  * nested|", MarkdownEditing.newline) == "  * nested\n  * |")
        #expect(apply("- [x] done|", MarkdownEditing.newline) == "- [x] done\n- [ ] |")
        #expect(apply("9. nine|", MarkdownEditing.newline) == "9. nine\n10. |")
        #expect(apply("1) a|", MarkdownEditing.newline) == "1) a\n2) |")
        #expect(apply("> said|", MarkdownEditing.newline) == "> said\n> |")
    }

    @Test func returnOnAnEmptyItemEndsTheList() {
        #expect(apply("- a\n- |", MarkdownEditing.newline) == "- a\n|")
        #expect(apply("- [ ] |", MarkdownEditing.newline) == "|")
    }

    @Test func returnSplitsAnItem() {
        #expect(apply("- ab|cd", MarkdownEditing.newline) == "- ab\n- |cd")
    }

    @Test func returnInsideTheMarkerIsDefault() {
        #expect(apply("-| a", MarkdownEditing.newline) == nil)
    }

    @Test func returnKeepsIndentationOutsideLists() {
        #expect(apply("    code|", MarkdownEditing.newline) == "    code\n    |")
        #expect(apply("plain|", MarkdownEditing.newline) == nil)
    }

    // MARK: Tab

    @Test func tabIndentsListItems() {
        #expect(apply("- a|", MarkdownEditing.indentListItems) == "    - a|")
        #expect(apply("«- a\n- b»", MarkdownEditing.indentListItems) == "    «- a\n    - b»")
        #expect(apply("text|", MarkdownEditing.indentListItems) == nil)
    }

    @Test func shiftTabOutdents() {
        #expect(apply("    - a|", MarkdownEditing.outdentListItems) == "- a|")
        #expect(apply("\t- a|", MarkdownEditing.outdentListItems) == "- a|")
        #expect(apply("- a|", MarkdownEditing.outdentListItems) == nil)
    }

    // MARK: Inline formatting

    @Test func wrapAndUnwrap() {
        #expect(apply("a «word» b", { MarkdownEditing.toggleWrap("**", in: $0, selection: $1) }) == "a **«word»** b")
        #expect(apply("a **«word»** b", { MarkdownEditing.toggleWrap("**", in: $0, selection: $1) }) == "a «word» b")
        #expect(apply("a «**word**» b", { MarkdownEditing.toggleWrap("**", in: $0, selection: $1) }) == "a «word» b")
        #expect(apply("«word »", { MarkdownEditing.toggleWrap("_", in: $0, selection: $1) }) == "_«word»_ ")
    }

    @Test func wrapWithNothingSelectedInsertsAPair() {
        #expect(apply("a |", { MarkdownEditing.toggleWrap("**", in: $0, selection: $1) }) == "a **|**")
        #expect(apply("a **|**", { MarkdownEditing.toggleWrap("**", in: $0, selection: $1) }) == "a |")
    }

    @Test func headings() {
        #expect(apply("Title|", { MarkdownEditing.setHeading(level: 2, in: $0, selection: $1) }) == "## Title|")
        #expect(apply("# Ti|tle", { MarkdownEditing.setHeading(level: 3, in: $0, selection: $1) }) == "### Ti|tle")
        #expect(apply("## Ti|tle", { MarkdownEditing.setHeading(level: 2, in: $0, selection: $1) }) == "Ti|tle")
        #expect(apply("## Ti|tle", { MarkdownEditing.setHeading(level: 0, in: $0, selection: $1) }) == "Ti|tle")
        #expect(apply("|## Title", { MarkdownEditing.setHeading(level: 1, in: $0, selection: $1) }) == "# |Title")
    }

    @Test func links() {
        #expect(apply("|", MarkdownEditing.insertLink) == "[|]()")
        #expect(apply("«Apple»", MarkdownEditing.insertLink) == "[Apple](|)")
        #expect(apply("«https://apple.com»", MarkdownEditing.insertLink) == "[|](https://apple.com)")
    }

    // MARK: Tasks

    @Test func toggleTaskConvertsAndChecks() {
        #expect(apply("buy milk|", MarkdownEditing.toggleTask) == "- [ ] buy milk|")
        #expect(apply("- buy milk|", MarkdownEditing.toggleTask) == "- [ ] buy milk|")
        #expect(apply("- [ ] buy milk|", MarkdownEditing.toggleTask) == "- [x] buy milk|")
        #expect(apply("- [x] buy milk|", MarkdownEditing.toggleTask) == "- [ ] buy milk|")
        #expect(apply("|", MarkdownEditing.toggleTask) == "- [ ] |")
    }

    @Test func toggleTaskBoxByLocation() {
        let (text, selection) = parse("- [ ] a|")
        let edit = MarkdownEditing.toggleTaskBox(at: 2, in: text, selection: selection)
        #expect(edit.map { $0.applied(to: text) } == "- [x] a")
        #expect(MarkdownEditing.toggleTaskBox(at: 0, in: text, selection: selection) == nil)
    }

    // MARK: Auto-pairing

    @Test func pairsBrackets() {
        #expect(apply("a |", { AutoPair.insert("(", in: $0, selection: $1) }) == "a (|)")
        #expect(apply("a |b", { AutoPair.insert("(", in: $0, selection: $1) }) == nil)
        #expect(apply("(a|)", { AutoPair.insert(")", in: $0, selection: $1) }) == "(a)|")
    }

    @Test func wrapsSelections() {
        #expect(apply("«word»", { AutoPair.insert("*", in: $0, selection: $1) }) == "*«word»*")
        #expect(apply("«word»", { AutoPair.insert("[", in: $0, selection: $1) }) == "[«word»]")
        #expect(apply("«word»", { AutoPair.insert("a", in: $0, selection: $1) }) == nil)
    }

    @Test func backticksAllowCodeFences() {
        var text = "|"
        for _ in 0..<3 {
            let (parsed, selection) = parse(text)
            text = render(AutoPair.insert("`", in: parsed, selection: selection), on: parsed)
                ?? render(TextEdit(range: selection, replacement: "`", selection: TextRange(location: selection.location + 1, length: 0)), on: parsed)!
        }
        #expect(text == "```|")
    }

    @Test func taskBoxTypesNaturally() {
        // Typing "[", " ", "]" after "- " gives "- [ ]".
        var (text, selection) = parse("- |")
        let open = AutoPair.insert("[", in: text, selection: selection)!
        text = MarkdownText(open.applied(to: text)); selection = open.selection
        text = MarkdownText(TextEdit(range: selection, replacement: " ", selection: selection).applied(to: text))
        selection = TextRange(location: selection.location + 1, length: 0)
        let close = AutoPair.insert("]", in: text, selection: selection)!
        #expect(render(close, on: text) == "- [ ]|")
    }

    @Test func backspaceDeletesEmptyPairs() {
        #expect(apply("(|)", AutoPair.deleteBackward) == "|")
        #expect(apply("(a|)", AutoPair.deleteBackward) == nil)
    }
}
