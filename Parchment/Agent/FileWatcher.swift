import Foundation

/// Calls `onChange` when the file at `url` changes on disk.
///
/// Many programs save by writing a new file and renaming it over the old one. The watched file
/// is then gone, so the watcher waits briefly and starts watching whatever is at the path now.
final class FileWatcher {
    let url: URL
    private let onChange: () -> Void
    private var source: (any DispatchSourceFileSystemObject)?
    private var retryTask: Task<Void, Never>?
    private var isStopped = false

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start()
    }

    func stop() {
        isStopped = true
        retryTask?.cancel()
        retryTask = nil
        source?.cancel()
        source = nil
    }

    private func start() {
        guard !isStopped else { return }
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            scheduleRetry(attempt: 1)
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.handleEvent()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        self.source = source
        source.resume()
    }

    private func handleEvent() {
        guard let source else { return }
        let events = source.data
        if !events.isDisjoint(with: [.delete, .rename, .revoke]) {
            source.cancel()
            self.source = nil
            scheduleRetry(attempt: 1)
            return
        }
        onChange()
    }

    /// Re-opens the path after an atomic save. Retries quickly at first, then every two seconds
    /// while the file is missing.
    private func scheduleRetry(attempt: Int) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: attempt < 20 ? .milliseconds(100) : .seconds(2))
            guard !Task.isCancelled, let self, !self.isStopped else { return }
            if FileManager.default.fileExists(atPath: self.url.path) {
                self.start()
                self.onChange()
            } else {
                self.scheduleRetry(attempt: attempt + 1)
            }
        }
    }
}
