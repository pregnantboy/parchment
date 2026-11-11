import SwiftUI
import ParchmentCore

/// Word count and reading time, shown at the bottom center of the window.
struct StatusPill: View {
    let controller: EditorController
    /// Adds a small scroll before the count.
    let ornaments: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .font(.system(size: 12, design: .serif))
            .foregroundStyle(Color.parchmentInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
            .opacity(isVisible ? 1 : 0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: isVisible)
            .accessibilityElement(children: .combine)
            .accessibilityHidden(!isVisible)
            .allowsHitTesting(false)
    }

    private var isVisible: Bool {
        controller.stats.words > 0 && !controller.isTyping
    }

    @ViewBuilder
    private var content: some View {
        if let selection = controller.selectionStats {
            Text("\(selection.words.formatted()) of \(wordsText(controller.stats.words))")
                .fontWeight(.semibold)
        } else {
            HStack(spacing: 8) {
                if ornaments {
                    Image(systemName: controller.isReading ? "book" : "scroll")
                        .imageScale(.small)
                        .opacity(0.8)
                        .accessibilityHidden(true)
                }
                Text(wordsText(controller.stats.words))
                    .fontWeight(.semibold)
                Text("\(controller.stats.readingMinutes.formatted()) min read")
                    .opacity(0.7)
            }
        }
    }

    private func wordsText(_ count: Int) -> String {
        count == 1 ? "1 word" : "\(count.formatted()) words"
    }
}
