/// UTF-16 code units for the ASCII characters Markdown syntax is built from.
enum Unit {
    static let tab = scalar("\t")
    static let newline = scalar("\n")
    static let carriageReturn = scalar("\r")
    static let space = scalar(" ")
    static let exclamation = scalar("!")
    static let quote = scalar("\"")
    static let hash = scalar("#")
    static let apostrophe = scalar("'")
    static let openParen = scalar("(")
    static let closeParen = scalar(")")
    static let asterisk = scalar("*")
    static let plus = scalar("+")
    static let comma = scalar(",")
    static let hyphen = scalar("-")
    static let period = scalar(".")
    static let slash = scalar("/")
    static let zero = scalar("0")
    static let nine = scalar("9")
    static let colon = scalar(":")
    static let semicolon = scalar(";")
    static let lessThan = scalar("<")
    static let greaterThan = scalar(">")
    static let question = scalar("?")
    static let openBracket = scalar("[")
    static let backslash = scalar("\\")
    static let closeBracket = scalar("]")
    static let underscore = scalar("_")
    static let backtick = scalar("`")
    static let openBrace = scalar("{")
    static let pipe = scalar("|")
    static let closeBrace = scalar("}")
    static let tilde = scalar("~")
    static let lowerX = scalar("x")
    static let lowerH = scalar("h")
    static let at = scalar("@")
    static let upperX = scalar("X")

    private static func scalar(_ value: Unicode.Scalar) -> UInt16 {
        UInt16(value.value)
    }

    static func isWhitespace(_ unit: UInt16?) -> Bool {
        guard let unit else { return true }
        return unit == space || unit == tab || unit == newline || unit == carriageReturn
    }

    static func isDigit(_ unit: UInt16?) -> Bool {
        guard let unit else { return false }
        return unit >= zero && unit <= nine
    }

    static func isASCIILetter(_ unit: UInt16?) -> Bool {
        guard let unit else { return false }
        return (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122)
    }

    static func isUppercaseASCII(_ unit: UInt16?) -> Bool {
        guard let unit else { return false }
        return unit >= 65 && unit <= 90
    }

    static func isIdentifierStart(_ unit: UInt16?) -> Bool {
        isASCIILetter(unit) || unit == underscore || unit == scalar("$") || unit == scalar("@")
    }

    static func isIdentifierPart(_ unit: UInt16?) -> Bool {
        isASCIILetter(unit) || isDigit(unit) || unit == underscore || unit == scalar("$")
    }

    /// Letters and digits, including non-ASCII letters, used for intraword checks.
    static func isAlphanumeric(_ unit: UInt16?) -> Bool {
        guard let unit else { return false }
        if isASCIILetter(unit) || isDigit(unit) { return true }
        // Treat any non-ASCII, non-surrogate-punctuation unit as a word character.
        return unit >= 0x00C0 && !(unit >= 0x2000 && unit <= 0x206F)
    }

    static func isASCIIPunctuation(_ unit: UInt16?) -> Bool {
        guard let unit else { return false }
        return (unit >= 33 && unit <= 47) || (unit >= 58 && unit <= 64)
            || (unit >= 91 && unit <= 96) || (unit >= 123 && unit <= 126)
    }
}
