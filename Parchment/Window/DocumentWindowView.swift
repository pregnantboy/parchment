import SwiftUI

struct DocumentWindowView: View {
    let document: MarkdownDocument
    let fileURL: URL?

    @State private var controller = EditorController()
    @AppStorage(PreferenceKey.fontSize) private var fontSize = EditorMetrics.defaultFontSize
    @AppStorage(PreferenceKey.focusMode) private var isFocusMode = false
    @AppStorage(PreferenceKey.typewriterMode) private var isTypewriterMode = false

    init(document: MarkdownDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
    }

    var body: some View {
        @Bindable var controller = controller

        EditorView(
            document: document,
            fileURL: fileURL,
            controller: controller,
            fontSize: fontSize,
            isFocusMode: isFocusMode,
            isTypewriterMode: isTypewriterMode
        )
        .overlay(alignment: .top) {
            ProgressLine(progress: controller.scrollProgress)
        }
        .overlay(alignment: .bottom) {
            StatusPill(controller: controller)
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
    }
}
