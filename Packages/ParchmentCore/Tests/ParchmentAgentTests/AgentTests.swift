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
}
