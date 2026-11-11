import Foundation

/// Boils Claude's own messages down to one line for the status pill.
public enum MessageSummary {
    public static let maxLength = 140

    /// The sentence Claude is writing right now: the last sentence of the text so far.
    public static func latest(_ text: String) -> String? {
        sentences(in: text).last.map(shorten)
    }

    /// What a finished message comes down to. A closing question wins, since it is what Claude
    /// waits on; otherwise the opening sentence, where Claude usually states the outcome.
    public static func conclusion(_ text: String) -> String? {
        let all = sentences(in: text)
        guard let first = all.first else { return nil }
        if let last = all.last, last.hasSuffix("?") {
            return shorten(last)
        }
        return shorten(first)
    }

    /// The message as plain sentences: Markdown symbols and code blocks removed.
    static func sentences(in text: String) -> [String] {
        var result: [String] = []
        var inCodeBlock = false
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inCodeBlock.toggle()
                continue
            }
            // Table rows and rules say nothing in one line.
            if inCodeBlock || line.hasPrefix("|") || line.allSatisfy({ "-=*_ ".contains($0) }) { continue }
            line = plain(line)
            guard !line.isEmpty else { continue }
            result.append(contentsOf: split(line))
        }
        return result
    }

    /// Removes heading marks, list markers, emphasis and code ticks, and keeps a link's text.
    static func plain(_ line: String) -> String {
        var text = Substring(line)
        while let first = text.first, "#>".contains(first) || first == " " { text = text.dropFirst() }
        for marker in ["- [ ] ", "- [x] ", "- [/] ", "- [!] ", "- ", "* ", "+ "] where text.hasPrefix(marker) {
            text = text.dropFirst(marker.count)
            break
        }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "*" || character == "`" || (character == "_" && isEmphasisMark(text, at: index)) {
                index = text.index(after: index)
                continue
            }
            // [text](url) keeps only the text.
            if character == "[", let close = text[index...].firstIndex(of: "]"),
               text.index(after: close) < text.endIndex, text[text.index(after: close)] == "(",
               let end = text[close...].firstIndex(of: ")") {
                result += text[text.index(after: index)..<close]
                index = text.index(after: end)
                continue
            }
            result.append(character)
            index = text.index(after: index)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// An underscore at a word's edge is emphasis; inside a word (`snake_case`) it stays.
    private static func isEmphasisMark(_ text: Substring, at index: Substring.Index) -> Bool {
        let before = index > text.startIndex ? text[text.index(before: index)] : " "
        let afterIndex = text.index(after: index)
        let after = afterIndex < text.endIndex ? text[afterIndex] : " "
        return !(before.isLetter || before.isNumber) || !(after.isLetter || after.isNumber)
    }

    /// Splits at ". ", "? " and "! ". A period inside a file name or number has no space after it.
    private static func split(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var previous: Character = " "
        for character in line {
            if character == " ", ".?!".contains(previous), current.count > 1 {
                result.append(current)
                current = ""
            } else {
                current.append(character)
            }
            previous = character
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { result.append(rest) }
        return result
    }

    private static func shorten(_ text: String) -> String {
        ActivityText.shorten(text, to: maxLength)
    }
}

/// Short durations for the pill and the timeline: "42s", "3m 05s", "14 min", "1h 05m".
public enum ElapsedText {
    public static func short(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 { return "\(total)s" }
        if total < 10 * 60 { return "\(total / 60)m \(pad(total % 60))s" }
        if total < 60 * 60 { return "\(total / 60) min" }
        return "\(total / 3600)h \(pad(total % 3600 / 60))m"
    }

    private static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
