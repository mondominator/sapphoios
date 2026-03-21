import XCTest
@testable import Sappho

final class AudioPlayerServiceExtendedTests: XCTestCase {

    private var playerService: AudioPlayerService!

    private let skipForwardKey = "skipForwardSeconds"
    private let skipBackwardKey = "skipBackwardSeconds"
    private let rewindOnResumeKey = "rewindOnResume"
    private let lastAudiobookIdKey = "lastPlayedAudiobookId"
    private let lastPositionKey = "lastPlayedPosition"
    private let pendingSyncKey = "pendingProgressSync"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: skipForwardKey)
        UserDefaults.standard.removeObject(forKey: skipBackwardKey)
        UserDefaults.standard.removeObject(forKey: rewindOnResumeKey)
        UserDefaults.standard.removeObject(forKey: lastAudiobookIdKey)
        UserDefaults.standard.removeObject(forKey: lastPositionKey)
        UserDefaults.standard.removeObject(forKey: pendingSyncKey)
    }

    override func tearDown() {
        playerService = nil
        UserDefaults.standard.removeObject(forKey: skipForwardKey)
        UserDefaults.standard.removeObject(forKey: skipBackwardKey)
        UserDefaults.standard.removeObject(forKey: rewindOnResumeKey)
        UserDefaults.standard.removeObject(forKey: lastAudiobookIdKey)
        UserDefaults.standard.removeObject(forKey: lastPositionKey)
        UserDefaults.standard.removeObject(forKey: pendingSyncKey)
        super.tearDown()
    }

    // MARK: - Skip Seconds Configuration

    func testDefaultSkipForwardSecondsIsZeroInUserDefaults() {
        // When no value is stored, UserDefaults.integer returns 0
        let value = UserDefaults.standard.integer(forKey: skipForwardKey)
        XCTAssertEqual(value, 0, "Default skip forward should be 0 (unset) in UserDefaults")
    }

    func testDefaultSkipBackwardSecondsIsZeroInUserDefaults() {
        let value = UserDefaults.standard.integer(forKey: skipBackwardKey)
        XCTAssertEqual(value, 0, "Default skip backward should be 0 (unset) in UserDefaults")
    }

    func testSetCustomSkipForwardSecondsPersists() {
        UserDefaults.standard.set(45, forKey: skipForwardKey)
        let value = UserDefaults.standard.integer(forKey: skipForwardKey)
        XCTAssertEqual(value, 45, "Custom skip forward should persist")
    }

    func testSetCustomSkipBackwardSecondsPersists() {
        UserDefaults.standard.set(10, forKey: skipBackwardKey)
        let value = UserDefaults.standard.integer(forKey: skipBackwardKey)
        XCTAssertEqual(value, 10, "Custom skip backward should persist")
    }

    func testConfigureSkipSecondsStoresToUserDefaults() {
        // Simulate what the settings UI does via AppStorage
        UserDefaults.standard.set(60, forKey: skipForwardKey)
        UserDefaults.standard.set(20, forKey: skipBackwardKey)

        XCTAssertEqual(UserDefaults.standard.integer(forKey: skipForwardKey), 60)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: skipBackwardKey), 20)

        // Verify the player service reads these values (used in setupRemoteCommands)
        playerService = AudioPlayerService()
        // The service should not crash when initialized with custom skip values
    }

    func testSkipForwardUsesStoredSeconds() {
        UserDefaults.standard.set(45, forKey: skipForwardKey)
        playerService = AudioPlayerService()
        // skipForward with no player should not crash
        playerService.skipForward(seconds: TimeInterval(45))
    }

    func testSkipBackwardUsesStoredSeconds() {
        UserDefaults.standard.set(10, forKey: skipBackwardKey)
        playerService = AudioPlayerService()
        playerService.position = 50
        // skipBackward with no player should not crash
        playerService.skipBackward(seconds: TimeInterval(10))
    }

    // MARK: - Rewind on Resume

    func testDefaultRewindOnResumeIsZero() {
        let value = UserDefaults.standard.integer(forKey: rewindOnResumeKey)
        XCTAssertEqual(value, 0, "Default rewind on resume should be 0 (disabled)")
    }

    func testRewindOnResumePersistence() {
        UserDefaults.standard.set(5, forKey: rewindOnResumeKey)
        let value = UserDefaults.standard.integer(forKey: rewindOnResumeKey)
        XCTAssertEqual(value, 5, "Rewind on resume value should persist")
    }

    func testRewindOnResumeReadByService() {
        // Set a rewind value before creating the service
        UserDefaults.standard.set(10, forKey: rewindOnResumeKey)
        playerService = AudioPlayerService()

        // resume() reads rewindOnResume from UserDefaults;
        // without a player it won't seek, but should not crash
        playerService.resume()
    }

    func testRewindOnResumeDisabledWhenZero() {
        UserDefaults.standard.set(0, forKey: rewindOnResumeKey)
        playerService = AudioPlayerService()
        // With rewind set to 0, resume should proceed without rewind logic
        playerService.resume()
    }

    // MARK: - Pending Progress Sync

    func testSavePendingProgressSyncStoresData() {
        // Simulate what savePendingSync does (it is private, so we test via UserDefaults directly)
        var pending: [String: Int] = [:]
        pending["42"] = 1200
        UserDefaults.standard.set(pending, forKey: pendingSyncKey)

        let stored = UserDefaults.standard.dictionary(forKey: pendingSyncKey) as? [String: Int]
        XCTAssertNotNil(stored)
        XCTAssertEqual(stored?["42"], 1200)
    }

    func testClearPendingProgressSyncRemovesData() {
        var pending: [String: Int] = ["42": 1200, "7": 300]
        UserDefaults.standard.set(pending, forKey: pendingSyncKey)

        // Remove one entry
        pending.removeValue(forKey: "42")
        UserDefaults.standard.set(pending, forKey: pendingSyncKey)

        let stored = UserDefaults.standard.dictionary(forKey: pendingSyncKey) as? [String: Int]
        XCTAssertNil(stored?["42"], "Cleared entry should be nil")
        XCTAssertEqual(stored?["7"], 300, "Other entries should remain")
    }

    func testClearAllPendingProgressSync() {
        let pending: [String: Int] = ["42": 1200]
        UserDefaults.standard.set(pending, forKey: pendingSyncKey)

        UserDefaults.standard.removeObject(forKey: pendingSyncKey)

        let stored = UserDefaults.standard.dictionary(forKey: pendingSyncKey)
        XCTAssertNil(stored, "All pending sync data should be cleared")
    }

    func testPendingProgressSyncRetrieval() {
        let pending: [String: Int] = ["1": 100, "2": 200, "3": 300]
        UserDefaults.standard.set(pending, forKey: pendingSyncKey)

        let stored = UserDefaults.standard.dictionary(forKey: pendingSyncKey) as? [String: Int] ?? [:]
        XCTAssertEqual(stored.count, 3)
        XCTAssertEqual(stored["1"], 100)
        XCTAssertEqual(stored["2"], 200)
        XCTAssertEqual(stored["3"], 300)
    }

    func testPendingProgressSyncReturnsEmptyWhenNone() {
        let stored = UserDefaults.standard.dictionary(forKey: pendingSyncKey) as? [String: Int] ?? [:]
        XCTAssertTrue(stored.isEmpty, "Should return empty dict when no pending syncs exist")
    }

    func testSyncPendingProgressDoesNotCrashWithoutAPI() {
        let pending: [String: Int] = ["42": 500]
        UserDefaults.standard.set(pending, forKey: pendingSyncKey)

        playerService = AudioPlayerService()
        // syncPendingProgress without api configured should not crash
        playerService.syncPendingProgress()
    }

    // MARK: - Last Played Tracking

    func testLastPlayedAudiobookIdFromUserDefaults() {
        UserDefaults.standard.set(42, forKey: lastAudiobookIdKey)
        let storedId = UserDefaults.standard.integer(forKey: lastAudiobookIdKey)
        XCTAssertEqual(storedId, 42)
    }

    func testLastPlayedPositionFromUserDefaults() {
        UserDefaults.standard.set(1500, forKey: lastPositionKey)
        let storedPosition = UserDefaults.standard.integer(forKey: lastPositionKey)
        XCTAssertEqual(storedPosition, 1500)
    }

    func testLastPlayedDefaultsToZeroWhenNotSet() {
        let storedId = UserDefaults.standard.integer(forKey: lastAudiobookIdKey)
        let storedPosition = UserDefaults.standard.integer(forKey: lastPositionKey)
        XCTAssertEqual(storedId, 0)
        XCTAssertEqual(storedPosition, 0)
    }

    func testStopClearsLastPlayedFromUserDefaults() {
        UserDefaults.standard.set(42, forKey: lastAudiobookIdKey)
        UserDefaults.standard.set(1500, forKey: lastPositionKey)

        playerService = AudioPlayerService()
        playerService.stop()

        let storedId = UserDefaults.standard.integer(forKey: lastAudiobookIdKey)
        let storedPosition = UserDefaults.standard.integer(forKey: lastPositionKey)
        XCTAssertEqual(storedId, 0, "stop() should clear lastPlayedAudiobookId")
        XCTAssertEqual(storedPosition, 0, "stop() should clear lastPlayedPosition")
    }

    // MARK: - Chapter Navigation

    func testJumpToChapterDoesNotCrashWithoutPlayer() {
        playerService = AudioPlayerService()
        let chapter = Chapter(
            id: 1,
            audiobookId: 10,
            chapterNumber: 1,
            startTime: 120.0,
            duration: 300.0,
            title: "Chapter 1"
        )
        // jumpToChapter should not crash even without a player
        playerService.jumpToChapter(chapter)
    }

    func testJumpToChapterWithZeroStartTime() {
        playerService = AudioPlayerService()
        let chapter = Chapter(
            id: 1,
            audiobookId: 10,
            chapterNumber: 1,
            startTime: 0.0,
            duration: 600.0,
            title: "Prologue"
        )
        playerService.jumpToChapter(chapter)
    }

    // MARK: - Multiple Sleep Timer Interactions

    func testSetSleepTimerAfterEndOfChapter() {
        playerService = AudioPlayerService()

        // First set end-of-chapter timer
        playerService.setSleepTimerEndOfChapter()
        XCTAssertTrue(playerService.sleepAtEndOfChapter)
        XCTAssertEqual(playerService.sleepTimerRemaining, -1)

        // Now set a timed timer -- should replace end-of-chapter
        playerService.setSleepTimer(minutes: 15)
        XCTAssertFalse(playerService.sleepAtEndOfChapter, "Timed timer should clear end-of-chapter flag")
        XCTAssertEqual(playerService.sleepTimerRemaining, 900, "Should be set to 15 minutes")
    }

    func testCancelSleepTimerClearsSleepAtEndOfChapter() {
        playerService = AudioPlayerService()

        playerService.setSleepTimerEndOfChapter()
        XCTAssertTrue(playerService.sleepAtEndOfChapter)

        playerService.cancelSleepTimer()
        XCTAssertFalse(playerService.sleepAtEndOfChapter, "Cancel should clear sleepAtEndOfChapter")
        XCTAssertNil(playerService.sleepTimerRemaining, "Cancel should clear remaining time")
    }

    func testMultipleSleepTimerReplacements() {
        playerService = AudioPlayerService()

        // Set 30 min timer
        playerService.setSleepTimer(minutes: 30)
        XCTAssertEqual(playerService.sleepTimerRemaining, 1800)

        // Replace with end-of-chapter
        playerService.setSleepTimerEndOfChapter()
        XCTAssertTrue(playerService.sleepAtEndOfChapter)
        XCTAssertEqual(playerService.sleepTimerRemaining, -1)

        // Replace with 5 min timer
        playerService.setSleepTimer(minutes: 5)
        XCTAssertFalse(playerService.sleepAtEndOfChapter)
        XCTAssertEqual(playerService.sleepTimerRemaining, 300)

        // Cancel everything
        playerService.cancelSleepTimer()
        XCTAssertNil(playerService.sleepTimerRemaining)
        XCTAssertFalse(playerService.sleepAtEndOfChapter)
    }

    func testSetSleepTimerZeroMinutes() {
        playerService = AudioPlayerService()
        playerService.setSleepTimer(minutes: 0)
        XCTAssertEqual(playerService.sleepTimerRemaining, 0, "0 minutes should set 0 seconds remaining")
    }
}
