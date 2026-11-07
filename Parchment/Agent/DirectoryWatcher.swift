import Foundation

/// Calls `onChange` when files are added to, removed from, or renamed in a folder.
final class DirectoryWatcher {
    private let onChange: () -> Void
    private var source: (any DispatchSourceFileSystemObject)?

    init(url: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.onChange()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
