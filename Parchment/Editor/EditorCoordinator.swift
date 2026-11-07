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
    /// Watches the document's file so changes made by other programs (like Claude Code) show up.
    private var fileWatcher: FileWatcher?

    init(document: MarkdownDocument, controller: EditorController, metrics: EditorMetrics) {
        self.document = document
        self.controller = controller
        self.styler = MarkdownStyler(metrics: metrics)
        super.init()
    }

    /// The metrics for the user's text size and line height, each clamped into its range.
    static func metrics(fontSize: Double, lineHeight: Double) -> EditorMetrics {
        EditorMetrics(fontSize: fontSize, lineHeight: lineHeight)
    }

    // MARK: - Lifecycle

    func makeScrollView(from view: EditorView, undoManager: UndoManager?) -> NSScrollView {
        documentUndoManager = undoManager

        let textView = ParchmentTextView.makeEditor()
        textView.styler = styler
        styler.textView = textView
        styler.documentURL = view.fileURL
        textView.metrics = styler.metrics

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Palette.paper
        scrollView.documentView = textView

        // Set before loading, so the first styling pass already includes them.
        textView.ornaments = view.ornaments
        textView.isReading = view.isReading
        textView.inkEffect = view.inkEffect
        textView.loadText(document.text)
        textView.isAgentReadOnly = view.isReadOnly
        textView.isFocusMode = view.isFocusMode
        textView.isTypewriterMode = view.isTypewriterMode
        textView.delegate = self
        self.textView = textView

        controller.textView = textView
        controller.textDidChange(styler.text, lines: styler.lines)
        observe(scrollView.contentView)
        watchFile(at: view.fileURL)
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
            let isSameFile = view.fileURL != nil && view.fileURL == fileWatcher?.url
            document = view.document
            if isSameFile {
                // The same file read again (Revert, or AppKit reloading it after an outside change):
                // change only what differs.
                applyExternalText(document.text)
            } else {
                // Undo actions recorded against the old text would apply to the wrong ranges.
                textView.undoManager?.removeAllActions()
                textView.loadText(document.text)
                controller.textDidChange(styler.text, lines: styler.lines)
            }
        } else if controllerChanged {
            controller.textDidChange(styler.text, lines: styler.lines)
        }
        if styler.documentURL != view.fileURL {
            styler.documentURL = view.fileURL
            styler.restyleImageLines(matching: nil)
        }
        watchFile(at: view.fileURL)
        if textView.isAgentReadOnly != view.isReadOnly {
            textView.isAgentReadOnly = view.isReadOnly
        }
        if textView.agentPresence != view.agent {
            textView.agentPresence = view.agent
        }

        let metrics = Self.metrics(fontSize: view.fontSize, lineHeight: view.lineHeight)
        if textView.metrics != metrics {
            textView.metrics = metrics
        }
        if textView.isFocusMode != view.isFocusMode {
            textView.isFocusMode = view.isFocusMode
        }
        if textView.isTypewriterMode != view.isTypewriterMode {
            textView.isTypewriterMode = view.isTypewriterMode
        }
        if textView.ornaments != view.ornaments {
            textView.ornaments = view.ornaments
        }
        if textView.isReading != view.isReading {
            textView.isReading = view.isReading
        }
        if textView.inkEffect != view.inkEffect {
            textView.inkEffect = view.inkEffect
        }
    }

    func tearDown() {
        textView?.stopAgentEffects()
        fileWatcher?.stop()
        fileWatcher = nil
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

    // MARK: - Changes on disk

    private func watchFile(at url: URL?) {
        guard url != fileWatcher?.url else { return }
        fileWatcher?.stop()
        fileWatcher = url.map { url in
            FileWatcher(url: url) { [weak self] in
                self?.fileDidChangeOnDisk()
            }
        }
    }

    /// Reloads the text from disk, unless the window has unsaved changes (those are never
    /// overwritten; saving later shows AppKit's usual "changed by another application" choice).
    private func fileDidChangeOnDisk() {
        guard let url = fileWatcher?.url else { return }
        let appDocument = NSDocumentController.shared.document(for: url)
        guard appDocument?.isDocumentEdited != true,
              let data = try? Data(contentsOf: url),
              let string = String(data: data, encoding: .utf8) else { return }
        applyExternalText(string)
        // Tell AppKit the document matches the file now, so a later save doesn't warn that
        // another application changed it.
        if let appDocument, !appDocument.isDocumentEdited,
           let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date {
            appDocument.fileModificationDate = date
        }
    }

    private func applyExternalText(_ string: String) {
        guard let textView, let change = textView.applyExternalText(string) else { return }
        document.text = textView.string
        controller.textDidChange(styler.text, lines: styler.lines)
        controller.externalTextDidChange(change)
        if let scrollView = textView.enclosingScrollView {
            reportScrollProgress(of: scrollView, documentHeight: textView.frame.height)
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
        controller.visibleTopDidChange(to: textView.topVisibleCharacterIndex())
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

    /// Keeps spelling and grammar underlines out of inline code and code blocks, where
    /// identifiers like `noImplicitAny` are not misspellings.
    func textView(_ textView: NSTextView, shouldSetSpellingState value: Int, range affectedCharRange: NSRange) -> Int {
        guard value != 0, let storage = textView.textStorage,
              affectedCharRange.location < storage.length else { return value }
        let clamped = NSIntersectionRange(affectedCharRange, NSRange(location: 0, length: storage.length))
        var isCode = false
        storage.enumerateAttributes(in: clamped, options: []) { attributes, _, stop in
            if attributes[.parchmentInlineCode] != nil {
                isCode = true
            } else if let raw = attributes[.parchmentBlock] as? NSNumber,
                      BlockDecoration(rawValue: raw.intValue).contains(.code) {
                isCode = true
            }
            if isCode { stop.pointee = true }
        }
        return isCode ? 0 : value
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
