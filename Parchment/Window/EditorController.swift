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
    /// The outline popover, used when the window is too narrow for the side panel.
    var isShowingOutline = false
    /// Reading mode for this window: read-only, Markdown symbols hidden.
    var isReading = false
    /// Set by the window: whether it is wide enough for the outline side panel.
    var isOutlineSidebarAvailable = false {
        didSet {
            if isOutlineSidebarAvailable { isShowingOutline = false }
        }
    }

    private var caretLocation: Int?
    /// The heading at the top of the window, which reading mode highlights in the outline.
    private var readingHeadingID: OutlineHeading.ID?
    @ObservationIgnored private var topVisibleLocation: Int?

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

    /// The UTF-16 offset of the first character at the top of the window.
    func visibleTopDidChange(to location: Int?) {
        topVisibleLocation = location
        updateReadingHeading()
    }

    // MARK: Called by menus and views

    func perform(_ command: EditorCommand) {
        textView?.perform(command)
    }

    /// Shows or hides the side panel when the window is wide enough, the popover otherwise.
    func toggleOutline() {
        if isOutlineSidebarAvailable {
            let defaults = UserDefaults.standard
            let isShown = defaults.object(forKey: PreferenceKey.showsOutlineSidebar) as? Bool ?? true
            defaults.set(!isShown, forKey: PreferenceKey.showsOutlineSidebar)
        } else {
            isShowingOutline.toggle()
        }
    }

    func reveal(_ heading: OutlineHeading) {
        textView?.reveal(heading.range)
        isShowingOutline = false
    }

    /// The last heading at or before the caret, or while reading, at the top of the window.
    var currentHeadingID: OutlineHeading.ID? {
        if isReading { return readingHeadingID }
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
        updateReadingHeading()
    }

    private func updateReadingHeading() {
        guard let location = topVisibleLocation else { return }
        let id = headings.last { $0.range.location <= location }?.id
        if id != readingHeadingID {
            readingHeadingID = id
        }
    }
}
