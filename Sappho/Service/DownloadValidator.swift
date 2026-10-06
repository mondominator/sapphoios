import Foundation

/// Rules for deciding whether a downloaded file is really the book.
///
/// Downloads used to be accepted unconditionally: a 401/404/500 response body
/// (a 40-byte JSON error) was saved as `<id>.m4b`, shown as Downloaded, and
/// played in preference to the stream -- silently failing on every attempt.
enum DownloadValidator {
    enum Verdict: Equatable {
        case valid
        case invalid(String)

        var isValid: Bool { self == .valid }
    }

    /// Smaller than this is not an audiobook; error bodies are tens of bytes.
    static let minimumAudioBytes: Int64 = 64 * 1024

    /// Only a 200 (whole file) or 206 (resumed range) carries the audio.
    static func validateResponse(statusCode: Int?) -> Verdict {
        guard let statusCode else { return .invalid("No response from the server") }
        switch statusCode {
        case 200, 206:
            return .valid
        case 401, 403:
            return .invalid("Not authorized to download this book (HTTP \(statusCode))")
        case 404:
            return .invalid("The server no longer has this book (HTTP 404)")
        case 409:
            return .invalid("The server cannot serve this book as one file yet (HTTP 409)")
        default:
            return .invalid("Download failed: the server returned HTTP \(statusCode)")
        }
    }

    /// Size and content sanity for a finished file.
    /// - Parameters:
    ///   - expectedLength: the response's Content-Length for a full (200)
    ///     response, when known. A mismatch means the transfer was cut short.
    ///   - leadingBytes: the first few bytes; a JSON or HTML body starts with
    ///     `{`, `[` or `<`, which no audio container does.
    static func validateFile(size: Int64, expectedLength: Int64?, leadingBytes: Data) -> Verdict {
        if let first = leadingBytes.first(where: { !isWhitespace($0) }),
           first == UInt8(ascii: "{") || first == UInt8(ascii: "[") || first == UInt8(ascii: "<") {
            return .invalid("The server sent an error page instead of audio")
        }
        if let expectedLength, expectedLength > 0, size != expectedLength {
            return .invalid("Download incomplete (\(size) of \(expectedLength) bytes)")
        }
        if size < minimumAudioBytes {
            return .invalid("Downloaded file is too small to be an audiobook (\(size) bytes)")
        }
        return .valid
    }

    /// A file whose audio is clearly shorter than the book is a partial
    /// download, or part 1 of a multi-file book. Unknown durations pass.
    /// The margin is wide (10%, at least 2 minutes) because AVFoundation only
    /// estimates the length of some MP3s, and deleting a good download by
    /// mistake is worse than keeping a slightly short one.
    static func validateDuration(actual: TimeInterval?, expected: TimeInterval?) -> Verdict {
        guard let actual, let expected, actual.isFinite, actual > 0, expected > 0 else { return .valid }
        let tolerance = max(120, expected * 0.10)
        if actual < expected - tolerance {
            return .invalid("Downloaded audio is shorter than the book (\(Int(actual))s of \(Int(expected))s)")
        }
        return .valid
    }

    /// Whether the server's file has changed since this download.
    ///
    /// Compares the server's `file_size` now with the value recorded when the
    /// download was made. Downloads from before that was recorded compare it
    /// with the size on disk instead (this catches the part-1 downloads of
    /// multi-file books, whose server size is the sum of all parts); once
    /// re-downloaded they carry a recorded value, so a server whose stored
    /// size is slightly off cannot cause a re-download loop.
    static func isStale(recordedServerSize: Int64?, localSize: Int64, currentServerSize: Int64?) -> Bool {
        guard let currentServerSize, currentServerSize > 0 else { return false }
        if let recordedServerSize {
            return recordedServerSize != currentServerSize
        }
        return localSize != currentServerSize
    }

    /// Fallback when the book API has no size: compare the stream's ETag (or
    /// length) now with what was downloaded.
    static func isStale(recordedETag: String?, localSize: Int64, streamETag: String?, streamLength: Int64?) -> Bool {
        if let recordedETag, let streamETag {
            return recordedETag != streamETag
        }
        if let streamLength, streamLength > 0 {
            return streamLength != localSize
        }
        return false
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }
}
