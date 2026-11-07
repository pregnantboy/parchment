import SwiftUI

/// The document outline shown from the toolbar button.
struct OutlinePopover: View {
    let controller: EditorController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Outline")
                    .font(.system(.headline, design: .serif))
                Spacer()
                Text("\u{21E7}\u{2318}O")
                    .font(.caption)
                    .foregroundStyle(Color.parchmentMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if controller.headings.isEmpty {
                ContentUnavailableView(
                    "No Headings",
                    systemImage: "list.bullet.indent",
                    description: Text("Start a line with # to add a heading.")
                )
                .frame(height: 200)
            } else {
                let currentID = controller.currentHeadingID
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(controller.headings) { heading in
                            OutlineRow(heading: heading, isCurrent: heading.id == currentID) {
                                controller.reveal(heading)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 360)
            }
        }
        .frame(width: 300)
        .frame(maxHeight: 420)
    }
}
