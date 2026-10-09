import Foundation

/// A user's most recent listening, for Admin > Users (server 0.16.5+).
/// `GET /api/users` reports `last_listened_at` (latest playback progress,
/// SQLite UTC) and `last_listened_title` (that book), plus `last_login_at`.
/// Older servers omit them entirely, which `AdminUser.reportsActivity` tells
/// apart from null.
struct ListeningActivity: Equatable {
    /// Nil when the server couldn't name the book.
    let title: String?
    let date: Date

    /// "Listened to Golden Son", or "Listened" without a title.
    var headline: String {
        guard let title, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return "Listened" }
        return "Listened to \(title)"
    }

    /// "Listened to Golden Son · Today 6:12 PM", or "No listening yet".
    static func summary(_ activity: ListeningActivity?, now: Date = Date(),
                        timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        guard let activity else { return "No listening yet" }
        return "\(activity.headline) · \(timestamp(activity.date, now: now, timeZone: timeZone, locale: locale))"
    }

    /// Last sign-in for the detail screen. Null means the server hasn't
    /// recorded one yet (tracked from 0.16.5), not that they never signed in.
    static func lastLoginLabel(_ lastLogin: Date?, now: Date = Date(),
                               timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        guard let lastLogin else { return "Not recorded yet" }
        return timestamp(lastLogin, now: now, timeZone: timeZone, locale: locale)
    }

    /// Absolute, in local time: "Today 6:12 PM", "Yesterday 6:12 PM",
    /// "Mon 6:12 PM" within the last week, otherwise "Oct 3" (with the year
    /// when it isn't this year). Times follow the locale's 12/24-hour clock.
    static func timestamp(_ date: Date, now: Date = Date(),
                          timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale

        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)
        ).day ?? 0

        func format(_ template: String) -> String {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = timeZone
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter.string(from: date)
        }

        switch days {
        case 0: return "Today \(format("jmm"))"
        case 1: return "Yesterday \(format("jmm"))"
        case 2...6: return format("EEEjmm")
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            return format(sameYear ? "MMMd" : "yMMMd")
        }
    }
}

extension AdminUser {
    var lastListenedDate: Date? { ProgressReconciler.parseServerTimestamp(lastListenedAt) }
    var lastLoginDate: Date? { ProgressReconciler.parseServerTimestamp(lastLoginAt) }
    var createdDate: Date? { ProgressReconciler.parseServerTimestamp(createdAt) }

    var lastListen: ListeningActivity? {
        lastListenedDate.map { ListeningActivity(title: lastListenedTitle, date: $0) }
    }
}
