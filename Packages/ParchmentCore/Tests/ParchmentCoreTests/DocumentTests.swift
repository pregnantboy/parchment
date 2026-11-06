import Testing
@testable import ParchmentCore

@Suite("Stats, outline and diffing")
struct DocumentTests {
    @Test func wordCountIgnoresMarkdownSyntax() {
        #expect(DocumentStats(counting: "# Hello **world**").words == 2)
        #expect(DocumentStats(counting: "- [ ] buy milk\n- eggs").words == 3)
        #expect(DocumentStats(counting: "don't stop well-known").words == 3)
        #expect(DocumentStats(counting: "").words == 0)
        #expect(DocumentStats(counting: "日本語").words == 3)
    }

    @Test func readingTimeRoundsUp() {
        #expect(DocumentStats(words: 0, characters: 0).readingMinutes == 0)
        #expect(DocumentStats(words: 1, characters: 1).readingMinutes == 1)
        #expect(DocumentStats(words: 238, characters: 1).readingMinutes == 1)
        #expect(DocumentStats(words: 239, characters: 1).readingMinutes == 2)
    }

    @Test func outlineSkipsCodeAndCleansTitles() {
        let text = MarkdownText("# One\n```\n# not\n```\n## **Two** ##\n###")
        let headings = OutlineHeading.headings(in: MarkdownParser.lines(in: text), text: text)
        #expect(headings.map(\.title) == ["One", "Two"])
        #expect(headings.map(\.level) == [1, 2])
    }

    @Test func diffFindsOnlyTheEditedLine() {
        let old = MarkdownText("a\nb\nc")
        let new = MarkdownText("a\nbb\nc")
        let range = LineDiff.changedLines(
            old: old, oldLines: MarkdownParser.lines(in: old),
            new: new, newLines: MarkdownParser.lines(in: new)
        )
        #expect(range == 1..<2)
    }

    @Test func diffWidensWhenAFenceOpens() {
        let old = MarkdownText("a\nb\nc")
        let new = MarkdownText("```\nb\nc")
        let range = LineDiff.changedLines(
            old: old, oldLines: MarkdownParser.lines(in: old),
            new: new, newLines: MarkdownParser.lines(in: new)
        )
        #expect(range == 0..<3)
    }

    @Test func diffOfIdenticalTextIsEmpty() {
        let text = MarkdownText("a\nb")
        let lines = MarkdownParser.lines(in: text)
        #expect(LineDiff.changedLines(old: text, oldLines: lines, new: text, newLines: lines).isEmpty)
    }

    @Test func diffCatchesInsertedLines() {
        let old = MarkdownText("a\nc")
        let new = MarkdownText("a\nb\nc")
        let range = LineDiff.changedLines(
            old: old, oldLines: MarkdownParser.lines(in: old),
            new: new, newLines: MarkdownParser.lines(in: new)
        )
        #expect(range == 1..<2)
    }

    @Test func lineRangesTouchingASelection() {
        let text = MarkdownText("one\ntwo\nthree")
        #expect(text.lineRanges(touching: TextRange(location: 1, length: 0)).count == 1)
        #expect(text.lineRanges(touching: TextRange(location: 1, length: 5)).count == 2)
        // A selection ending right after a line break doesn't include the next line.
        #expect(text.lineRanges(touching: TextRange(location: 0, length: 4)).count == 1)
        #expect(text.lineRanges(touching: TextRange(location: 0, length: 13)).count == 3)
    }
}
