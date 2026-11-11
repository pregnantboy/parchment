import ParchmentAgent
import SwiftUI

/// Replaces the word count pill while Claude follows the file: who is working, what they are
/// doing and for how long, and how far the plan is. A second line carries Claude's own words:
/// the sentence it is writing, or what its last message came down to. A light sweep runs across
/// the text while Claude works. The last few actions float above it and fade out.
/// Clicking the pill opens the timeline of everything Claude has done.
struct AgentPill: View {
    let status: PlanStatus
    @Binding var isShowingActivity: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// An activity shorter than this shows no timer: most tool calls are over in a moment.
    private static let timerAfter: TimeInterval = 10

    var body: some View {
        VStack(spacing: 8) {
            ActivityTicker(actions: status.session.recentActions)
            Button {
                isShowingActivity.toggle()
            } label: {
                // Ticks so the timer counts up and "Last update 6 min ago" appears without new events.
                TimelineView(.periodic(from: .now, by: status.isWorking ? 1 : 30)) { context in
                    pill(at: context.date)
                }
            }
            .buttonStyle(.plain)
            .help("Show what Claude has done (\u{21E7}\u{2318}A)")
            .popover(isPresented: $isShowingActivity, arrowEdge: .top) {
                AgentTimeline(status: status)
            }
        }
    }

    private func pill(at date: Date) -> some View {
        let shimmers = status.isWorking && !status.isStale(at: date) && !reduceMotion
        let headline = status.headline(at: date)
        let text = label(headline, at: date)
        return VStack(spacing: 2) {
            text.overlay {
                if shimmers {
                    ShimmerBand().mask(text)
                }
            }
            if let detail = headline.detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.parchmentMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .modifier(CappedWidth(limit: 520))
        // The bar takes the text's width, so it never stretches the pill.
        .padding(.bottom, hasBar ? 7 : 0)
        .overlay(alignment: .bottom) {
            if hasBar {
                SegmentedProgressBar(progress: status.progress)
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, headline.detail == nil && !hasBar ? 14 : 18)
        .padding(.vertical, 7)
        .clearGlass(in: .capsule)
        .contentShape(.capsule)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows what Claude has done")
    }

    private var hasBar: Bool { !status.progress.segments.isEmpty }

    private func label(_ headline: SessionHeadline, at date: Date) -> some View {
        HStack(spacing: 8) {
            Text(status.who)
                .fontWeight(.semibold)
            Text(headline.title)
                .lineLimit(1)
                .truncationMode(.middle)
            if let since = headline.since, date.timeIntervalSince(since) >= Self.timerAfter {
                Text(ElapsedText.short(date.timeIntervalSince(since)))
                    .monospacedDigit()
                    .opacity(0.7)
            }
            if let progress = status.progressText {
                Text(progress)
                    .monospacedDigit()
                    .opacity(0.7)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.parchmentInk)
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
        .clearGlass(in: .capsule)
        .opacity(min(1, max(0, (Self.lifetime - age) / Self.fade)))
        .transition(.opacity)
    }
}
