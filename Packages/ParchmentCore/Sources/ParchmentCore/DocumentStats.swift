/// Word count and reading time for a document or selection.
public struct DocumentStats: Hashable, Sendable {
    public var words: Int
    public var characters: Int

    /// Average adult silent reading speed for non-fiction.
    public static let wordsPerMinute = 238

    public static let empty = DocumentStats(words: 0, characters: 0)

    public init(words: Int, characters: Int) {
        self.words = words
        self.characters = characters
    }

    /// Whole minutes to read, rounding up, and at least one minute for any text at all.
    public var readingMinutes: Int {
        guard words > 0 else { return 0 }
        return (words + Self.wordsPerMinute - 1) / Self.wordsPerMinute
    }

    /// Counts words the way a reader would: Markdown punctuation like `#`, `-` and `**`
    /// is not a word, and each Chinese, Japanese or Korean character counts as one word.
    public init(counting string: String) {
        var words = 0
        var characters = 0
        var inWord = false
        for scalar in string.unicodeScalars {
            if !scalar.properties.isWhitespace {
                characters += 1
            }
            if Self.isIdeograph(scalar) {
                words += 1
                inWord = false
            } else if scalar.properties.isAlphabetic || scalar.properties.numericType != nil {
                if !inWord {
                    words += 1
                    inWord = true
                }
            } else if inWord, scalar == "'" || scalar == "\u{2019}" || scalar == "-" {
                // Keep contractions and hyphenated words together: don't, well-known.
                continue
            } else {
                inWord = false
            }
        }
        self.init(words: words, characters: characters)
    }

    private static func isIdeograph(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, // Hiragana, Katakana
             0x3400...0x4DBF, // CJK Extension A
             0x4E00...0x9FFF, // CJK Unified Ideographs
             0xAC00...0xD7AF, // Hangul syllables
             0xF900...0xFAFF, // CJK Compatibility Ideographs
             0x20000...0x2FFFF: // CJK Extensions B and later
            true
        default:
            false
        }
    }
}
