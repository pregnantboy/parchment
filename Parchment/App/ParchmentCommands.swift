import SwiftUI

struct ParchmentCommands: Commands {
    @FocusedValue(\.editorController) private var editor
    @AppStorage(PreferenceKey.fontSize) private var fontSize = EditorMetrics.defaultFontSize
    @AppStorage(PreferenceKey.focusMode) private var isFocusMode = false
    @AppStorage(PreferenceKey.typewriterMode) private var isTypewriterMode = false
    @AppStorage(PreferenceKey.followClaude) private var followsClaude = true

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            ClaudeConnectionMenuItem()
        }

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

            Toggle("Follow Claude", isOn: $followsClaude)
            Button("Stop Following Claude") { editor?.stopFollowingClaude() }
                .disabled(editor?.isFollowedByClaude != true)

            Divider()

            Button("Bigger") { fontSize = min(fontSize + 1, EditorMetrics.fontSizeRange.upperBound) }
                .keyboardShortcut("+", modifiers: .command)
            // ⌘= without Shift, as in other Mac apps; hidden so the menu shows one Bigger item.
            Button("Bigger") { fontSize = min(fontSize + 1, EditorMetrics.fontSizeRange.upperBound) }
                .keyboardShortcut("=", modifiers: .command)
                .hidden()
            Button("Smaller") { fontSize = max(fontSize - 1, EditorMetrics.fontSizeRange.lowerBound) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { fontSize = EditorMetrics.defaultFontSize }
                .keyboardShortcut("0", modifiers: [.command, .option])
        }
    }
}

/// "Connect to Claude Code…" or "Disconnect from Claude Code…", whichever applies.
private struct ClaudeConnectionMenuItem: View {
    var body: some View {
        if AgentMonitor.shared.isConnected {
            Button("Disconnect from Claude Code…") { ClaudeConnection.confirmDisconnect() }
        } else {
            Button("Connect to Claude Code…") { ClaudeConnection.confirmConnect() }
        }
    }
}
