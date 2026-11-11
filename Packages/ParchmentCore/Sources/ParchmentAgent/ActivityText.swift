import Foundation

/// Short, plain descriptions of what a tool call does, for the status pill, the ticker and
/// the activity timeline.
public enum ActivityText {
    static let maxLength = 48
    /// Search patterns and queries are quoted, so they get less room.
    static let maxQuoteLength = 32

    /// One tool call, described while it runs and once it is over.
    public struct Phrase: Sendable, Equatable {
        /// "Editing StatusPill.swift"
        public var present: String
        /// "Edited StatusPill.swift"
        public var past: String
        /// True for tools that only look around (Read, Grep, todo updates). They are listed in
        /// the timeline but not announced in the ticker.
        public var isQuiet: Bool
    }

    public static func phrase(toolName: String, input: JSONValue?) -> Phrase {
        let file = fileName(input)
        switch toolName {
        case "Read":
            return Phrase(present: file.map { "Reading \($0)" } ?? "Reading", past: file.map { "Read \($0)" } ?? "Read a file", isQuiet: true)
        case "Write":
            return Phrase(present: file.map { "Writing \($0)" } ?? "Writing a file", past: file.map { "Wrote \($0)" } ?? "Wrote a file", isQuiet: file == nil)
        case "Edit", "MultiEdit", "NotebookEdit":
            return Phrase(present: file.map { "Editing \($0)" } ?? "Editing a file", past: file.map { "Edited \($0)" } ?? "Edited a file", isQuiet: file == nil)
        case "Bash":
            if let description = commandDescription(input) {
                return Phrase(present: description, past: description, isQuiet: false)
            }
            if let command = command(input) {
                return Phrase(present: "Running \(command)", past: "Ran \(command)", isQuiet: false)
            }
            return Phrase(present: "Running a command", past: "Ran a command", isQuiet: true)
        case "Grep":
            if let pattern = quoted(input?["pattern"]?.string) {
                return Phrase(present: "Searching for \(pattern)", past: "Searched for \(pattern)", isQuiet: true)
            }
            return Phrase(present: "Searching the code", past: "Searched the code", isQuiet: true)
        case "Glob":
            if let pattern = quoted(input?["pattern"]?.string) {
                return Phrase(present: "Looking for files like \(pattern)", past: "Looked for files like \(pattern)", isQuiet: true)
            }
            return Phrase(present: "Searching the code", past: "Searched the code", isQuiet: true)
        case "LS":
            return Phrase(present: "Searching the code", past: "Searched the code", isQuiet: true)
        case "WebSearch":
            if let query = quoted(input?["query"]?.string) {
                return Phrase(present: "Searching the web for \(query)", past: "Searched the web for \(query)", isQuiet: false)
            }
            return Phrase(present: "Searching the web", past: "Searched the web", isQuiet: false)
        case "WebFetch":
            let host = host(input)
            return Phrase(present: host.map { "Reading \($0)" } ?? "Reading a web page", past: host.map { "Read \($0)" } ?? "Read a web page", isQuiet: host == nil)
        case "Agent", "Task":
            if let task = helperTask(input) {
                return Phrase(present: "Starting a helper: \(task)", past: "Helper finished: \(task)", isQuiet: true)
            }
            return Phrase(present: "Starting a helper", past: "Helper finished", isQuiet: true)
        case "TodoWrite", "TaskCreate", "TaskUpdate", "TaskList", "TaskGet":
            return Phrase(present: "Updating the todo list", past: "Updated the todo list", isQuiet: true)
        case "EnterPlanMode":
            return Phrase(present: "Planning", past: "Started planning", isQuiet: true)
        case "ExitPlanMode":
            return Phrase(present: "Presenting the plan", past: "Plan approved", isQuiet: true)
        case "AskUserQuestion":
            if let question = question(input) {
                return Phrase(present: "Asking you: \(question)", past: "You answered: \(question)", isQuiet: true)
            }
            return Phrase(present: "Asking you a question", past: "You answered a question", isQuiet: true)
        case "Skill":
            if let skill = input?["skill"]?.string, !skill.isEmpty {
                return Phrase(present: "Using the \(skill) skill", past: "Used the \(skill) skill", isQuiet: true)
            }
            return Phrase(present: "Using a skill", past: "Used a skill", isQuiet: true)
        default:
            let name = mcpServer(toolName) ?? toolName
            return Phrase(present: "Using \(name)", past: "Used \(name)", isQuiet: true)
        }
    }

    /// What Claude is doing while a tool runs: "Editing StatusPill.swift", "Searching the code".
    public static func current(toolName: String, input: JSONValue?) -> String {
        phrase(toolName: toolName, input: input).present
    }

    /// A finished action worth listing in the ticker, or `nil` for quiet tools like Read and Grep.
    public static func finished(toolName: String, input: JSONValue?) -> String? {
        let phrase = phrase(toolName: toolName, input: input)
        return phrase.isQuiet ? nil : phrase.past
    }

    /// What Claude asks permission for, to follow "Needs your permission to": "run swift test",
    /// "edit StatusPill.swift".
    public static func request(toolName: String, input: JSONValue?) -> String {
        let file = fileName(input)
        switch toolName {
        case "Bash": return command(input).map { "run \($0)" } ?? "run a command"
        case "Read": return file.map { "read \($0)" } ?? "read a file"
        case "Write": return file.map { "write \($0)" } ?? "write a file"
        case "Edit", "MultiEdit", "NotebookEdit": return file.map { "edit \($0)" } ?? "edit a file"
        case "WebFetch": return host(input).map { "read \($0)" } ?? "read a web page"
        case "WebSearch": return "search the web"
        default: return "use \(mcpServer(toolName) ?? toolName)"
        }
    }

    static func fileName(_ input: JSONValue?) -> String? {
        guard let path = input?["file_path"]?.string ?? input?["notebook_path"]?.string, !path.isEmpty else { return nil }
        return (path as NSString).lastPathComponent
    }

    /// Claude's description of the command ("Run the unit tests"), if it gave one.
    static func commandDescription(_ input: JSONValue?) -> String? {
        guard let description = input?["description"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !description.isEmpty else { return nil }
        return shorten(description)
    }

    /// The command's first line, shortened.
    static func command(_ input: JSONValue?) -> String? {
        guard let command = input?["command"]?.string else { return nil }
        let firstLine = command.split(separator: "\n").first.map(String.init) ?? command
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : shorten(trimmed)
    }

    static func host(_ input: JSONValue?) -> String? {
        guard let raw = input?["url"]?.string, let host = URL(string: raw)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The short task Claude gave a helper, like "Find the hook installer".
    public static func helperTask(_ input: JSONValue?) -> String? {
        guard let task = input?["description"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !task.isEmpty else { return nil }
        return shorten(task)
    }

    /// The first question of an `AskUserQuestion` call.
    public static func question(_ input: JSONValue?) -> String? {
        guard let text = input?["questions"]?.array?.first?["question"]?.string?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return shorten(text, to: 120)
    }

    /// `mcp__github__create_issue` is "github".
    static func mcpServer(_ toolName: String) -> String? {
        guard toolName.hasPrefix("mcp__") else { return nil }
        let parts = toolName.dropFirst(5).components(separatedBy: "__")
        guard let server = parts.first, !server.isEmpty else { return nil }
        return server.replacingOccurrences(of: "_", with: " ")
    }

    /// The text in curly quotes, shortened; `nil` when there is none.
    static func quoted(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return "\u{201C}\(shorten(text, to: maxQuoteLength))\u{201D}"
    }

    static func shorten(_ text: String, to limit: Int = maxLength) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
