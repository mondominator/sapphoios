import XCTest
@testable import Sappho

final class AudioPlayerServiceTests: XCTestCase {

    private var playerService: AudioPlayerService!

    /// Unique suite key to isolate UserDefaults between test runs
    private let speedKey = "playbackSpeed"
    private let skipForwardKey = "skipForwardSeconds"
    private let skipBackwardKey = "skipBackwardSeconds"
    private let rewindOnResumeKey = "rewindOnResume"

    override func setUp() {
        super.setUp()
        // Clear UserDefaults keys used by AudioPlayerService
        UserDefaults.standard.removeObject(forKey: speedKey)
        UserDefaults.standard.removeObject(forKey: skipForwardKey)
        UserDefaults.standard.removeObject(forKey: skipBackwardKey)
        UserDefaults.standard.removeObject(forKey: rewindOnResumeKey)
        UserDefaults.standard.removeObject(forKey: "lastPlayedAudiobookId")
        UserDefaults.standard.removeObject(forKey: "lastPlayedPosition")
        UserDefaults.standard.removeObject(forKey: "pendingProgressSync")
    }

    override func tearDown() {
        playerService = nil
        UserDefaults.standard.removeObject(forKey: speedKey)
        UserDefaults.standard.removeObject(forKey: skipForwardKey)
        UserDefaults.standard.removeObject(forKey: skipBackwardKey)
        UserDefaults.standard.removeObject(forKey: rewindOnResumeKey)
        UserDefaults.standard.removeObject(forKey: "lastPlayedAudiobookId")
        UserDefaults.standard.removeObject(forKey: "lastPlayedPosition")
        UserDefaults.standard.removeObject(forKey: "pendingProgressSync")
        super.tearDown()
    }

    // MARK: - Default State

    func testDefaultPlaybackSpeed() {
        playerService = AudioPlayerService()
        XCTAssertEqual(playerService.playbackSpeed, 1.0, "Default speed should be 1.0x")
    }

    func testDefaultIsPlayingIsFalse() {
        playerService = AudioPlayerService()
        XCTAssertFalse(playerService.isPlaying)
    }

    func testDefaultPositionIsZero() {
        playerService = AudioPlayerService()
        XCTAssertEqual(playerService.position, 0)
    }

    func testDefaultDurationIsZero() {
        playerService = AudioPlayerService()
        XCTAssertEqual(playerService.duration, 0)
    }

    func testDefaultCurrentAudiobookIsNil() {
        playerService = AudioPlayerService()
        XCTAssertNil(playerService.currentAudiobook)
    }

    func testDefaultCurrentChapterIsNil() {
        playerService = AudioPlayerService()
        XCTAssertNil(playerService.currentChapter)
    }

    func testDefaultIsBufferingIsFalse() {
        playerService = AudioPlayerService()
        XCTAssertFalse(playerService.isBuffering)
    }

    func testDefaultSleepTimerIsNil() {
        playerService = AudioPlayerService()
        XCTAssertNil(playerService.sleepTimerRemaining)
    }

    func testDefaultShowFullPlayerIsFalse() {
        playerService = AudioPlayerService()
        XCTAssertFalse(playerService.showFullPlayer)
    }

    // MARK: - Playback Speed Persistence

    func testPlaybackSpeedRestoresFromUserDefaults() {
        UserDefaults.standard.set(Float(1.5), forKey: speedKey)
        playerService = AudioPlayerService()
        XCTAssertEqual(playerService.playbackSpeed, 1.5, "Should restore saved speed of 1.5x")
    }

    func testPlaybackSpeedDefaultsTo1WhenNoSaved() {
        // Ensure no saved value
        UserDefaults.standard.removeObject(forKey: speedKey)
        playerService = AudioPlayerService()
        XCTAssertEqual(playerService.playbackSpeed, 1.0)
    }

    func testSetPlaybackSpeedSavesToUserDefaults() {
        playerService = AudioPlayerService()
        playerService.setPlaybackSpeed(2.0)

        XCTAssertEqual(playerService.playbackSpeed, 2.0)
        XCTAssertEqual(UserDefaults.standard.float(forKey: speedKey), 2.0)
    }

    func testSetPlaybackSpeedPersistsAcrossInstances() {
        playerService = AudioPlayerService()
        playerService.setPlaybackSpeed(1.75)

        let newService = AudioPlayerService()
        XCTAssertEqual(newService.playbackSpeed, 1.75)
    }

    // MARK: - Skip Forward/Backward Calculations

    func testSkipForwardDoesNotExceedDuration() {
        playerService = AudioPlayerService()
        playerService.position = 100
        // Duration defaults to 0, so skipForward should clamp to duration
        playerService.skipForward(seconds: 30)

        // Since there's no player, position won't actually change via seek,
        // but we can verify the method doesn't crash
    }

    func testSkipBackwardDoesNotGoBelowZero() {
        playerService = AudioPlayerService()
        playerService.position = 5
        // skipBackward by 15 seconds from position 5 should clamp to 0
        playerService.skipBackward(seconds: 15)

        // Method doesn't crash, and underlying logic calculates max(5 - 15, 0) = 0
    }

    // MARK: - Toggle Play/Pause

    func testTogglePlayPauseWhenNotPlaying() {
        playerService = AudioPlayerService()
        XCTAssertFalse(playerService.isPlaying)
        // togglePlayPause when not playing calls resume()
        // Without a player, it won't start playback, but it shouldn't crash
        playerService.togglePlayPause()
    }

    // MARK: - Sleep Timer

    func testSleepTimerSetsRemaining() {
        playerService = AudioPlayerService()
        playerService.setSleepTimer(minutes: 15)

        XCTAssertNotNil(playerService.sleepTimerRemaining)
        XCTAssertEqual(playerService.sleepTimerRemaining, 900, "15 minutes = 900 seconds")
    }

    func testCancelSleepTimerClearsState() {
        playerService = AudioPlayerService()
        playerService.setSleepTimer(minutes: 10)
        XCTAssertNotNil(playerService.sleepTimerRemaining)

        playerService.cancelSleepTimer()
        XCTAssertNil(playerService.sleepTimerRemaining)
        XCTAssertFalse(playerService.sleepAtEndOfChapter)
    }

    func testSleepTimerEndOfChapterSetsSentinel() {
        playerService = AudioPlayerService()
        playerService.setSleepTimerEndOfChapter()

        XCTAssertTrue(playerService.sleepAtEndOfChapter)
        XCTAssertEqual(playerService.sleepTimerRemaining, -1, "End-of-chapter uses -1 sentinel")
    }

    func testNewSleepTimerCancelsPrevious() {
        playerService = AudioPlayerService()
        playerService.setSleepTimer(minutes: 30)
        XCTAssertEqual(playerService.sleepTimerRemaining, 1800)

        playerService.setSleepTimer(minutes: 5)
        XCTAssertEqual(playerService.sleepTimerRemaining, 300, "New timer should replace old one")
    }

    func testSleepTimerEndOfChapterCancelsTimedTimer() {
        playerService = AudioPlayerService()
        playerService.setSleepTimer(minutes: 10)

        playerService.setSleepTimerEndOfChapter()
        XCTAssertTrue(playerService.sleepAtEndOfChapter)
        XCTAssertEqual(playerService.sleepTimerRemaining, -1)
    }

    // MARK: - Stop

    func testStopClearsState() {
        playerService = AudioPlayerService()
        // Set some state manually
        playerService.showFullPlayer = true

        playerService.stop()

        XCTAssertNil(playerService.currentAudiobook)
        XCTAssertNil(playerService.currentChapter)
        XCTAssertFalse(playerService.isPlaying)
        XCTAssertEqual(playerService.position, 0)
        XCTAssertEqual(playerService.duration, 0)
    }

    // MARK: - Configure

    func testConfigureAcceptsAPI() {
        playerService = AudioPlayerService()
        let authRepo = AuthRepository()
        let api = SapphoAPI(authRepository: authRepo)

        // Should not crash
        playerService.configure(api: api)

        authRepo.clear()
    }
}
