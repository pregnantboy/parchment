import AppKit
import Observation
import ParchmentAgent

/// Follows Claude Code sessions through the events Parchment's hook drops into its inbox folder,
/// opens the plans they write, and tells each window which session is working on its file.
@Observable
final class AgentMonitor {
    static let shared = AgentMonitor()

    private(set) var sessions: [String: AgentSession] = [:]
    /// The session working on each followed file. Keys are standardized file URLs.
    private(set) var followers: [URL: String] = [:]
    /// Whether Parchment's hook is in Claude Code's settings.
    private(set) var isConnected = false

    /// The plan window Parchment opened by itself for each session, so a newer plan can replace it.
    @ObservationIgnored private var autoOpened: [String: URL] = [:]
    /// Files the user chose to stop following. Claude editing them again doesn't re-attach them;
    /// a new plan written to them does.
    @ObservationIgnored private var detached: Set<URL> = []
    @ObservationIgnored private var inboxWatcher: DirectoryWatcher?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let home = FileManager.default.homeDirectoryForCurrentUser

    private var inboxURL: URL { HookInstaller.inboxURL(home: home) }
    private var scriptURL: URL { HookInstaller.scriptURL(home: home) }
    /// Resolved, so a settings file that is a symlink into a dotfiles folder stays a symlink.
    private var settingsURL: URL { HookInstaller.settingsURL(home: home).resolvingSymlinksInPath() }
    private var memoryURL: URL { InstructionsInstaller.memoryURL(home: home).resolvingSymlinksInPath() }

    private init() {}

    // MARK: Lifecycle

    func start() {
        guard inboxWatcher == nil else { return }
        try? FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        refreshConnection()
        inboxWatcher = DirectoryWatcher(url: inboxURL) { [weak self] in
            self?.readInbox()
        }
        // A safety net in case a folder change notification is missed.
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                self?.readInbox()
            }
        }
        readInbox()
    }

    // MARK: Windows

    /// The session working on the file at `url`, if any.
    func session(following url: URL?) -> AgentSession? {
        guard let url else { return nil }
        return followers[url.standardizedFileURL].flatMap { sessions[$0] }
    }

    /// Detaches the file from its session, so its window becomes an ordinary, editable document.
    func stopFollowing(_ url: URL) {
        let url = url.standardizedFileURL
        followers[url] = nil
        detached.insert(url)
    }

    // MARK: Events

    private func readInbox() {
        let events = EventInbox(directory: inboxURL).drain()
        guard !events.isEmpty else { return }
        for event in events {
            handle(event)
        }
        pruneSessions(now: Date())
    }

    private func handle(_ event: AgentEvent) {
        var session = sessions[event.sessionID] ?? AgentSession(id: event.sessionID, date: event.date)
        let effects = session.apply(event)
        sessions[event.sessionID] = session

        for effect in effects {
            switch effect {
            case .planChanged(let path):
                openPlan(URL(fileURLWithPath: path).standardizedFileURL, sessionID: session.id)
            case .fileEdited(let path, _):
                // Claude editing a Markdown file the user already has open makes it followed too.
                let url = URL(fileURLWithPath: path).standardizedFileURL
                guard followers[url] == nil, !detached.contains(url), PlanFileRule.isMarkdown(path: path),
                      NSDocumentController.shared.document(for: url) != nil else { continue }
                followers[url] = session.id
            }
        }
    }

    /// Forgets sessions that ended an hour ago, or went quiet for half a day, unless a window
    /// still follows them.
    private func pruneSessions(now: Date) {
        let followed = Set(followers.values)
        for (id, session) in sessions where !followed.contains(id) {
            let quiet = now.timeIntervalSince(session.lastEventDate)
            if (session.status == .ended && quiet > 60 * 60) || quiet > 12 * 60 * 60 {
                sessions[id] = nil
                autoOpened[id] = nil
            }
        }
    }

    /// Opens the session's plan in the background, replacing the plan window Parchment opened
    /// for the same session earlier.
    private func openPlan(_ url: URL, sessionID: String) {
        let documents = NSDocumentController.shared
        detached.remove(url)
        followers[url] = sessionID

        if let previous = autoOpened[sessionID], previous != url {
            autoOpened[sessionID] = nil
            if followers[previous] == sessionID {
                followers[previous] = nil
            }
            if let document = documents.document(for: previous), !document.isDocumentEdited {
                document.close()
            }
        }
        guard documents.document(for: url) == nil else { return }
        autoOpened[sessionID] = url

        let wasActive = NSApp.isActive
        Task {
            _ = try? await documents.openDocument(withContentsOf: url, display: true)
            // Opened in the background (often right after `open -g` launched Parchment): close the
            // blank page Parchment starts with, so only the plan shows.
            if !wasActive {
                for document in documents.documents where document.fileURL == nil && !document.isDocumentEdited {
                    document.close()
                }
            }
        }
    }

    // MARK: Connecting to Claude Code

    func refreshConnection() {
        isConnected = HookInstaller.isInstalled(in: try? Data(contentsOf: settingsURL))
    }

    /// The JSON Parchment adds to Claude Code's settings, for showing before connecting.
    var hookPreview: String {
        let data = (try? HookInstaller.installing(into: nil, command: HookInstaller.command(scriptPath: scriptURL.path))) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    var settingsPath: String {
        (HookInstaller.settingsURL(home: home).path as NSString).abbreviatingWithTildeInPath
    }

    var memoryPath: String {
        (InstructionsInstaller.memoryURL(home: home).path as NSString).abbreviatingWithTildeInPath
    }

    /// Writes the hook script and adds it to `~/.claude/settings.json`, and adds the task-state
    /// instructions to `~/.claude/CLAUDE.md`, after saving a backup of each.
    func connect() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        try Data(HookInstaller.script.utf8).write(to: scriptURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let existing = try? Data(contentsOf: settingsURL)
        let updated = try HookInstaller.installing(into: existing, command: HookInstaller.command(scriptPath: scriptURL.path))
        try fileManager.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let existing {
            try existing.write(to: backupURL, options: .atomic)
        }
        try updated.write(to: settingsURL, options: .atomic)

        let memory = try? String(contentsOf: memoryURL, encoding: .utf8)
        if let memory {
            try Data(memory.utf8).write(to: memoryBackupURL, options: .atomic)
        }
        try Data(InstructionsInstaller.installing(into: memory).utf8).write(to: memoryURL, options: .atomic)
        refreshConnection()
    }

    /// Removes Parchment's hook from the settings and its block from `CLAUDE.md` (after saving a
    /// backup of each) and deletes the script.
    func disconnect() throws {
        if let existing = try? Data(contentsOf: settingsURL) {
            try existing.write(to: backupURL, options: .atomic)
            try HookInstaller.removing(from: existing).write(to: settingsURL, options: .atomic)
        }
        if let memory = try? String(contentsOf: memoryURL, encoding: .utf8), InstructionsInstaller.isInstalled(in: memory) {
            try Data(memory.utf8).write(to: memoryBackupURL, options: .atomic)
            try Data(InstructionsInstaller.removing(from: memory).utf8).write(to: memoryURL, options: .atomic)
        }
        try? FileManager.default.removeItem(at: scriptURL)
        refreshConnection()
    }

    private var memoryBackupURL: URL {
        memoryURL.deletingLastPathComponent().appendingPathComponent("CLAUDE.md.parchment-backup")
    }

    private var backupURL: URL {
        settingsURL.deletingLastPathComponent().appendingPathComponent("settings.json.parchment-backup")
    }
}
