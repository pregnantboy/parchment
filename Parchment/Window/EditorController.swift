import Foundation
import Observation
import ParchmentCore

/// One per window. The editor engine reports text, selection and scroll changes here,
/// and the window views and menu commands read the derived state.
@Observable
final class EditorController {
    @ObservationIgnored weak var textView: ParchmentTextView?

    private(set) var stats: DocumentStats = .empty
    private(set) var selectionStats: DocumentStats?
    private(set) var headings: [OutlineHeading] = []
    private(set) var scrollProgress: Double = 0
    private(set) var isTyping = false
    var isShowingOutline = false

    private var caretLocation: Int?

    @ObservationIgnored private var pendingText: MarkdownText?
    @ObservationIgnored private var pendingLines: [MarkdownLine] = []
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    @ObservationIgnored private var typingTask: Task<Void, Never>?

    // MARK: Called by the editor engine

    func textDidChange(_ text: MarkdownText, lines: [MarkdownLine]) {
        pendingText = text
        pendingLines = lines

        isTyping = true
        typingTask?.cancel()
        typingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.isTyping = false
        }

        updateTask?.cancel()
        updateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.flushPendingText()
        }
    }

    func selectionDidChange(selectedText: String) {
        if selectedText.isEmpty {
            selectionStats = nil
        } else {
            selectionStats = DocumentStats(counting: selectedText)
        }
    }

    /// Optional: the engine may report the caret's UTF-16 offset to highlight the current heading.
    func caretDidMove(to location: Int) {
        guard caretLocation != location else { return }
        caretLocation = location
    }

    func scrollDidChange(progress: Double) {
        scrollProgress = min(max(progress, 0), 1)
    }

    // MARK: Called by menus and views

    func perform(_ command: EditorCommand) {
        textView?.perform(command)
    }

    func reveal(_ heading: OutlineHeading) {
        textView?.reveal(heading.range)
        isShowingOutline = false
    }

    /// The last heading at or before the caret.
    var currentHeadingID: OutlineHeading.ID? {
        guard let caret = caretLocation ?? textView?.selectedRange().location else { return nil }
        return headings.last { $0.range.location <= caret }?.id
    }

    // MARK: Private

    private func flushPendingText() {
        guard let text = pendingText else { return }
        pendingText = nil
        let string = String(decoding: text.units, as: UTF16.self)
        stats = DocumentStats(counting: string)
        headings = OutlineHeading.headings(in: pendingLines, text: text)
        pendingLines = []
    }
}
