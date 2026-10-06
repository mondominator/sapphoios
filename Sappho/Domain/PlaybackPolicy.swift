import Foundation

// Pure decision rules pulled out of the services so they can be unit tested
// without a player, a network or a device. Each one encodes a bug that shipped:
// keep the rule here and the side effects in the service.

// MARK: - Auth

enum AuthFailurePolicy {
    /// Whether an HTTP status from an authenticated request means the session
    /// is gone and the stored tokens should be cleared.
    ///
    /// - 401 means the token is missing, expired or revoked. Clear it, unless
    ///   the request was already retried with a freshly refreshed token: a
    ///   brand-new token cannot be expired, so a 401 then is the endpoint's own
    ///   answer (e.g. "Current password is incorrect"), not a dead session.
    /// - 403 means the token is valid but this request is forbidden by policy
    ///   (admin-only route, must_change_password, SSO account). The server
    ///   documents that clients must NOT log out on it (server/auth.js).
    static func shouldClearSession(statusCode: Int, retriedWithFreshToken: Bool) -> Bool {
        statusCode == 401 && !retriedWithFreshToken
    }

    /// True when a 403 body is the server's "change your password first" gate.
    static func isPasswordChangeRequired(statusCode: Int, body: Data) -> Bool {
        guard statusCode == 403,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return false
        }
        if let flag = object["must_change_password"] as? Bool { return flag }
        if let flag = object["must_change_password"] as? Int { return flag == 1 }
        return false
    }
}

// MARK: - Finishing a book

enum PlaybackCompletionPolicy {
    /// How close to the book's real end playback must be for "the file ended"
    /// to count as "the book is finished".
    static let finishTolerance: TimeInterval = 60

    /// The book's length as the server knows it: its duration, or failing
    /// that the end of the last chapter. Never the player item's own duration,
    /// because a truncated file or a part-1 stream reports its own short length.
    static func knownDuration(bookDuration: Int?, chapters: [Chapter]?) -> TimeInterval? {
        if let bookDuration, bookDuration > 0 {
            return TimeInterval(bookDuration)
        }
        if let last = chapters?.max(by: { $0.startTime < $1.startTime }),
           let length = last.duration, length > 0 {
            return last.startTime + length
        }
        return nil
    }

    /// True only when the end of the audio is genuinely the end of the book.
    /// An early end (multi-file part 1, truncated download) must not mark the
    /// book finished and reset it to 0.
    static func isGenuineEnd(position: TimeInterval, knownDuration: TimeInterval?) -> Bool {
        guard let knownDuration, knownDuration > 0 else { return false }
        return position >= knownDuration - finishTolerance
    }
}

// MARK: - Which position wins

/// A position saved on this device, with when it was saved.
struct LocalProgress: Codable, Equatable {
    let position: Int
    let updatedAt: Date
}

enum ProgressReconciler {
    /// Pick the position to start from: the newer of the server's and this
    /// device's, by timestamp. With no usable server timestamp, the further
    /// position wins (losing listening is worse than replaying a little).
    ///
    /// `untimedLocal` is a position saved before timestamps were recorded
    /// (the pre-1.0.1 "last played" slot); with no way to order it, the
    /// further position wins.
    static func resolve(serverPosition: Int?, serverUpdatedAt: String?, local: LocalProgress?, untimedLocal: Int? = nil) -> Int {
        let server = serverPosition ?? 0
        guard let local else { return max(server, untimedLocal ?? 0) }
        guard serverPosition != nil else { return local.position }
        guard let serverDate = parseServerTimestamp(serverUpdatedAt) else {
            return max(server, local.position)
        }
        return local.updatedAt > serverDate ? local.position : server
    }

    /// The server stores SQLite `CURRENT_TIMESTAMP`, "YYYY-MM-DD HH:MM:SS" in
    /// UTC; accept ISO 8601 too in case a route formats it.
    static func parseServerTimestamp(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let sqlite = DateFormatter()
        sqlite.locale = Locale(identifier: "en_US_POSIX")
        sqlite.timeZone = TimeZone(identifier: "UTC")
        sqlite.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = sqlite.date(from: value) { return date }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: value)
    }
}

// MARK: - Audio session events

enum InterruptionPolicy {
    /// Resume after an interruption (phone call, Siri, alarm) only if the
    /// system says resuming is appropriate AND we were playing when it began.
    /// Either alone is wrong: a paused book must not start by itself after a
    /// call, and another app taking over audio must not be undone.
    static func shouldResume(systemSaysShouldResume: Bool, wasPlaying: Bool) -> Bool {
        systemSaysShouldResume && wasPlaying
    }
}

enum PlayRequestPolicy {
    /// "Play" on the book that is already loaded continues from where the
    /// player is, instead of reloading it at the position the caller fetched
    /// (which may be an hour stale). An explicit start (a chapter tap) still
    /// restarts at that position.
    static func shouldResumeLoadedBook(loadedBookId: Int?, requestedBookId: Int, explicitStart: TimeInterval?) -> Bool {
        explicitStart == nil && loadedBookId == requestedBookId
    }
}
