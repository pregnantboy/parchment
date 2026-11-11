import AppKit
import ParchmentAgent
import ParchmentCore

/// What the text view needs to know about the Claude session following its file.
struct AgentPresence: Equatable {
    /// A step Claude (or a helper) is working on, by the start of its line.
    struct StepMark: Equatable {
        var location: Int
        var owner: String?
    }

    var isWorking: Bool
    /// Who made the last change in this file, for the name tag on Claude's caret.
    var lastEditor: String
    var currentSteps: [StepMark]
    /// Scroll to each change, unless the user scrolled a moment ago.
    var follows: Bool

    init(status: PlanStatus, steps: [PlanStep], follows: Bool) {
        isWorking = status.isWorking
        lastEditor = status.session.lastEdit?.owner ?? AgentSession.mainAgentName
        currentSteps = status.progress.currentSteps.compactMap { current in
            guard steps.indices.contains(current.index) else { return nil }
            return StepMark(location: steps[current.index].range.location, owner: current.owner)
        }
        self.follows = follows
    }
}

/// The live state of the in-text effects. Times are `CACurrentMediaTime()` seconds.
final class AgentEffects {
    struct Mark {
        var range: NSRange
        var start: CFTimeInterval
    }

    /// Text Claude just wrote, drying from faint to full ink.
    var inks: [Mark] = []
    /// Lines Claude just changed, marked in the margin.
    var marks: [Mark] = []
    /// Task boxes Claude just ticked, by the location of their `[`.
    var fills: [Int: CFTimeInterval] = [:]
    /// Where Claude's last change ended.
    var caret: Int?

    static let inkDuration: CFTimeInterval = 0.6
    static let markHold: CFTimeInterval = 3
    static let markFade: CFTimeInterval = 1
    static let fillDuration: CFTimeInterval = 0.35
    static let caretPeriod: CFTimeInterval = 1.2
    static let pulsePeriod: CFTimeInterval = 1.6

    var isEmpty: Bool { inks.isEmpty && marks.isEmpty && fills.isEmpty }

    /// Moves every stored location through a newer change, so marks stay on their text.
    func shift(by change: TextChange) {
        func moved(_ range: NSRange) -> NSRange {
            let start = change.map(range.location)
            let end = change.map(NSMaxRange(range))
            return NSRange(location: start, length: max(0, end - start))
        }
        inks = inks.map { Mark(range: moved($0.range), start: $0.start) }
        marks = marks.map { Mark(range: moved($0.range), start: $0.start) }
        fills = Dictionary(fills.map { (change.map($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
        caret = caret.map { change.map($0) }
    }

    /// Drops finished effects and returns their ranges, so their last frame can be cleared.
    func prune(now: CFTimeInterval) -> [NSRange] {
        var removed: [NSRange] = []
        inks.removeAll { mark in
            let done = now - mark.start >= Self.inkDuration
            if done { removed.append(mark.range) }
            return done
        }
        marks.removeAll { mark in
            let done = now - mark.start >= Self.markHold + Self.markFade
            if done { removed.append(mark.range) }
            return done
        }
        for (location, start) in fills where now - start >= Self.fillDuration {
            fills[location] = nil
            removed.append(NSRange(location: location, length: 3))
        }
        return removed
    }

    func clear() {
        inks = []
        marks = []
        fills = [:]
        caret = nil
    }
}

extension ParchmentTextView {
    var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: - Reacting

    func agentPresenceDidChange(from old: AgentPresence?) {
        guard let layoutManager = markdownLayoutManager else { return }
        guard let presence = agentPresence else {
            agentEffects.clear()
            layoutManager.activeTaskLines = []
            layoutManager.taskFills = [:]
            stopAgentEffects()
            needsDisplay = true
            return
        }
        let lines = Set(presence.currentSteps.map(\.location))
        if lines != layoutManager.activeTaskLines || presence.currentSteps != old?.currentSteps
            || presence.isWorking != old?.isWorking {
            layoutManager.activeTaskLines = lines
            needsDisplay = true
        }
        startAgentEffects()
    }

    /// Called after Claude changed the file and the change was applied and restyled.
    func agentDidChangeText(_ change: TextChange, replaced: String) {
        guard let presence = agentPresence, let storage = textStorage else { return }
        let now = CACurrentMediaTime()
        let text = storage.mutableString
        let range = NSRange(location: change.newRange.location, length: change.newRange.length)
        agentEffects.shift(by: change)

        let lines = text.lineRange(for: NSRange(location: min(range.location, text.length), length: min(range.length, text.length - min(range.location, text.length))))
        if range.length > 0 {
            agentEffects.inks.append(AgentEffects.Mark(range: range, start: now))
        }
        agentEffects.marks.append(AgentEffects.Mark(range: lines, start: now))

        // A box Claude ticked: "[ ]", "[/]" or "[!]" became "[x]".
        if [" ", "/", "!"].contains(replaced), range.length == 1, NSMaxRange(range) <= storage.length,
           text.substring(with: range).lowercased() == "x" {
            var box = NSRange(location: NSNotFound, length: 0)
            if storage.attribute(.parchmentTaskBox, at: range.location, effectiveRange: &box) != nil,
               box.location != NSNotFound {
                agentEffects.fills[box.location] = now
            }
        }
        agentEffects.caret = NSMaxRange(range)

        if presence.follows {
            followAgent(to: range)
        }
        startAgentEffects()
        invalidateAgentEffects()
    }

    /// Scrolls the change into the middle of the window when it is near the edge or off screen,
    /// unless the user scrolled in the last four seconds.
    private func followAgent(to range: NSRange) {
        guard Date().timeIntervalSince(lastUserScroll) > 4,
              let scrollView = enclosingScrollView,
              let rect = lineRect(forCharacterAt: range.location) else { return }
        let clip = scrollView.contentView.bounds
        let insets = scrollView.contentInsets
        let height = CGFloat(visibleHeight)
        let top = clip.minY + insets.top
        let margin = height * 0.15
        guard rect.minY < top + margin || rect.maxY > top + height - margin else { return }
        scrollClip(toY: rect.midY - insets.top - height / 2, animated: !reducesMotion)
    }

    // MARK: - Animation

    private var isAnimatingAgentEffects: Bool {
        !agentEffects.isEmpty || (agentPresence?.isWorking == true && !reducesMotion)
    }

    func startAgentEffects() {
        guard agentEffectsLink == nil, isAnimatingAgentEffects else { return }
        let link = displayLink(target: self, selector: #selector(agentEffectsFrame(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 60, preferred: 30)
        link.add(to: .main, forMode: .common)
        agentEffectsLink = link
    }

    func stopAgentEffects() {
        agentEffectsLink?.invalidate()
        agentEffectsLink = nil
    }

    @objc private func agentEffectsFrame(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let removed = agentEffects.prune(now: now)
        for range in removed {
            invalidate(range, padding: 8)
        }
        if let layoutManager = markdownLayoutManager {
            let reduce = reducesMotion
            layoutManager.animatesTasks = !reduce
            layoutManager.taskPulse = reduce ? 0 : CGFloat((now / AgentEffects.pulsePeriod).truncatingRemainder(dividingBy: 1))
            layoutManager.taskFills = agentEffects.fills.mapValues { start in
                reduce ? 1 : CGFloat(min(1, (now - start) / AgentEffects.fillDuration))
            }
        }
        invalidateAgentEffects()
        if !isAnimatingAgentEffects {
            stopAgentEffects()
        }
    }

    /// Asks for a redraw of just the places that animate.
    private func invalidateAgentEffects() {
        for mark in agentEffects.inks { invalidate(mark.range, padding: 2) }
        for mark in agentEffects.marks { invalidate(mark.range, padding: 2) }
        for location in agentEffects.fills.keys { invalidate(NSRange(location: location, length: 3), padding: 8) }
        if let caret = agentEffects.caret, let rect = caretRect(at: caret) {
            setNeedsDisplay(rect.insetBy(dx: -4, dy: -22))
        }
        for step in agentPresence?.currentSteps ?? [] {
            if let rect = lineRect(forCharacterAt: step.location) {
                setNeedsDisplay(rect.insetBy(dx: 0, dy: -10))
            }
        }
    }

    private func invalidate(_ range: NSRange, padding: CGFloat) {
        for rect in glyphRects(for: range) {
            setNeedsDisplay(rect.insetBy(dx: -padding, dy: -padding))
        }
    }

    // MARK: - Drawing

    func drawAgentEffects(in dirtyRect: NSRect) {
        guard agentPresence != nil else { return }
        let now = CACurrentMediaTime()
        let reduce = reducesMotion

        // Wet ink: a paper-colored veil over new text that clears as the ink dries.
        if !reduce {
            for ink in agentEffects.inks {
                let progress = (now - ink.start) / AgentEffects.inkDuration
                guard progress < 1 else { continue }
                let alpha = 0.75 * (1 - progress) * (1 - progress)
                Palette.paper.withAlphaComponent(alpha).setFill()
                for rect in glyphRects(for: ink.range) where rect.intersects(dirtyRect) {
                    NSBezierPath(rect: rect).fill()
                }
            }
        }

        // Margin marks: a thin bar left of the column beside each changed line.
        for mark in agentEffects.marks {
            let age = now - mark.start
            let alpha = reduce || age < AgentEffects.markHold
                ? 1
                : max(0, 1 - (age - AgentEffects.markHold) / AgentEffects.markFade)
            guard alpha > 0, let bounds = unionRect(of: glyphRects(for: mark.range)) else { continue }
            let bar = NSRect(x: textContainerOrigin.x - 14, y: bounds.minY + 2, width: 3, height: max(4, bounds.height - 4))
            guard bar.intersects(dirtyRect) else { continue }
            Palette.accent.withAlphaComponent(alpha).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
        }

        drawHelperTags(in: dirtyRect)
        drawAgentCaret(now: now, reduce: reduce, in: dirtyRect)
    }

    /// Claude's caret: a pulsing vermilion bar where the last change ended, with a name tag.
    private func drawAgentCaret(now: CFTimeInterval, reduce: Bool, in dirtyRect: NSRect) {
        guard let presence = agentPresence, presence.isWorking,
              let caret = agentEffects.caret, let rect = caretRect(at: caret) else { return }

        let tag = NSAttributedString(string: presence.lastEditor, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: Palette.paper
        ])
        let tagSize = tag.size()
        let tagRect = NSRect(x: rect.minX - 1, y: rect.minY - tagSize.height - 5, width: tagSize.width + 10, height: tagSize.height + 3)
        guard rect.union(tagRect).intersects(dirtyRect) else { return }

        let pulse = reduce ? 1 : 0.45 + 0.55 * (0.5 + 0.5 * cos(2 * .pi * now / AgentEffects.caretPeriod))
        Palette.accent.withAlphaComponent(pulse).setFill()
        NSBezierPath(rect: rect).fill()

        Palette.accent.setFill()
        NSBezierPath(roundedRect: tagRect, xRadius: tagRect.height / 2, yRadius: tagRect.height / 2).fill()
        tag.draw(at: NSPoint(x: tagRect.minX + 5, y: tagRect.minY + 1.5))
    }

    /// The helper's name after the first line of each step a helper is working on.
    private func drawHelperTags(in dirtyRect: NSRect) {
        guard let presence = agentPresence else { return }
        for step in presence.currentSteps {
            guard let owner = step.owner, owner != AgentSession.mainAgentName,
                  let line = lineRect(forCharacterAt: step.location) else { continue }
            let tag = NSAttributedString(string: "● " + owner, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: Palette.accent
            ])
            let size = tag.size()
            let origin = NSPoint(x: line.maxX + 12, y: line.midY - size.height / 2)
            guard NSRect(origin: origin, size: size).intersects(dirtyRect) else { continue }
            tag.draw(at: origin)
        }
    }

    // MARK: - Geometry

    /// The rects of the glyphs in `range`, one per line fragment, in view coordinates.
    private func glyphRects(for range: NSRange) -> [NSRect] {
        guard let layoutManager, let textContainer, let storage = textStorage else { return [] }
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        guard clamped.length > 0 else { return [] }
        let glyphs = layoutManager.glyphRange(forCharacterRange: clamped, actualCharacterRange: nil)
        let origin = textContainerOrigin
        var rects: [NSRect] = []
        layoutManager.enumerateEnclosingRects(
            forGlyphRange: glyphs,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: textContainer
        ) { rect, _ in
            rects.append(rect.offsetBy(dx: origin.x, dy: origin.y))
        }
        return rects
    }

    private func unionRect(of rects: [NSRect]) -> NSRect? {
        guard var result = rects.first else { return nil }
        for rect in rects.dropFirst() {
            result = result.union(rect)
        }
        return result
    }

    /// A 2pt bar at `location`, as tall as the text line.
    private func caretRect(at location: Int) -> NSRect? {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let text = storage.mutableString
        let location = min(max(0, location), storage.length)
        // At the start of a line (or after its break), sit at the line's first character.
        if location == 0 || text.character(at: location - 1) == 10 {
            guard let line = lineRect(forCharacterAt: location) else { return nil }
            return NSRect(x: textContainerOrigin.x + CGFloat(effectiveGutter), y: line.minY, width: 2, height: line.height)
        }
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: location - 1, length: 1), actualCharacterRange: nil)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        return NSRect(x: glyphRect.maxX + 1, y: glyphRect.minY, width: 2, height: glyphRect.height)
    }
}
