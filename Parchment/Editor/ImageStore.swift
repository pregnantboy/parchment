import AppKit

/// Loads and caches the images shown below `![alt](source)` lines.
///
/// Local files and web images both load through `URLSession`, which handles `file://` URLs too.
/// Failures are remembered so a broken link isn't refetched on every keystroke.
@MainActor
final class ImageStore {
    static let shared = ImageStore()

    private var cache: [URL: NSImage] = [:]
    private var misses: Set<URL> = []
    private var inFlight: [URL: Task<Data?, Never>] = [:]

    /// The cached image for `url`, without starting a load.
    func image(for url: URL) -> NSImage? {
        cache[url]
    }

    /// True when an earlier load of `url` failed, so the caller shouldn't ask again.
    func hasFailed(_ url: URL) -> Bool {
        misses.contains(url)
    }

    /// Loads `url` once, sharing the download between callers that ask at the same time.
    /// Returns `nil` when the image can't be fetched or decoded.
    func load(_ url: URL) async -> NSImage? {
        if let cached = cache[url] { return cached }
        if misses.contains(url) { return nil }

        let task: Task<Data?, Never>
        if let existing = inFlight[url] {
            task = existing
        } else {
            task = Task {
                do {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        return nil
                    }
                    return data
                } catch {
                    return nil
                }
            }
            inFlight[url] = task
        }

        let data = await task.value
        inFlight[url] = nil

        // Another caller may have decoded it while this one waited.
        if let cached = cache[url] { return cached }
        guard let data, let image = NSImage(data: data), image.isValid,
              image.size.width > 0, image.size.height > 0 else {
            misses.insert(url)
            return nil
        }
        cache[url] = image
        return image
    }
}
