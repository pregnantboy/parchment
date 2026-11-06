import SwiftUI

struct ParchmentCommands: Commands {
    @FocusedValue(\.editorController) private var editor
    @AppStorage(PreferenceKey.fontSize) private var fontSize = EditorMetrics.defaultFontSize
    @AppStorage(PreferenceKey.focusMode) private var isFocusMode = false
    @AppStorage(PreferenceKey.typewriterMode) private var isTypewriterMode = false

    var body: some Commands {
        CommandMenu("Format") {
            Group {
            Button("Bold") { editor?.perform(.bold) }
                .keyboardShortcut("b", modifiers: .command)
            Button("Italic") { editor?.perform(.italic) }
                .keyboardShortcut("i", modifiers: .command)
            Button("Strikethrough") { editor?.perform(.strikethrough) }
                .keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Inline Code") { editor?.perform(.inlineCode) }
                .keyboardShortcut("c", modifiers: [.command, .option])
            Button("Link") { editor?.perform(.link) }
                .keyboardShortcut("k", modifiers: .command)

            Divider()

            Menu("Heading") {
                Button("Body") { editor?.perform(.heading(0)) }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Heading 1") { editor?.perform(.heading(1)) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Heading 2") { editor?.perform(.heading(2)) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Heading 3") { editor?.perform(.heading(3)) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Heading 4") { editor?.perform(.heading(4)) }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Heading 5") { editor?.perform(.heading(5)) }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Heading 6") { editor?.perform(.heading(6)) }
                    .keyboardShortcut("6", modifiers: .command)
            }

            Divider()

            Button("Toggle Task") { editor?.perform(.task) }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Indent") { editor?.perform(.indent) }
                .keyboardShortcut("]", modifiers: .command)
            Button("Outdent") { editor?.perform(.outdent) }
                .keyboardShortcut("[", modifiers: .command)
            }
            .disabled(editor == nil)
        }

        CommandGroup(after: .toolbar) {
            Toggle("Focus Mode", isOn: $isFocusMode)
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Toggle("Typewriter Mode", isOn: $isTypewriterMode)
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Show Outline") { editor?.isShowingOutline.toggle() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(editor == nil)

            Divider()

            Button("Bigger") { fontSize = min(fontSize + 1, EditorMetrics.fontSizeRange.upperBound) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Smaller") { fontSize = max(fontSize - 1, EditorMetrics.fontSizeRange.lowerBound) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { fontSize = EditorMetrics.defaultFontSize }
                .keyboardShortcut("0", modifiers: [.command, .option])
        }
    }
}
