import Combine
import SwiftUI
import UniformTypeIdentifiers

/// A Markdown file on disk.
///
/// This is a reference type (`ReferenceFileDocument`) on purpose. The `NSTextView`
/// owns undo and registers its own undo actions with the window's undo manager.
/// A value-type `FileDocument` would make SwiftUI register an extra undo action for
/// every keystroke, which would fight with the text view. With a reference document
/// SwiftUI only marks the document dirty from the text view's undo registrations.
///
/// The text is read and written from background save work, so it is guarded by a lock.
nonisolated final class MarkdownDocument: ReferenceFileDocument, @unchecked Sendable {
    static var readableContentTypes: [UTType] { [.markdownText, .plainText] }
    static var writableContentTypes: [UTType] { [.markdownText, .plainText] }

    private let lock = NSLock()
    private var storage: String

    var text: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storage = newValue
        }
    }

    init(text: String = "") {
        storage = text
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let encodings: [String.Encoding] = [.utf8, .utf16, .windowsCP1252, .isoLatin1, .macOSRoman]
        for encoding in encodings {
            if let decoded = String(data: data, encoding: encoding) {
                storage = decoded
                return
            }
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    func snapshot(contentType: UTType) throws -> String {
        text
    }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }
}
