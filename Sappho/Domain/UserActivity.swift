import Foundation

/// Admin user activity (server 0.16.5+). `GET /api/users` reports, per user:
/// - `last_listened_at`: latest playback progress update (filled for everyone)
/// - `last_active_at`: last sign-in or session refresh
/// - `last_login_at`: last sign-in
/// All are SQLite UTC timestamps or null. Older servers omit them entirely,
/// which `AdminUser.reportsActivity` tells apart from null.
enum UserActivity {
    /// The more recent of listening and session activity; nil if neither.
    static func mostRecent(lastListened: Date?, lastActive: Date?) -> Date? {
        switch (lastListened, lastActive) {
        case let (listened?, active?): return max(listened, active)
        case let (listened?, nil): return listened
        case let (nil, active?): return active
        case (nil, nil): return nil
        }
    }

    /// List-row line: "Active 3 days ago", or "No activity yet".
    static func activeLabel(_ lastActivity: Date?, now: Date = Date(), locale: Locale = .current) -> String {
        guard let lastActivity else { return "No activity yet" }
        return "Active \(relative(lastActivity, now: now, locale: locale))"
    }

    /// Detail value for last sign-in. Null means the server hasn't recorded
    /// one yet (column added in 0.16.5), not that the user never signed in.
    static func lastLoginLabel(_ lastLogin: Date?, now: Date = Date(), locale: Locale = .current) -> String {
        guard let lastLogin else { return "Not recorded yet" }
        return relative(lastLogin, now: now, locale: locale)
    }

    /// "3 days ago". Anything under a minute, including a server clock a
    /// little ahead of ours, reads "just now" rather than "in 5 seconds".
    static func relative(_ date: Date, now: Date = Date(), locale: Locale = .current) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .numeric
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

extension AdminUser {
    var lastListenedDate: Date? { ProgressReconciler.parseServerTimestamp(lastListenedAt) }
    var lastActiveDate: Date? { ProgressReconciler.parseServerTimestamp(lastActiveAt) }
    var lastLoginDate: Date? { ProgressReconciler.parseServerTimestamp(lastLoginAt) }
    var createdDate: Date? { ProgressReconciler.parseServerTimestamp(createdAt) }

    /// Most recent of listening and session activity.
    var lastActivityDate: Date? {
        UserActivity.mostRecent(lastListened: lastListenedDate, lastActive: lastActiveDate)
    }
}
