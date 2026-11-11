import Foundation

/// The status pill's wording for a session: one main line, and a second line when there is
/// more to say.
public struct SessionHeadline: Sendable, Equatable {
    /// "Running the tests", "Waiting for you", "Needs your permission to run swift test".
    public var title: String
    /// Claude's own words: the sentence it is writing, or what its last message came down to.
    public var detail: String?
    /// When the thing in `title` started, for showing how long it has been going.
    public var since: Date?

    public init(title: String, detail: String? = nil, since: Date? = nil) {
        self.title = title
        self.detail = detail
        self.since = since
    }

    /// - Parameters:
    ///   - planComplete: every task of the followed plan is done.
    ///   - staleAfter: a working session that sent nothing for this long, with nothing running,
    ///     is shown as possibly stuck.
    public static func make(session: AgentSession, planComplete: Bool, now: Date, staleAfter: TimeInterval) -> SessionHeadline {
        if session.isStale(at: now, after: staleAfter) {
            let minutes = Int(now.timeIntervalSince(session.lastEventDate) / 60)
            return SessionHeadline(title: "Last update \(minutes) min ago", detail: session.narration)
        }
        switch session.status {
        case .working:
            if let activity = session.activity {
                return SessionHeadline(title: activity, detail: session.narration, since: session.activityStart)
            }
            // Claude itself is between tool calls: say what a helper does, else what Claude says.
            if let helper = session.helpers.first(where: { $0.activity != nil }), let activity = helper.activity {
                return SessionHeadline(title: "\(helper.name): \(activity)", detail: session.narration)
            }
            if let helper = session.helpers.first {
                let task = helper.task.map { ": \($0)" } ?? ""
                return SessionHeadline(title: "\(helper.name) is working\(task)", detail: session.narration, since: helper.startDate)
            }
            return SessionHeadline(title: session.narration ?? "Thinking")
        case .waiting(.permission):
            let request = session.permissionRequest.map { " to \($0)" } ?? ""
            return SessionHeadline(title: "Needs your permission\(request)")
        case .waiting(.question):
            return SessionHeadline(title: session.question.map { "Asks you: \($0)" } ?? "Asks you a question")
        case .waiting(.planApproval):
            return SessionHeadline(title: "Waiting for you to approve the plan")
        case .waiting(.background):
            let count = session.backgroundTasks.count
            return SessionHeadline(
                title: count == 1 ? "Waiting on 1 background task" : "Waiting on \(count) background tasks",
                detail: session.backgroundTasks.first
            )
        case .waiting(.failed):
            return SessionHeadline(title: "Stopped: \(session.failure ?? "an error")")
        case .waiting(.idle):
            return SessionHeadline(title: "Waiting for you", detail: conclusion(session))
        case .waiting(.finishedTurn):
            return SessionHeadline(title: planComplete ? "Done" : "Waiting for you", detail: conclusion(session))
        case .ended:
            return SessionHeadline(title: planComplete ? "Done" : "Session ended", detail: conclusion(session))
        }
    }

    private static func conclusion(_ session: AgentSession) -> String? {
        session.lastMessage.flatMap(MessageSummary.conclusion)
    }
}
