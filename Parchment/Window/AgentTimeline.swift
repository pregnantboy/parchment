import ParchmentAgent
import SwiftUI

/// The story of a Claude session, opened from the status pill: what you asked, what Claude said
/// in its own words, each action with how long it took and whether it worked, and what each
/// helper was sent to do and reported back.
struct AgentTimeline: View {
    let status: PlanStatus

    private var session: AgentSession { status.session }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if session.timeline.isEmpty {
                Text("Nothing yet. Actions appear here as Claude works.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.parchmentMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 9) {
                        ForEach(session.timeline) { entry in
                            TimelineRow(entry: entry)
                        }
                    }
                    .padding(14)
                }
                // Stays at the newest line as lines are added.
                .defaultScrollAnchor(.bottom)
            }
        }
        .frame(width: 400, height: 460)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(status.who)
                    .font(.system(size: 13, weight: .semibold))
                if let project = status.projectName {
                    Text("in \(project)")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.parchmentMuted)
                }
                Spacer()
                if let progress = status.progressText {
                    Text(progress)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Color.parchmentMuted)
                }
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                summary(at: context.date)
            }
            if let prompt = session.prompt {
                labeled("You asked", prompt)
            }
            ForEach(session.helpers) { helper in
                HelperRow(helper: helper)
            }
        }
        .padding(14)
        .foregroundStyle(Color.parchmentInk)
    }

    /// The headline, then "Working for 3m 05s · 4 files edited · 6 commands · 1 failed".
    private func summary(at date: Date) -> some View {
        let headline = status.headline(at: date)
        var parts: [String] = []
        if status.isWorking {
            parts.append("Working for \(ElapsedText.short(date.timeIntervalSince(session.turn.start)))")
        }
        if let turn = session.turn.text {
            parts.append(turn)
        }
        return VStack(alignment: .leading, spacing: 3) {
            Text(headline.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
            if let detail = headline.detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.parchmentMuted)
                    .lineLimit(3)
            }
            if !parts.isEmpty {
                Text(parts.joined(separator: " · "))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(Color.parchmentMuted)
            }
        }
    }

    private func labeled(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(Color.parchmentMuted)
            Text(text)
                .font(.system(size: 12))
                .lineLimit(3)
                .textSelection(.enabled)
        }
    }
}

/// One helper at work: its name, what it was sent to do, what it is doing, and for how long.
private struct HelperRow: View {
    let helper: AgentSession.Helper

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "person.2")
                .font(.system(size: 10))
                .foregroundStyle(Color.parchmentAccent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(helper.task.map { "\(helper.name): \($0)" } ?? helper.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(helper.activity ?? helper.narration ?? "Thinking")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.parchmentMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            ElapsedLabel(since: helper.startDate)
        }
    }
}

/// One line of the timeline.
private struct TimelineRow: View {
    let entry: AgentSession.TimelineEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            icon
                .frame(width: 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                text
                if let detail = entry.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(isFailure ? Color.parchmentAccent : Color.parchmentMuted)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .accessibilityElement(children: .combine)
    }

    private var isFailure: Bool {
        entry.kind == .action(.failed) || entry.kind == .failed
    }

    private var isHelper: Bool {
        entry.owner != AgentSession.mainAgentName && entry.owner != "You"
    }

    @ViewBuilder
    private var text: some View {
        switch entry.kind {
        case .prompt:
            Text(entry.text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.parchmentInk)
                .lineLimit(4)
                .textSelection(.enabled)
        case .said:
            // Claude's words, set like the document. Inline Markdown (bold, code) is styled.
            Text(Self.styled(entry.text))
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(Color.parchmentInk)
                .lineLimit(8)
                .textSelection(.enabled)
        default:
            Text(isHelper && !entry.text.hasPrefix(entry.owner) ? "\(entry.owner): \(entry.text)" : entry.text)
                .font(.system(size: 12))
                .foregroundStyle(isFailure ? Color.parchmentAccent : Color.parchmentMuted)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch entry.kind {
        case .prompt: symbol("person.fill", color: .parchmentInk)
        case .said: symbol("quote.opening", color: .parchmentAccent)
        case .action(.running): ProgressView().controlSize(.mini)
        case .action(.succeeded): symbol("checkmark", color: .parchmentMuted)
        case .action(.failed): symbol("xmark", color: .parchmentAccent, label: "failed")
        case .helperStarted, .helperFinished: symbol("person.2", color: .parchmentMuted)
        case .asked: symbol("hand.raised", color: .parchmentAccent)
        case .finished: symbol("flag.checkered", color: .parchmentInk)
        case .failed: symbol("exclamationmark.triangle", color: .parchmentAccent)
        }
    }

    private func symbol(_ name: String, color: Color, label: String? = nil) -> some View {
        Image(systemName: name)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .accessibilityLabel(label ?? "")
    }

    /// How long it took, a running timer, or the time of day for your messages.
    @ViewBuilder
    private var trailing: some View {
        if entry.kind == .action(.running) {
            ElapsedLabel(since: entry.date)
        } else if let duration = entry.duration, duration >= 1 {
            Text(ElapsedText.short(duration))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Color.parchmentMuted)
        } else if entry.kind == .prompt {
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Color.parchmentMuted)
        }
    }

    private static func styled(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// A timer that counts up from `since`: "42s", "3m 05s".
private struct ElapsedLabel: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(ElapsedText.short(context.date.timeIntervalSince(since)))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Color.parchmentMuted)
        }
    }
}
