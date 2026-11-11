import Foundation
import ParchmentCore

/// How far through a plan Claude is, from whatever the plan offers.
public struct PlanProgress: Sendable, Equatable {
    public enum Label: Sendable, Equatable {
        /// "6 of 9": counted from checkboxes or Claude's todo list.
        case count(done: Int, total: Int)
        /// "Step 3 of 7": a guess from where Claude is editing.
        case step(current: Int, total: Int)
        case none
    }

    /// A step being worked on, and by whom ("Claude" or a helper's type).
    public struct CurrentStep: Sendable, Equatable {
        public var index: Int
        public var owner: String?

        public init(index: Int, owner: String?) {
            self.index = index
            self.owner = owner
        }
    }

    /// One piece of the progress bar: a top-level task, a todo, or a step.
    public struct Segment: Sendable, Equatable {
        public enum State: Sendable, Equatable {
            case open
            case inProgress
            case blocked
            case done
        }

        public var state: State
        /// 0...1: how much of this piece is done. A task with sub-steps fills as they are
        /// ticked; a task in progress fills with Claude's todo list, or to half.
        public var fill: Double

        public init(state: State, fill: Double) {
            self.state = state
            self.fill = fill
        }
    }

    public var label: Label
    /// 0...1: the average fill of the segments.
    public var fraction: Double
    public var currentSteps: [CurrentStep]
    /// The progress bar, piece by piece, in plan order.
    public var segments: [Segment]
    /// True when done-ness is a guess from where Claude is editing.
    public var isEstimate: Bool

    public init(label: Label, fraction: Double, currentSteps: [CurrentStep], segments: [Segment] = [], isEstimate: Bool = false) {
        self.label = label
        self.fraction = fraction
        self.currentSteps = currentSteps
        self.segments = segments
        self.isEstimate = isEstimate
    }

    /// A started task with nothing else to go by counts as half done, like its half-filled circle.
    static let startedFill = 0.5
    /// A started task filled from the todo list stays between these until its box is ticked.
    static let todoFillRange = 0.1...0.9

    /// "64%"
    public var percentText: String? {
        segments.isEmpty ? nil : "\(Int((fraction * 100).rounded()))%"
    }

    public static let empty = PlanProgress(label: .none, fraction: 0, currentSteps: [])

    public var isComplete: Bool {
        if case .count(let done, let total) = label { return total > 0 && done == total }
        return false
    }

    /// - Parameters:
    ///   - steps: the plan's steps (`PlanSteps.steps(in:text:)`).
    ///   - todos: Claude's todo list for the session.
    ///   - lastEdit: offset of Claude's last change in this file, and who made it.
    public static func make(steps: [PlanStep], todos: [AgentTodo], lastEdit: (location: Int, owner: String)?) -> PlanProgress {
        let matched = matchedInProgressTodos(todos, steps: steps)

        // 1. Checkboxes in the file. Steps marked `[/]` are current; otherwise Claude's
        // in-progress todos, then the first open step. Blocked steps are never guessed.
        if steps.contains(where: \.isTask) {
            let done = steps.count { $0.isChecked }
            let owners = Dictionary(matched.map { ($0.index, $0.owner) }, uniquingKeysWith: { first, _ in first })
            var current = steps.indices
                .filter { steps[$0].taskState == .inProgress }
                .map { CurrentStep(index: $0, owner: owners[$0] ?? nil) }
            if current.isEmpty {
                current = matched.filter { steps[$0.index].taskState == .open }
            }
            if current.isEmpty, let first = steps.firstIndex(where: { $0.taskState == .open }) {
                current = [CurrentStep(index: first, owner: nil)]
            }
            let segments = taskSegments(steps, todos: todos)
            return PlanProgress(
                label: .count(done: done, total: steps.count),
                fraction: done == steps.count ? 1 : average(segments),
                currentSteps: done == steps.count ? [] : current,
                segments: segments
            )
        }

        // 2. Claude's todo list.
        if !todos.isEmpty {
            let done = todos.count { $0.status == .completed }
            var current = matched
            if current.isEmpty, let lastEdit, let index = PlanSteps.index(of: lastEdit.location, in: steps),
               done < todos.count {
                current = [CurrentStep(index: index, owner: lastEdit.owner)]
            }
            let segments = todos.map { todo in
                switch todo.status {
                case .completed: Segment(state: .done, fill: 1)
                case .inProgress: Segment(state: .inProgress, fill: startedFill)
                case .pending: Segment(state: .open, fill: 0)
                }
            }
            return PlanProgress(
                label: .count(done: done, total: todos.count),
                fraction: average(segments),
                currentSteps: current,
                segments: segments
            )
        }

        // 3. The plan's structure.
        guard !steps.isEmpty, let lastEdit, let index = PlanSteps.index(of: lastEdit.location, in: steps) else {
            return .empty
        }
        let segments = steps.indices.map { step in
            step < index ? Segment(state: .done, fill: 1)
                : step == index ? Segment(state: .inProgress, fill: startedFill) : Segment(state: .open, fill: 0)
        }
        return PlanProgress(
            label: .step(current: index + 1, total: steps.count),
            fraction: average(segments),
            currentSteps: [CurrentStep(index: index, owner: lastEdit.owner)],
            segments: segments,
            isEstimate: true
        )
    }

    // MARK: Segments

    private static func average(_ segments: [Segment]) -> Double {
        segments.isEmpty ? 0 : segments.reduce(0) { $0 + $1.fill } / Double(segments.count)
    }

    /// One segment per top-level task. A task indented under another is its sub-step and fills
    /// part of its parent's segment.
    private static func taskSegments(_ steps: [PlanStep], todos: [AgentTodo]) -> [Segment] {
        // Each task's parent: the nearest task above it that is indented less.
        var children = [[Int]](repeating: [], count: steps.count)
        var roots: [Int] = []
        var stack: [Int] = []
        for index in steps.indices {
            while let last = stack.last, steps[last].indent >= steps[index].indent { stack.removeLast() }
            if let parent = stack.last { children[parent].append(index) } else { roots.append(index) }
            stack.append(index)
        }

        let started = todoFill(todos, steps: steps, children: children)
        func segment(_ index: Int) -> Segment {
            let state = steps[index].taskState ?? .open
            if state == .done { return Segment(state: .done, fill: 1) }
            let parts = children[index].map(segment)
            guard !parts.isEmpty else {
                switch state {
                case .inProgress: return Segment(state: .inProgress, fill: started)
                case .blocked: return Segment(state: .blocked, fill: 0)
                default: return Segment(state: .open, fill: 0)
                }
            }
            // An unticked parent is never full, even with every sub-step ticked.
            let fill = min(average(parts), todoFillRange.upperBound)
            if state == .blocked { return Segment(state: .blocked, fill: fill) }
            if state == .inProgress || parts.contains(where: { $0.state == .inProgress }) || fill > 0 {
                return Segment(state: .inProgress, fill: fill)
            }
            return Segment(state: parts.contains { $0.state == .blocked } ? .blocked : .open, fill: fill)
        }
        return roots.map(segment)
    }

    /// How full a started task is. When exactly one task without sub-steps is in progress and
    /// Claude's todo list is its breakdown, the share of todos done; otherwise half.
    ///
    /// Claude's todo list often just repeats the plan's tasks. Then it says nothing about the
    /// inside of one task, so it is only used when most todos match no plan task.
    private static func todoFill(_ todos: [AgentTodo], steps: [PlanStep], children: [[Int]]) -> Double {
        let startedLeaves = steps.indices.count { steps[$0].taskState == .inProgress && children[$0].isEmpty }
        guard startedLeaves == 1, todos.count >= 2 else { return startedFill }
        let mirrored = todos.count { StepMatcher.bestStep(for: [$0.content], in: steps) != nil }
        guard mirrored * 2 < todos.count else { return startedFill }
        let done = Double(todos.count { $0.status == .completed }) / Double(todos.count)
        return min(max(done, todoFillRange.lowerBound), todoFillRange.upperBound)
    }

    private static func matchedInProgressTodos(_ todos: [AgentTodo], steps: [PlanStep]) -> [CurrentStep] {
        var seen = Set<Int>()
        var result: [CurrentStep] = []
        for todo in todos where todo.status == .inProgress {
            let texts = [todo.content] + (todo.activeForm.map { [$0] } ?? [])
            guard let index = StepMatcher.bestStep(for: texts, in: steps), seen.insert(index).inserted else { continue }
            result.append(CurrentStep(index: index, owner: todo.owner))
        }
        return result.sorted { $0.index < $1.index }
    }
}
