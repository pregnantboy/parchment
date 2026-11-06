import AppKit
import ParchmentCore

/// The editor's text view: TextKit 1, a centered column with a hanging gutter, Markdown-aware
/// keys, clickable task circles, focus dimming, and typewriter scrolling.
final class ParchmentTextView: NSTextView {
    /// Type metrics. Setting it recomputes the column and restyles the whole document.
    var metrics = EditorMetrics(fontSize: EditorMetrics.defaultFontSize) {
        didSet {
            guard metrics != oldValue else { return }
            styler?.metrics = metrics
            defaultParagraphStyle = styler?.bodyParagraphStyle
            updateGeometry(forceRestyle: true)
        }
    }

    /// Dims everything except the paragraph holding the caret.
    var isFocusMode = false {
        didSet {
            guard isFocusMode != oldValue else { return }
            lastFocusState = nil
            refreshFocusDimming()
        }
    }

    /// Keeps the caret's line at the vertical center of the window.
    var isTypewriterMode = false {
        didSet {
            guard isTypewriterMode != oldValue else { return }
            updateGeometry(forceRestyle: false)
            centerCaretIfNeeded()
        }
    }

    /// Set by the coordinator, which owns it.
    weak var styler: MarkdownStyler?

    /// TextKit 1 text views don't retain their storage, so the view keeps it alive itself.
    private var retainedStorage: NSTextStorage?
    private var lastGeometryWidth: CGFloat = -1
    private var lastVisibleHeight: CGFloat = -1
    private var effectiveGutter: Double = 0
    private var isUpdatingGeometry = false
    private var hasBecomeFirstResponder = false
    /// The ranges the last focus dimming pass used, to skip identical passes.
    private var lastFocusState: FocusState?
    /// Whether any dimming has been applied since focus mode was last cleared.
    private var hasFocusDimming = false

    private static let minimumSideInset = 24.0
    private static let tapSlop: CGFloat = 6

    // MARK: - Construction

    /// Builds the TextKit 1 stack explicitly: storage → layout manager → container → view.
    static func makeEditor() -> ParchmentTextView {
        let storage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let view = ParchmentTextView(frame: .zero, textContainer: container)
        view.retainedStorage = storage
        view.configure()
        return view
    }

    private func configure() {
        isRichText = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isContinuousSpellCheckingEnabled = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        smartInsertDeleteEnabled = false
        importsGraphics = false
        usesFontPanel = false
        usesRuler = false
        displaysLinkToolTips = false

        drawsBackground = true
        backgroundColor = Palette.paper
        insertionPointColor = Palette.accent
        selectedTextAttributes = [.backgroundColor: Palette.selection]

        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textContainerInset = NSSize(width: Self.minimumSideInset, height: metrics.topInset)
    }

    /// Replaces the whole text without registering undo, then styles it from scratch.
    func loadText(_ string: String) {
        guard let storage = textStorage else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: string)
        storage.endEditing()
        styler?.restyle(storage, full: true)
        defaultParagraphStyle = styler?.bodyParagraphStyle
        setSelectedRange(NSRange(location: 0, length: 0))
        lastFocusState = nil
        refreshFocusDimming()
    }

    private var markdownLayoutManager: MarkdownLayoutManager? {
        layoutManager as? MarkdownLayoutManager
    }

    // MARK: - Public surface

    func perform(_ command: EditorCommand) {
        guard !hasMarkedText() else { return }
        let text = currentMarkdownText()
        let selection = currentSelection
        let edit: TextEdit? = switch command {
        case .bold: MarkdownEditing.toggleWrap("**", in: text, selection: selection)
        case .italic: MarkdownEditing.toggleWrap("_", in: text, selection: selection)
        case .strikethrough: MarkdownEditing.toggleWrap("~~", in: text, selection: selection)
        case .inlineCode: MarkdownEditing.toggleWrap("`", in: text, selection: selection)
        case .link: MarkdownEditing.insertLink(in: text, selection: selection)
        case .heading(let level): MarkdownEditing.setHeading(level: level, in: text, selection: selection)
        case .task: MarkdownEditing.toggleTask(in: text, selection: selection)
        case .indent: MarkdownEditing.indentListItems(in: text, selection: selection)
        case .outdent: MarkdownEditing.outdentListItems(in: text, selection: selection)
        }
        if let edit {
            apply(edit)
        }
    }

    /// Puts the caret at the start of `range` and scrolls it to the upper third of the window.
    func reveal(_ range: MarkdownRange) {
        guard let storage = textStorage else { return }
        let location = min(max(0, range.location), storage.length)
        setSelectedRange(NSRange(location: location, length: 0))
        window?.makeFirstResponder(self)
        guard let lineRect = lineRect(forCharacterAt: location) else {
            scrollRangeToVisible(NSRange(location: location, length: 0))
            return
        }
        if isTypewriterMode {
            centerCaretIfNeeded()
        } else {
            let insetTop = enclosingScrollView?.contentInsets.top ?? 0
            scrollClip(toY: lineRect.minY - insetTop - CGFloat(visibleHeight / 3))
        }
    }

    /// Applies an edit as one undoable change, then selects and reveals the edit's selection.
    func apply(_ edit: TextEdit) {
        apply(edit, revealSelection: true)
    }

    private func apply(_ edit: TextEdit, revealSelection: Bool) {
        guard let storage = textStorage else { return }
        let range = NSRange(edit.range)
        guard range.location >= 0, NSMaxRange(range) <= storage.length else { return }
        breakUndoCoalescing()
        guard shouldChangeText(in: range, replacementString: edit.replacement) else { return }
        storage.replaceCharacters(in: range, with: edit.replacement)
        didChangeText()

        let selection = NSRange(edit.selection)
        if NSMaxRange(selection) <= storage.length {
            setSelectedRange(selection)
        }
        if revealSelection {
            scrollRangeToVisible(selectedRange())
        }
    }

    // MARK: - Keys

    /// Handles Return, Tab, Shift-Tab and Backspace with Markdown-aware edits. Returns true
    /// only when an edit was applied, so the default behavior runs otherwise.
    func handleCommand(_ selector: Selector) -> Bool {
        guard !hasMarkedText(), selectedRanges.count == 1 else { return false }
        let edit: TextEdit?
        if selector == #selector(NSResponder.insertNewline(_:)) {
            edit = MarkdownEditing.newline(in: currentMarkdownText(), selection: currentSelection)
        } else if selector == #selector(NSResponder.insertTab(_:)) {
            edit = MarkdownEditing.indentListItems(in: currentMarkdownText(), selection: currentSelection)
        } else if selector == #selector(NSResponder.insertBacktab(_:)) {
            edit = MarkdownEditing.outdentListItems(in: currentMarkdownText(), selection: currentSelection)
        } else if selector == #selector(NSResponder.deleteBackward(_:)) {
            edit = AutoPair.deleteBackward(in: currentMarkdownText(), selection: currentSelection)
        } else {
            edit = nil
        }
        guard let edit else { return false }
        apply(edit)
        return true
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        guard !hasMarkedText(),
              replacementRange.location == NSNotFound,
              selectedRanges.count == 1,
              let typed = string as? String,
              typed.utf16.count == 1,
              let edit = AutoPair.insert(typed, in: currentMarkdownText(), selection: currentSelection) else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        apply(edit)
    }

    /// The styler's last parse when it matches the storage, which it does after every change;
    /// otherwise a fresh snapshot.
    private func currentMarkdownText() -> MarkdownText {
        let length = textStorage?.length ?? 0
        if let styler, styler.text.length == length {
            return styler.text
        }
        return MarkdownText(string)
    }

    private var currentSelection: MarkdownRange {
        let range = selectedRange()
        return MarkdownRange(location: range.location, length: range.length)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let boxLocation = taskBoxLocation(at: point) {
            if let edit = MarkdownEditing.toggleTaskBox(at: boxLocation, in: currentMarkdownText(), selection: currentSelection) {
                apply(edit, revealSelection: false)
            }
            return
        }
        if event.modifierFlags.contains(.command), let destination = linkDestination(at: point) {
            openLink(destination)
            return
        }
        super.mouseDown(with: event)
        // super tracks the mouse until it is released; center once the click settles.
        centerCaretIfNeeded()
    }

    private func containerPoint(for point: NSPoint) -> NSPoint {
        let origin = textContainerOrigin
        return NSPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    /// The location of the `[` of the task box under `point`, if any.
    private func taskBoxLocation(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let local = containerPoint(for: point)
        let index = layoutManager.characterIndex(for: local, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        for candidate in [index, index - 1, index - 2, index + 1] where candidate >= 0 && candidate < storage.length {
            var boxRange = NSRange(location: NSNotFound, length: 0)
            let searchStart = max(0, candidate - 3)
            let searchRange = NSRange(location: searchStart, length: min(storage.length, candidate + 4) - searchStart)
            guard storage.attribute(.parchmentTaskBox, at: candidate, longestEffectiveRange: &boxRange, in: searchRange) != nil,
                  boxRange.location != NSNotFound else { continue }
            let glyphs = layoutManager.glyphRange(forCharacterRange: boxRange, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
                .insetBy(dx: -Self.tapSlop, dy: -Self.tapSlop / 2)
            if rect.contains(local) {
                return boxRange.location
            }
        }
        return nil
    }

    private func linkDestination(at point: NSPoint) -> String? {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let local = containerPoint(for: point)
        let index = layoutManager.characterIndex(for: local, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        guard index < storage.length,
              let destination = storage.attribute(.parchmentLink, at: index, effectiveRange: nil) as? String else { return nil }
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer).insetBy(dx: -2, dy: -2)
        return rect.contains(local) ? destination : nil
    }

    /// Opens a link: URLs with a scheme as written, `www.` as https, bare addresses as mail,
    /// and anything else as a file relative to the document.
    private func openLink(_ destination: String) {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return }
        let url: URL?
        if let parsed = URL(string: trimmed), let scheme = parsed.scheme, !scheme.isEmpty {
            url = parsed
        } else if trimmed.lowercased().hasPrefix("www.") {
            url = URL(string: "https://" + trimmed)
        } else if trimmed.contains("@"), !trimmed.contains("/") {
            url = URL(string: "mailto:" + trimmed)
        } else {
            let path = trimmed.split(separator: "#", maxSplits: 1).first.map(String.init) ?? trimmed
            url = styler?.resolveURL(path)
        }
        if let url {
            _ = NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Geometry

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if newSize.width != lastGeometryWidth {
            updateGeometry(forceRestyle: false)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        updateGeometry(forceRestyle: false)
        if !hasBecomeFirstResponder {
            hasBecomeFirstResponder = true
            window.makeFirstResponder(self)
        }
    }

    /// Decorations reach past the text container (code backgrounds, wide images), so every
    /// invalidation covers the full width of the view.
    override func setNeedsDisplay(_ invalidRect: NSRect, avoidAdditionalLayout flag: Bool) {
        var rect = invalidRect
        rect.origin.x = bounds.minX
        rect.size.width = bounds.width
        super.setNeedsDisplay(rect, avoidAdditionalLayout: flag)
    }

    /// Centers gutter + measure in the view, narrowing the measure (and then the gutter, down to
    /// 60%) when the window is small, and sets the top and bottom insets for typewriter mode.
    func updateGeometry(forceRestyle: Bool) {
        guard !isUpdatingGeometry else { return }
        isUpdatingGeometry = true
        defer { isUpdatingGeometry = false }

        let width = Double(bounds.width)
        let height = CGFloat(visibleHeight)
        lastGeometryWidth = bounds.width
        lastVisibleHeight = height

        var needsRestyle = forceRestyle
        // Before the view has a width, assume the full gutter.
        let column = width > 0 ? Self.column(width: width, metrics: metrics) : (gutter: metrics.gutter, sideInset: Self.minimumSideInset)
        if column.gutter != effectiveGutter {
            effectiveGutter = column.gutter
            markdownLayoutManager?.gutter = CGFloat(column.gutter)
        }
        if let styler, styler.gutter != column.gutter {
            styler.gutter = column.gutter
            needsRestyle = true
        }
        if width > 0 {
            let verticalInset = isTypewriterMode ? max(metrics.topInset, Double(height) / 2) : metrics.topInset
            let inset = NSSize(width: column.sideInset.rounded(.down), height: verticalInset.rounded())
            if textContainerInset != inset {
                textContainerInset = inset
            }
            styler?.updateAvailableImageWidth(width - column.sideInset.rounded(.down) - column.gutter - Self.minimumSideInset)
        }

        if needsRestyle, let storage = textStorage, let styler {
            styler.restyle(storage, full: true)
            defaultParagraphStyle = styler.bodyParagraphStyle
            lastFocusState = nil
            refreshFocusDimming()
        }
    }

    /// Called when the scroll view's visible height changes, which typewriter insets depend on.
    func visibleSizeDidChange() {
        if CGFloat(visibleHeight) != lastVisibleHeight || bounds.width != lastGeometryWidth {
            updateGeometry(forceRestyle: false)
            centerCaretIfNeeded()
        }
    }

    private static func column(width: Double, metrics: EditorMetrics) -> (gutter: Double, sideInset: Double) {
        var gutter = metrics.gutter
        var measure = metrics.measure
        let available = width - 2 * minimumSideInset
        if available < gutter + measure {
            let minimumMeasure = metrics.fontSize * 12
            measure = available - gutter
            if measure < minimumMeasure {
                // Quantized so live resizing restyles in steps rather than every frame.
                let shrunk = ((available - minimumMeasure) / 4).rounded(.down) * 4
                gutter = max(metrics.gutter * 0.6, min(metrics.gutter, shrunk))
                measure = max(0, available - gutter)
            }
        }
        return (gutter, max(minimumSideInset, (width - gutter - measure) / 2))
    }

    /// The scroll view's visible height, excluding content insets such as a toolbar.
    private var visibleHeight: Double {
        guard let scrollView = enclosingScrollView else { return Double(visibleRect.height) }
        let insets = scrollView.contentInsets
        return Double(max(0, scrollView.contentView.bounds.height - insets.top - insets.bottom))
    }

    // MARK: - Editing feedback

    /// Called by the coordinator after every text change.
    func editorTextDidChange() {
        refreshFocusDimming()
        centerCaretIfNeeded()
    }

    /// Called by the coordinator after every selection change.
    func editorSelectionDidChange() {
        refreshFocusDimming()
        // Don't chase the caret while the user is still dragging out a selection.
        if NSEvent.pressedMouseButtons == 0 {
            centerCaretIfNeeded()
        }
    }

    /// Called by the coordinator when the view scrolls.
    func visibleRegionDidChange() {
        refreshFocusDimming()
    }

    // MARK: - Typewriter

    private func centerCaretIfNeeded() {
        guard isTypewriterMode, let storage = textStorage else { return }
        let location = min(selectedRange().location, storage.length)
        guard let lineRect = lineRect(forCharacterAt: location) else { return }
        let insetTop = enclosingScrollView?.contentInsets.top ?? 0
        scrollClip(toY: lineRect.midY - insetTop - CGFloat(visibleHeight / 2))
    }

    /// The used rect of the line holding `location`, in view coordinates.
    private func lineRect(forCharacterAt location: Int) -> NSRect? {
        guard let layoutManager, let storage = textStorage else { return nil }
        let origin = textContainerOrigin
        let length = storage.length
        if length == 0 || (location >= length && storage.mutableString.character(at: length - 1) == 10) {
            layoutManager.ensureLayout(forCharacterRange: NSRange(location: max(0, length - 1), length: min(1, length)))
            let extra = layoutManager.extraLineFragmentRect
            guard !extra.isEmpty else { return nil }
            return extra.offsetBy(dx: origin.x, dy: origin.y)
        }
        let glyph = layoutManager.glyphIndexForCharacter(at: min(location, length - 1))
        let rect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
        return rect.offsetBy(dx: origin.x, dy: origin.y)
    }

    private func scrollClip(toY y: CGFloat) {
        guard let scrollView = enclosingScrollView else { return }
        let clip = scrollView.contentView
        let insets = scrollView.contentInsets
        let minimum = -insets.top
        let maximum = max(minimum, frame.height - clip.bounds.height + insets.bottom)
        let target = min(max(y, minimum), maximum).rounded()
        guard abs(clip.bounds.origin.y - target) >= 0.5 else { return }
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: target))
        scrollView.reflectScrolledClipView(clip)
    }

    // MARK: - Focus mode

    /// Dims the visible text with a temporary color, then lifts it from the current paragraph
    /// (the non-blank lines around the caret). Only the visible range is touched.
    private func refreshFocusDimming() {
        guard let layoutManager, let storage = textStorage else { return }
        let length = storage.length
        guard isFocusMode, length > 0 else {
            if hasFocusDimming {
                layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: length))
                hasFocusDimming = false
            }
            lastFocusState = nil
            return
        }

        let visible = visibleCharacterRange()
        let current = currentParagraphRange()
        let state = FocusState(visible: visible, current: current, length: length)
        guard state != lastFocusState else { return }
        lastFocusState = state
        guard visible.length > 0 else { return }

        layoutManager.addTemporaryAttribute(.foregroundColor, value: Palette.dimmed, forCharacterRange: visible)
        hasFocusDimming = true
        if current.length > 0 {
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: current)
        }
        // Task boxes are drawn as circles; their transparent glyphs must stay transparent.
        storage.enumerateAttribute(.parchmentTaskBox, in: visible, options: []) { value, range, _ in
            if value != nil {
                layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
            }
        }
    }

    /// The visible characters plus half a screen above and below, so scrolling never shows
    /// undimmed text before the next pass.
    private func visibleCharacterRange() -> NSRange {
        guard let layoutManager, let textContainer, let storage = textStorage else { return NSRange(location: 0, length: 0) }
        let origin = textContainerOrigin
        var rect = visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        rect = rect.insetBy(dx: 0, dy: -rect.height / 2)
        let glyphs = layoutManager.glyphRange(forBoundingRect: rect, in: textContainer)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        return NSIntersectionRange(characters, NSRange(location: 0, length: storage.length))
    }

    /// The run of non-blank lines around the selection.
    private func currentParagraphRange() -> NSRange {
        guard let storage = textStorage, storage.length > 0 else { return NSRange(location: 0, length: 0) }
        let text = storage.mutableString
        let length = storage.length
        let selection = selectedRange()
        let lowerLine = text.lineRange(for: NSRange(location: min(selection.location, length), length: 0))
        let upperLine = text.lineRange(for: NSRange(location: min(NSMaxRange(selection), length), length: 0))
        if selection.length == 0, Self.isBlank(lowerLine, in: text) {
            return NSRange(location: lowerLine.location, length: 0)
        }

        var start = lowerLine.location
        var steps = 0
        while start > 0, steps < 500 {
            let previous = text.lineRange(for: NSRange(location: start - 1, length: 0))
            if Self.isBlank(previous, in: text) { break }
            start = previous.location
            steps += 1
        }
        var end = NSMaxRange(upperLine)
        steps = 0
        while end < length, steps < 500 {
            let next = text.lineRange(for: NSRange(location: end, length: 0))
            if Self.isBlank(next, in: text) { break }
            end = NSMaxRange(next)
            steps += 1
        }
        return NSRange(location: start, length: end - start)
    }

    private static func isBlank(_ line: NSRange, in text: NSString) -> Bool {
        let whitespace = CharacterSet.whitespacesAndNewlines
        for offset in 0..<line.length {
            guard let scalar = Unicode.Scalar(text.character(at: line.location + offset)) else { return false }
            if !whitespace.contains(scalar) { return false }
        }
        return true
    }
}

/// The inputs of a focus dimming pass.
nonisolated private struct FocusState: Equatable {
    var visible: NSRange
    var current: NSRange
    var length: Int
}

private extension NSRange {
    init(_ textRange: MarkdownRange) {
        self.init(location: textRange.location, length: textRange.length)
    }
}
