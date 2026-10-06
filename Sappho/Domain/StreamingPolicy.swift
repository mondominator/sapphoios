import Foundation
import CoreMedia

// MARK: - Choosing progressive or HLS

/// The network as `NWPath` describes it, reduced to what the stream choice
/// needs. Value type so the choice can be tested without a real path.
struct NetworkConditions: Equatable {
    var isCellular: Bool
    /// Personal hotspot, cellular, or a network the user marked as metered.
    var isExpensive: Bool
    /// Low Data Mode.
    var isConstrained: Bool

    static let unmetered = NetworkConditions(isCellular: false, isExpensive: false, isConstrained: false)

    /// Where the first audio has to arrive in a few hundred KB instead of the
    /// whole `moov` box (up to ~15 MB on a long book).
    var isCostly: Bool { isCellular || isExpensive || isConstrained }
}

/// How the player gets a book's audio.
enum StreamMode: Equatable {
    /// The downloaded file.
    case localFile
    /// `GET /api/audiobooks/:id/stream` (supports range requests; fine on Wi-Fi).
    case progressive
    /// `GET /api/audiobooks/:id/hls/master.m3u8`; `preferLow` asks for the
    /// 32 kbps speech variant first (data saver).
    case hls(preferLow: Bool)

    var isHLS: Bool {
        if case .hls = self { return true }
        return false
    }
}

/// What the server can serve as HLS, from what the client knows about the file.
enum HLSCodecHint: Equatable {
    /// AAC in MP4 (.m4b/.m4a/.mp4/.aac): HLS works.
    case supported
    /// Anything else (MP3, FLAC, ...): the server answers 415; skip the round trip.
    case unsupported
    /// No file name: try HLS and fall back on 415.
    case unknown

    private static let mp4Extensions: Set<String> = ["m4b", "m4a", "mp4", "aac"]

    /// From the book's `file_path` (only its extension is used).
    static func from(filePath: String?) -> HLSCodecHint {
        guard let filePath, !filePath.isEmpty else { return .unknown }
        let ext = (filePath as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return .unknown }
        return mp4Extensions.contains(ext) ? .supported : .unsupported
    }
}

enum StreamingPolicy {
    /// UserDefaults key of the "Data saver" setting (default off).
    static let dataSaverKey = "dataSaver"

    /// Pick how to play a book.
    ///
    /// - A downloaded book always plays its file.
    /// - HLS on a cellular / expensive / constrained network, or with data
    ///   saver on (which also asks for the low variant first). Progressive
    ///   needs the whole `moov` before the first audio; HLS needs ~0.1 MB.
    /// - Otherwise progressive, as before.
    /// - Never HLS for a file the server can't serve as HLS (`codec`), or
    ///   when HLS already failed for this book (`hlsBlocked`).
    static func mode(
        isDownloaded: Bool,
        network: NetworkConditions,
        dataSaver: Bool,
        codec: HLSCodecHint,
        hlsBlocked: Bool
    ) -> StreamMode {
        if isDownloaded { return .localFile }
        guard codec != .unsupported, !hlsBlocked else { return .progressive }
        if dataSaver { return .hls(preferLow: true) }
        if network.isCostly { return .hls(preferLow: false) }
        return .progressive
    }

    /// The URL for a remote mode (nil for `.localFile`).
    static func url(for mode: StreamMode, baseURL: URL, audiobookId: Int) -> URL? {
        let book = baseURL.appendingPathComponent("api/audiobooks/\(audiobookId)")
        switch mode {
        case .localFile:
            return nil
        case .progressive:
            return book.appendingPathComponent("stream")
        case .hls(let preferLow):
            let master = book.appendingPathComponent("hls/master.m3u8")
            guard preferLow, var components = URLComponents(url: master, resolvingAgainstBaseURL: false) else { return master }
            components.queryItems = [URLQueryItem(name: "prefer", value: "low")]
            return components.url
        }
    }

    /// With data saver on, keep AVPlayer on the lowest variant even when the
    /// link could take more (it would otherwise switch up to `source`). Below
    /// every variant's bandwidth, so AVPlayer picks the lowest one listed.
    static let dataSaverPeakBitRate: Double = 48_000

    static func preferredPeakBitRate(for mode: StreamMode) -> Double {
        if case .hls(preferLow: true) = mode { return dataSaverPeakBitRate }
        return 0 // no limit
    }
}

// MARK: - Seeking

enum SeekPolicy {
    /// Seeks are exact in both modes. AVPlayer's default tolerance lets an HLS
    /// seek land on a segment boundary (up to ~10 s away), so the same saved
    /// position would resume at a different spot on cellular than on Wi-Fi.
    /// AAC frames are all sync samples, so an exact seek costs nothing extra.
    static let toleranceBefore: CMTime = .zero
    static let toleranceAfter: CMTime = .zero
}

// MARK: - HLS failures

/// What the client learned by asking for the master playlist itself (after
/// AVPlayer failed on an HLS item, since AVPlayer does not expose the
/// server's status codes or error bodies).
enum HLSProbeResult: Equatable {
    /// 200; `fileVersion` from `X-File-Version`.
    case available(fileVersion: String?)
    /// 415 HLS_UNSUPPORTED (e.g. an MP3 book): use `/stream`.
    case unsupported
    /// Anything else (no network, 401, 409 unmerged, 5xx).
    case failed(statusCode: Int?)
}

enum HLSRecoveryAction: Equatable {
    /// Rebuild the item from a freshly requested master playlist at the
    /// current position (the file changed, or the token was refreshed).
    case reloadHLS
    /// Play `/stream` at the current position for the rest of this play.
    case fallBackToProgressive
}

enum HLSRecoveryPolicy {
    /// HLS reloads allowed per play request, so a server that keeps failing
    /// ends on progressive instead of a reload loop.
    static let maxReloads = 2

    /// - `failedVersion`: the file version in the URI AVPlayer failed on, if
    ///   any (`/hls/<version>/...`).
    /// - `failedStatusCode`: the HTTP status AVPlayer logged for it.
    static func action(
        probe: HLSProbeResult,
        failedVersion: String?,
        failedStatusCode: Int?,
        reloadsSoFar: Int
    ) -> HLSRecoveryAction {
        guard reloadsSoFar < maxReloads, case .available(let current) = probe else {
            return .fallBackToProgressive
        }
        // 404 FILE_VERSION_CHANGED: the file was replaced (merge, faststart,
        // re-tag) under the playlist AVPlayer loaded. The new master points
        // at the new version; positions are unchanged.
        if let failedVersion, let current, failedVersion != current {
            return .reloadHLS
        }
        // AVPlayer's error log often omits the URI. A 404 under the
        // immutable versioned URLs while the master answers means the same.
        if failedStatusCode == 404, failedVersion == nil {
            return .reloadHLS
        }
        // The token in the item's headers expired; the master just answered
        // with the refreshed one.
        if failedStatusCode == 401 {
            return .reloadHLS
        }
        return .fallBackToProgressive
    }

    /// The HTTP status of a failed HLS request as AVPlayer logs it: the
    /// comment reads "HTTP 404: File Not Found"; the code is a CoreMedia
    /// error (e.g. -12938), or the status itself on some versions.
    static func httpStatus(comment: String?, code: Int?) -> Int? {
        if let comment,
           let range = comment.range(of: #"HTTP (\d{3})"#, options: .regularExpression),
           let status = Int(comment[range].dropFirst(5)) {
            return status
        }
        if let code, (100...599).contains(code) { return code }
        return nil
    }

    /// `<version>` from `.../hls/<version>/<variant>/<file>`.
    static func fileVersion(inURI uri: String?) -> String? {
        guard let uri else { return nil }
        let path = URL(string: uri)?.path ?? uri
        let parts = path.split(separator: "/").map(String.init)
        guard let hls = parts.firstIndex(of: "hls"), hls + 2 < parts.count else { return nil }
        let version = parts[hls + 1]
        guard version != "master.m3u8", version.range(of: #"^\d+-\d+$"#, options: .regularExpression) != nil else { return nil }
        return version
    }
}
