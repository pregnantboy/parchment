/// One step of a plan, found from the document's structure.
public struct PlanStep: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case task(TaskState)
        case numbered
        case heading(level: Int)
    }

    /// The step line's start offset, unique within one snapshot of the document.
    public var id: Int { range.location }
    public var kind: Kind
    public var title: String
    /// The step's own line.
    public var range: MarkdownRange
    /// From the step's line to the start of the next step (or the end of the document).
    /// Edits inside it count as work on this step.
    public var section: MarkdownRange

    public init(kind: Kind, title: String, range: MarkdownRange, section: MarkdownRange) {
        self.kind = kind
        self.title = title
        self.range = range
        self.section = section
    }

    public var isTask: Bool {
        if case .task = kind { return true }
        return false
    }

    public var taskState: TaskState? {
        if case .task(let state) = kind { return state }
        return nil
    }

    public var isChecked: Bool { taskState == .done }
}

public enum PlanSteps {
    /// The steps of any plan, whatever its format:
    /// 1. every task (`- [ ]`, `- [/]`, `- [!]`, `- [x]`) if there is at least one;
    /// 2. else top-level numbered list items, if there are at least two;
    /// 3. else headings named like steps ("Phase 2", "Step 3", "Milestone", "1. Setup");
    /// 4. else level 2 headings, or level 3 headings when there are no level 2 ones.
    public static func steps(in lines: [MarkdownLine], text: MarkdownText) -> [PlanStep] {
        let tasks = lines.filter {
            if case .task = $0.kind { return true }
            return false
        }
        if !tasks.isEmpty {
            return make(tasks, text: text)
        }

        let numbered = lines.filter {
            guard case .listItem(isOrdered: true) = $0.kind else { return false }
            return indentation(of: $0, in: text) == 0
        }
        if numbered.count >= 2 {
            return make(numbered, text: text)
        }

        let headings = lines.filter {
            if case .heading = $0.kind { return true }
            return false
        }
        let named = headings.filter { looksLikeStep(OutlineHeading.cleanTitle(text.string(in: $0.contentRange))) }
        if !named.isEmpty {
            return make(named, text: text)
        }
        for level in [2, 3] {
            let matching = headings.filter { $0.kind == .heading(level: level) }
            if !matching.isEmpty {
                return make(matching, text: text)
            }
        }
        return []
    }

    /// The index of the step whose section contains `location`.
    public static func index(of location: Int, in steps: [PlanStep]) -> Int? {
        steps.lastIndex { $0.section.location <= location && location <= $0.section.upperBound }
    }

    private static func make(_ lines: [MarkdownLine], text: MarkdownText) -> [PlanStep] {
        lines.enumerated().map { index, line in
            let end = index + 1 < lines.count ? lines[index + 1].range.location : text.length
            let kind: PlanStep.Kind = switch line.kind {
            case .task(let state): .task(state)
            case .heading(let level): .heading(level: level)
            default: .numbered
            }
            return PlanStep(
                kind: kind,
                title: OutlineHeading.cleanTitle(text.string(in: line.contentRange)),
                range: line.range,
                section: MarkdownRange(location: line.range.location, length: max(0, end - line.range.location))
            )
        }
    }

    private static func indentation(of line: MarkdownLine, in text: MarkdownText) -> Int {
        var count = 0
        var index = line.range.location
        while index < line.range.upperBound, text[index] == Unit.space || text[index] == Unit.tab {
            count += 1
            index += 1
        }
        return count
    }

    private static let stepWords: Set<String> = ["phase", "step", "stage", "milestone", "part", "task", "day", "week", "sprint"]

    static func looksLikeStep(_ title: String) -> Bool {
        let lowered = title.lowercased()
        if let first = lowered.split(whereSeparator: { $0 == " " || $0 == ":" || $0 == "." }).first,
           stepWords.contains(String(first)) {
            return true
        }
        // "1. Setup", "2) Build", "3 - Ship"
        var digits = 0
        for character in lowered {
            if character.isNumber { digits += 1 } else { break }
        }
        // Up to two digits, so a year like "2026 roadmap" is not a step.
        guard (1...2).contains(digits) else { return false }
        let rest = lowered.dropFirst(digits)
        return rest.first == "." || rest.first == ")" || rest.first == " "
    }
}
