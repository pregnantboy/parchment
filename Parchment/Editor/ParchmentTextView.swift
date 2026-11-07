import AppKit
import ParchmentCore
import QuartzCore

/// The editor's text view: TextKit 1, a centered column with a hanging gutter, Markdown-aware
/// keys, clickable task circles, focus dimming, typewriter scrolling, reading mode, and wet ink.
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

    /// Read-only, with Markdown symbols hidden. Task circles stay clickable and links open
    /// with a plain click.
    var isReading = false {
        didSet {
            guard isReading != oldValue else { return }
            updateEditability()
            styler?.isReading = isReading
            markdownLayoutManager?.isReading = isReading
            stopInk()
            restyleEverything()
        }
    }

    /// Locked while Claude Code is working on this file. Unlike reading mode, task circles
    /// can't be ticked either.
    var isAgentReadOnly = false {
        didSet {
            if isAgentReadOnly != oldValue { updateEditability() }
        }
    }

    private func updateEditability() {
        isEditable = !isReading && !isAgentReadOnly
    }

    /// Wax seals, filigree rules, a raised initial, a large quote mark and diamond bullets.
    var ornaments = false {
        didSet {
            guard ornaments != oldValue else { return }
            styler?.ornaments = ornaments
            markdownLayoutManager?.ornaments = ornaments
            restyleEverything()
        }
    }

    /// New letters land as wet ink and dry over `InkDrop.duration`.
    var inkEffect = false {
        didSet {
            if !inkEffect { stopInk() }
        }
    }

    /// Set by the coordinator, which owns it.
    weak var styler: MarkdownStyler?

    /// What Claude is doing in this file, or `nil` when no session follows it. Drives the
    /// in-text effects in `AgentEffects.swift`.
    var agentPresence: AgentPresence? {
        didSet {
            if agentPresence != oldValue { agentPresenceDidChange(from: oldValue) }
        }
    }
    let agentEffects = AgentEffects()
    var agentEffectsLink: CADisplayLink?
    /// When the user last scrolled by hand. Following Claude pauses for a few seconds after.
    var lastUserScroll = Date.distantPast

    /// TextKit 1 text views don't retain their storage, so the view keeps it alive itself.
    private var retainedStorage: NSTextStorage?
    private var lastGeometryWidth: CGFloat = -1
    private var lastVisibleHeight: CGFloat = -1
    private(set) var effectiveGutter: Double = 0
    private var isUpdatingGeometry = false
    private var hasBecomeFirstResponder = false
    /// The ranges the last focus dimming pass used, to skip identical passes.
    private var lastFocusState: FocusState?
    /// Whether any dimming has been applied since focus mode was last cleared.
    private var hasFocusDimming = false
    /// The container inset from the column and typewriter geometry, before the room for a
    /// trailing image is added below the text.
    private var baseContainerInset = NSSize.zero
    /// Room reserved below the text for an image on the document's last line. That line has
    /// no line break, so the paragraph spacing that holds every other image doesn't exist.
    private var trailingImageReserve: CGFloat = 0

    private static let minimumSideInset = 24.0
    /// Matches the layout manager's gap between an image and its source line.
    private static let imageTopGap: CGFloat = 12
    private static let imageRadius: CGFloat = 12
    private static let tapSlop: CGFloat = 6
    /// The most drops kept drying at once; fast typists never notice the cap.
    private static let maxInkDrops = 48

    private var inkDisplayLink: CADisplayLink?

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
        baseContainerInset = NSSize(width: Self.minimumSideInset, height: metrics.topInset)
        textContainerInset = baseContainerInset
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

    /// Replaces the text with a newer version from disk, changing only the part that differs, so
    /// the rest keeps its styling and the selection stays put. The edit bypasses undo (undo
    /// history is cleared, since its ranges no longer match), so the document is not marked as edited.
    /// Returns the change, or `nil` when the text is the same.
    @discardableResult
    func applyExternalText(_ string: String) -> TextChange? {
        guard let storage = textStorage, !hasMarkedText() else { return nil }
        let new = MarkdownText(string)
        guard let change = TextChange.between(old: currentMarkdownText(), new: new) else { return nil }

        let selection = selectedRange()
        let replaced = storage.mutableString.substring(with: NSRange(change.oldRange))
        undoManager?.removeAllActions()
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(change.oldRange), with: new.string(in: change.newRange))
        storage.endEditing()

        let start = change.map(selection.location)
        let end = change.map(NSMaxRange(selection))
        setSelectedRange(NSRange(location: start, length: max(0, end - start)))
        styler?.restyle(storage, full: false)
        lastFocusState = nil
        refreshFocusDimming()
        if agentPresence != nil {
            agentDidChangeText(change, replaced: replaced)
        }
        return change
    }

    var markdownLayoutManager: MarkdownLayoutManager? {
        layoutManager as? MarkdownLayoutManager
    }

    /// Restyles the whole document and rebuilds its glyphs, for switches that change which
    /// characters are hidden or decorated.
    private func restyleEverything() {
        guard let storage = textStorage, let styler else { return }
        styler.restyle(storage, full: true)
        defaultParagraphStyle = styler.bodyParagraphStyle
        let all = NSRange(location: 0, length: storage.length)
        layoutManager?.invalidateGlyphs(forCharacterRange: all, changeInLength: 0, actualCharacterRange: nil)
        layoutManager?.invalidateLayout(forCharacterRange: all, actualCharacterRange: nil)
        lastFocusState = nil
        refreshFocusDimming()
        needsDisplay = true
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
        // Keep the edit its own undo step, apart from any typing that follows.
        breakUndoCoalescing()

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
        let wasComposing = hasMarkedText()
        let start = selectedRange().location
        insertTyping(string, replacementRange: replacementRange)

        // Typed letters (not pasted text or input method commits) land as wet ink.
        let typed = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        let count = typed.utf16.count
        if !wasComposing, !hasMarkedText(), replacementRange.location == NSNotFound,
           count > 0, count <= 4, typed.contains(where: { !$0.isWhitespace }) {
            addInkDrop(NSRange(location: start, length: count))
        }
    }

    private func insertTyping(_ string: Any, replacementRange: NSRange) {
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

    /// Keeps drying ink on the right characters when text before it changes.
    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard super.shouldChangeText(in: affectedCharRange, replacementString: replacementString) else { return false }
        if let replacementString {
            shiftInkDrops(around: affectedCharRange, replacementLength: replacementString.utf16.count)
        }
        return true
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
        // While an input method is composing, the styler's parse is stale; let super commit first.
        if !hasMarkedText(), !isAgentReadOnly, let boxLocation = taskBoxLocation(at: point) {
            if let edit = MarkdownEditing.toggleTaskBox(at: boxLocation, in: currentMarkdownText(), selection: currentSelection) {
                // Reading mode is read-only except for ticking tasks, so allow this one edit.
                let wasEditable = isEditable
                isEditable = true
                apply(edit, revealSelection: false)
                isEditable = wasEditable
            }
            return
        }
        if isReading || event.modifierFlags.contains(.command), let destination = linkDestination(at: point) {
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
        guard let window else {
            stopInk()
            return
        }
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
            baseContainerInset = NSSize(width: column.sideInset.rounded(.down), height: verticalInset.rounded())
            styler?.updateAvailableImageWidth(width - column.sideInset.rounded(.down) - column.gutter - Self.minimumSideInset)
        }

        if needsRestyle, let storage = textStorage, let styler {
            styler.restyle(storage, full: true)
            defaultParagraphStyle = styler.bodyParagraphStyle
            lastFocusState = nil
            refreshFocusDimming()
        }
        applyContainerInset()
    }

    // MARK: - Trailing image

    /// Called by the styler after it restyles, since the last line may have gained or lost an image.
    func stylingDidChange() {
        applyContainerInset()
    }

    /// The text container sits `baseContainerInset.height` from the top. The inset is grown by
    /// half the trailing image reserve and `textContainerOrigin` moves back up by the same
    /// amount, so the whole reserve lands below the text (the view adds the inset above and below).
    private func applyContainerInset() {
        var reserve: CGFloat = 0
        if let trailing = trailingImage() {
            reserve = (trailing.spacing / 2).rounded(.up) * 2
        }
        let reserveChanged = reserve != trailingImageReserve
        trailingImageReserve = reserve
        let inset = NSSize(width: baseContainerInset.width, height: baseContainerInset.height + reserve / 2)
        if textContainerInset != inset {
            textContainerInset = inset
        }
        if reserveChanged {
            needsDisplay = true
        }
    }

    override var textContainerOrigin: NSPoint {
        let origin = super.textContainerOrigin
        return NSPoint(x: origin.x, y: origin.y - trailingImageReserve / 2)
    }

    /// The image on the last line when that line has no line break, with the height the styler
    /// sized it to and the paragraph spacing it reserved for it.
    private func trailingImage() -> (image: NSImage, height: CGFloat, spacing: CGFloat)? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let last = storage.length - 1
        let character = storage.mutableString.character(at: last)
        guard character != 10, character != 13 else { return nil }
        let attributes = storage.attributes(at: last, effectiveRange: nil)
        guard let image = attributes[.parchmentImage] as? NSImage,
              let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle else { return nil }
        let height = paragraph.paragraphSpacing - Self.imageTopGap * 2
        guard height > 1, image.size.width > 0, image.size.height > 0 else { return nil }
        return (image, height, paragraph.paragraphSpacing)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawTrailingImage(in: dirtyRect)
        drawAgentEffects(in: dirtyRect)
    }

    override func scrollWheel(with event: NSEvent) {
        lastUserScroll = Date()
        super.scrollWheel(with: event)
    }

    /// The layout manager draws images in their line's paragraph spacing; the last line has
    /// none, so its image is drawn here, in the reserve below the text.
    private func drawTrailingImage(in dirtyRect: NSRect) {
        guard trailingImageReserve > 0, let trailing = trailingImage(), let storage = textStorage,
              let line = lineRect(forCharacterAt: storage.length - 1) else { return }
        let size = trailing.image.size
        let destination = NSRect(
            x: textContainerOrigin.x + CGFloat(effectiveGutter),
            y: line.maxY + Self.imageTopGap,
            width: trailing.height * size.width / size.height,
            height: trailing.height
        )
        guard destination.intersects(dirtyRect) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: destination, xRadius: Self.imageRadius, yRadius: Self.imageRadius).addClip()
        trailing.image.draw(
            in: destination,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)]
        )
        NSGraphicsContext.restoreGraphicsState()
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
    var visibleHeight: Double {
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

    // MARK: - Wet ink

    private func addInkDrop(_ range: NSRange) {
        guard inkEffect, !isReading, let layoutManager = markdownLayoutManager,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let storage = textStorage, NSMaxRange(range) <= storage.length else { return }
        layoutManager.inkDrops.append(InkDrop(range: range, start: ProcessInfo.processInfo.systemUptime))
        if layoutManager.inkDrops.count > Self.maxInkDrops {
            layoutManager.inkDrops.removeFirst(layoutManager.inkDrops.count - Self.maxInkDrops)
        }
        if inkDisplayLink == nil {
            let link = displayLink(target: self, selector: #selector(inkFrame(_:)))
            link.add(to: .main, forMode: .common)
            inkDisplayLink = link
        }
    }

    /// Redraws drying ink each frame, and stops once every drop has dried.
    @objc private func inkFrame(_ link: CADisplayLink) {
        guard let layoutManager = markdownLayoutManager else {
            stopInk()
            return
        }
        for drop in layoutManager.inkDrops {
            if let rect = inkRect(for: drop.range) {
                setNeedsDisplay(rect)
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        // Expired drops were just invalidated above, so their final, dry frame still draws.
        layoutManager.inkDrops.removeAll { now - $0.start >= InkDrop.duration }
        if layoutManager.inkDrops.isEmpty {
            link.invalidate()
            inkDisplayLink = nil
        }
    }

    private func stopInk() {
        inkDisplayLink?.invalidate()
        inkDisplayLink = nil
        if let layoutManager = markdownLayoutManager, !layoutManager.inkDrops.isEmpty {
            layoutManager.inkDrops.removeAll()
            needsDisplay = true
        }
    }

    /// The area a drop draws in, including its halo, in view coordinates.
    private func inkRect(for range: NSRange) -> NSRect? {
        guard let layoutManager, let textContainer, let storage = textStorage,
              range.length > 0, NSMaxRange(range) <= storage.length else { return nil }
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        let origin = textContainerOrigin
        return layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            .offsetBy(dx: origin.x, dy: origin.y)
            .insetBy(dx: -24, dy: -16)
    }

    /// Moves drops after an edit by its change in length and drops any the edit touched.
    private func shiftInkDrops(around edited: NSRange, replacementLength: Int) {
        guard let layoutManager = markdownLayoutManager, !layoutManager.inkDrops.isEmpty else { return }
        let delta = replacementLength - edited.length
        layoutManager.inkDrops = layoutManager.inkDrops.compactMap { drop in
            var drop = drop
            if drop.range.location >= NSMaxRange(edited) {
                drop.range.location += delta
            } else if NSMaxRange(drop.range) > edited.location {
                return nil
            }
            return drop
        }
    }

    /// The character at the top of the visible text, below any toolbar.
    func topVisibleCharacterIndex() -> Int? {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let origin = textContainerOrigin
        let insetTop = enclosingScrollView?.contentInsets.top ?? 0
        let point = NSPoint(x: CGFloat(effectiveGutter) + 1, y: visibleRect.minY + insetTop + 12 - origin.y)
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
        return min(layoutManager.characterIndexForGlyph(at: glyph), storage.length)
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
    func lineRect(forCharacterAt location: Int) -> NSRect? {
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

    func scrollClip(toY y: CGFloat, animated: Bool = false) {
        guard let scrollView = enclosingScrollView else { return }
        let clip = scrollView.contentView
        let insets = scrollView.contentInsets
        let minimum = -insets.top
        let maximum = max(minimum, frame.height - clip.bounds.height + insets.bottom)
        let target = min(max(y, minimum), maximum).rounded()
        guard abs(clip.bounds.origin.y - target) >= 0.5 else { return }
        let origin = NSPoint(x: clip.bounds.origin.x, y: target)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                clip.animator().setBoundsOrigin(origin)
            }
        } else {
            clip.scroll(to: origin)
        }
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
        // Transparent glyphs (task boxes drawn as circles, markers hidden in reading mode)
        // must stay transparent.
        storage.enumerateAttribute(.foregroundColor, in: visible, options: []) { value, range, _ in
            if let color = value as? NSColor, color.alphaComponent == 0 {
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
