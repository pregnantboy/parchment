import ParchmentAgent
import SwiftUI

/// Replaces the word count pill while Claude follows the file: who is working, what they are
/// doing, and how far the plan is. A light sweep runs across the text while Claude works.
/// The last few actions float above it and fade out.
struct AgentPill: View {
    let status: PlanStatus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            ActivityTicker(actions: status.session.recentActions)
            // Ticks so "Last update 6 min ago" appears and counts up without new events.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                pill(at: context.date)
            }
        }
    }

    private func pill(at date: Date) -> some View {
        let shimmers = status.isWorking && !status.isStale(at: date) && !reduceMotion
        let text = label(at: date)
        return text
            .overlay {
                if shimmers {
                    ShimmerBand().mask(text)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
            .accessibilityElement(children: .combine)
            .allowsHitTesting(false)
    }

    private func label(at date: Date) -> some View {
        HStack(spacing: 8) {
            Text(status.who)
                .fontWeight(.semibold)
            Text(status.headline(at: date))
                .lineLimit(1)
                .truncationMode(.middle)
            if let progress = status.progressText {
                Text(progress)
                    .monospacedDigit()
                    .opacity(0.7)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.parchmentInk)
        .modifier(CappedWidth(limit: 520))
    }
}

/// Lets a view hug its content but never grow past `limit`. A plain `.frame(maxWidth:)`
/// would stretch the pill to the full limit even for short text.
private struct CappedWidth: ViewModifier {
    let limit: CGFloat

    func body(content: Content) -> some View {
        CappedWidthLayout(limit: limit) { content }
    }
}

private struct CappedWidthLayout: Layout {
    let limit: CGFloat

    private func capped(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: min(proposal.width ?? limit, limit), height: proposal.height)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(capped(proposal)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: capped(proposal))
    }
}

/// A vermilion band that sweeps left to right every 2.2 seconds.
private struct ShimmerBand: View {
    private static let period = 2.2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            GeometryReader { geometry in
                let width = geometry.size.width
                let band = max(48, width * 0.35)
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.period) / Self.period
                LinearGradient(
                    colors: [.clear, Color.parchmentAccent, .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: band)
                .offset(x: -band + (width + band) * phase)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The last few finished actions ("Edited StatusPill.swift ✓"), each fading out after 8 seconds.
private struct ActivityTicker: View {
    let actions: [AgentSession.RecentAction]

    private static let lifetime: TimeInterval = 8
    private static let fade: TimeInterval = 2

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let visible = actions.filter { context.date.timeIntervalSince($0.date) < Self.lifetime }
            VStack(spacing: 4) {
                ForEach(visible) { action in
                    row(action, age: context.date.timeIntervalSince(action.date))
                }
            }
            .animation(.easeOut(duration: 0.4), value: visible.map(\.id))
        }
        .allowsHitTesting(false)
    }

    private func row(_ action: AgentSession.RecentAction, age: TimeInterval) -> some View {
        HStack(spacing: 5) {
            Text(action.text)
                .lineLimit(1)
            Image(systemName: action.succeeded ? "checkmark" : "xmark")
                .font(.system(size: 9, weight: .bold))
                .accessibilityLabel(action.succeeded ? "succeeded" : "failed")
        }
        .font(.system(size: 11))
        .foregroundStyle(action.succeeded ? Color.parchmentMuted : Color.parchmentAccent)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .glassEffect(.regular, in: .capsule)
        .opacity(min(1, max(0, (Self.lifetime - age) / Self.fade)))
        .transition(.opacity)
    }
}
