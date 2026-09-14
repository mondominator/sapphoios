import XCTest
@testable import Sappho

// MARK: - ServiceLocator Tests

@MainActor
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
