import Foundation

/// Adds a short block to Claude Code's user memory (`~/.claude/CLAUDE.md`) asking Claude to keep
/// each plan task's box up to date, and removes it again.
///
/// The block sits between two HTML comments, so it can be found and replaced or removed without
/// touching anything else in the file.
public enum InstructionsInstaller {
    public static let startMarker = "<!-- parchment:task-states:start -->"
    public static let endMarker = "<!-- parchment:task-states:end -->"

    public static let instructions = """
    ## Plan task states (added by Parchment)

    When you work through a Markdown plan that has task checkboxes, keep each task's box up to \
    date in the file as you go, so the plan always shows where things stand:

    - `- [ ]` not started
    - `- [/]` in progress: mark a task when you start it
    - `- [!]` blocked: add a short reason, like `- [!] Deploy (blocked: needs an API key)`
    - `- [x]` done: mark it as soon as the task is finished

    Change only the character between the brackets, plus the reason for a blocked task. When a \
    blocked task is unblocked, set it back to `[/]` or `[ ]`.
    """

    public static var block: String {
        "\(startMarker)\n\(instructions)\n\(endMarker)\n"
    }

    public static func memoryURL(home: URL) -> URL {
        home.appendingPathComponent(".claude/CLAUDE.md")
    }

    public static func isInstalled(in text: String?) -> Bool {
        guard let text else { return false }
        return text.contains(startMarker)
    }

    /// The file with Parchment's block added at the end, replacing an older copy.
    /// `text` is the current file, or `nil` when there is none.
    public static func installing(into text: String?) -> String {
        let rest = removing(from: text ?? "")
        if rest.isEmpty { return block }
        let separator = rest.hasSuffix("\n\n") ? "" : (rest.hasSuffix("\n") ? "\n" : "\n\n")
        return rest + separator + block
    }

    /// The file without Parchment's block, and without the blank lines left around it.
    public static func removing(from text: String) -> String {
        guard let start = text.range(of: startMarker) else { return text }
        let end = text.range(of: endMarker, range: start.upperBound..<text.endIndex)?.upperBound ?? text.endIndex
        var before = String(text[..<start.lowerBound])
        var after = String(text[end...])
        if after.hasPrefix("\n") { after.removeFirst() }
        if after.isEmpty {
            while before.hasSuffix("\n\n") { before.removeLast() }
        }
        return before + after
    }
}
