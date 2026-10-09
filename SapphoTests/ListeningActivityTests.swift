import XCTest
@testable import Sappho

final class ListeningActivityTests: XCTestCase {

    private let decoder = JSONDecoder()
    private let enUS = Locale(identifier: "en_US")

    private func decode(_ json: String) throws -> AdminUser {
        try decoder.decode(AdminUser.self, from: Data(json.utf8))
    }

    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        var components = DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s)
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    // MARK: - Decoding

    func testDecodesFieldsInSQLiteFormat() throws {
        let user = try decode("""
        {"id": 1, "username": "anna", "is_admin": 0,
         "last_login_at": "2026-10-01 08:30:00",
         "last_active_at": "2026-10-08 12:00:00",
         "last_listened_at": "2026-10-07 21:15:30",
         "last_listened_title": "Golden Son"}
        """)

        XCTAssertTrue(user.reportsActivity)
        XCTAssertEqual(user.lastLoginDate, utc(2026, 10, 1, 8, 30))
        XCTAssertEqual(user.lastListenedDate, utc(2026, 10, 7, 21, 15, 30))
        // last_active_at is newer but ignored: the row is listening only.
        XCTAssertEqual(user.lastListen, ListeningActivity(title: "Golden Son", date: utc(2026, 10, 7, 21, 15, 30)))
    }

    func testSQLiteTimestampIsReadAsUTC() throws {
        // No zone in the string: it must not be read as device-local time.
        let user = try decode("""
        {"id": 1, "username": "anna", "is_admin": 0, "last_listened_at": "2026-01-02 03:04:05"}
        """)
        XCTAssertEqual(user.lastListenedDate?.timeIntervalSince1970, utc(2026, 1, 2, 3, 4, 5).timeIntervalSince1970)
    }

    func testDecodesISO8601Timestamps() throws {
        let user = try decode("""
        {"id": 1, "username": "anna", "is_admin": 0,
         "last_login_at": "2026-10-01T08:30:00Z",
         "last_listened_at": "2026-10-05T12:00:00.250Z"}
        """)

        XCTAssertEqual(user.lastLoginDate, utc(2026, 10, 1, 8, 30))
        XCTAssertEqual(user.lastListenedDate!.timeIntervalSince1970,
                       utc(2026, 10, 5, 12).timeIntervalSince1970 + 0.25, accuracy: 0.001)
    }

    func testNullFieldsMeanNoListeningButStillReportActivity() throws {
        let user = try decode("""
        {"id": 1, "username": "anna", "is_admin": 0,
         "last_login_at": null, "last_active_at": "2026-10-08 12:00:00",
         "last_listened_at": null, "last_listened_title": null}
        """)

        XCTAssertTrue(user.reportsActivity, "a 0.16.5 server sent the fields, they are just empty")
        XCTAssertNil(user.lastLoginAt)
        XCTAssertNil(user.lastListen, "opening the app is not listening")
        XCTAssertEqual(ListeningActivity.summary(user.lastListen, locale: enUS), "No listening yet")
    }

    func testListenedWithNullTitle() throws {
        let user = try decode("""
        {"id": 1, "username": "anna", "is_admin": 0,
         "last_listened_at": "2026-10-07 21:15:30", "last_listened_title": null}
        """)
        XCTAssertEqual(user.lastListen, ListeningActivity(title: nil, date: utc(2026, 10, 7, 21, 15, 30)))
        XCTAssertEqual(user.lastListen?.headline, "Listened")
    }

    func testMissingFieldsFromOlderServer() throws {
        let user = try decode("""
        {"id": 1, "username": "anna", "is_admin": 0, "created_at": "2024-01-01 00:00:00"}
        """)

        XCTAssertFalse(user.reportsActivity, "older servers omit the fields; don't claim 'No listening yet'")
        XCTAssertNil(user.lastLoginAt)
        XCTAssertNil(user.lastListenedAt)
        XCTAssertNil(user.lastListenedTitle)
        XCTAssertEqual(user.createdDate, utc(2024, 1, 1))
    }

    func testUnparseableTimestampIsNil() throws {
        let user = try decode("""
        {"id": 1, "username": "anna", "is_admin": 0, "last_listened_at": "yesterday-ish"}
        """)
        XCTAssertEqual(user.lastListenedAt, "yesterday-ish")
        XCTAssertNil(user.lastListen)
    }

    // MARK: - Headline

    func testHeadline() {
        let date = utc(2026, 10, 1)
        XCTAssertEqual(ListeningActivity(title: "Golden Son", date: date).headline, "Listened to Golden Son")
        XCTAssertEqual(ListeningActivity(title: nil, date: date).headline, "Listened")
        XCTAssertEqual(ListeningActivity(title: "  ", date: date).headline, "Listened")
    }

    // MARK: - Timestamps (fixed now + zone)

    /// Thursday 2026-10-08 19:00 in Denver (MDT, UTC-6).
    private let denver = TimeZone(identifier: "America/Denver")!
    private var now: Date { local(2026, 10, 8, 19, 0) }

    private func local(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var components = DateComponents(year: y, month: mo, day: d, hour: h, minute: mi)
        components.timeZone = denver
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    /// ICU puts a narrow no-break space before AM/PM; compare as plain spaces.
    private func plain(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    private func stamp(_ date: Date) -> String {
        plain(ListeningActivity.timestamp(date, now: now, timeZone: denver, locale: enUS))
    }

    func testTimestampToday() {
        XCTAssertEqual(stamp(local(2026, 10, 8, 18, 12)), "Today 6:12 PM")
        XCTAssertEqual(stamp(local(2026, 10, 8, 0, 5)), "Today 12:05 AM")
    }

    func testTimestampUsesGivenTimeZone() {
        // 00:30 UTC on the 9th is still the evening of the 8th in Denver.
        XCTAssertEqual(stamp(utc(2026, 10, 9, 0, 30)), "Today 6:30 PM")
    }

    func testTimestampYesterday() {
        XCTAssertEqual(stamp(local(2026, 10, 7, 23, 59)), "Yesterday 11:59 PM")
    }

    func testTimestampWithinLastWeekShowsWeekday() {
        XCTAssertEqual(stamp(local(2026, 10, 5, 9, 30)), "Mon 9:30 AM")
        XCTAssertEqual(stamp(local(2026, 10, 2, 18, 12)), "Fri 6:12 PM")
    }

    func testTimestampOlderThisYear() {
        XCTAssertEqual(stamp(local(2026, 10, 1, 18, 12)), "Oct 1")
        XCTAssertEqual(stamp(local(2026, 3, 14, 8, 0)), "Mar 14")
    }

    func testTimestampPreviousYearIncludesYear() {
        XCTAssertEqual(stamp(local(2025, 12, 31, 8, 0)), "Dec 31, 2025")
    }

    // MARK: - Summary

    private func summary(_ activity: ListeningActivity?) -> String {
        plain(ListeningActivity.summary(activity, now: now, timeZone: denver, locale: enUS))
    }

    func testSummaryCombinesWhatAndWhen() {
        XCTAssertEqual(summary(ListeningActivity(title: "Golden Son", date: local(2026, 10, 8, 18, 12))),
                       "Listened to Golden Son · Today 6:12 PM")
        XCTAssertEqual(summary(ListeningActivity(title: "Red Rising", date: local(2026, 10, 3, 10, 0))),
                       "Listened to Red Rising · Sat 10:00 AM")
        XCTAssertEqual(summary(ListeningActivity(title: nil, date: local(2026, 10, 1, 10, 0))),
                       "Listened · Oct 1")
    }

    func testSummaryNeverListened() {
        XCTAssertEqual(summary(nil), "No listening yet")
    }

    // MARK: - Last login

    func testLastLoginNotRecordedYet() {
        XCTAssertEqual(ListeningActivity.lastLoginLabel(nil, locale: enUS), "Not recorded yet")
    }

    func testLastLoginTimestamp() {
        let label = ListeningActivity.lastLoginLabel(local(2026, 9, 24, 12, 0), now: now, timeZone: denver, locale: enUS)
        XCTAssertEqual(label, "Sep 24")
    }
}
