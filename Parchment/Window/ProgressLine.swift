import SwiftUI

/// A 3pt accent bar along the top edge. Its width follows the scroll position, or the plan's
/// progress while Claude follows the file; then a soft glint runs along it while Claude works.
struct ProgressLine: View {
    let progress: Double
    var glints = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let glintPeriod = 2.4
    private static let glintWidth: CGFloat = 80

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * max(progress, 0.001)
            Rectangle()
                .fill(Color.parchmentAccent)
                .frame(width: width, height: 3)
                .overlay(alignment: .leading) {
                    if glints && !reduceMotion {
                        glint(across: width)
                    }
                }
                .clipped()
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: progress)
        }
        .frame(height: 3)
        .opacity(progress > 0 ? 1 : 0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func glint(across width: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.glintPeriod) / Self.glintPeriod
            LinearGradient(
                colors: [.clear, .white.opacity(0.75), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: Self.glintWidth, height: 3)
            .offset(x: -Self.glintWidth + (width + Self.glintWidth) * phase)
        }
    }
}
