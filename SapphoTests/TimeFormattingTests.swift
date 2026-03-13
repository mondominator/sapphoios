import XCTest
@testable import Sappho

final class TimeFormattingTests: XCTestCase {

    // MARK: - formatTime (TimeInterval overload)

    func testFormatTimeZeroSeconds() {
        XCTAssertEqual(formatTime(TimeInterval(0)), "0:00")
    }

    func testFormatTimeSecondsOnly() {
        XCTAssertEqual(formatTime(TimeInterval(5)), "0:05")
        XCTAssertEqual(formatTime(TimeInterval(45)), "0:45")
        XCTAssertEqual(formatTime(TimeInterval(59)), "0:59")
    }

    func testFormatTimeMinutesAndSeconds() {
        XCTAssertEqual(formatTime(TimeInterval(60)), "1:00")
        XCTAssertEqual(formatTime(TimeInterval(90)), "1:30")
        XCTAssertEqual(formatTime(TimeInterval(125)), "2:05")
        XCTAssertEqual(formatTime(TimeInterval(3599)), "59:59")
    }

    func testFormatTimeHoursMinutesSeconds() {
        XCTAssertEqual(formatTime(TimeInterval(3600)), "1:00:00")
        XCTAssertEqual(formatTime(TimeInterval(3661)), "1:01:01")
        XCTAssertEqual(formatTime(TimeInterval(7200)), "2:00:00")
        XCTAssertEqual(formatTime(TimeInterval(7384)), "2:03:04")
    }

    func testFormatTimeLargeValues() {
        // 10 hours
        XCTAssertEqual(formatTime(TimeInterval(36000)), "10:00:00")
        // 100 hours
        XCTAssertEqual(formatTime(TimeInterval(360000)), "100:00:00")
    }

    func testFormatTimeFractionalSeconds() {
        // Fractional seconds should be truncated (Int conversion)
        XCTAssertEqual(formatTime(TimeInterval(65.9)), "1:05")
        XCTAssertEqual(formatTime(TimeInterval(3600.5)), "1:00:00")
    }

    func testFormatTimeLeadingZeroPadding() {
        // Minutes and seconds should be zero-padded to 2 digits
        XCTAssertEqual(formatTime(TimeInterval(3601)), "1:00:01")
        XCTAssertEqual(formatTime(TimeInterval(3660)), "1:01:00")
    }

    // MARK: - formatTime (Int overload)

    func testFormatTimeIntOverload() {
        XCTAssertEqual(formatTime(0), "0:00")
        XCTAssertEqual(formatTime(90), "1:30")
        XCTAssertEqual(formatTime(3661), "1:01:01")
    }

    // MARK: - formatDuration

    func testFormatDurationZero() {
        XCTAssertEqual(formatDuration(0), "0m")
    }

    func testFormatDurationMinutesOnly() {
        XCTAssertEqual(formatDuration(60), "1m")
        XCTAssertEqual(formatDuration(300), "5m")
        XCTAssertEqual(formatDuration(2700), "45m")
        XCTAssertEqual(formatDuration(3540), "59m")
    }

    func testFormatDurationHoursAndMinutes() {
        XCTAssertEqual(formatDuration(3600), "1h 0m")
        XCTAssertEqual(formatDuration(5400), "1h 30m")
        XCTAssertEqual(formatDuration(7200), "2h 0m")
        XCTAssertEqual(formatDuration(8100), "2h 15m")
    }

    func testFormatDurationLargeValues() {
        // 24 hours
        XCTAssertEqual(formatDuration(86400), "24h 0m")
        // 100 hours 30 minutes
        XCTAssertEqual(formatDuration(361800), "100h 30m")
    }

    func testFormatDurationSecondsIgnored() {
        // Seconds less than a full minute should not appear
        XCTAssertEqual(formatDuration(59), "0m")
        XCTAssertEqual(formatDuration(61), "1m")
        // 3659 = 1 hour, 0 minutes, 59 seconds -> "1h 0m" (seconds are dropped)
        XCTAssertEqual(formatDuration(3659), "1h 0m")
    }

    func testFormatDurationExactHours() {
        XCTAssertEqual(formatDuration(3600), "1h 0m")
        XCTAssertEqual(formatDuration(10800), "3h 0m")
    }
}
