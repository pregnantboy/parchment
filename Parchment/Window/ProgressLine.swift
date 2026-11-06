import SwiftUI

/// A 3pt accent bar along the top edge whose width follows the scroll position.
struct ProgressLine: View {
    let progress: Double

    var body: some View {
        Rectangle()
            .fill(Color.parchmentAccent)
            .frame(height: 3)
            .scaleEffect(x: max(progress, 0.001), y: 1, anchor: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(progress > 0 ? 1 : 0)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}
