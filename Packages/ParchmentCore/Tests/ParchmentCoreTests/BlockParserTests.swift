import Testing
@testable import ParchmentCore

@Suite("Block parsing")
struct BlockParserTests {
    private func kinds(_ source: String) -> [LineKind] {
        MarkdownParser.lines(in: MarkdownText(source)).map(\.kind)
    }

    @Test func headingsNeedASpaceAfterTheHashes() {
        #expect(kinds("# Title") == [.heading(level: 1)])
        #expect(kinds("###### Six") == [.heading(level: 6)])
        #expect(kinds("####### Seven") == [.paragraph])
        #expect(kinds("#hashtag") == [.paragraph])
        #expect(kinds("##") == [.heading(level: 2)])
    }

    @Test func headingContentStartsAfterTheMarker() {
        let lines = MarkdownParser.lines(in: MarkdownText("## Hello"))
        #expect(lines[0].contentStart == 3)
    }

    @Test func fencedCodeBlocksClaimTheirLines() {
        let source = """
        Intro
        ```swift
        let x = 1
        # not a heading
        ```
        After
        """
        #expect(kinds(source) == [
            .paragraph,
            .fence(language: "swift", isOpening: true),
            .code(language: "swift"),
            .code(language: "swift"),
            .fence(language: "swift", isOpening: false),
            .paragraph,
        ])
    }

    @Test func unclosedFenceRunsToTheEnd() {
        #expect(kinds("~~~\na\nb") == [.fence(language: "", isOpening: true), .code(language: ""), .code(language: "")])
    }

    @Test func shorterFenceDoesNotClose() {
        #expect(kinds("````\n```\n````") == [
            .fence(language: "", isOpening: true),
            .code(language: ""),
            .fence(language: "", isOpening: false),
        ])
    }

    @Test func listsTasksAndQuotes() {
        #expect(kinds("- item") == [.listItem(isOrdered: false)])
        #expect(kinds("12. item") == [.listItem(isOrdered: true)])
        #expect(kinds("- [ ] todo") == [.task(.open)])
        #expect(kinds("* [x] done") == [.task(.done)])
        #expect(kinds("- [/] going") == [.task(.inProgress)])
        #expect(kinds("1. [!] stuck") == [.task(.blocked)])
        #expect(kinds("- [?] unknown") == [.listItem(isOrdered: false)])
        #expect(kinds("> quoted") == [.quote])
        #expect(kinds("-not a list") == [.paragraph])
        #expect(kinds("1.5 million") == [.paragraph])
    }

    @Test func rulesBeatLists() {
        #expect(kinds("---") == [.rule])
        #expect(kinds("* * *") == [.rule])
        #expect(kinds("___") == [.rule])
        #expect(kinds("--") == [.paragraph])
    }

    @Test func tablesNeedADelimiterRow() {
        let source = """
        | Name | Age |
        | ---- | --: |
        | Ada  | 36  |
        Not a row
        """
        #expect(kinds(source) == [.tableHeader, .tableDelimiter, .tableRow, .paragraph])
        #expect(kinds("a | b\nplain") == [.paragraph, .paragraph])
    }

    @Test func imageOnlyLines() {
        #expect(kinds("![Alt text](images/cat.png)") == [.image(source: "images/cat.png")])
        #expect(kinds("![a](<my photo.jpg> \"Title\")") == [.image(source: "my photo.jpg")])
        #expect(kinds("See ![a](b.png) inline") == [.paragraph])
    }

    @Test func blankLinesAndLineBreaks() {
        let lines = MarkdownParser.lines(in: MarkdownText("a\r\n\nb"))
        #expect(lines.map(\.kind) == [.paragraph, .blank, .paragraph])
        #expect(lines.map(\.lineBreakLength) == [2, 1, 0])
        #expect(lines[0].range == MarkdownRange(location: 0, length: 1))
        #expect(lines[2].range == MarkdownRange(location: 4, length: 1))
    }

    @Test func trailingNewlineMakesAnEmptyLastLine() {
        let lines = MarkdownParser.lines(in: MarkdownText("a\n"))
        #expect(lines.count == 2)
        #expect(lines[1].range == MarkdownRange(location: 2, length: 0))
    }

    @Test func blockPositionsGroupRelatedLines() {
        let source = "```\ncode\n```\n> one\n> two\n\ntext"
        let positions = MarkdownParser.lines(in: MarkdownText(source)).map(\.blockPosition)
        #expect(positions == [.first, .middle, .last, .first, .last, .none, .none])
    }

    @Test func aPlainLineRightAfterAQuoteBelongsToIt() {
        let source = "> one\ntwo"
        let positions = MarkdownParser.lines(in: MarkdownText(source)).map(\.blockPosition)
        #expect(positions == [.first, .last])
    }

    private func continuations(_ source: String) -> [Bool] {
        MarkdownParser.lines(in: MarkdownText(source)).map(\.isContinuation)
    }

    @Test func hardWrappedLinesContinueTheirParagraph() {
        #expect(continuations("one\ntwo\nthree") == [false, true, true])
        #expect(continuations("- item\n  wrapped\n- next") == [false, true, false])
        #expect(continuations("- [ ] task\nwrapped") == [false, true])
        #expect(continuations("1. item\nwrapped") == [false, true])
        #expect(continuations("> one\n> two\nthree") == [false, true, true])
    }

    @Test func continuationsStopAtOtherBlocks() {
        #expect(continuations("one\n\ntwo") == [false, false, false])
        #expect(continuations("# Title\ntext") == [false, false])
        #expect(continuations("text\n# Title") == [false, false])
        #expect(continuations("text\n- item") == [false, false])
        #expect(continuations("- \ntext") == [false, false])
        #expect(continuations(">\n> two") == [false, false])
        #expect(continuations("text\n> quote") == [false, false])
        #expect(continuations("```\na\nb\n```") == [false, false, false, false])
        #expect(continuations("text\n| a | b |\n|---|---|") == [false, false, false])
    }

    @Test func backToBackCodeBlocksStaySeparate() {
        let source = "```\na\n```\n```\nb\n```"
        let positions = MarkdownParser.lines(in: MarkdownText(source)).map(\.blockPosition)
        #expect(positions == [.first, .middle, .last, .first, .middle, .last])
    }

    @Test func emptyDocumentHasOneBlankLine() {
        #expect(kinds("") == [.blank])
    }
}
