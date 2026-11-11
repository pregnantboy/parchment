import Foundation
import Testing
import ParchmentCore
@testable import ParchmentAgent

private let start = Date(timeIntervalSince1970: 1_000)

private func event(_ json: String, at seconds: Double = 0) -> AgentEvent {
    AgentEvent.decode(Data(json.utf8), date: start.addingTimeInterval(seconds))!
}

private func tool(_ hook: String, _ name: String, input: String = "{}", response: String = "null", agent: String? = nil) -> AgentEvent {
    let agentFields = agent.map { #", "agent_id": "a1", "agent_type": "\#($0)""# } ?? ""
    return event(#"{"session_id": "s1", "cwd": "/repo", "hook_event_name": "\#(hook)", "tool_name": "\#(name)", "tool_input": \#(input), "tool_response": \#(response)\#(agentFields)}"#)
}

@Suite("Hook events and sessions")
struct AgentSessionTests {
    @Test func decodesToolEventsAndIgnoresUnknownOnes() {
        let decoded = tool("PostToolUse", "Write", input: #"{"file_path": "/repo/docs/plans/x.md", "content": "hi"}"#)
        #expect(decoded.kind == .toolFinished(succeeded: true))
        #expect(decoded.sessionID == "s1")
        #expect(decoded.filePath == "/repo/docs/plans/x.md")
        #expect(decoded.editsFile)
        #expect(AgentEvent.decode(Data(#"{"session_id": "s1", "hook_event_name": "Mystery"}"#.utf8), date: start) == nil)
        #expect(AgentEvent.decode(Data("not json".utf8), date: start) == nil)
    }

    @Test func exitPlanModeFileComesFromTheResponse() {
        let decoded = tool("PostToolUse", "ExitPlanMode", response: ##"{"plan": "# P", "filePath": "/Users/me/.claude/plans/p.md"}"##)
        #expect(decoded.filePath == "/Users/me/.claude/plans/p.md")
        var session = AgentSession(id: "s1", date: start)
        let effects1 = session.apply(decoded)
        #expect(effects1 == [.planChanged(path: "/Users/me/.claude/plans/p.md")])
        #expect(session.planPath == "/Users/me/.claude/plans/p.md")
    }

    @Test func writingAPlanFileMakesItThePlanOnce() {
        var session = AgentSession(id: "s1", date: start)
        let write = tool("PostToolUse", "Write", input: #"{"file_path": "/repo/docs/plans/x.md"}"#)
        let effects2 = session.apply(write)
        #expect(effects2 == [.planChanged(path: "/repo/docs/plans/x.md"), .fileEdited(path: "/repo/docs/plans/x.md", owner: "Claude")])
        let effects3 = session.apply(write)
        #expect(effects3 == [.fileEdited(path: "/repo/docs/plans/x.md", owner: "Claude")])
        let other = tool("PostToolUse", "Edit", input: #"{"file_path": "/repo/README.md"}"#)
        let effects4 = session.apply(other)
        #expect(effects4 == [.fileEdited(path: "/repo/README.md", owner: "Claude")])
        #expect(session.planPath == "/repo/docs/plans/x.md")
    }

    @Test func statusFollowsTheConversation() {
        var session = AgentSession(id: "s1", date: start)
        session.apply(event(#"{"session_id": "s1", "hook_event_name": "SessionStart"}"#))
        #expect(session.status == .waiting(.idle))
        session.apply(event(#"{"session_id": "s1", "hook_event_name": "UserPromptSubmit", "prompt": "go"}"#))
        #expect(session.status == .working)
        session.apply(tool("PreToolUse", "Bash", input: #"{"command": "swift test --parallel", "description": "Run the unit tests"}"#))
        #expect(session.activity == "Run the unit tests")
        session.apply(event(#"{"session_id": "s1", "hook_event_name": "Notification", "notification_type": "permission_prompt", "message": "m"}"#))
        #expect(session.status == .waiting(.permission))
        session.apply(tool("PostToolUse", "Bash", input: #"{"command": "swift test"}"#))
        #expect(session.status == .working)
        #expect(session.recentActions.map(\.text) == ["Ran swift test"])
        session.apply(event(#"{"session_id": "s1", "hook_event_name": "Stop", "stop_hook_active": false}"#))
        #expect(session.status == .waiting(.finishedTurn))
        #expect(session.activity == nil)
        session.apply(event(#"{"session_id": "s1", "hook_event_name": "SessionEnd", "reason": "exit"}"#))
        #expect(session.status == .ended)
        session.apply(tool("PreToolUse", "Read"))
        #expect(session.status == .ended)
    }

    @Test func helpersAreTrackedSeparately() {
        var session = AgentSession(id: "s1", date: start)
        session.apply(event(#"{"session_id": "s1", "hook_event_name": "SubagentStart", "agent_id": "a1", "agent_type": "Explore"}"#))
        session.apply(tool("PreToolUse", "Grep", agent: "Explore"))
        #expect(session.helpers.map(\.name) == ["Explore"])
        #expect(session.helpers.first?.activity == "Searching the code")
        #expect(session.activity == nil)
        let edit = tool("PostToolUse", "Edit", input: #"{"file_path": "/repo/plan.md"}"#, agent: "Explore")
        let effects5 = session.apply(edit)
        #expect(effects5.contains(.fileEdited(path: "/repo/plan.md", owner: "Explore")))
        session.apply(event(#"{"session_id": "s1", "hook_event_name": "SubagentStop", "agent_id": "a1", "agent_type": "Explore"}"#))
        #expect(session.helpers.isEmpty)
    }

    @Test func tickerKeepsTheLastThreeActions() {
        var session = AgentSession(id: "s1", date: start)
        for name in ["a", "b", "c", "d"] {
            session.apply(tool("PostToolUse", "Edit", input: #"{"file_path": "/repo/\#(name).swift"}"#))
        }
        session.apply(tool("PostToolUse", "Read", input: #"{"file_path": "/repo/e.swift"}"#))
        session.apply(tool("PostToolUseFailure", "Bash", input: #"{"command": "make"}"#))
        #expect(session.recentActions.map(\.text) == ["Edited c.swift", "Edited d.swift", "Ran make"])
        #expect(session.recentActions.last?.succeeded == false)
    }
}

@Suite("Todo list")
struct TodoListTests {
    @Test func todoWriteReplacesTheList() {
        var list = TodoList()
        let input: JSONValue = .object(["todos": .array([
            .object(["content": .string("Parse events"), "status": .string("completed"), "activeForm": .string("Parsing events")]),
            .object(["content": .string("Draw the pill"), "status": .string("in_progress"), "activeForm": .string("Drawing the pill")]),
            .object(["content": .string("Ship"), "status": .string("pending")])
        ])])
        let changed = list.apply(toolName: "TodoWrite", input: input, response: nil, agentName: "Claude")
        #expect(changed)
        #expect(list.items.map(\.status) == [.completed, .inProgress, .pending])
        #expect(list.items[1].owner == "Claude")
        #expect(list.items[0].owner == nil)
    }

    @Test func taskToolsChangeOneItem() {
        var list = TodoList()
        list.apply(toolName: "TaskCreate", input: .object(["subject": .string("Write tests")]), response: .string("Task #7 created successfully: Write tests"), agentName: "Claude")
        list.apply(toolName: "TaskCreate", input: .object(["subject": .string("Fix CI")]), response: .object(["task": .object(["id": .number(8)])]), agentName: "Claude")
        #expect(list.items.map(\.id) == ["7", "8"])
        list.apply(toolName: "TaskUpdate", input: .object(["taskId": .string("7"), "status": .string("in_progress")]), response: nil, agentName: "Explore")
        #expect(list.items[0].status == .inProgress)
        #expect(list.items[0].owner == "Explore")
        list.apply(toolName: "TaskUpdate", input: .object(["taskId": .string("8"), "status": .string("deleted")]), response: nil, agentName: "Claude")
        #expect(list.items.map(\.id) == ["7"])
    }

    @Test func taskCreateWithoutAnIdGetsALocalOne() {
        var list = TodoList()
        list.apply(toolName: "TaskCreate", input: .object(["subject": .string("A")]), response: nil, agentName: "Claude")
        #expect(list.items.first?.id == "local-1")
    }
}

@Suite("Progress")
struct ProgressTests {
    private func steps(_ string: String) -> [PlanStep] {
        let text = MarkdownText(string)
        return PlanSteps.steps(in: MarkdownParser.lines(in: text), text: text)
    }

    @Test func checkboxesGiveACount() {
        let plan = steps("- [x] Parse hook events\n- [ ] Draw the status pill\n- [ ] Ship it")
        let progress = PlanProgress.make(steps: plan, todos: [], lastEdit: nil)
        #expect(progress.label == .count(done: 1, total: 3))
        #expect(progress.currentSteps == [PlanProgress.CurrentStep(index: 1, owner: nil)])
        #expect(!progress.isComplete)
    }

    @Test func inProgressBoxesAreCurrentAndBlockedOnesAreSkipped() {
        let plan = steps("- [x] Parse hook events\n- [!] Sign the app\n- [ ] Draw the pill\n- [/] Draw margin marks")
        let progress = PlanProgress.make(steps: plan, todos: [], lastEdit: nil)
        #expect(progress.label == .count(done: 1, total: 4))
        #expect(progress.currentSteps == [PlanProgress.CurrentStep(index: 3, owner: nil)])

        let noneStarted = steps("- [!] Sign the app\n- [ ] Draw the pill")
        #expect(PlanProgress.make(steps: noneStarted, todos: [], lastEdit: nil).currentSteps == [PlanProgress.CurrentStep(index: 1, owner: nil)])
    }

    @Test func inProgressTodosPointAtTheirSteps() {
        let plan = steps("- [ ] Parse hook events\n- [ ] Draw the status pill\n- [ ] Draw margin marks")
        let todos = [
            AgentTodo(id: "1", content: "Draw the shimmering status pill", status: .inProgress, owner: "Claude"),
            AgentTodo(id: "2", content: "Margin marks for changed lines", status: .inProgress, owner: "Explore")
        ]
        let progress = PlanProgress.make(steps: plan, todos: todos, lastEdit: nil)
        #expect(progress.currentSteps == [
            PlanProgress.CurrentStep(index: 1, owner: "Claude"),
            PlanProgress.CurrentStep(index: 2, owner: "Explore")
        ])
    }

    @Test func todosCountWhenThePlanHasNoCheckboxes() {
        let plan = steps("## Phase 1: Events\n## Phase 2: Pill")
        let todos = [
            AgentTodo(id: "1", content: "a", status: .completed),
            AgentTodo(id: "2", content: "b", status: .pending)
        ]
        let progress = PlanProgress.make(steps: plan, todos: todos, lastEdit: (25, "Claude"))
        #expect(progress.label == .count(done: 1, total: 2))
        #expect(progress.fraction == 0.5)
        #expect(progress.currentSteps == [PlanProgress.CurrentStep(index: 1, owner: "Claude")])
    }

    @Test func structureAloneGivesAStepGuess() {
        let plan = steps("1. Install\n2. Configure\n3. Ship")
        let progress = PlanProgress.make(steps: plan, todos: [], lastEdit: (12, "Claude"))
        #expect(progress.label == .step(current: 2, total: 3))
        #expect(PlanProgress.make(steps: plan, todos: [], lastEdit: nil) == .empty)
    }

    @Test func allCheckedIsComplete() {
        let progress = PlanProgress.make(steps: steps("- [x] a\n- [x] b"), todos: [], lastEdit: nil)
        #expect(progress.isComplete)
        #expect(progress.currentSteps.isEmpty)
    }

    @Test func startedTasksCountAsHalf() {
        let progress = PlanProgress.make(steps: steps("- [x] a\n- [/] b\n- [!] c\n- [ ] d"), todos: [], lastEdit: nil)
        #expect(progress.segments == [
            .init(state: .done, fill: 1), .init(state: .inProgress, fill: 0.5),
            .init(state: .blocked, fill: 0), .init(state: .open, fill: 0)
        ])
        #expect(progress.fraction == 0.375)
        #expect(progress.percentText == "38%")
        #expect(!progress.isEstimate)
    }

    @Test func subStepsFillTheirParent() {
        let plan = steps("- [ ] Build the pill\n  - [x] Layout\n  - [x] Colors\n  - [ ] Shimmer\n  - [ ] Timer\n- [ ] Ship it\n- [x] Plan it\n  - [ ] Left unticked")
        let progress = PlanProgress.make(steps: plan, todos: [], lastEdit: nil)
        // Every checkbox still counts in "3 of 8"; the bar has one piece per top-level task.
        #expect(progress.label == .count(done: 3, total: 8))
        #expect(progress.segments == [
            .init(state: .inProgress, fill: 0.5), .init(state: .open, fill: 0), .init(state: .done, fill: 1)
        ])
        #expect(progress.fraction == 0.5)

        // All sub-steps ticked, parent not: nearly full, never full.
        let almost = PlanProgress.make(steps: steps("- [ ] a\n  - [x] b\n  - [x] c"), todos: [], lastEdit: nil)
        #expect(almost.segments == [.init(state: .inProgress, fill: 0.9)])
        #expect(!almost.isComplete)

        let blocked = PlanProgress.make(steps: steps("- [ ] a\n  - [!] b\n  - [ ] c"), todos: [], lastEdit: nil)
        #expect(blocked.segments == [.init(state: .blocked, fill: 0)])
    }

    @Test func todosFillTheTaskInProgress() {
        let plan = steps("- [x] Parse hook events\n- [/] Draw the status pill\n- [ ] Ship it")
        let breakdown = [
            AgentTodo(id: "1", content: "Measure the capsule", status: .completed),
            AgentTodo(id: "2", content: "Add the shimmer band", status: .completed),
            AgentTodo(id: "3", content: "Wire up reduce motion", status: .completed),
            AgentTodo(id: "4", content: "Check dark mode", status: .inProgress)
        ]
        let progress = PlanProgress.make(steps: plan, todos: breakdown, lastEdit: nil)
        #expect(progress.segments[1] == .init(state: .inProgress, fill: 0.75))
        #expect(progress.label == .count(done: 1, total: 3))

        // A todo list that repeats the plan's tasks says nothing about the inside of one.
        let mirror = [
            AgentTodo(id: "1", content: "Parse the hook events", status: .completed),
            AgentTodo(id: "2", content: "Draw status pill", status: .inProgress),
            AgentTodo(id: "3", content: "Ship it", status: .pending)
        ]
        #expect(PlanProgress.make(steps: plan, todos: mirror, lastEdit: nil).segments[1].fill == 0.5)

        // Two tasks in progress: the todos cannot be pinned on one.
        let two = steps("- [/] Draw the status pill\n- [/] Ship it")
        #expect(PlanProgress.make(steps: two, todos: breakdown, lastEdit: nil).segments.map(\.fill) == [0.5, 0.5])
    }

    @Test func todoListsAndGuessesGetSegmentsToo() {
        let todos = [
            AgentTodo(id: "1", content: "a", status: .completed),
            AgentTodo(id: "2", content: "b", status: .inProgress),
            AgentTodo(id: "3", content: "c", status: .pending)
        ]
        let fromTodos = PlanProgress.make(steps: [], todos: todos, lastEdit: nil)
        #expect(fromTodos.segments.map(\.fill) == [1, 0.5, 0])
        #expect(fromTodos.fraction == 0.5)

        let guess = PlanProgress.make(steps: steps("1. Install\n2. Configure\n3. Ship"), todos: [], lastEdit: (12, "Claude"))
        #expect(guess.segments.map(\.state) == [.done, .inProgress, .open])
        #expect(guess.isEstimate)
        #expect(PlanProgress.empty.percentText == nil)
    }

    @Test func matcherNeedsRealOverlap() {
        let plan = steps("- [ ] Reload the file when it changes\n- [ ] Install the hook")
        #expect(StepMatcher.bestStep(for: ["Reloading files on change"], in: plan) == 0)
        #expect(StepMatcher.bestStep(for: ["Installing hooks"], in: plan) == 1)
        #expect(StepMatcher.bestStep(for: ["Write the README"], in: plan) == nil)
    }
}

@Suite("Plan files, inbox and installer")
struct PlumbingTests {
    @Test func planLikePaths() {
        #expect(PlanFileRule.isPlanLike(path: "/Users/me/.claude/plans/wobbly-lamport.md"))
        #expect(PlanFileRule.isPlanLike(path: "/repo/docs/plans/2026-11-07-x.md"))
        #expect(PlanFileRule.isPlanLike(path: "/repo/PLAN.md"))
        #expect(PlanFileRule.isPlanLike(path: "/repo/migration-plan.markdown"))
        #expect(!PlanFileRule.isPlanLike(path: "/repo/README.md"))
        #expect(!PlanFileRule.isPlanLike(path: "/repo/plans/notes.txt"))
    }

    @Test func activityTexts() {
        #expect(ActivityText.current(toolName: "Edit", input: .object(["file_path": .string("/a/b/Pill.swift")])) == "Editing Pill.swift")
        #expect(ActivityText.current(toolName: "Bash", input: .object(["command": .string("swift test\necho done")])) == "Running swift test")
        #expect(ActivityText.current(toolName: "mcp__github__create_issue", input: nil) == "Using github")
        #expect(ActivityText.current(toolName: "WebFetch", input: .object(["url": .string("https://www.swift.org/x")])) == "Reading swift.org")
        #expect(ActivityText.finished(toolName: "Read", input: .object(["file_path": .string("/a")])) == nil)
        let long = String(repeating: "x", count: 80)
        #expect(ActivityText.current(toolName: "Bash", input: .object(["command": .string(long)])).count == "Running ".count + ActivityText.maxLength)
    }

    @Test func inboxReadsInOrderAndDeletes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("inbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = #"{"session_id": "s1", "hook_event_name": "UserPromptSubmit"}"#
        let second = #"{"session_id": "s1", "hook_event_name": "Stop"}"#
        try Data(first.utf8).write(to: directory.appendingPathComponent("100-1.json"))
        Thread.sleep(forTimeInterval: 0.02)
        try Data(second.utf8).write(to: directory.appendingPathComponent("100-2.json"))
        try Data("partial".utf8).write(to: directory.appendingPathComponent(".3.tmp"))

        let events = EventInbox(directory: directory).drain()
        #expect(events.map(\.kind) == [.promptSubmitted, .stop])
        let left = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(left == [".3.tmp"])
    }

    @Test func inboxDropsOldEvents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("inbox-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{"session_id": "s1", "hook_event_name": "Stop"}"#.utf8).write(to: directory.appendingPathComponent("1-1.json"))
        #expect(EventInbox(directory: directory).drain(now: Date().addingTimeInterval(3 * 60 * 60)).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func installerKeepsOtherSettingsAndIsIdempotent() throws {
        let existing = Data(#"""
        {"model": "opus", "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "/x/block.sh"}]}]}}
        """#.utf8)
        let command = HookInstaller.command(scriptPath: "/Users/me/Library/Application Support/Parchment/claude-hook.sh")
        #expect(command == "'/Users/me/Library/Application Support/Parchment/claude-hook.sh'")

        let once = try HookInstaller.installing(into: existing, command: command)
        let twice = try HookInstaller.installing(into: once, command: command)
        #expect(once == twice)
        #expect(HookInstaller.isInstalled(in: once))

        let settings = try #require(try JSONSerialization.jsonObject(with: once) as? [String: Any])
        #expect(settings["model"] as? String == "opus")
        let hooks = try #require(settings["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == Set(HookInstaller.events.map(\.name)))
        let pre = try #require(hooks["PreToolUse"] as? [[String: Any]])
        #expect(pre.count == 2)
        #expect(pre[1]["matcher"] as? String == "*")
        #expect((hooks["Stop"] as? [[String: Any]])?.first?["matcher"] == nil)

        let removed = try HookInstaller.removing(from: once)
        #expect(!HookInstaller.isInstalled(in: removed))
        let after = try #require(try JSONSerialization.jsonObject(with: removed) as? [String: Any])
        #expect(Set((after["hooks"] as? [String: Any])?.keys ?? [:].keys) == ["PreToolUse"])
    }

    @Test func installerHandlesMissingAndBrokenFiles() throws {
        let fresh = try HookInstaller.installing(into: nil, command: "'/p/Parchment/claude-hook.sh'")
        #expect(HookInstaller.isInstalled(in: fresh))
        let removed = try HookInstaller.removing(from: fresh)
        #expect(String(decoding: removed, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "{\n\n}" ||
                String(decoding: removed, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "{}")
        #expect(throws: HookInstaller.Failure.unreadableSettings) {
            try HookInstaller.installing(into: Data("{ nope".utf8), command: "x")
        }
        #expect(!HookInstaller.isInstalled(in: Data("[]".utf8)))
    }

    @Test func scriptLooksRight() {
        #expect(HookInstaller.script.hasPrefix("#!/bin/sh\n"))
        #expect(HookInstaller.script.contains("open -g -b app.parchment.Parchment"))
        #expect(HookInstaller.script.contains(#"\.(md|markdown)"#))
    }

    @Test func instructionsAreAddedOnceAndRemovedCleanly() {
        let mine = "# My rules\n\nUse tabs.\n"
        let once = InstructionsInstaller.installing(into: mine)
        #expect(InstructionsInstaller.installing(into: once) == once)
        #expect(once.hasPrefix(mine))
        #expect(InstructionsInstaller.isInstalled(in: once))
        #expect(once.contains("- [!] Deploy (blocked: needs an API key)"))
        #expect(InstructionsInstaller.removing(from: once) == mine)

        #expect(InstructionsInstaller.installing(into: nil) == InstructionsInstaller.block)
        #expect(InstructionsInstaller.removing(from: InstructionsInstaller.block) == "")
        #expect(InstructionsInstaller.removing(from: mine) == mine)
    }
}

@Suite("What Claude says and the timeline")
struct InsightTests {
    private func hook(_ name: String, _ fields: String = "", at seconds: Double = 0) -> AgentEvent {
        let extra = fields.isEmpty ? "" : ", \(fields)"
        return event(#"{"session_id": "s1", "hook_event_name": "\#(name)"\#(extra)}"#, at: seconds)
    }

    @Test func decodesTheNewEvents() {
        let piece = hook("MessageDisplay", #""message_id": "m1", "index": 0, "final": false, "delta": "Here is the plan:\n""#)
        #expect(piece.kind == .message(delta: "Here is the plan:\n", isFinal: false))
        #expect(piece.messageID == "m1")
        let stop = hook("Stop", #""last_assistant_message": "All done.", "background_tasks": [{"id": "t1", "type": "shell", "status": "running", "description": "tail logs"}, {"id": "t2", "type": "shell", "status": "completed", "description": "old"}]"#)
        #expect(stop.lastMessage == "All done.")
        #expect(stop.backgroundTasks == ["tail logs"])
        #expect(hook("StopFailure", #""error": "rate_limit""#).kind == .stopFailed(error: "rate_limit"))
        #expect(hook("PermissionRequest", #""tool_name": "Bash", "tool_input": {"command": "rm -rf build"}"#).kind == .permissionRequested)
        #expect(hook("UserPromptSubmit", #""prompt": "Fix the pill""#).prompt == "Fix the pill")
    }

    @Test func narrationFollowsWhatClaudeWrites() {
        var session = AgentSession(id: "s1", date: start)
        session.apply(hook("UserPromptSubmit", #""prompt": "Fix the pill""#))
        #expect(session.activity == nil)
        #expect(session.prompt == "Fix the pill")
        session.apply(hook("MessageDisplay", #""message_id": "m1", "final": false, "delta": "The tests fail because of **X**. ""#, at: 1))
        session.apply(hook("MessageDisplay", #""message_id": "m1", "final": true, "delta": "I will fix `Pill.swift` next.""#, at: 2))
        #expect(session.narration == "I will fix Pill.swift next.")
        #expect(session.timeline.map(\.kind) == [.prompt, .said])
        #expect(session.timeline.last?.text == "The tests fail because of **X**. I will fix `Pill.swift` next.")
        // A new message starts a new line.
        session.apply(hook("MessageDisplay", #""message_id": "m2", "final": false, "delta": "Now the tests.""#, at: 3))
        #expect(session.timeline.count == 3)
        #expect(session.narration == "Now the tests.")

        let headline = SessionHeadline.make(session: session, planComplete: false, now: start.addingTimeInterval(4), staleAfter: 300)
        #expect(headline == SessionHeadline(title: "Now the tests."))
    }

    @Test func toolsGetDurationsAndClearWhenDone() {
        var session = AgentSession(id: "s1", date: start)
        session.apply(hook("UserPromptSubmit", #""prompt": "go""#))
        session.apply(hook("PreToolUse", #""tool_name": "Bash", "tool_use_id": "t1", "tool_input": {"command": "swift test"}"#, at: 10))
        #expect(session.activity == "Running swift test")
        #expect(session.activityStart == start.addingTimeInterval(10))
        #expect(session.hasRunningWork)
        // Silent for ten minutes, but a command is running: not stale.
        #expect(!session.isStale(at: start.addingTimeInterval(610), after: 300))
        let running = SessionHeadline.make(session: session, planComplete: false, now: start.addingTimeInterval(52), staleAfter: 300)
        #expect(running.title == "Running swift test")
        #expect(running.since == start.addingTimeInterval(10))

        session.apply(hook("PostToolUseFailure", #""tool_name": "Bash", "tool_use_id": "t1", "tool_input": {"command": "swift test"}, "error": "Exit code 1\n3 tests failed""#, at: 52))
        #expect(session.activity == nil)
        #expect(!session.hasRunningWork)
        let entry = session.timeline.last
        #expect(entry?.kind == .action(.failed))
        #expect(entry?.text == "Ran swift test")
        #expect(entry?.detail == "Exit code 1")
        #expect(entry?.duration == 42)
        #expect(session.turn.commands == 1)
        #expect(session.turn.failures == 1)

        session.apply(hook("PostToolUse", #""tool_name": "Edit", "tool_input": {"file_path": "/repo/Pill.swift"}"#, at: 60))
        session.apply(hook("PostToolUse", #""tool_name": "Edit", "tool_input": {"file_path": "/repo/Pill.swift"}"#, at: 61))
        #expect(session.turn.editedFiles == ["Pill.swift"])
        #expect(session.turn.text == "1 file edited · 1 command · 1 failed")
        #expect(session.isStale(at: start.addingTimeInterval(700), after: 300))
    }

    @Test func parallelToolsFallBackToTheOneStillRunning() {
        var session = AgentSession(id: "s1", date: start)
        session.apply(hook("PreToolUse", #""tool_name": "Read", "tool_use_id": "a", "tool_input": {"file_path": "/r/A.swift"}"#))
        session.apply(hook("PreToolUse", #""tool_name": "Read", "tool_use_id": "b", "tool_input": {"file_path": "/r/B.swift"}"#, at: 1))
        #expect(session.activity == "Reading B.swift")
        session.apply(hook("PostToolUse", #""tool_name": "Read", "tool_use_id": "b", "tool_input": {"file_path": "/r/B.swift"}"#, at: 2))
        #expect(session.activity == "Reading A.swift")
        #expect(session.timeline.map(\.text) == ["Reading A.swift", "Read B.swift"])
    }

    @Test func waitingSaysWhatFor() {
        var session = AgentSession(id: "s1", date: start)
        func title() -> String {
            SessionHeadline.make(session: session, planComplete: false, now: start.addingTimeInterval(1), staleAfter: 300).title
        }
        session.apply(hook("PreToolUse", #""tool_name": "Bash", "tool_input": {"command": "rm -rf build"}"#))
        session.apply(hook("PermissionRequest", #""tool_name": "Bash", "tool_input": {"command": "rm -rf build"}"#))
        #expect(session.status == .waiting(.permission))
        #expect(title() == "Needs your permission to run rm -rf build")
        // A helper's tool does not answer Claude's permission request.
        session.apply(hook("PreToolUse", #""tool_name": "Grep", "agent_id": "a1", "agent_type": "Explore""#))
        #expect(session.status == .waiting(.permission))
        session.apply(hook("PostToolUse", #""tool_name": "Bash", "tool_input": {"command": "rm -rf build"}"#))
        #expect(session.status == .working)
        #expect(session.permissionRequest == nil)

        session.apply(hook("PreToolUse", #""tool_name": "AskUserQuestion", "tool_input": {"questions": [{"question": "Which color?"}]}"#))
        #expect(session.status == .waiting(.question))
        #expect(title() == "Asks you: Which color?")
        session.apply(hook("PostToolUse", #""tool_name": "AskUserQuestion", "tool_input": {"questions": [{"question": "Which color?"}]}"#))

        session.apply(hook("PreToolUse", #""tool_name": "ExitPlanMode""#))
        session.apply(hook("PermissionRequest", #""tool_name": "ExitPlanMode""#))
        #expect(title() == "Waiting for you to approve the plan")
        // The late permission notification keeps the clearer reason.
        session.apply(hook("Notification", #""notification_type": "permission_prompt""#))
        #expect(session.status == .waiting(.planApproval))
    }

    @Test func stoppingKeepsWhatClaudeConcluded() {
        var session = AgentSession(id: "s1", date: start)
        session.apply(hook("UserPromptSubmit", #""prompt": "go""#))
        session.apply(hook("Stop", ###""last_assistant_message": "## Done\n\nI fixed the pill and the tests pass.\n\n```swift\nlet x = 1\n```\n\nShould I also update the README?""###, at: 90))
        #expect(session.status == .waiting(.finishedTurn))
        var headline = SessionHeadline.make(session: session, planComplete: false, now: start.addingTimeInterval(91), staleAfter: 300)
        #expect(headline == SessionHeadline(title: "Waiting for you", detail: "Should I also update the README?"))
        #expect(session.timeline.last?.kind == .finished)
        #expect(session.timeline.last?.duration == 90)

        session.apply(hook("UserPromptSubmit", #""prompt": "yes""#, at: 100))
        #expect(session.lastMessage == nil)
        session.apply(hook("Stop", #""last_assistant_message": "Updated the README. It now covers the timeline.", "background_tasks": [{"type": "shell", "status": "running", "description": "Watch the build"}]"#, at: 120))
        #expect(session.status == .waiting(.background))
        headline = SessionHeadline.make(session: session, planComplete: false, now: start.addingTimeInterval(121), staleAfter: 300)
        #expect(headline == SessionHeadline(title: "Waiting on 1 background task", detail: "Watch the build"))

        session.apply(hook("UserPromptSubmit", #""prompt": "more""#, at: 130))
        session.apply(hook("StopFailure", #""error": "rate_limit""#, at: 131))
        #expect(SessionHeadline.make(session: session, planComplete: false, now: start.addingTimeInterval(132), staleAfter: 300).title == "Stopped: Rate limit reached")
    }

    @Test func helpersCarryTheirTaskAndReport() {
        var session = AgentSession(id: "s1", date: start)
        session.apply(hook("UserPromptSubmit", #""prompt": "go""#))
        session.apply(hook("PreToolUse", #""tool_name": "Agent", "tool_input": {"description": "Find the hook installer", "subagent_type": "Explore", "prompt": "..."}"#, at: 1))
        session.apply(hook("SubagentStart", #""agent_id": "a1", "agent_type": "Explore""#, at: 2))
        #expect(session.helpers.first?.task == "Find the hook installer")
        #expect(session.turn.helpers == 1)
        session.apply(hook("PreToolUse", #""tool_name": "Grep", "agent_id": "a1", "agent_type": "Explore", "tool_input": {"pattern": "HookInstaller"}"#, at: 3))
        // Claude's own "starting a helper" call is still open, so the pill names it.
        #expect(session.activity == "Starting a helper: Find the hook installer")
        #expect(session.helpers.first?.activity == "Searching for \u{201C}HookInstaller\u{201D}")
        // An agent Claude Code runs for itself stops without having started: ignored.
        session.apply(hook("SubagentStop", #""agent_id": "zz", "agent_type": """#, at: 4))
        #expect(session.helpers.count == 1)
        session.apply(hook("SubagentStop", #""agent_id": "a1", "agent_type": "Explore", "last_assistant_message": "It lives in HookInstaller.swift. Nothing else touches settings.""#, at: 32))
        #expect(session.helpers.isEmpty)
        let finished = session.timeline.last
        #expect(finished?.kind == .helperFinished)
        #expect(finished?.text == "Explore finished")
        #expect(finished?.detail == "It lives in HookInstaller.swift.")
        #expect(finished?.duration == 30)
        #expect(session.timeline.map(\.text).contains("Explore started: Find the hook installer"))
    }

    @Test func summariesReadAsPlainSentences() {
        #expect(MessageSummary.latest("First thing. Then `swift test` in **bold**") == "Then swift test in bold")
        #expect(MessageSummary.latest("- [x] Read [the docs](https://x.y/z) for snake_case") == "Read the docs for snake_case")
        #expect(MessageSummary.conclusion("Edited Pill.swift and v1.2 notes. More below.\n\n| a | b |\n|---|---|") == "Edited Pill.swift and v1.2 notes.")
        #expect(MessageSummary.conclusion("```\ncode only\n```") == nil)
        #expect(MessageSummary.latest("   \n") == nil)
        #expect(ElapsedText.short(42) == "42s")
        #expect(ElapsedText.short(185) == "3m 05s")
        #expect(ElapsedText.short(840) == "14 min")
        #expect(ElapsedText.short(3_900) == "1h 05m")
    }

    @Test func timelineIsCappedAndOlderInstallsAreNoticed() throws {
        var session = AgentSession(id: "s1", date: start)
        for index in 0..<(AgentSession.maxTimelineEntries + 20) {
            session.apply(hook("PostToolUse", #""tool_name": "Read", "tool_input": {"file_path": "/r/\#(index).swift"}"#))
        }
        #expect(session.timeline.count == AgentSession.maxTimelineEntries)
        #expect(session.timeline.first?.text == "Read 20.swift")

        let current = try HookInstaller.installing(into: nil, command: "'/p/Parchment/claude-hook.sh'")
        #expect(HookInstaller.isCurrent(in: current))
        var settings = try #require(try JSONSerialization.jsonObject(with: current) as? [String: Any])
        var hooks = try #require(settings["hooks"] as? [String: Any])
        hooks["MessageDisplay"] = nil
        settings["hooks"] = hooks
        let older = try JSONSerialization.data(withJSONObject: settings)
        #expect(HookInstaller.isInstalled(in: older))
        #expect(!HookInstaller.isCurrent(in: older))
    }
}
