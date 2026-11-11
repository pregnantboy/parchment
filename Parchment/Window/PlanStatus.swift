import Foundation
import ParchmentAgent
import ParchmentCore

/// What the window shows about the Claude session following its file.
struct PlanStatus {
    let session: AgentSession
    let progress: PlanProgress

    /// Without updates for this long, a working session is shown as possibly stuck.
    static let staleAfter: TimeInterval = 5 * 60

    init(session: AgentSession, steps: [PlanStep], lastEdit: Int?) {
        self.session = session
        let owner = session.lastEdit?.owner ?? AgentSession.mainAgentName
        progress = PlanProgress.make(steps: steps, todos: session.todos, lastEdit: lastEdit.map { ($0, owner) })
    }

    /// The window stays read-only until the session ends.
    var isReadOnly: Bool { session.status != .ended }

    var isWorking: Bool { session.status == .working }

    /// A working session that went quiet although nothing is running. During a long command
    /// or while helpers work, silence is expected and the pill shows the elapsed time instead.
    func isStale(at date: Date) -> Bool {
        session.isStale(at: date, after: Self.staleAfter)
    }

    /// "Claude", "Claude + 1 helper", "Claude + 3 helpers".
    var who: String {
        switch session.helpers.count {
        case 0: AgentSession.mainAgentName
        case 1: "\(AgentSession.mainAgentName) + 1 helper"
        case let count: "\(AgentSession.mainAgentName) + \(count) helpers"
        }
    }

    /// The pill's wording: what Claude does or waits for, and what it says in its own words.
    func headline(at date: Date) -> SessionHeadline {
        SessionHeadline.make(session: session, planComplete: progress.isComplete, now: date, staleAfter: Self.staleAfter)
    }

    /// The folder Claude Code runs in, like "parchment".
    var projectName: String? {
        session.cwd.map { ($0 as NSString).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// "6 of 9", "Step 3 of 7", or nothing.
    var progressText: String? {
        switch progress.label {
        case .count(let done, let total): "\(done) of \(total)"
        case .step(let current, let total): "Step \(current) of \(total)"
        case .none: nil
        }
    }

    /// For the progress line. Slightly above zero while working, so the glint has room.
    var lineFraction: Double {
        isWorking ? max(progress.fraction, 0.02) : progress.fraction
    }
}
