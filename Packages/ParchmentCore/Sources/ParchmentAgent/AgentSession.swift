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
        /// Claude asked you a question and waits for the answer.
        case question
        /// Claude presented a plan and waits for you to approve it.
        case planApproval
        /// Claude stopped, but work it started in the background still runs and will wake it.
        case background
        /// The turn ended with an API error, like a rate limit.
        case failed
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
        /// What Claude asked it to do, like "Find the hook installer".
        public var task: String?
        /// The sentence the helper is writing, if Claude Code reports helpers' text.
        public var narration: String?
        public var startDate: Date
    }

    /// A finished action for the ticker.
    public struct RecentAction: Sendable, Equatable, Identifiable {
        public var id: Int
        public var text: String
        public var succeeded: Bool
        public var date: Date
    }

    /// One line of the session's story, for the activity timeline.
    public struct TimelineEntry: Sendable, Equatable, Identifiable {
        public enum Outcome: Sendable, Equatable {
            case running
            case succeeded
            case failed
        }

        public enum Kind: Sendable, Equatable {
            /// What you asked for.
            case prompt
            /// Claude's own words.
            case said
            /// A tool call.
            case action(Outcome)
            case helperStarted
            case helperFinished
            /// Claude asked for permission.
            case asked
            /// The turn ended and Claude waits for you.
            case finished
            /// The turn ended with an error.
            case failed
        }

        public var id: Int
        public var kind: Kind
        public var text: String
        /// A second line: why an action failed, or what a helper reported.
        public var detail: String?
        /// "Claude" or a helper's type.
        public var owner: String
        public var date: Date
        /// How long an action, a helper or the turn took.
        public var duration: TimeInterval?
    }

    /// What happened since your last message.
    public struct TurnSummary: Sendable, Equatable {
        public var start: Date
        /// Names of the files written or edited, in order, each once.
        public var editedFiles: [String] = []
        public var commands = 0
        public var failures = 0
        public var helpers = 0

        /// "4 files edited · 6 commands · 1 failed · 2 helpers", or `nil` when nothing happened yet.
        public var text: String? {
            var parts: [String] = []
            if !editedFiles.isEmpty { parts.append(editedFiles.count == 1 ? "1 file edited" : "\(editedFiles.count) files edited") }
            if commands > 0 { parts.append(commands == 1 ? "1 command" : "\(commands) commands") }
            if failures > 0 { parts.append("\(failures) failed") }
            if helpers > 0 { parts.append(helpers == 1 ? "1 helper" : "\(helpers) helpers") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
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

    /// A tool call that started and has not finished.
    private struct RunningTool: Sendable, Equatable {
        var toolUseID: String?
        var toolName: String
        var agentID: String?
        var entryID: Int?
        var text: String
        var start: Date
    }

    /// A task Claude handed to a helper that has not started yet.
    private struct PendingHelperTask: Sendable, Equatable {
        var type: String?
        var task: String
    }

    /// A message being written, piece by piece.
    private struct OpenMessage: Sendable, Equatable {
        var messageID: String?
        var entryID: Int
        var text: String
    }

    public static let mainAgentName = "Claude"
    static let maxRecentActions = 3
    static let maxTimelineEntries = 200
    static let maxMessageLength = 4_000
    static let maxPromptLength = 600

    public let id: String
    public private(set) var cwd: String?
    public private(set) var status: Status = .working
    /// What the main agent is doing right now. `nil` between tool calls, while Claude thinks.
    public private(set) var activity: String?
    /// When the current activity started, for "Running the tests · 42s".
    public private(set) var activityStart: Date?
    /// The sentence Claude is writing right now, in its own words.
    public private(set) var narration: String?
    /// Your last message to Claude.
    public private(set) var prompt: String?
    /// Claude's closing message of the last turn.
    public private(set) var lastMessage: String?
    /// What Claude asks permission for, like "run swift test".
    public private(set) var permissionRequest: String?
    /// The question Claude asked you.
    public private(set) var question: String?
    /// Why the last turn failed, like "Rate limit reached".
    public private(set) var failure: String?
    /// What still runs in the background after Claude stopped.
    public private(set) var backgroundTasks: [String] = []
    public private(set) var helpers: [Helper] = []
    public private(set) var todoList = TodoList()
    public private(set) var planPath: String?
    public private(set) var lastEdit: Edit?
    public private(set) var recentActions: [RecentAction] = []
    public private(set) var timeline: [TimelineEntry] = []
    public private(set) var turn: TurnSummary
    public private(set) var lastEventDate: Date
    private var actionCounter = 0
    private var entryCounter = 0
    private var running: [RunningTool] = []
    /// Keyed by the writer: "" for Claude, else the helper's id.
    private var openMessages: [String: OpenMessage] = [:]
    /// Tasks Claude handed to helpers that have not started yet, by helper type.
    private var pendingHelperTasks: [PendingHelperTask] = []
    /// Whose permission request is open: "" for Claude, else the helper's id.
    private var permissionOwner: String?

    public init(id: String, date: Date) {
        self.id = id
        self.lastEventDate = date
        self.turn = TurnSummary(start: date)
    }

    public var todos: [AgentTodo] { todoList.items }

    /// True while a tool call or a helper is under way, so silence is expected.
    public var hasRunningWork: Bool { !running.isEmpty || !helpers.isEmpty }

    /// True when a working session has sent nothing for `interval` although nothing is running.
    public func isStale(at date: Date, after interval: TimeInterval) -> Bool {
        status == .working && !hasRunningWork && date.timeIntervalSince(lastEventDate) > interval
    }

    @discardableResult
    public mutating func apply(_ event: AgentEvent) -> [Effect] {
        lastEventDate = max(lastEventDate, event.date)
        if let cwd = event.cwd { self.cwd = cwd }
        let agentName = event.agentID == nil ? Self.mainAgentName : (event.agentType ?? "Helper")

        switch event.kind {
        case .sessionStart:
            status = .waiting(.idle)
            clearLiveState()

        case .sessionEnd:
            status = .ended
            clearLiveState()

        case .promptSubmitted:
            status = .working
            clearLiveState()
            lastMessage = nil
            failure = nil
            backgroundTasks = []
            turn = TurnSummary(start: event.date)
            if let text = event.prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                prompt = ActivityText.shorten(text, to: Self.maxPromptLength)
                addEntry(.prompt, text: prompt ?? text, owner: "You", date: event.date)
            }

        case .toolStarted:
            guard status != .ended, let tool = event.toolName else { break }
            startTool(tool, event: event, agentName: agentName)

        case .toolFinished(let succeeded):
            guard let tool = event.toolName else { break }
            return finishTool(tool, event: event, succeeded: succeeded, agentName: agentName)

        case .permissionRequested:
            guard status != .ended, let tool = event.toolName else { break }
            requestPermission(tool, event: event, agentName: agentName)

        case .notification(let type):
            guard status != .ended else { break }
            switch type {
            case "permission_prompt":
                // The question and plan prompts are permission prompts too; keep the clearer reason.
                if status == .working { status = .waiting(.permission) }
            case "idle_prompt":
                if status == .working { status = .waiting(.idle) }
            default:
                break
            }

        case .message(let delta, let isFinal):
            guard status != .ended else { break }
            appendMessage(delta, isFinal: isFinal, event: event, agentName: agentName)

        case .stop:
            guard event.agentID == nil, status != .ended else { break }
            let written = openMessages[""]?.text
            clearLiveState()
            backgroundTasks = event.backgroundTasks
            status = .waiting(backgroundTasks.isEmpty ? .finishedTurn : .background)
            if let message = event.lastMessage ?? written, !message.isEmpty {
                lastMessage = ActivityText.shorten(message, to: Self.maxMessageLength)
            }
            addEntry(.finished, text: "Finished the turn", detail: turn.text, owner: Self.mainAgentName, date: event.date,
                     duration: event.date.timeIntervalSince(turn.start))

        case .stopFailed(let error):
            guard status != .ended else { break }
            clearLiveState()
            failure = Self.failureText(error)
            status = .waiting(.failed)
            addEntry(.failed, text: "Stopped: \(failure ?? error)", owner: Self.mainAgentName, date: event.date)

        case .subagentStart:
            guard let agentID = event.agentID else { break }
            let isNew = !helpers.contains { $0.id == agentID }
            setHelper(id: agentID, name: agentName, activity: nil, date: event.date)
            guard isNew, let index = helpers.firstIndex(where: { $0.id == agentID }) else { break }
            helpers[index].task = takeHelperTask(type: event.agentType)
            turn.helpers += 1
            let task = helpers[index].task.map { ": \($0)" } ?? ""
            addEntry(.helperStarted, text: "\(agentName) started\(task)", owner: agentName, date: event.date)

        case .subagentStop:
            // Claude Code also runs agents of its own (prompt suggestions, side questions) that
            // stop without having started as helpers. Only known helpers are reported.
            guard let index = helpers.firstIndex(where: { $0.id == event.agentID }) else { break }
            let helper = helpers.remove(at: index)
            running.removeAll { $0.agentID == helper.id }
            openMessages[helper.id] = nil
            addEntry(.helperFinished, text: "\(helper.name) finished", detail: event.lastMessage.flatMap(MessageSummary.conclusion),
                     owner: helper.name, date: event.date, duration: event.date.timeIntervalSince(helper.startDate))
        }
        return []
    }

    // MARK: Tools

    private mutating func startTool(_ tool: String, event: AgentEvent, agentName: String) {
        let phrase = ActivityText.phrase(toolName: tool, input: event.toolInput)
        let isMain = event.agentID == nil

        if tool == "AskUserQuestion", isMain {
            status = .waiting(.question)
            question = ActivityText.question(event.toolInput)
        } else if permissionOwner == nil || permissionOwner == (event.agentID ?? "") {
            // Another agent starting a tool does not answer an open permission request.
            status = .working
            permissionOwner = nil
            permissionRequest = nil
        }

        var entryID: Int?
        if tool == "Agent" || tool == "Task" {
            // The helper's own start and finish lines tell this part of the story.
            if let task = ActivityText.helperTask(event.toolInput) {
                pendingHelperTasks.append(PendingHelperTask(type: event.toolInput?["subagent_type"]?.string, task: task))
            }
        } else {
            entryID = addEntry(.action(.running), text: phrase.present, owner: agentName, date: event.date)
        }
        running.append(RunningTool(toolUseID: event.toolUseID, toolName: tool, agentID: event.agentID, entryID: entryID,
                                   text: phrase.present, start: event.date))

        if let agentID = event.agentID {
            setHelper(id: agentID, name: agentName, activity: phrase.present, date: event.date)
        } else {
            activity = phrase.present
            activityStart = event.date
        }
    }

    private mutating func finishTool(_ tool: String, event: AgentEvent, succeeded: Bool, agentName: String) -> [Effect] {
        var effects: [Effect] = []
        let phrase = ActivityText.phrase(toolName: tool, input: event.toolInput)
        if status != .ended {
            status = .working
            permissionOwner = nil
            permissionRequest = nil
            question = nil
        }
        if succeeded {
            todoList.apply(toolName: tool, input: event.toolInput, response: event.toolResponse, agentName: agentName)
        }

        // Close the timeline line the tool's start opened, or add one if the start was missed.
        let started = takeRunningTool(tool, event: event)
        let detail = succeeded ? nil : event.errorText.flatMap(Self.firstLine)
        let outcome: TimelineEntry.Outcome = succeeded ? .succeeded : .failed
        if let entryID = started?.entryID, let index = timeline.firstIndex(where: { $0.id == entryID }) {
            timeline[index].kind = .action(outcome)
            timeline[index].text = phrase.past
            timeline[index].detail = detail
            timeline[index].duration = started.map { event.date.timeIntervalSince($0.start) }
        } else if tool != "Agent", tool != "Task" {
            addEntry(.action(outcome), text: phrase.past, detail: detail, owner: agentName, date: event.date)
        }

        // Back to whatever else still runs, or to thinking.
        if let agentID = event.agentID {
            if let index = helpers.firstIndex(where: { $0.id == agentID }) {
                helpers[index].activity = running.last { $0.agentID == agentID }?.text
            }
        } else {
            let other = running.last { $0.agentID == nil }
            activity = other?.text
            activityStart = other?.start
        }

        if !succeeded { turn.failures += 1 }
        if tool == "Bash" { turn.commands += 1 }

        if !phrase.isQuiet {
            actionCounter += 1
            recentActions.append(RecentAction(id: actionCounter, text: phrase.past, succeeded: succeeded, date: event.date))
            if recentActions.count > Self.maxRecentActions {
                recentActions.removeFirst(recentActions.count - Self.maxRecentActions)
            }
        }
        guard succeeded, let path = event.filePath else { return effects }

        if event.editsFile {
            lastEdit = Edit(path: path, owner: agentName, date: event.date)
            effects.append(.fileEdited(path: path, owner: agentName))
            let name = (path as NSString).lastPathComponent
            if !turn.editedFiles.contains(name) { turn.editedFiles.append(name) }
        }
        let isPlan = tool == "ExitPlanMode" || (event.editsFile && PlanFileRule.isPlanLike(path: path))
        if isPlan, planPath != path {
            planPath = path
            effects.insert(.planChanged(path: path), at: 0)
        }
        return effects
    }

    /// The started call this finish belongs to: by id, else the latest same tool of the same agent.
    private mutating func takeRunningTool(_ tool: String, event: AgentEvent) -> RunningTool? {
        let index = event.toolUseID.flatMap { id in running.lastIndex { $0.toolUseID == id } }
            ?? running.lastIndex { $0.toolName == tool && $0.agentID == event.agentID }
        return index.map { running.remove(at: $0) }
    }

    private mutating func requestPermission(_ tool: String, event: AgentEvent, agentName: String) {
        permissionOwner = event.agentID ?? ""
        switch tool {
        case "AskUserQuestion":
            status = .waiting(.question)
            question = ActivityText.question(event.toolInput) ?? question
        case "ExitPlanMode":
            status = .waiting(.planApproval)
        default:
            status = .waiting(.permission)
            let request = ActivityText.request(toolName: tool, input: event.toolInput)
            permissionRequest = request
            addEntry(.asked, text: "Asked permission to \(request)", owner: agentName, date: event.date)
        }
    }

    // MARK: Messages

    private mutating func appendMessage(_ delta: String, isFinal: Bool, event: AgentEvent, agentName: String) {
        let key = event.agentID ?? ""
        var message: OpenMessage
        if let open = openMessages[key], open.messageID == event.messageID, timeline.contains(where: { $0.id == open.entryID }) {
            message = open
        } else {
            guard !delta.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            message = OpenMessage(messageID: event.messageID, entryID: addEntry(.said, text: "", owner: agentName, date: event.date), text: "")
        }
        if message.text.count < Self.maxMessageLength {
            message.text += delta
        }
        if let index = timeline.firstIndex(where: { $0.id == message.entryID }) {
            timeline[index].text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        openMessages[key] = isFinal ? nil : message

        let latest = MessageSummary.latest(message.text)
        if let agentID = event.agentID {
            if let index = helpers.firstIndex(where: { $0.id == agentID }) {
                helpers[index].narration = latest
            }
        } else {
            narration = latest
        }
    }

    // MARK: Helpers

    private mutating func setHelper(id: String, name: String, activity: String?, date: Date) {
        if let index = helpers.firstIndex(where: { $0.id == id }) {
            if let activity { helpers[index].activity = activity }
        } else {
            helpers.append(Helper(id: id, name: name, activity: activity, startDate: date))
        }
    }

    /// The task Claude gave the helper that just started: the oldest waiting one for its type.
    private mutating func takeHelperTask(type: String?) -> String? {
        let index = pendingHelperTasks.firstIndex { $0.type == type } ?? pendingHelperTasks.firstIndex { $0.type == nil }
        return index.map { pendingHelperTasks.remove(at: $0).task }
    }

    // MARK: Timeline

    @discardableResult
    private mutating func addEntry(_ kind: TimelineEntry.Kind, text: String, detail: String? = nil, owner: String, date: Date,
                                   duration: TimeInterval? = nil) -> Int {
        entryCounter += 1
        timeline.append(TimelineEntry(id: entryCounter, kind: kind, text: text, detail: detail, owner: owner, date: date, duration: duration))
        if timeline.count > Self.maxTimelineEntries {
            timeline.removeFirst(timeline.count - Self.maxTimelineEntries)
        }
        return entryCounter
    }

    /// Forgets everything that only holds while Claude is in the middle of a turn. Actions still
    /// marked as running are closed, since their end was not seen.
    private mutating func clearLiveState() {
        activity = nil
        activityStart = nil
        narration = nil
        permissionRequest = nil
        permissionOwner = nil
        question = nil
        helpers = []
        running = []
        openMessages = [:]
        pendingHelperTasks = []
        for index in timeline.indices where timeline[index].kind == .action(.running) {
            timeline[index].kind = .action(.succeeded)
        }
    }

    private static func firstLine(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return line.isEmpty ? nil : ActivityText.shorten(line, to: 160)
    }

    /// Claude Code's error types in plain words.
    static func failureText(_ error: String) -> String {
        switch error {
        case "rate_limit": "Rate limit reached"
        case "overloaded": "Claude is overloaded"
        case "authentication_failed", "oauth_org_not_allowed", "cloud_credential_error": "Sign-in problem"
        case "account_on_hold", "billing_error": "Billing problem"
        case "max_output_tokens": "The reply got too long"
        case "server_error": "Server error"
        case "model_not_found": "Model not found"
        default: "An error stopped the turn"
        }
    }
}
