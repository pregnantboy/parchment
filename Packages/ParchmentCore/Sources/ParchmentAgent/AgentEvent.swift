import Foundation

/// One Claude Code hook event, as the hook script passed it on.
public struct AgentEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case sessionStart
        case sessionEnd
        case promptSubmitted
        case toolStarted
        case toolFinished(succeeded: Bool)
        /// `permission_prompt`, `idle_prompt`, or another type Claude Code adds later.
        case notification(type: String)
        case stop
        case subagentStart
        case subagentStop
        /// Claude asks for permission to use a tool, the moment the prompt appears.
        case permissionRequested
        /// A piece of Claude's own text, as it is shown in the terminal.
        case message(delta: String, isFinal: Bool)
        /// The turn ended because of an API error, like a rate limit.
        case stopFailed(error: String)
    }

    public var kind: Kind
    public var sessionID: String
    public var cwd: String?
    /// Set when the event fired inside a subagent (a helper).
    public var agentID: String?
    public var agentType: String?
    public var toolName: String?
    public var toolInput: JSONValue?
    public var toolResponse: JSONValue?
    /// Links a tool's start to its end.
    public var toolUseID: String?
    /// Why a tool call failed.
    public var errorText: String?
    /// What the user typed, on `promptSubmitted`.
    public var prompt: String?
    /// Claude's (or a helper's) closing message, on `stop` and `subagentStop`.
    public var lastMessage: String?
    /// The message a `message` piece belongs to.
    public var messageID: String?
    /// What still runs in the background when Claude stops, one description each.
    public var backgroundTasks: [String]
    public var date: Date

    public init(
        kind: Kind,
        sessionID: String,
        cwd: String? = nil,
        agentID: String? = nil,
        agentType: String? = nil,
        toolName: String? = nil,
        toolInput: JSONValue? = nil,
        toolResponse: JSONValue? = nil,
        toolUseID: String? = nil,
        errorText: String? = nil,
        prompt: String? = nil,
        lastMessage: String? = nil,
        messageID: String? = nil,
        backgroundTasks: [String] = [],
        date: Date
    ) {
        self.kind = kind
        self.sessionID = sessionID
        self.cwd = cwd
        self.agentID = agentID
        self.agentType = agentType
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolResponse = toolResponse
        self.toolUseID = toolUseID
        self.errorText = errorText
        self.prompt = prompt
        self.lastMessage = lastMessage
        self.messageID = messageID
        self.backgroundTasks = backgroundTasks
        self.date = date
    }

    /// Decodes one hook input object. Returns `nil` for unreadable data, a missing session id,
    /// or an event Parchment does not use.
    public static func decode(_ data: Data, date: Date) -> AgentEvent? {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              let sessionID = json["session_id"]?.string, !sessionID.isEmpty,
              let name = json["hook_event_name"]?.string else { return nil }

        let kind: Kind
        switch name {
        case "SessionStart": kind = .sessionStart
        case "SessionEnd": kind = .sessionEnd
        case "UserPromptSubmit": kind = .promptSubmitted
        case "PreToolUse": kind = .toolStarted
        case "PostToolUse": kind = .toolFinished(succeeded: true)
        case "PostToolUseFailure": kind = .toolFinished(succeeded: false)
        case "Notification": kind = .notification(type: json["notification_type"]?.string ?? "")
        case "Stop": kind = .stop
        case "SubagentStart": kind = .subagentStart
        case "SubagentStop": kind = .subagentStop
        case "PermissionRequest": kind = .permissionRequested
        case "MessageDisplay":
            guard let delta = json["delta"]?.string else { return nil }
            kind = .message(delta: delta, isFinal: json["final"]?.bool ?? false)
        case "StopFailure": kind = .stopFailed(error: json["error"]?.string ?? "unknown")
        default: return nil
        }

        // Running tasks only: a finished one no longer keeps the session busy.
        let background: [String] = (json["background_tasks"]?.array ?? []).compactMap { task in
            if let status = task["status"]?.string, ["completed", "failed", "killed", "stopped"].contains(status) { return nil }
            return task["description"]?.string ?? task["command"]?.string ?? task["type"]?.string
        }

        return AgentEvent(
            kind: kind,
            sessionID: sessionID,
            cwd: json["cwd"]?.string,
            agentID: json["agent_id"]?.string,
            agentType: json["agent_type"]?.string,
            toolName: json["tool_name"]?.string,
            toolInput: json["tool_input"],
            toolResponse: json["tool_response"],
            toolUseID: json["tool_use_id"]?.string,
            errorText: json["error"]?.string,
            prompt: json["prompt"]?.string,
            lastMessage: json["last_assistant_message"]?.string,
            messageID: json["message_id"]?.string,
            backgroundTasks: background,
            date: date
        )
    }

    /// The file a file tool worked on. For `ExitPlanMode`, the plan file Claude Code wrote.
    public var filePath: String? {
        if toolName == "ExitPlanMode" {
            return toolResponse?["filePath"]?.string ?? toolInput?["filePath"]?.string
        }
        return toolInput?["file_path"]?.string ?? toolInput?["notebook_path"]?.string
    }

    /// True for tools that change a file's contents.
    public var editsFile: Bool {
        switch toolName {
        case "Write", "Edit", "MultiEdit", "NotebookEdit": true
        default: false
        }
    }
}
