import Foundation

/// Cover image URLs.
///
/// The server resizes covers for `?width=` in a fixed set of sizes and caches
/// the result (server/services/thumbnailService.js: 120, 300, 600). Any other
/// width is ignored and the original is sent -- which is what CarPlay used to
/// fetch for every row: an original cover can be several MB, and a car on
/// cellular was pulling up to 100 of them at once next to the list requests.
/// A 120 px thumbnail is a few KB.
///
/// Servers too old to know `width` ignore it and send the original, so asking
/// is always safe.
enum CoverURL {
    /// Widths the server will resize to, smallest first.
    static let serverWidths = [120, 300, 600]

    /// CarPlay list rows draw covers at most ~90 pt; 120 px is the server's
    /// smallest size and plenty for a row.
    static let listThumbnailWidth = 120
    /// Now Playing / lock screen artwork.
    static let artworkWidth = 600

    /// The smallest server size that is at least `width`, or the largest.
    static func serverWidth(atLeast width: Int) -> Int {
        serverWidths.first { $0 >= width } ?? serverWidths[serverWidths.count - 1]
    }

    /// The cover URL; with `width`, a server-resized copy (snapped to a size
    /// the server supports, since other values are ignored).
    static func make(baseURL: URL, audiobookId: Int, width: Int? = nil) -> URL {
        let url = baseURL.appendingPathComponent("api/audiobooks/\(audiobookId)/cover")
        guard let width else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "width", value: String(serverWidth(atLeast: width)))]
        return components?.url ?? url
    }
}
