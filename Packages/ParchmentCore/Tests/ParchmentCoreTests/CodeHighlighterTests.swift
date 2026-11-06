import Testing
@testable import ParchmentCore

@Suite("Code highlighting")
struct CodeHighlighterTests {
    private func tokens(_ code: String, language: String) -> [(CodeTokenKind, String)] {
        let text = MarkdownText(code)
        var spans: [MarkdownSpan] = []
        CodeHighlighter.highlight(text, range: TextRange(location: 0, length: text.length), language: language, into: &spans)
        return spans.compactMap { span in
            guard case .codeToken(let kind) = span.kind else { return nil }
            return (kind, text.string(in: span.range))
        }
    }

    @Test func swiftKeywordsStringsAndComments() {
        let result = tokens(#"let name = "Ada" // greet"#, language: "swift")
        #expect(result.map(\.0) == [.keyword, .string, .comment])
        #expect(result.map(\.1) == ["let", "\"Ada\"", "// greet"])
    }

    @Test func numbersTypesAndRanges() {
        let result = tokens("for i in 0..<10 { View(i) }", language: "swift")
        #expect(result.contains { $0 == (.number, "0") })
        #expect(result.contains { $0 == (.number, "10") })
        #expect(result.contains { $0 == (.type, "View") })
    }

    @Test func escapedQuotesStayInsideStrings() {
        let result = tokens(#"x = "a \" b""#, language: "python")
        #expect(result.map(\.1) == [#""a \" b""#])
    }

    @Test func hashCommentsOnlyAtWordStart() {
        #expect(tokens("echo $# # count", language: "bash").last?.1 == "# count")
        #expect(tokens("#include <stdio.h>", language: "c").first?.0 == .keyword)
    }

    @Test func markupTags() {
        let result = tokens(#"<a href="/x">hi</a>"#, language: "html")
        #expect(result.map(\.1) == ["a", "href", "\"/x\"", "a"])
    }

    @Test func blockCommentOnOneLine() {
        let result = tokens("a /* note */ b", language: "css")
        #expect(result.map(\.1) == ["/* note */"])
    }

    @Test func codeLinesAreHighlightedThroughTheParser() {
        let text = MarkdownText("```js\nconst a = 1\n```")
        let lines = MarkdownParser.lines(in: text)
        let spans = MarkdownParser.spans(for: lines[1], in: text)
        #expect(spans.contains { $0.kind == .codeToken(.keyword) })
    }
}
