import XCTest
@testable import Sappho

final class UserActivityTests: XCTestCase {

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

    func testDecodesAllActivityFieldsInSQLiteFormat() throws {
        let user = try decode("""
        {"id": 1, "username": "anna", "is_admin": 0,
         "last_login_at": "2026-10-01 08:30:00",
         "last_active_at": "2026-10-05 12:00:00",
         "last_listened_at": "2026-10-07 21:15:30"}
        """)

        XCTAssertTrue(user.reportsActivity)
        XCTAssertEqual(user.lastLoginDate, utc(2026, 10, 1, 8, 30))
        XCTAssertEqual(user.lastActiveDate, utc(2026, 10, 5, 12))
        XCTAssertEqual(user.lastListenedDate, utc(2026, 10, 7, 21, 15, 30))
    }

    func testSQLiteTimestampIsReadAsUTC() throws {
        // No zone in the string: it must not be read as device-local time.
        let user = try decode("""
        {"id": 1, "username": "anna", "is_admin": 0, "last_login_at": "2026-01-02 03:04:05"}
        """)
        XCTAssertEqual(user.lastLoginDate?.timeIntervalSince1970, utc(2026, 1, 2, 3, 4, 5).timeIntervalSince1970)
    }

    func testDecodesISO8601Timestamps() throws {
        let user = try decode("""
        {"id": 1, "username": "anna", "is_admin": 0,
         "last_login_at": "2026-10-01T08:30:00Z",
         "last_active_at": "2026-10-05T12:00:00.250Z",
         "last_listened_at": null}
        """)

        XCTAssertEqual(user.lastLoginDate, utc(2026, 10, 1, 8, 30))
        XCTAssertEqual(user.lastActiveDate!.timeIntervalSince1970,
                       utc(2026, 10, 5, 12).timeIntervalSince1970 + 0.25, accuracy: 0.001)
        XCTAssertNil(user.lastListenedDate)
    }

    func testNullFieldsDecodeAsNilButStillReportActivity() throws {
        let user = try decode("""
        {"id": 1, "username": "anna", "is_admin": 0,
         "last_login_at": null, "last_active_at": null, "last_listened_at": null}
        """)

        XCTAssertTrue(user.reportsActivity, "a 0.16.5 server sent the fields, they are just empty")
        XCTAssertNil(user.lastLoginAt)
        XCTAssertNil(user.lastActiveAt)
        XCTAssertNil(user.lastListenedAt)
        XCTAssertNil(user.lastActivityDate)
    }

    func testMissingFieldsFromOlderServer() throws {
        let user = try decode("""
        {"id": 1, "username": "anna", "is_admin": 0, "created_at": "2024-01-01 00:00:00"}
        """)

        XCTAssertFalse(user.reportsActivity, "older servers omit the fields; don't claim 'No activity yet'")
        XCTAssertNil(user.lastLoginAt)
        XCTAssertNil(user.lastActiveAt)
        XCTAssertNil(user.lastListenedAt)
        XCTAssertEqual(user.username, "anna")
        XCTAssertEqual(user.createdDate, utc(2024, 1, 1))
    }

    func testUnparseableTimestampIsNil() throws {
        let user = try decode("""
        {"id": 1, "username": "anna", "is_admin": 0, "last_active_at": "yesterday-ish"}
        """)
        XCTAssertEqual(user.lastActiveAt, "yesterday-ish")
        XCTAssertNil(user.lastActiveDate)
    }

    // MARK: - Most recent activity

    func testMostRecentPicksListenedWhenNewer() {
        let listened = utc(2026, 10, 7)
        let active = utc(2026, 10, 1)
        XCTAssertEqual(UserActivity.mostRecent(lastListened: listened, lastActive: active), listened)
    }

    func testMostRecentPicksActiveWhenNewer() {
        let listened = utc(2026, 9, 1)
        let active = utc(2026, 10, 1)
        XCTAssertEqual(UserActivity.mostRecent(lastListened: listened, lastActive: active), active)
    }

    func testMostRecentWithOneSideNil() {
        let date = utc(2026, 10, 1)
        XCTAssertEqual(UserActivity.mostRecent(lastListened: nil, lastActive: date), date)
        XCTAssertEqual(UserActivity.mostRecent(lastListened: date, lastActive: nil), date)
    }

    func testMostRecentAllNil() {
        XCTAssertNil(UserActivity.mostRecent(lastListened: nil, lastActive: nil))
    }

    func testLastActivityDateFromDecodedUser() throws {
        let user = try decode("""
        {"id": 1, "username": "anna", "is_admin": 0,
         "last_active_at": "2026-10-05 12:00:00", "last_listened_at": "2026-10-07 21:15:30"}
        """)
        XCTAssertEqual(user.lastActivityDate, utc(2026, 10, 7, 21, 15, 30))
    }

    // MARK: - Labels

    func testActiveLabelRelative() {
        let now = utc(2026, 10, 8, 12)
        XCTAssertEqual(UserActivity.activeLabel(utc(2026, 10, 5, 12), now: now, locale: enUS), "Active 3 days ago")
        XCTAssertEqual(UserActivity.activeLabel(utc(2026, 10, 8, 10), now: now, locale: enUS), "Active 2 hours ago")
    }

    func testActiveLabelAllNil() {
        XCTAssertEqual(UserActivity.activeLabel(nil, locale: enUS), "No activity yet")
    }

    func testLastLoginLabelNotRecordedYet() {
        XCTAssertEqual(UserActivity.lastLoginLabel(nil, locale: enUS), "Not recorded yet")
    }

    func testLastLoginLabelRelative() {
        let now = utc(2026, 10, 8, 12)
        XCTAssertEqual(UserActivity.lastLoginLabel(utc(2026, 9, 24, 12), now: now, locale: enUS), "2 weeks ago")
    }

    func testRecentAndSlightlyFutureReadJustNow() {
        let now = utc(2026, 10, 8, 12)
        XCTAssertEqual(UserActivity.relative(now.addingTimeInterval(-20), now: now, locale: enUS), "just now")
        XCTAssertEqual(UserActivity.relative(now.addingTimeInterval(30), now: now, locale: enUS), "just now")
        XCTAssertEqual(UserActivity.activeLabel(now, now: now, locale: enUS), "Active just now")
    }
}
