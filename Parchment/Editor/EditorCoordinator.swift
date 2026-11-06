import AppKit
import ParchmentCore

/// Connects the text view to the document and the window's `EditorController`.
///
/// It owns the styler, writes every change back to `document.text`, restyles incrementally,
/// reports text, selection, and scroll progress, and hands the text view the document's undo
/// manager so SwiftUI tracks unsaved changes.
final class EditorCoordinator: NSObject, NSTextViewDelegate {
    let styler: MarkdownStyler
    private(set) var document: MarkdownDocument
    private var controller: EditorController
    private(set) weak var textView: ParchmentTextView?
    /// The document's undo manager from the SwiftUI environment.
    private var documentUndoManager: UndoManager?
    private var observers: [any NSObjectProtocol] = []
    private var lastReportedProgress = -1.0

    init(document: MarkdownDocument, controller: EditorController, metrics: EditorMetrics) {
        self.document = document
        self.controller = controller
        self.styler = MarkdownStyler(metrics: metrics)
        super.init()
    }

    /// Clamps the user's text size into the supported range.
    static func metrics(forFontSize fontSize: Double) -> EditorMetrics {
        let range = EditorMetrics.fontSizeRange
        return EditorMetrics(fontSize: min(max(fontSize, range.lowerBound), range.upperBound))
    }

    // MARK: - Lifecycle

    func makeScrollView(fileURL: URL?, isFocusMode: Bool, isTypewriterMode: Bool, undoManager: UndoManager?) -> NSScrollView {
        documentUndoManager = undoManager

        let textView = ParchmentTextView.makeEditor()
        textView.styler = styler
        styler.textView = textView
        styler.documentURL = fileURL
        textView.metrics = styler.metrics

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Palette.paper
        scrollView.documentView = textView

        textView.loadText(document.text)
        textView.isFocusMode = isFocusMode
        textView.isTypewriterMode = isTypewriterMode
        textView.delegate = self
        self.textView = textView

        controller.textView = textView
        controller.textDidChange(styler.text, lines: styler.lines)
        observe(scrollView.contentView)
        return scrollView
    }

    func update(from view: EditorView, undoManager: UndoManager?) {
        documentUndoManager = undoManager
        let controllerChanged = view.controller !== controller
        if controllerChanged {
            controller = view.controller
        }
        guard let textView else { return }
        controller.textView = textView

        if view.document !== document {
            document = view.document
            // Undo actions recorded against the old text would apply to the wrong ranges.
            textView.undoManager?.removeAllActions()
            textView.loadText(document.text)
            controller.textDidChange(styler.text, lines: styler.lines)
        } else if controllerChanged {
            controller.textDidChange(styler.text, lines: styler.lines)
        }
        if styler.documentURL != view.fileURL {
            styler.documentURL = view.fileURL
            styler.restyleImageLines(matching: nil)
        }

        let metrics = Self.metrics(forFontSize: view.fontSize)
        if textView.metrics != metrics {
            textView.metrics = metrics
        }
        if textView.isFocusMode != view.isFocusMode {
            textView.isFocusMode = view.isFocusMode
        }
        if textView.isTypewriterMode != view.isTypewriterMode {
            textView.isTypewriterMode = view.isTypewriterMode
        }
    }

    func tearDown() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        if let textView {
            textView.delegate = nil
            if controller.textView === textView {
                controller.textView = nil
            }
        }
    }

    /// Watches the clip view for scrolling (progress line, focus dimming) and resizing
    /// (typewriter insets). Observers run synchronously on the main thread that posts them.
    private func observe(_ clipView: NSClipView) {
        clipView.postsBoundsChangedNotifications = true
        clipView.postsFrameChangedNotifications = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: clipView, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.visibleRegionDidChange()
            }
        })
        observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: clipView, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.textView?.visibleSizeDidChange()
                self?.visibleRegionDidChange()
            }
        })
    }

    private func visibleRegionDidChange() {
        guard let textView, let scrollView = textView.enclosingScrollView else { return }
        textView.visibleRegionDidChange()
        reportScrollProgress(of: scrollView, documentHeight: textView.frame.height)
    }

    private func reportScrollProgress(of scrollView: NSScrollView, documentHeight: CGFloat) {
        let clip = scrollView.contentView
        let insets = scrollView.contentInsets
        let scrollable = documentHeight + insets.top + insets.bottom - clip.bounds.height
        let progress: Double = if scrollable > 1 {
            min(max(Double((clip.bounds.minY + insets.top) / scrollable), 0), 1)
        } else {
            0
        }
        guard abs(progress - lastReportedProgress) >= 0.001 else { return }
        lastReportedProgress = progress
        controller.scrollDidChange(progress: progress)
    }

    // MARK: - NSTextViewDelegate

    func undoManager(for view: NSTextView) -> UndoManager? {
        documentUndoManager ?? view.window?.undoManager
    }

    func textDidChange(_ notification: Notification) {
        guard let textView, let storage = textView.textStorage else { return }
        document.text = textView.string
        // Restyling mid-composition would wipe the input method's marked-text underline; the
        // line diff catches up once the composition is committed.
        guard !textView.hasMarkedText() else { return }
        styler.restyle(storage, full: false)
        controller.textDidChange(styler.text, lines: styler.lines)
        textView.editorTextDidChange()
        if let scrollView = textView.enclosingScrollView {
            reportScrollProgress(of: scrollView, documentHeight: textView.frame.height)
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView else { return }
        controller.selectionDidChange(selectedText: Self.selectedText(in: textView))
        controller.caretDidMove(to: textView.selectedRange().location)
        textView.editorSelectionDidChange()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let editor = textView as? ParchmentTextView else { return false }
        return editor.handleCommand(commandSelector)
    }

    private static func selectedText(in textView: NSTextView) -> String {
        // The storage's own string, so a caret move doesn't copy the whole document.
        guard let string = textView.textStorage?.mutableString else { return "" }
        let pieces = textView.selectedRanges.map(\.rangeValue).filter { $0.length > 0 && NSMaxRange($0) <= string.length }
        guard !pieces.isEmpty else { return "" }
        return pieces.map { string.substring(with: $0) }.joined(separator: "\n")
    }
}
