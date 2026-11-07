import Testing
@testable import ParchmentCore

@Suite("Plan steps and text changes")
struct PlanTests {
    private func steps(_ string: String) -> [PlanStep] {
        let text = MarkdownText(string)
        return PlanSteps.steps(in: MarkdownParser.lines(in: text), text: text)
    }

    @Test func tasksWinOverEverythingElse() {
        let found = steps("# Plan\n## Phase 1\n- [x] Parse **events**\n  - [ ] Nested task\n1. Not a step\n2. Nor this")
        #expect(found.map(\.title) == ["Parse events", "Nested task"])
        #expect(found.map(\.isChecked) == [true, false])
    }

    @Test func topLevelNumberedItemsWithoutTasks() {
        let found = steps("Intro\n1. Install\n   1. nested\n2. Configure\n3. Ship")
        #expect(found.map(\.title) == ["Install", "Configure", "Ship"])
        #expect(found.allSatisfy { $0.kind == .numbered })
    }

    @Test func oneNumberedItemIsNotAPlan() {
        #expect(steps("1. Only one\n\nSome text").isEmpty)
    }

    @Test func headingsNamedLikeStepsBeatOtherHeadings() {
        let found = steps("# Title\n## Context\n## Phase 1: Setup\n## Phase 2: Build\n## Notes")
        #expect(found.map(\.title) == ["Phase 1: Setup", "Phase 2: Build"])
    }

    @Test func numberedHeadingsCountAsSteps() {
        #expect(PlanSteps.looksLikeStep("1. Setup"))
        #expect(PlanSteps.looksLikeStep("2) Build"))
        #expect(PlanSteps.looksLikeStep("Milestone: beta"))
        #expect(!PlanSteps.looksLikeStep("2026 roadmap"))
        #expect(!PlanSteps.looksLikeStep("Stepping back"))
    }

    @Test func fallsBackToLevelTwoHeadings() {
        let found = steps("# Title\n## Context\n### Detail\n## Approach")
        #expect(found.map(\.title) == ["Context", "Approach"])
    }

    @Test func sectionsRunToTheNextStep() {
        let string = "## Phase 1\ntext\n## Phase 2\nmore"
        let found = steps(string)
        #expect(found.count == 2)
        #expect(found[0].section == MarkdownRange(location: 0, length: 16))
        #expect(found[1].section.upperBound == string.utf16.count)
        #expect(PlanSteps.index(of: 12, in: found) == 0)
        #expect(PlanSteps.index(of: 20, in: found) == 1)
    }

    @Test func noChangeForEqualTexts() {
        #expect(TextChange.between(old: MarkdownText("abc"), new: MarkdownText("abc")) == nil)
    }

    @Test func changeLeavesOutCommonEnds() {
        let change = TextChange.between(old: MarkdownText("- [ ] one\n- [ ] two"), new: MarkdownText("- [ ] one\n- [x] two"))
        #expect(change == TextChange(oldRange: MarkdownRange(location: 13, length: 1), newRange: MarkdownRange(location: 13, length: 1)))
    }

    @Test func insertionAndDeletion() {
        #expect(TextChange.between(old: MarkdownText("ac"), new: MarkdownText("abc"))
            == TextChange(oldRange: MarkdownRange(location: 1, length: 0), newRange: MarkdownRange(location: 1, length: 1)))
        #expect(TextChange.between(old: MarkdownText("aaa"), new: MarkdownText("aa"))
            == TextChange(oldRange: MarkdownRange(location: 2, length: 1), newRange: MarkdownRange(location: 2, length: 0)))
    }

    @Test func changeNeverSplitsASurrogatePair() {
        // 😀 and 😃 share their high surrogate.
        let change = TextChange.between(old: MarkdownText("a😀b"), new: MarkdownText("a😃b"))
        #expect(change == TextChange(oldRange: MarkdownRange(location: 1, length: 2), newRange: MarkdownRange(location: 1, length: 2)))
    }

    @Test func offsetsMoveWithTheChange() {
        let change = TextChange(oldRange: MarkdownRange(location: 5, length: 2), newRange: MarkdownRange(location: 5, length: 6))
        #expect(change.map(3) == 3)
        #expect(change.map(5) == 5)
        #expect(change.map(6) == 11)
        #expect(change.map(7) == 11)
        #expect(change.map(10) == 14)
    }
}
