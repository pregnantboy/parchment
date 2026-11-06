import SwiftUI

@main
struct ParchmentApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { MarkdownDocument() }) { configuration in
            DocumentWindowView(document: configuration.document, fileURL: configuration.fileURL)
        }
        .commands {
            ParchmentCommands()
        }
        .defaultSize(width: 980, height: 820)
    }
}
