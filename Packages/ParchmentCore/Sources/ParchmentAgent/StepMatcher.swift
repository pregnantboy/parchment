import Foundation
import ParchmentCore

/// Finds the plan step a todo item talks about, by shared words.
///
/// Todos are written by Claude while it works ("Add the reload watcher"), steps by whoever wrote the
/// plan ("Phase 2: Reload on change"), so exact matches are rare. Two texts match when at least half
/// the meaningful words of the shorter one appear in the other.
public enum StepMatcher {
    static let threshold = 0.5

    public static func bestStep(for texts: [String], in steps: [PlanStep]) -> Int? {
        let todoWords = texts.reduce(into: Set<String>()) { $0.formUnion(words(in: $1)) }
        guard !todoWords.isEmpty else { return nil }

        var best: (index: Int, score: Double, shared: Int)?
        for (index, step) in steps.enumerated() {
            let stepWords = words(in: step.title)
            guard !stepWords.isEmpty else { continue }
            let shared = todoWords.intersection(stepWords).count
            let needed = min(todoWords.count, stepWords.count)
            // One shared word only counts when one side is a single word.
            guard shared >= min(2, needed) else { continue }
            let score = Double(shared) / Double(needed)
            guard score >= threshold else { continue }
            if best == nil || score > best!.score || (score == best!.score && shared > best!.shared) {
                best = (index, score, shared)
            }
        }
        return best?.index
    }

    /// Lowercased words longer than two letters, without common filler words and with a trailing
    /// "s", "ed" or "ing" removed so "tests" matches "test" and "adding" matches "add".
    static func words(in text: String) -> Set<String> {
        let raw = text.lowercased().split { !($0.isLetter || $0.isNumber) }
        var result = Set<String>()
        for word in raw where word.count > 2 {
            let word = String(word)
            guard !stopWords.contains(word) else { continue }
            result.insert(stem(word))
        }
        return result
    }

    private static func stem(_ word: String) -> String {
        for suffix in ["ing", "ed", "s"] where word.count > suffix.count + 2 && word.hasSuffix(suffix) {
            return String(word.dropLast(suffix.count))
        }
        return word
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "from", "into", "that", "this", "then", "than", "when", "all",
        "any", "are", "was", "will", "can", "its", "our", "your", "new", "use", "using", "make",
        "phase", "step", "stage", "part", "task", "todo"
    ]
}
