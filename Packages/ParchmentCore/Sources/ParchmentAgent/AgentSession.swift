import Foundation

/// What one Claude Code session is doing, built up from its hook events.
public struct AgentSession: Sendable, Equatable {
    public enum WaitReason: Sendable, Equatable {
        /// Claude finished its turn and waits for your next message.
        case finishedTurn
        /// Claude asks for permission to use a tool.
        case permission
        /// Claude has been waiting for input for a while.
        case idle
    }

    public enum Status: Sendable, Equatable {
        case working
        case waiting(WaitReason)
        case ended
    }

    /// A subagent working for the session.
    public struct Helper: Sendable, Equatable, Identifiable {
        public var id: String
        /// The helper's type, like "Explore".
        public var name: String
        public var activity: String?
    }

    /// A finished action for the ticker.
    public struct RecentAction: Sendable, Equatable, Identifiable {
        public var id: Int
        public var text: String
        public var succeeded: Bool
        public var date: Date
    }

    /// The last file change Claude made.
    public struct Edit: Sendable, Equatable {
        public var path: String
        /// "Claude" or a helper's type.
        public var owner: String
        public var date: Date
    }

    /// What the app should react to after an event.
    public enum Effect: Sendable, Equatable {
        /// The session's plan is now this file (new or different from before).
        case planChanged(path: String)
        /// A file was written or edited.
        case fileEdited(path: String, owner: String)
    }

    public static let mainAgentName = "Claude"
    static let maxRecentActions = 3

    public let id: String
    public private(set) var cwd: String?
    public private(set) var status: Status = .working
    /// What the main agent is doing right now.
    public private(set) var activity: String?
    public private(set) var helpers: [Helper] = []
    public private(set) var todoList = TodoList()
    public private(set) var planPath: String?
    public private(set) var lastEdit: Edit?
    public private(set) var recentActions: [RecentAction] = []
    public private(set) var lastEventDate: Date
    private var actionCounter = 0

    public init(id: String, date: Date) {
        self.id = id
        self.lastEventDate = date
    }

    public var todos: [AgentTodo] { todoList.items }

    @discardableResult
    public mutating func apply(_ event: AgentEvent) -> [Effect] {
        lastEventDate = max(lastEventDate, event.date)
        if let cwd = event.cwd { self.cwd = cwd }
        let agentName = event.agentID == nil ? Self.mainAgentName : (event.agentType ?? "Helper")

        switch event.kind {
        case .sessionStart:
            status = .waiting(.idle)
            activity = nil
            helpers = []

        case .sessionEnd:
            status = .ended
            activity = nil
            helpers = []

        case .promptSubmitted:
            status = .working
            activity = "Thinking"

        case .toolStarted:
            guard status != .ended, let tool = event.toolName else { break }
            status = .working
            let text = ActivityText.current(toolName: tool, input: event.toolInput)
            if let agentID = event.agentID {
                setHelper(id: agentID, name: agentName, activity: text)
            } else {
                activity = text
            }

        case .toolFinished(let succeeded):
            guard let tool = event.toolName else { break }
            if status != .ended { status = .working }
            return finishTool(tool, event: event, succeeded: succeeded, agentName: agentName)

        case .notification(let type):
            guard status != .ended else { break }
            switch type {
            case "permission_prompt": status = .waiting(.permission)
            case "idle_prompt": status = .waiting(.idle)
            default: break
            }

        case .stop:
            guard event.agentID == nil, status != .ended else { break }
            status = .waiting(.finishedTurn)
            activity = nil
            helpers = []

        case .subagentStart:
            guard let agentID = event.agentID else { break }
            setHelper(id: agentID, name: agentName, activity: nil)

        case .subagentStop:
            helpers.removeAll { $0.id == event.agentID }
        }
        return []
    }

    private mutating func finishTool(_ tool: String, event: AgentEvent, succeeded: Bool, agentName: String) -> [Effect] {
        var effects: [Effect] = []
        if succeeded {
            todoList.apply(toolName: tool, input: event.toolInput, response: event.toolResponse, agentName: agentName)
        }
        if let text = ActivityText.finished(toolName: tool, input: event.toolInput) {
            actionCounter += 1
            recentActions.append(RecentAction(id: actionCounter, text: text, succeeded: succeeded, date: event.date))
            if recentActions.count > Self.maxRecentActions {
                recentActions.removeFirst(recentActions.count - Self.maxRecentActions)
            }
        }
        guard succeeded, let path = event.filePath else { return effects }

        if event.editsFile {
            lastEdit = Edit(path: path, owner: agentName, date: event.date)
            effects.append(.fileEdited(path: path, owner: agentName))
        }
        let isPlan = tool == "ExitPlanMode" || (event.editsFile && PlanFileRule.isPlanLike(path: path))
        if isPlan, planPath != path {
            planPath = path
            effects.insert(.planChanged(path: path), at: 0)
        }
        return effects
    }

    private mutating func setHelper(id: String, name: String, activity: String?) {
        if let index = helpers.firstIndex(where: { $0.id == id }) {
            if let activity { helpers[index].activity = activity }
        } else {
            helpers.append(Helper(id: id, name: name, activity: activity))
        }
    }
}
