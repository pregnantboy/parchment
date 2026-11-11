import SwiftUI

extension View {
    /// Clear Liquid Glass in `shape`, over a faint wash of paper so text set on the glass stays
    /// readable above the page's own text.
    func clearGlass<S: Shape>(in shape: S) -> some View {
        background(Color.parchmentPaper.opacity(0.25), in: shape)
            .glassEffect(.clear, in: shape)
    }
}
