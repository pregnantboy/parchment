import Foundation

/// Decides which Markdown files are plans worth opening automatically.
public enum PlanFileRule {
    static let extensions: Set<String> = ["md", "markdown"]

    /// True for `.md`/`.markdown` files in `~/.claude/plans/`, in any folder named `plans`, or whose
    /// name contains "plan" (any case). Claude Code's `ExitPlanMode` file is always a plan; the
    /// caller handles that case.
    public static func isPlanLike(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard extensions.contains(url.pathExtension.lowercased()) else { return false }
        if url.deletingPathExtension().lastPathComponent.lowercased().contains("plan") {
            return true
        }
        // Any folder on the path named "plans", which includes ~/.claude/plans.
        return url.deletingLastPathComponent().pathComponents.contains { $0.lowercased() == "plans" }
    }

    /// True for any Markdown file.
    public static func isMarkdown(path: String) -> Bool {
        extensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }
}
