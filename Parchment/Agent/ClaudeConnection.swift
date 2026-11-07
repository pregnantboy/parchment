import AppKit
import ParchmentAgent

/// The Connect and Disconnect dialogs. Each says exactly what changes before changing it.
enum ClaudeConnection {
    static func confirmConnect() {
        let monitor = AgentMonitor.shared
        let alert = NSAlert()
        alert.messageText = "Connect Parchment to Claude Code?"
        alert.informativeText = """
        Parchment will add the hook below to \(monitor.settingsPath), so Claude Code tells Parchment \
        which plan it is writing and what it is doing. Your other settings stay as they are, and a \
        backup is saved next to the file.

        Claude Code sessions that are already running need a restart to pick this up.
        """
        alert.accessoryView = codeView(monitor.hookPreview)
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try monitor.connect()
        } catch {
            showError(error, action: "connect to Claude Code")
        }
    }

    static func confirmDisconnect() {
        let monitor = AgentMonitor.shared
        let alert = NSAlert()
        alert.messageText = "Disconnect Parchment from Claude Code?"
        alert.informativeText = "Parchment will remove only its own hook from \(monitor.settingsPath). Plans already open stay open."
        alert.addButton(withTitle: "Disconnect")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try monitor.disconnect()
        } catch {
            showError(error, action: "disconnect from Claude Code")
        }
    }

    private static func showError(_ error: any Error, action: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Parchment couldn't \(action)."
        if let failure = error as? HookInstaller.Failure, failure == .unreadableSettings {
            alert.informativeText = "\(AgentMonitor.shared.settingsPath) isn't valid JSON, so Parchment left it alone. Fix the file and try again."
        } else {
            alert.informativeText = error.localizedDescription
        }
        alert.runModal()
    }

    /// A small read-only, scrollable code view for the alert.
    private static func codeView(_ text: String) -> NSView {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: 220))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        let textView = NSTextView(frame: scrollView.contentView.bounds)
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.string = text
        scrollView.documentView = textView
        return scrollView
    }
}
