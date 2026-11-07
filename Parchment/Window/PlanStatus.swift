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

    func isStale(at date: Date) -> Bool {
        isWorking && date.timeIntervalSince(session.lastEventDate) > Self.staleAfter
    }

    /// "Claude", "Claude + 1 helper", "Claude + 3 helpers".
    var who: String {
        switch session.helpers.count {
        case 0: AgentSession.mainAgentName
        case 1: "\(AgentSession.mainAgentName) + 1 helper"
        case let count: "\(AgentSession.mainAgentName) + \(count) helpers"
        }
    }

    func headline(at date: Date) -> String {
        if isStale(at: date) {
            let minutes = Int(date.timeIntervalSince(session.lastEventDate) / 60)
            return "Last update \(minutes) min ago"
        }
        switch session.status {
        case .working:
            return session.activity ?? session.helpers.lazy.compactMap(\.activity).first ?? "Working"
        case .waiting(.permission):
            return "Needs your permission"
        case .waiting(.idle):
            return "Waiting for you"
        case .waiting(.finishedTurn):
            return progress.isComplete ? "Done" : "Waiting for you"
        case .ended:
            return progress.isComplete ? "Done" : "Session ended"
        }
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
