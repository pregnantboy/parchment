import SwiftUI

/// The outline as a panel on the left, shown when the window is wide enough.
struct OutlineSidebar: View {
    static let width = 248.0

    let controller: EditorController
    let ornaments: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Contents")
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .textCase(.uppercase)
                    .tracking(1.6)
                    .foregroundStyle(Color.parchmentMuted)
                if ornaments {
                    FlourishShape()
                        .fill(Color.parchmentAccent.opacity(0.7))
                        .frame(width: 120, height: 7)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)

            if controller.headings.isEmpty {
                Text("Start a line with # to add a heading.")
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Color.parchmentMuted)
                    .padding(.horizontal, 20)
                Spacer(minLength: 0)
            } else {
                let currentID = controller.currentHeadingID
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(controller.headings) { heading in
                                OutlineRow(heading: heading, isCurrent: heading.id == currentID) {
                                    controller.reveal(heading)
                                }
                                .id(heading.id)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 16)
                    }
                    .scrollIndicators(.automatic)
                    .onChange(of: currentID) { _, id in
                        guard let id else { return }
                        proxy.scrollTo(id)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.parchmentSidebar.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Outline")
    }
}

/// The filigree used for rules, drawn as a SwiftUI shape.
struct FlourishShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(OrnamentPath.flourish(in: rect))
    }
}
