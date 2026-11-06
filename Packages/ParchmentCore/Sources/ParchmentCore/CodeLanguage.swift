/// Lexical rules for a family of programming languages, enough for line-by-line highlighting.
struct CodeLanguage: Sendable {
    var keywords: Set<String>
    var lineComments: [String]
    var blockComment: (open: String, close: String)?
    /// Characters that open a string literal.
    var stringDelimiters: Set<UInt16>
    /// Highlights capitalized identifiers as types.
    var highlightsTypes: Bool
    var isMarkup: Bool = false

    static func named(_ name: String) -> CodeLanguage {
        switch name {
        case "swift":
            cFamily(swiftKeywords)
        case "js", "javascript", "jsx", "ts", "typescript", "tsx", "mjs", "cjs":
            CodeLanguage(keywords: javaScriptKeywords, lineComments: ["//"], blockComment: ("/*", "*/"), stringDelimiters: [Unit.quote, Unit.apostrophe, Unit.backtick], highlightsTypes: true)
        case "py", "python":
            CodeLanguage(keywords: pythonKeywords, lineComments: ["#"], blockComment: nil, stringDelimiters: [Unit.quote, Unit.apostrophe], highlightsTypes: true)
        case "rb", "ruby":
            CodeLanguage(keywords: rubyKeywords, lineComments: ["#"], blockComment: nil, stringDelimiters: [Unit.quote, Unit.apostrophe], highlightsTypes: true)
        case "go", "golang":
            cFamily(goKeywords)
        case "rs", "rust":
            cFamily(rustKeywords)
        case "c", "h", "cpp", "c++", "cc", "hpp", "objc", "objective-c", "java", "kotlin", "kt", "cs", "csharp", "c#", "dart", "scala", "php":
            cFamily(cFamilyKeywords)
        case "sh", "bash", "zsh", "shell", "console", "fish":
            CodeLanguage(keywords: shellKeywords, lineComments: ["#"], blockComment: nil, stringDelimiters: [Unit.quote, Unit.apostrophe], highlightsTypes: false)
        case "sql", "postgres", "mysql", "sqlite":
            CodeLanguage(keywords: sqlKeywords, lineComments: ["--"], blockComment: ("/*", "*/"), stringDelimiters: [Unit.apostrophe, Unit.quote], highlightsTypes: false)
        case "json", "jsonc", "json5":
            CodeLanguage(keywords: ["true", "false", "null"], lineComments: ["//"], blockComment: nil, stringDelimiters: [Unit.quote], highlightsTypes: false)
        case "yaml", "yml", "toml", "ini", "conf", "dockerfile", "makefile", "r":
            CodeLanguage(keywords: ["true", "false", "null", "yes", "no", "on", "off"], lineComments: ["#"], blockComment: nil, stringDelimiters: [Unit.quote, Unit.apostrophe], highlightsTypes: false)
        case "css", "scss", "less":
            CodeLanguage(keywords: ["important", "media", "import", "keyframes", "from", "to", "root"], lineComments: [], blockComment: ("/*", "*/"), stringDelimiters: [Unit.quote, Unit.apostrophe], highlightsTypes: false)
        case "html", "xml", "svg", "plist", "vue", "svelte":
            CodeLanguage(keywords: [], lineComments: [], blockComment: ("<!--", "-->"), stringDelimiters: [Unit.quote, Unit.apostrophe], highlightsTypes: false, isMarkup: true)
        case "lua", "hs", "haskell":
            CodeLanguage(keywords: luaKeywords, lineComments: ["--"], blockComment: nil, stringDelimiters: [Unit.quote, Unit.apostrophe], highlightsTypes: true)
        default:
            CodeLanguage(keywords: genericKeywords, lineComments: ["//", "#"], blockComment: ("/*", "*/"), stringDelimiters: [Unit.quote, Unit.apostrophe], highlightsTypes: true)
        }
    }

    private static func cFamily(_ keywords: Set<String>) -> CodeLanguage {
        CodeLanguage(keywords: keywords, lineComments: ["//"], blockComment: ("/*", "*/"), stringDelimiters: [Unit.quote, Unit.apostrophe], highlightsTypes: true)
    }

    private static let swiftKeywords: Set<String> = [
        "actor", "any", "as", "async", "await", "break", "case", "catch", "class", "continue", "default", "defer",
        "deinit", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate", "final", "for", "func",
        "guard", "if", "import", "in", "init", "inout", "internal", "is", "let", "lazy", "mutating", "nil",
        "nonisolated", "open", "operator", "override", "private", "protocol", "public", "repeat", "rethrows",
        "return", "self", "Self", "some", "static", "struct", "subscript", "super", "switch", "throw", "throws",
        "true", "try", "typealias", "var", "weak", "where", "while", "@MainActor", "@Observable", "@State",
        "@Binding", "@Environment", "@main", "@escaping", "@available", "@objc", "consume", "borrowing", "consuming",
    ]

    private static let javaScriptKeywords: Set<String> = [
        "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete",
        "do", "else", "export", "extends", "false", "finally", "for", "from", "function", "if", "import", "in",
        "instanceof", "interface", "let", "new", "null", "of", "return", "static", "super", "switch", "this",
        "throw", "true", "try", "type", "typeof", "undefined", "var", "void", "while", "yield", "enum", "implements",
        "private", "public", "protected", "readonly", "as", "satisfies", "keyof",
    ]

    private static let pythonKeywords: Set<String> = [
        "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else",
        "except", "False", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "None",
        "nonlocal", "not", "or", "pass", "raise", "return", "True", "try", "while", "with", "yield", "self", "match", "case",
    ]

    private static let rubyKeywords: Set<String> = [
        "alias", "and", "begin", "break", "case", "class", "def", "do", "else", "elsif", "end", "ensure", "false",
        "for", "if", "in", "module", "next", "nil", "not", "or", "redo", "rescue", "retry", "return", "self",
        "super", "then", "true", "undef", "unless", "until", "when", "while", "yield", "require", "attr_reader",
        "attr_accessor", "private", "puts",
    ]

    private static let goKeywords: Set<String> = [
        "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func",
        "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct",
        "switch", "type", "var", "nil", "true", "false", "err",
    ]

    private static let rustKeywords: Set<String> = [
        "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false",
        "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return",
        "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while",
    ]

    private static let cFamilyKeywords: Set<String> = [
        "abstract", "auto", "bool", "break", "case", "catch", "char", "class", "const", "continue", "default",
        "delete", "do", "double", "else", "enum", "extends", "extern", "false", "final", "float", "for", "fun",
        "if", "implements", "import", "int", "interface", "long", "namespace", "new", "null", "nullptr", "object",
        "override", "package", "private", "protected", "public", "return", "short", "signed", "sizeof", "static",
        "struct", "super", "switch", "template", "this", "throw", "throws", "true", "try", "typedef", "typename",
        "union", "unsigned", "using", "val", "var", "virtual", "void", "volatile", "when", "while", "function",
        "echo", "#include", "#define", "#import", "#if", "#endif", "#ifdef", "#ifndef", "#pragma",
    ]

    private static let shellKeywords: Set<String> = [
        "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac", "in",
        "function", "return", "export", "local", "readonly", "source", "echo", "cd", "exit", "set", "unset",
        "sudo", "brew", "git", "npm", "swift", "xcodegen", "xcodebuild",
    ]

    private static let sqlKeywords: Set<String> = {
        let words = [
            "select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create", "table",
            "drop", "alter", "add", "index", "on", "join", "left", "right", "inner", "outer", "group", "by", "order",
            "having", "limit", "offset", "as", "and", "or", "not", "null", "is", "in", "like", "distinct", "union",
            "all", "primary", "key", "foreign", "references", "default", "with", "case", "when", "then", "else",
            "end", "count", "sum", "avg", "min", "max", "asc", "desc", "returning", "exists", "between",
        ]
        return Set(words + words.map { $0.uppercased() })
    }()

    private static let luaKeywords: Set<String> = [
        "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil",
        "not", "or", "repeat", "return", "then", "true", "until", "while", "let", "where", "module", "import", "data",
    ]

    private static let genericKeywords: Set<String> = [
        "if", "else", "for", "while", "return", "function", "func", "def", "class", "struct", "enum", "import",
        "export", "let", "var", "const", "true", "false", "null", "nil", "None", "new", "this", "self", "public",
        "private", "static", "try", "catch", "throw", "async", "await", "switch", "case", "break", "continue",
    ]
}
