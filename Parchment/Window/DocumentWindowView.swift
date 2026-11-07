import SwiftUI

struct DocumentWindowView: View {
    let document: MarkdownDocument
    let fileURL: URL?

    @State private var controller = EditorController()
    @AppStorage(PreferenceKey.fontSize) private var fontSize = EditorMetrics.defaultFontSize
    @AppStorage(PreferenceKey.focusMode) private var isFocusMode = false
    @AppStorage(PreferenceKey.typewriterMode) private var isTypewriterMode = false
    @AppStorage(PreferenceKey.followClaude) private var followsClaude = true

    init(document: MarkdownDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
    }

    /// Set while a Claude Code session is working on this file.
    private var planStatus: PlanStatus? {
        guard let session = AgentMonitor.shared.session(following: fileURL) else { return nil }
        return PlanStatus(session: session, steps: controller.planSteps, lastEdit: controller.lastExternalEdit)
    }

    var body: some View {
        @Bindable var controller = controller
        let status = planStatus

        EditorView(
            document: document,
            fileURL: fileURL,
            controller: controller,
            isReadOnly: status?.isReadOnly ?? false,
            agent: status.map { AgentPresence(status: $0, steps: controller.planSteps, follows: followsClaude) },
            fontSize: fontSize,
            isFocusMode: isFocusMode,
            isTypewriterMode: isTypewriterMode
        )
        .overlay(alignment: .top) {
            if let status {
                ProgressLine(progress: status.lineFraction, glints: status.isWorking)
            } else {
                ProgressLine(progress: controller.scrollProgress)
            }
        }
        .overlay(alignment: .bottom) {
            Group {
                if let status {
                    AgentPill(status: status)
                } else {
                    StatusPill(controller: controller)
                }
            }
            .padding(.bottom, 18)
        }
        .background(Color.parchmentPaper.ignoresSafeArea())
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Outline", systemImage: "list.bullet.indent") {
                    controller.isShowingOutline.toggle()
                }
                .popover(isPresented: $controller.isShowingOutline) {
                    OutlinePopover(controller: controller)
                }
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .focusedSceneValue(\.editorController, controller)
        .task(id: fileURL) {
            controller.fileURL = fileURL
        }
    }
}
