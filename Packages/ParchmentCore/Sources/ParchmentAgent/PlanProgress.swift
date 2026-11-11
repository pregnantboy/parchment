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

    public var label: Label
    /// 0...1, for the progress line.
    public var fraction: Double
    public var currentSteps: [CurrentStep]

    public init(label: Label, fraction: Double, currentSteps: [CurrentStep]) {
        self.label = label
        self.fraction = fraction
        self.currentSteps = currentSteps
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
            return PlanProgress(
                label: .count(done: done, total: steps.count),
                fraction: Double(done) / Double(steps.count),
                currentSteps: done == steps.count ? [] : current
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
            return PlanProgress(
                label: .count(done: done, total: todos.count),
                fraction: Double(done) / Double(todos.count),
                currentSteps: current
            )
        }

        // 3. The plan's structure.
        guard !steps.isEmpty, let lastEdit, let index = PlanSteps.index(of: lastEdit.location, in: steps) else {
            return .empty
        }
        return PlanProgress(
            label: .step(current: index + 1, total: steps.count),
            fraction: Double(index) / Double(steps.count),
            currentSteps: [CurrentStep(index: index, owner: lastEdit.owner)]
        )
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
