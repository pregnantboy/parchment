import Testing
@testable import ParchmentCore

@Suite("Performance")
struct PerformanceTests {
    /// About 300 KB of mixed Markdown, far longer than a typical note.
    private static let largeDocument: String = {
        let section = """
        ## Section heading with **bold** and *italic*

        A paragraph with a [link](https://example.com), some `inline code`, and ~~struck~~ words that wrap.
        - [ ] a task item
        - a bullet with _emphasis_
        > a quote line

        ```swift
        let value = compute("text", 42) // comment
        ```

        | a | b |
        |---|---|
        | 1 | 2 |

        """
        return String(repeating: section, count: 1_000)
    }()

    @Test func parsingAndStylingALargeDocumentIsFast() {
        let clock = ContinuousClock()
        var spanCount = 0
        let elapsed = clock.measure {
            let text = MarkdownText(Self.largeDocument)
            let lines = MarkdownParser.lines(in: text)
            for line in lines {
                spanCount += MarkdownParser.spans(for: line, in: text).count
            }
        }
        #expect(spanCount > 10_000)
        // Generous bound for unoptimized debug builds on CI; release builds are many times faster.
        #expect(elapsed < .seconds(2), "Full parse took \(elapsed)")
        print("Parsed \(Self.largeDocument.utf16.count) UTF-16 units into \(spanCount) spans in \(elapsed)")
    }

    @Test func diffingAKeystrokeIsFast() {
        let old = MarkdownText(Self.largeDocument)
        let oldLines = MarkdownParser.lines(in: old)
        let new = MarkdownText(Self.largeDocument + "x")
        let clock = ContinuousClock()
        var changed = 0..<0
        let elapsed = clock.measure {
            let newLines = MarkdownParser.lines(in: new)
            changed = LineDiff.changedLines(old: old, oldLines: oldLines, new: new, newLines: newLines)
        }
        #expect(changed.count == 1)
        print("Keystroke reparse and diff took \(elapsed)")
    }
}
