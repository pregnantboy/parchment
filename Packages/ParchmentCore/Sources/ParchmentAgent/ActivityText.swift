import Foundation

/// Short, plain descriptions of what a tool call does, for the status pill and the ticker.
public enum ActivityText {
    static let maxLength = 48

    /// What Claude is doing while a tool runs: "Editing StatusPill.swift", "Searching the code".
    public static func current(toolName: String, input: JSONValue?) -> String {
        let file = fileName(input)
        switch toolName {
        case "Read": return file.map { "Reading \($0)" } ?? "Reading"
        case "Write": return file.map { "Writing \($0)" } ?? "Writing a file"
        case "Edit", "MultiEdit", "NotebookEdit": return file.map { "Editing \($0)" } ?? "Editing a file"
        case "Bash": return commandDescription(input) ?? command(input).map { "Running \($0)" } ?? "Running a command"
        case "Grep", "Glob", "LS": return "Searching the code"
        case "WebSearch": return "Searching the web"
        case "WebFetch": return host(input).map { "Reading \($0)" } ?? "Reading a web page"
        case "Agent", "Task": return "Starting a helper"
        case "TodoWrite", "TaskCreate", "TaskUpdate", "TaskList", "TaskGet": return "Updating the todo list"
        case "EnterPlanMode": return "Planning"
        case "ExitPlanMode": return "Presenting the plan"
        case "AskUserQuestion": return "Asking you a question"
        case "Skill": return "Using a skill"
        default: return mcpServer(toolName).map { "Using \($0)" } ?? "Using \(toolName)"
        }
    }

    /// A finished action worth listing in the ticker, or `nil` for quiet tools like Read and Grep.
    public static func finished(toolName: String, input: JSONValue?) -> String? {
        let file = fileName(input)
        switch toolName {
        case "Write": return file.map { "Wrote \($0)" }
        case "Edit", "MultiEdit", "NotebookEdit": return file.map { "Edited \($0)" }
        case "Bash": return commandDescription(input) ?? command(input).map { "Ran \($0)" }
        case "WebFetch": return host(input).map { "Read \($0)" }
        case "WebSearch": return "Searched the web"
        default: return nil
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

    /// `mcp__github__create_issue` is "github".
    static func mcpServer(_ toolName: String) -> String? {
        guard toolName.hasPrefix("mcp__") else { return nil }
        let parts = toolName.dropFirst(5).components(separatedBy: "__")
        guard let server = parts.first, !server.isEmpty else { return nil }
        return server.replacingOccurrences(of: "_", with: " ")
    }

    static func shorten(_ text: String) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
