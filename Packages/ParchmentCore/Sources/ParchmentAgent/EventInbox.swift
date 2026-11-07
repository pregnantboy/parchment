import Foundation

/// The folder the hook script drops one JSON file per event into.
///
/// The script writes each event to a hidden temp file in the same folder and renames it into
/// place, so a visible `*.json` file is always complete. Files are read in the order they were
/// created and deleted once read.
public struct EventInbox: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Reads, deletes and returns every pending event, oldest first. Events older than `maxAge`
    /// (left over from a crash or a quit mid-session) are deleted without being returned.
    public func drain(now: Date = Date(), maxAge: TimeInterval = 2 * 60 * 60) -> [AgentEvent] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.creationDateKey, .contentModificationDateKey]
        guard let urls = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else {
            return []
        }

        let files: [(url: URL, date: Date)] = urls.compactMap { url in
            let name = url.lastPathComponent
            guard !name.hasPrefix("."), url.pathExtension == "json" else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
            return (url, date)
        }
        .sorted { $0.date == $1.date ? $0.url.lastPathComponent < $1.url.lastPathComponent : $0.date < $1.date }

        var events: [AgentEvent] = []
        for file in files {
            let data = try? Data(contentsOf: file.url)
            try? fileManager.removeItem(at: file.url)
            guard let data, now.timeIntervalSince(file.date) <= maxAge,
                  let event = AgentEvent.decode(data, date: file.date) else { continue }
            events.append(event)
        }
        return events
    }
}
