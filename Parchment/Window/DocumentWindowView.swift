import SwiftUI

struct DocumentWindowView: View {
    let document: MarkdownDocument
    let fileURL: URL?

    @State private var controller = EditorController()
    @State private var windowWidth = 0.0
    @AppStorage(PreferenceKey.fontSize) private var fontSize = EditorMetrics.defaultFontSize
    @AppStorage(PreferenceKey.focusMode) private var isFocusMode = false
    @AppStorage(PreferenceKey.typewriterMode) private var isTypewriterMode = false
    @AppStorage(PreferenceKey.ornaments) private var ornaments = true
    @AppStorage(PreferenceKey.inkEffect) private var inkEffect = true
    @AppStorage(PreferenceKey.showsOutlineSidebar) private var showsOutlineSidebar = true

    init(document: MarkdownDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
    }

    var body: some View {
        @Bindable var controller = controller

        HStack(spacing: 0) {
            if showsSidebar {
                OutlineSidebar(controller: controller, ornaments: ornaments)
                    .frame(width: OutlineSidebar.width)
                Rectangle()
                    .fill(Color.parchmentRule)
                    .frame(width: 1)
                    .ignoresSafeArea()
            }
            editor
        }
        .onGeometryChange(for: Double.self) { proxy in
            Double(proxy.size.width)
        } action: { width in
            windowWidth = width
        }
        .onChange(of: isSidebarAvailable, initial: true) { _, isAvailable in
            controller.isOutlineSidebarAvailable = isAvailable
        }
        .background(Color.parchmentPaper.ignoresSafeArea())
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(outlineButtonTitle, systemImage: isSidebarAvailable ? "sidebar.left" : "list.bullet.indent") {
                    controller.toggleOutline()
                }
                .help(outlineButtonTitle)
                .popover(isPresented: $controller.isShowingOutline) {
                    OutlinePopover(controller: controller)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(
                    controller.isReading ? "Edit" : "Read",
                    systemImage: controller.isReading ? "pencil.line" : "book"
                ) {
                    controller.isReading.toggle()
                }
                .help(controller.isReading ? "Back to editing (\u{21E7}\u{2318}R)" : "Reading mode (\u{21E7}\u{2318}R)")
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .focusedSceneValue(\.editorController, controller)
    }

    private var editor: some View {
        EditorView(
            document: document,
            fileURL: fileURL,
            controller: controller,
            fontSize: fontSize,
            isFocusMode: isFocusMode,
            isTypewriterMode: isTypewriterMode,
            isReading: controller.isReading,
            ornaments: ornaments,
            inkEffect: inkEffect
        )
        .overlay(alignment: .top) {
            ProgressLine(progress: controller.scrollProgress)
        }
        .overlay(alignment: .bottom) {
            StatusPill(controller: controller, ornaments: ornaments)
                .padding(.bottom, 18)
        }
    }

    /// Room for the panel plus the full text column with some breathing space each side.
    private var isSidebarAvailable: Bool {
        let metrics = EditorMetrics(fontSize: fontSize)
        let needed = OutlineSidebar.width + 1 + metrics.gutter + metrics.measure + 96
        return windowWidth >= needed
    }

    private var showsSidebar: Bool {
        isSidebarAvailable && showsOutlineSidebar
    }

    private var outlineButtonTitle: String {
        if isSidebarAvailable {
            return showsOutlineSidebar ? "Hide Outline" : "Show Outline"
        }
        return "Outline"
    }
}
