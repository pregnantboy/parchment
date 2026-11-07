import Foundation

/// One item of Claude's todo list.
public struct AgentTodo: Sendable, Hashable, Identifiable {
    public enum Status: String, Sendable, Hashable {
        case pending
        case inProgress = "in_progress"
        case completed
    }

    public var id: String
    public var content: String
    /// The "-ing" form Claude shows while working on it, like "Running the tests".
    public var activeForm: String?
    public var status: Status
    /// Who works on it: "Claude" or a helper's type, like "Explore".
    public var owner: String?

    public init(id: String, content: String, activeForm: String? = nil, status: Status, owner: String? = nil) {
        self.id = id
        self.content = content
        self.activeForm = activeForm
        self.status = status
        self.owner = owner
    }
}

/// Keeps Claude's todo list in step with the `TodoWrite` tool (which always sends the whole list)
/// and the `TaskCreate` / `TaskUpdate` tools (which change one item at a time).
public struct TodoList: Sendable, Equatable {
    public private(set) var items: [AgentTodo] = []
    private var nextLocalID = 1

    public init(items: [AgentTodo] = []) {
        self.items = items
    }

    /// Applies a finished tool call. Returns true when the list changed.
    @discardableResult
    public mutating func apply(toolName: String, input: JSONValue?, response: JSONValue?, agentName: String) -> Bool {
        let before = items
        switch toolName {
        case "TodoWrite":
            replaceAll(with: input?["todos"]?.array ?? [], agentName: agentName)
        case "TaskCreate":
            create(input: input, response: response)
        case "TaskUpdate":
            update(input: input, agentName: agentName)
        default:
            return false
        }
        return items != before
    }

    private mutating func replaceAll(with todos: [JSONValue], agentName: String) {
        let previousOwners = Dictionary(items.map { ($0.content, $0.owner) }, uniquingKeysWith: { first, _ in first })
        items = todos.enumerated().compactMap { index, todo -> AgentTodo? in
            guard let content = todo["content"]?.string ?? todo["subject"]?.string else { return nil }
            let status = AgentTodo.Status(rawValue: todo["status"]?.string ?? "") ?? .pending
            var owner = previousOwners[content] ?? nil
            if status == .inProgress, owner == nil {
                owner = agentName
            }
            return AgentTodo(
                id: todo["id"]?.identifier ?? String(index + 1),
                content: content,
                activeForm: todo["activeForm"]?.string,
                status: status,
                owner: owner
            )
        }
    }

    private mutating func create(input: JSONValue?, response: JSONValue?) {
        guard let subject = input?["subject"]?.string ?? input?["content"]?.string else { return }
        let id = Self.createdID(in: response) ?? "local-\(nextLocalID)"
        nextLocalID += 1
        items.removeAll { $0.id == id }
        items.append(AgentTodo(id: id, content: subject, activeForm: input?["activeForm"]?.string, status: .pending))
    }

    private mutating func update(input: JSONValue?, agentName: String) {
        guard let id = input?["taskId"]?.identifier ?? input?["id"]?.identifier,
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        if let raw = input?["status"]?.string {
            if raw == "deleted" {
                items.remove(at: index)
                return
            }
            if let status = AgentTodo.Status(rawValue: raw) {
                items[index].status = status
                if status == .inProgress, items[index].owner == nil {
                    items[index].owner = agentName
                }
            }
        }
        if let subject = input?["subject"]?.string { items[index].content = subject }
        if let activeForm = input?["activeForm"]?.string { items[index].activeForm = activeForm }
        if let owner = input?["owner"]?.string, !owner.isEmpty { items[index].owner = owner }
    }

    /// The new task's id. The response shape is not documented, so look in the likely places,
    /// then for "#12" or "Task 12" in any text.
    static func createdID(in response: JSONValue?) -> String? {
        guard let response else { return nil }
        for candidate in [response["task"]?["id"], response["id"], response["taskId"]] {
            if let id = candidate?.identifier { return id }
        }
        for text in response.allStrings {
            if let id = firstNumber(after: "#", in: text) ?? firstNumber(after: "Task ", in: text) {
                return id
            }
        }
        return nil
    }

    private static func firstNumber(after marker: String, in text: String) -> String? {
        guard let range = text.range(of: marker) else { return nil }
        let digits = text[range.upperBound...].prefix { $0.isASCII && $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }
}
