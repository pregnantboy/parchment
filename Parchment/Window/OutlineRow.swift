import SwiftUI
import ParchmentCore

/// One heading in the outline popover.
struct OutlineRow: View {
    let heading: OutlineHeading
    let isCurrent: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(heading.title)
                .font(.system(size: 13, weight: heading.level == 1 ? .semibold : .regular))
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .padding(.leading, Double(max(heading.level - 1, 0)) * 14)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .background(background, in: .rect(cornerRadius: 8))
                .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(heading.title)
        .accessibilityValue(Text("Heading level \(heading.level)"))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    private var titleColor: Color {
        if isCurrent { return .parchmentAccent }
        return heading.level >= 3 ? .parchmentMuted : .parchmentInk
    }

    private var background: Color {
        if isCurrent { return Color.parchmentAccent.opacity(0.12) }
        return isHovering ? Color.parchmentInk.opacity(0.06) : .clear
    }
}
