import Foundation

/// Adds Parchment's hook to Claude Code's user settings (`~/.claude/settings.json`) and removes it.
///
/// Parchment's entries are recognised by their command, which always contains `marker`.
/// Everything else in the settings file is kept.
public enum HookInstaller {
    public static let marker = "Parchment/claude-hook.sh"
    public static let bundleIdentifier = "app.parchment.Parchment"

    /// The hook events Parchment listens to. Tool events get the "*" matcher (every tool).
    public static let events: [(name: String, isToolEvent: Bool)] = [
        ("SessionStart", false),
        ("SessionEnd", false),
        ("UserPromptSubmit", false),
        ("PreToolUse", true),
        ("PostToolUse", true),
        ("PostToolUseFailure", true),
        ("PermissionRequest", true),
        ("MessageDisplay", false),
        ("Notification", false),
        ("Stop", false),
        ("StopFailure", false),
        ("SubagentStart", false),
        ("SubagentStop", false)
    ]

    public enum Failure: Error, Equatable {
        /// The settings file exists but is not a JSON object. It is left untouched.
        case unreadableSettings
    }

    // MARK: Locations

    public static func supportDirectory(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Parchment", isDirectory: true)
    }

    public static func scriptURL(home: URL) -> URL {
        supportDirectory(home: home).appendingPathComponent("claude-hook.sh")
    }

    public static func inboxURL(home: URL) -> URL {
        supportDirectory(home: home).appendingPathComponent("Inbox", isDirectory: true)
    }

    public static func settingsURL(home: URL) -> URL {
        home.appendingPathComponent(".claude/settings.json")
    }

    /// The hook command: the script's absolute path, quoted for the shell.
    public static func command(scriptPath: String) -> String {
        "'" + scriptPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: The hook script

    /// Runs before and after every tool call, so it only copies stdin and renames a file.
    /// When Parchment is not running it writes nothing, unless the event is about a plan file:
    /// then it saves the event and opens Parchment in the background (`open -g`).
    public static let script = """
    #!/bin/sh
    # Passes Claude Code hook events to Parchment. Added from Parchment > Settings > Claude Code.
    # Remove it there with Disconnect.
    dir="$HOME/Library/Application Support/Parchment/Inbox"
    mkdir -p "$dir" || exit 0
    tmp="$dir/.$$.tmp"
    cat > "$tmp" || { rm -f "$tmp"; exit 0; }
    name="$dir/$(date +%s)-$$.json"
    if pgrep -x Parchment >/dev/null 2>&1; then
      mv "$tmp" "$name"
    elif grep -Eq '"tool_name" *: *"ExitPlanMode"' "$tmp" ||
         grep -Eiq '"file_path" *: *"[^"]*(/plans/[^"]*|plan[^"/]*)\\.(md|markdown)"' "$tmp"; then
      mv "$tmp" "$name" && open -g -b \(bundleIdentifier)
    fi
    rm -f "$tmp"
    exit 0

    """

    // MARK: Settings

    public static func isInstalled(in data: Data?) -> Bool {
        guard let data, let settings = try? object(from: data),
              let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { groups in
            (groups as? [[String: Any]])?.contains { group in
                (group["hooks"] as? [[String: Any]])?.contains(where: isParchmentHook) ?? false
            } ?? false
        }
    }

    /// True when Parchment's hook is set for every event in `events`. False after an update of
    /// Parchment that listens to more events than the installed hooks cover.
    public static func isCurrent(in data: Data?) -> Bool {
        guard let data, let settings = try? object(from: data),
              let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            (hooks[event.name] as? [[String: Any]])?.contains { group in
                (group["hooks"] as? [[String: Any]])?.contains(where: isParchmentHook) ?? false
            } ?? false
        }
    }

    /// The settings with Parchment's hooks added (replacing any older Parchment entries).
    /// `data` is the current file, or `nil` when there is none.
    public static func installing(into data: Data?, command: String) throws -> Data {
        var settings = try data.map(object(from:)) ?? [:]
        var hooks = withoutParchment(settings["hooks"] as? [String: Any] ?? [:])
        for event in events {
            var group: [String: Any] = [
                "hooks": [["type": "command", "command": command, "timeout": 10] as [String: Any]]
            ]
            if event.isToolEvent {
                group["matcher"] = "*"
            }
            var groups = hooks[event.name] as? [[String: Any]] ?? []
            groups.append(group)
            hooks[event.name] = groups
        }
        settings["hooks"] = hooks
        return try serialize(settings)
    }

    /// The settings without Parchment's hooks. Empty groups and events are removed too.
    public static func removing(from data: Data) throws -> Data {
        var settings = try object(from: data)
        guard let hooks = settings["hooks"] as? [String: Any] else { return try serialize(settings) }
        let remaining = withoutParchment(hooks)
        settings["hooks"] = remaining.isEmpty ? nil : remaining
        return try serialize(settings)
    }

    private static func withoutParchment(_ hooks: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else {
                result[event] = value
                continue
            }
            let kept: [[String: Any]] = groups.compactMap { group in
                guard let entries = group["hooks"] as? [[String: Any]] else { return group }
                let others = entries.filter { !isParchmentHook($0) }
                if others.isEmpty { return nil }
                var copy = group
                copy["hooks"] = others
                return copy
            }
            if !kept.isEmpty {
                result[event] = kept
            }
        }
        return result
    }

    private static func isParchmentHook(_ entry: [String: Any]) -> Bool {
        (entry["command"] as? String)?.contains(marker) ?? false
    }

    private static func object(from data: Data) throws -> [String: Any] {
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
            return [:]
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unreadableSettings
        }
        return object
    }

    private static func serialize(_ settings: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }
}
