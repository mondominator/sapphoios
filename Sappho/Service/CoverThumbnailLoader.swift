import UIKit

/// Loads small, server-resized covers for lists that must stay responsive on
/// a slow link (CarPlay), into the same `ImageCache` the phone uses.
///
/// - Cache first, synchronously: the resized copy, else the phone's cached
///   original (scaled down), so a cover the phone has shown costs nothing.
/// - Otherwise fetched in the background, a few at a time (rows are shown
///   first, images arrive later), each request deduplicated and bounded by a
///   timeout. A cover that fails just stays blank.
@MainActor
final class CoverThumbnailLoader {
    static let shared = CoverThumbnailLoader()

    /// Covers in flight at once. On cellular, list requests and the audio
    /// stream must not queue behind dozens of images.
    var maxConcurrent = 3
    var timeout: TimeInterval = 15

    private let session: URLSession
    private var running = 0
    private var queue: [String] = []
    private var jobs: [String: Job] = [:]

    private struct Job {
        let request: URLRequest
        var completions: [(UIImage?) -> Void]
    }

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// A cached cover for the book, if either size is on disk or in memory.
    func cachedImage(audiobookId: Int, width: Int, api: SapphoAPI) -> UIImage? {
        let keys = [api.coverURL(for: audiobookId, width: width), api.coverURL(for: audiobookId)]
            .compactMap { $0?.absoluteString }
        for key in keys {
            if let image = ImageCache.shared.image(for: key) { return image }
        }
        return nil
    }

    /// Calls `completion` with the cover (cached or fetched), or nil if it
    /// could not be loaded. The completion runs on the main actor; when the
    /// image is cached it runs before this returns.
    func load(audiobookId: Int, width: Int, api: SapphoAPI, completion: @escaping (UIImage?) -> Void) {
        if let cached = cachedImage(audiobookId: audiobookId, width: width, api: api) {
            completion(cached)
            return
        }
        guard let url = api.coverURL(for: audiobookId, width: width) else {
            completion(nil)
            return
        }
        let key = url.absoluteString
        if jobs[key] != nil {
            jobs[key]?.completions.append(completion)
            return
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        for (field, value) in api.authHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        jobs[key] = Job(request: request, completions: [completion])
        queue.append(key)
        pump()
    }

    private func pump() {
        while running < maxConcurrent, !queue.isEmpty {
            let key = queue.removeFirst()
            guard let job = jobs[key] else { continue }
            running += 1
            let session = self.session
            let timeout = self.timeout
            Task {
                let image = try? await Deadline.run(seconds: timeout) {
                    let (data, response) = try await session.data(for: job.request)
                    guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
                          let image = UIImage(data: data) else { return nil as UIImage? }
                    return image
                }
                self.finish(key: key, image: image ?? nil)
            }
        }
    }

    private func finish(key: String, image: UIImage?) {
        running -= 1
        if let image {
            ImageCache.shared.setImage(image, for: key)
        }
        let completions = jobs.removeValue(forKey: key)?.completions ?? []
        completions.forEach { $0(image) }
        pump()
    }
}
