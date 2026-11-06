/// A heading in the document outline.
public struct OutlineHeading: Identifiable, Hashable, Sendable {
    /// The heading line's start offset, unique within one snapshot of the document.
    public var id: Int { range.location }
    public var level: Int
    public var title: String
    /// The whole heading line.
    public var range: MarkdownRange

    public init(level: Int, title: String, range: MarkdownRange) {
        self.level = level
        self.title = title
        self.range = range
    }

    /// The headings of a parsed document, in order. Headings inside code blocks are ignored
    /// because the parser already classifies those lines as code.
    public static func headings(in lines: [MarkdownLine], text: MarkdownText) -> [OutlineHeading] {
        lines.compactMap { line in
            guard case .heading(let level) = line.kind else { return nil }
            let title = cleanTitle(text.string(in: line.contentRange))
            guard !title.isEmpty else { return nil }
            return OutlineHeading(level: level, title: title, range: line.range)
        }
    }

    /// Strips closing hashes and inline emphasis markers, so `## **Bold** idea ##` reads "Bold idea".
    static func cleanTitle(_ raw: String) -> String {
        var title = Substring(raw)
        while title.last == " " || title.last == "\t" { title.removeLast() }
        if title.last == "#" {
            let withoutHashes = title.reversed().drop { $0 == "#" }
            if withoutHashes.first == " " || withoutHashes.isEmpty {
                title = Substring(String(withoutHashes.reversed()))
            }
        }
        let markers: Set<Character> = ["*", "_", "`", "~"]
        let cleaned = title.filter { !markers.contains($0) }
        return cleaned.trimmingSpaces()
    }
}

private extension String {
    func trimmingSpaces() -> String {
        var slice = Substring(self)
        while slice.first == " " || slice.first == "\t" { slice.removeFirst() }
        while slice.last == " " || slice.last == "\t" { slice.removeLast() }
        return String(slice)
    }
}
