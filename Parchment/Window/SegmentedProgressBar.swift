import ParchmentAgent
import SwiftUI

/// The plan's progress as a row of pieces, one per top-level task (or todo, or step).
/// A piece fills as its sub-steps are ticked, is part filled while Claude works on it, and is
/// drawn dark when it is blocked. A soft glint runs along the bar while Claude works.
struct SegmentedProgressBar: View {
    let progress: PlanProgress
    var glints = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let glintPeriod = 2.4
    private static let glintWidth: CGFloat = 80

    var body: some View {
        bar
            .overlay {
                if glints && !reduceMotion {
                    glint.mask(bar)
                }
            }
            // Progress guessed from where Claude is editing is drawn fainter.
            .opacity(progress.isEstimate ? 0.55 : 1)
            .accessibilityElement()
            .accessibilityLabel("Plan progress")
            .accessibilityValue(progress.percentText ?? "")
            .allowsHitTesting(false)
    }

    private var bar: some View {
        let segments = progress.segments
        return Canvas { context, size in
            guard !segments.isEmpty else { return }
            let count = CGFloat(segments.count)
            // Gaps shrink, then vanish, as a long plan squeezes the pieces.
            let gap = segments.count > 1 ? min(2, size.width / count * 0.2) : 0
            let width = (size.width - gap * (count - 1)) / count
            let radius = min(size.height, width) / 2

            for (index, segment) in segments.enumerated() {
                let x = CGFloat(index) * (width + gap)
                let whole = CGRect(x: x, y: 0, width: width, height: size.height)
                context.fill(Path(roundedRect: whole, cornerRadius: radius), with: .color(Color.parchmentInk.opacity(0.14)))
                if segment.state == .blocked {
                    context.fill(Path(roundedRect: whole, cornerRadius: radius), with: .color(Color.parchmentInk.opacity(0.5)))
                }
                let fill = min(max(segment.fill, 0), 1)
                guard fill > 0 else { continue }
                // Clipped to the piece, so a part fill keeps the piece's rounded end.
                var layer = context
                layer.clip(to: Path(roundedRect: whole, cornerRadius: radius))
                layer.fill(Path(CGRect(x: x, y: 0, width: width * fill, height: size.height)), with: .color(Color.parchmentAccent))
            }
        }
    }

    private var glint: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            GeometryReader { geometry in
                let width = geometry.size.width
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.glintPeriod) / Self.glintPeriod
                LinearGradient(
                    colors: [.clear, .white.opacity(0.7), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: Self.glintWidth)
                .offset(x: -Self.glintWidth + (width + Self.glintWidth) * phase)
            }
        }
        .accessibilityHidden(true)
    }
}
