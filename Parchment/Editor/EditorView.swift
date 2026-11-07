import SwiftUI

/// The live-styled Markdown editor, hosting `ParchmentTextView` in a scroll view.
struct EditorView: NSViewRepresentable {
    let document: MarkdownDocument
    let fileURL: URL?
    let controller: EditorController
    let fontSize: Double
    let isFocusMode: Bool
    let isTypewriterMode: Bool
    let isReading: Bool
    let ornaments: Bool
    let inkEffect: Bool

    func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(
            document: document,
            controller: controller,
            metrics: EditorCoordinator.metrics(forFontSize: fontSize)
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScrollView(from: self, undoManager: context.environment.undoManager)
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.update(from: self, undoManager: context.environment.undoManager)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: EditorCoordinator) {
        coordinator.tearDown()
    }
}
