/// The state of a task item, from the character inside its box.
///
/// `[ ]` and `[x]` are standard Markdown. `[/]` (in progress) and `[!]` (blocked) are a common
/// extension; other apps such as GitHub show them as plain text.
public enum TaskState: Int, Hashable, Sendable, CaseIterable {
    case open
    case inProgress
    case blocked
    case done

    /// The state for the character between the brackets, or nil if it is not a task box.
    public init?(mark: UInt16) {
        switch mark {
        case Unit.space: self = .open
        case Unit.slash: self = .inProgress
        case Unit.exclamation: self = .blocked
        case Unit.lowerX, Unit.upperX: self = .done
        default: return nil
        }
    }

    /// The character Parchment writes between the brackets.
    public var mark: String {
        switch self {
        case .open: " "
        case .inProgress: "/"
        case .blocked: "!"
        case .done: "x"
        }
    }

    public var isDone: Bool { self == .done }
}
