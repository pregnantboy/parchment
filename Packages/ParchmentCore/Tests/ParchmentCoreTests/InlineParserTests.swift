import Testing
@testable import ParchmentCore

@Suite("Inline parsing")
struct InlineParserTests {
    /// Spans of the first line, as (kind, covered text) pairs, sorted by position.
    private func spans(_ source: String) -> [(SpanKind, String)] {
        let text = MarkdownText(source)
        let line = MarkdownParser.lines(in: text)[0]
        return MarkdownParser.spans(for: line, in: text)
            .sorted { ($0.range.location, $0.range.length) < ($1.range.location, $1.range.length) }
            .map { ($0.kind, text.string(in: $0.range)) }
    }

    private func texts(of kind: SpanKind, in source: String) -> [String] {
        spans(source).filter { $0.0 == kind }.map(\.1)
    }

    @Test func strongAndEmphasis() {
        #expect(texts(of: .strong, in: "a **bold** b") == ["bold"])
        #expect(texts(of: .emphasis, in: "a *it* and _it_") == ["it", "it"])
        #expect(texts(of: .syntax, in: "**x**") == ["**", "**"])
    }

    @Test func tripleDelimitersAreBoldItalic() {
        // CommonMark nests these as <em><strong>both</strong></em>.
        #expect(texts(of: .strong, in: "***both***") == ["both"])
        #expect(texts(of: .emphasis, in: "***both***") == ["**both**"])
    }

    @Test func nestedEmphasis() {
        #expect(texts(of: .strong, in: "**bold *and* more**") == ["bold *and* more"])
        #expect(texts(of: .emphasis, in: "**bold *and* more**") == ["and"])
    }

    @Test func intrawordUnderscoresAreLiteral() {
        #expect(texts(of: .emphasis, in: "snake_case_name") == [])
        #expect(texts(of: .emphasis, in: "a * b * c") == [])
    }

    @Test func strikethroughNeedsTwoTildes() {
        #expect(texts(of: .strikethrough, in: "~~gone~~") == ["gone"])
        #expect(texts(of: .strikethrough, in: "~not~") == [])
    }

    @Test func codeSpansProtectTheirContent() {
        #expect(texts(of: .code, in: "use `**raw**` here") == ["**raw**"])
        #expect(texts(of: .strong, in: "use `**raw**` here") == [])
        #expect(texts(of: .code, in: "``a ` b``") == ["a ` b"])
        #expect(texts(of: .code, in: "unclosed `tick") == [])
    }

    @Test func escapesAreSyntaxAndBlockEmphasis() {
        #expect(texts(of: .emphasis, in: "\\*not\\*") == [])
        #expect(texts(of: .syntax, in: "\\*not\\*") == ["\\", "\\"])
    }

    @Test func links() {
        let result = spans("see [the docs](https://example.com) now")
        #expect(result.contains { $0.0 == .linkText(destination: "https://example.com") && $0.1 == "the docs" })
        #expect(result.contains { $0.0 == .linkDestination(destination: "https://example.com") && $0.1 == "https://example.com" })
        #expect(texts(of: .syntax, in: "[a](b)") == ["[", "](", ")"])
    }

    @Test func emphasisInsideLinkText() {
        #expect(texts(of: .strong, in: "[**bold** link](x)") == ["bold"])
    }

    @Test func inlineImagesUseLinkStyling() {
        #expect(texts(of: .syntax, in: "a ![pic](p.png) b") == ["![", "](", ")"])
    }

    @Test func autolinksAndBareURLs() {
        #expect(texts(of: .linkText(destination: "https://a.com"), in: "<https://a.com>") == ["https://a.com"])
        #expect(texts(of: .linkText(destination: "https://apple.com/mac"), in: "Go to https://apple.com/mac.") == ["https://apple.com/mac"])
        #expect(texts(of: .emphasis, in: "https://x.com/a_b_c") == [])
    }

    @Test func headingMarkersAndClosingHashes() {
        let result = spans("## Title ##")
        #expect(result.filter { $0.0 == .syntax }.map(\.1) == ["## ", "##"])
    }

    @Test func taskSpans() {
        let result = spans("- [x] done")
        #expect(result.contains { $0.0 == .taskBox(.done) && $0.1 == "[x]" })
        #expect(result.contains { $0.0 == .completedTask && $0.1 == "done" })
        #expect(result.contains { $0.0 == .listMarker && $0.1 == "- " })
    }

    @Test func blockedAndInProgressTasksAreNotStruckThrough() {
        let blocked = spans("- [!] stuck")
        #expect(blocked.contains { $0.0 == .taskBox(.blocked) && $0.1 == "[!]" })
        #expect(!blocked.contains { $0.0 == .completedTask })
        #expect(spans("- [/] going").contains { $0.0 == .taskBox(.inProgress) && $0.1 == "[/]" })
    }

    @Test func tablePipesAreSyntax() {
        let text = MarkdownText("| a | b |\n|---|---|\n| 1 | 2 |")
        let lines = MarkdownParser.lines(in: text)
        let pipes = MarkdownParser.spans(for: lines[2], in: text).filter { $0.kind == .syntax }
        #expect(pipes.count == 3)
    }
}
