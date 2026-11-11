import SwiftUI

/// Parchment > Settings (⌘,): text size, line spacing, decorative effects and the Claude Code connection.
struct SettingsView: View {
    @AppStorage(PreferenceKey.fontSize) private var fontSize = EditorMetrics.defaultFontSize
    @AppStorage(PreferenceKey.lineHeight) private var lineHeight = EditorMetrics.defaultLineHeight
    @AppStorage(PreferenceKey.inkEffect) private var inkEffect = true
    @AppStorage(PreferenceKey.ornaments) private var ornaments = true

    var body: some View {
        Form {
            Section("Text") {
                LabeledContent("Text size") {
                    HStack {
                        Slider(value: $fontSize, in: EditorMetrics.fontSizeRange, step: 1)
                        Text("\(Int(fontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                LabeledContent("Line spacing") {
                    HStack {
                        Slider(value: $lineHeight, in: EditorMetrics.lineHeightRange, step: 0.1)
                        Text(lineHeight, format: .number.precision(.fractionLength(1)))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                HStack {
                    Spacer()
                    Button("Restore Defaults") {
                        fontSize = EditorMetrics.defaultFontSize
                        lineHeight = EditorMetrics.defaultLineHeight
                    }
                    .disabled(fontSize == EditorMetrics.defaultFontSize && lineHeight == EditorMetrics.defaultLineHeight)
                }
            }
            Section("Effects") {
                Toggle(isOn: $inkEffect) {
                    Text("Ink bleeds as you type")
                    Text("New letters land as wet ink and settle. Off while Reduce Motion is on.")
                }
                Toggle(isOn: $ornaments) {
                    Text("Ornaments")
                    Text("Wax-seal checkboxes, filigree rules, quote marks and diamond bullets.")
                }
            }
            Section("Claude Code") {
                ClaudeConnectionRow()
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Whether Parchment is connected to Claude Code, with a button to connect or disconnect.
private struct ClaudeConnectionRow: View {
    var body: some View {
        let isConnected = AgentMonitor.shared.isConnected
        let needsUpdate = AgentMonitor.shared.needsUpdate
        LabeledContent {
            if isConnected {
                if needsUpdate {
                    Button("Update…") { ClaudeConnection.confirmConnect(isUpdate: true) }
                }
                Button("Disconnect…") { ClaudeConnection.confirmDisconnect() }
            } else {
                Button("Connect…") { ClaudeConnection.confirmConnect() }
            }
        } label: {
            Text(isConnected ? (needsUpdate ? "Connected, update available" : "Connected") : "Not connected")
            Text(needsUpdate
                ? "Update the hook so Parchment can show what Claude says, what it asks permission for, and why it stopped."
                : "Lets Parchment follow the plans Claude Code writes and show what it is doing.")
        }
    }
}
