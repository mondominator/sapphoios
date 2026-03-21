import XCTest
@testable import Sappho

// MARK: - CarPlayContentProvider.formatDuration Tests

@MainActor
final class CarPlayFormatDurationTests: XCTestCase {

    func testFormatDurationZeroSeconds() {
        XCTAssertEqual(CarPlayContentProvider.formatDuration(0), "0m", "Zero seconds should display as 0m")
    }

    func testFormatDurationSubMinuteSeconds() {
        XCTAssertEqual(CarPlayContentProvider.formatDuration(30), "0m", "30 seconds should display as 0m (seconds are dropped)")
    }

    func testFormatDurationExactlyOneMinute() {
        XCTAssertEqual(CarPlayContentProvider.formatDuration(60), "1m", "60 seconds should display as 1m")
    }

    func testFormatDurationOneMinuteThirtySeconds() {
        XCTAssertEqual(CarPlayContentProvider.formatDuration(90), "1m", "90 seconds should display as 1m (seconds are dropped)")
    }

    func testFormatDurationExactlyOneHour() {
        XCTAssertEqual(CarPlayContentProvider.formatDuration(3600), "1h 0m", "3600 seconds should display as 1h 0m")
    }

    func testFormatDurationOneHourOneMinuteOneSecond() {
        XCTAssertEqual(CarPlayContentProvider.formatDuration(3661), "1h 1m", "3661 seconds should display as 1h 1m")
    }

    func testFormatDurationExactlyTwoHours() {
        XCTAssertEqual(CarPlayContentProvider.formatDuration(7200), "2h 0m", "7200 seconds should display as 2h 0m")
    }

    func testFormatDurationTenHours() {
        XCTAssertEqual(CarPlayContentProvider.formatDuration(36000), "10h 0m", "36000 seconds should display as 10h 0m")
    }
}

// MARK: - ServiceLocator Tests

final class ServiceLocatorTests: XCTestCase {

    func testSharedInstanceIsSingleton() {
        let first = ServiceLocator.shared
        let second = ServiceLocator.shared
        XCTAssertTrue(first === second, "ServiceLocator.shared should always return the same instance")
    }

    func testIsConfiguredAfterConfigure() {
        let authRepo = AuthRepository()
        let api = SapphoAPI(authRepository: authRepo)
        let audioPlayer = AudioPlayerService()

        ServiceLocator.shared.configure(api: api, audioPlayer: audioPlayer, authRepository: authRepo)

        XCTAssertTrue(ServiceLocator.shared.isConfigured, "isConfigured should be true after configure() is called")
        authRepo.clear()
    }

    func testConfigureSetsAPI() {
        let authRepo = AuthRepository()
        let api = SapphoAPI(authRepository: authRepo)
        let audioPlayer = AudioPlayerService()

        ServiceLocator.shared.configure(api: api, audioPlayer: audioPlayer, authRepository: authRepo)

        XCTAssertNotNil(ServiceLocator.shared.api, "api should not be nil after configure()")
        XCTAssertTrue(ServiceLocator.shared.api === api, "api should be the same instance passed to configure()")
        authRepo.clear()
    }

    func testConfigureSetsAudioPlayer() {
        let authRepo = AuthRepository()
        let api = SapphoAPI(authRepository: authRepo)
        let audioPlayer = AudioPlayerService()

        ServiceLocator.shared.configure(api: api, audioPlayer: audioPlayer, authRepository: authRepo)

        XCTAssertNotNil(ServiceLocator.shared.audioPlayer, "audioPlayer should not be nil after configure()")
        XCTAssertTrue(ServiceLocator.shared.audioPlayer === audioPlayer, "audioPlayer should be the same instance passed to configure()")
        authRepo.clear()
    }

    func testConfigureSetsAuthRepository() {
        let authRepo = AuthRepository()
        let api = SapphoAPI(authRepository: authRepo)
        let audioPlayer = AudioPlayerService()

        ServiceLocator.shared.configure(api: api, audioPlayer: audioPlayer, authRepository: authRepo)

        XCTAssertNotNil(ServiceLocator.shared.authRepository, "authRepository should not be nil after configure()")
        XCTAssertTrue(ServiceLocator.shared.authRepository === authRepo, "authRepository should be the same instance passed to configure()")
        authRepo.clear()
    }
}
