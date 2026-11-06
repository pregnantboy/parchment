import UniformTypeIdentifiers

nonisolated extension UTType {
    /// Markdown, imported through the app's Info.plist (`net.daringfireball.markdown`).
    static let markdownText = UTType(importedAs: "net.daringfireball.markdown")
}
