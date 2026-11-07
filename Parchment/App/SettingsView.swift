import SwiftUI

/// Parchment > Settings (⌘,): switches for the decorative effects.
struct SettingsView: View {
    @AppStorage(PreferenceKey.inkEffect) private var inkEffect = true
    @AppStorage(PreferenceKey.ornaments) private var ornaments = true

    var body: some View {
        Form {
            Section("Effects") {
                Toggle(isOn: $inkEffect) {
                    Text("Ink bleeds as you type")
                    Text("New letters land as wet ink and settle. Off while Reduce Motion is on.")
                }
                Toggle(isOn: $ornaments) {
                    Text("Ornaments")
                    Text("Wax-seal checkboxes, filigree rules, a large first letter, quote marks and diamond bullets.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
