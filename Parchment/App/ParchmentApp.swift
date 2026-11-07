import SwiftUI

@main
struct ParchmentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // With iCloud Drive on, document apps open the Open panel at launch. Turning this
        // AppKit default off makes Parchment start on a blank page instead. Windows macOS
        // restores from last time still come back as usual.
        UserDefaults.standard.register(defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false])
    }

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
